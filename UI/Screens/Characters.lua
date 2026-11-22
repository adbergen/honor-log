-- HonorLog Characters screen
-- The last screen of the full window: every character of the account side by side, one card each. A card says
-- who it is and when it was last played, its PvP rank and where it stands this week, its honor against the
-- cap, the battleground marks it holds and its next gear goal. Every value comes from
-- HonorLog:GetCharacterRows() (Model.lua, over Modules/Characters.lua); this file only lays them out. A value
-- the record does not hold is left out, never drawn as 0 or "?".
--
-- Refresh first asks Characters:Snapshot() for a fresh line of the character being played, so its card is not
-- as old as its last game. Each part is drawn under pcall, so one failing part leaves the rest drawn, and all the
-- work happens in the screen's Refresh: nothing runs per frame.
--
-- Forget: a card of a character other than the current one has a small "Forget" button, for a character that was
-- deleted. One click only arms it (its text changes and C_Timer disarms it again after a few seconds); the second
-- click within that time removes the record. There is no pop-up.
--
-- Widths: a 12 point text is about 6.3 px a character, a 10 point text about 5.2 px. Every text that can outgrow
-- its box is a fixed-width text (the client cuts it with "...") with a hover frame over it that carries the full
-- text in a tooltip. The meaning of a week line is in its words; its colour only supports them.
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

local safe, color, commas = Vendors.safe, Vendors.color, Vendors.commas

local PANEL_W, PANEL_H = 868, 490
local LIST_Y, LIST_H = 30, 438
local LIST_W = PANEL_W - Kit.SCROLL_BAR_SPACE -- 846
local CARD_H, CARD_STEP = 80, 86 -- a card and the 6 px gap after it: five fit in the list
local NOTE_H = 22
local FOOT_Y = 474
local FORGET_SECONDS = 4 -- how long a first click on Forget stays armed

-- Columns of a card (x within the card, width). The portrait covers the top left corner of the first card, so
-- nothing of it starts above y = 8.
local COL_WHO, COL_WHO_W = 17, 200
local COL_RANK, COL_RANK_W = 231, 180
local COL_HONOR, COL_HONOR_W = 425, 170
local COL_GOAL, COL_GOAL_W = 609, 225
local ICON = 34
local MARK, MARK_STEP = 16, 42

local CharactersScreen = {}
HonorLog.CharactersScreen = CharactersScreen

local TONE_COLOR = { capped = "green", gate = "orange", progress = "white" }

local function runSteps(steps)
    for _, step in ipairs(steps) do
        local ok, err = pcall(step)
        if not ok then
            local handler = geterrorhandler and geterrorhandler()
            if handler then handler(err) end
        end
    end
end

