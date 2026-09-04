Boxes = {}
BoxByEntity = {}

local strips = {}
local nearby = {}
local nearbyCount = 0
local tick
local timeOffset = 0
local deployDuration = 0
local strip = Config.strip
local dict = strip.animDict
local clip = strip.deployClip
local halfWidth = strip.width / 2

local synced = false

local function serverTime()
    return GetGameTimer() + timeOffset
end

local function since(t)
    if not synced then return 0 end
    local elapsed = serverTime() - t
    if elapsed < 0 then return 0 end
    return elapsed
end

local function entityFromNetId(netId)
    local ok, entity = pcall(lib.waitFor, function()
        if NetworkDoesEntityExistWithNetworkId(netId) then
            local ent = NetworkGetEntityFromNetworkId(netId)
            if ent ~= 0 then return ent end
        end
    end, nil, 10000)
    if ok and entity and DoesEntityExist(entity) then return entity end
end

local function getDeployDuration()
    if deployDuration > 0 then return deployDuration end
    lib.requestAnimDict(dict)
    deployDuration = math.floor(GetAnimDuration(dict, clip) * 1000)
    if deployDuration <= 0 then deployDuration = strip.deployTime end
    return deployDuration
end

local bankLoaded

local function playDeploySound(entity)
    local sound = Config.sound.deploy
    if not sound then return end
    if bankLoaded == nil then
        local ok, loaded = pcall(lib.requestAudioBank, sound.bank, 3000)
        bankLoaded = ok and loaded and true or false
    end
    local id = GetSoundId()
    if bankLoaded then
        PlaySoundFromEntity(id, sound.name, entity, sound.set, false, 0)
    elseif sound.fallback then
        PlaySoundFromEntity(id, sound.fallback.name, entity, sound.fallback.set, false, 0)
    end
    ReleaseSoundId(id)
end

local function groundZ(p)
    local found, z = GetGroundZFor_3dCoord(p.x, p.y, p.z + 2.0, false)
    if found then return z end
end

local function groundAt(p)
    local z = groundZ(p)
    if z then return vec3(p.x, p.y, z) end
    return p
end

local modelMinZ

local function groundStrip(data)
    local entity = data.entity
    if not DoesEntityExist(entity) then return false end
    local coords = GetEntityCoords(entity)
    local z = groundZ(coords)
    if not z then return false end
    if not modelMinZ then
        local min = GetModelDimensions(strip.model)
        modelMinZ = min and min.z or 0.0
    end
    SetEntityRotation(entity, 0.0, 0.0, data.heading, 2, true)
    local near = GetOffsetFromEntityInWorldCoords(entity, 0.0, strip.yMin, 0.0)
    local far = GetOffsetFromEntityInWorldCoords(entity, 0.0, strip.yMax, 0.0)
    local zn = groundZ(near)
    local zf = groundZ(far)
    local pitch = 0.0
    if zn and zf then
        if data.origin and zn < data.origin.z - 0.05 then zn = data.origin.z end
        pitch = math.deg(math.atan(zf - zn, strip.yMax - strip.yMin))
        z = (zn + zf) / 2
    end
    z = z - modelMinZ + (strip.zOffset or 0.0)
    SetEntityCoordsNoOffset(entity, coords.x, coords.y, z, false, false, false)
    SetEntityRotation(entity, pitch, 0.0, data.heading, 2, true)
    FreezeEntityPosition(entity, true)
    data.grounded = true
    data.pitch = pitch
    if NetworkHasControlOfEntity(entity) then
        TriggerServerEvent('nd_autospike:server:grounded', data.netId, vec3(coords.x, coords.y, z), vec3(pitch, 0.0, data.heading))
    end
    return true
end

local function waitForAnim(entity)
    return pcall(lib.waitFor, function()
        if IsEntityPlayingAnim(entity, dict, clip, 3) then return true end
    end, nil, 2000)
end

local function startAnim(entity)
    lib.requestAnimDict(dict)
    PlayEntityAnim(entity, clip, dict, 1000.0, false, true, false, 0.0, 0)
    return waitForAnim(entity)
end

local function holdPhase()
    return math.min(strip.holdPhase or 1.0, 0.999)
end

local function holdAnim(entity)
    SetEntityAnimCurrentTime(entity, dict, clip, holdPhase())
    SetEntityAnimSpeed(entity, dict, clip, 0.0)
end

local coilSide

