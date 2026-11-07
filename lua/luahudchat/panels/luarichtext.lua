local DRAW_CLICK_PANELS = false

local DRAW_OFFSET_X = 3
local DRAW_OFFSET_Y = 1
local MAX_BUFFER_SIZE = 999999

do
	---@class LuaClickPanel: Panel
	local PANEL = {}

	PANEL._viewIndex = 0
	PANEL._textIndex = 0

	function PANEL:Init()
		--self:AddActionSignalTarget(self:GetParent())

		self:SetCursor("hand")

		self:SetPaintBackgroundEnabled(false)
	end

	---@param linkStartIndex integer
	---@param viewStartIndex integer
	function PANEL:SetTextIndex(linkStartIndex, viewStartIndex)
		self._textIndex = linkStartIndex
		self._viewIndex = viewStartIndex
	end

	if DRAW_CLICK_PANELS then
		function PANEL:Paint(w, h)
			surface.SetDrawColor(255, 0, 0, 255)
			surface.DrawOutlinedRect(0, 0, w, h)
		end
	end

	function PANEL:GetTextIndex()
		return self._textIndex
	end

	function PANEL:GetViewTextIndex()
		return self._viewIndex
	end

	function PANEL:OnMousePressed(code)
		if code == MOUSE_LEFT then
			local parent = self:GetParent()
			if parent:IsValid() then
				parent:OnClickPanel(self._textIndex)
			end
		else
			local parent = self:GetParent()
			if parent:IsValid() then
				parent:OnMousePressed(code)
			end
		end
	end

	vgui.Register("LuaClickPanel", PANEL, "EditablePanel")
end

do
	---@class LuaRichTextInterior: Panel
	local PANEL = {}

	function PANEL:Init()
		self:SetKeyboardInputEnabled(false)
		self:SetMouseInputEnabled(false)
		self:SetPaintBackgroundEnabled(false)
		self.m_pRichText = self:GetParent()
	end

	vgui.Register("LuaRichTextInterior", PANEL, "EditablePanel")
end

