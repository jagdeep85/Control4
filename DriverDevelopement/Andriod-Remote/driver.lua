require("socket")

-- UDP socket
udp = nil

-- Driver properties (set these in Composer)
DEVICE_IP       = Properties["Device IP"] or "192.168.1.64"
DEVICE_PORT     = tonumber(Properties["Device Port"]) or 1028
REPEAT_INTERVAL = tonumber(Properties["Repeat Interval (ms)"]) or 100

-- App launch mappings - customize these for your device
-- Map app names to the actual commands your device understands
APP_LAUNCH_COMMANDS = {
    ["Netflix"]     = "launchApp netflix",
    ["Hulu"]        = "launchApp hulu", 
    ["YouTube"]     = "launchApp youtube",
    ["Disney+"]     = "launchApp disneyplus",
    ["Prime Video"] = "launchApp primevideo",
    ["Apple TV+"]   = "launchApp appletv",
    ["HBO Max"]     = "launchApp hbomax",
    ["Spotify"]     = "launchApp spotify",
}

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

-- Current app tracking
local currentApp = nil

function ExecuteCommand(command, params)
    print("Executing command: " .. tostring(command))
    
    if command == "PrintApps" then
        print("\n=== Available Apps ===")
        for appName, cmd in pairs(APP_LAUNCH_COMMANDS) do
            print("  " .. appName .. " -> " .. cmd)
        end
        print("======================\n")
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
        print("Device IP updated to: " .. cachedIP)
        
    elseif strProperty == "Device Port" then
        DEVICE_PORT = tonumber(value) or 1028
        cachedPort = DEVICE_PORT
        print("Device Port updated to: " .. cachedPort)
        
    elseif strProperty == "Repeat Interval (ms)" then
        REPEAT_INTERVAL = tonumber(value) or 100
        cachedRepeatInterval = REPEAT_INTERVAL
        print("Repeat Interval updated to: " .. cachedRepeatInterval)
        
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
        print("ERROR: Socket library not available")
        return
    end
    if not udp then
        udp = socket.udp()
        udp:settimeout(0)
        print("UDP socket initialized successfully")
        print("Target: " .. cachedIP .. ":" .. cachedPort)
    end
end

function SendUDP(command)
    print("Sending UDP command: " .. command .. " to " .. cachedIP .. ":" .. cachedPort)
    if udp then
        local bytes, err = udp:sendto(command, cachedIP, cachedPort)
        if err then
            print("UDP send error: " .. tostring(err))
        else
            print("UDP command sent successfully (" .. tostring(bytes) .. " bytes)")
        end
    else
        print("ERROR: UDP socket not initialized")
    end
end

-- -----------------------------
-- App Launch Function
-- -----------------------------
function LaunchApp(appName, appId)
    print("\n" .. string.rep("=", 60))
    print("LAUNCHING APP")
    print(string.rep("=", 60))
    print("App Name: " .. tostring(appName))
    print("App ID: " .. tostring(appId))
    print("Device: " .. cachedIP .. ":" .. cachedPort)
    
    local launchCommand = "openApp " .. tostring(appName)

    if launchCommand then
        SendUDP(launchCommand)
        currentApp = appName
        C4:UpdateProperty("Current App", appName or "Unknown")
        print("SUCCESS: App launch command sent")
    else
        print("ERROR: No launch command found for app: " .. tostring(appName))
        print("Available apps:")
        for name, _ in pairs(APP_LAUNCH_COMMANDS) do
            print("  - " .. name)
        end
        print("\nPlease add this app to APP_LAUNCH_COMMANDS table")
    end
    
    print(string.rep("=", 60) .. "\n")
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
    print("\n" .. string.rep("=", 60))
    print("Physical Device Driver Initializing")
    print(string.rep("=", 60))
    print("Device IP: " .. cachedIP)
    print("Device Port: " .. cachedPort)
    print("Repeat Interval: " .. cachedRepeatInterval .. "ms")
    print(string.rep("=", 60) .. "\n")
    
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
    tParams = tParams or {}
    
    print("\n" .. string.rep("=", 60))
    print("PHYSICAL DEVICE - ReceivedFromProxy")
    print(string.rep("=", 60))
    print("Binding ID: " .. bindingID)
    print("Command: " .. strCommand)
    print("Parameters:")
    for k, v in pairs(tParams) do
        print("  " .. k .. " = " .. tostring(v))
    end
    print(string.rep("=", 60) .. "\n")
    
    -- Handle PASSTHROUGH first
    if (strCommand == 'PASSTHROUGH') then
        strCommand = tParams.PASSTHROUGH_COMMAND
        print("Extracted PASSTHROUGH command: " .. tostring(strCommand))
        tParams.PASSTHROUGH_COMMAND = nil
    end
    
    -- ===== HANDLE APP LAUNCH =====
    if (strCommand == 'LAUNCH_APP') then
        local appName = tParams.APP_NAME
        local appId = tParams.APP_ID or tParams.CHANNEL_ID
        
        print(">>> LAUNCH_APP COMMAND RECEIVED <<<")
        print("App Name from mini-app: " .. tostring(appName))
        print("App ID from mini-app: " .. tostring(appId))
        
        LaunchApp(appName, appId)
        return
    end
    
    -- ===== HANDLE LONG-PRESS COMMANDS =====
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
    
    -- ===== HANDLE SINGLE-PRESS COMMANDS =====
    else
        local key = map[strCommand]
        if key then
            print("Mapped command '" .. strCommand .. "' to key: " .. key)
            SendUDP(key)
        else
            print("WARNING: Unknown command: " .. strCommand)
            print("Command not found in map table")
        end
    end
end