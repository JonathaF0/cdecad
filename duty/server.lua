do
    local Config = DutyConfig

    Config.CAD = Config.CAD or {}
    Config.CAD.Url    = GetConvar('CDE_CAD_API_URL', '')
    Config.CAD.ApiKey = GetConvar('CDE_CAD_API_KEY', '')
    Config.Discord = Config.Discord or {}
    Config.Discord.DepartmentWebhooks = Config.Discord.DepartmentWebhooks or {}
    do
        local function w(d) return GetConvar('CDE_CAD_WEBHOOK_' .. d, '') end
        for _, d in ipairs({'SASP','LCSO','LSPD','BCSO','LSFD','BCFD'}) do
            Config.Discord.DepartmentWebhooks[d:lower()] = w(d)
        end
    end
    Config.Discord.Webhooks = Config.Discord.Webhooks or {}
    Config.Discord.Webhooks.Duty     = GetConvar('CDE_CAD_WEBHOOK_DUTY', '')
    Config.Discord.Webhooks.Paycheck = GetConvar('CDE_CAD_WEBHOOK_PAYCHECK', '')

PlaytimeTracker = {}
OnDutyUnits = {}
OnDutyLEOUnits = {}
OnDutyFireUnits = {}
PlayerCalloutSettings = {}
PlayerDepartments = {}
PlayerPaycheckTimers = {} -- Track individual paycheck timers

print("^2[CDE-DUTY] Server loading...^0")

-- ========================================
-- UTILITY FUNCTIONS
-- ========================================

function GetDiscordID(src)
    local ids = GetPlayerIdentifiers(src)
    for _, id in pairs(ids) do
        if string.sub(id, 1, 8) == "discord:" then
            return string.sub(id, 9)
        end
    end
    return "Not Found"
end

function FormatTime(seconds)
    local mins = math.floor(seconds / 60)
    local hrs = math.floor(mins / 60)
    mins = mins % 60
    return string.format("%02dh %02dm", hrs, mins)
end

-- ========================================
-- CAD DUTY STATUS PUSH
-- ========================================
-- POST /api/ers/duty so the CAD flips the user's status to 10-8 / 10-42.
-- Backend is gated by Config.fivemSettings.ersAutoOnDuty and silently
-- no-ops if the community hasn't enabled it.

local SERVICE_TYPE_BY_DEPT_TYPE = {
    leo  = 'police',
    fire = 'fire',
    ems  = 'ambulance',
}

function PushDutyToCAD(source, onShift, deptType)
    if not Config or not Config.CAD or not Config.CAD.Url or Config.CAD.Url == '' then return end
    if not Config.CAD.ApiKey or Config.CAD.ApiKey == '' then return end

    local discordId = GetDiscordID(source)
    if not discordId or discordId == 'Not Found' then return end

    local payload = json.encode({
        discordId   = discordId,
        onShift     = onShift == true,
        serviceType = SERVICE_TYPE_BY_DEPT_TYPE[deptType or ''],
    })

    local url = (Config.CAD.Url:gsub('/$', '')) .. '/api/ers/duty'
    PerformHttpRequest(url, function(statusCode, body)
        if Config.CAD.Debug then
            print(('^5[CDE-DUTY] CAD duty push (%s) -> HTTP %s^0'):format(
                onShift and 'on' or 'off', tostring(statusCode)))
        end
    end, 'POST', payload, {
        ['Content-Type'] = 'application/json',
        ['x-api-key']    = Config.CAD.ApiKey,
    })
end

-- ========================================
-- CAD BACKEND SYNC (/api/fivem/cde-duty)
-- ========================================
-- Mirrors on/off-duty events to the CAD so the supervisor panel can show
-- in-game duty time alongside CAD duty time. 

