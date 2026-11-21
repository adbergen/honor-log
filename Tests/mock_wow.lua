--[[ HonorLog - Tests/mock_wow.lua

    A stand-in for the WoW Forever Lua environment so the addon can be loaded
    and driven by a plain Lua interpreter in CI. The mock is Forever-shaped on
    purpose: it has the retail-style C_ namespaces (C_PvP, C_MajorFactions,
    C_CurrencyInfo, C_SeasonInfo, C_Item, C_Container, ...) and leaves out the
    TBC-only globals (GetHonorCurrency, GetPVPCurrency, GetArenaCurrency,
    GetBattlefieldScore, GetItemInfo, GetItemCount, GetContainer*,
    GetAddOnMetadata, InterfaceOptions_AddCategory, CombatLogGetCurrentEventInfo),
    so a call to any of them fails the test with a nil-call error.

    Registering an unknown or restricted event raises, as on the client.
    Run via Tests/run.lua.
]]

unpack = unpack or table.unpack -- luacheck: ignore (5.2+ compatibility)

local M = {}
M.frames = {} -- every created frame, for event dispatch

-- ─── Frame mock ──────────────────────────────────────────────────────

local FrameMT = {}
local methods = {}

local FRAME_TYPES = {
    Frame = true, Button = true, ScrollFrame = true, Slider = true,
    CheckButton = true, EditBox = true, StatusBar = true, Cooldown = true,
}

local function newObject(objType, parent, name)
    local o = setmetatable({
        __type = objType, __parent = parent, __name = name,
        __scripts = {}, __events = {}, __children = {}, __nregions = 0,
        __shown = true,
    }, FrameMT)
    if parent and type(parent) == "table" and parent.__children then
        if FRAME_TYPES[objType] then
            table.insert(parent.__children, o)
        else
            parent.__nregions = parent.__nregions + 1
        end
    end
    if FRAME_TYPES[objType] then table.insert(M.frames, o) end
    if name then _G[name] = o end
    return o
end
M.newObject = newObject

local function noop(self) return self end
local CHILD_KEYS = { ScrollBar = true, Text = true, Track = true, Thumb = true }
FrameMT.__index = function(_, key)
    -- Internal "__" storage fields must read as nil when unset, not as noop —
    -- otherwise getters like `self.__height or 0` see a truthy function.
    if type(key) == "string" and key:sub(1, 2) == "__" then return nil end
    -- A client without Frame:CreateLine: M.noCreateLine makes the method read as missing.
    if key == "CreateLine" and M.noCreateLine then return nil end
    if methods[key] then return methods[key] end
    -- Template child keys (parentKey): created on first use, like the client's.
    if CHILD_KEYS[key] then
        local child = newObject(key == "Text" and "FontString" or "Frame", _, nil)
        rawset(_, key, child)
        return child
    end
    return noop
end

