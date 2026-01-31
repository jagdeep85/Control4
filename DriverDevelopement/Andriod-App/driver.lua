-- Copyright 2020 Wirepath Home Systems, LLC. All Rights Reserved.

JSON                    = require('json')

UNIVERSAL_APP_VER       = 2
APP_BINDING             = 3101
CURRENT_SELECTED_DEVICE = 1000
CURRENT_AUDIO_PATH      = 1007

APP_NAME                = Properties["App Name"] or "Unknown App"
APP_ID                  = Properties["App ID"] or ""
PHYSICAL_DEVICE_ID      = tonumber(Properties["Physical Device ID"]) or 0

-- Cache for pending launches
LastRoomID = nil
PendingLaunch = false
PendingLaunchRoom = nil

function formatParams(tParams)
    tParams = tParams or {}
    local out = {}
    for k, v in pairs(tParams) do
        table.insert(out, k .. ": " .. tostring(v))
    end
    return table.concat(out, ", ")
end

function OnDriverDestroyed()
    C4:UnregisterSystemEvent(C4SystemEvents.OnPIP, 0)
end

function OnDriverInit()
    C4:RegisterSystemEvent(C4SystemEvents.OnPIP, 0)
    print("Mini-App Driver Initialized: " .. APP_NAME)
    print("Physical Device ID from property: " .. PHYSICAL_DEVICE_ID)
end

function OnDriverLateInit()
    print("OnDriverLateInit called for: " .. APP_NAME)
    RegisterRooms()
end

function OnPropertyChanged(strProperty)
    print("Property Changed: " .. strProperty)
    local value = Properties[strProperty]
    
    if strProperty == "App Name" then
        APP_NAME = value or "Unknown App"
        print("App Name updated to: " .. APP_NAME)
        
    elseif strProperty == "App ID" then
        APP_ID = value or ""
        print("App ID updated to: " .. APP_ID)
        
    elseif strProperty == "Physical Device ID" then
        PHYSICAL_DEVICE_ID = tonumber(value) or 0
        print("Physical Device ID updated to: " .. PHYSICAL_DEVICE_ID)
    end
end

function OnSystemEvent(event)
    local eventname = string.match(event, '.-name="(.-)"')
    print("OnSystemEvent: " .. eventname)
    if (eventname == 'OnPIP') then
        ConnectedDevices = (C4:GetBoundConsumerDevices(C4:GetProxyDevices(), APP_BINDING))
        RegisterRooms()
    end
end

