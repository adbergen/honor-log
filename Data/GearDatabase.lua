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
    HONOR70 = "Level 70 Honor", -- TBC launch honor gear (pre-arena)
}

-- Archived seasons (not yet available in game)
-- When arena seasons release, remove them from this list
HonorLog.ARCHIVED_SEASONS = {
    S1 = true,  -- Gladiator gear - unlocks with TBC Arena Season 1
    S2 = true,  -- Merciless Gladiator - unlocks with Arena Season 2
    S3 = true,  -- Vengeful Gladiator - unlocks with Arena Season 3
    S4 = true,  -- Brutal Gladiator - unlocks with Arena Season 4
    -- HONOR70 available at TBC launch
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

    -- PALADIN - Champion's Redoubt (Horde, set 697) - Cross-faction for Blood Elf Paladins
    [29604] = { slot = "HEAD", class = "PALADIN", honor = 4335, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Champion's Lamellar Headguard" },
    [29605] = { slot = "SHOULDER", class = "PALADIN", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Champion's Lamellar Shoulders" },
    [29602] = { slot = "CHEST", class = "PALADIN", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Legionnaire's Lamellar Chestplate" },
    [29600] = { slot = "HANDS", class = "PALADIN", honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Blood Guard's Lamellar Gauntlets" },
    [29603] = { slot = "LEGS", class = "PALADIN", honor = 4335, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Legionnaire's Lamellar Leggings" },
    [29601] = { slot = "FEET", class = "PALADIN", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Blood Guard's Lamellar Greaves" },

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

    -- SHAMAN - Lieutenant Commander's Earthshaker (Alliance, set 718) - Cross-faction for Draenei Shamans
    [29598] = { slot = "HEAD", class = "SHAMAN", honor = 4335, arena = 0, marks = { AV = 3 }, season = "PREPATCH", name = "Lieutenant Commander's Mail Headguard" },
    [29599] = { slot = "SHOULDER", class = "SHAMAN", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Lieutenant Commander's Mail Pauldrons" },
    [29596] = { slot = "CHEST", class = "SHAMAN", honor = 4590, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Knight-Captain's Mail Hauberk" },
    [29595] = { slot = "HANDS", class = "SHAMAN", honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Knight-Lieutenant's Mail Gauntlets" },
    [29597] = { slot = "LEGS", class = "SHAMAN", honor = 4335, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Knight-Captain's Mail Leggings" },
    [29594] = { slot = "FEET", class = "SHAMAN", honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Knight-Lieutenant's Mail Greaves" },

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
    [24549] = { slot = "TRINKET", class = "SHAMAN", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Alliance" }, -- Draenei Shaman (TBC)

    -- HORDE INSIGNIAS
    [18834] = { slot = "TRINKET", class = "WARRIOR", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },
    [18846] = { slot = "TRINKET", class = "HUNTER", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },
    [18849] = { slot = "TRINKET", class = "ROGUE", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },
    [18852] = { slot = "TRINKET", class = "WARLOCK", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },
    [18851] = { slot = "TRINKET", class = "PRIEST", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },
    [18853] = { slot = "TRINKET", class = "DRUID", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },
    [18845] = { slot = "TRINKET", class = "SHAMAN", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },
    [18850] = { slot = "TRINKET", class = "MAGE", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" },
    [24550] = { slot = "TRINKET", class = "PALADIN", honor = 2805, arena = 0, marks = nil, season = "PREPATCH", name = "Insignia of the Horde" }, -- Blood Elf Paladin (TBC)

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
    WSG REPUTATION REWARDS - Alliance (Silverwing Sentinels)
    ============================================================================
    --]]

    -- TABARD
    [19506] = { slot = "TABARD", class = nil, honor = 0, arena = 0, marks = { WSG = 60 }, season = "PREPATCH", name = "Silverwing Battle Tabard" },

    -- RINGS - Protector's Band (all levels)
    [19514] = { slot = "FINGER", class = nil, honor = 1530, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Protector's Band" },
    [19516] = { slot = "FINGER", class = nil, honor = 208, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Protector's Band" },
    [19515] = { slot = "FINGER", class = nil, honor = 141, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Protector's Band" },
    [19517] = { slot = "FINGER", class = nil, honor = 95, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Protector's Band" },
    [20439] = { slot = "FINGER", class = nil, honor = 65, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Protector's Band" },

    -- RINGS - Lorekeeper's Ring (all levels)
    [19522] = { slot = "FINGER", class = nil, honor = 1530, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Lorekeeper's Ring" },
    [19523] = { slot = "FINGER", class = nil, honor = 208, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Lorekeeper's Ring" },
    [19524] = { slot = "FINGER", class = nil, honor = 141, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Lorekeeper's Ring" },
    [19525] = { slot = "FINGER", class = nil, honor = 95, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Lorekeeper's Ring" },
    [20431] = { slot = "FINGER", class = nil, honor = 65, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Lorekeeper's Ring" },

    -- NECK - Sentinel's Medallion (all levels)
    [19538] = { slot = "NECK", class = nil, honor = 1530, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Sentinel's Medallion" },
    [19539] = { slot = "NECK", class = nil, honor = 208, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Sentinel's Medallion" },
    [19540] = { slot = "NECK", class = nil, honor = 141, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Sentinel's Medallion" },
    [19541] = { slot = "NECK", class = nil, honor = 95, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Sentinel's Medallion" },
    [20444] = { slot = "NECK", class = nil, honor = 65, arena = 0, marks = { WSG = 2 }, season = "PREPATCH", name = "Sentinel's Medallion" },

    -- BACK - Caretaker's Cape (all levels)
    [19530] = { slot = "BACK", class = nil, honor = 1530, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "Caretaker's Cape" },
    [19531] = { slot = "BACK", class = nil, honor = 208, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "Caretaker's Cape" },
    [19532] = { slot = "BACK", class = nil, honor = 141, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "Caretaker's Cape" },
    [19533] = { slot = "BACK", class = nil, honor = 95, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "Caretaker's Cape" },
    [20428] = { slot = "BACK", class = nil, honor = 65, arena = 0, marks = { WSG = 1 }, season = "PREPATCH", name = "Caretaker's Cape" },

    -- WEAPONS - Sentinel's Blade (dagger, all levels)
    [19546] = { slot = "MAIN_HAND", class = nil, honor = 5100, arena = 0, marks = nil, season = "PREPATCH", name = "Sentinel's Blade" },
    [19547] = { slot = "MAIN_HAND", class = nil, honor = 694, arena = 0, marks = nil, season = "PREPATCH", name = "Sentinel's Blade" },
    [19548] = { slot = "MAIN_HAND", class = nil, honor = 469, arena = 0, marks = nil, season = "PREPATCH", name = "Sentinel's Blade" },
    [19549] = { slot = "MAIN_HAND", class = nil, honor = 316, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Sentinel's Blade" },
    [20443] = { slot = "MAIN_HAND", class = nil, honor = 214, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Sentinel's Blade" },

    -- WEAPONS - Protector's Sword (2H sword, all levels)
    [19554] = { slot = "MAIN_HAND", class = nil, honor = 10200, arena = 0, marks = nil, season = "PREPATCH", name = "Protector's Sword" },
    [19555] = { slot = "MAIN_HAND", class = nil, honor = 694, arena = 0, marks = nil, season = "PREPATCH", name = "Protector's Sword" },
    [19556] = { slot = "MAIN_HAND", class = nil, honor = 469, arena = 0, marks = nil, season = "PREPATCH", name = "Protector's Sword" },
    [19557] = { slot = "MAIN_HAND", class = nil, honor = 316, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Protector's Sword" },
    [20440] = { slot = "MAIN_HAND", class = nil, honor = 214, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Protector's Sword" },

    -- WEAPONS - Outrunner's Bow (ranged, all levels)
    [19562] = { slot = "RANGED", class = nil, honor = 5100, arena = 0, marks = nil, season = "PREPATCH", name = "Outrunner's Bow" },
    [19563] = { slot = "RANGED", class = nil, honor = 694, arena = 0, marks = nil, season = "PREPATCH", name = "Outrunner's Bow" },
    [19564] = { slot = "RANGED", class = nil, honor = 469, arena = 0, marks = nil, season = "PREPATCH", name = "Outrunner's Bow" },
    [19565] = { slot = "RANGED", class = nil, honor = 316, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Outrunner's Bow" },
    [20438] = { slot = "RANGED", class = nil, honor = 214, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Outrunner's Bow" },

    -- WEAPONS - Lorekeeper's Staff (staff, all levels)
    [19570] = { slot = "TWO_HAND", class = nil, honor = 10200, arena = 0, marks = nil, season = "PREPATCH", name = "Lorekeeper's Staff" },
    [19571] = { slot = "TWO_HAND", class = nil, honor = 1387, arena = 0, marks = nil, season = "PREPATCH", name = "Lorekeeper's Staff" },
    [19572] = { slot = "TWO_HAND", class = nil, honor = 938, arena = 0, marks = nil, season = "PREPATCH", name = "Lorekeeper's Staff" },
    [19573] = { slot = "TWO_HAND", class = nil, honor = 632, arena = 0, marks = nil, season = "PREPATCH", name = "Lorekeeper's Staff" },
    [20434] = { slot = "TWO_HAND", class = nil, honor = 428, arena = 0, marks = nil, season = "PREPATCH", name = "Lorekeeper's Staff" },

    -- TRINKET - Rune of Duty (Priest only)
    [21567] = { slot = "TRINKET", class = "PRIEST", honor = 258, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Rune of Duty" },
    [21568] = { slot = "TRINKET", class = "PRIEST", honor = 118, arena = 0, marks = { WSG = 3 }, season = "PREPATCH", name = "Rune of Duty" },

    -- LEGS - Sentinel's (all armor types)
    [22672] = { slot = "LEGS", class = nil, honor = 8925, arena = 0, marks = nil, season = "PREPATCH", name = "Sentinel's Plate Legguards" },
    [22748] = { slot = "LEGS", class = nil, honor = 8925, arena = 0, marks = nil, season = "PREPATCH", name = "Sentinel's Chain Leggings" },
    [22749] = { slot = "LEGS", class = nil, honor = 8925, arena = 0, marks = nil, season = "PREPATCH", name = "Sentinel's Leather Pants" },
    [22750] = { slot = "LEGS", class = nil, honor = 8925, arena = 0, marks = nil, season = "PREPATCH", name = "Sentinel's Lizardhide Pants" },
    [22752] = { slot = "LEGS", class = nil, honor = 8925, arena = 0, marks = nil, season = "PREPATCH", name = "Sentinel's Silk Leggings" },
    [22753] = { slot = "LEGS", class = nil, honor = 8925, arena = 0, marks = nil, season = "PREPATCH", name = "Sentinel's Lamellar Legguards" },

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

    -- WAIST - Defiler's Lamellar Girdle (Paladin)
    [20177] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lamellar Girdle" },
    [20178] = { slot = "WAIST", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lamellar Girdle" },
    [20179] = { slot = "WAIST", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lamellar Girdle" },
    [20180] = { slot = "WAIST", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lamellar Girdle" },

    -- FEET - Defiler's Lamellar Greaves (Paladin)
    [20181] = { slot = "FEET", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lamellar Greaves" },
    [20182] = { slot = "FEET", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lamellar Greaves" },
    [20183] = { slot = "FEET", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lamellar Greaves" },
    [20184] = { slot = "FEET", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Defiler's Lamellar Greaves" },

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

    -- TABARD
    [20131] = { slot = "TABARD", class = nil, honor = 0, arena = 0, marks = { AB = 60 }, season = "PREPATCH", name = "Battle Tabard of the Defilers" },

    --[[
    ============================================================================
    AB REPUTATION REWARDS - Alliance (Highlander's / League of Arathor)
    ============================================================================
    --]]

    -- TABARD
    [20132] = { slot = "TABARD", class = nil, honor = 0, arena = 0, marks = { AB = 60 }, season = "PREPATCH", name = "Arathor Battle Tabard" },

    -- TRINKET - Talisman of Arathor (all levels)
    [20071] = { slot = "TRINKET", class = nil, honor = 2805, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Talisman of Arathor" },
    [21117] = { slot = "TRINKET", class = nil, honor = 382, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Talisman of Arathor" },
    [21118] = { slot = "TRINKET", class = nil, honor = 258, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Talisman of Arathor" },
    [21119] = { slot = "TRINKET", class = nil, honor = 175, arena = 0, marks = { AB = 3 }, season = "PREPATCH", name = "Talisman of Arathor" },

    -- FEET - Highlander's Cloth Boots (all levels)
    [20054] = { slot = "FEET", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Cloth Boots" },
    [20094] = { slot = "FEET", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Cloth Boots" },
    [20095] = { slot = "FEET", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Cloth Boots" },
    [20096] = { slot = "FEET", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Cloth Boots" },

    -- WAIST - Highlander's Cloth Girdle (all levels)
    [20047] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Cloth Girdle" },
    [20097] = { slot = "WAIST", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Cloth Girdle" },
    [20098] = { slot = "WAIST", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Cloth Girdle" },
    [20099] = { slot = "WAIST", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Cloth Girdle" },

    -- SHOULDER - Highlander's Epaulets (cloth)
    [20061] = { slot = "SHOULDER", class = nil, honor = 8415, arena = 0, marks = { AB = 4 }, season = "PREPATCH", name = "Highlander's Epaulets" },

    -- FEET - Highlander's Chain Greaves (Hunter)
    [20050] = { slot = "FEET", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Chain Greaves" },
    [20091] = { slot = "FEET", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Chain Greaves" },
    [20092] = { slot = "FEET", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Chain Greaves" },
    [20093] = { slot = "FEET", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Chain Greaves" },

    -- WAIST - Highlander's Chain Girdle (Hunter)
    [20043] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Chain Girdle" },
    [20088] = { slot = "WAIST", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Chain Girdle" },
    [20089] = { slot = "WAIST", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Chain Girdle" },
    [20090] = { slot = "WAIST", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Chain Girdle" },

    -- SHOULDER - Highlander's Chain Pauldrons (Hunter)
    [20055] = { slot = "SHOULDER", class = nil, honor = 8415, arena = 0, marks = { AB = 4 }, season = "PREPATCH", name = "Highlander's Chain Pauldrons" },

    -- FEET - Highlander's Lizardhide Boots (Druid/Rogue)
    [20053] = { slot = "FEET", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Lizardhide Boots" },
    [20100] = { slot = "FEET", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Lizardhide Boots" },
    [20101] = { slot = "FEET", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Lizardhide Boots" },
    [20102] = { slot = "FEET", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Lizardhide Boots" },

    -- WAIST - Highlander's Lizardhide Girdle (Druid/Rogue)
    [20046] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Lizardhide Girdle" },
    [20103] = { slot = "WAIST", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Lizardhide Girdle" },
    [20104] = { slot = "WAIST", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Lizardhide Girdle" },
    [20105] = { slot = "WAIST", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Lizardhide Girdle" },

    -- SHOULDER - Highlander's Lizardhide Shoulders (Druid/Rogue)
    [20060] = { slot = "SHOULDER", class = nil, honor = 8415, arena = 0, marks = { AB = 4 }, season = "PREPATCH", name = "Highlander's Lizardhide Shoulders" },

    -- FEET - Highlander's Lamellar Greaves (Paladin)
    [20049] = { slot = "FEET", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Lamellar Greaves" },
    [20109] = { slot = "FEET", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Lamellar Greaves" },
    [20110] = { slot = "FEET", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Lamellar Greaves" },
    [20111] = { slot = "FEET", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Lamellar Greaves" },

    -- WAIST - Highlander's Lamellar Girdle (Paladin)
    [20042] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Lamellar Girdle" },
    [20106] = { slot = "WAIST", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Lamellar Girdle" },
    [20107] = { slot = "WAIST", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Lamellar Girdle" },
    [20108] = { slot = "WAIST", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Lamellar Girdle" },

    -- SHOULDER - Highlander's Lamellar Spaulders (Paladin)
    [20058] = { slot = "SHOULDER", class = nil, honor = 8415, arena = 0, marks = { AB = 4 }, season = "PREPATCH", name = "Highlander's Lamellar Spaulders" },

    -- FEET - Highlander's Leather Boots (Druid/Rogue)
    [20052] = { slot = "FEET", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Leather Boots" },
    [20112] = { slot = "FEET", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Leather Boots" },
    [20113] = { slot = "FEET", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Leather Boots" },
    [20114] = { slot = "FEET", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Leather Boots" },

    -- WAIST - Highlander's Leather Girdle (Druid/Rogue)
    [20045] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Leather Girdle" },
    [20115] = { slot = "WAIST", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Leather Girdle" },
    [20116] = { slot = "WAIST", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Leather Girdle" },
    [20117] = { slot = "WAIST", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Leather Girdle" },

    -- SHOULDER - Highlander's Leather Shoulders (Druid/Rogue)
    [20059] = { slot = "SHOULDER", class = nil, honor = 8415, arena = 0, marks = { AB = 4 }, season = "PREPATCH", name = "Highlander's Leather Shoulders" },

    -- FEET - Highlander's Plate Greaves (Warrior)
    [20048] = { slot = "FEET", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Plate Greaves" },
    [20127] = { slot = "FEET", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Plate Greaves" },
    [20128] = { slot = "FEET", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Plate Greaves" },
    [20129] = { slot = "FEET", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Plate Greaves" },

    -- WAIST - Highlander's Plate Girdle (Warrior)
    [20041] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Plate Girdle" },
    [20124] = { slot = "WAIST", class = nil, honor = 382, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Plate Girdle" },
    [20125] = { slot = "WAIST", class = nil, honor = 258, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Plate Girdle" },
    [20126] = { slot = "WAIST", class = nil, honor = 175, arena = 0, marks = { AB = 2 }, season = "PREPATCH", name = "Highlander's Plate Girdle" },

    -- SHOULDER - Highlander's Plate Spaulders (Warrior)
    [20057] = { slot = "SHOULDER", class = nil, honor = 8415, arena = 0, marks = { AB = 4 }, season = "PREPATCH", name = "Highlander's Plate Spaulders" },

    -- WEAPONS
    [20070] = { slot = "MAIN_HAND", class = nil, honor = 8160, arena = 0, marks = { AB = 4 }, season = "PREPATCH", name = "Sageclaw" },
    [20069] = { slot = "TWO_HAND", class = nil, honor = 15300, arena = 0, marks = { AB = 4 }, season = "PREPATCH", name = "Ironbark Staff" },

    --[[
    ============================================================================
    AV REPUTATION REWARDS - Alliance (Stormpike Guard)
    ============================================================================
    --]]

    -- TABARD
    [19032] = { slot = "TABARD", class = nil, honor = 0, arena = 0, marks = { AV = 60 }, season = "PREPATCH", name = "Stormpike Battle Tabard" },

    -- BACK - Cloaks
    [19084] = { slot = "BACK", class = nil, honor = 1530, arena = 0, marks = { AV = 1 }, season = "PREPATCH", name = "Stormpike Soldier's Cloak" },
    [19086] = { slot = "BACK", class = nil, honor = 1530, arena = 0, marks = { AV = 1 }, season = "PREPATCH", name = "Stormpike Sage's Cloak" },

    -- NECK - Pendants
    [19097] = { slot = "NECK", class = nil, honor = 1530, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Stormpike Soldier's Pendant" },
    [19098] = { slot = "NECK", class = nil, honor = 1530, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Stormpike Sage's Pendant" },

    -- WAIST - Girdles (all armor types)
    [19091] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Stormpike Plate Girdle" },
    [19092] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Stormpike Mail Girdle" },
    [19093] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Stormpike Leather Girdle" },
    [19094] = { slot = "WAIST", class = nil, honor = 2805, arena = 0, marks = { AV = 2 }, season = "PREPATCH", name = "Stormpike Cloth Girdle" },

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

    --[[
    ============================================================================
    TBC LEVEL 70 RARE (BLUE) HONOR GEAR - HONOR70 SEASON
    Grand Marshal (Alliance) / High Warlord (Horde) sets
    Available at TBC launch before Arena Season 1 begins
    Item IDs from AtlasLoot ItemSet.lua
    ============================================================================
    --]]

    -- ==========================================
    -- WARRIOR - Grand Marshal's Battlegear (Alliance) - Set 590
    -- AtlasLoot order: {28701,28703,28699,28700,28702} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    -- ==========================================
    [28701] = { slot = "HEAD", class = "WARRIOR", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Plate Helm" },
    [28703] = { slot = "SHOULDER", class = "WARRIOR", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Plate Shoulders" },
    [28699] = { slot = "CHEST", class = "WARRIOR", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Grand Marshal's Plate Chestpiece" },
    [28700] = { slot = "HANDS", class = "WARRIOR", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Plate Gauntlets" },
    [28702] = { slot = "LEGS", class = "WARRIOR", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Plate Legguards" },

    -- WARRIOR - High Warlord's Battlegear (Horde) - Set 588
    -- AtlasLoot order: {28853,28855,28851,28852,28854} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [28853] = { slot = "HEAD", class = "WARRIOR", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Plate Helm" },
    [28855] = { slot = "SHOULDER", class = "WARRIOR", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Plate Shoulders" },
    [28851] = { slot = "CHEST", class = "WARRIOR", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "High Warlord's Plate Chestpiece" },
    [28852] = { slot = "HANDS", class = "WARRIOR", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Plate Gauntlets" },
    [28854] = { slot = "LEGS", class = "WARRIOR", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Plate Legguards" },

    -- ==========================================
    -- PALADIN - Grand Marshal's Aegis (Alliance) - Set 589
    -- AtlasLoot order: {28681,28683,28679,28680,28724} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    -- ==========================================
    [28681] = { slot = "HEAD", class = "PALADIN", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Lamellar Helm" },
    [28683] = { slot = "SHOULDER", class = "PALADIN", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Lamellar Shoulders" },
    [28679] = { slot = "CHEST", class = "PALADIN", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Grand Marshal's Lamellar Chestpiece" },
    [28680] = { slot = "HANDS", class = "PALADIN", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Lamellar Gauntlets" },
    [28724] = { slot = "LEGS", class = "PALADIN", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Lamellar Legguards" },

    -- PALADIN - High Warlord's Aegis (Horde) - Set 587
    -- AtlasLoot order: {28833,28835,28831,28832,28834} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [28833] = { slot = "HEAD", class = "PALADIN", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Lamellar Helm" },
    [28835] = { slot = "SHOULDER", class = "PALADIN", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Lamellar Shoulders" },
    [28831] = { slot = "CHEST", class = "PALADIN", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "High Warlord's Lamellar Chestpiece" },
    [28832] = { slot = "HANDS", class = "PALADIN", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Lamellar Gauntlets" },
    [28834] = { slot = "LEGS", class = "PALADIN", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Lamellar Legguards" },

    -- PALADIN - Grand Marshal's Vindication (Alliance) - Set 607
    -- AtlasLoot order: {28711,28713,28709,28710,28712} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [28711] = { slot = "HEAD", class = "PALADIN", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Ornamented Headcover" },
    [28713] = { slot = "SHOULDER", class = "PALADIN", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Ornamented Spaulders" },
    [28709] = { slot = "CHEST", class = "PALADIN", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Grand Marshal's Ornamented Chestplate" },
    [28710] = { slot = "HANDS", class = "PALADIN", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Ornamented Gloves" },
    [28712] = { slot = "LEGS", class = "PALADIN", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Ornamented Leggings" },

    -- PALADIN - High Warlord's Vindication (Horde) - Set 608
    -- AtlasLoot order: {28863,28865,28861,28862,28864} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [28863] = { slot = "HEAD", class = "PALADIN", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Ornamented Headcover" },
    [28865] = { slot = "SHOULDER", class = "PALADIN", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Ornamented Spaulders" },
    [28861] = { slot = "CHEST", class = "PALADIN", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "High Warlord's Ornamented Chestplate" },
    [28862] = { slot = "HANDS", class = "PALADIN", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Ornamented Gloves" },
    [28864] = { slot = "LEGS", class = "PALADIN", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Ornamented Leggings" },

    -- PALADIN - Grand Marshal's Redemption (Alliance) - Set 693
    -- AtlasLoot order: {31632,31634,31630,31631,31633} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [31632] = { slot = "HEAD", class = "PALADIN", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Scaled Helm" },
    [31634] = { slot = "SHOULDER", class = "PALADIN", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Scaled Shoulders" },
    [31630] = { slot = "CHEST", class = "PALADIN", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Grand Marshal's Scaled Chestpiece" },
    [31631] = { slot = "HANDS", class = "PALADIN", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Scaled Gauntlets" },
    [31633] = { slot = "LEGS", class = "PALADIN", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Scaled Legguards" },

    -- PALADIN - High Warlord's Redemption (Horde) - Set 694
    -- AtlasLoot order: {31637,31639,31635,31636,31638} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [31637] = { slot = "HEAD", class = "PALADIN", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Scaled Helm" },
    [31639] = { slot = "SHOULDER", class = "PALADIN", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Scaled Shoulders" },
    [31635] = { slot = "CHEST", class = "PALADIN", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "High Warlord's Scaled Chestpiece" },
    [31636] = { slot = "HANDS", class = "PALADIN", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Scaled Gauntlets" },
    [31638] = { slot = "LEGS", class = "PALADIN", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Scaled Legguards" },

    -- ==========================================
    -- HUNTER - Grand Marshal's Pursuit (Alliance) - Set 595
    -- AtlasLoot order: {28615,28617,28613,28614,28616} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    -- ==========================================
    [28615] = { slot = "HEAD", class = "HUNTER", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Chain Helm" },
    [28617] = { slot = "SHOULDER", class = "HUNTER", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Chain Spaulders" },
    [28613] = { slot = "CHEST", class = "HUNTER", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Grand Marshal's Chain Armor" },
    [28614] = { slot = "HANDS", class = "HUNTER", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Chain Gauntlets" },
    [28616] = { slot = "LEGS", class = "HUNTER", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Chain Leggings" },

    -- HUNTER - High Warlord's Pursuit (Horde) - Set 596
    -- AtlasLoot order: {28807,28809,28805,28806,28808} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [28807] = { slot = "HEAD", class = "HUNTER", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Chain Helm" },
    [28809] = { slot = "SHOULDER", class = "HUNTER", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Chain Spaulders" },
    [28805] = { slot = "CHEST", class = "HUNTER", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "High Warlord's Chain Armor" },
    [28806] = { slot = "HANDS", class = "HUNTER", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Chain Gauntlets" },
    [28808] = { slot = "LEGS", class = "HUNTER", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Chain Leggings" },

    -- ==========================================
    -- ROGUE - Grand Marshal's Vestments (Alliance) - Set 605
    -- AtlasLoot order: {28685,28687,28688,28684,28686} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    -- ==========================================
    [28685] = { slot = "HEAD", class = "ROGUE", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Leather Helm" },
    [28687] = { slot = "SHOULDER", class = "ROGUE", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Leather Spaulders" },
    [28688] = { slot = "CHEST", class = "ROGUE", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Grand Marshal's Leather Tunic" },
    [28684] = { slot = "HANDS", class = "ROGUE", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Leather Gloves" },
    [28686] = { slot = "LEGS", class = "ROGUE", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Leather Legguards" },

    -- ROGUE - High Warlord's Vestments (Horde) - Set 606
    -- AtlasLoot order: {28837,28839,28840,28836,28838} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [28837] = { slot = "HEAD", class = "ROGUE", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Leather Helm" },
    [28839] = { slot = "SHOULDER", class = "ROGUE", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Leather Spaulders" },
    [28840] = { slot = "CHEST", class = "ROGUE", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "High Warlord's Leather Tunic" },
    [28836] = { slot = "HANDS", class = "ROGUE", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Leather Gloves" },
    [28838] = { slot = "LEGS", class = "ROGUE", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Leather Legguards" },

    -- ==========================================
    -- PRIEST - Grand Marshal's Raiment (Alliance) - Set 597
    -- AtlasLoot order: {28705,28707,28708,28704,28706} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    -- ==========================================
    [28705] = { slot = "HEAD", class = "PRIEST", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Satin Hood" },
    [28707] = { slot = "SHOULDER", class = "PRIEST", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Satin Mantle" },
    [28708] = { slot = "CHEST", class = "PRIEST", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Grand Marshal's Satin Robe" },
    [28704] = { slot = "HANDS", class = "PRIEST", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Satin Gloves" },
    [28706] = { slot = "LEGS", class = "PRIEST", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Satin Leggings" },

    -- PRIEST - High Warlord's Raiment (Horde) - Set 598
    -- AtlasLoot order: {28857,28859,28860,28856,28858} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [28857] = { slot = "HEAD", class = "PRIEST", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Satin Hood" },
    [28859] = { slot = "SHOULDER", class = "PRIEST", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Satin Mantle" },
    [28860] = { slot = "CHEST", class = "PRIEST", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "High Warlord's Satin Robe" },
    [28856] = { slot = "HANDS", class = "PRIEST", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Satin Gloves" },
    [28858] = { slot = "LEGS", class = "PRIEST", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Satin Leggings" },

    -- PRIEST - Grand Marshal's Investiture (Alliance) - Set 691
    -- AtlasLoot order: {31622,31624,31625,31620,31623} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [31622] = { slot = "HEAD", class = "PRIEST", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Mooncloth Cowl" },
    [31624] = { slot = "SHOULDER", class = "PRIEST", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Mooncloth Mantle" },
    [31625] = { slot = "CHEST", class = "PRIEST", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Grand Marshal's Mooncloth Robe" },
    [31620] = { slot = "HANDS", class = "PRIEST", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Mooncloth Gloves" },
    [31623] = { slot = "LEGS", class = "PRIEST", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Mooncloth Leggings" },

    -- PRIEST - High Warlord's Investiture (Horde) - Set 692
    -- AtlasLoot order: {31626,31628,31629,31621,31627} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [31626] = { slot = "HEAD", class = "PRIEST", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Mooncloth Cowl" },
    [31628] = { slot = "SHOULDER", class = "PRIEST", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Mooncloth Mantle" },
    [31629] = { slot = "CHEST", class = "PRIEST", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "High Warlord's Mooncloth Robe" },
    [31621] = { slot = "HANDS", class = "PRIEST", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Mooncloth Gloves" },
    [31627] = { slot = "LEGS", class = "PRIEST", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Mooncloth Leggings" },

    -- ==========================================
    -- SHAMAN - Grand Marshal's Earthshaker (Alliance) - Set 593
    -- AtlasLoot order: {28691,28693,28689,28690,28692} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    -- ==========================================
    [28691] = { slot = "HEAD", class = "SHAMAN", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Linked Helm" },
    [28693] = { slot = "SHOULDER", class = "SHAMAN", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Linked Spaulders" },
    [28689] = { slot = "CHEST", class = "SHAMAN", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Grand Marshal's Linked Armor" },
    [28690] = { slot = "HANDS", class = "SHAMAN", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Linked Gauntlets" },
    [28692] = { slot = "LEGS", class = "SHAMAN", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Linked Leggings" },

    -- SHAMAN - High Warlord's Earthshaker (Horde) - Set 594
    -- AtlasLoot order: {28843,28845,28841,28842,28844} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [28843] = { slot = "HEAD", class = "SHAMAN", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Linked Helm" },
    [28845] = { slot = "SHOULDER", class = "SHAMAN", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Linked Spaulders" },
    [28841] = { slot = "CHEST", class = "SHAMAN", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "High Warlord's Linked Armor" },
    [28842] = { slot = "HANDS", class = "SHAMAN", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Linked Gauntlets" },
    [28844] = { slot = "LEGS", class = "SHAMAN", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Linked Leggings" },

    -- SHAMAN - Grand Marshal's Thunderfist (Alliance) - Set 603
    -- AtlasLoot order: {28696,28698,28694,28695,28697} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [28696] = { slot = "HEAD", class = "SHAMAN", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Mail Helm" },
    [28698] = { slot = "SHOULDER", class = "SHAMAN", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Mail Spaulders" },
    [28694] = { slot = "CHEST", class = "SHAMAN", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Grand Marshal's Mail Armor" },
    [28695] = { slot = "HANDS", class = "SHAMAN", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Mail Gauntlets" },
    [28697] = { slot = "LEGS", class = "SHAMAN", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Mail Leggings" },

    -- SHAMAN - High Warlord's Thunderfist (Horde) - Set 604
    -- AtlasLoot order: {28848,28850,28846,28847,28849} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [28848] = { slot = "HEAD", class = "SHAMAN", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Mail Helm" },
    [28850] = { slot = "SHOULDER", class = "SHAMAN", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Mail Spaulders" },
    [28846] = { slot = "CHEST", class = "SHAMAN", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "High Warlord's Mail Armor" },
    [28847] = { slot = "HANDS", class = "SHAMAN", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Mail Gauntlets" },
    [28849] = { slot = "LEGS", class = "SHAMAN", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Mail Leggings" },

    -- SHAMAN - Grand Marshal's Wartide (Alliance) - Set 695
    -- AtlasLoot order: {31642,31644,31640,31641,31643} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [31642] = { slot = "HEAD", class = "SHAMAN", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Ringmail Headpiece" },
    [31644] = { slot = "SHOULDER", class = "SHAMAN", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Ringmail Shoulders" },
    [31640] = { slot = "CHEST", class = "SHAMAN", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Grand Marshal's Ringmail Chestguard" },
    [31641] = { slot = "HANDS", class = "SHAMAN", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Ringmail Gloves" },
    [31643] = { slot = "LEGS", class = "SHAMAN", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Ringmail Legguards" },

    -- SHAMAN - High Warlord's Wartide (Horde) - Set 696
    -- AtlasLoot order: {31648,31650,31646,31647,31649} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [31648] = { slot = "HEAD", class = "SHAMAN", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Ringmail Headpiece" },
    [31650] = { slot = "SHOULDER", class = "SHAMAN", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Ringmail Shoulders" },
    [31646] = { slot = "CHEST", class = "SHAMAN", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "High Warlord's Ringmail Chestguard" },
    [31647] = { slot = "HANDS", class = "SHAMAN", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Ringmail Gloves" },
    [31649] = { slot = "LEGS", class = "SHAMAN", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Ringmail Legguards" },

    -- ==========================================
    -- MAGE - Grand Marshal's Regalia (Alliance) - Set 599
    -- AtlasLoot order: {28715,28714,28717,28716,28718} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    -- ==========================================
    [28715] = { slot = "HEAD", class = "MAGE", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Silk Cowl" },
    [28714] = { slot = "SHOULDER", class = "MAGE", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Silk Amice" },
    [28717] = { slot = "CHEST", class = "MAGE", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Grand Marshal's Silk Raiment" },
    [28716] = { slot = "HANDS", class = "MAGE", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Silk Handguards" },
    [28718] = { slot = "LEGS", class = "MAGE", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Silk Trousers" },

    -- MAGE - High Warlord's Regalia (Horde) - Set 600
    -- AtlasLoot order: {28867,28866,28869,28868,28870} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [28867] = { slot = "HEAD", class = "MAGE", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Silk Cowl" },
    [28866] = { slot = "SHOULDER", class = "MAGE", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Silk Amice" },
    [28869] = { slot = "CHEST", class = "MAGE", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "High Warlord's Silk Raiment" },
    [28868] = { slot = "HANDS", class = "MAGE", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Silk Handguards" },
    [28870] = { slot = "LEGS", class = "MAGE", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Silk Trousers" },

    -- ==========================================
    -- WARLOCK - Grand Marshal's Dreadgear (Alliance) - Set 591
    -- AtlasLoot order: {28625,28627,28628,28624,28626} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    -- ==========================================
    [28625] = { slot = "HEAD", class = "WARLOCK", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Dreadweave Hood" },
    [28627] = { slot = "SHOULDER", class = "WARLOCK", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Dreadweave Mantle" },
    [28628] = { slot = "CHEST", class = "WARLOCK", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Grand Marshal's Dreadweave Robe" },
    [28624] = { slot = "HANDS", class = "WARLOCK", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Dreadweave Gloves" },
    [28626] = { slot = "LEGS", class = "WARLOCK", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Dreadweave Leggings" },

    -- WARLOCK - High Warlord's Dreadgear (Horde) - Set 592
    -- AtlasLoot order: {28818,28820,28821,28817,28819} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [28818] = { slot = "HEAD", class = "WARLOCK", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Dreadweave Hood" },
    [28820] = { slot = "SHOULDER", class = "WARLOCK", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Dreadweave Mantle" },
    [28821] = { slot = "CHEST", class = "WARLOCK", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "High Warlord's Dreadweave Robe" },
    [28817] = { slot = "HANDS", class = "WARLOCK", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Dreadweave Gloves" },
    [28819] = { slot = "LEGS", class = "WARLOCK", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Dreadweave Leggings" },

    -- ==========================================
    -- DRUID - Grand Marshal's Sanctuary (Alliance) - Feral - Set 601
    -- AtlasLoot order: {28619,28622,28623,28618,28620} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    -- ==========================================
    [28619] = { slot = "HEAD", class = "DRUID", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Dragonhide Helm" },
    [28622] = { slot = "SHOULDER", class = "DRUID", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Dragonhide Spaulders" },
    [28623] = { slot = "CHEST", class = "DRUID", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Grand Marshal's Dragonhide Tunic" },
    [28618] = { slot = "HANDS", class = "DRUID", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Dragonhide Gloves" },
    [28620] = { slot = "LEGS", class = "DRUID", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Dragonhide Legguards" },

    -- DRUID - High Warlord's Sanctuary (Horde) - Feral - Set 602
    -- AtlasLoot order: {28812,28814,28815,28811,28813} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [28812] = { slot = "HEAD", class = "DRUID", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Dragonhide Helm" },
    [28814] = { slot = "SHOULDER", class = "DRUID", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Dragonhide Spaulders" },
    [28815] = { slot = "CHEST", class = "DRUID", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "High Warlord's Dragonhide Tunic" },
    [28811] = { slot = "HANDS", class = "DRUID", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Dragonhide Gloves" },
    [28813] = { slot = "LEGS", class = "DRUID", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Dragonhide Legguards" },

    -- DRUID - Grand Marshal's Wildhide (Alliance) - Balance - Set 609
    -- AtlasLoot order: {28720,28722,28723,28719,28721} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [28720] = { slot = "HEAD", class = "DRUID", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Wyrmhide Helm" },
    [28722] = { slot = "SHOULDER", class = "DRUID", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Wyrmhide Spaulders" },
    [28723] = { slot = "CHEST", class = "DRUID", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Grand Marshal's Wyrmhide Tunic" },
    [28719] = { slot = "HANDS", class = "DRUID", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Wyrmhide Gloves" },
    [28721] = { slot = "LEGS", class = "DRUID", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Wyrmhide Legguards" },

    -- DRUID - High Warlord's Wildhide (Horde) - Balance - Set 610
    -- AtlasLoot order: {28872,28874,28875,28871,28873} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [28872] = { slot = "HEAD", class = "DRUID", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Wyrmhide Helm" },
    [28874] = { slot = "SHOULDER", class = "DRUID", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Wyrmhide Spaulders" },
    [28875] = { slot = "CHEST", class = "DRUID", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "High Warlord's Wyrmhide Tunic" },
    [28871] = { slot = "HANDS", class = "DRUID", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Wyrmhide Gloves" },
    [28873] = { slot = "LEGS", class = "DRUID", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Wyrmhide Legguards" },

    -- DRUID - Grand Marshal's Refuge (Alliance) - Restoration - Set 688
    -- AtlasLoot order: {31590,31592,31593,31589,31591} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [31590] = { slot = "HEAD", class = "DRUID", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Kodohide Helm" },
    [31592] = { slot = "SHOULDER", class = "DRUID", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Kodohide Spaulders" },
    [31593] = { slot = "CHEST", class = "DRUID", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Grand Marshal's Kodohide Tunic" },
    [31589] = { slot = "HANDS", class = "DRUID", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Kodohide Gloves" },
    [31591] = { slot = "LEGS", class = "DRUID", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Kodohide Legguards" },

    -- DRUID - High Warlord's Refuge (Horde) - Restoration - Set 689
    -- AtlasLoot order: {31585,31587,31588,31584,31586} = {HEAD,SHOULDER,CHEST,HANDS,LEGS}
    [31585] = { slot = "HEAD", class = "DRUID", honor = 14280, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Kodohide Helm" },
    [31587] = { slot = "SHOULDER", class = "DRUID", honor = 11794, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Kodohide Spaulders" },
    [31588] = { slot = "CHEST", class = "DRUID", honor = 14280, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "High Warlord's Kodohide Tunic" },
    [31584] = { slot = "HANDS", class = "DRUID", honor = 10360, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Kodohide Gloves" },
    [31586] = { slot = "LEGS", class = "DRUID", honor = 14280, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Kodohide Legguards" },

    -- ==========================================
    -- HONOR70 WEAPONS - Grand Marshal's (Alliance)
    -- ==========================================

    -- One-Handed Daggers
    [28954] = { slot = "MAIN_HAND", class = nil, honor = 17850, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Shanker" },
    [28955] = { slot = "OFF_HAND", class = nil, honor = 9178, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Shiv" },

    -- One-Handed Maces
    [28951] = { slot = "MAIN_HAND", class = nil, honor = 17850, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Pummeler" },
    [28950] = { slot = "ONE_HAND", class = nil, honor = 17850, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Bonecracker" },

    -- One-Handed Swords
    [28956] = { slot = "MAIN_HAND", class = nil, honor = 17850, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Slicer" },
    [28952] = { slot = "ONE_HAND", class = nil, honor = 17850, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Quickblade" },

    -- One-Handed Axes
    [28944] = { slot = "MAIN_HAND", class = nil, honor = 17850, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Cleaver" },
    [28946] = { slot = "ONE_HAND", class = nil, honor = 17850, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Hacker" },

    -- One-Handed Fist Weapons
    [28953] = { slot = "MAIN_HAND", class = nil, honor = 17850, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Right Ripper" },
    [28947] = { slot = "OFF_HAND", class = nil, honor = 9178, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Left Ripper" },

    -- Caster One-Hand
    [28957] = { slot = "MAIN_HAND", class = nil, honor = 17850, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "Grand Marshal's Spellblade" },

    -- Two-Handed Swords
    [28943] = { slot = "TWO_HAND", class = nil, honor = 38250, arena = 0, marks = { EotS = 40 }, season = "HONOR70", name = "Grand Marshal's Warblade" },

    -- Two-Handed Axes
    [28945] = { slot = "TWO_HAND", class = nil, honor = 38250, arena = 0, marks = { EotS = 40 }, season = "HONOR70", name = "Grand Marshal's Decapitator" },

    -- Two-Handed Maces
    [28942] = { slot = "TWO_HAND", class = nil, honor = 38250, arena = 0, marks = { EotS = 40 }, season = "HONOR70", name = "Grand Marshal's Bonegrinder" },
    [28948] = { slot = "TWO_HAND", class = nil, honor = 38250, arena = 0, marks = { EotS = 40 }, season = "HONOR70", name = "Grand Marshal's Maul" },

    -- Polearms
    [28949] = { slot = "TWO_HAND", class = nil, honor = 38250, arena = 0, marks = { EotS = 40 }, season = "HONOR70", name = "Grand Marshal's Painsaw" },

    -- Staves
    [28959] = { slot = "TWO_HAND", class = nil, honor = 38250, arena = 0, marks = { EotS = 40 }, season = "HONOR70", name = "Grand Marshal's War Staff" },

    -- Ranged
    [28960] = { slot = "RANGED", class = nil, honor = 17850, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Grand Marshal's Heavy Crossbow" },

    -- Off-Hand
    [28940] = { slot = "OFF_HAND", class = nil, honor = 15300, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Grand Marshal's Barricade" },
    [28941] = { slot = "OFF_HAND", class = nil, honor = 9199, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Grand Marshal's Battletome" },

    -- ==========================================
    -- HONOR70 WEAPONS - High Warlord's (Horde)
    -- ==========================================

    -- One-Handed Daggers
    [28929] = { slot = "MAIN_HAND", class = nil, honor = 17850, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Shanker" },
    [28930] = { slot = "OFF_HAND", class = nil, honor = 9178, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Shiv" },

    -- One-Handed Maces
    [28925] = { slot = "MAIN_HAND", class = nil, honor = 17850, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Pummeler" },
    [28924] = { slot = "ONE_HAND", class = nil, honor = 17850, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Bonecracker" },

    -- One-Handed Swords
    [28937] = { slot = "MAIN_HAND", class = nil, honor = 17850, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Slicer" },
    [28926] = { slot = "ONE_HAND", class = nil, honor = 17850, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Quickblade" },

    -- One-Handed Axes
    [28920] = { slot = "MAIN_HAND", class = nil, honor = 17850, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Cleaver" },
    [28921] = { slot = "ONE_HAND", class = nil, honor = 17850, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Hacker" },

    -- One-Handed Fist Weapons
    [28928] = { slot = "MAIN_HAND", class = nil, honor = 17850, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Right Ripper" },
    [28922] = { slot = "OFF_HAND", class = nil, honor = 9178, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Left Ripper" },

    -- Caster One-Hand
    [28931] = { slot = "MAIN_HAND", class = nil, honor = 17850, arena = 0, marks = { EotS = 20 }, season = "HONOR70", name = "High Warlord's Spellblade" },

    -- Two-Handed Swords
    [28293] = { slot = "TWO_HAND", class = nil, honor = 38250, arena = 0, marks = { EotS = 40 }, season = "HONOR70", name = "High Warlord's Claymore" },

    -- Two-Handed Axes
    [28918] = { slot = "TWO_HAND", class = nil, honor = 38250, arena = 0, marks = { EotS = 40 }, season = "HONOR70", name = "High Warlord's Decapitator" },

    -- Two-Handed Maces
    [28917] = { slot = "TWO_HAND", class = nil, honor = 38250, arena = 0, marks = { EotS = 40 }, season = "HONOR70", name = "High Warlord's Bonegrinder" },
    [28919] = { slot = "TWO_HAND", class = nil, honor = 38250, arena = 0, marks = { EotS = 40 }, season = "HONOR70", name = "High Warlord's Maul" },

    -- Polearms
    [28923] = { slot = "TWO_HAND", class = nil, honor = 38250, arena = 0, marks = { EotS = 40 }, season = "HONOR70", name = "High Warlord's Painsaw" },

    -- Staves
    [28935] = { slot = "TWO_HAND", class = nil, honor = 38250, arena = 0, marks = { EotS = 40 }, season = "HONOR70", name = "High Warlord's War Staff" },

    -- Ranged
    [28933] = { slot = "RANGED", class = nil, honor = 17850, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "High Warlord's Heavy Crossbow" },

    -- Off-Hand
    [28939] = { slot = "OFF_HAND", class = nil, honor = 15300, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "High Warlord's Barricade" },
    [28938] = { slot = "OFF_HAND", class = nil, honor = 9199, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "High Warlord's Battletome" },

    -- ==========================================
    -- HONOR70 OFF-PIECES - Veteran's Gear
    -- ==========================================

    -- Neck (Pendants) - All classes
    [33066] = { slot = "NECK", class = nil, honor = 15300, arena = 0, marks = { EotS = 10 }, season = "HONOR70", name = "Veteran's Pendant of Triumph" },
    [33068] = { slot = "NECK", class = nil, honor = 15300, arena = 0, marks = { EotS = 10 }, season = "HONOR70", name = "Veteran's Pendant of Salvation" },
    [33065] = { slot = "NECK", class = nil, honor = 15300, arena = 0, marks = { EotS = 10 }, season = "HONOR70", name = "Veteran's Pendant of Dominance" },
    [33067] = { slot = "NECK", class = nil, honor = 15300, arena = 0, marks = { EotS = 10 }, season = "HONOR70", name = "Veteran's Pendant of Conquest" },

    -- Rings (Bands) - All classes
    [33057] = { slot = "FINGER", class = nil, honor = 10500, arena = 0, marks = { AV = 10 }, season = "HONOR70", name = "Veteran's Band of Triumph" },
    [33064] = { slot = "FINGER", class = nil, honor = 10500, arena = 0, marks = { AV = 10 }, season = "HONOR70", name = "Veteran's Band of Salvation" },
    [33056] = { slot = "FINGER", class = nil, honor = 10500, arena = 0, marks = { AV = 10 }, season = "HONOR70", name = "Veteran's Band of Dominance" },

    -- ==========================================
    -- CLOTH OFF-PIECES
    -- ==========================================

    -- Mage - Veteran's Silk
    [32820] = { slot = "WRIST", class = "MAGE", honor = 7548, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Veteran's Silk Cuffs" },
    [32807] = { slot = "WAIST", class = "MAGE", honor = 7548, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Veteran's Silk Belt" },
    [32795] = { slot = "FEET", class = "MAGE", honor = 10360, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Veteran's Silk Footguards" },

    -- Warlock - Veteran's Dreadweave
    [32811] = { slot = "WRIST", class = "WARLOCK", honor = 7548, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Veteran's Dreadweave Cuffs" },
    [32799] = { slot = "WAIST", class = "WARLOCK", honor = 7548, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Veteran's Dreadweave Belt" },
    [32787] = { slot = "FEET", class = "WARLOCK", honor = 10360, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Veteran's Dreadweave Stalkers" },

    -- Priest - Veteran's Mooncloth
    [32980] = { slot = "WRIST", class = "PRIEST", honor = 7548, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Veteran's Mooncloth Cuffs" },
    [32979] = { slot = "WAIST", class = "PRIEST", honor = 7548, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Veteran's Mooncloth Belt" },
    [32981] = { slot = "FEET", class = "PRIEST", honor = 10360, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Veteran's Mooncloth Slippers" },

    -- ==========================================
    -- LEATHER OFF-PIECES
    -- ==========================================

    -- Druid Feral - Veteran's Dragonhide
    [32810] = { slot = "WRIST", class = "DRUID", honor = 7548, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Veteran's Dragonhide Bracers" },
    [32798] = { slot = "WAIST", class = "DRUID", honor = 7548, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Veteran's Dragonhide Belt" },
    [32786] = { slot = "FEET", class = "DRUID", honor = 10360, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Veteran's Dragonhide Boots" },

    -- Rogue - Veteran's Leather
    [32814] = { slot = "WRIST", class = "ROGUE", honor = 7548, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Veteran's Leather Bracers" },
    [32802] = { slot = "WAIST", class = "ROGUE", honor = 7548, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Veteran's Leather Belt" },
    [32790] = { slot = "FEET", class = "ROGUE", honor = 10360, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Veteran's Leather Boots" },

    -- Druid Resto - Veteran's Kodohide
    [32812] = { slot = "WRIST", class = "DRUID", honor = 7548, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Veteran's Kodohide Bracers" },
    [32800] = { slot = "WAIST", class = "DRUID", honor = 7548, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Veteran's Kodohide Belt" },
    [32788] = { slot = "FEET", class = "DRUID", honor = 10360, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Veteran's Kodohide Boots" },

    -- Druid Balance - Veteran's Wyrmhide
    [32821] = { slot = "WRIST", class = "DRUID", honor = 7548, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Veteran's Wyrmhide Bracers" },
    [32808] = { slot = "WAIST", class = "DRUID", honor = 7548, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Veteran's Wyrmhide Belt" },
    [32796] = { slot = "FEET", class = "DRUID", honor = 10360, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Veteran's Wyrmhide Boots" },

    -- ==========================================
    -- MAIL OFF-PIECES
    -- ==========================================

    -- Shaman Enhancement - Veteran's Ringmail
    [32997] = { slot = "WRIST", class = "SHAMAN", honor = 7548, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Veteran's Ringmail Bracers" },
    [32998] = { slot = "WAIST", class = "SHAMAN", honor = 7548, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Veteran's Ringmail Girdle" },
    [32999] = { slot = "FEET", class = "SHAMAN", honor = 10360, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Veteran's Ringmail Sabatons" },

    -- Hunter - Veteran's Mail
    [32817] = { slot = "WRIST", class = "HUNTER", honor = 7548, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Veteran's Mail Bracers" },
    [32804] = { slot = "WAIST", class = "HUNTER", honor = 7548, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Veteran's Mail Girdle" },
    [32792] = { slot = "FEET", class = "HUNTER", honor = 10360, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Veteran's Mail Sabatons" },

    -- Shaman Elemental - Veteran's Linked
    [32816] = { slot = "WRIST", class = "SHAMAN", honor = 7548, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Veteran's Linked Bracers" },
    [32803] = { slot = "WAIST", class = "SHAMAN", honor = 7548, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Veteran's Linked Girdle" },
    [32791] = { slot = "FEET", class = "SHAMAN", honor = 10360, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Veteran's Linked Sabatons" },

    -- Shaman Resto - Veteran's Chain
    [32809] = { slot = "WRIST", class = "SHAMAN", honor = 7548, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Veteran's Chain Bracers" },
    [32797] = { slot = "WAIST", class = "SHAMAN", honor = 7548, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Veteran's Chain Girdle" },
    [32785] = { slot = "FEET", class = "SHAMAN", honor = 10360, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Veteran's Chain Sabatons" },

    -- ==========================================
    -- PLATE OFF-PIECES
    -- ==========================================

    -- Paladin Retribution - Veteran's Scaled
    [32819] = { slot = "WRIST", class = "PALADIN", honor = 7548, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Veteran's Scaled Bracers" },
    [32806] = { slot = "WAIST", class = "PALADIN", honor = 7548, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Veteran's Scaled Belt" },
    [32794] = { slot = "FEET", class = "PALADIN", honor = 10360, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Veteran's Scaled Greaves" },

    -- Warrior - Veteran's Plate
    [32818] = { slot = "WRIST", class = "WARRIOR", honor = 7548, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Veteran's Plate Bracers" },
    [32805] = { slot = "WAIST", class = "WARRIOR", honor = 7548, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Veteran's Plate Belt" },
    [32793] = { slot = "FEET", class = "WARRIOR", honor = 10360, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Veteran's Plate Greaves" },

    -- Paladin Holy - Veteran's Ornamented
    [32989] = { slot = "WRIST", class = "PALADIN", honor = 7548, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Veteran's Ornamented Bracers" },
    [32988] = { slot = "WAIST", class = "PALADIN", honor = 7548, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Veteran's Ornamented Belt" },
    [32990] = { slot = "FEET", class = "PALADIN", honor = 10360, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Veteran's Ornamented Greaves" },

    -- Paladin Protection - Veteran's Lamellar
    [32813] = { slot = "WRIST", class = "PALADIN", honor = 7548, arena = 0, marks = { WSG = 20 }, season = "HONOR70", name = "Veteran's Lamellar Bracers" },
    [32801] = { slot = "WAIST", class = "PALADIN", honor = 7548, arena = 0, marks = { AB = 20 }, season = "HONOR70", name = "Veteran's Lamellar Belt" },
    [32789] = { slot = "FEET", class = "PALADIN", honor = 10360, arena = 0, marks = { AV = 20 }, season = "HONOR70", name = "Veteran's Lamellar Greaves" },

    -- ==========================================
    -- HONOR70 TRINKETS - Medallions
    -- ==========================================

    -- Alliance Medallions (PvP Trinket)
    [37864] = { slot = "TRINKET", class = nil, honor = 40000, arena = 0, marks = {}, season = "HONOR70", name = "Medallion of the Alliance" },

    -- Horde Medallions (PvP Trinket)
    [37865] = { slot = "TRINKET", class = nil, honor = 40000, arena = 0, marks = {}, season = "HONOR70", name = "Medallion of the Horde" },

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
