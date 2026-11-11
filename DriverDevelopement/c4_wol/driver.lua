function OnDriverInit()
    print("WOL Driver Initialized")
end

function OnPropertyChanged(property)
    print("Property changed: " .. tostring(property))
end

function ExecuteCommand(command, params)
	print("Executing command: " .. tostring(command))
    if command == "LUA_ACTION" then
        command = params and params["ACTION"]
        print("Executing action: " .. tostring(command))
    end

    if command == "Wake" or command == "Send WOL to default MAC" then
        SendWOL()
    end
end

function SendWOL()
    local mac = Properties["MAC"]
    local port = tonumber(Properties["Port"]) or 9

    if not mac or mac == "" then
        print("ERROR: MAC Address not set")
        return
    end

    mac = mac:gsub("[:%-]", "")
    if #mac ~= 12 or mac:find("[^%x]") then
        print("ERROR: Invalid MAC Address format")
        return
    end

    C4:SendWOL(mac, port)
    print("WOL request submitted for " .. mac .. " on UDP port " .. port)
end
