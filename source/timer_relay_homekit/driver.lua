do
	Helper = {}
	Timer = {}
	EX_CMDS = {}
	PROXY_CMDS = {}
	ACTIONS = {}
	ON_INIT = {}
	ON_LATE_INIT = {}
	ON_PROPERTY_CHANGED = {}
	UI_REQUEST = {}
	DEVICE = {}
end

do
		if (C4.GetDriverConfigInfo) then
		VERSION = C4:GetDriverConfigInfo ("version")
	else
		VERSION = 'Incompatible with this OS'
	end
	AvailableStates = {1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50,55,60,90,120,180}
	All_Times = '1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50,55,60,90,120,180'
	gStateIndex = 1
	gCurrentState = "Off"
	gPressIsOff = gPressIsOff or false
	LED = LED or {}
	LED ['On'] = '000000'
	LED ['Off'] = '000000'
	LED ['Pressed'] = '000000'

	EXTERNAL_DEVICE = EXTERNAL_DEVICE or 0
	EXTERNAL = EXTERNAL or false
	ON_FIRST = ON_FIRST or false
	INDIVIDUAL_COLORS = INDIVIDUAL_COLORS or false
	TIME_COLOR = 0

	TOGGLE_PROXY = 500
	ON_PROXY = 501
	OFF_PROXY = 502

	HK_HUB      = 999
	HOMEKIT     = HOMEKIT or false
	HK_AID      = HK_AID or "1"
	HK_FLAT     = HK_FLAT or {}
	HK_CTRL_IID = HK_CTRL_IID or nil
	HK_CTRL_TYPE = HK_CTRL_TYPE or nil
	HKC = { ON="25", ACTIVE="B0", INUSE="D2" }
end

function dbg (strDebugText, ...)
	if (DEBUGPRINT) then print (os.date ('%x %X : ') .. (strDebugText or ''), ...) end
end

function dbgdump (strDebugText, ...)
	if (DEBUGPRINT) then hexdump (strDebugText or '') print (...) end
end

function hk_to_hub (cmd, p)
	p = p or {}
	p.aid = HK_AID
	C4:SendToProxy (HK_HUB, cmd, p)
end

function hk_same_aid (a)
	return (tonumber(a) ~= nil) and (tonumber(a) == tonumber(HK_AID))
end

function hk_resolve ()
	if (HK_FLAT [HKC.ON]) then
		HK_CTRL_IID, HK_CTRL_TYPE = HK_FLAT [HKC.ON], HKC.ON
	else
		HK_CTRL_IID, HK_CTRL_TYPE = HK_FLAT [HKC.ACTIVE], HKC.ACTIVE
	end
	dbg ('HK control iid = ' .. tostring(HK_CTRL_IID) .. ' type ' .. tostring(HK_CTRL_TYPE))
end

function DEVICE.HKSet (bOn)
	if (not HOMEKIT) then return end
	if (not HK_CTRL_IID) then dbg ('HKSet: no control iid resolved yet') return end
	dbg ('HKSet ' .. tostring(bOn) .. ' -> iid ' .. tostring(HK_CTRL_IID))
	local v
	if (HK_CTRL_TYPE == HKC.ON) then
		v = bOn and 'true' or 'false'
	else
		v = bOn and '1' or '0'
	end
	hk_to_hub ('HK_SET_CHAR', { iid = tostring(HK_CTRL_IID), value = v })
end

function DEVICE.HKReflect (v)
	dbg ('relay state reported = ' .. tostring(v))
	C4:SetVariable ('STATE', (tonumber (v) == 1 or v == true) and 1 or 0)
end


function ExecuteCommand (strCommand, tParams)
    print("ExecuteCommand function called with : " .. strCommand)

    if EX_CMDS and type(EX_CMDS[strCommand]) == "function" then
            EX_CMDS[strCommand](tParams)
    elseif strCommand == "LUA_ACTION" then
        if tParams ~= nil then
            for cmd, cmdv in pairs(tParams) do
                print (cmd,cmdv)
                if cmd == "ACTION" then
                    if ACTIONS and type(ACTIONS[cmdv]) == "function" then
                        ACTIONS[cmdv](tParams)
                    else
                        print("From ExecuteCommand Function - Undefined Action")
                        print("Key: " .. cmd .. " Value: " .. cmdv)
                    end
                else
                    print("From ExecuteCommand Function - Undefined ACTION")
                    print("Key: " .. cmd .. " Value: " .. cmdv)
                end
            end
        end
    end
