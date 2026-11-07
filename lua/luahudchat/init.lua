local KeyValuesHelper = include("luahudchat/classes/keyvalues.lua")

LuaHudChat = LuaHudChat or {}

local text_clickable = CreateConVar("hud_saytext_clickable", "1", FCVAR_ARCHIVE, "Allows portions of text in chat to be clicked")

include("panels/luarichtext.lua")
include("panels/hudchathistory.lua")
include("panels/hudchatfiltercheckbox.lua")
include("panels/hudchatfilterpanel.lua")
include("panels/hudchatinputline.lua")
include("panels/hudchat.lua")

local cl_chatfilters = GetConVar("cl_chatfilters")
local hud_saytext_time = GetConVar("hud_saytext_time")

LuaHudChat._CHAT_HISTORY_ALPHA = 127
LuaHudChat._CHAT_HISTORY_IDLE_FADE_TIME = 2.5

local CHAT_INTERFACE_LINES = 6

-- "format string" with special handling of %s; %s1, %s2, etc will be replaced with passed vargs
-- allows translation strings to move around specific vars without breaking grammar in languages
function LuaHudChat.ConstructStringReplace(fmt, ...)
	local nargs = select("#", ...)
	if nargs > 9 then return end
	local args = {...}

	return string.gsub(fmt, "%%s([1-9])", function(numStr)
		local argIndex = tonumber(numStr)
		if argIndex and argIndex >= 1 and argIndex <= nargs then
			return tostring(args[argIndex])
		end
	end)
end

CHAT_TEXT_COLOR_NORMAL = 1
CHAT_TEXT_COLOR_USEOLDCOLORS = 2
CHAT_TEXT_COLOR_PLAYERNAME = 3
CHAT_TEXT_COLOR_LOCATION = 4
CHAT_TEXT_COLOR_ACHIEVEMENT = 5
CHAT_TEXT_COLOR_CUSTOM = 6			-- Will use the most recently SetCustomColor()
CHAT_TEXT_COLOR_HEXCODE = 7			-- Reads the color from the next six characters
CHAT_TEXT_COLOR_HEXCODE_ALPHA = 8	-- Reads the color and alpha from the next eight characters
CHAT_TEXT_COLOR_MAX = 9

--local COLOR_CHAT_DARKGREEN = Color(64, 255, 64, 255)
--local COLOR_CHAT_GREEN = Color(153, 255, 153, 255)
--local COLOR_CHAT_YELLOW = Color(255, 178, 0, 255)

local COLOR_CHAT_DEFAULT = Color(150, 210, 255, 255)	-- 0xFFFFD296
local COLOR_CHAT_SERVERMSG = Color(150, 210, 255, 255)	-- 0xFFFFD296
local COLOR_CHAT_JOINLEAVE = Color(160, 255, 160, 255)	-- 0xFFA0FFA0
local COLOR_CHAT_NAMECHANGE = Color(240, 190, 80, 255)	-- 0xFF50BEF0

local COLOR_CHAT_WHITE = Color(250, 250, 250, 255)		-- 0xFFFAFAFA
local COLOR_CHAT_GRAY = Color(210, 210, 210, 255)		-- 0xFFD2D2D2

--local COLOR_CHAT_DEAD = Color(255, 30, 40, 255)
--local COLOR_CHAT_TEAM = Color(30, 160, 40, 255)

--local function HexToColor(hex)
--	local r = bit.band(hex, 0xff)
--	local g = bit.band(bit.rshift(hex, 8), 0xff)
--	local b = bit.band(bit.rshift(hex, 16), 0xff)
--	local a = bit.band(bit.rshift(hex, 24), 0xff)
--	return Color(r, g, b, a)
--end
--local COLOR_MYSTERY = HexToColor(0xFFFFD296)
--MsgC(COLOR_MYSTERY, "█\n")

LuaHudChat.ChatControlSettings = swl4d.KeyValuesHelper(file.Read("resource/ui/BaseChat.res", "GAME"), nil, true)
LuaHudChat.ChatFilterControlSettings = swl4d.KeyValuesHelper(file.Read("resource/ui/chatfilters.res", "GAME"), nil, true)

