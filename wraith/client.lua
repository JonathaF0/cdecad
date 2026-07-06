do
    local Config = WraithConfig
    if not Config or not Config.Enabled then return end
--[[
    CDE Wraith ARS 2X Integration - Client
    Handles displaying plate reader results to the player
]]

print('[CDE-Wraith] Client script LOADED (build with /cdetestlock and /cdetestscan)')

local isDisplaying = false
local hideTimer = nil

-- =============================================================================
-- DIAGNOSTIC COMMANDS
-- =============================================================================

-- /cdetestlock [plate] - fire wk:onPlateLocked as wraith would
RegisterCommand('cdetestlock', function(source, args)
    local plate = args[1] or 'TEST123'
    print(('[CDE-Wraith] CLIENT firing TriggerServerEvent("wk:onPlateLocked", "front", "%s", 0)'):format(plate))
    TriggerServerEvent('wk:onPlateLocked', 'front', plate, 0)
end, false)

-- /cdetestscan [plate] - same but for the scan event
RegisterCommand('cdetestscan', function(source, args)
    local plate = args[1] or 'TEST456'
    print(('[CDE-Wraith] CLIENT firing TriggerServerEvent("wk:onPlateScanned", "front", "%s", 0)'):format(plate))
    TriggerServerEvent('wk:onPlateScanned', 'front', plate, 0)
end, false)

-- =============================================================================
-- LEGACY CLIENT BRIDGE (no-op on wk_wars2x v1.3.1+)
-- =============================================================================
-- fallback for older builds that fire these as client-local events;
-- v1.3.1+ fires TriggerServerEvent directly. server-side cooldowns make
-- double-fire safe.

-- some forks pass a single table instead of (cam, plate, index)
local function WkArgs(a, b, c)
    if type(a) == 'table' then
        return a.cam or a.camera or a.antenna or a.ant, a.plate, a.index
    end
    return a, b, c
end

AddEventHandler('wk:onPlateLocked', function(a, b, c)
    local cam, plate, index = WkArgs(a, b, c)
    if not plate or plate == '' then return end
    TriggerServerEvent('wk:onPlateLocked', cam, plate, index)
end)

AddEventHandler('wk:onPlateScanned', function(a, b, c)
    local cam, plate, index = WkArgs(a, b, c)
    if not plate or plate == '' then return end
    TriggerServerEvent('wk:onPlateScanned', cam, plate, index)
end)

-- =============================================================================
-- RECEIVE PLATE RESULTS FROM SERVER
-- =============================================================================

-- emergency-vehicle filter for scans. GetVehicleClass is client-only,
-- so this check can't run on the server. class 18 = emergency.
local function NormalizePlateLocal(p)
    if not p then return '' end
    return (p:gsub('%s', '')):upper()
end

local function ScannedVehicleIsEmergency(plate)
    local target = NormalizePlateLocal(plate)
    if target == '' then return false end
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if NormalizePlateLocal(GetVehicleNumberPlateText(veh)) == target then
            return GetVehicleClass(veh) == 18
        end
    end
    return false
end

RegisterNetEvent('cde-wraith:plateResult')
AddEventHandler('cde-wraith:plateResult', function(data, cam)
    if not data then return end

    -- skip emergency-class vehicles on scans; locks bypass this filter
    if data.cached and Config.PlateReader.IgnoreEmergencyVehicles and data.plate then
        if ScannedVehicleIsEmergency(data.plate) then
            return
        end
    end

    -- feed the /reader console; passive iframe, never takes focus
    SendNUIMessage({ action = 'readerScan', data = data, cam = cam })

    if Config.Display.ShowChat then
        ShowChatResult(data, cam)
    end

    -- never show the popup while another NUI holds focus: the cursor
    -- hit-test does not reliably honor pointer-events:none on it, so it
    -- can capture input from the focused NUI. locks always pop (even
    -- NOT ON FILE); scans only pop for found, non-clean results.
    local isCleanScan = data.cached and data.alertLevel == 'none'
    local wantPopup = Config.Display.ShowPopup
        and ((not data.cached) or (data.found and not isCleanScan))
    if wantPopup and not IsNuiFocused() then
        ShowNUIResult(data, cam)
    end

    if Config.Notifications.UseOxLib then
        ShowOxLibNotification(data, cam)
    end
end)

