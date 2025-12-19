-- Global variables for driver state
local g_deviceIP = ""
local g_devicePort = 0
local g_isConnected = false

function OnDriverInit()
    -- Load properties during driver initialization
    g_deviceIP = Properties["Device IP"]
    g_devicePort = tonumber(Properties["Device Port"]) or 5000
    
    -- Validate configuration
    if g_deviceIP == "" then
        C4:ErrorLog("Device IP property is not configured")
        return false
    end
    
    print("Initializing driver for device at " .. g_deviceIP .. ":" .. g_devicePort)
    
    -- Attempt initial connection
    ConnectToDevice()
end

function ConnectToDevice()
    print("Connecting to " .. g_deviceIP .. ":" .. g_devicePort)
    C4:NetConnect(6001, g_devicePort)
end

function OnConnectionStatusChanged(idBinding, nPort, strStatus)
    if idBinding == 6001 then
        if strStatus == "ONLINE" then
            g_isConnected = true
            print("Connected to device successfully")
            -- Send initialization command
            SendDeviceCommand("INIT")
        else
            g_isConnected = false
            print("Disconnected from device")
        end
    end
end

function SendDeviceCommand(cmd)
    if not g_isConnected then
        print("Device not connected")
        return
    end
    
    -- Use timeout property for command execution
    local timeout = tonumber(Properties["Command Timeout"]) or 5
    print("Sending command: " .. cmd .. " (timeout: " .. timeout .. "s)")
    
    local payload = cmd .. "\r\n"
    C4:SendToNetwork(6001, g_devicePort, payload)
end

function OnPropertyChanged(strProperty)
    if strProperty == "Device IP" then
        local newIP = Properties["Device IP"]
        if newIP ~= g_deviceIP then
            print("Device IP changed from " .. g_deviceIP .. " to " .. newIP)
            g_deviceIP = newIP
            -- Reconnect with new IP
            ConnectToDevice()
        end
        
    elseif strProperty == "Device Port" then
        local newPort = tonumber(Properties["Device Port"]) or 5000
        if newPort ~= g_devicePort then
            print("Device port changed to " .. newPort)
            g_devicePort = newPort
            -- Reconnect with new port
            ConnectToDevice()
        end
    end
end
