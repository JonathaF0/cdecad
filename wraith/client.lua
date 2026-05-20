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

-- /cdetestlock [plate] — fires wk:onPlateLocked from the client exactly as
-- Wraith would, so we can prove whether the issue is upstream (Wraith/LuxArt
-- isn't emitting the event) or in our server handler.
RegisterCommand('cdetestlock', function(source, args)
    local plate = args[1] or 'TEST123'
    print(('[CDE-Wraith] CLIENT firing TriggerServerEvent("wk:onPlateLocked", "front", "%s", 0)'):format(plate))
    TriggerServerEvent('wk:onPlateLocked', 'front', plate, 0)
end, false)

-- /cdetestscan [plate] — same but for the scan event
RegisterCommand('cdetestscan', function(source, args)
    local plate = args[1] or 'TEST456'
    print(('[CDE-Wraith] CLIENT firing TriggerServerEvent("wk:onPlateScanned", "front", "%s", 0)'):format(plate))
    TriggerServerEvent('wk:onPlateScanned', 'front', plate, 0)
end, false)

-- =============================================================================
-- LEGACY CLIENT BRIDGE (no-op on wk_wars2x v1.3.1+)
-- =============================================================================
-- wk_wars2x v1.3.1+ fires `wk:onPlateLocked` / `wk:onPlateScanned` via
-- TriggerServerEvent directly, so the server receives them without any
-- client involvement. These local handlers are a fallback for older builds
-- that fire the events as client-local TriggerEvent. Server-side cooldowns
-- + the server-authoritative player/emergency filter make double-fire safe.

AddEventHandler('wk:onPlateLocked', function(cam, plate, index)
    if not plate or plate == '' then return end
    TriggerServerEvent('wk:onPlateLocked', cam, plate, index)
end)

AddEventHandler('wk:onPlateScanned', function(cam, plate, index)
    if not plate or plate == '' then return end
    TriggerServerEvent('wk:onPlateScanned', cam, plate, index)
end)

-- =============================================================================
-- RECEIVE PLATE RESULTS FROM SERVER
-- =============================================================================

-- Client-side emergency-vehicle filter for scans. GetVehicleClass is client-only
-- in FiveM so the server can't run this check; the officer's client always has
-- the scanned vehicle streamed in (they're looking at it), making this the
-- right place to do it. Class 18 = Emergency.
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

    -- Suppress display for emergency-class vehicles on the scan path.
    -- Locks bypass this because the officer explicitly requested the lookup.
    if data.cached and Config.PlateReader.IgnoreEmergencyVehicles and data.plate then
        if ScannedVehicleIsEmergency(data.plate) then
            return
        end
    end

    -- Show chat message
    if Config.Display.ShowChat then
        ShowChatResult(data, cam)
    end

    -- Show NUI popup (but not for low-key CLEAN cached scans — chat line is enough).
    local isCleanScan = data.cached and data.alertLevel == 'none'
    if Config.Display.ShowPopup and data.found and not isCleanScan then
        ShowNUIResult(data, cam)
    end

    -- Show ox_lib notification
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

    -- Cached scan-hits don't have vehicle/owner data — emit a compact alert line.
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

    SetNuiFocus(false, false) -- Don't steal mouse focus

    -- Auto-hide after duration
    if Config.Display.DisplayDuration > 0 then
        -- Cancel any existing hide timer
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

    -- Determine notification type based on alert level
    local notifType = 'success'
    if data.alertLevel == 'caution' then
        notifType = 'warning'
    elseif data.alertLevel == 'alert' then
        notifType = 'error'
    end

    -- Cached scan hit: short notification with flags only.
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
-- NUI CALLBACKS
-- =============================================================================

RegisterNUICallback('closePlateResult', function(data, cb)
    HideNUIResult()
    cb('ok')
end)

-- =============================================================================
-- KEY BINDING TO DISMISS
-- =============================================================================

-- Press Backspace to dismiss the plate result popup
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
