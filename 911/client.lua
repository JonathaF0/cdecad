do
    local Config = Cad911Config
-- ═══════════════════════════════════════════════════════════════════
-- CLIENT-SIDE 911 CALLS
-- Gathers location, postal, and coordinates then sends to server
-- ═══════════════════════════════════════════════════════════════════

local lastCallTime = 0

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

local function GetZoneName(coords)
    local zoneHash = GetNameOfZone(coords.x, coords.y, coords.z)
    local label = GetLabelText(zoneHash)
    if label and label ~= 'NULL' and label ~= '' then
        return label
    end
    return ''
end

--- Try multiple popular postal resources, return postal code or empty string.
local function GetNearestPostal(coords)
    -- nearest-postal (most common)
    local ok, result = pcall(function()
        return exports['nearest-postal']:getClosestPostal(coords)
    end)
    if ok and result then
        if type(result) == 'table' then
            return tostring(result.code or result[1] or '')
        end
        return tostring(result)
    end

    -- nearest-postal alternate export
    ok, result = pcall(function()
        return exports['nearest-postal']:getPostal()
    end)
    if ok and result then
        return tostring(result)
    end

    -- postal-code / postal
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

-- ─── Build full location string ──────────────────────────────────

local function GetLocationData()
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local street = GetStreetName(coords)
    local zone   = GetZoneName(coords)
    local postal = GetNearestPostal(coords)

    local location = street
    if zone ~= '' then
        location = location .. ', ' .. zone
    end
    if postal ~= '' then
        location = location .. ' (Postal ' .. postal .. ')'
    end

    return {
        location = location,
        postal   = postal,
        coords   = { x = coords.x, y = coords.y, z = coords.z },
    }
end

-- ─── Cooldown check ──────────────────────────────────────────────

local function CheckCooldown()
    local now = GetGameTimer() / 1000
    local remaining = Config.CooldownSeconds - (now - lastCallTime)
    if remaining > 0 then
        if Config.ChatEnabled then
            TriggerEvent('chat:addMessage', {
                color = { 255, 50, 50 },
                args  = { string.format(Config.Messages.cooldown, math.ceil(remaining)) }
            })
        end
        return false
    end
    lastCallTime = now
    return true
end

-- ─── /911 command ────────────────────────────────────────────────

RegisterCommand(Config.Command911, function(source, args)
    local message = table.concat(args, ' ')
    if message == '' then
        if Config.ChatEnabled then
            TriggerEvent('chat:addMessage', {
                color = { 255, 50, 50 },
                args  = { Config.Messages.noMsg }
            })
        end
        return
    end

    if not CheckCooldown() then return end

    local loc = GetLocationData()
    TriggerServerEvent('cad-911:call', {
        message  = message,
        location = loc.location,
        postal   = loc.postal,
        coords   = loc.coords,
        anon     = false,
    })

    if Config.ChatEnabled then
        TriggerEvent('chat:addMessage', {
            color = { 50, 205, 50 },
            args  = { Config.Messages.sent }
        })
    end
end, false)

-- ─── /a911 command (anonymous) ───────────────────────────────────

RegisterCommand(Config.CommandAnon, function(source, args)
    local message = table.concat(args, ' ')
    if message == '' then
        if Config.ChatEnabled then
            TriggerEvent('chat:addMessage', {
                color = { 255, 50, 50 },
                args  = { Config.Messages.noMsg }
            })
        end
        return
    end

    if not CheckCooldown() then return end

    local loc = GetLocationData()
    TriggerServerEvent('cad-911:call', {
        message  = message,
        location = loc.location,
        postal   = loc.postal,
        coords   = loc.coords,
        anon     = true,
    })

    if Config.ChatEnabled then
        TriggerEvent('chat:addMessage', {
            color = { 50, 205, 50 },
            args  = { Config.Messages.sentAnon }
        })
    end
end, false)

end
