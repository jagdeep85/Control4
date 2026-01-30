require("socket")

-- UDP socket
udp = nil

-- Driver properties (set these in Composer)
DEVICE_IP       = Properties["Device IP"] or "192.168.1.64"
DEVICE_PORT     = tonumber(Properties["Device Port"]) or 1028
REPEAT_INTERVAL = tonumber(Properties["Repeat Interval (ms)"]) or 100

-- Map proxy commands to device keycodes
map = {
	
    UP          = "dpadUp",
    DOWN        = "dpadDown",
    LEFT        = "dpadLeft",
    RIGHT       = "dpadRight",
    ENTER       = "dpadCenter",
    CANCEL      = "back",
    HOME        = "home",
    APP_SWITCH  = "recent",
    --SLEEP       = "lockScreen",
	--OFF         = "lockScreen",
    VOLUME_UP   = "volumeUp",
    VOLUME_DOWN = "volumeDown",
    VOLUME_MUTE = "volumeNormal",
    NUMBER_1    = "pressNumber1",
    NUMBER_2    = "pressNumber2",
    NUMBER_3    = "pressNumber3",
    NUMBER_4    = "pressNumber4",
    NUMBER_5    = "pressNumber5",
    NUMBER_6    = "pressNumber6",
    NUMBER_7    = "pressNumber7",
    NUMBER_8    = "pressNumber8",
    NUMBER_9    = "pressNumber9",
    NUMBER_0    = "pressNumber0",
    MENU        = "home",
    GUIDE       = "keycodeGuide",
    PROGRAM_A   = "keycode KEYCODE_PROG_RED",
    PROGRAM_B   = "keycode KEYCODE_PROG_GREEN",
    PROGRAM_C   = "keycode KEYCODE_PROG_YELLOW",
    PROGRAM_D   = "keycode KEYCODE_PROG_BLUE",
}

-- Timer ID
TIMER_ID_REPEAT = 1

-- Session tracking for instant stop
local activeSessionId = nil

-- Cached values for performance
local cachedIP = DEVICE_IP
local cachedPort = DEVICE_PORT
local cachedRepeatInterval = REPEAT_INTERVAL



function ExecuteCommand(command, params)
	print("Executing command: " .. tostring(command))
    if command == "PrintApps" then
        print("Sending dpadRight command to Roku device via UDP")
    end
end
-- -----------------------------
-- Property Changed Handler
-- -----------------------------
function OnPropertyChanged(strProperty)
	print("Property Changed: " .. strProperty)
    local value = Properties[strProperty]
    
    if strProperty == "Device IP" then
        DEVICE_IP = value or "192.168.1.64"
        cachedIP = DEVICE_IP
        
    elseif strProperty == "Device Port" then
        DEVICE_PORT = tonumber(value) or 1028
        cachedPort = DEVICE_PORT
        
    elseif strProperty == "Repeat Interval (ms)" then
        REPEAT_INTERVAL = tonumber(value) or 100
        cachedRepeatInterval = REPEAT_INTERVAL
        
        -- Restart timer with new interval if currently active
        if activeSessionId then
            C4:KillTimer(TIMER_ID_REPEAT)
            C4:SetTimer(cachedRepeatInterval, function()
                OnRepeatTimer(activeSessionId.id, activeSessionId.key)
            end, true, TIMER_ID_REPEAT)
        end
    end
end

-- -----------------------------
-- UDP Functions
-- -----------------------------
function InitUDP()
    if not socket then
        print("Socket library not available")
        return
    end
    if not udp then
        udp = socket.udp()
        udp:settimeout(0)
        print("UDP socket initialized")
    end
end

function SendUDP(command)
	print("Sending UDP command: " .. command)
    if udp then
        udp:sendto(command, cachedIP, cachedPort)
    end
end

-- -----------------------------
-- Long-Press Functions
-- -----------------------------
function StartLongPress(direction)
    local key = map[direction]
    if not key then return end
    
    -- Create new session with unique ID
    local sessionId = {
        id = os.time() .. math.random(1000, 9999),
        key = key
    }
    
    -- Set new session FIRST (invalidates any pending timer callbacks)
    activeSessionId = sessionId
    
    -- Kill old timer
    C4:KillTimer(TIMER_ID_REPEAT)
    
    -- Send initial command immediately
    SendUDP(key)
    
    -- Start repeating timer
    C4:SetTimer(cachedRepeatInterval, function()
        OnRepeatTimer(sessionId.id, key)
    end, true, TIMER_ID_REPEAT)
end

function OnRepeatTimer(sessionId, key)
    -- Only send if this session is still active
    if not activeSessionId or activeSessionId.id ~= sessionId then
        return
    end
    
    SendUDP(key)
end

function StopLongPress()
    if not activeSessionId then return end
    
    -- Invalidate session IMMEDIATELY (stops any pending timer callbacks)
    activeSessionId = nil
    
    -- Kill timer
    C4:KillTimer(TIMER_ID_REPEAT)
end

-- -----------------------------
-- Driver Lifecycle
-- -----------------------------
function OnDriverInit()
    print("Driver initializing")
    InitUDP()
end

function OnDriverDestroyed()
    print("Driver shutting down")
    StopLongPress()
    if udp then
        udp:close()
        udp = nil
    end
end

-- -----------------------------
-- Proxy Commands Handler
-- -----------------------------
function ReceivedFromProxy(bindingID, strCommand, tParams)
	print("ReceivedFromProxy Command Received: " .. strCommand)
    -- Long-press START commands
    if strCommand == "START_UP" then
        StartLongPress("UP")
    elseif strCommand == "START_DOWN" then
        StartLongPress("DOWN")
    elseif strCommand == "START_LEFT" then
        StartLongPress("LEFT")
    elseif strCommand == "START_RIGHT" then
        StartLongPress("RIGHT")
    
    -- Long-press STOP commands
    elseif strCommand == "STOP_UP" or strCommand == "STOP_DOWN" or 
           strCommand == "STOP_LEFT" or strCommand == "STOP_RIGHT" then
        StopLongPress()
    
    -- Single-press commands
    else
        local key = map[strCommand]
        if key then
            SendUDP(key)
        end
    end
end