LuaHudChat.ChatScheme = swl4d.KeyValuesHelper(file.Read("resource/ChatScheme.res", "GAME"), nil, true)
LuaHudChat.SchemeColors = LuaHudChat.ChatScheme:GetSubKeyInsensitive("colors")
LuaHudChat.SchemeBaseSettings = LuaHudChat.ChatScheme:GetSubKeyInsensitive("basesettings")

LuaHudChat.SchemeBorders = LuaHudChat.ChatScheme:GetSubKeyInsensitive("borders")

LuaHudChat.ChatSettings = LuaHudChat.ChatControlSettings:GetSubKeyInsensitive("hudchat")
LuaHudChat.ChatFiltersSettings = LuaHudChat.ChatControlSettings:GetSubKeyInsensitive("chatfiltersbutton")
LuaHudChat.ChatInputLineSettings = LuaHudChat.ChatControlSettings:GetSubKeyInsensitive("chatinputline")
LuaHudChat.ChatHistorySettings = LuaHudChat.ChatControlSettings:GetSubKeyInsensitive("hudchathistory")
LuaHudChat.ChatFilterSettings = LuaHudChat.ChatFilterControlSettings:GetSubKeyInsensitive("hudchatfilterpanel")

LuaHudChat.filter1Settings = LuaHudChat.ChatFilterControlSettings:GetSubKeyInsensitive("joinleave_button")
LuaHudChat.filter2Settings = LuaHudChat.ChatFilterControlSettings:GetSubKeyInsensitive("namechange_button")
LuaHudChat.filter3Settings = LuaHudChat.ChatFilterControlSettings:GetSubKeyInsensitive("publicchat_button")
LuaHudChat.filter4Settings = LuaHudChat.ChatFilterControlSettings:GetSubKeyInsensitive("servermsg_button")
LuaHudChat.filter5Settings = LuaHudChat.ChatFilterControlSettings:GetSubKeyInsensitive("teamchange_button")
LuaHudChat.filter6Settings = LuaHudChat.ChatFilterControlSettings:GetSubKeyInsensitive("achivement_button")
LuaHudChat.filter7Settings = LuaHudChat.ChatFilterControlSettings:GetSubKeyInsensitive("profanity_button")

surface.CreateFont("ChatFont_Underline", { -- "ChatFont" "4"
	name = "Verdana",
	--underline = true,
	shadow = true,
	weight = 700,
	size = 17,
	antialias = false,
})

surface.CreateFont("Default_HL2", {
    font = "Verdana",
    extended = false,
    size = 16,
    weight = 0,
    antialias = true,
})

--surface.CreateFont("Marlett_ScrollBar", {
--    font = "Marlett",
--    extended = true,
--    size = 17,
--    weight = 0,
--    antialias = false,
--})

CHAT_FILTER_NONE		= 0
CHAT_FILTER_JOINLEAVE	= 0x1
CHAT_FILTER_NAMECHANGE	= 0x2
CHAT_FILTER_PUBLICCHAT	= 0x4
CHAT_FILTER_SERVERMSG	= 0x8
CHAT_FILTER_TEAMCHANGE	= 0x10
CHAT_FILTER_ACHIEVEMENT	= 0x20
CHAT_FILTER_PROFANITY	= 0x40

MESSAGEMODE_NONE		= 0
MESSAGEMODE_SAY			= 1
MESSAGEMODE_SAY_TEAM	= 2

function LuaHudChat.GetSchemeColor(input, defaultColor)
	if isstring(input) then
		local color = LuaHudChat.SchemeBaseSettings:GetString(input)
		if not color then
			color = LuaHudChat.SchemeColors:GetString(input)
		else
			local r,g,b,a = string.match(color, "(%d+)%s*(%d+)%s*(%d+)%s*(%d*)")
			if r and g and b then
				return Color(tonumber(r), tonumber(g), tonumber(b), tonumber(a) or 255)
			end

			color = LuaHudChat.SchemeColors:GetString(color)
		end

		if color then
			local namedColor = NamedColor(color)
			if namedColor then
				return namedColor
			end
		else
			--print("PARSE???", input, color)
		end
	end

	return defaultColor
