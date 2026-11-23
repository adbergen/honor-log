-- HonorLog Kit
-- The pieces the full window is built from: a window frame, insets, headers, buttons, tabs, bars, the rank
-- ring, tiles, a pooled list, item and mark icons, a line chart and a map link.
--
-- Every piece tries Blizzard's own template or atlas first and falls back to plain drawing, because most of
-- those names could not be checked against the client's source before the first in-game look. A wrong name
-- must cost looks, never an error: templates are tried under pcall, atlases are checked with
-- C_Texture.GetAtlasInfo first, and methods that only a template frame has are called only when they exist.
--
-- Loaded after Theme and before Window. Nothing here creates a frame until a function is called.

local _, HonorLog = ...
HonorLog = HonorLog or {}

local Util = HonorLog.Util
local num, call = Util.num, Util.call
local L = HonorLog.L

local Kit = {}
HonorLog.Kit = Kit

--------------------------------------------------------------------------------
-- Colours and fonts
--------------------------------------------------------------------------------

Kit.COLORS = {
    white = { 1, 1, 1 },
    gold = { 1, 0.82, 0 },
    grey = { 0.66, 0.64, 0.59 },
    green = { 0.25, 0.88, 0.38 },
    red = { 1, 0.35, 0.28 },
    orange = { 1, 0.6, 0.24 },
    line = { 0.43, 0.42, 0.38 },
}

-- Colour escape for inline text ("|cffffd100...|r").
function Kit:Hex(name)
    local c = self.COLORS[name] or self.COLORS.white
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- Blizzard font objects by style, first one the client has wins.
Kit.FONTS = {
    label = { "GameFontNormal" },
    labelSmall = { "GameFontNormalSmall", "GameFontNormal" },
    value = { "GameFontHighlight" },
    grey = { "GameFontDisableSmall", "GameFontNormalSmall" },
    title = { "GameFontHighlightLarge" },
    big = { "GameFontHighlightHuge", "GameFontNormalHuge", "GameFontHighlightLarge" },
}
local FONT_FILE_SIZE = { label = 13, labelSmall = 11, value = 13, grey = 11, title = 16, big = 22 }
local STYLE_COLOR = { label = "gold", labelSmall = "gold", value = "white", grey = "grey", title = "white", big = "white" }

local function fontFor(style)
    for _, name in ipairs(Kit.FONTS[style] or Kit.FONTS.value) do
        if _G[name] ~= nil then return _G[name], name end
    end
end

-- A FontString in one of the styles label, labelSmall, value, grey, title, big.
function Kit:Text(parent, style, layer)
    style = Kit.FONTS[style] and style or "value"
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    local font, fontName = fontFor(style)
    if font then
        fs:SetFontObject(font)
    else
        -- No font object at all: a font file keeps SetText from raising "Font not set".
        fs:SetFont("Fonts\\FRIZQT__.TTF", FONT_FILE_SIZE[style] or 12, "")
        local c = Kit.COLORS[STYLE_COLOR[style]]
        fs:SetTextColor(c[1], c[2], c[3])
    end
    fs:SetJustifyH("LEFT")
    fs.honorLogStyle, fs.honorLogFont = style, fontName or false
    return fs
end

--------------------------------------------------------------------------------
-- Templates and atlases
--------------------------------------------------------------------------------

-- A client that only logs a missing template still hands back a frame, with none of the template in it.
-- A frame that came out of a template with no region and no child did not get one.
local function hollow(frame)
    local regions = frame.GetNumRegions and num(frame:GetNumRegions())
    local children = frame.GetNumChildren and num(frame:GetNumChildren())
    return regions == 0 and children == 0
end

local function tryTemplate(frameType, name, parent, template)
    local ok, frame = pcall(CreateFrame, frameType, name, parent, template)
    if not (ok and type(frame) == "table") then return nil end
    if template and hollow(frame) then
        frame:Hide()
        return nil
    end
    return frame
end

-- One template, or nil when the client rejects it.
function Kit:TryTemplate(frameType, name, parent, template)
    return tryTemplate(frameType, name, parent, template)
end

-- The template-safe constructor: tries each template in order; when none works builds a plain frame.
-- Returns the frame and the template that took (nil for the plain one).
function Kit:CreateTemplated(frameType, name, parent, ...)
    for i = 1, select("#", ...) do
        local template = select(i, ...)
        if template then
            local frame = tryTemplate(frameType, name, parent, template)
            if frame then return frame, template end
        end
    end
    return CreateFrame(frameType, name, parent), nil
end

-- Asked two ways, because the first in-game look showed an atlas Blizzard's own PvP tab uses reported as
-- missing: C_Texture.GetAtlasInfo, then setting it on a scratch texture and reading it back.
local scratchTexture
function Kit:HasAtlas(name)
    if type(name) ~= "string" then return false end
    if C_Texture and C_Texture.GetAtlasInfo then
        local ok, info = pcall(C_Texture.GetAtlasInfo, name)
        if ok and info ~= nil then return true end
    end
    if not scratchTexture then
        local holder = CreateFrame("Frame")
        holder:Hide()
        scratchTexture = holder:CreateTexture()
    end
    if type(scratchTexture.GetAtlas) ~= "function" then return false end
    local ok, got = pcall(function()
        scratchTexture:SetAtlas(name)
        return scratchTexture:GetAtlas()
    end)
    return ok and got == name
end

-- The atlas when the client has it, else a plain colour. Returns true when the atlas took.
function Kit:SetAtlasOr(texture, atlas, r, g, b, a)
    if self:HasAtlas(atlas) and pcall(texture.SetAtlas, texture, atlas) then
        texture:SetVertexColor(1, 1, 1, 1)
        return true
    end
    texture:SetColorTexture(r or 0.1, g or 0.1, b or 0.1, a or 1)
    return false
end

