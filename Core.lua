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
local bgHonorAccumulated = 0  -- Track honor gained during BG via events
local lastHonorValue = nil    -- For tracking honor changes
local isInBG = false
local bgEnded = false
local debugMode = false

-- Backup state for when we leave before score update arrives
local lastBG = nil
local lastBGStartTime = nil
local lastBGStartHonor = nil
local lastBGLeaveTime = nil

-- Create main frame for events
local eventFrame = CreateFrame("Frame", "HonorLogEventFrame")
HonorLog.eventFrame = eventFrame

-- Safe initialization wrapper with error boundary
local function SafeInit(name, func)
    local success, err = pcall(func)
    if not success then
        print("|cffff0000[HonorLog ERROR]|r Failed to initialize " .. name .. ": " .. tostring(err))
        return false
    end
    return true
end

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
    "CHAT_MSG_RAID_BOSS_EMOTE",
    "CHAT_MSG_MONSTER_YELL",
    "HONOR_XP_UPDATE",
    "CHAT_MSG_COMBAT_HONOR_GAIN", -- TBC Classic honor kills
    "CHAT_MSG_SYSTEM", -- For "You receive currency: [Honor Points] xN" messages
    "PLAYER_LOGOUT",
    "PLAYER_DEAD",
    "BATTLEGROUND_POINTS_UPDATE",
}

for _, event in ipairs(events) do
    eventFrame:RegisterEvent(event)
end

-- Save BG state to persist across /reload
local function SaveBGState()
    if HonorLog.db and HonorLog.db.char then
        HonorLog.db.char.bgState = {
            currentBG = currentBG,
            bgStartTime = bgStartTime,
            bgStartHonor = bgStartHonor,
            bgHonorAccumulated = bgHonorAccumulated,
            isInBG = isInBG,
        }
    end
end

-- Restore BG state after /reload (called from InitializeDB when reload detected)
function HonorLog:RestoreBGState()
    local state = self.db.char.bgState
    if state and state.isInBG then
        currentBG = state.currentBG
        bgStartTime = state.bgStartTime
        bgStartHonor = state.bgStartHonor
        bgHonorAccumulated = state.bgHonorAccumulated or 0
        isInBG = state.isInBG
        print("|cff00ff00[HonorLog]|r Restored BG state: " .. tostring(currentBG) .. ", honor: " .. tostring(bgHonorAccumulated))
    end
end

-- Addon loaded
function HonorLog:ADDON_LOADED(addon)
    if addon ~= ADDON_NAME then return end

    -- Initialize database (this also detects reload vs fresh login)
    self:InitializeDB()

    -- Restore BG state if this is a reload and we were in a BG
    if self.isReload and self.db.char.bgState and self.db.char.bgState.isInBG then
        self:RestoreBGState()
    end

    -- Initialize UI with error boundaries
    local uiOK = SafeInit("MainFrame", function() self:InitializeMainFrame() end)
    if uiOK then
        SafeInit("GoalsUI", function() self:InitializeGoalsUI() end)
    end
    SafeInit("Options", function() self:InitializeOptions() end)
    SafeInit("LDB", function() self:InitializeLDB() end)

    -- Register slash commands (always works even if UI fails)
    self:RegisterSlashCommands()

    -- Unregister this event
    eventFrame:UnregisterEvent("ADDON_LOADED")

    print("|cff00ff00HonorLog|r loaded. Type |cffffffff/honorlog|r or |cffffffff/hl|r for options.")
end

-- Detect current battleground
function HonorLog:DetectBattleground()
    -- Method 1: Check instance map ID
    local instanceName, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, mapID = GetInstanceInfo()

    if debugMode then
        print("|cffff00ff[HonorLog Debug]|r Instance: " .. tostring(instanceName) .. ", Type: " .. tostring(instanceType) .. ", MapID: " .. tostring(mapID))
    end

    if instanceType == "pvp" and mapID and BG_MAP_IDS[mapID] then
        return BG_MAP_IDS[mapID]
    end

    -- Method 2: Check zone name
    local zoneName = GetRealZoneText()
    if debugMode and zoneName then
        print("|cffff00ff[HonorLog Debug]|r Zone: " .. zoneName)
    end
    if zoneName and BG_INSTANCE_NAMES[zoneName] then
        return BG_INSTANCE_NAMES[zoneName]
    end

    -- Method 3: Check battlefield status
    for i = 1, GetMaxBattlefieldID() do
        local status, mapName = GetBattlefieldStatus(i)
        if debugMode then
            print("|cffff00ff[HonorLog Debug]|r BF " .. i .. " Status: " .. tostring(status) .. ", Map: " .. tostring(mapName))
        end
        if status == "active" and mapName then
            for name, bgType in pairs(BG_INSTANCE_NAMES) do
                if mapName:find(name) then
                    return bgType
                end
            end
            -- Also check if mapName itself is a direct match
            if BG_INSTANCE_NAMES[mapName] then
                return BG_INSTANCE_NAMES[mapName]
            end
        end
    end

    -- Method 4: Check by instance name directly (fallback)
    if instanceType == "pvp" and instanceName then
        for name, bgType in pairs(BG_INSTANCE_NAMES) do
            if instanceName:find(name) then
                return bgType
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

