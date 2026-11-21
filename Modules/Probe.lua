-- HonorLog Probe
-- A kept debug aid. It records which PvP data WoW Forever actually gives
-- addons, so the tracking, rank and gear rounds can be designed on facts.
--
--   /honorlog probe          one-off snapshot into HonorLogDB.probe.snapshot
--   /honorlog probe on|off   arm / disarm passive event logging (persisted in
--                            HonorLogDB.probe.armed, ring buffer in .log)
--   /honorlog probe status   show what is armed and how much is stored
--   /honorlog probe clear    wipe the log and the scoreboard attempts
--
-- While armed it also learns what quests pay (HonorLogDB.probe.quests): no data an
-- addon can read ahead of time says what a PvP quest rewards, so the offer is read
-- when a quest window opens and the real change in honor, rank points, marks and
-- money is measured when the quest is handed in.
--
-- Rules this file follows (Forever API docs, build 70888):
--   * A value that may be secret is checked with issecretvalue() before it is
--     compared, concatenated, indexed or stored; a secret is stored as the
--     string "<secret>". Every read runs under pcall and keeps the error text.
--   * A function or event the docs flag HasRestrictions is never called or
--     registered (calling one raises the "blocked from an action" popup). It is
--     recorded as "skipped: restricted" instead. That covers the combat log:
--     COMBAT_LOG_EVENT_UNFILTERED, COMBAT_LOG_EVENT, C_CombatLogSecure.*.
--   * Nothing here ever writes a secret into saved variables.

local ADDON_NAME, HonorLog = ...

local Probe = {}
HonorLog.Probe = Probe

local PREFIX = "|cff00ff00[HonorLog]|r "
local LOG_CAP = 400
local SECRET = "<secret>"
local SKIPPED = "skipped: restricted"

local HONOR_CURRENCY, RANK_POINTS_CURRENCY, RANK_CURRENCY = 1792, 3468, 3473
local RANK_FACTION = 2800
local CURRENCY_IDS = { HONOR_CURRENCY, RANK_POINTS_CURRENCY, RANK_CURRENCY }
local MARK_ITEMS = { WSG = 20558, AB = 20559, AV = 20560, DI = 274895 }

-- Events the docs list as unrestricted; the log is only as good as this list.
local EVENTS = {
    "CHAT_MSG_COMBAT_HONOR_GAIN",
    "CURRENCY_DISPLAY_UPDATE",
    "PVP_MATCH_ACTIVE",
    "PVP_MATCH_COMPLETE",
    "UPDATE_BATTLEFIELD_SCORE",
    "ADDON_RESTRICTION_STATE_CHANGED",
    "PLAYER_PVP_KILLS_CHANGED",
    "PLAYER_PVP_RANK_CHANGED",
    "MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
    "CHAT_MSG_BG_SYSTEM_ALLIANCE",
    "CHAT_MSG_BG_SYSTEM_HORDE",
    "CHAT_MSG_BG_SYSTEM_NEUTRAL",
    "PLAYER_DEAD",
    "PARTY_KILL",
    "ZONE_CHANGED_NEW_AREA",
    "UPDATE_BATTLEFIELD_STATUS",
    "BAG_UPDATE_DELAYED",
    -- The client's own end-of-match reward report; may give each game's honor
    -- and rank points directly, without currency deltas.
    "POST_MATCH_CURRENCY_REWARD_UPDATE",
    "POST_MATCH_ITEM_REWARD_UPDATE",
    -- Quest windows and hand-ins, for the quest reward store.
    "QUEST_DETAIL",
    "QUEST_COMPLETE",
    "QUEST_TURNED_IN",
}

-- Flagged HasRestrictions in the Forever docs. Never called, never registered.
local RESTRICTED_EVENTS = {
    COMBAT_LOG_EVENT_UNFILTERED = "C_CombatLog.CombatLogEventUnfiltered: HasRestrictions",
    COMBAT_LOG_EVENT = "C_CombatLog.CombatLogEvent: HasRestrictions",
}
local RESTRICTED_FUNCTIONS = {
    ["C_CombatLogSecure.GetCurrentEventInfo"] = "HasRestrictions",
    ["C_CombatLogSecure.GetCurrentEntryInfo"] = "HasRestrictions",
    ["CombatLogGetCurrentEventInfo"] = "deprecation alias of the restricted combat-log getter; not in the docs, not called",
}

