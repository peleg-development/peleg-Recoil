local CTRL_INC           = 172 -- Up
local CTRL_DEC           = 173 -- Down
local CTRL_SAVE_A        = 170 -- F3
local CTRL_SAVE_B        = 191 -- Enter
local CTRL_TOGGLE        = 74 -- H

local MAX_HEALTH         = 200
local MAX_ARMOUR         = 100
local HEAD_BONE          = 31086

local recoilState        = { saved = {} }
local headshotState      = { saved = {} }
local damageState        = { saved = {} }

local controlState       = {
    active          = false,
    weaponHash      = nil,
    weaponName      = nil,
    currentModifier = 1.0,
    minModifier     = 0.0,
    maxModifier     = 10.0,
    step            = 0.05,
    originalWeapon  = nil,
    originalAmmo    = 0,
}

local damageControlState = {
    active             = false,
    weaponHash         = nil,
    weaponName         = nil,
    currentModifier    = 1.0,
    minModifier        = 0.0,
    maxModifier        = 10.0,
    step               = 0.05,
    originalWeapon     = nil,
    originalAmmo       = 0,
    targetPed          = nil,
    wasDead            = false,
    resetCooldownUntil = 0,
    headshotFixed150   = false,
    lastTargetHealth   = MAX_HEALTH,
    lastTargetArmour   = MAX_ARMOUR,
}

local nuiState           = {
    visible = false,
    mode    = 'recoil', -- 'recoil' | 'damage'
}

--- @param name string
--- @return number
local function H(name) return GetHashKey(name) end

--- @param title string
--- @param msg string
local function chat(title, msg)
    TriggerEvent('chat:addMessage', { args = { title, msg } })
end

--- Clamp helper.
--- @param x number
--- @param a number
--- @param b number
--- @return number
local function clamp(x, a, b)
    if x < a then return a end
    if x > b then return b end
    return x
end

--- @param modifier number
--- @param weaponName string
--- @param mode 'recoil'|'damage'
--- @param saveEvent string
local function showNUI(modifier, weaponName, mode, saveEvent)
    if nuiState.visible then return end
    nuiState.visible = true
    nuiState.mode    = mode or 'recoil'
    SendNUIMessage({
        type        = 'showUI',
        modifier    = modifier,
        weaponName  = weaponName,
        mode        = nuiState.mode,
        saveEvent   = saveEvent or 'peleg:client:saveRecoil',
        headshotFix = damageControlState.headshotFixed150,
    })
end

local function hideNUI()
    if not nuiState.visible then return end
    nuiState.visible = false
    SendNUIMessage({ type = 'hideUI' })
end

--- @param value number
local function updateNUI(value)
    if not nuiState.visible then return end
    SendNUIMessage({ type = 'updateModifier', modifier = value })
end

--- @param health number
--- @param armour number
local function showHUD(health, armour)
    SendNUIMessage({
        type = 'showHUD',
        health = health,
        armour = armour,
        maxHealth = MAX_HEALTH,
        maxArmour = MAX_ARMOUR,
    })
end

local function hideHUD()
    SendNUIMessage({ type = 'hideHUD' })
end

--- @param health number
--- @param armour number
local function updateHUD(health, armour)
    SendNUIMessage({
        type = 'updateTargetStats',
        health = health,
        armour = armour,
        maxHealth = MAX_HEALTH,
        maxArmour = MAX_ARMOUR,
    })
end

CreateThread(function()
    while true do
        Wait(0)
        local ped = cache.ped
        if IsPedArmed(ped, 6) then
            local weapon = cache.weapon
            local mod = (controlState.active and controlState.weaponHash == weapon)
                and controlState.currentModifier
                or (recoilState.saved[tostring(weapon)] or 1.0)
            SetWeaponRecoilShakeAmplitude(weapon, mod)
        end
    end
end)

