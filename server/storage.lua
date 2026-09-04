Storage = {
    enabled = false,
}

local TABLE = 'nd_autospike_boxes'

local function fire(sql, params)
    local ok, err = pcall(function()
        exports.oxmysql:query(sql, params or {}, function() end, GetCurrentResourceName())
    end)
    if not ok then print('[nd_autospike] database write failed', err) end
end

local function run(sql, params, timeout)
    local p = promise.new()
    local done = false
    local ok, err = pcall(function()
        exports.oxmysql:query(sql, params or {}, function(result)
            if not done then
                done = true
                p:resolve(result)
            end
        end, GetCurrentResourceName())
    end)
    if not ok then
        print('[nd_autospike] database query failed', err)
        return nil
    end
    SetTimeout(timeout or 10000, function()
        if not done then
            done = true
            print('[nd_autospike] database query timed out')
            p:resolve(nil)
        end
    end)
    return Citizen.Await(p)
end

function Storage.init()
    if not Config.persistence then return false end
    if GetResourceState('oxmysql') ~= 'started' then
        print('[nd_autospike] persistence enabled but oxmysql is not started, boxes will not be saved')
        return false
    end
    local created = run(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `id` VARCHAR(8) NOT NULL,
            `owner` VARCHAR(64) NOT NULL,
            `x` FLOAT NOT NULL,
            `y` FLOAT NOT NULL,
            `z` FLOAT NOT NULL,
            `rx` FLOAT NOT NULL DEFAULT 0,
            `ry` FLOAT NOT NULL DEFAULT 0,
            `rz` FLOAT NOT NULL DEFAULT 0,
            `deployed` TINYINT(1) NOT NULL DEFAULT 0,
            `links` TEXT NULL,
            `fobs_issued` INT NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`)
        )
    ]]):format(TABLE))
    if created == nil then
        print('[nd_autospike] could not create the boxes table, persistence disabled')
        return false
    end
    Storage.enabled = true
    return true
end

function Storage.load()
    if not Storage.enabled then return {} end
    local rows = run(('SELECT * FROM `%s`'):format(TABLE)) or {}
    local list = {}
    for i = 1, #rows do
        local row = rows[i]
        local links = {}
        if row.links and row.links ~= '' then
            local ok, decoded = pcall(json.decode, row.links)
            if ok and type(decoded) == 'table' then links = decoded end
        end
        list[#list + 1] = {
            id = tostring(row.id),
            owner = row.owner,
            coords = vec3(row.x + 0.0, row.y + 0.0, row.z + 0.0),
            rotation = vec3(row.rx + 0.0, row.ry + 0.0, row.rz + 0.0),
            deployed = row.deployed == 1 or row.deployed == true,
            links = links,
            fobsIssued = row.fobs_issued or 0,
        }
    end
    return list
end

function Storage.save(box)
    if not Storage.enabled then return end
    fire(([[
        INSERT INTO `%s` (`id`, `owner`, `x`, `y`, `z`, `rx`, `ry`, `rz`, `deployed`, `links`, `fobs_issued`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `deployed` = VALUES(`deployed`), `links` = VALUES(`links`), `fobs_issued` = VALUES(`fobs_issued`)
    ]]):format(TABLE), {
        box.id, box.owner,
        box.coords.x, box.coords.y, box.coords.z,
        box.rotation.x, box.rotation.y, box.rotation.z,
        box.deployed and 1 or 0,
        json.encode(box.links or {}),
        box.fobsIssued or 0,
    })
end

function Storage.delete(id)
    if not Storage.enabled then return end
    fire(('DELETE FROM `%s` WHERE `id` = ?'):format(TABLE), { id })
end

function Storage.clear()
    if not Storage.enabled then return end
    fire(('DELETE FROM `%s`'):format(TABLE))
end
