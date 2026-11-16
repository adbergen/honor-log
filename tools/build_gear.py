#!/usr/bin/env python3
"""Build Data/GearDatabase.lua from Forever's own game tables.

Reads DB2 tables as CSV from wago.tools (live Forever, product wowf), reads
rank and reputation requirements from the Wowhead Forever tooltip API (the
client data has RequiredPVPRank = 0 for every Forever-new item), and prices
the honor vendor items from a small hand-kept rule table (tools/gear_rules.py)
that is re-checked against ItemExtendedCost on every run. The run exits
non-zero when the game data no longer matches a rule.

Everything downloaded is cached under tools/.cache, so a rerun is offline and
byte-identical.

Usage:  python3 tools/build_gear.py [--refresh] [--report]
"""

import argparse
import csv
import io
import json
import pathlib
import re
import sys
import time
import urllib.request
from collections import Counter, defaultdict

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import gear_rules as R  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / ".cache"
OUT = ROOT / "Data" / "GearDatabase.lua"

MIRROR = "https://wago.tools"
PRODUCT = "wowf"
USER_AGENT = "HonorLog-gear-build/1.0 (+https://github.com/adbergen/honor-log)"
TOOLTIP_URL = "https://nether.wowhead.com/forever/tooltip/item/%d"
XML_URL = "https://www.wowhead.com/forever/item=%d&xml"
DELAY = 0.3  # seconds between network requests

TABLES = ["ItemSparse", "Item", "ItemExtendedCost", "ItemSet", "ChrClasses", "Faction"]

SLOTS = [
    "HEAD", "NECK", "SHOULDER", "BACK", "CHEST",
    "WRIST", "HANDS", "WAIST", "LEGS", "FEET",
    "FINGER", "TRINKET", "MAIN_HAND", "OFF_HAND",
    "TWO_HAND", "RANGED", "RELIC",
    "TABARD", "MOUNT", "TOKEN", "CONSUMABLE", "OTHER",
]
SLOT_INDEX = {s: i for i, s in enumerate(SLOTS)}

# InventoryType -> slot.
INV_SLOT = {
    1: "HEAD", 2: "NECK", 3: "SHOULDER", 5: "CHEST", 20: "CHEST", 6: "WAIST",
    7: "LEGS", 8: "FEET", 9: "WRIST", 10: "HANDS", 11: "FINGER", 12: "TRINKET",
    13: "MAIN_HAND", 21: "MAIN_HAND", 22: "OFF_HAND", 14: "OFF_HAND",
    23: "OFF_HAND", 17: "TWO_HAND", 15: "RANGED", 26: "RANGED", 25: "RANGED",
    28: "RELIC", 16: "BACK", 19: "TABARD",
}
ARMOUR_INV = {1, 3, 5, 20, 6, 7, 8, 9, 10}
ARMOUR_TYPE = {1: "CLOTH", 2: "LEATHER", 3: "MAIL", 4: "PLATE"}
WEAPON_RULE = {13: "ONE_HAND", 21: "ONE_HAND", 22: "ONE_HAND", 15: "ONE_HAND",
               26: "ONE_HAND", 25: "ONE_HAND", 14: "SHIELD", 23: "SHIELD",
               17: "TWO_HAND"}
HORDE_CORE_RACES = {2, 5, 6, 8, 10}
ALLIANCE_CORE_RACES = {1, 3, 4, 7, 11}

RANK_RE = re.compile(r"Requires ([^|]*?)\(Rank (\d+)\)")
REP_RE = re.compile(r"Requires ([^|]+?) - (Hated|Hostile|Unfriendly|Neutral|Friendly|Honored|Revered|Exalted)")


class Drift(Exception):
    pass


def fetch(url, delay=True):
    last = None
    for attempt in range(4):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=60) as response:
                body = response.read().decode("utf-8", "replace")
            if delay:
                time.sleep(DELAY)
            return body
        except Exception as error:  # noqa: BLE001
            last = error
            time.sleep(2 * (attempt + 1))
    raise SystemExit("fetch failed: %s (%s)" % (url, last))


