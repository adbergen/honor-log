-- HonorLog World Log
-- A record of each kill and death outside battlegrounds, in char.worldLog (newest first, at most 500), so
-- that a later World PvP screen can show today's numbers, the log with filters, where the player fights,
-- all-time totals and the history with one opponent. No screen draws it yet.
--
-- An entry: { t (time), kind ("kill" | "death"), kb (true for a killing blow), name, class, rank (the
-- victim's rank text, from the kill message), honor (what the kill message said the kill gave), map, x, y
-- (percent of the map), zone, subzone }. A value that is unknown, of the wrong type or a secret is left out;
-- a kill nobody could be named for has no name.
--
-- Writing: HonorLog_WorldKill and HonorLog_WorldDeath (fired by HonorLog:RecordWorldKill and
-- RecordWorldDeath, after the counters and the opponents tally have been updated). Each handler runs under
-- pcall and reports to the error handler, so a failure here never reaches the game's events or the counting.
-- The place is read at that moment with HonorLog:ReadVendorLocation, keeping map, x, y, zone and subzone:
-- the client withholds the position inside an instance, and a city or a subzone may have no name.
--
-- Client functions used: none of its own; ReadVendorLocation reads C_Map.GetBestMapForUnit,
-- C_Map.GetPlayerMapPosition, GetRealZoneText and GetSubZoneText (Forever API documentation, build
-- 1.60.1.71037, none flagged HasRestrictions). Nothing here leaves the player's computer.

local _, HonorLog = ...
HonorLog = HonorLog or {}

local WorldLog = {}
HonorLog.WorldLog = WorldLog

local Util = HonorLog.Util
local num, str, call = Util.num, Util.str, Util.call
local isSecret = Util.isSecret

local KEPT = 500
local DEFAULT_LIMIT = 100

WorldLog.KEPT = KEPT

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

local function char()
    local c = HonorLog.db and HonorLog.db.char
    return type(c) == "table" and c or nil
end

-- The list, made if need be.
local function store(c)
    if type(c.worldLog) ~= "table" then c.worldLog = {} end
    return c.worldLog
end

local function nonEmpty(v)
    v = str(v)
    if v and v ~= "" then return v end
    return nil
end

--------------------------------------------------------------------------------
-- Writing
--------------------------------------------------------------------------------

-- Where the player stands now: map, x, y, zone, subzone, each only when the client gives it.
local function readPlace(entry)
    local loc = HonorLog.ReadVendorLocation and call(HonorLog.ReadVendorLocation, HonorLog)
    if type(loc) ~= "table" or isSecret(loc) then return end
    entry.map, entry.x, entry.y = num(loc.map), num(loc.x), num(loc.y)
    entry.zone, entry.subzone = nonEmpty(loc.zone), nonEmpty(loc.subzone)
end

local function add(kind, source)
    local c = char()
    if not c then return end
    local entry = { t = time(), kind = kind }
    if type(source) == "table" and not isSecret(source) then
        entry.name, entry.class = nonEmpty(source.name), nonEmpty(source.class)
        if kind == "kill" then
            if not isSecret(source.kb) and source.kb == true then entry.kb = true end
            entry.rank, entry.honor = nonEmpty(source.rank), num(source.honor)
        end
    end
    readPlace(entry)
    local list = store(c)
    table.insert(list, 1, entry)
    while #list > KEPT do table.remove(list) end
end

function WorldLog:OnKill(entry) add("kill", entry) end
function WorldLog:OnDeath(entry) add("death", entry) end

HonorLog.RegisterCallback(WorldLog, "HonorLog_WorldKill", guarded(function(_, entry) WorldLog:OnKill(entry) end))
HonorLog.RegisterCallback(WorldLog, "HonorLog_WorldDeath", guarded(function(_, entry) WorldLog:OnDeath(entry) end))

-- Empties the log (a character's reset).
function WorldLog:Reset()
    local c = char()
    if c then c.worldLog = {} end
end

--------------------------------------------------------------------------------
-- Readers
--------------------------------------------------------------------------------

-- The entries that are usable: tables with a number for a time, newest first as saved.
local function entries()
    local c = char()
    local out = {}
    for _, e in ipairs(c and type(c.worldLog) == "table" and c.worldLog or {}) do
        if type(e) == "table" and num(e.t) then out[#out + 1] = e end
    end
    return out
end

local function whereOf(e)
    local sub, zone = nonEmpty(e.subzone), nonEmpty(e.zone)
    if sub and zone and sub ~= zone then return sub .. ", " .. zone end
    return sub or zone
end

local function row(e)
    local r = {}
    for k, v in pairs(e) do r[k] = v end
    r.where = whereOf(e)
    if num(e.map) and num(e.x) and num(e.y) then
        r.place = { map = e.map, x = e.x, y = e.y, name = nonEmpty(e.name) or HonorLog.L["Unknown player"],
                    detail = r.where, kind = "place" }
    end
    return r
end

local function limitOf(limit)
    limit = num(limit)
    if limit and limit >= 0 then return math.floor(limit) end
    return DEFAULT_LIMIT
end

-- Today (calendar day, local time) in numbers. deathZones: the zones of today's deaths, each once, in the
-- order they happened.
function WorldLog:GetToday()
    local today = HonorLog:GetDayKey()
    local out = { kills = 0, killingBlows = 0, deaths = 0, honor = 0, named = 0, deathZones = {} }
    local list = entries()
    local seen = {}
    for i = #list, 1, -1 do -- oldest first, for the order of the zones
        local e = list[i]
        if HonorLog:GetDayKey(e.t) == today then
            if e.kind == "kill" then
                out.kills = out.kills + 1
                if e.kb == true then out.killingBlows = out.killingBlows + 1 end
                out.honor = out.honor + (num(e.honor) or 0)
                if nonEmpty(e.name) then out.named = out.named + 1 end
            elseif e.kind == "death" then
                out.deaths = out.deaths + 1
                local zone = nonEmpty(e.zone)
                if zone and not seen[zone] then
                    seen[zone] = true
                    out.deathZones[#out.deathZones + 1] = zone
                end
            end
        end
    end
    return out
end

-- filters: kind ("all" | "kill" | "death"), name (part of a name, any case), limit (default 100).
function WorldLog:GetList(filters)
    filters = type(filters) == "table" and filters or {}
    local kind = filters.kind
    if kind ~= "kill" and kind ~= "death" then kind = nil end
    local part = nonEmpty(filters.name)
    part = part and part:lower() or nil
    local limit = limitOf(filters.limit)
    local rows = {}
    for _, e in ipairs(entries()) do
        if #rows >= limit then break end
        local name = nonEmpty(e.name)
        if (not kind or e.kind == kind) and (not part or (name and name:lower():find(part, 1, true))) then
            rows[#rows + 1] = row(e)
        end
    end
    return rows
end

-- Where the player fights: { zone, kills, deaths, total }, most fights first, then by name. An entry with
-- no zone is in no row.
function WorldLog:GetZones(limit)
    local by, list = {}, {}
    for _, e in ipairs(entries()) do
        local zone = nonEmpty(e.zone)
        if zone and (e.kind == "kill" or e.kind == "death") then
            local z = by[zone]
            if not z then
                z = { zone = zone, kills = 0, deaths = 0, total = 0 }
                by[zone] = z
                list[#list + 1] = z
            end
            if e.kind == "kill" then z.kills = z.kills + 1 else z.deaths = z.deaths + 1 end
            z.total = z.total + 1
        end
    end
    table.sort(list, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.zone < b.zone
    end)
    limit = num(limit)
    if limit and limit >= 0 then
        for i = #list, math.floor(limit) + 1, -1 do list[i] = nil end
    end
    return list
end

-- All-time counts from the world PvP counters ("character" or "account"; the saved view mode when nil) and
-- the date this character's counting began.
function WorldLog:GetTotals(scope)
    local w = HonorLog.GetWorldPvPStats and HonorLog:GetWorldPvPStats(scope)
    if type(w) ~= "table" then w = {} end
    local c = char()
    return {
        kills = num(w.kills) or 0, deaths = num(w.deaths) or 0, killingBlows = num(w.killingBlows) or 0,
        unknownKills = num(w.unknownKills) or 0, since = c and num(c.since) or nil,
    }
end

-- The history with one opponent: the opponents tally (class, kills, deaths, lastSeen; nil where it has
-- none) and the log's rows with exactly that name, newest first.
function WorldLog:GetWith(name)
    name = nonEmpty(name)
    local out = { name = name, rows = {} }
    if not name then return out end
    local c = char()
    local opp = c and type(c.opponents) == "table" and c.opponents[name]
    if type(opp) == "table" then
        out.class, out.kills, out.deaths, out.lastSeen = str(opp.class), num(opp.kills), num(opp.deaths), num(opp.lastSeen)
    end
    for _, e in ipairs(entries()) do
        if e.name == name then out.rows[#out.rows + 1] = row(e) end
    end
    return out
end
