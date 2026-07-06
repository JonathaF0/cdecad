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
--[[
    CDECAD Civilian Manager - Server Script
    Handles API calls, persistence, and data management
]]

-- Store active civilians per player (source -> civilian data)
local ActiveCivilians = {}

-- Cache community settings (fetched once on startup)
local CommunitySettings = nil

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

local function Debug(...)
    if Config.Debug then
        print('[CDECAD-CIVMANAGER]', ...)
    end
end

-- Get player's Discord ID
local function GetDiscordId(source)
    local identifiers = GetPlayerIdentifiers(source)
    for _, id in ipairs(identifiers) do
        if string.find(id, 'discord:') then
            return id:gsub('discord:', '')
        end
    end
    return nil
end

-- Get player's license (for KVP key)
local function GetLicense(source)
    local identifiers = GetPlayerIdentifiers(source)
    for _, id in ipairs(identifiers) do
        if string.find(id, 'license:') then
            return id
        end
    end
    return nil
end

-- =============================================================================
-- API FUNCTIONS
-- =============================================================================

-- Make API request to CDECAD
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

-- Get all civilians for a Discord ID
local function GetCiviliansForDiscord(discordId, callback)
    APIRequest('GET', '/civilian/fivem-civilians-by-discord/' .. discordId .. '?communityId=' .. Config.COMMUNITY_ID, nil, callback)
end

-- Get civilian by SSN (citizenid)
local function GetCivilianBySSN(ssn, callback)
    APIRequest('GET', '/civilian/fivem-civilian/' .. ssn .. '?communityId=' .. Config.COMMUNITY_ID, nil, callback)
end

-- Register a vehicle
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

-- Build community settings from local config (no API call needed)
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

-- =============================================================================
-- PERSISTENCE FUNCTIONS
-- =============================================================================

-- Save selected civilian (server-side for MySQL, or tell client for KVP)
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
        -- KVP is handled client-side, just acknowledge
        Debug('KVP persistence handled client-side')
    end
end

-- Load selected civilian from MySQL
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
        -- KVP is handled client-side
        callback(nil)
    end
end

-- =============================================================================
-- CALLBACKS
-- =============================================================================

-- Get community settings
lib.callback.register('cdecad-civmanager:getCommunitySettings', function(source)
    if CommunitySettings then
        return CommunitySettings
    end
    
    -- If not cached yet, fetch synchronously
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

-- Get civilians for player
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

-- Get specific civilian data
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

-- Load last selected civilian (MySQL only)
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

-- Register vehicle
lib.callback.register('cdecad-civmanager:registerVehicle', function(source, vehicleData)
    local activeCiv = ActiveCivilians[source]
    
    if not activeCiv then
        return { success = false, error = 'No civilian selected. Use /setciv first.' }
    end
    
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

-- =============================================================================
-- EVENT HANDLERS
-- =============================================================================

-- Player selects a civilian
RegisterNetEvent('cdecad-civmanager:selectCivilian', function(civilianData)
    local source = source

    if civilianData == nil then
        ActiveCivilians[source] = nil
        Debug('Cleared civilian for source:', source)
        return
    end

    -- Shape check only; ownership is not verified, so treat ActiveCivilians
    -- as untrusted and re-validate before granting privileges.
    if type(civilianData) ~= 'table' then return end
    local maxKeys = 0
    for _ in pairs(civilianData) do maxKeys = maxKeys + 1 end
    if maxKeys > 40 then return end   -- guard against oversized payloads

    local stored = {}
    for k, v in pairs(civilianData) do
        if type(k) == 'string' and #k < 64 then stored[k] = v end
    end
    if stored.mugshotUrl then
        local url = stored.mugshotUrl
        -- Base64 data is very long and never starts with http
        if #url > 500 or not (string.sub(url, 1, 4) == 'http') then
            stored.mugshotUrl = nil
        end
    end
    -- Fall back to the Mongo id when the civilian has no SSN
    if not stored.ssn and (stored.id or stored._id) then
        stored.ssn = tostring(stored.id or stored._id)
    end

    ActiveCivilians[source] = stored
    Debug('Set civilian for source:', source)
    Debug('  Name:', civilianData.firstName, civilianData.lastName)
    Debug('  SSN:', stored.ssn)

    -- Save to persistence
    SaveSelectedCivilian(source, stored.ssn or stored.id)

    -- Confirm back to client
    TriggerClientEvent('cdecad-civmanager:civilianSet', source, stored)
end)

-- Player shows ID to nearby players
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

    -- Sent without the mugshot to stay under FiveM's ~64 KB event limit;
    -- each viewer's NUI fetches the photo separately.
    local playerPed = GetPlayerPed(source)
    local playerCoords = GetEntityCoords(playerPed)

    -- Build style with community settings
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

    -- Find nearby players
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

    -- Also show to the player themselves
    TriggerClientEvent('cdecad-civmanager:receiveID', source, activeCiv, 'You', cardStyle)
end)

-- Player disconnected
AddEventHandler('playerDropped', function(reason)
    local source = source
    ActiveCivilians[source] = nil
    Debug('Player dropped, cleared civilian for source:', source)
end)

-- =============================================================================
-- OX_TARGET EVENTS
-- =============================================================================

-- Show ID to a specific player (from ox_target)
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

    -- Avoid sending the event twice to the same player (e.g. solo testing with ox_target)
    if targetId ~= source then
        TriggerClientEvent('cdecad-civmanager:receiveID', targetId, activeCiv, GetPlayerName(source), cardStyle)
    end
    TriggerClientEvent('cdecad-civmanager:receiveID', source, activeCiv, 'You', cardStyle)
end)