def latest_build(refresh):
    path = CACHE / "builds.json"
    if refresh or not path.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        path.write_text(fetch(MIRROR + "/api/builds", delay=False))
    builds = json.loads(path.read_text())[PRODUCT]
    builds.sort(key=lambda b: b["created_at"], reverse=True)
    return builds[0]["version"], builds[0]["created_at"][:10]


def load_table(build, name, refresh):
    folder = CACHE / build
    path = folder / (name + ".csv")
    if refresh or not path.exists():
        folder.mkdir(parents=True, exist_ok=True)
        path.write_text(fetch("%s/db2/%s/csv?build=%s" % (MIRROR, name, build)))
    return list(csv.DictReader(io.StringIO(path.read_text())))


def cached(kind, item_id, url, ext):
    path = CACHE / kind / ("%d.%s" % (item_id, ext))
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(fetch(url % item_id))
    return path.read_text()


def tooltip(item_id):
    """Return (rank, [(faction name, standing id)]) from the Wowhead tooltip."""
    data = json.loads(cached("tooltip", item_id, TOOLTIP_URL, "json"))
    html = re.sub(r"<br ?/?>|</td>|</tr>|</th>", "|", data["tooltip"])
    text = re.sub(r"<[^>]+>", "", html)
    rank = RANK_RE.search(text)
    reps = []
    for match in REP_RE.finditer(text):
        reps.append((match.group(1).split("Requires ")[-1].strip(), R.STANDINGS[match.group(2)]))
    return (int(rank.group(2)) if rank else None), reps


def vendors(item_id):
    """NPC ids that Wowhead lists as selling the item."""
    xml = cached("xml", item_id, XML_URL, "xml")
    match = re.search(r'"sourcemore":\[(.*?)\]', xml)
    return {int(n) for n in re.findall(r'"ti":(\d+)', match.group(1))} if match else set()


def race_faction(mask):
    mask = int(mask) & 0xFFFFFFFF
    if mask == 0xFFFFFFFF:
        return None
    races = {i + 1 for i in range(32) if mask >> i & 1}
    horde, alliance = bool(races & HORDE_CORE_RACES), bool(races & ALLIANCE_CORE_RACES)
    if horde and not alliance:
        return "Horde"
    if alliance and not horde:
        return "Alliance"
    return None


def lua_str(value):
    return '"%s"' % str(value).replace("\\", "\\\\").replace('"', '\\"')