end

function EX_CMDS.SetCountdown (tParams)
    dbg ("SetTimer()", tParams.Time)

	if (Indexes [tParams.Time]) then
		gStateIndex = Indexes [tParams.Time]
		gCurrentState = States [gStateIndex]
		DEVICE.SendIcon(gCurrentState)
		Helper.DriverInfo ('Timer selected: ' .. gCurrentState)
		if (tParams.Time == 'Off') then
			gPressIsOff = true
			PROXY_CMDS.SELECT ()
		else
			Timer.StateDebounce = Helper.AddTimer (Timer.StateDebounce, 2, 'SECONDS', false)
			Timer.PressIsOff = Helper.AddTimer (Timer.PressIsOff, 5, 'SECONDS', false)
		end
		DEVICE.SetLEDColor (gCurrentState)
	else
		print ('Does not exist')
	end
end

function OnDriverInit ()
	Helper.RunFunctions(ON_INIT)
end

function ON_INIT.setupState ()
    gStateIndex = "1"
    dbg ("State Index set to:", gStateIndex)
end

function ON_INIT.Version ()
	C4:UpdateProperty ('Driver Version', VERSION)
end

function ON_INIT.Variables ()
	C4:AddVariable("RUNTIME", "0", "NUMBER", true, false)
	C4:AddVariable("COUNTDOWN", "0", "NUMBER", true, false)
	C4:AddVariable("STATE", "0", "NUMBER", true, false)
end
function ON_INIT.TimeColors ()

	if (PersistData == nil) then
		PersistData = {}
	end

	if (PersistData["LED_TIME"] == nil) then
		PersistData["LED_TIME"] = {}
		LED_TIME = PersistData["LED_TIME"]
		for k, v in pairs (AvailableStates) do
			LED_TIME [v] = Helper.RGB2HEX ('0,200,0')
		end
		PersistData["LED_TIME"]  = LED_TIME
	else
		LED_TIME = PersistData["LED_TIME"]
	end


end
function OnDriverLateInit ()
    Helper.RunFunctions(ON_LATE_INIT)
end

function ON_LATE_INIT.SetTimes ()

	C4:UpdatePropertyList ('Select time', All_Times)

	for k, _ in pairs (Properties) do
		if (k ~= 'Control Method') then
			OnPropertyChanged (k)
		end
	end
	OnPropertyChanged ('Control Method')
	Timer.CheckInitialize = Helper.AddTimer (Timer.CheckInitialize, 60, 'SECONDS', false)
end

function ON_INIT.VersionCheck ()
	if not Helper.VersionCheck ('2.9.0.0') then
		C4:UpdateProperty ('Driver Version', 'ERROR: This driver requires OS2.9 or higher')
	end
end

function OnPropertyChanged(sProperty)
	dbg ("OnPropertyChanged(" .. sProperty .. ") changed to: " .. Properties[sProperty])

	local propertyValue = Properties[sProperty]

	local trimmedProperty = string.gsub(sProperty, " ", "")

	if (ON_PROPERTY_CHANGED[sProperty] ~= nil and type(ON_PROPERTY_CHANGED[sProperty]) == "function") then
		ON_PROPERTY_CHANGED[sProperty](propertyValue)
		return
	elseif (ON_PROPERTY_CHANGED[trimmedProperty] ~= nil and type(ON_PROPERTY_CHANGED[trimmedProperty]) == "function") then
		ON_PROPERTY_CHANGED[trimmedProperty](propertyValue)
		return
	end
end

function ON_PROPERTY_CHANGED.CountdownTimes (value)
	States = {}
	local time_list = ''

  NONE_VALUE = '[None]'

  if (value == '') then
    value = NONE_VALUE
    C4:UpdateProperty('Countdown Times', NONE_VALUE)
  end

  if (value ~= NONE_VALUE) then
    for value in string.gmatch (value, "(%d+)") do
      local found = false
      for k,v in pairs (AvailableStates) do
        if tonumber(value) == v then found = true end
      end
      if (found) then
        table.insert (States, value)
        time_list = time_list .. value .. ','
      else
        Helper.DriverInfo ('Countdown Time ' .. value .. ' is invalid')
        return
      end
    end
  end

	if (ON_FIRST) then
		table.insert (States, 1, 'On')
		table.insert (States, 1, 'Off')
	else
		table.insert (States, 1, 'Off')
		table.insert (States, 'On')
	end
	Indexes = Helper.TableInvert (States)
	gStateIndex, gCurrentState = next (States, nil)
	DEVICE.SendIcon (gCurrentState)
	gPressIsOff = false
	C4:SendToProxy (2, "OPEN", '')

	time_list= string.sub (time_list, 1, -2)
	C4:UpdatePropertyList ('Manual run time minutes', time_list)

