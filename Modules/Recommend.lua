-- HonorLog Recommend
-- Recommended gear goals: for each slot, the best PvP reward the character's class and spec can use, offered
-- when its item level beats what the character wears. The engine and its cached read (GetCached, at the end; its only frame listens for the events that change an
-- answer), nothing per frame, and nothing
-- is ever added to the goal list or reordered here. The player clicks (the screens call AddGoal).
--
-- The rules:
--   * Candidates: the generated gear database (HonorLog:GetPickerItems: the player's side, stocked, not owned,
--     not already a goal), for the player's class: its own set pieces and the neutral items. Neutral armour must
--     be the heaviest type the class wears at its level (HonorLog.ArmorLevels, from SkillRaceClassInfo); a weapon
--     the class cannot use is dropped (Data.lua ClassUsesWeapon).
--   * Role (healer, physical, caster): a choice the player made (per character: db.char.recommendRole), else the
--     client's spec (C_SpecializationInfo), else unknown. Unknown offers every line of the class. A class with
--     one set line offers its set pieces whatever the role. An item whose role the class has no line for (a
--     physical ring for a mage) is never offered; an item with no role fits every role.
--   * Comparison: the worn item per slot (GetInventoryItemID) and its item level
--     (C_Item.GetDetailedItemLevelInfo, the database level as a fallback for a worn reward). Two-place slots
--     (finger, trinket) compare with the weaker of the two; a one-hand weapon with the weaker of main and
--     off hand when both hold weapons; a two-hander with the main hand only, said in the reason. An empty slot
--     is the biggest gain. A slot the client will not report (nil, an error, a secret) is skipped and named in
--     the second result, never guessed.
--   * A blue piece and its Seal upgrade are one path: the blue piece is recommended first (ranked by the item
--     level the path reaches); once it is worn or owned, the epic.
--   * Level: a reward whose required level is above the character's is never offered (with the level unknown,
--     nothing is filtered by level). A blue piece reaches its Seal epic only when the epic's required level is met.
--   * One recommendation per slot (and per role line while the role is unknown): the highest item level; ties go
--     to what can be bought now, then the soonest date. When that best is not buyable now, the best reward of the
--     slot that is buyable now and still an upgrade comes beside it (now = true), so there is always something to buy.
--   * Nothing worn at all (no place reports an item) means the client is not telling: no recommendations.
--   * Priority: buyable now first, biggest gain first; then by the date it becomes buyable, soonest first, then
--     by gain. The date and the status sentence come from the same progress object a goal has
--     (HonorLog:BuildGoalProgress and HonorLog:GoalReadyText); there is no second forecast.
--
-- Client functions used (Forever API documentation, build 1.60.1.71037; none flagged HasRestrictions, none
-- documented secret-returning, all SecretArguments = "AllowedWhenUntainted"): C_SpecializationInfo.
-- GetSpecialization and GetSpecializationInfo, C_Item.GetDetailedItemLevelInfo and GetItemInventoryTypeByID,
-- UnitClass, UnitLevel, UnitFactionGroup, UnitSex, GetInventoryItemID (the legacy global, already used by
-- Data.lua). Every answer goes through Util.call / Util.num / Util.str; an error, a nil or a secret means
-- "unknown".

local _, HonorLog = ...
HonorLog = HonorLog or {}

local Recommend = {}
HonorLog.Recommend = Recommend

local Util = HonorLog.Util
local L = HonorLog.L
local num, str, call = Util.num, Util.str, Util.call
local isSecret = Util.isSecret

local ROLES = { "healer", "physical", "caster" }
local ROLE_OK = { healer = true, physical = true, caster = true }

-- Database slot -> the inventory slots a worn item sits in.
local PLACES = {
    HEAD = { 1 }, NECK = { 2 }, SHOULDER = { 3 }, BACK = { 15 }, CHEST = { 5 }, WRIST = { 9 }, HANDS = { 10 },
    WAIST = { 6 }, LEGS = { 7 }, FEET = { 8 }, FINGER = { 11, 12 }, TRINKET = { 13, 14 },
    MAIN_HAND = { 16 }, OFF_HAND = { 17 }, TWO_HAND = { 16 }, RANGED = { 18 },
}
local MAIN_HAND, OFF_HAND, RANGED_PLACE = 16, 17, 18
local WEAPON_SLOTS = { MAIN_HAND = true, OFF_HAND = true, TWO_HAND = true, RANGED = true }
-- Inventory types: 17 is a two-hander; 13, 21 and 22 are one-hand, main-hand and off-hand weapons.
local TWO_HAND_TYPE = 17
local WEAPON_TYPES = { [13] = true, [21] = true, [22] = true }
-- Primary stat indices (UnitStat order): 1 Strength, 2 Agility, 4 Intellect.
local STAT_STRENGTH, STAT_AGILITY, STAT_INTELLECT = 1, 2, 4
local ARMOR_ORDER = { "PLATE", "MAIL", "LEATHER", "CLOTH" }

