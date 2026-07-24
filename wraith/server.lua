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



local CACHE_REFRESH_MS = 60 * 60 * 1000


local plateCache = {}

local flaggedCache = {}
local flaggedCacheGeneratedAt = nil
local flaggedCacheCount = 0

local registeredCache = {}
local registeredCacheCount = 0

local scanResultCooldown = {}
local SCAN_RESULT_COOLDOWN_S = 30


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

        local newCache = {}
        local count = 0
        for _, entry in ipairs(data.plates) do
            local plate = NormalizePlate(entry.plate)
            if plate ~= '' then
                newCache[plate] = {
                    flags = entry.flags or {},
                    alertLevel = entry.alertLevel or 'caution',
                    owner = entry.owner,
                    dl = entry.dl,
                }
                count = count + 1
            end
        end

        flaggedCache = newCache
        flaggedCacheCount = count
        flaggedCacheGeneratedAt = data.generatedAt or os.date('!%Y-%m-%dT%H:%M:%SZ')

        local newRegistered = {}
        local regCount = 0
        if type(data.cleanInfo) == 'table' then
            for _, info in ipairs(data.cleanInfo) do
                local plate = NormalizePlate(type(info) == 'table' and info.plate or nil)
                if plate ~= '' then
                    newRegistered[plate] = { owner = info.owner, dl = info.dl }
                    regCount = regCount + 1
                end
            end
        elseif type(data.cleanPlates) == 'table' then
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


local plateLookupBySource = {}

local function LookupPlate(plate, source, cam)
    if type(plate) ~= 'string' then return end
    local cleanPlate = plate:gsub('%s', ''):gsub('[^%w]', '')

    if cleanPlate == '' then return end

    local nowT = GetGameTimer()
    if source and source > 0 then
        local last = plateLookupBySource[source]
        if last and (nowT - last) < 750 then return end
        plateLookupBySource[source] = nowT
    end

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
            print(('[CDE-Wraith] Lock lookup for %s FAILED (status %s) - sending not-found to client'):format(
                cleanPlate, tostring(statusCode)))
            TriggerClientEvent('cde-wraith:plateResult', source, {
                success = true,
                found = false,
                plate = cleanPlate,
            }, cam)
            return
        end

        local ok, data = pcall(json.decode, responseText)
        if not ok or not data then
            print(('[CDE-Wraith] Lock lookup for %s returned UNPARSEABLE response (%s...) - sending not-found'):format(
                cleanPlate, tostring(responseText):sub(1, 80)))
            TriggerClientEvent('cde-wraith:plateResult', source, {
                success = true,
                found = false,
                plate = cleanPlate,
            }, cam)
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



local function WkArgs(a, b, c)
    if type(a) == 'table' then
        return a.cam or a.camera or a.antenna or a.ant, a.plate, a.index
    end
    return a, b, c
end

local lockEventDedup = {}
local lockEventDedupCount = 0

local function HandlePlateLocked(a, b, c)
    local src = source
    local cam, plate, index = WkArgs(a, b, c)

    print(('[CDE-Wraith] >>> PLATE LOCKED | source=%s cam=%s plate=%s index=%s'):format(
        tostring(src), tostring(cam), tostring(plate), tostring(index)
    ))

    if not Config.PlateReader.LookupOnLock then
        print('[CDE-Wraith] LookupOnLock is disabled, ignoring')
        return
    end

    local dedupKey = tostring(src) .. ':' .. NormalizePlate(plate or '')
    local nowMs = GetGameTimer()
    if lockEventDedup[dedupKey] and (nowMs - lockEventDedup[dedupKey]) < 2000 then
        return
    end
    if lockEventDedupCount > 512 then
        lockEventDedup, lockEventDedupCount = {}, 0
    end
    if not lockEventDedup[dedupKey] then lockEventDedupCount = lockEventDedupCount + 1 end
    lockEventDedup[dedupKey] = nowMs

    LookupPlate(plate, src, cam)
end

RegisterNetEvent('wk:onPlateLocked', HandlePlateLocked)

local scanProbeCount = 0

RegisterNetEvent('wk:onPlateScanned', function(a, b, c)
    local cam, plate, index = WkArgs(a, b, c)
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
            return
        end
        if veh and Config.PlateReader.IgnoreEmergencyVehicles and IsEmergencyVehicle(veh) then
            if Config.Debug then
                print(('[CDE-Wraith] scan filter: plate=%s skipped by EmergencyVehicleModels (model=%s)'):format(
                    cleanPlate, tostring(GetEntityModel(veh))
                ))
            end
            return
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

    fire(true)
end)

