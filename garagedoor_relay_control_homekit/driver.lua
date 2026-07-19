-- Start Code --
--------------------------------------------------------------------------------------------
-- Copyright 2021 Wirepath Home Systems, LLC. All Rights Reserved.
--------------------------------------------------------------------------------------------

-- TODO: Defect #39360... I should track whether there has been a change from Opened to Closed, or from Closed to Opened...
--                        Once that's happened, don't do a Toggle if state is known.
--       If it's a change from Unknown to Opened, or Unknown to Closed, it doesn't count as being 'known state'...
--       Using KNOWN_STATE variable to track it.  If we get an OPENED/CLOSED (not a STATE_OPENED/STATE_CLOSED), we set KNOWN_STATE to true.


do --Version globals
  if (C4.GetDriverConfigInfo) then
    VERSION = C4:GetDriverConfigInfo ("version")
  else
    VERSION = 'Incompatible with this OS'
  end

  Helper = {} --useful functions
  Timer = {} --timers
end


do --Globals
  CAPTURE_INIT = false -- Useful in debugging initial commands. Only set to true during debugging.

  Gate = {}

  FAILSAFE = FAILSAFE or 60

  KNOWN_STATE = false   -- Used to track whether we've received an unknown -> known state change...
                        -- Once we have, we don't send toggle for open/close when single toggle relay + 1/2 contact sensors.

  BUTTON_PROXY_ID = 5001

  OPEN_RELAY_ID = 1
  CLOSE_RELAY_ID = 2
  STOP_RELAY_ID = 3
  CLOSED_CONTACT_SENSOR_ID = 4
  OPENED_CONTACT_SENSOR_ID = 5

  TOGGLE_LINK_ID = 500
  OPEN_LINK_ID = 501
  CLOSE_LINK_ID = 502

  INVERT_OPEN_RELAY = INVERT_OPEN_RELAY or false
  INVERT_CLOSE_RELAY = INVERT_CLOSE_RELAY or false
  INVERT_STOP_RELAY = INVERT_STOP_RELAY or false

  INVERT_OPEN_CONTACT = INVERT_OPEN_CONTACT or false
  INVERT_CLOSED_CONTACT = INVERT_CLOSED_CONTACT or false

  CLOSED_SENSOR = CLOSED_SENSOR or false
  OPENED_SENSOR = OPENED_SENSOR or false
  NUM_SENSORS = NUM_SENSORS or 0

  OPENDEBOUNCE = OPENDEBOUNCE or 100
  CLOSEDEBOUNCE = CLOSEDEBOUNCE or 100

  PROXY_NAME = {}
  PROXY_NAME[OPEN_RELAY_ID] = " Open Relay "
  PROXY_NAME[CLOSE_RELAY_ID] = " Close Relay "
  PROXY_NAME[STOP_RELAY_ID] = " Stop Relay "
  PROXY_NAME[CLOSED_CONTACT_SENSOR_ID] = " Closed Input "
  PROXY_NAME[OPENED_CONTACT_SENSOR_ID] = " Opened Input "
  PROXY_NAME[BUTTON_PROXY_ID] = " UIButton "
  PROXY_NAME[TOGGLE_LINK_ID] = " Toggle Link "
  PROXY_NAME[OPEN_LINK_ID] = " Open Link "
  PROXY_NAME[CLOSE_LINK_ID] = " Close Link "

  STATE = STATE or 'Closed'
  CUR_STATES = CUR_STATES or {}

  PROPERTY_SHOW = 0
  PROPERTY_HIDE = 1

  INVERTED = {}
  INVERTED[true] = {Opened = 'Closed', Closed = 'Opened', OPEN = 'CLOSE', CLOSE = 'OPEN'}
  INVERTED[false] = {Opened = 'Opened', Closed = 'Closed', OPEN = 'OPEN', CLOSE = 'CLOSE'}

  if (HOLD == nil) then HOLD = true end

  LED = LED or {Opened = '000000', Closed = '000000', Off = '000000', Partial = '000000', Unknown = '000000'}

  PROXY_CMDS = {}
  ON_PROPERTY_CHANGED = {}
  EX_CMDS = {}
  LUA_ACTION = {}

  INIT_HEADER = "-------------------INIT-----------------"

  BINDING_STATE = {}
  BINDING_STATE[true] = "Bound"
  BINDING_STATE[false] = "Unbound"

  HK_HUB = 999
  PROXY_NAME[HK_HUB] = " HomeKit Hub "
  HOMEKIT = HOMEKIT or false
  HK_AID = HK_AID or "1"
  HK_FLAT = HK_FLAT or {}
  HK_TARGET_IID = HK_TARGET_IID or nil
  HK_CURRENT_IID = HK_CURRENT_IID or nil
  HKC = { TARGET = "32", CURRENT = "E" }
  HK_DOORSTATE = { [0] = 'Opened', [1] = 'Closed', [2] = 'Partial', [3] = 'Partial', [4] = 'Partial' }
end


function TestCondition(strName, tConditions)
  if (strName == "State") then
    local logic = tConditions.LOGIC or ""
    local value = tConditions.VALUE or ""
    if (value == 'Partially Open') then value = 'Partial' end
    if (logic == "EQUAL") then
      local cond = (value == STATE)
      dbg("TestCondition [" .. strName .. "]: (" .. formatParams(tConditions) .. ") -- " .. tostring(cond))
      return cond
    end
    if (logic == "NOT_EQUAL") then
      local cond = (value ~= STATE)
      dbg("TestCondition [" .. strName .. "]: (" .. formatParams(tConditions) .. ") -- " .. tostring(cond))
      return cond
    end
    return false
  end
end


function SetDefaultLEDColors(FORCE)
  PersistData = PersistData or {}
  if (not FORCE) and (PersistData["LED Defaults Set"]) then dbg("LED Defaults previously set. Exiting.") return end

  PersistData["LED Defaults Set"] = true
  C4:InvalidateState()

  dbg("Setting LED colors to project defaults...")
  local info = parse_flat(select(3,C4:GetProjectItems("LIMIT_DEVICE_DATA","LOCATIONS"):find("(<itemdata>.-toggle_on.-</itemdata>)")))

  C4:UpdateProperty("Opened LED Color", Helper.HEX2RGB(info.toggle_on or "000000"))
  C4:UpdateProperty("Closed LED Color", Helper.HEX2RGB(info.toggle_off or "000000"))
  C4:UpdateProperty("Off LED Color", Helper.HEX2RGB(info.top_off or "000000"))
  C4:UpdateProperty("Partial Open LED Color", Helper.HEX2RGB(info.toggle_on or "000000"))
  C4:UpdateProperty("Unknown LED Color", Helper.HEX2RGB("FF0000")) -- Red by default
end


