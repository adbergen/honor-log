-- HonorLog Core
-- Event handling, BG detection, and main addon logic

local ADDON_NAME, HonorLog = ...

-- BG Map IDs for TBC Classic
local BG_MAP_IDS = {
    [30] = "AV",   -- Alterac Valley
    [529] = "AB",  -- Arathi Basin
    [489] = "WSG", -- Warsong Gulch
    [566] = "EotS", -- Eye of the Storm
}

-- BG Instance Names (backup detection)
local BG_INSTANCE_NAMES = {
    ["Alterac Valley"] = "AV",
    ["Arathi Basin"] = "AB",
    ["Warsong Gulch"] = "WSG",
    ["Eye of the Storm"] = "EotS",
}

-- State tracking
local currentBG = nil
local bgStartTime = nil
local bgStartHonor = nil
local isInBG = false
local bgEnded = false

-- Create main frame for events
local eventFrame = CreateFrame("Frame", "HonorLogEventFrame")
HonorLog.eventFrame = eventFrame

-- Event handler
local function OnEvent(self, event, ...)
    if HonorLog[event] then
        HonorLog[event](HonorLog, ...)
    end
end

eventFrame:SetScript("OnEvent", OnEvent)

-- Register events
local events = {
    "ADDON_LOADED",
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "UPDATE_BATTLEFIELD_STATUS",
    "UPDATE_BATTLEFIELD_SCORE",
    "CHAT_MSG_BG_SYSTEM_ALLIANCE",
    "CHAT_MSG_BG_SYSTEM_HORDE",
    "CHAT_MSG_BG_SYSTEM_NEUTRAL",
    "HONOR_XP_UPDATE",
    "PLAYER_LOGOUT",
}

for _, event in ipairs(events) do
    eventFrame:RegisterEvent(event)
end

-- Addon loaded
function HonorLog:ADDON_LOADED(addon)
    if addon ~= ADDON_NAME then return end

    -- Initialize database
    self:InitializeDB()

    -- Initialize UI
    self:InitializeMainFrame()
    self:InitializeOptions()
    self:InitializeLDB()

    -- Register slash commands
    self:RegisterSlashCommands()

    -- Unregister this event
    eventFrame:UnregisterEvent("ADDON_LOADED")

    print("|cff00ff00HonorLog|r loaded. Type |cffffffff/bg|r for options.")
end

-- Detect current battleground
function HonorLog:DetectBattleground()
    -- Method 1: Check instance map ID
    local _, instanceType, _, _, _, _, _, mapID = GetInstanceInfo()
    if instanceType == "pvp" and mapID and BG_MAP_IDS[mapID] then
        return BG_MAP_IDS[mapID]
    end

    -- Method 2: Check zone name
    local zoneName = GetRealZoneText()
    if zoneName and BG_INSTANCE_NAMES[zoneName] then
        return BG_INSTANCE_NAMES[zoneName]
    end

    -- Method 3: Check battlefield status
    for i = 1, GetMaxBattlefieldID() do
        local status, mapName = GetBattlefieldStatus(i)
        if status == "active" and mapName then
            for name, bgType in pairs(BG_INSTANCE_NAMES) do
                if mapName:find(name) then
                    return bgType
                end
            end
        end
    end

    return nil
end

-- Player entering world (includes BG zone-ins)
function HonorLog:PLAYER_ENTERING_WORLD()
    self:CheckBattlegroundStatus()
end

-- Zone changed
function HonorLog:ZONE_CHANGED_NEW_AREA()
    self:CheckBattlegroundStatus()
end

-- Battlefield status update
function HonorLog:UPDATE_BATTLEFIELD_STATUS()
    self:CheckBattlegroundStatus()
end

