# Store listing

The text of HonorLog's CurseForge and Wago Addons pages. Neither site reads it from
here, so after a change, paste each field into the site by hand:

- **CurseForge:** project page → Settings. "Project name" and "Summary" are on the
  General tab, "Description" on the Description tab (choose the Markdown editor),
  and screenshots under Images.
- **Wago Addons:** project page → Edit. Same fields.

Screenshots in this folder are excluded from the release zip.

## Project name

```
HonorLog - PvP Rank, Honor & Gear Goals
```

The name is what search matches first, so it carries the words players type: PvP,
rank, honor, gear.

## Summary

```
PvP tracker for WoW Forever: rank planner, measured honor, marks and rank points per battleground game, and gear goals with rank gates.
```

## Categories

Battlegrounds / PvP (main), Combat.

## Screenshots

Still wanted, taken on WoW Forever: the stats frame after a battleground, the Rank tab,
and the Goals tab with an epic goal.

## Description

Paste everything below the line.

---

**Your PvP climb on WoW Forever: ranks, honor and gear, tracked for you.**

HonorLog is built for **WoW Forever**. It watches your battlegrounds and world PvP,
works out how long the next rank and the next piece of gear will take, and keeps the
numbers honest by measuring them instead of guessing.

> **Playing TBC Classic Anniversary?** Stay on HonorLog **1.2.3**. Version 2.0 is for
> WoW Forever only.

### Features

- **Rank planner.** See your rank, this week's cap and the season countdown. Pick any
  rank and HonorLog tells you the games it takes at your own pace and the earliest date
  the weekly cap allows.
- **Measured honor, marks and rank points, per game.** Read from your own currencies,
  bags and rank after every battleground, so the totals match what you really earned.
- **Gear goals that say what is missing.** About 900 Forever PvP items: Premier blue and
  epic sets, Seals, rank 14 weapons and battleground reputation gear. Each shows honor,
  marks, gold, the rank and character level it needs and a "ready on" date. Epics are
  priced as the blue piece plus its Seal.
- **Reputation forecast.** Reputation goals show your standing with amounts and a date
  based on the reputation your own recent games gave. Until a game has measured it, no
  date is shown.
- **Vendor locations.** A goal says who sells the item and where, and Alt+Click opens
  your map on the vendor with a pin, and an arrow shows the way.
- **Honor cap advice.** If the cap is near and nothing on your list can be bought yet,
  HonorLog says why and lists what you could buy now.
- **Every battleground:** Alterac Valley, Warsong Gulch, Arathi Basin and Darkspear
  Islands. Wins, losses, draws and games you left, with kills, deaths, damage, healing
  and objectives from the scoreboard.
- **World PvP without the combat log:** kills, killing blows, deaths, honor, and the
  opponents you meet most.
- **Honor today, this week and this session,** honor per hour in battlegrounds, and a
  warning before you reach the cap.
- **Rank points that make sense.** Each game saves why it gave the rank points it did,
  and the Rank tab shows your measured points per win and loss for each battleground.
- **Real vendor prices.** Open a PvP vendor and HonorLog reads what it charges, so your
  goals follow price changes. One chat line, once per vendor every 10 minutes; you can
  switch it off in the options.
- **Export** every saved game, your world PvP and opponents as text or comma-separated
  CSV.
- **Data Broker and minimap button** for Titan Panel, ChocolateBar and Bazooka.

### Game versions

WoW Forever (client 1.60.1) only.

### Commands

| Command | Result |
| --- | --- |
| `/honorlog` | Show or hide the stats frame |
| `/honorlog rank [n]` | Rank summary, or the plan to rank n |
| `/honorlog goal` | Open the gear goals |
| `/honorlog vendor [item or goal number]` | Show the vendor that sells an item on the map (`clear` removes the pins) |
| `/honorlog export` | Export games as text or CSV |
| `/honorlog config` | Open settings |
| `/honorlog help` | List commands |

`/hl` works too, unless another addon has taken it.

### Bugs and ideas

[GitHub issues](https://github.com/adbergen/honor-log/issues)