local function hexOf(r, g, b)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- A frame over a text (or any box) that shows its text in a tooltip: x, y from the card's top left corner.
local function hoverFrame(face, x, y, w, h)
    local hit = CreateFrame("Frame", nil, face)
    hit:SetSize(w, h)
    hit:SetPoint("TOPLEFT", face, "TOPLEFT", x, -y)
    hit:EnableMouse(true)
    hit.honorLogLines = false
    hit:SetScript("OnEnter", function(self)
        local lines = self.honorLogLines
        if type(lines) ~= "table" or #lines == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for i, line in ipairs(lines) do
            if i == 1 then GameTooltip:AddLine(line, 1, 0.82, 0) else GameTooltip:AddLine(line, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return hit
end

-- A fixed-width one-line text at (x, y) of the card with its hover frame: text:SetText plus hit.honorLogLines.
local function cutText(face, style, x, y, w, h)
    local fs = Kit:FixedText(face, style, w)
    fs:SetPoint("TOPLEFT", face, "TOPLEFT", x, -y)
    local hit = hoverFrame(face, x, y, w, h)
    return fs, hit
end

--------------------------------------------------------------------------------
-- One card
--------------------------------------------------------------------------------

local function createCard(row, ctx)
    row.inset = Kit:Inset(row)
    row.inset:SetSize(LIST_W, CARD_H)
    row.inset:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    -- the inset may be a Blizzard template: our own frame above it holds everything that is drawn
    local face = CreateFrame("Frame", nil, row)
    face:SetAllPoints(row.inset)
    face:SetFrameLevel((num(row.inset:GetFrameLevel()) or 0) + 1)
    row.face = face

    row.edge = face:CreateTexture(nil, "ARTWORK")
    row.edge:SetSize(3, CARD_H - 12)
    row.edge:SetPoint("TOPLEFT", face, "TOPLEFT", 0, -6)

    -- who
    row.name, row.nameHit = cutText(face, "title", COL_WHO, 8, COL_WHO_W, 20)
    row.level = Kit:FixedText(face, "value", COL_WHO_W)
    row.level:SetPoint("TOPLEFT", face, "TOPLEFT", COL_WHO, -31)
    row.last = Kit:FixedText(face, "grey", 120)
    row.last:SetPoint("TOPLEFT", face, "TOPLEFT", COL_WHO, -54)
    row.stub = Kit:FixedText(face, "grey", 560)
    row.stub:SetPoint("TOPLEFT", face, "TOPLEFT", COL_WHO, -32)

    -- forget
    row.forget = Kit:Button(face, L["Forget"], "small")
    row.forget.honorLogArmedKey, row.forget.honorLogToken = false, 0
    row.forget:SetSize(74, 20)
    row.forget:SetPoint("TOPLEFT", face, "TOPLEFT", 141, -50)
    row.forget:SetFrameLevel((num(face:GetFrameLevel()) or 0) + 3)
    row.forget:SetScript("OnClick", function(self)
        local key = row.honorLogKey
        if not key or row.honorLogCurrent then return end
        if self.honorLogArmedKey == key then
            self.honorLogArmedKey = false
            self:SetText(L["Forget"])
            local Characters = HonorLog.Characters
            if Characters then pcall(Characters.Forget, Characters, key) end
            ctx.refresh()
            return
        end
        -- first click: arm, and disarm again by itself
        ctx.armed = (ctx.armed or 0) + 1
        local token = ctx.armed
        self.honorLogArmedKey, self.honorLogToken = key, token
        self:SetText(L["Click again"])
        C_Timer.After(FORGET_SECONDS, function()
            if self.honorLogToken == token and self.honorLogArmedKey then
                self.honorLogArmedKey = false
                self:SetText(L["Forget"])
            end
        end)
    end)
    row.forget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Forget"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Removes this character's saved line. It comes back when you log in with it again."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row.forget:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- rank
    row.rankHead = Kit:Text(face, "labelSmall")
    row.rankHead:SetPoint("TOPLEFT", face, "TOPLEFT", COL_RANK, -8)
    row.rankHead:SetText(L["Rank"])
    row.badge = Kit:RankBadge(face, 20)
    row.badge:SetPoint("TOPLEFT", face, "TOPLEFT", COL_RANK, -26)
    row.title, row.titleHit = cutText(face, "value", COL_RANK + 28, 29, COL_RANK_W - 28, 16)
    row.week, row.weekHit = cutText(face, "value", COL_RANK, 54, COL_RANK_W, 16)

    -- honor
    row.honorHead = Kit:Text(face, "labelSmall")
    row.honorHead:SetPoint("TOPLEFT", face, "TOPLEFT", COL_HONOR, -8)
    row.honorHead:SetText(L["Honor"])
    row.honor = Kit:FixedText(face, "value", 120)
    row.honor:SetPoint("TOPLEFT", face, "TOPLEFT", COL_HONOR + COL_HONOR_W - 120, -7)
    row.honor:SetJustifyH("RIGHT")
    row.bar = Kit:Bar(face)
    row.bar:SetSize(COL_HONOR_W, 8)
    row.bar:SetPoint("TOPLEFT", face, "TOPLEFT", COL_HONOR, -28)
    row.marks = {}
    local slots = math.max(4, #(HonorLog.BG_ORDER or {}))
    for i = 1, slots do
        local icon = Kit:MarkIcon(face, MARK)
        icon:SetPoint("TOPLEFT", face, "TOPLEFT", COL_HONOR + (i - 1) * MARK_STEP, -46)
        -- the small font: a three-digit count still fits its slot beside the icon
        local count = Kit:FixedText(face, "grey", MARK_STEP - MARK - 3)
        count:SetTextColor(1, 1, 1)
        count:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        row.marks[i] = { icon = icon, count = count }
    end

    -- next goal
    row.goalHead = Kit:Text(face, "labelSmall")
    row.goalHead:SetPoint("TOPLEFT", face, "TOPLEFT", COL_GOAL, -8)
    row.goalHead:SetText(L["Next goal"])
    row.goalIcon = Kit:ItemIcon(face, ICON)
    row.goalIcon:SetPoint("TOPLEFT", face, "TOPLEFT", COL_GOAL, -26)
    local textX, textW = COL_GOAL + ICON + 8, COL_GOAL_W - ICON - 8
    row.goalName = Kit:FixedText(face, "value", textW)
    row.goalName:SetPoint("TOPLEFT", face, "TOPLEFT", textX, -28)
    row.goalNote = Kit:FixedText(face, "grey", textW)
    row.goalNote:SetPoint("TOPLEFT", face, "TOPLEFT", textX, -46)
    row.goalHit = hoverFrame(face, textX, 28, textW, 32)
    row.noGoal = Kit:FixedText(face, "value", COL_GOAL_W)
    row.noGoal:SetPoint("TOPLEFT", face, "TOPLEFT", COL_GOAL, -28)
    row.noGoal:SetText(L["No goals yet"])
    row.noGoalNote = Kit:FixedText(face, "grey", COL_GOAL_W)
    row.noGoalNote:SetPoint("TOPLEFT", face, "TOPLEFT", COL_GOAL, -46)
    row.noGoalNote:SetText(L["Pick gear to aim for on this character."])
end

-- Back to the first label of the Forget button when the row now shows another character.
local function disarm(row)
    if row.forget.honorLogArmedKey and row.forget.honorLogArmedKey ~= row.honorLogKey then
        row.forget.honorLogArmedKey = false
    end
    row.forget:SetText(row.forget.honorLogArmedKey and L["Click again"] or L["Forget"])
end

local function setShown(list, shown)
    for _, f in ipairs(list) do f:SetShown(shown) end
end

local function updateCard(row, entry)
    local rec = entry.rec
    row.honorLogKey, row.honorLogCurrent = rec.key, rec.current == true
    disarm(row)
    row.forget:SetShown(not rec.current)

    local name = str(rec.name) or str(rec.key) or ""
    local cname, r, g, b = Kit:ClassText(rec.class)
    row.name:SetText(name)
    row.name:SetTextColor(r, g, b)
    row.nameHit.honorLogLines = { name }
    if cname == "" then
        row.edge:SetColorTexture(Kit.COLORS.line[1], Kit.COLORS.line[2], Kit.COLORS.line[3], 1)
    else
        row.edge:SetColorTexture(r, g, b, 1)
    end

    local who = { row.level, row.last, row.rankHead, row.badge, row.title, row.week, row.honorHead, row.honor, row.bar, row.goalHead,
        row.goalIcon, row.goalName, row.goalNote, row.goalHit, row.noGoal, row.noGoalNote, row.titleHit, row.weekHit }
    for _, m in ipairs(row.marks) do who[#who + 1] = m.icon; who[#who + 1] = m.count end

    -- a character not seen since the update: its name and one sentence
    row.stub:SetShown(rec.stub == true)
    if rec.stub then
        row.stub:SetText(L["It appears in full after it has been logged in once."])
        setShown(who, false)
        return
    end

    -- who: level and class word in its colour, and when it was played
    local level = num(rec.level)
    local word = cname ~= "" and (hexOf(r, g, b) .. cname .. "|r") or nil
    local levelText
    if level and word then levelText = string.format(L["Level %d %s"], level, word)
    elseif level then levelText = string.format(L["Level %d"], level)
    else levelText = word end
    row.level:SetShown(levelText ~= nil)
    if levelText then row.level:SetText(levelText) end
    local last = str(rec.lastText)
    row.last:SetShown(last ~= nil)
    if last then
        row.last:SetText(rec.current and last or string.format(L["Played %s"], last))
        color(row.last, "grey")
    end

    -- rank: the badge with its number, the title, the week line
    local rank = num(rec.rank)
    local title = str(rec.rankTitle)
    local weekText = str(rec.weekText)
    row.rankHead:SetShown(rank ~= nil or weekText ~= nil)
    row.badge:SetShown(rank ~= nil)
    if rank then row.badge.number:SetText(tostring(rank)) end
    row.title:SetShown(rank ~= nil and title ~= nil)
    row.titleHit:SetShown(rank ~= nil and title ~= nil)
    if title then
        row.title:SetText(title)
        row.titleHit.honorLogLines = { title }
    end
    row.week:SetShown(weekText ~= nil)
    row.weekHit:SetShown(weekText ~= nil)
    if weekText then
        row.week:SetText(weekText)
        color(row.week, TONE_COLOR[rec.weekTone] or "white")
        row.weekHit.honorLogLines = { weekText }
    end

    -- honor against the cap
    local honor, cap = num(rec.honor), num(rec.honorCap)
    row.honorHead:SetShown(honor ~= nil)
    row.honor:SetShown(honor ~= nil)
    row.bar:SetShown(honor ~= nil and cap ~= nil and cap > 0)
    if honor then
        local near = cap ~= nil and cap > 0 and honor * 10 >= cap * 9
        if cap and cap > 0 then
            row.honor:SetText(string.format(L["%s / %s"], commas(honor), commas(cap)))
            row.bar:SetValue01(honor / cap)
            if near then row.bar:SetBarColor(Kit.COLORS.orange[1], Kit.COLORS.orange[2], Kit.COLORS.orange[3])
            else row.bar:SetBarColor(1, 0.82, 0.1) end
        else
            row.honor:SetText(commas(honor))
        end
        color(row.honor, near and "orange" or "white")
    end

    -- marks, in battleground order, only the ones this character holds
    local used = 0
    local held = type(rec.marks) == "table" and rec.marks or {}
    for _, bg in ipairs(HonorLog.BG_ORDER or {}) do
        local count = num(held[bg])
        if count and count > 0 and used < #row.marks then
            used = used + 1
            local m = row.marks[used]
            m.icon:SetBattleground(bg, count, name)
            m.count:SetText(tostring(count))
            m.icon:Show()
            m.count:Show()
        end
    end
    for i = used + 1, #row.marks do
        row.marks[i].icon:Hide()
        row.marks[i].count:Hide()
    end

    -- next goal
    local item = num(rec.goalItem)
    row.goalHead:SetShown(true)
    row.noGoal:SetShown(item == nil)
    row.noGoalNote:SetShown(item == nil)
    row.goalIcon:SetShown(item ~= nil)
    row.goalHit:SetShown(item ~= nil)
    local goalName, goalNote = str(rec.goalName), str(rec.goalNote)
    row.goalName:SetShown(item ~= nil and goalName ~= nil)
    row.goalNote:SetShown(item ~= nil and goalNote ~= nil)
    if item then
        row.goalIcon:SetItem(item)
        if goalName then
            row.goalName:SetText(goalName)
            local cr, cg, cb = Kit:QualityColor(row.goalIcon.honorLogQuality)
            row.goalName:SetTextColor(cr, cg, cb)
        end
        if goalNote then
            row.goalNote:SetText(goalNote)
            color(row.goalNote, "grey")
        end
        local lines = {}
        if goalName then lines[#lines + 1] = goalName end
        if goalNote then lines[#lines + 1] = goalNote end
        row.goalHit.honorLogLines = lines
    end
end

local function updateNote(row)
    row.text:SetText(L["Other characters appear here after they have been logged in once."])
end

local function createNote(row)
    row.text = Kit:FixedText(row, "grey", LIST_W - 4)
    row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
end

--------------------------------------------------------------------------------
-- The head, the list and the foot
--------------------------------------------------------------------------------

local function countText(n) return n == 1 and L["1 character"] or string.format(L["%d characters"], n) end
local function cappedText(n)
    if n == 0 then return L["None capped this week"] end
    return n == 1 and L["1 capped this week"] or string.format(L["%d capped this week"], n)
end

-- "3 characters · 43,440 honor · 1 capped this week"
local function summaryText(rows)
    local Characters = HonorLog.Characters
    local totals = Characters and safe(Characters.GetTotals, Characters, rows)
    if type(totals) ~= "table" then return "" end
    local parts = { countText(num(totals.count) or #rows) }
    local anyHonor = false
    for _, r in ipairs(rows) do if num(r.honor) then anyHonor = true end end
    if anyHonor then parts[#parts + 1] = string.format(L["%s honor"], commas(num(totals.honor) or 0)) end
    parts[#parts + 1] = cappedText(num(totals.cappedNow) or 0)
    return table.concat(parts, " \194\183 ")
end

local function create(parent)
    local root = CreateFrame("Frame", nil, parent)
    local area = CreateFrame("Frame", nil, root)
    area:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -10)
    area:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, 10)
    area:SetSize(PANEL_W, PANEL_H)

    local ctx = { refresh = function() root:Refresh() end }
    local head = {}
    head.title = Kit:FixedText(area, "label", 130) -- the gold heading every screen opens with
    head.title:SetPoint("TOPLEFT", area, "TOPLEFT", Kit.PORTRAIT_CLEAR + 8, -4)
    head.title:SetText(L["Your characters"])
    head.summary = Kit:FixedText(area, "grey", 680)
    head.summary:SetPoint("TOPLEFT", area, "TOPLEFT", 188, -7)

    local list = {}
    list.area = Kit:ScrollArea(area)
    list.area:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -LIST_Y)
    list.area:SetSize(LIST_W, LIST_H)
    list.stack = Kit:Stack(list.area.honorLogChild, {
        card = { create = function(row) createCard(row, ctx) end, update = updateCard },
        note = { create = createNote, update = updateNote },
    })
    list.empty = Kit:FixedText(area, "grey", LIST_W)
    list.empty:SetPoint("TOPLEFT", area, "TOPLEFT", 8, -(LIST_Y + 8))
    list.empty:SetText(L["No characters saved yet."])

    local foot = Kit:FixedText(area, "grey", PANEL_W)
    foot:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -FOOT_Y)
    foot:SetText(L["Each character's line is saved when you log out of it. Nothing leaves your computer."])

    local rows = {}
    function root:Refresh()
        rows = {}
        runSteps({
            -- a fresh line for the character being played
            function()
                local Characters = HonorLog.Characters
                if Characters then Characters:Snapshot() end
            end,
            function()
                local got = HonorLog:GetCharacterRows()
                if type(got) == "table" then rows = got end
            end,
            function() head.summary:SetText(#rows > 0 and summaryText(rows) or "") end,
            function()
                local entries = {}
                for _, rec in ipairs(rows) do
                    if type(rec) == "table" and type(rec.key) == "string" then
                        entries[#entries + 1] = { kind = "card", height = CARD_STEP, rec = rec }
                    end
                end
                if #entries == 1 then entries[2] = { kind = "note", height = NOTE_H } end
                list.empty:SetShown(#entries == 0)
                list.area:honorLogSetContentHeight(list.stack:SetData(entries))
            end,
        })
    end
    root.honorLogParts = { head = head, list = list, foot = foot }
    return root
end

Window:RegisterScreen({ key = "characters", title = L["Characters"], order = 8, create = create })
