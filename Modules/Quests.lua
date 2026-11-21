-- HonorLog Quests
-- What the PvP quests pay and where they are handed in, always on, and the list the Quests screen draws.
--
-- The quest ids come from Data/Quests.lua (generated). What a quest pays is not in any data an addon can read,
-- so it is measured: when a quest's hand-in window opens (QUEST_COMPLETE) the module reads honor, rank points,
-- marks and money and notes where the player stands and who they are talking to; when the quest is handed in
-- (QUEST_TURNED_IN) it reads again a moment later and stores the difference in HonorLogDB.questRewards[id]. A
-- value that could not be measured is left out, never guessed. A hand-in without the window has nothing to
-- compare with and is only counted.
--
-- Client functions and events used (Forever API documentation, build 1.60.1.71037, none flagged HasRestrictions):
-- events QUEST_COMPLETE, QUEST_TURNED_IN; C_QuestLog.GetTitleForQuestID, IsOnQuest, IsComplete,
-- ReadyForTurnIn, GetQuestObjectives, IsQuestFlaggedCompleted. GetQuestID, GetTitleText and the other
-- quest-window globals are not in the documentation: they are called only behind Util.call.
-- Every answer is checked for secrecy and type (Util.num, Util.str) before it is used.

local _, HonorLog = ...
HonorLog = HonorLog or {}

local Quests = {}
HonorLog.Quests = Quests

local Util = HonorLog.Util
local num, str, call = Util.num, Util.str, Util.call
local isSecret = Util.isSecret

local HONOR_CURRENCY = 1792
local RANK_FACTION = 2800
local KEPT = 400        -- quests kept in the store, oldest hand-in dropped first
local SETTLE = 1.5      -- seconds after a hand-in before the rewards are measured
local WINDOW = 120      -- seconds a hand-in window's reading stays usable

Quests.KEPT = KEPT

-- Battleground keys in display order, then the two groups that belong to none.
Quests.BG_KEYS = { "AV", "WSG", "AB", "DI", "ALL", "SEASON" }
local BG_RANK = {}
for i, key in ipairs(Quests.BG_KEYS) do BG_RANK[key] = i end

local STATE_RANK = { ready = 1, log = 2, open = 3, done = 4 }

local function markItems()
    return HonorLog.BG_MARK_ITEMS or {}
end

--------------------------------------------------------------------------------
-- The shared read
--------------------------------------------------------------------------------

-- The player's honor, rank points as one running total, money and each battleground's marks, as plain numbers;
-- a value the client does not give, or gives as a secret, is nil. Used here and by the probe.
function Quests.ReadState()
    local state = { marks = {} }
    local info = C_CurrencyInfo and call(C_CurrencyInfo.GetCurrencyInfo, HONOR_CURRENCY)
    if type(info) == "table" and not isSecret(info) then state.honor = num(info.quantity) end

    local progress = C_MajorFactions and call(C_MajorFactions.GetMajorFactionProgressionInfo, RANK_FACTION)
    if type(progress) == "table" and not isSecret(progress) then
        local level, earned = num(progress.renownLevel), num(progress.renownReputationEarned)
        local curve = HonorLog.Rank
        if level and earned then
            state.rank = ((curve and curve.TotalForRank) and curve:TotalForRank(level) or 0) + earned
        end
    end

    state.money = GetMoney and num(call(GetMoney)) or nil
    for bg, itemID in pairs(markItems()) do
        local count = C_Item and num(call(C_Item.GetItemCount, itemID, true))
        if count then state.marks[bg] = count end
    end
    return state
end

--------------------------------------------------------------------------------
-- The store
--------------------------------------------------------------------------------

local function store()
    if type(HonorLogDB) ~= "table" then return nil end
    if type(HonorLogDB.questRewards) ~= "table" then HonorLogDB.questRewards = {} end
    return HonorLogDB.questRewards
end

-- The stored record of a quest, or nil.
function Quests:GetPaid(id)
    local s = type(HonorLogDB) == "table" and HonorLogDB.questRewards
    local rec = type(s) == "table" and s[id]
    if type(rec) == "table" then return rec end
end

