-- HonorLog Gear Database
-- TBC Classic PvP gear with VERIFIED itemIDs from Wowhead and in-game vendor scans
-- Last updated: 2025-01-27

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
    PREPATCH HONOR GEAR - EPIC (Rank 12-14 equivalent)
    Costs follow pattern: HEAD/CHEST/LEGS = 13005-13770 honor, SHOULDER/HANDS/FEET = 8415 honor
    ============================================================================
    --]]

    -- =========================================================================
    -- WARRIOR - EPIC SETS
    -- =========================================================================

    -- WARRIOR - Field Marshal's Battlegear (Alliance, set 384)
    [16478] = { slot = "HEAD", class = "WARRIOR", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Field Marshal's Plate Helm" },
    [16480] = { slot = "SHOULDER", class = "WARRIOR", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Field Marshal's Plate Shoulderguards" },
    [16477] = { slot = "CHEST", class = "WARRIOR", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Field Marshal's Plate Armor" },
    [16484] = { slot = "HANDS", class = "WARRIOR", honor = 8415, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Marshal's Plate Gauntlets" },
    [16479] = { slot = "LEGS", class = "WARRIOR", honor = 13005, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Marshal's Plate Legguards" },
    [16483] = { slot = "FEET", class = "WARRIOR", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Plate Boots" },

    -- WARRIOR - Warlord's Battlegear (Horde, set 383)
    [16542] = { slot = "HEAD", class = "WARRIOR", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Warlord's Plate Headpiece" },
    [16544] = { slot = "SHOULDER", class = "WARRIOR", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Warlord's Plate Shoulders" },
    [16541] = { slot = "CHEST", class = "WARRIOR", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Warlord's Plate Armor" },
    [16548] = { slot = "HANDS", class = "WARRIOR", honor = 8415, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "General's Plate Gauntlets" },
    [16543] = { slot = "LEGS", class = "WARRIOR", honor = 13005, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "General's Plate Leggings" },
    [16545] = { slot = "FEET", class = "WARRIOR", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Plate Boots" },

    -- =========================================================================
    -- PALADIN - EPIC SETS
    -- =========================================================================

    -- PALADIN - Field Marshal's Aegis (Alliance, set 402)
    [16474] = { slot = "HEAD", class = "PALADIN", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Field Marshal's Lamellar Faceguard" },
    [16476] = { slot = "SHOULDER", class = "PALADIN", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Field Marshal's Lamellar Pauldrons" },
    [16473] = { slot = "CHEST", class = "PALADIN", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Field Marshal's Lamellar Chestplate" },
    [16471] = { slot = "HANDS", class = "PALADIN", honor = 8415, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Marshal's Lamellar Gloves" },
    [16475] = { slot = "LEGS", class = "PALADIN", honor = 13005, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Marshal's Lamellar Legplates" },
    [16472] = { slot = "FEET", class = "PALADIN", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Lamellar Boots" },

    -- =========================================================================
    -- HUNTER - EPIC SETS
    -- =========================================================================

    -- HUNTER - Field Marshal's Pursuit (Alliance, set 395)
    [16465] = { slot = "HEAD", class = "HUNTER", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Field Marshal's Chain Helm" },
    [16468] = { slot = "SHOULDER", class = "HUNTER", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Field Marshal's Chain Spaulders" },
    [16466] = { slot = "CHEST", class = "HUNTER", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Field Marshal's Chain Breastplate" },
    [16463] = { slot = "HANDS", class = "HUNTER", honor = 8415, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Marshal's Chain Grips" },
    [16467] = { slot = "LEGS", class = "HUNTER", honor = 13005, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Marshal's Chain Legguards" },
    [16462] = { slot = "FEET", class = "HUNTER", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Chain Boots" },

    -- HUNTER - Warlord's Pursuit (Horde, set 396)
    [16566] = { slot = "HEAD", class = "HUNTER", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Warlord's Chain Helmet" },
    [16568] = { slot = "SHOULDER", class = "HUNTER", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Warlord's Chain Shoulders" },
    [16565] = { slot = "CHEST", class = "HUNTER", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Warlord's Chain Chestpiece" },
    [16571] = { slot = "HANDS", class = "HUNTER", honor = 8415, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "General's Chain Gloves" },
    [16567] = { slot = "LEGS", class = "HUNTER", honor = 13005, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "General's Chain Legguards" },
    [16569] = { slot = "FEET", class = "HUNTER", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Chain Boots" },

    -- =========================================================================
    -- SHAMAN - EPIC SETS
    -- =========================================================================

    -- SHAMAN - Warlord's Earthshaker (Horde, set 386)
    [16578] = { slot = "HEAD", class = "SHAMAN", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Warlord's Mail Helm" },
    [16580] = { slot = "SHOULDER", class = "SHAMAN", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Warlord's Mail Spaulders" },
    [16577] = { slot = "CHEST", class = "SHAMAN", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Warlord's Mail Armor" },
    [16574] = { slot = "HANDS", class = "SHAMAN", honor = 8415, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "General's Mail Gauntlets" },
    [16579] = { slot = "LEGS", class = "SHAMAN", honor = 13005, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "General's Mail Leggings" },
    [16573] = { slot = "FEET", class = "SHAMAN", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Mail Boots" },

    -- =========================================================================
    -- ROGUE - EPIC SETS
    -- =========================================================================

    -- ROGUE - Field Marshal's Vestments (Alliance, set 394)
    [16455] = { slot = "HEAD", class = "ROGUE", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Field Marshal's Leather Mask" },
    [16457] = { slot = "SHOULDER", class = "ROGUE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Field Marshal's Leather Epaulets" },
    [16453] = { slot = "CHEST", class = "ROGUE", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Field Marshal's Leather Chestpiece" },
    [16454] = { slot = "HANDS", class = "ROGUE", honor = 8415, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Marshal's Leather Handgrips" },
    [16456] = { slot = "LEGS", class = "ROGUE", honor = 13005, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Marshal's Leather Leggings" },
    [16446] = { slot = "FEET", class = "ROGUE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Leather Footguards" },

    -- ROGUE - Warlord's Vestments (Horde, set 393)
    [16561] = { slot = "HEAD", class = "ROGUE", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Warlord's Leather Helm" },
    [16562] = { slot = "SHOULDER", class = "ROGUE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Warlord's Leather Spaulders" },
    [16563] = { slot = "CHEST", class = "ROGUE", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Warlord's Leather Breastplate" },
    [16560] = { slot = "HANDS", class = "ROGUE", honor = 8415, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "General's Leather Mitts" },
    [16564] = { slot = "LEGS", class = "ROGUE", honor = 13005, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "General's Leather Legguards" },
    [16558] = { slot = "FEET", class = "ROGUE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Leather Treads" },

    -- =========================================================================
    -- PRIEST - EPIC SETS
    -- =========================================================================

    -- PRIEST - Field Marshal's Raiment (Alliance, set 389)
    [17602] = { slot = "HEAD", class = "PRIEST", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Field Marshal's Headdress" },
    [17604] = { slot = "SHOULDER", class = "PRIEST", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Field Marshal's Satin Mantle" },
    [17605] = { slot = "CHEST", class = "PRIEST", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Field Marshal's Satin Vestments" },
    [17608] = { slot = "HANDS", class = "PRIEST", honor = 8415, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Marshal's Satin Gloves" },
    [17603] = { slot = "LEGS", class = "PRIEST", honor = 13005, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Marshal's Satin Pants" },
    [17607] = { slot = "FEET", class = "PRIEST", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Satin Sandals" },

    -- PRIEST - Warlord's Raiment (Horde, set 390)
    [17623] = { slot = "HEAD", class = "PRIEST", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Warlord's Satin Cowl" },
    [17622] = { slot = "SHOULDER", class = "PRIEST", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Warlord's Satin Mantle" },
    [17624] = { slot = "CHEST", class = "PRIEST", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Warlord's Satin Robes" },
    [17620] = { slot = "HANDS", class = "PRIEST", honor = 8415, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "General's Satin Gloves" },
    [17625] = { slot = "LEGS", class = "PRIEST", honor = 13005, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "General's Satin Leggings" },
    [17618] = { slot = "FEET", class = "PRIEST", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Satin Boots" },

    -- =========================================================================
    -- MAGE - EPIC SETS (Verified from vendor scan)
    -- =========================================================================

    -- MAGE - Field Marshal's Regalia (Alliance, set 388)
    [16441] = { slot = "HEAD", class = "MAGE", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Field Marshal's Silk Cowl" },
    [16444] = { slot = "SHOULDER", class = "MAGE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Field Marshal's Silk Spaulders" },
    [16443] = { slot = "CHEST", class = "MAGE", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Field Marshal's Silk Vestments" },
    [16440] = { slot = "HANDS", class = "MAGE", honor = 8415, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Marshal's Silk Gloves" },
    [16442] = { slot = "LEGS", class = "MAGE", honor = 13005, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Marshal's Silk Leggings" },
    [16437] = { slot = "FEET", class = "MAGE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Silk Footwraps" },

    -- MAGE - Warlord's Regalia (Horde, set 387) - VERIFIED FROM VENDOR SCAN
    [16533] = { slot = "HEAD", class = "MAGE", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Warlord's Silk Cowl" },
    [16536] = { slot = "SHOULDER", class = "MAGE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Warlord's Silk Amice" },
    [16535] = { slot = "CHEST", class = "MAGE", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Warlord's Silk Raiment" },
    [16540] = { slot = "HANDS", class = "MAGE", honor = 8415, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "General's Silk Handguards" },
    [16534] = { slot = "LEGS", class = "MAGE", honor = 13005, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "General's Silk Trousers" },
    [16539] = { slot = "FEET", class = "MAGE", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Silk Boots" },

    -- =========================================================================
    -- WARLOCK - EPIC SETS
    -- =========================================================================

    -- WARLOCK - Field Marshal's Threads (Alliance, set 392)
    [17578] = { slot = "HEAD", class = "WARLOCK", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Field Marshal's Dreadweave Hood" },
    [17580] = { slot = "SHOULDER", class = "WARLOCK", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Field Marshal's Dreadweave Shoulders" },
    [17581] = { slot = "CHEST", class = "WARLOCK", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Field Marshal's Dreadweave Robe" },
    [17584] = { slot = "HANDS", class = "WARLOCK", honor = 8415, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Marshal's Dreadweave Gloves" },
    [17579] = { slot = "LEGS", class = "WARLOCK", honor = 13005, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Marshal's Dreadweave Leggings" },
    [17583] = { slot = "FEET", class = "WARLOCK", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Dreadweave Boots" },

    -- WARLOCK - Warlord's Threads (Horde, set 391)
    [17591] = { slot = "HEAD", class = "WARLOCK", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Warlord's Dreadweave Hood" },
    [17590] = { slot = "SHOULDER", class = "WARLOCK", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Warlord's Dreadweave Mantle" },
    [17592] = { slot = "CHEST", class = "WARLOCK", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Warlord's Dreadweave Robe" },
    [17588] = { slot = "HANDS", class = "WARLOCK", honor = 8415, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "General's Dreadweave Gloves" },
    [17593] = { slot = "LEGS", class = "WARLOCK", honor = 13005, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "General's Dreadweave Pants" },
    [17586] = { slot = "FEET", class = "WARLOCK", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Dreadweave Boots" },

    -- =========================================================================
    -- DRUID - EPIC SETS
    -- =========================================================================

    -- DRUID - Field Marshal's Sanctuary (Alliance, set 397)
    [16451] = { slot = "HEAD", class = "DRUID", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Field Marshal's Dragonhide Helmet" },
    [16449] = { slot = "SHOULDER", class = "DRUID", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Field Marshal's Dragonhide Spaulders" },
    [16452] = { slot = "CHEST", class = "DRUID", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Field Marshal's Dragonhide Breastplate" },
    [16448] = { slot = "HANDS", class = "DRUID", honor = 8415, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Marshal's Dragonhide Gauntlets" },
    [16450] = { slot = "LEGS", class = "DRUID", honor = 13005, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Marshal's Dragonhide Legguards" },
    [16459] = { slot = "FEET", class = "DRUID", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Marshal's Dragonhide Boots" },

    -- DRUID - Warlord's Sanctuary (Horde, set 398)
    [16550] = { slot = "HEAD", class = "DRUID", honor = 13005, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Warlord's Dragonhide Helmet" },
    [16551] = { slot = "SHOULDER", class = "DRUID", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Warlord's Dragonhide Epaulets" },
    [16549] = { slot = "CHEST", class = "DRUID", honor = 13770, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Warlord's Dragonhide Hauberk" },
    [16555] = { slot = "HANDS", class = "DRUID", honor = 8415, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "General's Dragonhide Gloves" },
    [16552] = { slot = "LEGS", class = "DRUID", honor = 13005, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "General's Dragonhide Leggings" },
    [16554] = { slot = "FEET", class = "DRUID", honor = 8415, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "General's Dragonhide Boots" },

    --[[
    ============================================================================
    PREPATCH HONOR GEAR - RARE (Rank 7-10 equivalent)
    Costs follow pattern: HEAD/CHEST/LEGS = 4335-4590 honor, SHOULDER/HANDS/FEET = 2805 honor
    ============================================================================
    --]]

    -- =========================================================================
    -- WARRIOR - RARE SETS
    -- =========================================================================

    -- WARRIOR - Lieutenant Commander's Battlearmor (Alliance, set 545)
    [23314] = { slot = "HEAD", class = "WARRIOR", honor = 4335, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Lieutenant Commander's Plate Helm" },
    [23315] = { slot = "SHOULDER", class = "WARRIOR", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Plate Pauldrons" },
    [23300] = { slot = "CHEST", class = "WARRIOR", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Knight-Captain's Plate Hauberk" },
    [23286] = { slot = "HANDS", class = "WARRIOR", honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Knight-Lieutenant's Plate Gauntlets" },
    [23301] = { slot = "LEGS", class = "WARRIOR", honor = 4335, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Knight-Captain's Plate Leggings" },
    [23287] = { slot = "FEET", class = "WARRIOR", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Knight-Lieutenant's Plate Greaves" },

    -- WARRIOR - Champion's Battlearmor (Horde, set 537)
    [23244] = { slot = "HEAD", class = "WARRIOR", honor = 4335, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Champion's Plate Headguard" },
    [23243] = { slot = "SHOULDER", class = "WARRIOR", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Plate Pauldrons" },
    [22872] = { slot = "CHEST", class = "WARRIOR", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Legionnaire's Plate Hauberk" },
    [22868] = { slot = "HANDS", class = "WARRIOR", honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Blood Guard's Plate Gauntlets" },
    [22873] = { slot = "LEGS", class = "WARRIOR", honor = 4335, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Legionnaire's Plate Leggings" },
    [22858] = { slot = "FEET", class = "WARRIOR", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Blood Guard's Plate Greaves" },

    -- =========================================================================
    -- PALADIN - RARE SETS
    -- =========================================================================

    -- PALADIN - Lieutenant Commander's Redoubt (Alliance, set 544)
    [23276] = { slot = "HEAD", class = "PALADIN", honor = 4335, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Lieutenant Commander's Lamellar Headguard" },
    [23277] = { slot = "SHOULDER", class = "PALADIN", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Lamellar Shoulders" },
    [23272] = { slot = "CHEST", class = "PALADIN", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Knight-Captain's Lamellar Breastplate" },
    [23274] = { slot = "HANDS", class = "PALADIN", honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Knight-Lieutenant's Lamellar Gauntlets" },
    [23273] = { slot = "LEGS", class = "PALADIN", honor = 4335, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Knight-Captain's Lamellar Leggings" },
    [23275] = { slot = "FEET", class = "PALADIN", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Knight-Lieutenant's Lamellar Sabatons" },

    -- =========================================================================
    -- HUNTER - RARE SETS
    -- =========================================================================

    -- HUNTER - Lieutenant Commander's Pursuance (Alliance, set 550)
    [23306] = { slot = "HEAD", class = "HUNTER", honor = 4335, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Lieutenant Commander's Chain Helm" },
    [23307] = { slot = "SHOULDER", class = "HUNTER", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Chain Pauldrons" },
    [23292] = { slot = "CHEST", class = "HUNTER", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Knight-Captain's Chain Hauberk" },
    [23279] = { slot = "HANDS", class = "HUNTER", honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Knight-Lieutenant's Chain Gauntlets" },
    [23293] = { slot = "LEGS", class = "HUNTER", honor = 4335, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Knight-Captain's Chain Legguards" },
    [23278] = { slot = "FEET", class = "HUNTER", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Knight-Lieutenant's Chain Greaves" },

    -- HUNTER - Champion's Pursuance (Horde, set 543)
    [23251] = { slot = "HEAD", class = "HUNTER", honor = 4335, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Champion's Chain Headguard" },
    [23252] = { slot = "SHOULDER", class = "HUNTER", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Chain Pauldrons" },
    [22874] = { slot = "CHEST", class = "HUNTER", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Legionnaire's Chain Hauberk" },
    [22862] = { slot = "HANDS", class = "HUNTER", honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Blood Guard's Chain Gauntlets" },
    [22875] = { slot = "LEGS", class = "HUNTER", honor = 4335, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Legionnaire's Chain Leggings" },
    [22843] = { slot = "FEET", class = "HUNTER", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Blood Guard's Chain Greaves" },

    -- =========================================================================
    -- SHAMAN - RARE SETS
    -- =========================================================================

    -- SHAMAN - Champion's Stormcaller (Horde, set 538)
    [23259] = { slot = "HEAD", class = "SHAMAN", honor = 4335, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Champion's Mail Headguard" },
    [23260] = { slot = "SHOULDER", class = "SHAMAN", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Mail Pauldrons" },
    [22876] = { slot = "CHEST", class = "SHAMAN", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Legionnaire's Mail Hauberk" },
    [22867] = { slot = "HANDS", class = "SHAMAN", honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Blood Guard's Mail Gauntlets" },
    [22887] = { slot = "LEGS", class = "SHAMAN", honor = 4335, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Legionnaire's Mail Leggings" },
    [22857] = { slot = "FEET", class = "SHAMAN", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Blood Guard's Mail Greaves" },

    -- =========================================================================
    -- ROGUE - RARE SETS
    -- =========================================================================

    -- ROGUE - Lieutenant Commander's Guard (Alliance, set 548)
    [23312] = { slot = "HEAD", class = "ROGUE", honor = 4335, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Lieutenant Commander's Leather Helm" },
    [23313] = { slot = "SHOULDER", class = "ROGUE", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Leather Shoulders" },
    [23298] = { slot = "CHEST", class = "ROGUE", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Knight-Captain's Leather Chestpiece" },
    [23284] = { slot = "HANDS", class = "ROGUE", honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Knight-Lieutenant's Leather Gauntlets" },
    [23299] = { slot = "LEGS", class = "ROGUE", honor = 4335, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Knight-Captain's Leather Legguards" },
    [23285] = { slot = "FEET", class = "ROGUE", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Knight-Lieutenant's Leather Walkers" },

    -- ROGUE - Champion's Guard (Horde, set 522)
    [23257] = { slot = "HEAD", class = "ROGUE", honor = 4335, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Champion's Leather Headguard" },
    [23258] = { slot = "SHOULDER", class = "ROGUE", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Leather Mantle" },
    [22879] = { slot = "CHEST", class = "ROGUE", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Legionnaire's Leather Chestpiece" },
    [22864] = { slot = "HANDS", class = "ROGUE", honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Blood Guard's Leather Treads" },
    [22880] = { slot = "LEGS", class = "ROGUE", honor = 4335, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Legionnaire's Leather Leggings" },
    [22856] = { slot = "FEET", class = "ROGUE", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Blood Guard's Leather Vices" },

    -- =========================================================================
    -- PRIEST - RARE SETS
    -- =========================================================================

    -- PRIEST - Lieutenant Commander's Investiture (Alliance, set 549)
    [23316] = { slot = "HEAD", class = "PRIEST", honor = 4335, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Lieutenant Commander's Satin Hood" },
    [23317] = { slot = "SHOULDER", class = "PRIEST", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Satin Mantle" },
    [23303] = { slot = "CHEST", class = "PRIEST", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Knight-Captain's Satin Tunic" },
    [23288] = { slot = "HANDS", class = "PRIEST", honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Knight-Lieutenant's Satin Handwraps" },
    [23302] = { slot = "LEGS", class = "PRIEST", honor = 4335, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Knight-Captain's Satin Legguards" },
    [23289] = { slot = "FEET", class = "PRIEST", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Knight-Lieutenant's Satin Walkers" },

    -- PRIEST - Champion's Investiture (Horde, set 540)
    [23261] = { slot = "HEAD", class = "PRIEST", honor = 4335, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Champion's Satin Cowl" },
    [23262] = { slot = "SHOULDER", class = "PRIEST", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Satin Shoulderpads" },
    [22885] = { slot = "CHEST", class = "PRIEST", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Legionnaire's Satin Vestments" },
    [22869] = { slot = "HANDS", class = "PRIEST", honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Blood Guard's Satin Gloves" },
    [22882] = { slot = "LEGS", class = "PRIEST", honor = 4335, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Legionnaire's Satin Trousers" },
    [22859] = { slot = "FEET", class = "PRIEST", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Blood Guard's Satin Walkers" },

    -- =========================================================================
    -- MAGE - RARE SETS (Verified from vendor scan)
    -- =========================================================================

    -- MAGE - Lieutenant Commander's Arcanum (Alliance, set 546)
    [23318] = { slot = "HEAD", class = "MAGE", honor = 4335, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Lieutenant Commander's Silk Cowl" },
    [23319] = { slot = "SHOULDER", class = "MAGE", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Silk Mantle" },
    [23305] = { slot = "CHEST", class = "MAGE", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Knight-Captain's Silk Tunic" },
    [23290] = { slot = "HANDS", class = "MAGE", honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Knight-Lieutenant's Silk Handwraps" },
    [23304] = { slot = "LEGS", class = "MAGE", honor = 4335, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Knight-Captain's Silk Legguards" },
    [23291] = { slot = "FEET", class = "MAGE", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Knight-Lieutenant's Silk Walkers" },

    -- MAGE - Champion's Arcanum (Horde, set 542) - VERIFIED FROM VENDOR SCAN
    [23263] = { slot = "HEAD", class = "MAGE", honor = 4335, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Champion's Silk Cowl" },
    [23264] = { slot = "SHOULDER", class = "MAGE", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Silk Mantle" },
    [22886] = { slot = "CHEST", class = "MAGE", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Legionnaire's Silk Tunic" },
    [22870] = { slot = "HANDS", class = "MAGE", honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Blood Guard's Silk Handwraps" },
    [22883] = { slot = "LEGS", class = "MAGE", honor = 4335, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Legionnaire's Silk Legguards" },
    [22860] = { slot = "FEET", class = "MAGE", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Blood Guard's Silk Walkers" },

    -- =========================================================================
    -- WARLOCK - RARE SETS
    -- =========================================================================

    -- WARLOCK - Lieutenant Commander's Dreadgear (Alliance, set 547)
    [23310] = { slot = "HEAD", class = "WARLOCK", honor = 4335, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Lieutenant Commander's Dreadweave Cowl" },
    [23311] = { slot = "SHOULDER", class = "WARLOCK", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Dreadweave Mantle" },
    [23297] = { slot = "CHEST", class = "WARLOCK", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Knight-Captain's Dreadweave Tunic" },
    [23282] = { slot = "HANDS", class = "WARLOCK", honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Knight-Lieutenant's Dreadweave Handwraps" },
    [23296] = { slot = "LEGS", class = "WARLOCK", honor = 4335, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Knight-Captain's Dreadweave Legguards" },
    [23283] = { slot = "FEET", class = "WARLOCK", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Knight-Lieutenant's Dreadweave Walkers" },

    -- WARLOCK - Champion's Dreadgear (Horde, set 541)
    [23255] = { slot = "HEAD", class = "WARLOCK", honor = 4335, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Champion's Dreadweave Cowl" },
    [23256] = { slot = "SHOULDER", class = "WARLOCK", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Dreadweave Shoulders" },
    [22884] = { slot = "CHEST", class = "WARLOCK", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Legionnaire's Dreadweave Tunic" },
    [22865] = { slot = "HANDS", class = "WARLOCK", honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Blood Guard's Dreadweave Gloves" },
    [22881] = { slot = "LEGS", class = "WARLOCK", honor = 4335, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Legionnaire's Dreadweave Legguards" },
    [22855] = { slot = "FEET", class = "WARLOCK", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Blood Guard's Dreadweave Walkers" },

    -- =========================================================================
    -- DRUID - RARE SETS
    -- =========================================================================

    -- DRUID - Lieutenant Commander's Refuge (Alliance, set 551)
    [23308] = { slot = "HEAD", class = "DRUID", honor = 4335, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Lieutenant Commander's Dragonhide Headguard" },
    [23309] = { slot = "SHOULDER", class = "DRUID", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Dragonhide Shoulders" },
    [23294] = { slot = "CHEST", class = "DRUID", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Knight-Captain's Dragonhide Tunic" },
    [23280] = { slot = "HANDS", class = "DRUID", honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Knight-Lieutenant's Dragonhide Grips" },
    [23295] = { slot = "LEGS", class = "DRUID", honor = 4335, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Knight-Captain's Dragonhide Leggings" },
    [23281] = { slot = "FEET", class = "DRUID", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Knight-Lieutenant's Dragonhide Treads" },

    -- DRUID - Champion's Refuge (Horde, set 539)
    [23253] = { slot = "HEAD", class = "DRUID", honor = 4335, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Champion's Dragonhide Headguard" },
    [23254] = { slot = "SHOULDER", class = "DRUID", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Dragonhide Shoulders" },
    [22877] = { slot = "CHEST", class = "DRUID", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Legionnaire's Dragonhide Chestpiece" },
    [22863] = { slot = "HANDS", class = "DRUID", honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Blood Guard's Dragonhide Gauntlets" },
    [22878] = { slot = "LEGS", class = "DRUID", honor = 4335, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Legionnaire's Dragonhide Leggings" },
    [22852] = { slot = "FEET", class = "DRUID", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Blood Guard's Dragonhide Treads" },

    --[[
    ============================================================================
    PREPATCH ACCESSORIES - WRIST/CLOAK (All Classes)
    ============================================================================
    --]]

    -- CLOTH WRIST - First Sergeant's Silk Cuffs
    [16486] = { slot = "WRIST", class = nil, honor = 1530, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "First Sergeant's Silk Cuffs" },
    [18437] = { slot = "WRIST", class = nil, honor = 1530, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "First Sergeant's Silk Cuffs" },

    -- LEATHER WRIST - First Sergeant's Leather Armguards
    [16497] = { slot = "WRIST", class = nil, honor = 1530, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "First Sergeant's Leather Armguards" },
    [18435] = { slot = "WRIST", class = nil, honor = 1530, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "First Sergeant's Leather Armguards" },

    -- MAIL WRIST - First Sergeant's Mail Wristguards
    [16532] = { slot = "WRIST", class = nil, honor = 1530, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "First Sergeant's Mail Wristguards" },
    [18432] = { slot = "WRIST", class = nil, honor = 1530, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "First Sergeant's Mail Wristguards" },

    -- PLATE WRIST - First Sergeant's Plate Bracers
    [18429] = { slot = "WRIST", class = nil, honor = 1530, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "First Sergeant's Plate Bracers" },
    [18430] = { slot = "WRIST", class = nil, honor = 1530, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "First Sergeant's Plate Bracers" },

    -- DRAGONHIDE WRIST - First Sergeant's Dragonhide Armguards (Druid)
    [18434] = { slot = "WRIST", class = "DRUID", honor = 1530, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "First Sergeant's Dragonhide Armguards" },
    [18436] = { slot = "WRIST", class = "DRUID", honor = 1530, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "First Sergeant's Dragonhide Armguards" },

    -- ALL CLASSES - Sergeant's Cloak
    [16341] = { slot = "BACK", class = nil, honor = 1530, arena = 0, marks = { AB = 1 }, season = "PREPATCH", name = "Sergeant's Cloak" },
    [18427] = { slot = "BACK", class = nil, honor = 1530, arena = 0, marks = { AB = 1 }, season = "PREPATCH", name = "Sergeant's Cloak" },
    [18461] = { slot = "BACK", class = nil, honor = 1530, arena = 0, marks = { AB = 1 }, season = "PREPATCH", name = "Sergeant's Cloak" },

    --[[
    ============================================================================
    PREPATCH WEAPONS - High Warlord's / Grand Marshal's
    ============================================================================
    --]]

    -- GRAND MARSHAL'S WEAPONS (Alliance) - 7,935 honor (1H/OH/Ranged) or 15,870 honor (2H), no marks
    [18827] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Handaxe" },
    [18830] = { slot = "TWO_HAND", class = nil, honor = 15870, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Sunderer" },
    [18838] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Dirk" },
    [23451] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Mageblade" },
    [18843] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Right Hand Blade" },
    [18847] = { slot = "OFF_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Left Hand Blade" },
    [18865] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Punisher" },
    [23454] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Warhammer" },
    [23455] = { slot = "TWO_HAND", class = nil, honor = 15870, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Demolisher" },
    [18867] = { slot = "TWO_HAND", class = nil, honor = 15870, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Battle Hammer" },
    [12584] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Longsword" },
    [23456] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Swiftblade" },
    [18876] = { slot = "TWO_HAND", class = nil, honor = 15870, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Claymore" },
    [18869] = { slot = "TWO_HAND", class = nil, honor = 15870, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Glaive" },
    [18873] = { slot = "TWO_HAND", class = nil, honor = 15870, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Stave" },
    [18833] = { slot = "RANGED", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Bullseye" },
    [18836] = { slot = "RANGED", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Repeater" },
    [18855] = { slot = "RANGED", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Hand Cannon" },
    [18825] = { slot = "OFF_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Aegis" },
    [23452] = { slot = "OFF_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Tome of Power" },
    [23453] = { slot = "OFF_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "Grand Marshal's Tome of Restoration" },

    -- HIGH WARLORD'S WEAPONS (Horde) - 7,935 honor (1H/OH/Ranged) or 15,870 honor (2H), no marks
    [18828] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Cleaver" },
    [18831] = { slot = "TWO_HAND", class = nil, honor = 15870, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Battle Axe" },
    [18840] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Razor" },
    [23466] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Spellblade" },
    [18844] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Right Claw" },
    [18848] = { slot = "OFF_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Left Claw" },
    [18866] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Bludgeon" },
    [23464] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Battle Mace" },
    [23465] = { slot = "TWO_HAND", class = nil, honor = 15870, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Destroyer" },
    [18868] = { slot = "TWO_HAND", class = nil, honor = 15870, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Pulverizer" },
    [16345] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Blade" },
    [23467] = { slot = "MAIN_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Quickblade" },
    [18877] = { slot = "TWO_HAND", class = nil, honor = 15870, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Greatsword" },
    [18871] = { slot = "TWO_HAND", class = nil, honor = 15870, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Pig Sticker" },
    [18874] = { slot = "TWO_HAND", class = nil, honor = 15870, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's War Staff" },
    [18835] = { slot = "RANGED", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Recurve" },
    [18837] = { slot = "RANGED", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Crossbow" },
    [18860] = { slot = "RANGED", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Street Sweeper" },
    [18826] = { slot = "OFF_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Shield Wall" },
    [23468] = { slot = "OFF_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Tome of Destruction" },
    [23469] = { slot = "OFF_HAND", class = nil, honor = 7935, arena = 0, marks = nil, season = "PREPATCH", name = "High Warlord's Tome of Mending" },

    --[[
    ============================================================================
    PREPATCH INSIGNIAS (PvP Trinkets)
    ============================================================================
    --]]

    -- ALLIANCE INSIGNIAS
    [18854] = { slot = "TRINKET", class = "WARRIOR", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Alliance" },
    [18856] = { slot = "TRINKET", class = "HUNTER", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Alliance" },
    [18857] = { slot = "TRINKET", class = "ROGUE", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Alliance" },
    [18858] = { slot = "TRINKET", class = "WARLOCK", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Alliance" },
    [18862] = { slot = "TRINKET", class = "PRIEST", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Alliance" },
    [18863] = { slot = "TRINKET", class = "DRUID", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Alliance" },
    [18864] = { slot = "TRINKET", class = "PALADIN", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Alliance" },
    [18859] = { slot = "TRINKET", class = "MAGE", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Alliance" },

    -- HORDE INSIGNIAS
    [18834] = { slot = "TRINKET", class = "WARRIOR", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },
    [18846] = { slot = "TRINKET", class = "HUNTER", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },
    [18849] = { slot = "TRINKET", class = "ROGUE", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },
    [18852] = { slot = "TRINKET", class = "WARLOCK", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },
    [18851] = { slot = "TRINKET", class = "PRIEST", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },
    [18853] = { slot = "TRINKET", class = "DRUID", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },
    [18845] = { slot = "TRINKET", class = "SHAMAN", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },
    [18850] = { slot = "TRINKET", class = "MAGE", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },

    --[[
    ============================================================================
    WSG REPUTATION REWARDS - Horde (All Levels)
    ============================================================================
    --]]

    -- TABARD
    [19505] = { slot = "TABARD", class = nil, honor = 0, arena = 0, marks = { WSG = 60 }, season = "PREPATCH", name = "Warsong Battle Tabard" },

    -- RINGS - Legionnaire's Band (all levels)
    [19510] = { slot = "FINGER", class = nil, honor = 1530, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Legionnaire's Band" },
    [19511] = { slot = "FINGER", class = nil, honor = 208, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Legionnaire's Band" },
    [19512] = { slot = "FINGER", class = nil, honor = 141, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Legionnaire's Band" },
    [19513] = { slot = "FINGER", class = nil, honor = 95, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Legionnaire's Band" },
    [20429] = { slot = "FINGER", class = nil, honor = 65, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Legionnaire's Band" },

    -- RINGS - Advisor's Ring (all levels)
    [19518] = { slot = "FINGER", class = nil, honor = 1530, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Advisor's Ring" },
    [19519] = { slot = "FINGER", class = nil, honor = 208, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Advisor's Ring" },
    [19520] = { slot = "FINGER", class = nil, honor = 141, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Advisor's Ring" },
    [19521] = { slot = "FINGER", class = nil, honor = 95, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Advisor's Ring" },
    [20426] = { slot = "FINGER", class = nil, honor = 65, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Advisor's Ring" },

    -- NECK - Scout's Medallion (all levels)
    [19534] = { slot = "NECK", class = nil, honor = 1530, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Scout's Medallion" },
    [19535] = { slot = "NECK", class = nil, honor = 208, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Scout's Medallion" },
    [19536] = { slot = "NECK", class = nil, honor = 141, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Scout's Medallion" },
    [19537] = { slot = "NECK", class = nil, honor = 95, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Scout's Medallion" },
    [20442] = { slot = "NECK", class = nil, honor = 65, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Scout's Medallion" },

    -- BACK - Battle Healer's Cloak (all levels)
    [19526] = { slot = "BACK", class = nil, honor = 1530, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "Battle Healer's Cloak" },
    [19527] = { slot = "BACK", class = nil, honor = 208, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "Battle Healer's Cloak" },
    [19528] = { slot = "BACK", class = nil, honor = 141, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "Battle Healer's Cloak" },
    [19529] = { slot = "BACK", class = nil, honor = 95, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "Battle Healer's Cloak" },
    [20427] = { slot = "BACK", class = nil, honor = 65, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "Battle Healer's Cloak" },

    -- WRIST - Berserker Bracers (plate, all levels)
    [19578] = { slot = "WRIST", class = nil, honor = 4590, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Berserker Bracers" },
    [19580] = { slot = "WRIST", class = nil, honor = 624, arena = 0, marks = nil, season = "PREPATCH", name = "Berserker Bracers" },
    [19581] = { slot = "WRIST", class = nil, honor = 422, arena = 0, marks = nil, season = "PREPATCH", name = "Berserker Bracers" },

    -- WRIST - Windtalker's Wristguards (mail, all levels)
    [19582] = { slot = "WRIST", class = nil, honor = 4590, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Windtalker's Wristguards" },
    [19583] = { slot = "WRIST", class = nil, honor = 624, arena = 0, marks = nil, season = "PREPATCH", name = "Windtalker's Wristguards" },
    [19584] = { slot = "WRIST", class = nil, honor = 422, arena = 0, marks = nil, season = "PREPATCH", name = "Windtalker's Wristguards" },

    -- WRIST - Forest Stalker's Bracers (leather, all levels)
    [19587] = { slot = "WRIST", class = nil, honor = 4590, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Forest Stalker's Bracers" },
    [19589] = { slot = "WRIST", class = nil, honor = 624, arena = 0, marks = nil, season = "PREPATCH", name = "Forest Stalker's Bracers" },
    [19590] = { slot = "WRIST", class = nil, honor = 422, arena = 0, marks = nil, season = "PREPATCH", name = "Forest Stalker's Bracers" },

    -- WRIST - Dryad's Wrist Bindings (cloth, all levels)
    [19595] = { slot = "WRIST", class = nil, honor = 4590, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Dryad's Wrist Bindings" },
    [19596] = { slot = "WRIST", class = nil, honor = 624, arena = 0, marks = nil, season = "PREPATCH", name = "Dryad's Wrist Bindings" },
    [19597] = { slot = "WRIST", class = nil, honor = 422, arena = 0, marks = nil, season = "PREPATCH", name = "Dryad's Wrist Bindings" },

    -- WEAPONS - Scout's Blade (dagger, all levels)
    [19542] = { slot = "MAIN_HAND", class = nil, honor = 5100, arena = 0, marks = nil, season = "PREPATCH", name = "Scout's Blade" },
    [19543] = { slot = "MAIN_HAND", class = nil, honor = 694, arena = 0, marks = nil, season = "PREPATCH", name = "Scout's Blade" },
    [19544] = { slot = "MAIN_HAND", class = nil, honor = 469, arena = 0, marks = nil, season = "PREPATCH", name = "Scout's Blade" },
    [19545] = { slot = "MAIN_HAND", class = nil, honor = 316, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Scout's Blade" },
    [20441] = { slot = "MAIN_HAND", class = nil, honor = 214, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Scout's Blade" },

    -- WEAPONS - Legionnaire's Sword (2H sword, all levels)
    [19550] = { slot = "MAIN_HAND", class = nil, honor = 10200, arena = 0, marks = nil, season = "PREPATCH", name = "Legionnaire's Sword" },
    [19551] = { slot = "MAIN_HAND", class = nil, honor = 694, arena = 0, marks = nil, season = "PREPATCH", name = "Legionnaire's Sword" },
    [19552] = { slot = "MAIN_HAND", class = nil, honor = 469, arena = 0, marks = nil, season = "PREPATCH", name = "Legionnaire's Sword" },
    [19553] = { slot = "MAIN_HAND", class = nil, honor = 316, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Legionnaire's Sword" },
    [20430] = { slot = "MAIN_HAND", class = nil, honor = 214, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Legionnaire's Sword" },

    -- WEAPONS - Outrider's Bow (ranged, all levels)
    [19558] = { slot = "RANGED", class = nil, honor = 5100, arena = 0, marks = nil, season = "PREPATCH", name = "Outrider's Bow" },
    [19559] = { slot = "RANGED", class = nil, honor = 694, arena = 0, marks = nil, season = "PREPATCH", name = "Outrider's Bow" },
    [19560] = { slot = "RANGED", class = nil, honor = 469, arena = 0, marks = nil, season = "PREPATCH", name = "Outrider's Bow" },
    [19561] = { slot = "RANGED", class = nil, honor = 316, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Outrider's Bow" },
    [20437] = { slot = "RANGED", class = nil, honor = 214, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Outrider's Bow" },

    -- WEAPONS - Advisor's Gnarled Staff (staff, all levels)
    [19566] = { slot = "TWO_HAND", class = nil, honor = 10200, arena = 0, marks = nil, season = "PREPATCH", name = "Advisor's Gnarled Staff" },
    [19567] = { slot = "TWO_HAND", class = nil, honor = 1387, arena = 0, marks = nil, season = "PREPATCH", name = "Advisor's Gnarled Staff" },
    [19568] = { slot = "TWO_HAND", class = nil, honor = 938, arena = 0, marks = nil, season = "PREPATCH", name = "Advisor's Gnarled Staff" },
    [19569] = { slot = "TWO_HAND", class = nil, honor = 632, arena = 0, marks = nil, season = "PREPATCH", name = "Advisor's Gnarled Staff" },
    [20425] = { slot = "TWO_HAND", class = nil, honor = 428, arena = 0, marks = nil, season = "PREPATCH", name = "Advisor's Gnarled Staff" },

    -- TRINKET - Rune of Perfection (Priest only)
    [21565] = { slot = "TRINKET", class = "PRIEST", honor = 258, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Rune of Perfection" },
    [21566] = { slot = "TRINKET", class = "PRIEST", honor = 118, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Rune of Perfection" },

    -- LEGS - Outrider's (all armor types)
    [22651] = { slot = "LEGS", class = nil, honor = 8925, arena = 0, marks = nil, season = "PREPATCH", name = "Outrider's Plate Legguards" },
    [22673] = { slot = "LEGS", class = nil, honor = 8925, arena = 0, marks = nil, season = "PREPATCH", name = "Outrider's Chain Leggings" },
    [22676] = { slot = "LEGS", class = nil, honor = 8925, arena = 0, marks = nil, season = "PREPATCH", name = "Outrider's Mail Leggings" },
    [22740] = { slot = "LEGS", class = nil, honor = 8925, arena = 0, marks = nil, season = "PREPATCH", name = "Outrider's Leather Pants" },
    [22741] = { slot = "LEGS", class = nil, honor = 8925, arena = 0, marks = nil, season = "PREPATCH", name = "Outrider's Lizardhide Pants" },
    [22747] = { slot = "LEGS", class = nil, honor = 8925, arena = 0, marks = nil, season = "PREPATCH", name = "Outrider's Silk Leggings" },
    [30498] = { slot = "LEGS", class = nil, honor = 7905, arena = 0, marks = nil, season = "PREPATCH", name = "Outrider's Lamellar Legguards" },

    --[[
    ============================================================================
    AB REPUTATION REWARDS - Horde (Defiler's)
    ============================================================================
    --]]

    -- BACK - Deathguard's Cloak (Horde) / Cloak of the Honor Guard (Alliance)
    [20068] = { slot = "BACK", class = nil, honor = 4590, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Deathguard's Cloak" },
    [20073] = { slot = "BACK", class = nil, honor = 4590, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Cloak of the Honor Guard" },

    -- TRINKET - Defiler's Talisman (all levels)
    [20072] = { slot = "TRINKET", class = nil, honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Talisman" },
    [21115] = { slot = "TRINKET", class = nil, honor = 382, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Talisman" },
    [21116] = { slot = "TRINKET", class = nil, honor = 258, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Talisman" },
    [21120] = { slot = "TRINKET", class = nil, honor = 175, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Defiler's Talisman" },

    -- FEET - Defiler's Cloth Boots (all levels)
    [20159] = { slot = "FEET", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Cloth Boots" },
    [20160] = { slot = "FEET", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Cloth Boots" },
    [20161] = { slot = "FEET", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Cloth Boots" },
    [20162] = { slot = "FEET", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Cloth Boots" },

    -- WAIST - Defiler's Cloth Girdle (all levels)
    [20163] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Cloth Girdle" },
    [20164] = { slot = "WAIST", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Cloth Girdle" },
    [20165] = { slot = "WAIST", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Cloth Girdle" },
    [20166] = { slot = "WAIST", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Cloth Girdle" },

    -- SHOULDER - Defiler's Epaulets (cloth)
    [20176] = { slot = "SHOULDER", class = nil, honor = 8415, arena = 0, marks = { AB = 4 }, season = "PREPATCH", name = "Defiler's Epaulets" },

    -- FEET - Defiler's Chain Greaves (Hunter/Shaman)
    [20154] = { slot = "FEET", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Chain Greaves" },
    [20155] = { slot = "FEET", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Chain Greaves" },
    [20156] = { slot = "FEET", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Chain Greaves" },
    [20157] = { slot = "FEET", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Chain Greaves" },

    -- WAIST - Defiler's Chain Girdle (Hunter/Shaman)
    [20150] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Chain Girdle" },
    [20151] = { slot = "WAIST", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Chain Girdle" },
    [20152] = { slot = "WAIST", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Chain Girdle" },
    [20153] = { slot = "WAIST", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Chain Girdle" },

    -- SHOULDER - Defiler's Chain Pauldrons (Hunter/Shaman)
    [20158] = { slot = "SHOULDER", class = nil, honor = 8415, arena = 0, marks = { AB = 4 }, season = "PREPATCH", name = "Defiler's Chain Pauldrons" },

    -- FEET - Defiler's Lizardhide Boots (Druid/Rogue)
    [20167] = { slot = "FEET", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lizardhide Boots" },
    [20168] = { slot = "FEET", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lizardhide Boots" },
    [20169] = { slot = "FEET", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lizardhide Boots" },
    [20170] = { slot = "FEET", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lizardhide Boots" },

    -- WAIST - Defiler's Lizardhide Girdle (Druid/Rogue)
    [20171] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lizardhide Girdle" },
    [20172] = { slot = "WAIST", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lizardhide Girdle" },
    [20173] = { slot = "WAIST", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lizardhide Girdle" },
    [20174] = { slot = "WAIST", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lizardhide Girdle" },

    -- SHOULDER - Defiler's Lizardhide Shoulders (Druid/Rogue)
    [20175] = { slot = "SHOULDER", class = nil, honor = 8415, arena = 0, marks = { AB = 4 }, season = "PREPATCH", name = "Defiler's Lizardhide Shoulders" },

    -- FEET - Defiler's Lamellar Greaves (Paladin)
    [20177] = { slot = "FEET", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lamellar Greaves" },
    [20178] = { slot = "FEET", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lamellar Greaves" },
    [20179] = { slot = "FEET", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lamellar Greaves" },
    [20180] = { slot = "FEET", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lamellar Greaves" },

    -- WAIST - Defiler's Lamellar Girdle (Paladin)
    [20181] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lamellar Girdle" },
    [20182] = { slot = "WAIST", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lamellar Girdle" },
    [20183] = { slot = "WAIST", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lamellar Girdle" },
    [20184] = { slot = "WAIST", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lamellar Girdle" },

    -- SHOULDER - Defiler's Lamellar Spaulders (Paladin)
    [20185] = { slot = "SHOULDER", class = nil, honor = 8415, arena = 0, marks = { AB = 4 }, season = "PREPATCH", name = "Defiler's Lamellar Spaulders" },

    -- FEET - Defiler's Leather Boots (Druid/Rogue)
    [20186] = { slot = "FEET", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Leather Boots" },
    [20187] = { slot = "FEET", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Leather Boots" },
    [20188] = { slot = "FEET", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Leather Boots" },
    [20189] = { slot = "FEET", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Leather Boots" },

    -- WAIST - Defiler's Leather Girdle (Druid/Rogue)
    [20190] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Leather Girdle" },
    [20191] = { slot = "WAIST", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Leather Girdle" },
    [20192] = { slot = "WAIST", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Leather Girdle" },
    [20193] = { slot = "WAIST", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Leather Girdle" },

    -- SHOULDER - Defiler's Leather Shoulders (Druid/Rogue)
    [20194] = { slot = "SHOULDER", class = nil, honor = 8415, arena = 0, marks = { AB = 4 }, season = "PREPATCH", name = "Defiler's Leather Shoulders" },

    -- FEET - Defiler's Mail Greaves (Hunter/Shaman)
    [20199] = { slot = "FEET", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Mail Greaves" },
    [20200] = { slot = "FEET", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Mail Greaves" },
    [20201] = { slot = "FEET", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Mail Greaves" },
    [20202] = { slot = "FEET", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Mail Greaves" },

    -- WAIST - Defiler's Mail Girdle (Hunter/Shaman)
    [20195] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Mail Girdle" },
    [20196] = { slot = "WAIST", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Mail Girdle" },
    [20197] = { slot = "WAIST", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Mail Girdle" },
    [20198] = { slot = "WAIST", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Mail Girdle" },

    -- SHOULDER - Defiler's Mail Pauldrons (Hunter/Shaman)
    [20203] = { slot = "SHOULDER", class = nil, honor = 8415, arena = 0, marks = { AB = 4 }, season = "PREPATCH", name = "Defiler's Mail Pauldrons" },

    -- FEET - Defiler's Plate Greaves (Warrior)
    [20208] = { slot = "FEET", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Plate Greaves" },
    [20209] = { slot = "FEET", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Plate Greaves" },
    [20210] = { slot = "FEET", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Plate Greaves" },
    [20211] = { slot = "FEET", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Plate Greaves" },

    -- WAIST - Defiler's Plate Girdle (Warrior)
    [20204] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Plate Girdle" },
    [20205] = { slot = "WAIST", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Plate Girdle" },
    [20206] = { slot = "WAIST", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Plate Girdle" },
    [20207] = { slot = "WAIST", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Plate Girdle" },

    -- SHOULDER - Defiler's Plate Spaulders (Warrior)
    [20212] = { slot = "SHOULDER", class = nil, honor = 8415, arena = 0, marks = { AB = 4 }, season = "PREPATCH", name = "Defiler's Plate Spaulders" },

    -- WEAPONS
    [20214] = { slot = "MAIN_HAND", class = nil, honor = 8160, arena = 0, marks = { AB = 4 }, season = "PREPATCH", name = "Mindfang" },
    [20220] = { slot = "TWO_HAND", class = nil, honor = 15300, arena = 0, marks = { AB = 4 }, season = "PREPATCH", name = "Ironbark Staff" },

    --[[
    ============================================================================
    AV REPUTATION REWARDS - Horde (Frostwolf)
    ============================================================================
    --]]

    -- TABARD
    [19031] = { slot = "TABARD", class = nil, honor = 0, arena = 0, marks = { AV = 60 }, season = "PREPATCH", name = "Frostwolf Battle Tabard" },

    -- BACK - Cloaks
    [19083] = { slot = "BACK", class = nil, honor = 1530, arena = 0, marks = { AV = 1 }, season = "PREPATCH", name = "Frostwolf Legionnaire's Cloak" },
    [19085] = { slot = "BACK", class = nil, honor = 1530, arena = 0, marks = { AV = 1 }, season = "PREPATCH", name = "Frostwolf Advisor's Cloak" },

    -- NECK - Pendants
    [19095] = { slot = "NECK", class = nil, honor = 1530, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Frostwolf Legionnaire's Pendant" },
    [19096] = { slot = "NECK", class = nil, honor = 1530, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Frostwolf Advisor's Pendant" },

    -- WAIST - Belts (all armor types)
    [19087] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Frostwolf Plate Belt" },
    [19088] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Frostwolf Mail Belt" },
    [19089] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Frostwolf Leather Belt" },
    [19090] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Frostwolf Cloth Belt" },

    -- FINGER - Rings
    [19325] = { slot = "FINGER", class = nil, honor = 4590, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Don Julio's Band" },
    [21563] = { slot = "FINGER", class = nil, honor = 4590, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Don Rodrigo's Band" },

    -- WEAPONS - Budget
    [19099] = { slot = "MAIN_HAND", class = nil, honor = 2380, arena = 0, marks = { AV = 1 }, season = "PREPATCH", name = "Glacial Blade" },
    [19101] = { slot = "TWO_HAND", class = nil, honor = 2720, arena = 0, marks = { AV = 1 }, season = "PREPATCH", name = "Whiteout Staff" },
    [19103] = { slot = "MAIN_HAND", class = nil, honor = 2380, arena = 0, marks = { AV = 1 }, season = "PREPATCH", name = "Frostbite" },

    -- WEAPONS - Epic
    [19323] = { slot = "TWO_HAND", class = nil, honor = 4760, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "The Unstoppable Force" },
    [19324] = { slot = "MAIN_HAND", class = nil, honor = 4760, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "The Lobotomizer" },

    -- OFF_HAND - Shield
    [19321] = { slot = "OFF_HAND", class = nil, honor = 4760, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "The Immovable Object" },

    -- OFF_HAND - Tomes/Caster
    [19308] = { slot = "OFF_HAND", class = nil, honor = 4760, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Tome of Arcane Domination" },
    [19309] = { slot = "OFF_HAND", class = nil, honor = 4760, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Tome of Shadow Force" },
    [19310] = { slot = "OFF_HAND", class = nil, honor = 4760, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Tome of the Ice Lord" },
    [19311] = { slot = "OFF_HAND", class = nil, honor = 4760, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Tome of Fiery Arcana" },
    [19312] = { slot = "OFF_HAND", class = nil, honor = 4760, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Lei of the Lifegiver" },
    [19315] = { slot = "OFF_HAND", class = nil, honor = 4760, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Therazane's Touch" },

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
