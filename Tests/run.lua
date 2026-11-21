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
        "Util.lua",
        "Data/GearDatabase.lua",
        "Data/Vendors.lua",
        "Data.lua", "Core.lua",
        "Modules/BattlegroundBase.lua", "Modules/AV.lua", "Modules/AB.lua", "Modules/WSG.lua",
        "Modules/DI.lua", "Modules/Rank.lua", "Modules/VendorScanner.lua", "Modules/Probe.lua",
        "Model.lua",
        "UI/Theme.lua", "UI/MapPin.lua", "UI/Animation.lua", "UI/MainFrame.lua", "UI/GoalsPanel.lua", "UI/Options.lua",
        "UI/Export.lua", "UI/Kit.lua", "UI/Window.lua", "UI/Screens/Overview.lua",
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
    local function loadAddon()
        local namespace = {}
        for _, file in ipairs(FILES) do
            local chunk, err = loadfile(ROOT .. "/" .. file)
            check(chunk, "could not load " .. file .. ": " .. tostring(err))
            local ok, runErr = pcall(chunk, "HonorLog", namespace)
            check(ok, "error while loading " .. file .. ": " .. tostring(runErr))
        end
        return namespace
    end
    local HonorLog = loadAddon()
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

    ----------------------------------------------------------------------
    -- Round 1: battleground games, world PvP, honor, migration
    ----------------------------------------------------------------------
    local HL = HonorLog
    local function countPrinted(pattern)
        local n = 0
        for _, line in ipairs(printed) do if line:find(pattern) then n = n + 1 end end
        return n
    end
    local function resetPvP()
        mock.pvp.matchActive, mock.pvp.matchComplete, mock.pvp.scoresSecret = false, false, false
        mock.pvp.numScores, mock.pvp.roster, mock.pvp.columns = 0, nil, nil
        mock.pvp.duration, mock.pvp.winner, mock.pvp.bfWinner, mock.pvp.team = 30, 1, nil, 1
    end
    local function enter(name, mapID)
        mock.setInstance(name, "pvp", mapID)
        mock.fireEvent("PLAYER_ENTERING_WORLD")
    end
    local function leave()
        mock.fireEvent("PLAYER_LEAVING_WORLD")
        mock.setInstance("Stormwind City", "none", 0)
        mock.fireEvent("PLAYER_ENTERING_WORLD")
    end
    local function gainHonor(n)
        local q = mock.currencies[1792].quantity + n
        mock.currencies[1792].quantity = q
        mock.fireEvent("CURRENCY_DISPLAY_UPDATE", 1792, q, n)
    end
    local function roster()
        return {
            { name = "Tester", guid = "Player-1-1", faction = 1, kb = 3, hk = 12, deaths = 2, damage = 50000, healing = 1200,
              stats = { { id = 42, name = "Flag Captures", value = 2 }, { id = 44, name = "Flag Returns", value = 4 } } },
            { name = "Ally2", guid = "Player-1-2", faction = 1, kb = 1, hk = 5, deaths = 4, damage = 9000, healing = 0, stats = {} },
            { name = "Foe1", guid = "Player-9-1", faction = 0, kb = 5, hk = 9, deaths = 3, damage = 30000, healing = 0, stats = {} },
            { name = "Foe2", guid = "Player-9-2", faction = 0, kb = 2, hk = 4, deaths = 6, damage = 12000, healing = 800, stats = {} },
        }
    end
    local function lastGame() return HL.db.char.history[1] end

    mock.now = 100000
    mock.deferTimers = true
    mock.timers = {}
    resetPvP()
    mock.bagItems = { [20558] = 12, [20559] = 3 }
    mock.currencies[1792].quantity, mock.currencies[1792].maxQuantity = 8200, 25000

    -- The registry: Forever's four battlegrounds by map id, no EotS, no arena.
    check(HL.BG_BY_MAP[30] == "AV" and HL.BG_BY_MAP[489] == "WSG" and HL.BG_BY_MAP[529] == "AB" and HL.BG_BY_MAP[2997] == "DI",
        "registry keys the four battlegrounds by instance map id")
    check(table.concat(HL.BG_ORDER, ",") == "AV,WSG,AB,DI", "BG_ORDER is AV, WSG, AB, DI")
    check(HL.BG_MARK_ITEMS.AV == 20560 and HL.BG_MARK_ITEMS.WSG == 20558 and HL.BG_MARK_ITEMS.AB == 20559 and HL.BG_MARK_ITEMS.DI == 274895,
        "mark items per battleground")
    check(HL.Battlegrounds.EotS == nil, "EotS is no longer a tracked battleground")
    check(HL.mainFrame.bgCards.DI and not HL.mainFrame.bgCards.EotS, "stats UI has a DI card and no EotS card")
    check(HL.db.global.battlegrounds.DI and not HL.db.global.battlegrounds.EotS, "DI defaults exist, EotS aggregate is gone")
    for _, frame in ipairs(mock.frames) do
        check(not frame.__events.HONOR_XP_UPDATE and not frame.__events.CHAT_MSG_SYSTEM, "TBC honor events are not registered")
    end

    -- Honor-gain strings compile from the client's own format strings (any language).
    local kind, victim, rank, honor = HL.ParseHonorMessage(string.format(COMBATLOG_HONORGAIN, "Bob-the-Mage (x)", "Corporal", 21))
    check(kind == "kill" and victim == "Bob-the-Mage (x)" and rank == "Corporal" and honor == 21, "kill message parsed with magic characters in the name")
    local awardRank
    kind, victim, awardRank, honor = HL.ParseHonorMessage(string.format(COMBATLOG_HONORAWARD, 15))
    check(kind == "award" and victim == nil and awardRank == nil and honor == 15, "award message parsed as honor, not a kill")
    local positional = HL.CompileFormat("%2$s gets %1$d honor")
    local caps = { ("Zed gets 9 honor"):match(positional.pattern) }
    check(positional.order[1] == 2 and positional.order[2] == 1 and caps[1] == "Zed" and caps[2] == "9", "positional format arguments keep their order")
    check(HL.ParseHonorMessage("something unrelated") == nil, "unrelated text is not a honor message")

    -- 1. WSG win. Scores are secret when the match ends, readable on a later UPDATE_BATTLEFIELD_SCORE.
    local wsg0 = HL.db.char.battlegrounds.WSG
    local played0, wins0, sessionHonor0 = wsg0.played, wsg0.wins, HL.db.char.session.WSG.honor
    local history0 = #HL.db.char.history
    mock.rank = { level = 3, earned = 120, threshold = 1050 }
    mock.pvp.columns = { { id = 42, name = "Flag Captures" }, { id = 44, name = "Flag Returns" } }
    enter("Warsong Gulch", 489)
    local m = HL:GetMatchState()
    check(HL:GetCurrentBG() == "WSG" and m.snapshot.honor == 8200, "entering a battleground snapshots honor")
    check(m.snapshot.marks.WSG == 12 and m.snapshot.marks.AB == 3 and m.snapshot.marks.AV == 0 and m.snapshot.marks.DI == 0, "snapshot has the four mark counts")
    check(m.snapshot.rank.level == 3 and m.snapshot.rank.earned == 120, "snapshot has rank progress")
    mock.pvp.matchActive, mock.pvp.duration = true, 30
    mock.fireEvent("PVP_MATCH_ACTIVE")
    check(m.joinChecked and not m.joinedInProgress, "a match that has just started is not joined in progress")
    mock.advance(300)
    gainHonor(100)
    gainHonor(350)
    mock.bagItems[20558] = 15
    mock.fireEvent("BAG_UPDATE_DELAYED")
    check(m.marks.WSG == 3, "mark delta recomputed on BAG_UPDATE_DELAYED")
    mock.rank.earned = 220
    mock.pvp.roster, mock.pvp.scoresSecret, mock.pvp.matchComplete, mock.pvp.matchActive = roster(), true, true, false
    mock.fireEvent("PVP_MATCH_COMPLETE", 1, 612)
    check(m.completed and m.result == "win", "winner 1 with team 1 is a win")
    check(m.sbState == "pending" and #HL.db.char.history == history0, "scoreboard secret at match end: not recorded yet")
    check(mock.pvp.requests > 0, "RequestBattlefieldScoreData was called")
    mock.advance(3)
    check(m.sbState == "pending", "still pending while the scores stay secret")
    mock.pvp.scoresSecret = false
    mock.fireEvent("UPDATE_BATTLEFIELD_SCORE")
    check(m.sbState == "accepted", "readable scoreboard accepted on UPDATE_BATTLEFIELD_SCORE")
    gainHonor(50) -- the end-of-game bonus
    mock.advance(2.5)
    check(not m.recorded, "not recorded before the 20 s window")
    mock.advance(20)
    check(m.recorded and #HL.db.char.history == history0 + 1, "recorded 20 s after completion")
    local game = lastGame()
    check(game.bgType == "WSG" and game.result == "win" and game.win == true, "result win")
    check(game.honor == 500, "honor is the measured sum including the bonus: " .. tostring(game.honor))
    check(game.marks == 3, "marks delta")
    check(game.rankPoints == 100, "rank point delta: " .. tostring(game.rankPoints))
    check(game.kb == 3 and game.hk == 12 and game.deaths == 2 and game.damage == 50000 and game.healing == 1200, "the player's scoreboard line")
    check(game.objectives["Flag Captures"] == 2 and game.objectives["Flag Returns"] == 4, "objective stats keyed by column name")
    check(game.teams[1].players == 2 and game.teams[1].kb == 4 and game.teams[1].hk == 17 and game.teams[1].deaths == 6, "own team summary")
    check(game.teams[0].players == 2 and game.teams[0].kb == 7 and game.teams[0].hk == 13 and game.teams[0].deaths == 9, "enemy team summary")
    check(game.teams[1][1] == nil and game.teams[0][1] == nil, "team summary has no per-player rows")
    check(game.scoreboard == true and game.joinedInProgress == nil and game.duration == 612, "scoreboard flag, not joined, duration from the event")
    check(HL.db.char.battlegrounds.WSG.played == played0 + 1 and HL.db.char.battlegrounds.WSG.wins == wins0 + 1, "stats updated")
    check(HL.db.char.session.WSG.honor == sessionHonor0 + 500, "session honor updated")
    leave()
    check(#HL.db.char.history == history0 + 1 and HL:GetCurrentBG() == nil, "leaving after recording adds nothing")

    -- 2. DI loss, rank level-up during the game (rank-point delta across a threshold).
    mock.bagItems[274895] = 0
    mock.rank = { level = 3, earned = 1000, threshold = 1200 } -- rank 3 is worth the 4th curve entry
    resetPvP()
    enter("Darkspear Islands", 2997)
    check(HL:GetCurrentBG() == "DI", "map 2997 is DI")
    mock.advance(200)
    gainHonor(120)
    mock.bagItems[274895] = 1
    mock.fireEvent("BAG_UPDATE_DELAYED")
    mock.rank = { level = 4, earned = 40, threshold = 1200 }
    mock.pvp.roster, mock.pvp.matchComplete = roster(), true
    mock.fireEvent("PVP_MATCH_COMPLETE", 0, 480)
    check(HL:GetMatchState().result == "loss" and HL:GetMatchState().sbState == "accepted", "winner 0 with team 1 is a loss; readable board accepted at once")
    leave() -- before the 20 s window: recorded on leaving
    game = lastGame()
    check(game.bgType == "DI" and game.result == "loss" and game.win == false, "DI loss recorded when leaving")
    check(game.rankPoints == 240, "rank delta across a level: 200 left + 40 into the next = " .. tostring(game.rankPoints))
    check(game.marks == 1 and game.honor == 120, "DI marks and honor")
    check(HL.db.char.battlegrounds.DI.losses == 1 and HL.db.char.battlegrounds.DI.wins == 0, "DI stats")
    -- Reaching rank n costs the first n curve entries: level L is worth curve[L + 1], with or without the rank module.
    check(HL.RankDelta({ level = 2, earned = 100, threshold = 1050 }, { level = 5, earned = 10 }) == 950 + 1200 + 1350 + 10, "rank delta spans skipped levels (rank module)")
    check(HL.RankDelta({ level = 3, earned = 1000 }, { level = 4, earned = 40 }) == 240, "rank delta across one level (rank module)")
    local savedRankModule = HL.Rank
    HL.Rank = nil
    check(HL.RankDelta({ level = 2, earned = 100 }, { level = 5, earned = 10 }) == 950 + 1200 + 1350 + 10, "rank delta fallback: curve[level + 1] per level")
    check(HL.RankDelta({ level = 3, earned = 1000, threshold = 1200 }, { level = 4, earned = 40 }) == 240, "rank delta fallback across a level-up")
    check(HL.RankDelta({ level = 0, earned = 100 }, { level = 1, earned = 5 }) == 650 + 5, "rank delta fallback from rank 0 uses the first curve entry")
    HL.Rank = savedRankModule

    -- 3. Leaving early is recorded as "left"; it does not count in the win rate.
    resetPvP()
    mock.bagItems[20559] = 3
    enter("Arathi Basin", 529)
    mock.advance(90)
    gainHonor(40)
    leave()
    game = lastGame()
    check(game.bgType == "AB" and game.result == "left" and game.win == false and game.scoreboard == false, "left early")
    check(game.honor == 40 and game.kb == nil, "left game keeps measured honor, has no scoreboard line")
    local ab = HL.db.char.battlegrounds.AB
    check(ab.left == 1 and ab.wins == 0 and ab.losses == 0 and ab.played == 1, "left counted apart")
    check(HL:GetDerivedStats("AB").winrate == 0, "a left game is not a loss in the win rate")

    -- 4. A draw.
    resetPvP()
    enter("Alterac Valley", 30)
    mock.advance(1500)
    mock.pvp.roster, mock.pvp.matchComplete = roster(), true
    mock.fireEvent("PVP_MATCH_COMPLETE", 255, 1500)
    leave()
    game = lastGame()
    check(game.bgType == "AV" and game.result == "draw" and game.scoreboard == true, "draw (winner 255)")
    check(HL.db.char.battlegrounds.AV.draws == 1 and HL.db.char.session.AV.draws == 1, "draw counted apart")
    check(HL:GetDerivedStats("AV").winrate == 0, "a draw is not in the win rate")
    HL:RecordGame("AB", true, 100, 10, 1, { result = "win" })
    check(HL:GetDerivedStats("AB").winrate == 100, "win rate counts wins and losses only: 1 win, 1 left = 100%")

    -- 5. Joined in progress.
    resetPvP()
    mock.pvp.matchActive, mock.pvp.duration = true, 540
    enter("Warsong Gulch", 489)
    check(HL:GetMatchState().joinedInProgress == true, "match already running 540 s on entry")
    mock.advance(100)
    mock.pvp.matchActive, mock.pvp.roster, mock.pvp.matchComplete = false, roster(), true
    mock.fireEvent("PVP_MATCH_COMPLETE", 1, 640)
    leave()
    game = lastGame()
    check(game.joinedInProgress == true and game.result == "win" and game.duration == 100, "joined-in-progress game keeps its own time")

    -- 6. The scoreboard never becomes readable.
    resetPvP()
    enter("Warsong Gulch", 489)
    mock.advance(60)
    mock.pvp.roster, mock.pvp.scoresSecret, mock.pvp.matchComplete = roster(), true, true
    mock.fireEvent("PVP_MATCH_COMPLETE", 1, 612)
    history0 = #HL.db.char.history
    m = HL:GetMatchState()
    mock.advance(13)
    check(m.sbState == "gaveup" and #HL.db.char.history == history0, "scoreboard abandoned after 12 s; game not recorded yet")
    leave()
    game = lastGame()
    check(#HL.db.char.history == history0 + 1 and game.result == "win" and game.scoreboard == false and game.kb == nil and game.teams == nil,
        "recorded without scoreboard stats")
    resetPvP()
    enter("Warsong Gulch", 489)
    mock.pvp.roster, mock.pvp.scoresSecret, mock.pvp.matchComplete = roster(), true, true
    mock.fireEvent("PVP_MATCH_COMPLETE", 1, 612)
    m = HL:GetMatchState()
    mock.advance(21)
    check(m.recorded and lastGame().scoreboard == false, "the 20 s timer records it too")
    leave()

    -- Winner fallbacks: no usable payload -> GetBattlefieldWinner -> BG chat text.
    resetPvP()
    enter("Arathi Basin", 529)
    mock.pvp.matchComplete, mock.pvp.winner = true, 0
    mock.fireEvent("PVP_MATCH_COMPLETE", mock.newSecret(), 100)
    check(HL:GetMatchState().result == "loss", "secret payload falls back to GetActiveMatchWinner once the match is complete")
    leave()
    resetPvP()
    enter("Arathi Basin", 529)
    mock.pvp.winner = 0 -- the client reports 0 while the match is not complete: not believed
    mock.pvp.bfWinner = 1
    mock.fireEvent("PVP_MATCH_COMPLETE", mock.newSecret(), 100)
    check(HL:GetMatchState().result == "win", "an incomplete match's API winner is ignored; GetBattlefieldWinner is next")
    leave()
    resetPvP()
    enter("Arathi Basin", 529)
    mock.fireEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL", "The Alliance wins!")
    check(HL:GetMatchState().completed and HL:GetMatchState().result == "win", "BG chat text names the winner as a last resort")
    mock.pvp.matchComplete = true
    mock.fireEvent("PVP_MATCH_COMPLETE", 0, 100)
    check(HL:GetMatchState().result == "loss", "the event's winner replaces a chat guess")
    leave()
    resetPvP()

    -- An unknown battleground map is tracked from day one under "MAP<id>".
    enter("Mystery Fields", 9999)
    check(HL:GetCurrentBG() == "MAP9999" and HL:GetBGDisplayName("MAP9999") == "Mystery Fields", "unknown pvp map gets a generic entry named from GetInstanceInfo")
    mock.pvp.roster, mock.pvp.matchComplete = roster(), true
    mock.fireEvent("PVP_MATCH_COMPLETE", 1, 300)
    leave()
    check(HL.db.char.battlegrounds.MAP9999.played == 1 and lastGame().bgType == "MAP9999", "generic battleground recorded")
    resetPvP()

    -- 7. /reload inside a battleground: the snapshot and the running sums survive.
    mock.bagItems[20558] = 15
    enter("Warsong Gulch", 489)
    mock.advance(10)
    gainHonor(75)
    mock.bagItems[20558] = 16
    mock.fireEvent("BAG_UPDATE_DELAYED")
    local snapHonor = HL:GetMatchState().snapshot.honor
    local beforeReload = #HL.db.char.history
    mock.advance(1)
    mock.fireEvent("PLAYER_LOGOUT")
    for i = #mock.frames, 1, -1 do mock.frames[i] = nil end -- the UI is rebuilt
    mock.timers = {}                                         -- timers die with the UI
    LibStub.libs, LibStub.minors = {}, {}                    -- a reload starts a fresh Lua state: no libraries yet
    HL = loadAddon()
    mock.fireEvent("ADDON_LOADED", "HonorLog")
    mock.fireEvent("PLAYER_LOGIN")
    mock.fireEvent("PLAYER_ENTERING_WORLD")
    m = HL:GetMatchState()
    check(HL.isReload == true, "second load counts as a reload")
    check(m and m.bgType == "WSG" and m.honorGained == 75 and m.snapshot.honor == snapHonor and m.snapshot.marks.WSG == 15 and m.marks.WSG == 1,
        "snapshot and running sums survive /reload")
    check(HL:GetCurrentBG() == "WSG" and #HL.db.char.history == beforeReload, "reload did not record a game")
    history0 = #HL.db.char.history
    gainHonor(25)
    mock.pvp.roster, mock.pvp.matchComplete = roster(), true
    mock.fireEvent("PVP_MATCH_COMPLETE", 1, 400)
    leave()
    check(#HL.db.char.history == history0 + 1 and lastGame().honor == 100 and lastGame().marks == 1, "game finished after the reload counts the honor from both halves")
    resetPvP()

    -- 8. World kills: the honor message plus PLAYER_PVP_KILLS_CHANGED.
    mock.deferTimers = false
    mock.pvp.sessionHK = 5
    mock.fireEvent("PLAYER_ENTERING_WORLD") -- baseline for the kill counter
    local world, charWorld = HL.db.char.worldPvP, HL.db.char.worldPvP
    local kills0, unknown0, kb0 = world.kills, world.unknownKills, world.killingBlows
    mock.fireEvent("PARTY_KILL", "Player-1-1", "Player-2-77")
    mock.fireEvent("CHAT_MSG_COMBAT_HONOR_GAIN", string.format(COMBATLOG_HONORGAIN, "EnemyMage", "Corporal", 21))
    mock.pvp.sessionHK = 6
    mock.fireEvent("PLAYER_PVP_KILLS_CHANGED")
    check(charWorld.kills == kills0 + 1 and charWorld.unknownKills == unknown0, "kill attributed from the honor message")
    check(charWorld.killingBlows == kb0 + 1, "readable PARTY_KILL by the player makes it a killing blow")
    check(HL.db.char.opponents.EnemyMage and HL.db.char.opponents.EnemyMage.kills == 1, "opponent entry created for the victim")
    check(charWorld.honorKill == 21, "kill honor split out")
    mock.fireEvent("CHAT_MSG_COMBAT_HONOR_GAIN", string.format(COMBATLOG_HONORAWARD, 15))
    check(charWorld.honorAward == 15 and charWorld.kills == kills0 + 1, "award message is honor, not a kill")
    mock.fireEvent("CHAT_MSG_COMBAT_HONOR_GAIN", mock.newSecret())
    mock.fireEvent("PARTY_KILL", mock.newSecret(), mock.newSecret())
    check(charWorld.kills == kills0 + 1, "secret message and GUIDs are ignored")
    local honorBefore = charWorld.honor
    gainHonor(21)
    check(charWorld.honor == honorBefore + 21, "honor gained outside a battleground is world honor")

    mock.deferTimers = true
    mock.timers = {}
    mock.pvp.sessionHK = 7 -- the counter first, the message a moment later
    mock.fireEvent("PLAYER_PVP_KILLS_CHANGED")
    mock.advance(0.5)
    mock.fireEvent("CHAT_MSG_COMBAT_HONOR_GAIN", string.format(COMBATLOG_HONORGAIN_NO_RANK, "EnemyHunter", "Private", 12))
    mock.advance(3)
    check(charWorld.kills == kills0 + 2 and HL.db.char.opponents.EnemyHunter and HL.db.char.opponents.EnemyHunter.kills == 1, "message after the counter step still attributes within the window")
    mock.units.target = { name = "EnemyRogue", class = "ROGUE", enemy = true, dead = true }
    mock.pvp.sessionHK = 8 -- no message: the dead enemy in sight
    mock.fireEvent("PLAYER_PVP_KILLS_CHANGED")
    mock.advance(3)
    check(charWorld.kills == kills0 + 3 and HL.db.char.opponents.EnemyRogue and HL.db.char.opponents.EnemyRogue.kills == 1
        and HL.db.char.opponents.EnemyRogue.class == "ROGUE", "kill attributed to the dead enemy in sight")
    mock.units.target = nil
    mock.pvp.sessionHK = 9 -- nobody to blame
    mock.fireEvent("PLAYER_PVP_KILLS_CHANGED")
    mock.advance(3)
    check(charWorld.kills == kills0 + 4 and charWorld.unknownKills == unknown0 + 1, "kill with no attribution is recorded as unknown")
    mock.pvp.sessionHK = 3 -- counter reset (new session): no kills, no error
    mock.fireEvent("PLAYER_PVP_KILLS_CHANGED")
    check(charWorld.kills == kills0 + 4, "a counter that goes down is a new session, not kills")

    -- 9. World death: a recap with a player killer.
    local deaths0 = charWorld.deaths
    mock.recap = {
        { timestamp = 100, sourceGUID = "Creature-0-1-1", sourceName = "Wolf" },
        { timestamp = 103, sourceGUID = "Player-2-99", sourceName = "EnemyMage" },
        { timestamp = 104, sourceGUID = "Player-2-77", sourceName = "EnemyRogue" },
    }
    mock.fireEvent("PLAYER_DEAD")
    mock.advance(1.5)
    check(charWorld.deaths == deaths0 + 1, "death with a player killer counted")
    check(HL.db.char.opponents.EnemyRogue.deaths == 1 and HL.db.char.opponents.EnemyMage.deaths == 0, "the latest player source is the killer")
    mock.recap = { { timestamp = 100, sourceGUID = "Creature-0-1-1", sourceName = "Wolf" } }
    mock.fireEvent("PLAYER_DEAD")
    mock.advance(5)
    check(charWorld.deaths == deaths0 + 1, "death by a creature is not a PvP death")
    mock.recap = {}

    -- The opponents table is capped at 500, oldest lastSeen first.
    for i = 1, 510 do HL:NoteOpponent("Cap" .. i, "MAGE", "kill") end
    local count = 0
    for _ in pairs(HL.db.char.opponents) do count = count + 1 end
    check(count == 500 and HL.db.char.opponents.Cap510 and not HL.db.char.opponents.Cap1, "opponents capped at 500, oldest dropped")
    check(#HL:GetTopOpponents(5) == 5, "top opponents list")
    local wholeSeconds = true
    for _, e in pairs(HL.db.char.opponents) do
        wholeSeconds = wholeSeconds and e.lastSeen == math.floor(e.lastSeen) and e.lastSeen > 1e9
    end
    check(wholeSeconds, "opponent lastSeen is stored as whole seconds (time())")

    -- 10. The honor cap warning fires once per crossing, from the currency's own max.
    mock.deferTimers = false
    local cap = mock.currencies[1792]
    cap.maxQuantity, cap.quantity = 30000, 22600
    mock.fireEvent("CURRENCY_DISPLAY_UPDATE", 1792, 22600, 0)
    check(countPrinted("Honor cap: ") == 0, "75% of a 30000 cap does not warn: the cap is read, not hardcoded")
    cap.maxQuantity = 25000
    mock.fireEvent("CURRENCY_DISPLAY_UPDATE", 1792, 22600, 0)
    mock.fireEvent("CURRENCY_DISPLAY_UPDATE", 1792, 22700, 100)
    check(countPrinted("Honor cap: ") == 1, "90% of the cap warns, once")
    cap.quantity = 5000
    mock.fireEvent("CURRENCY_DISPLAY_UPDATE", 1792, 5000, -17700)
    cap.quantity = 23000
    mock.fireEvent("CURRENCY_DISPLAY_UPDATE", 1792, 23000, 18000)
    check(countPrinted("Honor cap: ") == 2, "a new crossing warns again")
    cap.quantity = 9000
    mock.fireEvent("CURRENCY_DISPLAY_UPDATE", 1792, 9000, 0)

    -- Honor summary: today, week, session, per hour.
    local summary = HL:GetHonorSummary()
    check(summary.today > 0 and summary.week >= summary.today and summary.session > 0, "honor today / week / session measured")
    check(summary.cap == 25000 and summary.current == 9000, "honor summary reads the cap from the currency")
    HL.db.char.honorLog.weekEnd = time() - 5
    HL.db.char.honorLog.day = 19990101
    HL:AddHonorGain(10)
    summary = HL:GetHonorSummary()
    check(summary.week == 10 and summary.today == 10, "a new day and a new week start from zero")
    check(HL.db.char.honorLog.weekEnd > time(), "the week ends at the next weekly reset")

    -- The new slash commands and tooltips run.
    slash("history")
    slash("honor")
    slash("cap 80")
    check(HL.db.settings.honorCapWarnPct == 80, "cap percent is a setting")
    slash("cap 90")
    slash("test DI")
    slash("test kill")
    slash("test death")
    HL:ShowBGTooltip(HL.mainFrame.bgCards.WSG, "WSG")
    HL:ShowWorldTooltip(HL.mainFrame.worldCard)
    HL:UpdateMainFrame()

    ----------------------------------------------------------------------
    -- Round 2: the rank climb
    ----------------------------------------------------------------------
    local Rank = HL.Rank
    local CURVE = { 750, 900, 1050, 1200, 1350, 1500, 1650, 1800, 1950, 2100, 2350, 2500, 2650, 3000 }
    local function setRank(level, earned, cap, week, prevCap)
        mock.rank = { level = level, earned = earned, threshold = CURVE[level + 1] or 0 }
        mock.rankWindow.cap, mock.rankWindow.week = cap, week
        mock.rankWindow.prevCap = prevCap or math.max(0, cap - 1)
    end
    local function countPlain(text)
        local n = 0
        for _, line in ipairs(printed) do if line:find(text, 1, true) then n = n + 1 end end
        return n
    end
    local char = HL.db.char
    local savedHistory = char.history
    local function history(spec) -- spec: list of { result, rankPoints, hoursAgo }, newest first
        local h = {}
        for i, g in ipairs(spec) do
            h[i] = { bgType = "WSG", result = g[1], win = g[1] == "win", rankPoints = g[2], timestamp = time() - g[3] * 3600 }
        end
        char.history = h
    end
    local function measuredGames(n, wins, winPts, lossPts)
        local spec = {}
        for i = 1, n do
            local won = i <= wins
            spec[i] = { won and "win" or "loss", won and winPts or lossPts, i * 2 }
        end
        history(spec)
    end

    -- GetInfo maps the client's numbers and titles the rank for the faction.
    setRank(4, 300, 6, 3, 5)
    mock.faction = "Alliance"
    local info = Rank:GetInfo()
    check(info and info.rank == 4 and info.points == 300 and info.threshold == 1350, "GetInfo: rank, points, threshold")
    check(info.totalPoints == 3900 + 300, "GetInfo: total = total for the rank + points earned: " .. tostring(info.totalPoints))
    check(info.weekCapRank == 6 and info.weekCapTotal == 6750 and info.prevWeekCapRank == 5 and info.seasonMaxRank == 14, "GetInfo: cap fields")
    check(info.weekNumber == 3 and info.season == 2 and info.secondsToSeasonEnd == 30 * 86400 and info.secondsToWeeklyReset == 3 * 86400, "GetInfo: week, season, countdowns")
    check(info.capped == false and info.pointsLeftThisWeek == 2550, "GetInfo: not capped, points left this week")
    check(info.title == "Master Sergeant", "Alliance title for rank 4: " .. tostring(info.title))
    mock.faction = "Horde"
    check(Rank:GetInfo().title == "Senior Sergeant", "Horde title for rank 4")
    mock.faction = "Alliance"
    setRank(0, 100, 3, 1)
    check(Rank:GetInfo().title == "Unranked" and Rank:GetInfo().rank == 0, "rank 0 is Unranked")
    setRank(5, 0, 5, 3)
    check(Rank:GetInfo().capped == true and Rank:GetInfo().pointsLeftThisWeek == 0, "capped once the total reaches the cap total")

    -- TotalForRank: the client's number, else the curve.
    check(Rank:TotalForRank(6) == 6750 and Rank:TotalForRank(0) == 0, "TotalForRank from the client")
    local clientTotal = C_MajorFactions.GetTotalReputationForRenownLevel
    mock.removeTotalFn()
    local curveSum = 0
    for _, v in ipairs(CURVE) do curveSum = curveSum + v end
    check(Rank:TotalForRank(6) == 6750 and Rank:TotalForRank(14) == curveSum, "TotalForRank falls back to the curve")
    C_MajorFactions.GetTotalReputationForRenownLevel = clientTotal

    -- CapRankForWeek: client number now, curve later, shifted to agree, bounded by the season.
    setRank(4, 300, 6, 3, 5)
    info = Rank:GetInfo()
    check(Rank:CapRankForWeek(3, info) == 6 and Rank:CapRankForWeek(4, info) == 7 and Rank:CapRankForWeek(5, info) == 8, "cap by week follows the curve from the client's week")
    check(Rank:CapRankForWeek(8, info) == 12 and Rank:CapRankForWeek(10, info) == 14 and Rank:CapRankForWeek(30, info) == 14, "cap by week reaches 14 and stays")
    setRank(4, 300, 7, 3, 6) -- the client is a step ahead of the table
    check(Rank:CapRankForWeek(3) == 7 and Rank:CapRankForWeek(4) == 8, "the table is shifted so the current week agrees with the client")
    mock.rankWindow.seasonMax = 10
    check(Rank:CapRankForWeek(9) == 10, "never above the season maximum")
    mock.rankWindow.seasonMax = 14

    -- Pace: an estimate below 5 measured games, measured from 30.
    history({})
    local pace = Rank:GetPace()
    check(pace.estimated and pace.pointsPerWin == 100 and pace.pointsPerLoss == 25 and pace.measuredGames == 0 and pace.gamesPerDay == 0, "pace defaults with no games")
    measuredGames(4, 4, 500, 500)
    pace = Rank:GetPace()
    check(pace.estimated and pace.pointsPerWin == 100 and pace.measuredGames == 4, "4 measured games is still an estimate, with the default points")
    measuredGames(30, 20, 120, 30)
    local pad = char.history
    for i = 1, 10 do pad[#pad + 1] = { result = "win", rankPoints = 999, timestamp = time() - 100 * 3600 - i } end -- older than the 30
    pace = Rank:GetPace()
    check(not pace.estimated and pace.measuredGames == 30, "30 measured games is a measurement")
    check(pace.pointsPerWin == 120 and pace.pointsPerLoss == 30, "average points per win and loss over the last 30: " .. pace.pointsPerWin .. "/" .. pace.pointsPerLoss)
    check(math.abs(pace.winRate - 30 / 40) < 1e-9, "win rate over the decided games: " .. pace.winRate)
    check(pace.gamesPerDay > 9 and pace.gamesPerDay < 15, "games per day over the last 7 days: " .. pace.gamesPerDay)
    measuredGames(30, 20, 120, 30) -- clean set for the plans

    -- Plans.
    setRank(4, 300, 6, 3, 5)
    info = Rank:GetInfo()
    pace = Rank:GetPace()
    local now = time()
    local plan = Rank:PlanToRank(6, info, pace) -- this week allows it: pace decides
    check(plan.pointsNeeded == 2550 and plan.gamesNeeded == math.ceil(2550 / pace.pointsPerGame), "plan: points and games")
    check(plan.earliestWeekByCap == 3 and plan.earliestDateByCap >= now and plan.earliestDateByCap <= now + 2 and plan.limitedBy == "pace", "plan limited by pace")
    check(plan.projectedDateAtPace > now and plan.date == plan.projectedDateAtPace, "pace date is the plan date")
    plan = Rank:PlanToRank(8, info, pace) -- rank 8 opens in week 5
    check(plan.earliestWeekByCap == 5 and math.abs(plan.earliestDateByCap - (now + 3 * 86400 + 7 * 86400)) <= 2, "plan: cap date = reset + whole weeks")
    check(plan.limitedBy == "cap" and plan.date == plan.earliestDateByCap and plan.projectedDateAtPace < plan.earliestDateByCap, "plan limited by the cap")
    plan = Rank:PlanToRank(3, info, pace)
    check(plan.reached and plan.limitedBy == "reached" and plan.pointsNeeded == 0 and plan.gamesNeeded == 0, "plan for a rank already reached")
    plan = Rank:PlanToRank(4, info, pace)
    check(plan.reached, "the current rank counts as reached")
    mock.rankWindow.seasonMax = 10
    plan = Rank:PlanToRank(12, Rank:GetInfo(), pace)
    check(plan.limitedBy == "season" and not plan.reached and plan.pointsNeeded > 0, "target above the season maximum")
    mock.rankWindow.seasonMax = 14
    mock.seasonSeconds = 86400
    plan = Rank:PlanToRank(8, Rank:GetInfo(), pace)
    check(plan.limitedBy == "season", "a date later than the season end is limited by the season")
    mock.seasonSeconds = 86400 * 30
    history({})
    plan = Rank:PlanToRank(6)
    check(plan.projectedDateAtPace == nil and plan.limitedBy == "pace" and plan.date == plan.earliestDateByCap, "no recent games: no pace date")
    measuredGames(30, 20, 120, 30)

    -- Rewards: the first rank above the current one that has any.
    setRank(4, 300, 6, 3, 5)
    local nextRank, rewards = Rank:NextReward()
    check(nextRank == 8 and #rewards == 2 and rewards[1].description == "Wrist Seal" and rewards[1].icon == 1008, "next reward skips ranks without rewards")
    setRank(1, 0, 3, 1)
    check((Rank:NextReward()) == 2, "next reward from rank 1")
    setRank(8, 0, 9, 7)
    check(Rank:NextReward() == nil, "no reward left above rank 8")
    check(#Rank:GetRewards(5) == 0 and #Rank:GetRewards(8) == 2, "GetRewards")

    -- A rank-up fires one celebration.
    setRank(5, 0, 6, 3, 5)
    local celebBefore = countPlain("Sergeant Major")
    mock.fireEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 2800, 5, 4)
    check(countPlain("Sergeant Major") == celebBefore + 1, "rank-up prints one celebration")
    check(countPlain("Rank 5 \226\128\148 Sergeant Major") >= 1, "celebration reads Rank N - title")
    check(countPlain("Next reward at Rank 8") == 1 and countPlain("Alliance quartermasters") == 1, "celebration names the next reward and the vendor")
    mock.fireEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 2800, 5, 4)
    check(countPlain("Sergeant Major") == celebBefore + 1, "the same rank-up is not celebrated twice")
    mock.fireEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 1234, 9, 8)
    check(countPlain("Rank 9") == 0, "another faction's renown is ignored")

    -- The weekly cap alert: once a week, again the next week.
    char.rankCapAlertWeek = 0
    local capAlerts = function() return countPlain("Weekly rank cap reached") end
    local base = capAlerts()
    setRank(5, 0, 5, 3, 3) -- total 5250 = the cap total for rank 5
    mock.fireEvent("UPDATE_FACTION")
    check(capAlerts() == base + 1 and countPlain("Rank 6 opens in 3d 0h") >= 1, "cap alert names the next rank and the time")
    mock.fireEvent("CURRENCY_DISPLAY_UPDATE", 3468, 100, 10)
    mock.fireEvent("PLAYER_PVP_RANK_CHANGED", "player")
    check(capAlerts() == base + 1, "the cap alert fires once in a week")
    setRank(5, 0, 6, 4, 5) -- next week: a higher cap, not reached
    mock.fireEvent("UPDATE_FACTION")
    check(capAlerts() == base + 1, "no alert while under the new cap")
    setRank(6, 0, 6, 4, 5) -- reaches it
    mock.fireEvent("UPDATE_FACTION")
    check(capAlerts() == base + 2, "the cap alert fires again the next week")
    HL.db.settings.rankCapAlert = false
    setRank(7, 0, 7, 5, 6)
    mock.fireEvent("UPDATE_FACTION")
    check(capAlerts() == base + 2, "the setting turns the cap alert off")
    HL.db.settings.rankCapAlert = true

    -- The weekly log rolls over a week change and keeps 20 weeks.
    check(char.rankWeeks[3] and char.rankWeeks[4] and char.rankWeeks[4].startTotal == char.rankWeeks[3].endTotal,
        "a new week starts where the last one ended")
    check(char.rankWeeks[4].endTotal == 6750 and char.rankWeeks[4].capRank == 6, "the week log holds the end total and the cap")
    history({ { "win", 100, 1 }, { "win", 100, 5 }, { "loss", 25, 24 * 20 } })
    setRank(7, 0, 7, 5, 6)
    Rank:Refresh()
    check(char.rankWeeks[5].games == 2, "games this week are counted from the history: " .. tostring(char.rankWeeks[5].games))
    HL.db.settings.rankCapAlert = false
    for w = 6, 30 do
        setRank(7, 0, 7, w, 6)
        Rank:Refresh()
    end
    HL.db.settings.rankCapAlert = true
    local weeks = 0
    for _ in pairs(char.rankWeeks) do weeks = weeks + 1 end
    check(weeks == 20 and char.rankWeeks[30] and char.rankWeeks[11] and not char.rankWeeks[10], "the weekly log keeps the last 20 weeks")
    measuredGames(30, 20, 120, 30)

    -- The rank bar, the broker text and the slash command.
    setRank(4, 300, 6, 3, 5)
    HL.db.settings.showRankBar = true
    Rank:Refresh()
    local rui = HL.rankUI
    check(rui.bar:IsShown() and rui.tab:IsShown(), "rank bar and Rank tab shown with data")
    check(rui.bar.title:GetText() == "R4 Master Sergeant" and rui.bar.text:GetText() == "300 / 1,350 \194\183 cap R6", "rank bar text: " .. tostring(rui.bar.text:GetText()))
    check(rui.markerAt == nil, "no cap marker when the cap is beyond this rank")
    local tip = { lines = {} }
    function tip:AddLine(t) self.lines[#self.lines + 1] = t end
    function tip:AddDoubleLine(l, r) self.lines[#self.lines + 1] = l .. " " .. r end
    check(Rank:AddTooltipLines(tip), "tooltip fills with data")
    local tipText = table.concat(tip.lines, "\n")
    check(tipText:find("R5 Sergeant Major", 1, true) and tipText:find("R6", 1, true) and tipText:find("R7", 1, true), "tooltip plans the next 3 ranks")
    check(tipText:find("Next reward: Rank 8", 1, true) and tipText:find("Wrist Seal", 1, true), "tooltip names the next reward")
    check(tipText:find("Season ends in", 1, true) and tipText:find("Weekly reset in", 1, true), "tooltip has both countdowns")
    HL.db.settings.ldbFormat = "rank"
    HL:UpdateLDB()
    check(HL.ldb.text == "R4 Master Sergeant \194\183 22%", "broker rank text: " .. tostring(HL.ldb.text))
    HL.db.settings.ldbFormat = "games"
    HL:UpdateLDB()
    check(HL.ldb.text ~= "R4 Master Sergeant \194\183 22%", "the default broker text is unchanged")
    slash("rank")
    check(countPlain("Rank 4 Master Sergeant") >= 1, "/honorlog rank prints the summary")
    slash("rank 8")
    check(countPlain("Rank 8 Knight-Captain") >= 1 and countPlain("Limited by cap") >= 1, "/honorlog rank 8 prints the plan")
    slash("rank 2")
    check(countPlain("already reached") >= 1, "/honorlog rank for a reached rank")
    HL:ShowBGTooltip(HL.mainFrame.bgCards.WSG, "WSG")
    HL.ldb.OnTooltipShow(GameTooltip)

    -- The Rank tab with data.
    HL:SetExpanded(true)
    HL:SwitchTab("rank")
    check(HL.mainFrame.currentView == "rank" and rui.panel:IsShown() and not HL.mainFrame.expanded:IsShown(), "Rank tab shows the rank panel")
    check(#rui.panel.rows == 14 and rui.panel.rows[4].name:GetText() == "R4 Master Sergeant", "the table has ranks 1-14")
    check(rui.panel.rows[1].detail:GetText():find("reached", 1, true) and rui.panel.rows[8].detail:GetText():find("to go", 1, true), "reached and open rows")
    check(rui.panel.rows[8].tag:GetText() == "cap" and rui.panel.rows[5].tag:GetText() == "pace", "limited-by tags")
    check(rui.panel.rows[8].icons[2]:IsShown() and not rui.panel.rows[8].icons[3]:IsShown() and not rui.panel.rows[5].icons[1]:IsShown(), "reward icons per rank")
    check(rui.panel.lines[1]:GetText():find("Master Sergeant", 1, true), "summary line")
    -- (Not the Goals tab: GoalsPanel.lua's Update indexes DI in tables that only list AV, AB, WSG, EotS. Round 3.)
    HL:SwitchTab("stats")
    check(HL.mainFrame.currentView == "stats" and not rui.panel:IsShown() and not rui.tab.isActive, "switching to Stats hides the rank panel")
    HL:SetExpanded(false)

    -- No rank data: nothing errors and the rank UI hides.
    HL:SetExpanded(true)
    HL:SwitchTab("rank")
    mock.rankWindow.noData = true
    check(Rank:GetInfo() == nil and Rank:PlanToRank(8) == nil and Rank:BrokerText() == nil, "no data: GetInfo, PlanToRank and BrokerText give nil")
    local errorsBefore = #mock.handledErrors
    mock.fireEvent("UPDATE_FACTION")
    mock.fireEvent("CURRENCY_DISPLAY_UPDATE", 3468, 0, 0)
    mock.fireEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 2800, 1, 0)
    mock.fireEvent("PLAYER_PVP_RANK_CHANGED", "player")
    HL:UpdateMainFrame()
    HL:UpdateLDB()
    check(not rui.bar:IsShown() and not rui.tab:IsShown() and not rui.barActive, "no data: the rank bar and the Rank tab hide")
    check(HL.mainFrame.currentView ~= "rank" and not rui.panel:IsShown(), "no data: the Rank view falls back to Stats")
    rui.panel:Update(nil)
    check(rui.panel.lines[1]:GetText():find("No PvP rank data", 1, true), "the Rank panel builds without data")
    slash("rank")
    check(countPlain("No PvP rank data") >= 1 and #mock.handledErrors == errorsBefore, "/honorlog rank without data")
    mock.rankWindow.noData = false
    setRank(4, 300, 6, 3, 5)
    Rank:Refresh()
    check(rui.bar:IsShown() and rui.tab:IsShown(), "the rank UI returns when data does")
    HL:SetExpanded(false)

    -- Options: the stale Eye of the Storm toggle is gone; rank settings exist.
    check(_G.HonorLogDICheck and not _G.HonorLogEotSCheck, "options: Darkspear Islands card toggle replaces Eye of the Storm")
    check(_G.HonorLogRankBarCheck and _G.HonorLogRankCapCheck and _G.HonorLogLDBFormatDropdown, "options: rank bar, cap alert and broker format")
    char.history = savedHistory
    check(not printedMatching("HonorLog ERROR"), "rank tests reported an error: " .. tostring(printedMatching("HonorLog ERROR")))

    ----------------------------------------------------------------------
    -- Round 3: gear goals on the Forever reward model
    do
        local GearDB = HL.GearDB
        local function near(a, b, tol) return a ~= nil and math.abs(a - b) <= (tol or 2) end
        local function rowOf(gp, kind, bg)
            for _, r in ipairs(gp.rows) do if r.kind == kind and r.bg == bg then return r end end
        end
        local function missingKinds(gp)
            local out = {}
            for _, r in ipairs(gp.missing) do out[#out + 1] = r.kind end
            return table.concat(out, ",")
        end
        -- Ids from the generated database (Alliance warrior, so the mock's faction and class fit).
        local BLUE, EPIC, WRIST_EPIC, REP_ITEM, MULTI_REP, LEGACY_TABARD, HORDE_BLUE = 272738, 272787, 272790, 271903, 17349, 19032, 272477
        check(GearDB[BLUE].parts == nil and GearDB[EPIC].parts[1] == BLUE and GearDB[EPIC].parts[2] == 275241, "fixture ids: blue piece, epic with its Seal")
        check(GearDB[MULTI_REP].rep.faction == nil and GearDB[REP_ITEM].rep.faction == 2799 and GearDB[LEGACY_TABARD].legacy, "fixture ids: reputation items")

        -- A known player: Alliance warrior, rank 4, 8200 honor, measured pace of 12 games a day.
        mock.faction = "Alliance"
        setRank(4, 300, 6, 3, 5)
        mock.seasonSeconds = 86400 * 100
        mock.currencies[1792].quantity = 8200
        mock.bagItems = { [20560] = 5, [20558] = 12, [20559] = 3, [274895] = 0 }
        mock.bagContents, mock.equipped, mock.reputation, mock.money = {}, {}, {}, 123456
        local stats = HL.db.char.battlegrounds
        stats.AV.played, stats.AV.honorLifetime, stats.AV.marksLifetime = 10, 5000, 30
        stats.WSG.played, stats.WSG.honorLifetime, stats.WSG.marksLifetime = 10, 3000, 20
        stats.AB.played, stats.AB.honorLifetime, stats.AB.marksLifetime = 10, 2000, 10
        stats.DI.played, stats.DI.honorLifetime, stats.DI.marksLifetime = 0, 0, 0
        measuredGames(30, 20, 120, 30)
        char.goals.items, char.goals.completed = {}, {}
        HonorLogDB.scannedGear = {}
        check(near(Rank:GetPace().gamesPerDay, 12, 0.5), "test pace is about 12 games a day: " .. tostring(Rank:GetPace().gamesPerDay))

        -- Accessors: no season or arena logic is left; names come from the client once cached.
        check(HL.SEASONS == nil and HL.ARCHIVED_SEASONS == nil and HL.IsSeasonAvailable == nil and HL.GetCurrentArenaPoints == nil, "the TBC season and arena code is gone")
        local item = HL:GetGearItem(BLUE)
        check(item.itemID == BLUE and item.honor == 9000 and item.marks.AV == 15 and item.name == "Item " .. BLUE and not item.scanned, "GetGearItem: generated entry, client name")
        check(HL:GetGearItem(12345678) == nil, "GetGearItem: unknown id")
        check(HL:IsGearAvailable(BLUE) and not HL:IsGearAvailable(MULTI_REP), "legacy items are unavailable until a scan sees them")

        -- A blue piece: honor plus marks, partly affordable.
        local gp = HL:GetGoalProgress(BLUE)
        check(gp.honor.needed == 9000 and gp.honor.current == 8200 and gp.honor.remaining == 800, "blue piece: honor row")
        check(gp.marks.AV.needed == 15 and gp.marks.AV.current == 5 and gp.marks.AV.remaining == 10 and gp.marks.WSG == nil, "blue piece: AV marks row only")
        check(gp.gold.needed == 0 and gp.rank == nil and gp.rep == nil and not gp.isComplete, "blue piece: no gold, rank or reputation row")
        check(missingKinds(gp) == "honor,marks" and #gp.rows == 4 and gp.level and gp.level.met, "blue piece: missing honor and marks, a met level row: " .. missingKinds(gp))
        check(gp.honor.cap == 25000 and not gp.honor.overCap, "the honor cap comes from the currency")
        check(gp.totalGamesNeeded == 4 and gp.readyLimitedBy == "marks" and near(gp.readyDate, time() + math.floor(4 / Rank:GetPace().gamesPerDay * 86400), 5),
            "blue piece: ready date from the marks rate: " .. tostring(gp.totalGamesNeeded) .. " " .. tostring(gp.readyLimitedBy))
        mock.bagItems[20560] = 15
        mock.currencies[1792].quantity = 9000
        gp = HL:GetGoalProgress(BLUE)
        check(gp.isComplete and #gp.missing == 0 and gp.readyLimitedBy == "ready" and near(gp.readyDate, time()), "blue piece: complete when honor and marks are in hand")
        mock.bagItems[20560], mock.currencies[1792].quantity = 5, 8200

        -- An epic: blue piece plus Seal, rank-gated.
        local plan = Rank:PlanToRank(13)
        check(plan and plan.limitedBy == "cap" and plan.earliestWeekByCap, "the rank 13 plan is limited by the weekly cap in this setup")
        gp = HL:GetGoalProgress(EPIC)
        check(gp.parts and #gp.parts == 2 and gp.parts[1].role == "blue" and gp.parts[2].role == "seal" and not gp.parts[1].owned and not gp.parts[2].owned, "epic: two parts, neither owned")
        check(gp.honor.needed == 9000 + 2650 and gp.marks.AV.needed == 15, "epic: the summed cost")
        check(gp.rank.needed == 13 and gp.rank.current == 4 and not gp.rank.met and gp.rank.limitedBy == "cap" and gp.rank.week == plan.earliestWeekByCap, "epic: rank row with the plan")
        check(missingKinds(gp) == "honor,marks,rank", "epic: missing honor, marks and rank: " .. missingKinds(gp))
        check(gp.readyLimitedBy == "cap" and gp.readyDate == plan.date, "epic: the ready date is limited by the cap, as the rank plan says")
        -- Blue piece in the bags: only the Seal's honor is left.
        mock.bagContents = { BLUE }
        gp = HL:GetGoalProgress(EPIC)
        check(gp.parts[1].owned and not gp.parts[2].owned, "epic: the blue piece in the bags counts as owned")
        check(gp.honor.needed == 2650 and gp.honor.remaining == 0 and gp.marks.AV == nil, "epic with the blue piece owned: only the Seal's honor is left")
        check(gp.rank.needed == 13 and missingKinds(gp) == "rank", "epic with the blue piece owned: only the rank is missing: " .. missingKinds(gp))
        -- Worn counts too; the Seal in the bags drops the rank gate (it is already bought).
        mock.bagContents, mock.equipped = { 275241 }, { [1] = BLUE }
        gp = HL:GetGoalProgress(EPIC)
        check(gp.parts[1].owned and gp.parts[2].owned and gp.honor.needed == 0 and gp.rank == nil and gp.isComplete, "epic: worn blue piece and Seal in the bags are both paid")
        mock.bagContents, mock.equipped = {}, {}
        -- At rank 13 the gate is met and the date is the rate's.
        setRank(13, 0, 13, 9, 12)
        gp = HL:GetGoalProgress(EPIC)
        check(gp.rank.met and gp.readyLimitedBy ~= "cap" and gp.readyLimitedBy ~= "rank", "epic: rank met, no rank limit")
        setRank(4, 300, 6, 3, 5)
        -- No rank data: the row exists, is unknown and short, and nothing errors.
        mock.rankWindow.noData = true
        gp = HL:GetGoalProgress(EPIC)
        check(gp.rank and gp.rank.known == false and not gp.rank.met and not gp.isComplete, "epic without rank data: the rank row is unknown")
        mock.rankWindow.noData = false
        -- A rank gate no season can open
        mock.rankWindow.seasonMax = 10
        gp = HL:GetGoalProgress(EPIC)
        check(gp.readyDate == nil and gp.readyLimitedBy == "season", "epic beyond the season maximum: no date, limited by the season")
        mock.rankWindow.seasonMax = 14
        -- A scan of the parts flows into the epic's cost
        HonorLogDB.scannedGear[BLUE] = { honor = 13500, marks = { AV = 15 }, gold = 0, seen = 1, npc = "t" }
        check(HL:GetGoalProgress(EPIC).honor.needed == 13500 + 2650, "a scanned part price flows into the epic's cost")
        HonorLogDB.scannedGear = {}

        -- Reputation: standing below and at the requirement.
        gp = HL:GetGoalProgress(REP_ITEM)
        check(gp.rep.needed == 5 and gp.rep.faction == 2799 and gp.rep.known and gp.rep.current == 0 and not gp.rep.met, "reputation item: faction not met yet")
        check(gp.gold.needed == GearDB[REP_ITEM].gold and gp.gold.remaining == 0 and missingKinds(gp) == "rep" and not gp.isComplete, "reputation item: gold in hand, the standing is missing")
        mock.reputation[2799] = 4
        gp = HL:GetGoalProgress(REP_ITEM)
        check(gp.rep.current == 4 and not gp.rep.met and not gp.isComplete, "reputation below the requirement (Neutral < Friendly)")
        mock.reputation[2799] = 5
        gp = HL:GetGoalProgress(REP_ITEM)
        check(gp.rep.current == 5 and gp.rep.met and gp.isComplete and gp.readyLimitedBy == "ready", "reputation at the requirement")
        mock.money = 1000
        gp = HL:GetGoalProgress(REP_ITEM)
        check(missingKinds(gp) == "gold" and gp.readyDate and gp.readyLimitedBy == "gold", "gold and reputation have no rate: today, named for what holds it")
        mock.money = 123456
        -- A multi-faction reputation item shows the requirement without progress.
        gp = HL:GetGoalProgress(MULTI_REP)
        check(gp.rep and gp.rep.faction == nil and gp.rep.known == false and gp.rep.current == nil and gp.rep.standingName == "Friendly", "multi-faction item: the requirement, no progress")
        check(#gp.unverified == 1 and #gp.missing == 0 and gp.isComplete, "multi-faction item: unverified, not counted as short")

        -- The waterfall across three goals.
        local W1, W2, W3 = BLUE, nil, nil
        for _, entry in ipairs(HL:GetPickerItems({ class = "WARRIOR", source = "HONOR", showUnverified = true })) do
            if entry.itemID ~= BLUE and not W2 and entry.data.honor == 9350 then W2 = entry.itemID
            elseif entry.itemID ~= BLUE and not W3 and entry.data.honor == 7500 and entry.data.marks and entry.data.marks.WSG then W3 = entry.itemID end
        end
        check(W2 and W3, "waterfall fixture: a chest (AB) and a hands piece (WSG)")
        for _, id in ipairs({ W1, W2, W3 }) do check(HL:AddGoal(id), "goal added: " .. id) end
        HL.db.settings.goalProgressMode = "shared"
        local shared = HL:GetAllGoalsProgress()
        check(#shared == 3 and shared[1].honor.current == 8200 and shared[2].honor.current == 8200 and shared[3].honor.current == 8200, "shared mode: every goal sees all the honor")
        HL.db.settings.goalProgressMode = "waterfall"
        local fall = HL:GetAllGoalsProgress()
        check(#fall == 3 and fall[1].honor.current == 8200 and fall[2].honor.current == 0 and fall[3].honor.current == 0, "waterfall: the first goal takes the honor")
        check(fall[1].marks.AV.current == 5 and fall[2].marks.AB.current == 3 and fall[3].marks.WSG.current == 10, "waterfall: marks go to the goals that need them")
        check(fall[1].honor.remaining == 800 and fall[2].honor.remaining == 9350 and fall[3].honor.remaining == 7500, "waterfall: what each goal is still short")
        check(fall[3].totalGamesNeeded >= fall[2].totalGamesNeeded and fall[2].totalGamesNeeded >= fall[1].totalGamesNeeded, "waterfall: later goals wait for the ones above")
        check(fall[3].readyDate >= fall[1].readyDate, "waterfall: later goals are ready no earlier")
        local wf2 = HL:GetAllGoalsProgressWaterfall()
        check(#wf2 == 3 and wf2[1].itemID == W1, "GetAllGoalsProgressWaterfall returns the goals in order")
        local totals = HL:GetGoalsTotals(fall)
        check(totals.honorNeeded == 9000 + 9350 + 7500 and totals.honorCurrent == 8200 and totals.percent < 100 and totals.games > 0, "goal totals")
        HL.db.settings.goalProgressMode = "shared"

        -- Honor-cap advice
        check(HL:GetHonorCapAdvice() == nil, "no cap advice at 8200 honor")
        mock.currencies[1792].quantity = 24800
        mock.bagItems[20560] = 15
        local advice = HL:GetHonorCapAdvice()
        check(advice and advice.text:find("spend before you cap", 1, true) and advice.goal and advice.goal.itemID == W1 and advice.current == 24800, "cap advice fires and names the first affordable goal")
        check(advice.text:find(HL:GetGearName(W1), 1, true), "the advice names the goal")
        mock.currencies[1792].quantity = 22600 -- 90.4% of the cap, and the next game would not pass it
        check(HL:GetHonorCapAdvice() ~= nil, "cap advice also fires at the warning percentage")
        mock.currencies[1792].quantity = 21000
        check(HL:GetHonorCapAdvice() == nil, "no advice below the warning percentage")
        mock.currencies[1792].quantity = 24800
        HL.db.settings.goalCapAdvice = false
        check(HL:GetHonorCapAdvice() == nil, "the setting turns the advice off")
        HL.db.settings.goalCapAdvice = true
        slash("goal advice")
        check(countPlain("spend before you cap") >= 1, "/honorlog goal advice prints it")

        -- The Goals tab renders with goals present (the crash) and with none.
        HL:SetExpanded(true)
        HL:SwitchTab("goals")
        local goalsPanel = HL.mainFrame.goalsPanel
        local errs = #mock.handledErrors
        HL:UpdateGoalsPanel()
        check(HL.mainFrame.currentView == "goals" and goalsPanel:IsShown(), "the Goals tab shows its panel")
        check(goalsPanel.adviceBar:IsShown() and goalsPanel.adviceBar.text:GetText():find("spend before you cap", 1, true), "the goals header warns before the cap")
        local card1 = goalsPanel.goalCards[1]
        check(card1:IsShown() and card1.currencyLine:GetText():find("Honor", 1, true) and card1.statusLine:GetText():find("Ready to purchase", 1, true), "a ready goal card")
        check(goalsPanel.totalsText:GetText():find("Honor", 1, true), "the totals bar reads: " .. tostring(goalsPanel.totalsText:GetText()))
        mock.currencies[1792].quantity = 8200
        mock.bagItems[20560] = 5
        HL:UpdateGoalsPanel()
        check(not goalsPanel.adviceBar:IsShown(), "the header warning goes away")
        check(card1.statusLine:GetText():find("ready", 1, true), "a goal card shows its ready date: " .. tostring(card1.statusLine:GetText()))
        HL:UpdateGoalsCompact()
        -- An epic card: the two parts as sub-rows, the rank badge, rank locked until a week
        HL:AddGoal(EPIC)
        mock.bagContents = { BLUE }
        HL:UpdateGoalsPanel()
        local epicCard = goalsPanel.goalCards[4]
        check(epicCard.partRows[1]:IsShown() and epicCard.partRows[1]:GetText():find("owned", 1, true) and epicCard.partRows[2]:IsShown() and not epicCard.partRows[2]:GetText():find("owned", 1, true), "epic card: blue piece owned, Seal missing")
        check(epicCard.partRows[2]:GetText():find("2,650", 1, true) or epicCard.partRows[2]:GetText():find("2650", 1, true), "epic card: the Seal's cost")
        check(epicCard.statusLine:GetText():find("locked until week " .. plan.earliestWeekByCap, 1, true), "epic card: locked until week N: " .. tostring(epicCard.statusLine:GetText()))
        check(epicCard.currencyLine:GetText():find("Rank 4/13", 1, true), "epic card: rank row")
        check(not goalsPanel.goalCards[1].partRows[1]:IsShown(), "a blue piece card has no part rows")
        mock.rankWindow.cap = 14 -- the cap no longer limits: a date instead
        local pg = HL:GetGoalProgress(EPIC)
        check(pg.rank.limitedBy ~= "cap", "no cap limit with a high weekly cap")
        HL:UpdateGoalsPanel()
        check(epicCard.statusLine:GetText():find("Rank 13 \194\183", 1, true), "epic card: Rank N date badge: " .. tostring(epicCard.statusLine:GetText()))
        mock.rankWindow.cap = 6
        mock.bagContents = {}
        HL:RemoveGoal(EPIC)
        -- Reputation cards, multi-faction included
        HL:AddGoal(REP_ITEM)
        HL:AddGoal(MULTI_REP)
        HL:UpdateGoalsPanel()
        check(goalsPanel.goalCards[4].currencyLine:GetText():find("Neutral/Friendly", 1, true) or goalsPanel.goalCards[4].currencyLine:GetText():find("Friendly", 1, true), "reputation card")
        check(goalsPanel.goalCards[5].currencyLine:GetText():find("Friendly reputation", 1, true), "multi-faction card: requirement only")
        -- Tooltip text paths
        goalsPanel.goalCards[1]:GetScript("OnEnter")(goalsPanel.goalCards[1])
        goalsPanel.totalsBar:GetScript("OnEnter")(goalsPanel.totalsBar)
        HL:RemoveGoal(REP_ITEM)
        HL:RemoveGoal(MULTI_REP)
        -- Waterfall mode renders too
        HL.db.settings.goalProgressMode = "waterfall"
        HL:UpdateGoalsPanel()
        HL.db.settings.goalProgressMode = "shared"
        -- With none
        for _, id in ipairs({ W1, W2, W3 }) do HL:RemoveGoal(id) end
        HL:UpdateGoalsPanel()
        HL:UpdateGoalsCompact()
        check(goalsPanel.emptyState:IsShown() and not goalsPanel.totalsBar:IsShown(), "the Goals tab with no goals shows the empty state")
        check(#mock.handledErrors == errs and not printedMatching("HonorLog ERROR"), "the Goals tab raised no error: " .. tostring(mock.handledErrors[errs + 1]))
        HL:SwitchTab("stats")
        HL:SetExpanded(false)

        -- The picker: faction and class defaults, legacy items, filters.
        HL:ShowGoalPicker()
        local picker = _G.HonorLogGoalPicker
        check(picker and picker.filters.class == "WARRIOR" and picker:IsShown(), "the picker opens on the player's class")
        check(#picker.shownItems > 0, "the picker lists items: " .. tostring(#picker.shownItems) .. " " .. tostring(mock.handledErrors[1]) .. tostring(picker.filters.class))
        local function listed(id)
            for _, e in ipairs(picker.shownItems) do if e.itemID == id then return true end end
            return false
        end
        local otherFaction, otherClass = 0, 0
        for _, e in ipairs(picker.shownItems) do
            if e.data.faction == "Horde" then otherFaction = otherFaction + 1 end
            if e.data.class and e.data.class ~= "WARRIOR" then otherClass = otherClass + 1 end
        end
        check(otherFaction == 0 and not listed(HORDE_BLUE), "the faction filter hides the other faction")
        check(otherClass == 0 and listed(BLUE) and listed(EPIC), "the class default shows the player's class only")
        picker.filters.class = nil
        picker:RefreshItems()
        local mages = 0
        for _, e in ipairs(picker.shownItems) do if e.data.class == "MAGE" then mages = mages + 1 end end
        check(mages > 0 and not listed(HORDE_BLUE), "class 'any' shows other classes, still not the other faction")
        mock.faction = "Horde"
        picker:RefreshItems()
        check(listed(HORDE_BLUE) and not listed(BLUE), "a Horde player sees Horde items and not Alliance ones")
        mock.faction = "Alliance"
        picker.filters.class = "WARRIOR"
        picker:RefreshItems()
        check(not listed(MULTI_REP), "a legacy item is hidden")
        picker.filters.unverified = true
        picker:RefreshItems()
        check(listed(MULTI_REP), "show unverified lists it")
        picker.filters.unverified = false
        HonorLogDB.scannedGear[MULTI_REP] = { honor = 0, marks = {}, gold = 500, seen = 1, npc = "t" }
        picker:RefreshItems()
        check(listed(MULTI_REP) and HL:IsGearAvailable(MULTI_REP) and HL:GetGearItem(MULTI_REP).stocked, "a scan that saw it stocked shows a legacy item")
        HonorLogDB.scannedGear = {}
        picker.filters.slot, picker.filters.source = "HEAD", "UPGRADE"
        picker:RefreshItems()
        local ok = #picker.shownItems > 0
        for _, e in ipairs(picker.shownItems) do ok = ok and e.data.slot == "HEAD" and e.data.source == "UPGRADE" end
        check(ok and listed(EPIC) and not listed(BLUE), "slot and source filters")
        picker.filters.slot, picker.filters.source = nil, nil
        picker.filters.armor = "CLOTH"
        picker.filters.class = nil
        picker:RefreshItems()
        ok = #picker.shownItems > 0
        for _, e in ipairs(picker.shownItems) do ok = ok and e.data.armor == "CLOTH" end
        check(ok, "the armour filter")
        picker.filters.armor, picker.filters.class = nil, "WARRIOR"
        picker.filters.search = "item " .. BLUE -- the mock client names every item "Item <id>"
        picker:RefreshItems()
        check(#picker.shownItems == 1 and listed(BLUE), "the name search narrows the list: " .. tostring(#picker.shownItems))
        picker.filters.search = ""
        HL:AddGoal(BLUE)
        picker:RefreshItems()
        check(not listed(BLUE), "a goal is not offered again")
        HL:RemoveGoal(BLUE)
        picker:Hide()

        -- A vendor scan overrides a generated cost and marks the item stocked.
        MerchantFrame:Show()
        mock.units.npc = { name = "Test Quartermaster" }
        mock.merchant.items = {
            { id = BLUE, name = "Premier Plate Helm", price = 0, ext = true, costs = {
                { link = "|cff1eff00|Hcurrency:1792:0|h[Honor]|h|r", count = 13500, name = "Honor" },
                { link = "|cff1eff00|Hitem:20560::::::::60|h[Alterac Valley Mark of Honor]|h|r", count = 15, name = "AV" } } },
            { id = LEGACY_TABARD, name = "Stormpike Battle Tabard", price = 12000, ext = false, costs = {} },
            { id = 99999999, name = "Linen Cloth", price = 5, ext = false, costs = {} },
            { id = 88888888, name = "Brand New PvP Thing", price = 0, ext = true, costs = {
                { link = "|Hcurrency:1792:0|h[Honor]|h", count = 100 } } },
        }
        check(HL:ScanCurrentVendor() == 3, "the scan keeps database items and new honor items, not Linen Cloth")
        local scanned = HonorLogDB.scannedGear[BLUE]
        check(scanned.honor == 13500 and scanned.marks.AV == 15 and scanned.gold == 0 and scanned.npc == "Test Quartermaster" and scanned.seen, "scan record: honor, marks, gold, seen, npc")
        item = HL:GetGearItem(BLUE)
        check(item.honor == 13500 and item.scanned and item.stocked and GearDB[BLUE].honor == 9000, "a scanned cost overrides the generated one, which is untouched")
        check(HL:GetGoalProgress(BLUE).honor.needed == 13500, "progress uses the scanned cost")
        check(HonorLogDB.scannedGear[LEGACY_TABARD].gold == 12000 and HL:IsGearAvailable(LEGACY_TABARD), "a legacy item seen in stock becomes available")
        check(HonorLogDB.scannedGear[99999999] == nil and HonorLogDB.scannedGear[88888888].honor == 100, "scan filter")
        slash("scan export")
        check(countPlain("honor 9000 -> 13500") >= 1 and countPlain("NEW Brand New PvP Thing") + countPlain("NEW item 88888888") >= 1, "scan export prints differences from the generated data")
        check(countPlain("stocked (generated data says legacy)") >= 1, "scan export flags a legacy item seen stocked")
        slash("scan status")
        slash("scan clear")
        check(next(HonorLogDB.scannedGear) == nil, "scan clear")

        -- Opening a vendor that sells database items scans it quietly and prints one line.
        local function openVendor() mock.fireEvent("MERCHANT_SHOW"); mock.flushTimers() end
        local manualScans = countPlain("Scanned ")
        mock.advance(1000)
        openVendor()
        check(HonorLogDB.scannedGear[BLUE] and HonorLogDB.scannedGear[BLUE].honor == 13500, "auto scan at a GearDB vendor stores the prices")
        check(countPlain("updated prices for 3 PvP items from Test Quartermaster") == 1, "auto scan prints the one-line summary")
        check(countPlain("Scanned ") == manualScans, "the auto scan is quiet apart from that line")
        openVendor()
        check(countPlain("updated prices for") == 1, "the same NPC is not scanned twice within 10 minutes")
        mock.advance(599)
        openVendor()
        check(countPlain("updated prices for") == 1, "still guarded at 599 seconds")
        mock.advance(2)
        openVendor()
        check(countPlain("updated prices for") == 2, "scanned again after 10 minutes")
        mock.units.npc = { name = "Other Quartermaster" }
        openVendor()
        check(countPlain("updated prices for 3 PvP items from Other Quartermaster") == 1, "a different NPC is not guarded")
        mock.advance(700)
        HL.db.settings.autoVendorScan = false
        openVendor()
        check(countPlain("updated prices for") == 3, "the setting turns the auto scan off")
        HL.db.settings.autoVendorScan = true
        HL:ClearScannedData()
        local normal = { { id = 99999999, name = "Linen Cloth", price = 5, ext = false, costs = {} } }
        local saved = mock.merchant.items
        mock.merchant.items = normal
        mock.units.npc = { name = "Innkeeper" }
        mock.advance(700)
        openVendor()
        check(countPlain("updated prices for") == 3 and next(HonorLogDB.scannedGear) == nil, "a normal merchant is not scanned")
        mock.merchant.items = saved
        mock.units.npc = { name = "Test Quartermaster" }
        check(_G.HonorLogAutoScanCheck, "options: auto vendor scan checkbox")
        MerchantFrame:Hide()
        local noWindow = countPlain("No vendor window open")
        check(HL:ScanCurrentVendor() == 0 and countPlain("No vendor window open") == noWindow + 1, "no vendor open: nothing scanned")

        -- Options carry the goal settings.
        check(_G.HonorLogGoalCapAdviceCheck and _G.HonorLogGoalUnverifiedCheck and _G.HonorLogWaterfallCheck, "options: goal settings")
        local optionsSource = io.open(ROOT .. "/UI/Options.lua"):read("*a")
        check(not optionsSource:find("BCC", 1, true) and optionsSource:find("WoW Forever", 1, true), "the options subtitle names WoW Forever")

        char.goals.items, char.goals.completed = {}, {}
        measuredGames(30, 20, 120, 30)
        mock.seasonSeconds = 86400 * 30
        mock.bagItems = { [20558] = 12, [20559] = 3 }
        mock.currencies[1792].quantity = 8200
    end

    ----------------------------------------------------------------------
    -- Round 5: rank that tells the truth
    ----------------------------------------------------------------------
    do
        local Util = HL.Util
        local savedHist, savedLevel = char.history, mock.level
        local savedRank, savedWindow = mock.rank, { cap = mock.rankWindow.cap, week = mock.rankWindow.week, prevCap = mock.rankWindow.prevCap }
        local function near2(a, b) return math.abs(a - b) < 1e-6 end

        -- Util: the shared readers, copies, chat helpers and the string table.
        check(Util.num(5) == 5 and Util.num("5") == nil and Util.num(mock.newSecret()) == nil, "Util.num: numbers only, never a secret")
        check(Util.str("a") == "a" and Util.str(5) == nil and Util.str(mock.newSecret()) == nil, "Util.str: strings only, never a secret")
        check(Util.isSecret(mock.newSecret()) == true and Util.isSecret(1) == false, "Util.isSecret")
        local c1, c2 = Util.call(function(a, b) return a + b, a * b end, 3, 4)
        check(c1 == 7 and c2 == 12, "Util.call returns the results")
        check(Util.call(function() error("boom") end) == nil and Util.call(nil) == nil, "Util.call: an error or a non-function gives nothing")
        local orig = { a = 1, nested = { b = 2 } }
        local copy = Util.DeepCopy(orig)
        copy.nested.b = 9
        check(orig.nested.b == 2 and copy.a == 1, "Util.DeepCopy copies nested tables")
        local target = { a = 5, nested = {} }
        Util.DeepMerge(target, { a = 1, c = 3, nested = { b = 2 } })
        check(target.a == 5 and target.c == 3 and target.nested.b == 2, "Util.DeepMerge fills missing keys and keeps existing ones")
        check(HL.L["Rank %d needs level %d."] == "Rank %d needs level %d." and HL.L["never added"] == "never added", "HonorLog.L returns the key")
        local nSay = countPlain("[HonorLog]|r hello say")
        HL:Say("hello say")
        check(countPlain("[HonorLog]|r hello say") == nSay + 1, "HonorLog:Say prints with the prefix")
        local nAnn = countPlain("announce check")
        HL:Announce("announce check")
        Rank:Announce("announce check")
        check(countPlain("announce check") == nAnn + 2, "HonorLog:Announce and Rank:Announce both print")

        -- A recorded-game helper: newest first, spaced a few hours apart.
        local function rec(bg, result, pts, state, extra)
            local g = { bgType = bg, result = result, win = result == "win", rankPoints = pts, rankState = state,
                timestamp = time() - 3600 * (extra and extra.hours or 2) }
            if extra then for k, v in pairs(extra) do if k ~= "hours" then g[k] = v end end end
            return g
        end
        local function setHistory(list)
            for i, g in ipairs(list) do g.timestamp = time() - i * 3600 end
            char.history = list
        end

        -- Rank state per game, through the whole game flow.
        mock.level = 60
        local function playGame(bg, mapID, winner, midGame)
            resetPvP()
            enter(bg, mapID)
            if midGame then midGame() end
            mock.pvp.roster, mock.pvp.matchComplete = roster(), true
            mock.fireEvent("PVP_MATCH_COMPLETE", winner, 400)
            leave()
            return lastGame()
        end
        mock.currencies[1792].quantity, mock.currencies[1792].maxQuantity = 8200, 25000
        char.history = {}
        setRank(3, 100, 6, 3, 5)
        local g = playGame("Warsong Gulch", 489, 1, function() mock.rank.earned = 200 end)
        check(g.rankState == "earned" and g.rankPoints == 100 and g.rankCappedDuring == nil, "game state earned: " .. tostring(g.rankState))
        setRank(3, 100, 6, 3, 5)
        g = playGame("Warsong Gulch", 489, 0)
        check(g.rankState == "zero" and g.rankPoints == 0, "game state zero when nothing else explains the 0: " .. tostring(g.rankState))
        setRank(3, 100, 6, 3, 5)
        g = playGame("Warsong Gulch", 489, 0, function() mock.rankWindow.noData = true end)
        mock.rankWindow.noData = false
        check(g.rankState == "nodata", "game state nodata when the end read is nil: " .. tostring(g.rankState))
        setRank(3, 100, 6, 3, 5)
        mock.rankWindow.noData = true
        resetPvP()
        enter("Warsong Gulch", 489)
        mock.rankWindow.noData = false
        mock.pvp.roster, mock.pvp.matchComplete = roster(), true
        mock.fireEvent("PVP_MATCH_COMPLETE", 0, 400)
        leave()
        check(lastGame().rankState == "nodata", "game state nodata when the start read is nil")
        setRank(5, 0, 5, 3, 4) -- total points equal this week's cap total
        g = playGame("Warsong Gulch", 489, 0)
        check(g.rankState == "capped", "game state capped when the week's cap was already reached: " .. tostring(g.rankState))
        setRank(4, 1300, 5, 3, 4) -- 50 points short of the cap total
        g = playGame("Warsong Gulch", 489, 1, function() mock.rank.earned = 1350 end)
        check(g.rankState == "earned" and g.rankPoints == 50 and g.rankCappedDuring == true, "earned, and the cap was reached during the game")
        mock.level = 35
        setRank(3, 100, 6, 3, 5)
        g = playGame("Warsong Gulch", 489, 0)
        check(g.rankState == "gated", "game state gated: level 35, rank 3, nothing earned: " .. tostring(g.rankState))
        setRank(1, 100, 6, 3, 5)
        g = playGame("Warsong Gulch", 489, 0)
        check(g.rankState == "zero", "a 0 at rank 1 under the gate is not the gate's doing: " .. tostring(g.rankState))
        setRank(3, 100, 6, 3, 5)
        g = playGame("Warsong Gulch", 489, 1, function() mock.rank.earned = 190 end)
        check(g.rankState == "earned" and g.rankPoints == 90, "points earned under the gate still read as earned")
        mock.level = 60

        -- Pace uses only earned and zero games.
        local noise = {
            rec("WSG", "win", 0, "capped"), rec("WSG", "loss", 0, "nodata"), rec("WSG", "loss", 0, "gated"),
            rec("WSG", "win", 0, nil), -- an old record that gave 0: unknown
            rec("WSG", "win", 10, "earned", { rankCappedDuring = true }),
        }
        local list = {}
        for _, n in ipairs(noise) do list[#list + 1] = n end
        for _ = 1, 5 do list[#list + 1] = rec("WSG", "win", 100, "earned") end
        for _ = 1, 3 do list[#list + 1] = rec("WSG", "loss", 25, "earned") end
        list[#list + 1] = rec("WSG", "win", 100) -- an old record that gave points: earned
        for _ = 1, 2 do list[#list + 1] = rec("WSG", "loss", 0, "zero") end
        setHistory(list)
        pace = Rank:GetPace()
        check(pace.measuredGames == 11 and not pace.estimated, "pace measures earned and zero games only: " .. pace.measuredGames)
        check(near2(pace.pointsPerWin, 100) and near2(pace.pointsPerLoss, 15), "per win 100 and per loss 75/5 = 15: " .. pace.pointsPerWin .. "/" .. pace.pointsPerLoss)
        check(pace.noPoints == false and pace.measuredWins == 6 and pace.measuredLosses == 5, "pace counts measured wins and losses")
        setHistory({ rec("WSG", "win", 100, "earned"), rec("WSG", "win", 100, "earned"), rec("WSG", "win", 0, "capped"), rec("WSG", "loss", 0, "gated") })
        pace = Rank:GetPace()
        check(pace.estimated and pace.measuredGames == 2 and pace.pointsPerWin == 100 and pace.noPoints == false, "below 5 measured games the pace stays an estimate with the defaults")
        local mixed = {}
        for _ = 1, 6 do mixed[#mixed + 1] = rec("AV", "loss", 0, "zero") end
        for _ = 1, 6 do mixed[#mixed + 1] = rec("WSG", "win", 100, "earned") end
        setHistory(mixed)
        check(Rank:GetPace("AV").noPoints == true and Rank:GetPace("AV").measuredGames == 6, "pace for one battleground: AV gives no points")
        check(Rank:GetPace("WSG").noPoints == false and near2(Rank:GetPace("WSG").pointsPerWin, 100) and Rank:GetPace("WSG").measuredGames == 6, "pace for one battleground: WSG is unaffected")
        check(Rank:GetPace().noPoints == false and Rank:GetPace().measuredGames == 12, "pace for everything mixes both")

        -- Points per result: one row per battleground with measured games.
        local ppr = Rank:GetPointsPerResult()
        check(#ppr == 2 and ppr[1].bgType == "AV" and ppr[1].perWin == nil and ppr[1].perLoss == 0 and ppr[1].games == 6, "points per result: AV row")
        check(ppr[2].bgType == "WSG" and ppr[2].perWin == 100 and ppr[2].perLoss == nil and ppr[2].games == 6, "points per result: WSG row")

        -- The zero-point pace: no "~0 games" and no today's date anywhere.
        local zeros = {}
        for _ = 1, 6 do zeros[#zeros + 1] = rec("WSG", "win", 0, "zero") end
        setHistory(zeros)
        setRank(4, 300, 6, 3, 5)
        info = Rank:GetInfo()
        pace = Rank:GetPace()
        check(pace.noPoints == true and not pace.estimated, "6 measured games averaging 0 is a measured no-points pace")
        plan = Rank:PlanToRank(6, info, pace)
        check(plan.gamesNeeded == nil and plan.projectedDateAtPace == nil and plan.limitedBy == "nopoints" and plan.date == nil, "plan with a 0 pace: no games, no date, limited by nopoints")
        check(plan.pointsNeeded == 2550, "the plan still says the points needed")
        check(Rank:PlanToRank(3, info, pace).reached, "a reached rank is still reached")
        local tip2 = { lines = {} }
        function tip2:AddLine(t) self.lines[#self.lines + 1] = t end
        function tip2:AddDoubleLine(l, r) self.lines[#self.lines + 1] = l .. " " .. r end
        Rank:AddTooltipLines(tip2)
        local tip2Text = table.concat(tip2.lines, "\n")
        check(tip2Text:find("no estimate: your games give no rank points", 1, true) and not tip2Text:find("~0", 1, true), "tooltip: plain sentence, no ~0 games")
        local before = #printed
        slash("rank 6")
        slash("rank")
        local out = table.concat(printed, "\n", before + 1)
        check(out:find("No estimate: your games give no rank points", 1, true) and not out:find("about 0", 1, true) and not out:find("~0 games", 1, true), "/honorlog rank 6: plain sentence")
        check(out:find("no pace to plan with", 1, true), "/honorlog rank: says there is no pace")
        HL.db.settings.showRankBar = true
        Rank:Refresh()
        rui.panel:Update(Rank:GetInfo())
        local detail = rui.panel.rows[6].detail:GetText()
        check(detail:find("no estimate", 1, true) and not detail:find("~0", 1, true), "Rank tab row: plain sentence: " .. tostring(detail))
        check(rui.panel.lines[4]:GetText():find("no pace to plan with", 1, true), "Rank tab summary says there is no pace")
        -- Goals: a rank-gated item with the 0 pace has a limit and no date, with nothing erroring.
        local rankItem
        for id in pairs(HL.GearDB) do
            local it = HL:GetGearItem(id)
            if it and it.rank and it.rank >= 6 and not it.scanned and HL:IsGearAvailable(id) then rankItem = id break end
        end
        check(rankItem ~= nil, "found a rank-gated item in the gear database")
        local gp2 = HL:GetGoalProgress(rankItem)
        check(gp2.rank and gp2.rank.limitedBy == "nopoints" and gp2.rank.date == nil and gp2.readyLimitedBy == "nopoints" and gp2.readyDate == nil,
            "goal progress with a 0 rank pace: " .. tostring(gp2.rank and gp2.rank.limitedBy) .. "/" .. tostring(gp2.readyLimitedBy))

        -- Zero-point battlegrounds: the latest three or more earned/zero games all 0.
        local zl = {}
        for i = 1, 3 do zl[#zl + 1] = rec("AV", "loss", 0, "zero") end
        zl[#zl + 1] = rec("AV", "win", 100, "earned") -- older
        for i = 1, 4 do zl[#zl + 1] = rec("WSG", "win", 62, "earned") end
        setHistory(zl)
        local zp = Rank:GetZeroPointBattlegrounds()
        check(#zp == 1 and zp[1].bgType == "AV" and zp[1].zero == 3 and zp[1].games == 3 and near2(zp[1].otherAverage, 62), "zero-point battlegrounds: AV, 3 of 3, others average 62")
        check(Rank:ZeroPointText(zp[1]) == "Alterac Valley gave 0 rank points in 3 of 3 games. Your other battlegrounds average 62.", "zero-point sentence: " .. Rank:ZeroPointText(zp[1]))
        setHistory({ rec("AV", "loss", 0, "zero"), rec("AV", "loss", 0, "zero"), rec("AV", "loss", 0, "capped"), rec("AV", "win", 100, "earned") })
        check(#Rank:GetZeroPointBattlegrounds() == 0, "two zeros are not enough; a capped game neither counts nor breaks the run")
        setHistory({ rec("AV", "win", 100, "earned"), rec("AV", "loss", 0, "zero"), rec("AV", "loss", 0, "zero"), rec("AV", "loss", 0, "zero") })
        check(#Rank:GetZeroPointBattlegrounds() == 0, "an earned game after the zeros ends the flag")
        setHistory({ rec("WSG", "left", 0, "zero"), rec("WSG", "left", 0, "zero"), rec("WSG", "left", 0, "zero"), rec("WSG", "left", 0, "zero"), rec("WSG", "left", 0, "zero") })
        check(#Rank:GetZeroPointBattlegrounds() == 0, "games left early never flag a battleground")
        check(Rank:GetPace().measuredGames == 0 and not Rank:GetPace().noPoints, "games left early are not measured games")
        setHistory({ rec("AV", "loss", 0, "zero"), rec("AV", "loss", 0, "zero"), rec("AV", "loss", 0, "zero") })
        zp = Rank:GetZeroPointBattlegrounds()
        check(#zp == 1 and zp[1].otherAverage == nil and Rank:ZeroPointText(zp[1]) == "Alterac Valley gave 0 rank points in 3 of 3 games.", "with no other data the second sentence is dropped")
        -- The Rank tab lists it, then the points per result.
        setHistory(zl)
        setRank(4, 300, 6, 3, 5)
        Rank:Refresh()
        rui.panel:Update(Rank:GetInfo())
        check(rui.panel.extraRows[1].name:GetText() == "Alterac Valley" and rui.panel.extraRows[1].detail:GetText() == "Gave 0 rank points in 3 of 3 games.", "Rank tab: one line per zero-point battleground")
        check(rui.panel.extraHeader:GetText() == "Points per result (measured games)", "Rank tab: points per result header")
        check(rui.panel.extraRows[3].name:GetText() == "Alterac Valley" or rui.panel.extraRows[2].name:GetText() == "Alterac Valley", "Rank tab: a points-per-result row for AV")
        check(rui.panel.extraRows[3].detail:GetText() == "per win 100, per loss 0" or rui.panel.extraRows[2].detail:GetText() == "per win 100, per loss 0", "Rank tab: AV measured 100 per win and 0 per loss")
        check(rui.panel.extraRows[4].detail:GetText() == "per win 62, per loss -" and rui.panel.extraRows[4].tag:GetText() == "4 games", "Rank tab: WSG row")
        check(rui.panel.content:GetHeight() == (Rank.MAX_RANK + 4) * (HL.Layout.RANK_ROW_HEIGHT + 2), "the scroll area grows to hold the extra rows: " .. rui.panel.content:GetHeight())
        -- The end-of-game line: once per battleground per login.
        local avGames = {}
        for _ = 1, 2 do avGames[#avGames + 1] = rec("AV", "loss", 0, "zero") end
        for _ = 1, 4 do avGames[#avGames + 1] = rec("WSG", "win", 62, "earned") end
        setHistory(avGames)
        setRank(3, 100, 6, 3, 5)
        local fullLine = "Alterac Valley gave 0 rank points in 3 of 3 games. Your other battlegrounds average 62."
        local nLine, n33 = countPlain(fullLine), countPlain("gave 0 rank points in 3 of 3")
        g = playGame("Alterac Valley", 30, 0)
        check(g.rankState == "zero", "the third AV game gave 0")
        check(countPlain(fullLine) == nLine + 1, "the end-of-game line names the zero-point battleground")
        g = playGame("Alterac Valley", 30, 0)
        check(countPlain("Alterac Valley gave 0 rank points in 4 of 4") == 0 and countPlain("gave 0 rank points in 3 of 3") == n33 + 1, "the line is not repeated for the same battleground in the same login")
        check(Rank:TakeZeroPointLine("AV") == nil, "TakeZeroPointLine: already told this login")
        setHistory({ rec("MAP999", "loss", 0, "zero"), rec("MAP999", "loss", 0, "zero"), rec("MAP999", "loss", 0, "zero") })
        local t1 = Rank:TakeZeroPointLine("MAP999")
        local t2 = Rank:TakeZeroPointLine("MAP999")
        check(t1 ~= nil and t2 == nil, "a second battleground is told once: " .. tostring(t1) .. " / " .. tostring(t2))
        check(Rank:TakeZeroPointLine("AB") == nil, "a battleground that gives points gets no line")

        -- The level gate.
        check(Rank.LEVEL_GATES[1].rank == 4 and Rank.LEVEL_GATES[1].level == 40, "the one reported gate: rank 4 needs level 40")
        char.gateDisproved = nil
        setHistory({})
        mock.level = 35
        setRank(3, 100, 6, 3, 5)
        info = Rank:GetInfo()
        check(info.gate and info.gate.rank == 4 and info.gate.level == 40 and info.gate.blocking == true, "gate blocks: level 35, rank 3, cap 6")
        local gateSentence = "Rank 4 needs level 40. Players report this; Blizzard hasn't confirmed it."
        check(Rank:GateText(info.gate) == gateSentence, "gate sentence")
        Rank:Refresh()
        check(rui.bar.text:GetText():find("Rank 4 needs level 40", 1, true), "rank bar says the gate: " .. tostring(rui.bar.text:GetText()))
        rui.panel:Update(Rank:GetInfo())
        check(rui.panel.lines[4]:GetText() == gateSentence, "Rank tab summary says the gate sentence")
        tip2 = { lines = {} }
        function tip2:AddLine(t) self.lines[#self.lines + 1] = t end
        function tip2:AddDoubleLine(l, r) self.lines[#self.lines + 1] = l .. " " .. r end
        Rank:AddTooltipLines(tip2)
        check(table.concat(tip2.lines, "\n"):find(gateSentence, 1, true), "tooltip says the gate sentence")
        before = #printed
        slash("rank")
        check(table.concat(printed, "\n", before + 1):find(gateSentence, 1, true), "/honorlog rank says the gate sentence")
        HL.db.settings.ldbFormat = "rank"
        check(Rank:BrokerText():find("needs level 40", 1, true), "broker text says the gate")
        HL.db.settings.ldbFormat = "games"
        -- Plans past the gate.
        plan = Rank:PlanToRank(6, info, Rank:GetPace())
        check(plan.limitedBy == "level" and plan.gateLevel == 40 and plan.date == nil and plan.projectedDateAtPace == nil, "plan past the gate: limited by level, no date")
        check(Rank:PlanToRank(4, info, Rank:GetPace()).limitedBy == "level", "the gate rank itself is behind the gate")
        before = #printed
        slash("rank 6")
        check(table.concat(printed, "\n", before + 1):find("after level 40", 1, true), "/honorlog rank 6: after level 40")
        rui.panel:Update(Rank:GetInfo())
        check(rui.panel.rows[6].detail:GetText():find("after level 40", 1, true) and rui.panel.rows[6].tag:GetText() == "level", "Rank tab row: after level 40")
        tip2 = { lines = {} }
        function tip2:AddLine(t) self.lines[#self.lines + 1] = t end
        function tip2:AddDoubleLine(l, r) self.lines[#self.lines + 1] = l .. " " .. r end
        Rank:AddTooltipLines(tip2)
        check(table.concat(tip2.lines, "\n"):find("after level 40", 1, true), "tooltip: after level 40")
        gp2 = HL:GetGoalProgress(rankItem)
        check(gp2.rank.limitedBy == "level" and gp2.rank.date == nil and gp2.readyLimitedBy == "level" and gp2.readyDate == nil, "goal progress behind the gate: level, no date")
        -- When it applies and when it blocks.
        setRank(3, 100, 3, 3, 3)
        info = Rank:GetInfo()
        check(info.gate and info.gate.blocking == false, "the gate applies but the weekly cap (rank 3) is the limit, so it is not blocking")
        Rank:Refresh()
        check(not rui.bar.text:GetText():find("needs level", 1, true), "bar does not blame the level while the cap is the limit")
        setRank(3, 100, 0, 3, 0)
        check(Rank:GetInfo().gate.blocking == true, "no cap named: blocking")
        setRank(2, 100, 6, 3, 5)
        check(Rank:GetInfo().gate and Rank:GetInfo().gate.blocking == false, "rank 2 is two below the gate rank: applies, not blocking")
        check(Rank:PlanToRank(3, Rank:GetInfo(), Rank:GetPace()).limitedBy ~= "level" and Rank:PlanToRank(5, Rank:GetInfo(), Rank:GetPace()).limitedBy == "level", "plans below the gate rank are not level-limited")
        mock.level = 40
        setRank(3, 100, 6, 3, 5)
        check(Rank:GetInfo().gate == nil, "level 40: no gate")
        mock.level = 35
        setRank(4, 100, 6, 3, 5)
        check(Rank:GetInfo().gate == nil, "at the gate rank already: no gate")
        -- Disproved: holding the rank under the level.
        HonorLogDB.probe = HonorLogDB.probe or {}
        HonorLogDB.probe.log = {}
        HonorLogDB.probe.armed = false
        Rank:Refresh()
        check(char.gateDisproved and char.gateDisproved[4] == true, "holding rank 4 at level 35 disproves the gate")
        check(#HonorLogDB.probe.log == 0, "a disarmed probe logs nothing")
        char.gateDisproved = nil
        slash("probe on")
        HonorLogDB.probe.log = {}
        Rank:Refresh()
        Rank:Refresh()
        local gateLogs = 0
        for _, e in ipairs(HonorLogDB.probe.log) do if e.event == "RANK_GATE_DISPROVED" then gateLogs = gateLogs + 1 end end
        check(gateLogs == 1, "an armed probe logs the observation once: " .. gateLogs)
        check(HonorLogDB.probe.log[#HonorLogDB.probe.log].args[1] == 4 and HonorLogDB.probe.log[#HonorLogDB.probe.log].args[3] == 35, "the log entry has the gate rank and the level")
        slash("probe off")
        setRank(3, 100, 6, 3, 5) -- e.g. a season reset: the gate stays off for this character
        check(Rank:GetInfo().gate == nil, "a disproved gate is not applied again")
        check(Rank:PlanToRank(6, Rank:GetInfo(), Rank:GetPace()).limitedBy ~= "level", "plans ignore a disproved gate")
        char.gateDisproved = nil
        -- PLAYER_LEVEL_UP refreshes the rank; the new level wins while the client still reports the old one.
        check(mock.knownEvents.PLAYER_LEVEL_UP, "the mock knows PLAYER_LEVEL_UP")
        local registered = false
        for _, f in ipairs(mock.frames) do if f.__events.PLAYER_LEVEL_UP then registered = true end end
        check(registered, "HonorLog registers PLAYER_LEVEL_UP")
        Rank:Refresh()
        check(rui.bar.text:GetText():find("needs level 40", 1, true) or rui.bar.text:GetText():find("Rank 4 needs level 40", 1, true), "before the level-up the bar shows the gate")
        mock.deferTimers, mock.timers = true, {}
        mock.level = 40
        mock.fireEvent("PLAYER_LEVEL_UP", 40)
        check(not rui.bar.text:GetText():find("needs level", 1, true), "after the level-up the bar no longer shows the gate")
        mock.level = 35
        mock.fireEvent("PLAYER_LEVEL_UP", 40) -- the client still says 35
        check(not rui.bar.text:GetText():find("needs level", 1, true), "the level in the event wins while the client catches up")
        mock.flushTimers()
        mock.deferTimers = false
        check(rui.bar.text:GetText():find("needs level", 1, true), "a second read from the client settles on its own level")
        mock.level = 60
        Rank:Refresh()

        -- Honor at the cap: flagged games stay out of the honor averages.
        setRank(3, 100, 6, 3, 5)
        mock.currencies[1792].quantity, mock.currencies[1792].maxQuantity = 25000, 25000
        g = playGame("Warsong Gulch", 489, 1)
        check(g.honorCapped == true, "a game that starts at the honor cap is flagged")
        mock.currencies[1792].quantity = 24900
        g = playGame("Warsong Gulch", 489, 1, function() gainHonor(200) end)
        check(g.honorCapped == true, "a game that reaches the cap is flagged")
        mock.currencies[1792].quantity = 8200
        g = playGame("Warsong Gulch", 489, 1)
        check(g.honorCapped == nil, "a game below the cap is not flagged")
        mock.currencies[1792].quantity, mock.currencies[1792].maxQuantity = 25000, 30000
        g = playGame("Warsong Gulch", 489, 1)
        check(g.honorCapped == nil, "the cap comes from the currency, not from 25000")
        mock.currencies[1792].quantity, mock.currencies[1792].maxQuantity = 8200, 25000
        local avgAll, avgDI, best0 = HL:GetAverageHonorPerGame(), HL:GetAverageHonorPerBG("DI"), HL:GetBestHonorPerGame()
        HL:RecordGame("DI", true, 100, 90000, 0, { honorCapped = true })
        check(near2(HL:GetAverageHonorPerGame(), avgAll) and near2(HL:GetAverageHonorPerBG("DI"), avgDI) and near2(HL:GetBestHonorPerGame(), best0),
            "a capped game moves none of the three honor averages")
        check(lastGame().honorCapped == true and HL.db.char.battlegrounds.DI.cappedPlayed >= 1, "the flag is kept on the record and the counters")
        HL:RecordGame("DI", true, 100, 90000, 0, {})
        check(HL:GetBestHonorPerGame() > best0, "an uncapped game does move the averages")

        char.history = savedHist
        mock.level, mock.rank = savedLevel, savedRank
        mock.rankWindow.cap, mock.rankWindow.week, mock.rankWindow.prevCap = savedWindow.cap, savedWindow.week, savedWindow.prevCap
        mock.pvp.matchComplete = false
        Rank:Refresh()
    end

    ----------------------------------------------------------------------
    -- Round 6: gear that tells the truth
    ----------------------------------------------------------------------
    do
        local GearDB = HL.GearDB
        local goalsPanel, savedStats
        local function setRankR(...) setRank(...) Rank:Refresh() end
        local saved = {
            history = char.history, level = mock.level, faction = mock.faction, money = mock.money, bag = mock.bagItems,
            honor = mock.currencies[1792].quantity, cap = mock.currencies[1792].maxQuantity, rank = mock.rank,
            window = { cap = mock.rankWindow.cap, week = mock.rankWindow.week, prevCap = mock.rankWindow.prevCap },
            goals = char.goals.items, completed = char.goals.completed, seconds = mock.seasonSeconds,
            gear = HonorLogDB.scannedGear, vendors = HonorLogDB.scannedVendors, mode = HL.db.settings.goalProgressMode,
        }
        local function near(a, b, tol) return a ~= nil and math.abs(a - b) <= (tol or 2) end
        local function kinds(list)
            local out = {}
            for _, r in ipairs(list) do out[#out + 1] = r.kind end
            return table.concat(out, ",")
        end
        local function hasKind(list, kind)
            for _, r in ipairs(list) do if r.kind == kind then return true end end
            return false
        end
        local function playGame(bg, mapID, midGame)
            resetPvP()
            enter(bg, mapID)
            if midGame then midGame() end
            mock.pvp.roster, mock.pvp.matchComplete = roster(), true
            mock.fireEvent("PVP_MATCH_COMPLETE", 1, 400)
            leave()
            mock.pvp.matchComplete = false
            return lastGame()
        end
        -- Tooltip lines the card or row showed.
        local tipLines = {}
        local realAddLine = GameTooltip.AddLine
        GameTooltip.AddLine = function(_, text) tipLines[#tipLines + 1] = tostring(text) end
        local function tipHas(text)
            for _, l in ipairs(tipLines) do if l:find(text, 1, true) then return true end end
            return false
        end

        local BLUE, EPIC, RANK4, LOW_LEVEL = 272738, 272787, 274969, 274444
        local TABARD, MULTI_REP, AB_GIRDLE, AB_PAULDRONS = 19032, 17349, 20041, 20055
        local HORDE_WSG_NECK, HORDE_ARMOR, DI_REP, MOUNT, SEAL, ALLY_WEAPON = 19534, 272480, 271903, 18241, 275241, 272693

        mock.faction, mock.level, mock.money = "Alliance", 60, 123456
        char.gateDisproved = nil
        setRankR(3, 100, 6, 3, 5)
        mock.level = 35
        mock.seasonSeconds = 86400 * 100
        mock.currencies[1792].quantity, mock.currencies[1792].maxQuantity = 8200, 25000
        mock.bagItems = { [20560] = 5, [20558] = 12, [20559] = 3, [274895] = 0 }
        mock.bagContents, mock.equipped, mock.reputation, mock.repAmounts, mock.repSecret = {}, {}, {}, {}, {}
        char.goals.items, char.goals.completed = {}, {}
        HonorLogDB.scannedGear, HonorLogDB.scannedVendors = {}, {}
        HL.db.settings.goalProgressMode = "shared"
        measuredGames(30, 20, 120, 30)

        -- 1. Level requirement -------------------------------------------------
        local gp = HL:GetGoalProgress(BLUE)
        check(gp.level and gp.level.kind == "level" and gp.level.needed == 55 and gp.level.current == 35 and gp.level.known and not gp.level.met,
            "level row: needed 55, current 35, unmet")
        check(hasKind(gp.missing, "level") and not gp.isComplete, "an unmet level is in the missing list")
        check(gp.readyDate == nil and gp.readyLimitedBy == "level", "an unmet level means no ready date, limited by level: " .. tostring(gp.readyLimitedBy))
        check(gp.level.remaining == 20, "the level row counts the levels to go")
        mock.level = 60
        gp = HL:GetGoalProgress(BLUE)
        check(gp.level.met and not hasKind(gp.missing, "level") and gp.readyLimitedBy ~= "level" and gp.readyDate ~= nil, "a met level: still a row, not missing, a date again")
        check(HL:GetGoalProgress(LOW_LEVEL).level == nil, "an item needing level 0 or 1 has no level row")
        mock.level = mock.newSecret()
        gp = HL:GetGoalProgress(BLUE)
        check(gp.level.known == false and not hasKind(gp.missing, "level") and gp.readyLimitedBy ~= "level", "a secret player level: unknown, not counted as short")
        mock.level = 35

        -- The card: requirement line, status line, tooltip.
        HL:AddGoal(BLUE)
        HL:SetExpanded(true)
        HL:SwitchTab("goals")
        goalsPanel = HL.mainFrame.goalsPanel
        HL:UpdateGoalsPanel()
        local card = goalsPanel.goalCards[1]
        check(card.currencyLine:GetText():find("Level 35 / 55", 1, true), "card requirement line: Level 35 / 55: " .. tostring(card.currencyLine:GetText()))
        check(card.statusLine:GetText():find("Ready at level 55", 1, true), "card status: Ready at level 55: " .. tostring(card.statusLine:GetText()))
        check(card.statusLine:GetText():find("also needs 800 honor, 10 AV marks", 1, true), "card status: what else is missing")
        tipLines = {}
        card:GetScript("OnEnter")(card)
        check(tipHas("  Level 55"), "card tooltip: Level 55 in the missing list")
        local before = #printed
        slash("goal list")
        check(table.concat(printed, "\n", before + 1):find("Level 55", 1, true), "/honorlog goal list names Level 55")
        mock.level = 60
        HL:UpdateGoalsPanel()
        check(not card.currencyLine:GetText():find("Level", 1, true) and not card.statusLine:GetText():find("Ready at level", 1, true), "a met level is not shown")

        -- Rank text: the level gate and the zero-point pace no longer read "not reachable this season".
        HL:RemoveGoal(BLUE)
        HL:AddGoal(RANK4)
        mock.level = 35
        setRankR(3, 100, 6, 3, 5)
        char.history = {}
        HL:UpdateGoalsPanel()
        local rankCard = goalsPanel.goalCards[1]
        check(rankCard.statusLine:GetText():find("after level 40", 1, true) and not rankCard.statusLine:GetText():find("not reachable", 1, true),
            "rank goal under the level gate: after level 40: " .. tostring(rankCard.statusLine:GetText()))
        check(rankCard.statusLine:GetText():find("Ready at level 55", 1, true), "the item's own level shows first")
        HL:RemoveGoal(RANK4)
        local rankItem
        for id in pairs(GearDB) do
            local it = HL:GetGearItem(id)
            if it and it.rank and it.rank >= 6 and (it.reqLevel or 0) <= 1 and not it.scanned and HL:IsGearAvailable(id) then rankItem = id break end
        end
        if not rankItem then
            for id in pairs(GearDB) do
                local it = HL:GetGearItem(id)
                if it and it.rank and it.rank >= 6 and HL:IsGearAvailable(id) then rankItem = id break end
            end
        end
        mock.level = 60
        setRankR(3, 100, 6, 3, 5)
        local zeros = {}
        for i = 1, 6 do zeros[i] = { bgType = "WSG", result = "win", win = true, rankPoints = 0, rankState = "zero", timestamp = time() - i * 3600 } end
        char.history = zeros
        HL:AddGoal(rankItem)
        HL:UpdateGoalsPanel()
        local zeroText = goalsPanel.goalCards[1].statusLine:GetText()
        check(zeroText:find("no estimate", 1, true) and not zeroText:find("not reachable", 1, true), "rank goal at a zero pace: no estimate, not 'not reachable': " .. tostring(zeroText))
        HL:RemoveGoal(rankItem)
        check(type(HL.RANK_TAG_COLORS.level) == "table" and type(HL.RANK_TAG_COLORS.nopoints) == "table", "level and nopoints have tag colours")
        measuredGames(30, 20, 120, 30)
        setRankR(3, 100, 6, 3, 5)
        mock.level = 35

        -- 2. Reputation with numbers -------------------------------------------
        check(HL.BG_REP_FACTIONS.AB.Horde == 510 and HL.BG_REP_FACTIONS.AB.Alliance == 509 and HL.BG_REP_FACTIONS.AV.Horde == 729
            and HL.BG_REP_FACTIONS.AV.Alliance == 730 and HL.BG_REP_FACTIONS.WSG.Horde == 889 and HL.BG_REP_FACTIONS.WSG.Alliance == 890
            and HL.BG_REP_FACTIONS.DI.Horde == 2798 and HL.BG_REP_FACTIONS.DI.Alliance == 2799, "the battleground faction table")
        check(HL:GetBGRepFaction("AB") == 509 and HL:GetBGRepFaction("DI") == 2799 and HL:GetBGRepFaction("Nope") == nil, "faction by battleground for the player's side")
        mock.reputation[730] = 6
        mock.repAmounts[730] = { current = 13200, floor = 9000, ceiling = 21000 }
        local prog = HL:GetReputationProgress(730)
        check(prog.standing == 6 and prog.current == 13200 and prog.floor == 9000 and prog.ceiling == 21000, "GetReputationProgress: standing, current, floor, ceiling")
        check(HL:GetReputationStanding(730) == 6, "GetReputationStanding works on top of it")
        check(HL:GetReputationProgress(729).standing == 0 and HL:GetReputationStanding(729) == 0, "a faction not met reads as standing 0")
        mock.repSecret[730] = true
        check(HL:GetReputationProgress(730) == nil and HL:GetReputationStanding(730) == nil, "a secret standing is unknown, not an error")
        mock.repSecret[730] = nil
        local savedRepAPI = C_Reputation
        C_Reputation = nil
        check(HL:GetReputationProgress(730) == nil, "no reputation API: nil")
        C_Reputation = savedRepAPI

        -- The row: Honored 4,200 / 12,000, needing Exalted (the Highlander pauldrons are level 60: not the point here).
        mock.reputation[509] = 6
        mock.repAmounts[509] = { current = 13200, floor = 9000, ceiling = 21000 }
        mock.level = 60
        gp = HL:GetGoalProgress(AB_PAULDRONS)
        check(gp.rep.current == 6 and gp.rep.amount == 4200 and gp.rep.ceiling == 12000, "rep row: amount 4200 of 12000 into Honored")
        check(gp.rep.remainingRep == 12000 + 21000 - 4200, "rep row: remaining across the standings in between: " .. tostring(gp.rep.remainingRep))
        check(gp.rep.perGame == nil and gp.rep.games == nil, "rep row: no measured rate yet")
        HL:AddGoal(AB_PAULDRONS)
        HL:UpdateGoalsPanel()
        check(goalsPanel.goalCards[1].currencyLine:GetText():find("Honored 4,200 / 12,000", 1, true), "card: Honored 4,200 / 12,000: " .. tostring(goalsPanel.goalCards[1].currencyLine:GetText()))
        HL:RemoveGoal(AB_PAULDRONS)
        check(HL:ReputationRemaining(4, 0, 5) == 3000 and HL:ReputationRemaining(5, 1000, 6) == 5000 and HL:ReputationRemaining(6, 0, 6) == 0
            and HL:ReputationRemaining(4, 0, 8) == 3000 + 6000 + 12000 + 21000, "standard spans: Neutral 3,000, Friendly 6,000, Honored 12,000, Revered 21,000")

        -- No measured rate: no date, never "ready today".
        mock.reputation[730] = 4
        mock.repAmounts[730] = { current = 1200, floor = 0, ceiling = 3000 }
        mock.level = 60
        gp = HL:GetGoalProgress(TABARD)
        check(gp.rep.needed == 5 and gp.rep.amount == 1200 and gp.rep.remainingRep == 1800 and gp.rep.perGame == nil, "tabard: 1,800 reputation to Friendly, no rate")
        check(gp.readyDate == nil and gp.readyLimitedBy == "norep" and not gp.isComplete, "a reputation-only item with no rate: no date, limited by norep")
        check(gp.readyText == "play a Alterac Valley game to measure reputation", "the norep text names the battleground: " .. tostring(gp.readyText))
        HL:AddGoal(TABARD)
        HL:UpdateGoalsPanel()
        check(goalsPanel.goalCards[1].statusLine:GetText():find("play a Alterac Valley game to measure reputation", 1, true), "card status says to play a game")
        before = #printed
        slash("goal list")
        check(table.concat(printed, "\n", before + 1):find("play a Alterac Valley game", 1, true), "/honorlog goal list says it too")

        -- Per-game rate: newest 20 games that recorded the faction.
        local repHistory = {}
        for i = 1, 25 do
            repHistory[i] = { bgType = "AV", result = "win", win = true, rankPoints = 100, timestamp = time() - i * 3600,
                rep = { faction = 730, gained = i <= 20 and 100 or 1000 } }
        end
        repHistory[3].rep = { faction = 729, gained = 5000 } -- another faction: not counted
        repHistory[4] = { bgType = "AV", result = "win", win = true, rankPoints = 100, timestamp = time() - 4 * 3600 } -- no rep recorded
        char.history = repHistory
        -- 23 games recorded faction 730; the newest 20 are 18 of 100 and 2 of 1000.
        check(near(HL:GetRepPerGame(730), (18 * 100 + 2 * 1000) / 20, 1e-6), "GetRepPerGame: average of the newest 20 games that recorded the faction: " .. tostring(HL:GetRepPerGame(730)))
        check(HL:GetRepPerGame(1234) == nil, "no games for a faction: nil")
        gp = HL:GetGoalProgress(TABARD)
        check(near(gp.rep.perGame, 190, 1e-6) and gp.rep.games == 10, "rep row: perGame 190, 10 games for 1,800: " .. tostring(gp.rep.games))
        local gpd = Rank:GetPace().gamesPerDay
        check(gp.readyLimitedBy == "rep" and gp.totalGamesNeeded == 10 and near(gp.readyDate, time() + math.floor(10 / gpd * 86400), 5),
            "a reputation date from games over the games per day: " .. tostring(gp.readyLimitedBy) .. " " .. tostring(gp.totalGamesNeeded))
        mock.repAmounts[730] = { current = 2950, floor = 0, ceiling = 3000 }
        gp = HL:GetGoalProgress(TABARD)
        check(gp.rep.remainingRep == 50 and gp.rep.games == 1, "50 reputation to go is one game")
        mock.reputation[730] = 5
        mock.repAmounts[730] = { current = 3100, floor = 3000, ceiling = 9000 }
        gp = HL:GetGoalProgress(TABARD)
        check(gp.rep.met and gp.isComplete and gp.readyLimitedBy == "ready" and gp.readyDate ~= nil, "the standing met: ready today is allowed")
        mock.reputation[730] = 4
        mock.repAmounts[730] = { current = 1200, floor = 0, ceiling = 3000 }
        tipLines = {}
        HL:UpdateGoalsPanel()
        goalsPanel.goalCards[1]:GetScript("OnEnter")(goalsPanel.goalCards[1])
        check(tipHas("1,800 reputation to go") and tipHas("about 10 games at 190 reputation a game"), "card tooltip: reputation to go and games")
        mock.repSecret[730] = true
        HL:UpdateGoalsPanel()
        gp = HL:GetGoalProgress(TABARD)
        check(gp.rep.known == false and #gp.unverified == 1 and gp.readyLimitedBy ~= "norep", "a secret reputation reads as unknown and does not break the goal")
        mock.repSecret[730] = nil
        HL:RemoveGoal(TABARD)

        -- Each game records the reputation its battleground's faction gave.
        mock.reputation[509] = 5
        mock.repAmounts[509] = { current = 3500, floor = 3000, ceiling = 9000 }
        local g = playGame("Arathi Basin", 529, function() mock.repAmounts[509].current = 3900 end)
        check(g.bgType == "AB" and g.rep and g.rep.faction == 509 and g.rep.gained == 400, "Alliance AB game: rep 509 gained 400: " .. tostring(g.rep and g.rep.gained))
        g = playGame("Darkspear Islands", 2997, function() mock.reputation[2799] = 4; mock.repAmounts[2799] = { current = 250, floor = 0, ceiling = 3000 } end)
        check(g.rep and g.rep.faction == 2799 and g.rep.gained == 250, "a faction first met during the game starts from 0: " .. tostring(g.rep and g.rep.gained))
        mock.faction = "Horde"
        mock.reputation[889] = 4
        mock.repAmounts[889] = { current = 100, floor = 0, ceiling = 3000 }
        g = playGame("Warsong Gulch", 489, function() mock.repAmounts[889].current = 180 end)
        check(g.rep and g.rep.faction == 889 and g.rep.gained == 80, "Horde WSG game: rep 889 gained 80")
        mock.faction = "Alliance"
        g = playGame("Alterac Valley", 30, function() mock.repSecret[730] = true end)
        check(g.rep == nil and g.result ~= nil, "a secret reputation: the game is recorded without rep")
        mock.repSecret[730] = nil
        check(HL.db.global.history[1].rep == nil, "the account history keeps the same record")
        HL:RecordGame("AB", true, 100, 10, 0, { rep = { faction = 509, gained = 7 } })
        check(lastGame().rep.gained == 7 and HL.db.global.history[1].rep.faction == 509, "RecordGame stores extra.rep on both histories")
        HL:RecordGame("AB", true, 100, 10, 0, {})
        check(lastGame().rep == nil, "a game without rep has none")

        -- 3. Battleground reputation gear is visible -------------------------
        mock.level = 60
        check(HL:IsGearAvailable(TABARD) and HL:IsGearAvailable(AB_GIRDLE) and HL:IsGearAvailable(HORDE_WSG_NECK), "AB, AV and WSG reputation items are available by default")
        check(HL:GetGearItem(TABARD).unconfirmed == true and HL:GetGearItem(AB_GIRDLE).unconfirmed == true, "…and unconfirmed")
        check(not HL:IsGearAvailable(MULTI_REP) and HL:GetGearItem(MULTI_REP).unconfirmed == nil, "other legacy items stay hidden until scanned")
        check(HL:GetGearItem(BLUE).unconfirmed == nil, "a current item is not unconfirmed")
        HL:ShowGoalPicker()
        local picker = _G.HonorLogGoalPicker
        picker.filters.class = nil
        picker:RefreshItems()
        local function pickerRow(id)
            for i, e in ipairs(picker.shownItems) do if e.itemID == id then return picker.itemRows[i] end end
        end
        local trow = pickerRow(TABARD)
        check(trow and trow.slotText:GetText():find("price unconfirmed", 1, true) and not trow.slotText:GetText():find("unverified", 1, true), "picker row says price unconfirmed: " .. tostring(trow and trow.slotText:GetText()))
        check(pickerRow(MULTI_REP) == nil, "the picker still hides other legacy items")
        HonorLogDB.scannedGear[TABARD] = { honor = 0, marks = {}, gold = 10000, seen = 1, npc = "t" }
        picker:RefreshItems()
        check(HL:GetGearItem(TABARD).unconfirmed == nil and pickerRow(TABARD).slotText:GetText():find("scanned", 1, true), "a scan clears unconfirmed")
        HonorLogDB.scannedGear = {}
        HL:AddGoal(TABARD)
        HL:UpdateGoalsPanel()
        tipLines = {}
        goalsPanel.goalCards[1]:GetScript("OnEnter")(goalsPanel.goalCards[1])
        check(tipHas("Price unconfirmed"), "goal card tooltip says the price is unconfirmed")
        HL:RemoveGoal(TABARD)

        -- 4. Vendors ------------------------------------------------------------
        check(type(HL.VENDORS) == "table" and #HL.VENDORS == 14, "Data/Vendors.lua: 14 vendors")
        local byNpc = {}
        for _, v in ipairs(HL.VENDORS) do
            byNpc[v.npc] = v
            check(v.name and v.role and v.faction and v.place, "vendor " .. tostring(v.npc) .. " has name, role, faction and place")
        end
        check(byNpc[12792].x == nil and byNpc[12792].y == nil and byNpc[12777].x == 74.4 and byNpc[12777].y == 67.5 and byNpc[12781].x == 75.2, "coordinates are left out where unknown and kept where known")
        check(byNpc[15127].repFaction == 509 and byNpc[14754].repFaction == 889 and byNpc[13219].repFaction == 729 and byNpc[12777].repFaction == nil, "supply officers carry their reputation faction")
        check(byNpc[12777].map == 1453 and byNpc[15127].map == 1417 and byNpc[14754].map == 1413, "uiMap ids")
        local function vendorName(id) local v = HL:GetVendorFor(id) return v and v.name end
        check(vendorName(BLUE) == "Captain Dirgehammer" and HL:GetVendorFor(BLUE).source == "builtin", "HONOR armour: the Armor Quartermaster")
        check(vendorName(EPIC) == "Captain Dirgehammer", "UPGRADE armour: the Armor Quartermaster")
        check(vendorName(ALLY_WEAPON) == "Captain O'Neal", "a RANK weapon: the Weapons Quartermaster")
        check(vendorName(MOUNT) == "Lieutenant Karter", "a mount: the mount vendor")
        check(vendorName(SEAL) == "Master Sergeant Biggins" and vendorName(LOW_LEVEL) == "Master Sergeant Biggins" and vendorName(RANK4) == "Master Sergeant Biggins",
            "Seals and other RANK items: the Officer Accessories Quartermaster")
        check(vendorName(TABARD) == "Thanthaldis Snowgleam" and vendorName(AB_GIRDLE) == "Samuel Hawke", "a one-faction REP item: that faction's supply officer")
        check(vendorName(MULTI_REP) == nil and vendorName(DI_REP) == nil and vendorName(99999999) == nil, "no rule, or no vendor in the table: nil")
        local v = HL:GetVendorFor(BLUE)
        check(v.map == 1453 and v.x == 74.4 and v.y == 67.5 and v.npc == 12777 and v.role == "Armor Quartermaster" and v.place == "Champions' Hall, Stormwind City", "the vendor record")
        mock.faction = "Horde"
        check(vendorName(HORDE_WSG_NECK) == "Kelm Hargunth" and vendorName(HORDE_ARMOR) == "Lady Palanseer", "a Horde player gets the Horde vendors")
        check(HL:GetVendorFor(HORDE_ARMOR).x == nil and HL:GetVendorFor(HORDE_ARMOR).map == 1454, "…with no coordinates where none are known")
        mock.faction = "Alliance"

        -- The scanner records where the vendor stands, when the client allows.
        MerchantFrame:Show()
        mock.units.npc = { name = "Test Quartermaster" }
        mock.merchant.items = { { id = BLUE, name = "Premier Plate Helm", price = 0, ext = true, costs = {
            { link = "|cff1eff00|Hcurrency:1792:0|h[Honor]|h|r", count = 9000, name = "Honor" } } } }
        mock.npcGuid = "Creature-0-3-1-0-12777-0000ABCDEF"
        mock.map = { id = 1453, x = 0.744, y = 0.675 }
        mock.zone, mock.subzone = "Stormwind City", "Champions' Hall"
        HL:ScanCurrentVendor(true)
        local rec = HonorLogDB.scannedVendors["Test Quartermaster"]
        check(rec.npc == 12777 and rec.map == 1453 and rec.x == 74.4 and rec.y == 67.5 and rec.zone == "Stormwind City" and rec.subzone == "Champions' Hall"
            and rec.itemCount == 1 and rec.timestamp, "scan record: npc, map, position, zone, subzone, beside the old fields")
        v = HL:GetVendorFor(BLUE)
        check(v.source == "scan" and v.name == "Test Quartermaster" and v.npc == 12777 and v.map == 1453 and v.x == 74.4 and v.place == "Champions' Hall, Stormwind City",
            "a vendor that scanned the item wins over the built-in one")
        mock.npcGuidSecret, mock.map.restricted = true, true
        mock.zone, mock.subzone = mock.newSecret(), mock.newSecret()
        HL:ScanCurrentVendor(true)
        rec = HonorLogDB.scannedVendors["Test Quartermaster"]
        check(rec.npc == nil and rec.x == nil and rec.zone == nil and rec.subzone == nil and rec.map == 1453, "secret or restricted values are left out, nothing errors")
        mock.npcGuidSecret, mock.map.restricted, mock.zone, mock.subzone = false, nil, "Stormwind City", ""
        mock.npcGuid = nil
        HL:ScanCurrentVendor(true)
        check(HonorLogDB.scannedVendors["Test Quartermaster"].npc == nil, "no GUID: no npc id")
        -- An old saved entry (no position) keeps working, and borrows the built-in position of a known vendor.
        HonorLogDB.scannedVendors = { ["Old Vendor"] = { timestamp = 1, itemCount = 2 }, ["Captain Dirgehammer"] = { timestamp = 1, itemCount = 2 } }
        HonorLogDB.scannedGear[BLUE] = { honor = 9000, marks = { AV = 15 }, gold = 0, seen = 1, npc = "Old Vendor" }
        v = HL:GetVendorFor(BLUE)
        check(v.source == "scan" and v.name == "Old Vendor" and v.map == nil and v.place == nil, "an old scan entry without a position still answers")
        check(HL:GetVendorLine(BLUE) == "Sold by Old Vendor", "…and the line has no place")
        HonorLogDB.scannedGear[BLUE].npc = "Captain Dirgehammer"
        v = HL:GetVendorFor(BLUE)
        check(v.source == "scan" and v.x == 74.4 and v.map == 1453 and v.place == "Champions' Hall, Stormwind City", "…borrowing the built-in position for a known name")
        HonorLogDB.scannedGear, HonorLogDB.scannedVendors = {}, {}
        MerchantFrame:Hide()
        mock.units.npc = nil
        mock.merchant.items = {}

        -- The map pin and arrow (UI/MapPin.lua); the game's user waypoint is never touched.
        local MP = HL.MapPin
        local canvas = mock.worldCanvas
        mock.waypoint, mock.superTracked = nil, nil
        mock.worldMap.mapID, mock.worldMap.setCalls, mock.panelShown = 1, {}, nil
        WorldMapFrame:Hide()
        mock.deferTimers = true
        before = #printed
        v = HL:GetVendorFor(BLUE)
        check(HL:ShowVendorOnMap(v) == true, "ShowVendorOnMap with coordinates returns true")
        check(mock.waypoint == nil and mock.superTracked == nil, "C_Map.SetUserWaypoint and C_SuperTrack are never called")
        check(MP:Count() == 1 and MP:GetPin(12777) and MP:GetPin(12777).name == "Captain Dirgehammer", "one pin, keyed by the npc id")
        check(WorldMapFrame:IsShown() and mock.panelShown == 1 and mock.worldMap.mapID == 1453, "out of combat the map opens on the vendor's zone")
        check(table.concat(printed, "\n", before + 1):find("Marked Captain Dirgehammer - Stormwind City on the map.", 1, true), "one line: marked name - map name")
        local pinButton = MP:GetPin(12777).button
        check(pinButton and pinButton:IsShown(), "the pin button is shown on its own map")
        mock.advance(1)
        check(#mock.worldMap.setCalls >= 3, "SetMapID is repeated shortly after, for a client that ignores the first call")
        mock.deferTimers = false

        -- Position: x / 100 of the canvas width, y / 100 of its height from the top-left, undoing the zoom.
        local lastPoint
        local realSetPoint = pinButton.SetPoint
        pinButton.SetPoint = function(self, ...) lastPoint = { ... }; return realSetPoint(self, ...) end
        MP:Refresh()
        check(lastPoint[1] == "CENTER" and lastPoint[2] == canvas and lastPoint[3] == "TOPLEFT"
            and near(lastPoint[4], 744, 1e-6) and near(lastPoint[5], -337.5, 1e-6), "the pin sits at x% of the canvas width and y% of its height")
        mock.canvasScale = 2
        MP:Refresh()
        check(near(lastPoint[4], 1488, 1e-6) and near(lastPoint[5], -675, 1e-6), "zoomed canvas: offset follows the pin's own scale")
        mock.canvasScale = 1
        MP:Refresh()

        -- Other maps: hidden, or projected through an ancestor's rectangle.
        mock.worldMap.mapID = 1454
        MP:Refresh()
        check(not pinButton:IsShown(), "hidden on an unrelated map")
        mock.mapRects["1453:12"] = { 0.2, 0.4, 0.5, 0.9 }
        mock.worldMap.mapID = 12
        MP:Refresh()
        check(pinButton:IsShown() and near(lastPoint[4], (0.2 + 0.744 * 0.2) * 1000, 1e-6) and near(lastPoint[5], -(0.5 + 0.675 * 0.4) * 500, 1e-6), "an ancestor map: the position is projected into its rectangle")
        mock.worldMap.mapID = 1453
        MP:Refresh()

        -- Tooltip.
        tipLines = {}
        pinButton:GetScript("OnEnter")(pinButton)
        check(tipHas("Captain Dirgehammer") and tipHas("Armor Quartermaster") and tipHas("Right-click to remove"), "pin tooltip: name, role, how to remove")

        -- Showing the same place again reuses its pin.
        check(HL:ShowVendorOnMap(v) == true and MP:Count() == 1 and MP:GetPin(12777).button == pinButton, "the same place twice makes one pin")

        -- The pin remembers what the player is buying: the item name and icon.
        check(HL:ShowVendorForItem(BLUE) == true and MP:GetPin(12777).reason == HL:GetGearName(BLUE) and MP:GetPin(12777).icon == 100000 + BLUE % 1000, "ShowVendorForItem adds the item name and icon")
        tipLines = {}
        pinButton:GetScript("OnEnter")(pinButton)
        check(tipHas("For: " .. HL:GetGearName(BLUE)), "pin tooltip: For: <item>")

        -- Right-click removes the pin and the arrow that pointed at it.
        check(MP:GetArrow() and MP:GetTarget() == 12777, "the arrow points at the new pin")
        pinButton:GetScript("OnClick")(pinButton, "RightButton")
        check(MP:Count() == 0 and not pinButton:IsShown() and MP:GetTarget() == nil, "right-click removes the pin and the arrow's target")
        check(MP:GetArrow():GetScript("OnUpdate") == nil, "no target: no OnUpdate script")

        -- A vendor with a map but no coordinates: the map opens, no pin, false, and a line says why.
        mock.faction = "Horde"
        mock.worldMap.mapID, mock.panelShown = 1, nil
        WorldMapFrame:Hide()
        mock.map = { id = 1454 }
        before = #printed
        local noXY = { name = "Lady Palanseer", map = 1454, place = "Hall of Legends, Orgrimmar" }
        check(HL:ShowVendorOnMap(noXY) == false and MP:Count() == 0, "a map without coordinates: false, no pin")
        check(mock.worldMap.mapID == 1454 and WorldMapFrame:IsShown(), "…but the map opens on that zone")
        check(table.concat(printed, "\n", before + 1):find("Lady Palanseer is in Orgrimmar. Open the vendor once and HonorLog will remember exactly where it stands.", 1, true), "…and the line says to open the vendor once")
        mock.map = { id = 1453, x = 0.744, y = 0.675 }
        before = #printed
        check(HL:ShowVendorOnMap(HL:GetVendorFor(HORDE_ARMOR)) == false and MP:Count() == 0 and mock.waypoint == nil, "a built-in vendor with a map and no position: false, no pin")
        check(table.concat(printed, "\n", before + 1):find("Lady Palanseer is in ", 1, true), "…and the line names the vendor and the zone")
        before = #printed
        check(HL:ShowVendorOnMap({ name = "Lady Palanseer", place = "Hall of Legends, Orgrimmar" }) == false and MP:Count() == 0, "no map at all: false, no pin")
        check(table.concat(printed, "\n", before + 1):find("Lady Palanseer, Hall of Legends, Orgrimmar: open this vendor once and HonorLog will remember where it stands.", 1, true), "…the older line is kept")
        mock.faction = "Alliance"
        check(HL:ShowVendorOnMap(nil) == false, "no vendor: false")

        -- Combat: the pin is kept, the map is not opened, and the line names the key.
        mock.worldMap.mapID, mock.panelShown = 1, nil
        WorldMapFrame:Hide()
        mock.combat = true
        before = #printed
        check(HL:ShowVendorOnMap(v) == true and MP:Count() == 1, "combat: the pin is still placed")
        check(not WorldMapFrame:IsShown() and mock.panelShown == nil and mock.worldMap.mapID == 1, "combat: the map is not opened")
        check(table.concat(printed, "\n", before + 1):find("The map can't open during combat. Press M to see the marked spot.", 1, true) and MP:GetJumpKey() == 12777, "combat: the line names the key, and the jump is remembered")
        mock.combat = false
        ShowUIPanel(WorldMapFrame)
        check(mock.worldMap.mapID == 1453 and MP:GetJumpKey() == nil, "the next time the map shows it jumps to the pin once")
        WorldMapFrame:Hide()
        mock.worldMap.mapID = 1
        ShowUIPanel(WorldMapFrame)
        check(mock.worldMap.mapID == 1, "…and only once")

        -- Combat with the map already open: the open map switches to the pin, nothing is deferred.
        mock.combat = true
        before = #printed
        check(HL:ShowVendorOnMap(v) == true and mock.worldMap.mapID == 1453 and MP:GetJumpKey() == nil, "combat with the map open: it switches to the pin")
        check(table.concat(printed, "\n", before + 1):find("Marked Captain Dirgehammer - Stormwind City on the map.", 1, true), "…and the usual line is printed")
        mock.combat = false

        -- While the map is open with a pin, a ticker redraws it; it stops when the map closes.
        local ticker = MP:GetMapTicker()
        check(ticker ~= nil and not ticker.cancelled, "an open map with a pin has a redraw ticker")
        mock.worldMap.mapID = 99 -- changed behind the hooks' back
        ticker.fn()
        check(not MP:GetPin(12777).button:IsShown(), "the ticker hides the pin when the map changed without a notification")
        mock.worldMap.mapID = 1453
        ticker.fn()
        check(MP:GetPin(12777).button:IsShown(), "…and shows it again on its own map")
        WorldMapFrame:Hide()
        ticker.fn()
        check(ticker.cancelled and MP:GetMapTicker() == nil, "the ticker stops when the map closes")

        -- The arrow: distance, arrival, instances, secret and missing reads. World axes: x grows to the north and
        -- y to the west, in that order from both UnitPosition and C_Map's vector.
        local arrowFrame = MP:GetArrow()
        check(arrowFrame:GetScript("OnUpdate") ~= nil, "with a target the arrow has an OnUpdate")
        check(arrowFrame.honorLogTexture.__atlas == "UI-WorldMapArrow", "the arrow uses the world map's own player arrow")
        mock.worldPos[1453] = { 0, 1000, 2000 }
        mock.unitPosition = { 1000 - 30, 2000 - 40, 0, 0 } -- 30 south and 40 east of the target
        mock.facing = 0
        MP:GetPin(12777).world = nil
        MP:UpdateArrow()
        check(MP.arrowInfo.state == "ready" and near(MP.arrowInfo.distance, 50, 1e-6) and MP.arrowInfo.text == "50 yds", "the arrow reports 50 yards for a 30/40 offset")
        check(arrowFrame.honorLogDistance:GetText() == "50 yds" and arrowFrame.honorLogName:GetText() == "Captain Dirgehammer", "the arrow shows the name and the distance")
        check(arrowFrame.honorLogTexture:GetRotation() ~= nil, "the arrow graphic is rotated")
        mock.unitPosition = { 1000 - 10, 2000, 0, 0 }
        MP:UpdateArrow()
        check(near(arrowFrame.honorLogTexture:GetRotation(), 0, 1e-6), "facing north with the target due north: no rotation")
        mock.unitPosition = { 1000, 2000 - 10, 0, 0 }
        MP:UpdateArrow()
        check(near(arrowFrame.honorLogTexture:GetRotation(), math.pi / 2, 1e-6), "facing north with the target due west: a quarter turn to the left")
        mock.facing = math.pi / 2
        MP:UpdateArrow()
        check(near(arrowFrame.honorLogTexture:GetRotation(), 0, 1e-6), "facing west with the target due west: straight ahead")
        mock.unitPosition = { 1000 - 10, 2000, 0, 0 }
        MP:UpdateArrow()
        check(near(arrowFrame.honorLogTexture:GetRotation(), -math.pi / 2, 1e-6), "facing west with the target due north: a quarter turn to the right")
        mock.facing = 0
        -- Another continent: no rotation, "In <map>".
        mock.unitPosition = { 1000 - 30, 2000 - 40, 0, 530 }
        MP:UpdateArrow()
        check(MP.arrowInfo.state == "far" and arrowFrame.honorLogDistance:GetText() == "In Stormwind City", "another continent: the target's map name")
        mock.unitPosition = { 1000 - 30, 2000 - 40, 0, 0 }
        -- Secret or missing reads never raise, and just hide the graphic.
        mock.positionSecret = true
        check(pcall(MP.UpdateArrow, MP) and MP.arrowInfo.state == "unknown", "a secret position: no error, the graphic is hidden")
        mock.positionSecret = false
        local savedPos = mock.unitPosition
        mock.unitPosition = nil
        check(pcall(MP.UpdateArrow, MP) and MP.arrowInfo.state == "unknown", "a missing position: no error")
        mock.unitPosition = savedPos
        local savedFacing = mock.facing
        mock.facing = nil
        check(pcall(MP.UpdateArrow, MP) and MP.arrowInfo.state == "no-facing", "no facing: no error")
        mock.facing = savedFacing
        -- Inside an instance the arrow waits, then comes back.
        mock.inInstance = true
        MP:UpdateArrow()
        check(MP.arrowInfo.state == "instance" and arrowFrame:GetAlpha() == 0 and MP:Count() == 1, "inside an instance the arrow is hidden")
        mock.inInstance = false
        MP:UpdateArrow()
        check(arrowFrame:GetAlpha() == 1 and MP.arrowInfo.state == "ready", "…and returns outside")
        -- The throttled OnUpdate: ticks under 0.1 s do nothing.
        mock.unitPosition = { 1000 - 30, 2000 - 40, 0, 0 }
        MP.arrowInfo.text = "stale"
        arrowFrame:GetScript("OnUpdate")(arrowFrame, 0.05)
        check(MP.arrowInfo.text == "stale", "OnUpdate is throttled")
        arrowFrame:GetScript("OnUpdate")(arrowFrame, 0.06)
        check(MP.arrowInfo.text == "50 yds", "…and updates after 0.1 s")
        -- Right-click on the arrow hides it and keeps the pin; left-click opens the map.
        arrowFrame:GetScript("OnClick")(arrowFrame, "LeftButton")
        check(mock.worldMap.mapID == 1453 and WorldMapFrame:IsShown(), "left-click on the arrow opens the map on the pin")
        arrowFrame:GetScript("OnDragStop")(arrowFrame)
        check(type(HL.db.settings.mapArrowPoint) == "table", "dragging saves the arrow's position")
        arrowFrame:GetScript("OnClick")(arrowFrame, "RightButton")
        check(MP:Count() == 1 and not arrowFrame:IsShown() and arrowFrame:GetScript("OnUpdate") == nil, "right-click on the arrow: arrow gone, pin kept, no OnUpdate")
        -- Arrival.
        check(HL:ShowVendorOnMap(v) == true and arrowFrame:GetScript("OnUpdate") ~= nil, "showing the place again brings the arrow back")
        mock.unitPosition = { 1000 - 4, 2000 - 3, 0, 0 }
        MP:UpdateArrow()
        check(MP.arrowInfo.state == "arrived" and not arrowFrame:IsShown() and arrowFrame:GetScript("OnUpdate") == nil and MP:Count() == 1, "within 8 yards the arrow goes away and the pin stays")

        -- Opening the pinned vendor clears the pin.
        mock.units.npc = { name = "Somebody Else" }
        mock.npcGuid = "Creature-0-3-1-0-99999-0000ABCDEF"
        mock.fireEvent("MERCHANT_SHOW"); mock.flushTimers()
        check(MP:Count() == 1, "another vendor's window leaves the pin")
        mock.units.npc = { name = "Captain Dirgehammer" }
        mock.npcGuid = "Creature-0-3-1-0-12777-0000ABCDEF"
        mock.fireEvent("MERCHANT_SHOW"); mock.flushTimers()
        check(MP:Count() == 0, "MERCHANT_SHOW for the pinned vendor clears its pin")
        -- Without an npc id the name decides.
        HL:ShowPlaceOnMap({ map = 1453, x = 50, y = 50, name = "Nameless Vendor", kind = "vendor" })
        check(MP:Count() == 1, "a vendor pin without an npc is keyed by map and position")
        mock.npcGuid = nil
        mock.units.npc = { name = "Nameless Vendor" }
        mock.fireEvent("MERCHANT_SHOW"); mock.flushTimers()
        check(MP:Count() == 0, "…and cleared by name when the npc id is unknown")
        mock.units.npc = nil
        mock.merchant.items = {}
        MerchantFrame:Hide()
        -- A place that is not a vendor stays when a vendor opens; /honorlog vendor clear removes it.
        HL:ShowPlaceOnMap({ map = 1453, x = 10, y = 20, name = "Kill spot", kind = "place" })
        check(HL:ShowPlaceOnMap({ map = 1453, name = "Broken" }) == false and HL:ShowPlaceOnMap(nil) == false, "an incomplete place is refused")
        check(MP:Count() == 1, "a place pin is made for any place")
        before = #printed
        -- (the file-level slash handler belongs to the first load; use the current one)
        SlashCmdList.HONORLOG("vendor clear")
        check(MP:Count() == 0 and MP:GetTarget() == nil and table.concat(printed, "\n", before + 1):find("Cleared the map pins and the arrow.", 1, true), "/honorlog vendor clear clears the pins and the arrow")
        check(HL:ClearMapPins("nothing") == 0, "clearing an unknown key removes nothing")
        mock.worldMap.mapID, mock.map = 1, { id = 1453, x = 0.744, y = 0.675 }

        -- Tooltips and Alt+Click on a goal card and a picker row.
        HL:AddGoal(BLUE)
        HL:UpdateGoalsPanel()
        card = goalsPanel.goalCards[1]
        tipLines = {}
        card:GetScript("OnEnter")(card)
        check(tipHas("Sold by Captain Dirgehammer, Champions' Hall, Stormwind City") and tipHas("Alt+Click to show the vendor on the map"), "goal card tooltip: sold by, and the Alt+Click hint")
        card:GetScript("OnMouseUp")(card, "LeftButton")
        check(MP:Count() == 0, "a plain click on a card marks nothing")
        mock.alt = true
        card:GetScript("OnMouseUp")(card, "LeftButton")
        check(MP:Count() == 1 and MP:GetPin(12777), "Alt+Click on a goal card marks the vendor on the map")
        HL:ClearMapPins()
        mock.alt = false
        HL:RemoveGoal(BLUE)
        picker.filters.class = "WARRIOR"
        picker:RefreshItems()
        local prow = pickerRow(BLUE)
        check(prow ~= nil, "the picker lists the helm again")
        tipLines = {}
        prow:GetScript("OnEnter")(prow)
        check(tipHas("Sold by Captain Dirgehammer, Champions' Hall, Stormwind City") and tipHas("Alt+Click to show the vendor on the map"), "picker row tooltip: sold by, and the Alt+Click hint")
        mock.alt = true
        prow:GetScript("OnMouseUp")(prow, "LeftButton")
        check(MP:Count() == 1 and MP:GetPin(12777), "Alt+Click on a picker row marks the vendor on the map")
        HL:ClearMapPins()
        mock.alt = false
        picker:Hide()

        -- /honorlog vendor
        HL:AddGoal(EPIC)
        before = #printed
        SlashCmdList.HONORLOG("vendor 1")
        check(MP:Count() == 1 and MP:GetPin(12777), "/honorlog vendor 1: the first goal's vendor")
        HL:ClearMapPins()
        SlashCmdList.HONORLOG("vendor item " .. BLUE)
        check(MP:Count() == 1 and table.concat(printed, "\n", before + 1):find("Marked Captain Dirgehammer", 1, true), "/honorlog vendor <item name>: any gear item")
        HL:ClearMapPins()
        SlashCmdList.HONORLOG("vendor zzz no such thing")
        check(MP:Count() == 0 and table.concat(printed, "\n", before + 1):find("No gear item matches", 1, true), "/honorlog vendor: an unknown name says so")
        SlashCmdList.HONORLOG("vendor")
        check(table.concat(printed, "\n", before + 1):find("Usage: /honorlog vendor", 1, true), "/honorlog vendor with nothing prints the usage")
        SlashCmdList.HONORLOG("goal vendor 1")
        HL:RemoveGoal(EPIC)

        -- 5. Honor cap advice -----------------------------------------------------
        mock.level = 35
        setRankR(3, 100, 6, 3, 5)
        mock.bagItems = { [20560] = 5, [20558] = 12, [20559] = 3, [274895] = 0 }
        char.history = {}
        measuredGames(30, 20, 120, 30)
        HL.db.settings.goalCapAdvice, HL.db.settings.honorCapWarning, HL.db.settings.honorCapWarnPct = true, true, 90
        HL:AddGoal(BLUE)
        -- A known honor per game: 10,000 honor over 30 games.
        savedStats = HL.Util.DeepCopy(HL.db.char.battlegrounds)
        for _, bg in pairs(HL.db.char.battlegrounds) do bg.played, bg.honorLifetime, bg.cappedPlayed, bg.cappedHonor = 0, 0, 0, 0 end
        local bgs = HL.db.char.battlegrounds
        bgs.AV.played, bgs.AV.honorLifetime, bgs.WSG.played, bgs.WSG.honorLifetime, bgs.AB.played, bgs.AB.honorLifetime = 10, 5000, 10, 3000, 10, 2000
        local expected = HL:GetAverageHonorPerGame()
        check(near(expected, 10000 / 30, 1e-6), "an honor per game is measured: " .. tostring(expected))
        mock.currencies[1792].quantity = 25000 - math.ceil(expected * 13.5)
        local advice = HL:GetHonorCapAdvice()
        check(advice and advice.blocked and advice.gamesToCap == 14, "cap advice: blocked by level, 14 games away: " .. tostring(advice and advice.gamesToCap))
        check(advice.text == "You'll reach the 25,000 honor cap in about 14 games and nothing on your list can be bought before level 55.", "the sentence: " .. tostring(advice and advice.text))
        check(type(advice.buyable) == "table" and #advice.buyable <= 3, "the advice carries up to three buyable items")
        mock.currencies[1792].maxQuantity = 30000
        mock.currencies[1792].quantity = 30000 - math.ceil(expected * 13.5)
        advice = HL:GetHonorCapAdvice()
        check(advice.text:find("30,000", 1, true) and not advice.text:find("25,000", 1, true), "the cap number comes from the client")
        mock.currencies[1792].maxQuantity = 25000
        mock.currencies[1792].quantity = 25000 - math.ceil(expected * 0.5)
        advice = HL:GetHonorCapAdvice()
        check(advice.text:find("in about 1 game and", 1, true), "one game away reads '1 game'")
        mock.currencies[1792].quantity = 25000
        advice = HL:GetHonorCapAdvice()
        check(advice.text == "You are at the 25,000 honor cap and nothing on your list can be bought before level 55.", "at the cap: " .. tostring(advice.text))
        mock.currencies[1792].quantity = 8200
        check(HL:GetHonorCapAdvice() == nil, "far from the cap: no advice")
        mock.currencies[1792].quantity = 25000 - math.ceil(expected * 13.5)
        mock.level = 60
        advice = HL:GetHonorCapAdvice()
        check(advice == nil or not advice.blocked, "once the level is met the goal is no longer blocked")
        HL:RemoveGoal(BLUE)
        -- Rank-gated goal at a good level: generic sentence
        HL:AddGoal(EPIC)
        advice = HL:GetHonorCapAdvice()
        check(advice and advice.blocked and advice.text == "You'll reach the 25,000 honor cap in about 14 games and nothing on your list can be bought yet because of level, rank or reputation.",
            "a rank-gated goal: the generic sentence: " .. tostring(advice and advice.text))
        -- A goal that is not gated keeps the old advice.
        HL:AddGoal(LOW_LEVEL)
        mock.bagItems[20560] = 15
        advice = HL:GetHonorCapAdvice()
        check(advice == nil or not advice.blocked, "one goal without a gate: not blocked")
        HL:RemoveGoal(LOW_LEVEL)

        -- What the character could buy right now.
        mock.level, mock.bagItems = 60, { [20560] = 15, [20559] = 15, [20558] = 15, [274895] = 15 }
        mock.currencies[1792].quantity = 24000
        mock.bagContents, mock.equipped = {}, {}
        local buy = HL:GetBuyableNow(3)
        check(#buy == 3, "three things could be bought: " .. #buy)
        local okBuy = true
        for i, entry in ipairs(buy) do
            local it = HL:GetGearItem(entry.itemID)
            okBuy = okBuy and it.reqLevel <= 60 and (it.rank == nil or it.rank <= 3) and it.honor <= 24000 and (not it.faction or it.faction == "Alliance")
                and it.source ~= "UPGRADE" and (not it.class or it.class == "WARRIOR")
            if i > 1 then okBuy = okBuy and buy[i - 1].weight >= entry.weight end
        end
        check(okBuy, "each buyable item meets level, rank, faction, class and honor, most expensive first")
        local firstBuy = buy[1].itemID
        mock.bagItems[firstBuy] = 1
        buy = HL:GetBuyableNow(3)
        check(buy[1].itemID ~= firstBuy, "an item already owned is not offered")
        mock.bagItems[firstBuy] = nil
        mock.currencies[1792].quantity = 100
        check(#HL:GetBuyableNow(3) == 0 or HL:GetBuyableNow(3)[1].honor <= 100, "with no honor, nothing that costs honor is offered")
        mock.level = 1
        for _, entry in ipairs(HL:GetBuyableNow(3)) do check(HL:GetGearItem(entry.itemID).reqLevel <= 1, "level 1 buys only level 0-1 items") end
        mock.level = 60
        mock.currencies[1792].quantity = 25000 - math.ceil(expected * 13.5)
        advice = HL:GetHonorCapAdvice()
        check(advice.blocked and #advice.buyable > 0, "the advice lists what could be bought")
        before = #printed
        slash("goal advice")
        local adviceOut = table.concat(printed, "\n", before + 1)
        check(adviceOut:find("nothing on your list can be bought", 1, true) and adviceOut:find("You could buy right now:", 1, true)
            and adviceOut:find(advice.buyable[1].name, 1, true), "/honorlog goal advice prints the sentence and the buyable items")
        HL:UpdateGoalsPanel()
        check(goalsPanel.adviceBar:IsShown() and goalsPanel.adviceBar.text:GetText():find("nothing on your list can be bought", 1, true), "the goals header shows the sentence")
        HL:RemoveGoal(EPIC)

        -- 6. Bug fixes ------------------------------------------------------------
        -- Export: real CSV with quoting.
        HL:RecordGame("AB", true, 60, 1, 0, { objectives = { ['Flag "caps", total'] = 3 } })
        local csv2 = HL:GenerateCSVExport("character")
        check(not csv2:find("\t", 1, true), "CSV has no tabs")
        check(csv2:find('"Flag ""caps"", total 3"', 1, true), "CSV quotes a field with commas and doubles its quotes")
        check(csv2:find("Battleground,Played,Wins,Losses,Draws,Left,Winrate,Avg Duration (s),Honor,Marks", 1, true), "CSV header is comma separated")
        for line in csv2:gmatch("[^\n]+") do
            if line:find("^%d%d%d%d%-%d%d%-%d%d ") then
                local cols = 0
                local inQuote = false
                for ch in line:gmatch(".") do
                    if ch == '"' then inQuote = not inQuote elseif ch == "," and not inQuote then cols = cols + 1 end
                end
                check(cols == 13, "every games row has 14 fields: " .. line)
                break
            end
        end
        -- Export window: contents on open, format argument, setting.
        HL.db.settings.exportFormat = "text"
        slash("export csv")
        local ef = _G.HonorLogExportFrame
        check(ef and ef:IsShown(), "the export window opens")
        local body = ef.editBox:GetText()
        check(type(body) == "string" and #body > 0, "the export window is not empty on open")
        check(body:find("Battleground,Played,Wins", 1, true) and not body:find("HonorLog Summary", 1, true), "/honorlog export csv shows CSV")
        check(ef.formatDropdown.__ddText == "CSV (Spreadsheet)" and ef.GetCurrentFormat() == "csv", "…under the CSV label")
        ef:Hide()
        slash("export text")
        check(ef:IsShown() and ef.editBox:GetText():find("HonorLog Summary", 1, true) and ef.GetCurrentFormat() == "text", "/honorlog export text shows text")
        ef:Hide()
        HL.db.settings.exportFormat = "csv"
        slash("export")
        check(ef.GetCurrentFormat() == "csv" and ef.editBox:GetText():find("Battleground,Played,Wins", 1, true), "with no argument the Export Format setting decides (csv)")
        ef:Hide()
        HL.db.settings.exportFormat = "text"
        slash("export")
        check(ef.GetCurrentFormat() == "text" and ef.editBox:GetText():find("HonorLog Summary", 1, true), "…and text")
        ef:Hide()
        slash("export bogus")
        check(ef.GetCurrentFormat() == "text", "an unknown format falls back to the setting")
        local pickedBody = ef.editBox:GetText()
        mock.pickDropdown(ef.formatDropdown, "CSV (Spreadsheet)")
        check(ef.editBox:GetText() ~= pickedBody and ef.editBox:GetText():find("Battleground,Played,Wins", 1, true), "the dialog's format dropdown switches the contents")
        ef:Hide()
        local optionsDropdown = _G.HonorLogExportFormatDropdown
        check(optionsDropdown and optionsDropdown.setting == "exportFormat" and optionsDropdown ~= ef.formatDropdown
            and _G.HonorLogExportDialogFormatDropdown == ef.formatDropdown, "the Options and export dialog dropdowns have different frame names")
        mock.pickDropdown(optionsDropdown, "CSV (Spreadsheet)")
        check(HL.db.settings.exportFormat == "csv", "the Options dropdown writes the setting")
        HL.db.settings.exportFormat = "text"

        -- Gear picker: the dropdowns drive the filters the list reads.
        HL:ShowGoalPicker()
        picker = _G.HonorLogGoalPicker
        picker.filters.class = nil
        picker:RefreshItems()
        local function allMatch(pred)
            if #picker.shownItems == 0 then return false end
            for _, e in ipairs(picker.shownItems) do if not pred(e.data) then return false end end
            return true
        end
        mock.pickDropdown(_G.HonorLogSlotDropdown, "Head")
        check(picker.filters.slot == "HEAD" and allMatch(function(d) return d.slot == "HEAD" end), "slot dropdown: Head filters the list")
        mock.pickDropdown(_G.HonorLogSourceDropdown, "Honor")
        check(picker.filters.source == "HONOR" and allMatch(function(d) return d.slot == "HEAD" and d.source == "HONOR" end), "source dropdown: Honor filters the list")
        mock.pickDropdown(_G.HonorLogSlotDropdown, "All Slots")
        check(picker.filters.slot == nil and allMatch(function(d) return d.source == "HONOR" end) and #picker.shownItems > 0, "All Slots clears the slot filter")
        mock.pickDropdown(_G.HonorLogSourceDropdown, "All Sources")
        mock.pickDropdown(_G.HonorLogClassDropdown, "Mage")
        check(picker.filters.class == "MAGE" and allMatch(function(d) return d.class == nil or d.class == "MAGE" end), "class dropdown: Mage filters the list")
        local mageCount = #picker.shownItems
        mock.pickDropdown(_G.HonorLogClassDropdown, "Any class")
        check(picker.filters.class == nil and #picker.shownItems > mageCount, "Any class clears the class filter")
        mock.pickDropdown(_G.HonorLogArmorDropdown, "Cloth")
        check(picker.filters.armor == "CLOTH" and allMatch(function(d) return d.armor == "CLOTH" end), "armor dropdown: Cloth filters the list")
        mock.pickDropdown(_G.HonorLogArmorDropdown, "Any armor")
        check(picker.filters.armor == nil and picker.filters.filterSlot == nil and picker.filters.filterClass == nil, "no stray filter keys")
        picker:Hide()

        -- Header drag respects "Lock Frame Position"; the dead timer is gone.
        local main = HL.mainFrame
        local moves = 0
        main.StartMoving = function() moves = moves + 1 end
        HL.db.settings.frameLocked = true
        main.header:GetScript("OnDragStart")(main.header)
        check(moves == 0, "a locked frame does not move from its header")
        HL.db.settings.framePoint = nil
        main.header:GetScript("OnDragStop")(main.header)
        check(HL.db.settings.framePoint == nil, "…and a stop without a start saves nothing")
        HL.db.settings.frameLocked = false
        main.header:GetScript("OnDragStart")(main.header)
        check(moves == 1, "an unlocked frame moves from its header")
        main.header:GetScript("OnDragStop")(main.header)
        check(HL.db.settings.framePoint ~= nil, "…and saves its position")
        main.StartMoving = nil
        local mf = io.open(ROOT .. "/UI/MainFrame.lua"):read("*a")
        check(not mf:find("self.currentTab", 1, true) and not mf:find("UpdateFrameLayout", 1, true), "the dead timer and the undefined UpdateFrameLayout call are gone")

        -- 7. Probe ------------------------------------------------------------------
        slash("probe on")
        local probeLog = HonorLogDB.probe.log
        local function lastEvent(name)
            for i = #probeLog, 1, -1 do if probeLog[i].event == name then return probeLog[i] end end
        end
        mock.npcGuid = "Creature-0-3-1-0-12777-0000ABCDEF"
        mock.map = { id = 1453, x = 0.744, y = 0.675 }
        mock.fireEvent("MERCHANT_SHOW")
        local m1 = lastEvent("MERCHANT_READ")
        check(m1 and m1.args[1] == true and m1.args[2] == true and m1.npc == 12777 and m1.map == 1453, "probe at MERCHANT_SHOW: GUID readable, position available")
        mock.npcGuidSecret, mock.map.restricted = true, true
        mock.fireEvent("MERCHANT_SHOW")
        local m2 = lastEvent("MERCHANT_READ")
        check(m2 ~= m1 and m2.args[1] == false and m2.args[2] == false, "probe at MERCHANT_SHOW: nothing readable")
        mock.npcGuidSecret, mock.map.restricted, mock.npcGuid = false, nil, nil
        mock.reputation[509] = 5
        mock.repAmounts[509] = { current = 3500, floor = 3000, ceiling = 9000 }
        playGame("Arathi Basin", 529, function() mock.repAmounts[509].current = 3650 end)
        local rp = lastEvent("REP_DELTA")
        check(rp and rp.faction == 509 and rp.startAmount == 3500 and rp.endAmount == 3650 and rp.gained == 150 and rp.readable == true, "probe after a game: the reputation delta read")

        -- Quest rewards: the offer is read when a quest window opens, the real change when it is handed in.
        -- (The file-level slash() belongs to the first load; the reloaded addon's own probe has the live frame.)
        SlashCmdList.HONORLOG("probe on")
        mock.quest = { id = 8426, title = "Battle of Warsong Gulch", money = 4500, xp = 0, honor = 10,
            rewards = { { "Some Token", 134400, 1, 2, true, 99999 } } }
        mock.fireEvent("QUEST_DETAIL")
        local q = HonorLogDB.probe.quests and HonorLogDB.probe.quests[8426]
        check(q and q.title == "Battle of Warsong Gulch" and q.offer.money == 4500 and q.offer.honor == 10
            and q.offer.items[1][1] == "Some Token" and q.offer.items[1][6] == 99999 and q.offerFrom == "QUEST_DETAIL", "probe at QUEST_DETAIL: the offer is stored by quest id")
        check(q.pvp == true and q.turnIns == 0, "an offer that pays honor marks the quest as PvP")
        local logBeforeQuest = #HonorLogDB.probe.log
        mock.deferTimers = true
        mock.fireEvent("QUEST_COMPLETE")
        check(q.offerFrom == "QUEST_COMPLETE", "the hand-in window refreshes the offer")
        mock.currencies[1792].quantity = mock.currencies[1792].quantity + 10
        mock.rank.earned = mock.rank.earned + 500
        mock.bagItems[20558] = mock.bagItems[20558] - 3
        mock.money = mock.money + 4500
        mock.fireEvent("QUEST_TURNED_IN", 8426, 0, 4500)
        check(q.turnIns == 1 and q.last.measured == false and q.last.money == 4500, "probe at QUEST_TURNED_IN: counted at once, measured a moment later")
        mock.flushTimers()
        mock.deferTimers = false
        check(q.last.measured == true and q.last.honor == 10 and q.last.rank == 500 and q.last.moneyChange == 4500 and q.last.marks.WSG_20558 == -3,
            "…then honor, rank points, money and marks are measured: " .. tostring(q.last.honor) .. "/" .. tostring(q.last.rank) .. "/" .. tostring(q.last.moneyChange))
        check(next(q.last.marks, "WSG_20558") == nil, "only the marks that changed are listed")
        check(#HonorLogDB.probe.log == logBeforeQuest, "quest readings stay out of the ring log")
        mock.currencies[1792].quantity = mock.currencies[1792].quantity - 10
        mock.rank.earned = mock.rank.earned - 500
        mock.bagItems[20558] = mock.bagItems[20558] + 3
        mock.money = mock.money - 4500
        -- A quest handed in without its window is counted, not measured, and a secret id is ignored.
        mock.fireEvent("QUEST_TURNED_IN", 777, 100, 0)
        local q2 = HonorLogDB.probe.quests[777]
        check(q2 and q2.turnIns == 1 and q2.last.measured == false and q2.pvp == nil, "a hand-in without its window is counted, not measured")
        check(pcall(mock.fireEvent, "QUEST_TURNED_IN", mock.newSecret(), 0, 0), "a secret quest id raises nothing")
        mock.quest = nil
        check(pcall(mock.fireEvent, "QUEST_DETAIL"), "no quest window: nothing raised")
        -- The store is capped; records that never touched honor, rank points or marks go first.
        for i = 1, 320 do
            mock.quest = { id = 100000 + i, title = "Filler " .. i }
            mock.fireEvent("QUEST_DETAIL")
        end
        mock.quest = nil
        local questCount = 0
        for _ in pairs(HonorLogDB.probe.quests) do questCount = questCount + 1 end
        check(questCount == 300 and HonorLogDB.probe.quests[8426] ~= nil and HonorLogDB.probe.quests[777] == nil, "the quest store caps at 300 and keeps the PvP quest: " .. questCount)
        local printedBeforeStatus = #printed
        SlashCmdList.HONORLOG("probe status")
        check(table.concat(printed, "\n", printedBeforeStatus + 1):find("quests seen: 300 (1 paid honor, rank points or marks)", 1, true), "probe status counts the quests")

        SlashCmdList.HONORLOG("probe off")
        slash("probe off")
        mock.quest = { id = 555, title = "Seen while off" }
        mock.fireEvent("QUEST_DETAIL")
        mock.quest = nil
        check(HonorLogDB.probe.quests[555] == nil, "a disarmed probe stores no quests")
        local countBefore = #HonorLogDB.probe.log
        mock.fireEvent("MERCHANT_SHOW")
        check(#HonorLogDB.probe.log == countBefore, "a disarmed probe logs nothing at MERCHANT_SHOW")
        slash("probe clear")

        -- 8. Docs and tools ------------------------------------------------------
        local function slurp(path) local f = io.open(ROOT .. "/" .. path) local t = f and f:read("*a") f:close() return t or "" end
        local release = slurp(".github/workflows/release.yml")
        check(release:find("--exclude='.luacheckrc'", 1, true), "the release zip leaves out .luacheckrc")
        check(not release:find("tail -n +3 CHANGELOG.md", 1, true) and release:find("n == 1", 1, true), "the release notes are the newest changelog section")
        local agent = slurp("tools/build_gear.py"):match('USER_AGENT = "([^"]*)"') or ""
        check(agent ~= "" and not agent:lower():find("honor", 1, true) and not agent:lower():find("adbergen", 1, true) and not agent:find("github", 1, true), "the build tool's User-Agent names no project or repository")
        local readme, listing, changes = slurp("README.md"), slurp("docs/listing.md"), slurp("CHANGELOG.md")
        check(readme:find("honor per hour", 1, true) and listing:find("honor per hour", 1, true), "README and listing mention honor per hour")
        check(readme:find("Level 35 / 55", 1, true) and readme:find("Reputation forecast", 1, true) and readme:find("Alt+Click", 1, true), "README covers level, reputation and vendors")
        check(listing:find("Reputation forecast", 1, true) and listing:find("Vendor locations", 1, true), "listing covers reputation and vendors")
        check(changes:find("Gear goals tell the truth", 1, true), "the changelog has this round")
        check(slurp("Data/Vendors.lua"):find("Wowhead Forever NPC tooltip API", 1, true), "Vendors.lua carries its source line")

        -- Restore what the block changed.
        HL.db.char.battlegrounds = savedStats
        char.gateDisproved = nil
        GameTooltip.AddLine = realAddLine
        HL:SwitchTab("stats")
        HL:SetExpanded(false)
        char.history, mock.level, mock.faction, mock.money, mock.bagItems = saved.history, saved.level, saved.faction, saved.money, saved.bag
        mock.currencies[1792].quantity, mock.currencies[1792].maxQuantity, mock.rank = saved.honor, saved.cap, saved.rank
        mock.rankWindow.cap, mock.rankWindow.week, mock.rankWindow.prevCap = saved.window.cap, saved.window.week, saved.window.prevCap
        char.goals.items, char.goals.completed, mock.seasonSeconds = saved.goals, saved.completed, saved.seconds
        HonorLogDB.scannedGear, HonorLogDB.scannedVendors, HL.db.settings.goalProgressMode = saved.gear, saved.vendors, saved.mode
        mock.reputation, mock.repAmounts, mock.repSecret, mock.alt = {}, {}, {}, false
        mock.pvp.matchComplete = false
        check(not printedMatching("HonorLog ERROR"), "round 6 raised no error line: " .. tostring(printedMatching("HonorLog ERROR")))
        check(#mock.handledErrors == 0, "round 6 reached no error handler: " .. tostring(mock.handledErrors[1]))
    end

    -- 11. Migration: a TBC-era save with EotS and arena fields loads, migrates, keeps its history.
    local fixture = dofile(ROOT .. "/Tests/fixtures/tbc_savedvars.lua")
    fixture.char.opponents = { Frac = { kills = 1, deaths = 0, lastSeen = 1794894684.0000069 } }
    HonorLogDB, HonorLogCharDB = fixture.global, fixture.char
    HL:InitializeDB()
    check(HonorLogDB.dbVersion == 2 and HonorLogCharDB.dbVersion == 2, "dbVersion 2 after migration")
    check(HonorLogDB.battlegrounds.EotS == nil and HonorLogCharDB.battlegrounds.EotS == nil, "EotS leaves the tracked battlegrounds")
    check(HonorLogDB.legacy.EotS.played == 8 and HonorLogCharDB.legacy.EotS.wins == 5, "EotS aggregates kept under legacy")
    check(HonorLogDB.legacy.Arena2v2 and HonorLogDB.battlegrounds.Arena2v2 == nil, "arena aggregate moved to legacy")
    check(HonorLogDB.battlegrounds.AV.played == 10 and HonorLogDB.battlegrounds.WSG.wins == 15, "tracked battleground stats untouched")
    check(HonorLogDB.battlegrounds.DI and HonorLogDB.battlegrounds.DI.played == 0 and HonorLogDB.battlegrounds.AV.draws == 0 and HonorLogDB.battlegrounds.AV.left == 0,
        "DI defaults added, draws and left start at zero")
    check(HonorLogCharDB.session.EotS == nil and HonorLogCharDB.session.DI and HonorLogCharDB.session.AB.honor == 400, "session migrated")
    check(HonorLogCharDB.bgState.isInBG == false, "a TBC mid-game state is dropped")
    -- Saved TBC goals are archived once: unknown ids leave the active and completed lists, Forever ids stay.
    check(#HonorLogCharDB.goals.items == 1 and HonorLogCharDB.goals.items[1].itemID == 272738 and HonorLogCharDB.goals.items[1].priority == 1, "TBC goals leave the active list")
    check(#HonorLogCharDB.goals.completed == 0 and #HonorLogCharDB.goalsLegacy == 3, "TBC goals move to goalsLegacy (active and completed)")
    check(printedMatching("3 TBC goals archived"), "the archive is announced once")
    HL:InitializeDB()
    check(HonorLogCharDB.opponents.Frac.lastSeen == 1794894684, "a saved fractional lastSeen is floored on load")
    check(#HonorLogCharDB.goalsLegacy == 3 and #HonorLogCharDB.goals.items == 1, "the archive does not repeat")
    check(HonorLogDB.settings.visibleCards.EotS == nil and HonorLogDB.settings.visibleCards.DI == true, "card toggles migrated")
    check(HonorLogCharDB.opponents and HonorLogCharDB.honorLog, "new per-character tables created")
    check(#HonorLogCharDB.history == 3 and #HonorLogDB.history == 3, "history kept")
    local old = HL:GetHistory("character", 10)
    check(old[1].bgType == "EotS" and HL:GetBGDisplayName("EotS") == "Eye of the Storm (TBC)", "EotS history displays as Eye of the Storm (TBC)")
    check(HL:FormatHistoryRow(old[1]):find("Eye of the Storm (TBC)", 1, true) and HL:FormatHistoryRow(old[1]):find("Win"), "old entries format without the new fields")
    check(HL:FormatHistoryRow(old[2]):find("Loss"), "old loss entry")
    HL:RecordGame("WSG", true, 500, 200, 3, { result = "win" })
    check(HonorLogCharDB.battlegrounds.WSG.played == 31 and #HonorLogCharDB.history == 4, "recording works on a migrated save")
    HL:InitializeDB()
    check(HonorLogDB.legacy.EotS.played == 8, "migration runs once")

    -- Export: every result kind, Darkspear Islands, objectives, world PvP, opponents and the TBC rows.
    HL:RecordGame("DI", true, 600, 450, 3, { result = "win", joinedInProgress = true, kb = 4, hk = 12, deaths = 2,
        damage = 123456, healing = 7890, objectives = { ["Flag Captures"] = 2, ["Bases Assaulted"] = 1, ["Bases Defended"] = 0 }, rankPoints = 100 })
    HL:RecordGame("AV", false, 900, 120, 1, { result = "loss", kb = 1, hk = 5, deaths = 6, damage = 5000, healing = 0, rankPoints = 25 })
    HL:RecordGame("WSG", false, 700, 200, 2, { result = "draw" })
    HL:RecordGame("AB", false, 120, 10, 0, { result = "left" })
    HL:NoteOpponent("Foe", "MAGE", "kill")
    HL:NoteOpponent("Foe", "MAGE", "death")
    HL:RecordWorldKill("Foe", "MAGE", true)
    HL:RecordWorldHonor(80)
    local text = HL:GenerateTextExport("character")
    local csv = HL:GenerateCSVExport("character")
    local function has(s, plain) return s:find(plain, 1, true) ~= nil end
    check(has(text, "Darkspear Islands | Win") and has(text, "K 4 HK 12 D 2") and has(text, "dmg 123.5K") and has(text, "heal 7.9K"), "text export: DI game with K/HK/D, damage, healing")
    check(has(text, "obj: Bases Assaulted 1; Flag Captures 2") and not has(text, "Bases Defended 0"), "text export: objectives in one compact column, zeros left out")
    check(has(text, "rank +100") and has(text, "joined in progress") and has(text, "honor 450, marks 3"), "text export: rank points, joined in progress, honor, marks")
    check(has(text, "| Loss |") and has(text, "| Draw |") and has(text, "| Left |"), "text export: loss, draw and left results")
    check(has(text, "Eye of the Storm (TBC)") and has(text, "Warsong Gulch (TBC)") and has(text, "Arathi Basin (TBC)"), "text export: old rows are labelled (TBC)")
    check(has(text, "WORLD PVP:") and has(text, "killing blows 1") and has(text, "kills "), "text export: world PvP section")
    check(has(text, "OPPONENTS (this character)") and has(text, "Foe (MAGE) | kills 2, deaths 1"), "text export: opponents section")
    local rows = {}
    for line in csv:gmatch("[^\n]+") do rows[#rows + 1] = line end
    local function row(prefix)
        for _, l in ipairs(rows) do if l:find(prefix, 1, true) then return l end end
    end
    check(has(csv, "Date,Battleground,Result,Joined In Progress,Duration (s),K,HK,D,Damage,Healing,Objectives,Honor,Marks,Rank Points"), "csv export: game header")
    local di = row("Darkspear Islands,Win")
    check(di and di:find(",yes,600,4,12,2,123456,7890,Bases Assaulted 1; Flag Captures 2,450,3,100$"), "csv export: DI row carries every column: " .. tostring(di))
    check(row("Alterac Valley,Loss") and row("Warsong Gulch,Draw") and row("Arathi Basin,Left"), "csv export: loss, draw and left rows")
    check(row("Warsong Gulch,Draw"):find(",no,700,,,,,,,200,2,$"), "csv export: a row without scoreboard data leaves its columns empty")
    check(row("Eye of the Storm (TBC),Win") and row("Warsong Gulch (TBC),Loss") and row("Arathi Basin (TBC),Win"), "csv export: TBC rows keep exporting, labelled (TBC)")
    check(has(csv, "--- World PvP ---") and has(csv, "Kills,Deaths,Killing Blows"), "csv export: world PvP section")
    check(row("Foe,MAGE,2,1,"), "csv export: opponents section (name, class, kills, deaths, last seen)")
    check(has(csv, "Name,Class,Kills,Deaths,Last Seen"), "csv export: opponents header")
    slash("history")
    slash("stats")
    HL:UpdateMainFrame()
    mock.deferTimers = false

    ----------------------------------------------------------------------
    -- Model: the view models the new window reads
    ----------------------------------------------------------------------
    do
        local Util = HL.Util
        local char = HL.db.char -- earlier sections may have swapped the table the outer local points at
        local realTime = time
        local clock = realTime({ year = 2026, month = 11, day = 18, hour = 10, min = 0, sec = 0 })
        time = function(t) if t then return realTime(t) end return clock end -- luacheck: ignore 121
        local function at(day, hour, min) return realTime({ year = 2026, month = 11, day = day, hour = hour, min = min or 0, sec = 0 }) end
        local savedState = {
            history = Util.DeepCopy(char.history), honorLog = Util.DeepCopy(char.honorLog), honorDays = Util.DeepCopy(char.honorDays),
            bgs = Util.DeepCopy(char.battlegrounds), gbgs = Util.DeepCopy(HL.db.global.battlegrounds),
            ghist = Util.DeepCopy(HL.db.global.history), goals = Util.DeepCopy(char.goals), session = Util.DeepCopy(char.session),
            gate = Util.DeepCopy(char.gateDisproved), celebrated = char.rankCelebrated, capWeek = char.rankCapAlertWeek,
            warned = char.honorCapWarned, rank = mock.rank, level = mock.level, reset = mock.weeklyReset,
            window = { cap = mock.rankWindow.cap, week = mock.rankWindow.week, prevCap = mock.rankWindow.prevCap },
            scannedGear = HonorLogDB.scannedGear, scannedVendors = HonorLogDB.scannedVendors, honor = mock.currencies[1792].quantity,
            money = mock.money, bags = mock.bagContents,
        }
        local function kinds(list)
            local out = {}
            for _, a in ipairs(list) do out[#out + 1] = a.kind end
            return table.concat(out, ",")
        end
        local function game(result, bg, ts, extra)
            local g = { bgType = bg or "WSG", result = result, win = result == "win", timestamp = ts, duration = 600, honor = 100, marks = 1,
                rankPoints = 0, rankState = "zero" }
            for k, v in pairs(extra or {}) do g[k] = v end
            return g
        end
        mock.weeklyReset = 3 * 86400

        -- I. One colour table: the hex codes are derived from BG_COLORS.
        for bg, c in pairs(HL.BG_COLORS) do
            check(HL.BG_COLOR_HEX[bg] == string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)),
                "colour: " .. bg .. " hex is derived from BG_COLORS")
        end
        check(HL.BG_COLOR_HEX.AB == "e65959" and HL.BG_COLOR_HEX.WSG == "59d973" and HL.BG_COLOR_HEX.DI == "59d9a6", "colour: AB, WSG and DI hex codes")
        check(HL.BG_COLORS.AV[1] == 0.45 and HL.BG_COLORS.AV[2] == 0.75 and HL.BG_COLORS.AV[3] == 1.0, "colour: Alterac Valley keeps its colour")
        check(math.abs(HL.BG_COLORS.AB[1] - 0xe6 / 255) < 1e-9 and math.abs(HL.BG_COLORS.WSG[2] - 0xd9 / 255) < 1e-9, "colour: AB and WSG floats follow the new hex codes")

        -- A. Today
        check(HL:GetDayKey() == "20261118" and HL:GetDayKey(at(3, 23, 59)) == "20261103", "GetDayKey: local YYYYMMDD, now by default")
        char.history = {}
        char.honorLog = { day = 0, today = 0, weekEnd = 0, week = 0, session = 0 }
        char.honorDays = nil
        mock.level = 60
        setRank(3, 100, 14, 3)
        HL:AddHonorGain(300)
        char.history = {
            game("win", "WSG", at(18, 9, 30), { duration = 600, honor = 200, marks = 3, rankPoints = 100, rankState = "earned" }),
            game("loss", "AV", at(18, 9, 0), { duration = 900, honor = 100, marks = 1, rankPoints = 25, rankState = "earned" }),
            game("win", "AB", at(17, 22, 0), { rankPoints = 100, rankState = "earned" }),
        }
        check(#HL:GetGamesOn("20261118", "character") == 2 and HL:GetGamesOn("20261118", "character")[1].bgType == "WSG", "GetGamesOn: that day's games, newest first")
        check(#HL:GetGamesOn("20261117") == 1 and #HL:GetGamesOn("20260101") == 0, "GetGamesOn: other days")
        local today = HL:GetTodayModel()
        check(today.dayKey == "20261118" and today.played == 2 and today.wins == 1 and today.losses == 1 and today.draws == 0 and today.left == 0, "Today: counts")
        check(today.duration == 1500 and today.honor == 300 and today.honorPerHour == 720 and today.rankPoints == 125, "Today: duration, honor, honor per hour, rank points")
        check(today.marks.WSG == 3 and today.marks.AV == 1 and today.marksTotal == 4 and #today.games == 2 and today.rankBlocked == nil, "Today: marks per battleground, games, nothing blocking")
        clock = at(19, 0, 10) -- midnight passes with the player online: no login, no event
        local rolled = HL:GetTodayModel()
        check(rolled.dayKey == "20261119" and rolled.played == 0 and rolled.honor == 0 and rolled.marksTotal == 0 and #rolled.games == 0, "Today: rolls over at midnight with the player online")
        check(rolled.honorPerHour == nil, "Today: no honor per hour without games")
        check(#HL:GetGamesOn("20261118") == 2, "Today: yesterday's games stay reachable")
        setRank(4, 100, 4, 3)
        check(HL:GetTodayModel().rankBlocked == "cap", "Today: rank points 0 at the weekly cap say cap")
        setRank(3, 100, 14, 3)
        mock.level = 30
        check(HL:GetTodayModel().rankBlocked == "gate", "Today: rank points 0 under the level gate say gate")
        mock.level = 60
        char.history = { game("loss", "WSG", at(19, 0, 5), { rankState = "capped" }) }
        check(HL:GetTodayModel().rankBlocked == "cap", "Today: a game that hit the cap says cap")
        char.history = { game("loss", "WSG", at(19, 0, 5), { rankState = "gated" }) }
        check(HL:GetTodayModel().rankBlocked == "gate", "Today: a gated game says gate")
        clock = at(18, 10, 0)

        -- C. Why a game paid what it did
        local function rp(entry) local text, tone = HL:DescribeRankPoints(entry) return text .. "|" .. tone end
        check(rp({ rankPoints = 100, rankState = "earned" }) == "+100|earned", "DescribeRankPoints: earned")
        check(rp({ rankPoints = 40, rankState = "earned", rankCappedDuring = true }) == "+40, then the weekly cap|earned", "DescribeRankPoints: earned, then the cap")
        check(rp({ rankPoints = 0, rankState = "gated" }) == "0, level 40 needed|blocked", "DescribeRankPoints: gated")
        check(rp({ rankPoints = 0, rankState = "capped" }) == "0, weekly cap reached|blocked", "DescribeRankPoints: capped")
        check(rp({ rankPoints = 0, rankState = "zero" }) == "0, this battleground gave none|blocked", "DescribeRankPoints: zero")
        check(rp({ rankPoints = 0, rankState = "zero", result = "left" }) == "0, you left early|blocked", "DescribeRankPoints: left early")
        check(rp({ rankState = "nodata" }) == "not measured|unknown", "DescribeRankPoints: no data")
        check(rp({ rankPoints = 100 }) == "+100|earned", "DescribeRankPoints: an old row that gave points is earned")
        check(rp({ rankPoints = 0 }) == "0, reason not recorded|unknown" and rp({}) == "not measured|unknown" and rp(nil) == "not measured|unknown", "DescribeRankPoints: old rows without points or state")
        check(HL:DescribeHonor({ honor = 450 }) == "+450 honor" and HL:DescribeHonor({ honor = 450, honorCapped = true }) == "+450 honor, played at the honor cap"
            and HL:DescribeHonor({}) == "+0 honor", "DescribeHonor: plain and at the cap")

        -- B. Advice
        mock.level, mock.money = 30, 1e9
        setRank(3, 100, 14, 3) -- rank 3 at level 30: the level gate holds rank 4
        mock.currencies[1792].quantity = 24000
        char.goals.items, char.goals.completed = {}, {}
        char.history = { game("loss", "WSG", at(18, 9, 0)), game("loss", "WSG", at(18, 8, 0)), game("loss", "WSG", at(18, 7, 0)), game("win", "AV", at(18, 6, 0), { rankPoints = 100, rankState = "earned" }) }
        char.battlegrounds.WSG = { played = 5, wins = 2, losses = 3, draws = 0, left = 0, totalDuration = 3000, honorLifetime = 1000, marksLifetime = 5, cappedPlayed = 0, cappedHonor = 0 }
        char.battlegrounds.AV = { played = 4, wins = 3, losses = 1, draws = 0, left = 0, totalDuration = 3600, honorLifetime = 2000, marksLifetime = 8, cappedPlayed = 0, cappedHonor = 0 }
        char.battlegrounds.AB, char.battlegrounds.DI = HL.NewBGStats(), HL.NewBGStats()
        char.gateDisproved = {}
        local advice = HL:GetAdvice(10)
        check(kinds(advice) == "gate,cap,zero,bestbg,unlock", "Advice: every kind in priority order: " .. kinds(advice))
        check(#HL:GetAdvice() == 4 and #HL:GetAdvice(1) == 1 and HL:GetAdvice(1)[1].kind == "gate", "Advice: four by default, the limit cuts from the end")
        for _, a in ipairs(advice) do check(type(a.head) == "string" and a.head ~= "" and type(a.body) == "string" and a.body ~= "", "Advice: " .. a.kind .. " has a head and a body") end
        check(advice[1].head:find("level 40") and advice[1].body == Rank:GateText(Rank:GetInfo().gate), "Advice: the gate names the level")
        local buyable = HL:GetBuyableNow(3)
        check((advice[2].itemID == (buyable[1] and buyable[1].itemID)) and advice[2].head:find("24,000 of 25,000"), "Advice: the cap names what can be bought now")
        check(advice[3].bgType == "WSG" and advice[3].head:find("Warsong Gulch") and advice[3].body:find("0 rank points in 3 of 3"), "Advice: zero names the battleground")
        check(advice[4].bgType == "AV" and advice[4].body:find("500") and advice[4].body:find("200") and advice[4].body:find("Warsong Gulch"), "Advice: the best battleground by honor per game")
        check(advice[5].itemID == HL:GetRankUnlocks(4)[1] and advice[5].head:find("Rank 4 unlocks"), "Advice: the next rank's first unlock")
        -- Kinds that do not apply are absent.
        mock.level = 60
        mock.currencies[1792].quantity = 8200
        char.battlegrounds.WSG.played = 2
        char.history = { game("win", "WSG", at(18, 9, 0), { rankPoints = 100, rankState = "earned" }) }
        check(kinds(HL:GetAdvice(10)) == "unlock", "Advice: only the unlock when nothing else applies: " .. kinds(HL:GetAdvice(10)))
        char.history = {}
        check(kinds(HL:GetAdvice(10)) == "unlock,nogames", "Advice: no games recorded adds nogames last")
        setRank(14, 0, 14, 10)
        check(kinds(HL:GetAdvice(10)) == "nogames", "Advice: no unlock at the top rank")

        -- D. Season and ranks
        check(Rank:PointsForRank(1) == 750 and Rank:PointsForRank(14) == 3000 and Rank:PointsForRank(15) == nil and Rank:PointsForRank(0) == nil, "PointsForRank: the curve entry")
        setRank(3, 120, 5, 2, 3)
        local info = Rank:GetInfo()
        local schedule = Rank:GetSeasonSchedule(info)
        check(#schedule == 10, "Schedule: one row per week the cap table covers")
        local currentRows = 0
        for i, row in ipairs(schedule) do
            check(row.week == i and row.capRank == Rank:CapRankForWeek(i, info) and row.capTotal == Rank:TotalForRank(row.capRank), "Schedule: week " .. i .. " cap")
            if i > 1 then check(row.start - schedule[i - 1].start == 7 * 86400, "Schedule: week " .. i .. " starts seven days after the last") end
            if row.current then currentRows = currentRows + 1 end
            check(row.past == (i < 2) and row.current == (i == 2), "Schedule: week " .. i .. " past and current flags")
        end
        check(currentRows == 1 and schedule[2].start == clock + 3 * 86400 - 7 * 86400 and schedule[2].capRank == 5, "Schedule: the current week starts one week before the reset")
        mock.weeklyReset = 0
        check(Rank:GetSeasonSchedule(Rank:GetInfo())[1].start == nil, "Schedule: no reset clock, no start times")
        mock.weeklyReset = 3 * 86400
        mock.rankWindow.noData = true
        check(#Rank:GetSeasonSchedule() == 0 and #Rank:GetRankTable() == 0, "Schedule and rank table: empty without rank data")
        mock.rankWindow.noData = false
        setRank(8, 100, 9, 4)
        info = Rank:GetInfo()
        local rows = Rank:GetRankTable(info, Rank:GetPace())
        check(#rows == 14, "RankTable: fourteen rows")
        for n, row in ipairs(rows) do
            check(row.rank == n and row.total == Rank:TotalForRank(n) and row.points == CURVE[n] and row.title == Rank:TitleForRank(n), "RankTable: rank " .. n .. " title and points")
            local state = n < 8 and "reached" or (n == 8 and "current" or "ahead")
            check(row.state == state and (state == "ahead") == (row.plan ~= nil), "RankTable: rank " .. n .. " state " .. state)
            check(row.when == (row.plan and Rank.PlanWhen(row.plan) or state), "RankTable: rank " .. n .. " when")
        end
        check(rows[9].plan.target == 9 and rows[2].plan == nil, "RankTable: a plan for ranks ahead only")
        check(#rows[2].items == 1 and rows[2].items[1] == 274445, "RankTable: rank 2 unlocks the Alliance insignia")
        check(#rows[8].items == 2 and rows[8].items[1] == 275244 and rows[8].items[2] == 275240, "RankTable: rank 8 unlocks the two Seals, by name")
        local want14 = 0
        for _, data in pairs(HL.GearDB) do
            if data.source == "RANK" and data.rank == 14 and data.faction ~= "Horde" then want14 = want14 + 1 end
        end
        check(want14 > 10 and #rows[14].items == want14, "RankTable: rank 14 lists the Alliance weapons only")
        local sorted14 = true
        for i = 2, #rows[14].items do
            local a, b = HL.GearDB[rows[14].items[i - 1]], HL.GearDB[rows[14].items[i]]
            if a.quality < b.quality or (a.quality == b.quality and a.name > b.name) then sorted14 = false end
        end
        check(sorted14 and #HL:GetRankUnlocks(99) == 0 and #HL:GetRankUnlocks(nil) == 0, "GetRankUnlocks: best quality first, then name; none for an unknown rank")
        mock.faction = "Horde"
        check(HL:GetRankUnlocks(2)[1] == 274444, "GetRankUnlocks: the Horde sees its own insignia")
        mock.faction = "Alliance"

        -- E. Goal texts
        local gp = { isComplete = false, missing = { { kind = "honor", remaining = 800 }, { kind = "marks", remaining = 10, bg = "AV" } },
            rows = { { kind = "honor", current = 500, needed = 1000 }, { kind = "marks", bg = "AV", current = 10, needed = 20 }, { kind = "level", met = true, current = 60, needed = 55 } } }
        check(HL:GetGoalPercent(gp) < 99 and HL:GetGoalPercent({ isComplete = true, rows = {} }) == 100, "GetGoalPercent: weighted share, 100 when complete")
        check(HL:GoalMissingText(gp) == "800 honor, 10 AV marks", "GoalMissingText: plain words")
        check(HL:GoalRowText(gp.rows[1], 1):find("500/1,000 Honor", 1, true) and HL:GoalRowText(gp.rows[1], 0):find("0/1,000 Honor", 1, true), "GoalRowText: honor, scaled by the factor")
        check(HL:GoalRowText(gp.rows[2], 1):find(HL.BG_COLOR_HEX.AV, 1, true), "GoalRowText: marks use the battleground colour")
        local line = HL:GoalCurrencyLine(gp, 1)
        check(line:find("Honor") and not line:find("Level"), "GoalCurrencyLine: a met level row is left out")
        check(HL:GoalReadyText({ isComplete = true }):find("Ready to purchase", 1, true), "GoalReadyText: complete")
        check(HL:GoalReadyText({ isComplete = false, missing = {}, readyLimitedBy = "nopace" }):find("play a game for a date", 1, true), "GoalReadyText: no pace")
        check(HL:GoalPartText({ role = "seal", owned = true }):find("Seal") and HL:GoalPartText({ role = "blue", owned = false, honor = 9000, marks = { AV = 15 } }):find("9,000 honor, 15 AV", 1, true), "GoalPartText: owned and still to buy")

        -- F. Vendors and sets
        local BLUE, EPIC = 272738, 272787
        check(HL:GetVendorKind(BLUE) == "armor" and HL:GetVendorKind(274445) == "accessories" and HL:GetVendorKind(1) == nil, "GetVendorKind: armor, accessories, unknown")
        local supplyID
        for id, data in pairs(HL.GearDB) do if data.source == "REP" and data.rep and data.rep.faction == 890 and not supplyID then supplyID = id end end
        local sk, srep = HL:GetVendorKind(supplyID)
        check(sk == "supply" and srep == 890, "GetVendorKind: a supply item names its reputation faction")
        HonorLogDB.scannedGear, HonorLogDB.scannedVendors = {}, {}
        local vendors = HL:GetVendorList()
        check(#vendors == 7, "GetVendorList: the Alliance's seven built-in vendors: " .. #vendors)
        local armorVendor
        for _, v in ipairs(vendors) do
            check(v.key == v.name and v.kind and v.role and v.place and type(v.count) == "number", "GetVendorList: " .. v.name .. " row")
            if v.kind == "armor" then armorVendor = v end
        end
        check(armorVendor.known == true and armorVendor.x == 74.4 and armorVendor.count > 5 and armorVendor.npc == 12777, "GetVendorList: the armor vendor, with a position")
        mock.faction = "Horde"
        local hordeArmor
        for _, v in ipairs(HL:GetVendorList()) do if v.kind == "armor" then hordeArmor = v end end
        check(hordeArmor.known == false and hordeArmor.name == "Lady Palanseer", "GetVendorList: a Horde vendor without a position is not known")
        mock.faction = "Alliance"
        HonorLogDB.scannedVendors["Test Quartermaster"] = { map = 1453, x = 10, y = 20, zone = "Stormwind City", subzone = "Trade District", npc = 999 }
        HonorLogDB.scannedGear[BLUE] = { honor = 9000, marks = { AV = 15 }, gold = 0, seen = 1, npc = "Test Quartermaster" }
        local withScan = HL:GetVendorList()
        local scanned = withScan[#withScan]
        check(#withScan == 8 and scanned.name == "Test Quartermaster" and scanned.kind == "armor" and scanned.known and scanned.place == "Trade District, Stormwind City" and scanned.npc == 999, "GetVendorList: a scanned vendor the table lacks is added")
        HonorLogDB.scannedGear, HonorLogDB.scannedVendors = {}, {}

        local stock = HL:GetVendorStock(armorVendor)
        local blueRow
        for _, r in ipairs(stock) do
            check(r.data.source ~= "UPGRADE" and (not r.data.class or r.data.class == "WARRIOR") and (not r.data.faction or r.data.faction == "Alliance"), "GetVendorStock: " .. r.itemID .. " is for a warrior of the Alliance, not an upgrade row")
            check(r.name and r.data.itemID == r.itemID and r.slot == r.data.slot and r.set == r.data.set, "GetVendorStock: row " .. r.itemID .. " fields")
            check(HL:GetVendorKind(r.itemID) == "armor", "GetVendorStock: " .. r.itemID .. " is armor-vendor stock")
            if r.itemID == BLUE then blueRow = r end
        end
        check(blueRow and blueRow.set == 282 and blueRow.isGoal == false and not blueRow.owned, "GetVendorStock: the blue plate helm, not a goal, not owned")
        check(blueRow.upgrade and blueRow.upgrade.itemID == EPIC and blueRow.upgrade.sealID == HL.GearDB[EPIC].parts[2] and blueRow.upgrade.rank == HL.GearDB[EPIC].rank
            and blueRow.upgrade.honor == HL.GearDB[blueRow.upgrade.sealID].honor, "GetVendorStock: the blue piece carries its upgrade")
        local epicListed = false
        for _, r in ipairs(stock) do if r.itemID == EPIC then epicListed = true end end
        check(not epicListed, "GetVendorStock: the epic's own row is not listed")
        local inPicker = false
        for _, entry in ipairs(HL:GetPickerItems({ class = "WARRIOR", slot = "HEAD" })) do if entry.itemID == BLUE then inPicker = true end end
        check(inPicker, "GetVendorStock: the picker lists the helm while it is no goal")
        check(HL:AddGoal(BLUE), "GetVendorStock: a goal is added")
        local goalRow
        for _, r in ipairs(HL:GetVendorStock(armorVendor)) do if r.itemID == BLUE then goalRow = r end end
        inPicker = false
        for _, entry in ipairs(HL:GetPickerItems({ class = "WARRIOR", slot = "HEAD" })) do if entry.itemID == BLUE then inPicker = true end end
        check(goalRow and goalRow.isGoal == true and not inPicker, "GetVendorStock: an item that is already a goal is still listed, flagged")
        HL:RemoveGoal(BLUE)
        mock.bagContents = { BLUE }
        for _, r in ipairs(HL:GetVendorStock(armorVendor)) do if r.itemID == BLUE then check(r.owned == true, "GetVendorStock: an owned item is flagged") end end
        mock.bagContents = {}
        -- order: set, then slot order, then name; rows with no set last
        local lastSet, lastSlot = -1, 0
        local slotIndex = {}
        for i, s in ipairs(HL.SLOTS) do slotIndex[s] = i end
        for i, r in ipairs(stock) do
            local setKey = r.set or math.huge
            check(setKey >= lastSet, "GetVendorStock: sorted by set (row " .. i .. ")")
            if setKey ~= lastSet then lastSlot = 0 end
            check(slotIndex[r.slot] >= lastSlot, "GetVendorStock: slot order inside a set (row " .. i .. ")")
            lastSet, lastSlot = setKey, slotIndex[r.slot]
        end
        -- filters
        local function allMatch(list, fn) for _, r in ipairs(list) do if not fn(r) then return false end end return #list > 0 end
        check(allMatch(HL:GetVendorStock(armorVendor, { set = 282 }), function(r) return r.set == 282 end), "GetVendorStock: set filter")
        check(allMatch(HL:GetVendorStock(armorVendor, { slot = "HEAD" }), function(r) return r.slot == "HEAD" end), "GetVendorStock: slot filter")
        local allClasses, mageSeen = HL:GetVendorStock(armorVendor, { class = "ALL" }), false
        for _, r in ipairs(allClasses) do if r.data.class == "MAGE" then mageSeen = true end end
        check(mageSeen and #allClasses > #stock, "GetVendorStock: class ALL lists every class")
        check(allMatch(HL:GetVendorStock(armorVendor, { class = "MAGE" }), function(r) return not r.data.class or r.data.class == "MAGE" end), "GetVendorStock: another class")
        check(#HL:GetVendorStock(nil) == 0 and #HL:GetVendorStock({}) == 0, "GetVendorStock: no vendor, no rows")
        -- supply officers: their own reputation faction only
        local supplyVendor
        for _, v in ipairs(vendors) do if v.kind == "supply" and v.repFaction == 890 then supplyVendor = v end end
        check(allMatch(HL:GetVendorStock(supplyVendor, { class = "ALL" }), function(r) local k, f = HL:GetVendorKind(r.itemID) return k == "supply" and f == 890 end), "GetVendorStock: a supply officer lists its own faction's items")
        -- rows without a set
        local accessories
        for _, v in ipairs(vendors) do if v.kind == "accessories" then accessories = v end end
        local accStock = HL:GetVendorStock(accessories)
        check(#accStock > 0 and allMatch(accStock, function(r) return r.set == nil end) and #HL:GetVendorSets(accessories) == 0, "Vendor stock without sets: listed, and no sets reported")
        local savedSet = HL.GearDB[BLUE].set
        HL.GearDB[BLUE].set = nil
        local noSet = HL:GetVendorStock(armorVendor)
        local noSetRow
        for i, r in ipairs(noSet) do if r.itemID == BLUE then noSetRow = i end end
        local firstBare = #noSet + 1
        for i, r in ipairs(noSet) do if r.set == nil then firstBare = math.min(firstBare, i) end end
        check(noSetRow and noSetRow >= firstBare and noSet[noSetRow].set == nil and #noSet == #stock, "Vendor stock: a row with no set is listed")
        for i = firstBare, #noSet do check(noSet[i].set == nil, "Vendor stock: rows with no set come after every set (row " .. i .. ")") end
        HL.GearDB[BLUE].set = savedSet
        local sets = HL:GetVendorSets(armorVendor)
        local setTotal, has282 = 0, false
        for i, s in ipairs(sets) do
            setTotal = setTotal + s.count
            if s.id == 282 then has282 = s.name == HL.GearSets[282] end
            if i > 1 then check(sets[i - 1].name <= s.name, "GetVendorSets: sorted by name") end
        end
        local withSet = 0
        for _, r in ipairs(stock) do if r.set then withSet = withSet + 1 end end
        check(has282 and setTotal == withSet and #HL:GetVendorSets(armorVendor, "ALL") >= #sets, "GetVendorSets: counts add up to the stock's set rows")
        check(next(HL.GearSets) and HL.GearSets[282] and type(HL.GearDB[BLUE].set) == "number", "Gear database: set ids and names")

        -- G. Battlegrounds and honor by day
        local order = { "win", "loss", "draw", "left", "win", "win", "loss", "win", "loss", "loss", "win", "draw" } -- newest first
        local wsgHistory = {}
        for i, result in ipairs(order) do
            wsgHistory[i] = game(result, "WSG", at(18, 9, 0) - i * 3600, { rankPoints = result == "win" and 100 or 25, rankState = "earned" })
        end
        char.history = wsgHistory
        char.battlegrounds.WSG = { played = 6, wins = 3, losses = 2, draws = 1, left = 0, totalDuration = 3600, honorLifetime = 1200, marksLifetime = 5, cappedPlayed = 1, cappedHonor = 300 }
        HL.db.global.battlegrounds.WSG = { played = 10, wins = 9, losses = 1, draws = 0, left = 0, totalDuration = 1000, honorLifetime = 5000, marksLifetime = 5, cappedPlayed = 0, cappedHonor = 0 }
        mock.bagItems[20558] = 12
        local m = HL:GetBattlegroundModel("WSG", "character")
        check(m.bgType == "WSG" and m.name == "Warsong Gulch" and m.played == 6 and m.wins == 3 and m.losses == 2 and m.draws == 1 and m.left == 0, "BattlegroundModel: counters")
        check(math.abs(m.winRate - 60) < 1e-9 and m.honorPerGame == 180 and m.avgDuration == 600 and m.marksHeld == 12, "BattlegroundModel: win rate, honor per game (cap games left out), duration, marks held")
        check(table.concat(m.sequence) == "LLWLWWXDLW" and #m.sequence == 10, "BattlegroundModel: the last ten results, oldest first: " .. table.concat(m.sequence))
        check(m.pointsPerWin == 100 and m.pointsPerLoss == 25, "BattlegroundModel: measured points per win and loss")
        check(HL:GetBattlegroundModel("WSG", "account").played == 10 and HL:GetBattlegroundModel("WSG", "account").honorPerGame == 500, "BattlegroundModel: the account scope")
        local empty = HL:GetBattlegroundModel("DI", "character")
        check(empty.played == 0 and empty.winRate == nil and empty.honorPerGame == nil and empty.avgDuration == nil and #empty.sequence == 0
            and empty.pointsPerWin == nil and empty.pointsPerLoss == nil, "BattlegroundModel: nothing played is nil, not 0 or 250")
        check(HL:GetBattlegroundModel(nil) == nil and HL.db.char.battlegrounds.NEVER == nil and HL:GetBattlegroundModel("NEVER").played == 0 and HL.db.char.battlegrounds.NEVER == nil, "BattlegroundModel: reading creates no stats")
        check(HL:GetAverageHonorPerBG("DI") == 250, "BattlegroundModel: the 250 fallback stays for the old callers")
        char.history = { game("loss", "WSG", at(18, 9, 0)), game("left", "WSG", at(18, 8, 0)) }
        check(table.concat(HL:GetBattlegroundModel("WSG", "character").sequence) == "XL", "BattlegroundModel: a game left early is X")
        char.battlegrounds.WSG = { played = 2, wins = 0, losses = 0, draws = 0, left = 2, totalDuration = 100, honorLifetime = 50, marksLifetime = 0, cappedPlayed = 0, cappedHonor = 0 }
        check(HL:GetBattlegroundModel("WSG", "character").winRate == nil, "BattlegroundModel: no decided game, no win rate")

        -- honor by day: created once, back-filled from the saved games, pruned at 60 days
        char.honorDays = nil
        char.honorLog = { day = 20261118, today = 500, weekEnd = clock + 86400, week = 500, session = 0 }
        char.history = {
            game("win", "WSG", at(18, 9, 0), { honor = 200 }), game("win", "WSG", at(17, 20, 0), { honor = 100 }),
            game("loss", "AV", at(17, 9, 0), { honor = 50 }), game("win", "AB", at(15, 9, 0), { honor = 90 }),
        }
        local byDay = HL:GetHonorByDay()
        check(#byDay == 7 and byDay[1].dayKey == "20261112" and byDay[7].dayKey == "20261118" and byDay[7].label == "Today", "HonorByDay: seven days, oldest first, today last")
        check(byDay[1].label == date("%a", at(12, 12)) and byDay[6].label == date("%a", at(17, 12)), "HonorByDay: short weekday names")
        check(byDay[7].honor == 500 and byDay[6].honor == 150 and byDay[4].honor == 90 and byDay[1].honor == 0, "HonorByDay: back-filled from the saved games, today from the honor log")
        char.history = {}
        check(HL:GetHonorByDay()[6].honor == 150, "HonorByDay: the back-fill runs once")
        check(#HL:GetHonorByDay(3) == 3 and HL:GetHonorByDay(3)[1].dayKey == "20261116", "HonorByDay: the day count")
        char.honorDays["20260101"], char.honorDays["20260919"], char.honorDays["20260918"] = 5, 7, 9
        HL:AddHonorGain(100)
        check(char.honorDays["20261118"] == 600 and HL:GetHonorSummary().today == 600, "HonorByDay: a gain lands in today's store and today's total")
        check(char.honorDays["20260101"] == nil and char.honorDays["20260918"] == nil and char.honorDays["20260919"] == 7, "HonorByDay: pruned past 60 days")
        clock = at(19, 0, 5)
        local after = HL:GetHonorByDay(2)
        check(after[1].honor == 600 and after[2].label == "Today" and after[2].honor == 0 and HL:GetHonorSummary().today == 0, "HonorByDay: rolls over at midnight with the player online")
        HL:AddHonorGain(40)
        check(HL:GetHonorByDay(2)[2].honor == 40 and HL:GetHonorByDay(2)[1].honor == 600, "HonorByDay: the new day starts on its own")
        clock = at(18, 10, 0)

        -- hour buckets
        char.history = {
            game("win", "WSG", at(18, 2, 0)), game("loss", "WSG", at(18, 4, 59)), game("draw", "WSG", at(18, 3, 0)),
            game("win", "WSG", at(18, 5, 0)), game("win", "WSG", at(17, 11, 59)),
            game("loss", "WSG", at(16, 12, 0)), game("loss", "AV", at(16, 17, 59)),
            game("left", "WSG", at(15, 18, 0)), game("draw", "WSG", at(15, 23, 59)),
        }
        local buckets = HL:GetWinRateByHour("character")
        check(#buckets == 4 and buckets[1].key == "night" and buckets[2].key == "morning" and buckets[3].key == "afternoon" and buckets[4].key == "evening", "WinRateByHour: four buckets in order")
        check(buckets[1].played == 2 and buckets[1].wins == 1 and buckets[1].winRate == 50, "WinRateByHour: night 0-5 (a draw is not counted)")
        check(buckets[2].played == 2 and buckets[2].winRate == 100, "WinRateByHour: morning 5-12 starts at 5:00")
        check(buckets[3].played == 2 and buckets[3].winRate == 0, "WinRateByHour: afternoon 12-18")
        check(buckets[4].played == 0 and buckets[4].winRate == nil and buckets[4].label == "Evening", "WinRateByHour: evening has no decided game, so no rate")

        -- H. Events with data
        local seen = {}
        local listener, other = {}, {}
        local function listen(event)
            seen[event] = {}
            HL.RegisterCallback(listener, event, function(name, ...) seen[event][#seen[event] + 1] = { name = name, n = select("#", ...), ... } end)
        end
        for _, event in ipairs({ "HonorLog_GameRecorded", "HonorLog_RankUp", "HonorLog_WeekCapReached", "HonorLog_HonorCapNear", "HonorLog_GoalAcquired" }) do listen(event) end
        check(HL.callbacks and type(HL.RegisterCallback) == "function" and type(HL.UnregisterCallback) == "function", "events: a callback registry on HonorLog")
        local erroring = 0
        HL.RegisterCallback(other, "HonorLog_GameRecorded", function() erroring = erroring + 1 error("listener failed") end)
        local before = #char.history
        HL:RecordGame("WSG", true, 100, 10, 1, { result = "win" })
        check(#char.history == before + 1, "events: a listener that errors does not break RecordGame")
        check(#seen.HonorLog_GameRecorded == 1 and seen.HonorLog_GameRecorded[1].name == "HonorLog_GameRecorded" and seen.HonorLog_GameRecorded[1][1] == char.history[1], "events: HonorLog_GameRecorded fires once with the saved entry")
        check(erroring == 1 and #mock.secureErrors >= 1 and #mock.handledErrors == 0, "events: the erroring listener ran, its error stayed out of the caller")
        HL.UnregisterCallback(other, "HonorLog_GameRecorded")
        local realFire = HL.callbacks.Fire
        HL.callbacks.Fire = function() error("registry failed") end
        check(pcall(HL.Fire, HL, "HonorLog_GameRecorded", {}), "events: Fire never raises")
        HL.callbacks.Fire = realFire
        -- rank up: once per rank
        char.rankCelebrated = 0
        setRank(4, 40, 14, 3)
        Rank:OnRenownChanged(2800, 4, 3)
        Rank:OnRenownChanged(2800, 4, 3)
        local ru = seen.HonorLog_RankUp
        check(#ru == 1 and ru[1][1] == 4 and type(ru[1][2]) == "table" and ru[1][2].rank == 4, "events: HonorLog_RankUp fires once with the new rank and the rank info")
        Rank:OnRenownChanged(2800, 5, 4)
        check(#ru == 2 and ru[2][1] == 5, "events: the next rank fires again")
        -- weekly cap
        setRank(5, 100, 5, 3)
        char.rankCapAlertWeek = 0
        Rank:CheckCapAlert(Rank:GetInfo())
        Rank:CheckCapAlert(Rank:GetInfo())
        local wc = seen.HonorLog_WeekCapReached
        check(#wc == 1 and type(wc[1][1]) == "table" and wc[1][1].capped and wc[1][1].weekCapRank == 5, "events: HonorLog_WeekCapReached fires once with the info")
        -- honor cap
        mock.currencies[1792].quantity = 24000
        char.honorCapWarned = false
        HL:CheckHonorCap()
        HL:CheckHonorCap()
        local hc = seen.HonorLog_HonorCapNear
        check(#hc == 1 and hc[1][1] == 24000 and hc[1][2] == 25000, "events: HonorLog_HonorCapNear fires once with the amount and the cap")
        mock.currencies[1792].quantity = 8200
        -- goal acquired
        check(HL:AddGoal(BLUE), "events: a goal to acquire")
        mock.bagContents = { BLUE }
        HL:ScanGoalsForAcquiredItems()
        HL:ScanGoalsForAcquiredItems()
        local ga = seen.HonorLog_GoalAcquired
        check(#ga == 1 and ga[1][1] == BLUE, "events: HonorLog_GoalAcquired fires once with the item")
        mock.bagContents = {}
        HL.UnregisterCallback(listener, "HonorLog_GameRecorded")
        HL:RecordGame("WSG", true, 100, 10, 1, { result = "win" })
        check(#seen.HonorLog_GameRecorded == 1, "events: UnregisterCallback stops the calls")

        -- put everything back
        time = realTime -- luacheck: ignore 121
        char.history, char.honorLog, char.honorDays = savedState.history, savedState.honorLog, savedState.honorDays
        char.battlegrounds, HL.db.global.battlegrounds, HL.db.global.history = savedState.bgs, savedState.gbgs, savedState.ghist
        char.goals, char.session, char.gateDisproved = savedState.goals, savedState.session, savedState.gate
        char.rankCelebrated, char.rankCapAlertWeek, char.honorCapWarned = savedState.celebrated, savedState.capWeek, savedState.warned
        mock.rank, mock.level, mock.weeklyReset = savedState.rank, savedState.level, savedState.reset
        mock.rankWindow.cap, mock.rankWindow.week, mock.rankWindow.prevCap = savedState.window.cap, savedState.window.week, savedState.window.prevCap
        HonorLogDB.scannedGear, HonorLogDB.scannedVendors = savedState.scannedGear, savedState.scannedVendors
        mock.currencies[1792].quantity, mock.money, mock.bagContents = savedState.honor, savedState.money, savedState.bags
    end

    -- ═══ The full window: Kit, Window, Overview ══════════════════════════════════════
    do
        local Kit = HL.Kit
        check(Kit and HL.Window, "Kit and Window are loaded")
        check(_G.HonorLogWindow == nil and HL.Window.frame == nil, "window: no frame exists before first use")
        local function liveTickers()
            local n = 0
            for _, t in ipairs(mock.tickers) do if not t.cancelled then n = n + 1 end end
            return n
        end
        local tickersAtStart = liveTickers()

        local function setMode(present)
            mock.atlasMode = present and "all" or "none"
            mock.missingTemplates = present and {} or { ["*"] = true }
            if present then mock.restoreFonts() else mock.removeFonts() end
        end

        -- Blizzard globals the kit uses when present; the test supplies recording stand-ins.
        local selectCalls, deselectCalls, pctCalls = {}, {}, {}
        local function addBlizzardGlobals()
            _G.PanelTemplates_SelectTab = function(b) selectCalls[#selectCalls + 1] = b end
            _G.PanelTemplates_DeselectTab = function(b) deselectCalls[#deselectCalls + 1] = b end
            _G.PanelTemplates_TabResize = function() end
            _G.CooldownFrame_SetDisplayAsPercentage = function(cd, pct) pctCalls[#pctCalls + 1] = { cd, pct } end
        end
        local function removeBlizzardGlobals()
            _G.PanelTemplates_SelectTab, _G.PanelTemplates_DeselectTab, _G.PanelTemplates_TabResize = nil, nil, nil
            _G.CooldownFrame_SetDisplayAsPercentage = nil
        end

        -- An item whose vendor is known with a position on the map.
        local vendorItem
        for id in pairs(HL.GearDB) do
            local v = HL:GetVendorFor(id)
            if v and v.map and v.x and v.y then vendorItem = id break end
        end
        check(vendorItem, "kit tests have an item with a vendor that has coordinates")

        local function kitSuite(present)
            local label = present and "kit (all present): " or "kit (all missing): "
            setMode(present)
            addBlizzardGlobals()
            local parent = CreateFrame("Frame", nil, UIParent)

            -- templates and atlases
            local f, template = Kit:CreateTemplated("Frame", nil, parent, "InsetFrameTemplate")
            check(f and template == (present and "InsetFrameTemplate" or nil), label .. "CreateTemplated reports the template that took")
            local f2, t2 = Kit:CreateTemplated("Frame", nil, parent, "NoSuchTemplate", "AnotherOne")
            check(f2 and (present and t2 == "NoSuchTemplate" or t2 == nil), label .. "CreateTemplated tries each template in order")
            check(Kit:HasAtlas("UI-Character-Info-Honor-Bar") == present, label .. "HasAtlas follows the client")
            local tex = parent:CreateTexture()
            check(Kit:SetAtlasOr(tex, "UI-Character-Info-Honor-Bar", 0.1, 0.2, 0.3, 0.4) == present, label .. "SetAtlasOr reports which one took")
            if present then
                check(tex.__atlas == "UI-Character-Info-Honor-Bar", label .. "the atlas is set")
            else
                check(tex.__color and tex.__color[1] == 0.1 and tex.__color[4] == 0.4, label .. "a plain colour replaces the atlas")
            end

            -- text styles and fonts
            for _, style in ipairs({ "label", "labelSmall", "value", "grey", "title", "big" }) do
                local fs = Kit:Text(parent, style)
                check(fs.honorLogStyle == style, label .. "text style " .. style)
                check((fs.honorLogFont ~= false) == present, label .. "font object for " .. style .. " is " .. (present and "found" or "absent"))
            end
            if present then
                check(Kit:Text(parent, "big").honorLogFont == "GameFontHighlightHuge", "big text uses GameFontHighlightHuge first")
                _G.GameFontHighlightHuge = nil
                check(Kit:Text(parent, "big").honorLogFont == "GameFontNormalHuge", "big text falls back to GameFontNormalHuge")
                _G.GameFontNormalHuge = nil
                check(Kit:Text(parent, "big").honorLogFont == "GameFontHighlightLarge", "…then GameFontHighlightLarge")
                mock.restoreFonts()
            end

            -- the window frame
            local w = Kit:Window("HonorLogKitWindow" .. (present and "A" or "B"), 900, 540)
            check(w.honorLogChrome == (present and "PortraitFrameTemplate" or false), label .. "window chrome")
            w:SetTitleText("Title")
            check(w:GetTitleText() == "Title", label .. "SetTitleText")
            if present then check(w.__title == "Title", label .. "the template's SetTitle is used") end
            w:SetPortraitTexture(4242)
            check(w.honorLogPortrait == 4242, label .. "SetPortraitTexture")
            if present then check(w.__portrait == 4242, label .. "the template's SetPortraitToAsset is used") end
            check(type(w.Content) == "table" and type(w.CloseButton) == "table", label .. "window has Content and CloseButton")
            local topLeft, bottomRight
            for _, pt in ipairs(w.Content.__points) do
                if pt[1] == "TOPLEFT" then topLeft = pt elseif pt[1] == "BOTTOMRIGHT" then bottomRight = pt end
            end
            check(topLeft and topLeft[4] == 6 and topLeft[5] == -24 and bottomRight and bottomRight[4] == -6 and bottomRight[5] == 6,
                label .. "Content is inset 6 left, right and bottom and 24 from the top")
            w:Show()
            local click = w.CloseButton.__scripts.OnClick
            check(present or click, label .. "the close button closes the window on the plain path")
            if click then click(w.CloseButton) end
            if not present then check(not w:IsShown(), label .. "the close button hides the window") end
            local started, moved = 0, nil
            rawset(w, "StartMoving", function() started = started + 1 end)
            w.honorLogOnMoved = function() moved = true end
            w.honorLogDrag.__scripts.OnDragStart(w.honorLogDrag)
            w.honorLogDrag.__scripts.OnDragStop(w.honorLogDrag)
            check(started == 1 and moved, label .. "the title area drags the window and reports the move")

            -- inset, header, buttons
            local inset = Kit:Inset(parent)
            check(inset.honorLogTemplate == (present and "InsetFrameTemplate" or false), label .. "inset template")
            if not present then check(#inset.honorLogEdges == 4, label .. "plain inset draws a 1-pixel edge") end
            local header = Kit:Header(parent, "Section")
            check(header.Label:GetText() == "Section", label .. "header text")
            local red, small = Kit:Button(parent, "Go", "red"), Kit:Button(parent, "Small", "small")
            check(red:GetText() == "Go" and small:GetText() == "Small", label .. "button texts")
            check(red.honorLogTemplate == (present and "UIPanelButtonTemplate" or false), label .. "red button template")
            check(small.honorLogTemplate == (present and "SharedButtonSmallTemplate" or false), label .. "small button template")
            if present then
                mock.missingTemplates = { SharedButtonSmallTemplate = true }
                check(Kit:Button(parent, "S2", "small").honorLogTemplate == "UIPanelButtonTemplate", label .. "small button falls back to UIPanelButtonTemplate")
                mock.missingTemplates = {}
            end

            -- tabs
            local picked = {}
            local tabs = Kit:Tabs(w, function(key) picked[#picked + 1] = key end)
            local ta, tb = tabs:Add("a", "Alpha"), tabs:Add("b", "Bravo")
            check(ta.honorLogTemplate == (present and "PanelTabButtonTemplate" or false), label .. "tab template")
            check(tabs:GetSelected() == nil, label .. "no tab is selected at first")
            check(tabs:Select("b") and tabs:GetSelected() == "b" and picked[#picked] == "b", label .. "Select reports the selection")
            check(not tabs:Select("zzz") and tabs:GetSelected() == "b", label .. "an unknown tab changes nothing")
            ta.__scripts.OnClick(ta)
            check(tabs:GetSelected() == "a" and picked[#picked] == "a", label .. "clicking a tab selects it")
            check(ta.honorLogSelected and not tb.honorLogSelected, label .. "only the selected tab is marked")
            if present then
                check(selectCalls[#selectCalls] == ta and deselectCalls[#deselectCalls] == tb, label .. "PanelTemplates select and deselect are used")
            else
                check(ta.GetHeight(ta) > tb.GetHeight(tb), label .. "the selected plain tab is taller, not only a different colour")
            end

            -- bar
            local bar = Kit:Bar(parent)
            bar:SetValue01(0.4)
            check(bar:GetValue() == 0.4, label .. "bar value")
            bar:SetValue01(7)
            check(bar:GetValue() == 1, label .. "bar value clamps high")
            bar:SetValue01(-1)
            check(bar:GetValue() == 0, label .. "bar value clamps low")
            bar:SetBarColor(1, 0.5, 0.25)
            check(bar.honorLogColor[2] == 0.5, label .. "bar colour")

            -- ring
            local ring = Kit:Ring(parent, 150)
            check(ring.honorLogFull == present, label .. "the ring art is used only when the client has it")
            ring:SetRank(3, "Horde")
            check(ring.honorLogRank == 3 and ring.Badge.Label:GetText() == "3", label .. "ring rank number")
            if present then
                check(ring.Icon.__atlas == "UI-Character-Info-Honor-Icon-3", label .. "ring rank icon atlas")
                check(ring.Disc.__atlas == "UI-Character-Info-Honor-Bar-BG-Horde", label .. "ring faction disc")
                ring:SetRank(0, "Alliance")
                check(ring.Icon.__atlas == "UI-Character-Info-Honor-Icon-Alliance", label .. "rank 0 shows the faction icon")
                ring:SetProgress(0.4)
                check(pctCalls[#pctCalls][1] == ring.Cooldown and pctCalls[#pctCalls][2] == 0.4, label .. "progress goes through CooldownFrame_SetDisplayAsPercentage")
                _G.CooldownFrame_SetDisplayAsPercentage = nil
                local cdCalls = {}
                rawset(ring.Cooldown, "SetCooldown", function(_, start, duration) cdCalls.start, cdCalls.duration = start, duration end)
                rawset(ring.Cooldown, "Pause", function() cdCalls.paused = true end)
                mock.now = 1000
                ring:SetProgress(0.25)
                mock.now = nil
                check(cdCalls.duration == 100 and cdCalls.start == 975 and cdCalls.paused, label .. "without that function the cooldown is set and paused by hand")
                ring:SetProgress(5)
                check(ring.honorLogProgress == 1, label .. "ring progress clamps")
            else
                check(ring.Bar and ring.Icon, label .. "the fallback ring is an icon over a bar")
                ring:SetProgress(0.5)
                check(ring.Bar:GetValue() == 0.5, label .. "fallback ring progress drives the bar")
                ring:SetRank(0, "Alliance")
                check(ring.Icon.__texture == HL.RANK_ICON_FALLBACK, label .. "rank 0 uses the neutral icon")
            end

            -- tile and rows
            local tile = Kit:Tile(parent)
            check(tile.label and tile.value and tile.note and tile.noteRow and not tile.noteRow:IsShown(), label .. "tile parts")
            local made, updated = 0, {}
            local rows = Kit:Rows(parent, 20, function() made = made + 1 end, function(row, entry, i) updated[i] = entry end)
            rows:SetData({ "x", "y", "z" })
            check(made == 3 and rows.count == 3 and updated[3] == "z" and rows.frames[3]:IsShown(), label .. "rows show one row per entry")
            rows:SetData({ "q" })
            check(made == 3 and rows.frames[1]:IsShown() and not rows.frames[2]:IsShown() and not rows.frames[3]:IsShown(), label .. "rows hide the rest and are pooled")
            rows:SetData({})
            check(rows.count == 0 and not rows.frames[1]:IsShown(), label .. "rows with no data")

            -- item icon
            local base = HL.GearDB[vendorItem]
            local icon = Kit:ItemIcon(parent, 18)
            icon:SetItem(vendorItem)
            check(icon.honorLogItemID == vendorItem and icon.honorLogTexture.__texture == 100000 + vendorItem % 1000, label .. "item icon texture")
            local qr, qg, qb = Kit:QualityColor(base.quality)
            check(icon.honorLogBorder.__color[1] == qr and icon.honorLogBorder.__color[2] == qg and icon.honorLogBorder.__color[3] == qb,
                label .. "item border has the quality colour")
            mock.itemQuality[vendorItem] = 4
            icon:SetItem(vendorItem)
            check(icon.honorLogQuality == 4, label .. "quality from C_Item.GetItemQualityByID wins over the gear database")
            mock.itemQuality[vendorItem] = nil
            _G.ITEM_QUALITY_COLORS = { [3] = { r = 0.1, g = 0.2, b = 0.3 } }
            check(select(2, Kit:QualityColor(3)) == 0.2, label .. "ITEM_QUALITY_COLORS is used when present")
            _G.ITEM_QUALITY_COLORS = nil
            check(select(2, Kit:QualityColor(3)) == 0.44, label .. "a built-in table is used otherwise")
            icon:SetItem(nil)
            icon:SetItem(vendorItem)
            icon.__scripts.OnEnter(icon)
            check(mock.tip.itemID == vendorItem and mock.tip.owner == icon and mock.tip.anchor == "ANCHOR_RIGHT" and mock.tip.shown,
                label .. "item tooltip is the item's own")
            local vendorLine, clickLine
            for _, line in ipairs(mock.tip.lines) do
                if line.text == HL:GetVendorLine(vendorItem) then vendorLine = line end
                if line.text == "Click: show the vendor on your map" then clickLine = line end
            end
            check(vendorLine, label .. "tooltip says where it is sold")
            check(clickLine and clickLine.g > clickLine.r, label .. "tooltip adds the green click line")
            icon.__scripts.OnLeave(icon)
            check(not mock.tip.shown, label .. "tooltip hides on leave")

            HL:ClearMapPins()
            icon.__scripts.OnClick(icon, "LeftButton")
            check(HL.MapPin:Count() == 1, label .. "a click places the vendor's map pin")
            HL:ClearMapPins()
            local dressed, linked = {}, {}
            _G.DressUpItemLink = function(link) dressed[#dressed + 1] = link end
            _G.ChatEdit_InsertLink = function(link) linked[#linked + 1] = link return true end
            mock.ctrl = true
            icon.__scripts.OnClick(icon, "LeftButton")
            mock.ctrl = false
            check(#dressed == 1 and dressed[1]:find("Hitem:" .. vendorItem, 1, true) and HL.MapPin:Count() == 0, label .. "Ctrl+click previews and places no pin")
            mock.shift = true
            icon.__scripts.OnClick(icon, "LeftButton")
            mock.shift = false
            check(#linked == 1 and linked[1]:find("Hitem:" .. vendorItem, 1, true) and HL.MapPin:Count() == 0 and #dressed == 1,
                label .. "Shift+click links the item and places no pin")
            _G.DressUpItemLink, _G.ChatEdit_InsertLink = nil, nil
            mock.ctrl, mock.shift = true, true
            icon.__scripts.OnClick(icon, "LeftButton") -- without the client functions: nothing, and no error
            mock.ctrl, mock.shift = false, false

            -- mark icon
            local mark = Kit:MarkIcon(parent, 14)
            mark:SetBattleground("AB")
            check(mark.honorLogTexture.__texture == HL.BG_ICONS.AB, label .. "mark icon texture")
            mark.__scripts.OnEnter(mark)
            check(mock.tip.itemID == 20559 and mock.tip.shown, label .. "mark tooltip shows the mark item")
            local bags
            for _, line in ipairs(mock.tip.lines) do if line.text:find("^In your bags") then bags = line.text end end
            check(bags == string.format("In your bags: %d", HL:GetCurrentMarks("AB")), label .. "mark tooltip counts the bags: " .. tostring(bags))
            mark.__scripts.OnClick(mark, "LeftButton")

            -- place link
            local calls = {}
            local realVendor, realPlace = HL.ShowVendorOnMap, HL.ShowPlaceOnMap
            HL.ShowVendorOnMap = function(_, vendor) calls.vendor = vendor end
            HL.ShowPlaceOnMap = function(_, place) calls.place = place end
            local pl = Kit:PlaceLink(parent)
            local vendor, place = { name = "Brave Stonehide", map = 1 }, { name = "Graveyard", map = 2, x = 1, y = 2 }
            pl:SetVendor(vendor)
            check(pl.honorLogName:GetText() == "Brave Stonehide", label .. "place link names the vendor")
            pl.__scripts.OnClick(pl)
            check(calls.vendor == vendor and not calls.place, label .. "a vendor link calls ShowVendorOnMap")
            pl:SetPlace(place)
            check(pl.honorLogName:GetText() == "Graveyard", label .. "place link names the place")
            pl.__scripts.OnClick(pl)
            check(calls.place == place, label .. "a place link calls ShowPlaceOnMap")
            pl.__scripts.OnEnter(pl)
            pl.__scripts.OnLeave(pl)
            HL.ShowVendorOnMap, HL.ShowPlaceOnMap = realVendor, realPlace
            removeBlizzardGlobals()
        end
        kitSuite(true)
        kitSuite(false)
        setMode(true)
        mock.atlasMode, mock.missingTemplates = "default", {}

        -- ── Window ──────────────────────────────────────────────────────────────────
        local Window = HL.Window
        local framesBefore = #mock.frames
        local probeRefreshes
        local function registerProbe()
            probeRefreshes = 0
            HL.Window:RegisterScreen({ key = "probe", title = "Probe", order = 2, create = function(parent)
                local f = CreateFrame("Frame", nil, parent)
                function f:Refresh() probeRefreshes = probeRefreshes + 1 end
                return f
            end })
        end
        registerProbe()
        check(#Window.screens == 2 and Window.screens[1].key == "overview" and Window.screens[2].key == "probe", "window: screens are kept in order")
        check(_G.HonorLogWindow == nil and not Window:IsShown(), "window: still nothing before the first open")
        check(HonorLogDB.settings.windowScale == 1 and HonorLogDB.settings.windowTab == "overview", "window: the new settings have defaults")

        mock.runShowScripts = true
        local function closed() return not Window:IsShown() end
        local function expectOpen(what, fn)
            if Window:IsShown() then Window:Hide() end
            fn()
            check(Window:IsShown(), "window opens from " .. what)
            Window:Hide()
        end
        local mini = HL.mainFrame
        local miniBefore = mini:IsShown()
        expectOpen("the bare slash command", function() SlashCmdList.HONORLOG("") end)
        check(_G.HonorLogWindow == Window.frame and Window.frame:GetName() == "HonorLogWindow", "window: the frame is HonorLogWindow")
        check(mini:IsShown() == miniBefore, "the bare slash command leaves the small frame alone")
        expectOpen("/honorlog toggle", function() SlashCmdList.HONORLOG("toggle") end)
        SlashCmdList.HONORLOG("toggle")
        SlashCmdList.HONORLOG("toggle")
        check(closed(), "toggle closes the window again")
        expectOpen("the key binding function", function() _G.HonorLog_ToggleWindow() end)
        expectOpen("the addon menu function", function() _G.HonorLog_OnAddonCompartmentClick("HonorLog", "LeftButton") end)
        expectOpen("the broker left click", function() HL.ldb.OnClick(nil, "LeftButton") end)
        expectOpen("the small frame's menu", function()
            HL:ShowContextMenu()
            mock.pickDropdown(_G.HonorLogContextMenu, "Open HonorLog")
        end)
        check(_G.BINDING_HEADER_HONORLOG == "HonorLog" and _G.BINDING_NAME_HONORLOG_TOGGLE == "Open or close HonorLog", "binding names are set")
        local bindings = io.open(ROOT .. "/Bindings.xml"):read("*a")
        check(bindings:find('name="HONORLOG_TOGGLE"', 1, true) and bindings:find('header="HONORLOG"', 1, true)
            and bindings:find('category="ADDONS"', 1, true) and bindings:find("HonorLog_ToggleWindow()", 1, true),
            "Bindings.xml names the binding under the AddOns category with HonorLog's header and calls the toggle")
        check(not io.open(ROOT .. "/HonorLog.toc"):read("*a"):find("Bindings.xml", 1, true), "the toc does not list Bindings.xml")

        -- A template that comes back as a bare frame (a client that only logs a missing template) counts as missing.
        do
            local Kit = HL.Kit
            local holder = CreateFrame("Frame", nil, UIParent)
            mock.hollowTemplates = { InsetFrameTemplate = true, UIPanelButtonTemplate = true, PanelTabButtonTemplate = true,
                PortraitFrameTemplate = true, PortraitFrameBaseTemplate = true }
            check(Kit:Inset(holder).honorLogTemplate == false, "kit: a hollow inset template is drawn plain")
            check(Kit:Button(holder, "B", "red").honorLogTemplate == false, "kit: a hollow button template is drawn plain")
            local hollowWindow = Kit:Window("HonorLogHollowTestWindow", 300, 200)
            check(hollowWindow.honorLogChrome == false and hollowWindow.Content ~= nil and hollowWindow.CloseButton ~= nil, "kit: hollow window templates fall back to the plain window")
            hollowWindow:SetTitleText("T")
            check(hollowWindow:GetTitleText() == "T", "kit: the plain window still takes a title")
            mock.hollowTemplates = {}
            check(Kit:Inset(holder).honorLogTemplate == "InsetFrameTemplate", "kit: with its regions the inset template takes")
            -- The window's content has its own ground, and the title bar texts sit on the drag strip.
            local win = Kit:Window("HonorLogGroundTestWindow", 300, 200)
            check(win.Content.honorLogBg ~= nil and win.honorLogDrag ~= nil, "kit: the content has a background and the window a drag strip")
        end
        check(HL.Window.leftText:GetParent() == HL.Window.frame.honorLogDrag and HL.Window.rightText:GetParent() == HL.Window.frame.honorLogDrag, "window: the title bar texts sit on the drag strip, above the frame art")
        local tocText = io.open(ROOT .. "/HonorLog.toc"):read("*a")
        check(tocText:find("## AddonCompartmentFunc: HonorLog_OnAddonCompartmentClick", 1, true) and tocText:find("## IconTexture: ", 1, true), "toc names the addon menu function and icon")
        SlashCmdList.HONORLOG("mini")
        check(mini:IsShown() ~= miniBefore and not Window:IsShown(), "/honorlog mini toggles the small frame, not the window")
        SlashCmdList.HONORLOG("mini")
        check(mini:IsShown() == miniBefore, "/honorlog mini toggles it back")
        local helpFrom = #printed
        SlashCmdList.HONORLOG("help")
        local sawMini = false
        for i = helpFrom + 1, #printed do if printed[i]:find("/honorlog mini", 1, true) then sawMini = true end end
        check(sawMini, "the help lists /honorlog mini")
        check(HL.ldb.icon == Window.frame.honorLogPortrait, "the portrait is the broker object's icon")
        local escape = false
        for _, n in ipairs(UISpecialFrames) do if n == "HonorLogWindow" then escape = true end end
        check(escape, "Escape closes the window (registered in UISpecialFrames)")

        -- the title bar
        Window:Show()
        check(Window.leftText:GetText() == "Tester \194\183 Level 60 Warrior", "title bar left: " .. tostring(Window.leftText:GetText()))
        local rightText = Window.rightText:GetText()
        check(rightText:find("Rank week resets in", 1, true) and rightText:find("3d 0h", 1, true) and rightText:find("|cffffffff", 1, true), "title bar right: " .. tostring(rightText))
        mock.rankWindow.noData = true
        Window:UpdateTitleBar()
        check(not Window.rightText:IsShown(), "the reset text hides without rank data")
        mock.rankWindow.noData = false
        Window:UpdateTitleBar()
        check(Window.rightText:IsShown(), "…and returns with it")

        -- tickers and OnUpdate
        local base = liveTickers()
        Window:Hide()
        check(liveTickers() == tickersAtStart and Window.ticker == nil, "no live ticker while the window is hidden")
        Window:Show()
        check(liveTickers() == tickersAtStart + 1, "exactly one ticker while shown")
        local ticker = Window.ticker
        mock.weeklyReset = 86400
        ticker.fn()
        check(Window.rightText:GetText():find("1d 0h", 1, true), "the 30-second ticker refreshes the title bar")
        mock.weeklyReset = 3 * 86400
        check(ticker.interval == 30, "the ticker runs every 30 seconds")
        Window:Hide()
        check(ticker.cancelled and liveTickers() == base - 1, "the ticker is cancelled on hide")
        local onUpdates = 0
        for i = framesBefore + 1, #mock.frames do if mock.frames[i].__scripts.OnUpdate then onUpdates = onUpdates + 1 end end
        check(onUpdates == 0, "the window sets no OnUpdate script")

        -- screens: lazy creation, tab switching, dirty and refresh
        check(Window.frames.overview and not Window.frames.probe, "a screen's frame is built when its tab is first shown")
        Window:Show()
        local probeTab = Window.tabs.buttons.probe
        probeTab.__scripts.OnClick(probeTab)
        check(Window.frames.probe and Window.current == "probe" and HonorLogDB.settings.windowTab == "probe", "selecting a tab builds its screen and saves the tab")
        check(not Window.frames.overview:IsShown() and Window.frames.probe:IsShown(), "only the selected screen is shown")
        local r0 = probeRefreshes
        HL:Fire("HonorLog_GameRecorded", {})
        check(probeRefreshes == r0 + 1, "HonorLog_GameRecorded refreshes the shown screen at once")
        HL:Fire("HonorLog_RankUp", 4, {})
        HL:Fire("HonorLog_GoalAcquired", 1)
        check(probeRefreshes == r0 + 3, "HonorLog_RankUp and HonorLog_GoalAcquired refresh it too")
        HL:OnDataUpdated()
        check(probeRefreshes == r0 + 4, "the OnDataUpdated post-hook refreshes it")
        Window:Hide()
        HL:Fire("HonorLog_GameRecorded", {})
        HL:OnDataUpdated()
        check(probeRefreshes == r0 + 4 and Window.dirty, "while hidden a change only marks the window dirty")
        Window:Show()
        check(probeRefreshes == r0 + 5 and not Window.dirty, "the next show refreshes and clears the mark")
        Window:Hide()
        Window:Show()
        check(probeRefreshes == r0 + 6, "every show refreshes")
        probeTab.__scripts.OnClick(probeTab)
        check(probeRefreshes == r0 + 7, "selecting a tab refreshes it")

        -- position, scale and tab survive a reload
        Window.frame:ClearAllPoints()
        Window.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 120, -80)
        Window.frame.honorLogDrag.__scripts.OnDragStop(Window.frame.honorLogDrag)
        local saved = HonorLogDB.settings.windowPoint
        check(saved and saved[1] == "TOPLEFT" and saved[2] == "TOPLEFT" and saved[3] == 120 and saved[4] == -80, "dragging saves the position")
        HonorLogDB.settings.windowScale = 1.25
        Window:Hide()
        mock.runShowScripts = false
        mock.fireEvent("PLAYER_LOGOUT")
        for i = #mock.frames, 1, -1 do mock.frames[i] = nil end
        mock.timers = {}
        LibStub.libs, LibStub.minors = {}, {}
        _G.HonorLogWindow, _G.HonorLogContextMenu = nil, nil
        for i = #UISpecialFrames, 1, -1 do UISpecialFrames[i] = nil end
        HL = loadAddon()
        mock.fireEvent("ADDON_LOADED", "HonorLog")
        mock.fireEvent("PLAYER_LOGIN")
        mock.fireEvent("PLAYER_ENTERING_WORLD")
        Window = HL.Window
        framesBefore = #mock.frames
        check(Window.frame == nil and _G.HonorLogWindow == nil, "after a reload the window is not built until it is opened")
        registerProbe()
        mock.runShowScripts = true
        SlashCmdList.HONORLOG("")
        local lastPoint = Window.frame.__points[#Window.frame.__points]
        check(lastPoint[1] == "TOPLEFT" and lastPoint[3] == "TOPLEFT" and lastPoint[4] == 120 and lastPoint[5] == -80, "the saved position is restored")
        check(Window.frame:GetScale() == 1.25, "the saved scale is restored")
        check(Window.current == "probe" and Window.frames.probe:IsShown(), "the last tab is restored")
        Window:Hide()

        -- ── Overview ────────────────────────────────────────────────────────────────
        HL.db.settings.windowTab = "overview"
        local char = HL.db.char
        local saveChar = { history = char.history, goals = char.goals, session = char.session }
        local saveRank = { level = mock.rank.level, earned = mock.rank.earned, threshold = mock.rank.threshold }
        local saveState = { level = mock.level, faction = mock.faction, honor = mock.currencies[1792].quantity,
            window = { cap = mock.rankWindow.cap, prevCap = mock.rankWindow.prevCap, week = mock.rankWindow.week }, noData = mock.rankWindow.noData }
        mock.rank.level, mock.rank.earned, mock.rank.threshold = 3, 120, 1050
        mock.level, mock.faction, mock.currencies[1792].quantity = 60, "Alliance", 8200
        mock.rankWindow.cap, mock.rankWindow.prevCap, mock.rankWindow.week, mock.rankWindow.noData = 5, 3, 2, false
        local function commas(n) return HL.Rank.FormatNumber(n) end
        local now = time()
        local function game(bg, result, duration, honor, marks, pts, state, extra)
            local g = { bgType = bg, result = result, win = result == "win", duration = duration, honor = honor, marks = marks,
                rankPoints = pts, rankState = state, timestamp = now }
            for k, v in pairs(extra or {}) do g[k] = v end
            return g
        end
        local games = {
            game("AB", "win", 600, 450, 3, 100, "earned"),
            game("WSG", "loss", 305, 120, 1, 0, "zero"),
            game("AV", "draw", 1800, 200, 0, nil, "unknown", { rankPoints = 0 }),
            game("DI", "left", 90, 0, 0, 0, "zero"),
            game("AB", "win", 720, 300, 5, 0, "capped", { honorCapped = true }),
            game("WSG", "loss", 61, 10, 0, 0, "gated"),
            game("AV", "win", 100, 1, 1, 5, "earned"),
        }
        char.history = games
        Window:Show("overview")
        local ov = Window.frames.overview
        local parts = ov.honorLogParts
        check(ov and parts and Window.current == "overview", "overview: built on its tab")
        local left, tiles = parts.left, parts.tiles

        -- left pane
        local info = HL.Rank:GetInfo()
        check(left.season:GetText() == "Season 2", "overview: season " .. tostring(left.season:GetText()))
        check(left.rank:GetText() == "Rank 3 Sergeant", "overview: rank and title: " .. tostring(left.rank:GetText()))
        check(left.ring.honorLogRank == 3 and math.abs(left.ring.honorLogProgress - info.totalPoints / info.weekCapTotal) < 1e-9, "overview: ring rank and progress")
        local pts = left.points:GetText()
        check(pts:find("Rank Points: ", 1, true) and pts:find(commas(info.totalPoints), 1, true) and pts:find(commas(HL.Rank:TotalForRank(4)), 1, true)
            and pts:find("|cffffffff", 1, true), "overview: rank points line: " .. tostring(pts))
        check(left.percent:GetText() == string.format("%d%% of this week's cap, Rank %d", math.floor(info.totalPoints / info.weekCapTotal * 100), info.weekCapRank),
            "overview: percent of the cap: " .. tostring(left.percent:GetText()))
        check(not left.gate:IsShown(), "overview: no gate warning at level 60")
        check(left.honorValue:GetText():find("8,200", 1, true) and left.honorValue:GetText():find("25,000", 1, true), "overview: honor value")
        check(left.honorBar:GetValue() == 8200 / 25000, "overview: honor bar fraction")
        check(not left.cap:IsShown(), "overview: no cap line far from the cap")
        mock.currencies[1792].quantity = 24000
        ov:Refresh()
        local capAdvice = HL:GetHonorCapAdvice()
        check(capAdvice and capAdvice.gamesToCap and left.cap:IsShown() and left.cap:GetText() == string.format("Cap in about %d games", capAdvice.gamesToCap),
            "overview: cap line " .. tostring(left.cap:GetText()))
        mock.currencies[1792].quantity = 8200

        -- tiles, normal case
        local m = HL:GetTodayModel()
        check(tiles[1].value:GetText() == "3 \226\128\147 2", "overview: today's wins and losses " .. tostring(tiles[1].value:GetText()))
        check(tiles[1].note:GetText() == string.format("7 games in %s", HL.Rank.FormatSpan(m.duration)), "overview: games and time " .. tostring(tiles[1].note:GetText()))
        check(tiles[2].value:GetText() == "+" .. commas(m.honor) and tiles[2].value.__textColor[1] == 1 and tiles[2].value.__textColor[3] == 0, "overview: honor today in gold")
        check(tiles[2].note:GetText() == commas(m.honorPerHour) .. " an hour", "overview: honor per hour " .. tostring(tiles[2].note:GetText()))
        check(tiles[3].value:GetText() == "+105", "overview: rank points today " .. tostring(tiles[3].value:GetText()))
        check(tiles[4].value:GetText() == "+10", "overview: marks today " .. tostring(tiles[4].value:GetText()))
        local row = tiles[4].noteRow
        check(row:IsShown() and not tiles[4].note:IsShown(), "overview: the marks tile's note line is the icon row")
        check(row.widgets.AB.icon:IsShown() and row.widgets.AB.count:GetText() == "8" and row.widgets.WSG.count:GetText() == "1"
            and row.widgets.AV.count:GetText() == "1" and not row.widgets.DI.icon:IsShown(), "overview: mark counts per battleground")

        -- tiles, gate case (level 35 holds rank points at rank 3)
        char.history = { game("AB", "win", 600, 450, 3, 0, "gated"), game("WSG", "loss", 300, 100, 1, 0, "gated") }
        mock.level = 35
        ov:Refresh()
        check(tiles[3].value:GetText() == "0" and tiles[3].value.__textColor[2] == 0.6 and tiles[3].note:GetText() == "Level 40 needed", "overview: rank tile in the gate case: " .. tostring(tiles[3].note:GetText()))
        check(left.gate:IsShown() and left.gateTitle:GetText() == "Rank 4 needs level 40" and left.gateText:GetText() == HL.Rank:GateText(HL.Rank:GetInfo().gate),
            "overview: the gate warning")
        mock.level = 60
        -- tiles, cap case
        mock.rank.level, mock.rank.earned, mock.rank.threshold = 5, 10, 1350
        char.history = { game("AB", "win", 600, 450, 3, 0, "capped") }
        ov:Refresh()
        check(tiles[3].value:GetText() == "0" and tiles[3].note:GetText() == "Weekly cap reached", "overview: rank tile in the cap case: " .. tostring(tiles[3].note:GetText()))
        mock.rank.level, mock.rank.earned, mock.rank.threshold = 3, 120, 1050
        -- no games today
        char.history = {}
        ov:Refresh()
        check(tiles[1].value:GetText() == "0 \226\128\147 0" and tiles[1].note:GetText() == "No games yet today", "overview: no games today")
        check(tiles[4].value:GetText() == "+0" and not row.widgets.AB.icon:IsShown(), "overview: no marks today")

        -- recent games
        char.history = games
        ov:Refresh()
        local g = parts.games
        check(g.rows.count == 6 and not g.empty:IsShown(), "overview: six recent games")
        local function cellText(i, key) return g.rows.frames[i].cells[key].text:GetText() end
        local expectBg = { "AB", "WSG", "AV", "DI", "AB", "WSG" }
        for i, bg in ipairs(expectBg) do
            check(cellText(i, "bg") == HL:GetBGDisplayName(bg), "overview: row " .. i .. " battleground")
        end
        local words = { "Win", "Loss", "Draw", "Left early", "Win", "Loss" }
        for i, word in ipairs(words) do check(cellText(i, "result") == word, "overview: row " .. i .. " result word " .. tostring(cellText(i, "result"))) end
        local sym = function(i) return g.rows.frames[i].cells.result.symbol end
        check(sym(1).__texture == "Interface\\RaidFrame\\ReadyCheck-Ready" and sym(1):IsShown(), "overview: a win has the tick")
        check(sym(2).__texture == "Interface\\RaidFrame\\ReadyCheck-NotReady" and sym(2):IsShown(), "overview: a loss has the cross")
        check(not sym(3):IsShown() and not sym(4):IsShown(), "overview: a draw and a left-early game have words only")
        check(cellText(1, "length") == "10:00" and cellText(2, "length") == "5:05" and cellText(6, "length") == "1:01", "overview: lengths as m:ss")
        check(cellText(1, "honor") == "+450" and cellText(5, "honor") == "+300 *", "overview: honor, with a marker when played at the cap")
        local honorCell = g.rows.frames[5].cells.honor
        honorCell.__scripts.OnEnter(honorCell)
        check(mock.tip.lines[1].text == HL:DescribeHonor(games[5]) and mock.tip.shown, "overview: the honor cell's tooltip is DescribeHonor")
        honorCell.__scripts.OnLeave(honorCell)
        local tones = { "earned", "blocked", "unknown", "blocked", "blocked", "blocked" }
        local colorOf = { earned = Kit.COLORS.white, blocked = Kit.COLORS.orange, unknown = Kit.COLORS.grey }
        for i, tone in ipairs(tones) do
            local text, t = HL:DescribeRankPoints(games[i])
            check(t == tone and cellText(i, "rank") == text, "overview: row " .. i .. " rank points text and tone (" .. tostring(text) .. ")")
            local tc = g.rows.frames[i].cells.rank.text.__textColor
            check(tc[1] == colorOf[tone][1] and tc[2] == colorOf[tone][2] and tc[3] == colorOf[tone][3], "overview: row " .. i .. " rank points colour for " .. tone)
        end
        check(cellText(1, "marks") == "+3" and g.rows.frames[1].cells.marks.mark.honorLogBG == "AB", "overview: marks with their icon")
        char.history = {}
        ov:Refresh()
        check(g.rows.count == 0 and g.empty:IsShown() and g.empty:GetText() == "No games recorded yet. Play a battleground and it will show here.", "overview: no games recorded")

        -- what to do next
        local realAdvice, realGoals = HL.GetAdvice, HL.GetAllGoalsProgress
        local a = parts.advice
        HL.GetAdvice = function() return {
            { kind = "cap", head = "Honor is near the cap.", body = "Spend it.", itemID = vendorItem },
            { kind = "bestbg", head = "AB pays best.", body = "412 honor a game.", bgType = "AB" },
            { kind = "nogames", head = "No games recorded yet.", body = "Play one." },
        } end
        ov:Refresh()
        check(a.rows.count == 3 and not a.empty:IsShown(), "overview: three advice rows")
        do
            local f1, f2 = a.rows.frames[1], a.rows.frames[2]
            local _, _, _, _, y1 = f1:GetPoint(1)
            local _, _, _, _, y2 = f2:GetPoint(1)
            check(y1 == 0 and f1:GetHeight() >= 18 and y2 == -(f1:GetHeight() + 8), "overview: advice rows stack under one another, each as tall as its text")
            local long = string.rep("word ", 60)
            a.rows:SetData({ { head = long }, { head = long }, { head = long }, { head = long }, { head = long } })
            check(f1:GetHeight() == 36 and a.rows.count == 3 and not a.rows.frames[4]:IsShown(), "overview: a long advice line wraps to three lines at most, and a row that would run past the box is left out")
            a.rows:SetData({})
            check(a.rows.count == 0 and not f1:IsShown(), "overview: no advice hides every row")
            HL.Window:RefreshCurrent()
        end
        local r1, r2, r3 = a.rows.frames[1], a.rows.frames[2], a.rows.frames[3]
        check(r1.text:GetText() == "Honor is near the cap. |cffa8a297Spend it.|r" or r1.text:GetText():find("^Honor is near the cap%. |cff%x+Spend it%.|r$"), "overview: head then grey body: " .. tostring(r1.text:GetText()))
        check(r1.item:IsShown() and r1.item.honorLogItemID == vendorItem and not r1.mark:IsShown(), "overview: an advice row with an item shows its icon")
        check(r2.mark:IsShown() and r2.mark.honorLogBG == "AB" and not r2.item:IsShown(), "overview: an advice row with a battleground shows its mark")
        check(not r3.item:IsShown() and not r3.mark:IsShown(), "overview: a plain advice row has no icon")
        HL.GetAdvice = function() return {} end
        ov:Refresh()
        check(a.rows.count == 0 and a.empty:IsShown() and a.empty:GetText() == "Nothing pressing. Keep playing.", "overview: nothing pressing")
        HL.GetAdvice = realAdvice
        ov:Refresh()
        check(a.rows.count == #HL:GetAdvice(4), "overview: the real advice list is drawn")

        -- next goal
        local goalPart = parts.goal
        local pickerCalls, tabCalls = 0, {}
        local realPicker, realSwitch = HL.ShowGoalPicker, HL.SwitchTab
        HL.ShowGoalPicker = function() pickerCalls = pickerCalls + 1 end
        HL.SwitchTab = function(_, tab) tabCalls[#tabCalls + 1] = tab end
        HL.GetAllGoalsProgress = function() return {} end
        ov:Refresh()
        check(goalPart.none:IsShown() and goalPart.none:GetText() == "No goals yet" and goalPart.add:IsShown() and not goalPart.view:IsShown() and not goalPart.icon:IsShown(), "overview: no goals")
        check(goalPart.add:GetText() == "Add a goal", "overview: the add button")
        goalPart.add.__scripts.OnClick(goalPart.add)
        check(pickerCalls == 1, "overview: Add a goal opens the goal picker")
        local gp = { itemID = vendorItem, name = "Premier Test Cloak", isComplete = false, rows = {
            { kind = "honor", needed = 5000, current = 1200, met = false },
            { kind = "marks", bg = "AB", needed = 10, current = 10, met = true },
            { kind = "rank", needed = 6, current = 3, met = false },
            { kind = "level", needed = 55, current = 35, met = false },
            { kind = "gold", needed = 15000, current = 20000, met = true },
            { kind = "rep", needed = 5, current = 4, met = false, factionName = "The League of Arathor", standingName = "Friendly" },
        } }
        HL.GetAllGoalsProgress = function() return { gp } end
        ov:Refresh()
        check(goalPart.icon:IsShown() and goalPart.icon.honorLogItemID == vendorItem and goalPart.view:IsShown() and not goalPart.add:IsShown() and not goalPart.none:IsShown(), "overview: a goal is shown")
        check(goalPart.name:GetText() == Kit:QualityHex(goalPart.icon.honorLogQuality) .. "Premier Test Cloak|r", "overview: the name in its quality colour")
        check(goalPart.percent:GetText() == string.format("%d%% complete", math.floor(HL:GetGoalPercent(gp))), "overview: percent complete " .. tostring(goalPart.percent:GetText()))
        local gr = goalPart.rows
        local expect = {
            { "Honor", "1,200 / 5,000", Kit.COLORS.white }, { HL:GetBGDisplayName("AB") .. " marks", "10 / 10", Kit.COLORS.green },
            { "Rank", "3 / 6", Kit.COLORS.red }, { "Level", "35 / 55", Kit.COLORS.red },
            { "Gold", "2g / 1g", Kit.COLORS.green }, { "The League of Arathor", "Neutral / Friendly", Kit.COLORS.white },
        }
        check(gr.count == 6, "overview: one line per requirement")
        for i, e in ipairs(expect) do
            local rf = gr.frames[i]
            check(rf.label:GetText() == e[1] and rf.value:GetText() == e[2], "overview: goal row " .. i .. " reads " .. tostring(rf.label:GetText()) .. " " .. tostring(rf.value:GetText()))
            local c = rf.value.__textColor
            check(c[1] == e[3][1] and c[2] == e[3][2] and c[3] == e[3][3], "overview: goal row " .. i .. " colour")
        end
        check(gr.frames[2].mark:IsShown() and gr.frames[2].mark.honorLogBG == "AB" and not gr.frames[1].mark:IsShown(), "overview: the marks row has its mark icon")
        check(goalPart.view:GetText() == "View goal", "overview: the view button")
        local miniShown = HL.mainFrame:IsShown()
        if miniShown then HL:ToggleMainFrame() end
        goalPart.view.__scripts.OnClick(goalPart.view)
        check(tabCalls[1] == "goals" and HL.mainFrame:IsShown(), "overview: View goal opens the goals panel in the small frame")
        if not miniShown then HL:ToggleMainFrame() end
        -- an unmet-rep-free goal and a goal whose rows are all requirements work with the real model too
        HL.GetAllGoalsProgress = realGoals
        HL.ShowGoalPicker, HL.SwitchTab = realPicker, realSwitch
        ov:Refresh()
        check(goalPart.none:IsShown() == (#HL:GetAllGoalsProgress() == 0), "overview: the real goal list is drawn")

        -- no rank data, no games, and reads that return nothing or a secret
        mock.rankWindow.noData = true
        char.history = {}
        ov:Refresh()
        check(left.rank:GetText() == "No rank yet" and left.points:GetText() == "No rank yet" and left.ring.honorLogRank == 0 and not left.gate:IsShown() and left.season:GetText() == "",
            "overview: without rank data it says so")
        mock.rankWindow.noData = false
        local errorsBefore = #mock.handledErrors
        local secret = mock.newSecret
        local savedReads = { UnitName = UnitName, UnitLevel = UnitLevel, UnitClass = UnitClass, UnitFactionGroup = UnitFactionGroup,
            info = C_CurrencyInfo.GetCurrencyInfo, rank = C_MajorFactions.GetMajorFactionProgressionInfo, icon = C_Item.GetItemIconByID,
            count = C_Item.GetItemCount, season = C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd, reset = C_DateAndTime.GetSecondsUntilWeeklyReset }
        _G.UnitName, _G.UnitLevel, _G.UnitClass, _G.UnitFactionGroup = function() return secret() end, function() return secret() end, function() return secret() end, function() return secret() end
        C_CurrencyInfo.GetCurrencyInfo = function() return nil end
        C_MajorFactions.GetMajorFactionProgressionInfo = function() return { renownLevel = secret(), renownReputationEarned = secret() } end
        C_Item.GetItemIconByID, C_Item.GetItemCount = function() return nil end, function() return secret() end
        C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd, C_DateAndTime.GetSecondsUntilWeeklyReset = function() return secret() end, function() return secret() end
        Window:UpdateTitleBar()
        ov:Refresh()
        HL:GetBGDisplayName("AB")
        check(#mock.handledErrors == errorsBefore, "overview: no error when every client read is secret: " .. tostring(mock.handledErrors[errorsBefore + 1]))
        C_CurrencyInfo.GetCurrencyInfo = function() return secret() end
        C_MajorFactions.GetMajorFactionProgressionInfo = function() return nil end
        Window:UpdateTitleBar()
        ov:Refresh()
        check(#mock.handledErrors == errorsBefore, "overview: no error when the reads return nil or a secret: " .. tostring(mock.handledErrors[errorsBefore + 1]))
        _G.UnitName, _G.UnitLevel, _G.UnitClass, _G.UnitFactionGroup = savedReads.UnitName, savedReads.UnitLevel, savedReads.UnitClass, savedReads.UnitFactionGroup
        C_CurrencyInfo.GetCurrencyInfo, C_MajorFactions.GetMajorFactionProgressionInfo = savedReads.info, savedReads.rank
        C_Item.GetItemIconByID, C_Item.GetItemCount = savedReads.icon, savedReads.count
        C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd, C_DateAndTime.GetSecondsUntilWeeklyReset = savedReads.season, savedReads.reset

        -- a screen that raises costs a refresh, not the caller
        local realTitle = HL.Rank.GetInfo
        HL.Rank.GetInfo = function() error("boom") end
        local before2 = #mock.handledErrors
        mock.runShowScripts = true
        ov:Refresh()
        Window:OnDataChanged()
        check(#mock.handledErrors >= before2, "a failing read is reported without stopping the caller")
        HL.Rank.GetInfo = realTitle
        for i = #mock.handledErrors, before2 + 1, -1 do mock.handledErrors[i] = nil end

        -- ── Integration: every control, twice ───────────────────────────────────────
        char.history = games
        local function integration(label)
            Window:Show("overview")
            local n = 0
            local list = {}
            for i = framesBefore, #mock.frames do list[#list + 1] = mock.frames[i] end
            for _, f in ipairs(list) do
                if f.__scripts.OnEnter then f.__scripts.OnEnter(f); n = n + 1 end
                if f.__scripts.OnLeave then f.__scripts.OnLeave(f) end
                if f.__scripts.OnClick then
                    f.__scripts.OnClick(f, "LeftButton"); n = n + 1
                    if not Window:IsShown() then Window:Show() end -- the close button closed it
                end
            end
            check(n > 20, label .. "integration clicked " .. n .. " controls")
            Window:Hide()
            Window:Show()
            check(Window:IsShown(), label .. "the window reopens")
            Window:Hide()
        end
        local before3 = #mock.handledErrors
        integration("window: ")
        -- the same with every template and atlas missing
        mock.atlasMode, mock.missingTemplates = "none", { ["*"] = true }
        mock.removeFonts()
        Window.frame, Window.frames, Window.tabs, Window.current, _G.HonorLogWindow = nil, {}, nil, nil, nil
        framesBefore = #mock.frames
        Window:Show("overview")
        check(Window.frame.honorLogChrome == false and Window.frames.overview.honorLogParts.left.ring.honorLogFull == false, "window: built from plain drawing when nothing exists")
        integration("window (plain): ")
        mock.atlasMode, mock.missingTemplates = "default", {}
        mock.restoreFonts()
        check(#mock.handledErrors == before3, "window: the integration run raised no error: " .. tostring(mock.handledErrors[before3 + 1]))

        -- put everything back
        mock.runShowScripts = false
        Window:Hide()
        char.history, char.goals, char.session = saveChar.history, saveChar.goals, saveChar.session
        mock.rank.level, mock.rank.earned, mock.rank.threshold = saveRank.level, saveRank.earned, saveRank.threshold
        mock.level, mock.faction, mock.currencies[1792].quantity = saveState.level, saveState.faction, saveState.honor
        mock.rankWindow.cap, mock.rankWindow.prevCap, mock.rankWindow.week = saveState.window.cap, saveState.window.prevCap, saveState.window.week
        mock.rankWindow.noData = saveState.noData
        mock.shift, mock.ctrl = false, false
        HL:ClearMapPins()
    end

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
