do
    local Config = TabletConfig

    Config.APIKey      = GetConvar('CDE_CAD_API_KEY', '')
    Config.CADEndpoint = GetConvar('CDE_CAD_API_URL', '')
    if Config.APIKey == '' or Config.CADEndpoint == '' then
        print('^1[CDECAD/TABLET] CDE_CAD_API_KEY / CDE_CAD_API_URL convar not set.^0')
    end
-- server/main.lua
-- CAD Tablet Server — Fetches assigned calls from CAD API for the popup
-- and (optionally) pushes player locations for the CAD livemap.

local function debugLog(msg)
    if Config.EnableDebug then
        print("^5[CAD-TABLET-SV] " .. msg .. "^0")
    end
end

-- ─── Build API URL ───────────────────────────────────────────────────────────
local function apiUrl(path)
    local base = Config.CADEndpoint
    if base:sub(-1) == '/' then base = base:sub(1, -2) end
    return base .. path
end

local function getDiscordId(src)
    if not src or src <= 0 then return nil end
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'discord:' then return id:sub(9) end
    end
    return nil
end

-- ─── Fetch assigned calls for a player ───────────────────────────────────────
RegisterNetEvent('cad-tablet:requestCalls')
AddEventHandler('cad-tablet:requestCalls', function()
    local src = source
    if not src or src <= 0 then return end

    local discordId = getDiscordId(src)

    if not discordId then
        debugLog("No Discord identifier for player " .. src)
        TriggerClientEvent('cad-tablet:receiveCalls', src, {})
        return
    end

    local url = apiUrl('/api/fivem/unit-calls?discordId=' .. discordId)

    PerformHttpRequest(url, function(statusCode, body, headers)
        if statusCode ~= 200 then
            debugLog("API error " .. tostring(statusCode) .. ": " .. tostring(body))
            TriggerClientEvent('cad-tablet:receiveCalls', src, {})
            return
        end

        local ok, data = pcall(json.decode, body)
        if not ok or not data or not data.success then
            debugLog("Failed to parse response")
            TriggerClientEvent('cad-tablet:receiveCalls', src, {})
            return
        end

        TriggerClientEvent('cad-tablet:receiveCalls', src, data.calls or {})
    end, 'GET', '', {
        ['Content-Type']  = 'application/json',
        ['x-api-key']     = Config.APIKey,
    })
end)

-- ─── Optional: Location Tracking ─────────────────────────────────────────────
-- Mirrors what cde_lm does. Pushes the player's coords + status to the CAD
-- livemap. Only used when Config.LocationTracking.Enabled = true.

local function postJSON(url, payload, onDone)
    PerformHttpRequest(url, function(statusCode, body, headers)
        if onDone then onDone(statusCode, body) end
    end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json',
        ['x-api-key']    = Config.APIKey,
    })
end

-- Client asks "am I active in the CAD?" — relay to backend, push result back.
RegisterNetEvent('cad-tablet:checkCADActive')
AddEventHandler('cad-tablet:checkCADActive', function()
    local src = source
    local discordId = getDiscordId(src)
    if not discordId then return end

    PerformHttpRequest(apiUrl('/api/fivem/unit-active?discordId=' .. discordId),
        function(statusCode, body)
            if statusCode ~= 200 then
                debugLog("unit-active error " .. tostring(statusCode))
                return
            end
            local ok, data = pcall(json.decode, body)
            if not ok or not data or not data.success then return end

            TriggerClientEvent('cad-tablet:cadActiveResult', src, {
                active     = data.active == true,
                status     = data.status,
                department = data.department,
                callSign   = data.callSign,
            })
        end, 'GET', '', {
            ['Content-Type'] = 'application/json',
            ['x-api-key']    = Config.APIKey,
        })
end)

-- Client pushes raw GTA coords; we forward to /api/dispatch/location-update
-- with the community API key. Backend resolves the community from the key.
RegisterNetEvent('cad-tablet:pushLocation')
AddEventHandler('cad-tablet:pushLocation', function(payload)
    local src = source
    local discordId = getDiscordId(src)
    if not discordId or type(payload) ~= 'table' then return end

    local body = {
        unitId   = discordId,
        unitName = GetPlayerName(src) or ('Unit-' .. tostring(src)),
        x        = tonumber(payload.x),
        y        = tonumber(payload.y),
        z        = tonumber(payload.z) or 0,
        heading  = tonumber(payload.heading) or 0,
        status   = payload.status or 'In Service',
        job      = payload.department,
        postal   = payload.postal or 'Unknown',
        apiKey   = Config.APIKey,
    }

    if not body.x or not body.y then return end

    postJSON(apiUrl('/api/dispatch/location-update'), body, function(statusCode)
        if statusCode ~= 200 then
            debugLog("location-update failed " .. tostring(statusCode))
        end
    end)
end)

-- Mark player offline on the livemap. Used on resource stop, drop, or off-duty.
local function sendOffline(src, discordId, name)
    if not discordId then return end
    postJSON(apiUrl('/api/dispatch/location-update'), {
        unitId   = discordId,
        unitName = name or GetPlayerName(src) or ('Unit-' .. tostring(src or 0)),
        status   = 'offline',
        apiKey   = Config.APIKey,
    })
end

RegisterNetEvent('cad-tablet:sendOffline')
AddEventHandler('cad-tablet:sendOffline', function()
    local src = source
    sendOffline(src, getDiscordId(src), GetPlayerName(src))
end)

-- Catch the client-disconnect case (the client thread can't run on drop).
AddEventHandler('playerDropped', function(reason)
    if not Config.LocationTracking
       or not Config.LocationTracking.Enabled
       or not Config.LocationTracking.SendOfflineOnDisconnect then return end
    local src = source
    sendOffline(src, getDiscordId(src), GetPlayerName(src))
end)

-- ─── Init ────────────────────────────────────────────────────────────────────
AddEventHandler('onResourceStart', function(res)
    if GetCurrentResourceName() ~= res then return end
    print("^2[CAD-TABLET] Server initialized^0")
    if Config.LocationTracking and Config.LocationTracking.Enabled then
        print("^2[CAD-TABLET] Location tracking ENABLED — DutySource=" ..
              tostring(Config.LocationTracking.DutySource) ..
              ", Interval=" .. tostring(Config.LocationTracking.Interval) .. "ms^0")
    end
end)

end
