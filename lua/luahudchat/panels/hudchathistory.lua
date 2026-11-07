local PANEL = {}
local BaseClass = vgui.GetControlTable("LuaRichText")

local text_clickable = GetConVar("hud_saytext_clickable")

-- https://github.com/Earu/EasyChat/blob/abf780df5f5897a00330d1f70aa55bc5a5cf281d/lua/easychat/client/vgui/richtext_legacy.lua#L19-L31
function PANEL:InsertClickableTextStart(value)
    local prev = self.m_ClickList[#self.m_ClickList]

    table.insert(self.m_ClickList, {
        signalValue = value,
        prev = prev,
        panel = false,
    })

    if #self.m_ClickList > 1024 then
        table.Empty(self.m_ClickList[1])
        table.remove(self.m_ClickList, 1)
    end

    BaseClass.InsertClickableTextStart(self, value)
end

function PANEL:IsHovered()
    return BaseClass.IsHovered(self) or self:IsChildHovered()
end

function PANEL:Init()
    -- HACK: Initial init fails when subclassed
    if self._vertScrollBar and self._vertScrollBar:IsValid() then
        self._vertScrollBar:Remove()
    end
    if self.m_pInterior and self.m_pInterior:IsValid() then
        self.m_pInterior:Remove()
    end
    BaseClass.Init(self)
    --  HACK: determine whether a clickable segment of text is being hovered or not
    self.m_ClickList = {}

    --self._InsertClickableTextStart = self._InsertClickableTextStart or self.InsertClickableTextStart -- original
    --self.InsertClickableTextStart = self.__InsertClickableTextStart -- override
    --self._IsHovered = self._IsHovered or self.IsHovered -- original
    --self.IsHovered = self.__IsHovered -- override
end


PANEL.m_NextThinkHover = 0
function PANEL:Think()
    BaseClass.Think(self)

    local curtime = RealTime()
    if self.m_NextThinkHover <= curtime then
        self.m_NextThinkHover = curtime + 0.1
        self:ThinkClickableHover()
    end
end

function PANEL:ThinkClickableHover()
    if self.m_DirtyClickList then
        self.m_DirtyClickList = false
        self:CleanupDirtyClickList()
    end

    local hoveredPanel = vgui.GetHoveredPanel()

    if not hoveredPanel or (hoveredPanel:GetClassName() ~= "ClickPanel" and hoveredPanel:GetName() ~= "LuaClickPanel") then
        local signalValue = self.m_LastHoverSignalValue

        if signalValue then
            self.m_LastHoverSignalValue = nil
            self:OnTextHover(self.m_HoveredClickable, signalValue, false)
        end

        self.m_HoveredClickable = false

        return
    end

    if hoveredPanel:GetParent() ~= self then return end
    if self.m_HoveredClickable == hoveredPanel then return end
    self.m_HoveredClickable = hoveredPanel

    if self.m_LastHoverSignalValue then
        local signalValue = self.m_LastHoverSignalValue
        self.m_LastHoverSignalValue = nil
        self:OnTextHover(hoveredPanel, signalValue, false)
    end

    local signalValue = hoveredPanel.m_SignalValue
    if not signalValue then return end

    self.m_LastHoverSignalValue = signalValue
    self:OnTextHover(hoveredPanel, signalValue, true)
end

function PANEL:CleanupDirtyClickList()
    local data = self.m_ClickList[#self.m_ClickList]
    if not data then return end
    if not data.panel then return end -- haven't assigned all of them yet
    -- latest one has been assigned, the old ones stand no chance of being reassigned

    for i = 1, 1025 do
        data = self.m_ClickList[i]
        if not data then break end
        table.Empty(data)
    end

    table.Empty(self.m_ClickList)
end

function PANEL:ApplySchemeSettings()
    self:SetTextSelectionColors(
        LuaHudChat.GetSchemeColor("RichText.SelectedTextColor"),
        LuaHudChat.GetSchemeColor("RichText.SelectedBgColor"))

    self:SetFontInternal("ChatFont")
    self:SetUnderlineFont("ChatFont")--self:SetUnderlineFont("ChatFont_Underline")

    self:SetBGColor(LuaHudChat.GetSchemeColor("RichText.BgColor"))
    self:SetFGColor(LuaHudChat.GetSchemeColor("RichText.TextColor"))
end

--function PANEL:PerformLayout(w,h)
--	if self:GetFont() ~= "ChatFont" then
--		--self:SetFontInternal("ChatFont")
--		--self:SetUnderlineFont("ChatFont")
--	end
--
--	-- why dont you respect ApplySchemeSettings
--	--self:SetBGColor(LuaHudChat.GetSchemeColor("RichText.BgColor"))
--	--self:SetFGColor(LuaHudChat.GetSchemeColor("RichText.TextColor"))
--end

function PANEL:OnChildAdded(clickpanel)
    if clickpanel:GetClassName() == "ClickPanel" then
        local now = RealTime()
        if table.IsEmpty(self.m_ClickList) then return end

        local data = self.m_ClickList[#self.m_ClickList]
        if not data or table.IsEmpty(data) then return end

        local old_panel = data.panel
        data.panel = clickpanel
        clickpanel.m_ClickData = data
        clickpanel.m_SignalValue = data.signalValue

        self.m_DirtyClickList = true

        -- shift previous entries
        local prevData = data.prev
        for i = 1, 1024 do
            if not IsValid(old_panel) then break end
            clickpanel = old_panel

            data = prevData
            if not data or table.IsEmpty(data) then return end

            old_panel = data.panel
            data.panel = clickpanel
            clickpanel.m_ClickData = data
            clickpanel.m_SignalValue = data.signalValue

            prevData = data.prev
        end

        self:OnClickableTextAdded(clickpanel, data.signalValue)
    end
end

function PANEL:OnClickableTextAdded(panel, signalValue)
    print("ClickableTextAdded", panel, signalValue)
    if string.sub(signalValue, 1, 7) == "Player:" then
        local sid64 = string.sub(signalValue, 8)
        --local ply = player.GetBySteamID64(sid64)
        panel:SetTooltip("STEAMID64: " .. sid64)
    elseif string.sub(signalValue, 1, 4) == "Model:" then
        local modelPath = string.sub(signalValue, 6)
        panel:SetTooltip("Model: " .. modelPath)
    end
end

function PANEL:OnTextHover(panel, signalValue, isHovered)
    if string.sub(signalValue, 1, 7) == "Player:" then
        --
    else
        --print("RichText:OnTextHovered()", self, panel, signalValue, isHovered)
    end
end

function PANEL:OnTextClicked(id)
    local panel = self.m_HoveredClickable
    if not (panel and panel:IsValid()) then return end

    local chatPanel = self:GetParent()

    if string.sub(id, 1, 7) == "Player:" then
        local sid64 = string.sub(id, 8)
        local ply = player.GetBySteamID64(sid64)

        local menu = DermaMenu(true, panel)
        local x,y = panel:LocalToScreen(0, panel:GetTall())
        menu:AddOption("Copy SteamID64", function()
            SetClipboardText(sid64)
        end)
        menu:AddOption("View Profile", function()
            gui.OpenURL(string.format("https://steamcommunity.com/profiles/%s", sid64))
        end)
        menu:Open(x, y)

        chatPanel.m_CurrentContextMenu = menu

        chatPanel.m_ChatInput:RequestFocus()
    elseif string.sub(id, 1, 6) == "Model:" then
        local modelPath = string.sub(id, 7)
        local menu = DermaMenu(true, panel)
        local x,y = panel:LocalToScreen(0, panel:GetTall())
        menu:AddOption("Copy Model", function()
            SetClipboardText(modelPath)
        end)
        menu:Open(x, y)

        chatPanel.m_CurrentContextMenu = menu

        chatPanel.m_ChatInput:RequestFocus()
    else
        print("unhandled RichText clickable", self, id)
    end
end

function PANEL:AppendPlayerText(plyName, steamID64, nameColor, fadeTime)
    local r,g,b = nameColor:Unpack()
    self:InsertColorChange(r, g, b, 255)

    local bIsPlayer = steamID64 and steamID64 ~= ""
    local bAllowClickableText = bIsPlayer and text_clickable:GetBool()

    local name = plyName or "Console"

    if bAllowClickableText then
        self:InsertClickableTextStart("Player:"..steamID64)
    end
    self:AppendText(name)
    self:InsertFade(fadeTime, LuaHudChat._CHAT_HISTORY_IDLE_FADE_TIME)
    if bAllowClickableText then
        self:InsertClickableTextEnd()
    end
end

vgui.Register("LuaHudChatHistory", PANEL, "LuaRichText")
--vgui.Register("LuaHudChatHistory", PANEL, "RichText")