function SendCdeDutyToCad(discordId, onShift, department, callSign, durationSec)
    if not Config or not Config.CAD then return end
    if not Config.CAD.Url or Config.CAD.Url == '' then return end
    if not Config.CAD.ApiKey or Config.CAD.ApiKey == '' then return end
    if not discordId or discordId == '' or discordId == 'Not Found' then return end

    local payload = {
        discordId  = discordId,
        onShift    = onShift and true or false,
        department = department or nil,
        callSign   = callSign or nil,
    }
    if (not onShift) and durationSec and durationSec > 0 then
        payload.durationMs = math.floor(durationSec * 1000)
    end

    PerformHttpRequest(Config.CAD.Url .. '/api/fivem/cde-duty', function(statusCode, response)
        if Config.CAD.Debug then
            print(('^3[CDE-DUTY CAD] %s -> HTTP %s^0'):format(onShift and 'on' or 'off', tostring(statusCode)))
        elseif statusCode and statusCode >= 400 then
            print(('^1[CDE-DUTY CAD] HTTP %s: %s^0'):format(tostring(statusCode), tostring(response):sub(1, 200)))
        end
    end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json',
        ['x-api-key']    = Config.CAD.ApiKey,
    })
end

-- ========================================
-- WEBHOOK FUNCTION
-- ========================================

function SendDutyWebhook(department, title, description, color)
    if not Config then return end
    if not Config.Discord then return end
    if not Config.Discord.Enabled then return end
    
    local webhookUrl = nil
    
    if department and Config.Discord.DepartmentWebhooks then
        webhookUrl = Config.Discord.DepartmentWebhooks[department]
    end
    
    if not webhookUrl or webhookUrl == "" then
        if Config.Discord.Webhooks and Config.Discord.Webhooks.Duty then
            webhookUrl = Config.Discord.Webhooks.Duty
        end
    end
    
    if not webhookUrl or webhookUrl == "" then
        return
    end
    
    if not color and Config.Discord.Colors then
        if department and Config.Discord.Colors[department] then
            color = Config.Discord.Colors[department]
        else
            color = 65280
        end
    end
    
    local embed = {
        {
            title = title,
            description = description,
            color = color or 65280,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            footer = {
                text = "CDE Duty System"
            }
        }
    }
    
    PerformHttpRequest(webhookUrl, function(err, text, headers)
    end, 'POST', json.encode({
        username = "CDE Duty System",
        embeds = embed
    }), { ['Content-Type'] = 'application/json' })
end

-- ========================================
-- INDIVIDUAL PAYCHECK TIMER
-- ========================================

function StartPaycheckTimer(playerId, department)
    if not Config or not Config.Paychecks or not Config.Paychecks.Enabled then
        return
    end
    
    -- Kill any existing timer for this player
    if PlayerPaycheckTimers[playerId] then
        PlayerPaycheckTimers[playerId] = nil
    end
    
    -- Get paycheck amount
    local amount = Config.Paychecks.OnDutyPay or 500
    
    if department and Config.Departments[department] and Config.Departments[department].paycheck then
        amount = Config.Departments[department].paycheck
    end
    
    -- Schedule paycheck for 30 minutes (1800000ms) from now
    local payInterval = (Config.Paychecks.Interval or 30) * 60000 -- Config value in minutes, convert to ms
    
    print("^3[CDE-DUTY] Scheduled paycheck for " .. GetPlayerName(playerId) .. " in " .. (payInterval / 60000) .. " minutes ($" .. amount .. ")^0")
    
    PlayerPaycheckTimers[playerId] = SetTimeout(payInterval, function()
        -- Check if player is still on duty
        local stillOnDuty = false
        for _, unitId in ipairs(OnDutyUnits) do
            if unitId == playerId then
                stillOnDuty = true
                break
            end
        end
        
        if stillOnDuty and GetPlayerName(playerId) then
            -- Add cash using pefcl export
            local success = exports.pefcl:addCash(playerId, amount)
            
            if success then
                TriggerClientEvent('chat:addMessage', playerId, {
                    color = {0, 255, 0},
                    args = {"[PAYCHECK]", "You received $" .. amount .. " (on duty for " .. (Config.Paychecks.Interval or 30) .. " mins)"}
                })
                
                print("^2[CDE-DUTY] Paid " .. GetPlayerName(playerId) .. " $" .. amount .. "^0")
                
                -- Reschedule next paycheck
                StartPaycheckTimer(playerId, PlayerDepartments[playerId])
            else
                print("^1[CDE-DUTY] Failed to pay " .. GetPlayerName(playerId) .. "^0")
                -- Reschedule next paycheck anyway
                StartPaycheckTimer(playerId, PlayerDepartments[playerId])
            end
        else
            print("^3[CDE-DUTY] Paycheck timer expired for player (went off duty or disconnected)^0")
        end
    end)
