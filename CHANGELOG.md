# Changelog

## [2.1.0] - Unreleased

### Added
- **A summary of each of your characters**, kept in the account's saved data: class, faction, level, rank and
  rank points, whether the weekly rank cap is reached and until when, honor, marks, how far the first gear
  goal is, games and wins. Each character writes its own on entering the world, after each game, on a
  rank-up and at logout. Nothing shows it yet; a later screen lists them side by side.
- **A record per reset week**, kept for 26 weeks: games and results, honor, marks, rank points gained, the
  best game and world kills and deaths. The first time it runs it also builds the earlier weeks from the games
  you have saved. Nothing shows it yet; a later screen turns it into a weekly recap.

### Changed
- The saved data moves to version 3. The change only adds data, so going back to 2.0 keeps working and loses
  only the new summaries and weeks.

## [2.0.0] - Unreleased

HonorLog 2.0 is built for **WoW Forever** (client 1.60.1). TBC Anniversary stays on
1.2.3: if you play TBC, keep that version.

### Added
- **Quests**, the window's fifth screen. The PvP quests the game data names (208 of them, by battleground and
  faction): which are ready to hand in, in your log (with their objectives), not picked up or done, what each paid
  you (honor, rank points, marks, money, experience) and where to hand it in, with a button that shows the place
  on the map. HonorLog now remembers what a quest paid and where it was handed in, always, with no command; titles
  and objectives come from the game, so they are in your language. The Rank plan's weekly quest uses what it
  measured.
- **Pop-up cards** for the moments that matter, in place of the plain centre-screen text: a game report after
  each battleground (the result, honor, rank points, marks, reputation or killing blows, a highlight, your
  next goal and how close the honor cap is), a rank-up card (the new rank, what it unlocks, what comes next)
  and an honor cap card (how close the cap is and what to buy before honor is wasted, with the way to the
  vendor). Each can be switched off in the options, none appears during a fight, and each goes away by itself
  after 12 seconds (held while the mouse is over it). `/honorlog moment report|rank|cap` shows one now. The
  chat lines stay.
- **Battlegrounds**, the window's fourth screen. A card per battleground with your record, your last ten
  results and what a game there is worth (win rate, honor a game, average length, rank points); the honor
  of each of the last seven days; your win rate by time of day; and the table of every recorded game with
  filters for battleground, result and character or account, and an Export button. Click a card to show
  only that battleground's games. The Overview's Recent games has an "All games" button that opens it.
- **The Horde quartermasters are on the map from the start.** The four PvP quartermasters in Orgrimmar's
  Hall of Legends now have their positions built in, so "Show on map" pins them before you have ever opened
  one. (Alliance already had theirs.)
- **Gear goals**, the window's third screen. Your goals in order, each with what it still takes and when it
  will be ready; the chosen goal in detail (what it takes, the two purchases of an epic or the epic upgrade of
  a blue piece, who sells it and a button to show the vendor on the map, and why the date is what it is);
  what you can buy today and what the next ranks open; and a vendor browser ("Add a goal") that lists every
  PvP vendor and its stock, so a goal is added with one click on a star. Items show their real icon and the
  game's tooltip; Ctrl-click an icon to preview the item.
- **Rank plan**, the window's second screen: the season charted against the weekly rank cap (your points,
  and a projection at your pace), the fourteen ranks with what each unlocks, a planner to a target rank
  that says what holds you back, and the rank points each battleground gave, with the season's weekly quest.
- **The HonorLog window**, with its first screen, the Overview: rank ring and honor on the left; today's
  games, honor, rank points and marks; what to do next; your next goal; and your recent games. It opens
  with `/honorlog`, the minimap button, a key binding (Key Bindings, AddOns) or the addon menu. The
  small frame stays as the in-battleground tracker (`/honorlog mini`).
- **Data layer for the new window** (nothing visible yet): today's numbers, advice, the season's
  week-by-week cap schedule, a table of the 14 ranks with what each unlocks, why each game paid what it
  did, vendor lists with each vendor's stock and sets, per-battleground summaries, honor by day, win rate
  by time of day, and events other addons can listen to (`HonorLog_GameRecorded`, `HonorLog_RankUp`,
  `HonorLog_WeekCapReached`, `HonorLog_HonorCapNear`, `HonorLog_GoalAcquired`). Arathi Basin and Warsong
  Gulch now use one colour everywhere.
