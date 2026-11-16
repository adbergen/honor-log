-- HonorLog Darkspear Islands Module
-- Forever's fourth battleground (map 2997). Its mark is item 274895.

local ADDON_NAME, HonorLog = ...

HonorLog.BattlegroundBase:New("DI", {
    displayName = "Darkspear Islands",
    shortName = "DI",
    mapID = 2997,
    markItem = 274895,
    objectives = { "Flag Captures", "Bases Assaulted", "Bases Defended" },
})
