-- HonorLog Players screen
-- The seventh screen of the full window: "who is this player to me". Left, one scrolling list: who you win
-- with, who you lose to, the top killers you have faced and the players you fight most in the world (or, with
-- text in the search box, the players whose name matches). Right, the whole record with the chosen player: the
-- battleground games on your team and against them, their best killing blows in one game, the world kills and
-- deaths and the latest fights. Every number comes from Modules/Met.lua (GetCount, Get, GetList), Modules/
-- WorldLog.lua (GetWith) and Data.lua / Model.lua (GetTopOpponents, FindPlayers); this file only lays them out.
-- Each part guards its own reads, so one failing part leaves the rest drawn, and all the work happens in the
-- screen's Refresh: nothing runs per frame.
--
-- The rules that are easy to get wrong:
--   * A draw is a game with no win, so battlegrounds read "won 5 of 8 games", never "5 - 3".
--   * kbBest is a player's best killing-blow count in one game on the other team, not kills of you: the label
--     says "most killing blows in one game against your team".
--   * A scoreboard name with a realm suffix and the same name without one are one player here: a lookup tries the
--     whole name, the part before the "-", and any other spelling of the same name either store holds.
--   * The chosen player is the setting windowPlayer; a name nothing knows reads as nobody.
--
-- Staying current: the players-met store is written in the handler of HonorLog_GameScoreboard, which runs after
-- the window's own refresh (the world log likewise for HonorLog_WorldKill / HonorLog_WorldDeath). The screen
-- listens to all three itself and refreshes once on the next tick, only while it is the open screen.
--
-- Places share one fixed pin key, so clicking fights moves one pin on the map. Widths: a 12 point text is about
-- 6.3 px a character, a 10 point text about 5.2 px, a 16 point text about 8.4 px. A text that can outgrow its box
-- is a fixed-width text (the client cuts it with "...") whose full text is in a tooltip. Nothing about other
-- players leaves the computer.
--
-- Loaded after Quests. The screen's frame is built the first time its tab is shown.

local _, HonorLog = ...
HonorLog = HonorLog or {}

local Util = HonorLog.Util
local num, str = Util.num, Util.str
local L = HonorLog.L
local Kit = HonorLog.Kit
local Window = HonorLog.Window
local Vendors = HonorLog.GearVendors

local safe, color, showTooltip = Vendors.safe, Vendors.color, Vendors.showTooltip

local PANEL_W, PANEL_H = 868, 490
local SEARCH_X, SEARCH_Y, SEARCH_W = Kit.PORTRAIT_CLEAR + 8, 2, 220
local COUNT_X, COUNT_Y, COUNT_W = 568, 5, 300
local BODY_Y, BODY_H = 30, 460
local LIST_W = 520
local DETAIL_X, DETAIL_W = 528, 340
local DETAIL_INNER = DETAIL_W - 24 -- 316
local LIST_AREA_W = LIST_W - 12 - Kit.SCROLL_BAR_SPACE -- 486
local LIST_AREA_H = BODY_H - 16 -- 444
local TITLE_H, ROW_H = 22, 24
local GROUP_ROWS, MATCH_ROWS = 5, 30
local FIGHTS = 6
local FIGHT_Y, FIGHT_H = 298, 22
local PLACE_KEY = "honorLogPlayers" -- the one pin every place on this screen uses
local DOT = "\194\183"

-- the list's columns inside the 486 px area: x, width
local COL = {
    name = { 8, 176 }, class = { 190, 56 }, games = { 252, 70 }, bar = { 330, 90 }, value = { 428, 50 },
}

local PlayersScreen = {}
HonorLog.PlayersScreen = PlayersScreen

local function settings() return HonorLog.db and HonorLog.db.settings end

local function setSetting(key, value)
    if HonorLog.SetSetting and settings() then HonorLog:SetSetting(key, value) end
end

local function runSteps(steps)
    for _, step in ipairs(steps) do
        local ok, err = pcall(step)
        if not ok then
            local handler = geterrorhandler and geterrorhandler()
            if handler then handler(err) end
        end
    end
end

local function whenText(ts)
    local bg = HonorLog.BattlegroundsScreen
    if bg and bg.When then return bg.When(ts) end
    ts = num(ts)
    return ts and date("%b %d %H:%M", ts) or "-"
end