- **Forever battlegrounds:** Alterac Valley, Warsong Gulch, Arathi Basin and the new
  Darkspear Islands, with their own colours and mark icons. A battleground Forever
  adds later is tracked from its first game.
- **Measured, not assumed.** Honor, marks and rank points for each game are read from
  your own currencies, bags and rank, so they match what you really got. Results are
  win, loss, draw or left early, and a game you joined in progress is flagged.
- **Scoreboard stats:** killing blows, honorable kills, deaths, damage, healing and the
  objectives (flags, bases and so on) are saved with each game once the client
  reveals the scoreboard.
- **World PvP without the combat log:** kills, killing blows, deaths and honor outside
  battlegrounds, split into honor from kills and honor from awards, plus a list of the
  opponents you meet most.
- **Rank planner:** Forever's 14 PvP ranks with the points into your rank, this week's
  cap, the season countdown and the next reward. Pick a rank and it tells you the games
  needed at your own pace and the earliest date the weekly cap allows it. The main
  panel has a rank bar and a Rank tab, with a rank-up celebration and a weekly-cap alert.
- **Rank planner says why.** Each game saves why it gave the rank points it did: earned,
  zero, week's cap already reached, the level gate, or no rank data. Your pace is
  averaged from the earned and zero games only, so games played at the cap no longer pull
  it down. The Rank tab lists your measured points per win and per loss for each
  battleground.
- **No more "~0 games".** If at least 5 measured games gave 0 rank points, the plan, the
  tooltip, `/honorlog rank` and the goals say so in a sentence instead of printing a date
  for today.
- **Battlegrounds that give no rank points.** When a battleground's last 3 or more
  counted games all gave 0 (Alterac Valley, per player reports), the Rank tab and the
  end-of-game chat line say so, with your average in the other battlegrounds. The chat
  line shows once per battleground each login.
- **Level gate on rank 4.** Players report that rank 4 needs character level 40; Blizzard
  hasn't confirmed it. Below level 40 at rank 3, the rank bar, Rank tab, tooltip and
  `/honorlog rank` say so, and plans for rank 4 and above read "after level 40". If a
  character holds rank 4 or higher under level 40, HonorLog drops the gate for that
  character. The probe records the observation when it is armed.
- **Honor summary** for today, this week and this session, with a warning before you hit
  the 25,000 honor cap.
- **Gear goals rebuilt for Forever:** about 900 items (Premier blue and epic sets, Seals,
  rank 14 weapons, rank rewards and battleground reputation gear) with honor, marks, gold,
  rank gates and reputation requirements. Epic upgrades are shown as the blue piece plus
  its Seal. The picker filters by your faction and class, and every goal gets a
  "ready on" date.
- **Automatic vendor price scan.** Open a PvP vendor and HonorLog reads what it really
  charges, so goals follow price changes. It prints one line, "updated prices for N PvP
  items", and checks the same vendor at most once every 10 minutes. Turn it off under
  Options, "Scan PvP Vendors".
- **Fuller export:** text and CSV now hold every saved game (date, battleground, result,
  joined in progress, duration, kills, honorable kills, deaths, damage, healing,
  objectives, honor, marks, rank points), a world PvP section and your opponents.
- **Gear goals tell the truth.**
  - A goal shows the character level its item needs: "Level 35 / 55" in the requirement
    line, and "Ready at level 55" instead of a date while you are under it.
  - Reputation goals show amounts ("Honored 4,200 / 12,000"). Each battleground game now
    saves the reputation it gave with its own faction, and the date comes from your
    average over your last 20 games. Without a measured rate there is no date, and the
    goal asks you to play a game of that battleground.
  - The Arathi Basin, Alterac Valley and Warsong Gulch reputation items are listed by
    default, tagged "price unconfirmed" until a vendor scan has seen them.
  - Goals and picker rows say who sells the item and where. Alt+Click, or
    `/honorlog vendor <item or goal number>`, opens the map on the vendor's zone, marks the
    exact spot with HonorLog's own pulsing pin and shows a small arrow with the vendor's name
    and the distance in yards. The pin and arrow clear themselves when you open that vendor;
    right-click removes them, and `/honorlog vendor clear` removes all of them. During combat the
    pin is kept and the map jumps to it the next time you open it. A vendor scan now also
    records the vendor's NPC id, map and position.
  - When the honor cap is near (or 20 games away) and nothing on your list can be bought
    because of level, rank or reputation, the advice says so and `/honorlog goal advice`
    lists up to three items you could buy now.
