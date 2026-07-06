do
    local Config = TabletConfig
-- client/main.lua
-- CAD Tablet & Call Details Popup

local tabletOpen    = false
local popupVisible  = false
local callData      = {}
local callIndex     = 1
local lastOpenTime  = 0
local openDebounce  = 500
local tabletProp    = nil

local TABLET_ANIM_DICT = "amb@code_human_in_bus_passenger_idles@female@tablet@base"
local TABLET_ANIM_NAME = "base"
local TABLET_PROP_MODEL = "prop_cs_tablet"

-- ─── Debug helper ────────────────────────────────────────────────────────────
local function dbg(msg)
    print("^5[CAD-TABLET] " .. msg .. "^0")
end

-- ─── Duty check (Standalone / CDE) ──────────────────────────────────────────
local function isOnDuty()
    if not Config.RequireOnDuty then return true end
    if not Config.Framework.Standalone then return true end

    local me = GetCurrentResourceName(); if not exports[me] then return false end

    local ok, result = pcall(function()
        return exports[GetCurrentResourceName()]:GetDutyStatus()
    end)
    if ok and result then return result.onDuty end

    local ok2, isLEO = pcall(function()
        return exports[GetCurrentResourceName()]:IsOnDutyLEO()
    end)
    return ok2 and isLEO or false
end

-- ─── Tablet open / close ─────────────────────────────────────────────────────
local function cleanupProp()
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    if tabletProp and DoesEntityExist(tabletProp) then
        DeleteEntity(tabletProp)
        tabletProp = nil
    end
end

local function closeTablet()
    -- Always release NUI focus even if the tablet is already flagged closed;
    -- the close callback can race the JS-side hide.
    dbg("closeTablet() called (was open=" .. tostring(tabletOpen) .. ")")

    cleanupProp()

    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "closeTablet" })

    tabletOpen = false
    lastOpenTime = GetGameTimer()

    dbg("Tablet closed")
end

local function openTablet()
    if tabletOpen then return end
    if not isOnDuty() then
        dbg("Cannot open tablet - not on duty")
        return
    end

    -- Debounce rapid toggles
    if (GetGameTimer() - lastOpenTime) < openDebounce then return end

    dbg("openTablet() called")
    tabletOpen = true
    lastOpenTime = GetGameTimer()

    -- Play tablet animation and attach prop
    local ped = PlayerPedId()
    RequestAnimDict(TABLET_ANIM_DICT)
    while not HasAnimDictLoaded(TABLET_ANIM_DICT) do
        Citizen.Wait(100)
    end

    tabletProp = CreateObject(GetHashKey(TABLET_PROP_MODEL), 0, 0, 0, true, true, true)
    AttachEntityToEntity(
        tabletProp, ped, GetPedBoneIndex(ped, 60309),
        0.03, 0.002, -0.02,
        0.0, 0.0, 0.0,
        true, true, false, true, 1, true
    )
    TaskPlayAnim(ped, TABLET_ANIM_DICT, TABLET_ANIM_NAME, 8.0, -8.0, -1, 50, 0, false, false, false)

    Citizen.Wait(200)
    SendNUIMessage({ type = "openTablet", url = Config.TabletURL, dimmer = Config.TabletDimmer })
    SetNuiFocus(true, true)
    -- Exclusive focus; ESC is captured by the JS keydown listener in html/script.js.
    SetNuiFocusKeepInput(false)

    dbg("Tablet opened")
end

local function toggleTablet()
    dbg("toggleTablet() - tabletOpen=" .. tostring(tabletOpen))
    if tabletOpen then closeTablet() else openTablet() end
end

-- ─── Call popup ──────────────────────────────────────────────────────────────
local function showPopup()
    if popupVisible then return end
    popupVisible = true
    SendNUIMessage({ type = "showPopup" })
    TriggerServerEvent('cad-tablet:requestCalls')
    dbg("Popup shown")
end

local function hidePopup()
    if not popupVisible then return end
    popupVisible = false
    SendNUIMessage({ type = "hidePopup" })
    dbg("Popup hidden")
end

local function togglePopup()
    if popupVisible then hidePopup() else showPopup() end
end

-- ─── Receive call data from server ───────────────────────────────────────────
RegisterNetEvent('cad-tablet:receiveCalls')
AddEventHandler('cad-tablet:receiveCalls', function(calls)
    callData = calls or {}
    if callIndex > #callData then callIndex = #callData end
    if callIndex < 1 then callIndex = 1 end

    SendNUIMessage({
        type       = "updateCalls",
        calls      = callData,
        callIndex  = callIndex,
        totalCalls = #callData,
    })
end)

-- ─── Polling thread - only runs while popup is visible ───────────────────────
local function startPolling()
    Citizen.CreateThread(function()
        while popupVisible do
            Citizen.Wait(Config.CallPollInterval)
            if popupVisible then
                TriggerServerEvent('cad-tablet:requestCalls')
            end
        end
    end)
end

