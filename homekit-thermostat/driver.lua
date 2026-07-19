package.preload['commands'] = (function (...)

local PROXY, HUB = 5001, 999
local AID
local TYPEMAP, IIDTYPE, STATE, META = {}, {}, {}, {}
local SELECTED_SCALE = "FAHRENHEIT"
local HAS_HUMIDITY, HAS_FAN, ONLINE, IS_HC = false, false, false, false

local SENSOR_BINDING = 1
local HAS_REMOTE_SENSOR, REMOTE_TEMP_C, REMOTE_UNAVAIL = false, nil, false
local REMOTE_FORCED_OFF = false

local HK = {
  CUR_TEMP="11", TGT_TEMP="35", CUR_STATE="F", TGT_STATE="33",
  UNITS="36", HUM="10", HEAT_THRESH="12", COOL_THRESH="D",
  ACTIVE="B0", HC_CUR="B1", HC_TGT="B2",
  FAN_ACTIVE="B0", FAN_TGT="BF", FAN_CUR="AF", FAN_SPEED="29",
}
local MODE_TO_HK  = { Off=0, Heat=1, Cool=2, Auto=3 }
local HK_TO_MODE  = { [0]="Off", [1]="Heat", [2]="Cool", [3]="Auto" }
local HK_TO_STATE = { [0]="Off", [1]="Heating", [2]="Cooling" }
local MODE_TO_HC  = { Auto=0, Heat=1, Cool=2 }
local HC_TO_MODE  = { [0]="Auto", [1]="Heat", [2]="Cool" }
local HC_TO_STATE = { [0]="Off", [1]="Off", [2]="Heating", [3]="Cooling" }

local function norm(t)
  t = tostring(t):upper()
  if #t > 8 then return t end
  return (t:gsub("^0+(%x)", "%1"))
end
local function aidfmt(a) local n = tonumber(a); return n and string.format("%.0f", n) or tostring(a) end
local function notify(cmd, p) C4:SendToProxy(PROXY, cmd, p, "NOTIFY") end
local function to_hub(cmd, p) p = p or {}; p.aid = AID; C4:SendToProxy(HUB, cmd, p) end
local function c2f(c) return c * 9 / 5 + 32 end
local function f2c(f) return (f - 32) * 5 / 9 end

local function dispn(celsius)
  local c = tonumber(celsius); if not c then return nil end
  if SELECTED_SCALE == "FAHRENHEIT" then return math.floor(c2f(c) + 0.5) end
  return math.floor(c * 2 + 0.5) / 2
end
local function disp(celsius) local n = dispn(celsius); return n and tostring(n) or nil end

local function fit(hk_type, v)
  local m = META[hk_type]
  if not m then return v end
  if m.step and m.step > 0 then v = math.floor(v / m.step + 0.5) * m.step end
  v = math.floor(v * 1000 + 0.5) / 1000
  if m.min and v < m.min then v = m.min end
  if m.max and v > m.max then v = m.max end
  return v
end

local function write_char(hk_type, value)
  local iid = TYPEMAP[hk_type]
  if iid then
    if type(value) == "number" then
      local snapped = fit(hk_type, value)
      if snapped ~= value then
        dbg(("  %s: %s -> %s (accessory step=%s)"):format(tostring(hk_type), tostring(value),
          tostring(snapped), tostring(META[hk_type] and META[hk_type].step)))
      end
      value = snapped
    end
    to_hub("HK_SET_CHAR", { iid = tostring(iid), value = tostring(value) })
  else
    dbg(("NOT SENT: no iid for characteristic %s. Accessory AID=%s -- is that this "
      .. "accessory's aid (see Show Accessories on the hub), and is the hub bound/Connected?")
      :format(tostring(hk_type), tostring(AID)))
  end
end
local function write_chars(chars)
  if #chars == 0 then
    dbg(("NOT SENT: no iids resolved. Accessory AID=%s -- accessory DB not received?"):format(tostring(AID)))
    return
  end
  to_hub("HK_SET_CHARS", { data = JSON:encode(chars) })
end
local function write_units()
  if TYPEMAP[HK.UNITS] then write_char(HK.UNITS, (SELECTED_SCALE == "FAHRENHEIT") and "1" or "0") end
end

local function current_mode()
  if IS_HC then
    local act = tonumber(STATE[HK.ACTIVE])
    if act == 0 then return "Off" end
    return HC_TO_MODE[tonumber(STATE[HK.HC_TGT]) or 0] or "Auto"
  end
  return HK_TO_MODE[tonumber(STATE[HK.TGT_STATE]) or 0] or "Off"
end

local function current_state()
  if IS_HC then return HC_TO_STATE[tonumber(STATE[HK.HC_CUR]) or 0] or "Off" end
  return HK_TO_STATE[tonumber(STATE[HK.CUR_STATE]) or 0] or "Off"
end

local function send_caps()
  notify("DYNAMIC_CAPABILITIES_CHANGED", { HAS_HUMIDITY = HAS_HUMIDITY })
  notify("ALLOWED_HVAC_MODES_CHANGED", { MODES = "Off,Heat,Cool,Auto" })
  notify("ALLOWED_FAN_MODES_CHANGED", { MODES = HAS_FAN and "Auto,On" or "" })
  notify("ALLOWED_HOLD_MODES_CHANGED", { MODES = "Off" })
  notify("HOLD_MODE_CHANGED", { MODE = "Off" })
end

local function mark_online()
  if not ONLINE then
    ONLINE = true
    notify("CONNECTION", { CONNECTED = "true" })
    dbg("thermostat -> ONLINE")
  end
end

local setpoint_src_ro

local function report_fan()
  if not HAS_FAN then return end
  local tgt = tonumber(STATE[HK.FAN_TGT])
  if tgt ~= nil then notify("FAN_MODE_CHANGED", { MODE = (tgt == 1) and "Auto" or "On" }) end
  local cur = tonumber(STATE[HK.FAN_CUR])
  if cur ~= nil then notify("FAN_STATE_CHANGED", { STATE = (cur == 2) and "On" or "Off" }) end
end

local function report_all()
  local t = (HAS_REMOTE_SENSOR and REMOTE_TEMP_C) or STATE[HK.CUR_TEMP]
  if t ~= nil then notify("TEMPERATURE_CHANGED", { TEMPERATURE = disp(t), SCALE = SELECTED_SCALE }) end

  local h = tonumber(STATE[HK.HUM])
  if h ~= nil then
    if not HAS_HUMIDITY then HAS_HUMIDITY = true; notify("DYNAMIC_CAPABILITIES_CHANGED", { HAS_HUMIDITY = true }) end
    notify("HUMIDITY_CHANGED", { HUMIDITY = math.floor(h + 0.5) })
  end

  local mode = current_mode()
  notify("HVAC_MODE_CHANGED", { MODE = mode })
  notify("HVAC_STATE_CHANGED", { STATE = current_state() })

  if IS_HC then
    if STATE[HK.HEAT_THRESH] then notify("HEAT_SETPOINT_CHANGED", { SETPOINT = dispn(STATE[HK.HEAT_THRESH]), SCALE = SELECTED_SCALE }) end
    if STATE[HK.COOL_THRESH] then notify("COOL_SETPOINT_CHANGED", { SETPOINT = dispn(STATE[HK.COOL_THRESH]), SCALE = SELECTED_SCALE }) end
    local single = (mode == "Cool") and STATE[HK.COOL_THRESH] or STATE[HK.HEAT_THRESH]
    if single then notify("SINGLE_SETPOINT_CHANGED", { SETPOINT = dispn(single), SCALE = SELECTED_SCALE }) end
    report_fan()
    return
  end

  local hs = setpoint_src_ro("heat")
  local cs = setpoint_src_ro("cool")
  if hs and STATE[hs] ~= nil then notify("HEAT_SETPOINT_CHANGED", { SETPOINT = dispn(STATE[hs]), SCALE = SELECTED_SCALE }) end
  if cs and STATE[cs] ~= nil then notify("COOL_SETPOINT_CHANGED", { SETPOINT = dispn(STATE[cs]), SCALE = SELECTED_SCALE }) end
  if STATE[HK.TGT_TEMP] ~= nil then
    notify("SINGLE_SETPOINT_CHANGED", { SETPOINT = dispn(STATE[HK.TGT_TEMP]), SCALE = SELECTED_SCALE })
  end
  report_fan()
end

local function set_scale(s)
  if s ~= "FAHRENHEIT" and s ~= "CELSIUS" then return end
  SELECTED_SCALE = s
  pcall(function() C4:PersistSetValue("hk_scale", s) end)
  notify("SCALE_CHANGED", { SCALE = SELECTED_SCALE })
  write_units()
  report_all()
end

function DRV.OnDriverLateInit()
  AID = aidfmt(Properties and Properties["Accessory AID"] or "1")
  local saved = (C4 and C4.PersistGetValue and C4:PersistGetValue("hk_scale"))
  if saved == "CELSIUS" or saved == "FAHRENHEIT" then SELECTED_SCALE = saved end
  local rs = (C4 and C4.PersistGetValue and C4:PersistGetValue("hk_remote_sensor"))
  HAS_REMOTE_SENSOR = (rs == "true" or rs == true)
  dbg("thermostat init, aid=" .. tostring(AID) .. " scale=" .. SELECTED_SCALE
      .. " remote sensor=" .. tostring(HAS_REMOTE_SENSOR))
  notify("REMOTE_SENSOR_CHANGED", { IN_USE = HAS_REMOTE_SENSOR })
  send_caps()
  notify("SCALE_CHANGED", { SCALE = SELECTED_SCALE })
  to_hub("HK_GET_STATE")
end
OPC["Accessory AID"] = function(v) AID = aidfmt(v); ONLINE = false; to_hub("HK_GET_STATE") end
GCPL.OnBindingChanged = function(idBinding, class, bIsBound)
  if tonumber(idBinding) == SENSOR_BINDING then
    if bIsBound then
      pcall(function() C4:SendToProxy(SENSOR_BINDING, "QUERY_SETTINGS", {}) end)
      pcall(function() C4:SendToProxy(SENSOR_BINDING, "GET_SENSOR_VALUE", {}) end)
    else
      HAS_REMOTE_SENSOR, REMOTE_TEMP_C, REMOTE_FORCED_OFF = false, nil, false
      pcall(function() C4:PersistSetValue("hk_remote_sensor", "false") end)
      dbg("temperature sensor unbound -> back to the accessory's own reading")
      report_all()
    end
    return
  end
  if tonumber(idBinding) == HUB then
    if bIsBound then to_hub("HK_GET_STATE")
    else ONLINE = false; notify("CONNECTION", { CONNECTED = "false" }) end
  end
end

function RFP.SET_REMOTE_SENSOR(idBinding, tParams)
  tParams = tParams or {}
  local on = not (tParams.IN_USE == false or tParams.IN_USE == "False" or tParams.IN_USE == "false")
  HAS_REMOTE_SENSOR = on
  REMOTE_FORCED_OFF = not on
  dbg("remote sensor -> " .. (on and "in use" or "not in use"))
  notify("REMOTE_SENSOR_CHANGED", tParams)
  pcall(function() C4:PersistSetValue("hk_remote_sensor", on and "true" or "false") end)
  if not on then REMOTE_TEMP_C, REMOTE_UNAVAIL = nil, false end
  report_all()
  if on then pcall(function() C4:SendToProxy(SENSOR_BINDING, "GET_SENSOR_VALUE", {}) end) end
end

local function adopt_sensor()
  if HAS_REMOTE_SENSOR or REMOTE_FORCED_OFF then return end
  HAS_REMOTE_SENSOR = true
  pcall(function() C4:PersistSetValue("hk_remote_sensor", "true") end)
  notify("REMOTE_SENSOR_CHANGED", { IN_USE = true })
  dbg("temperature sensor is supplying readings -> remote sensor in use")
end

local function take_sensor_value(tParams)
  local c = tonumber(tParams and tParams.CELSIUS)
  if not c then
    local fv = tonumber(tParams and tParams.FAHRENHEIT)
    if fv then c = f2c(fv) end
  end
  if not c then return false end
  REMOTE_TEMP_C = c
  return true
end

function RFP.VALUE_INITIALIZED(idBinding, tParams)
  if tonumber(idBinding) ~= SENSOR_BINDING or REMOTE_FORCED_OFF then return end
  adopt_sensor()
  REMOTE_UNAVAIL = false
  notify("CONNECTION", { CONNECTED = "true" })
  if take_sensor_value(tParams) then
    notify("VALUE_INITIALIZED", { STATUS = "active", TIMESTAMP = tostring(os.time()) })
    dbg(("remote sensor initialised: %.1fC"):format(REMOTE_TEMP_C))
    report_all()
  end
end
function RFP.VALUE_INITIALIZE(idBinding, tParams) RFP.VALUE_INITIALIZED(idBinding, tParams) end

function RFP.VALUE_CHANGED(idBinding, tParams)
  if tonumber(idBinding) ~= SENSOR_BINDING or REMOTE_FORCED_OFF then return end
  adopt_sensor()
  if REMOTE_UNAVAIL then return RFP.VALUE_INITIALIZED(idBinding, tParams) end
  if take_sensor_value(tParams) then
    dbg(("remote sensor: %.1fC"):format(REMOTE_TEMP_C))
    report_all()
  end
end

function RFP.VALUE_UNAVAILABLE(idBinding, tParams)
  if not (HAS_REMOTE_SENSOR and tonumber(idBinding) == SENSOR_BINDING) then return end
  REMOTE_UNAVAIL = true
  dbg("remote sensor unavailable")
  notify("CONNECTION", { CONNECTED = "false" })
end

function RFP.SET_SCALE(idBinding, tParams) dbg("proxy SET_SCALE " .. tostring(tParams.SCALE)); set_scale(tParams.SCALE) end

local function set_iid_maps(map)
  TYPEMAP, IIDTYPE = {}, {}
  for t, iid in pairs(map or {}) do TYPEMAP[norm(t)] = iid; IIDTYPE[tonumber(iid) or iid] = norm(t) end
end

function RFP.RECEIVE_DB(idBinding, tParams)
  if aidfmt(tParams.aid) ~= AID then return end
  local ok, map = pcall(function() return JSON:decode(tParams.data) end)
  if ok then
    set_iid_maps(map)
    IS_HC = (TYPEMAP[HK.HC_TGT] ~= nil) and (TYPEMAP[HK.TGT_STATE] == nil)
    HAS_FAN = (not IS_HC) and (TYPEMAP[HK.FAN_TGT] ~= nil)
    HAS_HUMIDITY = (TYPEMAP[HK.HUM] ~= nil)
    dbg("got DB: service=" .. (IS_HC and "HeaterCooler" or "Thermostat")
        .. " humidity=" .. tostring(HAS_HUMIDITY) .. " fan=" .. tostring(HAS_FAN))
    mark_online()
    send_caps()
    report_all()
  end
end

local function apply_chars(list)
  mark_online()
  for _, c in ipairs(list) do
    local t = IIDTYPE[c.iid] or IIDTYPE[tonumber(c.iid)]
    if t then STATE[t] = c.value end
  end
  report_all()
end
function RFP.RECEIVE_META(idBinding, tParams)
  if aidfmt(tParams.aid) ~= AID then return end
  local ok, m = pcall(function() return JSON:decode(tParams.data) end)
  if ok and m then
    META = {}
    for t, v in pairs(m) do META[norm(t)] = v end
    local tt = META[HK.TGT_TEMP]
    dbg("got META: TargetTemp step=" .. tostring(tt and tt.step)
        .. " min=" .. tostring(tt and tt.min) .. " max=" .. tostring(tt and tt.max))
  end
end

function RFP.RECEIVE_STATE(idBinding, tParams)
  if aidfmt(tParams.aid) ~= AID then return end
  local ok, l = pcall(function() return JSON:decode(tParams.data) end); if ok and l then apply_chars(l) end
end
function RFP.RECEIVE_EVENT(idBinding, tParams)
  if aidfmt(tParams.aid) ~= AID then return end
  local ok, l = pcall(function() return JSON:decode(tParams.data) end); if ok and l then apply_chars(l) end
end

setpoint_src_ro = function(kind)
  local m = tonumber(STATE[HK.TGT_STATE]) or 0
  if m == 3 then
    return (kind == "heat") and HK.HEAT_THRESH or HK.COOL_THRESH
  end
  if (kind == "heat" and m == 1) or (kind == "cool" and m == 2) then
    return HK.TGT_TEMP
  end
  local t = (kind == "heat") and HK.HEAT_THRESH or HK.COOL_THRESH
  if TYPEMAP[t] then return t end
  return nil
end

local function want_celsius(tParams)
  if SELECTED_SCALE == "FAHRENHEIT" then
    local f = tonumber(tParams.FAHRENHEIT); if f then return f2c(f) end
  end
  local c = tonumber(tParams.CELSIUS); if c then return c end
  local f = tonumber(tParams.FAHRENHEIT); if f then return f2c(f) end
  local t = tonumber(tParams.TEMPERATURE or tParams.SETPOINT)
  if t then return (tParams.SCALE == "FAHRENHEIT" or tParams.SCALE == "F") and f2c(t) or t end
  return nil
end
local function round1(x) return math.floor(x * 10 + 0.5) / 10 end

function RFP.SET_SETPOINT_HEAT(idBinding, tParams)
  local c = want_celsius(tParams); if not c then return end
  dbg("proxy SET_SETPOINT_HEAT -> " .. round1(c) .. "C")
  if IS_HC then write_char(HK.HEAT_THRESH, round1(c)); return end
  local t = setpoint_src_ro("heat")
  if t then write_char(t, round1(c))
  else dbg("  (no place to store the heat setpoint in this mode; ignored)") end
end

function RFP.SET_SETPOINT_COOL(idBinding, tParams)
  local c = want_celsius(tParams); if not c then return end
  dbg("proxy SET_SETPOINT_COOL -> " .. round1(c) .. "C")
  if IS_HC then write_char(HK.COOL_THRESH, round1(c)); return end
  local t = setpoint_src_ro("cool")
  if t then write_char(t, round1(c))
  else dbg("  (no place to store the cool setpoint in this mode; ignored)") end
end

function RFP.SET_SETPOINT_SINGLE(idBinding, tParams)
  local c = want_celsius(tParams); if not c then return end
  dbg("proxy SET_SETPOINT_SINGLE -> " .. round1(c) .. "C")
  if IS_HC then
    local mode = current_mode()
    if mode == "Cool" then write_char(HK.COOL_THRESH, round1(c))
    elseif mode == "Heat" then write_char(HK.HEAT_THRESH, round1(c))
    else write_chars({ { iid = TYPEMAP[HK.HEAT_THRESH], value = round1(c) },
                       { iid = TYPEMAP[HK.COOL_THRESH], value = round1(c) } }) end
    return
  end
  write_char(HK.TGT_TEMP, round1(c))
end

function RFP.SET_MODE_HVAC(idBinding, tParams)
  local mode = tParams.MODE
  dbg("proxy SET_MODE_HVAC " .. tostring(mode))
  if IS_HC then
    if mode == "Off" then
      if TYPEMAP[HK.ACTIVE] then write_chars({ { iid = TYPEMAP[HK.ACTIVE], value = 0 } }) end
      return
    end
    local hc = MODE_TO_HC[mode]
    if hc == nil then return end
    local chars = {}
    if TYPEMAP[HK.ACTIVE] then chars[#chars+1] = { iid = TYPEMAP[HK.ACTIVE], value = 1 } end
    if TYPEMAP[HK.HC_TGT] then chars[#chars+1] = { iid = TYPEMAP[HK.HC_TGT], value = hc } end
    if #chars > 0 then write_chars(chars) end
    return
  end
  local hk = MODE_TO_HK[mode]
  if hk ~= nil then write_char(HK.TGT_STATE, hk) end
end

function RFP.SET_MODE_FAN(idBinding, tParams)
  local mode = tParams.MODE
  dbg("proxy SET_MODE_FAN " .. tostring(mode))
  if not HAS_FAN then dbg("  accessory has no fan service; ignoring"); return end
  local chars = {}
  if mode == "Auto" then
    if TYPEMAP[HK.FAN_TGT] then chars[#chars+1] = { iid = TYPEMAP[HK.FAN_TGT], value = 1 } end
  else
    if TYPEMAP[HK.FAN_TGT] then chars[#chars+1] = { iid = TYPEMAP[HK.FAN_TGT], value = 0 } end
    if TYPEMAP[HK.FAN_ACTIVE] then chars[#chars+1] = { iid = TYPEMAP[HK.FAN_ACTIVE], value = 1 } end
  end
  if #chars > 0 then write_chars(chars) end
end

function RFP.SET_MODE_HOLD(idBinding, tParams)
  dbg("SET_MODE_HOLD " .. tostring(tParams and tParams.MODE) .. " (no standard HomeKit equivalent)")
end
function RFP.SET_PRESET() end
function RFP.SET_PRESETS() end
function RFP.SET_EVENT() end
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