-- Four 1-pixel edges around a frame.
function Kit:Edges(frame, r, g, b, a)
    local edges = {}
    local function edge(p1, p2, w, h)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(r, g, b, a or 1)
        t:SetPoint(p1, frame, p1, 0, 0)
        t:SetPoint(p2, frame, p2, 0, 0)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        edges[#edges + 1] = t
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
    frame.honorLogEdges = edges
    return edges
end

local function fill(frame, r, g, b, a, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints(frame)
    t:SetColorTexture(r, g, b, a)
    return t
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- The window's round portrait hangs over the top left corner of every screen: about 44 pixels across and
-- 22 down, measured from a screen's own corner. Anything a screen puts in that corner starts this far right.
Kit.PORTRAIT_CLEAR = 36

-- Everything this file adds to a frame that came from a Blizzard template is named honorLog...: a
-- template frame carries Blizzard's own methods and fields (a PortraitFrame has GetTitleText, CloseButton,
-- ...), and a second thing under one of those names breaks Blizzard's code, not ours.
--
-- The outer frame. Whichever way it is drawn it offers honorLogSetTitle, honorLogSetPortrait, honorLogContent (a frame
-- inset from the chrome) and CloseButton. honorLogChrome names what drew it: "PortraitFrameTemplate",
-- "PortraitFrameBaseTemplate" or nil for the plain drawing.
function Kit:Window(name, width, height)
    local frame = tryTemplate("Frame", name, UIParent, "PortraitFrameTemplate")
    local chrome = frame and "PortraitFrameTemplate" or nil
    local closeButton
    if frame then
        if type(frame.CloseButton) == "table" then closeButton = frame.CloseButton end
    else
        frame = tryTemplate("Frame", name, UIParent, "PortraitFrameBaseTemplate")
        chrome = frame and "PortraitFrameBaseTemplate" or nil
    end
    if not frame then frame = CreateFrame("Frame", name, UIParent) end
    frame.honorLogChrome = chrome or false
    frame:SetSize(width, height)
    -- The layer Blizzard's own panels use, raised by a click like them. In a higher layer the window covered
    -- everything the game opens beside it (seen in game: the dressing room came up behind it).
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()

    local titleText, portrait
    if not chrome then
        fill(frame, 0.06, 0.055, 0.05, 0.97)
        Kit:Edges(frame, 0.45, 0.42, 0.38, 1)
        local strip = frame:CreateTexture(nil, "BORDER")
        strip:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        strip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
        strip:SetHeight(22)
        strip:SetColorTexture(0.16, 0.12, 0.11, 1)
        titleText = Kit:Text(frame, "label")
        titleText:SetPoint("TOP", frame, "TOP", 0, -5)
        -- A round portrait on a gold ring.
        local ring = frame:CreateTexture(nil, "ARTWORK", nil, 1)
        ring:SetSize(60, 60)
        ring:SetPoint("TOPLEFT", frame, "TOPLEFT", -8, 10)
        ring:SetColorTexture(0.85, 0.66, 0.23, 1)
        portrait = frame:CreateTexture(nil, "ARTWORK", nil, 2)
        portrait:SetSize(54, 54)
        portrait:SetPoint("CENTER", ring, "CENTER", 0, 0)
        for _, tex in ipairs({ ring, portrait }) do
            local mask = frame:CreateMaskTexture()
            mask:SetAllPoints(tex)
            pcall(mask.SetTexture, mask, PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            pcall(tex.AddMaskTexture, tex, mask)
        end
    end

    if not closeButton then
        local template
        closeButton, template = Kit:CreateTemplated("Button", nil, frame, "UIPanelCloseButtonDefaultAnchors", "UIPanelCloseButton")
        if template == "UIPanelCloseButton" then
            closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        elseif not template then
            closeButton:SetSize(22, 22)
            closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -1)
            fill(closeButton, 0.16, 0.06, 0.05, 1)
            Kit:Edges(closeButton, 0.45, 0.42, 0.38, 1)
            local hl = closeButton:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(closeButton)
            hl:SetColorTexture(1, 1, 1, 0.12)
            local x = Kit:Text(closeButton, "label")
            x:SetPoint("CENTER", 0, 0)
            x:SetText("X")
        end
        closeButton:SetScript("OnClick", function() frame:Hide() end)
    end
    frame.honorLogClose = closeButton

    -- The template's own title when it takes it; else a text of our own on the drag strip.
    function frame:honorLogSetTitle(text)
        self.honorLogTitle = text
        if chrome and type(self.SetTitle) == "function" and pcall(self.SetTitle, self, text) then return end
        if not titleText then
            titleText = Kit:Text(self.honorLogDrag or self, "label")
            titleText:SetPoint("TOP", self, "TOP", 0, -5)
        end
        titleText:SetText(text)
    end
    function frame:honorLogGetTitle() return self.honorLogTitle end

    function frame:honorLogSetPortrait(texture)
        self.honorLogPortrait = texture
        if chrome and type(self.SetPortraitToAsset) == "function" and pcall(self.SetPortraitToAsset, self, texture) then return end
        if portrait then portrait:SetTexture(texture) end
    end

    -- The title area drags the window; the close button stays clear of it. It sits above the template's
    -- own title bar art (Blizzard's border and title pieces are child frames with high levels), so text
    -- parented to it (frame.honorLogDrag) is not hidden behind that art.
    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -26, 0)
    drag:SetHeight(24)
    drag:SetFrameLevel(frame:GetFrameLevel() + 600)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if frame.honorLogOnMoved then frame.honorLogOnMoved(frame) end
    end)
    frame.honorLogDrag = drag

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -24)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    -- Its own dark ground: PortraitFrameBaseTemplate draws no background (the Character window adds its
    -- own), and the screens only paint their panes and boxes.
    content.honorLogBg = fill(content, 0.07, 0.065, 0.06, 1)
    frame.honorLogContent = content
    return frame
end

--------------------------------------------------------------------------------
-- Insets, headers, buttons
--------------------------------------------------------------------------------

-- A dark box.
function Kit:Inset(parent)
    local frame, template = Kit:CreateTemplated("Frame", nil, parent, "InsetFrameTemplate")
    if not template then
        fill(frame, 0.06, 0.055, 0.05, 0.9)
        Kit:Edges(frame, 0.24, 0.23, 0.22, 1)
    end
    frame.honorLogTemplate = template or false
    return frame
end

-- A gold label with a thin line running to the right edge.
function Kit:Header(parent, text)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(18)
    header.Label = Kit:Text(header, "label")
    header.Label:SetPoint("LEFT", header, "LEFT", 0, 0)
    header.Line = header:CreateTexture(nil, "ARTWORK")
    header.Line:SetColorTexture(Kit.COLORS.line[1], Kit.COLORS.line[2], Kit.COLORS.line[3], 0.8)
    header.Line:SetHeight(1)
    header.Line:SetPoint("LEFT", header.Label, "RIGHT", 8, 0)
    header.Line:SetPoint("RIGHT", header, "RIGHT", 0, 0)
    function header:SetText(t) self.Label:SetText(t) end
    header:SetText(text or "")
    return header
end

-- style "red" (the main action) or "small".
function Kit:Button(parent, text, style)
    local templates = style == "small" and { "SharedButtonSmallTemplate", "UIPanelButtonTemplate" } or { "UIPanelButtonTemplate" }
    local button, template = Kit:CreateTemplated("Button", nil, parent, unpack(templates))
    button.honorLogTemplate = template or false
    if not template then
        if style == "small" then fill(button, 0.17, 0.16, 0.15, 1) else fill(button, 0.36, 0.06, 0.05, 1) end
        Kit:Edges(button, 0.43, 0.42, 0.38, 1)
        local hl = button:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(button)
        hl:SetColorTexture(1, 1, 1, 0.1)
        local fs = Kit:Text(button, style == "small" and "labelSmall" or "label")
        fs:SetPoint("CENTER", 0, 0)
        button:SetFontString(fs)
        button:SetSize(style == "small" and 70 or 110, style == "small" and 20 or 24)
    elseif style ~= "small" then
        button:SetSize(110, 24)
    end
    button:SetText(text or "")
    return button
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

