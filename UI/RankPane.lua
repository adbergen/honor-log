-- HonorLog rank pane
-- The left pane the Overview and the Rank plan screens share: the rank ring, the rank title, the points, the
-- level gate note, what the next rank unlocks, and the honor bar. Moved out of UI/Screens/Overview.lua as it
-- was; every number comes from Modules/Rank.lua, Model.lua and Data.lua, and a read that fails or returns
-- nothing leaves its text empty instead of raising.
--
-- Loaded after Kit, before the screens. Nothing here creates a frame until Create is called.

local _, HonorLog = ...
HonorLog = HonorLog or {}

local Util = HonorLog.Util
local num, str = Util.num, Util.str
local L = HonorLog.L
local Kit = HonorLog.Kit

local RankPane = {}
HonorLog.RankPane = RankPane

local WIDTH = 264
RankPane.WIDTH = WIDTH
local UNLOCK_ICONS = 5 -- item icons shown for the next rank's unlocks
local WARNING = "Interface\\DialogFrame\\DialogAlertIcon"

local function commas(n) return HonorLog.Rank.FormatNumber(n) end

-- The first result of a model call, or nil when it raises.
local function safe(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
end

local function color(fs, name)
    local c = Kit.COLORS[name]
    fs:SetTextColor(c[1], c[2], c[3])
end

local function white(text) return Kit:Hex("white") .. text .. "|r" end

local function build(root)
    local pane = CreateFrame("Frame", nil, root)
    pane:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
    pane:SetWidth(WIDTH)

    local bg = pane:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(pane)
    if not Kit:SetAtlasOr(bg, "UI-Character-Info-General-BG", 0.17, 0.115, 0.12, 1) then
        pcall(bg.SetGradient, bg, "VERTICAL", CreateColor(0.11, 0.07, 0.07, 1), CreateColor(0.23, 0.16, 0.17, 1))
    end
    local divider = pane:CreateTexture(nil, "BORDER")
    divider:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
    divider:SetWidth(4)
    if not Kit:SetAtlasOr(divider, "common-framedivider", 0.43, 0.42, 0.38, 1) then divider:SetWidth(1) end

    local p = { pane = pane }
    p.season = Kit:Text(pane, "label")
    p.season:SetPoint("TOP", pane, "TOP", 0, -14)
    p.rank = Kit:Text(pane, "title")
    p.rank:SetPoint("TOP", pane, "TOP", 0, -34)
    p.line = pane:CreateTexture(nil, "ARTWORK")
    p.line:SetPoint("TOP", pane, "TOP", 0, -62)
    if Kit:HasAtlas("UI-Character-Info-Honor-LevelBG") then
        p.line:SetAtlas("UI-Character-Info-Honor-LevelBG")
        p.line:SetSize(180, 12)
    else
        p.line:SetColorTexture(0.85, 0.66, 0.23, 0.8)
        p.line:SetSize(180, 1)
    end
    for _, fs in ipairs({ p.season, p.rank }) do
        fs:SetJustifyH("CENTER")
        fs:SetWidth(WIDTH - 20)
    end

    p.ring = Kit:Ring(pane, 150)
    p.ring:SetPoint("TOP", pane, "TOP", 0, -88)

    p.points = Kit:Text(pane, "label")
    p.points:SetPoint("TOP", pane, "TOP", 0, -258)
    p.points:SetJustifyH("CENTER")
    p.points:SetWidth(WIDTH - 20)
    p.percent = Kit:Text(pane, "grey")
    p.percent:SetPoint("TOP", pane, "TOP", 0, -276)
    p.percent:SetJustifyH("CENTER")
    p.percent:SetWidth(WIDTH - 20)

    p.gate = Kit:Inset(pane)
    p.gate:SetPoint("TOPLEFT", pane, "TOPLEFT", 12, -300)
    p.gate:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -14, -300)
    p.gate:SetHeight(80)
    p.gateIcon = p.gate:CreateTexture(nil, "ARTWORK")
    p.gateIcon:SetSize(22, 22)
    p.gateIcon:SetPoint("TOPLEFT", p.gate, "TOPLEFT", 8, -8)
    p.gateIcon:SetTexture(WARNING)
    p.gateTitle = Kit:Text(p.gate, "value")
    p.gateTitle:SetPoint("TOPLEFT", p.gate, "TOPLEFT", 36, -8)
    p.gateTitle:SetPoint("TOPRIGHT", p.gate, "TOPRIGHT", -8, -8)
    color(p.gateTitle, "orange")
    p.gateText = Kit:Text(p.gate, "grey")
    p.gateText:SetPoint("TOPLEFT", p.gate, "TOPLEFT", 36, -26)
    p.gateText:SetPoint("TOPRIGHT", p.gate, "TOPRIGHT", -8, -26)
    p.gateText:SetWordWrap(true)
    p.gateText:SetJustifyV("TOP")
    p.gate:Hide()

    -- What the next rank unlocks, as item icons (under the gate note when that shows).
    p.unlockLabel = Kit:Text(pane, "labelSmall")
    p.unlockLabel:SetJustifyH("CENTER")
    p.unlockLabel:SetWidth(WIDTH - 20)
    p.unlockIcons = {}
    for i = 1, UNLOCK_ICONS do
        p.unlockIcons[i] = Kit:ItemIcon(pane, 28)
        p.unlockIcons[i]:Hide()
    end

    p.honorLabel = Kit:Text(pane, "label")
    p.honorLabel:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 14, 56)
    p.honorLabel:SetText(L["Honor Points:"])
    p.honorValue = Kit:Text(pane, "value")
    p.honorValue:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -16, 56)
    p.honorValue:SetJustifyH("RIGHT")
    p.honorBar = Kit:Bar(pane)
    p.honorBar:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 14, 34)
    p.honorBar:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -16, 34)
    p.honorBar:SetBarColor(1, 0.82, 0.1)
    p.cap = Kit:Text(pane, "grey")
    p.cap:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 14, 14)
    return p