function dbg(strDebugText, ...)
  if (DEBUGPRINT) then print(os.date ('%x %X : ') .. (strDebugText or ''), ...) end

  if (CAPTURE_INIT) then
    if (strDebugText == "INIT") then
      print(table.concat(gInit, "\n"))
      print(INIT_HEADER)
      return
    end
    if (gInitCapture) then
      gInit = gInit or { INIT_HEADER }
      table.insert(gInit, os.date ('%x %X : ') .. (strDebugText or ''), ...)
    end
  end
end


function hk_to_hub(cmd, p)
  p = p or {}
  p.aid = HK_AID
  C4:SendToProxy(HK_HUB, cmd, p)
end

function hk_same_aid(a)
  return (tonumber(a) ~= nil) and (tonumber(a) == tonumber(HK_AID))
end

function hk_resolve()
  HK_TARGET_IID = HK_FLAT[HKC.TARGET]
  HK_CURRENT_IID = HK_FLAT[HKC.CURRENT]
  dbg("HK target iid " .. tostring(HK_TARGET_IID) .. " current iid " .. tostring(HK_CURRENT_IID))
end

function hk_set_door(bOpen)
  if (not HOMEKIT) then return end
  if (not HK_TARGET_IID) then dbg("no HomeKit target iid resolved yet") return end
  hk_to_hub("HK_SET_CHAR", { iid = tostring(HK_TARGET_IID), value = bOpen and "0" or "1" })
end

function PROXY_CMDS.RECEIVE_META(tParams) end
function PROXY_CMDS.RECEIVE_SERVICES(tParams) end

function PROXY_CMDS.RECEIVE_DB(tParams)
  if (not hk_same_aid(tParams.aid)) then return end
  local ok, map = pcall(function() return C4:JsonDecode(tParams.data) end)
  if (ok and type(map) == 'table') then HK_FLAT = map hk_resolve() end
end

function PROXY_CMDS.RECEIVE_STATE(tParams)
  if (not hk_same_aid(tParams.aid)) then return end
  local ok, list = pcall(function() return C4:JsonDecode(tParams.data) end)
  if (not (ok and type(list) == 'table')) then return end
  for _, c in ipairs(list) do
    if (HK_CURRENT_IID and tonumber(c.iid) == tonumber(HK_CURRENT_IID)) then
      local st = HK_DOORSTATE[tonumber(c.value)]
      if (st) then Gate.UpdateState(st) end
    end
  end
end
PROXY_CMDS.RECEIVE_EVENT = PROXY_CMDS.RECEIVE_STATE

function ON_PROPERTY_CHANGED.AccessoryAID(value)
  HK_AID = tostring(value or "1")
  if (HOMEKIT) then hk_to_hub("HK_GET_STATE") end
end

function ON_PROPERTY_CHANGED.ControlMethod(value)
  HOMEKIT = (value == "HomeKit")
  C4:SetPropertyAttribs("Accessory AID", HOMEKIT and PROPERTY_SHOW or PROPERTY_HIDE)
  if (HOMEKIT) then hk_to_hub("HK_GET_STATE") end
end

function ExecuteCommand(strCommand, tParams)
  dbg("ExecuteCommand function called with : " .. strCommand)

  if EX_CMDS and type(EX_CMDS[strCommand]) == "function" then
    EX_CMDS[strCommand](tParams)
  end
end


EX_CMDS.OPEN = function() Gate.OpenCommand() end
EX_CMDS.CLOSE = function() Gate.CloseCommand() end
EX_CMDS.STOP = function() Gate.StopCommand() end

function EX_CMDS.LUA_ACTION(tParams)
  tParams = tParams or {}
  if (tParams.ACTION) then
    LUA_ACTION[tParams.ACTION]()
  end
end


LUA_ACTION.OPEN = function() Gate.OpenCommand() end
LUA_ACTION.CLOSE = function() Gate.CloseCommand() end
LUA_ACTION.STOP = function() Gate.StopCommand() end

LUA_ACTION.RESET_COLORS = function() SetDefaultLEDColors(true) end


function ReportSensorUsage()
  local showOpenCloseTimes = PROPERTY_HIDE

  NUM_SENSORS = 0
  if (CLOSED_SENSOR) then
    NUM_SENSORS = NUM_SENSORS + 1
    if (OPENED_SENSOR) then
      Helper.ContactStatus("Found both 'closed' and 'opened' contact sensors")
      NUM_SENSORS = NUM_SENSORS + 1
      showOpenCloseTimes = PROPERTY_SHOW
    else
      Helper.ContactStatus("Found 'closed' contact sensor")
    end
  else
    if (OPENED_SENSOR) then
      Helper.ContactStatus("Found 'opened' contact sensor")
      NUM_SENSORS = NUM_SENSORS + 1
    else
      Helper.ContactStatus("Found no contact sensors")
    end
  end

  C4:SetPropertyAttribs('Expected Open Time (s)', showOpenCloseTimes)
  C4:SetPropertyAttribs('Expected Close Time (s)', showOpenCloseTimes)
end


function GetGateState()
  Gate.UpdateState('Unknown', false)

  -- Get initial states of contacts, to set current status...
  MySendToProxy(CLOSED_CONTACT_SENSOR_ID, "GET_STATE")
  MySendToProxy(OPENED_CONTACT_SENSOR_ID, "GET_STATE")
end


function OnBindingChanged(idBinding, strClass, bIsBound)
  dbg('OnBindingChanged[' .. idBinding .. '] ' .. strClass .. ' ' .. BINDING_STATE[bIsBound])
  if (idBinding == HK_HUB) then
    if (bIsBound and HOMEKIT) then hk_to_hub("HK_GET_STATE") end
    return
  end
  if (idBinding == CLOSED_CONTACT_SENSOR_ID) then -- 'closed' contact sensor
    CLOSED_SENSOR = bIsBound
  end
  if (idBinding == OPENED_CONTACT_SENSOR_ID) then -- 'opened' contact sensor
    OPENED_SENSOR = bIsBound
  end
  OneShotTimer.Add(250, "MILLISECONDS", ReportSensorUsage, "RSU")
  OneShotTimer.Add(250, "MILLISECONDS", GetGateState, "GGS")
end


function OnDriverDestroyed()
  C4:DestroyServer()
  Helper.KillAllTimers()
  C4:DeleteVariable('STATE')
end


function OnDriverInit()
  PersistData = PersistData or {}

  RELAYS = PersistData.RELAYS or 0
  PersistData.RELAYS = RELAYS

  PersistData["RelayBindings"] = PersistData["RelayBindings"] or {}

  if (RELAYS ~= 0) then -- not setting up
    for k,v in pairs(PersistData["RelayBindings"]) do
      C4:AddDynamicBinding(k, "CONTROL", false, v , "RELAY", false, false)
    end
  end
end


