-- HonorLog Export
-- Copyable export dialog with text/CSV formats. The dialog opens on the format named in
-- /honorlog export [text|csv], else on the Export Format setting (UI/Options.lua).

local ADDON_NAME, HonorLog = ...

local exportFrame = nil

local function CreateExportFrame()
    local frame = CreateFrame("Frame", "HonorLogExportFrame", UIParent, "BackdropTemplate")
    frame:SetSize(450, 350)
    frame:SetPoint("CENTER", 0, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")

    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 26,
        insets = { left = 9, right = 9, top = 9, bottom = 9 },
    })
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("HonorLog Export")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Format dropdown
    local formatLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    formatLabel:SetPoint("TOPLEFT", 20, -45)
    formatLabel:SetText("Format:")

    -- Not the name UI/Options.lua gives its Export Format setting: one frame name, one frame.
    local formatDropdown = CreateFrame("Frame", "HonorLogExportDialogFormatDropdown", frame, "UIDropDownMenuTemplate")
    formatDropdown:SetPoint("LEFT", formatLabel, "RIGHT", 0, -2)
    UIDropDownMenu_SetWidth(formatDropdown, 150)

    local FORMATS = {
        { text = "Text (Discord/Forums)", value = "text" },
        { text = "CSV (Spreadsheet)", value = "csv" },
    }
    local function FormatText(value)
        for _, item in ipairs(FORMATS) do
            if item.value == value then return item.text end
        end
        return FORMATS[1].text
    end
    local currentFormat = HonorLog:GetExportFormat()

    UIDropDownMenu_Initialize(formatDropdown, function(self, level)
        local items = FORMATS
        for _, item in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.value = item.value
            info.checked = (currentFormat == item.value)
            info.func = function()
                currentFormat = item.value
                UIDropDownMenu_SetText(formatDropdown, item.text)
                HonorLog:UpdateExportContent(currentFormat)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    UIDropDownMenu_SetText(formatDropdown, FormatText(currentFormat))
    frame.formatDropdown = formatDropdown

    -- Scope dropdown
    local scopeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scopeLabel:SetPoint("LEFT", formatDropdown, "RIGHT", 20, 2)
    scopeLabel:SetText("Scope:")

    local scopeDropdown = CreateFrame("Frame", "HonorLogExportScopeDropdown", frame, "UIDropDownMenuTemplate")
    scopeDropdown:SetPoint("LEFT", scopeLabel, "RIGHT", 0, -2)
    UIDropDownMenu_SetWidth(scopeDropdown, 100)

    local currentScope = HonorLog.db.settings.viewMode

    UIDropDownMenu_Initialize(scopeDropdown, function(self, level)
        local items = {
            { text = "Character", value = "character" },
            { text = "Account", value = "account" },
        }
        for _, item in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.value = item.value
            info.checked = (currentScope == item.value)
            info.func = function()
                currentScope = item.value
                UIDropDownMenu_SetText(scopeDropdown, item.text)
                HonorLog:UpdateExportContent(currentFormat)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    UIDropDownMenu_SetText(scopeDropdown, currentScope == "account" and "Account" or "Character")
    frame.scopeDropdown = scopeDropdown

    -- ScrollFrame for content
    local scrollFrame = CreateFrame("ScrollFrame", "HonorLogExportScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -80)
    scrollFrame:SetPoint("BOTTOMRIGHT", -40, 50)

    local editBox = CreateFrame("EditBox", "HonorLogExportEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetWidth(scrollFrame:GetWidth() - 10)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    scrollFrame:SetScrollChild(editBox)
    frame.editBox = editBox

    -- Instructions
    local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instructions:SetPoint("BOTTOMLEFT", 20, 25)
    instructions:SetText("Press Ctrl+A to select all, then Ctrl+C to copy")
    instructions:SetTextColor(0.7, 0.7, 0.7, 1)

    -- Copy button (highlights all text)
    local copyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    copyBtn:SetSize(100, 25)
    copyBtn:SetPoint("BOTTOMRIGHT", -20, 15)
    copyBtn:SetText("Select All")
    copyBtn:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)

    -- Dragging
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- Store references for scope
    frame.GetCurrentFormat = function() return currentFormat end
    frame.SetFormat = function(self, value)
        currentFormat = value == "csv" and "csv" or "text"
        UIDropDownMenu_SetText(formatDropdown, FormatText(currentFormat))
    end
    frame.GetCurrentScope = function() return currentScope end

    frame:Hide()
    return frame
end

-- "text" or "csv": the Export Format setting, text when it holds anything else.
function HonorLog:GetExportFormat()
    local value = self.db and self.db.settings and self.db.settings.exportFormat
    return value == "csv" and "csv" or "text"
end

-- format is the /honorlog export argument: "csv", "text", or anything else for the setting.
function HonorLog:ShowExportFrame(format)
    if not exportFrame then
        exportFrame = CreateExportFrame()
    end

    format = type(format) == "string" and format:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    if format == "csv" or format == "text" then
        exportFrame:SetFormat(format)
    else
        exportFrame:SetFormat(self:GetExportFormat())
    end

    exportFrame:Show()
    self:UpdateExportContent(exportFrame.GetCurrentFormat())
end

function HonorLog:UpdateExportContent(format)
    if not exportFrame then return end

    format = format or exportFrame.GetCurrentFormat() or "text"
    local scope = exportFrame.GetCurrentScope() or self.db.settings.viewMode

    local content
    if format == "csv" then
        content = self:GenerateCSVExport(scope)
    else
        content = self:GenerateTextExport(scope)
    end

    exportFrame.editBox:SetText(content)
    exportFrame.editBox:SetCursorPosition(0)
end

-- Whole numbers for %d: Lua 5.3+ refuses a float with a fraction, and damage can arrive as a float.
local function int(x) return math.floor(tonumber(x) or 0) end

local RESULT_NAMES = { win = "Win", loss = "Loss", draw = "Draw", left = "Left" }

-- A row from before 2.0 has no `result` field; Eye of the Storm only exists in those. Both are TBC history.
local function IsTBCRow(entry)
    return entry.result == nil or entry.bgType == "EotS"
end

local function ResultName(entry)
    return RESULT_NAMES[entry.result or (entry.win and "win" or "loss")] or "Loss"
end

-- Battleground name for a row; TBC-era rows say so once.
local function RowBGName(self, entry)
    local name = self:GetBGDisplayName(entry.bgType)
    if IsTBCRow(entry) and not name:find("(TBC)", 1, true) then name = name .. " (TBC)" end
    return name
end

-- Objectives as one compact cell: "Flag Captures 2; Bases Assaulted 1". Zeros are left out.
local function ObjectivesText(objectives, separator)
    if type(objectives) ~= "table" then return "" end
    local labels = {}
    for label, value in pairs(objectives) do
        if type(value) == "number" and value ~= 0 then labels[#labels + 1] = label end
    end
    table.sort(labels)
    local parts = {}
    for _, label in ipairs(labels) do
        parts[#parts + 1] = string.format("%s %d", (tostring(label):gsub("[\t\r\n]", " ")), int(objectives[label]))
    end
    return table.concat(parts, separator or "; ")
end

local function Stamp(entry) return date("%Y-%m-%d %H:%M", entry.timestamp or 0) end

local function SortedOpponents(self)
    local list = {}
    for name, e in pairs(self.db.char.opponents or {}) do
        list[#list + 1] = { name = name, class = e.class or "", kills = e.kills or 0, deaths = e.deaths or 0, lastSeen = e.lastSeen or 0 }
    end
    table.sort(list, function(a, b)
        local ta, tb = a.kills + a.deaths, b.kills + b.deaths
        if ta ~= tb then return ta > tb end
        if a.lastSeen ~= b.lastSeen then return a.lastSeen > b.lastSeen end
        return a.name < b.name
    end)
    return list
end

local function GameLine(self, entry)
    local parts = {
        Stamp(entry), RowBGName(self, entry), ResultName(entry),
        self:FormatDuration(entry.duration),
    }
    if entry.kb or entry.hk or entry.deaths then
        parts[#parts + 1] = string.format("K %d HK %d D %d", int(entry.kb), int(entry.hk), int(entry.deaths))
    end
    if entry.damage then parts[#parts + 1] = "dmg " .. self:FormatNumber(int(entry.damage)) end
    if entry.healing then parts[#parts + 1] = "heal " .. self:FormatNumber(int(entry.healing)) end
    local objectives = ObjectivesText(entry.objectives)
    if objectives ~= "" then parts[#parts + 1] = "obj: " .. objectives end
    parts[#parts + 1] = string.format("honor %d, marks %d", int(entry.honor), int(entry.marks))
    if entry.rankPoints then parts[#parts + 1] = string.format("rank %+d", int(entry.rankPoints)) end
    if entry.joinedInProgress then parts[#parts + 1] = "joined in progress" end
    return table.concat(parts, " | ")
end

function HonorLog:GenerateTextExport(scope)
    local lines = {}
    local scopeLabel = scope == "account" and "Account-Wide" or ("Character: " .. UnitName("player"))

    table.insert(lines, "╔══════════════════════════════════════╗")
    table.insert(lines, "║          HonorLog Summary            ║")
    table.insert(lines, "║  " .. scopeLabel .. string.rep(" ", math.max(0, 36 - #scopeLabel)) .. "║")
    table.insert(lines, "╠══════════════════════════════════════╣")

    for _, bgType in ipairs(HonorLog.BG_ORDER) do
        local stats = self:GetBGStats(bgType, scope)
        local derived = self:GetDerivedStats(bgType, scope)

        if stats.played > 0 then
            table.insert(lines, "║ " .. self:GetBGDisplayName(bgType) .. ":")
            table.insert(lines, string.format("║   Games: %d (%d-%d) %.1f%% WR",
                stats.played, stats.wins, stats.losses, derived.winrate))
            if (stats.draws or 0) > 0 or (stats.left or 0) > 0 then
                table.insert(lines, string.format("║   Draws: %d | Left early: %d", stats.draws or 0, stats.left or 0))
            end
            table.insert(lines, string.format("║   Avg Duration: %s", self:FormatDuration(derived.avgDuration)))
            table.insert(lines, string.format("║   Honor: %s | Marks: %d",
                self:FormatNumber(stats.honorLifetime), stats.marksLifetime))
            table.insert(lines, "║")
        end
    end

    -- World PvP
    local world = self:GetWorldPvPStats(scope)
    table.insert(lines, "╠══════════════════════════════════════╣")
    table.insert(lines, "║ WORLD PVP:")
    table.insert(lines, string.format("║   Kills: %d (killing blows %d) | Deaths: %d",
        world.kills or 0, world.killingBlows or 0, world.deaths or 0))
    local kill, award = world.honorKill or 0, world.honorAward or 0
    table.insert(lines, string.format("║   Honor: %s (kills %s, awards %s, other %s)",
        self:FormatNumber(world.honor or 0), self:FormatNumber(kill), self:FormatNumber(award),
        self:FormatNumber(math.max(0, (world.honor or 0) - kill - award))))

    -- Session stats
    local session = self:GetTotalSessionStats()
    if session.played > 0 then
        table.insert(lines, "╠══════════════════════════════════════╣")
        table.insert(lines, "║ TODAY:")
        table.insert(lines, string.format("║   Games: %d (%d-%d) %.1f%% WR",
            session.played, session.wins, session.losses, session.winrate))
        table.insert(lines, string.format("║   Honor: +%s | Marks: +%d",
            self:FormatNumber(session.honor), session.marks))
    end

    table.insert(lines, "╚══════════════════════════════════════╝")

    -- Every stored game
    local history = self:GetHistory(scope, 500)
    if #history > 0 then
        table.insert(lines, "")
        table.insert(lines, "GAMES (newest first)")
        for _, entry in ipairs(history) do
            table.insert(lines, GameLine(self, entry))
        end
    end

    -- Opponents are kept per character, whatever the scope
    local opponents = SortedOpponents(self)
    if #opponents > 0 then
        table.insert(lines, "")
        table.insert(lines, "OPPONENTS (this character)")
        for _, o in ipairs(opponents) do
            table.insert(lines, string.format("%s%s | kills %d, deaths %d | last seen %s",
                o.name, o.class ~= "" and (" (" .. o.class .. ")") or "", o.kills, o.deaths,
                o.lastSeen > 0 and date("%Y-%m-%d %H:%M", o.lastSeen) or "never"))
        end
    end

    table.insert(lines, "")
    table.insert(lines, "Generated by HonorLog addon")
    table.insert(lines, "Date: " .. date("%Y-%m-%d %H:%M"))

    return table.concat(lines, "\n")
end

-- One CSV field: wrapped in double quotes when it holds a comma, a quote or a line break, with
-- inner quotes doubled.
local function csvField(value)
    local text = value == nil and "" or tostring(value)
    if text:find('[",\r\n]') then text = '"' .. text:gsub('"', '""') .. '"' end
    return text
end

local function csvRow(...)
    local fields = { ... }
    local n = select("#", ...)
    for i = 1, n do fields[i] = csvField(fields[i]) end
    return table.concat(fields, ",", 1, n)
end

function HonorLog:GenerateCSVExport(scope)
    local lines = {}

    -- Header
    table.insert(lines, csvRow("Battleground", "Played", "Wins", "Losses", "Draws", "Left", "Winrate", "Avg Duration (s)", "Honor", "Marks"))

    -- BG data
    for _, bgType in ipairs(HonorLog.BG_ORDER) do
        local stats = self:GetBGStats(bgType, scope)
        local derived = self:GetDerivedStats(bgType, scope)

        table.insert(lines, csvRow(
            self:GetBGDisplayName(bgType),
            int(stats.played),
            int(stats.wins),
            int(stats.losses),
            int(stats.draws),
            int(stats.left),
            string.format("%.2f", derived.winrate),
            math.floor(derived.avgDuration),
            int(stats.honorLifetime),
            int(stats.marksLifetime)
        ))
    end

    -- World PvP
    local world = self:GetWorldPvPStats(scope)
    table.insert(lines, "")
    table.insert(lines, "--- World PvP ---")
    table.insert(lines, csvRow("Kills", "Deaths", "Killing Blows", "Unknown Kills", "Honor", "Honor (kills)", "Honor (awards)", "Honor (other)"))
    local kill, award = world.honorKill or 0, world.honorAward or 0
    table.insert(lines, csvRow(
        int(world.kills), int(world.deaths), int(world.killingBlows), int(world.unknownKills),
        int(world.honor), int(kill), int(award), int(math.max(0, (world.honor or 0) - kill - award))))

    -- Every stored game
    table.insert(lines, "")
    table.insert(lines, "--- Games History ---")
    table.insert(lines, csvRow("Date", "Battleground", "Result", "Joined In Progress", "Duration (s)", "K", "HK", "D", "Damage", "Healing", "Objectives", "Honor", "Marks", "Rank Points"))
    local history = self:GetHistory(scope, 500)
    for _, entry in ipairs(history) do
        table.insert(lines, csvRow(
            Stamp(entry),
            RowBGName(self, entry),
            ResultName(entry),
            entry.joinedInProgress and "yes" or "no",
            int(entry.duration),
            entry.kb ~= nil and int(entry.kb) or "",
            entry.hk ~= nil and int(entry.hk) or "",
            entry.deaths ~= nil and int(entry.deaths) or "",
            entry.damage ~= nil and int(entry.damage) or "",
            entry.healing ~= nil and int(entry.healing) or "",
            ObjectivesText(entry.objectives),
            int(entry.honor),
            int(entry.marks),
            entry.rankPoints ~= nil and int(entry.rankPoints) or ""))
    end

    -- Opponents are kept per character, whatever the scope
    table.insert(lines, "")
    table.insert(lines, "--- Opponents (this character) ---")
    table.insert(lines, csvRow("Name", "Class", "Kills", "Deaths", "Last Seen"))
    for _, o in ipairs(SortedOpponents(self)) do
        table.insert(lines, csvRow(o.name, o.class, o.kills, o.deaths,
            o.lastSeen > 0 and date("%Y-%m-%d %H:%M", o.lastSeen) or ""))
    end

    return table.concat(lines, "\n")
end

-- Utility for formatting large numbers
function HonorLog:FormatNumber(num)
    if num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fK", num / 1000)
    else
        return tostring(num)
    end
end
