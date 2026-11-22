-- HonorLog Overview screen
-- The first screen of the full window: the rank ring and honor on the left; today's tiles, what to do next,
-- the next goal and the recent games on the right. Every number comes from the view models (Model.lua),
-- Modules/Rank.lua and Data.lua; this file only lays them out. A read that fails or returns nothing leaves
-- its text empty instead of raising.
--
-- The left pane is shared with the Rank plan screen (UI/RankPane.lua).
-- Loaded after Window and RankPane. The screen's frame is built the first time its tab is shown.

local _, HonorLog = ...
HonorLog = HonorLog or {}

local Util = HonorLog.Util
local num, str = Util.num, Util.str
local L = HonorLog.L
local Kit = HonorLog.Kit
local Window = HonorLog.Window

local LEFT_WIDTH = HonorLog.RankPane.WIDTH
local COLUMN_WIDTH = 604
local TILE_HEIGHT, TILE_WIDTH = 68, 145
local MIDDLE_HEIGHT = 206
local GOAL_WIDTH = 224
local ADVICE_ROWS, GAME_ROWS, GAME_ROW_HEIGHT = 4, 6, 25
local GOAL_ROW_HEIGHT, GOAL_ROWS = 15, 6
local GAME_PAD = 6 -- the games table's left padding, shared by its column titles and its cells
local ADVICE_LIST_HEIGHT, ADVICE_LINES, ADVICE_GAP = 164, 3, 8

local READY, NOT_READY = "Interface\\RaidFrame\\ReadyCheck-Ready", "Interface\\RaidFrame\\ReadyCheck-NotReady"

local function commas(n) return HonorLog.Rank.FormatNumber(n) end