-- Helper function to get current honor (handles API differences)
local function GetCurrentHonor()
    local honor = nil
    local source = "none"

    -- Try GetHonorCurrency first (TBC/Wrath)
    if GetHonorCurrency then
        honor = GetHonorCurrency()
        if honor and honor > 0 then
            source = "GetHonorCurrency"
        end
    end

    -- Fallback to UnitHonor (some clients)
    if (not honor or honor == 0) and UnitHonor then
        local unitHonor = UnitHonor("player")
        if unitHonor and unitHonor > 0 then
            honor = unitHonor
            source = "UnitHonor"
        end
    end

    -- Fallback to GetPVPCurrency for honor (some TBC clients)
    if (not honor or honor == 0) and GetPVPCurrency then
        local pvpHonor = GetPVPCurrency(HONOR_CURRENCY or 1)
        if pvpHonor and pvpHonor > 0 then
            honor = pvpHonor
            source = "GetPVPCurrency"
        end
    end

    -- Try C_CurrencyInfo if available (retail-like API)
    if (not honor or honor == 0) and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = C_CurrencyInfo.GetCurrencyInfo(1901) -- Honor currency ID
        if info and info.quantity and info.quantity > 0 then
            honor = info.quantity
            source = "C_CurrencyInfo"
        end
    end

    if debugMode and source ~= "none" then
        print("|cffff00ff[HonorLog Debug]|r GetCurrentHonor using: " .. source .. " = " .. tostring(honor))
    end

    return honor or 0
end

-- Entering battleground
function HonorLog:OnBattlegroundEnter(bgType)
    isInBG = true
    currentBG = bgType
    bgStartTime = GetTime()
    bgEnded = false

    -- Reset honor tracking for this BG
    bgHonorAccumulated = 0
    bgStartHonor = GetCurrentHonor()
    lastHonorValue = bgStartHonor

    -- If honor is 0 or nil, try again after a short delay (API might not be ready)
    if not bgStartHonor or bgStartHonor == 0 then
        C_Timer.After(1, function()
            if isInBG and currentBG == bgType and (not bgStartHonor or bgStartHonor == 0) then
                bgStartHonor = GetCurrentHonor()
                lastHonorValue = bgStartHonor
                if debugMode then
                    print("|cffff00ff[HonorLog Debug]|r Delayed honor capture: " .. tostring(bgStartHonor))
                end
            end
        end)
    end

    -- Update UI
    if self.UpdateMainFrame then
        self:UpdateMainFrame()
    end

    -- Always print BG entry so user knows tracking is working
    print("|cff00ff00[HonorLog]|r Entered " .. bgType .. " - tracking started")

    if debugMode then
        print("|cffff00ff[HonorLog Debug]|r BG Entry - Type: " .. bgType .. ", StartHonor: " .. tostring(bgStartHonor))
        -- Show which APIs are available
        print("|cffff00ff[HonorLog Debug]|r   APIs: GetHonorCurrency=" .. tostring(GetHonorCurrency ~= nil) ..
            ", UnitHonor=" .. tostring(UnitHonor ~= nil) ..
            ", GetPVPCurrency=" .. tostring(GetPVPCurrency ~= nil) ..
            ", C_CurrencyInfo=" .. tostring(C_CurrencyInfo ~= nil))
        -- Show raw API values
        if GetHonorCurrency then print("|cffff00ff[HonorLog Debug]|r   GetHonorCurrency()=" .. tostring(GetHonorCurrency())) end
        if UnitHonor then print("|cffff00ff[HonorLog Debug]|r   UnitHonor('player')=" .. tostring(UnitHonor("player"))) end
    end

    -- Save state for /reload persistence
    SaveBGState()
end

-- Leaving battleground
function HonorLog:OnBattlegroundLeave()
    if debugMode then
        print("|cffff00ff[HonorLog Debug]|r OnBattlegroundLeave called")
        print("|cffff00ff[HonorLog Debug]|r   isInBG: " .. tostring(isInBG))
        print("|cffff00ff[HonorLog Debug]|r   bgEnded: " .. tostring(bgEnded))
        print("|cffff00ff[HonorLog Debug]|r   currentBG: " .. tostring(currentBG))
    end

    -- If game already ended and recorded, just clean up
    if bgEnded then
        if debugMode then
            print("|cffff00ff[HonorLog Debug]|r   Game already recorded, cleaning up")
        end
        isInBG = false
        currentBG = nil
        bgStartTime = nil
        bgStartHonor = nil
        bgHonorAccumulated = 0  -- Reset honor counter for next BG
        bgEnded = false  -- Reset flag for next BG
        lastHonorValue = nil  -- Reset honor tracking
        SaveBGState()
        if self.UpdateMainFrame then
            self:UpdateMainFrame()
        end
        return
    end

    -- IMPORTANT: Check for winner BEFORE clearing state!
    -- This handles the case where we're teleported out before UPDATE_BATTLEFIELD_SCORE fires
    if currentBG and bgStartTime and not bgEnded then
        local winner = GetBattlefieldWinner()
        if debugMode then
            print("|cffff00ff[HonorLog Debug]|r   Checking for winner before leaving: " .. tostring(winner))
        end

        if winner ~= nil then
            local factions = { [0] = "Horde", [1] = "Alliance" }
            local winningFaction = factions[winner]
            if debugMode then
                print("|cffff00ff[HonorLog Debug]|r   Found winner on leave: " .. tostring(winningFaction))
            end
            if winningFaction then
                bgEnded = true
                self:OnBattlegroundEnd(winningFaction)
            end
        else
            -- No winner detected yet - save state in case UPDATE_BATTLEFIELD_SCORE fires after we leave
            if debugMode then
                print("|cffff00ff[HonorLog Debug]|r   No winner yet, saving backup state for delayed detection")
            end
            lastBG = currentBG
            lastBGStartTime = bgStartTime
            lastBGStartHonor = bgStartHonor
            lastBGLeaveTime = GetTime()
        end
    end

    isInBG = false
    currentBG = nil
    bgStartTime = nil
    bgStartHonor = nil
    bgHonorAccumulated = 0  -- Reset honor counter
    bgEnded = false  -- Reset flag for next BG
    lastHonorValue = nil  -- Reset honor tracking

    -- Save cleared state
    SaveBGState()

    -- Update UI
    if self.UpdateMainFrame then
        self:UpdateMainFrame()
    end