- `/honorlog probe`, a diagnostic that records which PvP data the client gives addons.
  While it is on it also notes what each quest offers and what a hand-in really changed
  (honor, rank points, marks, money), so the rewards of PvP quests can be learned in game.
  `/honorlog probe guild` and `/honorlog probe group` send one hidden test message and report
  whether the game lets copies of HonorLog share data there; nothing is sent without the command.
  `/honorlog probe ui` records which of Blizzard's templates, art and helper functions the
  client has.
  It also logs whether a vendor's NPC id and position can be read, and the reputation
  change after each game.

### Changed
- The theme drops the arena and Eye of the Storm leftovers, and Darkspear Islands uses its
  own mark icon.
- Your TBC history is kept and labelled "(TBC)"; old goals for TBC items are archived once.
- Opponent "last seen" times are saved as whole seconds.

### Fixed
- Games played at the honor cap gave 0 honor and pulled the honor averages down. They are
  now flagged and left out of the honor per game figures.
- A rank pace of 0 points per game was shown as "~0 games" and today's date.
- `/honorlog goal list` raised an error.
- The history limit stopped at 100 although the slider offers 500.
- Debug messages appeared on every right-click.
- The bundled Data Broker library could replace the real one for other addons.
- The export window opened empty, `/honorlog export csv` showed plain text under a CSV
  label, and the Export Format option was never read. CSV is now real comma-separated
  values with quoting.
- The two export format dropdowns shared one frame name.
- The gear picker's slot, source, class and armor filters did nothing, and "Any class"
  did not clear the class filter.
- Dragging the frame by its header ignored "Lock Frame Position".
- The rank goals' status said "not reachable this season" when the real reason was the
  level gate or a rank pace of 0 points.
- The release zip no longer ships `.luacheckrc`, and the release notes are only the
  newest version's changelog section.

## [1.2.3] - 2025-02-05

### Changed
- **World PvP min view**: Now shows honor alongside K/D (e.g., "World PvP 0-1 0 Honor")
- **Consistent K/D formatting**: Neutral gray dash between colored kill/death numbers

## [1.2.2] - 2025-02-03

### Changed
- **UI color scheme refresh**: Unified dark neutral theme replacing blue accents
- **Tighter currency spacing**: Reduced spacing around separators in totals display

### Fixed
- **Debug messages removed**: Cleaned up chat spam from debug prints running outside debug mode

## [1.2.1] - 2025-02-03

### Added
- **Total games estimate**: See how many games remain to complete all your goals
  - Header summary shows games after the percentage (e.g., "2/14 goals · 45% · 32 games")
  - Hover over the Totals bar for a detailed tooltip with the estimate
  - Based on your average honor and marks per game

### Changed
- **Cumulative goal progress**: Total bar now tracks overall journey progress including completed goals
  - Completed items count as 100% done toward the total
  - Progress percentage never decreases when completing goals
  - Honor/currency display matches the cumulative percentage
- **Compact header format**: Changed from verbose "2 goals · 88% · 14 acquired" to cleaner "14/16 goals · 88%"

### Fixed
- **World PvP stats display**: Status line now always shows K/D ratio even when 0-0

## [1.2.0] - 2025-02-01

### Added
- **TBC Level 70 Honor Gear**: Complete database of TBC launch PvP gear
  - Grand Marshal's (Alliance) and High Warlord's (Horde) rare (blue) armor sets for all classes
  - All spec variants included (Feral, Balance, Resto for Druids; Enhancement, Elemental, Resto for Shaman; etc.)
  - Level 70 PvP weapons: daggers, swords, axes, maces, fist weapons, polearms, staves, crossbows, shields, off-hands
  - **Veteran's off-pieces**: bracers, belts, boots for all armor types (cloth, leather, mail, plate)
  - **Accessories**: neck pieces (Pendants), rings (Bands), and PvP trinkets (Medallion of Alliance/Horde)
  - Accurate honor and mark costs for all items
  - All item data with verified slot assignments
- **Eye of the Storm support**: EotS stat card and tracking now enabled for TBC launch
- **Stormpike Guard items**: Added missing Alliance AV reputation vendor gear (tabard, cloaks, pendants, girdles)
- **Cross-faction class rank armor**: Added TBC prepatch items for Blood Elf Paladins and Draenei Shamans
  - Alliance: Lieutenant Commander's Earthshaker (Shaman Mail set)
  - Horde: Champion's Redoubt (Paladin Lamellar set)

