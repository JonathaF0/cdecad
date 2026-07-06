do
    local Config = CivConfig
--[[
    CDECAD Civilian Manager - Client Script
    Handles commands, UI, and local state
]]

local ActiveCivilian = nil
local IsIDShowing = false
local IsRegisteringVehicle = false

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

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
        -- Fallback to chat
        TriggerEvent('chat:addMessage', {
            color = type == 'success' and {0, 255, 0} or type == 'error' and {255, 0, 0} or {255, 255, 255},
            args = {'[CivManager]', message}
        })
    end
end

-- Get current vehicle info
local function GetCurrentVehicleInfo()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then
        return nil
    end

    -- Strip whitespace; the backend normalizes plates the same way
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
        year = tostring(2020 + math.random(0, 5)) -- GTA doesn't expose a year; fake one
    }
end

-- =============================================================================
-- FRAMEWORK CASH DETECTION
-- =============================================================================

-- Returns the player's current in-game cash, or nil if unknown.
local function GetPlayerCash()
    -- QBCore / QBox
    if GetResourceState('qb-core') == 'started' then
        local ok, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok and QBCore then
            local pd = QBCore.Functions.GetPlayerData()
            if pd and pd.money then
                return pd.money.cash or pd.money['cash'] or 0
            end
        end
    end
    -- ESX
    if GetResourceState('es_extended') == 'started' then
        local ok, ESX = pcall(function() return exports['es_extended']:getSharedObject() end)
        if ok and ESX then
            local pd = ESX.GetPlayerData()
            if pd then return pd.money or 0 end
        end
    end
    return nil -- framework not detected; server will handle validation
end

-- =============================================================================
-- KVP PERSISTENCE (Client-side)
-- =============================================================================

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

-- =============================================================================
-- CIVILIAN SELECTOR UI
-- =============================================================================

local function OpenCivilianSelector()
    -- Fetch civilians from server
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
    
    -- Build options for ox_lib menu
    local options = {}
    
    for _, civ in ipairs(result.civilians) do
        -- Handle different field name formats from API
        local firstName = civ.firstName or civ.firstname or civ.first_name or 'Unknown'
        local lastName = civ.lastName or civ.lastname or civ.last_name or 'Unknown'
        local dob = civ.dob or civ.dateOfBirth or civ.date_of_birth or civ.birthdate or 'Unknown'
        local ssn = civ.ssn or civ.citizenid or civ.id or 'Unknown'
        
        local label = firstName .. ' ' .. lastName
        local description = 'DOB: ' .. tostring(dob)
        
        if ssn and ssn ~= 'Unknown' then
            description = description .. ' | ID: ' .. tostring(ssn)
        end
        
        -- Normalize the civilian data for storage
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
    
    -- Add clear option
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

-- Capture and upload mugshot for the active civilian
local function CaptureMugshotForCivilian(civilianId)
    if GetResourceState('MugShotBase64') ~= 'started' then
        Debug('MugShotBase64 not running, skipping mugshot capture')
        return
    end

    -- Wait a moment so the ped is fully loaded before capturing
    SetTimeout(3000, function()
        local ok, result = pcall(function()
            return exports['MugShotBase64']:GetMugShotBase64(PlayerPedId(), true)
        end)

        if ok and result and result ~= '' then
            Debug('Mugshot captured for civilian:', civilianId)
            TriggerServerEvent('cdecad-civmanager:updateMugshot', civilianId, result)
            -- Update local ActiveCivilian so the ID card shows it immediately this session
            if ActiveCivilian and (ActiveCivilian.id == civilianId or ActiveCivilian._id == civilianId or ActiveCivilian.ssn == civilianId) then
                ActiveCivilian.mugshotUrl = result
            end
        else
            Debug('Mugshot capture failed')
        end
    end)
end