function OnDriverLateInit()
  Helper.KillAllTimers()

  if (RELAYS == 0) then -- setting up
    OnPropertyChanged ('Number of Relays')
  end

  for k, _ in pairs(Properties) do
    if (k ~= 'Number of Relays') then OnPropertyChanged(k) end
  end

  C4:AddVariable('STATE', 'Unknown', 'STRING', false, false)

  SetDefaultLEDColors()
  SetLEDColors()

  Gate.UpdateState('Unknown', false)
end


function table_count(t)
  t = t or {}
  local count = 0
  for _, _ in pairs(t) do count = count + 1 end
  return count
end


-- Parses 'flat' XML (all 'single' matching tags under main tag, for a set of nodes passed in (childnodes))
-- Does *NOT* return Attributes, as that can't be returned 'flat'. Need to parse through C4:ParseXML returned tree to get attributes + values...
function parse_nodes(node)
  local out, tins = {}, table.insert

  for _, n in pairs(node) do
    local cn = n.ChildNodes or {}
    if ((table_count(cn) > 0) and n.Value == "") then
      out[n.Name] = out[n.Name] or {}

      local mynode = parse_nodes(cn)
      if (table_count(mynode) > 0) then
        if (type(out[n.Name]) ~= "table") then
          out[n.Name] = {}
        end
        tins(out[n.Name], mynode)
      else
        out[n.Name] = ""
      end
    else
      out[n.Name] = n.Value
    end
  end
  return out
end


function parse_flat(xml)
  -- C4 Parser seems to not like CDATA sections...
  xml = xml:gsub("<!%[CDATA%[.-%]%]>", "")

  local c4parsed = C4:ParseXml(xml)
  local status, retval = pcall(parse_nodes, c4parsed.ChildNodes)
  if (status ~= true) then
    dbg("parse_flat Error: xml: " .. xml .. " " .. retval .. " " .. debug.traceback())
    return {}
  end
  return retval
end


function OnPropertyChanged(sProperty)
  dbg("OnPropertyChanged(" .. sProperty .. ") changed to: " .. Properties[sProperty])
  OneShotTimer.Add(250, "MILLISECONDS", ShowHideProperties, "SHOWHIDE")

  local propertyValue = Properties[sProperty]

  -- Remove any spaces (trim the property)
  local trimmedProperty = sProperty:gsub(' ',''):gsub('/',''):gsub('%(',''):gsub('%)','')

  -- if function exists then execute (non-stripped)
  if (ON_PROPERTY_CHANGED[sProperty] ~= nil and type(ON_PROPERTY_CHANGED[sProperty]) == "function") then
    ON_PROPERTY_CHANGED[sProperty](propertyValue)
    return
    -- elseif trimmed function exists then execute
  elseif (ON_PROPERTY_CHANGED[trimmedProperty] ~= nil and type(ON_PROPERTY_CHANGED[trimmedProperty]) == "function") then
    ON_PROPERTY_CHANGED[trimmedProperty](propertyValue)
    return
  end
end


function ON_PROPERTY_CHANGED.DebugMode(value)
  if (value == 'Off') then
    DEBUGPRINT = false
    Timer.Debug = Helper.KillTimer(Timer.Debug)
  elseif (value == 'On') or (value == 'Print') then
    DEBUGPRINT = true
    Timer.Debug = Helper.AddTimer(Timer.Debug, 8 * 60, 'MINUTES')
    dbg("Debug Timer set to 8 Hours...")
  end
end


function ON_PROPERTY_CHANGED.IconSet(_) -- value
  Gate.UpdateState(STATE, false)
end


function ON_PROPERTY_CHANGED.DriverVersion(_) -- value
  C4:UpdateProperty('Driver Version', VERSION)
end


function ON_PROPERTY_CHANGED.FailSafeSeconds(value)
  FAILSAFE = tonumber(value)
end


function ON_PROPERTY_CHANGED.InvertOpenToggleRelay(value)
  INVERT_OPEN_RELAY = (value == 'Yes')
  OneShotTimer.Add(2, "SECONDS", GetGateState, "INVERT_CHANGED")
end


function ON_PROPERTY_CHANGED.InvertCloseRelay(value)
  INVERT_CLOSE_RELAY = (value == 'Yes')
  OneShotTimer.Add(2, "SECONDS", GetGateState, "INVERT_CHANGED")
end


function ON_PROPERTY_CHANGED.InvertStopRelay(value)
  INVERT_STOP_RELAY = (value == 'Yes')
  OneShotTimer.Add(2, "SECONDS", GetGateState, "INVERT_CHANGED")
end


function ShowHideProperties()
  if (HOLD == true) then
    -- Show Pulse Time MS only if Pulse Relay (not HOLD)
    C4:SetPropertyAttribs('Open/Toggle Relay Pulse Time (ms)', PROPERTY_HIDE)
    C4:SetPropertyAttribs('Close Relay Pulse Time (ms)', PROPERTY_HIDE)
    C4:SetPropertyAttribs('Stop Relay Pulse Time (ms)', PROPERTY_HIDE)

    -- Show Fail Safe Secs only if HOLD relay, and only for 3 relay setups, since the 'Stop' command is used to implement failsafe...
    if (RELAYS < 3) then
      C4:SetPropertyAttribs('Fail Safe Seconds', PROPERTY_HIDE)
    else
      C4:SetPropertyAttribs('Fail Safe Seconds', PROPERTY_SHOW)
    end
  else
    -- Show Pulse Time MS for Pulse Relay
    C4:SetPropertyAttribs('Open/Toggle Relay Pulse Time (ms)', PROPERTY_SHOW)

    if (RELAYS == 1) then
      C4:SetPropertyAttribs('Close Relay Pulse Time (ms)', PROPERTY_HIDE)
      C4:SetPropertyAttribs('Stop Relay Pulse Time (ms)', PROPERTY_HIDE)
    elseif (RELAYS == 2) then
      C4:SetPropertyAttribs('Close Relay Pulse Time (ms)', PROPERTY_SHOW)
      C4:SetPropertyAttribs('Stop Relay Pulse Time (ms)', PROPERTY_HIDE)
    elseif (RELAYS == 3) then
      C4:SetPropertyAttribs('Close Relay Pulse Time (ms)', PROPERTY_SHOW)
      C4:SetPropertyAttribs('Stop Relay Pulse Time (ms)', PROPERTY_SHOW)
    end

    -- Hide Fail Safe Secs for Pulse Relay
    C4:SetPropertyAttribs('Fail Safe Seconds', PROPERTY_HIDE)
  end

  C4:SetPropertyAttribs('Invert Open/Toggle Relay', PROPERTY_SHOW)
  if (RELAYS == 1) then
    C4:SetPropertyAttribs('Invert Close Relay', PROPERTY_HIDE)
    C4:SetPropertyAttribs('Invert Stop Relay', PROPERTY_HIDE)
  elseif (RELAYS == 2) then
    C4:SetPropertyAttribs('Invert Close Relay', PROPERTY_SHOW)
    C4:SetPropertyAttribs('Invert Stop Relay', PROPERTY_HIDE)
  elseif (RELAYS == 3) then
    C4:SetPropertyAttribs('Invert Close Relay', PROPERTY_SHOW)
    C4:SetPropertyAttribs('Invert Stop Relay', PROPERTY_SHOW)
  end

