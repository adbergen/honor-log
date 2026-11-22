-- HonorLog Rank plan screen
-- The second screen of the full window: the season charted against the weekly rank cap, the fourteen ranks
-- with what each unlocks, a planner to a target rank and the measured rank points per game. The shared rank
-- pane (UI/RankPane.lua) sits on the left. Every number comes from Modules/Rank.lua and Model.lua; this file
-- only lays them out. Each part guards its own reads, so one failing part leaves the rest drawn, and all the
-- work happens in the screen's Refresh: nothing runs per frame.
--
-- Loaded after Overview. The screen's frame is built the first time its tab is shown.

local _, HonorLog = ...
HonorLog = HonorLog or {}

local Util = HonorLog.Util
local num, str = Util.num, Util.str
local L = HonorLog.L
local Kit = HonorLog.Kit
local Window = HonorLog.Window
local Rank = HonorLog.Rank

local COLUMN_WIDTH = 604
local CHART_HEIGHT, BOTTOM_HEIGHT, GAP = 150, 332, 8
local SIDE_WIDTH = 200
local TABLE_WIDTH = COLUMN_WIDTH - SIDE_WIDTH - GAP
local PLAN_HEIGHT = 170
local MAX_RANK = 14

local function commas(n) return Rank.FormatNumber(n) end

