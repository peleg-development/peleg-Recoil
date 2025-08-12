--[[
  Commands
    • /controlrecoil <weapon_name>
    • /controldmage  <weapon_name>  (kept for backward-compat)
    • /controldamage <weapon_name>  (fixed alias)
]]

---@diagnostic disable: undefined-global

----------------------------------------
-- Config Access
----------------------------------------
local resourceName = GetCurrentResourceName()

----------------------------------------
-- Persistence
----------------------------------------
--- Reads the JSON state from disk, creating an empty file if necessary.
--- @return table
local function readJsonFile()
    local raw = LoadResourceFile(resourceName, 'recoil.json')
    if not raw or raw == '' then
        local initial = { weapons = {} }
        SaveResourceFile(resourceName, 'recoil.json', json.encode(initial), -1)
        return initial
    end
    local decoded = json.decode(raw) or { weapons = {} }
    decoded.weapons = decoded.weapons or {}
    return decoded
end

--- Writes the JSON state back to disk.
--- @param state table
local function writeJsonFile(state)
    SaveResourceFile(resourceName, 'recoil.json', json.encode({ weapons = state.weapons or {} }), -1)
end

----------------------------------------
-- Identity & Permissions
----------------------------------------
--- Returns the rockstar license identifier for a player, if any.
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

--- Checks whether a license is allowed via Config.allowedLicenses (if provided).
--- @param license string|nil
--- @return boolean
local function isLicenseAllowed(license)
    if not license then return false end
    for _, allowed in ipairs(Config.allowedLicenses) do
        if allowed == license then return true end
    end
    return false
end

----------------------------------------
-- State (Loaded from disk)
----------------------------------------
local persistentState = readJsonFile()

--- Ensures a weapon entry exists.
--- @param weaponHashStr string
--- @param defaults table|nil
local function ensureWeaponEntry(weaponHashStr, defaults)
    if not persistentState.weapons[weaponHashStr] then
        persistentState.weapons[weaponHashStr] = {
            name            = defaults and defaults.name or 'UNKNOWN_WEAPON',
            recoilModifier  = defaults and defaults.recoilModifier or 1.0,
            damageModifier  = defaults and defaults.damageModifier or 1.0,
            headshotFixed150 = defaults and defaults.headshotFixed150 or false,
        }
    end

    local entry = persistentState.weapons[weaponHashStr]
    if entry.recoilModifier == nil then entry.recoilModifier = defaults and defaults.recoilModifier or 1.0 end
    if entry.damageModifier == nil then entry.damageModifier = defaults and defaults.damageModifier or 1.0 end
    if entry.headshotFixed150 == nil then entry.headshotFixed150 = defaults and defaults.headshotFixed150 or false end
    if not entry.name or entry.name == '' then entry.name = defaults and defaults.name or 'UNKNOWN_WEAPON' end

    writeJsonFile(persistentState)
end


--- Builds a table of { [hashStr] = number } for a given numeric field.
--- @param field 'recoilModifier'|'damageModifier'
--- @return table
local function buildNumericMap(field)
    local t = {}
    for hash, weaponData in pairs(persistentState.weapons) do
        local v = weaponData[field]
        if type(v) == 'number' then
            t[hash] = v
        end
    end
    return t
end

--- Builds a table of { [hashStr] = boolean } for the headshot toggle.
--- @return table
local function buildHeadshotMap()
    local t = {}
    for hash, weaponData in pairs(persistentState.weapons) do
        if weaponData.headshotFixed150 ~= nil then
            t[hash] = weaponData.headshotFixed150 and true or false
        end
    end
    return t
end

----------------------------------------
-- Request Handlers (client → server)
----------------------------------------

--- Used events because those are only triggered once when the script starts creating a callback creates unnecessary overhead
RegisterNetEvent('peleg:server:requestRecoilData', function()
    local src = source
    TriggerClientEvent('peleg:client:syncRecoilData', src, buildNumericMap('recoilModifier'))
end)

RegisterNetEvent('peleg:server:requestDamageData', function()
    local src = source
    TriggerClientEvent('peleg:client:syncDamageData', src, buildNumericMap('damageModifier'))
end)

RegisterNetEvent('peleg:server:requestHeadshotFix', function()
    local src = source
    TriggerClientEvent('peleg:client:syncHeadshotFix', src, buildHeadshotMap())
end)
---

lib.callback.register('peleg:server:checkPermission', function(src)
    local license
    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if identifier:sub(1, 8) == 'license:' then
            license = identifier
            break
        end
    end
    return isLicenseAllowed(license)
end)

