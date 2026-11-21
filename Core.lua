-- HonorLog Core
-- Event handling, match lifecycle, world PvP and honor tracking.
--
-- Everything here reads Forever's own signals and measures instead of assuming:
--   * a battleground game is snapshotted on entry (honor, marks, rank progress)
--     and diffed at the end; honor is also summed from CURRENCY_DISPLAY_UPDATE;
--   * the result comes from PVP_MATCH_COMPLETE, with the winner APIs and the BG
--     chat text as fallbacks;
--   * the scoreboard is secret during a match, so it is re-read after the match
--     until every number is readable (or 12 s pass);
--   * world kills come from the honorable-kill counter plus the honor message,
--     deaths from the death recap. The combat log is restricted and never used.
-- Rule for every value that may be secret: check issecretvalue() before it is
-- compared, added, concatenated, indexed or stored (see Modules/Probe.lua).

local ADDON_NAME, HonorLog = ...

-- Forever-safe wrappers (defined in Data.lua)
local Compat = HonorLog.Compat
local GetItemInfo = Compat.GetItemInfo
local GetItemCount = Compat.GetItemCount
local GetNumBattlefieldScores = Compat.GetNumBattlefieldScores

local HONOR_CURRENCY = 1792
local RANK_FACTION = 2800
-- Points to finish each rank (curve 103650), used when a game crosses a rank.
local RANK_CURVE = { 750, 900, 1050, 1200, 1350, 1500, 1650, 1800, 1950, 2100, 2350, 2500, 2650, 3000 }

local RECORD_DELAY = 20    -- seconds after PVP_MATCH_COMPLETE the game is recorded (bonus honor lands first)
local SB_GIVEUP = 12       -- seconds the scoreboard is chased before the game is recorded without it
local SB_REREAD = 2        -- seconds after an accepted read the board is read again for a fuller roster
local SB_POLL = 1          -- seconds between scoreboard requests while it is unreadable
local JOINED_LATE = 60     -- a match already running this long on entry counts as joined in progress
local KILL_WINDOW = 2      -- seconds within which a kill counter step and its honor message belong together
local CREDIT_WINDOW = 60   -- a dead enemy is credited for at most one kill in this time

-- State
local match = nil          -- the battleground game in progress (also saved as bgState.match)
local debugMode = false
local lastHK = nil         -- honorable kills the client reported at the last check
local pendingHK = {}       -- kill counter steps not yet matched: { t = GetTime() }
local pendingMsgs = {}     -- kill honor messages not yet matched: { name, rank, honor, t }
local pendingParty = {}    -- PARTY_KILL records with readable GUIDs: { t, name, class }
local credited = {}        -- enemy name -> GetTime() of the kill it was credited for
local deathToken = 0

-- Create main frame for events
local eventFrame = CreateFrame("Frame", "HonorLogEventFrame")
HonorLog.eventFrame = eventFrame

-- Safe initialization wrapper with error boundary
local function SafeInit(name, func)
    local success, err = pcall(func)
    if not success then
        print("|cffff0000[HonorLog ERROR]|r Failed to initialize " .. name .. ": " .. tostring(err))
        return false
    end
    return true
end

local function dbg(...)
    if debugMode then print("|cffff00ff[HonorLog Debug]|r", ...) end
end

--------------------------------------------------------------------------------
-- Secret-safe readers
--------------------------------------------------------------------------------

local Util = HonorLog.Util
local isSecret, num, str, call = Util.isSecret, Util.num, Util.str, Util.call
local L = HonorLog.L

local function pvp(name, ...)
    if not C_PvP then return end
    return call(C_PvP[name], ...)
end

-- Event handler
local function OnEvent(self, event, ...)
    if HonorLog[event] then
        HonorLog[event](HonorLog, ...)
    end
end

eventFrame:SetScript("OnEvent", OnEvent)

-- Register events
local events = {
    "ADDON_LOADED",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_LEAVING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "UPDATE_BATTLEFIELD_STATUS",
    "UPDATE_BATTLEFIELD_SCORE",
    "PVP_MATCH_ACTIVE",
    "PVP_MATCH_COMPLETE",
    "CHAT_MSG_BG_SYSTEM_ALLIANCE",
    "CHAT_MSG_BG_SYSTEM_HORDE",
    "CHAT_MSG_BG_SYSTEM_NEUTRAL",
    "CHAT_MSG_RAID_BOSS_EMOTE",
    "CHAT_MSG_MONSTER_YELL",
    "CHAT_MSG_COMBAT_HONOR_GAIN",
    "PLAYER_LOGOUT",
    "PLAYER_DEAD",
    "PLAYER_PVP_KILLS_CHANGED",
    "PARTY_KILL",
    "CURRENCY_DISPLAY_UPDATE",
    "BAG_UPDATE_DELAYED",
    "BAG_UPDATE", -- For detecting acquired goal items
    "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", -- rank gained (faction 2800)
    "PLAYER_LEVEL_UP", -- the level gate on rank 4 and above
    "PLAYER_PVP_RANK_CHANGED",
    "UPDATE_FACTION",
    "MERCHANT_SHOW", -- automatic PvP vendor price scan
    -- COMBAT_LOG_EVENT_UNFILTERED is deliberately not registered: the Forever
    -- docs flag it HasRestrictions and registering it raises the "blocked"
    -- popup. Kills and deaths come from the signals above instead.
}

-- Registering an event the client does not know raises an error, so a miss
-- must never abort the load.
for _, event in ipairs(events) do
    pcall(eventFrame.RegisterEvent, eventFrame, event)
end

--------------------------------------------------------------------------------
-- Match state persistence (survives /reload)
--------------------------------------------------------------------------------

local function SaveBGState()
    if not (HonorLog.db and HonorLog.db.char) then return end
    if match then
        HonorLog.db.char.bgState = { isInBG = true, currentBG = match.bgType, match = match }
    else
        HonorLog.db.char.bgState = { isInBG = false }
    end
end

local ArmFinish, PollScoreboard, FinalizeMatch -- defined below

-- Restore after /reload (called from ADDON_LOADED when a reload is detected).
function HonorLog:RestoreBGState()
    local state = self.db.char.bgState
    if not (state and state.isInBG and type(state.match) == "table" and state.match.bgType) then return end
    match = state.match
    if match.recorded then return end
    -- The timers died with the old UI; re-arm what the game still needs.
    if match.completed then
        local elapsed = GetTime() - (match.completedAt or GetTime())
        ArmFinish(match, math.max(0.1, RECORD_DELAY - elapsed))
        if match.sbState == "pending" then PollScoreboard(match) end
    end
    dbg("Restored BG state:", match.bgType, "honor", match.honorGained)
end

-- Addon loaded
function HonorLog:ADDON_LOADED(addon)
    if addon ~= ADDON_NAME then return end

    -- Initialize database (this also detects reload vs fresh login)
    self:InitializeDB()

    -- Restore the game in progress if this is a reload inside a battleground
    if self.isReload and self.db.char.bgState and self.db.char.bgState.isInBG then
        self:RestoreBGState()
    end

    -- Initialize UI with error boundaries
    local uiOK = SafeInit("MainFrame", function() self:InitializeMainFrame() end)
    if uiOK then
        SafeInit("GoalsUI", function() self:InitializeGoalsUI() end)
        SafeInit("RankUI", function() self:InitializeRankUI() end)
    end
    SafeInit("Options", function() self:InitializeOptions() end)
    SafeInit("LDB", function() self:InitializeLDB() end)
    SafeInit("Probe", function() if self.Probe then self.Probe:Init() end end)

    -- Register slash commands (always works even if UI fails)
    self:RegisterSlashCommands()

    -- Unregister this event
    eventFrame:UnregisterEvent("ADDON_LOADED")

    print("|cff00ff00HonorLog|r loaded. Type |cffffffff/honorlog|r or |cffffffff/hl|r for options.")
end

--------------------------------------------------------------------------------
-- Snapshot readers
--------------------------------------------------------------------------------

-- Honor from the currency itself (nil when the API cannot say).
local function ReadHonor()
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
    local info = call(C_CurrencyInfo.GetCurrencyInfo, HONOR_CURRENCY)
    if type(info) ~= "table" then return nil end
    return num(info.quantity)
end

-- The honor cap, from the currency itself (never a fixed number); nil when the client does not say.
local function ReadHonorCap()
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
    local info = call(C_CurrencyInfo.GetCurrencyInfo, HONOR_CURRENCY)
    if type(info) ~= "table" then return nil end
    local cap = num(info.maxQuantity)
    if cap and cap > 0 then return cap end
end

-- { level, earned, threshold, capRank, capTotal, total } of the PvP rank faction, or nil. capRank and
-- capTotal are this week's cap (0 when the client names none); total is every point earned so far.
local function ReadRank()
    if not (C_MajorFactions and C_MajorFactions.GetMajorFactionProgressionInfo) then return nil end
    local info = call(C_MajorFactions.GetMajorFactionProgressionInfo, RANK_FACTION)
    if type(info) ~= "table" then return nil end
    local level, earned = num(info.renownLevel), num(info.renownReputationEarned)
    if not level or not earned then return nil end
    local capRank = num(info.currentWeekProgressiveMaxLevel) or 0
    local rank = HonorLog.Rank
    local total = rank and rank.TotalForRank and (rank:TotalForRank(level) + earned) or earned
    local capTotal = (rank and rank.TotalForRank and capRank > 0) and rank:TotalForRank(capRank) or 0
    return { level = level, earned = earned, threshold = num(info.renownLevelThreshold),
             capRank = capRank, capTotal = capTotal, total = total }
end

