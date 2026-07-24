do
    local Config = CivConfig
--[[
    CDECAD Civilian Manager - NUI Handler
    Handles NUI callbacks and messages
]]

-- Close ID card when clicked
RegisterNUICallback('closeID', function(data, cb)
    cb('ok')
end)

RegisterNUICallback('getMugshot', function(data, cb)
    local ssn = data and data.ssn
    if not ssn or ssn == '' then cb({ mugshotUrl = nil }) return end
    local result = lib.callback.await('cdecad-civmanager:getMugshot', false, tostring(ssn))
    cb({ mugshotUrl = result and result.mugshotUrl or nil })
end)

-- NUI proxy for the server-rendered license PNG. Keeps the x-api-key out
-- of the browser context - the server-side callback fetches the PNG with
-- the resource's key and returns it as a base64 data URI.
RegisterNUICallback('fetchLicensePng', function(data, cb)
    local civilianId  = data and data.civilianId
    local licenseType = (data and data.licenseType) or 'drivers'
    if not civilianId or civilianId == '' then cb({ ok = false }) return end
    local result = lib.callback.await('cdecad-civmanager:fetchLicensePng', false, civilianId, licenseType)
    cb(result or { ok = false })
end)

-- Handle escape key
RegisterNUICallback('escape', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)


end
