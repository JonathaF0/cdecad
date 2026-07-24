do
    local Config = CivConfig

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

local ActiveCivilians = {}

function CDECAD_GetActiveCivilian(src)
    return ActiveCivilians[src]
end

local CommunitySettings = nil


local function Debug(...)
    if Config.Debug then
        print('[CDECAD-CIVMANAGER]', ...)
    end
end

local function GetDiscordId(source)
    local identifiers = GetPlayerIdentifiers(source)
    for _, id in ipairs(identifiers) do
        if string.find(id, 'discord:') then
            return id:gsub('discord:', '')
        end
    end
    return nil
end

local function GetLicense(source)
    local identifiers = GetPlayerIdentifiers(source)
    for _, id in ipairs(identifiers) do
        if string.find(id, 'license:') then
            return id
        end
    end
    return nil
end


local function APIRequest(method, endpoint, data, callback)
    local url = Config.API_URL .. endpoint
    
    local headers = {
        ['Content-Type'] = 'application/json',
        ['x-api-key'] = Config.API_KEY
    }
    
    Debug('API Request:', method, url)
    
    PerformHttpRequest(url, function(statusCode, responseText, responseHeaders)
        Debug('API Response:', statusCode)
        
        local success = statusCode >= 200 and statusCode < 300
        local responseData = nil
        
        if responseText and responseText ~= '' then
            local ok, decoded = pcall(json.decode, responseText)
            if ok then
                responseData = decoded
            end
        end
        
        if callback then
            callback(success, responseData, statusCode)
        end
    end, method, data and json.encode(data) or '', headers)
end

local function GetCiviliansForDiscord(discordId, callback)
    APIRequest('GET', '/civilian/fivem-civilians-by-discord/' .. discordId .. '?communityId=' .. Config.COMMUNITY_ID, nil, callback)
end

local function GetCivilianBySSN(ssn, callback)
    APIRequest('GET', '/civilian/fivem-civilian/' .. ssn .. '?communityId=' .. Config.COMMUNITY_ID, nil, callback)
end

local function RegisterVehicle(civilianId, vehicleData, callback)
    local payload = {
        plate = vehicleData.plate,
        ownerId = civilianId,
        communityId = Config.COMMUNITY_ID,
        make = vehicleData.make or 'Unknown',
        model = vehicleData.model,
        color = vehicleData.color or 'Unknown',
        year = vehicleData.year or os.date('%Y')
    }
    
    APIRequest('POST', '/civilian/fivem-register-vehicle', payload, callback)
end

local function FetchCommunitySettings(callback)
    CommunitySettings = {
        communityName = 'Unknown',
        jurisdiction = {
            city  = '',
            county = '',
            state = Config.IDCard.CardStyle.StateName or 'San Andreas'
        }
    }
    Debug('Community settings loaded from config - State:', CommunitySettings.jurisdiction.state)
    if callback then callback(CommunitySettings) end
end


local function SaveSelectedCivilian(source, civilianId)
    if Config.Persistence == 'mysql' then
        local discordId = GetDiscordId(source)
        if discordId then
            MySQL.Async.execute([[
                INSERT INTO ]] .. Config.MySQLTable .. [[ (discord_id, civilian_id, updated_at)
                VALUES (@discord, @civ, NOW())
                ON DUPLICATE KEY UPDATE civilian_id = @civ, updated_at = NOW()
            ]], {
                ['@discord'] = discordId,
                ['@civ'] = civilianId
            })
            Debug('Saved civilian to MySQL:', discordId, civilianId)
        end
    else
        Debug('KVP persistence handled client-side')
    end
end

local function LoadSelectedCivilian(source, callback)
    if Config.Persistence == 'mysql' then
        local discordId = GetDiscordId(source)
        if discordId then
            MySQL.Async.fetchScalar([[
                SELECT civilian_id FROM ]] .. Config.MySQLTable .. [[ WHERE discord_id = @discord
            ]], {
                ['@discord'] = discordId
            }, function(civilianId)
                callback(civilianId)
            end)
        else
            callback(nil)
        end
    else
        callback(nil)
    end
end


lib.callback.register('cdecad-civmanager:getCommunitySettings', function(source)
    if CommunitySettings then
        return CommunitySettings
    end
    
    local result = nil
    local completed = false
    
    FetchCommunitySettings(function(settings)
        result = settings
        completed = true
    end)
    
    while not completed do
        Wait(10)
    end
    
    return result
end)

lib.callback.register('cdecad-civmanager:getCivilians', function(source)
    local discordId = GetDiscordId(source)
    
    if not discordId then
        Debug('No Discord ID found for source:', source)
        return { success = false, error = 'No Discord ID found. Make sure Discord is linked.' }
    end
    
    Debug('Fetching civilians for Discord:', discordId)
    
    local result = nil
    local completed = false
    
    GetCiviliansForDiscord(discordId, function(success, data, statusCode)
        if success and data then
            result = { success = true, civilians = data }
        else
            result = { success = false, error = 'Failed to fetch civilians', statusCode = statusCode }
        end
        completed = true
    end)
    
    while not completed do
        Wait(10)
    end
    
    return result
end)

