do
    local Config = CivConfig

local ActiveCivilian = nil
local IsIDShowing = false
local IsRegisteringVehicle = false


local function Debug(...)
    if Config.Debug then
        print('[CDECAD-CIVMANAGER]', ...)
    end
end

local function Notify(type, message)
    if Config.Notifications.UseOxLib then
        lib.notify({
            title = 'Civilian Manager',
            description = message,
            type = type,
            duration = Config.Notifications.Duration,
            position = Config.Notifications.Position
        })
    else
        TriggerEvent('chat:addMessage', {
            color = type == 'success' and {0, 255, 0} or type == 'error' and {255, 0, 0} or {255, 255, 255},
            args = {'[CivManager]', message}
        })
    end
end

local function GetCurrentVehicleInfo()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then
        return nil
    end

    local plate = GetVehicleNumberPlateText(vehicle):gsub('%s+', '')
    local modelHash = GetEntityModel(vehicle)
    local spawnName = GetDisplayNameFromVehicleModel(modelHash) or ''

    local make, model = VehicleUtils.ResolveMakeModel(spawnName, modelHash)
    local primaryColor = GetVehicleColours(vehicle)
    local color = VehicleUtils.ResolveColor(primaryColor)

    return {
        plate = plate,
        model = model,
        make = make,
        color = color,
        year = tostring(2020 + math.random(0, 5))
    }
end


local function SaveCivilianToKVP(civilianId)
    if Config.Persistence == 'kvp' then
        SetResourceKvp('cdecad_selected_civ', civilianId or '')
        Debug('Saved civilian to KVP:', civilianId)
    end
end

local function LoadCivilianFromKVP()
    if Config.Persistence == 'kvp' then
        local civilianId = GetResourceKvpString('cdecad_selected_civ')
        if civilianId and civilianId ~= '' then
            Debug('Loaded civilian from KVP:', civilianId)
            return civilianId
        end
    end
    return nil
end

local function ClearCivilianFromKVP()
    if Config.Persistence == 'kvp' then
        DeleteResourceKvp('cdecad_selected_civ')
        Debug('Cleared civilian from KVP')
    end
end


local function OpenCivilianSelector()
    local result = lib.callback.await('cdecad-civmanager:getCivilians', false)
    
    if not result.success then
        Notify('error', result.error or 'Failed to fetch civilians')
        return
    end
    
    if not result.civilians or #result.civilians == 0 then
        Notify('error', 'No civilians found for your account. Create one in the CAD first.')
        return
    end
    
    Debug('Received civilians:', json.encode(result.civilians))
    
    local options = {}
    
    for _, civ in ipairs(result.civilians) do
        local firstName = civ.firstName or civ.firstname or civ.first_name or 'Unknown'
        local lastName = civ.lastName or civ.lastname or civ.last_name or 'Unknown'
        local dob = civ.dob or civ.dateOfBirth or civ.date_of_birth or civ.birthdate or 'Unknown'
        local ssn = civ.ssn or civ.citizenid or civ.id or 'Unknown'
        
        local label = firstName .. ' ' .. lastName
        local description = 'DOB: ' .. tostring(dob)
        
        if ssn and ssn ~= 'Unknown' then
            description = description .. ' | ID: ' .. tostring(ssn)
        end
        
        local normalizedCiv = {
            id = civ.id or civ._id,
            firstName = firstName,
            lastName = lastName,
            dob = dob,
            dateOfBirth = dob,
            ssn = ssn,
            gender = civ.gender,
            phone = civ.phone,
            address = civ.address,
            height = civ.height,
            weight = civ.weight,
            eyeColor = civ.eyeColor or civ.eye_color,
            hairColor = civ.hairColor or civ.hair_color,
            mugshotUrl = civ.mugshotUrl or civ.mugshot_url or civ.photoUrl,
            licenses = civ.licenses
        }
        
        table.insert(options, {
            title = label,
            description = description,
            icon = 'user',
            onSelect = function()
                SelectCivilian(normalizedCiv)
            end
        })
    end
    
    table.insert(options, {
        title = 'Clear Selection',
        description = 'Remove current civilian selection',
        icon = 'xmark',
        onSelect = function()
            ClearCivilian()
        end
    })
    
    lib.registerContext({
        id = 'cdecad_civ_selector',
        title = 'Select Civilian',
        options = options
    })
    
    lib.showContext('cdecad_civ_selector')