-- Request ID from another player
RegisterNetEvent('cdecad-civmanager:requestID', function(targetId)
    local source = source
    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 or not GetPlayerName(targetId) then return end

    Debug('ID requested from player:', targetId, 'by:', source)
    TriggerClientEvent('cdecad-civmanager:idRequested', targetId, source, GetPlayerName(source))
end)

-- =============================================================================
-- MUGSHOT UPDATE
-- =============================================================================

RegisterNetEvent('cdecad-civmanager:updateMugshot', function(civilianId, mugshotBase64)
    local source = source

    if type(civilianId) ~= 'string' or not civilianId:match('^[%w%-_]+$') then return end
    if type(mugshotBase64) ~= 'string' or #mugshotBase64 > 5 * 1024 * 1024 then return end
    if not mugshotBase64:match('^data:image/') then return end

    -- civilianId may be the active civ's SSN or its Mongo _id/id
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

-- =============================================================================
-- FRAMEWORK CASH HELPERS
-- =============================================================================

-- Returns the player's current cash, or nil if the framework isn't detected.
local function GetPlayerCash(source)
    -- QBCore / QBox
    if GetResourceState('qb-core') == 'started' then
        local ok, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok and QBCore then
            local Player = QBCore.Functions.GetPlayer(source)
            if Player then
                local money = Player.PlayerData.money
                return money and (money.cash or money['cash']) or 0
            end
        end
    end
    -- ESX
    if GetResourceState('es_extended') == 'started' then
        local ok, ESX = pcall(function() return exports['es_extended']:getSharedObject() end)
        if ok and ESX then
            local xPlayer = ESX.GetPlayerFromId(source)
            if xPlayer then return xPlayer.getMoney() or 0 end
        end
    end
    return nil -- no framework; caller decides how to handle
end

-- Removes cash from the player. Returns true on success.
local function RemovePlayerCash(source, amount)
    -- QBCore / QBox
    if GetResourceState('qb-core') == 'started' then
        local ok, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok and QBCore then
            local Player = QBCore.Functions.GetPlayer(source)
            if Player then
                Player.Functions.RemoveMoney('cash', amount, 'bank-deposit')
                return true
            end
        end
    end
    -- ESX
    if GetResourceState('es_extended') == 'started' then
        local ok, ESX = pcall(function() return exports['es_extended']:getSharedObject() end)
        if ok and ESX then
            local xPlayer = ESX.GetPlayerFromId(source)
            if xPlayer then
                xPlayer.removeMoney(amount)
                return true
            end
        end
    end
    return false
end

-- Fetch just the mugshotUrl for a civilian by SSN (NUI fallback)
lib.callback.register('cdecad-civmanager:getMugshot', function(source, ssn)
    local result = nil
    local completed = false

    APIRequest('GET', '/civilian/fivem-civilian/' .. tostring(ssn) .. '?communityId=' .. Config.COMMUNITY_ID, nil,
        function(success, data, statusCode)
            if success and data then
                result = data.mugshotUrl
            end
            completed = true
        end)

    while not completed do Wait(10) end
    return result
end)

-- Fetch a server-rendered license PNG. The CAD endpoint returns JSON
-- `{ ok, dataUri }` with the PNG already base64-encoded, so this proxy
-- never handles raw binary; the JSON is forwarded to the NUI as-is.
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

    -- Bounded wait so a stalled HTTP response doesn't pin the thread
    local waited = 0
    while not completed and waited < 10000 do
        Wait(50); waited = waited + 50
    end
    if not completed then return { ok = false, status = 504 } end
    return result
end)

-- =============================================================================
-- BANKING CALLBACKS
-- =============================================================================

-- Get bank account for a civilian
lib.callback.register('cdecad-civmanager:getBankAccount', function(source, civilianId)
    local result = nil
    local completed = false

    APIRequest('GET', '/banking/fivem/account?civilianId=' .. civilianId .. '&communityId=' .. Config.COMMUNITY_ID, nil, function(success, data, statusCode)
        if success and data then
            result = { success = true, account = data }
        else
            result = { success = false, error = 'Failed to load bank account', statusCode = statusCode }
        end
        completed = true
    end)

    while not completed do Wait(10) end
    return result
end)