-- Labelled tabs hanging under the window's bottom-left corner. tabs:Add(key, text), tabs:Select(key) (which
-- calls onSelect(key)), tabs:GetSelected(). The selected tab is taller as well as lighter, so it is not
-- colour alone.
function Kit:Tabs(window, onSelect)
    local tabs = { list = {}, buttons = {}, selected = nil }

    local function paint(button, selected)
        button.honorLogSelected = selected
        if button.honorLogTemplate then
            local api = selected and PanelTemplates_SelectTab or PanelTemplates_DeselectTab
            if api then
                pcall(api, button)
            else
                pcall(selected and button.LockHighlight or button.UnlockHighlight, button)
            end
        else
            button:SetHeight(selected and 30 or 26)
            if selected then
                button.honorLogBg:SetColorTexture(0.08, 0.07, 0.06, 1)
                button.honorLogLabel:SetTextColor(1, 1, 1)
            else
                button.honorLogBg:SetColorTexture(0.16, 0.06, 0.05, 1)
                button.honorLogLabel:SetTextColor(Kit.COLORS.gold[1], Kit.COLORS.gold[2], Kit.COLORS.gold[3])
            end
        end
    end

    function tabs:Add(key, text)
        local button, template = Kit:CreateTemplated("Button", nil, window, "PanelTabButtonTemplate")
        button.honorLogTemplate, button.honorLogKey = template or false, key
        local previous = self.list[#self.list]
        if previous then
            -- 1 px apart, as Blizzard's own tabs are: at 3 px whatever sits behind the row showed between them
            button:SetPoint("TOPLEFT", previous, "TOPRIGHT", template and 1 or 3, 0)
        else
            button:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 12, 2)
        end
        if template then
            button:SetText(text)
            if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, button, 0) end
        else
            button.honorLogBg = fill(button, 0.16, 0.06, 0.05, 1)
            Kit:Edges(button, 0.43, 0.42, 0.38, 1)
            button.honorLogLabel = Kit:Text(button, "label")
            button.honorLogLabel:SetPoint("CENTER", 0, -1)
            button.honorLogLabel:SetText(text)
            button:SetSize(math.max(60, (button.honorLogLabel:GetStringWidth() or 40) + 32), 26)
        end
        button:SetScript("OnClick", function() tabs:Select(key) end)
        self.list[#self.list + 1] = button
        self.buttons[key] = button
        paint(button, false)
        return button
    end

    function tabs:Select(key)
        if not self.buttons[key] then return false end
        for k, button in pairs(self.buttons) do paint(button, k == key) end
        self.selected = key
        if onSelect then onSelect(key) end
        return true
    end

    function tabs:GetSelected() return self.selected end
    return tabs
end

--------------------------------------------------------------------------------
-- Bar
--------------------------------------------------------------------------------

local function clamp01(f)
    f = tonumber(f) or 0
    if f ~= f then f = 0 end
    return math.max(0, math.min(1, f))
end
Kit.Clamp01 = clamp01

-- A status bar on a dark track with a border. SetValue01(fraction), SetBarColor(r, g, b).
function Kit:Bar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(14)
    fill(bar, 0.035, 0.03, 0.03, 1)
    Kit:Edges(bar, 0.4, 0.33, 0.12, 1)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    function bar:SetValue01(fraction)
        self.honorLogFraction = clamp01(fraction)
        self:SetValue(self.honorLogFraction)
    end
    function bar:SetBarColor(r, g, b)
        self.honorLogColor = { r, g, b }
        self:SetStatusBarColor(r, g, b)
    end
    bar:SetBarColor(1, 0.82, 0.1)
    return bar
end

--------------------------------------------------------------------------------
-- Rank ring
--------------------------------------------------------------------------------

-- A dark round ground behind a ring-shaped badge, so the art under the badge does not show through its
-- middle. Round, because a square one shows its corners past the ring. Without mask textures it is a
-- smaller square whose corners stay under the ring.
function Kit:RoundGround(frame, r, g, b)
    local ground = frame:CreateTexture(nil, "BACKGROUND")
    ground:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    ground:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    ground:SetColorTexture(r or 0.1, g or 0.1, b or 0.1, 1)
    local masked = type(frame.CreateMaskTexture) == "function" and pcall(function()
        local mask = frame:CreateMaskTexture()
        mask:SetAllPoints(ground)
        mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        ground:AddMaskTexture(mask)
    end)
    if not masked then
        local side = (num(frame:GetWidth()) or 18) * 0.6
        ground:ClearAllPoints()
        ground:SetPoint("CENTER", frame, "CENTER", 0, 0)
        ground:SetSize(side, side)
    end
    ground.honorLogRound = masked and true or false
    return ground
end

local RING = {
    glow = "UI-Character-Info-Honor-Bar-BG-Glow",
    horde = "UI-Character-Info-Honor-Bar-BG-Horde",
    alliance = "UI-Character-Info-Honor-Bar-BG-Alliance",
    -- The ring art. Build 1.60.1.71037 has only the second name (asked in game with /honorlog probe ui);
    -- the first is what the published PVPRankFrame.lua sets.
    bar = "UI-Character-Info-Honor-Bar",
    barOld = "pvpqueue-sidebar-honorbar-background",
    badge = "UI-Character-Info-Honor-RewardRing",
    iconHorde = "UI-Character-Info-Honor-Icon-Horde",
    iconAlliance = "UI-Character-Info-Honor-Icon-Alliance",
}
local SWIPE = "Interface\\PVPFrame\\pvpqueue-sidebar-honorbar-fill"
Kit.RING_ATLASES = RING

-- The rank badge: Blizzard's atlas, then the classic badge file, then a neutral icon. Rank 0 is the faction's.
local function setRankIcon(tex, rank, faction)
    tex:SetTexCoord(0, 1, 0, 1)
    if not rank or rank <= 0 then
        if Kit:SetAtlasOr(tex, faction == "Horde" and RING.iconHorde or RING.iconAlliance, 0.3, 0.3, 0.3, 0) then return end
        tex:SetTexture(HonorLog.RANK_ICON_FALLBACK)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        return
    end
    local atlas = string.format(HonorLog.RANK_ICON_ATLAS, rank)
    if Kit:HasAtlas(atlas) and pcall(tex.SetAtlas, tex, atlas) then return end
    if rank <= 14 then
        tex:SetTexture(string.format(HonorLog.RANK_ICON_FILE, rank))
        return
    end
    tex:SetTexture(HonorLog.RANK_ICON_FALLBACK)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

-- The ring is drawn as PVPRankFrame does: a Cooldown frame is the progress swipe, over the faction disc and
-- under the ring art, with the rank icon in the middle and a round badge with the rank number at the bottom.
-- Without the ring art it is the rank icon over a Kit:Bar. ring:SetRank(rank, faction), ring:SetProgress(fraction).
function Kit:Ring(parent, size)
    size = size or 150
    local scale = size / 154
    local ring = CreateFrame("Frame", nil, parent)
    ring:SetSize(size, size)
    ring.honorLogRank, ring.honorLogProgress = 0, 0

    local ringArt = (Kit:HasAtlas(RING.bar) and RING.bar) or (Kit:HasAtlas(RING.barOld) and RING.barOld) or nil
    local full = ringArt ~= nil
    local cd
    if full then
        cd = tryTemplate("Cooldown", nil, ring, "CooldownFrameTemplate") or tryTemplate("Cooldown", nil, ring)
        full = cd ~= nil
    end
    ring.honorLogFull = full

    if full then
        cd:SetAllPoints(ring)
        pcall(function()
            cd:SetSwipeTexture(SWIPE)
            cd:SetReverse(true)
            cd:SetRotation(math.pi)
            cd:SetHideCountdownNumbers(true)
            cd:SetDrawEdge(false)
            cd:SetDrawBling(false)
            cd:Pause()
        end)
        ring.Cooldown = cd
        local glow = cd:CreateTexture(nil, "BACKGROUND", nil, 0)
        glow:SetSize(275 * scale, 295 * scale)
        glow:SetPoint("CENTER", ring, "CENTER", 0, 0)
        Kit:SetAtlasOr(glow, RING.glow, 0.8, 0.2, 0.15, 0.25)
        ring.Glow = glow
        ring.Disc = cd:CreateTexture(nil, "BACKGROUND", nil, 1)
        ring.Disc:SetSize(115 * scale, 115 * scale)
        ring.Disc:SetPoint("CENTER", ring, "CENTER", 0, 0)
        local art = cd:CreateTexture(nil, "BORDER")
        art:SetSize(235 * scale, 209 * scale)
        art:SetPoint("CENTER", ring, "CENTER", 0, -1 * scale)
        art:SetAtlas(ringArt)
        ring.Art = art
        ring.Icon = cd:CreateTexture(nil, "ARTWORK")
        ring.Icon:SetSize(72 * scale, 84 * scale)
        ring.Icon:SetPoint("CENTER", ring, "CENTER", 0, 0)

        local badge = CreateFrame("Frame", nil, ring)
        badge:SetSize(34 * scale, 34 * scale)
        badge:SetPoint("BOTTOM", ring, "BOTTOM", 0, -1 * scale)
        badge:SetFrameLevel(ring:GetFrameLevel() + 3)
        badge.honorLogGround = Kit:RoundGround(badge)
        local badgeRing = badge:CreateTexture(nil, "BORDER")
        badgeRing:SetAllPoints(badge)
        Kit:SetAtlasOr(badgeRing, RING.badge, 0.85, 0.66, 0.23, 1)
        badge.Label = Kit:Text(badge, "label")
        badge.Label:SetPoint("CENTER", 0, 0)
        badge.Label:SetJustifyH("CENTER")
        ring.Badge = badge
    else
        ring.Icon = ring:CreateTexture(nil, "ARTWORK")
        ring.Icon:SetSize(size * 0.7, size * 0.7)
        ring.Icon:SetPoint("TOP", ring, "TOP", 0, 0)
        ring.Bar = Kit:Bar(ring)
        ring.Bar:SetPoint("BOTTOMLEFT", ring, "BOTTOMLEFT", 0, 0)
        ring.Bar:SetPoint("BOTTOMRIGHT", ring, "BOTTOMRIGHT", 0, 0)
        ring.Bar:SetHeight(12)
        ring.Badge = CreateFrame("Frame", nil, ring)
        ring.Badge.Label = Kit:Text(ring.Badge, "label")
        ring.Badge.Label:SetPoint("BOTTOM", ring.Icon, "BOTTOM", 0, 0)
        ring.Badge.Label:SetJustifyH("CENTER")
    end

    function ring:SetRank(rank, faction)
        rank = num(rank) or 0
        self.honorLogRank, self.honorLogFaction = rank, faction
        if self.honorLogFull then
            Kit:SetAtlasOr(self.Disc, faction == "Horde" and RING.horde or RING.alliance, 0.2, 0.12, 0.12, 1)
        end
        setRankIcon(self.Icon, rank, faction)
        self.Badge.Label:SetText(rank > 0 and tostring(rank) or "")
        -- no rank yet: no empty badge under the faction emblem
        if self.honorLogFull then self.Badge:SetShown(rank > 0) end
    end

    function ring:SetProgress(fraction)
        fraction = clamp01(fraction)
        self.honorLogProgress = fraction
        if self.honorLogFull then
            if CooldownFrame_SetDisplayAsPercentage then
                CooldownFrame_SetDisplayAsPercentage(self.Cooldown, fraction)
            else
                -- The same thing by hand: a 100-second cooldown paused at the wanted share.
                local duration = 100
                self.Cooldown:SetCooldown(GetTime() - duration * math.min(fraction, 0.9999), duration)
                self.Cooldown:Pause()
            end
        else
            self.Bar:SetValue01(fraction)
        end
    end

    ring:SetRank(0, Util.str(call(UnitFactionGroup, "player")) or "Alliance")
    ring:SetProgress(0)
    return ring
end

--------------------------------------------------------------------------------
-- Tile and rows
--------------------------------------------------------------------------------

-- An inset with a gold label, a big value and a note line. The note line can instead hold a row of widgets
-- (tile.noteRow, a frame in the same place; hide tile.note and show it).
function Kit:Tile(parent)
    -- A frame of our own holds the fields; the inset (which may be a Blizzard template) is only its ground.
    local tile = CreateFrame("Frame", nil, parent)
    local inset = Kit:Inset(tile)
    inset:SetAllPoints(tile)
    local face = CreateFrame("Frame", nil, tile)
    face:SetAllPoints(tile)
    face:SetFrameLevel((num(inset:GetFrameLevel()) or 0) + 1)
    tile.inset = inset
    tile.label = Kit:Text(face, "labelSmall")
    tile.label:SetPoint("TOPLEFT", tile, "TOPLEFT", 12, -7)
    tile.value = Kit:Text(face, "big")
    tile.value:SetPoint("TOPLEFT", tile, "TOPLEFT", 12, -20)
    tile.note = Kit:Text(face, "grey")
    tile.note:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 12, 7)
    tile.note:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -8, 7)
    tile.noteRow = CreateFrame("Frame", nil, face)
    tile.noteRow:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 12, 6)
    tile.noteRow:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -8, 6)
    tile.noteRow:SetHeight(16)
    tile.noteRow:Hide()
    return tile
