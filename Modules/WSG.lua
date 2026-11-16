-- HonorLog Warsong Gulch Module

local ADDON_NAME, HonorLog = ...

HonorLog.BattlegroundBase:New("WSG", {
    displayName = "Warsong Gulch",
    shortName = "WSG",
    mapID = 489,
    markItem = 20558,
    objectives = { "Flag Captures", "Flag Returns" },
})
