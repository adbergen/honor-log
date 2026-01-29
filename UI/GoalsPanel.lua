-- HonorLog Goals Panel
-- UI for gear goal tracking

local ADDON_NAME, HonorLog = ...

--------------------------------------------------------------------------------
-- ANIMATION UTILITIES
--------------------------------------------------------------------------------
local activeAnimations = {}

-- Smooth easing function (ease-out quad)
local function EaseOutQuad(t)
    return t * (2 - t)
end

-- Smooth easing function (ease-in-out)
local function EaseInOutQuad(t)
    if t < 0.5 then
        return 2 * t * t
    else
        return 1 - (-2 * t + 2) ^ 2 / 2
    end
end

-- Animate a value from start to target over duration
local function AnimateValue(id, startVal, targetVal, duration, onUpdate, onComplete)
    -- Cancel any existing animation with same ID
    if activeAnimations[id] then
        activeAnimations[id].cancelled = true
    end

    local animation = {
        startVal = startVal,
        targetVal = targetVal,
        duration = duration,
        elapsed = 0,
        onUpdate = onUpdate,
        onComplete = onComplete,
        cancelled = false,
    }

    activeAnimations[id] = animation

    -- Parent to UIParent to ensure OnUpdate events are received in TBC Classic
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetScript("OnUpdate", function(self, elapsed)
        if animation.cancelled then
            self:SetScript("OnUpdate", nil)
            activeAnimations[id] = nil
            return
        end

        animation.elapsed = animation.elapsed + elapsed
        local progress = math.min(animation.elapsed / animation.duration, 1)
        local easedProgress = EaseOutQuad(progress)
        local currentVal = animation.startVal + (animation.targetVal - animation.startVal) * easedProgress

        if animation.onUpdate then
            animation.onUpdate(currentVal, progress)
        end

        if progress >= 1 then
            self:SetScript("OnUpdate", nil)
            activeAnimations[id] = nil
            if animation.onComplete then
                animation.onComplete()
            end
        end
    end)

    return animation
end

-- Cancel an animation by ID
local function CancelAnimation(id)
    if activeAnimations[id] then
        activeAnimations[id].cancelled = true
        activeAnimations[id] = nil
    end
end

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
-- Drag state for reordering
local draggedCard = nil
local dragStartY = 0
local originalIndex = 0
local dragFrame = nil -- Floating drag frame
local dropIndicator = nil -- Legacy (kept for cleanup)
local currentGapIndex = nil -- Current position where gap is shown during drag
local animateProgressOnNextUpdate = false -- Flag to force progress bar animation after reorder
local animateCardsOnNextUpdate = false -- Flag to animate card positions after reorder
local affectedPositionRange = nil -- {min, max} range of card positions affected by reorder
local animateOnTabSwitch = false -- Flag to animate all progress bars when switching to Goals tab

-- Animate cards to create a visual gap at the specified index
-- Cards animate smoothly to their new positions during drag
local CARD_MOVE_DURATION = 0.25  -- Smooth animation duration

local function AnimateCardsForGap(goalsPanel, gapIndex, draggedIndex)
    if not goalsPanel or not goalsPanel.goalCards then return end

    local cardHeight = GOAL_CARD_HEIGHT + GOAL_CARD_SPACING

    for i, card in pairs(goalsPanel.goalCards) do
        if card and card:IsShown() and card.cardIndex and not card.isDragging then
            local visualIndex = card.cardIndex
            local targetY

            -- Determine if this card needs to shift to make room
            if gapIndex then
                if draggedIndex < gapIndex then
                    -- Dragging down: cards between old and new position shift UP
                    if visualIndex > draggedIndex and visualIndex <= gapIndex then
                        targetY = -((visualIndex - 2) * cardHeight)
                    else
                        targetY = -((visualIndex - 1) * cardHeight)
                    end
                elseif draggedIndex > gapIndex then
                    -- Dragging up: cards between new and old position shift DOWN
                    if visualIndex >= gapIndex and visualIndex < draggedIndex then
                        targetY = -(visualIndex * cardHeight)
                    else
                        targetY = -((visualIndex - 1) * cardHeight)
                    end
                else
                    -- Gap is at original position - normal positions
                    targetY = -((visualIndex - 1) * cardHeight)
                end
            else
                targetY = -((visualIndex - 1) * cardHeight)
            end

            -- Get current Y position (for animation start)
            local currentY = card.currentAnimY or -((visualIndex - 1) * cardHeight)

            -- Only animate if position actually changed
            if math.abs(currentY - targetY) > 0.5 then
                -- Cancel any existing animation for this card
                local animId = "card_drag_" .. (card.cardIndex or i)
                CancelAnimation(animId)

                -- Animate to new position
                AnimateValue(animId, currentY, targetY, CARD_MOVE_DURATION, function(val)
                    card.currentAnimY = val
                    card:ClearAllPoints()
                    card:SetPoint("TOPLEFT", PADDING, val)
                    card:SetPoint("TOPRIGHT", -PADDING, val)
                end, function()
                    card.currentAnimY = targetY
                end)
            end
        end
    end
end

-- Reset all cards to their natural positions
local function ResetCardPositions(goalsPanel)
    if not goalsPanel or not goalsPanel.goalCards then return end

    local cardHeight = GOAL_CARD_HEIGHT + GOAL_CARD_SPACING

    for i, card in pairs(goalsPanel.goalCards) do
        if card and card:IsShown() and card.cardIndex then
            -- Cancel any running drag animation for this card
            local animId = "card_drag_" .. (card.cardIndex or i)
            CancelAnimation(animId)

            local targetY = -((card.cardIndex - 1) * cardHeight)
            card.currentAnimY = targetY  -- Reset tracking
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", PADDING, targetY)
            card:SetPoint("TOPRIGHT", -PADDING, targetY)
        end
    end
end

