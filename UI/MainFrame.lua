-- HonorLog Main Frame
-- Enterprise-level UI inspired by Details!, WeakAuras, and ElvUI

local ADDON_NAME, HonorLog = ...

--------------------------------------------------------------------------------
-- THEME (from shared UI/Theme.lua)
--------------------------------------------------------------------------------
local COLORS = HonorLog.Theme
local BG_COLORS = HonorLog.BG_COLORS
local BG_GLOW_COLORS = HonorLog.BG_GLOW_COLORS

-- Full BG names
local BG_NAMES = {
    AV = "Alterac Valley",
    AB = "Arathi Basin",
    WSG = "Warsong Gulch",
    EotS = "Eye of the Storm",
}

-- Mark of Honor icons (TBC Classic mark item icons)
local BG_ICONS = {
    AV = "Interface\\Icons\\INV_Jewelry_Necklace_21",   -- Alterac Valley Mark (blue crystal)
    AB = "Interface\\Icons\\INV_Jewelry_Amulet_07",  -- Arathi Basin Mark
    WSG = "Interface\\Icons\\INV_Misc_Rune_07",  -- Warsong Gulch Mark (green medallion)
    EotS = "Interface\\Icons\\Spell_Nature_EyeOfTheStorm",        -- Eye of the Storm Mark (purple)
}

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS (from shared UI/Theme.lua)
--------------------------------------------------------------------------------
local Layout = HonorLog.Layout
local FRAME_WIDTH = Layout.FRAME_WIDTH
local FRAME_HEIGHT_COMPACT = Layout.FRAME_HEIGHT_COMPACT
local FRAME_HEIGHT_EXPANDED = Layout.FRAME_HEIGHT_EXPANDED
local HEADER_HEIGHT = Layout.HEADER_HEIGHT
local CARD_HEIGHT = Layout.CARD_HEIGHT
local CARD_SPACING = Layout.CARD_SPACING
local PADDING = Layout.PADDING
local INNER_PADDING = Layout.INNER_PADDING

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

-- Create smooth gradient texture
local function CreateGradient(parent, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    local gradient = parent:CreateTexture(nil, "BACKGROUND")
    gradient:SetAllPoints()
    gradient:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    gradient:SetGradient(orientation,
        CreateColor(r1, g1, b1, a1),
        CreateColor(r2, g2, b2, a2))
    return gradient
end

-- Create inner shadow effect
local function CreateInnerShadow(frame)
    local shadow = frame:CreateTexture(nil, "OVERLAY", nil, -1)
    shadow:SetPoint("TOPLEFT", 1, -1)
    shadow:SetPoint("BOTTOMRIGHT", -1, 1)
    shadow:SetColorTexture(0, 0, 0, 0.3)
    return shadow
end

-- Create glow border
local function CreateGlowBorder(frame, color)
    local glow = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    glow:SetPoint("TOPLEFT", -2, 2)
    glow:SetPoint("BOTTOMRIGHT", 2, -2)
    glow:SetBackdrop({
        bgFile = nil,
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 2,
    })
    glow:SetBackdropBorderColor(unpack(color or COLORS.borderGlow))
    glow:SetFrameLevel(frame:GetFrameLevel() - 1)
    return glow
end

-- Create slim progress bar (no text inside - too small)
local function CreateProgressBar(parent, height)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(height or 3)

    -- Background track
    local bgTrack = container:CreateTexture(nil, "BACKGROUND")
    bgTrack:SetAllPoints()
    bgTrack:SetColorTexture(0.12, 0.12, 0.15, 0.9)
    container.bgTrack = bgTrack

    -- Fill bar
    local fill = container:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMLEFT", 0, 0)
    fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    fill:SetWidth(1)
    container.fill = fill

    function container:SetProgress(percent, isWin)
        local maxWidth = container:GetWidth()
        local width = math.max(1, maxWidth * (percent / 100))
        fill:SetWidth(width)

        if isWin then
            fill:SetVertexColor(0.25, 0.85, 0.35, 1)
        else
            fill:SetVertexColor(0.90, 0.30, 0.30, 1)
        end
    end

    return container
end

-- Create icon button with hover effect
local function CreateIconButton(parent, normalTex, size)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size or 20, size or 20)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(COLORS.bgTertiary))
    bg:SetAlpha(0)
    btn.bg = bg

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(normalTex)
    icon:SetAlpha(0.7)
    btn.icon = icon

    btn:SetScript("OnEnter", function(self)
        self.bg:SetAlpha(1)
        self.icon:SetAlpha(1)
    end)
    btn:SetScript("OnLeave", function(self)
        self.bg:SetAlpha(0)
        self.icon:SetAlpha(0.7)
    end)

    return btn