-- The first result of a model call, or nil when it raises.
local function safe(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
end

local function color(fs, name)
    local c = Kit.COLORS[name]
    fs:SetTextColor(c[1], c[2], c[3])
end

local function showTooltip(owner, text)
    if not text or text == "" then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
end

local function settings() return HonorLog.db and HonorLog.db.settings end

--------------------------------------------------------------------------------
-- Season chart
--------------------------------------------------------------------------------

local CHART_TOP = 26 -- the header line above the plot
local PLOT = { left = 44, right = 14, bottom = 22, top = 8 }
local CAP_COLOR = { 1, 0.82, 0 }
local POINTS_COLOR = { 0.88, 0.28, 0.25 }
local PROJECTED_COLOR = { 0.78, 0.76, 0.71 }
local GUIDE_RANKS = { 8, 12, 14 } -- ranks with a faint guide and a label at the left

local function buildChart(col)
    local inset = Kit:Inset(col)
    inset:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0)
    inset:SetSize(COLUMN_WIDTH, CHART_HEIGHT)
    local c = { inset = inset, legend = {} }

    c.title = Kit:Text(inset, "label")
    c.title:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -8)
    c.title:SetText(L["Your season"])

    -- Three samples with words: gold line, thick red line, grey dashed line.
    local x = 14 + (c.title:GetStringWidth() or 70) + 22
    local function sample(words, draw)
        local width = draw(x)
        local fs = Kit:Text(inset, "grey")
        fs:SetPoint("TOPLEFT", inset, "TOPLEFT", x + width + 6, -9)
        fs:SetText(words)
        c.legend[#c.legend + 1] = fs
        x = x + width + 6 + (fs:GetStringWidth() or 60) + 18
    end
    local function bar(px, py, w, h, rgb)
        local t = inset:CreateTexture(nil, "ARTWORK")
        t:SetPoint("TOPLEFT", inset, "TOPLEFT", px, py)
        t:SetSize(w, h)
        t:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
        c.legend[#c.legend + 1] = t
    end
    sample(L["Weekly cap"], function(px) bar(px, -15, 16, 2, CAP_COLOR) return 16 end)
    sample(L["Your points"], function(px) bar(px, -14, 16, 3, POINTS_COLOR) return 16 end)
    sample(L["Projected at your pace"], function(px)
        for i = 0, 2 do bar(px + i * 6, -15, 4, 2, PROJECTED_COLOR) end
        return 16
    end)

    c.chart = Kit:Chart(inset)
    c.chart:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, -CHART_TOP)
    c.chart:SetSize(COLUMN_WIDTH, CHART_HEIGHT - CHART_TOP)

    c.none = Kit:Text(inset, "grey")
    c.none:SetPoint("CENTER", inset, "CENTER", 0, -8)
    c.none:SetJustifyH("CENTER")
    c.none:SetText(L["No rank data yet. Play a battleground to start your season."])
    c.none:Hide()
    return c
end

local function refreshChart(c, info, pace)
    local chart = c.chart
    chart:Clear()
    local series = info and safe(Rank.GetSeasonSeries, Rank, info, pace)
    local weeks = series and series.weeks or {}
    local maxTotal = series and num(series.maxTotal) or 0
    local noData = not info or #weeks == 0 or maxTotal <= 0
    c.none:SetShown(noData)
    for _, piece in ipairs(c.legend) do piece:SetShown(not noData) end
    if noData then return end

    local n = #weeks
    local plotW = COLUMN_WIDTH - PLOT.left - PLOT.right
    local plotH = CHART_HEIGHT - CHART_TOP - PLOT.bottom - PLOT.top
    local slot = plotW / n
    local function xOf(week) return PLOT.left + (week - 0.5) * slot end
    local function yOf(total) return PLOT.bottom + plotH * Kit.Clamp01((num(total) or 0) / maxTotal) end
    local line = Kit.COLORS.line

    -- faint guides at rank 8, 12 and 14, and the zero line
    chart:Line(PLOT.left, PLOT.bottom, PLOT.left + plotW, PLOT.bottom, 1, line[1], line[2], line[3], 0.8)
    chart:Label(PLOT.left - 6, PLOT.bottom, "0", "grey", "RIGHT")
    for _, rank in ipairs(GUIDE_RANKS) do
        local y = yOf(Rank:TotalForRank(rank))
        chart:Line(PLOT.left, y, PLOT.left + plotW, y, 1, line[1], line[2], line[3], 0.28)
        chart:Label(PLOT.left - 6, y, "R" .. rank, "grey", "RIGHT")
    end

    -- the weekly cap as a step line, with a faint fill under it
    for i, row in ipairs(weeks) do
        local xa, xb = PLOT.left + (i - 1) * slot, PLOT.left + i * slot
        local y = yOf(row.capTotal)
        chart:Rect(xa, PLOT.bottom, slot, y - PLOT.bottom, CAP_COLOR[1], CAP_COLOR[2], CAP_COLOR[3], 0.1)
        chart:Line(xa, y, xb, y, 2, CAP_COLOR[1], CAP_COLOR[2], CAP_COLOR[3], 1)
        local nextRow = weeks[i + 1]
        if nextRow then chart:Line(xb, y, xb, yOf(nextRow.capTotal), 2, CAP_COLOR[1], CAP_COLOR[2], CAP_COLOR[3], 1) end
    end

    -- the week labels under the axis, the current one white
    local current = num(series.currentWeek)
    for i = 1, n do
        local text = i == 1 and string.format(L["Week %d"], 1) or tostring(i)
        chart:Label(xOf(i), 9, text, "grey", "CENTER", i == current and "white" or nil)
    end

    -- your points: a thick red line ending in a ringed dot at the current week
    local previous
    for _, point in ipairs(series.actual or {}) do
        local week = num(point.week)
        if week and week >= 1 and week <= n then
            local x, y = xOf(week), yOf(point.total)
            if previous then chart:Line(previous[1], previous[2], x, y, 3, POINTS_COLOR[1], POINTS_COLOR[2], POINTS_COLOR[3], 1) end
            previous = { x, y }
        end
    end

    -- the projection starts at that dot and runs to each later week's end
    if previous then
        local from = previous
        for _, point in ipairs(series.projected or {}) do
            local week = num(point.week)
            if week and current and week > current and week <= n then
                local x, y = xOf(week), yOf(point.total)
                chart:Dashed(from[1], from[2], x, y, 2, PROJECTED_COLOR[1], PROJECTED_COLOR[2], PROJECTED_COLOR[3], 1)
                from = { x, y }
            end
        end
        -- a blocking level gate: a vertical dashed orange line at the current position
        if series.gateLevel then
            local o = Kit.COLORS.orange
            chart:Dashed(previous[1], PLOT.bottom, previous[1], PLOT.bottom + plotH, 2, o[1], o[2], o[3], 1)
            local text = string.format(L["Rank points start at level %d"], series.gateLevel)
            if previous[1] > COLUMN_WIDTH - 190 then
                chart:Label(previous[1] - 6, PLOT.bottom + plotH - 6, text, "grey", "RIGHT", "orange")
            else
                chart:Label(previous[1] + 6, PLOT.bottom + plotH - 6, text, "grey", "LEFT", "orange")
            end
        end
        chart:Dot(previous[1], previous[2], 12, 0.95, 0.9, 0.8)
        chart:Dot(previous[1], previous[2], 8, POINTS_COLOR[1], POINTS_COLOR[2], POINTS_COLOR[3])
    end
end

--------------------------------------------------------------------------------
-- Rank table
--------------------------------------------------------------------------------

local ROW_HEIGHT = 22
local ICONS_PER_ROW = 3
local COL = { badge = 6, title = 28, titleW = 116, points = 148, pointsW = 44, icons = 196, earliest = 292, earliestW = 98 }

local function buildTable(bottom)
    local inset = Kit:Inset(bottom)
    inset:SetPoint("TOPLEFT", bottom, "TOPLEFT", 0, 0)
    inset:SetSize(TABLE_WIDTH, BOTTOM_HEIGHT)
    local t = { inset = inset }
    for _, h in ipairs({
        { L["Rank"], COL.badge + 2 }, { L["Points"], COL.points }, { L["Unlocks"], COL.icons }, { L["Earliest"], COL.earliest },
    }) do
        local fs = Kit:Text(inset, "labelSmall")
        fs:SetPoint("TOPLEFT", inset, "TOPLEFT", h[2], -5)
        fs:SetText(h[1])
    end
    local list = CreateFrame("Frame", nil, inset)
    list:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, -22)
    list:SetPoint("TOPRIGHT", inset, "TOPRIGHT", 0, -22)
    list:SetHeight(MAX_RANK * ROW_HEIGHT)

    t.empty = Kit:Text(inset, "grey")
    t.empty:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -34)
    t.empty:SetText(L["No rank data yet. Play a battleground to start your season."])

    local badgeRing = Kit.RING_ATLASES.badge
    t.rows = Kit:Rows(list, ROW_HEIGHT, function(row)
        row.wash = row:CreateTexture(nil, "BACKGROUND")
        row.wash:SetAllPoints(row)
        row.wash:SetColorTexture(0.5, 0.08, 0.06, 0.5)
        row.wash:Hide()

        -- a small round badge with the rank number
        row.badge = CreateFrame("Frame", nil, row)
        row.badge:SetSize(20, 20)
        row.badge:SetPoint("LEFT", row, "LEFT", COL.badge - 1, 0)
        if Kit:HasAtlas(badgeRing) then
            Kit:RoundGround(row.badge)
            local ring = row.badge:CreateTexture(nil, "ARTWORK")
            ring:SetAllPoints(row.badge)
            ring:SetAtlas(badgeRing)
        else
            local ground = row.badge:CreateTexture(nil, "BACKGROUND")
            ground:SetAllPoints(row.badge)
            ground:SetColorTexture(0.1, 0.1, 0.1, 1)
            Kit:Edges(row.badge, 0.85, 0.66, 0.23, 1)
        end
        row.badge.number = Kit:Text(row.badge, "labelSmall")
        row.badge.number:SetPoint("CENTER", 0, 0)
        row.badge.number:SetJustifyH("CENTER")

        row.title = Kit:Text(row, "value")
        row.title:SetPoint("LEFT", row, "LEFT", COL.title, 0)
        row.title:SetWidth(COL.titleW)
        row.title:SetWordWrap(false)
        row.points = Kit:Text(row, "value")
        row.points:SetPoint("LEFT", row, "LEFT", COL.points, 0)
        row.points:SetWidth(COL.pointsW)
        row.points:SetWordWrap(false)

        row.icons = {}
        for i = 1, ICONS_PER_ROW do
            row.icons[i] = Kit:ItemIcon(row, 18)
            row.icons[i]:SetPoint("LEFT", row, "LEFT", COL.icons + (i - 1) * 21, 0)
            row.icons[i]:Hide()
        end
        row.more = Kit:Text(row, "grey")
        row.more:SetPoint("LEFT", row, "LEFT", COL.icons + ICONS_PER_ROW * 21 + 1, 0)

        row.cell = CreateFrame("Frame", nil, row)
        row.cell:SetPoint("LEFT", row, "LEFT", COL.earliest, 0)
        row.cell:SetSize(COL.earliestW, ROW_HEIGHT)
        row.cell:EnableMouse(true)
        row.cell.text = Kit:Text(row.cell, "value")
        row.cell.text:SetPoint("LEFT", row.cell, "LEFT", 0, 0)
        row.cell.text:SetWidth(COL.earliestW)
        row.cell.text:SetWordWrap(false)
        row.cell:SetScript("OnEnter", function(self) showTooltip(self, self.tip) end)
        row.cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end, function(row, entry)
        local state = entry.state
        local tone = state == "reached" and "grey" or "white"
        row.wash:SetShown(state == "current")
        row.badge.number:SetText(tostring(entry.rank))
        -- two digits do not fit the ring at the size one digit has
        local number = row.badge.number
        pcall(function()
            local file, _, flags = number:GetFont()
            if type(file) == "string" then number:SetFont(file, entry.rank >= 10 and 8 or 10, flags) end
        end)
        row.title:SetText(str(entry.title) or "")
        color(row.title, tone)
        row.points:SetText(commas(entry.total or 0))
        color(row.points, tone)

        local items = entry.items or {}
        for i = 1, ICONS_PER_ROW do
            local icon = row.icons[i]
            if items[i] then
                icon:SetItem(items[i])
                icon:Show()
            else
                icon:Hide()
            end
        end
        if #items > ICONS_PER_ROW then
            row.more:SetText(string.format("+%d", #items - ICONS_PER_ROW))
            row.more:Show()
        else
            row.more:SetText("")
            row.more:Hide()
        end

        local text, name
        if state == "reached" then
            text, name = L["Reached"], "grey"
        elseif state == "current" then
            text, name = L["You are here"], "gold"
        else
            local plan = entry.plan
            text = str(entry.when)
            -- a date at the player's pace needs a measured pace; a level gate or a season limit is said either way
            if plan and plan.paceMeasured == false and plan.limitedBy ~= "level" and plan.limitedBy ~= "season" and plan.limitedBy ~= "nopoints" then
                text = L["not measured yet"]
            end
            -- the model says "ahead" when a plan has no date, which only happens past what the season allows
            if not text or text == "ahead" then
                text = plan and plan.limitedBy == "season" and L["Not this season"] or "-"
            end
            local limited = plan and (plan.limitedBy == "level" or plan.limitedBy == "nopoints")
            name = limited and "orange" or "grey"
        end
        row.cell.text:SetText(text)
        color(row.cell.text, name)
        row.cell.tip = text
    end)
    return t
end

local function refreshTable(t, info, pace)
    local list = info and safe(Rank.GetRankTable, Rank, info, pace) or {}
    t.rows:SetData(list)
    t.empty:SetShown(#list == 0)
end

--------------------------------------------------------------------------------
-- Plan to
--------------------------------------------------------------------------------

local MAX_TARGETS, UNLOCK_ICONS = 4, 4

-- The ranks offered as targets: the next rank that unlocks something, and 8, 11 and 14, leaving out any at
-- or below the current rank and any above the season's top rank, each once, lowest first.
local function offeredTargets(info)
    local out = {}
    if not info then return out end
    local rank = num(info.rank) or 0
    local top = math.min(num(info.seasonMaxRank) or MAX_RANK, MAX_RANK)
    local candidates = {}
    for n = rank + 1, top do
        local items = safe(HonorLog.GetRankUnlocks, HonorLog, n) or {}
        if #items > 0 then
            candidates[#candidates + 1] = n
            break
        end
    end
    for _, n in ipairs({ 8, 11, 14 }) do candidates[#candidates + 1] = n end
    local seen = {}
    for _, n in ipairs(candidates) do
        if n > rank and n <= top and not seen[n] then
            seen[n] = true
            out[#out + 1] = n
        end
    end
    table.sort(out)
    while #out > MAX_TARGETS do out[#out] = nil end
    return out
end

local function chosenTarget(offered)
    local saved = settings() and num(settings().windowRankTarget)
    for _, n in ipairs(offered) do
        if n == saved then return n end
    end
    return offered[1]
end

local refreshPlan

local function buildPlan(side)
    local inset = Kit:Inset(side)
    inset:SetPoint("TOPLEFT", side, "TOPLEFT", 0, 0)
    inset:SetSize(SIDE_WIDTH, PLAN_HEIGHT)
    local header = Kit:Header(inset, L["Plan to"])
    header:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -6)
    header:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -12, -6)

    local p = { inset = inset, buttons = {}, targets = {} }
    local width = math.floor((SIDE_WIDTH - 24 - (MAX_TARGETS - 1) * 4) / MAX_TARGETS)
    for i = 1, MAX_TARGETS do
        local button = Kit:Button(inset, "", "small")
        button:SetSize(width, 20)
        button:SetPoint("TOPLEFT", inset, "TOPLEFT", 12 + (i - 1) * (width + 4), -26)
        button:SetScript("OnClick", function()
            local rank = p.targets[i]
            if rank and settings() then
                settings().windowRankTarget = rank
                refreshPlan(p)
            end
        end)
        button:Hide()
        p.buttons[i] = button
    end
    -- the chosen target is also underlined, so it is not colour alone
    p.underline = inset:CreateTexture(nil, "OVERLAY")
    p.underline:SetHeight(2)
    p.underline:SetColorTexture(1, 0.82, 0, 1)
    p.underline:Hide()

    p.title = Kit:Text(inset, "value")
    p.title:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -52)
    p.title:SetWidth(SIDE_WIDTH - 24)
    p.title:SetWordWrap(false)

    p.pairs = {}
    local labels = { L["Points to go"], L["At your pace"], L["Cap opens"], L["Unlocks"] }
    for i, text in ipairs(labels) do
        local y = -70 - (i - 1) * 15
        local label = Kit:Text(inset, "labelSmall")
        label:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, y)
        label:SetText(text)
        local value = Kit:Text(inset, "value")
        value:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -12, y)
        value:SetJustifyH("RIGHT")
        p.pairs[i] = { label = label, value = value }
    end
    -- the unlocks pair is a row of icons instead of a text value
    local unlocksY = -70 - 3 * 15
    p.pairs[4].value:Hide()
    p.unlockIcons = {}
    for i = 1, UNLOCK_ICONS do
        p.unlockIcons[i] = Kit:ItemIcon(inset, 20)
        p.unlockIcons[i]:SetPoint("TOPLEFT", inset, "TOPLEFT", 78 + (i - 1) * 23, unlocksY + 3)
        p.unlockIcons[i]:Hide()
    end
    p.unlockMore = Kit:Text(inset, "grey")
    p.unlockMore:SetPoint("TOPLEFT", inset, "TOPLEFT", 78 + UNLOCK_ICONS * 23, unlocksY)

    p.holdBack = Kit:Text(inset, "grey")
    p.holdBack:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -140)
    p.holdBack:SetWidth(SIDE_WIDTH - 24)
    p.holdBack:SetWordWrap(true)
    p.holdBack:SetMaxLines(2)
    p.holdBack:SetJustifyV("TOP")

    p.done = Kit:Text(inset, "value")
    p.done:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -34)
    p.done:SetText(L["Top rank reached."])
    p.done:Hide()
    return p
