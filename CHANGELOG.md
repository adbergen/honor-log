# Changelog

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