end

local function CaptureMugshotForCivilian(civilianId)
    if GetResourceState('MugShotBase64') ~= 'started' then
        Debug('MugShotBase64 not running, skipping mugshot capture')
        return
    end

    SetTimeout(3000, function()
        local ok, result = pcall(function()
            return exports['MugShotBase64']:GetMugShotBase64(PlayerPedId(), true)
        end)

        if ok and result and result ~= '' then
            Debug('Mugshot captured for civilian:', civilianId)
            TriggerServerEvent('cdecad-civmanager:updateMugshot', civilianId, result)
            if ActiveCivilian and (ActiveCivilian.id == civilianId or ActiveCivilian._id == civilianId or ActiveCivilian.ssn == civilianId) then
                ActiveCivilian.mugshotUrl = result
            end
        else
            Debug('Mugshot capture failed')
        end
    end)
end

function SelectCivilian(civData)
    Debug('SelectCivilian called with:', json.encode(civData))

    ActiveCivilian = nil

    ActiveCivilian = civData

    local saveId = civData.ssn or civData.id
    Debug('Saving to KVP with ID:', saveId)
    SaveCivilianToKVP(saveId)

    TriggerServerEvent('cdecad-civmanager:selectCivilian', civData)

    Notify('success', 'Now playing as: ' .. (civData.firstName or 'Unknown') .. ' ' .. (civData.lastName or 'Unknown'))

    if Config.CaptureFiveMMugshot then
        local civId = civData.ssn or civData.id or civData._id
        if civId then
            CaptureMugshotForCivilian(civId)
        end
    end

    Debug('ActiveCivilian is now:', ActiveCivilian and (ActiveCivilian.firstName .. ' ' .. ActiveCivilian.lastName) or 'nil')
end

function ClearCivilian()
    Debug('ClearCivilian called')
    ActiveCivilian = nil
    ClearCivilianFromKVP()
    TriggerServerEvent('cdecad-civmanager:selectCivilian', nil)
    Notify('success', 'Civilian selection cleared')
end


RegisterCommand(Config.Commands.SelectCiv, function()
    OpenCivilianSelector()
end, false)

RegisterCommand(Config.Commands.ShowInfo, function()
    if not ActiveCivilian then
        Notify('error', 'No civilian selected. Use /' .. Config.Commands.SelectCiv)
        return
    end
    
    local info = string.format('%s %s | DOB: %s | Phone: %s',
        ActiveCivilian.firstName,
        ActiveCivilian.lastName,
        ActiveCivilian.dob or ActiveCivilian.dateOfBirth or 'Unknown',
        ActiveCivilian.phone or 'Unknown'
    )
    
    Notify('info', info)
end, false)

RegisterCommand(Config.Commands.ShowID, function()
    if not ActiveCivilian then
        Notify('error', 'No civilian selected. Use /' .. Config.Commands.SelectCiv)
        return
    end

    TriggerServerEvent('cdecad-civmanager:showID')
end, false)


