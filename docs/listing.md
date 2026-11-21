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

Still wanted, taken on WoW Forever: the Overview, the Rank plan, Gear goals with a goal chosen,
the vendor browser ("Add a goal"), Battlegrounds, Quests, a game report card, and the world map
with HonorLog's pin and arrow on a vendor.

## Description

Paste everything below the line.

---

**Your PvP climb on WoW Forever: ranks, honor and gear, in one window.**

HonorLog is built for **WoW Forever**. It records every battleground and world PvP fight,
works out how long the next rank and the next piece of gear will take, and measures its
numbers from your own character instead of guessing them.

> **Playing TBC Classic Anniversary?** Stay on HonorLog **1.2.3**. Version 2.0 is for
> WoW Forever only.

### One window, five screens

- **Overview.** Your rank and honor, today's games, what to do next, your next gear goal
  and your recent games.
- **Rank plan.** Your season charted against the weekly rank cap, all 14 ranks with what
  each one unlocks (shown as the real items, with their tooltips), and a planner to any
  rank: the points to go, the games it takes at your own pace and the earliest date the
  cap allows.
- **Gear goals.** About 900 Forever PvP items: Premier blue and epic sets, Seals, rank 14
  weapons and battleground reputation gear. Each goal shows what it still takes (honor,
  marks, gold, rank, level, reputation) and a "ready on" date; epics are priced as the
  blue piece plus its Seal. "Add a goal" opens every PvP vendor's stock, and one click on
  a star adds the item.
- **Battlegrounds.** A card for Alterac Valley, Warsong Gulch, Arathi Basin and Darkspear
  Islands with your record, your last ten results, win rate, honor a game and measured
  rank points. Honor for each of the last seven days, your win rate by time of day, and
  every recorded game in a table you can filter and export.
- **Quests.** The PvP quests for your faction: ready to hand in, in your log, not picked
  up and done. HonorLog remembers what each quest paid you and where you handed it in.

### It shows you the way

- **Vendor locations.** A goal says who sells the item and where, and "Show on map"
  opens your map on the vendor with a pin while an arrow on your screen points the way
  with the distance.
- **Quest hand-ins.** The same button takes you back to where you handed a quest in.

### Cards at the moments that matter

- **Game report** after each battleground: the result, honor against your average there,
  rank points with the reason when a game gave none, marks, and how close your next goal
  and the honor cap are.
- **Rank up:** the new rank, what it unlocks, and what the next rank takes.
- **Honor cap:** how close the cap is and what you can buy before honor is wasted.

Each card can be switched off, never appears during a fight and goes away by itself.

### Numbers you can trust

- **Measured, per game.** Honor, marks and rank points are read from your own currencies,
  bags and rank after every battleground, and each game saves why it gave the rank
  points it did.
- **Real vendor prices.** Open a PvP vendor and HonorLog reads what it charges, so your
  goals follow price changes. One chat line, once per vendor every 10 minutes; you can
  switch it off in the options.
- **Reputation forecast.** Reputation goals show your standing with amounts and a date
  based on the reputation your own recent games gave. Until a game has measured it, no
  date is shown.
- **Honor cap advice.** If the cap is near and nothing on your list can be bought yet,
  HonorLog says why and lists what you could buy now.

### Also

- **World PvP without the combat log:** kills, killing blows, deaths, honor, and the
  opponents you meet most.
- **A small tracker frame** for inside a battleground, next to the full window: honor
  today, this week and this session, and honor per hour in battlegrounds.
- **Export** every saved game, your world PvP and opponents as text or comma-separated
  CSV.
- **Data Broker and minimap button** for Titan Panel, ChocolateBar and Bazooka. The
  window also opens from a key binding and the game's addon menu.

### Game versions

WoW Forever (client 1.60.1) only.

### Commands

| Command | Result |
| --- | --- |
| `/honorlog` | Open or close the HonorLog window |
| `/honorlog mini` | Show or hide the small tracker frame |
| `/honorlog rank [n]` | Rank summary, or the plan to rank n |
| `/honorlog goal [add\|list\|clear\|advice]` | Gear goals from the chat line |
| `/honorlog vendor [item or goal number]` | Show the vendor that sells an item on the map (`clear` removes the pins) |
| `/honorlog export` | Export games as text or CSV |
| `/honorlog moment report\|rank\|cap` | Show a pop-up card now |
| `/honorlog config` | Open settings |
| `/honorlog help` | List commands |

`/hl` works too, unless another addon has taken it.

### Bugs and ideas

[GitHub issues](https://github.com/adbergen/honor-log/issues)
