-- HonorLog vendor browser
-- The second mode of the Gear goals screen: every PvP vendor on the left, what the chosen one sells on the
-- right, with a star on each item that makes it a goal. Every number comes from Model.lua (GetVendorList,
-- GetVendorStock, GetVendorSets) and Data.lua; this file only lays them out. Each part guards its own reads,
-- so one failing part leaves the other drawn, and all the work happens in :Refresh(): nothing runs per frame.
--
-- Loaded after RankPane and before the screens; UI/Screens/Gear.lua builds it and shows it in vendors mode.

local _, HonorLog = ...
HonorLog = HonorLog or {}

local Util = HonorLog.Util
local num, str, call = Util.num, Util.str, Util.call
local L = HonorLog.L
local Kit = HonorLog.Kit

local GearVendors = {}
HonorLog.GearVendors = GearVendors

local PANEL_W, PANEL_H = 868, 490
local LIST_W = 250
local TABLE_W = PANEL_W - LIST_W - 8
local ROW_H, TITLE_H = 40, 22
local STOCK_ROW_H = 30
local MAX_SET_CHIPS = 5
local TICK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local DOT = "\194\183"

GearVendors.SLOT_NAMES = {
    HEAD = "Head", SHOULDER = "Shoulder", CHEST = "Chest", HANDS = "Hands", LEGS = "Legs", WAIST = "Waist",
    FEET = "Feet", WRIST = "Wrist", MAIN_HAND = "Main hand", TWO_HAND = "Two-hand", OFF_HAND = "Off-hand",
    RANGED = "Ranged", NECK = "Neck", FINGER = "Ring", TRINKET = "Trinket", BACK = "Back", RELIC = "Relic",
    TABARD = "Tabard", MOUNT = "Mount", TOKEN = "Seal", CONSUMABLE = "Consumable", OTHER = "Other",
}

function GearVendors.SlotName(slot)
    local name = GearVendors.SLOT_NAMES[slot]
    return name and L[name] or (str(slot) or "")
end

