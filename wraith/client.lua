do
    local Config = WraithConfig
    if not Config or not Config.Enabled then return end

print('[CDE-Wraith] Client script LOADED (build with /cdetestlock and /cdetestscan)')

local isDisplaying = false
local hideTimer = nil
local pendingPopup = nil


RegisterCommand('cdetestlock', function(source, args)
    local plate = args[1] or 'TEST123'
    print(('[CDE-Wraith] CLIENT firing TriggerServerEvent("wk:onPlateLocked", "front", "%s", 0)'):format(plate))
    TriggerServerEvent('wk:onPlateLocked', 'front', plate, 0)
end, false)

RegisterCommand('cdetestscan', function(source, args)
    local plate = args[1] or 'TEST456'
    print(('[CDE-Wraith] CLIENT firing TriggerServerEvent("wk:onPlateScanned", "front", "%s", 0)'):format(plate))
    TriggerServerEvent('wk:onPlateScanned', 'front', plate, 0)
end, false)


local recentLockForward = {}

local function MarkLockForwarded(cam, cleanPlate)
    recentLockForward[(cam or '?') .. ':' .. cleanPlate] = GetGameTimer()
end

local function LockRecentlyForwarded(cam, cleanPlate)
    local t = recentLockForward[(cam or '?') .. ':' .. cleanPlate]
    return t ~= nil and (GetGameTimer() - t) < 5000
end


local function WkArgs(a, b, c)
    if type(a) == 'table' then
        return a.cam or a.camera or a.antenna or a.ant, a.plate, a.index
    end
    return a, b, c
end

AddEventHandler('wk:onPlateLocked', function(a, b, c)
    local cam, plate, index = WkArgs(a, b, c)
    if not plate or plate == '' then return end
    print(('[CDE-Wraith] bridging client-local wk:onPlateLocked (%s) %s to server'):format(tostring(cam), plate))
    MarkLockForwarded(cam, plate:gsub('%s', ''):upper())
    TriggerServerEvent('wk:onPlateLocked', cam, plate, index)
end)

AddEventHandler('wk:onPlateScanned', function(a, b, c)
    local cam, plate, index = WkArgs(a, b, c)
    if not plate or plate == '' then return end
    TriggerServerEvent('wk:onPlateScanned', cam, plate, index)
end)