end

local function holdBackText(plan)
    local by = plan.limitedBy
    if by == "level" then return string.format(L["Held back by level %d first."], plan.gateLevel or 0), "orange" end
    if by == "cap" then return L["Held back by the weekly cap."], "grey" end
    if by == "nopoints" then return L["Your recent games gave no rank points."], "orange" end
    if by == "season" then return L["Not reachable this season."], "orange" end
    if by == "pace" then
        if plan.paceMeasured == false then return L["Play a battleground to measure your pace."], "grey" end
        return string.format(L["At your pace: %s."], Rank.PlanWhen(plan) or "-"), "grey"
    end
    return nil
end

function refreshPlan(p, info, pace)
    info = info or safe(Rank.GetInfo, Rank)
    local offered = offeredTargets(info)
    local target = chosenTarget(offered)
    p.targets, p.target = offered, target or false

    local plan = target and safe(Rank.PlanToRank, Rank, target, info, pace or safe(Rank.GetPace, Rank)) or nil
    local show = plan ~= nil
    for i, button in ipairs(p.buttons) do
        local rank = offered[i]
        if rank then
            button:SetText("R" .. rank)
            button:Show()
            if rank == target then
                pcall(button.LockHighlight, button)
                p.underline:ClearAllPoints()
                p.underline:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 3, -3)
                p.underline:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, -3)
                p.underline:Show()
            else
                pcall(button.UnlockHighlight, button)
            end
        else
            button:Hide()
        end
    end
    if not target then p.underline:Hide() end
    -- every rank reached is a sentence of its own; no rank data leaves the box empty
    p.done:SetShown(info ~= nil and not target)
    p.title:SetShown(show)
    for _, pair in ipairs(p.pairs) do
        pair.label:SetShown(show)
        pair.value:SetShown(show and pair ~= p.pairs[4])
    end
    p.holdBack:SetShown(show)
    p.unlockMore:Hide()
    for i = 1, UNLOCK_ICONS do p.unlockIcons[i]:Hide() end
    if not show then
        p.holdBack:SetText("")
        return
    end

    p.title:SetText(string.format(L["Rank %d %s"], target, safe(Rank.TitleForRank, Rank, target) or ""))
    p.pairs[1].value:SetText(commas(plan.pointsNeeded or 0))
    local games
    if plan.gamesNeeded == nil or plan.paceMeasured == false then
        games = L["not measured yet"]
    else
        games = Rank.PlanGames(plan) or "-"
    end
    p.pairs[2].value:SetText(games)
    local capDate = plan.earliestDateByCap
    if capDate and capDate <= time() then
        p.pairs[3].value:SetText(L["now"])
    elseif capDate then
        p.pairs[3].value:SetText(string.format(L["%s (week %d)"], Rank.FormatDate(capDate), plan.earliestWeekByCap or 0))
    else
        p.pairs[3].value:SetText("-")
    end

    local items = safe(HonorLog.GetRankUnlocks, HonorLog, target) or {}
    for i = 1, UNLOCK_ICONS do
        if items[i] then
            p.unlockIcons[i]:SetItem(items[i])
            p.unlockIcons[i]:Show()
        end
    end
    if #items > UNLOCK_ICONS then
        p.unlockMore:SetText(string.format("+%d", #items - UNLOCK_ICONS))
        p.unlockMore:Show()
    end

    local text, tone = holdBackText(plan)
    p.holdBack:SetText(text or "")
    color(p.holdBack, tone or "grey")
end

--------------------------------------------------------------------------------
-- Rank points per game
--------------------------------------------------------------------------------

local GAME_ROWS, GAME_ROW_HEIGHT = 4, 14
local GAME_LIST_TOP = 38

local function buildPerGame(side)
    local inset = Kit:Inset(side)
    inset:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -(PLAN_HEIGHT + GAP))
    inset:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0)
    local header = Kit:Header(inset, L["Rank points per game"])
    header:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -6)
    header:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -12, -6)
    for _, h in ipairs({ { L["Battleground"], 12 }, { L["Win"], 122 }, { L["Loss"], 158 } }) do
        local fs = Kit:Text(inset, "labelSmall")
        fs:SetPoint("TOPLEFT", inset, "TOPLEFT", h[2], -24)
        fs:SetText(h[1])
    end
    local list = CreateFrame("Frame", nil, inset)
    list:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, -GAME_LIST_TOP)
    list:SetPoint("TOPRIGHT", inset, "TOPRIGHT", 0, -GAME_LIST_TOP)
    list:SetHeight(GAME_ROWS * GAME_ROW_HEIGHT)

    local g = { inset = inset }
    g.rows = Kit:Rows(list, GAME_ROW_HEIGHT, function(row)
        row.name = Kit:Text(row, "value")
        row.name:SetPoint("LEFT", row, "LEFT", 12, 0)
        row.name:SetWidth(106)
        row.name:SetWordWrap(false)
        row.win = Kit:Text(row, "value")
        row.win:SetPoint("LEFT", row, "LEFT", 122, 0)
        row.loss = Kit:Text(row, "value")
        row.loss:SetPoint("LEFT", row, "LEFT", 158, 0)
    end, function(row, entry)
        local function points(v) return v and tostring(math.floor(v + 0.5)) or "-" end
        row.name:SetText(str(entry.name) or "")
        row.win:SetText(points(entry.perWin))
        row.loss:SetText(points(entry.perLoss))
        local zero = entry.perWin == 0 and entry.perLoss == 0
        local name = zero and "orange" or "white"
        color(row.name, name)
        color(row.win, name)
        color(row.loss, name)
    end)
    g.empty = Kit:Text(inset, "grey")
    g.empty:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -GAME_LIST_TOP)
    g.empty:SetText(L["Not measured yet."])

    g.zero = Kit:Text(inset, "grey")
    g.zero:SetWidth(SIDE_WIDTH - 24)
    g.zero:SetWordWrap(true)
    g.zero:SetMaxLines(2)
    g.zero:SetJustifyV("TOP")
    color(g.zero, "orange")
    g.quest = Kit:Text(inset, "grey")
    g.quest:SetWidth(SIDE_WIDTH - 24)
    g.quest:SetWordWrap(true)
    g.quest:SetMaxLines(3)
    g.quest:SetJustifyV("TOP")
    return g
