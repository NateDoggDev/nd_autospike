if GetResourceState('ox_inventory') == 'started' then return end
if GetResourceState('qb-core') ~= 'started' then return end

local QBCore = exports['qb-core']:GetCoreObject()
local qbInv = GetResourceState('qb-inventory') == 'started' and exports['qb-inventory'] or nil

local function hasExport(name)
    if not qbInv then return false end
    return pcall(function() return qbInv[name] end)
end

local modern = hasExport('SetItemData') and hasExport('GetItemBySlot')

Inventory = {
    name = modern and 'qb-inventory' or 'qb-core',
    metadata = true,
}

function Inventory.getSlot(source, slot)
    if not slot then return end
    local data
    if modern then
        data = qbInv:GetItemBySlot(source, slot)
    else
        local player = QBCore.Functions.GetPlayer(source)
        data = player and player.Functions.GetItemBySlot(slot)
    end
    if not data then return end
    return { name = data.name, slot = data.slot, metadata = data.info or {} }
end

function Inventory.findSlot(source, name, metadata)
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return end
    for _, item in pairs(player.PlayerData.items or {}) do
        if item and item.name == name then
            local info = item.info or {}
            local match = true
            if metadata then
                for k, v in pairs(metadata) do
                    if info[k] ~= v then
                        match = false
                        break
                    end
                end
            end
            if match then
                return { name = item.name, slot = item.slot, metadata = info }
            end
        end
    end
end

function Inventory.findSlots(source, name)
    local list = {}
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return list end
    for _, item in pairs(player.PlayerData.items or {}) do
        if item and item.name == name then
            list[#list + 1] = { name = item.name, slot = item.slot, metadata = item.info or {} }
        end
    end
    return list
end

function Inventory.setMetadata(source, slot, metadata)
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return false end
    local item = player.Functions.GetItemBySlot(slot)
    if not item then return false end
    if modern then
        for k in pairs(item.info or {}) do
            if metadata[k] == nil then
                qbInv:SetItemData(source, item.name, k, nil, slot)
            end
        end
        for k, v in pairs(metadata) do
            qbInv:SetItemData(source, item.name, k, v, slot)
        end
        return true
    end
    local items = player.PlayerData.items
    items[slot].info = metadata
    player.Functions.SetInventory(items, true)
    return true
end

function Inventory.addItem(source, name, count, metadata)
    if modern then
        if not qbInv:CanAddItem(source, name, count) then return false end
        return qbInv:AddItem(source, name, count, false, metadata or {}, 'nd_autospike') and true or false
    end
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return false end
    return player.Functions.AddItem(name, count, false, metadata or {}) and true or false
end

function Inventory.removeItem(source, name, count, slot)
    if modern then
        return qbInv:RemoveItem(source, name, count, slot, 'nd_autospike') and true or false
    end
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return false end
    return player.Functions.RemoveItem(name, count, slot) and true or false
end

function Inventory.hasItem(source, name)
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return false end
    local item = player.Functions.GetItemByName(name)
    return item ~= nil and (item.amount or 0) > 0
end
