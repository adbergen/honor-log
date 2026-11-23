-- HonorLog Moments
-- Four pop-up cards that appear on the game screen at the moments that matter, in place of the plain
-- centre-screen text: a report card after each battleground, a rank-up card, an honor cap card and a weekly
-- recap when the rank week turns over. Each can be switched off in the options, none appears in the middle of a
-- fight (it waits for the end of it), and each goes away on its own (the recap stays longer: it is read, and
-- paged through).
--
-- Cards are built the first time they are shown. They stack downward from one anchor at the top centre of the
-- screen, in the order they were shown. The same kind asked for twice while one is up replaces its content.
-- Timing is C_Timer (a counter makes an old timer harmless: nothing is cancelled) and fading is an
-- AnimationGroup; nothing runs per frame. While the mouse is over a card its timer is held, and it restarts with
-- four seconds when the mouse leaves.
--
-- Every number comes from Data.lua, Model.lua and Modules/Rank.lua; this file lays them out. Each part of a card
-- guards its own reads, so one failing part leaves the rest drawn, and a card that cannot be built never raises
-- into the game.
--
-- Widths: a 12 point text is about 6.3 px a character, a 10 point text about 5.2 px, a 16 point text about 8.4
-- and a 22 point text about 12. Every text that can outgrow its box is a fixed-width one-line text (the client
-- cuts it with "...") and the cut ones carry their full text in a tooltip. A headline number is never cut.
--
-- Loaded last. HonorLog:Announce (Util.lua) is told to stay quiet when the card for its moment will show.

local _, HonorLog = ...
HonorLog = HonorLog or {}

local Util = HonorLog.Util
local num, str, call = Util.num, Util.str, Util.call
local L = HonorLog.L
local Kit = HonorLog.Kit

local Moments = {}
HonorLog.Moments = Moments

local ANCHOR_TOP = 140 -- pixels from the top of the screen to the first card
local STACK_GAP = 8
local FADE_SECONDS = 0.4
local LEAVE_SECONDS = 4 -- how long a card stays after the mouse leaves it
local DEFAULT_SECONDS = 12
local RECAP_SECONDS = 60 -- the recap is read and paged through: it stays at least this long (until closed when the time is 0)
local RECAP_LEAVE_SECONDS = 15 -- and this long after the mouse leaves it
local RECAP_LOGIN_WINDOW = 30 -- a week that ends within this many seconds of the addon loading is a login ...
local RECAP_LOGIN_DELAY = 6 -- ... and its card waits this long so the player sees it
local RECAP_LEAVE_BG_DELAY = 2 -- seconds after leaving a battleground before a held recap shows
local PAD, SECTION_GAP, TILE_GAP = 12, 6, 8
local DAY = 86400
local HONOR_FULL_PCT = 0.9 -- the bar turns orange from here
local DOT = " \194\183 "

local function settings() return HonorLog.db and HonorLog.db.settings end

-- The first result of a call, or nil when it raises. A second result is kept for the model calls that have two.
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local function commas(n) return HonorLog.Rank.FormatNumber(n) end

local function round(n) return math.floor((num(n) or 0) + 0.5) end

local function paint(fs, name)
    local c = Kit.COLORS[name] or Kit.COLORS.white
    fs:SetTextColor(c[1], c[2], c[3])
end

local function showTooltip(owner, text)
    if not text or text == "" then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
end

local function plain(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
end

local function resultOf(entry)
    return entry.result or (entry.win and "win" or "loss")
end

local function bgName(bgType)
    if not bgType then return "" end
    return str(safe(HonorLog.GetBGDisplayName, HonorLog, bgType)) or tostring(bgType)
end

--------------------------------------------------------------------------------
-- The highlight line of the report card
--------------------------------------------------------------------------------

local KILLING_BLOWS_MIN, WEEK_GAMES_MIN, STREAK_MIN = 2, 3, 3

-- The one gold line a finished game earns, the first that applies, else nil: more killing blows than any other
-- of this week's games in that battleground, when the week has at least three games there (a best of one game
-- says nothing, and a tie is not a best), or a run of three or more wins in a row (across battlegrounds).
-- `history` is the saved games newest first (the record itself may be in it); `weekStart` is a timestamp, by
-- default seven days before the record. Returns the text and its kind ("kills" or "streak").
function Moments.Highlight(record, history, weekStart)
    if type(record) ~= "table" then return nil end
    history = type(history) == "table" and history or {}
    local stamp = num(record.timestamp)
    weekStart = num(weekStart) or (stamp and stamp - 7 * DAY) or nil

    local kb, bgType = num(record.kb), record.bgType
    if kb and kb >= KILLING_BLOWS_MIN and bgType then
        local best, games = true, 1
        for _, g in ipairs(history) do
            if type(g) == "table" and g ~= record and g.bgType == bgType then
                local at, theirs = num(g.timestamp), num(g.kb)
                local inWeek = weekStart == nil or (at ~= nil and at >= weekStart)
                -- a copy of the record (the same time) is the same game, not another one
                if inWeek and not (stamp and at == stamp) then
                    games = games + 1
                    if theirs and theirs >= kb then best = false end
                end
            end
        end
        if best and games >= WEEK_GAMES_MIN then
            return string.format(L["%d killing blows, your best in %s this week."], kb, bgName(bgType)), "kills"
        end
    end

    if resultOf(record) == "win" then
        local index
        for i, g in ipairs(history) do
            if g == record then index = i break end
        end
        if not index and stamp then
            for i, g in ipairs(history) do
                if type(g) == "table" and num(g.timestamp) == stamp and g.bgType == bgType then index = i break end
            end
        end
        local count = 1
        for i = (index or 0) + 1, #history do
            local g = history[i]
            if type(g) ~= "table" or resultOf(g) ~= "win" then break end
            count = count + 1
        end
        if count >= STREAK_MIN then return string.format(L["That is %d wins in a row."], count), "streak" end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Machinery shared by the three cards
--------------------------------------------------------------------------------

local KINDS = {} -- filled below: kind -> { setting, width, title, name, build }
local states = {} -- kind -> { card, parts, sections, fills, token, fade, ... }
local order = {} -- the kinds that are up, in the order they were shown
local waiting = {} -- kinds asked for during a fight, in order, with their data in waitingData
local waitingData = {}
local watcher

Moments.states, Moments.order = states, order

local function inCombat()
    return call(InCombatLockdown) == true
end

local function seconds()
    local s = settings()
    local v = s and num(s.momentSeconds)
    if v == nil then return DEFAULT_SECONDS end
    return math.max(0, v)
end

-- How long a card of this kind stays up: momentSeconds, and for the recap at least RECAP_SECONDS. 0 = until closed.
local function lifetime(kind)
    local v = seconds()
    if v > 0 and kind == "recap" then return math.max(RECAP_SECONDS, v * 4) end
    return v
end

-- True when the card of this kind is switched on in the options.
function Moments:Shows(kind)
    local def = KINDS[kind]
    if not def then return false end
    local s = settings()
    return not (s and s[def.setting] == false)
end

local function reflow()
    local previous
    for _, kind in ipairs(order) do
        local card = states[kind].card
        card:ClearAllPoints()
        if previous then
            card:SetPoint("TOP", previous, "BOTTOM", 0, -STACK_GAP)
        else
            card:SetPoint("TOP", UIParent, "TOP", 0, -ANCHOR_TOP)
        end
        previous = card
    end
end

local function removeFromOrder(kind)
    for i, k in ipairs(order) do
        if k == kind then table.remove(order, i) break end
    end
end

-- Starts a timer for `delay` seconds; an older one (a different token) does nothing when it runs.
local function arm(state, delay)
    state.token = state.token + 1
    if not delay or delay <= 0 then return end
    local token = state.token
    C_Timer.After(delay, function()
        if state.token ~= token or not state.card:IsShown() then return end
        Moments:Fade(state.kind)
    end)
end

local function mouseOver(frame)
    local v = call(frame.IsMouseOver, frame)
    return v == true
end

