-- HonorLog Goals Panel
-- UI for gear goal tracking

local ADDON_NAME, HonorLog = ...

--------------------------------------------------------------------------------
-- THEME (from shared UI/Theme.lua)
--------------------------------------------------------------------------------
local COLORS = HonorLog.Theme
local BG_COLOR_HEX = HonorLog.BG_COLOR_HEX

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS (from shared UI/Theme.lua)
--------------------------------------------------------------------------------
local Layout = HonorLog.Layout
local PADDING = Layout.PADDING
local GOAL_CARD_HEIGHT = Layout.GOAL_CARD_HEIGHT
local GOAL_CARD_SPACING = Layout.GOAL_CARD_SPACING
local TAB_WIDTH = Layout.TAB_WIDTH
local TAB_HEIGHT = Layout.TAB_HEIGHT
local ITEM_ROW_HEIGHT = Layout.ITEM_ROW_HEIGHT

--------------------------------------------------------------------------------
-- TAB SYSTEM
--------------------------------------------------------------------------------
local currentTab = "stats" -- "stats" or "goals"

local function CreateTabButton(parent, text, isFirst)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(TAB_WIDTH, TAB_HEIGHT)

    -- Background
    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.15, 0.15, 0.20, 0.8)
    tab.bg = bg

    -- Text
    local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", 0, 0)
    label:SetText(text)
    label:SetTextColor(unpack(COLORS.textSecondary))
    tab.label = label

    -- Border
    local border = tab:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetPoint("BOTTOMRIGHT", 0, 0)
    border:SetColorTexture(unpack(COLORS.borderDark))
    tab.border = border

    -- Active indicator (bottom bar)
    local active = tab:CreateTexture(nil, "OVERLAY")
    active:SetHeight(2)
    active:SetPoint("BOTTOMLEFT", 1, 0)
    active:SetPoint("BOTTOMRIGHT", -1, 0)
    active:SetColorTexture(unpack(COLORS.brand))
    active:Hide()
    tab.activeIndicator = active

    -- Hover effect
    tab:SetScript("OnEnter", function(self)
        if not self.isActive then
            self.bg:SetColorTexture(0.20, 0.20, 0.25, 0.9)
        end
    end)
    tab:SetScript("OnLeave", function(self)
        if not self.isActive then
            self.bg:SetColorTexture(0.15, 0.15, 0.20, 0.8)
        end
    end)

    function tab:SetActive(isActive)
        self.isActive = isActive
        if isActive then
            self.bg:SetColorTexture(0.18, 0.22, 0.28, 1)
            self.label:SetTextColor(unpack(COLORS.brand))
            self.activeIndicator:Show()
        else
            self.bg:SetColorTexture(0.15, 0.15, 0.20, 0.8)
            self.label:SetTextColor(unpack(COLORS.textSecondary))
            self.activeIndicator:Hide()
        end
    end

    return tab
end