local DEATH_RECAP_EVENTS = 3

local UPDATE_SCORE_THROTTLE = 2 -- seconds between logged UPDATE_BATTLEFIELD_SCORE entries
local SCOREBOARD_DELAYS = { 1, 3, 10 }
local SCOREBOARD_MAX_EVENT_ATTEMPTS = 20

local QUEST_CAP = 300    -- quest records kept
local QUEST_SETTLE = 1.5 -- seconds after a hand-in before the rewards are measured
local QUEST_WINDOW = 120 -- seconds a hand-in window's reading stays usable

local frame
local lastScoreLog = 0
local questBefore -- { id, gt, state }: the reading taken when a hand-in window opened
local watch -- the scoreboard watch in progress, nil when none

--------------------------------------------------------------------------------
-- Secret-safe helpers
--------------------------------------------------------------------------------

local function isSecret(v)
    if not issecretvalue then return false end
    local ok, secret = pcall(issecretvalue, v)
    return (not ok) or secret == true
end

-- A copy of v that is safe to store: scalars as they are, secrets as "<secret>",
-- tables copied to a limited depth and size, everything else as its type name.
local function safe(v, depth)
    depth = depth or 0
    if isSecret(v) then return SECRET end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
    if t == "nil" then return "<nil>" end
    if t == "table" then
        if depth >= 3 then return "<table>" end
        local out, n = {}, 0
        local ok, err = pcall(function()
            for k, val in pairs(v) do
                n = n + 1
                if n > 60 then out["<truncated>"] = true break end
                local key = (type(k) == "number" or type(k) == "string") and k or tostring(type(k))
                out[key] = safe(val, depth + 1)
            end
        end)
        if not ok then out["<error>"] = tostring(err) end
        return out
    end
    return "<" .. t .. ">"
end

-- Call fn(...) under pcall. Returns the sanitized result (one value as itself,
-- several as a list, none as "<nothing>") or "error: <text>".
local function read(fn, ...)
    if type(fn) ~= "function" then return "unavailable" end
    local res = { pcall(fn, ...) }
    if not res[1] then return "error: " .. tostring(res[2]) end
    local n = #res
    if n == 1 then return "<nothing>" end
    if n == 2 then return safe(res[2]) end
    local out = {}
    for i = 2, n do out[i - 1] = safe(res[i]) end
    return out
end

local function nsFunc(ns, name)
    local t = _G[ns]
    if type(t) == "table" and type(t[name]) == "function" then return t[name] end
end

local function readNs(ns, name, ...)
    local fn = nsFunc(ns, name)
    if not fn then return "unavailable" end
    return read(fn, ...)
end

local function readGlobal(name, ...)
    return read(_G[name], ...)
end

local function db()
    HonorLogDB = HonorLogDB or {}
    HonorLogDB.probe = HonorLogDB.probe or {}
    local p = HonorLogDB.probe
    p.log = p.log or {}
    return p
end

local function say(msg)
    print(PREFIX .. msg)
end

--------------------------------------------------------------------------------
-- Snapshot
--------------------------------------------------------------------------------

local function markCounts()
    local counts = {}
    for bg, itemID in pairs(MARK_ITEMS) do
        counts[bg .. "_" .. itemID] = readNs("C_Item", "GetItemCount", itemID, true)
    end
    return counts
end

local function restrictionStates()
    local out = {}
    if not (C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState) then
        return "unavailable"
    end
    local types = {}
    local enum = Enum and Enum.AddOnRestrictionType
    if type(enum) == "table" then
        for name, value in pairs(enum) do types[name] = value end
    else
        for i = 0, 5 do types["type" .. i] = i end
    end
    for name, value in pairs(types) do
        out[name] = {
            state = readNs("C_RestrictedActions", "GetAddOnRestrictionState", value),
            active = readNs("C_RestrictedActions", "IsAddOnRestrictionActive", value),
        }
    end
    return out
end

local function battlegroundList()
    local list = {}
    local count = readGlobal("GetNumBattlegroundTypes")
    local n = type(count) == "number" and count or 12
    for i = 1, n do
        local info = readNs("C_PvP", "GetBattlegroundInfo", i)
        if type(info) ~= "table" then
            if i == 1 then list[1] = info end
            break
        end
        list[i] = info
    end
    return { count = count, battlegrounds = list }