-- Rank points earned between two reads. Reaching rank n costs the first n curve entries, so the
-- level a player is on (level L) is worth curve[L + 1] points. A level-up adds the rest of the old
-- level, every level skipped, and the progress into the new one; the rank module's totals say it in one line.
local function RankDelta(from, to)
    if not from or not to then return 0 end
    if to.level == from.level then return math.max(0, to.earned - from.earned) end
    if to.level < from.level then return 0 end
    local rank = HonorLog.Rank
    if rank and rank.TotalForRank then
        return math.max(0, rank:TotalForRank(to.level) + to.earned - rank:TotalForRank(from.level) - from.earned)
    end
    local function threshold(level) return RANK_CURVE[level + 1] or 0 end
    local total = math.max(0, (from.threshold or threshold(from.level)) - from.earned)
    for level = from.level + 1, to.level - 1 do
        total = total + threshold(level)
    end
    return total + to.earned
end
HonorLog.RankDelta = RankDelta

-- Mark counts for every battleground that has a mark item.
local function ReadMarks()
    local marks = {}
    for bgType, itemID in pairs(HonorLog.BG_MARK_ITEMS or {}) do
        marks[bgType] = Compat.GetItemCount(itemID) or 0
    end
    return marks
end

-- Reputation with the battleground's own faction: { faction, amount } (the client's absolute number),
-- or nil when the battleground has no faction or the client will not say. A faction not met yet
-- reads as 0, the start of Neutral.
local function ReadRep(bgType)
    local faction = bgType and HonorLog:GetBGRepFaction(bgType)
    if not faction then return nil end
    local progress = HonorLog:GetReputationProgress(faction)
    if not progress then return nil end
    local amount = progress.current
    if amount == nil and progress.standing == 0 then amount = 0 end
    return { faction = faction, amount = amount }
end

local function TakeSnapshot(bgType)
    return { honor = ReadHonor(), honorCap = ReadHonorCap(), marks = ReadMarks(), rank = ReadRank(),
             level = num(call(UnitLevel, "player")), rep = ReadRep(bgType), t = time() }
end

-- Mark counts gained since the snapshot (can be negative when marks are spent).
local function UpdateMarks(m)
    if not m.snapshot then return end
    m.marks = m.marks or {}
    for bgType, count in pairs(ReadMarks()) do
        m.marks[bgType] = count - ((m.snapshot.marks and m.snapshot.marks[bgType]) or 0)
    end
end

--------------------------------------------------------------------------------
-- Battleground detection and entry / exit
--------------------------------------------------------------------------------

-- Returns bgType, mapID, name for the current instance when it is a battleground.
function HonorLog:DetectBattleground()
    local name, instanceType, _, _, _, _, _, mapID = GetInstanceInfo()
    if instanceType ~= "pvp" then return nil end
    local bgType = self:GetBGTypeForMap(mapID, name, instanceType)
    if debugMode then dbg("Instance:", tostring(name), "map", tostring(mapID), "->", tostring(bgType)) end
    return bgType, mapID, name
end

local function InPvPInstance()
    if match then return true end
    local _, instanceType = GetInstanceInfo()
    return instanceType == "pvp"
end

-- Player entering world (includes BG zone-ins)
function HonorLog:PLAYER_ENTERING_WORLD()
    self:CheckBattlegroundStatus()
    lastHK = lastHK or call(GetPVPSessionStats)
    if not num(lastHK) then lastHK = nil end
    self:CheckHonorCap()
    self:RefreshRank()

    -- Delayed scan for acquired goal items (bags may not be ready immediately)
    C_Timer.After(2, function()
        if HonorLog.ScanGoalsForAcquiredItems then
            local acquired = HonorLog:ScanGoalsForAcquiredItems()
            if acquired > 0 then
                HonorLog:UpdateGoalsPanel()
            end
        end
    end)
end

-- Rank data refresh (the Rank module owns the logic).
function HonorLog:RefreshRank()
    if self.Rank then self.Rank:Refresh() end
end

-- A level-up can move the level gate. The client may still report the old level while the event runs,
-- so the new one is passed along, and the rank is read again a moment later from the client itself.
function HonorLog:PLAYER_LEVEL_UP(newLevel)
    self.levelHint = num(newLevel)
    self:RefreshRank()
    self.levelHint = nil
    C_Timer.After(1, function() HonorLog:RefreshRank() end)
end

function HonorLog:MAJOR_FACTION_RENOWN_LEVEL_CHANGED(factionID, newLevel, oldLevel)
    if self.Rank then self.Rank:OnRenownChanged(factionID, newLevel, oldLevel) end
end

function HonorLog:PLAYER_PVP_RANK_CHANGED(unitTarget)
    if unitTarget ~= nil and not isSecret(unitTarget) and unitTarget ~= "player" then return end
    self:RefreshRank()
end

-- A vendor opened: let the scanner decide whether it sells PvP gear. A short delay lets the
-- merchant frame fill in its item links first.
function HonorLog:MERCHANT_SHOW()
    if self.Probe and self.Probe.LogMerchantRead then self.Probe:LogMerchantRead(self:ReadVendorLocation()) end
    C_Timer.After(0.3, function() self:AutoScanVendor() end)
end

function HonorLog:UPDATE_FACTION()
    self:RefreshRank()
end

function HonorLog:ZONE_CHANGED_NEW_AREA()
    self:CheckBattlegroundStatus()
end

function HonorLog:UPDATE_BATTLEFIELD_STATUS()
    self:CheckBattlegroundStatus()
end

-- Check and update BG status
function HonorLog:CheckBattlegroundStatus()
    local bg, mapID, name = self:DetectBattleground()

    if bg and not match then
        self:OnBattlegroundEnter(bg, mapID, name)
    elseif not bg and match then
        self:OnBattlegroundLeave()
    elseif bg and match and bg ~= match.bgType then
        self:OnBattlegroundLeave()
        self:OnBattlegroundEnter(bg, mapID, name)
    end
end

-- Joined in progress: the match was already active and had run more than a minute.
local function EvaluateJoin(m)
    if m.joinChecked then return end
    if pvp("IsMatchActive") ~= true then return end
    local elapsed = num(pvp("GetActiveMatchDuration"))
    if not elapsed then return end
    m.joinChecked = true
    m.joinedInProgress = elapsed > JOINED_LATE or nil
    dbg("Join check: match running", elapsed, "s, joined in progress:", tostring(m.joinedInProgress))
end

-- Entering battleground
function HonorLog:OnBattlegroundEnter(bgType, mapID, name)
    match = {
        bgType = bgType, mapID = mapID, name = name,
        startTime = GetTime(), startStamp = time(),
        snapshot = TakeSnapshot(bgType),
        honorGained = 0,
        marks = {},
    }
    EvaluateJoin(match)

    -- Start session timer on first BG entry (so hourly rate only counts BG time)
    if self.db and self.db.char and (not self.db.char.sessionStartTime or self.db.char.sessionStartTime == 0) then
        self.db.char.sessionStartTime = time()
    end

    lastHK = call(GetPVPSessionStats) -- kills inside the battleground are not world kills
    if not num(lastHK) then lastHK = nil end

    if self.UpdateMainFrame then self:UpdateMainFrame() end
    print("|cff00ff00[HonorLog]|r Entered " .. self:GetBGDisplayName(bgType) .. " - tracking started")
    dbg("BG entry:", bgType, "snapshot honor", tostring(match.snapshot.honor))
    SaveBGState()
end

-- Leaving battleground: a game still unrecorded is recorded now.
function HonorLog:OnBattlegroundLeave()
    dbg("OnBattlegroundLeave, match:", tostring(match and match.bgType))
    if match and not match.recorded then
        FinalizeMatch("left")
    end
    match = nil
    lastHK = call(GetPVPSessionStats)
    if not num(lastHK) then lastHK = nil end
    SaveBGState()
    if self.UpdateMainFrame then self:UpdateMainFrame() end
end

function HonorLog:PVP_MATCH_ACTIVE()
    if match then EvaluateJoin(match) end
end

--------------------------------------------------------------------------------
-- Result
--------------------------------------------------------------------------------

-- The player's team: 0 Horde, 1 Alliance. Blizzard's own call first (it is right
-- for cross-faction groups), then the scoreboard line, then the character's faction.
local function MyTeam()
    local team = num(call(GetBattlefieldArenaFaction))
    if team == 0 or team == 1 then return team, "arena" end
    if match and match.sb and match.sb.me and (match.sb.me.faction == 0 or match.sb.me.faction == 1) then
        return match.sb.me.faction, "board"
    end
    local faction = call(UnitFactionGroup, "player")
    if faction == "Horde" then return 0, "faction" end
    if faction == "Alliance" then return 1, "faction" end
    return nil
end

-- The winner is 0 Horde, 1 Alliance or 255 for a draw.
local function ResolveResult(winner)
    if winner == 255 then return "draw", "arena" end
    if winner ~= 0 and winner ~= 1 then return nil end
    local team, source = MyTeam()
    if team == nil then return nil end
    return (winner == team) and "win" or "loss", source
end

-- Winner when PVP_MATCH_COMPLETE gave nothing usable. The match winner API is
-- only believed once the match is complete (it reports 0 at all other times).
local function FallbackWinner()
    local complete = pvp("IsMatchComplete") == true or num(pvp("GetActiveMatchState")) == 5
    if complete then
        local winner = num(pvp("GetActiveMatchWinner"))
        if winner ~= nil then return winner, "api" end
    end
    local winner = num(call(GetBattlefieldWinner))
    if winner ~= nil then return winner, "api" end
    return nil
end

local SOURCE_RANK = { chat = 1, api = 2, event = 3 }