end

-- BG end message patterns (case-insensitive matching used below)
local WIN_PATTERNS = {
    -- Generic win messages
    ["the alliance wins"] = "Alliance",
    ["the horde wins"] = "Horde",
    ["alliance wins"] = "Alliance",
    ["horde wins"] = "Horde",
    ["alliance victory"] = "Alliance",
    ["horde victory"] = "Horde",
    -- WSG specific
    ["the alliance has won the battle for warsong gulch"] = "Alliance",
    ["the horde has won the battle for warsong gulch"] = "Horde",
    ["alliance has won the battle"] = "Alliance",
    ["horde has won the battle"] = "Horde",
    -- AB specific
    ["the alliance has won the battle for arathi basin"] = "Alliance",
    ["the horde has won the battle for arathi basin"] = "Horde",
    -- EotS specific
    ["the alliance has won the battle for eye of the storm"] = "Alliance",
    ["the horde has won the battle for eye of the storm"] = "Horde",
    -- AV specific
    ["the alliance has won the battle for alterac valley"] = "Alliance",
    ["the horde has won the battle for alterac valley"] = "Horde",
    -- AV general kills (backup detection)
    ["drek'thar is dead"] = "Alliance",
    ["vanndar stormpike is dead"] = "Horde",
    ["drek'thar has been slain"] = "Alliance",
    ["vanndar stormpike has been slain"] = "Horde",
}

-- Handle BG system messages
local function HandleBGMessage(self, msg)
    -- ALWAYS print BG messages in debug mode, even if we're not tracking
    if debugMode then
        print("|cffff00ff[HonorLog Debug]|r HandleBGMessage received:")
        print("|cffff00ff[HonorLog Debug]|r   msg: " .. tostring(msg))
        print("|cffff00ff[HonorLog Debug]|r   isInBG: " .. tostring(isInBG) .. ", currentBG: " .. tostring(currentBG) .. ", bgEnded: " .. tostring(bgEnded))
    end

    if not isInBG or not currentBG or bgEnded then
        if debugMode then
            print("|cffff00ff[HonorLog Debug]|r   SKIPPING - not tracking this BG")
        end
        return
    end

    -- Convert to lowercase for case-insensitive matching
    local msgLower = msg:lower()

    -- Check for win messages (case-insensitive)
    local winner = nil
    for pattern, faction in pairs(WIN_PATTERNS) do
        if msgLower:find(pattern, 1, true) then
            winner = faction
            if debugMode then
                print("|cffff00ff[HonorLog Debug]|r Matched pattern: " .. pattern .. " -> " .. faction)
            end
            break
        end
    end

    -- AV: Check for general kill messages
    if not winner and currentBG == "AV" then
        if msgLower:find("drek'thar") and (msgLower:find("slain") or msgLower:find("dead") or msgLower:find("killed")) then
            winner = "Alliance"
        elseif msgLower:find("vanndar") and (msgLower:find("slain") or msgLower:find("dead") or msgLower:find("killed")) then
            winner = "Horde"
        end
    end

    -- Fallback: check for actual win messages (not "Icewing" which contains "win")
    if not winner then
        -- More specific patterns to avoid false positives like "Icewing"
        if msgLower:find("alliance wins") or msgLower:find("alliance victory") or msgLower:find("the alliance wins") then
            winner = "Alliance"
            if debugMode then
                print("|cffff00ff[HonorLog Debug]|r Fallback match: Alliance wins")
            end
        elseif msgLower:find("horde wins") or msgLower:find("horde victory") or msgLower:find("the horde wins") then
            winner = "Horde"
            if debugMode then
                print("|cffff00ff[HonorLog Debug]|r Fallback match: Horde wins")
            end
        end
    end

    if winner then
        if debugMode then
            print("|cffff00ff[HonorLog Debug]|r Winner detected from BG message: " .. winner)
            print("|cffff00ff[HonorLog Debug]|r   Setting bgEnded = true and calling OnBattlegroundEnd")
        end
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

-- Additional message events that might contain BG win info
function HonorLog:CHAT_MSG_RAID_BOSS_EMOTE(msg)
    HandleBGMessage(self, msg)
end

function HonorLog:CHAT_MSG_MONSTER_YELL(msg)
    HandleBGMessage(self, msg)
end

-- Battleground points update (AB, EotS resource-based BGs)
function HonorLog:BATTLEGROUND_POINTS_UPDATE()
    if not isInBG or not currentBG or bgEnded then return end

    -- Check if we've hit 2000 resources (win condition for AB/EotS)
    if currentBG == "AB" or currentBG == "EotS" then
        local allianceScore, hordScore = GetBattlefieldScore()

        if debugMode then
            print("|cffff00ff[HonorLog Debug]|r Points update - Alliance: " .. tostring(allianceScore) .. ", Horde: " .. tostring(hordScore))
        end

        local winScore = (currentBG == "AB") and 2000 or 2000

        if allianceScore and allianceScore >= winScore then
            bgEnded = true
            self:OnBattlegroundEnd("Alliance")
        elseif hordScore and hordScore >= winScore then
            bgEnded = true
            self:OnBattlegroundEnd("Horde")
        end
    end
