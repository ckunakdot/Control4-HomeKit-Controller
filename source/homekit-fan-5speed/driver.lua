package.preload['commands'] = (function (...)

local PROXY, HUB = 5001, 999
local SPEEDS = 5
local AID
local TYPEMAP, IIDTYPE, STATE, META = {}, {}, {}, {}

local HK = { ON = "25", SPEED = "29", DIR = "28", ACTIVE = "B0", CURFAN = "AF", TGTFAN = "BF" }

local function norm(t) return (tostring(t):upper():gsub("^0+(%x)", "%1")) end
local function notify(cmd, p) C4:SendToProxy(PROXY, cmd, p, "NOTIFY") end
local function aidfmt(a) local n = tonumber(a); return n and string.format("%.0f", n) or tostring(a) end
local function to_hub(cmd, p) p = p or {}; p.aid = AID; C4:SendToProxy(HUB, cmd, p) end

local function set_iid_maps(map)
  TYPEMAP, IIDTYPE = {}, {}
  for t, iid in pairs(map or {}) do TYPEMAP[norm(t)] = iid; IIDTYPE[tonumber(iid) or iid] = norm(t) end
end

local function power_type() return TYPEMAP[HK.ACTIVE] and HK.ACTIVE or HK.ON end
local function is_on()
  local v = STATE[power_type()]
  return v == true or v == 1 or v == "1" or v == "true"
end

local function pct_to_speed(p)
  p = tonumber(p) or 0
  local s = math.floor(p * SPEEDS / 100 + 0.5)
  if s < 0 then s = 0 elseif s > SPEEDS then s = SPEEDS end
  return s
end
local function speed_to_pct(s)
  s = tonumber(s) or 0
  if s <= 0 then return 0 end
  if s >= SPEEDS then return 100 end
  return math.floor(s * 100 / SPEEDS + 0.5)
end

local ONLINE = false
local function mark_online()
  if not ONLINE then notify("ONLINE_CHANGED", { STATE = true }); ONLINE = true; dbg("fan -> ONLINE") end
end

local function current_speed()
  if not is_on() then return 0 end
  if TYPEMAP[HK.SPEED] and STATE[HK.SPEED] ~= nil then
    local s = pct_to_speed(STATE[HK.SPEED])
    if s == 0 then s = 1 end
    return s
  end
  return SPEEDS
end

local function reflect()
  if is_on() then notify("ON", {}) else notify("OFF", {}) end
  notify("CURRENT_SPEED", { SPEED = current_speed() })
end

local function apply(list)
  mark_online()
  for _, c in ipairs(list) do
    local t = IIDTYPE[c.iid] or IIDTYPE[tonumber(c.iid)]
    if t then STATE[t] = c.value end
  end
  reflect()
end

function DRV.OnDriverLateInit()
  AID = aidfmt(Properties and Properties["Accessory AID"] or "1")
  dbg("fan init, aid=" .. tostring(AID) .. " speeds=" .. SPEEDS)
  to_hub("HK_GET_STATE")
end
OPC["Accessory AID"] = function(v) AID = aidfmt(v); to_hub("HK_GET_STATE") end
GCPL.OnBindingChanged = function(idBinding, class, bIsBound)
  if tonumber(idBinding) == HUB and bIsBound then to_hub("HK_GET_STATE") end
end

function RFP.RECEIVE_DB(idBinding, tParams)
  if aidfmt(tParams.aid) ~= AID then return end
  local ok, map = pcall(function() return JSON:decode(tParams.data) end)
  if ok then
    set_iid_maps(map)
    dbg("got DB: power(" .. power_type() .. ") iid=" .. tostring(TYPEMAP[power_type()])
        .. " RotationSpeed iid=" .. tostring(TYPEMAP[HK.SPEED]))
    if TYPEMAP[HK.ON] or TYPEMAP[HK.ACTIVE] then mark_online(); reflect() end
  end
end
function RFP.RECEIVE_STATE(idBinding, tParams)
  if aidfmt(tParams.aid) ~= AID then return end
  local ok, l = pcall(function() return JSON:decode(tParams.data) end); if ok and l then apply(l) end
end
function RFP.RECEIVE_EVENT(idBinding, tParams)
  if aidfmt(tParams.aid) ~= AID then return end
  local ok, l = pcall(function() return JSON:decode(tParams.data) end); if ok and l then apply(l) end
end

local function power_value(on)
  if power_type() == HK.ACTIVE then return on and 1 or 0 end
  return on and true or false
end

local function fit(hk_type, v)
  local m = META[hk_type]
  if not m or type(v) ~= "number" then return v end
  if m.step and m.step > 0 then v = math.floor(v / m.step + 0.5) * m.step end
  v = math.floor(v * 1000 + 0.5) / 1000
  if m.min and v < m.min then v = m.min end
  if m.max and v > m.max then v = m.max end
  return v
end

local function write_chars(chars)
  for _, c in ipairs(chars) do
    local t = IIDTYPE[c.iid] or IIDTYPE[tonumber(c.iid)]
    if t then
      local snapped = fit(t, c.value)
      if snapped ~= c.value then
        dbg(("  %s: %s -> %s (accessory step=%s)"):format(tostring(t), tostring(c.value),
          tostring(snapped), tostring(META[t] and META[t].step)))
        c.value = snapped
      end
    end
  end
  to_hub("HK_SET_CHARS", { data = JSON:encode(chars) })
end

function RFP.RECEIVE_META(idBinding, tParams)
  if aidfmt(tParams.aid) ~= AID then return end
  local ok, m = pcall(function() return JSON:decode(tParams.data) end)
  if ok and m then
    META = {}
    for t, v in pairs(m) do META[norm(t)] = v end
    local rs = META[HK.SPEED]
    dbg("got META: RotationSpeed step=" .. tostring(rs and rs.step)
        .. " min=" .. tostring(rs and rs.min) .. " max=" .. tostring(rs and rs.max))
  end
end

local function set_on(on)
  local iid = TYPEMAP[power_type()]
  if iid then write_chars({ { iid = iid, value = power_value(on) } }) end
end

local function set_speed(sp)
  sp = tonumber(sp) or 0
  if sp <= 0 then set_on(false); return end
  if sp > SPEEDS then sp = SPEEDS end
  local piid, siid = TYPEMAP[power_type()], TYPEMAP[HK.SPEED]
  local chars = { { iid = piid, value = power_value(true) } }
  if siid then chars[#chars + 1] = { iid = siid, value = speed_to_pct(sp) } end
  write_chars(chars)
end

function RFP.ON()  dbg("proxy ON");  set_on(true) end
function RFP.OFF() dbg("proxy OFF"); set_on(false) end
function RFP.TOGGLE() dbg("proxy TOGGLE"); if is_on() then set_on(false) else set_on(true) end end

function RFP.SET_SPEED(idBinding, tParams)
  local sp = tonumber(tParams.SPEED) or 0
  dbg("proxy SET_SPEED " .. sp); set_speed(sp)
end
function RFP.CYCLE_SPEED_UP()
  local s = current_speed() + 1; if s > SPEEDS then s = SPEEDS end
  dbg("proxy CYCLE_SPEED_UP -> " .. s); set_speed(s)
end
function RFP.CYCLE_SPEED_DOWN()
  local s = current_speed() - 1; if s < 0 then s = 0 end
  dbg("proxy CYCLE_SPEED_DOWN -> " .. s); set_speed(s)
end
 end)

package.preload['Control4-HomeKit-Base.helpers'] = (function (...)
function DecodeValue(value, table)
    local options = {}
    for enum_val, name in pairs(table) do
        if BitwiseAnd(value, enum_val) ~= 0 then
            table.insert(options, name)
        end
    end
    return options
end

function BitwiseAnd(a, b)
    local result = 0
    local bitval = 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then
            result = result + bitval
        end
        bitval = bitval * 2
        a = math.floor(a / 2)
        b = math.floor(b / 2)
    end
    return result
end

function MapValue(oldValue, low, high)
    local newValue = ((oldValue * low) / high)

    return math.floor(newValue + 0.5)
end

function HasValue(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

function TablesMatch(a, b)
    return table.concat(a) == table.concat(b)
end


function ToCelsius(f)
    return (f - 32) * 5 / 9
end

function ToFahrenheit(c)
    return c * 9 / 5 + 32
end

 end)

package.preload['module.json'] = (function (...)
local COPYRIGHT = '2010-2011 Jeffrey Friedl'
local URL = 'http://regex.info/blog/'
local VERSION = 20111207.5
OBJDEF = {VERSION = VERSION, URL = URL, COPYRIGHT = COPYRIGHT}


local author =
	'-[ JSON.lua package by Jeffrey Friedl (http://regex.info/blog/lua/json), version ' .. tostring(VERSION) .. ' ]-'
local isArray = {__tostring = function()
		return 'JSON array'
	end}
isArray.__index = isArray
local isObject = {__tostring = function()
		return 'JSON object'
	end}
isObject.__index = isObject

function OBJDEF:newArray(tbl)
	return setmetatable(tbl or {}, isArray)
end

function OBJDEF:newObject(tbl)
	return setmetatable(tbl or {}, isObject)
end

local function unicode_codepoint_as_utf8(codepoint)
	if codepoint <= 127 then
		return string.char(codepoint)
	elseif codepoint <= 2047 then
		local highpart = math.floor(codepoint / 0x40)
		local lowpart = codepoint - (0x40 * highpart)
		return string.char(0xC0 + highpart, 0x80 + lowpart)
	elseif codepoint <= 65535 then
		local highpart = math.floor(codepoint / 0x1000)
		local remainder = codepoint - 0x1000 * highpart
		local midpart = math.floor(remainder / 0x40)
		local lowpart = remainder - 0x40 * midpart

		highpart = 0xE0 + highpart
		midpart = 0x80 + midpart
		lowpart = 0x80 + lowpart

		if
			(highpart == 0xE0 and midpart < 0xA0) or (highpart == 0xED and midpart > 0x9F) or
				(highpart == 0xF0 and midpart < 0x90) or
				(highpart == 0xF4 and midpart > 0x8F)
		then
			return '?'
		else
			return string.char(highpart, midpart, lowpart)
		end
	else
		local highpart = math.floor(codepoint / 0x40000)
		local remainder = codepoint - 0x40000 * highpart
		local midA = math.floor(remainder / 0x1000)
		remainder = remainder - 0x1000 * midA
		local midB = math.floor(remainder / 0x40)
		local lowpart = remainder - 0x40 * midB

		return string.char(0xF0 + highpart, 0x80 + midA, 0x80 + midB, 0x80 + lowpart)
	end
end

function OBJDEF:onDecodeError(message, text, location, etc)
	if text then
		if location then
			message = string.format('%s at char %d of: %s', message, location, text)
		else
			message = string.format('%s: %s', message, text)
		end
	end
	if etc ~= nil then
		message = message .. ' (' .. OBJDEF:encode(etc) .. ')'
	end

	print ('JSON decode error:' .. message)
end

OBJDEF.onDecodeOfNilError = OBJDEF.onDecodeError
OBJDEF.onDecodeOfHTMLError = OBJDEF.onDecodeError

function OBJDEF:onEncodeError(message, etc)
	if etc ~= nil then
		message = message .. ' (' .. OBJDEF:encode(etc) .. ')'
	end

	print ('JSON encode error:' .. message)
end

local function grok_number(self, text, start, etc)
	local integer_part = text:match('^-?[1-9]%d*', start) or text:match('^-?0', start)

	if not integer_part then
		self:onDecodeError('expected number', text, start, etc)
	end

	local i = start + integer_part:len()

	local decimal_part = text:match('^%.%d+', i) or ''

	i = i + decimal_part:len()

	local exponent_part = text:match('^[eE][-+]?%d+', i) or ''

	i = i + exponent_part:len()

	local full_number_text = integer_part .. decimal_part .. exponent_part


	local tonumber_loc = function(str, base)
		local s = str
		local num = tonumber(s, base)
		if (num == nil) then
			s = str:gsub('%.', ',')
			num = tonumber(s, base)
		end
		return num
	end

	local as_number = tonumber_loc(full_number_text)

	if not as_number then
		self:onDecodeError('bad number', text, start, etc)
	end

	return as_number, i
end

local function grok_string(self, text, start, etc)
	if text:sub(start, start) ~= '"' then
		self:onDecodeError("expected string's opening quote", text, start, etc)
	end

	local i = start + 1
	local text_len = text:len()
	local VALUE = ''
	while i <= text_len do
		local c = text:sub(i, i)
		if c == '"' then
			return VALUE, i + 1
		end
		if c ~= '\\' then
			VALUE = VALUE .. c
			i = i + 1
		elseif text:match('^\\b', i) then
			VALUE = VALUE .. '\b'
			i = i + 2
		elseif text:match('^\\f', i) then
			VALUE = VALUE .. '\f'
			i = i + 2
		elseif text:match('^\\n', i) then
			VALUE = VALUE .. '\n'
			i = i + 2
		elseif text:match('^\\r', i) then
			VALUE = VALUE .. '\r'
			i = i + 2
		elseif text:match('^\\t', i) then
			VALUE = VALUE .. '\t'
			i = i + 2
		else
			local hex =
				text:match(
				'^\\u([0123456789aAbBcCdDeEfF][0123456789aAbBcCdDeEfF][0123456789aAbBcCdDeEfF][0123456789aAbBcCdDeEfF])',
				i
			)
			if hex then
				i = i + 6

				local codepoint = tonumber(hex, 16)
				if codepoint >= 0xD800 and codepoint <= 0xDBFF then
					local lo_surrogate = text:match('^\\u([dD][cdefCDEF][0123456789aAbBcCdDeEfF][0123456789aAbBcCdDeEfF])', i)
					if lo_surrogate then
						i = i + 6
						codepoint = 0x2400 + (codepoint - 0xD800) * 0x400 + tonumber(lo_surrogate, 16)
					else
					end
				end
				VALUE = VALUE .. unicode_codepoint_as_utf8(codepoint)
			else
				VALUE = VALUE .. text:match('^\\(.)', i)
				i = i + 2
			end
		end
	end

	self:onDecodeError('unclosed string', text, start, etc)
end

local function skip_whitespace(text, start)
	local match_start, match_end = text:find('^[ \n\r\t]+', start)
	if match_end then
		return match_end + 1
	else
		return start
	end
end

local grok_one

local function grok_object(self, text, start, etc)
	if not text:sub(start, start) == '{' then
		self:onDecodeError("expected '{'", text, start, etc)
	end

	local i = skip_whitespace(text, start + 1)

	local VALUE = self.strictTypes and self:newObject {} or {}

	if text:sub(i, i) == '}' then
		return VALUE, i + 1
	end
	local text_len = text:len()
	while i <= text_len do
		local key, new_i = grok_string(self, text, i, etc)

		i = skip_whitespace(text, new_i)

		if text:sub(i, i) ~= ':' then
			self:onDecodeError('expected colon', text, i, etc)
		end

		i = skip_whitespace(text, i + 1)

		local val, new_i = grok_one(self, text, i)

		VALUE[key] = val

		i = skip_whitespace(text, new_i)

		local c = text:sub(i, i)

		if c == '}' then
			return VALUE, i + 1
		end

		if text:sub(i, i) ~= ',' then
			self:onDecodeError("expected comma or '}'", text, i, etc)
		end

		i = skip_whitespace(text, i + 1)
	end

	self:onDecodeError("unclosed '{'", text, start, etc)
end

local function grok_array(self, text, start, etc)
	if not text:sub(start, start) == '[' then
		self:onDecodeError("expected '['", text, start, etc)
	end

	local i = skip_whitespace(text, start + 1)
	local VALUE = self.strictTypes and self:newArray {} or {}
	if text:sub(i, i) == ']' then
		return VALUE, i + 1
	end

	local text_len = text:len()
	while i <= text_len do
		local val, new_i = grok_one(self, text, i)

		table.insert(VALUE, val)

		i = skip_whitespace(text, new_i)

		local c = text:sub(i, i)
		if c == ']' then
			return VALUE, i + 1
		end
		if text:sub(i, i) ~= ',' then
			self:onDecodeError("expected comma or '['", text, i, etc)
		end
		i = skip_whitespace(text, i + 1)
	end
	self:onDecodeError("unclosed '['", text, start, etc)
end

grok_one = function(self, text, start, etc)
	start = skip_whitespace(text, start)

	if start > text:len() then
		self:onDecodeError('unexpected end of string', text, nil, etc)
	end

	if text:find('^"', start) then
		return grok_string(self, text, start, etc)
	elseif text:find('^[-0123456789 ]', start) then
		return grok_number(self, text, start, etc)
	elseif text:find('^%{', start) then
		return grok_object(self, text, start, etc)
	elseif text:find('^%[', start) then
		return grok_array(self, text, start, etc)
	elseif text:find('^true', start) then
		return true, start + 4
	elseif text:find('^false', start) then
		return false, start + 5
	elseif text:find('^null', start) then
		return nil, start + 4
	else
		self:onDecodeError("can't parse JSON", text, start, etc)
	end
end

function OBJDEF:decode(text, etc)
	if type(self) ~= 'table' or self.__index ~= OBJDEF then
		OBJDEF:onDecodeError('JSON:decode must be called in method format', nil, nil, etc)
	end

	if text == nil then
		self:onDecodeOfNilError(string.format('nil passed to JSON:decode()'), nil, nil, etc)
	elseif type(text) ~= 'string' then
		self:onDecodeError(string.format('expected string argument to JSON:decode(), got %s', type(text)), nil, nil, etc)
	end

	if text:match('^%s*$') then
		return nil
	end

	if text:match('^%s*<') then
		self:onDecodeOfHTMLError(string.format('html passed to JSON:decode()'), text, nil, etc)
	end

	if text:sub(1, 1):byte() == 0 or (text:len() >= 2 and text:sub(2, 2):byte() == 0) then
		self:onDecodeError('JSON package groks only UTF-8, sorry', text, nil, etc)
	end

	local success, value = pcall(grok_one, self, text, 1, etc)
	if success then
		return value
	else
		print ('JSON decode panic:', value)
		return nil
	end
end

local function backslash_replacement_function(c)
	if c == '\n' then
		return '\\n'
	elseif c == '\r' then
		return '\\r'
	elseif c == '\t' then
		return '\\t'
	elseif c == '\b' then
		return '\\b'
	elseif c == '\f' then
		return '\\f'
	elseif c == '"' then
		return '\\"'
	elseif c == '\\' then
		return '\\\\'
	else
		return string.format('\\u%04x', c:byte())
	end
end

local chars_to_be_escaped_in_JSON_string =
	'[' ..
	'"' ..
		'%\\' .. -- class sub-pattern to match a backslash
			'%z' ..
				'\001' ..
					'-' ..
						'\031' ..
							']'

local function json_string_literal(value)
	local newval = value:gsub(chars_to_be_escaped_in_JSON_string, backslash_replacement_function)
	return '"' .. newval .. '"'
end

local function object_or_array(self, T, etc)
	local string_keys = {}
	local seen_number_key = false
	local maximum_number_key

	for key in pairs(T) do
		if type(key) == 'number' then
			seen_number_key = true
			if not maximum_number_key or maximum_number_key < key then
				maximum_number_key = key
			end
		elseif type(key) == 'string' then
			table.insert(string_keys, key)
		else
			self:onEncodeError("can't encode table with a key of type " .. type(key), etc)
		end
	end

	if seen_number_key and #string_keys > 0 then
		self:onEncodeError('a table with both numeric and string keys could be an object or array; aborting', etc)
	elseif #string_keys == 0 then
		if seen_number_key then
			return nil, maximum_number_key
		else
			if tostring(T) == 'JSON array' then
				return nil
			elseif tostring(T) == 'JSON object' then
				return {}
			else
				return nil
			end
		end
	else
		table.sort(string_keys)
		return string_keys
	end
end

local encode_value
function encode_value(self, value, parents, etc)
	if value == nil then
		return 'null'
	end

	if type(value) == 'string' then
		return json_string_literal(value)
	elseif type(value) == 'number' then
		if value ~= value then
			return 'null'
		elseif value >= math.huge then
			return '1e+9999'
		elseif value <= -math.huge then
			return '-1e+9999'
		else
			if value == math.floor(value) and value > -1e18 and value < 1e18 then
				return string.format("%.0f", value)
			end
			local ret = tostring (value)
			ret = ret:gsub ('%,', '%.')
			return ret
		end
	elseif type(value) == 'boolean' then
		return tostring(value)
	elseif type(value) ~= 'table' then
		self:onEncodeError("can't convert " .. type(value) .. ' to JSON', etc)
	else
		local T = value

		if parents[T] then
			self:onEncodeError('table ' .. tostring(T) .. ' is a child of itself', etc)
		else
			parents[T] = true
		end

		local result_value

		local object_keys, maximum_number_key = object_or_array(self, T, etc)
		if maximum_number_key then
			local ITEMS = {}
			for i = 1, maximum_number_key do
				table.insert(ITEMS, encode_value(self, T[i], parents, etc))
			end

			result_value = '[' .. table.concat(ITEMS, ',') .. ']'
		elseif object_keys then

			local PARTS = {}
			for _, key in ipairs(object_keys) do
				local encoded_key = encode_value(self, tostring(key), parents, etc)
				local encoded_val = encode_value(self, T[key], parents, etc)
				table.insert(PARTS, string.format('%s:%s', encoded_key, encoded_val))
			end
			result_value = '{' .. table.concat(PARTS, ',') .. '}'
		else
			result_value = '{}'
		end

		parents[T] = false
		return result_value
	end
end

local encode_pretty_value
function encode_pretty_value(self, value, parents, indent, etc)
	if type(value) == 'string' then
		return json_string_literal(value)
	elseif type(value) == 'number' then
		local ret = tostring (value)
		ret = ret:gsub ('%,', '%.')
		return ret
	elseif type(value) == 'boolean' then
		return tostring(value)
	elseif type(value) == 'nil' then
		return 'null'
	elseif type(value) ~= 'table' then
		self:onEncodeError("can't convert " .. type(value) .. ' to JSON', etc)
	else
		local T = value

		if parents[T] then
			self:onEncodeError('table ' .. tostring(T) .. ' is a child of itself', etc)
		end
		parents[T] = true

		local result_value

		local object_keys = object_or_array(self, T, etc)
		if not object_keys then
			local ITEMS = {}
			local subtable_indent = indent .. '  '
			local FORMAT = '%s%s'

			for i = 1, #T do

				local encoded_val = encode_pretty_value(self, T[i], parents, subtable_indent, etc)

				table.insert(ITEMS, string.format(FORMAT, subtable_indent, encoded_val))
			end

			result_value = '[\n' .. table.concat(ITEMS, ',\n') .. '\n' .. indent .. ']'
		else

			local KEYS = {}
			for _, key in ipairs(object_keys) do
				local encoded = encode_pretty_value(self, tostring(key), parents, '', etc)
				table.insert(KEYS, encoded)
			end
			local subtable_indent = indent .. '  '
			local FORMAT = '%s%s: %s'

			local COMBINED_PARTS = {}
			for i, key in ipairs(object_keys) do
				local encoded_val = encode_pretty_value(self, T[key], parents, subtable_indent, etc)
				table.insert(COMBINED_PARTS, string.format(FORMAT, subtable_indent, KEYS[i], encoded_val))
			end
			result_value = '{\n' .. table.concat(COMBINED_PARTS, ',\n') .. '\n' .. indent .. '}'
		end

		parents[T] = false
		return result_value
	end
end

function OBJDEF:encode(value, etc)
	if type(self) ~= 'table' or self.__index ~= OBJDEF then
		OBJDEF:onEncodeError('JSON:encode must be called in method format', etc)
	end

	local parents = {}
	return encode_value(self, value, parents, etc)
end

function OBJDEF:encode_pretty(value, etc)
	local parents = {}
	local subtable_indent = ''
	return encode_pretty_value(self, value, parents, subtable_indent, etc)
end

function OBJDEF.__tostring()
	return 'JSON encode/decode package'
end

OBJDEF.__index = OBJDEF

function OBJDEF:new(args)
	local new = {}

	if args then
		for key, val in pairs(args) do
			new[key] = val
		end
	end

	return setmetatable(new, OBJDEF)
end

return OBJDEF:new()

 end)

JSON = require("module.json")
local ok_helpers, helpers = pcall(require, "Control4-HomeKit-Base.helpers")
if ok_helpers then Helpers = helpers end

DRV = {}
EC  = {}
OPC = {}
RFP = {}
GCPL = {}
NOTIFY = {}

DEBUG = false
function dbg(...)
  if not DEBUG then return end
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
  local msg = table.concat(parts, " ")
  if C4 and C4.ErrorLog then C4:ErrorLog("[HomeKit] " .. msg) end
  print("[HomeKit] " .. msg)
end

require("commands")

function OnDriverInit()
  if DRV.OnDriverInit then DRV.OnDriverInit() end
end

function OnDriverLateInit(...)
  DEBUG = (Properties and Properties["Debug Mode"] == "On") or DEBUG
  if DRV.OnDriverLateInit then DRV.OnDriverLateInit(...) end
end

function OnDriverDestroyed(...)
  if DRV.OnDriverDestroyed then DRV.OnDriverDestroyed(...) end
end

function OnPropertyChanged(strProperty)
  local value = Properties[strProperty]
  if strProperty == "Debug Mode" then DEBUG = (value == "On") end
  local h = OPC[strProperty]
  if h then h(value) end
end

function ExecuteCommand(strCommand, tParams)
  tParams = tParams or {}
  if strCommand == "LUA_ACTION" and tParams.ACTION then strCommand = tParams.ACTION end
  local h = EC[strCommand]
  if h then return h(tParams) end
  dbg("Unhandled ExecuteCommand:", strCommand)
end

function ReceivedFromProxy(idBinding, strCommand, tParams)
  tParams = tParams or {}
  local h = RFP[strCommand]
  if h then return h(idBinding, tParams) end
  dbg("Unhandled ReceivedFromProxy:", strCommand)
end

function ReceivedFromProxyCommand(idBinding, strCommand, tParams)
  return ReceivedFromProxy(idBinding, strCommand, tParams)
end

function OnConnectionStatusChanged(idBinding, nPort, eStatus)
  if GCPL.OnConnectionStatusChanged then GCPL.OnConnectionStatusChanged(idBinding, nPort, eStatus) end
end

function OnBindingChanged(idBinding, class, bIsBound)
  if GCPL.OnBindingChanged then GCPL.OnBindingChanged(idBinding, class, bIsBound) end
end

function OnTimerExpired(idTimer)
  if DRV.OnTimerExpired then DRV.OnTimerExpired(idTimer) end
end

function ReceivedFromNetwork(idBinding, nPort, sData)
  if DRV.ReceivedFromNetwork then DRV.ReceivedFromNetwork(idBinding, nPort, sData) end
end

function OnNetworkConnectionStatusChanged(idBinding, nPort, strStatus)
  if DRV.OnNetworkConnectionStatusChanged then DRV.OnNetworkConnectionStatusChanged(idBinding, nPort, strStatus) end
end
