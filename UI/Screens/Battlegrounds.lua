-- HonorLog Battlegrounds screen
-- The fourth screen of the full window: a card per battleground (the record and what a game there is worth),
-- the honor of each of the last seven days, the win rate by time of day, and the table of every recorded game
-- with filters and export. Every number comes from Model.lua (GetBattlegroundModel, GetHonorByDay,
-- GetWinRateByHour, DescribeRankPoints, DescribeHonor) and Data.lua (GetHistory, FormatDuration); this file only
-- lays them out. Each part guards its own reads, so one failing part leaves the rest drawn, and all the work
-- happens in the screen's Refresh: nothing runs per frame.
--
-- Widths: a 12 point text is about 6.3 px a character, a 10 point text about 5.2 px. Every text that can outgrow
-- its box is a fixed-width text (the client cuts it with "...") and the cut ones carry their full text in a tooltip.
--
-- Loaded after Gear. The screen's frame is built the first time its tab is shown.

local _, HonorLog = ...
HonorLog = HonorLog or {}

local Util = HonorLog.Util
local num, str = Util.num, Util.str
local L = HonorLog.L
local Kit = HonorLog.Kit
local Window = HonorLog.Window
local Vendors = HonorLog.GearVendors

local safe, color, commas, showTooltip = Vendors.safe, Vendors.color, Vendors.commas, Vendors.showTooltip

local PANEL_W, PANEL_H = 868, 490
local GAP = 8
local CARD_H, BAND2_H = 132, 120
local BAND3_H = PANEL_H - CARD_H - BAND2_H - 2 * GAP
local DAYS_W = 520
local HOURS_W = PANEL_W - DAYS_W - GAP
local ROW_H, MAX_ROWS, HISTORY_READ = 20, 100, 1000
local MIN_DECIDED = 5
local DAY = 86400

local BgScreen = {}
HonorLog.BattlegroundsScreen = BgScreen

local function settings() return HonorLog.db and HonorLog.db.settings end

local function scope()
    local s = settings()
    return s and s.viewMode == "account" and "account" or "character"
end

local function bgOrder() return HonorLog.BG_ORDER or {} end

-- The saved filters, with anything unknown read as "all" (the fallback is not saved).
local function bgFilter()
    local s = settings()
    local v = s and s.windowBattleground
    for _, bg in ipairs(bgOrder()) do
        if v == bg then return v end
    end
    return "all"
end

local function resultFilter()
    local s = settings()
    local v = s and s.windowResult
    if v == "win" or v == "loss" then return v end
    return "all"
end

local function round(n) return math.floor((num(n) or 0) + 0.5) end

local function gamesText(n)
    return n == 1 and L["1 game"] or string.format(L["%d games"], n)
end

local function resultOf(entry)
    return entry.result or (entry.win and "win" or "loss")
end

-- A number as "184k" or "1.2m" (a dash when the record does not have it).
function BgScreen.Short(n)
    n = num(n)
    if not n then return "-" end
    n = round(n)
    local function trim(x) return (string.format("%.1f", x):gsub("%.0$", "")) end
    if n < 1000 then return tostring(n) end
    if n < 10000 then return trim(n / 1000) .. "k" end
    if n < 1000000 then return string.format("%dk", math.floor(n / 1000)) end
    if n < 10000000 then return trim(n / 1000000) .. "m" end
    return string.format("%dm", math.floor(n / 1000000))
end
local short = BgScreen.Short

-- "Today 21:14", "Yesterday 18:02", else "Nov 18 21:14".
function BgScreen.When(ts)
    ts = num(ts)
    if not ts then return "-" end
    local clock = date("%H:%M", ts)
    local key = HonorLog:GetDayKey(ts)
    if key == HonorLog:GetDayKey() then return string.format(L["Today %s"], clock) end
    local now = date("*t", time())
    -- noon of yesterday, so a daylight-saving change cannot move it onto the wrong date
    local yesterday = time({ year = now.year, month = now.month, day = now.day - 1, hour = 12 })
    if key == HonorLog:GetDayKey(yesterday) then return string.format(L["Yesterday %s"], clock) end
    return date("%b %d ", ts) .. clock
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

