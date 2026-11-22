-- HonorLog World PvP screen
-- The fifth screen of the full window: today's world PvP at a glance (four tiles), the log of every kill and
-- death with who, where and how much honor, the record against the players you meet most, and the places you
-- fight in. Every number comes from Modules/WorldLog.lua (GetToday, GetList, GetZones, GetSpan, GetTotals) and
-- Data.lua (GetTopOpponents); this file only lays them out. Each part guards its own reads, so one failing part
-- leaves the rest drawn, and all the work happens in the screen's Refresh: nothing runs per frame.
--
-- Every place (a Where cell, a zone row) is a Kit:PlaceLink with one fixed key, so clicking rows moves one pin on
-- the map instead of leaving many.
--
-- Staying current: the log is written in the handler of HonorLog_WorldKill / HonorLog_WorldDeath, which runs after
-- the window's own refresh. The screen listens to both events itself and refreshes once on the next tick, only
-- while it is the open screen. It never relies on the order the listeners are called in.
--
-- Widths: a 12 point text is about 6.3 px a character, a 10 point text about 5.2 px. Every text that can outgrow
-- its box is a fixed-width text (the client cuts it with "...") and the cut ones carry their full text in a tooltip.
--
-- Loaded after Battlegrounds. The screen's frame is built the first time its tab is shown.

local _, HonorLog = ...
HonorLog = HonorLog or {}

local Util = HonorLog.Util
local num, str = Util.num, Util.str
local L = HonorLog.L
local Kit = HonorLog.Kit
local Window = HonorLog.Window
local Vendors = HonorLog.GearVendors
local WorldLog = HonorLog.WorldLog or {}

local safe, color, commas, showTooltip = Vendors.safe, Vendors.color, Vendors.commas, Vendors.showTooltip

local PANEL_W, PANEL_H = 868, 490
local GAP = 8
local TILE_W, TILE_H, TILE_STEP = 211, 68, 219
local LOG_X, LOG_Y, LOG_W, LOG_H = 0, 76, 580, 414
local SIDE_X, SIDE_W = 588, 280
local HEAD_Y, HEAD_H = 76, 196
local ZONES_Y, ZONES_H = 280, 210
local ROW_H, MAX_ROWS = 20, 100
local AREA_TOP = 46
local AREA_W = LOG_W - 16 - Kit.SCROLL_BAR_SPACE -- 542
local AREA_H = 16 * 20 -- sixteen whole rows: a row is never cut by the foot
local OPPONENTS, ZONE_ROWS = 4, 6
local INNER_W = SIDE_W - 28 -- 252
local PLACE_KEY = "honorLogWorld" -- the one pin every place on this screen uses

local WorldScreen = {}
HonorLog.WorldScreen = WorldScreen

local function settings() return HonorLog.db and HonorLog.db.settings end

-- The saved kind filter, with anything unknown read as "all" (the fallback is not saved).
local function kindFilter()
    local s = settings()
    local v = s and s.windowWorldKind
    if v == "kill" or v == "death" then return v end
    return "all"
end

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

-- "Nov 5".
local function dayText(ts)
    ts = num(ts)
    if not ts then return nil end
    return date("%b ", ts) .. (tonumber(date("%d", ts)) or "")
end

local function killsText(n) return n == 1 and L["1 kill"] or string.format(L["%d kills"], n) end
local function deathsText(n) return n == 1 and L["1 death"] or string.format(L["%d deaths"], n) end

local function nameOf(r) return type(r) == "table" and str(r.name) or nil end

-- The place a row of the log or a zone is linked to: a position pins it, a map alone opens the zone, nothing
-- is plain text. Every one carries the same key.
local function placeFor(source, label, name)
    local place = type(source.place) == "table" and source.place or nil
    if place then
        place.key = PLACE_KEY
        return place
    end
    return { map = num(source.map), name = name or label, detail = label, kind = "place", key = PLACE_KEY }
end

local function setCell(fs, text, tone)
    fs:SetText(text)
    color(fs, text == "-" and "grey" or (tone or "white"))
end

