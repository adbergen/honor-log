-- HonorLog Alterac Valley Module
-- AV-specific tracking and detection

local ADDON_NAME, HonorLog = ...

local AV = HonorLog.BattlegroundBase:New("AV", {
    displayName = "Alterac Valley",
    icon = "Interface\\Icons\\INV_Jewelry_Necklace_21",
    mapID = 30,
})

-- AV-specific win patterns
local WIN_PATTERNS = {
    ["The Alliance wins!"] = "Alliance",
    ["The Horde wins!"] = "Horde",
    ["Alterac Valley"] = nil, -- Generic, needs more context
}

-- AV has reinforcement-based victory
-- Alliance starts at 600 reinforcements, Horde at 600
-- First to 0 or kill General loses

function AV:DetectWin(msg)
    for pattern, faction in pairs(WIN_PATTERNS) do
        if msg:find(pattern) and faction then
            return faction
        end
    end

    -- Check for general kill messages
    if msg:find("Drek'Thar") and msg:find("slain") then
        return "Alliance"
    elseif msg:find("Vanndar Stormpike") and msg:find("slain") then
        return "Horde"
    end

    return nil
end

function AV:GetCurrentScore()
    -- AV tracks reinforcements, not a simple score
    -- This would require parsing the BG scoreboard
    return nil
end

function AV:CalculateBonusMarks(won, score)
    -- AV gives 3 marks for win, 1 for loss (standard)
    return won and 3 or 1
end

-- AV-specific stats we might want to track in the future
-- - Towers captured/defended
-- - Graveyards captured
-- - Captain/Lieutenant kills
-- - Mine captures