-- The first result of a model call, or nil when it raises.
local function safe(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
end

local function color(fs, name)
    local c = Kit.COLORS[name]
    fs:SetTextColor(c[1], c[2], c[3])
end

local function white(text) return Kit:Hex("white") .. text .. "|r" end

local function showTooltip(owner, text)
    if not text or text == "" then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Tiles
--------------------------------------------------------------------------------

local function buildTiles(col)
    local tiles = {}
    local labels = { L["Today"], L["Honor today"], L["Rank points today"], L["Marks today"] }
    for i = 1, 4 do
        local tile = Kit:Tile(col)
        tile:SetSize(TILE_WIDTH, TILE_HEIGHT)
        tile:SetPoint("TOPLEFT", col, "TOPLEFT", (i - 1) * (TILE_WIDTH + 8), 0)
        tile.label:SetText(labels[i])
        tiles[i] = tile
    end
    -- the marks tile's note line is a row of mark icons, each with its count
    local row = tiles[4].noteRow
    row.widgets = {}
    for _, bg in ipairs(HonorLog.BG_ORDER) do
        local w = { icon = Kit:MarkIcon(row, 14), count = Kit:Text(row, "grey") }
        w.icon:SetBattleground(bg)
        w.count:SetPoint("LEFT", w.icon, "RIGHT", 3, 0)
        w.icon:Hide()
        w.count:Hide()
        row.widgets[bg] = w
    end
    return tiles
end

local function setNote(tile, text, name)
    tile.noteRow:Hide()
    tile.note:Show()
    tile.note:SetText(text or "")
    color(tile.note, name or "grey")
end

local function refreshTiles(tiles)
    local m = safe(HonorLog.GetTodayModel, HonorLog)
    local info = safe(HonorLog.Rank.GetInfo, HonorLog.Rank)
    local span = HonorLog.Rank.FormatSpan

    -- Today
    if m then
        tiles[1].value:SetText(string.format(L["%d – %d"], m.wins, m.losses))
        if m.played > 0 then
            local duration = num(m.duration) or 0
            setNote(tiles[1], duration >= 60 and string.format(L["%d games in %s"], m.played, span(duration)) or string.format(L["%d games"], m.played))
        else
            setNote(tiles[1], L["No games yet today"])
        end
    else
        tiles[1].value:SetText("")
        setNote(tiles[1], "")
    end

    -- Honor today
    -- nothing gained reads "0" in white on every tile, a gain reads "+N"
    local honorToday = m and (num(m.honor) or 0) or nil
    tiles[2].value:SetText(honorToday and (honorToday > 0 and string.format(L["+%s"], commas(honorToday)) or "0") or "")
    color(tiles[2].value, honorToday and honorToday > 0 and "gold" or "white")
    setNote(tiles[2], m and m.honorPerHour and string.format(L["%s an hour"], commas(m.honorPerHour)) or "")

    -- Rank points today
    if m and (m.rankPoints or 0) > 0 then
        tiles[3].value:SetText(string.format(L["+%s"], commas(m.rankPoints)))
        color(tiles[3].value, "white")
        setNote(tiles[3], "")
    elseif m then
        tiles[3].value:SetText("0")
        -- orange only when something is holding the points back; a day without games is just 0
        color(tiles[3].value, m.rankBlocked and "orange" or "white")
        if m.rankBlocked == "gate" then
            local level = info and info.gate and info.gate.level
                or (HonorLog.Rank.LEVEL_GATES[1] and HonorLog.Rank.LEVEL_GATES[1].level) or 0
            setNote(tiles[3], string.format(L["Level %d needed"], level), "orange")
        elseif m.rankBlocked == "cap" then
            setNote(tiles[3], L["Weekly cap reached"], "orange")
        else
            setNote(tiles[3], "")
        end
    else
        tiles[3].value:SetText("")
        setNote(tiles[3], "")
    end

    -- Marks today
    local marksToday = m and (num(m.marksTotal) or 0) or nil
    tiles[4].value:SetText(marksToday and (marksToday > 0 and string.format("+%d", marksToday) or "0") or "")
    color(tiles[4].value, "white")
    local row = tiles[4].noteRow
    tiles[4].note:Hide()
    row:Show()
    local x = 0
    for _, bg in ipairs(HonorLog.BG_ORDER) do
        local w = row.widgets[bg]
        local n = m and m.marks and num(m.marks[bg]) or 0
        if n > 0 then
            w.icon:ClearAllPoints()
            w.icon:SetPoint("LEFT", row, "LEFT", x, 0)
            w.icon:Show()
            w.count:SetText(tostring(n))
            w.count:Show()
            x = x + 14 + 3 + (w.count:GetStringWidth() or 0) + 8
        else
            w.icon:Hide()
            w.count:Hide()
        end
    end
end

--------------------------------------------------------------------------------
-- What to do next
--------------------------------------------------------------------------------

local function buildAdvice(col)
    local inset = Kit:Inset(col)
    inset:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -(TILE_HEIGHT + 8))
    inset:SetSize(COLUMN_WIDTH - GOAL_WIDTH - 8, MIDDLE_HEIGHT)
    local header = Kit:Header(inset, L["What to do next"])
    header:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -9)
    header:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -14, -9)

    local listWidth = COLUMN_WIDTH - GOAL_WIDTH - 8 - 28
    local list = CreateFrame("Frame", nil, inset)
    list:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -34)
    list:SetSize(listWidth, ADVICE_LIST_HEIGHT)

    local a = { inset = inset }
    a.empty = Kit:Text(inset, "grey")
    a.empty:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -38)
    a.empty:SetText(L["Nothing pressing. Keep playing."])

    -- Rows are as tall as their text (up to three lines), stacked; a row that would run past the box is
    -- left out, the most pressing advice being first.
    local rows = { frames = {}, count = 0 }
    local function makeRow()
        local row = CreateFrame("Frame", nil, list)
        row.bullet = row:CreateTexture(nil, "ARTWORK")
        row.bullet:SetSize(7, 7)
        row.bullet:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -5)
        row.bullet:SetColorTexture(0.85, 0.66, 0.23, 1)
        row.bullet:SetRotation(math.pi / 4)
        row.text = Kit:Text(row, "value")
        row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 16, 0)
        row.text:SetWidth(listWidth - 16 - 26)
        row.text:SetWordWrap(true)
        row.text:SetMaxLines(ADVICE_LINES)
        row.text:SetJustifyV("TOP")
        row.item = Kit:ItemIcon(row, 18)
        row.item:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        row.mark = Kit:MarkIcon(row, 18)
        row.mark:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        return row
    end
    function rows:SetData(entries)
        entries = entries or {}
        local y, shown = 0, 0
        for i = 1, math.max(#entries, #self.frames) do
            local entry, row = entries[i], self.frames[i]
            local placed = false
            if entry and i <= ADVICE_ROWS then
                if not row then
                    row = makeRow()
                    self.frames[i] = row
                end
                local head, body = str(entry.head) or "", str(entry.body)
                row.text:SetText(body and (head .. " " .. Kit:Hex("grey") .. body .. "|r") or head)
                local height = math.max(18, math.ceil(num(row.text:GetStringHeight()) or 14))
                if shown == 0 or y + height <= ADVICE_LIST_HEIGHT then
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
                    row:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -y)
                    row:SetHeight(height)
                    if entry.itemID then
                        row.item:SetItem(entry.itemID)
                        row.item:Show()
                        row.mark:Hide()
                    elseif entry.bgType then
                        row.mark:SetBattleground(entry.bgType)
                        row.mark:Show()
                        row.item:Hide()
                    else
                        row.item:Hide()
                        row.mark:Hide()
                    end
                    row:Show()
                    y, shown, placed = y + height + ADVICE_GAP, shown + 1, true
                end
            end
            if row and not placed then row:Hide() end
        end
        self.count = shown
    end
    a.rows = rows
    return a
