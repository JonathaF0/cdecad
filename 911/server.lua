do
    local Config = Cad911Config

    Config.CadUrl = GetConvar('CDE_CAD_API_URL', '')
    Config.ApiKey = GetConvar('CDE_CAD_API_KEY', '')
-- ═══════════════════════════════════════════════════════════════════
-- SERVER-SIDE 911 CALLS
-- Receives call data from client and sends to CAD backend
-- ═══════════════════════════════════════════════════════════════════

local cooldowns = {}  -- { [serverId] = timestamp }

-- ─── Helpers ────────────────────────────────────────────────────

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

local function DebugLog(msg)
    if Config.Debug then
        print('[cad-911] ' .. tostring(msg))
    end
end

local function CadRequest(endpoint, payload, cb)
    local url  = Config.CadUrl .. '/api/fivem/' .. endpoint
    local body = json.encode(payload)

    DebugLog(('POST /%s → %s'):format(endpoint, body))

    PerformHttpRequest(url, function(statusCode, response, headers)
        local ok, data = pcall(json.decode, response or '')
        if cb then
            cb(statusCode, ok and data or nil)
        end

        if statusCode >= 400 then
            print(('[cad-911] API error %d on /%s: %s'):format(
                statusCode, endpoint, response or 'no body'
            ))
        elseif Config.Debug then
            DebugLog(('/%s → %d OK'):format(endpoint, statusCode))
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

-- Caller's phone number: lb-phone when running, otherwise the active CAD
-- civilian's registered number. nil when neither is available.
local function GetCallerPhone(src)
    if Config.LbPhone == false then return nil end
    if GetResourceState('lb-phone') == 'started' then
        local ok, num = pcall(function()
            return exports['lb-phone']:GetEquippedPhoneNumber(src)
        end)
        if ok and type(num) == 'string' and num ~= '' then return num end
    end
    local ok, civ = pcall(function()
        return exports[GetCurrentResourceName()]:GetActiveCivilian(src)
    end)
    if ok and type(civ) == 'table' then
        local phone = civ.phone or civ.secondaryPhone
        if type(phone) == 'string' and phone ~= '' then return phone end
    end
    return nil
end

-- ─── 911 Call Event ─────────────────────────────────────────────

RegisterNetEvent('cad-911:call')
AddEventHandler('cad-911:call', function(data)
    local src = source
    local now = os.time()

    -- Server-side cooldown enforcement
    if cooldowns[src] and (now - cooldowns[src]) < Config.CooldownSeconds then
        DebugLog(('Cooldown active for player %d, ignoring'):format(src))
        return
    end
    cooldowns[src] = now

    if not data or not data.message or data.message == '' then
        return
    end

    local playerName = GetPlayerNameSafe(src)
    local callerName = data.anon and Config.AnonCallerName or playerName
    local location   = data.location or 'Unknown'
    local postal     = data.postal or ''
    local coords     = data.coords or { x = 0, y = 0, z = 0 }

    print(('[cad-911] %s call from %s [%d]: %s | Location: %s'):format(
        data.anon and 'Anonymous' or '911',
        playerName, src, data.message, location
    ))

    CadRequest('911', {
        callType    = Config.DefaultCallType,
        callerName  = callerName,
        callerNumber = (not data.anon) and GetCallerPhone(src) or nil,
        location    = location,
        postal      = postal,
        coordinates = coords,
        description = data.message,
        priority    = Config.DefaultPriority,
        source      = 'player',
    }, function(status, res)
        if status == 201 and res and res.incidentNumber then
            print(('[cad-911] Call created: %s'):format(res.incidentNumber))
        end
    end)
end)

-- ─── NPC witness reports ───────────────────────────────────────

local npcCooldowns = {}  -- per (reportType, 100m grid cell) → timestamp

RegisterNetEvent('cad-911:npc')
AddEventHandler('cad-911:npc', function(data)
    if not data or type(data) ~= 'table' or not data.reportType or not data.callType then return end
    if not data.coords or not data.coords.x or not data.coords.y then return end

    -- Rate-limit per area+type so a single trigger doesn't spam the CAD.
    local key = string.format('%s:%d:%d',
        data.reportType,
        math.floor((data.coords.x or 0) / 100),
        math.floor((data.coords.y or 0) / 100))
    local now = os.time()
    local cd  = 60
    if npcCooldowns[key] and (now - npcCooldowns[key]) < cd then return end
    npcCooldowns[key] = now

    CadRequest('911', {
        callType    = data.callType,
        callerName  = 'Anonymous Witness',
        location    = data.location or 'Unknown',
        postal      = data.postal,
        coordinates = data.coords,
        description = data.metadata
            and ('Plate ' .. tostring(data.metadata.plate or '?') ..
                 ' @ ' .. tostring(data.metadata.speed or '?') .. ' mph')
            or nil,
        priority    = 'normal',
        source      = 'npc',
    }, function(status)
        DebugLog(('NPC %s → %s'):format(data.reportType, tostring(status)))
    end)
end)

-- ─── Cleanup on Player Drop ────────────────────────────────────

AddEventHandler('playerDropped', function()
    cooldowns[source] = nil
end)

-- ─── Startup configuration check ───────────────────────────────
AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if not Config.ApiKey or Config.ApiKey == '' then
        print('^1[cad-911] Config.ApiKey is empty - /911 calls will fail with 401. Set it in config.lua.^7')
    end
    if not Config.CadUrl or Config.CadUrl == '' then
        print('^1[cad-911] Config.CadUrl is empty - /911 will not be able to reach the CAD.^7')
    end
end)

end
