-- HonorLog Data Layer
-- Handles SavedVariables, data structures, and persistence

local ADDON_NAME, HonorLog = ...
HonorLog = HonorLog or {}
_G.HonorLog = HonorLog

-- Forever-safe wrappers. WoW Forever's client is retail-shaped: the TBC globals
-- (GetItemInfo, GetBattlefieldScore, ...) are gone or only exist as optional
-- deprecation fallbacks, so every call goes through here and degrades to nil.
local Compat = {}
HonorLog.Compat = Compat

function Compat.GetItemInfo(...)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(...) end
    if GetItemInfo then return GetItemInfo(...) end
end

function Compat.GetItemCount(...)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(...) end
    if GetItemCount then return GetItemCount(...) end
    return 0
end

function Compat.GetBattlefieldWinner()
    if GetBattlefieldWinner then return GetBattlefieldWinner() end
end

function Compat.GetNumBattlefieldScores()
    if GetNumBattlefieldScores then return GetNumBattlefieldScores() end
    return 0
end

-- Returns name, killingBlows, honorableKills, deaths, honorGained, faction.
-- Old clients had GetBattlefieldScore; Forever only has C_PvP.GetScoreInfo,
-- which is secret during a match, so a secret row is treated as unreadable.
function Compat.GetBattlefieldScore(index)
    if GetBattlefieldScore then return GetBattlefieldScore(index) end
    if not index or not (C_PvP and C_PvP.GetScoreInfo) then return end
    local info = C_PvP.GetScoreInfo(index)
    if type(info) ~= "table" then return end
    if issecretvalue and issecretvalue(info.honorGained) then return end
    return info.name, info.killingBlows, info.honorableKills, info.deaths, info.honorGained, info.faction
end

-- Returns name, texture, price, quantity, numAvailable, isPurchasable, isUsable, hasExtendedCost.
function Compat.GetMerchantItemInfo(index)
    if GetMerchantItemInfo then return GetMerchantItemInfo(index) end
    if not (C_MerchantFrame and C_MerchantFrame.GetItemInfo) then return end
    local info = C_MerchantFrame.GetItemInfo(index)
    if not info then return end
    return info.name, info.texture, info.price, info.stackCount, info.numAvailable,
        info.isPurchasable, info.isUsable, info.hasExtendedCost
end

local GetItemInfo = Compat.GetItemInfo
local GetItemCount = Compat.GetItemCount

-- Saved-variable layout version. 2 = Forever (EotS moved to `legacy`, new history fields).
-- 3 = a summary per character (account `characters`), a record per reset week (`weeks`) and `since`.
local DB_VERSION = 3

-- Events with data: HonorLog.RegisterCallback(listener, "HonorLog_GameRecorded", function(event, entry) end).
-- Names and arguments: HonorLog_GameRecorded (entry), HonorLog_RankUp (newRank, Rank:GetInfo()),
-- HonorLog_WeekCapReached (info), HonorLog_HonorCapNear (current, cap), HonorLog_GoalAcquired (itemID),
-- HonorLog_QuestPaid (questID), HonorLog_WeekEnded (record), HonorLog_WorldKill (entry), HonorLog_WorldDeath (entry),
-- HonorLog_GameScoreboard (board = { rows, me, result, bgType, timestamp }, after a game with a readable board is saved).
HonorLog.callbacks = LibStub("CallbackHandler-1.0"):New(HonorLog)

-- Fire an event to the listeners. A listener that errors never reaches the caller.
function HonorLog:Fire(event, ...)
    local callbacks = self.callbacks
    if callbacks then pcall(callbacks.Fire, callbacks, event, ...) end
end

-- Lifetime counters for one battleground. played counts every recorded game;
-- win rate uses wins and losses only, draws and games left early are shown apart.
local function NewBGStats()
    -- cappedPlayed and cappedHonor are the games played at the honor cap and what they gave:
    -- the honor averages leave them out, because honor stops counting at the cap.
    return { played = 0, wins = 0, losses = 0, draws = 0, left = 0, totalDuration = 0, honorLifetime = 0, marksLifetime = 0,
             cappedPlayed = 0, cappedHonor = 0 }
end
local function NewSessionBG()
    return { played = 0, wins = 0, losses = 0, draws = 0, left = 0, honor = 0, marks = 0 }
end
local function NewWorldStats()
    return { kills = 0, deaths = 0, honor = 0, honorKill = 0, honorAward = 0, killingBlows = 0, unknownKills = 0 }
end

HonorLog.NewBGStats = NewBGStats
HonorLog.NewWorldStats = NewWorldStats

-- Default database structure
local DEFAULTS = {
    global = {
        -- Account-wide lifetime stats per BG
        battlegrounds = {
            AV = NewBGStats(),
            WSG = NewBGStats(),
            AB = NewBGStats(),
            DI = NewBGStats(),
        },
        -- Account-wide world PvP stats
        worldPvP = NewWorldStats(),
        history = {}, -- Account-wide history
        historyLimit = 200,
        scannedGear = {}, -- itemID -> { honor, marks, gold, seen, npc } from /honorlog scan
        scannedVendors = {},
        characters = {}, -- Track which characters contributed
        legacy = {}, -- TBC aggregates for battlegrounds Forever does not have (EotS)
        dbVersion = DB_VERSION,
    },
    char = {
        -- Per-character stats
        battlegrounds = {
            AV = NewBGStats(),
            WSG = NewBGStats(),
            AB = NewBGStats(),
            DI = NewBGStats(),
        },
        -- Per-character world PvP stats
        worldPvP = NewWorldStats(),
        history = {}, -- Per-character history
        historyLimit = 200,
        legacy = {}, -- TBC aggregates for battlegrounds Forever does not have (EotS)
        dbVersion = DB_VERSION,
        -- One record per reset week, newest first, at most 26 (Modules/Weeks.lua)
        weeks = {},
        -- Opponents met in world PvP: name -> { class, kills, deaths, lastSeen }, capped at 500
        opponents = {},
        -- Every world PvP kill and death, newest first, at most 500 (Modules/WorldLog.lua)
        worldLog = {},
        -- Players met in battlegrounds: name -> { class, with, withWins, against, againstWins, kbBest, last }, at most 1000 (Modules/Met.lua)
        met = {},
        -- Measured honor: today (by date), this week (until the weekly reset) and this login session
        honorLog = { day = 0, today = 0, weekEnd = 0, week = 0, session = 0 },
        honorCapWarned = false,
        -- Rank climb: weekly log (week number -> { startTotal, endTotal, games, capRank }, last 20 weeks),
        -- the week the cap alert last fired and the last rank celebrated.
        rankWeeks = {},
        rankCapAlertWeek = 0,
        rankCelebrated = 0,
        -- Saved goals whose items are not in the Forever database (TBC items), kept out of sight
        goalsLegacy = {},
        -- Gear Goals system
        goals = {
            items = {}, -- Array of { itemID, addedAt, priority }
            completed = {}, -- Array of { itemID, addedAt, completedAt }
            settings = {
                autoRemoveCompleted = false,
                showInLDB = true,
                celebrateCompletion = true,
            },
            -- No goal limit
        },
        -- Daily stats (persists across /reload, resets at midnight)
        session = {
            AV = NewSessionBG(),
            WSG = NewSessionBG(),
            AB = NewSessionBG(),
            DI = NewSessionBG(),
            worldPvP = NewWorldStats(),
        },
        sessionStartTime = 0, -- Timestamp when session started (deprecated, use sessionTotalDuration)
        sessionTotalDuration = 0, -- Cumulative BG duration in seconds (for accurate hourly rate)
        lastUpdateTime = 0, -- Timestamp when session was last updated
        wasLogout = false, -- Track if last exit was logout vs reload (deprecated, kept for migration)
        lastGameTime = 0, -- GetTime() at last save - used to detect reload vs fresh login
        -- BG state (persists across /reload for mid-BG continuity)
        -- bgState.match carries the snapshot and running sums of the game in progress.
        bgState = {
            currentBG = nil,
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
        windowPoint = nil, -- { point, relativePoint, x, y } of the full window; nil = centred
        windowScale = 1.0, -- scale of the full window
        windowTab = "overview", -- the screen the full window opens on
        windowRankTarget = 0, -- the rank the Rank plan screen plans to; 0 or one not offered = the first it offers
        windowGoal = 0, -- the item id chosen on the Gear goals screen; 0 or one not on the list = the first goal
        windowVendor = "", -- the vendor (its name) chosen in the vendor browser; "" or an unknown one = the first
        windowVendorClass = "player", -- the vendor browser's class filter: "player" (the player's class) or "all"
        windowBattleground = "all", -- the Battlegrounds screen's battleground filter: "all" or a battleground key
        windowResult = "all", -- its result filter: "all", "win" or "loss"
        viewMode = "character", -- "character" or "account"
        exportFormat = "text", -- "text" or "csv"
        notificationsEnabled = false,
        ldbEnabled = true,
        minimapButton = {
            hide = false,
        },
        mapArrowPoint = nil, -- { point, relativePoint, x, y } where the player left the map arrow
        goalProgressMode = "shared", -- "shared" (all show same %) or "waterfall" (fills top-to-bottom)
        goalCapAdvice = true, -- the goals header names what to buy when honor is about to cap
        goalShowUnverified = false, -- the picker lists retired-looking items nobody has seen stocked
        honorCapWarning = true,
        honorCapWarnPct = 90, -- warn once per crossing at this percent of the honor cap
        showRankBar = true, -- the rank bar under the header of the main panel
        rankCapAlert = true, -- one alert per week when the weekly rank cap is reached
        momentReport = true, -- the game report card after each battleground
        momentRankUp = true, -- the rank-up card
        momentHonorCap = true, -- the honor cap card
        momentSeconds = 12, -- seconds a card stays up (0 = until it is closed)
        ldbFormat = "games", -- broker text: "games" (win-loss today) or "rank" (R7 Title · 62%)
        visibleCards = { -- Which stat cards to show
            AV = true,
            WSG = true,
            AB = true,
            DI = true,
            World = true,
        },
    },
}

local DeepCopy, DeepMerge = HonorLog.Util.DeepCopy, HonorLog.Util.DeepMerge
local L = HonorLog.L
local Util = HonorLog.Util

-- Battleground keys Forever tracks. Anything else in an old save (EotS, arena
-- aggregates) moves under `legacy`; its history entries stay in the history list.
local TRACKED_BG = { AV = true, WSG = true, AB = true, DI = true }

-- Migration steps, run in order, each once, from the save's version plus one up to DB_VERSION.
local STEPS = {}