end

local function refreshAdvice(a)
    local list = safe(HonorLog.GetAdvice, HonorLog, ADVICE_ROWS) or {}
    a.rows:SetData(list)
    a.empty:SetShown(#list == 0)
end

--------------------------------------------------------------------------------
-- Next goal
--------------------------------------------------------------------------------

local function buildGoal(col)
    local inset = Kit:Inset(col)
    inset:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, -(TILE_HEIGHT + 8))
    inset:SetSize(GOAL_WIDTH, MIDDLE_HEIGHT)
    local g = { inset = inset }
    -- the whole card opens the goal on the Gear goals screen; made first, so everything on the card sits above it
    g.card = CreateFrame("Button", nil, inset)
    g.card:SetAllPoints(inset)
    g.card:SetScript("OnClick", function()
        if g.itemID and HonorLog.GearScreen then HonorLog.GearScreen:Open("goals", g.itemID) end
    end)
    local header = Kit:Header(inset, L["Next goal"])
    header:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -9)
    header:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -14, -9)

    g.icon = Kit:ItemIcon(inset, 34)
    g.icon:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -32)
    g.name = Kit:Text(inset, "value")
    g.name:SetPoint("TOPLEFT", g.icon, "TOPRIGHT", 8, 0)
    g.name:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -10, -32)
    g.name:SetWordWrap(true)
    g.name:SetMaxLines(2)
    g.name:SetJustifyV("TOP")
    g.percent = Kit:Text(inset, "grey")
    g.percent:SetPoint("BOTTOMLEFT", g.icon, "BOTTOMRIGHT", 8, 0)

    local list = CreateFrame("Frame", nil, inset)
    list:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -74)
    list:SetSize(GOAL_WIDTH - 28, GOAL_ROWS * GOAL_ROW_HEIGHT)
    g.rows = Kit:Rows(list, GOAL_ROW_HEIGHT, function(row)
        row.mark = Kit:MarkIcon(row, 14)
        row.mark:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.label = Kit:Text(row, "labelSmall")
        row.value = Kit:Text(row, "value")
        row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.value:SetJustifyH("RIGHT")
    end, function(row, entry)
        row.label:ClearAllPoints()
        if entry.bg then
            row.mark:SetBattleground(entry.bg)
            row.mark:Show()
            row.label:SetPoint("LEFT", row, "LEFT", 18, 0)
        else
            row.mark:Hide()
            row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
        end
        row.label:SetText(entry.label)
        row.value:SetText(entry.value)
        color(row.value, entry.tone)
    end)

    g.none = Kit:Text(inset, "grey")
    g.none:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -40)
    g.none:SetText(L["No goals yet"])
    g.view = Kit:Button(inset, L["View goal"], "red")
    g.view:SetPoint("BOTTOM", inset, "BOTTOM", 0, 10)
    g.view:SetScript("OnClick", function()
        if g.itemID and HonorLog.GearScreen then HonorLog.GearScreen:Open("goals", g.itemID) end
    end)
    g.add = Kit:Button(inset, L["Add a goal"], "red")
    g.add:SetPoint("BOTTOM", inset, "BOTTOM", 0, 10)
    g.add:SetScript("OnClick", function() HonorLog.GearScreen:Open("vendors") end)
    return g
end