end
function ON_PROPERTY_CHANGED.DebugMode (value)
	if (value == 'Off') then
		DEBUGPRINT = false
		Timer.Debug = Helper.KillTimer (Timer.Debug)
		if (C4.AllowExecute) then C4:AllowExecute (false) end
	elseif (value == 'On') then
		DEBUGPRINT = true
		Timer.Debug = Helper.AddTimer (Timer.Debug, 45, 'MINUTES')
		if (C4.AllowExecute) then C4:AllowExecute (true) end
	end
end

function ON_PROPERTY_CHANGED.DriverVersion (value)
	C4:UpdateProperty ('Driver Version', VERSION)
end
function ON_PROPERTY_CHANGED.OnLEDColor (value)
	LED ['On'] = Helper.RGB2HEX (value)
	C4:SendToProxy(TOGGLE_PROXY, "BUTTON_COLORS", {ON_COLOR = {COLOR_STR = LED ['On']}, OFF_COLOR = {COLOR_STR = LED ['Off']}}, "NOTIFY")
	C4:SendToProxy(ON_PROXY, "BUTTON_COLORS", {ON_COLOR = {COLOR_STR = LED ['On']}, OFF_COLOR = {COLOR_STR = '000000'}}, "NOTIFY")
end

function ON_PROPERTY_CHANGED.OffLEDColor (value)
	LED ['Off'] = Helper.RGB2HEX (value)
	C4:SendToProxy(TOGGLE_PROXY, "BUTTON_COLORS", {ON_COLOR = {COLOR_STR = LED ['On']}, OFF_COLOR = {COLOR_STR = LED ['Off']}}, "NOTIFY")
	C4:SendToProxy(OFF_PROXY, "BUTTON_COLORS", {ON_COLOR = {COLOR_STR = LED ['Off']}, OFF_COLOR = {COLOR_STR = '000000'}}, "NOTIFY")
end

function ON_PROPERTY_CHANGED.PressedLEDColor (value)
	LED ['Pressed'] = Helper.RGB2HEX (value)
end
function ON_PROPERTY_CHANGED.LightSwitch (value)
	if (EXTERNAL_DEVICE and EXTERNAL_DEVICE ~= 0) then
		C4:UnregisterVariableListener(EXTERNAL_DEVICE, 1000)
	end
	EXTERNAL_DEVICE = tonumber(value)
	if (EXTERNAL_DEVICE) then
		C4:RegisterVariableListener(EXTERNAL_DEVICE, 1000)
	else
		EXTERNAL_DEVICE = 0
	end
end
function ON_PROPERTY_CHANGED.Usetimerifturnedonmanually (value)
	MANUAL_TIMER = (value == 'Yes')
	if (MANUAL_TIMER) then
		C4:SetPropertyAttribs('Manual run time minutes', 0)
	else
		C4:SetPropertyAttribs('Manual run time minutes', 1)
	end
end
function ON_PROPERTY_CHANGED.Manualruntimeminutes (value)
	MANUAL_TIME = tonumber (value)
end
function ON_PROPERTY_CHANGED.ControlMethod (value)

	if (value == 'Relay') then
		C4:SetPropertyAttribs('Light Switch', 1)
		EXTERNAL = false
		HOMEKIT = false
		if (EXTERNAL_DEVICE and EXTERNAL_DEVICE ~= 0) then
			C4:UnregisterVariableListener(EXTERNAL_DEVICE, 1000)
		end
		EXTERNAL_DEVICE = 0
		C4:SetPropertyAttribs('Accessory AID', 1)

	elseif (value == 'Light Switch') then
		C4:SetPropertyAttribs('Light Switch', 0)
		EXTERNAL = true
		HOMEKIT = false
		C4:SetPropertyAttribs('Accessory AID', 1)
		OnPropertyChanged ('Light Switch')

	elseif (value == 'HomeKit') then
		C4:SetPropertyAttribs('Light Switch', 1)
		EXTERNAL = false
		HOMEKIT = true
		if (EXTERNAL_DEVICE and EXTERNAL_DEVICE ~= 0) then
			C4:UnregisterVariableListener(EXTERNAL_DEVICE, 1000)
		end
		EXTERNAL_DEVICE = 0
		C4:SetPropertyAttribs('Accessory AID', 0)
		hk_to_hub ('HK_GET_STATE')

	end
