-- HonorLog Gear goals screen
-- The third screen of the full window, in two modes. Goals: the gear goals in order with what each still
-- takes and when it will be ready (left), the chosen goal in detail with its vendor (middle), and what can be
-- bought today and what the next ranks open (right). Vendors: every PvP vendor and its stock, a star on an item
-- making it a goal (UI/GearVendors.lua). Every number comes from Model.lua, Modules/Rank.lua and Data.lua; this
-- file only lays them out. Each part guards its own reads, so one failing part leaves the rest drawn, and all
-- the work happens in the screen's Refresh: nothing runs per frame. A goal change goes through the Data.lua
-- functions, which already refresh the open screen, so nothing here refreshes after one.
--
-- Loaded after RankPlan. The screen's frame is built the first time its tab is shown.

local _, HonorLog = ...
HonorLog = HonorLog or {}

local Util = HonorLog.Util
local num, str = Util.num, Util.str
local L = HonorLog.L
local Kit = HonorLog.Kit
local Window = HonorLog.Window
local Rank = HonorLog.Rank
local Vendors = HonorLog.GearVendors

local safe, color, commas = Vendors.safe, Vendors.color, Vendors.commas
local showTooltip, fixedText = Vendors.showTooltip, Vendors.fixedText

local PANEL_H = 490
local A_W, B_W, C_W, GAP = 300, 348, 204, 8
local DOT = "\194\183"
local TICK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local GOAL_ROW_H, DIVIDER_H = 50, 22
local TAKES_ROW_H = 26
local MAX_TAKES, MAX_PARTS = 8, 2
-- a row whose item name needs two lines is taller, so no name is cut
local BUY_ROW_H, BUY_ROW_TALL, BUY_LIMIT = 34, 48, 4

local GearScreen = {}
HonorLog.GearScreen = GearScreen
GearScreen.mode = "goals"

local function settings() return HonorLog.db and HonorLog.db.settings end

local function redraw() Window:RefreshCurrent() end

