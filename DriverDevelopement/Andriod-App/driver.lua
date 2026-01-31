-- Copyright 2020 Wirepath Home Systems, LLC. All Rights Reserved.

JSON                    = require('json')

UNIVERSAL_APP_VER       = 2
APP_BINDING             = 3101
CURRENT_SELECTED_DEVICE = 1000
CURRENT_VIDEO_PATH      = 1006  -- VIDEO path (not audio)
CURRENT_AUDIO_PATH      = 1007  -- Keep for fallback

APP_NAME                = Properties["App Name"] or "Unknown App"
APP_ID                  = Properties["App ID"] or ""
PHYSICAL_DEVICE_ID      = tonumber(Properties["Physical Device ID"]) or 0

-- Cache for pending launches
LastRoomID = nil
PendingLaunch = false
PendingLaunchRoom = nil
VideoPathUpdated = {}  -- Track which rooms have updated video paths

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
    print("Using VIDEO path (variable 1006) for routing")
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
                print(string.rep("=", 60) .. "\n")
                
                -- Mark that we're waiting for video path update
                print("⏳ Waiting for VIDEO path update before launching...")
                PendingLaunch = true
                PendingLaunchRoom = roomId
                VideoPathUpdated[roomId] = false
                
                -- Trigger video path read
                EnsureRoomTarget(roomId)
            end
            
        elseif (idVariable == CURRENT_VIDEO_PATH) then
            print("\n" .. string.rep("=", 60))
            print("VIDEO path changed for room " .. roomId)
            print(string.rep("=", 60))
            
            RoomIDRoutes[roomId] = {}
            for id in string.gmatch(strValue or '', '<id>(.-)</id>') do
                local deviceId = tonumber(id)
                table.insert(RoomIDRoutes[roomId], deviceId)
                print("  VIDEO route includes device: " .. deviceId)
            end
            
            -- Mark that video path has been updated
            VideoPathUpdated[roomId] = true
            
            -- Rebuild target for this room based on the NEW video route
            RoomIDTargets = RoomIDTargets or {}
            local oldTarget = RoomIDTargets[roomId]
            RoomIDTargets[roomId] = nil
            
            -- Find the correct target device for this room
            local targetFound = false
            
            -- Method 1: Use connected devices on APP_BINDING (most reliable)
            ConnectedDevices = ConnectedDevices or (C4:GetBoundConsumerDevices(C4:GetProxyDevices(), APP_BINDING))
            
            if (ConnectedDevices) then
                for _, id in ipairs(RoomIDRoutes[roomId]) do
                    if (ConnectedDevices[id]) then
                        RoomIDTargets[roomId] = id
                        print("✓ Room " .. roomId .. " NEW target (from binding): device " .. id)
                        if (oldTarget and oldTarget ~= id) then
                            print("  Changed from device " .. oldTarget .. " to " .. id)
                        end
                        targetFound = true
                        break
                    end
                end
            end
            
            -- Method 2: If Physical Device ID is set AND in the route, use it
            if (not targetFound and PHYSICAL_DEVICE_ID and PHYSICAL_DEVICE_ID > 0) then
                for _, id in ipairs(RoomIDRoutes[roomId]) do
                    if (id == PHYSICAL_DEVICE_ID) then
                        RoomIDTargets[roomId] = PHYSICAL_DEVICE_ID
                        print("✓ Room " .. roomId .. " NEW target (from property): device " .. PHYSICAL_DEVICE_ID)
                        if (oldTarget and oldTarget ~= PHYSICAL_DEVICE_ID) then
                            print("  Changed from device " .. oldTarget .. " to " .. PHYSICAL_DEVICE_ID)
                        end
                        targetFound = true
                        break
                    end
                end
            end
            
            -- Method 3: Use first device in video route (fallback)
            if (not targetFound and #RoomIDRoutes[roomId] > 0) then
                local firstDevice = RoomIDRoutes[roomId][1]
                RoomIDTargets[roomId] = firstDevice
                print("⚠ Room " .. roomId .. " NEW target (fallback - first in video route): device " .. firstDevice)
                if (oldTarget and oldTarget ~= firstDevice) then
                    print("  Changed from device " .. oldTarget .. " to " .. firstDevice)
                end
                targetFound = true
            end
            
            if (not targetFound) then
                print("✗ No target device found in VIDEO route for room " .. roomId)
            end
            
            print(string.rep("=", 60) .. "\n")
            
            -- NOW launch if there's a pending launch for this room
            if (PendingLaunch and PendingLaunchRoom == roomId and VideoPathUpdated[roomId]) then
                print(">>> VIDEO path updated! Executing pending launch for room " .. roomId)
                OnMiniAppSelected(roomId)
                PendingLaunch = false
                PendingLaunchRoom = nil
                VideoPathUpdated[roomId] = false
            end
            
        elseif (idVariable == CURRENT_AUDIO_PATH) then
            -- Also monitor audio path for debugging/fallback
            print("Audio path changed for room " .. roomId .. " (monitored for reference)")
            local audioDevices = {}
            for id in string.gmatch(strValue or '', '<id>(.-)</id>') do
                table.insert(audioDevices, tonumber(id))
            end
            if (#audioDevices > 0) then
                print("  Audio route: " .. table.concat(audioDevices, " → "))
            end
        end
    end
end

-- Ensure a target exists for the given room
function EnsureRoomTarget(roomId)
    if (not roomId) then return false end
    
    -- Always refresh the video path to get current routing
    print("Refreshing VIDEO path for room " .. roomId)
    
    -- Initialize tables if needed
    RoomIDTargets = RoomIDTargets or {}
    RoomIDRoutes = RoomIDRoutes or {}
    
    -- Get the CURRENT VIDEO path for this room
    local videoPath = C4:GetDeviceVariable(roomId, CURRENT_VIDEO_PATH) or ''
    print("Current VIDEO path: " .. videoPath)
    
    -- Parse the route
    RoomIDRoutes[roomId] = {}
    for id in string.gmatch(videoPath, '<id>(.-)</id>') do
        local deviceId = tonumber(id)
        table.insert(RoomIDRoutes[roomId], deviceId)
        print("  Device in VIDEO route: " .. deviceId)
    end
    
    -- Don't set target here - wait for OnWatchedVariableChanged to set it
    -- This ensures we use the LATEST route information
    print("  Waiting for VIDEO path variable change to set target...")
    
    return false  -- Indicates we're waiting
end

function OnMiniAppSelected(roomId)
    print("\n" .. string.rep("=", 60))
    print(">>> LAUNCHING APP ON PHYSICAL DEVICE <<<")
    print(string.rep("=", 60))
    print("App: " .. APP_NAME)
    print("App ID: " .. APP_ID)
    print("Room: " .. tostring(roomId))
    
    local targetDeviceId = nil
    
    -- Use room-specific target (should be set by video path change)
    if (RoomIDTargets and roomId and RoomIDTargets[roomId]) then
        targetDeviceId = RoomIDTargets[roomId]
        print("✓ Using room-specific target from VIDEO route: device " .. targetDeviceId)
        
        -- Show the VIDEO route for debugging
        if (RoomIDRoutes and RoomIDRoutes[roomId]) then
            print("  VIDEO route: " .. table.concat(RoomIDRoutes[roomId], " → "))
        end
    else
        print("✗ No room-specific target found in VIDEO route!")
        
        if (RoomIDRoutes and roomId and RoomIDRoutes[roomId]) then
            print("  VIDEO route devices available: " .. table.concat(RoomIDRoutes[roomId], ", "))
        end
        
        -- Fallback: Use Physical Device ID only as last resort
        if (PHYSICAL_DEVICE_ID and PHYSICAL_DEVICE_ID > 0) then
            targetDeviceId = PHYSICAL_DEVICE_ID
            print("⚠ Using Physical Device ID as fallback: " .. targetDeviceId)
            print("  WARNING: This may not be the correct device for this room!")
        end
    end
    
    if (targetDeviceId) then
        print("\n>>> Sending LAUNCH_APP Command <<<")
        print("Target Device: " .. targetDeviceId)
        print("App Name: " .. APP_NAME)
        print("App ID: " .. APP_ID)
        
        -- Send app launch command to physical device
        C4:SendToDevice(targetDeviceId, 'LAUNCH_APP', {
            APP_NAME = APP_NAME,
            APP_ID = APP_ID,
            CHANNEL_ID = APP_ID,
            UNIVERSAL_APP_VER = UNIVERSAL_APP_VER,
            ROOMID = roomId
        })
        
        print("✓ LAUNCH_APP command sent successfully to device " .. targetDeviceId)
        print(string.rep("=", 60) .. "\n")
        return true
    else
        print("✗ Cannot launch - no target device available")
        print(string.rep("=", 60) .. "\n")
        return false
    end
end

function RegisterRooms()
    print("RegisterRooms() called")
    RoomIDs = C4:GetDevicesByC4iName('roomdevice.c4i') or {}
    RoomIDSources = {}
    RoomIDRoutes = {}
    RoomIDTargets = {}
    VideoPathUpdated = {}
    
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
            print("  (none)")
        end
    else
        print("  No connected devices found")
    end
    
    print("Physical Device ID property: " .. tostring(PHYSICAL_DEVICE_ID))
    print("\nUsing VIDEO path (variable " .. CURRENT_VIDEO_PATH .. ") for routing")
    
    -- Register each room
    for roomId, _ in pairs(RoomIDs) do
        print("\nRegistering room " .. roomId .. ":")
        
        -- Get current selected device
        RoomIDSources[roomId] = tonumber(C4:GetDeviceVariable(roomId, CURRENT_SELECTED_DEVICE)) or 0
        print("  Current source: " .. RoomIDSources[roomId])
        
        -- Get and parse VIDEO path
        local videoPath = C4:GetDeviceVariable(roomId, CURRENT_VIDEO_PATH) or ''
        RoomIDRoutes[roomId] = {}
        
        for id in string.gmatch(videoPath, '<id>(.-)</id>') do
            local deviceId = tonumber(id)
            table.insert(RoomIDRoutes[roomId], deviceId)
            print("  VIDEO route device: " .. deviceId)
        end
        
        -- Also show audio path for comparison
        local audioPath = C4:GetDeviceVariable(roomId, CURRENT_AUDIO_PATH) or ''
        local audioDevices = {}
        for id in string.gmatch(audioPath, '<id>(.-)</id>') do
            table.insert(audioDevices, tonumber(id))
        end
        if (#audioDevices > 0) then
            print("  Audio route (for reference): " .. table.concat(audioDevices, " → "))
        end
        
        local targetFound = false
        
        -- Method 1: Try connected devices FIRST (most reliable)
        if (ConnectedDevices) then
            for _, id in ipairs(RoomIDRoutes[roomId]) do
                if (ConnectedDevices[id]) then
                    RoomIDTargets[roomId] = id
                    print("  ✓ Target (from binding in VIDEO route): device " .. id)
                    targetFound = true
                    break
                end
            end
        end
        
        -- Method 2: Try Physical Device ID property (only if in VIDEO route)
        if (not targetFound and PHYSICAL_DEVICE_ID and PHYSICAL_DEVICE_ID > 0) then
            for _, id in ipairs(RoomIDRoutes[roomId]) do
                if (id == PHYSICAL_DEVICE_ID) then
                    RoomIDTargets[roomId] = PHYSICAL_DEVICE_ID
                    print("  ✓ Target (from property in VIDEO route): device " .. PHYSICAL_DEVICE_ID)
                    targetFound = true
                    break
                end
            end
        end
        
        -- Method 3: Use first device in VIDEO route (fallback)
        if (not targetFound and #RoomIDRoutes[roomId] > 0) then
            local firstDevice = RoomIDRoutes[roomId][1]
            RoomIDTargets[roomId] = firstDevice
            print("  ⚠ Target (fallback - first in VIDEO route): device " .. firstDevice)
            targetFound = true
        end
        
        if (not targetFound) then
            print("  ✗ No target found in VIDEO route")
        end
        
        VideoPathUpdated[roomId] = true  -- Initial state is updated
        
        -- Register variable listeners
        C4:UnregisterVariableListener(roomId, CURRENT_SELECTED_DEVICE)
        C4:RegisterVariableListener(roomId, CURRENT_SELECTED_DEVICE)

        C4:UnregisterVariableListener(roomId, CURRENT_VIDEO_PATH)
        C4:RegisterVariableListener(roomId, CURRENT_VIDEO_PATH)
        
        C4:UnregisterVariableListener(roomId, CURRENT_AUDIO_PATH)
        C4:RegisterVariableListener(roomId, CURRENT_AUDIO_PATH)
    end
    
    print("\nRoom registration complete")
    print("\nRoom VIDEO targets summary:")
    for roomId, targetId in pairs(RoomIDTargets) do
        print("  Room " .. roomId .. " → Device " .. targetId)
    end
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
            
            -- DON'T launch immediately - let OnWatchedVariableChanged handle it
            -- This ensures VIDEO path is updated first
            print("⏳ Deferring launch to OnWatchedVariableChanged")
            print("   This ensures VIDEO path is updated with correct route")
            PendingLaunch = true
            PendingLaunchRoom = roomId
            VideoPathUpdated[roomId] = false
        else
            print("⏳ No Room ID found - launch will happen via OnWatchedVariableChanged")
            PendingLaunch = true
            PendingLaunchRoom = nil
        end
    end

    -- Route all other commands to target device
    if (strCommand ~= 'ON' and strCommand ~= 'SELECT_VIDEO_DEVICE' and 
        strCommand ~= 'CONNECT' and strCommand ~= 'SELECT_SOURCE') then
        
        -- Use room-specific target FIRST
        local targetDevice = nil
        
        if (roomId and RoomIDTargets and RoomIDTargets[roomId]) then
            targetDevice = RoomIDTargets[roomId]
            print("Using room-specific target from VIDEO route: device " .. targetDevice)
        elseif (PHYSICAL_DEVICE_ID and PHYSICAL_DEVICE_ID > 0) then
            targetDevice = PHYSICAL_DEVICE_ID
            print("Using global Physical Device ID: device " .. targetDevice)
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