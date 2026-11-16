-- HonorLog Battleground Registry
-- One module per Forever battleground, keyed by the instance map id (the 8th
-- return of GetInstanceInfo), which is the same in every client language.
-- Colours live in UI/Theme.lua; each module carries its names, mark item and
-- the labels of its scoreboard objective columns.

local ADDON_NAME, HonorLog = ...

HonorLog.Battlegrounds = HonorLog.Battlegrounds or {} -- bgType -> module
HonorLog.BG_BY_MAP = HonorLog.BG_BY_MAP or {}         -- instance map id -> bgType
HonorLog.BG_MARK_ITEMS = HonorLog.BG_MARK_ITEMS or {} -- bgType -> mark item id

local BattlegroundBase = {}
BattlegroundBase.__index = BattlegroundBase

-- Win text the client prints in the BG system channels. Only the fallback for a
-- match whose PVP_MATCH_COMPLETE payload and winner APIs gave nothing usable.
local GENERIC_WIN = {
    ["the alliance wins"] = "Alliance",
    ["the horde wins"] = "Horde",
    ["alliance wins"] = "Alliance",
    ["horde wins"] = "Horde",
    ["alliance victory"] = "Alliance",
    ["horde victory"] = "Horde",
    ["alliance has won the battle"] = "Alliance",
    ["horde has won the battle"] = "Horde",
}

-- config: displayName, shortName, mapID, markItem, objectives (labels, in display order)
function BattlegroundBase:New(bgType, config)
    local instance = setmetatable({}, BattlegroundBase)
    instance.bgType = bgType
    instance.config = config or {}
    instance.enabled = true

    HonorLog.Battlegrounds[bgType] = instance
    if instance.config.mapID then HonorLog.BG_BY_MAP[instance.config.mapID] = bgType end
    if instance.config.markItem then HonorLog.BG_MARK_ITEMS[bgType] = instance.config.markItem end
    return instance
end

-- Returns "Alliance", "Horde" or nil for one BG system message.
function BattlegroundBase:DetectWin(msg)
    local lower = msg:lower()
    for pattern, faction in pairs(GENERIC_WIN) do
        if lower:find(pattern, 1, true) then return faction end
    end
    return nil
end

function BattlegroundBase:GetDisplayName() return self.config.displayName or self.bgType end
function BattlegroundBase:GetShortName() return self.config.shortName or self.bgType end
function BattlegroundBase:GetMarkItem() return self.config.markItem end
function BattlegroundBase:GetObjectiveLabels() return self.config.objectives or {} end
function BattlegroundBase:IsEnabled() return self.enabled end
function BattlegroundBase:SetEnabled(enabled) self.enabled = enabled end

HonorLog.BattlegroundBase = BattlegroundBase

function HonorLog:GetBattlegroundModule(bgType)
    return self.Battlegrounds[bgType]
end

-- The bgType for an instance map id. An unknown map in a "pvp" instance gets a
-- generic "MAP<id>" entry named from GetInstanceInfo, so a battleground that
-- opens later is tracked from its first game.
function HonorLog:GetBGTypeForMap(mapID, instanceName, instanceType)
    if not mapID then return nil end
    local known = self.BG_BY_MAP[mapID]
    if known then return known end
    if instanceType ~= "pvp" then return nil end
    local bgType = "MAP" .. mapID
    if not self.Battlegrounds[bgType] then
        BattlegroundBase:New(bgType, {
            displayName = instanceName or bgType,
            shortName = instanceName or bgType,
            mapID = mapID,
            objectives = {},
            generic = true,
        })
    end
    return bgType
end

-- Display name for any bgType, including the TBC history key and generic maps.
function HonorLog:GetBGDisplayName(bgType)
    if bgType == "EotS" then return "Eye of the Storm (TBC)" end
    local module = self.Battlegrounds[bgType]
    if module then return module:GetDisplayName() end
    return tostring(bgType)
end

function HonorLog:GetBGShortName(bgType)
    if bgType == "EotS" then return "EotS" end
    local module = self.Battlegrounds[bgType]
    if module then return module:GetShortName() end
    return tostring(bgType)
end

-- All registered battlegrounds (generic ones included), tracked order first.
function HonorLog:GetAllBattlegrounds()
    local bgs, seen = {}, {}
    for _, bgType in ipairs(self.BG_ORDER or {}) do
        if self.Battlegrounds[bgType] then bgs[#bgs + 1] = bgType; seen[bgType] = true end
    end
    local extra = {}
    for bgType, module in pairs(self.Battlegrounds) do
        if not seen[bgType] and module:IsEnabled() then extra[#extra + 1] = bgType end
    end
    table.sort(extra)
    for _, bgType in ipairs(extra) do bgs[#bgs + 1] = bgType end
    return bgs
end
