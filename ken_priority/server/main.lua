local ESX = exports['es_extended']:getSharedObject()

-- ============================================================
-- STATE
-- ============================================================
local priorityStates = {
    police = {
        status     = 'safe',
        cooldown   = 0,
        startedBy  = nil,
        startedJob = nil,
    },
    sheriff = {
        status     = 'safe',
        cooldown   = 0,
        startedBy  = nil,
        startedJob = nil,
    }
}

local cooldownTimers = {
    police  = nil,
    sheriff = nil,
}

-- ============================================================
-- HELPER: get job group
-- ============================================================
local function GetJobGroup(jobName)
    if jobName == 'police' then return 'police'
    elseif jobName == 'sheriff' then return 'sheriff'
    end
    return nil
end

-- ============================================================
-- HELPER: broadcast state
-- ============================================================
local function BroadcastState()
    TriggerClientEvent('priority_cooldown:updateState', -1, priorityStates)
end

-- ============================================================
-- MYSQL: Save state to DB
-- ============================================================
local function SaveStateToDB(group)
    local state = priorityStates[group]
    if not state then
        print('[ken_priority] SaveStateToDB: state is nil for group: ' .. tostring(group))
        return
    end

    print('[ken_priority] Saving to DB: group=' .. group .. ' status=' .. state.status .. ' cooldown=' .. tostring(state.cooldown))

    exports.oxmysql:execute(
        'UPDATE `priority_state` SET `status` = ?, `started_by` = ?, `started_job` = ?, `cooldown` = ? WHERE `group` = ?',
        { state.status, state.startedBy, state.startedJob, state.cooldown, group },
        function(affectedRows)
            print('[ken_priority] DB saved: affectedRows=' .. tostring(affectedRows) .. ' group=' .. group)
        end
    )
end

-- ============================================================
-- HELPER: cooldown tick per group
-- ============================================================
local function StartCooldownTick(group, seconds)
    cooldownTimers[group] = nil
    priorityStates[group].cooldown = seconds

    Citizen.CreateThread(function()
        local token = {}
        cooldownTimers[group] = token

        while priorityStates[group].cooldown > 0 and cooldownTimers[group] == token do
            Citizen.Wait(1000)
            if cooldownTimers[group] ~= token then break end
            priorityStates[group].cooldown = priorityStates[group].cooldown - 1

            if priorityStates[group].cooldown % 10 == 0 then
                SaveStateToDB(group)
            end

            BroadcastState()
        end

        if cooldownTimers[group] == token
        and priorityStates[group].cooldown <= 0
        and priorityStates[group].status == 'progress' then
            cooldownTimers[group] = nil
            SaveStateToDB(group)
            BroadcastState()

            local groupLabel = group:upper()
            TriggerClientEvent('priority_cooldown:notify', -1,
                string.format(
                    '~y~[%s PRIORITY] Cooldown tapos na. ~w~Mag-type ng ~g~/safe ~w~para i-clear ang priority.',
                    groupLabel
                ), 'info')

            print('[ken_priority] Progress cooldown done for: ' .. group .. ' — waiting for manual /safe')
        end
    end)
end

-- ============================================================
-- MYSQL: Load state from DB on resource start
-- ============================================================
local function LoadStateFromDB()
    exports.oxmysql:fetch('SELECT * FROM `priority_state`', {}, function(results)
        if not results or #results == 0 then
            print('[ken_priority] Warning: No results from priority_state table.')
            return
        end

        for _, row in ipairs(results) do
            local group = row['group']
            if priorityStates[group] then
                priorityStates[group].status     = row.status or 'safe'
                priorityStates[group].startedBy  = row.started_by
                priorityStates[group].startedJob = row.started_job
                priorityStates[group].cooldown   = row.cooldown or 0

                print('[ken_priority] Loaded: group=' .. group .. ' status=' .. priorityStates[group].status .. ' cooldown=' .. priorityStates[group].cooldown)

                if priorityStates[group].cooldown > 0 and priorityStates[group].status == 'progress' then
                    print('[ken_priority] Resuming cooldown for: ' .. group .. ' (' .. priorityStates[group].cooldown .. 's left)')
                    StartCooldownTick(group, priorityStates[group].cooldown)
                end
            end
        end

        BroadcastState()
        print('[ken_priority] State loaded from database.')
    end)