-- The first result of a model call, or nil when it raises.
local function safe(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
end

local function color(fs, name)
    local c = Kit.COLORS[name]
    fs:SetTextColor(c[1], c[2], c[3])
end

local function commas(n) return HonorLog.Rank.FormatNumber(n) end

local function settings() return HonorLog.db and HonorLog.db.settings end

local function showTooltip(owner, text, r, g, b)
    if not text or text == "" then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(text, r or 1, g or 1, b or 1, true)
    GameTooltip:Show()
end

-- A fixed-width one-line text: the client cuts it with "..." when it is longer than its box.
local function fixedText(parent, style, width)
    local fs = Kit:Text(parent, style)
    fs:SetWidth(width)
    fs:SetWordWrap(false)
    return fs
end

-- Shared with UI/Screens/Gear.lua.
GearVendors.safe, GearVendors.color, GearVendors.commas = safe, color, commas
GearVendors.showTooltip, GearVendors.fixedText = showTooltip, fixedText

--------------------------------------------------------------------------------
-- A stack of pooled rows of different heights
--------------------------------------------------------------------------------

-- Rows of several kinds in one scrolling child, each kind with its own height. makers[kind] =
-- { create = function(row), update = function(row, entry) }; an entry is { kind, height, ... }. A row frame is
-- made once per kind and position and reused, so the number of frames grows to the longest list and no further.
-- stack:SetData(entries) returns the content height. Shared with UI/Screens/Gear.lua.
function GearVendors.Stack(child, makers)
    local stack = { pools = {}, height = 0, count = 0 }
    function stack:SetData(entries)
        local used, y = {}, 0
        for _, entry in ipairs(entries or {}) do
            local kind = entry.kind
            local maker = makers[kind]
            local pool = self.pools[kind]
            if not pool then
                pool = {}
                self.pools[kind] = pool
            end
            used[kind] = (used[kind] or 0) + 1
            local row = pool[used[kind]]
            if not row then
                row = CreateFrame("Frame", nil, child)
                maker.create(row)
                pool[used[kind]] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
            row:SetHeight(entry.height)
            row:Show()
            row.honorLogEntry = entry
            maker.update(row, entry)
            y = y + entry.height
        end
        for kind, pool in pairs(self.pools) do
            for i = (used[kind] or 0) + 1, #pool do pool[i]:Hide() end
        end
        self.height, self.count = y, #(entries or {})
        return y
    end
    return stack
end

-- The wash and 3 px gold edge of a chosen row, so a choice is not colour alone.
function GearVendors.AddChosenMarks(row)
    row.wash = row:CreateTexture(nil, "BACKGROUND")
    row.wash:SetAllPoints(row)
    row.wash:SetColorTexture(0.5, 0.08, 0.06, 0.45)
    row.wash:Hide()
    row.edge = row:CreateTexture(nil, "ARTWORK")
    row.edge:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.edge:SetWidth(3)
    row.edge:SetColorTexture(1, 0.82, 0, 1)
    row.edge:Hide()
end

function GearVendors.SetChosen(row, chosen)
    row.wash:SetShown(chosen)
    row.edge:SetShown(chosen)
end

--------------------------------------------------------------------------------
-- Vendor list
--------------------------------------------------------------------------------

local LIST_AREA_W = LIST_W - 12 - Kit.SCROLL_BAR_SPACE
local LIST_AREA_H = PANEL_H - 8 - 36

local function buildList(root, onChoose)
    local inset = Kit:Inset(root)
    inset:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    inset:SetSize(LIST_W, PANEL_H)
    local l = { inset = inset }

    l.area = Kit:ScrollArea(inset)
    l.area:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -8)
    l.area:SetSize(LIST_AREA_W, LIST_AREA_H)

    l.foot = fixedText(inset, "grey", LIST_W - 24)
    l.foot:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 12, 12)
    l.foot:SetText(L["Counts are what your class can use."])

    l.stack = GearVendors.Stack(l.area.honorLogChild, {
        title = {
            create = function(row)
                row.text = fixedText(row, "labelSmall", LIST_AREA_W - 16)
                row.text:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 3)
            end,
            update = function(row, entry) row.text:SetText(entry.text or "") end,
        },
        vendor = {
            create = function(row)
                GearVendors.AddChosenMarks(row)
                -- first, so the texts and the pin above it stay visible and the hover covers the whole row
                row.click = CreateFrame("Button", nil, row)
                row.click:SetAllPoints(row)
                local hl = row.click:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(row.click)
                hl:SetColorTexture(1, 1, 1, 0.07)
                row.name = fixedText(row, "value", 150)
                row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -5)
                row.role = fixedText(row, "grey", 160)
                row.role:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -23)
                row.pin = row:CreateTexture(nil, "ARTWORK")
                row.pin:SetSize(12, 12)
                row.pin:SetPoint("RIGHT", row, "RIGHT", -44, 0)
                Kit:SetAtlasOr(row.pin, "Waypoint-MapPin-Untracked", 0.6, 0.6, 0.6, 1)
                row.pin:SetVertexColor(0.6, 0.6, 0.6, 1)
                row.count = fixedText(row, "value", 34)
                row.count:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                row.count:SetJustifyH("RIGHT")
                color(row.count, "gold")
                row.click:SetScript("OnClick", function()
                    local entry = row.honorLogEntry
                    if entry and onChoose then onChoose(entry.vendor.key) end
                end)
                row.click:SetScript("OnEnter", function()
                    local v = row.honorLogEntry and row.honorLogEntry.vendor
                    if not v then return end
                    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(str(v.name) or "", 1, 1, 1)
                    if v.role then GameTooltip:AddLine(v.role, 0.66, 0.64, 0.59) end
                    if not v.known then
                        GameTooltip:AddLine(L["Not found yet. Open this vendor once and HonorLog remembers where it is."], 1, 0.6, 0.24, true)
                    end
                    GameTooltip:Show()
                end)
                row.click:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end,
            update = function(row, entry)
                local v = entry.vendor
                row.name:SetText(str(v.name) or "")
                row.role:SetText(str(v.role) or "")
                row.count:SetText(tostring(num(v.count) or 0))
                row.pin:SetShown(not v.known)
                GearVendors.SetChosen(row, entry.chosen)
            end,
        },
    })
    return l