-- 2: Forever. Eye of the Storm and arena aggregates move to `legacy`; a TBC mid-game state is dropped.
STEPS[2] = function(store, isChar)
    store.legacy = store.legacy or {}
    if type(store.battlegrounds) == "table" then
        for key, stats in pairs(store.battlegrounds) do
            if not TRACKED_BG[key] then
                store.legacy[key] = stats
                store.battlegrounds[key] = nil
            end
        end
    end
    if isChar then
        if type(store.session) == "table" then
            for key, value in pairs(store.session) do
                if key ~= "worldPvP" and not TRACKED_BG[key] and type(value) == "table" then
                    store.session[key] = nil
                end
            end
        end
        -- A TBC mid-game state has no snapshot to resume from.
        store.bgState = nil
    end
end

-- 3: additive only, so HonorLog 2.0 still reads the save and loses only the new data.
-- The account's `characters[key] = true` becomes `{ name = key }` (2.0 only ever wrote that value, and never
-- read it); a key an early build made by joining a name to an empty realm ("Name-") is dropped.
-- A character store gets `since`, the earliest date the save can prove counting had begun by: its oldest
-- saved game, the oldest "last seen" of an opponent, or its first day of honor; with none of those, now.
STEPS[3] = function(store, isChar)
    if isChar then
        if type(store.since) ~= "number" then
            local oldest
            local function note(ts)
                if type(ts) == "number" and ts > 0 and (not oldest or ts < oldest) then oldest = ts end
            end
            if type(store.history) == "table" then
                for _, game in pairs(store.history) do
                    if type(game) == "table" then note(game.timestamp) end
                end
            end
            if type(store.opponents) == "table" then
                for _, opponent in pairs(store.opponents) do
                    if type(opponent) == "table" then note(opponent.lastSeen) end
                end
            end
            if type(store.honorDays) == "table" then
                for key in pairs(store.honorDays) do
                    local y, m, d = tostring(key):match("^(%d%d%d%d)(%d%d)(%d%d)$")
                    if y then note(time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })) end
                end
            end
            store.since = oldest or time()
        end
    elseif type(store.characters) == "table" then
        for key, value in pairs(store.characters) do
            if type(key) ~= "string" or key == "" or key:sub(-1) == "-" then
                store.characters[key] = nil
            elseif value == true then
                store.characters[key] = { name = key }
            end
        end
    end
end

-- A save with no version counts as version 1; one newer than this build is left alone.
local function MigrateStore(store, isChar)
    local version = type(store.dbVersion) == "number" and store.dbVersion or 1
    for step = version + 1, DB_VERSION do
        STEPS[step](store, isChar)
        store.dbVersion = step
    end
end
HonorLog.MigrateStore = MigrateStore

-- Initialize database
function HonorLog:InitializeDB()
    if type(HonorLogDB) == "table" then
        MigrateStore(HonorLogDB, false)
        if type(HonorLogDB.settings) == "table" and type(HonorLogDB.settings.visibleCards) == "table" then
            HonorLogDB.settings.visibleCards.EotS = nil
        end
    end
    if type(HonorLogCharDB) == "table" then MigrateStore(HonorLogCharDB, true) end

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

    -- Early 2.0 builds saved lastSeen with a fractional part; keep whole seconds.
    for _, e in pairs(HonorLogCharDB.opponents or {}) do
        if type(e) == "table" and type(e.lastSeen) == "number" then e.lastSeen = math.floor(e.lastSeen) end
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

    -- Debug: Print session state on load
    local sessionDebug = false -- Set to true to debug session issues
    if sessionDebug then
        print("|cffff00ff[HonorLog Session Debug]|r")
        print("  lastSessionDate: " .. tostring(lastSessionDate) .. " (type: " .. type(lastSessionDate) .. ")")
        print("  today: " .. tostring(today) .. " (type: " .. type(today) .. ")")
        print("  currentGameTime: " .. tostring(currentGameTime))
        print("  lastGameTime: " .. tostring(lastGameTime))
        -- Show current session stats before any reset
        if HonorLogCharDB.session then
            for bgType, s in pairs(HonorLogCharDB.session) do
                if s.played then
                    print("  session." .. bgType .. ": " .. s.played .. " played, " .. s.wins .. " wins")
                end
            end
        end
    end

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
        resetReason = "migration (keeping existing session)"
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
        resetReason = "reload (keeping everything)"
    end

    if sessionDebug then
        print("  Decision: " .. resetReason .. ", shouldReset: " .. tostring(shouldResetSession))
    end

    if shouldResetSession then
        -- Silent reset - no chat spam
        HonorLogCharDB.session = DeepCopy(DEFAULTS.char.session)
        HonorLogCharDB.bgState = DeepCopy(DEFAULTS.char.bgState)
        HonorLogCharDB.sessionStartTime = 0 -- Deprecated, kept for backwards compatibility
        HonorLogCharDB.sessionTotalDuration = 0 -- Reset cumulative BG time
        HonorLogCharDB.sessionDate = today
        self.isReload = false
    else
        HonorLogCharDB.lastUpdateTime = now
    end

    -- The honor "session" is this login; a /reload keeps it.
    if not self.isReload then HonorLogCharDB.honorLog.session = 0 end

    -- Update tracking values
    HonorLogCharDB.lastGameTime = currentGameTime

    -- Track this character
    local characterKey = self:GetCharacterKey()
    if type(HonorLogDB.characters[characterKey]) ~= "table" then HonorLogDB.characters[characterKey] = { name = characterKey } end

    self.db = {
        global = HonorLogDB,
        char = HonorLogCharDB,
        settings = HonorLogDB.settings,
    }

    self:ArchiveUnknownGoals()

    return self.db
end

-- Counters for a battleground, created on first use so a generic "MAP<id>"
-- battleground (one the registry did not know) is recorded like any other.
function HonorLog:EnsureBGStats(bgType)
    local char, global, session = self.db.char, self.db.global, self.db.char.session
    char.battlegrounds[bgType] = char.battlegrounds[bgType] or NewBGStats()
    global.battlegrounds[bgType] = global.battlegrounds[bgType] or NewBGStats()
    session[bgType] = session[bgType] or NewSessionBG()
    for _, tbl in ipairs({ char.battlegrounds[bgType], global.battlegrounds[bgType] }) do
        DeepMerge(tbl, NewBGStats())
    end
    DeepMerge(session[bgType], NewSessionBG())
end

-- Get stats for a specific BG
function HonorLog:GetBGStats(bgType, scope)
    scope = scope or self.db.settings.viewMode
    self:EnsureBGStats(bgType)
    if scope == "account" then
        return self.db.global.battlegrounds[bgType]
    else
        return self.db.char.battlegrounds[bgType]
    end
end

-- Get session stats for a BG
function HonorLog:GetSessionStats(bgType)
    self:EnsureBGStats(bgType)
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

-- Win rate is wins over decided games; draws and games left early are not in it.
local function WinRate(wins, losses)
    local decided = (wins or 0) + (losses or 0)
    if decided <= 0 then return 0 end
    return (wins / decided) * 100
end

-- Calculate derived stats
function HonorLog:GetDerivedStats(bgType, scope)
    local stats = self:GetBGStats(bgType, scope)
    local session = self:GetSessionStats(bgType)

    local avgDuration = 0
    if stats.played > 0 then
        avgDuration = stats.totalDuration / stats.played
    end

    return {
        winrate = WinRate(stats.wins, stats.losses),
        avgDuration = avgDuration,
        sessionWinrate = WinRate(session.wins, session.losses),
    }
end

local RESULTS = { win = "wins", loss = "losses", draw = "draws", left = "left" }

