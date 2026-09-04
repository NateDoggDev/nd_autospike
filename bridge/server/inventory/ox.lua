if GetResourceState('ox_inventory') ~= 'started' then return end

local ox = exports.ox_inventory

Inventory = {
    name = 'ox_inventory',
    metadata = true,
}

function Inventory.getSlot(source, slot)
    if not slot then return end
    local data = ox:GetSlot(source, slot)
    if not data then return end
    return { name = data.name, slot = data.slot, metadata = data.metadata or {} }
end

function Inventory.findSlot(source, name, metadata)
    local data = ox:GetSlotWithItem(source, name, metadata)
    if not data then return end
    return { name = data.name, slot = data.slot, metadata = data.metadata or {} }
end

function Inventory.findSlots(source, name)
    local list = {}
    local slots = ox:GetSlotsWithItem(source, name) or {}
    for i = 1, #slots do
        list[#list + 1] = { name = slots[i].name, slot = slots[i].slot, metadata = slots[i].metadata or {} }
    end
    return list
end

function Inventory.setMetadata(source, slot, metadata)
    ox:SetMetadata(source, slot, metadata)
    return true
end

function Inventory.addItem(source, name, count, metadata)
    if not ox:CanCarryItem(source, name, count) then return false end
    return ox:AddItem(source, name, count, metadata) and true or false
end

function Inventory.removeItem(source, name, count, slot)
    return ox:RemoveItem(source, name, count, nil, slot) and true or false
end

function Inventory.hasItem(source, name)
    return (ox:GetItemCount(source, name) or 0) > 0
end

local usedItems = {}

function Inventory.registerUsable(name, cb)
    usedItems[name] = cb
end

AddEventHandler('ox_inventory:usedItem', function(source, name, slot, metadata)
    local cb = usedItems[name]
    if cb then cb(source, slot, metadata) end
end)

exports('useItem', function(event)
    if event == 'usingItem' then return end
end)
