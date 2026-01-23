-- HonorLog Arathi Basin Module
-- AB-specific tracking and detection

local ADDON_NAME, HonorLog = ...

local AB = HonorLog.BattlegroundBase:New("AB", {
    displayName = "Arathi Basin",
    icon = "Interface\\Icons\\INV_Jewelry_Amulet_07",
    mapID = 529,
})

-- AB-specific win patterns
local WIN_PATTERNS = {
    ["The Alliance has won the battle for Arathi Basin!"] = "Alliance",
    ["The Horde has won the battle for Arathi Basin!"] = "Horde",
    ["The Alliance wins!"] = "Alliance",
    ["The Horde wins!"] = "Horde",
}

-- AB is resource-based: first to 1600 (or 2000 in some versions) wins
local WINNING_SCORE = 1600

function AB:DetectWin(msg)
    for pattern, faction in pairs(WIN_PATTERNS) do
        if msg:find(pattern) then
            return faction
        end
    end
    return nil
end

function AB:GetCurrentScore()
    -- Parse AB scoreboard for current resources
    -- This would require reading from the BG score frame
    local numScores = GetNumBattlefieldScores()
    if numScores > 0 then
        -- AB shows faction scores in specific UI elements
        -- For now, return nil - enhancement for future versions
    end
    return nil
end

function AB:CalculateBonusMarks(won, score)
    -- AB standard marks: 3 for win, 1 for loss
    return won and 3 or 1
end

-- AB bases
local BASES = {
    "Stables",
    "Blacksmith",
    "Lumber Mill",
    "Gold Mine",
    "Farm",
}

-- AB-specific stats we might want to track in the future
-- - Bases captured/defended
-- - Time with 5-cap
-- - Closest games (opponent score at win)
