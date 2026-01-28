-- HonorLog Data Layer
-- Handles SavedVariables, data structures, and persistence

local ADDON_NAME, HonorLog = ...
HonorLog = HonorLog or {}
_G.HonorLog = HonorLog

-- Default database structure
local DEFAULTS = {
    global = {
        -- Account-wide lifetime stats per BG
        battlegrounds = {
            AV = { played = 0, wins = 0, losses = 0, totalDuration = 0, honorLifetime = 0, marksLifetime = 0 },
            AB = { played = 0, wins = 0, losses = 0, totalDuration = 0, honorLifetime = 0, marksLifetime = 0 },
            WSG = { played = 0, wins = 0, losses = 0, totalDuration = 0, honorLifetime = 0, marksLifetime = 0 },
            EotS = { played = 0, wins = 0, losses = 0, totalDuration = 0, honorLifetime = 0, marksLifetime = 0 },
        },
        history = {}, -- Account-wide history
        historyLimit = 50,
        characters = {}, -- Track which characters contributed
    },
    char = {
        -- Per-character stats
        battlegrounds = {
            AV = { played = 0, wins = 0, losses = 0, totalDuration = 0, honorLifetime = 0, marksLifetime = 0 },
            AB = { played = 0, wins = 0, losses = 0, totalDuration = 0, honorLifetime = 0, marksLifetime = 0 },
            WSG = { played = 0, wins = 0, losses = 0, totalDuration = 0, honorLifetime = 0, marksLifetime = 0 },
            EotS = { played = 0, wins = 0, losses = 0, totalDuration = 0, honorLifetime = 0, marksLifetime = 0 },
        },
        history = {}, -- Per-character history
        historyLimit = 50,
        -- Gear Goals system
        goals = {
            items = {}, -- Array of { itemID, addedAt, priority }
            settings = {
                autoRemoveCompleted = false,
                showInLDB = true,
                celebrateCompletion = true,
            },
            -- No goal limit
        },
        -- Daily stats (persists across /reload, resets at midnight)
        session = {
            AV = { played = 0, wins = 0, losses = 0, honor = 0, marks = 0 },
            AB = { played = 0, wins = 0, losses = 0, honor = 0, marks = 0 },
            WSG = { played = 0, wins = 0, losses = 0, honor = 0, marks = 0 },
            EotS = { played = 0, wins = 0, losses = 0, honor = 0, marks = 0 },
        },
        sessionStartTime = 0, -- Timestamp when session started
        lastUpdateTime = 0, -- Timestamp when session was last updated
        wasLogout = false, -- Track if last exit was logout vs reload (deprecated, kept for migration)
        lastGameTime = 0, -- GetTime() at last save - used to detect reload vs fresh login
        -- BG state (persists across /reload for mid-BG continuity)
        bgState = {
            currentBG = nil,
            bgStartTime = nil,
            bgStartHonor = nil,
            bgHonorAccumulated = 0,
            isInBG = false,
        },
    },
    settings = {
        frameVisible = true,
        frameExpanded = false,
        frameLocked = false,
        framePoint = { "CENTER", nil, "CENTER", 0, 0 },
        frameScale = 1.0,
        frameSize = nil, -- nil = use default, or { width, height } for custom size
        frameResizable = true, -- Allow frame resizing
        viewMode = "character", -- "character" or "account"
        exportFormat = "text", -- "text" or "csv"
        notificationsEnabled = false,
        ldbEnabled = true,
        minimapButton = {
            hide = false,
        },
        goalProgressMode = "shared", -- "shared" (all show same %) or "waterfall" (fills top-to-bottom)
    },
}

-- Deep copy utility
local function DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = DeepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