AddEventHandler("gameEventTriggered", function(name, args)
    if name ~= "CEventNetworkEntityDamage" then return end

    local victim     = args[1]
    local attacker   = args[2]
    local victimDied = args[6] == 1
    local weaponHash = args[7]
    local bone       = args[10] 

    if attacker ~= cache.ped then return end
    if bone ~= HEAD_BONE then return end

    if headshotState.saved[tostring(weaponHash)] then
        local armour = GetPedArmour(victim)
        local health = GetEntityHealth(victim)

        local total       = 150
        local armourAfter = math.max(0, armour - total)
        local remaining   = math.max(0, total - armour)
        local healthAfter = math.max(0, health - remaining)

        SetPedArmour(victim, armourAfter)
        SetEntityHealth(victim, healthAfter)
    end
end)

--- @param ped number
--- @param weaponHash number
local function keepInfiniteAmmoIfCurrent(ped, weaponHash)
    if not IsPedArmed(ped, 6) then return end
    local _, current = cache.weapon
    if current ~= weaponHash then return end
    SetPedInfiniteAmmo(ped, true, weaponHash)
    SetPedInfiniteAmmoClip(ped, true)
end

--- @param out table
local function saveCurrentWeapon(out)
    local ped          = cache.ped
    local _, weap      = cache.weapon
    out.originalWeapon = weap
    out.originalAmmo   = GetAmmoInPedWeapon(ped, weap)
end

--- @param saved table
local function restoreWeapon(saved)
    local ped = cache.ped
    if saved.weaponHash then
        RemoveWeaponFromPed(ped, saved.weaponHash)
    end
    if saved.originalWeapon and saved.originalWeapon ~= 0 then
        GiveWeaponToPed(ped, saved.originalWeapon, saved.originalAmmo or 0, false, true)
        SetCurrentPedWeapon(ped, saved.originalWeapon, true)
    else
        SetCurrentPedWeapon(ped, H('WEAPON_UNARMED'), true)
    end
end

--- @param weaponHash number
--- @param value number
local function applyDamageModifier(weaponHash, value)
    SetWeaponDamageModifier(weaponHash, value)
end

--- @param model string
--- @return number ped
local function spawnTargetPed(model)
    local modelHash = H(model)
    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do Wait(0) end

    local playerPed = PlayerPedId()
    local pcoords = GetEntityCoords(playerPed)
    local fx, fy, fz = table.unpack(GetEntityForwardVector(playerPed))
    local pos = vector3(pcoords.x + fx * 4.0, pcoords.y + fy * 4.0, pcoords.z)

    local _, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z, false)
    if groundZ and groundZ > 0.0 then pos = vector3(pos.x, pos.y, groundZ) end

    local ped = CreatePed(4, modelHash, pos.x, pos.y, pos.z, GetEntityHeading(playerPed) + 180.0, false, true)

    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskStandStill(ped, -1)
    SetEntityInvincible(ped, false)
    SetPedCanRagdoll(ped, false)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetPedRagdollOnCollision(ped, false)
    FreezeEntityPosition(ped, true)
    SetPedDropsWeaponsWhenDead(ped, false)
    DisablePedPainAudio(ped, true)
    StopPedSpeaking(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, false)
    SetPedHearingRange(ped, 0.0)
    SetPedSeeingRange(ped, 0.0)
    SetPedAlertness(ped, 0)
    SetPedSuffersCriticalHits(ped, false)
    SetEntityOnlyDamagedByPlayer(ped, true)
    SetPedArmour(ped, MAX_ARMOUR)
    SetEntityHealth(ped, MAX_HEALTH)
    ClearPedTasksImmediately(ped)
    ResetPedRagdollTimer(ped)
    SetEntityVelocity(ped, 0.0, 0.0, 0.0)
    TaskStandStill(ped, -1)

    return ped
end

