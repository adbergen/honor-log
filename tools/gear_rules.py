"""Hand-kept rules for tools/build_gear.py.

Everything here is knowledge the client tables do not carry: which vendor
cost row prices which kind of item, the Seal ranks, and the few faction and
id facts that have no data source. build_gear.py re-reads every IEC row named
below on every run and exits non-zero when the game data no longer matches.
"""

# Currency 1792 is Honor.
HONOR_CURRENCY = 1792

# Mark of Honor item id -> key used in the addon.
MARK_KEYS = {20560: "AV", 20559: "AB", 20558: "WSG", 274895: "DI"}

# Verified ItemExtendedCost rows (memory reference-forever-pvp-data, checked
# 2026-11-15). Each rule: IEC id, honor, marks by item id. The IEC table has no
# link back to items, so the item -> rule assignment is by slot or weapon type.
# Where two rows carry the same price (11584/11587/11591 and so on) the
# assignment of a row to a slot is arbitrary; only the amounts are verified.
BLUE_ARMOUR_RULES = {
    "HEAD":     {"iec": 11575, "honor": 9000, "marks": {20560: 15}},
    "SHOULDER": {"iec": 11576, "honor": 6350, "marks": {20559: 10}},
    "CHEST":    {"iec": 11578, "honor": 9350, "marks": {20559: 15}},
    "WRIST":    {"iec": 11579, "honor": 4500, "marks": {20558: 10}},
    "HANDS":    {"iec": 11580, "honor": 7500, "marks": {20558: 10}},
    "WAIST":    {"iec": 11581, "honor": 6000, "marks": {20559: 10}},
    "LEGS":     {"iec": 11582, "honor": 9000, "marks": {20558: 15}},
    "FEET":     {"iec": 11583, "honor": 7500, "marks": {274895: 10}},
}

# Rank rewards sold for honor. Keys are used by build_gear.rule_for().
RANK_RULES = {
    "BACK":      {"iec": 11577, "honor": 4500,  "marks": {20559: 10}},
    "NECK":      {"iec": 11595, "honor": 7500,  "marks": {274895: 10}},
    "TRINKET":   {"iec": 11596, "honor": 5250,  "marks": {}},  # plus BuyPrice gold, checked below
    "ONE_HAND":  {"iec": 11593, "honor": 12000, "marks": {274895: 10}},  # also ranged weapons
    "SHIELD":    {"iec": 11706, "honor": 10500, "marks": {274895: 10}},  # shields and tomes
    "TWO_HAND":  {"iec": 11594, "honor": 22500, "marks": {20560: 20}},
}

# Premier Emboldened Seals: item id -> (slot it upgrades, expected rank, IEC rule).
SEALS = {
    275241: ("HEAD",     13, {"iec": 11591, "honor": 2650, "marks": {}}),
    275238: ("CHEST",    13, {"iec": 11587, "honor": 2650, "marks": {}}),
    275242: ("LEGS",     12, {"iec": 11584, "honor": 2650, "marks": {}}),
    275229: ("SHOULDER", 12, {"iec": 11589, "honor": 2250, "marks": {}}),
    275239: ("HANDS",    10, {"iec": 11585, "honor": 2250, "marks": {}}),
    275243: ("FEET",      9, {"iec": 11592, "honor": 1500, "marks": {}}),
    275244: ("WAIST",     8, {"iec": 11590, "honor": 1500, "marks": {}}),
    275240: ("WRIST",     8, {"iec": 11586, "honor": 1200, "marks": {}}),
}

# Gold prices (copper) verified against ItemSparse.BuyPrice.
GOLD_CHECKS = {
    274444: 15000,    # Insignia trinket, 1g50s
    274445: 15000,
    18241: 1000000, 18242: 1000000, 18243: 1000000, 18244: 1000000,   # Alliance black war mounts, 100g
    18245: 1000000, 18246: 1000000, 18247: 1000000,                   # Horde black war mounts
}