end

-- ========================================
-- MAIN DUTY COMMAND
-- ========================================

RegisterCommand("d", function(source, args, rawCommand)
    if source == 0 then return end
    
    local type = args[1]
    local playerName = GetPlayerName(source)
    
    if not type then
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 0, 0},
            args = {"[DUTY]", "Usage: /d [sasp/lcso/lspd/bcso/lsfd/bcfd/off]"}
        })
        return
    end
    
    type = string.lower(type)
    
    if type == "off" then
        -- GO OFF DUTY
        local wasOnDuty = false
        local department = PlayerDepartments[source]
        
        for i = #OnDutyUnits, 1, -1 do
            if OnDutyUnits[i] == source then
                table.remove(OnDutyUnits, i)
                wasOnDuty = true
            end
        end
        
        for i = #OnDutyLEOUnits, 1, -1 do
            if OnDutyLEOUnits[i] == source then
                table.remove(OnDutyLEOUnits, i)
            end
        end
        
        for i = #OnDutyFireUnits, 1, -1 do
            if OnDutyFireUnits[i] == source then
                table.remove(OnDutyFireUnits, i)
            end
        end
        
        -- Cancel pending paycheck
        if PlayerPaycheckTimers[source] then
            print("^3[CDE-DUTY] Cancelled pending paycheck for " .. playerName .. "^0")
            PlayerPaycheckTimers[source] = nil
        end
        
        if not wasOnDuty then
            TriggerClientEvent('chat:addMessage', source, {
                color = {255, 255, 0},
                args = {"[DUTY]", "You are not on duty!"}
            })
            return
        end
        
        local dutyStart = PlaytimeTracker[source]
        local timePlayed = 0
        if dutyStart then
            timePlayed = os.time() - dutyStart
        end
        PlaytimeTracker[source] = nil
        local formattedTime = FormatTime(timePlayed)
        
        -- Clear radio
        TriggerClientEvent("CDE:SetRadioAgency", source, nil)
        
        -- Notify client off duty
        TriggerClientEvent("CDE:ConfirmOffDuty", source)
        
        -- Update LEO status for 911 system
        TriggerClientEvent('CDE:SetLEOStatus', source, false)
        
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 0, 0},
            args = {"[DUTY]", "You are now OFF DUTY (Time: " .. formattedTime .. ")"}
        })
        
        -- Send webhook
        if department and Config and Config.Departments and Config.Departments[department] then
            local deptInfo = Config.Departments[department]
            local discordId = GetDiscordID(source)
            SendDutyWebhook(department,
                "Officer Off Duty",
                "**Officer:** " .. playerName .. "\n" ..
                "**Department:** " .. deptInfo.name .. "\n" ..
                "**Time on Duty:** " .. formattedTime .. "\n" ..
                "**Discord:** <@" .. discordId .. ">",
                16711680
            )
            PushDutyToCAD(source, false, deptInfo.type)
            local cadDept = deptInfo.cadShortName or deptInfo.shortName or deptInfo.name or department
            SendCdeDutyToCad(discordId, false, cadDept, deptInfo.callSign, timePlayed)
        end

        PlayerDepartments[source] = nil
        
        print("^1[CDE-DUTY] " .. playerName .. " went off duty after " .. formattedTime .. "^0")
        
    else
        -- GO ON DUTY
        if not Config or not Config.Departments then
            print("^1[CDE-DUTY] Config not loaded!^0")
            return
        end
        
        local deptConfig = Config.Departments[type]
        
        if not deptConfig then
            TriggerClientEvent('chat:addMessage', source, {
                color = {255, 0, 0},
                args = {"[DUTY]", "Invalid department!"}
            })
            return
        end
        
        -- Check if already on duty
        for _, unitId in ipairs(OnDutyUnits) do
            if unitId == source then
                TriggerClientEvent('chat:addMessage', source, {
                    color = {255, 255, 0},
                    args = {"[DUTY]", "Already on duty! Use /d off first."}
                })
                return
            end
        end
        
        -- Add to duty
        table.insert(OnDutyUnits, source)
        PlayerDepartments[source] = type
        
        if deptConfig.type == "leo" then
            table.insert(OnDutyLEOUnits, source)
            TriggerClientEvent('CDE:SetLEOStatus', source, true)
        else
            table.insert(OnDutyFireUnits, source)
        end
        
        PlaytimeTracker[source] = os.time()
        
        -- Start individual paycheck timer (30 mins from clock-in)
        StartPaycheckTimer(source, type)
        
        -- Set radio - use lowercase department code (not callSign)
        local radioAgency = string.lower(type) -- Use the department code (sasp, lcso, etc)
        TriggerClientEvent("CDE:SetRadioAgency", source, radioAgency)
        print("^2[CDE-DUTY] Setting radio agency to: " .. radioAgency .. "^0")
        
        -- Send bodycam overlay event (not recording, just overlay)
        TriggerClientEvent("CDE:ConfirmOnDutyDepartment", source, type, deptConfig)
        
        TriggerClientEvent('chat:addMessage', source, {
            color = {0, 255, 0},
            args = {"[DUTY]", "You are now ON DUTY as " .. deptConfig.name}
        })
        
        -- Send webhook
        local discordId = GetDiscordID(source)
        SendDutyWebhook(type,
            "Officer On Duty",
            "**Officer:** " .. playerName .. "\n" ..
            "**Department:** " .. deptConfig.name .. "\n" ..
            "**Discord:** <@" .. discordId .. ">",
            65280
        )

        PushDutyToCAD(source, true, deptConfig.type)
        do
            local cadDept = deptConfig.cadShortName or deptConfig.shortName or deptConfig.name or type
            SendCdeDutyToCad(discordId, true, cadDept, deptConfig.callSign, nil)
        end

        print("^2[CDE-DUTY] " .. playerName .. " on duty as " .. deptConfig.name .. "^0")
    end
