-- HonorLog Main Frame
-- Expandable movable stats panel

local ADDON_NAME, HonorLog = ...

-- Frame colors
local COLORS = {
    bg = { 0.1, 0.1, 0.1, 0.9 },
    border = { 0.3, 0.3, 0.3, 1 },
    header = { 0.2, 0.2, 0.2, 1 },
    win = { 0, 1, 0, 1 },
    loss = { 1, 0, 0, 1 },
    neutral = { 1, 0.82, 0, 1 },
    text = { 1, 1, 1, 1 },
    label = { 0.7, 0.7, 0.7, 1 },
}

local BG_COLORS = {
    AV = { 0.4, 0.6, 1, 1 },    -- Blue
    AB = { 1, 0.5, 0.2, 1 },    -- Orange
    WSG = { 0.2, 0.8, 0.2, 1 }, -- Green
    EotS = { 0.8, 0.4, 0.8, 1 }, -- Purple
}

-- Create the main frame
local function CreateMainFrame()
    local frame = CreateFrame("Frame", "HonorLogMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(180, 60) -- Compact size
    frame:SetPoint("CENTER", 0, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    -- Backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(unpack(COLORS.bg))
    frame:SetBackdropBorderColor(unpack(COLORS.border))

    -- Header bar
    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetHeight(18)
    header:SetPoint("TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", -4, -4)
    header:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    })
    header:SetBackdropColor(unpack(COLORS.header))
    frame.header = header

    -- Title
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", 4, 0)
    title:SetText("HonorLog")
    title:SetTextColor(0, 1, 0, 1)
    frame.title = title

    -- View mode indicator
    local viewMode = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    viewMode:SetPoint("RIGHT", -20, 0)
    viewMode:SetTextColor(0.7, 0.7, 0.7, 1)
    frame.viewMode = viewMode

    -- Close button
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(14, 14)
    closeBtn:SetPoint("RIGHT", -2, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    closeBtn:SetScript("OnClick", function()
        HonorLog:ToggleMainFrame()
    end)

    -- Expand/collapse button
    local expandBtn = CreateFrame("Button", nil, header)
    expandBtn:SetSize(14, 14)
    expandBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    expandBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-UP")
    expandBtn:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-DOWN")
    expandBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    expandBtn:SetScript("OnClick", function()
        HonorLog:ToggleExpanded()
    end)
    frame.expandBtn = expandBtn

    -- Compact content area
    local compact = CreateFrame("Frame", nil, frame)
    compact:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    compact:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -4)
    compact:SetHeight(30)
    frame.compact = compact

    -- Current BG / Status line
    local statusLine = compact:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLine:SetPoint("TOPLEFT", 4, 0)
    statusLine:SetPoint("TOPRIGHT", -4, 0)
    statusLine:SetJustifyH("LEFT")
    frame.statusLine = statusLine

    -- Session stats line
    local sessionLine = compact:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sessionLine:SetPoint("TOPLEFT", statusLine, "BOTTOMLEFT", 0, -2)
    sessionLine:SetPoint("TOPRIGHT", statusLine, "BOTTOMRIGHT", 0, -2)
    sessionLine:SetJustifyH("LEFT")
    sessionLine:SetTextColor(unpack(COLORS.label))
    frame.sessionLine = sessionLine

    -- Expanded content area (initially hidden)
    local expanded = CreateFrame("Frame", nil, frame)
    expanded:SetPoint("TOPLEFT", compact, "BOTTOMLEFT", 0, -4)
    expanded:SetPoint("TOPRIGHT", compact, "BOTTOMRIGHT", 0, -4)
    expanded:SetHeight(140)
    expanded:Hide()
    frame.expanded = expanded

    -- Create BG stat rows
    frame.bgRows = {}
    local yOffset = 0
    for _, bgType in ipairs({"AV", "AB", "WSG", "EotS"}) do
        local row = CreateFrame("Frame", nil, expanded)
        row:SetHeight(30)
        row:SetPoint("TOPLEFT", 0, yOffset)
        row:SetPoint("TOPRIGHT", 0, yOffset)

        -- BG name
        local bgName = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bgName:SetPoint("LEFT", 4, 0)
        bgName:SetWidth(35)
        bgName:SetText(bgType)
        bgName:SetTextColor(unpack(BG_COLORS[bgType]))
        row.bgName = bgName

        -- Record (W-L)
        local record = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        record:SetPoint("LEFT", bgName, "RIGHT", 4, 0)
        record:SetWidth(45)
        record:SetJustifyH("CENTER")
        row.record = record

        -- Winrate
        local winrate = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        winrate:SetPoint("LEFT", record, "RIGHT", 4, 0)
        winrate:SetWidth(40)
        winrate:SetJustifyH("CENTER")
        row.winrate = winrate

        -- Honor
        local honor = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        honor:SetPoint("LEFT", winrate, "RIGHT", 4, 0)
        honor:SetWidth(45)
        honor:SetJustifyH("RIGHT")
        honor:SetTextColor(unpack(COLORS.neutral))
        row.honor = honor

        frame.bgRows[bgType] = row
        yOffset = yOffset - 30
    end

    -- Session summary row
    local sessionRow = CreateFrame("Frame", nil, expanded)
    sessionRow:SetHeight(24)
    sessionRow:SetPoint("TOPLEFT", 0, yOffset - 4)
    sessionRow:SetPoint("TOPRIGHT", 0, yOffset - 4)

    local sessionLabel = sessionRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sessionLabel:SetPoint("LEFT", 4, 0)
    sessionLabel:SetText("Session:")
    sessionLabel:SetTextColor(0, 1, 0, 1)

    local sessionStats = sessionRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sessionStats:SetPoint("LEFT", sessionLabel, "RIGHT", 4, 0)
    sessionStats:SetPoint("RIGHT", -4, 0)
    sessionStats:SetJustifyH("LEFT")
    frame.sessionStats = sessionStats
    frame.sessionRow = sessionRow

    -- Dragging
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not HonorLog.db.settings.frameLocked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        HonorLog.db.settings.framePoint = { point, nil, relPoint, x, y }
    end)

    -- Right-click menu
    frame:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            HonorLog:ShowContextMenu()
        end
    end)

    return frame