end

function ON_PROPERTY_CHANGED.AccessoryAID (value)
	HK_AID = tostring (value or '1')
	if (HOMEKIT) then hk_to_hub ('HK_GET_STATE') end
end

function ON_PROPERTY_CHANGED.PermanentOnisfirstselection (value)
	ON_FIRST = (value == 'Yes')
	OnPropertyChanged ('Countdown Times')
end

function ON_PROPERTY_CHANGED.SetLEDcolorsforeachtime (value)
	if (value == 'Yes') then
		C4:SetPropertyAttribs('Select time', 0)
		C4:SetPropertyAttribs('Choose LED Color', 0)
		INDIVIDUAL_COLORS = true
	else
		C4:SetPropertyAttribs('Select time', 1)
		C4:SetPropertyAttribs('Choose LED Color', 1)
		INDIVIDUAL_COLORS = false
	end
end

function ON_PROPERTY_CHANGED.Selecttime (value)
	if (value == '') then return end
	TIME_COLOR = tonumber (value)
	C4:UpdateProperty ('Choose LED Color', Helper.HEX2RGB (LED_TIME [TIME_COLOR]))
end

function ON_PROPERTY_CHANGED.ChooseLEDColor (value)
	if (TIME_COLOR ~= 0) then
		LED_TIME [TIME_COLOR] = Helper.RGB2HEX (value)
	end
end

function OnTimerExpired (idTimer)
	if (idTimer == Timer.Debug) then
		dbg ('Turning Debug Mode Off (timer expired)')
		C4:UpdateProperty ('Debug Mode', 'Off')
		OnPropertyChanged ('Debug Mode')

	elseif (idTimer == Timer.PressIsOff) then
		dbg ('Next Press Is Off')
		gPressIsOff = true

	elseif (idTimer == Timer.StateDebounce) then
		DEVICE.SetLEDColor (gCurrentState)
		DEVICE.StartTimer ()

	elseif (idTimer == Timer.Minute) then
		DEVICE.Countdown ()

	elseif (idTimer == Timer.CheckInitialize) then
		if (States  == nil ) then
			ON_LATE_INIT.SetTimes ()
		end

	end
end
function OnWatchedVariableChanged(idDevice, idVariable, strValue)
	dbg ('Device: ' .. idDevice .. ' Variable: ' .. idVariable .. ' Value: ' .. strValue)
	if (idDevice == EXTERNAL_DEVICE and EXTERNAL == true) then
		if (idVariable == 1000) then
			if (strValue == '1' and gCurrentState == 'Off') then
				dbg ('Device is on by external control')
				if (MANUAL_TIMER) then
					EX_CMDS.SetCountdown ({Time = tostring (MANUAL_TIME)})
				else
					EX_CMDS.SetCountdown ({Time = 'On'})
				end
			elseif (strValue == '0' and gCurrentState ~= 'Off') then
				dbg ('Device is off by external control')
				EX_CMDS.SetCountdown ({Time = 'Off'})
			end
		end
	end
end
function ReceivedFromProxy (idBinding, strCommand, tParams)
    dbg ("RecievedFromProxy()", idBinding, strCommand)
    if type(PROXY_CMDS[strCommand]) == "function" then
        local success, retVal = pcall(PROXY_CMDS[strCommand], tParams, idBinding)
        if success then
            return retVal
        end
    end
    return nil
end
function PROXY_CMDS.RECEIVE_META (tParams) end
function PROXY_CMDS.RECEIVE_SERVICES (tParams) end

function PROXY_CMDS.RECEIVE_DB (tParams)
	if (not hk_same_aid (tParams.aid)) then return end
	local ok, map = pcall (function () return C4:JsonDecode (tParams.data) end)
	if (ok and type(map) == 'table') then HK_FLAT = map ; hk_resolve () end
end