local function detectCoilSide(entity)
    if strip.coilSide and strip.coilSide ~= 'auto' then return strip.coilSide end
    if coilSide then return coilSide end
    local count = GetEntityBoneCount(entity)
    if not count or count < 3 or not startAnim(entity) then
        coilSide = 'near'
        return coilSide
    end
    SetEntityAnimSpeed(entity, dict, clip, 0.0)
    SetEntityAnimCurrentTime(entity, dict, clip, 0.0)
    Wait(0)
    Wait(0)
    local sum, n = 0.0, 0
    for i = 0, count - 1 do
        local pos = GetWorldPositionOfEntityBone(entity, i)
        if pos.x ~= 0.0 or pos.y ~= 0.0 or pos.z ~= 0.0 then
            local off = GetOffsetFromEntityGivenWorldCoords(entity, pos.x, pos.y, pos.z)
            sum += off.y
            n += 1
        end
    end
    local mean = n > 0 and sum / n or 0.0
    coilSide = mean > 0.3 and 'far' or 'near'
    if Config.debug then print('[nd_autospike] coil side', coilSide, mean, count) end
    return coilSide
end

local function orientForCoil(data)
    local entity = data.entity
    if detectCoilSide(entity) == 'far' and not data.flipped then
        data.flipped = true
        data.heading = (data.heading + 180.0) % 360
        local pitch = data.pitch and -data.pitch or 0.0
        data.pitch = data.pitch and -data.pitch or nil
        SetEntityRotation(entity, pitch, 0.0, data.heading, 2, true)
    end
end

local function rollDeploy(data)
    local entity = data.entity
    orientForCoil(data)
    local hold = holdPhase()
    local duration = math.floor(getDeployDuration() * hold)
    local per = duration + strip.stagger
    local startAt = (data.index - 1) * per
    local elapsed = since(data.at)

    if elapsed >= startAt + duration then
        if startAnim(entity) then
            SetEntityAnimSpeed(entity, dict, clip, 1.0)
            holdAnim(entity)
        end
        SetEntityVisible(entity, true, false)
        if data.phase == 'deploy' then data.phase = 'deployed' end
        return
    end

    SetEntityVisible(entity, false, false)
    if elapsed < startAt then
        Wait(startAt - elapsed)
    end
    if data.phase ~= 'deploy' or not DoesEntityExist(entity) or data.entity ~= entity then return end

    if startAnim(entity) then
        SetEntityAnimSpeed(entity, dict, clip, 1.0)
        SetEntityAnimCurrentTime(entity, dict, clip, 0.0)
        elapsed = since(data.at)
        local progress = (elapsed - startAt) / duration * hold
        if progress > 0.05 and progress < hold then
            SetEntityAnimCurrentTime(entity, dict, clip, progress)
        end
    end
    SetEntityVisible(entity, true, false)
    playDeploySound(entity)

    while DoesEntityExist(entity) and data.entity == entity and data.phase == 'deploy' do
        local remaining = (startAt + duration) - since(data.at)
        if remaining <= 0 then break end
        Wait(math.min(remaining, 50))
    end
    if data.phase == 'deploy' and data.entity == entity and DoesEntityExist(entity) then
        if hold < 0.999 then holdAnim(entity) end
        data.phase = 'deployed'
    end
end

local function rollRetract(data)
    local entity = data.entity
    if not DoesEntityExist(entity) then return end
    local duration = strip.retractDuration
    local startAt = ((data.count or data.index) - data.index) * (duration + strip.stagger)
    local elapsed = since(data.at)
    if elapsed < startAt then
        Wait(startAt - elapsed)
    end
    if data.phase ~= 'retract' or not DoesEntityExist(entity) or data.entity ~= entity then return end
    if not IsEntityPlayingAnim(entity, dict, clip, 3) then
        startAnim(entity)
    end
    SetEntityAnimSpeed(entity, dict, clip, 0.0)
    local hold = holdPhase()
    local start = data.at + startAt
    while DoesEntityExist(entity) and data.entity == entity do
        local t = hold * (1.0 - since(start) / duration)
        if t <= 0.0 then break end
        SetEntityAnimCurrentTime(entity, dict, clip, t)
        Wait(0)
    end
    if DoesEntityExist(entity) then
        SetEntityVisible(entity, false, false)
    end
end

local function easeOut(t)
    return 1.0 - (1.0 - t) * (1.0 - t)
end

local function easeIn(t)
    return t * t
end

