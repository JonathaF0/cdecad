do
    local Config = DutyConfig

    Config.CAD = Config.CAD or {}
    Config.CAD.Url    = GetConvar('CDE_CAD_API_URL', ''):gsub('/$', ''):gsub('/[Aa][Pp][Ii]$', '')
    Config.CAD.ApiKey = GetConvar('CDE_CAD_API_KEY', '')
    Config.Discord = Config.Discord or {}
    Config.Discord.DepartmentWebhooks = Config.Discord.DepartmentWebhooks or {}
    do
        local codes = GetConvar('CDE_CAD_WEBHOOK_DEPTS', '')
        for code in string.gmatch(codes, '([^,%s]+)') do
            Config.Discord.DepartmentWebhooks[code:lower()] = GetConvar('CDE_CAD_WEBHOOK_' .. code:upper(), '')
        end
    end
    Config.Discord.Webhooks = Config.Discord.Webhooks or {}
    Config.Discord.Webhooks.Duty     = GetConvar('CDE_CAD_WEBHOOK_DUTY', '')
    Config.Discord.Webhooks.Paycheck = GetConvar('CDE_CAD_WEBHOOK_PAYCHECK', '')

    local function BuildDeptTable(list)
        local out = {}
        for _, d in ipairs(list or {}) do
            if d.code and d.code ~= '' then
                out[d.code] = {
                    name       = d.name or d.code,
                    type       = d.type or 'leo',
                    color      = tonumber(d.blipColor) or 38,
                    blipSprite = tonumber(d.blipSprite) or 60,
                    paycheck   = tonumber(d.paycheck) or 1500,
                    callSign   = d.callSign or '',
                }
            end
        end
        return out
    end

    local function PullDepartments(onDone)
        if Config.CAD.Url == '' or Config.CAD.ApiKey == '' then
            print('^3[CDE-DUTY] CAD url/key not set - using local Config.Departments fallback^0')
            if onDone then onDone(false, 'CAD url/key not set') end
            return
        end
        local url = Config.CAD.Url:gsub('/$', '') .. '/api/civilian/fivem-departments'
        PerformHttpRequest(url, function(status, body)
            if status ~= 200 or not body or body == '' then
                print('^1[CDE-DUTY] Department pull failed (HTTP ' .. tostring(status) .. ') - using local fallback^0')
                if onDone then onDone(false, 'HTTP ' .. tostring(status)) end
                return
            end
            local ok, data = pcall(json.decode, body)
            if not ok or type(data) ~= 'table' or type(data.departments) ~= 'table' or #data.departments == 0 then
                print('^1[CDE-DUTY] Department pull returned no departments - using local fallback^0')
                if onDone then onDone(false, 'no departments returned') end
                return
            end
            Config.Departments = BuildDeptTable(data.departments)
            print('^2[CDE-DUTY] Pulled ' .. tostring(#data.departments) .. ' departments from the CAD^0')
            if onDone then onDone(true, #data.departments) end
        end, 'GET', '', { ['x-api-key'] = Config.CAD.ApiKey, ['Content-Type'] = 'application/json' })
    end

    CreateThread(function()
        PullDepartments()
    end)

    RegisterCommand('refreshdepts', function(source)
        if source ~= 0 and not IsPlayerAceAllowed(source, 'command.refreshdepts') then
            return
        end
        local function reply(msg, color)
            if source == 0 then
                print(msg)
            else
                TriggerClientEvent('chat:addMessage', source, {
                    color = color or {255, 255, 0},
                    args = {'[DUTY]', msg}
                })
            end
        end
        reply('Refreshing departments from the CAD…')
        PullDepartments(function(ok, info)
            if ok then
                reply('Departments refreshed - ' .. tostring(info) .. ' loaded from the CAD.', {0, 255, 0})
            else
                reply('Department refresh failed (' .. tostring(info) .. ') - keeping current list.', {255, 0, 0})
            end
        end)
    end, true)

PlaytimeTracker = {}
OnDutyUnits = {}
OnDutyLEOUnits = {}
OnDutyFireUnits = {}
PlayerCalloutSettings = {}
PlayerDepartments = {}
PlayerPaycheckTimers = {}
PlayerPaycheckGen = {}

print("^2[CDE-DUTY] Server loading...^0")


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

function PayPlayerWage(playerId, amount, department, onDone)
    local activeCiv = (CDECAD_GetActiveCivilian and CDECAD_GetActiveCivilian(playerId)) or nil
    local civId = activeCiv and tostring(activeCiv._id or activeCiv.id or activeCiv.ssn or '') or ''
    if civId == '' then
        if onDone then onDone('nociv') end
        return
    end

    local base = ((Config.CAD and Config.CAD.Url) or GetConvar('CDE_CAD_API_URL', '')):gsub('/$', '')
    if base == '' then
        if onDone then onDone('failed') end
        return
    end
    if not base:find('/api$') then base = base .. '/api' end
    local apiKey      = (Config.CAD and Config.CAD.ApiKey) or GetConvar('CDE_CAD_API_KEY', '')
    local communityId = GetConvar('CDE_CAD_COMMUNITY_ID', '')

    local discordId = GetDiscordID(playerId)
    if discordId == 'Not Found' then discordId = nil end

    local body = json.encode({
        civilianId  = civId,
        communityId = communityId,
        amount      = amount,
        department  = department,
        discordId   = discordId,
    })
    PerformHttpRequest(base .. '/civilian/fivem-paycheck', function(status, resp)
        if status < 200 or status >= 300 then
            if onDone then onDone('failed') end
            return
        end
        local ok, data = pcall(json.decode, resp)
        if ok and type(data) == 'table' and data.ok then
            if onDone then onDone('paid', tonumber(data.amount) or amount, tonumber(data.balance)) end
        else
            if onDone then onDone('failed') end
        end
    end, 'POST', body, { ['Content-Type'] = 'application/json', ['x-api-key'] = apiKey })
end


function StartPaycheckTimer(playerId, department)
    if not Config or not Config.Paychecks or not Config.Paychecks.Enabled then
        return
    end
    
    local gen = (PlayerPaycheckGen[playerId] or 0) + 1
    PlayerPaycheckGen[playerId] = gen
    PlayerPaycheckTimers[playerId] = true

    local amount = Config.Paychecks.OnDutyPay or 500

    if department and Config.Departments[department] and Config.Departments[department].paycheck then
        amount = Config.Departments[department].paycheck
    end

    local payInterval = (Config.Paychecks.Interval or 30) * 60000

    print("^3[CDE-DUTY] Scheduled paycheck for " .. GetPlayerName(playerId) .. " in " .. (payInterval / 60000) .. " minutes ($" .. amount .. ")^0")

    SetTimeout(payInterval, function()
        if PlayerPaycheckGen[playerId] ~= gen then return end

        local stillOnDuty = false
        for _, unitId in ipairs(OnDutyUnits) do
            if unitId == playerId then
                stillOnDuty = true
                break
            end
        end

        if stillOnDuty and GetPlayerName(playerId) then
            PayPlayerWage(playerId, amount, department, function(result, paidAmount, balance)
                if PlayerPaycheckGen[playerId] ~= gen then return end

                if result == 'paid' then
                    local shown = paidAmount or amount
                    TriggerClientEvent('chat:addMessage', playerId, {
                        color = {0, 255, 0},
                        args = {"[PAYCHECK]", "You received $" .. shown .. " (on duty for " .. (Config.Paychecks.Interval or 30) .. " mins)"}
                    })
                    TriggerClientEvent('CDE:ReceivePaycheck', playerId, shown, balance)
                    print("^2[CDE-DUTY] Paid " .. GetPlayerName(playerId) .. " $" .. shown
                        .. (balance and (" (civ balance $" .. balance .. ")") or "") .. "^0")
                elseif result == 'nociv' then
                    print("^3[CDE-DUTY] Paycheck skipped for " .. GetPlayerName(playerId)
                        .. " - no civilian selected (/setciv)^0")
                else
                    print("^1[CDE-DUTY] Paycheck deposit failed for " .. GetPlayerName(playerId) .. " (CAD error)^0")
                end

                StartPaycheckTimer(playerId, PlayerDepartments[playerId])
            end)
        else
            print("^3[CDE-DUTY] Paycheck timer expired for player (went off duty or disconnected)^0")
        end
    end)
end


local function buildDeptUsage()
    if not Config or not Config.Departments then
        return "Usage: /d [department/off]"
    end
    local keys = {}
    for k in pairs(Config.Departments) do keys[#keys + 1] = k end
    table.sort(keys)
    keys[#keys + 1] = "off"
    return "Usage: /d [" .. table.concat(keys, "/") .. "]"
end

RegisterCommand("d", function(source, args, rawCommand)
    if source == 0 then return end

    local type = args[1]
    local playerName = GetPlayerName(source)

    if not type then
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 0, 0},
            args = {"[DUTY]", buildDeptUsage()}
        })
        return
    end
    
    type = string.lower(type)
    
    if type == "off" then
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
        
        if PlayerPaycheckTimers[source] then
            print("^3[CDE-DUTY] Cancelled pending paycheck for " .. playerName .. "^0")
            PlayerPaycheckTimers[source] = nil
            PlayerPaycheckGen[source] = (PlayerPaycheckGen[source] or 0) + 1
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
        
        TriggerClientEvent("CDE:SetRadioAgency", source, nil)
        
        TriggerClientEvent("CDE:ConfirmOffDuty", source)
        
        TriggerClientEvent('CDE:SetLEOStatus', source, false)
        
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 0, 0},
            args = {"[DUTY]", "You are now OFF DUTY (Time: " .. formattedTime .. ")"}
        })
        
        local discordId = GetDiscordID(source)
        if department and Config and Config.Departments and Config.Departments[department] then
            local deptInfo = Config.Departments[department]
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
        elseif department then
            PushDutyToCAD(source, false, nil)
            SendCdeDutyToCad(discordId, false, department, nil, timePlayed)
        end

        PlayerDepartments[source] = nil
        
        print("^1[CDE-DUTY] " .. playerName .. " went off duty after " .. formattedTime .. "^0")
        
    else
        if not Config or not Config.Departments then
            print("^1[CDE-DUTY] Config not loaded!^0")
            return
        end
        
        local deptConfig = Config.Departments[type]

        if not deptConfig and Config.DutyTypes and Config.DutyTypes[type] then
            local aliased = Config.DutyTypes[type]
            if Config.Departments[aliased] then
                type = aliased
                deptConfig = Config.Departments[aliased]
            end
        end

        if not deptConfig then
            TriggerClientEvent('chat:addMessage', source, {
                color = {255, 0, 0},
                args = {"[DUTY]", "Invalid department!"}
            })
            return
        end
        
        for _, unitId in ipairs(OnDutyUnits) do
            if unitId == source then
                TriggerClientEvent('chat:addMessage', source, {
                    color = {255, 255, 0},
                    args = {"[DUTY]", "Already on duty! Use /d off first."}
                })
                return
            end
        end
        
        table.insert(OnDutyUnits, source)
        PlayerDepartments[source] = type
        
        if deptConfig.type == "leo" then
            table.insert(OnDutyLEOUnits, source)
            TriggerClientEvent('CDE:SetLEOStatus', source, true)
        else
            table.insert(OnDutyFireUnits, source)
        end
        
        PlaytimeTracker[source] = os.time()
        
        StartPaycheckTimer(source, type)
        
        local radioAgency = string.lower(type)
        TriggerClientEvent("CDE:SetRadioAgency", source, radioAgency)
        print("^2[CDE-DUTY] Setting radio agency to: " .. radioAgency .. "^0")
        
        TriggerClientEvent("CDE:ConfirmOnDutyDepartment", source, type, deptConfig)
        
        TriggerClientEvent('chat:addMessage', source, {
            color = {0, 255, 0},
            args = {"[DUTY]", "You are now ON DUTY as " .. deptConfig.name}
        })
        
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