function PROXY_CMDS.RECEIVE_STATE (tParams)
	if (not hk_same_aid (tParams.aid)) then return end
	local ok, list = pcall (function () return C4:JsonDecode (tParams.data) end)
	if (not (ok and type(list) == 'table')) then return end
	for _, c in ipairs (list) do
		if (HK_CTRL_IID and tonumber(c.iid) == tonumber(HK_CTRL_IID)) then DEVICE.HKReflect (c.value) end
	end
end
PROXY_CMDS.RECEIVE_EVENT = PROXY_CMDS.RECEIVE_STATE

function OnBindingChanged (idBinding, strClass, bIsBound)
	if (tonumber(idBinding) == HK_HUB and bIsBound) then
		dbg ('HomeKit hub bound; requesting state')
		hk_to_hub ('HK_GET_STATE')
	end
end

function PROXY_CMDS.ON (tParams)
	dbg ('On')
	EX_CMDS.SetCountdown ({Time = 'On'})
end
function PROXY_CMDS.OFF(tParams)
	dbg ('Off')
	EX_CMDS.SetCountdown ({Time = 'Off'})
end
function PROXY_CMDS.DO_CLICK (tParams, idBinding)
	dbg ('Do click')
	if (idBinding == TOGGLE_PROXY) then
		PROXY_CMDS.SELECT (tParams)

	elseif (idBinding == ON_PROXY) then
		if (MANUAL_TIMER) then
			EX_CMDS.SetCountdown ({Time = tostring (MANUAL_TIME)})
		else
			EX_CMDS.SetCountdown ({Time = 'On'})
		end

	elseif (idBinding == OFF_PROXY) then
		EX_CMDS.SetCountdown ({Time = 'Off'})

	else
		print ('Unhandled binding ' .. idBinding)
	end
end
function PROXY_CMDS.OPENED (tParams)
	if (gCurrentState ~='Off') then
		EX_CMDS.SetCountdown ({Time = 'Off'})
		Helper.DriverInfo ('Device switched off externally')
	end

end

function PROXY_CMDS.STATE_OPENED (tParams)
	if (gCurrentState ~='Off') then
		gCurrentState = 'Off'
		gPressIsOff = false
		DEVICE.FireEvent(gCurrentState)
		DEVICE.SendIcon (gCurrentState)
		Timer.Minute = Helper.KillTimer (Timer.Minute)
		gStateIndex = Indexes [gCurrentState]
		Helper.DriverInfo ('Timer stopped externally')
		C4:SetVariable ('COUNTDOWN', 0)
		C4:SetVariable ('RUNTIME', 0)
	end

end

function PROXY_CMDS.CLOSED (tParams)
	if (gCurrentState =='Off') then
		if (MANUAL_TIMER) then
			EX_CMDS.SetCountdown ({Time = tostring (MANUAL_TIME)})
		else
			EX_CMDS.SetCountdown ({Time = 'On'})
		end
		Helper.DriverInfo ('Device switched on externally')
	end
end

function PROXY_CMDS.STATE_CLOSED (tParams)
	if (gCurrentState =='Off') then
		gCurrentState = 'On'
		gStateIndex = Indexes [gCurrentState]
		Timer.PressIsOff = Helper.AddTimer (Timer.PressIsOff, 5, 'SECONDS', false)
		Timer.Minute = Helper.KillTimer (Timer.Minute)
		DEVICE.FireEvent(gCurrentState)
		DEVICE.SendIcon(gCurrentState)
		gTimerTime = 0
		C4:SetVariable ('RUNTIME', -1)
		C4:SetVariable ('COUNTDOWN', 0)
		Helper.DriverInfo ('Relay switched on permanently externally')
	end
end