RegisterNetEvent('cde-wraith:lockWkDisplay', function(cam)
    local src = source
    cam = cam == 'rear' and 'rear' or 'front'
    pcall(function()
        exports['wk_wars2x']:TogglePlateLock(src, cam, true, false)
    end)
end)


RegisterNetEvent('cdecad-reader:check', function(batch)
    local src = source
    if type(batch) ~= 'table' then return end
    local results = {}
    for i, item in ipairs(batch) do
        if i > 20 then break end
        local plate = NormalizePlate(type(item) == 'table' and item.plate or nil)
        if plate ~= '' then
            local cam = (type(item) == 'table' and item.cam == 'rear') and 'rear' or 'front'
            local hit = flaggedCache[plate]
            local data
            if hit then
                data = { success = true, found = true, plate = plate, alertLevel = hit.alertLevel, flags = hit.flags, owner = hit.owner, dl = hit.dl, cached = true }
            elseif registeredCache[plate] then
                local reg = registeredCache[plate]
                local owner, dl = nil, nil
                if type(reg) == 'table' then owner, dl = reg.owner, reg.dl end
                data = { success = true, found = true, plate = plate, alertLevel = 'none', flags = {}, owner = owner, dl = dl, cached = true }
            else
                data = { success = true, found = false, plate = plate, cached = true }
            end
            results[#results + 1] = { data = data, cam = cam }
        end
    end
    if #results > 0 then
        TriggerClientEvent('cdecad-reader:result', src, results)
    end
end)


local plateDesignsPayload = nil

local function RefreshPlateDesigns()
    if Config.API_URL == '' or Config.COMMUNITY_ID == '' then return end
    local url = Config.API_URL .. '/civilian/fivem-plate-designs?communityId=' .. Config.COMMUNITY_ID
    PerformHttpRequest(url, function(statusCode, responseText)
        if statusCode ~= 200 or not responseText or responseText == '' then
            DebugPrint('Plate designs refresh failed (status ' .. tostring(statusCode) .. ')')
            return
        end
        local ok, data = pcall(json.decode, responseText)
        if not ok or type(data) ~= 'table' or not data.success then
            DebugPrint('Plate designs refresh: bad response payload')
            return
        end
        local nDesigns, nPlates = 0, 0
        for _ in pairs(data.plateDesigns or {}) do nDesigns = nDesigns + 1 end
        for _ in pairs(data.designIdByPlate or {}) do nPlates = nPlates + 1 end
        plateDesignsPayload = {
            designs = data.plateDesigns or {},
            byPlate = data.designIdByPlate or {},
        }
        print(('[CDE-Wraith] Custom plate designs loaded: %d design(s) across %d plate(s)'):format(nDesigns, nPlates))
        TriggerClientEvent('cde-wraith:plateDesigns', -1, plateDesignsPayload)
    end, 'GET', '', {
        ['x-api-key'] = Config.API_KEY,
    })
end

RegisterNetEvent('cde-wraith:getPlateDesigns', function()
    local src = source
    if plateDesignsPayload then
        TriggerClientEvent('cde-wraith:plateDesigns', src, plateDesignsPayload)
    end
end)


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

RegisterCommand('cdewraithrefresh', function(source, args)
    if source ~= 0 and not IsPlayerAceAllowed(source, 'command.cdewraithrefresh') then
        return
    end
    print('[CDE-Wraith] Manual flagged-plates cache refresh requested')
    RebuildFlaggedCache()
    RefreshPlateDesigns()
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


CreateThread(function()
    while true do
        Wait(300000)
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


AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetTimeout(3000, function()
        RebuildFlaggedCache()
        RefreshPlateDesigns()
    end)
end)

CreateThread(function()
    while true do
        Wait(CACHE_REFRESH_MS)
        RebuildFlaggedCache()
        RefreshPlateDesigns()
    end
end)

print('[CDE-Wraith] Wraith ARS 2X <> CDECAD integration loaded')
print('[CDE-Wraith] Debug: ' .. tostring(Config.Debug) ..
    ' | LookupOnLock: ' .. tostring(Config.PlateReader.LookupOnLock) ..
    ' | LookupOnScan: ' .. tostring(Config.PlateReader.LookupOnScan))
print('[CDE-Wraith] Listening for wk:onPlateLocked (TriggerServerEvent from Wraith client)')
print('[CDE-Wraith] Test: /cdewraithtest [plate] or /platelookup [plate]')

CreateThread(function()
    Wait(2000)
    local state = GetResourceState('wk_wars2x')
    if state == 'started' then
        print('[CDE-Wraith] OK: wk_wars2x detected (state=started)')

        local ver  = GetResourceMetadata('wk_wars2x', 'version', 0)
        local path = GetResourcePath('wk_wars2x')
        print(('[CDE-Wraith] wk_wars2x version=%s'):format(tostring(ver)))
        print(('[CDE-Wraith] wk_wars2x path=%s'):format(tostring(path)))

        local emitKind, emitFile = nil, nil
        local checked = false
        for _, f in ipairs({ 'cl_plate_reader.lua', 'cl_radar.lua', 'cl_reader.lua' }) do
            local body = LoadResourceFile('wk_wars2x', f)
            if body then
                checked = true
                if body:find('TriggerServerEvent%s*%(%s*["\']wk:onPlateLocked') then
                    emitKind, emitFile = 'server', f
                    break
                elseif body:find('TriggerEvent%s*%(%s*["\']wk:onPlateLocked') then
                    emitKind, emitFile = 'local', f
                    break
                elseif not emitKind and body:find('wk:onPlateLocked', 1, true) then
                    emitKind, emitFile = 'mention', f
                end
            end
        end
        if emitKind == 'server' then
            print(('[CDE-Wraith] RUNNING wk_wars2x: %s fires TriggerServerEvent("wk:onPlateLocked") - locks reach the CAD directly. A real lock MUST print ">>> PLATE LOCKED" in this console; if it does not, the client is running a different cached copy.'):format(emitFile))
        elseif emitKind == 'local' then
            print(('[CDE-Wraith] RUNNING wk_wars2x: %s fires wk:onPlateLocked as a CLIENT-LOCAL event - the CDECAD client bridge forwards it (watch for "[CDE-Wraith] bridging" in F8 on lock).'):format(emitFile))
        elseif emitKind == 'mention' then
            print(('[CDE-Wraith] !!! RUNNING wk_wars2x: %s MENTIONS wk:onPlateLocked but never fires it (commented out or modified). Locks CANNOT reach the CAD from this build - use /cdelockfront + /cdelockrear.'):format(emitFile))
        elseif checked then
            print('[CDE-Wraith] !!! RUNNING wk_wars2x does NOT emit wk:onPlateLocked - the live copy is NOT the file you inspected (stale or duplicate folder). Native lock keys reach the CAD only via seamless export polling (or /cdelockfront + /cdelockrear).')
        else
            print('[CDE-Wraith] Could not read the running wk_wars2x client files to verify the integration events.')
        end

        local exportNames = {}
        local metaFiles = {}
        for _, key in ipairs({ 'client_script', 'shared_script' }) do
            local n = GetNumResourceMetadata('wk_wars2x', key) or 0
            for i = 0, n - 1 do
                metaFiles[#metaFiles + 1] = GetResourceMetadata('wk_wars2x', key, i)
            end
        end
        for _, f in ipairs(metaFiles) do
            local body = LoadResourceFile('wk_wars2x', f)
            if body then
                for name in body:gmatch('exports%s*%(%s*["\']([%w_]+)["\']') do
                    exportNames[#exportNames + 1] = name
                end
            end
        end
        if #exportNames > 0 then
            print('[CDE-Wraith] wk_wars2x client exports: ' .. table.concat(exportNames, ', ') ..
                ' (usable for Config.SeamlessLock overrides)')
        else
            print('[CDE-Wraith] wk_wars2x registers NO client exports - seamless lock polling cannot work on this build; use /cdelockfront + /cdelockrear (bindable in FiveM keybinds).')
        end
    else
        print(('[CDE-Wraith] WARNING: wk_wars2x is "%s" - cde-wraith will receive no plate events until it is started.'):format(state or 'missing'))
        print('[CDE-Wraith] Add `ensure wk_wars2x` to server.cfg (before `ensure cde-wraith`) and restart.')
    end
end)

end