local function trim(s)
    local ids = {}
    for id in pairs(s) do ids[#ids + 1] = id end
    if #ids <= KEPT then return end
    table.sort(ids, function(a, b)
        local la, lb = num(s[a].last) or 0, num(s[b].last) or 0
        if la ~= lb then return la < lb end
        return a < b
    end)
    for i = 1, #ids - KEPT do s[ids[i]] = nil end
end

local function playerLevel()
    return num(call(UnitLevel, "player"))
end

-- A hand-in seen: the record is made if need be, counted and dated.
local function touch(s, id)
    local rec = s[id]
    if type(rec) ~= "table" then
        rec = { count = 0 }
        s[id] = rec
    end
    rec.count = (num(rec.count) or 0) + 1
    rec.last = time()
    rec.level = playerLevel() or rec.level
    return rec
end

-- Where the player stands and who they are talking to, each only when the client gives it.
local function readPlace()
    local place = {}
    local loc = HonorLog.ReadVendorLocation and call(HonorLog.ReadVendorLocation, HonorLog)
    if type(loc) == "table" then
        for _, key in ipairs({ "npc", "map", "x", "y", "zone", "subzone" }) do
            if loc[key] ~= nil then place[key] = loc[key] end
        end
    end
    place.name = Util.unitName("npc")
    if next(place) then return place end
end

--------------------------------------------------------------------------------
-- Hand-ins
--------------------------------------------------------------------------------

local before -- { id, gt, state, place }: the reading taken when a hand-in window opened

-- The window of a quest being handed in is open: read where things stand.
function Quests:OnQuestComplete()
    local id = num(call(_G.GetQuestID))
    if not id or id == 0 then return end
    before = { id = id, gt = GetTime(), state = Quests.ReadState(), place = readPlace() }
end

-- What changed between two readings, as what the quest paid: only gains, only what both readings had.
local function measure(was, now)
    local paid = { marks = {} }
    if was.honor and now.honor and now.honor > was.honor then paid.honor = now.honor - was.honor end
    if was.rank and now.rank and now.rank > was.rank then paid.rank = now.rank - was.rank end
    for bg, count in pairs(now.marks) do
        local old = was.marks[bg]
        if old and count > old then paid.marks[bg] = count - old end
    end
    return paid
end

local function pays(paid)
    return paid.honor ~= nil or paid.rank ~= nil or next(paid.marks) ~= nil
end

-- Writes what a measured hand-in paid into the quest's record; only what was measured replaces what is kept.
local function apply(rec, paid, xp, money, place)
    rec.honor = paid.honor or rec.honor
    rec.rank = paid.rank or rec.rank
    if next(paid.marks) then
        rec.marks = type(rec.marks) == "table" and rec.marks or {}
        for bg, n in pairs(paid.marks) do rec.marks[bg] = n end
    end
    rec.money = money or rec.money
    rec.xp = xp or rec.xp
    if place and next(place) then rec.place = place end
end

-- The quest was handed in. xp and money are the event's own numbers.
function Quests:OnQuestTurnedIn(id, xp, money)
    id, xp, money = num(id), num(xp), num(money)
    if not id then return end
    if xp and xp <= 0 then xp = nil end
    if money and money <= 0 then money = nil end
    local s = store()
    if not s then return end
    local listed = HonorLog.QuestDB and HonorLog.QuestDB[id] ~= nil
    local reading = before
    before = nil
    if not (reading and reading.id == id and GetTime() - reading.gt <= WINDOW) then reading = nil end

    local counted = false
    if listed then
        touch(s, id)
        counted = true
        trim(s)
    end
    if not reading then return end

    C_Timer.After(SETTLE, function()
        local now = Quests.ReadState()
        local paid = measure(reading.state, now)
        local moneyPaid = money
        if not moneyPaid and reading.state.money and now.money and now.money > reading.state.money then
            moneyPaid = now.money - reading.state.money
        end
        -- a quest the list does not know is learned only when it paid honor, rank points or marks
        if not (listed or pays(paid)) then return end
        local live = store()
        if not live then return end
        local rec = live[id]
        if type(rec) ~= "table" or not counted then
            rec = touch(live, id)
        end
        apply(rec, paid, xp, moneyPaid, reading.place)
        trim(live)
        HonorLog:Fire("HonorLog_QuestPaid", id)
    end)
end

local frame = CreateFrame("Frame", "HonorLogQuestsFrame")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "QUEST_COMPLETE" then
        Quests:OnQuestComplete()
    elseif event == "QUEST_TURNED_IN" then
        Quests:OnQuestTurnedIn(...)
    end
end)
for _, event in ipairs({ "QUEST_COMPLETE", "QUEST_TURNED_IN" }) do pcall(frame.RegisterEvent, frame, event) end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

