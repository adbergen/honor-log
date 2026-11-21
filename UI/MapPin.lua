-- HonorLog MapPin
-- Takes the player to a place: opens the world map on the right zone, marks the exact spot
-- with HonorLog's own pulsing pin, and shows a small arrow with the name and the distance.
-- Works for any place (a vendor today, a kill location later), not only vendors.
--
-- Why not the game's user waypoint: it is unreliable on the Forever client.
-- C_Map.OpenWorldMap is flagged HasRestrictions in the API documentation, so the map is
-- opened with ShowUIPanel(WorldMapFrame) and WorldMapFrame:SetMapID instead.
-- The map frame is only post-hooked (OnShow script, OnMapChanged); no Blizzard function is
-- replaced and no secure or protected frame is touched. Fields put on Blizzard frames start
-- with "honorLog".
--
-- Loaded after Data.lua and Core.lua (it adds methods to HonorLog) and after UI/Theme.lua.

local _, HonorLog = ...
local Util = HonorLog.Util
local L = HonorLog.L
local call, isSecret = Util.call, Util.isSecret

local MapPin = {}
HonorLog.MapPin = MapPin

local ARRIVAL_YARDS = 8
local ARROW_TICK = 0.1
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FLAT = "Interface\\Buttons\\WHITE8x8"
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local ARROW_TEXTURE = "Interface\\Minimap\\ROTATING-MINIMAPARROW"
local PIN_SIZE = 28

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local pins = {}          -- key -> { key, map, x, y, name, detail, reason, icon, npc, kind, button }
local spareButtons = {}  -- released pin buttons, reused
local targetKey = nil    -- the pin the arrow points at
local jumpKey = nil      -- a pin whose map the world map should switch to the next time it opens
local hooked = false
local merchantFrame = nil
local arrow = nil

-- What the last arrow update decided; the test reads it.
MapPin.arrowInfo = { state = "none" }

local function gold()
    local t = HonorLog.Theme and HonorLog.Theme.neutral
    return t and t[1] or 1, t and t[2] or 0.85, t and t[3] or 0.25
end

local function inCombat()
    return InCombatLockdown and InCombatLockdown() == true
end

-- The localized name of a map, or nil.
function MapPin.MapName(map)
    if not (C_Map and map) then return nil end
    local info = call(C_Map.GetMapInfo, map)
    if type(info) ~= "table" or isSecret(info) then return nil end
    local name = Util.str(info.name)
    return name ~= "" and name or nil
end

local function PlaceKey(place)
    if place.npc then return place.npc end
    return string.format("%s:%s:%s", tostring(place.map), tostring(place.x), tostring(place.y))
end

--------------------------------------------------------------------------------
-- Opening the world map
--------------------------------------------------------------------------------

local function MapFrame()
    local wm = WorldMapFrame
    if type(wm) == "table" and not isSecret(wm) then return wm end
    return nil
end

local function SetShownMap(map)
    local wm = MapFrame()
    if wm and map then call(wm.SetMapID, wm, map) end
end

-- Shows the map on `map`, out of combat only. `stillWanted` (optional) is asked before the
-- repeats, so a pin removed in the meantime is left alone.
function MapPin:OpenMap(map, stillWanted)
    if inCombat() then return false end
    local wm = MapFrame()
    if not wm then return false end
    if not call(wm.IsShown, wm) then
        call(ShowUIPanel, wm)
        if not call(wm.IsShown, wm) then call(wm.Show, wm) end
    end
    MapPin:Hook()
    local function apply()
        if stillWanted and not stillWanted() then return end
        SetShownMap(map)
        MapPin:Refresh()
    end
    apply()
    -- The client sometimes ignores the first call while the frame is opening.
    C_Timer.After(0.1, apply)
    C_Timer.After(0.5, apply)
    return true
end

--------------------------------------------------------------------------------
-- The pin on the map
--------------------------------------------------------------------------------

