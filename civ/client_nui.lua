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

-- Handle escape key
RegisterNUICallback('escape', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

-- =============================================================================
-- BANK NUI CALLBACKS
-- =============================================================================

-- Close bank panel
RegisterNUICallback('closeBank', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

-- Deposit
RegisterNUICallback('bankDeposit', function(data, cb)
    local result = lib.callback.await('cdecad-civmanager:bankDeposit', false,
        data.civilianId, tonumber(data.amount), data.description)
    cb(result)
end)

-- Withdraw
RegisterNUICallback('bankWithdraw', function(data, cb)
    local result = lib.callback.await('cdecad-civmanager:bankWithdraw', false,
        data.civilianId, tonumber(data.amount), data.description)
    cb(result)
end)

-- Transfer
RegisterNUICallback('bankTransfer', function(data, cb)
    local result = lib.callback.await('cdecad-civmanager:bankTransfer', false,
        data.fromCivilianId, data.toAccountNumber, tonumber(data.amount), data.description)
    cb(result)
end)

-- =============================================================================
-- ADMIN BANK (BANK EMPLOYEE) NUI CALLBACKS
-- =============================================================================

-- Load a single account's full detail for the banker view
RegisterNUICallback('bankerLoadAccount', function(data, cb)
    local result = lib.callback.await('cdecad-civmanager:bankerLoadAccount', false, data.accountId)
    cb(result)
end)

-- Approve / deny a pending loan
RegisterNUICallback('bankerLoanDecision', function(data, cb)
    local result = lib.callback.await('cdecad-civmanager:bankerLoanDecision', false,
        data.accountId, data.loanId, data.decision, data.reason)
    cb(result)
end)

-- Freeze / unfreeze / close an account
RegisterNUICallback('bankerSetStatus', function(data, cb)
    local result = lib.callback.await('cdecad-civmanager:bankerSetStatus', false,
        data.accountId, data.status)
    cb(result)
end)

-- Teller adjust — deposit/withdraw/transfer on behalf of a customer
RegisterNUICallback('bankerAdjust', function(data, cb)
    local result = lib.callback.await('cdecad-civmanager:bankerAdjust', false,
        data.accountId, data.action, tonumber(data.amount), data.description, data.recipientAccountNumber)
    cb(result)
end)

end
