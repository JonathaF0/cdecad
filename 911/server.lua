do
    local Config = Cad911Config

    Config.CadUrl = GetConvar('CDE_CAD_API_URL', ''):gsub('/$', ''):gsub('/[Aa][Pp][Ii]$', '')
    Config.ApiKey = GetConvar('CDE_CAD_API_KEY', '')

local cooldowns = {}


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

local function NotifyOnDutyUnits(callData)
    if Config.NotifyOnDuty == false then return end
    TriggerEvent('cad:forward911ToUnits', callData)
end

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


RegisterNetEvent('cad-911:call')
AddEventHandler('cad-911:call', function(data)
    local src = source
    local now = os.time()

    if cooldowns[src] and (now - cooldowns[src]) < Config.CooldownSeconds then
        DebugLog(('Cooldown active for player %d, ignoring'):format(src))
        return
    end

    if not data or type(data) ~= 'table' or type(data.message) ~= 'string' or data.message == '' then
        return
    end

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


local npcCooldowns = {}
local npcPlayerCooldowns = {}

RegisterNetEvent('cad-911:npc')
AddEventHandler('cad-911:npc', function(data)
    local src = source
    if not data or type(data) ~= 'table' or not data.reportType or not data.callType then return end
    local cxRaw, cyRaw = tonumber(data.coords and data.coords.x), tonumber(data.coords and data.coords.y)
    if not cxRaw or not cyRaw or cxRaw ~= cxRaw or cyRaw ~= cyRaw
       or math.abs(cxRaw) > 1e7 or math.abs(cyRaw) > 1e7 then return end

    local now = os.time()

    if npcPlayerCooldowns[src] and (now - npcPlayerCooldowns[src]) < 10 then return end
    npcPlayerCooldowns[src] = now

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


AddEventHandler('playerDropped', function()
    cooldowns[source] = nil
    npcPlayerCooldowns[source] = nil
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(600000)
        local cutoff = os.time() - 120
        for k, ts in pairs(npcCooldowns) do
            if ts < cutoff then npcCooldowns[k] = nil end
        end
    end
end)

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