end

--------------------------------------------------------------------------------
-- MAIN FRAME CREATION
--------------------------------------------------------------------------------
local function CreateMainFrame()
    local frame = CreateFrame("Frame", "HonorLogMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT_COMPACT)
    frame:SetPoint("CENTER", 0, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(100)

    -- Main backdrop with premium dark theme
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(unpack(COLORS.bgPrimary))
    frame:SetBackdropBorderColor(unpack(COLORS.borderDark))

    -- Outer glow effect
    local outerGlow = CreateGlowBorder(frame, COLORS.borderGlow)
    frame.outerGlow = outerGlow

    ----------------------------------------------------------------------------
    -- HEADER
    ----------------------------------------------------------------------------
    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", 5, -5)
    header:SetPoint("TOPRIGHT", -5, -5)
    header:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    header:SetBackdropColor(unpack(COLORS.headerGradientTop))
    header:SetBackdropBorderColor(unpack(COLORS.borderLight))
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relPoint, x, y = frame:GetPoint()
        HonorLog.db.settings.framePoint = { point, nil, relPoint, x, y }
    end)
    -- Right-click handler set at end of CreateMainFrame
    frame.header = header

    -- Header gradient overlay
    local headerGradient = header:CreateTexture(nil, "ARTWORK")
    headerGradient:SetPoint("TOPLEFT", 1, -1)
    headerGradient:SetPoint("BOTTOMRIGHT", -1, 1)
    headerGradient:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    headerGradient:SetGradient("VERTICAL",
        CreateColor(0.18, 0.18, 0.24, 0.8),
        CreateColor(0.10, 0.10, 0.14, 0.95))

    -- Addon icon
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexture("Interface\\Icons\\Spell_Holy_ChampionsBond")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Title with brand color
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    title:SetText("HonorLog")
    title:SetTextColor(unpack(COLORS.brand))
    frame.title = title

    -- Version badge
    local versionBadge = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionBadge:SetPoint("LEFT", title, "RIGHT", 4, 0)
    versionBadge:SetText("v1.1.0")
    versionBadge:SetTextColor(unpack(COLORS.accent))

    -- View mode indicator (pill badge)
    local viewModeBg = header:CreateTexture(nil, "ARTWORK")
    viewModeBg:SetSize(50, 16)
    viewModeBg:SetPoint("LEFT", versionBadge, "RIGHT", 8, 0)
    viewModeBg:SetColorTexture(0.15, 0.15, 0.20, 0.8)
    frame.viewModeBg = viewModeBg

    local viewMode = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    viewMode:SetPoint("CENTER", viewModeBg, "CENTER", 0, 0)
    viewMode:SetTextColor(unpack(COLORS.textSecondary))
    frame.viewMode = viewMode

    -- Close button (custom styled)
    local closeBtn = CreateIconButton(header, "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", 16)
    closeBtn:SetPoint("RIGHT", -4, 0)
    closeBtn:SetScript("OnClick", function()
        HonorLog:ToggleMainFrame()
    end)

    -- Expand/collapse button
    local expandBtn = CreateIconButton(header, "Interface\\Buttons\\UI-PlusButton-UP", 16)
    expandBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    expandBtn:SetScript("OnClick", function()
        HonorLog:ToggleExpanded()
    end)
    frame.expandBtn = expandBtn

    ----------------------------------------------------------------------------
    -- COMPACT VIEW (Summary Stats)
    ----------------------------------------------------------------------------
    local compact = CreateFrame("Frame", nil, frame)
    compact:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    compact:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -4)
    compact:SetHeight(22)
    compact:EnableMouse(true)
    -- Right-click handler set at end of CreateMainFrame
    frame.compact = compact

    -- Current BG status with icon
    local statusIcon = compact:CreateTexture(nil, "ARTWORK")
    statusIcon:SetSize(12, 12)
    statusIcon:SetPoint("LEFT", PADDING, 0)
    statusIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
    statusIcon:SetAlpha(0.8)
    frame.statusIcon = statusIcon

    local statusLine = compact:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLine:SetPoint("LEFT", statusIcon, "RIGHT", 4, 0)
    statusLine:SetJustifyH("LEFT")
    frame.statusLine = statusLine

    -- Session quick stats (right aligned)
    local sessionQuick = compact:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sessionQuick:SetPoint("RIGHT", -PADDING, 0)
    sessionQuick:SetJustifyH("RIGHT")
    frame.sessionQuick = sessionQuick

    ----------------------------------------------------------------------------
    -- EXPANDED VIEW
    ----------------------------------------------------------------------------
    local expanded = CreateFrame("Frame", nil, frame)
    expanded:SetPoint("TOPLEFT", compact, "BOTTOMLEFT", 0, -2)
    expanded:SetPoint("TOPRIGHT", compact, "BOTTOMRIGHT", 0, -2)
    expanded:SetHeight(180)
    expanded:EnableMouse(true)
    -- Right-click handler set at end of CreateMainFrame
    expanded:Hide()
    frame.expanded = expanded

    -- Subtle separator
    local topSep = expanded:CreateTexture(nil, "ARTWORK")
    topSep:SetHeight(1)
    topSep:SetPoint("TOPLEFT", PADDING, 0)
    topSep:SetPoint("TOPRIGHT", -PADDING, 0)
    topSep:SetColorTexture(unpack(COLORS.separator))

    -- BG Stats Cards
    frame.bgCards = {}
    local yOffset = -8

    for _, bgType in ipairs({"AV", "AB", "WSG", "EotS"}) do
        local card = CreateFrame("Frame", nil, expanded, "BackdropTemplate")
        card:SetHeight(CARD_HEIGHT)
        card:SetPoint("TOPLEFT", PADDING, yOffset)
        card:SetPoint("TOPRIGHT", -PADDING, yOffset)

        -- Card background with hover effect
        card:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        card:SetBackdropColor(unpack(COLORS.bgCard))
        card:SetBackdropBorderColor(unpack(COLORS.borderDark))

        card:EnableMouse(true)
        card:SetScript("OnEnter", function(self)
            self:SetBackdropColor(unpack(COLORS.bgCardHover))
            self:SetBackdropBorderColor(unpack(BG_GLOW_COLORS[bgType]))
            if self.bgIcon then self.bgIcon:SetAlpha(1) end
        end)
        card:SetScript("OnLeave", function(self)
            self:SetBackdropColor(unpack(COLORS.bgCard))
            self:SetBackdropBorderColor(unpack(COLORS.borderDark))
            if self.bgIcon then self.bgIcon:SetAlpha(0.9) end
        end)
        -- Right-click handler set at end of CreateMainFrame

        -- Left accent bar
        local accentBar = card:CreateTexture(nil, "ARTWORK")
        accentBar:SetWidth(3)
        accentBar:SetPoint("TOPLEFT", 0, 0)
        accentBar:SetPoint("BOTTOMLEFT", 0, 0)
        accentBar:SetColorTexture(unpack(BG_COLORS[bgType]))
        card.accentBar = accentBar

        -- BG Icon
        local bgIcon = card:CreateTexture(nil, "ARTWORK")
        bgIcon:SetSize(24, 24)
        bgIcon:SetPoint("LEFT", 6, 0)
        bgIcon:SetTexture(BG_ICONS[bgType])
        bgIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        bgIcon:SetAlpha(0.9)
        card.bgIcon = bgIcon

        -- BG Name (abbreviated)
        local bgName = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bgName:SetPoint("LEFT", bgIcon, "RIGHT", 5, 4)
        bgName:SetText(bgType)
        bgName:SetTextColor(unpack(BG_COLORS[bgType]))
        card.bgName = bgName

        -- Full BG name (smaller, below abbreviation)
        local bgFullName = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bgFullName:SetPoint("TOPLEFT", bgName, "BOTTOMLEFT", 0, 0)
        bgFullName:SetText(BG_NAMES[bgType])
        bgFullName:SetTextColor(unpack(COLORS.textTertiary))
        card.bgFullName = bgFullName

        -- Win-Loss record (right side)
        local record = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        record:SetPoint("TOPRIGHT", -6, -4)
        record:SetJustifyH("RIGHT")
        card.record = record

        -- Winrate + Honor on bottom right
        local winrate = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        winrate:SetPoint("BOTTOMRIGHT", -6, 5)
        winrate:SetJustifyH("RIGHT")
        card.winrate = winrate

        -- Honor earned (left of winrate)
        local honor = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        honor:SetPoint("RIGHT", winrate, "LEFT", -8, 0)
        honor:SetJustifyH("RIGHT")
        honor:SetTextColor(unpack(COLORS.neutral))
        card.honor = honor

        -- Winrate progress bar (bottom of card)
        local progressBar = CreateProgressBar(card, 2)
        progressBar:SetPoint("BOTTOMLEFT", 3, 1)
        progressBar:SetPoint("BOTTOMRIGHT", -3, 1)
        card.progressBar = progressBar

        frame.bgCards[bgType] = card
        yOffset = yOffset - CARD_HEIGHT - CARD_SPACING
    end

    -- Session Summary Panel
    local sessionPanel = CreateFrame("Frame", nil, expanded, "BackdropTemplate")
    sessionPanel:SetHeight(36)
    sessionPanel:SetPoint("TOPLEFT", PADDING, yOffset - 3)
    sessionPanel:SetPoint("TOPRIGHT", -PADDING, yOffset - 3)
    sessionPanel:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    sessionPanel:SetBackdropColor(0.08, 0.15, 0.20, 0.9)
    sessionPanel:SetBackdropBorderColor(unpack(COLORS.accentDim))
    sessionPanel:EnableMouse(true)
    -- Right-click handler set at end of CreateMainFrame
    frame.sessionPanel = sessionPanel

    -- Session label
    local sessionLabel = sessionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sessionLabel:SetPoint("TOPLEFT", 8, -3)
    sessionLabel:SetText("Session:")
    sessionLabel:SetTextColor(unpack(COLORS.accent))

    -- Session stats (W-L and winrate)
    local sessionStats = sessionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sessionStats:SetPoint("LEFT", sessionLabel, "RIGHT", 6, 0)
    sessionStats:SetJustifyH("LEFT")
    frame.sessionStats = sessionStats

    -- Hourly rate (right side of top line)
    local sessionRate = sessionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sessionRate:SetPoint("TOPRIGHT", -8, -3)
    sessionRate:SetJustifyH("RIGHT")
    sessionRate:SetTextColor(1, 0.84, 0, 1) -- Gold
    frame.sessionRate = sessionRate

    -- Session rewards (second line)
    local sessionRewards = sessionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sessionRewards:SetPoint("BOTTOMLEFT", 8, 3)
    sessionRewards:SetPoint("RIGHT", -8, 0)
    sessionRewards:SetJustifyH("LEFT")
    frame.sessionRewards = sessionRewards

    ----------------------------------------------------------------------------
    -- INTERACTIONS
    ----------------------------------------------------------------------------

    -- Dragging (already registered in frame creation)
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

    -- Right-click menu - use BOTH OnMouseDown and OnMouseUp for maximum compatibility
    local function HandleRightClick(self, button)
        if button == "RightButton" then
            print("|cff00ff00[HonorLog]|r Right-click detected on: " .. (self:GetName() or "unnamed frame"))
            HonorLog:ShowContextMenu()
        end
    end

    -- Apply to main frame
    frame:SetScript("OnMouseDown", HandleRightClick)
    frame:SetScript("OnMouseUp", HandleRightClick)

    -- Apply to header
    header:SetScript("OnMouseDown", HandleRightClick)

    -- Apply to compact view
    compact:SetScript("OnMouseDown", HandleRightClick)

    -- Apply to expanded view
    expanded:SetScript("OnMouseDown", HandleRightClick)

    -- Apply to session panel
    sessionPanel:SetScript("OnMouseDown", HandleRightClick)

    -- Apply to all BG cards
    for bgType, card in pairs(frame.bgCards) do
        card:SetScript("OnMouseDown", HandleRightClick)
    end

    return frame
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- TOGGLE FUNCTIONS
--------------------------------------------------------------------------------
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