local function makeGhost(data)
    lib.requestModel(strip.model)
    local ghost = CreateObjectNoOffset(strip.model, data.origin.x, data.origin.y, data.origin.z, false, false, false)
    SetModelAsNoLongerNeeded(strip.model)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetEntityRotation(ghost, 0.0, 0.0, data.heading, 2, true)
    return ghost
end

local function killGhost(data, ghost)
    if data.ghost == ghost then data.ghost = nil end
    if DoesEntityExist(ghost) then DeleteEntity(ghost) end
end

local function slideDeployTiming(data)
    if data.index == 1 then
        return 0, strip.flipTime, strip.flipTime
    end
    local startAt = strip.flipTime + (data.index - 2) * strip.stagger
    return startAt, strip.slideTime, startAt + strip.slideTime
end

local function slideRetractTiming(data)
    local count = data.count or data.index
    if data.index == 1 then
        local startAt = count > 1 and (strip.slideTime + (count - 2) * strip.stagger) or 0
        return startAt, strip.flipTime
    end
    return (count - data.index) * strip.stagger, strip.slideTime
end

local function slideDeploy(data)
    local entity = data.entity
    local startAt, duration, total = slideDeployTiming(data)
    local elapsed = since(data.at)

    if elapsed >= total then
        SetEntityVisible(entity, true, false)
        if data.phase == 'deploy' then data.phase = 'deployed' end
        return
    end

    SetEntityVisible(entity, false, false)
    if elapsed < startAt then Wait(startAt - elapsed) end
    if data.phase ~= 'deploy' or not DoesEntityExist(entity) or data.entity ~= entity then return end

    local ghost = makeGhost(data)
    data.ghost = ghost
    if since(data.at) - startAt < 100 then playDeploySound(ghost) end

    local start = data.at + startAt
    local origin = groundAt(data.origin)
    local final = groundAt(data.final)
    local pitch = data.pitch or 0.0
    while DoesEntityExist(entity) and data.entity == entity and data.ghost == ghost and data.phase == 'deploy' do
        local t = since(start) / duration
        if t >= 1.0 then break end
        if data.index == 1 then
            local e = easeOut(t)
            SetEntityCoordsNoOffset(ghost, origin.x, origin.y, origin.z, false, false, false)
            SetEntityRotation(ghost, strip.flipStartPitch * (1.0 - e) + pitch * e, 0.0, data.heading, 2, true)
        else
            local p = origin + (final - origin) * easeOut(t)
            SetEntityCoordsNoOffset(ghost, p.x, p.y, p.z, false, false, false)
        end
        Wait(0)
    end
    killGhost(data, ghost)
    if data.phase == 'deploy' and data.entity == entity and DoesEntityExist(entity) then
        SetEntityVisible(entity, true, false)
        data.phase = 'deployed'
    end
end

local function slideRetract(data)
    local entity = data.entity
    if not DoesEntityExist(entity) then return end
    local startAt, duration = slideRetractTiming(data)
    local elapsed = since(data.at)

    SetEntityVisible(entity, false, false)
    if elapsed >= startAt + duration then return end
    if elapsed < startAt then Wait(startAt - elapsed) end
    if data.phase ~= 'retract' or not DoesEntityExist(entity) or data.entity ~= entity then return end

    local ghost = makeGhost(data)
    data.ghost = ghost
    local start = data.at + startAt
    local origin = groundAt(data.origin)
    local final = groundAt(data.final)
    local pitch = data.pitch or 0.0
    while DoesEntityExist(entity) and data.entity == entity and data.ghost == ghost do
        local t = since(start) / duration
        if t >= 1.0 then break end
        if data.index == 1 then
            local e = easeIn(t)
            SetEntityCoordsNoOffset(ghost, origin.x, origin.y, origin.z, false, false, false)
            SetEntityRotation(ghost, pitch * (1.0 - e) + strip.flipStartPitch * e, 0.0, data.heading, 2, true)
        else
            local p = final + (origin - final) * easeIn(t)
            SetEntityCoordsNoOffset(ghost, p.x, p.y, p.z, false, false, false)
        end
        Wait(0)
    end
    killGhost(data, ghost)
end

local deployStrip = strip.mode == 'roll' and rollDeploy or slideDeploy
local retractStrip = strip.mode == 'roll' and rollRetract or slideRetract

