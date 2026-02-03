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

-- Cache addon metadata at load time
-- TBC Classic Anniversary uses C_AddOns.GetAddOnMetadata, not the global GetAddOnMetadata
local function GetMeta(field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(ADDON_NAME, field)
    elseif GetAddOnMetadata then
        return GetAddOnMetadata(ADDON_NAME, field)
    end
end
local ADDON_VERSION = GetMeta("Version") or "?"
local ADDON_AUTHOR = GetMeta("Author") or "Unknown"

-- BG Icons (from shared UI/Theme.lua)
local BG_ICONS = HonorLog.BG_ICONS

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

    -- Store current values for resize recalculation
    container.currentPercent = 0

    function container:SetProgress(percent, isWin)
        self.currentPercent = percent
        local maxWidth = self:GetWidth()
        local width = math.max(1, maxWidth * (percent / 100))
        fill:SetWidth(width)

        if isWin then
            fill:SetVertexColor(0.25, 0.85, 0.35, 1)
        else
            fill:SetVertexColor(0.90, 0.30, 0.30, 1)
        end
    end

    -- Handle resize to update fill width
    container:SetScript("OnSizeChanged", function(self)
        local maxWidth = self:GetWidth()
        if maxWidth > 0 then
            local width = math.max(1, maxWidth * (self.currentPercent / 100))
            fill:SetWidth(width)
        end
    end)

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
    frame:SetResizable(true)
    frame:SetResizeBounds(220, 60, 450, 500) -- Min width/height, max width/height (scroll handles overflow)
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
    header:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("HonorLog v" .. ADDON_VERSION)
        GameTooltip:AddLine("by " .. ADDON_AUTHOR, 0.7, 0.7, 0.75)
        GameTooltip:Show()
    end)
    header:HookScript("OnLeave", function() GameTooltip:Hide() end)
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

    -- View mode indicator (pill badge)
    local viewModeBg = header:CreateTexture(nil, "ARTWORK")
    viewModeBg:SetSize(50, 16)
    viewModeBg:SetPoint("LEFT", title, "RIGHT", 8, 0)
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

    -- Goals compact view (shown when goals tab is active and minimized)
    local goalsCompactContainer = CreateFrame("Frame", nil, compact)
    goalsCompactContainer:SetAllPoints()
    goalsCompactContainer:Hide()
    frame.goalsCompact = goalsCompactContainer

    -- Goals icon
    local goalsIcon = goalsCompactContainer:CreateTexture(nil, "ARTWORK")
    goalsIcon:SetSize(12, 12)
    goalsIcon:SetPoint("LEFT", PADDING, 0)
    goalsIcon:SetTexture("Interface\\Icons\\INV_Misc_Token_HonorHold")
    goalsIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    goalsIcon:SetAlpha(0.8)
    frame.goalsCompactIcon = goalsIcon

    -- Goals summary text (left side)
    local goalsSummary = goalsCompactContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goalsSummary:SetPoint("LEFT", goalsIcon, "RIGHT", 4, 0)
    goalsSummary:SetJustifyH("LEFT")
    frame.goalsCompactSummary = goalsSummary

    -- Goals currency text (right side)
    local goalsCurrency = goalsCompactContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goalsCurrency:SetPoint("RIGHT", -PADDING, 0)
    goalsCurrency:SetJustifyH("RIGHT")
    frame.goalsCompactCurrency = goalsCurrency

    ----------------------------------------------------------------------------
    -- EXPANDED VIEW (with scroll support)
    ----------------------------------------------------------------------------
    local expanded = CreateFrame("Frame", nil, frame)
    expanded:SetPoint("TOPLEFT", compact, "BOTTOMLEFT", 0, -2)
    expanded:SetPoint("TOPRIGHT", compact, "BOTTOMRIGHT", 0, -2)
    expanded:SetPoint("BOTTOM", frame, "BOTTOM", 0, 5)
    expanded:EnableMouse(true)
    -- Right-click handler set at end of CreateMainFrame
    expanded:Hide()
    frame.expanded = expanded

    -- Scroll Frame for content (leave room at bottom for fixed session panel)
    local scrollFrame = CreateFrame("ScrollFrame", nil, expanded, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 46)  -- Match Goals panel
    frame.scrollFrame = scrollFrame

    -- Style scroll bar to match Goals panel
    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"]
    if scrollBar then
        scrollBar:SetAlpha(0.5)
        -- Darken scrollbar track background
        local track = scrollBar.Track or scrollBar:GetChildren()
        if track and track.SetAlpha then
            track:SetAlpha(0.3)
        end
    end

    -- Scroll content container
    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetWidth(FRAME_WIDTH - 22)
    scrollFrame:SetScrollChild(scrollContent)
    frame.scrollContent = scrollContent

    -- BG Stats Cards
    frame.bgCards = {}
    local yOffset = 0

    for _, bgType in ipairs(HonorLog.BG_ORDER) do
        local card = CreateFrame("Frame", nil, scrollContent, "BackdropTemplate")
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

    -- World PvP Card (same style as BG cards)
    local WORLD_COLOR = { 0.90, 0.55, 0.20, 1 }  -- Orange for world PvP
    local WORLD_GLOW = { 0.80, 0.45, 0.10, 0.3 }

    local worldCard = CreateFrame("Frame", nil, scrollContent, "BackdropTemplate")
    worldCard:SetHeight(CARD_HEIGHT)
    worldCard:SetPoint("TOPLEFT", PADDING, yOffset)
    worldCard:SetPoint("TOPRIGHT", -PADDING, yOffset)
    worldCard:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    worldCard:SetBackdropColor(unpack(COLORS.bgCard))
    worldCard:SetBackdropBorderColor(unpack(COLORS.borderDark))
    worldCard:EnableMouse(true)
    worldCard:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(COLORS.bgCardHover))
        self:SetBackdropBorderColor(unpack(WORLD_GLOW))
        if self.worldIcon then self.worldIcon:SetAlpha(1) end
    end)
    worldCard:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(COLORS.bgCard))
        self:SetBackdropBorderColor(unpack(COLORS.borderDark))
        if self.worldIcon then self.worldIcon:SetAlpha(0.9) end
    end)

    -- Left accent bar (orange)
    local worldAccent = worldCard:CreateTexture(nil, "ARTWORK")
    worldAccent:SetWidth(3)
    worldAccent:SetPoint("TOPLEFT", 0, 0)
    worldAccent:SetPoint("BOTTOMLEFT", 0, 0)
    worldAccent:SetColorTexture(unpack(WORLD_COLOR))
    worldCard.accentBar = worldAccent

    -- World PvP Icon (skull)
    local worldIcon = worldCard:CreateTexture(nil, "ARTWORK")
    worldIcon:SetSize(24, 24)
    worldIcon:SetPoint("LEFT", 6, 0)
    worldIcon:SetTexture("Interface\\Icons\\Ability_DualWield")  -- Skull-like icon
    worldIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    worldIcon:SetAlpha(0.9)
    worldCard.worldIcon = worldIcon

    -- "World" label
    local worldName = worldCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    worldName:SetPoint("LEFT", worldIcon, "RIGHT", 5, 4)
    worldName:SetText("World")
    worldName:SetTextColor(unpack(WORLD_COLOR))
    worldCard.worldName = worldName

    -- "Open World PvP" subtitle
    local worldFullName = worldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    worldFullName:SetPoint("TOPLEFT", worldName, "BOTTOMLEFT", 0, 0)
    worldFullName:SetText("Open World PvP")
    worldFullName:SetTextColor(unpack(COLORS.textTertiary))
    worldCard.worldFullName = worldFullName

    -- Kills/Deaths record (right side)
    local worldRecord = worldCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    worldRecord:SetPoint("TOPRIGHT", -6, -4)
    worldRecord:SetJustifyH("RIGHT")
    worldCard.record = worldRecord

    -- K/D ratio on bottom right
    local worldKD = worldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    worldKD:SetPoint("BOTTOMRIGHT", -6, 5)
    worldKD:SetJustifyH("RIGHT")
    worldCard.kd = worldKD

    -- Session kills (left of K/D)
    local worldSession = worldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    worldSession:SetPoint("RIGHT", worldKD, "LEFT", -8, 0)
    worldSession:SetJustifyH("RIGHT")
    worldSession:SetTextColor(unpack(COLORS.neutral))
    worldCard.sessionText = worldSession

    frame.worldCard = worldCard
    yOffset = yOffset - CARD_HEIGHT - CARD_SPACING

    -- Session Summary Panel (fixed at bottom, outside scroll content)
    local sessionPanel = CreateFrame("Frame", nil, expanded, "BackdropTemplate")
    sessionPanel:SetHeight(36)
    sessionPanel:SetPoint("BOTTOMLEFT", PADDING, 4)
    sessionPanel:SetPoint("BOTTOMRIGHT", -PADDING, 4)
    sessionPanel:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    sessionPanel:SetBackdropColor(0.08, 0.15, 0.20, 0.9)
    sessionPanel:SetBackdropBorderColor(unpack(COLORS.accentDim))
    sessionPanel:EnableMouse(true)
    -- Tooltip explaining today's stats
    sessionPanel:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Today's Progress", 1, 0.82, 0)
        GameTooltip:AddLine("Stats reset at midnight server time", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("W-L", "Wins and losses today", 0.4, 0.8, 1, 0.7, 0.7, 0.7)
        GameTooltip:AddDoubleLine("XX%", "Win rate percentage", 0.4, 0.8, 1, 0.7, 0.7, 0.7)
        GameTooltip:AddDoubleLine("XXX/hr", "Honor earned per hour", 1, 0.84, 0, 0.7, 0.7, 0.7)
        GameTooltip:AddDoubleLine("X-X |TInterface\\Icons\\Ability_DualWield:12|t", "World PvP kills-deaths", 0.9, 0.55, 0.2, 0.7, 0.7, 0.7)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Hourly rate calculated from first BG entry", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    sessionPanel:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    -- Right-click handler set at end of CreateMainFrame
    frame.sessionPanel = sessionPanel

    -- Session label
    local sessionLabel = sessionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sessionLabel:SetPoint("TOPLEFT", 8, -3)
    sessionLabel:SetText("Today:")
    sessionLabel:SetTextColor(unpack(COLORS.accent))

    -- Session stats (W-L and winrate)
    local sessionStats = sessionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sessionStats:SetPoint("LEFT", sessionLabel, "RIGHT", 6, 0)
    sessionStats:SetJustifyH("LEFT")
    frame.sessionStats = sessionStats

    -- World PvP (right side of top line - pairs with W/L stats)
    local sessionWorld = sessionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sessionWorld:SetPoint("TOPRIGHT", -8, -3)
    sessionWorld:SetJustifyH("RIGHT")
    frame.sessionWorld = sessionWorld

    -- Session rewards (second line, left side)
    local sessionRewards = sessionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sessionRewards:SetPoint("BOTTOMLEFT", 8, 3)
    sessionRewards:SetJustifyH("LEFT")
    frame.sessionRewards = sessionRewards

    -- Hourly rate (second line, right side - pairs with honor earned)
    local sessionRate = sessionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sessionRate:SetPoint("BOTTOMRIGHT", -8, 3)
    sessionRate:SetJustifyH("RIGHT")
    sessionRate:SetTextColor(1, 0.84, 0, 1) -- Gold
    frame.sessionRate = sessionRate

    -- Set scroll content height (BG cards + World card + padding)
    local numCards = #HonorLog.BG_ORDER + 1  -- BG cards from BG_ORDER + World card
    local contentHeight = (numCards * CARD_HEIGHT) + (numCards * CARD_SPACING) + 4
    scrollContent:SetHeight(contentHeight)

    -- Function to update scroll content width when frame is resized
    function frame:UpdateScrollContentWidth()
        local frameWidth = self:GetWidth()
        if self.scrollContent then
            self.scrollContent:SetWidth(frameWidth - 22)
        end
    end

    -- Function to update scroll bar visibility
    function frame:UpdateScrollBarVisibility()
        if not self.scrollFrame or not self.scrollContent then return end

        local scrollBar = self.scrollFrame.ScrollBar or _G[self.scrollFrame:GetName() .. "ScrollBar"]
        if not scrollBar then return end

        local viewHeight = self.scrollFrame:GetHeight()
        local contentHeight = self.scrollContent:GetHeight()

        if contentHeight > viewHeight then
            scrollBar:Show()
            scrollBar:SetAlpha(0.6)
        else
            scrollBar:Hide()
            self.scrollFrame:SetVerticalScroll(0)
        end
    end

    -- Update on size change
    frame:SetScript("OnSizeChanged", function(self, width, height)
        self:UpdateScrollContentWidth()
        -- Delay scroll bar update to next frame for proper layout
        C_Timer.After(0, function()
            if self.UpdateScrollBarVisibility then
                self:UpdateScrollBarVisibility()
            end
        end)
    end)

    ----------------------------------------------------------------------------
    -- RESIZE GRIP
    ----------------------------------------------------------------------------
    local resizeGrip = CreateFrame("Button", nil, frame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeGrip:SetFrameLevel(frame:GetFrameLevel() + 10)
    resizeGrip:EnableMouse(true)

    -- Resize grip texture (diagonal lines pattern)
    local gripTexture = resizeGrip:CreateTexture(nil, "ARTWORK")
    gripTexture:SetAllPoints()
    gripTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip.texture = gripTexture

    -- Highlight texture on hover
    local gripHighlight = resizeGrip:CreateTexture(nil, "HIGHLIGHT")
    gripHighlight:SetAllPoints()
    gripHighlight:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")

    -- Resize cursor on hover
    resizeGrip:SetScript("OnEnter", function(self)
        if HonorLog.db.settings.frameResizable and not HonorLog.db.settings.frameLocked then
            self.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        end
    end)

    resizeGrip:SetScript("OnLeave", function(self)
        self.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    end)

    -- Resize functionality
    resizeGrip:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and HonorLog.db.settings.frameResizable and not HonorLog.db.settings.frameLocked then
            frame:StartSizing("BOTTOMRIGHT")
            frame.isResizing = true
        end
    end)

    resizeGrip:SetScript("OnMouseUp", function(self, button)
        if frame.isResizing then
            frame:StopMovingOrSizing()
            frame.isResizing = false

            -- Save the new size
            local width, height = frame:GetSize()
            HonorLog.db.settings.frameSize = { width, height }

            -- Update scroll content width
            if frame.UpdateScrollContentWidth then
                frame:UpdateScrollContentWidth()
            end

            -- Update content layout
            if HonorLog.UpdateFrameLayout then
                HonorLog:UpdateFrameLayout()
            end
        end
    end)

    -- Hide/show resize grip based on settings
    frame.resizeGrip = resizeGrip

    function frame:UpdateResizeGrip()
        if HonorLog.db.settings.frameResizable and not HonorLog.db.settings.frameLocked then
            self.resizeGrip:Show()
            self.resizeGrip:SetAlpha(0.6)
        else
            self.resizeGrip:Hide()
        end
    end

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

    -- Restore custom size if saved
    local savedSize = self.db.settings.frameSize
    if savedSize and savedSize[1] and savedSize[2] then
        -- Only apply width, height is determined by expanded state
        self.savedWidth = savedSize[1]
    end

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

    -- Update resize grip visibility
    if self.mainFrame.UpdateResizeGrip then
        self.mainFrame:UpdateResizeGrip()
    end

    -- Update scroll content width and visibility
    if self.mainFrame.UpdateScrollContentWidth then
        self.mainFrame:UpdateScrollContentWidth()
    end
    C_Timer.After(0.1, function()
        if self.mainFrame and self.mainFrame.UpdateScrollBarVisibility then
            self.mainFrame:UpdateScrollBarVisibility()
        end
    end)

    -- Initial update
    self:UpdateMainFrame()

    -- Real-time update timer for live hourly rate during BGs
    local updateTimer = CreateFrame("Frame")
    local timeSinceUpdate = 0
    local UPDATE_INTERVAL = 1 -- Update every second while in BG for "alive" feel
    updateTimer:SetScript("OnUpdate", function(_, elapsed)
        timeSinceUpdate = timeSinceUpdate + elapsed
        if timeSinceUpdate >= UPDATE_INTERVAL then
            timeSinceUpdate = 0
            -- Only update if in BG, frame is visible, and on stats tab
            if self:IsInBG() and self.mainFrame and self.mainFrame:IsShown() and self.currentTab == "stats" then
                self:UpdateMainFrame()
            end
        end
    end)
end

-- Reset frame size to defaults
function HonorLog:ResetFrameSize()
    self.db.settings.frameSize = nil
    self.savedWidth = nil

    if self.mainFrame then
        self.mainFrame:SetWidth(FRAME_WIDTH)
        if self.db.settings.frameExpanded then
            self.mainFrame:SetHeight(FRAME_HEIGHT_EXPANDED)
        else
            self.mainFrame:SetHeight(FRAME_HEIGHT_COMPACT)
        end
    end

    print("|cff40d860HonorLog|r Frame size reset to default.")
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
    local frame = self.mainFrame

    -- Get saved width or use default
    local savedSize = self.db.settings.frameSize
    local width = (savedSize and savedSize[1]) or FRAME_WIDTH

    -- Determine which view is active (default to stats if not set)
    local currentView = frame.currentView or "stats"

    if expanded then
        frame:SetSize(width, FRAME_HEIGHT_EXPANDED)
        frame.expandBtn.icon:SetTexture("Interface\\Buttons\\UI-MinusButton-UP")

        -- Show the appropriate expanded view based on current tab
        if currentView == "goals" then
            frame.expanded:Hide()
            if frame.goalsPanel then
                frame.goalsPanel:SetAlpha(1) -- Ensure panel is visible (reset from any animation)
                frame.goalsPanel:Show()
                self:UpdateGoalsPanel()
            end
        else
            frame.expanded:SetAlpha(1) -- Ensure panel is visible (reset from any animation)
            frame.expanded:Show()
            if frame.goalsPanel then
                frame.goalsPanel:Hide()
            end
        end

        -- Update scroll bar visibility after showing
        C_Timer.After(0, function()
            if self.mainFrame and self.mainFrame.UpdateScrollBarVisibility then
                self.mainFrame:UpdateScrollBarVisibility()
            end
        end)
    else
        -- Minimized state - hide all expanded views
        frame.expanded:Hide()
        if frame.goalsPanel then
            frame.goalsPanel:Hide()
        end
        frame:SetSize(width, FRAME_HEIGHT_COMPACT)
        frame.expandBtn.icon:SetTexture("Interface\\Buttons\\UI-PlusButton-UP")
    end

    -- Update compact view to show appropriate content
    self:UpdateCompactView()
end

function HonorLog:UpdateCompactView()
    local frame = self.mainFrame
    if not frame then return end

    local currentView = frame.currentView or "stats"

    if currentView == "goals" then
        -- Show goals compact, hide stats compact
        frame.statusIcon:Hide()
        frame.statusLine:Hide()
        frame.sessionQuick:Hide()
        if frame.goalsCompact then
            frame.goalsCompact:Show()
            self:UpdateGoalsCompact()
        end
    else
        -- Show stats compact, hide goals compact
        frame.statusIcon:Show()
        frame.statusLine:Show()
        -- Hide session quick stats when expanded (redundant with Today panel)
        if self.db.settings.frameExpanded then
            frame.sessionQuick:Hide()
        else
            frame.sessionQuick:Show()
        end
        if frame.goalsCompact then
            frame.goalsCompact:Hide()
        end
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
        -- World PvP mode when not in a battleground - always show K/D
        local worldSession = self:GetSessionWorldPvPStats()
        local kills = worldSession and worldSession.kills or 0
        local deaths = worldSession and worldSession.deaths or 0
        local worldText = string.format("World PvP  |cff40d860%d|r-|cffe65959%d|r", kills, deaths)
        frame.statusLine:SetText(worldText)
        frame.statusLine:SetTextColor(0.65, 0.65, 0.72, 1)
        frame.statusIcon:SetTexture("Interface\\Icons\\Ability_DualWield")
        frame.statusIcon:SetVertexColor(0.7, 0.7, 0.75, 0.9)
    end

    -- Session quick stats (compact view)
    local totalSession = self:GetTotalSessionStats()
    if totalSession.played > 0 then
        local color = totalSession.winrate >= 50 and COLORS.win or COLORS.loss
        local quickText = string.format("%d-%d  %.0f%%",
            totalSession.wins, totalSession.losses, totalSession.winrate)
        -- Add hourly rate if available
        if totalSession.hourlyRate > 0 then
            quickText = quickText .. string.format("  |cffffd700%d/hr|r", totalSession.hourlyRate)
        end
        frame.sessionQuick:SetText(quickText)
        frame.sessionQuick:SetTextColor(unpack(color))
    else
        frame.sessionQuick:SetText("--")
        frame.sessionQuick:SetTextColor(unpack(COLORS.textMuted))
    end

    -- Card visibility settings
    local visibleCards = self.db.settings.visibleCards or { AV = true, AB = true, WSG = true, EotS = true, World = true }

    -- Reposition visible BG cards
    local yOffset = 0
    for _, bgType in ipairs(HonorLog.BG_ORDER) do
        local card = frame.bgCards[bgType]
        if card then
            if visibleCards[bgType] ~= false then
                card:Show()
                card:ClearAllPoints()
                card:SetPoint("TOPLEFT", PADDING, yOffset)
                card:SetPoint("TOPRIGHT", -PADDING, yOffset)
                yOffset = yOffset - CARD_HEIGHT - CARD_SPACING
            else
                card:Hide()
            end
        end
    end

    -- Position World card after visible BG cards
    if frame.worldCard then
        if visibleCards.World ~= false then
            frame.worldCard:Show()
            frame.worldCard:ClearAllPoints()
            frame.worldCard:SetPoint("TOPLEFT", PADDING, yOffset)
            frame.worldCard:SetPoint("TOPRIGHT", -PADDING, yOffset)
        else
            frame.worldCard:Hide()
        end
    end

    -- Update BG cards
    for bgType, card in pairs(frame.bgCards) do
        if not card:IsShown() then
            -- Skip hidden cards
        else
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
            card.record:SetText("0-0")
            card.record:SetTextColor(unpack(COLORS.textMuted))
            card.winrate:SetText("0%")
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
        end -- closes else for visible card
    end

    -- Update World PvP card (only if visible)
    local worldCard = frame.worldCard
    if worldCard and visibleCards.World ~= false then
        local worldStats = self:GetWorldPvPStats(scope)
        local worldSession = self:GetSessionWorldPvPStats()

        if worldStats.kills > 0 or worldStats.deaths > 0 or (worldStats.honor and worldStats.honor > 0) then
            -- Kills-Deaths record (matches BG card W-L style)
            worldCard.record:SetText(string.format("|cff40d860%d|r-|cffe65959%d|r", worldStats.kills, worldStats.deaths))

            -- Honor + K/D ratio (matches BG card "21.7k Honor  26%" style)
            local kd = worldStats.deaths > 0 and (worldStats.kills / worldStats.deaths) or worldStats.kills
            local kdColor = kd >= 1 and COLORS.win or COLORS.loss
            local worldHonor = worldStats.honor or 0
            local honorText
            if worldHonor >= 1000 then
                honorText = string.format("%.1fk Honor  ", worldHonor / 1000)
            else
                honorText = string.format("%d Honor  ", worldHonor)
            end
            worldCard.kd:SetText(string.format("%s|cff%s%.1f K/D|r", honorText, kd >= 1 and "40d860" or "e65959", kd))
            worldCard.kd:SetTextColor(unpack(COLORS.neutralDim))

            -- Session kills/deaths (only show if different from lifetime)
            local sessionDiffers = worldSession.kills ~= worldStats.kills or worldSession.deaths ~= worldStats.deaths
            if sessionDiffers and (worldSession.kills > 0 or worldSession.deaths > 0) then
                worldCard.sessionText:SetText(string.format("Today: %d-%d", worldSession.kills, worldSession.deaths))
            else
                worldCard.sessionText:SetText("")
            end

            -- Full opacity
            worldCard.worldIcon:SetAlpha(0.9)
            worldCard.worldName:SetAlpha(1)
            worldCard.worldFullName:SetAlpha(0.7)
            worldCard.accentBar:SetAlpha(1)
        else
            worldCard.record:SetText("0-0")
            worldCard.record:SetTextColor(unpack(COLORS.textMuted))
            worldCard.sessionText:SetText("0 Honor")
            worldCard.sessionText:SetTextColor(unpack(COLORS.textMuted))
            worldCard.kd:SetText("0.0 K/D")
            worldCard.kd:SetTextColor(unpack(COLORS.textMuted))

            -- Dimmed
            worldCard.worldIcon:SetAlpha(0.4)
            worldCard.worldName:SetAlpha(0.5)
            worldCard.worldFullName:SetAlpha(0.3)
            worldCard.accentBar:SetAlpha(0.3)
        end
    end

    -- Update session panel
    if totalSession.played > 0 then
        local color = totalSession.winrate >= 50 and COLORS.win or COLORS.loss

        -- Line 1 left: BG stats
        frame.sessionStats:SetText(string.format("%d-%d (%.0f%%)", totalSession.wins, totalSession.losses, totalSession.winrate))
        frame.sessionStats:SetTextColor(unpack(color))

        -- Line 1 right: Hourly rate
        if totalSession.hourlyRate > 0 then
            frame.sessionRate:SetText(string.format("%d/hr", totalSession.hourlyRate))
        else
            frame.sessionRate:SetText("")
        end

        -- Line 2 left: Honor + marks (currency earned)
        local rewardsText = string.format("|cffffd100+%d Honor|r", totalSession.honor)
        local marksBreakdown = {}
        for _, bgType in ipairs(HonorLog.BG_ORDER) do
            local bgSession = self.db.char.session[bgType]
            if bgSession and bgSession.marks > 0 then
                local icon = BG_ICONS[bgType]
                local colorHex = HonorLog.BG_COLOR_HEX[bgType] or "ffffff"
                -- Format: count [icon] with space before icon (matches goals panel)
                table.insert(marksBreakdown, string.format("|cff%s%d|r |T%s:14:14:0:0|t", colorHex, bgSession.marks, icon))
            end
        end
        if #marksBreakdown > 0 then
            rewardsText = rewardsText .. " · " .. table.concat(marksBreakdown, " ")
        end
        frame.sessionRewards:SetText(rewardsText)
        frame.sessionRewards:SetTextColor(unpack(COLORS.neutral))

        -- Line 2 right: World PvP (always shown)
        local worldSession = self:GetSessionWorldPvPStats()
        local worldKills = worldSession and worldSession.kills or 0
        local worldDeaths = worldSession and worldSession.deaths or 0
        local worldHonor = worldSession and worldSession.honor or 0
        local honorText = ""
        if worldHonor > 0 then
            honorText = string.format(" |cffffd100(+%d)|r", worldHonor)
        end
        frame.sessionWorld:SetText(string.format("|cffe5a040%d|r-|cffe65959%d|r%s |T%s:14:14:0:0|t",
            worldKills, worldDeaths, honorText, "Interface\\Icons\\Ability_DualWield"))
    else
        frame.sessionStats:SetText("No games yet")
        frame.sessionStats:SetTextColor(unpack(COLORS.textTertiary))
        frame.sessionRate:SetText("")
        frame.sessionRewards:SetText("")
        -- Still show World PvP even with no BGs (always visible per changelog)
        local worldSession = self:GetSessionWorldPvPStats()
        local worldKills = worldSession and worldSession.kills or 0
        local worldDeaths = worldSession and worldSession.deaths or 0
        local worldHonor = worldSession and worldSession.honor or 0
        local honorText = ""
        if worldHonor > 0 then
            honorText = string.format(" |cffffd100(+%d)|r", worldHonor)
        end
        frame.sessionWorld:SetText(string.format("|cffe5a040%d|r-|cffe65959%d|r%s |T%s:14:14:0:0|t",
            worldKills, worldDeaths, honorText, "Interface\\Icons\\Ability_DualWield"))
    end

    -- Update goals compact if in goals view
    if frame.currentView == "goals" and self.UpdateGoalsCompact then
        self:UpdateGoalsCompact()
    end
end

--------------------------------------------------------------------------------
-- GOALS COMPACT VIEW UPDATE
--------------------------------------------------------------------------------
function HonorLog:UpdateGoalsCompact()
    if not self.mainFrame then return end
    local frame = self.mainFrame

    -- Use GetAllGoalsProgress to get actual displayable goals (filters out orphans)
    local goals = self:GetAllGoalsProgress() or {}
    local goalCount = #goals
    local completedGoals = self:GetCompletedGoals()
    local numCompleted = 0
    if completedGoals and type(completedGoals) == "table" then
        for _ in pairs(completedGoals) do
            numCompleted = numCompleted + 1
        end
    end

    if goalCount == 0 and numCompleted > 0 then
        -- All goals complete!
        frame.goalsCompactSummary:SetText(string.format("%d/%d goals · 100%%", numCompleted, numCompleted))
        frame.goalsCompactSummary:SetTextColor(0.30, 0.90, 0.40, 1) -- Green
        frame.goalsCompactIcon:SetTexture("Interface\\Icons\\Spell_Holy_Crusade") -- TBC-safe checkmark/victory icon
        frame.goalsCompactIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        frame.goalsCompactIcon:SetVertexColor(0.3, 0.9, 0.4, 1)
        frame.goalsCompactCurrency:SetText("|cff40d860All complete!|r")
    elseif goalCount == 0 then
        frame.goalsCompactSummary:SetText("No goals set")
        frame.goalsCompactSummary:SetTextColor(unpack(COLORS.textTertiary))
        frame.goalsCompactIcon:SetTexture("Interface\\Icons\\INV_Misc_Token_HonorHold")
        frame.goalsCompactIcon:SetVertexColor(0.5, 0.5, 0.5, 0.7)
        frame.goalsCompactCurrency:SetText("")
    else
        -- Get top goal info
        local goals = self:GetAllGoalsProgress()
        if goals and #goals > 0 then
            local topGoal = goals[1]

            -- Update icon to match top goal
            local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(topGoal.itemID)
            if itemTexture then
                frame.goalsCompactIcon:SetTexture(itemTexture)
            else
                frame.goalsCompactIcon:SetTexture("Interface\\Icons\\INV_Misc_Token_HonorHold")
            end
            frame.goalsCompactIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            frame.goalsCompactIcon:SetVertexColor(1, 1, 1, 0.9)

            -- Calculate overall progress (same weighted calculation as totals bar)
            local totalHonorNeeded = 0
            local totalArenaNeeded = 0
            local totalMarksNeeded = { AV = 0, AB = 0, WSG = 0, EotS = 0 }

            local totalGamesNeeded = 0
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
                -- Sum up games needed for each goal
                if goal.totalGamesNeeded and goal.totalGamesNeeded > 0 then
                    totalGamesNeeded = totalGamesNeeded + goal.totalGamesNeeded
                end
            end

            -- Get actual player currency for active goals
            local totalHonorCurrent = math.min(self:GetCurrentHonor(), totalHonorNeeded)
            local totalArenaCurrent = math.min(self:GetCurrentArenaPoints(), totalArenaNeeded)

            -- Include completed goals at 100% progress (cumulative tracking)
            local completedHonorTotal = 0
            local completedArenaTotal = 0
            local completedMarksTotal = { AV = 0, AB = 0, WSG = 0, EotS = 0 }

            if completedGoals then
                for _, completedGoal in ipairs(completedGoals) do
                    local itemData = self.GearDB and self.GearDB[completedGoal.itemID]
                    if itemData then
                        if itemData.honor and itemData.honor > 0 then
                            completedHonorTotal = completedHonorTotal + itemData.honor
                        end
                        if itemData.arena and itemData.arena > 0 then
                            completedArenaTotal = completedArenaTotal + itemData.arena
                        end
                        if itemData.marks then
                            for bgType, markCount in pairs(itemData.marks) do
                                if markCount > 0 then
                                    completedMarksTotal[bgType] = completedMarksTotal[bgType] + markCount
                                end
                            end
                        end
                    end
                end
            end

            -- Calculate weighted total (active + completed goals)
            local totalNeeded = 0
            local totalCurrent = 0

            -- Active goals: current progress toward needed
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
                    local marksCurrent = math.min(self:GetCurrentMarks(bgType), totalMarksNeeded[bgType])
                    totalNeeded = totalNeeded + (totalMarksNeeded[bgType] * 100)
                    totalCurrent = totalCurrent + (marksCurrent * 100)
                end
            end

            -- Completed goals: 100% progress (add to both needed AND current)
            if completedHonorTotal > 0 then
                totalNeeded = totalNeeded + completedHonorTotal
                totalCurrent = totalCurrent + completedHonorTotal
            end
            if completedArenaTotal > 0 then
                totalNeeded = totalNeeded + completedArenaTotal
                totalCurrent = totalCurrent + completedArenaTotal
            end
            for _, bgType in ipairs(HonorLog.BG_ORDER) do
                if completedMarksTotal[bgType] > 0 then
                    totalNeeded = totalNeeded + (completedMarksTotal[bgType] * 100)
                    totalCurrent = totalCurrent + (completedMarksTotal[bgType] * 100)
                end
            end

            local avgProgress = totalNeeded > 0 and (totalCurrent / totalNeeded * 100) or 100

            -- Summary text - completion ratio format (14/16 goals · 88% · ~Xg)
            local summaryText
            local totalGoalCount = #goals + numCompleted

            if avgProgress >= 100 then
                -- All active goals ready to purchase
                summaryText = string.format("%d/%d goals · 100%%", numCompleted, totalGoalCount)
            elseif totalGamesNeeded > 0 then
                -- In progress with games estimate
                summaryText = string.format("%d/%d goals · %.0f%% · %d games", numCompleted, totalGoalCount, avgProgress, totalGamesNeeded)
            else
                -- In progress but no games estimate available
                summaryText = string.format("%d/%d goals · %.0f%%", numCompleted, totalGoalCount, avgProgress)
            end
            frame.goalsCompactSummary:SetText(summaryText)

            -- Color based on progress
            if avgProgress >= 100 then
                frame.goalsCompactSummary:SetTextColor(unpack(COLORS.progressFull))
            elseif avgProgress >= 50 then
                frame.goalsCompactSummary:SetTextColor(unpack(COLORS.progressPartial))
            else
                frame.goalsCompactSummary:SetTextColor(unpack(COLORS.textPrimary))
            end

            -- Currency display (current honor)
            local currentHonor = self:GetCurrentHonor()
            frame.goalsCompactCurrency:SetText(string.format("|cffffd700%s|r Honor", BreakUpLargeNumbers(currentHonor)))
        end
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
            if HonorLog.mainFrame and HonorLog.mainFrame.UpdateResizeGrip then
                HonorLog.mainFrame:UpdateResizeGrip()
            end
        end
        UIDropDownMenu_AddButton(info, level)

        -- Enable/Disable Resizing
        info = UIDropDownMenu_CreateInfo()
        info.text = HonorLog.db.settings.frameResizable and "Disable Resizing" or "Enable Resizing"
        info.notCheckable = true
        info.func = function()
            HonorLog.db.settings.frameResizable = not HonorLog.db.settings.frameResizable
            print("|cff40d860HonorLog|r Frame resizing " .. (HonorLog.db.settings.frameResizable and "enabled" or "disabled"))
            if HonorLog.mainFrame and HonorLog.mainFrame.UpdateResizeGrip then
                HonorLog.mainFrame:UpdateResizeGrip()
            end
        end
        UIDropDownMenu_AddButton(info, level)

        -- Reset Frame Size
        info = UIDropDownMenu_CreateInfo()
        info.text = "Reset Frame Size"
        info.notCheckable = true
        info.func = function()
            HonorLog:ResetFrameSize()
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
        info.text = "Reset Today"
        info.notCheckable = true
        info.func = function()
            HonorLog:ResetSession()
            print("|cff40d860HonorLog|r Today's stats reset.")
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
            -- Also reset World PvP stats
            HonorLog.db.char.worldPvP = { kills = 0, deaths = 0, honor = 0 }
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
            -- Also reset World PvP stats
            HonorLog.db.global.worldPvP = { kills = 0, deaths = 0, honor = 0 }
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
            -- Also update goals panel if it's visible (for real-time progress tracking)
            if HonorLog.mainFrame.goalsPanel and HonorLog.mainFrame.goalsPanel:IsShown() then
                HonorLog:UpdateGoalsPanel()
            end
        end
    end
end

HonorLog.eventFrame:SetScript("OnUpdate", OnUpdate)