-- A class token as its word in its colour, a dash when there is none.
local function setClass(fs, token)
    local name, r, g, b = Kit:ClassText(token)
    if name == "" then
        setCell(fs, "-")
        return nil
    end
    fs:SetText(name)
    fs:SetTextColor(r, g, b)
    return name
end

--------------------------------------------------------------------------------
-- The four tiles
--------------------------------------------------------------------------------

local function buildTiles(parent)
    local tiles = {}
    for i = 1, 4 do
        local tile = Kit:NoteTile(parent)
        tile:SetSize(TILE_W, TILE_H)
        tile:SetPoint("TOPLEFT", parent, "TOPLEFT", (i - 1) * TILE_STEP, 0)
        if i == 1 then
            -- the first tile's top left corner is under the window portrait: its texts start past it, the note
            -- too, so the tile keeps one left edge
            local left = 12 + Kit.PORTRAIT_CLEAR
            tile.label:ClearAllPoints()
            tile.label:SetPoint("TOPLEFT", tile, "TOPLEFT", left, -7)
            tile.value:ClearAllPoints()
            tile.value:SetPoint("TOPLEFT", tile, "TOPLEFT", left, -20)
            tile.note:ClearAllPoints()
            tile.note:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", left, 7)
            tile.note:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -8, 7)
            tile.honorLogTipButton:ClearAllPoints()
            tile.honorLogTipButton:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", left - 6, 3)
            tile.honorLogTipButton:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -4, 3)
        end
        tiles[i] = tile
    end
    return tiles
end