local _showPopup = showPopup
showPopup = function()
    _showPopup()
    startPolling()
end

-- ─── NUI callbacks ───────────────────────────────────────────────────────────
RegisterNUICallback('closeTablet', function(_, cb)
    dbg("NUI callback: closeTablet")
    closeTablet()
    cb('ok')
end)

RegisterNUICallback('prevCall', function(_, cb)
    if callIndex > 1 then
        callIndex = callIndex - 1
        SendNUIMessage({
            type       = "updateCalls",
            calls      = callData,
            callIndex  = callIndex,
            totalCalls = #callData,
        })
    end
    cb('ok')
end)

RegisterNUICallback('nextCall', function(_, cb)
    if callIndex < #callData then
        callIndex = callIndex + 1
        SendNUIMessage({
            type       = "updateCalls",
            calls      = callData,
            callIndex  = callIndex,
            totalCalls = #callData,
        })
    end
    cb('ok')
end)

RegisterNUICallback('closePopup', function(_, cb)
    hidePopup()
    cb('ok')
end)

-- ─── Commands ────────────────────────────────────────────────────────────────
-- 'tablet' and 'cad' both toggle so existing keybinds keep working.
RegisterCommand('tablet', function()
    dbg("Command 'tablet' fired")
    toggleTablet()
end, false)

RegisterCommand('cad', function()
    dbg("Command 'cad' fired")
    toggleTablet()
end, false)

RegisterKeyMapping('tablet', Config.TabletDescription, 'keyboard', Config.TabletKey)

-- Hard-reload the CAD iframe in-place
RegisterCommand('cadrefresh', function()
    dbg("Command 'cadrefresh' fired")
    SendNUIMessage({ type = "reloadTablet" })
end, false)

-- Emergency reset command
RegisterCommand('resetcad', function()
    dbg("Emergency reset triggered")
    cleanupProp()
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "closeTablet" })
    tabletOpen = false
    lastOpenTime = GetGameTimer()
    dbg("Emergency reset complete")
end, false)

if Config.EnableCallPopup then
    RegisterCommand('cad_popup', function()
        if tabletOpen then return end
        togglePopup()
    end, false)
    RegisterKeyMapping('cad_popup', Config.CallPopupDescription, 'keyboard', Config.CallPopupKey)
end

-- ─── Main control thread ─────────────────────────────────────────────────────
-- ESC is handled in JS (html/script.js); close the tablet if the player dies.
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if tabletOpen then
            DisableAllControlActions(0)

            if IsEntityDead(PlayerPedId()) then
                dbg("Player died, closing tablet")
                closeTablet()
            end
        end
    end
end)

-- ─── Cleanup ─────────────────────────────────────────────────────────────────
AddEventHandler('onResourceStop', function(res)
    if GetCurrentResourceName() ~= res then return end
    cleanupProp()
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    if Config.LocationTracking and Config.LocationTracking.Enabled
       and Config.LocationTracking.SendOfflineOnDisconnect then
        TriggerServerEvent('cad-tablet:sendOffline')
    end
end)

-- ─── Optional: Location Tracking ─────────────────────────────────────────────
-- Pushes on-duty player coords to /api/dispatch/location-update on a timer.

local LEO_JOBS = {
    leo = true, police = true, sheriff = true, trooper = true,
    statepolice = true, lspd = true, bcso = true, sasp = true, highway = true,
}

local cadActiveCache = {
    active     = false,
    status     = 'Offline',
    department = nil,
    callSign   = nil,
    lastUpdate = 0,
}

local trackingState = {
    lastPos      = nil,
    lastSent     = 0,
    isTracking   = false,
}

local function getPostal()
    if GetResourceState('nearest-postal') ~= 'started' then return 'Unknown' end
    local attempts = {
        function() return exports.npostal:npostal() end,
        function() return exports['nearest-postal']:npostal() end,
        function() return exports['nearest-postal']:getPostal() end,
        function() return exports.npostal:getPostal() end,
    }
    for _, fn in ipairs(attempts) do
        local ok, result = pcall(fn)
        if ok and result then return tostring(result) end
    end
    return 'Unknown'
end

local function getDutyFromCDE()
    local me = GetCurrentResourceName(); if not exports[me] then return nil end
    local ok, result = pcall(function() return exports[GetCurrentResourceName()]:GetDutyStatus() end)
    if not ok or not result then return nil end
    if result.onDuty then
        return {
            onDuty     = true,
            department = result.department or result.job,
            job        = result.job,
            status     = 'In Service',
        }
    end
    return { onDuty = false }
end

local function getDutyFromESX()
    if GetResourceState('es_extended') ~= 'started' then return nil end
    local ok, ESX = pcall(function() return exports['es_extended']:getSharedObject() end)
    if not ok or not ESX then return nil end
    local pd = ESX.GetPlayerData and ESX.GetPlayerData()
    if pd and pd.job and pd.job.name then
        return {
            onDuty     = true,
            department = pd.job.name,
            job        = pd.job.name,
            status     = 'In Service',
        }
    end
    return { onDuty = false }