end

local function ParseSideSettings(border, side, data)
    if not data then return end

    side.lines = {}

    local index = 1
    for _, kv in data:IterSubKeys() do
        local line = {}

        -- this is the color name, get that from the color table
        local col = kv:GetString("color")
        line.col = LuaHudChat.GetSchemeColor(col, Color(0,0,0,0))


        col = kv:GetString("offset")
        if col then
            col = string.Split(col, " ")
            local Start, End = 0, 0
            Start = tonumber(col[1]) or Start
            End = tonumber(col[2]) or End
            line.startOffset = Start
            line.endOffset = End
        end

        side.lines[index] = line
        index = index + 1
    end
end

LuaHudChat.Borders = {}
for name, data in LuaHudChat.SchemeBorders:IterSubKeys() do
    local border = {
        sides = {
            left = {},
            top = {},
            right = {},
            bottom = {},
        },
        backgroundType = data:GetInt("backgroundtype"),
    }

    local insetLeft,insetTop,insetRight,insetBottom = 0,0,0,0
    local insetString = data:GetString("inset", "0 0 0 0")

    local insetValues = string.Split(insetString, " ")
    insetLeft = tonumber(insetValues[1]) or insetLeft
    insetTop = tonumber(insetValues[2]) or insetTop
    insetRight = tonumber(insetValues[3]) or insetRight
    insetBottom = tonumber(insetValues[4]) or insetBottom

    border.insetLeft = insetLeft
    border.insetTop = insetTop
    border.insetRight = insetRight
    border.insetBottom = insetBottom

    ParseSideSettings(border, border.sides.left, data:GetSubKey("Left"))
    ParseSideSettings(border, border.sides.top, data:GetSubKey("Top"))
    ParseSideSettings(border, border.sides.right, data:GetSubKey("Right"))
    ParseSideSettings(border, border.sides.bottom, data:GetSubKey("Bottom"))

    LuaHudChat.Borders[name] = border
end

function LuaHudChat.PaintBorder(borderName, x,y, w,h)
    local border = LuaHudChat.Borders[borderName]

    for i, line in ipairs(border.sides.left.lines) do
        i = i - 1
        -- breakside??
        surface.SetDrawColor(line.col)
        surface.DrawRect(x + i, y + line.startOffset, x + i + 1, h - line.endOffset)
    end

    for i, line in ipairs(border.sides.top.lines) do
        i = i - 1
        -- breakside??
        surface.SetDrawColor(line.col)
        surface.DrawRect(x + line.startOffset, y + i, w - line.endOffset, y + i + 1)
    end

    for i, line in ipairs(border.sides.right.lines) do
        i = i - 1
        surface.SetDrawColor(line.col)
        surface.DrawRect(w - (i+1), y + line.startOffset, i + 1, h - line.endOffset)
    end

    for i, line in ipairs(border.sides.bottom.lines) do
        i = i - 1
        surface.SetDrawColor(line.col)
        surface.DrawRect(x + line.startOffset, h - (i+1), w - line.endOffset, i + 1)
    end
end

local autorefresh_recreate = false
if LuaChatPanel and LuaChatPanel:IsValid() then
	LuaChatPanel:Remove()
	LuaChatPanel = nil
	autorefresh_recreate = true
elseif LuaChatPanel and not LuaChatPanel:IsValid() then
	LuaChatPanel = nil
	autorefresh_recreate = true
end

local function CreateChatPanel()
	LuaChatPanel = LuaChatPanel or vgui.Create("LuaHudChat")
	if LuaChatPanel and LuaChatPanel:IsValid() then
		LuaChatPanel:ParentToHUD()
		--LuaChatPanel:SetVisible(false)
	end
end
if autorefresh_recreate then
	CreateChatPanel()
else
	hook.Add("CreateTeams", "LuaHudChat", CreateChatPanel)
end

