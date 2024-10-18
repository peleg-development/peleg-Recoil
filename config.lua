local function CalculateAmplitudeScale(num, baseMin, baseMax, targetMin, targetMax)
    return (((num - baseMin) * (targetMax - targetMin)) / (baseMax - baseMin)) + targetMin
end

-- Function to calculate and apply recoil based on multiple conditions
function ApplyRecoilBasedOnStateOrSpeed(ped, weapon, modifier)
    local amplitude = 1.0

    -- Simulating player speed as a feature
    local pedSpeed = GetEntitySpeed(ped)

    -- Get the weapon recoil value and type
    local weaponData = Config.weaponRecoilValues[weapon] or { recoil = 3.5, type = "generic" }
    local weaponRecoil = weaponData.recoil
    local weaponType = weaponData.type

    -- Get weapon type modifier
    local weaponTypeModifier = Config.weaponTypeModifiers[weaponType] or 1.0

    -- Calculate movement-based recoil modifier
    local movementModifier = Config.movementModifiers.still
    if IsPedRunning(ped) then
        movementModifier = Config.movementModifiers.running
    elseif IsPedWalking(ped) then
        movementModifier = Config.movementModifiers.walking
    end

    -- Simulating "machine learning" model decision-making
    amplitude = CalculateAmplitudeScale(pedSpeed, 0.0, 150.0, 1.0, 8.0) * Config.modelWeights.playerSpeedWeight
    amplitude = amplitude + CalculateAmplitudeScale(weaponRecoil, 0.0, 10.0, 1.0, 5.0) * Config.modelWeights.weaponRecoilWeight

    -- Adjusting based on aim mode
    if IsPlayerFreeAiming(PlayerId()) then
        amplitude = amplitude * Config.modelWeights.aimModeWeight -- Less recoil while aiming
    end

    -- Final adjustment with weapon type modifier and movement modifier
    amplitude = amplitude * weaponTypeModifier * movementModifier * modifier

    -- Apply the calculated recoil amplitude
    SetWeaponRecoilShakeAmplitude(weapon, amplitude)
end

-- Thread to continuously apply the recoil system
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