local function bool(v)
    if isSecret(v) or type(v) ~= "boolean" then return nil end
    return v
end

local function questLog(name, id)
    local api = C_QuestLog
    if type(api) ~= "table" or type(api[name]) ~= "function" then return nil end
    return call(api[name], id)
end

-- The log's objectives of a quest as { { text, finished } }, or nil when it is not in the log.
local function readObjectives(id)
    local list = questLog("GetQuestObjectives", id)
    if type(list) ~= "table" or isSecret(list) then return {} end
    local out = {}
    for _, o in ipairs(list) do
        if type(o) == "table" and not isSecret(o) then
            local text = str(o.text)
            if text and text ~= "" then out[#out + 1] = { text = text, finished = bool(o.finished) == true } end
        end
    end
    return out
end

local function playerFaction()
    return str((call(UnitFactionGroup, "player")))
end

-- The season's current week from the rank data, or nil.
local function currentWeek()
    local info = HonorLog.Rank and HonorLog.Rank:GetInfo()
    return info and num(info.weekNumber) or nil
end

-- A quest with a level is in the player's ten-level range (10-19 ... 50-59, 60 alone).
local function inRange(questLevel, level)
    if not level then return true end
    return math.floor(questLevel / 10) == math.floor(level / 10)
end

local function placeOf(paid, title)
    local p = type(paid) == "table" and paid.place
    if type(p) ~= "table" then return nil end
    local map, x, y = num(p.map), num(p.x), num(p.y)
    if not (map and x and y) then return nil end
    return { map = map, x = x, y = y, name = str(p.name) or title, npc = num(p.npc), detail = str(p.zone), kind = "place" }
end

-- filters: bg ("all", a battleground key or "other"), levels ("mine" or "all"). Returns the rows for the player's
-- faction and the quests with none, in the order the screen draws them.
function Quests:GetList(filters)
    filters = type(filters) == "table" and filters or {}
    local bgFilter = filters.bg or "all"
    local allLevels = filters.levels == "all"
    local faction = playerFaction()
    local level = playerLevel()
    local week = currentWeek()

    local rows = {}
    for id, q in pairs(HonorLog.QuestDB or {}) do
        local mine = q.faction == nil or q.faction == faction
        local wanted = bgFilter == "all" or q.bg == bgFilter or (bgFilter == "other" and (q.bg == "ALL" or q.bg == "SEASON"))
        if mine and wanted and (q.kind ~= "weekly" or (week and q.week <= week)) then
            local inLog = questLog("IsOnQuest", id) == true
            local done = questLog("IsQuestFlaggedCompleted", id) == true
            local paid = Quests:GetPaid(id)
            if allLevels or not q.level or inLog or done or paid or inRange(q.level, level) then
                local title = str(questLog("GetTitleForQuestID", id))
                if not title or title == "" then title = q.name end
                local ready = inLog and (questLog("ReadyForTurnIn", id) == true or questLog("IsComplete", id) == true) or false
                rows[#rows + 1] = {
                    id = id, bg = q.bg, level = q.level, kind = q.kind, week = q.week, title = title,
                    inLog = inLog, ready = ready, done = done,
                    objectives = inLog and readObjectives(id) or nil,
                    paid = paid, place = placeOf(paid, title),
                    state = ready and "ready" or inLog and "log" or done and "done" or "open",
                }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.state ~= b.state then return STATE_RANK[a.state] < STATE_RANK[b.state] end
        if a.bg ~= b.bg then return (BG_RANK[a.bg] or 99) < (BG_RANK[b.bg] or 99) end
        local la, lb = a.level or 1000, b.level or 1000
        if la ~= lb then return la < lb end
        local ta, tb = a.title:lower(), b.title:lower()
        if ta ~= tb then return ta < tb end
        return a.id < b.id
    end)
    return rows
end

-- How many rows of each state a list has.
function Quests:GetCounts(list)
    local counts = { ready = 0, log = 0, open = 0, done = 0 }
    for _, row in ipairs(list or {}) do counts[row.state] = (counts[row.state] or 0) + 1 end
    return counts
end