----------------------------------------
-- Save Handlers (client → server)
----------------------------------------
RegisterNetEvent('peleg:server:saveRecoil', function(weaponHash, recoilValue)
    local src     = source
    local license = getPlayerLicense(src)
    if not isLicenseAllowed(license) then return end

    local nHash = tonumber(weaponHash)
    local nVal  = tonumber(recoilValue)
    if not nHash or not nVal then return end

    local key = tostring(nHash)
    ensureWeaponEntry(key)
    persistentState.weapons[key].recoilModifier = nVal

    writeJsonFile(persistentState)
    TriggerClientEvent('peleg:client:syncRecoilData', src, buildNumericMap('recoilModifier'))
end)

RegisterNetEvent('peleg:server:saveDamage', function(weaponHash, damageValue)
    local src     = source
    local license = getPlayerLicense(src)
    if not isLicenseAllowed(license) then return end

    local nHash = tonumber(weaponHash)
    local nVal  = tonumber(damageValue)
    if not nHash or not nVal then return end

    local key = tostring(nHash)
    ensureWeaponEntry(key)
    persistentState.weapons[key].damageModifier = nVal

    writeJsonFile(persistentState)
    TriggerClientEvent('peleg:client:syncDamageData', src, buildNumericMap('damageModifier'))
end)

RegisterNetEvent('peleg:server:saveHeadshotFix', function(weaponHash, isEnabled)
    local src     = source
    local license = getPlayerLicense(src)
    if not isLicenseAllowed(license) then return end

    local nHash = tonumber(weaponHash)
    if not nHash then return end

    local key = tostring(nHash)
    ensureWeaponEntry(key)
    persistentState.weapons[key].headshotFixed150 = (isEnabled and true or false)

    writeJsonFile(persistentState)
    TriggerClientEvent('peleg:client:syncHeadshotFix', src, buildHeadshotMap())
end)

----------------------------------------
-- Commands
----------------------------------------
--- Normalizes a weapon name into a GTA weapon identifier string.
--- @param raw string
--- @return string normalized
local function normalizeWeaponName(raw)
    local s = string.lower(raw or '')
    if s == '' then return '' end
    if not s:find('weapon_', 1, true) then s = 'weapon_' .. s end
    return s
end

--- Starts recoil control on client.
--- /controlrecoil <weapon_name>
RegisterCommand('controlrecoil', function(src, args)
    if src == 0 then
        print('[peleg-recoil] This command must be used by a player.')
        return
    end

    local license = getPlayerLicense(src)
    if not isLicenseAllowed(license) then
        TriggerClientEvent('chat:addMessage', src,
            { args = { 'Recoil', 'You do not have permission to use this command.' } })
        return
    end

    local normalized = normalizeWeaponName(args[1] or '')
    if normalized == '' then
        TriggerClientEvent('chat:addMessage', src, { args = { 'Recoil', 'Usage: /controlrecoil <weapon_name>' } })
        return
    end

    local weaponHash = GetHashKey(normalized)
    if weaponHash == 0 then
        TriggerClientEvent('chat:addMessage', src, { args = { 'Recoil', 'Unknown weapon.' } })
        return
    end
    ensureWeaponEntry(tostring(weaponHash), { name = normalized })
    TriggerClientEvent('peleg:client:syncRecoilData', src, buildNumericMap('recoilModifier'))
    TriggerClientEvent('peleg:client:startRecoilControl', src, normalized)
end, false)

--- Starts damage control on client.
--- /controldmage  <weapon_name> (legacy)
--- /controldamage <weapon_name> (preferred)
local function cmdStartDamage(src, args)
    if src == 0 then
        print('[peleg-recoil] This command must be used by a player.')
        return
    end

    local license = getPlayerLicense(src)
    if not isLicenseAllowed(license) then
        TriggerClientEvent('chat:addMessage', src,
            { args = { 'Damage', 'You do not have permission to use this command.' } })
        return
    end

    local normalized = normalizeWeaponName(args[1] or '')
    if normalized == '' then
        TriggerClientEvent('chat:addMessage', src, { args = { 'Damage', 'Usage: /controldamage <weapon_name>' } })
        return
    end

    local weaponHash = GetHashKey(normalized)
    if weaponHash == 0 then
        TriggerClientEvent('chat:addMessage', src, { args = { 'Damage', 'Unknown weapon.' } })
        return
    end
    ensureWeaponEntry(tostring(weaponHash), { name = normalized })
    TriggerClientEvent('peleg:client:syncDamageData', src, buildNumericMap('damageModifier'))
    TriggerClientEvent('peleg:client:startDamageControl', src, normalized)
end

RegisterCommand('controldmage', cmdStartDamage, false)  -- legacy
RegisterCommand('controldamage', cmdStartDamage, false) -- fixed alias