### Fixed
- **World PvP honor tracking**: Now only counts honorable kills (ignores quest reward honor)
- **Defiler's Lamellar items**: Fixed swapped item IDs for Girdle (20177-20180) and Greaves (20181-20184)

## [1.1.26] - 2025-02-01

### Added
- **Gear browser preview**: Ctrl+Click items in the gear selection screen to preview in dressing room (same as goal cards)

## [1.1.25] - 2025-02-01

### Added
- **Gear preview**: Ctrl+Click any goal card to open dressing room and see how gear looks on your character
- **Preview cursor**: Magnifying glass cursor appears when holding Ctrl over goal cards (native WoW behavior)
- **Smart positioning**: Dressing room opens to the side of HonorLog instead of overlapping

## [1.1.24] - 2025-01-31

### Added
- **Configurable stat cards**: Options to show/hide individual BG cards (AV, AB, WSG, EotS) and World PvP card

### Changed
- **History limit increased**: Default history storage increased from 50 to 200 games (configurable up to 500 in options)
- **Options panel redesigned**: Two-column scrollable layout with grouped sections (Display, Frame, Visible Cards, Features, Data)

### Fixed
- **Honor/hour now calculates correctly**: Hourly rate now based on cumulative BG play time instead of time since first BG entry.
- **BG honor no longer counts as World PvP after /reload**: Honor earned in BGs now correctly attributed even when `isInBG` state is stale (uses `GetInstanceInfo()` fallback)
- **Goals totals bar styling**: Add button now matches totals bar colors for unified appearance
- **Goals totals bar spacing**: Added 4px gap between totals bar and add button
- **Today panel World PvP always visible**: World PvP stats now always shown in Today panel (displays `0-0 ⚔` when no activity)
- **World PvP stats now reset with character/account reset**: Reset Stats menu and `/hl reset` commands now properly clear World PvP kills/deaths/honor
- **World card now included in tab switch animation**: World PvP card fades in with other cards when switching to Stats tab
- **Add goal button now included in tab switch animation**: Add button fades in with totals bar when switching to Goals tab
- **Improved empty state placeholders**: Cards without data now show `0-0`, `0%`, `0.0 K/D` instead of `--` for clearer context
- **Live hourly rate during BGs**: Honor/hour updates in real-time (every second) while in a battleground, including current match duration
- **Reduced header redundancy in expanded view**: Session stats hidden from header when expanded (visible in Today panel instead)

## [1.1.23] - 2025-01-30

### Changed
- **Today panel now fixed at bottom**: BG and World cards scroll while Today section stays visible (like totals bar in goals)
- World PvP stats always shown in Today panel (defaults to `0-0 ⚔` when no activity)
- Today panel honor text now gold colored for consistency
- Today panel uses dot separator between honor and marks (matches goals totals style)
- World card honor text uses muted color to match BG card styling

## [1.1.22] - 2025-01-30

### Added
- **World PvP Tracking**: Complete open world PvP statistics tracking
  - Dedicated "World" card in stats panel (same style as BG cards)
  - Tracks world kills (enemy players killed in open world)
  - Tracks world deaths (killed by enemy players)
  - **Tracks world honor earned** from honorable kills outside BGs
  - Shows kills/deaths, K/D ratio, honor earned, and today's stats
  - Session stats (today) and lifetime stats per character/account
  - World PvP displays in Today panel with honor earned: `2-0 (+150) ⚔`
  - Shows in `/honorlog stats` command output
  - Shows in minimap/LDB tooltip
  - Test commands: `/hl test kill` and `/hl test death`

## [1.1.21] - 2025-01-30

### Added
- **Smart Compact View Status**: Minimized header now shows contextual goal status
  - "X goals ready!" (green) when all active goals are at 100%
  - "X goals · Y%" when in progress
  - "Item Name ready!" for single goal at 100%
  - Acquired count suffix: "2 goals ready! · 3 acquired"
  - "X goals acquired!" + "All complete!" when all goals are done
- **Completed Section Auto-Expand**: When no active goals remain, completed section automatically expands to show acquired items
- **Marks Icons Throughout UI**: All mark displays now use BG-specific mark icons
  - Session panel: `+3,500 Honor  40[AV] 9[AB] 3[WSG]` instead of `+6 Marks`
  - Goal cards: Currency requirements show icons instead of text abbreviations
  - Totals bar: Mark progress uses icons for each BG type
  - Goal picker: Item costs display marks with icons
