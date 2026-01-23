-- HonorLog Eye of the Storm Module
-- EotS-specific tracking and detection
-- NOTE: This module is prepared but disabled by default for BCC initial release

local ADDON_NAME, HonorLog = ...

local EotS = HonorLog.BattlegroundBase:New("EotS", {
    displayName = "Eye of the Storm",
    icon = "Interface\\Icons\\Spell_Nature_EyeOfTheStorm",
    mapID = 566,
})

-- Disable EotS by default until it's needed
-- Enable via: HonorLog.Battlegrounds.EotS:SetEnabled(true)
EotS:SetEnabled(false)

-- EotS-specific win patterns
local WIN_PATTERNS = {
    ["The Alliance has won the battle for Eye of the Storm!"] = "Alliance",
    ["The Horde has won the battle for Eye of the Storm!"] = "Horde",
    ["The Alliance wins!"] = "Alliance",
    ["The Horde wins!"] = "Horde",
}

-- EotS is a hybrid: points from bases + flag captures
-- First to 1600 (or 2000 in some versions) wins
local WINNING_SCORE = 1600

function EotS:DetectWin(msg)
    if not self:IsEnabled() then return nil end

    for pattern, faction in pairs(WIN_PATTERNS) do
        if msg:find(pattern) then
            return faction
        end
    end
    return nil
end

function EotS:GetCurrentScore()
    if not self:IsEnabled() then return nil end
    -- EotS tracks resources similar to AB
    return nil
end

function EotS:CalculateBonusMarks(won, score)
    -- EotS standard marks: 3 for win, 1 for loss
    return won and 3 or 1
end

-- EotS towers/bases
local TOWERS = {
    "Mage Tower",
    "Draenei Ruins",
    "Blood Elf Tower",
    "Fel Reaver Ruins",
}

-- EotS-specific stats we might want to track in the future
-- - Towers captured/defended
-- - Flag captures (center flag)
-- - Points from bases vs flags
