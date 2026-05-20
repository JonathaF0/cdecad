do
    local Config = ErsConfig
    if not Config or not Config.Enabled then return end

    Config.CADEndpoint = GetConvar('CDE_CAD_API_URL', '')
    Config.APIKey      = GetConvar('CDE_CAD_API_KEY', '')
-- server/main.lua
-- ERS Bridge for CDECAD — Server-side
-- Hooks into night_ers server events and pushes data to the CAD backend API.

local activeCallouts = {} -- Track active ERS callouts per player source
local activeTrafficStops = {} -- Track active traffic stop ersCalloutId per player source (for closing on pullover end)
local pendingTrafficStopPed = {} -- Track ped data from pullover NPC interaction (for pairing with vehicle)
local pendingTrafficStopLoc = {} -- Track location data from pullover NPC interaction
local trafficStopHandled = {} -- Dedup: tracks whether a traffic stop was already sent for this player's current pullover

-- ─── Helper: Build headers for CAD API requests ────────────────────────────
local function GetHeaders()
    return {
        ["Content-Type"]  = "application/json",
        ["x-api-key"]     = Config.APIKey,
    }
end

-- ─── Helper: Build API URL ─────────────────────────────────────────────────
local function GetApiUrl(path)
    return Config.CADEndpoint .. "/api/fivem/ers/" .. path
end

-- ─── Helper: Debug logging ─────────────────────────────────────────────────
local function DebugLog(msg)
    if Config.EnableDebug then
        print("[CDE-ERS] " .. msg)
    end
end

