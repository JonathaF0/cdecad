do
    local Config = WraithConfig
    if not Config or not Config.Enabled then return end

    do
        local baseUrl = GetConvar('CDE_CAD_API_URL', '')
        if baseUrl ~= '' and not baseUrl:find('/api$') then
            Config.API_URL = baseUrl:gsub('/$', '') .. '/api'
        else
            Config.API_URL = baseUrl:gsub('/$', '')
        end
    end
    Config.API_KEY      = GetConvar('CDE_CAD_API_KEY', '')
    Config.COMMUNITY_ID = GetConvar('CDE_CAD_COMMUNITY_ID', '')

-- =============================================================================
-- CONSTANTS
-- =============================================================================

local CACHE_REFRESH_MS = 60 * 60 * 1000

-- =============================================================================
-- STATE
-- =============================================================================

local plateCache = {}
local flaggedCache = {}
local flaggedCacheGeneratedAt = nil
local flaggedCacheCount = 0
local registeredCache = {}
local registeredCacheCount = 0
local scanResultCooldown = {}
local SCAN_RESULT_COOLDOWN_S = 30

-- =============================================================================
-- HELPERS
-- =============================================================================

local function DebugPrint(...)
    if Config.Debug then
        print('[CDE-Wraith]', ...)
    end
end

local function NormalizePlate(plate)
    if not plate then return '' end
    return (plate:gsub('%s', '')):upper()
end
local function FindPlayerVehicleByPlate(plate)
    local target = NormalizePlate(plate)
    if target == '' then return nil end
    for _, pid in ipairs(GetPlayers()) do
        -- GetPlayers() returns source IDs as strings; cast for natives.
        local src = tonumber(pid)
        if src then
            local ped = GetPlayerPed(src)
            if ped and ped ~= 0 then
                local veh = GetVehiclePedIsIn(ped, false)
                if veh and veh ~= 0 then
                    if NormalizePlate(GetVehicleNumberPlateText(veh)) == target then
                        return veh, src
                    end
                end
            end
        end
    end
    return nil
end

local emergencyModelHashes = nil

local function IsEmergencyVehicle(veh)
    if not veh or veh == 0 then return false end
    if not Config.PlateReader.EmergencyVehicleModels then return false end
    local model = GetEntityModel(veh)
    if not model then return false end
    if not emergencyModelHashes then
        emergencyModelHashes = {}
        for _, name in ipairs(Config.PlateReader.EmergencyVehicleModels) do
            emergencyModelHashes[GetHashKey(name)] = true
        end
    end
    return emergencyModelHashes[model] == true
end

local function MatchesEmergencyPlate(plate)
    local patterns = Config.PlateReader.EmergencyPlatePatterns
    if not patterns then return false end
    for _, pat in ipairs(patterns) do
        if plate:match(pat) then return true end
    end
    return false
end

-- =============================================================================
-- FLAGGED-PLATES CACHE (scan-time matching, never hits the API per scan)
-- =============================================================================

local function RebuildFlaggedCache()
    local url = Config.API_URL .. '/civilian/fivem-flagged-plates?communityId=' .. Config.COMMUNITY_ID

    DebugPrint('Rebuilding flagged-plates cache from', url)

    PerformHttpRequest(url, function(statusCode, responseText)
        if statusCode ~= 200 or not responseText or responseText == '' then
            print(('[CDE-Wraith] Flagged-plates cache refresh FAILED (status %s). Cache unchanged.'):format(tostring(statusCode)))
            return
        end

        local ok, data = pcall(json.decode, responseText)
        if not ok or not data or not data.success or type(data.plates) ~= 'table' then
            print('[CDE-Wraith] Flagged-plates cache refresh: bad response payload')
            return
        end

        -- Atomic swap: build the new map fully before replacing the live one.
        local newCache = {}
        local count = 0
        for _, entry in ipairs(data.plates) do
            local plate = NormalizePlate(entry.plate)
            if plate ~= '' then
                newCache[plate] = {
                    flags = entry.flags or {},
                    alertLevel = entry.alertLevel or 'caution',
                }
                count = count + 1
            end
        end

        flaggedCache = newCache
        flaggedCacheCount = count
        flaggedCacheGeneratedAt = data.generatedAt or os.date('!%Y-%m-%dT%H:%M:%SZ')

        -- Build the clean-registered set in the same swap.
        local newRegistered = {}
        local regCount = 0
        if type(data.cleanPlates) == 'table' then
            for _, p in ipairs(data.cleanPlates) do
                local plate = NormalizePlate(p)
                if plate ~= '' then
                    newRegistered[plate] = true
                    regCount = regCount + 1
                end
            end
        end
        registeredCache = newRegistered
        registeredCacheCount = regCount

        print(('[CDE-Wraith] Plate cache rebuilt: %d flagged + %d clean = %d total'):format(
            count, regCount, count + regCount
        ))
    end, 'GET', '', {
        ['Content-Type'] = 'application/json',
        ['x-api-key'] = Config.API_KEY,
    })