local function gamesText(n) return n == 1 and L["1 game"] or string.format(L["%d games"], n) end
local function killingBlowsText(n) return n == 1 and L["1 killing blow"] or string.format(L["%d killing blows"], n) end

-- "won 5 of 8 games": a draw is a game with no win, so this is never a score.
local function wonText(wins, games)
    if games == 1 then return string.format(L["won %d of 1 game"], wins) end
    return string.format(L["won %d of %d games"], wins, games)
end

local function percent(rate) return string.format(L["%d%%"], math.floor((num(rate) or 0) * 100 + 0.5)) end

-- A class token as its word in its colour, a dash when there is none.
local function setClass(fs, token)
    local name, r, g, b = Kit:ClassText(token)
    if name == "" then
        fs:SetText("-")
        color(fs, "grey")
        return nil
    end
    fs:SetText(name)
    fs:SetTextColor(r, g, b)
    return name
end

--------------------------------------------------------------------------------
-- Finding one player in both stores
--------------------------------------------------------------------------------

-- The name before a "-realm" suffix, or nil when there is none.
local function baseOf(name) return name:match("^([^-]+)-") end

-- The same player under a name with a realm suffix and without one: the name before the "-", any case.
local function keyOf(name) return (name:match("^([^-]+)") or name):lower() end