RegisterNetEvent('wk:onPlateLocked')
AddEventHandler('wk:onPlateLocked', function(cam, plate, index)
    local src = source
    if not plate or plate == '' then return end
    TriggerClientEvent('CDE:WraithPlateLocked', src, cam, plate, index)
end)

RegisterNetEvent('CDE:TrafficStop')
AddEventHandler('CDE:TrafficStop', function(data)
    local src = source
    if not data or type(data) ~= 'table' or type(data.plate) ~= 'string' or data.plate == '' then return end

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

RegisterNetEvent('CDE:RequestRoute911')
AddEventHandler('CDE:RequestRoute911', function()
    local src = source
    if not Config or not Config.CAD or not Config.CAD.Url or Config.CAD.Url == ''
       or not Config.CAD.ApiKey or Config.CAD.ApiKey == '' then
        TriggerClientEvent('CDE:Route911Result', src, { success = false, reason = 'noconfig' })
        return
    end

    local discordId = GetDiscordID(src)
    if discordId == 'Not Found' then discordId = '' end

    local url = Config.CAD.Url .. '/api/fivem/route-call?discordId=' .. discordId
    PerformHttpRequest(url, function(statusCode, response)
        local ok, parsed = pcall(json.decode, response or '')
        if statusCode == 200 and ok and parsed and parsed.success
           and parsed.call and parsed.call.coordinates then
            local c = parsed.call.coordinates
            if type(c.x) == 'number' and type(c.y) == 'number' then
                TriggerClientEvent('CDE:Route911Result', src, {
                    success  = true,
                    coords   = { x = c.x, y = c.y, z = c.z or 0.0 },
                    location = parsed.call.location,
                    id       = parsed.call.id,
                })
                return
            end
        end
        TriggerClientEvent('CDE:Route911Result', src, { success = false, reason = 'nocall' })
    end, 'GET', '', { ['x-api-key'] = Config.CAD.ApiKey, ['Content-Type'] = 'application/json' })
end)


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


RegisterCommand("dutycallouts", function(source, args)
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
    ExecuteCommand("dutycallouts")
end, false)


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
    
    if PlayerPaycheckTimers[serverId] then
        PlayerPaycheckTimers[serverId] = nil
    end
    PlayerPaycheckGen[serverId] = (PlayerPaycheckGen[serverId] or 0) + 1

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
            SendCdeDutyToCad(discordId, false, department, nil, timePlayed)
        end
    end

    PlayerCalloutSettings[serverId] = nil
    PlayerDepartments[serverId] = nil
    PlaytimeTracker[serverId] = nil
end)

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
    print("  /dutycallouts - Toggle 911 calls")
    print("^2Paycheck System:^0")
    print("  - Each player gets paid 30 mins after clocking in")
    print("  - Joe clocks in at 9:02 → gets paid at 9:32")
    print("  - You clock in at 9:05 → get paid at 9:35")
    print("  - Prevents server lag from bulk payouts")
    print("^2========================================^0")
end)

print("^2[CDE-DUTY] Server loaded successfully^0")
end