-- getters that must return real values
function methods.GetName(self) return self.__name end
function methods.GetObjectType(self) return self.__type or "Frame" end
function methods.IsObjectType(self, t) return (self.__type or "Frame") == t end
function methods.GetParent(self) return self.__parent end
function methods.SetParent(self, p) self.__parent = p; return self end
function methods.GetChildren(self) return unpack(self.__children) end
function methods.GetNumRegions(self) return self.__nregions or 0 end
function methods.GetNumChildren(self) return #self.__children end
function methods.GetWidth(self) return self.__width or 0 end
function methods.GetHeight(self) return self.__height or 0 end
function methods.SetWidth(self, w) self.__width = w; self.__wrapWidth = w; return self end
function methods.SetHeight(self, h) self.__height = h; return self end
function methods.SetSize(self, w, h) self.__width, self.__height = w, h; return self end
function methods.GetNumPoints() return 0 end
-- Points are remembered, so a test can read back where a frame was put.
function methods.SetPoint(self, point, rel, relPoint, x, y)
    if type(rel) ~= "table" then rel, relPoint, x, y = nil, rel, relPoint, x end
    self.__points = self.__points or {}
    self.__points[#self.__points + 1] = { point, rel, relPoint or point, x or 0, y or 0 }
    return self
end
function methods.ClearAllPoints(self) self.__points = nil; return self end
function methods.GetPoint(self, i)
    local p = self.__points and self.__points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
    return "CENTER", nil, "CENTER", 0, 0
end
-- A wrapped text is as tall as its lines: six pixels a character across the set width, twelve a line.
function methods.SetMaxLines(self, n) self.__maxLines = n; return self end
function methods.GetStringHeight(self)
    local text = tostring(self.__text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    -- the width the text was told to wrap at (SetText overwrites __width with the string's own width)
    local width = (self.__wrapWidth and self.__wrapWidth > 0) and self.__wrapWidth or 300
    local lines = math.max(1, math.ceil(#text * 6 / width))
    if self.__maxLines then lines = math.min(lines, self.__maxLines) end
    return lines * 12
end
function methods.GetScale(self) return self.__scale or 1 end
function methods.SetScale(self, v) self.__scale = v; return self end
function methods.GetEffectiveScale() return 1 end
function methods.GetCenter() return 400, 300 end
function methods.GetFrameLevel(self) return self.__level or 0 end
function methods.SetFrameLevel(self, level) self.__level = level; return self end
-- A scroll frame remembers where it was scrolled to, like the client's, and reports the range its scroll child allows.
function methods.GetVerticalScroll(self) return self.__vscroll or 0 end
function methods.SetVerticalScroll(self, v) self.__vscroll = v; return self end
function methods.GetVerticalScrollRange(self)
    local child = self.__scrollchild
    return math.max(0, ((child and child.__height) or 0) - (self.__height or 0))
end
function methods.GetLeft() return 0 end
function methods.GetTop() return 0 end
function methods.GetValue(self) return self.__value or 0 end
-- Like the client, a value change fires OnValueChanged straight away, even
-- when the change comes from code rather than the user.
function methods.SetValue(self, v)
    local changed = v ~= self.__value
    self.__value = v
    if changed and self.__scripts.OnValueChanged then self.__scripts.OnValueChanged(self, v) end
    return self
end
function methods.IsMouseOver() return false end
function methods.HasFocus() return false end
function methods.IsForbidden() return false end
function methods.IsShown(self) return self.__shown ~= false end
function methods.IsVisible(self) return self.__shown ~= false end
-- With M.runShowScripts on, a change of shown state runs OnShow / OnHide, as the client does.
function methods.Show(self)
    local was = self.__shown ~= false
    self.__shown = true
    if M.runShowScripts and not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end
    return self
end
function methods.Hide(self)
    local was = self.__shown ~= false
    self.__shown = false
    if M.runShowScripts and was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
    return self
end
function methods.SetShown(self, b) self.__shown = b and true or false; return self end
-- Buttons remember whether they are enabled, so a test can read a disabled "Move up".
function methods.SetEnabled(self, b) self.__enabled = b and true or false; return self end
function methods.IsEnabled(self) return self.__enabled ~= false end

-- Colours, textures and fonts are remembered so a test can read what was drawn.
function methods.SetColorTexture(self, r, g, b, a) self.__color = { r, g, b, a }; self.__texture = nil; self.__atlas = nil; return self end
function methods.SetVertexColor(self, r, g, b, a) self.__vertex = { r, g, b, a }; return self end
function methods.SetTextColor(self, r, g, b, a) self.__textColor = { r, g, b, a }; return self end
function methods.SetTexture(self, tex) self.__texture = tex; self.__atlas = nil; return self end
function methods.SetTexCoord(self, ...) self.__texCoord = { ... }; return self end
function methods.SetDesaturated(self, on) self.__desaturated = on and true or false; return self end
function methods.SetFontObject(self, font) self.__font = font; return self end

function methods.SetText(self, txt)
    self.__text = txt
    if self.__type == "FontString" then
        self.__height = 12
        self.__width = #tostring(txt or "") * 6
    end
    return self
end
function methods.GetText(self) return self.__text end
function methods.GetStringWidth(self) return self.__width or (#tostring(self.__text or "") * 6) end

function methods.SetScript(self, name, fn) self.__scripts[name] = fn; return self end
function methods.GetScript(self, name) return self.__scripts[name] end
function methods.HookScript(self, name, fn)
    local prev = self.__scripts[name]
    self.__scripts[name] = function(...)
        if prev then prev(...) end
        return fn(...)
    end
    return self
end
function methods.RegisterEvent(self, e)
    if M.restrictedEvents[e] then
        error("blocked from an action only available to the Blizzard UI: " .. e)
    end
    if not M.knownEvents[e] then error("Frame:RegisterEvent(): Attempt to register unknown event \"" .. tostring(e) .. "\"") end
    self.__events[e] = true
    return self
end
function methods.UnregisterAllEvents(self) self.__events = {}; return self end
function methods.UnregisterEvent(self, e) self.__events[e] = nil; return self end
function methods.RegisterForClicks() return end

function methods.CreateTexture(self) return newObject("Texture", self) end
-- Lines (Frame:CreateLine): the end points, thickness and colour are remembered so a test can read the drawing.
function methods.CreateLine(self) return newObject("Line", self) end
function methods.SetStartPoint(self, point, rel, x, y) self.__start = { point, rel, x or 0, y or 0 }; return self end
function methods.SetEndPoint(self, point, rel, x, y) self.__end = { point, rel, x or 0, y or 0 }; return self end
function methods.SetThickness(self, t) self.__thickness = t; return self end
function methods.GetThickness(self) return self.__thickness end
function methods.CreateMaskTexture(self) return newObject("Texture", self) end
function methods.SetRotation(self, r) self.__rotation = r; return self end
function methods.SetAtlas(self, atlas) self.__atlas = atlas; self.__color = nil; self.__texture = nil; return self end
-- The client hands the name back only for an atlas it has. M.atlasInfoBlind lists atlases the client has but
-- C_Texture.GetAtlasInfo does not report (seen in game), so only this read finds them.
function methods.GetAtlas(self)
    local name = self.__atlas
    if name and (M.atlasInfoBlind[name] or M.atlasKnown(name)) then return name end
end
function methods.GetRotation(self) return self.__rotation end
function methods.SetAlpha(self, a) self.__alpha = a; return self end
function methods.GetAlpha(self) return self.__alpha or 1 end
function methods.CreateFontString(self) return newObject("FontString", self) end
function methods.CreateAnimationGroup(self) return newObject("AnimationGroup", self) end
function methods.CreateAnimation(self) return newObject("Animation", self) end
-- An animation group remembers whether it plays; a test ends it with group.__scripts.OnFinished(group, false).
function methods.Play(self) self.__playing = true; return self end
function methods.Stop(self) self.__playing = false; return self end
function methods.IsPlaying(self) return self.__playing == true end
function methods.SetScrollChild(self, c) self.__scrollchild = c; return self end

-- ─── Globals ─────────────────────────────────────────────────────────

-- Templates: any template is accepted (as before) unless a test lists it in M.missingTemplates, which makes
-- CreateFrame raise the way the client does for an unknown one. A few templates give the frame the children
-- and methods the real ones have (M.templateInit), so the full window is built the way it is in the game.
M.missingTemplates = {}
function M.portraitMixin(f)
    local title = newObject("FontString", f)
    rawset(f, "GetTitleText", function() return title end)
    rawset(f, "SetTitle", function(self, text)
        if M.titleRaises then error("SetTitle: forced failure") end
        local fs = self:GetTitleText()
        fs:SetText(text) -- raises when GetTitleText was replaced by something that is not a FontString
        self.__title = text
    end)
    rawset(f, "SetPortraitToAsset", function(self, tex) self.__portrait = tex end)
end
M.hollowTemplates = {}
M.templateInit = {
    -- Like Blizzard's PortraitFrameMixin: SetTitle goes through the frame's own GetTitleText, so an addon
    -- that puts another GetTitleText on the frame breaks it ("attempt to call a nil value", seen in game).
    PortraitFrameTemplate = function(f)
        rawset(f, "CloseButton", newObject("Button", f))
        M.portraitMixin(f)
    end,
    PortraitFrameBaseTemplate = function(f) M.portraitMixin(f) end,
}
function CreateFrame(objType, name, parent, template)
    if template then
        for t in tostring(template):gmatch("[^,%s]+") do
            if M.missingTemplates[t] or M.missingTemplates["*"] then
                error("CreateFrame: Couldn't find inherited node \"" .. t .. "\"")
            end
        end
    end
    local f = newObject(objType or "Frame", parent, name)
    if template then
        for t in tostring(template):gmatch("[^,%s]+") do
            -- A real template brings regions and children; M.hollowTemplates lists ones that come back empty,
            -- the way a client that only logs a missing template would hand them over.
            if not M.hollowTemplates[t] then
                if M.templateInit[t] then M.templateInit[t](f) end
                f.__nregions = (f.__nregions or 0) + 1
            end
        end
        f.__template = template
    end
    return f
end

function hooksecurefunc(arg1, arg2, arg3)
    local tbl, key, post
    if type(arg1) == "table" then
        tbl, key, post = arg1, arg2, arg3
    else
        tbl, key, post = _G, arg1, arg2
    end
    local orig = tbl[key]
    tbl[key] = function(...)
        if orig then orig(...) end
        return post(...)
    end
end

-- Timers run at once unless a test defers them with M.deferTimers = true.
-- A deferred timer remembers when it is due (M.now + delay), so M.advance(dt)
-- can move the clock and run what falls due, in order, including timers that
-- the callbacks themselves schedule.
M.timers = {}
M.deferTimers = false
C_Timer = {
    After = function(delay, fn)
        if not fn then return end
        if M.deferTimers then
            M.timers[#M.timers + 1] = { delay = delay, fn = fn, due = (M.now or 0) + delay }
        else
            fn()
        end
    end,
    -- Tickers never fire by themselves; a test runs one with M.tickers[i].fn().
    NewTicker = function(interval, fn)
        local t = { interval = interval, fn = fn, cancelled = false }
        function t.Cancel(self) self.cancelled = true end
        M.tickers[#M.tickers + 1] = t
        return t
    end,
}
M.tickers = {}
function M.advance(dt)
    local target = (M.now or 0) + dt
    while true do
        local nextIndex
        for i, t in ipairs(M.timers) do
            if t.due <= target and (not nextIndex or t.due < M.timers[nextIndex].due) then nextIndex = i end
        end
        if not nextIndex then break end
        local t = table.remove(M.timers, nextIndex)
        if t.due > (M.now or 0) then M.now = t.due end
        t.fn()
    end
    M.now = target
end
function M.flushTimers(maxDelay)
    local pending = M.timers
    M.timers = {}
    table.sort(pending, function(a, b) return a.delay < b.delay end)
    for _, t in ipairs(pending) do
        if not maxDelay or t.delay <= maxDelay then t.fn() else M.timers[#M.timers + 1] = t end
    end
end

-- Events the Forever docs list (the ones HonorLog and the probe use).
M.knownEvents = {}
for _, e in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
    "UPDATE_BATTLEFIELD_STATUS", "UPDATE_BATTLEFIELD_SCORE", "CHAT_MSG_BG_SYSTEM_ALLIANCE",
    "CHAT_MSG_BG_SYSTEM_HORDE", "CHAT_MSG_BG_SYSTEM_NEUTRAL", "CHAT_MSG_RAID_BOSS_EMOTE",
    "CHAT_MSG_MONSTER_YELL", "HONOR_XP_UPDATE", "CHAT_MSG_COMBAT_HONOR_GAIN", "CHAT_MSG_SYSTEM",
    "PLAYER_DEAD", "BATTLEGROUND_POINTS_UPDATE", "CURRENCY_DISPLAY_UPDATE", "BAG_UPDATE",
    "BAG_UPDATE_DELAYED", "POST_MATCH_CURRENCY_REWARD_UPDATE", "POST_MATCH_ITEM_REWARD_UPDATE", "PVP_MATCH_ACTIVE", "PVP_MATCH_COMPLETE", "PLAYER_PVP_KILLS_CHANGED",
    "PLAYER_PVP_RANK_CHANGED", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "ADDON_RESTRICTION_STATE_CHANGED",
    "PARTY_KILL", "UPDATE_FACTION", "PLAYER_LEVEL_UP", "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "PLAYER_LEAVING_WORLD",
    "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "CHAT_MSG_ADDON", "PLAYER_REGEN_ENABLED",
}) do M.knownEvents[e] = true end
-- Known to the client but flagged HasRestrictions in the docs.
M.restrictedEvents = { COMBAT_LOG_EVENT_UNFILTERED = true, COMBAT_LOG_EVENT = true }

-- Quests: titles the client knows and quests flagged completed.
-- M.questLog[id] = { complete = bool, objectives = { { text, finished } } } is a quest in the log.
M.questTitles, M.questsDone, M.questLog = {}, {}, {}
C_QuestLog = {
    GetTitleForQuestID = function(id) return M.questTitles[id] end,
    IsQuestFlaggedCompleted = function(id) return M.questsDone[id] == true end,
    IsOnQuest = function(id) return M.questLog[id] ~= nil end,
    IsComplete = function(id) return M.questLog[id] ~= nil and M.questLog[id].complete == true end,
    ReadyForTurnIn = function(id) return M.questLog[id] ~= nil and M.questLog[id].complete == true end,
    GetQuestObjectives = function(id)
        local q = M.questLog[id]
        if not q then return {} end
        local out = {}
        for i, o in ipairs(q.objectives or {}) do
            out[i] = { text = o.text, type = "monster", finished = o.finished, numFulfilled = 0, numRequired = 1 }
        end
        return out
    end,
}

-- Secret values: a table registered here makes issecretvalue() true. Touching
-- one (comparison, arithmetic, indexing) errors, like the client does.
local secrets = setmetatable({}, { __mode = "k" })
local SecretMT = {}
local function secretError() error("attempt to use a secret value") end
SecretMT.__index = secretError
SecretMT.__eq = nil
SecretMT.__lt = secretError
SecretMT.__le = secretError
SecretMT.__add = secretError
SecretMT.__concat = secretError
SecretMT.__call = secretError
function M.newSecret()
    local s = setmetatable({}, SecretMT)
    secrets[s] = true
    return s
end
function issecretvalue(v) return secrets[v] == true end

-- PvP state the C_PvP mock reports; tests change it.
M.pvp = {
    matchActive = false,
    matchComplete = false,
    scoresSecret = false,  -- GetScoreInfo rows carry secret numbers
    numScores = 0,
    duration = 612,        -- C_PvP.GetActiveMatchDuration
    winner = 1,            -- C_PvP.GetActiveMatchWinner (the client reports 0 at other times)
    bfWinner = nil,        -- GetBattlefieldWinner
    team = 1,              -- GetBattlefieldArenaFaction
    sessionHK = 5,         -- GetPVPSessionStats
    roster = nil,          -- optional list of { name, guid, faction, kb, hk, deaths, damage, healing, stats = { { id, name, value } } }
    columns = nil,         -- optional list of { id, name } for GetMatchPVPStatColumns
    requests = 0,          -- RequestBattlefieldScoreData calls
}
M.secretHonor = M.newSecret()

local function rosterRow(i)
    local r = M.pvp.roster[i]
    if not r then return nil end
    local secret = M.pvp.scoresSecret
    local function v(x) return secret and M.newSecret() or x end
    local stats = {}
    for _, st in ipairs(r.stats or {}) do
        stats[#stats + 1] = { pvpStatID = st.id, pvpStatValue = v(st.value), name = st.name }
    end
    return {
        name = r.name, guid = r.guid, killingBlows = v(r.kb), honorableKills = v(r.hk), deaths = v(r.deaths),
        honorGained = secret and M.secretHonor or (r.honor or 0), faction = r.faction, raceName = "Human",
        className = "Warrior", classToken = r.class or "WARRIOR", damageDone = v(r.damage or 0),
        healingDone = v(r.healing or 0), stats = stats,
    }
end

local function scoreRow(i)
    if M.pvp.roster then return rosterRow(i) end
    if i > M.pvp.numScores or i < 1 then return nil end
    local secret = M.pvp.scoresSecret
    return {
        name = i == 1 and "Tester" or ("Player" .. i), guid = "Player-1-" .. i,
        killingBlows = secret and M.newSecret() or 3, honorableKills = secret and M.newSecret() or 12,
        deaths = secret and M.newSecret() or 2, honorGained = secret and M.secretHonor or 450,
        damageDone = secret and M.newSecret() or 1000, healingDone = secret and M.newSecret() or 0,
        faction = 1, className = "Warrior", classToken = "WARRIOR",
        stats = { { pvpStatID = 1, pvpStatValue = secret and M.newSecret() or 7, name = "Flags" } },
    }
end

C_PvP = {
    GetBattlegroundInfo = function(i)
        local list = {
            { name = "Warsong Gulch", mapID = 489, battlegroundID = 2, maxPlayers = 10 },
            { name = "Arathi Basin", mapID = 529, battlegroundID = 3, maxPlayers = 15 },
            { name = "Alterac Valley", mapID = 30, battlegroundID = 1, maxPlayers = 40 },
        }
        return list[i]
    end,
    GetScoreInfo = scoreRow,
    GetScoreInfoByPlayerGuid = function(guid)
        if M.pvp.roster then
            for i, r in ipairs(M.pvp.roster) do
                if r.guid == guid then return rosterRow(i) end
            end
            return nil
        end
        if guid == "Player-1-1" then return scoreRow(1) end
    end,
    GetMatchPVPStatColumns = function()
        if M.pvp.columns then
            local cols = {}
            for i, c in ipairs(M.pvp.columns) do cols[i] = { pvpStatID = c.id, name = c.name, orderIndex = i } end
            return cols
        end
        return { { pvpStatID = 1, name = "Flags", orderIndex = 1 } }
    end,
    GetActiveMatchWinner = function() return M.pvp.matchComplete and M.pvp.winner or 0 end,
    GetActiveMatchDuration = function() return M.pvp.duration end,
    -- Enum.PvPMatchState: 2 StartUp, 3 Engaged, 5 Complete.
    GetActiveMatchState = function() return M.pvp.matchComplete and 5 or 3 end,
    IsMatchActive = function() return M.pvp.matchActive end,
    IsMatchComplete = function() return M.pvp.matchComplete end,
    IsBattleground = function() return false end,
    IsPVPMap = function() return false end,
}
-- Errors routed to the client's error handler (libraries do this) are recorded
-- here instead of raised, so a test can look at them.
M.handledErrors = {}
-- The client's securecallfunction runs a callback and reports its error without raising it (CallbackHandler uses it).
M.secureErrors = {}
function securecallfunction(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then M.secureErrors[#M.secureErrors + 1] = tostring(err) end
end
function geterrorhandler() return function(e) M.handledErrors[#M.handledErrors + 1] = tostring(e) end end
function GetNumBattlegroundTypes() return 3 end
function GetBattlefieldWinner() return M.pvp.bfWinner end
function GetNumBattlefieldScores() return M.pvp.roster and #M.pvp.roster or M.pvp.numScores end
function GetBattlefieldStatus() return "none" end
function GetMaxBattlefieldID() return 3 end
function GetBattlefieldArenaFaction() return M.pvp.team end
function RequestBattlefieldScoreData() M.pvp.requests = M.pvp.requests + 1 end
function GetPVPSessionStats() return M.pvp.sessionHK, 0 end
function GetPVPLifetimeStats() return 120, 4 end
function GetPVPYesterdayStats() return 9, 0 end

M.rank = { level = 3, earned = 120, threshold = 1050 }
-- Rank-window state the progression mock reports; tests change it. noData makes the
-- call return nil (a low-level character); noTotalFn removes GetTotalReputationForRenownLevel.
M.rankWindow = { cap = 5, prevCap = 3, week = 2, seasonMax = 14, noData = false }
local RANK_CURVE = { 750, 900, 1050, 1200, 1350, 1500, 1650, 1800, 1950, 2100, 2350, 2500, 2650, 3000 }
-- Ranks that have rewards; the others return an empty list, like the client.
M.rankRewards = {
    [2] = { { icon = 1002, description = "Insignia trinket" } },
    [3] = { { icon = 1003, description = "Cloak" } },
    [8] = { { icon = 1008, description = "Wrist Seal" }, { icon = 1009, description = "Waist Seal" } },
}
C_MajorFactions = {
    GetMajorFactionProgressionInfo = function(id)
        if id == 2800 and not M.rankWindow.noData then
            return { renownLevel = M.rank.level, renownReputationEarned = M.rank.earned,
                     renownLevelThreshold = M.rank.threshold, currentWeekProgressiveMaxLevel = M.rankWindow.cap,
                     previousWeekProgressiveMaxLevel = M.rankWindow.prevCap, maxLevel = M.rankWindow.seasonMax,
                     weekNumber = M.rankWindow.week }
        end
    end,
    GetTotalReputationForRenownLevel = function(_, level)
        local sum = 0
        for i = 1, math.min(level, #RANK_CURVE) do sum = sum + RANK_CURVE[i] end
        return sum
    end,
    GetMajorFactionData = function(id) return { factionID = id, name = "PvP Rank Points" } end,
    GetRenownRewardsForLevel = function(_, level) return M.rankRewards[level] or {} end,
}
function M.removeTotalFn() C_MajorFactions.GetTotalReputationForRenownLevel = nil end
-- Faction and rank titles, as the client's own strings (key PVP_RANK_<5..18>_<0 Horde|1 Alliance>).
M.faction = "Alliance"
local HORDE = { "Scout", "Grunt", "Sergeant", "Senior Sergeant", "First Sergeant", "Stone Guard", "Blood Guard",
    "Legionnaire", "Centurion", "Champion", "Lieutenant General", "General", "Warlord", "High Warlord" }
local ALLIANCE = { "Private", "Corporal", "Sergeant", "Master Sergeant", "Sergeant Major", "Knight", "Knight-Lieutenant",
    "Knight-Captain", "Knight-Champion", "Lieutenant Commander", "Commander", "Marshal", "Field Marshal", "Grand Marshal" }
for i = 1, 14 do
    _G["PVP_RANK_" .. (4 + i) .. "_0"] = HORDE[i]
    _G["PVP_RANK_" .. (4 + i) .. "_1"] = ALLIANCE[i]
end
PVP_RANK_0_NAME = "Unranked"
PVP_RANK_REWARDS_VENDOR_HORDE = "Rank rewards are sold by the Horde quartermasters."
PVP_RANK_REWARDS_VENDOR_ALLIANCE = "Rank rewards are sold by the Alliance quartermasters."
local Enum_PvPRanks = { RankNone = 0, Rank_1 = 5, Rank_14 = 18 }
function GetText(key) return _G[key] end
function UnitSex() return 2 end
M.arenaSeason = 2
function GetCurrentArenaSeason() return M.arenaSeason end
-- Atlases the texture mock knows; SetAtlas on an unknown one would show nothing on the client.
-- Atlases the client knows besides the rank icons: M.atlases[name] = true.
M.atlases = { ["UI-WorldMapArrow"] = true }
-- M.atlasMode: "default" (the list above), "all" (every atlas exists) or "none" (no atlas exists).
M.atlasMode = "default"
M.atlasInfoBlind = {}
function M.atlasKnown(name)
    if M.atlasMode == "none" then return false end
    return M.atlasMode == "all" or M.atlases[name] == true or name:find("^UI%-Character%-Info%-Honor%-Icon%-%d+$") ~= nil
end
C_Texture = { GetAtlasInfo = function(name)
    if M.atlasInfoBlind[name] then return nil end
    if M.atlasKnown(name) then return { width = 64, height = 64 } end
end }
local CURRENCIES = {
    [1792] = { name = "Honor", quantity = 8200, maxQuantity = 25000 },
    [3468] = { name = "PvP Rank Points", quantity = 120, maxQuantity = 0 },
    [3473] = { name = "PvP Rank", quantity = 3, maxQuantity = 14 },
}
M.currencies = CURRENCIES
C_CurrencyInfo = {
    GetCurrencyInfo = function(id)
        local c = CURRENCIES[id]
        if not c then return nil end
        return { name = c.name, quantity = c.quantity, maxQuantity = c.maxQuantity, currencyID = id }
    end,
}
M.seasonSeconds = 86400 * 30
C_SeasonInfo = {
    GetCurrentDisplaySeasonID = function() return 1 end,
    GetCurrentDisplaySeasonExpansion = function() return 0 end,
    GetTimeUntilCurrentPVPSeasonEnd = function() return M.seasonSeconds end,
}
M.bagItems = { [20558] = 12, [20559] = 3 }
M.itemQuality = {} -- item id -> quality, for C_Item.GetItemQualityByID
C_Item = {
    GetItemIconByID = function(id) return 100000 + id % 1000 end,
    GetItemQualityByID = function(id) return M.itemQuality[id] end,
    GetItemCount = function(id) return M.bagItems[id] or 0 end,
    GetItemInfo = function(id)
        return "Item " .. tostring(id), "|cff0070dd|Hitem:" .. tostring(id) .. "|h[Item " .. tostring(id) .. "]|h|r",
            3, 60, 55, "Armor", "Plate", 1, "INVTYPE_CHEST", 134400
    end,
}
-- Item ids in the backpack (bag 0) and worn items by inventory slot; tests change them.
M.bagContents = {}
M.equipped = {}
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and #M.bagContents or 0 end,
    GetContainerItemID = function(bag, slot) return bag == 0 and M.bagContents[slot] or nil end,
    GetContainerItemInfo = function() return nil end,
}
-- The open vendor. items[i] = { id, name, price, ext (has an extended cost), costs = { { link, count } } }.
M.merchant = { items = {} }
C_MerchantFrame = {
    GetItemInfo = function(i)
        local it = M.merchant.items[i]
        if not it then return nil end
        return { name = it.name, texture = 1, price = it.price or 0, stackCount = 1, numAvailable = -1,
            isPurchasable = true, isUsable = true, hasExtendedCost = it.ext and true or false }
    end,
}
function GetMerchantNumItems() return #M.merchant.items end
function GetMerchantItemLink(i)
    local it = M.merchant.items[i]
    return it and ("|cff0070dd|Hitem:" .. it.id .. "::::::::60:|h[" .. (it.name or "x") .. "]|h|r") or nil
end
function GetMerchantItemCostInfo(i)
    local it = M.merchant.items[i]
    return it and it.costs and #it.costs or 0
end
function GetMerchantItemCostItem(i, c)
    local cost = M.merchant.items[i].costs[c]
    return 1, cost.count, cost.link, cost.name
end
MerchantFrame = CreateFrame("Frame", "MerchantFrame")
MerchantFrame:Hide()
-- Reputation standing (reaction id, 4 Neutral .. 8 Exalted) by faction id; a missing faction is not met yet.
-- M.repAmounts[id] = { current, floor, ceiling } (the client's absolute numbers) when a test wants amounts;
-- M.repSecret[id] = true makes the standing a secret value.
M.reputation = {}
M.repAmounts = {}
M.repSecret = {}
C_Reputation = {
    GetFactionDataByID = function(id)
        local reaction = M.reputation[id]
        if not reaction then return nil end
        local amounts = M.repAmounts[id] or {}
        return { factionID = id, name = "Faction " .. id, reaction = M.repSecret[id] and M.newSecret() or reaction,
            currentStanding = amounts.current or 0, currentReactionThreshold = amounts.floor,
            nextReactionThreshold = amounts.ceiling }
    end,
}
Enum = { AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
    PvPRanks = Enum_PvPRanks }
C_RestrictedActions = {
    GetAddOnRestrictionState = function(t) return t == 3 and M.pvp.matchActive and 2 or 0 end,
    IsAddOnRestrictionActive = function(t) return t == 3 and M.pvp.matchActive end,
}

C_AddOns = {
    GetAddOnMetadata = function(_, key) return key == "Version" and "2.0.0-test" or "" end,
}

function GetInventoryItemID(_, slot) return M.equipped[slot] end
function UnitHonor() return 0 end
-- M.twoWordNames: the Forever way, seen in game: a name has two words, UnitName returns them as two values
-- and the client's GetUnitName joins them. M.playerName and M.realm override the defaults.
M.twoWordNames = false
function UnitName(unit)
    local name
    if unit == nil or unit == "player" then
        name = M.playerName or "Tester"
    else
        local u = M.units[unit]
        name = u and u.name or nil
    end
    if name and M.twoWordNames then
        local first, last = name:match("^(%S+)%s+(.+)$")
        if first then return first, last end
    end
    return name
end
function GetUnitName(unit)
    local first, last = UnitName(unit)
    if first and last then return first .. " " .. last end
    return first
end
function UnitFactionGroup() return M.faction, M.faction end
M.level = 60 -- tests change it
function UnitLevel() return M.level end
function UnitClass(unit)
    local u = unit and unit ~= "player" and M.units[unit]
    if u then return u.class, u.class, 1 end
    return "Warrior", "WARRIOR", 1
end
function UnitRace() return "Human", "Human" end
-- UnitGUID("npc") is the open vendor's GUID (nil when no test sets one); M.npcGuidSecret makes it secret.
M.npcGuid, M.npcGuidSecret = nil, false
-- The player's own GUID: M.playerGuid overrides it (false = none), M.playerGuidSecret makes it secret.
M.playerGuid, M.playerGuidSecret = nil, false
function UnitGUID(unit)
    if unit == "npc" then return M.npcGuidSecret and M.newSecret() or M.npcGuid end
    if M.playerGuidSecret then return M.newSecret() end
    if M.playerGuid == false then return nil end
    return M.playerGuid or "Player-1-1"
end
function GetRealmName() return M.realm or "TestRealm" end
M.zone, M.subzone = "Stormwind City", ""
function GetRealZoneText() return M.zone end
function GetSubZoneText() return M.subzone end
-- Maps: M.map = { id, x, y } is where the player stands (x, y in 0..1; nil x means no position).
-- A test can set M.map.restricted to make the position unavailable, as inside an instance.
M.map = { id = 1453, x = 0.744, y = 0.674 }
M.waypoint, M.superTracked, M.waypointBlocked = nil, nil, false
C_Map = {
    GetBestMapForUnit = function() return M.map.id end,
    GetPlayerMapPosition = function()
        if M.map.restricted or not M.map.x then return nil end
        local x, y = M.map.x, M.map.y
        return { GetXY = function() return x, y end }
    end,
    CanSetUserWaypointOnMap = function() return not M.waypointBlocked end,
    SetUserWaypoint = function(point) M.waypoint = point end,
    GetMapInfo = function(id) return M.mapNames[id] and { name = M.mapNames[id], mapID = id } or nil end,
    -- Rectangles of a map on an ancestor: M.mapRects["child:top"] = { minX, maxX, minY, maxY }.
    GetMapRectOnMap = function(id, top)
        local r = M.mapRects[id .. ":" .. top]
        if r then return r[1], r[2], r[3], r[4] end
    end,
    -- Target world positions: M.worldPos[mapId] = { instance, x, y } (a fixed point per map, ignoring the input).
    GetWorldPosFromMapPos = function(id, v)
        local w = M.worldPos[id]
        if not w then return nil end
        if M.worldPosFromInput then return w[1], CreateVector2D(w[2] + v.x * 1000, w[3] + v.y * 1000) end
        return w[1], CreateVector2D(w[2], w[3])
    end,
}
M.mapNames = { [1453] = "Stormwind City", [1454] = "Orgrimmar", [12] = "Kalimdor" }
M.mapRects, M.worldPos = {}, {}
function CreateVector2D(x, y)
    return { x = x, y = y, GetXY = function() return x, y end }
end

-- Player state the map arrow reads.
M.combat, M.inInstance = false, false
M.unitPosition = { 100, 200, 0, 0 } -- x (north), y (west), height, instance, as UnitPosition returns them
M.facing = 0
M.bindings = { TOGGLEWORLDMAP = "M" }
function InCombatLockdown() return M.combat end
function IsInInstance() return M.inInstance, M.inInstance and "pvp" or "none" end
function UnitPosition(unit)
    if unit ~= "player" or not M.unitPosition then return nil end
    local p = M.unitPosition
    if M.positionSecret then return M.newSecret(), M.newSecret(), 0, 0 end
    return p[1], p[2], p[3], p[4]
end
function GetPlayerFacing() return M.facing end
function GetBindingKey(action) return M.bindings[action] end

-- The world map: shown, the map it shows, and a canvas of known size and scale.
M.worldMap = { mapID = 1, setCalls = {} }
WorldMapFrame = CreateFrame("Frame", "WorldMapFrame", UIParent)
WorldMapFrame:Hide()
local worldCanvas = CreateFrame("Frame", nil, WorldMapFrame)
worldCanvas:SetSize(1000, 500)
M.worldCanvas = worldCanvas
M.canvasScale = 1
rawset(WorldMapFrame, "GetCanvas", function() return worldCanvas end)
rawset(WorldMapFrame, "GetCanvasScale", function() return M.canvasScale end)
rawset(WorldMapFrame, "GetMapID", function() return M.worldMap.mapID end)
rawset(WorldMapFrame, "OnMapChanged", function() end)
rawset(WorldMapFrame, "SetMapID", function(_, id)
    M.worldMap.setCalls[#M.worldMap.setCalls + 1] = id
    M.worldMap.mapID = id
    WorldMapFrame:OnMapChanged()
end)
-- Like the client: showing a panel runs its OnShow.
function ShowUIPanel(frame)
    M.panelShown = (M.panelShown or 0) + 1
    frame:Show()
    if frame.__scripts.OnShow then frame.__scripts.OnShow(frame) end
end
UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { uiMapID = map, position = { x = x, y = y } } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) M.superTracked = on end }
-- The instance the player is in; tests change it. mapID is the 8th return.
M.instance = { name = "Stormwind City", type = "none", mapID = 0 }
function GetInstanceInfo()
    local i = M.instance
    return i.name, i.type, 0, "", 0, 0, false, i.mapID
end
function M.setInstance(name, instanceType, mapID) M.instance = { name = name, type = instanceType, mapID = mapID } end

-- Units in sight (target, mouseover, nameplate1...): { name, class, enemy, dead, player }.
M.units = {}
function UnitExists(unit) return M.units[unit] ~= nil end
function UnitIsPlayer(unit) local u = M.units[unit]; return u ~= nil and u.player ~= false end
function UnitIsEnemy(_, unit) local u = M.units[unit]; return u ~= nil and u.enemy == true end
function UnitIsDeadOrGhost(unit) local u = M.units[unit]; return u ~= nil and u.dead == true end
function UnitIsFeignDeath() return false end
-- Death recap events the client would return: { timestamp, sourceGUID, sourceName, spellName, amount }.
M.recap = {}
C_DeathRecap = {
    GetRecapEvents = function() return M.recap end,
    HasRecapEvents = function() return #M.recap > 0 end,
}
-- Seconds to the weekly reset.
M.weeklyReset = 3 * 86400
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return M.weeklyReset end }
-- localizedClass, englishClass, localizedRace, englishRace, sex, name, realm
function GetPlayerInfoByGUID(guid)
    if guid == "Player-2-77" then return "Rogue", "ROGUE", "Orc", "Orc", 2, "EnemyRogue", "" end
    return "Warrior", "WARRIOR", "Human", "Human", 2, "Someone", ""
end
function GetBuildInfo() return "1.60.1", "70938", "Nov 1 2026", 16001 end
M.money = 123456 -- copper
function GetMoney() return M.money end

-- Addon messages. M.chat: inGuild, group (nil, "party", "raid" or "instance"), sendResult (the enum the
-- client returns; 0 = success), echo (the client plays a sender's own message back), secretSender,
-- sent (every message handed to SendAddonMessage).
M.chat = { inGuild = true, group = nil, sendResult = 0, echo = true, secretSender = false, sent = {}, registered = {} }
function IsInGuild() return M.chat.inGuild end
function IsInRaid() return M.chat.group == "raid" end
function IsInGroup(category)
    if category == 2 then return M.chat.group == "instance" end
    return M.chat.group ~= nil
end
C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix)
        M.chat.registered[prefix] = true
        return 0
    end,
    SendAddonMessage = function(prefix, text, chatType, target)
        M.chat.sent[#M.chat.sent + 1] = { prefix = prefix, text = text, chatType = chatType, target = target }
        if M.chat.sendResult == 0 and M.chat.echo then
            M.fireEvent("CHAT_MSG_ADDON", prefix, text, chatType, M.chat.secretSender and M.newSecret() or "Tester-Realm")
        end
        return M.chat.sendResult
    end,
}

-- The open quest window: M.quest = { id, title, money, xp, honor, rewards = { { name, texture, count,
-- quality, usable, itemID } }, choices = {...}, currencies = {...}, factions = {...} }, or nil when none.
M.quest = nil
function GetQuestID() return M.quest and M.quest.id or 0 end
function GetTitleText() return M.quest and M.quest.title end
function GetRewardMoney() return M.quest and M.quest.money or 0 end
function GetRewardXP() return M.quest and M.quest.xp or 0 end
function GetRewardHonor() return M.quest and M.quest.honor or 0 end
function GetNumQuestRewards() return M.quest and #(M.quest.rewards or {}) or 0 end
function GetNumQuestChoices() return M.quest and #(M.quest.choices or {}) or 0 end
function GetQuestItemInfo(kind, i)
    local list = M.quest and (kind == "choice" and M.quest.choices or M.quest.rewards) or {}
    local r = list[i]
    if r then return r[1], r[2], r[3], r[4], r[5], r[6] end
end
C_QuestInfoSystem = { GetQuestRewardCurrencies = function() return M.quest and M.quest.currencies or {} end }
C_QuestOffer = { GetQuestOfferMajorFactionReputationRewards = function() return M.quest and M.quest.factions or {} end }
function GetTime() return M.now or os.clock() end
function PlaySound() end
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857 }
M.alt = false -- tests set it to simulate Alt held
function IsAltKeyDown() return M.alt end
M.shift, M.ctrl = false, false -- tests set them to simulate a held modifier
function IsShiftKeyDown() return M.shift end
function IsControlKeyDown() return M.ctrl end
function GetCursorPosition() return 0, 0 end
function SetCursor() end
function ResetCursor() end
function BreakUpLargeNumbers(n)
    local text = tostring(math.floor(tonumber(n) or 0))
    local sign, digits = text:match("^(%-?)(%d+)$")
    digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return sign .. digits
end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
-- Blizzard's Lua aliases.
strmatch, strfind, strsub, strlen, strlower, strupper = string.match, string.find, string.sub, string.len, string.lower, string.upper
strrep, strbyte, strchar, strtrim = string.rep, string.byte, string.char, function(x) return (x:gsub("^%s+", ""):gsub("%s+$", "")) end
format, gsub, gmatch = string.format, string.gsub, string.gmatch
tinsert, tremove, sort = table.insert, table.remove, table.sort
floor, ceil, abs, min, max = math.floor, math.ceil, math.abs, math.min, math.max
date = os.date
time = os.time
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
ChatTypeInfo = { RAID_WARNING = { r = 1, g = 0.3, b = 0 } }
COMBATLOG_HONORGAIN = "%s dies (Honorable Kill: %s). You gain %d Honor."
COMBATLOG_HONORGAIN_NO_RANK = "%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)"
COMBATLOG_HONORAWARD = "You have been awarded %d honor."
if not bit then
    bit = { band = function(a, b)
        local r, bitv = 0, 1
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then r = r + bitv end
            a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
        end
        return r
    end }
end

-- Dropdown helpers (Blizzard_SharedXML).
-- A dropdown remembers its initialiser and its text. M.openDropdown(frame) runs the initialiser and
-- returns the entries it adds (the info tables); M.pickDropdown(frame, text) runs one entry's func, as
-- a click on it would. Tests drive the callbacks this way, not the state they write.
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) if M.ddCollect then M.ddCollect[#M.ddCollect + 1] = info end end
function UIDropDownMenu_Initialize(frame, fn) frame.__ddInit = fn end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText(frame, text) frame.__ddText = text end
function M.openDropdown(frame)
    local list = {}
    M.ddCollect = list
    frame.__ddInit(frame, 1)
    M.ddCollect = nil
    return list
end
function M.pickDropdown(frame, text)
    for _, info in ipairs(M.openDropdown(frame)) do
        if info.text == text then info.func(info) return info end
    end
    error("dropdown has no entry " .. tostring(text))
end
function UIDropDownMenu_SetWidth() end
function ToggleDropDownMenu() end
function CloseDropDownMenus() end

SlashCmdList = {}

Settings = {
    RegisterCanvasLayoutCategory = function(_, name)
        return { ID = name, GetID = function() return name end }
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}

-- ─── World frames ────────────────────────────────────────────────────

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1024, 768)
Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap:SetSize(140, 140)
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
UIErrorsFrame = CreateFrame("Frame", "UIErrorsFrame", UIParent)
DressUpFrame = CreateFrame("Frame", "DressUpFrame", UIParent)
UISpecialFrames = {}

-- The tooltip remembers what it was asked to show: M.tip.owner, .anchor, .itemID, .lines, .shown.
M.tip = { lines = {} }
rawset(GameTooltip, "SetOwner", function(_, owner, anchor) M.tip = { owner = owner, anchor = anchor, lines = {} } end)
rawset(GameTooltip, "SetItemByID", function(_, id) M.tip.itemID = id end)
rawset(GameTooltip, "AddLine", function(_, text, r, g, b) M.tip.lines[#M.tip.lines + 1] = { text = text, r = r, g = g, b = b } end)
rawset(GameTooltip, "Show", function() M.tip.shown = true end)
rawset(GameTooltip, "Hide", function() M.tip.shown = false end)

-- Blizzard font objects the kit looks up by name; M.removeFonts() takes them away to test the fallbacks.
M.fontNames = { "GameFontNormal", "GameFontNormalSmall", "GameFontHighlight", "GameFontDisableSmall",
    "GameFontHighlightLarge", "GameFontHighlightHuge", "GameFontNormalHuge" }
for _, n in ipairs(M.fontNames) do _G[n] = { name = n } end
function M.removeFonts() for _, n in ipairs(M.fontNames) do _G[n] = nil end end
function M.restoreFonts() for _, n in ipairs(M.fontNames) do _G[n] = { name = n } end end

-- ─── Test helpers ────────────────────────────────────────────────────

function M.fireEvent(event, ...)
    for _, frame in ipairs(M.frames) do
        if frame.__events[event] and frame.__scripts.OnEvent then
            frame.__scripts.OnEvent(frame, event, ...)
        end
    end
end

return M