-- Every spelling of a player either store holds: the whole name, the part before the "-", then whatever else
-- shares that part.
local function spellings(name)
    local list, seen = {}, {}
    local function add(n)
        n = str(n)
        if n and n ~= "" and not seen[n] then
            seen[n] = true
            list[#list + 1] = n
        end
    end
    add(name)
    add(baseOf(name))
    local key = keyOf(name)
    local Met = HonorLog.Met
    if Met then
        for _, rec in ipairs(safe(Met.Search, Met, key, Met.KEPT) or {}) do
            if type(rec) == "table" and str(rec.name) and keyOf(rec.name) == key then add(rec.name) end
        end
    end
    for _, o in ipairs(safe(HonorLog.GetTopOpponents, HonorLog, 1000) or {}) do
        if type(o) == "table" and str(o.name) and keyOf(o.name) == key then add(o.name) end
    end
    return list
end

-- The whole record with one player: { name, class, met = { with, withWins, against, againstWins, kbBest, last }
-- or nil, world = { kills, deaths, lastSeen } or nil, rows (the latest fights, newest first) }, or nil when
-- neither store knows the player.
local function playerData(name)
    name = str(name)
    if not name or name == "" then return nil end
    local Met, WorldLog = HonorLog.Met, HonorLog.WorldLog
    local met, world, rows, class = nil, nil, {}, nil
    for _, n in ipairs(spellings(name)) do
        local rec = Met and safe(Met.Get, Met, n)
        if type(rec) == "table" then
            class = class or str(rec.class)
            met = met or { with = 0, withWins = 0, against = 0, againstWins = 0, kbBest = 0, last = 0 }
            for _, k in ipairs({ "with", "withWins", "against", "againstWins" }) do met[k] = met[k] + (num(rec[k]) or 0) end
            met.kbBest = math.max(met.kbBest, num(rec.kbBest) or 0)
            met.last = math.max(met.last, num(rec.last) or 0)
        end
        local w = WorldLog and safe(WorldLog.GetWith, WorldLog, n)
        if type(w) == "table" then
            class = class or str(w.class)
            if num(w.kills) or num(w.deaths) then
                world = world or { kills = 0, deaths = 0, lastSeen = 0 }
                world.kills = world.kills + (num(w.kills) or 0)
                world.deaths = world.deaths + (num(w.deaths) or 0)
                world.lastSeen = math.max(world.lastSeen, num(w.lastSeen) or 0)
            end
            if type(w.rows) == "table" then
                for _, r in ipairs(w.rows) do
                    if type(r) == "table" then rows[#rows + 1] = r end
                end
            end
        end
    end
    if not met and not world and #rows == 0 then return nil end
    table.sort(rows, function(a, b) return (num(a.t) or 0) > (num(b.t) or 0) end)
    return { name = name, class = class, met = met, world = world, rows = rows }
end
PlayersScreen.PlayerData = playerData

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

local GROUP_TITLE = {
    allies = L["Who you win with"], rivals = L["Who you lose to"], killers = L["Top killers you have faced"],
    world = L["Most fought in the world"], matches = L["Matches"],
}

local function showRowTip(row)
    local e = row.honorLogEntry
    if type(e) ~= "table" then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.name, 1, 0.82, 0)
    local className = Kit:ClassText(e.class)
    if className ~= "" then GameTooltip:AddLine(className, 1, 1, 1) end
    if e.group == "allies" then
        GameTooltip:AddLine(string.format(L["On your team: %s"], wonText(e.wins, e.games)), 0.66, 0.64, 0.59, true)
    elseif e.group == "rivals" then
        GameTooltip:AddLine(string.format(L["Against them: %s"], wonText(e.wins, e.games)), 0.66, 0.64, 0.59, true)
    elseif e.group == "killers" then
        GameTooltip:AddLine(string.format(L["Most killing blows in one game against your team: %d"], e.kb), 0.66, 0.64, 0.59, true)
    elseif e.world then
        GameTooltip:AddLine(string.format(L["Your kills: %d"], e.world.kills), 0.66, 0.64, 0.59, true)
        GameTooltip:AddLine(string.format(L["Their kills: %d"], e.world.deaths), 0.66, 0.64, 0.59, true)
    end
    GameTooltip:Show()
end

local function buildList(root, onChoose)
    local inset = Kit:Inset(root)
    inset:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -BODY_Y)
    inset:SetSize(LIST_W, BODY_H)
    local l = { inset = inset }

    l.area = Kit:ScrollArea(inset)
    l.area:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -8)
    l.area:SetSize(LIST_AREA_W, LIST_AREA_H)

    l.empty = Kit:Text(inset, "grey")
    l.empty:SetWidth(LIST_W - 28)
    l.empty:SetWordWrap(true)
    l.empty:SetJustifyV("TOP")
    l.empty:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -14)
    l.empty:Hide()

    l.stack = Kit:Stack(l.area.honorLogChild, {
        title = {
            create = function(row)
                row.text = Kit:FixedText(row, "labelSmall", LIST_AREA_W - 16)
                row.text:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 3)
            end,
            update = function(row, entry) row.text:SetText(entry.text or "") end,
        },
        player = {
            create = function(row)
                Vendors.AddChosenMarks(row)
                local base = num(row:GetFrameLevel()) or 0
                row.name = Kit:FixedText(row, "value", COL.name[2])
                row.name:SetPoint("LEFT", row, "LEFT", COL.name[1], 0)
                row.class = Kit:FixedText(row, "value", COL.class[2])
                row.class:SetPoint("LEFT", row, "LEFT", COL.class[1], 0)
                row.games = Kit:FixedText(row, "value", COL.games[2])
                row.games:SetPoint("LEFT", row, "LEFT", COL.games[1], 0)
                row.bar = Kit:Bar(row)
                row.bar:SetSize(COL.bar[2], 8)
                row.bar:SetPoint("LEFT", row, "LEFT", COL.bar[1], 0)
                row.split = Kit:SplitBar(row, COL.bar[2], 8)
                row.split:SetPoint("LEFT", row, "LEFT", COL.bar[1], 0)
                row.value = Kit:FixedText(row, "value", COL.value[2])
                row.value:SetPoint("LEFT", row, "LEFT", COL.value[1], 0)
                row.value:SetJustifyH("RIGHT")
                -- the click area is the whole row, above its texts: a wash on hover, the tooltip, the choice
                row.click = CreateFrame("Button", nil, row)
                row.click:SetAllPoints(row)
                row.click:SetFrameLevel(base + 4)
                local hl = row.click:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(row.click)
                hl:SetColorTexture(1, 1, 1, 0.07)
                row.click:SetScript("OnClick", function()
                    local e = row.honorLogEntry
                    if e and onChoose then onChoose(e.name) end
                end)
                row.click:SetScript("OnEnter", function() showRowTip(row) end)
                row.click:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end,
            update = function(row, e)
                row.name:SetText(e.name)
                color(row.name, "white")
                setClass(row.class, e.class)
                local mode = e.bar -- "rate", "split" or nil
                row.bar:SetShown(mode == "rate")
                row.split:SetShown(mode == "split")
                if mode == "rate" then row.bar:SetValue01(e.rate) end
                if mode == "split" and e.world then row.split:SetCounts(e.world.kills, e.world.deaths) end
                row.games:SetText(e.gamesText or "")
                row.value:SetText(e.valueText or "")
                Vendors.SetChosen(row, e.chosen)
            end,
        },
    })
    return l
