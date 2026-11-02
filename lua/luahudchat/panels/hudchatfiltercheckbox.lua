local PANEL = {}

function PANEL:Init()
    --
    self:SetPaintBorderEnabled(true)
    self:SetPaintBackgroundEnabled(true)
    self:SetPaintBackground(false)
end

vgui.Register("LuaHudChatFilterCheckbox", PANEL, "DButton")