end

local function refreshPerGame(g, info)
    local list = safe(Rank.GetPointsPerResult, Rank) or {}
    local shown = {}
    for i = 1, math.min(#list, GAME_ROWS) do shown[i] = list[i] end
    g.rows:SetData(shown)
    g.empty:SetShown(#shown == 0)

    local y = GAME_LIST_TOP + math.max(#shown, 1) * GAME_ROW_HEIGHT + 4
    local zero = (safe(Rank.GetZeroPointBattlegrounds, Rank) or {})[1]
    g.zero:ClearAllPoints()
    if zero then
        g.zero:SetPoint("TOPLEFT", g.inset, "TOPLEFT", 12, -y)
        g.zero:SetText(safe(Rank.ZeroPointText, Rank, zero) or "")
        g.zero:Show()
        y = y + (num(g.zero:GetStringHeight()) or 12) + 4
    else
        g.zero:SetText("")
        g.zero:Hide()
    end

    local quest = info and safe(Rank.GetWeeklyQuest, Rank, info)
    g.quest:ClearAllPoints()
    if quest then
        -- the title on its own line: it carries a colon of its own ("Field of Honor: Week 3")
        local title = str(quest.title) or ""
        local text, name
        if quest.measured and quest.done == true then
            text, name = string.format(L["%s\ndone this week, +%d rank points"], title, quest.measured), "white"
        elseif quest.measured then
            text, name = string.format(L["%s\n+%d rank points (measured)"], title, quest.measured), "white"
        elseif quest.done == true then
            text, name = string.format(L["%s\ndone this week"], title), "grey"
        else
            text, name = string.format(L["%s\nreward not measured yet"], title), "grey"
        end
        g.quest:SetPoint("TOPLEFT", g.inset, "TOPLEFT", 12, -y)
        g.quest:SetText(text)
        color(g.quest, name)
        g.quest:Show()
    else
        g.quest:SetText("")
        g.quest:Hide()
    end
end

--------------------------------------------------------------------------------
-- The screen
--------------------------------------------------------------------------------

local function create(parent)
    local root = CreateFrame("Frame", nil, parent)
    local pane = HonorLog.RankPane:Create(root)

    local col = CreateFrame("Frame", nil, root)
    col:SetPoint("TOPLEFT", root, "TOPLEFT", HonorLog.RankPane.WIDTH + 10, -10)
    col:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, 10)
    local chart = buildChart(col)

    local bottom = CreateFrame("Frame", nil, col)
    bottom:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -(CHART_HEIGHT + GAP))
    bottom:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", 0, 0)
    local rankTable = buildTable(bottom)
    local side = CreateFrame("Frame", nil, bottom)
    side:SetPoint("TOPRIGHT", bottom, "TOPRIGHT", 0, 0)
    side:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", 0, 0)
    side:SetWidth(SIDE_WIDTH)
    local plan = buildPlan(side)
    local perGame = buildPerGame(side)

    function root:Refresh()
        local info = safe(Rank.GetInfo, Rank)
        local pace = safe(Rank.GetPace, Rank)
        -- each part guards its own reads, and one failing part leaves the rest drawn
        for _, step in ipairs({
            function() pane:Refresh() end,
            function() refreshChart(chart, info, pace) end,
            function() refreshTable(rankTable, info, pace) end,
            function() refreshPlan(plan, info, pace) end,
            function() refreshPerGame(perGame, info) end,
        }) do
            local ok, err = pcall(step)
            if not ok then
                local handler = geterrorhandler and geterrorhandler()
                if handler then handler(err) end
            end
        end
    end
    root.honorLogParts = { left = pane.honorLogParts, chart = chart, rankTable = rankTable, plan = plan, perGame = perGame }
    return root
end

Window:RegisterScreen({ key = "rank", title = L["Rank plan"], order = 2, create = create })