end

-- Initialize the main frame
function HonorLog:InitializeMainFrame()
    self.mainFrame = CreateMainFrame()

    -- Restore position
    local point = self.db.settings.framePoint
    if point and point[1] then
        self.mainFrame:ClearAllPoints()
        self.mainFrame:SetPoint(point[1], UIParent, point[3], point[4], point[5])
    end

    -- Restore scale
    self.mainFrame:SetScale(self.db.settings.frameScale or 1.0)

    -- Restore visibility
    if self.db.settings.frameVisible then
        self.mainFrame:Show()
    else
        self.mainFrame:Hide()
    end

    -- Restore expanded state
    if self.db.settings.frameExpanded then
        self:SetExpanded(true)
    end

    -- Initial update
    self:UpdateMainFrame()
end

-- Toggle frame visibility
function HonorLog:ToggleMainFrame()
    if self.mainFrame:IsShown() then
        self.mainFrame:Hide()
        self.db.settings.frameVisible = false
    else
        self.mainFrame:Show()
        self.db.settings.frameVisible = true
        self:UpdateMainFrame()
    end
end

-- Toggle expanded state
function HonorLog:ToggleExpanded()
    self:SetExpanded(not self.db.settings.frameExpanded)
end

-- Set expanded state
function HonorLog:SetExpanded(expanded)
    self.db.settings.frameExpanded = expanded

    if expanded then
        self.mainFrame.expanded:Show()
        self.mainFrame:SetHeight(200)
        self.mainFrame.expandBtn:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-UP")
        self.mainFrame.expandBtn:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-DOWN")
    else
        self.mainFrame.expanded:Hide()
        self.mainFrame:SetHeight(60)
        self.mainFrame.expandBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-UP")
        self.mainFrame.expandBtn:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-DOWN")
    end
end

