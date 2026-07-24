do
    local Config = ErsConfig
    if not Config or not Config.Enabled then return end

print("[CDE-ERS Client] script loaded (v1.5.x) - dispatch offer handler armed")

local isOnCallout = false

local function DebugLog(msg)
    if Config and Config.EnableDebug then
        print("[CDE-ERS Client] " .. tostring(msg))
    end
end

function IsPlayerOnErsShift()
    local success, result = pcall(function()
        return exports['night_ers']:getIsPlayerOnShift()
    end)
    return success and result or false
end

function IsPlayerOnCallout()
    local success, result = pcall(function()
        return exports['night_ers']:getIsPlayerAttachedToCallout()
    end)
    return success and result or false
end

function GetPlayerServiceType()
    local success, result = pcall(function()
        return exports['night_ers']:getPlayerActiveServiceType()
    end)
    return success and result or "police"
end

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
    local p = tryPostalExport('nearest-postal', 'npostal')
    if p then return p end
    p = tryPostalExport('nearest-postal', 'getPostal')
    if p then return p end

    p = tryPostalExport('mnr-postals', 'getPostal')
    if p then return p end

    p = tryPostalExport('rHUD', 'getNearestPostal')
    if p then return p end

    p = tryPostalExport('SimpleHUD', 'getNearestPostal')
    if p then return p end

    p = tryPostalExport('ModernHUD', 'getNearestPostal')
    if p then return p end

    return ""
end

local function GetPlayerLocationData()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local streetName = GetStreetNameFromHashKey(streetHash) or ""
    local crossingName = GetStreetNameFromHashKey(crossingHash) or ""
    local location = streetName
    if crossingName ~= "" then
        location = location .. " / " .. crossingName
    end

    local zoneHash = GetNameOfZone(coords.x, coords.y, coords.z)
    local zoneName = GetLabelText(zoneHash)
    if zoneName and zoneName ~= "NULL" and zoneName ~= "" then
        location = location .. ", " .. zoneName
    end

    local postal = GetNearestPostal()

    return {
        location = location,
        postal = postal,
        coordinates = { x = coords.x, y = coords.y, z = coords.z },
    }
end

RegisterNetEvent('ErsIntegration::RequestLocation')
AddEventHandler('ErsIntegration::RequestLocation', function()
    local loc = GetPlayerLocationData()
    TriggerServerEvent('ErsIntegration::LocationResponse', loc)
end)


RegisterNetEvent('cde-ers:dispatchCallout')
AddEventHandler('cde-ers:dispatchCallout', function(data)
    if not data then return end
    print("[CDE-ERS Client] Dispatch callout: " .. tostring(data.callType) ..
        " | ersCalloutId=" .. tostring(data.ersCalloutId) ..
        " | clonedCalloutId=" .. tostring(data.clonedCalloutId))
end)



function OnIsOfferedCallout(calloutData)
    DebugLog("OnIsOfferedCallout called")
    TriggerServerEvent('ErsIntegration::OnIsOfferedCallout', calloutData)
end

function OnAcceptedCalloutOffer(calloutData)
    DebugLog("OnAcceptedCalloutOffer called")
    TriggerServerEvent('ErsIntegration::OnAcceptedCalloutOffer', calloutData)
end

function OnArrivedAtCallout(calloutData)
    DebugLog("OnArrivedAtCallout called")
    TriggerServerEvent('ErsIntegration::OnArrivedAtCallout', calloutData)
end

function OnEndedACallout(calloutData)
    DebugLog("OnEndedACallout called")
    TriggerServerEvent('ErsIntegration::OnEndedACallout', calloutData)
end

function OnCalloutCompletedSuccesfully(calloutData)
    DebugLog("OnCalloutCompletedSuccesfully called")
    TriggerServerEvent('ErsIntegration::OnCalloutCompletedSuccesfully', calloutData)
end


function OnFirstNPCInteraction(pedData, context)
    DebugLog("OnFirstNPCInteraction called | context=" .. tostring(context))
    local loc = GetPlayerLocationData()
    TriggerServerEvent('ErsIntegration::OnFirstNPCInteraction', pedData, context, loc)
end

function OnFirstVehicleInteraction(vehicleData, context)
    DebugLog("OnFirstVehicleInteraction called | context=" .. tostring(context))
    local loc = GetPlayerLocationData()
    TriggerServerEvent('ErsIntegration::OnFirstVehicleInteraction', vehicleData, context, loc)
end


function OnPullover(pedData, vehicleData)
    print("[CDE-ERS] >>> OnPullover CALLED | pedData=" .. tostring(pedData ~= nil) .. " vehicleData=" .. tostring(vehicleData ~= nil))
    local loc = GetPlayerLocationData()
    TriggerServerEvent('ErsIntegration::OnPullover', pedData, vehicleData, loc)
end

function OnPulloverEnded(pedData, vehicleData)
    print("[CDE-ERS] >>> OnPulloverEnded CALLED")
    TriggerServerEvent('ErsIntegration::OnPulloverEnded', pedData, vehicleData)
end


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
    TriggerServerEvent('ErsIntegration::OnToggleShift', false, isOnShift, serviceType)
end


function OnPursuitStarted(pedData, vehicleData)
    print("[CDE-ERS] >>> OnPursuitStarted CALLED")
    TriggerServerEvent('ErsIntegration::OnPursuitStarted', pedData, vehicleData)
end

function OnPursuitEnded(pedData)
    print("[CDE-ERS] >>> OnPursuitEnded CALLED")
    TriggerServerEvent('ErsIntegration::OnPursuitEnded', pedData)
end

end
