-- HonorLog Kit
-- The pieces the full window is built from: a window frame, insets, headers, buttons, tabs, bars, the rank
-- ring, tiles, a pooled list, item and mark icons and a map link.
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

function Kit:HasAtlas(name)
    if type(name) ~= "string" or not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
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
    frame:SetFrameStrata("HIGH")
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
            button:SetPoint("TOPLEFT", previous, "TOPRIGHT", 3, 0)
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

local RING = {
    glow = "UI-Character-Info-Honor-Bar-BG-Glow",
    horde = "UI-Character-Info-Honor-Bar-BG-Horde",
    alliance = "UI-Character-Info-Honor-Bar-BG-Alliance",
    bar = "UI-Character-Info-Honor-Bar",
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

    local full = Kit:HasAtlas(RING.bar)
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
        art:SetAtlas(RING.bar)
        ring.Art = art
        ring.Icon = cd:CreateTexture(nil, "ARTWORK")
        ring.Icon:SetSize(72 * scale, 84 * scale)
        ring.Icon:SetPoint("CENTER", ring, "CENTER", 0, 0)

        local badge = CreateFrame("Frame", nil, ring)
        badge:SetSize(34 * scale, 34 * scale)
        badge:SetPoint("BOTTOM", ring, "BOTTOM", 0, -1 * scale)
        badge:SetFrameLevel(ring:GetFrameLevel() + 3)
        local cover = badge:CreateTexture(nil, "BACKGROUND")
        cover:SetAllPoints(badge)
        cover:SetColorTexture(0.1, 0.1, 0.1, 1)
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
            local link = itemLink(id)
            if link and DressUpItemLink then DressUpItemLink(link) end
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
