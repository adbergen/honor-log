-- HonorLog Window
-- The full window: a frame that looks like an extension of Blizzard's PvP tab, with one tab per registered
-- screen. Screens register themselves (UI/Screens/*.lua) with a create function; a screen's frame is
-- built the first time its tab is shown. The small frame in UI/MainFrame.lua stays the in-battleground tracker.
--
-- Nothing exists before first use: no frame, no ticker, no OnUpdate. While the window is hidden a data
-- change only marks it dirty; the next show refreshes. Loaded after Kit, before the screens.

local _, HonorLog = ...
HonorLog = HonorLog or {}

local Util = HonorLog.Util
local num, str, call = Util.num, Util.str, Util.call
local L = HonorLog.L
local Kit = HonorLog.Kit

local Window = {}
HonorLog.Window = Window

local FRAME_NAME = "HonorLogWindow"
local WIDTH, HEIGHT = 900, 540
local TICK_SECONDS = 30
Window.ICON = "Interface\\Icons\\Spell_Holy_ChampionsBond" -- the broker object's icon, used when it has none yet

Window.screens = {} -- { key, title, order, create }, in tab order
Window.frames = {}  -- key -> the screen's frame, built on first show
Window.dirty = false

local function settings() return HonorLog.db and HonorLog.db.settings end

local function report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
end

--------------------------------------------------------------------------------
-- Screens
--------------------------------------------------------------------------------

-- def = { key, title, order, create = function(parent) return frame end }; the frame has :Refresh().
function Window:RegisterScreen(def)
    if type(def) ~= "table" or not def.key or type(def.create) ~= "function" then return end
    for i, existing in ipairs(self.screens) do
        if existing.key == def.key then table.remove(self.screens, i) break end
    end
    def.order = def.order or 100
    local at = #self.screens + 1
    for i, existing in ipairs(self.screens) do
        if existing.order > def.order then at = i break end
    end
    table.insert(self.screens, at, def)
    if self.tabs then self.tabs:Add(def.key, def.title) end
end

function Window:GetScreen(key)
    for _, def in ipairs(self.screens) do
        if def.key == key then return def end
    end
end

-- Builds the screen's frame the first time, shows it and hides the others.
function Window:ShowScreen(key)
    local def = self:GetScreen(key)
    if not (def and self.frame) then return end
    local frame = self.frames[key]
    if not frame then
        local ok, made = pcall(def.create, self.frame.Content)
        if not ok then report(made) return end
        frame = made
        frame:SetAllPoints(self.frame.Content)
        self.frames[key] = frame
    end
    for k, other in pairs(self.frames) do
        if k ~= key then other:Hide() end
    end
    frame:Show()
    self.current = key
    local s = settings()
    if s then s.windowTab = key end
    if self.frame:IsShown() then self:RefreshCurrent() else self.dirty = true end
end

function Window:RefreshCurrent()
    local frame = self.current and self.frames[self.current]
    self.dirty = false
    if frame and frame.Refresh then
        local ok, err = pcall(frame.Refresh, frame)
        if not ok then report(err) end
    end
end

-- A data change: refresh now when shown, else only remember it.
function Window:OnDataChanged()
    if not self.frame then return end
    if self.frame:IsShown() then self:RefreshCurrent() else self.dirty = true end
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

function Window:UpdateTitleBar()
    if not self.frame then return end
    local name = str(call(UnitName, "player"))
    local level = num(call(UnitLevel, "player"))
    local class = str((call(UnitClass, "player")))
    local left
    if name and level then
        left = string.format(L["%s · Level %d %s"], name, level, class or "")
    else
        left = name or ""
    end
    self.leftText:SetText(left)

    local info = HonorLog.Rank and HonorLog.Rank:GetInfo()
    local seconds = info and num(info.secondsToWeeklyReset)
    if seconds and seconds > 0 then
        self.rightText:SetText(string.format(L["Rank week resets in %s"], Kit:Hex("white") .. HonorLog.Rank.FormatSpan(seconds) .. "|r"))
        self.rightText:Show()
    else
        self.rightText:SetText("")
        self.rightText:Hide()
    end
end

local function savePosition(frame)
    local s = settings()
    if not s then return end
    local point, _, relativePoint, x, y = frame:GetPoint()
    s.windowPoint = { point, relativePoint, x, y }
end

function Window:Create()
    if self.frame then return self.frame end
    local frame = Kit:Window(FRAME_NAME, WIDTH, HEIGHT)
    self.frame = frame
    frame:SetTitleText(L["HonorLog"])
    frame:SetPortraitTexture((HonorLog.ldb and HonorLog.ldb.icon) or Window.ICON)

    local s = settings() or {}
    local p = s.windowPoint
    frame:ClearAllPoints()
    if type(p) == "table" and p[1] then
        frame:SetPoint(p[1], UIParent, p[2] or p[1], num(p[3]) or 0, num(p[4]) or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    local scale = num(s.windowScale)
    frame:SetScale(scale and math.max(0.5, math.min(2, scale)) or 1)
    frame.honorLogOnMoved = savePosition

    if UISpecialFrames then
        local listed = false
        for _, n in ipairs(UISpecialFrames) do if n == FRAME_NAME then listed = true end end
        if not listed then table.insert(UISpecialFrames, FRAME_NAME) end
    end

    -- On the drag strip, which sits above the template's title bar art.
    local bar = frame.honorLogDrag or frame
    self.leftText = Kit:Text(bar, "grey")
    self.leftText:SetPoint("TOPLEFT", frame, "TOPLEFT", 68, -7)
    self.rightText = Kit:Text(bar, "grey")
    self.rightText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -7)
    self.rightText:SetJustifyH("RIGHT")

    self.tabs = Kit:Tabs(frame, function(key) Window:ShowScreen(key) end)
    for _, def in ipairs(self.screens) do self.tabs:Add(def.key, def.title) end

    frame:SetScript("OnShow", function()
        Window:UpdateTitleBar()
        if not Window.ticker then
            Window.ticker = C_Timer.NewTicker(TICK_SECONDS, function() Window:UpdateTitleBar() end)
        end
        Window:RefreshCurrent()
    end)
    frame:SetScript("OnHide", function()
        if Window.ticker then
            Window.ticker:Cancel()
            Window.ticker = nil
        end
    end)
    return frame
end

--------------------------------------------------------------------------------
-- Opening and closing
--------------------------------------------------------------------------------

function Window:IsShown() return self.frame ~= nil and self.frame:IsShown() end

-- Opens the window on a screen (the saved one by default).
function Window:Show(screenKey)
    local frame = self:Create()
    local s = settings()
    local key = screenKey
    if not self:GetScreen(key) then key = s and s.windowTab end
    if not self:GetScreen(key) then key = self.screens[1] and self.screens[1].key end
    if key and (self.current ~= key or not self.frames[key]) then self.tabs:Select(key) end
    frame:Show()
end

function Window:Hide()
    if self.frame then self.frame:Hide() end
end

function Window:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
end

--------------------------------------------------------------------------------
-- Entry points and data changes
--------------------------------------------------------------------------------

BINDING_HEADER_HONORLOG = "HonorLog"
BINDING_NAME_HONORLOG_TOGGLE = L["Open or close HonorLog"]

function HonorLog_ToggleWindow() Window:Toggle() end
function HonorLog_OnAddonCompartmentClick() Window:Toggle() end

for _, event in ipairs({ "HonorLog_GameRecorded", "HonorLog_RankUp", "HonorLog_GoalAcquired" }) do
    HonorLog.RegisterCallback(Window, event, function() Window:OnDataChanged() end)
end
if type(HonorLog.OnDataUpdated) == "function" then
    hooksecurefunc(HonorLog, "OnDataUpdated", function()
        local ok, err = pcall(Window.OnDataChanged, Window)
        if not ok then report(err) end
    end)
end
