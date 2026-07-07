do
    local Config = DutyConfig
-- CDE Duty System - Client

-- ========================================
-- VARIABLES
-- ========================================
local isOnDuty = false
local currentJob = nil
local currentDepartment = nil
local lastCallData = nil
local calloutSettings = {
    showCallouts = true,
    showPostal = true
}

print("^2[CDE-DUTY] Client loading...^0")

-- ========================================
-- RADIO AGENCY HANDLERS (LOWERCASE)
-- ========================================

RegisterNetEvent('CDE:SetRadioAgency')
AddEventHandler('CDE:SetRadioAgency', function(agency)
    if agency then
        -- Ensure lowercase for radio system
        agency = string.lower(agency)
        print("^3[CDE-DUTY] Setting radio agency: " .. agency .. "^0")
        
        ExecuteCommand("setradioagency " .. agency)

        -- Also try the capitalized command variant
        Citizen.SetTimeout(500, function()
            ExecuteCommand("setRadioAgency " .. agency)
        end)
        
        TriggerEvent('chat:addMessage', {
            color = {0, 255, 0},
            args = {"[RADIO]", "Radio agency set to: " .. string.upper(agency)}
        })
    else
        print("^3[CDE-DUTY] Clearing radio agency^0")
        ExecuteCommand("setradioagency clear")
        ExecuteCommand("setRadioAgency clear")
        
        TriggerEvent('chat:addMessage', {
            color = {255, 255, 0},
            args = {"[RADIO]", "Radio agency cleared"}
        })
    end
end)

-- ========================================
-- PAYCHECK HANDLER
-- ========================================