end

local function formatStrings()
    local out = {}
    local ok, err = pcall(function()
        for key, value in pairs(_G) do
            if type(key) == "string" and key:find("^COMBATLOG_HONOR") then
                out[key] = safe(value)
            end
        end
    end)
    if not ok then out["<error>"] = tostring(err) end
    return out
end

local function renownRewards()
    local rewards = {}
    for level = 1, 14 do
        rewards[level] = readNs("C_MajorFactions", "GetRenownRewardsForLevel", RANK_FACTION, level)
    end
    return rewards
end

local function currencies()
    local out = {}
    for _, id in ipairs(CURRENCY_IDS) do
        out[tostring(id)] = readNs("C_CurrencyInfo", "GetCurrencyInfo", id)
    end
    return out
end

local function playerInfo()
    return {
        faction = readGlobal("UnitFactionGroup", "player"),
        level = readGlobal("UnitLevel", "player"),
        instance = readGlobal("GetInstanceInfo"),
        build = readGlobal("GetBuildInfo"),
        matchActive = readNs("C_PvP", "IsMatchActive"),
        matchComplete = readNs("C_PvP", "IsMatchComplete"),
        matchState = readNs("C_PvP", "GetActiveMatchState"),
        isBattleground = readNs("C_PvP", "IsBattleground"),
        isPVPMap = readNs("C_PvP", "IsPVPMap"),
    }
end

function Probe:TakeSnapshot()
    local snap = {
        t = time(),
        gt = GetTime(),
        player = playerInfo(),
        battlegrounds = battlegroundList(),
        faction2800 = {
            progression = readNs("C_MajorFactions", "GetMajorFactionProgressionInfo", RANK_FACTION),
            data = readNs("C_MajorFactions", "GetMajorFactionData", RANK_FACTION),
            rewards = renownRewards(),
        },
        currencies = currencies(),
        season = {
            displaySeasonID = readNs("C_SeasonInfo", "GetCurrentDisplaySeasonID"),
            displaySeasonExpansion = readNs("C_SeasonInfo", "GetCurrentDisplaySeasonExpansion"),
            secondsUntilPVPSeasonEnd = readNs("C_SeasonInfo", "GetTimeUntilCurrentPVPSeasonEnd"),
        },
        pvpStats = {
            session = readGlobal("GetPVPSessionStats"),
            lifetime = readGlobal("GetPVPLifetimeStats"),
            yesterday = readGlobal("GetPVPYesterdayStats"),
        },
        marks = markCounts(),
        honorFormatStrings = formatStrings(),
        addonRestrictions = restrictionStates(),
        -- Static, from the Forever docs: nothing below was called or registered.
        restrictedEvents = RESTRICTED_EVENTS,
        restrictedFunctions = RESTRICTED_FUNCTIONS,
        combatLog = {
            COMBAT_LOG_EVENT_UNFILTERED = SKIPPED,
            CombatLogGetCurrentEventInfo = SKIPPED,
        },
    }
    db().snapshot = snap
    return snap
end

--------------------------------------------------------------------------------
-- Scoreboard timing: when does the end-of-match scoreboard become readable?
--------------------------------------------------------------------------------

local function ownRow()
    if not (C_PvP and C_PvP.GetScoreInfoByPlayerGuid) then return nil, "unavailable" end
    local guid = UnitGUID and UnitGUID("player")
    if guid == nil or isSecret(guid) then return nil, "no readable player guid" end
    local ok, info = pcall(C_PvP.GetScoreInfoByPlayerGuid, guid)
    if not ok then return nil, "error: " .. tostring(info) end
    return info
end

