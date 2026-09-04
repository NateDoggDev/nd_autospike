lib.locale()

Notify = Notify or function(msg, type)
    lib.notify({ description = msg, type = type })
end

local placing = false
local useTarget = Config.useTarget
if useTarget == 'auto' then
    useTarget = GetResourceState('ox_target') == 'started' and 'ox_target'
        or GetResourceState('qb-target') == 'started' and 'qb-target'
        or false
end

local function progress(anim, label)
    return lib.progressBar({
        duration = anim.duration,
        label = label,
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true, mouse = false },
        anim = { dict = anim.dict, clip = anim.clip, flag = anim.flag or 49 },
    })
end

local function placeBox(slot)
    if placing then return end
    if cache.vehicle then return Notify(locale('in_vehicle'), 'error') end

    placing = true
    local model = Config.box.model
    lib.requestModel(model)
    local pedCoords = GetEntityCoords(cache.ped)
    local ghost = CreateObjectNoOffset(model, pedCoords.x, pedCoords.y, pedCoords.z, false, false, false)
    SetModelAsNoLongerNeeded(model)
    SetEntityAlpha(ghost, 160, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)

    local heading = GetEntityHeading(cache.ped)
    local confirmed = false
    lib.showTextUI(locale('place_help'), { position = 'right-center' })

    while placing do
        Wait(0)
        DisableControlAction(0, 14, true)
        DisableControlAction(0, 15, true)
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 140, true)
        DisableControlAction(0, 141, true)
        DisableControlAction(0, 142, true)

        local hit, _, endCoords = lib.raycast.fromCamera(17, 4, Config.placeDistance + 4.0)
        pedCoords = GetEntityCoords(cache.ped)
        local target = hit and endCoords or GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 2.0, 0.0)
        local flat = vec3(target.x - pedCoords.x, target.y - pedCoords.y, 0.0)
        if #flat > Config.placeDistance then
            target = pedCoords + flat / #flat * Config.placeDistance
            local found, groundZ = GetGroundZFor_3dCoord(target.x, target.y, target.z + 2.0, false)
            if found then target = vec3(target.x, target.y, groundZ) end
        end

        if IsControlPressed(0, 174) then heading += 1.5 end
        if IsControlPressed(0, 175) then heading -= 1.5 end
        if IsDisabledControlJustPressed(0, 14) then heading -= 10.0 end
        if IsDisabledControlJustPressed(0, 15) then heading += 10.0 end
        heading = heading % 360

        SetEntityCoordsNoOffset(ghost, target.x, target.y, target.z, false, false, false)
        SetEntityHeading(ghost, heading)

        if IsControlJustReleased(0, 38) then
            confirmed = true
            placing = false
        elseif IsControlJustReleased(0, 177) or IsControlJustReleased(0, 194) then
            placing = false
        end
    end

    lib.hideTextUI()
    PlaceObjectOnGroundProperly(ghost)
    local coords = GetEntityCoords(ghost)
    local rotation = GetEntityRotation(ghost, 2)
    DeleteEntity(ghost)

    if not confirmed then
        TriggerServerEvent('nd_autospike:server:cancelPlace')
        return Notify(locale('cancelled'), 'error')
    end

    if not progress(Config.box.placeAnim, locale('placing')) then
        TriggerServerEvent('nd_autospike:server:cancelPlace')
        return Notify(locale('cancelled'), 'error')
    end

    local id, err = lib.callback.await('nd_autospike:place', false, slot, coords, rotation)
    if not id then return Notify(locale(err or 'cancelled'), 'error') end
    Notify(locale('box_placed', id), 'success')
end

RegisterNetEvent('nd_autospike:client:place', function(slot)
    placeBox(slot)
end)

local function pickupBox(entity)
    if cache.vehicle or placing then return end
    local box = BoxByEntity[entity]
    if not box or box.deployed then return end
    if not progress(Config.box.pickupAnim, locale('picking_up')) then
        return Notify(locale('cancelled'), 'error')
    end
    local ok, err = lib.callback.await('nd_autospike:pickup', false, box.netId)
    if not ok then return Notify(locale(err or 'cancelled'), 'error') end
    Notify(locale('box_picked_up'), 'success')
end

local function takeFob(entity)
    if cache.vehicle or placing then return end
    local box = BoxByEntity[entity]
    if not box then return end
    local ok, key = lib.callback.await('nd_autospike:takeFob', false, box.netId)
    Notify(locale(key or 'cancelled'), ok and 'success' or 'error')
end

local function toggleBox(entity)
    local box = BoxByEntity[entity]
    if not box then return end
    local ok, key = lib.callback.await('nd_autospike:toggle', false, box.netId)
    if key then Notify(locale(key), ok and 'success' or 'error') end
end

local function playFob()
    local fob = Config.fob
    local ped = cache.ped
    lib.requestAnimDict(fob.anim.dict)
    local prop
    if fob.prop then
        lib.requestModel(fob.prop.model)
        local coords = GetEntityCoords(ped)
        prop = CreateObject(fob.prop.model, coords.x, coords.y, coords.z, false, false, false)
        SetModelAsNoLongerNeeded(fob.prop.model)
        local o, r = fob.prop.offset, fob.prop.rotation
        AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, fob.prop.bone), o.x, o.y, o.z, r.x, r.y, r.z, true, true, false, true, 1, true)
    end
    TaskPlayAnim(ped, fob.anim.dict, fob.anim.clip, 8.0, -8.0, fob.anim.duration, fob.anim.flag, 0.0, false, false, false)
    if fob.sound then
        PlaySoundFrontend(-1, fob.sound.name, fob.sound.set, true)
    end
    Wait(fob.anim.duration)
    StopAnimTask(ped, fob.anim.dict, fob.anim.clip, 1.0)
    RemoveAnimDict(fob.anim.dict)
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
end