-- A slot is named in the second result by its database key, in this order.
local SLOT_ORDER = {}
for i, slot in ipairs({ "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET",
    "FINGER", "TRINKET", "MAIN_HAND", "OFF_HAND", "TWO_HAND", "RANGED" }) do SLOT_ORDER[slot] = i end

--------------------------------------------------------------------------------
-- The role
--------------------------------------------------------------------------------

local function charStore()
    local db = HonorLog.db
    return type(db) == "table" and type(db.char) == "table" and db.char or nil
end

-- The role the player chose on this character: "healer", "physical" or "caster", or nil.
function Recommend:GetChosenRole()
    local store = charStore()
    local role = store and store.recommendRole
    return ROLE_OK[role] and role or nil
end

-- Save the player's choice, or clear it with nil. Returns false for anything else. Screens refresh the way
-- the goal functions tell them to.
function Recommend:SetRole(role)
    local store = charStore()
    if not store then return false end
    if role ~= nil and not ROLE_OK[role] then return false end
    if store.recommendRole == role then return true end
    store.recommendRole = role
    Recommend:Invalidate()
    if HonorLog.OnDataUpdated then HonorLog:OnDataUpdated() end
    return true
end

-- The role of the client's spec, or nil when it cannot be told.
function Recommend:GetSpecRole()
    local api = C_SpecializationInfo
    if type(api) ~= "table" then return nil end
    local index = num(call(api.GetSpecialization))
    if not index or index < 1 then return nil end
    local sex = num(call(UnitSex, "player"))
    local _, _, _, _, role, stat = call(api.GetSpecializationInfo, index, false, false, nil, sex)
    role, stat = str(role), num(stat)
    if role == "HEALER" then return "healer" end
    if role == "DAMAGER" or role == "TANK" then
        if stat == STAT_STRENGTH or stat == STAT_AGILITY then return "physical" end
        if stat == STAT_INTELLECT then return "caster" end
    end
    return nil
end

