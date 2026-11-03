local PANEL = {}

function PANEL:ApplySchemeSettings()
    self.m_Prompt:SetFont("ChatFont")
    self.m_Input:SetFont("ChatFont")

    self.m_Input:SetFGColor(
        LuaHudChat.GetSchemeColor(
            "Chat.TypingText",
            LuaHudChat.GetSchemeColor(
                "Panel.FgColor",
                Color(255,255,255,255))))

    self:SetPaintBackgroundEnabled(true)
    self.m_Prompt:SetPaintBackgroundEnabled(true)
    self.m_Prompt:SetContentAlignment(4)
    self.m_Prompt:SetTextInset(2, 0)

    self.m_Prompt:SetBGColor(LuaHudChat.GetSchemeColor("Label.BgColor"))
    self.m_Input:SetBGColor(LuaHudChat.GetSchemeColor("TextEntry.BgColor"))
    self.m_Input:SetFGColor(LuaHudChat.GetSchemeColor("TextEntry.TextColor"))

    self.m_Input:SetMouseInputEnabled(true)

    self:SetBGColor(0,0,0,0)
end

local function TextInput_OnKeyCodeTyped(self, code)
    self:OnKeyCode(code)

    --[[
    if code == KEY_ENTER and not self:IsMultiline() and self:GetEnterAllowed() then
        if IsValid(self.Menu) then
            self.Menu:Remove()
        end

        self:FocusNext()
        self:OnEnter(self:GetText())
        self.HistoryPos = 0
    end
    --]]

    if self.m_bHistory or IsValid(self.Menu) then
        if code == KEY_UP then
            self.HistoryPos = self.HistoryPos - 1
            self:UpdateFromHistory()
        elseif code == KEY_DOWN --[[or code == KEY_TAB]] then
            self.HistoryPos = self.HistoryPos + 1
            self:UpdateFromHistory()
        end
    end
end

local function TextInput_OnKeyCode(self, keycode)
    local hudChat = self.m_HudChat

    local text = self:GetText()
    --hook.Run("ChatTextChanged", text)

    if keycode == KEY_ENTER or keycode == KEY_PAD_ENTER then
        if hudChat and hudChat:IsValid() then
            --local textFinal = text ..
            if #text > 0 then
                self:AddHistory(text)
            end
            hudChat:Send()
            hudChat:StopMessageMode(self)
            return true
        end
    elseif keycode == KEY_ESCAPE then
        hudChat:StopMessageMode(self)
    elseif keycode == KEY_TAB then
        if hudChat:IsValid() then
            local newText = hook.Run("OnChatTab", hudChat.m_ChatInput:GetMessageText())
            if newText and isstring(newText) then
                hudChat.m_ChatInput:SetEntry(newText)
                self:SetCaretPos(#newText)
                timer.Simple(0, function()
                    self:RequestFocus()
                end)
                --return true
            end
        end
    end

    --local text = self:GetText()
    --hook.Run("ChatTextChanged", text)
end
local function TextInput_OnTextChanged(self)
    local text = self:GetText()
    hook.Run("ChatTextChanged", text)
end

function PANEL:Init()
    self.m_HudChat = self:GetParent()

    self:SetMouseInputEnabled(true)

    self.m_Prompt = vgui.Create("DLabel", self, "ChatInputPrompt")

    self.m_Input = vgui.Create("DTextEntry", self, "ChatInput")
    
    --self.m_Input:SetHighlightColor(LuaHudChat.GetSchemeColor("TextEntry.SelectedBgColor"))

    self.m_Input:SetTextSelectionColors(
        LuaHudChat.GetSchemeColor("RichText.SelectedTextColor"),
        LuaHudChat.GetSchemeColor("RichText.SelectedBgColor"))

    --function self.m_Input.ApplySchemeSettings(input)
    --	input:SetBGColor(LuaHudChat.GetSchemeColor("TextEntry.BgColor"))
    --end

    self.m_Input.m_HudChat = self.m_HudChat
    self.m_Input.OnKeyCode = TextInput_OnKeyCode
    self.m_Input.OnKeyCodeTyped = TextInput_OnKeyCodeTyped
    self.m_Input.OnTextChanged = TextInput_OnTextChanged
    self.m_Input:SetHighlightColor(LuaHudChat.GetSchemeColor("TextEntry.SelectedBgColor"))
    self.m_Input:SetHistoryEnabled(true)
    -- TODO: text selection colors??? because default doesnt do that
    self.m_Input:SetPaintBorderEnabled(true)
    self.m_Input:SetPaintBackgroundEnabled(true)
    self.m_Input:SetPaintBackground(false)
    self.m_Input:SetFont("ChatFont")
    self.m_Input:SetAllowNonAsciiCharacters(true)
    self.m_Input:SetDrawLanguageIDAtLeft(true)
    self.m_Input:SetMaximumCharCount(127) -- novus: DUMB!!!!!
end

function PANEL:PerformLayout(wide,tall)
    local w, h = self.m_Prompt:GetContentSize()

    local promptField = self.m_Prompt
    promptField:SetPos(0, 0)
    promptField:SetSize(w, h)

    local inputField = self.m_Input
    inputField:SetPos(w + 2, 0)
    inputField:SetSize(wide - w - 2, tall)

    -- why dont you respect ApplySchemeSettings
    --if promptField:GetFont() ~= "ChatFont" then promptField:SetFontInternal("ChatFont") end
    --if inputField:GetFont() ~= "ChatFont" then inputField:SetFontInternal("ChatFont") end

    --inputField:SetFGColor(LuaHudChat.GetSchemeColor("TextEntry.TextColor"))
end

function PANEL:GetInputPanel()
    return self.m_Input
end

function PANEL:GetMessageText()
    return self.m_Input:GetValue()
end

function PANEL:SetEntry(entry)
    self.m_Input:SetText(entry)
    self:InvalidateLayout()
end

function PANEL:ClearEntry()
    local text = self.m_Input:GetText()
    --if #text < 0 then
    --	hook.Run("ChatTextChanged", "")
    --end

    self:SetEntry("")
end

function PANEL:SetPrompt(prompt)
    self.m_Prompt:SetText(prompt)
    self:InvalidateLayout()
end

function PANEL:OnFocusChanged(gained)
    if gained then
        self.m_Input:RequestFocus()
    end
end

vgui.Register("LuaHudChatInputLine", PANEL, "Panel")
