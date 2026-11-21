-- HonorLog Rank
-- Plans the climb through Forever's 14-rank PvP system.
--
-- Rank is renown on major faction 2800 ("PvP Rank Points"). The client says
-- where the player stands, what this week's cap is and when the season ends;
-- this module adds what the client does not: how many games a target rank
-- takes at the player's measured pace and the earliest date the weekly cap
-- allows it. Maths follow Blizzard's own rank window (Camelot/PVPRankFrame.lua):
--   * my total = total points for the current rank + points earned in it;
--   * this week's cap total = total points for currentWeekProgressiveMaxLevel;
--   * the next reward is the first rank above the current one with rewards.
-- Every client call runs under pcall and every number is checked for secrecy
-- first (see Modules/Probe.lua); rank data is not secret, the habit is kept.

local ADDON_NAME, HonorLog = ...

local Rank = {}
HonorLog.Rank = Rank

local RANK_FACTION = 2800
local RANK_POINTS_CURRENCY = 3468
local MAX_RANK = 14
local DAY = 86400

-- Points to finish each rank (curve 103650); the fallback when the client
-- cannot give cumulative totals.
local CURVE = { 750, 900, 1050, 1200, 1350, 1500, 1650, 1800, 1950, 2100, 2350, 2500, 2650, 3000 }
-- Highest rank each week of the season allows (curve 102601).
local CAP_BY_WEEK = { 3, 5, 6, 7, 8, 9, 11, 12, 13, 14 }

-- Pace
local DEFAULT_WIN, DEFAULT_LOSS = 100, 25
local MIN_MEASURED = 5       -- below this the pace is an estimate
local POINTS_SAMPLE = 30     -- games averaged for points per win / loss
local RATE_SAMPLE = 50       -- decided games used for the win rate
local PACE_DAYS = 7
local WEEKS_KEPT = 20
local PLAN_WEEK_LIMIT = 60
local ZERO_RUN = 3           -- games in a row giving 0 before a battleground is flagged

-- Character levels that block a rank. Player-reported and unconfirmed: the client data holds no
-- level rule for ranks (RenownRewards 46 has none), so a gate is only believed until the
-- character is seen holding that rank under the level (see CheckGateEvidence).
Rank.LEVEL_GATES = { { rank = 4, level = 40 } }

--------------------------------------------------------------------------------
-- Safe readers
--------------------------------------------------------------------------------
local Util = HonorLog.Util
local isSecret, num, str, call = Util.isSecret, Util.num, Util.str, Util.call
local L = HonorLog.L

--------------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------------
function Rank.FormatNumber(n)
    n = math.floor((tonumber(n) or 0) + 0.5)
    local s, k = tostring(n), 0
    repeat
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return s
end
local commas = Rank.FormatNumber