end

local function refresh(p)
    local Rank = HonorLog.Rank
    local info = safe(Rank.GetInfo, Rank)
    local faction = str(select(2, pcall(UnitFactionGroup, "player"))) or "Alliance"

    if info then
        p.season:SetText(info.season and info.season > 0 and string.format(L["Season %d"], info.season) or "")
        p.rank:SetText(info.rank > 0 and string.format(L["Rank %d %s"], info.rank, info.title or "") or (info.title or L["No rank yet"]))
        p.ring:SetRank(info.rank, faction)
        local capTotal = num(info.weekCapTotal) or 0
        local fraction = capTotal > 0 and (num(info.totalPoints) or 0) / capTotal or 0
        p.ring:SetProgress(fraction)
        local nextRank = math.min(info.rank + 1, info.seasonMaxRank or 14)
        p.points:SetText(string.format(L["Rank Points: %s / %s"], white(commas(info.totalPoints or 0)), white(commas(Rank:TotalForRank(nextRank)))))
        if capTotal > 0 then
            p.percent:SetText(string.format(L["%d%% of this week's cap, Rank %d"], math.floor(Kit.Clamp01(fraction) * 100), info.weekCapRank or 0))
        else
            p.percent:SetText("")
        end
        if info.gate and info.gate.blocking then
            p.gateTitle:SetText(string.format(L["Rank %d needs level %d"], info.gate.rank, info.gate.level))
            p.gateText:SetText(Rank:GateText(info.gate))
            p.gate:Show()
        else
            p.gate:Hide()
        end
    else
        p.season:SetText("")
        p.rank:SetText(L["No rank yet"])
        p.ring:SetRank(0, faction)
        p.ring:SetProgress(0)
        p.points:SetText(L["No rank yet"])
        p.percent:SetText("")
        p.gate:Hide()
    end

    -- The next rank that unlocks something, and what.
    local items, unlockRank = {}, nil
    if info then
        for n = (num(info.rank) or 0) + 1, math.min(num(info.seasonMaxRank) or 14, 14) do
            local list = safe(HonorLog.GetRankUnlocks, HonorLog, n) or {}
            if #list > 0 then
                items, unlockRank = list, n
                break
            end
        end
    end
    local shown = math.min(#items, UNLOCK_ICONS)
    if shown > 0 then
        local top = p.gate:IsShown() and -392 or -312
        p.unlockLabel:ClearAllPoints()
        p.unlockLabel:SetPoint("TOP", p.pane, "TOP", 0, top)
        p.unlockLabel:SetText(string.format(L["Rank %d unlocks"], unlockRank))
        p.unlockLabel:Show()
        local width = shown * 28 + (shown - 1) * 6
        for i = 1, UNLOCK_ICONS do
            local icon = p.unlockIcons[i]
            if i <= shown then
                icon:SetItem(items[i])
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", p.pane, "TOP", -width / 2 + (i - 1) * 34, top - 18)
                icon:Show()
            else
                icon:Hide()
            end
        end
    else
        p.unlockLabel:Hide()
        for i = 1, UNLOCK_ICONS do p.unlockIcons[i]:Hide() end
    end
    p.unlockRank, p.unlockShown = unlockRank or false, shown

    local honor = safe(HonorLog.GetHonorSummary, HonorLog)
    local current, cap = num(honor and honor.current) or 0, num(honor and honor.cap) or 0
    if cap > 0 then
        p.honorValue:SetText(string.format(L["%s / %s"], white(commas(current)), white(commas(cap))))
    else
        p.honorValue:SetText(white(commas(current)))
    end
    p.honorBar:SetValue01(cap > 0 and current / cap or 0)
    local advice = safe(HonorLog.GetHonorCapAdvice, HonorLog)
    local games = advice and num(advice.gamesToCap)
    if games then
        p.cap:SetText(string.format(L["Cap in about %d games"], games))
        p.cap:Show()
    else
        p.cap:SetText("")
        p.cap:Hide()
    end
end

-- The pane, anchored to the left edge of its parent. pane:Refresh() redraws it; pane.honorLogParts holds
-- its texts and widgets (season, rank, ring, points, percent, gate, unlock icons, honor bar, cap).
function RankPane:Create(parent)
    local parts = build(parent)
    local pane = parts.pane
    pane.honorLogParts = parts
    function pane:Refresh() refresh(parts) end
    return pane
end