-- =============================================================================
-- CHAT DISPLAY
-- =============================================================================

function ShowChatResult(data, cam)
    local plate = data.plate or 'UNKNOWN'

    if not data.found then
        TriggerEvent('chat:addMessage', {
            args = { string.format(Config.Display.ChatNotFoundFormat, plate) }
        })
        return
    end

    -- cached scan hits have no vehicle/owner data; compact alert line only
    if data.cached then
        if data.alertLevel == 'none' then
            TriggerEvent('chat:addMessage', {
                args = { string.format('~g~[PLATE READER]~w~ %s | ~g~CLEAN', plate) }
            })
            return
        end
        local flagStr = table.concat(data.flags or {}, ', ')
        local color = data.alertLevel == 'alert' and '~r~' or '~y~'
        TriggerEvent('chat:addMessage', {
            args = { string.format('%s[PLATE READER]~w~ %s | %sFLAGS: %s ~s~(lock for details)',
                color, plate, color, flagStr
            ) }
        })
        return
    end

    local veh = data.vehicle or {}
    local owner = data.owner or {}
    local ownerName = owner.name or 'Unknown'

    if data.alertLevel == 'none' then
        TriggerEvent('chat:addMessage', {
            args = { string.format(Config.Display.ChatCleanFormat,
                plate, veh.color or '', veh.year or '', veh.model or '', ownerName
            ) }
        })
    else
        local flagStr = table.concat(data.flags or {}, ', ')
        TriggerEvent('chat:addMessage', {
            args = { string.format(Config.Display.ChatFlagFormat,
                plate, veh.color or '', veh.year or '', veh.model or '', ownerName, flagStr
            ) }
        })
    end
end

-- =============================================================================
-- NUI DISPLAY
-- =============================================================================

function ShowNUIResult(data, cam)
    isDisplaying = true

    SendNUIMessage({
        action = 'showPlateResult',
        data = data,
        cam = cam,
    })

    -- no SetNuiFocus here: SetNuiFocus(false, false) would release focus
    -- held by another NUI (e.g. the CAD tablet)

    -- auto-hide after duration
    if Config.Display.DisplayDuration > 0 then
        if hideTimer then
            hideTimer = nil
        end

        local thisTimer = GetGameTimer()
        hideTimer = thisTimer

        SetTimeout(Config.Display.DisplayDuration * 1000, function()
            if hideTimer == thisTimer then
                HideNUIResult()
            end
        end)
    end
end

function HideNUIResult()
    isDisplaying = false
    hideTimer = nil

    SendNUIMessage({
        action = 'hidePlateResult',
    })
end

-- =============================================================================
-- OX_LIB NOTIFICATIONS
-- =============================================================================

