local PANEL = {}

function PANEL:ApplySchemeSettings()
    local color = LuaHudChat.GetSchemeColor("DullWhite", self:GetBGColor())
    local r,g,b,a = color:Unpack()
    self:SetBGColor(r,g,b, LuaHudChat._CHAT_HISTORY_ALPHA)

    self:SetFGColor(LuaHudChat.GetSchemeColor("Blank", self:GetFGColor()))

    --self.m_FontName = "ChatFont"
    --self:SetFontInternal("ChatFont")
end

local cl_chatfilters = GetConVar("cl_chatfilters")

local _ContentAlignment = {
    north = 8,
    east = 6,
    south = 2,
    west = 4,
    ["south-west"] = 1,
    ["south-east"] = 3,
    ["north-west"] = 7,
    ["north-east"] = 9,
    center = 5,
}
local function ApplyButtonControlSettings(panel, settings, filterFlag)
    if not settings then return end

    panel.m_FilterFlag = filterFlag

    local x,y = ScreenScaleH(settings:GetInt("xpos")), ScreenScaleH(settings:GetInt("ypos"))
    local w,h = ScreenScaleH(settings:GetInt("wide")), ScreenScaleH(settings:GetInt("tall"))
    panel:SetPos(x, y)
    panel:SetSize(w, h)

    local bEnabled = bit.band(cl_chatfilters:GetInt(), filterFlag) ~= 0
    panel:SetValue(bEnabled)

    function panel:OnChange(val)
        local curFilter = cl_chatfilters:GetInt()
        if val then
            curFilter = bit.bor(curFilter, filterFlag)
        else
            curFilter = bit.band(curFilter, bit.bnot(filterFlag))
        end

        print("chat filters changed", filterFlag, self:GetText(), val, curFilter)
        --cl_chatfilters:SetInt(curFilter)
        RunConsoleCommand("cl_chatfilters", tostring(math.floor(curFilter)))
    end

    local alignment = _ContentAlignment[settings:GetString("textAlignment")] or 5
    panel:SetContentAlignment(alignment)
    panel:SetText(settings:GetString("labelText"))
end

function PANEL:Init()
    self.joinleave = vgui.Create("DCheckBoxLabel", self, "joinleave_button")
    self.namechange = vgui.Create("DCheckBoxLabel", self, "namechange_button")
    self.publicchat = vgui.Create("DCheckBoxLabel", self, "publicchat_button")
    self.servermsg = vgui.Create("DCheckBoxLabel", self, "servermsg_button")
    self.teamchange = vgui.Create("DCheckBoxLabel", self, "teamchange_button")
    self.achivement = vgui.Create("DCheckBoxLabel", self, "achivement_button")
    self.profanity = vgui.Create("DCheckBoxLabel", self, "profanity_button")

    ApplyButtonControlSettings(self.joinleave, LuaHudChat.filter1Settings, CHAT_FILTER_JOINLEAVE)
    ApplyButtonControlSettings(self.namechange, LuaHudChat.filter2Settings, CHAT_FILTER_NAMECHANGE)
    ApplyButtonControlSettings(self.publicchat, LuaHudChat.filter3Settings, CHAT_FILTER_PUBLICCHAT)
    ApplyButtonControlSettings(self.servermsg, LuaHudChat.filter4Settings, CHAT_FILTER_SERVERMSG)
    ApplyButtonControlSettings(self.teamchange, LuaHudChat.filter5Settings, CHAT_FILTER_TEAMCHANGE)
    ApplyButtonControlSettings(self.achivement, LuaHudChat.filter6Settings, CHAT_FILTER_ACHIEVEMENT)
    ApplyButtonControlSettings(self.profanity, LuaHudChat.filter7Settings, CHAT_FILTER_PROFANITY)
end

function PANEL:Paint(w, h)
    local color = self:GetBGColor()
    draw.RoundedBox(6, 0, 0, w, h, color)
    return true
end

vgui.Register("LuaHudChatFilterPanel", PANEL, "EditablePanel")
