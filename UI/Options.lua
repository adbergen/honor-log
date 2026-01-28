-- HonorLog Options Panel
-- Blizzard Interface Options integration

local ADDON_NAME, HonorLog = ...

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
    -- Create slider frame manually for TBC Classic compatibility
    local slider = CreateFrame("Slider", name, parent, "BackdropTemplate")
    slider:SetWidth(200)
    slider:SetHeight(17)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    -- Set up backdrop for slider track
    slider:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 }
    })

    -- Create thumb texture
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    thumb:SetSize(32, 32)
    slider:SetThumbTexture(thumb)

    -- Create label text above slider
    local labelText = slider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("BOTTOM", slider, "TOP", 0, 3)
    labelText:SetText(label)
    slider.labelText = labelText

    -- Create min value text
    local lowText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lowText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, 0)
    lowText:SetText(minVal)
    slider.lowText = lowText

    -- Create max value text
    local highText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, 0)
    highText:SetText(maxVal)
    slider.highText = highText

    slider.tooltipText = tooltip

    -- Enable mouse interaction
    slider:EnableMouse(true)
    slider:SetScript("OnEnter", function(self)
        if self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
        end
    end)
    slider:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return slider
end

local function CreateDropdown(parent, name, label, items, onClick)
    local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dropdown, 120)

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

