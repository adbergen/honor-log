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
    CheckButton = true, EditBox = true, StatusBar = true,
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
function methods.SetWidth(self, w) self.__width = w; return self end
function methods.SetHeight(self, h) self.__height = h; return self end
function methods.SetSize(self, w, h) self.__width, self.__height = w, h; return self end
function methods.GetNumPoints() return 0 end
function methods.GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function methods.GetScale() return 1 end
function methods.GetEffectiveScale() return 1 end
function methods.GetCenter() return 400, 300 end
function methods.GetFrameLevel() return 0 end
function methods.GetVerticalScroll() return 0 end
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
function methods.Show(self) self.__shown = true; return self end
function methods.Hide(self) self.__shown = false; return self end
function methods.SetShown(self, b) self.__shown = b and true or false; return self end

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
function methods.GetStringHeight() return 12 end

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
function methods.CreateFontString(self) return newObject("FontString", self) end
function methods.CreateAnimationGroup(self) return newObject("AnimationGroup", self) end
function methods.CreateAnimation(self) return newObject("Animation", self) end
function methods.SetScrollChild(self, c) self.__scrollchild = c; return self end

-- ─── Globals ─────────────────────────────────────────────────────────

function CreateFrame(objType, name, parent)
    return newObject(objType or "Frame", parent, name)
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
}
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
    "BAG_UPDATE_DELAYED", "PVP_MATCH_ACTIVE", "PVP_MATCH_COMPLETE", "PLAYER_PVP_KILLS_CHANGED",
    "PLAYER_PVP_RANK_CHANGED", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "ADDON_RESTRICTION_STATE_CHANGED",
    "PARTY_KILL", "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "PLAYER_LEAVING_WORLD",
}) do M.knownEvents[e] = true end
-- Known to the client but flagged HasRestrictions in the docs.
M.restrictedEvents = { COMBAT_LOG_EVENT_UNFILTERED = true, COMBAT_LOG_EVENT = true }

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
C_MajorFactions = {
    GetMajorFactionProgressionInfo = function(id)
        if id == 2800 then
            return { renownLevel = M.rank.level, renownReputationEarned = M.rank.earned,
                     renownLevelThreshold = M.rank.threshold, currentWeekProgressiveMaxLevel = 5, weekNumber = 2 }
        end
    end,
    GetMajorFactionData = function(id) return { factionID = id, name = "PvP Rank Points" } end,
    GetRenownRewardsForLevel = function(id, level) return { { itemID = 1000 + level } } end,
}
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
C_SeasonInfo = {
    GetCurrentDisplaySeasonID = function() return 1 end,
    GetCurrentDisplaySeasonExpansion = function() return 0 end,
    GetTimeUntilCurrentPVPSeasonEnd = function() return 86400 * 30 end,
}
M.bagItems = { [20558] = 12, [20559] = 3 }
C_Item = {
    GetItemCount = function(id) return M.bagItems[id] or 0 end,
    GetItemInfo = function(id)
        return "Item " .. tostring(id), "|cff0070dd|Hitem:" .. tostring(id) .. "|h[Item " .. tostring(id) .. "]|h|r",
            3, 60, 55, "Armor", "Plate", 1, "INVTYPE_CHEST", 134400
    end,
}
C_Container = {
    GetContainerNumSlots = function() return 0 end,
    GetContainerItemID = function() return nil end,
    GetContainerItemInfo = function() return nil end,
}
C_MerchantFrame = { GetItemInfo = function() return nil end }
Enum = { AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 } }
C_RestrictedActions = {
    GetAddOnRestrictionState = function(t) return t == 3 and M.pvp.matchActive and 2 or 0 end,
    IsAddOnRestrictionActive = function(t) return t == 3 and M.pvp.matchActive end,
}

C_AddOns = {
    GetAddOnMetadata = function(_, key) return key == "Version" and "2.0.0-test" or "" end,
}

function GetInventoryItemID() return nil end
function UnitHonor() return 0 end
function UnitName(unit)
    if unit == nil or unit == "player" then return "Tester" end
    local u = M.units[unit]
    return u and u.name or nil
end
function UnitFactionGroup() return "Alliance", "Alliance" end
function UnitLevel() return 60 end
function UnitClass(unit)
    local u = unit and unit ~= "player" and M.units[unit]
    if u then return u.class, u.class, 1 end
    return "Warrior", "WARRIOR", 1
end
function UnitRace() return "Human", "Human" end
function UnitGUID() return "Player-1-1" end
function GetRealmName() return "TestRealm" end
function GetRealZoneText() return "Stormwind City" end
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
function GetMoney() return 123456 end
function GetTime() return M.now or os.clock() end
function PlaySound() end
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857 }
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function GetCursorPosition() return 0, 0 end
function SetCursor() end
function ResetCursor() end
function BreakUpLargeNumbers(n) return tostring(n) end
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
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText() end
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

-- ─── Test helpers ────────────────────────────────────────────────────

function M.fireEvent(event, ...)
    for _, frame in ipairs(M.frames) do
        if frame.__events[event] and frame.__scripts.OnEvent then
            frame.__scripts.OnEvent(frame, event, ...)
        end
    end
end

return M