local function registerStrip(netId, value)
    local entity = entityFromNetId(netId)
    if not entity then return end
    local data = strips[netId]
    if data and data.ghost then
        killGhost(data, data.ghost)
    end
    if not data or data.entity ~= entity then
        data = {
            netId = netId,
            entity = entity,
            box = value.box,
            index = value.index,
            count = value.count,
            heading = value.heading,
            origin = value.origin,
            final = value.final,
            at = value.at,
            phase = value.phase,
        }
        strips[netId] = data
        FreezeEntityPosition(entity, true)
        SetEntityRotation(entity, 0.0, 0.0, value.heading, 2, true)
        groundStrip(data)
    else
        data.phase = value.phase
        data.at = value.at
    end

    if value.phase == 'deploy' then
        CreateThread(function()
            local ok, err = pcall(deployStrip, data)
            if not ok and Config.debug then print('[nd_autospike] deploy error', err) end
            if data.phase == 'deploy' and data.entity == entity and DoesEntityExist(entity) then
                if data.ghost then killGhost(data, data.ghost) end
                SetEntityVisible(entity, true, false)
                data.phase = 'deployed'
            end
        end)
    elseif value.phase == 'retract' then
        CreateThread(function()
            local ok, err = pcall(retractStrip, data)
            if not ok and Config.debug then print('[nd_autospike] retract error', err) end
            if data.ghost then killGhost(data, data.ghost) end
        end)
    end
end

local function registerBox(netId, value)
    local box = Boxes[netId]
    if box and DoesEntityExist(box.entity) then
        box.deployed = value.deployed
        box.owner = value.owner
        return
    end
    if box then BoxByEntity[box.entity] = nil end
    local entity = entityFromNetId(netId)
    if not entity then return end
    FreezeEntityPosition(entity, true)
    SetEntityRotation(entity, value.rotation.x, value.rotation.y, value.rotation.z, 2, true)
    Boxes[netId] = {
        netId = netId,
        entity = entity,
        id = value.id,
        owner = value.owner,
        deployed = value.deployed,
    }
    BoxByEntity[entity] = Boxes[netId]
end

local function unregisterBox(netId)
    local box = Boxes[netId]
    if not box then return end
    BoxByEntity[box.entity] = nil
    Boxes[netId] = nil
end

local function netIdFromBag(bagName)
    return tonumber(bagName:match('entity:(%d+)'))
end

AddStateBagChangeHandler('nd_autospike', nil, function(bagName, _, value)
    local netId = netIdFromBag(bagName)
    if not netId then return end
    if not value then return unregisterBox(netId) end
    registerBox(netId, value)
end)

AddStateBagChangeHandler('nd_autospike_strip', nil, function(bagName, _, value)
    local netId = netIdFromBag(bagName)
    if not netId then return end
    if not value then
        local data = strips[netId]
        if data and data.ghost then killGhost(data, data.ghost) end
        strips[netId] = nil
        return
    end
    registerStrip(netId, value)
end)

local lastPositions = {}
local candidates = {}

