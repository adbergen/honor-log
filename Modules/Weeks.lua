-- HonorLog Weeks
-- A record per reset week for this character, in char.weeks (newest first, at most 26), so that a later
-- weekly recap can say what the week was: games, honor, marks, rank points and the best game.
--
-- A record: { start, finish, estimated (true while finish is a guess), number (the rank week number, when
-- known), season (when known), games, wins, losses, draws, left, honor (all honor gained), bgHonor (honor of
-- recorded games), marks = { [bg] = n }, rankStart, rankEnd (running totals), kills, deaths, killingBlows,
-- best = { bgType, honor, timestamp }, filled (rebuilt from saved games), closed }.
--
-- The week. Weeks:Current() makes the record or turns it over. finish is now plus the seconds to the weekly
-- reset when the client gives that clock (a positive number); otherwise start plus seven days, estimated,
-- and corrected the first time the clock is readable. When now has reached finish the record is closed,
-- HonorLog_WeekEnded(record) fires once for it and one new record opens whose start is the most recent
-- reset: a player away for three weeks gets one new week, never empty ones. Turnover is lazy: it happens
-- at the first call after the reset (login, a game, an honor gain, a screen reading the week).
--
-- Filling it: the recorded game (HonorLog_GameRecorded), every honor gain (a post-hook on
-- HonorLog.AddHonorGain, the way UI/Window.lua hooks OnDataUpdated), a rank-up, and the world-PvP kill and
-- death events (HonorLog_WorldKill, HonorLog_WorldDeath; nothing fires those two yet). Each runs under
-- pcall and reports to the error handler.
--
-- Past weeks, once: the first time the current week has a real finish, it is rebuilt from the saved games
-- and each earlier week with saved games gets a record with filled = true (honor, kills, deaths and
-- killing blows are left out of those: the saved games do not hold them). char.weeksFilled marks it done.
--
-- Client functions used (Forever API documentation, build 1.60.1.71037, none flagged HasRestrictions):
-- C_DateAndTime.GetSecondsUntilWeeklyReset, and what Rank:GetInfo reads. Every answer is checked with
-- Util.num before use. Event PLAYER_ENTERING_WORLD turns the week over at login.

local _, HonorLog = ...
HonorLog = HonorLog or {}

local Weeks = {}
HonorLog.Weeks = Weeks

local Util = HonorLog.Util
local num, call = Util.num, Util.call
local isSecret = Util.isSecret

local DAY = 86400
local WEEK = 7 * DAY
local KEPT = 26
local HOUR = 3600
local JUMP = 3 * DAY -- a reset clock this far past the stored finish means a reset has happened
local AGREE = 300 -- seconds two readings of the reset clock may differ by and still name the same reset

Weeks.KEPT = KEPT

local function report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
end

