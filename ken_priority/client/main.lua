local ESX = exports['es_extended']:getSharedObject()

local isNuiVisible = false

local function IsAllowedJob()
    local playerData = ESX.GetPlayerData()
    if not playerData or not playerData.job then return false end
    local jobName = playerData.job.name

    for group, jobs in pairs(Config.AllowedJobs) do
        if type(jobs) == 'table' then
            for _, j in ipairs(jobs) do
                if j == jobName then return true end
            end
        elseif jobs == jobName then
            return true
        end
    end
    return false
end

local function ShowNUI(show)
    isNuiVisible = show
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'toggleUI',
        show   = show
    })
end

RegisterCommand('safe', function()
    if not IsAllowedJob() then
        ESX.ShowNotification('~r~Hindi ka awtorisado gamitin ang command na ito.')
        return
    end
    TriggerServerEvent('priority_cooldown:setStatus', 'safe')
end, false)

RegisterCommand('hold', function()
    if not IsAllowedJob() then
        ESX.ShowNotification('~r~Hindi ka awtorisado gamitin ang command na ito.')
        return
    end
    TriggerServerEvent('priority_cooldown:setStatus', 'hold')
end, false)

RegisterCommand('progress', function()
    if not IsAllowedJob() then
        ESX.ShowNotification('~r~Hindi ka awtorisado gamitin ang command na ito.')
        return
    end
    TriggerServerEvent('priority_cooldown:setStatus', 'progress')
end, false)

RegisterCommand('priority', function()
    ShowNUI(not isNuiVisible)
end, false)

-- ✅ Updated: now receives priorityStates (both police & sheriff)
RegisterNetEvent('priority_cooldown:updateState')
AddEventHandler('priority_cooldown:updateState', function(states)
    SendNUIMessage({
        action = 'updateState',
        states = states  -- { police = {...}, sheriff = {...} }
    })
end)

RegisterNetEvent('priority_cooldown:notify')
AddEventHandler('priority_cooldown:notify', function(msg, msgType)
    ESX.ShowNotification(msg)
end)

RegisterNUICallback('close', function(data, cb)
    ShowNUI(false)
    cb({})
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if IsControlJustReleased(0, 166) then
            ShowNUI(not isNuiVisible)
        end
    end
end)


 
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        Citizen.Wait(2000) -- hintayin maging connected properly
        TriggerServerEvent('priority_cooldown:requestState') 
        Citizen.Wait(500)
        ShowNUI(true)
    end
end)

AddEventHandler('playerSpawned', function()
    Citizen.Wait(1000)
    TriggerServerEvent('priority_cooldown:requestState')
end)



-- TEMP: para malaman kung ano job mo, i-type sa chat /myjob
RegisterCommand('myjob', function()
    local playerData = ESX.GetPlayerData()
    if playerData and playerData.job then
        ESX.ShowNotification('Job: ~b~' .. playerData.job.name)
    end
end, false)



-- ============================================================
-- PRIORITY AUTO-HOLD INTEGRATION
-- ============================================================
local function triggerPriorityHold(department, trapName)
    if GetResourceState('ken_priority') ~= 'started' then
        print('[esx_traphouse] ken_priority resource not found, skipping auto-hold.')
        return false
    end

    local success = exports['ken_priority']:triggerAutoHold(
        department,
        'Traphouse Robbery: ' .. trapName
    )

    if success then
        TriggerClientEvent('esx_traphouse:notifyPriorityHold', -1, department, trapName)
        print('[esx_traphouse] Auto-hold triggered for: ' .. department)
    else
        print('[esx_traphouse] Auto-hold not triggered (existing priority active)')
    end

    return success
end

local function triggerPrioritySafe(department, trapName)
    if GetResourceState('ken_priority') ~= 'started' then
        print('[esx_traphouse] ken_priority resource not found, skipping auto-safe.')
        return false
    end

    local success = exports['ken_priority']:triggerAutoSafe(
        department,
        'Traphouse Robbery ended: ' .. trapName
    )

    if success then
        TriggerClientEvent('esx_traphouse:notifyPrioritySafe', -1, department, trapName)
        print('[esx_traphouse] Auto-safe triggered for: ' .. department)
    end

    return success
end


