-- HonorLog vendor table, written by hand (not generated).
-- Source: Wowhead Forever NPC tooltip API (nether.wowhead.com/forever/tooltip/npc/<id>), read 2026-11-20; uiMap ids from wago UiMap, build 1.60.1.71037
--
-- One row per PvP vendor: npc id, name, role text, kind (armor, accessories, weapons, mount,
-- supply), faction, place text, uiMap id and x, y in percent of the map where known, and for supply
-- officers the reputation faction they sell for. HonorLog:GetVendorFor (Data.lua) picks the row.
-- The Horde quartermasters' coordinates were read in the game on 2026-11-21 (where the player stood at each
-- vendor in the Hall of Legends, so within a few steps). Unknown, so left out: the Darkspear Islands vendors
-- for factions 2798 and 2799. Which vendor sells which item is not in this table either; the vendor scan
-- records that.

local _, HonorLog = ...
HonorLog = HonorLog or {}

HonorLog.VENDORS = {
    { npc = 12792, name = "Lady Palanseer", role = "Armor Quartermaster", kind = "armor", faction = "Horde",
      place = "Hall of Legends, Orgrimmar", map = 1454, x = 37.0, y = 65.0 },
    { npc = 12793, name = "Brave Stonehide", role = "Officer Accessories Quartermaster", kind = "accessories",
      faction = "Horde", place = "Hall of Legends, Orgrimmar", map = 1454, x = 36.5, y = 66.2 },
    { npc = 14581, name = "Sergeant Thunderhorn", role = "Weapons Quartermaster", kind = "weapons", faction = "Horde",
      place = "Hall of Legends, Orgrimmar", map = 1454, x = 36.8, y = 67.3 },
    { npc = 12796, name = "Raider Bork", role = "Mount Quartermaster", kind = "mount", faction = "Horde",
      place = "Hall of Legends, Orgrimmar", map = 1454, x = 37.8, y = 64.4 },
    { npc = 12777, name = "Captain Dirgehammer", role = "Armor Quartermaster", kind = "armor", faction = "Alliance",
      place = "Champions' Hall, Stormwind City", map = 1453, x = 74.4, y = 67.5 },
    { npc = 12781, name = "Master Sergeant Biggins", role = "Officer Accessories Quartermaster", kind = "accessories",
      faction = "Alliance", place = "Champions' Hall, Stormwind City", map = 1453, x = 75.2, y = 67.2 },
    { npc = 12782, name = "Captain O'Neal", role = "Weapons Quartermaster", kind = "weapons", faction = "Alliance",
      place = "Champions' Hall, Stormwind City", map = 1453, x = 74.4, y = 67.4 },
    { npc = 12783, name = "Lieutenant Karter", role = "Mount Vendor", kind = "mount", faction = "Alliance",
      place = "Champions' Hall, Stormwind City", map = 1453, x = 74.4, y = 67.4 },
    { npc = 14754, name = "Kelm Hargunth", role = "Warsong Supply Officer", kind = "supply", faction = "Horde",
      repFaction = 889, place = "Mor'shan Base Camp, The Barrens", map = 1413, x = 46.6, y = 8.4 },
    { npc = 14753, name = "Illiyana Moonblaze", role = "Silverwing Supply Officer", kind = "supply", faction = "Alliance",
      repFaction = 890, place = "Silverwing Grove, Ashenvale", map = 1440, x = 61.4, y = 83.8 },
    { npc = 15126, name = "Rutherford Twing", role = "Defilers Supply Officer", kind = "supply", faction = "Horde",
      repFaction = 510, place = "Hammerfall, Arathi Highlands", map = 1417, x = 73.4, y = 29.8 },
    { npc = 15127, name = "Samuel Hawke", role = "League of Arathor Supply Officer", kind = "supply", faction = "Alliance",
      repFaction = 509, place = "Refuge Pointe, Arathi Highlands", map = 1417, x = 46.0, y = 45.2 },
    { npc = 13219, name = "Jekyll Flandring", role = "Frostwolf Supply Officer", kind = "supply", faction = "Horde",
      repFaction = 729, place = "Alterac Mountains", map = 1416, x = 62.8, y = 59.4 },
    { npc = 13217, name = "Thanthaldis Snowgleam", role = "Stormpike Supply Officer", kind = "supply", faction = "Alliance",
      repFaction = 730, place = "Alterac Mountains", map = 1416, x = 39.4, y = 81.4 },
}