end, false)

RegisterCommand("duty", function(source, args, rawCommand)
    if source == 0 then return end
    ExecuteCommand("d " .. (args[1] or ""))
end, false)

-- ========================================
-- TRAFFIC STOP (/ts) -> CAD BACKEND
-- ========================================
-- The /ts command is fired client-side from the Wraith plate reader workflow.
-- We forward it to /api/fivem/traffic-stop on the CAD backend, which creates
-- a Traffic Stop call and auto-attaches the unit (resolved by Discord ID).

local TS_B64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function TSBase64Encode(data)
    return ((data:gsub('.', function(x)
        local r, b = '', x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2^i - b % 2^(i-1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i,i) == '1' and 2^(6-i) or 0) end
        return TS_B64_CHARS:sub(c+1, c+1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

local trafficStopCooldowns = {}

-- Wraith ARS 2X fires `wk:onPlateLocked` as a server-side net event only.
-- Mirror it back to the originating client so the duty system can remember
-- the locked plate for /ts.  
RegisterNetEvent('wk:onPlateLocked')
AddEventHandler('wk:onPlateLocked', function(cam, plate, index)
    local src = source
    if not plate or plate == '' then return end
    TriggerClientEvent('CDE:WraithPlateLocked', src, cam, plate, index)
end)

RegisterNetEvent('CDE:TrafficStop')
AddEventHandler('CDE:TrafficStop', function(data)
    local src = source
    if not data or not data.plate or data.plate == '' then return end

    -- LEO-on-duty enforcement (server-authoritative)
    if not Config or not Config.TrafficStop or Config.TrafficStop.RequireLEO ~= false then
        local isLEO = false
        for _, unitId in ipairs(OnDutyLEOUnits) do
            if unitId == src then isLEO = true break end
        end
        if not isLEO then
            TriggerClientEvent('CDE:TrafficStopResult', src, {
                success = false,
                msg = 'You must be on duty as LEO.'
            })
            return
        end
    end

    -- Cooldown
    local cd = (Config.TrafficStop and Config.TrafficStop.CooldownSeconds) or 5
    local now = os.time()
    if trafficStopCooldowns[src] and (now - trafficStopCooldowns[src]) < cd then
        TriggerClientEvent('CDE:TrafficStopResult', src, {
            success = false,
            msg = string.format('Cooldown active (%ds).', cd - (now - trafficStopCooldowns[src]))
        })
        return
    end
    trafficStopCooldowns[src] = now

    if not Config.CAD or not Config.CAD.Url or Config.CAD.Url == '' then
        print('^1[CDE-DUTY TS] Config.CAD.Url is not configured^0')
        TriggerClientEvent('CDE:TrafficStopResult', src, {
            success = false,
            msg = 'CAD URL not configured.'
        })
        return
    end
    if not Config.CAD.ApiKey or Config.CAD.ApiKey == '' then
        print('^1[CDE-DUTY TS] Config.CAD.ApiKey is not configured^0')
        TriggerClientEvent('CDE:TrafficStopResult', src, {
            success = false,
            msg = 'CAD API key not configured.'
        })
        return
    end

    -- Resolve callSign from the player's current department
    local department = PlayerDepartments[src]
    local callSign
    if department and Config.Departments[department] then
        callSign = Config.Departments[department].callSign
    end

    local discordId = GetDiscordID(src)
    if discordId == 'Not Found' then discordId = nil end

    local plate = string.upper((data.plate:gsub('%s', '')))

    local payload = {
        plate       = plate,
        discordId   = discordId,
        callSign    = callSign,
        location    = data.location or 'Unknown',
        postal      = data.postal or '',
        coordinates = data.coords or { x = 0, y = 0, z = 0 },
    }
    local body = json.encode(payload)
    local url  = Config.CAD.Url .. '/api/fivem/traffic-stop'

    if Config.CAD.Debug then
        print(('^3[CDE-DUTY TS] POST %s body=%s^0'):format(url, body))
    end

    PerformHttpRequest(url, function(statusCode, response, headers)
        local ok, parsed = pcall(json.decode, response or '')

        if statusCode == 201 and ok and parsed and parsed.success then
            print(('^2[CDE-DUTY TS] %s opened on plate %s (alert=%s) for %s^0'):format(
                tostring(parsed.incidentNumber),
                plate,
                tostring(parsed.alertLevel),
                GetPlayerName(src) or '?'
            ))
            TriggerClientEvent('CDE:TrafficStopResult', src, {
                success        = true,
                incidentNumber = parsed.incidentNumber,
                plate          = parsed.plate or plate,
                alertLevel     = parsed.alertLevel,
                flags          = (parsed.flags and #parsed.flags > 0) and table.concat(parsed.flags, ', ') or '',
                vehicle        = parsed.vehicle,
                owner          = parsed.owner,
                bolo           = parsed.bolo,
                ownerBolo      = parsed.ownerBolo,
            })
        else
            local msg = (ok and parsed and parsed.msg) or ('HTTP ' .. tostring(statusCode))
            print(('^1[CDE-DUTY TS] Error %s on plate %s: %s^0'):format(tostring(statusCode), plate, msg))
            TriggerClientEvent('CDE:TrafficStopResult', src, {
                success = false,
                msg     = msg,
                plate   = plate,
            })
        end
    end, 'POST', body, {
        ['Content-Type'] = 'application/json',
        ['x-api-key']    = Config.CAD.ApiKey,
        ['x-payload']    = TSBase64Encode(body),
    })
end)

AddEventHandler('playerDropped', function()
    trafficStopCooldowns[source] = nil
end)

-- ========================================
-- 911 CALL FORWARDING
-- ========================================

-- Server-only event (no RegisterNetEvent); clients cannot trigger.
AddEventHandler('cad:forward911ToUnits', function(callData)
    local totalUnits = #OnDutyLEOUnits + #OnDutyFireUnits
    
    print("^1[911] Forwarding to " .. totalUnits .. " units^0")
    
    for _, unitId in ipairs(OnDutyLEOUnits) do
        if GetPlayerName(unitId) then
            TriggerClientEvent("CDE:Receive911", unitId, callData)
        end
    end
    
    for _, unitId in ipairs(OnDutyFireUnits) do
        if GetPlayerName(unitId) then
            TriggerClientEvent("CDE:Receive911", unitId, callData)
        end
    end
end)

-- ========================================
-- LEO STATUS CHECK FOR 911
-- ========================================

RegisterNetEvent('cad:requestLEOStatus')
AddEventHandler('cad:requestLEOStatus', function()
    local source = source
    local isLEO = false
    
    for _, unitId in ipairs(OnDutyLEOUnits) do
        if unitId == source then
            isLEO = true
            break
        end
    end
    
    TriggerClientEvent('CDE:SetLEOStatus', source, isLEO)
end)

-- ========================================
-- CALLOUT TOGGLES
-- ========================================

RegisterCommand("togglecallouts", function(source, args)
    if source == 0 then return end
    
    if not PlayerCalloutSettings[source] then
        PlayerCalloutSettings[source] = {showCallouts = true}
    end
    
    PlayerCalloutSettings[source].showCallouts = not PlayerCalloutSettings[source].showCallouts
    
    local status = PlayerCalloutSettings[source].showCallouts and "ENABLED" or "DISABLED"
    
    TriggerClientEvent('chat:addMessage', source, {
        color = {0, 255, 0},
        args = {"[CALLOUTS]", "911 callouts are now " .. status}
    })
    
    TriggerClientEvent("CDE:UpdateCalloutSettings", source, PlayerCalloutSettings[source])
end, false)

RegisterCommand("callouts", function(source, args)
    if source == 0 then return end
    ExecuteCommand("togglecallouts")
end, false)

-- ========================================
-- DUTY LIST
-- ========================================

RegisterCommand("dutylist", function(source, args)
    local message = "=== ON-DUTY UNITS ===\n"
    message = message .. "LEO: " .. #OnDutyLEOUnits .. " units\n"
    message = message .. "Fire/EMS: " .. #OnDutyFireUnits .. " units\n"
    
    for _, unitId in ipairs(OnDutyUnits) do
        local name = GetPlayerName(unitId)
        if name then
            local dept = PlayerDepartments[unitId] or "unknown"
            message = message .. name .. " (" .. dept .. ")\n"
        end
    end
    
    if source == 0 then
        print(message)
    else
        TriggerClientEvent("chat:addMessage", source, {
            color = {0, 255, 0},
            multiline = true,
            args = {"[DUTY]", message}
        })
    end
end, false)

-- ========================================
-- DISCONNECT HANDLER
-- ========================================

AddEventHandler("playerDropped", function(reason)
    local serverId = source
    local playerName = GetPlayerName(serverId) or "Unknown"
    local department = PlayerDepartments[serverId]

    local wasOnDuty = false
    
    for i = #OnDutyUnits, 1, -1 do
        if OnDutyUnits[i] == serverId then
            table.remove(OnDutyUnits, i)
            wasOnDuty = true
            break
        end
    end
    
    for i = #OnDutyLEOUnits, 1, -1 do
        if OnDutyLEOUnits[i] == serverId then
            table.remove(OnDutyLEOUnits, i)
            break
        end
    end
    
    for i = #OnDutyFireUnits, 1, -1 do
        if OnDutyFireUnits[i] == serverId then
            table.remove(OnDutyFireUnits, i)
            break
        end
    end
    
    -- Cancel pending paycheck
    if PlayerPaycheckTimers[serverId] then
        PlayerPaycheckTimers[serverId] = nil
    end
    
    if wasOnDuty then
        print("^3[CDE-DUTY] " .. playerName .. " disconnected while on duty^0")
        local discordId = GetDiscordID(serverId)
        local dutyStart = PlaytimeTracker[serverId]
        local timePlayed = dutyStart and (os.time() - dutyStart) or 0

        if department and Config and Config.Departments and Config.Departments[department] then
            local deptInfo = Config.Departments[department]
            PushDutyToCAD(serverId, false, deptInfo.type)
            local cadDept = deptInfo.cadShortName or deptInfo.shortName or deptInfo.name or department
            local cadCallSign = deptInfo.callSign
            SendCdeDutyToCad(discordId, false, cadDept, cadCallSign, timePlayed)
        else
            -- Department config is gone (deleted while the player was on
            -- duty?) , still close the CAD-side session
            SendCdeDutyToCad(discordId, false, department, nil, timePlayed)
        end
    end

    PlayerCalloutSettings[serverId] = nil
    PlayerDepartments[serverId] = nil
    PlaytimeTracker[serverId] = nil
end)

-- ========================================
-- RESOURCE LIFECYCLE
-- ========================================
-- Close every in-game duty session on the CAD when this resource is stopped
-- (server shutdown, manual restart, etc.). 
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    print("^3[CDE-DUTY] Resource stopping , closing CAD duty sessions for " .. #OnDutyUnits .. " players^0")
    for _, serverId in ipairs(OnDutyUnits) do
        local discordId = GetDiscordID(serverId)
        local department = PlayerDepartments[serverId]
        local dutyStart = PlaytimeTracker[serverId]
        local timePlayed = dutyStart and (os.time() - dutyStart) or 0
        local cadDept = department
        local cadCallSign = nil
        if department and Config and Config.Departments and Config.Departments[department] then
            local deptInfo = Config.Departments[department]
            cadDept = deptInfo.cadShortName or deptInfo.shortName or deptInfo.name or department
            cadCallSign = deptInfo.callSign
        end
        SendCdeDutyToCad(discordId, false, cadDept, cadCallSign, timePlayed)
    end
end)

-- ========================================
-- EXPORTS
-- ========================================

exports('GetOnDutyUnits', function() return OnDutyUnits end)
exports('GetOnDutyLEOUnits', function() return OnDutyLEOUnits end)
exports('GetOnDutyFireUnits', function() return OnDutyFireUnits end)

exports('IsPlayerOnDutyLEO', function(playerId)
    for _, unitId in ipairs(OnDutyLEOUnits) do
        if unitId == playerId then
            return true
        end
    end
    return false
end)

exports('IsPlayerOnDuty', function(playerId)
    for _, unitId in ipairs(OnDutyUnits) do
        if unitId == playerId then
            return true
        end
    end
    return false
end)

-- ========================================
-- STARTUP
-- ========================================

Citizen.CreateThread(function()
    Citizen.Wait(1000)
    print("^2========================================^0")
    print("^2     CDE DUTY SYSTEM v4.0.0            ^0")
    print("^2     MODIFIED: Individual Paychecks    ^0")
    print("^2========================================^0")
    print("^2Features:^0")
    print("  - Department duty system")
    print("  - 911 call forwarding")
    print("  - LEO status for CAD-911")
    print("  - Radio integration")
    print("  - Webhook support")
    print("  - Individual paycheck timers (no bulk payouts)")
    print("^2Commands:^0")
    print("  /d [dept/off] - Toggle duty")
    print("  /dutylist - Show on-duty units")
    print("  /togglecallouts - Toggle 911 calls")
    print("^2Paycheck System:^0")
    print("  - Each player gets paid 30 mins after clocking in")
    print("  - Joe clocks in at 9:02 → gets paid at 9:32")
    print("  - You clock in at 9:05 → get paid at 9:35")
    print("  - Prevents server lag from bulk payouts")
    print("^2========================================^0")
end)

print("^2[CDE-DUTY] Server loaded successfully^0")
end