-- The match is over. Idempotent; a better source (event > api > chat) may still
-- correct the result until the game is recorded.
local function CompleteMatch(winner, source, duration)
    local m = match
    if not m or m.recorded then return end
    local first = not m.completed
    if first then
        m.completed = true
        m.completedAt = GetTime()
    end
    if duration and duration > 0 and source == "event" then m.duration = duration end
    if winner ~= nil and (SOURCE_RANK[source] or 0) > (m.sourceRank or 0) then
        local result, teamSource = ResolveResult(winner)
        if result then
            m.winner, m.result, m.teamSource = winner, result, teamSource
            m.sourceRank = SOURCE_RANK[source]
        end
    end
    SaveBGState()
    if first then
        ArmFinish(m, RECORD_DELAY)
        m.sbState = "pending"
        m.sbStart = GetTime()
        PollScoreboard(m)
    end
end

function HonorLog:PVP_MATCH_COMPLETE(winner, duration)
    if not match then self:CheckBattlegroundStatus() end
    if not match or match.recorded then return end
    local w, d = num(winner), num(duration)
    if w == nil or (w ~= 0 and w ~= 1 and w ~= 255) then
        local fallback, source = FallbackWinner()
        CompleteMatch(fallback, source, d)
    else
        CompleteMatch(w, "event", d)
    end
end

-- BG system text, the last resort: only when nothing else named a winner.
local function HandleBGMessage(self, msg)
    if not match or match.recorded or match.result then return end
    if isSecret(msg) or type(msg) ~= "string" then return end
    local module = HonorLog.Battlegrounds[match.bgType]
    local faction = module and module:DetectWin(msg)
    if faction then
        dbg("BG text names the winner:", faction)
        CompleteMatch(faction == "Horde" and 0 or 1, "chat")
    end
end

function HonorLog:CHAT_MSG_BG_SYSTEM_ALLIANCE(msg) HandleBGMessage(self, msg) end
function HonorLog:CHAT_MSG_BG_SYSTEM_HORDE(msg) HandleBGMessage(self, msg) end
function HonorLog:CHAT_MSG_BG_SYSTEM_NEUTRAL(msg) HandleBGMessage(self, msg) end
function HonorLog:CHAT_MSG_RAID_BOSS_EMOTE(msg) HandleBGMessage(self, msg) end
function HonorLog:CHAT_MSG_MONSTER_YELL(msg) HandleBGMessage(self, msg) end

--------------------------------------------------------------------------------
-- Scoreboard capture
--------------------------------------------------------------------------------

-- pvpStatID -> column name (names are never secret).
local function StatColumnNames()
    local names = {}
    local cols = pvp("GetMatchPVPStatColumns")
    if type(cols) == "table" and not isSecret(cols) then
        for _, col in ipairs(cols) do
            if type(col) == "table" then
                local id, name = num(col.pvpStatID), str(col.name)
                if id and name then names[id] = name end
            end
        end
    end
    return names
end

-- One row, or nil when any number we need is still secret.
local function ReadRow(info, withStats, columns)
    if type(info) ~= "table" or isSecret(info) then return nil end
    local name, faction = str(info.name), num(info.faction)
    local kb, hk, deaths = num(info.killingBlows), num(info.honorableKills), num(info.deaths)
    local damage, healing = num(info.damageDone), num(info.healingDone)
    if not name or (faction ~= 0 and faction ~= 1) then return nil end
    if not (kb and hk and deaths and damage and healing) then return nil end
    local row = { name = name, faction = faction, kb = kb, hk = hk, deaths = deaths, damage = damage, healing = healing,
        class = str(info.classToken) }
    local honor = num(info.honorGained)
    if honor then row.honor = honor end
    if withStats then
        local objectives = {}
        if type(info.stats) == "table" and not isSecret(info.stats) then
            for _, stat in ipairs(info.stats) do
                if type(stat) == "table" then
                    local id, value = num(stat.pvpStatID), num(stat.pvpStatValue)
                    local label = (id and columns[id]) or str(stat.name) or (id and ("stat " .. id))
                    -- A secret objective value means the board is not final yet.
                    if label and value == nil then return nil end
                    if label then objectives[label] = value end
                end
            end
        end
        row.objectives = objectives
    end
    return row
end

local function SamePlayer(rowName, myName)
    if not rowName or not myName then return false end
    return rowName == myName or rowName:match("^([^-]+)-") == myName
end

