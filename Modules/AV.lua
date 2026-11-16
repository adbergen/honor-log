-- HonorLog Alterac Valley Module
-- AV: the winner is the side whose general survives.

local ADDON_NAME, HonorLog = ...

local AV = HonorLog.BattlegroundBase:New("AV", {
    displayName = "Alterac Valley",
    shortName = "AV",
    mapID = 30,
    markItem = 20560,
    objectives = { "Graveyards Assaulted", "Graveyards Defended", "Towers Assaulted", "Towers Defended" },
})

local base = HonorLog.BattlegroundBase

function AV:DetectWin(msg)
    local faction = base.DetectWin(self, msg)
    if faction then return faction end
    local lower = msg:lower()
    local general = lower:find("slain", 1, true) or lower:find("dead", 1, true) or lower:find("killed", 1, true)
    if general and lower:find("drek'thar", 1, true) then return "Alliance" end
    if general and lower:find("vanndar", 1, true) then return "Horde" end
    return nil
end