-- One requirement as { label, value, tone, bg }, or nil when nothing is required.
local function goalRow(row)
    local kind = row.kind
    local have, need = num(row.current), num(row.needed)
    local met = row.met
    local entry = { tone = met and "green" or "white" }
    if kind == "honor" then
        if not need or need <= 0 then return nil end
        entry.label, entry.value = L["Honor"], string.format(L["%s / %s"], commas(have or 0), commas(need))
    elseif kind == "marks" then
        entry.label = string.format(L["%s marks"], HonorLog:GetBGDisplayName(row.bg))
        entry.value, entry.bg = string.format("%d / %d", have or 0, need or 0), row.bg
    elseif kind == "rank" then
        entry.label, entry.value = L["Rank"], string.format("%s / %s", have and tostring(have) or "?", tostring(need or "?"))
        if not met then entry.tone = "red" end
    elseif kind == "level" then
        entry.label, entry.value = L["Level"], string.format("%d / %d", have or 0, need or 0)
        if not met then entry.tone = "red" end
    elseif kind == "gold" then
        if not need or need <= 0 then return nil end
        entry.label, entry.value = L["Gold"], string.format(L["%s / %s"], HonorLog:GoldShort(have or 0), HonorLog:GoldShort(need))
    elseif kind == "rep" then
        entry.label = str(row.factionName) or L["Reputation"]
        local names = HonorLog.STANDING_NAMES or {}
        entry.value = string.format(L["%s / %s"], names[have] or "?", str(row.standingName) or names[need] or "?")
    else
        return nil
    end
    return entry
end

local function refreshGoal(g)
    local gp = (safe(HonorLog.GetAllGoalsProgress, HonorLog) or {})[1]
    g.itemID = gp and gp.itemID or nil
    g.icon:SetShown(gp ~= nil)
    g.name:SetShown(gp ~= nil)
    g.percent:SetShown(gp ~= nil)
    g.none:SetShown(gp == nil)
    g.view:SetShown(gp ~= nil)
    g.add:SetShown(gp == nil)
    if not gp then
        g.rows:SetData({})
        return
    end
    g.icon:SetItem(gp.itemID)
    local name = str(gp.name) or ""
    g.name:SetText(Kit:QualityHex(g.icon.honorLogQuality) .. name .. "|r")
    g.percent:SetText(string.format(L["%d%% complete"], math.floor(num(safe(HonorLog.GetGoalPercent, HonorLog, gp)) or 0)))
    local entries = {}
    for _, row in ipairs(gp.rows or {}) do
        local entry = goalRow(row)
        if entry then entries[#entries + 1] = entry end
        if #entries >= GOAL_ROWS then break end
    end
    g.rows:SetData(entries)
end

--------------------------------------------------------------------------------
-- Recent games
--------------------------------------------------------------------------------

local COLUMNS = {
    { key = "bg", x = 8, w = 128, title = L["Battleground"] },
    { key = "result", x = 142, w = 80, title = L["Result"] },
    { key = "length", x = 228, w = 50, title = L["Length"] },
    { key = "honor", x = 284, w = 70, title = L["Honor"] },
    { key = "rank", x = 360, w = 160, title = L["Rank points"] },
    { key = "marks", x = 526, w = 56, title = L["Marks"] },
}

local RESULT_WORD = { win = L["Win"], loss = L["Loss"], draw = L["Draw"], left = L["Left early"] }

local function cell(row, col, style)
    local f = CreateFrame("Frame", nil, row)
    f:SetPoint("LEFT", row, "LEFT", col.x + GAME_PAD, 0)
    f:SetSize(col.w, GAME_ROW_HEIGHT)
    f.text = Kit:Text(f, style or "value")
    f.text:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.text:SetWidth(col.w)
    f.text:SetWordWrap(false)
    return f
end

local function buildGames(col)
    local inset = Kit:Inset(col)
    inset:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -(TILE_HEIGHT + 8 + MIDDLE_HEIGHT + 8))
    inset:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", 0, 0)
    local header = Kit:Header(inset, L["Recent games"])
    header:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -8)
    header:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -14 - 86, -8)
    -- the Battlegrounds screen holds every game; this is the way in
    local all = Kit:Button(inset, L["All games"], "small")
    all:SetSize(80, 18)
    all:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -10, -7)
    all:SetScript("OnClick", function() Window:Show("battlegrounds") end)
    for _, c in ipairs(COLUMNS) do
        local fs = Kit:Text(inset, "labelSmall")
        fs:SetPoint("TOPLEFT", inset, "TOPLEFT", c.x + GAME_PAD, -30)
        fs:SetText(c.title)
    end
    local list = CreateFrame("Frame", nil, inset)
    list:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, -46)
    list:SetPoint("TOPRIGHT", inset, "TOPRIGHT", 0, -46)
    list:SetHeight(GAME_ROWS * GAME_ROW_HEIGHT)

    local gm = { inset = inset, all = all }
    gm.empty = Kit:Text(inset, "grey")
    gm.empty:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -56)
    gm.empty:SetText(L["No games recorded yet. Play a battleground and it will show here."])
    gm.rows = Kit:Rows(list, GAME_ROW_HEIGHT, function(row)
        row.cells = {}
        for _, c in ipairs(COLUMNS) do row.cells[c.key] = cell(row, c) end
        local result = row.cells.result
        result.symbol = result:CreateTexture(nil, "ARTWORK")
        result.symbol:SetSize(14, 14)
        result.symbol:SetPoint("LEFT", result, "LEFT", 0, 0)
        result.text:ClearAllPoints()
        result.text:SetPoint("LEFT", result, "LEFT", 18, 0)
        result.text:SetWidth(60)
        row.cells.length.text:SetPoint("LEFT", row.cells.length, "LEFT", 0, 0)
        row.cells.marks.mark = Kit:MarkIcon(row.cells.marks, 14)
        row.cells.marks.mark:SetPoint("LEFT", row.cells.marks, "LEFT", 0, 0)
        row.cells.marks.text:ClearAllPoints()
        row.cells.marks.text:SetPoint("LEFT", row.cells.marks, "LEFT", 18, 0)
        row.cells.marks.text:SetWidth(36)
        for _, key in ipairs({ "honor", "rank" }) do
            local f = row.cells[key]
            f:EnableMouse(true)
            f:SetScript("OnEnter", function(self) showTooltip(self, self.honorLogTip) end)
            f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end, function(row, entry)
        local c = row.cells
        c.bg.text:SetText(HonorLog:GetBGDisplayName(entry.bgType))
        color(c.bg.text, "white")

        local result = entry.result or (entry.win and "win" or "loss")
        c.result.text:SetText(RESULT_WORD[result] or tostring(result))
        if result == "win" then
            c.result.symbol:SetTexture(READY)
            c.result.symbol:Show()
            color(c.result.text, "green")
        elseif result == "loss" then
            c.result.symbol:SetTexture(NOT_READY)
            c.result.symbol:Show()
            color(c.result.text, "red")
        else
            c.result.symbol:Hide()
            color(c.result.text, "grey")
        end

        local d = num(entry.duration)
        c.length.text:SetText(d and string.format("%d:%02d", math.floor(d / 60), d % 60) or "-")
        color(c.length.text, "grey")

        c.honor.text:SetText(string.format(L["+%s"], commas(num(entry.honor) or 0)) .. (entry.honorCapped and " *" or ""))
        color(c.honor.text, "gold")
        c.honor.honorLogTip = safe(HonorLog.DescribeHonor, HonorLog, entry)

        local text, tone = HonorLog:DescribeRankPoints(entry)
        c.rank.text:SetText(text or "")
        color(c.rank.text, tone == "earned" and "white" or tone == "blocked" and "orange" or "grey")
        c.rank.honorLogTip = text

        local marks = num(entry.marks) or 0
        c.marks.mark:SetBattleground(entry.bgType)
        c.marks.text:SetText(string.format("+%d", marks))
        color(c.marks.text, "white")
    end)
    return gm
