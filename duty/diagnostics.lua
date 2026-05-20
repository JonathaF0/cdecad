do
    local Config = DutyConfig
-- event_diagnostic.lua
-- Add this to your resource to diagnose the event issue

-- ========================================
-- CLIENT SIDE DIAGNOSTICS
-- ========================================
if not IsDuplicityVersion() then
    
    -- Test different event methods
    RegisterCommand('testevent', function()
        print("^2[CLIENT] ============================================^0")
        print("^2[CLIENT] TESTING ALL EVENT METHODS^0")
        print("^2[CLIENT] ============================================^0")
        
        local testData = {
            playerId = GetPlayerServerId(PlayerId()),
            playerName = GetPlayerName(PlayerId()),
            timestamp = GetGameTimer()
        }
        
        -- Method 1: Standard TriggerServerEvent
        print("^3[CLIENT] Method 1: Standard TriggerServerEvent^0")
        TriggerServerEvent('test:method1', 'Hello from method 1')
        
        Citizen.Wait(100)
        
        -- Method 2: With table data
        print("^3[CLIENT] Method 2: With table data^0")
        TriggerServerEvent('test:method2', testData)
        
        Citizen.Wait(100)
        
        -- Method 3: Multiple parameters
        print("^3[CLIENT] Method 3: Multiple parameters^0")
        TriggerServerEvent('test:method3', true, 'leo', GetPlayerServerId(PlayerId()))
        
        Citizen.Wait(100)
        
        -- Method 4: Direct duty event
        print("^3[CLIENT] Method 4: Direct duty event^0")
        TriggerServerEvent('duty:setDutyStatus', true, 'leo')
        
        SetNotificationTextEntry("STRING")
        AddTextComponentString("~y~Test events sent - check server console!")
        DrawNotification(false, false)
    end, false)
    
    -- Force duty with maximum logging
    RegisterCommand('forcedutyon', function()
        print("^1[CLIENT] ============================================^0")
        print("^1[CLIENT] FORCE DUTY ON WITH ALL METHODS^0")
        print("^1[CLIENT] ============================================^0")
        
        -- Set local state first
        isOnDuty = true
        dutyType = "leo"
        
        -- Try every possible way to send the event
        print("^3[CLIENT] Attempt 1: duty:setDutyStatus^0")
        TriggerServerEvent('duty:setDutyStatus', true, 'leo')
        
        Citizen.Wait(50)
        
        print("^3[CLIENT] Attempt 2: Basic parameters^0")
        TriggerServerEvent('duty:basicSet', true, 'leo')
        
        Citizen.Wait(50)
        
        print("^3[CLIENT] Attempt 3: String event^0")
        TriggerServerEvent('duty:stringSet', 'on:leo')
        
        Citizen.Wait(50)
        
        print("^3[CLIENT] Attempt 4: Table event^0")
        local dutyData = {
            status = true,
            type = 'leo',
            player = GetPlayerServerId(PlayerId())
        }
        TriggerServerEvent('duty:tableSet', dutyData)
        
        TriggerEvent('chat:addMessage', {
            color = {255, 255, 0},
            args = {"[DEBUG]", "Force duty events sent - check server console"}
        })
    end, false)