function OnWatchedVariableChanged(idDevice, idVariable, strValue)
    if (RoomIDs and RoomIDs[idDevice]) then
        local roomId = tonumber(idDevice)
        
        if (idVariable == CURRENT_SELECTED_DEVICE) then
            print("Device selected in room " .. roomId .. ": " .. strValue)
            local deviceId = tonumber(strValue) or 0
            RoomIDSources[roomId] = deviceId
            
            -- CHECK IF THIS MINI-APP WAS SELECTED
            if (deviceId == C4:GetDeviceID()) then
                print("\n" .. string.rep("=", 60))
                print(">>> MINI-APP SELECTED (via variable change)! <<<")
                print("App Name: " .. APP_NAME)
                print("App ID: " .. APP_ID)
                print("Room ID: " .. roomId)
                print("Pending Launch: " .. tostring(PendingLaunch))
                print(string.rep("=", 60) .. "\n")
                
                -- Build target for this room if needed
                EnsureRoomTarget(roomId)
                
                -- Always launch when selected
                OnMiniAppSelected(roomId)
                
                -- Clear pending flag
                PendingLaunch = false
                PendingLaunchRoom = nil
            end
            
        elseif (idVariable == CURRENT_AUDIO_PATH) then
            print("Audio path changed for room " .. roomId)
            RoomIDRoutes[roomId] = {}
            for id in string.gmatch(strValue or '', '<id>(.-)</id>') do
                local deviceId = tonumber(id)
                table.insert(RoomIDRoutes[roomId], deviceId)
                print("  Route includes device: " .. deviceId)
            end
            
            -- Rebuild target for this room
            RoomIDTargets = RoomIDTargets or {}
            RoomIDTargets[roomId] = nil
            
            -- Method 1: Use configured physical device ID
            if (PHYSICAL_DEVICE_ID and PHYSICAL_DEVICE_ID > 0) then
                -- Check if physical device is in the route
                for _, id in ipairs(RoomIDRoutes[roomId]) do
                    if (id == PHYSICAL_DEVICE_ID) then
                        RoomIDTargets[roomId] = PHYSICAL_DEVICE_ID
                        print("✓ Room " .. roomId .. " target (from property): device " .. PHYSICAL_DEVICE_ID)
                        
                        -- Check if there's a pending launch for this room
                        if (PendingLaunch and PendingLaunchRoom == roomId) then
                            print(">>> Executing pending launch for room " .. roomId)
                            OnMiniAppSelected(roomId)
                            PendingLaunch = false
                            PendingLaunchRoom = nil
                        end
                        return
                    end
                end
            end
            
            -- Method 2: Use connected devices on APP_BINDING
            ConnectedDevices = ConnectedDevices or (C4:GetBoundConsumerDevices(C4:GetProxyDevices(), APP_BINDING))
            
            if (ConnectedDevices) then
                for _, id in ipairs(RoomIDRoutes[roomId]) do
                    if (ConnectedDevices[id]) then
                        RoomIDTargets[roomId] = id
                        print("✓ Room " .. roomId .. " target (from binding): device " .. id)
                        
                        -- Check if there's a pending launch for this room
                        if (PendingLaunch and PendingLaunchRoom == roomId) then
                            print(">>> Executing pending launch for room " .. roomId)
                            OnMiniAppSelected(roomId)
                            PendingLaunch = false
                            PendingLaunchRoom = nil
                        end
                        return
                    end
                end
            end
            
            -- Method 3: Use first device in route (fallback)
            if (#RoomIDRoutes[roomId] > 0) then
                local firstDevice = RoomIDRoutes[roomId][1]
                RoomIDTargets[roomId] = firstDevice
                print("⚠ Room " .. roomId .. " target (fallback - first in route): device " .. firstDevice)
                
                -- Check if there's a pending launch for this room
                if (PendingLaunch and PendingLaunchRoom == roomId) then
                    print(">>> Executing pending launch for room " .. roomId)
                    OnMiniAppSelected(roomId)
                    PendingLaunch = false
                    PendingLaunchRoom = nil
                end
            else
                print("✗ No target device found for room " .. roomId)
            end
        end
    end
end

-- Ensure a target exists for the given room
function EnsureRoomTarget(roomId)
    if (not roomId) then return false end
    
    -- If we already have a target, we're good
    if (RoomIDTargets and RoomIDTargets[roomId]) then
        print("Room " .. roomId .. " already has target: " .. RoomIDTargets[roomId])
        return true
    end
    
    print("Building target for room " .. roomId)
    
    -- Initialize tables if needed
    RoomIDTargets = RoomIDTargets or {}
    RoomIDRoutes = RoomIDRoutes or {}
    
    -- Get the current audio path for this room
    local audioPath = C4:GetDeviceVariable(roomId, CURRENT_AUDIO_PATH) or ''
    print("Audio path for room " .. roomId .. ": " .. audioPath)
    
    -- Parse the route
    RoomIDRoutes[roomId] = {}
    for id in string.gmatch(audioPath, '<id>(.-)</id>') do
        local deviceId = tonumber(id)
        table.insert(RoomIDRoutes[roomId], deviceId)
        print("  Found device in route: " .. deviceId)
    end
    
    -- Method 1: Try to use configured physical device ID
    if (PHYSICAL_DEVICE_ID and PHYSICAL_DEVICE_ID > 0) then
        print("Checking for configured physical device " .. PHYSICAL_DEVICE_ID .. " in route...")
        for _, id in ipairs(RoomIDRoutes[roomId]) do
            if (id == PHYSICAL_DEVICE_ID) then
                RoomIDTargets[roomId] = PHYSICAL_DEVICE_ID
                print("✓ Room " .. roomId .. " target (from property): device " .. PHYSICAL_DEVICE_ID)
                return true
            end
        end
        print("  Physical device " .. PHYSICAL_DEVICE_ID .. " not in route")
    end
    
    -- Method 2: Get connected devices on APP_BINDING
    ConnectedDevices = ConnectedDevices or (C4:GetBoundConsumerDevices(C4:GetProxyDevices(), APP_BINDING))
    
    -- Find target device in the route
    if (ConnectedDevices and RoomIDRoutes[roomId]) then
        for _, id in ipairs(RoomIDRoutes[roomId]) do
            if (ConnectedDevices[id]) then
                RoomIDTargets[roomId] = id
                print("✓ Room " .. roomId .. " target (from binding): device " .. id)
                return true
            end
        end
    end
    
    -- Method 3: Use first device in route as fallback
    if (#RoomIDRoutes[roomId] > 0) then
        local firstDevice = RoomIDRoutes[roomId][1]
        RoomIDTargets[roomId] = firstDevice
        print("⚠ Room " .. roomId .. " target (fallback): device " .. firstDevice)
        return true
    end
    
    print("✗ No target device found for room " .. roomId)
    return false
end

function OnMiniAppSelected(roomId)
    print("\n>>> Launching App on Physical Device <<<")
    print("App: " .. APP_NAME)
    print("Room: " .. tostring(roomId))
    
    -- Ensure we have a target for this room
    local hasTarget = false
    if (roomId) then
        hasTarget = EnsureRoomTarget(roomId)
    end
    
    local targetDeviceId = nil
    
    -- Priority 1: Use configured Physical Device ID
    if (PHYSICAL_DEVICE_ID and PHYSICAL_DEVICE_ID > 0) then
        targetDeviceId = PHYSICAL_DEVICE_ID
        print("Using Physical Device ID from property: " .. targetDeviceId)
    
    -- Priority 2: Use RoomIDTargets
    elseif (RoomIDTargets and roomId and RoomIDTargets[roomId]) then
        targetDeviceId = RoomIDTargets[roomId]
        print("Using target from RoomIDTargets: " .. targetDeviceId)
    end
    
    if (targetDeviceId) then
        print("Target Device ID: " .. targetDeviceId)
        print("Sending LAUNCH_APP command...")
        
        -- Send app launch command to physical device
        C4:SendToDevice(targetDeviceId, 'LAUNCH_APP', {
            APP_NAME = APP_NAME,
            APP_ID = APP_ID,
            CHANNEL_ID = APP_ID,
            UNIVERSAL_APP_VER = UNIVERSAL_APP_VER,
            ROOMID = roomId
        })
        
        print("✓ LAUNCH_APP command sent successfully to device " .. targetDeviceId)
        return true
    else
        print("✗ Cannot launch - no target device available")
        return false
    end
end

function RegisterRooms()
    print("RegisterRooms() called")
    RoomIDs = C4:GetDevicesByC4iName('roomdevice.c4i') or {}
    RoomIDSources = {}
    RoomIDRoutes = {}
    RoomIDTargets = {}
    
    local roomCount = 0
    for _, _ in pairs(RoomIDs) do
        roomCount = roomCount + 1
    end
    print("Found " .. roomCount .. " rooms")
    
    -- Get connected devices on APP_BINDING
    ConnectedDevices = C4:GetBoundConsumerDevices(C4:GetProxyDevices(), APP_BINDING)
    
    print("Connected devices on binding " .. APP_BINDING .. ":")
    if (ConnectedDevices) then
        local count = 0
        for id, _ in pairs(ConnectedDevices) do
            print("  Device: " .. id)
            count = count + 1
        end
        if (count == 0) then
            print("  (none - using Physical Device ID property)")
        end
    else
        print("  No connected devices found")
    end
    
    -- Register each room
    for roomId, _ in pairs(RoomIDs) do
        print("\nRegistering room " .. roomId .. ":")
        
        -- Get current selected device
        RoomIDSources[roomId] = tonumber(C4:GetDeviceVariable(roomId, CURRENT_SELECTED_DEVICE)) or 0
        print("  Current source: " .. RoomIDSources[roomId])
        
        -- Get and parse audio path
        local audioPath = C4:GetDeviceVariable(roomId, CURRENT_AUDIO_PATH) or ''
        RoomIDRoutes[roomId] = {}
        
        for id in string.gmatch(audioPath, '<id>(.-)</id>') do
            local deviceId = tonumber(id)
            table.insert(RoomIDRoutes[roomId], deviceId)
            print("  Route device: " .. deviceId)
        end
        
        -- Method 1: Try Physical Device ID property
        if (PHYSICAL_DEVICE_ID and PHYSICAL_DEVICE_ID > 0) then
            for _, id in ipairs(RoomIDRoutes[roomId]) do
                if (id == PHYSICAL_DEVICE_ID) then
                    RoomIDTargets[roomId] = PHYSICAL_DEVICE_ID
                    print("  ✓ Target (from property): device " .. PHYSICAL_DEVICE_ID)
                    break
                end
            end
        end
        
        -- Method 2: Try connected devices
        if (not RoomIDTargets[roomId] and ConnectedDevices) then
            for _, id in ipairs(RoomIDRoutes[roomId]) do
                if (ConnectedDevices[id]) then
                    RoomIDTargets[roomId] = id
                    print("  ✓ Target (from binding): device " .. id)
                    break
                end
            end
        end
        
        if (not RoomIDTargets[roomId]) then
            print("  ✗ No target found")
            if (#RoomIDRoutes[roomId] > 0) then
                print("  → Set Physical Device ID property to one of: " .. 
                      table.concat(RoomIDRoutes[roomId], ", "))
            end
        end
        
        -- Register variable listeners
        C4:UnregisterVariableListener(roomId, CURRENT_SELECTED_DEVICE)
        C4:RegisterVariableListener(roomId, CURRENT_SELECTED_DEVICE)

        C4:UnregisterVariableListener(roomId, CURRENT_AUDIO_PATH)
        C4:RegisterVariableListener(roomId, CURRENT_AUDIO_PATH)
    end
    
    print("\nRoom registration complete")
end

function ReceivedFromProxy(idBinding, strCommand, tParams)
    strCommand = strCommand or ''
    tParams = tParams or {}
    
    print("\n=== Mini-App ReceivedFromProxy ===")
    print("App: " .. APP_NAME)
    print("Binding: " .. idBinding)
    print("Command: " .. strCommand)
    print("Params: " .. formatParams(tParams))
    print("==================================\n")

    -- Extract and cache room ID from SELECT_SOURCE
    if (strCommand == 'SELECT_SOURCE') then
        local roomId = tonumber(tParams.ROOM_ID) or tonumber(tParams.ROOMID)
        if (roomId) then
            LastRoomID = roomId
            print("Cached Room ID from SELECT_SOURCE: " .. roomId)
            
            -- Ensure target exists for this room
            EnsureRoomTarget(roomId)
        end
    end

    -- Extract room ID from various possible parameter names
    local roomId = tonumber(tParams.ROOMID) or 
                   tonumber(tParams.ROOM_ID) or 
                   tonumber(tParams.roomid) or
                   tonumber(tParams.room_id) or
                   LastRoomID  -- Use cached room ID from SELECT_SOURCE
    
    if (not roomId) then
        print("No Room ID in parameters, checking current room context...")
        
        -- Try to find room from current source
        if (RoomIDSources) then
            for rid, sourceId in pairs(RoomIDSources) do
                if (sourceId == C4:GetDeviceID()) then
                    roomId = rid
                    print("Found Room ID from source tracking: " .. roomId)
                    break
                end
            end
        end
    end

    -- Handle ON command (when mini-app is selected from AV Switch)
    if (strCommand == 'ON' or strCommand == 'SELECT_VIDEO_DEVICE' or strCommand == 'CONNECT') then
        print(">>> Mini-App Selected via '" .. strCommand .. "' command")
        print("App Name: " .. APP_NAME)
        
        if (roomId) then
            print("Room ID: " .. roomId)
            
            -- Try to launch immediately
            local launched = OnMiniAppSelected(roomId)
            
            if (not launched) then
                -- If launch failed, mark as pending
                -- The launch will happen when OnWatchedVariableChanged fires
                print("⏳ Launch unsuccessful, marking as pending")
                print("   Will launch when variable change is detected")
                PendingLaunch = true
                PendingLaunchRoom = roomId
            end
        else
            print("⏳ No Room ID found - launch will happen via OnWatchedVariableChanged")
            PendingLaunch = true
            PendingLaunchRoom = nil
        end
    end

    -- Route all other commands to target device
    if (strCommand ~= 'ON' and strCommand ~= 'SELECT_VIDEO_DEVICE' and 
        strCommand ~= 'CONNECT' and strCommand ~= 'SELECT_SOURCE') then
        
        local targetDevice = PHYSICAL_DEVICE_ID
        
        if (not targetDevice or targetDevice == 0) then
            if (roomId and RoomIDTargets and RoomIDTargets[roomId]) then
                targetDevice = RoomIDTargets[roomId]
            end
        end
        
        if (targetDevice and targetDevice > 0) then
            -- Add app information to passthrough
            tParams.PASSTHROUGH_COMMAND = strCommand
            tParams.APP_NAME = APP_NAME
            tParams.APP_ID = APP_ID
            
            print("Forwarding '" .. strCommand .. "' to device " .. targetDevice)
            
            C4:SendToDevice(targetDevice, 'PASSTHROUGH', tParams)
        else
            print("Cannot forward - no target device")
        end
    end
end