def gold_text(copper):
    return "%dg %ds %dc" % (copper // 10000, copper // 100 % 100, copper % 100)


def check_iec(iec_rows):
    """Compare every hand-kept rule with its ItemExtendedCost row."""
    rules = {}
    for table in (R.BLUE_ARMOUR_RULES, R.RANK_RULES):
        for key, rule in table.items():
            rules["%s" % key] = rule
    for item_id, (slot, _rank, rule) in R.SEALS.items():
        rules["SEAL:%s" % slot] = rule
    problems, ok = [], []
    for key, rule in sorted(rules.items()):
        row = iec_rows.get(rule["iec"])
        if row is None:
            problems.append("IEC %d (%s) is missing" % (rule["iec"], key))
            continue
        honor = marks = None
        honor = sum(int(row["CurrencyCount_%d" % i]) for i in range(5)
                    if int(row["CurrencyID_%d" % i]) == R.HONOR_CURRENCY)
        marks = {int(row["ItemID_%d" % i]): int(row["ItemCount_%d" % i]) for i in range(5)
                 if int(row["ItemID_%d" % i])}
        if honor != rule["honor"] or marks != rule["marks"]:
            problems.append("IEC %d (%s): data honor=%d marks=%s, rule honor=%d marks=%s"
                            % (rule["iec"], key, honor, marks, rule["honor"], rule["marks"]))
        else:
            ok.append(rule["iec"])
    return problems, len(rules), len(ok)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--refresh", action="store_true", help="redownload the build list and tables")
    parser.add_argument("--report", action="store_true", help="print coverage and checks")
    args = parser.parse_args()

    build, build_date = latest_build(args.refresh)
    tables = {name: load_table(build, name, args.refresh) for name in TABLES}
    sparse = {int(r["ID"]): r for r in tables["ItemSparse"]}
    item = {int(r["ID"]): r for r in tables["Item"]}
    iec_rows = {int(r["ID"]): r for r in tables["ItemExtendedCost"]}
    sets = {int(r["ID"]): r["Name_lang"] for r in tables["ItemSet"]}
    faction_names = {int(r["ID"]): r["Name_lang"] for r in tables["Faction"]}
    faction_ids = {name: fid for fid, name in faction_names.items()}
    classes = {1 << (int(r["ID"]) - 1): r["Filename"].upper() for r in tables["ChrClasses"]}

    # ---- drift checks (fatal) --------------------------------------------------
    problems, rule_count, rule_ok = check_iec(iec_rows)
    for item_id, copper in R.GOLD_CHECKS.items():
        if int(sparse[item_id]["BuyPrice"]) != copper:
            problems.append("BuyPrice of %d is %s, rule says %d" % (item_id, sparse[item_id]["BuyPrice"], copper))
    notes = defaultdict(list)  # report sections

    def base(item_id):
        row, meta = sparse[item_id], item.get(item_id, {})
        inv = int(row["InventoryType"])
        cls_id, sub_id = int(meta.get("ClassID", -1)), int(meta.get("SubclassID", -1))
        if inv in INV_SLOT:
            slot = INV_SLOT[inv]
        elif cls_id == 15:
            slot = "MOUNT"
        elif cls_id == 0 and sub_id == 8:
            slot = "OTHER"
        elif cls_id == 0:
            slot = "CONSUMABLE"
        else:
            slot = "OTHER"
        mask = int(row["AllowableClass"])
        entry = {
            "name": row["Display_lang"], "slot": slot,
            "class": classes.get(mask) if mask > 0 and mask in classes else None,
            "armor": ARMOUR_TYPE.get(sub_id) if inv in ARMOUR_INV and cls_id == 4 else None,
            "faction": None, "quality": int(row["OverallQualityID"]),
            "ilvl": int(row["ItemLevel"]), "reqLevel": int(row["RequiredLevel"]),
        }
        if mask > 0 and mask not in classes and mask != 0x7FFF:
            notes["multi-class mask"].append((item_id, mask))
        return entry

    entries = {}
    tt_rank = {}

    def faction_for(item_id):
        """Vendor listing first, then the hand-kept name tokens; nil when neither knows."""
        if item_id in R.FACTION_OVERRIDE:
            notes["faction inferred from the item name (no data source)"].append(item_id)
            return R.FACTION_OVERRIDE[item_id]
        name = sparse[item_id]["Display_lang"]
        token = next((f for t, f in R.NAME_TOKENS.items() if t in name), None)
        if vendors(item_id) & R.HORDE_VENDORS:
            if token and token != "Horde":
                notes["vendor listing disagrees with name token"].append(item_id)
            notes["faction from a Horde vendor listing"].append(item_id)
            return "Horde"
        if token:
            notes["faction inferred from the item name (no data source)"].append(item_id)
            return token
        notes["faction nil (no vendor, no token)"].append(item_id)
        return None

    # ---- Premier items ---------------------------------------------------------
    premier = sorted(i for i, r in sparse.items() if "Premier" in r["Display_lang"])
    blue_armour, epic_armour, unclassified = {}, {}, []
    for item_id in premier:
        row, meta = sparse[item_id], item.get(item_id, {})
        inv, quality = int(row["InventoryType"]), int(row["OverallQualityID"])
        rank, _reps = tooltip(item_id)
        tt_rank[item_id] = rank
        entry = base(item_id)
        if item_id in R.SEALS:
            slot, expected, rule = R.SEALS[item_id]
            if rank != expected:
                problems.append("Seal %d (%s) tooltip rank %s, rule says %d" % (item_id, slot, rank, expected))
            entry.update(slot="TOKEN", source="RANK", honor=rule["honor"], rank=rank, iec=rule["iec"])
            entries[item_id] = entry
        elif inv in ARMOUR_INV and int(meta.get("ClassID", -1)) == 4 and quality in (3, 4):
            (blue_armour if quality == 3 else epic_armour)[item_id] = entry
        elif quality == 4 and inv in WEAPON_RULE:
            rule = R.RANK_RULES[WEAPON_RULE[inv]]
            entry.update(source="RANK", honor=rule["honor"], marks=dict(rule["marks"]), rank=rank, iec=rule["iec"],
                         faction=faction_for(item_id))
            entries[item_id] = entry
        elif quality == 3 and inv in (16, 2):
            rule = R.RANK_RULES["BACK" if inv == 16 else "NECK"]
            entry.update(source="RANK", honor=rule["honor"], marks=dict(rule["marks"]), rank=rank, iec=rule["iec"],
                         faction=faction_for(item_id))
            entries[item_id] = entry
        else:
            unclassified.append(item_id)

    # Blue armour: honor vendor, priced by slot; epic: blue plus Seal.
    def set_info(item_id):
        match = re.match(r"(Champion's|Warlord's|Lieutenant Commander's|Field Marshal's) (.+)$",
                         sets.get(int(sparse[item_id]["ItemSet"]), ""))
        if not match:
            return None
        faction, grade = R.SET_TIERS[match.group(1)]
        return faction, grade, match.group(2), match.group(1)

    def theme_of(name):
        words = name.replace("Premier ", "", 1).split()
        for i, word in enumerate(words[:3]):
            if word.endswith("'s") and i < len(words) - 2:
                words = words[i + 1:]  # drop an epic's rank title (Legionnaire's, Field Marshal's ...)
                break
        return words[0]

    theme_faction = {}  # (class mask, theme) -> faction, learned from the pieces that sit in a set
    clashes = set()
    for item_id in list(blue_armour) + list(epic_armour):
        info = set_info(item_id)
        if info:
            key = (sparse[item_id]["AllowableClass"], theme_of(sparse[item_id]["Display_lang"]))
            if theme_faction.setdefault(key, info[0]) != info[0]:
                clashes.add(key)
    if clashes:
        notes["theme words used by both factions"] = sorted(clashes)

    set_blue = {}  # (class mask, faction, theme) -> set id
    for item_id in blue_armour:
        info = set_info(item_id)
        if info and info[1] == "blue":
            set_blue[(sparse[item_id]["AllowableClass"], info[0], info[2])] = int(sparse[item_id]["ItemSet"])
    for item_id, entry in blue_armour.items():
        info = set_info(item_id)
        rule = R.BLUE_ARMOUR_RULES[entry["slot"]]
        tkey = (sparse[item_id]["AllowableClass"], theme_of(entry["name"]))
        faction = info[0] if info else (theme_faction.get(tkey) if tkey not in clashes else None)
        if not info:
            notes["set-less blue armour: faction from the theme word of its set mates"].append(item_id)
        entry.update(source="HONOR", honor=rule["honor"], marks=dict(rule["marks"]), iec=rule["iec"],
                     faction=faction, rank=tt_rank[item_id])
        if tt_rank[item_id]:
            notes["blue armour with a tooltip rank"].append(item_id)
        if not faction:
            notes["armour with faction nil"].append(item_id)
        entries[item_id] = entry

    seal_by_slot = {slot: (sid, rank, rule) for sid, (slot, rank, rule) in R.SEALS.items()}
    by_set_slot = defaultdict(list)
    by_theme_slot = defaultdict(list)
    for item_id, entry in blue_armour.items():
        by_set_slot[(int(sparse[item_id]["ItemSet"]), entry["slot"])].append(item_id)
        by_theme_slot[(sparse[item_id]["AllowableClass"], theme_of(entry["name"]), entry["slot"])].append(item_id)
    icon_match = icon_total = 0
    unpaired = []
    for item_id, entry in epic_armour.items():
        info = set_info(item_id)
        blue_id = None
        if info and info[1] == "epic":
            blue_tier = {"Warlord's": "Champion's", "Field Marshal's": "Lieutenant Commander's"}[info[3]]
            blue_set = set_blue.get((sparse[item_id]["AllowableClass"], info[0], info[2]))
            cands = by_set_slot.get((blue_set, entry["slot"]), []) if blue_set else []
            if len(cands) == 1:
                blue_id = cands[0]
        if blue_id is None and not info:
            cands = by_theme_slot.get((sparse[item_id]["AllowableClass"], theme_of(entry["name"]), entry["slot"]), [])
            if len(cands) == 1:
                blue_id = cands[0]
                notes["set-less epic paired to its blue by class, slot and theme word"].append(item_id)
                info = (entries[blue_id]["faction"],)
        if blue_id is None:
            unpaired.append(item_id)
            entry.update(faction=info[0] if info else None, source="UPGRADE")
            entries[item_id] = entry
            continue
        seal_id, seal_rank, seal_rule = seal_by_slot[entry["slot"]]
        blue = entries[blue_id]
        icon_total += 1
        icon_match += item[item_id]["IconFileDataID"] == item[blue_id]["IconFileDataID"]
        epic_rank = tt_rank[item_id]
        entry.update(faction=info[0], source="UPGRADE", parts=[blue_id, seal_id],
                     honor=blue["honor"] + seal_rule["honor"], marks=dict(blue["marks"]),
                     rank=epic_rank if epic_rank else tt_rank[seal_id])
        if not epic_rank:
            notes["rank inferred from the Seal (epic tooltip has no rank line)"].append(item_id)
        entries[item_id] = entry

    # ---- rank rewards that are not Premier items ----------------------------------
    for item_id, slot in R.RANK_EXTRA.items():
        row = sparse[item_id]
        rank, _reps = tooltip(item_id)
        if rank is None:
            problems.append("rank reward %d has no rank line in its tooltip" % item_id)
        entry = base(item_id)
        entry["slot"] = slot
        gold = int(row["BuyPrice"])
        if slot == "MOUNT":
            faction = race_faction(row["AllowableRace_0"])
        else:
            faction = faction_for(item_id) if slot in ("TRINKET", "TABARD", "OTHER") else None
        entry.update(source="RANK", rank=rank, faction=faction, gold=gold or None)
        if slot == "TRINKET":
            rule = R.RANK_RULES["TRINKET"]
            entry.update(honor=rule["honor"], marks=dict(rule["marks"]), iec=rule["iec"])
        entries[item_id] = entry

    # ---- reputation items --------------------------------------------------------------
    rep_mismatch = []
    rep_excluded = []
    rep_ids = {}
    for item_id, row in sparse.items():
        if int(row["MinFactionID"]) in R.REP_DATA_FACTIONS:
            rep_ids[item_id] = (int(row["MinFactionID"]), int(row["MinReputation"]) + 1, "data")
    candidates = [i for i, r in sparse.items()
                  if int(r["MinFactionID"]) == 0 and int(r["MinReputation"]) > 0 and "Premier" not in r["Display_lang"]]
    candidates += [i for i in R.REP_EXTRA_IDS if i in sparse and i not in candidates]
    for item_id in sorted(candidates):
        _rank, reps = tooltip(item_id)
        found = {name for name, _s in reps}
        fids = {faction_ids.get(n) for n in found}
        standings = {s for _n, s in reps}
        if found and fids <= set(R.REP_TOOLTIP_FACTIONS) | set(R.REP_DATA_FACTIONS) and len(standings) == 1:
            if len(fids) == 1:
                rep_ids[item_id] = (next(iter(fids)), standings.pop(), "tooltip")
            else:
                rep_ids[item_id] = (None, standings.pop(), "tooltip")  # sold on both sides
                notes["rep faction nil: tooltip names several factions"].append(item_id)
            continue
        rep_excluded.append((item_id, sparse[item_id]["Display_lang"], sorted(found)))
    for item_id, (fid, standing, origin) in sorted(rep_ids.items()):
        _rank, reps = tooltip(item_id)
        if origin == "data" and fid:
            names = {n for n, _s in reps}
            if names != {faction_names[fid]} or reps[0][1] != standing:
                rep_mismatch.append((item_id, fid, standing, reps))
        gold = int(sparse[item_id]["BuyPrice"])
        entry = base(item_id)
        entry.update(source="REP", faction=R.REP_SIDE.get(fid), gold=gold or None,
                     rep={"faction": fid, "standing": standing})
        entries[item_id] = entry

    # ---- old rank items (excluded) -------------------------------------------------------
    old_rank = [i for i, r in sparse.items() if int(r["RequiredPVPRank"]) > 0]
    overlap = [i for i in old_rank if i in entries]
    if overlap:
        notes["items in both the old-rank list and the output"] = overlap

    if problems:
        sys.stderr.write("DATA DRIFT - not writing %s\n" % OUT.name)
        for line in problems:
            sys.stderr.write("  " + line + "\n")
        if args.report:
            print("IEC drift check: FAILED")
        sys.exit(1)

    # ---- write Lua -------------------------------------------------------------------------
    used_factions = {2798, 2799, 509, 510}
    used_factions |= {e["rep"]["faction"] for e in entries.values() if e.get("rep") and e["rep"]["faction"]}

    def fmt(item_id, e):
        parts = ["name = " + lua_str(e["name"]), "slot = " + lua_str(e["slot"])]
        if e.get("class"):
            parts.append("class = " + lua_str(e["class"]))
        if e.get("armor"):
            parts.append("armor = " + lua_str(e["armor"]))
        if e.get("faction"):
            parts.append("faction = " + lua_str(e["faction"]))
        parts += ["quality = %d" % e["quality"], "ilvl = %d" % e["ilvl"], "reqLevel = %d" % e["reqLevel"],
                  "source = " + lua_str(e["source"])]
        if e.get("honor"):
            parts.append("honor = %d" % e["honor"])
        if e.get("marks"):
            parts.append("marks = { %s }" % ", ".join("%s = %d" % (R.MARK_KEYS[k], v)
                                                      for k, v in sorted(e["marks"].items(), key=lambda kv: R.MARK_KEYS[kv[0]])))
        if e.get("gold"):
            parts.append("gold = %d" % e["gold"])
        if e.get("rank"):
            parts.append("rank = %d" % e["rank"])
        if e.get("rep"):
            if e["rep"]["faction"]:
                parts.append("rep = { faction = %d, standing = %d }" % (e["rep"]["faction"], e["rep"]["standing"]))
            else:
                parts.append("rep = { standing = %d }" % e["rep"]["standing"])
        if e.get("parts"):
            parts.append("parts = { %s }" % ", ".join(str(p) for p in e["parts"]))
        if e.get("iec"):
            parts.append("iec = %d" % e["iec"])
        return "    [%d] = { %s },\n" % (item_id, ", ".join(parts))

    ordered = sorted(entries.items(), key=lambda kv: (SLOT_INDEX[kv[1]["slot"]], kv[1]["source"], kv[0]))
    out = []
    out.append("-- GENERATED by tools/build_gear.py from wago.tools build %s (%s) and Wowhead Forever tooltips. Do not edit.\n"
               % (build, build_date))
    out.append("local ADDON_NAME, HonorLog = ...\n\n")
    out.append("HonorLog.GEAR_BUILD = %s\n\n" % lua_str(build))
    out.append("HonorLog.SLOTS = {\n" + "".join("    %s,\n" % lua_str(s) for s in SLOTS) + "}\n\n")
    out.append("HonorLog.CLASSES = {\n" + "".join("    %s,\n" % lua_str(classes[m]) for m in sorted(classes)) + "}\n\n")
    out.append("HonorLog.MARK_ITEMS = { AV = 20560, AB = 20559, WSG = 20558, DI = 274895 }\n\n")
    out.append("HonorLog.REP_FACTIONS = {\n" + "".join("    [%d] = %s,\n" % (f, lua_str(faction_names[f]))
                                                     for f in sorted(used_factions)) + "}\n\n")
    out.append("HonorLog.GearDB = {\n" + "".join(fmt(i, e) for i, e in ordered) + "}\n")
    OUT.write_text("".join(out))

    if args.report:
        report(entries, ordered, build, build_date, notes, unpaired, unclassified, rule_count, rule_ok,
               icon_match, icon_total, rep_mismatch, rep_excluded, old_rank, sparse, tt_rank, epic_armour)


def report(entries, ordered, build, build_date, notes, unpaired, unclassified, rule_count, rule_ok,
           icon_match, icon_total, rep_mismatch, rep_excluded, old_rank, sparse, tt_rank, epic_armour):
    print("Build %s (%s), %d items written" % (build, build_date, len(entries)))
    print("\n== Counts per slot x source x faction")
    counts = Counter((e["slot"], e["source"], e.get("faction") or "-") for e in entries.values())
    for key in sorted(counts, key=lambda k: (SLOT_INDEX[k[0]], k[1], k[2])):
        print("  %-10s %-8s %-9s %d" % (key + (counts[key],)))
    print("\n== Items with no cost found")
    nocost = [i for i, e in ordered if not (e.get("honor") or e.get("gold") or e.get("marks"))]
    print("  %d: %s" % (len(nocost), ", ".join("%d %s" % (i, entries[i]["name"]) for i in nocost[:40])))
    print("\n== Rank taken from inference rather than a tooltip")
    inferred = notes["rank inferred from the Seal (epic tooltip has no rank line)"]
    print("  %d epic armour pieces take their rank from the matching Seal (tooltip has no rank line)" % len(inferred))
    ranked_epics = [i for i in epic_armour if tt_rank.get(i)]
    print("  epic armour with a tooltip rank line: %d" % len(ranked_epics))
    print("\n== Alliance items priced by the Horde-derived rule (IEC rows have no faction link)")
    assumed = [i for i, e in entries.items() if e.get("faction") == "Alliance" and (e.get("iec") or e.get("parts"))]
    by = Counter((entries[i]["slot"], entries[i]["source"]) for i in assumed)
    print("  %d items: %s" % (len(assumed), ", ".join("%s/%s x%d" % (s, src, n) for (s, src), n in sorted(by.items()))))
    gold_alliance = [i for i, e in entries.items() if e.get("faction") == "Alliance" and e.get("gold") and not e.get("iec")]
    print("  Alliance items priced in gold from their own BuyPrice (not assumed): %d" % len(gold_alliance))
    print("\n== IEC drift check")
    print("  PASS: %d of %d rules match their ItemExtendedCost rows; Seal ranks and gold checks match" % (rule_ok, rule_count))
    print("\n== Epic pairing")
    print("  epics: %d, unpaired: %d %s" % (len(epic_armour), len(unpaired), unpaired[:10]))
    print("  paired blue and epic share an icon file: %d of %d (a sanity check, not the pairing key)" % (icon_match, icon_total))
    print("\n== Other findings")
    for key in sorted(notes):
        if key.startswith("rank inferred"):
            continue
        print("  %s: %d %s" % (key, len(notes[key]), sorted(set(map(str, notes[key])))[:12]))
    print("  Premier items not classified: %d %s" % (len(unclassified), unclassified[:10]))
    print("  reputation items whose tooltip disagrees with the client data: %d %s" % (len(rep_mismatch), rep_mismatch[:5]))
    print("  reputation candidates left out (no single PvP faction in tooltip): %d" % len(rep_excluded))
    for i, name, found in rep_excluded[:15]:
        print("      %d %s %s" % (i, name, found))
    reps = Counter(e["rep"]["faction"] or 0 for e in entries.values() if e.get("rep"))
    print("  reputation items per faction id: %s" % dict(sorted(reps.items())))
    print("  excluded old vanilla/SoD rank items (RequiredPVPRank 5-18 in client data): %d" % len(old_rank))


if __name__ == "__main__":
    main()