-- Deep merge (target inherits missing keys from source)
local function DeepMerge(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            DeepMerge(target[k], v)
        elseif target[k] == nil then
            target[k] = DeepCopy(v)
        end
    end
end

-- Initialize database
function HonorLog:InitializeDB()
    -- Global (account-wide) saved variables
    if not HonorLogDB then
        HonorLogDB = DeepCopy(DEFAULTS.global)
    else
        DeepMerge(HonorLogDB, DEFAULTS.global)
    end

    -- Per-character saved variables
    if not HonorLogCharDB then
        HonorLogCharDB = DeepCopy(DEFAULTS.char)
    else
        DeepMerge(HonorLogCharDB, DEFAULTS.char)
    end

    -- Settings (stored in global)
    if not HonorLogDB.settings then
        HonorLogDB.settings = DeepCopy(DEFAULTS.settings)
    else
        DeepMerge(HonorLogDB.settings, DEFAULTS.settings)
    end

    -- Session reset logic: Daily reset + reload detection
    -- Session = "today's stats" - resets at midnight, persists across /reload
    local now = time()
    local currentGameTime = GetTime()
    local lastGameTime = HonorLogCharDB.lastGameTime or 0
    local lastSessionDate = HonorLogCharDB.sessionDate

    -- Get today's date as YYYYMMDD number for easy comparison
    local today = tonumber(date("%Y%m%d", now))

    -- Check if we need to reset session
    local shouldResetSession = false
    local resetReason = ""

    -- Migration: if sessionDate was never set, this is first run after update
    -- Don't reset existing session data, just set the date
    -- sessionStartTime will be handled by the safety check below
    if not lastSessionDate then
        HonorLogCharDB.sessionDate = today
        lastSessionDate = today
        self.isReload = true
    -- Reset if it's a new day
    elseif lastSessionDate ~= today then
        shouldResetSession = true
        resetReason = "new day"
    -- Reset if client was restarted (GetTime() reset)
    elseif currentGameTime < lastGameTime and lastGameTime > 0 then
        -- Client restart on same day keeps session (daily stats)
        -- But we do need to clear BG state since that's mid-game tracking
        HonorLogCharDB.bgState = DeepCopy(DEFAULTS.char.bgState)
        self.isReload = false
        resetReason = "client restart (keeping daily session)"
    else
        -- This is a /reload - keep everything
        self.isReload = true
    end

    if shouldResetSession then
        print("|cff00ff00[HonorLog]|r New day detected - resetting daily stats for " .. date("%Y-%m-%d", now))
        HonorLogCharDB.session = DeepCopy(DEFAULTS.char.session)
        HonorLogCharDB.bgState = DeepCopy(DEFAULTS.char.bgState)
        HonorLogCharDB.sessionStartTime = 0 -- Will be set when first BG is entered
        HonorLogCharDB.sessionDate = today
        self.isReload = false
    else
        HonorLogCharDB.lastUpdateTime = now
    end

    -- Safety: Ensure sessionStartTime is valid for hourly rate calculation
    -- Only auto-set if there are existing session games (migration from older versions)
    if not HonorLogCharDB.sessionStartTime or HonorLogCharDB.sessionStartTime == 0 then
        local hasSessionGames = false
        for _, s in pairs(HonorLogCharDB.session) do
            if s.played and s.played > 0 then
                hasSessionGames = true
                break
            end
        end
        if hasSessionGames then
            HonorLogCharDB.sessionStartTime = now
        end
    end

    -- Update tracking values
    HonorLogCharDB.lastGameTime = currentGameTime

    -- Track this character
    local charKey = UnitName("player") .. "-" .. GetRealmName()
    HonorLogDB.characters[charKey] = true

    self.db = {
        global = HonorLogDB,
        char = HonorLogCharDB,
        settings = HonorLogDB.settings,
    }

    return self.db
end

-- Get stats for a specific BG
function HonorLog:GetBGStats(bgType, scope)
    scope = scope or self.db.settings.viewMode
    if scope == "account" then
        return self.db.global.battlegrounds[bgType]
    else
        return self.db.char.battlegrounds[bgType]
    end
end

-- Get session stats for a BG
function HonorLog:GetSessionStats(bgType)
    return self.db.char.session[bgType]
end

-- Get all BG stats
function HonorLog:GetAllBGStats(scope)
    scope = scope or self.db.settings.viewMode
    if scope == "account" then
        return self.db.global.battlegrounds
    else
        return self.db.char.battlegrounds
    end
end

-- Calculate derived stats
function HonorLog:GetDerivedStats(bgType, scope)
    local stats = self:GetBGStats(bgType, scope)
    local session = self:GetSessionStats(bgType)

    local winrate = 0
    if stats.played > 0 then
        winrate = (stats.wins / stats.played) * 100
    end

    local avgDuration = 0
    if stats.played > 0 then
        avgDuration = stats.totalDuration / stats.played
    end

    local sessionWinrate = 0
    if session.played > 0 then
        sessionWinrate = (session.wins / session.played) * 100
    end

    return {
        winrate = winrate,
        avgDuration = avgDuration,
        sessionWinrate = sessionWinrate,
    }
end

-- Record a completed game
function HonorLog:RecordGame(bgType, won, duration, honor, marks)
    -- Update character stats
    local charBG = self.db.char.battlegrounds[bgType]
    charBG.played = charBG.played + 1
    if won then
        charBG.wins = charBG.wins + 1
    else
        charBG.losses = charBG.losses + 1
    end
    charBG.totalDuration = charBG.totalDuration + duration
    charBG.honorLifetime = charBG.honorLifetime + honor
    charBG.marksLifetime = charBG.marksLifetime + marks

    -- Update account stats
    local globalBG = self.db.global.battlegrounds[bgType]
    globalBG.played = globalBG.played + 1
    if won then
        globalBG.wins = globalBG.wins + 1
    else
        globalBG.losses = globalBG.losses + 1
    end
    globalBG.totalDuration = globalBG.totalDuration + duration
    globalBG.honorLifetime = globalBG.honorLifetime + honor
    globalBG.marksLifetime = globalBG.marksLifetime + marks

    -- Update session stats
    local session = self.db.char.session[bgType]
    session.played = session.played + 1
    if won then
        session.wins = session.wins + 1
    else
        session.losses = session.losses + 1
    end
    session.honor = session.honor + honor
    session.marks = session.marks + marks

    -- Add to history
    local historyEntry = {
        bgType = bgType,
        win = won,
        duration = duration,
        honor = honor,
        marks = marks,
        timestamp = time(),
        character = UnitName("player"),
    }

    -- Character history
    table.insert(self.db.char.history, 1, historyEntry)
    while #self.db.char.history > self.db.char.historyLimit do
        table.remove(self.db.char.history)
    end

    -- Account history
    table.insert(self.db.global.history, 1, historyEntry)
    while #self.db.global.history > self.db.global.historyLimit do
        table.remove(self.db.global.history)
    end

    -- Check milestones
    self:CheckMilestones(bgType)

    -- Fire callback for UI update
    if self.OnDataUpdated then
        self:OnDataUpdated()
    end
end

-- Reset session stats
function HonorLog:ResetSession(bgType)
    if bgType then
        self.db.char.session[bgType] = DeepCopy(DEFAULTS.char.session[bgType])
    else
        self.db.char.session = DeepCopy(DEFAULTS.char.session)
    end

    if self.OnDataUpdated then
        self:OnDataUpdated()
    end

    return true
end

-- Get history
function HonorLog:GetHistory(scope, limit)
    scope = scope or self.db.settings.viewMode
    limit = limit or 10

    local history
    if scope == "account" then
        history = self.db.global.history
    else
        history = self.db.char.history
    end

    local result = {}
    for i = 1, math.min(limit, #history) do
        result[i] = history[i]
    end
    return result
end

-- Set history limit
function HonorLog:SetHistoryLimit(limit)
    limit = math.max(10, math.min(100, limit))
    self.db.char.historyLimit = limit
    self.db.global.historyLimit = limit

    -- Trim existing history
    while #self.db.char.history > limit do
        table.remove(self.db.char.history)
    end
    while #self.db.global.history > limit do
        table.remove(self.db.global.history)
    end
end

-- Milestone checking
local MILESTONES = {
    wins = { 10, 25, 50, 100, 250, 500, 1000 },
    played = { 10, 50, 100, 250, 500, 1000 },
    winrate = { 50, 60, 70, 80, 90 },
}

function HonorLog:CheckMilestones(bgType)
    if not self.db.settings.notificationsEnabled then return end

    local stats = self:GetBGStats(bgType, "character")
    local derived = self:GetDerivedStats(bgType, "character")

    -- Check win milestones
    for _, milestone in ipairs(MILESTONES.wins) do
        if stats.wins == milestone then
            self:AnnounceMilestone(bgType, "wins", milestone)
        end
    end

    -- Check games played milestones
    for _, milestone in ipairs(MILESTONES.played) do
        if stats.played == milestone then
            self:AnnounceMilestone(bgType, "played", milestone)
        end
    end

    -- Check winrate milestones (only if 10+ games)
    if stats.played >= 10 then
        for _, milestone in ipairs(MILESTONES.winrate) do
            local prevWinrate = ((stats.wins - 1) / (stats.played - 1)) * 100
            if prevWinrate < milestone and derived.winrate >= milestone then
                self:AnnounceMilestone(bgType, "winrate", milestone)
            end
        end
    end
end

function HonorLog:AnnounceMilestone(bgType, statType, value)
    local messages = {
        wins = string.format("|cff00ff00[HonorLog]|r Milestone! %d wins in %s!", value, bgType),
        played = string.format("|cff00ff00[HonorLog]|r Milestone! %d games played in %s!", value, bgType),
        winrate = string.format("|cff00ff00[HonorLog]|r Milestone! %d%% winrate achieved in %s!", value, bgType),
    }

    DEFAULT_CHAT_FRAME:AddMessage(messages[statType])
end

-- Settings accessors
function HonorLog:GetSetting(key)
    return self.db.settings[key]
end

function HonorLog:SetSetting(key, value)
    self.db.settings[key] = value
end

-- Format time duration
function HonorLog:FormatDuration(seconds)
    if seconds < 60 then
        return string.format("%ds", seconds)
    elseif seconds < 3600 then
        return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
    else
        return string.format("%dh %dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
    end
end

-- Get total session stats across all BGs
function HonorLog:GetTotalSessionStats()
    local total = {
        played = 0,
        wins = 0,
        losses = 0,
        honor = 0,
        marks = 0,
        hourlyRate = 0,
        sessionDuration = 0,
    }

    for bgType, session in pairs(self.db.char.session) do
        total.played = total.played + session.played
        total.wins = total.wins + session.wins
        total.losses = total.losses + session.losses
        total.honor = total.honor + session.honor
        total.marks = total.marks + session.marks
    end

    total.winrate = total.played > 0 and (total.wins / total.played * 100) or 0

    -- Calculate hourly rate based on session duration
    local sessionStart = self.db.char.sessionStartTime or 0
    if sessionStart > 0 and total.honor > 0 then
        local now = time()
        total.sessionDuration = now - sessionStart
        -- Only calculate rate if we have at least 1 minute of data
        if total.sessionDuration >= 60 then
            local hours = total.sessionDuration / 3600
            total.hourlyRate = math.floor(total.honor / hours)
        end
    end

    return total
end

--[[
============================================================================
CURRENCY APIs - For Gear Goal Tracking
============================================================================
--]]

-- Get current honor points
function HonorLog:GetCurrentHonor()
    -- Try C_CurrencyInfo API first (TBC Classic Anniversary uses this)
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        -- Honor currency ID 1901 is used in TBC Classic Anniversary
        local info = C_CurrencyInfo.GetCurrencyInfo(1901)
        if info and info.quantity and info.quantity > 0 then
            return info.quantity
        end
        -- Try other known honor currency IDs as fallback
        local currencyIDs = {1792, 392, 43308}
        for _, currencyID in ipairs(currencyIDs) do
            info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
            if info and info.quantity and info.quantity > 0 then
                return info.quantity
            end
        end
    end

    -- TBC Classic (original) uses GetHonorCurrency
    if GetHonorCurrency then
        local honor = GetHonorCurrency()
        if honor and honor > 0 then
            return honor
        end
    end

    -- Fallback: GetPVPCurrency (older Classic)
    if GetPVPCurrency then
        local _, honor = GetPVPCurrency()
        if honor and honor > 0 then
            return honor
        end
    end

    return 0
end

-- Get current arena points
function HonorLog:GetCurrentArenaPoints()
    -- Try C_CurrencyInfo API first (TBC Classic Anniversary)
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        -- Arena Points currency ID 1900 in TBC Classic Anniversary
        local info = C_CurrencyInfo.GetCurrencyInfo(1900)
        if info and info.quantity and info.quantity > 0 then
            return info.quantity
        end
    end

    -- TBC Classic (original) uses GetArenaCurrency
    if GetArenaCurrency then
        return GetArenaCurrency()
    end

    return 0
end

-- Get current marks for a specific BG type
function HonorLog:GetCurrentMarks(bgType)
    if not self.MARK_ITEMS then return 0 end
    local itemID = self.MARK_ITEMS[bgType]
    if itemID then
        return GetItemCount(itemID, true) -- true = include bank
    end
    return 0
end

-- Get all current marks
function HonorLog:GetAllCurrentMarks()
    return {
        AV = self:GetCurrentMarks("AV"),
        AB = self:GetCurrentMarks("AB"),
        WSG = self:GetCurrentMarks("WSG"),
        EotS = self:GetCurrentMarks("EotS"),
    }
end

--[[
============================================================================
AVERAGE CALCULATION APIs - For Game Estimates
============================================================================
--]]

-- Get average honor per game (based on lifetime stats)
function HonorLog:GetAverageHonorPerGame(scope)
    scope = scope or "character"
    local stats = scope == "account" and self.db.global.battlegrounds or self.db.char.battlegrounds

    local totalHonor = 0
    local totalGames = 0

    for bgType, bgStats in pairs(stats) do
        totalHonor = totalHonor + bgStats.honorLifetime
        totalGames = totalGames + bgStats.played
    end

    if totalGames > 0 then
        return totalHonor / totalGames
    end
    return 0
end

-- Get average marks per game for a specific BG
function HonorLog:GetAverageMarksPerGame(bgType, scope)
    scope = scope or "character"
    local stats = scope == "account" and self.db.global.battlegrounds or self.db.char.battlegrounds
    local bgStats = stats[bgType]

    if bgStats and bgStats.played > 0 then
        return bgStats.marksLifetime / bgStats.played
    end
    return 0
end

-- Get average honor per game for a specific BG
function HonorLog:GetAverageHonorPerBG(bgType, scope)
    scope = scope or "character"
    local stats = scope == "account" and self.db.global.battlegrounds or self.db.char.battlegrounds
    local bgStats = stats[bgType]

    if bgStats and bgStats.played > 0 then
        return bgStats.honorLifetime / bgStats.played
    end
    return 0
end

--[[
============================================================================
GOAL MANAGEMENT APIs
============================================================================
--]]

-- Get all goals
function HonorLog:GetGoals()
    return self.db.char.goals.items or {}
end

-- Get goal count
function HonorLog:GetGoalCount()
    return #(self.db.char.goals.items or {})
end

-- Check if can add more goals (no limit)
function HonorLog:CanAddGoal()
    return true
end

-- Check if item is already a goal
function HonorLog:IsGoal(itemID)
    for _, goal in ipairs(self.db.char.goals.items) do
        if goal.itemID == itemID then
            return true
        end
    end
    return false
end

-- Add a goal
function HonorLog:AddGoal(itemID)
    if not self:CanAddGoal() then
        return false, "Maximum goals reached"
    end

    if self:IsGoal(itemID) then
        return false, "Item is already a goal"
    end

    local item = self:GetGearItem(itemID)
    if not item then
        return false, "Item not found in gear database"
    end

    table.insert(self.db.char.goals.items, {
        itemID = itemID,
        addedAt = time(),
        priority = self:GetGoalCount() + 1,
    })

    if self.OnDataUpdated then
        self:OnDataUpdated()
    end

    return true
end

-- Remove a goal
function HonorLog:RemoveGoal(itemID)
    local goals = self.db.char.goals.items
    for i, goal in ipairs(goals) do
        if goal.itemID == itemID then
            table.remove(goals, i)
            -- Re-prioritize remaining goals
            for j = i, #goals do
                goals[j].priority = j
            end
            if self.OnDataUpdated then
                self:OnDataUpdated()
            end
            return true
        end
    end
    return false
end

-- Reorder a goal
function HonorLog:ReorderGoal(itemID, newPosition)
    local goals = self.db.char.goals.items
    local oldIndex = nil

    -- Find current position
    for i, goal in ipairs(goals) do
        if goal.itemID == itemID then
            oldIndex = i
            break
        end
    end

    if not oldIndex then return false end
    if newPosition < 1 or newPosition > #goals then return false end
    if oldIndex == newPosition then return true end

    -- Remove from old position and insert at new position
    local goal = table.remove(goals, oldIndex)
    table.insert(goals, newPosition, goal)

    -- Update priorities
    for i, g in ipairs(goals) do
        g.priority = i
    end

    if self.OnDataUpdated then
        self:OnDataUpdated()
    end

    return true
end

-- Get goal progress for a specific item
function HonorLog:GetGoalProgress(itemID)
    local item = self:GetGearItem(itemID)
    if not item then return nil end

    local result = {
        itemID = itemID,
        name = item.name,
        slot = item.slot,
        honor = {
            needed = item.honor or 0,
            current = self:GetCurrentHonor(),
            remaining = 0,
            percent = 0,
            games = 0,
        },
        arena = {
            needed = item.arena or 0,
            current = self:GetCurrentArenaPoints(),
            remaining = 0,
            percent = 0,
            weeks = 0,
        },
        marks = {},
        isComplete = true,
        totalGamesNeeded = 0,
    }

    -- Honor calculation
    if item.honor > 0 then
        result.honor.remaining = math.max(0, item.honor - result.honor.current)
        result.honor.percent = math.min(100, (result.honor.current / item.honor) * 100)

        local avgHonor = self:GetAverageHonorPerGame()
        if avgHonor > 0 and result.honor.remaining > 0 then
            result.honor.games = math.ceil(result.honor.remaining / avgHonor)
            result.totalGamesNeeded = math.max(result.totalGamesNeeded, result.honor.games)
        end

        if result.honor.remaining > 0 then
            result.isComplete = false
        end
    end

    -- Arena calculation
    if item.arena > 0 then
        result.arena.remaining = math.max(0, item.arena - result.arena.current)
        result.arena.percent = math.min(100, (result.arena.current / item.arena) * 100)

        if result.arena.remaining > 0 then
            result.isComplete = false
        end
    end

    -- Marks calculation
    if item.marks then
        for bgType, needed in pairs(item.marks) do
            if needed > 0 then
                local current = self:GetCurrentMarks(bgType)
                local remaining = math.max(0, needed - current)
                local percent = math.min(100, (current / needed) * 100)
                local games = 0

                local avgMarks = self:GetAverageMarksPerGame(bgType)
                if avgMarks > 0 and remaining > 0 then
                    games = math.ceil(remaining / avgMarks)
                    result.totalGamesNeeded = math.max(result.totalGamesNeeded, games)
                end

                result.marks[bgType] = {
                    needed = needed,
                    current = current,
                    remaining = remaining,
                    percent = percent,
                    games = games,
                }

                if remaining > 0 then
                    result.isComplete = false
                end
            end
        end
    end

    return result
end

-- Get all goals with progress
function HonorLog:GetAllGoalsProgress()
    local progressMode = self.db.settings.goalProgressMode or "shared"

    if progressMode == "waterfall" then
        return self:GetAllGoalsProgressWaterfall()
    end

    -- Default "shared" mode - all goals show same percentage based on current currency
    local results = {}
    for _, goal in ipairs(self.db.char.goals.items) do
        local progress = self:GetGoalProgress(goal.itemID)
        if progress then
            progress.addedAt = goal.addedAt
            progress.priority = goal.priority
            table.insert(results, progress)
        end
    end
    return results
end

-- Get all goals with waterfall-style progress (currency fills goals top-to-bottom)
function HonorLog:GetAllGoalsProgressWaterfall()
    local results = {}
    local goals = self.db.char.goals.items

    -- Get current currency totals
    local remainingHonor = self:GetCurrentHonor()
    local remainingArena = self:GetCurrentArenaPoints()
    local remainingMarks = {
        AV = self:GetCurrentMarks("AV"),
        AB = self:GetCurrentMarks("AB"),
        WSG = self:GetCurrentMarks("WSG"),
        EotS = self:GetCurrentMarks("EotS"),
    }

    -- Process goals in order, allocating currency top-to-bottom
    for _, goal in ipairs(goals) do
        local item = self:GetGearItem(goal.itemID)
        if item then
            local result = {
                itemID = goal.itemID,
                name = item.name,
                slot = item.slot,
                addedAt = goal.addedAt,
                priority = goal.priority,
                honor = {
                    needed = item.honor or 0,
                    current = 0,
                    remaining = 0,
                    percent = 0,
                    games = 0,
                },
                arena = {
                    needed = item.arena or 0,
                    current = 0,
                    remaining = 0,
                    percent = 0,
                    weeks = 0,
                },
                marks = {},
                isComplete = true,
                totalGamesNeeded = 0,
            }

            -- Honor allocation (waterfall style)
            if item.honor > 0 then
                local allocated = math.min(remainingHonor, item.honor)
                remainingHonor = remainingHonor - allocated

                result.honor.current = allocated
                result.honor.remaining = math.max(0, item.honor - allocated)
                result.honor.percent = math.min(100, (allocated / item.honor) * 100)

                local avgHonor = self:GetAverageHonorPerGame()
                if avgHonor > 0 and result.honor.remaining > 0 then
                    result.honor.games = math.ceil(result.honor.remaining / avgHonor)
                    result.totalGamesNeeded = math.max(result.totalGamesNeeded, result.honor.games)
                end

                if result.honor.remaining > 0 then
                    result.isComplete = false
                end
            end

            -- Arena allocation (waterfall style)
            if item.arena > 0 then
                local allocated = math.min(remainingArena, item.arena)
                remainingArena = remainingArena - allocated

                result.arena.current = allocated
                result.arena.remaining = math.max(0, item.arena - allocated)
                result.arena.percent = math.min(100, (allocated / item.arena) * 100)

                if result.arena.remaining > 0 then
                    result.isComplete = false
                end
            end

            -- Marks allocation (waterfall style)
            if item.marks then
                for bgType, needed in pairs(item.marks) do
                    if needed > 0 then
                        local allocated = math.min(remainingMarks[bgType] or 0, needed)
                        remainingMarks[bgType] = (remainingMarks[bgType] or 0) - allocated

                        local remaining = math.max(0, needed - allocated)
                        local percent = math.min(100, (allocated / needed) * 100)
                        local games = 0

                        local avgMarks = self:GetAverageMarksPerGame(bgType)
                        if avgMarks > 0 and remaining > 0 then
                            games = math.ceil(remaining / avgMarks)
                            result.totalGamesNeeded = math.max(result.totalGamesNeeded, games)
                        end

                        result.marks[bgType] = {
                            needed = needed,
                            current = allocated,
                            remaining = remaining,
                            percent = percent,
                            games = games,
                        }

                        if remaining > 0 then
                            result.isComplete = false
                        end
                    end
                end
            end

            table.insert(results, result)
        end
    end

    return results
end

-- Check and handle completed goals
function HonorLog:CheckCompletedGoals()
    local completed = {}
    local goals = self.db.char.goals.items

    for i = #goals, 1, -1 do
        local progress = self:GetGoalProgress(goals[i].itemID)
        if progress and progress.isComplete then
            table.insert(completed, progress)
            if self.db.char.goals.settings.autoRemoveCompleted then
                table.remove(goals, i)
            end
        end
    end

    -- Notify about completions
    if #completed > 0 and self.db.char.goals.settings.celebrateCompletion then
        for _, item in ipairs(completed) do
            print(string.format("|cff00ff00[HonorLog]|r Goal complete! You can now purchase: %s", item.name))
        end
    end

    return completed
end

-- Get goals settings
function HonorLog:GetGoalsSetting(key)
    return self.db.char.goals.settings[key]
end

-- Set goals setting
function HonorLog:SetGoalsSetting(key, value)
    self.db.char.goals.settings[key] = value
end
