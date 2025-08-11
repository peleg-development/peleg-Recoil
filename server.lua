---@diagnostic disable: undefined-global

local resourceName = GetCurrentResourceName()

local function readJsonFile()
    local raw = LoadResourceFile(resourceName, 'recoil.json')
    if not raw or raw == '' then
        local initial = { weapons = {} }
        SaveResourceFile(resourceName, 'recoil.json', json.encode(initial), -1)
        return initial
    end
    local decoded = json.decode(raw)
    if not decoded then
        decoded = { weapons = {} }
        SaveResourceFile(resourceName, 'recoil.json', json.encode(decoded), -1)
    end
    decoded.weapons = decoded.weapons or {}
    return decoded
end

--- Persists the current state to disk.
--- @param state table
local function writeJsonFile(state)
    SaveResourceFile(resourceName, 'recoil.json', json.encode({ weapons = state.weapons }), -1)
end

--- Extracts the primary Rockstar license identifier from a player's identifiers.
--- @param src number
--- @return string|nil
local function getPlayerLicense(src)
    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if identifier:sub(1, 8) == 'license:' then
            return identifier
        end
    end
    return nil
end

--- Determines whether a license has permission to use recoil control.
--- @param license string
--- @return boolean
local function isLicenseAllowed(license)
    if not Config or not Config.allowedLicenses then
        return true
    end
    for _, allowed in ipairs(Config.allowedLicenses) do
        if allowed == license then
            return true
        end
    end
    return false
end

---@diagnostic disable: undefined-global
local persistentState = readJsonFile()

RegisterNetEvent('peleg:server:requestRecoilData')
AddEventHandler('peleg:server:requestRecoilData', function()
    local src = source
    local license = getPlayerLicense(src)
    if not license then
        TriggerClientEvent('peleg:client:syncRecoilData', src, {})
        return
    end
    
    if not isLicenseAllowed(license) then
        TriggerClientEvent('peleg:client:syncRecoilData', src, {})
        return
    end
    
    local recoilData = {}
    for weaponHash, weaponData in pairs(persistentState.weapons) do
        if weaponData.recoilModifier then
            recoilData[weaponHash] = weaponData.recoilModifier
        end
    end
    
    TriggerClientEvent('peleg:client:syncRecoilData', src, recoilData)
end)

RegisterNetEvent('peleg:server:saveRecoil')
AddEventHandler('peleg:server:saveRecoil', function(weaponHash, recoilValue)
    local src = source
    local license = getPlayerLicense(src)
    if not license then
        return
    end
    
    if not isLicenseAllowed(license) then
        return
    end
    
    local numericHash = tonumber(weaponHash)
    local numericValue = tonumber(recoilValue)
    if not numericHash or not numericValue then
        return
    end
    
    local weaponHashStr = tostring(numericHash)
    
    if not persistentState.weapons[weaponHashStr] then
        persistentState.weapons[weaponHashStr] = {
            name = "UNKNOWN_WEAPON",
            recoilModifier = 1.0
        }
    end
    
    persistentState.weapons[weaponHashStr].recoilModifier = numericValue
    
    writeJsonFile(persistentState)
    
    -- Send updated data back to client
    local recoilData = {}
    for hash, weaponData in pairs(persistentState.weapons) do
        if weaponData.recoilModifier then
            recoilData[hash] = weaponData.recoilModifier
        end
    end
    
    TriggerClientEvent('peleg:client:syncRecoilData', src, recoilData)
end)

RegisterCommand('controlrecoil', function(src, args)
    if src == 0 then
        print('[peleg-recoil] This command must be used by a player.')
        return
    end
    
    local license = getPlayerLicense(src)
    if not license then
        TriggerClientEvent('chat:addMessage', src, { args = { 'Recoil', 'No license identifier found.' } })
        return
    end
    
    if not isLicenseAllowed(license) then
        TriggerClientEvent('chat:addMessage', src, { args = { 'Recoil', 'You do not have permission to use this command.' } })
        return
    end
    
    local weaponArg = args[1]
    if not weaponArg or weaponArg == '' then
        TriggerClientEvent('chat:addMessage', src, { args = { 'Recoil', 'Usage: /controlrecoil weapon_name' } })
        return
    end
    
    local normalized = string.lower(weaponArg)
    if not normalized:find('weapon_', 1, true) then
        normalized = 'weapon_' .. normalized
    end
    
    local weaponHash = GetHashKey(normalized)
    if weaponHash == 0 then
        TriggerClientEvent('chat:addMessage', src, { args = { 'Recoil', 'Unknown weapon.' } })
        return
    end
    
    local recoilData = {}
    for hash, weaponData in pairs(persistentState.weapons) do
        if weaponData.recoilModifier then
            recoilData[hash] = weaponData.recoilModifier
        end
    end
    
    TriggerClientEvent('peleg:client:syncRecoilData', src, recoilData)
    TriggerClientEvent('peleg:client:startRecoilControl', src, normalized)
end, false)


