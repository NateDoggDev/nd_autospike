if GetResourceState('qbx_core') ~= 'started' then return end

Framework = 'qbox'

function GetPlayerIdentifier(source)
    local player = exports.qbx_core:GetPlayer(source)
    return player and player.PlayerData.citizenid
end

function GetPlayerJob(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player or not player.PlayerData.job then return end
    return { name = player.PlayerData.job.name, grade = player.PlayerData.job.grade.level, type = player.PlayerData.job.type }
end

function NotifyPlayer(source, msg, type)
    exports.qbx_core:Notify(source, msg, type)
end

function RegisterUsableItem(name, cb)
    exports.qbx_core:CreateUseableItem(name, function(source, item)
        cb(source, item and item.slot, item and item.metadata)
    end)
end