end

-- =============================================================================
-- FULL API LOOKUP (on lock — original baseline behaviour)
-- =============================================================================

local function LookupPlate(plate, source, cam)
    -- Clean the plate (Wraith pads plates with spaces to 8 chars)
    local cleanPlate = plate:gsub('%s', '')

    if cleanPlate == '' then return end

    -- Check cooldown cache
    local cacheKey = cleanPlate:upper()
    local now = os.time()

    if plateCache[cacheKey] and (now - plateCache[cacheKey].time) < Config.PlateReader.LookupCooldown then
        DebugPrint('Cache hit for plate:', cleanPlate)
        TriggerClientEvent('cde-wraith:plateResult', source, plateCache[cacheKey].data, cam)
        return
    end

    local url = Config.API_URL .. '/civilian/fivem-plate-lookup/' .. cleanPlate .. '?communityId=' .. Config.COMMUNITY_ID

    DebugPrint('Looking up plate:', cleanPlate, 'URL:', url)

    PerformHttpRequest(url, function(statusCode, responseText, responseHeaders)
        DebugPrint('Response:', statusCode, responseText)

        if statusCode ~= 200 or not responseText or responseText == '' then
            DebugPrint('Lookup failed - status:', statusCode)
            TriggerClientEvent('cde-wraith:plateResult', source, {
                success = true,
                found = false,
                plate = cleanPlate,
            }, cam)
            return
        end

        local ok, data = pcall(json.decode, responseText)
        if not ok or not data then
            DebugPrint('Failed to decode response')
            return
        end

        plateCache[cacheKey] = { time = now, data = data }
        TriggerClientEvent('cde-wraith:plateResult', source, data, cam)

        local playerName = GetPlayerName(source) or 'Unknown'
        if data.found then
            print(('[CDE-Wraith] %s looked up plate %s via %s reader - Alert: %s'):format(
                playerName, cleanPlate, cam, data.alertLevel or 'none'
            ))
        end

    end, 'GET', '', {
        ['Content-Type'] = 'application/json',
        ['x-api-key'] = Config.API_KEY,
    })
end

-- =============================================================================
-- WRAITH ARS 2X EVENT HANDLERS
-- =============================================================================

-- Wraith fires TriggerServerEvent("wk:onPlateLocked") from the client plate reader.

local function HandlePlateLocked(cam, plate, index)
    local src = source

    print(('[CDE-Wraith] >>> PLATE LOCKED | source=%s cam=%s plate=%s index=%s'):format(
        tostring(src), tostring(cam), tostring(plate), tostring(index)
    ))

    if not Config.PlateReader.LookupOnLock then
        print('[CDE-Wraith] LookupOnLock is disabled, ignoring')
        return
    end

    -- Skip permission check if no framework is configured (matches working baseline)
    if Config.Permissions.RestrictToJobs and (Config.Permissions.UseQBCore or Config.Permissions.UseESX) then
        TriggerEvent('cde-wraith:checkPermission', src, function(allowed)
            if allowed then
                LookupPlate(plate, src, cam)
            else
                print('[CDE-Wraith] Permission denied for player ' .. tostring(src))
            end
        end)
    else
        LookupPlate(plate, src, cam)
    end
end

RegisterNetEvent('wk:onPlateLocked', HandlePlateLocked)

local scanProbeCount = 0