-- One scoreboard read. Returns the record to store and whether it counts as
-- fully readable: a score count, the player's own row with a plain-number
-- honorGained, and the stat columns.
local function readScoreboard(label)
    local rec = { attempt = label, t = time(), gt = GetTime() }
    -- Ask the server for fresh score data first, as Blizzard's scoreboard does.
    -- Not in the docs (so not flagged restricted); pcall keeps it harmless.
    rec.requestScoreData = read(_G.RequestBattlefieldScoreData)
    local numScores = readGlobal("GetNumBattlefieldScores")
    rec.numScores = numScores

    local raw, why = ownRow()
    local ownReadable = false
    if raw ~= nil then
        rec.own = safe(raw)
        -- NeverSecret fields (name, faction, className) and numeric fields are
        -- reported separately: the docs promise the first group, not the second.
        local function fieldsReadable(fields)
            local ok, res = pcall(function()
                local all, any = true, false
                for _, f in ipairs(fields) do
                    local v = raw[f]
                    if isSecret(v) or v == nil then all = false else any = true end
                end
                return { all = all, any = any }
            end)
            return ok and res or ("error: " .. tostring(res))
        end
        rec.neverSecretFieldsReadable = fieldsReadable({ "name", "faction", "className" })
        rec.numericFieldsReadable = fieldsReadable({ "killingBlows", "honorableKills", "deaths", "honorGained" })
        local ok, honor = pcall(function() return raw.honorGained end)
        ownReadable = ok and not isSecret(honor) and type(honor) == "number"
    else
        rec.own = why or "<nil>"
    end

    rec.row1 = readNs("C_PvP", "GetScoreInfo", 1)
    rec.row2 = readNs("C_PvP", "GetScoreInfo", 2)
    local columns = readNs("C_PvP", "GetMatchPVPStatColumns")
    rec.columns = columns
    rec.winner = readNs("C_PvP", "GetActiveMatchWinner")
    rec.team = readGlobal("GetBattlefieldArenaFaction")
    rec.duration = readNs("C_PvP", "GetActiveMatchDuration")
    rec.matchComplete = readNs("C_PvP", "IsMatchComplete")
    rec.postMatchCurrency = readNs("C_PvP", "GetPostMatchCurrencyRewards")
    rec.postMatchItems = readNs("C_PvP", "GetPostMatchItemRewards")

    local scoresOK = type(numScores) == "number" and numScores > 0
    local columnsOK = type(columns) == "table"
    rec.readable = scoresOK and ownReadable and columnsOK or false
    return rec, rec.readable
end

