
local Config = CivConfig or {}

local scanning = false
local hideToken = 0

local function FpConfig()
    return Config.Fingerprint or {}
end

local function Notify(kind, message)
    if lib and lib.notify then
        lib.notify({ title = 'Fingerprint', description = message, type = kind })
    else
        TriggerEvent('chat:addMessage', { args = { '^3[Fingerprint]^0 ' .. message } })
    end
end

local function HideCard()
    hideToken = hideToken + 1
    SendNUIMessage({ action = 'hideFingerprint' })
end

local function ScanTarget(targetServerId)
    if scanning then return end
    if not targetServerId or targetServerId <= 0 then
        Notify('error', 'Could not identify the subject')
        return
    end

    HideCard()

    scanning = true
    local completed = true
    if lib and lib.progressCircle then
        completed = lib.progressCircle({
            duration = FpConfig().ScanDuration or 2500,
            label = 'Scanning fingerprint...',
            useWhileDead = false,
            canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = { dict = 'mp_common', clip = 'givetake1_a' },
        })
    else
        Wait(FpConfig().ScanDuration or 2500)
    end
    scanning = false
    if not completed then return end

    TriggerServerEvent('cdecad-fingerprint:scan', targetServerId)
end

RegisterNetEvent('cdecad-fingerprint:result', function(payload)
    if type(payload) ~= 'table' then return end
    SendNUIMessage({ action = 'showFingerprint', data = payload })
    hideToken = hideToken + 1
    local token = hideToken
    SetTimeout(FpConfig().DisplayDuration or 20000, function()
        if hideToken == token then
            SendNUIMessage({ action = 'hideFingerprint' })
        end
    end)
end)

RegisterNetEvent('cdecad-fingerprint:notify', function(kind, message)
    Notify(kind or 'inform', tostring(message or ''))
end)


CreateThread(function()
    local fpc = FpConfig()
    if not fpc.Enabled or not fpc.UseOxTarget then return end

    Wait(2000)
    if GetResourceState('ox_target') ~= 'started' then
        return
    end

    exports.ox_target:addGlobalPlayer({
        {
            name = 'cdecad_scan_fingerprint',
            icon = 'fas fa-fingerprint',
            label = fpc.TargetLabel or 'Scan Fingerprint',
            distance = fpc.Range or 2.5,
            onSelect = function(data)
                local targetPlayerId = NetworkGetPlayerIndexFromPed(data.entity)
                local targetServerId = GetPlayerServerId(targetPlayerId)
                ScanTarget(targetServerId)
            end,
            canInteract = function()
                if scanning then return false end
                if fpc.RequireLEO then
                    local ok, onDuty = pcall(function()
                        return exports[GetCurrentResourceName()]:IsOnDutyLEO()
                    end)
                    return ok and onDuty == true
                end
                return true
            end,
        },
    })

    print('[CDECAD-FINGERPRINT] ox_target integration loaded')
end)


CreateThread(function()
    local fpc = FpConfig()
    if not fpc.Enabled or not fpc.Command or fpc.Command == '' then return end

    RegisterCommand(fpc.Command, function()
        local myCoords = GetEntityCoords(PlayerPedId())
        local closest, closestDist = nil, (fpc.Range or 2.5)
        for _, player in ipairs(GetActivePlayers()) do
            if player ~= PlayerId() then
                local dist = #(GetEntityCoords(GetPlayerPed(player)) - myCoords)
                if dist < closestDist then
                    closest, closestDist = player, dist
                end
            end
        end
        if not closest then
            Notify('error', 'No one close enough to scan')
            return
        end
        ScanTarget(GetPlayerServerId(closest))
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. fpc.Command, "Scan the nearest player's fingerprint")
end)

print('[CDECAD-FINGERPRINT] Client script loaded')
