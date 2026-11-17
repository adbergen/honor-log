# HonorLog

[![CurseForge Downloads](https://img.shields.io/curseforge/dt/1442154?style=flat&logo=curseforge&label=Downloads&color=f16436)](https://www.curseforge.com/wow/addons/honorlog)

Battleground and world PvP stats, a PvP rank planner and gear goals for **WoW Forever**
(client 1.60.1).

**Playing TBC Classic Anniversary?** Stay on HonorLog 1.2.3. Version 2.0 is built for Forever only and
is not meant for the TBC client.

## Features

- **Battlegrounds:** Alterac Valley, Warsong Gulch, Arathi Basin and Darkspear Islands. A new
  battleground is tracked from its first game.
- **Measured per game:** honor, marks and rank points come from your own currency, bags and
  rank, not from fixed guesses. Each game is saved as a win, loss, draw or left early, and a
  game you joined in progress is flagged.
- **Scoreboard stats:** killing blows, honorable kills, deaths, damage, healing and
  objectives, saved once the client lets addons read the scoreboard.
- **World PvP:** kills, killing blows, deaths, honor (from kills and from awards) and the
  opponents you meet most, without the combat log.
- **Honor summary:** today, this week and this session, with a warning before the 25,000 cap.
- **Rank planner:** the 14 PvP ranks, this week's cap, the season end, and for any rank the
  games it takes at your pace and the earliest date the cap allows.
- **Gear goals:** about 900 Forever PvP items with honor, marks, gold, rank gates and
  reputation. Epics show as blue piece plus Seal; goals get a "ready on" date.
- **Vendor scan:** reads real vendor prices, automatically (see below).
- **Export:** every saved game, world PvP and opponents, as text or CSV.
- **Session and scope:** today's stats, per-character or account-wide views, up to 500 games
  of history.
- **LDB and minimap button** for Titan Panel, ChocolateBar, Bazooka and the like.

## Slash commands

`/honorlog` or `/hl` (use `/honorlog` if another addon also claims `/hl`).

| Command | Result |
| --- | --- |
| `/honorlog` | Show or hide the stats frame |
| `/honorlog stats [bg]` | Print a stats summary |
| `/honorlog history [n]` | Recent games |
| `/honorlog honor` | Honor today, this week and this session |
| `/honorlog cap [on\|off\|percent]` | Honor cap warning |
| `/honorlog rank [n]` | Rank summary, or the plan to rank n |
| `/honorlog goal [add\|list\|clear]` | Gear goals |
| `/honorlog export [text\|csv]` | Open the export window |
| `/honorlog view [character\|account]` | Switch scope |
| `/honorlog reset [today\|character\|account]` | Reset stats |
| `/honorlog scan [export\|clear\|status]` | Vendor scan tools |
| `/honorlog probe [on\|off\|status\|clear]` | Record what PvP data the client exposes |
| `/honorlog config` | Options |
| `/honorlog status`, `debug`, `test` | Tracking state, debug prints, fake game |
| `/honorlog help` | List commands |

## Vendor prices

Costs in the gear database come from game data and can lag a hotfix. When you open a PvP
vendor that sells any item HonorLog knows, it reads what the vendor charges, stores it in
`HonorLogDB.scannedGear` (these prices override the built-in ones) and prints
"HonorLog: updated prices for N PvP items from <vendor>". The same vendor is not scanned
again for 10 minutes. Switch it off under Options, "Scan PvP Vendors". You can still run
`/honorlog scan` by hand, and `/honorlog scan export` lists where the vendor and the built-in
data disagree.

## How the gear data is generated

`Data/GearDatabase.lua` is generated, never edited by hand:

```
python3 tools/build_gear.py            # write the file
python3 tools/build_gear.py --report   # also print coverage and checks
python3 tools/build_gear.py --refresh  # redownload the sources first
```

It joins wago.tools DB2 tables for the live Forever build (items, extended costs, item sets)
with Wowhead Forever tooltips for rank and reputation requirements. The rules in
`tools/gear_rules.py` (verified cost rows, Seal ranks) are checked on every run, and the
script stops if a price changed. Details are in `tools/README.md`.

## Development

```
lua Tests/run.lua    # headless load test under a Forever-shaped mock
luacheck .           # lint, config in .luacheckrc
```

Tests and tools are not part of the release zip.

## Install

Download from CurseForge and extract to
`World of Warcraft/_forever_/Interface/AddOns/HonorLog`, then `/reload` or restart the game.

## Feedback

[GitHub issues](https://github.com/adbergen/honor-log/issues)
