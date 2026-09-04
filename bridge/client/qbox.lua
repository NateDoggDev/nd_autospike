if GetResourceState('qbx_core') ~= 'started' then return end

function Notify(msg, type)
    exports.qbx_core:Notify(msg, type)
end