RegisterNetEvent('CDE:ReceivePaycheck')
AddEventHandler('CDE:ReceivePaycheck', function(amount)
    -- Hook point for standalone/custom money systems

    SetNotificationTextEntry("STRING")
    AddTextComponentString("~g~PAYCHECK~n~~w~+$" .. amount .. " added to cash")
    DrawNotification(false, true)
    
    -- Play sound
    PlaySoundFrontend(-1, "WAYPOINT_SET", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
end)

-- ========================================
-- LEO STATUS FOR 911 SYSTEM
-- ========================================

RegisterNetEvent('CDE:SetLEOStatus')
AddEventHandler('CDE:SetLEOStatus', function(status)
    -- LEO status from server; used by the CAD-911 system to prevent NPC reports
    if status then
        print("^2[CDE-DUTY] LEO status: Active^0")
    else
        print("^3[CDE-DUTY] LEO status: Inactive^0")
    end
end)

-- ========================================
-- DUTY EVENT HANDLERS
-- ========================================

RegisterNetEvent('CDE:UpdateCalloutSettings')
AddEventHandler('CDE:UpdateCalloutSettings', function(settings)
    calloutSettings = settings
    print("^3[CDE-DUTY] Settings updated: Callouts=" .. tostring(settings.showCallouts) .. "^0")
end)

AddEventHandler('playerSpawned', function()
    TriggerServerEvent('CDE:RequestCalloutSettings')
    TriggerServerEvent('cad:requestLEOStatus')
end)

RegisterNetEvent('CDE:ConfirmOnDutyDepartment')
AddEventHandler('CDE:ConfirmOnDutyDepartment', function(department, deptConfig)
    print("^2[CDE-DUTY] On duty as " .. deptConfig.name .. "^0")
    
    isOnDuty = true
    currentJob = deptConfig.type
    currentDepartment = department
    
    -- Always give armor when going on duty
    local playerPed = PlayerPedId()
    SetPedArmour(playerPed, 100)
    
    -- Give flares to all on-duty personnel
    GiveWeaponToPed(playerPed, GetHashKey("WEAPON_FLARE"), 20, false, false)
    
    -- Give less-lethal weapons to LEO
    if deptConfig.type == "leo" then
        GiveWeaponToPed(playerPed, GetHashKey("weapon_lesslauncher"), 50, false, false)
        GiveWeaponToPed(playerPed, GetHashKey("weapon_beanbag"), 100, false, false)
        
        SetNotificationTextEntry("STRING")
        AddTextComponentString("~g~ON DUTY~n~" .. deptConfig.name .. "~n~~y~Radio Set~n~~b~Armor, Flares & Less-Lethal Given")
        DrawNotification(false, false)
    else
        SetNotificationTextEntry("STRING")
        AddTextComponentString("~g~ON DUTY~n~" .. deptConfig.name .. "~n~~y~Radio Set~n~~b~Armor & Flares Given")
        DrawNotification(false, false)
    end
    
    -- Give department loadout
    if Config and Config.WeaponLoadouts then
        if deptConfig.type == "leo" then
            GiveDutyLoadout("leo")
        elseif deptConfig.type == "fire" then
            GiveDutyLoadout("fire")
        end
    end
    
    -- Notify 911 system if LEO
    if deptConfig.type == "leo" then
        TriggerEvent('CDE:SetLEOStatus', true)
        
        -- Bodycam overlay notification (bodycam script handles the actual overlay)
        Citizen.SetTimeout(1000, function()
            TriggerEvent('chat:addMessage', {
                color = {0, 255, 255},
                args = {"[BODYCAM]", "Bodycam overlay active"}
            })
        end)
    end
end)

RegisterNetEvent('CDE:ConfirmOffDuty')
AddEventHandler('CDE:ConfirmOffDuty', function()
    print("^1[CDE-DUTY] Off duty^0")
    
    isOnDuty = false
    currentJob = nil
    currentDepartment = nil
    lastCallData = nil
    
    SetNotificationTextEntry("STRING")
    AddTextComponentString("~r~OFF DUTY~n~~y~Radio Cleared")
    DrawNotification(false, false)
    
    -- Remove weapons if configured
    if Config and Config.Advanced and Config.Advanced.RemoveWeaponsOffDuty then
        RemoveAllPedWeapons(PlayerPedId(), false)
    end
    
    TriggerEvent('CDE:SetLEOStatus', false)
end)

-- ========================================
-- 911 CALL RECEIVER
-- ========================================

RegisterNetEvent('CDE:Receive911')
AddEventHandler('CDE:Receive911', function(callData)
    if not isOnDuty then return end
    
    lastCallData = callData
    
    -- Play sound
    PlaySoundFrontend(-1, "CHALLENGE_UNLOCKED", "HUD_AWARDS", true)
    
    -- Show notification
    local callPrefix = "911 DISPATCH"
    if callData.reportType then
        local types = {
            ["Gunshots"] = "SHOTS FIRED",
            ["Speeding"] = "SPEEDING",
            ["Accident"] = "ACCIDENT",
            ["Fighting"] = "FIGHT",
            ["Explosion"] = "EXPLOSION",
            ["Brandishing"] = "ARMED PERSON",
            ["CCTV"] = "CCTV ALERT"
        }
        callPrefix = types[callData.reportType] or callPrefix
    end
    
    SetNotificationTextEntry("STRING")
    local notifText = "~r~" .. callPrefix .. "~n~~w~" .. (callData.description or "Emergency")
    
    if callData.location then
        local location = callData.location
        if not calloutSettings.showPostal then
            location = string.gsub(location, "%s*%- Postal%s+%d+", "")
            location = string.gsub(location, "%s*Postal%s+%d+", "")
        end
        notifText = notifText .. "~n~~y~" .. location
    end
    
    AddTextComponentString(notifText)
    DrawNotification(false, true)
    
    -- Show in chat if enabled
    if calloutSettings.showCallouts then
        local details = ""
        if callData.location then
            local location = callData.location
            if not calloutSettings.showPostal then
                location = string.gsub(location, "%s*%- Postal%s+%d+", "")
            end
            details = "Location: " .. location
        end
        if callData.description then
            details = details .. "\n" .. callData.description
        end
        
        TriggerEvent('chat:addMessage', {
            color = {255, 0, 0},
            multiline = true,
            args = {callPrefix, details}
        })
    end
    
    -- Set waypoint if coords provided
    if callData.coords and Config and Config.GPSRouting and Config.GPSRouting.AutoRoute then
        SetNewWaypoint(callData.coords.x, callData.coords.y)
        print("^2[911] GPS waypoint set^0")
    end
end)

-- ========================================
-- WRAITH ARS 2X - TRAFFIC STOP (/ts)
-- ========================================
-- Track the most-recently locked plate from the Wraith plate reader so the
-- /ts command can attach the unit to a Traffic Stop call in CAD with the
-- correct vehicle.

local lastLockedPlate = nil
local lastLockedAt    = 0
local lastLockedCam   = nil
local tsLastCallTime  = 0

local function StoreLockedPlate(cam, plate)
    if not plate or plate == '' then return end
    lastLockedPlate = string.upper((plate:gsub('%s', '')))
    lastLockedAt    = GetGameTimer() / 1000
    lastLockedCam   = cam or 'manual'
end

-- Wraith ARS 2X fires `wk:onPlateLocked` server-side; the duty server mirrors
-- it back via CDE:WraithPlateLocked. Both are listened to in case a Wraith
-- build also fires it client-side.
RegisterNetEvent('wk:onPlateLocked')
AddEventHandler('wk:onPlateLocked', function(cam, plate, index)
    StoreLockedPlate(cam, plate)
end)

RegisterNetEvent('CDE:WraithPlateLocked')
AddEventHandler('CDE:WraithPlateLocked', function(cam, plate, index)
    StoreLockedPlate(cam, plate)
end)

local function GetTSStreetName(coords)
    local streetHash, crossHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash) or ''
    local cross  = GetStreetNameFromHashKey(crossHash) or ''
    if cross ~= '' then return street .. ' / ' .. cross end
    return street