--------------------------------------------------------------------------------
-- Band 1: a card per battleground
--------------------------------------------------------------------------------

local CARD_INNER = 191

local function buildCard(parent, bgType, index, count, onClick)
    local cardW = math.floor((PANEL_W - (count - 1) * GAP) / count)
    local c = { bgType = bgType }
    c.root = CreateFrame("Frame", nil, parent)
    c.root:SetSize(cardW, CARD_H)
    c.root:SetPoint("TOPLEFT", parent, "TOPLEFT", (index - 1) * (cardW + GAP), 0)
    c.inset = Kit:Inset(c.root)
    c.inset:SetAllPoints(c.root)
    local base = num(c.inset:GetFrameLevel()) or 0
    -- the click area is made first and sits below the face, so the marks and the sequence on the face keep their tooltips
    c.button = CreateFrame("Button", nil, c.root)
    c.button:SetAllPoints(c.root)
    c.button:SetFrameLevel(base + 2)
    local hl = c.button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(c.button)
    hl:SetColorTexture(1, 1, 1, 0.05)
    c.face = CreateFrame("Frame", nil, c.root)
    c.face:SetAllPoints(c.root)
    c.face:SetFrameLevel(base + 4)
    local face = c.face

    c.wash = face:CreateTexture(nil, "BACKGROUND")
    c.wash:SetAllPoints(face)
    c.wash:SetColorTexture(1, 0.82, 0, 0.1)
    c.wash:Hide()
    c.edges = Kit:Edges(face, 1, 0.82, 0, 1)
    for _, e in ipairs(c.edges) do e:Hide() end

    c.mark = Kit:MarkIcon(face, 20)
    c.mark:SetPoint("TOPLEFT", face, "TOPLEFT", 10, -8)
    c.mark:SetBattleground(bgType)
    c.name = Kit:FixedText(face, "label", 125)
    c.name:SetPoint("TOPLEFT", face, "TOPLEFT", 36, -11)
    c.held = CreateFrame("Frame", nil, face)
    c.held:SetSize(36, 18)
    c.held:SetPoint("TOPRIGHT", face, "TOPRIGHT", -8, -9)
    c.held:EnableMouse(true)
    c.heldText = Kit:FixedText(c.held, "value", 36)
    c.heldText:SetPoint("RIGHT", c.held, "RIGHT", 0, 0)
    c.heldText:SetJustifyH("RIGHT")
    c.held:SetScript("OnEnter", function(self) showTooltip(self, L["In your bags"]) end)
    c.held:SetScript("OnLeave", function() GameTooltip:Hide() end)

    c.none = Kit:FixedText(face, "grey", CARD_INNER)
    c.none:SetPoint("TOPLEFT", face, "TOPLEFT", 10, -38)
    c.none:SetText(L["No games yet."])
    c.record = Kit:FixedText(face, "big", 86)
    c.record:SetPoint("TOPLEFT", face, "TOPLEFT", 10, -30)
    c.extras = Kit:FixedText(face, "grey", 99)
    c.extras:SetPoint("TOPLEFT", face, "TOPLEFT", 102, -38)
    c.seq = Kit:Sequence(face, 10)
    c.seq:SetPoint("TOPLEFT", face, "TOPLEFT", 10, -56)
    c.lines = {}
    for i, label in ipairs({ L["Win rate"], L["Honor a game"], L["Average length"] }) do
        local y = -74 - (i - 1) * 14
        local line = { label = Kit:FixedText(face, "labelSmall", 100), value = Kit:FixedText(face, "value", 91) }
        line.label:SetPoint("TOPLEFT", face, "TOPLEFT", 10, y)
        line.label:SetText(label)
        line.value:SetPoint("TOPLEFT", face, "TOPLEFT", 110, y + 1)
        line.value:SetJustifyH("RIGHT")
        c.lines[i] = line
    end
    c.rank = Kit:FixedText(face, "grey", CARD_INNER)
    c.rank:SetPoint("TOPLEFT", face, "TOPLEFT", 10, -118)

    c.button:SetScript("OnClick", function() onClick(bgType) end)
    c.button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(c.fullName or bgType, 1, 0.82, 0)
        GameTooltip:AddLine(L["Click to show only these games"], 1, 1, 1, true)
        if c.rankText then GameTooltip:AddLine(c.rankText, 0.66, 0.64, 0.59, true) end
        GameTooltip:Show()
    end)
    c.button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return c