--------------------------------------------------------------------------------
-- GOAL CARD CREATION
--------------------------------------------------------------------------------
local function CreateGoalCard(parent, index)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetHeight(GOAL_CARD_HEIGHT)
    card:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    card:SetBackdropColor(unpack(COLORS.bgCard))
    card:SetBackdropBorderColor(unpack(COLORS.borderDark))

    -- Hover effect with item tooltip and shift-compare
    card:EnableMouse(true)
    card.shiftWasDown = false

    local function ShowCardTooltip(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
            if IsShiftKeyDown() then
                GameTooltip_ShowCompareItem()
                self.shiftWasDown = true
            else
                self.shiftWasDown = false
            end
        end
    end

    card:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(COLORS.bgCardHover))
        self:SetBackdropBorderColor(unpack(COLORS.borderAccent))
        ShowCardTooltip(self)
    end)
    card:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(COLORS.bgCard))
        self:SetBackdropBorderColor(unpack(COLORS.borderDark))
        GameTooltip:Hide()
        if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
        if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
    end)
    card:SetScript("OnUpdate", function(self)
        if not self:IsMouseOver() then return end
        local shiftDown = IsShiftKeyDown()
        if shiftDown ~= self.shiftWasDown then
            ShowCardTooltip(self)
        end
    end)

    -- Item icon
    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", 8, -8)
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card.icon = icon

    -- Remove button (top right corner, create early for anchoring)
    local removeBtn = CreateFrame("Button", nil, card)
    removeBtn:SetSize(14, 14)
    removeBtn:SetPoint("TOPRIGHT", -4, -4)

    local removeBg = removeBtn:CreateTexture(nil, "BACKGROUND")
    removeBg:SetAllPoints()
    removeBg:SetColorTexture(0.8, 0.2, 0.2, 0)
    removeBtn.bg = removeBg

    local removeIcon = removeBtn:CreateTexture(nil, "ARTWORK")
    removeIcon:SetAllPoints()
    removeIcon:SetTexture("Interface\\Buttons\\UI-StopButton")
    removeIcon:SetAlpha(0.4)
    removeBtn.icon = removeIcon

    removeBtn:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(0.8, 0.2, 0.2, 0.3)
        self.icon:SetAlpha(1)
    end)
    removeBtn:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(0.8, 0.2, 0.2, 0)
        self.icon:SetAlpha(0.4)
    end)
    card.removeBtn = removeBtn

    -- Item name (extends to remove button)
    local itemName = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    itemName:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -1)
    itemName:SetPoint("RIGHT", removeBtn, "LEFT", -4, 0)
    itemName:SetJustifyH("LEFT")
    itemName:SetTextColor(unpack(COLORS.textPrimary))
    itemName:SetWordWrap(false)
    itemName:SetMaxLines(1)
    card.itemName = itemName

    -- XP-style progress bar container (below name)
    local barContainer = CreateFrame("Frame", nil, card, "BackdropTemplate")
    barContainer:SetHeight(8)
    barContainer:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -15)
    barContainer:SetPoint("RIGHT", -42, 0)

    -- Progress percentage (aligned with bar, right side)
    local progressText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    progressText:SetPoint("LEFT", barContainer, "RIGHT", 4, 0)
    progressText:SetJustifyH("RIGHT")
    progressText:SetWidth(32)
    card.progressText = progressText
    barContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    barContainer:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    barContainer:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    card.barContainer = barContainer

    -- Progress bar fill (XP bar style - purple/blue gradient)
    local progressFill = barContainer:CreateTexture(nil, "ARTWORK")
    progressFill:SetHeight(6)
    progressFill:SetPoint("TOPLEFT", 1, -1)
    progressFill:SetPoint("BOTTOMLEFT", 1, 1)
    progressFill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    progressFill:SetWidth(1)
    card.progressFill = progressFill

    -- Subtle shine overlay
    local progressShine = barContainer:CreateTexture(nil, "ARTWORK", nil, 1)
    progressShine:SetHeight(3)
    progressShine:SetPoint("TOPLEFT", progressFill, "TOPLEFT", 0, 0)
    progressShine:SetPoint("TOPRIGHT", progressFill, "TOPRIGHT", 0, 0)
    progressShine:SetTexture("Interface\\Buttons\\WHITE8x8")
    progressShine:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0.15), CreateColor(1, 1, 1, 0))
    card.progressShine = progressShine

    -- Spark at end of progress bar
    local progressSpark = barContainer:CreateTexture(nil, "OVERLAY")
    progressSpark:SetSize(12, 12)
    progressSpark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    progressSpark:SetBlendMode("ADD")
    progressSpark:SetAlpha(0.7)
    card.progressSpark = progressSpark

    -- Handle resize to update progress bar fill width
    barContainer:SetScript("OnSizeChanged", function(self)
        local percent = card.progressPercent or 0
        local containerWidth = self:GetWidth()
        if containerWidth > 2 then
            local fillWidth = math.max(1, (containerWidth - 2) * (percent / 100))
            card.progressFill:SetWidth(fillWidth)
            card.progressShine:SetWidth(fillWidth)
        end
    end)

    -- Reference for positioning
    card.progressBg = barContainer

    -- Currency info line (below progress bar)
    local currencyLine = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    currencyLine:SetPoint("TOPLEFT", barContainer, "BOTTOMLEFT", 0, -4)
    currencyLine:SetPoint("RIGHT", -6, 0)
    currencyLine:SetJustifyH("LEFT")
    currencyLine:SetTextColor(unpack(COLORS.textSecondary))
    currencyLine:SetWordWrap(false)
    currencyLine:SetMaxLines(1)
    card.currencyLine = currencyLine

    -- Games estimate line (bottom)
    local gamesLine = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gamesLine:SetPoint("TOPLEFT", currencyLine, "BOTTOMLEFT", 0, -2)
    gamesLine:SetPoint("RIGHT", -6, 0)
    gamesLine:SetJustifyH("LEFT")
    gamesLine:SetTextColor(unpack(COLORS.textTertiary))
    gamesLine:SetWordWrap(false)
    gamesLine:SetMaxLines(1)
    card.gamesLine = gamesLine

    -- Complete indicator (shown when goal is achieved)
    local completeIcon = card:CreateTexture(nil, "OVERLAY")
    completeIcon:SetSize(12, 12)
    completeIcon:SetPoint("RIGHT", removeBtn, "LEFT", -4, 0) -- Position left of remove button
    completeIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
    completeIcon:SetVertexColor(0.3, 0.9, 0.4, 1)
    completeIcon:Hide()
    card.completeIcon = completeIcon

    -- Update function
    function card:Update(goalProgress)
        if not goalProgress then
            self:Hide()
            return
        end

        self:Show()

        -- Get item info
        local itemID = goalProgress.itemID
        local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)

        if itemTexture then
            self.icon:SetTexture(itemTexture)
        else
            self.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            -- Request item info for next update
            C_Item.RequestLoadItemDataByID(itemID)
        end

        self.itemName:SetText(goalProgress.name or itemName or "Unknown Item")

        -- Calculate overall progress
        local overallPercent = 100
        local parts = {}

        if goalProgress.honor.needed > 0 then
            overallPercent = math.min(overallPercent, goalProgress.honor.percent)
            if goalProgress.honor.remaining > 0 then
                -- Not enough yet - show in gold
                table.insert(parts, string.format("|cffffd700%d/%d Honor|r", goalProgress.honor.current, goalProgress.honor.needed))
            else
                -- Have enough - show in green
                table.insert(parts, string.format("|cff40d860%d/%d Honor|r", goalProgress.honor.current, goalProgress.honor.needed))
            end
        end

        if goalProgress.arena.needed > 0 then
            overallPercent = math.min(overallPercent, goalProgress.arena.percent)
            if goalProgress.arena.remaining > 0 then
                -- Not enough yet - show in purple
                table.insert(parts, string.format("|cffaa55ff%d/%d Arena|r", goalProgress.arena.current, goalProgress.arena.needed))
            else
                -- Have enough - show in green
                table.insert(parts, string.format("|cff40d860%d/%d Arena|r", goalProgress.arena.current, goalProgress.arena.needed))
            end
        end

        -- Process marks in consistent order with BG-specific colors
        local bgOrder = { "AV", "AB", "WSG", "EotS" }
        for _, bgType in ipairs(bgOrder) do
            local markData = goalProgress.marks[bgType]
            if markData then
                overallPercent = math.min(overallPercent, markData.percent)
                if markData.remaining > 0 then
                    -- Not enough yet - show in BG color
                    local colorHex = BG_COLOR_HEX[bgType] or "55bbff"
                    table.insert(parts, string.format("|cff%s%d/%d %s|r", colorHex, markData.current, markData.needed, bgType))
                else
                    -- Have enough - show in green
                    table.insert(parts, string.format("|cff40d860%d/%d %s|r", markData.current, markData.needed, bgType))
                end
            end
        end

        -- Store progress percent for responsive resize
        self.progressPercent = overallPercent

        -- Update XP-style progress bar
        local containerWidth = self.barContainer:GetWidth()
        local fillWidth = math.max(1, (containerWidth - 2) * (overallPercent / 100))
        self.progressFill:SetWidth(fillWidth)
        self.progressShine:SetWidth(fillWidth)

        -- Position spark at end of fill (XP bar effect)
        if overallPercent > 0 and overallPercent < 100 then
            self.progressSpark:SetPoint("CENTER", self.progressFill, "RIGHT", 0, 0)
            self.progressSpark:Show()
        else
            self.progressSpark:Hide()
        end

        if overallPercent >= 100 then
            self.progressFill:SetVertexColor(unpack(COLORS.progressFull))
            self.progressText:SetText("100%")
            self.progressText:SetTextColor(unpack(COLORS.progressFull))
            self.completeIcon:Show()
        elseif overallPercent >= 50 then
            self.progressFill:SetVertexColor(unpack(COLORS.progressPartial))
            self.progressText:SetText(string.format("%.0f%%", overallPercent))
            self.progressText:SetTextColor(unpack(COLORS.progressPartial))
            self.completeIcon:Hide()
        else
            self.progressFill:SetVertexColor(unpack(COLORS.progressLow))
            self.progressText:SetText(string.format("%.0f%%", overallPercent))
            self.progressText:SetTextColor(unpack(COLORS.progressLow))
            self.completeIcon:Hide()
        end

        -- Currency line (formatted nicely)
        if #parts > 0 then
            self.currencyLine:SetText(table.concat(parts, "  |cff666666·|r  "))
        else
            self.currencyLine:SetText("|cff40d860Ready to purchase!|r")
        end

        -- Games remaining estimate (separate line)
        if goalProgress.totalGamesNeeded > 0 then
            self.gamesLine:SetText(string.format("Est. %d games remaining", goalProgress.totalGamesNeeded))
            self.gamesLine:Show()
        else
            self.gamesLine:SetText("")
            self.gamesLine:Hide()
        end

        -- Store itemID for remove button
        self.itemID = itemID
    end

    return card