local function CanvasScale(wm, canvas)
    local s = Util.num(call(wm.GetCanvasScale, wm))
    if not s then s = Util.num(call(canvas.GetScale, canvas)) end
    if not s or s <= 0 then return 1 end
    return s
end

-- The pin's position on the displayed map as fractions 0..1, or nil when it is not on that map.
local function ProjectOnto(pin, shownMap)
    if shownMap == pin.map then return pin.x / 100, pin.y / 100 end
    if not (C_Map and C_Map.GetMapRectOnMap) then return nil end
    local minX, maxX, minY, maxY = call(C_Map.GetMapRectOnMap, pin.map, shownMap)
    minX, maxX, minY, maxY = Util.num(minX), Util.num(maxX), Util.num(minY), Util.num(maxY)
    if not (minX and maxX and minY and maxY) then return nil end
    return minX + pin.x / 100 * (maxX - minX), minY + pin.y / 100 * (maxY - minY)
end

local function MaskedTexture(button, layer, sublevel, size)
    local tex = button:CreateTexture(nil, layer, nil, sublevel)
    tex:SetSize(size, size)
    tex:SetPoint("CENTER")
    local mask = button:CreateMaskTexture()
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
    return tex
end

local function ShowPinTooltip(button)
    local pin = button.honorLogPin
    if not pin then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:AddLine(pin.name, 1, 1, 1)
    if pin.detail then GameTooltip:AddLine(pin.detail, 1, 0.82, 0) end
    if pin.reason then GameTooltip:AddLine(string.format(L["For: %s"], pin.reason), 0.8, 0.8, 0.85) end
    GameTooltip:AddLine(L["Right-click to remove"], 0.6, 0.6, 0.65)
    GameTooltip:Show()
end

local function CreatePinButton(canvas)
    local r, g, b = gold()
    local button = CreateFrame("Button", nil, canvas)
    button:SetSize(PIN_SIZE, PIN_SIZE)
    button:SetFrameLevel((Util.num(call(canvas.GetFrameLevel, canvas)) or 0) + 2000)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- A soft ring that ripples outward in a loop.
    local ripple = MaskedTexture(button, "BACKGROUND", 0, PIN_SIZE)
    ripple:SetTexture(FLAT)
    ripple:SetVertexColor(r, g, b, 0.7)
    local group = ripple:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    local grow = group:CreateAnimation("Scale")
    grow:SetScaleFrom(1, 1)
    grow:SetScaleTo(2.1, 2.1)
    grow:SetDuration(1.6)
    grow:SetOrder(1)
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.7)
    fade:SetToAlpha(0)
    fade:SetDuration(1.6)
    fade:SetOrder(1)
    button.honorLogPulse = group

    -- The gold ring, the dark disc and the icon, all round.
    local ring = MaskedTexture(button, "BACKGROUND", 1, PIN_SIZE)
    ring:SetTexture(FLAT)
    ring:SetVertexColor(r, g, b, 1)
    local disc = MaskedTexture(button, "ARTWORK", 0, PIN_SIZE - 5)
    disc:SetTexture(FLAT)
    disc:SetVertexColor(0.05, 0.04, 0.03, 0.95)
    local icon = MaskedTexture(button, "ARTWORK", 1, PIN_SIZE - 9)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.honorLogIcon = icon

    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(button)
    hl:SetTexture(FLAT)
    hl:SetVertexColor(1, 1, 1, 0.12)

    button:SetScript("OnShow", function(self) if self.honorLogPulse then self.honorLogPulse:Play() end end)
    button:SetScript("OnHide", function(self) if self.honorLogPulse then self.honorLogPulse:Stop() end end)
    button:SetScript("OnEnter", ShowPinTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", function(self, mouseButton)
        local pin = self.honorLogPin
        if not pin then return end
        if mouseButton == "RightButton" then
            HonorLog:ClearMapPins(pin.key)
        else
            SetShownMap(pin.map)
            MapPin:Refresh()
        end
    end)
    return button
end