function PROXY_CMDS.SELECT (tParams)
	Timer.StateDebounce = Helper.KillTimer (Timer.StateDebounce)
	Timer.PressIsOff = Helper.KillTimer (Timer.PressIsOff)

	if (gPressIsOff) then
		gPressIsOff = false
		gCurrentState = 'Off'
		gStateIndex = Indexes [gCurrentState]
		if (EXTERNAL_DEVICE ~= 0 and EXTERNAL == true) then
			C4:SendToDevice (EXTERNAL_DEVICE, "OFF", {})
		end
		if (HOMEKIT) then DEVICE.HKSet (false) end
		DEVICE.FireEvent(gCurrentState)
		DEVICE.SetLEDColor (gCurrentState)
		Timer.Minute = Helper.KillTimer (Timer.Minute)
		C4:SetVariable ('COUNTDOWN', 0)
		C4:SetVariable ('STATE', 0)
		C4:SendToProxy (2, "OPEN", '')

	else
		gStateIndex, gCurrentState = next (States, gStateIndex)
		if (gStateIndex == nil) then
			gStateIndex, gCurrentState = next (States, nil)
		end
		Timer.StateDebounce = Helper.AddTimer (Timer.StateDebounce, 2, 'SECONDS', false)
		if (gCurrentState ~= 'Off') then
			Timer.PressIsOff = Helper.AddTimer (Timer.PressIsOff, 5, 'SECONDS', false)
		end

		if (INDIVIDUAL_COLORS) then
			DEVICE.SetLEDColor (gCurrentState)
		else
			C4:SendToProxy(TOGGLE_PROXY, "BUTTON_COLORS", {ON_COLOR = {COLOR_STR = LED ['Pressed']}, OFF_COLOR = {COLOR_STR = LED ['Off']}}, "NOTIFY")
			C4:SendToProxy (TOGGLE_PROXY, 'MATCH_LED_STATE', {STATE = '1'})
		end

	end
	Helper.DriverInfo ('Timer selected: ' .. gCurrentState)
	DEVICE.SendIcon (gCurrentState)
end

function Helper.AddTimer (timer, count, units, recur)
	local newTimer
	if (recur == nil) then recur = false end
	if (timer and timer ~= 0) then Helper.KillTimer (timer) end

	newTimer = C4:AddTimer (count, units, recur)
	return newTimer
end

function Helper.DriverInfo (info)
	C4:UpdateProperty ('Driver Information', info)
	print (os.date ('%x %X : ') .. info)
end

function Helper.KillAllTimers ()

	for k,v in pairs (Timer or {}) do
		if (type (v) == 'number') then
			Timer [k] = Helper.KillTimer (Timer [k])
		end
	end

	for _, thisQ in pairs (Qs or {}) do
		if (thisQ.ConnectingTimer and thisQ.ConnectingTimer ~= 0) then thisQ.ConnectingTimer = Helper.KillTimer (thisQ.ConnectingTimer) end
		if (thisQ.ConnectedTimer and thisQ.ConnectedTimer ~= 0) then thisQ.ConnectedTimer = Helper.KillTimer (thisQ.ConnectedTimer) end
	end
end

function Helper.KillTimer (timer)
	if (timer and type (timer) == 'number') then
		return (C4:KillTimer (timer))
	else
		return (0)
	end
end

function Helper.Print (data)
	if (type (data) == 'table') then
		for k, v in pairs (data) do print (k, v) end
	elseif (type (data) ~= 'nil') then
		print (type (data), data)
	else
		print ('nil value')
	end
end


function Helper.RGB2HEX (rgb)
	local hex = ''
	for color in string.gmatch(rgb, "%d+") do
		hex = hex .. string.format ('%02x', color)
	end
	return hex
end
function Helper.HEX2RGB (hex)
    hex = hex:gsub("#","")
    return tonumber("0x"..hex:sub(1,2)) .. ',' .. tonumber("0x"..hex:sub(3,4)) .. ',' .. tonumber("0x"..hex:sub(5,6))
end
function Helper.Round(num, idp)
  local mult = 10^(idp or 0)
  return math.floor(num * mult + 0.5) / mult
end
function Helper.TableInvert (t)
	local u = {}
	for k, v in pairs(t) do u[v] = k end
	return u
end
function Helper.VersionCheck (requires_version)
	local curver = {}
	curver [1], curver [2], curver [3], curver [4] = string.match (C4:GetVersionInfo ().version, '(%d+)%.(%d+)%.(%d+)%.(%d+)')
	local reqver = {}
	reqver [1], reqver [2], reqver [3], reqver [4] = string.match (requires_version, '(%d+)%.(%d+)%.(%d+)%.(%d+)')

	for i = 1, 4 do
		local cur = tonumber (curver [i])
		local req = tonumber (reqver [i])
		if (cur > req) then
			return true
		end
		if (cur < req) then
			return false
		end
	end
	return true
end


function Helper.RunFunctions(funcMap)
    for k,v in pairs(funcMap) do
        if type(v) == "function" then
            pcall(v)
        end
    end
end


