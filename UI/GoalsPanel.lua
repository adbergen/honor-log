-- HonorLog Goals Panel
-- UI for gear goal tracking

local ADDON_NAME, HonorLog = ...

-- Forever-safe wrappers (defined in Data.lua)
local GetItemInfo = HonorLog.Compat.GetItemInfo
local GetItemCount = HonorLog.Compat.GetItemCount
local L = HonorLog.L

--------------------------------------------------------------------------------
-- ANIMATION IMPORTS (from UI/Animation.lua)
--------------------------------------------------------------------------------
local AnimateValue = HonorLog.Animation.AnimateValue
local CancelAnimation = HonorLog.Animation.CancelAnimation
local CancelAllAnimations = HonorLog.Animation.CancelAllAnimations
local ANIM = HonorLog.Animation.ANIM

--------------------------------------------------------------------------------
-- THEME (from shared UI/Theme.lua)
--------------------------------------------------------------------------------
local COLORS = HonorLog.Theme
local BG_COLOR_HEX = HonorLog.BG_COLOR_HEX
local BG_ICONS = HonorLog.BG_ICONS
local CURRENCY_ICONS = HonorLog.CURRENCY_ICONS

-- Get faction-specific honor icon
local function GetHonorIcon()
    local faction = UnitFactionGroup("player")
    return CURRENCY_ICONS.honor[faction] or CURRENCY_ICONS.honor.Horde
end

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS (from shared UI/Theme.lua)
--------------------------------------------------------------------------------
local Layout = HonorLog.Layout
local PADDING = Layout.PADDING
local FRAME_WIDTH = Layout.FRAME_WIDTH
-- Two lines taller than the shared layout: a status line (rank badge, ready date) and an epic's two parts.
local GOAL_CARD_HEIGHT = Layout.GOAL_CARD_HEIGHT + 14
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
-- Drag state for reordering (encapsulated)
local dragState = {
    card = nil,              -- Currently dragging card
    startY = 0,              -- Initial cursor Y position
    originalIndex = 0,       -- Card's original position
    frame = nil,             -- Floating drag frame (singleton)
    currentGapIndex = nil,   -- Visual gap position during drag
}

-- Animation state flags (encapsulated)
local animState = {
    progressOnNextUpdate = false,  -- Force progress bar animation after reorder
    cardsOnNextUpdate = false,     -- Force card position animation after reorder
    affectedRange = nil,           -- {min, max} affected positions
    onTabSwitch = false,           -- Animate all on tab switch
}