end

local function getDutyFromQBCore()
    if GetResourceState('qb-core') ~= 'started' then return nil end
    local ok, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if not ok or not QBCore then return nil end
    local pd = QBCore.Functions and QBCore.Functions.GetPlayerData()
    if pd and pd.job and pd.job.name and pd.job.onduty then
        return {
            onDuty     = true,
            department = pd.job.name,
            job        = pd.job.name,
            status     = 'In Service',
        }
    end
    return { onDuty = false }
end

local function getDutyFromCAD()
    return {
        onDuty     = cadActiveCache.active == true,
        department = cadActiveCache.department,
        job        = nil,
        status     = cadActiveCache.status or 'In Service',
    }
end

local function resolveDutyState()
    local src = (Config.LocationTracking and Config.LocationTracking.DutySource) or 'auto'
    if src == 'cde_duty' then return getDutyFromCDE() or { onDuty = false } end
    if src == 'esx'      then return getDutyFromESX() or { onDuty = false } end
    if src == 'qbcore'   then return getDutyFromQBCore() or { onDuty = false } end
    if src == 'cad'      then return getDutyFromCAD() end
    -- auto: first source that returns a usable result
    return getDutyFromCDE() or getDutyFromESX() or getDutyFromQBCore() or getDutyFromCAD()
end

local function getDistance(a, b)
    if not a or not b then return math.huge end
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function shouldTrack(duty)
    if not duty or not duty.onDuty then return false end
    if Config.LocationTracking.LEOOnly and duty.job and not LEO_JOBS[string.lower(duty.job)] then
        return false
    end
    return true
end

local function pushLocation(coords, duty)
    TriggerServerEvent('cad-tablet:pushLocation', {
        x          = coords.x,
        y          = coords.y,
        z          = coords.z,
        heading    = GetEntityHeading(PlayerPedId()),
        status     = duty.status or 'In Service',
        department = duty.department,
        postal     = getPostal(),
    })
    trackingState.lastPos  = coords
    trackingState.lastSent = GetGameTimer()
end

-- Latest CAD active-state, pushed from the server
RegisterNetEvent('cad-tablet:cadActiveResult')
AddEventHandler('cad-tablet:cadActiveResult', function(data)
    cadActiveCache.active     = data and data.active == true
    cadActiveCache.status     = data and data.status or 'Offline'
    cadActiveCache.department = data and data.department or nil
    cadActiveCache.callSign   = data and data.callSign or nil
    cadActiveCache.lastUpdate = GetGameTimer()
    dbg("CAD active=" .. tostring(cadActiveCache.active)
        .. ", dept=" .. tostring(cadActiveCache.department))
end)

-- Push thread - only created when tracking is enabled
if Config.LocationTracking and Config.LocationTracking.Enabled then
    Citizen.CreateThread(function()
        -- Wait for resource init / framework load
        Citizen.Wait(5000)

        if GetResourceState('cde_lm') == 'started' then
            print("^1[CAD-TABLET] WARNING: cde_lm livemap is also running. " ..
                  "You'll get duplicate location updates. Disable one.^0")
        end

        while true do
            Citizen.Wait(Config.LocationTracking.Interval or 10000)

            local duty = resolveDutyState()
            if shouldTrack(duty) then
                local ped = PlayerPedId()
                if DoesEntityExist(ped) and not IsEntityDead(ped) then
                    local coords = GetEntityCoords(ped)
                    local moved  = getDistance(coords, trackingState.lastPos)
                    if moved >= (Config.LocationTracking.MinDistance or 50.0) then
                        pushLocation(coords, duty)
                        if not trackingState.isTracking then
                            trackingState.isTracking = true
                            dbg("Tracking started - dept=" .. tostring(duty.department))
                        end
                    end
                end
            else
                if trackingState.isTracking then
                    trackingState.isTracking = false
                    dbg("Tracking stopped - went off duty")
                    if Config.LocationTracking.SendOfflineOnDisconnect then
                        TriggerServerEvent('cad-tablet:sendOffline')
                    end
                end
            end
        end
    end)

    -- CAD active-state poller (only when DutySource needs it)
    Citizen.CreateThread(function()
        local src = Config.LocationTracking.DutySource or 'auto'
        if src ~= 'cad' and src ~= 'auto' then return end

        Citizen.Wait(3000)
        while true do
            TriggerServerEvent('cad-tablet:checkCADActive')
            Citizen.Wait(Config.LocationTracking.CADActiveCheckInterval or 30000)
        end
    end)
end

-- ─── Init ────────────────────────────────────────────────────────────────────
Citizen.CreateThread(function()
    SetNuiFocus(false, false)
    Citizen.Wait(500)
    dbg("Initialized - Tablet key: " .. Config.TabletKey ..
         ", Popup key: " .. (Config.EnableCallPopup and Config.CallPopupKey or "disabled"))
end)

end
