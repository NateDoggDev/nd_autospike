lib.locale()

Framework = Framework or 'standalone'

GetPlayerIdentifier = GetPlayerIdentifier or function(source)
    return GetPlayerIdentifierByType(source, 'license') or ('src:%s'):format(source)
end

GetPlayerJob = GetPlayerJob or function()
    return nil
end

NotifyPlayer = NotifyPlayer or function(source, msg, type)
    TriggerClientEvent('ox_lib:notify', source, { description = msg, type = type })
end

Inventory = Inventory or {
    name = 'none',
    metadata = false,
    getSlot = function() return nil end,
    findSlot = function() return nil end,
    setMetadata = function() return false end,
    addItem = function() return true end,
    removeItem = function() return true end,
    hasItem = function() return true end,
}

local boxes = {}
local boxCount = 0
local cooldowns = {}
local placing = {}

local function debugPrint(...)
    if not Config.debug then return end
    print('[nd_autospike]', ...)
end

local function notify(source, key, type, ...)
    NotifyPlayer(source, locale(key, ...), type or 'inform')
end

local function isAuthorized(source)
    if Config.acePermission and not IsPlayerAceAllowed(source, Config.acePermission) then return false end
    if not next(Config.allowedJobs) then return true end
    local job = GetPlayerJob(source)
    if not job then return false end
    local minGrade = Config.allowedJobs[job.name]
    if minGrade == nil and job.type then minGrade = Config.allowedJobs[job.type] end
    return minGrade ~= nil and (job.grade or 0) >= minGrade
end

local function onCooldown(source)
    local now = GetGameTimer()
    if cooldowns[source] and now - cooldowns[source] < Config.toggleCooldown then return true end
    cooldowns[source] = now
    return false
end

local function newBoxId()
    local id
    repeat
        id = tostring(math.random(1000, 9999))
    until not boxes[id]
    return id
end

local function spawnBoxEntity(box)
    local entity = CreateObjectNoOffset(Config.box.model, box.coords.x, box.coords.y, box.coords.z, true, true, false)
    if not entity or entity == 0 then return false end
    if SetEntityRotation then SetEntityRotation(entity, box.rotation.x, box.rotation.y, box.rotation.z, 2, true) end
    if SetEntityOrphanMode then SetEntityOrphanMode(entity, 2) end
    box.entity = entity
    box.netId = NetworkGetNetworkIdFromEntity(entity)
    return true
end

local function setBoxState(box)
    if not box.entity or not DoesEntityExist(box.entity) then return end
    Entity(box.entity).state:set('nd_autospike', {
        id = box.id,
        owner = box.owner,
        rotation = box.rotation,
        deployed = box.deployed,
    }, true)
end

local function playerBoxCount(identifier)
    local count = 0
    for _, box in pairs(boxes) do
        if box.owner == identifier then count += 1 end
    end
    return count
end

local function boxByNetId(netId)
    for _, box in pairs(boxes) do
        if box.netId == netId then return box end
    end
end

local function nearestBox(coords, maxDistance, filter)
    local best, bestDistance
    for _, box in pairs(boxes) do
        if not filter or filter(box) then
            local distance = #(coords - box.coords)
            if distance <= maxDistance and (not bestDistance or distance < bestDistance) then
                best, bestDistance = box, distance
            end
        end
    end
    return best, bestDistance
end

local function stripTransforms(box)
    local rad = math.rad(box.heading)
    local forward = vec3(-math.sin(rad), math.cos(rad), 0.0)
    local front = box.coords + forward * Config.box.frontOffset
    local origin = front + forward * Config.strip.originOffset
    local list = {}
    for i = 1, Config.strip.count do
        list[i] = {
            origin = origin,
            coords = origin + forward * ((i - 1) * (Config.strip.length + Config.strip.gap)),
            heading = (box.heading + Config.strip.headingOffset) % 360,
        }
    end
    return list
end

local function deployTotal()
    local s = Config.strip
    if s.mode == 'roll' then
        return s.count * (s.deployTime + s.stagger)
    end
    return s.flipTime + (s.count > 1 and (s.slideTime + (s.count - 2) * s.stagger) or 0)
end

local function retractTotal(count)
    local s = Config.strip
    if s.mode == 'roll' then
        return count * (s.retractDuration + s.stagger)
    end
    return s.flipTime + (count > 1 and (s.slideTime + (count - 2) * s.stagger) or 0)
end

local function deleteStrips(strips)
    for i = 1, #strips do
        if DoesEntityExist(strips[i]) then
            DeleteEntity(strips[i])
        end
    end
end

local function setBusy(box, duration)
    box.busy = duration > 0
    box.busyUntil = GetGameTimer() + duration
end

