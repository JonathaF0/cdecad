do
    local Config = Cad911Config

-- ═══════════════════════════════════════════════════════════════════
-- NPC WITNESS REPORTS
-- Detects gunshots / fights / speed-camera triggers from the local
-- player and fires `cad-911:npc` to the server, which forwards to
-- the CAD as a witness 911.
-- ═══════════════════════════════════════════════════════════════════

if not Config.NPCReports or not Config.NPCReports.Enabled then return end

-- ─── Shared helpers ─────────────────────────────────────────────────

local function StreetName(coords)
    local s, c = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(s) or ''
    local cross  = GetStreetNameFromHashKey(c) or ''
    if cross ~= '' then return street .. ' / ' .. cross end
    return street ~= '' and street or 'Unknown Location'
end

local function PostalCode(coords)
    local ok, r = pcall(function() return exports['nearest-postal']:getClosestPostal(coords) end)
    if ok and r then
        if type(r) == 'table' then return tostring(r.code or r[1] or '') end
        return tostring(r)
    end
    ok, r = pcall(function() return exports['nearest-postal']:getPostal() end)
    if ok and r then return tostring(r) end
    return ''
end

local function NearbyLivingPeds(coords, radius)
    local count = 0
    local handle, ped = FindFirstPed()
    local ok = true
    repeat
        if not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped) then
            if #(coords - GetEntityCoords(ped)) <= radius then
                count = count + 1
            end
        end
        ok, ped = FindNextPed(handle)
    until not ok
    EndFindPed(handle)
    return count
end

-- Skip NPC reports for on-duty LEOs; checked live at send time via the duty export
local function IsLocalOnDutyLEO()
    local ok, res = pcall(function()
        return exports[GetCurrentResourceName()]:IsOnDutyLEO()
    end)
    return ok and res == true
end

local function SendNPC(report)
    if IsLocalOnDutyLEO() then return end
    TriggerServerEvent('cad-911:npc', report)
end

-- ─── Gunshots ───────────────────────────────────────────────────────

local GunWeapons = {
    [`WEAPON_PISTOL`]=1, [`WEAPON_PISTOL_MK2`]=1, [`WEAPON_COMBATPISTOL`]=1,
    [`WEAPON_APPISTOL`]=1, [`WEAPON_PISTOL50`]=1, [`WEAPON_SNSPISTOL`]=1,
    [`WEAPON_SNSPISTOL_MK2`]=1, [`WEAPON_HEAVYPISTOL`]=1, [`WEAPON_VINTAGEPISTOL`]=1,
    [`WEAPON_MARKSMANPISTOL`]=1, [`WEAPON_REVOLVER`]=1, [`WEAPON_REVOLVER_MK2`]=1,
    [`WEAPON_DOUBLEACTION`]=1, [`WEAPON_CERAMICPISTOL`]=1, [`WEAPON_NAVYREVOLVER`]=1,
    [`WEAPON_GADGETPISTOL`]=1, [`WEAPON_MICROSMG`]=1, [`WEAPON_SMG`]=1,
    [`WEAPON_SMG_MK2`]=1, [`WEAPON_ASSAULTSMG`]=1, [`WEAPON_COMBATPDW`]=1,
    [`WEAPON_MACHINEPISTOL`]=1, [`WEAPON_MINISMG`]=1, [`WEAPON_RAYCARBINE`]=1,
    [`WEAPON_PUMPSHOTGUN`]=1, [`WEAPON_PUMPSHOTGUN_MK2`]=1, [`WEAPON_SAWNOFFSHOTGUN`]=1,
    [`WEAPON_ASSAULTSHOTGUN`]=1, [`WEAPON_BULLPUPSHOTGUN`]=1, [`WEAPON_MUSKET`]=1,
    [`WEAPON_HEAVYSHOTGUN`]=1, [`WEAPON_DBSHOTGUN`]=1, [`WEAPON_AUTOSHOTGUN`]=1,
    [`WEAPON_COMBATSHOTGUN`]=1, [`WEAPON_ASSAULTRIFLE`]=1, [`WEAPON_ASSAULTRIFLE_MK2`]=1,
    [`WEAPON_CARBINERIFLE`]=1, [`WEAPON_CARBINERIFLE_MK2`]=1, [`WEAPON_ADVANCEDRIFLE`]=1,
    [`WEAPON_SPECIALCARBINE`]=1, [`WEAPON_SPECIALCARBINE_MK2`]=1, [`WEAPON_BULLPUPRIFLE`]=1,
    [`WEAPON_BULLPUPRIFLE_MK2`]=1, [`WEAPON_COMPACTRIFLE`]=1, [`WEAPON_MILITARYRIFLE`]=1,
    [`WEAPON_MG`]=1, [`WEAPON_COMBATMG`]=1, [`WEAPON_COMBATMG_MK2`]=1,
    [`WEAPON_GUSENBERG`]=1, [`WEAPON_SNIPERRIFLE`]=1, [`WEAPON_HEAVYSNIPER`]=1,
    [`WEAPON_HEAVYSNIPER_MK2`]=1, [`WEAPON_MARKSMANRIFLE`]=1, [`WEAPON_MARKSMANRIFLE_MK2`]=1,
    [`WEAPON_MINIGUN`]=1,
}