-- Select a civilian
function SelectCivilian(civData)
    Debug('SelectCivilian called with:', json.encode(civData))

    ActiveCivilian = nil

    ActiveCivilian = civData

    -- Save to persistence
    local saveId = civData.ssn or civData.id
    Debug('Saving to KVP with ID:', saveId)
    SaveCivilianToKVP(saveId)

    -- Notify server
    TriggerServerEvent('cdecad-civmanager:selectCivilian', civData)

    Notify('success', 'Now playing as: ' .. (civData.firstName or 'Unknown') .. ' ' .. (civData.lastName or 'Unknown'))

    -- Capture and sync FiveM mugshot (disabled by default - CAD photo is source of truth)
    if Config.CaptureFiveMMugshot then
        local civId = civData.ssn or civData.id or civData._id
        if civId then
            CaptureMugshotForCivilian(civId)
        end
    end

    Debug('ActiveCivilian is now:', ActiveCivilian and (ActiveCivilian.firstName .. ' ' .. ActiveCivilian.lastName) or 'nil')
end

-- Clear current civilian
function ClearCivilian()
    Debug('ClearCivilian called')
    ActiveCivilian = nil
    ClearCivilianFromKVP()
    TriggerServerEvent('cdecad-civmanager:selectCivilian', nil)
    Notify('success', 'Civilian selection cleared')
end

-- =============================================================================
-- COMMANDS
-- =============================================================================

-- /setciv - Open civilian selector
RegisterCommand(Config.Commands.SelectCiv, function()
    OpenCivilianSelector()
end, false)

-- /myciv - Show current civilian info
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

-- /showid - Show ID to nearby players
RegisterCommand(Config.Commands.ShowID, function()
    if not ActiveCivilian then
        Notify('error', 'No civilian selected. Use /' .. Config.Commands.SelectCiv)
        return
    end

    -- Each viewer's NUI fetches the mugshot on demand
    TriggerServerEvent('cdecad-civmanager:showID')
end, false)

-- /bank - Open bank panel
RegisterCommand(Config.Commands.Bank, function()
    if not Config.Bank.Enabled then
        Notify('error', 'Bank is disabled')
        return
    end

    if not ActiveCivilian then
        Notify('error', 'No civilian selected. Use /' .. Config.Commands.SelectCiv)
        return
    end

    local civId = ActiveCivilian.id or ActiveCivilian._id
    if not civId then
        Notify('error', 'Civilian ID not found. Please re-select your civilian.')
        return
    end

    -- Request account data from server then open the bank UI
    local result = lib.callback.await('cdecad-civmanager:getBankAccount', false, civId)

    if not result or not result.success then
        Notify('error', result and result.error or 'Failed to load bank account')
        return
    end

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openBank',
        account = result.account,
        civilian = {
            firstName = ActiveCivilian.firstName,
            lastName = ActiveCivilian.lastName,
            id = civId
        },
        communityId = Config.COMMUNITY_ID,
        playerCash = GetPlayerCash()  -- may be nil if framework not detected
    })
end, false)

-- /adminbank - Open the admin bank panel (CAD authorizes bank employees only)
RegisterCommand(Config.Commands.AdminBank or 'adminbank', function()
    if not (Config.Bank and Config.Bank.AdminEnabled) then
        Notify('error', 'Admin bank is disabled')
        return
    end

    local result = lib.callback.await('cdecad-civmanager:adminBankAccess', false)
    if not result or not result.success then
        Notify('error', result and result.error or 'Access denied')
        return
    end

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openAdminBank',
        communityId = Config.COMMUNITY_ID,
        accounts = result.accounts or {},
        settings = result.settings or {}
    })
end, false)

