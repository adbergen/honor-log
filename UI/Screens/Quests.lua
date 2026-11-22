-- HonorLog Quests screen
-- The fifth screen of the full window: the PvP quests the game data names, which are in your log (with their
-- objectives), which are done and which are still to pick up, what each paid you and the way to the hand-in on
-- the map. Every row comes from Modules/Quests.lua (GetList, GetCounts); this file only lays them out. Each part
-- guards its own reads, so one failing part leaves the rest drawn, and all the work happens in the screen's
-- Refresh: nothing runs per frame. The list is computed in a Refresh and kept: choosing a row redraws the rows
-- and the detail from it without asking the client again.
--
-- Widths: a 12 point text is about 6.3 px a character, a 10 point text about 5.2 px, a 16 point text about 8.4 px.
-- Every text that can outgrow its box is a fixed-width text (the client cuts it with "...") and the cut ones carry
-- their full text in a tooltip: quest titles and objectives are longer in other languages.
--
-- The quest log's update event is used (QUEST_LOG_UPDATE, documented, not flagged HasRestrictions) only while
-- this screen is the open one, and answered with one refresh a second at most.
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
local Quests = HonorLog.Quests

local safe, color, commas, showTooltip = Vendors.safe, Vendors.color, Vendors.commas, Vendors.showTooltip

local PANEL_W, PANEL_H = 868, 490
local FILTER_H, GAP = 26, 8
local BODY_H = PANEL_H - FILTER_H - GAP + 4
local LIST_W = 520
local DETAIL_W = PANEL_W - LIST_W - GAP
local ROW_H, TITLE_H = 40, 22
local LIST_AREA_W = LIST_W - 12 - Kit.SCROLL_BAR_SPACE
local LIST_AREA_H = BODY_H - 16
local DETAIL_INNER = DETAIL_W - 24
local MAX_OBJECTIVES, MAX_PAID = 4, 8
local THROTTLE = 1
local TICK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local DOT = "\194\183"

local QuestsScreen = {}
HonorLog.QuestsScreen = QuestsScreen

local function settings() return HonorLog.db and HonorLog.db.settings end

local function setSetting(key, value)
    if HonorLog.SetSetting and settings() then HonorLog:SetSetting(key, value) end
end

