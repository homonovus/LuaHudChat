local PANEL = {}

local CHAT_HISTORY_FADE_TIME = 0.25
local CHAT_HISTORY_ONE_OVER_FADE_TIME = 1 / CHAT_HISTORY_FADE_TIME

function PANEL:ApplySchemeSettings()
    if LuaHudChat.ChatSettings then
        local x, y = ScreenScaleH(LuaHudChat.ChatSettings:GetInt("xpos", 10)), ScreenScaleH(LuaHudChat.ChatSettings:GetInt("ypos", 275))
        local w, h = ScreenScaleH(LuaHudChat.ChatSettings:GetInt("wide", 320)), ScreenScaleH(LuaHudChat.ChatSettings:GetInt("tall", 120))

        self:SetPos(x, y)
        self:SetSize(w, h)

        self:SetName("LuaHudChat")
    end

    --self:SetBackgroundType(2)
    self:SetPaintBorderEnabled(true)
    self:SetPaintBackgroundEnabled(true)

    self:SetKeyboardInputEnabled(false)
    self:SetMouseInputEnabled(false)

    local color = LuaHudChat.GetSchemeColor("DullWhite", self:GetBGColor())
    self:SetBGColor(color.r, color.g, color.b, LuaHudChat._CHAT_HISTORY_ALPHA)

    self:FadeChatHistory()

    local chatHistory = self:GetChatHistory()
    chatHistory:SetVerticalScrollbarEnabled(false)
end

PANEL.m_FilterFlags = 0
AccessorFunc(PANEL, "m_FilterFlags", "FilterFlags", FORCE_NUMBER)

local function FiltersButton_Paint(self, w,h)
    local borderName = LuaHudChat.SchemeBorders:GetString("ButtonBorder", "RaisedBorder")
    LuaHudChat.PaintBorder(borderName, 0,0, w,h)
end

local cl_chatfilters = GetConVar("cl_chatfilters")
local hud_saytext_time = GetConVar("hud_saytext_time")