-- Joins words as "a, b and c".
local function joinWords(list)
    if #list <= 1 then return list[1] or "" end
    return table.concat(list, ", ", 1, #list - 1) .. " " .. L["and"] .. " " .. list[#list]
end

local function gamesText(n)
    n = num(n) or 0
    return n == 1 and L["about 1 game"] or string.format(L["about %d games"], n)
end

-- "5,000 honor, 10 AB, 2g" for an item's cost.
local function costText(item)
    local parts = {}
    local honor = num(item.honor) or 0
    if honor > 0 then parts[#parts + 1] = string.format(L["%s honor"], commas(honor)) end
    for _, bg in ipairs(HonorLog.BG_ORDER or {}) do
        local n = item.marks and num(item.marks[bg])
        if n and n > 0 then parts[#parts + 1] = n .. " " .. (str(HonorLog:GetBGShortName(bg)) or bg) end
    end
    local gold = num(item.gold) or 0
    if gold > 0 then parts[#parts + 1] = HonorLog:GoldShort(gold) end
    return #parts > 0 and table.concat(parts, ", ") or "-"
end

-- The shared state of one refresh: the active goals with progress, the bought ones and the chosen one.
local function resolveState()
    local s = settings() or {}
    local gps = safe(HonorLog.GetAllGoalsProgress, HonorLog) or {}
    local bought = safe(HonorLog.GetCompletedGoals, HonorLog) or {}
    local saved = num(s.windowGoal)
    local chosen
    for i, gp in ipairs(gps) do
        if gp.itemID == saved then chosen = { itemID = gp.itemID, gp = gp, index = i } end
    end
    if not chosen then
        for _, g in ipairs(bought) do
            if g.itemID == saved then chosen = { itemID = g.itemID, bought = true } end
        end
    end
    if not chosen and gps[1] then chosen = { itemID = gps[1].itemID, gp = gps[1], index = 1 } end
    return { gps = gps, bought = bought, chosen = chosen }
end

--------------------------------------------------------------------------------
-- A. Your goals, in order
--------------------------------------------------------------------------------

local A_AREA_W = A_W - 12 - Kit.SCROLL_BAR_SPACE
local A_AREA_TOP = 28
local TOTALS_H = 104
local A_HEIGHT_TOTALS = PANEL_H - A_AREA_TOP - 40 - TOTALS_H - 8
local A_HEIGHT_PLAIN = PANEL_H - A_AREA_TOP - 40

-- A goal row: icon, then name over status, then the percent over its bar at the right.
local GOAL_SIDE_W = 44
local GOAL_TEXT_W = A_AREA_W - 46 - 8 - GOAL_SIDE_W - 6

local function chooseGoal(itemID)
    local s = settings()
    if s then s.windowGoal = itemID end
    redraw()
end

local function goalRowCreate(row)
    Vendors.AddChosenMarks(row)
    row.click = CreateFrame("Button", nil, row)
    row.click:SetAllPoints(row)
    local hl = row.click:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row.click)
    hl:SetColorTexture(1, 1, 1, 0.07)
    row.icon = Kit:ItemIcon(row, 32)
    row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    -- above the row's click area, which covers it: two frames at one level have no promised order
    row.icon:SetFrameLevel((num(row.click:GetFrameLevel()) or 0) + 1)
    row.name = fixedText(row, "value", GOAL_TEXT_W)
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 46, -6)
    -- two lines: "Rank 11 locked until week 7 · ready Dec 08" is the point of the row and must not be cut
    row.status = Kit:Text(row, "grey")
    row.status:SetWidth(GOAL_TEXT_W)
    row.status:SetJustifyV("TOP")
    row.status:SetMaxLines(2)
    row.status:SetPoint("TOPLEFT", row, "TOPLEFT", 46, -22)
    row.percent = fixedText(row, "value", GOAL_SIDE_W)
    row.percent:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -7)
    row.percent:SetJustifyH("RIGHT")
    row.bar = Kit:Bar(row)
    row.bar:SetSize(GOAL_SIDE_W, 8)
    row.bar:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -26)
    row.tick = row:CreateTexture(nil, "ARTWORK")
    row.tick:SetSize(16, 16)
    row.tick:SetPoint("RIGHT", row, "RIGHT", -16, 0)
    row.tick:SetTexture(TICK)
    row.click:SetScript("OnClick", function()
        local entry = row.honorLogEntry
        if entry then chooseGoal(entry.itemID) end
    end)
    row.click:SetScript("OnEnter", function()
        local entry = row.honorLogEntry
        if not entry then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(entry.name or "", 1, 1, 1)
        if entry.statusText and entry.statusText ~= "" then GameTooltip:AddLine(entry.statusText, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    row.click:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function goalRowUpdate(row, entry)
    row.icon:SetItem(entry.itemID)
    local name = str(entry.name) or ""
    if entry.bought then
        row.name:SetText(name)
        color(row.name, "grey")
        row.status:SetText(Vendors.SlotName(entry.slot))
        row.percent:SetText("")
        row.bar:Hide()
        row.tick:Show()
    else
        row.name:SetText(Kit:QualityHex(row.icon.honorLogQuality) .. name .. "|r")
        row.status:SetText(entry.statusText or "")
        local pct = entry.percent or 0
        row.percent:SetText(string.format("%d%%", math.floor(pct)))
        color(row.percent, entry.complete and "green" or "white")
        row.bar:SetValue01(pct / 100)
        if entry.complete then row.bar:SetBarColor(Kit.COLORS.green[1], Kit.COLORS.green[2], Kit.COLORS.green[3]) else row.bar:SetBarColor(1, 0.82, 0.1) end
        row.bar:Show()
        row.tick:Hide()
    end
    Vendors.SetChosen(row, entry.chosen)
end

local function buildGoalsList(inset)
    local a = { inset = inset }
    local header = Kit:Header(inset, L["Your goals, in order"])
    header:SetPoint("TOPLEFT", inset, "TOPLEFT", 12 + Kit.PORTRAIT_CLEAR, -6)
    header:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -12, -6)

    a.area = Kit:ScrollArea(inset)
    a.area:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -A_AREA_TOP)
    a.area:SetSize(A_AREA_W, A_HEIGHT_PLAIN)
    a.stack = Vendors.Stack(a.area.honorLogChild, {
        goal = { create = goalRowCreate, update = goalRowUpdate },
        bought = { create = goalRowCreate, update = goalRowUpdate },
        divider = {
            create = function(row)
                row.text = fixedText(row, "grey", A_AREA_W - 16)
                row.text:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 3)
            end,
            update = function(row, entry) row.text:SetText(entry.text) end,
        },
    })

    a.none = Kit:Text(inset, "grey")
    a.none:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -A_AREA_TOP - 6)
    a.none:SetWidth(A_W - 28)
    a.none:SetWordWrap(true)
    a.none:SetJustifyV("TOP")
    a.none:SetText(L["No goals yet. Pick gear from a vendor's stock and HonorLog plans the way to it."])

    -- the totals box, pinned under the list
    local wrap = CreateFrame("Frame", nil, inset)
    wrap:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 6, 40)
    wrap:SetSize(A_W - 12, TOTALS_H)
    local ground = Kit:Inset(wrap)
    ground:SetAllPoints(wrap)
    local face = CreateFrame("Frame", nil, wrap)
    face:SetAllPoints(wrap)
    face:SetFrameLevel((num(ground:GetFrameLevel()) or 0) + 1)
    local t = { wrap = wrap }
    t.title = Kit:Text(face, "labelSmall")
    t.title:SetPoint("TOPLEFT", wrap, "TOPLEFT", 10, -7)
    t.honorLabel = Kit:Text(face, "grey")
    t.honorLabel:SetPoint("TOPLEFT", wrap, "TOPLEFT", 10, -23)
    t.honorLabel:SetText(L["Honor"])
    t.honor = fixedText(face, "value", 190)
    t.honor:SetPoint("TOPLEFT", wrap, "TOPLEFT", 52, -23)
    t.marksRow = CreateFrame("Frame", nil, face)
    t.marksRow:SetPoint("TOPLEFT", wrap, "TOPLEFT", 10, -39)
    t.marksRow:SetSize(A_W - 32, 16)
    t.marks = {}
    for _, bg in ipairs(HonorLog.BG_ORDER or {}) do
        local w = { icon = Kit:MarkIcon(t.marksRow, 14), count = fixedText(t.marksRow, "value", 56) }
        w.icon:SetBattleground(bg)
        w.icon:Hide()
        w.count:Hide()
        t.marks[bg] = w
    end
    t.goldLabel = Kit:Text(face, "grey")
    t.goldLabel:SetPoint("TOPLEFT", wrap, "TOPLEFT", 10, -57)
    t.goldLabel:SetText(L["Gold"])
    t.gold = fixedText(face, "value", 190)
    t.gold:SetPoint("TOPLEFT", wrap, "TOPLEFT", 52, -57)
    t.short = Kit:Text(face, "grey")
    t.short:SetPoint("TOPLEFT", wrap, "TOPLEFT", 10, -74)
    t.short:SetWidth(A_W - 32)
    t.short:SetWordWrap(true)
    t.short:SetMaxLines(2)
    t.short:SetJustifyV("TOP")
    a.totals = t

    a.add = Kit:Button(inset, L["Add a goal"], "red")
    a.add:SetSize(A_W - 24, 24)
    a.add:SetPoint("BOTTOM", inset, "BOTTOM", 0, 10)
    a.add:SetScript("OnClick", function() GearScreen:Open("vendors") end)
    return a
