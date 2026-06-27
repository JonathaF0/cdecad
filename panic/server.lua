do
    local Config = PanicConfig

    Config.CadUrl      = GetConvar('CDE_CAD_API_URL', '')
    Config.ApiKey      = GetConvar('CDE_CAD_API_KEY', '')
    Config.ServerName  = GetConvar('CDE_CAD_SERVER_NAME', 'My Server')
    Config.CommunityID = GetConvar('CDE_CAD_COMMUNITY_ID', '')
local cooldowns = {}  -- { [serverId] = timestamp }
local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64Encode(data)
    return ((data:gsub('.', function(x)
        local r, b = '', x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2^i - b % 2^(i-1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i,i) == '1' and 2^(6-i) or 0) end
        return b64chars:sub(c+1, c+1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

local function CadRequest(endpoint, payload, cb)
    local url  = Config.CadUrl .. '/api/fivem/' .. endpoint
    local body = json.encode(payload)

    if Config.Debug then
        print(('[cdecad-panic] POST /%s → %s'):format(endpoint, body))
    end

    PerformHttpRequest(url, function(statusCode, response, headers)
        local ok, data = pcall(json.decode, response or '')
        if cb then
            cb(statusCode, ok and data or nil)
        end

        if statusCode >= 400 then
            print(('[cdecad-panic] API error %d on /%s: %s'):format(
                statusCode, endpoint, response or 'no body'
            ))
        elseif Config.Debug then
            print(('[cdecad-panic] /%s → %d OK'):format(endpoint, statusCode))
        end
    end, 'POST', body, {
        ['Content-Type'] = 'application/json',
        ['x-api-key']    = Config.ApiKey,
        ['x-payload']    = base64Encode(body),
    })
end

local function GetPlayerNameSafe(src)
    return GetPlayerName(src) or ('Player ' .. src)
end
  
local function IsOnDutyLEO(src)
    local ok, res = pcall(function()
        return exports['CDECAD']:IsPlayerOnDutyLEO(src)
    end)
    if ok and res ~= nil then
        return res and true or false
    end
    return true
end

--- Returns the list of server IDs that should receive the panic alert.
--- When BroadcastToLEOOnly is on, only on-duty LEOs are notified; otherwise
--- everyone (nil => -1) receives it.
local function GetPanicRecipients()
    if Config.BroadcastToLEOOnly then
        local ok, units = pcall(function()
            return exports['CDECAD']:GetOnDutyLEOUnits()
        end)
        if ok and type(units) == 'table' then
            return units
        end
    end
    return nil
end

-- ─── Panic Event from Client ────────────────────────────────────

RegisterNetEvent('cdecad-panic:activate')
AddEventHandler('cdecad-panic:activate', function(data)
    local src = source
    local now = os.time()
    data = data or {} 
    if Config.RequireOnDutyLEO and not IsOnDutyLEO(src) then
        if Config.Debug then
            print(('[cdecad-panic] Rejected panic from %s [%d]: not an on-duty LEO'):format(
                GetPlayerNameSafe(src), src))
        end
        return
    end

    -- Server-side cooldown enforcement (prevents spam exploits)
    if cooldowns[src] and (now - cooldowns[src]) < Config.CooldownSeconds then
        return
    end
    cooldowns[src] = now

    local playerName = GetPlayerNameSafe(src)
    local street     = data.street or 'Unknown'
    local postal     = data.postal or ''
    local coords     = data.coords or { x = 0, y = 0, z = 0 }
    local location   = street
    if postal ~= '' then
        location = street .. ' (Postal: ' .. postal .. ')'
    end

    print(('[cdecad-panic] PANIC activated by %s [%d] at %s'):format(playerName, src, location))
    local payload = {
        serverId = src,
        name     = playerName,
        coords   = coords,
        street   = street,
        postal   = postal,
        expires  = Config.BlipDurationSeconds,
    }

    local recipients = GetPanicRecipients()
    if recipients then
        for _, targetId in ipairs(recipients) do
            TriggerClientEvent('cdecad-panic:broadcast', targetId, payload)
        end
    else
        TriggerClientEvent('cdecad-panic:broadcast', -1, payload)
    end

    -- 2. Send panic to CAD
    CadRequest('panic', {
        officerName = playerName,
        officerId   = GetPlayerIdentifierByType(src, 'license') or nil,
        location    = location,
        postal      = postal,
        coordinates = coords,
        serverName  = Config.ServerName,
        communityId = Config.CommunityID ~= '' and Config.CommunityID or nil,
    })

    -- 3. Auto-generate 911 call in CAD
    if Config.Auto911 then
        local description = ('PANIC BUTTON activated by %s at %s'):format(playerName, location)

        CadRequest('911', {
            callType    = Config.Auto911CallType,
            location    = location,
            postal      = postal,
            coordinates = coords,
            callerName  = Config.Auto911Caller,
            serverName  = Config.ServerName,
            description = description,
            communityId = Config.CommunityID ~= '' and Config.CommunityID or nil,
        }, function(status, res)
            if status == 201 and res and res.incidentNumber then
                print(('[cdecad-panic] 911 call created: %s'):format(res.incidentNumber))
            end
        end)
    end
end)

-- ─── Cleanup on Player Drop ─────────────────────────────────────

AddEventHandler('playerDropped', function()
    cooldowns[source] = nil
end)

end