-- Animate cards to create a visual gap at the specified index
-- Cards animate smoothly to their new positions during drag

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
                AnimateValue(animId, currentY, targetY, ANIM.CARD_MOVE, function(val)
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
    if not dragState.frame then
        dragState.frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        dragState.frame:SetFrameStrata("TOOLTIP")
        dragState.frame:SetSize(200, GOAL_CARD_HEIGHT)

        -- Outer glow/shadow effect
        local shadow = CreateFrame("Frame", nil, dragState.frame, "BackdropTemplate")
        shadow:SetPoint("TOPLEFT", -4, 4)
        shadow:SetPoint("BOTTOMRIGHT", 4, -4)
        shadow:SetFrameLevel(dragState.frame:GetFrameLevel() - 1)
        shadow:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeSize = 6,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        shadow:SetBackdropColor(0, 0, 0, 0.5)
        shadow:SetBackdropBorderColor(0, 0, 0, 0.35)
        dragState.frame.shadow = shadow

        dragState.frame:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        dragState.frame:SetBackdropColor(0.18, 0.20, 0.25, 0.98)
        dragState.frame:SetBackdropBorderColor(1, 0.82, 0.2, 1) -- Gold border
        dragState.frame:Hide()

        -- Highlight glow at top
        local glow = dragState.frame:CreateTexture(nil, "ARTWORK")
        glow:SetHeight(GOAL_CARD_HEIGHT / 2)
        glow:SetPoint("TOPLEFT", 1, -1)
        glow:SetPoint("TOPRIGHT", -1, -1)
        glow:SetTexture("Interface\\Buttons\\WHITE8x8")
        glow:SetGradient("VERTICAL", CreateColor(1, 0.9, 0.5, 0.12), CreateColor(1, 0.9, 0.5, 0))
        dragState.frame.glow = glow

        -- Icon (slightly larger)
        local icon = dragState.frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(36, 36)
        icon:SetPoint("LEFT", 10, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        dragState.frame.icon = icon

        -- Name (larger font)
        local name = dragState.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        name:SetPoint("RIGHT", -10, 0)
        name:SetJustifyH("LEFT")
        dragState.frame.itemName = name
    end
    return dragState.frame
end

-- Create drop indicator line
local dropIndicator
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

--------------------------------------------------------------------------------
-- REQUIREMENT TEXT (shared by the cards and the totals bar)
--------------------------------------------------------------------------------
local GOLD_HEX, RANK_HEX = "e6cc80", "c8a0ff"
local TICK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t"
local CROSS = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t"

-- Hex colour of a Rank tag ("level", "nopoints", ...), or the fallback.
local function TagHex(tag, fallback)
    local c = HonorLog.RANK_TAG_COLORS and HonorLog.RANK_TAG_COLORS[tag]
    if type(c) ~= "table" then return fallback end
    return string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- 12,345 copper -> "1g", 150 -> "1s", 3 -> "3c" (whole units; the exact price is in the tooltip)
local function GoldShort(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper >= 10000 then return BreakUpLargeNumbers(math.floor(copper / 10000)) .. "g" end
    if copper >= 100 then return math.floor(copper / 100) .. "s" end
    return copper .. "c"
end

local function ProgressColor(percent)
    if percent >= 100 then return unpack(COLORS.progressFull) end
    local lowR, lowG, lowB, highR, highG, highB, t
    if percent >= 50 then
        t = (percent - 50) / 50
        lowR, lowG, lowB = unpack(COLORS.progressPartial)
        highR, highG, highB = unpack(COLORS.progressFull)
    else
        t = percent / 50
        lowR, lowG, lowB = unpack(COLORS.progressLow)
        highR, highG, highB = unpack(COLORS.progressPartial)
    end
    return lowR + (highR - lowR) * t, lowG + (highG - lowG) * t, lowB + (highB - lowB) * t
end

-- One requirement as coloured text. factor (0..1) scales the counted amounts for the fill animation.
local function RowText(row, factor)
    factor = factor or 1
    local done = "40d860"
    if row.kind == "honor" then
        local current = math.floor(row.current * factor)
        return string.format("|cff%s%s/%s Honor|r", current >= row.needed and done or "ffd700",
            BreakUpLargeNumbers(current), BreakUpLargeNumbers(row.needed))
    elseif row.kind == "marks" then
        local current = math.floor(row.current * factor)
        return string.format("|cff%s%d/%d|r |T%s:14:14:0:0|t", current >= row.needed and done or (BG_COLOR_HEX[row.bg] or "55bbff"),
            current, row.needed, BG_ICONS[row.bg] or "")
    elseif row.kind == "gold" then
        local current = math.floor(row.current * factor)
        return string.format("|cff%s%s/%s|r", current >= row.needed and done or GOLD_HEX, GoldShort(current), GoldShort(row.needed))
    elseif row.kind == "rank" then
        return string.format("|cff%sRank %s/%d|r", row.met and done or RANK_HEX, row.current and tostring(row.current) or "?", row.needed)
    elseif row.kind == "level" then
        return string.format("|cff%s%s|r", row.met and done or TagHex("level", RANK_HEX),
            string.format(L["Level %d / %d"], row.current or 0, row.needed))
    elseif row.kind == "rep" then
        local need = row.standingName or tostring(row.needed)
        if row.faction and row.known then
            local have = HonorLog.STANDING_NAMES[row.current] or "Unknown"
            if row.amount and row.ceiling and not row.met then
                return string.format("|cff7fc8ff%s %s / %s|r", have, BreakUpLargeNumbers(row.amount), BreakUpLargeNumbers(row.ceiling))
            end
            return string.format("|cff%s%s/%s|r", row.met and done or "7fc8ff", have, need)
        end
        return string.format("|cff9aa5b5%s reputation|r", need)
    end
    return ""
end

local function CurrencyLine(gp, factor)
    local parts = {}
    for _, row in ipairs(gp.rows) do
        if (row.kind == "honor" or row.kind == "gold") then
            if row.needed > 0 then parts[#parts + 1] = RowText(row, factor) end
        elseif row.kind == "level" then
            if not row.met then parts[#parts + 1] = RowText(row, factor) end -- shown only while unmet
        else
            parts[#parts + 1] = RowText(row, factor)
        end
    end
    return table.concat(parts, " |cff666666·|r ")
end

-- Weighted share of honor, marks and gold in hand. Rank and reputation have no amounts, so they only hold
-- the bar just under full.
local function OverallPercent(gp)
    local needed, current = 0, 0
    for _, row in ipairs(gp.rows) do
        local weight = row.kind == "honor" and 1 or row.kind == "marks" and 100 or row.kind == "gold" and 0.001 or nil
        if weight and row.needed > 0 then
            needed = needed + row.needed * weight
            current = current + math.min(row.current, row.needed) * weight
        end
    end
    local percent = needed > 0 and current / needed * 100 or 100
    if not gp.isComplete then percent = math.min(percent, 99) end
    return percent
end

-- What else is short, as plain words ("800 honor, 10 AV marks"), for the status line.
local function OtherMissingText(gp)
    local out = {}
    for _, row in ipairs(gp.missing) do
        if row.kind == "honor" then out[#out + 1] = string.format("%s honor", BreakUpLargeNumbers(row.remaining))
        elseif row.kind == "marks" then out[#out + 1] = string.format("%d %s marks", row.remaining, row.bg)
        elseif row.kind == "gold" then out[#out + 1] = GoldShort(row.remaining)
        elseif row.kind == "rep" then out[#out + 1] = string.format("%s reputation", row.standingName or "standing") end
    end
    return table.concat(out, ", ")
end

local function ReadyText(gp)
    if gp.isComplete then return "|cff40d860Ready to purchase|r" end
    local pieces = {}
    local level = gp.level
    local levelUnmet = level and level.known and not level.met
    if levelUnmet then
        pieces[#pieces + 1] = string.format("|cff%s%s|r", TagHex("level", RANK_HEX), string.format(L["Ready at level %d"], level.needed))
    end
    local rank = gp.rank
    if rank and not rank.met then
        if rank.known and rank.limitedBy == "cap" and rank.week then
            pieces[#pieces + 1] = string.format("|cff%sRank %d locked until week %d|r", RANK_HEX, rank.needed, rank.week)
        elseif rank.known and rank.date then
            pieces[#pieces + 1] = string.format("|cff%sRank %d · %s|r", RANK_HEX, rank.needed, HonorLog.Rank.FormatDate(rank.date))
        elseif rank.known and rank.plan and (rank.limitedBy == "level" or rank.limitedBy == "nopoints") then
            pieces[#pieces + 1] = string.format("|cff%sRank %d · %s|r", TagHex(rank.limitedBy, RANK_HEX), rank.needed, HonorLog.Rank.PlanWhen(rank.plan))
        elseif rank.known then
            pieces[#pieces + 1] = string.format("|cff%sRank %d not reachable this season|r", RANK_HEX, rank.needed)
        else
            pieces[#pieces + 1] = string.format("|cff%sRank %d|r", RANK_HEX, rank.needed)
        end
    end
    if levelUnmet then
        local others = OtherMissingText(gp)
        if others ~= "" then pieces[#pieces + 1] = string.format("|cff9aa5b5%s|r", string.format(L["also needs %s"], others)) end
    elseif gp.readyDate then
        pieces[#pieces + 1] = string.format("|cffb4c8e0ready %s%s|r", gp.estimated and "~" or "on ", HonorLog.Rank.FormatDate(gp.readyDate))
    elseif gp.readyLimitedBy == "norep" and gp.readyText then
        pieces[#pieces + 1] = string.format("|cff888888%s|r", gp.readyText)
    elseif gp.readyLimitedBy == "nopace" then
        pieces[#pieces + 1] = "|cff888888play a game for a date|r"
    end
    return table.concat(pieces, " |cff666666·|r ")
end

local PART_LABEL = { blue = "Blue piece", seal = "Seal" }

local function PartText(part)
    local label = PART_LABEL[part.role] or "Part"
    if part.owned then
        return string.format("%s |cff40d860%s owned|r", TICK, label)
    end
    local cost = {}
    if part.honor > 0 then cost[#cost + 1] = BreakUpLargeNumbers(part.honor) .. " honor" end
    for _, bgType in ipairs(HonorLog.BG_ORDER) do
        local n = part.marks and part.marks[bgType]
        if n then cost[#cost + 1] = n .. " " .. bgType end
    end
    return string.format("%s |cffe0a050%s|r |cff9aa5b5%s|r", CROSS, label, table.concat(cost, ", "))
end

-- The totals bar's currency line: honor, marks and gold, completed goals counted as done. start holds the
-- values to count up from (the fill animation), progress runs 0..1.
function HonorLog:TotalsText(T, start, progress)
    start = start or {}
    local parts = {}
    local function value(from, to) return math.floor(from + (to - from) * progress) end
    local honorNeeded = T.honorNeeded + T.completed.honor
    if honorNeeded > 0 then
        local shown = value(start.honor or T.honorCurrent, T.honorCurrent) + T.completed.honor
        parts[#parts + 1] = string.format("|cff%s%s/%s|r |cffffd700Honor|r", shown >= honorNeeded and "40d860" or "ffd700",
            BreakUpLargeNumbers(shown), BreakUpLargeNumbers(honorNeeded))
    end
    for _, bgType in ipairs(HonorLog.BG_ORDER) do
        local needed = (T.marksNeeded[bgType] or 0) + (T.completed.marks[bgType] or 0)
        if needed > 0 then
            local shown = value((start.marks or {})[bgType] or T.marksCurrent[bgType] or 0, T.marksCurrent[bgType] or 0)
                + (T.completed.marks[bgType] or 0)
            parts[#parts + 1] = string.format("|cff%s%d/%d|r |T%s:14:14:0:0|t", shown >= needed and "40d860" or (BG_COLOR_HEX[bgType] or "55bbff"),
                shown, needed, BG_ICONS[bgType] or "")
        end
    end
    local goldNeeded = T.goldNeeded + T.completed.gold
    if goldNeeded > 0 then
        local shown = value(start.gold or T.goldCurrent, T.goldCurrent) + T.completed.gold
        parts[#parts + 1] = string.format("|cff%s%s/%s|r", shown >= goldNeeded and "40d860" or GOLD_HEX, GoldShort(shown), GoldShort(goldNeeded))
    end
    return table.concat(parts, " |cff666666·|r ")
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
    card.progressPercent = 0
    card.previousItemID = false

    -- Ready state indicator (shown at 100% progress)
    -- Subtle green background tint overlay (static)
    local readyTint = CreateFrame("Frame", nil, card, "BackdropTemplate")
    readyTint:SetAllPoints()
    readyTint:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    })
    readyTint:SetBackdropColor(0.15, 0.45, 0.2, 0.12) -- Soft green wash
    readyTint:SetFrameLevel(card:GetFrameLevel())
    readyTint:Hide()
    card.readyGlow = readyTint

    -- Dummy frames for compatibility
    card.midGlow = CreateFrame("Frame", nil, card)
    card.innerGlow = CreateFrame("Frame", nil, card)
    card.barShimmer = CreateFrame("Frame", nil, card)
    card.sparkle = CreateFrame("Frame", nil, card)

    -- Hover effect with item tooltip, shift-compare, and ctrl-preview
    card:EnableMouse(true)
    card.shiftWasDown = false
    card.ctrlWasDown = false

    local function ShowCardTooltip(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:AddLine(" ")
            local gp = self.progress
            if gp and not gp.isComplete then
                GameTooltip:AddLine("Still missing", 1, 0.82, 0)
                for _, row in ipairs(gp.missing) do
                    if row.kind == "honor" then
                        GameTooltip:AddLine(string.format("  %s honor", BreakUpLargeNumbers(row.remaining)), 1, 1, 1)
                    elseif row.kind == "marks" then
                        GameTooltip:AddLine(string.format("  %d %s marks", row.remaining, row.bg), 1, 1, 1)
                    elseif row.kind == "gold" then
                        GameTooltip:AddLine("  " .. HonorLog:FormatMoney(row.remaining), 1, 1, 1)
                    elseif row.kind == "level" then
                        GameTooltip:AddLine("  " .. string.format(L["Level %d"], row.needed), 1, 1, 1)
                    elseif row.kind == "rank" then
                        GameTooltip:AddLine(string.format("  Rank %d (you are %s)", row.needed, row.current and tostring(row.current) or "unknown"), 1, 1, 1)
                    elseif row.kind == "rep" then
                        GameTooltip:AddLine(string.format("  %s with %s", row.standingName or "Standing", row.factionName or "the faction"), 1, 1, 1)
                        if row.remainingRep and row.remainingRep > 0 then
                            GameTooltip:AddLine("  " .. string.format(L["%s reputation to go"], BreakUpLargeNumbers(row.remainingRep)), 0.7, 0.78, 0.9)
                            if row.perGame and row.perGame > 0 and row.games then
                                GameTooltip:AddLine("  " .. string.format(L["about %d games at %s reputation a game"], row.games, BreakUpLargeNumbers(math.floor(row.perGame + 0.5))), 0.7, 0.78, 0.9)
                            end
                        end
                    end
                end
                if gp.readyDate then
                    GameTooltip:AddLine(string.format("Ready %s%s", gp.estimated and "around " or "on ", HonorLog.Rank.FormatDate(gp.readyDate)), 0.7, 0.9, 1)
                elseif gp.readyText then
                    GameTooltip:AddLine(gp.readyText, 0.6, 0.65, 0.7)
                end
                GameTooltip:AddLine(" ")
            end
            if gp and gp.unconfirmed then
                GameTooltip:AddLine(L["Price unconfirmed: no vendor scan has seen this item yet."], 0.6, 0.65, 0.7, true)
            end
            local vendorLine = HonorLog:GetVendorLine(self.itemID)
            if vendorLine then GameTooltip:AddLine(vendorLine, 0.7, 0.9, 1) end
            for _, row in ipairs(gp and gp.unverified or {}) do
                if row.kind == "rep" then
                    GameTooltip:AddLine(string.format("Needs %s with one of several factions", row.standingName or "standing"), 0.6, 0.65, 0.7)
                end
            end
            GameTooltip:AddLine("|cff888888Ctrl+Click to preview|r", 1, 1, 1)
            GameTooltip:AddLine("|cff888888" .. L["Alt+Click to show the vendor on the map"] .. "|r", 1, 1, 1)
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
        if not dragState.card then
            self:SetBackdropColor(unpack(COLORS.bgCardHover))
            self:SetBackdropBorderColor(unpack(COLORS.borderAccent))
            ShowCardTooltip(self)
            -- Show magnifying glass cursor if Ctrl is held
            if IsControlKeyDown() and self.itemID then
                SetCursor("INSPECT_CURSOR")
                self.ctrlWasDown = true
            else
                self.ctrlWasDown = false
            end
        end
    end)
    card:SetScript("OnLeave", function(self)
        if not dragState.card then
            self:SetBackdropColor(unpack(COLORS.bgCard))
            self:SetBackdropBorderColor(unpack(COLORS.borderDark))
            GameTooltip:Hide()
            if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
            if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
            ResetCursor()
            self.ctrlWasDown = false
        end
    end)
    card:SetScript("OnUpdate", function(self)
        if not self:IsMouseOver() then return end
        if dragState.card then return end
        -- Handle Shift for compare tooltip
        local shiftDown = IsShiftKeyDown()
        if shiftDown ~= self.shiftWasDown then
            ShowCardTooltip(self)
        end
        -- Handle Ctrl for magnifying glass cursor
        local ctrlDown = IsControlKeyDown()
        if ctrlDown ~= self.ctrlWasDown then
            if ctrlDown and self.itemID then
                SetCursor("INSPECT_CURSOR")
            else
                ResetCursor()
            end
            self.ctrlWasDown = ctrlDown
        end
    end)

    -- Ctrl+Click to preview item in dressing room
    card:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and IsAltKeyDown and IsAltKeyDown() and self.itemID then
            HonorLog:ShowVendorForItem(self.itemID)
            return
        end
        if button == "LeftButton" and IsControlKeyDown() and self.itemID and DressUpItemLink then
            local _, itemLink = GetItemInfo(self.itemID)
            if itemLink then
                DressUpItemLink(itemLink)
                -- Position dressing room to the side of HonorLog frame
                if DressUpFrame and HonorLog.mainFrame then
                    DressUpFrame:ClearAllPoints()
                    DressUpFrame:SetPoint("TOPLEFT", HonorLog.mainFrame, "TOPRIGHT", 10, 0)
                end
            end
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
            dragState.card = card
            dragState.originalIndex = card.cardIndex
            dragState.currentGapIndex = card.cardIndex
            dragState.startY = select(2, GetCursorPosition()) / card:GetEffectiveScale()
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
            AnimateValue("drag_lift", 0, 1, ANIM.LIFT_DURATION, function(progress)
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
                AnimateCardsForGap(goalsPanel, dragState.currentGapIndex, dragState.originalIndex)
            end
        end
    end)

    dragHandle:SetScript("OnUpdate", function(self)
        if dragState.card ~= card then return end

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
                if targetIndex ~= dragState.currentGapIndex then
                    dragState.currentGapIndex = targetIndex
                    AnimateCardsForGap(goalsPanel, dragState.currentGapIndex, dragState.originalIndex)
                end

                dragState.card.targetIndex = targetIndex
            end
        end
    end)

    dragHandle:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and dragState.card == card then
            local df = GetDragFrame()
            local goalsPanel = HonorLog.mainFrame and HonorLog.mainFrame.goalsPanel

            -- Use the current gap position as drop target
            local newIndex = dragState.currentGapIndex or dragState.originalIndex
            local goalCount = HonorLog:GetGoalCount()
            newIndex = math.max(1, math.min(goalCount, newIndex))

            -- Clear all drag state immediately
            dragState.card = nil
            dragState.currentGapIndex = nil
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
                local startScale = df:GetScale()
                AnimateValue("drop_move", 0, 1, ANIM.DROP_MOVE, function(progress)
                    local currentX = startX + (endX - startX) * progress
                    local currentY = startY + (endY - startY) * progress
                    df:ClearAllPoints()
                    df:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", currentX, currentY)
                    -- Scale settles back to 1.0
                    df:SetScale(startScale + (1.0 - startScale) * progress)
                end, function()
                    -- Position animation complete, now fade out
                    df:SetScale(1.0)
                    AnimateValue("drop_fade", 0.95, 0, ANIM.DROP_FADE, function(alpha)
                        df:SetAlpha(alpha)
                    end, function()
                        df:Hide()
                        df:SetAlpha(0.95)

                        -- Perform reorder if position changed
                        if newIndex ~= dragState.originalIndex and card.itemID then
                            HonorLog:ReorderGoal(card.itemID, newIndex)
                            animState.progressOnNextUpdate = true
                            animState.cardsOnNextUpdate = true
                            -- Track which positions are affected (inclusive range)
                            animState.affectedRange = {
                                min = math.min(dragState.originalIndex, newIndex),
                                max = math.max(dragState.originalIndex, newIndex)
                            }
                        end

                        -- Update panel to reflect new order
                        HonorLog:UpdateGoalsPanel()
                    end)
                end)
            else
                -- Fallback: scale settle + fade out
                local startScale = df:GetScale()
                AnimateValue("drop_fade", 0, 1, ANIM.DROP_FADE_FALLBACK, function(progress)
                    df:SetAlpha(0.95 * (1 - progress))
                    df:SetScale(startScale + (1.0 - startScale) * progress)
                end, function()
                    df:Hide()
                    df:SetAlpha(0.95)
                    df:SetScale(1.0)

                    if newIndex ~= dragState.originalIndex and card.itemID then
                        HonorLog:ReorderGoal(card.itemID, newIndex)
                        animState.progressOnNextUpdate = true
                        animState.cardsOnNextUpdate = true
                        -- Track which positions are affected (inclusive range)
                        animState.affectedRange = {
                            min = math.min(dragState.originalIndex, newIndex),
                            max = math.max(dragState.originalIndex, newIndex)
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
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Remove Goal")
        GameTooltip:AddLine("Stop tracking this item", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    removeBtn:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(0.8, 0.2, 0.2, 0)
        self.icon:SetAlpha(0.4)
        GameTooltip:Hide()
    end)
    card.removeBtn = removeBtn

    -- Complete button (checkmark, manual fallback for auto-detection)
    local completeBtn = CreateFrame("Button", nil, card)
    completeBtn:SetSize(16, 16)
    completeBtn:SetPoint("RIGHT", removeBtn, "LEFT", -1, 0)

    local completeBg = completeBtn:CreateTexture(nil, "BACKGROUND")
    completeBg:SetAllPoints()
    completeBg:SetColorTexture(0.2, 0.6, 0.2, 0)
    completeBtn.bg = completeBg

    local completeIcon = completeBtn:CreateTexture(nil, "ARTWORK")
    completeIcon:SetSize(14, 14)
    completeIcon:SetPoint("CENTER")
    completeIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    completeIcon:SetAlpha(0.5)
    completeBtn.icon = completeIcon

    completeBtn:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(0.2, 0.6, 0.2, 0.3)
        self.icon:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Mark as Acquired")
        GameTooltip:AddLine("Manual: Move to completed list", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("(Items auto-complete when bought)", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    completeBtn:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(0.2, 0.6, 0.2, 0)
        self.icon:SetAlpha(0.5)
        GameTooltip:Hide()
    end)
    completeBtn:SetScript("OnClick", function()
        if card.itemID then
            local itemName = GetItemInfo(card.itemID) or "Item"
            HonorLog:CompleteGoal(card.itemID)

            -- Celebration! (same as auto-complete)
            PlaySound(878) -- Quest complete sound
            if RaidNotice_AddMessage and RaidBossEmoteFrame then
                RaidNotice_AddMessage(RaidBossEmoteFrame, "|cff00ff00Goal Acquired!|r " .. itemName, ChatTypeInfo["RAID_WARNING"])
            end
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage("|cff40d860[HonorLog]|r Goal acquired: " .. itemName, 0.25, 0.85, 0.37, 1, 3)
            end
            print("|cff40d860[HonorLog]|r || Goal acquired: |cffffffff" .. itemName .. "|r")

            HonorLog:UpdateGoalsPanel()
        end
    end)
    card.completeBtn = completeBtn

    -- Item name (extends to complete button)
    local itemName = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    itemName:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -1)
    itemName:SetPoint("RIGHT", completeBtn, "LEFT", -4, 0)
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

    -- Status line (rank badge, ready date) and an epic's two parts
    local statusLine = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLine:SetPoint("TOPLEFT", currencyLine, "BOTTOMLEFT", 0, -2)
    statusLine:SetPoint("RIGHT", -6, 0)
    statusLine:SetJustifyH("LEFT")
    statusLine:SetWordWrap(false)
    statusLine:SetMaxLines(1)
    card.statusLine = statusLine

    gamesLine:ClearAllPoints()
    gamesLine:SetPoint("TOPLEFT", statusLine, "BOTTOMLEFT", 0, -2)
    gamesLine:SetPoint("RIGHT", -6, 0)

    card.partRows = {}
    for i = 1, 2 do
        local row = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if i == 1 then
            row:SetPoint("TOPLEFT", statusLine, "BOTTOMLEFT", 0, -2)
        else
            row:SetPoint("TOPLEFT", card.partRows[1], "TOPRIGHT", 10, 0)
        end
        row:SetJustifyH("LEFT")
        row:SetWordWrap(false)
        row:SetMaxLines(1)
        row:Hide()
        card.partRows[i] = row
    end

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
        self.progress = goalProgress
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

        local overallPercent = OverallPercent(goalProgress)

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
            local inAffectedRange = animState.affectedRange and
                cardIndex >= animState.affectedRange.min and
                cardIndex <= animState.affectedRange.max
            local forceAnimateReorder = animState.progressOnNextUpdate and inAffectedRange
            local forceAnimateTabSwitch = animState.onTabSwitch
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

                -- For reorder/tab switch, start from minimum width for a fresh fill animation
                local startWidth = forceAnimate and 1 or currentWidth
                local startPercent = forceAnimate and 0 or previousPercent
                local targetPercent = overallPercent

                AnimateValue(animId, 0, 1, ANIM.PROGRESS_FILL, function(progress)
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

                        -- Count the currency lines up with the fill
                        local line = CurrencyLine(goalProgress, progress)
                        if line ~= "" then currencyLine:SetText(line) end

                        local r, g, b = ProgressColor(currentPercent)
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
                end)
            else
                self.progressFill:SetWidth(targetWidth)
                self.progressShine:SetWidth(targetWidth)

                -- Set percentage and color directly (no animation)
                local r, g, b = ProgressColor(overallPercent)
                self.progressText:SetText(overallPercent >= 100 and "100%" or string.format("%.0f%%", overallPercent))
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

        -- Ready glow once everything is in hand
        if goalProgress.isComplete then
            self.readyGlow:Show()
            if self.sparkle then self.sparkle:Show() end
            if self.barShimmer then self.barShimmer:Show() end
        else
            self.readyGlow:Hide()
            if self.sparkle then self.sparkle:Hide() end
            if self.barShimmer then self.barShimmer:Hide() end
        end

        -- Currency line: honor, marks, gold, rank, reputation
        local line = CurrencyLine(goalProgress, 1)
        self.currencyLine:SetText(line ~= "" and line or "|cff40d860Ready to purchase!|r")

        -- Status line: rank badge and ready date
        self.statusLine:SetText(ReadyText(goalProgress))

        -- An epic shows its two parts; anything else shows the games estimate
        if goalProgress.parts then
            for i = 1, 2 do
                local part = goalProgress.parts[i]
                if part then
                    self.partRows[i]:SetText(PartText(part))
                    self.partRows[i]:Show()
                else
                    self.partRows[i]:SetText("")
                    self.partRows[i]:Hide()
                end
            end
            self.gamesLine:SetText("")
            self.gamesLine:Hide()
        else
            for i = 1, 2 do
                self.partRows[i]:SetText("")
                self.partRows[i]:Hide()
            end
            if goalProgress.totalGamesNeeded > 0 then
                self.gamesLine:SetText(string.format("Est. %d games remaining", goalProgress.totalGamesNeeded))
                self.gamesLine:Show()
            else
                self.gamesLine:SetText("")
                self.gamesLine:Hide()
            end
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
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 46)  -- Match Stats panel
    panel.scrollFrame = scrollFrame

    -- Honor-cap advice (shown only while honor is about to be wasted)
    local adviceBar = CreateFrame("Frame", nil, panel)
    adviceBar:SetHeight(16)
    adviceBar:SetPoint("TOPLEFT", PADDING, -3)
    adviceBar:SetPoint("TOPRIGHT", -PADDING - 22, -3)
    local adviceText = adviceBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    adviceText:SetPoint("LEFT", 0, 0)
    adviceText:SetPoint("RIGHT", 0, 0)
    adviceText:SetJustifyH("LEFT")
    adviceText:SetWordWrap(false)
    adviceText:SetMaxLines(1)
    adviceBar.text = adviceText
    adviceBar:Hide()
    panel.adviceBar = adviceBar

    -- Style scroll bar to match dark theme
    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"]
    if scrollBar then
        scrollBar:SetAlpha(0.5)
        -- Darken scrollbar track background
        local track = scrollBar.Track or scrollBar:GetChildren()
        if track and track.SetAlpha then
            track:SetAlpha(0.3)
        end
    end

    -- Goals container (scroll content)
    local goalsContainer = CreateFrame("Frame", nil, scrollFrame)
    goalsContainer:SetWidth(FRAME_WIDTH - 22)  -- Match Stats panel
    scrollFrame:SetScrollChild(goalsContainer)
    panel.goalsContainer = goalsContainer

    -- Card pool for goal cards (reused to avoid frame creation overhead)
    panel.goalCards = {}
    panel.totalsProgressPercent = 0 -- explicit, so the headless mock (which answers any unset field) reads numbers
    panel.totalsPrev = {}
    panel.cardPoolHighWater = 0  -- Track max cards ever created (for debugging)

    -- Function to get or create a goal card from pool
    function panel:GetOrCreateCard(index)
        if not self.goalCards[index] then
            local card = CreateGoalCard(self.goalsContainer, index)
            local yOffset = -((index - 1) * (GOAL_CARD_HEIGHT + GOAL_CARD_SPACING))
            card:SetPoint("TOPLEFT", PADDING, yOffset)
            card:SetPoint("TOPRIGHT", -PADDING, yOffset)  -- Match Stats panel
            card.currentAnimY = yOffset  -- Initialize animation tracking
            card:Hide()

            -- Remove button handler
            card.removeBtn:SetScript("OnClick", function()
                if card.itemID then
                    HonorLog:RemoveGoal(card.itemID)
                    HonorLog:UpdateGoalsPanel()
                end
            end)

            self.goalCards[index] = card
            self.cardPoolHighWater = math.max(self.cardPoolHighWater, index)
        end
        return self.goalCards[index]
    end

    -- Release a card back to pool (hide and reset state)
    function panel:ReleaseCard(index)
        local card = self.goalCards[index]
        if card then
            card:Hide()
            card:SetAlpha(1)
            card.isDragging = nil
            card.itemID = nil
        end
    end

    -- Clear all cards from pool (for cleanup)
    function panel:ClearCardPool()
        for i, card in pairs(self.goalCards) do
            card:Hide()
            card:SetParent(nil)
        end
        wipe(self.goalCards)
        self.cardPoolHighWater = 0
    end

    -- Initial container height (will be updated dynamically)
    goalsContainer:SetHeight(10)

    -- Function to update scroll content width
    function panel:UpdateScrollWidth()
        if self.goalsContainer then
            self.goalsContainer:SetWidth(FRAME_WIDTH - 22)  -- Match Stats panel
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
    -- Styled to match the Stats "Today" panel
    local totalsBar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    totalsBar:SetHeight(36)
    totalsBar:SetPoint("BOTTOMLEFT", PADDING, 4)
    totalsBar:SetPoint("BOTTOMRIGHT", -48, 4) -- Leave room for add button + gap
    totalsBar:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    totalsBar:SetBackdropColor(0.08, 0.15, 0.20, 0.9) -- Match Today panel
    totalsBar:SetBackdropBorderColor(unpack(COLORS.accentDim)) -- Match Today panel
    panel.totalsBar = totalsBar

    -- Tooltip for games estimate
    totalsBar:EnableMouse(true)
    totalsBar:SetScript("OnEnter", function(self)
        local games = panel.totalGamesNeeded or 0
        if games > 0 or panel.totalReadyDate then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Estimated Games Remaining", 1, 0.82, 0)
            if games > 0 then
                GameTooltip:AddLine(string.format("%d games to complete all active goals", games), 1, 1, 1)
            end
            if panel.totalReadyDate then
                GameTooltip:AddLine(string.format("Everything ready around %s", HonorLog.Rank.FormatDate(panel.totalReadyDate)), 0.7, 0.9, 1)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Based on your measured honor and marks per game and the rank planner.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    totalsBar:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- "Total:" label (matches Today: label styling)
    local totalsLabel = totalsBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totalsLabel:SetPoint("TOPLEFT", 8, -3)
    totalsLabel:SetText("Total:")
    totalsLabel:SetTextColor(unpack(COLORS.accent))
    panel.totalsLabel = totalsLabel

    -- Progress bar container (XP-style, positioned in top row)
    -- Anchored after "Total:" label, same vertical position
    local totalsBarContainer = CreateFrame("Frame", nil, totalsBar, "BackdropTemplate")
    totalsBarContainer:SetHeight(10)
    totalsBarContainer:SetPoint("LEFT", totalsLabel, "RIGHT", 6, 0)
    totalsBarContainer:SetPoint("TOPRIGHT", -45, -5)
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
    totalsFill:SetHeight(8)
    totalsFill:SetPoint("TOPLEFT", 1, -1)
    totalsFill:SetPoint("BOTTOMLEFT", 1, 1)
    totalsFill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    totalsFill:SetWidth(1)
    panel.totalsFill = totalsFill

    -- Inner glow effect for more vibrant bar
    local totalsGlow = totalsBarContainer:CreateTexture(nil, "ARTWORK", nil, -1)
    totalsGlow:SetHeight(12)
    totalsGlow:SetPoint("TOPLEFT", totalsFill, "TOPLEFT", -2, 2)
    totalsGlow:SetPoint("BOTTOMLEFT", totalsFill, "BOTTOMLEFT", -2, -2)
    totalsGlow:SetWidth(3)
    totalsGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
    totalsGlow:SetGradient("HORIZONTAL", CreateColor(0.2, 0.8, 0.3, 0.3), CreateColor(0.2, 0.8, 0.3, 0))
    panel.totalsGlow = totalsGlow

    -- Shine overlay
    local totalsShine = totalsBarContainer:CreateTexture(nil, "ARTWORK", nil, 1)
    totalsShine:SetHeight(4)
    totalsShine:SetPoint("TOPLEFT", totalsFill, "TOPLEFT", 0, 0)
    totalsShine:SetPoint("TOPRIGHT", totalsFill, "TOPRIGHT", 0, 0)
    totalsShine:SetTexture("Interface\\Buttons\\WHITE8x8")
    totalsShine:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0.2), CreateColor(1, 1, 1, 0))
    panel.totalsShine = totalsShine

    -- Spark at end of bar (XP bar effect)
    local totalsSpark = totalsBarContainer:CreateTexture(nil, "OVERLAY")
    totalsSpark:SetSize(10, 18)
    totalsSpark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    totalsSpark:SetBlendMode("ADD")
    totalsSpark:SetAlpha(0.7)
    totalsSpark:Hide()
    panel.totalsSpark = totalsSpark

    -- Progress percentage (right side of top row, matches sessionRate style)
    local totalsPercent = totalsBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totalsPercent:SetPoint("TOPRIGHT", -8, -3)
    totalsPercent:SetJustifyH("RIGHT")
    panel.totalsPercent = totalsPercent

    -- Currency totals text (bottom row, matches sessionRewards style)
    local totalsText = totalsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalsText:SetPoint("BOTTOMLEFT", 8, 3)
    totalsText:SetPoint("BOTTOMRIGHT", -8, 3)
    totalsText:SetJustifyH("LEFT")
    totalsText:SetTextColor(unpack(COLORS.neutral))
    totalsText:SetWordWrap(false)
    totalsText:SetMaxLines(1)
    panel.totalsText = totalsText

    -- Footer add button (polished "+" button next to totals bar)
    local footerAddBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
    footerAddBtn:SetSize(36, 36)
    footerAddBtn:SetPoint("BOTTOMRIGHT", -PADDING, 4)
    footerAddBtn:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    footerAddBtn:SetBackdropColor(0.08, 0.15, 0.20, 0.9) -- Match totals bar
    footerAddBtn:SetBackdropBorderColor(unpack(COLORS.accentDim)) -- Match totals bar
    panel.footerAddBtn = footerAddBtn

    -- Inner glow layer for hover effect
    local btnGlow = footerAddBtn:CreateTexture(nil, "BACKGROUND")
    btnGlow:SetAllPoints()
    btnGlow:SetColorTexture(0.35, 0.78, 1.0, 0)
    footerAddBtn.glow = btnGlow

    -- Plus icon with accent color
    local footerAddIcon = footerAddBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    footerAddIcon:SetPoint("CENTER", 0, 0)
    footerAddIcon:SetText("+")
    footerAddIcon:SetTextColor(0.55, 0.55, 0.62, 1)
    footerAddBtn.icon = footerAddIcon

    footerAddBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.22, 0.28, 1)
        self:SetBackdropBorderColor(1.0, 0.82, 0.0, 0.8) -- Gold accent border
        self.glow:SetColorTexture(1.0, 0.85, 0.25, 0.08) -- Subtle gold glow
        self.icon:SetTextColor(1.0, 0.85, 0.25, 1) -- Gold "+"
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Add Goal")
        GameTooltip:Show()
    end)
    footerAddBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.08, 0.15, 0.20, 0.9) -- Match totals bar
        self:SetBackdropBorderColor(unpack(COLORS.accentDim)) -- Match totals bar
        self.glow:SetColorTexture(0.35, 0.78, 1.0, 0)
        self.icon:SetTextColor(0.55, 0.55, 0.62, 1)
        GameTooltip:Hide()
    end)
    footerAddBtn:SetScript("OnMouseDown", function(self)
        self.icon:SetPoint("CENTER", 0, -1) -- Subtle press effect
    end)
    footerAddBtn:SetScript("OnMouseUp", function(self)
        self.icon:SetPoint("CENTER", 0, 0)
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

    --------------------------------------------------------------------------------
    -- COMPLETED SECTION
    --------------------------------------------------------------------------------
    panel.completedExpanded = false -- Start collapsed
    panel.completedCards = {}

    -- Completed section header (collapsible)
    local completedHeader = CreateFrame("Button", nil, goalsContainer, "BackdropTemplate")
    completedHeader:SetHeight(20)
    completedHeader:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    })
    completedHeader:SetBackdropColor(0.06, 0.08, 0.06, 0.6)
    completedHeader:Hide() -- Hidden until there are completed goals
    panel.completedHeader = completedHeader

    -- Expand/collapse arrow texture (using Blizzard's arrow textures)
    local completedArrow = completedHeader:CreateTexture(nil, "ARTWORK")
    completedArrow:SetSize(12, 12)
    completedArrow:SetPoint("LEFT", 6, 0)
    completedArrow:SetTexture("Interface\\Buttons\\UI-PlusMinusButtons")
    completedArrow:SetTexCoord(0, 0.4375, 0, 0.4375) -- Plus sign (collapsed)
    panel.completedArrow = completedArrow

    -- "Completed" label with count
    local completedLabel = completedHeader:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    completedLabel:SetPoint("LEFT", completedArrow, "RIGHT", 4, 0)
    completedLabel:SetText("Completed (0)")
    completedLabel:SetTextColor(0.45, 0.55, 0.45, 0.9)
    panel.completedLabel = completedLabel

    completedHeader:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.08, 0.12, 0.08, 0.8)
        panel.completedLabel:SetTextColor(0.5, 0.7, 0.5, 1)
    end)
    completedHeader:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.06, 0.08, 0.06, 0.6)
        panel.completedLabel:SetTextColor(0.45, 0.55, 0.45, 0.9)
    end)
    completedHeader:SetScript("OnClick", function()
        panel.completedExpanded = not panel.completedExpanded
        if panel.completedExpanded then
            -- Minus sign (expanded)
            panel.completedArrow:SetTexCoord(0.5625, 1, 0, 0.4375)
        else
            -- Plus sign (collapsed)
            panel.completedArrow:SetTexCoord(0, 0.4375, 0, 0.4375)
        end
        panel:Update()
    end)

    -- Helper to create a completed goal card (compact, muted style)
    local function CreateCompletedCard(parent, index)
        local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        card:SetHeight(22) -- Compact height
        card:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        })
        card:SetBackdropColor(0.06, 0.08, 0.06, 0.4)
        card:EnableMouse(true)

        -- Hover effect with item tooltip
        card:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.1, 0.14, 0.1, 0.6)
            if self.itemID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(self.itemID)
                GameTooltip:Show()
            end
        end)
        card:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.06, 0.08, 0.06, 0.4)
            GameTooltip:Hide()
        end)

        -- Checkmark icon (completion indicator)
        local checkmark = card:CreateTexture(nil, "ARTWORK")
        checkmark:SetSize(14, 14)
        checkmark:SetPoint("LEFT", 4, 0)
        checkmark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        checkmark:SetVertexColor(0.4, 0.7, 0.4, 0.9) -- Muted green to match theme
        card.checkmark = checkmark

        -- Item icon (smaller, desaturated)
        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", checkmark, "RIGHT", 3, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetDesaturated(true)
        icon:SetAlpha(0.7)
        card.icon = icon

        -- Item name (muted green, compact)
        local name = card:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        name:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        name:SetPoint("RIGHT", -22, 0)
        name:SetJustifyH("LEFT")
        name:SetTextColor(0.4, 0.55, 0.4, 0.85)
        card.name = name

        -- Restore button (moves back to active)
        local removeBtn = CreateFrame("Button", nil, card)
        removeBtn:SetSize(14, 14)
        removeBtn:SetPoint("RIGHT", -4, 0)
        removeBtn:SetNormalFontObject("GameFontNormalSmall")
        removeBtn:SetText("x")
        removeBtn:GetFontString():SetTextColor(0.4, 0.4, 0.4, 0.6)
        removeBtn:SetScript("OnEnter", function(self)
            self:GetFontString():SetTextColor(0.8, 0.3, 0.3, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Restore to Active")
            GameTooltip:AddLine("Move back to active goals", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        removeBtn:SetScript("OnLeave", function(self)
            self:GetFontString():SetTextColor(0.4, 0.4, 0.4, 0.6)
            GameTooltip:Hide()
        end)
        card.removeBtn = removeBtn

        return card
    end

    -- Get or create completed card
    function panel:GetOrCreateCompletedCard(index)
        if not self.completedCards[index] then
            local card = CreateCompletedCard(self.goalsContainer, index)
            self.completedCards[index] = card
        end
        return self.completedCards[index]
    end

    -- Update function
    function panel:Update()
        local goals = HonorLog:GetAllGoalsProgress()
        local completedGoals = HonorLog:GetCompletedGoals()

        -- "Spend before you cap" header
        local advice = #goals > 0 and HonorLog:GetHonorCapAdvice(goals) or nil
        self.advice = advice
        if advice then
            self.adviceBar.text:SetText(string.format("|cffff8040%s|r  |cffb0b0b0%s/%s honor|r",
                advice.text, BreakUpLargeNumbers(advice.current), BreakUpLargeNumbers(advice.cap)))
            self.adviceBar:Show()
            self.scrollFrame:SetPoint("TOPLEFT", 0, -22)
        else
            self.adviceBar:Hide()
            self.scrollFrame:SetPoint("TOPLEFT", 0, -4)
        end

        -- Only show empty state if BOTH active and completed are empty
        if #goals == 0 and #completedGoals == 0 then
            self.emptyState:Show()
            self.scrollFrame:Hide()
            self.totalsBar:Hide()
            self.footerAddBtn:Show()
            self.addGoalRow:Hide()

            -- Animate add button on tab switch
            if animState.onTabSwitch then
                self.footerAddBtn:SetAlpha(0)
                AnimateValue("addbtn_fade_empty", 0, 1, ANIM.CARD_FADE_IN, function(alpha)
                    if self.footerAddBtn then
                        self.footerAddBtn:SetAlpha(alpha)
                    end
                end)
            end
            self.completedHeader:Hide()
            for _, card in ipairs(self.goalCards) do
                card:Hide()
            end
            for _, card in ipairs(self.completedCards) do
                card:Hide()
            end
        elseif #goals == 0 and #completedGoals > 0 then
            -- No active goals but has completed - show completed section only
            self.emptyState:Hide()
            self.scrollFrame:Show()
            self.totalsBar:Hide() -- No totals since no active goals
            self.footerAddBtn:Show()
            self.addGoalRow:Hide()

            -- Animate add button on tab switch
            if animState.onTabSwitch then
                self.footerAddBtn:SetAlpha(0)
                AnimateValue("addbtn_fade_completed", 0, 1, ANIM.CARD_FADE_IN, function(alpha)
                    if self.footerAddBtn then
                        self.footerAddBtn:SetAlpha(alpha)
                    end
                end)
            end

            -- Hide active goal cards
            for _, card in ipairs(self.goalCards) do
                card:Hide()
            end

            -- Auto-expand completed section when no active goals
            self.completedExpanded = true

            -- Show completed section
            local contentHeight = 0
            self.completedHeader:Show()
            self.completedHeader:SetPoint("TOPLEFT", PADDING, -contentHeight)
            self.completedHeader:SetPoint("TOPRIGHT", -PADDING, -contentHeight)
            self.completedLabel:SetText(string.format("Completed (%d)", #completedGoals))
            contentHeight = contentHeight + 24 -- Header height

            if self.completedExpanded then
                -- Minus sign (expanded)
                self.completedArrow:SetTexCoord(0.5625, 1, 0, 0.4375)

                local completedCardHeight = 24
                for i, goalData in ipairs(completedGoals) do
                    local card = self:GetOrCreateCompletedCard(i)
                    local yOffset = -(contentHeight + (i - 1) * completedCardHeight)
                    card:ClearAllPoints()
                    card:SetPoint("TOPLEFT", self.goalsContainer, "TOPLEFT", PADDING, yOffset)
                    card:SetPoint("TOPRIGHT", self.goalsContainer, "TOPRIGHT", -PADDING, yOffset)
                    card.itemID = goalData.itemID
                    local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(goalData.itemID)
                    card.icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
                    card.name:SetText(itemName or "Loading...")
                    card.removeBtn:SetScript("OnClick", function()
                        HonorLog:RestoreGoal(goalData.itemID)
                        HonorLog:UpdateGoalsPanel()
                    end)
                    card:Show()
                end
                contentHeight = contentHeight + (#completedGoals * completedCardHeight)

                -- Hide extra completed cards
                for i = #completedGoals + 1, #self.completedCards do
                    self.completedCards[i]:Hide()
                end
            else
                -- Plus sign (collapsed)
                self.completedArrow:SetTexCoord(0, 0.4375, 0, 0.4375)

                for _, card in ipairs(self.completedCards) do
                    card:Hide()
                end
            end

            self.goalsContainer:SetHeight(math.max(contentHeight + 8, 50))
        else
            self.emptyState:Hide()
            self.scrollFrame:Show()
            self.totalsBar:Show()
            self.footerAddBtn:Show()

            -- Fade in totals bar and add button on tab switch (after cards start fading)
            if animState.onTabSwitch then
                self.totalsBar:SetAlpha(0)
                self.footerAddBtn:SetAlpha(0)
                local totalsDelay = #goals * ANIM.CARD_STAGGER + 0.1 -- Start after last card begins + small buffer
                C_Timer.After(totalsDelay, function()
                    if self.totalsBar and self.totalsBar:IsShown() then
                        AnimateValue("totals_fade", 0, 1, ANIM.CARD_FADE_IN, function(alpha)
                            if self.totalsBar then
                                self.totalsBar:SetAlpha(alpha)
                            end
                        end)
                    end
                    if self.footerAddBtn and self.footerAddBtn:IsShown() then
                        AnimateValue("addbtn_fade", 0, 1, ANIM.CARD_FADE_IN, function(alpha)
                            if self.footerAddBtn then
                                self.footerAddBtn:SetAlpha(alpha)
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
                if not dragState.card then
                    local targetY = -((i - 1) * cardHeight)

                    -- Animate cards to their positions after drop
                    if animState.cardsOnNextUpdate and card.currentAnimY then
                        local startY = card.currentAnimY
                        local animId = "card_settle_" .. i
                        CancelAnimation(animId)

                        AnimateValue(animId, 0, 1, ANIM.CARD_SETTLE, function(progress)
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
                    if animState.onTabSwitch then
                        -- Start invisible and fade in with staggered delay
                        card:SetAlpha(0)
                        local delay = (i - 1) * ANIM.CARD_STAGGER
                        local fadeAnimId = "card_fade_" .. i
                        CancelAnimation(fadeAnimId)
                        C_Timer.After(delay, function()
                            if card and card:IsShown() then
                                AnimateValue(fadeAnimId, 0, 1, ANIM.CARD_FADE_IN, function(alpha)
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

            -- Calculate base content height from active goals
            local contentHeight = (#goals * cardHeight) + PADDING

            --------------------------------------------------------------------------------
            -- COMPLETED SECTION UPDATE
            --------------------------------------------------------------------------------
            -- (completedGoals already fetched at top of Update function)
            local completedCardHeight = 24 -- 22 + 2 spacing (compact)

            if #completedGoals > 0 then
                -- Show completed header
                self.completedHeader:Show()
                self.completedHeader:SetPoint("TOPLEFT", PADDING, -(contentHeight + 4))
                self.completedHeader:SetPoint("TOPRIGHT", -PADDING, -(contentHeight + 4))
                self.completedLabel:SetText(string.format("Completed (%d)", #completedGoals))
                contentHeight = contentHeight + 24 -- header height + spacing

                if self.completedExpanded then
                    -- Minus sign (expanded)
                    self.completedArrow:SetTexCoord(0.5625, 1, 0, 0.4375)

                    -- Show completed cards
                    for i, completedGoal in ipairs(completedGoals) do
                        local card = self:GetOrCreateCompletedCard(i)
                        local yOffset = -(contentHeight + (i - 1) * completedCardHeight)

                        card:ClearAllPoints()
                        card:SetPoint("TOPLEFT", PADDING, yOffset)
                        card:SetPoint("TOPRIGHT", -PADDING, yOffset)
                        card:Show()

                        -- Update card content
                        card.itemID = completedGoal.itemID
                        local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(completedGoal.itemID)
                        card.name:SetText(itemName or "Loading...")
                        card.icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")

                        -- Restore button handler (moves back to active goals)
                        card.removeBtn:SetScript("OnClick", function()
                            HonorLog:RestoreGoal(completedGoal.itemID)
                            panel:Update()
                        end)
                    end
                    contentHeight = contentHeight + (#completedGoals * completedCardHeight)

                    -- Hide extra completed cards
                    for i = #completedGoals + 1, #self.completedCards do
                        self.completedCards[i]:Hide()
                    end
                else
                    -- Plus sign (collapsed)
                    self.completedArrow:SetTexCoord(0, 0.4375, 0, 0.4375)
                    -- Hide all completed cards when collapsed
                    for _, card in ipairs(self.completedCards) do
                        card:Hide()
                    end
                end
            else
                -- No completed goals - hide the section
                self.completedHeader:Hide()
                for _, card in ipairs(self.completedCards) do
                    card:Hide()
                end
            end

            -- Update scroll content height
            self.goalsContainer:SetHeight(contentHeight)

            -- Totals for the whole list (active goals plus what is already bought)
            local T = HonorLog:GetGoalsTotals(goals)
            self.totalGamesNeeded = T.games
            self.totalReadyDate, self.totalReadyLimit = T.readyDate, T.readyLimitedBy
            local overallPercent = T.percent

            local previousPercent = self.totalsProgressPercent or 0
            local prev = self.totalsPrev or {}
            self.totalsProgressPercent = overallPercent
            self.totalsPrev = { honor = T.honorCurrent, gold = T.goldCurrent, marks = {} }
            for bgType, val in pairs(T.marksCurrent) do self.totalsPrev.marks[bgType] = val end

            -- Update progress bar with animation
            local containerWidth = self.totalsBarContainer:GetWidth()
            local targetWidth = math.max(1, (containerWidth - 2) * (overallPercent / 100))
            local currentWidth = self.totalsFill:GetWidth() or 1

            local widthDiff = math.abs(targetWidth - currentWidth)
            local currencyChanged = math.abs(T.honorCurrent - (prev.honor or 0)) > 0 or math.abs(T.goldCurrent - (prev.gold or 0)) > 0
            for bgType, val in pairs(T.marksCurrent) do
                if math.abs(val - ((prev.marks or {})[bgType] or 0)) > 0 then currencyChanged = true end
            end
            local forceAnimateTabSwitch = animState.onTabSwitch

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
                local start = forceAnimateTabSwitch and { honor = 0, gold = 0, marks = {} } or prev

                AnimateValue(animId, 0, 1, ANIM.TOTALS_FILL, function(progress)
                    if fill and fill:IsShown() then
                        local currentWidthVal = startWidth + (targetWidth - startWidth) * progress
                        fill:SetWidth(currentWidthVal)
                        shine:SetWidth(currentWidthVal)
                        if glow then glow:SetWidth(currentWidthVal + 4) end

                        local currentPercent = startPercent + (targetPercent - startPercent) * progress
                        percentText:SetText(currentPercent >= 100 and "100%" or string.format("%.0f%%", currentPercent))

                        local r, g, b = ProgressColor(currentPercent)
                        fill:SetVertexColor(r, g, b)
                        percentText:SetTextColor(r, g, b)
                        if glow then
                            glow:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.4), CreateColor(r, g, b, 0))
                        end

                        local text = HonorLog:TotalsText(T, start, progress)
                        if text ~= "" then currencyText:SetText(text) end

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

                local r, g, b = ProgressColor(overallPercent)
                self.totalsPercent:SetText(overallPercent >= 100 and "100%" or string.format("%.0f%%", overallPercent))
                self.totalsFill:SetVertexColor(r, g, b)
                self.totalsPercent:SetTextColor(r, g, b)
                if self.totalsGlow then
                    self.totalsGlow:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.4), CreateColor(r, g, b, 0))
                end

                self.totalsText:SetText(HonorLog:TotalsText(T, nil, 1))
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
        animState.progressOnNextUpdate = false
        animState.cardsOnNextUpdate = false
        animState.affectedRange = nil
        animState.onTabSwitch = false

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

        if dragState.card then
            dragState.card:SetAlpha(1)
            dragState.card.targetIndex = nil
            dragState.card = nil
        end
        if dragState.frame then
            dragState.frame:Hide()
        end
        if dropIndicator then
            dropIndicator:Hide()
        end
        dragState.currentGapIndex = nil
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

    -- Filter: Source dropdown (Honor, Rank, Reputation, Upgrade)
    local sourceDropdown = CreateFrame("Frame", "HonorLogSourceDropdown", frame, "UIDropDownMenuTemplate")
    sourceDropdown:SetPoint("LEFT", slotDropdown, "RIGHT", -10, 0)
    UIDropDownMenu_SetWidth(sourceDropdown, 90)
    frame.sourceDropdown = sourceDropdown

    -- Filter row 2: class and armour type
    local classLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    classLabel:SetPoint("TOPLEFT", 16, -66)
    classLabel:SetText("Class:")
    classLabel:SetTextColor(unpack(COLORS.textSecondary))

    local classDropdown = CreateFrame("Frame", "HonorLogClassDropdown", frame, "UIDropDownMenuTemplate")
    classDropdown:SetPoint("LEFT", classLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(classDropdown, 90)
    frame.classDropdown = classDropdown

    local armorDropdown = CreateFrame("Frame", "HonorLogArmorDropdown", frame, "UIDropDownMenuTemplate")
    armorDropdown:SetPoint("LEFT", classDropdown, "RIGHT", -10, 0)
    UIDropDownMenu_SetWidth(armorDropdown, 90)
    frame.armorDropdown = armorDropdown

    -- Filter row 2: Search box
    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 16, -96)
    searchLabel:SetText("Search:")
    searchLabel:SetTextColor(unpack(COLORS.textSecondary))

    local searchBox = CreateFrame("EditBox", "HonorLogSearchBox", frame, "InputBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)

    -- Filter row 3: Checkboxes (below search)
    local unverifiedCheck = CreateFrame("CheckButton", "HonorLogUnverifiedCheck", frame, "UICheckButtonTemplate")
    unverifiedCheck:SetSize(24, 24)
    unverifiedCheck:SetPoint("TOPLEFT", 16, -120)
    unverifiedCheck:SetChecked(HonorLog.db.settings.goalShowUnverified == true)
    unverifiedCheck.text = unverifiedCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    unverifiedCheck.text:SetPoint("LEFT", unverifiedCheck, "RIGHT", 0, 0)
    unverifiedCheck.text:SetText("Show unverified")
    unverifiedCheck.text:SetTextColor(unpack(COLORS.textSecondary))
    unverifiedCheck:SetScript("OnClick", function(self)
        frame.filters.unverified = self:GetChecked() and true or false
        frame:RefreshItems()
    end)
    frame.unverifiedCheck = unverifiedCheck

    local hideOwnedCheck = CreateFrame("CheckButton", "HonorLogHideOwnedCheck", frame, "UICheckButtonTemplate")
    hideOwnedCheck:SetSize(24, 24)
    hideOwnedCheck:SetPoint("LEFT", unverifiedCheck, "RIGHT", 100, 0)
    hideOwnedCheck:SetChecked(false)
    hideOwnedCheck.text = hideOwnedCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hideOwnedCheck.text:SetPoint("LEFT", hideOwnedCheck, "RIGHT", 0, 0)
    hideOwnedCheck.text:SetText("Hide Owned")
    hideOwnedCheck.text:SetTextColor(unpack(COLORS.textSecondary))
    hideOwnedCheck:SetScript("OnClick", function(self)
        frame.filters.hideOwned = self:GetChecked()
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
    scrollFrame:SetPoint("TOPLEFT", 12, -148)
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

    -- Filter state. Faction is not a filter: the picker always shows the player's own faction plus neutral items.
    local _, playerClassToken = UnitClass("player")
    frame.filters = {} -- a plain table: unset entries read nil (frames answer any unset field with a function in the test mock)
    frame.filters.slot = nil
    frame.filters.source = nil
    frame.filters.class = playerClassToken -- the player's class by default; nil means any class
    frame.filters.armor = nil
    frame.filters.unverified = HonorLog.db.settings.goalShowUnverified == true
    frame.filters.hideOwned = false -- Default to showing all items
    frame.filters.search = ""

    local SLOT_NAMES = {
        HEAD = "Head", SHOULDER = "Shoulder", CHEST = "Chest", HANDS = "Hands", LEGS = "Legs", WAIST = "Waist",
        FEET = "Feet", WRIST = "Wrist", MAIN_HAND = "Main Hand", TWO_HAND = "Two-Hand", OFF_HAND = "Off-Hand",
        RANGED = "Ranged", NECK = "Neck", FINGER = "Ring", TRINKET = "Trinket", BACK = "Back", RELIC = "Relic",
        TABARD = "Tabard", MOUNT = "Mount", TOKEN = "Seal", CONSUMABLE = "Consumable", OTHER = "Other",
    }
    local SOURCE_NAMES = { HONOR = "Honor", RANK = "Rank", REP = "Reputation", UPGRADE = "Upgrade" }
    local SOURCE_ORDER = { "HONOR", "RANK", "REP", "UPGRADE" }
    local ARMOR_NAMES = { CLOTH = "Cloth", LEATHER = "Leather", MAIL = "Mail", PLATE = "Plate" }
    local ARMOR_ORDER = { "CLOTH", "LEATHER", "MAIL", "PLATE" }
    local function ClassName(token) return token and (token:sub(1, 1) .. token:sub(2):lower()) or "Any class" end
    frame.SLOT_NAMES = SLOT_NAMES

    -- One dropdown: an "any" entry plus a list of values.
    local function InitChoiceDropdown(dropdown, anyText, values, nameOf, field)
        return function(_, level)
            local info = UIDropDownMenu_CreateInfo()
            info.text = anyText
            info.checked = (frame.filters[field] == nil)
            info.func = function()
                frame.filters[field] = nil
                UIDropDownMenu_SetText(dropdown, anyText)
                frame:RefreshItems()
            end
            UIDropDownMenu_AddButton(info, level)
            for _, value in ipairs(values) do
                info = UIDropDownMenu_CreateInfo()
                info.text = nameOf(value)
                info.value = value
                info.checked = (frame.filters[field] == value)
                info.func = function()
                    frame.filters[field] = value
                    UIDropDownMenu_SetText(dropdown, nameOf(value))
                    frame:RefreshItems()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end
    local slotChoices = { "HEAD", "SHOULDER", "CHEST", "HANDS", "LEGS", "WAIST", "FEET", "WRIST", "MAIN_HAND", "TWO_HAND",
        "OFF_HAND", "RANGED", "NECK", "FINGER", "TRINKET", "BACK", "RELIC", "TOKEN", "MOUNT", "TABARD", "OTHER" }

    UIDropDownMenu_Initialize(slotDropdown, InitChoiceDropdown(slotDropdown, "All Slots", slotChoices, function(v) return SLOT_NAMES[v] or v end, "slot"))
    UIDropDownMenu_SetText(slotDropdown, "All Slots")
    UIDropDownMenu_Initialize(sourceDropdown, InitChoiceDropdown(sourceDropdown, "All Sources", SOURCE_ORDER, function(v) return SOURCE_NAMES[v] end, "source"))
    UIDropDownMenu_SetText(sourceDropdown, "All Sources")
    UIDropDownMenu_Initialize(classDropdown, InitChoiceDropdown(classDropdown, "Any class", HonorLog.CLASSES or {}, ClassName, "class"))
    UIDropDownMenu_SetText(classDropdown, ClassName(frame.filters.class))
    UIDropDownMenu_Initialize(armorDropdown, InitChoiceDropdown(armorDropdown, "Any armor", ARMOR_ORDER, function(v) return ARMOR_NAMES[v] end, "armor"))
    UIDropDownMenu_SetText(armorDropdown, "Any armor")

    -- Search handler
    searchBox:SetScript("OnTextChanged", function(self)
        frame.filters.search = self:GetText():lower()
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

        -- Track shift state for compare tooltip and ctrl state for preview
        row.shiftWasDown = false
        row.ctrlWasDown = false

        local function ShowItemTooltip(self)
            if self.itemID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(self.itemID)
                GameTooltip:AddLine(" ")
                local vendorLine = HonorLog:GetVendorLine(self.itemID)
                if vendorLine then GameTooltip:AddLine(vendorLine, 0.7, 0.9, 1) end
                GameTooltip:AddLine("|cff888888Ctrl+Click to preview|r", 1, 1, 1)
                GameTooltip:AddLine("|cff888888" .. L["Alt+Click to show the vendor on the map"] .. "|r", 1, 1, 1)
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
            -- Show magnifying glass cursor if Ctrl is held
            if IsControlKeyDown() and self.itemID then
                SetCursor("INSPECT_CURSOR")
                self.ctrlWasDown = true
            else
                self.ctrlWasDown = false
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.bg:SetColorTexture(0.10, 0.10, 0.14, 0.9)
            self.iconBorder:SetColorTexture(0.25, 0.25, 0.30, 1)
            GameTooltip:Hide()
            -- Hide shopping/compare tooltips
            if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
            if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
            ResetCursor()
            self.ctrlWasDown = false
        end)
        -- Detect shift/ctrl key changes while hovering
        row:SetScript("OnUpdate", function(self)
            if not self:IsMouseOver() then return end
            -- Handle Shift for compare tooltip
            local shiftDown = IsShiftKeyDown()
            if shiftDown ~= self.shiftWasDown then
                ShowItemTooltip(self)
            end
            -- Handle Ctrl for magnifying glass cursor
            local ctrlDown = IsControlKeyDown()
            if ctrlDown ~= self.ctrlWasDown then
                if ctrlDown and self.itemID then
                    SetCursor("INSPECT_CURSOR")
                else
                    ResetCursor()
                end
                self.ctrlWasDown = ctrlDown
            end
        end)

        -- Ctrl+Click to preview item in dressing room
        row:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and IsAltKeyDown and IsAltKeyDown() and self.itemID then
                HonorLog:ShowVendorForItem(self.itemID)
                return
            end
            if button == "LeftButton" and IsControlKeyDown() and self.itemID and DressUpItemLink then
                local _, itemLink = GetItemInfo(self.itemID)
                if itemLink then
                    DressUpItemLink(itemLink)
                    -- Position dressing room to the side of the gear picker frame
                    local pickerFrame = _G["HonorLogGoalPicker"]
                    if DressUpFrame and pickerFrame then
                        DressUpFrame:ClearAllPoints()
                        DressUpFrame:SetPoint("TOPLEFT", pickerFrame, "TOPRIGHT", 10, 0)
                    end
                end
            end
        end)

        return row
    end

    -- Refresh items list
    function frame:RefreshItems()
        local filteredItems = HonorLog:GetPickerItems({
            slot = self.filters.slot, class = self.filters.class, armor = self.filters.armor, source = self.filters.source,
            search = self.filters.search, showUnverified = self.filters.unverified, hideOwned = self.filters.hideOwned,
        })
        self.shownItems = filteredItems

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

            row.name:SetText(item.name or data.name or itemName or "Item " .. itemID)

            -- Compact cost line: honor, marks, gold, rank, reputation (scanned costs replace generated ones)
            local entry = HonorLog:GetGearItem(itemID) or data
            local costParts = {}
            if (entry.honor or 0) > 0 then
                table.insert(costParts, string.format("|cffffd700%s|r |cffbbaa55H|r", BreakUpLargeNumbers(entry.honor)))
            end
            for _, bgType in ipairs(HonorLog.BG_ORDER) do
                local count = entry.marks and entry.marks[bgType]
                if count and count > 0 then
                    table.insert(costParts, string.format("|cff%s%d|r |T%s:14:14:0:0|t", BG_COLOR_HEX[bgType] or "55bbff", count, BG_ICONS[bgType] or ""))
                end
            end
            if (entry.gold or 0) > 0 then
                table.insert(costParts, string.format("|cff%s%s|r", GOLD_HEX, GoldShort(entry.gold)))
            end
            if entry.rank then
                table.insert(costParts, string.format("|cff%sR%d|r", RANK_HEX, entry.rank))
            end
            if entry.rep and entry.rep.standing then
                table.insert(costParts, string.format("|cff7fc8ff%s|r", HonorLog.STANDING_NAMES[entry.rep.standing] or "Rep"))
            end
            row.costLine:SetText(table.concat(costParts, " "))

            -- Slot (and source) indicator
            local slotLabel = (self.SLOT_NAMES and self.SLOT_NAMES[data.slot]) or data.slot or ""
            if data.source == "UPGRADE" then slotLabel = slotLabel .. " · Epic" end
            if entry.scanned then
                slotLabel = slotLabel .. " · scanned"
            elseif entry.unconfirmed then
                slotLabel = slotLabel .. " · " .. L["price unconfirmed"]
            elseif data.legacy then
                slotLabel = slotLabel .. " · unverified"
            end
            row.slotText:SetText(slotLabel)

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

    -- Tab click handlers with tooltips
    statsTab:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Battleground Stats")
        GameTooltip:AddLine("Win/loss records and honor earned per BG", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    statsTab:HookScript("OnLeave", function() GameTooltip:Hide() end)
    statsTab:SetScript("OnClick", function()
        self:SwitchTab("stats")
    end)

    goalsTab:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Gear Goals")
        GameTooltip:AddLine("Track progress toward PvP gear purchases", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    goalsTab:HookScript("OnLeave", function() GameTooltip:Hide() end)
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
                    local delay = (cardIndex - 1) * ANIM.CARD_STAGGER
                    local animId = "stats_card_fade_" .. bgType
                    CancelAnimation(animId)
                    C_Timer.After(delay, function()
                        if card and card:IsShown() then
                            AnimateValue(animId, 0, 1, ANIM.CARD_FADE_IN, function(alpha)
                                if card then card:SetAlpha(alpha) end
                            end)
                        end
                    end)
                end
            end

            -- Also animate World card (after BG cards)
            if frame.worldCard then
                cardIndex = cardIndex + 1
                frame.worldCard:SetAlpha(0)
                local worldDelay = (cardIndex - 1) * ANIM.CARD_STAGGER
                CancelAnimation("stats_card_fade_world")
                C_Timer.After(worldDelay, function()
                    if frame.worldCard and frame.worldCard:IsShown() then
                        AnimateValue("stats_card_fade_world", 0, 1, ANIM.CARD_FADE_IN, function(alpha)
                            if frame.worldCard then frame.worldCard:SetAlpha(alpha) end
                        end)
                    end
                end)
            end

            -- Fade in session panel after cards
            if frame.sessionPanel then
                frame.sessionPanel:SetAlpha(0)
                local sessionDelay = cardIndex * ANIM.CARD_STAGGER + 0.1
                C_Timer.After(sessionDelay, function()
                    if frame.sessionPanel and frame.sessionPanel:IsShown() then
                        AnimateValue("stats_session_fade", 0, 1, ANIM.CARD_FADE_IN, function(alpha)
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
                animState.onTabSwitch = true -- Trigger animation for all progress bars
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
