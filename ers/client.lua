do
    local Config = ErsConfig
    if not Config or not Config.Enabled then return end
-- client/main.lua
-- ERS Bridge for CDECAD — Client-side
-- Provides coordinate/postal data to server-side events when needed.

-- Unconditional startup print so we can confirm in F8 whether the cde-ers
-- client script even loaded on this player's session. If this line is
-- missing from a player's F8 console, the resource isn't running for them
-- and dispatch offers (or any of the cde-ers client hooks) can't fire.
print("[CDE-ERS Client] script loaded (v1.5.x) — dispatch offer handler armed")

local isOnCallout = false

-- ─── Helper: Debug logging (matches server DebugLog) ─────────────────────────
local function DebugLog(msg)
    if Config and Config.EnableDebug then
        print("[CDE-ERS Client] " .. tostring(msg))
    end
end

-- ─── Helper: Check if player is on an ERS shift ────────────────────────────
function IsPlayerOnErsShift()
    local success, result = pcall(function()
        return exports['night_ers']:getIsPlayerOnShift()
    end)
    return success and result or false
end

-- ─── Helper: Check if player is attached to an ERS callout ─────────────────
function IsPlayerOnCallout()
    local success, result = pcall(function()
        return exports['night_ers']:getIsPlayerAttachedToCallout()
    end)
    return success and result or false
end

-- ─── Helper: Get player's active ERS service type ──────────────────────────
function GetPlayerServiceType()
    local success, result = pcall(function()
        return exports['night_ers']:getPlayerActiveServiceType()
    end)
    return success and result or "police"
end

-- ─── Helper: Get nearest postal code ───────────────────────────────────────
-- Mirrors the auto-detection added to ERS's c_functions.lua: tries the
-- supported postal resources in order and returns the first value found.
-- Supported: rHUD, SimpleHUD, ModernHUD, nearest-postal, mnr-postals.
local function tryPostalExport(resource, exportName)
    local ok, result = pcall(function()
        return exports[resource][exportName](exports[resource])
    end)
    if ok and result and tostring(result) ~= "" then
        return tostring(result)
    end
    return nil
end

function GetNearestPostal()
    -- nearest-postal: getPostal()
    local p = tryPostalExport('nearest-postal', 'getPostal')
    if p then return p end

    -- mnr-postals: getPostal()
    p = tryPostalExport('mnr-postals', 'getPostal')
    if p then return p end

    -- rHUD: getNearestPostal()
    p = tryPostalExport('rHUD', 'getNearestPostal')
    if p then return p end

    -- SimpleHUD: getNearestPostal()
    p = tryPostalExport('SimpleHUD', 'getNearestPostal')
    if p then return p end

    -- ModernHUD: getNearestPostal()
    p = tryPostalExport('ModernHUD', 'getNearestPostal')
    if p then return p end

    return ""
end

-- ─── Helper: Get player location data for CAD ──────────────────────────────
local function GetPlayerLocationData()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    -- Street name
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local streetName = GetStreetNameFromHashKey(streetHash) or ""
    local crossingName = GetStreetNameFromHashKey(crossingHash) or ""
    local location = streetName
    if crossingName ~= "" then
        location = location .. " / " .. crossingName
    end

    -- Zone name
    local zoneHash = GetNameOfZone(coords.x, coords.y, coords.z)
    local zoneName = GetLabelText(zoneHash)
    if zoneName and zoneName ~= "NULL" and zoneName ~= "" then
        location = location .. ", " .. zoneName
    end

    -- Postal
    local postal = GetNearestPostal()

    return {
        location = location,
        postal = postal,
        coordinates = { x = coords.x, y = coords.y, z = coords.z },
    }
end

-- ─── Server location request handler ─────────────────────────────────────
-- Server requests location data when it needs street names for traffic stops
RegisterNetEvent('ErsIntegration::RequestLocation')
AddEventHandler('ErsIntegration::RequestLocation', function()
    local loc = GetPlayerLocationData()
    TriggerServerEvent('ErsIntegration::LocationResponse', loc)
end)

-- ========================================================================
-- DISPATCH-CREATED ERS CALLOUT HANDLER
-- ========================================================================
-- Receives notification from the server after a dispatch callout has been
-- added to the night_ers pool via createCallout(). Triggers the native ERS
-- callout offer by executing /requestcallout so the player gets the
-- standard ERS accept/decline UI.

RegisterNetEvent('cde-ers:dispatchCallout')
AddEventHandler('cde-ers:dispatchCallout', function(data)
    if not data then return end
    -- Informational only — the actual offer UI is shown by ERS via the
    -- server-side exports['night_ers']:SendCalloutOfferToPlayer call that
    -- runs in ProcessDispatchCallout. No client work required here.
    print("[CDE-ERS Client] Dispatch callout: " .. tostring(data.callType) ..
        " | ersCalloutId=" .. tostring(data.ersCalloutId) ..
        " | clonedCalloutId=" .. tostring(data.clonedCalloutId))
end)