RegisterCommand(Config.Commands.RegisterVehicle, function()
    if not Config.VehicleRegistration.Enabled then
        Notify('error', 'Vehicle registration is disabled')
        return
    end

    if IsRegisteringVehicle then
        Notify('error', 'Registration already in progress')
        return
    end

    if not ActiveCivilian then
        Notify('error', 'No civilian selected. Use /' .. Config.Commands.SelectCiv)
        return
    end

    if Config.VehicleRegistration.RequireInVehicle then
        local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
        if vehicle == 0 then
            Notify('error', 'You must be in a vehicle to register it')
            return
        end
    end

    local vehicleInfo = GetCurrentVehicleInfo()

    if not vehicleInfo then
        Notify('error', 'Could not get vehicle information')
        return
    end

    local confirm = lib.alertDialog({
        header = 'Register Vehicle',
        content = string.format('Register this vehicle?\n\n**Plate:** %s\n**Make:** %s\n**Model:** %s\n**Color:** %s',
            vehicleInfo.plate,
            vehicleInfo.make,
            vehicleInfo.model,
            vehicleInfo.color
        ),
        centered = true,
        cancel = true
    })

    if confirm ~= 'confirm' then
        return
    end

    IsRegisteringVehicle = true
    local ok, result = pcall(lib.callback.await, 'cdecad-civmanager:registerVehicle', false, vehicleInfo)
    IsRegisteringVehicle = false

    if not ok or not result then
        Notify('error', 'Failed to register vehicle')
        return
    end

    if result.success then
        Notify('success', 'Vehicle registered: ' .. vehicleInfo.plate)
    else
        Notify('error', result.error or 'Failed to register vehicle')
    end
end, false)

RegisterCommand(Config.Commands.ClearCiv, function()
    ClearCivilian()
end, false)


RegisterNetEvent('cdecad-civmanager:notify', function(type, message)
    Notify(type, message)
end)

RegisterNetEvent('cdecad-civmanager:civilianSet', function(civData)
    Debug('civilianSet event received from server')
    if civData then
        Debug('Server confirmed civilian:', civData.firstName, civData.lastName)
        ActiveCivilian = civData
    else
        Debug('Server cleared civilian')
        ActiveCivilian = nil
    end
end)

local function FormatDOB(dob)
    if not dob then return 'Unknown' end
    local y, m, d = tostring(dob):match('(%d%d%d%d)-(%d%d)-(%d%d)')
    if y and m and d then return m .. '/' .. d .. '/' .. y end
    return tostring(dob)
end

RegisterNetEvent('cdecad-civmanager:receiveID', function(civData, fromName, cardStyle)
    Debug('Received ID from:', fromName)

    if Config.IDCard.ShowHTML then
        local mode = (Config.IDCard.LicenseMode or 'html'):lower()
        local civId = civData.id or civData._id or ''
        SendNUIMessage({
            action      = 'showID',
            civilian    = civData,
            from        = fromName,
            duration    = Config.IDCard.DisplayDuration,
            style       = cardStyle or Config.IDCard.CardStyle,
            licenseMode = mode,
            civilianId  = civId,
            licenseType = 'drivers',
        })
        SetNuiFocus(false, false)
    end
    
    if Config.IDCard.ShowInChat then
        local idText = string.format('[ID SHOWN by %s] %s %s | DOB: %s | SSN: %s',
            fromName,
            civData.firstName or 'Unknown',
            civData.lastName or 'Unknown',
            FormatDOB(civData.dob or civData.dateOfBirth),
            civData.ssn or 'Unknown'
        )
        
        TriggerEvent('chat:addMessage', {
            color = {66, 182, 245},
            args = {'', idText}
        })
    end
    
    if Config.IDCard.UseOxNotify then
        lib.notify({
            title = 'ID Shown by ' .. fromName,
            description = (civData.firstName or 'Unknown') .. ' ' .. (civData.lastName or 'Unknown'),
            type = 'info',
            duration = Config.IDCard.DisplayDuration
        })
    end
end)

RegisterNetEvent('cdecad-civmanager:idRequested', function(requesterId, requesterName)
    if not ActiveCivilian then
        Notify('info', requesterName .. ' requested your ID, but you have no civilian selected.')
        return
    end
    
    local confirm = lib.alertDialog({
        header = 'ID Requested',
        content = '**' .. requesterName .. '** is requesting to see your ID.\n\nShow your ID to them?',
        centered = true,
        cancel = true
    })
    
    if confirm == 'confirm' then
        TriggerServerEvent('cdecad-civmanager:showIDToPlayer', requesterId)
    end
end)