end

-- Rows of the lists the data layer answers, as the entries the stack draws. A row without a usable name is left out.
local function metEntries(group, list)
    local out = {}
    for _, r in ipairs(type(list) == "table" and list or {}) do
        local name = type(r) == "table" and str(r.name) or nil
        -- "Who you win with" means more wins than not, and "Who you lose to" fewer: a group's title must hold for
        -- every row under it, so a 53 percent record is in neither.
        local rate = type(r) == "table" and num(r.rate) or nil
        local fits = true
        if group == "allies" then fits = rate ~= nil and rate > 0.5 elseif group == "rivals" then fits = rate ~= nil and rate < 0.5 end
        if fits and name and name ~= "" and #out < GROUP_ROWS then
            local games, wins = num(r.games) or 0, num(r.wins) or 0
            local e = { kind = "player", height = ROW_H, group = group, name = name, class = str(r.class), games = games, wins = wins,
                rate = num(r.rate) or 0, kb = num(r.kbBest) or 0, gamesText = gamesText(games) }
            if group == "killers" then
                e.valueText = string.format(L["%d KB"], e.kb)
            else
                e.bar, e.valueText = "rate", percent(e.rate)
            end
            out[#out + 1] = e
        end
    end
    return out
end

local function worldEntries(list)
    local out = {}
    for _, r in ipairs(type(list) == "table" and list or {}) do
        local name = type(r) == "table" and str(r.name) or nil
        if name and name ~= "" and #out < GROUP_ROWS then
            local kills, deaths = num(r.kills) or 0, num(r.deaths) or 0
            out[#out + 1] = { kind = "player", height = ROW_H, group = "world", name = name, class = str(r.class), bar = "split",
                world = { kills = kills, deaths = deaths }, gamesText = string.format("%d - %d", kills, deaths) }
        end
    end
    return out
end

local function matchEntries(list)
    local out = {}
    for _, p in ipairs(type(list) == "table" and list or {}) do
        local name = type(p) == "table" and str(p.name) or nil
        if name and name ~= "" and #out < MATCH_ROWS then
            local e = { kind = "player", height = ROW_H, group = "matches", name = name, class = str(p.class) }
            local met = type(p.met) == "table" and p.met or nil
            local world = type(p.world) == "table" and p.world or nil
            local games = met and ((num(met.with) or 0) + (num(met.against) or 0)) or 0
            if games > 0 then
                e.gamesText = gamesText(games)
            elseif world then
                e.world = { kills = num(world.kills) or 0, deaths = num(world.deaths) or 0 }
                e.bar, e.gamesText = "split", string.format("%d - %d", e.world.kills, e.world.deaths)
            end
            out[#out + 1] = e
        end
    end
    return out
end

-- The groups to draw, in order: { { key, entries } }, the empty ones left out.
local function readGroups(searchText)
    local out = {}
    if searchText ~= "" then
        local found = safe(HonorLog.FindPlayers, HonorLog, searchText, MATCH_ROWS)
        local entries = matchEntries(found)
        if #entries > 0 then out[1] = { key = "matches", entries = entries } end
        return out
    end
    local Met = HonorLog.Met
    local function add(key, entries)
        if #entries > 0 then out[#out + 1] = { key = key, entries = entries } end
    end
    runSteps({
        function() add("allies", metEntries("allies", Met and Met:GetList("allies", GROUP_ROWS))) end,
        function() add("rivals", metEntries("rivals", Met and Met:GetList("rivals", GROUP_ROWS))) end,
        function() add("killers", metEntries("killers", Met and Met:GetList("killers", GROUP_ROWS))) end,
        function() add("world", worldEntries(HonorLog:GetTopOpponents(GROUP_ROWS))) end,
    })
    return out
end

local function listEntries(groups, chosenName)
    local out = {}
    for _, g in ipairs(groups) do
        out[#out + 1] = { kind = "title", height = TITLE_H, text = GROUP_TITLE[g.key] }
        for _, e in ipairs(g.entries) do
            e.chosen = chosenName ~= nil and e.name == chosenName
            out[#out + 1] = e
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- The detail
--------------------------------------------------------------------------------

local function buildDetail(root)
    local inset = Kit:Inset(root)
    inset:SetPoint("TOPLEFT", root, "TOPLEFT", DETAIL_X, -BODY_Y)
    inset:SetSize(DETAIL_W, BODY_H)
    local d = { inset = inset, shown = {} }

    local function at(el, x, y)
        el:ClearAllPoints()
        el:SetPoint("TOPLEFT", inset, "TOPLEFT", x, -y)
    end
    -- every part that is drawn per player, so a redraw can hide them all first
    local function track(el)
        d.shown[#d.shown + 1] = el
        return el
    end
    local function text(style, width, x, y, right)
        local fs = track(Kit:FixedText(inset, style, width))
        at(fs, x, y)
        if right then fs:SetJustifyH("RIGHT") end
        return fs
    end
    local function header(label, y)
        local h = track(Kit:Header(inset, label))
        h:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -y)
        h:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -12, -y)
        return h
    end

    d.title = text("title", DETAIL_INNER, 12, 10)
    d.titleHit = track(CreateFrame("Frame", nil, inset))
    d.titleHit:SetSize(DETAIL_INNER, 20)
    at(d.titleHit, 12, 10)
    d.titleHit:EnableMouse(true)
    d.titleHit:SetScript("OnEnter", function(self) showTooltip(self, d.fullName) end)
    d.titleHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.class = text("value", 130, 12, 32)
    d.lastGame = text("grey", 180, 12 + 136, 34, true)

    -- in battlegrounds
    d.bgHeader = header(L["In battlegrounds"], 56)
    d.withLabel = text("labelSmall", 100, 12, 80)
    d.withValue = text("value", 130, 116, 80)
    d.withBar = track(Kit:Bar(inset))
    d.withBar:SetSize(70, 8)
    at(d.withBar, 248, 83)
    d.againstLabel = text("labelSmall", 100, 12, 102)
    d.againstValue = text("value", 130, 116, 102)
    d.againstBar = track(Kit:Bar(inset))
    d.againstBar:SetSize(70, 8)
    at(d.againstBar, 248, 105)
    d.kbLabel = text("grey", DETAIL_INNER, 12, 124)
    d.kbValue = text("value", DETAIL_INNER, 12, 138)
    d.bgNone = text("grey", DETAIL_INNER, 12, 80)

    -- in the world
    d.worldHeader = header(L["In the world"], 180)
    d.yourKills = text("value", 150, 12, 204)
    d.theirKills = text("value", 150, 12 + 166, 204, true)
    d.split = track(Kit:SplitBar(inset, DETAIL_INNER, 8))
    at(d.split, 12, 224)
    d.splitNote = text("grey", DETAIL_INNER, 12, 238)
    d.lastSeen = text("grey", DETAIL_INNER, 12, 256)
    d.worldNone = text("grey", DETAIL_INNER, 12, 204)

    -- the latest fights
    d.fightHeader = header(L["Latest fights"], 274)
    d.fights = {}
    for i = 1, FIGHTS do
        local f = {}
        local y = FIGHT_Y + (i - 1) * FIGHT_H
        f.when = text("grey", 100, 12, y)
        f.result = text("value", 48, 112, y)
        f.place = track(Kit:PlaceLink(inset))
        at(f.place, 164, y - 1)
        f.none = text("grey", 160, 164, y)
        f.none:SetText("-")
        d.fights[i] = f
    end
    d.fightNone = text("grey", DETAIL_INNER, 12, FIGHT_Y)

    d.foot = Kit:FixedText(inset, "grey", DETAIL_INNER)
    d.foot:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 12, 10)
    d.foot:SetText(L["Nothing about other players leaves your computer."])

    d.empty = Kit:Text(inset, "grey")
    d.empty:SetWidth(DETAIL_INNER)
    d.empty:SetWordWrap(true)
    d.empty:SetJustifyV("TOP")
    d.empty:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -14)
    d.empty:SetText(L["Pick a player on the left to see your whole record with them."])
    return d
end

-- The place a fight is linked to: a position pins it, a map alone opens the zone, nothing is plain text. Every
-- one carries the same key.
local function placeFor(r, label, name)
    local place = type(r.place) == "table" and r.place or nil
    if place then
        place.key = PLACE_KEY
        return place
    end
    return { map = num(r.map), name = name or label, detail = label, kind = "place", key = PLACE_KEY }
end

local function setValue(fs, value, tone)
    fs:SetText(value)
    color(fs, tone or "white")
end

local function showBattlegrounds(d, met)
    d.bgHeader:Show()
    if not met or ((num(met.with) or 0) + (num(met.against) or 0)) == 0 then
        d.bgNone:SetText(L["No battleground games with this player yet."])
        d.bgNone:Show()
        return
    end
    local with, withWins = num(met.with) or 0, num(met.withWins) or 0
    local against, againstWins = num(met.against) or 0, num(met.againstWins) or 0
    d.withLabel:SetText(L["On your team"])
    d.withLabel:Show()
    if with > 0 then
        setValue(d.withValue, wonText(math.min(withWins, with), with))
        d.withBar:SetValue01(math.min(withWins, with) / with)
        d.withBar:Show()
    else
        setValue(d.withValue, L["No games on your team"], "grey")
    end
    d.withValue:SetWidth(with > 0 and 130 or 200) -- the sentence takes the bar's room when there is no bar
    d.withValue:Show()
    d.againstLabel:SetText(L["Against them"])
    d.againstLabel:Show()
    if against > 0 then
        setValue(d.againstValue, wonText(math.min(againstWins, against), against))
        d.againstBar:SetValue01(math.min(againstWins, against) / against)
        d.againstBar:Show()
    else
        setValue(d.againstValue, L["No games against them"], "grey")
    end
    d.againstValue:SetWidth(against > 0 and 130 or 200)
    d.againstValue:Show()
    if against > 0 then
        d.kbLabel:SetText(L["Most killing blows in one game against your team"])
        d.kbLabel:Show()
        local kb = num(met.kbBest) or 0
        if kb > 0 then setValue(d.kbValue, killingBlowsText(kb)) else setValue(d.kbValue, L["No killing blows"], "grey") end
        d.kbValue:Show()
    end
end

local function showWorld(d, world)
    d.worldHeader:Show()
    local kills, deaths = world and (num(world.kills) or 0) or 0, world and (num(world.deaths) or 0) or 0
    if kills + deaths == 0 then
        d.worldNone:SetText(L["Never fought outside a battleground."])
        d.worldNone:Show()
        return
    end
    d.yourKills:SetText(string.format(L["Your kills: %d"], kills))
    d.yourKills:Show()
    d.theirKills:SetText(string.format(L["Their kills: %d"], deaths))
    d.theirKills:Show()
    d.split:SetCounts(kills, deaths)
    d.split:Show()
    d.splitNote:SetText(L["Green: your kills. Red: their kills."])
    d.splitNote:Show()
    local seen = num(world.lastSeen)
    if seen and seen > 0 then
        d.lastSeen:SetText(string.format(L["Last seen: %s"], whenText(seen)))
        d.lastSeen:Show()
    end
end

local function showFights(d, rows, name)
    d.fightHeader:Show()
    local used = 0
    for _, r in ipairs(rows) do
        if used < FIGHTS then
            used = used + 1
            local f = d.fights[used]
            f.when:SetText(whenText(r.t))
            f.when:Show()
            local kill = r.kind == "kill"
            setValue(f.result, kill and L["Kill"] or L["Death"], kill and "green" or "red")
            f.result:Show()
            local where = str(r.where)
            f.place:SetShown(where ~= nil)
            f.none:SetShown(where == nil)
            if where then f.place:SetPlace(placeFor(r, where, name), (HonorLog.WorldLog and HonorLog.WorldLog:WhereLabel(r)) or where, 160) end
        end
    end
    if used == 0 then
        d.fightNone:SetText(L["No fights to list yet."])
        d.fightNone:Show()
    end
end

-- Draws the chosen player (data from playerData), or the sentence for nobody.
local function showDetail(d, data)
    for _, el in ipairs(d.shown) do el:Hide() end
    d.fullName = nil
    d.empty:SetShown(data == nil)
    d.foot:Show()
    if not data then return end
    d.fullName = data.name
    d.title:SetText(data.name)
    d.title:Show()
    d.titleHit:Show()
    if setClass(d.class, data.class) then d.class:Show() end
    local last = data.met and num(data.met.last)
    if last and last > 0 then
        d.lastGame:SetText(string.format(L["Last game: %s"], whenText(last)))
        d.lastGame:Show()
    end
    runSteps({
        function() showBattlegrounds(d, data.met) end,
        function() showWorld(d, data.world) end,
        function() showFights(d, data.rows, data.name) end,
    })
end

--------------------------------------------------------------------------------
-- The screen
--------------------------------------------------------------------------------

local live, pending = nil, false -- the built screen, and whether a refresh is already waiting for the next tick

local function isOpen()
    return live ~= nil and Window.current == "players" and Window:IsShown() and live:IsShown()
end

-- Opens the window on this screen with a player chosen. Other screens call this.
function PlayersScreen:Open(name)
    self.request = { name = str(name) }
    Window:Show("players")
    -- the first show already drew it when the client ran the window's OnShow; otherwise draw now
    if self.request and Window.frames.players then Window:RefreshCurrent() end
end

local function create(parent)
    local root = CreateFrame("Frame", nil, parent)
    local area = CreateFrame("Frame", nil, root)
    area:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -10)
    area:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, 10)
    area:SetSize(PANEL_W, PANEL_H)

    local search, count, list, detail
    local searchText = ""
    local groups, chosen = {}, nil -- what the list shows, and the chosen player's record

    local function redrawList()
        local entries = listEntries(groups, chosen and chosen.name)
        list.area:honorLogSetContentHeight(list.stack:SetData(entries))
        if #groups == 0 then
            list.empty:SetText(searchText ~= "" and L["No players match."]
                or L["Players appear here after a battleground whose scoreboard HonorLog could read, and a player needs three games to be ranked."])
        end
        list.empty:SetShown(#groups == 0)
    end

    -- the saved choice, read as nobody when neither store knows the name
    local function readChosen()
        local s = settings()
        local saved = s and str(s.windowPlayer)
        chosen = saved and saved ~= "" and playerData(saved) or nil
    end

    -- a click on a row: the list is drawn again from what is in hand, the detail from the stores
    local function onChoose(name)
        setSetting("windowPlayer", name)
        readChosen()
        runSteps({ redrawList, function() showDetail(detail, chosen) end })
    end

    local function applyRequest()
        local r = PlayersScreen.request
        if not r then return end
        PlayersScreen.request = nil
        searchText = ""
        if search then search:honorLogSetText("") end
        if list then list.area:SetVerticalScroll(0) end
        if r.name then setSetting("windowPlayer", r.name) end
    end

    search = Kit:SearchBox(area, L["Search a player"], SEARCH_W, function(text)
        searchText = text
        list.area:SetVerticalScroll(0)
        root:Refresh()
    end)
    search:SetPoint("TOPLEFT", area, "TOPLEFT", SEARCH_X, -SEARCH_Y)
    count = Kit:FixedText(area, "grey", COUNT_W)
    count:SetPoint("TOPLEFT", area, "TOPLEFT", COUNT_X, -COUNT_Y)
    count:SetJustifyH("RIGHT")
    list = buildList(area, onChoose)
    detail = buildDetail(area)

    function root:Refresh()
        applyRequest()
        runSteps({
            function()
                local Met = HonorLog.Met
                local n = Met and num(Met:GetCount()) or 0
                count:SetText(n == 0 and L["No players met yet"] or (n == 1 and L["1 player met"] or string.format(L["%d players met"], n)))
            end,
            function() groups = readGroups(searchText) end,
            readChosen,
            redrawList,
            function() showDetail(detail, chosen) end,
        })
    end
    root.honorLogParts = { search = search, count = count, list = list, detail = detail }
    root.honorLogSearchText = function() return searchText end
    live = root
    return root
end

-- The stores are written after the window's own refresh: draw again on the next tick, once, while this is the
-- open screen.
local function onChange()
    if pending or not isOpen() then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        if isOpen() then live:Refresh() end
    end)
end
HonorLog.RegisterCallback(PlayersScreen, "HonorLog_GameScoreboard", onChange)
HonorLog.RegisterCallback(PlayersScreen, "HonorLog_WorldKill", onChange)
HonorLog.RegisterCallback(PlayersScreen, "HonorLog_WorldDeath", onChange)

Window:RegisterScreen({ key = "players", title = L["Players"], order = 7, create = create })
