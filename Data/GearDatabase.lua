-- HonorLog Gear Database
-- TBC Classic PvP gear with VERIFIED itemIDs from Wowhead
-- Last updated: 2025-01-24

local ADDON_NAME, HonorLog = ...

-- Slot constants for filtering
HonorLog.SLOTS = {
    "HEAD", "NECK", "SHOULDER", "BACK", "CHEST",
    "WRIST", "HANDS", "WAIST", "LEGS", "FEET",
    "FINGER", "TRINKET", "MAIN_HAND", "OFF_HAND",
    "TWO_HAND", "RANGED", "RELIC"
}

-- Class constants
HonorLog.CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID"
}

-- Arena season constants
HonorLog.SEASONS = {
    S1 = "Gladiator",
    S2 = "Merciless Gladiator",
    S3 = "Vengeful Gladiator",
    S4 = "Brutal Gladiator",
    PREPATCH = "Prepatch",
}

-- Archived seasons (not yet available in game)
-- TBC Anniversary: Only prepatch gear is available initially
-- When TBC releases, move seasons from ARCHIVED to ACTIVE
HonorLog.ARCHIVED_SEASONS = {
    S1 = true,  -- Gladiator gear - unlocks with TBC Arena Season 1
    S2 = true,  -- Merciless Gladiator - unlocks with Arena Season 2
    S3 = true,  -- Vengeful Gladiator - unlocks with Arena Season 3
    S4 = true,  -- Brutal Gladiator - unlocks with Arena Season 4
}

-- Check if a season is currently available
function HonorLog:IsSeasonAvailable(season)
    if not season then return true end  -- nil season = honor gear, always available
    return not self.ARCHIVED_SEASONS[season]
end

-- Check if an item is currently available
function HonorLog:IsItemAvailable(itemID)
    local item = self.GearDB[itemID]
    if not item then return false end
    return self:IsSeasonAvailable(item.season)
end

-- Mark of Honor item IDs (verified)
HonorLog.MARK_ITEMS = {
    AV = 20560,   -- Alterac Valley Mark of Honor
    AB = 20559,   -- Arathi Basin Mark of Honor
    WSG = 20558,  -- Warsong Gulch Mark of Honor
    EotS = 29024, -- Eye of the Storm Mark of Honor
}

-- Gear Database
-- Format: [itemID] = { slot, class, honor, arena, marks, season, name }
-- marks = { AV = n, AB = n, WSG = n, EotS = n } or nil if no marks required
-- class = nil means any class can use
-- season = nil for non-arena items
--
-- IMPORTANT: All itemIDs verified from Wowhead TBC Classic database

