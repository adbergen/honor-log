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
        -- Session data (not persisted, reset on login)
        session = {
            AV = { played = 0, wins = 0, losses = 0, honor = 0, marks = 0 },
            AB = { played = 0, wins = 0, losses = 0, honor = 0, marks = 0 },
            WSG = { played = 0, wins = 0, losses = 0, honor = 0, marks = 0 },
            EotS = { played = 0, wins = 0, losses = 0, honor = 0, marks = 0 },
        },
    },
    settings = {
        frameVisible = true,
        frameExpanded = false,
        frameLocked = false,
        framePoint = { "CENTER", nil, "CENTER", 0, 0 },
        frameScale = 1.0,
        viewMode = "character", -- "character" or "account"
        exportFormat = "text", -- "text" or "csv"
        notificationsEnabled = false,
        ldbEnabled = true,
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

    -- Always reset session on login
    HonorLogCharDB.session = DeepCopy(DEFAULTS.char.session)

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
    }

    for bgType, session in pairs(self.db.char.session) do
        total.played = total.played + session.played
        total.wins = total.wins + session.wins
        total.losses = total.losses + session.losses
        total.honor = total.honor + session.honor
        total.marks = total.marks + session.marks
    end

    total.winrate = total.played > 0 and (total.wins / total.played * 100) or 0

    return total
end
