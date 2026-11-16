# HonorLog tools

## build_gear.py

Regenerates `Data/GearDatabase.lua` (every Forever PvP reward item with its cost and requirements).

```
python3 tools/build_gear.py            # write the file
python3 tools/build_gear.py --report   # also print coverage and the checks below
python3 tools/build_gear.py --refresh  # redownload the build list and tables first
```

Sources:

- wago.tools DB2 CSV for the newest `wowf` build (live Forever): `ItemSparse`, `Item`, `ItemExtendedCost`, `ItemSet`, `ChrClasses`, `Faction`.
- Wowhead Forever tooltip API (`nether.wowhead.com/forever/tooltip/item/<id>`) for rank and reputation lines. The client data has `RequiredPVPRank = 0` for every Forever-new item. One request at a time, 0.3 s apart.
- Wowhead Forever item XML (`www.wowhead.com/forever/item=<id>&xml`) for vendor listings, used only to tell Horde items from Alliance items.
- `tools/gear_rules.py`, kept by hand: the verified `ItemExtendedCost` rows per slot and weapon type, the Seal ranks, and the few ids and faction facts no source carries.

Downloads are cached in `tools/.cache/` (never committed). A warm rerun is offline and byte-identical. The header date is the wago build date, not today, to keep the output deterministic.

### The drift check

Every run re-reads each IEC row named in `gear_rules.py` and exits 1, without writing, if any honor or mark amount differs. It does the same for the Seal ranks (tooltip) and the verified gold prices (`BuyPrice`). When Blizzard hotfixes a price, update the rule after checking the vendor in game.

### How items are classified

- Blue Premier armour: priced by slot (`BLUE_ARMOUR_RULES`). Source `HONOR`.
- Epic Premier armour: source `UPGRADE`, `parts = { blue, seal }`. Cost is blue plus Seal; rank comes from the Seal.
  - Pairing: the epic's `ItemSet` name and the blue's `ItemSet` name are matched on class, rank tier (Champion's to Warlord's, Lieutenant Commander's to Field Marshal's) and theme word. Wrists and belts have no set, so they are matched on class, slot and the theme word of the item name.
- Seals: slot `TOKEN`. Weapons, shields, tomes, cloaks, necks, trinkets, tabards, standards, potions and the rank 11 mounts: source `RANK`.
- Reputation items: source `REP`. Data supplies the faction for Arathor Basin and Darkspear Islands. Warsong Gulch and Alterac Valley items have no faction in the data, so the tooltip supplies it. Items whose tooltip names several factions get `rep = { standing = n }` with no faction.
- Excluded: every item with `RequiredPVPRank > 0` in the client data (old vanilla and Season of Discovery rank encoding).

### Faction

No Premier item carries a race flag. Faction is taken, in order, from the race mask (mounts), a Horde vendor listing, the `ItemSet` rank tier (armour), and last the item's own rank title (`NAME_TOKENS`). `--report` lists which items rest on each.