-- The roles a class has set lines for, as an array in the order healer, physical, caster.
local classRoleCache = {}
function Recommend:GetClassRoles(class)
    if type(class) ~= "string" then return {} end
    local cached = classRoleCache[class]
    if cached then return cached end
    local seen = {}
    local setRoles = HonorLog.SetRoles or {}
    for _, data in pairs(HonorLog.GearDB or {}) do
        if data.class == class and data.set and ROLE_OK[setRoles[data.set]] then seen[setRoles[data.set]] = true end
    end
    local out = {}
    for _, role in ipairs(ROLES) do
        if seen[role] then out[#out + 1] = role end
    end
    classRoleCache[class] = out
    return out
end

-- The number of set lines a class has (a line is one set id on one side and tier); a class with one line
-- offers its set pieces whatever the role.
local lineCache = {}
local function lineCount(class)
    if lineCache[class] then return lineCache[class] end
    local lines = {}
    for _, data in pairs(HonorLog.GearDB or {}) do
        if data.class == class and data.set and data.faction == "Horde" and data.quality == 3 then
            lines[data.set] = true
        end
    end
    local n = 0
    for _ in pairs(lines) do n = n + 1 end
    lineCache[class] = n
    return n
end

-- The role in use and where it came from: role, "choice" | "spec" | "unknown". A role the class has no line
-- for is not used.
function Recommend:GetRole(class)
    local roles = self:GetClassRoles(class)
    local has = {}
    for _, role in ipairs(roles) do has[role] = true end
    local chosen = self:GetChosenRole()
    if chosen and has[chosen] then return chosen, "choice" end
    local spec = self:GetSpecRole()
    if spec and has[spec] then return spec, "spec" end
    return nil, "unknown"
end

--------------------------------------------------------------------------------
-- Worn gear
--------------------------------------------------------------------------------

-- What sits in one inventory slot: { kind = "empty" } or { kind = "worn", id, level, name }, or nil when
-- the client will not say (or the level cannot be told).
local function readPlace(place)
    if type(GetInventoryItemID) ~= "function" then return nil end
    local ok, id = pcall(GetInventoryItemID, "player", place)
    if not ok or isSecret(id) then return nil end
    if id == nil then return { kind = "empty" } end
    id = num(id)
    if not id or id <= 0 then return nil end
    local level
    if C_Item then level = num((call(C_Item.GetDetailedItemLevelInfo, id))) end
    if not level or level <= 0 then
        local base = HonorLog.GearDB and HonorLog.GearDB[id]
        level = base and base.ilvl or nil
    end
    if not level then return nil end
    local name = HonorLog.GetGearName and HonorLog:GetGearName(id) or nil
    return { kind = "worn", id = id, level = level, name = str(name) }
end

-- Whether any inventory place reports an item (a number, not a secret).
local function anyWorn()
    if type(GetInventoryItemID) ~= "function" then return false end
    for place = 1, 18 do
        if place ~= 4 then
            local ok, id = pcall(GetInventoryItemID, "player", place)
            if ok and not isSecret(id) and num(id) and id > 0 then return true end
        end
    end
    return false
end

local function inventoryType(id)
    return C_Item and num((call(C_Item.GetItemInventoryTypeByID, id))) or nil
end

local function isTwoHander(id)
    local base = HonorLog.GearDB and HonorLog.GearDB[id]
    if base and base.slot == "TWO_HAND" then return true end
    return inventoryType(id) == TWO_HAND_TYPE
end

local function isWeapon(id)
    local base = HonorLog.GearDB and HonorLog.GearDB[id]
    if base and base.slot == "MAIN_HAND" then return true end
    return WEAPON_TYPES[inventoryType(id) or 0] == true
end

-- What a reward for `slot` is compared with. Returns:
--   a worn record ({ kind, id, level, name, mainHandOnly }) or { kind = "empty" } when there is something to compare;
--   false when the slot is not a place for this reward (an off hand while a two-hander is worn);
--   nil when the client would not report a place (skipped).
local function wornFor(slot)
    local places = PLACES[slot]
    if not places then return nil end
    if slot == "MAIN_HAND" then
        local main = readPlace(MAIN_HAND)
        if not main then return nil end
        if main.kind == "empty" then return main end
        if isTwoHander(main.id) then
            main.mainHandOnly = true
            return main
        end
        local off = readPlace(OFF_HAND)
        if off and off.kind == "worn" and isWeapon(off.id) and off.level < main.level then return off end
        return main
    elseif slot == "TWO_HAND" then
        local main = readPlace(MAIN_HAND)
        if not main then return nil end
        if main.kind == "worn" then
            local off = readPlace(OFF_HAND)
            if off and off.kind == "worn" then main.mainHandOnly = true end
        end
        return main
    elseif slot == "OFF_HAND" then
        local main = readPlace(MAIN_HAND)
        if not main then return nil end
        if main.kind == "worn" and isTwoHander(main.id) then return false end
        return readPlace(OFF_HAND)
    end
    -- One or two places: an empty one is the biggest gain, else the weaker worn item.
    local weakest, empty
    for _, place in ipairs(places) do
        local read = readPlace(place)
        if not read then return nil end
        if read.kind == "empty" then
            empty = read
        elseif not weakest or read.level < weakest.level then
            weakest = read
        end
    end
    return empty or weakest
end

--------------------------------------------------------------------------------
-- The ranking
--------------------------------------------------------------------------------

-- blue piece id -> its Seal-upgrade epic id, from the generated parts.
local blueToEpic
local function upgradeOf(blueID)
    if not blueToEpic then
        blueToEpic = {}
        for id, data in pairs(HonorLog.GearDB or {}) do
            if data.source == "UPGRADE" and type(data.parts) == "table" and data.parts[1] then
                blueToEpic[data.parts[1]] = id
            end
        end
    end
    return blueToEpic[blueID]
end

local function owned(itemID)
    local okBags, inBags = pcall(HonorLog.IsItemInInventory, HonorLog, itemID)
    if okBags and inBags == true then return true end
    local okCount, count = pcall(HonorLog.Compat.GetItemCount, itemID, true)
    count = okCount and num(count) or nil
    return count ~= nil and count > 0
end

-- The heaviest armour type `class` wears at `level` (HonorLog.ArmorLevels), or nil.
local function heaviestArmor(class, level)
    local table_ = HonorLog.ArmorLevels and HonorLog.ArmorLevels[class]
    if not table_ or not level then return nil end
    for _, kind in ipairs(ARMOR_ORDER) do
        if table_[kind] and table_[kind] <= level then return kind end
    end
    return nil
end

-- The heaviest armour type `class` wears at `level` ("PLATE", "MAIL", "LEATHER" or "CLOTH"), or nil when
-- either is unknown.
function Recommend:GetArmorType(class, level)
    return heaviestArmor(class, num(level))
end

local function plain(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function reasonFor(gain, worn, note, viaSeal)
    local text
    if not worn or worn.kind == "empty" then
        text = L["Empty slot"]
    elseif worn.name then
        text = string.format(gain == 1 and L["+%d item level over %s"] or L["+%d item levels over %s"], gain, worn.name)
    else
        text = string.format(gain == 1 and L["+%d item level over what you wear"] or L["+%d item levels over what you wear"], gain)
    end
    -- the first part has no full stop of its own (it also stands alone in a row), so the joins bring one
    if viaSeal then text = text .. ". " .. L["Buy the blue piece first, then upgrade it with a Seal."] end
    if note then text = text .. (viaSeal and " " or ". ") .. L["Compared with your main hand only."] end
    return text
end

-- GetRecommendedGoals(limit): the ranked recommendations, best first, at most `limit` (all when nil).
-- Returns list, info.
--   list[i] = {
--     itemID, name, slot (database slot key), source ("HONOR", "RANK", "REP" or "UPGRADE"), role (or nil),
--     ilvl (the item level the player reaches: for a blue piece, its Seal epic's), itemIlvl (this item's own),
--     gain (item levels over what is worn, nil when the slot is empty), empty (true when the slot is empty),
--     worn = { itemID, name, ilvl } or nil, reason (a sentence), buyable (true when it can be bought now),
--     status (plain sentence for when it becomes buyable, or nil), statusRich (the same with colour codes),
--     readyDate (time, or nil), progress (the goal progress object), step ("blue" first, "seal" for the
--     upgrade, or nil), upgradeID (the epic that follows a blue piece, or nil), mainHandOnly (true when a two-hander
--     was compared with the main hand only)
--   }
--   (also on an entry: now = true on the buyable-today alternative that sits beside a slot's best when the best is
--   not buyable now, alternative = that alternative's item id on the best, alternativeTo = the best's item id on
--   the alternative.)
--   info = { progressBuilt (goal progress objects this call built), inventoryUnknown (true when no place reported
--     an item and nothing was recommended), class, level, role, roleSource ("choice", "spec" or "unknown"), classRoles = { "healer", ... },
--     skipped = { "HEAD", ... } (slots the client would not report), levelUnknown (true when armour
--     could not be judged) }
function Recommend:GetRecommendedGoals(limit)
    local info = { role = nil, roleSource = "unknown", classRoles = {}, skipped = {} }
    local class = str((select(2, call(UnitClass, "player"))))
    local level = num(call(UnitLevel, "player"))
    info.class, info.level = class, level
    if not class or class == "" then return {}, info end
    info.classRoles = self:GetClassRoles(class)
    info.role, info.roleSource = self:GetRole(class)
    info.levelUnknown = level == nil
    local role, hasRoles = info.role, {}
    for _, r in ipairs(info.classRoles) do hasRoles[r] = true end
    local armor = heaviestArmor(class, level)
    local oneLine = lineCount(class) == 1
    local classUsesWeapon = HonorLog.ClassUsesWeapon

    -- Nothing worn at all: the client is not saying (a nil answer also means an empty slot), so what the
    -- character wears is unknown and nothing is recommended.
    if not anyWorn() then
        info.inventoryUnknown = true
        return {}, info
    end

    local skipped = {}
    local wornCache = {}
    local function worn(slot)
        local cached = wornCache[slot]
        if cached == nil then
            cached = wornFor(slot)
            if cached == nil then cached = "unknown" end
            wornCache[slot] = cached
        end
        return cached
    end

    -- Candidates, grouped: one best per slot (and per role line while the role is unknown).
    local groups, groupOrder = {}, {}
    for _, entry in ipairs(HonorLog:GetPickerItems({ hideOwned = true })) do
        local id, data = entry.itemID, entry.data
        local slot = data.slot
        local ok = PLACES[slot] ~= nil
        if ok and data.class and data.class ~= class then ok = false end
        if ok and not data.class and data.armor then ok = armor ~= nil and data.armor == armor end
        if ok and WEAPON_SLOTS[slot] and classUsesWeapon and not classUsesWeapon(class, id) then ok = false end
        if ok and data.role then
            if data.set then
                ok = oneLine or role == nil or data.role == role
            else
                ok = hasRoles[data.role] == true and (role == nil or data.role == role)
            end
        end
        if ok and level and (data.reqLevel or 0) > level then ok = false end
        local start, finish -- the item to offer, the item whose level it reaches
        if ok and data.source == "UPGRADE" and type(data.parts) == "table" and data.parts[1] then
            -- The epic: offered only once its blue piece is worn or owned.
            if owned(data.parts[1]) then start, finish = id, id else ok = false end
        elseif ok then
            local epicID = data.source == "HONOR" and upgradeOf(id) or nil
            local epic = epicID and HonorLog.GearDB[epicID] or nil
            if epic and not HonorLog:IsGoal(epicID) and not owned(epicID) then
                if level and (epic.reqLevel or 0) > level then
                    start, finish = id, id -- the Seal upgrade is out of reach: the blue piece stands on its own level
                else
                    start, finish = id, epicID
                end
            elseif epic then
                ok = false -- the epic is already a goal or owned: this blue piece is part of it
            else
                start, finish = id, id
            end
        end
        if ok then
            local w = worn(slot)
            if w == "unknown" then
                skipped[slot] = true
            elseif w ~= false then
                local reach = HonorLog.GearDB[finish].ilvl
                local gain, ownGain
                if w.kind == "worn" then
                    gain = reach - w.level
                    ownGain = data.ilvl - w.level
                    if gain <= 0 then ok = false end
                end
                if ok then
                    local key = slot
                    if role == nil then key = (data.role or "-") .. ":" .. slot end
                    local cand = {
                        itemID = start, finishID = finish, data = data, slot = slot, ilvl = reach, gain = gain,
                        upgradeNow = ownGain == nil or ownGain > 0, worn = w, role = data.role, key = key,
                    }
                    local group = groups[key]
                    if not group then
                        group = { best = reach, list = {} }
                        groups[key] = group
                        groupOrder[#groupOrder + 1] = key
                    end
                    if reach > group.best then group.best = reach end
                    group.list[#group.list + 1] = cand
                end
            end
        end
    end

    -- Progress for every candidate (one context for all), then the best of each group and, when the best
    -- cannot be bought now, the best that can.
    local okCtx, ctx = pcall(HonorLog.NewGoalContext, HonorLog)
    if not okCtx or type(ctx) ~= "table" then return {}, info end
    local picks, built = {}, 0
    local function better(a, b) -- a over b: higher level, then buyable, then sooner, then lower id
        if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
        if a.buyable ~= b.buyable then return a.buyable end
        local da, db = a.readyDate or math.huge, b.readyDate or math.huge
        if da ~= db then return da < db end
        return a.itemID < b.itemID
    end
    for _, key in ipairs(groupOrder) do
        local best, near
        for _, cand in ipairs(groups[key].list) do
            local okProgress, progress = pcall(HonorLog.BuildGoalProgress, HonorLog, cand.itemID, ctx, nil)
            built = built + 1
            cand.progress = okProgress and type(progress) == "table" and progress or nil
            cand.buyable = cand.progress ~= nil and cand.progress.isComplete == true
            cand.readyDate = cand.progress and num(cand.progress.readyDate) or nil
            if cand.progress then
                if not best or better(cand, best) then best = cand end
                if cand.buyable and cand.upgradeNow then
                    if not near or cand.ilvl > near.ilvl or (cand.ilvl == near.ilvl and cand.itemID < near.itemID) then near = cand end
                end
            end
        end
        if best then
            picks[#picks + 1] = best
            if not best.buyable and near then
                near.now, near.alternativeTo, best.alternative = true, best.itemID, near.itemID
                picks[#picks + 1] = near
            end
        end
    end
    info.progressBuilt = built

    table.sort(picks, function(a, b)
        if a.buyable ~= b.buyable then return a.buyable end
        local ga, gb = a.gain or math.huge, b.gain or math.huge
        if a.buyable then
            if ga ~= gb then return ga > gb end
        else
            local da, db = a.readyDate or math.huge, b.readyDate or math.huge
            if da ~= db then return da < db end
            if ga ~= gb then return ga > gb end
        end
        local sa, sb = SLOT_ORDER[a.slot] or 99, SLOT_ORDER[b.slot] or 99
        if sa ~= sb then return sa < sb end
        return a.itemID < b.itemID
    end)

    local out = {}
    local max = limit and math.min(limit, #picks) or #picks
    for i = 1, max do
        local c = picks[i]
        local upgrade = c.data.source == "UPGRADE"
        local viaSeal = c.finishID ~= c.itemID
        local ready
        if HonorLog.GoalReadyText and c.progress then
            local okText, text = pcall(HonorLog.GoalReadyText, HonorLog, c.progress)
            if okText and type(text) == "string" and text ~= "" then ready = text end
        end
        local wornInfo
        if c.worn and c.worn.kind == "worn" then
            wornInfo = { itemID = c.worn.id, name = c.worn.name, ilvl = c.worn.level }
        end
        out[i] = {
            itemID = c.itemID, name = c.progress.name or c.data.name, slot = c.slot, source = c.data.source,
            role = c.role, ilvl = c.ilvl, itemIlvl = c.data.ilvl, gain = c.gain, empty = c.worn.kind == "empty",
            worn = wornInfo, reason = reasonFor(c.gain, c.worn, c.worn.mainHandOnly, viaSeal),
            buyable = c.buyable, status = ready and plain(ready) or nil, statusRich = ready,
            readyDate = c.readyDate, progress = c.progress, step = viaSeal and "blue" or (upgrade and "seal" or nil),
            upgradeID = viaSeal and c.finishID or nil, mainHandOnly = c.worn.mainHandOnly == true,
            now = c.now == true, alternative = c.alternative, alternativeTo = c.alternativeTo,
        }
    end

    for slot in pairs(skipped) do info.skipped[#info.skipped + 1] = slot end
    table.sort(info.skipped, function(a, b) return (SLOT_ORDER[a] or 99) < (SLOT_ORDER[b] or 99) end)
    return out, info
end

--------------------------------------------------------------------------------
-- The cached read
--------------------------------------------------------------------------------

-- One GetRecommendedGoals call builds up to about 135 goal-progress objects, so no screen calls it on a
-- refresh: screens and the advice call GetCached, which computes lazily and keeps the answer until an input
-- changes. What throws it away (Invalidate): the data-updated notification (a goal added or removed, a game
-- recorded, the sort), SetRole, and the client's own events for a change of worn equipment, a level-up, a
-- change of spec, and (nothing redrawn for these two) a currency or bag change, which moves what can be
-- bought today. A failed or empty answer from the engine is not kept, so the next read asks again.
local cache

function Recommend:Invalidate() cache = nil end

-- GetCached(limit): list, info as GetRecommendedGoals returns them, the list cut to `limit` when given (a new
-- table; the entries are shared). Returns nil when the engine raises or answers with no list.
function Recommend:GetCached(limit)
    if not cache then
        local ok, list, info = pcall(self.GetRecommendedGoals, self)
        if not ok or type(list) ~= "table" or type(info) ~= "table" then return nil end
        cache = { list = list, info = info }
    end
    local list = cache.list
    limit = num(limit)
    if limit and limit < #list then
        local out = {}
        for i = 1, math.max(0, math.floor(limit)) do out[i] = list[i] end
        list = out
    end
    return list, cache.info
end

-- The screens redraw on a change the player can see; a window that is closed only remembers it.
local function redrawWindow()
    local window = HonorLog.Window
    if window and window.OnDataChanged then pcall(window.OnDataChanged, window) end
end

if type(HonorLog.OnDataUpdated) == "function" then
    -- registered before the window's own hook (this file loads first), so the window redraws on a fresh read
    hooksecurefunc(HonorLog, "OnDataUpdated", function() Recommend:Invalidate() end)
end

local REDRAW_EVENTS = {
    PLAYER_EQUIPMENT_CHANGED = true, PLAYER_LEVEL_UP = true, ACTIVE_TALENT_GROUP_CHANGED = true,
    PLAYER_SPECIALIZATION_CHANGED = true, ACTIVE_PLAYER_SPECIALIZATION_CHANGED = true,
}
local QUIET_EVENTS = { CURRENCY_DISPLAY_UPDATE = true, BAG_UPDATE_DELAYED = true }

local frame = CreateFrame("Frame", "HonorLogRecommendFrame")
frame:SetScript("OnEvent", function(_, event)
    Recommend:Invalidate()
    if REDRAW_EVENTS[event] then redrawWindow() end
end)
-- Every event is in the build's API documentation, none flagged HasRestrictions; a refused one is skipped.
for event in pairs(REDRAW_EVENTS) do pcall(frame.RegisterEvent, frame, event) end
for event in pairs(QUIET_EVENTS) do pcall(frame.RegisterEvent, frame, event) end