end

local function refreshGames(gm)
    local list = safe(HonorLog.GetHistory, HonorLog, "character", GAME_ROWS) or {}
    gm.rows:SetData(list)
    gm.empty:SetShown(#list == 0)
end

--------------------------------------------------------------------------------
-- The screen
--------------------------------------------------------------------------------

local function create(parent)
    local root = CreateFrame("Frame", nil, parent)
    local pane = HonorLog.RankPane:Create(root)
    local left = pane.honorLogParts
    local col = CreateFrame("Frame", nil, root)
    col:SetPoint("TOPLEFT", root, "TOPLEFT", LEFT_WIDTH + 10, -10)
    col:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, 10)
    local tiles = buildTiles(col)
    local advice = buildAdvice(col)
    local goal = buildGoal(col)
    local games = buildGames(col)

    function root:Refresh()
        -- each part guards its own reads, and one failing part leaves the rest drawn
        for _, step in ipairs({
            function() pane:Refresh() end, function() refreshTiles(tiles) end,
            function() refreshAdvice(advice) end, function() refreshGoal(goal) end, function() refreshGames(games) end,
        }) do
            local ok, err = pcall(step)
            if not ok then
                local handler = geterrorhandler and geterrorhandler()
                if handler then handler(err) end
            end
        end
    end
    root.honorLogParts = { left = left, tiles = tiles, advice = advice, goal = goal, games = games }
    return root
end

Window:RegisterScreen({ key = "overview", title = L["Overview"], order = 1, create = create })