local function ReleaseButton(pin)
    local button = pin.button
    if not button then return end
    button.honorLogPin = nil
    button:Hide()
    spareButtons[#spareButtons + 1] = button
    pin.button = nil
end

-- Draws every pin on the world map: at its spot on the pin's own map, projected onto an
-- ancestor map, hidden on any other. Safe to call at any time; does nothing before the map exists.
function MapPin:Refresh()
    local wm = MapFrame()
    if not wm then return end
    local canvas = call(wm.GetCanvas, wm)
    if type(canvas) ~= "table" or isSecret(canvas) then return end
    local shownMap = Util.num(call(wm.GetMapID, wm))
    local scale = CanvasScale(wm, canvas)
    local width, height = Util.num(call(canvas.GetWidth, canvas)), Util.num(call(canvas.GetHeight, canvas))

    for _, pin in pairs(pins) do
        local fx, fy
        if shownMap and width and height then fx, fy = ProjectOnto(pin, shownMap) end
        if fx and fy then
            if not pin.button then
                pin.button = table.remove(spareButtons) or CreatePinButton(canvas)
                pin.button:SetParent(canvas)
            end
            local button = pin.button
            button.honorLogPin = pin
            button.honorLogIcon:SetTexture(pin.icon or DEFAULT_ICON)
            -- Constant apparent size: undo the canvas zoom, and give the offset in the pin's own scale.
            button:SetScale(1 / scale)
            button:ClearAllPoints()
            button:SetPoint("CENTER", canvas, "TOPLEFT", fx * width * scale, -fy * height * scale)
            button:Show()
        elseif pin.button then
            pin.button:Hide()
        end
    end
end

-- Post-hooks only: nothing of Blizzard's is replaced.
function MapPin:Hook()
    if hooked then return end
    local wm = MapFrame()
    if not wm then return end
    hooked = true
    call(wm.HookScript, wm, "OnShow", function()
        if jumpKey then
            local pin = pins[jumpKey]
            jumpKey = nil
            if pin then SetShownMap(pin.map) end
        end
        MapPin:Refresh()
    end)
    if type(wm.OnMapChanged) == "function" then
        call(hooksecurefunc, wm, "OnMapChanged", function() MapPin:Refresh() end)
    end
end

--------------------------------------------------------------------------------
-- The arrow
--------------------------------------------------------------------------------

local function SaveArrowPoint()
    if not (arrow and HonorLog.db and HonorLog.db.settings) then return end
    local point, _, relPoint, x, y = arrow:GetPoint()
    HonorLog.db.settings.mapArrowPoint = { point, relPoint, x, y }
end

local function SetArrowVisible(visible)
    arrow:SetAlpha(visible and 1 or 0)
    arrow:EnableMouse(visible)
end

local function StopArrow()
    targetKey = nil
    MapPin.arrowInfo = { state = "none" }
    if arrow then
        arrow:SetScript("OnUpdate", nil)
        arrow:Hide()
    end
end

local function JumpToPin(pin)
    if inCombat() then
        jumpKey = pin.key
        MapPin:SayCombat()
        return
    end
    MapPin:OpenMap(pin.map, function() return pins[pin.key] == pin end)
end

local function CreateArrow()
    local r, g, b = gold()
    local frame = CreateFrame("Button", nil, UIParent)
    frame:SetSize(200, 46)
    local saved = HonorLog.db and HonorLog.db.settings and HonorLog.db.settings.mapArrowPoint
    if type(saved) == "table" and saved[1] then
        frame:SetPoint(saved[1], UIParent, saved[2] or saved[1], saved[3] or 0, saved[4] or 0)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetTexture(FLAT)
    bg:SetVertexColor(0.05, 0.04, 0.03, 0.78)
    local edge = frame:CreateTexture(nil, "BORDER")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetPoint("BOTTOMRIGHT")
    edge:SetHeight(1)
    edge:SetTexture(FLAT)
    edge:SetVertexColor(r, g, b, 0.9)

    frame.honorLogTexture = frame:CreateTexture(nil, "ARTWORK")
    frame.honorLogTexture:SetSize(30, 30)
    frame.honorLogTexture:SetPoint("LEFT", 8, 0)
    frame.honorLogTexture:SetTexture(ARROW_TEXTURE)
    frame.honorLogTexture:SetVertexColor(r, g, b, 1)

    frame.honorLogName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.honorLogName:SetPoint("TOPLEFT", 46, -8)
    frame.honorLogName:SetPoint("RIGHT", -8, 0)
    frame.honorLogName:SetJustifyH("LEFT")
    frame.honorLogDistance = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.honorLogDistance:SetPoint("BOTTOMLEFT", 46, 8)
    frame.honorLogDistance:SetJustifyH("LEFT")

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveArrowPoint()
    end)
    frame:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            StopArrow()
        else
            local pin = targetKey and pins[targetKey]
            if pin then JumpToPin(pin) end
        end
    end)
    return frame