end

-- A pooled list. create(row, index) runs once per row, update(row, entry, index) on every SetData.
function Kit:Rows(parent, rowHeight, create, update)
    local rows = { frames = {}, count = 0 }
    function rows:SetData(list)
        list = list or {}
        for i, entry in ipairs(list) do
            local row = self.frames[i]
            if not row then
                row = CreateFrame("Frame", nil, parent)
                row:SetHeight(rowHeight)
                row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * rowHeight)
                row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(i - 1) * rowHeight)
                row.honorLogStripe = row:CreateTexture(nil, "BACKGROUND")
                row.honorLogStripe:SetAllPoints(row)
                row.honorLogStripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
                if create then create(row, i) end
                self.frames[i] = row
            end
            row:Show()
            if update then update(row, entry, i) end
        end
        for i = #list + 1, #self.frames do self.frames[i]:Hide() end
        self.count = #list
    end
    return rows
end

--------------------------------------------------------------------------------
-- Stack, fixed text and sequence
--------------------------------------------------------------------------------

-- Rows of several kinds in one scrolling child, each kind with its own height. makers[kind] =
-- { create = function(row), update = function(row, entry) }; an entry is { kind, height, ... }. A row frame is
-- made once per kind and position and reused, so the number of frames grows to the longest list and no further.
-- stack:SetData(entries) returns the content height. Moved here from UI/GearVendors.lua, which keeps an alias.
function Kit:Stack(child, makers)
    local stack = { pools = {}, height = 0, count = 0 }
    function stack:SetData(entries)
        local used, y = {}, 0
        for _, entry in ipairs(entries or {}) do
            local kind = entry.kind
            local maker = makers[kind]
            local pool = self.pools[kind]
            if not pool then
                pool = {}
                self.pools[kind] = pool
            end
            used[kind] = (used[kind] or 0) + 1
            local row = pool[used[kind]]
            if not row then
                row = CreateFrame("Frame", nil, child)
                maker.create(row)
                pool[used[kind]] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
            row:SetHeight(entry.height)
            row:Show()
            row.honorLogEntry = entry
            maker.update(row, entry)
            y = y + entry.height
        end
        for kind, pool in pairs(self.pools) do
            for i = (used[kind] or 0) + 1, #pool do pool[i]:Hide() end
        end
        self.height, self.count = y, #(entries or {})
        return y
    end
    return stack
end

-- A fixed-width one-line text: the client cuts it with "..." when it is longer than its box.
function Kit:FixedText(parent, style, width)
    local fs = Kit:Text(parent, style)
    fs:SetWidth(width)
    fs:SetWordWrap(false)
    return fs
