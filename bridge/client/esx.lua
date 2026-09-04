if GetResourceState('es_extended') ~= 'started' then return end

function Notify(msg, type)
    lib.notify({ description = msg, type = type })
end
