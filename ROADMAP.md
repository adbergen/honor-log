# HonorLog Roadmap

## Current Version: 1.1.13

---

## Completed: Window Resizer (v1.1.1)

### Features Delivered
- Drag-to-resize via bottom-right grip
- Custom size persistence across sessions
- Min/max size constraints (220-450 width, 60-400 height)
- Toggle resizing via context menu or slash command
- Reset to default size option

---

## Completed: Gear Goal Tracker (v1.1.0)

### Overview
Allow players to set gear goals and track progress toward purchasing PvP items. Shows honor/marks/arena points needed and estimates games remaining based on personal performance data.

### User Stories
1. As a PvP player, I want to set a gear piece as my goal so I can see how close I am
2. As a PvP player, I want to see estimated games remaining based on MY average honor gains
3. As a PvP player, I want to track multiple goals simultaneously (unlimited)
4. As a PvP player, I want the addon to know PvP gear costs without manual entry
5. As a PvP player, I want to track arena gear goals alongside honor gear

### UI Decision
**Chosen approach**: Tab-based view switching in expanded mode
- Header gets two small tab buttons: "Stats" | "Goals"
- Stats view = current BG cards + session panel
- Goals view = goal cards + "Add Goal" button
- Same frame size, clean integration

---

## Implementation Progress

### Phase 1: Data Layer
- [x] Create PvP gear database structure
- [x] Populate TBC Honor gear (Rare PvP sets)
- [x] Populate TBC Arena gear (Gladiator sets S1-S4)
- [x] Populate Mark vendor items (each BG type)
- [x] Add goals data structure to SavedVariables
- [x] Add API: `GetCurrentHonor()`, `GetCurrentArenaPoints()`
- [x] Add API: `GetCurrentMarks(bgType)`
- [x] Add API: `GetAverageHonorPerGame()`, `GetAverageMarksPerGame(bgType)`
- [ ] Add API: `GetArenaPointsPerWeek()` (estimate based on rating if available)

### Phase 2: Goal Management
- [x] Goal data structure: `{ itemID, addedAt, priority }`
- [x] `AddGoal(itemID)` - add item to goals list
- [x] `RemoveGoal(itemID)` - remove from goals
- [x] `ReorderGoal(itemID, newPosition)` - change priority
- [x] `GetGoals()` - return all goals with progress calculated
- [x] `GetGoalProgress(itemID)` - returns { current, needed, percent, gamesRemaining }
- [x] Auto-remove completed goals option

### Phase 3: UI - Goals Panel
- [x] Add tab buttons to header ("Stats" | "Goals")
- [x] Create goals container (same size as expanded stats)
- [x] Goal card component:
  ```
  ┌─────────────────────────────────────────┐
  │ [Icon] Gladiator's Plate Helm      [X]  │
  │ ████████████░░░░░░  12,500 / 14,500     │
  │ 86%  •  ~6 games  •  1,875 Arena Pts    │
  └─────────────────────────────────────────┘
  ```
- [x] "Add Goal" button at bottom
- [x] Empty state: "No goals set. Click + to add one!"
- [x] Goal completion indicator (checkmark, glow)

### Phase 4: Goal Picker UI
- [x] Modal/popup frame for item selection
- [ ] Category tabs: Armor | Weapons | Accessories | Off-pieces
- [x] Slot filter dropdown (Head, Chest, etc.)
- [x] Class filter (show only usable items)
- [x] Search box for item name
- [x] Item rows with: Icon, Name, Cost breakdown, "Add" button
- [x] Hover shows full item tooltip
- [ ] Shift-click item anywhere to quick-add (if valid PvP item)

### Phase 5: Polish & UX
- [x] Goal completion celebration (message notification)
- [x] "You can afford this!" notification (Ready to purchase!)
- [ ] Tooltip on goal card shows full breakdown
- [ ] Goals in LDB tooltip
- [x] `/honorlog goal add <itemlink>` command
- [x] `/honorlog goal list` command
- [x] `/honorlog goal clear` command
- [ ] Export goals with stats

---

## Technical Specifications

### Gear Database Structure
```lua
-- Data/GearDatabase.lua
HonorLog.GearDB = {
    -- Format: [itemID] = { slot, class, honor, arena, marks }
    -- marks = { AV = n, AB = n, WSG = n, EotS = n }

    -- Example: Gladiator's Plate Helm (Warrior)
    [30486] = {
        slot = "HEAD",
        class = "WARRIOR",
        honor = 14500,
        arena = 1875,
        marks = {},
    },

    -- Example: Mark-only item
    [28915] = {
        slot = "NECK",
        class = nil, -- any class
        honor = 0,
        arena = 0,
        marks = { AV = 30, AB = 30, WSG = 30, EotS = 0 },
    },
}

-- Slot constants for filtering
HonorLog.SLOTS = {
    "HEAD", "NECK", "SHOULDER", "BACK", "CHEST",
    "WRIST", "HANDS", "WAIST", "LEGS", "FEET",
    "FINGER", "TRINKET", "MAIN_HAND", "OFF_HAND",
    "TWO_HAND", "RANGED", "RELIC"
}

-- Class constants
HonorLog.CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID"
}
```