local function bgKeys()
    local keys = {}
    for _, key in ipairs(HonorLog.BG_ORDER or {}) do keys[#keys + 1] = key end
    return keys
end

-- The saved filters; a key that is not there yet, or that nothing offers, reads as the default (not saved).
local function bgFilter()
    local s = settings()
    local v = s and s.windowQuestBG
    if v == "other" then return v end
    for _, key in ipairs(bgKeys()) do
        if v == key then return v end
    end
    return "all"
end

local function levelFilter()
    local s = settings()
    return s and s.windowQuestLevels == "all" and "all" or "mine"
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

local function round(n) return math.floor((num(n) or 0) + 0.5) end

-- "3g 20s 5c" for an amount in copper.
local function moneyText(copper)
    copper = round(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = string.format(L["%dg"], g) end
    if s > 0 then parts[#parts + 1] = string.format(L["%ds"], s) end
    if c > 0 or #parts == 0 then parts[#parts + 1] = string.format(L["%dc"], c) end
    return table.concat(parts, " ")
end

local function bgShort(bg)
    if bg == "ALL" then return L["All battlegrounds"] end
    if bg == "SEASON" then return L["Season"] end
    return str(safe(HonorLog.GetBGShortName, HonorLog, bg)) or tostring(bg)
end

local function bgFull(bg)
    if bg == "ALL" then return L["All battlegrounds"] end
    if bg == "SEASON" then return L["Season"] end
    return str(safe(HonorLog.GetBGDisplayName, HonorLog, bg)) or tostring(bg)
end

local STATE_TEXT = {
    ready = L["Ready to hand in."], log = L["In your log."], open = L["Not picked up yet."], done = L["Done."],
}
local GROUP_TITLE = {
    ready = L["Ready to hand in"], log = L["In your log"], open = L["Not picked up"], done = L["Done"],
}
local STATE_ORDER = { "ready", "log", "open", "done" }

-- What a quest paid, as the entries the list and the detail draw: { text, bg (for a mark), amount }. Honor, rank
-- points, then each battleground's marks; the largest first.
local function paidEntries(paid)
    local out = {}
    if type(paid) ~= "table" then return out end
    local honor, rank = num(paid.honor), num(paid.rank)
    if honor and honor > 0 then out[#out + 1] = { text = string.format(L["+%s honor"], commas(round(honor))), amount = honor, order = 1 } end
    if rank and rank > 0 then out[#out + 1] = { text = string.format(L["+%s rank"], commas(round(rank))), amount = rank, order = 2 } end
    if type(paid.marks) == "table" then
        for i, bg in ipairs(HonorLog.BG_ORDER or {}) do
            local n = num(paid.marks[bg])
            if n and n > 0 then out[#out + 1] = { text = string.format("+%d", round(n)), bg = bg, amount = n, order = 2 + i } end
        end
    end
    table.sort(out, function(a, b)
        if a.amount ~= b.amount then return a.amount > b.amount end
        return a.order < b.order
    end)
    return out
end
QuestsScreen.PaidEntries = paidEntries

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

local function setMark(row, state)
    row.ready:SetShown(state == "ready")
    row.dot:SetShown(state == "log")
    for _, e in ipairs(row.ring) do e:SetShown(state == "open") end
    row.tick:SetShown(state == "done")
end

local function subText(q)
    local parts = { bgShort(q.bg) }
    if q.level then parts[#parts + 1] = string.format(L["Level %d"], q.level) end
    if q.inLog and q.objectives then
        for _, o in ipairs(q.objectives) do
            if not o.finished then parts[#parts + 1] = o.text break end
        end
    end
    return table.concat(parts, " " .. DOT .. " ")
end

local function buildList(root, onChoose)
    local inset = Kit:Inset(root)
    inset:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(FILTER_H + GAP - 4))
    inset:SetSize(LIST_W, BODY_H)
    local l = { inset = inset }

    l.area = Kit:ScrollArea(inset)
    l.area:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -8)
    l.area:SetSize(LIST_AREA_W, LIST_AREA_H)

    l.empty = Kit:FixedText(inset, "grey", LIST_W - 28)
    l.empty:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -14)
    l.empty:SetText(L["No quests match."])
    l.empty:Hide()

    l.stack = Kit:Stack(l.area.honorLogChild, {
        title = {
            create = function(row)
                row.text = Kit:FixedText(row, "labelSmall", LIST_AREA_W - 16)
                row.text:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 3)
            end,
            update = function(row, entry) row.text:SetText(entry.text or "") end,
        },
        quest = {
            create = function(row)
                Vendors.AddChosenMarks(row)
                local base = num(row:GetFrameLevel()) or 0
                -- the click area is the whole row and sits below the face, so the mark icons keep their tooltips
                row.click = CreateFrame("Button", nil, row)
                row.click:SetAllPoints(row)
                row.click:SetFrameLevel(base + 2)
                local hl = row.click:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(row.click)
                hl:SetColorTexture(1, 1, 1, 0.07)
                row.face = CreateFrame("Frame", nil, row)
                row.face:SetAllPoints(row)
                row.face:SetFrameLevel(base + 4)
                local face = row.face

                -- the state mark: a shape and a colour
                row.ready = Kit:Text(face, "title")
                row.ready:SetPoint("LEFT", face, "LEFT", 14, 0)
                row.ready:SetText("!")
                color(row.ready, "gold")
                row.dot = face:CreateTexture(nil, "ARTWORK")
                row.dot:SetSize(8, 8)
                row.dot:SetPoint("LEFT", face, "LEFT", 14, 0)
                row.dot:SetColorTexture(1, 1, 1, 1)
                row.ringBox = CreateFrame("Frame", nil, face)
                row.ringBox:SetSize(10, 10)
                row.ringBox:SetPoint("LEFT", face, "LEFT", 13, 0)
                row.ring = Kit:Edges(row.ringBox, 0.66, 0.64, 0.59, 1)
                row.tick = face:CreateTexture(nil, "ARTWORK")
                row.tick:SetSize(16, 16)
                row.tick:SetPoint("LEFT", face, "LEFT", 10, 0)
                row.tick:SetTexture(TICK)

                row.title = Kit:FixedText(face, "value", 268)
                row.title:SetPoint("TOPLEFT", face, "TOPLEFT", 34, -6)
                row.sub = Kit:FixedText(face, "grey", 268)
                row.sub:SetPoint("TOPLEFT", face, "TOPLEFT", 34, -23)

                -- what it paid: up to two entries, one under the other, at the right
                row.paid = {}
                for i = 1, 2 do
                    local p = {}
                    local y = -(5 + (i - 1) * 16)
                    p.icon = Kit:MarkIcon(face, 14)
                    p.icon:SetPoint("TOPRIGHT", face, "TOPRIGHT", -8, y - 1)
                    p.text = Kit:FixedText(face, "value", 150)
                    p.text:SetJustifyH("RIGHT")
                    p.y = y
                    row.paid[i] = p
                end
                row.click:SetScript("OnClick", function()
                    local entry = row.honorLogEntry
                    if entry and onChoose then onChoose(entry.quest.id) end
                end)
                row.click:SetScript("OnEnter", function()
                    local entry = row.honorLogEntry
                    local q = entry and entry.quest
                    if not q then return end
                    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(q.title, 1, 1, 1, true)
                    local sub = subText(q)
                    if sub ~= "" then GameTooltip:AddLine(sub, 0.66, 0.64, 0.59, true) end
                    GameTooltip:Show()
                end)
                row.click:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end,
            update = function(row, entry)
                local q = entry.quest
                setMark(row, q.state)
                row.title:SetText(q.title)
                color(row.title, q.state == "done" and "grey" or "white")
                row.sub:SetText(subText(q))
                local items = paidEntries(q.paid)
                for i, p in ipairs(row.paid) do
                    local item = items[i]
                    local none = i == 1 and #items == 0
                    p.icon:SetShown(item ~= nil and item.bg ~= nil)
                    if item then p.icon:SetBattleground(item.bg or "AV") end
                    p.text:SetShown(item ~= nil or none)
                    p.text:ClearAllPoints()
                    p.text:SetPoint("TOPRIGHT", row.face, "TOPRIGHT", (item and item.bg) and -26 or -8, p.y)
                    if item then
                        p.text:SetText(item.text)
                        color(p.text, "white")
                    elseif none then
                        p.text:SetText(q.paid and L["nothing measured"] or L["not measured yet"])
                        color(p.text, "grey")
                    end
                end
                Vendors.SetChosen(row, entry.chosen)
            end,
        },
    })
    return l
end

-- Group titles over the non-empty groups, a row per quest.
local function listEntries(rows, chosenId)
    local by = { ready = {}, log = {}, open = {}, done = {} }
    for _, q in ipairs(rows) do table.insert(by[q.state], q) end
    local out = {}
    for _, state in ipairs(STATE_ORDER) do
        if #by[state] > 0 then
            out[#out + 1] = { kind = "title", height = TITLE_H, text = GROUP_TITLE[state] }
            for _, q in ipairs(by[state]) do
                out[#out + 1] = { kind = "quest", height = ROW_H, quest = q, chosen = q.id == chosenId }
            end
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- The detail
--------------------------------------------------------------------------------

local function buildDetail(root)
    local inset = Kit:Inset(root)
    inset:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -(FILTER_H + GAP - 4))
    inset:SetSize(DETAIL_W, BODY_H)
    local d = { inset = inset }

    local function at(el, x, y)
        el:ClearAllPoints()
        el:SetPoint("TOPLEFT", inset, "TOPLEFT", x, -y)
    end
    local function header(text)
        local h = Kit:Header(inset, text)
        h:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -60)
        h:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -12, -60)
        return h
    end
    d.at = at

    d.title = Kit:FixedText(inset, "title", DETAIL_INNER)
    d.titleHit = CreateFrame("Frame", nil, inset)
    d.titleHit:SetSize(DETAIL_INNER, 20)
    d.titleHit:EnableMouse(true)
    d.titleHit:SetScript("OnEnter", function(self) showTooltip(self, d.fullTitle) end)
    d.titleHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.sub = Kit:FixedText(inset, "grey", DETAIL_INNER)
    d.state = Kit:FixedText(inset, "value", DETAIL_INNER)

    d.objHeader = header(L["Objectives"])
    d.objects = {}
    for i = 1, MAX_OBJECTIVES do
        local o = CreateFrame("Frame", nil, inset)
        o:SetSize(DETAIL_INNER, 16)
        o:EnableMouse(true)
        o.tick = o:CreateTexture(nil, "ARTWORK")
        o.tick:SetSize(14, 14)
        o.tick:SetPoint("LEFT", o, "LEFT", 0, 0)
        o.tick:SetTexture(TICK)
        o.box = CreateFrame("Frame", nil, o)
        o.box:SetSize(10, 10)
        o.box:SetPoint("LEFT", o, "LEFT", 2, 0)
        o.edges = Kit:Edges(o.box, 0.66, 0.64, 0.59, 1)
        o.text = Kit:FixedText(o, "value", DETAIL_INNER - 22)
        o.text:SetPoint("LEFT", o, "LEFT", 22, 0)
        o:SetScript("OnEnter", function(self) showTooltip(self, self.honorLogFull) end)
        o:SetScript("OnLeave", function() GameTooltip:Hide() end)
        d.objects[i] = o
    end
    d.objNone = Kit:FixedText(inset, "grey", DETAIL_INNER)
    d.objNone:SetText(L["Pick it up to see its objectives."])

    d.paidHeader = header(L["What it paid you"])
    d.paidLines = {}
    for i = 1, MAX_PAID do
        local p = {}
        p.label = Kit:FixedText(inset, "labelSmall", 110)
        p.icon = Kit:MarkIcon(inset, 14)
        p.value = Kit:FixedText(inset, "value", 150)
        d.paidLines[i] = p
    end
    d.paidNone = Kit:FixedText(inset, "grey", DETAIL_INNER)
    d.paidNone:SetText(L["Hand it in once and HonorLog remembers what it pays."])
    d.paidFoot = Kit:FixedText(inset, "grey", DETAIL_INNER)

    d.placeHeader = header(L["Hand in at"])
    d.link = Kit:PlaceLink(inset)
    d.link.honorLogName:SetWidth(DETAIL_INNER - 22)
    d.link.honorLogName:SetWordWrap(false)
    d.link:HookScript("OnEnter", function(self)
        local p = self.honorLogPlace
        if type(p) == "table" then showTooltip(self, str(p.name)) end
    end)
    d.link:HookScript("OnLeave", function() GameTooltip:Hide() end)
    d.zone = Kit:FixedText(inset, "grey", DETAIL_INNER)
    d.map = Kit:Button(inset, L["Show on map"], "small")
    d.map:SetSize(120, 22)
    d.map:SetScript("OnClick", function()
        if d.place then HonorLog:ShowPlaceOnMap(d.place) end
    end)
    d.placeNone = Kit:FixedText(inset, "grey", DETAIL_INNER)
    d.placeNone:SetText(L["Hand it in once and HonorLog remembers where."])

    d.foot = Kit:Text(inset, "grey")
    d.foot:SetWidth(DETAIL_INNER)
    d.foot:SetWordWrap(true)
    d.foot:SetJustifyV("TOP")
    d.foot:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 12, 10)
    d.foot:SetText(L["HonorLog lists the PvP quests the game data names. Some may not be offered at your level."])

    d.empty = Kit:FixedText(inset, "grey", DETAIL_INNER)
    d.empty:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -14)
    d.empty:SetText(L["Choose a quest on the left."])
    return d
end

local function hideAll(d)
    for _, el in ipairs({ d.title, d.titleHit, d.sub, d.state, d.objHeader, d.objNone, d.paidHeader, d.paidNone, d.paidFoot,
        d.placeHeader, d.link, d.zone, d.map, d.placeNone, d.foot }) do
        el:Hide()
    end
    for _, o in ipairs(d.objects) do o:Hide() end
    for _, p in ipairs(d.paidLines) do
        p.label:Hide()
        p.icon:Hide()
        p.value:Hide()
    end
end

local function showDetail(d, q)
    hideAll(d)
    d.place, d.fullTitle = nil, nil
    d.empty:SetShown(q == nil)
    if not q then return end
    d.fullTitle = q.title
    local y = 10
    d.at(d.title, 12, y)
    d.title:SetText(q.title)
    d.title:Show()
    d.at(d.titleHit, 12, y)
    d.titleHit:Show()
    y = y + 26
    d.at(d.sub, 12, y)
    local sub = bgFull(q.bg)
    if q.level then sub = sub .. " " .. DOT .. " " .. string.format(L["Level %d"], q.level) end
    d.sub:SetText(sub)
    d.sub:Show()
    y = y + 18
    d.at(d.state, 12, y)
    d.state:SetText(STATE_TEXT[q.state] or "")
    d.state:Show()
    y = y + 26

    -- objectives
    d.at(d.objHeader, 12, y)
    d.objHeader:Show()
    y = y + 24
    local shown = 0
    if q.inLog and q.objectives then
        for i, o in ipairs(q.objectives) do
            local line = d.objects[i]
            if not line then break end
            d.at(line, 12, y)
            line.text:SetText(o.text)
            line.honorLogFull = o.text
            line.tick:SetShown(o.finished)
            for _, e in ipairs(line.edges) do e:SetShown(not o.finished) end
            line:Show()
            y = y + 17
            shown = shown + 1
        end
    end
    if shown == 0 then
        d.at(d.objNone, 12, y)
        d.objNone:SetText(q.inLog and L["No objectives to show."] or L["Pick it up to see its objectives."])
        d.objNone:Show()
        y = y + 17
    end
    y = y + 8

    -- what it paid
    d.at(d.paidHeader, 12, y)
    d.paidHeader:Show()
    y = y + 24
    local paid = q.paid
    local lines = {}
    if type(paid) == "table" then
        local honor, rank = num(paid.honor), num(paid.rank)
        if honor and honor > 0 then lines[#lines + 1] = { label = L["Honor"], value = commas(round(honor)) } end
        if rank and rank > 0 then lines[#lines + 1] = { label = L["Rank points"], value = commas(round(rank)) } end
        if type(paid.marks) == "table" then
            for _, bg in ipairs(HonorLog.BG_ORDER or {}) do
                local n = num(paid.marks[bg])
                if n and n > 0 then lines[#lines + 1] = { label = string.format(L["%s marks"], bgShort(bg)), value = tostring(round(n)), bg = bg } end
            end
        end
        local money, xp = num(paid.money), num(paid.xp)
        if money and money > 0 then lines[#lines + 1] = { label = L["Money"], value = moneyText(money) } end
        if xp and xp > 0 then lines[#lines + 1] = { label = L["Experience"], value = commas(round(xp)) } end
    end
    if type(paid) == "table" then
        for i, entry in ipairs(lines) do
            local p = d.paidLines[i]
            if not p then break end
            d.at(p.label, 12, y)
            p.label:SetText(entry.label)
            p.label:Show()
            if entry.bg then
                d.at(p.icon, 12 + 118, y - 1)
                p.icon:SetBattleground(entry.bg)
                p.icon:Show()
                d.at(p.value, 12 + 118 + 18, y)
            else
                d.at(p.value, 12 + 118, y)
            end
            p.value:SetText(entry.value)
            p.value:Show()
            y = y + 16
        end
        local count = num(paid.count) or 0
        local last = num(paid.last)
        if count > 0 then
            d.at(d.paidFoot, 12, y + 2)
            local when = last and date("%Y-%m-%d", last) or "-"
            d.paidFoot:SetText(count == 1 and string.format(L["Handed in once, on %s."], when)
                or string.format(L["Handed in %d times, last on %s."], count, when))
            d.paidFoot:Show()
            y = y + 20
        end
    else
        d.at(d.paidNone, 12, y)
        d.paidNone:Show()
        y = y + 17
    end
    y = y + 8

    -- where to hand it in
    d.at(d.placeHeader, 12, y)
    d.placeHeader:Show()
    y = y + 24
    if q.place then
        d.place = q.place
        d.at(d.link, 12, y)
        d.link:SetPlace(q.place)
        d.link.honorLogName:SetText(Kit:Cut(q.place.name, 34))
        d.link:SetWidth(math.min(DETAIL_INNER, 18 + (d.link.honorLogName:GetStringWidth() or 0)))
        d.link:Show()
        y = y + 20
        local zone = q.paid and q.paid.place
        local zoneText = zone and (str(zone.zone) or "") or ""
        local subzone = zone and str(zone.subzone)
        if subzone and subzone ~= "" and subzone ~= zoneText then
            zoneText = zoneText ~= "" and (zoneText .. " " .. DOT .. " " .. subzone) or subzone
        end
        if zoneText ~= "" then
            d.at(d.zone, 12, y)
            d.zone:SetText(zoneText)
            d.zone:Show()
            y = y + 18
        end
        d.at(d.map, 12, y + 2)
        d.map:Show()
    else
        d.at(d.placeNone, 12, y)
        d.placeNone:Show()
    end
    d.foot:Show()
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

    local list, detail, bgChips, levelChips
    local rows, chosenId = {}, nil
    local pending = false

    local function redraw()
        local entries = listEntries(rows, chosenId)
        list.area:honorLogSetContentHeight(list.stack:SetData(entries))
        list.empty:SetShown(#rows == 0)
    end
    local function chosenRow()
        for _, q in ipairs(rows) do
            if q.id == chosenId then return q end
        end
    end
    -- a click on a row: no new reads, the rows and the detail are drawn again from the list in hand
    local function onChoose(id)
        setSetting("windowQuest", id)
        chosenId = id
        runSteps({ redraw, function() showDetail(detail, chosenRow()) end })
    end
    local function changed()
        list.area:SetVerticalScroll(0)
        root:Refresh()
    end

    bgChips = Kit:Chips(area, function(key)
        setSetting("windowQuestBG", key)
        changed()
    end)
    bgChips:SetPoint("TOPLEFT", area, "TOPLEFT", Kit.PORTRAIT_CLEAR, -2)
    levelChips = Kit:Chips(area, function(key)
        setSetting("windowQuestLevels", key)
        changed()
    end)
    levelChips:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -2)
    list = buildList(area, onChoose)
    detail = buildDetail(area)

    local function open()
        return Window.current == "quests" and Window:IsShown() and root:IsShown()
    end

    function root:Refresh()
        runSteps({
            function()
                local options = { { key = "all", text = L["All"] } }
                for _, key in ipairs(bgKeys()) do options[#options + 1] = { key = key, text = bgShort(key) } end
                options[#options + 1] = { key = "other", text = L["Other"] }
                bgChips:SetOptions(options, bgFilter())
                levelChips:SetOptions({ { key = "mine", text = L["Your level range"] }, { key = "all", text = L["All levels"] } }, levelFilter())
            end,
            function()
                rows = safe(Quests.GetList, Quests, { bg = bgFilter(), levels = levelFilter() }) or {}
                local saved = settings() and num(settings().windowQuest)
                chosenId = nil
                for _, q in ipairs(rows) do
                    if q.id == saved then chosenId = saved end
                end
                if not chosenId and rows[1] then chosenId = rows[1].id end
            end,
            redraw,
            function() showDetail(detail, chosenRow()) end,
        })
        -- the quest log's changes are heard only while this screen is open
        if root.honorLogEvents then pcall(root.honorLogEvents.RegisterEvent, root.honorLogEvents, "QUEST_LOG_UPDATE") end
    end

    -- QUEST_LOG_UPDATE: one refresh a second at most, and only while this screen is the open one
    root.honorLogEvents = CreateFrame("Frame", nil, root)
    root.honorLogEvents:SetScript("OnEvent", function()
        if pending or not open() then return end
        pending = true
        C_Timer.After(THROTTLE, function()
            pending = false
            if open() then root:Refresh() end
        end)
    end)
    root:HookScript("OnHide", function() root.honorLogEvents:UnregisterAllEvents() end)

    root.honorLogParts = { bgChips = bgChips, levelChips = levelChips, list = list, detail = detail }
    root.honorLogOpen = open
    return root
end

-- A stored hand-in changes what the rows show.
HonorLog.RegisterCallback(QuestsScreen, "HonorLog_QuestPaid", function()
    if Window.current == "quests" and Window:IsShown() then Window:RefreshCurrent() end
end)

Window:RegisterScreen({ key = "quests", title = L["Quests"], order = 6, create = create })