end

-- The player's and the target's world positions, or nil for a tick that cannot read them.
-- UnitPosition answers (north-south, east-west, height, instance); the first two are swapped
-- against the vector C_Map gives, so they are named by the C_Map convention here.
local function PlayerWorldPosition()
    local a, b, _, instance = call(UnitPosition, "player")
    a, b, instance = Util.num(a), Util.num(b), Util.num(instance)
    if not (a and b) then return nil end
    return b, a, instance
end

local function TargetWorldPosition(pin)
    if pin.world then return pin.world[1], pin.world[2], pin.world[3] end
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local point = call(CreateVector2D, pin.x / 100, pin.y / 100)
    if not point then return nil end
    local instance, vec = call(C_Map.GetWorldPosFromMapPos, pin.map, point)
    instance = Util.num(instance)
    if not instance or type(vec) ~= "table" or isSecret(vec) then return nil end
    local x, y
    if type(vec.GetXY) == "function" then x, y = call(vec.GetXY, vec) else x, y = vec.x, vec.y end
    x, y = Util.num(x), Util.num(y)
    if not (x and y) then return nil end
    pin.world = { x, y, instance }
    return x, y, instance
end

-- One arrow tick: where the target lies, what the arrow shows. Never raises.
function MapPin:UpdateArrow()
    local pin = targetKey and pins[targetKey]
    if not pin or not arrow then
        StopArrow()
        return
    end
    local info = { state = "ready", name = pin.name }
    MapPin.arrowInfo = info
    arrow.honorLogName:SetText(pin.name)

    if call(IsInInstance) == true then
        -- The client reports no position inside instances and battlegrounds; the arrow waits.
        info.state = "instance"
        SetArrowVisible(false)
        return
    end
    SetArrowVisible(true)

    local px, py, pInstance = PlayerWorldPosition()
    local tx, ty, tInstance = TargetWorldPosition(pin)
    if not (px and tx) then
        info.state = "unknown"
        arrow.honorLogTexture:Hide()
        arrow.honorLogDistance:SetText("")
        return
    end
    if pInstance and tInstance and pInstance ~= tInstance then
        info.state = "far"
        arrow.honorLogTexture:Hide()
        local text = string.format(L["In %s"], MapPin.MapName(pin.map) or pin.name)
        info.text = text
        arrow.honorLogDistance:SetText(text)
        return
    end

    local dx, dy = tx - px, ty - py
    local yards = math.sqrt(dx * dx + dy * dy)
    info.distance = yards
    if yards <= ARRIVAL_YARDS then
        info.state = "arrived"
        StopArrow()
        MapPin.arrowInfo = info
        return
    end
    info.text = string.format(L["%d yds"], math.floor(yards + 0.5))
    arrow.honorLogDistance:SetText(info.text)

    local facing = Util.num(call(GetPlayerFacing))
    if not facing then
        info.state = "no-facing"
        arrow.honorLogTexture:Hide()
        return
    end
    -- x grows to the north and y to the west; the facing is counterclockwise from north.
    local rotation = atan2(dy, dx) - facing
    info.rotation = rotation
    arrow.honorLogTexture:Show()
    arrow.honorLogTexture:SetRotation(rotation)