function HonorLog:ToggleExpanded()
    self:SetExpanded(not self.db.settings.frameExpanded)
end

function HonorLog:SetExpanded(expanded)
    self.db.settings.frameExpanded = expanded

    if expanded then
        self.mainFrame.expanded:Show()
        self.mainFrame:SetHeight(FRAME_HEIGHT_EXPANDED)
        self.mainFrame.expandBtn.icon:SetTexture("Interface\\Buttons\\UI-MinusButton-UP")
    else
        self.mainFrame.expanded:Hide()
        self.mainFrame:SetHeight(FRAME_HEIGHT_COMPACT)
        self.mainFrame.expandBtn.icon:SetTexture("Interface\\Buttons\\UI-PlusButton-UP")
    end
end

--------------------------------------------------------------------------------
-- UPDATE FUNCTION
--------------------------------------------------------------------------------
function HonorLog:UpdateMainFrame()
    if not self.mainFrame or not self.mainFrame:IsShown() then return end

    local scope = self.db.settings.viewMode
    local frame = self.mainFrame

    -- Update view mode indicator
    if scope == "account" then
        frame.viewMode:SetText("ACCOUNT")
        frame.viewModeBg:SetColorTexture(0.18, 0.12, 0.25, 0.9)
    else
        frame.viewMode:SetText("CHAR")
        frame.viewModeBg:SetColorTexture(0.12, 0.18, 0.22, 0.9)
    end

    -- Adjust badge width
    local textWidth = frame.viewMode:GetStringWidth() + 12
    frame.viewModeBg:SetWidth(math.max(40, textWidth))

    -- Update status line (compact view)
    local currentBG = self:GetCurrentBG()
    if currentBG then
        local duration = 0
        local startTime = self:GetBGStartTime()
        if startTime then
            duration = math.floor(GetTime() - startTime)
        end
        local honorAccum = self:GetBGHonorAccumulated()
        local statusText = string.format("%s  -  %s", currentBG, self:FormatDuration(duration))
        if honorAccum > 0 then
            statusText = statusText .. string.format("  |cffffd700+%d|r", honorAccum)
        end
        frame.statusLine:SetText(statusText)
        frame.statusLine:SetTextColor(unpack(BG_COLORS[currentBG] or COLORS.textPrimary))
        frame.statusIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
        frame.statusIcon:SetVertexColor(0.3, 0.9, 0.4, 1)
    else
        frame.statusLine:SetText("Not in Battleground")
        frame.statusLine:SetTextColor(unpack(COLORS.textTertiary))
        frame.statusIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-NotReady")
        frame.statusIcon:SetVertexColor(0.5, 0.5, 0.55, 0.7)
    end

    -- Session quick stats (compact view)
    local totalSession = self:GetTotalSessionStats()
    if totalSession.played > 0 then
        local color = totalSession.winrate >= 50 and COLORS.win or COLORS.loss
        frame.sessionQuick:SetText(string.format("%d-%d  %.0f%%",
            totalSession.wins, totalSession.losses, totalSession.winrate))
        frame.sessionQuick:SetTextColor(unpack(color))
    else
        frame.sessionQuick:SetText("--")
        frame.sessionQuick:SetTextColor(unpack(COLORS.textMuted))
    end

    -- Update BG cards
    for bgType, card in pairs(frame.bgCards) do
        local stats = self:GetBGStats(bgType, scope)
        local derived = self:GetDerivedStats(bgType, scope)

        if stats.played > 0 then
            -- Record
            card.record:SetText(string.format("%d-%d", stats.wins, stats.losses))
            card.record:SetTextColor(unpack(COLORS.textPrimary))

            -- Winrate
            local isWinning = derived.winrate >= 50
            local color = isWinning and COLORS.win or COLORS.loss

            card.winrate:SetText(string.format("%.0f%%", derived.winrate))
            card.winrate:SetTextColor(unpack(color))

            -- Honor (formatted)
            local honorText = stats.honorLifetime >= 1000
                and string.format("%.1fk", stats.honorLifetime / 1000)
                or tostring(stats.honorLifetime)
            card.honor:SetText(honorText .. " Honor")
            card.honor:SetTextColor(unpack(COLORS.neutralDim))

            -- Progress bar
            card.progressBar:SetProgress(derived.winrate, isWinning)

            -- Full opacity
            card.bgIcon:SetAlpha(0.9)
            card.bgName:SetAlpha(1)
            card.bgFullName:SetAlpha(0.7)
            card.accentBar:SetAlpha(1)
        else
            card.record:SetText("--")
            card.record:SetTextColor(unpack(COLORS.textMuted))
            card.winrate:SetText("--")
            card.winrate:SetTextColor(unpack(COLORS.textMuted))
            card.honor:SetText("0 Honor")
            card.honor:SetTextColor(unpack(COLORS.textMuted))
            card.progressBar:SetProgress(0, true)

            -- Dimmed
            card.bgIcon:SetAlpha(0.4)
            card.bgName:SetAlpha(0.5)
            card.bgFullName:SetAlpha(0.3)
            card.accentBar:SetAlpha(0.3)
        end
    end

    -- Update session panel
    if totalSession.played > 0 then
        local color = totalSession.winrate >= 50 and COLORS.win or COLORS.loss
        frame.sessionStats:SetText(string.format("%d-%d (%.0f%%)",
            totalSession.wins, totalSession.losses, totalSession.winrate))
        frame.sessionStats:SetTextColor(unpack(color))

        -- Hourly rate (right side)
        if totalSession.hourlyRate > 0 then
            frame.sessionRate:SetText(string.format("%d/hr", totalSession.hourlyRate))
        else
            frame.sessionRate:SetText("")
        end

        -- Rewards on second line
        frame.sessionRewards:SetText(string.format("+%d Honor  +%d Marks",
            totalSession.honor, totalSession.marks))
        frame.sessionRewards:SetTextColor(unpack(COLORS.neutral))
    else
        frame.sessionStats:SetText("No games yet")
        frame.sessionStats:SetTextColor(unpack(COLORS.textTertiary))
        frame.sessionRate:SetText("")
        frame.sessionRewards:SetText("")
    end
