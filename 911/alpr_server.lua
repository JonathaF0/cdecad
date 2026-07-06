do
    local Config = Cad911Config
    if not Config or not Config.ALPR or not Config.ALPR.Enabled then return end

    local ALPR = Config.ALPR

-- ═══════════════════════════════════════════════════════════════════
-- ALPR CAMERAS - SERVER
-- Owns the placed-camera list (persisted in resource KVP), keeps a
-- flagged-plate cache pulled from the CAD, and turns a flagged plate
-- seen by a camera into an auto-911 call via /api/fivem/911.
-- ═══════════════════════════════════════════════════════════════════

    -- Base CAD URL: trailing slash and /api stripped, full paths appended below
    local CadUrl = GetConvar('CDE_CAD_API_URL', ''):gsub('/$', ''):gsub('/[Aa][Pp][Ii]$', '')
    local ApiKey = GetConvar('CDE_CAD_API_KEY', '')
    local CommunityId = GetConvar('CDE_CAD_COMMUNITY_ID', '')

-- ─── Helpers ─────────────────────────────────────────────────────────

    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local function base64Encode(data)
        return ((data:gsub('.', function(x)
            local r, b = '', x:byte()
            for i = 8, 1, -1 do r = r .. (b % 2^i - b % 2^(i-1) > 0 and '1' or '0') end
            return r
        end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
            if #x < 6 then return '' end
            local c = 0
            for i = 1, 6 do c = c + (x:sub(i,i) == '1' and 2^(6-i) or 0) end
            return b64chars:sub(c+1, c+1)
        end) .. ({ '', '==', '=' })[#data % 3 + 1])
    end

    local function DebugLog(msg)
        if Config.Debug then
            print('[cad-alpr] ' .. tostring(msg))
        end
    end

    local function NormalizePlate(plate)
        if not plate then return '' end
        return (tostring(plate):gsub('%s', '')):upper()
    end

    local function CadPost(endpoint, payload, cb)
        if CadUrl == '' then
            DebugLog('CDE_CAD_API_URL not set - cannot POST /' .. endpoint)
            return
        end
        local url  = CadUrl .. '/api/fivem/' .. endpoint
        local body = json.encode(payload)
        PerformHttpRequest(url, function(statusCode, response)
            local ok, data = pcall(json.decode, response or '')
            if cb then cb(statusCode, ok and data or nil) end
            if statusCode >= 400 then
                print(('[cad-alpr] API error %d on /%s: %s'):format(statusCode, endpoint, response or 'no body'))
            end
        end, 'POST', body, {
            ['Content-Type'] = 'application/json',
            ['x-api-key']    = ApiKey,
            ['x-payload']    = base64Encode(body),
        })
    end

    local function CadGet(endpoint, cb)
        if CadUrl == '' then return end
        PerformHttpRequest(CadUrl .. '/api/fivem/' .. endpoint, function(statusCode, response)
            local ok, data = pcall(json.decode, response or '')
            if cb then cb(statusCode, ok and data or nil) end
        end, 'GET', '', {
            ['Content-Type'] = 'application/json',
            ['x-api-key']    = ApiKey,
        })
    end

    local function IsOnDutyLEO(src)
        local ok, res = pcall(function()
            return exports['CDECAD']:IsPlayerOnDutyLEO(src)
        end)
        if ok and res ~= nil then
            return res and true or false
        end
        return true  -- duty module absent → don't hard-block
    end

-- ─── Flagged-plate cache (pulled from the CAD, refreshed on a timer) ─

    local flaggedCache = {}          -- [PLATE] = { flags = {...}, alertLevel = 'caution'|'alert' }
    local flaggedCacheCount = 0
    local flaggedCacheGeneratedAt = nil

    local function RebuildFlaggedCache()
        if CadUrl == '' then
            print('^1[cad-alpr] CDE_CAD_API_URL is empty - ALPR cannot load flagged plates.^7')
            return
        end
        local url = CadUrl .. '/api/civilian/fivem-flagged-plates?communityId=' .. CommunityId
        PerformHttpRequest(url, function(statusCode, responseText)
            if statusCode ~= 200 or not responseText or responseText == '' then
                print(('[cad-alpr] Flagged-plate cache refresh FAILED (status %s). Cache unchanged.'):format(tostring(statusCode)))
                return
            end
            local ok, data = pcall(json.decode, responseText)
            if not ok or not data or not data.success or type(data.plates) ~= 'table' then
                print('[cad-alpr] Flagged-plate cache refresh: bad response payload')
                return
            end
            local newCache, count = {}, 0
            for _, entry in ipairs(data.plates) do
                local plate = NormalizePlate(entry.plate)
                if plate ~= '' then
                    newCache[plate] = {
                        flags = entry.flags or {},
                        alertLevel = entry.alertLevel or 'caution',
                    }
                    count = count + 1
                end
            end
            flaggedCache = newCache
            flaggedCacheCount = count
            flaggedCacheGeneratedAt = data.generatedAt or os.date('!%Y-%m-%dT%H:%M:%SZ')
            print(('[cad-alpr] Flagged-plate cache rebuilt: %d plates'):format(count))
        end, 'GET', '', {
            ['Content-Type'] = 'application/json',
            ['x-api-key'] = ApiKey,
        })
    end

-- ─── Camera store (persisted in resource KVP) ───────────────────────

    local KVP_KEY = 'cdecad_alpr_cameras'
    local cameras = {}   -- array of { id, x, y, z, heading, label, postal, placedBy }
    local nextId = 1

    local function SaveCameras()
        SetResourceKvp(KVP_KEY, json.encode({ nextId = nextId, cameras = cameras }))
    end

    local function LoadCameras()
        local raw = GetResourceKvpString(KVP_KEY)
        if not raw or raw == '' then return end
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' and type(data.cameras) == 'table' then
            cameras = data.cameras
            nextId  = data.nextId or (#cameras + 1)
        end
    end

    local function BroadcastCameras(target)
        TriggerClientEvent('cdecad-alpr:sync', target or -1, cameras)
    end

-- ─── Hotlist (plate watch list) - persisted in KVP ──────────────────

    local HOTLIST_KEY = 'cdecad_alpr_hotlist'
    local hotlist = {}   -- [PLATE] = { reason, addedBy, at }

    local function SaveHotlist()
        SetResourceKvp(HOTLIST_KEY, json.encode(hotlist))
    end

    local function LoadHotlist()
        local raw = GetResourceKvpString(HOTLIST_KEY)
        if not raw or raw == '' then return end
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' then hotlist = data end
    end

-- ─── CAD sync: mirror the camera list into the CAD (web ALPR panel) ─

    local function SyncCamerasToCad()
        CadPost('alpr/cameras/sync', { cameras = cameras }, function(status)
            if status ~= 200 then
                DebugLog('Camera sync to CAD failed: ' .. tostring(status))
            end
        end)
    end

    -- Persist + broadcast + CAD-sync after any camera mutation.
    local function CommitCameras()
        SaveCameras()
        BroadcastCameras()
        SyncCamerasToCad()
    end

-- ─── Hit plumbing: severity gate, officer alerts, CAD hit record ────

    local function FindCamera(camId)
        for _, c in ipairs(cameras) do
            if c.id == camId then return c end
        end
        return nil
    end

    -- Severity override: set from the in-game panel, persisted in KVP
    local SEVERITY_KEY = 'cdecad_alpr_severity'
    local severityOverride = nil

    local function CurrentSeverity()
        return severityOverride or ALPR.MinAlertLevel or 'caution'
    end

    local function LoadSeverity()
        local raw = GetResourceKvpString(SEVERITY_KEY)
        if raw == 'caution' or raw == 'alert' then severityOverride = raw end
    end

    local function BroadcastMeta(target)
        TriggerClientEvent('cdecad-alpr:meta', target or -1, { severity = CurrentSeverity() })
    end

    -- AlertFlags allow-list wins when non-empty; otherwise the severity level
    -- ('caution' = all flags, 'alert' = stolen/BOLO/warrant only)
    local function PassesSeverity(hit)
        if type(ALPR.AlertFlags) == 'table' and #ALPR.AlertFlags > 0 then
            for _, f in ipairs(hit.flags or {}) do
                local fu = tostring(f):upper()
                for _, want in ipairs(ALPR.AlertFlags) do
                    if fu:find(tostring(want):upper(), 1, true) then return true end
                end
            end
            return false
        end
        if CurrentSeverity() == 'alert' then
            return hit.alertLevel == 'alert'
        end
        return true
    end

    -- Alert on-duty LEOs; falls back to everyone if LEOOnly is off or the export fails
    local function AlertOfficers(payload)
        local A = ALPR.Alerts
        if not A or not A.Enabled then return end
        if A.LEOOnly then
            local ok, units = pcall(function()
                return exports['CDECAD']:GetOnDutyLEOUnits()
            end)
            if ok and type(units) == 'table' then
                for _, id in ipairs(units) do
                    TriggerClientEvent('cdecad-alpr:hitAlert', id, payload)
                end
                return
            end
        end
        TriggerClientEvent('cdecad-alpr:hitAlert', -1, payload)
    end

    -- Pick which client shoots the hit photo: nearest non-offender, LEOs first.
    -- The offender's view never switches. Returns src, povAllowed
    local function PickPhotoReporter(cam, plate, fallbackSrc)
        local camPos = vector3(cam.x, cam.y, cam.z)

        -- Offender = player driving the flagged vehicle
        local offenderSrc = nil
        for _, pid in ipairs(GetPlayers()) do
            local src = tonumber(pid)
            if src then
                local ped = GetPlayerPed(src)
                local veh = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
                if veh ~= 0
                    and NormalizePlate(GetVehicleNumberPlateText(veh)) == plate
                    and GetPedInVehicleSeat(veh, -1) == ped then
                    offenderSrc = src
                    break
                end
            end
        end

        local range = (ALPR.ClientActiveRange or 200.0) * 1.5
        local bestLeo, bestLeoD = nil, math.huge
        local bestAny, bestAnyD = nil, math.huge
        for _, pid in ipairs(GetPlayers()) do
            local src = tonumber(pid)
            if src and src ~= offenderSrc then
                local ped = GetPlayerPed(src)
                if ped and ped ~= 0 then
                    local d = #(GetEntityCoords(ped) - camPos)
                    if d <= range then
                        if d < bestAnyD then bestAny, bestAnyD = src, d end
                        if IsOnDutyLEO(src) and d < bestLeoD then bestLeo, bestLeoD = src, d end
                    end
                end
            end
        end

        local pick = bestLeo or bestAny
        if pick then return pick, true end
        return offenderSrc or fallbackSrc, false
    end

    -- Record the hit on the CAD. A returned screenshot token gives a client a
    -- single-use upload URL; clients never hold the API key
    local function RecordHit(cam, data, incidentNumber, reporterSrc)
        CadPost('alpr/hit', {
            camId       = cam.id,
            cameraName  = (cam.name and cam.name ~= '') and cam.name or (cam.label or ''),
            plate       = data.plate,
            kind        = data.kind,
            flags       = data.flags,
            alertLevel  = data.alertLevel,
            speed       = data.speed,
            speedLimit  = cam.speedLimit,
            location    = cam.label,
            coordinates = { x = cam.x, y = cam.y, z = cam.z },
            incidentNumber = incidentNumber,
            screenshots = {
                enabled        = (ALPR.Screenshots and ALPR.Screenshots.Enabled) or false,
                retentionHours = (ALPR.Screenshots and ALPR.Screenshots.RetentionHours) or 24,
            },
        }, function(status, res)
            if status == 201 and res and res.screenshotToken and reporterSrc then
                local shooter, povAllowed = PickPhotoReporter(cam, data.plate, reporterSrc)
                if shooter then
                    print(('[cad-alpr] Hit recorded - requesting scene photo from %s (%s)'):format(
                        GetPlayerName(shooter) or tostring(shooter),
                        povAllowed and 'camera POV' or 'own view - offender/no other unit nearby'))
                    TriggerClientEvent('cdecad-alpr:takeScreenshot', shooter,
                        {
                            main  = CadUrl .. '/api/alpr-upload/' .. res.screenshotToken,
                            plate = res.plateToken and (CadUrl .. '/api/alpr-upload/' .. res.plateToken) or nil,
                        },
                        -- Camera info for the POV shot and overlay; os.date is server-only
                        {
                            x = cam.x, y = cam.y, z = cam.z,
                            heading = cam.heading,
                            name = (cam.name and cam.name ~= '') and cam.name or (cam.label or ('Camera #' .. cam.id)),
                            id = cam.id,
                            plate = data.plate,
                            ts = os.date('%Y-%m-%d %H:%M:%S'),
                            pov = povAllowed,
                        })
                end
            elseif status == 201 then
                -- Hit stored but no upload token returned
                print('[cad-alpr] Hit recorded but the CAD returned no screenshot token - redeploy the CAD backend (or screenshots are disabled).')
            else
                print(('[cad-alpr] Hit record failed (status %s) - this hit will be missing from the web panel history.'):format(tostring(status)))
            end
        end)
    end

    -- Echo client photo outcomes to the server console
    RegisterNetEvent('cdecad-alpr:photoResult')
    AddEventHandler('cdecad-alpr:photoResult', function(result)
        local src = source
        print(('[cad-alpr] photo result from %s: %s'):format(
            GetPlayerName(src) or tostring(src), tostring(result):sub(1, 200)))
    end)

-- ─── Camera management events ───────────────────────────────────────

    RegisterNetEvent('cdecad-alpr:place')
    AddEventHandler('cdecad-alpr:place', function(cam)
        local src = source
        if ALPR.RequireOnDutyLEO and not IsOnDutyLEO(src) then
            TriggerClientEvent('chat:addMessage', src, { args = { '^1[ALPR]', 'Only on-duty LEOs can place cameras.' } })
            return
        end
        if type(cam) ~= 'table' or not cam.x or not cam.y or not cam.z then return end

        -- Sanitize the requested prop against the allow-list; unknown/missing = default
        local propModel = (ALPR.Prop and ALPR.Prop.Model) or nil
        if cam.prop and ALPR.Prop and type(ALPR.Prop.Models) == 'table' then
            for _, m in ipairs(ALPR.Prop.Models) do
                if m == cam.prop then propModel = cam.prop break end
            end
        end

        local entry = {
            id       = nextId,
            x        = cam.x + 0.0,
            y        = cam.y + 0.0,
            z        = cam.z + 0.0,
            heading  = (cam.heading or 0.0) + 0.0,
            label    = tostring(cam.label or 'Unknown'),
            postal   = tostring(cam.postal or ''),
            prop     = propModel,
            placedBy = GetPlayerName(src) or ('Player ' .. src),
        }
        nextId = nextId + 1
        cameras[#cameras + 1] = entry
        CommitCameras()
        TriggerClientEvent('chat:addMessage', src, {
            args = { '^2[ALPR]', ('Camera #%d placed at %s.'):format(entry.id, entry.label) }
        })
        DebugLog(('Camera #%d placed by %s at %s'):format(entry.id, entry.placedBy, entry.label))
    end)

    RegisterNetEvent('cdecad-alpr:remove')
    AddEventHandler('cdecad-alpr:remove', function(coords)
        local src = source
        if ALPR.RequireOnDutyLEO and not IsOnDutyLEO(src) then
            TriggerClientEvent('chat:addMessage', src, { args = { '^1[ALPR]', 'Only on-duty LEOs can remove cameras.' } })
            return
        end
        if type(coords) ~= 'table' or not coords.x then return end

        local bestIdx, bestDist = nil, 12.0  -- must be within 12m of a camera
        for i, c in ipairs(cameras) do
            local dx, dy = c.x - coords.x, c.y - coords.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < bestDist then bestIdx, bestDist = i, d end
        end
        if not bestIdx then
            TriggerClientEvent('chat:addMessage', src, { args = { '^1[ALPR]', 'No camera within range to remove. Stand next to one.' } })
            return
        end
        local removed = table.remove(cameras, bestIdx)
        CommitCameras()
        TriggerClientEvent('chat:addMessage', src, {
            args = { '^2[ALPR]', ('Removed camera #%d (%s).'):format(removed.id, removed.label) }
        })
    end)

    -- ─── Camera management: name / toggle / speed limit / move ──────────

    local function LEOGate(src, action)
        if ALPR.RequireOnDutyLEO and not IsOnDutyLEO(src) then
            TriggerClientEvent('chat:addMessage', src, { args = { '^1[ALPR]', 'Only on-duty LEOs can ' .. action .. ' cameras.' } })
            return false
        end
        return true
    end

    RegisterNetEvent('cdecad-alpr:name')
    AddEventHandler('cdecad-alpr:name', function(camId, text)
        local src = source
        if not LEOGate(src, 'rename') then return end
        local cam = FindCamera(tonumber(camId))
        if not cam then
            TriggerClientEvent('chat:addMessage', src, { args = { '^1[ALPR]', 'No such camera.' } })
            return
        end
        cam.name = tostring(text or ''):sub(1, 60)
        CommitCameras()
        TriggerClientEvent('chat:addMessage', src, {
            args = { '^2[ALPR]', ('Camera #%d named "%s".'):format(cam.id, cam.name) }
        })
    end)

    RegisterNetEvent('cdecad-alpr:toggle')
    AddEventHandler('cdecad-alpr:toggle', function(camId)
        local src = source
        if not LEOGate(src, 'toggle') then return end
        local cam = FindCamera(tonumber(camId))
        if not cam then
            TriggerClientEvent('chat:addMessage', src, { args = { '^1[ALPR]', 'No such camera.' } })
            return
        end
        cam.enabled = (cam.enabled == false) and true or false
        CommitCameras()
        TriggerClientEvent('chat:addMessage', src, {
            args = { '^2[ALPR]', ('Camera #%d is now %s.'):format(cam.id, cam.enabled and 'ENABLED' or 'DISABLED') }
        })
    end)

    -- Flip a camera 180°; prop, blip, and detection cone follow the stored heading
    RegisterNetEvent('cdecad-alpr:flip')
    AddEventHandler('cdecad-alpr:flip', function(camId)
        local src = source
        if not LEOGate(src, 'flip') then return end
        local cam = FindCamera(tonumber(camId))
        if not cam then
            TriggerClientEvent('chat:addMessage', src, { args = { '^1[ALPR]', 'No such camera.' } })
            return
        end
        cam.heading = ((cam.heading or 0.0) + 180.0) % 360.0
        CommitCameras()
        TriggerClientEvent('chat:addMessage', src, {
            args = { '^2[ALPR]', ('Camera #%d flipped 180° - now reading the other direction.'):format(cam.id) }
        })
    end)

    RegisterNetEvent('cdecad-alpr:speed')
    AddEventHandler('cdecad-alpr:speed', function(camId, mph)
        local src = source
        if not LEOGate(src, 'configure') then return end
        local cam = FindCamera(tonumber(camId))
        if not cam then
            TriggerClientEvent('chat:addMessage', src, { args = { '^1[ALPR]', 'No such camera.' } })
            return
        end
        local lim = tonumber(mph)
        if lim and lim > 0 then
            cam.speedLimit = math.floor(lim)
            TriggerClientEvent('chat:addMessage', src, {
                args = { '^2[ALPR]', ('Camera #%d speed enforcement: %d mph.'):format(cam.id, cam.speedLimit) }
            })
        else
            cam.speedLimit = nil
            TriggerClientEvent('chat:addMessage', src, {
                args = { '^2[ALPR]', ('Camera #%d speed enforcement OFF.'):format(cam.id) }
            })
        end
        CommitCameras()
    end)

    RegisterNetEvent('cdecad-alpr:move')
    AddEventHandler('cdecad-alpr:move', function(payload)
        local src = source
        if not LEOGate(src, 'move') then return end
        if type(payload) ~= 'table' or not payload.id or not payload.x then return end
        local cam = FindCamera(tonumber(payload.id))
        if not cam then
            TriggerClientEvent('chat:addMessage', src, { args = { '^1[ALPR]', 'No such camera.' } })
            return
        end
        cam.x       = payload.x + 0.0
        cam.y       = payload.y + 0.0
        cam.z       = payload.z + 0.0
        cam.heading = (payload.heading or cam.heading or 0.0) + 0.0
        cam.label   = tostring(payload.label or cam.label or 'Unknown')
        cam.postal  = tostring(payload.postal or cam.postal or '')
        -- Keep the existing prop unless a valid new one was picked
        if payload.prop and type(ALPR.Prop.Models) == 'table' then
            for _, m in ipairs(ALPR.Prop.Models) do
                if m == payload.prop then cam.prop = payload.prop break end
            end
        end
        CommitCameras()
        TriggerClientEvent('chat:addMessage', src, {
            args = { '^2[ALPR]', ('Camera #%d moved to %s.'):format(cam.id, cam.label) }
        })
    end)

    -- On-demand flagged-plate cache rebuild (LEO)
    RegisterNetEvent('cdecad-alpr:refresh')
    AddEventHandler('cdecad-alpr:refresh', function()
        local src = source
        if not LEOGate(src, 'refresh plates for') then return end
        RebuildFlaggedCache()
        TriggerClientEvent('chat:addMessage', src, {
            args = { '^2[ALPR]', 'Flagged-plate cache refreshing from the CAD - new stolen/BOLO markings apply in a few seconds.' }
        })
    end)

    -- Toggle the live severity filter from the in-game panel
    RegisterNetEvent('cdecad-alpr:severity')
    AddEventHandler('cdecad-alpr:severity', function()
        local src = source
        if not LEOGate(src, 'configure') then return end
        severityOverride = CurrentSeverity() == 'alert' and 'caution' or 'alert'
        SetResourceKvp(SEVERITY_KEY, severityOverride)
        BroadcastMeta()
        TriggerClientEvent('chat:addMessage', src, {
            args = { '^2[ALPR]', severityOverride == 'alert'
                and 'Alert filter: SERIOUS ONLY (stolen / BOLO / warrant).'
                or 'Alert filter: ALL FLAGS (every flagged plate fires).' }
        })
    end)

    -- ─── Plate hotlist: /alpr watch add|rm|list ──────────────────────────

    RegisterNetEvent('cdecad-alpr:watch')
    AddEventHandler('cdecad-alpr:watch', function(action, plate, reason)
        local src = source
        if not LEOGate(src, 'manage the hotlist for') then return end
        action = tostring(action or 'list'):lower()
        local cleanPlate = NormalizePlate(plate)

        if action == 'add' then
            if cleanPlate == '' then
                TriggerClientEvent('chat:addMessage', src, { args = { '^1[ALPR]', 'Usage: watch add <plate> [reason]' } })
                return
            end
            hotlist[cleanPlate] = {
                reason = tostring(reason or ''):sub(1, 120),
                addedBy = GetPlayerName(src) or ('Player ' .. src),
                at = os.time(),
            }
            SaveHotlist()
            TriggerClientEvent('chat:addMessage', src, {
                args = { '^2[ALPR]', ('Plate %s added to the hotlist. Any camera that sees it will alert.'):format(cleanPlate) }
            })
        elseif action == 'rm' or action == 'remove' then
            if cleanPlate == '' or not hotlist[cleanPlate] then
                TriggerClientEvent('chat:addMessage', src, { args = { '^1[ALPR]', 'Plate not on the hotlist.' } })
                return
            end
            hotlist[cleanPlate] = nil
            SaveHotlist()
            TriggerClientEvent('chat:addMessage', src, {
                args = { '^2[ALPR]', ('Plate %s removed from the hotlist.'):format(cleanPlate) }
            })
        else -- list
            local n = 0
            for p, e in pairs(hotlist) do
                n = n + 1
                TriggerClientEvent('chat:addMessage', src, {
                    args = { '^3[ALPR]', ('  %s - %s (by %s)'):format(p, e.reason ~= '' and e.reason or 'no reason', e.addedBy or '?') }
                })
            end
            if n == 0 then
                TriggerClientEvent('chat:addMessage', src, { args = { '^3[ALPR]', 'Hotlist is empty. watch add <plate> [reason]' } })
            end
        end
    end)

    RegisterNetEvent('cdecad-alpr:clear')
    AddEventHandler('cdecad-alpr:clear', function()
        local src = source
        -- Clearing all cameras is an admin action
        if src ~= 0 and not IsPlayerAceAllowed(src, 'command.alprcam') and not IsOnDutyLEO(src) then
            TriggerClientEvent('chat:addMessage', src, { args = { '^1[ALPR]', 'Not permitted.' } })
            return
        end
        local n = #cameras
        cameras = {}
        CommitCameras()
        TriggerClientEvent('chat:addMessage', src, { args = { '^2[ALPR]', ('Cleared %d cameras.'):format(n) } })
    end)

    RegisterNetEvent('cdecad-alpr:requestSync')
    AddEventHandler('cdecad-alpr:requestSync', function()
        BroadcastCameras(source)
        BroadcastMeta(source)
    end)

-- ─── Plate seen by a camera → flag check → auto-911 ─────────────────

    local callCooldown = {}  -- [camId..':'..PLATE] = os.time()

    RegisterNetEvent('cdecad-alpr:plateSeen')
    AddEventHandler('cdecad-alpr:plateSeen', function(camId, plate, speedMph)
        local src = source
        local cleanPlate = NormalizePlate(plate)
        if cleanPlate == '' or not camId then return end

        -- Server-authoritative camera lookup (coords, enabled, speed limit)
        local cam = FindCamera(camId)
        if not cam or cam.enabled == false then return end

        speedMph = tonumber(speedMph)

        -- Classify the read: hotlist beats CAD flags beats speed
        local kind, flags, alertLevel
        local hot = hotlist[cleanPlate]
        local hit = flaggedCache[cleanPlate]
        local speeding = cam.speedLimit and speedMph and speedMph > cam.speedLimit

        if hot then
            kind = 'hotlist'
            flags = { 'HOTLIST' .. ((hot.reason and hot.reason ~= '') and (': ' .. hot.reason) or '') }
            alertLevel = 'alert'
        elseif hit and PassesSeverity(hit) then
            kind = 'flag'
            flags = hit.flags or {}
            alertLevel = hit.alertLevel or 'caution'
        elseif speeding then
            kind = 'speed'
            flags = { ('SPEEDING %d IN %d ZONE'):format(math.floor(speedMph), math.floor(cam.speedLimit)) }
            alertLevel = 'caution'
        else
            -- Flagged but below the severity filter: log once per cooldown window
            if hit then
                local fkey = 'f:' .. tostring(camId) .. ':' .. cleanPlate
                local fnow = os.time()
                if not callCooldown[fkey] or (fnow - callCooldown[fkey]) >= ALPR.CallCooldownSeconds then
                    callCooldown[fkey] = fnow
                    print(('[cad-alpr] plate %s seen at camera #%s is flagged (%s) but below the severity filter (%s) - not escalating. Toggle in /%s panel.'):format(
                        cleanPlate, tostring(camId), table.concat(hit.flags or {}, ', '), CurrentSeverity(), ALPR.Command or 'alpr'))
                end
            end
            return -- clean or below the severity filter
        end

        -- One escalation per (camera, plate) per cooldown window; dedups across clients
        local key = tostring(camId) .. ':' .. cleanPlate
        local now = os.time()
        if callCooldown[key] and (now - callCooldown[key]) < ALPR.CallCooldownSeconds then
            return
        end
        callCooldown[key] = now

        local camName = (cam.name and cam.name ~= '') and cam.name or (cam.label or ('Camera #' .. cam.id))
        local flagStr = table.concat(flags, ', ')

        print(('[cad-alpr] %s hit: plate %s at camera #%d (%s) - %s'):format(
            kind:upper(), cleanPlate, camId, camName, flagStr
        ))

        -- Bump the camera's hit counter (shown in the in-game panel)
        cam.hits = (cam.hits or 0) + 1
        SaveCameras()
        BroadcastCameras()

        -- Direct alert to on-duty LEOs: chat + flashing blip + sound
        AlertOfficers({
            camId = cam.id, cameraName = camName, plate = cleanPlate,
            kind = kind, flags = flags,
            x = cam.x, y = cam.y, z = cam.z,
        })

        -- Auto-911, then record the hit on the CAD with the incident number
        local callType, priority, description
        if kind == 'speed' then
            callType    = ALPR.SpeedCallType or 'ALPR Speed'
            priority    = 'normal'
            description = ('Plate %s clocked at %d mph in a %d mph zone (%s)'):format(
                cleanPlate, math.floor(speedMph), math.floor(cam.speedLimit), camName)
        else
            callType    = ALPR.CallType
            priority    = (alertLevel == 'alert') and 'high' or 'normal'
            description = ('ALPR %s on plate %s - %s'):format(
                kind == 'hotlist' and 'HOTLIST hit' or 'flag',
                cleanPlate, flagStr ~= '' and flagStr or 'flagged in CAD')
        end

        local hitData = { plate = cleanPlate, kind = kind, flags = flags, alertLevel = alertLevel, speed = speedMph }

        CadPost('911', {
            callType    = callType,
            callerName  = ALPR.CallerName,
            location    = cam.label ~= '' and cam.label or 'ALPR Camera',
            postal      = cam.postal,
            coordinates = { x = cam.x, y = cam.y, z = cam.z },
            description = description,
            priority    = priority,
            source      = 'cctv',
        }, function(status, res)
            local incidentNumber = (status == 201 and res and res.incidentNumber) or nil
            if incidentNumber then
                print(('[cad-alpr] Auto-911 created: %s'):format(incidentNumber))
            end
            -- Record the hit regardless of 911 success
            RecordHit(cam, hitData, incidentNumber, src)
        end)
    end)

-- ─── Cooldown cleanup ───────────────────────────────────────────────

    CreateThread(function()
        while true do
            Wait(300000)  -- 5 min
            local now = os.time()
            for k, t in pairs(callCooldown) do
                if (now - t) > ALPR.CallCooldownSeconds * 2 then
                    callCooldown[k] = nil
                end
            end
        end
    end)

-- ─── Admin console/status command ───────────────────────────────────

    RegisterCommand('alprstatus', function(source)
        local msg = ('%d cameras placed | flagged-plate cache: %d plates (generated %s)'):format(
            #cameras, flaggedCacheCount, tostring(flaggedCacheGeneratedAt or 'never')
        )
        if source > 0 then
            TriggerClientEvent('chat:addMessage', source, { args = { '^3[ALPR]', msg } })
        else
            print('[cad-alpr] ' .. msg)
        end
    end, false)

    RegisterCommand('alprrefresh', function(source)
        if source ~= 0 and not IsPlayerAceAllowed(source, 'command.alprrefresh') then return end
        print('[cad-alpr] Manual flagged-plate cache refresh requested')
        RebuildFlaggedCache()
    end, true)

-- ─── Startup ────────────────────────────────────────────────────────

    AddEventHandler('onResourceStart', function(resource)
        if resource ~= GetCurrentResourceName() then return end
        LoadCameras()
        LoadHotlist()
        LoadSeverity()
        SetTimeout(3000, function()
            RebuildFlaggedCache()
            BroadcastCameras()
            BroadcastMeta()
            SyncCamerasToCad()
        end)
        if not ApiKey or ApiKey == '' then
            print('^1[cad-alpr] Config API key is empty - ALPR auto-911 calls will fail with 401.^7')
        end
    end)

    CreateThread(function()
        local ms = (ALPR.CacheRefreshMinutes or 60) * 60 * 1000
        while true do
            Wait(ms)
            RebuildFlaggedCache()
        end
    end)

    -- Apply queued camera edits from the CAD web panel every 30s, through the
    -- same commit path as in-game edits
    CreateThread(function()
        while true do
            Wait(30000)
            CadGet('alpr/commands', function(status, data)
                if status ~= 200 or not data or not data.success
                    or type(data.commands) ~= 'table' or #data.commands == 0 then
                    return
                end
                local applied = 0
                for _, cmd in ipairs(data.commands) do
                    local cam = FindCamera(tonumber(cmd.camId))
                    if cam and type(cmd.changes) == 'table' then
                        local ch = cmd.changes
                        if ch.enabled ~= nil then
                            cam.enabled = ch.enabled and true or false
                            applied = applied + 1
                        end
                        if ch.speedLimit ~= nil then
                            local lim = tonumber(ch.speedLimit)
                            cam.speedLimit = (lim and lim > 0) and math.floor(lim) or nil
                            applied = applied + 1
                        end
                        if type(ch.name) == 'string' then
                            cam.name = ch.name:sub(1, 60)
                            applied = applied + 1
                        end
                    end
                end
                if applied > 0 then
                    CommitCameras()
                    print(('[cad-alpr] Applied %d camera edit(s) from the CAD web panel'):format(applied))
                end
            end)
        end
    end)

    print(('[cad-alpr] ALPR server loaded (RequireOnDutyLEO=%s, radius=%.0fm)'):format(
        tostring(ALPR.RequireOnDutyLEO), ALPR.CameraRadius
    ))
end