end


function ON_PROPERTY_CHANGED.NumberofRelays(value)
  local relays = tonumber(value)

  if (relays ~= RELAYS) then -- number of relays has changed

    for i = 1, RELAYS do
      C4:RemoveDynamicBinding(i)
    end

    Outlets = {}
    Names = {}

    RELAYS = relays
    PersistData.RELAYS = relays
    PersistData.RelayBindings = {}
    if (RELAYS == 1) then
      Names[1] = 'Open-Close'

    elseif (RELAYS == 2) then
      Names[1] = 'Open'
      Names[2] = 'Close'

    elseif (RELAYS == 3) then
      Names[1] = 'Open'
      Names[2] = 'Close'
      Names[3] = 'Stop'
    end

    for i = 1, RELAYS do
      PersistData["RelayBindings"][i] = Names[i]
      C4:AddDynamicBinding(i, "CONTROL", false, Names[i] , "RELAY", false, false)
    end
  end
end


function ON_PROPERTY_CHANGED.RelayConfiguration(value)
  HOLD = (value == 'Hold')
end


function ON_PROPERTY_CHANGED.OpenedContactDebouncems(value)
  OPENDEBOUNCE = tonumber(value)
end


function ON_PROPERTY_CHANGED.ClosedContactDebouncems(value)
  CLOSEDEBOUNCE = tonumber(value)
end


function ON_PROPERTY_CHANGED.InvertClosedContact(value)
  INVERT_CLOSED_CONTACT = (value == 'Yes')
  OneShotTimer.Add(2, "SECONDS", GetGateState, "INVERT_CHANGED")
end


function ON_PROPERTY_CHANGED.InvertOpenedContact(value)
  INVERT_OPEN_CONTACT = (value == 'Yes')
  OneShotTimer.Add(2, "SECONDS", GetGateState, "INVERT_CHANGED")
end


function SetButtonColor(idBinding, onColor, offColor, strState)
  -- NOTE: MATCH_LED_STATE *has* to be *AFTER* the SetButtonColor...

  MySendToProxy(idBinding, "BUTTON_COLORS", {ON_COLOR = {COLOR_STR = onColor}, OFF_COLOR = {COLOR_STR = offColor}}, "NOTIFY")

  strState = strState or ''
  if (strState ~= '') then
    MySendToProxy(idBinding, 'MATCH_LED_STATE', {STATE = strState})
  end
end


function SetLEDColors()
  LED['Opened'] = Helper.RGB2HEX(Properties['Opened LED Color'])
  LED['Closed'] = Helper.RGB2HEX(Properties['Closed LED Color'])
  LED['Off'] = Helper.RGB2HEX(Properties['Off LED Color'])
  LED['Partial'] = Helper.RGB2HEX(Properties['Partial Open LED Color'])
  LED['Unknown'] = Helper.RGB2HEX(Properties['Unknown LED Color'])
end


function ON_PROPERTY_CHANGED.OpenedLEDColor(_) -- value
  OneShotTimer.Add(100, "MILLISECONDS", SetLEDColors, "SETLETCOLORS")
end


function ON_PROPERTY_CHANGED.ClosedLEDColor(_) -- value
  OneShotTimer.Add(100, "MILLISECONDS", SetLEDColors, "SETLETCOLORS")
end


function ON_PROPERTY_CHANGED.OffLEDColor(_) -- value
  OneShotTimer.Add(100, "MILLISECONDS", SetLEDColors, "SETLETCOLORS")
end


function ON_PROPERTY_CHANGED.PartialOpenLEDColor(_) -- value
  OneShotTimer.Add(100, "MILLISECONDS", SetLEDColors, "SETLETCOLORS")
end


function ON_PROPERTY_CHANGED.UnknownLEDColor(_) -- value
  OneShotTimer.Add(100, "MILLISECONDS", SetLEDColors, "SETLETCOLORS")
end


function OnTimerExpired(idTimer)

  if (idTimer == Timer.Debug) then
    dbg ('Turning Debug Mode Off (timer expired)')
    C4:UpdateProperty('Debug Mode', 'Off')
    OnPropertyChanged('Debug Mode')
  end

  if (idTimer == Timer.StillOpen) then
    Timer.StillOpen = C4:KillTimer(Timer.StillOpen or 0)
    MyFireEvent("Still Open")
    return
  end

  if (idTimer == Timer.Failsafe and HOLD) then
    dbg('Failsafe Expired')
    -- Failsafe is only triggered if there is a 'Stop' Relay... Otherwise, it opens the HOLD relays for open / close gate.
    if (RELAYS == 3) then
      Gate.StopCommand()
    end
  end
  C4:KillTimer(idTimer)
end


FILTER = {}
FILTER["MATCH_LED_STATE"] = true
FILTER["BUTTON_COLORS"] = true


function MySendToProxy(idBinding, strCommand, tParams, notify)
  strCommand = strCommand or ""
  tParams = tParams or ''

  if (not FILTER[strCommand]) then
    dbg("---STP--> [" .. (PROXY_NAME[idBinding] or " Unknown ") .. "]: " .. strCommand .. " (" .. formatParams(tParams) .. ")")
  end

  if (notify) then
    C4:SendToProxy(idBinding, strCommand, tParams, notify)
  else
    C4:SendToProxy(idBinding, strCommand, tParams)
  end
end


function formatParams(tParams)
  tParams = tParams or {}
  if (type(tParams) ~= "table") then tParams = {} end
  local out = {}
  for k,v in pairs(tParams) do
    if (k == "AccessToken") then
      table.insert(out, k .. ": [ACCESS TOKEN]")
    else
      if (type(v) == "table") then
        table.insert(out, k .. ": {" .. formatParams(v) .. "}")
      else
        table.insert(out, k .. ": " .. tostring(v))
      end
    end
  end
  return table.concat(out, ", ")
end


function ReceivedFromProxy(idBinding, strCommand, tParams)
  tParams = tParams or {}
  dbg("<--RFP--- [" .. PROXY_NAME[idBinding] .. "]: " .. strCommand .. " (" .. formatParams(tParams) .. ")")
  if type(PROXY_CMDS[strCommand]) == "function" then
    local success, retVal = pcall(PROXY_CMDS[strCommand], tParams, idBinding)
    if success then
      return retVal
    else
      dbg("Error in ReceivedFromProxy call... " .. retVal)
    end
  end
  return nil