end

local SEQUENCE_SIZE, SEQUENCE_GAP = 14, 2
local SEQUENCE_LETTERS = { W = "green", L = "red", D = "grey", X = "orange" }

-- A row of `count` small squares for recent results, oldest at the left: seq:SetResults({ "W", "L", "D", "X" }).
-- Each square carries its letter (W win, L loss, D draw, X left early) in small text over a tint of its colour
-- (green, red, grey, orange), so the result is never colour alone. More results than squares keep the newest;
-- unused squares are hidden. All squares are made at once and reused; the row's tooltip says what the letters mean.
function Kit:Sequence(parent, count)
    count = math.max(1, math.floor(num(count) or 10))
    local seq = CreateFrame("Frame", nil, parent)
    seq:SetSize(count * SEQUENCE_SIZE + (count - 1) * SEQUENCE_GAP, SEQUENCE_SIZE)
    seq:EnableMouse(true)
    seq.honorLogSquares = {}
    for i = 1, count do
        local sq = CreateFrame("Frame", nil, seq)
        sq:SetSize(SEQUENCE_SIZE, SEQUENCE_SIZE)
        sq:SetPoint("TOPLEFT", seq, "TOPLEFT", (i - 1) * (SEQUENCE_SIZE + SEQUENCE_GAP), 0)
        sq.honorLogTint = sq:CreateTexture(nil, "BACKGROUND")
        sq.honorLogTint:SetAllPoints(sq)
        sq.honorLogLetter = Kit:Text(sq, "grey")
        sq.honorLogLetter:SetPoint("CENTER", sq, "CENTER", 0, 0)
        sq.honorLogLetter:SetJustifyH("CENTER")
        sq:Hide()
        seq.honorLogSquares[i] = sq
    end

    function seq:SetResults(results)
        results = type(results) == "table" and results or {}
        local first = math.max(1, #results - count + 1)
        local shown = 0
        for i = first, #results do
            local letter = results[i]
            local colorName = SEQUENCE_LETTERS[letter]
            if colorName and shown < count then
                shown = shown + 1
                local sq = self.honorLogSquares[shown]
                local c = Kit.COLORS[colorName]
                sq.honorLogResult, sq.honorLogColorName = letter, colorName
                sq.honorLogTint:SetColorTexture(c[1] * 0.4, c[2] * 0.4, c[3] * 0.4, 1)
                sq.honorLogLetter:SetText(letter)
                sq.honorLogLetter:SetTextColor(c[1], c[2], c[3])
                sq:Show()
            end
        end
        for i = shown + 1, count do self.honorLogSquares[i]:Hide() end
        self.honorLogShown = shown
    end

    seq:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Recent results, oldest first"], 1, 0.82, 0)
        GameTooltip:AddLine(L["W win, L loss, D draw, X left early"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    seq:SetScript("OnLeave", function() GameTooltip:Hide() end)
    seq:SetResults({})
    return seq
end

--------------------------------------------------------------------------------
-- Item and mark icons
--------------------------------------------------------------------------------

local QUALITY = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 },
}

-- r, g, b of an item quality (0 poor .. 7 heirloom).
function Kit:QualityColor(quality)
    quality = num(quality) or 1
    local blizzard = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if type(blizzard) == "table" and num(blizzard.r) and num(blizzard.g) and num(blizzard.b) then
        return blizzard.r, blizzard.g, blizzard.b
    end
    local c = QUALITY[quality] or QUALITY[1]
    return c[1], c[2], c[3]
end

-- "|cffrrggbb" for a quality.
function Kit:QualityHex(quality)
    local r, g, b = self:QualityColor(quality)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local function itemQuality(itemID)
    local q = C_Item and C_Item.GetItemQualityByID and num(call(C_Item.GetItemQualityByID, itemID))
    if q then return q end
    local base = HonorLog.GearDB and HonorLog.GearDB[itemID]
    return base and num(base.quality) or 1
end

local function itemLink(itemID)
    local _, link = HonorLog.Compat.GetItemInfo(itemID)
    if type(link) == "string" and not Util.isSecret(link) then return link end
end

-- The square every icon shares: a quality-coloured 1-pixel border round the texture.
local function iconButton(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.honorLogBorder = b:CreateTexture(nil, "BACKGROUND")
    b.honorLogBorder:SetAllPoints(b)
    b.honorLogBorder:SetColorTexture(1, 1, 1, 1)
    b.honorLogTexture = b:CreateTexture(nil, "ARTWORK")
    b.honorLogTexture:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.honorLogTexture:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.honorLogTexture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.18)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function shiftLink(link)
    if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
end

-- Opens the dressing room on an item (what Ctrl+click on an item icon does). True when it was handed over.
function Kit:PreviewItem(itemID)
    itemID = num(itemID)
    local link = itemID and itemLink(itemID)
    if link and DressUpItemLink then
        pcall(DressUpItemLink, link)
        -- The dressing room is a panel of its own: bring it in front of the window the click came from.
        local dress = _G.DressUpFrame
        if type(dress) == "table" and call(dress.IsShown, dress) then call(dress.Raise, dress) end
        return true
    end
    return false
end

-- A button with an item's icon. icon:SetItem(itemID). Hover: the item's tooltip and where it is sold. Click:
-- the vendor on the map; Ctrl+click previews it; Shift+click links it into an open chat box.
function Kit:ItemIcon(parent, size)
    local icon = iconButton(parent, size or 18)

    function icon:SetItem(itemID)
        itemID = num(itemID)
        self.honorLogItemID = itemID or false
        if not itemID then
            self.honorLogTexture:SetTexture(QUESTION_MARK)
            self.honorLogBorder:SetColorTexture(Kit:QualityColor(1))
            return
        end
        local texture = C_Item and C_Item.GetItemIconByID and call(C_Item.GetItemIconByID, itemID)
        self.honorLogTexture:SetTexture(texture or QUESTION_MARK)
        self.honorLogQuality = itemQuality(itemID)
        local r, g, b = Kit:QualityColor(self.honorLogQuality)
        self.honorLogBorder:SetColorTexture(r, g, b, 1)
    end

    icon:SetScript("OnEnter", function(self)
        local id = self.honorLogItemID
        if not id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetItemByID, GameTooltip, id)
        local line = HonorLog:GetVendorLine(id)
        if line then GameTooltip:AddLine(line, 0.7, 0.9, 1) end
        if HonorLog:GetVendorFor(id) then
            GameTooltip:AddLine(L["Click: show the vendor on your map"], 0.25, 0.88, 0.38)
        end
        GameTooltip:Show()
    end)

    icon:SetScript("OnClick", function(self)
        local id = self.honorLogItemID
        if not id then return end
        if IsShiftKeyDown() then
            shiftLink(itemLink(id))
        elseif IsControlKeyDown() then
            Kit:PreviewItem(id)
        else
            HonorLog:ShowVendorForItem(id)
        end
    end)
    return icon
end