local function onEnter(state)
    state.token = state.token + 1 -- holds the timer
    state.held = true
    if state.fading then
        state.fading = false
        call(state.fade.Stop, state.fade)
        state.card:SetAlpha(1)
    end
end

local function onLeave(state)
    -- moving onto a control of the card leaves the card's own frame; the mouse is still on the card
    if mouseOver(state.card) then return end
    state.held = false
    if seconds() > 0 then arm(state, state.kind == "recap" and RECAP_LEAVE_SECONDS or LEAVE_SECONDS) end
end

-- Whatever the mouse can rest on keeps the card's timer held while it is over it.
local function track(state, frame)
    frame:HookScript("OnEnter", function() onEnter(state) end)
    frame:HookScript("OnLeave", function() onLeave(state) end)
    return frame
end

-- A section is a plain frame of the card's body; the layout stacks the shown ones.
local function newSection(state, height)
    local sec = CreateFrame("Frame", nil, state.card.honorLogBody)
    sec:SetSize(state.inner, height)
    sec.honorLogHeight = height
    state.sections[#state.sections + 1] = sec
    return sec
end

local function relayout(state)
    local y = PAD
    local body = state.card.honorLogBody
    for _, sec in ipairs(state.sections) do
        if sec:IsShown() then
            sec:ClearAllPoints()
            sec:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -y)
            sec:SetSize(state.inner, sec.honorLogHeight)
            y = y + sec.honorLogHeight + SECTION_GAP
        end
    end
    state.card:SetBodyHeight(math.max(y - SECTION_GAP + PAD, 2 * PAD))
end