-- "3d 4h", "5h 12m", "9m".
function Rank.FormatSpan(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local d = math.floor(seconds / DAY)
    local h = math.floor((seconds % DAY) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

function Rank.FormatDate(ts)
    if not ts then return "-" end
    return date("%b %d", ts)
end

--------------------------------------------------------------------------------
-- Client reads
--------------------------------------------------------------------------------
local function db()
    return HonorLog.db
end

-- Title for a rank, for the player's faction and sex, as Blizzard builds it.
function Rank:TitleForRank(n)
    n = num(n)
    if not n or n <= 0 then
        return str(PVP_RANK_0_NAME) or "Unranked"
    end
    local first = (Enum and Enum.PvPRanks and num(Enum.PvPRanks.Rank_1)) or 5
    local faction01 = (call(UnitFactionGroup, "player") == "Alliance") and 1 or 0
    local key = "PVP_RANK_" .. tostring(first + n - 1) .. "_" .. tostring(faction01)
    local gender = UnitSex and call(UnitSex, "player") or nil
    if gender and isSecret(gender) then gender = nil end
    local text = GetText and str(call(GetText, key, gender)) or nil
    if text and text ~= "" and text ~= key then return text end
    return "Rank " .. n
end

-- Cumulative points needed to reach rank n (rank 0 is unranked, so rank n costs the
-- first n curve entries). The client knows; the curve is the fallback.
function Rank:TotalForRank(n)
    n = num(n)
    if not n or n <= 0 then return 0 end
    local api = C_MajorFactions
    if api and api.GetTotalReputationForRenownLevel then
        local total = num(call(api.GetTotalReputationForRenownLevel, RANK_FACTION, n))
        if total then return total end
    end
    local sum = 0
    for level = 1, math.min(n, #CURVE) do sum = sum + CURVE[level] end
    return sum
end

local function readSeason()
    local season = GetCurrentArenaSeason and num(call(GetCurrentArenaSeason))
    if not season and C_SeasonInfo and C_SeasonInfo.GetCurrentDisplaySeasonID then
        season = num(call(C_SeasonInfo.GetCurrentDisplaySeasonID))
    end
    return season or 0
end

-- The character's level; the one a level-up event just reported wins while the client catches up.
function Rank:PlayerLevel()
    local level = num(call(UnitLevel, "player"))
    local hint = num(HonorLog.levelHint)
    if hint and (not level or hint > level) then level = hint end
    return level
end

-- The level gate that applies to a character of this level and rank: { rank, level, blocking }, or nil.
-- It applies while the level is under the gate's level, the rank is under the gate's rank and the
-- gate has not been disproved for this character. It blocks now when the rank is the one just under the
-- gate rank and the weekly cap does not already stop the climb there (cap rank 0 = none named).
function Rank:GetGate(level, rank, capRank)
    if not (level and rank) then return nil end
    local char = db() and db().char
    local disproved = char and char.gateDisproved or {}
    for _, g in ipairs(Rank.LEVEL_GATES) do
        if level < g.level and rank < g.rank and not disproved[g.rank] then
            return {
                rank = g.rank, level = g.level,
                blocking = rank == g.rank - 1 and ((capRank or 0) <= 0 or capRank >= g.rank),
            }
        end
    end
    return nil
end

-- "Rank 4 needs level 40. Players report this; Blizzard hasn't confirmed it."
function Rank:GateText(gate)
    return string.format(L["Rank %d needs level %d. Players report this; Blizzard hasn't confirmed it."], gate.rank, gate.level)
end

-- A character that holds a gate's rank while under its level shows the gate is wrong for it.
function Rank:CheckGateEvidence(info)
    local char = db() and db().char
    if not (char and info and info.level) then return end
    for _, g in ipairs(Rank.LEVEL_GATES) do
        char.gateDisproved = char.gateDisproved or {}
        if info.level < g.level and info.rank >= g.rank and not char.gateDisproved[g.rank] then
            char.gateDisproved[g.rank] = true
            if HonorLog.Probe and HonorLog.Probe.LogGateObservation then
                HonorLog.Probe:LogGateObservation(g.rank, g.level, info.level, info.rank)
            end
        end
    end
end

-- nil when the client has no rank data (a low-level character, data not loaded).
function Rank:GetInfo()
    local api = C_MajorFactions
    if not (api and api.GetMajorFactionProgressionInfo) then return nil end
    local p = call(api.GetMajorFactionProgressionInfo, RANK_FACTION)
    if type(p) ~= "table" then return nil end
    local rank, earned = num(p.renownLevel), num(p.renownReputationEarned)
    if not rank or not earned then return nil end

    local threshold = num(p.renownLevelThreshold) or 0
    local seasonMax = num(p.maxLevel)
    if not seasonMax or seasonMax <= 0 then seasonMax = MAX_RANK end
    local capRank = num(p.currentWeekProgressiveMaxLevel) or 0
    local week = num(p.weekNumber)
    if not week or week < 1 then week = 1 end

    local total = self:TotalForRank(rank) + earned
    local capTotal = capRank > 0 and self:TotalForRank(capRank) or 0
    local seasonSeconds = C_SeasonInfo and num(call(C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd)) or 0
    local resetSeconds = C_DateAndTime and num(call(C_DateAndTime.GetSecondsUntilWeeklyReset)) or 0
    local level = self:PlayerLevel()

    return {
        level = level,
        gate = self:GetGate(level, rank, capRank),
        rank = rank,
        title = self:TitleForRank(rank),
        points = earned,
        threshold = threshold,
        percent = threshold > 0 and math.min(100, earned / threshold * 100) or 100,
        totalPoints = total,
        weekCapRank = capRank,
        weekCapTotal = capTotal,
        prevWeekCapRank = num(p.previousWeekProgressiveMaxLevel) or 0,
        seasonMaxRank = seasonMax,
        weekNumber = week,
        season = readSeason(),
        secondsToSeasonEnd = seasonSeconds,
        secondsToWeeklyReset = resetSeconds,
        capped = capTotal > 0 and total >= capTotal,
        pointsLeftThisWeek = capTotal > 0 and math.max(0, capTotal - total) or nil,
    }
end

--------------------------------------------------------------------------------
-- The weekly cap
--------------------------------------------------------------------------------

-- Highest rank week w allows. The current week is the client's own number; later
-- weeks follow the season curve, shifted so the current week agrees with it.
function Rank:CapRankForWeek(w, info)
    info = info or self:GetInfo()
    if not info then return 0 end
    w = math.floor(tonumber(w) or info.weekNumber)
    local seasonMax = info.seasonMaxRank
    local clientCap = info.weekCapRank
    if clientCap <= 0 then return seasonMax end -- the client names no cap
    if w <= info.weekNumber then
        if w == info.weekNumber then return math.min(clientCap, seasonMax) end
        return math.min(info.prevWeekCapRank > 0 and info.prevWeekCapRank or clientCap, seasonMax)
    end
    local offset = 0
    for k, cap in ipairs(CAP_BY_WEEK) do
        if cap == clientCap then offset = k - info.weekNumber break end
    end
    local idx = math.max(1, math.min(#CAP_BY_WEEK, w + offset))
    return math.min(math.max(CAP_BY_WEEK[idx], clientCap), seasonMax)
end

-- Points to finish rank n: the curve entry (rank n costs CURVE[n]; TotalForRank adds them up). nil
-- outside ranks 1 to 14.
function Rank:PointsForRank(n)
    n = num(n)
    return n and CURVE[math.floor(n)] or nil
end

-- One row per week of the season the cap table covers (and the current week when it lies beyond):
-- { { week, start (epoch seconds the week starts; nil when the client gives no reset clock), capRank,
-- capTotal (cumulative points of the cap rank), current (bool), past (bool) }, ... }, oldest week first.
-- Empty without rank data. Weeks are seven days apart, counted from the current week's reset time.
function Rank:GetSeasonSchedule(info)
    info = info or self:GetInfo()
    local out = {}
    if not info then return out end
    local currentStart
    if (info.secondsToWeeklyReset or 0) > 0 then currentStart = time() + info.secondsToWeeklyReset - 7 * DAY end
    for w = 1, math.max(#CAP_BY_WEEK, info.weekNumber) do
        local capRank = self:CapRankForWeek(w, info)
        out[#out + 1] = {
            week = w,
            start = currentStart and (currentStart + (w - info.weekNumber) * 7 * DAY) or nil,
            capRank = capRank, capTotal = self:TotalForRank(capRank),
            current = w == info.weekNumber, past = w < info.weekNumber,
        }
    end
    return out
end

-- Fourteen rows, ranks 1 to 14: { { rank, title, total (cumulative points), points (this rank's own cost),
-- state ("reached", "current" or "ahead"), items (HonorLog:GetRankUnlocks), plan (PlanToRank, for ranks
-- ahead; else nil), when (what PlanWhen says, else the state) }, ... }. Empty without rank data.
function Rank:GetRankTable(info, pace)
    info = info or self:GetInfo()
    local out = {}
    if not info then return out end
    pace = pace or self:GetPace()
    for n = 1, MAX_RANK do
        local state = n < info.rank and "reached" or (n == info.rank and "current" or "ahead")
        local plan = state == "ahead" and self:PlanToRank(n, info, pace) or nil
        out[#out + 1] = {
            rank = n, title = self:TitleForRank(n), total = self:TotalForRank(n), points = self:PointsForRank(n),
            state = state, items = HonorLog:GetRankUnlocks(n), plan = plan,
            when = plan and Rank.PlanWhen(plan) or state,
        }
    end
    return out
end

-- What the season chart draws: { weeks (GetSeasonSchedule), maxTotal (rank 14's cumulative points),
-- currentWeek, currentTotal, actual = { { week, total } } (end-of-week totals from the week log, oldest
-- first, ending with the current week's running total), projected = { { week, total } } (from the current
-- week on: each week's END total at the player's pace, never above that week's cap total; empty when the
-- pace is unknown or gives no points), gateLevel (the level a blocking gate needs, else nil) }.
-- A blocking gate keeps the projection flat: HonorLog cannot know when the level will come. All tables are
-- empty without rank data.
function Rank:GetSeasonSeries(info, pace)
    info = info or self:GetInfo()
    local out = { weeks = {}, maxTotal = 0, actual = {}, projected = {} }
    if not info then return out end
    pace = pace or self:GetPace()
    out.weeks = self:GetSeasonSchedule(info)
    out.maxTotal = self:TotalForRank(MAX_RANK)
    out.currentWeek, out.currentTotal = info.weekNumber, info.totalPoints

    local log = db() and db().char and db().char.rankWeeks or {}
    local past = {}
    for w, e in pairs(log) do
        if type(w) == "number" and w < info.weekNumber and type(e) == "table" and num(e.endTotal) then
            past[#past + 1] = w
        end
    end
    table.sort(past)
    for _, w in ipairs(past) do out.actual[#out.actual + 1] = { week = w, total = log[w].endTotal } end
    out.actual[#out.actual + 1] = { week = info.weekNumber, total = info.totalPoints }

    local gate = info.gate
    if gate and gate.blocking then out.gateLevel = gate.level end

    local perWeek = 0
    if pace and not pace.noPoints and (num(pace.pointsPerGame) or 0) > 0 and (num(pace.gamesPerDay) or 0) > 0 then
        perWeek = pace.gamesPerDay * 7 * pace.pointsPerGame
    end
    if perWeek <= 0 then return out end

    local running = info.totalPoints
    local left = (info.secondsToWeeklyReset or 0) > 0 and math.min(1, info.secondsToWeeklyReset / (7 * DAY)) or 1
    for _, row in ipairs(out.weeks) do
        if row.week >= info.weekNumber then
            if not out.gateLevel then
                local gain = row.week == info.weekNumber and perWeek * left or perWeek
                running = math.max(running, math.min(running + gain, row.capTotal))
            end
            out.projected[#out.projected + 1] = { week = row.week, total = running }
        end
    end
    return out
end

local WEEKLY_QUEST_FIRST, WEEKLY_QUEST_WEEKS = 96912, 10

-- The season's weekly quest ("Field of Honor: Week N", ids 96912 to 96921 for weeks 1 to 10) for the current
-- week: { week, questID, title, measured (rank points a hand-in of any of the ten quests gave, from the
-- probe's store; else nil), done (flagged completed, when the client says; else nil) }. nil outside weeks 1-10.
function Rank:GetWeeklyQuest(info)
    info = info or self:GetInfo()
    local week = info and num(info.weekNumber)
    if not week or week < 1 or week > WEEKLY_QUEST_WEEKS then return nil end
    local questID = WEEKLY_QUEST_FIRST + week - 1
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and str(call(C_QuestLog.GetTitleForQuestID, questID))
    if not title or title == "" then title = string.format(L["Field of Honor: Week %d"], week) end

    local store = type(HonorLogDB) == "table" and type(HonorLogDB.probe) == "table" and HonorLogDB.probe.quests
    local measured, newest = nil, -1
    for id = WEEKLY_QUEST_FIRST, WEEKLY_QUEST_FIRST + WEEKLY_QUEST_WEEKS - 1 do
        local last = type(store) == "table" and type(store[id]) == "table" and store[id].last
        local points = type(last) == "table" and num(last.rank)
        if points and points > 0 then
            -- this week's own quest wins; else the most recent hand-in of any of them
            local stamp = id == questID and math.huge or (num(last.t) or 0)
            if stamp > newest then measured, newest = points, stamp end
        end
    end

    local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and call(C_QuestLog.IsQuestFlaggedCompleted, questID)
    if isSecret(done) or type(done) ~= "boolean" then done = nil end
    return { week = week, questID = questID, title = title, measured = measured, done = done }
end

--------------------------------------------------------------------------------
-- Pace, measured from the games HonorLog recorded
--------------------------------------------------------------------------------
-- Why a game gave the rank points it did: the state FinalizeMatch stored, or for a record
-- from before that, "earned" when it gave points and "unknown" when it gave none.
local function gameState(g)
    if g.rankState then return g.rankState end
    if type(g.rankPoints) == "number" and g.rankPoints > 0 then return "earned" end
    return "unknown"
end

-- The points of a game that measures what a game gives: earned or zero, and not one that hit the
-- weekly cap on the way (its points were cut short). nil for every other game, and for a game the
-- player left early: leaving gives nothing whatever the battleground pays.
local function measuredPoints(g)
    if g.result == "left" then return nil end
    local state = gameState(g)
    if state == "zero" then return 0 end
    if state == "earned" and not g.rankCappedDuring and type(g.rankPoints) == "number" then return g.rankPoints end
    return nil
end

-- How the end of a game reads: state ("nodata", "capped", "gated", "earned" or "zero") and whether
-- the weekly cap was reached during it. from and to are the rank reads before and after
-- (Core's ReadRank), delta the points between them and level the character's level at the start.
-- A game that gave points is "earned" even where the gate applies: the gate only explains a 0.
function Rank:ClassifyGame(from, to, delta, level)
    if not from or not to then return "nodata" end
    if from.capTotal and from.capTotal > 0 and from.total and from.total >= from.capTotal then return "capped" end
    if delta > 0 then
        local cappedDuring = to.capTotal and to.capTotal > 0 and to.total and to.total >= to.capTotal or nil
        return "earned", cappedDuring
    end
    local gate = self:GetGate(level, from.level, from.capRank)
    if gate and gate.blocking then return "gated" end
    return "zero"
end

-- Battleground codes in display order, then any other seen in the history.
local function bgKeys(history)
    local keys, seen = {}, {}
    for _, bg in ipairs(HonorLog.BG_ORDER or {}) do keys[#keys + 1], seen[bg] = bg, true end
    local extra = {}
    for _, g in ipairs(history) do
        if g.bgType and not seen[g.bgType] then seen[g.bgType] = true extra[#extra + 1] = g.bgType end
    end
    table.sort(extra)
    for _, bg in ipairs(extra) do keys[#keys + 1] = bg end
    return keys
end

-- Pace for one battleground (bgType) or for all of them. Points per win and per loss come from
-- the measured games only: states earned and zero, never capped, gated, nodata or unknown ones.
function Rank:GetPace(bgType)
    local char = db() and db().char
    local all = char and char.history or {}
    local history = all
    if bgType then
        history = {}
        for _, g in ipairs(all) do
            if g.bgType == bgType then history[#history + 1] = g end
        end
    end
    local now = time()

    -- history[1] is the newest game.
    local winSum, winN, lossSum, lossN, measured, pointSum = 0, 0, 0, 0, 0, 0
    for _, g in ipairs(history) do
        local pts = measuredPoints(g)
        if pts then
            measured = measured + 1
            pointSum = pointSum + pts
            if g.result == "win" then winSum, winN = winSum + pts, winN + 1
            elseif g.result == "loss" then lossSum, lossN = lossSum + pts, lossN + 1 end
            if measured >= POINTS_SAMPLE then break end
        end
    end

    local wins, losses, decided = 0, 0, 0
    for _, g in ipairs(history) do
        if g.result == "win" then wins, decided = wins + 1, decided + 1
        elseif g.result == "loss" then losses, decided = losses + 1, decided + 1 end
        if decided >= RATE_SAMPLE then break end
    end

    local cutoff = now - PACE_DAYS * DAY
    local recent, oldest = 0, now
    for _, g in ipairs(history) do
        local ts = type(g.timestamp) == "number" and g.timestamp or nil
        if ts then
            if ts >= cutoff then recent = recent + 1 end
            if ts < oldest then oldest = ts end
        end
    end
    local days = PACE_DAYS
    if oldest > cutoff then days = math.max(1, (now - oldest) / DAY) end

    local estimated = measured < MIN_MEASURED
    local perWin = (not estimated and winN > 0) and winSum / winN or DEFAULT_WIN
    local perLoss = (not estimated and lossN > 0) and lossSum / lossN or DEFAULT_LOSS
    local rate = decided > 0 and wins / decided or 0.5

    return {
        pointsPerWin = perWin,
        pointsPerLoss = perLoss,
        winRate = rate,
        gamesPerDay = recent / days,
        measuredGames = measured,
        measuredWins = winN,
        measuredLosses = lossN,
        avgWin = winN > 0 and winSum / winN or nil,   -- the plain measured averages, with no defaults
        avgLoss = lossN > 0 and lossSum / lossN or nil,
        estimated = estimated,
        noPoints = not estimated and pointSum == 0,   -- measured, and every game gave 0
        pointsPerGame = rate * perWin + (1 - rate) * perLoss,
    }
end

-- One row per battleground with measured games: { bgType, name, perWin, perLoss, games }.
function Rank:GetPointsPerResult()
    local char = db() and db().char
    local history = char and char.history or {}
    local out = {}
    for _, bg in ipairs(bgKeys(history)) do
        local pace = self:GetPace(bg)
        if pace.measuredGames > 0 then
            out[#out + 1] = { bgType = bg, name = HonorLog:GetBGDisplayName(bg), perWin = pace.avgWin,
                perLoss = pace.avgLoss, games = pace.measuredGames }
        end
    end
    return out
end

-- Average points of the measured games outside one battleground; nil when there are none.
local function otherAverage(history, exclude)
    local sum, n = 0, 0
    for _, g in ipairs(history) do
        if g.bgType ~= exclude then
            local pts = measuredPoints(g)
            if pts then
                sum, n = sum + pts, n + 1
                if n >= POINTS_SAMPLE then break end
            end
        end
    end
    return n > 0 and sum / n or nil
end

-- Battlegrounds whose latest ZERO_RUN or more earned/zero games all gave 0 points:
-- { bgType, name, zero, games, otherAverage }. Games with another state (capped, gated, no
-- data, unknown) and games the player left early neither count nor break the run.
function Rank:GetZeroPointBattlegrounds()
    local char = db() and db().char
    local history = char and char.history or {}
    local runs, stopped = {}, {}
    for _, g in ipairs(history) do
        local bg = g.bgType
        if bg and not stopped[bg] and g.result ~= "left" then
            local state = gameState(g)
            if state == "zero" then runs[bg] = (runs[bg] or 0) + 1
            elseif state == "earned" then stopped[bg] = true end
        end
    end
    local out = {}
    for _, bg in ipairs(bgKeys(history)) do
        if (runs[bg] or 0) >= ZERO_RUN then
            out[#out + 1] = { bgType = bg, name = HonorLog:GetBGDisplayName(bg), zero = runs[bg], games = runs[bg],
                otherAverage = otherAverage(history, bg) }
        end
    end
    return out
end

-- "Alterac Valley gave 0 rank points in 3 of 3 games. Your other battlegrounds average 62."
function Rank:ZeroPointText(entry)
    local text = string.format(L["%s gave 0 rank points in %d of %d games."], entry.name, entry.zero, entry.games)
    if entry.otherAverage then
        text = text .. " " .. string.format(L["Your other battlegrounds average %d."], math.floor(entry.otherAverage + 0.5))
    end
    return text
end

local announcedZero = {} -- this login only

-- The chat line for a battleground that gives no points, once per battleground per login; else nil.
function Rank:TakeZeroPointLine(bgType)
    if announcedZero[bgType] then return nil end
    for _, entry in ipairs(self:GetZeroPointBattlegrounds()) do
        if entry.bgType == bgType then
            announcedZero[bgType] = true
            return self:ZeroPointText(entry)
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Plans
--------------------------------------------------------------------------------

-- What reaching rank n takes. info and pace may be passed in to avoid re-reading
-- them for every row of a table.
function Rank:PlanToRank(n, info, pace)
    info = info or self:GetInfo()
    if not info then return nil end
    pace = pace or self:GetPace()
    n = math.floor(tonumber(n) or 0)
    if n < 1 then n = 1 end
    local now = time()

    local plan = { target = n, reached = info.rank >= n, pointsNeeded = 0, gamesNeeded = 0 }
    if plan.reached then
        plan.limitedBy = "reached"
        return plan
    end
    plan.pointsNeeded = math.max(0, self:TotalForRank(n) - info.totalPoints)
    -- A pace of 0 points a game has no games-needed: a number would read "~0 games".
    local noPoints = pace.noPoints or pace.pointsPerGame <= 0
    plan.gamesNeeded = (not noPoints) and math.ceil(plan.pointsNeeded / pace.pointsPerGame) or nil

    if n > info.seasonMaxRank then
        plan.limitedBy = "season"
        return plan
    end

    -- Under a level gate no pace or cap date means anything yet.
    if info.gate and n >= info.gate.rank then
        plan.limitedBy, plan.gateLevel = "level", info.gate.level
        return plan
    end

    local week
    for w = info.weekNumber, info.weekNumber + PLAN_WEEK_LIMIT do
        if self:CapRankForWeek(w, info) >= n then week = w break end
    end
    plan.earliestWeekByCap = week
    if week then
        if week == info.weekNumber then
            plan.earliestDateByCap = now
        else
            plan.earliestDateByCap = now + info.secondsToWeeklyReset + (week - info.weekNumber - 1) * 7 * DAY
        end
    end
    if not noPoints and pace.gamesPerDay > 0 then
        plan.projectedDateAtPace = now + math.floor(plan.gamesNeeded / pace.gamesPerDay * DAY)
    end

    local capDate, paceDate = plan.earliestDateByCap, plan.projectedDateAtPace
    if not capDate then
        plan.limitedBy = "season"
        return plan
    end
    if noPoints then
        plan.limitedBy = "nopoints"
        return plan
    end
    plan.date = math.max(capDate, paceDate or capDate)
    if info.secondsToSeasonEnd > 0 and plan.date > now + info.secondsToSeasonEnd then
        plan.limitedBy = "season"
    elseif capDate > now and capDate >= (paceDate or 0) then
        plan.limitedBy = "cap"
    else
        plan.limitedBy = "pace"
    end
    return plan
end

--------------------------------------------------------------------------------
-- Rewards
--------------------------------------------------------------------------------
function Rank:GetRewards(n)
    local api = C_MajorFactions
    if not (api and api.GetRenownRewardsForLevel) then return {} end
    local raw = call(api.GetRenownRewardsForLevel, RANK_FACTION, n)
    local out = {}
    if type(raw) ~= "table" then return out end
    for _, r in ipairs(raw) do
        if type(r) == "table" then
            out[#out + 1] = {
                icon = r.icon, itemID = num(r.itemID),
                name = str(r.name), description = str(r.description) or str(r.name),
            }
        end
    end
    return out
end

-- The first rank above the current one that has rewards: rank, rewards.
function Rank:NextReward(info)
    info = info or self:GetInfo()
    if not info then return nil end
    for n = info.rank + 1, info.seasonMaxRank do
        local rewards = self:GetRewards(n)
        if #rewards > 0 then return n, rewards end
    end
    return nil
end

local function vendorHint()
    local key = (call(UnitFactionGroup, "player") == "Horde") and "PVP_RANK_REWARDS_VENDOR_HORDE"
        or "PVP_RANK_REWARDS_VENDOR_ALLIANCE"
    return str(_G[key])
end

--------------------------------------------------------------------------------
-- Alerts
--------------------------------------------------------------------------------

-- The shared alert (Util.lua): sound, centre-screen notice, error-frame line and chat.
function Rank:Announce(text, r, g, b)
    HonorLog:Announce(text, r, g, b)
end

-- MAJOR_FACTION_RENOWN_LEVEL_CHANGED: one celebration per rank gained.
function Rank:OnRenownChanged(factionID, newLevel, oldLevel)
    if num(factionID) ~= RANK_FACTION then return end
    newLevel, oldLevel = num(newLevel), num(oldLevel)
    local char = db() and db().char
    if newLevel and char and (not oldLevel or newLevel > oldLevel) and char.rankCelebrated ~= newLevel then
        char.rankCelebrated = newLevel
        self:Announce(string.format("Rank %d \226\128\148 %s", newLevel, self:TitleForRank(newLevel)))
        local info = self:GetInfo()
        HonorLog:Fire("HonorLog_RankUp", newLevel, info)
        local nextRank, rewards = self:NextReward(info or { rank = newLevel, seasonMaxRank = MAX_RANK })
        if nextRank then
            local names = {}
            for _, r in ipairs(rewards) do names[#names + 1] = r.description or r.name or "reward" end
            print(string.format("|cffffd700[HonorLog]|r Next reward at Rank %d: %s", nextRank, table.concat(names, ", ")))
        end
        local hint = vendorHint()
        if hint then print("|cffffd700[HonorLog]|r " .. hint) end
    end
    self:Refresh()
end

-- Once per week, the first time the cap is reached.
function Rank:CheckCapAlert(info)
    local d = db()
    if not (d and info and info.capped) then return end
    if d.settings.rankCapAlert == false then return end
    if d.char.rankCapAlertWeek == info.weekNumber then return end
    d.char.rankCapAlertWeek = info.weekNumber
    local text = string.format("Weekly rank cap reached (Rank %d).", info.weekCapRank)
    if info.weekCapRank < info.seasonMaxRank then
        text = string.format("Weekly rank cap reached (Rank %d). Rank %d opens in %s",
            info.weekCapRank, info.weekCapRank + 1, Rank.FormatSpan(info.secondsToWeeklyReset))
    end
    self:Announce(text)
    HonorLog:Fire("HonorLog_WeekCapReached", info)
end

--------------------------------------------------------------------------------
-- Weekly log: char.rankWeeks[week] = { startTotal, endTotal, games, capRank }
--------------------------------------------------------------------------------
function Rank:UpdateWeekLog(info)
    local char = db() and db().char
    if not (char and info) then return end
    char.rankWeeks = char.rankWeeks or {}
    local weeks = char.rankWeeks
    local entry = weeks[info.weekNumber]
    if not entry then
        -- A week starts where the last known one ended.
        local prevEnd, prevWeek
        for w, e in pairs(weeks) do
            if w < info.weekNumber and (not prevWeek or w > prevWeek) then prevWeek, prevEnd = w, e.endTotal end
        end
        entry = { startTotal = prevEnd or info.totalPoints, endTotal = info.totalPoints, games = 0, capRank = info.weekCapRank }
        weeks[info.weekNumber] = entry
    end
    entry.endTotal = info.totalPoints
    entry.capRank = info.weekCapRank

    local weekStart = time() + info.secondsToWeeklyReset - 7 * DAY
    local games = 0
    for _, g in ipairs(char.history or {}) do
        if type(g.timestamp) == "number" and g.timestamp >= weekStart then games = games + 1 end
    end
    entry.games = games

    local keys = {}
    for w in pairs(weeks) do keys[#keys + 1] = w end
    if #keys > WEEKS_KEPT then
        table.sort(keys)
        for i = 1, #keys - WEEKS_KEPT do weeks[keys[i]] = nil end
    end
end

-- Re-read everything: the week log, the cap alert, the UI and the broker text.
function Rank:Refresh()
    local info = self:GetInfo()
    if info and db() then
        self:CheckGateEvidence(info)
        self:UpdateWeekLog(info)
        self:CheckCapAlert(info)
    end
    if HonorLog.UpdateRankUI then HonorLog:UpdateRankUI(info) end
    if HonorLog.UpdateLDB then HonorLog:UpdateLDB() end
    return info
end

--------------------------------------------------------------------------------
-- Text for the broker, the tooltips and /honorlog rank
--------------------------------------------------------------------------------

-- "R7 Knight-Captain · 62%" when the player chose the rank format, else nil.
function Rank:BrokerText()
    local settings = db() and db().settings
    if not settings or settings.ldbFormat ~= "rank" then return nil end
    local info = self:GetInfo()
    if not info then return nil end
    local head = info.rank > 0 and string.format("R%d %s", info.rank, info.title) or info.title
    local text = string.format("%s \194\183 %d%%", head, math.floor(info.percent))
    if info.gate and info.gate.blocking then
        text = text .. " \194\183 " .. string.format(L["needs level %d"], info.gate.level)
    end
    return text
end

local TAG_TEXT = { cap = "cap", pace = "pace", season = "season", reached = "reached",
    level = L["level"], nopoints = L["no points"] }
Rank.TAG_TEXT = TAG_TEXT

-- What a plan says about time, in words: "after level 40", "no estimate: ...", else the date.
-- nil when there is nothing to say (reached, or a season plan with no date).
function Rank.PlanWhen(plan)
    if plan.limitedBy == "level" then return string.format(L["after level %d"], plan.gateLevel) end
    if plan.limitedBy == "nopoints" then return L["no estimate: your games give no rank points"] end
    if plan.date then return Rank.FormatDate(plan.date) end
    return nil
end

-- "~120 games", or nil when the plan has no games figure (no points, or a level gate).
function Rank.PlanGames(plan)
    if plan.gamesNeeded == nil or plan.limitedBy == "level" then return nil end
    return "~" .. commas(plan.gamesNeeded) .. " games"
end

local function planLine(self, plan)
    if plan.reached then return "reached" end
    local parts = { commas(plan.pointsNeeded) .. " pts" }
    parts[#parts + 1] = Rank.PlanGames(plan)
    parts[#parts + 1] = Rank.PlanWhen(plan)
    if plan.limitedBy ~= "nopoints" then parts[#parts + 1] = "(" .. (TAG_TEXT[plan.limitedBy] or "?") .. ")" end
    return table.concat(parts, " \194\183 ")
end

-- Fill a tooltip (the rank bar's and the broker's share this).
function Rank:AddTooltipLines(tooltip)
    local info = self:GetInfo()
    if not info then return false end
    local pace = self:GetPace()
    local head = info.rank > 0 and string.format("Rank %d \226\128\148 %s", info.rank, info.title) or info.title
    tooltip:AddLine(head, 1, 0.82, 0)
    if info.gate and info.gate.blocking then tooltip:AddLine(self:GateText(info.gate), 1, 0.55, 0.2, true) end
    if info.threshold > 0 then
        tooltip:AddDoubleLine("Progress", string.format("%s / %s (%d%%)", commas(info.points),
            commas(info.threshold), math.floor(info.percent)), 1, 1, 1, 1, 1, 1)
    end
    if info.weekCapRank > 0 then
        local capText = "Rank " .. info.weekCapRank
        if info.capped then capText = capText .. " (reached)"
        elseif info.pointsLeftThisWeek then capText = capText .. " (" .. commas(info.pointsLeftThisWeek) .. " pts left)" end
        tooltip:AddDoubleLine("This week's cap", capText, 1, 1, 1, 1, 0.82, 0)
    end

    local shown = 0
    for n = info.rank + 1, info.seasonMaxRank do
        if shown == 0 then tooltip:AddLine(" ") tooltip:AddLine("Next ranks" .. (pace.estimated and " (estimate)" or ""), 0.7, 0.7, 0.8) end
        local plan = self:PlanToRank(n, info, pace)
        tooltip:AddDoubleLine(string.format("R%d %s", n, self:TitleForRank(n)), planLine(self, plan), 1, 1, 1, 0.8, 0.8, 0.85)
        shown = shown + 1
        if shown >= 3 then break end
    end

    local nextRank, rewards = self:NextReward(info)
    if nextRank then
        tooltip:AddLine(" ")
        tooltip:AddLine("Next reward: Rank " .. nextRank, 0.7, 0.7, 0.8)
        for _, r in ipairs(rewards) do
            local icon = r.icon and ("|T" .. tostring(r.icon) .. ":14:14:0:0|t ") or ""
            tooltip:AddLine(icon .. (r.description or r.name or "Reward"), 1, 1, 1)
        end
    end

    tooltip:AddLine(" ")
    if info.secondsToSeasonEnd > 0 then
        tooltip:AddDoubleLine("Season ends in", Rank.FormatSpan(info.secondsToSeasonEnd), 1, 1, 1, 0.8, 0.8, 0.85)
    end
    if info.secondsToWeeklyReset > 0 then
        tooltip:AddDoubleLine("Weekly reset in", Rank.FormatSpan(info.secondsToWeeklyReset), 1, 1, 1, 0.8, 0.8, 0.85)
    end
    return true
end

local function say(text) HonorLog:Say(text) end

-- /honorlog rank [n]
function Rank:PrintSlash(arg)
    local info = self:GetInfo()
    if not info then
        say("No PvP rank data from the client yet.")
        return
    end
    local pace = self:GetPace()
    local target = tonumber(arg and arg:match("%d+"))
    if target then
        local plan = self:PlanToRank(target, info, pace)
        local title = string.format("Rank %d %s", plan.target, self:TitleForRank(plan.target))
        if plan.reached then
            say(title .. ": already reached.")
        elseif plan.limitedBy == "level" then
            say(string.format(L["%s: %s points to go, after level %d."], title, commas(plan.pointsNeeded), plan.gateLevel))
            say(self:GateText(info.gate))
        elseif plan.limitedBy == "nopoints" then
            say(string.format(L["%s: %s points to go. No estimate: your games give no rank points."], title, commas(plan.pointsNeeded)))
        elseif plan.limitedBy == "season" and not plan.date then
            say(string.format("%s: %s points to go, but this season tops out at Rank %d.",
                title, commas(plan.pointsNeeded), info.seasonMaxRank))
        else
            say(string.format("%s: %s points, about %s games%s. Earliest by cap: %s. At your pace: %s. Limited by %s.",
                title, commas(plan.pointsNeeded), commas(plan.gamesNeeded), pace.estimated and " (estimate)" or "",
                plan.earliestDateByCap and (plan.earliestDateByCap <= time() and "now" or Rank.FormatDate(plan.earliestDateByCap)) or "never this season",
                plan.projectedDateAtPace and Rank.FormatDate(plan.projectedDateAtPace) or "no games lately",
                TAG_TEXT[plan.limitedBy] or "?"))
        end
        return
    end

    local head = info.rank > 0 and string.format("Rank %d %s", info.rank, info.title) or info.title
    if info.gate and info.gate.blocking then say(self:GateText(info.gate)) end
    if info.threshold > 0 then
        say(string.format("%s: %s / %s (%d%%), %s points in total.", head, commas(info.points),
            commas(info.threshold), math.floor(info.percent), commas(info.totalPoints)))
    else
        say(string.format("%s: %s points in total.", head, commas(info.totalPoints)))
    end
    if info.weekCapRank > 0 then
        if info.capped then
            say(string.format("Week %d cap: Rank %d reached. %s", info.weekNumber, info.weekCapRank,
                info.weekCapRank < info.seasonMaxRank and
                    string.format("Rank %d opens in %s.", info.weekCapRank + 1, Rank.FormatSpan(info.secondsToWeeklyReset)) or ""))
        else
            say(string.format("Week %d cap: Rank %d, %s points to go. Next cap in %s.", info.weekNumber,
                info.weekCapRank, commas(info.pointsLeftThisWeek or 0), Rank.FormatSpan(info.secondsToWeeklyReset)))
        end
    end
    if info.secondsToSeasonEnd > 0 then say("Season ends in " .. Rank.FormatSpan(info.secondsToSeasonEnd) .. ".") end
    local nextRank, rewards = self:NextReward(info)
    if nextRank then
        local names = {}
        for _, r in ipairs(rewards) do names[#names + 1] = r.description or r.name or "reward" end
        say(string.format("Next reward at Rank %d: %s", nextRank, table.concat(names, ", ")))
    end
    for _, entry in ipairs(self:GetZeroPointBattlegrounds()) do say(self:ZeroPointText(entry)) end
    if pace.noPoints then say(L["Your measured games give no rank points, so there is no pace to plan with."]) end
    say(string.format("Pace: %d per win, %d per loss, %d%% wins, %.1f games a day%s.", math.floor(pace.pointsPerWin + 0.5),
        math.floor(pace.pointsPerLoss + 0.5), math.floor(pace.winRate * 100 + 0.5), pace.gamesPerDay,
        pace.estimated and " (estimate: fewer than " .. MIN_MEASURED .. " measured games)" or ""))
    if info.rank < info.seasonMaxRank then
        local plan = self:PlanToRank(info.rank + 1, info, pace)
        local games = Rank.PlanGames(plan)
        say(string.format("Rank %d: %s points, %s%s (%s).", plan.target, commas(plan.pointsNeeded),
            games and (games:gsub("^~", "about ") .. ", ") or "", Rank.PlanWhen(plan) or "no date",
            TAG_TEXT[plan.limitedBy] or "?"))
    end
end

Rank.RANK_FACTION = RANK_FACTION
Rank.RANK_POINTS_CURRENCY = RANK_POINTS_CURRENCY
Rank.MAX_RANK = MAX_RANK