function ShowOxLibNotification(data, cam)
    local plate = data.plate or 'UNKNOWN'

    if not data.found then
        lib.notify({
            title = 'Plate Reader',
            description = plate .. ' - Not in system',
            type = 'warning',
            position = Config.Notifications.Position,
            duration = Config.Notifications.Duration,
        })
        return
    end

    local notifType = 'success'
    if data.alertLevel == 'caution' then
        notifType = 'warning'
    elseif data.alertLevel == 'alert' then
        notifType = 'error'
    end

    -- cached scan hit: short notification with flags only
    if data.cached then
        lib.notify({
            title = 'Plate: ' .. plate,
            description = table.concat(data.flags or {}, ', ') .. '\nLock for details',
            type = notifType,
            position = Config.Notifications.Position,
            duration = Config.Notifications.Duration,
        })
        return
    end

    local veh = data.vehicle or {}
    local owner = data.owner or {}

    -- Build description
    local desc = ''
    if Config.Notifications.Detailed then
        desc = string.format('%s %s %s %s', veh.color or '', veh.year or '', veh.make or '', veh.model or '')
        desc = desc .. '\nOwner: ' .. (owner.name or 'Unknown')
        if owner.licenseStatus then
            desc = desc .. '\nLicense: ' .. owner.licenseStatus
        end
        if data.flags and #data.flags > 0 then
            desc = desc .. '\nFlags: ' .. table.concat(data.flags, ', ')
        end
        if data.bolo then
            desc = desc .. '\nBOLO: ' .. (data.bolo.reason or 'Active')
        end
    else
        if data.alertLevel == 'none' then
            desc = (owner.name or 'Unknown') .. ' - Clean'
        else
            desc = (owner.name or 'Unknown') .. ' - ' .. table.concat(data.flags or {}, ', ')
        end
    end

    lib.notify({
        title = 'Plate: ' .. plate,
        description = desc,
        type = notifType,
        position = Config.Notifications.Position,
        duration = Config.Notifications.Duration,
    })
end

-- =============================================================================
-- IN-CAR ALPR CONSOLE (/reader)
-- =============================================================================
-- rolling list of wraith reads with CAD status, plus last-read display.
-- fully passive: pointer-events:none, never takes NUI focus.