local function sweepHit(entity, from, to)
    local a = GetOffsetFromEntityGivenWorldCoords(entity, from.x, from.y, from.z)
    local b = GetOffsetFromEntityGivenWorldCoords(entity, to.x, to.y, to.z)
    local delta = b - a
    local steps = math.min(32, math.max(1, math.ceil(#delta / 0.12)))
    for i = 0, steps do
        local p = a + delta * (i / steps)
        if math.abs(p.x) <= halfWidth and p.y >= strip.yMin and p.y <= strip.yMax and math.abs(p.z) <= 1.0 then
            return true
        end
    end
    return false
end

local function wheelPositions(vehicle)
    local now = GetGameTimer()
    local prev = lastPositions[vehicle]
    if not prev then
        prev = { time = now }
        lastPositions[vehicle] = prev
    end
    local stale = now - prev.time > 150
    prev.time = now
    local wheels = Config.wheels
    local list = {}
    for i = 1, #wheels do
        local wheel = wheels[i]
        local boneIndex = GetEntityBoneIndexByName(vehicle, wheel.bone)
        if boneIndex ~= -1 then
            local pos = GetWorldPositionOfEntityBone(vehicle, boneIndex)
            local from = (not stale and prev[wheel.index]) or pos
            prev[wheel.index] = pos
            list[#list + 1] = { index = wheel.index, from = from, to = pos }
        end
    end
    return list
end

local function burstTyre(vehicle, index, onRim)
    SetVehicleTyresCanBurst(vehicle, true)
    SetVehicleTyreBurst(vehicle, index, false, 1000.0)
    if onRim then
        SetVehicleTyreBurst(vehicle, index, true, 1000.0)
    end
end

local function burstWheels(vehicle, wheels)
    local vehicleCoords = GetEntityCoords(vehicle)
    local speed = GetEntitySpeed(vehicle) * 3.6
    local onRim = Config.burst.alwaysRim or speed >= Config.burst.rimSpeed
    for i = 1, nearbyCount do
        local data = nearby[i]
        local entity = data.entity
        if DoesEntityExist(entity) and #(vehicleCoords - GetEntityCoords(entity)) < 14.0 then
            for w = 1, #wheels do
                local wheel = wheels[w]
                if not IsVehicleTyreBurst(vehicle, wheel.index, true) then
                    local flat = IsVehicleTyreBurst(vehicle, wheel.index, false)
                    if (not flat or onRim) and sweepHit(entity, wheel.from, wheel.to) then
                        burstTyre(vehicle, wheel.index, onRim)
                    end
                end
            end
        end
    end
end

local function nearAnyStrip(coords)
    for i = 1, nearbyCount do
        local entity = nearby[i].entity
        if DoesEntityExist(entity) and #(coords - GetEntityCoords(entity)) < 16.0 then
            return true
        end
    end
    return false
end

local function processStrips()
    local vehicle = cache.seat == -1 and cache.vehicle or nil
    if vehicle then
        burstWheels(vehicle, wheelPositions(vehicle))
    end
    if Config.burstNpcVehicles then
        for i = 1, #candidates do
            local npc = candidates[i]
            if npc ~= vehicle and DoesEntityExist(npc) and NetworkHasControlOfEntity(npc) and nearAnyStrip(GetEntityCoords(npc)) then
                burstWheels(npc, wheelPositions(npc))
            end
        end
    end
end

local function rescan()
    for _, obj in ipairs(GetGamePool('CObject')) do
        if NetworkGetEntityIsNetworked(obj) then
            local state = Entity(obj).state
            local netId = NetworkGetNetworkIdFromEntity(obj)
            if state.nd_autospike then
                local box = Boxes[netId]
                if not box or box.entity ~= obj then registerBox(netId, state.nd_autospike) end
            elseif state.nd_autospike_strip then
                local data = strips[netId]
                if not data or data.entity ~= obj then registerStrip(netId, state.nd_autospike_strip) end
            end
        end
    end
end

CreateThread(function()
    while not synced do
        local serverNow = lib.callback.await('nd_autospike:sync', false)
        if serverNow then
            timeOffset = serverNow - GetGameTimer()
            synced = true
        else
            Wait(1000)
        end
    end
end)

CreateThread(function()
    rescan()

    local scanRange = Config.burstNpcVehicles and 120.0 or 60.0
    local ticks = 0
    while true do
        ticks += 1
        if ticks % 20 == 0 then rescan() end
        if nearbyCount > 0 then
            table.wipe(nearby)
            nearbyCount = 0
        end
        local pedCoords = GetEntityCoords(cache.ped)
        for netId, data in pairs(strips) do
            if not DoesEntityExist(data.entity) then
                if data.ghost then killGhost(data, data.ghost) end
                strips[netId] = nil
            else
                local distance = #(pedCoords - GetEntityCoords(data.entity))
                if not data.grounded and distance < 150.0 then
                    groundStrip(data)
                end
                if data.phase == 'deployed' and distance < scanRange then
                    nearbyCount += 1
                    nearby[nearbyCount] = data
                end
            end
        end
        for netId, box in pairs(Boxes) do
            if not DoesEntityExist(box.entity) then unregisterBox(netId) end
        end
        if nearbyCount > 0 then
            if Config.burstNpcVehicles then
                table.wipe(candidates)
                for _, veh in ipairs(lib.getNearbyVehicles(pedCoords, scanRange, false)) do
                    candidates[#candidates + 1] = veh.vehicle
                end
            end
            if (cache.seat == -1 or Config.burstNpcVehicles) and not tick then
                tick = SetInterval(processStrips, 0)
            elseif not (cache.seat == -1 or Config.burstNpcVehicles) and tick then
                tick = ClearInterval(tick)
            end
        else
            if tick then tick = ClearInterval(tick) end
            if next(lastPositions) then table.wipe(lastPositions) end
        end
        Wait(250)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if tick then ClearInterval(tick) end
    for _, data in pairs(strips) do
        if data.ghost then killGhost(data, data.ghost) end
    end
end)