end

-- What is short, in words: "You are 330 honor and 15 marks short.".
local function shortSentence(T)
    local parts = {}
    local honor = math.max(0, (num(T.honorNeeded) or 0) - (num(T.honorCurrent) or 0))
    if honor > 0 then parts[#parts + 1] = string.format(L["%s honor"], commas(honor)) end
    local marks = 0
    for bg, need in pairs(T.marksNeeded or {}) do marks = marks + math.max(0, (num(need) or 0) - (num(T.marksCurrent and T.marksCurrent[bg]) or 0)) end
    if marks > 0 then parts[#parts + 1] = string.format(L["%d marks"], marks) end
    local gold = math.max(0, (num(T.goldNeeded) or 0) - (num(T.goldCurrent) or 0))
    if gold > 0 then parts[#parts + 1] = HonorLog:GoldShort(gold) end
    if #parts > 0 then return string.format(L["You are %s short."], joinWords(parts)) end
    if T.allComplete then return L["You can buy everything on your list."] end
    return L["Honor, marks and gold are covered; rank, level or reputation still hold some goals back."]
end

local function refreshTotals(a, state)
    local t = a.totals
    local show = #state.gps >= 2
    t.wrap:SetShown(show)
    a.area:SetHeight(show and A_HEIGHT_TOTALS or A_HEIGHT_PLAIN)
    if not show then return end
    local T = safe(HonorLog.GetGoalsTotals, HonorLog, state.gps)
    if not T then
        t.wrap:Hide()
        a.area:SetHeight(A_HEIGHT_PLAIN)
        return
    end
    t.title:SetText(string.format(L["All %d together"], #state.gps))
    if (num(T.honorNeeded) or 0) > 0 then
        t.honor:SetText(string.format(L["%s / %s"], commas(T.honorCurrent or 0), commas(T.honorNeeded or 0)))
    else
        t.honor:SetText(L["none needed"])
    end
    local x = 0
    for _, bg in ipairs(HonorLog.BG_ORDER or {}) do
        local w = t.marks[bg]
        local need = num(T.marksNeeded and T.marksNeeded[bg])
        if need and need > 0 then
            w.icon:ClearAllPoints()
            w.icon:SetPoint("LEFT", t.marksRow, "LEFT", x, 0)
            w.icon:Show()
            w.count:ClearAllPoints()
            w.count:SetPoint("LEFT", w.icon, "RIGHT", 3, 0)
            w.count:SetText(string.format("%d/%d", num(T.marksCurrent and T.marksCurrent[bg]) or 0, need))
            w.count:Show()
            x = x + 14 + 3 + (num(w.count:GetStringWidth()) or 30) + 8
        else
            w.icon:Hide()
            w.count:Hide()
        end
    end
    -- gold and the sentence move up when no marks are needed, so the box has no empty line
    local goldNeed = num(T.goldNeeded) or 0
    local goldY = x > 0 and -57 or -39
    t.goldLabel:ClearAllPoints()
    t.goldLabel:SetPoint("TOPLEFT", t.wrap, "TOPLEFT", 10, goldY)
    t.gold:ClearAllPoints()
    t.gold:SetPoint("TOPLEFT", t.wrap, "TOPLEFT", 52, goldY)
    t.short:ClearAllPoints()
    t.short:SetPoint("TOPLEFT", t.wrap, "TOPLEFT", 10, goldNeed > 0 and goldY - 17 or goldY)
    t.goldLabel:SetShown(goldNeed > 0)
    t.gold:SetShown(goldNeed > 0)
    t.gold:SetText(string.format(L["%s / %s"], HonorLog:GoldShort(T.goldCurrent or 0), HonorLog:GoldShort(goldNeed)))
    t.short:SetText(shortSentence(T))
end

local function refreshGoalsList(a, state)
    local entries = {}
    local chosenID = state.chosen and state.chosen.itemID
    for _, gp in ipairs(state.gps) do
        local status = safe(HonorLog.GoalReadyText, HonorLog, gp) or ""
        entries[#entries + 1] = { kind = "goal", height = GOAL_ROW_H, itemID = gp.itemID, name = gp.name, statusText = status,
            percent = safe(HonorLog.GetGoalPercent, HonorLog, gp) or 0, complete = gp.isComplete, chosen = gp.itemID == chosenID }
    end
    if #state.bought > 0 then
        entries[#entries + 1] = { kind = "divider", height = DIVIDER_H, text = L["Bought"] }
        for _, g in ipairs(state.bought) do
            local item = safe(HonorLog.GetGearItem, HonorLog, g.itemID)
            entries[#entries + 1] = { kind = "bought", height = GOAL_ROW_H, itemID = g.itemID, bought = true,
                name = item and item.name or HonorLog:GetGearName(g.itemID), slot = item and item.slot, chosen = g.itemID == chosenID }
        end
    end
    a.none:SetShown(#entries == 0)
    refreshTotals(a, state)
    a.area:honorLogSetContentHeight(a.stack:SetData(entries))
end

--------------------------------------------------------------------------------
-- B. The chosen goal
--------------------------------------------------------------------------------

local B_INNER = B_W - 24
local BUTTONS_Y, TAKES_Y = 58, 88

local function plainButtonClick(self)
    if self.honorLogAction then self.honorLogAction() end
end

local function buildTakesRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(B_INNER, TAKES_ROW_H)
    row:EnableMouse(true)
    row.tick = row:CreateTexture(nil, "ARTWORK")
    row.tick:SetSize(12, 12)
    row.tick:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    row.tick:SetTexture(TICK)
    row.mark = Kit:MarkIcon(row, 14)
    row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 16, 0)
    row.label = fixedText(row, "labelSmall", 92)
    row.value = fixedText(row, "value", B_INNER - 124)
    row.value:SetPoint("TOPLEFT", row, "TOPLEFT", 124, 0)
    row.bar = Kit:Bar(row)
    row.bar:SetSize(96, 6)
    row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 124, -17)
    row.note = fixedText(row, "grey", B_INNER - 124)
    row:SetScript("OnEnter", function(self)
        if self.tip then showTooltip(self, self.tip) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

-- Where a rank requirement stands, in a few words.
local function rankNote(row)
    if row.met or not row.known then return nil end
    if row.limitedBy == "cap" and row.week then return string.format(L["opens in week %d"], row.week), "orange" end
    if row.date then return Rank.FormatDate(row.date) end
    if row.plan and (row.limitedBy == "level" or row.limitedBy == "nopoints") then return str(Rank.PlanWhen(row.plan)), "orange" end
    return L["not this season"], "orange"
end

local function takesEntry(row)
    local kind = row.kind
    local needed = num(row.needed) or 0
    local e = { kind = kind, met = row.met, label = "", barFraction = nil }
    if kind == "honor" then
        if needed <= 0 then return nil end
        e.label = L["Honor"]
        e.bar = true
        if (num(row.remaining) or 0) > 0 and (num(row.games) or 0) > 0 then e.note = gamesText(row.games) end
    elseif kind == "marks" then
        e.label, e.bg, e.bar = str(HonorLog:GetBGDisplayName(row.bg)) or tostring(row.bg), row.bg, true
        if (num(row.remaining) or 0) > 0 and (num(row.games) or 0) > 0 then e.note = gamesText(row.games) end
    elseif kind == "gold" then
        if needed <= 0 then return nil end
        e.label, e.bar = L["Gold"], true
    elseif kind == "rank" then
        e.label = L["Rank"]
        e.note, e.noteTone = rankNote(row)
    elseif kind == "level" then
        e.label = L["Level"]
    elseif kind == "rep" then
        e.label = str(row.factionName) or L["Reputation"]
        if row.known and not row.met and (num(row.games) or 0) > 0 then e.note = gamesText(row.games) end
    else
        return nil
    end
    e.value = safe(HonorLog.GoalRowText, HonorLog, row) or ""
    if e.bar then e.fraction = (num(row.percent) or 0) / 100 end
    return e
end

local function buildDetail(inset)
    local b = { inset = inset }
    b.icon = Kit:ItemIcon(inset, 40)
    b.icon:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -10)
    b.name = fixedText(inset, "title", B_W - 24 - 40 - 8)
    b.name:SetPoint("TOPLEFT", inset, "TOPLEFT", 60, -12)
    b.sub = fixedText(inset, "grey", B_W - 24 - 40 - 8)
    b.sub:SetPoint("TOPLEFT", inset, "TOPLEFT", 60, -34)

    b.buttons = {}
    local width = math.floor((B_INNER - 3 * 4) / 4)
    for i = 1, 4 do
        local button = Kit:Button(inset, "", "small")
        button:SetSize(width, 22)
        button:SetPoint("TOPLEFT", inset, "TOPLEFT", 12 + (i - 1) * (width + 4), -BUTTONS_Y)
        button:SetScript("OnClick", plainButtonClick)
        b.buttons[i] = button
    end

    b.none = Kit:Text(inset, "grey")
    b.none:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -14)
    b.none:SetWidth(B_INNER)
    b.none:SetWordWrap(true)
    b.none:SetJustifyV("TOP")
    b.none:SetText(L["Choose a goal on the left, or add one."])

    b.takesHeader = Kit:Header(inset, L["What it takes"])
    b.takes = {}
    for i = 1, MAX_TAKES do
        b.takes[i] = buildTakesRow(inset)
        b.takes[i]:Hide()
    end
    b.boughtNote = Kit:Text(inset, "grey")
    b.boughtNote:SetWidth(B_INNER)
    b.boughtNote:SetWordWrap(true)
    b.boughtNote:SetJustifyV("TOP")
    b.boughtNote:SetText(L["You bought this. Put it back to plan it again."])

    -- an epic: its two purchases
    b.partsHeader = Kit:Header(inset, L["Two purchases"])
    b.parts = {}
    for i = 1, MAX_PARTS do
        local p = CreateFrame("Frame", nil, inset)
        p:SetSize(B_INNER, 24)
        p.icon = Kit:ItemIcon(p, 20)
        p.icon:SetPoint("LEFT", p, "LEFT", 0, 0)
        p.text = fixedText(p, "value", B_INNER - 28)
        p.text:SetPoint("LEFT", p, "LEFT", 28, 0)
        p:Hide()
        b.parts[i] = p
    end

    -- a blue piece: its epic upgrade
    b.upHeader = Kit:Header(inset, "")
    b.up = CreateFrame("Frame", nil, inset)
    b.up:SetSize(B_INNER, 28)
    b.up.epic = Kit:ItemIcon(b.up, 24)
    b.up.epic:SetPoint("LEFT", b.up, "LEFT", 0, 0)
    b.up.plus = Kit:Text(b.up, "grey")
    b.up.plus:SetPoint("LEFT", b.up, "LEFT", 30, 0)
    b.up.plus:SetText("+")
    b.up.seal = Kit:ItemIcon(b.up, 24)
    b.up.seal:SetPoint("LEFT", b.up, "LEFT", 44, 0)
    b.up.cost = fixedText(b.up, "value", 150)
    b.up.cost:SetPoint("LEFT", b.up, "LEFT", 76, 0)
    b.up.star = Kit:Star(b.up, 20)
    b.up.star:SetPoint("RIGHT", b.up, "RIGHT", 0, 0)
    b.up.star.honorLogOnToggle = function(star, on)
        local id = b.up.epicID
        if not id then return end
        if on then HonorLog:AddGoal(id) else HonorLog:RemoveGoal(id) end
        star:SetOn(HonorLog:IsGoal(id))
    end
    b.upHeader:Hide()
    b.up:Hide()

    -- who sells it
    b.soldHeader = Kit:Header(inset, L["Sold by"])
    b.link = Kit:PlaceLink(inset)
    b.map = Kit:Button(inset, L["Show on map"], "small")
    b.map:SetSize(100, 20)
    b.map:SetScript("OnClick", plainButtonClick)
    b.place = fixedText(inset, "grey", B_INNER)
    b.noVendor = Kit:Text(inset, "grey")
    b.noVendor:SetWidth(B_INNER)
    b.noVendor:SetWordWrap(true)
    b.noVendor:SetMaxLines(3)
    b.noVendor:SetJustifyV("TOP")
    b.noVendor:SetText(L["Vendor not known yet. Open a PvP vendor once and HonorLog remembers where it is."])

    -- when it will be ready, pinned at the bottom
    b.readyLabel = Kit:Text(inset, "labelSmall")
    b.readyLabel:SetText(L["Ready"])
    b.readyValue = fixedText(inset, "value", B_INNER - 52)
    b.reason = Kit:Text(inset, "grey")
    b.reason:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 12, 12)
    b.reason:SetWidth(B_INNER)
    b.reason:SetWordWrap(true)
    b.reason:SetMaxLines(3)
    b.reason:SetJustifyV("BOTTOM")
    b.readyLabel:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 12, 52)
    b.readyValue:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 56, 51)
    return b
end

-- The sentence under the ready date: what holds it back, in plain words.
local function reasonText(gp)
    if gp.readyText then return gp.readyText end
    local by = gp.readyLimitedBy
    if gp.isComplete or by == "ready" then return L["You have everything this needs."] end
    if by == "honor" then return L["Honor is what takes longest."] end
    if by == "marks" then return L["Marks are what take longest."] end
    if by == "rank" then return L["The rank is what takes longest."] end
    if by == "cap" then return L["The weekly rank cap holds the rank back."] end
    if by == "level" then
        local need = gp.level and num(gp.level.needed)
        return need and string.format(L["Your level is too low: reach level %d first."], need) or L["Your level is too low."]
    end
    if by == "rep" then return L["Reputation is what takes longest."] end
    if by == "gold" then return L["Only gold is short."] end
    if by == "nopace" then return L["No recent games to measure from. Play a game for a date."] end
    if by == "nopoints" then return L["Your recent games gave no rank points, so the rank cannot be dated."] end
    if by == "season" then return L["The rank cannot be reached this season."] end
    return ""
end

local function place(widget, inset, y, x)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", inset, "TOPLEFT", x or 12, -y)
end

local function placeHeader(header, inset, y)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -y)
    header:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -12, -y)
    header:Show()