end


function PROXY_CMDS.DO_CLICK(tParams, idBinding)
  if (idBinding == TOGGLE_LINK_ID) then
    PROXY_CMDS.SELECT(tParams) -- Toggle button click acts like UI button pressed
  elseif (idBinding == OPEN_LINK_ID) then
    Gate.OpenCommand()
  elseif (idBinding == CLOSE_LINK_ID) then
    Gate.CloseCommand()
  else
    print('Unhandled DO_CLICK binding ' .. idBinding)
  end
end


-- Calculation of state is delayed for initial state checks, since you need to know both states to know 'unknown' / 'partial'
-- This is only called on *initial* state, if there are no contacts.  Not called on relays changing...
function CalcStateFromRelays()
  --dbg("-------------------------- CalcStateFromRelays --------------------------")
  -- If there are no sensors, and pulse config on relay, no way to get state... Unknown...
  if (not HOLD) then
    dbg("CalcStateFromRelays -- Relays in pulse configuration. Unknown State.")
    Gate.UpdateState('Unknown', false)
    return
  end

  if (RELAYS == 1) then
    local relay_state = CUR_STATES[OPEN_RELAY_ID] or ""
    Gate.UpdateState(relay_state, false)
  else
    -- Don't care about stop relay, it can't tell us anything about state...
    local open_relay_state = CUR_STATES[OPEN_RELAY_ID] or ""
    local close_relay_state = CUR_STATES[CLOSE_RELAY_ID] or ""
    dbg("CalcStateFromRelays -- Opened [" .. open_relay_state .. "] Closed [" .. close_relay_state .. "]")
    if (open_relay_state == 'Closed') then
      if (close_relay_state == 'Closed') then
        Gate.UpdateState('Unknown', false) -- Both relays 'triggered' -- Unknown state
      else
        Gate.UpdateState('Opened', false) -- Open relay 'triggered'
      end
    else
      if (close_relay_state == 'Closed') then
        Gate.UpdateState('Closed', false) -- Close relay 'triggered'
      else
        Gate.UpdateState('Unknown', false) -- Neither relay 'triggered' -- Unknown state
      end
    end
  end
end


function CalcState(bFireEvents)
  local state = Gate.CurrentSensorState()

  if (state == 'Opened') or (state == 'Closed') then Timer.Failsafe = Helper.KillTimer(Timer.Failsafe) end
  Gate.UpdateState(state, bFireEvents)
end


function PROXY_CMDS.OPENED(tParams, idBinding)
  -- Contact, should always use for state...
  if (idBinding == OPENED_CONTACT_SENSOR_ID) then
      CUR_STATES[idBinding] = INVERTED[INVERT_OPEN_CONTACT].Opened
      OneShotTimer.Add(OPENDEBOUNCE, "MILLISECONDS", function() CalcState(tParams.STATE_ONLY) end, "ContactInput")
      KNOWN_STATE = true
    return
  end
  if (idBinding == CLOSED_CONTACT_SENSOR_ID) then
      CUR_STATES[idBinding] = INVERTED[INVERT_CLOSED_CONTACT].Opened
      OneShotTimer.Add(CLOSEDEBOUNCE, "MILLISECONDS", function() CalcState(tParams.STATE_ONLY) end, "ContactInput")
      KNOWN_STATE = true
    return
  end

  CUR_STATES[idBinding] = INVERTED[INVERT_OPEN_RELAY].Opened

  -- Calculate state based on relay states... On initial (or STATE_OPENED/STATE_CLOSED) entries...
  if ((NUM_SENSORS == 0) and (tParams.STATE_ONLY)) then
    OneShotTimer.Add(500, "MILLSECONDS", CalcStateFromRelays, "RelayInitialState")
  end
end


function PROXY_CMDS.CLOSED(tParams, idBinding)
  -- Contact, should always use for state...
  if (idBinding == OPENED_CONTACT_SENSOR_ID) then
      CUR_STATES[idBinding] = INVERTED[INVERT_OPEN_CONTACT].Closed
      OneShotTimer.Add(OPENDEBOUNCE, "MILLISECONDS", function() CalcState(tParams.STATE_ONLY) end, "ContactInput")
      KNOWN_STATE = true
    return
  end
  if (idBinding == CLOSED_CONTACT_SENSOR_ID) then
      CUR_STATES[idBinding] = INVERTED[INVERT_CLOSED_CONTACT].Closed
      OneShotTimer.Add(CLOSEDEBOUNCE, "MILLISECONDS", function() CalcState(tParams.STATE_ONLY) end, "ContactInput")
      KNOWN_STATE = true
    return
  end

  CUR_STATES[idBinding] = INVERTED[INVERT_CLOSE_RELAY].Closed

  -- Calculate state based on relay states... On initial (or STATE_OPENED/STATE_CLOSED) entries...
  if ((NUM_SENSORS == 0) and (tParams.STATE_ONLY)) then
    OneShotTimer.Add(500, "MILLSECONDS", CalcStateFromRelays, "RelayInitialState")
  end
end


function PROXY_CMDS.STATE_CLOSED(tParams, idBinding)
  tParams.STATE_ONLY = true
  PROXY_CMDS.CLOSED(tParams, idBinding)
end


function PROXY_CMDS.STATE_OPENED(tParams, idBinding)
  tParams.STATE_ONLY = true
  PROXY_CMDS.OPENED(tParams, idBinding)
end


function PROXY_CMDS.REQUEST_BUTTON_COLORS(_, idBinding) -- tParams
  if (idBinding == TOGGLE_LINK_ID) then
    SetButtonColor(TOGGLE_LINK_ID, LED['Opened'], LED['Closed'])
  elseif (idBinding == OPEN_LINK_ID) then
    SetButtonColor(OPEN_LINK_ID, LED['Opened'], LED['Off'])
  elseif (idBinding == CLOSE_LINK_ID) then
    SetButtonColor(CLOSE_LINK_ID, LED['Closed'], LED['Off'])
  end
  OneShotTimer.Add(5, "SECONDS", function() Gate.UpdateState(nil, false) end, "BUTTON_LINK_CHANGED")
end


function PROXY_CMDS.SELECT(_) -- tParams
  if (STATE == 'Closed') then -- open it
    Gate.OpenCommand()
  else -- close it
    Gate.CloseCommand()
  end
end


function Helper.AddTimer(timer, count, units, recur)
  Helper.KillTimer(timer or 0)
  return C4:AddTimer(count, units, recur or false)
end


function Helper.ContactStatus(info)
  C4:UpdateProperty('Contact Status', info)
  dbg(info)
end


function Helper.KillAllTimers()
  for k,v in pairs(Timer or {}) do
    if (type(v) == 'number') then
      Timer[k] = Helper.KillTimer(Timer[k])
    end
  end