-- Wrap a handler so a failure is reported and never raised into the game.
local function guarded(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then report(err) end
    end
end

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

local function char()
    local c = HonorLog.db and HonorLog.db.char
    return type(c) == "table" and c or nil
end

-- Seconds to the weekly reset, or nil when the client does not give a number a week can hold (positive, and
-- no more than seven days and an hour).
local function resetSeconds()
    local api = C_DateAndTime
    local seconds = api and num(call(api.GetSecondsUntilWeeklyReset))
    if seconds and seconds > 0 and seconds <= WEEK + HOUR then return seconds end
    return nil
end

local function rankInfo()
    local rank = HonorLog.Rank
    if not (rank and rank.GetInfo) then return nil end
    local ok, info = pcall(rank.GetInfo, rank)
    if ok and type(info) == "table" then return info end
    return nil
end

--------------------------------------------------------------------------------
-- The store
--------------------------------------------------------------------------------

local function newRecord(start, finish, estimated)
    return {
        start = start, finish = finish, estimated = estimated or nil,
        games = 0, wins = 0, losses = 0, draws = 0, left = 0,
        honor = 0, bgHonor = 0, marks = {},
        kills = 0, deaths = 0, killingBlows = 0,
    }
end

-- The list, made if need be; `since` is set here for a save that began at version 3.
local function store(c)
    if type(c.weeks) ~= "table" then c.weeks = {} end
    if type(c.since) ~= "number" then c.since = time() end
    return c.weeks
end

local function prune(weeks)
    while #weeks > KEPT do table.remove(weeks) end
end

local RESULT_FIELD = { win = "wins", loss = "losses", draw = "draws", left = "left" }

-- Count one saved game into a record: games, the result, battleground honor, marks and the best game.
-- A field that is missing, not of its type or a secret is left out.
local function tally(rec, entry)
    rec.games = rec.games + 1
    local result = Util.str(entry.result)
    local field = result and RESULT_FIELD[result]
    if not field and not isSecret(entry.win) then
        if entry.win == true then field = "wins" elseif entry.win == false then field = "losses" end
    end
    if field then rec[field] = (rec[field] or 0) + 1 end
    local bgType = Util.str(entry.bgType)
    local honor = num(entry.honor)
    if honor and honor > 0 then
        rec.bgHonor = rec.bgHonor + honor
        if not rec.best or honor > (num(rec.best.honor) or 0) then
            rec.best = { bgType = bgType, honor = honor, timestamp = num(entry.timestamp) }
        end
    end
    local marks = num(entry.marks)
    if marks and marks > 0 and bgType then
        rec.marks[bgType] = (rec.marks[bgType] or 0) + marks
    end
end

--------------------------------------------------------------------------------
-- Opening, correcting, turning over
--------------------------------------------------------------------------------

-- Fill number, season and the running totals from the rank data, once each and only when known. The number
-- of a new week is not taken while it still equals the one before (the client may not have turned over).
local function stamp(rec, info, prev)
    local n, season = num(info.weekNumber), num(info.season)
    if season == 0 then season = nil end
    if rec.number == nil and n and not (prev and prev.number == n and prev.season == season) then
        rec.number, rec.season = n, season
    elseif rec.number ~= nil and rec.season == nil and season and rec.number == n then
        rec.season = season
    end
    local total = num(info.totalPoints)
    if total then
        if rec.rankStart == nil then rec.rankStart = total end
        rec.rankEnd = total
    end
end

local function open(weeks, now, reset, prev)
    local start, finish, estimated
    if reset then
        finish = now + reset
        start = finish - WEEK
    elseif prev and num(prev.finish) then
        -- no clock: the most recent boundary in the chain of weeks, not one record per missed week
        start = prev.finish + math.floor((now - prev.finish) / WEEK) * WEEK
        finish, estimated = start + WEEK, true
    else
        start, finish, estimated = now, now + WEEK, true
    end
    if prev and num(prev.finish) and start < prev.finish then start = prev.finish end
    local rec = newRecord(start, finish, estimated)
    table.insert(weeks, 1, rec)
    prune(weeks)
    return rec
end

-- The games of char.history with a timestamp, newest first as saved.
local function savedGames(c)
    local out = {}
    if type(c.history) == "table" then
        for _, g in ipairs(c.history) do
            if type(g) == "table" and num(g.timestamp) then out[#out + 1] = g end
        end
    end
    return out
end

local function rankWeek(c, number)
    local log = type(c.rankWeeks) == "table" and number and c.rankWeeks[number]
    return type(log) == "table" and log or nil
end

-- The one-time fill of past weeks (see the header). Never fires HonorLog_WeekEnded.
local function fill(c, weeks, cur)
    local games = savedGames(c)

    -- the current week, brought up to date from the saved games since its start
    cur.games, cur.wins, cur.losses, cur.draws, cur.left, cur.bgHonor = 0, 0, 0, 0, 0, 0
    cur.marks, cur.best = {}, nil
    for _, g in ipairs(games) do
        if g.timestamp >= cur.start and g.timestamp < cur.finish then tally(cur, g) end
    end
    local log = c.honorLog
    local tookHonor = false
    if type(log) == "table" and num(log.weekEnd) and num(log.week) and math.abs(log.weekEnd - cur.finish) <= HOUR then
        cur.honor = log.week
        tookHonor = true
    end
    local own = rankWeek(c, cur.number)
    if own and num(own.startTotal) then cur.rankStart = own.startTotal end

    -- each earlier week that has saved games
    local buckets, skipped = {}, {}
    for _, g in ipairs(games) do
        if g.timestamp < cur.start then
            local k = math.floor((cur.start - g.timestamp - 1) / WEEK) + 1
            if not skipped[k] then
                local bucket = buckets[k]
                if not bucket then
                    local start = cur.start - k * WEEK
                    for i = 2, #weeks do
                        local other = weeks[i]
                        if num(other.start) and num(other.finish) and other.start < start + WEEK and other.finish > start then
                            skipped[k] = true -- an existing record already covers it
                        end
                    end
                    if not skipped[k] then
                        bucket = newRecord(start, start + WEEK)
                        bucket.filled, bucket.closed = true, true
                        bucket.honor, bucket.kills, bucket.deaths, bucket.killingBlows = nil, nil, nil, nil
                        local n = cur.number and cur.number - k
                        if n and n >= 1 then
                            bucket.number, bucket.season = n, cur.season
                            local past = rankWeek(c, n)
                            if past then bucket.rankStart, bucket.rankEnd = num(past.startTotal), num(past.endTotal) end
                        end
                        buckets[k] = bucket
                    end
                end
                if bucket then tally(bucket, g) end
            end
        end
    end
    local added = false
    for _, bucket in pairs(buckets) do
        weeks[#weeks + 1] = bucket
        added = true
    end
    if added then
        table.sort(weeks, function(a, b) return a.start > b.start end)
        prune(weeks)
    end
    return tookHonor
end

-- The record whose finish a second, later reading of the reset clock has agreed with (kept in memory only).
-- The one-time fill cuts every past week from that finish, and what it writes cannot be redone, so it does
-- not trust the single reading a record was made from.
local confirmFor, confirmed

-- The current record, made or turned over first. full = also read the rank data (number, season and the
-- running totals); the honor and kill paths leave it out unless something is missing. Also returns whether
-- the one-time fill ran in this call, and whether that fill took the honor log's total for the week: the
-- caller's own game or honor gain is then already counted.
local function current(full)
    local c = char()
    if not c then return nil end
    local weeks = store(c)
    local now = time()
    local reset = resetSeconds()
    local cur = weeks[1]
    local ended

    if type(cur) ~= "table" then
        cur = open(weeks, now, reset, nil)
    else
        local due = now >= (num(cur.finish) or 0)
        if not due and reset and not cur.estimated and now + reset - cur.finish > JUMP then due = true end
        if due then
            if not cur.closed then
                cur.closed = true
                ended = cur
            end
            cur = open(weeks, now, reset, cur)
        elseif cur.estimated and reset then
            -- the clock is readable for the first time: the finish is real, and the week began a week before it
            cur.finish, cur.estimated = now + reset, nil
            local start = cur.finish - WEEK
            local prev = weeks[2]
            if type(prev) == "table" and num(prev.finish) and start < prev.finish then start = prev.finish end
            if start < cur.start then cur.start = start end
        end
    end

    local info
    if full or ended or cur.number == nil or cur.rankStart == nil then
        info = rankInfo()
        if info then stamp(cur, info, weeks[2]) end
    end
    if reset and not cur.estimated then
        if confirmFor ~= cur then
            confirmFor, confirmed = cur, false -- first sight of this record with a clock
        elseif math.abs(now + reset - cur.finish) <= AGREE then
            confirmed = true
        end
    end
    local filledNow, tookHonor = false, false
    if not c.weeksFilled and not cur.estimated and confirmFor == cur and confirmed then
        c.weeksFilled = true
        filledNow = true
        local ok, result = pcall(fill, c, weeks, cur)
        if ok then tookHonor = result == true else report(result) end
    end
    if ended then HonorLog:Fire("HonorLog_WeekEnded", ended) end
    return cur, filledNow, tookHonor
end

-- The current record (after turning over when it is due).
function Weeks:Current()
    return (current(true))
end
Weeks.GetCurrent = Weeks.Current

--------------------------------------------------------------------------------
-- Filling it as things happen
--------------------------------------------------------------------------------

function Weeks:OnGame(entry)
    if type(entry) ~= "table" or isSecret(entry) then return end
    local rec, filledNow = current(true) -- reads the rank data, which sets rankEnd
    if not rec then return end
    if filledNow then
        -- the fill has just counted every saved game of this week, and a recorded game is saved before its
        -- event fires: counting it here too would count it twice
        local c = char()
        for _, g in ipairs(c and type(c.history) == "table" and c.history or {}) do
            if g == entry then return end
        end
    end
    tally(rec, entry)
end

function Weeks:OnHonor(amount)
    amount = num(amount)
    if not amount or amount <= 0 then return end
    local rec, _, tookHonor = current(false)
    -- a fill that took the honor log's week total in this call already holds this gain
    if rec and not tookHonor then rec.honor = (rec.honor or 0) + amount end
end

function Weeks:OnRankUp(_, info)
    local rec = current(true)
    local total = type(info) == "table" and not isSecret(info) and num(info.totalPoints)
    if rec and total then rec.rankEnd = total end
end

function Weeks:OnKill(entry)
    local rec = current(false)
    if not rec then return end
    rec.kills = (rec.kills or 0) + 1
    if type(entry) == "table" and not isSecret(entry) and not isSecret(entry.kb) and entry.kb == true then
        rec.killingBlows = (rec.killingBlows or 0) + 1
    end
end

function Weeks:OnDeath()
    local rec = current(false)
    if rec then rec.deaths = (rec.deaths or 0) + 1 end
end

HonorLog.RegisterCallback(Weeks, "HonorLog_GameRecorded", guarded(function(_, entry) Weeks:OnGame(entry) end))
HonorLog.RegisterCallback(Weeks, "HonorLog_RankUp", guarded(function(_, newRank, info) Weeks:OnRankUp(newRank, info) end))
HonorLog.RegisterCallback(Weeks, "HonorLog_WorldKill", guarded(function(_, entry) Weeks:OnKill(entry) end))
HonorLog.RegisterCallback(Weeks, "HonorLog_WorldDeath", guarded(function() Weeks:OnDeath() end))

-- Every honor gain: a post-hook, so AddHonorGain itself is not edited.
if type(HonorLog.AddHonorGain) == "function" then
    hooksecurefunc(HonorLog, "AddHonorGain", guarded(function(_, amount) Weeks:OnHonor(amount) end))
end

-- At login: turn the week over if a reset has passed, and look again a few seconds later, which gives the
-- reset clock its second reading.
local frame = CreateFrame("Frame", "HonorLogWeeksFrame")
frame:SetScript("OnEvent", guarded(function()
    current(true)
    if C_Timer and C_Timer.After then C_Timer.After(5, guarded(function() current(true) end)) end
end))
pcall(frame.RegisterEvent, frame, "PLAYER_ENTERING_WORLD")

--------------------------------------------------------------------------------
-- Readers
--------------------------------------------------------------------------------

-- What a week was. n = 0 is this week, 1 the last closed week (the record before it, which is not always the
-- calendar week before: a week with no visit has no record), and so on; nil when there is none. See the
-- brief for the fields; a field the record does not hold is nil (a filled week has no kills, deaths or
-- killing blows, and no honor beyond bgHonor).
function Weeks:GetRecap(n)
    if n == nil then n = 0 end
    n = num(n)
    if not n or n < 0 or n ~= math.floor(n) then return nil end
    local cur = current(true)
    if not cur then return nil end
    local weeks = char().weeks
    local rec = n == 0 and cur or weeks[n + 1]
    if type(rec) ~= "table" then return nil end

    local marksTotal, marks = 0, {}
    for bg, count in pairs(rec.marks or {}) do
        if num(count) then marks[bg] = count; marksTotal = marksTotal + count end
    end
    local games = num(rec.games) or 0
    local recap = {
        week = rec, played = games,
        wins = rec.wins or 0, losses = rec.losses or 0, draws = rec.draws or 0, left = rec.left or 0,
        honor = rec.honor,
        honorPerGame = games > 0 and (num(rec.bgHonor) or 0) / games or nil,
        marks = marks, marksTotal = marksTotal,
        rankGained = num(rec.rankStart) and num(rec.rankEnd) and rec.rankEnd - rec.rankStart or nil,
        best = rec.best, kills = rec.kills, deaths = rec.deaths, killingBlows = rec.killingBlows,
    }

    local number, rank = num(rec.number), HonorLog.Rank
    if number and rank and rank.CapRankForWeek then
        local info = rankInfo()
        if info then
            local ok, now, after = pcall(function() return rank:CapRankForWeek(number, info), rank:CapRankForWeek(number + 1, info) end)
            if ok and num(now) and num(after) and after > now then
                recap.nextCap = { rank = after, unlocks = HonorLog.GetRankUnlocks and HonorLog:GetRankUnlocks(after) or {} }
            end
        end
    end
    return recap
end