end

-- ============================================================
-- EVENT: Manual command (safe / hold / progress)
-- ============================================================
RegisterNetEvent('priority_cooldown:setStatus')
AddEventHandler('priority_cooldown:setStatus', function(cmd)
    local src    = source
    local player = ESX.GetPlayerFromId(src)
    if not player then return end

    local jobName = player.getJob().name
    local group   = GetJobGroup(jobName)

    if not group then
        TriggerClientEvent('priority_cooldown:notify', src,
            '~r~Ikaw ay hindi awtorisado na gamitin ang priority commands.', 'error')
        return
    end

    if cmd ~= 'safe' and cmd ~= 'hold' and cmd ~= 'progress' then return end

    local playerName = GetPlayerName(src)

    cooldownTimers[group] = nil

    priorityStates[group].status     = cmd
    priorityStates[group].startedBy  = playerName
    priorityStates[group].startedJob = jobName
    priorityStates[group].cooldown   = Config.Cooldowns[cmd] or 0

    SaveStateToDB(group)
    BroadcastState()

    local groupLabel = group:upper()
    local messages = {
        safe = string.format(
            '~g~[%s PRIORITY] %s ay nag-set ng status sa: SAFE.',
            groupLabel, playerName),
        hold = string.format(
            '~y~[%s PRIORITY] %s ay nag-set ng status sa: ON HOLD.',
            groupLabel, playerName),
        progress = string.format(
            '~r~[%s PRIORITY] %s ay nag-set ng status sa: IN PROGRESS. Cooldown: %ds',
            groupLabel, playerName, Config.Cooldowns.progress or 0),
    }

    TriggerClientEvent('priority_cooldown:notify', -1, messages[cmd], cmd)

    if (Config.Cooldowns[cmd] or 0) > 0 then
        StartCooldownTick(group, Config.Cooldowns[cmd])
    end

    print('[ken_priority] Manual ' .. cmd .. ' set by ' .. playerName .. ' for: ' .. group)
end)

-- ============================================================
-- EVENT: Player joined — sync state
-- ============================================================
AddEventHandler('playerSpawned', function()
    local src = source
    Citizen.Wait(2000)
    TriggerClientEvent('priority_cooldown:updateState', src, priorityStates)
end)

RegisterNetEvent('priority_cooldown:requestState')
AddEventHandler('priority_cooldown:requestState', function()
    local src = source
    TriggerClientEvent('priority_cooldown:updateState', src, priorityStates)
end)

-- ============================================================
-- EXPORT: isRobberyAllowed
-- ============================================================
exports('isRobberyAllowed', function(group)
    if group ~= 'police' and group ~= 'sheriff' then
        return false, 'Invalid department'
    end

    local status = priorityStates[group].status

    if status == 'hold' then
        return false, 'May ON HOLD na priority sa ' .. group .. '. Hintaying mag /safe ang cops.'
    elseif status == 'progress' then
        return false, 'May IN PROGRESS na priority sa ' .. group .. '. Hintaying mag /safe ang cops.'
    end

    return true, 'Pwede mag-rob'
end)

