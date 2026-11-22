-- HonorLog Players Met
-- A small local record of the players the player has played with and against in battlegrounds, in
-- char.met, so that a later screen can show who they win with, who they lose to and the top killers they
-- have faced. No screen draws it yet. Readers: GetCount(), Get(name), GetList(kind, limit, minGames) and
-- Search(part, limit). Nothing here leaves the player's computer.
--
-- A record, filed under the name the scoreboard gave (a name with a realm suffix is a different key from
-- the same name without one): { class, with (games on the player's team), withWins, against (games on the
-- other team), againstWins (the player's wins in those games), kbBest (their most killing blows in one game
-- against the player), last (time of the newest game) }. At most 1,000 players; past that the one seen
-- longest ago is dropped, never one from the game being recorded.
--
-- Writing: HonorLog_GameScoreboard (fired by Core.lua after a game with a readable scoreboard has been saved).
-- The player's own row is found the way the match flow finds it (same name, or the name before the realm
-- suffix). A win counts only for result "win"; a draw counts the game with no win; "left" records nothing.
-- A value that is unknown, of the wrong type or a secret is left out. The handler runs under pcall and
-- reports to the error handler, so a failure here never reaches the game's events or the counting.
--
-- Client functions used: none of its own (Util.unitName reads the player's name). Nothing runs per frame.

local _, HonorLog = ...
HonorLog = HonorLog or {}

local Met = {}
HonorLog.Met = Met

local Util = HonorLog.Util
local num, str = Util.num, Util.str
local isSecret = Util.isSecret

local KEPT = 1000
local DEFAULT_LIMIT = 20

Met.KEPT = KEPT

local function report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
end

local function guarded(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then report(err) end
    end
end

local function char()
    local c = HonorLog.db and HonorLog.db.char
    return type(c) == "table" and c or nil
end

local function store(c)
    if type(c.met) ~= "table" then c.met = {} end
    return c.met
end

local function nonEmpty(v)
    v = str(v)
    if v and v ~= "" then return v end
    return nil
end

-- The same test the match flow uses: the whole name, or the name before a "-realm" suffix.
local function samePlayer(rowName, myName)
    if not rowName or not myName then return false end
    return rowName == myName or rowName:match("^([^-]+)-") == myName
end

local function usableRow(row)
    if type(row) ~= "table" or isSecret(row) then return nil end
    local name, faction = nonEmpty(row.name), num(row.faction)
    if not name or (faction ~= 0 and faction ~= 1) then return nil end
    return name, faction
end

--------------------------------------------------------------------------------
-- Writing
--------------------------------------------------------------------------------

-- Drop the players seen longest ago until the store fits, never one of `current`.
local function prune(list, current)
    local names = {}
    for name in pairs(list) do names[#names + 1] = name end
    local excess = #names - KEPT
    if excess <= 0 then return end
    local candidates = {}
    for _, name in ipairs(names) do
        if not current[name] then
            local rec = list[name]
            candidates[#candidates + 1] = { name = name, last = type(rec) == "table" and num(rec.last) or 0 }
        end
    end
    table.sort(candidates, function(a, b)
        if a.last ~= b.last then return a.last < b.last end
        return a.name < b.name
    end)
    for i = 1, math.min(excess, #candidates) do list[candidates[i].name] = nil end
end

function Met:OnScoreboard(board)
    local c = char()
    if not c or type(board) ~= "table" or isSecret(board) then return end
    local result = str(board.result)
    if result ~= "win" and result ~= "loss" and result ~= "draw" then return end
    local rows, me = board.rows, board.me
    if type(rows) ~= "table" or isSecret(rows) then return end
    local myName, myFaction = usableRow(me)
    if not myName then return end
    local when = num(board.timestamp) or time()
    local mine = Util.unitName("player")
    local win = result == "win"

    local list = store(c)
    local current = {}
    for _, row in ipairs(rows) do
        local name, faction = usableRow(row)
        if name and not current[name] and not samePlayer(name, mine) and not samePlayer(name, myName)
            and not samePlayer(myName, name) then
            current[name] = true
            local rec = list[name]
            if type(rec) ~= "table" then
                rec = { with = 0, withWins = 0, against = 0, againstWins = 0, kbBest = 0 }
                list[name] = rec
            end
            local class = nonEmpty(row.class)
            if class then rec.class = class end
            if faction == myFaction then
                rec.with = (num(rec.with) or 0) + 1
                if win then rec.withWins = (num(rec.withWins) or 0) + 1 end
            else
                rec.against = (num(rec.against) or 0) + 1
                if win then rec.againstWins = (num(rec.againstWins) or 0) + 1 end
                local kb = num(row.kb)
                if kb and kb > (num(rec.kbBest) or 0) then rec.kbBest = kb end
            end
            if when > (num(rec.last) or 0) then rec.last = when end
        end
    end
    prune(list, current)
end

HonorLog.RegisterCallback(Met, "HonorLog_GameScoreboard", guarded(function(_, board) Met:OnScoreboard(board) end))

-- Empties the store (a character's reset).
function Met:Reset()
    local c = char()
    if c then c.met = {} end
end

--------------------------------------------------------------------------------
-- Readers
--------------------------------------------------------------------------------

function Met:GetCount()
    local c = char()
    local n = 0
    for name, rec in pairs(c and type(c.met) == "table" and c.met or {}) do
        if type(name) == "string" and type(rec) == "table" then n = n + 1 end
    end
    return n
end

-- A copy of one player's record, or nil.
function Met:Get(name)
    name = str(name)
    local c = char()
    local rec = name and c and type(c.met) == "table" and c.met[name]
    if type(rec) ~= "table" then return nil end
    return Util.DeepCopy(rec)
end

local function entry(name, rec, kind)
    local games, wins
    if kind == "allies" then
        games, wins = num(rec.with) or 0, num(rec.withWins) or 0
    else
        games, wins = num(rec.against) or 0, num(rec.againstWins) or 0
    end
    if wins > games then wins = games end
    return { name = name, class = nonEmpty(rec.class), games = games, wins = wins,
        rate = games > 0 and wins / games or 0, kbBest = num(rec.kbBest) or 0, last = num(rec.last) or 0 }
end

local ORDER = {
    allies = function(a, b)
        if a.rate ~= b.rate then return a.rate > b.rate end
        if a.games ~= b.games then return a.games > b.games end
        return a.name < b.name
    end,
    rivals = function(a, b)
        if a.rate ~= b.rate then return a.rate < b.rate end
        if a.games ~= b.games then return a.games > b.games end
        return a.name < b.name
    end,
    killers = function(a, b)
        if a.kbBest ~= b.kbBest then return a.kbBest > b.kbBest end
        if a.games ~= b.games then return a.games > b.games end
        return a.name < b.name
    end,
}
local DEFAULT_MIN = { allies = 3, rivals = 3, killers = 1 }

-- kind: "allies" (who the player wins with), "rivals" (who the player loses to) or "killers" (the top
-- killers faced). Rows { name, class, games, wins, rate (0 to 1), kbBest, last }; an unknown kind is empty.
function Met:GetList(kind, limit, minGames)
    local order = ORDER[kind]
    local c = char()
    if not order or not c or type(c.met) ~= "table" then return {} end
    limit = num(limit) or DEFAULT_LIMIT
    minGames = num(minGames) or DEFAULT_MIN[kind]
    local out = {}
    for name, rec in pairs(c.met) do
        if type(name) == "string" and type(rec) == "table" then
            local row = entry(name, rec, kind)
            if row.games >= minGames and row.games > 0 then out[#out + 1] = row end
        end
    end
    table.sort(out, order)
    for i = #out, math.max(0, math.floor(limit)) + 1, -1 do out[i] = nil end
    return out
end

-- The records whose name contains `part` (any case, plain find), newest `last` first, in the rows GetList
-- returns (games and wins count both sides: on the player's team and against). Nothing for an empty part.
function Met:Search(part, limit)
    part = nonEmpty(part)
    local c = char()
    if not part or not c or type(c.met) ~= "table" then return {} end
    part = part:lower()
    limit = num(limit) or DEFAULT_LIMIT
    local out = {}
    for name, rec in pairs(c.met) do
        if type(name) == "string" and type(rec) == "table" and name:lower():find(part, 1, true) then
            local row = entry(name, rec, "allies")
            row.games = row.games + (num(rec.against) or 0)
            row.wins = math.min(row.games, row.wins + (num(rec.againstWins) or 0))
            row.rate = row.games > 0 and row.wins / row.games or 0
            out[#out + 1] = row
        end
    end
    table.sort(out, function(a, b)
        if a.last ~= b.last then return a.last > b.last end
        return a.name < b.name
    end)
    for i = #out, math.max(0, math.floor(limit)) + 1, -1 do out[i] = nil end
    return out
end
