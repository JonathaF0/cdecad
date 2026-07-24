
local Config = CivConfig or {}

local API_URL do
    local baseUrl = GetConvar('CDE_CAD_API_URL', '')
    if baseUrl ~= '' and not baseUrl:find('/api$') then
        API_URL = baseUrl:gsub('/$', '') .. '/api'
    else
        API_URL = baseUrl:gsub('/$', '')
    end
end
local API_KEY      = GetConvar('CDE_CAD_API_KEY', '')
local COMMUNITY_ID = GetConvar('CDE_CAD_COMMUNITY_ID', '')

local function FpConfig()
    return Config.Fingerprint or {}
end

local function InDutyList(list, src)
    if type(list) ~= 'table' then return false end
    for i = 1, #list do
        if list[i] == src then return true end
    end
    return false
end

local scanCooldown = {}

RegisterNetEvent('cdecad-fingerprint:scan', function(targetId)
    local src = source
    local fpc = FpConfig()
    if not fpc.Enabled then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 or not GetPlayerName(targetId) then
        TriggerClientEvent('cdecad-fingerprint:notify', src, 'error', 'Subject not found')
        return
    end

    local now = os.time()
    if scanCooldown[src] and (now - scanCooldown[src]) < 3 then return end
    scanCooldown[src] = now

    if fpc.RequireLEO then
        if not InDutyList(OnDutyLEOUnits, src) then
            TriggerClientEvent('cdecad-fingerprint:notify', src, 'error', 'You must be on duty as LEO to scan prints')
            return
        end
    else
        if not InDutyList(OnDutyUnits, src) then
            TriggerClientEvent('cdecad-fingerprint:notify', src, 'error', 'You must be on duty to scan prints')
            return
        end
    end

    local myPed, targetPed = GetPlayerPed(src), GetPlayerPed(targetId)
    if myPed == 0 or targetPed == 0 then return end
    local dist = #(GetEntityCoords(myPed) - GetEntityCoords(targetPed))
    if dist > (fpc.Range or 2.5) + 2.0 then
        TriggerClientEvent('cdecad-fingerprint:notify', src, 'error', 'Subject is too far away')
        return
    end

    local activeCiv = (CDECAD_GetActiveCivilian and CDECAD_GetActiveCivilian(targetId)) or nil
    local civId = activeCiv and tostring(activeCiv._id or activeCiv.id or activeCiv.ssn or '') or ''
    if civId == '' then
        TriggerClientEvent('cdecad-fingerprint:notify', src, 'error', 'No readable prints - subject has no civilian selected')
        return
    end

    local url = API_URL .. '/civilian/fivem-fingerprint/' .. civId .. '?communityId=' .. COMMUNITY_ID
    PerformHttpRequest(url, function(statusCode, responseText)
        if statusCode < 200 or statusCode >= 300 or not responseText or responseText == '' then
            TriggerClientEvent('cdecad-fingerprint:notify', src, 'error', 'Print scan failed (CAD error ' .. tostring(statusCode) .. ')')
            return
        end
        local ok, data = pcall(json.decode, responseText)
        if not ok or type(data) ~= 'table' or not data.image then
            TriggerClientEvent('cdecad-fingerprint:notify', src, 'error', 'Print scan failed (bad response)')
            return
        end

        TriggerClientEvent('cdecad-fingerprint:result', src, {
            name          = data.name or 'Unknown',
            fingerprintId = data.fingerprintId or '',
            pattern       = data.pattern or '',
            image         = data.image,
            wanted        = data.wanted == true,
            missing       = data.missing == true,
        })

        if fpc.NotifySubject and targetId ~= src then
            TriggerClientEvent('cdecad-fingerprint:notify', targetId, 'inform',
                'Your fingerprints were scanned by ' .. (GetPlayerName(src) or 'an officer'))
        end
    end, 'GET', '', { ['x-api-key'] = API_KEY })
end)

AddEventHandler('playerDropped', function()
    scanCooldown[source] = nil
end)

print('[CDECAD-FINGERPRINT] Server script loaded')
