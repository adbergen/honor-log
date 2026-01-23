-- HonorLog Battleground Base Module
-- Shared functionality for all battleground modules

local ADDON_NAME, HonorLog = ...

HonorLog.Battlegrounds = HonorLog.Battlegrounds or {}

-- Base battleground module class
local BattlegroundBase = {}
BattlegroundBase.__index = BattlegroundBase

function BattlegroundBase:New(bgType, config)
    local instance = setmetatable({}, BattlegroundBase)
    instance.bgType = bgType
    instance.config = config or {}
    instance.enabled = true

    -- Register this module
    HonorLog.Battlegrounds[bgType] = instance

    return instance
end

-- Override in subclasses for BG-specific win detection
function BattlegroundBase:DetectWin(msg)
    -- Default implementation - subclasses can override
    return nil
end

-- Override in subclasses for BG-specific score tracking
function BattlegroundBase:GetCurrentScore()
    -- Returns { alliance = score, horde = score } or nil
    return nil
end

-- Override in subclasses for BG-specific bonus calculations
function BattlegroundBase:CalculateBonusMarks(won, score)
    -- Default: 3 marks for win, 1 for loss
    return won and 3 or 1
end

-- Get BG display name
function BattlegroundBase:GetDisplayName()
    return self.config.displayName or self.bgType
end

-- Get BG icon
function BattlegroundBase:GetIcon()
    return self.config.icon
end

-- Check if this BG module is enabled
function BattlegroundBase:IsEnabled()
    return self.enabled
end

-- Enable/disable this BG module
function BattlegroundBase:SetEnabled(enabled)
    self.enabled = enabled
end

HonorLog.BattlegroundBase = BattlegroundBase

-- Utility function to get the module for a BG type
function HonorLog:GetBattlegroundModule(bgType)
    return self.Battlegrounds[bgType]
end

-- Get all registered battlegrounds
function HonorLog:GetAllBattlegrounds()
    local bgs = {}
    for bgType, module in pairs(self.Battlegrounds) do
        if module:IsEnabled() then
            table.insert(bgs, bgType)
        end
    end
    table.sort(bgs)
    return bgs
end