-- Deposit
lib.callback.register('cdecad-civmanager:bankDeposit', function(source, civilianId, amount, description)
    -- Server-side cash validation (framework-aware)
    local playerCash = GetPlayerCash(source)
    if playerCash ~= nil and amount > playerCash then
        return { success = false, error = string.format('Insufficient cash. You have $%.2f available.', playerCash) }
    end

    local payload = {
        civilianId = civilianId,
        amount = amount,
        description = description,
        communityId = Config.COMMUNITY_ID
    }

    local result = nil
    local completed = false

    APIRequest('POST', '/banking/fivem/deposit', payload, function(success, data, statusCode)
        if success and data then
            -- Remove cash from player after successful bank deposit
            RemovePlayerCash(source, amount)
            result = { success = true, balance = data.balance, transaction = data.transaction }
        else
            result = { success = false, error = (data and data.error) or 'Deposit failed' }
        end
        completed = true
    end)

    while not completed do Wait(10) end
    return result
end)

-- Withdraw
lib.callback.register('cdecad-civmanager:bankWithdraw', function(source, civilianId, amount, description)
    local payload = {
        civilianId = civilianId,
        amount = amount,
        description = description,
        communityId = Config.COMMUNITY_ID
    }

    local result = nil
    local completed = false

    APIRequest('POST', '/banking/fivem/withdraw', payload, function(success, data, statusCode)
        if success and data then
            result = { success = true, balance = data.balance, transaction = data.transaction }
        else
            result = { success = false, error = (data and data.error) or 'Withdrawal failed' }
        end
        completed = true
    end)

    while not completed do Wait(10) end
    return result
end)

-- Synchronous JSON POST with the caller's Discord ID injected; shared by
-- all banker-write endpoints.
local function bankerPost(source, endpoint, payload)
    local discordId = GetDiscordId(source)
    if not discordId then
        return { success = false, error = 'Discord identifier required for bank-employee access' }
    end
    payload = payload or {}
    payload.discordId = discordId
    payload.communityId = Config.COMMUNITY_ID

    local result = nil
    local completed = false
    APIRequest('POST', endpoint, payload, function(success, data, statusCode)
        if success and data then
            result = data
            result.success = true
        else
            result = { success = false, error = (data and data.error) or 'Request failed' }
        end
        completed = true
    end)
    while not completed do Wait(10) end
    return result
end

-- Admin bank access; the CAD checks bank-employee roles by Discord ID
lib.callback.register('cdecad-civmanager:adminBankAccess', function(source)
    return bankerPost(source, '/banking/fivem/admin-access', {})
end)

-- Banker - load a single account
lib.callback.register('cdecad-civmanager:bankerLoadAccount', function(source, accountId)
    return bankerPost(source, '/banking/fivem/admin-account', { accountId = accountId })
end)

-- Banker - approve / deny a pending loan
lib.callback.register('cdecad-civmanager:bankerLoanDecision', function(source, accountId, loanId, decision, reason)
    return bankerPost(source, '/banking/fivem/admin-loan-decision', {
        accountId = accountId, loanId = loanId, decision = decision, reason = reason
    })
end)

-- Banker - freeze / unfreeze / close
lib.callback.register('cdecad-civmanager:bankerSetStatus', function(source, accountId, status)
    return bankerPost(source, '/banking/fivem/admin-freeze', {
        accountId = accountId, status = status
    })
end)

-- Banker - deposit / withdraw / transfer on behalf of a customer
lib.callback.register('cdecad-civmanager:bankerAdjust', function(source, accountId, action, amount, description, recipientAccountNumber)
    return bankerPost(source, '/banking/fivem/admin-adjust', {
        accountId = accountId,
        action = action,
        amount = amount,
        description = description,
        recipientAccountNumber = recipientAccountNumber
    })
end)

-- Transfer
lib.callback.register('cdecad-civmanager:bankTransfer', function(source, fromCivilianId, toAccountNumber, amount, description)
    local payload = {
        fromCivilianId = fromCivilianId,
        toAccountNumber = toAccountNumber,
        amount = amount,
        description = description,
        communityId = Config.COMMUNITY_ID
    }

    local result = nil
    local completed = false

    APIRequest('POST', '/banking/fivem/transfer', payload, function(success, data, statusCode)
        if success and data then
            result = { success = true, balance = data.senderBalance, transaction = data.transaction }
        else
            result = { success = false, error = (data and data.error) or 'Transfer failed' }
        end
        completed = true
    end)

    while not completed do Wait(10) end
    return result
end)

-- =============================================================================
-- EXPORTS
-- =============================================================================

-- Get a player's active civilian
exports('GetActiveCivilian', function(source)
    return ActiveCivilians[source]
end)

-- Check if player has a civilian selected
exports('HasActiveCivilian', function(source)
    return ActiveCivilians[source] ~= nil
end)

-- =============================================================================
-- MYSQL SETUP (if using MySQL persistence)
-- =============================================================================

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

-- =============================================================================
-- STARTUP
-- =============================================================================

CreateThread(function()
    Wait(2000)
    
    -- Fetch community settings on startup
    FetchCommunitySettings(function(settings)
        if settings then
            print('[CDECAD-CIVMANAGER] Community settings loaded - State: ' .. (settings.jurisdiction and settings.jurisdiction.state or 'San Andreas'))
        end
    end)
end)

print('[CDECAD-CIVMANAGER] Server script loaded')

end