end

local function GetTSZoneName(coords)
    local zoneHash = GetNameOfZone(coords.x, coords.y, coords.z)
    local label = GetLabelText(zoneHash)
    if label and label ~= 'NULL' and label ~= '' then return label end
    return ''
end

local function GetTSPostal(coords)
    local ok, result = pcall(function()
        return exports['nearest-postal']:getClosestPostal(coords)
    end)
    if ok and result then
        if type(result) == 'table' then
            return tostring(result.code or result[1] or '')
        end
        return tostring(result)
    end

    ok, result = pcall(function()
        return exports['nearest-postal']:getPostal()
    end)
    if ok and result then
        return tostring(result)
    end
    return ''
end

local function GetTSLocationData()
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local street = GetTSStreetName(coords)
    local zone   = GetTSZoneName(coords)
    local postal = GetTSPostal(coords)

    local location = street
    if zone   ~= '' then location = (location ~= '' and (location .. ', ') or '') .. zone end
    if postal ~= '' then location = (location ~= '' and location or 'Unknown') .. ' (Postal ' .. postal .. ')' end

    return {
        location = location ~= '' and location or 'Unknown',
        postal   = postal,
        coords   = { x = coords.x, y = coords.y, z = coords.z },
    }
end

RegisterCommand('ts', function(source, args)
    if Config.TrafficStop and Config.TrafficStop.RequireLEO and (not isOnDuty or currentJob ~= 'leo') then
        TriggerEvent('chat:addMessage', {
            color = {255, 0, 0},
            args  = {'[TS]', 'You must be on duty as LEO to start a traffic stop.'}
        })
        return
    end

    local cd = (Config.TrafficStop and Config.TrafficStop.CooldownSeconds) or 5
    local now = GetGameTimer() / 1000
    if (now - tsLastCallTime) < cd then
        TriggerEvent('chat:addMessage', {
            color = {255, 200, 0},
            args  = {'[TS]', string.format('Please wait %d more seconds.', math.ceil(cd - (now - tsLastCallTime)))}
        })
        return
    end

    -- /ts <plate> overrides the Wraith-locked plate if provided
    local plate = args[1]
    if plate and plate ~= '' then
        plate = string.upper((plate:gsub('%s', '')))
    else
        local maxAge = (Config.TrafficStop and Config.TrafficStop.PlateMaxAgeSeconds) or 120
        if not lastLockedPlate or lastLockedPlate == '' then
            TriggerEvent('chat:addMessage', {
                color = {255, 0, 0},
                args  = {'[TS]', 'No plate locked on Wraith reader. Lock a plate first or use /ts <plate>.'}
            })
            return
        end
        if (now - lastLockedAt) > maxAge then
            TriggerEvent('chat:addMessage', {
                color = {255, 0, 0},
                args  = {'[TS]', string.format('Last locked plate is too old (%ds). Lock again or use /ts <plate>.', math.floor(now - lastLockedAt))}
            })
            return
        end
        plate = lastLockedPlate
    end

    if plate == '' then return end
    tsLastCallTime = now

    local loc = GetTSLocationData()
    TriggerServerEvent('CDE:TrafficStop', {
        plate    = plate,
        cam      = lastLockedCam,
        location = loc.location,
        postal   = loc.postal,
        coords   = loc.coords,
    })

    TriggerEvent('chat:addMessage', {
        color = {0, 200, 255},
        args  = {'[TS]', 'Initiating traffic stop on ' .. plate .. '...'}
    })
end, false)