-- The same shape for a battleground's mark. mark:SetBattleground(bgType).
function Kit:MarkIcon(parent, size)
    local mark = iconButton(parent, size or 14)

    function mark:SetBattleground(bgType)
        self.honorLogBG = bgType
        self.honorLogTexture:SetTexture(HonorLog.BG_ICONS[bgType] or QUESTION_MARK)
        self.honorLogBorder:SetColorTexture(Kit:QualityColor(2))
    end

    local function itemID(self)
        local bg = self.honorLogBG
        return bg and ((HonorLog.BG_MARK_ITEMS and HonorLog.BG_MARK_ITEMS[bg]) or (HonorLog.MARK_ITEMS and HonorLog.MARK_ITEMS[bg])) or nil
    end

    mark:SetScript("OnEnter", function(self)
        local id = itemID(self)
        if not id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetItemByID, GameTooltip, id)
        GameTooltip:AddLine(string.format(L["In your bags: %d"], num(HonorLog:GetCurrentMarks(self.honorLogBG)) or 0), 1, 0.82, 0)
        GameTooltip:Show()
    end)
    mark:SetScript("OnClick", function(self)
        local id = itemID(self)
        if id and IsShiftKeyDown() then shiftLink(itemLink(id)) end
    end)
    return mark
end

--------------------------------------------------------------------------------
-- Chart
--------------------------------------------------------------------------------

local DASH, GAP = 6, 4

-- A drawing surface for lines, dots, filled boxes and labels, in the chart's own pixels measured from its
-- bottom-left corner. Everything is pooled: Clear() hides what a redraw used and the next draw takes it back,
-- so the number of lines, boxes and labels grows to the largest drawing and no further. Lines are the client's
-- own Line regions (CreateLine, as Blizzard's Edit Mode draws its guides); a client without CreateLine gets
-- horizontal and vertical lines as thin boxes and skips slanted ones. Nothing here runs per frame.
-- A plain frame of our own, so its fields are free; the pools are still named honorLog....
function Kit:Chart(parent)
    local chart = CreateFrame("Frame", nil, parent)
    chart.honorLogLines, chart.honorLogRects, chart.honorLogLabels = {}, {}, {}
    chart.honorLogLinesUsed, chart.honorLogRectsUsed = 0, 0
    chart.honorLogLabelsUsed = {}

    local function canLine()
        return type(chart.CreateLine) == "function"
    end

    function chart:Clear()
        for i = 1, #self.honorLogLines do self.honorLogLines[i]:Hide() end
        for i = 1, #self.honorLogRects do self.honorLogRects[i]:Hide() end
        for _, list in pairs(self.honorLogLabels) do
            for i = 1, #list do list[i]:Hide() end
        end
        self.honorLogLinesUsed, self.honorLogRectsUsed, self.honorLogLabelsUsed = 0, 0, {}
    end

    -- A filled box from (x, y), its bottom-left corner, w by h.
    function chart:Rect(x, y, w, h, r, g, b, a)
        x, y, w, h = num(x), num(y), num(w), num(h)
        if not (x and y and w and h) then return nil end
        local n = self.honorLogRectsUsed + 1
        self.honorLogRectsUsed = n
        local tex = self.honorLogRects[n]
        if not tex then
            tex = self:CreateTexture(nil, "ARTWORK")
            self.honorLogRects[n] = tex
        end
        tex:ClearAllPoints()
        tex:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, y)
        tex:SetSize(math.max(w, 0), math.max(h, 0))
        tex:SetColorTexture(r or 1, g or 1, b or 1, a or 1)
        tex:Show()
        return tex
    end

    -- A straight line. Returns true when something was drawn.
    function chart:Line(x1, y1, x2, y2, thickness, r, g, b, a)
        x1, y1, x2, y2 = num(x1), num(y1), num(x2), num(y2)
        if not (x1 and y1 and x2 and y2) then return false end
        thickness = num(thickness) or 1
        if canLine() then
            local n = self.honorLogLinesUsed + 1
            local line = self.honorLogLines[n]
            if not line then
                local ok, made = pcall(self.CreateLine, self, nil, "ARTWORK")
                if ok and type(made) == "table" then
                    line = made
                    self.honorLogLines[n] = line
                end
            end
            if line then
                self.honorLogLinesUsed = n
                line:SetThickness(thickness)
                line:SetStartPoint("BOTTOMLEFT", self, x1, y1)
                line:SetEndPoint("BOTTOMLEFT", self, x2, y2)
                line:SetColorTexture(r or 1, g or 1, b or 1, a or 1)
                line:Show()
                return true
            end
        end
        -- no lines on this client: a thin box for a level or an upright line, nothing for a slanted one
        if y1 == y2 then
            return self:Rect(math.min(x1, x2), y1 - thickness / 2, math.abs(x2 - x1), thickness, r, g, b, a) ~= nil
        elseif x1 == x2 then
            return self:Rect(x1 - thickness / 2, math.min(y1, y2), thickness, math.abs(y2 - y1), r, g, b, a) ~= nil
        end
        return false
    end

    -- The same as short segments.
    function chart:Dashed(x1, y1, x2, y2, thickness, r, g, b, a)
        x1, y1, x2, y2 = num(x1), num(y1), num(x2), num(y2)
        if not (x1 and y1 and x2 and y2) then return false end
        local length = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
        if length <= 0 then return false end
        local ux, uy = (x2 - x1) / length, (y2 - y1) / length
        local at, drawn = 0, false
        while at < length do
            local to = math.min(at + DASH, length)
            if self:Line(x1 + ux * at, y1 + uy * at, x1 + ux * to, y1 + uy * to, thickness, r, g, b, a) then drawn = true end
            at = to + GAP
        end
        return drawn
    end

    -- A square dot centred on (x, y).
    function chart:Dot(x, y, size, r, g, b)
        x, y, size = num(x), num(y), num(size) or 6
        if not (x and y) then return nil end
        return self:Rect(x - size / 2, y - size / 2, size, size, r, g, b, 1)
    end

    -- A text at (x, y): justify "LEFT" puts its left edge there, "RIGHT" its right edge, else its middle.
    -- colorName is a Kit.COLORS key; without one the style's own colour stands.
    function chart:Label(x, y, text, style, justify, colorName)
        x, y = num(x), num(y)
        if not (x and y) then return nil end
        style = Kit.FONTS[style] and style or "grey"
        local key = style .. "/" .. (colorName or "")
        local list = self.honorLogLabels[key]
        if not list then
            list = {}
            self.honorLogLabels[key] = list
        end
        local n = (self.honorLogLabelsUsed[key] or 0) + 1
        self.honorLogLabelsUsed[key] = n
        local fs = list[n]
        if not fs then
            fs = Kit:Text(self, style)
            if colorName and Kit.COLORS[colorName] then
                local c = Kit.COLORS[colorName]
                fs:SetTextColor(c[1], c[2], c[3])
            end
            list[n] = fs
        end
        local anchor = justify == "LEFT" and "LEFT" or justify == "RIGHT" and "RIGHT" or "CENTER"
        fs:ClearAllPoints()
        fs:SetPoint(anchor, self, "BOTTOMLEFT", x, y)
        fs:SetJustifyH(anchor)
        fs:SetText(text or "")
        fs:Show()
        return fs
    end

    return chart
end

--------------------------------------------------------------------------------
-- Map link
--------------------------------------------------------------------------------

