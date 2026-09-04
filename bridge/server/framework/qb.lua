if GetResourceState('qb-core') ~= 'started' or GetResourceState('qbx_core') == 'started' then return end

Framework = 'qb'

local QBCore = exports['qb-core']:GetCoreObject()

function GetPlayerIdentifier(source)
    local player = QBCore.Functions.GetPlayer(source)
    return player and player.PlayerData.citizenid
end

function GetPlayerJob(source)
    local player = QBCore.Functions.GetPlayer(source)
    if not player or not player.PlayerData.job then return end
    return { name = player.PlayerData.job.name, grade = player.PlayerData.job.grade.level, type = player.PlayerData.job.type }
end

function NotifyPlayer(source, msg, type)
    TriggerClientEvent('QBCore:Notify', source, msg, type)
end

function RegisterUsableItem(name, cb)
    QBCore.Functions.CreateUseableItem(name, function(source, item)
        cb(source, item and item.slot, item and (item.metadata or item.info))
    end)
end
