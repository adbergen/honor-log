# HonorLog

[![CurseForge Downloads](https://img.shields.io/curseforge/dt/1442154?style=flat&logo=curseforge&label=Downloads&color=f16436)](https://www.curseforge.com/wow/addons/honorlog)

Battleground and world PvP stats, a PvP rank planner and gear goals for **WoW Forever**
(client 1.60.1).

**Playing TBC Classic Anniversary?** Stay on HonorLog 1.2.3. Version 2.0 is built for Forever only and
is not meant for the TBC client.

## Features

### One window, five screens

Open it with `/honorlog`, the minimap button, a key binding (Key Bindings, AddOns) or the game's
addon menu.

- **Overview:** your rank and honor, today's games, honor, rank points and marks, what to do next,
  your next gear goal and your recent games.
- **Rank plan:** the season charted against the weekly rank cap, with your points and a projection
  at your pace; the 14 ranks with what each unlocks, shown as the real items; a planner to a target
  rank (points to go, games at your pace, when the cap opens it, what holds you back); your
  measured rank points per win and loss for each battleground; and the season's weekly quest.
  A battleground that gives no rank points is flagged, and so is character level 40 (a
  player-reported gate on rank 4) when it is what blocks the next rank.
- **Gear goals:** about 900 Forever PvP items with honor, marks, gold, rank gates, level and
  reputation. Your goals in order, each with what it still takes and a "ready on" date; the chosen
  goal in detail, with an epic's two purchases (blue piece plus Seal) or a blue piece's epic
  upgrade; what you can buy today and what the next ranks open. **Add a goal** opens the vendor
  browser: every PvP vendor, its stock for your class or all classes, set filters, and a star on
  each item that adds or removes the goal.
  - **Level requirement:** a goal whose item needs a higher character level reads "Ready at level
    55" instead of a date.
  - **Reputation forecast:** a reputation goal shows your standing with the amounts ("Honored
    4,200 / 12,000"). Every battleground game records the reputation it gave with that
    battleground's faction, and the date comes from your average over your last 20 games. Until a
    game has measured it, the goal asks you to play one and shows no date.
  - **Battleground reputation gear:** the Arathi Basin, Alterac Valley and Warsong Gulch
    reputation items are listed with a "price unconfirmed" tag until a vendor scan has seen them.
- **Battlegrounds:** a card for Alterac Valley, Warsong Gulch, Arathi Basin and Darkspear Islands
  with your record, your last ten results, win rate, honor a game, average length and measured rank
  points; honor for each of the last seven days; win rate by time of day; and the table of every
  recorded game, with filters for battleground, result and character or account, and export. A new
  battleground is tracked from its first game.
- **Quests:** the PvP quests the game data names for your faction, grouped as ready to hand in, in
  your log (with objectives), not picked up and done. HonorLog remembers what each quest paid
  (honor, rank points, marks, money, experience) and where you handed it in. Titles and objectives
  come from the game, so they are in your language.

### Show on map

Every vendor and every quest hand-in has a "Show on map" button, and clicking an item's icon does
the same for the vendor that sells it: the map opens on the spot with a pulsing pin, and an arrow
on screen points the way with the distance. `/honorlog vendor <item or goal number>` does it from
the chat line. The quartermasters and the Warsong Gulch, Arathi Basin and Alterac Valley supply
officers are built in; any other vendor is remembered the first time you open it.

### Pop-up cards

A **game report** after each battleground (result, honor against your average, rank points with the
reason for a zero, marks, your next goal, the honor cap), a **rank-up** card (the new rank, what it
unlocks, what comes next) and an **honor cap** card (how close the cap is and what to buy first).
Each can be switched off in the options, waits for the end of a fight and goes away by itself.
`/honorlog moment report|rank|cap` shows one now.

### Measured, not guessed

- **Per game:** honor, marks and rank points come from your own currency, bags and rank, not from
  fixed guesses. Each game is saved as a win, loss, draw or left early, with why it gave the rank
  points it did, and a game you joined in progress is flagged. Games played at the honor cap do not
  pull your honor per game down.
- **Scoreboard stats:** killing blows, honorable kills, deaths, damage, healing and objectives,
  saved once the client lets addons read the scoreboard.
- **Vendor scan:** reads real vendor prices, automatically (see below).
- **Honor cap advice:** when the cap is close, or about 20 games away at your own honor per game,
  and nothing on your goal list can be bought yet because of level, rank or reputation, HonorLog
  says so and lists up to three items you could buy now (`/honorlog goal advice`).

### Also

- **World PvP:** kills, killing blows, deaths, honor (from kills and from awards) and the
  opponents you meet most, without the combat log.
- **The small tracker frame** (`/honorlog mini`): today's stats, honor today, this week and this
  session, and honor per hour over the time you spent in battlegrounds.
- **Export:** every saved game, world PvP and opponents, as text or CSV (comma-separated, with
  quoting). `/honorlog export csv` opens the CSV; plain `/honorlog export` uses the Export Format
  option.
- **Scope:** per-character or account-wide views, up to 500 games of history.
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
| `/honorlog moment report\|rank\|cap` | Show a pop-up card now |
| `/honorlog probe [on\|off\|status\|clear\|guild\|group\|ui]` | Record what the client exposes to addons |
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