CreateThread(function()
    Wait(3000)
    
    local lastCivId = nil
    
    if Config.Persistence == 'kvp' then
        lastCivId = LoadCivilianFromKVP()
    elseif Config.Persistence == 'mysql' then
        lastCivId = lib.callback.await('cdecad-civmanager:loadLastCivilian', false)
    end
    
    if lastCivId then
        Debug('Found last civilian:', lastCivId)
        
        local result = lib.callback.await('cdecad-civmanager:getCivilian', false, lastCivId)
        
        if result.success and result.civilian then
            ActiveCivilian = result.civilian
            TriggerServerEvent('cdecad-civmanager:selectCivilian', result.civilian)
            Notify('info', 'Restored civilian: ' .. result.civilian.firstName .. ' ' .. result.civilian.lastName)
        else
            Debug('Could not restore civilian, clearing KVP')
            ClearCivilianFromKVP()
        end
    end
end)


exports('GetActiveCivilian', function()
    return ActiveCivilian
end)

exports('HasActiveCivilian', function()
    return ActiveCivilian ~= nil
end)

exports('OpenCivilianSelector', OpenCivilianSelector)


TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.SelectCiv, 'Select a civilian from your CAD account')
TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.ShowInfo, 'Show your current civilian info')
TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.ShowID, 'Show your ID to nearby players')
TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.RegisterVehicle, 'Register your current vehicle')
TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.ClearCiv, 'Clear your civilian selection')


CreateThread(function()
    if not Config.IDCard.UseOxTarget then
        Debug('ox_target integration disabled in config')
        return
    end
    
    Wait(2000)
    
    if GetResourceState('ox_target') ~= 'started' then
        Debug('ox_target not found, skipping target integration')
        return
    end
    
    exports.ox_target:addGlobalPlayer({
        {
            name = 'cdecad_show_id',
            icon = 'fas fa-id-card',
            label = 'Show ID',
            distance = 3.0,
            onSelect = function(data)
                if not ActiveCivilian then
                    Notify('error', 'No civilian selected. Use /' .. Config.Commands.SelectCiv)
                    return
                end
                
                local targetPed = data.entity
                local targetPlayerId = NetworkGetPlayerIndexFromPed(targetPed)
                local targetServerId = GetPlayerServerId(targetPlayerId)
                
                Debug('ox_target Show ID - targetPed:', targetPed, 'targetPlayerId:', targetPlayerId, 'targetServerId:', targetServerId)
                
                if targetServerId and targetServerId > 0 then
                    TriggerServerEvent('cdecad-civmanager:showIDToPlayer', targetServerId)
                    Notify('success', 'Showing ID to player')
                else
                    Notify('error', 'Could not identify target player')
                end
            end,
            canInteract = function(entity, distance, coords, name, bone)
                return ActiveCivilian ~= nil
            end
        },
        {
            name = 'cdecad_request_id',
            icon = 'fas fa-hand-paper',
            label = 'Request ID',
            distance = 3.0,
            onSelect = function(data)
                local targetPed = data.entity
                local targetPlayerId = NetworkGetPlayerIndexFromPed(targetPed)
                local targetServerId = GetPlayerServerId(targetPlayerId)
                
                Debug('ox_target Request ID - targetServerId:', targetServerId)
                
                if targetServerId and targetServerId > 0 then
                    TriggerServerEvent('cdecad-civmanager:requestID', targetServerId)
                    Notify('info', 'Requested ID from player')
                else
                    Notify('error', 'Could not identify target player')
                end
            end
        }
    })
    
    print('[CDECAD-CIVMANAGER] ox_target integration loaded')
end)

print('[CDECAD-CIVMANAGER] Client script loaded')

end