-- ─── Helper: Base64 encode (for x-payload fallback) ────────────────────────
local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64encode(data)
    return ((data:gsub('.', function(x)
        local r, b = '', x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
        return b64chars:sub(c + 1, c + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

-- ─── Helper: HTTP POST to CAD API ──────────────────────────────────────────
-- Sends the payload in both the body AND the x-payload header (base64).
-- This ensures delivery even when Cloudflare strips POST bodies from
-- non-browser user agents (FiveM's PerformHttpRequest).
local function PostToCAD(path, data, callback)
    local url = GetApiUrl(path)
    local jsonData = json.encode(data)

    DebugLog("POST " .. url .. " | Body: " .. jsonData)

    local headers = GetHeaders()
    headers["x-payload"] = base64encode(jsonData)

    PerformHttpRequest(url, function(statusCode, responseText, respHeaders)
        DebugLog("Response [" .. tostring(statusCode) .. "]: " .. tostring(responseText))

        if callback then
            local success = statusCode >= 200 and statusCode < 300
            local responseData = nil
            if responseText and responseText ~= "" then
                local ok, decoded = pcall(json.decode, responseText)
                if ok then responseData = decoded end
            end
            callback(success, responseData, statusCode)
        end
    end, "POST", jsonData, headers)
end

-- ─── Helper: HTTP GET from CAD API ─────────────────────────────────────────
local function GetFromCAD(path, callback)
    local url = GetApiUrl(path)
    local headers = GetHeaders()

    DebugLog("GET " .. url)

    PerformHttpRequest(url, function(statusCode, responseText, respHeaders)
        DebugLog("GET Response [" .. tostring(statusCode) .. "]: " .. tostring(responseText))

        if callback then
            local success = statusCode >= 200 and statusCode < 300
            local responseData = nil
            if responseText and responseText ~= "" then
                local ok, decoded = pcall(json.decode, responseText)
                if ok then responseData = decoded end
            end
            callback(success, responseData, statusCode)
        end
    end, "GET", "", headers)
end

-- ─── Helper: Get callout ID from calloutData ───────────────────────────────
local function GetCalloutId(calloutData)
    if not calloutData then return nil end
    -- ERS provides various identifiers; check PascalCase first, then camelCase
    return calloutData.CalloutId
        or calloutData.calloutId
        or calloutData.Id
        or calloutData.id
        or calloutData.callout_id
        or (calloutData.CalloutName or calloutData.calloutType) and (tostring(calloutData.CalloutName or calloutData.calloutType) .. "_" .. tostring(os.time()))
end

-- ─── Helper: Get player callSign ───────────────────────────────────────────
local function GetPlayerCallSign(source)
    local name = GetPlayerName(source)
    return name or ("Unit-" .. tostring(source))
end

-- ─── Helper: Get player Discord ID ───────────────────────────────────────────
-- Returns the raw numeric Discord ID (without the "discord:" prefix) so the
-- backend can cross-reference it against the active units table.
local function GetPlayerDiscordId(source)
    local id = GetPlayerIdentifierByType(source, 'discord')
    if id then
        -- Strip "discord:" prefix → return just the numeric ID
        return id:gsub("discord:", "")
    end
    return nil
end

-- ─── Helper: Map ERS service type ──────────────────────────────────────────
local function GetServiceType(calloutData)
    if not calloutData then return "police" end

    -- Check explicit service type field first
    local sType = calloutData.ServiceType or calloutData.serviceType or calloutData.service_type
    if type(sType) == "string" then
        sType = sType:lower()
        if sType == "police" or sType == "fire" or sType == "ambulance" or sType == "tow" then
            return sType
        end
    end

    -- Derive from CalloutUnitsRequired (ERS sends this for callouts)
    local units = calloutData.CalloutUnitsRequired
    if units then
        if units.policeRequired then return "police" end
        if units.fireRequired then return "fire" end
        if units.ambulanceRequired then return "ambulance" end
        if units.towRequired then return "tow" end
    end

    return "police"
end

-- ─── Helper: Map ERS priority ──────────────────────────────────────────────
local function GetPriority(calloutData)
    if not calloutData then return "medium" end
    local p = calloutData.Priority or calloutData.priority
    if p == 1 then return "low"
    elseif p == 2 then return "normal"
    elseif p == 3 then return "medium"
    elseif p == 4 then return "high"
    elseif p == 5 then return "critical"
    end
    return "medium"
end

-- ─── License status normalization ──────────────────────────────────────────
-- The new ERS uses string values like "VALID", "EXPIRED", "SUSPENDED",
-- "REVOKED", "NO LICENSE" plus oddities like "INTERNATIONAL LICENSE (VALID)"
-- and "REPORTED STOLEN (VALID)". Normalize to the CAD's enum.
local function NormalizeLicenseStatus(raw, isValidBool)
    if type(raw) == "string" and raw ~= "" then
        local up = raw:upper()
        if up == "VALID" or up == "INTERNATIONAL LICENSE (VALID)" then return "VALID" end
        if up == "REPORTED STOLEN (VALID)" or up == "REVOKED" then return "REVOKED" end
        if up == "EXPIRED" then return "EXPIRED" end
        if up == "SUSPENDED" then return "SUSPENDED" end
        if up == "NO LICENSE" or up == "NONE" or up == "N/A" then return "NONE" end
    end
    if isValidBool == true then return "VALID" end
    if isValidBool == false then return "NONE" end
    return nil
end

-- ─── Build civilian payload from pedData ───────────────────────────────────
-- Captures the full new-ERS pedData surface area: name, demographics, contact
-- info, profile picture, all five license types (Car/Bike/Boat/Pilot/Truck),
-- flags/markers, and MDT identifiers when night_shifts_mdt is running.
local function BuildCivilianPayload(pedData, ersCalloutId)
    if not pedData then return nil end

    return {
        ersCalloutId = ersCalloutId,
        -- Identity
        firstName      = pedData.FirstName or "Unknown",
        middleName     = pedData.MiddleName or nil,
        lastName       = pedData.LastName or "Doe",
        dateOfBirth    = pedData.DOB or nil,
        gender         = pedData.Gender or nil,
        race           = pedData.Nationality or nil,
        nationality    = pedData.Nationality or nil,
        profilePicture = pedData.ProfilePicture or nil,
        -- Address / contact
        address    = pedData.Address or nil,
        city       = pedData.City or nil,
        state      = pedData.State or nil,
        country    = pedData.Country or nil,
        postalCode = pedData.PostalCode or nil,
        phone      = pedData.Phone or pedData.PhoneNumber or nil,
        email      = pedData.Email or nil,
        -- Licenses — pass through raw + _Is_Valid so the route can normalize
        license_car            = pedData.License_Car or nil,
        license_car_is_valid   = pedData.License_Car_Is_Valid,
        license_bike           = pedData.License_Bike or nil,
        license_bike_is_valid  = pedData.License_Bike_Is_Valid,
        license_boat           = pedData.License_Boat or nil,
        license_boat_is_valid  = pedData.License_Boat_Is_Valid,
        license_pilot          = pedData.License_Pilot or nil,
        license_pilot_is_valid = pedData.License_Pilot_Is_Valid,
        license_truck          = pedData.License_Truck or nil,
        license_truck_is_valid = pedData.License_Truck_Is_Valid,
        -- Backward-compat aliases (drivers license summary)
        hasDriversLicense    = pedData.License_Car_Is_Valid or false,
        driversLicenseStatus = NormalizeLicenseStatus(pedData.License_Car, pedData.License_Car_Is_Valid),
        -- Notes / warrants
        flagsOrMarkers = pedData.FlagsOrMarkers or nil,
        -- MDT identifiers (only set when night_shifts_mdt is running)
        mdtCivilianId = pedData.mdtCivilianId or nil,
        mdtPersonalId = pedData.mdtPersonalId or nil,
        -- Existing ERS ped/civ identifiers
        civId = pedData.civId or pedData.id or nil,
        pedId = pedData.pedId or pedData.ped_id or nil,
    }
end

-- ─── Build vehicle payload from vehicleData ────────────────────────────────
-- Captures the full new-ERS vehicleData surface area including compliance
-- (mot, insurance, tax, stolen, bolo) and metadata (vehicle_class, secondary
-- color, picture URL) from the MDT-merged path.
local function BuildVehiclePayload(vehicleData, ersCalloutId)
    if not vehicleData then return nil end
    return {
        ersCalloutId = ersCalloutId,
        plate          = vehicleData.license_plate or vehicleData.plate or ("ERS" .. math.random(1000, 9999)),
        make           = vehicleData.make or vehicleData.brand or "Unknown",
        model          = vehicleData.model or "Unknown",
        color          = vehicleData.color or vehicleData.colour or "Unknown",
        colorSecondary = vehicleData.color_secondary or nil,
        year           = vehicleData.build_year or vehicleData.year or 2024,
        vehicleClass   = vehicleData.vehicle_class or nil,
        vehiclePictureUrl = vehicleData.vehicle_picture_url or nil,
        ownerName      = vehicleData.owner_name or nil,
        -- Compliance
        stolen         = vehicleData.stolen or false,
        mot            = vehicleData.mot,
        insurance      = vehicleData.insurance,
        tax            = vehicleData.tax,
        -- BOLO
        bolo           = vehicleData.bolo,
        boloDescription = vehicleData.bolo_description or nil,
    }
end

-- ========================================================================
-- ERS EVENT HANDLERS
-- ========================================================================

-- Register ALL ERS network events with RegisterNetEvent.
-- ERS c_functions.lua fires TriggerServerEvent for each of these.
-- Using RegisterNetEvent (not RegisterServerEvent) for consistency —
-- the callout events that WORK use RegisterNetEvent, so use it everywhere.
RegisterNetEvent("ErsIntegration::OnIsOfferedCallout")
RegisterNetEvent("ErsIntegration::OnAcceptedCalloutOffer")
RegisterNetEvent("ErsIntegration::OnArrivedAtCallout")
RegisterNetEvent("ErsIntegration::OnEndedACallout")
RegisterNetEvent("ErsIntegration::OnCalloutCompletedSuccesfully")
RegisterNetEvent("ErsIntegration::OnFirstNPCInteraction")
RegisterNetEvent("ErsIntegration::OnFirstVehicleInteraction")
RegisterNetEvent("ErsIntegration::OnToggleShift")
RegisterNetEvent("ErsIntegration::OnPullover")
RegisterNetEvent("ErsIntegration::OnPulloverEnded")
RegisterNetEvent("ErsIntegration::OnPursuitStarted")
RegisterNetEvent("ErsIntegration::OnPursuitEnded")

-- ─── OnIsOfferedCallout ────────────────────────────────────────────────────
-- Fires when ERS offers a callout to a player (before they accept/decline).
-- We log the offered callout's identity unconditionally so we can verify
-- whether ERS is actually offering OUR dispatch-created callout, vs picking
-- a different entry from the shared pool. This is the only way to diagnose
-- the "I dispatched X but the player got offered Y" class of bugs without
-- access to night_ers internals.
AddEventHandler("ErsIntegration::OnIsOfferedCallout", function(calloutData)
    local src = source
    local cd = calloutData or {}
    local cid = cd.CalloutId or cd.calloutId or cd.Id or cd.id or "?"
    local cname = cd.CalloutName or cd.calloutName or cd.calloutType or "?"
    local coords = cd.Coordinates or cd.coordinates
    local cx = coords and coords.x or "?"
    local cy = coords and coords.y or "?"
    print(string.format("[CDE-ERS] OFFERED -> player=%s | id=%s | name=%s | coords=(%s,%s)",
        tostring(src), tostring(cid), tostring(cname), tostring(cx), tostring(cy)))
end)

-- ─── OnAcceptedCalloutOffer ─────────────────────────────────────────────────
-- Fired when a player accepts an ERS callout offer.
AddEventHandler("ErsIntegration::OnAcceptedCalloutOffer", function(calloutData)
    local source = source
    DebugLog("OnAcceptedCalloutOffer RAW: " .. json.encode(calloutData or {}))

    local calloutId = GetCalloutId(calloutData)

    if not calloutId then
        DebugLog("OnAcceptedCalloutOffer: No callout ID found, skipping")
        return
    end

    -- Track the active callout for this player
    activeCallouts[tostring(source)] = calloutId
    DebugLog("Player " .. tostring(source) .. " accepted callout: " .. calloutId)

    -- Create CAD call
    if Config.CreateCallOnAccept then
        -- ERS uses PascalCase field names (CalloutName, Description, Coordinates, StreetName, etc.)
        local callType = calloutData.CalloutName or calloutData.calloutName or calloutData.calloutType or calloutData.type or "ERS Callout"
        local location = calloutData.StreetName or calloutData.Location or calloutData.location or calloutData.Address or calloutData.address or "Unknown"
        local postal   = calloutData.Postal or calloutData.postal or calloutData.PostalCode or ""

        -- Get coordinates from the callout data (ERS uses PascalCase "Coordinates")
        local coords = nil
        if calloutData.Coordinates then
            coords = calloutData.Coordinates
        elseif calloutData.coordinates then
            coords = calloutData.coordinates
        elseif calloutData.x and calloutData.y then
            coords = { x = calloutData.x, y = calloutData.y, z = calloutData.z or 0.0 }
        end

        PostToCAD("callout", {
            ersCalloutId = calloutId,
            callType     = callType,
            location     = location,
            postal       = postal,
            coordinates  = coords,
            description  = calloutData.Description or calloutData.description or calloutData.desc or "",
            priority     = GetPriority(calloutData),
            serviceType  = GetServiceType(calloutData),
        }, function(success, data)
            if success and data then
                DebugLog("Created CAD call: " .. tostring(data.incidentNumber))

                -- Auto-attach the accepting unit
                if Config.AttachUnitOnAccept then
                    PostToCAD("unit-attach", {
                        ersCalloutId = calloutId,
                        callSign     = GetPlayerCallSign(source),
                        discordId    = GetPlayerDiscordId(source),
                    })
                end

                -- NOTE: calloutData.FirstName/LastName is the 911 CALLER, not the
                -- suspect. Actual suspect NPCs arrive via OnFirstNPCInteraction
                -- (which requires forwarding code in night_ers/c_functions.lua).
                -- We skip auto-creating the caller as a civilian since it's not
                -- the person officers need to run in the system.
                if calloutData.FirstName and calloutData.LastName then
                    DebugLog("Callout caller: " .. calloutData.FirstName .. " " .. calloutData.LastName .. " (not creating as civilian — this is the 911 caller)")
                end
            end
        end)
    end
end)

-- ─── OnArrivedAtCallout ─────────────────────────────────────────────────────
-- Fired when a player arrives at the callout scene.
AddEventHandler("ErsIntegration::OnArrivedAtCallout", function(calloutData)
    local source = source
    DebugLog("OnArrivedAtCallout RAW: " .. json.encode(calloutData or {}))

    if not Config.UpdateOnArrival then return end

    local calloutId = activeCallouts[tostring(source)] or GetCalloutId(calloutData)
    if not calloutId then return end

    DebugLog("Player " .. tostring(source) .. " arrived at callout: " .. calloutId)

    PostToCAD("callout-arrived", {
        ersCalloutId = calloutId,
    })
end)

-- ─── OnEndedACallout ────────────────────────────────────────────────────────
-- Fired when an ERS callout ends (completed or abandoned).
AddEventHandler("ErsIntegration::OnEndedACallout", function(calloutData)
    local source = source
    DebugLog("OnEndedACallout RAW: " .. json.encode(calloutData or {}))

    if not Config.CloseCallOnEnd then return end

    local calloutId = activeCallouts[tostring(source)] or GetCalloutId(calloutData)
    if not calloutId then return end

    DebugLog("Callout ended: " .. calloutId)

    PostToCAD("callout-end", {
        ersCalloutId = calloutId,
    })

    -- Clean up tracking
    activeCallouts[tostring(source)] = nil
end)

-- ─── OnCalloutCompletedSuccesfully ──────────────────────────────────────────
-- Fired when an ERS callout is completed successfully.
AddEventHandler("ErsIntegration::OnCalloutCompletedSuccesfully", function(calloutData)
    local source = source
    DebugLog("OnCalloutCompletedSuccesfully RAW: " .. json.encode(calloutData or {}))
    local calloutId = activeCallouts[tostring(source)] or GetCalloutId(calloutData)
    if not calloutId then return end

    DebugLog("Callout completed successfully: " .. calloutId)

    if Config.CloseCallOnEnd then
        PostToCAD("callout-end", {
            ersCalloutId = calloutId,
        })
    end

    activeCallouts[tostring(source)] = nil
end)

-- ─── Helper: Build traffic stop payload and POST to CAD ──────────────────
-- Defined here (before event handlers that reference it) because Lua
-- ─── Helper: Get location data for a player ───────────────────────────────
-- Server-side coords are always available. Street name comes from client callback.
local pendingLocationCallbacks = {}

local function GetPlayerLocation(playerSource, callback)
    -- Get server-side coordinates immediately
    local coords = nil
    local playerPed = GetPlayerPed(playerSource)
    if playerPed and playerPed ~= 0 then
        local pos = GetEntityCoords(playerPed)
        if pos then
            coords = { x = pos.x, y = pos.y, z = pos.z }
        end
    end

    -- Request street name from client
    local key = tostring(playerSource)
    pendingLocationCallbacks[key] = function(clientLoc)
        pendingLocationCallbacks[key] = nil
        local loc = clientLoc or {}
        if not loc.coordinates and coords then
            loc.coordinates = coords
        end
        callback(loc)
    end

    TriggerClientEvent('ErsIntegration::RequestLocation', playerSource)

    -- Fallback: if client doesn't respond within 2 seconds, use coords only
    SetTimeout(2000, function()
        if pendingLocationCallbacks[key] then
            DebugLog("Location callback timeout for player " .. key .. ", using server coords only")
            pendingLocationCallbacks[key] = nil
            callback({ coordinates = coords })
        end
    end)
end

RegisterNetEvent('ErsIntegration::LocationResponse')
AddEventHandler('ErsIntegration::LocationResponse', function(locationData)
    local key = tostring(source)
    if pendingLocationCallbacks[key] then
        pendingLocationCallbacks[key](locationData)
    end
end)

-- ─── SendTrafficStop ──────────────────────────────────────────────────────
-- Builds and sends the traffic stop payload to the CAD API. Composes the
-- shared civilian + vehicle payload builders with the location + officer
-- context so the route gets every new-ERS field (License_Bike/Pilot/Truck,
-- ProfilePicture, FlagsOrMarkers, color_secondary, mot, vehicle_class,
-- bolo_description, mdt* identifiers, etc.).
local function SendTrafficStop(source, pedData, vehicleData, locationData)
    local loc = locationData or {}
    local civPayload = BuildCivilianPayload(pedData, nil) or {}
    local vehPayload = BuildVehiclePayload(vehicleData, nil) or {}
    civPayload.lastName = (pedData and (pedData.LastName)) or "Driver"

    local body = {
        -- Officer
        callSign    = GetPlayerCallSign(source),
        discordId   = GetPlayerDiscordId(source),
        -- Location
        location    = loc.location or nil,
        postal      = loc.postal or nil,
        coordinates = loc.coordinates or nil,
    }
    for k, v in pairs(civPayload) do body[k] = v end
    for k, v in pairs(vehPayload) do body[k] = v end
    body.ersCalloutId = nil -- traffic-stop endpoint assigns its own
    -- Legacy field aliases the route reads alongside the new ones.
    body.registration = vehicleData and vehicleData.tax or nil
    body.insurance    = vehicleData and vehicleData.insurance or nil

    PostToCAD("traffic-stop", body, function(success, data)
        if success and data then
            DebugLog("Traffic stop processed: " .. tostring(data.incidentNumber or "?") ..
                " | Civ: " .. tostring(data.civilianId or "?") ..
                " | Veh: " .. tostring(data.vehicleId or "?") ..
                " | ERS ID: " .. tostring(data.ersCalloutId or "?"))
            if data.ersCalloutId then
                activeTrafficStops[tostring(source)] = data.ersCalloutId
            end
        else
            DebugLog("Traffic stop failed")
        end
    end)
end

-- ─── HandleTrafficStop ────────────────────────────────────────────────────
-- Wrapper that resolves player location before sending.
-- If location data was provided (e.g. from client), uses it directly.
-- Otherwise, requests street name from client with server-side coord fallback.
local function HandleTrafficStop(playerSource, pedData, vehicleData, locationData)
    DebugLog("Processing traffic stop for player " .. tostring(playerSource))

    if locationData and locationData.location then
        SendTrafficStop(playerSource, pedData, vehicleData, locationData)
    else
        GetPlayerLocation(playerSource, function(loc)
            SendTrafficStop(playerSource, pedData, vehicleData, loc)
        end)
    end
end

-- ─── OnFirstNPCInteraction ──────────────────────────────────────────────────
-- ERS fires this as a global client function with context values:
--   "on_interaction", "on_aiming_at_ped", "on_pullover", "on_pursuit_start",
--   "on_pursuit_end", "on_pullover_end"
-- This is the PRIMARY way pullover/pursuit NPC data reaches us, since ERS
-- does NOT fire OnPullover as a global function (it's internal to c_functions.lua).
--
-- ERS may fire this EITHER:
--   a) Directly on server: TriggerEvent(..., source, pedData, context)  → src=number
--   b) Via client callback: TriggerServerEvent(..., pedData, context)   → src=table
AddEventHandler("ErsIntegration::OnFirstNPCInteraction", function(srcOrPed, pedDataOrCtx, contextOrNil, locOrNil)
    local playerSource, pedData, context, locationData

    if type(srcOrPed) == "number" then
        -- Server-side direct call: TriggerEvent(event, source, pedData, context, loc)
        playerSource = srcOrPed
        pedData      = pedDataOrCtx
        context      = contextOrNil
        locationData = locOrNil
    else
        -- Client callback: TriggerServerEvent(event, pedData, context, loc)
        -- args map to: srcOrPed=pedData, pedDataOrCtx=context, contextOrNil=loc
        playerSource = source
        pedData      = srcOrPed
        context      = pedDataOrCtx
        locationData = contextOrNil
    end

    -- Always log NPC interactions (not debug-gated) so we can diagnose pullover issues
    print("[CDE-ERS] OnFirstNPCInteraction source=" .. tostring(playerSource) .. " context=" .. tostring(context) .. " pedName=" .. tostring(pedData and (pedData.FirstName .. " " .. pedData.LastName) or "nil"))

    if not pedData then return end

    local calloutId = activeCallouts[tostring(playerSource)]
    local ctx = context and tostring(context):lower() or ""

    -- Detect pullover/pursuit contexts from ERS
    local isPullover = (ctx == "on_pullover")
    local isPursuit  = (ctx == "on_pursuit_start")

    DebugLog("NPC interaction | Context: " .. tostring(context) .. " | Callout: " .. tostring(calloutId or "none") .. " | isPullover: " .. tostring(isPullover) .. " | isPursuit: " .. tostring(isPursuit))

    -- ── Pullover or Pursuit context (outside callout) → traffic-stop endpoint ──
    if (isPullover or isPursuit) and Config.CreateOnTrafficStop then
        local key = tostring(playerSource)
        -- If a traffic stop was already sent for this pullover (e.g. driver already
        -- processed), ignore subsequent NPC interactions (passengers) to avoid duplicates.
        if activeTrafficStops[key] then
            DebugLog("Traffic stop already active for this pullover, skipping passenger NPC interaction")
            return
        end
        -- Also skip if the stop was already queued/handled this session
        if trafficStopHandled[key] then
            DebugLog("Traffic stop already handled for this pullover, skipping NPC interaction")
            return
        end
        DebugLog("Pullover/pursuit NPC detected via context, storing ped data and waiting for vehicle")
        -- Store ped data and location for pairing with vehicle data from OnFirstVehicleInteraction
        pendingTrafficStopPed[key] = pedData
        pendingTrafficStopLoc[key] = locationData
        trafficStopHandled[key] = false
        -- Fallback: if vehicle data never arrives within 3 seconds, send ped-only stop
        SetTimeout(3000, function()
            if not trafficStopHandled[key] then
                DebugLog("Fallback: no vehicle data arrived, sending ped-only traffic stop")
                trafficStopHandled[key] = true
                local savedLoc = pendingTrafficStopLoc[key]
                pendingTrafficStopPed[key] = nil
                pendingTrafficStopLoc[key] = nil
                HandleTrafficStop(playerSource, pedData, nil, savedLoc)
            end
        end)
        return
    end

    -- ── During a callout → create civilian linked to the callout ──
    if calloutId and Config.CreateCivilians then
        PostToCAD("civilian", BuildCivilianPayload(pedData, calloutId), function(success, data)
            if success and data then
                DebugLog("Created civilian: " .. tostring(data.fullName) .. " (ID: " .. tostring(data._id) .. ")")
            else
                DebugLog("Failed to create civilian: " .. json.encode(data or {}))
            end
        end)
    elseif not calloutId and not (ctx == "on_pullover_end" or ctx == "on_pursuit_end") and Config.CreateOnTrafficStop then
        -- Generic NPC interaction outside callout (ID check, etc.)
        DebugLog("NPC interaction outside callout, creating via traffic-stop endpoint")
        HandleTrafficStop(playerSource, pedData, nil, locationData)
    else
        DebugLog("NPC interaction skipped (no callout and traffic stop creation disabled)")
    end
end)

-- ─── OnFirstVehicleInteraction ──────────────────────────────────────────────
-- ERS fires this with context "on_pullover", "on_pursuit_start", etc.
-- For pullover/pursuit, the NPC data was already sent via OnFirstNPCInteraction;
-- this adds the vehicle data to the existing traffic stop.
AddEventHandler("ErsIntegration::OnFirstVehicleInteraction", function(srcOrVeh, vehDataOrCtx, contextOrNil, locOrNil)
    local playerSource, vehicleData, context, locationData

    if type(srcOrVeh) == "number" then
        playerSource = srcOrVeh
        vehicleData  = vehDataOrCtx
        context      = contextOrNil
        locationData = locOrNil
    else
        -- Client: TriggerServerEvent(event, vehicleData, context, loc)
        playerSource = source
        vehicleData  = srcOrVeh
        context      = vehDataOrCtx
        locationData = contextOrNil
    end

    print("[CDE-ERS] OnFirstVehicleInteraction source=" .. tostring(playerSource) .. " context=" .. tostring(context) .. " plate=" .. tostring(vehicleData and vehicleData.license_plate or "nil"))

    if not vehicleData then return end

    local ctx = context and tostring(context):lower() or ""
    local isPullover = (ctx == "on_pullover")
    local isPursuit  = (ctx == "on_pursuit_start")
    local calloutId = activeCallouts[tostring(playerSource)]

    -- ── Pullover/pursuit vehicle → send the SINGLE traffic stop with ped + vehicle data ──
    if (isPullover or isPursuit) and Config.CreateOnTrafficStop then
        local key = tostring(playerSource)
        local savedPed = pendingTrafficStopPed[key]
        local savedLoc = pendingTrafficStopLoc[key] or locationData
        pendingTrafficStopPed[key] = nil -- clean up
        pendingTrafficStopLoc[key] = nil
        if trafficStopHandled[key] then
            DebugLog("Pullover/pursuit vehicle arrived but traffic stop already sent, skipping")
            return
        end
        trafficStopHandled[key] = true
        DebugLog("Pullover/pursuit vehicle detected, creating traffic stop with ped + vehicle data")
        HandleTrafficStop(playerSource, savedPed, vehicleData, savedLoc)
        return
    end

    -- ── During a callout → create vehicle linked to the callout ──
    if not Config.CreateVehicles then return end
    if not calloutId then
        DebugLog("Vehicle interaction outside callout, skipping vehicle creation")
        return
    end

    DebugLog("Vehicle interaction during callout " .. calloutId .. " | Context: " .. tostring(context))
    PostToCAD("vehicle", BuildVehiclePayload(vehicleData, calloutId))
end)

-- ─── OnPullover (ERS native event) ───────────────────────────────────────
-- Fired by night_ers c_functions.lua via TriggerServerEvent when a
-- player initiates a traffic stop / pullover.
AddEventHandler("ErsIntegration::OnPullover", function(pedData, vehicleData, locationData)
    local src = source
    -- Always log (not debug-gated) so we can confirm the event fires
    print("[CDE-ERS] >>> OnPullover EVENT RECEIVED | src=" .. tostring(src) ..
        " | ped=" .. tostring(pedData and pedData.FirstName or "nil") ..
        " | veh=" .. tostring(vehicleData and vehicleData.license_plate or "nil"))
    if not Config.CreateOnTrafficStop then return end
    local key = tostring(src)
    -- Skip if already handled by OnFirstNPCInteraction + OnFirstVehicleInteraction
    if trafficStopHandled[key] then
        DebugLog("OnPullover skipped — traffic stop already created via NPC/Vehicle interaction events")
        return
    end
    trafficStopHandled[key] = true
    pendingTrafficStopPed[key] = nil -- clean up any pending data
    pendingTrafficStopLoc[key] = nil
    HandleTrafficStop(src, pedData, vehicleData, locationData)
end)

-- ─── OnPursuitStarted ───────────────────────────────────────────────────────
-- Fired when an ERS pursuit begins.
AddEventHandler("ErsIntegration::OnPursuitStarted", function(pedData, vehicleData)
    local source = source
    DebugLog("OnPursuitStarted RAW pedData=" .. json.encode(pedData or {}) .. " vehicleData=" .. json.encode(vehicleData or {}))

    local calloutId = activeCallouts[tostring(source)]
    if not calloutId then return end

    DebugLog("Pursuit started during callout " .. calloutId)

    if Config.CreateCivilians and pedData then
        PostToCAD("civilian", BuildCivilianPayload(pedData, calloutId))
    end

    if Config.CreateVehicles and vehicleData then
        PostToCAD("vehicle", BuildVehiclePayload(vehicleData, calloutId))
    end
end)

-- ─── OnPulloverEnded / OnPursuitEnded — close call and reset dedup flag ──────
AddEventHandler("ErsIntegration::OnPulloverEnded", function(pedData, vehicleData)
    local key = tostring(source)
    DebugLog("Pullover ended for player " .. key .. ", resetting dedup flag")

    -- Close the traffic stop call in the CAD (clears units 10-8 and removes call)
    if Config.CloseCallOnEnd and activeTrafficStops[key] then
        DebugLog("Closing traffic stop call: " .. activeTrafficStops[key])
        PostToCAD("callout-end", {
            ersCalloutId = activeTrafficStops[key],
        })
    end

    activeTrafficStops[key] = nil
    trafficStopHandled[key] = nil
    pendingTrafficStopPed[key] = nil
    pendingTrafficStopLoc[key] = nil
end)

AddEventHandler("ErsIntegration::OnPursuitEnded", function(pedData)
    local key = tostring(source)
    DebugLog("Pursuit ended for player " .. key .. ", resetting dedup flag")

    -- Close the traffic stop call in the CAD (clears units 10-8 and removes call)
    if Config.CloseCallOnEnd and activeTrafficStops[key] then
        DebugLog("Closing pursuit-related traffic stop call: " .. activeTrafficStops[key])
        PostToCAD("callout-end", {
            ersCalloutId = activeTrafficStops[key],
        })
    end

    activeTrafficStops[key] = nil
    trafficStopHandled[key] = nil
    pendingTrafficStopPed[key] = nil
    pendingTrafficStopLoc[key] = nil
end)

-- ─── OnToggleShift ──────────────────────────────────────────────────────────
-- Mirrors a player's ERS shift toggle to the CAD by hitting /ers/duty.
-- ERS's new s_functions.lua fires this with the signature
--   (source, isOnShift, serviceType)
-- where source is the FIRST argument (not the FiveM `source` global). The
-- previous version of this handler assumed (serviceType, isOnShift) and read
-- the global `source`, which produced "OnToggleShift (source=)" with empty
-- source in the diagnostic logs and silently broke the CAD duty sync.
AddEventHandler("ErsIntegration::OnToggleShift", function(srcArg, isOnShift, serviceType)
    if not Config.ToggleDutyOnShift then return end

    -- Prefer ERS's explicit source parameter; fall back to the global so that
    -- a future client-side TriggerServerEvent (which omits source) still works.
    local src = tonumber(srcArg) or source
    if not src or src == 0 then
        DebugLog("OnToggleShift skipped — no source resolved")
        return
    end

    local discordId = GetPlayerDiscordId(src)
    if not discordId then
        DebugLog("OnToggleShift skipped — no Discord ID for player " .. tostring(src))
        return
    end

    DebugLog("OnToggleShift | src=" .. tostring(src) .. " | discord=" .. tostring(discordId) ..
        " | service=" .. tostring(serviceType) .. " | onShift=" .. tostring(isOnShift))

    PostToCAD("duty", {
        discordId   = discordId,
        onShift     = isOnShift and true or false,
        serviceType = serviceType,
        callSign    = GetPlayerCallSign(src),
    }, function(success, data, statusCode)
        if success then
            DebugLog("Duty sync OK: " .. tostring(data and data.msg or "?"))
        else
            DebugLog("Duty sync FAIL (HTTP " .. tostring(statusCode) .. "): " ..
                tostring(data and data.msg or "?"))
        end
    end)
end)

-- ─── Player Disconnect Cleanup ──────────────────────────────────────────────
AddEventHandler("playerDropped", function()
    local source = source
    activeCallouts[tostring(source)] = nil
    activeTrafficStops[tostring(source)] = nil
    pendingTrafficStopPed[tostring(source)] = nil
    pendingTrafficStopLoc[tostring(source)] = nil
    trafficStopHandled[tostring(source)] = nil
end)

-- ========================================================================
-- SERVER CONSOLE TEST COMMANDS
-- ========================================================================

-- ─── ers_test ───────────────────────────────────────────────────────────────
-- Tests connectivity to the CAD backend API.
-- Usage: ers_test
RegisterCommand("ers_test", function(source, args)
    print("[CDE-ERS] ─── Running Connection Test ───")
    print("[CDE-ERS] Endpoint: " .. Config.CADEndpoint)
    print("[CDE-ERS] API Key:  " .. (Config.APIKey ~= "" and (string.sub(Config.APIKey, 1, 8) .. "...") or "NOT SET"))

    if Config.APIKey == "" then
        print("[CDE-ERS] ERROR: No API key configured. Set Config.APIKey in config.lua")
        return
    end

    -- Test 1: Create a test callout
    local testId = "ERS_TEST_" .. tostring(os.time())
    print("[CDE-ERS] [1/4] Creating test callout (" .. testId .. ")...")

    PostToCAD("callout", {
        ersCalloutId = testId,
        callType     = "ERS Test Callout",
        location     = "Test Location - Del Perro Pier",
        postal       = "102",
        coordinates  = { x = -1648.0, y = -1100.0, z = 13.0 },
        description  = "Automated test from cde-ers resource",
        priority     = "low",
        serviceType  = "police",
    }, function(success, data, statusCode)
        if not success then
            print("[CDE-ERS] [1/4] FAIL - Callout creation failed (HTTP " .. tostring(statusCode) .. ")")
            if data and data.msg then print("[CDE-ERS]        " .. data.msg) end
            return
        end
        print("[CDE-ERS] [1/4] OK - Call created: " .. tostring(data.incidentNumber or "?"))

        -- Test 2: Create a test civilian
        print("[CDE-ERS] [2/4] Creating test civilian...")
        PostToCAD("civilian", {
            ersCalloutId     = testId,
            firstName        = "Test",
            lastName         = "Subject",
            dateOfBirth      = "1990-01-15",
            gender           = "male",
            hasDriversLicense = true,
            hasFirearmsLicense = false,
        }, function(civSuccess, civData, civStatus)
            if not civSuccess then
                print("[CDE-ERS] [2/4] FAIL - Civilian creation failed (HTTP " .. tostring(civStatus) .. ")")
                if civData and civData.msg then print("[CDE-ERS]        " .. civData.msg) end
            else
                print("[CDE-ERS] [2/4] OK - Civilian created: " .. tostring(civData.fullName or "?"))
            end

            -- Test 3: Create a test vehicle
            print("[CDE-ERS] [3/4] Creating test vehicle...")
            PostToCAD("vehicle", {
                ersCalloutId = testId,
                plate        = "ERST" .. math.random(100, 999),
                make         = "Vapid",
                model        = "Stanier",
                color        = "Black",
                year         = 2024,
                stolen       = false,
            }, function(vehSuccess, vehData, vehStatus)
                if not vehSuccess then
                    print("[CDE-ERS] [3/4] FAIL - Vehicle creation failed (HTTP " .. tostring(vehStatus) .. ")")
                    if vehData and vehData.msg then print("[CDE-ERS]        " .. vehData.msg) end
                else
                    print("[CDE-ERS] [3/4] OK - Vehicle created: " .. tostring(vehData.plate or "?"))
                end

                -- Test 4: Close the test callout
                print("[CDE-ERS] [4/4] Closing test callout...")
                PostToCAD("callout-end", {
                    ersCalloutId = testId,
                }, function(endSuccess, endData, endStatus)
                    if not endSuccess then
                        print("[CDE-ERS] [4/4] FAIL - Callout close failed (HTTP " .. tostring(endStatus) .. ")")
                        if endData and endData.msg then print("[CDE-ERS]        " .. endData.msg) end
                    else
                        print("[CDE-ERS] [4/4] OK - Call closed: " .. tostring(endData.incidentNumber or "?"))
                    end

                    print("[CDE-ERS] ─── Test Complete ───")
                end)
            end)
        end)
    end)
end, true) -- true = restricted to server console only

-- ─── ers_status ─────────────────────────────────────────────────────────────
-- Shows current ERS bridge status and active callouts.
-- Usage: ers_status
RegisterCommand("ers_status", function(source, args)
    print("[CDE-ERS] ─── Bridge Status ───")
    print("[CDE-ERS] Endpoint:        " .. Config.CADEndpoint)
    print("[CDE-ERS] API Key:         " .. (Config.APIKey ~= "" and (string.sub(Config.APIKey, 1, 8) .. "...") or "NOT SET"))
    print("[CDE-ERS] Debug:           " .. tostring(Config.EnableDebug))
    print("[CDE-ERS] Create Calls:    " .. tostring(Config.CreateCallOnAccept))
    print("[CDE-ERS] Close on End:    " .. tostring(Config.CloseCallOnEnd))
    print("[CDE-ERS] Attach Units:    " .. tostring(Config.AttachUnitOnAccept))
    print("[CDE-ERS] Update Arrival:  " .. tostring(Config.UpdateOnArrival))
    print("[CDE-ERS] Create Civs:     " .. tostring(Config.CreateCivilians))
    print("[CDE-ERS] Create Vehicles: " .. tostring(Config.CreateVehicles))
    print("[CDE-ERS] Traffic Stops:  " .. tostring(Config.CreateOnTrafficStop))
    print("[CDE-ERS] Duty Sync:      " .. tostring(Config.ToggleDutyOnShift))

    local count = 0
    for k, v in pairs(activeCallouts) do
        count = count + 1
    end
    print("[CDE-ERS] Active Callouts: " .. tostring(count))
    if count > 0 then
        for playerSrc, calloutId in pairs(activeCallouts) do
            local name = GetPlayerName(tonumber(playerSrc)) or "Unknown"
            print("[CDE-ERS]   Player " .. playerSrc .. " (" .. name .. ") -> " .. calloutId)
        end
    end
    print("[CDE-ERS] ────────────────────")
end, true)

-- ─── ers_debug ──────────────────────────────────────────────────────────────
-- Toggles debug logging on/off at runtime.
-- Usage: ers_debug
RegisterCommand("ers_debug", function(source, args)
    Config.EnableDebug = not Config.EnableDebug
    print("[CDE-ERS] Debug mode: " .. (Config.EnableDebug and "ON" or "OFF"))
end, true)

-- ─── ers_exports ───────────────────────────────────────────────────────────
-- Enumerates every export the night_ers resource exposes. The fxmanifest
-- metadata route (GetResourceMetadata) returns 0 entries because night_ers
-- registers its exports at runtime via RegisterExport rather than
-- declaratively. So we also iterate the live exports['night_ers'] table —
-- that's what actually carries the runtime-registered exports.
-- Usage: ers_exports
RegisterCommand("ers_exports", function(source, args)
    print("[CDE-ERS] ─── Listing night_ers exports ───")
    local resourceName = "night_ers"
    local count = GetNumResourceMetadata(resourceName, "server_export") or 0
    local clientCount = GetNumResourceMetadata(resourceName, "export") or 0
    print("[CDE-ERS] fxmanifest server_export entries: " .. tostring(count))
    for i = 0, count - 1 do
        local name = GetResourceMetadata(resourceName, "server_export", i)
        print(string.format("[CDE-ERS]   server :%s", tostring(name)))
    end
    print("[CDE-ERS] fxmanifest export entries (shared): " .. tostring(clientCount))
    for i = 0, clientCount - 1 do
        local name = GetResourceMetadata(resourceName, "export", i)
        print(string.format("[CDE-ERS]   shared :%s", tostring(name)))
    end

    -- Runtime enumeration: iterate the live exports table. This catches
    -- exports registered via the runtime API rather than the fxmanifest.
    print("[CDE-ERS] Runtime exports['night_ers']:")
    local runtimeCount = 0
    local nightExports = exports['night_ers']
    if nightExports then
        local ok, err = pcall(function()
            for k, v in pairs(nightExports) do
                runtimeCount = runtimeCount + 1
                print(string.format("[CDE-ERS]   runtime :%s (%s)", tostring(k), type(v)))
            end
        end)
        if not ok then
            print("[CDE-ERS]   <pairs() failed: " .. tostring(err) .. ">")
        end
    else
        print("[CDE-ERS]   <exports['night_ers'] is nil>")
    end
    print("[CDE-ERS] Runtime export count: " .. runtimeCount)
    print("[CDE-ERS] ────────────────────")
end, true)

-- ─── ers_inspect ─────────────────────────────────────────────────────────────
-- Dumps the structure of one callout from getCallouts() so we can see
-- the exact fields night_ers expects for createCallout().
-- Usage: ers_inspect
RegisterCommand("ers_inspect", function(source, args)
    print("[CDE-ERS] ─── Inspecting night_ers callout structure ───")
    local ok, callouts = pcall(function()
        return exports['night_ers']:getCallouts()
    end)
    if not ok or not callouts then
        print("[CDE-ERS] ERROR: Could not call getCallouts(). Is night_ers running?")
        return
    end
    -- getCallouts() returns a table keyed by callout ID strings
    local count = 0
    local firstKey = nil
    local firstVal = nil
    print("[CDE-ERS] Callout IDs (keys for createCallout):")
    for k, v in pairs(callouts) do
        count = count + 1
        local name = (type(v) == "table" and v.CalloutName) or "?"
        print("[CDE-ERS]   [" .. tostring(k) .. "] = " .. name)
        if not firstKey then firstKey = k; firstVal = v end
    end
    print("[CDE-ERS] Total: " .. count)
    if firstVal and type(firstVal) == "table" then
        print("[CDE-ERS] First callout full dump (" .. tostring(firstKey) .. "):")
        for k, v in pairs(firstVal) do
            local valStr = tostring(v)
            if type(v) == "table" then valStr = json.encode(v) end
            print("[CDE-ERS]   " .. tostring(k) .. " (" .. type(v) .. ") = " .. valStr:sub(1, 200))
        end
    end
    print("[CDE-ERS] ────────────────────")
end, true)

-- ─── ers_test_traffic ──────────────────────────────────────────────────────
-- Sends a test traffic stop to the CAD to verify the /ers/traffic-stop
-- endpoint is reachable and working.
-- Usage: ers_test_traffic
RegisterCommand("ers_test_traffic", function(source, args)
    print("[CDE-ERS] ─── Running Traffic Stop Test ───")
    print("[CDE-ERS] Endpoint: " .. Config.CADEndpoint)

    if Config.APIKey == "" then
        print("[CDE-ERS] ERROR: No API key configured. Set Config.APIKey in config.lua")
        return
    end

    local testPlate = "TST" .. math.random(1000, 9999)

    print("[CDE-ERS] Sending test traffic stop (plate: " .. testPlate .. ")...")

    PostToCAD("traffic-stop", {
        -- Officer
        callSign             = "TEST-1",
        -- Civilian
        firstName            = "Test",
        lastName             = "Driver",
        dateOfBirth          = "1985-06-20",
        gender               = "male",
        driversLicenseStatus = "Valid",
        firearmsLicenseStatus = nil,
        civId                = nil,
        pedId                = nil,
        -- Vehicle
        plate  = testPlate,
        make   = "Vapid",
        model  = "Stanier",
        color  = "White",
        year   = 2024,
        stolen = false,
    }, function(success, data, statusCode)
        if not success then
            print("[CDE-ERS] FAIL - Traffic stop creation failed (HTTP " .. tostring(statusCode) .. ")")
            if data and data.msg then print("[CDE-ERS]        " .. data.msg) end
        else
            print("[CDE-ERS] OK - Traffic stop processed")
            print("[CDE-ERS]   Incident: " .. tostring(data.incidentNumber or "?"))
            print("[CDE-ERS]   Civilian: " .. tostring(data.civilianId or "?"))
            print("[CDE-ERS]   Vehicle:  " .. tostring(data.vehicleId or "?"))
        end
        print("[CDE-ERS] ─── Traffic Stop Test Complete ───")
    end)
end, true)

-- ─── ers_test_duty ─────────────────────────────────────────────────────────
-- Sends a duty sync request to the CAD using a Discord ID.
-- Usage: ers_test_duty <discordId> <on|off>
RegisterCommand("ers_test_duty", function(source, args)
    local discordId = args[1]
    local mode = (args[2] or ""):lower()
    if not discordId or (mode ~= "on" and mode ~= "off") then
        print("[CDE-ERS] Usage: ers_test_duty <discordId> <on|off>")
        return
    end
    local onShift = (mode == "on")
    print("[CDE-ERS] Sending duty sync: discord=" .. discordId .. " onShift=" .. tostring(onShift))
    PostToCAD("duty", {
        discordId = discordId,
        onShift   = onShift,
        callSign  = "TEST",
    }, function(success, data, statusCode)
        if success then
            print("[CDE-ERS] OK - " .. tostring(data and data.msg or "?") ..
                " | status=" .. tostring(data and data.status or "?"))
        else
            print("[CDE-ERS] FAIL (HTTP " .. tostring(statusCode) .. "): " ..
                tostring(data and data.msg or "?"))
        end
    end)
end, true)

-- ─── Catch-all: log ALL ErsIntegration events for diagnostics ────────────
-- This helps diagnose which events ERS actually fires vs which we expect.
for _, evtName in ipairs({
    "OnToggleShift", "OnIsOfferedCallout", "OnAcceptedCalloutOffer",
    "OnArrivedAtCallout", "OnEndedACallout", "OnCalloutCompletedSuccesfully",
    "OnFirstNPCInteraction", "OnFirstVehicleInteraction",
    "OnPullover", "OnPulloverEnded", "OnPursuitStarted", "OnPursuitEnded"
}) do
    AddEventHandler("ErsIntegration::" .. evtName, function(...)
        print("[CDE-ERS] EVENT >> " .. evtName .. " (source=" .. tostring(source) .. ")")
    end)
end

-- ========================================================================
-- DISPATCH-CREATED ERS CALLOUT POLLING
-- ========================================================================
-- Polls the CAD for callouts created from the dispatch livemap and
-- triggers them in-game via the night_ers export (if available) or
-- sends a notification to on-shift players.

local dispatchCalloutProcessing = false

local function FindNearestOnShiftPlayer(coords)
    local nearest = nil
    local nearestDist = math.huge
    local players = GetPlayers()

    for _, playerId in ipairs(players) do
        local ped = GetPlayerPed(playerId)
        if ped and ped ~= 0 then
            local pCoords = GetEntityCoords(ped)
            -- Check if player is on ERS shift via client callback would be ideal,
            -- but for simplicity we'll send to the nearest player
            local dist = #(vector3(pCoords.x, pCoords.y, pCoords.z) - vector3(coords.x, coords.y, coords.z or 0.0))
            if dist < nearestDist then
                nearestDist = dist
                nearest = tonumber(playerId)
            end
        end
    end

    return nearest
end

-- Dispatch flow (post-Sonoran-snippet finding): we add a clone to ERS's pool
-- via createCallout, capture the cloned callout ID returned in the response
-- table, forward it to the on-shift clients, and have them fire ERS's
-- internal NetEvent `night_ers:requestCallout(serviceType, calloutId)` —
-- which targets the offer at THAT specific clone instead of letting ERS pick
-- something random from the pool. The event is undocumented in the public
-- exports list but referenced in Sonoran's own ERS integration.
local function ProcessDispatchCallout(callout)
    local ersCalloutId = callout.ersCalloutId
    local callType    = callout.callType or "[ERS] Unknown"
    local location    = callout.location or "Unknown"
    local coords      = callout.coordinates or {}
    local priority    = callout.priority or "medium"
    local description = callout.description or ""
    local cfg         = callout.ersConfig or {}

    print("[CDE-ERS] Processing dispatch callout: " .. tostring(ersCalloutId) .. " | " .. callType)

    local cx = coords.x or 0.0
    local cy = coords.y or 0.0
    local cz = coords.z or 0.0

    -- Pick a string-keyed, non-cloned base callout that *matches the
    -- intended service type*. ERS's requestCallout handler validates that
    -- the requesting player's service satisfies the callout's
    -- CalloutUnitsRequired flags — cloning, say, gas_smell (fire+ambulance)
    -- and then firing requestCallout from a police officer gets silently
    -- rejected. So we filter the base picker to callouts whose required
    -- units include the dispatch's service type (defaulting to police —
    -- the dispatch panel currently sends police-shape callouts).
    local serviceType = callout.serviceType or "police"
    local requireField = ({
        police    = "policeRequired",
        fire      = "fireRequired",
        ambulance = "ambulanceRequired",
        tow       = "towRequired",
    })[serviceType] or "policeRequired"

    local baseCalloutId = nil
    local fallbackCalloutId = nil
    local baseOk, baseCallouts = pcall(function()
        return exports['night_ers']:getCallouts()
    end)
    if baseOk and type(baseCallouts) == "table" then
        for k, v in pairs(baseCallouts) do
            if type(k) == "string" and type(v) == "table" and v.Enabled ~= false
                and not string.find(k, "%-") then
                if v.CalloutUnitsRequired and v.CalloutUnitsRequired[requireField] then
                    baseCalloutId = k
                    break
                elseif not fallbackCalloutId then
                    fallbackCalloutId = k
                end
            end
        end
        if not baseCalloutId then baseCalloutId = fallbackCalloutId end
    end
    if baseCalloutId then
        print("[CDE-ERS] Base callout pick: " .. tostring(baseCalloutId) ..
            " (service=" .. tostring(serviceType) .. ", requires=" .. requireField .. ")")
    end

    local clonedCalloutId = nil
    if baseCalloutId then
        local weaponData = { cfg.weapon or "weapon_unarmed" }
        local ok, ret = pcall(function()
            return exports['night_ers']:createCallout({
                id = baseCalloutId,
                data = {
                    CalloutLocations = { { x = cx, y = cy, z = cz } },
                    PedWeaponData = weaponData,
                    PedActionOnNoActionFound = cfg.pedAction or "none",
                    PedChanceToFleeFromPlayer = cfg.chanceToFlee or 0,
                    PedChanceToObtainWeapons = cfg.chanceToObtainWeapons or 0,
                    PedChanceToAttackPlayer = cfg.chanceToAttack or 0,
                    PedChanceToSurrender = cfg.chanceToSurrender or 0,
                }
            })
        end)
        if ok then
            clonedCalloutId = type(ret) == "table" and ret.calloutId or nil
            print("[CDE-ERS] Dispatch callout added to night_ers pool | clonedCalloutId=" ..
                tostring(clonedCalloutId or "?"))
        else
            print("[CDE-ERS] createCallout failed for dispatch callout " .. tostring(ersCalloutId))
        end
    else
        print("[CDE-ERS] No base callout found in night_ers — dispatch callout not added to pool")
    end

    -- Direct-offer the cloned callout via ERS's official export
    -- (SendCalloutOfferToPlayer, shipped in the night_ers update we asked
    -- for). Replaces every previous workaround — no RegisterNetEvent hack,
    -- no client-side TriggerServerEvent, no service-type matching for the
    -- handler to validate against. ERS handles the Y/X offer UI natively.
    --
    -- IMPORTANT: the export blocks the calling thread via Citizen.Await
    -- until the client posts back externalCalloutOfferResult (default 5s
    -- watchdog). We fan out to every connected player in parallel via
    -- CreateThread so a 5s wait per player doesn't add up to a stall.
    -- The export returns multi-values (ok, reason) — pcall captures both
    -- as args 2 and 3 since the inner function returns both.
    if clonedCalloutId then
        for _, playerId in ipairs(GetPlayers()) do
            local pid = tonumber(playerId)
            Citizen.CreateThread(function()
                local pcallOk, exportOk, exportReason = pcall(function()
                    return exports['night_ers']:SendCalloutOfferToPlayer(pid, clonedCalloutId, 5000)
                end)
                if not pcallOk then
                    print(string.format("[CDE-ERS] SendCalloutOfferToPlayer pcall error for src=%s: %s",
                        tostring(pid), tostring(exportOk)))
                elseif exportOk then
                    print(string.format("[CDE-ERS] Offer delivered to src=%s for %s",
                        tostring(pid), tostring(clonedCalloutId)))
                else
                    print(string.format("[CDE-ERS] Offer refused for src=%s: %s",
                        tostring(pid), tostring(exportReason)))
                end
            end)
        end
    end

    -- Notify clients so they can drop a chat / blip / waypoint for context.
    -- The actual offer UI is handled by ERS's SendCalloutOfferToPlayer
    -- above; this event is informational only.
    TriggerClientEvent('cde-ers:dispatchCallout', -1, {
        ersCalloutId    = ersCalloutId,
        clonedCalloutId = clonedCalloutId,
        callType        = callType,
        location        = location,
        postal          = callout.postal or "",
        coordinates     = coords,
        priority        = priority,
        description     = description,
    })

    -- Ack so CAD stops re-queuing this callout.
    PostToCAD("ack-dispatch-callout", { ersCalloutId = ersCalloutId }, function(success)
        if success then
            DebugLog("Acknowledged dispatch callout: " .. tostring(ersCalloutId))
        else
            DebugLog("Failed to acknowledge dispatch callout: " .. tostring(ersCalloutId))
        end
    end)
end

-- ─── ers_dispatch_test ───────────────────────────────────────────────────────
-- Tests the dispatch callout flow locally (no CAD needed). Creates a callout
-- in night_ers and sends a notification to all players.
-- Usage: ers_dispatch_test [x] [y] [z]
RegisterCommand("ers_dispatch_test", function(source, args)
    print("[CDE-ERS] ─── Running Dispatch Callout Test ───")

    local testX = tonumber(args[1]) or 200.0
    local testY = tonumber(args[2]) or -900.0
    local testZ = tonumber(args[3]) or 30.0

    local testCallout = {
        ersCalloutId = "DISP-TEST-" .. os.time(),
        callType = "[ERS] Test Dispatch Callout",
        location = "Test Location",
        postal = "100",
        coordinates = { x = testX, y = testY, z = testZ },
        priority = "high",
        description = "Test callout from ers_dispatch_test command",
    }

    print("[CDE-ERS] Creating test dispatch callout at " .. testX .. ", " .. testY .. ", " .. testZ)
    ProcessDispatchCallout(testCallout)
    print("[CDE-ERS] ─── Dispatch Callout Test Complete ───")
end, true)

-- Polling thread
Citizen.CreateThread(function()
    -- Wait for resource to fully load
    Citizen.Wait(5000)

    if not Config.EnableDispatchCallouts then
        DebugLog("Dispatch callouts disabled in config")
        return
    end

    if Config.APIKey == "" then
        DebugLog("Skipping dispatch callout polling — no API key configured")
        return
    end

    local pollInterval = (Config.DispatchPollInterval or 5) * 1000

    print("[CDE-ERS] Dispatch callout polling started (every " .. tostring(Config.DispatchPollInterval or 5) .. "s)")

    while true do
        Citizen.Wait(pollInterval)

        if not dispatchCalloutProcessing then
            dispatchCalloutProcessing = true

            GetFromCAD("pending-dispatch-callouts", function(success, data)
                if success and data and data.callouts and #data.callouts > 0 then
                    DebugLog("Found " .. tostring(#data.callouts) .. " pending dispatch callout(s)")
                    for _, callout in ipairs(data.callouts) do
                        ProcessDispatchCallout(callout)
                    end
                end
                dispatchCalloutProcessing = false
            end)
        end
    end
end)

-- ─── Startup ────────────────────────────────────────────────────────────────
print("[CDE-ERS] ERS Bridge for CDECAD loaded successfully")
print("[CDE-ERS] Console commands: ers_test | ers_test_traffic | ers_dispatch_test | ers_test_duty | ers_status | ers_debug | ers_inspect | ers_exports")
if Config.APIKey == "" then
    print("[CDE-ERS] WARNING: No API key configured! Set Config.APIKey in config.lua")
end

end
