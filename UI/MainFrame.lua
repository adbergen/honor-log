-- HonorLog Main Frame
-- Enterprise-level UI inspired by Details!, WeakAuras, and ElvUI

local ADDON_NAME, HonorLog = ...

-- Forever-safe wrappers (defined in Data.lua)
local GetItemInfo = HonorLog.Compat.GetItemInfo

--------------------------------------------------------------------------------
-- THEME (from shared UI/Theme.lua)
--------------------------------------------------------------------------------
local COLORS = HonorLog.Theme
local BG_COLORS = HonorLog.BG_COLORS
local BG_GLOW_COLORS = HonorLog.BG_GLOW_COLORS

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
local RANK_BAR_HEIGHT = Layout.RANK_BAR_HEIGHT
local RANK_BAR_GAP = Layout.RANK_BAR_GAP

-- Rank UI state (bar, tab, panel) lives here, not on the frame, so a missing piece reads as nil.
local ui = {}
HonorLog.rankUI = ui

-- Extra frame height while the rank bar is shown.
local function RankBarExtra()
    return ui.barActive and (RANK_BAR_HEIGHT + RANK_BAR_GAP) or 0
end

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

-- Create glow border (rounded)
local function CreateGlowBorder(frame, color)
    local glow = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    glow:SetPoint("TOPLEFT", -3, 3)
    glow:SetPoint("BOTTOMRIGHT", 3, -3)
    glow:SetBackdrop({
        bgFile = nil,
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
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
    frame:SetBackdropBorderColor(0.18, 0.18, 0.22, 1) -- Clean dark border

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
    local headerMoving = false
    header:SetScript("OnDragStart", function()
        if HonorLog.db.settings.frameLocked then return end -- "Lock Frame Position"
        headerMoving = true
        frame:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        if not headerMoving then return end
        headerMoving = false
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
            HonorLog:ShowBGTooltip(self, bgType)
        end)
        card:SetScript("OnLeave", function(self)
            self:SetBackdropColor(unpack(COLORS.bgCard))
            self:SetBackdropBorderColor(unpack(COLORS.borderDark))
            if self.bgIcon then self.bgIcon:SetAlpha(0.9) end
            GameTooltip:Hide()
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
        bgName:SetText(HonorLog:GetBGShortName(bgType))
        bgName:SetTextColor(unpack(BG_COLORS[bgType]))
        card.bgName = bgName

        -- Full BG name (smaller, below abbreviation)
        local bgFullName = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bgFullName:SetPoint("TOPLEFT", bgName, "BOTTOMLEFT", 0, 0)
        bgFullName:SetText(HonorLog:GetBGDisplayName(bgType))
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
        HonorLog:ShowWorldTooltip(self)
    end)
    worldCard:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(COLORS.bgCard))
        self:SetBackdropBorderColor(unpack(COLORS.borderDark))
        if self.worldIcon then self.worldIcon:SetAlpha(0.9) end
        GameTooltip:Hide()
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
        local honor = HonorLog:GetHonorSummary()
        GameTooltip:AddDoubleLine("Honor today", tostring(honor.today), 1, 0.84, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("Honor this week", tostring(honor.week), 1, 0.84, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("Honor this session", tostring(honor.session), 1, 0.84, 0, 1, 1, 1)
        if honor.cap > 0 then
            GameTooltip:AddDoubleLine("Honor now / cap", string.format("%d / %d", honor.current, honor.cap), 1, 0.84, 0, 0.7, 0.7, 0.7)
        end
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
--------------------------------------------------------------------------------
-- TOOLTIPS: recent games per battleground, world PvP detail
--------------------------------------------------------------------------------
local RECENT_GAMES = 5

function HonorLog:ShowBGTooltip(anchor, bgType)
    local scope = self.db.settings.viewMode
    local stats = self:GetBGStats(bgType, scope)
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    GameTooltip:SetText(self:GetBGDisplayName(bgType), unpack(self:GetBGColor(bgType)))
    GameTooltip:AddDoubleLine("Won / lost", string.format("%d / %d", stats.wins, stats.losses), 0.7, 0.7, 0.7, 1, 1, 1)
    if (stats.draws or 0) > 0 or (stats.left or 0) > 0 then
        GameTooltip:AddDoubleLine("Draws / left early", string.format("%d / %d", stats.draws or 0, stats.left or 0), 0.7, 0.7, 0.7, 1, 1, 1)
    end
    local shown = 0
    for _, entry in ipairs(self:GetHistory(scope, 500)) do
        if entry.bgType == bgType then
            if shown == 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Recent games (K/HK/D)", 1, 0.82, 0)
            end
            GameTooltip:AddLine(self:FormatHistoryRow(entry), 1, 1, 1)
            shown = shown + 1
            if shown >= RECENT_GAMES then break end
        end
    end
    GameTooltip:Show()
end

function HonorLog:ShowWorldTooltip(anchor)
    local scope = self.db.settings.viewMode
    local world = self:GetWorldPvPStats(scope)
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    GameTooltip:SetText("World PvP", 0.9, 0.55, 0.2)
    GameTooltip:AddDoubleLine("Kills / deaths", string.format("%d / %d", world.kills, world.deaths), 0.7, 0.7, 0.7, 1, 1, 1)
    if (world.killingBlows or 0) > 0 or (world.unknownKills or 0) > 0 then
        GameTooltip:AddDoubleLine("Killing blows / unattributed", string.format("%d / %d", world.killingBlows or 0, world.unknownKills or 0), 0.7, 0.7, 0.7, 1, 1, 1)
    end
    local split = self:GetWorldHonorSplit(scope)
    GameTooltip:AddDoubleLine("Honor (kills / awards / other)",
        string.format("%d / %d / %d", split.kill, split.award, split.other), 0.7, 0.7, 0.7, 1, 0.82, 0)
    local top = self:GetTopOpponents(5)
    if #top > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Top opponents (kills / deaths)", 1, 0.82, 0)
        for _, o in ipairs(top) do
            GameTooltip:AddDoubleLine(o.name .. (o.class and (" |cff888888" .. o.class .. "|r") or ""),
                string.format("%d / %d", o.kills, o.deaths), 1, 1, 1, 0.7, 0.7, 0.7)
        end
    end
    GameTooltip:Show()
end

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
end

-- Reset frame size to defaults
function HonorLog:ResetFrameSize()
    self.db.settings.frameSize = nil
    self.savedWidth = nil

    if self.mainFrame then
        self.mainFrame:SetWidth(FRAME_WIDTH)
        if self.db.settings.frameExpanded then
            self.mainFrame:SetHeight(FRAME_HEIGHT_EXPANDED + RankBarExtra())
        else
            self.mainFrame:SetHeight(FRAME_HEIGHT_COMPACT + RankBarExtra())
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
        frame:SetSize(width, FRAME_HEIGHT_EXPANDED + RankBarExtra())
        frame.expandBtn.icon:SetTexture("Interface\\Buttons\\UI-MinusButton-UP")

        -- Show the appropriate expanded view based on current tab
        if currentView == "rank" and ui.panel then
            frame.expanded:Hide()
            if frame.goalsPanel then frame.goalsPanel:Hide() end
            ui.panel:Show()
            self:UpdateRankUI(self.Rank and self.Rank:GetInfo())
        elseif currentView == "goals" then
            frame.expanded:Hide()
            if ui.panel then ui.panel:Hide() end
            if frame.goalsPanel then
                frame.goalsPanel:SetAlpha(1) -- Ensure panel is visible (reset from any animation)
                frame.goalsPanel:Show()
                self:UpdateGoalsPanel()
            end
        else
            frame.expanded:SetAlpha(1) -- Ensure panel is visible (reset from any animation)
            frame.expanded:Show()
            if ui.panel then ui.panel:Hide() end
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
        if ui.panel then ui.panel:Hide() end
        frame:SetSize(width, FRAME_HEIGHT_COMPACT + RankBarExtra())
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

    self:UpdateRankUI(self.Rank and self.Rank:GetInfo())

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
        local statusText = string.format("%s  -  %s", self:GetBGShortName(currentBG), self:FormatDuration(duration))
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
        local worldHonor = worldSession and worldSession.honor or 0
        local honorStr = worldHonor >= 1000 and string.format("%.1fk", worldHonor / 1000) or tostring(worldHonor)
        local worldText = string.format("World PvP  |cff40d860%d|r|cff888888-|r|cffe65959%d|r  |cffffd700%s Honor|r", kills, deaths, honorStr)
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
    local visibleCards = self.db.settings.visibleCards or { AV = true, WSG = true, AB = true, DI = true, World = true }

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
        frame.goalsCompactIcon:SetTexture("Interface\\Icons\\Spell_Holy_Crusade") -- checkmark/victory icon
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

            -- Overall progress and games for the whole list: the same roll-up as the totals bar
            local totals = self:GetGoalsTotals(goals)
            local avgProgress = totals.percent
            local totalGamesNeeded = totals.games

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

            -- Currency display: current honor, or the cap advice when honor is about to be wasted
            local currentHonor = self:GetCurrentHonor()
            local advice = self:GetHonorCapAdvice(goals)
            if advice then
                frame.goalsCompactCurrency:SetText(string.format("|cffffd700%s|r Honor · |cffff8040%s|r", BreakUpLargeNumbers(currentHonor), advice.text))
            else
                frame.goalsCompactCurrency:SetText(string.format("|cffffd700%s|r Honor", BreakUpLargeNumbers(currentHonor)))
            end
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
                HonorLog.db.char.battlegrounds[bgType] = HonorLog.NewBGStats()
            end
            -- Also reset World PvP stats and the opponents list
            HonorLog.db.char.worldPvP = HonorLog.NewWorldStats()
            HonorLog.db.char.opponents = {}
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
                HonorLog.db.global.battlegrounds[bgType] = HonorLog.NewBGStats()
            end
            -- Also reset World PvP stats
            HonorLog.db.global.worldPvP = HonorLog.NewWorldStats()
            HonorLog.db.global.history = {}
            HonorLog:UpdateMainFrame()
            print("|cff40d860HonorLog|r Account stats reset.")
        end
        UIDropDownMenu_AddButton(info, level)
    end
end

-- Note: We initialize on each show for TBC Classic compatibility

function HonorLog:ShowContextMenu()
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

--------------------------------------------------------------------------------
-- RANK BAR AND RANK TAB
--------------------------------------------------------------------------------
-- The bar sits under the header; the Rank tab holds the summary and the table of
-- ranks 1-14. Data comes from HonorLog.Rank; with no rank data the bar and the tab
-- stay hidden. GoalsPanel.lua owns SwitchTab for Stats and Goals, so the Rank tab
-- wraps it instead of editing it.

local function commas(n) return HonorLog.Rank.FormatNumber(n) end

-- Rank badge: the atlas Blizzard's rank window uses, else the classic badge file,
-- else a neutral icon for unranked or unknown.
local function SetRankIcon(tex, rank)
    tex:SetTexCoord(0, 1, 0, 1)
    if rank and rank > 0 and rank <= HonorLog.Rank.MAX_RANK then
        local atlas = string.format(HonorLog.RANK_ICON_ATLAS, rank)
        local known = true
        if C_Texture and C_Texture.GetAtlasInfo then known = C_Texture.GetAtlasInfo(atlas) ~= nil end
        if known and tex.SetAtlas and pcall(tex.SetAtlas, tex, atlas) then return end
        tex:SetTexture(string.format(HonorLog.RANK_ICON_FILE, rank))
        return
    end
    tex:SetTexture(HonorLog.RANK_ICON_FALLBACK)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

local function CreateRankTabButton(parent, text)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(Layout.TAB_WIDTH, Layout.TAB_HEIGHT)
    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.15, 0.15, 0.20, 0.8)
    tab.bg = bg
    local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", 0, 0)
    label:SetText(text)
    label:SetTextColor(unpack(COLORS.textSecondary))
    tab.label = label
    local active = tab:CreateTexture(nil, "OVERLAY")
    active:SetHeight(2)
    active:SetPoint("BOTTOMLEFT", 1, 0)
    active:SetPoint("BOTTOMRIGHT", -1, 0)
    active:SetColorTexture(unpack(COLORS.brand))
    active:Hide()
    tab.activeIndicator = active
    tab:SetScript("OnEnter", function(self)
        if not self.isActive then self.bg:SetColorTexture(0.20, 0.20, 0.25, 0.9) end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("PvP Rank")
        GameTooltip:AddLine("Rank, weekly cap and the plan to any rank", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function(self)
        if not self.isActive then self.bg:SetColorTexture(0.15, 0.15, 0.20, 0.8) end
        GameTooltip:Hide()
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

local function CreateRankBar(frame)
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetHeight(RANK_BAR_HEIGHT)
    bar:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -RANK_BAR_GAP)
    bar:SetPoint("TOPRIGHT", frame.header, "BOTTOMRIGHT", 0, -RANK_BAR_GAP)
    bar:EnableMouse(true)

    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(RANK_BAR_HEIGHT - 2, RANK_BAR_HEIGHT - 2)
    icon:SetPoint("LEFT", PADDING, 0)
    bar.icon = icon

    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    title:SetWidth(92)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetTextColor(unpack(COLORS.accent))
    bar.title = title

    local track = CreateFrame("Frame", nil, bar)
    track:SetHeight(RANK_BAR_HEIGHT - 4)
    track:SetPoint("LEFT", title, "RIGHT", 4, 0)
    track:SetPoint("RIGHT", bar, "RIGHT", -PADDING, 0)
    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    trackBg:SetColorTexture(0.12, 0.12, 0.15, 0.9)
    local fill = track:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMLEFT", 0, 0)
    fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    fill:SetVertexColor(unpack(COLORS.rankFill))
    fill:SetWidth(1)
    local marker = track:CreateTexture(nil, "OVERLAY")
    marker:SetWidth(2)
    marker:SetPoint("TOP", track, "TOP", 0, 0)
    marker:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
    marker:SetColorTexture(unpack(COLORS.rankCap))
    marker:Hide()
    local text = track:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", 0, 0)
    bar.track, bar.fill, bar.marker, bar.text = track, fill, marker, text

    -- The fill and the marker are widths of the track, so a resize redraws them.
    function bar:Layout()
        local w = self.track:GetWidth() or 0
        self.fill:SetWidth(math.max(1, w * (ui.percent or 0) / 100))
        if ui.markerAt then
            self.marker:ClearAllPoints()
            self.marker:SetPoint("TOP", self.track, "TOPLEFT", w * ui.markerAt, 0)
            self.marker:SetPoint("BOTTOM", self.track, "BOTTOMLEFT", w * ui.markerAt, 0)
            self.marker:Show()
        else
            self.marker:Hide()
        end
    end
    track:SetScript("OnSizeChanged", function() bar:Layout() end)

    bar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:ClearLines()
        if HonorLog.Rank and HonorLog.Rank:AddTooltipLines(GameTooltip) then GameTooltip:Show() end
    end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        HonorLog:SwitchTab("rank")
        if not HonorLog.db.settings.frameExpanded then HonorLog:SetExpanded(true) end
    end)
    bar:Hide()
    return bar
end

-- Rank, points, cap: "1,240 / 1,800 · cap R8".
local function RankBarText(info)
    local parts = {}
    if info.threshold > 0 then
        parts[1] = commas(info.points) .. " / " .. commas(info.threshold)
    else
        parts[1] = commas(info.totalPoints) .. " pts"
    end
    if info.gate and info.gate.blocking then
        -- The full sentence is in the tooltip and on the Rank tab; the bar only has room for this.
        parts[#parts + 1] = string.format(HonorLog.L["Rank %d needs level %d"], info.gate.rank, info.gate.level)
    elseif info.weekCapRank > 0 then
        parts[#parts + 1] = (info.capped and "capped R" or "cap R") .. info.weekCapRank
    end
    return table.concat(parts, " \194\183 ")
end

local function UpdateRankBar(frame, info, show)
    local bar = ui.bar
    local was = ui.barActive or false
    ui.barActive = show and true or false
    if show then
        bar:Show()
        SetRankIcon(bar.icon, info.rank)
        bar.title:SetText(info.rank > 0 and string.format("R%d %s", info.rank, info.title) or info.title)
        bar.text:SetText(RankBarText(info))
        ui.percent = info.percent
        -- A marker where the weekly cap falls inside the current rank.
        local capPos = info.weekCapTotal - (info.totalPoints - info.points)
        ui.markerAt = (info.threshold > 0 and capPos > 0 and capPos < info.threshold) and (capPos / info.threshold) or nil
        bar:Layout()
    else
        bar:Hide()
    end
    if was ~= ui.barActive then
        frame.compact:ClearAllPoints()
        local anchor = show and bar or frame.header
        frame.compact:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        frame.compact:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
        local expanded = HonorLog.db.settings.frameExpanded
        frame:SetHeight((expanded and FRAME_HEIGHT_EXPANDED or FRAME_HEIGHT_COMPACT) + RankBarExtra())
    end
end

local rewardOf = setmetatable({}, { __mode = "k" }) -- icon button -> reward

local function CreateRankRow(parent, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(Layout.RANK_ROW_HEIGHT)
    row:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    row:SetPoint("TOPLEFT", PADDING, -(index - 1) * (Layout.RANK_ROW_HEIGHT + 2))
    row:SetPoint("TOPRIGHT", -PADDING, -(index - 1) * (Layout.RANK_ROW_HEIGHT + 2))

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("TOPLEFT", 6, -4)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.tag:SetJustifyH("RIGHT")

    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detail:SetPoint("BOTTOMLEFT", 6, 4)
    row.detail:SetPoint("BOTTOMRIGHT", -4, 4)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    row.detail:SetTextColor(unpack(COLORS.textSecondary))

    -- Reward icons, right to left; each shows its description on hover.
    row.icons = {}
    for i = 1, 3 do
        local btn = CreateFrame("Button", nil, row)
        btn:SetSize(14, 14)
        btn:SetPoint("TOPRIGHT", -4 - (i - 1) * 16, -3)
        btn.tex = btn:CreateTexture(nil, "ARTWORK")
        btn.tex:SetAllPoints()
        btn.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn:SetScript("OnEnter", function(self)
            local reward = rewardOf[self]
            if not reward then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(reward.description or reward.name or "Reward")
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:Hide()
        row.icons[i] = btn
    end
    row.tag:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4 - 3 * 16, -4)
    row.name:SetPoint("TOPRIGHT", row.tag, "TOPLEFT", -4, 0)
    return row
end

local function CreateRankPanel(frame)
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT", frame.compact, "BOTTOMLEFT", 0, -2)
    panel:SetPoint("TOPRIGHT", frame.compact, "BOTTOMRIGHT", 0, -2)
    panel:SetPoint("BOTTOM", 0, 5)

    panel.lines = {}
    for i = 1, 4 do
        local fs = panel:CreateFontString(nil, "OVERLAY", i == 1 and "GameFontNormal" or "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", PADDING, -4 - (i == 1 and 0 or 4 + (i - 1) * 13))
        fs:SetPoint("TOPRIGHT", -PADDING, -4 - (i == 1 and 0 or 4 + (i - 1) * 13))
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        if i > 1 then fs:SetTextColor(unpack(COLORS.textSecondary)) end
        panel.lines[i] = fs
    end

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -Layout.RANK_SUMMARY_HEIGHT)
    scroll:SetPoint("BOTTOMRIGHT", -22, 2)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(FRAME_WIDTH - 22)
    content:SetHeight(HonorLog.Rank.MAX_RANK * (Layout.RANK_ROW_HEIGHT + 2))
    scroll:SetScrollChild(content)
    panel.scroll, panel.content = scroll, content
    scroll:SetScript("OnSizeChanged", function(_, width) if width and width > 0 then content:SetWidth(width) end end)

    panel.rows = {}
    for n = 1, HonorLog.Rank.MAX_RANK do panel.rows[n] = CreateRankRow(content, n) end

    -- Below the rank rows: one row per battleground that gives no points, then the measured points
    -- per result. Rows are made when first needed and reuse the rank row style.
    panel.extraRows = {}
    panel.extraHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.extraHeader:SetJustifyH("LEFT")
    panel.extraHeader:SetTextColor(unpack(COLORS.textSecondary))
    local function extraRow(slot)
        local row = panel.extraRows[slot]
        if not row then
            row = CreateRankRow(content, HonorLog.Rank.MAX_RANK + slot)
            row.icons[1]:Hide() row.icons[2]:Hide() row.icons[3]:Hide()
            panel.extraRows[slot] = row
        end
        row:Show()
        row:SetBackdropColor(unpack(COLORS.bgCard))
        row:SetAlpha(1)
        return row
    end

    -- Fills the rows after the ranks and sizes the scroll area to them.
    function panel:UpdateExtras()
        local Rank, L = HonorLog.Rank, HonorLog.L
        for _, row in ipairs(self.extraRows) do row:Hide() end
        self.extraHeader:Hide()
        local slot = 0
        for _, entry in ipairs(Rank:GetZeroPointBattlegrounds()) do
            slot = slot + 1
            local row = extraRow(slot)
            row.name:SetText(entry.name)
            row.name:SetTextColor(unpack(COLORS.accent))
            row.tag:SetText(entry.otherAverage and string.format(L["others average %d"], math.floor(entry.otherAverage + 0.5)) or "")
            row.tag:SetTextColor(unpack(COLORS.rankCap))
            row.detail:SetText(string.format(L["Gave 0 rank points in %d of %d games."], entry.zero, entry.games))
            row:SetBackdropBorderColor(unpack(COLORS.rankCap))
        end
        local results = Rank:GetPointsPerResult()
        if #results > 0 then
            slot = slot + 1
            local y = -(HonorLog.Rank.MAX_RANK + slot - 1) * (Layout.RANK_ROW_HEIGHT + 2) - 8
            self.extraHeader:ClearAllPoints()
            self.extraHeader:SetPoint("TOPLEFT", content, "TOPLEFT", PADDING + 2, y)
            self.extraHeader:SetText(L["Points per result (measured games)"])
            self.extraHeader:Show()
            for _, r in ipairs(results) do
                slot = slot + 1
                local row = extraRow(slot)
                row.name:SetText(r.name)
                row.name:SetTextColor(unpack(COLORS.accent))
                row.tag:SetText(string.format(L["%d games"], r.games))
                row.tag:SetTextColor(unpack(COLORS.textSecondary))
                row.detail:SetText(string.format(L["per win %s, per loss %s"],
                    r.perWin and tostring(math.floor(r.perWin + 0.5)) or "-",
                    r.perLoss and tostring(math.floor(r.perLoss + 0.5)) or "-"))
                row:SetBackdropBorderColor(unpack(COLORS.borderDark))
            end
        end
        content:SetHeight((HonorLog.Rank.MAX_RANK + slot) * (Layout.RANK_ROW_HEIGHT + 2))
    end

    function panel:Update(info)
        local L = self.lines
        for _, row in ipairs(self.rows) do row:SetShown(info ~= nil) end
        if not info then
            L[1]:SetText("No PvP rank data from the client yet.")
            for i = 2, 4 do L[i]:SetText("") end
            for _, row in ipairs(self.extraRows) do row:Hide() end
            self.extraHeader:Hide()
            return
        end
        local Rank = HonorLog.Rank
        local pace = Rank:GetPace()
        L[1]:SetText(info.rank > 0 and string.format("Rank %d  %s", info.rank, info.title) or info.title)
        local progress = info.threshold > 0 and string.format("%s / %s (%d%%) \194\183 %s pts total", commas(info.points),
            commas(info.threshold), math.floor(info.percent), commas(info.totalPoints)) or (commas(info.totalPoints) .. " pts total")
        local cap
        if info.weekCapRank <= 0 then
            cap = "No weekly cap reported"
        elseif info.capped then
            cap = string.format("Week %d cap: Rank %d reached. Next cap in %s", info.weekNumber, info.weekCapRank,
                Rank.FormatSpan(info.secondsToWeeklyReset))
        else
            cap = string.format("Week %d cap: Rank %d, %s pts left. Next cap in %s", info.weekNumber, info.weekCapRank,
                commas(info.pointsLeftThisWeek or 0), Rank.FormatSpan(info.secondsToWeeklyReset))
        end
        L[2]:SetText(progress)
        L[3]:SetText(cap .. (info.secondsToSeasonEnd > 0 and (" \194\183 season ends in " .. Rank.FormatSpan(info.secondsToSeasonEnd)) or ""))
        if info.gate and info.gate.blocking then
            L[4]:SetText(Rank:GateText(info.gate))
            L[4]:SetTextColor(unpack(COLORS.rankCap))
        elseif pace.noPoints then
            L[4]:SetText(HonorLog.L["Your measured games give no rank points, so there is no pace to plan with."])
            L[4]:SetTextColor(unpack(COLORS.rankCap))
        else
            L[4]:SetText(string.format("Pace: %d/win, %d/loss, %d%% wins, %.1f games/day%s", math.floor(pace.pointsPerWin + 0.5),
                math.floor(pace.pointsPerLoss + 0.5), math.floor(pace.winRate * 100 + 0.5), pace.gamesPerDay,
                pace.estimated and " (estimate)" or ""))
            L[4]:SetTextColor(unpack(COLORS.textSecondary))
        end

        for n, row in ipairs(self.rows) do
            local plan = Rank:PlanToRank(n, info, pace)
            local color = HonorLog.RANK_TAG_COLORS[plan.limitedBy] or COLORS.textSecondary
            row.name:SetText(string.format("R%d %s", n, Rank:TitleForRank(n)))
            row.name:SetTextColor(unpack(plan.reached and COLORS.textTertiary or COLORS.accent))
            row.tag:SetText(Rank.TAG_TEXT[plan.limitedBy] or "")
            row.tag:SetTextColor(unpack(color))
            local total = commas(Rank:TotalForRank(n)) .. " total"
            if plan.reached then
                row.detail:SetText(total .. " \194\183 reached")
            else
                local games = Rank.PlanGames(plan)
                row.detail:SetText(string.format("%s \194\183 %s to go \194\183 %s%s", total,
                    commas(plan.pointsNeeded), games and (games .. " \194\183 ") or "", Rank.PlanWhen(plan) or "no date"))
            end
            -- The current rank and this week's cap stand out.
            local isCurrent, isCap = n == info.rank, info.weekCapRank > 0 and n == info.weekCapRank
            row:SetBackdropColor(unpack(isCurrent and COLORS.rankCurrentBg or COLORS.bgCard))
            row:SetBackdropBorderColor(unpack(isCurrent and COLORS.brand or (isCap and COLORS.rankCap or COLORS.borderDark)))
            row:SetAlpha(plan.reached and not isCurrent and 0.65 or 1)
            local rewards = Rank:GetRewards(n)
            for i, btn in ipairs(row.icons) do
                local r = rewards[i]
                rewardOf[btn] = r
                if r then
                    btn.tex:SetTexture(r.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    btn:Show()
                else
                    btn:Hide()
                end
            end
        end
        self:UpdateExtras()
    end

    panel:Hide()
    return panel
end

-- Rank bar and Rank tab, built after the Goals UI so the tabs line up.
function HonorLog:InitializeRankUI()
    local frame = self.mainFrame
    if not frame then return end

    ui.bar = CreateRankBar(frame)
    ui.panel = CreateRankPanel(frame)
    ui.tab = CreateRankTabButton(frame.header, "Rank")
    ui.tab:SetPoint("RIGHT", frame.expandBtn, "LEFT", -4, 0)
    ui.tab:SetActive(false)
    ui.tab:Hide()
    ui.tab:SetScript("OnClick", function() HonorLog:SwitchTab("rank") end)

    -- GoalsPanel.lua owns SwitchTab for Stats and Goals; Rank handles itself and hands the rest on.
    local goalsSwitch = self.SwitchTab
    self.SwitchTab = function(addon, tabName)
        local f = addon.mainFrame
        if not f then return end
        if tabName ~= "rank" then
            ui.panel:Hide()
            ui.tab:SetActive(false)
            if goalsSwitch then goalsSwitch(addon, tabName) end
            return
        end
        if not ui.tab:IsShown() then return end -- no rank data: no Rank view
        f.currentView = "rank"
        if f.statsTab then f.statsTab:SetActive(false) end
        if f.goalsTab then f.goalsTab:SetActive(false) end
        ui.tab:SetActive(true)
        addon:UpdateCompactView()
        f.statsView:Hide()
        if f.goalsPanel then f.goalsPanel:Hide() end
        if addon.db.settings.frameExpanded then
            ui.panel:Show()
            addon:UpdateRankUI(addon.Rank and addon.Rank:GetInfo())
        else
            ui.panel:Hide()
        end
    end

    -- Keep the Rank tab current whenever data changes (a recorded game moves the pace).
    local previous = self.OnDataUpdated
    self.OnDataUpdated = function(addon, ...)
        if previous then previous(addon, ...) end
        addon:RefreshRank()
    end

    self:UpdateRankUI(self.Rank and self.Rank:GetInfo())
end

-- info is nil when the client has no rank data: the bar and the tab hide.
function HonorLog:UpdateRankUI(info)
    local frame = self.mainFrame
    if not (frame and ui.bar and ui.tab) then return end
    local showBar = info ~= nil and self.db.settings.showRankBar ~= false
    UpdateRankBar(frame, info, showBar)

    local hasTab = info ~= nil
    if ui.tab:IsShown() ~= hasTab then
        ui.tab:SetShown(hasTab)
        -- The Goals tab sits beside the Rank tab when there is one.
        if frame.goalsTab then
            frame.goalsTab:ClearAllPoints()
            frame.goalsTab:SetPoint("RIGHT", hasTab and ui.tab or frame.expandBtn, "LEFT", hasTab and -2 or -4, 0)
        end
    end
    if not hasTab and frame.currentView == "rank" then
        self:SwitchTab("stats")
        return
    end
    if frame.currentView == "rank" and ui.panel:IsShown() then
        ui.panel:Update(info)
    end
end
