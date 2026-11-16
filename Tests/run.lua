--[[ HonorLog - Tests/run.lua

    Loads every addon file named in HonorLog.toc under the Forever-shaped mock
    (Tests/mock_wow.lua), then drives a short session: login, slash commands,
    a recorded game, the probe snapshot and its scoreboard timing. Any syntax
    error, load-order mistake or nil-global call aborts with a non-zero exit
    code, which is what CI checks.

    Usage:  lua Tests/run.lua   (run from the repository root)
]]

local function exists(path)
    local f = io.open(path)
    if f then f:close() return true end
    return false
end

local ROOT = exists("HonorLog.toc") and "."
    or (exists("../HonorLog.toc") and "..")
    or error("run from the repository root: lua Tests/run.lua")

local mock = dofile(ROOT .. "/Tests/mock_wow.lua")

-- Print capture, so the test can look for error lines the addon reports itself.
local printed = {}
local realPrint = print
print = function(...) -- luacheck: ignore 121 (the harness replaces print on purpose)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    printed[#printed + 1] = table.concat(parts, " ")
end
local function printedMatching(pattern)
    for _, line in ipairs(printed) do
        if line:find(pattern) then return line end
    end
    return nil
end

local assertions = 0
local function check(cond, msg)
    assertions = assertions + 1
    if not cond then error("ASSERT FAILED: " .. tostring(msg), 2) end
end

local function run()
    -- The test's file list must equal the .toc list, in order.
    local FILES = {
        "Libs/LibStub.lua", "Libs/CallbackHandler-1.0.lua", "Libs/LibDataBroker-1.1.lua", "Libs/LibDBIcon-1.0.lua",
        "Data/GearDatabase.lua",
        "Data.lua", "Core.lua",
        "Modules/BattlegroundBase.lua", "Modules/AV.lua", "Modules/AB.lua", "Modules/WSG.lua",
        "Modules/EotS.lua", "Modules/VendorScanner.lua", "Modules/Probe.lua",
        "UI/Theme.lua", "UI/Animation.lua", "UI/MainFrame.lua", "UI/GoalsPanel.lua", "UI/Options.lua",
        "UI/Export.lua",
    }
    local tocFiles = {}
    for line in io.lines(ROOT .. "/HonorLog.toc") do
        if not line:find("^%s*#") and not line:find("^%s*$") and not line:find("^##") then
            tocFiles[#tocFiles + 1] = (line:gsub("\\", "/"):gsub("%s+$", ""))
        end
    end
    check(#tocFiles == #FILES, "toc lists " .. #tocFiles .. " files, test lists " .. #FILES)
    for i, f in ipairs(FILES) do
        check(tocFiles[i] == f, "toc file " .. i .. " is " .. tostring(tocFiles[i]) .. ", test expects " .. f)
    end
    local toc = io.open(ROOT .. "/HonorLog.toc"):read("*a")
    check(toc:find("## Interface: 16001", 1, true), "toc must target Interface 16001")

    -- Every file loads, with the shared namespace, as WoW passes it.
    local ns = {}
    for _, file in ipairs(FILES) do
        local chunk, err = loadfile(ROOT .. "/" .. file)
        check(chunk, "could not load " .. file .. ": " .. tostring(err))
        local ok, runErr = pcall(chunk, "HonorLog", ns)
        check(ok, "error while loading " .. file .. ": " .. tostring(runErr))
    end
    local HonorLog = ns
    check(HonorLog.Compat and HonorLog.Probe, "Compat and Probe modules present")

    -- The Forever-shaped mock really lacks the TBC globals.
    for _, name in ipairs({ "GetHonorCurrency", "GetPVPCurrency", "GetArenaCurrency", "GetBattlefieldScore",
        "GetItemInfo", "GetItemCount", "GetContainerItemID", "GetAddOnMetadata",
        "InterfaceOptions_AddCategory", "CombatLogGetCurrentEventInfo" }) do
        check(_G[name] == nil, name .. " must be absent from the Forever mock")
    end

    -- Login. Saved variables are created in ADDON_LOADED (the client has them by then).
    mock.fireEvent("ADDON_LOADED", "HonorLog")
    mock.fireEvent("PLAYER_LOGIN")
    mock.fireEvent("PLAYER_ENTERING_WORLD")
    check(type(HonorLogDB) == "table", "HonorLogDB initialised")
    check(type(HonorLogCharDB) == "table", "HonorLogCharDB initialised")
    check(HonorLog.db and HonorLog.db.char == HonorLogCharDB, "db wired to saved variables")
    check(not printedMatching("HonorLog ERROR"), "init reported an error: " .. tostring(printedMatching("HonorLog ERROR")))
    check(HonorLog.mainFrame, "main frame built")

    -- Restricted events must not be registered; the combat log stays off.
    for _, frame in ipairs(mock.frames) do
        check(not frame.__events.COMBAT_LOG_EVENT_UNFILTERED, "COMBAT_LOG_EVENT_UNFILTERED must not be registered")
    end

    -- Slash commands.
    check(SLASH_HONORLOG1 == "/honorlog" and SLASH_HONORLOG2 == "/hl", "slash tokens set")
    local slash = SlashCmdList.HONORLOG
    check(type(slash) == "function", "slash handler registered")
    slash("status")
    check(printedMatching("HonorLog Status"), "/honorlog status printed")
    slash("goal list")
    check(not printedMatching("GetMaxGoals"), "goal list no longer calls GetMaxGoals")
    local goalItem = next(HonorLog.GearDB)
    check(HonorLog:AddGoal(goalItem), "a goal can be added from the gear database")
    slash("goal list")
    slash("currency")
    slash("help")

    -- History limit: 500, matching the Options slider.
    HonorLog:SetHistoryLimit(500)
    check(HonorLogCharDB.historyLimit == 500 and HonorLogDB.historyLimit == 500, "history limit accepts 500")
    HonorLog:SetHistoryLimit(5000)
    check(HonorLogCharDB.historyLimit == 500, "history limit caps at 500")

    -- Recording a game updates the stats.
    local before = HonorLogCharDB.battlegrounds.WSG.played
    HonorLog:RecordGame("WSG", true, 600, 100, 3)
    check(HonorLogCharDB.battlegrounds.WSG.played == before + 1, "RecordGame bumps played")
    check(HonorLogCharDB.battlegrounds.WSG.wins >= 1, "RecordGame bumps wins")
    check(HonorLogDB.battlegrounds.WSG.honorLifetime >= 100, "RecordGame bumps account honor")
    check(HonorLogCharDB.session.WSG.played >= 1, "RecordGame bumps the session")

    -- Honor reads the Forever currency (1792), not a TBC global.
    check(HonorLog:GetCurrentHonor() == 8200, "honor read from currency 1792")

    -- Probe snapshot.
    slash("probe")
    local snap = HonorLogDB.probe and HonorLogDB.probe.snapshot
    check(type(snap) == "table", "probe snapshot written to HonorLogDB.probe.snapshot")
    check(snap.faction2800.progression.renownLevel == 3, "snapshot has faction 2800 progression")
    check(#snap.faction2800.rewards == 14, "snapshot has 14 renown reward levels")
    check(snap.currencies["1792"].quantity == 8200, "snapshot has honor currency")
    check(snap.marks.WSG_20558 == 12, "snapshot has mark counts")
    check(snap.battlegrounds.battlegrounds[1].name == "Warsong Gulch", "snapshot has the BG list")
    check(snap.honorFormatStrings.COMBATLOG_HONORAWARD ~= nil, "snapshot has honor format strings")
    check(snap.addonRestrictions.PvPMatch ~= nil, "snapshot has addon restriction states")
    check(snap.combatLog.COMBAT_LOG_EVENT_UNFILTERED == "skipped: restricted", "combat log recorded as skipped")
    check(type(snap.season.secondsUntilPVPSeasonEnd) == "number", "snapshot has season end")
    slash("probe status")

    -- Passive logging: arm, feed events, check the ring buffer.
    slash("probe on")
    check(HonorLogDB.probe.armed == true, "probe armed flag persisted")
    check(#HonorLogDB.probe.registerFailed == 0, "every probe event registered: " .. table.concat(HonorLogDB.probe.registerFailed, ","))
    mock.fireEvent("CURRENCY_DISPLAY_UPDATE", 1792, 8300, 100)
    mock.fireEvent("CURRENCY_DISPLAY_UPDATE", 9999, 1, 1)
    local log = HonorLogDB.probe.log
    check(#log == 1 and log[1].event == "CURRENCY_DISPLAY_UPDATE", "only tracked currencies are logged")
    check(log[1].t and log[1].gt and log[1].args[1] == 1792, "log entry has t, gt, event, args")
    mock.fireEvent("BAG_UPDATE_DELAYED")
    check(log[#log].marks.WSG_20558 == 12, "BAG_UPDATE_DELAYED records mark counts")
    mock.fireEvent("PLAYER_DEAD")
    mock.fireEvent("PARTY_KILL", mock.newSecret(), mock.newSecret())
    check(log[#log].event == "PARTY_KILL" and log[#log].attackerSecret == true, "PARTY_KILL logs secret GUIDs")
    for i = 1, 450 do mock.fireEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL", "msg " .. i) end
    check(#HonorLogDB.probe.log == 400, "ring buffer caps at 400 entries")

    -- Secret values never reach the saved variables.
    mock.pvp.matchActive = true
    mock.pvp.scoresSecret = true
    mock.pvp.numScores = 4
    mock.fireEvent("PVP_MATCH_ACTIVE")
    local display = HonorLogDB.probe.secretDisplay
    check(display and display[1] and display[1].setTextOK == true, "secret display test ran and SetText succeeded")
    check(display[1].valueWasSecret == true, "secret display test saw a secret value")

    -- Scoreboard timing: unreadable at first, readable on a later attempt.
    mock.deferTimers = true
    mock.fireEvent("PVP_MATCH_COMPLETE", 1, 612)
    mock.pvp.matchActive, mock.pvp.matchComplete = false, true
    mock.flushTimers(1)
    mock.pvp.scoresSecret = false
    mock.flushTimers()
    mock.deferTimers = false
    local sb = HonorLogDB.probe.scoreboard
    check(sb and #sb == 1, "scoreboard watch recorded")
    check(sb[1].attempts[1].attempt == "immediate", "first attempt is the immediate read")
    check(sb[1].attempts[1].readable == false, "immediate read unreadable while scores are secret")
    check(sb[1].attempts[1].own.honorGained == "<secret>", "secret honorGained stored as <secret>")
    check(sb[1].firstReadable == "after 3s", "first readable attempt recorded: " .. tostring(sb[1].firstReadable))
    check(sb[1].attempts[1].neverSecretFieldsReadable.all == true, "never-secret fields reported readable")
    check(sb[1].attempts[1].numericFieldsReadable.all == false, "numeric fields reported unreadable")
    mock.pvp.matchComplete = false

    slash("probe off")
    check(HonorLogDB.probe.armed == false, "probe disarmed")
    slash("probe clear")

    -- The mock's registration rules are live: the restricted event raises.
    local ok = pcall(UIParent.RegisterEvent, UIParent, "COMBAT_LOG_EVENT_UNFILTERED")
    check(not ok, "registering COMBAT_LOG_EVENT_UNFILTERED raises in the mock")

    check(not printedMatching("HonorLog ERROR"), "an error line was printed: " .. tostring(printedMatching("HonorLog ERROR")))

    -- The embedded LibDataBroker must be the real CallbackHandler-based one:
    -- a stand-in with the same minor version would win LibStub for every addon
    -- loaded after HonorLog and break their broker callbacks.
    local ldb = LibStub("LibDataBroker-1.1")
    check(type(ldb.RegisterCallback) == "function", "LibDataBroker exposes RegisterCallback")
    check(#mock.handledErrors == 0, "errors reached geterrorhandler: " .. tostring(mock.handledErrors[1]))
end

local ok, err = xpcall(run, debug.traceback)
print = realPrint -- luacheck: ignore 121
if not ok then
    realPrint("HONORLOG HEADLESS TEST: FAIL")
    realPrint(err)
    os.exit(1)
end
realPrint("HONORLOG HEADLESS TEST: PASS (" .. assertions .. " assertions)")