-- ========================================================================
-- ERS OPEN-SOURCE CALLBACK FUNCTIONS
-- ========================================================================
-- ERS calls these global functions on the client when events occur.
-- We forward them to the server via TriggerServerEvent so our server
-- handlers can process the data and push it to the CAD API.
-- Ref: https://docs.nights-software.com/resources/ers/#-open-source-functions--events

-- ─── Callout Lifecycle ───────────────────────────────────────────────────────

--- Fired when a callout is offered to the player.
function OnIsOfferedCallout(calloutData)
    DebugLog("OnIsOfferedCallout called")
    TriggerServerEvent('ErsIntegration::OnIsOfferedCallout', calloutData)
end

--- Fired when the player accepts a callout offer.
function OnAcceptedCalloutOffer(calloutData)
    DebugLog("OnAcceptedCalloutOffer called")
    TriggerServerEvent('ErsIntegration::OnAcceptedCalloutOffer', calloutData)
end

--- Fired when the player arrives at the callout (before entities spawn).
function OnArrivedAtCallout(calloutData)
    DebugLog("OnArrivedAtCallout called")
    TriggerServerEvent('ErsIntegration::OnArrivedAtCallout', calloutData)
end

--- Fired before entities are deleted or callout is cancelled.
function OnEndedACallout(calloutData)
    DebugLog("OnEndedACallout called")
    TriggerServerEvent('ErsIntegration::OnEndedACallout', calloutData)
end

--- Fired after the entire callout task list is completed.
function OnCalloutCompletedSuccesfully(calloutData)
    DebugLog("OnCalloutCompletedSuccesfully called")
    TriggerServerEvent('ErsIntegration::OnCalloutCompletedSuccesfully', calloutData)
end

-- ─── NPC & Vehicle Interactions ────────────────────────────────────────────────
-- ERS may fire these as server events directly OR as client callbacks depending
-- on version/context. We define both client functions (forwarding to server)
-- and server handlers to cover all cases.

--- Fired on the first interaction with an NPC (during callout, pullover, etc.).
function OnFirstNPCInteraction(pedData, context)
    DebugLog("OnFirstNPCInteraction called | context=" .. tostring(context))
    local loc = GetPlayerLocationData()
    TriggerServerEvent('ErsIntegration::OnFirstNPCInteraction', pedData, context, loc)
end

--- Fired on the first interaction with a vehicle (during callout, pullover, etc.).
function OnFirstVehicleInteraction(vehicleData, context)
    DebugLog("OnFirstVehicleInteraction called | context=" .. tostring(context))
    local loc = GetPlayerLocationData()
    TriggerServerEvent('ErsIntegration::OnFirstVehicleInteraction', vehicleData, context, loc)
end

-- ─── Traffic Stops ───────────────────────────────────────────────────────────

--- Fired when a traffic stop / pullover is initiated.
function OnPullover(pedData, vehicleData)
    print("[CDE-ERS] >>> OnPullover CALLED | pedData=" .. tostring(pedData ~= nil) .. " vehicleData=" .. tostring(vehicleData ~= nil))
    local loc = GetPlayerLocationData()
    TriggerServerEvent('ErsIntegration::OnPullover', pedData, vehicleData, loc)
end

--- Fired when a traffic stop / pullover ends.
function OnPulloverEnded(pedData, vehicleData)
    print("[CDE-ERS] >>> OnPulloverEnded CALLED")
    TriggerServerEvent('ErsIntegration::OnPulloverEnded', pedData, vehicleData)
end

-- ─── Shift Toggle ────────────────────────────────────────────────────────────

--- Fired when a player toggles their ERS shift on or off.
-- ERS's documented signature is OnToggleShift(serviceType, isOnShift) but we
-- defensively re-resolve both via the night_ers exports so a signature change
-- (or call site that omits args) doesn't break the duty mirror.
function OnToggleShift(serviceTypeArg, isOnShiftArg)
    local isOnShift = isOnShiftArg
    if type(isOnShift) ~= "boolean" then
        isOnShift = IsPlayerOnErsShift()
    end

    local serviceType = serviceTypeArg
    if type(serviceType) ~= "string" or serviceType == "" then
        serviceType = GetPlayerServiceType()
    end

    DebugLog("OnToggleShift called | service=" .. tostring(serviceType) .. " | onShift=" .. tostring(isOnShift))
    TriggerServerEvent('ErsIntegration::OnToggleShift', serviceType, isOnShift)
end

-- ─── Pursuits ────────────────────────────────────────────────────────────────

--- Fired when a pursuit begins.
function OnPursuitStarted(pedData, vehicleData)
    print("[CDE-ERS] >>> OnPursuitStarted CALLED")
    TriggerServerEvent('ErsIntegration::OnPursuitStarted', pedData, vehicleData)
end

--- Fired when a pursuit ends.
function OnPursuitEnded(pedData)
    print("[CDE-ERS] >>> OnPursuitEnded CALLED")
    TriggerServerEvent('ErsIntegration::OnPursuitEnded', pedData)
end

end