-- ============================================================
-- EXPORT: triggerAutoHold
-- ============================================================
exports('triggerAutoHold', function(group, reason)
    if group ~= 'police' and group ~= 'sheriff' then
        print('[ken_priority] Invalid group: ' .. tostring(group))
        return false
    end

    local status = priorityStates[group].status

    if status == 'progress' or status == 'hold' then
        print('[ken_priority] ' .. group .. ' may active ' .. status .. ', hindi na-override ng auto-hold.')
        return false
    end

    cooldownTimers[group] = nil

    priorityStates[group].status     = 'hold'
    priorityStates[group].startedBy  = 'AUTO (Robbery System)'
    priorityStates[group].startedJob = group
    priorityStates[group].cooldown   = Config.Cooldowns['hold'] or 0

    SaveStateToDB(group)
    BroadcastState()

    local groupLabel = group:upper()
    TriggerClientEvent('priority_cooldown:notify', -1,
        string.format('~y~[%s PRIORITY] AUTO-HOLD! Robbery started: ~w~%s',
            groupLabel, reason or 'Robbery'),
        'hold')

    if (Config.Cooldowns['hold'] or 0) > 0 then
        StartCooldownTick(group, Config.Cooldowns['hold'])
    end

    print('[ken_priority] Auto-hold triggered: ' .. group .. ' | ' .. tostring(reason))
    return true
end)

-- ============================================================
-- EXPORT: triggerAutoProgress
-- ============================================================
exports('triggerAutoProgress', function(group, reason)
    if group ~= 'police' and group ~= 'sheriff' then
        print('[ken_priority] Invalid group: ' .. tostring(group))
        return false
    end

    local status = priorityStates[group].status

    if status == 'progress' then
        print('[ken_priority] ' .. group .. ' may active progress na, hindi na-override.')
        return false
    end

    cooldownTimers[group] = nil

    priorityStates[group].status     = 'progress'
    priorityStates[group].startedBy  = 'AUTO (Robbery System)'
    priorityStates[group].startedJob = group
    priorityStates[group].cooldown   = Config.Cooldowns['progress'] or 0

    SaveStateToDB(group)
    BroadcastState()

    local groupLabel = group:upper()
    TriggerClientEvent('priority_cooldown:notify', -1,
        string.format(
            '~r~[%s PRIORITY] AUTO-PROGRESS! Robbery: ~w~%s ~r~| ~w~Mag-type ng ~g~/safe ~w~para i-clear.',
            groupLabel, reason or 'Robbery'
        ), 'progress')

    if (Config.Cooldowns['progress'] or 0) > 0 then
        StartCooldownTick(group, Config.Cooldowns['progress'])
    end

    print('[ken_priority] Auto-progress triggered: ' .. group .. ' | ' .. tostring(reason))
    return true
end)

-- ============================================================
-- EXPORT: triggerAutoSafe
-- ============================================================
exports('triggerAutoSafe', function(group, reason)
    if group ~= 'police' and group ~= 'sheriff' then
        print('[ken_priority] Invalid group: ' .. tostring(group))
        return false
    end

    if priorityStates[group].status == 'progress'
    and priorityStates[group].cooldown > 0 then
        print('[ken_priority] May progress cooldown pa (' ..
              priorityStates[group].cooldown .. 's) para sa: ' .. group ..
              ' — kailangan manuwal na mag /safe')
        return false
    end

    cooldownTimers[group] = nil

    priorityStates[group].status     = 'safe'
    priorityStates[group].startedBy  = nil
    priorityStates[group].startedJob = nil
    priorityStates[group].cooldown   = 0

    SaveStateToDB(group)
    BroadcastState()

    local groupLabel = group:upper()
    TriggerClientEvent('priority_cooldown:notify', -1,
        string.format('~g~[%s PRIORITY] AUTO-SAFE. Robbery ended: ~w~%s',
            groupLabel, reason or 'Robbery'),
        'safe')

    print('[ken_priority] Auto-safe triggered: ' .. group .. ' | ' .. tostring(reason))
    return true
end)

-- ============================================================
-- LOAD STATE ON START
-- ============================================================
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        while GetResourceState('oxmysql') ~= 'started' do
            Citizen.Wait(500)
        end
        Citizen.Wait(2000)
        LoadStateFromDB()
    end
end)

print('^2========================================^7')
print('^2[Priority]^7 Script loaded successfully!')
print('^2[Priority]^7 Version: 1.0.0')
print('^2[Priority]^7 Author: Ken Mondragon')
print('^2========================================^7')