RegisterCommand('trafficstop', function(source, args)
    ExecuteCommand('ts ' .. (args[1] or ''))
end, false)

RegisterNetEvent('CDE:TrafficStopResult')
AddEventHandler('CDE:TrafficStopResult', function(result)
    if not result then return end

    if result.success then
        local prefix
        if result.alertLevel == 'alert' then
            prefix = '~r~ALERT'
        elseif result.alertLevel == 'caution' then
            prefix = '~o~CAUTION'
        else
            prefix = '~g~CLEAN'
        end

        local notif = string.format(
            '%s~n~~w~Traffic Stop %s~n~Plate: %s',
            prefix,
            tostring(result.incidentNumber or ''),
            tostring(result.plate or '')
        )
        if result.flags and result.flags ~= '' then
            notif = notif .. '~n~~y~' .. result.flags
        end

        SetNotificationTextEntry('STRING')
        AddTextComponentString(notif)
        DrawNotification(false, true)
        PlaySoundFrontend(-1, 'CHALLENGE_UNLOCKED', 'HUD_AWARDS', true)

        local chatLine = string.format('Call %s opened on %s.', tostring(result.incidentNumber or '?'), tostring(result.plate or '?'))
        if result.flags and result.flags ~= '' then
            chatLine = chatLine .. ' Flags: ' .. result.flags
        end
        TriggerEvent('chat:addMessage', {
            color = {0, 255, 0},
            args  = {'[TS]', chatLine}
        })
    else
        TriggerEvent('chat:addMessage', {
            color = {255, 0, 0},
            args  = {'[TS]', 'Failed: ' .. tostring(result.msg or 'Unknown error')}
        })
    end
end)

-- ========================================
-- WEAPON LOADOUT
-- ========================================

