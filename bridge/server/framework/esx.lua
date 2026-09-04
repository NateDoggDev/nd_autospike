if GetResourceState('es_extended') ~= 'started' then return end

Framework = 'esx'

local ESX = exports['es_extended']:getSharedObject()

function GetPlayerIdentifier(source)
    local player = ESX.GetPlayerFromId(source)
    return player and player.identifier
end

function GetPlayerJob(source)
    local player = ESX.GetPlayerFromId(source)
    if not player or not player.job then return end
    return { name = player.job.name, grade = player.job.grade, type = player.job.type }
end

function NotifyPlayer(source, msg, type)
    TriggerClientEvent('ox_lib:notify', source, { description = msg, type = type })
end

function RegisterUsableItem(name, cb)
    ESX.RegisterUsableItem(name, function(source, _, data)
        local isTable = type(data) == 'table'
        cb(source, isTable and data.slot or nil, isTable and data.metadata or nil)
    end)
end