-- handle opening & closing
hook.Add("PlayerBindPress", "LuaHudChat", function(ply, bind, pressed, code)
	local messageMode = MESSAGEMODE_NONE
	if pressed and not (input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT)) then
		if bind == "messagemode" then
			messageMode = MESSAGEMODE_SAY
		elseif bind == "messagemode2" then
			messageMode = MESSAGEMODE_SAY_TEAM
		end
	end

	if messageMode ~= MESSAGEMODE_NONE then
		if LuaChatPanel and LuaChatPanel:IsValid() then
			LuaChatPanel:StartMessageMode(messageMode)
			return true
		end
	end
end)

hook.Add("OnPauseMenuShow", "LuaHudChat", function()
	if LuaChatPanel and LuaChatPanel:IsValid() then
		if LuaChatPanel:IsMouseInputEnabled() then
			LuaChatPanel:StopMessageMode()
			return false
		end
	end
end)

-- hide default chatbox entirely
hook.Remove("HUDShouldDraw", "LuaHudChat", function(name)
	if name == "CHudChat" and LuaChatPanel and LuaChatPanel:IsValid() then
		return false
	end
end)

-- detour chat library
chat._Open = chat._Open or chat.Open
chat._Close = chat._Close or chat.Close
chat._GetChatBoxSize = chat._GetChatBoxSize or chat.GetChatBoxSize
chat._GetChatBoxPos = chat._GetChatBoxPos or chat.GetChatBoxPos
chat._AddText = chat._AddText or chat.AddText

function chat.Open(mode)
	if LuaChatPanel and LuaChatPanel:IsValid() then
		if mode == MESSAGEMODE_SAY then
			LuaChatPanel:StartMessageMode(mode)
		else
			LuaChatPanel:StartMessageMode(MESSAGEMODE_SAY_TEAM)
		end
	else
		chat._Open(mode)
	end
end

function chat.Close()
	if LuaChatPanel and LuaChatPanel:IsValid() then
		LuaChatPanel:StopMessageMode()
	else
		chat._Close()
	end
end

function chat.GetChatBoxSize()
	if LuaChatPanel and LuaChatPanel:IsValid() then
		return LuaChatPanel:GetSize()
	else
		return chat._GetChatBoxSize()
	end
end

function chat.GetChatBoxPos()
	if LuaChatPanel and LuaChatPanel:IsValid() then
		return LuaChatPanel:GetPos()
	else
		return chat._GetChatBoxPos()
	end
end

function chat.AddText(...)
	if LuaChatPanel and LuaChatPanel:IsValid() then
		local saytextFadeTime = hud_saytext_time:GetFloat()
		local history = LuaChatPanel:GetChatHistory()

		local r,g,b = COLOR_CHAT_DEFAULT:Unpack()
		history:InsertColorChange(r,g,b, 255)

		local nvargs = select("#", ...)
		for i = 1, nvargs do
			local v = select(i, ...)

			if istable(v) then
				r,g,b = v.r or 255, v.g or 255, v.b or 255
				history:InsertColorChange(r,g,b, 255)
			elseif isstring(v) or isnumber(v) then
				local str = tostring(v)

				--local foundClickable = false
				if text_clickable:GetBool() then
					local i1, i2 = string.find(str, "[%w_/]+%.mdl")
					if i1 then
						local modelPath = string.sub(str, i1, i2)
						--foundClickable = true

						history:AppendText(string.sub(str, 1, i1 - 1))
						history:InsertFade(saytextFadeTime, LuaHudChat._CHAT_HISTORY_IDLE_FADE_TIME)

						history:InsertClickableTextStart("Model:"..modelPath)
						history:AppendText(modelPath)
						history:InsertFade(saytextFadeTime, LuaHudChat._CHAT_HISTORY_IDLE_FADE_TIME)
						history:InsertClickableTextEnd()

						history:AppendText(string.sub(str, i2 + 1))
						history:InsertFade(saytextFadeTime, LuaHudChat._CHAT_HISTORY_IDLE_FADE_TIME)
					else
						history:AppendText(str)
						history:InsertFade(saytextFadeTime, LuaHudChat._CHAT_HISTORY_IDLE_FADE_TIME)
					end
				else
					history:AppendText(str)
					history:InsertFade(saytextFadeTime, LuaHudChat._CHAT_HISTORY_IDLE_FADE_TIME)
				end
			elseif isentity(v) then
				if v:IsPlayer() then
					local color = hook.Run("GetTeamColor", v)
					color = color or COLOR_CHAT_DEFAULT
					history:AppendPlayerText(v:Nick(), v:SteamID64(), color, saytextFadeTime)
					history:InsertColorChange(r,g,b, 255)
				else
					local str = v:IsValid() and v:GetClass() or "NULL"
					history:AppendText(str)
					history:InsertFade(saytextFadeTime, LuaHudChat._CHAT_HISTORY_IDLE_FADE_TIME)
				end
			else
				--print("arg", i, v)
			end
		end

		history:AppendText("\n")
		history:InsertFade(saytextFadeTime, LuaHudChat._CHAT_HISTORY_IDLE_FADE_TIME)
	end

	chat._AddText(...)