-- Read the whole board. Returns { n, me, teams } only when every row is readable.
local function ReadScoreboard()
    local n = num(GetNumBattlefieldScores())
    if not n or n < 1 then return nil end
    local columns = StatColumnNames()
    local myGUID = call(UnitGUID, "player")
    local myName = Util.unitName("player")

    local rows, teams = {}, { [0] = { players = 0, kb = 0, hk = 0, deaths = 0 }, [1] = { players = 0, kb = 0, hk = 0, deaths = 0 } }
    for i = 1, n do
        local row = ReadRow(pvp("GetScoreInfo", i), false, columns)
        if not row then return nil end
        rows[#rows + 1] = row
        local team = teams[row.faction]
        team.players = team.players + 1
        team.kb, team.hk, team.deaths = team.kb + row.kb, team.hk + row.hk, team.deaths + row.deaths
    end

    local me
    if myGUID and not isSecret(myGUID) then
        me = ReadRow(pvp("GetScoreInfoByPlayerGuid", myGUID), true, columns)
    end
    if not me and myName then
        for i = 1, n do
            if SamePlayer(rows[i].name, myName) then
                me = ReadRow(pvp("GetScoreInfo", i), true, columns)
                break
            end
        end
    end
    if not me then return nil end
    return { n = n, me = me, teams = teams }
end

local function RequestScores()
    if RequestBattlefieldScoreData then pcall(RequestBattlefieldScoreData) end
end

local function AcceptBoard(m, board)
    local fuller = not m.sb or board.n >= m.sb.n
    if fuller then m.sb = board end
    return fuller
end

-- Read now; accept the first fully readable board and schedule one re-read.
local function TryScoreboard(m, request)
    if request then RequestScores() end
    local board = ReadScoreboard()
    if not board then return false end
    if m.sbState == "accepted" then
        AcceptBoard(m, board)
    else
        m.sbState = "accepted"
        AcceptBoard(m, board)
        C_Timer.After(SB_REREAD, function()
            if match ~= m or m.recorded then return end
            RequestScores()
            local again = ReadScoreboard()
            if again then AcceptBoard(m, again) end
            -- A board read through a guessed team may reveal the real one.
            if m.winner and m.teamSource ~= "arena" then
                m.result, m.teamSource = ResolveResult(m.winner)
            end
            SaveBGState()
        end)
    end
    -- The player's own line may be the first reliable word on which team they were on.
    if m.winner and m.teamSource ~= "arena" then
        m.result, m.teamSource = ResolveResult(m.winner)
    end
    SaveBGState()
    return true
end

-- Poll once a second until the board is readable or SB_GIVEUP passes.
PollScoreboard = function(m)
    if match ~= m or m.recorded or m.sbState ~= "pending" then return end
    m.sbPolls = (m.sbPolls or 0) + 1
    if GetTime() - (m.sbStart or GetTime()) >= SB_GIVEUP or m.sbPolls > SB_GIVEUP + 3 then
        m.sbState = "gaveup"
        dbg("Scoreboard never became readable; recording without it")
        SaveBGState()
        return
    end
    if TryScoreboard(m, true) then return end
    C_Timer.After(SB_POLL, function() PollScoreboard(m) end)
end

function HonorLog:UPDATE_BATTLEFIELD_SCORE()
    local m = match
    if not m or m.recorded then return end
    if not m.completed then
        -- A winner the PVP_MATCH_COMPLETE event did not give us.
        local winner, source = FallbackWinner()
        if winner ~= nil then CompleteMatch(winner, source) end
        return
    end
    if m.sbState == "pending" then TryScoreboard(m, false) end
end

-- Last look at the board before a loading screen takes it away.
function HonorLog:PLAYER_LEAVING_WORLD()
    local m = match
    if m and m.completed and not m.recorded and m.sbState == "pending" then
        TryScoreboard(m, true)
    end
    if m then SaveBGState() end
end

--------------------------------------------------------------------------------
-- Recording the game
--------------------------------------------------------------------------------

ArmFinish = function(m, delay)
    C_Timer.After(delay, function()
        if match == m and not m.recorded then FinalizeMatch("timer") end
    end)
end

local function ResultLabel(result)
    if result == "win" then return "|cff00ff00Victory|r" end
    if result == "loss" then return "|cffff0000Defeat|r" end
    if result == "draw" then return "|cffffd700Draw|r" end
    return "|cff999999Left early|r"
end

FinalizeMatch = function(reason)
    local m = match
    if not m or m.recorded then return end
    m.recorded = true -- first, so an error below can never record the game twice

    -- A game that ended without us hearing it: ask the winner APIs one last time.
    if not m.result then
        local winner = FallbackWinner()
        if winner ~= nil then m.result = ResolveResult(winner) end
    end
    local result = m.result or "left"

    UpdateMarks(m)
    local bgType = m.bgType
    local module = HonorLog.Battlegrounds[bgType]

    -- Honor: the sum of the currency gains, or the balance difference when events were missed.
    local honor = m.honorGained or 0
    local honorNow = ReadHonor()
    if honorNow and m.snapshot.honor then honor = math.max(honor, honorNow - m.snapshot.honor) end

    -- Marks: this battleground's mark item; a generic battleground counts every mark gained.
    local marks = 0
    if module and module:GetMarkItem() then
        marks = math.max(0, (m.marks or {})[bgType] or 0)
    else
        for _, delta in pairs(m.marks or {}) do marks = marks + math.max(0, delta) end
    end

    local rankEnd = ReadRank()
    local rankPoints = RankDelta(m.snapshot.rank, rankEnd)
    local rankState, rankCappedDuring
    if HonorLog.Rank then
        rankState, rankCappedDuring = HonorLog.Rank:ClassifyGame(m.snapshot.rank, rankEnd, rankPoints, m.snapshot.level)
    end

    -- A game played at the honor cap gives no honor; it stays out of the honor averages.
    local honorCap = ReadHonorCap() or m.snapshot.honorCap
    local honorCapped = honorCap and ((m.snapshot.honor and m.snapshot.honor >= honorCap)
        or (honorNow and honorNow >= honorCap)) or false

    local duration
    if m.duration and not m.joinedInProgress and result ~= "left" then
        duration = m.duration
    else
        duration = (m.completedAt or GetTime()) - m.startTime
    end
    duration = math.max(0, math.floor(duration))

    -- Reputation the game gave with its battleground's own faction.
    local startRep, endRep = m.snapshot.rep, ReadRep(bgType)
    local rep
    if startRep and startRep.amount and endRep and endRep.faction == startRep.faction and endRep.amount then
        rep = { faction = startRep.faction, gained = endRep.amount - startRep.amount }
    end
    if HonorLog.Probe and HonorLog.Probe.LogRepRead then HonorLog.Probe:LogRepRead(bgType, startRep, endRep, rep) end

    local extra = {
        result = result,
        rep = rep,
        joinedInProgress = m.joinedInProgress,
        rankPoints = rankPoints,
        rankState = rankState,
        rankCappedDuring = rankCappedDuring,
        honorCapped = honorCapped or nil,
        scoreboard = m.sb ~= nil,
    }
    if m.sb then
        local me = m.sb.me
        extra.kb, extra.hk, extra.deaths = me.kb, me.hk, me.deaths
        extra.damage, extra.healing = me.damage, me.healing
        extra.objectives = me.objectives
        extra.teams = m.sb.teams
    end

    dbg("RECORDING", bgType, result, "honor", honor, "marks", marks, "rank", rankPoints, "via", reason)
    local ok, err = pcall(HonorLog.RecordGame, HonorLog, bgType, result == "win", duration, honor, marks, extra)
    if not ok then
        print("|cffff0000[HonorLog ERROR]|r RecordGame failed: " .. tostring(err))
    else
        print(string.format("|cff00ff00[HonorLog]|r %s in %s - %s, +%d honor, +%d marks, +%d rank points",
            ResultLabel(result), HonorLog:GetBGDisplayName(bgType), HonorLog:FormatDuration(duration),
            honor, marks, rankPoints))
        local zeroLine = HonorLog.Rank and HonorLog.Rank:TakeZeroPointLine(bgType)
        if zeroLine then HonorLog:Say(zeroLine) end
    end
    SaveBGState()
end

--------------------------------------------------------------------------------
-- Honor: measured gains, the cap warning
--------------------------------------------------------------------------------

function HonorLog:OnHonorGained(amount)
    self:AddHonorGain(amount)
    if match then
        match.honorGained = (match.honorGained or 0) + amount
        SaveBGState()
    elseif not InPvPInstance() then
        self:RecordWorldHonor(amount)
    end
end

-- Warn once each time honor climbs to the configured share of the cap.
function HonorLog:CheckHonorCap()
    local settings = self.db and self.db.settings
    if not settings or settings.honorCapWarning == false then return end
    local info = C_CurrencyInfo and call(C_CurrencyInfo.GetCurrencyInfo, HONOR_CURRENCY)
    if type(info) ~= "table" then return end
    local quantity, cap = num(info.quantity), num(info.maxQuantity)
    if not quantity or not cap or cap <= 0 then return end -- never a hardcoded cap
    local pct = (settings.honorCapWarnPct or 90)
    local char = self.db.char
    if quantity >= cap * pct / 100 then
        if not char.honorCapWarned then
            char.honorCapWarned = true
            local text = string.format("Honor cap: %s of %s (%d%%). Spend honor before it is wasted.",
                tostring(quantity), tostring(cap), math.floor(quantity / cap * 100))
            -- the honor cap card says it on screen when it is switched on
            HonorLog:Announce(text, nil, nil, nil, HonorLog.Moments and HonorLog.Moments:Shows("honorCap"))
            HonorLog:Fire("HonorLog_HonorCapNear", quantity, cap)
        end
    else
        char.honorCapWarned = false
    end
end

function HonorLog:CURRENCY_DISPLAY_UPDATE(currencyType, quantity, quantityChange)
    if num(currencyType) == HONOR_CURRENCY then
        local change = num(quantityChange)
        if change and change > 0 then self:OnHonorGained(change) end
        self:CheckHonorCap()
    elseif num(currencyType) == 3468 then
        self:RefreshRank()
    end

    -- Update goals panel when currency changes (honor, marks)
    if self.mainFrame and self.mainFrame:IsShown() then
        if self.mainFrame.goalsPanel and self.mainFrame.goalsPanel:IsShown() then
            self:UpdateGoalsPanel()
        end
        self:UpdateMainFrame()
    end
end

-- Marks arrive as items: recompute this game's deltas once the bags settle.
function HonorLog:BAG_UPDATE_DELAYED()
    if match and not match.recorded then
        UpdateMarks(match)
        SaveBGState()
    end
end

-- Bag update - check for acquired goal items
local bagUpdatePending = false
function HonorLog:BAG_UPDATE()
    -- Debounce: BAG_UPDATE fires frequently, batch into a single delayed check
    if bagUpdatePending then return end
    bagUpdatePending = true

    C_Timer.After(0.5, function()
        bagUpdatePending = false
        -- Scan goals for items now in inventory
        local acquired = HonorLog:ScanGoalsForAcquiredItems()
        if acquired > 0 then
            -- Refresh the goals panel if visible
            HonorLog:UpdateGoalsPanel()
        end
    end)
end

function HonorLog:PLAYER_LOGOUT()
    if self.db and self.db.char then
        -- Store current GetTime() - on /reload this value will be less than GetTime() at next load
        -- On fresh login after logout, GetTime() will have reset, so it will be less than this stored value
        self.db.char.lastGameTime = GetTime()
        self.db.char.wasLogout = true -- Keep for backwards compatibility
        SaveBGState()
    end
end

--------------------------------------------------------------------------------
-- World PvP: kills
--------------------------------------------------------------------------------

-- Turn a client format string ("%s dies ... %d Honor") into a Lua pattern, so
-- the parser follows whatever language the client speaks. Handles positional
-- arguments (%1$s). Returns { pattern, order = { argIndex per capture }, kinds = { [argIndex] = "s"|"d" } }.
local MAGIC = "[%^%$%(%)%%%.%[%]%*%+%-%?]"
local function CompileFormat(fmt)
    if type(fmt) ~= "string" then return nil end
    local parts, order, kinds, seq = {}, {}, {}, 0
    local i = 1
    while i <= #fmt do
        local c = fmt:sub(i, i)
        if c == "%" then
            if fmt:sub(i + 1, i + 1) == "%" then
                parts[#parts + 1] = "%%"
                i = i + 2
            else
                local n, dollar, kind = fmt:sub(i + 1):match("^(%d*)(%$?)([sd])")
                if kind then
                    seq = seq + 1
                    local argIndex = (dollar == "$" and n ~= "") and tonumber(n) or seq
                    order[#order + 1] = argIndex
                    kinds[argIndex] = kind
                    parts[#parts + 1] = kind == "s" and "(.+)" or "(%d+)"
                    i = i + 1 + #n + #dollar + 1
                else
                    parts[#parts + 1] = "%%"
                    i = i + 1
                end
            end
        else
            parts[#parts + 1] = (c:gsub(MAGIC, "%%%0"))
            i = i + 1
        end
    end
    return { pattern = "^" .. table.concat(parts) .. "$", order = order, kinds = kinds }
end
HonorLog.CompileFormat = CompileFormat

-- Kill messages carry victim, rank and honor; the award message is honor only.
local KILL_FORMATS = { "COMBATLOG_HONORGAIN", "COMBATLOG_HONORGAIN_NO_RANK", "COMBATLOG_HONORGAIN_EXHAUSTION1" }
local AWARD_FORMATS = { "COMBATLOG_HONORAWARD" }
local honorFormats = {}

local function BuildHonorFormats()
    honorFormats = {}
    for _, group in ipairs({ { "kill", KILL_FORMATS }, { "award", AWARD_FORMATS } }) do
        for _, global in ipairs(group[2]) do
            local compiled = CompileFormat(_G[global])
            if compiled then
                compiled.kind = group[1]
                honorFormats[#honorFormats + 1] = compiled
            end
        end
    end
end
BuildHonorFormats()

-- Returns kind ("kill" | "award"), victim, rank, honor for one message.
local function ParseHonorMessage(msg)
    if #honorFormats == 0 then BuildHonorFormats() end
    for _, f in ipairs(honorFormats) do
        local caps = { msg:match(f.pattern) }
        if #caps > 0 then
            local byArg = {}
            for k, value in ipairs(caps) do byArg[f.order[k]] = value end
            local honor, names = nil, {}
            for argIndex = 1, #f.order + 1 do
                if f.kinds[argIndex] == "d" and not honor then honor = tonumber(byArg[argIndex]) end
                if f.kinds[argIndex] == "s" then names[#names + 1] = byArg[argIndex] end
            end
            if honor then return f.kind, names[1], names[2], honor end
        end
    end
    return nil
end
HonorLog.ParseHonorMessage = ParseHonorMessage

-- Enemy players in sight: target, mouseover, focus and the nameplates.
local UNITS = { "target", "mouseover", "focus" }
for i = 1, 40 do UNITS[#UNITS + 1] = "nameplate" .. i end

local function VisibleEnemies()
    local seen, list = {}, {}
    for _, unit in ipairs(UNITS) do
        if call(UnitExists, unit) == true and call(UnitIsPlayer, unit) == true and call(UnitIsEnemy, "player", unit) == true then
            local name = Util.unitName(unit)
            if name and not seen[name] then
                seen[name] = true
                local dead = call(UnitIsDeadOrGhost, unit) == true
                if dead and call(UnitIsFeignDeath, unit) == true then dead = false end -- hunters
                local _, token = call(UnitClass, unit)
                list[#list + 1] = { unit = unit, name = name, class = str(token), dead = dead }
            end
        end
    end
    return list
end

local function ClassForName(name)
    for _, enemy in ipairs(VisibleEnemies()) do
        if enemy.name == name then return enemy.class end
    end
end

-- A kill counter step with no message: the dead enemy in sight, else unknown.
local function AttributeByVisible()
    local now = GetTime()
    local candidates = {}
    for _, enemy in ipairs(VisibleEnemies()) do
        local seen = credited[enemy.name]
        if enemy.dead and (not seen or now - seen >= CREDIT_WINDOW) then candidates[#candidates + 1] = enemy end
    end
    if #candidates == 1 then return candidates[1] end
    for _, enemy in ipairs(candidates) do
        if enemy.unit == "target" then return enemy end
    end
    return nil
end

-- A PARTY_KILL (readable, ours) near the step makes it a killing blow.
local function TakeParty(t)
    for i, record in ipairs(pendingParty) do
        if math.abs(record.t - t) <= KILL_WINDOW then
            table.remove(pendingParty, i)
            return record
        end
    end
end

local function ResolveKill(step, msg, enemy)
    local party = TakeParty(step.t)
    local name = (msg and msg.name) or (enemy and enemy.name) or (party and party.name)
    local class = (enemy and enemy.class) or (name and ClassForName(name)) or (party and party.class)
    if name then credited[name] = GetTime() end
    HonorLog:RecordWorldKill(name, class, party ~= nil)
    dbg("World kill:", tostring(name), "killing blow:", tostring(party ~= nil))
end

-- Pair kill counter steps with honor messages that arrived within KILL_WINDOW.
local function PairKills()
    while pendingHK[1] and pendingMsgs[1] do
        local step, msg = pendingHK[1], pendingMsgs[1]
        if math.abs(step.t - msg.t) <= KILL_WINDOW then
            table.remove(pendingHK, 1)
            table.remove(pendingMsgs, 1)
            ResolveKill(step, msg, nil)
        elseif msg.t < step.t then
            table.remove(pendingMsgs, 1) -- a message for a kill we never counted
        else
            break
        end
    end
end

local function ExpireStep(step)
    PairKills()
    for i, s in ipairs(pendingHK) do
        if s == step then
            table.remove(pendingHK, i)
            ResolveKill(step, nil, AttributeByVisible())
            return
        end
    end
end

function HonorLog:PLAYER_PVP_KILLS_CHANGED()
    local hk = call(GetPVPSessionStats)
    if not num(hk) then return end
    if lastHK == nil or hk < lastHK then lastHK = hk return end -- first read, or a new session
    local gained = hk - lastHK
    lastHK = hk
    if gained <= 0 or InPvPInstance() then return end -- inside a battleground, kills come from the scoreboard
    for _ = 1, gained do
        local step = { t = GetTime() }
        pendingHK[#pendingHK + 1] = step
        PairKills()
        -- Wait for a late honor message, then fall back to who is lying dead in sight.
        C_Timer.After(KILL_WINDOW + 0.1, function() ExpireStep(step) end)
    end
end

function HonorLog:CHAT_MSG_COMBAT_HONOR_GAIN(msg)
    if isSecret(msg) or type(msg) ~= "string" then return end
    local kind, victim, rank, honor = ParseHonorMessage(msg)
    if not kind then
        dbg("CHAT_MSG_COMBAT_HONOR_GAIN not parsed:", msg)
        return
    end
    if InPvPInstance() then return end -- battleground honor is measured from the currency
    if kind == "kill" then
        self:RecordWorldHonorKind("kill", honor)
        pendingMsgs[#pendingMsgs + 1] = { name = victim, rank = rank, honor = honor, t = GetTime() }
        PairKills()
    else
        self:RecordWorldHonorKind("award", honor)
    end
end

-- PARTY_KILL is only trusted when both GUIDs are readable and the killer is us.
function HonorLog:PARTY_KILL(attackerGUID, targetGUID)
    if isSecret(attackerGUID) or isSecret(targetGUID) then return end
    if type(attackerGUID) ~= "string" or type(targetGUID) ~= "string" then return end
    if attackerGUID ~= call(UnitGUID, "player") then return end
    if not targetGUID:find("^Player") or InPvPInstance() then return end
    local _, class, _, _, _, name = call(GetPlayerInfoByGUID, targetGUID)
    pendingParty[#pendingParty + 1] = { t = GetTime(), name = str(name), class = str(class) }
    while #pendingParty > 10 do table.remove(pendingParty, 1) end
end

--------------------------------------------------------------------------------
-- World PvP: deaths
--------------------------------------------------------------------------------

-- Newest-first death recap sources that are players other than us.
local function RecapKiller()
    if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return nil, false end
    local events = call(C_DeathRecap.GetRecapEvents)
    if type(events) ~= "table" or isSecret(events) then return nil, false end
    local list = {}
    for _, e in ipairs(events) do
        if type(e) == "table" and not isSecret(e) then
            list[#list + 1] = { t = num(e.timestamp) or 0, guid = str(e.sourceGUID), name = str(e.sourceName) }
        end
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    local me = call(UnitGUID, "player")
    for _, e in ipairs(list) do
        if e.guid and e.guid ~= me and e.guid:find("^Player") then
            local _, class = call(GetPlayerInfoByGUID, e.guid)
            return { name = e.name or "Unknown", class = str(class) }, true
        end
    end
    return nil, #list > 0
end

local function ReadDeath(token, attempt)
    if token ~= deathToken then return end
    local killer, hadEvents = RecapKiller()
    if killer then
        HonorLog:RecordWorldDeath(killer.name, killer.class)
        dbg("World death by", killer.name)
    elseif not hadEvents and attempt < 2 then
        C_Timer.After(2, function() ReadDeath(token, attempt + 1) end) -- the recap can lag the death
    else
        dbg("Death not by a player; not counted")
    end
end

function HonorLog:PLAYER_DEAD()
    local _, instanceType = GetInstanceInfo()
    if instanceType ~= "none" or match then return end -- world PvP only; battlegrounds use the scoreboard
    deathToken = deathToken + 1
    local token = deathToken
    C_Timer.After(1, function() ReadDeath(token, 1) end)
end

--------------------------------------------------------------------------------
-- State accessors
--------------------------------------------------------------------------------

function HonorLog:GetCurrentBG()
    return match and match.bgType or nil
end

function HonorLog:IsInBG()
    return match ~= nil
end

function HonorLog:GetBGStartTime()
    return match and match.startTime or nil
end

function HonorLog:GetBGHonorAccumulated()
    return match and match.honorGained or 0
end

-- The game in progress, for the debug commands and the tests.
function HonorLog:GetMatchState()
    return match
end

-- Slash commands
function HonorLog:RegisterSlashCommands()
    SLASH_HONORLOG1 = "/honorlog"
    SLASH_HONORLOG2 = "/hl"

    SlashCmdList["HONORLOG"] = function(msg)
        self:HandleSlashCommand(msg)
    end
end

function HonorLog:HandleSlashCommand(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")
    cmd = cmd:lower()

    if cmd == "" or cmd == "toggle" then
        if self.Window then self.Window:Toggle() else self:ToggleMainFrame() end
    elseif cmd == "mini" then
        self:ToggleMainFrame()
    elseif cmd == "stats" then
        self:PrintStats(arg)
    elseif cmd == "rank" then
        if self.Rank then self.Rank:PrintSlash(arg) end
    elseif cmd == "reset" then
        local resetType = arg:lower()
        if resetType == "today" or resetType == "session" then
            self:ResetSession()
            print("|cff00ff00HonorLog|r Today's stats reset.")
        elseif resetType == "character" or resetType == "char" then
            -- Reset character battleground stats
            for bgType, _ in pairs(self.db.char.battlegrounds) do
                self.db.char.battlegrounds[bgType] = self.NewBGStats()
            end
            -- Also reset World PvP stats and the opponents list
            self.db.char.worldPvP = self.NewWorldStats()
            self.db.char.opponents = {}
            self.db.char.history = {}
            self:ResetSession()
            if self.UpdateMainFrame then
                self:UpdateMainFrame()
            end
            print("|cff00ff00HonorLog|r Character stats reset.")
        elseif resetType == "account" then
            -- Reset account-wide battleground stats
            for bgType, _ in pairs(self.db.global.battlegrounds) do
                self.db.global.battlegrounds[bgType] = self.NewBGStats()
            end
            -- Also reset World PvP stats
            self.db.global.worldPvP = self.NewWorldStats()
            self.db.global.history = {}
            if self.UpdateMainFrame then
                self:UpdateMainFrame()
            end
            print("|cff00ff00HonorLog|r Account stats reset.")
        else
            print("|cff00ff00HonorLog|r Usage: /honorlog reset [today|character|account]")
        end
    elseif cmd == "vendor" then
        if arg:lower() == "clear" then
            self:ClearMapPins()
            self:Say(L["Cleared the map pins and the arrow."])
        else
            self:ShowVendorForArg(arg)
        end
    elseif cmd == "export" then
        self:ShowExportFrame(arg)
    elseif cmd == "config" or cmd == "options" then
        self:OpenOptions()
    elseif cmd == "help" then
        self:PrintHelp()
    elseif cmd == "view" then
        if arg == "character" or arg == "char" then
            self:SetSetting("viewMode", "character")
            print("|cff00ff00HonorLog|r Now showing character stats.")
        elseif arg == "account" then
            self:SetSetting("viewMode", "account")
            print("|cff00ff00HonorLog|r Now showing account-wide stats.")
        else
            print("|cff00ff00HonorLog|r Usage: /honorlog view [character|account]")
        end
        if self.UpdateMainFrame then
            self:UpdateMainFrame()
        end
    elseif cmd == "minimap" then
        self:ToggleMinimapButton()
        local shown = self:IsMinimapButtonShown()
        print("|cff00ff00HonorLog|r Minimap button: " .. (shown and "shown" or "hidden"))
    elseif cmd == "debug" then
        debugMode = not debugMode
        print("|cff00ff00HonorLog|r Debug mode: " .. (debugMode and "ON" or "OFF"))
        if debugMode then
            print("|cff00ff00HonorLog|r Current state:")
            print("  InBG: " .. tostring(match ~= nil))
            print("  BG: " .. tostring(match and match.bgType))
            print("  Completed: " .. tostring(match and match.completed) .. ", result: " .. tostring(match and match.result))
            print("  Scoreboard: " .. tostring(match and match.sbState))
            print("  StartTime: " .. tostring(match and match.startTime))
            -- Try to detect BG
            local detected = self:DetectBattleground()
            print("  Detected BG: " .. tostring(detected))
            print("  GetBattlefieldWinner: " .. tostring(call(GetBattlefieldWinner)))
            -- Show session data
            print("  Session wasLogout: " .. tostring(self.db.char.wasLogout))
        end
    elseif cmd == "status" then
        -- Show current tracking status
        print("|cff00ff00HonorLog Status:|r")
        print("  In BG: " .. tostring(match ~= nil))
        print("  Current BG: " .. tostring(match and match.bgType))
        print("  Match complete: " .. tostring(match and match.completed) .. ", recorded: " .. tostring(match and match.recorded))
        local detected = self:DetectBattleground()
        print("  Detected BG: " .. tostring(detected))
        local session = self:GetTotalSessionStats()
        print("  Session games: " .. session.played)
        -- Show per-BG session breakdown
        print("  |cffffd700Session breakdown:|r")
        for bgType, s in pairs(self.db.char.session) do
            if s.played then
                print(string.format("    %s: %d played, %d wins, %d losses, %d draws, %d left", bgType, s.played or 0, s.wins or 0, s.losses or 0, s.draws or 0, s.left or 0))
            end
        end
    elseif cmd == "test" then
        -- Test command to manually record a game or world kill
        local subCmd = arg:lower()
        if subCmd == "kill" then
            self:RecordWorldKill("Testplayer", "WARRIOR", false)
            print("|cff00ff00HonorLog|r Test world kill recorded")
        elseif subCmd == "death" then
            self:RecordWorldDeath("Testplayer", "WARRIOR")
            print("|cff00ff00HonorLog|r Test world death recorded")
        else
            local bgType = arg:upper()
            if bgType == "" then bgType = "WSG" end
            if self.Battlegrounds[bgType] and bgType ~= "EOTS" then
                self:RecordGame(bgType, true, 600, 100, 3, { result = "win" })
                print("|cff00ff00HonorLog|r Test game recorded: " .. bgType .. " WIN")
            else
                print("|cff00ff00HonorLog|r Usage:")
                print("  /honorlog test [AV|AB|WSG|DI] - Record test BG win")
                print("  /honorlog test kill - Record test world kill")
                print("  /honorlog test death - Record test world death")
            end
        end
    elseif cmd == "goals" or cmd == "goal" then
        -- Goal management commands
        local subCmd, subArg = arg:match("^(%S*)%s*(.*)$")
        subCmd = (subCmd or ""):lower()

        if subCmd == "" or subCmd == "show" then
            -- Switch to goals tab
            self:SwitchTab("goals")
            if not self.mainFrame:IsShown() then
                self:ToggleMainFrame()
            end
        elseif subCmd == "add" then
            -- Add goal by item link or ID
            local itemID = nil
            -- Try to parse item link
            local linkedID = subArg:match("item:(%d+)")
            if linkedID then
                itemID = tonumber(linkedID)
            else
                -- Try direct ID
                itemID = tonumber(subArg)
            end

            if itemID then
                local success, err = self:AddGoal(itemID)
                if success then
                    local item = self:GetGearItem(itemID)
                    print("|cff00ff00[HonorLog]|r Added goal: " .. (item and item.name or "Item " .. itemID))
                else
                    print("|cffff0000[HonorLog]|r " .. (err or "Could not add goal"))
                end
            else
                print("|cff00ff00HonorLog|r Usage: /honorlog goal add [itemlink or itemID]")
            end
        elseif subCmd == "list" then
            -- List current goals
            local goals = self:GetAllGoalsProgress()
            if #goals == 0 then
                print("|cff00ff00[HonorLog]|r No goals set. Use /honorlog goal add to add one.")
            else
                print("|cff00ff00[HonorLog Goals]|r (" .. #goals .. " goals)")
                for i, goal in ipairs(goals) do
                    local statusColor = goal.isComplete and "|cff00ff00" or "|cffffff00"
                    local status
                    if goal.isComplete then
                        status = "READY"
                    else
                        local pieces = {}
                        for _, row in ipairs(goal.missing) do
                            if row.kind == "honor" then pieces[#pieces + 1] = string.format("%d honor", row.remaining)
                            elseif row.kind == "marks" then pieces[#pieces + 1] = string.format("%d %s marks", row.remaining, row.bg)
                            elseif row.kind == "gold" then pieces[#pieces + 1] = "gold"
                            elseif row.kind == "level" then pieces[#pieces + 1] = string.format(L["Level %d"], row.needed)
                            elseif row.kind == "rank" then pieces[#pieces + 1] = "rank " .. row.needed
                            elseif row.kind == "rep" then pieces[#pieces + 1] = (row.standingName or "standing") .. " rep" end
                        end
                        status = "needs " .. table.concat(pieces, ", ")
                        if goal.readyDate then status = status .. ", ready " .. date("%b %d", goal.readyDate)
                        elseif goal.readyText then status = status .. ", " .. goal.readyText end
                    end
                    print(string.format("  %d. %s%s|r - %s", i, statusColor, goal.name, status))
                end
            end
        elseif subCmd == "clear" then
            -- Clear all goals
            self.db.char.goals.items = {}
            print("|cff00ff00[HonorLog]|r All goals cleared.")
            self:UpdateGoalsPanel()
        elseif subCmd == "vendor" then
            self:ShowVendorForArg(subArg)
        elseif subCmd == "picker" then
            self:ShowGoalPicker()
        elseif subCmd == "advice" then
            local advice = self:GetHonorCapAdvice()
            if advice then
                print(string.format("|cffffd700[HonorLog]|r Honor %d of %d: %s", advice.current, advice.cap, advice.text))
                if advice.buyable and #advice.buyable > 0 then
                    print(L["You could buy right now:"])
                    for _, entry in ipairs(advice.buyable) do
                        local cost = { string.format("%s honor", BreakUpLargeNumbers(entry.honor)) }
                        for bgType, count in pairs(entry.marks or {}) do cost[#cost + 1] = string.format("%d %s marks", count, bgType) end
                        if entry.gold > 0 then cost[#cost + 1] = self:FormatMoney(entry.gold) end
                        print(string.format("  %s (%s)", entry.name or ("item " .. entry.itemID), table.concat(cost, ", ")))
                    end
                elseif advice.blocked then
                    print(L["Nothing in the database is buyable for this character right now."])
                end
            else
                print("|cff00ff00[HonorLog]|r No honor-cap advice right now.")
            end
        else
            print("|cff00ff00HonorLog|r Goal commands:")
            print("  |cffffffff/honorlog goal|r - Show goals panel")
            print("  |cffffffff/honorlog goal add [itemlink]|r - Add a goal")
            print("  |cffffffff/honorlog goal list|r - List current goals")
            print("  |cffffffff/honorlog goal clear|r - Clear all goals")
            print("  |cffffffff/honorlog goal picker|r - Open goal picker")
            print("  |cffffffff/honorlog goal advice|r - What to spend before honor caps")
            print("  |cffffffff/honorlog vendor [item name or goal number]|r - Show the vendor on the map")
        end
    elseif cmd == "currency" or cmd == "cur" then
        -- Diagnostic: show current honor and marks detection
        print("|cff00ff00HonorLog Currency Diagnostic:|r")

        -- Honor APIs
        print("|cffffd700Honor APIs:|r")
        print("  GetHonorCurrency exists: " .. tostring(GetHonorCurrency ~= nil))
        print("  GetPVPCurrency exists: " .. tostring(GetPVPCurrency ~= nil))
        print("  C_CurrencyInfo exists: " .. tostring(C_CurrencyInfo ~= nil))

        if GetHonorCurrency then
            local honor = GetHonorCurrency()
            print("  GetHonorCurrency() = " .. tostring(honor))
        end
        if GetPVPCurrency then
            local _, honor = GetPVPCurrency()
            print("  GetPVPCurrency() = " .. tostring(honor))
        end
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            -- Try common honor currency IDs
            local currencyIDs = {1792, 392, 43308, 1901}
            for _, currencyID in ipairs(currencyIDs) do
                local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
                if info then
                    print(string.format("  C_CurrencyInfo(%d) = %s: %d",
                        currencyID, info.name or "?", info.quantity or 0))
                end
            end
        end

        -- Our wrapper functions
        print("|cff00ff00HonorLog Values:|r")
        print("  GetCurrentHonor() = " .. tostring(self:GetCurrentHonor()))

        -- Marks
        print("|cff55bbffMarks:|r")
        local markItems = self.BG_MARK_ITEMS
        if markItems then
            for bgType, itemID in pairs(markItems) do
                local count = GetItemCount(itemID, true)
                local itemName = GetItemInfo(itemID)
                print(string.format("  %s (ID %d): %d marks%s",
                    bgType, itemID, count,
                    itemName and (" - " .. itemName) or " - (item not cached)"))
            end
        else
            print("  BG_MARK_ITEMS not defined!")
        end

        -- Check bag contents for marks manually
        print("|cff888888Scanning bags for mark items...|r")
        local foundMarks = false
        for bag = 0, 4 do
            local numSlots
            if C_Container and C_Container.GetContainerNumSlots then
                numSlots = C_Container.GetContainerNumSlots(bag)
            elseif GetContainerNumSlots then
                numSlots = GetContainerNumSlots(bag)
            else
                numSlots = 0
            end
            for slot = 1, numSlots do
                local slotItemID
                if C_Container and C_Container.GetContainerItemID then
                    slotItemID = C_Container.GetContainerItemID(bag, slot)
                elseif GetContainerItemID then
                    slotItemID = GetContainerItemID(bag, slot)
                end
                if slotItemID then
                    -- Check if it's a mark (20558=WSG, 20559=AB, 20560=AV, 274895=DI)
                    if slotItemID == 20558 or slotItemID == 20559 or slotItemID == 20560 or slotItemID == 274895 then
                        local itemName = GetItemInfo(slotItemID)
                        local count = 0
                        if C_Container and C_Container.GetContainerItemInfo then
                            local info = C_Container.GetContainerItemInfo(bag, slot)
                            count = info and info.stackCount or 0
                        elseif GetContainerItemInfo then
                            local _, stackCount = GetContainerItemInfo(bag, slot)
                            count = stackCount or 0
                        end
                        print(string.format("  Found: %s x%d in bag %d slot %d",
                            itemName or slotItemID, count, bag, slot))
                        foundMarks = true
                    end
                end
            end
        end
        if not foundMarks then
            print("  No mark items found in bags")
        end

        print("|cff888888Tip: If values show 0 but you have currency, please report which APIs are available.|r")
    elseif cmd == "resize" then
        local subCmd = arg:lower()
        if subCmd == "reset" or subCmd == "" then
            self:ResetFrameSize()
        elseif subCmd == "toggle" then
            self.db.settings.frameResizable = not self.db.settings.frameResizable
            print("|cff40d860HonorLog|r Frame resizing " .. (self.db.settings.frameResizable and "enabled" or "disabled"))
            if self.mainFrame and self.mainFrame.UpdateResizeGrip then
                self.mainFrame:UpdateResizeGrip()
            end
        else
            print("|cff00ff00HonorLog|r Resize commands:")
            print("  |cffffffff/honorlog resize|r - Reset frame size to default")
            print("  |cffffffff/honorlog resize toggle|r - Toggle resizing on/off")
        end
    elseif cmd == "history" then
        local list = self:GetHistory(self.db.settings.viewMode, tonumber(arg) or 10)
        if #list == 0 then print("|cff00ff00HonorLog|r No games recorded yet.") end
        for _, entry in ipairs(list) do
            print(date("%m-%d %H:%M ", entry.timestamp or 0) .. self:FormatHistoryRow(entry))
        end
    elseif cmd == "honor" then
        local h = self:GetHonorSummary()
        print(string.format("|cff00ff00HonorLog|r Honor: today %d, this week %d, this session %d (%d/hr). Now %d of %d (%.0f%%).",
            h.today, h.week, h.session, h.perHour, h.current, h.cap, h.percent))
    elseif cmd == "cap" then
        local value = arg:lower()
        if value == "on" or value == "off" then
            self.db.settings.honorCapWarning = value == "on"
        elseif tonumber(value) then
            self.db.settings.honorCapWarnPct = math.max(1, math.min(100, tonumber(value)))
        end
        print(string.format("|cff00ff00HonorLog|r Honor cap warning %s at %d%% of the cap. Usage: /honorlog cap [on|off|percent]",
            self.db.settings.honorCapWarning == false and "OFF" or "ON", self.db.settings.honorCapWarnPct or 90))
    elseif cmd == "moment" then
        if self.Moments then self.Moments:Demo(arg) end
    elseif cmd == "probe" then
        if self.Probe then
            self.Probe:HandleCommand(arg)
        end
    elseif cmd == "scan" then
        local subCmd = arg:lower()
        if subCmd == "" then
            self:ScanCurrentVendor()
        elseif subCmd == "export" then
            self:ExportScannedData()
        elseif subCmd == "clear" then
            self:ClearScannedData()
        elseif subCmd == "status" then
            self:ShowScanStatus()
        elseif subCmd == "debug" then
            self:ToggleScannerDebug()
        else
            self:ShowScanStatus()
        end
    elseif cmd == "scangoals" then
        -- Debug: scan goals and show what's happening
        print("|cff00ff00HonorLog Goal Scan Debug:|r")
        local goals = self.db.char.goals.items or {}
        print("  Active goals: " .. #goals)

        for i, goal in ipairs(goals) do
            local itemName = GetItemInfo(goal.itemID) or "Unknown"
            print(string.format("  %d. %s (ID: %d)", i, itemName, goal.itemID))

            -- Check bags
            local foundInBag = false
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

                    if slotItemID == goal.itemID then
                        print(string.format("     FOUND in bag %d slot %d!", bag, slot))
                        foundInBag = true
                    end
                end
            end

            -- Check equipped
            local foundEquipped = false
            for slot = 1, 19 do
                local equippedItemID = GetInventoryItemID("player", slot)
                if equippedItemID == goal.itemID then
                    print(string.format("     FOUND equipped in slot %d!", slot))
                    foundEquipped = true
                end
            end

            if not foundInBag and not foundEquipped then
                print("     Not found in bags or equipped")
            end
        end

        -- Force a scan
        print("|cff00ff00Forcing scan...|r")
        local acquired = self:ScanGoalsForAcquiredItems()
        print("  Items auto-completed: " .. acquired)
    else
        print("|cff00ff00HonorLog|r Unknown command. Type /honorlog help for options.")
    end
end

function HonorLog:PrintHelp()
    print("|cff00ff00HonorLog Commands:|r (also: /hl)")
    print("  |cffffffff/honorlog|r - Open or close the HonorLog window")
    print("  |cffffffff/honorlog mini|r - Show or hide the small tracker frame")
    print("  |cffffffff/honorlog stats [bg]|r - Print stats summary")
    print("  |cffffffff/honorlog reset today|r - Reset today's stats")
    print("  |cffffffff/honorlog reset character|r - Reset character stats")
    print("  |cffffffff/honorlog reset account|r - Reset account-wide stats")
    print("  |cffffffff/honorlog export [text|csv]|r - Export stats")
    print("  |cffffffff/honorlog view [character|account]|r - Switch view mode")
    print("  |cffffffff/honorlog goal|r - Show goals panel")
    print("  |cffffffff/honorlog goal add [itemlink]|r - Add gear goal")
    print("  |cffffffff/honorlog goal list|r - List current goals")
    print("  |cffffffff/honorlog goal clear|r - Clear all goals")
    print("  |cffffffff/honorlog minimap|r - Toggle minimap button")
    print("  |cffffffff/honorlog resize|r - Reset frame to default size")
    print("  |cffffffff/honorlog resize toggle|r - Enable/disable resizing")
    print("  |cffffffff/honorlog config|r - Open options")
    print("  |cffffffff/honorlog status|r - Show tracking status")
    print("  |cffffffff/honorlog debug|r - Toggle debug mode")
    print("  |cffffffff/honorlog currency|r - Show currency diagnostic")
    print("  |cffffffff/honorlog test [bg]|r - Test record a game")
    print("  |cffffffff/honorlog history [n]|r - Recent games")
    print("  |cffffffff/honorlog honor|r - Honor today, this week and this session")
    print("  |cffffffff/honorlog cap [on|off|percent]|r - Honor cap warning")
    print("  |cffffffff/honorlog rank [n]|r - PvP rank summary, or the plan to rank n")
    print("  |cffffffff/honorlog moment [report|rank|cap]|r - Show a pop-up card now")
    print("  |cffffffff/honorlog probe [on|off|status|clear]|r - Record what PvP data the client exposes (dev)")
    print("  |cffffffff/honorlog probe guild|r or |cffffffffgroup|r - Send one hidden test message and report whether sharing works (dev)")
    print("  |cffffffff/honorlog probe ui|r - Record which Blizzard templates and art this client has (dev)")
    print("  |cffffffff/honorlog vendor [item, goal number or clear]|r - Show a gear vendor on the map, or clear the pins")
    print("  |cffffffff/honorlog scan|r - Scan current PvP vendor (dev)")
    print("  |cffffffff/honorlog scan export|r - Export scanned data as Lua")
    print("  |cffffffff/honorlog help|r - Show this help")
end

function HonorLog:PrintStats(bgFilter)
    local scope = self.db.settings.viewMode
    local scopeLabel = scope == "account" and "Account" or "Character"

    print("|cff00ff00=== HonorLog Summary (" .. scopeLabel .. ") ===|r")

    local bgTypes = self:GetAllBattlegrounds()
    if bgFilter and bgFilter ~= "" then
        bgFilter = bgFilter:upper()
        if self.Battlegrounds[bgFilter] then
            bgTypes = {bgFilter}
        end
    end

    for _, bgType in ipairs(bgTypes) do
        local stats = self:GetBGStats(bgType, scope)
        local derived = self:GetDerivedStats(bgType, scope)
        local session = self:GetSessionStats(bgType)

        if stats.played > 0 or session.played > 0 then
            print(string.format("|cffffd700%s:|r %d played (%d-%d, %d draws, %d left) %.1f%% WR, Avg %s",
                self:GetBGShortName(bgType), stats.played, stats.wins, stats.losses, stats.draws or 0, stats.left or 0,
                derived.winrate, self:FormatDuration(derived.avgDuration)))
            print(string.format("  Honor: %d lifetime | Marks: %d lifetime",
                stats.honorLifetime, stats.marksLifetime))
            if session.played > 0 then
                print(string.format("  Today: %d-%d (%.1f%%), +%d honor, +%d marks",
                    session.wins, session.losses, derived.sessionWinrate,
                    session.honor, session.marks))
            end
        end
    end

    local totalSession = self:GetTotalSessionStats()
    if totalSession.played > 0 then
        print(string.format("|cff00ff00Today:|r %d games, %d-%d (%.1f%%), +%d honor, +%d marks",
            totalSession.played, totalSession.wins, totalSession.losses,
            totalSession.winrate, totalSession.honor, totalSession.marks))
    end

    -- World PvP stats
    local worldStats = self:GetWorldPvPStats(scope)
    local worldSession = self:GetSessionWorldPvPStats()
    if worldStats.kills > 0 or worldStats.deaths > 0 or worldSession.kills > 0 or worldSession.deaths > 0 then
        print(string.format("|cff888888World PvP:|r %d kills (%d unattributed), %d deaths (lifetime)",
            worldStats.kills, worldStats.unknownKills or 0, worldStats.deaths))
        if worldSession.kills > 0 or worldSession.deaths > 0 then
            print(string.format("  Today: %d kills, %d deaths",
                worldSession.kills, worldSession.deaths))
        end
    end
end

-- Callback for data updates
function HonorLog:OnDataUpdated()
    if self.UpdateMainFrame then
        self:UpdateMainFrame()
    end
    if self.UpdateLDB then
        self:UpdateLDB()
    end
end

-- LDB (LibDataBroker) Integration
function HonorLog:InitializeLDB()
    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not LDB then return end

    self.ldb = LDB:NewDataObject("HonorLog", {
        type = "data source",
        icon = "Interface\\Icons\\Spell_Holy_ChampionsBond",
        text = "HonorLog",
        label = "HonorLog",

        OnClick = function(frame, button)
            if button == "LeftButton" then
                if IsShiftKeyDown() then
                    self:PrintStats()
                elseif self.Window then
                    self.Window:Toggle()
                else
                    self:ToggleMainFrame()
                end
            elseif button == "RightButton" then
                self:ShowContextMenu()
            elseif button == "MiddleButton" then
                self:ShowExportFrame()
            end
        end,

        OnTooltipShow = function(tooltip)
            HonorLog:BuildLDBTooltip(tooltip)
        end,
    })

    self:UpdateLDB()

    -- Initialize minimap button
    self:InitializeMinimapButton()
end

-- Minimap button using LibDBIcon
function HonorLog:InitializeMinimapButton()
    local icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not icon then return end

    -- Register the minimap button
    icon:Register("HonorLog", self.ldb, self.db.settings.minimapButton)
    self.minimapIcon = icon
end

-- Toggle minimap button visibility
function HonorLog:ToggleMinimapButton()
    if not self.minimapIcon then return end

    local hidden = self.db.settings.minimapButton.hide
    if hidden then
        self.minimapIcon:Show("HonorLog")
        self.db.settings.minimapButton.hide = false
    else
        self.minimapIcon:Hide("HonorLog")
        self.db.settings.minimapButton.hide = true
    end
end

-- Check if minimap button is visible
function HonorLog:IsMinimapButtonShown()
    if not self.minimapIcon then return false end
    return not self.db.settings.minimapButton.hide
end

function HonorLog:UpdateLDB()
    if not self.ldb or not self.db.settings.ldbEnabled then return end

    local rankText = self.Rank and self.Rank:BrokerText()
    if rankText then
        self.ldb.text = rankText
        return
    end

    local currentBG = self:GetCurrentBG()
    local session = self:GetTotalSessionStats()

    local text
    if currentBG then
        local sessionBG = self:GetSessionStats(currentBG)
        if sessionBG.played > 0 then
            local wr = self:GetDerivedStats(currentBG).sessionWinrate
            text = string.format("|cffffd700%s|r %d-%d (%.0f%%)",
                self:GetBGShortName(currentBG), sessionBG.wins, sessionBG.losses, wr)
        else
            text = string.format("|cffffd700%s|r In Progress", self:GetBGShortName(currentBG))
        end
    elseif session.played > 0 then
        text = string.format("%d-%d (%.0f%%) +%dH",
            session.wins, session.losses, session.winrate, session.honor)
    else
        text = "No games"
    end

    self.ldb.text = text
end

function HonorLog:BuildLDBTooltip(tooltip)
    tooltip:AddLine("HonorLog", 0, 1, 0)
    tooltip:AddLine(" ")

    local scope = self.db.settings.viewMode
    local scopeLabel = scope == "account" and "Account-Wide" or "Character"
    tooltip:AddLine(scopeLabel .. " Stats:", 1, 0.82, 0)

    for _, bgType in ipairs(self:GetAllBattlegrounds()) do
        local stats = self:GetBGStats(bgType, scope)
        if stats.played > 0 then
            local derived = self:GetDerivedStats(bgType, scope)
            local color = derived.winrate >= 50 and "|cff00ff00" or "|cffff0000"
            tooltip:AddDoubleLine(
                self:GetBGShortName(bgType),
                string.format("%s%d-%d (%.0f%%)|r", color, stats.wins, stats.losses, derived.winrate),
                1, 1, 1,
                1, 1, 1
            )
        end
    end

    -- Session summary
    local session = self:GetTotalSessionStats()
    if session.played > 0 then
        tooltip:AddLine(" ")
        tooltip:AddLine("Today:", 1, 0.82, 0)
        local color = session.winrate >= 50 and "|cff00ff00" or "|cffff0000"
        tooltip:AddDoubleLine(
            "Games",
            string.format("%s%d-%d (%.0f%%)|r", color, session.wins, session.losses, session.winrate),
            1, 1, 1,
            1, 1, 1
        )
        -- Honor with hourly rate
        local honorText = string.format("+%d", session.honor)
        if session.hourlyRate > 0 then
            honorText = string.format("+%d |cff888888(%d/hr)|r", session.honor, session.hourlyRate)
        end
        tooltip:AddDoubleLine("Honor", honorText, 1, 1, 1, 1, 0.82, 0)
        tooltip:AddDoubleLine("Marks", string.format("+%d", session.marks), 1, 1, 1, 0.5, 0.5, 1)
        if session.draws > 0 or session.left > 0 then
            tooltip:AddDoubleLine("Draws / left early", string.format("%d / %d", session.draws, session.left), 1, 1, 1, 0.7, 0.7, 0.7)
        end

        -- World PvP today
        local worldSession = self:GetSessionWorldPvPStats()
        if worldSession and (worldSession.kills > 0 or worldSession.deaths > 0 or (worldSession.honor and worldSession.honor > 0)) then
            local worldText = string.format("|cff40d860%d|r-|cffe65959%d|r", worldSession.kills, worldSession.deaths)
            if worldSession.honor and worldSession.honor > 0 then
                worldText = worldText .. string.format(" (+%d)", worldSession.honor)
            end
            tooltip:AddDoubleLine("World PvP", worldText, 1, 1, 1, 1, 1, 1)
        end
    end

    -- Rank plan
    if self.Rank then
        tooltip:AddLine(" ")
        if not self.Rank:AddTooltipLines(tooltip) then tooltip:AddLine("No PvP rank data yet", 0.6, 0.6, 0.6) end
    end

    -- Honor summary (measured from the honor currency)
    local honor = self:GetHonorSummary()
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("Honor today", tostring(honor.today), 1, 1, 1, 1, 0.82, 0)
    tooltip:AddDoubleLine("Honor this week", tostring(honor.week), 1, 1, 1, 1, 0.82, 0)
    tooltip:AddDoubleLine("Honor this session", tostring(honor.session), 1, 1, 1, 1, 0.82, 0)

    -- Current BG
    local currentBG = self:GetCurrentBG()
    if currentBG then
        tooltip:AddLine(" ")
        tooltip:AddLine("Currently in: |cffffd700" .. self:GetBGDisplayName(currentBG) .. "|r", 0, 1, 0)
        local startTime = self:GetBGStartTime()
        if startTime then
            local duration = math.floor(GetTime() - startTime)
            tooltip:AddLine("Duration: " .. self:FormatDuration(duration), 0.7, 0.7, 0.7)
        end
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("|cff888888Left-click: Toggle frame|r")
    tooltip:AddLine("|cff888888Shift+Left-click: Print stats|r")
    tooltip:AddLine("|cff888888Right-click: Menu|r")
    tooltip:AddLine("|cff888888Middle-click: Export|r")
end