- **Completed Goals Section**: Track acquired gear separately from active goals
  - **Auto-detection**: Goals automatically complete when item is bought/equipped
  - Scans bags and equipment on BAG_UPDATE event with debouncing
  - Manual fallback: Click checkmark button on any goal to mark as acquired
  - Also scans on login (2s delay) to catch items already owned
  - Collapsible "Completed (X)" section appears below active goals
  - Compact, muted cards (22px) with checkmark icon and desaturated item icons
  - Plus/minus toggle using Blizzard's native texture for reliable rendering
  - X button restores items back to active goals (for accidental completions)
- **Ready Indicator**: 100% complete goals have subtle green background tint
- **Session Panel Tooltip**: Hover explains W-L, win rate, and hourly rate calculations
- **UI Tooltips**: Helpful tooltips throughout the interface
  - Stats/Goals tabs explain their purpose
  - Remove button (X) now says "Remove Goal"
  - Completed items show full item info on hover
- **Goal Completion Celebration**: Multi-layer notification when gear is acquired
  - Quest complete sound effect for audio feedback
  - Center-screen alert (raid warning style)
  - Green message in error frame (top of screen)
  - Chat log message for history

### Fixed
- **X Button Bug**: Removing a goal no longer opens the goal picker window
- **Games Remaining Estimate**: Fixed nil safety in average calculations; added fallback estimates when no BG data exists yet (250 honor/game, 1.5 marks/game)
- **Bag Scanning API**: Fixed TBC Classic compatibility for auto-detection; proper fallback from C_Container to legacy API
- **Compact View Data Sync**: Fixed orphan goal items causing mismatch between compact header and goals panel (now uses same filtered goal list)
- **Completed Section Visibility**: Panel no longer shows empty state when all goals are completed
- **Totals Bar Currency Labels**: Changed "H" to gold "Honor" and "A" to purple "Arena" for consistency with goal cards

### Changed
- **Currency Spacing**: Added visual separation between numbers and mark icons
- **Code Architecture Refactoring**: Improved code organization and maintainability
  - Moved `BG_ICONS` to shared `UI/Theme.lua` for consistency across panels
  - Extracted animation system to `UI/Animation.lua` (~100 LOC)
  - Added `ANIM` timing constants (no more magic numbers)
  - Encapsulated drag state into `dragState` object
  - Encapsulated animation flags into `animState` object
  - Improved card pooling with `ReleaseCard()` and `ClearCardPool()` helpers
  - Added high-water mark tracking for card pool debugging

## [1.1.20] - 2025-01-29

### Added
- **Tab Switch Animations**: Sequential fade-in when switching tabs
  - Goal cards cascade in one-by-one (80ms stagger) when opening Goals tab
  - Stats cards cascade in one-by-one when opening Stats tab
  - Totals bar and session panel fade in after cards complete
- **Progress Bar Counting**: Numbers animate dynamically as bars fill
  - Percentage counts up smoothly (e.g., 0% → 75%)
  - Currency values count up (Honor, Arena, Marks)
  - Color transitions from red → yellow → green during animation
- **Totals Bar Live Animation**: Bottom summary bar animates on currency gain
  - Honor/marks count up from previous to new value in real-time
  - Triggers when gaining honor in battlegrounds

### Changed
- **Smooth Drag & Drop**: Enterprise-quality drag animations for goal cards
  - Lift effect on pickup (scale up + fade in)
  - Position animation on drop (card glides to target slot)
  - Scale settle and fade out for polished finish
  - Cards slide smoothly to create gap during drag (0.25s eased)
- **Smarter Progress Animation**: Only affected cards animate after reorder
  - Cards outside the reorder range don't re-animate
  - Prevents unnecessary visual noise
- **Animation Timing**: Slowed animations for better visual feedback
  - Card progress bars: 0.8s duration
  - Totals bar: 1.0s duration

## [1.1.19] - 2025-01-29

### Fixed
- **Add Goal Button Missing**: Fixed "+" button not visible when no goals are set
  - Button now always shows so users can add their first goal
- **Goal Card Progress After Reorder**: Fixed progress bars showing 0% after drag reorder
  - Progress bar now uses weighted average instead of minimum (consistent with totals bar)
  - Example: 1000/1000 Honor + 0/3 WSG now shows ~77% instead of 0%
  - Deferred width calculation for frames not yet laid out