lib.callback.register('cdecad-civmanager:getMugshot', function(source, ssn)
    if not ssn or ssn == '' then return { mugshotUrl = nil } end

    local result, done = { mugshotUrl = nil }, false
    GetCivilianBySSN(ssn, function(success, data)
        if success and data and data.mugshotUrl then
            result.mugshotUrl = data.mugshotUrl
        end
        done = true
    end)
    while not done do Wait(10) end
    return result
end)

lib.callback.register('cdecad-civmanager:getCivilian', function(source, civilianId)
    local result = nil
    local completed = false
    
    GetCivilianBySSN(civilianId, function(success, data, statusCode)
        if success and data then
            result = { success = true, civilian = data }
        else
            result = { success = false, error = 'Civilian not found' }
        end
        completed = true
    end)
    
    while not completed do
        Wait(10)
    end
    
    return result
end)

lib.callback.register('cdecad-civmanager:loadLastCivilian', function(source)
    if Config.Persistence ~= 'mysql' then
        return nil
    end
    
    local result = nil
    local completed = false
    
    LoadSelectedCivilian(source, function(civilianId)
        result = civilianId
        completed = true
    end)
    
    while not completed do
        Wait(10)
    end
    
    return result
end)

local vehicleRegCooldowns = {}
lib.callback.register('cdecad-civmanager:registerVehicle', function(source, vehicleData)
    local activeCiv = ActiveCivilians[source]

    if not activeCiv then
        return { success = false, error = 'No civilian selected. Use /setciv first.' }
    end

    local nowT = GetGameTimer()
    if vehicleRegCooldowns[source] and (nowT - vehicleRegCooldowns[source]) < 3000 then
        return { success = false, error = 'Please wait before registering another vehicle.' }
    end
    vehicleRegCooldowns[source] = nowT

    if type(vehicleData) ~= 'table' then
        return { success = false, error = 'Invalid vehicle data.' }
    end
    local function clampStr(v, max)
        if type(v) ~= 'string' then v = tostring(v or '') end
        return v:sub(1, max)
    end
    local cleanVehicle = {
        plate = clampStr(vehicleData.plate, 16),
        make  = clampStr(vehicleData.make, 48),
        model = clampStr(vehicleData.model, 48),
        color = clampStr(vehicleData.color, 32),
        year  = tonumber(vehicleData.year),
    }
    if cleanVehicle.year and (cleanVehicle.year < 1900 or cleanVehicle.year > 2100) then
        cleanVehicle.year = nil
    end
    if cleanVehicle.plate == '' then
        return { success = false, error = 'A plate is required.' }
    end
    vehicleData = cleanVehicle

    local result = nil
    local completed = false

    RegisterVehicle(activeCiv.ssn or activeCiv.id, vehicleData, function(success, data, statusCode)
        if success then
            result = { success = true, vehicle = data }
        else
            result = { success = false, error = 'Failed to register vehicle', statusCode = statusCode }
        end
        completed = true
    end)
    
    while not completed do
        Wait(10)
    end
    
    return result
end)


local function VerifyCivilianOwnership(source, ssn, cb)
    local discordId = GetDiscordId(source)
    if not discordId or not ssn or ssn == '' then
        cb(nil)
        return
    end
    GetCiviliansForDiscord(discordId, function(success, data)
        if not success or type(data) ~= 'table' then
            cb(nil)
            return
        end
        for _, civ in ipairs(data) do
            local cid = civ.ssn or civ._id or civ.id
            if cid and tostring(cid) == tostring(ssn) then
                cb(true)
                return
            end
        end
        cb(false)
    end)
end

RegisterNetEvent('cdecad-civmanager:selectCivilian', function(civilianData)
    local source = source

    if civilianData == nil then
        ActiveCivilians[source] = nil
        Debug('Cleared civilian for source:', source)
        return
    end

    if type(civilianData) ~= 'table' then return end
    local maxKeys = 0
    for _ in pairs(civilianData) do maxKeys = maxKeys + 1 end
    if maxKeys > 40 then return end

    local stored = {}
    for k, v in pairs(civilianData) do
        if type(k) == 'string' and #k < 64 then stored[k] = v end
    end
    if stored.mugshotUrl then
        local url = stored.mugshotUrl
        if #url > 500 or not (string.sub(url, 1, 4) == 'http') then
            stored.mugshotUrl = nil
        end
    end
    if not stored.ssn and (stored.id or stored._id) then
        stored.ssn = tostring(stored.id or stored._id)
    end

    VerifyCivilianOwnership(source, stored.ssn, function(owned)
        if owned == false then
            Debug('Rejected unowned civilian select for source:', source, 'ssn:', stored.ssn)
            TriggerClientEvent('cdecad-civmanager:notify', source, 'error',
                'That civilian is not linked to your account.')
            return
        end

        ActiveCivilians[source] = stored
        Debug('Set civilian for source:', source)
        Debug('  Name:', civilianData.firstName, civilianData.lastName)
        Debug('  SSN:', stored.ssn)

        SaveSelectedCivilian(source, stored.ssn or stored.id)

        TriggerClientEvent('cdecad-civmanager:civilianSet', source, stored)
    end)
end)

