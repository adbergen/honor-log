-- HonorLog Theme
-- Shared color system and layout constants
-- Inspired by Details!, WeakAuras, and ElvUI

local ADDON_NAME, HonorLog = ...

--------------------------------------------------------------------------------
-- ENTERPRISE COLOR SYSTEM
--------------------------------------------------------------------------------
HonorLog.Theme = {
    -- Background layers (dark theme with depth)
    bgPrimary = { 0.08, 0.08, 0.10, 0.98 },
    bgSecondary = { 0.10, 0.10, 0.13, 0.95 },
    bgTertiary = { 0.14, 0.14, 0.18, 0.90 },
    bgCard = { 0.12, 0.12, 0.16, 0.95 },
    bgCardHover = { 0.16, 0.16, 0.22, 1 },

    -- Accent gradients
    headerGradientTop = { 0.18, 0.18, 0.24, 1 },
    headerGradientBot = { 0.10, 0.10, 0.14, 1 },
    accentGlow = { 0.30, 0.70, 0.95, 0.15 },

    -- Borders
    borderDark = { 0.06, 0.06, 0.08, 1 },
    borderLight = { 0.30, 0.30, 0.38, 0.8 },
    borderGlow = { 0.40, 0.75, 1.0, 0.25 },
    borderAccent = { 0.35, 0.65, 0.90, 0.6 },

    -- Status colors
    win = { 0.30, 0.90, 0.40, 1 },
    winGlow = { 0.20, 0.80, 0.30, 0.4 },
    winDark = { 0.15, 0.50, 0.20, 0.8 },
    loss = { 0.95, 0.35, 0.35, 1 },
    lossGlow = { 0.85, 0.25, 0.25, 0.4 },
    lossDark = { 0.50, 0.18, 0.18, 0.8 },
    neutral = { 1.0, 0.85, 0.25, 1 },
    neutralDim = { 0.80, 0.68, 0.20, 0.7 },

    -- Text hierarchy
    textPrimary = { 0.98, 0.98, 1.0, 1 },
    textSecondary = { 0.75, 0.75, 0.80, 1 },
    textTertiary = { 0.50, 0.50, 0.58, 1 },
    textMuted = { 0.38, 0.38, 0.45, 1 },

    -- Brand accent
    accent = { 0.35, 0.78, 1.0, 1 },
    accentDim = { 0.25, 0.55, 0.75, 0.8 },
    brand = { 0.25, 0.85, 0.45, 1 },
    brandDim = { 0.18, 0.60, 0.32, 0.8 },

    -- Separators
    separator = { 0.25, 0.25, 0.32, 0.6 },
    separatorGlow = { 0.35, 0.65, 0.90, 0.2 },

    -- Progress colors (for goal tracking)
    progressFull = { 0.30, 0.90, 0.40, 1 },
    progressPartial = { 1.0, 0.85, 0.25, 1 },
    progressLow = { 0.95, 0.35, 0.35, 1 },

    -- Currency colors
    honor = { 1.0, 0.85, 0.25, 1 },
    arena = { 0.70, 0.30, 0.90, 1 },
    marks = { 0.35, 0.78, 1.0, 1 },
}

--------------------------------------------------------------------------------
-- BG-SPECIFIC COLORS
--------------------------------------------------------------------------------

-- Primary BG colors (for cards, icons, highlights)
HonorLog.BG_COLORS = {
    AV = { 0.45, 0.75, 1.0, 1 },   -- Ice blue
    AB = { 1.0, 0.78, 0.28, 1 },   -- Rich gold
    WSG = { 1.0, 0.38, 0.38, 1 },  -- Vibrant red
    EotS = { 0.75, 0.45, 1.0, 1 }, -- Deep purple
}

-- Glow/subtle BG colors (for backgrounds, subtle indicators)
HonorLog.BG_GLOW_COLORS = {
    AV = { 0.35, 0.65, 0.90, 0.3 },
    AB = { 0.90, 0.68, 0.18, 0.3 },
    WSG = { 0.90, 0.28, 0.28, 0.3 },
    EotS = { 0.65, 0.35, 0.90, 0.3 },
}

-- Hex codes for inline text coloring
HonorLog.BG_COLOR_HEX = {
    AV = "73b3f2",   -- Icy blue
    AB = "e65959",   -- Red (adjusted to match goals panel usage)
    WSG = "59d973",  -- Green
    EotS = "cc80f2", -- Purple
}

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS
--------------------------------------------------------------------------------
HonorLog.Layout = {
    -- Frame dimensions
    FRAME_WIDTH = 290,
    FRAME_HEIGHT_COMPACT = 60,
    FRAME_HEIGHT_EXPANDED = 262,

    -- Spacing
    PADDING = 8,
    INNER_PADDING = 6,
    CARD_SPACING = 2,

    -- Component sizes
    HEADER_HEIGHT = 28,
    CARD_HEIGHT = 36,
    GOAL_CARD_HEIGHT = 70,
    GOAL_CARD_SPACING = 4,
    ITEM_ROW_HEIGHT = 56,
    TAB_WIDTH = 38,
    TAB_HEIGHT = 16,

    -- Icon sizes
    ICON_SMALL = 16,
    ICON_MEDIUM = 24,
    ICON_LARGE = 40,

    -- Button sizes
    BUTTON_SMALL = 14,
    BUTTON_MEDIUM = 24,
}