end

-- The quartermasters (every kind but supply) under the first one's place, then the supply officers.
local function listEntries(vendors, chosenKey)
    local quarter, supply = {}, {}
    for _, v in ipairs(vendors) do
        if v.kind == "supply" then supply[#supply + 1] = v else quarter[#quarter + 1] = v end
    end
    local out = {}
    if #quarter > 0 then
        out[#out + 1] = { kind = "title", height = TITLE_H, text = str(quarter[1].place) or L["Quartermasters"] }
        for _, v in ipairs(quarter) do out[#out + 1] = { kind = "vendor", height = ROW_H, vendor = v, chosen = v.key == chosenKey } end
    end
    if #supply > 0 then
        out[#out + 1] = { kind = "title", height = TITLE_H, text = L["Battleground supply officers"] }
        for _, v in ipairs(supply) do out[#out + 1] = { kind = "vendor", height = ROW_H, vendor = v, chosen = v.key == chosenKey } end
    end
    return out
end

local function refreshList(l, vendors, chosenKey)
    local height = l.stack:SetData(listEntries(vendors, chosenKey))
    l.area:honorLogSetContentHeight(height)
end

--------------------------------------------------------------------------------
-- Stock table
--------------------------------------------------------------------------------

local COL = {
    item = { x = 4, w = 184 }, slot = { x = 192, w = 64 }, needs = { x = 260, w = 60 }, honor = { x = 324, w = 54 },
    marks = { x = 382, w = 64 }, upgrade = { x = 450, w = 70 }, star = { x = 524, w = 48 },
}
local STOCK_AREA_W = TABLE_W - 12 - Kit.SCROLL_BAR_SPACE
local STOCK_TOP = 120
local HEIGHT_PLAIN = PANEL_H - STOCK_TOP - 36
local HEIGHT_WITH_TOTALS = HEIGHT_PLAIN - 24

-- "R4 · L55" with its tone: nil text when the item needs neither.
local function needsOf(data, info, level)
    local parts, unmet, words = {}, false, {}
    local rank = num(data.rank)
    if rank and rank > 0 then
        parts[#parts + 1] = "R" .. rank
        words[#words + 1] = string.format(L["Rank %d"], rank)
        if not (info and num(info.rank) and info.rank >= rank) then unmet = true end
    end
    local req = num(data.reqLevel)
    if req and req > 1 then
        parts[#parts + 1] = "L" .. req
        words[#words + 1] = string.format(L["Level %d"], req)
        if not (level and level >= req) then unmet = true end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " " .. DOT .. " "), unmet, table.concat(words, " " .. DOT .. " ")
end

local function bgOrder() return HonorLog.BG_ORDER or {} end

local function buildStock(root, handlers)
    local inset = Kit:Inset(root)
    inset:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
    inset:SetSize(TABLE_W, PANEL_H)
    local t = { inset = inset }

    -- head
    t.name = fixedText(inset, "title", 380)
    t.name:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -8)
    t.role = fixedText(inset, "grey", 380)
    t.role:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -30)
    t.link = Kit:PlaceLink(inset)
    t.link:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -48)
    t.back = Kit:Button(inset, L["Back to goals"], "small")
    t.back:SetSize(120, 22)
    t.back:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -12, -8)
    t.back:SetScript("OnClick", function() if handlers.onBack then handlers.onBack() end end)
    t.map = Kit:Button(inset, L["Show on map"], "small")
    t.map:SetSize(120, 22)
    t.map:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -12, -36)
    t.map:SetScript("OnClick", function()
        if t.vendor then HonorLog:ShowVendorOnMap(t.vendor) end
    end)

    -- filters: sets at the left, the class at the right
    t.classChips = Kit:Chips(inset, function(key) handlers.onClass(key) end)
    t.classChips:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -12, -76)
    t.setChips = Kit:Chips(inset, function(key) handlers.onSet(key) end)
    t.setChips:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -76)

    -- column titles
    local titles = {
        { COL.item, L["Item"] }, { COL.slot, L["Slot"] }, { COL.needs, L["Needs"] }, { COL.honor, L["Honor"] },
        { COL.marks, L["Marks"] }, { COL.upgrade, L["Epic upgrade"] }, { COL.star, "" },
    }
    t.titles = {}
    for i, c in ipairs(titles) do
        local fs = fixedText(inset, "labelSmall", c[1].w)
        fs:SetPoint("TOPLEFT", inset, "TOPLEFT", 6 + c[1].x, -104)
        fs:SetText(c[2])
        t.titles[i] = fs
    end

    t.area = Kit:ScrollArea(inset)
    t.area:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -STOCK_TOP)
    t.area:SetSize(STOCK_AREA_W, HEIGHT_PLAIN)

    t.empty = Kit:Text(inset, "grey")
    t.empty:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -STOCK_TOP - 8)
    t.empty:SetText(L["Nothing here for your class. Try All classes."])
    t.empty:Hide()

    -- the whole set's price, under the table
    local totals = CreateFrame("Frame", nil, inset)
    totals:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 12, 36)
    totals:SetSize(TABLE_W - 24, 20)
    totals:Hide()
    totals.label = Kit:Text(totals, "labelSmall")
    totals.label:SetPoint("LEFT", totals, "LEFT", 0, 0)
    totals.label:SetText(L["Whole set"])
    totals.honor = fixedText(totals, "value", 110)
    totals.honor:SetPoint("LEFT", totals, "LEFT", 72, 0)
    totals.marks = {}
    for _, bg in ipairs(bgOrder()) do
        local w = { icon = Kit:MarkIcon(totals, 14), count = fixedText(totals, "value", 34) }
        w.icon:SetBattleground(bg)
        w.icon:Hide()
        w.count:Hide()
        totals.marks[bg] = w
    end
    totals.gold = fixedText(totals, "value", 80)
    t.totals = totals

    t.foot = fixedText(inset, "grey", TABLE_W - 24)
    t.foot:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 12, 12)
    t.foot:SetText(L["The star adds a goal. Prices come from the vendor once you have opened it, otherwise from game data."])
    t.foot.honorLogTip = t.foot:GetText()

    t.stack = GearVendors.Stack(t.area.honorLogChild, {
        item = {
            create = function(row)
                row.stripe = row:CreateTexture(nil, "BACKGROUND")
                row.stripe:SetAllPoints(row)
                row.stripe:SetColorTexture(1, 1, 1, 0.04)
                row.icon = Kit:ItemIcon(row, 24)
                row.icon:SetPoint("LEFT", row, "LEFT", COL.item.x, 0)
                row.name = fixedText(row, "value", COL.slot.x - COL.item.x - 28 - 4)
                row.name:SetPoint("LEFT", row, "LEFT", COL.item.x + 28, 0)
                row.slot = fixedText(row, "value", COL.slot.w)
                row.slot:SetPoint("LEFT", row, "LEFT", COL.slot.x, 0)

                row.needsCell = CreateFrame("Frame", nil, row)
                row.needsCell:SetPoint("LEFT", row, "LEFT", COL.needs.x, 0)
                row.needsCell:SetSize(COL.needs.w, STOCK_ROW_H)
                row.needsCell:EnableMouse(true)
                row.needs = fixedText(row.needsCell, "value", COL.needs.w)
                row.needs:SetPoint("LEFT", row.needsCell, "LEFT", 0, 0)
                row.needsCell:SetScript("OnEnter", function(self) showTooltip(self, self.tip) end)
                row.needsCell:SetScript("OnLeave", function() GameTooltip:Hide() end)

                row.honorCell = CreateFrame("Frame", nil, row)
                row.honorCell:SetPoint("LEFT", row, "LEFT", COL.honor.x, 0)
                row.honorCell:SetSize(COL.honor.w, STOCK_ROW_H)
                row.honor = fixedText(row.honorCell, "value", COL.honor.w)
                row.gold = fixedText(row.honorCell, "grey", COL.honor.w)

                row.marksCell = CreateFrame("Frame", nil, row)
                row.marksCell:SetPoint("LEFT", row, "LEFT", COL.marks.x, 0)
                row.marksCell:SetSize(COL.marks.w, STOCK_ROW_H)
                row.marks = {}
                for i = 1, 2 do
                    local w = { icon = Kit:MarkIcon(row.marksCell, 14), count = fixedText(row.marksCell, "value", 26) }
                    w.icon:Hide()
                    w.count:Hide()
                    row.marks[i] = w
                end

                row.upgradeCell = CreateFrame("Frame", nil, row)
                row.upgradeCell:SetPoint("LEFT", row, "LEFT", COL.upgrade.x, 0)
                row.upgradeCell:SetSize(COL.upgrade.w, STOCK_ROW_H)
                row.upgradeIcon = Kit:ItemIcon(row.upgradeCell, 18)
                row.upgradeIcon:SetPoint("LEFT", row.upgradeCell, "LEFT", 0, 0)
                row.upgradeRank = fixedText(row.upgradeCell, "value", COL.upgrade.w - 22)
                row.upgradeRank:SetPoint("TOPLEFT", row.upgradeCell, "TOPLEFT", 22, -3)
                row.upgradeHonor = fixedText(row.upgradeCell, "grey", COL.upgrade.w - 22)
                row.upgradeHonor:SetPoint("TOPLEFT", row.upgradeCell, "TOPLEFT", 22, -17)

                row.starCell = CreateFrame("Frame", nil, row)
                row.starCell:SetPoint("LEFT", row, "LEFT", COL.star.x, 0)
                row.starCell:SetSize(COL.star.w, STOCK_ROW_H)
                row.star = Kit:Star(row.starCell, 18)
                row.star:SetPoint("LEFT", row.starCell, "LEFT", 0, 0)
                row.star.honorLogOnToggle = function(star, on)
                    local entry = row.honorLogEntry
                    if not entry then return end
                    if on then HonorLog:AddGoal(entry.row.itemID) else HonorLog:RemoveGoal(entry.row.itemID) end
                    -- the goal list is the truth: a refused add puts the star back
                    star:SetOn(HonorLog:IsGoal(entry.row.itemID))
                end
                row.tick = row.starCell:CreateTexture(nil, "ARTWORK")
                row.tick:SetSize(12, 12)
                row.tick:SetPoint("LEFT", row.starCell, "LEFT", 0, 0)
                row.tick:SetTexture(TICK)
                row.owned = fixedText(row.starCell, "grey", COL.star.w - 16)
                row.owned:SetPoint("LEFT", row.starCell, "LEFT", 16, 0)
                row.owned:SetText(L["Owned"])
            end,
            update = function(row, entry)
                local r = entry.row
                local data = r.data or {}
                row.stripe:SetShown(entry.striped)
                row.icon:SetItem(r.itemID)
                row.name:SetText(Kit:QualityHex(row.icon.honorLogQuality) .. (str(r.name) or "") .. "|r")
                row.slot:SetText(GearVendors.SlotName(r.slot))
                color(row.slot, "grey")

                local text, unmet, words = needsOf(data, entry.info, entry.level)
                row.needs:SetText(text or "-")
                color(row.needs, text and (unmet and "orange" or "grey") or "grey")
                row.needsCell.tip = words

                -- honor, with a gold price under it, or alone in its place
                local honor, gold = num(data.honor) or 0, num(data.gold) or 0
                row.honor:ClearAllPoints()
                row.gold:ClearAllPoints()
                if honor > 0 and gold > 0 then
                    row.honor:SetPoint("TOPLEFT", row.honorCell, "TOPLEFT", 0, -3)
                    row.gold:SetPoint("TOPLEFT", row.honorCell, "TOPLEFT", 0, -17)
                    row.honor:SetText(commas(honor))
                    row.gold:SetText(HonorLog:GoldShort(gold))
                    row.gold:Show()
                elseif gold > 0 then
                    row.honor:SetPoint("LEFT", row.honorCell, "LEFT", 0, 0)
                    row.honor:SetText(HonorLog:GoldShort(gold))
                    row.gold:SetText("")
                    row.gold:Hide()
                else
                    row.honor:SetPoint("LEFT", row.honorCell, "LEFT", 0, 0)
                    row.honor:SetText(honor > 0 and commas(honor) or "-")
                    row.gold:SetText("")
                    row.gold:Hide()
                end

                -- marks: up to two battlegrounds
                local x, n = 0, 0
                for _, bg in ipairs(bgOrder()) do
                    local count = data.marks and num(data.marks[bg])
                    if count and count > 0 and n < 2 then
                        n = n + 1
                        local w = row.marks[n]
                        w.icon:SetBattleground(bg)
                        w.icon:ClearAllPoints()
                        w.icon:SetPoint("LEFT", row.marksCell, "LEFT", x, 0)
                        w.icon:Show()
                        w.count:ClearAllPoints()
                        w.count:SetPoint("LEFT", w.icon, "RIGHT", 3, 0)
                        w.count:SetText(tostring(count))
                        w.count:Show()
                        x = x + 14 + 3 + (num(w.count:GetStringWidth()) or 12) + 6
                    end
                end
                for i = n + 1, 2 do
                    row.marks[i].icon:Hide()
                    row.marks[i].count:Hide()
                end

                -- the epic upgrade of a blue piece
                local up = r.upgrade
                row.upgradeCell:SetShown(up ~= nil)
                if up then
                    row.upgradeIcon:SetItem(up.itemID)
                    row.upgradeRank:SetText(string.format(L["Rank %d"], num(up.rank) or 0))
                    row.upgradeHonor:SetText(commas(num(up.honor) or 0))
                end

                -- the star, or a tick when the item is already worn or carried
                row.star:SetShown(not r.owned)
                row.tick:SetShown(r.owned and true or false)
                row.owned:SetShown(r.owned and true or false)
                row.star:SetOn(r.isGoal and true or false)
            end,
        },
    })
    return t