-- Update the frame content
function HonorLog:UpdateMainFrame()
    if not self.mainFrame or not self.mainFrame:IsShown() then return end

    local scope = self.db.settings.viewMode
    local frame = self.mainFrame

    -- Update view mode indicator
    frame.viewMode:SetText(scope == "account" and "[A]" or "[C]")

    -- Update status line
    local currentBG = self:GetCurrentBG()
    if currentBG then
        local duration = 0
        local startTime = self:GetBGStartTime()
        if startTime then
            duration = math.floor(GetTime() - startTime)
        end
        frame.statusLine:SetText(string.format("|cffffd700%s|r - %s",
            currentBG, self:FormatDuration(duration)))
        frame.statusLine:SetTextColor(unpack(BG_COLORS[currentBG]))
    else
        frame.statusLine:SetText("Not in BG")
        frame.statusLine:SetTextColor(unpack(COLORS.label))
    end

    -- Update session line (compact view)
    local totalSession = self:GetTotalSessionStats()
    if totalSession.played > 0 then
        local color = totalSession.winrate >= 50 and COLORS.win or COLORS.loss
        frame.sessionLine:SetText(string.format("Session: %d-%d (%.0f%%) +%d hon",
            totalSession.wins, totalSession.losses, totalSession.winrate, totalSession.honor))
    else
        frame.sessionLine:SetText("Session: No games yet")
    end

    -- Update expanded BG rows
    for bgType, row in pairs(frame.bgRows) do
        local stats = self:GetBGStats(bgType, scope)
        local derived = self:GetDerivedStats(bgType, scope)

        if stats.played > 0 then
            row.record:SetText(string.format("%d-%d", stats.wins, stats.losses))
            row.winrate:SetText(string.format("%.0f%%", derived.winrate))

            local color = derived.winrate >= 50 and COLORS.win or COLORS.loss
            row.winrate:SetTextColor(unpack(color))

            row.honor:SetText(string.format("%dk", math.floor(stats.honorLifetime / 1000)))
        else
            row.record:SetText("-")
            row.record:SetTextColor(unpack(COLORS.label))
            row.winrate:SetText("-")
            row.winrate:SetTextColor(unpack(COLORS.label))
            row.honor:SetText("-")
        end
    end

    -- Update session summary
    if totalSession.played > 0 then
        frame.sessionStats:SetText(string.format("%d-%d (%.0f%%), +%d honor, +%d marks",
            totalSession.wins, totalSession.losses, totalSession.winrate,
            totalSession.honor, totalSession.marks))
    else
        frame.sessionStats:SetText("No games this session")
        frame.sessionStats:SetTextColor(unpack(COLORS.label))
    end
end

-- Context menu
local menuFrame = CreateFrame("Frame", "HonorLogContextMenu", UIParent, "UIDropDownMenuTemplate")

function HonorLog:ShowContextMenu()
    local menu = {
        { text = "HonorLog", isTitle = true, notCheckable = true },
        {
            text = "View Mode: " .. (self.db.settings.viewMode == "account" and "Account" or "Character"),
            notCheckable = true,
            func = function()
                self.db.settings.viewMode = self.db.settings.viewMode == "account" and "character" or "account"
                self:UpdateMainFrame()
            end,
        },
        {
            text = self.db.settings.frameLocked and "Unlock Frame" or "Lock Frame",
            notCheckable = true,
            func = function()
                self.db.settings.frameLocked = not self.db.settings.frameLocked
            end,
        },
        { text = "", notCheckable = true, disabled = true },
        {
            text = "Print Stats",
            notCheckable = true,
            func = function() self:PrintStats() end,
        },
        {
            text = "Reset Session",
            notCheckable = true,
            func = function()
                self:ResetSession()
                print("|cff00ff00HonorLog|r Session reset.")
            end,
        },
        {
            text = "Export",
            notCheckable = true,
            func = function() self:ShowExportFrame() end,
        },
        { text = "", notCheckable = true, disabled = true },
        {
            text = "Options",
            notCheckable = true,
            func = function() self:OpenOptions() end,
        },
        {
            text = "Close",
            notCheckable = true,
            func = function() CloseDropDownMenus() end,
        },
    }

    EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU")
end

-- Timer for in-BG duration updates
local updateTimer = 0
local UPDATE_INTERVAL = 1

local function OnUpdate(self, elapsed)
    updateTimer = updateTimer + elapsed
    if updateTimer >= UPDATE_INTERVAL then
        updateTimer = 0
        if HonorLog:IsInBG() and HonorLog.mainFrame and HonorLog.mainFrame:IsShown() then
            HonorLog:UpdateMainFrame()
        end
    end
end

HonorLog.eventFrame:SetScript("OnUpdate", OnUpdate)