RegisterNetEvent('wk:onPlateScanned', function(cam, plate, index)
    if not Config.PlateReader.LookupOnScan then return end

    local cleanPlate = NormalizePlate(plate)
    if cleanPlate == '' then return end

    local src = source

    if Config.PlateReader.IgnoreEmergencyVehicles and MatchesEmergencyPlate(cleanPlate) then
        if Config.Debug then
            print(('[CDE-Wraith] scan filter: plate=%s skipped by EmergencyPlatePatterns'):format(cleanPlate))
        end
        return
    end


    local playerVerified = false
    if Config.PlateReader.OnlyPlayerPlates or Config.PlateReader.IgnoreEmergencyVehicles then
        local veh, ownerSrc = FindPlayerVehicleByPlate(cleanPlate)
        if Config.Debug then
            print(('[CDE-Wraith] scan filter: plate=%s playerVeh=%s model=%s owner=%s'):format(
                cleanPlate,
                tostring(veh),
                veh and tostring(GetEntityModel(veh)) or 'n/a',
                ownerSrc and (GetPlayerName(ownerSrc) or tostring(ownerSrc)) or 'n/a'
            ))
        end
        if Config.PlateReader.OnlyPlayerPlates and not veh then
            return -- not a player-driven vehicle, drop silently
        end
        if veh and Config.PlateReader.IgnoreEmergencyVehicles and IsEmergencyVehicle(veh) then
            if Config.Debug then
                print(('[CDE-Wraith] scan filter: plate=%s skipped by EmergencyVehicleModels (model=%s)'):format(
                    cleanPlate, tostring(GetEntityModel(veh))
                ))
            end
            return -- on-duty cruiser / ambulance / fire — don't alert on coworkers
        end
        playerVerified = veh ~= nil
    end

    if Config.Debug then
        scanProbeCount = scanProbeCount + 1
        if scanProbeCount <= 5 or scanProbeCount % 50 == 0 then
            print(('[CDE-Wraith] DEBUG scan #%d plate="%s" cam=%s player=%s'):format(
                scanProbeCount, tostring(plate), tostring(cam), tostring(playerVerified)
            ))
        end
    end

    local hit = flaggedCache[cleanPlate]

    local function fire(allowed)
        if not allowed then return end

        local key = tostring(src) .. ':' .. cleanPlate
        local now = os.time()
        if scanResultCooldown[key] and (now - scanResultCooldown[key]) < SCAN_RESULT_COOLDOWN_S then
            return
        end
        scanResultCooldown[key] = now

        if hit then
            TriggerClientEvent('cde-wraith:plateResult', src, {
                success = true,
                found = true,
                plate = cleanPlate,
                alertLevel = hit.alertLevel,
                flags = hit.flags,
                cached = true,
            }, cam)
            return
        end


        if playerVerified then
            if registeredCache[cleanPlate] then
                if Config.PlateReader.ShowCleanScans then
                    TriggerClientEvent('cde-wraith:plateResult', src, {
                        success = true,
                        found = true,
                        plate = cleanPlate,
                        alertLevel = 'none',
                        flags = {},
                        cached = true,
                    }, cam)
                end
                return
            end
            TriggerClientEvent('cde-wraith:plateResult', src, {
                success = true,
                found = true,
                plate = cleanPlate,
                alertLevel = 'caution',
                flags = { 'NOT REGISTERED' },
                cached = true,
            }, cam)
            return
        end

        TriggerClientEvent('cde-wraith:plateResult', src, {
            success = true,
            found = false,
            plate = cleanPlate,
            cached = true,
        }, cam)
    end

    if Config.Permissions.RestrictToJobs and (Config.Permissions.UseQBCore or Config.Permissions.UseESX) then
        TriggerEvent('cde-wraith:checkPermission', src, fire)
    else
        fire(true)
    end
end)

-- =============================================================================
-- PERMISSION CHECK
-- =============================================================================

AddEventHandler('cde-wraith:checkPermission', function(src, callback)
    -- If no framework restriction, allow everyone
    if not Config.Permissions.RestrictToJobs then
        callback(true)
        return
    end

    if Config.Permissions.UseQBCore then
        local QBCore = exports['qb-core']:GetCoreObject()
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            local job = Player.PlayerData.job.name
            for _, allowedJob in ipairs(Config.Permissions.AllowedJobs) do
                if job == allowedJob then
                    callback(true)
                    return
                end
            end
        end
        callback(false)

    elseif Config.Permissions.UseESX then
        local ESX = exports['es_extended']:getSharedObject()
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            local job = xPlayer.getJob().name
            for _, allowedJob in ipairs(Config.Permissions.AllowedJobs) do
                if job == allowedJob then
                    callback(true)
                    return
                end
            end
        end
        callback(false)

    else
        -- No framework - allow all
        callback(true)
    end
end)

-- =============================================================================
-- COMMANDS
-- =============================================================================