if Config.NPCReports.Gunshots and Config.NPCReports.Gunshots.Enabled then
    local last = 0
    local cd   = (Config.NPCReports.Gunshots.Cooldown or 60) * 1000
    local rad  = Config.NPCReports.Gunshots.Radius or 200.0

    CreateThread(function()
        while true do
            Wait(100)
            local ped = PlayerPedId()
            if IsPedShooting(ped) and GunWeapons[GetSelectedPedWeapon(ped)] then
                local now = GetGameTimer()
                if now - last >= cd then
                    local coords = GetEntityCoords(ped)
                    if NearbyLivingPeds(coords, rad) > 0 then
                        last = now
                        SendNPC({
                            reportType = 'Gunshots',
                            callType   = 'Shots Fired',
                            location   = StreetName(coords),
                            postal     = PostalCode(coords),
                            coords     = { x = coords.x, y = coords.y, z = coords.z },
                        })
                    end
                end
            end
        end
    end)
end

-- ─── Fights ─────────────────────────────────────────────────────────

if Config.NPCReports.Fights and Config.NPCReports.Fights.Enabled then
    local last = 0
    local cd   = (Config.NPCReports.Fights.Cooldown or 60) * 1000

    CreateThread(function()
        while true do
            Wait(500)
            local ped = PlayerPedId()
            if IsPedInMeleeCombat(ped) then
                local now = GetGameTimer()
                if now - last >= cd then
                    local coords = GetEntityCoords(ped)
                    if NearbyLivingPeds(coords, 50.0) > 0 then
                        last = now
                        SendNPC({
                            reportType = 'Fighting',
                            callType   = 'Assault/Fight',
                            location   = StreetName(coords),
                            postal     = PostalCode(coords),
                            coords     = { x = coords.x, y = coords.y, z = coords.z },
                        })
                    end
                end
            end
        end
    end)
end

-- ─── Speed cameras ──────────────────────────────────────────────────

if Config.NPCReports.SpeedCamera and Config.NPCReports.SpeedCamera.Enabled
   and Config.NPCReports.SpeedCamera.Cameras and #Config.NPCReports.SpeedCamera.Cameras > 0 then
    local cd        = (Config.NPCReports.SpeedCamera.Cooldown or 60) * 1000
    local lastShot  = {}

    CreateThread(function()
        while true do
            Wait(1000)
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 then
                local speedMph = GetEntitySpeed(veh) * 2.236936
                local coords   = GetEntityCoords(ped)
                for i, cam in ipairs(Config.NPCReports.SpeedCamera.Cameras) do
                    if #(coords - cam.coords) < 50.0 and speedMph > (cam.speedLimit or 50) then
                        local now = GetGameTimer()
                        if not lastShot[i] or now - lastShot[i] >= cd then
                            lastShot[i] = now
                            SendNPC({
                                reportType = 'SpeedCamera',
                                callType   = 'Speeding Vehicle',
                                location   = cam.name or StreetName(coords),
                                postal     = PostalCode(coords),
                                coords     = { x = coords.x, y = coords.y, z = coords.z },
                                metadata   = {
                                    plate = GetVehicleNumberPlateText(veh),
                                    speed = math.floor(speedMph),
                                    limit = cam.speedLimit or 50,
                                },
                            })
                        end
                    end
                end
            end
        end
    end)
end

end