-- /regveh - Register current vehicle
RegisterCommand(Config.Commands.RegisterVehicle, function()
    if not Config.VehicleRegistration.Enabled then
        Notify('error', 'Vehicle registration is disabled')
        return
    end

    -- Block duplicate submissions while one is pending
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

    -- Confirm registration
    local confirm = lib.alertDialog({
        header = 'Register Vehicle',
        content = string.format('Register this vehicle?\n\n**Plate:** %s\n**Make:** %s\n**Model:** %s\n**Color:** %s\n\n**Fee:** $%d',
            vehicleInfo.plate,
            vehicleInfo.make,
            vehicleInfo.model,
            vehicleInfo.color,
            Config.VehicleRegistration.Fee
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

-- /clearciv - Clear selected civilian
RegisterCommand(Config.Commands.ClearCiv, function()
    ClearCivilian()
end, false)

-- =============================================================================
-- EVENT HANDLERS
-- =============================================================================

-- Receive notification from server
RegisterNetEvent('cdecad-civmanager:notify', function(type, message)
    Notify(type, message)
end)

-- Civilian set confirmation from server
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

-- Format ISO date string (e.g. "1999-01-01T00:00:00.000Z") to MM/DD/YYYY
local function FormatDOB(dob)
    if not dob then return 'Unknown' end
    local y, m, d = tostring(dob):match('(%d%d%d%d)-(%d%d)-(%d%d)')
    if y and m and d then return m .. '/' .. d .. '/' .. y end
    return tostring(dob)
end

-- Receive ID from another player
RegisterNetEvent('cdecad-civmanager:receiveID', function(civData, fromName, cardStyle)
    Debug('Received ID from:', fromName)

    if Config.IDCard.ShowHTML then
        -- Render mode defaults to 'html' when LicenseMode is unset.
        -- The NUI fetches the license image through /fetchLicensePng so the
        -- x-api-key never reaches the browser.
        local mode = (Config.IDCard.LicenseMode or 'html'):lower()
        local civId = civData.id or civData._id or ''
        SendNUIMessage({
            action      = 'showID',
            civilian    = civData,
            from        = fromName,
            duration    = Config.IDCard.DisplayDuration,
            style       = cardStyle or Config.IDCard.CardStyle,
            -- 'template': image only; 'auto': image with fallback to the
            -- styled card; 'html': styled card
            licenseMode = mode,
            civilianId  = civId,
            licenseType = 'drivers',
        })
        SetNuiFocus(false, false)
    end
    
    if Config.IDCard.ShowInChat then
        -- Show in chat/skybox
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

-- Someone requested your ID
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

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

CreateThread(function()
    -- Wait a bit for everything to load
    Wait(3000)
    
    -- Try to load last selected civilian
    local lastCivId = nil
    
    if Config.Persistence == 'kvp' then
        lastCivId = LoadCivilianFromKVP()
    elseif Config.Persistence == 'mysql' then
        lastCivId = lib.callback.await('cdecad-civmanager:loadLastCivilian', false)
    end
    
    if lastCivId then
        Debug('Found last civilian:', lastCivId)
        
        -- Fetch the civilian data
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

-- =============================================================================
-- EXPORTS
-- =============================================================================

exports('GetActiveCivilian', function()
    return ActiveCivilian
end)

exports('HasActiveCivilian', function()
    return ActiveCivilian ~= nil
end)

exports('OpenCivilianSelector', OpenCivilianSelector)

-- =============================================================================
-- CHAT SUGGESTIONS
-- =============================================================================

TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.SelectCiv, 'Select a civilian from your CAD account')
TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.ShowInfo, 'Show your current civilian info')
TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.ShowID, 'Show your ID to nearby players')
TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.Bank, 'Open your bank account')
if Config.Bank and Config.Bank.AdminEnabled and Config.Commands.AdminBank then
    TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.AdminBank, 'Open the admin bank panel (bank employees only)')
end
TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.RegisterVehicle, 'Register your current vehicle')
TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.ClearCiv, 'Clear your civilian selection')

-- =============================================================================
-- OX_TARGET INTEGRATION
-- =============================================================================

CreateThread(function()
    -- Check if ox_target integration is enabled
    if not Config.IDCard.UseOxTarget then
        Debug('ox_target integration disabled in config')
        return
    end
    
    -- Wait for ox_target to be ready
    Wait(2000)
    
    -- Check if ox_target is available
    if GetResourceState('ox_target') ~= 'started' then
        Debug('ox_target not found, skipping target integration')
        return
    end
    
    -- Add target option to players
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
                
                -- Get the target player's server ID
                local targetPed = data.entity
                local targetPlayerId = NetworkGetPlayerIndexFromPed(targetPed)
                local targetServerId = GetPlayerServerId(targetPlayerId)
                
                Debug('ox_target Show ID - targetPed:', targetPed, 'targetPlayerId:', targetPlayerId, 'targetServerId:', targetServerId)
                
                if targetServerId and targetServerId > 0 then
                    -- Send ID to specific player via server
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