RegisterCommand('platelookup', function(source, args)
    if source == 0 then
        print('[CDE-Wraith] This command can only be used in-game')
        return
    end

    local plate = table.concat(args, ' ')
    if plate == '' then
        TriggerClientEvent('chat:addMessage', source, {
            args = { '^1[CDE-Wraith]', 'Usage: /platelookup [plate number]' }
        })
        return
    end

    LookupPlate(plate, source, 'manual')
end, false)

RegisterCommand('cdewraithtest', function(source, args)
    local plate = args[1] or 'TEST123'
    print(('[CDE-Wraith] SELF-TEST invoked by source=%s plate=%s'):format(tostring(source), plate))
    LookupPlate(plate, source > 0 and source or 1, 'test')
end, true)

RegisterCommand('cdewraithplayers', function(source, args)
    local lines = {}
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        if src then
            local ped = GetPlayerPed(src)
            local veh = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
            local plate = veh and veh ~= 0 and NormalizePlate(GetVehicleNumberPlateText(veh)) or 'n/a'
            local model = veh and veh ~= 0 and tostring(GetEntityModel(veh)) or 'n/a'
            lines[#lines + 1] = ('  src=%s name=%s plate=%s model=%s'):format(
                tostring(src), GetPlayerName(src) or '?', plate, model
            )
        end
    end
    print('[CDE-Wraith] Online player vehicles:')
    for _, l in ipairs(lines) do print(l) end
end, true)

-- Admin: force-refresh the flagged-plates cache (useful after issuing a BOLO)
RegisterCommand('cdewraithrefresh', function(source, args)
    if source ~= 0 and not IsPlayerAceAllowed(source, 'command.cdewraithrefresh') then
        return
    end
    print('[CDE-Wraith] Manual flagged-plates cache refresh requested')
    RebuildFlaggedCache()
end, true)

RegisterCommand('cdewraithstatus', function(source, args)
    local msg = ('Plate cache: %d flagged + %d clean, generated %s'):format(
        flaggedCacheCount,
        registeredCacheCount,
        tostring(flaggedCacheGeneratedAt or 'never')
    )
    if source > 0 then
        TriggerClientEvent('chat:addMessage', source, { args = { '^3[CDE-Wraith]', msg } })
    else
        print('[CDE-Wraith] ' .. msg)
    end
end, true)

-- =============================================================================
-- CACHE CLEANUP (per-plate lookup cooldown)
-- =============================================================================

CreateThread(function()
    while true do
        Wait(300000) -- 5 minutes
        local now = os.time()
        local cleared = 0
        for k, v in pairs(plateCache) do
            if (now - v.time) > Config.PlateReader.LookupCooldown * 2 then
                plateCache[k] = nil
                cleared = cleared + 1
            end
        end
        for k, t in pairs(scanResultCooldown) do
            if (now - t) > SCAN_RESULT_COOLDOWN_S * 2 then
                scanResultCooldown[k] = nil
            end
        end
        if cleared > 0 then
            DebugPrint('Cleared', cleared, 'stale cache entries')
        end
    end
end)

-- =============================================================================
-- STARTUP + 60-MINUTE FLAGGED-PLATES REFRESH (HARDCODED)
-- =============================================================================

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetTimeout(3000, function()
        RebuildFlaggedCache()
    end)
end)

CreateThread(function()
    while true do
        Wait(CACHE_REFRESH_MS)
        RebuildFlaggedCache()
    end
end)

print('[CDE-Wraith] Wraith ARS 2X <> CDECAD integration loaded')
print('[CDE-Wraith] Debug: ' .. tostring(Config.Debug) ..
    ' | LookupOnLock: ' .. tostring(Config.PlateReader.LookupOnLock) ..
    ' | LookupOnScan: ' .. tostring(Config.PlateReader.LookupOnScan) ..
    ' | RestrictToJobs: ' .. tostring(Config.Permissions.RestrictToJobs))
print('[CDE-Wraith] Listening for wk:onPlateLocked (TriggerServerEvent from Wraith client)')
print('[CDE-Wraith] Test: /cdewraithtest [plate] or /platelookup [plate]')


CreateThread(function()
    Wait(2000) -- let all resources settle
    local state = GetResourceState('wk_wars2x')
    if state == 'started' then
        print('[CDE-Wraith] OK: wk_wars2x detected (state=started)')
    else
        print(('[CDE-Wraith] WARNING: wk_wars2x is "%s" — cde-wraith will receive no plate events until it is started.'):format(state or 'missing'))
        print('[CDE-Wraith] Add `ensure wk_wars2x` to server.cfg (before `ensure cde-wraith`) and restart.')
    end
end)

end
