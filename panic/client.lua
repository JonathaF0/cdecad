do
    local Config = PanicConfig
local activePanics = {}  
local lastPanicTime = 0

-- ─── Helpers ────────────────────────────────────────────────────

local function GetStreetName(coords)
    local streetHash, crossHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash) or ''
    local cross  = GetStreetNameFromHashKey(crossHash) or ''
    if cross ~= '' then
        return street .. ' / ' .. cross
    end
    return street
end

local function GetPlayerNameSafe()
    return GetPlayerName(PlayerId()) or 'Unknown'
end

local function IsLocalOnDutyLEO()
    local ok, res = pcall(function()
        return exports['CDECAD']:IsOnDutyLEO()
    end)
    if ok and res ~= nil then
        return res and true or false
    end

    return true
end


local function GetNearestPostal(coords)
    local ok, result = pcall(function()
        return exports['nearest-postal']:getClosestPostal(coords)
    end)
    if ok and result then
        if type(result) == 'table' then
            return tostring(result.code or result[1] or '')
        end
        return tostring(result)
    end

    ok, result = pcall(function()
        return exports['postal-code']:getPostal(coords)
    end)
    if ok and result then
        if type(result) == 'table' then
            return tostring(result.code or result[1] or '')
        end
        return tostring(result)
    end

    return ''
end

-- ─── Blip Management ────────────────────────────────────────────

local function CreatePanicBlip(coords, playerName)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, Config.BlipSprite)
    SetBlipColour(blip, Config.BlipColor)
    SetBlipScale(blip, Config.BlipScale)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('PANIC: ' .. playerName)
    EndTextCommandSetBlipName(blip)

    if Config.BlipFlashes then
        SetBlipFlashes(blip, true)
    end

    local routeBlip = nil
    if Config.ShowRoute then
        routeBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(routeBlip, Config.BlipSprite)
        SetBlipColour(routeBlip, Config.BlipColor)
        SetBlipRoute(routeBlip, true)
        SetBlipRouteColour(routeBlip, Config.BlipColor)
    end

    return blip, routeBlip
end

local function RemovePanicBlip(data)
    if data.blip and DoesBlipExist(data.blip) then
        RemoveBlip(data.blip)
    end
    if data.routeBlip and DoesBlipExist(data.routeBlip) then
        SetBlipRoute(data.routeBlip, false)
        RemoveBlip(data.routeBlip)
    end
end

-- ─── Panic Activation (client requests server to broadcast) ─────

local function ActivatePanic()
    -- Only on-duty LEOs may activate the panic button.
    if Config.RequireOnDutyLEO and not IsLocalOnDutyLEO() then
        if Config.ChatEnabled then
            TriggerEvent('chat:addMessage', {
                color = Config.ChatColor,
                args  = { Config.Messages.notOnDuty }
            })
        end
        return
    end

    local now = GetGameTimer() / 1000
    local remaining = Config.CooldownSeconds - (now - lastPanicTime)

    if remaining > 0 then
        if Config.ChatEnabled then
            TriggerEvent('chat:addMessage', {
                color = Config.ChatColor,
                args  = { string.format(Config.Messages.cooldown, math.ceil(remaining)) }
            })
        end
        return
    end

    lastPanicTime = now

    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local street = GetStreetName(coords)
    local postal = GetNearestPostal(coords)

    -- Tell the server — it handles CAD integration and broadcasts to all clients
    TriggerServerEvent('cdecad-panic:activate', {
        name   = GetPlayerNameSafe(),
        coords = { x = coords.x, y = coords.y, z = coords.z },
        street = street,
        postal = postal,
    })
end

-- ─── Register Command & Keybind ─────────────────────────────────

RegisterCommand(Config.Command, function()
    ActivatePanic()
end, false)

RegisterKeyMapping(Config.Command, Config.KeybindLabel, 'keyboard', Config.KeybindKey)

-- ─── Receive Panic Broadcasts from Server ───────────────────────

RegisterNetEvent('cdecad-panic:broadcast')
AddEventHandler('cdecad-panic:broadcast', function(data)
    local srcId = data.serverId

    if activePanics[srcId] then
        RemovePanicBlip(activePanics[srcId])
    end

    local blip, routeBlip = CreatePanicBlip(
        vector3(data.coords.x, data.coords.y, data.coords.z),
        data.name
    )

    activePanics[srcId] = {
        blip      = blip,
        routeBlip = routeBlip,
        name      = data.name,
        expires   = GetGameTimer() + (Config.BlipDurationSeconds * 1000),
    }

    if Config.ChatEnabled then
        TriggerEvent('chat:addMessage', {
            color = Config.ChatColor,
            args  = { string.format(Config.Messages.activated, data.name, data.street) }
        })
    end

    -- Brief red screen flash (NOT the death camera)
    AnimpostfxPlay('MP_OrbitalCannon', 0, false)
    Citizen.SetTimeout(200, function()
        AnimpostfxStop('MP_OrbitalCannon')
    end)

    PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
end)

-- ─── Tick: Expire Old Panics ────────────────────────────────────

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)

        local now = GetGameTimer()
        for srcId, data in pairs(activePanics) do
            if now >= data.expires then
                RemovePanicBlip(data)

                if Config.ChatEnabled then
                    TriggerEvent('chat:addMessage', {
                        color = Config.ChatColor,
                        args  = { string.format(Config.Messages.cleared, data.name) }
                    })
                end

                activePanics[srcId] = nil
            end
        end
    end
end)

end