local function refreshTiles(tiles)
    local today = safe(WorldLog.GetToday, WorldLog)
    if type(today) ~= "table" then today = {} end
    local kills, blows = num(today.kills) or 0, num(today.killingBlows) or 0
    local deaths, honor, named = num(today.deaths) or 0, num(today.honor) or 0, num(today.named) or 0
    local zones = type(today.deathZones) == "table" and today.deathZones or {}

    local note = L["No killing blows"]
    if blows == 1 then note = L["1 killing blow"] elseif blows > 1 then note = string.format(L["%d killing blows"], blows) end
    Kit:SetNoteTile(tiles[1], L["Kills today"], tostring(kills), note, nil, "white", "grey")

    local deathNote, deathTip = L["No deaths today"], nil
    if deaths > 0 then
        if #zones == 1 then
            deathNote = string.format(L["In %s"], str(zones[1]) or "")
        elseif #zones > 1 then
            deathNote = string.format(L["In %d zones"], #zones)
            deathTip = table.concat(zones, "\n")
        else
            deathNote = L["No place recorded"]
        end
    end
    Kit:SetNoteTile(tiles[2], L["Deaths today"], tostring(deaths), deathNote, deathTip, "white", "grey")

    local honorNote = L["Today, no named kills"]
    if named == 1 then honorNote = L["Today, 1 named kill"] elseif named > 1 then honorNote = string.format(L["Today, %d named kills"], named) end
    Kit:SetNoteTile(tiles[3], L["Honor from kills"], commas(honor), honorNote, nil, "gold", "grey")

    local totals = safe(WorldLog.GetTotals, WorldLog, "character")
    if type(totals) ~= "table" then totals = {} end
    local since = dayText(totals.since)
    Kit:SetNoteTile(tiles[4], L["All time"], string.format("%d - %d", num(totals.kills) or 0, num(totals.deaths) or 0),
        since and string.format(L["Kills and deaths since %s"], since) or L["Kills and deaths"], nil, "white", "grey")
end

--------------------------------------------------------------------------------
-- The kill log
--------------------------------------------------------------------------------

local COLUMNS = {
    { key = "when", title = L["When"], x = 6, w = 96 },
    { key = "result", title = L["Result"], x = 108, w = 44 },
    { key = "player", title = L["Player"], x = 158, w = 140 },
    { key = "class", title = L["Class"], x = 304, w = 50 },
    { key = "where", title = L["Where"], x = 360, w = 136 },
    { key = "honor", title = L["Honor"], x = 502, w = 34, right = true },
}
WorldScreen.COLUMNS = COLUMNS

local function showRowTip(row)
    local r = row.honorLogFight
    if type(r) ~= "table" then return end
    local kill = r.kind == "kill"
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(nameOf(r) or L["Unknown player"], 1, 0.82, 0)
    local className = Kit:ClassText(r.class)
    if className ~= "" then GameTooltip:AddLine(className, 1, 1, 1) end
    local ts = num(r.t)
    if ts then GameTooltip:AddLine(date("%Y-%m-%d %H:%M", ts), 1, 1, 1) end
    GameTooltip:AddLine(kill and L["You killed this player."] or L["This player killed you."], 0.66, 0.64, 0.59, true)
    if kill and r.kb == true then GameTooltip:AddLine(L["Killing blow"], 1, 1, 1, true) end
    local honor = num(r.honor)
    if kill and honor and honor > 0 then GameTooltip:AddLine(string.format(L["%s honor"], commas(honor)), 1, 0.82, 0, true) end
    if str(r.where) then GameTooltip:AddLine(r.where, 0.66, 0.64, 0.59, true) end
    GameTooltip:Show()
end

local function createRow(row)
    row:EnableMouse(true)
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints(row)
    row.stripe:SetColorTexture(1, 1, 1, 0.04)
    row.cells = {}
    for _, c in ipairs(COLUMNS) do
        if c.key == "where" then
            row.place = Kit:PlaceLink(row)
            row.place:SetPoint("LEFT", row, "LEFT", c.x, 0)
            row.none = Kit:FixedText(row, "grey", c.w)
            row.none:SetPoint("LEFT", row, "LEFT", c.x, 0)
            row.none:SetText("-")
        else
            local fs = Kit:FixedText(row, "value", c.w)
            fs:SetPoint("LEFT", row, "LEFT", c.x, 0)
            if c.right then fs:SetJustifyH("RIGHT") end
            row.cells[c.key] = fs
        end
    end
    row:SetScript("OnEnter", showRowTip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function updateRow(row, entry)
    local r, cells = entry.fight, row.cells
    row.honorLogFight = r
    row.stripe:SetShown(entry.index % 2 == 0)
    setCell(cells.when, whenText(r.t), "grey")
    local kill = r.kind == "kill"
    setCell(cells.result, kill and L["Kill"] or L["Death"], kill and "green" or "red")
    local name = nameOf(r)
    setCell(cells.player, name or L["Unknown player"], name and "white" or "grey")
    setClass(cells.class, r.class)
    local where = str(r.where)
    row.place:SetShown(where ~= nil)
    row.none:SetShown(where == nil)
    if where then row.place:SetPlace(placeFor(r, where, name or L["Unknown player"]), (HonorLog.WorldLog and HonorLog.WorldLog:WhereLabel(r)) or where, COLUMNS[5].w) end
    local honor = num(r.honor)
    setCell(cells.honor, kill and honor and honor > 0 and commas(honor) or "-", "gold")
end

local function buildLog(parent, onKind, onSearch)
    local g = {}
    g.inset = Kit:Inset(parent)
    g.inset:SetSize(LOG_W, LOG_H)
    g.inset:SetPoint("TOPLEFT", parent, "TOPLEFT", LOG_X, -LOG_Y)
    local inset = g.inset
    g.title = Kit:Text(inset, "label")
    g.title:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -10)
    g.title:SetText(L["Kill log"])
    g.chips = Kit:Chips(inset, onKind)
    g.chips:SetPoint("TOPLEFT", inset, "TOPLEFT", 80, -7)
    g.search = Kit:SearchBox(inset, L["Search a player or zone"], 200, onSearch)
    g.search:SetPoint("TOPLEFT", inset, "TOPLEFT", 370, -7)

    g.titles = {}
    for i, c in ipairs(COLUMNS) do
        local fs = Kit:FixedText(inset, "labelSmall", c.w)
        fs:SetPoint("TOPLEFT", inset, "TOPLEFT", 8 + c.x, -32)
        if c.right then fs:SetJustifyH("RIGHT") end
        fs:SetText(c.title)
        g.titles[i] = fs
    end

    g.area = Kit:ScrollArea(inset)
    g.area:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -AREA_TOP)
    g.area:SetSize(AREA_W, AREA_H)
    g.stack = Kit:Stack(g.area.honorLogChild, { fight = { create = createRow, update = updateRow } })
    g.empty = Kit:FixedText(inset, "grey", LOG_W - 28)
    g.empty:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -(AREA_TOP + 6))
    g.foot = Kit:FixedText(inset, "grey", LOG_W - 28)
    g.foot:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -376)
    g.hint = Kit:FixedText(inset, "grey", LOG_W - 28)
    g.hint:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -392)
    g.hint:SetText(L["Click a place to see it on your map."])
    return g