end

-- Name and count as one chip text, the name cut so both fit the width.
local function setChipText(set, maxWidth)
    local suffix = " " .. tostring(set.count)
    local room = math.floor((maxWidth - 16) / 6) - #suffix
    return Kit:Cut(set.name, math.max(4, room)) .. suffix
end

local function refreshStock(t, state)
    local vendor = state.vendor
    t.vendor = vendor
    local has = vendor ~= nil
    t.name:SetShown(has)
    t.role:SetShown(has)
    t.link:SetShown(has)
    t.map:SetShown(has)
    if has then
        t.name:SetText(str(vendor.name) or "")
        t.role:SetText(str(vendor.role) or "")
        t.link:SetVendor(vendor)
        -- the place, not the name again (the name is the title above)
        local place = str(vendor.place)
        if place and place ~= "" then
            t.link.honorLogName:SetText(place)
            t.link:SetWidth(18 + (num(t.link.honorLogName:GetStringWidth()) or 0))
        end
    end

    -- filters: the class chips are two options; the set chips are All and up to five sets
    local className = state.className
    t.classChips:SetOptions({
        { key = "player", text = className, maxWidth = 90 }, { key = "all", text = L["All classes"] },
    }, state.classMode)
    local available = TABLE_W - 24 - (num(t.classChips:GetWidth()) or 0) - 12
    local sets = {}
    for i = 1, math.min(#state.sets, MAX_SET_CHIPS) do sets[i] = state.sets[i] end
    local options = { { key = "all", text = L["All"] } }
    local each = #sets > 0 and math.floor((available - 36 - #sets * 4) / #sets) or 0
    for _, set in ipairs(sets) do
        local text = setChipText(set, math.min(each, 120))
        options[#options + 1] = { key = set.id, text = text, tip = string.format("%s (%d)", set.name, set.count) }
    end
    t.setChips:SetOptions(options, state.set or "all")

    local rows = state.rows
    local entries = {}
    for i, r in ipairs(rows) do
        entries[i] = { kind = "item", height = STOCK_ROW_H, row = r, striped = i % 2 == 0, info = state.info, level = state.level }
    end
    t.area:SetHeight(state.set and HEIGHT_WITH_TOTALS or HEIGHT_PLAIN)
    t.area:honorLogSetContentHeight(t.stack:SetData(entries))
    t.empty:SetShown(#rows == 0)

    -- the whole set: what the player does not own yet
    local totals = t.totals
    totals:SetShown(state.set ~= nil and #rows > 0)
    if state.set ~= nil and #rows > 0 then
        local honor, gold, marks = 0, 0, {}
        for _, r in ipairs(rows) do
            if not r.owned and r.data then
                honor = honor + (num(r.data.honor) or 0)
                gold = gold + (num(r.data.gold) or 0)
                for bg, n in pairs(r.data.marks or {}) do marks[bg] = (marks[bg] or 0) + (num(n) or 0) end
            end
        end
        totals.honor:SetText(honor > 0 and string.format(L["%s honor"], commas(honor)) or "")
        local x = 72 + 112
        for _, bg in ipairs(bgOrder()) do
            local w = totals.marks[bg]
            local n = marks[bg] or 0
            if n > 0 then
                w.icon:ClearAllPoints()
                w.icon:SetPoint("LEFT", totals, "LEFT", x, 0)
                w.icon:Show()
                w.count:ClearAllPoints()
                w.count:SetPoint("LEFT", w.icon, "RIGHT", 3, 0)
                w.count:SetText(tostring(n))
                w.count:Show()
                x = x + 14 + 3 + (num(w.count:GetStringWidth()) or 12) + 10
            else
                w.icon:Hide()
                w.count:Hide()
            end
        end
        totals.gold:ClearAllPoints()
        totals.gold:SetPoint("LEFT", totals, "LEFT", x, 0)
        totals.gold:SetText(gold > 0 and HonorLog:GoldShort(gold) or "")
    end
end

--------------------------------------------------------------------------------
-- The browser
--------------------------------------------------------------------------------

-- GearVendors:Create(parent, onBack) builds the browser in a frame that fills parent (868 x 490); the screen
-- shows and hides gv.frame. gv:Refresh() redraws it.
function GearVendors:Create(parent, onBack)
    local gv = { set = nil }
    local root = CreateFrame("Frame", nil, parent)
    root:SetAllPoints(parent)
    gv.frame = root

    local function redraw() if HonorLog.Window then HonorLog.Window:RefreshCurrent() end end
    gv.list = buildList(root, function(key)
        local s = settings()
        if s then s.windowVendor = key end
        gv.set = nil
        redraw()
    end)
    gv.stock = buildStock(root, {
        onBack = onBack,
        onSet = function(key)
            gv.set = key ~= "all" and key or nil
            redraw()
        end,
        onClass = function(key)
            local s = settings()
            if s then s.windowVendorClass = key == "all" and "all" or "player" end
            gv.set = nil
            redraw()
        end,
    })

    function gv:Refresh()
        local s = settings() or {}
        local vendors = safe(HonorLog.GetVendorList, HonorLog) or {}
        local chosen
        for _, v in ipairs(vendors) do
            if v.key == s.windowVendor then chosen = v break end
        end
        chosen = chosen or vendors[1]
        local classMode = s.windowVendorClass == "all" and "all" or "player"
        local classArg = classMode == "all" and "ALL" or nil
        local sets = chosen and safe(HonorLog.GetVendorSets, HonorLog, chosen, classArg) or {}
        -- a set the new filter no longer offers is dropped
        local offered = nil
        for _, set in ipairs(sets) do
            if set.id == self.set then offered = set.id end
        end
        self.set = offered
        local rows = chosen and safe(HonorLog.GetVendorStock, HonorLog, chosen, { class = classArg, set = self.set }) or {}
        local info = safe(HonorLog.Rank.GetInfo, HonorLog.Rank)
        local className = str((call(UnitClass, "player"))) or L["Your class"]
        local state = { vendor = chosen, sets = sets, set = self.set, rows = rows, classMode = classMode, className = className,
            info = info, level = num(call(UnitLevel, "player")) }
        -- each part guards its own reads, and one failing part leaves the other drawn
        for _, step in ipairs({
            function() refreshList(self.list, vendors, chosen and chosen.key) end,
            function() refreshStock(self.stock, state) end,
        }) do
            local ok, err = pcall(step)
            if not ok then
                local handler = geterrorhandler and geterrorhandler()
                if handler then handler(err) end
            end
        end
    end
    return gv
end