end

local function StartArrow(key)
    targetKey = key
    if not arrow then arrow = CreateArrow() end
    arrow:Show()
    local elapsed = 0
    arrow:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < ARROW_TICK then return end
        elapsed = 0
        MapPin:UpdateArrow()
    end)
    MapPin:UpdateArrow()
end

--------------------------------------------------------------------------------
-- Vendor window opened: the job is done
--------------------------------------------------------------------------------

local function OnMerchantShow()
    if not next(pins) then return end
    local npc
    if HonorLog.ReadVendorLocation then npc = HonorLog:ReadVendorLocation().npc end
    local name = Util.str(call(UnitName, "npc"))
    local done = {}
    for key, pin in pairs(pins) do
        if pin.kind == "vendor" then
            local same
            if npc and pin.npc then same = npc == pin.npc else same = name ~= nil and name == pin.name end
            if same then done[#done + 1] = key end
        end
    end
    for _, key in ipairs(done) do HonorLog:ClearMapPins(key) end
end

local function WatchMerchant()
    if merchantFrame then return end
    merchantFrame = CreateFrame("Frame")
    if pcall(merchantFrame.RegisterEvent, merchantFrame, "MERCHANT_SHOW") then
        merchantFrame:SetScript("OnEvent", OnMerchantShow)
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function MapPin:SayCombat()
    local key = GetBindingKey and Util.str(call(GetBindingKey, "TOGGLEWORLDMAP")) or nil
    HonorLog:Say(string.format(L["The map can't open during combat. Press %s to see the marked spot."], key or "M"))
end

-- place = { map, x, y (percent 0-100), name, detail, reason, icon, npc, kind = "vendor" | "place" }
-- Returns true when a pin was placed.
function HonorLog:ShowPlaceOnMap(place)
    if type(place) ~= "table" then return false end
    local map, x, y = Util.num(place.map), Util.num(place.x), Util.num(place.y)
    local name = Util.str(place.name)
    if not (map and x and y and name) then return false end

    local key = PlaceKey(place)
    local pin = pins[key]
    if not pin then
        pin = { key = key }
        pins[key] = pin
    end
    pin.map, pin.x, pin.y, pin.name = map, x, y, name
    pin.detail, pin.reason, pin.icon = place.detail, place.reason, place.icon
    pin.npc, pin.kind = place.npc, place.kind or "place"
    pin.world = nil

    WatchMerchant()
    MapPin:Hook()
    StartArrow(key)

    if inCombat() then
        jumpKey = key
        MapPin:SayCombat()
    else
        MapPin:OpenMap(map, function() return pins[key] == pin end)
        local mapName = MapPin.MapName(map)
        self:Say(string.format(L["Marked %s on the map."], mapName and (name .. " - " .. mapName) or name))
    end
    MapPin:Refresh()
    return true
end

-- Removes one pin (by key) or all of them, and the arrow when its target went away.
-- Returns how many pins were removed.
function HonorLog:ClearMapPins(key)
    local removed = 0
    local keys = {}
    if key ~= nil then
        if pins[key] then keys[1] = key end
    else
        for k in pairs(pins) do keys[#keys + 1] = k end
    end
    for _, k in ipairs(keys) do
        ReleaseButton(pins[k])
        pins[k] = nil
        removed = removed + 1
        if jumpKey == k then jumpKey = nil end
    end
    if targetKey and not pins[targetKey] then StopArrow() end
    return removed
end

-- For the test: how many pins exist.
function MapPin:Count()
    local n = 0
    for _ in pairs(pins) do n = n + 1 end
    return n
end

function MapPin:GetPin(key) return pins[key] end
function MapPin:GetArrow() return arrow end
function MapPin:GetTarget() return targetKey end
function MapPin:GetJumpKey() return jumpKey end
