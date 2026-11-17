-- HonorLog Options Panel
-- Blizzard Interface Options integration with scrollable two-column layout

local ADDON_NAME, HonorLog = ...

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function CreateCheckbox(parent, name, label, tooltip, onClick)
    local check = CreateFrame("CheckButton", name, parent, "InterfaceOptionsCheckButtonTemplate")
    check.Text:SetText(label)
    check.tooltipText = tooltip
    check:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        if onClick then onClick(checked) end
    end)
    return check
end

local function CreateSlider(parent, name, label, minVal, maxVal, step, tooltip)
    local slider = CreateFrame("Slider", name, parent, "BackdropTemplate")
    slider:SetWidth(180)
    slider:SetHeight(17)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    slider:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 }
    })

    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    thumb:SetSize(32, 32)
    slider:SetThumbTexture(thumb)

    local labelText = slider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("BOTTOM", slider, "TOP", 0, 3)
    labelText:SetText(label)
    slider.labelText = labelText

    local lowText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lowText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, 0)
    lowText:SetText(minVal)
    slider.lowText = lowText

    local highText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, 0)
    highText:SetText(maxVal)
    slider.highText = highText

    slider.tooltipText = tooltip
    slider:EnableMouse(true)
    slider:SetScript("OnEnter", function(self)
        if self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
        end
    end)
    slider:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return slider
end

