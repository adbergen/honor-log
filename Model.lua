-- HonorLog Model
-- View models: plain functions that turn saved data and client reads into the tables the screens show.
-- Nothing here builds a frame. Every function returns nil or an empty list on missing data instead of
-- raising, reads client values through Util.call with number/secret checks, and puts player-facing
-- sentences through HonorLog.L. The comment above each function states its return shape; the windows
-- treat those comments as the contract.
--
-- The 2.1 screens' readers, in the section at the end: GetCharacterRows, FindPlayers, GetHonorDaysBetween and
-- GetWeekRankReason.
--
-- Loaded after the Modules (it uses HonorLog.Rank) and before the UI files. Rates are percents (0-100),
-- the way GetDerivedStats reports them, and a win rate counts decided games only: draws and games
-- left early are not in it.

local _, HonorLog = ...
HonorLog = HonorLog or {}

local Util = HonorLog.Util
local num, str, call = Util.num, Util.str, Util.call
local L = HonorLog.L

local DAY = 86400
local HONOR_DAYS_KEPT = 60 -- days of per-day honor the character store keeps
local SEQUENCE_LENGTH = 10 -- results in a battleground's recent sequence
local BEST_BG_MIN_GAMES = 3

local function db() return HonorLog.db end

local function commas(n)
    n = math.floor((tonumber(n) or 0) + 0.5)
    local s, k = tostring(n), 0
    repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
end

local function playerFaction() return str(call(UnitFactionGroup, "player")) end
local function playerClass() return str(select(2, call(UnitClass, "player"))) end

-- The history list of a scope: "account" or "character"; the saved view mode when scope is nil.
local function historyFor(scope)
    local d = db()
    if not d then return {} end
    scope = scope or (d.settings and d.settings.viewMode)
    return (scope == "account" and d.global.history or d.char.history) or {}
end

--------------------------------------------------------------------------------
-- Goal texts (moved from UI/GoalsPanel.lua; both windows use them)
--------------------------------------------------------------------------------
local GOLD_HEX, RANK_HEX = "e6cc80", "c8a0ff"
local TICK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t"
local CROSS = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t"

-- Hex colour of a Rank tag ("level", "nopoints", ...), or the fallback.
local function TagHex(tag, fallback)
    local c = HonorLog.RANK_TAG_COLORS and HonorLog.RANK_TAG_COLORS[tag]
    if type(c) ~= "table" then return fallback end
    return string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- 12,345 copper -> "1g", 150 -> "1s", 3 -> "3c" (whole units; the exact price is in the tooltip).