HonorLog.GearDB = {
    --[[
    ============================================================================
    SEASON 1 - GLADIATOR GEAR (Arena Points)
    Verified from: https://www.wowhead.com/tbc/item-set=XXX
    ============================================================================
    --]]

    -- WARRIOR - Gladiator's Battlegear (Set 567)
    [24544] = { slot = "CHEST", class = "WARRIOR", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Plate Chestpiece" },
    [24545] = { slot = "HEAD", class = "WARRIOR", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Plate Helm" },
    [24546] = { slot = "SHOULDER", class = "WARRIOR", honor = 11250, arena = 1500, marks = nil, season = "S1", name = "Gladiator's Plate Shoulders" },
    [24547] = { slot = "LEGS", class = "WARRIOR", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Plate Legguards" },
    [24549] = { slot = "HANDS", class = "WARRIOR", honor = 10500, arena = 1125, marks = nil, season = "S1", name = "Gladiator's Plate Gauntlets" },

    -- PALADIN - Gladiator's Aegis (Set 582) - Holy/Protection
    [27702] = { slot = "CHEST", class = "PALADIN", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Lamellar Chestpiece" },
    [27703] = { slot = "HANDS", class = "PALADIN", honor = 10500, arena = 1125, marks = nil, season = "S1", name = "Gladiator's Lamellar Gauntlets" },
    [27704] = { slot = "HEAD", class = "PALADIN", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Lamellar Helm" },
    [27705] = { slot = "LEGS", class = "PALADIN", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Lamellar Legguards" },
    [27706] = { slot = "SHOULDER", class = "PALADIN", honor = 11250, arena = 1500, marks = nil, season = "S1", name = "Gladiator's Lamellar Shoulders" },

    -- HUNTER - Gladiator's Pursuit (Set 586)
    [28331] = { slot = "HEAD", class = "HUNTER", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Chain Helm" },
    [28332] = { slot = "LEGS", class = "HUNTER", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Chain Leggings" },
    [28333] = { slot = "SHOULDER", class = "HUNTER", honor = 11250, arena = 1500, marks = nil, season = "S1", name = "Gladiator's Chain Spaulders" },
    [28334] = { slot = "CHEST", class = "HUNTER", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Chain Armor" },
    [28335] = { slot = "HANDS", class = "HUNTER", honor = 10500, arena = 1125, marks = nil, season = "S1", name = "Gladiator's Chain Gauntlets" },

    -- ROGUE - Gladiator's Vestments (Set 577)
    [25830] = { slot = "HEAD", class = "ROGUE", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Leather Helm" },
    [25831] = { slot = "CHEST", class = "ROGUE", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Leather Tunic" },
    [25832] = { slot = "SHOULDER", class = "ROGUE", honor = 11250, arena = 1500, marks = nil, season = "S1", name = "Gladiator's Leather Spaulders" },
    [25833] = { slot = "LEGS", class = "ROGUE", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Leather Legguards" },
    [25834] = { slot = "HANDS", class = "ROGUE", honor = 10500, arena = 1125, marks = nil, season = "S1", name = "Gladiator's Leather Gloves" },

    -- PRIEST - Gladiator's Raiment (Set 581)
    [27707] = { slot = "HANDS", class = "PRIEST", honor = 10500, arena = 1125, marks = nil, season = "S1", name = "Gladiator's Satin Gloves" },
    [27708] = { slot = "HEAD", class = "PRIEST", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Satin Hood" },
    [27709] = { slot = "LEGS", class = "PRIEST", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Satin Leggings" },
    [27710] = { slot = "SHOULDER", class = "PRIEST", honor = 11250, arena = 1500, marks = nil, season = "S1", name = "Gladiator's Satin Mantle" },
    [27711] = { slot = "CHEST", class = "PRIEST", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Satin Robe" },

    -- SHAMAN - Gladiator's Earthshaker (Set 578) - Enhancement
    [25997] = { slot = "CHEST", class = "SHAMAN", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Linked Armor" },
    [25998] = { slot = "HEAD", class = "SHAMAN", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Linked Helm" },
    [25999] = { slot = "SHOULDER", class = "SHAMAN", honor = 11250, arena = 1500, marks = nil, season = "S1", name = "Gladiator's Linked Spaulders" },
    [26000] = { slot = "HANDS", class = "SHAMAN", honor = 10500, arena = 1125, marks = nil, season = "S1", name = "Gladiator's Linked Gauntlets" },
    [26001] = { slot = "LEGS", class = "SHAMAN", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Linked Leggings" },

    -- MAGE - Gladiator's Regalia (Set 579)
    [25854] = { slot = "SHOULDER", class = "MAGE", honor = 11250, arena = 1500, marks = nil, season = "S1", name = "Gladiator's Silk Amice" },
    [25855] = { slot = "HEAD", class = "MAGE", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Silk Cowl" },
    [25856] = { slot = "CHEST", class = "MAGE", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Silk Raiment" },
    [25857] = { slot = "HANDS", class = "MAGE", honor = 10500, arena = 1125, marks = nil, season = "S1", name = "Gladiator's Silk Handguards" },
    [25858] = { slot = "LEGS", class = "MAGE", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Silk Trousers" },

    -- WARLOCK - Gladiator's Dreadgear (Set 568)
    [24552] = { slot = "CHEST", class = "WARLOCK", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Dreadweave Robe" },
    [24553] = { slot = "HEAD", class = "WARLOCK", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Dreadweave Hood" },
    [24554] = { slot = "SHOULDER", class = "WARLOCK", honor = 11250, arena = 1500, marks = nil, season = "S1", name = "Gladiator's Dreadweave Mantle" },
    [24555] = { slot = "LEGS", class = "WARLOCK", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Dreadweave Leggings" },
    [24556] = { slot = "HANDS", class = "WARLOCK", honor = 10500, arena = 1125, marks = nil, season = "S1", name = "Gladiator's Dreadweave Gloves" },

    -- DRUID - Gladiator's Sanctuary (Set 584) - Feral
    [28126] = { slot = "HANDS", class = "DRUID", honor = 10500, arena = 1125, marks = nil, season = "S1", name = "Gladiator's Dragonhide Gloves" },
    [28127] = { slot = "HEAD", class = "DRUID", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Dragonhide Helm" },
    [28128] = { slot = "LEGS", class = "DRUID", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Dragonhide Legguards" },
    [28129] = { slot = "SHOULDER", class = "DRUID", honor = 11250, arena = 1500, marks = nil, season = "S1", name = "Gladiator's Dragonhide Spaulders" },
    [28130] = { slot = "CHEST", class = "DRUID", honor = 14500, arena = 1875, marks = nil, season = "S1", name = "Gladiator's Dragonhide Tunic" },

    --[[
    ============================================================================
    SEASON 2 - MERCILESS GLADIATOR GEAR (Arena Points)
    Verified itemIDs from Wowhead searches
    ============================================================================
    --]]

    -- WARRIOR - Merciless Gladiator's Plate
    [30486] = { slot = "CHEST", class = "WARRIOR", honor = 14500, arena = 1875, marks = nil, season = "S2", name = "Merciless Gladiator's Plate Chestpiece" },
    [30488] = { slot = "HEAD", class = "WARRIOR", honor = 14500, arena = 1875, marks = nil, season = "S2", name = "Merciless Gladiator's Plate Helm" },
    [30489] = { slot = "LEGS", class = "WARRIOR", honor = 14500, arena = 1875, marks = nil, season = "S2", name = "Merciless Gladiator's Plate Legguards" },
    [30490] = { slot = "SHOULDER", class = "WARRIOR", honor = 11250, arena = 1500, marks = nil, season = "S2", name = "Merciless Gladiator's Plate Shoulders" },
    [30487] = { slot = "HANDS", class = "WARRIOR", honor = 10500, arena = 1125, marks = nil, season = "S2", name = "Merciless Gladiator's Plate Gauntlets" },

    -- MAGE - Merciless Gladiator's Silk
    [32047] = { slot = "SHOULDER", class = "MAGE", honor = 11250, arena = 1500, marks = nil, season = "S2", name = "Merciless Gladiator's Silk Amice" },
    [32048] = { slot = "HEAD", class = "MAGE", honor = 14500, arena = 1875, marks = nil, season = "S2", name = "Merciless Gladiator's Silk Cowl" },
    [32049] = { slot = "HANDS", class = "MAGE", honor = 10500, arena = 1125, marks = nil, season = "S2", name = "Merciless Gladiator's Silk Handguards" },
    [32050] = { slot = "CHEST", class = "MAGE", honor = 14500, arena = 1875, marks = nil, season = "S2", name = "Merciless Gladiator's Silk Raiment" },
    [32051] = { slot = "LEGS", class = "MAGE", honor = 14500, arena = 1875, marks = nil, season = "S2", name = "Merciless Gladiator's Silk Trousers" },

    --[[
    ============================================================================
    SEASON 3 - VENGEFUL GLADIATOR GEAR (Arena Points)
    Verified from Wowhead search results
    ============================================================================
    --]]

    -- WARRIOR - Vengeful Gladiator's Plate
    [33728] = { slot = "CHEST", class = "WARRIOR", honor = 14500, arena = 1875, marks = nil, season = "S3", name = "Vengeful Gladiator's Plate Chestpiece" },
    [33729] = { slot = "HANDS", class = "WARRIOR", honor = 10500, arena = 1125, marks = nil, season = "S3", name = "Vengeful Gladiator's Plate Gauntlets" },
    [33730] = { slot = "HEAD", class = "WARRIOR", honor = 14500, arena = 1875, marks = nil, season = "S3", name = "Vengeful Gladiator's Plate Helm" },
    [33731] = { slot = "LEGS", class = "WARRIOR", honor = 14500, arena = 1875, marks = nil, season = "S3", name = "Vengeful Gladiator's Plate Legguards" },
    [33732] = { slot = "SHOULDER", class = "WARRIOR", honor = 11250, arena = 1500, marks = nil, season = "S3", name = "Vengeful Gladiator's Plate Shoulders" },

    -- MAGE - Vengeful Gladiator's Silk
    [33757] = { slot = "SHOULDER", class = "MAGE", honor = 11250, arena = 1500, marks = nil, season = "S3", name = "Vengeful Gladiator's Silk Amice" },
    [33758] = { slot = "HEAD", class = "MAGE", honor = 14500, arena = 1875, marks = nil, season = "S3", name = "Vengeful Gladiator's Silk Cowl" },
    [33759] = { slot = "HANDS", class = "MAGE", honor = 10500, arena = 1125, marks = nil, season = "S3", name = "Vengeful Gladiator's Silk Handguards" },
    [33760] = { slot = "CHEST", class = "MAGE", honor = 14500, arena = 1875, marks = nil, season = "S3", name = "Vengeful Gladiator's Silk Raiment" },
    [33761] = { slot = "LEGS", class = "MAGE", honor = 14500, arena = 1875, marks = nil, season = "S3", name = "Vengeful Gladiator's Silk Trousers" },

    --[[
    ============================================================================
    SEASON 4 - BRUTAL GLADIATOR GEAR (Arena Points)
    Verified from Wowhead search results
    ============================================================================
    --]]

    -- WARRIOR - Brutal Gladiator's Plate
    [35066] = { slot = "CHEST", class = "WARRIOR", honor = 14500, arena = 1875, marks = nil, season = "S4", name = "Brutal Gladiator's Plate Chestpiece" },
    [35067] = { slot = "HANDS", class = "WARRIOR", honor = 10500, arena = 1125, marks = nil, season = "S4", name = "Brutal Gladiator's Plate Gauntlets" },
    [35068] = { slot = "HEAD", class = "WARRIOR", honor = 14500, arena = 1875, marks = nil, season = "S4", name = "Brutal Gladiator's Plate Helm" },
    [35069] = { slot = "LEGS", class = "WARRIOR", honor = 14500, arena = 1875, marks = nil, season = "S4", name = "Brutal Gladiator's Plate Legguards" },
    [35070] = { slot = "SHOULDER", class = "WARRIOR", honor = 11250, arena = 1500, marks = nil, season = "S4", name = "Brutal Gladiator's Plate Shoulders" },

    -- MAGE - Brutal Gladiator's Silk
    [35096] = { slot = "SHOULDER", class = "MAGE", honor = 11250, arena = 1500, marks = nil, season = "S4", name = "Brutal Gladiator's Silk Amice" },
    [35097] = { slot = "HEAD", class = "MAGE", honor = 14500, arena = 1875, marks = nil, season = "S4", name = "Brutal Gladiator's Silk Cowl" },
    [35098] = { slot = "HANDS", class = "MAGE", honor = 10500, arena = 1125, marks = nil, season = "S4", name = "Brutal Gladiator's Silk Handguards" },
    [35099] = { slot = "CHEST", class = "MAGE", honor = 14500, arena = 1875, marks = nil, season = "S4", name = "Brutal Gladiator's Silk Raiment" },
    [35100] = { slot = "LEGS", class = "MAGE", honor = 14500, arena = 1875, marks = nil, season = "S4", name = "Brutal Gladiator's Silk Trousers" },

    --[[
    ============================================================================
    PREPATCH HONOR GEAR - High Warlord's Sets (Level 70 Rare PvP)
    Verified itemIDs from Wowhead TBC Classic
    Honor-only gear, no arena points required
    ============================================================================
    --]]

    -- WARRIOR - High Warlord's Battlegear (Plate)
    [28851] = { slot = "CHEST", class = "WARRIOR", honor = 14280, arena = 0, marks = { AB = 30 }, season = nil, name = "High Warlord's Plate Chestpiece" },
    [28852] = { slot = "HANDS", class = "WARRIOR", honor = 10360, arena = 0, marks = { AB = 20 }, season = nil, name = "High Warlord's Plate Gauntlets" },
    [28853] = { slot = "HEAD", class = "WARRIOR", honor = 14280, arena = 0, marks = { AV = 30 }, season = nil, name = "High Warlord's Plate Helm" },
    [28854] = { slot = "LEGS", class = "WARRIOR", honor = 14280, arena = 0, marks = { AB = 30 }, season = nil, name = "High Warlord's Plate Legguards" },
    [28855] = { slot = "SHOULDER", class = "WARRIOR", honor = 11424, arena = 0, marks = { AB = 20 }, season = nil, name = "High Warlord's Plate Shoulders" },

    -- PALADIN - High Warlord's Aegis (Lamellar Plate)
    [28831] = { slot = "CHEST", class = "PALADIN", honor = 14280, arena = 0, marks = { AB = 30 }, season = nil, name = "High Warlord's Lamellar Chestpiece" },
    [28832] = { slot = "HANDS", class = "PALADIN", honor = 10360, arena = 0, marks = { AB = 20 }, season = nil, name = "High Warlord's Lamellar Gauntlets" },
    [28833] = { slot = "HEAD", class = "PALADIN", honor = 14280, arena = 0, marks = { AV = 30 }, season = nil, name = "High Warlord's Lamellar Helm" },
    [28834] = { slot = "LEGS", class = "PALADIN", honor = 14280, arena = 0, marks = { AB = 30 }, season = nil, name = "High Warlord's Lamellar Legguards" },
    [28835] = { slot = "SHOULDER", class = "PALADIN", honor = 11424, arena = 0, marks = { AB = 20 }, season = nil, name = "High Warlord's Lamellar Shoulders" },

    -- HUNTER - High Warlord's Pursuit (Chain Mail)
    [28805] = { slot = "CHEST", class = "HUNTER", honor = 14280, arena = 0, marks = { AB = 30 }, season = nil, name = "High Warlord's Chain Armor" },
    [28806] = { slot = "HANDS", class = "HUNTER", honor = 10360, arena = 0, marks = { AB = 20 }, season = nil, name = "High Warlord's Chain Gauntlets" },
    [28807] = { slot = "HEAD", class = "HUNTER", honor = 14280, arena = 0, marks = { AV = 30 }, season = nil, name = "High Warlord's Chain Helm" },
    [28808] = { slot = "LEGS", class = "HUNTER", honor = 14280, arena = 0, marks = { AB = 30 }, season = nil, name = "High Warlord's Chain Leggings" },
    [28809] = { slot = "SHOULDER", class = "HUNTER", honor = 11424, arena = 0, marks = { AB = 20 }, season = nil, name = "High Warlord's Chain Spaulders" },

    -- SHAMAN - High Warlord's Earthshaker (Linked Mail)
    [28841] = { slot = "CHEST", class = "SHAMAN", honor = 14280, arena = 0, marks = { AB = 30 }, season = nil, name = "High Warlord's Linked Armor" },
    [28842] = { slot = "HANDS", class = "SHAMAN", honor = 10360, arena = 0, marks = { AB = 20 }, season = nil, name = "High Warlord's Linked Gauntlets" },
    [28843] = { slot = "HEAD", class = "SHAMAN", honor = 14280, arena = 0, marks = { AV = 30 }, season = nil, name = "High Warlord's Linked Helm" },
    [28844] = { slot = "LEGS", class = "SHAMAN", honor = 14280, arena = 0, marks = { AB = 30 }, season = nil, name = "High Warlord's Linked Leggings" },
    [28845] = { slot = "SHOULDER", class = "SHAMAN", honor = 11424, arena = 0, marks = { AB = 20 }, season = nil, name = "High Warlord's Linked Spaulders" },

    -- ROGUE - High Warlord's Vestments (Leather)
    [28836] = { slot = "HANDS", class = "ROGUE", honor = 10360, arena = 0, marks = { AB = 20 }, season = nil, name = "High Warlord's Leather Gloves" },
    [28837] = { slot = "HEAD", class = "ROGUE", honor = 14280, arena = 0, marks = { AV = 30 }, season = nil, name = "High Warlord's Leather Helm" },
    [28838] = { slot = "LEGS", class = "ROGUE", honor = 14280, arena = 0, marks = { AB = 30 }, season = nil, name = "High Warlord's Leather Legguards" },
    [28839] = { slot = "SHOULDER", class = "ROGUE", honor = 11424, arena = 0, marks = { AB = 20 }, season = nil, name = "High Warlord's Leather Spaulders" },
    [28840] = { slot = "CHEST", class = "ROGUE", honor = 14280, arena = 0, marks = { AB = 30 }, season = nil, name = "High Warlord's Leather Tunic" },

    -- DRUID - High Warlord's Sanctuary (Dragonhide Leather)
    [28810] = { slot = "CHEST", class = "DRUID", honor = 14280, arena = 0, marks = { AB = 30 }, season = nil, name = "High Warlord's Dragonhide Tunic" },
    [28811] = { slot = "HANDS", class = "DRUID", honor = 10360, arena = 0, marks = { AB = 20 }, season = nil, name = "High Warlord's Dragonhide Gloves" },
    [28812] = { slot = "HEAD", class = "DRUID", honor = 14280, arena = 0, marks = { AV = 30 }, season = nil, name = "High Warlord's Dragonhide Helm" },
    [28813] = { slot = "LEGS", class = "DRUID", honor = 14280, arena = 0, marks = { AB = 30 }, season = nil, name = "High Warlord's Dragonhide Legguards" },
    [28814] = { slot = "SHOULDER", class = "DRUID", honor = 11424, arena = 0, marks = { AB = 20 }, season = nil, name = "High Warlord's Dragonhide Spaulders" },

    -- PRIEST - High Warlord's Raiment (Satin Cloth)
    [28856] = { slot = "HANDS", class = "PRIEST", honor = 10360, arena = 0, marks = { AB = 20 }, season = nil, name = "High Warlord's Satin Gloves" },
    [28857] = { slot = "HEAD", class = "PRIEST", honor = 14280, arena = 0, marks = { AV = 30 }, season = nil, name = "High Warlord's Satin Hood" },
    [28858] = { slot = "LEGS", class = "PRIEST", honor = 14280, arena = 0, marks = { AB = 30 }, season = nil, name = "High Warlord's Satin Leggings" },
    [28859] = { slot = "SHOULDER", class = "PRIEST", honor = 11424, arena = 0, marks = { AB = 20 }, season = nil, name = "High Warlord's Satin Mantle" },
    [28860] = { slot = "CHEST", class = "PRIEST", honor = 14280, arena = 0, marks = { AB = 30 }, season = nil, name = "High Warlord's Satin Robe" },

    -- MAGE - High Warlord's Regalia (Silk Cloth)
    [28866] = { slot = "SHOULDER", class = "MAGE", honor = 11424, arena = 0, marks = { AB = 20 }, season = nil, name = "High Warlord's Silk Amice" },
    [28867] = { slot = "HEAD", class = "MAGE", honor = 14280, arena = 0, marks = { AV = 30 }, season = nil, name = "High Warlord's Silk Cowl" },
    [28868] = { slot = "HANDS", class = "MAGE", honor = 10360, arena = 0, marks = { AB = 20 }, season = nil, name = "High Warlord's Silk Handguards" },
    [28869] = { slot = "CHEST", class = "MAGE", honor = 14280, arena = 0, marks = { AB = 30 }, season = nil, name = "High Warlord's Silk Raiment" },
    [28870] = { slot = "LEGS", class = "MAGE", honor = 14280, arena = 0, marks = { AB = 30 }, season = nil, name = "High Warlord's Silk Trousers" },

    -- WARLOCK - High Warlord's Dreadgear (Dreadweave Cloth)
    [28817] = { slot = "HANDS", class = "WARLOCK", honor = 10360, arena = 0, marks = { AB = 20 }, season = nil, name = "High Warlord's Dreadweave Gloves" },
    [28818] = { slot = "HEAD", class = "WARLOCK", honor = 14280, arena = 0, marks = { AV = 30 }, season = nil, name = "High Warlord's Dreadweave Hood" },
    [28819] = { slot = "LEGS", class = "WARLOCK", honor = 14280, arena = 0, marks = { AB = 30 }, season = nil, name = "High Warlord's Dreadweave Leggings" },
    [28820] = { slot = "SHOULDER", class = "WARLOCK", honor = 11424, arena = 0, marks = { AB = 20 }, season = nil, name = "High Warlord's Dreadweave Mantle" },
    [28821] = { slot = "CHEST", class = "WARLOCK", honor = 14280, arena = 0, marks = { AB = 30 }, season = nil, name = "High Warlord's Dreadweave Robe" },

    --[[
    ============================================================================
    HONOR WEAPONS - High Warlord's / Grand Marshal's
    Verified from Wowhead TBC Classic
    ============================================================================
    --]]

    -- Two-Handed Weapons (TBC Level 70 versions)
    [28935] = { slot = "TWO_HAND", class = nil, honor = 38250, arena = 0, marks = { AV = 40 }, season = nil, name = "High Warlord's War Staff" },
    [28920] = { slot = "MAIN_HAND", class = nil, honor = 25200, arena = 0, marks = { AV = 20 }, season = nil, name = "High Warlord's Cleaver" },
    -- Note: Classic rank 14 weapons (18XXX, 16XXX, 12XXX range) are in the PREPATCH section with reduced costs

    --[[
    ============================================================================
    ACCESSORIES - Trinkets, Rings, Necks (Verified)
    ============================================================================
    --]]

    -- PvP Trinkets (Medallion of the Horde/Alliance - Break CC)
    [28235] = { slot = "TRINKET", class = nil, honor = 16983, arena = 0, marks = { AB = 10, AV = 10 }, season = nil, name = "Medallion of the Horde" },
    [28236] = { slot = "TRINKET", class = nil, honor = 16983, arena = 0, marks = { AB = 10, AV = 10 }, season = nil, name = "Medallion of the Alliance" },

    -- Battlemaster Trinkets
    [28237] = { slot = "TRINKET", class = nil, honor = 16983, arena = 0, marks = { EotS = 10, WSG = 10 }, season = nil, name = "Battlemaster's Cruelty" },
    [28238] = { slot = "TRINKET", class = nil, honor = 16983, arena = 0, marks = { EotS = 10, WSG = 10 }, season = nil, name = "Battlemaster's Depravity" },
    [28239] = { slot = "TRINKET", class = nil, honor = 16983, arena = 0, marks = { EotS = 10, WSG = 10 }, season = nil, name = "Battlemaster's Determination" },
    [28240] = { slot = "TRINKET", class = nil, honor = 16983, arena = 0, marks = { EotS = 10, WSG = 10 }, season = nil, name = "Battlemaster's Audacity" },
    [28241] = { slot = "TRINKET", class = nil, honor = 16983, arena = 0, marks = { EotS = 10, WSG = 10 }, season = nil, name = "Battlemaster's Perseverance" },

    -- PvP Rings (Verified from Wowhead)
    [28246] = { slot = "FINGER", class = nil, honor = 15300, arena = 0, marks = { AV = 10 }, season = nil, name = "Band of Triumph" },
    [28247] = { slot = "FINGER", class = nil, honor = 15300, arena = 0, marks = { AV = 10 }, season = nil, name = "Band of Dominance" },

    -- PvP Necklaces (Verified from Wowhead)
    [28244] = { slot = "NECK", class = nil, honor = 15300, arena = 0, marks = { AB = 10 }, season = nil, name = "Pendant of Triumph" },
    [28245] = { slot = "NECK", class = nil, honor = 15300, arena = 0, marks = { AB = 10 }, season = nil, name = "Pendant of Dominance" },

    -- Sergeant's Cloaks (Verified from Wowhead)
    [28377] = { slot = "BACK", class = nil, honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Sergeant's Heavy Cloak" },
    [28378] = { slot = "BACK", class = nil, honor = 11794, arena = 0, marks = { EotS = 20 }, season = nil, name = "Sergeant's Heavy Cape" },

    --[[
    ============================================================================
    VETERAN'S GEAR - Season 2 Honor Off-Pieces (Belts, Boots, Bracers)
    Verified itemIDs from Wowhead TBC Classic
    Honor + marks, no arena points required
    ============================================================================
    --]]

    -- VETERAN'S CLOTH (Mage/Warlock/Priest)
    -- Dreadweave (Warlock)
    [32799] = { slot = "WAIST", class = "WARLOCK", honor = 17850, arena = 0, marks = { AB = 40 }, season = nil, name = "Veteran's Dreadweave Belt" },
    [32797] = { slot = "WRIST", class = "WARLOCK", honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Veteran's Dreadweave Cuffs" },
    [32798] = { slot = "FEET", class = "WARLOCK", honor = 17850, arena = 0, marks = { EotS = 40 }, season = nil, name = "Veteran's Dreadweave Stalkers" },

    -- Silk (Mage)
    [32807] = { slot = "WAIST", class = "MAGE", honor = 17850, arena = 0, marks = { AB = 40 }, season = nil, name = "Veteran's Silk Belt" },
    [32820] = { slot = "WRIST", class = "MAGE", honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Veteran's Silk Cuffs" },
    [32795] = { slot = "FEET", class = "MAGE", honor = 17850, arena = 0, marks = { EotS = 40 }, season = nil, name = "Veteran's Silk Footguards" },

    -- Mooncloth (Priest)
    [32803] = { slot = "WAIST", class = "PRIEST", honor = 17850, arena = 0, marks = { AB = 40 }, season = nil, name = "Veteran's Mooncloth Belt" },
    [32817] = { slot = "WRIST", class = "PRIEST", honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Veteran's Mooncloth Cuffs" },
    [32791] = { slot = "FEET", class = "PRIEST", honor = 17850, arena = 0, marks = { EotS = 40 }, season = nil, name = "Veteran's Mooncloth Slippers" },

    -- VETERAN'S LEATHER (Rogue/Druid)
    -- Leather (Rogue)
    [32802] = { slot = "WAIST", class = "ROGUE", honor = 17850, arena = 0, marks = { AB = 40 }, season = nil, name = "Veteran's Leather Belt" },
    [32814] = { slot = "WRIST", class = "ROGUE", honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Veteran's Leather Bracers" },
    [32790] = { slot = "FEET", class = "ROGUE", honor = 17850, arena = 0, marks = { EotS = 40 }, season = nil, name = "Veteran's Leather Boots" },

    -- Dragonhide (Druid Feral)
    [32800] = { slot = "WAIST", class = "DRUID", honor = 17850, arena = 0, marks = { AB = 40 }, season = nil, name = "Veteran's Dragonhide Belt" },
    [32810] = { slot = "WRIST", class = "DRUID", honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Veteran's Dragonhide Bracers" },
    [32786] = { slot = "FEET", class = "DRUID", honor = 17850, arena = 0, marks = { EotS = 40 }, season = nil, name = "Veteran's Dragonhide Boots" },

    -- VETERAN'S MAIL (Hunter/Shaman)
    -- Chain (Hunter)
    [32788] = { slot = "WAIST", class = "HUNTER", honor = 17850, arena = 0, marks = { AB = 40 }, season = nil, name = "Veteran's Chain Girdle" },
    [32809] = { slot = "WRIST", class = "HUNTER", honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Veteran's Chain Bracers" },
    [32787] = { slot = "FEET", class = "HUNTER", honor = 17850, arena = 0, marks = { EotS = 40 }, season = nil, name = "Veteran's Chain Sabatons" },

    -- Linked (Shaman)
    [32804] = { slot = "WAIST", class = "SHAMAN", honor = 17850, arena = 0, marks = { AB = 40 }, season = nil, name = "Veteran's Linked Girdle" },
    [32815] = { slot = "WRIST", class = "SHAMAN", honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Veteran's Linked Bracers" },
    [32792] = { slot = "FEET", class = "SHAMAN", honor = 17850, arena = 0, marks = { EotS = 40 }, season = nil, name = "Veteran's Linked Sabatons" },

    -- VETERAN'S PLATE (Warrior/Paladin)
    -- Plate (Warrior)
    [32805] = { slot = "WAIST", class = "WARRIOR", honor = 17850, arena = 0, marks = { AB = 40 }, season = nil, name = "Veteran's Plate Belt" },
    [32818] = { slot = "WRIST", class = "WARRIOR", honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Veteran's Plate Bracers" },
    [32793] = { slot = "FEET", class = "WARRIOR", honor = 17850, arena = 0, marks = { EotS = 40 }, season = nil, name = "Veteran's Plate Greaves" },

    -- Lamellar (Paladin)
    [32801] = { slot = "WAIST", class = "PALADIN", honor = 17850, arena = 0, marks = { AB = 40 }, season = nil, name = "Veteran's Lamellar Belt" },
    [32812] = { slot = "WRIST", class = "PALADIN", honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Veteran's Lamellar Bracers" },
    [32789] = { slot = "FEET", class = "PALADIN", honor = 17850, arena = 0, marks = { EotS = 40 }, season = nil, name = "Veteran's Lamellar Greaves" },

    --[[
    ============================================================================
    VINDICATOR'S GEAR - Season 3 Honor Off-Pieces (Belts, Boots, Bracers)
    Verified itemIDs from Wowhead TBC Classic
    Honor + marks, no arena points required
    ============================================================================
    --]]

    -- VINDICATOR'S CLOTH (Mage/Warlock/Priest)
    -- Dreadweave (Warlock)
    [33882] = { slot = "WAIST", class = "WARLOCK", honor = 17850, arena = 0, marks = { AB = 40 }, season = nil, name = "Vindicator's Dreadweave Belt" },
    [33883] = { slot = "WRIST", class = "WARLOCK", honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Vindicator's Dreadweave Cuffs" },
    [33884] = { slot = "FEET", class = "WARLOCK", honor = 17850, arena = 0, marks = { EotS = 40 }, season = nil, name = "Vindicator's Dreadweave Stalkers" },

    -- Silk (Mage)
    [33912] = { slot = "WAIST", class = "MAGE", honor = 17850, arena = 0, marks = { AB = 40 }, season = nil, name = "Vindicator's Silk Belt" },
    [33913] = { slot = "WRIST", class = "MAGE", honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Vindicator's Silk Cuffs" },
    [33914] = { slot = "FEET", class = "MAGE", honor = 17850, arena = 0, marks = { EotS = 40 }, season = nil, name = "Vindicator's Silk Footguards" },

    -- Mooncloth (Priest)
    [33900] = { slot = "WAIST", class = "PRIEST", honor = 17850, arena = 0, marks = { AB = 40 }, season = nil, name = "Vindicator's Mooncloth Belt" },
    [33901] = { slot = "WRIST", class = "PRIEST", honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Vindicator's Mooncloth Cuffs" },
    [33902] = { slot = "FEET", class = "PRIEST", honor = 17850, arena = 0, marks = { EotS = 40 }, season = nil, name = "Vindicator's Mooncloth Slippers" },

    -- VINDICATOR'S LEATHER (Rogue/Druid)
    -- Leather (Rogue)
    [33891] = { slot = "WAIST", class = "ROGUE", honor = 17850, arena = 0, marks = { AB = 40 }, season = nil, name = "Vindicator's Leather Belt" },
    [33893] = { slot = "WRIST", class = "ROGUE", honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Vindicator's Leather Bracers" },
    [33892] = { slot = "FEET", class = "ROGUE", honor = 17850, arena = 0, marks = { EotS = 40 }, season = nil, name = "Vindicator's Leather Boots" },

    -- Dragonhide (Druid Feral)
    [33879] = { slot = "WAIST", class = "DRUID", honor = 17850, arena = 0, marks = { AB = 40 }, season = nil, name = "Vindicator's Dragonhide Belt" },
    [33881] = { slot = "WRIST", class = "DRUID", honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Vindicator's Dragonhide Bracers" },
    [33880] = { slot = "FEET", class = "DRUID", honor = 17850, arena = 0, marks = { EotS = 40 }, season = nil, name = "Vindicator's Dragonhide Boots" },

    -- VINDICATOR'S MAIL (Hunter/Shaman)
    -- Chain (Hunter)
    [33877] = { slot = "WAIST", class = "HUNTER", honor = 17850, arena = 0, marks = { AB = 40 }, season = nil, name = "Vindicator's Chain Girdle" },
    [33876] = { slot = "WRIST", class = "HUNTER", honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Vindicator's Chain Bracers" },
    [33878] = { slot = "FEET", class = "HUNTER", honor = 17850, arena = 0, marks = { EotS = 40 }, season = nil, name = "Vindicator's Chain Sabatons" },

    -- Linked (Shaman)
    [33895] = { slot = "WAIST", class = "SHAMAN", honor = 17850, arena = 0, marks = { AB = 40 }, season = nil, name = "Vindicator's Linked Girdle" },
    [33894] = { slot = "WRIST", class = "SHAMAN", honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Vindicator's Linked Bracers" },
    [33896] = { slot = "FEET", class = "SHAMAN", honor = 17850, arena = 0, marks = { EotS = 40 }, season = nil, name = "Vindicator's Linked Sabatons" },

    -- VINDICATOR'S PLATE (Warrior/Paladin)
    -- Plate (Warrior)
    [33811] = { slot = "WAIST", class = "WARRIOR", honor = 17850, arena = 0, marks = { AB = 40 }, season = nil, name = "Vindicator's Plate Belt" },
    [33813] = { slot = "WRIST", class = "WARRIOR", honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Vindicator's Plate Bracers" },
    [33812] = { slot = "FEET", class = "WARRIOR", honor = 17850, arena = 0, marks = { EotS = 40 }, season = nil, name = "Vindicator's Plate Greaves" },

    -- Lamellar (Paladin)
    [33885] = { slot = "WAIST", class = "PALADIN", honor = 17850, arena = 0, marks = { AB = 40 }, season = nil, name = "Vindicator's Lamellar Belt" },
    [33887] = { slot = "WRIST", class = "PALADIN", honor = 11794, arena = 0, marks = { WSG = 20 }, season = nil, name = "Vindicator's Lamellar Bracers" },
    [33886] = { slot = "FEET", class = "PALADIN", honor = 17850, arena = 0, marks = { EotS = 40 }, season = nil, name = "Vindicator's Lamellar Greaves" },

    --[[
    ============================================================================
    PREPATCH BG VENDOR ITEMS - Highlander's Sets (Alliance AB)
    TBC Prepatch costs: Honor + Arathi Basin marks (no rep required)
    ItemIDs verified from Wowhead TBC Classic set pages
    ============================================================================
    --]]

    -- HIGHLANDER'S CLOTH (Priest/Mage/Warlock) - The Highlander's Intent
    [20047] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Cloth Girdle" },
    [20054] = { slot = "FEET", class = nil, honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Cloth Boots" },
    [20061] = { slot = "SHOULDER", class = nil, honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Epaulets" },

    -- HIGHLANDER'S LEATHER (Rogue) - The Highlander's Purpose
    [20045] = { slot = "WAIST", class = "ROGUE", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Leather Girdle" },
    [20052] = { slot = "FEET", class = "ROGUE", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Leather Boots" },
    [20059] = { slot = "SHOULDER", class = "ROGUE", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Leather Shoulders" },

    -- HIGHLANDER'S LIZARDHIDE (Druid) - The Highlander's Resolve
    [20103] = { slot = "WAIST", class = "DRUID", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Lizardhide Girdle" },
    [20060] = { slot = "SHOULDER", class = "DRUID", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Lizardhide Shoulders" },

    -- HIGHLANDER'S CHAIN (Hunter) - The Highlander's Determination
    [20043] = { slot = "WAIST", class = "HUNTER", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Chain Girdle" },
    [20050] = { slot = "FEET", class = "HUNTER", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Chain Greaves" },
    [20055] = { slot = "SHOULDER", class = "HUNTER", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Chain Pauldrons" },

    -- HIGHLANDER'S MAIL (Shaman) - The Highlander's Fortitude
    [20044] = { slot = "WAIST", class = "SHAMAN", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Mail Girdle" },
    [20051] = { slot = "FEET", class = "SHAMAN", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Mail Greaves" },
    [20056] = { slot = "SHOULDER", class = "SHAMAN", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Mail Pauldrons" },

    -- HIGHLANDER'S PLATE (Warrior) - The Highlander's Resolution
    [20041] = { slot = "WAIST", class = "WARRIOR", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Plate Girdle" },
    [20127] = { slot = "FEET", class = "WARRIOR", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Plate Greaves" },
    [20057] = { slot = "SHOULDER", class = "WARRIOR", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Plate Spaulders" },

    -- HIGHLANDER'S LAMELLAR (Paladin) - The Highlander's Resolve
    [20042] = { slot = "WAIST", class = "PALADIN", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Lamellar Girdle" },
    [20049] = { slot = "FEET", class = "PALADIN", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Lamellar Greaves" },
    [20058] = { slot = "SHOULDER", class = "PALADIN", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Highlander's Lamellar Spaulders" },

    --[[
    ============================================================================
    PREPATCH BG VENDOR ITEMS - Defiler's Sets (Horde AB)
    TBC Prepatch costs: Honor + Arathi Basin marks (no rep required)
    ItemIDs verified from Wowhead TBC Classic set pages
    ============================================================================
    --]]

    -- DEFILER'S CLOTH (Priest/Mage/Warlock) - The Defiler's Intent
    [20163] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Cloth Girdle" },
    [20159] = { slot = "FEET", class = nil, honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Cloth Boots" },
    [20176] = { slot = "SHOULDER", class = nil, honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Epaulets" },

    -- DEFILER'S LEATHER (Rogue) - The Defiler's Purpose
    [20190] = { slot = "WAIST", class = "ROGUE", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Leather Girdle" },
    [20186] = { slot = "FEET", class = "ROGUE", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Leather Boots" },
    [20194] = { slot = "SHOULDER", class = "ROGUE", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Leather Shoulders" },

    -- DEFILER'S LIZARDHIDE (Druid) - The Defiler's Will
    [20171] = { slot = "WAIST", class = "DRUID", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Lizardhide Girdle" },
    [20167] = { slot = "FEET", class = "DRUID", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Lizardhide Boots" },
    [20175] = { slot = "SHOULDER", class = "DRUID", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Lizardhide Shoulders" },

    -- DEFILER'S CHAIN (Hunter) - The Defiler's Determination
    [20150] = { slot = "WAIST", class = "HUNTER", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Chain Girdle" },
    [20154] = { slot = "FEET", class = "HUNTER", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Chain Greaves" },
    [20158] = { slot = "SHOULDER", class = "HUNTER", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Chain Pauldrons" },

    -- DEFILER'S MAIL (Shaman) - The Defiler's Fortitude
    [20195] = { slot = "WAIST", class = "SHAMAN", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Mail Girdle" },
    [20203] = { slot = "SHOULDER", class = "SHAMAN", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Mail Pauldrons" },

    -- DEFILER'S PLATE (Warrior) - The Defiler's Resolution
    [20204] = { slot = "WAIST", class = "WARRIOR", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Plate Girdle" },
    [20211] = { slot = "FEET", class = "WARRIOR", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Plate Greaves" },
    [20212] = { slot = "SHOULDER", class = "WARRIOR", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Plate Spaulders" },

    -- DEFILER'S LAMELLAR (Paladin) - The Defiler's Resolve
    [20177] = { slot = "WAIST", class = "PALADIN", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Lamellar Girdle" },
    [20181] = { slot = "FEET", class = "PALADIN", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Lamellar Greaves" },
    [20184] = { slot = "SHOULDER", class = "PALADIN", honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Lamellar Spaulders" },

    --[[
    ============================================================================
    PREPATCH BG VENDOR ITEMS - Sentinel's Sets (Alliance WSG)
    TBC Prepatch costs: Honor + Warsong Gulch marks (no rep required)
    ItemIDs verified from Wowhead TBC Classic
    ============================================================================
    --]]

    -- SENTINEL'S SILK (Cloth - Caster)
    [22752] = { slot = "LEGS", class = nil, honor = 2805, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Sentinel's Silk Leggings" },

    -- SENTINEL'S LEATHER (Rogue)
    [22749] = { slot = "LEGS", class = "ROGUE", honor = 2805, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Sentinel's Leather Pants" },

    -- SENTINEL'S LIZARDHIDE (Druid)
    [22750] = { slot = "LEGS", class = "DRUID", honor = 2805, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Sentinel's Lizardhide Pants" },

    -- SENTINEL'S CHAIN (Hunter)
    [22748] = { slot = "LEGS", class = "HUNTER", honor = 2805, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Sentinel's Chain Leggings" },

    -- SENTINEL'S MAIL (Shaman)
    [30497] = { slot = "LEGS", class = "SHAMAN", honor = 2805, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Sentinel's Mail Leggings" },

    -- SENTINEL'S PLATE (Warrior)
    [22672] = { slot = "LEGS", class = "WARRIOR", honor = 2805, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Sentinel's Plate Legguards" },

    -- SENTINEL'S LAMELLAR (Paladin)
    [22753] = { slot = "LEGS", class = "PALADIN", honor = 2805, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Sentinel's Lamellar Legguards" },

    --[[
    ============================================================================
    PREPATCH BG VENDOR ITEMS - Outrider's Sets (Horde WSG)
    TBC Prepatch costs: Honor + Warsong Gulch marks (no rep required)
    ItemIDs verified from Wowhead TBC Classic
    ============================================================================
    --]]

    -- OUTRIDER'S SILK (Cloth - Caster)
    [22747] = { slot = "LEGS", class = nil, honor = 2805, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Outrider's Silk Leggings" },

    -- OUTRIDER'S LEATHER (Rogue)
    [22740] = { slot = "LEGS", class = "ROGUE", honor = 2805, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Outrider's Leather Pants" },

    -- OUTRIDER'S LIZARDHIDE (Druid)
    [22741] = { slot = "LEGS", class = "DRUID", honor = 2805, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Outrider's Lizardhide Pants" },

    -- OUTRIDER'S CHAIN (Hunter)
    [22673] = { slot = "LEGS", class = "HUNTER", honor = 2805, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Outrider's Chain Leggings" },

    -- OUTRIDER'S MAIL (Shaman)
    [22676] = { slot = "LEGS", class = "SHAMAN", honor = 2805, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Outrider's Mail Leggings" },

    -- OUTRIDER'S PLATE (Warrior)
    [22651] = { slot = "LEGS", class = "WARRIOR", honor = 2805, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Outrider's Plate Legguards" },

    -- OUTRIDER'S LAMELLAR (Paladin)
    [30498] = { slot = "LEGS", class = "PALADIN", honor = 2805, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Outrider's Lamellar Legguards" },

    --[[
    ============================================================================
    PREPATCH BG VENDOR ITEMS - Stormpike Sets (Alliance AV)
    TBC Prepatch costs: Honor + Alterac Valley marks (no rep required)
    ItemIDs verified from Wowhead TBC Classic
    ============================================================================
    --]]

    -- STORMPIKE CLOTH
    [19094] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Stormpike Cloth Girdle" },

    -- STORMPIKE LEATHER
    [19093] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Stormpike Leather Girdle" },

    -- STORMPIKE MAIL
    [19092] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Stormpike Mail Girdle" },

    -- STORMPIKE PLATE
    [19091] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Stormpike Plate Girdle" },

    --[[
    ============================================================================
    PREPATCH BG VENDOR ITEMS - Frostwolf Sets (Horde AV)
    TBC Prepatch costs: Honor + Alterac Valley marks (no rep required)
    ItemIDs verified from Wowhead TBC Classic
    ============================================================================
    --]]

    -- FROSTWOLF CLOTH
    [19090] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Frostwolf Cloth Belt" },

    -- FROSTWOLF LEATHER
    [19089] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Frostwolf Leather Belt" },

    -- FROSTWOLF MAIL
    [19088] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Frostwolf Mail Belt" },

    -- FROSTWOLF PLATE
    [19087] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Frostwolf Plate Belt" },

    --[[
    ============================================================================
    PREPATCH RANK 12-13 EPIC SETS - Field Marshal's / Warlord's (Alliance/Horde)
    TBC Prepatch costs based on Anniversary prepatch pricing (reduced marks)
    Head: 13005 honor + 3 AV marks
    Shoulders: 8415 honor + 2 AB marks
    Chest: 13770 honor + 3 AB marks
    Legs: 13005 honor + 3 WSG marks
    Hands: 8415 honor + 2 AV marks
    Feet: 8415 honor + 2 AB marks
    ============================================================================
    --]]

    -- WARRIOR - Field Marshal's Battlegear (Alliance)
    [16477] = { slot = "CHEST", class = "WARRIOR", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Field Marshal's Plate Armor" },
    [16478] = { slot = "HEAD", class = "WARRIOR", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Field Marshal's Plate Helm" },
    [16480] = { slot = "SHOULDER", class = "WARRIOR", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Field Marshal's Plate Shoulderguards" },
    [16483] = { slot = "FEET", class = "WARRIOR", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Plate Boots" },
    [16484] = { slot = "HANDS", class = "WARRIOR", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Plate Gauntlets" },
    [16479] = { slot = "LEGS", class = "WARRIOR", honor = 13005, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Marshal's Plate Legguards" },

    -- WARRIOR - Warlord's Battlegear (Horde)
    [16541] = { slot = "CHEST", class = "WARRIOR", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Warlord's Plate Armor" },
    [16542] = { slot = "HEAD", class = "WARRIOR", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Warlord's Plate Headpiece" },
    [16544] = { slot = "SHOULDER", class = "WARRIOR", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Warlord's Plate Shoulders" },
    [16545] = { slot = "FEET", class = "WARRIOR", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Plate Boots" },
    [16548] = { slot = "HANDS", class = "WARRIOR", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Plate Gauntlets" },
    [16543] = { slot = "LEGS", class = "WARRIOR", honor = 13005, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "General's Plate Leggings" },

    -- PALADIN - Field Marshal's Aegis (Alliance)
    [16473] = { slot = "CHEST", class = "PALADIN", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Field Marshal's Lamellar Chestplate" },
    [16474] = { slot = "HEAD", class = "PALADIN", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Field Marshal's Lamellar Faceguard" },
    [16476] = { slot = "SHOULDER", class = "PALADIN", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Field Marshal's Lamellar Pauldrons" },
    [16472] = { slot = "FEET", class = "PALADIN", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Lamellar Boots" },
    [16471] = { slot = "HANDS", class = "PALADIN", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Lamellar Gloves" },
    [16475] = { slot = "LEGS", class = "PALADIN", honor = 13005, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Marshal's Lamellar Legplates" },

    -- SHAMAN - Warlord's Earthshaker (Horde)
    [16577] = { slot = "CHEST", class = "SHAMAN", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Warlord's Mail Armor" },
    [16578] = { slot = "HEAD", class = "SHAMAN", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Warlord's Mail Helm" },
    [16580] = { slot = "SHOULDER", class = "SHAMAN", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Warlord's Mail Spaulders" },
    [16573] = { slot = "FEET", class = "SHAMAN", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Mail Boots" },
    [16574] = { slot = "HANDS", class = "SHAMAN", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Mail Gauntlets" },
    [16579] = { slot = "LEGS", class = "SHAMAN", honor = 13005, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "General's Mail Leggings" },

    -- HUNTER - Field Marshal's Pursuit (Alliance)
    [16466] = { slot = "CHEST", class = "HUNTER", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Field Marshal's Chain Breastplate" },
    [16465] = { slot = "HEAD", class = "HUNTER", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Field Marshal's Chain Helm" },
    [16468] = { slot = "SHOULDER", class = "HUNTER", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Field Marshal's Chain Spaulders" },
    [16462] = { slot = "FEET", class = "HUNTER", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Chain Boots" },
    [16463] = { slot = "HANDS", class = "HUNTER", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Chain Grips" },
    [16467] = { slot = "LEGS", class = "HUNTER", honor = 13005, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Marshal's Chain Legguards" },

    -- HUNTER - Warlord's Pursuit (Horde)
    [16565] = { slot = "CHEST", class = "HUNTER", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Warlord's Chain Chestpiece" },
    [16566] = { slot = "HEAD", class = "HUNTER", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Warlord's Chain Helmet" },
    [16568] = { slot = "SHOULDER", class = "HUNTER", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Warlord's Chain Shoulders" },
    [16569] = { slot = "FEET", class = "HUNTER", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Chain Sabatons" },
    [16571] = { slot = "HANDS", class = "HUNTER", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Chain Gloves" },
    [16567] = { slot = "LEGS", class = "HUNTER", honor = 13005, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "General's Chain Legguards" },

    -- ROGUE - Field Marshal's Vestments (Alliance)
    [16453] = { slot = "CHEST", class = "ROGUE", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Field Marshal's Leather Chestpiece" },
    [16455] = { slot = "HEAD", class = "ROGUE", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Field Marshal's Leather Mask" },
    [16457] = { slot = "SHOULDER", class = "ROGUE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Field Marshal's Leather Epaulets" },
    [16446] = { slot = "FEET", class = "ROGUE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Leather Footguards" },
    [16454] = { slot = "HANDS", class = "ROGUE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Leather Handgrips" },
    [16456] = { slot = "LEGS", class = "ROGUE", honor = 13005, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Marshal's Leather Leggings" },

    -- ROGUE - Warlord's Vestments (Horde)
    [16563] = { slot = "CHEST", class = "ROGUE", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Warlord's Leather Breastplate" },
    [16561] = { slot = "HEAD", class = "ROGUE", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Warlord's Leather Helm" },
    [16562] = { slot = "SHOULDER", class = "ROGUE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Warlord's Leather Spaulders" },
    [16558] = { slot = "FEET", class = "ROGUE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Leather Treads" },
    [16560] = { slot = "HANDS", class = "ROGUE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Leather Mitts" },
    [16564] = { slot = "LEGS", class = "ROGUE", honor = 13005, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "General's Leather Legguards" },

    -- DRUID - Field Marshal's Sanctuary (Alliance)
    [16452] = { slot = "CHEST", class = "DRUID", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Field Marshal's Dragonhide Breastplate" },
    [16451] = { slot = "HEAD", class = "DRUID", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Field Marshal's Dragonhide Helmet" },
    [16449] = { slot = "SHOULDER", class = "DRUID", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Field Marshal's Dragonhide Spaulders" },
    [16459] = { slot = "FEET", class = "DRUID", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Dragonhide Boots" },
    [16448] = { slot = "HANDS", class = "DRUID", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Dragonhide Gauntlets" },
    [16450] = { slot = "LEGS", class = "DRUID", honor = 13005, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Marshal's Dragonhide Legguards" },

    -- DRUID - Warlord's Sanctuary (Horde)
    [16549] = { slot = "CHEST", class = "DRUID", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Warlord's Dragonhide Hauberk" },
    [16550] = { slot = "HEAD", class = "DRUID", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Warlord's Dragonhide Helmet" },
    [16551] = { slot = "SHOULDER", class = "DRUID", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Warlord's Dragonhide Epaulets" },
    [16554] = { slot = "FEET", class = "DRUID", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Dragonhide Boots" },
    [16555] = { slot = "HANDS", class = "DRUID", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Dragonhide Gloves" },
    [16552] = { slot = "LEGS", class = "DRUID", honor = 13005, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "General's Dragonhide Leggings" },

    -- MAGE - Field Marshal's Regalia (Alliance)
    [16443] = { slot = "CHEST", class = "MAGE", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Field Marshal's Silk Vestments" },
    [16441] = { slot = "HEAD", class = "MAGE", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Field Marshal's Coronet" },
    [16444] = { slot = "SHOULDER", class = "MAGE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Field Marshal's Silk Spaulders" },
    [16445] = { slot = "FEET", class = "MAGE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Silk Footwraps" },
    [16440] = { slot = "HANDS", class = "MAGE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Silk Gloves" },
    [16442] = { slot = "LEGS", class = "MAGE", honor = 13005, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Marshal's Silk Leggings" },

    -- MAGE - Warlord's Regalia (Horde)
    [16535] = { slot = "CHEST", class = "MAGE", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Warlord's Silk Raiment" },
    [16533] = { slot = "HEAD", class = "MAGE", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Warlord's Silk Cowl" },
    [16536] = { slot = "SHOULDER", class = "MAGE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Warlord's Silk Amice" },
    [16539] = { slot = "FEET", class = "MAGE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Silk Boots" },
    [16540] = { slot = "HANDS", class = "MAGE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Silk Handguards" },
    [16534] = { slot = "LEGS", class = "MAGE", honor = 13005, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "General's Silk Trousers" },

    -- WARLOCK - Field Marshal's Threads (Alliance)
    [17581] = { slot = "CHEST", class = "WARLOCK", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Field Marshal's Dreadweave Robe" },
    [17578] = { slot = "HEAD", class = "WARLOCK", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Field Marshal's Coronal" },
    [17580] = { slot = "SHOULDER", class = "WARLOCK", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Field Marshal's Dreadweave Shoulders" },
    [17583] = { slot = "FEET", class = "WARLOCK", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Dreadweave Boots" },
    [17584] = { slot = "HANDS", class = "WARLOCK", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Dreadweave Gloves" },
    [17579] = { slot = "LEGS", class = "WARLOCK", honor = 13005, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Marshal's Dreadweave Leggings" },

    -- WARLOCK - Warlord's Threads (Horde)
    [17592] = { slot = "CHEST", class = "WARLOCK", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Warlord's Dreadweave Robe" },
    [17591] = { slot = "HEAD", class = "WARLOCK", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Warlord's Dreadweave Hood" },
    [17590] = { slot = "SHOULDER", class = "WARLOCK", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Warlord's Dreadweave Mantle" },
    [17586] = { slot = "FEET", class = "WARLOCK", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Dreadweave Boots" },
    [17588] = { slot = "HANDS", class = "WARLOCK", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Dreadweave Gloves" },
    [17593] = { slot = "LEGS", class = "WARLOCK", honor = 13005, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "General's Dreadweave Pants" },

    -- PRIEST - Field Marshal's Raiment (Alliance)
    [17605] = { slot = "CHEST", class = "PRIEST", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Field Marshal's Satin Vestments" },
    [17602] = { slot = "HEAD", class = "PRIEST", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Field Marshal's Headdress" },
    [17604] = { slot = "SHOULDER", class = "PRIEST", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Field Marshal's Satin Mantle" },
    [17607] = { slot = "FEET", class = "PRIEST", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Satin Sandals" },
    [17608] = { slot = "HANDS", class = "PRIEST", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Satin Gloves" },
    [17603] = { slot = "LEGS", class = "PRIEST", honor = 13005, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Marshal's Satin Pants" },

    -- PRIEST - Warlord's Raiment (Horde)
    [17624] = { slot = "CHEST", class = "PRIEST", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Warlord's Satin Robes" },
    [17623] = { slot = "HEAD", class = "PRIEST", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Warlord's Satin Cowl" },
    [17622] = { slot = "SHOULDER", class = "PRIEST", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Warlord's Satin Mantle" },
    [17618] = { slot = "FEET", class = "PRIEST", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Satin Boots" },
    [17620] = { slot = "HANDS", class = "PRIEST", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Satin Gloves" },
    [17625] = { slot = "LEGS", class = "PRIEST", honor = 13005, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "General's Satin Leggings" },

    --[[
    ============================================================================
    PREPATCH RANK 14 WEAPONS - Grand Marshal's / High Warlord's
    TBC Prepatch costs: 7935 honor, no marks required
    ============================================================================
    --]]

    -- TWO-HAND SWORDS
    [18876] = { slot = "TWO_HAND", class = "WARRIOR", honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Claymore" },
    [18877] = { slot = "TWO_HAND", class = "WARRIOR", honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Greatsword" },

    -- ONE-HAND SWORDS
    [12584] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Longsword" },
    [16345] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Blade" },

    --[[
    ============================================================================
    PREPATCH PVP TRINKETS - Insignia of the Alliance/Horde
    TBC Prepatch costs: Honor only (2805 estimated)
    ============================================================================
    --]]

    -- PVP Trinkets (Warrior)
    [18854] = { slot = "TRINKET", class = "WARRIOR", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Alliance" },
    [18852] = { slot = "TRINKET", class = "WARRIOR", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },

    -- PVP Trinkets (Paladin)
    [18862] = { slot = "TRINKET", class = "PALADIN", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Alliance" },
    [18834] = { slot = "TRINKET", class = "PALADIN", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },

    -- PVP Trinkets (Rogue)
    [18856] = { slot = "TRINKET", class = "ROGUE", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Alliance" },
    [18849] = { slot = "TRINKET", class = "ROGUE", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },

    -- PVP Trinkets (Priest)
    [18858] = { slot = "TRINKET", class = "PRIEST", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Alliance" },
    [18851] = { slot = "TRINKET", class = "PRIEST", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },

    -- PVP Trinkets (Mage)
    [18859] = { slot = "TRINKET", class = "MAGE", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Alliance" },
    [18845] = { slot = "TRINKET", class = "MAGE", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },

    -- PVP Trinkets (Warlock)
    [18857] = { slot = "TRINKET", class = "WARLOCK", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Alliance" },
    [18850] = { slot = "TRINKET", class = "WARLOCK", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },

    -- PVP Trinkets (Hunter)
    [18855] = { slot = "TRINKET", class = "HUNTER", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Alliance" },
    [18846] = { slot = "TRINKET", class = "HUNTER", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },

    -- PVP Trinkets (Druid)
    [18864] = { slot = "TRINKET", class = "DRUID", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Alliance" },
    [18853] = { slot = "TRINKET", class = "DRUID", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },

    -- PVP Trinkets (Shaman)
    [18847] = { slot = "TRINKET", class = "SHAMAN", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },

    --[[
    ============================================================================
    PREPATCH RANK 14 WEAPONS (continued) - All weapon types
    TBC Prepatch costs: 7935 honor, no marks required
    ============================================================================
    --]]

    -- ONE-HAND AXES
    [18866] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Handaxe" },
    [18826] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Cleaver" },

    -- TWO-HAND AXES
    [18865] = { slot = "TWO_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Sunderer" },
    [18831] = { slot = "TWO_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Pulverizer" },

    -- ONE-HAND MACES
    [18869] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Punisher" },
    [18843] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Quickblade" },

    -- TWO-HAND MACES
    [18867] = { slot = "TWO_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Demolisher" },
    [18832] = { slot = "TWO_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Destroyer" },

    -- STAVES
    [18874] = { slot = "TWO_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Stave" },
    [18840] = { slot = "TWO_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's War Staff" },

    -- POLEARMS
    [18875] = { slot = "TWO_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Glaive" },
    [18841] = { slot = "TWO_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Pig Sticker" },

    -- DAGGERS
    [18871] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Dirk" },
    [18836] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Razor" },

    -- FIST WEAPONS
    [18872] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Right Hand Blade" },
    [18838] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Right Claw" },
    [18873] = { slot = "OFF_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Left Hand Blade" },
    [18839] = { slot = "OFF_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Left Claw" },

    -- BOWS
    [18880] = { slot = "RANGED", class = "HUNTER", honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Bullseye" },
    [18835] = { slot = "RANGED", class = "HUNTER", honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Recurve" },

    -- CROSSBOWS
    [18870] = { slot = "RANGED", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Repeater" },
    [18833] = { slot = "RANGED", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Crossbow" },

    -- GUNS
    [18860] = { slot = "RANGED", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Hand Cannon" },
    [18861] = { slot = "RANGED", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Street Sweeper" },

    -- WANDS
    [18868] = { slot = "RANGED", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Tome of Power" },
    [18842] = { slot = "RANGED", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Tome of Destruction" },

    -- SHIELDS
    [18825] = { slot = "OFF_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Aegis" },
    [18829] = { slot = "OFF_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Shield Wall" },

    --[[
    ============================================================================
    PREPATCH PVP ACCESSORIES - Cloaks and Necklaces
    TBC Prepatch costs: Estimated 2805 honor based on similar accessories
    ============================================================================
    --]]

    -- SERGEANT'S CLOAKS (Rank 3 - Available to all)
    [18440] = { slot = "BACK", class = nil, honor = 1650, arena = 0, marks = nil, season = "PREPATCH", name = "Sergeant's Cloak" },

    -- KNIGHT-CAPTAIN/LEGIONNAIRE'S NECKLACES (Rank 7)
    [16059] = { slot = "NECK", class = nil, honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Legionnaire's Pendant" },
    [18457] = { slot = "NECK", class = nil, honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Knight-Captain's Pendant" },

    --[[
    ============================================================================
    PREPATCH RANK 10 BLUE SETS - Lieutenant Commander's / Champion's
    Alliance: Lieutenant Commander's Battlegear
    Horde: Champion's Battlegear
    TBC Prepatch costs: ~4950 honor + 2 marks per piece
    ============================================================================
    --]]

    -- WARRIOR - Lieutenant Commander's Battlegear (Alliance)
    [16428] = { slot = "HEAD", class = "WARRIOR", honor = 4950, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Plate Helm" },
    [16430] = { slot = "SHOULDER", class = "WARRIOR", honor = 3960, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Plate Shoulders" },
    [16429] = { slot = "CHEST", class = "WARRIOR", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Plate Hauberk" },
    [16431] = { slot = "HANDS", class = "WARRIOR", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Plate Gauntlets" },
    [16432] = { slot = "LEGS", class = "WARRIOR", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Plate Legguards" },
    [16433] = { slot = "FEET", class = "WARRIOR", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Plate Boots" },

    -- WARRIOR - Champion's Battlegear (Horde)
    [16514] = { slot = "HEAD", class = "WARRIOR", honor = 4950, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Champion's Plate Helm" },
    [16516] = { slot = "SHOULDER", class = "WARRIOR", honor = 3960, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Plate Shoulders" },
    [16515] = { slot = "CHEST", class = "WARRIOR", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Plate Hauberk" },
    [16513] = { slot = "HANDS", class = "WARRIOR", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Plate Gauntlets" },
    [16510] = { slot = "LEGS", class = "WARRIOR", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Plate Legguards" },
    [16509] = { slot = "FEET", class = "WARRIOR", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Plate Boots" },

    -- PALADIN - Lieutenant Commander's Aegis (Alliance)
    [16434] = { slot = "HEAD", class = "PALADIN", honor = 4950, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Lamellar Headguard" },
    [16436] = { slot = "SHOULDER", class = "PALADIN", honor = 3960, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Lamellar Shoulders" },
    [16435] = { slot = "CHEST", class = "PALADIN", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Lamellar Breastplate" },
    [16437] = { slot = "HANDS", class = "PALADIN", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Lamellar Gauntlets" },
    [16438] = { slot = "LEGS", class = "PALADIN", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Lamellar Leggings" },
    [16439] = { slot = "FEET", class = "PALADIN", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Lamellar Sabatons" },

    -- HUNTER - Lieutenant Commander's Pursuance (Alliance)
    [16424] = { slot = "HEAD", class = "HUNTER", honor = 4950, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Chain Helm" },
    [16426] = { slot = "SHOULDER", class = "HUNTER", honor = 3960, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Chain Shoulders" },
    [16425] = { slot = "CHEST", class = "HUNTER", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Chain Hauberk" },
    [16401] = { slot = "HANDS", class = "HUNTER", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Chain Gauntlets" },
    [16427] = { slot = "LEGS", class = "HUNTER", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Chain Legguards" },
    [16403] = { slot = "FEET", class = "HUNTER", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Chain Sabatons" },

    -- HUNTER - Champion's Pursuance (Horde)
    [16526] = { slot = "HEAD", class = "HUNTER", honor = 4950, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Champion's Chain Helm" },
    [16528] = { slot = "SHOULDER", class = "HUNTER", honor = 3960, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Chain Shoulders" },
    [16525] = { slot = "CHEST", class = "HUNTER", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Chain Hauberk" },
    [16530] = { slot = "HANDS", class = "HUNTER", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Chain Gauntlets" },
    [16527] = { slot = "LEGS", class = "HUNTER", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Chain Legguards" },
    [16529] = { slot = "FEET", class = "HUNTER", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Chain Boots" },

    -- SHAMAN - Champion's Stormcaller (Horde)
    [16522] = { slot = "HEAD", class = "SHAMAN", honor = 4950, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Champion's Mail Helm" },
    [16524] = { slot = "SHOULDER", class = "SHAMAN", honor = 3960, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Mail Shoulders" },
    [16521] = { slot = "CHEST", class = "SHAMAN", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Mail Hauberk" },
    [16519] = { slot = "HANDS", class = "SHAMAN", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Mail Gauntlets" },
    [16523] = { slot = "LEGS", class = "SHAMAN", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Mail Leggings" },
    [16518] = { slot = "FEET", class = "SHAMAN", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Mail Boots" },

    -- ROGUE - Lieutenant Commander's Vestments (Alliance)
    [16406] = { slot = "HEAD", class = "ROGUE", honor = 4950, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Leather Helm" },
    [16408] = { slot = "SHOULDER", class = "ROGUE", honor = 3960, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Leather Shoulders" },
    [16405] = { slot = "CHEST", class = "ROGUE", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Leather Hauberk" },
    [16409] = { slot = "HANDS", class = "ROGUE", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Leather Vambraces" },
    [16407] = { slot = "LEGS", class = "ROGUE", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Leather Legguards" },
    [16410] = { slot = "FEET", class = "ROGUE", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Leather Footguards" },

    -- ROGUE - Champion's Vestments (Horde)
    [16498] = { slot = "HEAD", class = "ROGUE", honor = 4950, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Champion's Leather Helm" },
    [16507] = { slot = "SHOULDER", class = "ROGUE", honor = 3960, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Leather Shoulders" },
    [16505] = { slot = "CHEST", class = "ROGUE", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Leather Hauberk" },
    [16499] = { slot = "HANDS", class = "ROGUE", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Leather Vambraces" },
    [16506] = { slot = "LEGS", class = "ROGUE", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Leather Legguards" },
    [16508] = { slot = "FEET", class = "ROGUE", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Leather Boots" },

    -- DRUID - Lieutenant Commander's Sanctuary (Alliance)
    [16420] = { slot = "HEAD", class = "DRUID", honor = 4950, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Dragonhide Headguard" },
    [16422] = { slot = "SHOULDER", class = "DRUID", honor = 3960, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Dragonhide Shoulders" },
    [16419] = { slot = "CHEST", class = "DRUID", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Dragonhide Breastplate" },
    [16423] = { slot = "HANDS", class = "DRUID", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Dragonhide Gloves" },
    [16421] = { slot = "LEGS", class = "DRUID", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Dragonhide Trousers" },
    [16418] = { slot = "FEET", class = "DRUID", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Dragonhide Footguards" },

    -- DRUID - Champion's Sanctuary (Horde)
    [16494] = { slot = "HEAD", class = "DRUID", honor = 4950, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Champion's Dragonhide Helm" },
    [16496] = { slot = "SHOULDER", class = "DRUID", honor = 3960, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Dragonhide Shoulders" },
    [16493] = { slot = "CHEST", class = "DRUID", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Dragonhide Breastplate" },
    [16497] = { slot = "HANDS", class = "DRUID", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Dragonhide Gloves" },
    [16495] = { slot = "LEGS", class = "DRUID", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Dragonhide Leggings" },
    [16492] = { slot = "FEET", class = "DRUID", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Dragonhide Footguards" },

    -- MAGE - Lieutenant Commander's Arcanum (Alliance)
    [16414] = { slot = "HEAD", class = "MAGE", honor = 4950, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Silk Cowl" },
    [16416] = { slot = "SHOULDER", class = "MAGE", honor = 3960, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Silk Mantle" },
    [16413] = { slot = "CHEST", class = "MAGE", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Silk Robes" },
    [16415] = { slot = "HANDS", class = "MAGE", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Silk Gloves" },
    [16417] = { slot = "LEGS", class = "MAGE", honor = 4950, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Silk Trousers" },
    [16411] = { slot = "FEET", class = "MAGE", honor = 3300, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Silk Boots" },

    -- MAGE - Champion's Arcanum (Horde)
    [16489] = { slot = "HEAD", class = "MAGE", honor = 4335, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Champion's Silk Cowl" },
    [16491] = { slot = "SHOULDER", class = "MAGE", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Silk Mantle" },
    [16487] = { slot = "CHEST", class = "MAGE", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Champion's Silk Robes" },
    [16488] = { slot = "HANDS", class = "MAGE", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Silk Gloves" },
    [16490] = { slot = "LEGS", class = "MAGE", honor = 4335, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Champion's Silk Trousers" },
    [16486] = { slot = "FEET", class = "MAGE", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Silk Footwraps" },

    -- NOTE: Rank 10 Warlock/Priest sets removed due to ID conflicts with rank 12-13 epic sets
    -- The 17XXX IDs are shared between blue and epic versions in Classic
    -- If rank 10 sets need to be added, they require verified unique item IDs

}

-- Helper functions for filtering

-- Get items by slot
function HonorLog:GetGearBySlot(slot)
    local items = {}
    for itemID, data in pairs(self.GearDB) do
        if data.slot == slot then
            items[itemID] = data
        end
    end
    return items
end

-- Get items by class (nil = any class can use)
function HonorLog:GetGearByClass(class)
    local items = {}
    for itemID, data in pairs(self.GearDB) do
        if data.class == nil or data.class == class then
            items[itemID] = data
        end
    end
    return items
end

-- Get items by season
function HonorLog:GetGearBySeason(season)
    local items = {}
    for itemID, data in pairs(self.GearDB) do
        if data.season == season then
            items[itemID] = data
        end
    end
    return items
end

-- Get honor-only items (no arena points required)
function HonorLog:GetHonorOnlyGear()
    local items = {}
    for itemID, data in pairs(self.GearDB) do
        if data.arena == 0 then
            items[itemID] = data
        end
    end
    return items
end

-- Get arena gear (requires arena points)
function HonorLog:GetArenaGear()
    local items = {}
    for itemID, data in pairs(self.GearDB) do
        if data.arena > 0 then
            items[itemID] = data
        end
    end
    return items
end

-- Get items that require marks
function HonorLog:GetMarkGear()
    local items = {}
    for itemID, data in pairs(self.GearDB) do
        if data.marks and next(data.marks) then
            items[itemID] = data
        end
    end
    return items
end

-- Get item by ID
function HonorLog:GetGearItem(itemID)
    return self.GearDB[itemID]
end

-- Get usable items for current player class
function HonorLog:GetUsableGear()
    local _, playerClass = UnitClass("player")
    return self:GetGearByClass(playerClass)
end

-- Search items by name (partial match)
function HonorLog:SearchGear(searchText)
    local items = {}
    searchText = searchText:lower()
    for itemID, data in pairs(self.GearDB) do
        if data.name and data.name:lower():find(searchText, 1, true) then
            items[itemID] = data
        end
    end
    return items
end

-- Get database statistics
function HonorLog:GetGearDBStats()
    local stats = {
        total = 0,
        bySlot = {},
        byClass = {},
        bySeason = {},
        honorOnly = 0,
        arenaRequired = 0,
        marksRequired = 0,
    }

    for itemID, data in pairs(self.GearDB) do
        stats.total = stats.total + 1

        -- Count by slot
        stats.bySlot[data.slot] = (stats.bySlot[data.slot] or 0) + 1

        -- Count by class
        local classKey = data.class or "ANY"
        stats.byClass[classKey] = (stats.byClass[classKey] or 0) + 1

        -- Count by season
        if data.season then
            stats.bySeason[data.season] = (stats.bySeason[data.season] or 0) + 1
        else
            stats.bySeason["HONOR"] = (stats.bySeason["HONOR"] or 0) + 1
        end

        -- Count by currency type
        if data.arena == 0 then
            stats.honorOnly = stats.honorOnly + 1
        else
            stats.arenaRequired = stats.arenaRequired + 1
        end

        if data.marks and next(data.marks) then
            stats.marksRequired = stats.marksRequired + 1
        end
    end

    return stats
end