-- Record a completed game. `won` stays for older callers; extra.result
-- ("win" | "loss" | "draw" | "left") wins over it. extra also carries the
-- optional history fields: joinedInProgress, kb, hk, deaths, damage, healing,
-- objectives, rankPoints, rankState, rankCappedDuring, honorCapped, teams, scoreboard, rep
-- ({ faction, gained }: reputation the game gave with its battleground's own faction).
function HonorLog:RecordGame(bgType, won, duration, honor, marks, extra)
    extra = extra or {}
    local result = extra.result or (won and "win" or "loss")
    local counter = RESULTS[result] or "losses"
    honor = honor or 0
    marks = marks or 0
    duration = duration or 0
    self:EnsureBGStats(bgType)

    -- Track cumulative BG time for accurate hourly rate calculation
    self.db.char.sessionTotalDuration = (self.db.char.sessionTotalDuration or 0) + duration

    local function bump(stats)
        stats.played = stats.played + 1
        stats[counter] = (stats[counter] or 0) + 1
    end
    local charBG = self.db.char.battlegrounds[bgType]
    bump(charBG)
    charBG.totalDuration = charBG.totalDuration + duration
    charBG.honorLifetime = charBG.honorLifetime + honor
    charBG.marksLifetime = charBG.marksLifetime + marks
    if extra.honorCapped then
        charBG.cappedPlayed = (charBG.cappedPlayed or 0) + 1
        charBG.cappedHonor = (charBG.cappedHonor or 0) + honor
    end

    local globalBG = self.db.global.battlegrounds[bgType]
    bump(globalBG)
    globalBG.totalDuration = globalBG.totalDuration + duration
    globalBG.honorLifetime = globalBG.honorLifetime + honor
    globalBG.marksLifetime = globalBG.marksLifetime + marks
    if extra.honorCapped then
        globalBG.cappedPlayed = (globalBG.cappedPlayed or 0) + 1
        globalBG.cappedHonor = (globalBG.cappedHonor or 0) + honor
    end

    local session = self.db.char.session[bgType]
    bump(session)
    session.honor = session.honor + honor
    session.marks = session.marks + marks

    -- Add to history. Every field after `character` is optional, so entries
    -- from older versions (win/duration/honor/marks only) display unchanged.
    local historyEntry = {
        bgType = bgType,
        win = result == "win",
        result = result,
        duration = duration,
        honor = honor,
        marks = marks,
        timestamp = time(),
        character = Util.unitName("player"),
        joinedInProgress = extra.joinedInProgress or nil,
        kb = extra.kb, hk = extra.hk, deaths = extra.deaths,
        damage = extra.damage, healing = extra.healing,
        objectives = extra.objectives,
        rankPoints = extra.rankPoints,
        rankState = extra.rankState,
        rankCappedDuring = extra.rankCappedDuring,
        honorCapped = extra.honorCapped,
        teams = extra.teams,
        scoreboard = extra.scoreboard,
        rep = extra.rep,
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
    self:CheckMilestones(bgType, result)

    -- Fire callback for UI update
    if self.OnDataUpdated then
        self:OnDataUpdated()
    end

    self:Fire("HonorLog_GameRecorded", historyEntry)
end

-- The key a character is filed under: the whole name, and the realm only when the client names one
-- (Forever returns an empty realm name).
function HonorLog:GetCharacterKey()
    local name, realm = Util.unitName("player") or "Unknown", Util.str(Util.call(GetRealmName))
    return (realm and realm ~= "") and (name .. "-" .. realm) or name
end

-- Reset session stats
function HonorLog:ResetSession(bgType)
    if bgType then
        self.db.char.session[bgType] = DeepCopy(DEFAULTS.char.session[bgType] or NewSessionBG())
    else
        self.db.char.session = DeepCopy(DEFAULTS.char.session)
        self.db.char.sessionTotalDuration = 0 -- Reset cumulative BG time
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

-- One history entry as a line: "Win  WSG  3/12/2  +450 honor  +3 marks  +100 rank".
-- Entries from before 2.0 have no result or scoreboard fields and show what they have.
local RESULT_TEXT = { win = "Win", loss = "Loss", draw = "Draw", left = "Left" }
local RESULT_COLOR = { win = "40d860", loss = "e65959", draw = "ffd700", left = "999999" }
function HonorLog:FormatHistoryRow(entry)
    local result = entry.result or (entry.win and "win" or "loss")
    local parts = {
        string.format("|cff%s%s|r", RESULT_COLOR[result] or "ffffff", RESULT_TEXT[result] or tostring(result)),
        self:GetBGDisplayName(entry.bgType),
    }
    if entry.kb or entry.hk or entry.deaths then
        parts[#parts + 1] = string.format("%d/%d/%d", entry.kb or 0, entry.hk or 0, entry.deaths or 0)
    end
    parts[#parts + 1] = string.format("+%d honor", entry.honor or 0)
    parts[#parts + 1] = string.format("+%d marks", entry.marks or 0)
    if entry.rankPoints then parts[#parts + 1] = string.format("+%d rank", entry.rankPoints) end
    if entry.joinedInProgress then parts[#parts + 1] = "(joined late)" end
    return table.concat(parts, "  ")
end

-- Set history limit
function HonorLog:SetHistoryLimit(limit)
    limit = math.max(10, math.min(500, limit))
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

function HonorLog:CheckMilestones(bgType, result)
    if not self.db.settings.notificationsEnabled then return end

    local stats = self:GetBGStats(bgType, "character")
    local derived = self:GetDerivedStats(bgType, "character")

    -- Check win milestones (only a win can reach one)
    for _, milestone in ipairs(MILESTONES.wins) do
        if result == "win" and stats.wins == milestone then
            self:AnnounceMilestone(bgType, "wins", milestone)
        end
    end

    -- Check games played milestones
    for _, milestone in ipairs(MILESTONES.played) do
        if stats.played == milestone then
            self:AnnounceMilestone(bgType, "played", milestone)
        end
    end

    -- Check winrate milestones (only if 10+ decided games, and only a win raises the rate)
    local decided = stats.wins + stats.losses
    if result == "win" and decided >= 10 then
        for _, milestone in ipairs(MILESTONES.winrate) do
            local prevWinrate = ((stats.wins - 1) / (decided - 1)) * 100
            if prevWinrate < milestone and derived.winrate >= milestone then
                self:AnnounceMilestone(bgType, "winrate", milestone)
            end
        end
    end
end

function HonorLog:AnnounceMilestone(bgType, statType, value)
    local name = self:GetBGDisplayName(bgType)
    local messages = {
        wins = string.format("|cff00ff00[HonorLog]|r Milestone! %d wins in %s!", value, name),
        played = string.format("|cff00ff00[HonorLog]|r Milestone! %d games played in %s!", value, name),
        winrate = string.format("|cff00ff00[HonorLog]|r Milestone! %d%% winrate achieved in %s!", value, name),
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
    seconds = math.floor(seconds or 0) -- averages are fractional; %d needs whole seconds
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
        draws = 0,
        left = 0,
        honor = 0,
        marks = 0,
        hourlyRate = 0,
        sessionDuration = 0,
    }

    for bgType, session in pairs(self.db.char.session) do
        -- Skip non-BG entries (like worldPvP)
        if session.played then
            total.played = total.played + session.played
            total.wins = total.wins + session.wins
            total.losses = total.losses + session.losses
            total.draws = total.draws + (session.draws or 0)
            total.left = total.left + (session.left or 0)
            total.honor = total.honor + session.honor
            total.marks = total.marks + session.marks
        end
    end

    total.winrate = WinRate(total.wins, total.losses)

    -- Calculate hourly rate based on cumulative BG duration (actual play time)
    local cumulativeDuration = self.db.char.sessionTotalDuration or 0

    -- Include current in-progress BG duration for live rate updates
    local bgStart = self:GetBGStartTime()
    if bgStart then
        local currentBGElapsed = GetTime() - bgStart
        if currentBGElapsed > 0 then
            cumulativeDuration = cumulativeDuration + currentBGElapsed
        end
    end

    if cumulativeDuration > 0 and total.honor > 0 then
        total.sessionDuration = cumulativeDuration
        -- Only calculate rate if we have at least 1 minute of BG time
        if cumulativeDuration >= 60 then
            local hours = cumulativeDuration / 3600
            total.hourlyRate = math.floor(total.honor / hours)
        end
    end

    return total
end

--[[
============================================================================
WORLD PVP TRACKING APIs
============================================================================
--]]

-- The three world-PvP counters every kill, death and honor gain lands in.
local function WorldTargets(self)
    return { self.db.char.worldPvP, self.db.global.worldPvP, self.db.char.session.worldPvP }
end

local OPPONENT_CAP = 500

-- Note an opponent met in the open world. kind = "kill" or "death".
function HonorLog:NoteOpponent(name, class, kind)
    if type(name) ~= "string" or name == "" then return end
    local opponents = self.db.char.opponents
    local entry = opponents[name]
    if not entry then
        entry = { kills = 0, deaths = 0 }
        opponents[name] = entry
        local count = 0
        for _ in pairs(opponents) do count = count + 1 end
        -- Over the cap: drop the oldest lastSeen first (never the entry just added).
        while count > OPPONENT_CAP do
            local oldestName, oldestSeen, oldestOrder
            for other, e in pairs(opponents) do
                local seen = math.floor(e.lastSeen or 0)
                local order = self.opponentOrder and self.opponentOrder[other] or 0
                if other ~= name and (not oldestSeen or seen < oldestSeen or (seen == oldestSeen and order < oldestOrder)) then
                    oldestName, oldestSeen, oldestOrder = other, seen, order
                end
            end
            if not oldestName then break end
            opponents[oldestName] = nil
            count = count - 1
        end
    end
    if class then entry.class = class end
    if kind == "kill" then entry.kills = entry.kills + 1 else entry.deaths = entry.deaths + 1 end
    -- lastSeen is whole seconds. Entries noted within the same second are told apart by an in-memory
    -- counter (never saved), so the cap still drops the oldest first.
    self.opponentSeq = (self.opponentSeq or 0) + 1
    self.opponentOrder = self.opponentOrder or {}
    self.opponentOrder[name] = self.opponentSeq
    entry.lastSeen = time()
end

-- Top opponents by total encounters (most kills + deaths first).
function HonorLog:GetTopOpponents(limit)
    local list = {}
    for name, e in pairs(self.db.char.opponents) do
        list[#list + 1] = { name = name, class = e.class, kills = e.kills or 0, deaths = e.deaths or 0, lastSeen = e.lastSeen or 0 }
    end
    table.sort(list, function(a, b)
        local ta, tb = a.kills + a.deaths, b.kills + b.deaths
        if ta ~= tb then return ta > tb end
        if a.lastSeen ~= b.lastSeen then return a.lastSeen > b.lastSeen end
        local oa, ob = self.opponentOrder and self.opponentOrder[a.name] or 0, self.opponentOrder and self.opponentOrder[b.name] or 0
        if oa ~= ob then return oa > ob end
        return a.name < b.name
    end)
    for i = #list, (limit or 5) + 1, -1 do list[i] = nil end
    return list
end

-- Record a world kill (outside battlegrounds). name is nil for a kill nobody
-- could be named for ("unknown"). detail = { rank, honor } from the kill message that was paired with the
-- kill, or nothing. Fires HonorLog_WorldKill(entry) with entry = { name, class, kb, rank, honor }, each only
-- when known (kb only when true).
function HonorLog:RecordWorldKill(name, class, killingBlow, detail)
    for _, w in ipairs(WorldTargets(self)) do
        w.kills = w.kills + 1
        if not name then w.unknownKills = (w.unknownKills or 0) + 1 end
        if killingBlow then w.killingBlows = (w.killingBlows or 0) + 1 end
    end
    if name then self:NoteOpponent(name, class, "kill") end
    if self.OnDataUpdated then self:OnDataUpdated() end
    local entry = { name = name, class = class, kb = killingBlow and true or nil }
    if type(detail) == "table" then entry.rank, entry.honor = detail.rank, detail.honor end
    self:Fire("HonorLog_WorldKill", entry)
end

-- Record a world death (killed by an enemy player outside battlegrounds). Fires HonorLog_WorldDeath(entry)
-- with entry = { name, class }, each only when known. A killer the death recap could not name counts as a
-- death and joins no opponent's tally.
function HonorLog:RecordWorldDeath(name, class)
    for _, w in ipairs(WorldTargets(self)) do
        w.deaths = w.deaths + 1
    end
    if name then self:NoteOpponent(name, class, "death") end
    if self.OnDataUpdated then self:OnDataUpdated() end
    self:Fire("HonorLog_WorldDeath", { name = name, class = class })
end

-- Record honor earned outside battlegrounds (measured from the currency).
function HonorLog:RecordWorldHonor(amount)
    if not amount or amount <= 0 then return end
    for _, w in ipairs(WorldTargets(self)) do
        w.honor = w.honor + amount
    end
    if self.OnDataUpdated then self:OnDataUpdated() end
end

-- The kill and award messages tell what kind of honor it was; the measured
-- total stays in `honor`, the rest is "other" (see GetWorldHonorSplit).
function HonorLog:RecordWorldHonorKind(kind, amount)
    if not amount or amount <= 0 then return end
    local field = kind == "kill" and "honorKill" or "honorAward"
    for _, w in ipairs(WorldTargets(self)) do
        w[field] = (w[field] or 0) + amount
    end
end

function HonorLog:GetWorldHonorSplit(scope)
    local w = self:GetWorldPvPStats(scope)
    local kill, award = w.honorKill or 0, w.honorAward or 0
    return { total = w.honor or 0, kill = kill, award = award, other = math.max(0, (w.honor or 0) - kill - award) }
end

-- Get world PvP stats
function HonorLog:GetWorldPvPStats(scope)
    scope = scope or self.db.settings.viewMode
    if scope == "account" then
        return self.db.global.worldPvP
    else
        return self.db.char.worldPvP
    end
end

-- Get session world PvP stats
function HonorLog:GetSessionWorldPvPStats()
    return self.db.char.session.worldPvP
end

--[[
============================================================================
HONOR SUMMARY - measured from currency 1792 gains, never assumed
============================================================================
--]]

local HONOR_CURRENCY = 1792

local function Today()
    return tonumber(date("%Y%m%d", time()))
end

-- Roll today / this week over when the date or the weekly reset has passed.
local function RollHonorLog(self)
    local log = self.db.char.honorLog
    local now = time()
    local day = Today()
    if log.day ~= day then log.day = day; log.today = 0 end
    if (log.weekEnd or 0) <= now then
        log.week = 0
        local untilReset = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()
        if type(untilReset) == "number" and not (issecretvalue and issecretvalue(untilReset)) and untilReset > 0 then
            log.weekEnd = now + untilReset
        else
            log.weekEnd = now + 7 * 86400 -- no reset clock: a rolling week
        end
    end
    return log
end

-- Called for every positive honor change, in a battleground or not.
function HonorLog:AddHonorGain(amount)
    if type(amount) ~= "number" or amount <= 0 then return end
    local log = RollHonorLog(self)
    -- The per-day store first: when it is created now, its back-fill reads today's total before this gain.
    if self.NoteHonorDay then self:NoteHonorDay(amount) end
    log.today = log.today + amount
    log.week = log.week + amount
    log.session = log.session + amount
end

-- The honor currency's record, or nil when the client gives none, raises, or hides it as a secret value
-- (a secret must not be indexed, compared or added).
local function HonorCurrency()
    local info = C_CurrencyInfo and Util.call(C_CurrencyInfo.GetCurrencyInfo, HONOR_CURRENCY)
    if type(info) ~= "table" or Util.isSecret(info) then return nil end
    return info
end

-- Today, this week, this session, the hourly rate and the cap.
function HonorLog:GetHonorSummary()
    local log = RollHonorLog(self)
    local info = HonorCurrency()
    local cap = info and Util.num(info.maxQuantity) or 0
    local current = info and Util.num(info.quantity) or 0
    return {
        today = log.today, week = log.week, session = log.session,
        perHour = self:GetTotalSessionStats().hourlyRate,
        current = current, cap = cap,
        percent = cap > 0 and (current / cap * 100) or 0,
    }
end

--[[
============================================================================
CURRENCY APIs - For Gear Goal Tracking
============================================================================
--]]

-- Get current honor points (currency 1792 on Forever)
function HonorLog:GetCurrentHonor()
    local info = HonorCurrency()
    return info and Util.num(info.quantity) or 0
end

-- Get current marks for a specific BG type
function HonorLog:GetCurrentMarks(bgType)
    -- The battleground registry knows Forever's mark items; the gear database's MARK_ITEMS is the fallback.
    local itemID = (self.BG_MARK_ITEMS and self.BG_MARK_ITEMS[bgType]) or (self.MARK_ITEMS and self.MARK_ITEMS[bgType])
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
        DI = self:GetCurrentMarks("DI"),
    }
end

--[[
============================================================================
AVERAGE CALCULATION APIs - For Game Estimates
============================================================================
--]]

-- Honor and games of a battleground's stats without the games played at the honor cap.
function HonorLog:UncappedHonor(bgStats)
    local games = (bgStats.played or 0) - (bgStats.cappedPlayed or 0)
    local honor = (bgStats.honorLifetime or 0) - (bgStats.cappedHonor or 0)
    return honor, math.max(0, games)
end

-- Get average honor per game (based on lifetime stats, games at the cap left out)
function HonorLog:GetAverageHonorPerGame(scope)
    scope = scope or "character"
    local stats = scope == "account" and self.db.global.battlegrounds or self.db.char.battlegrounds

    local totalHonor = 0
    local totalGames = 0

    for _, bgStats in pairs(stats) do
        local honor, games = self:UncappedHonor(bgStats)
        totalHonor = totalHonor + honor
        totalGames = totalGames + games
    end

    if totalGames > 0 then
        return totalHonor / totalGames
    end

    -- No games recorded yet: a rough estimate (~250 honor per game)
    return 250
end

-- Get average marks per game for a specific BG
function HonorLog:GetAverageMarksPerGame(bgType, scope)
    scope = scope or "character"
    local stats = scope == "account" and self.db.global.battlegrounds or self.db.char.battlegrounds
    local bgStats = stats[bgType]

    if bgStats and (bgStats.played or 0) > 0 then
        return (bgStats.marksLifetime or 0) / bgStats.played
    end

    -- Fallback: ~1.5 marks per game (3 for win, 0-1 for loss)
    return 1.5
end

-- Get average honor per game for a specific BG
function HonorLog:GetAverageHonorPerBG(bgType, scope)
    scope = scope or "character"
    local stats = scope == "account" and self.db.global.battlegrounds or self.db.char.battlegrounds
    local bgStats = stats[bgType]

    if bgStats then
        local honor, games = self:UncappedHonor(bgStats)
        if games > 0 then return honor / games end
    end

    -- No games recorded yet: a rough estimate
    return 250
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

-- Complete a goal (move from active to completed)
function HonorLog:CompleteGoal(itemID)
    local goals = self.db.char.goals.items
    local completed = self.db.char.goals.completed

    for i, goal in ipairs(goals) do
        if goal.itemID == itemID then
            -- Move to completed list
            table.insert(completed, {
                itemID = goal.itemID,
                addedAt = goal.addedAt,
                completedAt = time(),
            })
            -- Remove from active list
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

-- Restore a completed goal back to active
function HonorLog:RestoreGoal(itemID)
    local goals = self.db.char.goals.items
    local completed = self.db.char.goals.completed

    for i, goal in ipairs(completed) do
        if goal.itemID == itemID then
            -- Add back to active list at the end
            table.insert(goals, {
                itemID = goal.itemID,
                addedAt = goal.addedAt,
                priority = #goals + 1,
            })
            -- Remove from completed list
            table.remove(completed, i)
            if self.OnDataUpdated then
                self:OnDataUpdated()
            end
            return true
        end
    end
    return false
end

-- Remove a completed goal permanently
function HonorLog:RemoveCompletedGoal(itemID)
    local completed = self.db.char.goals.completed
    for i, goal in ipairs(completed) do
        if goal.itemID == itemID then
            table.remove(completed, i)
            if self.OnDataUpdated then
                self:OnDataUpdated()
            end
            return true
        end
    end
    return false
end

-- Get completed goals list
function HonorLog:GetCompletedGoals()
    return self.db.char.goals.completed or {}
end

-- Check if an item is in player's bags or equipped
function HonorLog:IsItemInInventory(itemID)
    -- Check bags (0 = backpack, 1-4 = additional bags)
    for bag = 0, 4 do
        local numSlots = 0
        if C_Container and C_Container.GetContainerNumSlots then
            numSlots = C_Container.GetContainerNumSlots(bag) or 0
        elseif GetContainerNumSlots then
            numSlots = GetContainerNumSlots(bag) or 0
        end

        for slot = 1, numSlots do
            local slotItemID = nil
            if C_Container and C_Container.GetContainerItemID then
                slotItemID = C_Container.GetContainerItemID(bag, slot)
            elseif GetContainerItemID then
                slotItemID = GetContainerItemID(bag, slot)
            end

            if slotItemID and slotItemID == itemID then
                return true
            end
        end
    end

    -- Check equipped items (slots 1-19 cover all equipment slots)
    for slot = 1, 19 do
        local equippedItemID = GetInventoryItemID("player", slot)
        if equippedItemID and equippedItemID == itemID then
            return true
        end
    end

    return false
end

-- Scan all active goals and auto-complete any that are in inventory
function HonorLog:ScanGoalsForAcquiredItems()
    local goals = self.db.char.goals.items
    local acquiredItems = {}

    -- First pass: find all acquired items
    for _, goal in ipairs(goals) do
        if self:IsItemInInventory(goal.itemID) then
            table.insert(acquiredItems, goal.itemID)
        end
    end

    -- Second pass: complete them (separate loop to avoid modifying table while iterating)
    for _, itemID in ipairs(acquiredItems) do
        local itemName, _, itemQuality = GetItemInfo(itemID)
        itemName = itemName or "Item"
        self:CompleteGoal(itemID)
        self:Fire("HonorLog_GoalAcquired", itemID)

        -- Celebratory notification!
        -- 1. Play quest complete sound
        PlaySound(878) -- SOUNDKIT.IG_QUEST_LIST_COMPLETE

        -- 2. Show center-screen alert (like achievements)
        if RaidNotice_AddMessage and RaidBossEmoteFrame then
            RaidNotice_AddMessage(RaidBossEmoteFrame, "|cff00ff00Goal Acquired!|r " .. itemName, ChatTypeInfo["RAID_WARNING"])
        end

        -- 3. Show in UIErrorsFrame (green, top of screen)
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage("|cff40d860[HonorLog]|r Goal acquired: " .. itemName, 0.25, 0.85, 0.37, 1, 3)
        end

        -- 4. Chat message (for log)
        print("|cff40d860[HonorLog]|r \124\124 Goal acquired: |cffffffff" .. itemName .. "|r")
    end

    return #acquiredItems
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

--[[
============================================================================
GEAR DATABASE ACCESS
============================================================================
Data/GearDatabase.lua is generated; HonorLogDB.scannedGear holds what the
player's own vendor scans saw (/honorlog scan). A scan overrides the generated
cost and proves the item is stocked right now.
--]]

HonorLog.STANDING_NAMES = { [1] = "Hated", [2] = "Hostile", [3] = "Unfriendly", [4] = "Neutral",
    [5] = "Friendly", [6] = "Honored", [7] = "Revered", [8] = "Exalted" }

local function ScannedEntry(itemID)
    local store = type(HonorLogDB) == "table" and HonorLogDB.scannedGear
    local scan = type(store) == "table" and store[itemID]
    return type(scan) == "table" and scan or nil
end

-- The client's name once the item is cached, the generated one before that.
function HonorLog:GetGearName(itemID)
    local name = GetItemInfo(itemID)
    if type(name) == "string" and name ~= "" then return name end
    local base = self.GearDB and self.GearDB[itemID]
    return base and base.name or nil
end

-- A copy of the database entry with scanned costs laid over it, or nil.
function HonorLog:GetGearItem(itemID)
    local base = self.GearDB and self.GearDB[itemID]
    if not base then return nil end
    local item = {}
    for key, value in pairs(base) do item[key] = value end
    item.itemID = itemID
    item.name = self:GetGearName(itemID) or base.name
    local scan = ScannedEntry(itemID)
    if scan then
        item.honor = scan.honor or 0
        item.gold = scan.gold or 0
        item.marks = nil
        if type(scan.marks) == "table" and next(scan.marks) then
            item.marks = {}
            for bgType, count in pairs(scan.marks) do item.marks[bgType] = count end
        end
        item.scanned, item.stocked, item.seen = true, true, scan.seen
    elseif self:IsBGReputationGear(base) then
        item.unconfirmed = true -- sold, players say, but no scan of yours has seen it yet
    end
    return item
end

-- The battleground faction ids by battleground and side, in one place. Each game records the
-- reputation it gave with its own battleground's faction.
HonorLog.BG_REP_FACTIONS = {
    AB = { Horde = 510, Alliance = 509 },
    AV = { Horde = 729, Alliance = 730 },
    WSG = { Horde = 889, Alliance = 890 },
    DI = { Horde = 2798, Alliance = 2799 },
}

-- Faction id -> battleground, for the three old battlegrounds whose reputation gear is sold again.
local BG_OF_REP_FACTION = {}
for bgType, sides in pairs(HonorLog.BG_REP_FACTIONS) do
    for _, factionID in pairs(sides) do BG_OF_REP_FACTION[factionID] = bgType end
end
HonorLog.BG_OF_REP_FACTION = BG_OF_REP_FACTION

-- The reputation faction of a battleground for the player's side, or nil.
function HonorLog:GetBGRepFaction(bgType)
    local sides = self.BG_REP_FACTIONS[bgType]
    local faction = Util.str(UnitFactionGroup and UnitFactionGroup("player"))
    return sides and faction and sides[faction] or nil
end

-- Arathi Basin, Alterac Valley and Warsong Gulch reputation items the generated data calls legacy.
function HonorLog:IsBGReputationGear(base)
    if not (base and base.legacy and base.source == "REP" and base.rep and base.rep.faction) then return false end
    local bgType = BG_OF_REP_FACTION[base.rep.faction]
    return bgType == "AB" or bgType == "AV" or bgType == "WSG"
end

-- Items the client may have retired stay in the database as `legacy` and count as available only
-- once a vendor scan has seen them stocked. The battleground reputation items are the exception:
-- players confirm those vendors sell on Forever, so they are available at once (item.unconfirmed
-- until a scan has seen them).
function HonorLog:IsGearAvailable(itemID)
    local base = self.GearDB and self.GearDB[itemID]
    if not base then return false end
    return not base.legacy or ScannedEntry(itemID) ~= nil or self:IsBGReputationGear(base)
end

function HonorLog:GetHonorCap()
    local info = HonorCurrency()
    local cap = info and Util.num(info.maxQuantity) or nil
    if cap and cap > 0 then return cap end
    return nil
end

-- Standing, amount and thresholds with a faction, from the client, or nil when it cannot say.
-- standing is the reaction id (4 Neutral .. 8 Exalted; 0 for a faction the client has not met);
-- current, floor and ceiling are the client's absolute numbers, so current - floor is the amount
-- into the standing and ceiling - floor the standing's span. A number the client withholds is nil.
function HonorLog:GetReputationProgress(factionID)
    if not (C_Reputation and C_Reputation.GetFactionDataByID) then return nil end
    local ok, data = pcall(C_Reputation.GetFactionDataByID, factionID)
    if not ok then return nil end
    if type(data) ~= "table" then return { standing = 0 } end
    local standing = Util.num(data.reaction)
    if not standing then return nil end
    return {
        standing = standing,
        current = Util.num(data.currentStanding),
        floor = Util.num(data.currentReactionThreshold),
        ceiling = Util.num(data.nextReactionThreshold),
    }
end

-- Reputation standing id (4 Neutral .. 8 Exalted) with a faction, or nil when the client cannot
-- say. A faction the client has not met reads as 0.
function HonorLog:GetReputationStanding(factionID)
    local progress = self:GetReputationProgress(factionID)
    return progress and progress.standing or nil
end

-- Reputation a standing takes to finish, by standing id (Neutral .. Revered).
HonorLog.STANDING_SPANS = { [4] = 3000, [5] = 6000, [6] = 12000, [7] = 21000 }

-- Reputation still needed to reach `needed` from a standing with `into` reputation gained inside it.
-- Standings below Neutral are counted from Neutral's start.
function HonorLog:ReputationRemaining(standing, into, needed)
    standing = math.max(4, standing or 0)
    if standing >= needed then return 0 end
    local total = 0
    for s = standing, needed - 1 do total = total + (self.STANDING_SPANS[s] or 0) end
    return math.max(0, total - (into or 0))
end

local REP_SAMPLE = 20 -- newest games that recorded a faction

-- Average reputation per game with a faction over the newest games that recorded it, or nil.
function HonorLog:GetRepPerGame(factionID)
    local history = self.db and self.db.char and self.db.char.history or {}
    local sum, n = 0, 0
    for _, game in ipairs(history) do
        local rep = game.rep
        if type(rep) == "table" and rep.faction == factionID and type(rep.gained) == "number" then
            sum, n = sum + rep.gained, n + 1
            if n >= REP_SAMPLE then break end
        end
    end
    if n == 0 then return nil end
    return sum / n
end

--[[
============================================================================
VENDORS
============================================================================
Where an item is sold. A vendor the player's own scan saw selling it wins; otherwise the built-in
table (Data/Vendors.lua) is searched by the item's source, slot and the player's faction.
--]]

local WEAPON_VENDOR_SLOTS = { MAIN_HAND = true, OFF_HAND = true, TWO_HAND = true, RANGED = true }

-- Position text for a scanned vendor: "Subzone, Zone", whichever the scan recorded.
local function ScannedPlace(rec)
    local zone, sub = Util.str(rec.zone), Util.str(rec.subzone)
    if zone and zone ~= "" and sub and sub ~= "" and sub ~= zone then return sub .. ", " .. zone end
    if sub and sub ~= "" then return sub end
    if zone and zone ~= "" then return zone end
    return nil
end

local function BuiltinVendorByName(self, name)
    for _, v in ipairs(self.VENDORS or {}) do
        if v.name == name then return v end
    end
    return nil
end

-- Which built-in vendor kind sells an item, and for a supply officer which faction.
local function VendorKindFor(base)
    if base.slot == "MOUNT" then return "mount" end
    if base.slot == "TOKEN" then return "accessories" end
    if base.source == "REP" then
        return base.rep and base.rep.faction and "supply" or nil, base.rep and base.rep.faction
    end
    if base.source == "HONOR" or base.source == "UPGRADE" then
        return WEAPON_VENDOR_SLOTS[base.slot] and "weapons" or "armor"
    end
    if base.source == "RANK" then
        return WEAPON_VENDOR_SLOTS[base.slot] and "weapons" or "accessories"
    end
    return nil
end

-- The kind of vendor that sells an item (armor, weapons, accessories, mount, supply) and, for a supply
-- officer, the reputation faction: kind, repFaction. nil when the item is not in the database.
function HonorLog:GetVendorKind(itemID)
    local base = self.GearDB and self.GearDB[itemID]
    if not base then return nil end
    return VendorKindFor(base)
end

-- { name, role, place, map, x, y, npc, source = "scan" | "builtin" } for the vendor that sells an
-- item, or nil. x and y are percent of the map and may be missing.
function HonorLog:GetVendorFor(itemID)
    local base = self.GearDB and self.GearDB[itemID]
    if not base then return nil end

    local scan = ScannedEntry(itemID)
    local scannedName = scan and Util.str(scan.npc)
    if scannedName then
        local rec = type(HonorLogDB) == "table" and type(HonorLogDB.scannedVendors) == "table"
            and HonorLogDB.scannedVendors[scannedName]
        rec = type(rec) == "table" and rec or {}
        local known = BuiltinVendorByName(self, scannedName)
        local vendor = { name = scannedName, source = "scan", npc = rec.npc, role = known and known.role or nil }
        vendor.map, vendor.x, vendor.y = rec.map, rec.x, rec.y
        vendor.place = ScannedPlace(rec)
        if known then
            -- A scan from before positions were recorded keeps working: borrow the built-in ones.
            if not vendor.map then vendor.map, vendor.x, vendor.y = known.map, known.x, known.y end
            vendor.place = vendor.place or known.place
            vendor.npc = vendor.npc or known.npc
        end
        return vendor
    end

    local kind, repFaction = VendorKindFor(base)
    if not kind then return nil end
    local faction = Util.str(UnitFactionGroup and UnitFactionGroup("player"))
    for _, v in ipairs(self.VENDORS or {}) do
        if v.kind == kind and (not faction or v.faction == faction)
            and (kind ~= "supply" or v.repFaction == repFaction) then
            return { name = v.name, role = v.role, place = v.place, map = v.map, x = v.x, y = v.y, npc = v.npc, source = "builtin" }
        end
    end
    return nil
end

-- Take the player to a vendor: HonorLog's own pin and arrow (UI/MapPin.lua). Returns true when a
-- pin was placed.
function HonorLog:ShowVendorOnMap(vendor, extra)
    if type(vendor) ~= "table" then
        self:Say(L["HonorLog does not know where this item is sold yet."])
        return false
    end
    if vendor.map and not (vendor.x and vendor.y) then
        -- The zone is known, the exact spot is not: show the zone and say how to learn the spot.
        local mapPin = self.MapPin
        local mapName = mapPin and mapPin.MapName(vendor.map) or vendor.place or vendor.name
        if mapPin then mapPin:OpenMap(vendor.map) end
        self:Say(string.format(L["%s is in %s. Open the vendor once and HonorLog will remember exactly where it stands."], vendor.name, mapName))
        return false
    end
    if not (vendor.map and vendor.x and vendor.y and self.ShowPlaceOnMap) then
        local where = vendor.place and (vendor.name .. ", " .. vendor.place) or vendor.name
        self:Say(string.format(L["%s: open this vendor once and HonorLog will remember where it stands."], where))
        return false
    end
    local place = {
        name = vendor.name, detail = vendor.role, map = vendor.map, x = vendor.x, y = vendor.y,
        npc = vendor.npc, kind = "vendor",
    }
    if extra then place.reason, place.icon = extra.reason, extra.icon end
    return self:ShowPlaceOnMap(place)
end

-- Alt+Click on a goal or a picker row: the pin also says what the player is going there to buy.
function HonorLog:ShowVendorForItem(itemID)
    local vendor = itemID and self:GetVendorFor(itemID) or nil
    local icon
    if itemID then
        local getIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
        if getIcon then icon = Util.call(getIcon, itemID) end
    end
    return self:ShowVendorOnMap(vendor, { reason = itemID and self:GetGearName(itemID) or nil, icon = icon })
end

-- /honorlog vendor <goal number | item name | item link>: the goal first, then any item the picker lists.
function HonorLog:ShowVendorForArg(arg)
    arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "" then
        self:Say(L["Usage: /honorlog vendor [item name or goal number]"])
        return false
    end
    local goals = self:GetGoals()
    local itemID = tonumber(arg:match("item:(%d+)"))
    local n = tonumber(arg)
    if not itemID and n and goals[n] then itemID = goals[n].itemID end
    local needle = arg:lower()
    if not itemID then
        for _, goal in ipairs(goals) do
            local name = (self:GetGearName(goal.itemID) or ""):lower()
            if name ~= "" and name:find(needle, 1, true) then itemID = goal.itemID break end
        end
    end
    if not itemID then
        local found = self:GetPickerItems({ search = needle, showUnverified = true })
        itemID = found[1] and found[1].itemID or nil
    end
    if not itemID then
        self:Say(string.format(L["No gear item matches '%s'."], arg))
        return false
    end
    return self:ShowVendorForItem(itemID)
end

-- "Sold by Brave Stonehide, Hall of Legends, Orgrimmar", or nil when the vendor is not known.
function HonorLog:GetVendorLine(itemID)
    local vendor = self:GetVendorFor(itemID)
    if not vendor then return nil end
    if vendor.place then return string.format(L["Sold by %s, %s"], vendor.name, vendor.place) end
    return string.format(L["Sold by %s"], vendor.name)
end

function HonorLog:FormatMoney(copper)
    copper = math.floor(tonumber(copper) or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local out = {}
    if g > 0 then out[#out + 1] = string.format("|cffffd700%sg|r", BreakUpLargeNumbers(g)) end
    if s > 0 then out[#out + 1] = string.format("|cffc0c0c0%ds|r", s) end
    if c > 0 or #out == 0 then out[#out + 1] = string.format("|cffcd7f32%dc|r", c) end
    return table.concat(out, " ")
end

--[[
============================================================================
PICKER
============================================================================
--]]

local ARMOR_BY_CLASS = {
    WARRIOR = "PLATE", PALADIN = "PLATE", HUNTER = "MAIL", SHAMAN = "MAIL",
    ROGUE = "LEATHER", DRUID = "LEATHER", PRIEST = "CLOTH", MAGE = "CLOTH", WARLOCK = "CLOTH",
}
HonorLog.ARMOR_BY_CLASS = ARMOR_BY_CLASS

-- Weapon sub-types a class can use (itemSubType as the client names them).
local WEAPON_SUBTYPES = {
    WARRIOR = { "One-Handed Axes", "Two-Handed Axes", "One-Handed Swords", "Two-Handed Swords", "One-Handed Maces",
        "Two-Handed Maces", "Daggers", "Fist Weapons", "Polearms", "Staves", "Bows", "Crossbows", "Guns", "Thrown" },
    PALADIN = { "One-Handed Axes", "Two-Handed Axes", "One-Handed Swords", "Two-Handed Swords", "One-Handed Maces",
        "Two-Handed Maces", "Polearms" },
    HUNTER = { "One-Handed Axes", "Two-Handed Axes", "One-Handed Swords", "Two-Handed Swords", "Daggers",
        "Fist Weapons", "Polearms", "Staves", "Bows", "Crossbows", "Guns", "Thrown" },
    SHAMAN = { "One-Handed Axes", "Two-Handed Axes", "One-Handed Maces", "Two-Handed Maces", "Daggers",
        "Fist Weapons", "Staves" },
    ROGUE = { "One-Handed Swords", "One-Handed Maces", "Daggers", "Fist Weapons", "Bows", "Crossbows", "Guns",
        "Thrown" },
    DRUID = { "One-Handed Maces", "Two-Handed Maces", "Daggers", "Fist Weapons", "Polearms", "Staves" },
    MAGE = { "One-Handed Swords", "Daggers", "Staves", "Wands" },
    WARLOCK = { "One-Handed Swords", "Daggers", "Staves", "Wands" },
    PRIEST = { "One-Handed Maces", "Daggers", "Staves", "Wands" },
}
local WEAPON_SLOTS = { MAIN_HAND = true, OFF_HAND = true, TWO_HAND = true, RANGED = true }

local function ClassUsesWeapon(class, itemID)
    local list = WEAPON_SUBTYPES[class]
    if not list then return true end
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(itemID)
    if itemType ~= "Weapon" or not itemSubType then return true end -- not cached: do not hide
    for _, name in ipairs(list) do
        if name == itemSubType then return true end
    end
    return false
end

-- Items the picker lists. filters: slot, class (nil = any class), armor, source, search (lower case),
-- showUnverified, hideOwned, keepGoals (also list items already on the goal list). Faction is never a filter: it is always the player's own plus neutral items.
function HonorLog:GetPickerItems(filters)
    filters = filters or {}
    local faction = UnitFactionGroup("player")
    local out = {}
    for itemID, data in pairs(self.GearDB or {}) do
        local pass = true
        if data.faction and data.faction ~= faction then pass = false end
        if pass and not filters.showUnverified and not self:IsGearAvailable(itemID) then pass = false end
        if pass and filters.slot and data.slot ~= filters.slot then pass = false end
        if pass and filters.class then
            if data.class and data.class ~= filters.class then pass = false end
            -- Armour with no class of its own (reputation pieces) must be the class's own armour type.
            if pass and not data.class and data.armor and ARMOR_BY_CLASS[filters.class] and data.armor ~= ARMOR_BY_CLASS[filters.class] then
                pass = false
            end
            if pass and WEAPON_SLOTS[data.slot] and not ClassUsesWeapon(filters.class, itemID) then pass = false end
        end
        if pass and filters.armor and data.armor ~= filters.armor then pass = false end
        if pass and filters.source then
            local src = data.source
            if filters.source == "RANK" then
                if src ~= "RANK" then pass = false end
            elseif src ~= filters.source then
                pass = false
            end
        end
        if pass and filters.search and filters.search ~= "" then
            local name = (self:GetGearName(itemID) or data.name or ""):lower()
            if not name:find(filters.search, 1, true) then pass = false end
        end
        if pass and filters.hideOwned and GetItemCount(itemID, true) > 0 then pass = false end
        if pass and not filters.keepGoals and self:IsGoal(itemID) then pass = false end
        if pass then out[#out + 1] = { itemID = itemID, data = data, name = self:GetGearName(itemID) or data.name } end
    end
    table.sort(out, function(a, b)
        if a.data.slot ~= b.data.slot then return a.data.slot < b.data.slot end
        if (a.name or "") ~= (b.name or "") then return (a.name or "") < (b.name or "") end
        return a.itemID < b.itemID
    end)
    return out
end

--[[
============================================================================
GOAL PROGRESS
============================================================================
A progress result carries one row per requirement (honor, one per battleground's
marks, gold, rank, reputation), the rows still short, and the date it will be
ready. Everything is also exposed under named fields (honor, marks[bg], gold,
rank, rep) for the panels.
--]]

local DAY = 86400

local function NewContext(self)
    local Rank = self.Rank
    local info = Rank and Rank.GetInfo and Rank:GetInfo() or nil
    local ctx = {
        honor = self:GetCurrentHonor(),
        cap = self:GetHonorCap(),
        money = GetMoney and GetMoney() or 0,
        marks = self:GetAllCurrentMarks(),
        level = Util.num(UnitLevel and UnitLevel("player")),
        faction = Util.str(UnitFactionGroup and UnitFactionGroup("player")),
        info = info,
        pace = Rank and Rank.GetPace and Rank:GetPace() or { gamesPerDay = 0, pointsPerGame = 0 },
        plans = {},
        now = time(),
    }
    return ctx
end

-- Best honor per game among the battlegrounds the player has played; the average otherwise.
function HonorLog:GetBestHonorPerGame()
    local best
    for _, bgType in ipairs(self.BG_ORDER or {}) do
        local stats = self.db.char.battlegrounds[bgType]
        if stats then
            local honor, games = self:UncappedHonor(stats)
            if games > 0 and (not best or honor / games > best) then best = honor / games end
        end
    end
    return best or self:GetAverageHonorPerGame()
end

-- Games it takes to earn the missing honor and marks. Each missing mark type is earned in its own
-- battleground; those games' honor counts, and any honor still missing is earned in the best battleground.
function HonorLog:EstimateGames(honorMissing, marksMissing)
    local games, marksGames, estimated = 0, 0, false
    local honorFromMarks = 0
    for _, bgType in ipairs(self.BG_ORDER or {}) do
        local missing = marksMissing and marksMissing[bgType] or 0
        if missing > 0 then
            local stats = self.db.char.battlegrounds[bgType]
            if not stats or (stats.played or 0) == 0 then estimated = true end
            local perGame = math.max(0.01, self:GetAverageMarksPerGame(bgType))
            local g = math.ceil(missing / perGame)
            marksGames = marksGames + g
            honorFromMarks = honorFromMarks + g * self:GetAverageHonorPerBG(bgType)
        end
    end
    local honorGames = 0
    local left = math.max(0, (honorMissing or 0) - honorFromMarks)
    if left > 0 then
        local best = math.max(1, self:GetBestHonorPerGame())
        honorGames = math.ceil(left / best)
    end
    local total = marksGames + honorGames
    return total, { marksGames = marksGames, honorGames = honorGames, estimated = estimated }
end

-- When honor and marks at the measured rate and the rank plan allow the purchase.
-- Returns date (or nil), limitedBy, games.
local function ReadyEstimate(self, ctx, honorMissing, marksMissing, rankRow, repRow)
    local games, detail = self:EstimateGames(honorMissing, marksMissing)
    local now = ctx.now
    local gpd = ctx.pace and ctx.pace.gamesPerDay or 0

    -- Reputation is earned in the same games as marks; it needs its own measured rate. Games for
    -- everything are the longest of the two. Without a rate there is no date: never "ready today".
    local rateLimitOverride, noRep
    if repRow and repRow.known and not repRow.met and repRow.faction and (repRow.remainingRep or 0) > 0 then
        if repRow.games then
            if repRow.games > games then
                games = repRow.games
                rateLimitOverride = "rep"
            end
        else
            noRep = true
        end
    end

    local rateDate, rateLimit
    if games == 0 and not noRep then
        rateDate = now
    elseif noRep then
        rateLimit = "norep"
    elseif gpd > 0 then
        rateDate = now + math.floor(games / gpd * DAY)
        rateLimit = rateLimitOverride or (detail.marksGames >= detail.honorGames and "marks" or "honor")
    else
        rateLimit = "nopace"
    end

    local rankDate, rankLimit
    if rankRow and not rankRow.met and rankRow.known then
        local plan = rankRow.plan
        rankDate = plan and plan.date or nil
        rankLimit = plan and plan.limitedBy or nil
        if rankLimit == "cap" then rankLimit = "cap" elseif rankLimit == "pace" then rankLimit = "rank" end
    end

    local readyDate, limitedBy
    local rankUnmet = rankRow and rankRow.known and not rankRow.met
    if rankUnmet and not rankDate then
        -- no date: the level gate, a pace of 0 rank points, or the season ends first
        limitedBy = (rankLimit == "level" or rankLimit == "nopoints") and rankLimit or "season"
    elseif rateLimit == "norep" then
        limitedBy = "norep" -- no game has measured the reputation rate yet
    elseif rateLimit == "nopace" then
        limitedBy = "nopace" -- no recent games to measure a rate from
    elseif rankUnmet and rankDate > rateDate then
        readyDate, limitedBy = rankDate, rankLimit
    else
        readyDate, limitedBy = rateDate, rateLimit or "ready"
    end
    return readyDate, limitedBy, games, detail.estimated or (ctx.pace and ctx.pace.estimated) or false
end

-- pool = nil: progress against everything the player holds. pool = table: waterfall, the goal takes what is
-- left in the pool and the pool tracks the shortfall of the goals above (for the date).
function HonorLog:BuildGoalProgress(itemID, ctx, pool)
    local item = self:GetGearItem(itemID)
    if not item then return nil end

    -- What is still to buy. An epic is two purchases: its blue piece and the Seal; a part in the bags or
    -- worn is paid for.
    local need = { honor = item.honor or 0, gold = item.gold or 0, marks = {} }
    for bgType, count in pairs(item.marks or {}) do need.marks[bgType] = count end
    local rankNeeded = item.rank
    local levelNeeded = item.reqLevel
    local parts
    if item.source == "UPGRADE" and type(item.parts) == "table" then
        local list = {}
        for i, partID in ipairs(item.parts) do
            local part = self:GetGearItem(partID)
            if part then
                list[#list + 1] = {
                    itemID = partID, name = part.name, role = i == 1 and "blue" or "seal",
                    owned = self:IsItemInInventory(partID), honor = part.honor or 0, gold = part.gold or 0,
                    marks = part.marks, rank = part.rank, scanned = part.scanned, reqLevel = part.reqLevel,
                }
            end
        end
        if #list > 0 then
            parts = list
            need = { honor = 0, gold = 0, marks = {} }
            rankNeeded, levelNeeded = nil, nil -- each part still to buy names its own
            for _, part in ipairs(list) do
                if not part.owned then
                    levelNeeded = math.max(levelNeeded or 0, part.reqLevel or 0)
                    need.honor = need.honor + part.honor
                    need.gold = need.gold + part.gold
                    for bgType, count in pairs(part.marks or {}) do
                        need.marks[bgType] = (need.marks[bgType] or 0) + count
                    end
                    if part.rank then rankNeeded = math.max(rankNeeded or 0, part.rank) end
                end
            end
        end
    end

    local result = {
        itemID = itemID, name = item.name, slot = item.slot, item = item, source = item.source,
        parts = parts, marks = {}, rows = {}, missing = {}, unverified = {},
        isComplete = true, totalGamesNeeded = 0, scanned = item.scanned, unconfirmed = item.unconfirmed,
    }
    local function addRow(row)
        row.remaining = math.max(0, row.needed - (row.current or 0))
        row.percent = row.needed > 0 and math.min(100, (row.current or 0) / row.needed * 100) or 100
        if row.met == nil then row.met = row.remaining <= 0 end
        result.rows[#result.rows + 1] = row
        if row.known == false then
            result.unverified[#result.unverified + 1] = row
        elseif not row.met then
            result.missing[#result.missing + 1] = row
            result.isComplete = false
        end
        return row
    end
    local function take(kind, bgType, needed)
        local have
        if kind == "honor" then have = ctx.honor elseif kind == "gold" then have = ctx.money else have = ctx.marks[bgType] or 0 end
        if not pool then return have end
        local left = pool[kind == "marks" and ("m" .. bgType) or kind]
        if left == nil then left = have end
        local allocated = math.min(left, needed)
        pool[kind == "marks" and ("m" .. bgType) or kind] = left - allocated
        return allocated
    end

    -- Honor
    result.honor = addRow({ kind = "honor", needed = need.honor, current = take("honor", nil, need.honor),
        cap = ctx.cap, overCap = ctx.cap and need.honor > ctx.cap or false })
    -- Marks
    for _, bgType in ipairs(self.BG_ORDER or {}) do
        local needed = need.marks[bgType]
        if needed and needed > 0 then
            result.marks[bgType] = addRow({ kind = "marks", bg = bgType, needed = needed, current = take("marks", bgType, needed) })
        end
    end
    -- Gold
    result.gold = addRow({ kind = "gold", needed = need.gold, current = take("gold", nil, need.gold) })

    -- Level: shown only while unmet. An unmet level means no ready date.
    local levelRow
    if levelNeeded and levelNeeded > 1 then
        levelRow = addRow({ kind = "level", needed = levelNeeded, current = ctx.level, known = ctx.level ~= nil })
        result.level = levelRow
    end

    -- Rank
    local rankRow
    if rankNeeded and rankNeeded > 0 then
        local current = ctx.info and ctx.info.rank or nil
        rankRow = { kind = "rank", needed = rankNeeded, current = current, known = current ~= nil,
            met = current ~= nil and current >= rankNeeded }
        if current == nil then rankRow.met = false end
        if rankRow.known and not rankRow.met and self.Rank then
            local plan = ctx.plans[rankNeeded]
            if not plan then
                plan = self.Rank:PlanToRank(rankNeeded, ctx.info, ctx.pace)
                ctx.plans[rankNeeded] = plan or false
            end
            if plan then
                rankRow.plan, rankRow.date, rankRow.limitedBy = plan, plan.date, plan.limitedBy
                rankRow.week = plan.earliestWeekByCap
            end
        end
        -- rank rows keep their own meaning of remaining: ranks to climb
        local row = rankRow
        row.remaining = math.max(0, rankNeeded - (current or 0))
        row.percent = rankNeeded > 0 and math.min(100, (current or 0) / rankNeeded * 100) or 100
        result.rows[#result.rows + 1] = row
        if not row.met then
            result.missing[#result.missing + 1] = row
            result.isComplete = false
        end
        result.rank = row
    end

    -- Reputation: the standing needed, with progress only when the item names one faction. current is
    -- the standing id; amount and ceiling are the reputation into that standing and its span.
    local repRow
    local rep = item.rep
    if rep and rep.standing then
        local row = { kind = "rep", needed = rep.standing, faction = rep.faction, standingName = HonorLog.STANDING_NAMES[rep.standing] }
        if rep.faction then
            row.factionName = self.REP_FACTIONS and self.REP_FACTIONS[rep.faction]
            local progress = self:GetReputationProgress(rep.faction)
            row.current = progress and progress.standing or nil
            row.known = row.current ~= nil
            row.met = row.known and row.current >= rep.standing
            if row.known and progress.current and progress.floor and progress.ceiling and progress.ceiling > progress.floor then
                row.amount = math.max(0, progress.current - progress.floor)
                row.ceiling = progress.ceiling - progress.floor
            end
            if row.known and not row.met then
                row.remainingRep = self:ReputationRemaining(row.current, row.amount, rep.standing)
                row.perGame = self:GetRepPerGame(rep.faction)
                row.repBG = BG_OF_REP_FACTION[rep.faction]
                if row.perGame and row.perGame > 0 then
                    row.games = math.ceil(row.remainingRep / row.perGame)
                end
            end
        else
            row.known = false -- several factions qualify: shown as a requirement, never as progress
            row.met = false
        end
        row.remaining = row.met and 0 or 1
        row.percent = row.met and 100 or 0
        result.rows[#result.rows + 1] = row
        if row.known == false then
            result.unverified[#result.unverified + 1] = row
        elseif not row.met then
            result.missing[#result.missing + 1] = row
            result.isComplete = false
        end
        result.rep = row
        repRow = row
    end

    -- Per-requirement games, for the old "games" labels
    local avgHonor = self:GetAverageHonorPerGame()
    if result.honor.remaining > 0 and avgHonor > 0 then result.honor.games = math.ceil(result.honor.remaining / avgHonor) else result.honor.games = 0 end
    for bgType, row in pairs(result.marks) do
        local avg = self:GetAverageMarksPerGame(bgType)
        row.games = (row.remaining > 0 and avg > 0) and math.ceil(row.remaining / avg) or 0
    end

    -- The date. A waterfall goal waits for the shortfall of the goals above it too.
    local honorMissing, marksMissing = result.honor.remaining, {}
    for bgType, row in pairs(result.marks) do marksMissing[bgType] = row.remaining end
    if pool then
        pool.shortHonor = (pool.shortHonor or 0) + honorMissing
        pool.shortMarks = pool.shortMarks or {}
        for bgType, missing in pairs(marksMissing) do
            pool.shortMarks[bgType] = (pool.shortMarks[bgType] or 0) + missing
        end
        honorMissing, marksMissing = pool.shortHonor, pool.shortMarks
    end
    result.readyDate, result.readyLimitedBy, result.totalGamesNeeded, result.estimated =
        ReadyEstimate(self, ctx, honorMissing, marksMissing, rankRow, repRow)
    if result.readyLimitedBy == "norep" and repRow then
        local bgName = repRow.repBG and self:GetBGDisplayName(repRow.repBG) or L["battleground"]
        result.readyText = string.format(L["play %s once to measure reputation"], bgName)
    end
    if levelRow and levelRow.known and not levelRow.met then
        result.readyDate, result.readyLimitedBy = nil, "level"
    end
    if result.isComplete then
        result.readyDate, result.readyLimitedBy = ctx.now, "ready"
    elseif #result.missing > 0 then
        -- Only gold or reputation left: they have no rate, so the date is today, named for what holds it.
        local rateOnly = true
        for _, row in ipairs(result.missing) do
            if row.kind ~= "gold" and row.kind ~= "rep" then rateOnly = false end
        end
        if rateOnly and result.readyLimitedBy == "ready" then
            result.readyLimitedBy = result.missing[1].kind
        end
    end
    return result
end

function HonorLog:GetGoalProgress(itemID)
    return self:BuildGoalProgress(itemID, NewContext(self), nil)
end

-- Get all goals with progress
function HonorLog:GetAllGoalsProgress()
    local progressMode = self.db.settings.goalProgressMode or "shared"
    if progressMode == "waterfall" then
        return self:GetAllGoalsProgressWaterfall()
    end

    local ctx = NewContext(self)
    local results = {}
    for _, goal in ipairs(self.db.char.goals.items) do
        local progress = self:BuildGoalProgress(goal.itemID, ctx, nil)
        if progress then
            progress.addedAt = goal.addedAt
            progress.priority = goal.priority
            table.insert(results, progress)
        end
    end
    return results
end

-- Currency fills goals top to bottom: honor, marks and gold go to the first goal that needs them.
function HonorLog:GetAllGoalsProgressWaterfall()
    local ctx = NewContext(self)
    local pool = {}
    local results = {}
    for _, goal in ipairs(self.db.char.goals.items) do
        local progress = self:BuildGoalProgress(goal.itemID, ctx, pool)
        if progress then
            progress.addedAt = goal.addedAt
            progress.priority = goal.priority
            table.insert(results, progress)
        end
    end
    return results
end

-- One roll-up of every goal, active and completed, for the totals bar and the compact view.
function HonorLog:GetGoalsTotals(goals)
    goals = goals or self:GetAllGoalsProgress()
    local ctx = NewContext(self)
    local T = { honorNeeded = 0, goldNeeded = 0, marksNeeded = {}, marksCurrent = {}, completed = { honor = 0, gold = 0, marks = {} } }
    local lastDate, limited
    for _, goal in ipairs(goals) do
        T.honorNeeded = T.honorNeeded + goal.honor.needed
        T.goldNeeded = T.goldNeeded + goal.gold.needed
        for bgType, row in pairs(goal.marks) do
            T.marksNeeded[bgType] = (T.marksNeeded[bgType] or 0) + row.needed
        end
        if goal.readyDate and (not lastDate or goal.readyDate > lastDate) then lastDate, limited = goal.readyDate, goal.readyLimitedBy end
    end
    T.honorCurrent = math.min(ctx.honor, T.honorNeeded)
    T.goldCurrent = math.min(ctx.money, T.goldNeeded)
    for bgType, needed in pairs(T.marksNeeded) do
        T.marksCurrent[bgType] = math.min(ctx.marks[bgType] or 0, needed)
    end
    for _, done in ipairs(self:GetCompletedGoals()) do
        local item = self:GetGearItem(done.itemID)
        if item then
            T.completed.honor = T.completed.honor + (item.honor or 0)
            T.completed.gold = T.completed.gold + (item.gold or 0)
            for bgType, count in pairs(item.marks or {}) do
                T.completed.marks[bgType] = (T.completed.marks[bgType] or 0) + count
            end
        end
    end
    -- Weighted: a mark counts 100 honor, a gold piece 10.
    local needed = T.honorNeeded + T.goldNeeded / 1000
    local current = T.honorCurrent + T.goldCurrent / 1000
    for bgType, n in pairs(T.marksNeeded) do
        needed = needed + n * 100
        current = current + (T.marksCurrent[bgType] or 0) * 100
    end
    needed = needed + T.completed.honor + T.completed.gold / 1000
    current = current + T.completed.honor + T.completed.gold / 1000
    for _, n in pairs(T.completed.marks) do
        needed = needed + n * 100
        current = current + n * 100
    end
    T.percent = needed > 0 and current / needed * 100 or 100
    T.allComplete = true
    for _, goal in ipairs(goals) do if not goal.isComplete then T.allComplete = false end end
    if not T.allComplete then T.percent = math.min(T.percent, 99) end -- rank or reputation can still be short
    -- Games for everything together: the shortfall of the whole list, not the sum of each goal's.
    local marksMissing = {}
    for bgType, n in pairs(T.marksNeeded) do marksMissing[bgType] = math.max(0, n - (T.marksCurrent[bgType] or 0)) end
    T.games = self:EstimateGames(math.max(0, T.honorNeeded - T.honorCurrent), marksMissing)
    T.readyDate, T.readyLimitedBy = lastDate, limited
    return T
end

local CAP_ADVICE_GAMES = 20 -- the cap advice also fires when the cap is this many games away

-- What the character could buy this minute: level, rank, reputation, faction and class met, honor,
-- marks and gold in hand, not owned. Most expensive first, at most `limit` entries of
-- { itemID, name, honor, marks, gold }. Epics (two purchases) and consumables are left out.
function HonorLog:GetBuyableNow(limit)
    local ctx = NewContext(self)
    local _, class = UnitClass("player")
    local list = {}
    for _, entry in ipairs(self:GetPickerItems({ class = Util.str(class), hideOwned = true })) do
        local base = entry.data
        local item = base.source ~= "UPGRADE" and base.slot ~= "CONSUMABLE" and self:GetGearItem(entry.itemID) or nil
        local ok = item ~= nil
        if ok and (item.reqLevel or 0) > 1 then ok = ctx.level ~= nil and ctx.level >= item.reqLevel end
        if ok and item.rank then ok = ctx.info ~= nil and ctx.info.rank ~= nil and ctx.info.rank >= item.rank end
        if ok and item.rep and item.rep.standing then
            local standing = item.rep.faction and self:GetReputationStanding(item.rep.faction)
            ok = standing ~= nil and standing >= item.rep.standing
        end
        if ok then ok = (item.honor or 0) <= ctx.honor and (item.gold or 0) <= ctx.money end
        if ok then
            for bgType, count in pairs(item.marks or {}) do
                if (ctx.marks[bgType] or 0) < count then ok = false end
            end
        end
        if ok then
            local weight = (item.honor or 0) + (item.gold or 0) / 1000
            for _, count in pairs(item.marks or {}) do weight = weight + count * 100 end
            list[#list + 1] = { itemID = entry.itemID, name = item.name, honor = item.honor or 0, marks = item.marks,
                gold = item.gold or 0, weight = weight }
        end
    end
    table.sort(list, function(a, b)
        if a.weight ~= b.weight then return a.weight > b.weight end
        if (a.name or "") ~= (b.name or "") then return (a.name or "") < (b.name or "") end
        return a.itemID < b.itemID
    end)
    local out = {}
    for i = 1, math.min(limit or 3, #list) do out[i] = list[i] end
    return out
end

-- True when every goal waits on level, rank or reputation (and none is ready). Second result: the
-- lowest level the goals wait for when every goal waits on a level, else nil.
local function GoalsBlockedByGate(goals)
    if #goals == 0 then return false end
    local allLevel, lowest = true, nil
    for _, goal in ipairs(goals) do
        if goal.isComplete then return false end
        local gated, levelGated = false, false
        for _, row in ipairs(goal.missing) do
            if row.kind == "level" then
                gated, levelGated = true, true
                lowest = math.min(lowest or row.needed, row.needed)
            elseif row.kind == "rank" or row.kind == "rep" then
                gated = true
            end
        end
        if not gated then return false end
        if not levelGated then allLevel = false end
    end
    return true, allLevel and lowest or nil
end

local function GamesPhrase(n)
    return string.format(n == 1 and L["%d game"] or L["%d games"], n)
end

-- The "you will cap with nothing to buy" sentence.
local function BlockedCapText(cap, gamesToCap, level)
    local capText = BreakUpLargeNumbers(cap)
    if gamesToCap == nil then
        if level then return string.format(L["You are near the %s honor cap and nothing on your list can be bought before level %d."], capText, level) end
        return string.format(L["You are near the %s honor cap and nothing on your list can be bought yet because of level, rank or reputation."], capText)
    elseif gamesToCap == 0 then
        if level then return string.format(L["You are at the %s honor cap and nothing on your list can be bought before level %d."], capText, level) end
        return string.format(L["You are at the %s honor cap and nothing on your list can be bought yet because of level, rank or reputation."], capText)
    end
    if level then
        return string.format(L["You'll reach the %s honor cap in about %s and nothing on your list can be bought before level %d."], capText, GamesPhrase(gamesToCap), level)
    end
    return string.format(L["You'll reach the %s honor cap in about %s and nothing on your list can be bought yet because of level, rank or reputation."], capText, GamesPhrase(gamesToCap))
end

-- "Spend before you cap": honor that the next game would push past the cap (or already sits at the
-- warning percentage), and the first goal that can be bought now. When every goal waits on level,
-- rank or reputation and the cap is near (or within 20 games at the measured honor per game), the
-- advice says so and lists up to three things the character could buy right now (advice.buyable).
function HonorLog:GetHonorCapAdvice(goals)
    local settings = self.db and self.db.settings
    if not settings or settings.honorCapWarning == false or settings.goalCapAdvice == false then return nil end
    local cap = self:GetHonorCap()
    if not cap then return nil end
    local current = self:GetCurrentHonor()
    local expected = self:GetAverageHonorPerGame()
    local pct = settings.honorCapWarnPct or 90
    local near = not (current + expected <= cap and current < cap * pct / 100)
    local gamesToCap
    if current >= cap then
        gamesToCap = 0
    elseif expected > 0 then
        gamesToCap = math.ceil((cap - current) / expected)
    end
    local soon = gamesToCap ~= nil and gamesToCap <= CAP_ADVICE_GAMES
    if not near and not soon then return nil end

    goals = goals or self:GetAllGoalsProgress()
    local advice = { current = current, cap = cap, expected = expected, gamesToCap = gamesToCap, text = "spend before you cap" }

    local blocked, level = GoalsBlockedByGate(goals)
    if blocked then
        advice.blocked = true
        advice.text = BlockedCapText(cap, gamesToCap, level)
        advice.buyable = self:GetBuyableNow(3)
        return advice
    end
    if not near then return nil end

    for _, goal in ipairs(goals) do
        if goal.isComplete then advice.goal = goal break end
    end
    if not advice.goal then
        for _, goal in ipairs(goals) do
            if goal.honor.needed > 0 and not goal.honor.overCap and goal.honor.remaining <= 0 then advice.goal, advice.partial = goal, true break end
        end
    end
    if advice.goal then
        advice.text = "spend before you cap: " .. tostring(advice.goal.name)
    end
    return advice
end

-- Saved goals that name an item the Forever database does not know (TBC items) are set aside.
function HonorLog:ArchiveUnknownGoals()
    local char = HonorLogCharDB
    if type(char) ~= "table" or type(char.goals) ~= "table" or not self.GearDB then return 0 end
    char.goalsLegacy = char.goalsLegacy or {}
    local moved = 0
    for _, list in ipairs({ char.goals.items or {}, char.goals.completed or {} }) do
        for i = #list, 1, -1 do
            local goal = list[i]
            if type(goal) ~= "table" or not goal.itemID or not self.GearDB[goal.itemID] then
                table.insert(char.goalsLegacy, table.remove(list, i))
                moved = moved + 1
            end
        end
    end
    for i, goal in ipairs(char.goals.items or {}) do goal.priority = i end
    if moved > 0 then
        print(string.format("|cff40d860[HonorLog]|r %d TBC goals archived", moved))
    end
    return moved
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