end

local function refreshButtons(b, chosen, state)
    local itemID = chosen.itemID
    local list = b.buttons
    local function set(button, text, action, enabled)
        button:SetText(text)
        button.honorLogAction = action
        button:SetEnabled(enabled)
        button.honorLogEnabled = enabled
        button:Show()
    end
    set(list[1], L["Try it on"], function() Kit:PreviewItem(itemID) end, true)
    if chosen.bought then
        set(list[2], L["Put back"], function() HonorLog:RestoreGoal(itemID) end, true)
        set(list[3], L["Remove"], function() HonorLog:RemoveCompletedGoal(itemID) end, true)
        list[4]:Hide()
    else
        local index, count = chosen.index, #state.gps
        set(list[2], L["Move up"], function() if index > 1 then HonorLog:ReorderGoal(itemID, index - 1) end end, index > 1)
        set(list[3], L["Move down"], function() if index < count then HonorLog:ReorderGoal(itemID, index + 1) end end, index < count)
        set(list[4], L["Remove"], function() HonorLog:RemoveGoal(itemID) end, true)
    end
end

local function refreshTakes(b, gp, y)
    local entries = {}
    for _, row in ipairs(gp.rows or {}) do
        local e = takesEntry(row)
        if e then entries[#entries + 1] = e end
        if #entries >= MAX_TAKES then break end
    end
    for i = 1, MAX_TAKES do
        local frame, e = b.takes[i], entries[i]
        if not e then
            frame:Hide()
        else
            place(frame, b.inset, y)
            frame:Show()
            frame.tick:SetShown(e.met == true)
            frame.label:ClearAllPoints()
            if e.bg then
                frame.mark:SetBattleground(e.bg)
                frame.mark:Show()
                frame.label:SetWidth(88)
                frame.label:SetPoint("TOPLEFT", frame, "TOPLEFT", 34, -1)
            else
                frame.mark:Hide()
                frame.label:SetWidth(104)
                frame.label:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -1)
            end
            frame.label:SetText(e.label)
            frame.value:SetText(e.value)
            frame.bar:SetShown(e.bar == true)
            if e.bar then
                frame.bar:SetValue01(e.fraction)
                if e.met then frame.bar:SetBarColor(Kit.COLORS.green[1], Kit.COLORS.green[2], Kit.COLORS.green[3]) else frame.bar:SetBarColor(1, 0.82, 0.1) end
            end
            frame.note:ClearAllPoints()
            if e.bar then
                frame.note:SetWidth(B_INNER - 124 - 102)
                frame.note:SetPoint("TOPLEFT", frame, "TOPLEFT", 124 + 102, -15)
            else
                frame.note:SetWidth(B_INNER - 124)
                frame.note:SetPoint("TOPLEFT", frame, "TOPLEFT", 124, -15)
            end
            frame.note:SetText(e.note or "")
            color(frame.note, e.noteTone or "grey")
            frame.tip = e.label .. ": " .. (e.value or "") .. (e.note and ("\n" .. e.note) or "")
            y = y + TAKES_ROW_H
        end
    end
    return y