local showIDCooldowns = {}
RegisterNetEvent('cdecad-civmanager:showID', function()
    local source = source
    local now = GetGameTimer()
    if showIDCooldowns[source] and (now - showIDCooldowns[source]) < 2000 then return end
    showIDCooldowns[source] = now

    local activeCiv = ActiveCivilians[source]
    if not activeCiv then
        TriggerClientEvent('cdecad-civmanager:notify', source, 'error', 'No civilian selected. Use /setciv first.')
        return
    end

    Debug('ShowID triggered for source:', source, 'Civilian:', activeCiv.firstName, activeCiv.lastName)

    local playerPed = GetPlayerPed(source)
    local playerCoords = GetEntityCoords(playerPed)

    local cardStyle = {
        StateName = 'San Andreas',
        CardTitle = "DRIVER'S LICENSE",
        BackgroundColor = '#1a365d'
    }

    if CommunitySettings and CommunitySettings.jurisdiction then
        if CommunitySettings.jurisdiction.state and CommunitySettings.jurisdiction.state ~= '' then
            cardStyle.StateName = CommunitySettings.jurisdiction.state
        end
    end

    local players = GetPlayers()
    for _, playerId in ipairs(players) do
        local targetId = tonumber(playerId)
        if targetId ~= source then
            local targetPed = GetPlayerPed(targetId)
            local targetCoords = GetEntityCoords(targetPed)
            local distance = #(playerCoords - targetCoords)

            if distance <= Config.IDCard.ShowRange then
                TriggerClientEvent('cdecad-civmanager:receiveID', targetId, activeCiv, GetPlayerName(source), cardStyle)
            end
        end
    end

    TriggerClientEvent('cdecad-civmanager:receiveID', source, activeCiv, 'You', cardStyle)
end)

local requestIDCooldowns = {}

AddEventHandler('playerDropped', function(reason)
    local source = source
    ActiveCivilians[source] = nil
    vehicleRegCooldowns[source] = nil
    requestIDCooldowns[source] = nil
    Debug('Player dropped, cleared civilian for source:', source)
end)


RegisterNetEvent('cdecad-civmanager:showIDToPlayer', function(targetId)
    local source = source
    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 or not GetPlayerName(targetId) then return end

    local activeCiv = ActiveCivilians[source]
    if not activeCiv then
        TriggerClientEvent('cdecad-civmanager:notify', source, 'error', 'No civilian selected.')
        return
    end

    Debug('ShowID to specific player:', targetId, 'from:', source)

    local cardStyle = {
        StateName = 'San Andreas',
        CardTitle = "DRIVER'S LICENSE",
        BackgroundColor = '#1a365d'
    }

    if CommunitySettings and CommunitySettings.jurisdiction then
        if CommunitySettings.jurisdiction.state and CommunitySettings.jurisdiction.state ~= '' then
            cardStyle.StateName = CommunitySettings.jurisdiction.state
        end
    end

    if targetId ~= source then
        TriggerClientEvent('cdecad-civmanager:receiveID', targetId, activeCiv, GetPlayerName(source), cardStyle)
    end
    TriggerClientEvent('cdecad-civmanager:receiveID', source, activeCiv, 'You', cardStyle)
end)

RegisterNetEvent('cdecad-civmanager:requestID', function(targetId)
    local source = source
    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 or not GetPlayerName(targetId) then return end

    local nowT = GetGameTimer()
    if requestIDCooldowns[source] and (nowT - requestIDCooldowns[source]) < 3000 then return end
    requestIDCooldowns[source] = nowT

    Debug('ID requested from player:', targetId, 'by:', source)
    TriggerClientEvent('cdecad-civmanager:idRequested', targetId, source, GetPlayerName(source))
end)