function HonorLog:GoldShort(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper >= 10000 then return BreakUpLargeNumbers(math.floor(copper / 10000)) .. "g" end
    if copper >= 100 then return math.floor(copper / 100) .. "s" end
    return copper .. "c"
end

-- Returns text. GoalRowText(row, factor): one requirement as coloured text; factor (0..1) scales the
-- counted amounts for the fill animation.
function HonorLog:GoalRowText(row, factor)
    factor = factor or 1
    local done = "40d860"
    if row.kind == "honor" then
        local current = math.floor(row.current * factor)
        return string.format("|cff%s%s/%s Honor|r", current >= row.needed and done or "ffd700",
            BreakUpLargeNumbers(current), BreakUpLargeNumbers(row.needed))
    elseif row.kind == "marks" then
        local current = math.floor(row.current * factor)
        return string.format("|cff%s%d/%d|r |T%s:14:14:0:0|t", current >= row.needed and done or (HonorLog.BG_COLOR_HEX[row.bg] or "55bbff"),
            current, row.needed, HonorLog.BG_ICONS[row.bg] or "")
    elseif row.kind == "gold" then
        local current = math.floor(row.current * factor)
        return string.format("|cff%s%s/%s|r", current >= row.needed and done or GOLD_HEX, self:GoldShort(current), self:GoldShort(row.needed))
    elseif row.kind == "rank" then
        return string.format("|cff%sRank %s/%d|r", row.met and done or RANK_HEX, row.current and tostring(row.current) or "?", row.needed)
    elseif row.kind == "level" then
        return string.format("|cff%s%s|r", row.met and done or TagHex("level", RANK_HEX),
            string.format(L["Level %d / %d"], row.current or 0, row.needed))
    elseif row.kind == "rep" then
        local need = row.standingName or tostring(row.needed)
        if row.faction and row.known then
            local have = HonorLog.STANDING_NAMES[row.current] or "Unknown"
            if row.amount and row.ceiling and not row.met then
                return string.format("|cff7fc8ff%s %s / %s|r", have, BreakUpLargeNumbers(row.amount), BreakUpLargeNumbers(row.ceiling))
            end
            return string.format("|cff%s%s/%s|r", row.met and done or "7fc8ff", have, need)
        end
        return string.format("|cff9aa5b5%s reputation|r", need)
    end
    return ""
end

-- GoalCurrencyLine(gp, factor): the goal's currency requirements as one coloured line (text).
function HonorLog:GoalCurrencyLine(gp, factor)
    local parts = {}
    for _, row in ipairs(gp.rows) do
        if (row.kind == "honor" or row.kind == "gold") then
            if row.needed > 0 then parts[#parts + 1] = self:GoalRowText(row, factor) end
        elseif row.kind == "level" then
            if not row.met then parts[#parts + 1] = self:GoalRowText(row, factor) end -- shown only while unmet
        else
            parts[#parts + 1] = self:GoalRowText(row, factor)
        end
    end
    return table.concat(parts, " |cff666666·|r ")
end

-- GetGoalPercent(gp): 0-100 number.
-- Weighted share of honor, marks and gold in hand. Rank and reputation have no amounts, so they only hold
-- the bar just under full.
function HonorLog:GetGoalPercent(gp)
    local needed, current = 0, 0
    for _, row in ipairs(gp.rows) do
        local weight = row.kind == "honor" and 1 or row.kind == "marks" and 100 or row.kind == "gold" and 0.001 or nil
        if weight and row.needed > 0 then
            needed = needed + row.needed * weight
            current = current + math.min(row.current, row.needed) * weight
        end
    end
    local percent = needed > 0 and current / needed * 100 or 100
    if not gp.isComplete then percent = math.min(percent, 99) end
    return percent
end

-- GoalMissingText(gp): text.
-- What else is short, as plain words ("800 honor, 10 AV marks"), for the status line.
function HonorLog:GoalMissingText(gp)
    local out = {}
    for _, row in ipairs(gp.missing) do
        if row.kind == "honor" then out[#out + 1] = string.format("%s honor", BreakUpLargeNumbers(row.remaining))
        elseif row.kind == "marks" then out[#out + 1] = string.format("%d %s marks", row.remaining, row.bg)
        elseif row.kind == "gold" then out[#out + 1] = self:GoldShort(row.remaining)
        elseif row.kind == "rep" then out[#out + 1] = string.format("%s reputation", row.standingName or "standing") end
    end
    return table.concat(out, ", ")
end

-- GoalReadyText(gp): the status line text ("Ready to purchase", rank and level waits, ready date).
function HonorLog:GoalReadyText(gp)
    if gp.isComplete then return "|cff40d860Ready to purchase|r" end
    local pieces = {}
    local level = gp.level
    local levelUnmet = level and level.known and not level.met
    if levelUnmet then
        pieces[#pieces + 1] = string.format("|cff%s%s|r", TagHex("level", RANK_HEX), string.format(L["Ready at level %d"], level.needed))
    end
    local rank = gp.rank
    if rank and not rank.met then
        if rank.known and rank.limitedBy == "cap" and rank.week then
            pieces[#pieces + 1] = string.format("|cff%sRank %d locked until week %d|r", RANK_HEX, rank.needed, rank.week)
        elseif rank.known and rank.date then
            pieces[#pieces + 1] = string.format("|cff%sRank %d · %s|r", RANK_HEX, rank.needed, HonorLog.Rank.FormatDate(rank.date))
        elseif rank.known and rank.plan and (rank.limitedBy == "level" or rank.limitedBy == "nopoints") then
            pieces[#pieces + 1] = string.format("|cff%sRank %d · %s|r", TagHex(rank.limitedBy, RANK_HEX), rank.needed, HonorLog.Rank.PlanWhen(rank.plan))
        elseif rank.known then
            pieces[#pieces + 1] = string.format("|cff%sRank %d not reachable this season|r", RANK_HEX, rank.needed)
        else
            pieces[#pieces + 1] = string.format("|cff%sRank %d|r", RANK_HEX, rank.needed)
        end
    end
    if levelUnmet then
        local others = self:GoalMissingText(gp)
        if others ~= "" then pieces[#pieces + 1] = string.format("|cff9aa5b5%s|r", string.format(L["also needs %s"], others)) end
    elseif gp.readyDate then
        pieces[#pieces + 1] = string.format("|cffb4c8e0ready %s%s|r", gp.estimated and "~" or "on ", HonorLog.Rank.FormatDate(gp.readyDate))
    elseif gp.readyLimitedBy == "norep" and gp.readyText then
        pieces[#pieces + 1] = string.format("|cff888888%s|r", gp.readyText)
    elseif gp.readyLimitedBy == "nopace" then
        pieces[#pieces + 1] = "|cff888888play a game for a date|r"
    end
    return table.concat(pieces, " |cff666666·|r ")
end

local PART_LABEL = { blue = "Blue piece", seal = "Seal" }

-- GoalPartText(part): one part (blue piece or Seal) of an epic as coloured text.
function HonorLog:GoalPartText(part)
    local label = PART_LABEL[part.role] or "Part"
    if part.owned then
        return string.format("%s |cff40d860%s owned|r", TICK, label)
    end
    local cost = {}
    if part.honor > 0 then cost[#cost + 1] = BreakUpLargeNumbers(part.honor) .. " honor" end
    for _, bgType in ipairs(HonorLog.BG_ORDER) do
        local n = part.marks and part.marks[bgType]
        if n then cost[#cost + 1] = n .. " " .. bgType end
    end
    return string.format("%s |cffe0a050%s|r |cff9aa5b5%s|r", CROSS, label, table.concat(cost, ", "))
end


--------------------------------------------------------------------------------
-- A. Today
--------------------------------------------------------------------------------

-- "YYYYMMDD" in local time for a timestamp (now by default).
function HonorLog:GetDayKey(t)
    return date("%Y%m%d", t or time())
end

-- The saved games of one calendar day (dayKey "YYYYMMDD", local time), newest first, from the history of
-- the scope ("character" or "account"; the saved view mode when nil). A list of the saved entries.
function HonorLog:GetGamesOn(dayKey, scope)
    local out = {}
    for _, g in ipairs(historyFor(scope)) do
        local ts = type(g) == "table" and num(g.timestamp)
        if ts and self:GetDayKey(ts) == dayKey then out[#out + 1] = g end
    end
    return out
end

-- Today's numbers for this character:
-- { dayKey, played, wins, losses, draws, left, duration (seconds in battlegrounds),
--   honor (all honor gained today, battlegrounds and world), honorPerHour (battleground honor per hour of
--   battleground time today; nil when under a minute is on record), rankPoints,
--   rankBlocked ("gate", "cap" or nil: why the rank points are 0), marks = { [bgType] = n }, marksTotal,
--   games (today's saved entries, newest first) }.
-- Games and marks come from the saved games of the calendar day, so the model rolls over at midnight
-- while the player stays online; honor does too, because GetHonorSummary rolls the honor log first.
-- nil before the database exists.
function HonorLog:GetTodayModel()
    if not db() then return nil end
    local dayKey = self:GetDayKey()
    local games = self:GetGamesOn(dayKey, "character")
    local m = { dayKey = dayKey, played = #games, wins = 0, losses = 0, draws = 0, left = 0, duration = 0,
        rankPoints = 0, marks = {}, marksTotal = 0, games = games }
    local gameHonor, gated, capped = 0, false, false
    for _, g in ipairs(games) do
        local result = g.result or (g.win and "win" or "loss")
        if result == "win" then m.wins = m.wins + 1
        elseif result == "loss" then m.losses = m.losses + 1
        elseif result == "draw" then m.draws = m.draws + 1
        elseif result == "left" then m.left = m.left + 1 end
        m.duration = m.duration + (num(g.duration) or 0)
        gameHonor = gameHonor + (num(g.honor) or 0)
        m.rankPoints = m.rankPoints + (num(g.rankPoints) or 0)
        local marks = num(g.marks) or 0
        if marks > 0 and g.bgType then
            m.marks[g.bgType] = (m.marks[g.bgType] or 0) + marks
            m.marksTotal = m.marksTotal + marks
        end
        if g.rankState == "gated" then gated = true elseif g.rankState == "capped" then capped = true end
    end
    local summary = self:GetHonorSummary()
    m.honor = summary and num(summary.today) or 0
    if m.duration >= 60 and gameHonor > 0 then m.honorPerHour = math.floor(gameHonor / (m.duration / 3600)) end
    if m.rankPoints == 0 then
        local info = HonorLog.Rank and HonorLog.Rank:GetInfo()
        if gated or (info and info.gate and info.gate.blocking) then m.rankBlocked = "gate"
        elseif capped or (info and info.capped) then m.rankBlocked = "cap" end
    end
    return m
end

--------------------------------------------------------------------------------
-- B. Advice
--------------------------------------------------------------------------------

-- Battlegrounds with BEST_BG_MIN_GAMES or more games, with their honor per game: { { bgType, name,
-- honorPerGame, played }, ... } best first.
local function comparableBattlegrounds(self)
    local rows = {}
    for bgType, stats in pairs(db().char.battlegrounds or {}) do
        if (stats.played or 0) >= BEST_BG_MIN_GAMES then
            local honor, games = self:UncappedHonor(stats)
            if games > 0 then
                rows[#rows + 1] = { bgType = bgType, name = self:GetBGDisplayName(bgType), honorPerGame = honor / games,
                    played = stats.played }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.honorPerGame ~= b.honorPerGame then return a.honorPerGame > b.honorPerGame end
        return a.bgType < b.bgType
    end)
    return rows
end

-- What to do next, most pressing first: a list (at most `limit`, default 4) of
-- { kind, head (one short sentence), body (one or two more), itemID?, bgType? }. Kinds, in this order, each
-- only when it applies: "gate" (the level gate holds rank points), "cap" (honor near the cap; itemID is
-- what can be bought now), "zero" (a battleground gave no rank points; bgType), "bestbg" (best honor per
-- game, with 3 or more games in at least two battlegrounds; bgType), "unlock" (what the next rank with a
-- reward unlocks; itemID), "nogames" (no games recorded). Empty without data.
function HonorLog:GetAdvice(limit)
    local out = {}
    if not db() then return out end
    limit = num(limit) or 4
    local Rank = HonorLog.Rank
    local info = Rank and Rank:GetInfo()

    if info and info.gate and info.gate.blocking then
        out[#out + 1] = { kind = "gate",
            head = string.format(L["Rank points are on hold until level %d."], info.gate.level),
            body = Rank:GateText(info.gate) }
    end

    -- the cached read: the best recommendation, when it can be bought today and is not a goal yet
    local recommend = HonorLog.Recommend
    local okTop, top = pcall(function() return recommend and (recommend:GetCached(1)) end)
    top = okTop and type(top) == "table" and top[1] or nil
    if top and not (top.buyable and top.itemID and not self:IsGoal(top.itemID)) then top = nil end

    local cap = self:GetHonorCapAdvice()
    if cap then
        local buyable = cap.buyable
        if not buyable or #buyable == 0 then buyable = self:GetBuyableNow(3) end
        local entry = { kind = "cap",
            head = string.format(L["Honor is at %s of %s, so spend it before it is wasted."], commas(cap.current), commas(cap.cap)) }
        if top then
            -- the best upgrade is what to spend it on: one item, so the sentence fits its three lines
            local name = str(top.name) or tostring(top.itemID)
            local body
            if top.empty then
                body = string.format(L["%s is your best upgrade: it fills an empty slot."], name)
            elseif num(top.gain) then
                body = string.format(top.gain == 1 and L["%s is your best upgrade: +%d item level."] or L["%s is your best upgrade: +%d item levels."], name, top.gain)
            end
            if not body or #entry.head + 1 + #body > 135 then body = string.format(L["Buy %s now."], name) end
            entry.itemID, entry.body = top.itemID, body
        elseif buyable and #buyable > 0 then
            -- one name, so the sentence fits its three lines; the Gear goals screen lists them all
            local first = buyable[1].name or tostring(buyable[1].itemID)
            local others = #buyable - 1
            entry.itemID = buyable[1].itemID
            if others == 0 then
                entry.body = string.format(L["You can buy %s now."], first)
            elseif others == 1 then
                entry.body = string.format(L["You can buy %s now, or 1 other item."], first)
            else
                entry.body = string.format(L["You can buy %s now, or %d other items."], first, others)
            end
        elseif cap.goal then
            entry.itemID = cap.goal.itemID
            entry.body = string.format(L["%s is on your goal list and ready to buy."], tostring(cap.goal.name))
        else
            entry.body = cap.text
        end
        out[#out + 1] = entry
    end

    -- the best upgrade, when it can be bought today and is not a goal yet
    if top and not cap then
        local name = str(top.name) or tostring(top.itemID)
        local head = string.format(L["Best upgrade today: %s."], name)
        local body = str(top.reason)
        -- head and body share three lines of about 47 characters: a long reason gives way to the short one
        if not body or #head + #body > 130 then
            if top.empty then
                body = L["Empty slot"]
            elseif num(top.gain) then
                body = string.format(top.gain == 1 and L["+%d item level over what you wear"] or L["+%d item levels over what you wear"], top.gain)
            end
        end
        if body then out[#out + 1] = { kind = "upgrade", itemID = top.itemID, head = head, body = body } end
    end

    local zero = Rank and Rank:GetZeroPointBattlegrounds()[1]
    if zero then
        out[#out + 1] = { kind = "zero", bgType = zero.bgType,
            head = string.format(L["%s has given you no rank points."], zero.name), body = Rank:ZeroPointText(zero) }
    end

    local bgs = comparableBattlegrounds(self)
    if #bgs >= 2 then
        local best, other = bgs[1], bgs[2]
        out[#out + 1] = { kind = "bestbg", bgType = best.bgType,
            head = string.format(L["%s pays the most honor per game."], best.name),
            body = string.format(L["About %s honor a game over %d games, against %s in %s."], commas(best.honorPerGame),
                best.played, commas(other.honorPerGame), other.name) }
    end

    if info then
        for n = info.rank + 1, math.min(info.seasonMaxRank or 14, 14) do
            local item = self:GetRankUnlocks(n)[1]
            if item then
                local name = self:GetGearName(item) or tostring(item)
                local left = math.max(0, Rank:TotalForRank(n) - (info.totalPoints or 0))
                out[#out + 1] = { kind = "unlock", itemID = item,
                    head = string.format(L["Rank %d unlocks %s."], n, name),
                    body = string.format(L["%s rank points to go."], commas(left)) }
                break
            end
        end
    end

    if #db().char.history == 0 then
        out[#out + 1] = { kind = "nogames", head = L["No games recorded yet."],
            body = L["Play a battleground and HonorLog starts measuring honor, marks and rank points."] }
    end

    while #out > limit do out[#out] = nil end
    return out
end

--------------------------------------------------------------------------------
-- C. Why a game paid what it did
--------------------------------------------------------------------------------

-- The rank points of a saved game as words: text, tone. tone is "earned", "blocked" or "unknown".
-- "+100", "+40, then the weekly cap", "0, level 40 needed", "0, weekly cap reached",
-- "0, this battleground gave none", "0, you left early", "not measured". A row saved before rankState
-- existed is "earned" when it gave points and "unknown" otherwise, as Modules/Rank.lua reads it.
function HonorLog:DescribeRankPoints(entry)
    if type(entry) ~= "table" then return L["not measured"], "unknown" end
    local pts = num(entry.rankPoints)
    local state = entry.rankState
    if not state then state = (pts and pts > 0) and "earned" or "unknown" end
    if state == "earned" and pts then
        if entry.rankCappedDuring then return string.format(L["+%d, then the weekly cap"], pts), "earned" end
        return string.format("+%d", pts), "earned"
    elseif state == "capped" then
        return L["0, weekly cap reached"], "blocked"
    elseif state == "gated" then
        local gate = HonorLog.Rank and HonorLog.Rank.LEVEL_GATES and HonorLog.Rank.LEVEL_GATES[1]
        if gate then return string.format(L["0, level %d needed"], gate.level), "blocked" end
        return L["0, level too low"], "blocked"
    elseif state == "zero" then
        if entry.result == "left" then return L["0, you left early"], "blocked" end
        return L["0, this battleground gave none"], "blocked"
    elseif state == "unknown" and pts == 0 then
        return L["0, reason not recorded"], "unknown"
    end
    return L["not measured"], "unknown"
end

-- The honor of a saved game as words (text): "+450 honor", or "+450 honor, played at the honor cap" when
-- honor had stopped counting.
function HonorLog:DescribeHonor(entry)
    if type(entry) ~= "table" then return L["not measured"] end
    local honor = num(entry.honor) or 0
    if entry.honorCapped then return string.format(L["+%d honor, played at the honor cap"], honor) end
    return string.format(L["+%d honor"], honor)
end

--------------------------------------------------------------------------------
-- D. Rank unlocks (the rest of section D is in Modules/Rank.lua)
--------------------------------------------------------------------------------

-- Item ids the gear database lists for rank n (source "RANK") for the player's faction and for both
-- factions, best quality first, then name, then id. A list of ids; empty for an unknown rank.
function HonorLog:GetRankUnlocks(n)
    local out = {}
    n = num(n)
    if not n then return out end
    local faction = playerFaction()
    for itemID, data in pairs(self.GearDB or {}) do
        if data.source == "RANK" and data.rank == n and (not data.faction or data.faction == faction) then
            out[#out + 1] = itemID
        end
    end
    local GearDB = self.GearDB
    table.sort(out, function(a, b)
        local qa, qb = GearDB[a].quality or 0, GearDB[b].quality or 0
        if qa ~= qb then return qa > qb end
        local na, nb = GearDB[a].name or "", GearDB[b].name or ""
        if na ~= nb then return na < nb end
        return a < b
    end)
    return out
end

--------------------------------------------------------------------------------
-- F. Vendors and sets
--------------------------------------------------------------------------------

local function scannedVendor(name)
    local store = type(HonorLogDB) == "table" and HonorLogDB.scannedVendors
    local rec = type(store) == "table" and store[name]
    return type(rec) == "table" and rec or nil
end

local function scannedPlace(rec)
    local zone, sub = str(rec.zone), str(rec.subzone)
    if zone and zone ~= "" and sub and sub ~= "" and sub ~= zone then return sub .. ", " .. zone end
    if sub and sub ~= "" then return sub end
    if zone and zone ~= "" then return zone end
    return nil
end

-- The kind of vendor a scanned (unlisted) vendor is, from the first item it sold: kind, repFaction.
local function scannedVendorKind(self, name)
    local gear = type(HonorLogDB) == "table" and HonorLogDB.scannedGear
    if type(gear) ~= "table" then return nil end
    local ids = {}
    for itemID, rec in pairs(gear) do
        if type(rec) == "table" and rec.npc == name then ids[#ids + 1] = itemID end
    end
    table.sort(ids)
    for _, itemID in ipairs(ids) do
        local kind, rep = self:GetVendorKind(itemID)
        if kind then return kind, rep end
    end
    return nil
end

-- The player's faction's vendors, built-in rows first (table order), then scanned ones the table lacks
-- (by name): { { key (the vendor's name), name, role, kind, place, map, x, y, npc, repFaction,
-- known (true when x and y are known), count (items the player's class can use there) }, ... }.
-- A scan fills the position a built-in row lacks.
function HonorLog:GetVendorList()
    local out = {}
    local faction = playerFaction()
    local listed = {}
    local function add(v)
        v.key, v.known = v.name, type(v.x) == "number" and type(v.y) == "number"
        v.count = #self:GetVendorStock(v, {})
        out[#out + 1] = v
    end
    for _, v in ipairs(self.VENDORS or {}) do
        listed[v.name] = true
        if not faction or v.faction == faction then
            local row = { name = v.name, role = v.role, kind = v.kind, place = v.place, map = v.map, x = v.x, y = v.y,
                npc = v.npc, repFaction = v.repFaction }
            local rec = scannedVendor(v.name)
            if rec and not (row.x and row.y) and num(rec.x) and num(rec.y) then
                row.map, row.x, row.y = num(rec.map) or row.map, rec.x, rec.y
                row.place = scannedPlace(rec) or row.place
            end
            add(row)
        end
    end
    local names = {}
    for name in pairs(type(HonorLogDB) == "table" and type(HonorLogDB.scannedVendors) == "table" and HonorLogDB.scannedVendors or {}) do
        if not listed[name] then names[#names + 1] = name end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local rec = scannedVendor(name)
        if rec then
            local kind, rep = scannedVendorKind(self, name)
            add({ name = name, kind = kind, repFaction = rep, place = scannedPlace(rec), map = num(rec.map),
                x = num(rec.x), y = num(rec.y), npc = rec.npc })
        end
    end
    return out
end

-- Blue piece id -> { itemID (the epic), sealID, rank, honor (the Seal's honor) } for every epic upgrade
-- the database lists.
local function upgradeMap(self)
    local map, epics = {}, {}
    for itemID, data in pairs(self.GearDB or {}) do
        if data.source == "UPGRADE" and type(data.parts) == "table" and data.parts[1] and data.parts[2] then
            epics[#epics + 1] = itemID
        end
    end
    table.sort(epics)
    for _, epicID in ipairs(epics) do
        local data = self.GearDB[epicID]
        local blue, seal = data.parts[1], data.parts[2]
        if not map[blue] then
            local sealItem = self:GetGearItem(seal)
            map[blue] = { itemID = epicID, sealID = seal, rank = data.rank, honor = sealItem and sealItem.honor or 0 }
        end
    end
    return map
end

-- The epic upgrade of a blue piece: { itemID (the epic), sealID, rank, honor (the Seal's honor) }, or nil for an
-- item that has none (an epic, a Seal, anything the database does not list as upgradable).
function HonorLog:GetUpgradeFor(itemID)
    itemID = num(itemID)
    if not itemID then return nil end
    return upgradeMap(self)[itemID]
end

-- Everything a vendor sells that the database knows: one row per item of the vendor's kind (and, for a
-- supply officer, its reputation faction) that the player's faction can buy:
-- { { itemID, name, data (GetGearItem), slot, set (ItemSet id or nil), isGoal, owned, upgrade }, ... },
-- sorted by set id (rows with no set last), then slot order, then name. Items already on the goal list are
-- included (GetPickerItems leaves them out). filters = { class (default the player's; "ALL" for every
-- class), set (id), slot }. A row with source "UPGRADE" is not listed; its blue piece's row carries
-- upgrade = { itemID (the epic), sealID, rank, honor (the Seal's honor) } instead.
function HonorLog:GetVendorStock(vendor, filters)
    local out = {}
    if type(vendor) ~= "table" or not vendor.kind or not db() then return out end
    filters = filters or {}
    local class = filters.class
    if class == nil then class = playerClass() end
    if class == "ALL" then class = nil end
    local upgrades = upgradeMap(self)
    for _, entry in ipairs(self:GetPickerItems({ class = class, slot = filters.slot, keepGoals = true })) do
        local base = entry.data
        local kind, rep = self:GetVendorKind(entry.itemID)
        if base.source ~= "UPGRADE" and kind == vendor.kind and (kind ~= "supply" or rep == vendor.repFaction)
            and (not filters.set or base.set == filters.set) then
            out[#out + 1] = { itemID = entry.itemID, name = entry.name, data = self:GetGearItem(entry.itemID),
                slot = base.slot, set = base.set, isGoal = self:IsGoal(entry.itemID),
                owned = self:IsItemInInventory(entry.itemID), upgrade = upgrades[entry.itemID] }
        end
    end
    local order = {}
    for i, slot in ipairs(self.SLOTS or {}) do order[slot] = i end
    table.sort(out, function(a, b)
        local sa, sb = a.set or math.huge, b.set or math.huge
        if sa ~= sb then return sa < sb end
        local oa, ob = order[a.slot] or 99, order[b.slot] or 99
        if oa ~= ob then return oa < ob end
        if (a.name or "") ~= (b.name or "") then return (a.name or "") < (b.name or "") end
        return a.itemID < b.itemID
    end)
    return out
end

-- The sets present in a vendor's stock for a class (the player's by default; "ALL" for every class):
-- { { id, name, count }, ... } by name. Items with no set are not counted.
function HonorLog:GetVendorSets(vendor, class)
    local counts, out = {}, {}
    for _, row in ipairs(self:GetVendorStock(vendor, { class = class })) do
        if row.set then counts[row.set] = (counts[row.set] or 0) + 1 end
    end
    for id, count in pairs(counts) do
        out[#out + 1] = { id = id, name = (self.GearSets and self.GearSets[id]) or ("Set " .. id), count = count }
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return out
end

--------------------------------------------------------------------------------
-- G. Battlegrounds and honor by day
--------------------------------------------------------------------------------

local SEQUENCE_LETTER = { win = "W", loss = "L", draw = "D", left = "X" }

-- One battleground: { bgType, name, played, wins, losses, draws, left (lifetime counters of the scope;
-- "character" or "account", the saved view mode when nil), winRate (percent; nil with no decided game),
-- honorPerGame (nil with no game; games at the honor cap left out), avgDuration (seconds; nil with no
-- game), sequence (the last 10 saved results, oldest first: "W", "L", "D", or "X" for a game left early),
-- pointsPerWin, pointsPerLoss (measured; nil when not measured; this character's games), marksHeld }.
-- nil without a bgType or database. Reads the stats without creating any.
function HonorLog:GetBattlegroundModel(bgType, scope)
    if not bgType or not db() then return nil end
    scope = scope or db().settings.viewMode
    local all = scope == "account" and db().global.battlegrounds or db().char.battlegrounds
    local stats = all[bgType] or self.NewBGStats()
    local m = { bgType = bgType, name = self:GetBGDisplayName(bgType), played = stats.played or 0, wins = stats.wins or 0,
        losses = stats.losses or 0, draws = stats.draws or 0, left = stats.left or 0 }
    local decided = m.wins + m.losses
    if decided > 0 then m.winRate = m.wins / decided * 100 end
    local honor, games = self:UncappedHonor(stats)
    if games > 0 then m.honorPerGame = honor / games end
    if m.played > 0 then m.avgDuration = (stats.totalDuration or 0) / m.played end

    local newestFirst = {}
    for _, g in ipairs(historyFor(scope)) do
        if g.bgType == bgType then
            newestFirst[#newestFirst + 1] = SEQUENCE_LETTER[g.result or (g.win and "win" or "loss")] or "L"
            if #newestFirst >= SEQUENCE_LENGTH then break end
        end
    end
    m.sequence = {}
    for i = #newestFirst, 1, -1 do m.sequence[#m.sequence + 1] = newestFirst[i] end

    local pace = HonorLog.Rank and HonorLog.Rank:GetPace(bgType)
    if pace then m.pointsPerWin, m.pointsPerLoss = pace.avgWin, pace.avgLoss end
    m.marksHeld = self:GetCurrentMarks(bgType)
    return m
end

-- The character's per-day honor store: { [dayKey] = honor }. Created the first time it is needed and filled
-- once from the saved games' honor for the days it lacks. That back-fill knows battleground honor only
-- (world honor was never saved per day), except today, which takes the honor log's total.
function HonorLog:EnsureHonorDays()
    local char = db() and db().char
    if not char then return nil end
    if type(char.honorDays) ~= "table" then
        local days = {}
        for _, g in ipairs(char.history or {}) do
            local ts, honor = num(g.timestamp), num(g.honor)
            if ts and honor and honor > 0 then
                local key = self:GetDayKey(ts)
                days[key] = (days[key] or 0) + honor
            end
        end
        local log = char.honorLog
        local today = self:GetDayKey()
        if log and tonumber(log.day) == tonumber(today) and (log.today or 0) > (days[today] or 0) then
            days[today] = log.today
        end
        char.honorDays = days
        self:PruneHonorDays()
    end
    return char.honorDays
end

-- Drop days older than 60 days from the per-day store.
function HonorLog:PruneHonorDays()
    local days = db() and db().char and db().char.honorDays
    if type(days) ~= "table" then return end
    local cutoff = self:GetDayKey(time() - HONOR_DAYS_KEPT * DAY)
    for key in pairs(days) do
        if tostring(key) < cutoff then days[key] = nil end
    end
end

-- Add a gain to today in the per-day store (AddHonorGain calls this for every positive honor change).
function HonorLog:NoteHonorDay(amount)
    local days = self:EnsureHonorDays()
    if not days or type(amount) ~= "number" or amount <= 0 then return end
    local key = self:GetDayKey()
    days[key] = (days[key] or 0) + amount
    self:PruneHonorDays()
end

-- Honor gained per day for the last `days` days (default 7), oldest first, today last:
-- { { dayKey, label (the short weekday name, "Today" for today), honor }, ... }. Empty without a database.
function HonorLog:GetHonorByDay(days)
    local out = {}
    local store = self:EnsureHonorDays()
    if not store then return out end
    days = math.max(1, math.floor(num(days) or 7))
    local now = date("*t", time())
    for back = days - 1, 0, -1 do
        -- Noon of the day, so a daylight-saving change cannot move it onto the wrong date.
        local ts = time({ year = now.year, month = now.month, day = now.day - back, hour = 12 })
        local key = self:GetDayKey(ts)
        out[#out + 1] = { dayKey = key, label = back == 0 and L["Today"] or date("%a", ts), honor = store[key] or 0 }
    end
    return out
end

local HOUR_BUCKETS = {
    { key = "night", from = 0, to = 5 },
    { key = "morning", from = 5, to = 12 },
    { key = "afternoon", from = 12, to = 18 },
    { key = "evening", from = 18, to = 24 },
}

-- Win rate by the local hour a game was recorded, four buckets in order: night 0-5, morning 5-12,
-- afternoon 12-18, evening 18-24: { { key, label, played (decided games), wins, winRate (percent; nil when
-- played is 0) }, ... }. Draws and games left early are not counted, as in every win rate here.
function HonorLog:GetWinRateByHour(scope)
    local labels = { night = L["Night"], morning = L["Morning"], afternoon = L["Afternoon"], evening = L["Evening"] }
    local out = {}
    for i, b in ipairs(HOUR_BUCKETS) do out[i] = { key = b.key, label = labels[b.key], played = 0, wins = 0 } end
    for _, g in ipairs(historyFor(scope)) do
        local ts = num(g.timestamp)
        local result = g.result or (g.win and "win" or "loss")
        if ts and (result == "win" or result == "loss") then
            local hour = tonumber(date("%H", ts)) or 0
            for i, b in ipairs(HOUR_BUCKETS) do
                if hour >= b.from and hour < b.to then
                    out[i].played = out[i].played + 1
                    if result == "win" then out[i].wins = out[i].wins + 1 end
                    break
                end
            end
        end
    end
    for _, row in ipairs(out) do
        if row.played > 0 then row.winRate = row.wins / row.played * 100 end
    end
    return out
end

--------------------------------------------------------------------------------
-- C. The 2.1 screens
--------------------------------------------------------------------------------

-- Whole calendar days from `from` to `to` (local time; noon of each day, so daylight saving cannot move one).
local function daysBetween(from, to)
    local a, b = date("*t", from), date("*t", to)
    local ta = time({ year = a.year, month = a.month, day = a.day, hour = 12 })
    local tb = time({ year = b.year, month = b.month, day = b.day, hour = 12 })
    return math.floor((tb - ta) / DAY + 0.5)
end

-- The week line of a character row: text and a tone ("capped", "gate" or "progress"); both nil when there is
-- nothing to say.
local function weekLine(rec)
    local Rank = HonorLog.Rank
    if rec.cappedNow then return L["Capped this week"], "capped" end
    local level, rank = num(rec.level), num(rec.rank)
    if Rank and level and rank then
        local gate = Rank:GetGate(level, rank)
        if gate and gate.blocking then
            return string.format(L["Rank %d needs level %d"], gate.rank, gate.level), "gate"
        end
    end
    local points = num(rec.rankPoints)
    if Rank and rank and points and rank >= 0 and rank < 14 then
        local missing = Rank:TotalForRank(rank + 1) - points
        if missing > 0 then
            return string.format(L["%s points to Rank %d"], commas(missing), rank + 1), "progress"
        end
    end
    return nil, nil
end

-- One row per saved character, from Characters:GetList() (the record's own fields stay: key, name, class,
-- level, rank, rankPoints, honor, marks, current, stub, cappedNow, ...) with the texts a row shows:
-- { lastText ("Playing now", "today", "yesterday", "N days ago"; nil for a stub), rankTitle (for that
-- record's faction; nil without a rank), weekText and weekTone ("capped", "gate" or "progress"; both nil
-- when there is nothing to say), honorCap (the client's cap, nil when unreadable), goalItem (item id) and
-- goalName, goalNote (the current character: GoalReadyText of the first goal; another: "Ready to buy" or
-- "NN% complete"), goalPercent }. A part that cannot be read leaves its fields nil. Empty without a store.
function HonorLog:GetCharacterRows()
    local out = {}
    local Characters = HonorLog.Characters
    if not Characters then return out end
    local ok, list = pcall(Characters.GetList, Characters)
    if not ok or type(list) ~= "table" then return out end
    local cap = num(call(self.GetHonorCap, self))
    local goals
    local now = time()
    for _, rec in ipairs(list) do
        local row = rec
        row.honorCap = cap
        if not rec.stub then
            local seen = num(rec.lastSeen)
            if rec.current then
                row.lastText = L["Playing now"]
            elseif seen then
                local days = daysBetween(seen, now)
                row.lastText = days <= 0 and L["today"] or days == 1 and L["yesterday"] or string.format(L["%d days ago"], days)
            end
            if num(rec.rank) and HonorLog.Rank then
                row.rankTitle = str(call(HonorLog.Rank.TitleForRank, HonorLog.Rank, rec.rank, rec.faction))
            end
            row.weekText, row.weekTone = weekLine(rec)
            local item = num(rec.nextGoal)
            if item then
                row.goalItem = item
                row.goalName = str(call(self.GetGearName, self, item))
                row.goalPercent = num(rec.goalPercent)
                if rec.current then
                    if goals == nil then
                        local gok, all = pcall(self.GetAllGoalsProgress, self)
                        goals = gok and type(all) == "table" and all or false
                    end
                    if goals and goals[1] then
                        local tok, text = pcall(self.GoalReadyText, self, goals[1])
                        if tok and type(text) == "string" and text ~= "" then row.goalNote = text end
                    end
                elseif row.goalPercent then
                    row.goalNote = row.goalPercent >= 100 and L["Ready to buy"] or string.format(L["%d%% complete"], math.floor(row.goalPercent))
                end
            end
        end
        out[#out + 1] = row
    end
    return out
end

-- The same player under a scoreboard name with a realm suffix and without one: the name before the "-", any case.
local function playerKey(name)
    return (name:match("^([^-]+)") or name):lower()
end

-- Players whose name contains `text` (any case), newest first: one row each, merging the battleground
-- store (Met) and the world opponents (the tally of kills and deaths outside battlegrounds). A name with a
-- realm suffix and the same name without one are one player. Rows { name (the one without a suffix when
-- both exist), class, met = { with, withWins, against, againstWins, kbBest, last } or nil, world = { kills,
-- deaths, lastSeen } or nil, last (the newest of the two) }; at most `limit` (default 20). Empty for no text.
function HonorLog:FindPlayers(text, limit)
    text = str(text)
    text = text and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if text == "" or not db() then return {} end
    limit = math.max(0, math.floor(num(limit) or 20))
    local Met = HonorLog.Met
    local part = text:lower()
    local players, keys = {}, {}
    local function player(name)
        local key = playerKey(name)
        local p = players[key]
        if not p then
            p = { name = name }
            players[key] = p
            keys[#keys + 1] = key
        elseif p.name:find("-", 1, true) and not name:find("-", 1, true) then
            p.name = name
        end
        return p
    end
    local function addMet(rec)
        local full = Met and Met:Get(rec.name)
        if not full then return end
        local p = player(rec.name)
        p.class = p.class or str(full.class)
        local m = p.met or { with = 0, withWins = 0, against = 0, againstWins = 0, kbBest = 0, last = 0 }
        for _, k in ipairs({ "with", "withWins", "against", "againstWins" }) do m[k] = m[k] + (num(full[k]) or 0) end
        m.kbBest = math.max(m.kbBest, num(full.kbBest) or 0)
        m.last = math.max(m.last, num(full.last) or 0)
        p.met = m
    end
    local function addWorld(name, opp)
        local p = player(name)
        p.class = p.class or str(opp.class)
        local w = p.world or { kills = 0, deaths = 0, lastSeen = 0 }
        w.kills = w.kills + (num(opp.kills) or 0)
        w.deaths = w.deaths + (num(opp.deaths) or 0)
        w.lastSeen = math.max(w.lastSeen, num(opp.lastSeen) or 0)
        p.world = w
    end

    local opponents = db().char and db().char.opponents
    opponents = type(opponents) == "table" and opponents or {}
    local matched = {}
    if Met then
        for _, rec in ipairs(Met:Search(text, Met.KEPT)) do
            matched[#matched + 1] = rec.name
            addMet(rec)
        end
    end
    for name, opp in pairs(opponents) do
        if type(name) == "string" and type(opp) == "table" and name:lower():find(part, 1, true) then
            matched[#matched + 1] = name
        end
    end
    -- What the other store knows about a matched player, whichever way its name is spelled.
    local byKey = {}
    for name, opp in pairs(opponents) do
        if type(name) == "string" and type(opp) == "table" then
            local key = playerKey(name)
            byKey[key] = byKey[key] or {}
            byKey[key][#byKey[key] + 1] = name
        end
    end
    local seen = {}
    for _, name in ipairs(matched) do
        local key = playerKey(name)
        if not seen[key] then
            seen[key] = true
            for _, oppName in ipairs(byKey[key] or {}) do addWorld(oppName, opponents[oppName]) end
            if Met and not (players[key] and players[key].met) then
                for _, rec in ipairs(Met:Search(key, Met.KEPT)) do
                    if playerKey(rec.name) == key then addMet(rec) end
                end
            end
        end
    end

    local out = {}
    for _, key in ipairs(keys) do
        local p = players[key]
        p.last = math.max(p.met and p.met.last or 0, p.world and p.world.lastSeen or 0)
        out[#out + 1] = p
    end
    table.sort(out, function(a, b)
        if a.last ~= b.last then return a.last > b.last end
        return a.name < b.name
    end)
    for i = #out, limit + 1, -1 do out[i] = nil end
    return out
end

-- Honor per calendar day over a span (start and finish are times; a day counts when its noon lies in
-- [start, finish), so a reset week gives seven): { { dayKey, label (the short weekday name), honor }, ... },
-- oldest first. nil when the span begins before the days the store keeps (60), has no days or there is no store.
function HonorLog:GetHonorDaysBetween(start, finish)
    start, finish = num(start), num(finish)
    if not (start and finish and finish > start) then return nil end
    local store = self:EnsureHonorDays()
    if not store then return nil end
    if self:GetDayKey(start) < self:GetDayKey(time() - HONOR_DAYS_KEPT * DAY) then return nil end
    local first = date("*t", start)
    local out = {}
    for add = 0, 40 do
        local ts = time({ year = first.year, month = first.month, day = first.day + add, hour = 12 })
        if ts >= finish then break end
        if ts >= start then
            local key = self:GetDayKey(ts)
            out[#out + 1] = { dayKey = key, label = date("%a", ts), honor = num(store[key]) or 0 }
        end
    end
    if #out == 0 then return nil end
    return out
end

-- Why a week gave no rank points: "gate" (the level gate held them) or "cap" (the weekly cap was reached),
-- read from the saved games inside the week the way GetTodayModel reads today's. `record` is a week record
-- (Weeks:GetRecap(n).week). nil when the week gave points, has no game that says, or the record is unusable.
function HonorLog:GetWeekRankReason(record)
    if type(record) ~= "table" or not db() or not db().char then return nil end
    local start, finish = num(record.start), num(record.finish)
    if not (start and finish) then return nil end
    local first, last = num(record.rankStart), num(record.rankEnd)
    if first and last and last - first > 0 then return nil end
    local gated, capped, points = false, false, 0
    for _, g in ipairs(db().char.history or {}) do
        local ts = type(g) == "table" and num(g.timestamp)
        if ts and ts >= start and ts < finish then
            points = points + (num(g.rankPoints) or 0)
            if g.rankState == "gated" then gated = true elseif g.rankState == "capped" then capped = true end
        end
    end
    if points > 0 then return nil end
    if gated then return "gate" end
    if capped then return "cap" end
    return nil
end