local function resetTargetPed()
    if DoesEntityExist(damageControlState.targetPed) then
        DeleteEntity(damageControlState.targetPed)
    end
    damageControlState.targetPed = spawnTargetPed('a_m_m_business_01')
    ClearEntityLastDamageEntity(damageControlState.targetPed)
    TaskStandStill(damageControlState.targetPed, -1)
    SetPedCanRagdoll(damageControlState.targetPed, false)
    SetPedCanRagdollFromPlayerImpact(damageControlState.targetPed, false)
    SetPedRagdollOnCollision(damageControlState.targetPed, false)
    FreezeEntityPosition(damageControlState.targetPed, true)
    SetPedDropsWeaponsWhenDead(damageControlState.targetPed, false)
    DisablePedPainAudio(damageControlState.targetPed, true)
    StopPedSpeaking(damageControlState.targetPed, true)
    SetPedFleeAttributes(damageControlState.targetPed, 0, false)
    SetPedCombatAttributes(damageControlState.targetPed, 46, false)
    SetPedHearingRange(damageControlState.targetPed, 0.0)
    SetPedSeeingRange(damageControlState.targetPed, 0.0)
    SetPedAlertness(damageControlState.targetPed, 0)
    SetPedSuffersCriticalHits(damageControlState.targetPed, false)
    SetEntityOnlyDamagedByPlayer(damageControlState.targetPed, true)
    damageControlState.lastTargetHealth = MAX_HEALTH
    damageControlState.lastTargetArmour = MAX_ARMOUR
    updateHUD(MAX_HEALTH, MAX_ARMOUR)
end

local function cleanupDamageControl()
    hideHUD()
    hideNUI()
    if DoesEntityExist(damageControlState.targetPed) then
        DeleteEntity(damageControlState.targetPed)
        damageControlState.targetPed = nil
    end
    restoreWeapon(damageControlState)
    damageControlState.active = false
end

local function saveRecoilAndExit()
    local ped = cache.ped
    TriggerServerEvent('peleg:server:saveRecoil', controlState.weaponHash, controlState.currentModifier)
    controlState.active = false
    hideNUI()
    RemoveWeaponFromPed(ped, controlState.weaponHash)
    restoreWeapon(controlState)
    chat('Recoil',
        string.format('Saved recoil modifier %.2f for %s', controlState.currentModifier, controlState.weaponName))
end

--- @param weaponName string
local function startRecoilControl(weaponName)
    local ped = cache.ped
    local weaponHash = H(weaponName)

    saveCurrentWeapon(controlState)

    controlState.active          = true
    controlState.weaponName      = weaponName
    controlState.weaponHash      = weaponHash
    controlState.currentModifier = recoilState.saved[tostring(weaponHash)] or 1.0

    GiveWeaponToPed(ped, weaponHash, 9999, false, true)
    SetCurrentPedWeapon(ped, weaponHash, true)
    SetPedInfiniteAmmo(ped, true, weaponHash)
    SetPedInfiniteAmmoClip(ped, true)

    showNUI(controlState.currentModifier, weaponName, 'recoil', 'peleg:client:saveRecoil')
    updateNUI(controlState.currentModifier)

    CreateThread(function()
        while controlState.active do
            Wait(0)
            keepInfiniteAmmoIfCurrent(ped, weaponHash)

            if IsControlJustPressed(0, CTRL_INC) then
                controlState.currentModifier = clamp(controlState.currentModifier + controlState.step,
                    controlState.minModifier, controlState.maxModifier)
                updateNUI(controlState.currentModifier)
            elseif IsControlJustPressed(0, CTRL_DEC) then
                controlState.currentModifier = clamp(controlState.currentModifier - controlState.step,
                    controlState.minModifier, controlState.maxModifier)
                updateNUI(controlState.currentModifier)
            elseif IsControlJustPressed(0, CTRL_SAVE_A) or IsControlJustPressed(0, CTRL_SAVE_B) then
                saveRecoilAndExit()
            end
        end
    end)
end