if not (Config.SeamlessLock and Config.SeamlessLock.Enabled == false) then
    CreateThread(function()
        Wait(4000)
        if GetResourceState('wk_wars2x') ~= 'started' then return end

        local SL = Config.SeamlessLock or {}
        local wk = exports['wk_wars2x']

        local function callWk(name, cam)
            local ok, res = pcall(function() return wk[name](wk, cam) end)
            return ok, res
        end

        local function candidateList(override, ...)
            local list = {}
            if type(override) == 'string' and override ~= '' then list[#list + 1] = override end
            for _, n in ipairs({ ... }) do list[#list + 1] = n end
            return list
        end

        local function resolveExport(list)
            for _, name in ipairs(list) do
                if (callWk(name, 'front')) then return name end
            end
            return nil
        end

        local lockGetter = resolveExport(candidateList(SL.LockExport,
            'GetCamLocked', 'GetPlateLocked', 'IsCamLocked', 'IsPlateLocked', 'GetAntennaLocked'))
        local plateGetter = resolveExport(candidateList(SL.PlateExport,
            'GetPlate', 'GetCamPlate', 'GetCurrentPlate', 'GetScannedPlate'))
        local lockedPlateGetter = nil
        if not (lockGetter and plateGetter) then
            lockedPlateGetter = resolveExport(candidateList(SL.LockedPlateExport, 'GetLockedPlate'))
        end

        if not lockedPlateGetter and not (lockGetter and plateGetter) then
            print('[CDE-Wraith] Seamless lock: the running wk_wars2x exposes none of the known reader exports. ' ..
                'Real radar locks cannot be auto-detected on this build - use /cdelockfront + /cdelockrear (bindable), ' ..
                'or set Config.SeamlessLock.LockExport / PlateExport to your build\'s export names ' ..
                '(the server console lists the exports it found at startup).')
            return
        end

        if lockedPlateGetter then
            print(('[CDE-Wraith] Seamless lock: polling wk_wars2x export %s'):format(lockedPlateGetter))
        else
            print(('[CDE-Wraith] Seamless lock: polling wk_wars2x exports %s + %s'):format(lockGetter, plateGetter))
        end

        local pollMs = tonumber(SL.PollMs) or 250
        local lastLocked = { front = false, rear = false }
        local cams = { 'front', 'rear' }

        while true do
            Wait(pollMs)
            for _, cam in ipairs(cams) do
                local locked, plate

                if lockedPlateGetter then
                    local ok, p = callWk(lockedPlateGetter, cam)
                    if ok and type(p) == 'string' and p:gsub('%s', '') ~= '' then
                        locked, plate = true, p
                    else
                        locked = false
                    end
                else
                    local ok, raw = callWk(lockGetter, cam)
                    locked = ok and (raw == true or raw == 1)
                    if locked then
                        local okP, p = callWk(plateGetter, cam)
                        if okP and type(p) == 'string' then plate = p end
                    end
                end

                if locked and not lastLocked[cam] then
                    local clean = plate and plate:gsub('%s', ''):upper() or ''
                    if clean ~= '' then
                        lastLocked[cam] = true
                        if not LockRecentlyForwarded(cam, clean) then
                            MarkLockForwarded(cam, clean)
                            print(('[CDE-Wraith] Seamless lock detected (%s): %s'):format(cam, clean))
                            TriggerServerEvent('wk:onPlateLocked', cam, plate, 0)
                        end
                    end
                elseif not locked then
                    lastLocked[cam] = false
                end
            end
        end
    end)
end


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

    if not data.cached then
        print(('[CDE-Wraith] lock result received (%s) %s found=%s'):format(
            tostring(cam), tostring(data.plate), tostring(data.found)))
    end

    if data.cached and Config.PlateReader.IgnoreEmergencyVehicles and data.plate then
        if ScannedVehicleIsEmergency(data.plate) then
            return
        end
    end

    SendNUIMessage({ action = 'readerScan', data = data, cam = cam })

    if Config.Display.ShowChat then
        ShowChatResult(data, cam)
    end

    local isCleanScan = data.cached and data.alertLevel == 'none'
    local wantPopup = Config.Display.ShowPopup
        and ((not data.cached) or (data.found and not isCleanScan))
    if wantPopup then
        if not IsNuiFocused() then
            ShowNUIResult(data, cam)
        else
            print('[CDE-Wraith] popup deferred - another NUI holds focus; it will show when focus clears')
            pendingPopup = { data = data, cam = cam, queuedAt = GetGameTimer() }
        end
    end

    if Config.Notifications.UseOxLib then
        ShowOxLibNotification(data, cam)
    end
end)

CreateThread(function()
    while true do
        Wait(250)
        if pendingPopup then
            if (GetGameTimer() - pendingPopup.queuedAt) > 15000 then
                print('[CDE-Wraith] deferred popup dropped after 15s - another NUI held focus the whole time')
                pendingPopup = nil
            elseif not IsNuiFocused() then
                local p = pendingPopup
                pendingPopup = nil
                ShowNUIResult(p.data, p.cam)
            end
        end
    end
end)


function ShowChatResult(data, cam)
    local plate = data.plate or 'UNKNOWN'

    if not data.found then
        TriggerEvent('chat:addMessage', {
            args = { string.format(Config.Display.ChatNotFoundFormat, plate) }
        })
        return
    end

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


function ShowNUIResult(data, cam)
    isDisplaying = true

    SendNUIMessage({
        action = 'showPlateResult',
        data = data,
        cam = cam,
    })


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


if Config.Reader and Config.Reader.Enabled then
    local readerVisible = false

    local designsLoaded = false
    RegisterNetEvent('cde-wraith:plateDesigns')
    AddEventHandler('cde-wraith:plateDesigns', function(payload)
        if type(payload) ~= 'table' then return end
        designsLoaded = true
        SendNUIMessage({
            action  = 'readerDesigns',
            designs = payload.designs or {},
            byPlate = payload.byPlate or {},
        })
    end)
    CreateThread(function()
        Wait(3000)
        if not designsLoaded then
            TriggerServerEvent('cde-wraith:getPlateDesigns')
        end
    end)

    local readerCmd = Config.Reader.Command or 'reader'
    RegisterCommand(readerCmd, function(_, args)
        local sub = (args and args[1] or ''):lower()
        if sub == 'move' or sub == 'edit' then
            if not readerVisible then
                readerVisible = true
                SendNUIMessage({ action = 'readerShow' })
            end
            SendNUIMessage({ action = 'readerEdit' })
            SetNuiFocus(true, true)
            TriggerEvent('chat:addMessage', {
                args = { '^3[ALPR]', 'Drag the title bar to move, corner handle to resize. Click DONE (or Esc) to save.' }
            })
            return
        end
        readerVisible = not readerVisible
        SendNUIMessage({ action = readerVisible and 'readerShow' or 'readerHide' })
        if readerVisible and not designsLoaded then
            TriggerServerEvent('cde-wraith:getPlateDesigns')
        end
        TriggerEvent('chat:addMessage', {
            args = { '^3[ALPR]', readerVisible and 'Plate reader console ON.' or 'Plate reader console OFF.' }
        })
    end, false)
    TriggerEvent('chat:addSuggestion', '/' .. readerCmd, 'Toggle the in-car ALPR reader console')
    TriggerEvent('chat:addSuggestion', '/' .. readerCmd .. ' move', 'Move / resize the reader console')

    RegisterCommand(readerCmd .. 'move', function()
        ExecuteCommand(readerCmd .. ' move')
    end, false)
    TriggerEvent('chat:addSuggestion', '/' .. readerCmd .. 'move', 'Move / resize the ALPR reader console')

    RegisterCommand(readerCmd .. 'reset', function()
        SendNUIMessage({ action = 'readerResetLayout' })
        TriggerEvent('chat:addMessage', { args = { '^3[ALPR]', 'Reader console layout reset to default.' } })
    end, false)
    TriggerEvent('chat:addSuggestion', '/' .. readerCmd .. 'reset', 'Reset the ALPR reader console to its default position')

    RegisterNUICallback('readerEditDone', function(_, cb)
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'readerEditOff' })
        cb('ok')
    end)
    RegisterKeyMapping(readerCmd, 'Toggle ALPR reader console', 'keyboard', '')

    local readerSeen = {}

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


do
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
        local best, bestDist = nil, ((Config.LockFallback and Config.LockFallback.Range) or 35.0)
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
        TriggerServerEvent('cde-wraith:lockWkDisplay', cam)
    end

    RegisterCommand('cdelockfront', function() LockDirection('front') end, false)
    RegisterCommand('cdelockrear',  function() LockDirection('rear')  end, false)
    RegisterKeyMapping('cdelockfront', 'CAD: lock plate ahead (front antenna)', 'keyboard', '')
    RegisterKeyMapping('cdelockrear',  'CAD: lock plate behind (rear antenna)', 'keyboard', '')
    TriggerEvent('chat:addSuggestion', '/cdelockfront', 'Lock the plate of the vehicle ahead into the CAD')
    TriggerEvent('chat:addSuggestion', '/cdelockrear', 'Lock the plate of the vehicle behind into the CAD')
end


RegisterNUICallback('closePlateResult', function(data, cb)
    HideNUIResult()
    cb('ok')
end)


CreateThread(function()
    while true do
        Wait(0)
        if isDisplaying then
            if IsControlJustReleased(0, 177) then
                HideNUIResult()
            end
        else
            Wait(500)
        end
    end
end)

end
