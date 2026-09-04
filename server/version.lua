local VERSION_URL = 'https://raw.githubusercontent.com/NateDoggDev/script_versions/main/nd_autospike.txt'

local function cleanVersion(version)
    version = tostring(version or ''):gsub('^%s+', ''):gsub('%s+$', '')
    return version:gsub('^[vV]', '')
end

local function compareVersions(a, b)
    local left, right = {}, {}

    for value in cleanVersion(a):gmatch('%d+') do
        left[#left + 1] = tonumber(value)
    end

    for value in cleanVersion(b):gmatch('%d+') do
        right[#right + 1] = tonumber(value)
    end

    for i = 1, math.max(#left, #right, 3) do
        local l = left[i] or 0
        local r = right[i] or 0
        if l > r then return 1 end
        if l < r then return -1 end
    end

    return 0
end

CreateThread(function()
    if GetConvar('autospike:versioncheck', 'true') ~= 'true' then return end

    Wait(1000)

    local resource = GetCurrentResourceName()
    local current = cleanVersion(GetResourceMetadata(resource, 'version', 0))

    PerformHttpRequest(VERSION_URL, function(status, body)
        if status ~= 200 or not body then return end

        local latest = cleanVersion(body)
        if latest == '' then return end

        local comparison = compareVersions(latest, current)
        if comparison > 0 then
            print(('^3[%s]^0 Update available: ^1%s^0 -> ^2%s^0'):format(resource, current ~= '' and current or 'unknown', latest))
            print(('^3[%s]^0 Download the latest version from your purchase portal.'):format(resource))
            print(('^3[%s]^0 Check Discord changelogs for files to update: discord.gg/ey2sMahZ6t'):format(resource))
        elseif comparison < 0 then
            print(('^3[%s]^0 Installed version ^2%s^0 is newer than the public version file ^1%s^0.'):format(resource, current ~= '' and current or 'unknown', latest))
        end
    end, 'GET')
end)