-- A small pin and a name. link:SetVendor(vendor) or link:SetPlace(place); a click puts the pin on the map.
function Kit:PlaceLink(parent)
    local link = CreateFrame("Button", nil, parent)
    link:SetHeight(16)
    link.honorLogPin = link:CreateTexture(nil, "ARTWORK")
    link.honorLogPin:SetSize(12, 12)
    link.honorLogPin:SetPoint("LEFT", link, "LEFT", 0, 0)
    Kit:SetAtlasOr(link.honorLogPin, "Waypoint-MapPin-Untracked", 1, 0.82, 0, 1)
    link.honorLogName = Kit:Text(link, "label")
    link.honorLogName:SetPoint("LEFT", link.honorLogPin, "RIGHT", 4, 0)

    local function show(self, name)
        self.honorLogName:SetText(name or "")
        self:SetWidth(18 + (self.honorLogName:GetStringWidth() or 0))
    end
    function link:SetVendor(vendor)
        self.honorLogVendor, self.honorLogPlace = vendor, false
        show(self, type(vendor) == "table" and vendor.name or nil)
    end
    function link:SetPlace(place)
        self.honorLogVendor, self.honorLogPlace = false, place
        show(self, type(place) == "table" and place.name or nil)
    end
    link:SetScript("OnEnter", function(self) self.honorLogName:SetTextColor(1, 1, 1) end)
    link:SetScript("OnLeave", function(self) self.honorLogName:SetTextColor(Kit.COLORS.gold[1], Kit.COLORS.gold[2], Kit.COLORS.gold[3]) end)
    link:SetScript("OnClick", function(self)
        if self.honorLogVendor then
            HonorLog:ShowVendorOnMap(self.honorLogVendor)
        elseif self.honorLogPlace then
            HonorLog:ShowPlaceOnMap(self.honorLogPlace)
        end
    end)
    return link
end

--------------------------------------------------------------------------------
-- Text fitting
--------------------------------------------------------------------------------

-- The number of characters in a string (a multi-byte character counts once).
function Kit:Chars(text)
    return #(tostring(text or ""):gsub("[\128-\191]", ""))
end

-- The text cut to at most maxChars characters, ending in "..." when something was cut. Never cuts a
-- multi-byte character in half.
function Kit:Cut(text, maxChars)
    text = tostring(text or "")
    maxChars = math.max(0, math.floor(num(maxChars) or 0))
    if Kit:Chars(text) <= maxChars then return text end
    local keep = math.max(0, maxChars - 3)
    local i, n, chars = 1, #text, 0
    while i <= n and chars < keep do
        local b = text:byte(i)
        i = i + (b >= 240 and 4 or b >= 224 and 3 or b >= 192 and 2 or 1)
        chars = chars + 1
    end
    return text:sub(1, i - 1) .. "..."
end

--------------------------------------------------------------------------------
-- Scroll area
--------------------------------------------------------------------------------

-- Blizzard's two scroll frames in this build (Blizzard_SharedXML): ScrollFrameTemplate (the new one; its
-- OnLoad, ScrollFrame_OnLoad in SecureUIPanelTemplates.lua, makes its own MinimalScrollBar as .ScrollBar just
-- right of the frame) and UIPanelScrollFrameTemplate (the classic one, SecureScrollTemplates.xml, with a
-- parentKey ScrollBar slider the same distance out). Both put the bar OUTSIDE the frame: leave
-- Kit.SCROLL_BAR_SPACE pixels to its right.
Kit.SCROLL_BAR_SPACE = 22
local SCROLL_STEP = 30
local scrollAreas = 0

-- A scrolling region for a list that can be longer than its box. area.honorLogChild is a plain frame for the
-- rows, as wide as the area; area:honorLogSetContentHeight(h) tells it how tall the rows are. With content no
-- taller than the box the bar is hidden and the wheel does nothing. Size it with SetSize (or SetWidth and
-- SetHeight): the child follows. The wheel is handled here for all three kinds, one notch is 30 pixels.
-- Nothing runs per frame.
function Kit:ScrollArea(parent)
    scrollAreas = scrollAreas + 1
    local area, template = Kit:TryTemplate("ScrollFrame", nil, parent, "ScrollFrameTemplate"), "ScrollFrameTemplate"
    if not area then
        area, template = Kit:TryTemplate("ScrollFrame", "HonorLogScrollArea" .. scrollAreas, parent, "UIPanelScrollFrameTemplate"), "UIPanelScrollFrameTemplate"
    end
    if not area then area, template = CreateFrame("ScrollFrame", nil, parent), nil end
    area.honorLogTemplate = template or false
    area.honorLogContentHeight = 0
    local bar = template and type(area.ScrollBar) == "table" and area.ScrollBar or nil
    area.honorLogBar = bar or false
    if bar and template == "ScrollFrameTemplate" and type(bar.SetHideIfUnscrollable) == "function" then
        pcall(bar.SetHideIfUnscrollable, bar, true)
    end

    local child = CreateFrame("Frame", nil, area)
    child:SetSize(1, 1)
    area:SetScrollChild(child)
    area.honorLogChild = child

    local function range()
        return math.max(0, (area.honorLogContentHeight or 0) - (num(area:GetHeight()) or 0))
    end
    local function syncWidth()
        local w = num(area:GetWidth())
        if w and w > 0 then child:SetWidth(w) end
    end

    function area:honorLogSetContentHeight(h)
        h = math.max(0, num(h) or 0)
        self.honorLogContentHeight = h
        syncWidth()
        child:SetHeight(math.max(h, 1))
        local max = range()
        local current = num(self:GetVerticalScroll()) or 0
        if current > max then self:SetVerticalScroll(max) end
        if self.honorLogBar then
            if max > 0 then self.honorLogBar:Show() else self.honorLogBar:Hide() end
        end
    end

    area:EnableMouseWheel(true)
    area:SetScript("OnMouseWheel", function(self, delta)
        delta = num(delta) or 0
        local max = range()
        if max <= 0 or delta == 0 then return end
        local current = num(self:GetVerticalScroll()) or 0
        self:SetVerticalScroll(math.max(0, math.min(max, current - delta * SCROLL_STEP)))
    end)
    area:HookScript("OnSizeChanged", syncWidth)
    return area
end

--------------------------------------------------------------------------------
-- Star
--------------------------------------------------------------------------------

-- A toggle for "this is a goal". star:SetOn(bool), star:IsOn(); a click flips it and calls
-- star.honorLogOnToggle(star, on). The art is the client's own star, Interface\Common\ReputationStar (the file
-- Forever's reputation window draws its star from; a file cannot be asked for the way an atlas can): the gold
-- star when on, the outlined star in grey when off, so the state is not colour alone. (The file's own dark
-- star, top right, is black on black on this window's ground.)
local STAR_FILE = "Interface\\Common\\ReputationStar"
local STAR_ON, STAR_OFF, STAR_GLOW = { 0, 0.5, 0, 0.5 }, { 0, 0.5, 0.5, 1 }, { 0, 0.5, 0.5, 1 }
Kit.STAR = { file = STAR_FILE, on = STAR_ON, off = STAR_OFF }

function Kit:Star(parent, size)
    size = size or 18
    local star = CreateFrame("Button", nil, parent)
    star:SetSize(size, size)
    star.honorLogOn = false
    star.honorLogArt = star:CreateTexture(nil, "ARTWORK")
    star.honorLogArt:SetAllPoints(star)
    star.honorLogArt:SetTexture(STAR_FILE)
    local hl = star:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(star)
    hl:SetTexture(STAR_FILE)
    hl:SetTexCoord(STAR_GLOW[1], STAR_GLOW[2], STAR_GLOW[3], STAR_GLOW[4])
    hl:SetBlendMode("ADD")

    function star:SetOn(on)
        on = on and true or false
        self.honorLogOn = on
        local c = on and STAR_ON or STAR_OFF
        self.honorLogArt:SetTexCoord(c[1], c[2], c[3], c[4])
        self.honorLogArt:SetDesaturated(not on)
        self.honorLogArt:SetAlpha(on and 1 or 0.85)
    end
    function star:IsOn() return self.honorLogOn end

    star:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.honorLogOn and L["Remove from your goals"] or L["Add to your goals"], 1, 1, 1)
        GameTooltip:Show()
    end)
    star:SetScript("OnLeave", function() GameTooltip:Hide() end)
    star:SetScript("OnClick", function(self)
        self:SetOn(not self.honorLogOn)
        if self.honorLogOnToggle then self.honorLogOnToggle(self, self.honorLogOn) end
    end)
    star:SetOn(false)
    return star