local function isBusy(box)
    if not box.busy then return false end
    if box.busyUntil and GetGameTimer() >= box.busyUntil then
        box.busy = false
        return false
    end
    return true
end

local function deploy(box, instant)
    setBusy(box, instant and 0 or deployTotal())
    box.deployed = true
    deleteStrips(box.strips)
    box.strips = {}
    local now = instant and (GetGameTimer() - 600000) or GetGameTimer()
    for i, transform in ipairs(stripTransforms(box)) do
        local entity = CreateObjectNoOffset(Config.strip.model, transform.coords.x, transform.coords.y, transform.coords.z, true, true, false)
        if entity and entity ~= 0 then
            if SetEntityRotation then SetEntityRotation(entity, 0.0, 0.0, transform.heading, 2, true) end
            if SetEntityOrphanMode then SetEntityOrphanMode(entity, 2) end
            Entity(entity).state:set('nd_autospike_strip', {
                box = box.id,
                index = i,
                count = Config.strip.count,
                heading = transform.heading,
                origin = transform.origin,
                final = transform.coords,
                at = now,
                phase = 'deploy',
            }, true)
            box.strips[#box.strips + 1] = entity
        end
    end
    setBoxState(box)
    if not instant then
        SetTimeout(deployTotal(), function()
            if box.deployed then box.busy = false end
        end)
    end
    Storage.save(box)
    if Config.autoRetract > 0 then
        local token = now
        box.autoToken = token
        SetTimeout(Config.autoRetract * 1000, function()
            if boxes[box.id] and box.deployed and box.autoToken == token then
                Retract(box)
            end
        end)
    end
    debugPrint('deployed', box.id, #box.strips)
end

function Retract(box, instant)
    box.deployed = false
    box.autoToken = nil
    local strips = box.strips
    box.strips = {}
    local now = GetGameTimer()
    for i = 1, #strips do
        if DoesEntityExist(strips[i]) then
            local state = Entity(strips[i]).state.nd_autospike_strip or {}
            state.phase = 'retract'
            state.at = now
            Entity(strips[i]).state:set('nd_autospike_strip', state, true)
        end
    end
    if instant then
        deleteStrips(strips)
        box.busy = false
    else
        setBusy(box, retractTotal(#strips) + 400)
        SetTimeout(retractTotal(#strips) + 400, function()
            deleteStrips(strips)
            box.busy = false
        end)
    end
    if boxes[box.id] then
        setBoxState(box)
        Storage.save(box)
    end
    debugPrint('retracted', box.id)
end

local function clearFobMetadata(source, slot, metadata)
    if not Inventory.metadata or not slot then return end
    local newMeta = lib.table.deepclone(metadata or {})
    newMeta.spikebox = nil
    newMeta.label = nil
    newMeta.description = nil
    Inventory.setMetadata(source, slot, newMeta)
end

local function collectFobs(box)
    if not Inventory.findSlots then return end
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if Inventory.metadata then
            local slots = Inventory.findSlots(src, Config.items.fob)
            for i = 1, #slots do
                if slots[i].metadata.spikebox == box.id then
                    Inventory.removeItem(src, Config.items.fob, 1, slots[i].slot)
                end
            end
        elseif box.links[GetPlayerIdentifier(src)] and Inventory.hasItem(src, Config.items.fob) then
            Inventory.removeItem(src, Config.items.fob, 1)
        end
    end
end

local function removeBox(box)
    if not boxes[box.id] then return end
    boxes[box.id] = nil
    boxCount -= 1
    Retract(box, true)
    if box.entity and DoesEntityExist(box.entity) then
        DeleteEntity(box.entity)
    end
    collectFobs(box)
    Storage.delete(box.id)
end

local function useBox(source, slot)
    if onCooldown(source) then return end
    if not isAuthorized(source) then return notify(source, 'not_authorized', 'error') end
    if boxCount >= Config.maxBoxes then return notify(source, 'too_many_boxes', 'error') end
    if playerBoxCount(GetPlayerIdentifier(source)) >= Config.maxBoxesPerPlayer then
        return notify(source, 'too_many_own_boxes', 'error')
    end
    placing[source] = { slot = slot, at = GetGameTimer() }
    TriggerClientEvent('nd_autospike:client:place', source, slot)
end

local function useFob(source, slot, metadata)
    if onCooldown(source) then return end
    if not isAuthorized(source) then return notify(source, 'not_authorized', 'error') end

    local identifier = GetPlayerIdentifier(source)
    local pedCoords = GetEntityCoords(GetPlayerPed(source))

    if (not metadata or not next(metadata)) and slot then
        local item = Inventory.getSlot(source, slot)
        metadata = item and item.metadata or {}
    end
    metadata = metadata or {}

    local linkedId = metadata.spikebox
    if linkedId and not boxes[linkedId] then
        Inventory.removeItem(source, Config.items.fob, 1, slot)
        return notify(source, 'box_missing', 'error')
    end

    local near = not linkedId and nearestBox(pedCoords, Config.linkDistance) or nil

    if near then
        if Config.ownerOnlyLink and near.owner ~= identifier then
            return notify(source, 'not_owner', 'error')
        end
        if Inventory.metadata and slot then
            local newMeta = lib.table.deepclone(metadata)
            newMeta.spikebox = near.id
            newMeta.label = locale('fob_label', near.id)
            newMeta.description = locale('fob_description', near.id)
            Inventory.setMetadata(source, slot, newMeta)
        end
        near.links[identifier] = true
        Storage.save(near)
        TriggerClientEvent('nd_autospike:client:fob', source)
        return notify(source, 'fob_linked', 'success', near.id)
    end

    local box
    if linkedId then
        box = boxes[linkedId]
    else
        box = nearestBox(pedCoords, Config.fobRange, function(b) return b.links[identifier] end)
        if not box then
            return notify(source, Inventory.metadata and 'fob_not_linked' or 'fob_no_boxes', 'error')
        end
    end

    if #(pedCoords - box.coords) > Config.fobRange then return notify(source, 'fob_out_of_range', 'error') end
    if isBusy(box) then return notify(source, 'box_busy', 'error') end

    TriggerClientEvent('nd_autospike:client:fob', source)

    if box.deployed then
        Retract(box)
        notify(source, 'box_retracted', 'inform')
    else
        deploy(box)
        notify(source, 'box_deployed', 'success')
    end
end

lib.callback.register('nd_autospike:sync', function()
    return GetGameTimer()
end)

lib.callback.register('nd_autospike:place', function(source, slot, coords, rotation)
    local pending = placing[source]
    placing[source] = nil
    if not pending or GetGameTimer() - pending.at > 120000 then return false, 'cancelled' end
    if type(coords) ~= 'vector3' or type(rotation) ~= 'vector3' then return false, 'invalid_position' end
    if #(GetEntityCoords(GetPlayerPed(source)) - coords) > Config.placeDistance + 3.0 then return false, 'too_far' end
    if not isAuthorized(source) then return false, 'not_authorized' end
    if boxCount >= Config.maxBoxes then return false, 'too_many_boxes' end

    local identifier = GetPlayerIdentifier(source)
    if playerBoxCount(identifier) >= Config.maxBoxesPerPlayer then return false, 'too_many_own_boxes' end

    slot = pending.slot or slot
    if Inventory.name ~= 'none' then
        local item = slot and Inventory.getSlot(source, slot) or Inventory.findSlot(source, Config.items.box)
        if not item or item.name ~= Config.items.box then return false, 'no_item' end
        slot = item.slot
    end
    if not Inventory.removeItem(source, Config.items.box, 1, slot) then return false, 'no_item' end

    local box = {
        id = newBoxId(),
        owner = identifier,
        coords = coords,
        rotation = rotation,
        heading = rotation.z % 360,
        deployed = false,
        busy = false,
        strips = {},
        links = {},
        fobsIssued = 0,
    }
    if not spawnBoxEntity(box) then
        Inventory.addItem(source, Config.items.box, 1)
        return false, 'invalid_position'
    end
    boxes[box.id] = box
    boxCount += 1
    setBoxState(box)
    Storage.save(box)
    debugPrint('placed', box.id, box.netId, identifier)
    return box.id
end)

RegisterNetEvent('nd_autospike:server:cancelPlace', function()
    placing[source] = nil
end)

RegisterNetEvent('nd_autospike:server:grounded', function(netId, coords, rotation)
    if type(coords) ~= 'vector3' or type(rotation) ~= 'vector3' then return end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    local state = Entity(entity).state.nd_autospike_strip
    if not state or not state.final then return end
    if #(coords - state.final) > 2.0 or math.abs(rotation.x) > 30.0 then return end
    SetEntityCoords(entity, coords.x, coords.y, coords.z)
    if SetEntityRotation then SetEntityRotation(entity, rotation.x, rotation.y, rotation.z, 2, true) end
end)

lib.callback.register('nd_autospike:pickup', function(source, netId)
    local box = boxByNetId(netId)
    if not box then return false, 'box_missing' end
    if #(GetEntityCoords(GetPlayerPed(source)) - box.coords) > Config.pickupDistance + 2.0 then return false, 'too_far' end
    if not isAuthorized(source) then return false, 'not_authorized' end
    if Config.ownerOnlyPickup and box.owner ~= GetPlayerIdentifier(source) then return false, 'not_owner' end
    if isBusy(box) then return false, 'box_busy' end
    if not Inventory.addItem(source, Config.items.box, 1) then return false, 'inventory_full' end
    removeBox(box)
    return true
end)

lib.callback.register('nd_autospike:takeFob', function(source, netId)
    local box = boxByNetId(netId)
    if not box then return false, 'box_missing' end
    if #(GetEntityCoords(GetPlayerPed(source)) - box.coords) > Config.pickupDistance + 2.0 then return false, 'too_far' end
    if not isAuthorized(source) then return false, 'not_authorized' end
    local identifier = GetPlayerIdentifier(source)
    if Config.ownerOnlyLink and box.owner ~= identifier then return false, 'not_owner' end
    if Config.maxFobsPerBox > 0 and box.fobsIssued >= Config.maxFobsPerBox then return false, 'fob_limit' end
    if Inventory.metadata and Inventory.findSlots then
        for _, slotData in ipairs(Inventory.findSlots(source, Config.items.fob)) do
            if slotData.metadata.spikebox == box.id then return false, 'fob_already' end
        end
    elseif not Inventory.metadata and box.links[identifier] and Inventory.hasItem(source, Config.items.fob) then
        return false, 'fob_already'
    end
    local metadata
    if Inventory.metadata then
        metadata = {
            spikebox = box.id,
            label = locale('fob_label', box.id),
            description = locale('fob_description', box.id),
        }
    end
    if not Inventory.addItem(source, Config.items.fob, 1, metadata) then return false, 'inventory_full' end
    box.fobsIssued += 1
    box.links[identifier] = true
    Storage.save(box)
    return true, 'fob_taken'
end)

lib.callback.register('nd_autospike:toggle', function(source, netId)
    local box = boxByNetId(netId)
    if not box then return false, 'box_missing' end
    if onCooldown(source) then return false end
    if #(GetEntityCoords(GetPlayerPed(source)) - box.coords) > Config.pickupDistance + 2.0 then return false, 'too_far' end
    if not isAuthorized(source) then return false, 'not_authorized' end
    if Config.ownerOnlyLink and box.owner ~= GetPlayerIdentifier(source) then return false, 'not_owner' end
    if isBusy(box) then return false, 'box_busy' end
    if box.deployed then
        Retract(box)
        return true, 'box_retracted'
    end
    deploy(box)
    return true, 'box_deployed'
end)

exports('useSpikeBox', useBox)
exports('useSpikeFob', useFob)

local function registerItems()
    if Inventory.registerUsable then
        Inventory.registerUsable(Config.items.box, useBox)
        Inventory.registerUsable(Config.items.fob, useFob)
    end
    if RegisterUsableItem then
        RegisterUsableItem(Config.items.box, useBox)
        RegisterUsableItem(Config.items.fob, useFob)
    end
end

registerItems()

if Config.clearCommand then
    lib.addCommand(Config.clearCommand, {
        help = 'Remove every placed spike box',
        restricted = 'group.admin',
    }, function(source)
        local removed = 0
        for _, box in pairs(boxes) do
            removeBox(box)
            removed += 1
        end
        Storage.clear()
        if source > 0 then notify(source, 'cleared', 'inform', removed) end
    end)
end

local function restore()
    if not Storage.init() then return end
    local saved = Storage.load()
    for i = 1, #saved do
        local row = saved[i]
        local box = {
            id = row.id,
            owner = row.owner,
            coords = row.coords,
            rotation = row.rotation,
            heading = row.rotation.z % 360,
            deployed = false,
            busy = false,
            strips = {},
            links = row.links or {},
            fobsIssued = row.fobsIssued or 0,
        }
        if spawnBoxEntity(box) then
            boxes[box.id] = box
            boxCount += 1
            setBoxState(box)
            if row.deployed and Config.restoreDeployed then
                deploy(box, true)
            elseif row.deployed then
                Storage.save(box)
            end
        else
            print(('[nd_autospike] failed to restore box %s, is the model streamed?'):format(box.id))
        end
    end
    if #saved > 0 then print(('[nd_autospike] restored %d spike box(es)'):format(#saved)) end
end

CreateThread(function()
    Wait(1000)
    restore()
    while true do
        Wait(10000)
        for _, box in pairs(boxes) do
            if not box.entity or not DoesEntityExist(box.entity) then
                debugPrint('box entity vanished, respawning', box.id)
                if spawnBoxEntity(box) then
                    setBoxState(box)
                end
            end
            if box.deployed and not isBusy(box) then
                local missing = #box.strips < Config.strip.count
                for i = 1, #box.strips do
                    if not DoesEntityExist(box.strips[i]) then missing = true end
                end
                if missing then
                    debugPrint('strips vanished, redeploying', box.id)
                    deploy(box, true)
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    placing[source] = nil
    cooldowns[source] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, box in pairs(boxes) do
        deleteStrips(box.strips)
        if box.entity and DoesEntityExist(box.entity) then DeleteEntity(box.entity) end
    end
end)