end

local function rankSide(value, fmt)
    value = num(value)
    return value and string.format(fmt, round(value)) or L["not measured"]
end

local function refreshCard(c, chosenBg)
    local chosen = chosenBg == c.bgType
    c.wash:SetShown(chosen)
    for _, e in ipairs(c.edges) do e:SetShown(chosen) end
    local m = safe(HonorLog.GetBattlegroundModel, HonorLog, c.bgType, scope())
    c.fullName = m and str(m.name) or str(safe(HonorLog.GetBGDisplayName, HonorLog, c.bgType)) or c.bgType
    c.name:SetText(c.fullName)
    c.heldText:SetText(m and tostring(num(m.marksHeld) or 0) or "")
    local played = m and num(m.played) or 0
    local has = played > 0
    c.none:SetShown(not has)
    c.record:SetShown(has)
    c.extras:SetShown(has)
    c.seq:SetShown(has)
    for _, line in ipairs(c.lines) do
        line.label:SetShown(has)
        line.value:SetShown(has)
    end
    c.rank:SetShown(has)
    c.rankText = nil
    if not has then
        c.seq:SetResults({})
        return
    end
    c.record:SetText(string.format("%d - %d", num(m.wins) or 0, num(m.losses) or 0))
    local extra = {}
    local draws, left = num(m.draws) or 0, num(m.left) or 0
    if draws > 0 then extra[#extra + 1] = draws == 1 and L["1 draw"] or string.format(L["%d draws"], draws) end
    if left > 0 then extra[#extra + 1] = string.format(L["%d left"], left) end
    c.extras:SetText(table.concat(extra, ", "))
    c.seq:SetResults(m.sequence)

    local rate, honor, length = num(m.winRate), num(m.honorPerGame), num(m.avgDuration)
    c.lines[1].value:SetText(rate and string.format("%d%%", round(rate)) or "-")
    c.lines[2].value:SetText(honor and commas(round(honor)) or "-")
    c.lines[3].value:SetText(length and (str(safe(HonorLog.FormatDuration, HonorLog, length)) or "-") or "-")
    for _, line in ipairs(c.lines) do color(line.value, line.value:GetText() == "-" and "grey" or "white") end

    local pw, pl = num(m.pointsPerWin), num(m.pointsPerLoss)
    if pw or pl then
        c.rankText = string.format(L["Rank points: %s, %s"], rankSide(pw, L["%d a win"]), rankSide(pl, L["%d a loss"]))
    else
        c.rankText = L["Rank points not measured yet"]
    end
    c.rank:SetText(c.rankText)
end

--------------------------------------------------------------------------------
-- Band 2: honor by day, best hours
--------------------------------------------------------------------------------

local CHART_W, CHART_H, CHART_BASE = DAYS_W - 28, 84, 14
local BAR_W = 34
local BAR_MAX = CHART_H - CHART_BASE - 14
local GOLD, DIM_GOLD, LINE = { 1, 0.82, 0 }, { 0.55, 0.45, 0.1 }, Kit.COLORS.line

local function buildDays(parent)
    local d = {}
    d.inset = Kit:Inset(parent)
    d.inset:SetSize(DAYS_W, BAND2_H)
    d.inset:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(CARD_H + GAP))
    d.header = Kit:Header(d.inset, L["Honor by day"])
    d.header:SetPoint("TOPLEFT", d.inset, "TOPLEFT", 14, -8)
    d.header:SetPoint("TOPRIGHT", d.inset, "TOPRIGHT", -14 - 176, -8)
    d.total = Kit:FixedText(d.inset, "grey", 170)
    d.total:SetPoint("TOPRIGHT", d.inset, "TOPRIGHT", -14, -11)
    d.total:SetJustifyH("RIGHT")
    d.chart = Kit:Chart(d.inset)
    d.chart:SetSize(CHART_W, CHART_H)
    d.chart:SetPoint("TOPLEFT", d.inset, "TOPLEFT", 14, -28)
    d.empty = Kit:FixedText(d.inset, "grey", CHART_W)
    d.empty:SetPoint("TOPLEFT", d.inset, "TOPLEFT", 14, -44)
    d.empty:SetText(L["No honor in the last 7 days."])
    return d
end

local function refreshDays(d)
    local list = safe(HonorLog.GetHonorByDay, HonorLog, 7) or {}
    local total, top = 0, 0
    for _, day in ipairs(list) do
        local honor = math.max(0, num(day.honor) or 0)
        total, top = total + honor, math.max(top, honor)
    end
    d.chart:Clear()
    local any = total > 0
    d.empty:SetShown(not any)
    d.total:SetShown(any)
    d.chart:SetShown(any)
    if not any then return end
    d.total:SetText(string.format(L["7 days: %s honor"], commas(total)))
    local slot = CHART_W / #list
    d.chart:Rect(0, CHART_BASE - 1, CHART_W, 1, LINE[1], LINE[2], LINE[3], 0.8)
    for i, day in ipairs(list) do
        local honor = math.max(0, num(day.honor) or 0)
        local today = i == #list
        local c = today and GOLD or DIM_GOLD
        local x = (i - 1) * slot + (slot - BAR_W) / 2
        local h = honor > 0 and math.max(2, math.floor(honor / top * BAR_MAX + 0.5)) or 1
        d.chart:Rect(x, CHART_BASE, BAR_W, h, c[1], c[2], c[3], 1)
        if honor > 0 then
            d.chart:Label((i - 1) * slot + slot / 2, CHART_BASE + h + 7, commas(honor), "grey", "CENTER", today and "gold" or "grey")
        end
        d.chart:Label((i - 1) * slot + slot / 2, 6, str(day.label) or "", "grey", "CENTER", today and "gold" or "grey")
    end
end

local HOURS_INNER = HOURS_W - 28
local HOUR_ROW_H = 18

local function buildHours(parent)
    local h = {}
    h.inset = Kit:Inset(parent)
    h.inset:SetSize(HOURS_W, BAND2_H)
    h.inset:SetPoint("TOPLEFT", parent, "TOPLEFT", DAYS_W + GAP, -(CARD_H + GAP))
    h.header = Kit:Header(h.inset, L["Your best hours"])
    h.header:SetPoint("TOPLEFT", h.inset, "TOPLEFT", 14, -8)
    h.header:SetPoint("TOPRIGHT", h.inset, "TOPRIGHT", -14, -8)
    h.rows = {}
    for i = 1, 4 do
        local row = CreateFrame("Frame", nil, h.inset)
        row:SetSize(HOURS_INNER, HOUR_ROW_H)
        row:SetPoint("TOPLEFT", h.inset, "TOPLEFT", 14, -28 - (i - 1) * HOUR_ROW_H)
        row.label = Kit:FixedText(row, "value", 66)
        row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.bar = Kit:Bar(row)
        row.bar:SetSize(96, 10)
        row.bar:SetPoint("LEFT", row, "LEFT", 72, 0)
        row.percent = Kit:FixedText(row, "value", 38)
        row.percent:SetPoint("LEFT", row, "LEFT", 174, 0)
        row.best = Kit:FixedText(row, "label", 30)
        row.best:SetPoint("LEFT", row, "LEFT", 216, 0)
        row.best:SetText(L["best"])
        row.games = Kit:FixedText(row, "grey", 62)
        row.games:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.games:SetJustifyH("RIGHT")
        h.rows[i] = row
    end
    h.foot = Kit:FixedText(h.inset, "grey", HOURS_INNER)
    h.foot:SetPoint("TOPLEFT", h.inset, "TOPLEFT", 14, -28 - 4 * HOUR_ROW_H - 2)
    h.few = Kit:FixedText(h.inset, "grey", HOURS_INNER)
    h.few:SetPoint("TOPLEFT", h.inset, "TOPLEFT", 14, -44)
    h.few:SetText(L["Play a few more games to see your best hours."])
    return h
end

local function refreshHours(h)
    local list = safe(HonorLog.GetWinRateByHour, HonorLog, scope()) or {}
    local decided, best, bestRate = 0, nil, -1
    for i, b in ipairs(list) do
        local played = num(b.played) or 0
        decided = decided + played
        local rate = num(b.winRate)
        if played >= MIN_DECIDED and rate and rate > bestRate then best, bestRate = i, rate end
    end
    local enough = decided >= MIN_DECIDED and #list > 0
    h.few:SetShown(not enough)
    h.foot:SetShown(enough)
    for i, row in ipairs(h.rows) do
        local b = list[i]
        row:SetShown(enough and b ~= nil)
        if enough and b then
            local played, rate = num(b.played) or 0, num(b.winRate)
            row.label:SetText(str(b.label) or "")
            row.bar:SetValue01(rate and rate / 100 or 0)
            row.percent:SetText(rate and played > 0 and string.format("%d%%", round(rate)) or "-")
            color(row.percent, rate and played > 0 and "white" or "grey")
            row.best:SetShown(best == i)
            row.games:SetText(gamesText(played))
        end
    end
    if enough then h.foot:SetText(string.format(L["Win rate by when you played, %d games."], decided)) end
end

--------------------------------------------------------------------------------
-- Band 3: the games table
--------------------------------------------------------------------------------

local COLUMN_GAP, COLUMN_PAD = 6, 6
local COLUMNS = {
    { key = "when", title = L["When"], w = 104 },
    { key = "bg", title = L["Battleground"], w = 88 },
    { key = "result", title = L["Result"], w = 52 },
    { key = "length", title = L["Length"], w = 60, right = true },
    { key = "honor", title = L["Honor"], w = 58, right = true },
    { key = "rank", title = L["Rank pts"], w = 58, right = true },
    { key = "marks", title = L["Marks"], w = 52 },
    { key = "kb", title = L["KB"], w = 44, right = true },
    { key = "hk", title = L["HK"], w = 44, right = true },
    { key = "deaths", title = L["Deaths"], w = 48, right = true },
    { key = "damage", title = L["Damage"], w = 64, right = true },
    { key = "healing", title = L["Healing"], w = 64, right = true },
}
do
    local x = COLUMN_PAD
    for _, c in ipairs(COLUMNS) do
        c.x = x
        x = x + c.w + COLUMN_GAP
    end
end
BgScreen.COLUMNS = COLUMNS

local RESULT_WORD = { win = L["Win"], loss = L["Loss"], draw = L["Draw"], left = L["Left"] }
local RESULT_COLOR = { win = "green", loss = "red", draw = "grey", left = "orange" }

local AREA_W = PANEL_W - 16 - Kit.SCROLL_BAR_SPACE
local AREA_TOP, FOOT_H = 46, 22
local AREA_H = BAND3_H - AREA_TOP - FOOT_H

local function setCell(fs, text, tone)
    fs:SetText(text)
    color(fs, text == "-" and "grey" or (tone or "white"))
end

local function showRowTip(row)
    local entry = row.honorLogEntry
    local g = entry and entry.game
    if not g then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(str(safe(HonorLog.GetBGDisplayName, HonorLog, g.bgType)) or tostring(g.bgType), 1, 0.82, 0)
    local ts = num(g.timestamp)
    if ts then GameTooltip:AddLine(date("%Y-%m-%d %H:%M", ts), 1, 1, 1) end
    local rank = str(safe(HonorLog.DescribeRankPoints, HonorLog, g))
    if rank then GameTooltip:AddLine(rank, 0.66, 0.64, 0.59, true) end
    local honor = str(safe(HonorLog.DescribeHonor, HonorLog, g))
    if honor then GameTooltip:AddLine(honor, 1, 1, 1, true) end
    if g.joinedInProgress then GameTooltip:AddLine(L["Joined in progress"], 1, 0.6, 0.24, true) end
    GameTooltip:Show()
end

local function createRow(row)
    row:EnableMouse(true)
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints(row)
    row.stripe:SetColorTexture(1, 1, 1, 0.04)
    row.cells = {}
    for _, c in ipairs(COLUMNS) do
        local cell
        if c.key == "marks" then
            cell = CreateFrame("Frame", nil, row)
            cell:SetSize(c.w, ROW_H)
            cell:SetPoint("LEFT", row, "LEFT", c.x, 0)
            cell.icon = Kit:MarkIcon(cell, 14)
            cell.icon:SetPoint("LEFT", cell, "LEFT", 0, 0)
            cell.text = Kit:FixedText(cell, "value", c.w - 18)
            cell.text:SetPoint("LEFT", cell, "LEFT", 18, 0)
            row.cells[c.key] = cell
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
    local g, cells = entry.game, row.cells
    row.stripe:SetShown(entry.index % 2 == 0)
    setCell(cells.when, BgScreen.When(g.timestamp), "grey")
    setCell(cells.bg, str(safe(HonorLog.GetBGShortName, HonorLog, g.bgType)) or tostring(g.bgType))
    local result = resultOf(g)
    setCell(cells.result, RESULT_WORD[result] or tostring(result), RESULT_COLOR[result] or "grey")
    local duration = num(g.duration)
    setCell(cells.length, duration and str(safe(HonorLog.FormatDuration, HonorLog, duration)) or "-")
    local honor = num(g.honor)
    setCell(cells.honor, honor and (commas(round(honor)) .. (g.honorCapped and "*" or "")) or "-", "gold")
    local points = num(g.rankPoints)
    local rankText = "-"
    if points then rankText = (points > 0 and "+" or "") .. round(points) end
    setCell(cells.rank, rankText, points and points > 0 and "white" or "orange")
    local marks = num(g.marks)
    cells.marks.icon:SetBattleground(g.bgType)
    cells.marks.icon:SetShown(marks ~= nil)
    setCell(cells.marks.text, marks and tostring(round(marks)) or "-")
    for _, key in ipairs({ "kb", "hk", "deaths", "damage", "healing" }) do setCell(cells[key], short(g[key])) end
end

local function buildGames(parent, onFilter)
    local g = {}
    g.inset = Kit:Inset(parent)
    g.inset:SetSize(PANEL_W, BAND3_H)
    g.inset:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(CARD_H + BAND2_H + 2 * GAP))
    local inset = g.inset
    g.title = Kit:Text(inset, "label")
    g.title:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -10)
    g.title:SetText(L["Games"])

    g.bgChips = Kit:Chips(inset, function(key) onFilter("bg", key) end)
    g.bgChips:SetPoint("TOPLEFT", inset, "TOPLEFT", 72, -7)
    g.resultChips = Kit:Chips(inset, function(key) onFilter("result", key) end)
    g.resultChips:SetPoint("LEFT", g.bgChips, "RIGHT", 16, 0)
    g.scopeChips = Kit:Chips(inset, function(key) onFilter("scope", key) end)
    g.scopeChips:SetPoint("LEFT", g.resultChips, "RIGHT", 16, 0)
    g.export = Kit:Button(inset, L["Export"], "small")
    g.export:SetSize(70, 20)
    g.export:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -8, -7)
    g.export:SetScript("OnClick", function() HonorLog:ShowExportFrame() end)

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
    g.stack = Kit:Stack(g.area.honorLogChild, { game = { create = createRow, update = updateRow } })
    g.empty = Kit:FixedText(inset, "grey", PANEL_W - 28)
    g.empty:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -(AREA_TOP + 6))
    g.foot = Kit:FixedText(inset, "grey", PANEL_W - 28)
    g.foot:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 14, 7)
    return g