local function CreateDropdown(parent, name, label, items, onClick)
    local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dropdown, 140)

    local labelText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 16, 3)
    labelText:SetText(label)
    dropdown.label = labelText

    UIDropDownMenu_Initialize(dropdown, function(self, level)
        for _, item in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.value = item.value
            info.checked = (HonorLog.db.settings[dropdown.setting] == item.value)
            info.func = function()
                UIDropDownMenu_SetSelectedValue(dropdown, item.value)
                UIDropDownMenu_SetText(dropdown, item.text)
                if onClick then onClick(item.value) end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    return dropdown
end

local function CreateSectionHeader(parent, text)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetText("|cffffd700" .. text .. "|r")
    return header
end

local function CreateButton(parent, name, text, width, onClick)
    local btn = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    btn:SetSize(width, 24)
    btn:SetText(text)
    btn:SetScript("OnClick", onClick)
    return btn
end

--------------------------------------------------------------------------------
-- OPTIONS PANEL
--------------------------------------------------------------------------------

function HonorLog:InitializeOptions()
    local panel = CreateFrame("Frame", "HonorLogOptionsPanel", UIParent)
    panel.name = "HonorLog"
    self.optionsPanel = panel

    -- Title (fixed at top)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("HonorLog Options")

    local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetText("Battleground statistics, PvP rank and gear goals for WoW Forever")

    -- Scroll frame for content
    local scrollFrame = CreateFrame("ScrollFrame", "HonorLogOptionsScroll", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 8)

    local scrollChild = CreateFrame("Frame", "HonorLogOptionsScrollChild", scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth() or 580)
    scrollChild:SetHeight(500) -- Will be adjusted
    scrollFrame:SetScrollChild(scrollChild)

    -- Update scroll child width when panel shows
    panel:SetScript("OnShow", function()
        scrollChild:SetWidth(scrollFrame:GetWidth())
    end)

    -- Column widths
    local COL_WIDTH = 280
    local COL_SPACING = 20
    local LEFT_COL = 0
    local RIGHT_COL = COL_WIDTH + COL_SPACING

    local leftY = 0
    local rightY = 0

    ----------------------------------------------------------------------------
    -- LEFT COLUMN: Display & Frame
    ----------------------------------------------------------------------------

    -- === DISPLAY SETTINGS ===
    local displayHeader = CreateSectionHeader(scrollChild, "Display")
    displayHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", LEFT_COL, leftY)
    leftY = leftY - 24

    -- View Mode dropdown
    local viewModeDropdown = CreateDropdown(scrollChild, "HonorLogViewModeDropdown", "Default View Mode", {
        { text = "Character", value = "character" },
        { text = "Account-wide", value = "account" },
    }, function(value)
        self.db.settings.viewMode = value
        self:UpdateMainFrame()
    end)
    viewModeDropdown:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", LEFT_COL - 13, leftY - 10)
    viewModeDropdown.setting = "viewMode"
    UIDropDownMenu_SetSelectedValue(viewModeDropdown, self.db.settings.viewMode)
    UIDropDownMenu_SetText(viewModeDropdown, self.db.settings.viewMode == "account" and "Account-wide" or "Character")
    leftY = leftY - 60

    -- Export Format dropdown
    local exportFormatDropdown = CreateDropdown(scrollChild, "HonorLogExportFormatDropdown", "Export Format", {
        { text = "Text (Discord/Forums)", value = "text" },
        { text = "CSV (Spreadsheet)", value = "csv" },
    }, function(value)
        self.db.settings.exportFormat = value
    end)
    exportFormatDropdown:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", LEFT_COL - 13, leftY - 10)
    exportFormatDropdown.setting = "exportFormat"
    UIDropDownMenu_SetSelectedValue(exportFormatDropdown, self.db.settings.exportFormat)
    UIDropDownMenu_SetText(exportFormatDropdown, self.db.settings.exportFormat == "csv" and "CSV (Spreadsheet)" or "Text (Discord/Forums)")
    leftY = leftY - 60

    -- === FRAME SETTINGS ===
    local frameHeader = CreateSectionHeader(scrollChild, "Frame")
    frameHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", LEFT_COL, leftY)
    leftY = leftY - 28

    -- Frame Scale slider
    local scaleSlider = CreateSlider(scrollChild, "HonorLogScaleSlider", "Frame Scale", 0.5, 2.0, 0.1, "Size of the stats frame")
    scaleSlider:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", LEFT_COL + 10, leftY)
    scaleSlider:SetValue(self.db.settings.frameScale or 1.0)
    scaleSlider:SetScript("OnValueChanged", function(self, value)
        self.labelText:SetText(string.format("Frame Scale: %.1f", value))
        HonorLog.db.settings.frameScale = value
        if HonorLog.mainFrame then
            HonorLog.mainFrame:SetScale(value)
        end
    end)
    scaleSlider.labelText:SetText(string.format("Frame Scale: %.1f", self.db.settings.frameScale or 1.0))
    leftY = leftY - 50

    -- Lock Frame checkbox
    local lockCheck = CreateCheckbox(scrollChild, "HonorLogLockCheck", "Lock Frame Position", "Prevent the frame from being moved", function(checked)
        HonorLog.db.settings.frameLocked = checked
    end)
    lockCheck:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", LEFT_COL, leftY)
    lockCheck:SetChecked(self.db.settings.frameLocked)
    leftY = leftY - 28

    -- === VISIBLE STAT CARDS ===
    local cardsHeader = CreateSectionHeader(scrollChild, "Visible Stat Cards")
    cardsHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", LEFT_COL, leftY)
    leftY = leftY - 24

    -- Ensure visibleCards exists
    if not self.db.settings.visibleCards then
        self.db.settings.visibleCards = { AV = true, AB = true, WSG = true, DI = true, World = true }
    end

    -- Card checkboxes
    local cardData = {
        { key = "AV", label = "Alterac Valley" },
        { key = "AB", label = "Arathi Basin" },
        { key = "WSG", label = "Warsong Gulch" },
        { key = "DI", label = "Darkspear Islands" },
        { key = "World", label = "World PvP" },
    }

    local cardStartY = leftY
    for i, card in ipairs(cardData) do
        local check = CreateCheckbox(scrollChild, "HonorLog" .. card.key .. "Check", card.label, nil, function(checked)
            HonorLog.db.settings.visibleCards[card.key] = checked
            if HonorLog.UpdateMainFrame then HonorLog:UpdateMainFrame() end
        end)
        check:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", LEFT_COL, cardStartY - ((i - 1) * 24))
        check:SetChecked(self.db.settings.visibleCards[card.key] ~= false)
    end
    leftY = cardStartY - (#cardData * 24) - 12

    -- === RANK ===
    local rankHeader = CreateSectionHeader(scrollChild, "PvP Rank")
    rankHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", LEFT_COL, leftY)
    leftY = leftY - 24

    local rankBarCheck = CreateCheckbox(scrollChild, "HonorLogRankBarCheck", "Show Rank Bar", "Show the rank progress bar under the title", function(checked)
        HonorLog.db.settings.showRankBar = checked
        if HonorLog.RefreshRank then HonorLog:RefreshRank() end
    end)
    rankBarCheck:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", LEFT_COL, leftY)
    rankBarCheck:SetChecked(self.db.settings.showRankBar ~= false)
    leftY = leftY - 26

    local rankCapCheck = CreateCheckbox(scrollChild, "HonorLogRankCapCheck", "Weekly Cap Alert", "Alert once a week when the weekly rank cap is reached", function(checked)
        HonorLog.db.settings.rankCapAlert = checked
    end)
    rankCapCheck:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", LEFT_COL, leftY)
    rankCapCheck:SetChecked(self.db.settings.rankCapAlert ~= false)
    leftY = leftY - 26

    local ldbFormatDropdown = CreateDropdown(scrollChild, "HonorLogLDBFormatDropdown", "Broker Text", {
        { text = "Games (today's record)", value = "games" },
        { text = "Rank (R7 Title - 62%)", value = "rank" },
    }, function(value)
        self.db.settings.ldbFormat = value
        if HonorLog.UpdateLDB then HonorLog:UpdateLDB() end
    end)
    ldbFormatDropdown:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", LEFT_COL - 13, leftY - 22)
    ldbFormatDropdown.setting = "ldbFormat"
    UIDropDownMenu_SetSelectedValue(ldbFormatDropdown, self.db.settings.ldbFormat)
    UIDropDownMenu_SetText(ldbFormatDropdown, self.db.settings.ldbFormat == "rank" and "Rank (R7 Title - 62%)" or "Games (today's record)")
    leftY = leftY - 70

    ----------------------------------------------------------------------------
    -- RIGHT COLUMN: Features & Data
    ----------------------------------------------------------------------------

    -- === FEATURES ===
    local featuresHeader = CreateSectionHeader(scrollChild, "Features")
    featuresHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", RIGHT_COL, rightY)
    rightY = rightY - 24

    -- Enable Notifications checkbox
    local notifyCheck = CreateCheckbox(scrollChild, "HonorLogNotifyCheck", "Milestone Notifications", "Show messages when you reach milestones", function(checked)
        HonorLog.db.settings.notificationsEnabled = checked
    end)
    notifyCheck:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", RIGHT_COL, rightY)
    notifyCheck:SetChecked(self.db.settings.notificationsEnabled)
    rightY = rightY - 26

    -- Waterfall Progress checkbox
    local waterfallCheck = CreateCheckbox(scrollChild, "HonorLogWaterfallCheck", "Waterfall Progress Mode", "Fill goals top to bottom instead of equal %", function(checked)
        HonorLog.db.settings.goalProgressMode = checked and "waterfall" or "shared"
        if HonorLog.OnDataUpdated then
            HonorLog:OnDataUpdated()
        end
    end)
    waterfallCheck:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", RIGHT_COL, rightY)
    waterfallCheck:SetChecked(self.db.settings.goalProgressMode == "waterfall")
    rightY = rightY - 26

    -- Spend-before-cap advice in the goals header
    local capAdviceCheck = CreateCheckbox(scrollChild, "HonorLogGoalCapAdviceCheck", "Goal Cap Advice", "Name the goal to buy when honor is about to cap", function(checked)
        HonorLog.db.settings.goalCapAdvice = checked
        if HonorLog.UpdateGoalsPanel then HonorLog:UpdateGoalsPanel() end
    end)
    capAdviceCheck:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", RIGHT_COL, rightY)
    capAdviceCheck:SetChecked(self.db.settings.goalCapAdvice ~= false)
    rightY = rightY - 26

    -- Items no vendor scan has seen stocked
    local unverifiedCheck = CreateCheckbox(scrollChild, "HonorLogGoalUnverifiedCheck", "Show Unverified Gear", "List items the client data marks as retired until a vendor scan sees them in stock", function(checked)
        HonorLog.db.settings.goalShowUnverified = checked
    end)
    unverifiedCheck:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", RIGHT_COL, rightY)
    unverifiedCheck:SetChecked(self.db.settings.goalShowUnverified == true)
    rightY = rightY - 26

    -- Automatic PvP vendor price scan
    local autoScanCheck = CreateCheckbox(scrollChild, "HonorLogAutoScanCheck", "Scan PvP Vendors", "Read the real prices when you open a PvP vendor, so goals use what the vendor charges", function(checked)
        HonorLog.db.settings.autoVendorScan = checked
    end)
    autoScanCheck:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", RIGHT_COL, rightY)
    autoScanCheck:SetChecked(self.db.settings.autoVendorScan ~= false)
    rightY = rightY - 26

    -- Enable LDB checkbox
    local ldbCheck = CreateCheckbox(scrollChild, "HonorLogLDBCheck", "Data Broker Feed", "Expose stats to Titan Panel, etc.", function(checked)
        HonorLog.db.settings.ldbEnabled = checked
        if HonorLog.UpdateLDB then
            HonorLog:UpdateLDB()
        end
    end)
    ldbCheck:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", RIGHT_COL, rightY)
    ldbCheck:SetChecked(self.db.settings.ldbEnabled)
    rightY = rightY - 26

    -- Show Minimap Button checkbox
    local minimapCheck = CreateCheckbox(scrollChild, "HonorLogMinimapCheck", "Minimap Button", "Display a minimap button for quick access", function(checked)
        if HonorLog.minimapIcon then
            if checked then
                HonorLog.minimapIcon:Show("HonorLog")
                HonorLog.db.settings.minimapButton.hide = false
            else
                HonorLog.minimapIcon:Hide("HonorLog")
                HonorLog.db.settings.minimapButton.hide = true
            end
        end
    end)
    minimapCheck:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", RIGHT_COL, rightY)
    minimapCheck:SetChecked(not self.db.settings.minimapButton.hide)
    rightY = rightY - 36

    -- === DATA ===
    local dataHeader = CreateSectionHeader(scrollChild, "Data")
    dataHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", RIGHT_COL, rightY)
    rightY = rightY - 28

    -- History Limit slider
    local historySlider = CreateSlider(scrollChild, "HonorLogHistorySlider", "History Limit", 10, 500, 10, "Number of games to store in history")
    historySlider:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", RIGHT_COL + 10, rightY)
    historySlider:SetValue(self.db.char.historyLimit or 200)
    historySlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        self.labelText:SetText("History Limit: " .. value)
        HonorLog:SetHistoryLimit(value)
    end)
    historySlider.labelText:SetText("History Limit: " .. (self.db.char.historyLimit or 200))
    rightY = rightY - 50

    -- Reset buttons
    local resetTodayBtn = CreateButton(scrollChild, "HonorLogResetSessionBtn", "Reset Today", 100, function()
        HonorLog:ResetSession()
        print("|cff40d860HonorLog|r Today's stats reset.")
    end)
    resetTodayBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", RIGHT_COL, rightY)

    local resetPosBtn = CreateButton(scrollChild, "HonorLogResetPosBtn", "Reset Frame", 100, function()
        HonorLog.db.settings.framePoint = { "CENTER", nil, "CENTER", 0, 0 }
        HonorLog.db.settings.frameScale = 1.0
        if HonorLog.mainFrame then
            HonorLog.mainFrame:ClearAllPoints()
            HonorLog.mainFrame:SetPoint("CENTER", 0, 0)
            HonorLog.mainFrame:SetScale(1.0)
        end
        scaleSlider:SetValue(1.0)
        print("|cff40d860HonorLog|r Frame position reset.")
    end)
    resetPosBtn:SetPoint("LEFT", resetTodayBtn, "RIGHT", 8, 0)
    rightY = rightY - 34

    ----------------------------------------------------------------------------
    -- Finalize scroll child height
    ----------------------------------------------------------------------------
    local contentHeight = math.max(math.abs(leftY), math.abs(rightY)) + 20
    scrollChild:SetHeight(contentHeight)

    -- Store references
    panel.scaleSlider = scaleSlider

    ----------------------------------------------------------------------------
    -- Register with Blizzard options
    ----------------------------------------------------------------------------
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        category.ID = panel.name
        Settings.RegisterAddOnCategory(category)
        self.optionsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function HonorLog:OpenOptions()
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory("HonorLog")
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
    end
end