end

-- Battleground ended
function HonorLog:OnBattlegroundEnd(winner)
    if debugMode then
        print("|cffff00ff[HonorLog Debug]|r OnBattlegroundEnd called")
        print("|cffff00ff[HonorLog Debug]|r   winner param: " .. tostring(winner))
        print("|cffff00ff[HonorLog Debug]|r   currentBG: " .. tostring(currentBG))
        print("|cffff00ff[HonorLog Debug]|r   bgStartTime: " .. tostring(bgStartTime))
    end

    if not currentBG or not bgStartTime then
        if debugMode then
            print("|cffff00ff[HonorLog Debug]|r   EARLY RETURN - missing currentBG or bgStartTime!")
        end
        return
    end

    local playerFaction = UnitFactionGroup("player")
    local won = (winner == playerFaction)

    if debugMode then
        print("|cffff00ff[HonorLog Debug]|r   playerFaction: " .. tostring(playerFaction))
        print("|cffff00ff[HonorLog Debug]|r   won: " .. tostring(won))
        print("|cffff00ff[HonorLog Debug]|r   Calculating duration...")
    end

    local duration = math.floor(GetTime() - bgStartTime)

    if debugMode then
        print("|cffff00ff[HonorLog Debug]|r   duration: " .. tostring(duration))
        print("|cffff00ff[HonorLog Debug]|r   Calculating honor...")
    end

    -- Calculate honor gained
    local honorGained = 0
    local currentHonor = GetCurrentHonor()

    if debugMode then
        print("|cffff00ff[HonorLog Debug]|r   currentHonor: " .. tostring(currentHonor) .. ", bgStartHonor: " .. tostring(bgStartHonor))
        print("|cffff00ff[HonorLog Debug]|r   bgHonorAccumulated: " .. tostring(bgHonorAccumulated))
    end

    -- Primary method: use accumulated honor from HONOR_XP_UPDATE events
    if bgHonorAccumulated and bgHonorAccumulated > 0 then
        honorGained = bgHonorAccumulated
    -- Fallback: calculate from start/end difference
    elseif bgStartHonor and bgStartHonor > 0 then
        honorGained = math.max(0, currentHonor - bgStartHonor)
    end

    if debugMode then
        print("|cffff00ff[HonorLog Debug]|r   honorGained: " .. tostring(honorGained))
    end

    -- Marks gained (3 for win, 1 for loss in most BGs)
    local marksGained = won and 3 or 1

    -- AV gives bonus marks
    if currentBG == "AV" then
        marksGained = won and 3 or 1
    end

    if debugMode then
        print("|cffff00ff[HonorLog Debug]|r   marksGained: " .. tostring(marksGained))
    end

    -- Record the game
    if debugMode then
        print("|cffff00ff[HonorLog Debug]|r *** RECORDING GAME ***")
        print("|cffff00ff[HonorLog Debug]|r   BG: " .. tostring(currentBG) .. ", Won: " .. tostring(won))
        print("|cffff00ff[HonorLog Debug]|r   Duration: " .. tostring(duration) .. ", Honor: " .. tostring(honorGained) .. ", Marks: " .. tostring(marksGained))
    end

    -- Use pcall to catch any errors in RecordGame
    local success, err = pcall(function()
        self:RecordGame(currentBG, won, duration, honorGained, marksGained)
    end)

    if not success then
        print("|cffff0000[HonorLog ERROR]|r RecordGame failed: " .. tostring(err))
    elseif debugMode then
        print("|cffff00ff[HonorLog Debug]|r   RecordGame completed successfully")
    end

    -- Print result
    local resultColor = won and "|cff00ff00" or "|cffff0000"
    local result = won and "Victory" or "Defeat"
    print(string.format("%s[HonorLog]|r %s%s|r in %s - %s, +%d honor, +%d marks",
        "|cff00ff00", resultColor, result, currentBG,
        self:FormatDuration(duration), honorGained, marksGained))

    -- Reset BG tracking state immediately after recording
    -- This prevents stale data if player does /reload before leaving the BG zone
    isInBG = false
    currentBG = nil
    bgStartTime = nil
    bgStartHonor = nil
    bgHonorAccumulated = 0
    lastHonorValue = nil
    -- bgEnded stays true so OnBattlegroundLeave knows game was recorded
    SaveBGState()

    -- Update UI
    if self.UpdateMainFrame then
        self:UpdateMainFrame()
    end
end