function GiveDutyLoadout(loadoutType)
    if not Config or not Config.WeaponLoadouts then return end
    
    local playerPed = PlayerPedId()
    local loadout = Config.WeaponLoadouts[loadoutType]
    
    while type(loadout) == "string" do
        loadout = Config.WeaponLoadouts[loadout]
    end
    
    if not loadout then return end
    
    SetEntityHealth(playerPed, loadout.health or 200)
    SetPedArmour(playerPed, loadout.armor or 100)
    
    if loadout.weapons then
        for _, weaponData in ipairs(loadout.weapons) do
            local weaponHash = GetHashKey(weaponData.weapon)
            GiveWeaponToPed(playerPed, weaponHash, weaponData.ammo, false, false)
            
            if weaponData.attachments then
                for _, attachment in ipairs(weaponData.attachments) do
                    GiveWeaponComponentToPed(playerPed, weaponHash, GetHashKey(attachment))
                end
            end
        end
        
        -- Always add flares if not already in loadout
        local hasFlares = false
        local hasLessLethal = false
        local hasBeanbag = false
        
        for _, weaponData in ipairs(loadout.weapons) do
            if weaponData.weapon == "WEAPON_FLARE" then
                hasFlares = true
            elseif weaponData.weapon == "weapon_lesslauncher" then
                hasLessLethal = true
            elseif weaponData.weapon == "weapon_beanbag" then
                hasBeanbag = true
            end
        end
        
        if not hasFlares then
            GiveWeaponToPed(playerPed, GetHashKey("WEAPON_FLARE"), 20, false, false)
            print("^2[CDE-DUTY] Added flares^0")
        end
        
        -- Add less-lethal weapons for LEO loadouts
        if loadoutType == "leo" or loadoutType == "swat" then
            if not hasLessLethal then
                GiveWeaponToPed(playerPed, GetHashKey("weapon_lesslauncher"), 50, false, false)
                print("^2[CDE-DUTY] Added less-lethal launcher^0")
            end
            if not hasBeanbag then
                GiveWeaponToPed(playerPed, GetHashKey("weapon_beanbag"), 100, false, false)
                print("^2[CDE-DUTY] Added beanbag shotgun^0")
            end
        end
        
        print("^2[CDE-DUTY] Loadout applied with armor, flares, and less-lethal options^0")
    end
end

-- ========================================
-- TOGGLE COMMANDS
-- ========================================

RegisterCommand('togglecallouts', function()
    calloutSettings.showCallouts = not calloutSettings.showCallouts
    TriggerServerEvent('CDE:UpdateCalloutSettings', calloutSettings)
    
    SetNotificationTextEntry("STRING")
    AddTextComponentString("911 Callouts: " .. (calloutSettings.showCallouts and "~g~ON" or "~r~OFF"))
    DrawNotification(false, false)
end, false)

RegisterCommand('callouts', function()
    ExecuteCommand("togglecallouts")
end, false)

RegisterCommand('togglepostal', function()
    calloutSettings.showPostal = not calloutSettings.showPostal
    TriggerServerEvent('CDE:UpdateCalloutSettings', calloutSettings)
    
    SetNotificationTextEntry("STRING")
    AddTextComponentString("Postal Codes: " .. (calloutSettings.showPostal and "~g~ON" or "~r~OFF"))
    DrawNotification(false, false)
end, false)

-- Alias intentionally NOT /postal: that clashes with the nearest-postal
-- resource's routing command on servers running both.
RegisterCommand('cdepostal', function()
    ExecuteCommand("togglepostal")
end, false)

-- ========================================
-- /p <postal> - GPS route to a postal code
-- ========================================
-- Reads postals.json straight from whichever postal resource is running,
-- so it works even when that resource doesn't provide its own routing.

local postalDb = nil       -- { CODE = { x = .., y = .. } }
local postalRouteBlip = nil

local function PostalNotify(msg)
    SetNotificationTextEntry("STRING")
    AddTextComponentString(msg)
    DrawNotification(false, false)
end

local function LoadPostalDb()
    if postalDb then return postalDb end
    for _, res in ipairs({ 'nearest-postal', 'postal-code', 'postals' }) do
        if GetResourceState(res) == 'started' then
            local raw = LoadResourceFile(res, 'postals.json')
            if raw then
                local ok, data = pcall(json.decode, raw)
                if ok and type(data) == 'table' then
                    local map = {}
                    for _, p in ipairs(data) do
                        local code = tostring(p.code or p.postal or ''):upper()
                        local x, y = tonumber(p.x), tonumber(p.y)
                        if code ~= '' and x and y then map[code] = { x = x, y = y } end
                    end
                    if next(map) then
                        postalDb = map
                        return map
                    end
                end
            end
        end
    end
    return nil
end

local function ClearPostalRoute(silent)
    if postalRouteBlip then
        RemoveBlip(postalRouteBlip)
        postalRouteBlip = nil
    end
    if not silent then PostalNotify("~y~Postal route cleared") end
end

