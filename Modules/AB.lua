-- HonorLog Arathi Basin Module

local ADDON_NAME, HonorLog = ...

HonorLog.BattlegroundBase:New("AB", {
    displayName = "Arathi Basin",
    shortName = "AB",
    mapID = 529,
    markItem = 20559,
    objectives = { "Bases Assaulted", "Bases Defended" },
})