RegisterNetEvent('nd_autospike:client:fob', function()
    CreateThread(playFob)
end)

if Config.debug then
    local tuneProp
    RegisterCommand('spikefobtune', function(_, args)
        local fob = Config.fob
        if args[1] == 'clear' then
            if tuneProp and DoesEntityExist(tuneProp) then DeleteEntity(tuneProp) end
            tuneProp = nil
            return
        end
        if #args >= 6 then
            fob.prop.offset = vec3(tonumber(args[1]), tonumber(args[2]), tonumber(args[3]))
            fob.prop.rotation = vec3(tonumber(args[4]), tonumber(args[5]), tonumber(args[6]))
        end
        if args[7] then fob.prop.bone = tonumber(args[7]) end
        if tuneProp and DoesEntityExist(tuneProp) then DeleteEntity(tuneProp) end
        lib.requestModel(fob.prop.model)
        local coords = GetEntityCoords(cache.ped)
        tuneProp = CreateObject(fob.prop.model, coords.x, coords.y, coords.z, false, false, false)
        local o, r = fob.prop.offset, fob.prop.rotation
        AttachEntityToEntity(tuneProp, cache.ped, GetPedBoneIndex(cache.ped, fob.prop.bone), o.x, o.y, o.z, r.x, r.y, r.z, true, true, false, true, 1, true)
        print(('offset = vec3(%.3f, %.3f, %.3f), rotation = vec3(%.1f, %.1f, %.1f), bone = %d'):format(o.x, o.y, o.z, r.x, r.y, r.z, fob.prop.bone))
    end, false)
end

local function canPickup(entity)
    local box = BoxByEntity[entity]
    return box ~= nil and not box.deployed and not cache.vehicle
end

local function canTakeFob(entity)
    return BoxByEntity[entity] ~= nil and not cache.vehicle
end

local function canDeploy(entity)
    local box = BoxByEntity[entity]
    return box ~= nil and not box.deployed
end

local function canRetract(entity)
    local box = BoxByEntity[entity]
    return box ~= nil and box.deployed
end

if useTarget == 'ox_target' then
    exports.ox_target:addModel(Config.box.model, {
        {
            name = 'nd_autospike:pickup',
            icon = 'fa-solid fa-box-open',
            label = locale('pickup_target'),
            distance = Config.pickupDistance,
            canInteract = canPickup,
            onSelect = function(data) pickupBox(data.entity) end,
        },
        {
            name = 'nd_autospike:fob',
            icon = 'fa-solid fa-key',
            label = locale('take_fob_target'),
            distance = Config.pickupDistance,
            canInteract = canTakeFob,
            onSelect = function(data) takeFob(data.entity) end,
        },
        {
            name = 'nd_autospike:deploy',
            icon = 'fa-solid fa-road-spikes',
            label = locale('deploy_target'),
            distance = Config.pickupDistance,
            canInteract = canDeploy,
            onSelect = function(data) toggleBox(data.entity) end,
        },
        {
            name = 'nd_autospike:retract',
            icon = 'fa-solid fa-road-spikes',
            label = locale('retract_target'),
            distance = Config.pickupDistance,
            canInteract = canRetract,
            onSelect = function(data) toggleBox(data.entity) end,
        },
    })
elseif useTarget == 'qb-target' then
    exports['qb-target']:AddTargetModel(Config.box.model, {
        options = {
            {
                icon = 'fa-solid fa-box-open',
                label = locale('pickup_target'),
                canInteract = canPickup,
                action = function(entity) pickupBox(entity) end,
            },
            {
                icon = 'fa-solid fa-key',
                label = locale('take_fob_target'),
                canInteract = canTakeFob,
                action = function(entity) takeFob(entity) end,
            },
            {
                icon = 'fa-solid fa-road-spikes',
                label = locale('deploy_target'),
                canInteract = canDeploy,
                action = function(entity) toggleBox(entity) end,
            },
            {
                icon = 'fa-solid fa-road-spikes',
                label = locale('retract_target'),
                canInteract = canRetract,
                action = function(entity) toggleBox(entity) end,
            },
        },
        distance = Config.pickupDistance,
    })
else
    local current
    local shown = false

    lib.addKeybind({
        name = 'nd_autospike_pickup',
        description = locale('keybind_pickup'),
        defaultKey = Config.pickupKey,
        onReleased = function()
            if current and not placing then pickupBox(current) end
        end,
    })

    lib.addKeybind({
        name = 'nd_autospike_fob',
        description = locale('keybind_fob'),
        defaultKey = Config.fobKey,
        onReleased = function()
            if current and not placing then takeFob(current) end
        end,
    })

    CreateThread(function()
        while true do
            local wait = 500
            current = nil
            if not cache.vehicle and next(BoxByEntity) then
                wait = 250
                local pedCoords = GetEntityCoords(cache.ped)
                local best
                for entity, box in pairs(BoxByEntity) do
                    if not box.deployed and DoesEntityExist(entity) then
                        local distance = #(pedCoords - GetEntityCoords(entity))
                        if distance <= Config.pickupDistance and (not best or distance < best) then
                            best = distance
                            current = entity
                        end
                    end
                end
            end
            if current and not shown and not placing then
                lib.showTextUI(locale('pickup_help'), { position = 'right-center' })
                shown = true
            elseif (not current or placing) and shown then
                lib.hideTextUI()
                shown = false
            end
            Wait(wait)
        end
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    placing = false
    lib.hideTextUI()
end)