# Rank rewards that are not "Premier" items: vanilla-numbered item ids that the
# Forever tooltip shows with a Forever rank line. Found by scanning tooltips of
# every candidate consumable, mount, tabard, trinket and standard.
# id -> slot.
RANK_EXTRA = {
    274444: "TRINKET", 274445: "TRINKET",          # Greater Insignia, rank 2
    272449: "TABARD", 272694: "TABARD",             # rank 1
    272450: "TABARD", 272695: "TABARD",             # rank 6
    18606: "OTHER", 18607: "OTHER",                 # Battle Standards, rank 7
    18839: "CONSUMABLE", 18841: "CONSUMABLE",       # Combat potions, rank 5
    18241: "MOUNT", 18242: "MOUNT", 18243: "MOUNT", 18244: "MOUNT",
    18245: "MOUNT", 18246: "MOUNT", 18247: "MOUNT",  # rank 11
}

# Faction facts with no data source (no race flags, no PlayerCondition, no
# vendor listing). Each is an inference from the item's own name and is listed
# in --report. Premier armour sets are handled by SET_TIERS instead.
FACTION_OVERRIDE = {
    18606: "Alliance",  # Alliance Battle Standard
    18607: "Horde",     # Horde Battle Standard
    274445: "Alliance",  # Greater Insignia of the Alliance (274444 has a Horde vendor listing)
}

# Fallback when neither a race flag nor a vendor listing exists (Wowhead lists
# only some Horde vendors; two-handers, cloaks and Alliance items have none).
# The item's own rank title decides. build_gear.py cross-checks the tokens against
# the vendor listings that do exist and reports any disagreement.
NAME_TOKENS = {
    "High Warlord's": "Horde", "Grand Marshal's": "Alliance",
    "Sergeant's Cloak": "Horde", "Sergeant's Cape": "Alliance",
    "Senior Sergeant's Insignia": "Horde", "Master Sergeant's Insignia": "Alliance",
    "Scout's Tabard": "Horde", "Private's Tabard": "Alliance",
    "Stone Guard's Herald": "Horde", "Knight's Colors": "Alliance",
}

# Wowhead lists only Horde vendors for the PvP rank items. These NPC ids come
# from the Forever data (Brave Stonehide, Lady Palanseer, Sgt. Thunderhorn).
HORDE_VENDORS = {12793, 12792, 14581}

# Premier armour has no race flag and no vendor listing in any source. The only
# data that separates the factions is the ItemSet name, whose first words are
# the rank tier. tier -> (faction, grade).
SET_TIERS = {
    "Champion's": ("Horde", "blue"),
    "Warlord's": ("Horde", "epic"),
    "Lieutenant Commander's": ("Alliance", "blue"),
    "Field Marshal's": ("Alliance", "epic"),
}

# Reputation factions: id -> side. Data gives the faction; the side is fixed.
REP_SIDE = {509: "Alliance", 510: "Horde", 2798: "Horde", 2799: "Alliance",
            889: "Horde", 890: "Alliance", 729: "Horde", 730: "Alliance"}
# Items whose MinFactionID is set in the client data.
REP_DATA_FACTIONS = (509, 510, 2798, 2799)
# Items with no MinFactionID: faction is read from the tooltip. Accepted only for these.
REP_TOOLTIP_FACTIONS = (889, 890, 729, 730)
# Alterac Valley items (no rep fields in the client data), by id: tabards, mounts,
# standards, cloaks, belts and pendants. Tooltip gives the faction and standing.
# 19031/19032 tabards, 19029/19030 mounts, 19045/19046 standards,
# 19083-19098 gear; 19505/19506 are the Warsong Gulch tabards.
REP_EXTRA_IDS = [19029, 19030, 19031, 19032, 19045, 19046, 19505, 19506] + list(range(19083, 19099))

# Standing names in tooltips -> Blizzard standing ids.
STANDINGS = {"Hated": 1, "Hostile": 2, "Unfriendly": 3, "Neutral": 4,
             "Friendly": 5, "Honored": 6, "Revered": 7, "Exalted": 8}
