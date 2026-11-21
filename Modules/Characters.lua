-- HonorLog Characters
-- A summary of each of the player's characters, kept in HonorLogDB.characters[key], so that a screen can
-- show them side by side. Each character writes only its own record; this module never reads another
-- character's saved variables.
--
-- A record: { name, class (token), faction, level, rank, rankPoints (the running total), capped (the weekly
-- rank cap is reached), capUntil (the time of the weekly reset the cap holds until), honor,
-- marks = { [bg] = n }, nextGoal (item id of the first goal), goalPercent, games, wins, lastSeen }.
-- Each value is written only when the client or the saved data gives it; one it does not give (or gives as a
-- secret) keeps what was stored before. A record with no lastSeen was never snapshotted: it is a stub that
-- holds only a name (the save migration and the login make those).
--
-- When it snapshots: on entering the world, five seconds later (rank data arrives late), after each recorded
-- game, on a rank-up, and at logout. Handlers run under pcall and report to the error handler; nothing
-- here runs per frame.
--
-- Client functions and events used (Forever API documentation, build 1.60.1.71037, none flagged
-- HasRestrictions): events PLAYER_ENTERING_WORLD, PLAYER_LOGOUT; UnitClass, UnitFactionGroup, UnitLevel,
-- GetUnitName / UnitName (through Util.unitName), GetRealmName, C_Timer.After; the reads Quests.ReadState
-- and Rank:GetInfo make (C_CurrencyInfo.GetCurrencyInfo, C_MajorFactions, C_DateAndTime,
-- C_SeasonInfo, C_Item.GetItemCount, GetMoney). Every answer goes through Util.num / Util.str first.

local _, HonorLog = ...
HonorLog = HonorLog or {}

local Characters = {}
HonorLog.Characters = Characters

local Util = HonorLog.Util
local num, str, call = Util.num, Util.str, Util.call
local isSecret = Util.isSecret

local LATE = 5 -- seconds after entering the world for the second snapshot

local function report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
end

-- Run one part of a snapshot, so that one failing part never stops the others.
local function part(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then report(err) end
end

local function accountStore()
    local global = HonorLog.db and HonorLog.db.global
    if type(global) ~= "table" then return nil end
    if type(global.characters) ~= "table" then global.characters = {} end
    return global.characters
end

-- The record of this character, made as a stub when there is none.
local function ownRecord(store, key)
    local rec = store[key]
    if type(rec) ~= "table" then
        rec = { name = key }
        store[key] = rec
    end
    return rec
end

--------------------------------------------------------------------------------
-- The snapshot
--------------------------------------------------------------------------------

local function readIdentity(rec)
    rec.name = Util.unitName("player") or rec.name
    local class = str((select(2, call(UnitClass, "player"))))
    if class and class ~= "" then rec.class = class end
    local faction = str((call(UnitFactionGroup, "player")))
    if faction and faction ~= "" then rec.faction = faction end
    rec.level = num(call(UnitLevel, "player")) or rec.level
end

local function readCurrencies(rec)
    local reading = HonorLog.Quests and HonorLog.Quests.ReadState and HonorLog.Quests.ReadState()
    if type(reading) ~= "table" then return false end
    rec.honor = num(reading.honor) or rec.honor
    if type(reading.marks) == "table" then
        for bg, count in pairs(reading.marks) do
            if type(bg) == "string" and num(count) then
                if type(rec.marks) ~= "table" then rec.marks = {} end
                rec.marks[bg] = count
            end
        end
    end
    return num(reading.honor) ~= nil
end

local function readRank(rec)
    -- Rank:GetInfo indexes the client's answer before checking it for secrecy, so it runs under pcall here.
    local rank = HonorLog.Rank
    local ok, info = pcall(function() return rank and rank.GetInfo and rank:GetInfo() end)
    if not ok or type(info) ~= "table" then return end
    rec.rank = num(info.rank) or rec.rank
    rec.rankPoints = num(info.totalPoints) or rec.rankPoints
    local capped = info.capped
    if not isSecret(capped) and type(capped) == "boolean" then
        rec.capped = capped
        if not capped then
            rec.capUntil = nil
        else
            local seconds = num(info.secondsToWeeklyReset)
            if seconds and seconds > 0 then rec.capUntil = time() + seconds end
        end
    end
end

local function readGames(rec)
    local stats = HonorLog.db and HonorLog.db.char and HonorLog.db.char.battlegrounds
    if type(stats) ~= "table" then return end
    local games, wins = 0, 0
    for _, bg in pairs(stats) do
        if type(bg) == "table" then
            games = games + (num(bg.played) or 0)
            wins = wins + (num(bg.wins) or 0)
        end
    end
    rec.games, rec.wins = games, wins
end

-- How far a goal is depends on the honor in hand, which the goal code reads from the client itself: with
-- honor unreadable the goal and its percent are left as they were.
local function readGoal(rec, honorKnown)
    if not honorKnown or not HonorLog.GetAllGoalsProgress then return end
    local list = HonorLog:GetAllGoalsProgress()
    if type(list) ~= "table" then return end
    local first = list[1]
    if type(first) ~= "table" then
        rec.nextGoal, rec.goalPercent = nil, nil -- the player has no goal
        return
    end
    rec.nextGoal = num(first.itemID) or rec.nextGoal
    local percent = HonorLog.GetGoalPercent and num(HonorLog:GetGoalPercent(first))
    if percent then rec.goalPercent = percent end
end

-- Write this character's record. Safe to call at any moment: every part runs under pcall.
function Characters:Snapshot()
    local store = accountStore()
    if not store then return nil end
    local rec = ownRecord(store, HonorLog:GetCharacterKey())
    part(readIdentity, rec)
    local honorKnown = false
    part(function() honorKnown = readCurrencies(rec) end)
    part(readRank, rec)
    part(readGames, rec)
    part(readGoal, rec, honorKnown)
    rec.lastSeen = time()
    return rec
end

local function safeSnapshot()
    local ok, err = pcall(Characters.Snapshot, Characters)
    if not ok then report(err) end
end

--------------------------------------------------------------------------------
-- When it runs
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame", "HonorLogCharactersFrame")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        safeSnapshot()
        C_Timer.After(LATE, safeSnapshot)
    elseif event == "PLAYER_LOGOUT" then
        safeSnapshot()
    end
end)
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT" }) do pcall(frame.RegisterEvent, frame, event) end