function DEVICE.Countdown ()
	gRunTime = gRunTime + 1
	local timeleft = gTimerTime - gRunTime
	C4:SetVariable ('COUNTDOWN', timeleft)
	Helper.DriverInfo ('Time left: ' .. timeleft .. ' minutes')

	if (timeleft == 0) then
		gCurrentState = 'Off'
		gPressIsOff = false
		DEVICE.FireEvent(gCurrentState)
		DEVICE.SendIcon (gCurrentState)
		DEVICE.SetLEDColor (gCurrentState)
		Timer.Minute = Helper.KillTimer (Timer.Minute)
		gStateIndex = Indexes [gCurrentState]
		C4:SendToProxy (2, "OPEN", '')
		if (EXTERNAL_DEVICE ~= 0 and EXTERNAL == true) then
			C4:SendToDevice (EXTERNAL_DEVICE, "OFF", {})
		end
		if (HOMEKIT) then DEVICE.HKSet (false) end

	else
		for k, v in pairs (AvailableStates) do
			if (timeleft == tonumber(v)) then
					DEVICE.FireEvent(v)
					DEVICE.SendIcon (v)
					DEVICE.SetLEDColor (v)
				break
			end
		end
	end

end

function DEVICE.FireEvent (eventName)
	dbg ("Firing event", eventName)
	C4:FireEvent( eventName )
end

function DEVICE.SendIcon (icon_state)
	if (gCurrentState == 'On') then
		C4:SendToProxy(5001, "ICON_CHANGED", {icon=icon_state, icon_description = 'Permanent'})
	elseif (gCurrentState == 'Off') then
		C4:SendToProxy(5001, "ICON_CHANGED", {icon=icon_state, icon_description = 'Off'})
	else
		C4:SendToProxy(5001, "ICON_CHANGED", {icon=icon_state, icon_description = gCurrentState .. ' mins'})
	end
end

function DEVICE.SetLEDColor (state)

	dbg ('Set LED color for state ' .. state)


	if (state ~= 'On' and state ~= 'Off') then
			if (INDIVIDUAL_COLORS) then
				C4:SendToProxy(TOGGLE_PROXY, "BUTTON_COLORS", {ON_COLOR = {COLOR_STR = LED_TIME [tonumber(state)]}, OFF_COLOR = {COLOR_STR = LED ['Off']}}, "NOTIFY")
				C4:SendToProxy(ON_PROXY, "BUTTON_COLORS", {ON_COLOR = {COLOR_STR = LED_TIME [tonumber(state)]}, OFF_COLOR = {COLOR_STR = '000000'}}, "NOTIFY")
				if (EXTERNAL_DEVICE ~= 0 and EXTERNAL == true) then
					C4:SendToDevice (EXTERNAL_DEVICE, "SET_BUTTON_COLOR", {ON_COLOR = LED_TIME [tonumber(state)], OFF_COLOR = '000000', BUTTON_ID = 0})
					C4:SendToDevice (EXTERNAL_DEVICE, "SET_BUTTON_COLOR", {ON_COLOR = '000000', OFF_COLOR = LED ['Off'], BUTTON_ID = 1})
				end
			else
				C4:SendToProxy(TOGGLE_PROXY, "BUTTON_COLORS", {ON_COLOR = {COLOR_STR = LED ['On']}, OFF_COLOR = {COLOR_STR = LED ['Off']}}, "NOTIFY")
				C4:SendToProxy(ON_PROXY, "BUTTON_COLORS", {ON_COLOR = {COLOR_STR = LED ['On']}, OFF_COLOR = {COLOR_STR = '000000'}}, "NOTIFY")
				if (EXTERNAL_DEVICE ~= 0 and EXTERNAL == true) then
					C4:SendToDevice (EXTERNAL_DEVICE, "SET_BUTTON_COLOR", {ON_COLOR = LED ['On'], OFF_COLOR = '000000', BUTTON_ID = 0})
					C4:SendToDevice (EXTERNAL_DEVICE, "SET_BUTTON_COLOR", {ON_COLOR = '000000', OFF_COLOR = LED ['Off'], BUTTON_ID = 1})
				end
			end
			C4:SendToProxy (TOGGLE_PROXY, 'MATCH_LED_STATE', {STATE = '1'})
			C4:SendToProxy (ON_PROXY, 'MATCH_LED_STATE', {STATE = '1'})
			C4:SendToProxy (OFF_PROXY, 'MATCH_LED_STATE', {STATE = '0'})

	else
		C4:SendToProxy(TOGGLE_PROXY, "BUTTON_COLORS", {ON_COLOR = {COLOR_STR = LED ['On']}, OFF_COLOR = {COLOR_STR = LED ['Off']}}, "NOTIFY")
		C4:SendToProxy(ON_PROXY, "BUTTON_COLORS", {ON_COLOR = {COLOR_STR = LED ['On']}, OFF_COLOR = {COLOR_STR = '000000'}}, "NOTIFY")
		C4:SendToProxy(OFF_PROXY, "BUTTON_COLORS", {ON_COLOR = {COLOR_STR = LED ['Off']}, OFF_COLOR = {COLOR_STR = '000000'}}, "NOTIFY")
		if (EXTERNAL_DEVICE ~= 0 and EXTERNAL == true) then
			C4:SendToDevice (EXTERNAL_DEVICE, "SET_BUTTON_COLOR", {ON_COLOR = LED ['On'], OFF_COLOR = '000000', BUTTON_ID = 0})
			C4:SendToDevice (EXTERNAL_DEVICE, "SET_BUTTON_COLOR", {ON_COLOR = '000000', OFF_COLOR = LED ['Off'], BUTTON_ID = 1})
		end
		if (state == 'On') then
			C4:SendToProxy (TOGGLE_PROXY, 'MATCH_LED_STATE', {STATE = '1'})
			C4:SendToProxy (ON_PROXY, 'MATCH_LED_STATE', {STATE = '1'})
			C4:SendToProxy (OFF_PROXY, 'MATCH_LED_STATE', {STATE = '0'})
		else
			C4:SendToProxy (TOGGLE_PROXY, 'MATCH_LED_STATE', {STATE = '0'})
			C4:SendToProxy (ON_PROXY, 'MATCH_LED_STATE', {STATE = '0'})
			C4:SendToProxy (OFF_PROXY, 'MATCH_LED_STATE', {STATE = '1'})
		end
	end


