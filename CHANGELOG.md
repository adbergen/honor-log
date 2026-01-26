# Changelog

## [1.2.0] - 2025-01-26

### Added
- **Hourly Honor Rate**: See your honor-per-hour across session panel, minimap tooltip, and goals panel
- **Session Stats Bar**: Goals panel now shows session honor rate and total gains

### Fixed
- **High Warlord's Gear Database**: Corrected mark types for level 70 HANDS (AB, not AV) and LEGS (AB, not WSG) items across all 9 classes
- **Currency Display**: Show current/needed format even when you have enough currency (displays in green when complete)
- **Session Panel Layout**: Two-line layout prevents text overlap on smaller frames

## [1.1.0] - 2025-01-25

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

### Fixed
- **Gear Database Accuracy**: Comprehensive audit and verification
  - All item IDs verified against Wowhead TBC Classic database
  - Fixed duplicate item ID conflicts
  - Corrected incorrect item IDs for several pieces

## [1.0.1] - 2025-01-23

### Added
- Minimap button using LibDBIcon for quick access
- Toggle minimap button via `/honorlog minimap` or Options panel

### Fixed
- BG timer and honor counter now reset properly when entering a new battleground
- BG tracking state resets immediately when game ends (no longer persists across /reload)

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