end


function Helper.KillTimer(timer)
  return C4:KillTimer(tonumber(timer) or 0)
end


function Helper.HEX2RGB(hex)
  local h, rgb = tohex(hex), ""
  for color in string.gmatch(h, ".") do
    if (rgb ~= "") then rgb = rgb .. "," end
    rgb = rgb .. string.format("%03d", string.byte(color))
  end
  return rgb
end


function Helper.RGB2HEX(rgb)
  local hex = ''
  for color in string.gmatch(rgb, "%d+") do
    hex = hex .. string.format('%02x', color)
  end
  return hex
end


-- Truth Table of Closed/Opened sensors and door state... gSensorState[closed_val][opened_val]...
gSensorState = {}
gSensorState[''] =    { [''] = 'Unknown',   Opened = 'Closed',  Closed = 'Opened'}
gSensorState.Opened = { Opened = 'Partial', Closed = 'Opened',  [''] = 'Opened'}
gSensorState.Closed = { Opened = 'Closed',  Closed = 'Unknown', [''] = 'Closed'}


function Gate.CurrentSensorState()
  local closed_val = CUR_STATES[CLOSED_CONTACT_SENSOR_ID] or ""
  if (not CLOSED_SENSOR) then closed_val = "" end
  local opened_val = CUR_STATES[OPENED_CONTACT_SENSOR_ID] or ""
  if (not OPENED_SENSOR) then opened_val = "" end
  dbg("CurrentSensorState -- Closed Contact: [" .. closed_val .. "] Opened Contact: [" .. opened_val .. "]")

  return gSensorState[closed_val][opened_val]
end


-- If a single toggle relay, should *always* toggle, not just open if not open, etc... BZ# 37068
function Gate.OpenCommand()
  if (HOMEKIT) then hk_set_door(true) return end
  local single_pulse = (RELAYS == 1) and (not HOLD)

  -- If there are sensors, verify that the door is not already in that state... if single pulse, and haven't gotten a KNOWN_STATE update, pulse anyway.
  local state = Gate.CurrentSensorState()
  if (state == 'Opened') then
    if (not single_pulse) or (KNOWN_STATE) then
      dbg("Already Open.  Not opening.")
      return
    end
  end

  dbg('Sending Open')
  Timer.Failsafe = Helper.KillTimer(Timer.Failsafe)

  -- Pulse Open/Close relay (toggle) special case...
  if single_pulse then -- just pulse close regardless
    MySendToProxy(OPEN_RELAY_ID, INVERTED[INVERT_OPEN_RELAY].CLOSE)
    local openpulse = tonumber(Properties["Open/Toggle Relay Pulse Time (ms)"] or 500) or 500
    OneShotTimer.Add(openpulse, "MILLISECONDS", function() MySendToProxy(OPEN_RELAY_ID, INVERTED[INVERT_OPEN_RELAY].OPEN) end, "TOGGLE")
    return
  end

  if (RELAYS == 1) then
    MySendToProxy(OPEN_RELAY_ID, INVERTED[INVERT_OPEN_RELAY].OPEN) -- Single relay, Open
  else
    -- Ensure 'break-before-make' for the relays...
    if (INVERT_OPEN_RELAY) then
      MySendToProxy(OPEN_RELAY_ID, INVERTED[INVERT_OPEN_RELAY].CLOSE)
      if (RELAYS == 3) then MySendToProxy(STOP_RELAY_ID, INVERTED[INVERT_STOP_RELAY].OPEN) end
      MySendToProxy(CLOSE_RELAY_ID, INVERTED[INVERT_CLOSE_RELAY].OPEN)
    else
      MySendToProxy(CLOSE_RELAY_ID, INVERTED[INVERT_CLOSE_RELAY].OPEN)
      if (RELAYS == 3) then MySendToProxy(STOP_RELAY_ID, INVERTED[INVERT_STOP_RELAY].OPEN) end
      MySendToProxy(OPEN_RELAY_ID, INVERTED[INVERT_OPEN_RELAY].CLOSE)
    end
  end

  -- If pulse on 2/3 relay, open the open relay after pulse delay
  if (not HOLD) then
    local openpulse = tonumber(Properties["Open/Toggle Relay Pulse Time (ms)"] or 500) or 500
    OneShotTimer.Add(openpulse, "MILLISECONDS", function() MySendToProxy(OPEN_RELAY_ID, INVERTED[INVERT_OPEN_RELAY].OPEN) end, "TOGGLE")
  end

  -- Single relay HOLD can't use failsafe...
  if (FAILSAFE ~= 0) and (RELAYS > 1) then
    Timer.Failsafe = Helper.AddTimer(Timer.Failsafe, FAILSAFE, 'SECONDS', false)
  end

  -- Immediate feedback if no sensors enabled...
  if (NUM_SENSORS == 0) then Gate.UpdateState('Opened') end
end


-- If a single toggle relay, should *always* toggle, not just open if not open, etc... BZ# 37068
function Gate.CloseCommand()
  if (HOMEKIT) then hk_set_door(false) return end
  local single_pulse = (RELAYS == 1) and (not HOLD)

  -- If there are sensors, verify that the door is not already in that state... if single pulse, and haven't gotten a KNOWN_STATE update, pulse anyway.
  local state = Gate.CurrentSensorState()
  if (state == 'Closed') then
    if (not single_pulse) or (KNOWN_STATE) then
      dbg("Already Closed.  Not closing.")
      return
    end
  end

  dbg('Sending Close')
  Timer.Failsafe = Helper.KillTimer(Timer.Failsafe)

  -- Pulse Open/Close relay (toggle) special case...
  if single_pulse then -- just pulse close regardless
    MySendToProxy(OPEN_RELAY_ID, INVERTED[INVERT_OPEN_RELAY].CLOSE)
    local openpulse = tonumber(Properties["Open/Toggle Relay Pulse Time (ms)"] or 500) or 500
    OneShotTimer.Add(openpulse, "MILLISECONDS", function() MySendToProxy(OPEN_RELAY_ID, INVERTED[INVERT_OPEN_RELAY].OPEN) end, "TOGGLE")
    return
  end

  if (RELAYS == 1) then
    MySendToProxy(OPEN_RELAY_ID, INVERTED[INVERT_OPEN_RELAY].CLOSE) -- Single relay, Close
  else
    -- Ensure 'break-before-make' for the relays...
    if (INVERT_CLOSE_RELAY) then
      MySendToProxy(CLOSE_RELAY_ID, INVERTED[INVERT_CLOSE_RELAY].CLOSE)
      if (RELAYS == 3) then MySendToProxy(STOP_RELAY_ID, INVERTED[INVERT_STOP_RELAY].OPEN) end
      MySendToProxy(OPEN_RELAY_ID, INVERTED[INVERT_OPEN_RELAY].OPEN)
    else
      MySendToProxy(OPEN_RELAY_ID, INVERTED[INVERT_OPEN_RELAY].OPEN)
      if (RELAYS == 3) then MySendToProxy(STOP_RELAY_ID, INVERTED[INVERT_STOP_RELAY].OPEN) end
      MySendToProxy(CLOSE_RELAY_ID, INVERTED[INVERT_CLOSE_RELAY].CLOSE)
    end
  end

  -- If pulse on 2/3 relay, open the open relay after pulse delay
  if (not HOLD) then
    local closepulse = tonumber(Properties["Close Relay Pulse Time (ms)"] or 500) or 500
    OneShotTimer.Add(closepulse, "MILLISECONDS", function() MySendToProxy(CLOSE_RELAY_ID, INVERTED[INVERT_CLOSE_RELAY].OPEN) end, "TOGGLE")
  end

  -- Single relay HOLD can't use failsafe...
  if (FAILSAFE ~= 0) and (RELAYS > 1) then
    Timer.Failsafe = Helper.AddTimer(Timer.Failsafe, FAILSAFE, 'SECONDS', false)
  end

  -- Immediate feedback if no sensors enabled...
  if (NUM_SENSORS == 0) then Gate.UpdateState('Closed') end