RegisterNetEvent('cdecad-civmanager:updateMugshot', function(civilianId, mugshotBase64)
    local source = source

    if type(civilianId) ~= 'string' or not civilianId:match('^[%w%-_]+$') then return end
    if type(mugshotBase64) ~= 'string' or #mugshotBase64 > 5 * 1024 * 1024 then return end
    if not mugshotBase64:match('^data:image/') then return end

    local active = ActiveCivilians[source]
    local matches = active and (
        tostring(active._id or active.id) == civilianId
        or tostring(active.ssn or '') == civilianId
    )
    if not matches then
        Debug('updateMugshot rejected: civilianId does not match caller\'s active civ', source, civilianId)
        return
    end

    APIRequest('PUT', '/civilian/fivem-update-character/' .. civilianId,
        { mugshotUrl = mugshotBase64, communityId = Config.COMMUNITY_ID },
        function(success, _, statusCode)
            if success then
                print('[CDECAD-CIVMANAGER] Mugshot updated for civilian: ' .. civilianId)
            else
                print('[CDECAD-CIVMANAGER] Mugshot update FAILED for civilian: ' .. civilianId .. ' (HTTP ' .. tostring(statusCode) .. ')')
            end
        end)
end)

lib.callback.register('cdecad-civmanager:getMugshot', function(source, ssn)
    local mugshotUrl = nil
    local completed = false

    APIRequest('GET', '/civilian/fivem-civilian/' .. tostring(ssn) .. '?communityId=' .. Config.COMMUNITY_ID, nil,
        function(success, data, statusCode)
            if success and data then
                mugshotUrl = data.mugshotUrl
            end
            completed = true
        end)

    while not completed do Wait(10) end
    return { mugshotUrl = mugshotUrl }
end)

lib.callback.register('cdecad-civmanager:fetchLicensePng', function(source, civilianId, licenseType)
    if not civilianId or civilianId == '' or not licenseType or licenseType == '' then
        return { ok = false, status = 400 }
    end
    local result = nil
    local completed = false
    local url = Config.API_URL
        .. '/fivem/license-templates/render/' .. tostring(civilianId)
        .. '/' .. tostring(licenseType)

    PerformHttpRequest(url, function(statusCode, body, headers)
        if statusCode >= 200 and statusCode < 300 and body and body ~= '' then
            local ok, decoded = pcall(json.decode, body)
            if ok and decoded and decoded.ok and decoded.dataUri then
                result = { ok = true, dataUri = decoded.dataUri }
            else
                result = { ok = false, status = 500, error = 'bad response' }
            end
        else
            result = { ok = false, status = statusCode }
        end
        completed = true
    end, 'GET', '', {
        ['x-api-key'] = Config.API_KEY,
        ['Accept']    = 'application/json',
    })

    local waited = 0
    while not completed and waited < 10000 do
        Wait(50); waited = waited + 50
    end
    if not completed then return { ok = false, status = 504 } end
    return result
end)


exports('GetActiveCivilian', function(source)
    return ActiveCivilians[source]
end)

exports('HasActiveCivilian', function(source)
    return ActiveCivilians[source] ~= nil
end)

exports('SetActiveCivilianBySSN', function(source, ssn, cb)
    ssn = ssn ~= nil and tostring(ssn) or ''
    if not source or ssn == '' then
        if cb then cb(false, 'invalid args') end
        return false
    end
    local discordId = GetDiscordId(source)
    if not discordId then
        if cb then cb(false, 'no discord id for player') end
        return false
    end
    GetCiviliansForDiscord(discordId, function(success, data)
        if not success or type(data) ~= 'table' then
            if cb then cb(false, 'civilian lookup failed') end
            return
        end
        for _, civ in ipairs(data) do
            local cid = civ.ssn or civ._id or civ.id
            if cid and tostring(cid) == ssn then
                if not civ.ssn and (civ.id or civ._id) then
                    civ.ssn = tostring(civ.id or civ._id)
                end
                ActiveCivilians[source] = civ
                TriggerClientEvent('cdecad-civmanager:notify', source, 'success',
                    ('Active civilian set to %s %s'):format(civ.firstName or '', civ.lastName or ''))
                Debug('Auto-set active civilian for source', source, 'ssn', ssn)
                if cb then cb(true) end
                return
            end
        end
        if cb then cb(false, 'no matching civilian for ssn ' .. ssn) end
    end)
    return true
end)


if Config.Persistence == 'mysql' then
    MySQL.ready(function()
        MySQL.Async.execute([[
            CREATE TABLE IF NOT EXISTS ]] .. Config.MySQLTable .. [[ (
                discord_id VARCHAR(32) PRIMARY KEY,
                civilian_id VARCHAR(64) NOT NULL,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ]], {}, function()
            Debug('MySQL table ready')
        end)
    end)
end


CreateThread(function()
    Wait(2000)
    
    FetchCommunitySettings(function(settings)
        if settings then
            print('[CDECAD-CIVMANAGER] Community settings loaded - State: ' .. (settings.jurisdiction and settings.jurisdiction.state or 'San Andreas'))
        end
    end)
end)

print('[CDECAD-CIVMANAGER] Server script loaded')

end