-- Battlefield score update (alternative detection method)
function HonorLog:UPDATE_BATTLEFIELD_SCORE()
    -- Check if the BG has ended by looking at the scoreboard
    local winner = GetBattlefieldWinner()
    local factions = { [0] = "Horde", [1] = "Alliance" }
    local winningFaction = winner ~= nil and factions[winner] or nil

    if debugMode then
        print("|cffff00ff[HonorLog Debug]|r UPDATE_BATTLEFIELD_SCORE")
        print("|cffff00ff[HonorLog Debug]|r   raw winner: " .. tostring(winner) .. " -> " .. tostring(winningFaction))
        print("|cffff00ff[HonorLog Debug]|r   bgEnded: " .. tostring(bgEnded))
        print("|cffff00ff[HonorLog Debug]|r   isInBG: " .. tostring(isInBG) .. ", currentBG: " .. tostring(currentBG))
        print("|cffff00ff[HonorLog Debug]|r   lastBG: " .. tostring(lastBG))
    end

    -- If we already recorded this game, skip
    if bgEnded then
        if debugMode then
            print("|cffff00ff[HonorLog Debug]|r   SKIPPED - bgEnded already true")
        end
        return
    end

    -- GetBattlefieldWinner returns: 0 = Horde, 1 = Alliance, nil = no winner yet
    if winner ~= nil then
        -- Check if we're still in BG with valid state
        if isInBG and currentBG then
            bgEnded = true
            if debugMode then
                print("|cffff00ff[HonorLog Debug]|r   Recording winner (in BG): " .. tostring(winningFaction))
            end
            if winningFaction then
                self:OnBattlegroundEnd(winningFaction)
            end
        -- Check if we just left but have backup state (within 10 seconds)
        elseif lastBG and lastBGStartTime and lastBGLeaveTime and (GetTime() - lastBGLeaveTime) < 10 then
            if debugMode then
                print("|cffff00ff[HonorLog Debug]|r   Recording winner (using backup state): " .. tostring(winningFaction))
            end
            -- Temporarily restore state to record the game
            currentBG = lastBG
            bgStartTime = lastBGStartTime
            bgStartHonor = lastBGStartHonor
            bgEnded = true

            if winningFaction then
                self:OnBattlegroundEnd(winningFaction)
            end

            -- Clear backup state
            lastBG = nil
            lastBGStartTime = nil
            lastBGStartHonor = nil
            lastBGLeaveTime = nil

            -- Clear main state again
            currentBG = nil
            bgStartTime = nil
            bgStartHonor = nil
        else
            if debugMode then
                print("|cffff00ff[HonorLog Debug]|r   Cannot record - no valid state")
            end
        end
    end
end

-- Honor update event - track honor gained during BG
function HonorLog:HONOR_XP_UPDATE()
    if not isInBG or bgEnded then return end

    local currentHonor = GetCurrentHonor()

    if debugMode then
        print("|cffff00ff[HonorLog Debug]|r HONOR_XP_UPDATE - current: " .. tostring(currentHonor) .. ", last: " .. tostring(lastHonorValue))
    end

    -- Track the change in honor
    if lastHonorValue and currentHonor > lastHonorValue then
        local gained = currentHonor - lastHonorValue
        bgHonorAccumulated = bgHonorAccumulated + gained
        SaveBGState()

        if debugMode then
            print("|cffff00ff[HonorLog Debug]|r   Gained " .. gained .. " honor, total accumulated: " .. bgHonorAccumulated)
        end
    end

    lastHonorValue = currentHonor
end

-- TBC Classic: Parse honor from chat messages
-- Formats:
--   "PlayerName dies, honorable kill Rank: RankName (X Honor Points)"
--   "You have been awarded X honor points."
function HonorLog:CHAT_MSG_COMBAT_HONOR_GAIN(msg)
    if not isInBG or bgEnded then return end

    local honorAmount = nil

    -- Try pattern 1: "(X Honor Points)" - honorable kills
    honorAmount = msg:match("%((%d+) Honor Point")

    -- Try pattern 2: "awarded X honor points" - BG bonus honor
    if not honorAmount then
        honorAmount = msg:match("awarded (%d+) honor")
    end

    -- Try pattern 3: just look for any number followed by "honor"
    if not honorAmount then
        honorAmount = msg:match("(%d+) honor")
    end

    if honorAmount then
        honorAmount = tonumber(honorAmount)
        if honorAmount and honorAmount > 0 then
            bgHonorAccumulated = bgHonorAccumulated + honorAmount
            SaveBGState()

            if debugMode then
                print("|cffff00ff[HonorLog Debug]|r CHAT_MSG_COMBAT_HONOR_GAIN - parsed: " .. honorAmount .. " honor, total: " .. bgHonorAccumulated)
            end
        end
    elseif debugMode then
        print("|cffff00ff[HonorLog Debug]|r CHAT_MSG_COMBAT_HONOR_GAIN - couldn't parse: " .. tostring(msg))
    end
end

-- TBC Classic: Parse honor from system messages
-- Format: "You receive currency: [Honor Points] x10"
function HonorLog:CHAT_MSG_SYSTEM(msg)
    -- Debug: show all system messages in BG when debug mode is on
    if debugMode and isInBG then
        print("|cffff00ff[HonorLog Debug]|r CHAT_MSG_SYSTEM: " .. tostring(msg))
    end

    if not isInBG then return end

    -- Check for honor currency messages (case-insensitive)
    local msgLower = msg:lower()
    if msgLower:find("honor points") or msgLower:find("honor point") then
        -- Try pattern: "Honor Points] x10" or "Honor Points] xN"
        local honorAmount = msg:match("%[Honor Points%]%s*x(%d+)")

        if not honorAmount then
            -- Try alternate pattern without x: just a number after Honor Points
            honorAmount = msg:match("%[Honor Points%]%s*(%d+)")
        end

        if honorAmount then
            honorAmount = tonumber(honorAmount)
            if honorAmount and honorAmount > 0 then
                bgHonorAccumulated = bgHonorAccumulated + honorAmount
                SaveBGState()

                if debugMode then
                    print("|cffff00ff[HonorLog Debug]|r CHAT_MSG_SYSTEM - parsed honor: " .. honorAmount .. ", total: " .. bgHonorAccumulated)
                end
            end
        elseif debugMode then
            print("|cffff00ff[HonorLog Debug]|r CHAT_MSG_SYSTEM - found Honor Points but couldn't parse amount: " .. tostring(msg))
        end
    end
