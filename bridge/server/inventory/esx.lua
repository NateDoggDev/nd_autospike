if GetResourceState('ox_inventory') == 'started' then return end
if GetResourceState('es_extended') ~= 'started' then return end

local ESX = exports['es_extended']:getSharedObject()

Inventory = {
    name = 'esx',
    metadata = false,
}

function Inventory.getSlot()
    return nil
end

function Inventory.findSlot(source, name)
    local player = ESX.GetPlayerFromId(source)
    if not player then return end
    local item = player.getInventoryItem(name)
    if not item or (item.count or 0) <= 0 then return end
    return { name = name, slot = nil, metadata = {} }
end

function Inventory.setMetadata()
    return false
end

function Inventory.addItem(source, name, count)
    local player = ESX.GetPlayerFromId(source)
    if not player then return false end
    if player.canCarryItem and not player.canCarryItem(name, count) then return false end
    player.addInventoryItem(name, count)
    return true
end

function Inventory.removeItem(source, name, count)
    local player = ESX.GetPlayerFromId(source)
    if not player then return false end
    local item = player.getInventoryItem(name)
    if not item or (item.count or 0) < count then return false end
    player.removeInventoryItem(name, count)
    return true
end

function Inventory.hasItem(source, name)
    local player = ESX.GetPlayerFromId(source)
    if not player then return false end
    local item = player.getInventoryItem(name)
    return item ~= nil and (item.count or 0) > 0
end