end

local function refreshLog(g, searchText)
    local kind = kindFilter()
    g.chips:SetOptions({ { key = "all", text = L["All"] }, { key = "kill", text = L["Kills"] }, { key = "death", text = L["Deaths"] } }, kind)
    local text = searchText ~= "" and searchText or nil
    local matched = safe(WorldLog.GetList, WorldLog, { kind = kind, text = text, limit = WorldLog.KEPT })
    if type(matched) ~= "table" then matched = {} end
    local span = safe(WorldLog.GetSpan, WorldLog)
    local held = type(span) == "table" and num(span.count) or 0

    local entries = {}
    for i = 1, math.min(#matched, MAX_ROWS) do
        if type(matched[i]) == "table" then entries[#entries + 1] = { kind = "fight", height = ROW_H, fight = matched[i], index = #entries + 1 } end
    end
    g.area:honorLogSetContentHeight(g.stack:SetData(entries))

    local any = #matched > 0
    g.empty:SetShown(not any)
    g.hint:SetShown(any)
    if not any then
        g.empty:SetText(held == 0 and L["Nothing here yet. Every kill and death outside a battleground is listed here as it happens."] or L["No fights match."])
        g.foot:SetText("")
    elseif #matched > MAX_ROWS then
        g.foot:SetText(string.format(L["Showing the latest %d of %d fights."], MAX_ROWS, #matched))
    else
        g.foot:SetText(#matched == 1 and L["1 fight"] or string.format(L["%d fights"], #matched))
    end
end

--------------------------------------------------------------------------------
-- Head to head
--------------------------------------------------------------------------------

local OPP_ROW_H = 36

local function showOpponentTip(row)
    local o = row.honorLogOpponent
    if type(o) ~= "table" then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(o.name, 1, 0.82, 0)
    local className = Kit:ClassText(o.class)
    if className ~= "" then GameTooltip:AddLine(className, 1, 1, 1) end
    GameTooltip:AddLine(string.format(L["Your kills: %d"], o.kills), 0.66, 0.64, 0.59, true)
    GameTooltip:AddLine(string.format(L["Their kills: %d"], o.deaths), 0.66, 0.64, 0.59, true)
    if row.honorLogClickable then GameTooltip:AddLine(L["Click to open this player"], 1, 1, 1, true) end
    GameTooltip:Show()
end

local function playersScreen()
    local p = HonorLog.PlayersScreen
    return type(p) == "table" and type(p.Open) == "function" and p or nil
end

local function buildHead(parent)
    local h = {}
    h.inset = Kit:Inset(parent)
    h.inset:SetSize(SIDE_W, HEAD_H)
    h.inset:SetPoint("TOPLEFT", parent, "TOPLEFT", SIDE_X, -HEAD_Y)
    h.header = Kit:Header(h.inset, L["Head to head"])
    h.header:SetPoint("TOPLEFT", h.inset, "TOPLEFT", 14, -8)
    h.header:SetPoint("TOPRIGHT", h.inset, "TOPRIGHT", -14, -8)
    h.rows = {}
    for i = 1, OPPONENTS do
        local row = CreateFrame("Button", nil, h.inset)
        row:SetSize(INNER_W, OPP_ROW_H)
        row:SetPoint("TOPLEFT", h.inset, "TOPLEFT", 14, -30 - (i - 1) * OPP_ROW_H)
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints(row)
        row.hl:SetColorTexture(1, 1, 1, 0.05)
        row.name = Kit:FixedText(row, "value", 128)
        row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
        row.class = Kit:FixedText(row, "value", 56)
        row.class:SetPoint("TOPLEFT", row, "TOPLEFT", 132, -2)
        row.record = Kit:FixedText(row, "value", 60)
        row.record:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
        row.record:SetJustifyH("RIGHT")
        row.bar = Kit:SplitBar(row, INNER_W, 8)
        row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -22)
        row:SetScript("OnEnter", showOpponentTip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            local screen = playersScreen()
            local o = self.honorLogOpponent
            if screen and type(o) == "table" then screen:Open(o.name) end
        end)
        h.rows[i] = row
    end
    h.note = Kit:FixedText(h.inset, "grey", INNER_W)
    h.note:SetPoint("TOPLEFT", h.inset, "TOPLEFT", 14, -178)
    h.note:SetText(L["Green: your kills. Red: their kills."])
    h.empty = Kit:FixedText(h.inset, "grey", INNER_W)
    h.empty:SetPoint("TOPLEFT", h.inset, "TOPLEFT", 14, -36)
    h.empty:SetText(L["The players you fight most will appear here."])
    return h
end

local function refreshHead(h)
    local list = safe(HonorLog.GetTopOpponents, HonorLog, OPPONENTS)
    if type(list) ~= "table" then list = {} end
    local clickable = playersScreen() ~= nil
    local used = 0
    for _, e in ipairs(list) do
        local name = type(e) == "table" and str(e.name) or nil
        if name and used < OPPONENTS then
            used = used + 1
            local row = h.rows[used]
            local kills, deaths = num(e.kills) or 0, num(e.deaths) or 0
            row.honorLogOpponent = { name = name, class = str(e.class), kills = kills, deaths = deaths }
            row.honorLogClickable = clickable
            row.hl:SetShown(clickable)
            row.name:SetText(name)
            row.name:SetTextColor(1, 1, 1)
            setClass(row.class, e.class)
            row.record:SetText(string.format("%d - %d", kills, deaths))
            row.bar:SetCounts(kills, deaths)
        end
    end
    for i, row in ipairs(h.rows) do row:SetShown(i <= used) end
    h.empty:SetShown(used == 0)
    h.note:SetShown(used > 0)
end

--------------------------------------------------------------------------------
-- Where you fight
--------------------------------------------------------------------------------

local ZONE_ROW_H = 22

local function buildZones(parent)
    local z = {}
    z.inset = Kit:Inset(parent)
    z.inset:SetSize(SIDE_W, ZONES_H)
    z.inset:SetPoint("TOPLEFT", parent, "TOPLEFT", SIDE_X, -ZONES_Y)
    z.header = Kit:Header(z.inset, L["Where you fight"])
    z.header:SetPoint("TOPLEFT", z.inset, "TOPLEFT", 14, -8)
    z.header:SetPoint("TOPRIGHT", z.inset, "TOPRIGHT", -14, -8)
    z.rows = {}
    for i = 1, ZONE_ROWS do
        local row = CreateFrame("Frame", nil, z.inset)
        row:SetSize(INNER_W, ZONE_ROW_H)
        row:SetPoint("TOPLEFT", z.inset, "TOPLEFT", 14, -30 - (i - 1) * ZONE_ROW_H)
        row.place = Kit:PlaceLink(row)
        row.place:SetPoint("LEFT", row, "LEFT", 0, 0)
        -- the bar and the count sit on a frame of their own, so their tooltip does not cover the place link
        row.counts = CreateFrame("Frame", nil, row)
        row.counts:SetSize(INNER_W - 138, ZONE_ROW_H)
        row.counts:SetPoint("LEFT", row, "LEFT", 138, 0)
        row.counts:EnableMouse(true)
        row.bar = Kit:Bar(row.counts)
        row.bar:SetSize(80, 8)
        row.bar:SetPoint("LEFT", row.counts, "LEFT", 0, 0)
        row.count = Kit:FixedText(row.counts, "value", 30)
        row.count:SetPoint("RIGHT", row.counts, "RIGHT", 0, 0)
        row.count:SetJustifyH("RIGHT")
        row.counts:SetScript("OnEnter", function(self)
            if not row.honorLogTip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(row.honorLogZone or "", 1, 0.82, 0)
            GameTooltip:AddLine(row.honorLogTip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row.counts:SetScript("OnLeave", function() GameTooltip:Hide() end)
        z.rows[i] = row
    end
    z.foot = Kit:FixedText(z.inset, "grey", INNER_W)
    z.foot:SetPoint("TOPLEFT", z.inset, "TOPLEFT", 14, -190)
    z.empty = Kit:FixedText(z.inset, "grey", INNER_W)
    z.empty:SetPoint("TOPLEFT", z.inset, "TOPLEFT", 14, -36)
    z.empty:SetText(L["The places you fight will appear here."])
    return z
end

local function refreshZones(z)
    local list = safe(WorldLog.GetZones, WorldLog, ZONE_ROWS)
    if type(list) ~= "table" then list = {} end
    local used, top = 0, nil
    for _, e in ipairs(list) do
        local zone = type(e) == "table" and str(e.zone) or nil
        if zone and used < ZONE_ROWS then
            used = used + 1
            local row = z.rows[used]
            local total, kills, deaths = num(e.total) or 0, num(e.kills) or 0, num(e.deaths) or 0
            top = top or math.max(1, total)
            row.honorLogZone = zone
            row.honorLogTip = string.format(L["%s, %s"], killsText(kills), deathsText(deaths))
            row.place:SetPlace(placeFor(e, zone, zone), zone, 130)
            row.bar:SetValue01(total / top)
            row.count:SetText(tostring(total))
        end
    end
    for i, row in ipairs(z.rows) do row:SetShown(i <= used) end
    z.empty:SetShown(used == 0)

    local span = safe(WorldLog.GetSpan, WorldLog)
    local count, oldest = type(span) == "table" and num(span.count) or 0, type(span) == "table" and dayText(span.oldest) or nil
    z.foot:SetShown(count > 0 and oldest ~= nil)
    if count > 0 and oldest then
        if count >= (num(WorldLog.KEPT) or 500) then
            z.foot:SetText(string.format(L["The last %d fights, counted since %s."], count, oldest))
        else
            z.foot:SetText(string.format(L["Fights counted since %s."], oldest))
        end
    end
end

--------------------------------------------------------------------------------
-- The screen
--------------------------------------------------------------------------------

local live, pending = nil, false -- the built screen, and whether a refresh is already waiting for the next tick

local function isOpen()
    return live ~= nil and Window.current == "world" and Window:IsShown() and live:IsShown()
end

local function create(parent)
    local root = CreateFrame("Frame", nil, parent)
    local area = CreateFrame("Frame", nil, root)
    area:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -10)
    area:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, 10)
    area:SetSize(PANEL_W, PANEL_H)

    local tiles, log, head, zones
    local searchText = ""

    -- a filter change goes back to the top of the table and redraws this screen
    local function changed()
        if log then log.area:SetVerticalScroll(0) end
        root:Refresh()
    end

    tiles = buildTiles(area)
    log = buildLog(area, function(key)
        setSetting("windowWorldKind", key)
        changed()
    end, function(text)
        searchText = text
        changed()
    end)
    head = buildHead(area)
    zones = buildZones(area)

    function root:Refresh()
        runSteps({
            function() refreshTiles(tiles) end,
            function() refreshLog(log, searchText) end,
            function() refreshHead(head) end,
            function() refreshZones(zones) end,
        })
    end
    root.honorLogParts = { tiles = tiles, log = log, head = head, zones = zones }
    root.honorLogSearchText = function() return searchText end
    live = root
    return root
end

-- The log is written after the window's own refresh: draw again on the next tick, once, while this is the open screen.
local function onFight()
    if pending or not isOpen() then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        if isOpen() then live:Refresh() end
    end)
end
HonorLog.RegisterCallback(WorldScreen, "HonorLog_WorldKill", onFight)
HonorLog.RegisterCallback(WorldScreen, "HonorLog_WorldDeath", onFight)

Window:RegisterScreen({ key = "world", title = L["World PvP"], order = 5, create = create })