RegisterCommand('p', function(_, args)
    local code = tostring(args[1] or ''):upper()
    if code == '' or code == 'CLEAR' then
        ClearPostalRoute(false)
        return
    end

    local db = LoadPostalDb()
    if not db then
        PostalNotify("~r~No postal database found (is nearest-postal running?)")
        return
    end

    local pt = db[code] or db[(code:gsub('^0+', ''))]
    if not pt then
        PostalNotify("~r~Postal ~w~" .. code .. "~r~ not found")
        return
    end

    ClearPostalRoute(true)
    postalRouteBlip = AddBlipForCoord(pt.x, pt.y, 0.0)
    SetBlipSprite(postalRouteBlip, 162)
    SetBlipColour(postalRouteBlip, 3)
    SetBlipRoute(postalRouteBlip, true)
    SetBlipRouteColour(postalRouteBlip, 3)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Postal " .. code)
    EndTextCommandSetBlipName(postalRouteBlip)
    PostalNotify("~g~Routing to postal ~w~" .. code)

    -- Auto-clear once the player arrives
    Citizen.CreateThread(function()
        local myBlip = postalRouteBlip
        while postalRouteBlip == myBlip do
            local pos = GetEntityCoords(PlayerPedId())
            if #(vector2(pos.x, pos.y) - vector2(pt.x, pt.y)) < 60.0 then
                ClearPostalRoute(true)
                PostalNotify("~g~Arrived at postal ~w~" .. code)
                break
            end
            Citizen.Wait(2000)
        end
    end)
end, false)

-- ========================================
-- UTILITY COMMANDS
-- ========================================

RegisterCommand('dutyinfo', function()
    print("^2[CDE-DUTY] Status:^0")
    print("  On Duty: " .. tostring(isOnDuty))
    print("  Job: " .. tostring(currentJob))
    print("  Department: " .. tostring(currentDepartment))
    print("  Callouts: " .. tostring(calloutSettings.showCallouts))
    
    SetNotificationTextEntry("STRING")
    if isOnDuty then
        local dept = currentDepartment or currentJob or "Unknown"
        AddTextComponentString("~g~ON DUTY~n~" .. dept)
    else
        AddTextComponentString("~r~OFF DUTY")
    end
    DrawNotification(false, false)
end, false)

RegisterCommand('loadout', function(source, args)
    local loadoutType = args[1]
    
    if not loadoutType then
        SetNotificationTextEntry("STRING")
        AddTextComponentString("~r~Usage: /loadout [swat/standard]")
        DrawNotification(false, false)
        return
    end
    
    if not isOnDuty or currentJob ~= "leo" then
        SetNotificationTextEntry("STRING")
        AddTextComponentString("~r~Must be on duty as LEO!")
        DrawNotification(false, false)
        return
    end
    
    loadoutType = string.lower(loadoutType)
    
    if loadoutType == "swat" then
        if Config and Config.WeaponLoadouts and Config.WeaponLoadouts["swat"] then
            RemoveAllPedWeapons(PlayerPedId(), false)
            GiveDutyLoadout("swat")
            TriggerServerEvent('CDE:NotifyLoadoutChange', 'swat')
            
            SetNotificationTextEntry("STRING")
            AddTextComponentString("~r~SWAT LOADOUT~n~~w~Tactical gear equipped")
            DrawNotification(false, true)
            
            PlaySoundFrontend(-1, "WEAPON_PURCHASE", "HUD_AMMO_SHOP_SOUNDSET", true)
        end
    elseif loadoutType == "standard" then
        RemoveAllPedWeapons(PlayerPedId(), false)
        GiveDutyLoadout("leo")
        TriggerServerEvent('CDE:NotifyLoadoutChange', 'standard')
        
        SetNotificationTextEntry("STRING")
        AddTextComponentString("~b~STANDARD LOADOUT~n~~w~Patrol gear equipped")
        DrawNotification(false, true)
        
        PlaySoundFrontend(-1, "WEAPON_PURCHASE", "HUD_AMMO_SHOP_SOUNDSET", true)
    end
end, false)