-- A button over a frame that shows `text` in a tooltip (the frame's own text can be cut). Its level is set
-- above the frame's, because two overlapping siblings have no promised order.
-- `frame` may be a text: a text cannot parent a frame (the client raises), so the button is then made on
-- `parent`, the frame the text sits in, and laid over the text.
local function tipOver(state, frame, parent)
    parent = parent or frame
    local b = CreateFrame("Button", nil, parent)
    b:SetAllPoints(frame)
    b:SetFrameLevel((num(parent:GetFrameLevel()) or 0) + 10)
    b:SetScript("OnEnter", function(self) showTooltip(self, self.honorLogText) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    track(state, b)
    return b
end

local function button(state, parent, text, onClick)
    local b = Kit:Button(parent, text, "small")
    b:SetSize(110, 22)
    b:SetScript("OnClick", function()
        local ok, err = pcall(onClick)
        if not ok then report(err) end
        Moments:Close(state.kind)
    end)
    track(state, b)
    return b
end

local function icon(state, parent, size)
    local ic = Kit:ItemIcon(parent, size)
    ic:SetFrameLevel((num(parent:GetFrameLevel()) or 0) + 5)
    track(state, ic)
    return ic
end

-- Runs every part's fill under pcall: a part that fails is reported and hidden, the others stay drawn.
local function runFills(state, data)
    for _, part in ipairs(state.fills) do
        local sec, fn = part[1], part[2]
        sec:Show()
        local ok, err = pcall(fn, data)
        if not ok then
            sec:Hide()
            report(err)
        end
    end
    relayout(state)
end

local function build(kind)
    local def = KINDS[kind]
    local card = Kit:Card(def.name, def.width)
    card:SetTitle(def.title)
    local state = { kind = kind, card = card, parts = {}, sections = {}, fills = {}, token = 0,
        inner = def.width - 2 - 2 * PAD }
    -- the card's own animation: alpha down over FADE_SECONDS, then it hides
    local group = card:CreateAnimationGroup()
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(0)
    alpha:SetDuration(FADE_SECONDS)
    group:SetToFinalAlpha(true)
    group:SetScript("OnFinished", function(_, requested)
        if requested then return end -- Stop() reports itself as finished
        Moments:Finish(kind)
    end)
    state.fade, state.fadeAlpha = group, alpha
    card:SetScript("OnEnter", function() onEnter(state) end)
    card:SetScript("OnLeave", function() onLeave(state) end)
    card.honorLogClose:SetScript("OnClick", function() Moments:Close(kind) end)
    track(state, card.honorLogClose)
    state.card.honorLogState = state
    def.build(state)
    return state
end

local function display(kind, data)
    local state = states[kind]
    if not state then
        state = build(kind)
        states[kind] = state
    end
    state.data = data
    state.fading, state.held = false, false
    call(state.fade.Stop, state.fade)
    state.card:SetAlpha(1)
    runFills(state, data)
    if not state.card:IsShown() then
        state.card:Show()
    end
    removeFromOrder(kind)
    order[#order + 1] = kind
    reflow()
    arm(state, lifetime(kind))
end

-- A card shown again while it is up replaces its content and keeps its place.
local function redisplay(state, data)
    state.data = data
    state.fading = false
    call(state.fade.Stop, state.fade)
    state.card:SetAlpha(1)
    runFills(state, data)
    if state.held then
        state.token = state.token + 1
    else
        arm(state, lifetime(state.kind))
    end
end

local function flush()
    local kinds, datas = waiting, waitingData
    waiting, waitingData = {}, {}
    for _, kind in ipairs(kinds) do
        local ok, err = pcall(Moments.Present, Moments, kind, datas[kind])
        if not ok then report(err) end
    end
end

local function watchCombat()
    if watcher then return end
    watcher = CreateFrame("Frame")
    -- PLAYER_REGEN_ENABLED carries no HasRestrictions flag in this build's API documentation
    if not pcall(watcher.RegisterEvent, watcher, "PLAYER_REGEN_ENABLED") then
        watcher = nil
        return
    end
    watcher:SetScript("OnEvent", function() flush() end)
end

-- Shows or refreshes a card now (no fight check). Raises on a failure; Show wraps it. A data of false stands
-- for "no data" (nil cannot sit in the waiting table).
function Moments:Present(kind, data)
    if type(data) ~= "table" then data = {} end
    local state = states[kind]
    local up = false
    for _, k in ipairs(order) do
        if k == kind then up = true end
    end
    if state and up and state.card:IsShown() then
        redisplay(state, data)
    else
        display(kind, data)
    end
end

-- Shows the card of `kind` ("report", "rankUp", "honorCap" or "recap") with its data. During a fight it waits for the end
-- of it. Returns true when shown, "waiting" when it is held back, false when it could not be made.
function Moments:Show(kind, data)
    if not KINDS[kind] then return false end
    if inCombat() then
        if waitingData[kind] == nil then waiting[#waiting + 1] = kind end
        waitingData[kind] = data == nil and false or data
        watchCombat()
        return "waiting"
    end
    local ok, err = pcall(self.Present, self, kind, data)
    if not ok then
        report(err)
        return false
    end
    return true
end

function Moments:Fade(kind)
    local state = states[kind]
    if not state or not state.card:IsShown() or state.fading then return end
    state.fading = true
    state.fade:Play()
end

-- The fade is over (or a card is closed): hide it and let the others move up.
function Moments:Finish(kind)
    local state = states[kind]
    if not state then return end
    state.token = state.token + 1
    state.fading, state.held = false, false
    state.card:Hide()
    state.card:SetAlpha(1)
    removeFromOrder(kind)
    reflow()
end

-- The close button: gone at once.
function Moments:Close(kind)
    local state = states[kind]
    if not state then return end
    call(state.fade.Stop, state.fade)
    self:Finish(kind)
end

--------------------------------------------------------------------------------
-- Report card
--------------------------------------------------------------------------------

local RESULTS = {
    win = { word = "Victory", color = "green", mark = "up" },
    loss = { word = "Defeat", color = "red", mark = "down" },
    draw = { word = "Draw", color = "grey", mark = "flat" },
    left = { word = "Left early", color = "orange", mark = "cross" },
}
local GLYPHS = { up = "^", down = "v", flat = "=", cross = "x" }
local TILE_H = 68

-- A small drawing of the result: an arrow up, an arrow down, an equals sign or a cross, in the result's colour.
-- A client without Line regions cannot draw a slanted line; a plain letter stands in then.
local function drawMark(mark, kind, color)
    local c = Kit.COLORS[color] or Kit.COLORS.white
    mark:Clear()
    local ok = true
    local function line(x1, y1, x2, y2)
        if not mark:Line(x1, y1, x2, y2, 2, c[1], c[2], c[3], 1) then ok = false end
    end
    if kind == "up" then
        line(8, 2, 8, 13) line(3, 8, 8, 13) line(13, 8, 8, 13)
    elseif kind == "down" then
        line(8, 14, 8, 3) line(3, 8, 8, 3) line(13, 8, 8, 3)
    elseif kind == "flat" then
        line(2, 6, 14, 6) line(2, 10, 14, 10)
    else
        line(3, 3, 13, 13) line(3, 13, 13, 3)
    end
    mark.honorLogKind = kind
    mark.honorLogColor = color
    mark.honorLogGlyph:SetText(GLYPHS[kind] or "")
    paint(mark.honorLogGlyph, color)
    mark.honorLogGlyph:SetShown(not ok)
end

local function factionName(id)
    id = num(id)
    if not id or not C_Reputation then return nil end
    local data = call(C_Reputation.GetFactionDataByID, id)
    return type(data) == "table" and str(data.name) or nil
end

-- The score line needs both teams' final scores; the saved record has none today (teams carry players, killing
-- blows, honorable kills and deaths), so this reads a `score` on each team and says nothing without both.
local function scoreText(record)
    local teams = record.teams
    if type(teams) ~= "table" then return nil end
    local mine = (call(UnitFactionGroup, "player") == "Alliance") and 1 or 0
    local a = type(teams[mine]) == "table" and num(teams[mine].score)
    local b = type(teams[1 - mine]) == "table" and num(teams[1 - mine].score)
    if not (a and b) then return nil end
    return string.format(L["%s to %s"], commas(a), commas(b))
end

local function makeTile(state, parent)
    local tile = Kit:NoteTile(parent)
    track(state, tile.honorLogTipButton)
    return tile
end

local function setTile(...) return Kit:SetNoteTile(...) end

local function buildReport(state)
    local p, inner = state.parts, state.inner
    local fills = state.fills

    -- head: the result, the battleground, the length and the score
    local head = newSection(state, 46)
    p.head = head
    p.mark = Kit:Chart(head)
    p.mark:SetSize(16, 16)
    p.mark:SetPoint("TOPLEFT", head, "TOPLEFT", 0, -5)
    p.mark.honorLogGlyph = Kit:Text(head, "label")
    p.mark.honorLogGlyph:SetPoint("CENTER", p.mark, "CENTER", 0, 0)
    p.mark.honorLogGlyph:Hide()
    p.word = Kit:Text(head, "big")
    p.word:SetPoint("TOPLEFT", head, "TOPLEFT", 24, 0)
    -- the word takes the width it needs (22 points, 12 px a character: "Left early" is about 120); the name gives way
    p.name = Kit:FixedText(head, "label", 232)
    p.name:SetPoint("LEFT", p.word, "RIGHT", 10, 0)
    p.sub = Kit:FixedText(head, "grey", inner)
    p.sub:SetPoint("TOPLEFT", head, "TOPLEFT", 0, -30)
    fills[#fills + 1] = { head, function(record)
        local r = RESULTS[resultOf(record)] or RESULTS.draw
        p.word:SetText(L[r.word])
        paint(p.word, r.color)
        drawMark(p.mark, r.mark, r.color)
        p.name:SetText(bgName(record.bgType))
        local bits = {}
        local duration = num(record.duration)
        if duration then bits[#bits + 1] = safe(HonorLog.FormatDuration, HonorLog, duration) end
        bits[#bits + 1] = scoreText(record)
        p.sub:SetText(table.concat(bits, DOT))
    end }

    -- tiles: Honor, Rank points, Marks and, when there is something for it, Reputation or Killing blows
    local row = newSection(state, TILE_H)
    p.row = row
    p.tiles = {}
    for i = 1, 4 do p.tiles[i] = makeTile(state, row) end
    local marksTile = p.tiles[3]
    p.markIcon = Kit:MarkIcon(marksTile, 18)
    p.markIcon:SetPoint("TOPLEFT", marksTile, "TOPLEFT", 12, -23)
    p.markIcon:SetFrameLevel((num(marksTile:GetFrameLevel()) or 0) + 10)
    track(state, p.markIcon)
    marksTile.value:ClearAllPoints()
    marksTile.value:SetPoint("LEFT", p.markIcon, "RIGHT", 6, 0)
    fills[#fills + 1] = { row, function(record)
        local bgType = record.bgType
        local honorTile, rankTile, extraTile = p.tiles[1], p.tiles[2], p.tiles[4]

        local honor = num(record.honor)
        local note
        if record.honorCapped then
            note = L["At the honor cap"]
        else
            local model = safe(HonorLog.GetBattlegroundModel, HonorLog, bgType)
            local average = type(model) == "table" and num(model.honorPerGame)
            note = average and string.format(L["Average %s"], commas(round(average))) or ""
        end
        setTile(honorTile, L["Honor"], honor and ("+" .. commas(honor)) or "-", note, nil, "gold")

        local points = num(record.rankPoints)
        local text, tone = safe(HonorLog.DescribeRankPoints, HonorLog, record)
        text = str(text) or ""
        -- a plain "+108" under the same "+108" says nothing: the note is for the cases that need words
        local rankNote = (tone == "earned" and not record.rankCappedDuring) and "" or text
        setTile(rankTile, L["Rank points"], (points and points > 0) and ("+" .. commas(points)) or (points == 0 and "0" or "-"),
            rankNote, text, "white", tone == "blocked" and "orange" or "grey")

        local marks = num(record.marks)
        local held = num(safe(HonorLog.GetCurrentMarks, HonorLog, bgType))
        p.markIcon:SetBattleground(bgType)
        setTile(marksTile, L["Marks"], "+" .. (marks or 0), held and string.format(L["%d in your bags"], held) or "")

        local rep = type(record.rep) == "table" and record.rep or nil
        local gained = rep and num(rep.gained)
        local kb = num(record.kb)
        local count = 3
        if gained and gained > 0 then
            local name = factionName(rep.faction) or bgName(bgType)
            setTile(extraTile, L["Reputation"], "+" .. commas(gained), name, name)
            count = 4
        elseif kb and kb > 0 then
            local hk = num(record.hk)
            setTile(extraTile, L["Killing blows"], tostring(kb), hk and string.format(L["%d honorable kills"], hk) or "")
            count = 4
        end
        local width = math.floor((inner - (count - 1) * TILE_GAP) / count)
        for i, tile in ipairs(p.tiles) do
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * (width + TILE_GAP), 0)
            tile:SetSize(width, TILE_H)
            tile:SetShown(i <= count)
        end
        p.tileCount = count
        -- the note's tooltip over the marks tile does not reach the icon (it sits higher up)
        p.markIcon:SetShown(true)
    end }

    -- highlight: one gold line, or none
    local light = newSection(state, 16)
    p.light = light
    p.lightDot = light:CreateTexture(nil, "ARTWORK")
    p.lightDot:SetSize(6, 6)
    p.lightDot:SetPoint("LEFT", light, "LEFT", 2, 0)
    p.lightDot:SetColorTexture(Kit.COLORS.gold[1], Kit.COLORS.gold[2], Kit.COLORS.gold[3], 1)
    p.lightText = Kit:FixedText(light, "value", inner - 16)
    p.lightText:SetPoint("LEFT", light, "LEFT", 14, 0)
    paint(p.lightText, "gold")
    p.lightTip = tipOver(state, light)
    fills[#fills + 1] = { light, function(record)
        local history = safe(HonorLog.GetHistory, HonorLog, "character", 200)
        local weekStart
        local info = HonorLog.Rank and safe(HonorLog.Rank.GetInfo, HonorLog.Rank)
        local reset = type(info) == "table" and num(info.secondsToWeeklyReset)
        if reset and reset > 0 then weekStart = time() + reset - 7 * DAY end
        local text = Moments.Highlight(record, history, weekStart)
        if not text then light:Hide() return end
        p.lightText:SetText(text)
        p.lightTip.honorLogText = text
    end }

    -- next goal
    local goal = newSection(state, 38)
    p.goal = goal
    p.goalLabel = Kit:FixedText(goal, "labelSmall", inner)
    p.goalLabel:SetPoint("TOPLEFT", goal, "TOPLEFT", 0, 0)
    p.goalLabel:SetText(L["Next goal"])
    p.goalIcon = icon(state, goal, 24)
    p.goalIcon:SetPoint("TOPLEFT", goal, "TOPLEFT", 0, -14)
    p.goalBox = CreateFrame("Frame", nil, goal)
    p.goalBox:SetPoint("TOPLEFT", goal, "TOPLEFT", 32, -14)
    p.goalBox:SetSize(inner - 32, 24)
    p.goalName = Kit:FixedText(p.goalBox, "value", inner - 32)
    p.goalName:SetPoint("TOPLEFT", p.goalBox, "TOPLEFT", 0, 0)
    p.goalText = Kit:FixedText(p.goalBox, "grey", inner - 32)
    p.goalText:SetPoint("TOPLEFT", p.goalBox, "TOPLEFT", 0, -15)
    p.goalTip = tipOver(state, p.goalBox)
    fills[#fills + 1] = { goal, function()
        local goals = safe(HonorLog.GetAllGoalsProgress, HonorLog)
        local gp = type(goals) == "table" and goals[1] or nil
        local itemID = type(gp) == "table" and num(gp.itemID)
        if not itemID then goal:Hide() return end
        local name = str(gp.name) or ""
        local ready = str(safe(HonorLog.GoalReadyText, HonorLog, gp)) or ""
        p.goalIcon:SetItem(itemID)
        p.goalName:SetText(name)
        p.goalText:SetText(ready)
        p.goalTip.honorLogText = name .. "\n" .. plain(ready)
    end }

    -- honor held over the honor cap
    local honor = newSection(state, 32)
    p.honor = honor
    p.honorLabel = Kit:Text(honor, "labelSmall")
    p.honorLabel:SetPoint("TOPLEFT", honor, "TOPLEFT", 0, 0)
    p.honorLabel:SetText(L["Honor"])
    p.honorValue = Kit:FixedText(honor, "value", 200)
    p.honorValue:SetJustifyH("RIGHT")
    p.honorValue:SetPoint("TOPRIGHT", honor, "TOPRIGHT", 0, 0)
    p.honorBar = Kit:Bar(honor)
    p.honorBar:SetPoint("TOPLEFT", honor, "TOPLEFT", 0, -18)
    p.honorBar:SetSize(inner, 14)
    fills[#fills + 1] = { honor, function()
        local held, cap = num(safe(HonorLog.GetCurrentHonor, HonorLog)), num(safe(HonorLog.GetHonorCap, HonorLog))
        if not held or not cap or cap <= 0 then honor:Hide() return end
        p.honorValue:SetText(commas(held) .. " / " .. commas(cap))
        p.honorBar:SetValue01(held / cap)
        local c = Kit.COLORS[held / cap >= HONOR_FULL_PCT and "orange" or "gold"]
        p.honorBar:SetBarColor(c[1], c[2], c[3])
    end }

    -- foot
    local foot = newSection(state, 24)
    p.foot = foot
    p.button = button(state, foot, L["All games"], function()
        if HonorLog.Window then HonorLog.Window:Show("battlegrounds") end
    end)
    p.button:SetPoint("RIGHT", foot, "RIGHT", 0, 0)
end

--------------------------------------------------------------------------------
-- Rank-up card
--------------------------------------------------------------------------------

local MAX_RANK_FALLBACK = 14

local function itemName(itemID)
    local name = str(safe(HonorLog.GetGearName, HonorLog, itemID))
    if name then return name end
    local base = HonorLog.GearDB and HonorLog.GearDB[itemID]
    return type(base) == "table" and str(base.name) or ""
end

local function buildRankUp(state)
    local p, inner = state.parts, state.inner
    local fills = state.fills

    -- head: "Rank" over the number, the title beside it
    local head = newSection(state, 44)
    p.head = head
    p.rankLabel = Kit:Text(head, "labelSmall")
    p.rankLabel:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
    p.rankLabel:SetText(L["Rank"])
    -- the number is never cut: it takes the width it needs and the title gives way
    p.rankNumber = Kit:Text(head, "big")
    p.rankNumber:SetPoint("TOPLEFT", head, "TOPLEFT", 0, -14)
    p.rankTitle = Kit:FixedText(head, "title", inner - 70)
    p.rankTitle:SetPoint("LEFT", p.rankNumber, "RIGHT", 12, 0)
    fills[#fills + 1] = { head, function(data)
        local rank = num(data.rank)
        p.rankNumber:SetText(rank and tostring(rank) or "-")
        local title = rank and str(safe(HonorLog.Rank.TitleForRank, HonorLog.Rank, rank)) or ""
        p.rankTitle:SetText(title)
    end }

    -- unlocked: up to five icons at 32
    local unlocked = newSection(state, 52)
    p.unlocked = unlocked
    p.unlockedLabel = Kit:Text(unlocked, "labelSmall")
    p.unlockedLabel:SetPoint("TOPLEFT", unlocked, "TOPLEFT", 0, 0)
    p.unlockedLabel:SetText(L["Unlocked"])
    p.unlockIcons = {}
    for i = 1, 5 do
        local ic = icon(state, unlocked, 32)
        ic:SetPoint("TOPLEFT", unlocked, "TOPLEFT", (i - 1) * 36, -18)
        ic:Hide()
        p.unlockIcons[i] = ic
    end
    p.unlockName = Kit:FixedText(unlocked, "value", inner - 40)
    p.unlockName:SetPoint("TOPLEFT", unlocked, "TOPLEFT", 40, -26)
    p.unlockMore = Kit:Text(unlocked, "value")
    p.unlockMore:SetPoint("TOPLEFT", unlocked, "TOPLEFT", 5 * 36 + 2, -26)
    p.unlockNone = Kit:FixedText(unlocked, "grey", inner)
    p.unlockNone:SetPoint("TOPLEFT", unlocked, "TOPLEFT", 0, -22)
    p.unlockNone:SetText(L["Nothing new at this rank."])
    fills[#fills + 1] = { unlocked, function(data)
        local ids = num(data.rank) and safe(HonorLog.GetRankUnlocks, HonorLog, data.rank)
        ids = type(ids) == "table" and ids or {}
        for i, ic in ipairs(p.unlockIcons) do
            if ids[i] then ic:SetItem(ids[i]) ic:Show() else ic:Hide() end
        end
        p.unlockCount = #ids
        p.unlockName:SetText("")
        p.unlockMore:SetText("")
        if #ids == 1 then
            p.unlockName:SetText(itemName(ids[1]))
        elseif #ids > 5 then
            p.unlockMore:SetText(string.format(L["+%d"], #ids - 5))
        end
        p.unlockNone:SetShown(#ids == 0)
    end }

    -- next: the next rank that unlocks something
    local nextSec = newSection(state, 60)
    p.next = nextSec
    p.nextLabel = Kit:FixedText(nextSec, "labelSmall", inner)
    p.nextLabel:SetPoint("TOPLEFT", nextSec, "TOPLEFT", 0, 0)
    p.nextIcons = {}
    for i = 1, 5 do
        local ic = icon(state, nextSec, 24)
        ic:SetPoint("TOPLEFT", nextSec, "TOPLEFT", (i - 1) * 28, -18)
        ic:Hide()
        p.nextIcons[i] = ic
    end
    p.nextLine = Kit:FixedText(nextSec, "grey", inner)
    p.nextLine:SetPoint("TOPLEFT", nextSec, "TOPLEFT", 0, -48)
    fills[#fills + 1] = { nextSec, function(data)
        local rank = num(data.rank)
        if not rank then nextSec:Hide() return end
        local info = type(data.info) == "table" and data.info or safe(HonorLog.Rank.GetInfo, HonorLog.Rank)
        local top = type(info) == "table" and num(info.seasonMaxRank) or MAX_RANK_FALLBACK
        local target, ids
        for n = rank + 1, top do
            local list = safe(HonorLog.GetRankUnlocks, HonorLog, n)
            if type(list) == "table" and #list > 0 then target, ids = n, list break end
        end
        if not target then nextSec:Hide() return end
        p.nextLabel:SetText(string.format(L["Next: Rank %d"], target))
        for i, ic in ipairs(p.nextIcons) do
            if ids[i] then ic:SetItem(ids[i]) ic:Show() else ic:Hide() end
        end
        local points = commas(num(safe(HonorLog.Rank.TotalForRank, HonorLog.Rank, target)) or 0)
        local pace = safe(HonorLog.Rank.GetPace, HonorLog.Rank)
        local games
        if type(pace) == "table" and not pace.estimated then
            local plan = safe(HonorLog.Rank.PlanToRank, HonorLog.Rank, target, type(info) == "table" and info or nil, pace)
            games = type(plan) == "table" and str(HonorLog.Rank.PlanGames(plan)) or nil
        end
        p.nextLine:SetText(games and string.format(L["at %s points, %s"], points, games) or string.format(L["at %s points"], points))
        p.nextTarget = target
    end }

    local foot = newSection(state, 24)
    p.foot = foot
    p.button = button(state, foot, L["Rank plan"], function()
        if HonorLog.Window then HonorLog.Window:Show("rank") end
    end)
    p.button:SetPoint("RIGHT", foot, "RIGHT", 0, 0)
end

--------------------------------------------------------------------------------
-- Honor cap card
--------------------------------------------------------------------------------

-- Honor a game gives on average, or nil when no game has been measured (GetAverageHonorPerGame answers a
-- guess of 250 then, which would read as a fact here).
local function measuredAverage()
    local db = HonorLog.db
    local stats = db and db.char and db.char.battlegrounds
    if type(stats) ~= "table" then return nil end
    local honor, games = 0, 0
    for _, s in pairs(stats) do
        local h, g = safe(HonorLog.UncappedHonor, HonorLog, s)
        h, g = num(h), num(g)
        if h and g then honor, games = honor + h, games + g end
    end
    if games > 0 and honor > 0 then return honor / games end
    return nil
end

local function costText(item)
    local bits = {}
    if (num(item.honor) or 0) > 0 then bits[#bits + 1] = string.format(L["%s honor"], commas(item.honor)) end
    for _, bgType in ipairs(HonorLog.BG_ORDER or {}) do
        local count = type(item.marks) == "table" and num(item.marks[bgType])
        if count and count > 0 then bits[#bits + 1] = string.format(L["%d %s marks"], count, bgName(bgType)) end
    end
    if (num(item.gold) or 0) > 0 then bits[#bits + 1] = str(safe(HonorLog.GoldShort, HonorLog, item.gold)) end
    return table.concat(bits, ", ")
end

local function buildHonorCap(state)
    local p, inner = state.parts, state.inner
    local fills = state.fills

    -- head: the numbers and the bar
    local head = newSection(state, 36)
    p.head = head
    p.headText = Kit:FixedText(head, "value", inner)
    p.headText:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
    p.bar = Kit:Bar(head)
    p.bar:SetPoint("TOPLEFT", head, "TOPLEFT", 0, -20)
    p.bar:SetSize(inner, 14)
    fills[#fills + 1] = { head, function(data)
        local held = num(data.current) or num(safe(HonorLog.GetCurrentHonor, HonorLog))
        local cap = num(data.cap) or num(safe(HonorLog.GetHonorCap, HonorLog))
        p.held, p.cap = held, cap
        if not held or not cap or cap <= 0 then head:Hide() return end
        p.headText:SetText(string.format(L["Honor is at %s / %s"], commas(held), commas(cap)))
        p.bar:SetValue01(held / cap)
        local c = Kit.COLORS[held / cap >= HONOR_FULL_PCT and "orange" or "gold"]
        p.bar:SetBarColor(c[1], c[2], c[3])
    end }

    -- the sentence from the pace
    local pace = newSection(state, 14)
    p.pace = pace
    p.paceText = Kit:FixedText(pace, "value", inner)
    p.paceText:SetPoint("TOPLEFT", pace, "TOPLEFT", 0, 0)
    fills[#fills + 1] = { pace, function(data)
        local held = num(data.current) or num(safe(HonorLog.GetCurrentHonor, HonorLog))
        local cap = num(data.cap) or num(safe(HonorLog.GetHonorCap, HonorLog))
        if not held or not cap or cap <= 0 then pace:Hide() return end
        if held >= cap then
            p.paceText:SetText(L["At the cap: more honor is wasted."])
            return
        end
        local average = measuredAverage()
        if not average then pace:Hide() return end
        local games = math.max(1, math.ceil((cap - held) / average))
        p.paceText:SetText(games == 1 and L["About 1 game until it stops counting."]
            or string.format(L["About %d games until it stops counting."], games))
    end }

    -- what can be bought now
    local buy = newSection(state, 76)
    p.buy = buy
    p.buyLabel = Kit:Text(buy, "labelSmall")
    p.buyLabel:SetPoint("TOPLEFT", buy, "TOPLEFT", 0, 0)
    p.buyLabel:SetText(L["You can buy now"])
    p.buyIcons = {}
    for i = 1, 3 do
        local ic = icon(state, buy, 28)
        ic:SetPoint("TOPLEFT", buy, "TOPLEFT", (i - 1) * 32, -16)
        ic:Hide()
        p.buyIcons[i] = ic
    end
    -- three icons take 92 px; the name and the cost sit right of them in what is left
    local textW = inner - 100
    p.buyBox = CreateFrame("Frame", nil, buy)
    p.buyBox:SetPoint("TOPLEFT", buy, "TOPLEFT", 100, -16)
    p.buyBox:SetSize(textW, 28)
    p.buyName = Kit:FixedText(p.buyBox, "value", textW)
    p.buyName:SetPoint("TOPLEFT", p.buyBox, "TOPLEFT", 0, 0)
    p.buyCost = Kit:FixedText(p.buyBox, "grey", textW)
    p.buyCost:SetPoint("TOPLEFT", p.buyBox, "TOPLEFT", 0, -15)
    p.buyTip = tipOver(state, p.buyBox)
    p.buyMap = Kit:Button(buy, L["Show on map"], "small")
    p.buyMap:SetSize(110, 22)
    p.buyMap:SetPoint("TOPLEFT", buy, "TOPLEFT", 0, -50)
    track(state, p.buyMap)
    -- nothing buyable: the advice, or a grey line
    p.buyNone = Kit:Text(buy, "grey")
    p.buyNone:SetPoint("TOPLEFT", buy, "TOPLEFT", 0, -18)
    p.buyNone:SetWidth(inner)
    p.buyNone:SetWordWrap(true)
    p.buyNone:SetMaxLines(3)
    p.buyNoneTip = CreateFrame("Button", nil, buy)
    p.buyNoneTip:SetPoint("TOPLEFT", buy, "TOPLEFT", 0, -18)
    p.buyNoneTip:SetSize(inner, 38)
    p.buyNoneTip:SetFrameLevel((num(buy:GetFrameLevel()) or 0) + 10)
    p.buyNoneTip:SetScript("OnEnter", function(self) showTooltip(self, self.honorLogText) end)
    p.buyNoneTip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    track(state, p.buyNoneTip)
    fills[#fills + 1] = { buy, function()
        local list = safe(HonorLog.GetBuyableNow, HonorLog, 3)
        list = type(list) == "table" and list or {}
        local first = list[1]
        local firstID = type(first) == "table" and num(first.itemID) or nil
        for i, ic in ipairs(p.buyIcons) do
            local entry = list[i]
            local id = type(entry) == "table" and num(entry.itemID) or nil
            if id then ic:SetItem(id) ic:Show() else ic:Hide() end
        end
        p.buyFirst = firstID
        -- "You can buy now" heads the list only when there is one; the sentence alone needs less room
        p.buyLabel:SetShown(firstID ~= nil)
        p.buyNone:ClearAllPoints()
        p.buyNone:SetPoint("TOPLEFT", buy, "TOPLEFT", 0, firstID and -18 or 0)
        p.buyNoneTip:ClearAllPoints()
        p.buyNoneTip:SetPoint("TOPLEFT", buy, "TOPLEFT", 0, firstID and -18 or 0)
        buy.honorLogHeight = firstID and 76 or 44
        p.buyBox:SetShown(firstID ~= nil)
        p.buyMap:SetShown(firstID ~= nil)
        p.buyNone:SetShown(firstID == nil)
        p.buyNoneTip:SetShown(firstID == nil)
        if firstID then
            local name = str(first.name) or itemName(firstID)
            local cost = costText(first)
            p.buyName:SetText(name)
            p.buyCost:SetText(cost)
            p.buyTip.honorLogText = name .. (cost ~= "" and ("\n" .. cost) or "")
            p.buyMap:SetScript("OnClick", function()
                local ok, err = pcall(HonorLog.ShowVendorForItem, HonorLog, firstID)
                if not ok then report(err) end
            end)
            return
        end
        local advice = safe(HonorLog.GetHonorCapAdvice, HonorLog)
        local text = type(advice) == "table" and str(advice.text) or nil
        if text and text ~= "" then
            text = text:sub(1, 1):upper() .. text:sub(2)
            p.buyNone:SetText(text)
            paint(p.buyNone, "white")
            p.buyNoneTip.honorLogText = text
        else
            p.buyNone:SetText(L["Nothing on your list can be bought yet."])
            paint(p.buyNone, "grey")
            p.buyNoneTip.honorLogText = nil
        end
    end }

    local foot = newSection(state, 24)
    p.foot = foot
    p.button = button(state, foot, L["Gear goals"], function()
        if HonorLog.GearScreen then HonorLog.GearScreen:Open("goals") end
    end)
    p.button:SetPoint("RIGHT", foot, "RIGHT", 0, 0)
end

--------------------------------------------------------------------------------
-- Weekly recap card
--------------------------------------------------------------------------------

-- Which week the card shows: 0 is this week, 1 the last closed week, and so on (Weeks:GetRecap's n).
local function pageOf(data)
    local n = type(data) == "table" and num(data.n) or nil
    if not n or n < 0 then return 0 end
    return math.floor(n)
end

-- Reading a week can turn the week over and fire HonorLog_WeekEnded while the card is being filled; the
-- listener ignores the event for as long as a read is going on (the card being filled is shown anyway).
local reading = 0

-- A table the record holds, or nil (a secret value, which cannot be indexed, is not one).
local function tbl(v)
    if type(v) == "table" and not Util.isSecret(v) then return v end
    return nil
end

local function readRecap(n)
    local Weeks = HonorLog.Weeks
    if not (Weeks and Weeks.GetRecap) then return nil end
    reading = reading + 1
    local ok, recap = pcall(Weeks.GetRecap, Weeks, n)
    reading = reading - 1
    if not ok then
        report(recap)
        return nil
    end
    return tbl(recap)
end

local function fontObject(style)
    for _, name in ipairs(Kit.FONTS[style] or {}) do
        if _G[name] ~= nil then return _G[name] end
    end
end

-- A headline number is never cut: it is set at the big size and, when it does not fit `width`, at the title
-- size. The colour is set again afterwards because a new font object brings its own.
local function fitValue(fs, width, color)
    local big, small = fontObject("big"), fontObject("title")
    if big then fs:SetFontObject(big) end
    if small and (num(fs:GetStringWidth()) or 0) > width then fs:SetFontObject(small) end
    paint(fs, color or "white")
end

local LINE_H = 18
local CHART_W, CHART_H, CHART_BASE = 180, 80, 14
local LINES_X = CHART_W + 16 -- the label column of the lines starts here, 60 wide, then the 194 wide value
local LABEL_W = 60
local VALUE_W = 194
local MARK_SLOTS, UNLOCK_SLOTS = 5, 3
local ICON_W = 20

local function buildRecap(state)
    local p, inner = state.parts, state.inner
    local fills = state.fills

    -- head: "Week 3" (never cut), the dates and the name
    local head = newSection(state, 40)
    p.head = head
    p.week = Kit:Text(head, "title")
    p.week:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
    paint(p.week, "gold")
    p.state = Kit:FixedText(head, "grey", 200)
    p.state:SetJustifyH("RIGHT")
    p.state:SetPoint("TOPRIGHT", head, "TOPRIGHT", 0, -3)
    p.sub = Kit:FixedText(head, "grey", inner)
    p.sub:SetPoint("TOPLEFT", head, "TOPLEFT", 0, -24)
    p.subTip = tipOver(state, p.sub, head)
    fills[#fills + 1] = { head, function(data)
        local n = pageOf(data)
        p.n, p.recap = n, nil
        p.recap = readRecap(n)
        local week = p.recap and tbl(p.recap.week)
        if not week then
            p.week:SetText(L["No week to show"])
            paint(p.week, "white")
            p.sub:SetText("")
            p.state:SetText("")
            p.subTip.honorLogText = nil
            return
        end
        local number, start, finish = num(week.number), num(week.start), num(week.finish)
        if number then
            p.week:SetText(string.format(L["Week %d"], number))
        else
            p.week:SetText(string.format(L["Week of %s"], start and HonorLog.Rank.FormatDate(start) or "-"))
        end
        paint(p.week, "gold")
        p.state:SetText(n == 0 and L["This week so far"] or "")
        local dates
        if start and finish then
            local last = math.max(start, finish - DAY) -- the finish is the reset: the last day is the one before
            dates = string.format(week.estimated and L["About %s to %s"] or L["%s to %s"],
                HonorLog.Rank.FormatDate(start), HonorLog.Rank.FormatDate(last))
        end
        local bits = { dates }
        bits[#bits + 1] = str(Util.unitName("player"))
        local text = table.concat(bits, DOT)
        p.sub:SetText(text)
        p.subTip.honorLogText = text
    end }

    -- tiles: games, honor, rank points, marks
    local row = newSection(state, TILE_H)
    p.row = row
    p.tiles = {}
    local count = 4
    local width = math.floor((inner - (count - 1) * TILE_GAP) / count)
    for i = 1, count do
        local tile = makeTile(state, row)
        tile:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * (width + TILE_GAP), 0)
        tile:SetSize(width, TILE_H)
        p.tiles[i] = tile
    end
    p.tileWidth = width
    local valueRoom = width - 12 - 8
    fills[#fills + 1] = { row, function()
        local recap = p.recap
        local week = recap and tbl(recap.week)
        if not week then row:Hide() return end
        local t = p.tiles

        -- games, as wins and losses; draws and games left early are in the tooltip
        local wins, losses, played = num(recap.wins) or 0, num(recap.losses) or 0, num(recap.played) or 0
        local playedText = string.format(L["%d played"], played)
        local extra = {}
        local draws, left = num(recap.draws) or 0, num(recap.left) or 0
        if draws > 0 then extra[#extra + 1] = draws == 1 and L["1 draw"] or string.format(L["%d draws"], draws) end
        if left > 0 then extra[#extra + 1] = string.format(L["%d left"], left) end
        setTile(t[1], L["Games"], string.format("%d - %d", wins, losses), playedText,
            #extra > 0 and (playedText .. "\n" .. table.concat(extra, ", ")) or playedText, "white")
        fitValue(t[1].value, valueRoom, "white")

        -- honor: the whole week's, or for a week rebuilt from saved games only what the games gave
        local honor = num(recap.honor)
        local rebuilt = honor == nil
        if rebuilt then honor = num(week.bgHonor) end
        local perGame = num(recap.honorPerGame)
        local perText = (perGame and perGame > 0) and string.format(L["%s a game"], commas(round(perGame))) or ""
        local honorTip = perText
        if rebuilt then
            honorTip = (perText ~= "" and (perText .. "\n") or "") .. L["Honor from battlegrounds only: this week was rebuilt from saved games."]
        end
        setTile(t[2], L["Honor"], honor and (honor > 0 and ("+" .. commas(honor)) or "0") or "-", perText, honorTip, "gold")
        fitValue(t[2].value, valueRoom, "gold")

        -- rank points, and the reason when the week gave none
        local gained = num(recap.rankGained)
        local reason = safe(HonorLog.GetWeekRankReason, HonorLog, week)
        local value, note, noteColor = "-", L["not measured"], "grey"
        if gained and gained > 0 then
            value, note = "+" .. commas(gained), ""
        elseif gained or reason then
            value, note = "0", ""
            if reason == "gate" then
                local gate = HonorLog.Rank and HonorLog.Rank.LEVEL_GATES and HonorLog.Rank.LEVEL_GATES[1]
                note = gate and string.format(L["Needs level %d"], gate.level) or L["Level too low"]
                noteColor = "orange"
            elseif reason == "cap" then
                note, noteColor = L["Weekly cap reached"], "orange"
            end
        end
        setTile(t[3], L["Rank points"], value, note, note, "white", noteColor)
        fitValue(t[3].value, valueRoom, "white")

        -- marks, with the battleground in the note when there is one
        local total = num(recap.marksTotal) or 0
        local bgs = {}
        for bg in pairs(tbl(recap.marks) or {}) do bgs[#bgs + 1] = bg end
        local marksNote = ""
        if #bgs == 1 then
            marksNote = bgName(bgs[1])
        elseif #bgs > 1 then
            marksNote = string.format(L["%d battlegrounds"], #bgs)
        end
        setTile(t[4], L["Marks"], "+" .. commas(total), marksNote, marksNote, "white")
        fitValue(t[4].value, valueRoom, "white")
    end }

    -- under the tiles: honor by day, and short lines beside it
    local under = newSection(state, 84)
    p.under = under
    p.chart = Kit:Chart(under)
    p.chart:SetSize(CHART_W, CHART_H)
    p.chart:SetPoint("TOPLEFT", under, "TOPLEFT", 0, -2)
    p.chartTip = tipOver(state, p.chart)
    p.lines = {}
    for i = 1, 4 do
        local line = CreateFrame("Frame", nil, under)
        line:SetSize(LABEL_W + 4 + VALUE_W, LINE_H)
        line.honorLogLabel = Kit:FixedText(line, "labelSmall", LABEL_W)
        line.honorLogLabel:SetPoint("LEFT", line, "LEFT", 0, 0)
        line.honorLogValue = Kit:FixedText(line, "value", VALUE_W)
        line.honorLogValue:SetPoint("LEFT", line, "LEFT", LABEL_W + 4, 0)
        p.lines[i] = line
    end
    local best, marks, world, cap = p.lines[1], p.lines[2], p.lines[3], p.lines[4]
    p.best, p.marksLine, p.world, p.cap = best, marks, world, cap
    best.honorLogLabel:SetText(L["Best game"])
    marks.honorLogLabel:SetText(L["Marks"])
    world.honorLogLabel:SetText(L["World PvP"])
    p.bestBox = CreateFrame("Frame", nil, best)
    p.bestBox:SetSize(VALUE_W, LINE_H)
    p.bestBox:SetPoint("LEFT", best, "LEFT", LABEL_W + 4, 0)
    p.bestTip = tipOver(state, p.bestBox)
    marks.honorLogValue:Hide()
    p.markIcons, p.markCounts = {}, {}
    for i = 1, MARK_SLOTS do
        local ic = Kit:MarkIcon(marks, 16)
        ic:SetFrameLevel((num(marks:GetFrameLevel()) or 0) + 5)
        ic:Hide()
        track(state, ic)
        p.markIcons[i] = ic
        local fs = Kit:Text(marks, "value")
        fs:Hide()
        p.markCounts[i] = fs
    end
    p.unlockIcons = {}
    for i = 1, UNLOCK_SLOTS do
        local ic = icon(state, cap, 18)
        ic:Hide()
        p.unlockIcons[i] = ic
    end
    fills[#fills + 1] = { under, function(data)
        local recap = p.recap
        local week = recap and tbl(recap.week)
        if not week then under:Hide() return end
        local shown = 0

        -- honor by day: bars and a weekday under each; the values are in the tooltip
        local days = safe(HonorLog.GetHonorDaysBetween, HonorLog, week.start, week.finish)
        local chartOn = type(days) == "table" and #days > 0
        p.chart:Clear()
        p.chart:SetShown(chartOn)
        p.chartTip:SetShown(chartOn)
        p.chartTip.honorLogText = nil
        if chartOn then
            local slot = math.floor(CHART_W / #days)
            local barW = math.max(4, slot - 6)
            local top = 0
            for _, d in ipairs(days) do top = math.max(top, num(d.honor) or 0) end
            local gold = Kit.COLORS.gold
            p.chart:Rect(0, CHART_BASE, CHART_W, 1, 0.43, 0.42, 0.38, 1)
            local tip = { L["Honor by day"] }
            for i, d in ipairs(days) do
                local honor = num(d.honor) or 0
                local x = (i - 1) * slot + math.floor((slot - barW) / 2)
                if honor > 0 and top > 0 then
                    local h = math.max(2, math.floor(honor / top * (CHART_H - CHART_BASE - 4)))
                    p.chart:Rect(x, CHART_BASE + 1, barW, h, gold[1], gold[2], gold[3], 1)
                end
                p.chart:Label(x + barW / 2, 6, str(d.label) or "", "grey")
                tip[#tip + 1] = (str(d.label) or "") .. "  " .. commas(honor)
            end
            p.chartTip.honorLogText = table.concat(tip, "\n")
        end

        -- the lines, stacked from the top: those with nothing to say are left out
        local visible = {}

        local bestRec = tbl(recap.best)
        local bestHonor = bestRec and num(bestRec.honor)
        if bestRec and bestRec.bgType and bestHonor then
            local text = string.format(L["%s, %s honor"], bgName(bestRec.bgType), commas(bestHonor))
            best.honorLogValue:SetText(text)
            p.bestTip.honorLogText = text
            visible[#visible + 1] = best
        end

        local list = {}
        for bg, count in pairs(tbl(recap.marks) or {}) do
            if num(count) and count > 0 then list[#list + 1] = { bg = bg, count = count } end
        end
        table.sort(list, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return tostring(a.bg) < tostring(b.bg)
        end)
        for i = 1, MARK_SLOTS do p.markIcons[i]:Hide() p.markCounts[i]:Hide() end
        if #list > 0 then
            local x = LABEL_W + 4
            for i = 1, math.min(#list, MARK_SLOTS) do
                local ic, fs = p.markIcons[i], p.markCounts[i]
                ic:SetBattleground(list[i].bg)
                ic:ClearAllPoints()
                ic:SetPoint("LEFT", marks, "LEFT", x, 0)
                ic:Show()
                fs:SetText(commas(list[i].count))
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", marks, "LEFT", x + 20, 0)
                fs:Show()
                x = x + 20 + (num(fs:GetStringWidth()) or 24) + 10
            end
            visible[#visible + 1] = marks
        end

        local kills, deaths = num(recap.kills), num(recap.deaths)
        if (kills and kills > 0) or (deaths and deaths > 0) then
            world.honorLogValue:SetText(string.format(L["Kills %d, deaths %d"], kills or 0, deaths or 0))
            visible[#visible + 1] = world
        end

        -- what the week's higher cap opens: for the week that has just ended, this week's cap; for this week,
        -- next week's; an older week says nothing
        local nextCap = tbl(recap.nextCap)
        local capRank = nextCap and num(nextCap.rank)
        for i = 1, UNLOCK_SLOTS do p.unlockIcons[i]:Hide() end
        if capRank and (p.n == 0 or p.n == 1) then
            cap.honorLogLabel:SetText(p.n == 0 and L["Next week"] or L["This week"])
            cap.honorLogValue:SetText(string.format(p.n == 0 and L["the cap rises to Rank %d"] or L["the cap is Rank %d"], capRank))
            local used = num(cap.honorLogValue:GetStringWidth()) or 120
            local room = math.floor((VALUE_W - used - 8) / ICON_W)
            local ids = tbl(nextCap.unlocks) or {}
            for i = 1, math.min(#ids, UNLOCK_SLOTS, math.max(room, 0)) do
                local ic = p.unlockIcons[i]
                ic:SetItem(ids[i])
                ic:ClearAllPoints()
                ic:SetPoint("LEFT", cap, "LEFT", LABEL_W + 4 + used + 8 + (i - 1) * ICON_W, 0)
                ic:Show()
            end
            visible[#visible + 1] = cap
        end

        for _, line in ipairs(p.lines) do line:Hide() end
        local x = chartOn and LINES_X or 0
        for i, line in ipairs(visible) do
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", under, "TOPLEFT", x, -((i - 1) * LINE_H) - 4)
            line:Show()
            shown = shown + 1
        end
        if not chartOn and shown == 0 then under:Hide() end
    end }

    -- foot: paging at the left (these do not close the card), the Rank plan at the right
    local foot = newSection(state, 24)
    p.foot = foot
    local function page(delta)
        local target = pageOf(state.data) + delta
        local count = num(safe(HonorLog.Weeks and HonorLog.Weeks.GetCount, HonorLog.Weeks)) or 0
        if target < 0 or target >= count then return end
        local ok, err = pcall(Moments.Present, Moments, "recap", { n = target })
        if not ok then report(err) end
    end
    p.earlier = Kit:Button(foot, L["Earlier"], "small")
    p.earlier:SetSize(70, 22)
    p.earlier:SetPoint("LEFT", foot, "LEFT", 0, 0)
    p.earlier:SetScript("OnClick", function() if p.earlier:IsEnabled() then page(1) end end)
    track(state, p.earlier)
    p.later = Kit:Button(foot, L["Later"], "small")
    p.later:SetSize(70, 22)
    p.later:SetPoint("LEFT", foot, "LEFT", 76, 0)
    p.later:SetScript("OnClick", function() if p.later:IsEnabled() then page(-1) end end)
    track(state, p.later)
    p.button = button(state, foot, L["Rank plan"], function()
        if HonorLog.Window then HonorLog.Window:Show("rank") end
    end)
    p.button:SetPoint("RIGHT", foot, "RIGHT", 0, 0)
    fills[#fills + 1] = { foot, function(data)
        local n = pageOf(data)
        local count = num(safe(HonorLog.Weeks and HonorLog.Weeks.GetCount, HonorLog.Weeks)) or 0
        p.earlier:SetEnabled(n + 1 < count)
        p.later:SetEnabled(n > 0)
    end }
end

--------------------------------------------------------------------------------
-- The four kinds, the events and the slash command
--------------------------------------------------------------------------------

KINDS.report = { setting = "momentReport", width = 480, name = "HonorLogReportCard", title = L["HonorLog: game report"], build = buildReport }
KINDS.rankUp = { setting = "momentRankUp", width = 360, name = "HonorLogRankUpCard", title = L["HonorLog: rank up"], build = buildRankUp }
KINDS.honorCap = { setting = "momentHonorCap", width = 360, name = "HonorLogHonorCapCard", title = L["HonorLog: honor cap"], build = buildHonorCap }

KINDS.recap = { setting = "momentRecap", width = 480, name = "HonorLogRecapCard", title = L["HonorLog: weekly recap"], build = buildRecap }

-- The recap of week n now (0 this week, 1 the last closed week), whatever the setting says. False with a line in
-- chat when there is no such week.
function Moments:ShowRecap(n)
    n = num(n)
    n = n and n >= 0 and math.floor(n) or 1
    if not readRecap(n) then
        HonorLog:Say(L["No week to show yet."])
        return false
    end
    return self:Show("recap", { n = n })
end

-- /honorlog moment report|rank|cap|recap [n]: the card now, whatever the settings say.
function Moments:Demo(arg)
    local which, rest = (arg or ""):lower():match("^(%S*)%s*(%S*)")
    if which == "report" then
        local list = safe(HonorLog.GetHistory, HonorLog, "character", 1)
        local record = type(list) == "table" and list[1] or nil
        if not record then
            HonorLog:Say(L["No saved game to show yet. The card appears by itself when your first battleground ends."])
            return
        end
        self:Show("report", record)
    elseif which == "rank" then
        local info = HonorLog.Rank and safe(HonorLog.Rank.GetInfo, HonorLog.Rank)
        local rank = type(info) == "table" and num(info.rank) or nil
        -- nobody ranks up to rank 0: before the first rank the card shows rank 1, the first one the player will see
        if not rank or rank < 1 then rank = 1 end
        self:Show("rankUp", { rank = rank, info = info })
    elseif which == "cap" then
        self:Show("honorCap", {})
    elseif which == "recap" and (rest == "" or tonumber(rest)) then
        self:ShowRecap(rest ~= "" and tonumber(rest) or 1)
    else
        HonorLog:Say(L["Usage: /honorlog moment report|rank|cap|recap [week]"])
    end
end

local function listen(event, kind, toData)
    HonorLog.RegisterCallback(Moments, event, function(_, ...)
        if not Moments:Shows(kind) then return end
        local ok, err = pcall(function(...) Moments:Show(kind, toData(...)) end, ...)
        if not ok then report(err) end
    end)
end

listen("HonorLog_GameRecorded", "report", function(record) return record end)
listen("HonorLog_RankUp", "rankUp", function(rank, info) return { rank = rank, info = info } end)
listen("HonorLog_HonorCapNear", "honorCap", function(current, cap) return { current = current, cap = cap } end)

--------------------------------------------------------------------------------
-- When the recap shows by itself
--------------------------------------------------------------------------------

-- Once, for the week that has ended, when HonorLog_WeekEnded fires: not for an empty week, not inside a
-- battleground (held until the player is out), and a little late at login so the player is there to see it. The
-- week turns over lazily (at login, on a game, an honor gain, or when anything reads the week), so the event
-- can come at any of those; a record is announced once whatever happens to it.
local announced = setmetatable({}, { __mode = "k" })
local heldRecap -- the record waiting for the end of a battleground
Moments.loadedAt = num(call(GetTime))

local function weekIsEmpty(rec)
    local function any(v) v = num(v) return v ~= nil and v > 0 end
    return not (any(rec.games) or any(rec.honor) or any(rec.bgHonor) or any(rec.kills) or any(rec.deaths))
end

local function deliverRecap(rec)
    if not Moments:Shows("recap") then return end
    if HonorLog:IsInBG() then
        heldRecap = rec
        return
    end
    local n = HonorLog.Weeks and HonorLog.Weeks:IndexOf(rec)
    if n then Moments:Show("recap", { n = n }) end
end

HonorLog.RegisterCallback(Moments, "HonorLog_WeekEnded", function(_, rec)
    local ok, err = pcall(function()
        if type(rec) ~= "table" or announced[rec] then return end
        announced[rec] = true
        if reading > 0 then return end -- a card is being filled: it shows a week already
        if not Moments:Shows("recap") or weekIsEmpty(rec) then return end
        local now, loaded = num(call(GetTime)), num(Moments.loadedAt)
        if now and loaded and now - loaded < RECAP_LOGIN_WINDOW then
            C_Timer.After(RECAP_LOGIN_DELAY, function()
                local ok2, err2 = pcall(deliverRecap, rec)
                if not ok2 then report(err2) end
            end)
        else
            deliverRecap(rec)
        end
    end)
    if not ok then report(err) end
end)

-- Out of the battleground: show the held recap a moment later (the loading screen is still up at first).
if type(HonorLog.OnBattlegroundLeave) == "function" then
    hooksecurefunc(HonorLog, "OnBattlegroundLeave", function()
        C_Timer.After(RECAP_LEAVE_BG_DELAY, function()
            local rec = heldRecap
            if not rec then return end
            heldRecap = nil
            local ok, err = pcall(deliverRecap, rec)
            if not ok then report(err) end
        end)
    end)
end