end

--------------------------------------------------------------------------------
-- Chips
--------------------------------------------------------------------------------

local CHIP_CHAR, CHIP_PAD, CHIP_GAP, CHIP_HEIGHT = 6, 16, 4, 20

-- A row of small buttons of which one is chosen. chips:SetOptions({ { key, text, maxWidth, tip }, ... }, chosenKey)
-- lays them out left to right (a text wider than maxWidth is cut, with the full text, or tip, as its tooltip);
-- a click chooses one and calls onSelect(key). The chosen one is highlight-locked and underlined, the way the
-- Rank plan's target buttons are. The buttons are pooled: SetOptions never makes more than the longest list.
-- chips.honorLogChosen is the key; the frame is as wide as its buttons, so it can be anchored by its right edge.
function Kit:Chips(parent, onSelect)
    local chips = CreateFrame("Frame", nil, parent)
    chips:SetHeight(CHIP_HEIGHT)
    chips.honorLogButtons, chips.honorLogChosen = {}, nil
    chips.honorLogUnderline = chips:CreateTexture(nil, "OVERLAY")
    chips.honorLogUnderline:SetHeight(2)
    chips.honorLogUnderline:SetColorTexture(1, 0.82, 0, 1)
    chips.honorLogUnderline:Hide()

    local function choose(key)
        chips.honorLogChosen = key
        for _, b in ipairs(chips.honorLogButtons) do
            local chosen = b:IsShown() and b.honorLogKey == key
            b.honorLogChosenFlag = chosen
            pcall(chosen and b.LockHighlight or b.UnlockHighlight, b)
            if chosen then
                chips.honorLogUnderline:ClearAllPoints()
                chips.honorLogUnderline:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 3, -3)
                chips.honorLogUnderline:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, -3)
                chips.honorLogUnderline:Show()
            end
        end
    end

    local function make()
        local b = Kit:Button(chips, "", "small")
        b:SetScript("OnClick", function(self)
            choose(self.honorLogKey)
            if onSelect then onSelect(self.honorLogKey) end
        end)
        -- hooked, not set: a template button may come with scripts of its own
        b:HookScript("OnEnter", function(self)
            if not self.honorLogTip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.honorLogTip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end

    function chips:SetOptions(options, chosenKey)
        options = options or {}
        local x, found, first = 0, false, nil
        for i, opt in ipairs(options) do
            local b = self.honorLogButtons[i]
            if not b then
                b = make()
                self.honorLogButtons[i] = b
            end
            local text = tostring(opt.text or "")
            local width = Kit:Chars(text) * CHIP_CHAR + CHIP_PAD
            local shown = text
            if opt.maxWidth and width > opt.maxWidth then
                width = opt.maxWidth
                shown = Kit:Cut(text, math.floor((width - CHIP_PAD) / CHIP_CHAR))
            end
            width = math.max(width, 36)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self, "TOPLEFT", x, 0)
            b:SetSize(width, CHIP_HEIGHT)
            b:SetText(shown)
            b.honorLogKey = opt.key
            b.honorLogTip = opt.tip or (shown ~= text and text or nil)
            b:Show()
            x = x + width + CHIP_GAP
            first = first or opt.key
            if opt.key == chosenKey then found = true end
        end
        for i = #options + 1, #self.honorLogButtons do self.honorLogButtons[i]:Hide() end
        self:SetWidth(math.max(1, x - CHIP_GAP))
        self.honorLogUnderline:Hide()
        choose(found and chosenKey or first)
    end
    return chips
end

--------------------------------------------------------------------------------
-- Card
--------------------------------------------------------------------------------

Kit.CARD_STRIP = 24

-- The chrome every pop-up card shares (UI/Moments.lua): a dark ground, a 1 pixel gold edge, a title strip with a
-- gold title and a close button at the top right, and honorLogBody, a plain frame under the strip for the content.
-- card:SetTitle(text) names it, card:SetBodyHeight(h) sizes it. A plain frame of our own at strata HIGH, hidden
-- until its owner shows it; it is not registered for the Escape key, so the scoreboard and the other windows
-- keep it. The close button is Blizzard's UIPanelCloseButton when the client has it (its art and click are
-- Blizzard's; nothing of ours is put on it but honorLog... names), else a drawn square with an "x". Its click
-- hides the card; the owner replaces the click when it has more to do.
function Kit:Card(name, width)
    width = num(width) or 360
    local gold = Kit.COLORS.gold
    local card = CreateFrame("Frame", name, UIParent)
    card:SetSize(width, Kit.CARD_STRIP + 2)
    card:SetFrameStrata("HIGH")
    card:SetClampedToScreen(true)
    card:EnableMouse(true)
    card:Hide()
    -- opaque: at 0.97 the game's zone name ("Mulgore") showed through the card (seen in game)
    fill(card, 0.06, 0.055, 0.05, 1)
    Kit:Edges(card, gold[1], gold[2], gold[3], 1)

    local strip = card:CreateTexture(nil, "BORDER")
    strip:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
    strip:SetPoint("TOPRIGHT", card, "TOPRIGHT", -1, -1)
    strip:SetHeight(Kit.CARD_STRIP - 1)
    strip:SetColorTexture(0.16, 0.12, 0.11, 1)
    card.honorLogStrip = strip

    -- 34 pixels stay clear at the right for the close button
    local title = Kit:FixedText(card, "label", width - 44)
    title:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -6)
    card.honorLogTitleText = title
    function card:SetTitle(text)
        self.honorLogTitle = text
        title:SetText(text or "")
    end

    local close = tryTemplate("Button", nil, card, "UIPanelCloseButton")
    if close then
        close:SetSize(Kit.CARD_STRIP, Kit.CARD_STRIP)
        close:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
        card.honorLogCloseTemplate = "UIPanelCloseButton"
    else
        close = CreateFrame("Button", nil, card)
        close:SetSize(20, 20)
        close:SetPoint("TOPRIGHT", card, "TOPRIGHT", -3, -2)
        fill(close, 0.16, 0.06, 0.05, 1)
        Kit:Edges(close, 0.45, 0.42, 0.38, 1)
        local hl = close:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(close)
        hl:SetColorTexture(1, 1, 1, 0.12)
        local x = Kit:Text(close, "label")
        x:SetPoint("CENTER", 0, 0)
        x:SetText("x")
        close.honorLogLabel = x
        card.honorLogCloseTemplate = false
    end
    close:SetScript("OnClick", function() card:Hide() end)
    card.honorLogClose = close

    local body = CreateFrame("Frame", nil, card)
    body:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -(Kit.CARD_STRIP + 1))
    body:SetSize(width - 2, 1)
    card.honorLogBody = body

    -- The card is the strip, the body and the two edges.
    function card:SetBodyHeight(h)
        h = math.max(0, num(h) or 0)
        body:SetHeight(h)
        self:SetHeight(Kit.CARD_STRIP + 2 + h)
    end
    card:SetBodyHeight(0)
    return card
end
