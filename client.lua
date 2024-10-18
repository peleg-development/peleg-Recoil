local playerPed = PlayerPedId()
local function CalculateAmplitudeScale(num, baseMin, baseMax, targetMin, targetMax)
    return (((num - baseMin) * (targetMax - targetMin)) / (baseMax - baseMin)) + targetMin
end

function ApplyRecoilBasedOnStateOrSpeed(ped, weapon, modifier)
    local amplitude = 1.0

    local pedSpeed = GetEntitySpeed(ped)

    local weaponData = Config.weaponRecoilValues[weapon] or { recoil = 3.5, type = "generic" }
    local weaponRecoil = weaponData.recoil
    local weaponType = weaponData.type

    local weaponTypeModifier = Config.weaponTypeModifiers[weaponType] or 1.0

    local movementModifier = Config.movementModifiers.still
    if IsPedRunning(ped) then
        movementModifier = Config.movementModifiers.running
    elseif IsPedWalking(ped) then
        movementModifier = Config.movementModifiers.walking
    end

    amplitude = CalculateAmplitudeScale(pedSpeed, 0.0, 150.0, 1.0, 8.0) * Config.modelWeights.playerSpeedWeight
    amplitude = amplitude + CalculateAmplitudeScale(weaponRecoil, 0.0, 10.0, 1.0, 5.0) * Config.modelWeights.weaponRecoilWeight

    -- Adjusting based on aim mode
    if IsPlayerFreeAiming(PlayerId()) then
        amplitude = amplitude * Config.modelWeights.aimModeWeight 
    end

    amplitude = amplitude * weaponTypeModifier * movementModifier * modifier

    SetWeaponRecoilShakeAmplitude(weapon, amplitude)
end

CreateThread(function()
    while true do
        Wait(150)

        local ped = PlayerPedId()
        if IsPedArmed(ped, 6) then
            local _, currentWeapon = GetCurrentPedWeapon(ped, true)
            ApplyRecoilBasedOnStateOrSpeed(ped, currentWeapon, 1.0)
        end
    end
end)