HonorLog.RegisterCallback(Characters, "HonorLog_GameRecorded", safeSnapshot)
HonorLog.RegisterCallback(Characters, "HonorLog_RankUp", safeSnapshot)

--------------------------------------------------------------------------------
-- Readers
--------------------------------------------------------------------------------

-- Copies of the records: each with key, current (this character), stub (never snapshotted: only a name) and
-- cappedNow (capped, and the reset it holds until is still ahead). The current character first, then the
-- others by lastSeen newest first, stubs last by name.
function Characters:GetList()
    local store = accountStore()
    local out = {}
    if not store then return out end
    local mine = HonorLog:GetCharacterKey()
    local now = time()
    for key, rec in pairs(store) do
        if type(key) == "string" and (type(rec) == "table" or rec == true) then
            local copy = type(rec) == "table" and Util.DeepCopy(rec) or { name = key }
            copy.key = key
            copy.current = key == mine
            copy.stub = num(copy.lastSeen) == nil
            local until_ = num(copy.capUntil)
            copy.cappedNow = copy.capped == true and until_ ~= nil and until_ > now
            out[#out + 1] = copy
        end
    end
    local function name(c) return (str(c.name) or c.key):lower() end
    table.sort(out, function(a, b)
        if a.current ~= b.current then return a.current end
        if a.stub ~= b.stub then return not a.stub end
        if not a.stub and a.lastSeen ~= b.lastSeen then return a.lastSeen > b.lastSeen end
        local na, nb = name(a), name(b)
        if na ~= nb then return na < nb end
        return a.key < b.key
    end)
    return out
end

-- { count, honor (the sum of the known ones), cappedNow (how many) } of a list from GetList (made when nil).
function Characters:GetTotals(list)
    list = list or self:GetList()
    local totals = { count = 0, honor = 0, cappedNow = 0 }
    for _, c in ipairs(list) do
        totals.count = totals.count + 1
        totals.honor = totals.honor + (num(c.honor) or 0)
        if c.cappedNow then totals.cappedNow = totals.cappedNow + 1 end
    end
    return totals
end

-- Remove the record of a character that is not this one (a deleted character). True when one was removed.
function Characters:Forget(key)
    local store = accountStore()
    if not store or type(key) ~= "string" or store[key] == nil then return false end
    if key == HonorLog:GetCharacterKey() then return false end
    store[key] = nil
    return true
end