end

local function refreshSold(b, itemID, y)
    placeHeader(b.soldHeader, b.inset, y)
    y = y + 22
    local vendor = safe(HonorLog.GetVendorFor, HonorLog, itemID)
    b.link:SetShown(vendor ~= nil)
    b.map:SetShown(vendor ~= nil)
    b.place:SetShown(vendor ~= nil)
    b.noVendor:SetShown(vendor == nil)
    if vendor then
        place(b.link, b.inset, y)
        b.link:SetVendor(vendor)
        place(b.map, b.inset, y - 2, 12 + B_INNER - 100)
        b.map.honorLogAction = function() HonorLog:ShowVendorForItem(itemID) end
        place(b.place, b.inset, y + 18)
        b.place:SetText(str(vendor.place) or "")
        color(b.place, "grey")
        return y + 32
    end
    place(b.noVendor, b.inset, y)
    return y + 36
end

local function refreshDetail(b, state)
    local chosen = state.chosen
    local widgets = { b.icon, b.name, b.sub, b.takesHeader, b.boughtNote, b.partsHeader, b.soldHeader, b.link, b.map, b.place,
        b.noVendor, b.readyLabel, b.readyValue, b.reason, b.upHeader, b.up }
    for _, w in ipairs(widgets) do w:SetShown(chosen ~= nil) end
    b.none:SetShown(chosen == nil)
    for _, button in ipairs(b.buttons) do button:SetShown(chosen ~= nil) end
    for _, row in ipairs(b.takes) do row:Hide() end
    for _, p in ipairs(b.parts) do p:Hide() end
    if not chosen then return end

    local itemID = chosen.itemID
    local gp = chosen.gp
    local item = gp and gp.item or safe(HonorLog.GetGearItem, HonorLog, itemID)
    b.icon:SetItem(itemID)
    local name = str(gp and gp.name or item and item.name or HonorLog:GetGearName(itemID)) or ""
    b.name:SetText(Kit:QualityHex(b.icon.honorLogQuality) .. name .. "|r")
    local sub = {}
    if item then
        if item.slot then sub[#sub + 1] = Vendors.SlotName(item.slot) end
        if num(item.ilvl) and item.ilvl > 0 then sub[#sub + 1] = string.format(L["Item Level %d"], item.ilvl) end
        if num(item.reqLevel) and item.reqLevel > 1 then sub[#sub + 1] = string.format(L["Requires Level %d"], item.reqLevel) end
    end
    b.sub:SetText(table.concat(sub, " " .. DOT .. " "))
    refreshButtons(b, chosen, state)

    local y = TAKES_Y
    if chosen.bought then
        b.takesHeader:Hide()
        b.partsHeader:Hide()
        b.upHeader:Hide()
        b.up:Hide()
        b.readyLabel:Hide()
        b.readyValue:Hide()
        b.reason:Hide()
        place(b.boughtNote, b.inset, y)
        b.boughtNote:Show()
        refreshSold(b, itemID, y + 36)
        return
    end
    b.boughtNote:Hide()

    placeHeader(b.takesHeader, b.inset, y)
    y = refreshTakes(b, gp, y + 22) + 8

    -- two purchases (an epic) or the epic upgrade (a blue piece)
    local parts = gp.parts
    b.partsHeader:SetShown(parts ~= nil)
    if parts then
        placeHeader(b.partsHeader, b.inset, y)
        y = y + 22
        for i, part in ipairs(parts) do
            local p = b.parts[i]
            if p then
                place(p, b.inset, y)
                p.icon:SetItem(part.itemID)
                p.text:SetText(safe(HonorLog.GoalPartText, HonorLog, part) or "")
                p:Show()
                y = y + 24
            end
        end
        y = y + 6
    end
    local up = not parts and safe(HonorLog.GetUpgradeFor, HonorLog, itemID) or nil
    b.upHeader:SetShown(up ~= nil)
    b.up:SetShown(up ~= nil)
    if up then
        b.upHeader.Label:SetText(string.format(L["Epic upgrade at Rank %d"], num(up.rank) or 0))
        placeHeader(b.upHeader, b.inset, y)
        y = y + 22
        place(b.up, b.inset, y)
        b.up.epicID = up.itemID
        b.up.epic:SetItem(up.itemID)
        b.up.seal:SetItem(up.sealID)
        b.up.cost:SetText(string.format(L["%s honor"], commas(num(up.honor) or 0)))
        b.up.star:SetOn(HonorLog:IsGoal(up.itemID))
        y = y + 34
    end

    refreshSold(b, itemID, y)

    -- ready
    local complete = gp.isComplete == true
    b.readyLabel:SetShown(not complete)
    b.readyValue:SetShown(true)
    if complete then
        b.readyValue:ClearAllPoints()
        b.readyValue:SetPoint("BOTTOMLEFT", b.inset, "BOTTOMLEFT", 12, 51)
        b.readyValue:SetText(L["Ready to purchase"])
        color(b.readyValue, "green")
    else
        b.readyValue:ClearAllPoints()
        b.readyValue:SetPoint("BOTTOMLEFT", b.inset, "BOTTOMLEFT", 56, 51)
        if gp.readyDate then
            local when = Rank.FormatDate(gp.readyDate)
            b.readyValue:SetText(gp.estimated and string.format(L["about %s"], when) or when)
            color(b.readyValue, "white")
        else
            b.readyValue:SetText(L["No date yet"])
            color(b.readyValue, "grey")
        end
    end
    b.reason:SetText(reasonText(gp))
    b.reason:Show()
end

--------------------------------------------------------------------------------
-- C. What you can get
--------------------------------------------------------------------------------

local C_INNER = C_W - 24
local C_FOOT = 36
local C_LIMIT = PANEL_H - C_FOOT

local function buildEntry(parent)
    local e = CreateFrame("Frame", nil, parent)
    e:SetSize(C_INNER, BUY_ROW_H)
    e.icon = Kit:ItemIcon(e, 24)
    e.icon:SetPoint("TOPLEFT", e, "TOPLEFT", 0, -5)
    e.name = Kit:Text(e, "value")
    e.name:SetPoint("TOPLEFT", e, "TOPLEFT", 30, -3)
    e.name:SetWidth(C_INNER - 30)
    e.name:SetWordWrap(true)
    e.name:SetMaxLines(2)
    e.name:SetJustifyV("TOP")
    e.cost = fixedText(e, "grey", C_INNER - 30)
    e:Hide()
    return e
end

local function buildRight(inset)
    local c = { inset = inset, entries = {}, headers = {} }
    for i = 1, 3 do
        c.headers[i] = Kit:Header(inset, "")
        c.headers[i]:Hide()
    end
    for i = 1, BUY_LIMIT + 8 do c.entries[i] = buildEntry(inset) end
    c.nothing = Kit:Text(inset, "grey")
    c.nothing:SetText(L["Nothing yet."])
    c.advice = Kit:Text(inset, "grey")
    c.advice:SetWidth(C_INNER)
    c.advice:SetWordWrap(true)
    c.advice:SetMaxLines(4)
    c.advice:SetJustifyV("TOP")
    color(c.advice, "orange")
    c.foot = Kit:Text(inset, "grey")
    c.foot:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 12, 10)
    c.foot:SetWidth(C_INNER)
    c.foot:SetWordWrap(true)
    c.foot:SetMaxLines(2)
    c.foot:SetJustifyV("BOTTOM")
    c.foot:SetText(L["Ctrl-click an icon to preview the item."])
    return c
end

-- Fills a row and returns its height: the cost sits under a one-line or a two-line name.
local function fillEntry(e, itemID, name, item)
    e.icon:SetItem(itemID)
    e.name:SetText(Kit:QualityHex(e.icon.honorLogQuality) .. (str(name) or "") .. "|r")
    e.cost:SetText(item and costText(item) or "-")
    local tall = (num(e.name:GetStringHeight()) or 0) > 18
    local height = tall and BUY_ROW_TALL or BUY_ROW_H
    e.cost:ClearAllPoints()
    e.cost:SetPoint("TOPLEFT", e, "TOPLEFT", 30, tall and -33 or -19)
    e:SetHeight(height)
    e:Show()
    return height
end

local function refreshRight(c, state)
    local used = 0
    for _, e in ipairs(c.entries) do e:Hide() end
    for _, h in ipairs(c.headers) do h:Hide() end
    local function header(i, text, y)
        local h = c.headers[i]
        h.Label:SetText(text)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", c.inset, "TOPLEFT", 12, -y)
        h:SetPoint("TOPRIGHT", c.inset, "TOPRIGHT", -12, -y)
        h:Show()
    end
    -- Places the next row at y and returns its height, or 0 when it would pass `limit` (or no row is left).
    local function entry(itemID, name, item, y, limit)
        local e = c.entries[used + 1]
        if not e then return 0 end
        local height = fillEntry(e, itemID, name, item)
        if limit and y + height > limit then
            e:Hide()
            return 0
        end
        used = used + 1
        e:ClearAllPoints()
        e:SetPoint("TOPLEFT", c.inset, "TOPLEFT", 12, -y)
        return height
    end

    local y = 6
    header(1, L["You can buy today"], y)
    y = y + 24
    local buyable = safe(HonorLog.GetBuyableNow, HonorLog, BUY_LIMIT) or {}
    c.nothing:SetShown(#buyable == 0)
    if #buyable == 0 then
        c.nothing:ClearAllPoints()
        c.nothing:SetPoint("TOPLEFT", c.inset, "TOPLEFT", 12, -y)
        y = y + 20
    end
    for i = 1, math.min(#buyable, BUY_LIMIT) do
        local it = buyable[i]
        y = y + entry(it.itemID, it.name, it, y)
    end

    local advice = safe(HonorLog.GetHonorCapAdvice, HonorLog, state.gps)
    local text = advice and str(advice.text)
    c.advice:SetShown(text ~= nil)
    if text then
        c.advice:ClearAllPoints()
        c.advice:SetPoint("TOPLEFT", c.inset, "TOPLEFT", 12, -(y + 4))
        c.advice:SetText((text:gsub("^%l", string.upper)))
        -- as tall as its text (one to four lines), so the lists below keep the room it does not use
        local height = math.ceil(num(c.advice:GetStringHeight()) or 0)
        y = y + 4 + math.max(13, math.min(52, height)) + 4
    end

    -- the next rank that opens something, and the next such rank after it, while there is room
    local info = safe(Rank.GetInfo, Rank)
    local rank = info and num(info.rank) or 0
    local top = math.min(info and num(info.seasonMaxRank) or 14, 14)
    local sections = 0
    for n = rank + 1, top do
        if sections >= 2 then break end
        local items = safe(HonorLog.GetRankUnlocks, HonorLog, n) or {}
        if #items > 0 then
            -- a section starts only where its header and one row of either height still fit
            if C_LIMIT - y - 8 - 24 < BUY_ROW_TALL then break end
            sections = sections + 1
            y = y + 8
            header(1 + sections, string.format(L["Rank %d opens"], n), y)
            y = y + 24
            for i = 1, math.min(#items, BUY_LIMIT) do
                local id = items[i]
                local item = safe(HonorLog.GetGearItem, HonorLog, id)
                local height = entry(id, item and item.name or HonorLog:GetGearName(id), item, y, C_LIMIT)
                if height == 0 then break end
                y = y + height
            end
        end
    end
end

--------------------------------------------------------------------------------
-- The screen
--------------------------------------------------------------------------------

-- Applies a pending request from Open: the mode, and the goal to choose.
function GearScreen:ApplyRequest()
    local r = self.request
    if not r then return end
    self.request = nil
    self.mode = r.mode
    local s = settings()
    if s and r.itemID then s.windowGoal = r.itemID end
end

-- Opens the window on this screen in a mode ("goals" or "vendors"), choosing the goal itemID when given. Other
-- screens call this.
function GearScreen:Open(mode, itemID)
    self.request = { mode = mode == "vendors" and "vendors" or "goals", itemID = num(itemID) }
    Window:Show("gear")
    -- the first show already drew it when the client ran the window's OnShow; otherwise draw now
    if self.request and Window.frames.gear then Window:RefreshCurrent() end
end

local function create(parent)
    local root = CreateFrame("Frame", nil, parent)
    local goalsRoot = CreateFrame("Frame", nil, root)
    goalsRoot:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -10)
    goalsRoot:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, 10)
    local vendorsRoot = CreateFrame("Frame", nil, root)
    vendorsRoot:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -10)
    vendorsRoot:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, 10)

    local insetA = Kit:Inset(goalsRoot)
    insetA:SetPoint("TOPLEFT", goalsRoot, "TOPLEFT", 0, 0)
    insetA:SetSize(A_W, PANEL_H)
    local insetB = Kit:Inset(goalsRoot)
    insetB:SetPoint("TOPLEFT", goalsRoot, "TOPLEFT", A_W + GAP, 0)
    insetB:SetSize(B_W, PANEL_H)
    local insetC = Kit:Inset(goalsRoot)
    insetC:SetPoint("TOPLEFT", goalsRoot, "TOPLEFT", A_W + GAP + B_W + GAP, 0)
    insetC:SetSize(C_W, PANEL_H)

    local list = buildGoalsList(insetA)
    local detail = buildDetail(insetB)
    local right = buildRight(insetC)
    local vendors = Vendors:Create(vendorsRoot, function() GearScreen:Open("goals") end)

    function root:Refresh()
        GearScreen:ApplyRequest()
        local mode = GearScreen.mode == "vendors" and "vendors" or "goals"
        goalsRoot:SetShown(mode == "goals")
        vendorsRoot:SetShown(mode == "vendors")
        local steps
        if mode == "vendors" then
            steps = { function() vendors:Refresh() end }
        else
            local state = resolveState()
            steps = {
                function() refreshGoalsList(list, state) end,
                function() refreshDetail(detail, state) end,
                function() refreshRight(right, state) end,
            }
        end
        -- each part guards its own reads, and one failing part leaves the rest drawn
        for _, step in ipairs(steps) do
            local ok, err = pcall(step)
            if not ok then
                local handler = geterrorhandler and geterrorhandler()
                if handler then handler(err) end
            end
        end
    end
    root.honorLogParts = { list = list, detail = detail, right = right, vendors = vendors, goalsRoot = goalsRoot, vendorsRoot = vendorsRoot }
    return root
end

Window:RegisterScreen({ key = "gear", title = L["Gear goals"], order = 3, create = create })