end

--------------------------------------------------------------------------------
-- CONTEXT MENU (TBC Classic compatible)
--------------------------------------------------------------------------------
local menuFrame = CreateFrame("Frame", "HonorLogContextMenu", UIParent, "UIDropDownMenuTemplate")

local function InitializeMenu(frame, level, menuList)
    level = level or 1

    if level == 1 then
        -- Title
        local info = UIDropDownMenu_CreateInfo()
        info.text = "|cff40d860HonorLog|r"
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)

        -- Separator
        info = UIDropDownMenu_CreateInfo()
        info.text = ""
        info.disabled = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)

        -- View mode toggle
        info = UIDropDownMenu_CreateInfo()
        info.text = "View: " .. (HonorLog.db.settings.viewMode == "account" and "Account-wide" or "Character")
        info.notCheckable = true
        info.func = function()
            HonorLog.db.settings.viewMode = HonorLog.db.settings.viewMode == "account" and "character" or "account"
            HonorLog:UpdateMainFrame()
        end
        UIDropDownMenu_AddButton(info, level)

        -- Lock/Unlock
        info = UIDropDownMenu_CreateInfo()
        info.text = HonorLog.db.settings.frameLocked and "Unlock Frame" or "Lock Frame"
        info.notCheckable = true
        info.func = function()
            HonorLog.db.settings.frameLocked = not HonorLog.db.settings.frameLocked
            print("|cff40d860HonorLog|r Frame " .. (HonorLog.db.settings.frameLocked and "locked" or "unlocked"))
        end
        UIDropDownMenu_AddButton(info, level)

        -- Separator
        info = UIDropDownMenu_CreateInfo()
        info.text = ""
        info.disabled = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)

        -- Print Stats
        info = UIDropDownMenu_CreateInfo()
        info.text = "Print Stats"
        info.notCheckable = true
        info.func = function() HonorLog:PrintStats() end
        UIDropDownMenu_AddButton(info, level)

        -- Reset Session
        info = UIDropDownMenu_CreateInfo()
        info.text = "Reset Session"
        info.notCheckable = true
        info.func = function()
            HonorLog:ResetSession()
            print("|cff40d860HonorLog|r Session stats reset.")
        end
        UIDropDownMenu_AddButton(info, level)

        -- Reset Stats submenu
        info = UIDropDownMenu_CreateInfo()
        info.text = "Reset Stats"
        info.notCheckable = true
        info.hasArrow = true
        info.menuList = "RESET_STATS"
        UIDropDownMenu_AddButton(info, level)

        -- Export
        info = UIDropDownMenu_CreateInfo()
        info.text = "Export Data"
        info.notCheckable = true
        info.func = function() HonorLog:ShowExportFrame() end
        UIDropDownMenu_AddButton(info, level)

        -- Separator
        info = UIDropDownMenu_CreateInfo()
        info.text = ""
        info.disabled = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)

        -- Options
        info = UIDropDownMenu_CreateInfo()
        info.text = "Options"
        info.notCheckable = true
        info.func = function() HonorLog:OpenOptions() end
        UIDropDownMenu_AddButton(info, level)

        -- Close
        info = UIDropDownMenu_CreateInfo()
        info.text = "Close"
        info.notCheckable = true
        info.func = function() CloseDropDownMenus() end
        UIDropDownMenu_AddButton(info, level)

    elseif level == 2 and menuList == "RESET_STATS" then
        -- Reset Character Stats
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Character Stats"
        info.notCheckable = true
        info.func = function()
            for bgType, _ in pairs(HonorLog.db.char.battlegrounds) do
                HonorLog.db.char.battlegrounds[bgType] = {
                    played = 0, wins = 0, losses = 0,
                    totalDuration = 0, honorLifetime = 0, marksLifetime = 0
                }
            end
            HonorLog.db.char.history = {}
            HonorLog:ResetSession()
            HonorLog:UpdateMainFrame()
            print("|cff40d860HonorLog|r Character stats reset.")
        end
        UIDropDownMenu_AddButton(info, level)

        -- Reset Account Stats
        info = UIDropDownMenu_CreateInfo()
        info.text = "Account Stats"
        info.notCheckable = true
        info.func = function()
            for bgType, _ in pairs(HonorLog.db.global.battlegrounds) do
                HonorLog.db.global.battlegrounds[bgType] = {
                    played = 0, wins = 0, losses = 0,
                    totalDuration = 0, honorLifetime = 0, marksLifetime = 0
                }
            end
            HonorLog.db.global.history = {}
            HonorLog:UpdateMainFrame()
            print("|cff40d860HonorLog|r Account stats reset.")
        end
        UIDropDownMenu_AddButton(info, level)
    end
end

-- Note: We initialize on each show for TBC Classic compatibility

function HonorLog:ShowContextMenu()
    print("|cff00ff00[HonorLog]|r ShowContextMenu called!")

    -- Re-initialize menu each time for TBC Classic compatibility
    UIDropDownMenu_Initialize(menuFrame, InitializeMenu, "MENU")

    -- Use cursor position
    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    cursorX = cursorX / scale
    cursorY = cursorY / scale

    -- Position and show menu
    menuFrame:ClearAllPoints()
    menuFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX, cursorY)

    -- Toggle the dropdown
    ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)

    print("|cff00ff00[HonorLog]|r   Menu toggled at cursor (" .. math.floor(cursorX) .. ", " .. math.floor(cursorY) .. ")")
end

--------------------------------------------------------------------------------
-- LIVE UPDATE TIMER
--------------------------------------------------------------------------------
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