end

local function refreshGames(g)
    local bg, result = bgFilter(), resultFilter()
    local bgOptions = { { key = "all", text = L["All"] } }
    for _, key in ipairs(bgOrder()) do
        bgOptions[#bgOptions + 1] = { key = key, text = str(safe(HonorLog.GetBGShortName, HonorLog, key)) or key }
    end
    g.bgChips:SetOptions(bgOptions, bg)
    g.resultChips:SetOptions({ { key = "all", text = L["All"] }, { key = "win", text = L["Wins"] }, { key = "loss", text = L["Losses"] } }, result)
    g.scopeChips:SetOptions({ { key = "character", text = L["This character"] }, { key = "account", text = L["Account"] } }, scope())

    local history = safe(HonorLog.GetHistory, HonorLog, scope(), HISTORY_READ) or {}
    local matched = {}
    for _, game in ipairs(history) do
        if type(game) == "table" and (bg == "all" or game.bgType == bg) and (result == "all" or resultOf(game) == result) then
            matched[#matched + 1] = game
        end
    end
    local entries = {}
    for i = 1, math.min(#matched, MAX_ROWS) do
        entries[i] = { kind = "game", height = ROW_H, game = matched[i], index = i }
    end
    g.area:honorLogSetContentHeight(g.stack:SetData(entries))
    g.rowCount, g.matched = #entries, #matched

    g.empty:SetShown(#matched == 0)
    if #matched == 0 then
        g.empty:SetText(#history == 0 and L["No games recorded yet. HonorLog records every battleground you finish."] or L["No games match."])
        g.foot:SetText("")
    elseif #matched > MAX_ROWS then
        g.foot:SetText(string.format(L["Showing the latest %d of %d. Export has them all."], MAX_ROWS, #matched))
    else
        g.foot:SetText(gamesText(#matched))
    end
end

--------------------------------------------------------------------------------
-- The screen
--------------------------------------------------------------------------------

local function create(parent)
    local root = CreateFrame("Frame", nil, parent)
    local area = CreateFrame("Frame", nil, root)
    area:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -10)
    area:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, 10)
    area:SetSize(PANEL_W, PANEL_H)

    local cards, days, hours, games

    -- a filter change goes back to the top of the table and redraws this screen
    local function changed()
        if games then games.area:SetVerticalScroll(0) end
        root:Refresh()
    end
    local function setSetting(key, value)
        if HonorLog.SetSetting and settings() then HonorLog:SetSetting(key, value) end
    end
    local function onFilter(kind, key)
        if kind == "bg" then
            setSetting("windowBattleground", key)
        elseif kind == "result" then
            setSetting("windowResult", key)
        elseif kind == "scope" then
            setSetting("viewMode", key == "account" and "account" or "character")
        end
        changed()
    end
    local function onCard(bgType)
        setSetting("windowBattleground", bgFilter() == bgType and "all" or bgType)
        changed()
    end

    cards = {}
    local order = bgOrder()
    for i, bgType in ipairs(order) do cards[i] = buildCard(area, bgType, i, #order, onCard) end
    days = buildDays(area)
    hours = buildHours(area)
    games = buildGames(area, onFilter)

    function root:Refresh()
        local steps = {}
        for _, card in ipairs(cards) do
            steps[#steps + 1] = function() refreshCard(card, bgFilter()) end
        end
        steps[#steps + 1] = function() refreshDays(days) end
        steps[#steps + 1] = function() refreshHours(hours) end
        steps[#steps + 1] = function() refreshGames(games) end
        -- each part guards its own reads, and one failing part leaves the rest drawn
        runSteps(steps)
    end
    root.honorLogParts = { cards = cards, days = days, hours = hours, games = games }
    return root
end

Window:RegisterScreen({ key = "battlegrounds", title = L["Battlegrounds"], order = 4, create = create })