--- @param weaponName string
local function startDamageControl(weaponName)
    local ped = cache.ped
    local weaponHash = H(weaponName)

    saveCurrentWeapon(damageControlState)

    damageControlState.active             = true
    damageControlState.weaponName         = weaponName
    damageControlState.weaponHash         = weaponHash
    damageControlState.currentModifier    = damageState.saved[tostring(weaponHash)] or 1.0
    damageControlState.wasDead            = false
    damageControlState.resetCooldownUntil = 0
    damageControlState.headshotFixed150   = not not headshotState.saved[tostring(weaponHash)]

    GiveWeaponToPed(ped, weaponHash, 9999, false, true)
    SetCurrentPedWeapon(ped, weaponHash, true)
    SetPedInfiniteAmmo(ped, true, weaponHash)
    SetPedInfiniteAmmoClip(ped, true)

    applyDamageModifier(weaponHash, damageControlState.currentModifier)

    damageControlState.targetPed = spawnTargetPed('a_m_m_business_01')
    showNUI(damageControlState.currentModifier, weaponName, 'damage', 'peleg:client:saveDamage')
    SendNUIMessage({ type = 'setHeadshotFix', value = damageControlState.headshotFixed150 })
    showHUD(GetEntityHealth(damageControlState.targetPed), GetPedArmour(damageControlState.targetPed))

    CreateThread(function()
        while damageControlState.active do
            Wait(0)

            keepInfiniteAmmoIfCurrent(ped, weaponHash)

            DisableControlAction(0, CTRL_TOGGLE, true)

            if DoesEntityExist(damageControlState.targetPed) then
                local h = GetEntityHealth(damageControlState.targetPed)
                local a = GetPedArmour(damageControlState.targetPed)
                updateHUD(h, a)

                local now = GetGameTimer()
                local dead = IsEntityDead(damageControlState.targetPed) or
                IsPedFatallyInjured(damageControlState.targetPed)

                if dead and not damageControlState.wasDead and now >= (damageControlState.resetCooldownUntil or 0) then
                    resetTargetPed()
                    damageControlState.wasDead = true
                    damageControlState.resetCooldownUntil = now + 1200
                elseif not dead then
                    damageControlState.wasDead = false
                end

                if damageControlState.headshotFixed150 then
                    local didDamage = HasEntityBeenDamagedByEntity(damageControlState.targetPed, ped, true)
                    if didDamage then
                        local hit, bone = GetPedLastDamageBone(damageControlState.targetPed)
                        if hit and bone == HEAD_BONE then
                            local total       = 150
                            local lastA       = damageControlState.lastTargetArmour or 0
                            local lastH       = damageControlState.lastTargetHealth or 0
                            local armourAfter = math.max(0, lastA - total)
                            local remaining   = math.max(0, total - lastA)
                            local healthAfter = math.max(0, lastH - remaining)
                            SetPedArmour(damageControlState.targetPed, armourAfter)
                            SetEntityHealth(damageControlState.targetPed, healthAfter)
                            a = armourAfter
                            h = healthAfter
                        end
                        ClearEntityLastDamageEntity(damageControlState.targetPed)
                    end
                end

                damageControlState.lastTargetHealth = h
                damageControlState.lastTargetArmour = a
            end

            if IsControlJustPressed(0, CTRL_INC) then
                damageControlState.currentModifier = clamp(damageControlState.currentModifier + damageControlState.step,
                    damageControlState.minModifier, damageControlState.maxModifier)
                applyDamageModifier(weaponHash, damageControlState.currentModifier)
                updateNUI(damageControlState.currentModifier)
            elseif IsControlJustPressed(0, CTRL_DEC) then
                damageControlState.currentModifier = clamp(damageControlState.currentModifier - damageControlState.step,
                    damageControlState.minModifier, damageControlState.maxModifier)
                applyDamageModifier(weaponHash, damageControlState.currentModifier)
                updateNUI(damageControlState.currentModifier)
            elseif IsDisabledControlJustPressed(0, CTRL_TOGGLE) or IsControlJustPressed(0, CTRL_TOGGLE) then
                damageControlState.headshotFixed150 = not damageControlState.headshotFixed150
                SendNUIMessage({ type = 'setHeadshotFix', value = damageControlState.headshotFixed150 })
                chat('Damage',
                    ('Headshot -150 (Armour first): %s'):format(damageControlState.headshotFixed150 and 'ON' or 'OFF'))
                TriggerServerEvent('peleg:server:saveHeadshotFix', damageControlState.weaponHash,
                    damageControlState.headshotFixed150)
            elseif IsControlJustPressed(0, CTRL_SAVE_A) or IsControlJustPressed(0, CTRL_SAVE_B) then
                TriggerServerEvent('peleg:server:saveDamage', damageControlState.weaponHash,
                    damageControlState.currentModifier)
                TriggerServerEvent('peleg:server:saveHeadshotFix', damageControlState.weaponHash,
                    damageControlState.headshotFixed150)
                chat('Damage',
                    string.format('Saved damage modifier %.2f for %s', damageControlState.currentModifier,
                        damageControlState.weaponName))
                cleanupDamageControl()
            end
        end
    end)