end

--------------------------------------------------------------------------------
-- GOALS PANEL CREATION
--------------------------------------------------------------------------------
local function CreateGoalsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel:Hide()

    -- Empty state
    local emptyState = CreateFrame("Frame", nil, panel)
    emptyState:SetAllPoints()
    panel.emptyState = emptyState

    local emptyIcon = emptyState:CreateTexture(nil, "ARTWORK")
    emptyIcon:SetSize(48, 48)
    emptyIcon:SetPoint("CENTER", 0, 20)
    emptyIcon:SetTexture("Interface\\Icons\\INV_Misc_Token_HonorHold")
    emptyIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    emptyIcon:SetAlpha(0.3)

    local emptyText = emptyState:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyText:SetPoint("TOP", emptyIcon, "BOTTOM", 0, -8)
    emptyText:SetText("No goals set")
    emptyText:SetTextColor(unpack(COLORS.textTertiary))

    local emptyHint = emptyState:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    emptyHint:SetPoint("TOP", emptyText, "BOTTOM", 0, -4)
    emptyHint:SetText("Click + to add a gear goal")
    emptyHint:SetTextColor(unpack(COLORS.textMuted))

    -- Scroll frame for goals (handles overflow when frame is resized)
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 42) -- Leave room for totals bar (32px at y=6) + add button
    panel.scrollFrame = scrollFrame

    -- Hide scroll bar when not needed
    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"]
    if scrollBar then
        scrollBar:SetAlpha(0.6)
    end

    -- Goals container (scroll content)
    local goalsContainer = CreateFrame("Frame", nil, scrollFrame)
    goalsContainer:SetWidth(260) -- Will be updated dynamically
    scrollFrame:SetScrollChild(goalsContainer)
    panel.goalsContainer = goalsContainer

    -- Goal cards (created dynamically as needed)
    panel.goalCards = {}

    -- Function to get or create a goal card
    function panel:GetOrCreateCard(index)
        if not self.goalCards[index] then
            local card = CreateGoalCard(self.goalsContainer, index)
            card:SetPoint("TOPLEFT", PADDING, -((index - 1) * (GOAL_CARD_HEIGHT + GOAL_CARD_SPACING)))
            card:SetPoint("TOPRIGHT", -PADDING, -((index - 1) * (GOAL_CARD_HEIGHT + GOAL_CARD_SPACING)))
            card:Hide()

            -- Remove button handler
            card.removeBtn:SetScript("OnClick", function()
                if card.itemID then
                    HonorLog:RemoveGoal(card.itemID)
                    HonorLog:UpdateGoalsPanel()
                    HonorLog:ShowGoalPicker()
                end
            end)

            self.goalCards[index] = card
        end
        return self.goalCards[index]
    end

    -- Initial container height (will be updated dynamically)
    goalsContainer:SetHeight(10)

    -- Function to update scroll content width
    function panel:UpdateScrollWidth()
        local panelWidth = self:GetWidth()
        if self.goalsContainer and panelWidth > 22 then
            self.goalsContainer:SetWidth(panelWidth - 22)
        end
    end

    -- Function to update scroll bar visibility
    function panel:UpdateScrollBarVisibility()
        if not self.scrollFrame or not self.goalsContainer then return end

        local scrollBar = self.scrollFrame.ScrollBar or _G[self.scrollFrame:GetName() .. "ScrollBar"]
        if not scrollBar then return end

        local viewHeight = self.scrollFrame:GetHeight()
        local contentHeight = self.goalsContainer:GetHeight()

        if contentHeight > viewHeight then
            scrollBar:Show()
            scrollBar:SetAlpha(0.6)
        else
            scrollBar:Hide()
            self.scrollFrame:SetVerticalScroll(0)
        end
    end

    -- Totals bar (shows combined cost of all goals with progress bar)
    local totalsBar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    totalsBar:SetHeight(32)
    totalsBar:SetPoint("BOTTOMLEFT", PADDING, 6)
    totalsBar:SetPoint("BOTTOMRIGHT", -PADDING - 36, 6) -- Leave room for add button
    totalsBar:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    totalsBar:SetBackdropColor(unpack(COLORS.bgCard))
    totalsBar:SetBackdropBorderColor(unpack(COLORS.borderDark))
    panel.totalsBar = totalsBar

    -- "Total" label
    local totalsLabel = totalsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalsLabel:SetPoint("TOPLEFT", 6, -4)
    totalsLabel:SetText("Total")
    totalsLabel:SetTextColor(unpack(COLORS.textPrimary))
    panel.totalsLabel = totalsLabel

    -- Progress bar container (XP-style)
    local totalsBarContainer = CreateFrame("Frame", nil, totalsBar, "BackdropTemplate")
    totalsBarContainer:SetHeight(8)
    totalsBarContainer:SetPoint("TOPLEFT", totalsLabel, "TOPRIGHT", 6, 2)
    totalsBarContainer:SetPoint("RIGHT", -40, 0)
    totalsBarContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    totalsBarContainer:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    totalsBarContainer:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    panel.totalsBarContainer = totalsBarContainer

    -- Handle resize to update progress bar fill width
    totalsBarContainer:SetScript("OnSizeChanged", function(self)
        local percent = panel.totalsProgressPercent or 0
        local containerWidth = self:GetWidth()
        if containerWidth > 2 then
            local fillWidth = math.max(1, (containerWidth - 2) * (percent / 100))
            panel.totalsFill:SetWidth(fillWidth)
            panel.totalsShine:SetWidth(fillWidth)
        end
    end)

    -- Progress bar fill
    local totalsFill = totalsBarContainer:CreateTexture(nil, "ARTWORK")
    totalsFill:SetHeight(6)
    totalsFill:SetPoint("TOPLEFT", 1, -1)
    totalsFill:SetPoint("BOTTOMLEFT", 1, 1)
    totalsFill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    totalsFill:SetWidth(1)
    panel.totalsFill = totalsFill

    -- Shine overlay
    local totalsShine = totalsBarContainer:CreateTexture(nil, "ARTWORK", nil, 1)
    totalsShine:SetHeight(3)
    totalsShine:SetPoint("TOPLEFT", totalsFill, "TOPLEFT", 0, 0)
    totalsShine:SetPoint("TOPRIGHT", totalsFill, "TOPRIGHT", 0, 0)
    totalsShine:SetTexture("Interface\\Buttons\\WHITE8x8")
    totalsShine:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0.15), CreateColor(1, 1, 1, 0))
    panel.totalsShine = totalsShine

    -- Progress percentage
    local totalsPercent = totalsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalsPercent:SetPoint("LEFT", totalsBarContainer, "RIGHT", 4, 0)
    totalsPercent:SetWidth(32)
    totalsPercent:SetJustifyH("RIGHT")
    panel.totalsPercent = totalsPercent

    -- Currency totals text (below progress bar)
    local totalsText = totalsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalsText:SetPoint("BOTTOMLEFT", 6, 4)
    totalsText:SetPoint("RIGHT", -6, 0)
    totalsText:SetJustifyH("LEFT")
    totalsText:SetTextColor(unpack(COLORS.textSecondary))
    totalsText:SetWordWrap(false)
    totalsText:SetMaxLines(1)
    panel.totalsText = totalsText

    -- Add Goal button (aligned with totals bar)
    local addBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
    addBtn:SetSize(28, 28)
    addBtn:SetPoint("BOTTOMRIGHT", -PADDING, 8) -- Vertically centered with 32px totals bar at y=6
    addBtn:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    addBtn:SetBackdropColor(0.15, 0.35, 0.25, 0.9)
    addBtn:SetBackdropBorderColor(unpack(COLORS.brand))
    panel.addBtn = addBtn

    local addIcon = addBtn:CreateTexture(nil, "ARTWORK")
    addIcon:SetSize(16, 16)
    addIcon:SetPoint("CENTER", 0, 0)
    addIcon:SetTexture("Interface\\Buttons\\UI-PlusButton-UP")
    addBtn.icon = addIcon

    addBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.45, 0.30, 1)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Add Gear Goal")
        GameTooltip:AddLine("Set a PvP gear item as a goal to track your progress.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    addBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.35, 0.25, 0.9)
        GameTooltip:Hide()
    end)
    addBtn:SetScript("OnClick", function()
        HonorLog:ShowGoalPicker()
    end)


    -- Update function
    function panel:Update()
        local goals = HonorLog:GetAllGoalsProgress()

        if #goals == 0 then
            self.emptyState:Show()
            self.scrollFrame:Hide()
            self.totalsBar:Hide()
            for _, card in ipairs(self.goalCards) do
                card:Hide()
            end
        else
            self.emptyState:Hide()
            self.scrollFrame:Show()
            self.totalsBar:Show()

            -- Update or create cards for each goal
            for i, goal in ipairs(goals) do
                local card = self:GetOrCreateCard(i)
                card:Update(goal)
            end

            -- Hide any extra cards beyond current goal count
            for i = #goals + 1, #self.goalCards do
                self.goalCards[i]:Hide()
            end

            -- Update scroll content height based on actual goals
            local contentHeight = (#goals * GOAL_CARD_HEIGHT) + ((#goals - 1) * GOAL_CARD_SPACING) + 10
            self.goalsContainer:SetHeight(contentHeight)

            -- Calculate totals from all goals (both current and needed)
            local totalHonorNeeded = 0
            local totalHonorCurrent = 0
            local totalArenaNeeded = 0
            local totalArenaCurrent = 0
            local totalMarksNeeded = { AV = 0, AB = 0, WSG = 0, EotS = 0 }
            local totalMarksCurrent = { AV = 0, AB = 0, WSG = 0, EotS = 0 }

            for _, goal in ipairs(goals) do
                if goal.honor.needed > 0 then
                    totalHonorNeeded = totalHonorNeeded + goal.honor.needed
                    totalHonorCurrent = totalHonorCurrent + math.min(goal.honor.current, goal.honor.needed)
                end
                if goal.arena.needed > 0 then
                    totalArenaNeeded = totalArenaNeeded + goal.arena.needed
                    totalArenaCurrent = totalArenaCurrent + math.min(goal.arena.current, goal.arena.needed)
                end
                for bgType, markData in pairs(goal.marks) do
                    if markData.needed > 0 then
                        totalMarksNeeded[bgType] = totalMarksNeeded[bgType] + markData.needed
                        totalMarksCurrent[bgType] = totalMarksCurrent[bgType] + math.min(markData.current, markData.needed)
                    end
                end
            end

            -- Calculate overall progress (weighted average based on total currency needed)
            local totalNeeded = 0
            local totalCurrent = 0

            if totalHonorNeeded > 0 then
                totalNeeded = totalNeeded + totalHonorNeeded
                totalCurrent = totalCurrent + totalHonorCurrent
            end
            if totalArenaNeeded > 0 then
                totalNeeded = totalNeeded + totalArenaNeeded
                totalCurrent = totalCurrent + totalArenaCurrent
            end
            local bgOrder = { "AV", "AB", "WSG", "EotS" }
            for _, bgType in ipairs(bgOrder) do
                if totalMarksNeeded[bgType] > 0 then
                    -- Weight marks by 100 to make them comparable to honor values
                    totalNeeded = totalNeeded + (totalMarksNeeded[bgType] * 100)
                    totalCurrent = totalCurrent + (totalMarksCurrent[bgType] * 100)
                end
            end

            local overallPercent = totalNeeded > 0 and (totalCurrent / totalNeeded * 100) or 100

            -- Store progress percent for responsive resize
            self.totalsProgressPercent = overallPercent

            -- Update progress bar
            local containerWidth = self.totalsBarContainer:GetWidth()
            local fillWidth = math.max(1, (containerWidth - 2) * (overallPercent / 100))
            self.totalsFill:SetWidth(fillWidth)
            self.totalsShine:SetWidth(fillWidth)

            -- Update progress bar color and percentage text
            if overallPercent >= 100 then
                self.totalsFill:SetVertexColor(unpack(COLORS.progressFull))
                self.totalsPercent:SetText("100%")
                self.totalsPercent:SetTextColor(unpack(COLORS.progressFull))
            elseif overallPercent >= 50 then
                self.totalsFill:SetVertexColor(unpack(COLORS.progressPartial))
                self.totalsPercent:SetText(string.format("%.0f%%", overallPercent))
                self.totalsPercent:SetTextColor(unpack(COLORS.progressPartial))
            else
                self.totalsFill:SetVertexColor(unpack(COLORS.progressLow))
                self.totalsPercent:SetText(string.format("%.0f%%", overallPercent))
                self.totalsPercent:SetTextColor(unpack(COLORS.progressLow))
            end

            -- Build currency totals text (current/needed format)
            local totalParts = {}
            if totalHonorNeeded > 0 then
                local color = totalHonorCurrent >= totalHonorNeeded and "40d860" or "ffd700"
                table.insert(totalParts, string.format("|cff%s%s/%s|r H", color, BreakUpLargeNumbers(totalHonorCurrent), BreakUpLargeNumbers(totalHonorNeeded)))
            end
            if totalArenaNeeded > 0 then
                local color = totalArenaCurrent >= totalArenaNeeded and "40d860" or "aa55ff"
                table.insert(totalParts, string.format("|cff%s%d/%d|r A", color, totalArenaCurrent, totalArenaNeeded))
            end
            for _, bgType in ipairs(bgOrder) do
                if totalMarksNeeded[bgType] > 0 then
                    local color = totalMarksCurrent[bgType] >= totalMarksNeeded[bgType] and "40d860" or (BG_COLOR_HEX[bgType] or "55bbff")
                    table.insert(totalParts, string.format("|cff%s%d/%d|r %s", color, totalMarksCurrent[bgType], totalMarksNeeded[bgType], bgType))
                end
            end

            if #totalParts > 0 then
                self.totalsText:SetText(table.concat(totalParts, "  "))
            else
                self.totalsText:SetText("")
            end
        end

        -- Update scroll width and visibility
        self:UpdateScrollWidth()
        C_Timer.After(0, function()
            if self and self.UpdateScrollBarVisibility then
                self:UpdateScrollBarVisibility()
            end
        end)

        -- Update add button state
        if HonorLog:CanAddGoal() then
            self.addBtn:Enable()
            self.addBtn:SetBackdropColor(0.15, 0.35, 0.25, 0.9)
            self.addBtn:SetBackdropBorderColor(unpack(COLORS.brand))
            self.addBtn.icon:SetAlpha(1)
        else
            self.addBtn:Disable()
            self.addBtn:SetBackdropColor(0.15, 0.15, 0.18, 0.9)
            self.addBtn:SetBackdropBorderColor(unpack(COLORS.borderDark))
            self.addBtn.icon:SetAlpha(0.3)
        end

    end

    -- Update scroll on show
    panel:SetScript("OnShow", function(self)
        self:UpdateScrollWidth()
        C_Timer.After(0.1, function()
            if self and self.UpdateScrollBarVisibility then
                self:UpdateScrollBarVisibility()
            end
        end)
    end)

    -- Update scroll on size change
    panel:SetScript("OnSizeChanged", function(self, width, height)
        self:UpdateScrollWidth()
        C_Timer.After(0, function()
            if self and self.UpdateScrollBarVisibility then
                self:UpdateScrollBarVisibility()
            end
        end)
    end)

    return panel
end

--------------------------------------------------------------------------------
-- GOAL PICKER (Simple Item Selection)
--------------------------------------------------------------------------------
local goalPickerFrame = nil

local function CreateGoalPicker()
    local frame = CreateFrame("Frame", "HonorLogGoalPicker", UIParent, "BackdropTemplate")
    frame:SetSize(420, 500)
    frame:SetPoint("CENTER", 0, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(200)

    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
    frame:SetBackdropBorderColor(0.06, 0.06, 0.08, 1)

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    -- Header
    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 16, -12)
    header:SetText("Add Gear Goal")
    header:SetTextColor(unpack(COLORS.brand))

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Filter row 1: Dropdowns
    local filterLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterLabel:SetPoint("TOPLEFT", 16, -40)
    filterLabel:SetText("Filter:")
    filterLabel:SetTextColor(unpack(COLORS.textSecondary))

    -- Filter: Slot dropdown
    local slotDropdown = CreateFrame("Frame", "HonorLogSlotDropdown", frame, "UIDropDownMenuTemplate")
    slotDropdown:SetPoint("LEFT", filterLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(slotDropdown, 90)
    frame.slotDropdown = slotDropdown

    -- Filter: Season dropdown
    local seasonDropdown = CreateFrame("Frame", "HonorLogSeasonDropdown", frame, "UIDropDownMenuTemplate")
    seasonDropdown:SetPoint("LEFT", slotDropdown, "RIGHT", -10, 0)
    UIDropDownMenu_SetWidth(seasonDropdown, 90)
    frame.seasonDropdown = seasonDropdown

    -- Filter: Useable checkbox
    local useableCheck = CreateFrame("CheckButton", "HonorLogUseableCheck", frame, "UICheckButtonTemplate")
    useableCheck:SetSize(24, 24)
    useableCheck:SetPoint("LEFT", seasonDropdown, "RIGHT", 0, 0)
    useableCheck:SetChecked(true) -- Default to checked
    useableCheck.text = useableCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    useableCheck.text:SetPoint("LEFT", useableCheck, "RIGHT", 0, 0)
    useableCheck.text:SetText("Useable")
    useableCheck.text:SetTextColor(unpack(COLORS.textSecondary))
    useableCheck:SetScript("OnClick", function(self)
        frame.filterUseable = self:IsChecked()
        frame:RefreshItems()
    end)
    frame.useableCheck = useableCheck

    -- Filter row 2: Search box (full width below dropdowns)
    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 16, -68)
    searchLabel:SetText("Search:")
    searchLabel:SetTextColor(unpack(COLORS.textSecondary))

    local searchBox = CreateFrame("EditBox", "HonorLogSearchBox", frame, "InputBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(50)
    searchBox:SetTextInsets(4, 4, 0, 0)

    -- Placeholder text for search
    local placeholder = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", 6, 0)
    placeholder:SetText("Type item name...")
    placeholder:SetTextColor(0.5, 0.5, 0.5, 0.8)
    searchBox.placeholder = placeholder

    searchBox:SetScript("OnEditFocusGained", function(self)
        self.placeholder:Hide()
    end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            self.placeholder:Show()
        end
    end)

    frame.searchBox = searchBox

    -- Scroll frame for items (adjusted to start below search row)
    local scrollFrame = CreateFrame("ScrollFrame", "HonorLogGoalPickerScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -95)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 12)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollChild = scrollChild
    frame.scrollFrame = scrollFrame

    -- Set scroll child width to match scroll frame on show
    frame:SetScript("OnShow", function(self)
        local scrollWidth = self.scrollFrame:GetWidth()
        self.scrollChild:SetWidth(scrollWidth)
        self:RefreshItems()
    end)

    -- Item rows (created dynamically)
    frame.itemRows = {}

    -- Filter state
    frame.filterSlot = nil
    frame.filterSeason = nil
    frame.filterUseable = true -- Default to useable only
    frame.searchText = ""

    -- Initialize dropdowns
    local function InitSlotDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()

        info.text = "All Slots"
        info.value = nil
        info.checked = (frame.filterSlot == nil)
        info.func = function()
            frame.filterSlot = nil
            UIDropDownMenu_SetText(slotDropdown, "All Slots")
            frame:RefreshItems()
        end
        UIDropDownMenu_AddButton(info, level)

        local slots = { "HEAD", "SHOULDER", "CHEST", "HANDS", "LEGS", "WAIST", "FEET", "WRIST", "MAIN_HAND", "TWO_HAND", "RANGED", "OFF_HAND", "NECK", "FINGER", "TRINKET", "BACK", "RELIC" }
        local slotNames = {
            HEAD = "Head", SHOULDER = "Shoulder", CHEST = "Chest",
            HANDS = "Hands", LEGS = "Legs", WAIST = "Waist",
            FEET = "Feet", WRIST = "Wrist", MAIN_HAND = "Main Hand",
            TWO_HAND = "Two-Hand", OFF_HAND = "Off-Hand", RANGED = "Ranged",
            NECK = "Neck", FINGER = "Ring", TRINKET = "Trinket",
            BACK = "Back", RELIC = "Relic"
        }
        for _, slot in ipairs(slots) do
            local displayName = slotNames[slot] or slot
            info.text = displayName
            info.value = slot
            info.checked = (frame.filterSlot == slot)
            info.func = function()
                frame.filterSlot = slot
                UIDropDownMenu_SetText(slotDropdown, displayName)
                frame:RefreshItems()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    local function InitSeasonDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()

        info.text = "All Types"
        info.value = nil
        info.checked = (frame.filterSeason == nil)
        info.func = function()
            frame.filterSeason = nil
            UIDropDownMenu_SetText(seasonDropdown, "All Types")
            frame:RefreshItems()
        end
        UIDropDownMenu_AddButton(info, level)

        info.text = "Honor Only"
        info.value = "HONOR"
        info.checked = (frame.filterSeason == "HONOR")
        info.func = function()
            frame.filterSeason = "HONOR"
            UIDropDownMenu_SetText(seasonDropdown, "Honor Only")
            frame:RefreshItems()
        end
        UIDropDownMenu_AddButton(info, level)

        -- Only show non-archived seasons
        local seasons = { "PREPATCH", "S1", "S2", "S3", "S4" }
        local seasonNames = { "Prepatch", "Season 1", "Season 2", "Season 3", "Season 4" }
        for i, season in ipairs(seasons) do
            -- Skip archived seasons
            if HonorLog:IsSeasonAvailable(season) then
                info.text = seasonNames[i]
                info.value = season
                info.checked = (frame.filterSeason == season)
                info.func = function()
                    frame.filterSeason = season
                    UIDropDownMenu_SetText(seasonDropdown, seasonNames[i])
                    frame:RefreshItems()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end

    UIDropDownMenu_Initialize(slotDropdown, InitSlotDropdown)
    UIDropDownMenu_SetText(slotDropdown, "All Slots")

    UIDropDownMenu_Initialize(seasonDropdown, InitSeasonDropdown)
    UIDropDownMenu_SetText(seasonDropdown, "All Types")

    -- Search handler
    searchBox:SetScript("OnTextChanged", function(self)
        frame.searchText = self:GetText():lower()
        frame:RefreshItems()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Create item row
    local function CreateItemRow(parent, yOffset)
        local row = CreateFrame("Button", nil, parent)
        row:SetHeight(ITEM_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, yOffset)
        row:SetPoint("TOPRIGHT", 0, yOffset)

        -- Background
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.10, 0.10, 0.14, 0.9)
        row.bg = bg

        -- Bottom border for separation
        local border = row:CreateTexture(nil, "BORDER")
        border:SetHeight(1)
        border:SetPoint("BOTTOMLEFT", 0, 0)
        border:SetPoint("BOTTOMRIGHT", 0, 0)
        border:SetColorTexture(0.20, 0.20, 0.25, 0.8)
        row.border = border

        -- Icon with border
        local iconBorder = row:CreateTexture(nil, "ARTWORK")
        iconBorder:SetSize(38, 38)
        iconBorder:SetPoint("LEFT", 8, 0)
        iconBorder:SetColorTexture(0.25, 0.25, 0.30, 1)
        row.iconBorder = iconBorder

        local icon = row:CreateTexture(nil, "OVERLAY")
        icon:SetSize(36, 36)
        icon:SetPoint("CENTER", iconBorder, "CENTER", 0, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon = icon

        -- Add button (positioned first for reference)
        local addBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        addBtn:SetSize(52, 28)
        addBtn:SetPoint("RIGHT", -8, 0)
        addBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        addBtn:SetBackdropColor(0.18, 0.45, 0.28, 1)
        addBtn:SetBackdropBorderColor(0.25, 0.60, 0.35, 1)

        local addText = addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        addText:SetPoint("CENTER", 0, 0)
        addText:SetText("Add")
        addText:SetTextColor(0.85, 1.0, 0.85, 1)
        addBtn.text = addText

        addBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.25, 0.55, 0.35, 1)
        end)
        addBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.18, 0.45, 0.28, 1)
        end)
        row.addBtn = addBtn

        -- Item name (stops before Add button)
        local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        name:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 8, -4)
        name:SetPoint("RIGHT", addBtn, "LEFT", -8, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        name:SetMaxLines(1)
        row.name = name

        -- Cost line (below name)
        local costLine = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        costLine:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
        costLine:SetPoint("RIGHT", addBtn, "LEFT", -8, 0)
        costLine:SetJustifyH("LEFT")
        costLine:SetTextColor(unpack(COLORS.textSecondary))
        costLine:SetWordWrap(false)
        costLine:SetMaxLines(1)
        row.costLine = costLine

        -- Slot indicator (below cost, muted)
        local slotText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        slotText:SetPoint("TOPLEFT", costLine, "BOTTOMLEFT", 0, -2)
        slotText:SetPoint("RIGHT", addBtn, "LEFT", -8, 0)
        slotText:SetJustifyH("LEFT")
        slotText:SetTextColor(unpack(COLORS.textMuted))
        slotText:SetWordWrap(false)
        slotText:SetMaxLines(1)
        row.slotText = slotText

        -- Track shift state for compare tooltip
        row.shiftWasDown = false

        local function ShowItemTooltip(self)
            if self.itemID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(self.itemID)
                GameTooltip:Show()
                -- Show compare tooltip if shift is held
                if IsShiftKeyDown() then
                    GameTooltip_ShowCompareItem()
                    self.shiftWasDown = true
                else
                    self.shiftWasDown = false
                end
            end
        end

        row:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(0.14, 0.14, 0.20, 1)
            self.iconBorder:SetColorTexture(0.35, 0.35, 0.45, 1)
            ShowItemTooltip(self)
        end)
        row:SetScript("OnLeave", function(self)
            self.bg:SetColorTexture(0.10, 0.10, 0.14, 0.9)
            self.iconBorder:SetColorTexture(0.25, 0.25, 0.30, 1)
            GameTooltip:Hide()
            -- Hide shopping/compare tooltips
            if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
            if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
        end)
        -- Detect shift key changes while hovering
        row:SetScript("OnUpdate", function(self)
            if not self:IsMouseOver() then return end
            local shiftDown = IsShiftKeyDown()
            if shiftDown ~= self.shiftWasDown then
                ShowItemTooltip(self)
            end
        end)

        return row
    end

    -- Refresh items list
    function frame:RefreshItems()
        -- Get player class and faction
        local _, playerClass = UnitClass("player")
        local playerFaction = UnitFactionGroup("player")

        -- Determine if player is Horde based on race if faction not loaded yet
        if not playerFaction then
            local _, playerRace = UnitRace("player")
            local hordeRaces = { Orc = true, Tauren = true, Troll = true, Undead = true, Scourge = true, BloodElf = true }
            playerFaction = hordeRaces[playerRace] and "Horde" or "Alliance"
        end

        -- Armor type usability by class
        local armorTypes = {
            WARRIOR = { Plate = true, Mail = true, Leather = true, Cloth = true },
            PALADIN = { Plate = true, Mail = true, Leather = true, Cloth = true },
            HUNTER = { Mail = true, Leather = true, Cloth = true },
            SHAMAN = { Mail = true, Leather = true, Cloth = true },
            ROGUE = { Leather = true, Cloth = true },
            DRUID = { Leather = true, Cloth = true },
            MAGE = { Cloth = true },
            WARLOCK = { Cloth = true },
            PRIEST = { Cloth = true },
        }

        -- Detect armor type from item name
        local function GetArmorType(name)
            if not name then return nil end
            -- Plate keywords
            if name:find("Plate") or name:find("Lamellar") or name:find("Berserker") then return "Plate" end
            -- Mail keywords
            if name:find("Chain") or name:find("Mail") or name:find("Ringmail") or name:find("Windtalker") then return "Mail" end
            -- Leather keywords
            if name:find("Leather") or name:find("Lizardhide") or name:find("Dragonhide") or name:find("Forest Stalker") then return "Leather" end
            -- Cloth keywords
            if name:find("Cloth") or name:find("Silk") or name:find("Satin") or name:find("Mooncloth") or name:find("Dryad") or name:find("Epaulets") then return "Cloth" end
            return nil -- Unknown or universal (weapons, trinkets, etc.)
        end

        -- Filter items
        local filteredItems = {}
        for itemID, data in pairs(HonorLog.GearDB or {}) do
            local passFilter = true

            -- Class filter (only show usable items if filter is enabled)
            if self.filterUseable and data.class and data.class ~= playerClass then
                passFilter = false
            end

            -- Armor type filter (only if useable filter is enabled)
            if passFilter and self.filterUseable then
                local armorType = GetArmorType(data.name)
                if armorType then
                    local canWear = armorTypes[playerClass]
                    if canWear and not canWear[armorType] then
                        passFilter = false
                    end
                end
            end

            -- Faction filter for faction-specific PvP gear
            if passFilter and data.name then
                local itemName = data.name
                -- Horde-only items: High Warlord (R14), Warlord's (R12-13), Defiler (AB), Outrider/Legionnaire/Advisor/Scout (WSG), Frostwolf (AV)
                if itemName:find("High Warlord") or itemName:find("Warlord's") or itemName:find("Defiler") or
                   itemName:find("Outrider") or itemName:find("Legionnaire") or itemName:find("Advisor") or itemName:find("Scout's") or
                   itemName:find("Frostwolf") or itemName:find("Warsong Battle") or itemName:find("Deathguard") then
                    if playerFaction ~= "Horde" then
                        passFilter = false
                    end
                -- Alliance-only items: Grand Marshal (R14), Field Marshal (R12-13), Highlander (AB), Sentinel/Silverwing (WSG), Stormpike (AV)
                elseif itemName:find("Grand Marshal") or itemName:find("Field Marshal") or itemName:find("Highlander") or
                       itemName:find("Sentinel") or itemName:find("Silverwing") or itemName:find("Stormpike") then
                    if playerFaction ~= "Alliance" then
                        passFilter = false
                    end
                end
                -- Gladiator's gear is faction-neutral, no filter needed
            end

            -- Filter out archived seasons (TBC gear not yet available)
            if passFilter and not HonorLog:IsSeasonAvailable(data.season) then
                passFilter = false
            end

            -- Slot filter
            if passFilter and self.filterSlot and data.slot ~= self.filterSlot then
                passFilter = false
            end

            -- Season filter
            if passFilter and self.filterSeason then
                if self.filterSeason == "HONOR" then
                    if data.season or data.arena > 0 then
                        passFilter = false
                    end
                elseif data.season ~= self.filterSeason then
                    passFilter = false
                end
            end

            -- Search filter
            if passFilter and self.searchText and self.searchText ~= "" then
                local name = data.name or ""
                if not name:lower():find(self.searchText, 1, true) then
                    passFilter = false
                end
            end

            -- Already a goal?
            if passFilter and HonorLog:IsGoal(itemID) then
                passFilter = false
            end

            if passFilter then
                table.insert(filteredItems, { itemID = itemID, data = data })
            end
        end

        -- Sort by slot, then name
        table.sort(filteredItems, function(a, b)
            if a.data.slot ~= b.data.slot then
                return a.data.slot < b.data.slot
            end
            return (a.data.name or "") < (b.data.name or "")
        end)

        -- Clear existing rows
        for _, row in ipairs(self.itemRows) do
            row:Hide()
        end

        -- Create/update rows
        local yOffset = 0
        for i, item in ipairs(filteredItems) do
            local row = self.itemRows[i]
            if not row then
                row = CreateItemRow(self.scrollChild, yOffset)
                self.itemRows[i] = row
            end

            row:SetPoint("TOPLEFT", 0, yOffset)
            row:SetPoint("TOPRIGHT", 0, yOffset)

            local itemID = item.itemID
            local data = item.data
            row.itemID = itemID

            -- Get item info
            local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
            if itemTexture then
                row.icon:SetTexture(itemTexture)
            else
                row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                C_Item.RequestLoadItemDataByID(itemID)
            end

            row.name:SetText(data.name or itemName or "Item " .. itemID)

            -- Build compact cost line: Honor + Arena + Marks (abbreviated)
            local costParts = {}
            if data.honor > 0 then
                table.insert(costParts, string.format("|cffffd700%s|r |cffbbaa55H|r", BreakUpLargeNumbers(data.honor)))
            end
            if data.arena > 0 then
                table.insert(costParts, string.format("|cffaa55ff%d|r |cff8844ccA|r", data.arena))
            end
            if data.marks then
                local bgOrder = { "AV", "AB", "WSG", "EotS" }
                for _, bgType in ipairs(bgOrder) do
                    local count = data.marks[bgType]
                    if count and count > 0 then
                        local colorHex = BG_COLOR_HEX[bgType] or "55bbff"
                        table.insert(costParts, string.format("|cff%s%d %s|r", colorHex, count, bgType))
                    end
                end
            end
            row.costLine:SetText(table.concat(costParts, " "))

            -- Slot indicator (formatted nicely)
            local slotNames = {
                HEAD = "Head", SHOULDER = "Shoulder", CHEST = "Chest",
                HANDS = "Hands", LEGS = "Legs", WAIST = "Waist",
                FEET = "Feet", WRIST = "Wrist", MAIN_HAND = "Main Hand",
                TWO_HAND = "Two-Hand", OFF_HAND = "Off-Hand", RANGED = "Ranged",
                NECK = "Neck", FINGER = "Ring", TRINKET = "Trinket",
                BACK = "Back", RELIC = "Relic"
            }
            row.slotText:SetText(slotNames[data.slot] or data.slot or "")

            -- Add button handler
            row.addBtn:SetScript("OnClick", function()
                local success, err = HonorLog:AddGoal(itemID)
                if success then
                    print(string.format("|cff00ff00[HonorLog]|r Added goal: %s", data.name or "Unknown"))
                    frame:RefreshItems()
                    HonorLog:UpdateGoalsPanel()

                    -- Close picker if max goals reached
                    if not HonorLog:CanAddGoal() then
                        frame:Hide()
                    end
                else
                    print(string.format("|cffff0000[HonorLog]|r %s", err or "Could not add goal"))
                end
            end)

            row:Show()
            yOffset = yOffset - (ITEM_ROW_HEIGHT + 2)
        end

        -- Update scroll child height
        self.scrollChild:SetHeight(math.max(1, math.abs(yOffset)))
    end

    frame:Hide()
    return frame