## [1.1.18] - 2025-01-28

### Added
- **Resizable Goal Picker**: Goal picker window can now be resized
  - Drag bottom-right corner to resize (320x300 min, 600x700 max)
  - Item list and rows adapt to new width
- **Animated Progress Bars**: Progress bar fills now animate smoothly when values change
  - Smooth width transitions with easing (0.4s duration for cards, 0.5s for totals)
  - Gradient color interpolation: red → yellow → green based on percentage
- **Enhanced Drag & Drop**: Goal card dragging now has polished visual feedback
  - Lift animation when picking up a card (scale + shadow effects)
  - Drop animation when releasing (smooth fade/scale out)
  - Shadow and glow effects on the drag preview
- **Totals Bar Improvements**: Visual enhancements to the goals summary bar
  - Inner glow effect on the progress fill
  - Animated spark at the end of the progress bar
  - Gradient color updates to match fill percentage

### Changed
- **Drag Handle Icon**: Changed from hamburger menu (☰) to 6-dot grip pattern (⠿)
  - Hamburger icons are for menus/drawers, grip dots are the standard drag affordance
- **Hide Eye of the Storm**: EotS hidden from UI until TBC releases
  - Reduces confusion since EotS isn't available during prepatch
  - Will be re-enabled when TBC content unlocks
- **Add Goal Button**: Moved to footer next to totals bar
  - Small "+" button always visible without scrolling
  - Tooltip shows "Add Goal" on hover

### Fixed
- **Goal Cards Invisible**: Fixed goal cards not appearing when switching to Goals tab
  - Removed tab fade transitions that were causing alpha issues in TBC Classic
  - Tab switching now uses direct show/hide for reliable visibility
- **Drag & Drop Reorder**: Fixed cards overlapping when dragging past multiple cards
  - Cards now move instantly instead of animating to avoid timing conflicts
  - Drop position uses midpoint targeting for more responsive feel
  - Fixed drag handle click area not covering full card height
  - Reset card positions before reordering to prevent overlap
- **Click Targeting**: Fixed clicking near drag handle picking up wrong card
  - Drag handle extended to icon edge (24px) to prevent click-through gap
  - Cards now have explicit frame levels so higher cards take click priority
- **Progress Bar After Reorder**: Fixed progress bars showing wrong percentage after drag/drop
  - Detects when card displays different item and skips animation
  - Prevents stale visual state from previous goal
- **Compact View Percentage**: Fixed minimized goals showing 0% when totals bar showed actual progress
  - Now uses same weighted currency calculation as totals bar

## [1.1.17] - 2025-01-28

### Changed
- **Version Tooltip**: Version badge moved from header to hover tooltip on the title bar
  - Hover over the header to see version and author info
  - Cleaner header layout with less visual clutter
- **Author**: Set addon author to adbergen

## [1.1.16] - 2025-01-28

### Fixed
- **Hourly Rate Accuracy**: Session timer now starts when first BG is entered, not at login
  - Previously, idle time (questing, AFK, etc.) diluted the honor/hr calculation
  - Now only counts time from first BG entry, giving accurate BG-focused rates

### Changed
- **Renamed "Session" to "Today"**: All UI labels, buttons, tooltips, and chat output now say "Today" instead of "Session" to better reflect the daily reset behavior
  - `/honorlog reset today` replaces `/honorlog reset session` (both still work)

## [1.1.15] - 2025-01-28

### Added
- **Alliance WSG/AB Reputation Gear**: ~120 items from Silverwing Sentinels and League of Arathor
  - WSG: Protector's Band, Lorekeeper's Ring, Sentinel's Medallion, Caretaker's Cape
  - WSG: Sentinel's Blade, Protector's Sword, Outrunner's Bow, Lorekeeper's Staff
  - WSG: Sentinel's leg armor (all 6 armor types), Rune of Duty (Priest)
  - WSG: Silverwing Battle Tabard
  - AB: Full Highlander's sets (boots, belts, shoulders) for all 6 armor types
  - AB: Talisman of Arathor, Sageclaw, Arathor Battle Tabard
  - AB: Battle Tabard of the Defilers (missing Horde tabard)
- **Improved Faction Filter**: Added patterns for all new Alliance item names
  - Protector's, Lorekeeper, Caretaker, Outrunner, Arathor, Sageclaw
  - Fixed Battle Healer's Cloak not being filtered as Horde-only

## [1.1.14] - 2025-01-28

