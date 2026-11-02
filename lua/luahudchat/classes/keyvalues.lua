-- make that a duplicate class in 4 projects

local META = {}
META.__index = META

local function PARSE_STRING(strInput)
	local inEscape, inString = false, false
	local name = {}

	for i = 1, #strInput do
		local char = string.sub(strInput, i, i)

		if inEscape then
			name[#name + 1] = char
			inEscape = false
			continue
		end

		if char == "\"" and not (inString or inEscape) then -- start string
			inString = true
		elseif char == "\\" then -- escape next char
			inEscape = true
			continue
		elseif inString and char == "\"" then -- end string
			name = table.concat(name)
			inString = false
			break
		elseif char == "\n" and not (inString or inEscape) then
			name = table.concat(name)
			break
		elseif inString then
			name[#name + 1] = char
		end
	end

	return name
end

-- accepts (KeyValues object), (KeyValuesHelper object), (KeyValues string, optional bool UsesEscapeSequences, optional bool PreserveKeyCase), or (string name)

---@param strInput string|table KeyValues string or KeyValues table
---@param escape boolean|nil Whether to use escape sequences (optional)
---@param case boolean|nil Whether to preserve key case (optional)
---@return KeyValuesHelper Parsed KeyValuesHelper object
local function KeyValuesHelper(strInput, escape, case)
	if istable(strInput) and getmetatable(strInput) == META then
		return strInput
	end

	local name = ""

	local KVs
	if istable(strInput) then
		if getmetatable(strInput.Value) == META then
			return strInput.Value
		end

		KVs = strInput.Value
		name = strInput.Key
	elseif isstring(strInput) then
		if #strInput == 0 then
			KVs = {}
		else
			-- extract root kv name from input, because util.KeyValuesToTable doesn't give us that

			local tLines = string.Split(strInput, "\n")
			if #tLines > 1 then
				for i, strLine in ipairs(tLines) do
					local line = string.Trim(strLine)

					-- comment
					if #line == 0 then continue end
					if string.find(line, "^//") then continue end

					if string.find(line, "\"") then
						name = PARSE_STRING(line)
					else
						name = line
					end

					break
				end

				if #name == 0 then
					KVs = {}
				end
			elseif #tLines == 1 then
				local line = string.Trim(tLines[1])
				if string.find(line, "^//") then
					name, KVs = "", {}
				else
					if string.find(line, "\"") then
						name = PARSE_STRING(line)
					else
						name, KVs = line, {}
					end
				end
			end

			if not KVs then
				KVs = util.KeyValuesToTablePreserveOrder(strInput, escape, case)
			end
		end
	else
		return
	end

	local keys = {}
	local keys_ordinal = {}
	local keys_types = {}
	local iSub -- index of first subkey
	local iVal -- index of first value

	for i, KV in ipairs(KVs) do
		local key = KV.Key
		if istable(KV.Value) then
			if not iSub then
				iSub = i
			end

			KV.Value = KeyValuesHelper(KV)
			keys_types[i] = KV_TYPE_NONE
		else
			if not iVal then
				iVal = i
			end

			keys_types[i] = KV_TYPE_STRING

			if isnumber(KV.Value) then
				if math.floor(KV.Value) == KV.Value then
					keys_types[i] = KV_TYPE_INT -- treat as int
				else
					keys_types[i] = KV_TYPE_FLOAT -- treat as float
				end
			end
		end

		keys[i] = key
		keys_ordinal[key] = i
	end

	return setmetatable({
		name = name,

		sub = iSub,
		val = iVal,
		keys_len = #keys,

		kv = KVs,
		keys = keys,
		keys_ord = keys_ordinal,
		keys_types = keys_types,
	}, META)
end

function META:__tostring()
	return ("KeyValuesHelper [%s]"):format(self.name)
end

local KV_TYPE_NONE = 0
local KV_TYPE_STRING = 1
local KV_TYPE_INT = 2
local KV_TYPE_FLOAT = 3
local KV_TYPE_NUM_TYPES = 4

AccessorFunc(META, "name", "Name", FORCE_STRING)

do -- getters/setters
	function META:FindKey(key)
		local index = self.keys_ord[key]
		if index then
			return self.kv[index].Value
		end

		return nil
	end

	function META:GetSubKey(key)
		local index = self.keys_ord[key]
		if index then
			local KeyVal = self.kv[index]

			if istable(KeyVal.Value) then
				return KeyVal.Value
			end
		end

		return nil
	end

	function META:GetSubKeyInsensitive(key)
		for k in next, self.keys_ord do
			if k:lower() == key then
				return self:GetSubKey(k)
			end
		end
	end

	function META:GetNextKey(key)
		local index = self.keys_ord[key]
		if index and index < self.keys_len and index > 0 then
			return self.kv[index + 1]
		end
	end

	function META:GetPreviousKey(key)
		local index = self.keys_ord[key]
		if index and index > 1 and index <= self.keys_len then
			return self.kv[index - 1]
		end
	end

	function META:GetString(key, default)
		local index = self.keys_ord[key]
		if index then
			return tostring(self.kv[index].Value)
		end

		return default
	end

	function META:GetBool(key, default)
		local index = self.keys_ord[key]
		if index then
			local val = self.kv[index].Value
			if tonumber(val) then
				return tonumber(val) ~= 0
			end
		end

		return default ~= nil and default or false
	end

	function META:GetInt(key, default)
		local index = self.keys_ord[key]
		if index then
			local val = self.kv[index].Value
			if val then
				return math.floor(tonumber(val) or default)
			end
		end

		return default
	end

	function META:GetFloat(key, default)
		local index = self.keys_ord[key]
		if index then
			local val = self.kv[index].Value
			if val then
				return tonumber(val) or default
			end
		end

		return default
	end

	function META:SetString(key, value)
		local index = self.keys_ord[key]
		if index then
			self.kv[index].Value = tostring(value)
			self.keys_types[index] = KV_TYPE_STRING
			return true
		elseif isstring(value) then
			-- create the non-existant key
			index = #self.keys + 1
			self.keys[index] = key
			self.keys_ord[key] = index
			self.keys_types[index] = KV_TYPE_STRING
			self.keys_len = self.keys_len + 1
			self.kv[index] = {Key = key, Value = tostring(value)}
			return true
		end

		return false
	end

	function META:SetBool(key, value)
		local index = self.keys_ord[key]
		if index then
			self.kv[index].Value = tobool(value) and 1 or 0
			self.keys_types[index] = KV_TYPE_INT
			return true
		elseif tonumber(value) then
			-- create the non-existant key
			index = #self.keys + 1
			self.keys[index] = key
			self.keys_ord[key] = index
			self.keys_types[index] = KV_TYPE_INT
			self.keys_len = self.keys_len + 1
			self.kv[index] = {Key = key, Value = tonumber(value) == 1 and 1 or 0}
			return true
		end

		return false
	end

	function META:SetInt(key, value)
		local index = self.keys_ord[key]
		if index then
			self.kv[index].Value = math.floor(tonumber(value) or 0)
			self.keys_types[index] = KV_TYPE_INT
			return true
		elseif tonumber(value) then
			-- create the non-existant key
			index = #self.keys + 1
			self.keys[index] = key
			self.keys_ord[key] = index
			self.keys_types[index] = KV_TYPE_INT
			self.keys_len = self.keys_len + 1
			self.kv[index] = {Key = key, Value = math.floor(tonumber(value))}
			return true
		end

		return false
	end

	function META:SetFloat(key, value)
		local index = self.keys_ord[key]
		if index then
			self.kv[index].Value = tonumber(value) or 0
			self.keys_types[index] = KV_TYPE_FLOAT
			return true
		elseif tonumber(value) then
			-- create the non-existant key
			index = #self.keys + 1
			self.keys[index] = key
			self.keys_ord[key] = index
			self.keys_types[index] = KV_TYPE_FLOAT
			self.keys_len = self.keys_len + 1
			self.kv[index] = {Key = key, Value = tostring(value)}
			return true
		end

		return false
	end

	function META:GetColor(key, default)
		local colStr = self:GetString(key)

		local r,g,b,a = 0,0,0,0
		if colStr then
			-- parse r,g,b,a from colStr; a is optional and may be omitted but defaults to 0
			r,g,b,a = colStr:match("^(%d+)%s+(%d+)%s+(%d+)%s*(%d*)$")
			r = tonumber(r) or 0
			g = tonumber(g) or 0
			b = tonumber(b) or 0
			a = tonumber(a) or 0
		elseif default then
			r, g, b, a = default:Unpack()
		else
			return
		end

		return Color(r, g, b, a)
	end

	function META:SetColor(key, value)
		if not IsColor(value) then return false end

		local r,g,b,a = value:Unpack()
		local index = self.keys_ord[key]
		if index then
			self.kv[index].Value = string.format("%d %d %d %d", r, g, b, a)
			self.keys_types[index] = KV_TYPE_STRING
			return true
		else
			-- create the non-existant key
			index = #self.keys + 1
			self.keys[index] = key
			self.keys_ord[key] = index
			self.keys_types[index] = KV_TYPE_STRING
			self.keys_len = self.keys_len + 1
			self.kv[index] = {Key = key, Value = string.format("%d %d %d %d", r, g, b, a)}
			return true
		end

		return false
	end

	-- accepts (KeyValuesHelper object), (name), (name, KeyValuesHelper object), or (name, firstKey, firstValue)
	function META:AddSubKey(name, firstKey, firstValue)
		local index = #self.keys + 1

		local subkey
		if istable(name) and getmetatable(name) == META then
			subkey = table.Copy(name)
			name = subkey.name
		elseif isstring(name) and firstKey then
			if istable(firstKey) and getmetatable(firstKey) == META then
				subkey = table.Copy(firstKey)
				subkey.name = name
			elseif isstring(firstKey) and firstValue then
				subkey = KeyValuesHelper({Key = name, Value = {{Key = firstKey, Value = firstValue}}})
			end
		else
			subkey = KeyValuesHelper("")
			subkey.name = name
		end

		self.keys[index] = name
		self.keys_ord[name] = index
		self.keys_types[index] = KV_TYPE_NONE
		self.keys_len = self.keys_len + 1

		self.kv[index] = {Key = name, Value = subkey}

		if not self.sub then
			self.sub = index
		end

		return subkey
	end
end

-- for use in for loops
function META:Iter()
	local i = 0
	local len = self.keys_len

	return function()
		i = i + 1
		if i > len then
			return nil
		end

		local KeyVal = self.kv[i]
		return KeyVal.Key, KeyVal.Value, i
	end
end

function META:IterSubKeys()
	local i = (self.sub or 0) - 1
	local len = self.keys_len
	local kv = self.kv

	return function()
		if i < 0 then return end

		repeat
			i = i + 1
		until i > len or istable(kv[i].Value)

		if i > len then
			return nil
		end

		local KeyVal = kv[i]
		return KeyVal.Key, KeyVal.Value, i
	end
end

function META:IterValues()
	local i = (self.val or 0) - 1
	local len = self.keys_len
	local kv = self.kv

	return function()
		if i < 0 then return end

		repeat
			i = i + 1
		until i > len or not istable(kv[i].Value)

		if i > len then
			return nil
		end

		local KeyVal = kv[i]
		return KeyVal.Key, KeyVal.Value, i
	end
end

function META:GetFirstSubKey()
	if self.sub and self.sub > 0 and self.sub <= self.keys_len then
		local KeyVal = self.kv[self.sub]
		if istable(KeyVal.Value) then
			return KeyVal.Value
		end
	end

	return nil
end

function META:GetFirstValue()
	if self.val and self.val > 0 and self.val <= self.keys_len then
		local KeyVal = self.kv[self.val]
		if not istable(KeyVal.Value) then
			return KeyVal.Value
		end
	end

	return nil
end

function META:print(_tabs)
	_tabs = _tabs or ""

	Msg(string.format("%s\"%s\"\n%s{\n", _tabs, self.name, _tabs))

	for k, v in self:Iter() do
		if getmetatable(v) == META then
			v:print(_tabs .. "\t")
		elseif isstring(v) then
			Msg(string.format("%s\t\"%s\"\t\t\"%s\"\n", _tabs, k, v))
		else
			Msg(string.format("%s\t\"%s\"\t\t%s\n", _tabs, k, v))
		end
	end

	Msg(string.format("%s\n%s}\n", _tabs, _tabs))
end

function META:tostring(_tabs)
	_tabs = _tabs or ""

	local str = {
		_tabs, "\"", self.name, "\"\n",
		_tabs, "{\n"
	}

	for k, v in self:Iter() do
		if getmetatable(v) == META then
			table.insert(str, v:tostring(_tabs .. "\t"))
		elseif isstring(v) then
			table.insert(str, string.format("%s\t\"%s\"\t\t\"%s\"\n", _tabs, k, v))
		else
			table.insert(str, string.format("%s\t\"%s\"\t\t%s\n", _tabs, k, v))
		end
	end

	table.insert(str, string.format("%s\n%s}\n", _tabs, _tabs))

	return table.concat(str, "")
end

function META:WriteToNet()
	local bytesWritten, bitsWritten = net.BytesWritten()
	if not bytesWritten then return end

	net.WriteUInt(0, 8)
	net.WriteString(self.name)

	for i = 1, self.keys_len do
		local kv = self.kv[i]
		local key = kv.Key
		local value = kv.Value

		local Type = self.keys_types[i]
		net.WriteUInt(Type, 8)
		net.WriteString(key)

		if Type == KV_TYPE_NONE then -- subkey
			value:WriteToNet()
		elseif Type == KV_TYPE_STRING then
			net.WriteString(value)
		elseif Type == KV_TYPE_INT then
			net.WriteInt(value, 32)
		elseif Type == KV_TYPE_FLOAT then
			net.WriteFloat(value)
		end
	end

	net.WriteUInt(KV_TYPE_NUM_TYPES, 8) -- end of keyvalues
end

function META:ReadFromNet()
	local bytesLeft, bitsLeft = net.BytesLeft()
	if not bytesLeft or bitsLeft < 8 then return end

	local Type = net.ReadUInt(8)
	if Type == KV_TYPE_NUM_TYPES then return end

	local name = net.ReadString()
	self.name = name

	while true do
		Type = net.ReadUInt(8)
		if Type == KV_TYPE_NUM_TYPES then
			break
		end

		local key = net.ReadString()
		local value

		if Type == KV_TYPE_NONE then -- subkey
			value = KeyValuesHelper("")
			value:ReadFromNet()
			self:AddSubKey(value)
		elseif Type == KV_TYPE_STRING then
			value = net.ReadString()
			self:SetString(key, value)
		elseif Type == KV_TYPE_INT then
			value = net.ReadInt(32)
			self:SetInt(key, value)
		elseif Type == KV_TYPE_FLOAT then
			value = net.ReadFloat()
			self:SetFloat(key, value)
		end
	end
end

return KeyValuesHelper