if Config.Reader and Config.Reader.Enabled then
    local readerVisible = false

    local readerCmd = Config.Reader.Command or 'reader'
    RegisterCommand(readerCmd, function()
        readerVisible = not readerVisible
        SendNUIMessage({ action = readerVisible and 'readerShow' or 'readerHide' })
        TriggerEvent('chat:addMessage', {
            args = { '^3[ALPR]', readerVisible and 'Plate reader console ON.' or 'Plate reader console OFF.' }
        })
    end, false)
    TriggerEvent('chat:addSuggestion', '/' .. readerCmd, 'Toggle the in-car ALPR reader console')
    -- bindable in Settings > Key Bindings > FiveM (unbound by default)
    RegisterKeyMapping(readerCmd, 'Toggle ALPR reader console', 'keyboard', '')

    -- ── Independent full-traffic sweep ─────────────────────────────────
    -- wraith only emits events for select scans, so the console sweeps
    -- every nearby vehicle itself while open. results come back
    -- display-only via cdecad-reader:result (no popups, alerts, or 911s).
    local readerSeen = {}  -- [plate] = GetGameTimer ms of last report

    local function ReaderSweep()
        local ped = PlayerPedId()
        local myVeh = GetVehiclePedIsIn(ped, false)
        if myVeh == 0 then return end
        local myPos = GetEntityCoords(myVeh)
        local fwd = GetEntityForwardVector(myVeh)
        local radius = Config.Reader.ScanRadius or 45.0
        local cooldownMs = (Config.Reader.PlateCooldown or 45) * 1000
        local now = GetGameTimer()
        local batch = {}
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            if veh ~= myVeh and DoesEntityExist(veh) then
                local vpos = GetEntityCoords(veh)
                local dx, dy = vpos.x - myPos.x, vpos.y - myPos.y
                if math.sqrt(dx * dx + dy * dy) <= radius then
                    local plate = (GetVehicleNumberPlateText(veh) or ''):gsub('%s', ''):upper()
                    if plate ~= '' and (not readerSeen[plate] or (now - readerSeen[plate]) > cooldownMs) then
                        readerSeen[plate] = now
                        -- front/rear antenna by position relative to the patrol car
                        local dot = dx * fwd.x + dy * fwd.y
                        batch[#batch + 1] = { plate = plate, cam = dot >= 0 and 'front' or 'rear' }
                        if #batch >= 12 then break end
                    end
                end
            end
        end
        if #batch > 0 then
            TriggerServerEvent('cdecad-reader:check', batch)
        end
    end

    CreateThread(function()
        while true do
            Wait(Config.Reader.ScanInterval or 1500)
            if readerVisible then ReaderSweep() end
        end
    end)

    CreateThread(function()
        while true do
            Wait(60000)
            local now = GetGameTimer()
            for p, t in pairs(readerSeen) do
                if (now - t) > 180000 then readerSeen[p] = nil end
            end
        end
    end)

    RegisterNetEvent('cdecad-reader:result')
    AddEventHandler('cdecad-reader:result', function(results)
        if type(results) ~= 'table' then return end
        for _, r in ipairs(results) do
            if type(r) == 'table' and r.data then
                SendNUIMessage({ action = 'readerScan', data = r.data, cam = r.cam })
            end
        end
    end)
end

-- =============================================================================
-- CAD LOCK FALLBACK KEYS (work on ANY wk_wars2x build)
-- =============================================================================
-- some wk builds show LOCKED but never emit wk:onPlateLocked. these
-- commands lock the vehicle ahead/behind through the same server
-- pipeline as a stock 1.3.1 lock.

if Config.LockFallback and Config.LockFallback.Enabled then
    local function LockDirection(cam)
        local ped = PlayerPedId()
        local myVeh = GetVehiclePedIsIn(ped, false)
        if myVeh == 0 then
            TriggerEvent('chat:addMessage', { args = { '^1[Wraith]', 'You must be in a vehicle to lock a plate.' } })
            return
        end
        local myPos = GetEntityCoords(myVeh)
        local fwd = GetEntityForwardVector(myVeh)
        local wantFront = cam == 'front'
        local best, bestDist = nil, (Config.LockFallback.Range or 35.0)
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            if veh ~= myVeh and DoesEntityExist(veh) then
                local vpos = GetEntityCoords(veh)
                local dx, dy = vpos.x - myPos.x, vpos.y - myPos.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist > 0.5 and dist < bestDist then
                    local dot = (dx * fwd.x + dy * fwd.y) / dist
                    if (wantFront and dot > 0.4) or (not wantFront and dot < -0.4) then
                        best, bestDist = veh, dist
                    end
                end
            end
        end
        if not best then
            TriggerEvent('chat:addMessage', { args = { '^3[Wraith]', ('No vehicle in range to lock (%s).'):format(cam) } })
            return
        end
        local plate = (GetVehicleNumberPlateText(best) or ''):gsub('%s', ''):upper()
        if plate == '' then return end
        TriggerServerEvent('wk:onPlateLocked', cam, plate, 0)
        -- mirror the lock onto the wraith unit display via wk's export
        TriggerServerEvent('cde-wraith:lockWkDisplay', cam)
    end

    RegisterCommand('cdelockfront', function() LockDirection('front') end, false)
    RegisterCommand('cdelockrear',  function() LockDirection('rear')  end, false)
    -- bindable in Settings > Key Bindings > FiveM (unbound by default)
    RegisterKeyMapping('cdelockfront', 'CAD: lock plate ahead (front antenna)', 'keyboard', '')
    RegisterKeyMapping('cdelockrear',  'CAD: lock plate behind (rear antenna)', 'keyboard', '')
    TriggerEvent('chat:addSuggestion', '/cdelockfront', 'Lock the plate of the vehicle ahead into the CAD')
    TriggerEvent('chat:addSuggestion', '/cdelockrear', 'Lock the plate of the vehicle behind into the CAD')
end

-- =============================================================================
-- NUI CALLBACKS
-- =============================================================================

RegisterNUICallback('closePlateResult', function(data, cb)
    HideNUIResult()
    cb('ok')
end)

-- =============================================================================
-- KEY BINDING TO DISMISS
-- =============================================================================

-- backspace dismisses the plate result popup
CreateThread(function()
    while true do
        Wait(0)
        if isDisplaying then
            if IsControlJustReleased(0, 177) then -- Backspace
                HideNUIResult()
            end
        else
            Wait(500) -- Reduce CPU usage when not displaying
        end
    end
end)

end
