---@diagnostic disable: undefined-global
local playerPed = PlayerPedId()

--- Persists and controls recoil tuning state.
local recoilState = { saved = {} }

--- Holds the current control session information.
local controlState = {
    active = false,
    weaponHash = nil,
    weaponName = nil,
    currentModifier = 1.0,
    minModifier = 0.0,
    maxModifier = 10.0,
    step = 0.05,
    originalWeapon = nil,
    originalAmmo = 0,
}

--- NUI state management
local nuiState = {
    visible = false,
    nuiId = nil
}

--- Returns the current recoil modifier for a weapon, applying live control when active.
--- @param weaponHash number
--- @return number
local function GetModifierForWeapon(weaponHash)
    if controlState.active and controlState.weaponHash == weaponHash then
        return controlState.currentModifier
    end
    local saved = recoilState.saved[tostring(weaponHash)]
    if type(saved) == 'number' then return saved end
    return 1.0
end


--- Shows the HTML NUI interface for recoil control.
--- @param modifier number
--- @param weaponName string
local function ShowNUI(modifier, weaponName)
    if not nuiState.visible then
        nuiState.visible = true
        nuiState.nuiId = SendNUIMessage({
            type = 'showUI',
            modifier = modifier,
            weaponName = weaponName
        })
    end
end

--- Hides the HTML NUI interface.
local function HideNUI()
    if nuiState.visible then
        nuiState.visible = false
        SendNUIMessage({
            type = 'hideUI'
        })
    end
end

--- Updates the modifier value in the NUI.
--- @param modifier number
local function UpdateNUI(modifier)
    if nuiState.visible then
        SendNUIMessage({
            type = 'updateModifier',
            modifier = modifier
        })
    end
end

--- Saves current modifier, cleans up session, restores weapon and hides UI.
local function SaveAndExit()
    local ped = PlayerPedId()
    TriggerServerEvent('peleg:server:saveRecoil', controlState.weaponHash, controlState.currentModifier)
    controlState.active = false
    HideNUI()
    RemoveWeaponFromPed(ped, controlState.weaponHash)
    if controlState.originalWeapon and controlState.originalWeapon ~= 0 then
        GiveWeaponToPed(ped, controlState.originalWeapon, controlState.originalAmmo, false, true)
        SetCurrentPedWeapon(ped, controlState.originalWeapon, true)
    else
        SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
    end
    TriggerEvent('chat:addMessage', {
        args = {'🎯 Recoil Control', string.format('Saved recoil modifier %.2f for %s', controlState.currentModifier, controlState.weaponName)}
    })
end

--- Starts the recoil control mode for a specific weapon.
--- @param weaponName string
local function StartControlMode(weaponName)
    local ped = PlayerPedId()
    local weaponHash = GetHashKey(weaponName)
    
    -- Store original weapon state
    local _, originalWeapon = GetCurrentPedWeapon(ped, true)
    local originalAmmo = GetAmmoInPedWeapon(ped, originalWeapon)
    
    controlState.active = true
    controlState.weaponName = weaponName
    controlState.weaponHash = weaponHash
    controlState.currentModifier = recoilState.saved[tostring(weaponHash)] or 1.0
    controlState.originalWeapon = originalWeapon
    controlState.originalAmmo = originalAmmo

    -- Give test weapon
    GiveWeaponToPed(ped, weaponHash, 9999, false, true)
    SetCurrentPedWeapon(ped, weaponHash, true)
    SetPedInfiniteAmmo(ped, true, weaponHash)
    SetPedInfiniteAmmoClip(ped, true)

    -- Show NUI interface
    ShowNUI(controlState.currentModifier, weaponName)

    CreateThread(function()
        while controlState.active do
            Wait(0)

            if IsPedArmed(ped, 6) then
                local _, currentWeapon = GetCurrentPedWeapon(ped, true)
                if currentWeapon == weaponHash then
                    SetPedInfiniteAmmo(ped, true, weaponHash)
                    SetPedInfiniteAmmoClip(ped, true)
                end
            end

            if IsControlJustPressed(0, 172) then
                controlState.currentModifier = math.min(controlState.currentModifier + controlState.step, controlState.maxModifier)
                UpdateNUI(controlState.currentModifier)
            elseif IsControlJustPressed(0, 173) then
                controlState.currentModifier = math.max(controlState.currentModifier - controlState.step, controlState.minModifier)
                UpdateNUI(controlState.currentModifier)
            elseif IsControlJustPressed(0, 170) or IsControlJustPressed(0, 191) then -- F3 to save
                SaveAndExit()
            end
        end
    end)
end

CreateThread(function()
    while true do
        Wait(0)

        local ped = PlayerPedId()
        if IsPedArmed(ped, 6) then
            local _, currentWeapon = GetCurrentPedWeapon(ped, true)
            local modifier = GetModifierForWeapon(currentWeapon)
            SetWeaponRecoilShakeAmplitude(currentWeapon, modifier)
        end
    end
end)

RegisterNetEvent('peleg:client:syncRecoilData', function(data)
    recoilState.saved = data or {}
end)

RegisterNetEvent('peleg:client:startRecoilControl', function(weaponName)
    StartControlMode(weaponName)
end)

--- NUI Callback for saving recoil
RegisterNUICallback('peleg:client:saveRecoil', function(data, cb)
    if controlState.active then
        local ped = PlayerPedId()
        
        -- Save and exit
        TriggerServerEvent('peleg:server:saveRecoil', controlState.weaponHash, controlState.currentModifier)
        controlState.active = false
        
        -- Hide NUI
        HideNUI()
        
        -- Remove test weapon completely
        RemoveWeaponFromPed(ped, controlState.weaponHash)
        
        -- Restore original weapon if it exists
        if controlState.originalWeapon and controlState.originalWeapon ~= 0 then
            GiveWeaponToPed(ped, controlState.originalWeapon, controlState.originalAmmo, false, true)
            SetCurrentPedWeapon(ped, controlState.originalWeapon, true)
        else
            -- If no original weapon, set to unarmed
            SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
        end
        
        -- Show save confirmation
        TriggerEvent('chat:addMessage', {
            args = {'🎯 Recoil Control', string.format('Saved recoil modifier %.2f for %s', controlState.currentModifier, controlState.weaponName)}
        })
    end
    
    if cb then cb('ok') end
end)

CreateThread(function()
    TriggerServerEvent('peleg:server:requestRecoilData')
end)
