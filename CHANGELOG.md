# Changelog

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