-- ========================================
-- SERVER SIDE DIAGNOSTICS
-- ========================================
else
    
    print("^1[SERVER] ============================================^0")
    print("^1[SERVER] EVENT DIAGNOSTIC LOADING^0")
    print("^1[SERVER] ============================================^0")
    
    -- Test Method 1
    RegisterNetEvent('test:method1')
    AddEventHandler('test:method1', function(message)
        local source = source
        print("^2[SERVER] METHOD 1 RECEIVED from player " .. source .. ": " .. tostring(message) .. "^0")
    end)
    
    -- Test Method 2
    RegisterNetEvent('test:method2')
    AddEventHandler('test:method2', function(data)
        local source = source
        print("^2[SERVER] METHOD 2 RECEIVED from player " .. source .. "^0")
        if data then
            print("  Data: " .. json.encode(data))
        end
    end)
    
    -- Test Method 3
    RegisterNetEvent('test:method3')
    AddEventHandler('test:method3', function(param1, param2, param3)
        local source = source
        print("^2[SERVER] METHOD 3 RECEIVED from player " .. source .. "^0")
        print("  Param1: " .. tostring(param1))
        print("  Param2: " .. tostring(param2))
        print("  Param3: " .. tostring(param3))
    end)
    
    -- Basic duty set
    RegisterNetEvent('duty:basicSet')
    AddEventHandler('duty:basicSet', function(status, type)
        local source = source
        print("^2[SERVER] BASIC SET RECEIVED from player " .. source .. "^0")
        print("  Status: " .. tostring(status) .. ", Type: " .. tostring(type))
        
        -- Actually set them on duty
        if not onDutyPlayers then
            onDutyPlayers = {}
        end
        
        onDutyPlayers[source] = {
            name = GetPlayerName(source),
            type = type or 'leo',
            timestamp = os.time()
        }
        
        -- Broadcast
        local players = GetPlayers()
        for _, playerId in ipairs(players) do
            TriggerClientEvent('duty:updateOnDutyList', tonumber(playerId), onDutyPlayers)
        end
    end)
    
    -- String duty set
    RegisterNetEvent('duty:stringSet')
    AddEventHandler('duty:stringSet', function(data)
        local source = source
        print("^2[SERVER] STRING SET RECEIVED from player " .. source .. ": " .. tostring(data) .. "^0")
    end)
    
    -- Table duty set
    RegisterNetEvent('duty:tableSet')
    AddEventHandler('duty:tableSet', function(data)
        local source = source
        print("^2[SERVER] TABLE SET RECEIVED from player " .. source .. "^0")
        if data then
            print("  Status: " .. tostring(data.status))
            print("  Type: " .. tostring(data.type))
            print("  Player: " .. tostring(data.player))
            
            -- Actually set them on duty
            if not onDutyPlayers then
                onDutyPlayers = {}
            end
            
            if data.status then
                onDutyPlayers[source] = {
                    name = GetPlayerName(source),
                    type = data.type or 'leo',
                    timestamp = os.time()
                }
                
                -- Broadcast
                local players = GetPlayers()
                for _, playerId in ipairs(players) do
                    TriggerClientEvent('duty:updateOnDutyList', tonumber(playerId), onDutyPlayers)
                end
                
                print("^2[SERVER] Player " .. source .. " added to duty roster^0")
            end
        end
    end)
    
    -- Manual add command (console)
    RegisterCommand('manualduty', function(source, args)
        if source ~= 0 then return end
        
        local targetId = tonumber(args[1])
        if not targetId or not GetPlayerName(targetId) then
            print("^1Usage: manualduty [playerID]^0")
            return
        end
        
        if not onDutyPlayers then
            onDutyPlayers = {}
        end
        
        onDutyPlayers[targetId] = {
            name = GetPlayerName(targetId),
            type = 'leo',
            timestamp = os.time()
        }
        
        print("^2[SERVER] Manually added player " .. targetId .. " to duty^0")
        
        -- Broadcast to all
        local players = GetPlayers()
        for _, playerId in ipairs(players) do
            TriggerClientEvent('duty:updateOnDutyList', tonumber(playerId), onDutyPlayers)
        end
        
        -- Sync with player
        TriggerClientEvent('duty:syncDutyStatus', targetId, true, 'leo')
        TriggerClientEvent('chat:addMessage', targetId, {
            color = {0, 255, 0},
            args = {"[DUTY]", "You have been manually placed on duty as LEO"}
        })
    end, true)
    
    -- Check what events are registered
    RegisterCommand('checkevents', function(source)
        print("^2[SERVER] Checking duty events...^0")
        print("  If you see this, the diagnostic script is loaded")
        print("  Try /testevent from client to test connection")
        print("  Try 'manualduty [playerID]' from console to force add")
    end, true)
    
    print("^2[SERVER] Event diagnostic loaded - Events registered:^0")
    print("  - test:method1, test:method2, test:method3")
    print("  - duty:basicSet, duty:stringSet, duty:tableSet")
    print("  - Commands: manualduty, checkevents")
end

print("^2[DIAGNOSTIC] Event diagnostic loaded^0")
end