end


function Gate.StopCommand()
  if (HOMEKIT) then return end
  dbg('Sending Stop')
  if (HOLD and RELAYS == 2) then
    MySendToProxy(OPEN_RELAY_ID, INVERTED[INVERT_OPEN_RELAY].OPEN)
    MySendToProxy(CLOSE_RELAY_ID, INVERTED[INVERT_CLOSE_RELAY].OPEN)
  elseif (RELAYS == 3) then
    MySendToProxy(OPEN_RELAY_ID, INVERTED[INVERT_OPEN_RELAY].OPEN)
    MySendToProxy(CLOSE_RELAY_ID, INVERTED[INVERT_CLOSE_RELAY].OPEN)
    MySendToProxy(STOP_RELAY_ID, INVERTED[INVERT_STOP_RELAY].CLOSE)

    -- Finish pulse on Stop relay after pulse time...
    if (not HOLD) then
      local stoppulse = tonumber(Properties["Stop Relay Pulse Time (ms)"] or 500) or 500
      OneShotTimer.Add(stoppulse, "MILLISECONDS", function() MySendToProxy(STOP_RELAY_ID, INVERTED[INVERT_STOP_RELAY].OPEN) end, "TOGGLE")
    end
  end
end


ACTION = {}
ACTION['Partial'] = "Partially Open"
ACTION['Opened'] = "Opened"
ACTION['Closed'] = "Closed"
ACTION['Unknown'] = "Unknown"


function StillOpenStart()
  if ((Timer.StillOpen or 0) == 0) then
    local stillopentime = tonumber(Properties["Still Open Time (s)"]) or 0
    if (stillopentime == 0) then return end
    dbg("Starting Still Open Check Timer: " .. stillopentime .. " seconds.")
    Timer.StillOpen = Helper.AddTimer(Timer.StillOpen, stillopentime, 'SECONDS', false)
  end
end


function Gate.UpdateState(strState, bFireEvents) -- uses STATE global

  -- DRIV-4981...
  local HistoryCategories = {
    Door = {            category = "Locks & Sensors", subcategory = "Door (Relay)" },
    ["Garage Door"] = { category = "Locks & Sensors", subcategory = "Garage Door (Relay)" },
    Gate = {            category = "Locks & Sensors", subcategory = "Gate (Relay)" },
    Window = {          category = "Locks & Sensors", subcategory = "Window (Relay)" },
    Lift = {            category = "Screens & Lifts", subcategory = "Motorized Screen" },
    Screen = {          category = "Screens & Lifts", subcategory = "Motorized Screen" },
  }

  local devtype = C4:GetCapability('DeviceType') or "Unknown"
  local history = HistoryCategories[devtype] or { category = "Unknown", subcategory = "Unknown" }

  if (strState == STATE) then dbg("UpdateState -- State not changed.  Exiting.") return end

  if (strState == 'Opened') then
    dbg("Killing EXPECTED_OPEN...")
    OneShotTimer.Kill("EXPECTED_OPEN")
    if (gStartedOpeningTime) then
      dbg("Opened in " .. os.time() - gStartedOpeningTime .. " Seconds. Killing timer.")
      gStartedOpeningTime = nil
    end
  end
  if (strState == 'Closed') then
    dbg("Killing EXPECTED_CLOSE...")
    OneShotTimer.Kill("EXPECTED_CLOSE")
    if (gStartedClosingTime) then
      dbg("Closed in " .. os.time() - gStartedClosingTime .. " Seconds. Killing timer.")
      gStartedClosingTime = nil
    end
  end

  if (strState == 'Partial') then
    if (STATE == 'Closed') then -- Door is opening
      if (CLOSED_SENSOR) then
        gStartedOpeningTime = os.time()
        local expected_open_time = Properties["Expected Open Time (s)"] or 60
        dbg("Expect Open State in " .. expected_open_time .. " Seconds")
        dbg("Starting EXPECTED_OPEN...")
        OneShotTimer.Add(expected_open_time, "SECONDS",
          function()
            dbg("EXPECTED_OPEN fired...")
            dbg("Did not open within " .. expected_open_time .. " Seconds")
            C4:FireEvent("Did Not Open")
          end
        , "EXPECTED_OPEN")
      end
    elseif (STATE == 'Opened') then -- Door is closing
      if (OPENED_SENSOR) then
        gStartedClosingTime = os.time()
        local expected_close_time = Properties["Expected Close Time (s)"] or 60
        dbg("Expect Closed State in " .. expected_close_time .. " Seconds")
        dbg("Starting EXPECTED_CLOSE...")
        OneShotTimer.Add(expected_close_time, "SECONDS",
          function()
            dbg("EXPECTED_CLOSE fired...")
            dbg("Did not close within " .. expected_close_time .. " Seconds")
            C4:FireEvent("Did Not Close")
          end
        , "EXPECTED_CLOSE")
      end
    end
  end

  STATE = strState or STATE
  if (bFireEvents == nil) then bFireEvents = true end
  local iconset = Properties["Icon Set"] or ""
  if (iconset ~= "") then iconset = "_" .. iconset end

  C4:SetVariable('STATE', STATE)

  if (bFireEvents) then
    MyFireEvent(STATE)
    C4:RecordHistory("Info", STATE, history.category, history.subcategory, "The " .. devtype .. " was " .. ACTION[STATE])
  else
    C4:RecordHistory("Info", STATE, history.category, history.subcategory, "The " .. devtype .. " state changed to " .. ACTION[STATE])
  end

  MySendToProxy(BUTTON_PROXY_ID, "ICON_CHANGED", {icon=STATE .. iconset, icon_description=STATE })

  if (STATE == 'Opened') then
    SetButtonColor(TOGGLE_LINK_ID, LED['Opened'], LED['Closed'], '1')
    SetButtonColor(CLOSE_LINK_ID, LED['Closed'], LED['Off'], '0')
    SetButtonColor(OPEN_LINK_ID, LED['Opened'], LED['Off'], '1')
    StillOpenStart()
    return
  end
  if (STATE == 'Closed') then
    SetButtonColor(TOGGLE_LINK_ID, LED['Opened'], LED['Closed'], '0')
    SetButtonColor(OPEN_LINK_ID, LED['Opened'], LED['Off'], '0')
    SetButtonColor(CLOSE_LINK_ID, LED['Closed'], LED['Off'], '1')
    Timer.StillOpen = C4:KillTimer(Timer.StillOpen or 0)
    return
  end
  if (STATE == 'Partial') then
    SetButtonColor(TOGGLE_LINK_ID, LED['Partial'], LED['Partial'], '1')
    SetButtonColor(OPEN_LINK_ID, LED['Partial'], LED['Partial'], '0')
    SetButtonColor(CLOSE_LINK_ID, LED['Partial'], LED['Partial'], '0')
    StillOpenStart()
    return
  end
  if (STATE == 'Unknown') then
    SetButtonColor(TOGGLE_LINK_ID, LED['Unknown'], LED['Unknown'], '1')
    SetButtonColor(OPEN_LINK_ID, LED['Unknown'], LED['Unknown'], '0')
    SetButtonColor(CLOSE_LINK_ID, LED['Unknown'], LED['Unknown'], '0')
    StillOpenStart()
    return
  end
  dbg("Unknown State: " .. strState)
