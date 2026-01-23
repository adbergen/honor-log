-- HonorLog Warsong Gulch Module
-- WSG-specific tracking and detection

local ADDON_NAME, HonorLog = ...

local WSG = HonorLog.BattlegroundBase:New("WSG", {
    displayName = "Warsong Gulch",
    icon = "Interface\\Icons\\INV_Misc_Rune_07",
    mapID = 489,
})

-- WSG-specific win patterns
local WIN_PATTERNS = {
    ["The Alliance has won the battle for Warsong Gulch!"] = "Alliance",
    ["The Horde has won the battle for Warsong Gulch!"] = "Horde",
    ["The Alliance wins!"] = "Alliance",
    ["The Horde wins!"] = "Horde",
    ["Alliance wins!"] = "Alliance",
    ["Horde wins!"] = "Horde",
}

-- WSG is capture-based: first to 3 flag captures wins
local WINNING_SCORE = 3

function WSG:DetectWin(msg)
    for pattern, faction in pairs(WIN_PATTERNS) do
        if msg:find(pattern) then
            return faction
        end
    end
    return nil
end

function WSG:GetCurrentScore()
    -- WSG tracks flag captures
    -- This requires parsing the BG UI
    return nil
end

function WSG:CalculateBonusMarks(won, score)
    -- WSG standard marks: 3 for win, 1 for loss
    return won and 3 or 1
end

-- WSG-specific messages
local WSG_MESSAGES = {
    -- Flag pickup
    ["captured the"] = "flag_capture",
    ["picked up the"] = "flag_pickup",
    ["dropped the"] = "flag_drop",
    ["returned the"] = "flag_return",
}

-- WSG-specific stats we might want to track in the future
-- - Flag captures
-- - Flag returns
-- - Flag carrier kills
-- - Time holding flag