end

-- gmod's gamemode base OnPlayerChat formats text using chat.AddText
-- so we don't need to do this ourselves
--hook.Add("OnPlayerChat", "LuaHudChat", function(ply, text, team, dead)
--	local chatPanel = LuaChatPanel
--	if not (chatPanel and chatPanel:IsValid()) then return end
--
--	chatPanel:ChatPrintF(ply:EntIndex(), CHAT_FILTER_PUBLICCHAT, text)
--end)

-- debug hooks
local hooks = {
	"StartChat",
	"ChatTextChanged",
	"OnChatTab",
	"FinishChat",

	"ChatText",
	"OnPlayerChat",
	"GetTeamColor",
}

for i, name in next, hooks do
	hook.Add(name, "test", function(...)
		print("HOOK:", name, ...)
	end)
end

gameevent.Listen("server_cvar")
gameevent.Listen("player_changename")
gameevent.Listen("player_connect_client")
gameevent.Listen("player_disconnect")
gameevent.Listen("achievement_earned")

hook.Add("server_cvar", "LuaHudChat", function(data)
	local chatPanel = LuaChatPanel
	if not (chatPanel and chatPanel:IsValid()) then return end

	local text = LuaHudChat.ConstructStringReplace(language.GetPhrase("#game_server_cvar_changed"), data.cvarname, data.cvarvalue)
	chatPanel:PrintF(CHAT_FILTER_SERVERMSG, text)
end)
hook.Add("player_changename", "LuaHudChat", function(data) -- i dont like this one
	local chatPanel = LuaChatPanel
	if not (chatPanel and chatPanel:IsValid()) then return end

	local history = chatPanel:GetChatHistory()
	if not (history and history:IsValid()) then return end

	local text = language.GetPhrase("#game_player_changed_name")

	local oldStart, oldEnd = string.find(text, "%s1", 1, true)
	local newStart, newEnd = string.find(text, "%s2", 1, true)

	if not (oldStart or newStart) then
		chatPanel:PrintF(CHAT_FILTER_NAMECHANGE, text)
		return
	end

	local firstStart, firstEnd, firstText, secondStart, secondEnd, secondText
	-- Determine the order of old and new names in the text
	if oldStart < newStart then
		firstText = data.oldname
		firstStart, firstEnd = oldStart, oldEnd
		secondText = data.newname
		secondStart, secondEnd = newStart, newEnd
	else
		firstText = data.newname
		firstStart, firstEnd = newStart, newEnd
		secondText = data.oldname
		secondStart, secondEnd = oldStart, oldEnd
	end

	local saytextFadeTime = hud_saytext_time:GetFloat()
	local r, g, b = COLOR_CHAT_NAMECHANGE:Unpack()
	if firstStart > 1 then
		history:InsertColorChange(r, g, b, 255)
		history:AppendText(string.sub(text, 1, firstStart - 1))
		history:InsertFade(saytextFadeTime, LuaHudChat._CHAT_HISTORY_IDLE_FADE_TIME)
	end

	local ply = Player(data.userid)
	local steamID64 = ply:SteamID64()
	history:AppendPlayerText(firstText, steamID64, COLOR_CHAT_NAMECHANGE, saytextFadeTime)

	history:InsertColorChange(r, g, b, 255)
	history:AppendText(string.sub(text, firstEnd + 1, secondStart - 1))
	history:InsertFade(saytextFadeTime, LuaHudChat._CHAT_HISTORY_IDLE_FADE_TIME)

	history:AppendPlayerText(secondText, steamID64, COLOR_CHAT_NAMECHANGE, saytextFadeTime)

	history:InsertColorChange(r, g, b, 255)
	history:AppendText(string.sub(text, secondEnd + 1) .. "\n")
	history:InsertFade(saytextFadeTime, LuaHudChat._CHAT_HISTORY_IDLE_FADE_TIME)
end)
hook.Add("player_connect_client", "LuaHudChat", function(data)
	local chatPanel = LuaChatPanel
	if not (chatPanel and chatPanel:IsValid()) then return end

	local history = chatPanel:GetChatHistory()
	if not (history and history:IsValid()) then return end

	local text = LuaHudChat.ConstructStringReplace(language.GetPhrase("#game_player_joined_game"), data.name)

	local nameStart, nameEnd = string.find(text, data.name, 1, true)
	if not nameStart then
		chatPanel:PrintF(CHAT_FILTER_JOINLEAVE, text)
		return
	end

	local saytextFadeTime = hud_saytext_time:GetFloat()
	local r, g, b = COLOR_CHAT_JOINLEAVE:Unpack()
	if nameStart > 1 then
		history:InsertColorChange(r, g, b, 255)
		history:AppendText(string.sub(text, 1, nameStart - 1))
		history:InsertFade(saytextFadeTime, LuaHudChat._CHAT_HISTORY_IDLE_FADE_TIME)
	end

	local ply = Player(data.userid)
	history:AppendPlayerText(data.name, util.SteamIDTo64(data.networkid), COLOR_CHAT_JOINLEAVE, saytextFadeTime)

	history:InsertColorChange(r, g, b, 255)
	history:AppendText(string.sub(text, nameEnd + 1) .. "\n")
	history:InsertFade(saytextFadeTime, LuaHudChat._CHAT_HISTORY_IDLE_FADE_TIME)
end)
hook.Add("player_disconnect", "LuaHudChat", function(data)
	local chatPanel = LuaChatPanel
	if not (chatPanel and chatPanel:IsValid()) then return end

	local history = chatPanel:GetChatHistory()
	if not (history and history:IsValid()) then return end

	local text = LuaHudChat.ConstructStringReplace(language.GetPhrase("#game_player_left_game"), data.name, data.reason)

	local nameStart, nameEnd = string.find(text, data.name, 1, true)
	if not nameStart then
		chatPanel:PrintF(CHAT_FILTER_JOINLEAVE, text)
		return
	end

	local saytextFadeTime = hud_saytext_time:GetFloat()
	local r, g, b = COLOR_CHAT_JOINLEAVE:Unpack()

	if nameStart > 1 then
		history:InsertColorChange(r, g, b, 255)
		history:AppendText(string.sub(text, 1, nameStart - 1))
		history:InsertFade(saytextFadeTime, LuaHudChat._CHAT_HISTORY_IDLE_FADE_TIME)
	end

	local ply = Player(data.userid)
	history:AppendPlayerText(data.name, util.SteamIDTo64(data.networkid), COLOR_CHAT_JOINLEAVE, saytextFadeTime)

	history:InsertColorChange(r, g, b, 255)
	history:AppendText(string.sub(text, nameEnd + 1) .. "\n")
	history:InsertFade(saytextFadeTime, LuaHudChat._CHAT_HISTORY_IDLE_FADE_TIME)
end)
--[[
hook.Add("achievement_earned", "LuaHudChat", function(data)
	local chatPanel = LuaChatPanel
	if not (chatPanel and chatPanel:IsValid()) then return end

	local history = chatPanel:GetChatHistory()
	if not (history and history:IsValid()) then return end

	local player = Player(data.player)
	if not (player and player:IsValid() and player:IsPlayer()) then return end

	local playerName = IsValid(player) and player:Nick() or "unconnected" 
	local text = LuaHudChat.ConstructStringReplace(language.GetPhrase("#achievement_earned"), playerName, achievements.GetName(data.achievement))
	chatPanel:PrintF(CHAT_FILTER_ACHIEVEMENT, text)
end)
--]]