RegisterCommand('route911', function()
    if not isOnDuty then
        SetNotificationTextEntry("STRING")
        AddTextComponentString("~r~Must be on duty!")
        DrawNotification(false, false)
        return
    end
    
    if lastCallData and lastCallData.coords then
        SetNewWaypoint(lastCallData.coords.x, lastCallData.coords.y)
        SetNotificationTextEntry("STRING")
        AddTextComponentString("~g~GPS set to last 911")
        DrawNotification(false, false)
    else
        SetNotificationTextEntry("STRING")
        AddTextComponentString("~y~No recent 911 calls")
        DrawNotification(false, false)
    end
end, false)

RegisterCommand('cleargps', function()
    DeleteWaypoint()
    SetNotificationTextEntry("STRING")
    AddTextComponentString("~y~GPS cleared")
    DrawNotification(false, false)
end, false)

-- ========================================
-- EXPORTS
-- ========================================

exports('IsOnDutyLEO', function()
    return isOnDuty and currentJob == "leo"
end)

exports('GetCurrentDepartment', function()
    return currentDepartment
end)

exports('GetDutyStatus', function()
    return {
        onDuty = isOnDuty,
        job = currentJob,
        department = currentDepartment
    }
end)

-- ========================================
-- INITIALIZATION
-- ========================================

Citizen.CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do
        Citizen.Wait(100)
    end
    
    Citizen.Wait(5000)
    
    TriggerServerEvent('CDE:RequestCalloutSettings')
    TriggerServerEvent('cad:requestLEOStatus')
    
    print("^2========================================^0")
    print("^2     CDE DUTY SYSTEM v4.0.0            ^0")
    print("^2========================================^0")
    print("^2Commands:^0")
    print("  /d [dept/off] - Toggle duty")
    print("  /togglecallouts - Toggle 911 in chat")
    print("  /togglepostal - Toggle postal codes")
    print("  /loadout [swat/standard] - Change loadout")
    print("  /dutyinfo - Check status")
    print("  /route911 - Route to last 911")
    print("  /cleargps - Clear GPS")
    print("^2Features:^0")
    print("  ✓ Department duty system")
    print("  ✓ 911 call reception")
    print("  ✓ Radio integration (lowercase)")
    print("  ✓ SWAT loadout")
    print("  ✓ LEO status for CAD-911")
    print("^2========================================^0")
end)

-- Chat suggestions
Citizen.CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/d', 'Toggle duty', {
        { name = "department", help = "sasp/lcso/lspd/bcso/lsfd/bcfd/off" }
    })
    
    TriggerEvent('chat:addSuggestion', '/duty', 'Toggle duty', {
        { name = "department", help = "sasp/lcso/lspd/bcso/lsfd/bcfd/off" }
    })
    
    TriggerEvent('chat:addSuggestion', '/togglecallouts', 'Toggle 911 in chat')
    TriggerEvent('chat:addSuggestion', '/callouts', 'Toggle 911 in chat')
    
    TriggerEvent('chat:addSuggestion', '/togglepostal', 'Toggle postal codes')
    TriggerEvent('chat:addSuggestion', '/cdepostal', 'Toggle postal codes')
    TriggerEvent('chat:addSuggestion', '/p', 'Set a GPS route to a postal code', {
        { name = "postal", help = "postal code, or empty/clear to remove the route" }
    })
    
    TriggerEvent('chat:addSuggestion', '/loadout', 'Change loadout', {
        { name = "type", help = "swat/standard" }
    })
    
    TriggerEvent('chat:addSuggestion', '/dutyinfo', 'Check duty status')
    TriggerEvent('chat:addSuggestion', '/route911', 'Route to last 911')
    TriggerEvent('chat:addSuggestion', '/cleargps', 'Clear GPS')

    TriggerEvent('chat:addSuggestion', '/ts', 'Initiate a traffic stop on the last Wraith-locked plate', {
        { name = "plate", help = "(optional) plate to use instead of the last locked plate" }
    })
    TriggerEvent('chat:addSuggestion', '/trafficstop', 'Alias for /ts', {
        { name = "plate", help = "(optional) plate to use instead of the last locked plate" }
    })
end)
end
