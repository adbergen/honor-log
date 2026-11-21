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
    accentGlow = { 0.25, 0.25, 0.30, 0.15 },   -- Neutral (was blue)

    -- Borders
    borderDark = { 0.06, 0.06, 0.08, 1 },
    borderLight = { 0.30, 0.30, 0.38, 0.8 },
    borderGlow = { 0.20, 0.22, 0.25, 0.4 },     -- Subtle dark glow (was blue)
    borderAccent = { 0.30, 0.32, 0.35, 0.8 },   -- Neutral accent (was blue)

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
    accent = { 0.85, 0.75, 0.45, 1 },          -- Warm gold for labels (was blue)
    accentDim = { 0.25, 0.27, 0.30, 0.9 },     -- Dark neutral for borders (was blue)
    brand = { 0.25, 0.85, 0.45, 1 },
    brandDim = { 0.18, 0.60, 0.32, 0.8 },

    -- Separators
    separator = { 0.25, 0.25, 0.32, 0.6 },
    separatorGlow = { 0.30, 0.30, 0.35, 0.3 },  -- Neutral (was blue)

    -- Progress colors (for goal tracking)
    progressFull = { 0.30, 0.90, 0.40, 1 },
    progressPartial = { 1.0, 0.85, 0.25, 1 },
    progressLow = { 0.95, 0.35, 0.35, 1 },

    -- Currency colors
    honor = { 1.0, 0.85, 0.25, 1 },
    marks = { 0.35, 0.78, 1.0, 1 },

    -- Rank climb
    rankFill = { 0.85, 0.70, 0.30, 1 },
    rankCap = { 1.0, 0.55, 0.20, 1 },
    rankCurrentBg = { 0.20, 0.18, 0.10, 0.95 },
}

-- Colour of the "limited by" tag in the Rank tab.
HonorLog.RANK_TAG_COLORS = {
    cap = { 1.0, 0.55, 0.20, 1 },
    pace = { 0.35, 0.78, 1.0, 1 },
    season = { 0.95, 0.35, 0.35, 1 },
    reached = { 0.30, 0.90, 0.40, 1 },
    level = { 0.78, 0.63, 1.0, 1 },
    nopoints = { 0.62, 0.65, 0.70, 1 },
}

-- Rank icons: the atlas Blizzard's own rank window uses, then the classic badge file, then a neutral icon.
HonorLog.RANK_ICON_ATLAS = "UI-Character-Info-Honor-Icon-%d"
HonorLog.RANK_ICON_FILE = "Interface\\PvPRankBadges\\PvPRank%02d"
HonorLog.RANK_ICON_FALLBACK = "Interface\\Icons\\Spell_Holy_ChampionsBond"

--------------------------------------------------------------------------------
-- BG-SPECIFIC COLORS
--------------------------------------------------------------------------------

-- Primary BG colors (for cards, icons, highlights). The single source: BG_COLOR_HEX is derived from it.
local function hexColor(hex)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1 }
end
HonorLog.BG_COLORS = {
    AV = { 0.45, 0.75, 1.0, 1 },   -- Ice blue
    AB = hexColor("e65959"),       -- Red
    WSG = hexColor("59d973"),      -- Green
    DI = hexColor("59d9a6"),       -- Island teal
}

-- Glow/subtle BG colors (for backgrounds, subtle indicators)
HonorLog.BG_GLOW_COLORS = {
    AV = { 0.35, 0.65, 0.90, 0.3 },
    AB = { 0.90, 0.68, 0.18, 0.3 },
    WSG = { 0.90, 0.28, 0.28, 0.3 },
    DI = { 0.25, 0.75, 0.55, 0.3 },
}

-- Hex codes for inline text coloring, derived from BG_COLORS
HonorLog.BG_COLOR_HEX = {}
for bgType, c in pairs(HonorLog.BG_COLORS) do
    HonorLog.BG_COLOR_HEX[bgType] = string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5),
        math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- Mark of Honor icons, one per battleground mark item
HonorLog.BG_ICONS = {
    AV = "Interface\\Icons\\INV_Jewelry_Necklace_21",   -- Alterac Valley Mark
    AB = "Interface\\Icons\\INV_Jewelry_Amulet_07",     -- Arathi Basin Mark
    WSG = "Interface\\Icons\\INV_Misc_Rune_07",         -- Warsong Gulch Mark
    DI = 237427,                                        -- Darkspear Islands Mark (item 274895): its own icon file id from the 1.60.1 client data
}

-- A battleground the registry does not know yet (generic "MAP<id>" entry) still needs colours.
local FALLBACK_COLOR = { 0.70, 0.70, 0.78, 1 }
local FALLBACK_GLOW = { 0.60, 0.60, 0.68, 0.3 }
function HonorLog:GetBGColor(bgType) return HonorLog.BG_COLORS[bgType] or FALLBACK_COLOR end
function HonorLog:GetBGGlow(bgType) return HonorLog.BG_GLOW_COLORS[bgType] or FALLBACK_GLOW end

-- Currency icons (honor, by faction)
HonorLog.CURRENCY_ICONS = {
    honor = {
        Alliance = "Interface\\Icons\\Spell_Holy_ChampionsBond",  -- Gold medallion
        Horde = "Interface\\Icons\\Spell_Holy_ChampionsBond",     -- Gold medallion
    },
}

--------------------------------------------------------------------------------
-- BATTLEGROUND ORDER
--------------------------------------------------------------------------------
-- Active BGs for UI display.
HonorLog.BG_ORDER = { "AV", "WSG", "AB", "DI" }

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
    GOAL_CARD_HEIGHT = 62,
    GOAL_CARD_SPACING = 4,
    ITEM_ROW_HEIGHT = 56,
    TAB_WIDTH = 38,
    TAB_HEIGHT = 16,

    -- Rank bar (under the header) and Rank tab rows
    RANK_BAR_HEIGHT = 16,
    RANK_BAR_GAP = 3,
    RANK_ROW_HEIGHT = 30,
    RANK_SUMMARY_HEIGHT = 66,

    -- Icon sizes
    ICON_SMALL = 16,
    ICON_MEDIUM = 24,
    ICON_LARGE = 40,

    -- Button sizes
    BUTTON_SMALL = 14,
    BUTTON_MEDIUM = 24,
}
