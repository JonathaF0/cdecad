do
    local Config = DutyConfig

local isOnDuty = false
local currentJob = nil
local currentDepartment = nil
local lastCallData = nil
local calloutSettings = {
    showCallouts = true,
    showPostal = true
}

print("^2[CDE-DUTY] Client loading...^0")


RegisterNetEvent('CDE:SetRadioAgency')
AddEventHandler('CDE:SetRadioAgency', function(agency)
    if agency then
        agency = string.lower(agency)
        print("^3[CDE-DUTY] Setting radio agency: " .. agency .. "^0")
        
        ExecuteCommand("setradioagency " .. agency)
        
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


RegisterNetEvent('CDE:ReceivePaycheck')
AddEventHandler('CDE:ReceivePaycheck', function(amount, balance)
    SetNotificationTextEntry("STRING")
    local line = "~g~PAYCHECK~n~~w~+$" .. tostring(amount) .. " deposited to your CAD bank"
    if balance then line = line .. "~n~~y~Balance: $" .. tostring(balance) end
    AddTextComponentString(line)
    DrawNotification(false, true)

    PlaySoundFrontend(-1, "WAYPOINT_SET", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
end)


RegisterNetEvent('CDE:SetLEOStatus')
AddEventHandler('CDE:SetLEOStatus', function(status)
    if status then
        print("^2[CDE-DUTY] LEO status: Active^0")
    else
        print("^3[CDE-DUTY] LEO status: Inactive^0")
    end
end)


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
    
    local playerPed = PlayerPedId()
    SetPedArmour(playerPed, 100)
    
    GiveWeaponToPed(playerPed, GetHashKey("WEAPON_FLARE"), 20, false, false)
    
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
    
    if Config and Config.WeaponLoadouts then
        GiveDutyLoadout(department or deptConfig.type)
    end
    
    if deptConfig.type == "leo" then
        TriggerEvent('CDE:SetLEOStatus', true)
        
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
    
    if Config and Config.Advanced and Config.Advanced.RemoveWeaponsOffDuty then
        RemoveAllPedWeapons(PlayerPedId(), false)
    end
    
    TriggerEvent('CDE:SetLEOStatus', false)
end)


local function StripPostal(location)
    if type(location) ~= 'string' then return location end
    location = location:gsub("%s*%(%s*Postal%s+%d+%s*%)", "")
    location = location:gsub("%s*%-%s*Postal%s+%d+", "")
    location = location:gsub("%s*Postal%s+%d+", "")
    return (location:gsub("%s+$", ""))
end

RegisterNetEvent('CDE:Receive911')
AddEventHandler('CDE:Receive911', function(callData)
    if not isOnDuty then return end

    lastCallData = callData

    if calloutSettings.showCallouts == false then return end

    PlaySoundFrontend(-1, "CHALLENGE_UNLOCKED", "HUD_AWARDS", true)
    
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
            location = StripPostal(location)
        end
        notifText = notifText .. "~n~~y~" .. location
    end
    
    AddTextComponentString(notifText)
    DrawNotification(false, true)
    
    if calloutSettings.showCallouts then
        local details = ""
        if callData.location then
            local location = callData.location
            if not calloutSettings.showPostal then
                location = StripPostal(location)
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
    
    if callData.coords and Config and Config.GPSRouting and Config.GPSRouting.AutoRoute then
        SetNewWaypoint(callData.coords.x, callData.coords.y)
        print("^2[911] GPS waypoint set^0")
    end
end)


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


function GiveDutyLoadout(loadoutType)
    if not Config or not Config.WeaponLoadouts then return end
    
    local playerPed = PlayerPedId()
    local loadout = Config.WeaponLoadouts[loadoutType]

    local hops = 0
    while type(loadout) == "string" do
        hops = hops + 1
        if hops > 10 then loadout = nil break end
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


RegisterCommand('dutycallouts', function()
    calloutSettings.showCallouts = not calloutSettings.showCallouts
    TriggerServerEvent('CDE:UpdateCalloutSettings', calloutSettings)
    
    SetNotificationTextEntry("STRING")
    AddTextComponentString("911 Callouts: " .. (calloutSettings.showCallouts and "~g~ON" or "~r~OFF"))
    DrawNotification(false, false)
end, false)

RegisterCommand('callouts', function()
    ExecuteCommand("dutycallouts")
end, false)

RegisterCommand('togglepostal', function()
    calloutSettings.showPostal = not calloutSettings.showPostal
    TriggerServerEvent('CDE:UpdateCalloutSettings', calloutSettings)
    
    SetNotificationTextEntry("STRING")
    AddTextComponentString("Postal Codes: " .. (calloutSettings.showPostal and "~g~ON" or "~r~OFF"))
    DrawNotification(false, false)
end, false)

RegisterCommand('cdepostal', function()
    ExecuteCommand("togglepostal")
end, false)


local postalDb = nil
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

    TriggerServerEvent('CDE:RequestRoute911')
end, false)

local function RouteToCoords(x, y, location)
    SetNewWaypoint(x, y)
    SetNotificationTextEntry("STRING")
    local msg = "~g~GPS set to last 911"
    if type(location) == 'string' and location ~= '' and location ~= 'Unknown' then
        msg = msg .. "~n~~w~" .. location
    end
    AddTextComponentString(msg)
    DrawNotification(false, false)
end

RegisterNetEvent('CDE:Route911Result')
AddEventHandler('CDE:Route911Result', function(res)
    if res and res.success and res.coords
       and type(res.coords.x) == 'number' and type(res.coords.y) == 'number' then
        RouteToCoords(res.coords.x, res.coords.y, res.location)
        return
    end

    local lc = lastCallData and lastCallData.coords
    if lc and type(lc.x) == 'number' and type(lc.y) == 'number'
       and (lc.x ~= 0 or lc.y ~= 0) then
        RouteToCoords(lc.x, lc.y, lastCallData.location)
        return
    end

    SetNotificationTextEntry("STRING")
    AddTextComponentString("~y~No recent 911 calls")
    DrawNotification(false, false)
end)

RegisterCommand('cleargps', function()
    DeleteWaypoint()
    SetNotificationTextEntry("STRING")
    AddTextComponentString("~y~GPS cleared")
    DrawNotification(false, false)
end, false)


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
    print("  /dutycallouts - Toggle 911 in chat")
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

local function buildDeptHelp()
    if not Config or not Config.Departments then
        return "department/off"
    end
    local keys = {}
    for k in pairs(Config.Departments) do keys[#keys + 1] = k end
    table.sort(keys)
    keys[#keys + 1] = "off"
    return table.concat(keys, "/")
end

Citizen.CreateThread(function()
    local deptHelp = buildDeptHelp()

    TriggerEvent('chat:addSuggestion', '/d', 'Toggle duty', {
        { name = "department", help = deptHelp }
    })

    TriggerEvent('chat:addSuggestion', '/duty', 'Toggle duty', {
        { name = "department", help = deptHelp }
    })
    
    TriggerEvent('chat:addSuggestion', '/dutycallouts', 'Toggle 911 in chat')
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
