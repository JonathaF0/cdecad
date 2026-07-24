do
    local Config = Cad911Config

    -- Normalize like the civ/duty/alpr modules: strip a trailing slash (→ '//api',
    -- which Express won't collapse, 404) and a trailing '/api' (some owners set
    -- the convar that way; we append the full '/api/...' path ourselves).
    Config.CadUrl = GetConvar('CDE_CAD_API_URL', ''):gsub('/$', ''):gsub('/[Aa][Pp][Ii]$', '')
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

-- In-game notify: hand the call to the duty module, which pushes it to every
-- on-duty LEO/Fire unit (chat + notification + sound + auto GPS route via
-- CDE:Receive911). Same-resource server event, so this is a direct handoff.
-- The legacy standalone pair (cde-duty-cad-911 → CDE_Duty) did this; the
-- unified bundle only sent calls to the CAD, so in-game 911 alerts were
-- silently lost. Fired independent of the CAD HTTP result on purpose:
-- officers should still hear the call even if the CAD is briefly down.
local function NotifyOnDutyUnits(callData)
    if Config.NotifyOnDuty == false then return end
    TriggerEvent('cad:forward911ToUnits', callData)
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

    if not data or type(data) ~= 'table' or type(data.message) ~= 'string' or data.message == '' then
        return
    end

    -- Only start the cooldown once we know this is a real call - an empty /
    -- malformed payload shouldn't burn the caller's window.
    cooldowns[src] = now

    local playerName = GetPlayerNameSafe(src)
    local callerName = data.anon and Config.AnonCallerName or playerName
    local location   = data.location or 'Unknown'
    local postal     = data.postal or ''
    local coords     = data.coords or { x = 0, y = 0, z = 0 }

    print(('[cad-911] %s call from %s [%d]: %s | Location: %s'):format(
        data.anon and 'Anonymous' or '911',
        playerName, src, data.message, location
    ))

    NotifyOnDutyUnits({
        description = data.message,
        message     = data.message,
        location    = location,
        coords      = coords,
        caller      = callerName,
        isAnonymous = data.anon == true,
        isNPC       = false,
    })

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
local npcPlayerCooldowns = {}  -- per source → timestamp (anti-spam floor)

RegisterNetEvent('cad-911:npc')
AddEventHandler('cad-911:npc', function(data)
    local src = source
    if not data or type(data) ~= 'table' or not data.reportType or not data.callType then return end
    -- Coords must be finite numbers. The grid-cell key below does
    -- string.format('%d', math.floor(x/100)); a non-number, NaN, or inf makes
    -- %d raise "number has no integer representation" and aborts the handler,
    -- and a forged huge coord is meaningless anyway. Reject up front.
    local cxRaw, cyRaw = tonumber(data.coords and data.coords.x), tonumber(data.coords and data.coords.y)
    if not cxRaw or not cyRaw or cxRaw ~= cxRaw or cyRaw ~= cyRaw
       or math.abs(cxRaw) > 1e7 or math.abs(cyRaw) > 1e7 then return end

    local now = os.time()

    -- Per-PLAYER floor: the grid+type key alone is forgeable (a modded client
    -- varying reportType or coords makes every call a fresh key, so the 60s
    -- area cooldown never bites). This hard per-source throttle bounds how
    -- often ANY one client can drive NPC reports regardless of key.
    if npcPlayerCooldowns[src] and (now - npcPlayerCooldowns[src]) < 10 then return end
    npcPlayerCooldowns[src] = now

    -- Rate-limit per area+type so a single trigger doesn't spam the CAD.
    local key = string.format('%s:%d:%d',
        tostring(data.reportType),
        math.floor(cxRaw / 100),
        math.floor(cyRaw / 100))
    local cd  = 60
    if npcCooldowns[key] and (now - npcCooldowns[key]) < cd then return end
    npcCooldowns[key] = now

    local npcDescription = data.metadata and type(data.metadata) == 'table'
        and ('Plate ' .. tostring(data.metadata.plate or '?') ..
             ' @ ' .. tostring(data.metadata.speed or '?') .. ' mph')
        or nil

    NotifyOnDutyUnits({
        description = npcDescription or (data.callType or 'Witness report'),
        location    = data.location or 'Unknown',
        coords      = data.coords,
        caller      = 'Anonymous Witness',
        reportType  = data.reportType,
        isNPC       = true,
    })

    CadRequest('911', {
        callType    = data.callType,
        callerName  = 'Anonymous Witness',
        location    = data.location or 'Unknown',
        postal      = data.postal,
        coordinates = data.coords,
        description = npcDescription,
        priority    = 'normal',
        source      = 'npc',
    }, function(status)
        DebugLog(('NPC %s → %s'):format(data.reportType, tostring(status)))
    end)
end)

-- ─── Cleanup on Player Drop ────────────────────────────────────

AddEventHandler('playerDropped', function()
    cooldowns[source] = nil
    npcPlayerCooldowns[source] = nil
end)

-- npcCooldowns is keyed by area+type, not by player, so it can't be pruned on
-- drop. Sweep entries older than the cooldown window periodically so a server
-- that runs for weeks (or gets fed forged keys) doesn't grow the table without
-- bound.
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(600000) -- every 10 min
        local cutoff = os.time() - 120
        for k, ts in pairs(npcCooldowns) do
            if ts < cutoff then npcCooldowns[k] = nil end
        end
    end
end)

-- ─── Startup configuration check ───────────────────────────────
-- Warn loudly if the resource starts without an API key. The most common
-- "/911 doesn't work" cause is leaving Config.ApiKey blank.
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
