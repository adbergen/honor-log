# Changelog

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