end

-- Player logout - save current GetTime() for reload detection
function HonorLog:PLAYER_LOGOUT()
    -- Debug: always print when this fires
    print("|cff00ff00[HonorLog]|r PLAYER_LOGOUT fired! GetTime()=" .. string.format("%.1f", GetTime()))

    if self.db and self.db.char then
        -- Store current GetTime() - on /reload this value will be less than GetTime() at next load
        -- On fresh login after logout, GetTime() will have reset, so it will be less than this stored value
        self.db.char.lastGameTime = GetTime()
        self.db.char.wasLogout = true -- Keep for backwards compatibility
        print("|cff00ff00[HonorLog]|r   Saved lastGameTime=" .. string.format("%.1f", self.db.char.lastGameTime))
    else
        print("|cffff0000[HonorLog]|r   ERROR: self.db or self.db.char is nil!")
    end
end

-- Periodic winner check (safety net for missed events)
local winnerCheckFrame = CreateFrame("Frame")
local winnerCheckTimer = 0
local WINNER_CHECK_INTERVAL = 1  -- Check every 1 second while in BG

winnerCheckFrame:SetScript("OnUpdate", function(self, elapsed)
    if not isInBG or bgEnded then return end

    winnerCheckTimer = winnerCheckTimer + elapsed
    if winnerCheckTimer >= WINNER_CHECK_INTERVAL then
        winnerCheckTimer = 0

        -- Method 1: GetBattlefieldWinner
        local winner = GetBattlefieldWinner()
        if winner ~= nil then
            local factions = { [0] = "Horde", [1] = "Alliance" }
            local winningFaction = factions[winner]
            if debugMode then
                print("|cffff00ff[HonorLog Debug]|r *** PERIODIC CHECK FOUND WINNER ***")
                print("|cffff00ff[HonorLog Debug]|r   raw: " .. tostring(winner) .. " -> " .. tostring(winningFaction))
                print("|cffff00ff[HonorLog Debug]|r   Setting bgEnded = true and calling OnBattlegroundEnd")
            end
            bgEnded = true
            if winningFaction then
                HonorLog:OnBattlegroundEnd(winningFaction)
            end
            return
        end

        -- Method 2: Check battlefield score for resource-based BGs
        if currentBG == "AB" or currentBG == "EotS" then
            local allianceScore = 0
            local hordeScore = 0

            -- Try to get the scores from the world state
            -- In TBC, AB and EotS use 2000 resources to win
            local numScores = GetNumBattlefieldScores()
            if numScores and numScores > 0 then
                -- Check faction scores via faction stat widgets
                for i = 1, numScores do
                    local name, kills, killingBlows, deaths, honorGained, faction = GetBattlefieldScore(i)
                    -- faction: 0 = Horde, 1 = Alliance
                end
            end
        end

        -- Method 3: Check if player just got honor (BG ended reward)
        -- This is a fallback detection
    end
end)