end

RegisterNetEvent('peleg:client:syncRecoilData', function(data)
    recoilState.saved = data or {}
end)

RegisterNetEvent('peleg:client:syncDamageData', function(data)
    damageState.saved = data or {}
    for hashStr, value in pairs(damageState.saved) do
        local h = tonumber(hashStr)
        if h then applyDamageModifier(h, value) end
    end
end)

RegisterNetEvent('peleg:client:startRecoilControl', function(weaponName)
    if lib.callback.await('peleg:server:checkPermission', false) then
        startRecoilControl(weaponName)
    else
        TriggerEvent('chat:addMessage', { args = { 'Recoil', 'You do not have permission to use this feature.' } })
    end
end)

RegisterNetEvent('peleg:client:startDamageControl', function(weaponName)
    if lib.callback.await('peleg:server:checkPermission', false) then
        startDamageControl(weaponName)
    else
        TriggerEvent('chat:addMessage', { args = { 'Damage', 'You do not have permission to use this feature.' } })
    end
end)

RegisterNetEvent('peleg:client:syncHeadshotFix', function(data)
    headshotState.saved = data or {}
end)

RegisterNUICallback('peleg:client:saveRecoil', function(_, cb)
    if controlState.active then
        local ped = cache.ped
        TriggerServerEvent('peleg:server:saveRecoil', controlState.weaponHash, controlState.currentModifier)
        controlState.active = false
        hideNUI()
        RemoveWeaponFromPed(ped, controlState.weaponHash)
        restoreWeapon(controlState)
        chat('Recoil',
            string.format('Saved recoil modifier %.2f for %s', controlState.currentModifier, controlState.weaponName))
    end
    if cb then cb('ok') end
end)

RegisterNUICallback('peleg:client:saveDamage', function(_, cb)
    if damageControlState.active then
        TriggerServerEvent('peleg:server:saveDamage', damageControlState.weaponHash, damageControlState.currentModifier)
        cleanupDamageControl()
    end
    if cb then cb('ok') end
end)

RegisterNUICallback('peleg:client:toggleHeadshotFix', function(_, cb)
    if damageControlState.active then
        damageControlState.headshotFixed150 = not damageControlState.headshotFixed150
        SendNUIMessage({ type = 'setHeadshotFix', value = damageControlState.headshotFixed150 })
        TriggerServerEvent('peleg:server:saveHeadshotFix', damageControlState.weaponHash,
            damageControlState.headshotFixed150)
    end
    if cb then cb('ok') end
end)

CreateThread(function()
    TriggerServerEvent('peleg:server:requestRecoilData')
    TriggerServerEvent('peleg:server:requestDamageData')
    TriggerServerEvent('peleg:server:requestHeadshotFix')
    TriggerServerEvent('peleg:server:requestPermission')
end)