do
	local function iscntrl(char)
		local byte = string.byte(char)
		if (byte >= 0 and byte <= 31) or byte == 127 then
			return true
		end

		return false
	end
	local function isspace(char)
		local byte = string.byte(char)
		if (byte >= 9 and byte <= 13) or byte == 32 then
			return true
		end

		return false
	end

	_G.LuaRichTextMatCache = _G.LuaRichTextMatCache or {}

	---@class LuaRichText: Panel
	local PANEL = {}
	---@class Panel
	local BaseClass = FindMetaTable("Panel")

	---@class TFade
	---@field flFadeStartTime number
	---@field flFadeLength number
	---@field flFadeSustain number
	---@field iOriginalAlpha integer

	---@class TFormatStream
	---@field color Color
	---@field pixelsIndent integer
	---@field textClickable boolean
	---@field m_sClickableTextAction string
	---@field fade TFade
	---@field textStreamIndex integer

	---@class ImageComponent
	---@field width integer
	---@field texture string
	---@field alias boolean
	---@field text string

	PANEL.m_bResetFades = false
	PANEL.m_bInteractive = false
	PANEL.m_bUnusedScrollbarInvis = false
	PANEL.m_bAllTextAlphaIsZero = false

	---the text in the text window is stored in this buffer
	---@type (string|ImageComponent)[]
	PANEL.m_TextStream = {}
	---an array that holds the index in the buffer to wrap lines at
	---@type integer[]
	PANEL.m_LineBreaks = {}
	---list of format changes
	---@type TFormatStream[]
	PANEL.m_FormatStream = {}

	PANEL.m_bRecalcLineBreaks = false

	---tells next linebreakindex index to Start recalculating line breaks
	PANEL._recalculateBreaksIndex = 1
	PANEL._invalidateVerticalScrollbarSlider = false
	---the position in the text buffer of the blinking cursor
	PANEL._cursorPos = 1
	---whether we are highlighting text or not (selecting text)
	PANEL._mouseSelection = false
	---tells weather mouse is outside window and button is down so we select text
	PANEL._mouseDragSelection = false
	---select[2] is the offset in the text to where the cursor is currently
	---select[1] is the offset to where the cursor was dragged to. or -1 if no drag.
	---@type integer[]
	PANEL._select = { 0, 0 }
	PANEL._pixelsIndent = 0
	---max number of chars that can be in the text buffer
	PANEL._maxCharCount = 0
	---font of chars in the text buffer
	PANEL._font = ""
	PANEL.m_hFontUnderline = ""
	PANEL._selectionColor = Color(255, 255, 255)
	---color of the highlighted text
	PANEL._selectionTextColor = Color(255, 255, 255)
	PANEL._currentTextClickable = false
	---@type LuaClickPanel[]
	PANEL._clickableTextPanels = {}
	PANEL._clickableTextIndex = 0
	PANEL._defaultTextColor = Color(255, 255, 255)
	PANEL._drawOffsetX = 0
	PANEL._drawOffsetY = 0

	---@type LuaRichTextInterior
	PANEL.m_pInterior = NULL
	---@type Panel
	PANEL.m_hPanelToHandleClickingURLs = NULL

	---cut/copy/paste popup
	---@type DMenu
	PANEL.m_pEditMenu = NULL

	PANEL.m_pszInitialText = ""

	---saved state
	PANEL._recalcSavedRenderState = false

	---@class TRenderState
	---@field x integer
	---@field y integer
	---@field textColor Color
	---@field pixelsIndent integer
	---@field textClickable boolean
	---@field formatStreamIndex integer

	---@type TRenderState
	PANEL.m_CachedRenderState = {}

	PANEL._bgColor = Color(255, 255, 255)
	PANEL._fgColor = Color(255, 255, 255)
	PANEL._paintBg = true

	local function ScrollPanelButton_OnMousePressed(btn, mousecode)
		if not btn:IsEnabled() then return end

		btn:MouseCapture(true)
		btn.Depressed = true
		btn:OnDepressed()
		btn:InvalidateLayout(true)
	end
	local function ScrollPanelButton_Paint(btn, w,h)
		local bgColor
		local borderName = "ScrollBarButtonBorder"
		if btn:IsDown() then
			bgColor = LuaHudChat.GetSchemeColor("ScrollBarButton.DepressedBgColor", Color(0,0,0,0))
			borderName = "ScrollBarButtonDepressedBorder"
		elseif btn:IsHovered() then
			bgColor = LuaHudChat.GetSchemeColor("ScrollBarButton.ArmedBgColor", Color(0,0,0,0))
		else
			bgColor = LuaHudChat.GetSchemeColor("ScrollBarButton.BgColor", Color(0,0,0,0))
		end

		surface.SetDrawColor(bgColor)
		surface.DrawRect(0, 0, w, h)
		LuaHudChat.PaintBorder(borderName, 0,0, w,h)
	end
	local function ScrollPanelGrip_Paint(btn, w,h)
		local bgColor = LuaHudChat.GetSchemeColor("ScrollBarSlider.FgColor", Color(0,0,0,0))
		surface.SetDrawColor(bgColor)
		surface.DrawRect(0, 0, w, h)

		if LuaHudChat.Borders["ScrollBarSliderBorder"] then
			LuaHudChat.PaintBorder("ScrollBarSliderBorder", 0,0, w,h)
		else
			local borderName = LuaHudChat.SchemeBorders:GetString("ButtonBorder", "RaisedBorder")
			LuaHudChat.PaintBorder(borderName, 0,0, w,h)
		end
	end
	local function ScrollPanel_PerformLayout(self)
		local Wide = self:GetWide()
		local BtnHeight = Wide
		if self:GetHideButtons() then BtnHeight = 0 end
		local Scroll = self:GetScroll() / self.CanvasSize
		local BarSize = math.max( self:BarScale() * ( self:GetTall() - ( BtnHeight * 2 ) ), BtnHeight )
		local Track = self:GetTall() - ( BtnHeight * 2 ) - BarSize
		Track = Track + 1

		Scroll = Scroll * Track

		self.btnGrip:SetPos( 0, BtnHeight + Scroll )
		self.btnGrip:SetSize( Wide, BarSize )

		if ( BtnHeight > 0 ) then
			self.btnUp:SetPos( 0, 0 )
			self.btnUp:SetSize( Wide, BtnHeight )

			self.btnDown:SetPos( 0, self:GetTall() - BtnHeight )
			self.btnDown:SetSize( Wide, BtnHeight )
		else
			self.btnDown:SetSize( Wide, BtnHeight )
			self.btnUp:SetSize( Wide, BtnHeight )
		end
	end

	-- scroll bar will scroll a little, then continuous scroll like in windows
	local SCROLL_BAR_DELAY = 0.400	-- default delay for all scroll bars
	local SCROLL_BAR_SPEED = 0.050	-- this is how fast the bar scrolls when you hold down the arrow button

	function PANEL:Init()
		do
			self.m_bResetFades = false
			self.m_bInteractive = false
			self.m_bUnusedScrollbarInvis = false
			self.m_bAllTextAlphaIsZero = false

			self.m_TextStream = {}
			self.m_LineBreaks = {}
			self.m_FormatStream = {}

			self.m_bRecalcLineBreaks = false

			self._recalculateBreaksIndex = 1
			self._invalidateVerticalScrollbarSlider = false
			self._cursorPos = 1
			self._mouseSelection = false
			self._mouseDragSelection = false
			self._select = { 0, 0 }
			self._pixelsIndent = 0
			self._maxCharCount = 0
			self._font = ""
			self.m_hFontUnderline = ""
			self._selectionColor = Color(255, 255, 255)
			self._selectionTextColor = Color(255, 255, 255)
			self._currentTextClickable = false
			self._clickableTextPanels = {}
			self._clickableTextIndex = 0
			self._defaultTextColor = Color(255, 255, 255)
			self._drawOffsetX = 0
			self._drawOffsetY = 0

			self.m_pInterior = NULL
			self.m_hPanelToHandleClickingURLs = NULL

			self.m_pEditMenu = NULL

			self.m_pszInitialText = ""

			self._recalcSavedRenderState = false

			self.m_CachedRenderState = {
				x = 0,
				y = 0,
				textColor = Color(255, 255, 255),
				pixelsIndent = 0,
				textClickable = false,
				formatStreamIndex = 1,
			}

			self._bgColor = Color(255, 255, 255)
			self._fgColor = Color(255, 255, 255)
			self._paintBg = true
		end

		self.m_bAllTextAlphaIsZero = false
		self._font = "Default"
		self.m_hFontUnderline = "DefaultUnderline"

		self.m_bRecalcLineBreaks = true
		self.m_pszInitialText = ""
		self._cursorPos = 1
		self._mouseSelection = false
		self._mouseDragSelection = false


		local scrollbar = vgui.Create("DVScrollBar", self, "ScrollBar")
		self._vertScrollBar = scrollbar
		scrollbar:SetWide(ScreenScaleH(LuaHudChat.SchemeBaseSettings:GetInt("ScrollBar.Wide", 17)))

		scrollbar.btnUp:SetCursor("arrow")
		scrollbar.btnDown:SetCursor("arrow")

		scrollbar.btnUp.DoClick = function()end
		scrollbar.btnDown.DoClick = function()end

		scrollbar.btnUp.OnMousePressed = ScrollPanelButton_OnMousePressed
		scrollbar.btnDown.OnMousePressed = ScrollPanelButton_OnMousePressed
		scrollbar.btnUp.Paint = ScrollPanelButton_Paint
		scrollbar.btnDown.Paint = ScrollPanelButton_Paint
		scrollbar.btnGrip.Paint = ScrollPanelGrip_Paint
		scrollbar.Paint = function(scroll, w,h)
			local bgColor = LuaHudChat.GetSchemeColor("ScrollBarSlider.BgColor", Color(255, 255, 255))
			surface.SetDrawColor(bgColor)

			local btnUpTall = scroll.btnUp:GetTall()
			surface.DrawRect(0, btnUpTall, w, h - scroll.btnDown:GetTall() - btnUpTall)
		end
		scrollbar.PerformLayout = ScrollPanel_PerformLayout

		scrollbar.btnUp:SetFont("Marlett")
		scrollbar.btnUp:SetText("t")
		scrollbar.btnUp:SetTextColor(LuaHudChat.GetSchemeColor("ScrollBarButton.FgColor", Color(255, 255, 255)))
		scrollbar.btnDown:SetFont("Marlett")
		scrollbar.btnDown:SetText("u")
		scrollbar.btnDown:SetTextColor(LuaHudChat.GetSchemeColor("ScrollBarButton.FgColor", Color(255, 255, 255)))

		scrollbar.Think = function(scroll)
			local direction = 0

			if scroll.btnUp:IsDown() then -- top button is down
				direction = -1
			elseif scroll.btnDown:IsDown() then -- bottom button is down
				direction = 1
			end

			if direction ~= 0 then -- a button is down
				if scroll._respond then
					local newValue = math.Clamp(math.floor(scroll:GetScroll() + (direction * (self:GetLineHeight()+1))), 0, scroll.CanvasSize)
					scroll:AddScroll(direction)
					--scroll:SetScroll(newValue)
					self._recalcSavedRenderState = true
				end

				if (scroll._scrollDelay or 0) < SysTime() then
					scroll._scrollDelay = SysTime() + SCROLL_BAR_SPEED
					scroll._respond = true
				else
					scroll._respond = false
				end
			else -- a button is not down
				-- if neither button is down keep delay at max
				scroll._scrollDelay = SysTime() + SCROLL_BAR_DELAY
				scroll._respond = true
			end
		end

		--scrollbar:SetVisible(false)
		--scrollbar:AddActionSignalTarget(self)
		scrollbar.OnMouseWheeled = function(scroll, delta)
			if scroll:IsVisible() then
				local val = scroll:GetScroll()
				val = val - delta
				scroll:SetScroll(val)
				self._recalcSavedRenderState = true
			end
		end
		scrollbar.OnCursorMoved = function(scroll, lx, ly)
			if not (scroll.Enabled and scroll.Dragging) then return end

			local richtext = scroll:GetParent()

			local x, y = scroll:ScreenToLocal(0, gui.MouseY())
			y = y - scroll.btnUp:GetTall() - scroll.HoldPos

			local btnHeight = scroll:GetWide()
			if scroll:GetHideButtons() then btnHeight = 0 end

			local trackSize = scroll:GetTall() - btnHeight * 2 - scroll.btnGrip:GetTall()
			y = y / trackSize

			scroll:SetScroll(math.SnapTo(y * scroll.CanvasSize, richtext:GetLineHeight()))
		end

		self._recalcSavedRenderState = true
		self._maxCharCount = 65536
		--self:AddActionSignalTarget(self)
		self.m_pInterior = vgui.Create("LuaRichTextInterior", self)

		-- a 0 for _select[1] means that the selection is empty
		self._select = { 0, 0 }
		self.m_pEditMenu = NULL

		self:SetCursor("beam")

		-- position the cursor so it is at the end of the text
		self:GotoTextEnd()

		-- set default foreground color to black
		self._defaultTextColor:SetUnpacked(0, 0, 0, 0)

		-- initialize the line break array
		self:InvalidateLineBreakStream()

		if --[[self:IsProportional()]] true then
			self._drawOffsetX = ScreenScale(DRAW_OFFSET_X)
			self._drawOffsetY = ScreenScale(DRAW_OFFSET_Y)
		else
			self._drawOffsetX = DRAW_OFFSET_X
			self._drawOffsetY = DRAW_OFFSET_Y
		end

		-- add a basic format string
		---@class TFormatStream
		local stream = {
			color = self._defaultTextColor,
			fade = {
				flFadeStartTime = 0,
				flFadeLength = -1,
				flFadeSustain = 0,
				iOriginalAlpha = 0,
			},
			pixelsIndent = 0,
			textStreamIndex = 1,
			textClickable = false,
		}
		self.m_FormatStream = { stream }

		self.m_bResetFades = false
		self.m_bInteractive = true
		self.m_bUnusedScrollbarInvis = false
	end

	---@param x integer
	---@param y integer
	function PANEL:SetDrawOffsets(x, y)
		self._drawOffsetX = x
		self._drawOffsetY = y
	end

	---sets it as drawing text only - used for embedded RichText control into other text drawing situations
	function PANEL:SetDrawTextOnly()
		self:SetDrawOffsets(0, 0)
		self:SetPaintBackgroundEnabled(false)
		self.m_pInterior:SetVisible(false)
		self:SetVerticalScrollbarEnabled(false)
	end

	---configures colors
	function PANEL:ApplySchemeSettings()
		self._font = "Default"
		self.m_hFontUnderline = "DefaultUnderline"

		-- FIXME: parse scheme file
		self:SetFGColor(221, 221, 221, 255)                    -- RichText.TextColor = Offwhite
		self:SetBGColor(0, 0, 0, 128)                          -- RichText.BgColor = TransparentBlack
		self._selectionTextColor:SetUnpacked(255, 255, 255, 255) -- RichText.SelectedTextColor = White
		self._selectionColor:SetUnpacked(0, 168, 255, 204)     -- RichText.SelectedBgColor = "0 168 255 204"

		--if #pScheme:GetString("RichText.InsetX") > 0 then
		--	self:SetDrawOffsets(pScheme:GetInt("RichText.InsetX"), pScheme:GetInt("RichText.InsetY"))
		--end
	end

	---if the default format color isn't set then set it
	---@param r Color|integer
	---@param g integer
	---@param b integer
	---@param a integer
	function PANEL:SetFGColor(r, g, b, a)
		local color
		if IsColor(r) then
			color = r --[[@as Color]]
			r, g, b, a = color:Unpack()
		else
			color = Color(r --[[@as integer]], g, b, a)
		end
		-- Replace default format color if the stream is empty and the color is the default ( or the previous FgColor )
		if #self.m_FormatStream == 1 and
				(self.m_FormatStream[1].color == self._defaultTextColor or self.m_FormatStream[1].color == self._fgColor) then
			self.m_FormatStream[1].color = color
		end

		self._fgColor:SetUnpacked(r --[[@as integer]], g, b, a)
	end

	---@return Color
	function PANEL:GetFGColor()
		return self._fgColor
	end

	---@param r Color|integer
	---@param g integer
	---@param b integer
	---@param a integer
	function PANEL:SetBGColor(r, g, b, a)
		if IsColor(r) then
			local color = r --[[@as Color]]
			r, g, b, a = color:Unpack()
		end

		self._bgColor:SetUnpacked(r --[[@as integer]], g, b, a)
	end

	---@return Color
	function PANEL:GetBGColor()
		return self._bgColor
	end

	---@param state boolean
	function PANEL:SetPaintBackgroundEnabled(state)
		self._paintBg = state
	end

	---Sends a message if the data has changed
	---Turns off any selected text in the window if we are not using the edit menu
	---@param gained boolean
	function PANEL:OnFocusedChanged(gained)
		if gained == true then return end -- we're only OnKillFocus

		-- check if we clicked the right mouse button or if it is down
		local mouseRightClicked = input.WasMousePressed(MOUSE_RIGHT)
		local mouseRightUp = input.WasMouseReleased(MOUSE_RIGHT)
		local mouseRightDown = input.IsMouseDown(MOUSE_RIGHT)

		if mouseRightClicked or mouseRightDown or mouseRightUp then
			local start, endpos = self:GetSelectedTextRange()
			if start then
				local startX, startY = self:CursorToPixelSpace(start)
				local endX, endY = self:CursorToPixelSpace(endpos)
				local cursorX, cursorY = self:ScreenToLocal(input.GetCursorPos())

				-- check the area vertically, we need to handle the horizontal edge cases eventually
				local fontTall = self:GetLineHeight()
				endY = endY + fontTall

				if startY < cursorY and endY > cursorY then
					-- if we clicked in the selection area, leave the text highlighted
					return
				end
			end
		end

		-- clear any selection
		self:SelectNone()
	end

	---Wipe line breaks after the size of a panel has been changed
	---@param w integer
	---@param h integer
	function PANEL:OnSizeChanged(w, h)
		-- blow away the line breaks list
		self._invalidateVerticalScrollbarSlider = true
		self:InvalidateLineBreakStream()
		self:InvalidateLayout()

		if self._vertScrollBar:IsVisible() then
			--self._vertScrollBar:MakeReadyForUse()
			self.m_pInterior:SetSize(w - self._vertScrollBar:GetWide(), h)
		else
			self.m_pInterior:SetSize(w, h)
		end
	end

	---Set the text array
	---Using this function will cause all lineBreaks to be discarded.
	---This is because this fxn replaces the contents of the text buffer.
	---For modifying large buffers use insert functions.
	---@param text string
	function PANEL:SetText(text)
		if not text then text = "" end

		if text:sub(1, 1) == "#" then
			text = language.GetPhrase(text)
		end

		-- reset the formatting stream
		---@class TFormatStream
		local stream = {
			color = self:GetFGColor(),
			fade = {
				flFadeStartTime = 0,
				flFadeLength = -1,
				flFadeSustain = 0,
				iOriginalAlpha = 0,
			},
			pixelsIndent = 0,
			textStreamIndex = 1,
			textClickable = false,
		}
		self.m_FormatStream = { stream }

		-- set the new text stream
		self.m_TextStream = {}
		for i = 1, utf8.len(text) do
			table.insert(self.m_TextStream, utf8.GetChar(text, i))
		end

		self:GotoTextStart()
		self:SelectNone()

		-- blow away the line breaks list
		self:InvalidateLineBreakStream()
		self:InvalidateLayout()
	end

	---Given cursor's position in the text buffer, convert it to the local window's x and y pixel coordinates
	---@param cursorPos integer cursor index
	---@return integer cx the corresponding coords in the local window
	---@return integer cy the corresponding coords in the local window
	function PANEL:CursorToPixelSpace(cursorPos)
		local yStart = self._drawOffsetY
		local x, y = self._drawOffsetX, yStart
		self._pixelsIndent = 0
		local lineBreakIndexIndex = 1

		local i = 1
		i, lineBreakIndexIndex = self:GetStartDrawIndex(lineBreakIndexIndex)
		while i <= #self.m_TextStream do
			i, lineBreakIndexIndex = self:GetStartDrawIndex(lineBreakIndexIndex)

			local ch = self.m_TextStream[i]

			-- if we've found the position, break
			if cursorPos == i then
				-- if we've passed a line break go to that
				if self.m_LineBreaks[lineBreakIndexIndex] == i then
					-- add another line
					x, y = self:AddAnotherLine(x, y)
					lineBreakIndexIndex = lineBreakIndexIndex + 1
				end
				break
			end

			-- if we've passed a line break go to that
			if self.m_LineBreaks[lineBreakIndexIndex] == i then
				-- add another line
				x, y = self:AddAnotherLine(x, y)
				lineBreakIndexIndex = lineBreakIndexIndex + 1
			end

			-- add to the current position
			if istable(ch) then
				x = x + ch.width
			else
				surface.SetFont(self._font)
				x = x + surface.GetTextSize(ch)
			end
		end

		return x, y
	end

	---Converts local pixel coordinates to an index in the text buffer
	---@param cx integer
	---@param cy integer
	---@return integer
	function PANEL:PixelToCursorSpace(cx, cy)
		local fontTall = self:GetLineHeight()

		-- where to start reading
		local yStart = self._drawOffsetY
		local x, y = self._drawOffsetX, yStart
		self._pixelsIndent = 0
		local lineBreakIndexIndex = 1

		local startIndex
		startIndex, lineBreakIndexIndex = self:GetStartDrawIndex(lineBreakIndexIndex)
		if self._recalcSavedRenderState then
			self:RecalculateDefaultState(startIndex)
		end

		self._pixelsIndent = self.m_CachedRenderState.pixelsIndent
		self._currentTextClickable = self.m_CachedRenderState.textClickable
		local renderState = {}
		table.CopyFromTo(self.m_CachedRenderState, renderState)

		local onRightLine = false
		local i = startIndex

		if #self.m_TextStream == 0 then return i end

		while i <= #self.m_TextStream do
			local ch = self.m_TextStream[i]

			renderState.x = x
			if self:UpdateRenderState(i, renderState) then
				x = renderState.x
			end

			-- if we are on the right line but off the end of if put the cursor at the end of the line
			if self.m_LineBreaks[lineBreakIndexIndex] == i then
				-- add another line
				x, y = self:AddAnotherLine(x, y)
				lineBreakIndexIndex = lineBreakIndexIndex + 1

				if onRightLine then break end
			end

			-- check to see if we're on the right line
			if cy < yStart then
				-- cursor is above panel
				onRightLine = true
			elseif cy >= y and cy < (y + fontTall + self._drawOffsetY) then
				onRightLine = true
			end

			local wide = 0
			if istable(ch) then
				wide = ch.width
			else
				---@cast ch string
				surface.SetFont(self._font)
				wide = surface.GetTextSize(ch)
			end

			-- if we've found the position, break
			if onRightLine then
				if cx > self:GetWide() then
					-- off right side of window
				elseif cx < (self._drawOffsetX + renderState.pixelsIndent) or cy < yStart then -- off left side of window
					-- move cursor one to left
					return i
				end

				if cx >= x and cx < (x + wide) then
					-- check which side of the letter they're on
					if cx < (x + (wide * 0.5)) then
						-- left side
						return i
					else
						-- right side
						return i + 1
					end
				end
			end

			x = x + wide

			i = i + 1
		end

		return i
	end

	---Draws a string of characters in the panel
	---@param iFirst integer Index of the first character to draw
	---@param iLast integer Index of the last character to draw
	---@param renderState TRenderState Render state to use
	---@param font string font to use
	---@return number w width of the character drawn
	function PANEL:DrawString(iFirst, iLast, renderState, font)
		-- Calculate the render size
		surface.SetFont(font)
		local _, fontTall = surface.GetTextSize("W")
		-- This won't exactly match the rendered size
		local charWide = 0

		for i = iFirst, iLast do
			local ch = self.m_TextStream[i]
			if istable(ch) then
				charWide = charWide + ch.width
			else
				---@cast ch string
				charWide = charWide + surface.GetTextSize(ch)
			end
		end

		-- draw selection, if any
		local selection0, selection1 = self:GetSelectedTextRange()

		if iFirst >= selection0 and iFirst < selection1 then
			-- draw background selection color
			surface.SetDrawColor(self._selectionColor:Unpack())
			surface.DrawRect(renderState.x, renderState.y, charWide, 1 + fontTall)

			-- reset text color
			surface.SetTextColor(self._selectionTextColor:Unpack())
			self.m_bAllTextAlphaIsZero = false
		else
			surface.SetTextColor(renderState.textColor:Unpack())
		end

		if renderState.textColor.a ~= 0 then
			self.m_bAllTextAlphaIsZero = false
			surface.SetTextPos(renderState.x, renderState.y)
			--local str = table.concat(self.m_TextStream, "", iFirst, iLast)
			--surface.DrawText(str)
			for i = iFirst, iLast do
				local ch = self.m_TextStream[i]
				if istable(ch) then
					local x, y = surface.GetTextPos()

					local m = LuaRichTextMatCache[ch.texture]
					if not m then
						m = Material(ch.texture, ch.alias and "noclamp" or "noclamp smooth")
						LuaRichTextMatCache[ch.texture] = m
					end
					surface.SetMaterial(m)
					local a = surface.GetTextColor().a
					surface.SetDrawColor(255, 255, 255, a)
					surface.DrawTexturedRect(x, y + math.floor((self:GetLineHeight() / 2) - (ch.width / 2)), ch.width,
						ch.width)

					x = x + ch.width
					surface.SetTextPos(x, y)
				else
					---@cast ch string
					surface.DrawText(ch)
				end
			end
		end

		return charWide
	end

	---Finish drawing url
	---@param x integer
	---@param y integer
	function PANEL:FinishingURL(x, y)
		-- finishing URL
		local clickPanel = self._clickableTextPanels[self._clickableTextIndex]
		if clickPanel and clickPanel:IsValid() then
			local px, py = clickPanel:GetPos()
			local fontTall = self:GetLineHeight()
			clickPanel:SetSize(math.max(x - px, 6), y - py + fontTall)
			clickPanel:SetVisible(true)

			-- if we haven't actually advanced any, step back and ignore this one
			-- this is probably a data input problem though, need to find root cause
			if x - px <= 0 then
				self._clickableTextIndex = self._clickableTextIndex - 1
				clickPanel:SetVisible(false)
			end
		end
	end

	---@param renderState TRenderState
	function PANEL:CalculateFade(renderState)
		local stream = self.m_FormatStream[renderState.formatStreamIndex]
		if stream then
			if self.m_bResetFades == false then
				if stream.fade.flFadeLength ~= -1 then
					local frac = (stream.fade.flFadeStartTime - SysTime()) / stream.fade.flFadeLength

					local alpha = math.floor(frac * stream.fade.iOriginalAlpha)
					alpha = math.Clamp(alpha, 0, stream.fade.iOriginalAlpha)
					local col = renderState.textColor
					renderState.textColor = Color(col.r, col.g, col.b, alpha)
				end
			end
		end
	end

	---Draws the text in the panel
	---@param w integer
	---@param h integer
	function PANEL:Paint(w, h)
		if self._paintBg then
			surface.SetDrawColor(self._bgColor:Unpack())
			surface.DrawRect(0, 0, w, h)
		end

		-- Assume the worst
		self.m_bAllTextAlphaIsZero = true
		local hFontCurrent = self._font

		-- hide all the clickable panels until we know where they are to reside
		for _, pnl in ipairs(self._clickableTextPanels) do
			pnl:SetVisible(false)
		end

		if not self:HasText() then return end

		local lineBreakIndexIndex = 1
		local startIndex
		startIndex, lineBreakIndexIndex = self:GetStartDrawIndex(lineBreakIndexIndex)
		self._currentTextClickable = false

		self._clickableTextIndex = self:GetClickableTextIndexStart(startIndex)

		-- recalculate and cache the render state at the render start
		if self._recalcSavedRenderState then
			self:RecalculateDefaultState(startIndex)
		end
		-- copy off the cached render state
		local renderState = {}
		table.CopyFromTo(self.m_CachedRenderState, renderState)

		self._pixelsIndent = self.m_CachedRenderState.pixelsIndent
		self._currentTextClickable = self.m_CachedRenderState.textClickable

		renderState.textClickable = self._currentTextClickable

		local stream = self.m_FormatStream[renderState.formatStreamIndex]
		if stream then
			renderState.textColor = stream.color
		end

		self:CalculateFade(renderState)

		renderState.formatStreamIndex = renderState.formatStreamIndex + 1

		if self._currentTextClickable then
			self._clickableTextIndex = startIndex
		end

		-- where to start drawing
		renderState.x = self._drawOffsetX + self._pixelsIndent
		renderState.y = self._drawOffsetY

		-- draw the text
		local selection0, selection1 = self:GetSelectedTextRange()

		surface.SetFont(hFontCurrent)

		local i = startIndex
		while i <= #self.m_TextStream and renderState.y < h do
			-- 1. Update our current render state based on the formatting and color streams, this has to happen if it's our
			-- very first iteration or if we are actually changing state.
			local nXBeforeStateChange = renderState.x
			if self:UpdateRenderState(i, renderState) or i == startIndex then
				-- check for url state change
				if renderState.textClickable ~= self._currentTextClickable then
					if renderState.textClickable then
						-- entering new URL
						self._clickableTextIndex = self._clickableTextIndex + 1
						hFontCurrent = self.m_hFontUnderline
						surface.SetFont(hFontCurrent)

						local clickPanel = self._clickableTextPanels[self._clickableTextIndex] or NULL
						if clickPanel:IsValid() then
							clickPanel:SetPos(renderState.x, renderState.y)
						end
					else
						self:FinishingURL(nXBeforeStateChange, renderState.y)
						hFontCurrent = self._font
						surface.SetFont(hFontCurrent)
					end
					self._currentTextClickable = renderState.textClickable
				end
			end

			-- 2. if we've passed a line break go to that
			if self.m_LineBreaks[lineBreakIndexIndex] ~= nil and self.m_LineBreaks[lineBreakIndexIndex] <= i then
				if self._currentTextClickable then
					self:FinishingURL(renderState.x, renderState.y)
				end

				-- add another line
				renderState.x, renderState.y = self:AddAnotherLine(renderState.x, renderState.y)
				lineBreakIndexIndex = lineBreakIndexIndex + 1

				-- Skip white space unless the previous line ended from the hard carriage return
				if i and self.m_TextStream[i - 1] ~= "\n" and self.m_TextStream[i - 1] ~= "\r" then
					while self.m_TextStream[i] == " " do
						if i + 1 < #self.m_TextStream then
							i = i + 1
						else
							break
						end
					end
				end

				if renderState.textClickable then
					-- move to the next URL
					self._clickableTextIndex = self._clickableTextIndex + 1
					local clickPanel = self._clickableTextPanels[self._clickableTextIndex] or NULL
					if clickPanel:IsValid() then
						clickPanel:SetPos(renderState.x, renderState.y)
					end
				end
			end

			-- 3. Calculate the range of text to draw all at once
			local iLast = #self.m_TextStream + 1

			-- Stop at the next line break
			local lbreak = self.m_LineBreaks[lineBreakIndexIndex]
			if lbreak ~= nil and lbreak <= iLast then
				iLast = lbreak
			end

			-- Stop at the next format change
			local fstream = self.m_FormatStream[renderState.formatStreamIndex]
			if fstream ~= nil and fstream.textStreamIndex <= iLast then
				iLast = fstream.textStreamIndex
			end

			-- these two statements are missing from sdk2013 and 2017 leak, i found this in Source.NET lmao
			if i < selection0 and iLast >= selection0 then
				iLast = selection0
			end
			if i >= selection0 and i < selection1 and iLast >= selection1 then
				iLast = selection1
			end

			-- Handle non-drawing characters specially
			for iT = i, iLast do
				local c = self.m_TextStream[iT]
				if isstring(c) and iscntrl(c) then
					iLast = iT
					break
				end
			end

			-- 4. Draw the current text range
			if iLast <= i then
				if self.m_TextStream[i] == "\t" then
					local dxTabWidth = math.max(1, 8 * surface.GetTextSize(" "))

					renderState.x = dxTabWidth * (1 + (renderState.x / dxTabWidth))
				end
				i = i + 1
			else
				renderState.x = renderState.x + self:DrawString(i, iLast - 1, renderState, hFontCurrent)
				i = iLast
			end
		end

		if renderState.textClickable then
			self:FinishingURL(renderState.x, renderState.y)
		end

		--self:DrawDebug()
	end

	function PANEL:DrawDebug()
		local clip = DisableClipping(true)
		local w, h = self:GetSize()
		surface.SetTextColor(255, 0, 0, 255)
		surface.SetFont(self._font)

		local y = 0
		for i = 1, #self.m_FormatStream do
			local piece = self.m_FormatStream[i]
			surface.SetTextPos(w + 16, y * 16)
			surface.DrawText(string.format(
				"Format Stream #%d: Text[%d] Color %d, %d, %d, %d, PixelsIndent %d, Fade [Start %d, Sustain %d, Length %d, OriginalAlpha %d]",
				i, piece.textStreamIndex, piece.color.r, piece.color.g, piece.color.b, piece.color.a, piece.pixelsIndent,
				piece.fade.flFadeStartTime, piece.fade.flFadeSustain, piece.fade.flFadeLength, piece.fade.iOriginalAlpha
			))
			y = y + 1
		end
		y = y + 1
		for i = 1, #self.m_LineBreaks do
			local piece = self.m_LineBreaks[i]
			surface.SetTextPos(w + 16, y * 16)
			surface.DrawText(string.format("Line break #%d = %d", i, piece))
			y = y + 1
		end
		y = y + 1
		local x = 0
		local max = 8
		for i = 1, #self.m_TextStream do
			local ch = self.m_TextStream[i]
			surface.SetTextPos(w + 16 + (x * 48), y * 16)
			if istable(ch) then
				surface.DrawText("IM")
			else
				---@cast ch string
				if iscntrl(ch) then
					if ch == "\n" then
						surface.DrawText("\\n")
					else
						surface.DrawText("0x" .. string.byte(ch))
					end
				elseif isspace(ch) then
					surface.DrawText("WS")
				else
					surface.DrawText(ch)
				end
			end

			y = (x > max and y + 1 or y)
			x = (x > max and 0 or x + 1)
		end
		DisableClipping(clip)
	end

	---@param startIndex integer
	function PANEL:GetClickableTextIndexStart(startIndex)
		for i, pnl in ipairs(self._clickableTextPanels) do
			if pnl:GetViewTextIndex() >= startIndex then
				return i - 1
			end
		end
		return 0
	end

	---Recalcultes the formatting state from the specified index
	---@param startIndex integer
	function PANEL:RecalculateDefaultState(startIndex)
		if not self:HasText() then return end

		assert(startIndex <= #self.m_TextStream)

		self.m_CachedRenderState.textColor = self:GetFGColor()
		self._pixelsIndent = 0
		self._currentTextClickable = false
		self._clickableTextIndex = self:GetClickableTextIndexStart(startIndex)

		-- find where in the formatting stream we need to be
		self:GenerateRenderStateForTextStreamIndex(startIndex, self.m_CachedRenderState)
		self._recalcSavedRenderState = false
	end

	---updates a render state based on the formatting and color streams-
	---@param textStreamPos integer
	---@param renderState TRenderState
	---@return boolean changed if we changed the render state
	function PANEL:UpdateRenderState(textStreamPos, renderState)
		local stream = self.m_FormatStream[renderState.formatStreamIndex]
		if stream ~= nil and stream.textStreamIndex == textStreamPos then
			-- set the current formatting
			renderState.textColor = stream.color
			renderState.textClickable = stream.textClickable

			self:CalculateFade(renderState)

			local indentChange = stream.pixelsIndent - renderState.pixelsIndent
			renderState.pixelsIndent = stream.pixelsIndent

			if indentChange ~= 0 then
				renderState.x = renderState.pixelsIndent + self._drawOffsetX
			end

			self._pixelsIndent = renderState.pixelsIndent

			-- move to the next position in the color stream
			renderState.formatStreamIndex = renderState.formatStreamIndex + 1
			return true
		end

		return false
	end

	---Returns the index in the format stream for the specified text stream index
	---@param textStreamIndex integer
	function PANEL:FindFormatStreamIndexForTextStreamPos(textStreamIndex)
		local formatStreamIndex = 1
		while self.m_FormatStream[formatStreamIndex] do
			if self.m_FormatStream[formatStreamIndex].textStreamIndex > textStreamIndex then
				break
			end
			formatStreamIndex = formatStreamIndex + 1
		end

		-- step back to the color change before the new line
		formatStreamIndex = formatStreamIndex - 1
		if not self.m_FormatStream[formatStreamIndex] then
			formatStreamIndex = 1
		end
		return formatStreamIndex
	end

	---Generates a base renderstate given a index into the text stream
	---@param textStreamIndex integer
	---@param renderState TRenderState
	function PANEL:GenerateRenderStateForTextStreamIndex(textStreamIndex, renderState)
		-- find where in the format stream we need to be given the specified place in the text stream
		renderState.formatStreamIndex = self:FindFormatStreamIndexForTextStreamPos(textStreamIndex)

		-- copy the state data
		local stream = self.m_FormatStream[renderState.formatStreamIndex]
		renderState.textColor = stream.color
		renderState.pixelsIndent = stream.pixelsIndent
		renderState.textClickable = stream.textClickable
	end

	function PANEL:Think()
		if self.m_bRecalcLineBreaks then
			self._recalcSavedRenderState = true
			self:RecalculateLineBreaks()

			-- recalculate scrollbar position
			if self._invalidateVerticalScrollbarSlider then
				self:LayoutVerticalScrollBarSlider()
			end
		end
	end

	function PANEL:PerformLayout()
		-- force a repaint
	end

	function PANEL:InsertColorChange(r, g, b, a)
		local prevItem = self.m_FormatStream[#self.m_FormatStream]
		if prevItem.color.r == r and prevItem.color.g == g and prevItem.color.b == b and prevItem.color.a == a then
			-- inserting same color into stream, just ignore
		elseif prevItem.textStreamIndex == #self.m_TextStream + 1 then
			-- this item is in the same place; update values
			prevItem.color = Color(r, g, b, a)
		else
			-- add to text stream, based off existing item
			---@class TFormatStream
			local streamItem = {}
			table.CopyFromTo(prevItem, streamItem)

			streamItem.color = Color(r, g, b, a)
			streamItem.textStreamIndex = #self.m_TextStream + 1

			table.insert(self.m_FormatStream, streamItem)
		end
	end

	function PANEL:InsertFade(flSustain, flLength)
		-- see if color already exists in text stream
		local prevItem = self.m_FormatStream[#self.m_FormatStream]
		if prevItem.textStreamIndex == #self.m_TextStream + 1 then
			-- this item is in the same place; update values
			prevItem.fade.flFadeStartTime = SysTime() + flSustain
			prevItem.fade.flFadeSustain = flSustain
			prevItem.fade.flFadeLength = flLength
			prevItem.fade.iOriginalAlpha = prevItem.color.a
		else
			-- add to text stream, based off existing item
			---@class TFormatStream
			local streamItem = {}
			table.CopyFromTo(prevItem, streamItem)

			prevItem.fade = {
				flFadeStartTime = SysTime() + flSustain,
				flFadeLength = flLength,
				flFadeSustain = flSustain,
				iOriginalAlpha = prevItem.color.a
			}

			streamItem.textStreamIndex = #self.m_TextStream + 1
			table.insert(self.m_FormatStream, streamItem)
		end
	end

	function PANEL:ResetAllFades(bHold, bOnlyExpired, flNewSustain)
		self.m_bResetFades = bHold

		if self.m_bResetFades == false then
			for i = 1, #self.m_FormatStream do
				local stream = self.m_FormatStream[i]
				if bOnlyExpired then
					if stream.fade.flFadeStartTime >= SysTime() then
						continue
					end
				end

				if flNewSustain == -1 then
					flNewSustain = stream.fade.flFadeSustain
				end

				stream.fade.flFadeStartTime = SysTime() + flNewSustain
			end
		end
	end

	function PANEL:InsertIndentChange(pixelsIndent)
		pixelsIndent = math.Clamp(pixelsIndent, 0, 255)

		-- see if indent change already exists in text stream
		local prevItem = self.m_FormatStream[#self.m_FormatStream]
		if prevItem.pixelsIndent == pixelsIndent then
			-- inserting same indent into stream, just ignore
		elseif prevItem.textStreamIndex == #self.m_TextStream + 1 then
			-- this item is in the same place; update
			prevItem.pixelsIndent = pixelsIndent
		else
			-- add to text stream, based off existing item
			---@class TFormatStream
			local streamItem = {}
			table.CopyFromTo(prevItem, streamItem)

			streamItem.pixelsIndent = pixelsIndent
			streamItem.textStreamIndex = #self.m_TextStream + 1
			table.insert(self.m_FormatStream, streamItem)
		end
	end

	function PANEL:InsertClickableTextStart(pchClickAction)
		-- see if indent change already exists in text stream
		local prevItem = self.m_FormatStream[#self.m_FormatStream]
		local pFormatStream = prevItem
		if prevItem.textStreamIndex == #self.m_TextStream + 1 then
			-- this item is in the same place; update
			prevItem.textClickable = true
			pFormatStream.m_sClickableTextAction = pchClickAction
		else
			-- add to text stream, based off existing item
			---@class TFormatStream
			local formatStreamCopy = {}
			table.CopyFromTo(prevItem, formatStreamCopy)
			table.insert(self.m_FormatStream, formatStreamCopy)

			pFormatStream = formatStreamCopy
			pFormatStream.textStreamIndex = #self.m_TextStream + 1
			pFormatStream.textClickable = true
			pFormatStream.m_sClickableTextAction = pchClickAction
		end

		-- invalidate the layout to recalculate where the click panels should go
		self:InvalidateLineBreakStream()
		self:InvalidateLayout()
	end

	function PANEL:InsertClickableTextEnd()
		-- see if indent change already exists in text stream
		local prevItem = self.m_FormatStream[#self.m_FormatStream]
		if not prevItem.textClickable then
			-- insert same indent into stream, just ignore
		elseif prevItem.textStreamIndex == #self.m_TextStream + 1 then
			-- this item is in the same place; update
			prevItem.textClickable = false
		else
			-- add to text stream, based off existing item
			---@class TFormatStream
			local streamItem = {}
			table.CopyFromTo(prevItem, streamItem)
			streamItem.textClickable = false
			streamItem.textStreamIndex = #self.m_TextStream + 1
			table.insert(self.m_FormatStream, streamItem)
		end
	end

	---moves x,y to the Start of the next line of text
	---@param cx integer
	---@param cy integer
	---@return integer x
	---@return integer y
	function PANEL:AddAnotherLine(cx, cy)
		cx = self._drawOffsetX + self._pixelsIndent
		cy = cy + self:GetLineHeight() + self._drawOffsetY

		return cx, cy
	end

	---Recalculates line breaks
	function PANEL:RecalculateLineBreaks()
		if not self.m_bRecalcLineBreaks then return end

		local wide = self:GetWide()
		if not wide then return end

		wide = wide - self._drawOffsetX

		self.m_bRecalcLineBreaks = false
		self._recalcSavedRenderState = true
		if not self:HasText() then return end

		local selection0, selection1 = -1, -1

		if self._vertScrollBar:IsVisible() then
			wide = wide - self._vertScrollBar:GetWide()
		end

		local x, y = self._drawOffsetX, self._drawOffsetY

		local fontWordStart
		local wordStartIndex = 1
		local lineStartIndex = 1
		local hasWord = false
		local justStartedNewLine = true
		local wordStartedOnNewLine = true

		local startChar = 1
		if self._recalculateBreaksIndex <= 1 then
			table.Empty(self.m_LineBreaks)
		else
			-- remove the rest of the linebreaks list since its out of date.
			for i = self._recalculateBreaksIndex + 1, #self.m_LineBreaks do
				table.remove(self.m_LineBreaks, i)
				--i = i - 1
			end
			startChar = self.m_LineBreaks[self._recalculateBreaksIndex]
			lineStartIndex = self.m_LineBreaks[self._recalculateBreaksIndex]
			wordStartIndex = lineStartIndex
		end

		-- handle the case where this char is a new line, in that case
		-- we have already taken its break index into account above so skip it.
		if self.m_TextStream[startChar] == "\r" or self.m_TextStream[startChar] == "\n" then
			startChar = startChar + 1
			lineStartIndex = startChar
		end

		-- cycle to the right url panel for what is visible after the startIndex.
		local clickableTextNum = self:GetClickableTextIndexStart(startChar)
		clickableTextNum = clickableTextNum + 1

		-- initialize the renderstate with the start
		---@class TRenderState
		local renderState = {}
		self:GenerateRenderStateForTextStreamIndex(startChar, renderState)
		self._currentTextClickable = false

		local font = self._font

		local bForceBreak = false
		local flLineWidthSoFar = 0

		-- loop through all characters
		local i = startChar - 1
		while i < #self.m_TextStream do
			i = i + 1

			local ch = self.m_TextStream[i]
			renderState.x = x
			if self:UpdateRenderState(i, renderState) then
				x = renderState.x
				local preI = i

				-- check for clickable text
				if renderState.textClickable ~= self._currentTextClickable then
					if renderState.textClickable then
						-- make a new clickable text panel
						if clickableTextNum >= #self._clickableTextPanels then
							table.insert(self._clickableTextPanels, vgui.Create("LuaClickPanel", self))
						end

						local clickPanel = self._clickableTextPanels[clickableTextNum]
						clickableTextNum = clickableTextNum + 1
						if clickPanel and clickPanel:IsValid() then
							clickPanel:SetTextIndex(preI, preI)
						end
					end

					-- url state change
					self._currentTextClickable = renderState.textClickable
				end
			end

			local bIsWSpace = isstring(ch) and isspace(ch)

			local bPreviousWordStartedOnNewLine = wordStartedOnNewLine
			local iPreviousWordStartIndex = wordStartIndex
			if not bIsWSpace and ch ~= "\t" and ch ~= "\n" and ch ~= "\r" then
				if not hasWord then
					-- Start a new word
					wordStartIndex = i
					hasWord = true
					wordStartedOnNewLine = justStartedNewLine
					fontWordStart = font
				end
				-- else append to the current word
			else
				-- whitespace/punctuation character
				-- end the word
				hasWord = false
			end

			--local w = 0
			--local wchBefore = 0
			--local wchAfter = 0
			--if i > 1 and i > lineStartIndex and i ~= selection0 and (i - 1) ~= selection1 then
			--	wchBefore = self.m_TextStream[i - 1]
			--end
			--if i < #self.m_TextStream and (i + 1) ~= selection0 and i ~= selection1 then
			--	wchAfter = self.m_TextStream[i + 1]
			--end

			--local flabcA
			-- this function is stubbed out in the 2017 leak, just makes w and flabcA 0
			--GetKernedCharacterWidth(font, ch, wchBefore, wchAfter, w, flabcA)
			--flLineWidthSoFar = flLineWidthSoFar + w

			surface.SetFont(font)
			local w = 0
			if istable(ch) then
				w = ch.width
			else
				---@cast ch string
				w = surface.GetTextSize(ch)
			end
			flLineWidthSoFar = flLineWidthSoFar + w

			-- See if we've exceeded the width we have available, with
			if math.floor(flLineWidthSoFar + 0.6) + x > wide then
				bForceBreak = true
			end

			if isstring(ch) and not iscntrl(ch) then
				justStartedNewLine = false
			end

			if bForceBreak or ch == "\r" or ch == "\n" then
				bForceBreak = false
				-- add another line
				x, y = self:AddAnotherLine(x, y)

				if ch == "\r" or ch == "\n" then
					-- skip the newline so it's not at the beginning of the new line
					lineStartIndex = i + 1
					table.insert(self.m_LineBreaks, i + 1)
				elseif bPreviousWordStartedOnNewLine or iPreviousWordStartIndex <= lineStartIndex then
					lineStartIndex = i
					table.insert(self.m_LineBreaks, i)

					if renderState.textClickable then
						-- need to split the url into two panels
						local oldIndex = self._clickableTextPanels[clickableTextNum - 1]:GetTextIndex()

						-- make a new clickable text panel
						if clickableTextNum >= #self._clickableTextPanels then
							table.insert(self._clickableTextPanels, vgui.Create("LuaClickPanel", self))
						end

						local clickPanel = self._clickableTextPanels[clickableTextNum]
						clickableTextNum = clickableTextNum + 1
						clickPanel:SetTextIndex(oldIndex, i)
					end
				else
					table.insert(self.m_LineBreaks, iPreviousWordStartIndex)
					lineStartIndex = iPreviousWordStartIndex
					i = iPreviousWordStartIndex

					---@class TRenderState
					local renderStateAtLastWord = {}
					self:GenerateRenderStateForTextStreamIndex(i, renderStateAtLastWord)

					-- If the word is clickable, and that started prior to the beginning of the word, then we must split the click panel
					if renderStateAtLastWord.textClickable and self.m_FormatStream[renderStateAtLastWord.formatStreamIndex].textStreamIndex < i then
						-- need to split the url into two panels
						local oldIndex = self._clickableTextPanels[clickableTextNum - 1]:GetTextIndex()

						-- make a new clickable text panel
						if clickableTextNum >= #self._clickableTextPanels then
							table.insert(self._clickableTextPanels, vgui.Create("LuaClickPanel", self))
						end

						local clickPanel = self._clickableTextPanels[clickableTextNum]
						clickableTextNum = clickableTextNum + 1
						clickPanel:SetTextIndex(oldIndex, i)
					end
				end

				flLineWidthSoFar = 0
				justStartedNewLine = true
				hasWord = false
				wordStartedOnNewLine = false
				self._currentTextClickable = false
				continue
			end
		end

		-- end the list
		table.insert(self.m_LineBreaks, MAX_BUFFER_SIZE)

		-- set up the scrollbar
		self._invalidateVerticalScrollbarSlider = true
	end

	---Recalculate where the vertical scroll bar slider should be based on the current cursor line we are on.
	function PANEL:LayoutVerticalScrollBarSlider()
		self._invalidateVerticalScrollbarSlider = false

		local scrollbar = self._vertScrollBar

		local previousValue = math.floor(scrollbar:GetScroll())
		local bCurrentlyAtEnd = false
		if previousValue == math.floor(scrollbar.CanvasSize) then
			bCurrentlyAtEnd = true
		end

		-- work out position to put scrollbar, factoring in insets
		local wide, tall = self:GetSize()

		scrollbar:SetPos(wide - scrollbar:GetWide(), 0)
		-- scrollbar is inside the borders.
		scrollbar:SetTall(tall)

		-- calculate how many lines we can fully display
		local lh = self:GetLineHeight() + self._drawOffsetY
		local displayLines = math.floor(tall / lh)
		local numLines = #self.m_LineBreaks

		if numLines <= displayLines then
			-- disable the scrollbar
			scrollbar:SetUp(tall, numLines * lh)
			scrollbar:SetEnabled(false)

			if self.m_bUnusedScrollbarInvis then
				self:SetVerticalScrollbarEnabled(false)
			end
		else
			if self.m_bUnusedScrollbarInvis then
				self:SetVerticalScrollbarEnabled(true)
			end

			-- set the scrollbars range
			scrollbar:SetUp(tall, numLines * lh)
			scrollbar:SetEnabled(true)

			if bCurrentlyAtEnd then
				scrollbar:SetScroll(numLines * lh)
			end
			scrollbar:InvalidateLayout()
		end
	end

	function PANEL:SetVerticalScrollbarEnabled(state)
		local scrollbar = self._vertScrollBar
		--print("SetVerticalScrollbarEnabled pre", state, scrollbar:IsVisible())
		if scrollbar:IsVisible() ~= state then
			scrollbar:SetMouseInputEnabled(state)
			scrollbar:SetVisible(state)
			self:InvalidateLineBreakStream()
			self:InvalidateLayout()
		end
		--print("SetVerticalScrollbarEnabled post", state, scrollbar:IsVisible())
	end

	---Create cut/copy/paste dropdown menu
	function PANEL:CreateEditMenu()
		-- create a drop down cut/copy/paste menu appropriate for this object's states
		if self.m_pEditMenu:IsValid() then
			self.m_pEditMenu:Remove()
		end
		self.m_pEditMenu = DermaMenu(false, self)

		-- add cut/copy/paste drop down options if its editable, just copy if it is not
		self.m_pEditMenu:AddOption("Copy", function() self:CopySelected() end)

		self.m_pEditMenu:SetVisible(false)
	end

	function PANEL:OnCursorEntered()
		self._mouseDragSelection = false -- outside of window dont recieve drag scrolling ticks
	end

	function PANEL:OnCursorExited()
		if self._mouseSelection then
			self._mouseDragSelection = true
		end
	end

	function PANEL:OnCursorMoved(ignX, ignY)
		if self._mouseSelection then
			local x, y = self:ScreenToLocal(input.GetCursorPos())
			self._cursorPos = self:PixelToCursorSpace(x, y)

			if self._cursorPos ~= self._select[2] then
				self._select[2] = self._cursorPos
			end
		end
	end

	function PANEL:OnMousePressed(code)
		if code == MOUSE_LEFT then
			-- clear current selection
			self:SelectNone()

			-- move the cursor to where the mouse was pressed
			local x, y = self:ScreenToLocal(input.GetCursorPos())

			self._cursorPos = self:PixelToCursorSpace(x, y)

			if self.m_bInteractive then
				-- enter selection mode
				self:MouseCapture(true)
				self._mouseSelection = true

				if self._select[1] < 1 then
					-- if no initial selection position, Start selection position at cursor
					self._select[1] = self._cursorPos
				end
				self._select[2] = self._cursorPos

				self:RequestFocus()

				if not self.__doubleclickwindow or self.__doubleclickwindow < RealTime() then
					self.__doubleclickwindow = RealTime() + 0.2
					return
				end

				self.__doubleclickwindow = nil

				local selectSpot = { 0, 0 }
				self:GotoWordLeft()
				selectSpot[1] = self._cursorPos
				self:GotoWordRight()
				selectSpot[2] = self._cursorPos

				if self._cursorPos > 1 and self._cursorPos - 1 < #self.m_TextStream then
					local ch = self.m_TextStream[self._cursorPos - 1]
					if isstring(ch) and isspace(ch) then
						selectSpot[2] = selectSpot[2] - 1
						self._cursorPos = self._cursorPos - 1
					end
				end

				self._select[1] = selectSpot[1]
				self._select[2] = selectSpot[2]
				self._mouseSelection = true
			end
		elseif code == MOUSE_RIGHT then -- check for context menu open
			if self.m_bInteractive then
				self:CreateEditMenu()
				assert(self.m_pEditMenu:IsValid())

				self:OpenEditMenu()
			end
		end
	end

	function PANEL:OnMouseReleased(code)
		self._mouseSelection = false
		self:MouseCapture(false)

		-- make sure something has been selected
		local cx0, cx1 = self:GetSelectedTextRange()
		if cx1 - cx0 == 0 then
			-- nullify selection
			self._select[1] = 0
		end
	end

	function PANEL:OnKeyCodePressed(code)
		local shift = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
		local ctrl = input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
		local alt = input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT)
		local winkey = input.IsKeyDown(KEY_LWIN) or input.IsKeyDown(KEY_RWIN)
		local fallThrough = false

		if ctrl or (winkey and system.IsOSX()) then
			if code == KEY_INSERT or code == KEY_C or code == KEY_X then
				self:CopySelected()
			elseif code == KEY_PAGEUP or code == KEY_HOME then
				self:GotoTextStart()
			elseif code == KEY_PAGEDOWN or code == KEY_END then
				self:GotoTextEnd()
			else
				fallThrough = true
			end
		elseif alt then
			-- do nothing with ALT-x keys
			fallThrough = true
		else
			if code == KEY_TAB or code == KEY_LSHIFT or code == KEY_RSHIFT or code == KEY_ESCAPE or code == KEY_ENTER then
				fallThrough = true
			elseif code == KEY_DELETE and shift then
				-- shift-delete is cut
				self:CopySelected()
			elseif code == KEY_HOME then
				self:GotoTextStart()
			elseif code == KEY_END then
				self:GotoTextEnd()
			elseif code == KEY_PAGEUP then
				-- if there is a scroll bar scroll down one rangewindow
				if self._vertScrollBar:IsVisible() then
					-- TODO
				end
			elseif code == KEY_PAGEDOWN then
				-- if there is a scroll bar scroll down one rangewindow
				if self._vertScrollBar:IsVisible() then
					-- TODO
				end
			else
				-- return if any other char is pressed.
				-- as it will be a unicode char.
				-- and we don't want select[2] changed unless a char was pressed that this fxn handles
				return
			end
		end

		-- select[2] is the location in the line where the blinking cursor started
		self._select[2] = self._cursorPos

		-- chain back on some keys
		if fallThrough then
			-- BaseClass call (doesn't exist)
		end
	end

	function PANEL:OnMouseWheeled(delta)
		self:MoveScrollBar(delta * 3)
	end

	---Scrolls the list
	---@param delta number amount to move scrollbar up
	function PANEL:MoveScrollBar(delta)
		self:MoveScrollBarDirect(delta * (self:GetLineHeight() + self._drawOffsetY))
	end

	---Scrolls the list
	---@param delta number amount to move scrollbar up
	function PANEL:MoveScrollBarDirect(delta)
		if self._vertScrollBar:IsVisible() then
			local val = self._vertScrollBar:GetScroll()
			val = val - delta
			self._vertScrollBar:SetScroll(val)
			self._recalcSavedRenderState = true
		end
	end

	---set the maximum number of chars in the text buffer
	---@param maxChars integer
	function PANEL:SetMaximumCharCount(maxChars)
		self._maxCharCount = maxChars
	end

	function PANEL:GetMaximumCharCount()
		return self._maxCharCount
	end

	---Find out what line the cursor is on
	function PANEL:GetCursorLine()
		-- always returns the last place
		local pos = self.m_LineBreaks[#self.m_LineBreaks]
		assert(pos == MAX_BUFFER_SIZE)
		return pos
	end

	---Move the cursor over to the Start of the next word to the right
	function PANEL:GotoWordRight()
		-- search right until we hit a whitespace character or a newline
		self._cursorPos = self._cursorPos + 1
		while self._cursorPos < #self.m_TextStream do
			local ch = self.m_TextStream[self._cursorPos]
			if isstring(ch) and isspace(ch) then break end

			self._cursorPos = self._cursorPos + 1
		end

		-- search right until we hit an nonspace character
		self._cursorPos = self._cursorPos + 1
		while self._cursorPos < #self.m_TextStream do
			local ch = self.m_TextStream[self._cursorPos]
			if not (isstring(ch) and isspace(ch)) then break end

			self._cursorPos = self._cursorPos + 1
		end

		if self._cursorPos > #self.m_TextStream then
			self._cursorPos = #self.m_TextStream
		end
	end

	---Move the cursor over to the Start of the next word to the left
	function PANEL:GotoWordLeft()
		if self._cursorPos < 1 then return end

		-- search left until we hit an nonspace character
		self._cursorPos = self._cursorPos - 1
		while self._cursorPos >= 1 do
			local ch = self.m_TextStream[self._cursorPos]
			if not (isstring(ch) and isspace(ch)) then break end

			self._cursorPos = self._cursorPos - 1
		end

		-- search left until we hit a whitespace character or a newline
		self._cursorPos = self._cursorPos - 1
		while self._cursorPos >= 1 do
			local ch = self.m_TextStream[self._cursorPos]
			if isstring(ch) and isspace(ch) then break end

			self._cursorPos = self._cursorPos - 1
		end

		-- we end one character off
		self._cursorPos = self._cursorPos + 1
	end

	---Move cursor to the Start of the text buffer
	function PANEL:GotoTextStart()
		self._cursorPos = 1 -- set cursor to start
		self._invalidateVerticalScrollbarSlider = true
		-- force scrollbar to the top
		self._vertScrollBar:SetScroll(0)
	end

	---Move cursor to the end of the text buffer
	function PANEL:GotoTextEnd()
		self._cursorPos = #self.m_TextStream
		self._invalidateVerticalScrollbarSlider = true

		-- force the scrollbar to the bottom
		self._vertScrollBar:SetScroll(self._vertScrollBar.CanvasSize)
	end

	---Culls the text stream down to a managable size
	function PANEL:TruncateTextStream()
		if self._maxCharCount < 1 then return end

		-- choose a point to cull at
		local cullPos = math.ceil(self._maxCharCount / 2)

		-- kill half the buffer
		for _ = 1, cullPos do
			table.remove(self.m_TextStream, 1)
		end

		-- work out where in the format stream we can start
		local formatIndex = self:FindFormatStreamIndexForTextStreamPos(cullPos)
		if formatIndex > 1 then
			-- take a copy, make it first
			self.m_FormatStream[1] = self.m_FormatStream[formatIndex]
			self.m_FormatStream[1].textStreamIndex = 1
			-- kill the others
			for _ = 2, formatIndex do
				table.remove(self.m_FormatStream, 2)
			end
		end

		-- renormalize the remainder of the format stream
		for i = 2, #self.m_FormatStream do
			assert(self.m_FormatStream[i].textStreamIndex > cullPos)
			self.m_FormatStream[i].textStreamIndex = self.m_FormatStream[i].textStreamIndex - cullPos
		end

		-- mark everything to be recalculated
		self:InvalidateLineBreakStream()
		self:InvalidateLayout()
		self._invalidateVerticalScrollbarSlider = true
	end

	---Insert a character into the text buffer
	---@param wch string|ImageComponent
	function PANEL:InsertChar(wch)
		if istable(wch) then
			if self._maxCharCount > 0 and #self.m_TextStream > self._maxCharCount then
				self:TruncateTextStream()
			end

			table.insert(self.m_TextStream, wch)
			return
		end
		---@cast wch string

		if utf8.len(wch) > 1 then
			wch = utf8.sub(wch, 1, 1)
		end

		-- throw away redundant linefeed characters
		if wch == "\r" then return end

		if self._maxCharCount > 0 and #self.m_TextStream > self._maxCharCount then
			self:TruncateTextStream()
		end

		-- insert the new char at the end of the buffer
		table.insert(self.m_TextStream, wch)

		-- mark the linebreak stream as needing recalculating from that point
		self._recalculateBreaksIndex = #self.m_LineBreaks - 2
	end

	---Insert a string into the text buffer
	---@param text string
	function PANEL:AppendText(text)
		if text:sub(1, 1) == "#" then
			text = language.GetPhrase(text)
		end

		for i = 1, utf8.len(text) do
			self:InsertChar(utf8.GetChar(text, i))
		end
		self:InvalidateLayout()
		self.m_bRecalcLineBreaks = true
	end

	---Declare a selection empty
	function PANEL:SelectNone()
		-- tag the selection as empty
		self._select[1] = 0
	end

	---Load in the selection range so cx0 is the Start and cx1 is the end from smallest to highest (right to left)
	---@return integer cx0
	---@return integer cx1
	function PANEL:GetSelectedTextRange()
		-- if tehre is nothing selected, return nothing
		if self._select[1] == 0 then return 0, 0 end

		-- sort the two positions so cx0 is the smallest
		local cx0 = self._select[1]
		local cx1 = self._select[2]
		if cx1 < cx0 then
			local temp = cx0
			cx0 = cx1
			cx1 = temp
		end

		return cx0, cx1
	end

	---Opens the cut/copy/paste dropdown menu
	function PANEL:OpenEditMenu()
		self.m_pEditMenu:Open()
	end

	---Cuts the selected chars from the buffer and copies them into the clipboard
	function PANEL:CutSelected()
		self:CopySelected()
		-- have to request focus if we used the menu
		self:RequestFocus()
	end

	---Copies the selected chars into the clipboard
	function PANEL:CopySelected()
		local x0, x1 = self:GetSelectedTextRange()
		local failed = x0 == 0 and x1 == 0
		if not failed then
			local buf = ""
			for i = x0, x1 do
				local char = self.m_TextStream[i]
				if char == nil then continue end

				if istable(char) then char = char.text end

				if char == "\n" then
					buf = buf .. "\r"
				end
				buf = buf .. char
			end
			SetClipboardText(buf)
		end

		-- have to request focus if we used the menu
		self:RequestFocus()
	end

	---Returns the index in the text buffer of the character the drawing should Start at
	---@param lineBreakIndexIndex integer
	---@return integer startIndex
	---@return integer lineBreakIndexIndex
	function PANEL:GetStartDrawIndex(lineBreakIndexIndex)
		local startIndex = 1
		local lh = self:GetLineHeight() + self._drawOffsetY
		local numLines = #self.m_LineBreaks
		local startLine = (numLines - math.floor(((numLines * lh) - self._vertScrollBar:GetScroll()) / lh)) + 1

		if startLine >= #self.m_LineBreaks then
			startLine = #self.m_LineBreaks - 1
		end

		lineBreakIndexIndex = startLine
		if startLine > 1 and startLine < #self.m_LineBreaks then
			startIndex = self.m_LineBreaks[startLine - 1]
		end
		if startIndex > #self.m_TextStream then
			startIndex = #self.m_TextStream
		end

		return startIndex, lineBreakIndexIndex
	end

	---Get a string from text buffer
	---@param offset integer? index to Start reading from
	---@param len integer? length of string
	---@return string
	function PANEL:GetText(offset, len)
		if offset == nil or offset < 1 then offset = 1 end
		local total = offset > 1 and #self.m_TextStream - offset or #self.m_TextStream
		if len == nil or len > total then len = total end

		local buf = {}
		for i = offset, len do
			local ch = self.m_TextStream[i]
			if istable(ch) then ch = ch.text end
			table.insert(buf, ch)
		end

		return table.concat(buf, "")
	end

	---Set the font of the buffer text
	---@param font string
	function PANEL:SetFontInternal(font)
		self._font = font
		self:InvalidateLayout()
		self.m_bRecalcLineBreaks = true
	end

	function PANEL:OnVScroll()
		self._recalcSavedRenderState = true
	end

	---Called when a URL, etc has been clicked on
	---@param index integer
	function PANEL:OnClickPanel(index)
		-- parse out the clickable text, and send it to our listeners
		self._currentTextClickable = true
		---@class TRenderState
		local renderState = {}
		self:GenerateRenderStateForTextStreamIndex(index, renderState)

		local wBuf = ""
		for i = index, #self.m_TextStream do
			-- stop getting characters when text is no longer clickable
			self:UpdateRenderState(i, renderState)
			if not renderState.textClickable then break end

			local ch = self.m_TextStream[i]
			if istable(ch) then ch = ch.text end

			-- copy out the character
			wBuf = wBuf .. ch
		end

		local iFormatStream = self:FindFormatStreamIndexForTextStreamPos(index)
		local stream = self.m_FormatStream[iFormatStream]
		if stream.m_sClickableTextAction and stream.m_sClickableTextAction ~= "" then
			wBuf = stream.m_sClickableTextAction
		end

		--PostActionSignal
		self:OnTextClicked(wBuf)
	end

	---Get the number of lines in the window
	---@return integer
	function PANEL:GetNumLines()
		return #self.m_LineBreaks
	end

	---Sets the height of the text entry window so all text will fit inside
	function PANEL:SetToFullHeight()
		-- We might not yet have calculated our line breaks yet, which would be bad since we're about to change our height
		-- based on how many lines we use. Let's make sure they're calculated.
		--self:RecalculateLineBreaks()
		self:PerformLayout()

		local wide, tall = self:GetSize()

		tall = self:GetNumLines() * (self:GetLineHeight() + self._drawOffsetY) + self._drawOffsetY + 2
		self:SetSize(wide, tall)
		self:PerformLayout()
	end

	---Select all the text.
	function PANEL:SelectAll()
		self._cursorPos = 1
		self._select[1] = 1
		self._select[2] = #self.m_TextStream
	end

	---Select none of the text
	function PANEL:SelectNoText()
		self._select[1] = 1
		self._select[2] = 1
	end

	---Invalidates the current linebreak stream
	function PANEL:InvalidateLineBreakStream()
		-- clear the buffer
		table.Empty(self.m_LineBreaks)
		table.insert(self.m_LineBreaks, MAX_BUFFER_SIZE)
		self._recalculateBreaksIndex = 1
		self.m_bRecalcLineBreaks = true
	end

	---Inserts a text string while making URLs clickable/different color
	---@param text string
	---@param URLTextColor Color
	---@param normalTextColor Color
	function PANEL:InsertPossibleURLString(text, URLTextColor, normalTextColor)
		self:InsertColorChange(normalTextColor:Unpack())

		-- TODO
	end

	---looks for URLs in the string and returns information about the URL
	---@param text string
	---@param startPos integer
	function PANEL:ParseTextStringsForUrls(text, startPos)
		-- TODO
	end

	---Executes the text-clicked command, which opens a web browser by default.
	---@param wszText string
	function PANEL:OnTextClicked(wszText)
		-- Strip leading/trailing quotes, which may be present on href tags or may not.
		local pwchURL = wszText
		local ch = pwchURL:sub(1, 1)
		if ch == '"' or ch == "'" then
			pwchURL = wszText:sub(2)
		end

		local strLen = #pwchURL
		local ch2 = pwchURL:sub(strLen - 1, strLen - 1)
		if ch2 == '"' or ch2 == "'" then
			pwchURL = pwchURL:sub(1, strLen - 1)
		end

		if self.m_hPanelToHandleClickingURLs:IsValid() then
			--PostMessage
		else
			if pwchURL:match("^https?://") then
				gui.OpenURL(pwchURL)
			end
		end
	end

	---@param pPanelToHandleClickMsg Panel
	function PANEL:SetURLClickedHandler(pPanelToHandleClickMsg)
		self.m_hPanelToHandleClickingURLs = pPanelToHandleClickMsg
	end

	---data accessor
	---@return boolean
	function PANEL:IsScrollbarVisible()
		return self._vertScrollBar:IsVisible()
	end

	---@param font string
	function PANEL:SetUnderlineFont(font)
		self.m_hFontUnderline = font
	end

	---@return boolean
	function PANEL:IsAllTextAlphaZero()
		return self.m_bAllTextAlphaIsZero
	end

	---@return boolean
	function PANEL:HasText()
		return #self.m_TextStream > 0
	end

	---Returns the height of the base font
	---@return number
	function PANEL:GetLineHeight()
		surface.SetFont(self._font)
		local _, h = surface.GetTextSize("W")
		return h
	end

	function PANEL:SetAllowNonAsciiCharacters(state)
		-- TODO
	end

	---@param textColor Color
	---@param backgroundColor Color
	function PANEL:SetTextSelectionColors(textColor, backgroundColor)
		self._selectionTextColor:SetUnpacked(textColor:Unpack())
		self._selectionColor:SetUnpacked(backgroundColor:Unpack())
	end

	function PANEL:SetLineHeight(h)
		-- TODO
	end

	vgui.Register("LuaRichText", PANEL, "EditablePanel")
end