end


function MyFireEvent(strEvent)
  dbg('--Event-> ' .. strEvent)
  C4:FireEvent(strEvent)
end


----------------------- INCLUDES ---------------------------
-- TODO: Make this a true module, by returning it inside a local table...
-- Now allows for 'named' one-shot timers.  If the name is re-used, reset timer, don't make a new one...

---------------------------------------------------------
--------------  OneShotTimer Timers Module  ----------------
---------------------------------------------------------
do
  local OTE, ODD
  local MTFUNC = function() end

  OneShotTimer = {}

  -- Check to see if new C4: SetTimer functionality exists.  If so, use that instead of 'monkey patching' the OnTimerExpired...
  if (LuaC4Object.SetTimer) then
    local timers = {}

    function OneShotTimer.Callback(timer)
      local tvals = timers[timer]
      if (tvals) then
        timer:Cancel()
        tvals.callback(tvals.name)
        timers[timer] = nil
      end
    end

    function OneShotTimer.ClearAll()
      for timer in pairs(timers) do timer:Cancel() end
      timers = {}
    end

    function OneShotTimer.OnDriverDestroyed()
      OneShotTimer.ClearAll()
      ODD()
    end

    function OneShotTimer.Kill(Name)
      if ((Name or "") == "") then return end
      for timer, tvals in pairs(timers) do
        if (tvals.name == Name) then
          timer:Cancel()
	  timers[timer] = nil
	  return
	end
      end
    end

    INTERVAL_MULT = {MILLISECONDS = 1, SECONDS = 1000, MINUTES = 1000*60, HOURS = 1000*60*60}

    function OneShotTimer.Add(nInterval, strUnits, fCallback, Name)
      OneShotTimer.Kill(Name)
      local time_ms = (tonumber(nInterval) or 1) * (INTERVAL_MULT[strUnits] or 1)
      if (time_ms < 1) then time_ms = 1 end
      local timer = C4:SetTimer(time_ms, OneShotTimer.Callback)
      timers[timer] = {callback = fCallback, name = (Name or "")}
    end

    -----  Overrides:  --------
    ODD , OnDriverDestroyed = OnDriverDestroyed or MTFUNC, OneShotTimer.OnDriverDestroyed
    ---  END Overrides:  ------

  else

    local tCallback = {}
  
    function OneShotTimer.OnTimerExpired(idTimer)
      if (tCallback[idTimer] ~= nil) then
        C4:KillTimer(idTimer)
        tCallback[idTimer].CALLBACK(tostring(tCallback[idTimer].NAME))
        tCallback[idTimer] = nil
      else
        OTE(idTimer)
      end
    end

    function OneShotTimer.ClearAll()
      for k,v in pairs(tCallback) do C4:KillTimer(k) end
      tCallback = {}
    end

    function OneShotTimer.OnDriverDestroyed()
      OneShotTimer.ClearAll()
      ODD()
    end

    function OneShotTimer.Kill(Name)
      if (Name ~= nil) then
        for k,v in pairs(tCallback) do if (v.NAME == Name) then C4:KillTimer(k) tCallback[k] = nil end end
      end
    end

    function OneShotTimer.Add(nInterval, strUnits, fCallback, Name)
      local id = C4:AddTimer(nInterval, strUnits)

      -- Look for name if not nil, if found, remove existing timer callback...
      if (Name ~= nil) then
        for k,v in pairs(tCallback) do if (v.NAME == Name) then C4:KillTimer(k) tCallback[k] = nil end end
      end
      tCallback[id] = {CALLBACK = fCallback, NAME = Name}
    end

    -----  Overrides:  --------
    OTE , OnTimerExpired = OnTimerExpired or MTFUNC, OneShotTimer.OnTimerExpired
    ODD , OnDriverDestroyed = OnDriverDestroyed or MTFUNC, OneShotTimer.OnDriverDestroyed
    ---  END Overrides:  ------

  end
end
---------------------------------------------------------
-----------  END OneShotTimer Timers Module  ---------------
---------------------------------------------------------

------------------------------------------------------------

if (C4.AllowExecute) then C4:AllowExecute(true) end
print("Driver Loaded..." .. os.date())


-- Fix for Defect #35178, contacts not seen on local driver sync update...
CLOSED_SENSOR = (C4:GetBoundProviderBinding(C4:GetDeviceID(), CLOSED_CONTACT_SENSOR_ID) ~= 0)
OPENED_SENSOR = (C4:GetBoundProviderBinding(C4:GetDeviceID(), OPENED_CONTACT_SENSOR_ID) ~= 0)
ReportSensorUsage() -- Set to zero on start, OnBindingChanged will update it as they connect...

GetGateState()

if (CAPTURE_INIT) then
  gInitCapture = true
  OneShotTimer.Add(2, "MINUTES", function() gInitCapture = false end) -- Only capture Init msgs for first 2 minutes of driver active...
  OneShotTimer.Add(15, "MINUTES", function() gInit = nil end) -- Only capture Init msgs for first 2 minutes of driver active...
end