-- Create the floating drag frame (created once, reused)
local function GetDragFrame()
    if not dragFrame then
        dragFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        dragFrame:SetFrameStrata("TOOLTIP")
        dragFrame:SetSize(200, GOAL_CARD_HEIGHT)

        -- Outer glow/shadow effect
        local shadow = CreateFrame("Frame", nil, dragFrame, "BackdropTemplate")
        shadow:SetPoint("TOPLEFT", -4, 4)
        shadow:SetPoint("BOTTOMRIGHT", 4, -4)
        shadow:SetFrameLevel(dragFrame:GetFrameLevel() - 1)
        shadow:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeSize = 6,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        shadow:SetBackdropColor(0, 0, 0, 0.5)
        shadow:SetBackdropBorderColor(0, 0, 0, 0.35)
        dragFrame.shadow = shadow

        dragFrame:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        dragFrame:SetBackdropColor(0.18, 0.20, 0.25, 0.98)
        dragFrame:SetBackdropBorderColor(1, 0.82, 0.2, 1) -- Gold border
        dragFrame:Hide()

        -- Highlight glow at top
        local glow = dragFrame:CreateTexture(nil, "ARTWORK")
        glow:SetHeight(GOAL_CARD_HEIGHT / 2)
        glow:SetPoint("TOPLEFT", 1, -1)
        glow:SetPoint("TOPRIGHT", -1, -1)
        glow:SetTexture("Interface\\Buttons\\WHITE8x8")
        glow:SetGradient("VERTICAL", CreateColor(1, 0.9, 0.5, 0.12), CreateColor(1, 0.9, 0.5, 0))
        dragFrame.glow = glow

        -- Icon (slightly larger)
        local icon = dragFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(36, 36)
        icon:SetPoint("LEFT", 10, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        dragFrame.icon = icon

        -- Name (larger font)
        local name = dragFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        name:SetPoint("RIGHT", -10, 0)
        name:SetJustifyH("LEFT")
        dragFrame.itemName = name
    end
    return dragFrame
end

-- Create drop indicator line
local function GetDropIndicator(parent)
    if not dropIndicator then
        dropIndicator = CreateFrame("Frame", nil, parent)
        dropIndicator:SetHeight(3)

        local line = dropIndicator:CreateTexture(nil, "OVERLAY")
        line:SetAllPoints()
        line:SetColorTexture(1, 0.8, 0, 0.8) -- Gold line

        -- Left arrow
        local leftArrow = dropIndicator:CreateTexture(nil, "OVERLAY")
        leftArrow:SetSize(8, 8)
        leftArrow:SetPoint("RIGHT", dropIndicator, "LEFT", 2, 0)
        leftArrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")
        leftArrow:SetRotation(math.rad(90))

        -- Right arrow
        local rightArrow = dropIndicator:CreateTexture(nil, "OVERLAY")
        rightArrow:SetSize(8, 8)
        rightArrow:SetPoint("LEFT", dropIndicator, "RIGHT", -2, 0)
        rightArrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")
        rightArrow:SetRotation(math.rad(-90))

        dropIndicator:Hide()
    end
    dropIndicator:SetParent(parent)
    return dropIndicator
end

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
        if not draggedCard then
            self:SetBackdropColor(unpack(COLORS.bgCardHover))
            self:SetBackdropBorderColor(unpack(COLORS.borderAccent))
            ShowCardTooltip(self)
        end
    end)
    card:SetScript("OnLeave", function(self)
        if not draggedCard then
            self:SetBackdropColor(unpack(COLORS.bgCard))
            self:SetBackdropBorderColor(unpack(COLORS.borderDark))
            GameTooltip:Hide()
            if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
            if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
        end
    end)
    card:SetScript("OnUpdate", function(self)
        if not self:IsMouseOver() then return end
        if draggedCard then return end
        local shiftDown = IsShiftKeyDown()
        if shiftDown ~= self.shiftWasDown then
            ShowCardTooltip(self)
        end
    end)

    -- Drag handle (left side grip) - extends to icon edge to prevent click-through
    local dragHandle = CreateFrame("Button", nil, card)
    dragHandle:SetSize(24, GOAL_CARD_HEIGHT)
    dragHandle:SetPoint("LEFT", 0, 0)
    card.dragHandle = dragHandle  -- Store reference early for frame level updates

    -- 6-dot grip pattern (2 columns × 3 rows) - standard drag handle icon
    local dotSize = 3
    local dotSpacingX = 5  -- horizontal spacing between columns
    local dotSpacingY = 5  -- vertical spacing between rows
    for row = 1, 3 do
        for col = 1, 2 do
            local dot = dragHandle:CreateTexture(nil, "ARTWORK")
            dot:SetSize(dotSize, dotSize)
            local xOffset = (col - 1.5) * dotSpacingX  -- center the 2 columns
            local yOffset = (row - 2) * dotSpacingY    -- center the 3 rows
            dot:SetPoint("CENTER", xOffset, -yOffset)
            dot:SetColorTexture(0.5, 0.5, 0.5, 0.6)
        end
    end

    dragHandle:SetScript("OnEnter", function(self)
        for i = 1, 6 do
            local dot = select(i, self:GetRegions())
            if dot and dot.SetColorTexture then
                dot:SetColorTexture(0.8, 0.8, 0.8, 0.9)
            end
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Drag to reorder")
        GameTooltip:Show()
    end)
    dragHandle:SetScript("OnLeave", function(self)
        for i = 1, 6 do
            local dot = select(i, self:GetRegions())
            if dot and dot.SetColorTexture then
                dot:SetColorTexture(0.5, 0.5, 0.5, 0.6)
            end
        end
        GameTooltip:Hide()
    end)

    dragHandle:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and card.cardIndex then
            draggedCard = card
            originalIndex = card.cardIndex
            currentGapIndex = card.cardIndex
            dragStartY = select(2, GetCursorPosition()) / card:GetEffectiveScale()
            GameTooltip:Hide()

            -- Mark card as being dragged and make invisible
            card.isDragging = true
            card:SetAlpha(0)

            -- Show and populate the floating drag frame
            local df = GetDragFrame()
            local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(card.itemID)
            df.icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
            df.itemName:SetText(card.itemName:GetText() or itemName or "Unknown")
            df:SetWidth(card:GetWidth())

            -- Show drag frame with lift animation
            df:SetScale(1.0)
            df:SetAlpha(0)
            df:Show()

            -- Animate lift effect (scale up + fade in)
            local LIFT_DURATION = 0.12
            AnimateValue("drag_lift", 0, 1, LIFT_DURATION, function(progress)
                df:SetScale(1.0 + 0.03 * progress)  -- Scale from 1.0 to 1.03
                df:SetAlpha(0.95 * progress)  -- Fade in
            end)

            -- Position drag frame so it appears under the cursor at the grab point
            -- Anchor by LEFT side with offset so the card doesn't jump to center on cursor
            local cursorX, cursorY = GetCursorPosition()
            local scale = df:GetEffectiveScale()
            df:ClearAllPoints()
            df:SetPoint("LEFT", UIParent, "BOTTOMLEFT", (cursorX / scale) - 12, cursorY / scale)

            -- Initialize gap at original position
            local goalsPanel = HonorLog.mainFrame and HonorLog.mainFrame.goalsPanel
            if goalsPanel then
                AnimateCardsForGap(goalsPanel, currentGapIndex, originalIndex)
            end
        end
    end)

    dragHandle:SetScript("OnUpdate", function(self)
        if draggedCard ~= card then return end

        local df = GetDragFrame()
        if df:IsShown() then
            -- Move drag frame with cursor (LEFT anchor with offset to match grab point)
            local cursorX, cursorY = GetCursorPosition()
            local scale = df:GetEffectiveScale()
            df:ClearAllPoints()
            df:SetPoint("LEFT", UIParent, "BOTTOMLEFT", (cursorX / scale) - 12, cursorY / scale)

            -- Calculate target drop position and move cards to create gap
            local goalsPanel = HonorLog.mainFrame and HonorLog.mainFrame.goalsPanel
            if goalsPanel and goalsPanel.goalsContainer then
                local cardHeight = GOAL_CARD_HEIGHT + GOAL_CARD_SPACING

                -- Calculate which position the cursor is over
                local containerY = select(2, goalsPanel.goalsContainer:GetCenter()) * goalsPanel.goalsContainer:GetEffectiveScale()
                local containerTop = containerY + (goalsPanel.goalsContainer:GetHeight() / 2) * goalsPanel.goalsContainer:GetEffectiveScale()
                local relativeY = (containerTop - cursorY) / goalsPanel.goalsContainer:GetEffectiveScale()

                -- Use rounding (floor + 0.5) so target switches at midpoint of each card slot
                -- This makes the drop feel more natural - you don't have to drag as far
                local targetIndex = math.floor(relativeY / cardHeight + 0.5) + 1
                local goalCount = HonorLog:GetGoalCount()
                targetIndex = math.max(1, math.min(goalCount, targetIndex))

                -- Move cards to create visual gap at target position
                if targetIndex ~= currentGapIndex then
                    currentGapIndex = targetIndex
                    AnimateCardsForGap(goalsPanel, currentGapIndex, originalIndex)
                end

                draggedCard.targetIndex = targetIndex
            end
        end
    end)

    dragHandle:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and draggedCard == card then
            local df = GetDragFrame()
            local goalsPanel = HonorLog.mainFrame and HonorLog.mainFrame.goalsPanel

            -- Use the current gap position as drop target
            local newIndex = currentGapIndex or originalIndex
            local goalCount = HonorLog:GetGoalCount()
            newIndex = math.max(1, math.min(goalCount, newIndex))

            -- Clear all drag state immediately
            draggedCard = nil
            currentGapIndex = nil
            card.targetIndex = nil
            card.isDragging = nil

            -- Cancel all card gap animations
            if goalsPanel and goalsPanel.goalCards then
                for i, c in pairs(goalsPanel.goalCards) do
                    if c and c.cardIndex then
                        CancelAnimation("card_drag_" .. c.cardIndex)
                    end
                end
            end

            -- Calculate target position for drop animation
            local canAnimatePosition = false
            local startX, startY, endX, endY

            if goalsPanel and goalsPanel.goalsContainer then
                local containerLeft = goalsPanel.goalsContainer:GetLeft()
                local containerTop = goalsPanel.goalsContainer:GetTop()
                startX = df:GetLeft()
                startY = df:GetTop()

                if containerLeft and containerTop and startX and startY then
                    local cardHeight = GOAL_CARD_HEIGHT + GOAL_CARD_SPACING
                    local targetY = -((newIndex - 1) * cardHeight)
                    endX = containerLeft + PADDING
                    endY = containerTop + targetY
                    canAnimatePosition = true
                end
            end

            if canAnimatePosition then
                -- Animate drag frame to target position with settle effect
                local MOVE_DURATION = 0.18
                local startScale = df:GetScale()
                AnimateValue("drop_move", 0, 1, MOVE_DURATION, function(progress)
                    local currentX = startX + (endX - startX) * progress
                    local currentY = startY + (endY - startY) * progress
                    df:ClearAllPoints()
                    df:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", currentX, currentY)
                    -- Scale settles back to 1.0
                    df:SetScale(startScale + (1.0 - startScale) * progress)
                end, function()
                    -- Position animation complete, now fade out
                    df:SetScale(1.0)
                    local FADE_DURATION = 0.08
                    AnimateValue("drop_fade", 0.95, 0, FADE_DURATION, function(alpha)
                        df:SetAlpha(alpha)
                    end, function()
                        df:Hide()
                        df:SetAlpha(0.95)

                        -- Perform reorder if position changed
                        if newIndex ~= originalIndex and card.itemID then
                            HonorLog:ReorderGoal(card.itemID, newIndex)
                            animateProgressOnNextUpdate = true
                            animateCardsOnNextUpdate = true
                            -- Track which positions are affected (inclusive range)
                            affectedPositionRange = {
                                min = math.min(originalIndex, newIndex),
                                max = math.max(originalIndex, newIndex)
                            }
                        end

                        -- Update panel to reflect new order
                        HonorLog:UpdateGoalsPanel()
                    end)
                end)
            else
                -- Fallback: scale settle + fade out
                local FADE_DURATION = 0.15
                local startScale = df:GetScale()
                AnimateValue("drop_fade", 0, 1, FADE_DURATION, function(progress)
                    df:SetAlpha(0.95 * (1 - progress))
                    df:SetScale(startScale + (1.0 - startScale) * progress)
                end, function()
                    df:Hide()
                    df:SetAlpha(0.95)
                    df:SetScale(1.0)

                    if newIndex ~= originalIndex and card.itemID then
                        HonorLog:ReorderGoal(card.itemID, newIndex)
                        animateProgressOnNextUpdate = true
                        animateCardsOnNextUpdate = true
                        -- Track which positions are affected (inclusive range)
                        affectedPositionRange = {
                            min = math.min(originalIndex, newIndex),
                            max = math.max(originalIndex, newIndex)
                        }
                    end
                    HonorLog:UpdateGoalsPanel()
                end)
            end
        end
    end)

    -- Item icon (positioned after drag handle)
    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", 24, -8)
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
    function card:Update(goalProgress, cardIndex)
        if not goalProgress then
            self:Hide()
            return
        end

        self:Show()
        if not self.isDragging then
            self:SetAlpha(1) -- Ensure card is fully visible (reset from any drag animation)
        end

        -- Store itemID and index for drag/drop reordering
        self.itemID = goalProgress.itemID
        self.cardIndex = cardIndex or goalProgress.priority or 1

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

        -- Calculate overall progress using weighted average (same as totals bar)
        local totalNeeded = 0
        local totalCurrent = 0
        local parts = {}

        if goalProgress.honor.needed > 0 then
            totalNeeded = totalNeeded + goalProgress.honor.needed
            totalCurrent = totalCurrent + math.min(goalProgress.honor.current, goalProgress.honor.needed)
            if goalProgress.honor.remaining > 0 then
                -- Not enough yet - show in gold
                table.insert(parts, string.format("|cffffd700%d/%d Honor|r", goalProgress.honor.current, goalProgress.honor.needed))
            else
                -- Have enough - show in green
                table.insert(parts, string.format("|cff40d860%d/%d Honor|r", goalProgress.honor.current, goalProgress.honor.needed))
            end
        end

        if goalProgress.arena.needed > 0 then
            totalNeeded = totalNeeded + goalProgress.arena.needed
            totalCurrent = totalCurrent + math.min(goalProgress.arena.current, goalProgress.arena.needed)
            if goalProgress.arena.remaining > 0 then
                -- Not enough yet - show in purple
                table.insert(parts, string.format("|cffaa55ff%d/%d Arena|r", goalProgress.arena.current, goalProgress.arena.needed))
            else
                -- Have enough - show in green
                table.insert(parts, string.format("|cff40d860%d/%d Arena|r", goalProgress.arena.current, goalProgress.arena.needed))
            end
        end

        -- Process marks in consistent order with BG-specific colors
        for _, bgType in ipairs(HonorLog.BG_ORDER) do
            local markData = goalProgress.marks[bgType]
            if markData then
                -- Weight marks by 100 to make them comparable to honor values
                totalNeeded = totalNeeded + (markData.needed * 100)
                totalCurrent = totalCurrent + (math.min(markData.current, markData.needed) * 100)
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

        -- Calculate weighted percentage
        local overallPercent = totalNeeded > 0 and (totalCurrent / totalNeeded * 100) or 100

        -- Store previous progress for animation
        local previousPercent = self.progressPercent or 0
        local previousItemID = self.previousItemID
        self.progressPercent = overallPercent
        self.previousItemID = itemID

        -- Update XP-style progress bar with animation
        local containerWidth = self.barContainer:GetWidth()

        -- If container hasn't been laid out yet (width is 0 or too small), defer progress bar update
        if containerWidth < 10 then
            local savedPercent = overallPercent
            C_Timer.After(0, function()
                if self and self.barContainer and self:IsShown() then
                    local width = self.barContainer:GetWidth()
                    if width >= 10 then
                        local fillWidth = math.max(1, (width - 2) * (savedPercent / 100))
                        self.progressFill:SetWidth(fillWidth)
                        self.progressShine:SetWidth(fillWidth)
                        if savedPercent > 0 and savedPercent < 100 then
                            self.progressSpark:SetPoint("CENTER", self.progressFill, "RIGHT", 0, 0)
                            self.progressSpark:Show()
                        end
                    end
                end
            end)
        else
            local targetWidth = math.max(1, (containerWidth - 2) * (overallPercent / 100))
            local currentWidth = self.progressFill:GetWidth() or 1

            -- Check if we should force animation (after reorder or tab switch)
            -- Only animate if this card is within the affected position range (for reorder)
            -- Or animate all cards on tab switch
            local cardIndex = self.cardIndex or 0
            local inAffectedRange = affectedPositionRange and
                cardIndex >= affectedPositionRange.min and
                cardIndex <= affectedPositionRange.max
            local forceAnimateReorder = animateProgressOnNextUpdate and inAffectedRange
            local forceAnimateTabSwitch = animateOnTabSwitch
            local forceAnimate = forceAnimateReorder or forceAnimateTabSwitch
            local itemChanged = previousItemID and previousItemID ~= itemID

            -- Animate width change
            local widthDiff = math.abs(targetWidth - currentWidth)
            local normalAnimate = widthDiff > 2 and previousPercent > 0 and not itemChanged

            if forceAnimate or (normalAnimate and targetWidth > 1) then
                local animId = "progress_" .. (self.cardIndex or 0)
                CancelAnimation(animId)

                local fill = self.progressFill
                local shine = self.progressShine
                local spark = self.progressSpark
                local progressText = self.progressText
                local currencyLine = self.currencyLine
                local completeIcon = self.completeIcon

                -- For reorder/tab switch, start from minimum width for a fresh fill animation
                local startWidth = forceAnimate and 1 or currentWidth
                local startPercent = forceAnimate and 0 or previousPercent
                local targetPercent = overallPercent

                -- Store currency targets for animation
                local honorCurrent = goalProgress.honor.current
                local honorNeeded = goalProgress.honor.needed
                local arenaCurrent = goalProgress.arena.current
                local arenaNeeded = goalProgress.arena.needed
                local marksData = goalProgress.marks

                AnimateValue(animId, 0, 1, 0.8, function(progress)
                    if fill and fill:IsShown() then
                        -- Animate width
                        local currentWidthVal = startWidth + (targetWidth - startWidth) * progress
                        fill:SetWidth(currentWidthVal)
                        shine:SetWidth(currentWidthVal)

                        -- Animate percentage text
                        local currentPercent = startPercent + (targetPercent - startPercent) * progress
                        if currentPercent >= 100 then
                            progressText:SetText("100%")
                        else
                            progressText:SetText(string.format("%.0f%%", currentPercent))
                        end

                        -- Animate currency line values
                        local animParts = {}
                        if honorNeeded > 0 then
                            local animHonor = math.floor(honorCurrent * progress)
                            local color = animHonor >= honorNeeded and "40d860" or "ffd700"
                            table.insert(animParts, string.format("|cff%s%d/%d Honor|r", color, animHonor, honorNeeded))
                        end
                        if arenaNeeded > 0 then
                            local animArena = math.floor(arenaCurrent * progress)
                            local color = animArena >= arenaNeeded and "40d860" or "aa55ff"
                            table.insert(animParts, string.format("|cff%s%d/%d Arena|r", color, animArena, arenaNeeded))
                        end
                        for _, bgType in ipairs(HonorLog.BG_ORDER) do
                            local markData = marksData[bgType]
                            if markData and markData.needed > 0 then
                                local animMarks = math.floor(markData.current * progress)
                                local color = animMarks >= markData.needed and "40d860" or (BG_COLOR_HEX[bgType] or "55bbff")
                                table.insert(animParts, string.format("|cff%s%d/%d %s|r", color, animMarks, markData.needed, bgType))
                            end
                        end
                        if #animParts > 0 then
                            currencyLine:SetText(table.concat(animParts, "  |cff666666·|r  "))
                        end

                        -- Animate color based on current percentage
                        local r, g, b
                        if currentPercent >= 100 then
                            r, g, b = unpack(COLORS.progressFull)
                        elseif currentPercent >= 50 then
                            local t = (currentPercent - 50) / 50
                            local lowR, lowG, lowB = unpack(COLORS.progressPartial)
                            local highR, highG, highB = unpack(COLORS.progressFull)
                            r = lowR + (highR - lowR) * t
                            g = lowG + (highG - lowG) * t
                            b = lowB + (highB - lowB) * t
                        else
                            local t = currentPercent / 50
                            local lowR, lowG, lowB = unpack(COLORS.progressLow)
                            local highR, highG, highB = unpack(COLORS.progressPartial)
                            r = lowR + (highR - lowR) * t
                            g = lowG + (highG - lowG) * t
                            b = lowB + (highB - lowB) * t
                        end
                        fill:SetVertexColor(r, g, b)
                        progressText:SetTextColor(r, g, b)

                        -- Update spark position during animation
                        if currentPercent > 0 and currentPercent < 100 then
                            spark:SetPoint("CENTER", fill, "RIGHT", 0, 0)
                            spark:Show()
                        else
                            spark:Hide()
                        end
                    end
                end, function()
                    -- Ensure final state is correct
                    if overallPercent >= 100 then
                        completeIcon:Show()
                    else
                        completeIcon:Hide()
                    end
                end)
            else
                self.progressFill:SetWidth(targetWidth)
                self.progressShine:SetWidth(targetWidth)

                -- Set percentage and color directly (no animation)
                local r, g, b
                if overallPercent >= 100 then
                    r, g, b = unpack(COLORS.progressFull)
                    self.progressText:SetText("100%")
                    self.completeIcon:Show()
                elseif overallPercent >= 50 then
                    local t = (overallPercent - 50) / 50
                    local lowR, lowG, lowB = unpack(COLORS.progressPartial)
                    local highR, highG, highB = unpack(COLORS.progressFull)
                    r = lowR + (highR - lowR) * t
                    g = lowG + (highG - lowG) * t
                    b = lowB + (highB - lowB) * t
                    self.progressText:SetText(string.format("%.0f%%", overallPercent))
                    self.completeIcon:Hide()
                else
                    local t = overallPercent / 50
                    local lowR, lowG, lowB = unpack(COLORS.progressLow)
                    local highR, highG, highB = unpack(COLORS.progressPartial)
                    r = lowR + (highR - lowR) * t
                    g = lowG + (highG - lowG) * t
                    b = lowB + (highB - lowB) * t
                    self.progressText:SetText(string.format("%.0f%%", overallPercent))
                    self.completeIcon:Hide()
                end
                self.progressFill:SetVertexColor(r, g, b)
                self.progressText:SetTextColor(r, g, b)

                -- Position spark
                if overallPercent > 0 and overallPercent < 100 then
                    self.progressSpark:SetPoint("CENTER", self.progressFill, "RIGHT", 0, 0)
                    self.progressSpark:Show()
                else
                    self.progressSpark:Hide()
                end
            end
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
    scrollFrame:SetPoint("TOPLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 44) -- Leave room for totals bar (32px at y=6) + add button + padding
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
            local yOffset = -((index - 1) * (GOAL_CARD_HEIGHT + GOAL_CARD_SPACING))
            card:SetPoint("TOPLEFT", PADDING, yOffset)
            card:SetPoint("TOPRIGHT", -PADDING, yOffset)
            card.currentAnimY = yOffset  -- Initialize animation tracking
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
    totalsBar:SetPoint("BOTTOMRIGHT", -44, 6) -- Leave room for add button
    totalsBar:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    totalsBar:SetBackdropColor(unpack(COLORS.bgCard))
    totalsBar:SetBackdropBorderColor(unpack(COLORS.borderDark))
    panel.totalsBar = totalsBar

    -- Subtle top highlight for depth
    local totalsHighlight = totalsBar:CreateTexture(nil, "ARTWORK", nil, -1)
    totalsHighlight:SetHeight(1)
    totalsHighlight:SetPoint("TOPLEFT", 1, -1)
    totalsHighlight:SetPoint("TOPRIGHT", -1, -1)
    totalsHighlight:SetTexture("Interface\\Buttons\\WHITE8x8")
    totalsHighlight:SetVertexColor(1, 1, 1, 0.06)

    -- "Total" label (positioned in top half of bar)
    local totalsLabel = totalsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalsLabel:SetPoint("TOPLEFT", 6, -5)
    totalsLabel:SetText("Total")
    totalsLabel:SetTextColor(unpack(COLORS.textPrimary))
    panel.totalsLabel = totalsLabel

    -- Progress bar container (XP-style, positioned in top half of bar)
    -- Anchored directly to totals bar with fixed offset (after "Total" label ~35px)
    local totalsBarContainer = CreateFrame("Frame", nil, totalsBar, "BackdropTemplate")
    totalsBarContainer:SetHeight(8)
    totalsBarContainer:SetPoint("TOPLEFT", 42, -4)
    totalsBarContainer:SetPoint("TOPRIGHT", -40, -4)
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
            if panel.totalsGlow then panel.totalsGlow:SetWidth(fillWidth + 4) end
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

    -- Inner glow effect for more vibrant bar
    local totalsGlow = totalsBarContainer:CreateTexture(nil, "ARTWORK", nil, -1)
    totalsGlow:SetHeight(10)
    totalsGlow:SetPoint("TOPLEFT", totalsFill, "TOPLEFT", -2, 2)
    totalsGlow:SetPoint("BOTTOMLEFT", totalsFill, "BOTTOMLEFT", -2, -2)
    totalsGlow:SetWidth(3)
    totalsGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
    totalsGlow:SetGradient("HORIZONTAL", CreateColor(0.2, 0.8, 0.3, 0.3), CreateColor(0.2, 0.8, 0.3, 0))
    panel.totalsGlow = totalsGlow

    -- Shine overlay
    local totalsShine = totalsBarContainer:CreateTexture(nil, "ARTWORK", nil, 1)
    totalsShine:SetHeight(3)
    totalsShine:SetPoint("TOPLEFT", totalsFill, "TOPLEFT", 0, 0)
    totalsShine:SetPoint("TOPRIGHT", totalsFill, "TOPRIGHT", 0, 0)
    totalsShine:SetTexture("Interface\\Buttons\\WHITE8x8")
    totalsShine:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0.2), CreateColor(1, 1, 1, 0))
    panel.totalsShine = totalsShine

    -- Spark at end of bar (XP bar effect)
    local totalsSpark = totalsBarContainer:CreateTexture(nil, "OVERLAY")
    totalsSpark:SetSize(8, 16)
    totalsSpark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    totalsSpark:SetBlendMode("ADD")
    totalsSpark:SetAlpha(0.7)
    totalsSpark:Hide()
    panel.totalsSpark = totalsSpark

    -- Progress percentage (positioned in top half)
    local totalsPercent = totalsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalsPercent:SetPoint("TOPRIGHT", -6, -5)
    totalsPercent:SetWidth(32)
    totalsPercent:SetJustifyH("RIGHT")
    panel.totalsPercent = totalsPercent

    -- Currency totals text (below progress bar row)
    local totalsText = totalsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalsText:SetPoint("BOTTOMLEFT", 6, 4)
    totalsText:SetPoint("BOTTOMRIGHT", -6, 4)
    totalsText:SetJustifyH("LEFT")
    totalsText:SetTextColor(unpack(COLORS.textSecondary))
    totalsText:SetWordWrap(false)
    totalsText:SetMaxLines(1)
    panel.totalsText = totalsText

    -- Footer add button (small "+" button next to totals bar)
    local footerAddBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
    footerAddBtn:SetSize(32, 32)
    footerAddBtn:SetPoint("BOTTOMRIGHT", -PADDING, 6)
    footerAddBtn:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    footerAddBtn:SetBackdropColor(unpack(COLORS.bgCard))
    footerAddBtn:SetBackdropBorderColor(unpack(COLORS.borderDark))
    panel.footerAddBtn = footerAddBtn

    local footerAddIcon = footerAddBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    footerAddIcon:SetPoint("CENTER", 0, 0)
    footerAddIcon:SetText("+")
    footerAddIcon:SetTextColor(unpack(COLORS.textSecondary))
    footerAddBtn.icon = footerAddIcon

    footerAddBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(COLORS.bgCardHover))
        self:SetBackdropBorderColor(unpack(COLORS.borderLight))
        self.icon:SetTextColor(unpack(COLORS.textPrimary))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Add Goal")
        GameTooltip:Show()
    end)
    footerAddBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(COLORS.bgCard))
        self:SetBackdropBorderColor(unpack(COLORS.borderDark))
        self.icon:SetTextColor(unpack(COLORS.textSecondary))
        GameTooltip:Hide()
    end)
    footerAddBtn:SetScript("OnClick", function()
        HonorLog:ShowGoalPicker()
    end)

    -- Add Goal row (inline at bottom of goals list in scroll area)
    local addGoalRow = CreateFrame("Button", nil, goalsContainer, "BackdropTemplate")
    addGoalRow:SetHeight(28)
    addGoalRow:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    addGoalRow:SetBackdropColor(0.10, 0.10, 0.12, 0.6)
    addGoalRow:SetBackdropBorderColor(unpack(COLORS.borderDark))
    panel.addGoalRow = addGoalRow

    -- Plus icon
    local addIcon = addGoalRow:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    addIcon:SetPoint("LEFT", 10, 0)
    addIcon:SetText("+")
    addIcon:SetTextColor(unpack(COLORS.textTertiary))
    addGoalRow.addIcon = addIcon

    -- "Add Goal" text
    local addLabel = addGoalRow:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    addLabel:SetPoint("LEFT", addIcon, "RIGHT", 6, 0)
    addLabel:SetText("Add Goal")
    addLabel:SetTextColor(unpack(COLORS.textTertiary))
    addGoalRow.addLabel = addLabel

    addGoalRow:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.14, 0.14, 0.18, 0.9)
        self:SetBackdropBorderColor(unpack(COLORS.borderLight))
        self.addIcon:SetTextColor(unpack(COLORS.textSecondary))
        self.addLabel:SetTextColor(unpack(COLORS.textSecondary))
    end)
    addGoalRow:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.10, 0.10, 0.12, 0.6)
        self:SetBackdropBorderColor(unpack(COLORS.borderDark))
        self.addIcon:SetTextColor(unpack(COLORS.textTertiary))
        self.addLabel:SetTextColor(unpack(COLORS.textTertiary))
    end)
    addGoalRow:SetScript("OnClick", function()
        HonorLog:ShowGoalPicker()
    end)


    -- Update function
    function panel:Update()
        local goals = HonorLog:GetAllGoalsProgress()

        if #goals == 0 then
            self.emptyState:Show()
            self.scrollFrame:Hide()
            self.totalsBar:Hide()
            self.footerAddBtn:Show() -- Keep visible so users can add goals
            self.addGoalRow:Hide()
            for _, card in ipairs(self.goalCards) do
                card:Hide()
            end
        else
            self.emptyState:Hide()
            self.scrollFrame:Show()
            self.totalsBar:Show()
            self.footerAddBtn:Show()

            -- Fade in totals bar on tab switch (after cards start fading)
            if animateOnTabSwitch then
                self.totalsBar:SetAlpha(0)
                local totalsDelay = #goals * 0.08 + 0.1 -- Start after last card begins + small buffer
                C_Timer.After(totalsDelay, function()
                    if self.totalsBar and self.totalsBar:IsShown() then
                        AnimateValue("totals_fade", 0, 1, 0.3, function(alpha)
                            if self.totalsBar then
                                self.totalsBar:SetAlpha(alpha)
                            end
                        end)
                    end
                end)
            end

            -- Update or create cards for each goal
            local cardHeight = GOAL_CARD_HEIGHT + GOAL_CARD_SPACING
            local baseLevel = self.goalsContainer:GetFrameLevel() + 1
            local totalGoals = #goals

            for i, goal in ipairs(goals) do
                local card = self:GetOrCreateCard(i)
                card:Update(goal, i)

                -- During active drag, preserve animated positions
                if not draggedCard then
                    local targetY = -((i - 1) * cardHeight)

                    -- Animate cards to their positions after drop
                    if animateCardsOnNextUpdate and card.currentAnimY then
                        local startY = card.currentAnimY
                        local animId = "card_settle_" .. i
                        CancelAnimation(animId)

                        AnimateValue(animId, 0, 1, 0.2, function(progress)
                            local currentY = startY + (targetY - startY) * progress
                            card.currentAnimY = currentY
                            card:ClearAllPoints()
                            card:SetPoint("TOPLEFT", PADDING, currentY)
                            card:SetPoint("TOPRIGHT", -PADDING, currentY)
                        end, function()
                            card.currentAnimY = targetY
                        end)
                    else
                        -- Set card position directly
                        card:ClearAllPoints()
                        card:SetPoint("TOPLEFT", PADDING, targetY)
                        card:SetPoint("TOPRIGHT", -PADDING, targetY)
                        card.currentAnimY = targetY
                    end
                end

                -- Cards higher in the list get higher frame levels for correct click targeting
                -- This ensures clicking on card 1 doesn't accidentally target card 2's drag handle
                local cardLevel = baseLevel + (totalGoals - i) * 2
                card:SetFrameLevel(cardLevel)
                if card.dragHandle then
                    card.dragHandle:SetFrameLevel(cardLevel + 1)
                end

                -- Ensure full opacity (in case drag was interrupted)
                -- Sequential fade-in on tab switch
                if not card.isDragging then
                    if animateOnTabSwitch then
                        -- Start invisible and fade in with staggered delay
                        card:SetAlpha(0)
                        local delay = (i - 1) * 0.08 -- 80ms stagger between cards
                        local fadeAnimId = "card_fade_" .. i
                        CancelAnimation(fadeAnimId)
                        C_Timer.After(delay, function()
                            if card and card:IsShown() then
                                AnimateValue(fadeAnimId, 0, 1, 0.3, function(alpha)
                                    if card and card:IsShown() and not card.isDragging then
                                        card:SetAlpha(alpha)
                                    end
                                end)
                            end
                        end)
                    else
                        card:SetAlpha(1)
                    end
                end
            end

            -- Hide any extra cards beyond current goal count
            for i = #goals + 1, #self.goalCards do
                self.goalCards[i]:Hide()
            end

            -- Hide the scroll area add row (button is in footer now)
            self.addGoalRow:Hide()

            -- Update scroll content height based on actual goals
            local contentHeight = (#goals * cardHeight) + PADDING
            self.goalsContainer:SetHeight(contentHeight)

            -- Calculate totals from all goals
            -- Sum up what's NEEDED from each goal
            local totalHonorNeeded = 0
            local totalArenaNeeded = 0
            local totalMarksNeeded = { AV = 0, AB = 0, WSG = 0, EotS = 0 }

            for _, goal in ipairs(goals) do
                if goal.honor.needed > 0 then
                    totalHonorNeeded = totalHonorNeeded + goal.honor.needed
                end
                if goal.arena.needed > 0 then
                    totalArenaNeeded = totalArenaNeeded + goal.arena.needed
                end
                for bgType, markData in pairs(goal.marks) do
                    if markData.needed > 0 then
                        totalMarksNeeded[bgType] = totalMarksNeeded[bgType] + markData.needed
                    end
                end
            end

            -- Get actual player currency (not multiplied per goal)
            local totalHonorCurrent = math.min(HonorLog:GetCurrentHonor(), totalHonorNeeded)
            local totalArenaCurrent = math.min(HonorLog:GetCurrentArenaPoints(), totalArenaNeeded)
            local totalMarksCurrent = {}
            for bgType, needed in pairs(totalMarksNeeded) do
                totalMarksCurrent[bgType] = math.min(HonorLog:GetCurrentMarks(bgType), needed)
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
            for _, bgType in ipairs(HonorLog.BG_ORDER) do
                if totalMarksNeeded[bgType] > 0 then
                    -- Weight marks by 100 to make them comparable to honor values
                    totalNeeded = totalNeeded + (totalMarksNeeded[bgType] * 100)
                    totalCurrent = totalCurrent + (totalMarksCurrent[bgType] * 100)
                end
            end

            local overallPercent = totalNeeded > 0 and (totalCurrent / totalNeeded * 100) or 100

            -- Store previous progress and currency values for animation
            local previousPercent = self.totalsProgressPercent or 0
            local prevHonor = self.totalsPrevHonor or 0
            local prevArena = self.totalsPrevArena or 0
            local prevMarks = self.totalsPrevMarks or {}

            self.totalsProgressPercent = overallPercent
            self.totalsPrevHonor = totalHonorCurrent
            self.totalsPrevArena = totalArenaCurrent
            self.totalsPrevMarks = {}
            for bgType, val in pairs(totalMarksCurrent) do
                self.totalsPrevMarks[bgType] = val
            end

            -- Update progress bar with animation
            local containerWidth = self.totalsBarContainer:GetWidth()
            local targetWidth = math.max(1, (containerWidth - 2) * (overallPercent / 100))
            local currentWidth = self.totalsFill:GetWidth() or 1

            -- Animate width change with counting effect
            local widthDiff = math.abs(targetWidth - currentWidth)
            local honorChanged = math.abs(totalHonorCurrent - prevHonor) > 0
            local arenaChanged = math.abs(totalArenaCurrent - prevArena) > 0
            local marksChanged = false
            for bgType, val in pairs(totalMarksCurrent) do
                if math.abs(val - (prevMarks[bgType] or 0)) > 0 then
                    marksChanged = true
                    break
                end
            end
            local currencyChanged = honorChanged or arenaChanged or marksChanged
            local forceAnimateTabSwitch = animateOnTabSwitch

            if forceAnimateTabSwitch or ((widthDiff > 2 or currencyChanged) and previousPercent > 0) then
                local animId = "totals_progress"
                CancelAnimation(animId)

                local fill = self.totalsFill
                local shine = self.totalsShine
                local glow = self.totalsGlow
                local spark = self.totalsSpark
                local percentText = self.totalsPercent
                local currencyText = self.totalsText

                -- For tab switch, start from 0; otherwise from current values
                local startWidth = forceAnimateTabSwitch and 1 or currentWidth
                local startPercent = forceAnimateTabSwitch and 0 or previousPercent
                local targetPercent = overallPercent

                -- Store start values for currency animation (0 on tab switch)
                local startHonor = forceAnimateTabSwitch and 0 or prevHonor
                local startArena = forceAnimateTabSwitch and 0 or prevArena
                local startMarks = forceAnimateTabSwitch and {} or prevMarks

                AnimateValue(animId, 0, 1, 1.0, function(progress)
                    if fill and fill:IsShown() then
                        -- Animate width
                        local currentWidthVal = startWidth + (targetWidth - startWidth) * progress
                        fill:SetWidth(currentWidthVal)
                        shine:SetWidth(currentWidthVal)
                        if glow then glow:SetWidth(currentWidthVal + 4) end

                        -- Animate percentage text
                        local currentPercent = startPercent + (targetPercent - startPercent) * progress
                        if currentPercent >= 100 then
                            percentText:SetText("100%")
                        else
                            percentText:SetText(string.format("%.0f%%", currentPercent))
                        end

                        -- Animate color based on current percentage
                        local r, g, b
                        if currentPercent >= 100 then
                            r, g, b = unpack(COLORS.progressFull)
                        elseif currentPercent >= 50 then
                            local t = (currentPercent - 50) / 50
                            local lowR, lowG, lowB = unpack(COLORS.progressPartial)
                            local highR, highG, highB = unpack(COLORS.progressFull)
                            r = lowR + (highR - lowR) * t
                            g = lowG + (highG - lowG) * t
                            b = lowB + (highB - lowB) * t
                        else
                            local t = currentPercent / 50
                            local lowR, lowG, lowB = unpack(COLORS.progressLow)
                            local highR, highG, highB = unpack(COLORS.progressPartial)
                            r = lowR + (highR - lowR) * t
                            g = lowG + (highG - lowG) * t
                            b = lowB + (highB - lowB) * t
                        end
                        fill:SetVertexColor(r, g, b)
                        percentText:SetTextColor(r, g, b)
                        if glow then
                            glow:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.4), CreateColor(r, g, b, 0))
                        end

                        -- Animate currency values from previous to current
                        local animParts = {}
                        if totalHonorNeeded > 0 then
                            local animHonor = math.floor(startHonor + (totalHonorCurrent - startHonor) * progress)
                            local color = animHonor >= totalHonorNeeded and "40d860" or "ffd700"
                            table.insert(animParts, string.format("|cff%s%s/%s|r H", color, BreakUpLargeNumbers(animHonor), BreakUpLargeNumbers(totalHonorNeeded)))
                        end
                        if totalArenaNeeded > 0 then
                            local animArena = math.floor(startArena + (totalArenaCurrent - startArena) * progress)
                            local color = animArena >= totalArenaNeeded and "40d860" or "aa55ff"
                            table.insert(animParts, string.format("|cff%s%d/%d|r A", color, animArena, totalArenaNeeded))
                        end
                        for _, bgType in ipairs(HonorLog.BG_ORDER) do
                            if totalMarksNeeded[bgType] > 0 then
                                local prevMark = startMarks[bgType] or 0
                                local animMarks = math.floor(prevMark + (totalMarksCurrent[bgType] - prevMark) * progress)
                                local color = animMarks >= totalMarksNeeded[bgType] and "40d860" or (BG_COLOR_HEX[bgType] or "55bbff")
                                table.insert(animParts, string.format("|cff%s%d/%d|r %s", color, animMarks, totalMarksNeeded[bgType], bgType))
                            end
                        end
                        if #animParts > 0 then
                            currencyText:SetText(table.concat(animParts, "  "))
                        end

                        -- Update spark position during animation
                        if spark and currentPercent > 0 and currentPercent < 100 then
                            spark:SetPoint("CENTER", fill, "RIGHT", 0, 0)
                            spark:Show()
                        elseif spark then
                            spark:Hide()
                        end
                    end
                end)
            else
                self.totalsFill:SetWidth(targetWidth)
                self.totalsShine:SetWidth(targetWidth)
                if self.totalsGlow then self.totalsGlow:SetWidth(targetWidth + 4) end

                -- Position spark at end of fill (XP bar effect)
                if self.totalsSpark then
                    if overallPercent > 0 and overallPercent < 100 then
                        self.totalsSpark:SetPoint("CENTER", self.totalsFill, "RIGHT", 0, 0)
                        self.totalsSpark:Show()
                    else
                        self.totalsSpark:Hide()
                    end
                end

                -- Update progress bar color directly (no animation)
                local r, g, b
                if overallPercent >= 100 then
                    r, g, b = unpack(COLORS.progressFull)
                    self.totalsPercent:SetText("100%")
                elseif overallPercent >= 50 then
                    local t = (overallPercent - 50) / 50
                    local lowR, lowG, lowB = unpack(COLORS.progressPartial)
                    local highR, highG, highB = unpack(COLORS.progressFull)
                    r = lowR + (highR - lowR) * t
                    g = lowG + (highG - lowG) * t
                    b = lowB + (highB - lowB) * t
                    self.totalsPercent:SetText(string.format("%.0f%%", overallPercent))
                else
                    local t = overallPercent / 50
                    local lowR, lowG, lowB = unpack(COLORS.progressLow)
                    local highR, highG, highB = unpack(COLORS.progressPartial)
                    r = lowR + (highR - lowR) * t
                    g = lowG + (highG - lowG) * t
                    b = lowB + (highB - lowB) * t
                    self.totalsPercent:SetText(string.format("%.0f%%", overallPercent))
                end

                self.totalsFill:SetVertexColor(r, g, b)
                self.totalsPercent:SetTextColor(r, g, b)
                if self.totalsGlow then
                    self.totalsGlow:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.4), CreateColor(r, g, b, 0))
                end

                -- Build currency totals text directly (no animation)
                local totalParts = {}
                if totalHonorNeeded > 0 then
                    local color = totalHonorCurrent >= totalHonorNeeded and "40d860" or "ffd700"
                    table.insert(totalParts, string.format("|cff%s%s/%s|r H", color, BreakUpLargeNumbers(totalHonorCurrent), BreakUpLargeNumbers(totalHonorNeeded)))
                end
                if totalArenaNeeded > 0 then
                    local color = totalArenaCurrent >= totalArenaNeeded and "40d860" or "aa55ff"
                    table.insert(totalParts, string.format("|cff%s%d/%d|r A", color, totalArenaCurrent, totalArenaNeeded))
                end
                for _, bgType in ipairs(HonorLog.BG_ORDER) do
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
        end

        -- Update scroll width and visibility
        self:UpdateScrollWidth()
        C_Timer.After(0, function()
            if self and self.UpdateScrollBarVisibility then
                self:UpdateScrollBarVisibility()
            end
        end)

        -- Clear animation flags after update completes
        animateProgressOnNextUpdate = false
        animateCardsOnNextUpdate = false
        affectedPositionRange = nil
        animateOnTabSwitch = false

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

    -- Clean up drag state when panel hides
    panel:SetScript("OnHide", function(self)
        -- Reset all card alphas
        if self.goalCards then
            for _, card in pairs(self.goalCards) do
                if card then card:SetAlpha(1) end
            end
        end

        if draggedCard then
            draggedCard:SetAlpha(1)
            draggedCard.targetIndex = nil
            draggedCard = nil
        end
        if dragFrame then
            dragFrame:Hide()
        end
        if dropIndicator then
            dropIndicator:Hide()
        end
        currentGapIndex = nil
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

    -- Make frame resizable
    frame:SetResizable(true)
    frame:SetResizeBounds(320, 300, 600, 700)

    -- Resize grip (bottom-right corner)
    local resizeGrip = CreateFrame("Button", nil, frame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", -6, 6)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:EnableMouse(true)
    resizeGrip:SetScript("OnMouseDown", function(self)
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function(self)
        frame:StopMovingOrSizing()
        -- Update scroll child width
        local scrollWidth = frame.scrollFrame:GetWidth()
        frame.scrollChild:SetWidth(scrollWidth)
    end)
    frame.resizeGrip = resizeGrip

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

    -- Filter row 2: Search box
    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 16, -68)
    searchLabel:SetText("Search:")
    searchLabel:SetTextColor(unpack(COLORS.textSecondary))

    local searchBox = CreateFrame("EditBox", "HonorLogSearchBox", frame, "InputBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)

    -- Filter row 3: Checkboxes (below search)
    local useableCheck = CreateFrame("CheckButton", "HonorLogUseableCheck", frame, "UICheckButtonTemplate")
    useableCheck:SetSize(24, 24)
    useableCheck:SetPoint("TOPLEFT", 16, -92)
    useableCheck:SetChecked(true)
    useableCheck.text = useableCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    useableCheck.text:SetPoint("LEFT", useableCheck, "RIGHT", 0, 0)
    useableCheck.text:SetText("Useable")
    useableCheck.text:SetTextColor(unpack(COLORS.textSecondary))
    useableCheck:SetScript("OnClick", function(self)
        frame.filterUseable = self:GetChecked()
        frame:RefreshItems()
    end)
    frame.useableCheck = useableCheck

    local hideOwnedCheck = CreateFrame("CheckButton", "HonorLogHideOwnedCheck", frame, "UICheckButtonTemplate")
    hideOwnedCheck:SetSize(24, 24)
    hideOwnedCheck:SetPoint("LEFT", useableCheck, "RIGHT", 70, 0)
    hideOwnedCheck:SetChecked(false)
    hideOwnedCheck.text = hideOwnedCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hideOwnedCheck.text:SetPoint("LEFT", hideOwnedCheck, "RIGHT", 0, 0)
    hideOwnedCheck.text:SetText("Hide Owned")
    hideOwnedCheck.text:SetTextColor(unpack(COLORS.textSecondary))
    hideOwnedCheck:SetScript("OnClick", function(self)
        frame.filterHideOwned = self:GetChecked()
        frame:RefreshItems()
    end)
    frame.hideOwnedCheck = hideOwnedCheck

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

    -- Scroll frame for items (adjusted to start below checkbox row)
    local scrollFrame = CreateFrame("ScrollFrame", "HonorLogGoalPickerScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -118)
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

    -- Update scroll child width on resize
    frame:SetScript("OnSizeChanged", function(self)
        local scrollWidth = self.scrollFrame:GetWidth()
        self.scrollChild:SetWidth(scrollWidth)
        -- Update item row widths
        for _, row in ipairs(self.itemRows) do
            if row:IsShown() then
                row:SetWidth(scrollWidth)
            end
        end
    end)

    -- Item rows (created dynamically)
    frame.itemRows = {}

    -- Filter state
    frame.filterSlot = nil
    frame.filterSeason = nil
    frame.filterUseable = true -- Default to useable only
    frame.filterHideOwned = false -- Default to showing all items
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

        -- Add button (modern dark theme style)
        local addBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        addBtn:SetSize(52, 28)
        addBtn:SetPoint("RIGHT", -8, 0)
        addBtn:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        addBtn:SetBackdropColor(0.14, 0.14, 0.18, 1)
        addBtn:SetBackdropBorderColor(0.30, 0.30, 0.38, 0.8)

        local addText = addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        addText:SetPoint("CENTER", 0, 0)
        addText:SetText("Add")
        addText:SetTextColor(unpack(COLORS.textSecondary))
        addBtn.text = addText

        addBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.20, 0.20, 0.26, 1)
            self:SetBackdropBorderColor(unpack(COLORS.borderLight))
            self.text:SetTextColor(unpack(COLORS.textPrimary))
        end)
        addBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.14, 0.14, 0.18, 1)
            self:SetBackdropBorderColor(0.30, 0.30, 0.38, 0.8)
            self.text:SetTextColor(unpack(COLORS.textSecondary))
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
        slotText:SetJustifyH("LEFT")
        slotText:SetTextColor(unpack(COLORS.textMuted))
        slotText:SetWordWrap(false)
        slotText:SetMaxLines(1)
        row.slotText = slotText

        -- Owned badge (shown when player has the item)
        local ownedBadge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ownedBadge:SetPoint("LEFT", slotText, "RIGHT", 6, 0)
        ownedBadge:SetText("|cff40d860|TInterface\\RAIDFRAME\\ReadyCheck-Ready:0|t Owned|r")
        ownedBadge:Hide()
        row.ownedBadge = ownedBadge

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

        -- Weapon subtype usability by class (matches GetItemInfo() itemSubType values)
        local weaponSubtypes = {
            WARRIOR = {
                ["One-Handed Axes"] = true, ["Two-Handed Axes"] = true,
                ["One-Handed Swords"] = true, ["Two-Handed Swords"] = true,
                ["One-Handed Maces"] = true, ["Two-Handed Maces"] = true,
                ["Daggers"] = true, ["Fist Weapons"] = true, ["Polearms"] = true,
                ["Staves"] = true, ["Bows"] = true, ["Crossbows"] = true, ["Guns"] = true,
                ["Thrown"] = true,
            },
            PALADIN = {
                ["One-Handed Axes"] = true, ["Two-Handed Axes"] = true,
                ["One-Handed Swords"] = true, ["Two-Handed Swords"] = true,
                ["One-Handed Maces"] = true, ["Two-Handed Maces"] = true,
                ["Polearms"] = true,
            },
            HUNTER = {
                ["One-Handed Axes"] = true, ["Two-Handed Axes"] = true,
                ["One-Handed Swords"] = true, ["Two-Handed Swords"] = true,
                ["Daggers"] = true, ["Fist Weapons"] = true, ["Polearms"] = true,
                ["Staves"] = true, ["Bows"] = true, ["Crossbows"] = true, ["Guns"] = true,
                ["Thrown"] = true,
            },
            SHAMAN = {
                ["One-Handed Axes"] = true, ["Two-Handed Axes"] = true,
                ["One-Handed Maces"] = true, ["Two-Handed Maces"] = true,
                ["Daggers"] = true, ["Fist Weapons"] = true, ["Staves"] = true,
            },
            ROGUE = {
                ["One-Handed Swords"] = true, ["One-Handed Maces"] = true,
                ["Daggers"] = true, ["Fist Weapons"] = true,
                ["Bows"] = true, ["Crossbows"] = true, ["Guns"] = true, ["Thrown"] = true,
            },
            DRUID = {
                ["One-Handed Maces"] = true, ["Two-Handed Maces"] = true,
                ["Daggers"] = true, ["Fist Weapons"] = true, ["Polearms"] = true,
                ["Staves"] = true,
            },
            MAGE = {
                ["One-Handed Swords"] = true, ["Daggers"] = true, ["Staves"] = true,
                ["Wands"] = true,
            },
            WARLOCK = {
                ["One-Handed Swords"] = true, ["Daggers"] = true, ["Staves"] = true,
                ["Wands"] = true,
            },
            PRIEST = {
                ["One-Handed Maces"] = true, ["Daggers"] = true, ["Staves"] = true,
                ["Wands"] = true,
            },
        }

        -- Get weapon subtype from item using WoW API
        local function GetWeaponSubtype(itemID, slot)
            if not itemID or not slot then return nil end
            -- Only check weapon slots
            if slot ~= "MAIN_HAND" and slot ~= "OFF_HAND" and slot ~= "TWO_HAND" and slot ~= "RANGED" then
                return nil
            end
            -- GetItemInfo returns: name, link, quality, ilvl, minLevel, type, subType, ...
            local _, _, _, _, _, itemType, itemSubType = GetItemInfo(itemID)
            if itemType == "Weapon" then
                return itemSubType
            end
            return nil
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

            -- Weapon type filter (only if useable filter is enabled)
            if passFilter and self.filterUseable then
                local weaponSubtype = GetWeaponSubtype(itemID, data.slot)
                if weaponSubtype then
                    local canUse = weaponSubtypes[playerClass]
                    if canUse and not canUse[weaponSubtype] then
                        passFilter = false
                    end
                end
            end

            -- Faction filter for faction-specific PvP gear (ALWAYS applied regardless of Useable filter)
            -- Exception: Paladin/Shaman class gear is NOT faction-filtered because TBC prepatch
            -- added Blood Elf Paladins (Horde) and Draenei Shamans (Alliance)
            if passFilter and data.name then
                local itemName = data.name

                -- Skip faction filter for Paladin/Shaman class-specific gear (cross-faction classes in TBC)
                -- Exception: Insignias are still faction-locked at vendors
                local isCrossFactionClassGear = (data.class == "PALADIN" or data.class == "SHAMAN")
                    and not itemName:find("Insignia")

                if not isCrossFactionClassGear then
                    -- Horde-only items:
                    -- - High Warlord (R14 weapons), Warlord's (head/shoulder/chest)
                    -- - General's (hands/legs/feet)
                    -- - Defiler's (AB reputation), Deathguard
                    -- - Outrider's, Legionnaire's, Advisor's, Scout's, Battle Healer's (WSG reputation)
                    -- - Frostwolf, Warsong Battle (AV/WSG reputation)
                    -- - Blood Guard, Champion's
                    local isHordeItem = itemName:find("High Warlord") or itemName:find("Warlord's") or
                        itemName:find("General's") or
                        itemName:find("Defiler") or itemName:find("Outrider") or itemName:find("Legionnaire") or
                        itemName:find("Advisor") or itemName:find("Scout's") or itemName:find("Battle Healer") or
                        itemName:find("Frostwolf") or itemName:find("Warsong Battle") or
                        itemName:find("Deathguard") or itemName:find("Blood Guard") or itemName:find("Champion's") or
                        itemName:find("Insignia of the Horde")

                    -- Alliance-only items:
                    -- - Grand Marshal (R14 weapons), Field Marshal's (head/shoulder/chest)
                    -- - Marshal's (hands/legs/feet)
                    -- - Highlander's, Arathor, Sageclaw (AB reputation)
                    -- - Sentinel's, Silverwing, Protector's, Lorekeeper, Caretaker, Outrunner (WSG reputation)
                    -- - Stormpike (AV reputation)
                    -- - Knight-, Lieutenant
                    -- - Insignia of the Alliance
                    local isAllianceItem = itemName:find("Grand Marshal") or itemName:find("Marshal's") or
                        itemName:find("Highlander") or itemName:find("Arathor") or itemName:find("Sageclaw") or
                        itemName:find("Sentinel") or itemName:find("Silverwing") or
                        itemName:find("Protector's") or itemName:find("Lorekeeper") or
                        itemName:find("Caretaker") or itemName:find("Outrunner") or
                        itemName:find("Stormpike") or itemName:find("Knight%-") or itemName:find("Lieutenant") or
                        itemName:find("Honor Guard") or itemName:find("Insignia of the Alliance")

                    if isHordeItem and playerFaction ~= "Horde" then
                        passFilter = false
                    elseif isAllianceItem and playerFaction ~= "Alliance" then
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

            -- Hide owned filter
            if passFilter and self.filterHideOwned then
                local ownedCount = GetItemCount(itemID, true) -- true = include bank
                if ownedCount > 0 then
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
                for _, bgType in ipairs(HonorLog.BG_ORDER) do
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

            -- Check if player owns this item
            local ownedCount = GetItemCount(itemID, true) -- true = include bank
            if ownedCount > 0 then
                row.ownedBadge:Show()
            else
                row.ownedBadge:Hide()
            end

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

    -- Update tab visual states
    if tabName == "stats" then
        frame.statsTab:SetActive(true)
        frame.goalsTab:SetActive(false)
    else
        frame.statsTab:SetActive(false)
        frame.goalsTab:SetActive(true)
    end

    -- Update compact view content
    if self.UpdateCompactView then
        self:UpdateCompactView()
    end

    -- Handle expanded views based on frame state
    if self.db.settings.frameExpanded then
        if tabName == "stats" then
            -- Switch to stats view
            if frame.goalsPanel then
                frame.goalsPanel:Hide()
            end
            frame.statsView:SetAlpha(1)
            frame.statsView:Show()

            -- Sequential fade-in for stats cards
            local cardIndex = 0
            for _, bgType in ipairs(HonorLog.BG_ORDER) do
                local card = frame.bgCards[bgType]
                if card then
                    cardIndex = cardIndex + 1
                    card:SetAlpha(0)
                    local delay = (cardIndex - 1) * 0.08
                    local animId = "stats_card_fade_" .. bgType
                    CancelAnimation(animId)
                    C_Timer.After(delay, function()
                        if card and card:IsShown() then
                            AnimateValue(animId, 0, 1, 0.3, function(alpha)
                                if card then card:SetAlpha(alpha) end
                            end)
                        end
                    end)
                end
            end

            -- Fade in session panel after cards
            if frame.sessionPanel then
                frame.sessionPanel:SetAlpha(0)
                local sessionDelay = cardIndex * 0.08 + 0.1
                C_Timer.After(sessionDelay, function()
                    if frame.sessionPanel and frame.sessionPanel:IsShown() then
                        AnimateValue("stats_session_fade", 0, 1, 0.3, function(alpha)
                            if frame.sessionPanel then frame.sessionPanel:SetAlpha(alpha) end
                        end)
                    end
                end)
            end
        else
            -- Switch to goals view
            frame.statsView:Hide()
            if frame.goalsPanel then
                frame.goalsPanel:SetAlpha(1)
                frame.goalsPanel:Show()
                animateOnTabSwitch = true -- Trigger animation for all progress bars
                self:UpdateGoalsPanel()
            end
        end
    else
        -- When minimized, both expanded views stay hidden (no animation needed)
        frame.statsView:Hide()
        frame.goalsPanel:Hide()
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