local function recordAttempt(label)
    if not watch then return end
    local rec, readable = readScoreboard(label)
    local attempts = watch.record.attempts
    attempts[#attempts + 1] = rec
    if readable and not watch.record.firstReadable then
        watch.record.firstReadable = label
        watch.record.firstReadableGt = rec.gt
        watch.record.secondsAfterComplete = rec.gt - watch.record.gt
    end
end

function Probe:BeginScoreboardWatch(winner, duration)
    local p = db()
    p.scoreboard = p.scoreboard or {}
    local list = p.scoreboard
    local record = {
        t = time(),
        gt = GetTime(),
        winner = safe(winner),
        duration = safe(duration),
        attempts = {},
    }
    list[#list + 1] = record
    while #list > 10 do table.remove(list, 1) end
    watch = { record = record, eventAttempts = 0 }

    recordAttempt("immediate")
    for _, delay in ipairs(SCOREBOARD_DELAYS) do
        C_Timer.After(delay, function()
            if watch and watch.record == record then
                recordAttempt("after " .. delay .. "s")
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Passive logging
--------------------------------------------------------------------------------

local function push(event, ...)
    local log = db().log
    local entry = { t = time(), gt = GetTime(), event = event }
    local n = select("#", ...)
    if n > 0 then
        local args = {}
        for i = 1, n do args[i] = safe((select(i, ...))) end
        entry.args = args
    end
    log[#log + 1] = entry
    while #log > LOG_CAP do table.remove(log, 1) end
    return entry
end

-- The rank module saw a character hold a rank at or above a level gate while under its level, so the
-- gate does not hold for it. One log entry, only while the probe is armed.
function Probe:LogGateObservation(gateRank, gateLevel, level, rank)
    if not db().armed then return end
    push("RANK_GATE_DISPROVED", gateRank, gateLevel, level, rank)
end

-- A vendor window opened: could the addon read the NPC's GUID, and was a map position available?
-- One log entry, only while the probe is armed. loc is HonorLog:ReadVendorLocation().
function Probe:LogMerchantRead(loc)
    if not db().armed or type(loc) ~= "table" then return end
    local entry = push("MERCHANT_READ", loc.guidReadable == true, loc.positionAvailable == true)
    entry.npc, entry.map, entry.x, entry.y = loc.npc, loc.map, loc.x, loc.y
end

-- A game was recorded: the reputation read at its start and end, and the delta kept. One log entry,
-- only while the probe is armed.
function Probe:LogRepRead(bgType, startRep, endRep, rep)
    if not db().armed then return end
    local entry = push("REP_DELTA", bgType)
    entry.faction = (rep and rep.faction) or (startRep and startRep.faction)
    entry.startAmount = startRep and startRep.amount
    entry.endAmount = endRep and endRep.amount
    entry.gained = rep and rep.gained
    entry.readable = rep ~= nil
end

--------------------------------------------------------------------------------
-- Quest rewards
--------------------------------------------------------------------------------
-- Kept per quest id, outside the ring log, so a levelling session does not push the
-- battleground entries out. The old quest-window globals (GetQuestID, GetRewardMoney, ...)
-- are not in the docs, so not flagged restricted; every read runs under pcall.

local function plain(v)
    if type(v) == "number" then return v end
end

-- Honor, rank points (faction 2800's standing as one running total), money and marks, as plain
-- numbers where the client gives them.
local function questState()
    local honor = readNs("C_CurrencyInfo", "GetCurrencyInfo", HONOR_CURRENCY)
    local progress = readNs("C_MajorFactions", "GetMajorFactionProgressionInfo", RANK_FACTION)
    local rank
    if type(progress) == "table" then
        local level, earned = plain(progress.renownLevel), plain(progress.renownReputationEarned)
        local curve = HonorLog.Rank
        if level and earned then
            rank = ((curve and curve.TotalForRank) and curve:TotalForRank(level) or 0) + earned
        end
    end
    return {
        honor = type(honor) == "table" and plain(honor.quantity) or nil,
        rank = rank,
        money = plain(readGlobal("GetMoney")),
        marks = markCounts(),
    }
end

local function questItems(kind, countFn)
    local list = {}
    for i = 1, math.min(plain(readGlobal(countFn)) or 0, 10) do
        list[i] = readGlobal("GetQuestItemInfo", kind, i)
    end
    return list
end

-- What the open quest window offers.
local function questOffer(id)
    return {
        money = readGlobal("GetRewardMoney"),
        xp = readGlobal("GetRewardXP"),
        honor = readGlobal("GetRewardHonor"),
        items = questItems("reward", "GetNumQuestRewards"),
        choices = questItems("choice", "GetNumQuestChoices"),
        currencies = readNs("C_QuestInfoSystem", "GetQuestRewardCurrencies", id),
        factions = readNs("C_QuestOffer", "GetQuestOfferMajorFactionReputationRewards"),
    }
end

local function questRecord(id)
    local p = db()
    p.quests = p.quests or {}
    local rec = p.quests[id]
    if not rec then
        rec = { id = id, turnIns = 0 }
        p.quests[id] = rec
    end
    rec.t = time()
    return rec
end

-- Over the cap, the oldest records that never touched honor, rank points or marks go first.
local function trimQuests()
    local quests = db().quests
    local list = {}
    for _, rec in pairs(quests or {}) do list[#list + 1] = rec end
    if #list <= QUEST_CAP then return end
    table.sort(list, function(a, b)
        if (a.pvp == true) ~= (b.pvp == true) then return a.pvp ~= true end
        if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) < (b.t or 0) end
        return a.id < b.id
    end)
    for i = 1, #list - QUEST_CAP do quests[list[i].id] = nil end
end

-- QUEST_DETAIL (a quest is offered) or QUEST_COMPLETE (its hand-in window is open).
local function onQuestWindow(event)
    local id = plain(readGlobal("GetQuestID"))
    if not id or id == 0 then return end
    local rec = questRecord(id)
    rec.title = readGlobal("GetTitleText")
    rec.offer = questOffer(id)
    rec.offerFrom = event
    local offer = rec.offer
    if (plain(offer.honor) or 0) > 0 or (type(offer.factions) == "table" and next(offer.factions) ~= nil) then
        rec.pvp = true
    end
    if event == "QUEST_COMPLETE" then
        questBefore = { id = id, gt = GetTime(), state = questState() }
    end
    trimQuests()
end

-- QUEST_TURNED_IN: compare the reading from the hand-in window with one taken a moment later.
-- A quest handed in without its window has nothing to compare against and is only counted.
local function onQuestTurnedIn(id, xp, money)
    if isSecret(id) or type(id) ~= "number" then return end
    local rec = questRecord(id)
    rec.turnIns = (rec.turnIns or 0) + 1
    local last = { t = time(), xp = safe(xp), money = safe(money), measured = false }
    rec.last = last
    local before
    if questBefore and questBefore.id == id and GetTime() - questBefore.gt <= QUEST_WINDOW then
        before = questBefore.state
    end
    questBefore = nil
    trimQuests()
    if not before then return end
    C_Timer.After(QUEST_SETTLE, function()
        local after = questState()
        local function change(key)
            if before[key] and after[key] then return after[key] - before[key] end
        end
        local marks = {}
        for key, count in pairs(after.marks) do
            local was = before.marks[key]
            if type(count) == "number" and type(was) == "number" and count ~= was then
                marks[key] = count - was
            end
        end
        last.honor, last.rank, last.moneyChange, last.marks = change("honor"), change("rank"), change("money"), marks
        last.measured = true
        if (last.honor or 0) ~= 0 or (last.rank or 0) ~= 0 or next(marks) ~= nil then rec.pvp = true end
    end)
end

-- PARTY_KILL: are the GUIDs secret, in or out of a battleground?
local function onPartyKill(attacker, target)
    local entry = { t = time(), gt = GetTime(), event = "PARTY_KILL" }
    entry.attackerSecret = isSecret(attacker)
    entry.targetSecret = isSecret(target)
    entry.inBattleground = readNs("C_PvP", "IsBattleground")
    entry.matchActive = readNs("C_PvP", "IsMatchActive")
    if not entry.targetSecret and type(target) == "string" then
        entry.targetInfo = readGlobal("GetPlayerInfoByGUID", target)
    else
        entry.targetInfo = "<guid not readable>"
    end
    local log = db().log
    log[#log + 1] = entry
    while #log > LOG_CAP do table.remove(log, 1) end
end

-- PLAYER_DEAD: the last few death recap events, source and spell names only.
local function recordDeathRecap(entry)
    if not (C_DeathRecap and C_DeathRecap.HasRecapEvents and C_DeathRecap.GetRecapEvents) then
        entry.recap = "unavailable"
        return
    end
    local has = readNs("C_DeathRecap", "HasRecapEvents")
    entry.hasRecap = has
    if has ~= true then return end
    local ok, events = pcall(C_DeathRecap.GetRecapEvents)
    if not ok then entry.recap = "error: " .. tostring(events) return end
    if isSecret(events) or type(events) ~= "table" then entry.recap = SECRET return end
    local out = {}
    local total = #events
    for i = math.max(1, total - DEATH_RECAP_EVENTS + 1), total do
        local ev = events[i]
        local row = {}
        for _, field in ipairs({ "sourceName", "spellName" }) do
            local fok, v = pcall(function() return ev[field] end)
            row[field] = fok and safe(v) or ("error: " .. tostring(v))
        end
        out[#out + 1] = row
    end
    entry.recap = { total = total, last = out }
end

-- Once per match, while it is active: hand the player's killingBlows straight
-- to SetText on a hidden FontString without reading it. The docs say SetText
-- takes secret Text arguments; this finds out whether that holds in practice.
local displayTestDone = false
local displayFontString
local function secretDisplayTest()
    if displayTestDone then return end
    if readNs("C_PvP", "IsMatchActive") ~= true then return end
    displayTestDone = true
    local rec = { t = time(), gt = GetTime() }
    local ok, err = pcall(function()
        if not (C_PvP and C_PvP.GetScoreInfoByPlayerGuid) then error("C_PvP.GetScoreInfoByPlayerGuid unavailable") end
        local guid = UnitGUID("player")
        if isSecret(guid) then error("player guid is secret") end
        local info = C_PvP.GetScoreInfoByPlayerGuid(guid)
        if type(info) ~= "table" then error("no score row") end
        if not displayFontString then
            local holder = CreateFrame("Frame", "HonorLogProbeDisplayTest", UIParent)
            holder:Hide()
            displayFontString = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        end
        rec.valueWasSecret = isSecret(info.killingBlows)
        displayFontString:SetText(info.killingBlows)
    end)
    rec.setTextOK = ok
    if not ok then rec.error = tostring(err) end
    local p = db()
    p.secretDisplay = p.secretDisplay or {}
    p.secretDisplay[#p.secretDisplay + 1] = rec
    while #p.secretDisplay > 10 do table.remove(p.secretDisplay, 1) end
end

local function isTrackedCurrency(id)
    if isSecret(id) then return true end -- log it: the secrecy is itself a finding
    for _, tracked in ipairs(CURRENCY_IDS) do
        if tracked == id then return true end
    end
    return false
end

local function onEvent(_, event, ...)
    if event == "CURRENCY_DISPLAY_UPDATE" then
        local currencyType = ...
        if currencyType ~= nil and not isTrackedCurrency(currencyType) then return end
        push(event, ...)
    elseif event == "PARTY_KILL" then
        onPartyKill(...)
    elseif event == "PLAYER_DEAD" then
        local entry = push(event)
        recordDeathRecap(entry)
    elseif event == "PVP_MATCH_ACTIVE" then
        displayTestDone = false
        push(event, ...)
        secretDisplayTest()
    elseif event == "UPDATE_BATTLEFIELD_SCORE" then
        secretDisplayTest()
        if watch and not watch.record.firstReadable
            and watch.eventAttempts < SCOREBOARD_MAX_EVENT_ATTEMPTS then
            watch.eventAttempts = watch.eventAttempts + 1
            recordAttempt("UPDATE_BATTLEFIELD_SCORE #" .. watch.eventAttempts)
        end
        local now = GetTime()
        if now - lastScoreLog >= UPDATE_SCORE_THROTTLE then
            lastScoreLog = now
            push(event, ...)
        end
    elseif event == "PVP_MATCH_COMPLETE" then
        push(event, ...)
        local winner, duration = ...
        Probe:BeginScoreboardWatch(winner, duration)
    elseif event == "BAG_UPDATE_DELAYED" then
        local entry = push(event)
        entry.marks = markCounts()
    elseif event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" then
        onQuestWindow(event)
    elseif event == "QUEST_TURNED_IN" then
        onQuestTurnedIn(...)
    else
        push(event, ...)
    end
end

function Probe:RegisterEvents()
    frame = frame or CreateFrame("Frame", "HonorLogProbeFrame")
    frame:SetScript("OnEvent", onEvent)
    local registered, failed = 0, {}
    for _, event in ipairs(EVENTS) do
        if RESTRICTED_EVENTS[event] then
            failed[#failed + 1] = event .. " (" .. SKIPPED .. ")"
        elseif pcall(frame.RegisterEvent, frame, event) then
            registered = registered + 1
        else
            failed[#failed + 1] = event
        end
    end
    db().registered = registered
    db().registerFailed = failed
    return registered, failed
end

function Probe:UnregisterEvents()
    if frame then frame:UnregisterAllEvents() end
end

function Probe:SetArmed(armed)
    local p = db()
    p.armed = armed and true or false
    if armed then
        local registered, failed = self:RegisterEvents()
        say("Probe armed: " .. registered .. " events registered"
            .. (#failed > 0 and (", not registered: " .. table.concat(failed, ", ")) or "") .. ".")
    else
        self:UnregisterEvents()
        say("Probe disarmed.")
    end
end

-- Called from ADDON_LOADED, after the saved variables exist.
function Probe:Init()
    local p = db()
    if p.armed then self:RegisterEvents() end
end

--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------

function Probe:HandleCommand(arg)
    arg = (arg or ""):lower()
    local p = db()
    if arg == "on" then
        self:SetArmed(true)
    elseif arg == "off" then
        self:SetArmed(false)
    elseif arg == "clear" then
        p.log = {}
        p.scoreboard = {}
        watch = nil
        say("Probe log and scoreboard attempts cleared.")
    elseif arg == "status" then
        local quests, pvpQuests = 0, 0
        for _, rec in pairs(p.quests or {}) do
            quests = quests + 1
            if rec.pvp then pvpQuests = pvpQuests + 1 end
        end
        say("Probe armed: " .. tostring(p.armed == true) .. ", log entries: " .. #p.log
            .. "/" .. LOG_CAP .. ", scoreboard watches: " .. #(p.scoreboard or {})
            .. ", snapshot: " .. (p.snapshot and "yes" or "no")
            .. ", quests seen: " .. quests .. " (" .. pvpQuests .. " paid honor, rank points or marks)")
    else
        self:TakeSnapshot()
        say("Probe snapshot saved to HonorLogDB.probe.snapshot (written to disk on /reload or logout).")
        say("Use /honorlog probe on to log events passively, off to stop.")
    end
end