end

function DEVICE.SetStateIndex ()
	print ('Someone called SetStateIndex')
end

function DEVICE.StartTimer ()

	if (gCurrentState == 'Off') then
		Timer.Minute = Helper.KillTimer (Timer.Minute)
		DEVICE.FireEvent(gCurrentState)
		C4:SendToProxy (2, "OPEN", '')
		if (EXTERNAL_DEVICE ~= 0 and EXTERNAL == true) then
			C4:SendToDevice (EXTERNAL_DEVICE, "OFF", {})
		end
		if (HOMEKIT) then DEVICE.HKSet (false) end
		gTimerTime = 0
		C4:SetVariable ('RUNTIME', gTimerTime)

	elseif (gCurrentState == 'On') then
		Timer.Minute = Helper.KillTimer (Timer.Minute)
		DEVICE.FireEvent(gCurrentState)
		C4:SendToProxy (2, "CLOSE", '')
		if (EXTERNAL_DEVICE ~= 0 and EXTERNAL == true) then
			C4:SendToDevice (EXTERNAL_DEVICE, "ON", {})
		end
		if (HOMEKIT) then DEVICE.HKSet (true) end
		gTimerTime = 0
		C4:SetVariable ('RUNTIME', -1)
		C4:SetVariable ('COUNTDOWN', 0)
		C4:SetVariable ('STATE', 1)

	else
		local time = string.match (gCurrentState, "(%d+)")
		gTimerTime = tonumber (time)
		C4:SetVariable ('RUNTIME', gTimerTime)
		C4:SetVariable ('COUNTDOWN', gTimerTime)
		C4:SetVariable ('STATE', 1)
		gRunTime = 0
		Timer.Minute = Helper.AddTimer (Timer.Minute, 1, 'MINUTES', true)
		DEVICE.FireEvent(gCurrentState)
		C4:SendToProxy (2, "CLOSE", '')
		if (EXTERNAL_DEVICE ~= 0 and EXTERNAL == true) then
			C4:SendToDevice (EXTERNAL_DEVICE, "ON", {})
		end
		if (HOMEKIT) then DEVICE.HKSet (true) end
	end
end

function GetTimesForProgramming (currentValue, done, search, searchFilter)

	local list = {}

	if (States) then
		for i = 1, #States do
			table.insert (list, {text = States[i] , value = States[i]})
		end
	end

	return (list)
end
