Config = {}

-- Configurable weights and options
Config.modelWeights = {
    playerSpeedWeight = 0.5,   -- Default speed weight
    weaponRecoilWeight = 0.3,  -- Default weapon recoil weight
    aimModeWeight = 0.2,       -- Recoil adjustment for aiming modes (hipfire vs ADS)
}

-- Configurable weapon recoil values
Config.weaponRecoilValues = {
    [`weapon_pistol50`] = { recoil = 3.5, type = "pistol" },
    [`weapon_assaultrifle`] = { recoil = 5.0, type = "rifle" },
    -- Add more weapons here with their recoil and types
    -- [`new_weapon`] = { recoil = new_recoil_value, type = "weapon_type" },
}

-- Weapon type-based modifiers (can be tuned for realism)
Config.weaponTypeModifiers = {
    pistol = 1.0,
    rifle = 1.5,
    shotgun = 2.0,
    smg = 1.2,
}

-- Movement-based recoil modifiers
Config.movementModifiers = {
    still = 0.8,
    walking = 1.0,
    running = 1.2,
}