### Fixed
- **Honor Tracking**: Fixed end-of-game bonus honor not being captured
  - Win detection now waits 3 seconds before recording to capture bonus honor
  - Honor tracking handlers continue accumulating during the delay
  - Fixes inaccurate honor counts in all battlegrounds (most noticeable in WSG)

## [1.1.13] - 2025-01-28

### Fixed
- **Cross-Faction Class Gear**: Paladin and Shaman gear now visible regardless of faction
  - Alliance Shamans can now see Horde-named PvP gear (Warlord's, General's, etc.)
  - Horde Paladins can now see Alliance-named PvP gear (Field Marshal's, Marshal's, etc.)
  - TBC prepatch added Blood Elf Paladins and Draenei Shamans, making these classes cross-faction

### Added
- **TBC Insignias**: Added missing PvP trinkets for cross-faction classes
  - Shaman Insignia of the Alliance (for Draenei Shamans)
  - Paladin Insignia of the Horde (for Blood Elf Paladins)

## [1.1.12] - 2025-01-28

### Added
- **Minimized Hourly Rate**: Stats compact view now shows honor/hr alongside win-loss record

### Fixed
- **Hourly Rate Display**: Fixed hourly rate not showing after updating addon
  - sessionStartTime was not initialized during migration from older versions
  - Added safety check to ensure sessionStartTime is always valid

## [1.1.11] - 2025-01-27

### Fixed
- **Minimized Goals View**: Goals tab now shows compact summary when minimized
  - Displays goal count and overall progress percentage
  - Shows top goal icon and current honor on right
  - Switching between Stats/Goals tabs works correctly when minimized

## [1.1.10] - 2025-01-27

### Fixed
- **CurseForge Release**: Fixed game version for TBC Anniversary

## [1.1.9] - 2025-01-27

### Fixed
- **CurseForge Release**: Attempted game version fix (failed)

## [1.1.8] - 2025-01-27