-- Check and update BG status
function HonorLog:CheckBattlegroundStatus()
    local bg = self:DetectBattleground()

    if bg and not isInBG then
        -- Entering a battleground
        self:OnBattlegroundEnter(bg)
    elseif not bg and isInBG then
        -- Leaving a battleground
        self:OnBattlegroundLeave()
    elseif bg and isInBG and bg ~= currentBG then
        -- Changed battlegrounds (shouldn't happen normally)
        self:OnBattlegroundLeave()
        self:OnBattlegroundEnter(bg)
    end
end

-- Entering battleground
function HonorLog:OnBattlegroundEnter(bgType)
    isInBG = true
    currentBG = bgType
    bgStartTime = GetTime()
    bgStartHonor = GetHonorCurrency and GetHonorCurrency() or UnitHonor("player") or 0
    bgEnded = false

    -- Update UI
    if self.UpdateMainFrame then
        self:UpdateMainFrame()
    end

    -- Debug
    -- print("|cff00ff00HonorLog|r Entered", bgType)
end

-- Leaving battleground
function HonorLog:OnBattlegroundLeave()
    if not isInBG or bgEnded then
        isInBG = false
        currentBG = nil
        bgStartTime = nil
        bgStartHonor = nil
        return
    end

    -- BG ended without proper detection - mark as loss
    if currentBG and bgStartTime then
        local duration = GetTime() - bgStartTime
        local honorGained = 0

        local currentHonor = GetHonorCurrency and GetHonorCurrency() or UnitHonor("player") or 0
        if bgStartHonor then
            honorGained = math.max(0, currentHonor - bgStartHonor)
        end

        -- We don't have winner info, so we'll rely on the BG message detection
        -- This is a fallback for edge cases
    end

    isInBG = false
    currentBG = nil
    bgStartTime = nil
    bgStartHonor = nil

    -- Update UI
    if self.UpdateMainFrame then
        self:UpdateMainFrame()
    end
end

-- BG end message patterns
local WIN_PATTERNS = {
    ["The Alliance wins!"] = "Alliance",
    ["The Horde wins!"] = "Horde",
    ["Alliance wins!"] = "Alliance",
    ["Horde wins!"] = "Horde",
    ["The Alliance has won the battle for Warsong Gulch!"] = "Alliance",
    ["The Horde has won the battle for Warsong Gulch!"] = "Horde",
    ["The Alliance has taken the flag!"] = nil, -- Capture, not win
    ["The battle for Alterac Valley has begun!"] = nil, -- Start message
}

-- Handle BG system messages
local function HandleBGMessage(self, msg)
    if not isInBG or not currentBG or bgEnded then return end

    -- Check for win messages
    local winner = nil
    for pattern, faction in pairs(WIN_PATTERNS) do
        if msg:find(pattern) then
            winner = faction
            break
        end
    end

    -- Also check for "wins" in the message
    if not winner then
        if msg:find("Alliance") and msg:find("win") then
            winner = "Alliance"
        elseif msg:find("Horde") and msg:find("win") then
            winner = "Horde"
        end
    end

    if winner then
        bgEnded = true
        self:OnBattlegroundEnd(winner)
    end
end

function HonorLog:CHAT_MSG_BG_SYSTEM_ALLIANCE(msg)
    HandleBGMessage(self, msg)
end

function HonorLog:CHAT_MSG_BG_SYSTEM_HORDE(msg)
    HandleBGMessage(self, msg)
end

function HonorLog:CHAT_MSG_BG_SYSTEM_NEUTRAL(msg)
    HandleBGMessage(self, msg)
end

-- Battleground ended
function HonorLog:OnBattlegroundEnd(winner)
    if not currentBG or not bgStartTime then return end

    local playerFaction = UnitFactionGroup("player")
    local won = (winner == playerFaction)

    local duration = math.floor(GetTime() - bgStartTime)

    -- Calculate honor gained
    local honorGained = 0
    local currentHonor = GetHonorCurrency and GetHonorCurrency() or UnitHonor("player") or 0
    if bgStartHonor then
        honorGained = math.max(0, currentHonor - bgStartHonor)
    end

    -- Marks gained (3 for win, 1 for loss in most BGs)
    local marksGained = won and 3 or 1

    -- AV gives bonus marks
    if currentBG == "AV" then
        marksGained = won and 3 or 1
    end

    -- Record the game
    self:RecordGame(currentBG, won, duration, honorGained, marksGained)

    -- Print result
    local resultColor = won and "|cff00ff00" or "|cffff0000"
    local result = won and "Victory" or "Defeat"
    print(string.format("%s[HonorLog]|r %s%s|r in %s - %s, +%d honor, +%d marks",
        "|cff00ff00", resultColor, result, currentBG,
        self:FormatDuration(duration), honorGained, marksGained))

    -- Update UI
    if self.UpdateMainFrame then
        self:UpdateMainFrame()
    end
end

-- Battlefield score update (alternative detection method)
function HonorLog:UPDATE_BATTLEFIELD_SCORE()
    if not isInBG or not currentBG or bgEnded then return end

    -- Check if the BG has ended by looking at the scoreboard
    local winner = GetBattlefieldWinner()
    if winner then
        bgEnded = true
        local factions = { [0] = "Horde", [1] = "Alliance" }
        self:OnBattlegroundEnd(factions[winner])
    end
end

-- Honor update event
function HonorLog:HONOR_XP_UPDATE()
    -- Could be used for more accurate honor tracking
    -- Currently handled in OnBattlegroundEnd
end

-- Slash commands
function HonorLog:RegisterSlashCommands()
    SLASH_HONORLOG1 = "/bg"
    SLASH_HONORLOG2 = "/honorlog"

    SlashCmdList["HONORLOG"] = function(msg)
        self:HandleSlashCommand(msg)
    end
end

function HonorLog:HandleSlashCommand(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")
    cmd = cmd:lower()

    if cmd == "" or cmd == "toggle" then
        self:ToggleMainFrame()
    elseif cmd == "stats" then
        self:PrintStats(arg)
    elseif cmd == "reset" then
        if arg:lower() == "session" then
            self:ResetSession()
            print("|cff00ff00HonorLog|r Session stats reset.")
        else
            print("|cff00ff00HonorLog|r Usage: /bg reset session")
        end
    elseif cmd == "export" then
        self:ShowExportFrame(arg)
    elseif cmd == "config" or cmd == "options" then
        self:OpenOptions()
    elseif cmd == "help" then
        self:PrintHelp()
    elseif cmd == "view" then
        if arg == "character" or arg == "char" then
            self:SetSetting("viewMode", "character")
            print("|cff00ff00HonorLog|r Now showing character stats.")
        elseif arg == "account" then
            self:SetSetting("viewMode", "account")
            print("|cff00ff00HonorLog|r Now showing account-wide stats.")
        else
            print("|cff00ff00HonorLog|r Usage: /bg view [character|account]")
        end
        if self.UpdateMainFrame then
            self:UpdateMainFrame()
        end
    else
        print("|cff00ff00HonorLog|r Unknown command. Type /bg help for options.")
    end
end

function HonorLog:PrintHelp()
    print("|cff00ff00HonorLog Commands:|r")
    print("  |cffffffff/bg|r - Toggle stats frame")
    print("  |cffffffff/bg stats [bg]|r - Print stats summary")
    print("  |cffffffff/bg reset session|r - Reset session stats")
    print("  |cffffffff/bg export [text|csv]|r - Export stats")
    print("  |cffffffff/bg view [character|account]|r - Switch view mode")
    print("  |cffffffff/bg config|r - Open options")
    print("  |cffffffff/bg help|r - Show this help")
end

function HonorLog:PrintStats(bgFilter)
    local scope = self.db.settings.viewMode
    local scopeLabel = scope == "account" and "Account" or "Character"

    print("|cff00ff00=== HonorLog Summary (" .. scopeLabel .. ") ===|r")

    local bgTypes = {"AV", "AB", "WSG", "EotS"}
    if bgFilter and bgFilter ~= "" then
        bgFilter = bgFilter:upper()
        if self.db.char.battlegrounds[bgFilter] then
            bgTypes = {bgFilter}
        end
    end

    for _, bgType in ipairs(bgTypes) do
        local stats = self:GetBGStats(bgType, scope)
        local derived = self:GetDerivedStats(bgType, scope)
        local session = self:GetSessionStats(bgType)

        if stats.played > 0 or session.played > 0 then
            print(string.format("|cffffd700%s:|r %d played (%d-%d) %.1f%% WR, Avg %s",
                bgType, stats.played, stats.wins, stats.losses,
                derived.winrate, self:FormatDuration(derived.avgDuration)))
            print(string.format("  Honor: %d lifetime | Marks: %d lifetime",
                stats.honorLifetime, stats.marksLifetime))
            if session.played > 0 then
                print(string.format("  Session: %d-%d (%.1f%%), +%d honor, +%d marks",
                    session.wins, session.losses, derived.sessionWinrate,
                    session.honor, session.marks))
            end
        end
    end

    local totalSession = self:GetTotalSessionStats()
    if totalSession.played > 0 then
        print(string.format("|cff00ff00Session Total:|r %d games, %d-%d (%.1f%%), +%d honor, +%d marks",
            totalSession.played, totalSession.wins, totalSession.losses,
            totalSession.winrate, totalSession.honor, totalSession.marks))
    end
end

-- Accessor for current BG state
function HonorLog:GetCurrentBG()
    return currentBG
end

function HonorLog:IsInBG()
    return isInBG
end

function HonorLog:GetBGStartTime()
    return bgStartTime
end

-- Callback for data updates
function HonorLog:OnDataUpdated()
    if self.UpdateMainFrame then
        self:UpdateMainFrame()
    end
    if self.UpdateLDB then
        self:UpdateLDB()
    end
end

-- LDB (LibDataBroker) Integration
function HonorLog:InitializeLDB()
    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not LDB then return end

    self.ldb = LDB:NewDataObject("HonorLog", {
        type = "data source",
        icon = "Interface\\Icons\\Achievement_BG_KillFlagCarriers_grabFlag_capit",
        text = "HonorLog",
        label = "HonorLog",

        OnClick = function(frame, button)
            if button == "LeftButton" then
                if IsShiftKeyDown() then
                    self:PrintStats()
                else
                    self:ToggleMainFrame()
                end
            elseif button == "RightButton" then
                self:ShowContextMenu()
            elseif button == "MiddleButton" then
                self:ShowExportFrame()
            end
        end,

        OnTooltipShow = function(tooltip)
            HonorLog:BuildLDBTooltip(tooltip)
        end,
    })

    self:UpdateLDB()
end

function HonorLog:UpdateLDB()
    if not self.ldb or not self.db.settings.ldbEnabled then return end

    local currentBG = self:GetCurrentBG()
    local session = self:GetTotalSessionStats()

    local text
    if currentBG then
        local sessionBG = self:GetSessionStats(currentBG)
        if sessionBG.played > 0 then
            local wr = sessionBG.played > 0 and (sessionBG.wins / sessionBG.played * 100) or 0
            text = string.format("|cffffd700%s|r %d-%d (%.0f%%)",
                currentBG, sessionBG.wins, sessionBG.losses, wr)
        else
            text = string.format("|cffffd700%s|r In Progress", currentBG)
        end
    elseif session.played > 0 then
        text = string.format("%d-%d (%.0f%%) +%dH",
            session.wins, session.losses, session.winrate, session.honor)
    else
        text = "No games"
    end

    self.ldb.text = text
end

function HonorLog:BuildLDBTooltip(tooltip)
    tooltip:AddLine("HonorLog", 0, 1, 0)
    tooltip:AddLine(" ")

    local scope = self.db.settings.viewMode
    local scopeLabel = scope == "account" and "Account-Wide" or "Character"
    tooltip:AddLine(scopeLabel .. " Stats:", 1, 0.82, 0)

    local bgTypes = {"AV", "AB", "WSG", "EotS"}
    for _, bgType in ipairs(bgTypes) do
        local stats = self:GetBGStats(bgType, scope)
        if stats.played > 0 then
            local derived = self:GetDerivedStats(bgType, scope)
            local color = derived.winrate >= 50 and "|cff00ff00" or "|cffff0000"
            tooltip:AddDoubleLine(
                bgType,
                string.format("%s%d-%d (%.0f%%)|r", color, stats.wins, stats.losses, derived.winrate),
                1, 1, 1,
                1, 1, 1
            )
        end
    end

    -- Session summary
    local session = self:GetTotalSessionStats()
    if session.played > 0 then
        tooltip:AddLine(" ")
        tooltip:AddLine("Session:", 1, 0.82, 0)
        local color = session.winrate >= 50 and "|cff00ff00" or "|cffff0000"
        tooltip:AddDoubleLine(
            "Games",
            string.format("%s%d-%d (%.0f%%)|r", color, session.wins, session.losses, session.winrate),
            1, 1, 1,
            1, 1, 1
        )
        tooltip:AddDoubleLine("Honor", string.format("+%d", session.honor), 1, 1, 1, 1, 0.82, 0)
        tooltip:AddDoubleLine("Marks", string.format("+%d", session.marks), 1, 1, 1, 0.5, 0.5, 1)
    end

    -- Current BG
    local currentBG = self:GetCurrentBG()
    if currentBG then
        tooltip:AddLine(" ")
        tooltip:AddLine("Currently in: |cffffd700" .. currentBG .. "|r", 0, 1, 0)
        local startTime = self:GetBGStartTime()
        if startTime then
            local duration = math.floor(GetTime() - startTime)
            tooltip:AddLine("Duration: " .. self:FormatDuration(duration), 0.7, 0.7, 0.7)
        end
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("|cff888888Left-click: Toggle frame|r")
    tooltip:AddLine("|cff888888Shift+Left-click: Print stats|r")
    tooltip:AddLine("|cff888888Right-click: Menu|r")
    tooltip:AddLine("|cff888888Middle-click: Export|r")
end