-- Slash commands
function HonorLog:RegisterSlashCommands()
    SLASH_HONORLOG1 = "/honorlog"
    SLASH_HONORLOG2 = "/hl"

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
        local resetType = arg:lower()
        if resetType == "session" then
            self:ResetSession()
            print("|cff00ff00HonorLog|r Session stats reset.")
        elseif resetType == "character" or resetType == "char" then
            -- Reset character battleground stats
            for bgType, _ in pairs(self.db.char.battlegrounds) do
                self.db.char.battlegrounds[bgType] = {
                    played = 0, wins = 0, losses = 0,
                    totalDuration = 0, honorLifetime = 0, marksLifetime = 0
                }
            end
            self.db.char.history = {}
            self:ResetSession()
            if self.UpdateMainFrame then
                self:UpdateMainFrame()
            end
            print("|cff00ff00HonorLog|r Character stats reset.")
        elseif resetType == "account" then
            -- Reset account-wide battleground stats
            for bgType, _ in pairs(self.db.global.battlegrounds) do
                self.db.global.battlegrounds[bgType] = {
                    played = 0, wins = 0, losses = 0,
                    totalDuration = 0, honorLifetime = 0, marksLifetime = 0
                }
            end
            self.db.global.history = {}
            if self.UpdateMainFrame then
                self:UpdateMainFrame()
            end
            print("|cff00ff00HonorLog|r Account stats reset.")
        else
            print("|cff00ff00HonorLog|r Usage: /honorlog reset [session|character|account]")
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
            print("|cff00ff00HonorLog|r Usage: /honorlog view [character|account]")
        end
        if self.UpdateMainFrame then
            self:UpdateMainFrame()
        end
    elseif cmd == "minimap" then
        self:ToggleMinimapButton()
        local shown = self:IsMinimapButtonShown()
        print("|cff00ff00HonorLog|r Minimap button: " .. (shown and "shown" or "hidden"))
    elseif cmd == "debug" then
        debugMode = not debugMode
        print("|cff00ff00HonorLog|r Debug mode: " .. (debugMode and "ON" or "OFF"))
        if debugMode then
            print("|cff00ff00HonorLog|r Current state:")
            print("  InBG: " .. tostring(isInBG))
            print("  BG: " .. tostring(currentBG))
            print("  Ended: " .. tostring(bgEnded))
            print("  StartTime: " .. tostring(bgStartTime))
            -- Try to detect BG
            local detected = self:DetectBattleground()
            print("  Detected BG: " .. tostring(detected))
            -- Show GetBattlefieldWinner result
            local winner = GetBattlefieldWinner()
            print("  GetBattlefieldWinner: " .. tostring(winner))
            -- Show session data
            print("  Session wasLogout: " .. tostring(self.db.char.wasLogout))
        end
    elseif cmd == "status" then
        -- Show current tracking status
        print("|cff00ff00HonorLog Status:|r")
        print("  In BG: " .. tostring(isInBG))
        print("  Current BG: " .. tostring(currentBG))
        print("  BG Ended: " .. tostring(bgEnded))
        local detected = self:DetectBattleground()
        print("  Detected BG: " .. tostring(detected))
        local session = self:GetTotalSessionStats()
        print("  Session games: " .. session.played)
    elseif cmd == "test" then
        -- Test command to manually record a game
        local bgType = arg:upper()
        if bgType == "" then bgType = "WSG" end
        if self.db.char.battlegrounds[bgType] then
            self:RecordGame(bgType, true, 600, 100, 3)
            print("|cff00ff00HonorLog|r Test game recorded: " .. bgType .. " WIN")
        else
            print("|cff00ff00HonorLog|r Invalid BG. Use: /honorlog test [AV|AB|WSG|EotS]")
        end
    elseif cmd == "goals" or cmd == "goal" then
        -- Goal management commands
        local subCmd, subArg = arg:match("^(%S*)%s*(.*)$")
        subCmd = (subCmd or ""):lower()

        if subCmd == "" or subCmd == "show" then
            -- Switch to goals tab
            self:SwitchTab("goals")
            if not self.mainFrame:IsShown() then
                self:ToggleMainFrame()
            end
        elseif subCmd == "add" then
            -- Add goal by item link or ID
            local itemID = nil
            -- Try to parse item link
            local linkedID = subArg:match("item:(%d+)")
            if linkedID then
                itemID = tonumber(linkedID)
            else
                -- Try direct ID
                itemID = tonumber(subArg)
            end

            if itemID then
                local success, err = self:AddGoal(itemID)
                if success then
                    local item = self:GetGearItem(itemID)
                    print("|cff00ff00[HonorLog]|r Added goal: " .. (item and item.name or "Item " .. itemID))
                else
                    print("|cffff0000[HonorLog]|r " .. (err or "Could not add goal"))
                end
            else
                print("|cff00ff00HonorLog|r Usage: /honorlog goal add [itemlink or itemID]")
            end
        elseif subCmd == "list" then
            -- List current goals
            local goals = self:GetAllGoalsProgress()
            if #goals == 0 then
                print("|cff00ff00[HonorLog]|r No goals set. Use /honorlog goal add to add one.")
            else
                print("|cff00ff00[HonorLog Goals]|r (" .. #goals .. "/" .. self:GetMaxGoals() .. ")")
                for i, goal in ipairs(goals) do
                    local statusColor = goal.isComplete and "|cff00ff00" or "|cffffff00"
                    local status = goal.isComplete and "READY" or string.format("%.0f%%", math.min(goal.honor.percent, goal.arena.percent > 0 and goal.arena.percent or 100))
                    print(string.format("  %d. %s%s|r - %s", i, statusColor, goal.name, status))
                end
            end
        elseif subCmd == "clear" then
            -- Clear all goals
            self.db.char.goals.items = {}
            print("|cff00ff00[HonorLog]|r All goals cleared.")
            self:UpdateGoalsPanel()
        elseif subCmd == "picker" then
            self:ShowGoalPicker()
        else
            print("|cff00ff00HonorLog|r Goal commands:")
            print("  |cffffffff/honorlog goal|r - Show goals panel")
            print("  |cffffffff/honorlog goal add [itemlink]|r - Add a goal")
            print("  |cffffffff/honorlog goal list|r - List current goals")
            print("  |cffffffff/honorlog goal clear|r - Clear all goals")
            print("  |cffffffff/honorlog goal picker|r - Open goal picker")
        end
    elseif cmd == "currency" or cmd == "cur" then
        -- Diagnostic: show current honor and marks detection
        print("|cff00ff00HonorLog Currency Diagnostic:|r")

        -- Honor APIs
        print("|cffffd700Honor APIs:|r")
        print("  GetHonorCurrency exists: " .. tostring(GetHonorCurrency ~= nil))
        print("  GetPVPCurrency exists: " .. tostring(GetPVPCurrency ~= nil))
        print("  C_CurrencyInfo exists: " .. tostring(C_CurrencyInfo ~= nil))

        if GetHonorCurrency then
            local honor = GetHonorCurrency()
            print("  GetHonorCurrency() = " .. tostring(honor))
        end
        if GetPVPCurrency then
            local _, honor = GetPVPCurrency()
            print("  GetPVPCurrency() = " .. tostring(honor))
        end
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            -- Try common honor currency IDs
            local currencyIDs = {1792, 392, 43308, 1901}
            for _, currencyID in ipairs(currencyIDs) do
                local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
                if info then
                    print(string.format("  C_CurrencyInfo(%d) = %s: %d",
                        currencyID, info.name or "?", info.quantity or 0))
                end
            end
        end

        -- Arena API
        print("|cffaa55ffArena APIs:|r")
        print("  GetArenaCurrency exists: " .. tostring(GetArenaCurrency ~= nil))
        if GetArenaCurrency then
            print("  GetArenaCurrency() = " .. tostring(GetArenaCurrency()))
        end

        -- Our wrapper functions
        print("|cff00ff00HonorLog Values:|r")
        print("  GetCurrentHonor() = " .. tostring(self:GetCurrentHonor()))
        print("  GetCurrentArenaPoints() = " .. tostring(self:GetCurrentArenaPoints()))

        -- Marks
        print("|cff55bbffMarks:|r")
        local markItems = self.MARK_ITEMS
        if markItems then
            for bgType, itemID in pairs(markItems) do
                local count = GetItemCount(itemID, true)
                local itemName = GetItemInfo(itemID)
                print(string.format("  %s (ID %d): %d marks%s",
                    bgType, itemID, count,
                    itemName and (" - " .. itemName) or " - (item not cached)"))
            end
        else
            print("  MARK_ITEMS not defined!")
        end

        -- Check bag contents for marks manually
        print("|cff888888Scanning bags for mark items...|r")
        local foundMarks = false
        for bag = 0, 4 do
            local numSlots
            if C_Container and C_Container.GetContainerNumSlots then
                numSlots = C_Container.GetContainerNumSlots(bag)
            elseif GetContainerNumSlots then
                numSlots = GetContainerNumSlots(bag)
            else
                numSlots = 0
            end
            for slot = 1, numSlots do
                local slotItemID
                if C_Container and C_Container.GetContainerItemID then
                    slotItemID = C_Container.GetContainerItemID(bag, slot)
                elseif GetContainerItemID then
                    slotItemID = GetContainerItemID(bag, slot)
                end
                if slotItemID then
                    -- Check if it's a mark (20558=WSG, 20559=AB, 20560=AV, 29024=EotS)
                    if slotItemID == 20558 or slotItemID == 20559 or slotItemID == 20560 or slotItemID == 29024 then
                        local itemName = GetItemInfo(slotItemID)
                        local count = 0
                        if C_Container and C_Container.GetContainerItemInfo then
                            local info = C_Container.GetContainerItemInfo(bag, slot)
                            count = info and info.stackCount or 0
                        elseif GetContainerItemInfo then
                            local _, stackCount = GetContainerItemInfo(bag, slot)
                            count = stackCount or 0
                        end
                        print(string.format("  Found: %s x%d in bag %d slot %d",
                            itemName or slotItemID, count, bag, slot))
                        foundMarks = true
                    end
                end
            end
        end
        if not foundMarks then
            print("  No mark items found in bags")
        end

        print("|cff888888Tip: If values show 0 but you have currency, please report which APIs are available.|r")
    else
        print("|cff00ff00HonorLog|r Unknown command. Type /honorlog help for options.")
    end
end

function HonorLog:PrintHelp()
    print("|cff00ff00HonorLog Commands:|r (also: /hl)")
    print("  |cffffffff/honorlog|r - Toggle stats frame")
    print("  |cffffffff/honorlog stats [bg]|r - Print stats summary")
    print("  |cffffffff/honorlog reset session|r - Reset session stats")
    print("  |cffffffff/honorlog reset character|r - Reset character stats")
    print("  |cffffffff/honorlog reset account|r - Reset account-wide stats")
    print("  |cffffffff/honorlog export [text|csv]|r - Export stats")
    print("  |cffffffff/honorlog view [character|account]|r - Switch view mode")
    print("  |cffffffff/honorlog goal|r - Show goals panel")
    print("  |cffffffff/honorlog goal add [itemlink]|r - Add gear goal")
    print("  |cffffffff/honorlog goal list|r - List current goals")
    print("  |cffffffff/honorlog goal clear|r - Clear all goals")
    print("  |cffffffff/honorlog minimap|r - Toggle minimap button")
    print("  |cffffffff/honorlog config|r - Open options")
    print("  |cffffffff/honorlog status|r - Show tracking status")
    print("  |cffffffff/honorlog debug|r - Toggle debug mode")
    print("  |cffffffff/honorlog currency|r - Show currency diagnostic")
    print("  |cffffffff/honorlog test [bg]|r - Test record a game")
    print("  |cffffffff/honorlog help|r - Show this help")
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

function HonorLog:GetBGHonorAccumulated()
    return bgHonorAccumulated or 0
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
        icon = "Interface\\Icons\\Spell_Holy_ChampionsBond",
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

    -- Initialize minimap button
    self:InitializeMinimapButton()
end

-- Minimap button using LibDBIcon
function HonorLog:InitializeMinimapButton()
    local icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not icon then return end

    -- Register the minimap button
    icon:Register("HonorLog", self.ldb, self.db.settings.minimapButton)
    self.minimapIcon = icon
end

-- Toggle minimap button visibility
function HonorLog:ToggleMinimapButton()
    if not self.minimapIcon then return end

    local hidden = self.db.settings.minimapButton.hide
    if hidden then
        self.minimapIcon:Show("HonorLog")
        self.db.settings.minimapButton.hide = false
    else
        self.minimapIcon:Hide("HonorLog")
        self.db.settings.minimapButton.hide = true
    end
end

-- Check if minimap button is visible
function HonorLog:IsMinimapButtonShown()
    if not self.minimapIcon then return false end
    return not self.db.settings.minimapButton.hide
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
        -- Honor with hourly rate
        local honorText = string.format("+%d", session.honor)
        if session.hourlyRate > 0 then
            honorText = string.format("+%d |cff888888(%d/hr)|r", session.honor, session.hourlyRate)
        end
        tooltip:AddDoubleLine("Honor", honorText, 1, 1, 1, 1, 0.82, 0)
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