function PANEL:Init()
    -- (We don't actually want input until they bring up the chat line).
    self:MakePopup()
    self:SetZPos(-30)

    self.m_FiltersButton = vgui.Create("DButton", self, "ChatFiltersButton")
    self.m_FiltersButton:SetCursor("arrow")
    if LuaHudChat.ChatFiltersSettings then
        local x, y = ScreenScaleH(LuaHudChat.ChatFiltersSettings:GetInt("xpos", 265)), ScreenScaleH(LuaHudChat.ChatFiltersSettings:GetInt("ypos", 2))
        local w, h = ScreenScaleH(LuaHudChat.ChatFiltersSettings:GetInt("wide", 45)), ScreenScaleH(LuaHudChat.ChatFiltersSettings:GetInt("tall", 15))

        self.m_FiltersButton:SetPos(x, y)
        self.m_FiltersButton:SetSize(w, h)
    end
    self.m_FiltersButton:SetFont("Default_HL2")
    self.m_FiltersButton:SetText("#chat_filterbutton")
    self.m_FiltersButton:SetContentAlignment(5)
    self.m_FiltersButton:SetTextInset(5, 0)
    self.m_FiltersButton:SetVisible(true)
    self.m_FiltersButton:SetEnabled(true)
    self.m_FiltersButton:SetMouseInputEnabled(true)
    self.m_FiltersButton:SetKeyboardInputEnabled(false)

    self.m_FiltersButton:SetDrawBackground(false)
    self.m_FiltersButton:SetPaintBorderEnabled(true)
    self.m_FiltersButton:SetTextColor(LuaHudChat.GetSchemeColor("Button.TextColor", Color(255, 255, 255)))
    self.m_FiltersButton.Paint = FiltersButton_Paint
    self.m_FiltersButton:NoClipping(true)

    function self.m_FiltersButton.DoClick(button)
        self.m_FilterPanel:ToggleVisible()
        self.m_ChatInput:RequestFocus()
        --self.m_FilterPanel:SetVisible(true)
    end

    self.m_ChatHistory = vgui.Create("LuaHudChatHistory", self, "HudChatHistory")
    if LuaHudChat.ChatHistorySettings then
        local x, y = ScreenScaleH(LuaHudChat.ChatHistorySettings:GetInt("xpos", 10)), ScreenScaleH(LuaHudChat.ChatHistorySettings:GetInt("ypos", 10))
        local w, h = ScreenScaleH(LuaHudChat.ChatHistorySettings:GetInt("wide", 300)), ScreenScaleH(LuaHudChat.ChatHistorySettings:GetInt("tall", 100))

        self.m_ChatHistory:SetPos(x, y)
        self.m_ChatHistory:SetSize(w, h)
    end
    self.m_ChatHistory:SetFontInternal("ChatFont")

    --self:CreateChatLine()
    self:CreateChatInputLine()
    self:GetChatFilterPanel()

    self.m_FilterFlags = cl_chatfilters:GetInt()
end

function PANEL:GetChatHistory()
    return self.m_ChatHistory
end

--function PANEL:CreateChatLine()
--	self.m_ChatLine = vgui.Create("LuaHudChatLine", self, "ChatLine1")
--end

--function PANEL:FindUnusedChatLine()
--	return self.m_ChatLine
--end

function PANEL:GetClientColor(playerIndex)
    if playerIndex == 0 then
        return CHAT_GREEN
    else
        local player = Entity(playerIndex)
        if player:IsValid() then
            local teamColor = hook.Run("GetTeamColor", player)
            if teamColor then return teamColor end
        end

        return COLOR_CHAT_GRAY
    end

    return CHAT_YELLOW
end

local MAX_PLAYER_NAME_LENGTH = 32

function PANEL:ChatPrintF(playerIndex, filter, format, ...)
    local msg = string.format(format, ...)

    -- Strip any trailing '\n'
    msg = string.gsub(msg, "(\n+)$", "")

    -- Strip leading \n characters ( or notify/color signifiers ) for empty string check
    local tmp = string.gsub(msg, "(\n+)", "")
    tmp = string.gsub(tmp, "[\1-\9]", "")
    if #tmp == 0 then return end

    -- Now strip just newlines, since we want the color info for printing
    tmp = string.gsub(msg, "(\n+)$", "")
    if #tmp == 0 then return end

    msg = tmp

    --local line = self:FindUnusedChatLine()
    --if not (line and line:IsValid()) then
    --	self:ExpireOldest()
    --	line = self:FindUnusedChatLine()
    --end
    --if not (line and line:IsValid()) then return end

    if filter ~= CHAT_FILTER_NONE then
        if bit.band(self.m_FilterFlags, filter) == 0 then
            return
        end
    end

    --line:SetText("")

    local nameLength = 0
    local nameStart = 0

    local name, ply = "", NULL
    if not playerIndex or playerIndex == 0 then
        name = "Console"
    else
        ply = Entity(playerIndex)
        if ply:IsValid() then
            name = ply:Name()
        end
    end
    nameLength = #name

    -- find the player's name in the unicode string, in case there is no color markup
    --except it's not unicode :D
    if nameLength > 0 then
        local find = string.find(msg, name, nil, true)
        if find then
            nameStart = find
            nameLength = nameLength + (find)
        end
    else
        --local r,g,b = CHAT_YELLOW:Unpack()
        --line:InsertColorChange(r, g, b, 255)
    end

    local nameColor = self:GetClientColor(playerIndex)
    --local r,g,b = color:Unpack()

    --line:SetVisible(false)

    local history = self:GetChatHistory()
    local saytextFadeTime = hud_saytext_time:GetFloat()

    
    if filter == CHAT_FILTER_PUBLICCHAT then
        history:AppendPlayerText(name, ply:SteamID64(), nameColor, saytextFadeTime)
        
        local r,g,b = COLOR_CHAT_WHITE:Unpack()
        history:InsertColorChange(r, g, b, 255)

        history:AppendText(": " .. msg .. "\n")
        history:InsertFade(saytextFadeTime, LuaHudChat._CHAT_HISTORY_IDLE_FADE_TIME)
    else
        local r,g,b = COLOR_CHAT_DEFAULT:Unpack()
        if filter == CHAT_FILTER_JOINLEAVE then
            r,g,b = COLOR_CHAT_JOINLEAVE:Unpack()
        elseif filter == CHAT_FILTER_NAMECHANGE	then
            r,g,b = COLOR_CHAT_NAMECHANGE:Unpack()
        elseif filter == CHAT_FILTER_SERVERMSG then
            r,g,b = COLOR_CHAT_SERVERMSG:Unpack()
        --elseif filter == CHAT_FILTER_TEAMCHANGE then
        --	r,g,b = COLOR_CHAT_TEAMCHANGE:Unpack()
        --elseif filter == CHAT_FILTER_ACHIEVEMENT then
        --	r,g,b = COLOR_CHAT_ACHIEVEMENT:Unpack()
        end

        history:InsertColorChange(r, g, b, 255)
        history:AppendText(msg .. "\n")
        history:InsertFade(saytextFadeTime, LuaHudChat._CHAT_HISTORY_IDLE_FADE_TIME)
    end
end

function PANEL:CreateChatInputLine()
    self.m_ChatInput = vgui.Create("LuaHudChatInputLine", self, "ChatInputLine")
    --self.m_ChatInput:SetVisible(false)

    if LuaHudChat.ChatInputLineSettings then
        local x, y = ScreenScaleH(LuaHudChat.ChatInputLineSettings:GetInt("xpos", 10)), ScreenScaleH(LuaHudChat.ChatInputLineSettings:GetInt("ypos", 108))
        local w, h = ScreenScaleH(LuaHudChat.ChatInputLineSettings:GetInt("wide", 300)), ScreenScaleH(LuaHudChat.ChatInputLineSettings:GetInt("tall", 2))

        self.m_ChatInput:SetPos(x, y)
        self.m_ChatInput:SetSize(w, h)
    end

    local history = self:GetChatHistory()
    if history and history:IsValid() then
        history:SetMaximumCharCount(127 * 100) -- novus: DUMB!!!!!
        history:SetVisible(true)
    end
end

local BACKGROUND_BORDER_WIDTH = 20
function PANEL:GetChatFilterPanel()
    if not (self.m_FilterPanel and self.m_FilterPanel:IsValid()) then
        -- novus: i can't parent this panel to chat because it won't render when outside of bounds
        self.m_FilterPanel = vgui.Create("LuaHudChatFilterPanel", nil, "HudChatFilterPanel")
        self.m_FilterPanel:NoClipping(true)
        self.m_FilterPanel:SetMouseInputEnabled(true)
        self.m_FilterPanel:SetPaintBorderEnabled(true)
        self.m_FilterPanel:SetVisible(false)

        if LuaHudChat.ChatFilterSettings then
            local x,y = ScreenScaleH(LuaHudChat.ChatFilterSettings:GetInt("xpos", 335)), ScreenScaleH(LuaHudChat.ChatFilterSettings:GetInt("ypos", 275))
            local w,h = ScreenScaleH(LuaHudChat.ChatFilterSettings:GetInt("wide", 130)), ScreenScaleH(LuaHudChat.ChatFilterSettings:GetInt("tall", 80))
            self.m_FilterPanel:SetPos(x, y)
            --self.m_FilterPanel:SetPos(ScreenScaleH(319), 0)
            --self.m_FilterPanel:SetPos(0, -20)
            self.m_FilterPanel:SetSize(w, h)
        end
    end

    return self.m_FilterPanel
end

function PANEL:PrintF(filter, fmt, ...)
    local msg = string.format(fmt, ...)

    self:ChatPrintF(0, filter, "%s", msg)
end

function PANEL:StartMessageMode(type)
    self.m_MessageMode = type

    self:MakePopup()

    self.m_ChatInput:ClearEntry()

    local prompt
    if type == MESSAGEMODE_SAY then prompt = language.GetPhrase("chat_say")
    elseif type == MESSAGEMODE_SAY_TEAM then prompt = language.GetPhrase("chat_say_team") end
    --if type == MM_SAY_lua_extra then prompt = language.GetPhrase("chat_say_lua_extra")

    if prompt then
        self.m_ChatInput:SetPrompt(prompt)
    else
        if type == MESSAGEMODE_SAY then
            self.m_ChatInput:SetPrompt("Say :")
        elseif type == MESSAGEMODE_SAY_TEAM then
            self.m_ChatInput:SetPrompt("Say (TEAM) :")
        end
    end

    local history = self:GetChatHistory()
    if history and history:IsValid() then
        history:SetFontInternal("ChatFont")
        history:SetMouseInputEnabled(true)
        history:SetKeyboardInputEnabled(false)
        history:SetVerticalScrollbarEnabled(true)
        history:ResetAllFades(true, false, -1)
        history:SetPaintBorderEnabled(true)
        history:SetVisible(true)
    end

    local visible = hook.Run("StartChat", type == MESSAGEMODE_SAY_TEAM)
    if visible ~= nil then
        self:SetVisible(not visible)
    end
    self:SetKeyboardInputEnabled(true)
    self:SetMouseInputEnabled(true)
    self.m_ChatInput:SetVisible(true)
    self.m_ChatInput:RequestFocus()
    self.m_ChatInput:SetPaintBorderEnabled(true)
    self.m_ChatInput:SetMouseInputEnabled(true)

    --Place mouse cursor near the text so people notice it.
    if history and history:IsValid() then
        local x,y = history:LocalToScreen(0, 0)
        local w,h = history:GetSize()
        input.SetCursorPos(x + (w/2), y + (h/2))
    end

    self.m_HistoryFadeTime = RealTime() + CHAT_HISTORY_FADE_TIME

    self.m_FilterPanel:SetVisible(false)

    -- RunConsoleCommand("gameui_preventescapetoshow")
end

function PANEL:StopMessageMode(fade)
    if fade == nil then
        fade = true
    end

    RunConsoleCommand("gameui_allowescapetoshow")

    hook.Run("FinishChat")

    self:SetKeyboardInputEnabled(false)
    self:SetMouseInputEnabled(false)

    local history = self:GetChatHistory()
    if history and history:IsValid() then
        history:SetPaintBorderEnabled(false)
        history:GotoTextEnd()
        --history:SetMouseInputEnabled(false)
        history:SetVerticalScrollbarEnabled(false)
        history:ResetAllFades(false, true, CHAT_HISTORY_FADE_TIME)
        history:SelectNone() --history:UnselectAll()
        --history:SetVisible(false)
    end

    local menu = self.m_CurrentContextMenu
    if menu and menu:IsValid() then
        menu:Remove()
    end
    self.m_CurrentContextMenu = nil

    --Clear the entry since we won't need it anymore.
    self.m_ChatInput:ClearEntry()

    local text = self:GetText()
    hook.Run("ChatTextChanged", text)

    --hide filter panel
    self.m_FilterPanel:SetVisible(false)

    if fade then
        self.m_HistoryFadeTime = RealTime() + CHAT_HISTORY_FADE_TIME
    else
        self.m_HistoryFadeTime = RealTime()
    end

    self.m_MessageMode = MESSAGEMODE_NONE

    --self:SetVisible(false)
end

local scrollbar_fadein = CreateConVar("hud_saytext_scrollbar_fadein", "1", FCVAR_ARCHIVE, "Enable alpha fade in for the chat history scrollbar")
PANEL.m_HistoryFadeTime = 0
function PANEL:FadeChatHistory()
    local frac = (self.m_HistoryFadeTime - RealTime()) * CHAT_HISTORY_ONE_OVER_FADE_TIME
    local alpha = frac * LuaHudChat._CHAT_HISTORY_ALPHA
    alpha = math.Clamp(alpha, 0, LuaHudChat._CHAT_HISTORY_ALPHA)

    if alpha >= 0 then
        local history = self:GetChatHistory()
        if history and history:IsValid() then
            local promptPanel = self.m_ChatInput.m_Prompt
            local inputPanel = self.m_ChatInput.m_Input
            local bgColor = self:GetBGColor()

			local scrollbar = history._vertScrollBar

            if self:IsMouseInputEnabled() then
                -- fade in
                history:SetBGColor(0,0,0, LuaHudChat._CHAT_HISTORY_ALPHA - alpha)

                if scrollbar and scrollbar:IsValid() then
                    if scrollbar_fadein:GetBool() then
                        scrollbar:SetAlpha((LuaHudChat._CHAT_HISTORY_ALPHA*2) - alpha)
                    else
                        scrollbar:SetAlpha(255)
                    end
                end

                bgColor.a = LuaHudChat._CHAT_HISTORY_ALPHA - alpha
                self:SetBGColor(bgColor)

                promptPanel:SetAlpha((LuaHudChat._CHAT_HISTORY_ALPHA*2) - alpha)
                inputPanel:SetAlpha((LuaHudChat._CHAT_HISTORY_ALPHA*2) - alpha)
                self.m_FiltersButton:SetAlpha((LuaHudChat._CHAT_HISTORY_ALPHA*2) - alpha)
            else
                -- fade out
                history:SetBGColor(0,0,0, alpha)

				if scrollbar and scrollbar:IsValid() then
					if scrollbar_fadein:GetBool() then
						scrollbar:SetAlpha(math.Clamp(frac, 0,1) * 255)
					else
						scrollbar:SetAlpha(0)
					end
				end

                bgColor.a = alpha
                self:SetBGColor(bgColor)

                promptPanel:SetAlpha(alpha)
                inputPanel:SetAlpha(alpha)
                self.m_FiltersButton:SetAlpha(alpha)
            end
        end
    end
end

function PANEL:Send()
    local text = self.m_ChatInput:GetMessageText()

    -- localize??

    --local len = #text

    -- This is a very long string that I am going to attempt to paste into the cs hud chat entry and we will see if it gets cropped or not.
    --

    -- Remove the \n
    --text = string.gsub(text, "\n", "")
    local len = #text

    if len > 0 then
        local cmd

        local messageMode = self.m_MessageMode
        if messageMode == MESSAGEMODE_SAY then
            cmd = "say"
        elseif messageMode == MESSAGEMODE_SAY_TEAM then
            cmd = "say_team"
        end

        if cmd then
            RunConsoleCommand(cmd, text)
        end
    end
end

function PANEL:Clear()
    -- Kill input prompt
    self:StopMessageMode()

    self.m_HistoryFadeTime = 0

    local history = self:GetChatHistory()
    if history and history:IsValid() then
        history:ResetAllFades(false, false, 0)
    end
end

function PANEL:Think()
    local line = self.m_ChatLine
    --if line and line:IsValid() then
        local font = "ChatFont" -- line:GetFont()
        surface.SetFont(font)
        local fontW, fontH = surface.GetTextSize("h")
        self.m_iFontHeight = fontH


        -- Put input area at bottom
        local inputX, inputY = self.m_ChatInput:GetPos()
        local inputW, inputH = self.m_ChatInput:GetSize()

        local chatX, chatY = self:GetPos()
        local chatW, chatH = self:GetSize()

        self.m_ChatInput:SetPos(inputX, chatH - (self.m_iFontHeight * 1.75))
        self.m_ChatInput:SetSize(inputW, self.m_iFontHeight)

        --Resize the History Panel so it fits more lines depending on screen resolution.
        local chatHistory = self:GetChatHistory()
        if chatHistory and chatHistory:IsValid() then
            local historyX, historyY = chatHistory:GetPos()
            local historyW, historyH = chatHistory:GetSize()

            chatHistory:SetTall(chatH - (self.m_iFontHeight * 2.25) - historyY)
        end
    --end

    self:FadeChatHistory()
end

function PANEL:Paint(w, h)
    local color = self:GetBGColor()
    draw.RoundedBox(6, 0, 0, w, h, color)
    return true
end

function PANEL:OnRemove()
    if self.m_FilterPanel and self.m_FilterPanel:IsValid() then
        self.m_FilterPanel:Remove()
    end
end

function PANEL:GetTextColorForClient(chatColor, playerIndex)
    if chatColor == CHAT_TEXT_COLOR_CUSTOM then
        -- return color_custom
    elseif chatColor == CHAT_TEXT_COLOR_PLAYERNAME then
        return self:GetClientColor(playerIndex)
    elseif chatColor == CHAT_TEXT_COLOR_LOCATION then
        return CHAT_DARKGREEN
    --elseif chatColor == CHAT_TEXT_COLOR_ACHIEVEMENT then
    --	-- SourceScheme->SteamLightGreen or self:GetDefaultTextColor()
    else
        return self:GetDefaultTextColor()
    end
end

function PANEL:GetDefaultTextColor()
    return CHAT_YELLOW
end

vgui.Register("LuaHudChat", PANEL, "EditablePanel")