end

--------------------------------------------------------------------------------
-- INTEGRATION WITH MAIN FRAME
--------------------------------------------------------------------------------
function HonorLog:InitializeGoalsUI()
    if not self.mainFrame then return end

    local frame = self.mainFrame
    local header = frame.header

    -- Store original expanded content
    frame.statsView = frame.expanded
    frame.currentView = "stats"

    -- Hide the view mode badge to make room for tabs
    if frame.viewModeBg then frame.viewModeBg:Hide() end
    if frame.viewMode then frame.viewMode:Hide() end

    -- Create tab buttons (anchored from right side, before expand button)
    local goalsTab = CreateTabButton(header, "Goals", false)
    goalsTab:SetPoint("RIGHT", frame.expandBtn, "LEFT", -4, 0)
    goalsTab:SetActive(false)
    frame.goalsTab = goalsTab

    local statsTab = CreateTabButton(header, "Stats", true)
    statsTab:SetPoint("RIGHT", goalsTab, "LEFT", -2, 0)
    statsTab:SetActive(true)
    frame.statsTab = statsTab

    -- Create goals panel
    frame.goalsPanel = CreateGoalsPanel(frame)
    frame.goalsPanel:SetPoint("TOPLEFT", frame.compact, "BOTTOMLEFT", 0, -2)
    frame.goalsPanel:SetPoint("TOPRIGHT", frame.compact, "BOTTOMRIGHT", 0, -2)
    frame.goalsPanel:SetPoint("BOTTOM", 0, 5)

    -- Tab click handlers
    statsTab:SetScript("OnClick", function()
        self:SwitchTab("stats")
    end)

    goalsTab:SetScript("OnClick", function()
        self:SwitchTab("goals")
    end)

    -- Update when data changes
    local originalOnDataUpdated = self.OnDataUpdated
    self.OnDataUpdated = function(addon)
        if originalOnDataUpdated then
            originalOnDataUpdated(addon)
        end
        self:UpdateMainFrame()
        if frame.currentView == "goals" then
            self:UpdateGoalsPanel()
        end
    end
end

function HonorLog:SwitchTab(tabName)
    local frame = self.mainFrame
    if not frame then return end

    frame.currentView = tabName

    if tabName == "stats" then
        frame.statsTab:SetActive(true)
        frame.goalsTab:SetActive(false)
        frame.statsView:Show()
        frame.goalsPanel:Hide()
    else
        frame.statsTab:SetActive(false)
        frame.goalsTab:SetActive(true)
        frame.statsView:Hide()
        frame.goalsPanel:Show()
        self:UpdateGoalsPanel()
    end

    -- Ensure frame is expanded when switching tabs
    if not self.db.settings.frameExpanded then
        self:SetExpanded(true)
    end
end

function HonorLog:UpdateGoalsPanel()
    if self.mainFrame and self.mainFrame.goalsPanel then
        self.mainFrame.goalsPanel:Update()
    end
end

function HonorLog:ShowGoalPicker()
    if not goalPickerFrame then
        goalPickerFrame = CreateGoalPicker()
    end

    goalPickerFrame:Show()
    goalPickerFrame:RefreshItems()
end
