-- HonorLog Export
-- Copyable export dialog with text/CSV formats

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

    local formatDropdown = CreateFrame("Frame", "HonorLogExportFormatDropdown", frame, "UIDropDownMenuTemplate")
    formatDropdown:SetPoint("LEFT", formatLabel, "RIGHT", 0, -2)
    UIDropDownMenu_SetWidth(formatDropdown, 150)

    local currentFormat = "text"

    UIDropDownMenu_Initialize(formatDropdown, function(self, level)
        local items = {
            { text = "Text (Discord/Forums)", value = "text" },
            { text = "CSV (Spreadsheet)", value = "csv" },
        }
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

    UIDropDownMenu_SetText(formatDropdown, "Text (Discord/Forums)")
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
    frame.GetCurrentScope = function() return currentScope end

    frame:Hide()
    return frame
end

function HonorLog:ShowExportFrame(format)
    if not exportFrame then
        exportFrame = CreateExportFrame()
    end

    if format then
        local formatText = format == "csv" and "CSV (Spreadsheet)" or "Text (Discord/Forums)"
        UIDropDownMenu_SetText(exportFrame.formatDropdown, formatText)
    end

    self:UpdateExportContent(exportFrame.GetCurrentFormat())
    exportFrame:Show()
end

function HonorLog:UpdateExportContent(format)
    if not exportFrame or not exportFrame:IsShown() then return end

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

function HonorLog:GenerateTextExport(scope)
    local lines = {}
    local scopeLabel = scope == "account" and "Account-Wide" or ("Character: " .. UnitName("player"))

    table.insert(lines, "╔══════════════════════════════════════╗")
    table.insert(lines, "║          HonorLog Summary            ║")
    table.insert(lines, "║  " .. scopeLabel .. string.rep(" ", 36 - #scopeLabel) .. "║")
    table.insert(lines, "╠══════════════════════════════════════╣")

    for _, bgType in ipairs(HonorLog.BG_ORDER) do
        local stats = self:GetBGStats(bgType, scope)
        local derived = self:GetDerivedStats(bgType, scope)

        if stats.played > 0 then
            table.insert(lines, "║ " .. bgType .. ":")
            table.insert(lines, string.format("║   Games: %d (%d-%d) %.1f%% WR",
                stats.played, stats.wins, stats.losses, derived.winrate))
            table.insert(lines, string.format("║   Avg Duration: %s", self:FormatDuration(derived.avgDuration)))
            table.insert(lines, string.format("║   Honor: %s | Marks: %d",
                self:FormatNumber(stats.honorLifetime), stats.marksLifetime))
            table.insert(lines, "║")
        end
    end

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
    table.insert(lines, "")
    table.insert(lines, "Generated by HonorLog addon")
    table.insert(lines, "Date: " .. date("%Y-%m-%d %H:%M"))

    return table.concat(lines, "\n")
end

function HonorLog:GenerateCSVExport(scope)
    local lines = {}

    -- Header
    table.insert(lines, "Battleground\tPlayed\tWins\tLosses\tWinrate\tAvg Duration (s)\tHonor\tMarks")

    -- BG data
    for _, bgType in ipairs(HonorLog.BG_ORDER) do
        local stats = self:GetBGStats(bgType, scope)
        local derived = self:GetDerivedStats(bgType, scope)

        table.insert(lines, string.format("%s\t%d\t%d\t%d\t%.2f\t%d\t%d\t%d",
            bgType,
            stats.played,
            stats.wins,
            stats.losses,
            derived.winrate,
            math.floor(derived.avgDuration),
            stats.honorLifetime,
            stats.marksLifetime
        ))
    end

    -- Empty line before history
    table.insert(lines, "")
    table.insert(lines, "--- Recent Games History ---")
    table.insert(lines, "BG\tResult\tDuration (s)\tHonor\tMarks\tTimestamp")

    -- History
    local history = self:GetHistory(scope, 50)
    for _, entry in ipairs(history) do
        table.insert(lines, string.format("%s\t%s\t%d\t%d\t%d\t%s",
            entry.bgType,
            entry.win and "Win" or "Loss",
            entry.duration,
            entry.honor,
            entry.marks,
            date("%Y-%m-%d %H:%M", entry.timestamp)
        ))
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
