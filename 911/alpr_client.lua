do
    local Config = Cad911Config
    if not Config or not Config.ALPR or not Config.ALPR.Enabled then return end

    local ALPR = Config.ALPR


    local cameras = {}
    local blips   = {}
    local props   = {}
    local renderedSig = {}
    local alprMeta = {}

    local placing = false
    local placeObj = nil
    local placeIdx = 1
    local placeHeadingOffset = 0.0
    local placeFwd  = 2.5
    local placeSide = 0.0
    local placeUp   = 0.0
    local placeSpeed = 1.0
    local placeMoveId = nil


    local function StreetName(coords)
        local s, c = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
        local street = GetStreetNameFromHashKey(s) or ''
        local cross  = GetStreetNameFromHashKey(c) or ''
        if cross ~= '' then return street .. ' / ' .. cross end
        return street ~= '' and street or 'Unknown Location'
    end

    local function ZoneName(coords)
        local label = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
        if label and label ~= 'NULL' and label ~= '' then return label end
        return ''
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

    local function NormalizePlate(p)
        if not p then return '' end
        return (p:gsub('%s', '')):upper()
    end


    local function ClearVisual(camId)
        if blips[camId] then RemoveBlip(blips[camId]); blips[camId] = nil end
        if props[camId] and DoesEntityExist(props[camId]) then
            DeleteEntity(props[camId]); props[camId] = nil
        end
    end

    local function SpawnProp(cam)
        if not ALPR.Prop.Enabled then return end
        local modelName = cam.prop or ALPR.Prop.Model
        local model = GetHashKey(modelName)
        if not IsModelInCdimage(model) or not IsModelValid(model) then
            print(('[cad-alpr] Prop model "%s" is not a valid game model - no camera prop spawned. Set Config.ALPR.Prop.Model to a valid prop.'):format(tostring(modelName)))
            return
        end
        RequestModel(model)
        local tries = 0
        while not HasModelLoaded(model) and tries < 200 do Wait(10); tries = tries + 1 end
        if not HasModelLoaded(model) then
            print(('[cad-alpr] Prop model "%s" failed to load in time - no camera prop spawned.'):format(tostring(modelName)))
            return
        end
        local obj = CreateObject(model, cam.x, cam.y, cam.z, false, false, false)
        SetEntityHeading(obj, cam.heading or 0.0)
        FreezeEntityPosition(obj, true)
        SetModelAsNoLongerNeeded(model)
        props[cam.id] = obj
    end

    local function RenderCamera(cam)
        ClearVisual(cam.id)
        if ALPR.Blip.Enabled then
            local blip = AddBlipForCoord(cam.x, cam.y, cam.z)
            SetBlipSprite(blip, ALPR.Blip.Sprite)
            SetBlipColour(blip, cam.enabled == false and 40 or ALPR.Blip.Color)
            SetBlipScale(blip, ALPR.Blip.Scale)
            SetBlipAsShortRange(blip, true)
            SetBlipRotation(blip, math.floor(((cam.heading or 0.0) + (ALPR.Prop and ALPR.Prop.LensOffset or 0.0)) % 360.0 + 0.5))
            ShowHeadingIndicatorOnBlip(blip, true)
            local label = (cam.name and cam.name ~= '') and cam.name or ALPR.Blip.Label
            if cam.enabled == false then label = label .. ' (off)' end
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(label)
            EndTextCommandSetBlipName(blip)
            blips[cam.id] = blip
        end
        SpawnProp(cam)
    end

    local function CamSig(c)
        return string.format('%.1f|%.1f|%.1f|%.0f|%s|%s|%s',
            c.x or 0, c.y or 0, c.z or 0, c.heading or 0,
            tostring(c.prop), tostring(c.name), tostring(c.enabled ~= false))
    end

    RegisterNetEvent('cdecad-alpr:sync')
    AddEventHandler('cdecad-alpr:sync', function(list)
        list = list or {}
        local incoming = {}
        for _, c in ipairs(list) do incoming[c.id] = true end
        local toClear = {}
        for camId in pairs(renderedSig) do if not incoming[camId] then toClear[camId] = true end end
        for camId in pairs(blips) do if not incoming[camId] then toClear[camId] = true end end
        for camId in pairs(props) do if not incoming[camId] then toClear[camId] = true end end
        for camId in pairs(toClear) do ClearVisual(camId); renderedSig[camId] = nil end
        cameras = list
        for _, cam in ipairs(list) do
            local sig = CamSig(cam)
            if renderedSig[cam.id] ~= sig then
                ClearVisual(cam.id)
                RenderCamera(cam)
                renderedSig[cam.id] = sig
            end
        end
    end)

    RegisterNetEvent('cdecad-alpr:meta')
    AddEventHandler('cdecad-alpr:meta', function(meta)
        if type(meta) == 'table' then alprMeta = meta end
    end)

    CreateThread(function()
        Wait(1500)
        TriggerServerEvent('cdecad-alpr:requestSync')
    end)

    AddEventHandler('onResourceStop', function(res)
        if res ~= GetCurrentResourceName() then return end
        placing = false
        if placeObj and DoesEntityExist(placeObj) then DeleteEntity(placeObj) end
        local ids = {}
        for camId in pairs(blips) do ids[camId] = true end
        for camId in pairs(props) do ids[camId] = true end
        for camId in pairs(ids) do ClearVisual(camId) end
    end)


    local function ChatMsg(text)
        TriggerEvent('chat:addMessage', { args = { '^3[ALPR]', text } })
    end

    local function IsLocalOnDutyLEO()
        local ok, res = pcall(function()
            return exports[GetCurrentResourceName()]:IsOnDutyLEO()
        end)
        if ok and res ~= nil then return res == true end
        return true
    end

    local function ResolvePropChoice(choice)
        local models = ALPR.Prop.Models or { ALPR.Prop.Model }
        if not choice or choice == '' then return ALPR.Prop.Model end
        local n = tonumber(choice)
        if n then
            if models[n] then return models[n] end
            return nil, ('Camera #%s is not in the list. Use /%s props to see options.'):format(choice, ALPR.Command)
        end
        local lc = choice:lower()
        for _, m in ipairs(models) do
            if m:lower() == lc then return m end
        end
        return nil, ('Unknown camera model "%s". Use /%s props to see options.'):format(choice, ALPR.Command)
    end

    local function SubmitPlacement(x, y, z, heading, model, moveId)
        local coords = vector3(x, y, z)
        local label = StreetName(coords)
        local zone  = ZoneName(coords)
        if zone ~= '' then label = label .. ', ' .. zone end
        local payload = {
            x = x, y = y, z = z,
            heading = heading,
            label   = label,
            postal  = PostalCode(coords),
            prop    = model,
        }
        if moveId then
            payload.id = moveId
            TriggerServerEvent('cdecad-alpr:move', payload)
        else
            TriggerServerEvent('cdecad-alpr:place', payload)
        end
    end


    local function propModels() return ALPR.Prop.Models or { ALPR.Prop.Model } end
    local function placeModelName() return propModels()[placeIdx] or ALPR.Prop.Model end

    local function loadModelSync(name)
        local h = GetHashKey(name)
        if not IsModelValid(h) or not IsModelInCdimage(h) then return nil end
        RequestModel(h)
        local t = 0
        while not HasModelLoaded(h) and t < 200 do Wait(10); t = t + 1 end
        if not HasModelLoaded(h) then return nil end
        return h
    end

    local function destroyPreview()
        if placeObj and DoesEntityExist(placeObj) then DeleteEntity(placeObj) end
        placeObj = nil
    end

    local function spawnPreview()
        destroyPreview()
        local h = loadModelSync(placeModelName())
        if not h then return end
        local p = GetEntityCoords(PlayerPedId())
        placeObj = CreateObject(h, p.x, p.y, p.z, false, false, false)
        SetEntityAlpha(placeObj, 160, false)
        SetEntityCollision(placeObj, false, false)
        FreezeEntityPosition(placeObj, true)
        SetModelAsNoLongerNeeded(h)
    end

    local function cycleModel(dir)
        local n = #propModels()
        if n == 0 then return end
        placeIdx = ((placeIdx - 1 + dir) % n) + 1
        spawnPreview()
    end

    local function hudText(x, y, text, scale, center)
        SetTextFont(4)
        SetTextScale(scale, scale)
        SetTextColour(255, 255, 255, 255)
        SetTextOutline()
        SetTextCentre(center == true)
        SetTextEntry('STRING')
        AddTextComponentString(text)
        DrawText(x, y)
    end

    local function drawPlacementHud()
        DrawRect(0.5, 0.900, 0.46, 0.185, 0, 0, 0, 170)
        hudText(0.5, 0.818, placeMoveId and ('MOVING ALPR CAMERA #' .. placeMoveId) or 'ALPR CAMERA PLACEMENT', 0.48, true)
        local m = propModels()
        hudText(0.5, 0.849, ('Model %d/%d:  %s      Speed %.2fx'):format(placeIdx, #m, placeModelName(), placeSpeed), 0.38, true)
        hudText(0.5, 0.879, '[ Arrows ]  Move        [ PgUp / PgDn ]  Height', 0.32, true)
        hudText(0.5, 0.903, '[ , ] / [ . ]  Model      [ Scroll ]  Rotate', 0.32, true)
        hudText(0.5, 0.927, '[ - ] / [ + ]  Speed      [ Enter ]  Place', 0.32, true)
        hudText(0.5, 0.951, '[ Backspace ]  Cancel', 0.32, true)
    end

    local function StartPlacement(startModel, moveId)
        if placing then ChatMsg('Already placing a camera - finish or cancel first.'); return end
        local m = propModels()
        placeIdx = 1
        local want = startModel or ALPR.Prop.Model
        for i, name in ipairs(m) do if name == want then placeIdx = i break end end
        placeHeadingOffset = 0.0
        placeFwd, placeSide, placeUp = 2.5, 0.0, 0.0
        placeSpeed = 1.0
        placeMoveId = moveId
        placing = true
        spawnPreview()
        CreateThread(function()
            while placing do
                Wait(0)
                local ped = PlayerPedId()
                local p = GetEntityCoords(ped)
                local fwd = GetEntityForwardVector(ped)
                local rx, ry = fwd.y, -fwd.x
                local tx = p.x + fwd.x * placeFwd + rx * placeSide
                local ty = p.y + fwd.y * placeFwd + ry * placeSide
                local found, gz = GetGroundZFor_3dCoord(tx, ty, p.z + 2.0, false)
                local tz = (found and gz or (p.z - 0.9)) + placeUp
                local heading = (GetEntityHeading(ped) + placeHeadingOffset) % 360.0

                if placeObj and DoesEntityExist(placeObj) then
                    SetEntityCoordsNoOffset(placeObj, tx, ty, tz, false, false, false)
                    SetEntityHeading(placeObj, heading)
                end

                DisableControlAction(0, 14, true)
                DisableControlAction(0, 15, true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)

                if IsRawKeyPressed(189) or IsRawKeyPressed(109) then placeSpeed = math.max(placeSpeed - 0.25, 0.25) end
                if IsRawKeyPressed(187) or IsRawKeyPressed(107) then placeSpeed = math.min(placeSpeed + 0.25, 4.0)  end
                local moveStep = 0.06 * placeSpeed
                local upStep   = 0.05 * placeSpeed

                if IsRawKeyDown(38) then placeFwd  = math.min(placeFwd  + moveStep, 12.0) end
                if IsRawKeyDown(40) then placeFwd  = math.max(placeFwd  - moveStep, 0.5)  end
                if IsRawKeyDown(39) then placeSide = math.min(placeSide + moveStep, 6.0)  end
                if IsRawKeyDown(37) then placeSide = math.max(placeSide - moveStep, -6.0) end
                if IsRawKeyDown(33) then placeUp   = math.min(placeUp   + upStep,   8.0)  end
                if IsRawKeyDown(34) then placeUp   = math.max(placeUp   - upStep,  -3.0)  end

                if IsRawKeyPressed(188) then cycleModel(-1) end
                if IsRawKeyPressed(190) then cycleModel(1)  end
                if IsDisabledControlJustPressed(0, 15) then placeHeadingOffset = placeHeadingOffset - 15.0 * placeSpeed end
                if IsDisabledControlJustPressed(0, 14) then placeHeadingOffset = placeHeadingOffset + 15.0 * placeSpeed end

                if IsControlJustPressed(0, 201) then
                    placing = false
                    destroyPreview()
                    SubmitPlacement(tx, ty, tz, heading, placeModelName(), placeMoveId)
                    placeMoveId = nil
                    break
                elseif IsControlJustPressed(0, 177) then
                    placing = false
                    destroyPreview()
                    placeMoveId = nil
                    ChatMsg('Placement cancelled.')
                    break
                end

                drawPlacementHud()
            end
        end)
    end

    local ShowPanel

    local function ShowSpeedMenu(camId)
        local options = {
            {
                title = 'Off - no speed enforcement',
                icon = 'ban',
                onSelect = function() TriggerServerEvent('cdecad-alpr:speed', camId, 0) end,
            },
        }
        for _, mph in ipairs(ALPR.SpeedOptions or { 25, 35, 45, 55, 65, 70, 80 }) do
            options[#options + 1] = {
                title = ('%d mph'):format(mph),
                icon = 'gauge-high',
                onSelect = function() TriggerServerEvent('cdecad-alpr:speed', camId, mph) end,
            }
        end
        lib.registerContext({
            id = 'cdecad_alpr_speed',
            title = ('Camera #%d - Speed Limit'):format(camId),
            menu = 'cdecad_alpr_cam',
            options = options,
        })
        lib.showContext('cdecad_alpr_speed')
    end

    local function ShowCameraMenu(camId)
        local cam
        for _, c in ipairs(cameras) do if c.id == camId then cam = c break end end
        if not cam then return end
        lib.registerContext({
            id = 'cdecad_alpr_cam',
            title = ('#%d - %s'):format(cam.id, (cam.name and cam.name ~= '') and cam.name or (cam.label or 'Camera')),
            menu = 'cdecad_alpr_panel',
            options = {
                {
                    title = 'Set Waypoint',
                    description = cam.label or '',
                    icon = 'location-dot',
                    onSelect = function() SetNewWaypoint(cam.x + 0.0, cam.y + 0.0) end,
                },
                {
                    title = (cam.enabled == false) and 'Enable Camera' or 'Disable Camera',
                    icon = 'power-off',
                    onSelect = function() TriggerServerEvent('cdecad-alpr:toggle', cam.id) end,
                },
                {
                    title = 'Flip Direction (180°)',
                    description = 'Turn the camera around if it reads the wrong way',
                    icon = 'rotate',
                    onSelect = function() TriggerServerEvent('cdecad-alpr:flip', cam.id) end,
                },
                {
                    title = 'Speed limit: ' .. (cam.speedLimit and (cam.speedLimit .. ' mph') or 'off'),
                    description = 'Pick a common value or turn enforcement off',
                    icon = 'gauge-high',
                    onSelect = function() ShowSpeedMenu(cam.id) end,
                },
                {
                    title = ('Hits: %d'):format(cam.hits or 0),
                    description = ('Placed by %s'):format(cam.placedBy or 'unknown'),
                    icon = 'video',
                },
            },
        })
        lib.showContext('cdecad_alpr_cam')
    end

    ShowPanel = function()
        if not lib or not lib.registerContext then
            ChatMsg('ox_lib context menus are unavailable on this server.')
            return
        end
        local pc = GetEntityCoords(PlayerPedId())
        local options = {}
        local sev = alprMeta.severity or 'caution'
        options[#options + 1] = {
            title = sev == 'alert' and 'Alert filter: SERIOUS ONLY' or 'Alert filter: ALL FLAGS',
            description = sev == 'alert'
                and 'Only stolen / BOLO / warrant plates fire. Select to switch to all flags.'
                or 'Every flagged plate fires (incl. expired reg / no insurance). Select to limit to serious only.',
            icon = 'filter',
            onSelect = function() TriggerServerEvent('cdecad-alpr:severity') end,
        }
        options[#options + 1] = {
            title = 'Refresh flagged plates',
            description = 'Pull the latest stolen/BOLO markings from the CAD now',
            icon = 'rotate',
            onSelect = function() TriggerServerEvent('cdecad-alpr:refresh') end,
        }
        for _, c in ipairs(cameras) do
            local dist = #(pc - vector3(c.x, c.y, c.z))
            options[#options + 1] = {
                title = ('#%d  %s'):format(c.id, (c.name and c.name ~= '') and c.name or (c.label or 'Camera')),
                description = ('%s · %.0fm · %d hits%s'):format(
                    (c.enabled == false) and 'DISABLED' or 'Active',
                    dist, c.hits or 0,
                    c.speedLimit and (' · limit ' .. c.speedLimit .. ' mph') or ''),
                icon = 'video',
                onSelect = function() ShowCameraMenu(c.id) end,
            }
        end
        if #cameras == 0 then
            options[#options + 1] = { title = 'No cameras placed', description = ('Use /%s place'):format(ALPR.Command) }
        end
        lib.registerContext({
            id = 'cdecad_alpr_panel',
            title = ('ALPR Cameras (%d)'):format(#cameras),
            options = options,
        })
        lib.showContext('cdecad_alpr_panel')
    end

    local function handleAlprCommand(source, args)
        local sub = (args[1] or 'place'):lower()
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)

        if sub == 'place' then
            if ALPR.RequireOnDutyLEO and not IsLocalOnDutyLEO() then
                ChatMsg('You must be on duty as an LEO to place cameras.')
                return
            end
            local model, err = ResolvePropChoice(args[2])
            if not model then ChatMsg(err); return end
            if ALPR.PlacementUI and ALPR.Prop.Enabled and #propModels() > 0 then
                StartPlacement(model)
            else
                SubmitPlacement(coords.x, coords.y, coords.z, GetEntityHeading(ped), model)
            end

        elseif sub == 'props' or sub == 'models' then
            ChatMsg('Camera models (use: /' .. ALPR.Command .. ' place <number>):')
            for i, m in ipairs(ALPR.Prop.Models or { ALPR.Prop.Model }) do
                ChatMsg(('  %d - %s%s'):format(i, m, m == ALPR.Prop.Model and ' (default)' or ''))
            end

        elseif sub == 'panel' then
            ShowPanel()

        elseif sub == 'name' then
            local id = tonumber(args[2])
            local text = table.concat(args, ' ', 3)
            if not id or text == '' then ChatMsg('Usage: /' .. ALPR.Command .. ' name <id> <name>'); return end
            TriggerServerEvent('cdecad-alpr:name', id, text)

        elseif sub == 'toggle' then
            local id = tonumber(args[2])
            if not id then ChatMsg('Usage: /' .. ALPR.Command .. ' toggle <id>'); return end
            TriggerServerEvent('cdecad-alpr:toggle', id)

        elseif sub == 'flip' then
            local id = tonumber(args[2])
            if not id then ChatMsg('Usage: /' .. ALPR.Command .. ' flip <id>'); return end
            TriggerServerEvent('cdecad-alpr:flip', id)

        elseif sub == 'refresh' then
            TriggerServerEvent('cdecad-alpr:refresh')

        elseif sub == 'speed' then
            local id = tonumber(args[2])
            if not id or not args[3] then ChatMsg('Usage: /' .. ALPR.Command .. ' speed <id> <mph|off>'); return end
            TriggerServerEvent('cdecad-alpr:speed', id, args[3])

        elseif sub == 'move' then
            local id = tonumber(args[2])
            if not id then ChatMsg('Usage: /' .. ALPR.Command .. ' move <id>'); return end
            local cam
            for _, c in ipairs(cameras) do if c.id == id then cam = c break end end
            if not cam then ChatMsg(('No camera #%d.'):format(id)); return end
            if ALPR.PlacementUI and ALPR.Prop.Enabled then
                StartPlacement(cam.prop, id)
            else
                SubmitPlacement(coords.x, coords.y, coords.z, GetEntityHeading(ped), cam.prop, id)
            end

        elseif sub == 'watch' then
            TriggerServerEvent('cdecad-alpr:watch', args[2], args[3], table.concat(args, ' ', 4))

        elseif sub == 'remove' or sub == 'delete' then
            TriggerServerEvent('cdecad-alpr:remove', { x = coords.x, y = coords.y, z = coords.z })

        elseif sub == 'clear' then
            TriggerServerEvent('cdecad-alpr:clear')

        elseif sub == 'list' then
            if #cameras == 0 then
                ChatMsg('No cameras placed.')
            else
                ChatMsg(('%d cameras:'):format(#cameras))
                for _, c in ipairs(cameras) do
                    local d = #(coords - vector3(c.x, c.y, c.z))
                    ChatMsg(('  #%d - %s (%.0fm)'):format(c.id, c.label or 'Unknown', d))
                end
            end

        else
            ChatMsg('Usage: /' .. ALPR.Command .. ' place [model#] | panel | props | name <id> <text> | toggle <id> | flip <id> | speed <id> <mph|off> | move <id> | watch add|rm|list | remove | list | clear')
        end
    end

    local cmdNames = { ALPR.Command }
    for _, a in ipairs(ALPR.CommandAliases or {}) do cmdNames[#cmdNames + 1] = a end
    for _, name in ipairs(cmdNames) do
        RegisterCommand(name, handleAlprCommand, false)
        TriggerEvent('chat:addSuggestion', '/' .. name, 'Manage ALPR cameras', {
            { name = 'action', help = 'place | panel | props | name | toggle | speed | move | watch | remove | list | clear' },
        })
    end


    if ALPR.Marker.Enabled then
        CreateThread(function()
            while true do
                local sleep = 1000
                if #cameras > 0 then
                    local pc = GetEntityCoords(PlayerPedId())
                    for _, cam in ipairs(cameras) do
                        local dist = #(pc - vector3(cam.x, cam.y, cam.z))
                        if dist < ALPR.Marker.DrawDistance then
                            sleep = 0
                            DrawMarker(2, cam.x, cam.y, cam.z + 1.2, 0, 0, 0, 0, 0, 0,
                                0.6, 0.6, 0.6, 255, 200, 0, 160, false, true, 2, false, nil, nil, false)
                        end
                    end
                end
                Wait(sleep)
            end
        end)
    end


    local function IsEmergencyClass(veh)
        return GetVehicleClass(veh) == 18
    end

    local function InCameraView(cam, vpos)
        if not ALPR.Directional then return true end
        local dx, dy = vpos.x - cam.x, vpos.y - cam.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 0.5 then return true end
        local h = math.rad((cam.heading or 0.0) + (ALPR.Prop and ALPR.Prop.LensOffset or 0.0))
        local fx, fy = -math.sin(h), math.cos(h)
        local dot = (dx / len) * fx + (dy / len) * fy
        return dot >= math.cos(math.rad((ALPR.FOV or 120.0) / 2))
    end

    local seen = {}
    local LOCAL_THROTTLE_MS = 20000

    CreateThread(function()
        while true do
            local sleep = ALPR.ScanInterval
            if #cameras > 0 then
                local pc = GetEntityCoords(PlayerPedId())
                local now = GetGameTimer()
                for _, cam in ipairs(cameras) do
                    local camPos = vector3(cam.x, cam.y, cam.z)
                    if cam.enabled ~= false and #(pc - camPos) <= ALPR.ClientActiveRange then
                        for _, veh in ipairs(GetGamePool('CVehicle')) do
                            local vpos = DoesEntityExist(veh) and GetEntityCoords(veh) or nil
                            if vpos and #(vpos - camPos) <= ALPR.CameraRadius and InCameraView(cam, vpos) then
                                local skip = false
                                if ALPR.IgnoreEmergencyVehicles and IsEmergencyClass(veh) then skip = true end
                                if not skip and ALPR.OnlyPlayerVehicles then
                                    local driver = GetPedInVehicleSeat(veh, -1)
                                    if not (driver ~= 0 and IsPedAPlayer(driver)) then skip = true end
                                end
                                if not skip then
                                    local plate = NormalizePlate(GetVehicleNumberPlateText(veh))
                                    if plate ~= '' then
                                        local key = cam.id .. ':' .. plate
                                        if not seen[key] or (now - seen[key]) > LOCAL_THROTTLE_MS then
                                            seen[key] = now
                                            local mph = math.floor(GetEntitySpeed(veh) * 2.236936)
                                            TriggerServerEvent('cdecad-alpr:plateSeen', cam.id, plate, mph)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            Wait(sleep)
        end
    end)

    CreateThread(function()
        while true do
            Wait(60000)
            local now = GetGameTimer()
            for k, t in pairs(seen) do
                if (now - t) > LOCAL_THROTTLE_MS * 2 then seen[k] = nil end
            end
        end
    end)


    RegisterNetEvent('cdecad-alpr:hitAlert')
    AddEventHandler('cdecad-alpr:hitAlert', function(data)
        if type(data) ~= 'table' then return end
        local A = ALPR.Alerts or {}
        local flagStr = table.concat(data.flags or {}, ', ')

        if A.Chat ~= false then
            TriggerEvent('chat:addMessage', {
                color = { 255, 60, 60 },
                args = { '^1[ALPR HIT]', ('%s | %s | %s'):format(
                    data.plate or '?', data.cameraName or ('Camera #' .. tostring(data.camId)), flagStr) }
            })
        end
        if A.Sound ~= false then
            PlaySoundFrontend(-1, 'CHALLENGE_UNLOCKED', 'HUD_AWARDS', true)
        end
        if A.Blip ~= false and data.x then
            local blip = AddBlipForCoord(data.x + 0.0, (data.y or 0.0) + 0.0, (data.z or 0.0) + 0.0)
            SetBlipSprite(blip, 161)
            SetBlipColour(blip, 1)
            SetBlipScale(blip, 1.2)
            SetBlipFlashes(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(('ALPR HIT: %s'):format(data.plate or ''))
            EndTextCommandSetBlipName(blip)
            SetTimeout((A.BlipDuration or 60) * 1000, function()
                if DoesBlipExist(blip) then RemoveBlip(blip) end
            end)
        end
    end)


    local warnedNoScreenshotBasic = false
    local capturing = false

    local function DrawCctvOverlay(info, mode)
        DrawRect(0.028, 0.045, 0.012, 0.02, 255, 40, 40, 220)
        local label = mode == 'plate' and 'PLATE CAM' or ''
        hudText(0.04, 0.032, ('REC   ALPR CAM #%s - %s %s'):format(
            tostring(info.id or '?'), tostring(info.name or ''), label), 0.38, false)
        hudText(0.82, 0.032, tostring(info.ts or ''), 0.38, false)
        hudText(0.028, 0.94, ('PLATE: %s'):format(tostring(info.plate or '')), 0.42, false)
    end

    local function ShootTo(url, label, cb)
        local responded = false
        local ok, err = pcall(function()
            exports['screenshot-basic']:requestScreenshotUpload(url, 'file', { encoding = 'jpg', quality = 0.85 }, function(res)
                responded = true
                local summary = tostring(res)
                if #summary > 160 then summary = summary:sub(1, 160) .. '…' end
                print(('[cad-alpr] %s upload response: %s'):format(label, summary))
                TriggerServerEvent('cdecad-alpr:photoResult', label .. ' upload response: ' .. summary)
            end)
        end)
        if not ok then
            print(('[cad-alpr] %s capture failed: %s'):format(label, tostring(err)))
            TriggerServerEvent('cdecad-alpr:photoResult', label .. ' capture error: ' .. tostring(err))
            if cb then cb(false) end
            return
        end
        SetTimeout(10000, function()
            if not responded then
                TriggerServerEvent('cdecad-alpr:photoResult',
                    label .. ': no response after 10s - upload blocked client-side (CAD CORS fix not deployed?) or URL unreachable from player')
            end
        end)
        if cb then
            SetTimeout(350, function() cb(true) end)
        end
    end

    local function CaptureAndUpload(urls, info)
        local SS = ALPR.Screenshots or {}
        local usePov = SS.CameraPOV ~= false
            and type(info) == 'table' and info.x ~= nil
            and info.pov ~= false
        local cam = nil
        local overlayMode = 'wide'

        local target = nil
        local wanted = NormalizePlate(type(info) == 'table' and info.plate or nil)
        if wanted ~= '' then
            for _, veh in ipairs(GetGamePool('CVehicle')) do
                if NormalizePlate(GetVehicleNumberPlateText(veh)) == wanted then target = veh break end
            end
        end

        capturing = true
        if usePov then
            ChatMsg(('Camera #%s hit - capturing scene photo, your view will switch for a second.'):format(tostring(info.id or '?')))
            cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
            SetCamCoord(cam, info.x + 0.0, info.y + 0.0, info.z + 0.4)
            if target and DoesEntityExist(target) then
                PointCamAtEntity(cam, target, 0.0, 0.0, 0.0, true)
                local dist = #(GetEntityCoords(target) - vector3(info.x, info.y, info.z))
                SetCamFov(cam, math.max(18.0, math.min(SS.POVFov or 55.0, dist * 1.1)))
            else
                local h = ((info.heading or 0.0) + (ALPR.Prop and ALPR.Prop.LensOffset or 0.0)) % 360.0
                SetCamRot(cam, -12.0, 0.0, h, 2)
                SetCamFov(cam, SS.POVFov or 55.0)
            end
            SetCamActive(cam, true)
            RenderScriptCams(true, false, 0, true, true)
        end

        CreateThread(function()
            while capturing do
                Wait(0)
                HideHudAndRadarThisFrame()
                if SS.Overlay ~= false and type(info) == 'table' then
                    DrawCctvOverlay(info, overlayMode)
                end
            end
        end)

        local function restore()
            if not capturing then return end
            capturing = false
            if cam then
                RenderScriptCams(false, false, 0, true, true)
                DestroyCam(cam, false)
            end
        end

        CreateThread(function()
            Wait(200)

            ShootTo(urls.main, 'wide shot', function(okMain)
                if not okMain or not urls.plate or not usePov
                    or not target or not DoesEntityExist(target) then
                    restore()
                    return
                end
                overlayMode = 'plate'
                local min = GetModelDimensions(GetEntityModel(target))
                local rear  = GetOffsetFromEntityInWorldCoords(target, 0.0, (min.y or -2.5) - 1.8, 0.35)
                local plate = GetOffsetFromEntityInWorldCoords(target, 0.0, (min.y or -2.5), 0.3)
                SetCamCoord(cam, rear.x, rear.y, rear.z)
                PointCamAtCoord(cam, plate.x, plate.y, plate.z)
                SetCamFov(cam, 30.0)
                CreateThread(function()
                    Wait(200)
                    ShootTo(urls.plate, 'plate close-up', function()
                        restore()
                    end)
                end)
            end)
        end)
    end

    RegisterNetEvent('cdecad-alpr:takeScreenshot')
    AddEventHandler('cdecad-alpr:takeScreenshot', function(urls, info)
        if type(urls) == 'string' then urls = { main = urls } end
        if type(urls) ~= 'table' or type(urls.main) ~= 'string' or urls.main == '' then return end
        if GetResourceState('screenshot-basic') ~= 'started' then
            if not warnedNoScreenshotBasic then
                warnedNoScreenshotBasic = true
                print('[cad-alpr] screenshot-basic is not running - ALPR hit photos are disabled. Add `ensure screenshot-basic` to server.cfg.')
                ChatMsg('Hit photo skipped: screenshot-basic is not running on this server.')
            end
            TriggerServerEvent('cdecad-alpr:photoResult', 'skipped - screenshot-basic not running')
            return
        end
        if capturing then
            TriggerServerEvent('cdecad-alpr:photoResult', 'skipped - capture already in progress')
            return
        end
        CaptureAndUpload(urls, info)
    end)

    print('[cad-alpr] ALPR client loaded (/' .. ALPR.Command .. ' - place, panel, watch, speed, move, …)')
end