### Goals SavedVariables Structure
```lua
-- Per-character goals
HonorLogCharDB.goals = {
    items = {
        -- { itemID = 30486, addedAt = timestamp, priority = 1 },
        -- { itemID = 28915, addedAt = timestamp, priority = 2 },
    },
    settings = {
        autoRemoveCompleted = false,
        showInLDB = true,
        celebrateCompletion = true,
    },
    -- No goal limit (unlimited)
}
```

### Currency APIs (TBC Classic)
```lua
-- Honor (TBC uses currency system)
local function GetCurrentHonor()
    -- TBC Classic Anniversary
    if GetHonorCurrency then
        return GetHonorCurrency()
    end
    -- Fallback
    return 0
end

-- Arena Points
local function GetCurrentArenaPoints()
    if GetArenaCurrency then
        return GetArenaCurrency()
    end
    return 0
end

-- Marks (items in bags)
local MARK_ITEMS = {
    AV = 20560,   -- Alterac Valley Mark of Honor
    AB = 20559,   -- Arathi Basin Mark of Honor
    WSG = 20558,  -- Warsong Gulch Mark of Honor
    EotS = 29024, -- Eye of the Storm Mark of Honor
}

local function GetCurrentMarks(bgType)
    local itemID = MARK_ITEMS[bgType]
    if itemID then
        return GetItemCount(itemID, true) -- true = include bank
    end
    return 0
end
```

### Estimation Algorithm
```lua
function HonorLog:EstimateGamesRemaining(itemID)
    local item = self.GearDB[itemID]
    if not item then return nil end

    local result = {
        honor = { needed = 0, current = 0, remaining = 0, games = 0 },
        arena = { needed = 0, current = 0, remaining = 0, weeks = 0 },
        marks = {},
    }

    -- Honor calculation
    if item.honor > 0 then
        result.honor.needed = item.honor
        result.honor.current = self:GetCurrentHonor()
        result.honor.remaining = math.max(0, item.honor - result.honor.current)

        local avgHonor = self:GetAverageHonorPerGame()
        if avgHonor > 0 then
            result.honor.games = math.ceil(result.honor.remaining / avgHonor)
        end
    end

    -- Arena calculation
    if item.arena > 0 then
        result.arena.needed = item.arena
        result.arena.current = self:GetCurrentArenaPoints()
        result.arena.remaining = math.max(0, item.arena - result.arena.current)
        -- Weeks estimate would need rating-based calculation
    end

    -- Marks calculation
    for bgType, count in pairs(item.marks or {}) do
        if count > 0 then
            local current = self:GetCurrentMarks(bgType)
            local remaining = math.max(0, count - current)
            local avgMarks = self:GetAverageMarksPerGame(bgType)

            result.marks[bgType] = {
                needed = count,
                current = current,
                remaining = remaining,
                games = avgMarks > 0 and math.ceil(remaining / avgMarks) or 0,
            }
        end
    end

    return result
end
```

---

## TBC PvP Gear Item IDs (To Research/Add)

### Season 1 Gladiator (Arena)
- Warrior, Paladin, Hunter, Rogue, Priest, Shaman, Mage, Warlock, Druid sets
- Weapons (various)

### Season 2 Merciless Gladiator (Arena)
- All class sets + weapons

### Season 3 Vengeful Gladiator (Arena)
- All class sets + weapons

### Season 4 Brutal Gladiator (Arena)
- All class sets + weapons

### Honor Gear (Rare Quality)
- High Warlord's/Grand Marshal's weapons
- Veteran's/Vindicator's armor sets
- PvP accessories (trinkets, rings, necks)

### Mark Vendors
- AV: Frostwolf/Stormpike reputation items
- AB: Honor+mark items
- WSG: Honor+mark items
- EotS: Honor+mark items

---

## Completed: Honor/Hour Analytics (v1.1.0)

### Features Delivered
- Hourly honor rate calculation based on session duration
- Display in session panel, minimap tooltip, and goals panel
- Session stats bar showing rate and total gains

## Future Features (Backlog)

### Performance Trends (v1.3.0)
- Combat log parsing for damage/healing/KB
- Track improvement over time
- Correlate stats with win/loss

### Enemy Intel (v1.4.0)
- Note system for enemy players
- Track encounter frequency
- Identify premade groups

### Arena Integration (v2.0.0)
- Track arena matches
- Rating history
- Team composition stats
