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
- **Honor summary:** today, this week and this session, with a warning before you reach the cap.
  The stats frame also shows honor per hour, counted over the time you spent in battlegrounds this
  session.
- **Honor cap advice:** when the cap is close, or about 20 games away at your own honor per game,
  and nothing on your goal list can be bought yet because of level, rank or reputation, HonorLog
  says so and lists up to three items you could buy now (`/honorlog goal advice`).
- **Rank planner:** the 14 PvP ranks, this week's cap, the season end, and for any rank the
  games it takes at your pace and the earliest date the cap allows. It records why each game
  gave the rank points it did, shows your measured points per win and loss for each
  battleground, flags battlegrounds that give no rank points, and says when character level 40
  (a player-reported gate on rank 4) is what blocks the next rank.
- **Gear goals:** about 900 Forever PvP items with honor, marks, gold, rank gates and
  reputation. Epics show as blue piece plus Seal; goals get a "ready on" date.
  - **Level requirement:** a goal whose item needs a higher character level shows "Level 35 / 55"
    and reads "Ready at level 55" instead of a date.
  - **Reputation forecast:** a reputation goal shows your standing with the amounts ("Honored
    4,200 / 12,000"). Every battleground game records the reputation it gave with that
    battleground's faction, and the date comes from your average over your last 20 games. Until a
    game has measured it, the goal asks you to play one and shows no date.
  - **Battleground reputation gear:** the Arathi Basin, Alterac Valley and Warsong Gulch
    reputation items are listed with a "price unconfirmed" tag until a vendor scan has seen them.
  - **Vendors:** a goal and a picker row say who sells the item and where ("Sold by Samuel Hawke,
    Refuge Pointe, Arathi Highlands"). Alt+Click opens the map on the vendor with a pulsing pin and a distance arrow, or
    use `/honorlog vendor <item or goal number>`. Where a vendor's position is not known yet,
    opening that vendor once lets HonorLog remember it.
- **Rank planner, measured:** each game saves why it gave the rank points it did, the Rank tab
  lists your measured points per win and loss for each battleground, and games played at the
  honor cap no longer pull your honor per game down.
- **Vendor scan:** reads real vendor prices, automatically (see below).
- **Export:** every saved game, world PvP and opponents, as text or CSV (comma-separated, with
  quoting). `/honorlog export csv` opens the CSV; plain `/honorlog export` uses the Export Format
  option.
- **Session and scope:** today's stats, per-character or account-wide views, up to 500 games
  of history.
- **LDB and minimap button** for Titan Panel, ChocolateBar, Bazooka and the like.

## Slash commands

`/honorlog` or `/hl` (use `/honorlog` if another addon also claims `/hl`).

| Command | Result |
| --- | --- |
| `/honorlog` | Open or close the HonorLog window (also the minimap button, a key binding and the addon menu) |
| `/honorlog mini` | Show or hide the small tracker frame |
| `/honorlog stats [bg]` | Print a stats summary |
| `/honorlog history [n]` | Recent games |
| `/honorlog honor` | Honor today, this week and this session |
| `/honorlog cap [on\|off\|percent]` | Honor cap warning |
| `/honorlog rank [n]` | Rank summary, or the plan to rank n |
| `/honorlog goal [add\|list\|clear\|advice]` | Gear goals |
| `/honorlog vendor [item or goal number]` | Put the vendor that sells an item on the map |
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
