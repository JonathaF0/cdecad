do
    local Config = CivConfig

RegisterNUICallback('closeID', function(data, cb)
    cb('ok')
end)

RegisterNUICallback('getMugshot', function(data, cb)
    local ssn = data and data.ssn
    if not ssn or ssn == '' then cb({ mugshotUrl = nil }) return end
    local result = lib.callback.await('cdecad-civmanager:getMugshot', false, tostring(ssn))
    cb({ mugshotUrl = result and result.mugshotUrl or nil })
end)

RegisterNUICallback('fetchLicensePng', function(data, cb)
    local civilianId  = data and data.civilianId
    local licenseType = (data and data.licenseType) or 'drivers'
    if not civilianId or civilianId == '' then cb({ ok = false }) return end
    local result = lib.callback.await('cdecad-civmanager:fetchLicensePng', false, civilianId, licenseType)
    cb(result or { ok = false })
end)

RegisterNUICallback('escape', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)


end