### Added
- **Alliance AB Cloak**: Added Cloak of the Honor Guard (Alliance equivalent of Deathguard's Cloak)

## [1.1.7] - 2025-01-27

### Added
- **Waterfall Progress Mode**: New option to fill goals from top to bottom sequentially
  - When enabled, currency is allocated to goals in priority order
  - First goal fills completely before second goal starts filling
  - Shows "what can I buy next" more intuitively
  - Toggle in Options panel under Goals Settings
- **Drag to Reorder Goals**: Drag the grip handle on the left side of goal cards to reorder priorities
  - Visual feedback: card "lifts" and follows cursor while dragging
  - Gold drop indicator shows where card will land

### Fixed
- **Options Panel**: Fixed sliders not visible (custom slider implementation for TBC Classic compatibility)
- **Options Navigation**: `/honorlog options` now opens directly to HonorLog settings instead of general game options

## [1.1.6] - 2025-01-27

### Added
- **Owned Indicator**: Goal picker now shows "✓ Owned" badge for items you already have
- **Hide Owned Filter**: New checkbox to filter out items you already own
- **Weapon Filter**: Useable filter now hides weapons your class can't equip (e.g., crossbows for mages)

### Fixed
- **Totals Bar**: Fixed progress showing wrong values (was multiplying current honor by goal count)
- **Multiple Counting**: Fixed wins/losses being counted 2-3x in AV (added session-based recording guard)
- **Faction Filter**: Expanded to catch all Marshal's/General's rank gear and faction insignias
- **Progress Bars**: Fixed BG card progress bars not updating on window resize

## [1.1.5] - 2025-01-27

### Added
- **Unlimited Goals**: Track as many gear goals as you need (was limited to 5)

## [1.1.4] - 2025-01-27

### Added
- **Expanded Gear Database**: ~400 prepatch PvP items including BG reputation rewards
  - WSG, AB, and AV reputation gear (boots, belts, shoulders, weapons, trinkets)
  - All armor types supported (Cloth, Leather, Mail, Plate)
- **Useable Filter**: Goal picker checkbox to show only items your class can equip
- **Vendor Scanner**: Dev tool to scan PvP vendors (`/honorlog scan`)

## [1.1.3] - 2025-01-26

### Fixed
- **Out of Date Addon**: Updated Interface version to 20505 for TBC Classic Anniversary

## [1.1.2] - 2025-01-26

### Fixed
- **Goal Card Checkmark**: Complete checkmark icon now positioned left of remove button instead of overlapping it

## [1.1.1] - 2025-01-26

### Added
- **Window Resizer**: Drag the bottom-right corner to resize the frame
  - Resize grip in bottom-right corner (visible when unlocked)
  - Custom size saved across sessions
  - Minimum size: 220x60, Maximum size: 450x500
  - Toggle resizing via right-click menu or `/honorlog resize toggle`
  - Reset to default size via right-click menu or `/honorlog resize`
  - Scrollable content in both Stats and Goals views when frame is resized smaller
- **Goals Total Summary**: Shows combined progress toward all goals at bottom of Goals panel
  - XP-style progress bar showing overall completion percentage
  - Current/needed display for honor, arena points, and marks
  - Color-coded: green when currency requirement is met

### Fixed
- **Responsive Progress Bars**: Progress bar fill now updates correctly when frame is resized
- **Goal Card Text Overflow**: Currency and estimate text no longer overflows card boundaries
- **Goal Card Layout**: Reduced extra empty space at bottom of goal cards
- **Goals Panel Layout**: Add button properly aligned with totals bar, removed redundant session stats row

## [1.1.0] - 2025-01-26

### Added
- **Gear Goal Tracker**: Track progress toward purchasing PvP gear
  - Set up to 5 gear goals to track simultaneously
  - Shows honor, arena points, and marks progress for each goal
  - Estimates games remaining based on your personal performance data
  - Tab-based UI: Switch between "Stats" and "Goals" views
- **Comprehensive PvP Gear Database**: 350+ verified TBC PvP items
  - 280+ Classic Prepatch gear (rank 10-14 sets, weapons, accessories)
  - 75 Season 1-4 Gladiator items (archived until TBC launches)
  - High Warlord's/Grand Marshal's rank 14 weapons
  - Accessories (trinkets, rings, necks, cloaks)
  - Off-pieces (belts, boots, bracers)
- **Goal Picker UI**: Browse and select gear goals
  - Filter by slot (Head, Chest, Weapons, etc.)
  - Filter by type (Honor Only, Prepatch)
  - Search by item name
  - Shows cost breakdown for each item
  - Class-aware filtering (only shows items you can use)
- **Season Availability System**: Smart content gating for Anniversary timeline
  - Arena seasons (S1-S4) archived until TBC content unlocks
  - Easy configuration to enable seasons when they launch
- **Currency Tracking APIs**:
  - Real-time honor, arena points, and marks display
  - Average honor/marks per game calculations
  - Games remaining estimates for each goal
- **Goal Commands**:
  - `/honorlog goal` - Show goals panel
  - `/honorlog goal add [itemlink]` - Add a gear goal
  - `/honorlog goal list` - List current goals
  - `/honorlog goal clear` - Clear all goals
  - `/honorlog goal picker` - Open goal picker
- **Goal Completion Notifications**: Alert when you can afford a goal item
- **Hourly Honor Rate**: See your honor-per-hour across session panel, minimap tooltip, and goals panel
- **Session Stats Bar**: Goals panel now shows session honor rate and total gains
- **Minimap Button**: Quick access via LibDBIcon, toggle with `/honorlog minimap`

### Fixed
- **High Warlord's Gear Database**: Corrected mark types for level 70 HANDS (AB, not AV) and LEGS (AB, not WSG) items across all 9 classes
- **Currency Display**: Show current/needed format even when you have enough currency (displays in green when complete)
- **Session Panel Layout**: Two-line layout prevents text overlap on smaller frames
- **Gear Database Accuracy**: All item IDs verified against Wowhead TBC Classic database
- **BG Tracking**: Timer and honor counter reset properly when entering a new battleground
- **BG State**: Tracking state resets immediately when game ends (no longer persists across /reload)

### Changed
- Session stats now reset daily at midnight instead of on logout
- Session represents "today's stats" - persists across /reload but resets each new day

## [1.0.0] - 2025-01-23

### Added
- Initial release
- Track wins, losses, honor, and marks for all TBC battlegrounds (AV, AB, WSG, EotS)
- Per-character and account-wide statistics
- Session stats that reset on logout
- Match history (last 50 games)
- Expandable/collapsible main stats frame
- Draggable, lockable frame with position saving
- Right-click context menu
- Export to text (Discord/forums) or CSV (spreadsheet)
- Blizzard Interface Options integration
- LibDataBroker support for broker display addons
- Milestone notifications (optional)
- Slash commands: /honorlog, /hl
