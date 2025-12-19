require "socket"

function OnDriverInit()
    print("WOL Driver Initialized")
end

function OnPropertyChanged(property)
    print("Property changed: " .. tostring(property))
end

function ExecuteCommand(command, params)
	print("Executing command: " .. tostring(command))
    --if command == "Wake" then
        SendWOL()
    --end
end

function SendWOL()
    local mac = Properties["MAC"]
    local ip  = Properties["Broadcast IP"] or "255.255.255.255"
    local port = tonumber(Properties["Port"]) or 9

    if not mac or mac == "" then
        print("ERROR: MAC Address not set")
        return
    end

    local packet = BuildMagicPacket(mac)
    if not packet then
        print("ERROR: Invalid MAC Address format")
        return
    end

    local udp = socket.udp()
    udp:setoption("broadcast", true)
    udp:sendto(packet, ip, port)
    udp:close()

    print("WOL packet sent to " .. mac)
end

function BuildMagicPacket(mac)
    mac = mac:gsub("[:%-]", "")

    if #mac ~= 12 then
        return nil
    end

    local mac_bytes = ""
    for i = 1, 12, 2 do
        local byte = tonumber(mac:sub(i, i + 1), 16)
        if not byte then return nil end
        mac_bytes = mac_bytes .. string.char(byte)
    end

    return string.rep(string.char(0xFF), 6) .. string.rep(mac_bytes, 16)
end