function HonorLog:InitializeOptions()
    -- Create main options panel
    local panel = CreateFrame("Frame", "HonorLogOptionsPanel", UIParent)
    panel.name = "HonorLog"
    self.optionsPanel = panel

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("HonorLog Options")

    local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Battleground statistics tracker for BCC Anniversary")

    -- General section
    local generalHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    generalHeader:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
    generalHeader:SetText("|cffffd700General Settings|r")

    -- View Mode dropdown
    local viewModeDropdown = CreateDropdown(panel, "HonorLogViewModeDropdown", "Default View Mode", {
        { text = "Character", value = "character" },
        { text = "Account-wide", value = "account" },
    }, function(value)
        self.db.settings.viewMode = value
        self:UpdateMainFrame()
    end)
    viewModeDropdown:SetPoint("TOPLEFT", generalHeader, "BOTTOMLEFT", -13, -24)
    viewModeDropdown.setting = "viewMode"
    UIDropDownMenu_SetSelectedValue(viewModeDropdown, self.db.settings.viewMode)
    UIDropDownMenu_SetText(viewModeDropdown, self.db.settings.viewMode == "account" and "Account-wide" or "Character")
    panel.viewModeDropdown = viewModeDropdown

    -- Export Format dropdown
    local exportFormatDropdown = CreateDropdown(panel, "HonorLogExportFormatDropdown", "Export Format", {
        { text = "Text (Discord/Forums)", value = "text" },
        { text = "CSV (Spreadsheet)", value = "csv" },
    }, function(value)
        self.db.settings.exportFormat = value
    end)
    exportFormatDropdown:SetPoint("TOPLEFT", viewModeDropdown, "TOPRIGHT", 20, 0)
    exportFormatDropdown.setting = "exportFormat"
    UIDropDownMenu_SetSelectedValue(exportFormatDropdown, self.db.settings.exportFormat)
    UIDropDownMenu_SetText(exportFormatDropdown, self.db.settings.exportFormat == "csv" and "CSV (Spreadsheet)" or "Text (Discord/Forums)")
    panel.exportFormatDropdown = exportFormatDropdown

    -- History Limit slider
    local historySlider = CreateSlider(panel, "HonorLogHistorySlider", "History Limit", 10, 100, 10, "Number of games to store in history")
    historySlider:SetPoint("TOPLEFT", viewModeDropdown, "BOTTOMLEFT", 20, -40)
    historySlider:SetValue(self.db.char.historyLimit or 50)
    historySlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        self.labelText:SetText("History Limit: " .. value)
        HonorLog:SetHistoryLimit(value)
    end)
    historySlider.labelText:SetText("History Limit: " .. (self.db.char.historyLimit or 50))
    panel.historySlider = historySlider

    -- Frame section
    local frameHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frameHeader:SetPoint("TOPLEFT", historySlider, "BOTTOMLEFT", -20, -25)
    frameHeader:SetText("|cffffd700Frame Settings|r")

    -- Frame Scale slider
    local scaleSlider = CreateSlider(panel, "HonorLogScaleSlider", "Frame Scale", 0.5, 2.0, 0.1, "Size of the stats frame")
    scaleSlider:SetPoint("TOPLEFT", frameHeader, "BOTTOMLEFT", 20, -20)
    scaleSlider:SetValue(self.db.settings.frameScale or 1.0)
    scaleSlider:SetScript("OnValueChanged", function(self, value)
        self.labelText:SetText(string.format("Frame Scale: %.1f", value))
        HonorLog.db.settings.frameScale = value
        if HonorLog.mainFrame then
            HonorLog.mainFrame:SetScale(value)
        end
    end)
    scaleSlider.labelText:SetText(string.format("Frame Scale: %.1f", self.db.settings.frameScale or 1.0))
    panel.scaleSlider = scaleSlider

    -- Lock Frame checkbox
    local lockCheck = CreateCheckbox(panel, "HonorLogLockCheck", "Lock Frame Position", "Prevent the frame from being moved", function(checked)
        HonorLog.db.settings.frameLocked = checked
    end)
    lockCheck:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", -4, -15)
    lockCheck:SetChecked(self.db.settings.frameLocked)
    panel.lockCheck = lockCheck

    -- Notifications section
    local notifyHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notifyHeader:SetPoint("TOPLEFT", lockCheck, "BOTTOMLEFT", 4, -12)
    notifyHeader:SetText("|cffffd700Notifications|r")

    -- Enable Notifications checkbox
    local notifyCheck = CreateCheckbox(panel, "HonorLogNotifyCheck", "Enable Milestone Notifications", "Show messages when you reach milestones (100 wins, 70% winrate, etc.)", function(checked)
        HonorLog.db.settings.notificationsEnabled = checked
    end)
    notifyCheck:SetPoint("TOPLEFT", notifyHeader, "BOTTOMLEFT", -4, -10)
    notifyCheck:SetChecked(self.db.settings.notificationsEnabled)
    panel.notifyCheck = notifyCheck

    -- Goals section
    local goalsHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    goalsHeader:SetPoint("TOPLEFT", notifyCheck, "BOTTOMLEFT", 4, -12)
    goalsHeader:SetText("|cffffd700Goals Settings|r")

    -- Waterfall Progress checkbox
    local waterfallCheck = CreateCheckbox(panel, "HonorLogWaterfallCheck", "Waterfall Progress Mode", "Fill goals from top to bottom sequentially instead of showing equal percentage across all goals", function(checked)
        HonorLog.db.settings.goalProgressMode = checked and "waterfall" or "shared"
        if HonorLog.OnDataUpdated then
            HonorLog:OnDataUpdated()
        end
    end)
    waterfallCheck:SetPoint("TOPLEFT", goalsHeader, "BOTTOMLEFT", -4, -10)
    waterfallCheck:SetChecked(self.db.settings.goalProgressMode == "waterfall")
    panel.waterfallCheck = waterfallCheck

    -- LDB section
    local ldbHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ldbHeader:SetPoint("TOPLEFT", waterfallCheck, "BOTTOMLEFT", 4, -12)
    ldbHeader:SetText("|cffffd700Data Broker|r")

    -- Enable LDB checkbox
    local ldbCheck = CreateCheckbox(panel, "HonorLogLDBCheck", "Enable LDB/Broker Data Feed", "Expose stats to Titan Panel, Bazooka, ChocolateBar, etc.", function(checked)
        HonorLog.db.settings.ldbEnabled = checked
        if HonorLog.UpdateLDB then
            HonorLog:UpdateLDB()
        end
    end)
    ldbCheck:SetPoint("TOPLEFT", ldbHeader, "BOTTOMLEFT", -4, -10)
    ldbCheck:SetChecked(self.db.settings.ldbEnabled)
    panel.ldbCheck = ldbCheck

    -- Show Minimap Button checkbox
    local minimapCheck = CreateCheckbox(panel, "HonorLogMinimapCheck", "Show Minimap Button", "Display a minimap button for quick access", function(checked)
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
    minimapCheck:SetPoint("TOPLEFT", ldbCheck, "BOTTOMLEFT", 0, -5)
    minimapCheck:SetChecked(not self.db.settings.minimapButton.hide)
    panel.minimapCheck = minimapCheck

    -- Reset buttons section
    local resetHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    resetHeader:SetPoint("TOPLEFT", minimapCheck, "BOTTOMLEFT", 4, -15)
    resetHeader:SetText("|cffffd700Data Management|r")

    -- Reset Session button
    local resetSessionBtn = CreateFrame("Button", "HonorLogResetSessionBtn", panel, "UIPanelButtonTemplate")
    resetSessionBtn:SetSize(120, 25)
    resetSessionBtn:SetPoint("TOPLEFT", resetHeader, "BOTTOMLEFT", 0, -10)
    resetSessionBtn:SetText("Reset Today")
    resetSessionBtn:SetScript("OnClick", function()
        HonorLog:ResetSession()
        print("|cff00ff00HonorLog|r Today's stats reset.")
    end)

    -- Reset Frame Position button
    local resetPosBtn = CreateFrame("Button", "HonorLogResetPosBtn", panel, "UIPanelButtonTemplate")
    resetPosBtn:SetSize(140, 25)
    resetPosBtn:SetPoint("LEFT", resetSessionBtn, "RIGHT", 10, 0)
    resetPosBtn:SetText("Reset Frame Position")
    resetPosBtn:SetScript("OnClick", function()
        HonorLog.db.settings.framePoint = { "CENTER", nil, "CENTER", 0, 0 }
        HonorLog.db.settings.frameScale = 1.0
        if HonorLog.mainFrame then
            HonorLog.mainFrame:ClearAllPoints()
            HonorLog.mainFrame:SetPoint("CENTER", 0, 0)
            HonorLog.mainFrame:SetScale(1.0)
        end
        scaleSlider:SetValue(1.0)
        print("|cff00ff00HonorLog|r Frame position reset.")
    end)

    -- Register with Blizzard options
    if Settings and Settings.RegisterCanvasLayoutCategory then
        -- Modern Settings API (Anniversary/Retail)
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        category.ID = panel.name  -- Set ID to match name for OpenToCategory lookup
        Settings.RegisterAddOnCategory(category)
        self.optionsCategory = category
    else
        -- Classic style
        InterfaceOptions_AddCategory(panel)
    end
end

function HonorLog:OpenOptions()
    if Settings and Settings.OpenToCategory then
        -- Use string name for lookup (matches category.ID we set during registration)
        Settings.OpenToCategory("HonorLog")
    else
        -- TBC Classic fallback (pre-Settings API)
        InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
    end
end
