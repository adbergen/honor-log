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
        "Data/Vendors.lua", "Data/Quests.lua",
        "Data.lua", "Core.lua",
        "Modules/BattlegroundBase.lua", "Modules/AV.lua", "Modules/AB.lua", "Modules/WSG.lua",
        "Modules/DI.lua", "Modules/Rank.lua", "Modules/Quests.lua", "Modules/Characters.lua", "Modules/Weeks.lua", "Modules/WorldLog.lua", "Modules/Met.lua", "Modules/VendorScanner.lua", "Modules/Probe.lua",
        "Model.lua",
        "UI/Theme.lua", "UI/MapPin.lua", "UI/Animation.lua", "UI/MainFrame.lua", "UI/GoalsPanel.lua", "UI/Options.lua",
        "UI/Export.lua", "UI/Kit.lua", "UI/RankPane.lua", "UI/GearVendors.lua", "UI/Window.lua", "UI/Screens/Overview.lua", "UI/Screens/RankPlan.lua",
        "UI/Screens/Gear.lua", "UI/Screens/Battlegrounds.lua", "UI/Screens/Quests.lua", "UI/Moments.lua",
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
    -- Every HonorLog_GameScoreboard, with how many games were saved when it fired.
    mock.boards = {}
    HL.RegisterCallback(mock.boards, "HonorLog_GameScoreboard", function(_, board)
        mock.boards[#mock.boards + 1] = { board = board, saved = #HL.db.char.history }
    end)

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
    check(#mock.boards == 1 and mock.boards[1].saved == history0 + 1, "board event: one event for the first game, fired after the game was saved")
    check(#mock.boards[1].board.rows == 4 and mock.boards[1].board.rows[3].name == "Foe1" and mock.boards[1].board.rows[3].kb == 5 and mock.boards[1].board.rows[3].faction == 0,
        "board event: every row of the board")
    check(mock.boards[1].board.me.name == "Tester" and mock.boards[1].board.me.objectives["Flag Captures"] == 2 and mock.boards[1].board.result == "win"
        and mock.boards[1].board.bgType == "WSG" and type(mock.boards[1].board.timestamp) == "number", "board event: the player's row, the result, the battleground, a time")
    check(next(game, nil) ~= nil and game.rows == nil and game.board == nil and game.players == nil and game.teams.rows == nil, "board event: the saved game has no per-player rows")
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
    check(#mock.boards == 2, "board event: a game left before the end fires nothing")
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
    check(#mock.boards == 3 and mock.boards[3].board.result == "draw" and mock.boards[3].board.bgType == "AV", "board event: a draw fires with the result draw")
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
    check(#mock.boards == 4, "board event: a board that never became readable fires nothing (events so far: " .. #mock.boards .. ")")
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
        check(byNpc[12777].x == 74.4 and byNpc[12777].y == 67.5 and byNpc[12781].x == 75.2, "the Alliance quartermasters keep their coordinates")
        check(byNpc[12792].x == 37.0 and byNpc[12792].y == 65.0 and byNpc[12793].x == 36.5 and byNpc[12793].y == 66.2 and byNpc[14581].x == 36.8 and byNpc[14581].y == 67.3
            and byNpc[12796].x == 37.8 and byNpc[12796].y == 64.4 and byNpc[12792].map == 1454, "the Horde quartermasters have the positions read in the game on 2026-11-21")
        for _, v in ipairs(HL.VENDORS) do
            check(type(v.x) == "number" and type(v.y) == "number" and type(v.map) == "number", "vendor " .. tostring(v.npc) .. " has a map position")
        end
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
        check(HL:GetVendorFor(HORDE_ARMOR).x == 37.0 and HL:GetVendorFor(HORDE_ARMOR).y == 65.0 and HL:GetVendorFor(HORDE_ARMOR).map == 1454, "…with the position read in the game")
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
        local hordeRow = HL:GetVendorFor(HORDE_ARMOR)
        check(HL:ShowVendorOnMap({ name = hordeRow.name, role = hordeRow.role, npc = hordeRow.npc, map = hordeRow.map, place = hordeRow.place }) == false
            and MP:Count() == 0 and mock.waypoint == nil, "a built-in vendor's row with a map and no position: false, no pin")
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

        -- Message tests: one hidden addon message per command, never without one.
        do
            local chat = mock.chat
            local function lastTest() local m = HonorLogDB.probe.messaging; return m and m[#m] end
            local function said(text, from) return table.concat(printed, "\n", from + 1):find(text, 1, true) ~= nil end
            check(#chat.sent == 0, "probe: nothing was ever sent before a message test is asked for")
            chat.inGuild = false
            local at = #printed
            SlashCmdList.HONORLOG("probe guild")
            check(#chat.sent == 0 and lastTest() == nil and said("You are not in a guild", at), "probe guild: no guild, nothing sent")
            chat.inGuild = true
            mock.deferTimers = true
            at = #printed
            SlashCmdList.HONORLOG("probe guild")
            check(#chat.sent == 1 and chat.sent[1].prefix == "HonorLogProbe" and chat.sent[1].chatType == "GUILD" and chat.sent[1].text:find("^ping %d+$") and chat.registered.HonorLogProbe,
                "probe guild: one message, prefix registered, a payload with nothing about the player")
            SlashCmdList.HONORLOG("probe guild")
            check(#chat.sent == 1 and said("still waiting", at), "probe guild: a second test waits for the first")
            mock.flushTimers()
            local r = lastTest()
            check(r and r.channel == "GUILD" and r.sent == 0 and r.echoed == true and r.textReadable == true and r.senderReadable == true and r.listening == true,
                "probe guild: the echo is recorded")
            check(said("sent and received back", at), "probe guild: the result line says sharing works")
            check(pcall(mock.fireEvent, "CHAT_MSG_ADDON", "HonorLogProbe", "late", "GUILD", "X") and #HonorLogDB.probe.messaging == 1, "probe guild: the listener is gone after the wait")
            -- refused by the client
            chat.sendResult = 4
            at = #printed
            SlashCmdList.HONORLOG("probe guild")
            mock.flushTimers()
            check(lastTest().sent == 4 and lastTest().echoed == false and said("refused it (result: 4)", at), "probe guild: a refusal is recorded with its result")
            -- accepted, but nothing comes back
            chat.sendResult, chat.echo = 0, false
            at = #printed
            SlashCmdList.HONORLOG("probe guild")
            mock.flushTimers()
            check(lastTest().sent == 0 and lastTest().echoed == false and said("nothing came back", at), "probe guild: accepted without an echo")
            -- a secret sender never raises
            chat.echo, chat.secretSender = true, true
            check(pcall(SlashCmdList.HONORLOG, "probe guild"), "probe guild: a secret sender raises nothing")
            mock.flushTimers()
            check(lastTest().echoed == true and lastTest().senderReadable == false, "probe guild: a secret sender is recorded as unreadable")
            chat.secretSender = false
            -- the group channel follows the kind of group
            at = #printed
            SlashCmdList.HONORLOG("probe group")
            check(said("You are not in a group", at), "probe group: no group, nothing sent")
            local sentBefore = #chat.sent
            for _, pair in ipairs({ { "instance", "INSTANCE_CHAT" }, { "raid", "RAID" }, { "party", "PARTY" } }) do
                chat.group = pair[1]
                SlashCmdList.HONORLOG("probe group")
                mock.flushTimers()
                check(chat.sent[#chat.sent].chatType == pair[2] and lastTest().channel == pair[2], "probe group: " .. pair[1] .. " uses " .. pair[2])
            end
            check(#chat.sent == sentBefore + 3, "probe group: one message per command")
            chat.group = nil
            for _ = 1, 25 do
                SlashCmdList.HONORLOG("probe guild")
                mock.flushTimers()
            end
            check(#HonorLogDB.probe.messaging == 20, "probe: at most 20 message tests are kept")
            at = #printed
            SlashCmdList.HONORLOG("probe status")
            check(said("message tests: 20", at), "probe status counts the message tests")
            mock.deferTimers = false
        end

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
    check(HonorLogDB.dbVersion == 3 and HonorLogCharDB.dbVersion == 3, "dbVersion 3 after migration (1 to 2 to 3)")
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
        check(hordeArmor.known == true and hordeArmor.x == 37.0 and hordeArmor.name == "Lady Palanseer", "GetVendorList: the Horde armor vendor, with a position")
        -- a row with no coordinates (none is left in the table, so one is blanked for the check)
        local palanseer
        for _, v in ipairs(HL.VENDORS) do if v.npc == 12792 then palanseer = v end end
        local px, py = palanseer.x, palanseer.y
        palanseer.x, palanseer.y = nil, nil
        for _, v in ipairs(HL:GetVendorList()) do if v.kind == "armor" then hordeArmor = v end end
        check(hordeArmor.known == false and hordeArmor.name == "Lady Palanseer", "GetVendorList: a vendor without a position is not known")
        palanseer.x, palanseer.y = px, py
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
            w:honorLogSetTitle("Title")
            check(w:honorLogGetTitle() == "Title", label .. "SetTitleText")
            if present then check(w.__title == "Title", label .. "the template's SetTitle is used") end
            w:honorLogSetPortrait(4242)
            check(w.honorLogPortrait == 4242, label .. "SetPortraitTexture")
            if present then check(w.__portrait == 4242, label .. "the template's SetPortraitToAsset is used") end
            check(type(w.honorLogContent) == "table" and type(w.honorLogClose) == "table", label .. "window has Content and CloseButton")
            local topLeft, bottomRight
            for _, pt in ipairs(w.honorLogContent.__points) do
                if pt[1] == "TOPLEFT" then topLeft = pt elseif pt[1] == "BOTTOMRIGHT" then bottomRight = pt end
            end
            check(topLeft and topLeft[4] == 6 and topLeft[5] == -24 and bottomRight and bottomRight[4] == -6 and bottomRight[5] == 6,
                label .. "Content is inset 6 left, right and bottom and 24 from the top")
            w:Show()
            local click = w.honorLogClose.__scripts.OnClick
            check(present or click, label .. "the close button closes the window on the plain path")
            if click then click(w.honorLogClose) end
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
            HL.Window:RegisterScreen({ key = "probe", title = "Probe", order = 5, create = function(parent)
                local f = CreateFrame("Frame", nil, parent)
                function f:Refresh() probeRefreshes = probeRefreshes + 1 end
                return f
            end })
        end
        registerProbe()
        check(#Window.screens == 6 and Window.screens[1].key == "overview" and Window.screens[2].key == "rank" and Window.screens[3].key == "gear" and Window.screens[4].key == "battlegrounds" and Window.screens[5].key == "quests" and Window.screens[6].key == "probe", "window: screens are kept in order")
        check(_G.HonorLogWindow == nil and not Window:IsShown(), "window: still nothing before the first open")
        check(HonorLogDB.settings.windowScale == 1 and HonorLogDB.settings.windowTab == "overview" and HonorLogDB.settings.windowRankTarget == 0, "window: the new settings have defaults")

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
            check(hollowWindow.honorLogChrome == false and hollowWindow.honorLogContent ~= nil and hollowWindow.honorLogClose ~= nil, "kit: hollow window templates fall back to the plain window")
            hollowWindow:honorLogSetTitle("T")
            check(hollowWindow:honorLogGetTitle() == "T", "kit: the plain window still takes a title")
            mock.hollowTemplates = {}
            check(Kit:Inset(holder).honorLogTemplate == "InsetFrameTemplate", "kit: with its regions the inset template takes")
            -- The window's content has its own ground, and the title bar texts sit on the drag strip.
            local win = Kit:Window("HonorLogGroundTestWindow", 300, 200)
            check(win.honorLogContent.honorLogBg ~= nil and win.honorLogDrag ~= nil, "kit: the content has a background and the window a drag strip")
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
        local pickerCalls, tabCalls = 0, 0
        local realPicker, realSwitch = HL.ShowGoalPicker, HL.SwitchTab
        HL.ShowGoalPicker = function() pickerCalls = pickerCalls + 1 end
        HL.SwitchTab = function() tabCalls = tabCalls + 1 end
        HL.GetAllGoalsProgress = function() return {} end
        ov:Refresh()
        check(goalPart.none:IsShown() and goalPart.none:GetText() == "No goals yet" and goalPart.add:IsShown() and not goalPart.view:IsShown() and not goalPart.icon:IsShown(), "overview: no goals")
        check(goalPart.add:GetText() == "Add a goal", "overview: the add button")
        local realOpen, openCalls = HL.GearScreen.Open, {}
        HL.GearScreen.Open = function(_, mode, id) openCalls[#openCalls + 1] = { mode, id } end
        goalPart.add.__scripts.OnClick(goalPart.add)
        check(#openCalls == 1 and openCalls[1][1] == "vendors" and openCalls[1][2] == nil and pickerCalls == 0, "overview: Add a goal opens the vendor browser, not the old picker")
        goalPart.card.__scripts.OnClick(goalPart.card)
        check(#openCalls == 1, "overview: the next-goal card does nothing while there is no goal")
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
        goalPart.card.__scripts.OnClick(goalPart.card)
        check(#openCalls == 2 and openCalls[2][1] == "goals" and openCalls[2][2] == vendorItem, "overview: a click on the next-goal card opens that goal on the Gear goals screen")
        goalPart.icon.__scripts.OnClick(goalPart.icon)
        check(#openCalls == 2, "overview: the goal's item icon keeps its own click")
        goalPart.view.__scripts.OnClick(goalPart.view)
        check(#openCalls == 3 and openCalls[3][1] == "goals" and openCalls[3][2] == vendorItem and tabCalls == 0,
            "overview: View goal opens that goal on the Gear goals screen, not the small frame's panel")
        HL.GearScreen.Open = realOpen
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

        -- ═══ Moments: the click-everything pass over the three cards (called from the integration pass) ═══
        ;(function()
            function mock.momentsPass(label)
                local M = HL.Moments
                for kind in pairs(M.states) do M:Close(kind) M.states[kind] = nil end -- rebuilt under this pass's templates
                local first = #mock.frames + 1
                M:Show("report", { bgType = "AB", result = "win", duration = 800, honor = 400, marks = 3, rankPoints = 25, rankState = "earned", kb = 6, hk = 9, timestamp = time(),
                    rep = { faction = 509, gained = 200 } })
                M:Show("rankUp", { rank = 3, info = HL.Rank:GetInfo() })
                M:Show("honorCap", { current = 23000, cap = 25000 })
                local n = 0
                local function inCard(f)
                    local hops = 0
                    while f and hops < 40 do
                        if f.honorLogState then return true end
                        f, hops = f.__parent, hops + 1
                    end
                    return false
                end
                local list = {}
                for i = first, #mock.frames do
                    if inCard(mock.frames[i]) then list[#list + 1] = mock.frames[i] end
                end
                for _, f in ipairs(list) do
                    if f.__scripts.OnEnter then f.__scripts.OnEnter(f, false) n = n + 1 end
                    if f.__scripts.OnLeave then f.__scripts.OnLeave(f) end
                end
                local errorsBefore = #mock.handledErrors
                for _, f in ipairs(list) do
                    if f.__scripts.OnClick then
                        f.__scripts.OnClick(f, "LeftButton") n = n + 1
                        for kind in pairs(M.states) do
                            if not M.states[kind].card:IsShown() then
                                M:Show(kind, M.states[kind].data) -- a click that closed the card: show it again for the next ones
                            end
                        end
                    end
                end
                check(n > 15, label .. "moments: the integration pass touched " .. n .. " controls on the three cards")
                check(#mock.handledErrors == errorsBefore, label .. "moments: clicking every control raised nothing: " .. tostring(mock.handledErrors[errorsBefore + 1]))
                for kind in pairs(M.states) do M:Close(kind) end
                Window:Hide()
            end
        end)()

        -- ── Integration: every control, twice ───────────────────────────────────────
        char.history = games
        local function integration(label)
            -- goals to click on: two to plan and one bought; the clicks may remove them, so they are a set of their own
            -- (the small frame's old goals panel needs templates the "nothing exists" pass takes away, and a goal
            -- change would refresh it: only the window hears about the change here)
            local savedGoals, realUpdated = char.goals, HL.OnDataUpdated
            HL.OnDataUpdated = function() Window:OnDataChanged() end
            char.goals = { items = {}, completed = {}, settings = savedGoals.settings }
            for _, id in ipairs({ 272738, 272787, 20041 }) do HL:AddGoal(id) end
            HL:CompleteGoal(20041)
            Window:Show("rank")
            Window:Show("gear")
            HL.GearScreen:Open("vendors")
            HL.GearScreen:Open("goals")
            Window:Show("battlegrounds")
            Window:Show("quests")
            Window:Show("overview")
            local S3 = HL.db.settings
            local savedBg = { bg = S3.windowBattleground, result = S3.windowResult, view = S3.viewMode }
            local n, gearClicks, bgClicks, questClicks = 0, 0, 0, 0
            -- Only what belongs to the window: a click on "Show on map" or a goal row reaches into the map pin and the
            -- model, which have their own tests; the pass is about the controls raising nothing.
            local function inWindow(f)
                local hops = 0
                while f and hops < 40 do
                    if f == Window.frame then return true end
                    f, hops = f.__parent, hops + 1
                end
                return false
            end
            local list = {}
            for i = framesBefore, #mock.frames do
                if inWindow(mock.frames[i]) then list[#list + 1] = mock.frames[i] end
            end
            for _, f in ipairs(list) do
                if f.__scripts.OnEnter then f.__scripts.OnEnter(f); n = n + 1 end
                if f.__scripts.OnLeave then f.__scripts.OnLeave(f) end
                if f.__scripts.OnClick then
                    f.__scripts.OnClick(f, "LeftButton"); n = n + 1
                    if Window.frames.gear then
                        local hops, p = 0, f
                        while p and hops < 40 do
                            if p == Window.frames.gear then gearClicks = gearClicks + 1 break end
                            p, hops = p.__parent, hops + 1
                        end
                    end
                    if Window.frames.battlegrounds then
                        local hops, p = 0, f
                        while p and hops < 40 do
                            if p == Window.frames.battlegrounds then bgClicks = bgClicks + 1 break end
                            p, hops = p.__parent, hops + 1
                        end
                    end
                    if Window.frames.quests then
                        local hops, p = 0, f
                        while p and hops < 40 do
                            if p == Window.frames.quests then questClicks = questClicks + 1 break end
                            p, hops = p.__parent, hops + 1
                        end
                    end
                    if not Window:IsShown() then Window:Show() end -- the close button closed it
                end
            end
            check(n > 20, label .. "integration clicked " .. n .. " controls")
            check(gearClicks > 25, label .. "integration clicked " .. gearClicks .. " controls on the Gear goals screen")
            check(bgClicks > 15, label .. "integration clicked " .. bgClicks .. " controls on the Battlegrounds screen")
            check(questClicks > 8, label .. "integration clicked " .. questClicks .. " controls on the Quests screen")
            mock.momentsPass(label)
            S3.windowBattleground, S3.windowResult, S3.viewMode = savedBg.bg, savedBg.result, savedBg.view
            char.goals, HL.OnDataUpdated = savedGoals, realUpdated
            HL.GearScreen.mode = "goals"
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

        -- What the first in-game look found (2026-11-20): the window code had put its own GetTitleText on the
        -- PortraitFrame, Blizzard's SetTitle called it, and the window never opened. So: nothing un-prefixed
        -- goes on a frame that came from a Blizzard template.
        do
            local function foreign(frame, allowed)
                local bad = {}
                for k in pairs(frame) do
                    if type(k) == "string" and not k:find("^__") and not k:find("^honorLog") and not (allowed and allowed[k]) then bad[#bad + 1] = k end
                end
                table.sort(bad)
                return table.concat(bad, ",")
            end
            local Kit = HL.Kit
            local holder = CreateFrame("Frame", nil, UIParent)
            local blizzard = { CloseButton = true, GetTitleText = true, SetTitle = true, SetPortraitToAsset = true }
            local tw = Kit:Window("HonorLogKeyTestWindow", 300, 200)
            check(tw.honorLogChrome == "PortraitFrameTemplate" and foreign(tw, blizzard) == "", "kit: the window adds only honorLog names to the template frame: " .. foreign(tw, blizzard))
            tw:honorLogSetTitle("Named")
            check(tw.__title == "Named" and tw:GetTitleText():GetText() == "Named" and tw:honorLogGetTitle() == "Named", "kit: Blizzard's own SetTitle and GetTitleText still work on the window")
            check(foreign(Kit:Inset(holder)) == "" and foreign(Kit:Button(holder, "B", "red")) == "", "kit: insets and buttons add only honorLog names")
            local tabset = Kit:Tabs(tw)
            check(foreign(tabset:Add("a", "A")) == "", "kit: tabs add only honorLog names")
            check(foreign(Kit:Tile(holder).inset) == "", "kit: a tile keeps its fields off the inset")
            -- A template whose SetTitle raises still gets a title, drawn by the kit.
            mock.titleRaises = true
            local tr = Kit:Window("HonorLogRaisingTitleWindow", 300, 200)
            check(pcall(tr.honorLogSetTitle, tr, "Fallback") and tr:honorLogGetTitle() == "Fallback", "kit: a raising SetTitle falls back to the kit's own title text")
            mock.titleRaises = false

            -- A build that fails half way leaves nothing behind, says so once, and the next try works.
            Window:Hide()
            Window.frame, Window.frames, Window.tabs, Window.current, Window.failed, _G.HonorLogWindow = nil, {}, nil, nil, nil, nil
            local realTabs = Kit.Tabs
            Kit.Tabs = function() error("tabs: forced failure") end
            local handled, at = #mock.handledErrors, #printed
            check(pcall(Window.Show, Window) and Window.frame == nil and Window.tabs == nil and not Window:IsShown(), "window: a failed build leaves nothing half made")
            check(#mock.handledErrors == handled + 1 and table.concat(printed, "\n", at + 1):find("could not be built", 1, true), "window: the failure is reported and said in chat")
            at = #printed
            check(pcall(Window.Toggle, Window) and Window.frame == nil and not table.concat(printed, "\n", at + 1):find("could not be built", 1, true), "window: a second failure does not repeat the chat line")
            Kit.Tabs = realTabs
            Window:Show("overview")
            check(Window.frame ~= nil and Window.tabs ~= nil and Window:IsShown(), "window: the next try builds it")
            mock.handledErrors[#mock.handledErrors] = nil
            mock.handledErrors[#mock.handledErrors] = nil
        end

        -- What the first screenshot showed (2026-11-21): the ring fell back to the plain icon although
        -- Blizzard's own tab uses that art, a day without games showed its 0 in warning orange, and the
        -- left pane had a large empty stretch.
        do
            local Kit = HL.Kit
            -- An atlas the client has but GetAtlasInfo does not report is found by setting it and reading it back.
            mock.atlases["Blind-Test-Atlas"] = true
            mock.atlasInfoBlind["Blind-Test-Atlas"] = true
            check(C_Texture.GetAtlasInfo("Blind-Test-Atlas") == nil and Kit:HasAtlas("Blind-Test-Atlas") == true, "kit: an atlas GetAtlasInfo does not report is still found")
            check(Kit:HasAtlas("No-Such-Atlas") == false and Kit:HasAtlas(nil) == false, "kit: a missing atlas is missing both ways")
            mock.atlases["Blind-Test-Atlas"], mock.atlasInfoBlind["Blind-Test-Atlas"] = nil, nil
            -- The ring takes either name of its art.
            local holder = CreateFrame("Frame", nil, UIParent)
            mock.atlases["pvpqueue-sidebar-honorbar-background"] = true
            check(Kit:Ring(holder, 150).honorLogFull == true, "kit: the ring is drawn with the older ring art when only that exists")
            mock.atlases["pvpqueue-sidebar-honorbar-background"] = nil
            mock.atlases["UI-Character-Info-Honor-Bar"], mock.atlasInfoBlind["UI-Character-Info-Honor-Bar"] = true, true
            check(Kit:Ring(holder, 150).honorLogFull == true, "kit: the ring is drawn when its art is only found by reading it back")
            mock.atlases["UI-Character-Info-Honor-Bar"], mock.atlasInfoBlind["UI-Character-Info-Honor-Bar"] = nil, nil
            check(Kit:Ring(holder, 150).honorLogFull == false, "kit: without ring art the plain version is drawn")

            -- No rank, no games: a white 0, and the next rank's unlocks as icons where the gate note would be.
            local saveRankLevel, saveEarned, saveHistory, saveLevel = mock.rank.level, mock.rank.earned, HL.db.char.history, mock.level
            mock.rank.level, mock.rank.earned, HL.db.char.history, mock.level = 0, 0, {}, 60
            Window:Show("overview")
            Window:RefreshCurrent()
            local parts = Window.frames.overview.honorLogParts
            local white = Kit.COLORS.white
            local c = parts.tiles[3].value.__textColor
            check(parts.tiles[3].value:GetText() == "0" and c[1] == white[1] and c[2] == white[2] and c[3] == white[3], "overview: a day without games shows a plain white 0 for rank points")
            local expectRank, expectItems
            for n = 1, 14 do
                local list = HL:GetRankUnlocks(n)
                if #list > 0 then expectRank, expectItems = n, list break end
            end
            local left = parts.left
            check(expectRank ~= nil and left.unlockRank == expectRank and left.unlockShown == math.min(#expectItems, 5)
                and left.unlockLabel:IsShown() and left.unlockLabel:GetText() == "Rank " .. expectRank .. " unlocks", "overview: the next rank's unlocks are named: " .. tostring(left.unlockLabel:GetText()))
            check(left.unlockIcons[1]:IsShown() and left.unlockIcons[1].honorLogItemID == expectItems[1] and left.unlockIcons[5]:IsShown() == (#expectItems >= 5),
                "overview: the unlocks are item icons")
            local _, _, _, _, yNoGate = left.unlockLabel:GetPoint(1)
            mock.level = 35
            mock.rank.level, mock.rank.earned = 3, 0
            Window:RefreshCurrent()
            local _, _, _, _, yGate = left.unlockLabel:GetPoint(1)
            check(left.gate:IsShown() and yGate < yNoGate, "overview: with the gate note showing the unlocks sit under it")
            mock.rank.level, mock.rank.earned, HL.db.char.history, mock.level = saveRankLevel, saveEarned, saveHistory, saveLevel
            Window:RefreshCurrent()
        end

        -- The UI audit: what the client has, asked of the client.
        do
            mock.missingTemplates = { InsetFrameTemplate = true }
            mock.atlases["UI-Character-Info-General-BG"] = true
            local at = #printed
            SlashCmdList.HONORLOG("probe ui")
            mock.missingTemplates = {}
            mock.atlases["UI-Character-Info-General-BG"] = nil
            local ui = HonorLogDB.probe.ui
            check(type(ui) == "table" and ui.atlases["UI-Character-Info-General-BG"].info == true and ui.atlases["UI-Character-Info-General-BG"].readBack == true
                and ui.atlases["common-framedivider"].info == false and ui.atlases["common-framedivider"].readBack == false, "probe ui: atlases are recorded both ways")
            check(ui.templates.PortraitFrameTemplate.ok == true and ui.templates.PortraitFrameTemplate.regions >= 1
                and ui.templates.InsetFrameTemplate.ok == false and ui.templates.InsetFrameTemplate.error:find("Couldn't find", 1, true), "probe ui: templates are tried, a missing one keeps its error")
            local methods = table.concat(ui.templates.PortraitFrameTemplate.methods, ",")
            check(methods:find("GetTitleText", 1, true) and methods:find("SetTitle", 1, true) and table.concat(ui.templates.PortraitFrameTemplate.parts, ","):find("CloseButton", 1, true),
                "probe ui: a template's own parts and methods are listed: " .. methods)
            check(ui.templates["Cooldown (no template)"].ok == true and type(ui.fonts) == "table" and ui.globals.UISpecialFrames == "table" and ui.globals.SetItemButtonQuality ~= nil,
                "probe ui: frame kinds without a template, fonts and helpers are recorded")
            check(type(ui.names) == "table" and ui.names.UnitName ~= nil and ui.names.GetRealmName ~= nil and type(ui.screen) == "table" and type(ui.kit) == "table" and type(ui.window) == "table",
                "probe ui: names, screen, the kit's own ring check and the window are recorded")
            check(table.concat(printed, "\n", at + 1):find("UI audit saved", 1, true), "probe ui: says it is saved")
        end

        -- Whole names (seen in game 2026-11-21: UnitName("player") gave "Liquid", "Elements" and an empty realm).
        do
            local Util = HL.Util
            check(Util.unitName("player") == "Tester" and HL:GetCharacterKey() == "Tester-TestRealm", "names: a one-word name and a named realm, as before")
            mock.twoWordNames, mock.playerName, mock.realm = true, "Liquid Elements", ""
            local first, last = UnitName("player")
            check(first == "Liquid" and last == "Elements" and Util.unitName("player") == "Liquid Elements", "names: two values from UnitName make one whole name")
            local realGet = GetUnitName
            GetUnitName = nil
            check(Util.unitName("player") == "Liquid Elements", "names: joined here when the client has no GetUnitName")
            GetUnitName = realGet
            check(HL:GetCharacterKey() == "Liquid Elements", "names: an empty realm is left out of the character key")
            Window:Show("overview")
            Window:UpdateTitleBar()
            check(Window.leftText:GetText():find("^Liquid Elements \194\183 Level"), "window: the title bar shows the whole name: " .. tostring(Window.leftText:GetText()))
            mock.units.npc = { name = "Brave Stonehide" }
            check(Util.unitName("npc") == "Brave Stonehide" and Util.unitName("nobody") == nil, "names: other units get their whole name, a missing unit nil")
            mock.units.npc = nil
            mock.twoWordNames, mock.playerName, mock.realm = false, nil, nil
            Window:UpdateTitleBar()

            -- No rank yet: the ring shows the faction emblem without an empty number badge.
            mock.atlasMode = "all"
            local ring = HL.Kit:Ring(CreateFrame("Frame", nil, UIParent), 150)
            ring:SetRank(0, "Horde")
            check(ring.honorLogFull == true and not ring.Badge:IsShown(), "kit: no badge on the ring at rank 0")
            ring:SetRank(3, "Horde")
            check(ring.Badge:IsShown() and ring.Badge.Label:GetText() == "3", "kit: the badge shows from rank 1 on")
            mock.atlasMode = "default"
        end

        -- ═══ Rank plan: the model, the chart, the table, the planner and the shared pane ═══
        -- (a function of its own: the enclosing function is near Lua's limit of 200 locals)
        ;(function()
            local Rank, Kit = HL.Rank, HL.Kit
            local realPace, realUnlocks, realPlan = Rank.GetPace, HL.GetRankUnlocks, Rank.PlanToRank
            local saveProbe = HonorLogDB.probe
            local saveWeeks, saveHistory, saveTarget = char.rankWeeks, char.history, HonorLogDB.settings.windowRankTarget
            local saveLevel, saveSeasonMax = mock.level, mock.rankWindow.seasonMax
            mock.rank.level, mock.rank.earned, mock.rank.threshold = 3, 120, 1050
            mock.level, mock.faction = 60, "Alliance"
            mock.rankWindow.cap, mock.rankWindow.prevCap, mock.rankWindow.week, mock.rankWindow.noData = 5, 3, 2, false
            char.history = games
            char.rankWeeks = { [1] = { startTotal = 0, endTotal = 900, games = 3, capRank = 3 } }
            local function fakePace(ppg, gpd, noPoints)
                return { pointsPerGame = ppg, gamesPerDay = gpd, noPoints = noPoints or false, estimated = false, measuredGames = 0,
                    pointsPerWin = ppg, pointsPerLoss = ppg, winRate = 0.5 }
            end
            local info = Rank:GetInfo()

            -- ── GetSeasonSeries ──
            local s = Rank:GetSeasonSeries(info, fakePace(100, 2))
            check(#s.weeks == 10 and s.maxTotal == Rank:TotalForRank(14) and s.currentWeek == 2 and s.currentTotal == info.totalPoints, "series: weeks, maximum, current week and total")
            check(#s.actual == 2 and s.actual[1].week == 1 and s.actual[1].total == 900 and s.actual[2].week == 2 and s.actual[2].total == info.totalPoints,
                "series: actual is the week log's end totals, then the running total of the current week")
            check(s.gateLevel == nil, "series: no gate level when nothing blocks")
            check(#s.projected == 9 and s.projected[1].week == 2 and s.projected[9].week == 10, "series: the projection runs from the current week on")
            local perWeek, ok = 100 * 2 * 7, true
            for i, p in ipairs(s.projected) do
                if p.total > s.weeks[p.week].capTotal or (s.projected[i - 1] and p.total < s.projected[i - 1].total) then ok = false end
            end
            check(ok, "series: the projection never passes a week's cap and never falls")
            check(s.projected[2].total == math.min(s.projected[1].total + perWeek, s.weeks[3].capTotal), "series: a later week adds a week at the pace, up to its cap")
            local fast = Rank:GetSeasonSeries(info, fakePace(100000, 50))
            check(fast.projected[1].total == fast.weeks[2].capTotal and fast.projected[5].total == fast.weeks[6].capTotal, "series: a very fast pace sits on the cap")
            check(#Rank:GetSeasonSeries(info, fakePace(0, 2, true)).projected == 0 and #Rank:GetSeasonSeries(info, fakePace(100, 0)).projected == 0
                and #Rank:GetSeasonSeries(info, fakePace(0, 3)).projected == 0, "series: no projection when the pace is unknown or gives no points")
            mock.level = 35
            local gated = Rank:GetSeasonSeries(Rank:GetInfo(), fakePace(100, 2))
            check(gated.gateLevel == 40 and #gated.projected == 9, "series: a blocking gate names its level")
            local flat = true
            for _, p in ipairs(gated.projected) do if p.total ~= gated.currentTotal then flat = false end end
            check(flat, "series: under a blocking gate the projection stays flat")
            mock.level = 60
            mock.rankWindow.noData = true
            local none = Rank:GetSeasonSeries()
            check(#none.weeks == 0 and #none.actual == 0 and #none.projected == 0 and none.maxTotal == 0 and none.currentWeek == nil and none.gateLevel == nil, "series: empty tables without rank data")
            mock.rankWindow.noData = false

            -- ── GetWeeklyQuest ──
            HonorLogDB.probe = { quests = {} }
            local q = Rank:GetWeeklyQuest()
            check(q.week == 2 and q.questID == 96913 and q.title == "Field of Honor: Week 2" and q.measured == nil and q.done == false, "quest: week 2, fallback title, nothing measured")
            mock.questTitles[96913] = "Field of Honor: Week 2 (client)"
            check(Rank:GetWeeklyQuest().title == "Field of Honor: Week 2 (client)", "quest: the client's title wins")
            mock.questTitles[96913] = nil
            HonorLogDB.probe.quests[96915] = { last = { rank = 0, t = 5 } }
            check(Rank:GetWeeklyQuest().measured == nil, "quest: a hand-in that gave 0 is not a measurement")
            HonorLogDB.probe.quests[96912] = { last = { rank = 75, t = 1 } }
            check(Rank:GetWeeklyQuest().measured == 75, "quest: a hand-in of another week's quest counts")
            HonorLogDB.probe.quests[96913] = { last = { rank = 90, t = 0 } }
            check(Rank:GetWeeklyQuest().measured == 90, "quest: this week's own hand-in wins")
            mock.questsDone[96913] = true
            check(Rank:GetWeeklyQuest().done == true, "quest: the completed flag")
            local realQL = _G.C_QuestLog
            _G.C_QuestLog = nil
            local noQL = Rank:GetWeeklyQuest()
            check(noQL.done == nil and noQL.title == "Field of Honor: Week 2", "quest: no quest API leaves done empty and the title to the fallback")
            _G.C_QuestLog = realQL
            mock.questsDone[96913] = nil
            mock.rankWindow.week = 11
            check(Rank:GetWeeklyQuest() == nil, "quest: nil outside weeks 1 to 10")
            mock.rankWindow.week = 2

            -- ── The screen ──
            mock.runShowScripts = true
            Window:Show("rank")
            local rp = Window.frames.rank
            local parts = rp.honorLogParts
            check(rp and parts and Window.current == "rank" and HonorLogDB.settings.windowTab == "rank", "rank plan: built on its tab")
            Rank.GetPace = function() return fakePace(100, 2) end
            Window:RefreshCurrent()
            local chartPart = parts.chart
            local chart = chartPart.chart
            local function shownLines()
                local out = {}
                for _, l in ipairs(chart.honorLogLines) do if l:IsShown() then out[#out + 1] = l end end
                return out
            end
            local function colorIs(f, rgb) local c = f.__color return c and c[1] == rgb[1] and c[2] == rgb[2] and c[3] == rgb[3] end
            local CAP, RED, GREY = { 1, 0.82, 0 }, { 0.88, 0.28, 0.25 }, { 0.78, 0.76, 0.71 }
            local function count(rgb, thick)
                local n = 0
                for _, l in ipairs(shownLines()) do if colorIs(l, rgb) and l.__thickness == thick then n = n + 1 end end
                return n
            end
            local function labels()
                local out = {}
                for _, list in pairs(chart.honorLogLabels) do
                    for _, fs in ipairs(list) do if fs:IsShown() then out[#out + 1] = fs:GetText() end end
                end
                return out
            end
            local function hasLabel(text) for _, t in ipairs(labels()) do if t == text then return true end end return false end
            check(count(CAP, 2) == 19, "chart: the cap steps are drawn for every week (10 levels and 9 steps), got " .. count(CAP, 2))
            local levels = 0
            for _, l in ipairs(shownLines()) do if colorIs(l, CAP) and l.__start[4] == l.__end[4] then levels = levels + 1 end end
            check(levels == 10, "chart: ten level cap segments")
            check(count(RED, 3) == 1, "chart: one red segment from week 1 to the current week")
            local ring, inner = 0, 0
            for i = 1, chart.honorLogRectsUsed do
                local r = chart.honorLogRects[i]
                if r:IsShown() and r.__width == 12 then ring = ring + 1 end
                if r:IsShown() and r.__width == 8 and colorIs(r, RED) then inner = inner + 1 end
            end
            check(ring == 1 and inner == 1, "chart: a ringed dot at the current week")
            check(count(GREY, 2) > 5, "chart: the projection is drawn as dashes")
            check(count(Kit.COLORS.orange, 2) == 0 and not hasLabel("Rank points start at level 40"), "chart: no gate marker without a blocking gate")
            for _, t in ipairs({ "Week 1", "2", "10", "R8", "R12", "R14", "0" }) do check(hasLabel(t), "chart: label " .. t) end
            local whites = 0
            for _, list in pairs(chart.honorLogLabels) do
                for _, fs in ipairs(list) do
                    if fs:IsShown() and fs.__textColor and fs.__textColor[1] == 1 and fs.__textColor[2] == 1 and fs.__textColor[3] == 1 and fs:GetText() == "2" then whites = whites + 1 end
                end
            end
            check(whites == 1, "chart: the current week's label is white")
            check(not chartPart.none:IsShown(), "chart: no empty-state text with data")
            -- gate
            mock.level = 35
            Window:RefreshCurrent()
            check(count(Kit.COLORS.orange, 2) > 3 and hasLabel("Rank points start at level 40"), "chart: a blocking gate draws the orange marker and its words")
            mock.level = 60
            -- pooling
            Window:RefreshCurrent()
            local function pool() return #chart.honorLogLines + #chart.honorLogRects + (function() local n = 0 for _, l in pairs(chart.honorLogLabels) do n = n + #l end return n end)() end
            local before = pool()
            for _ = 1, 10 do Window:RefreshCurrent() end
            check(pool() == before, "chart: pooled pieces do not grow across ten refreshes (" .. before .. " -> " .. pool() .. ")")
            -- no data
            mock.rankWindow.noData = true
            Window:RefreshCurrent()
            check(#shownLines() == 0 and chartPart.none:IsShown() and chartPart.none:GetText() == "No rank data yet. Play a battleground to start your season.", "chart: without rank data only the words show")
            mock.rankWindow.noData = false
            -- no CreateLine
            mock.noCreateLine = true
            local plain = Kit:Chart(UIParent)
            check(plain:Line(0, 5, 40, 5, 2, 1, 1, 1, 1) == true and plain:Line(7, 0, 7, 30, 2, 1, 1, 1, 1) == true and plain:Line(0, 0, 10, 10, 2, 1, 1, 1, 1) == false,
                "chart: without CreateLine level and upright lines are boxes and slanted ones are skipped")
            check(#plain.honorLogLines == 0 and plain.honorLogRectsUsed == 2, "chart: the fallback makes boxes, not lines")
            local errs = #mock.handledErrors
            Window:RefreshCurrent()
            check(#mock.handledErrors == errs, "chart: the whole screen refreshes without CreateLine")
            mock.noCreateLine = false
            Window:RefreshCurrent()

            -- ── The rank table ──
            local rows = parts.rankTable.rows
            local tbl = Rank:GetRankTable(Rank:GetInfo(), fakePace(100, 2))
            check(rows.count == 14 and #tbl == 14, "table: fourteen rows")
            local GREYC, GOLD = Kit.COLORS.grey, Kit.COLORS.gold
            local function textColor(fs) local c = fs.__textColor return c and { c[1], c[2], c[3] } end
            local function same(c, rgb) return c and c[1] == rgb[1] and c[2] == rgb[2] and c[3] == rgb[3] end
            check(rows.frames[1].cell.text:GetText() == "Reached" and same(textColor(rows.frames[1].cell.text), GREYC) and same(textColor(rows.frames[1].title), GREYC),
                "table: a reached rank reads Reached in grey")
            check(rows.frames[3].cell.text:GetText() == "You are here" and same(textColor(rows.frames[3].cell.text), GOLD) and rows.frames[3].wash:IsShown()
                and not rows.frames[1].wash:IsShown() and not rows.frames[4].wash:IsShown(), "table: the current rank says so in gold, on a red wash")
            check(rows.frames[4].cell.text:GetText() == tbl[4].when and same(textColor(rows.frames[4].cell.text), GREYC) and same(textColor(rows.frames[4].title), Kit.COLORS.white),
                "table: a rank ahead shows its date in grey, the rank in white: " .. tostring(rows.frames[4].cell.text:GetText()))
            for n = 1, 14 do
                local f, items = rows.frames[n], HL:GetRankUnlocks(n)
                local shown = 0
                for i = 1, 3 do if f.icons[i]:IsShown() then shown = shown + 1 end end
                check(f.badge.number:GetText() == tostring(n) and f.title:GetText() == Rank:TitleForRank(n) and f.points:GetText() == commas(Rank:TotalForRank(n)), "table: row " .. n .. " badge, title and points")
                check(shown == math.min(3, #items) and (f.icons[1]:IsShown() == (#items > 0)) and (#items == 0 or f.icons[1].honorLogItemID == items[1]), "table: row " .. n .. " icons")
                check((f.more:GetText() or "") == (#items > 3 and ("+" .. (#items - 3)) or ""), "table: row " .. n .. " +N")
            end
            HL.GetRankUnlocks = function(self, n)
                if n == 9 then return { vendorItem, vendorItem, vendorItem, vendorItem, vendorItem } end
                return realUnlocks(self, n)
            end
            Window:RefreshCurrent()
            check(rows.frames[9].icons[3]:IsShown() and rows.frames[9].more:GetText() == "+2" and rows.frames[9].more:IsShown(), "table: more than three unlocks show three icons and +2")
            HL.GetRankUnlocks = realUnlocks
            mock.level = 35
            Window:RefreshCurrent()
            check(rows.frames[4].cell.text:GetText() == "after level 40" and same(textColor(rows.frames[4].cell.text), Kit.COLORS.orange), "table: a level-limited rank is orange")
            Rank.GetPace = function() return fakePace(0, 2, true) end
            mock.level = 60
            Window:RefreshCurrent()
            check(same(textColor(rows.frames[4].cell.text), Kit.COLORS.orange) and rows.frames[4].cell.text:GetText():find("no estimate", 1, true), "table: no points is orange too")
            Rank.GetPace = function() return fakePace(100, 1) end
            Window:RefreshCurrent()
            check(rows.frames[14].cell.text:GetText() ~= "ahead" and rows.frames[14].cell.text:GetText() ~= "", "table: a rank with no date never shows the model's word ahead")
            local cell = rows.frames[4].cell
            cell.__scripts.OnEnter(cell)
            check(mock.tip.shown, "table: the earliest cell has a tooltip")
            cell.__scripts.OnLeave(cell)
            Rank.GetPace = function() return fakePace(100, 2) end

            -- ── The planner ──
            local plan = parts.plan
            local function expectTargets(rank, seasonMax)
                local top, out, seen = math.min(seasonMax, 14), {}, {}
                local cands = {}
                for n = rank + 1, top do if #realUnlocks(HL, n) > 0 then cands[#cands + 1] = n break end end
                for _, n in ipairs({ 8, 11, 14 }) do cands[#cands + 1] = n end
                for _, n in ipairs(cands) do if n > rank and n <= top and not seen[n] then seen[n] = true out[#out + 1] = n end end
                table.sort(out)
                return out
            end
            local function offeredNow()
                local out = {}
                for i, b in ipairs(plan.buttons) do if b:IsShown() then out[#out + 1] = tonumber(b:GetText():match("%d+")) end end
                return out
            end
            for _, case in ipairs({ { 0, 14 }, { 7, 14 }, { 14, 14 }, { 7, 10 } }) do
                mock.rank.level, mock.rank.earned, mock.rankWindow.seasonMax = case[1], 0, case[2]
                mock.rankWindow.cap = math.max(3, case[1])
                Window:RefreshCurrent()
                local want, got = expectTargets(case[1], case[2]), offeredNow()
                check(table.concat(got, ",") == table.concat(want, ","), "planner: rank " .. case[1] .. " (season top " .. case[2] .. ") offers " .. table.concat(want, ",") .. ", got " .. table.concat(got, ","))
            end
            mock.rank.level, mock.rank.earned, mock.rankWindow.seasonMax = 14, 0, 14
            Window:RefreshCurrent()
            check(plan.done:IsShown() and plan.done:GetText() == "Top rank reached." and not plan.title:IsShown() and not plan.holdBack:IsShown(), "planner: every rank reached")
            mock.rank.level, mock.rank.earned, mock.rankWindow.cap = 3, 120, 5
            -- saved target, its fallback
            Window:RefreshCurrent()
            local offered = offeredNow()
            check(#offered >= 3 and offered[#offered] == 14, "planner: a rank 3 character is offered several targets")
            HonorLogDB.settings.windowRankTarget = 11
            Window:RefreshCurrent()
            check(plan.target == 11 and plan.title:GetText() == "Rank 11 " .. Rank:TitleForRank(11), "planner: the saved target is planned: " .. tostring(plan.title:GetText()))
            local b14
            for i, b in ipairs(plan.buttons) do if b:IsShown() and plan.targets[i] == 14 then b14 = b end end
            b14.__scripts.OnClick(b14)
            check(HonorLogDB.settings.windowRankTarget == 14 and plan.target == 14 and plan.title:GetText() == "Rank 14 " .. Rank:TitleForRank(14), "planner: a button chooses the target and saves it")
            check(plan.underline:IsShown(), "planner: the chosen target is underlined")
            HonorLogDB.settings.windowRankTarget = 2
            Window:RefreshCurrent()
            check(plan.target == offered[1] and HonorLogDB.settings.windowRankTarget == 2, "planner: a target no longer offered falls back to the first button")
            HonorLogDB.settings.windowRankTarget = 8
            Window:RefreshCurrent()
            local p8 = Rank:PlanToRank(8, Rank:GetInfo(), fakePace(100, 2))
            check(plan.pairs[1].value:GetText() == commas(p8.pointsNeeded) and plan.pairs[2].value:GetText() == Rank.PlanGames(p8), "planner: points to go and games at the pace")
            check(plan.pairs[3].value:GetText() == string.format("%s (week %d)", Rank.FormatDate(p8.earliestDateByCap), p8.earliestWeekByCap), "planner: the cap date with its week: " .. tostring(plan.pairs[3].value:GetText()))
            -- cap row says now when the cap already allows it
            HonorLogDB.settings.windowRankTarget = 5
            mock.rank.level = 2
            Window:RefreshCurrent()
            local firstTarget = plan.target
            local pn = Rank:PlanToRank(firstTarget, Rank:GetInfo(), fakePace(100, 2))
            check((pn.earliestDateByCap <= time()) == (plan.pairs[3].value:GetText() == "now"), "planner: now when the cap allows it already")
            mock.rank.level = 3
            -- unlock icons
            HonorLogDB.settings.windowRankTarget = 14
            HL.GetRankUnlocks = function(self, n)
                if n == 14 then return { vendorItem, vendorItem, vendorItem, vendorItem, vendorItem, vendorItem } end
                return realUnlocks(self, n)
            end
            Window:RefreshCurrent()
            check(plan.unlockIcons[4]:IsShown() and plan.unlockIcons[4].honorLogItemID == vendorItem and plan.unlockMore:GetText() == "+2" and plan.unlockMore:IsShown(), "planner: four unlock icons and +2")
            HL.GetRankUnlocks = function(self, n) if n == 14 then return { vendorItem } end return realUnlocks(self, n) end
            Window:RefreshCurrent()
            check(plan.unlockIcons[1]:IsShown() and not plan.unlockIcons[2]:IsShown() and not plan.unlockMore:IsShown(), "planner: one unlock, one icon")
            HL.GetRankUnlocks = realUnlocks
            -- every limitedBy line
            HonorLogDB.settings.windowRankTarget = 8
            local function holdText(pace, level)
                mock.level = level or 60
                Rank.GetPace = function() return pace end
                Window:RefreshCurrent()
                mock.level = 60
                return plan.holdBack:GetText(), plan.pairs[2].value:GetText()
            end
            check(holdText(fakePace(100, 2), 35) == "Held back by level 40 first.", "planner: held back by level")
            check(holdText(fakePace(1000, 20)) == "Held back by the weekly cap.", "planner: held back by the cap")
            local t, g = holdText(fakePace(0, 2, true))
            check(t == "Your recent games gave no rank points." and g == "not measured yet", "planner: no points, games not measured")
            check(holdText(fakePace(100, 1)) == "Not reachable this season.", "planner: not reachable this season")
            local pt = holdText(fakePace(100, 4))
            local p4 = Rank:PlanToRank(8, Rank:GetInfo(), fakePace(100, 4))
            check(p4.limitedBy == "pace" and pt == "At your pace: " .. Rank.PlanWhen(p4) .. ".", "planner: at your pace: " .. tostring(pt))
            Rank.PlanToRank = function() return { target = 8, reached = true, limitedBy = "reached", pointsNeeded = 0, gamesNeeded = 0 } end
            Window:RefreshCurrent()
            check(plan.holdBack:GetText() == "", "planner: a reached plan has no held-back line")
            Rank.PlanToRank = realPlan
            Rank.GetPace = function() return fakePace(100, 2) end

            -- ── Rank points per game ──
            Rank.GetPace = realPace
            char.history = {
                game("WSG", "win", 300, 10, 0, 0, "zero"), game("WSG", "loss", 300, 10, 0, 0, "zero"), game("WSG", "loss", 300, 10, 0, 0, "zero"),
                game("AB", "win", 600, 450, 3, 100, "earned"),
            }
            mock.questsDone[96913], HonorLogDB.probe.quests = nil, {}
            Window:RefreshCurrent()
            local pg = parts.perGame
            local per = Rank:GetPointsPerResult()
            check(pg.rows.count == #per and #per == 2, "per game: one row per battleground with measured games")
            for i, e in ipairs(per) do
                local f = pg.rows.frames[i]
                check(f.name:GetText() == e.name and f.win:GetText() == (e.perWin and tostring(math.floor(e.perWin + 0.5)) or "-")
                    and f.loss:GetText() == (e.perLoss and tostring(math.floor(e.perLoss + 0.5)) or "-"), "per game: row " .. i .. " reads " .. tostring(f.name:GetText()))
            end
            local byName = {}
            for i, e in ipairs(per) do byName[e.bgType] = pg.rows.frames[i] end
            check(byName.AB.loss:GetText() == "-" and byName.AB.win:GetText() == "100" and same(textColor(byName.AB.name), Kit.COLORS.white), "per game: a missing measurement is a dash")
            check(byName.WSG.win:GetText() == "0" and byName.WSG.loss:GetText() == "0" and same(textColor(byName.WSG.name), Kit.COLORS.orange) and same(textColor(byName.WSG.win), Kit.COLORS.orange),
                "per game: a row of zeros is orange")
            local zero = Rank:GetZeroPointBattlegrounds()[1]
            check(zero and pg.zero:IsShown() and pg.zero:GetText() == Rank:ZeroPointText(zero) and same(textColor(pg.zero), Kit.COLORS.orange), "per game: the zero-point note in orange")
            check(pg.quest:GetText() == "Field of Honor: Week 2\nreward not measured yet" and same(textColor(pg.quest), GREYC), "per game: the quest with no measurement: " .. tostring(pg.quest:GetText()))
            mock.questsDone[96913] = true
            Window:RefreshCurrent()
            check(pg.quest:GetText() == "Field of Honor: Week 2\ndone this week" and same(textColor(pg.quest), GREYC), "per game: the quest done, not measured: " .. tostring(pg.quest:GetText()))
            mock.questsDone[96913] = nil
            HonorLogDB.probe.quests[96913] = { last = { rank = 90, t = 0 } }
            Window:RefreshCurrent()
            check(pg.quest:GetText() == "Field of Honor: Week 2\n+90 rank points (measured)" and same(textColor(pg.quest), Kit.COLORS.white), "per game: the measured quest: " .. tostring(pg.quest:GetText()))
            HonorLogDB.probe.quests[96913] = { last = { rank = 90, t = 0 } }
            mock.questsDone[96913] = true
            Window:RefreshCurrent()
            check(pg.quest:GetText() == "Field of Honor: Week 2\ndone this week, +90 rank points" and same(textColor(pg.quest), Kit.COLORS.white), "per game: the measured quest, done: " .. tostring(pg.quest:GetText()))
            mock.rankWindow.week = 11
            Window:RefreshCurrent()
            check(not pg.quest:IsShown() and pg.quest:GetText() == "", "per game: no quest line outside weeks 1 to 10")
            mock.rankWindow.week = 2
            char.history = {}
            Window:RefreshCurrent()
            check(pg.rows.count == 0 and pg.empty:IsShown() and not pg.zero:IsShown(), "per game: nothing measured")

            -- ── Shared pane, tabs, saved tab ──
            char.history = games
            Window:Show("overview")
            local ovLeft = Window.frames.overview.honorLogParts.left
            Window:Show("rank")
            local rkLeft = parts.left
            check(ovLeft ~= rkLeft and ovLeft.rank:GetText() == rkLeft.rank:GetText() and ovLeft.points:GetText() == rkLeft.points:GetText()
                and ovLeft.percent:GetText() == rkLeft.percent:GetText() and ovLeft.honorValue:GetText() == rkLeft.honorValue:GetText() and rkLeft.rank:GetText() == "Rank 3 Sergeant",
                "shared pane: the same texts on both screens")
            check(HL.RankPane.WIDTH == 264 and rkLeft.pane:GetWidth() == 264, "shared pane: 264 wide")
            check(Window.screens[2].key == "rank" and Window.screens[2].title == "Rank plan" and Window.screens[2].order == 2, "tabs: Rank plan is registered second")
            local tabs = Window.tabs.list
            local function tabText(b) return b.honorLogTemplate and b:GetText() or b.honorLogLabel:GetText() end
            check(tabs[1].honorLogKey == "overview" and tabs[2].honorLogKey == "rank" and tabText(tabs[2]) == "Rank plan", "tabs: Rank plan comes after Overview")
            HonorLogDB.settings.windowTab = "rank"
            Window:Hide()
            Window.frame, Window.frames, Window.tabs, Window.current, _G.HonorLogWindow = nil, {}, nil, nil, nil
            Window:Show()
            check(Window.current == "rank" and Window.frames.rank:IsShown(), "tabs: the saved tab restores the Rank plan screen")
            parts = Window.frames.rank.honorLogParts

            -- ── Hygiene ──
            local inRank = function(f)
                local hops = 0
                while f and hops < 40 do
                    if f == Window.frames.rank then return true end
                    f, hops = f.__parent, hops + 1
                end
                return false
            end
            local onUpdates, foreign, templated = 0, {}, 0
            for _, f in ipairs(mock.frames) do
                if f.__scripts.OnUpdate and (inRank(f) or f.__parent == Window.frame.honorLogContent) then onUpdates = onUpdates + 1 end
                if inRank(f) and f.__template then
                    templated = templated + 1
                    for k in pairs(f) do
                        if type(k) == "string" and not k:find("^__") and not k:find("^honorLog") then foreign[#foreign + 1] = k end
                    end
                end
            end
            check(onUpdates == 0, "rank plan: no OnUpdate anywhere (" .. onUpdates .. ")")
            check(templated > 5 and #foreign == 0, "rank plan: only honorLog names are added to template frames: " .. table.concat(foreign, ","))
            -- every client read gone or secret
            local errorsBefore2 = #mock.handledErrors
            local secret = mock.newSecret
            local realQuest = { t = C_QuestLog.GetTitleForQuestID, d = C_QuestLog.IsQuestFlaggedCompleted }
            local savedR = { info = C_MajorFactions.GetMajorFactionProgressionInfo, level = _G.UnitLevel, icon = C_Item.GetItemIconByID }
            C_QuestLog.GetTitleForQuestID, C_QuestLog.IsQuestFlaggedCompleted = function() return secret() end, function() return secret() end
            C_MajorFactions.GetMajorFactionProgressionInfo = function() return { renownLevel = secret(), renownReputationEarned = secret() } end
            _G.UnitLevel, C_Item.GetItemIconByID = function() return secret() end, function() return nil end
            Window:RefreshCurrent()
            C_MajorFactions.GetMajorFactionProgressionInfo = function() return nil end
            Window:RefreshCurrent()
            C_MajorFactions.GetMajorFactionProgressionInfo = savedR.info
            C_QuestLog.GetTitleForQuestID, C_QuestLog.IsQuestFlaggedCompleted = function() return secret() end, function() return secret() end
            Window:RefreshCurrent()
            check(#mock.handledErrors == errorsBefore2, "rank plan: nothing raises when every client read is nil or secret: " .. tostring(mock.handledErrors[errorsBefore2 + 1]))
            C_QuestLog.GetTitleForQuestID, C_QuestLog.IsQuestFlaggedCompleted = realQuest.t, realQuest.d
            _G.UnitLevel, C_Item.GetItemIconByID = savedR.level, savedR.icon

            -- put it back
            Rank.GetPace, Rank.PlanToRank, HL.GetRankUnlocks = realPace, realPlan, realUnlocks
            HonorLogDB.probe, char.rankWeeks, char.history, HonorLogDB.settings.windowRankTarget = saveProbe, saveWeeks, saveHistory, saveTarget
            mock.level, mock.rankWindow.seasonMax = saveLevel, saveSeasonMax
            mock.questsDone, mock.questTitles = {}, {}
            HonorLogDB.settings.windowTab = "overview"
            mock.rank.level, mock.rank.earned, mock.rank.threshold = 3, 120, 1050
            mock.rankWindow.cap, mock.rankWindow.prevCap, mock.rankWindow.week = 5, 3, 2
            Window:Hide()
        end)()

        -- ═══ Gear goals: the upgrade accessor, the kit's new pieces, the goals screen and the vendor browser ═══
        -- (a function of its own: the enclosing function is near Lua's limit of 200 locals)
        ;(function()
            local Kit, Rank = HL.Kit, HL.Rank
            local Gear, Vend = HL.GearScreen, HL.GearVendors
            local S = HonorLogDB.settings
            local BLUE, EPIC, REPGEAR, MOUNT = 272738, 272787, 20041, 18241
            local SEAL = HL.GearDB[EPIC].parts[2]
            local save = { goals = char.goals, goal = S.windowGoal, vendor = S.windowVendor, class = S.windowVendorClass, tab = S.windowTab,
                level = mock.level, history = char.history, honor = mock.currencies[1792].quantity, money = mock.money, bags = mock.bagContents,
                buyable = HL.GetBuyableNow, advice = HL.GetHonorCapAdvice, totals = HL.GetGoalsTotals, allGoals = HL.GetAllGoalsProgress,
                unlocks = HL.GetRankUnlocks, rankInfo = Rank.GetInfo, stock = HL.GetVendorStock, vendorFor = HL.GetVendorFor,
                showForItem = HL.ShowVendorForItem, showOnMap = HL.ShowVendorOnMap }
            local function textColor(fs) local c = fs.__textColor return c and { c[1], c[2], c[3] } end
            local function same(c, rgb) return c and c[1] == rgb[1] and c[2] == rgb[2] and c[3] == rgb[3] end
            local function click(f) f.__scripts.OnClick(f, "LeftButton") end
            local function tipText()
                local t = {}
                for _, l in ipairs(mock.tip.lines) do t[#t + 1] = l.text end
                return table.concat(t, "\n")
            end
            local function noErrors(label, fn)
                local before = #mock.handledErrors
                fn()
                check(#mock.handledErrors == before, label .. ": " .. tostring(mock.handledErrors[before + 1]))
            end
            mock.level, mock.faction = 60, "Alliance"
            mock.rank.level, mock.rank.earned, mock.rank.threshold = 3, 120, 1050
            mock.rankWindow.cap, mock.rankWindow.prevCap, mock.rankWindow.week, mock.rankWindow.noData = 5, 3, 2, false
            mock.currencies[1792].quantity, mock.money, mock.bagContents = 8200, 50000000, {}
            char.history = {}
            char.goals = { items = {}, completed = {}, settings = save.goals.settings }
            S.windowGoal, S.windowVendor, S.windowVendorClass = 0, "", "player"

            -- ── GetUpgradeFor ──
            local up = HL:GetUpgradeFor(BLUE)
            check(up and up.itemID == EPIC and up.sealID == SEAL and up.rank == HL.GearDB[EPIC].rank and up.honor == HL.GearDB[SEAL].honor, "GetUpgradeFor: a blue piece names its epic, Seal, rank and the Seal's honor")
            check(HL:GetUpgradeFor(EPIC) == nil and HL:GetUpgradeFor(SEAL) == nil and HL:GetUpgradeFor(1) == nil and HL:GetUpgradeFor(nil) == nil, "GetUpgradeFor: an epic, a Seal, an unknown item and nil have none")

            -- ── Kit:ScrollArea, with each template present and with all missing ──
            local function scrollSuite(label, missing, expect, hasBar)
                mock.missingTemplates = missing
                local holder = CreateFrame("Frame", nil, UIParent)
                local area = Kit:ScrollArea(holder)
                check(area.honorLogTemplate == expect, label .. "the " .. tostring(expect) .. " took")
                check((area.honorLogBar ~= false) == hasBar, label .. "a bar exactly when a template made one")
                area:SetSize(200, 100)
                area:honorLogSetContentHeight(80)
                check(area.honorLogChild:GetWidth() == 200 and area.honorLogChild:GetHeight() == 80, label .. "the child is as wide as the area and as tall as its content")
                if hasBar then check(not area.honorLogBar:IsShown(), label .. "content that fits hides the bar") end
                area.__scripts.OnMouseWheel(area, -1)
                check(area:GetVerticalScroll() == 0, label .. "content that fits does not scroll")
                area:honorLogSetContentHeight(400)
                if hasBar then check(area.honorLogBar:IsShown(), label .. "longer content shows the bar") end
                area.__scripts.OnMouseWheel(area, -1)
                check(area:GetVerticalScroll() == 30, label .. "one notch down is 30 pixels")
                for _ = 1, 30 do area.__scripts.OnMouseWheel(area, -1) end
                check(area:GetVerticalScroll() == 300, label .. "the wheel stops at the end of the content")
                area.__scripts.OnMouseWheel(area, 1)
                check(area:GetVerticalScroll() == 270, label .. "one notch up")
                for _ = 1, 30 do area.__scripts.OnMouseWheel(area, 1) end
                check(area:GetVerticalScroll() == 0, label .. "the wheel stops at the top")
                for _ = 1, 3 do area.__scripts.OnMouseWheel(area, -1) end
                area:honorLogSetContentHeight(500)
                check(area:GetVerticalScroll() == 90, label .. "the position is kept when the content is redrawn")
                area:honorLogSetContentHeight(150)
                check(area:GetVerticalScroll() == 50, label .. "a shorter list pulls the position back to its end")
                area:honorLogSetContentHeight(0)
                check(area:GetVerticalScroll() == 0 and area.honorLogChild:GetHeight() == 1, label .. "an empty list sits at the top")
                local bad = {}
                for k in pairs(area) do
                    if type(k) == "string" and not k:find("^__") and not k:find("^honorLog") and k ~= "ScrollBar" then bad[#bad + 1] = k end
                end
                check(#bad == 0, label .. "only honorLog names are added to the scroll frame: " .. table.concat(bad, ","))
                check(area.__scripts.OnUpdate == nil, label .. "no OnUpdate")
            end
            scrollSuite("scroll area (new template): ", {}, "ScrollFrameTemplate", true)
            scrollSuite("scroll area (classic template): ", { ScrollFrameTemplate = true }, "UIPanelScrollFrameTemplate", true)
            scrollSuite("scroll area (plain): ", { ["*"] = true }, false, false)
            mock.missingTemplates = {}

            -- ── Kit:Star ──
            local holder = CreateFrame("Frame", nil, UIParent)
            local star = Kit:Star(holder, 20)
            local toggles = {}
            star.honorLogOnToggle = function(s, on) toggles[#toggles + 1] = on end
            local art = star.honorLogArt
            check(star:IsOn() == false and art.__texture == Kit.STAR.file and same(art.__texCoord, Kit.STAR.off) and art.__desaturated == true and art.__alpha == 0.55,
                "star: off is the client's empty star, greyed and dimmed")
            click(star)
            check(star:IsOn() == true and toggles[1] == true and same(art.__texCoord, Kit.STAR.on) and art.__desaturated == false and art.__alpha == 1,
                "star: a click turns it on, shows the gold star and calls back")
            click(star)
            check(star:IsOn() == false and toggles[2] == false and same(art.__texCoord, Kit.STAR.off) and art.__desaturated == true, "star: a second click turns it off")
            star:SetOn(true)
            check(star:IsOn() and #toggles == 2, "star: SetOn changes the look without calling back")
            star.__scripts.OnEnter(star)
            check(mock.tip.shown and tipText() == "Remove from your goals", "star: the tooltip when on")
            star:SetOn(false)
            star.__scripts.OnEnter(star)
            check(tipText() == "Add to your goals", "star: the tooltip when off")
            star.__scripts.OnLeave(star)
            check(not mock.tip.shown, "star: the tooltip hides")

            -- ── Kit:Chips ──
            local chosen
            local chips = Kit:Chips(holder, function(key) chosen = key end)
            chips:SetOptions({ { key = "a", text = "All" }, { key = "b", text = "Second" }, { key = "c", text = "A very long chip name indeed", maxWidth = 80 } }, "b")
            local buttons = chips.honorLogButtons
            check(#buttons == 3 and buttons[1]:GetText() == "All" and buttons[2]:GetText() == "Second", "chips: one button per option with its text")
            check(chips.honorLogChosen == "b" and buttons[2].honorLogChosenFlag and not buttons[1].honorLogChosenFlag and chips.honorLogUnderline:IsShown(), "chips: the chosen one is locked and underlined")
            local ux = chips.honorLogUnderline.__points[1]
            check(ux[2] == buttons[2], "chips: the underline sits under the chosen button")
            check(buttons[3]:GetWidth() == 80 and buttons[3]:GetText():find("%.%.%.$") and #buttons[3]:GetText() < #"A very long chip name indeed" and buttons[3].honorLogTip == "A very long chip name indeed",
                "chips: a text wider than its box is cut, the full text is its tooltip")
            buttons[3].__scripts.OnEnter(buttons[3])
            check(tipText() == "A very long chip name indeed", "chips: the tooltip shows the full text")
            click(buttons[3])
            check(chosen == "c" and chips.honorLogChosen == "c" and buttons[3].honorLogChosenFlag and not buttons[2].honorLogChosenFlag and chips.honorLogUnderline.__points[1][2] == buttons[3],
                "chips: a click chooses and calls back")
            check(chips:GetWidth() == buttons[1]:GetWidth() + buttons[2]:GetWidth() + buttons[3]:GetWidth() + 8, "chips: the frame is as wide as its buttons")
            chips:SetOptions({ { key = "a", text = "All" } }, "zzz")
            check(chips.honorLogChosen == "a" and not buttons[2]:IsShown() and buttons[1]:IsShown(), "chips: an unknown choice falls back to the first option, spare buttons hide")
            local framesBefore2 = #mock.frames
            for i = 1, 10 do
                local list = {}
                for j = 1, (i % 3) + 1 do list[j] = { key = j, text = "Opt" .. j } end
                chips:SetOptions(list, 1)
            end
            check(#mock.frames == framesBefore2 and #chips.honorLogButtons == 3, "chips: ten refreshes make no new frames (pooled)")

            -- ── Kit:PreviewItem ──
            local dressed = {}
            _G.DressUpItemLink = function(link) dressed[#dressed + 1] = link end
            check(Kit:PreviewItem(BLUE) == true and #dressed == 1 and dressed[1]:find("Hitem:" .. BLUE, 1, true), "preview: an item goes to the dressing room")
            check(Kit:PreviewItem(nil) == false and #dressed == 1, "preview: nothing to preview")
            _G.DressUpItemLink = nil
            check(Kit:PreviewItem(BLUE) == false, "preview: without the client function it does nothing")

            -- ── Kit:Cut ──
            check(Kit:Cut("short", 10) == "short" and Kit:Cut("Warlord's Battlegear", 10) == "Warlord..." and Kit:Chars("a\194\183b") == 3
                and Kit:Cut("a\194\183bcdefghij", 6) == "a\194\183b...", "cut: texts are cut to their characters, never inside a character")

            -- ═══ The screen ═══
            Window:Hide()
            Window.frame, Window.frames, Window.tabs, Window.current, _G.HonorLogWindow = nil, {}, nil, nil, nil
            Gear.mode, Gear.request = "goals", nil
            mock.runShowScripts = true
            Window:Show("gear")
            local screen = Window.frames.gear
            check(screen and Window.current == "gear" and Window:IsShown(), "gear: the window opens on the Gear goals screen")
            local parts = screen.honorLogParts
            local list, detail, right = parts.list, parts.detail, parts.right
            check(Window.screens[3].key == "gear" and Window.screens[3].title == "Gear goals" and Window.screens[3].order == 3, "tabs: Gear goals is registered third")
            local function tabText(b) return b.honorLogTemplate and b:GetText() or b.honorLogLabel:GetText() end
            local tabs = Window.tabs.list
            check(tabs[2].honorLogKey == "rank" and tabs[3].honorLogKey == "gear" and tabText(tabs[3]) == "Gear goals", "tabs: Gear goals comes after Rank plan")

            -- no goals
            Window:RefreshCurrent()
            check(list.stack.count == 0 and list.none:IsShown() and list.none:GetText() == "No goals yet. Pick gear from a vendor's stock and HonorLog plans the way to it."
                , "goals: no goals, one sentence")
            check(not list.totals.wrap:IsShown() and list.add:GetText() == "Add a goal", "goals: no totals box without goals, and the Add a goal button")
            check(detail.none:IsShown() and detail.none:GetText() == "Choose a goal on the left, or add one." and not detail.icon:IsShown() and not detail.buttons[1]:IsShown(), "goals: the detail asks for a goal")
            check(list.area:GetHeight() > 400, "goals: with no totals box the list takes the room")

            -- three goals
            for _, id in ipairs({ BLUE, EPIC, REPGEAR, MOUNT }) do check(HL:AddGoal(id), "goals: " .. id .. " added") end
            HL:RemoveGoal(MOUNT)
            local order = { BLUE, EPIC, REPGEAR }
            local gps = HL:GetAllGoalsProgress()
            check(#gps == 3 and list.stack.count == 3 and not list.none:IsShown(), "goals: a row for each goal, and the empty text goes")
            local pool = list.stack.pools.goal
            check(pool[1].icon:GetFrameLevel() > pool[1].click:GetFrameLevel(), "goals: a row's item icon sits above the row's click area, so its own click and tooltip win")
            for i, id in ipairs(order) do
                local row, gp = pool[i], gps[i]
                check(gp.itemID == id and row.icon.honorLogItemID == id, "goals: row " .. i .. " is goal " .. i .. " in order")
                check(row.name:GetText() == Kit:QualityHex(row.icon.honorLogQuality) .. gp.name .. "|r", "goals: row " .. i .. " name in its quality colour")
                check(row.status:GetText() == HL:GoalReadyText(gp), "goals: row " .. i .. " status is the ready text")
                check(row.percent:GetText() == string.format("%d%%", math.floor(HL:GetGoalPercent(gp))) and row.bar.honorLogFraction == Kit.Clamp01(HL:GetGoalPercent(gp) / 100),
                    "goals: row " .. i .. " percent over a bar: " .. tostring(row.percent:GetText()))
                check(row.name.__wrapWidth == 150 and row.status.__wrapWidth == 150 and row.name.__wrapWidth and row.percent.__wrapWidth == 56 and row.bar:GetWidth() == 56 and row:GetHeight() == 50,
                    "goals: row " .. i .. " sizes, texts fixed so the client cuts them")
            end
            check(list.area.honorLogContentHeight == 150, "goals: the list is as tall as its rows")
            check(list.totals.wrap:IsShown() and list.area:GetHeight() < 330, "goals: with several goals the totals box shows and the list gives way")

            -- the chosen row
            check(pool[1].wash:IsShown() and pool[1].edge:IsShown() and not pool[2].wash:IsShown() and not pool[2].edge:IsShown() and pool[1].edge:GetWidth() == 3,
                "goals: with nothing chosen the first goal has the wash and the 3 px edge")
            check(S.windowGoal == 0, "goals: the fallback is not saved")
            click(pool[2].click)
            check(S.windowGoal == EPIC and pool[2].wash:IsShown() and pool[2].edge:IsShown() and not pool[1].wash:IsShown(), "goals: a click chooses a goal and saves it")
            check(detail.icon.honorLogItemID == EPIC and detail.name:GetText():find(gps[2].name, 1, true), "goals: the detail follows the choice")
            S.windowGoal = 999
            Window:RefreshCurrent()
            check(pool[1].wash:IsShown() and detail.icon.honorLogItemID == BLUE and S.windowGoal == 999, "goals: a goal that is not on the list falls back to the first")
            pool[2].click.__scripts.OnEnter(pool[2].click)
            check(mock.tip.shown and tipText():find(gps[2].name, 1, true), "goals: the row's tooltip carries the whole name")
            pool[2].click.__scripts.OnLeave(pool[2].click)

            -- the totals box
            local T = HL:GetGoalsTotals(gps)
            local tb = list.totals
            check(tb.title:GetText() == "All 3 together" and tb.honor:GetText() == string.format("%s / %s", HL.Rank.FormatNumber(T.honorCurrent), HL.Rank.FormatNumber(T.honorNeeded)), "totals: the count and honor in hand over honor needed")
            check(tb.marks.AV.icon:IsShown() and tb.marks.AV.count:GetText() == string.format("%d/%d", T.marksCurrent.AV, T.marksNeeded.AV) and not tb.marks.AB.icon:IsShown(), "totals: each battleground's marks as have/need")
            check(tb.gold:IsShown() and tb.gold:GetText() == string.format("%s / %s", HL:GoldShort(T.goldCurrent), HL:GoldShort(T.goldNeeded)), "totals: gold with GoldShort")
            local short = {}
            local honorShort = math.max(0, T.honorNeeded - T.honorCurrent)
            if honorShort > 0 then short[#short + 1] = HL.Rank.FormatNumber(honorShort) .. " honor" end
            local marksShort = math.max(0, T.marksNeeded.AV - T.marksCurrent.AV)
            if marksShort > 0 then short[#short + 1] = marksShort .. " marks" end
            local want = #short == 2 and ("You are " .. short[1] .. " and " .. short[2] .. " short.") or #short == 1 and ("You are " .. short[1] .. " short.") or "x"
            check(tb.short:GetText() == want, "totals: what is short, in words: " .. tostring(tb.short:GetText()) .. " / " .. want)
            local function stubTotals(t) HL.GetGoalsTotals = function() return t end Window:RefreshCurrent() end
            stubTotals({ honorNeeded = 5000, honorCurrent = 4670, goldNeeded = 0, goldCurrent = 0, marksNeeded = { AV = 20 }, marksCurrent = { AV = 5 }, allComplete = false })
            check(tb.short:GetText() == "You are 330 honor and 15 marks short.", "totals: the example sentence")
            check(tb.marks.AV.count:GetText() == "5/20" and not tb.gold:IsShown() and not tb.goldLabel:IsShown(), "totals: no gold line when no gold is needed")
            stubTotals({ honorNeeded = 5000, honorCurrent = 4670, goldNeeded = 30000, goldCurrent = 10000, marksNeeded = { AV = 20, AB = 10 }, marksCurrent = { AV = 5, AB = 10 }, allComplete = false })
            check(tb.short:GetText() == "You are 330 honor, 15 marks and 2g short.", "totals: three shortfalls in one sentence: " .. tostring(tb.short:GetText()))
            stubTotals({ honorNeeded = 5000, honorCurrent = 5000, goldNeeded = 0, goldCurrent = 0, marksNeeded = { AV = 20 }, marksCurrent = { AV = 20 }, allComplete = true })
            check(tb.short:GetText() == "You can buy everything on your list.", "totals: nothing short")
            stubTotals({ honorNeeded = 5000, honorCurrent = 5000, goldNeeded = 0, goldCurrent = 0, marksNeeded = {}, marksCurrent = {}, allComplete = false })
            check(tb.short:GetText():find("rank, level or reputation", 1, true), "totals: covered but gated is said so")
            HL.GetGoalsTotals = save.totals
            Window:RefreshCurrent()

            -- ── the chosen goal in detail (a real goal) ──
            click(pool[1].click)
            local gp1 = HL:GetAllGoalsProgress()[1]
            local item1 = HL.GearDB[BLUE]
            check(detail.icon:IsShown() and detail.icon.honorLogItemID == BLUE and not detail.none:IsShown(), "detail: the head shows the chosen goal's icon")
            check(detail.name:GetText() == Kit:QualityHex(detail.icon.honorLogQuality) .. gp1.name .. "|r" and detail.name.__wrapWidth == 276, "detail: the name in its quality colour, on one line")
            check(detail.sub:GetText() == "Head \194\183 Item Level 60 \194\183 Requires Level 55", "detail: slot, item level and required level: " .. tostring(detail.sub:GetText()))
            local function takesOf() local out = {} for _, r in ipairs(detail.takes) do if r:IsShown() then out[#out + 1] = r end end return out end
            local takes = takesOf()
            local kinds = {}
            for _, row in ipairs(gp1.rows) do if row.kind == "honor" or row.kind == "marks" or row.kind == "level" then kinds[#kinds + 1] = row end end
            check(#takes == #kinds and #takes == 3, "detail: one line per requirement that counts (a gold line only when gold is needed)")
            for i, row in ipairs(kinds) do
                local f = takes[i]
                check(f.value:GetText() == HL:GoalRowText(row), "detail: line " .. i .. " value is GoalRowText")
                check(f.tick:IsShown() == (row.met == true), "detail: line " .. i .. " a met requirement shows a tick")
            end
            check(takes[1].label:GetText() == "Honor" and takes[1].bar:IsShown() and takes[1].bar.honorLogFraction == Kit.Clamp01(gp1.rows[1].percent / 100), "detail: honor has a bar of current over needed")
            check(takes[2].label:GetText() == HL:GetBGDisplayName("AV") and takes[2].mark:IsShown() and takes[2].mark.honorLogBG == "AV" and takes[2].bar:IsShown(), "detail: marks carry the battleground's name and icon")
            check(takes[3].label:GetText() == "Level" and not takes[3].bar:IsShown() and takes[3].tick:IsShown(), "detail: level has no bar and a tick when met")
            check(takes[1].label.__wrapWidth == 104 and takes[2].label.__wrapWidth == 88 and takes[1].value.__wrapWidth == 200 and takes[1].note.__wrapWidth == 98, "detail: texts have fixed widths")
            takes[1].__scripts.OnEnter(takes[1])
            check(tipText():find("Honor: ", 1, true), "detail: a line's tooltip carries the whole text")
            check(not detail.partsHeader:IsShown() and not detail.parts[1]:IsShown(), "detail: a blue piece has no purchases block")

            -- the upgrade block (a blue piece)
            check(detail.upHeader:IsShown() and detail.upHeader.Label:GetText() == "Epic upgrade at Rank " .. HL.GearDB[EPIC].rank and detail.up:IsShown(), "detail: the blue piece offers its epic upgrade")
            check(detail.up.epic.honorLogItemID == EPIC and detail.up.seal.honorLogItemID == SEAL and detail.up.cost:GetText() == HL.Rank.FormatNumber(HL.GearDB[SEAL].honor) .. " honor",
                "detail: the epic's icon, the Seal's icon and the Seal's honor")
            check(detail.up.star:IsOn() == HL:IsGoal(EPIC) and HL:IsGoal(EPIC), "detail: the star is on while the epic is a goal")
            click(detail.up.star)
            check(not HL:IsGoal(EPIC) and not detail.up.star:IsOn(), "detail: the star removes the epic goal")
            click(detail.up.star)
            check(HL:IsGoal(EPIC) and detail.up.star:IsOn(), "detail: the star adds it back")
            check(HL:GetGoals()[3].itemID == EPIC, "detail: ...at the end of the list")
            HL:RemoveGoal(EPIC)
            HL:AddGoal(EPIC)
            HL:ReorderGoal(EPIC, 2)

            -- an epic: two purchases
            click(pool[2].click)
            check(detail.partsHeader:IsShown() and detail.partsHeader.Label:GetText() == "Two purchases" and not detail.up:IsShown() and not detail.upHeader:IsShown(), "detail: an epic shows its two purchases, not an upgrade")
            local gpE = HL:GetAllGoalsProgress()[2]
            check(#gpE.parts == 2 and detail.parts[1]:IsShown() and detail.parts[2]:IsShown(), "detail: a line for each part")
            for i, part in ipairs(gpE.parts) do
                check(detail.parts[i].icon.honorLogItemID == part.itemID and detail.parts[i].icon:GetWidth() == 20 and detail.parts[i].text:GetText() == HL:GoalPartText(part), "detail: part " .. i .. " has its icon and its text")
            end
            click(pool[1].click)

            -- buttons for an active goal
            local b = detail.buttons
            check(b[1]:GetText() == "Try it on" and b[2]:GetText() == "Move up" and b[3]:GetText() == "Move down" and b[4]:GetText() == "Remove" and b[4]:IsShown(), "detail: the active goal's buttons")
            check(b[2]:IsEnabled() == false and b[3]:IsEnabled() == true, "detail: the first goal cannot move up")
            local previewed = {}
            _G.DressUpItemLink = function(link) previewed[#previewed + 1] = link end
            click(b[1])
            check(#previewed == 1 and previewed[1]:find("Hitem:" .. BLUE, 1, true), "detail: Try it on previews the item")
            _G.DressUpItemLink = nil
            click(b[2])
            check(HL:GetGoals()[1].itemID == BLUE, "detail: Move up at the top does nothing")
            local function goalIDs() local out = {} for i, g in ipairs(HL:GetGoals()) do out[i] = g.itemID end return table.concat(out, ",") end
            click(b[3])
            check(goalIDs() == EPIC .. "," .. BLUE .. "," .. REPGEAR, "detail: Move down moves the goal down one place: " .. goalIDs())
            check(detail.icon.honorLogItemID == BLUE and b[2]:IsEnabled() == true and b[3]:IsEnabled() == true and pool[2].wash:IsShown(), "detail: the screen followed the goal, both moves open in the middle")
            click(b[3])
            check(goalIDs() == EPIC .. "," .. REPGEAR .. "," .. BLUE and b[3]:IsEnabled() == false and b[2]:IsEnabled() == true, "detail: at the end of the list Move down is disabled")
            click(b[3])
            check(goalIDs() == EPIC .. "," .. REPGEAR .. "," .. BLUE, "detail: Move down at the end does nothing")
            click(b[2])
            click(b[2])
            check(goalIDs() == BLUE .. "," .. EPIC .. "," .. REPGEAR and b[2]:IsEnabled() == false, "detail: Move up twice puts it back at the top, and Move up is disabled there")

            -- Remove removes, and the choice falls back to the first goal
            click(pool[2].click)
            click(b[4])
            check(goalIDs() == BLUE .. "," .. REPGEAR and list.stack.count == 2 and detail.icon.honorLogItemID == BLUE and S.windowGoal == EPIC, "detail: Remove removes the goal and the choice falls back to the first")
            HL:AddGoal(EPIC)
            HL:ReorderGoal(EPIC, 2)

            -- a bought goal
            HL:CompleteGoal(REPGEAR)
            local divider, boughtRow = list.stack.pools.divider and list.stack.pools.divider[1], list.stack.pools.bought and list.stack.pools.bought[1]
            check(list.stack.count == 4 and divider and divider:IsShown() and divider.text:GetText() == "Bought" and divider:GetHeight() == 22, "goals: a small divider named Bought comes after the active goals")
            check(boughtRow and boughtRow:IsShown() and boughtRow.icon.honorLogItemID == REPGEAR and boughtRow.tick:IsShown() and not boughtRow.bar:IsShown() and boughtRow.percent:GetText() == ""
                and same(textColor(boughtRow.name), Kit.COLORS.grey) and boughtRow:GetHeight() == 50, "goals: a bought goal is a grey row with a tick and no percent")
            check(boughtRow.name:GetText() == HL:GetGearName(REPGEAR) and boughtRow.status:GetText() == "Waist", "goals: a bought goal names the item and its slot")
            check(list.totals.title:GetText() == "All 2 together", "goals: the totals count the active goals only")
            click(boughtRow.click)
            check(S.windowGoal == REPGEAR and boughtRow.wash:IsShown() and boughtRow.edge:IsShown() and detail.icon.honorLogItemID == REPGEAR, "goals: a bought goal can be chosen")
            check(b[1]:GetText() == "Try it on" and b[2]:GetText() == "Put back" and b[3]:GetText() == "Remove" and not b[4]:IsShown(), "detail: a bought goal has Put back and Remove")
            check(detail.boughtNote:IsShown() and not detail.takesHeader:IsShown() and not detail.reason:IsShown() and not detail.readyValue:IsShown() and detail.soldHeader:IsShown(), "detail: a bought goal says so, plans nothing and still names its vendor")
            click(b[2])
            check(goalIDs() == BLUE .. "," .. EPIC .. "," .. REPGEAR and #HL:GetCompletedGoals() == 0 and not divider:IsShown() and list.stack.count == 3, "detail: Put back makes it an active goal again, and the divider goes")
            check(b[2]:GetText() == "Move up" and b[4]:IsShown(), "detail: and it has the active goal's buttons")
            HL:CompleteGoal(REPGEAR)
            click(list.stack.pools.bought[1].click)
            click(detail.buttons[3])
            check(#HL:GetCompletedGoals() == 0 and list.stack.count == 2 and detail.icon.honorLogItemID == BLUE, "detail: Remove on a bought goal removes it for good")
            HL:AddGoal(REPGEAR)
            S.windowGoal = BLUE
            Window:RefreshCurrent()

            -- ── every kind of requirement, with its note ──
            local DATE = os.time({ year = 2026, month = 12, day = 2, hour = 12 })
            local function stubGp(over)
                local base = {
                    itemID = BLUE, name = "Premier Plate Helm", item = HL:GetGearItem(BLUE), isComplete = false, missing = {}, unverified = {},
                    estimated = false, readyDate = DATE, readyLimitedBy = "honor",
                    rows = {
                        { kind = "honor", needed = 5000, current = 1200, met = false, remaining = 3800, percent = 24, games = 6 },
                        { kind = "marks", bg = "AB", needed = 10, current = 10, met = true, remaining = 0, percent = 100, games = 0 },
                        { kind = "gold", needed = 15000, current = 20000, met = true, remaining = 0, percent = 100 },
                        { kind = "rank", needed = 6, current = 3, met = false, known = true, date = DATE, limitedBy = "pace" },
                        { kind = "level", needed = 55, current = 35, met = false, known = true },
                        { kind = "rep", needed = 5, current = 4, met = false, known = true, faction = 509, factionName = "The League of Arathor", standingName = "Friendly",
                            games = 8, amount = 100, ceiling = 3000 },
                    },
                }
                for k, v in pairs(over or {}) do base[k] = v end
                return base
            end
            local current
            HL.GetAllGoalsProgress = function() return { current } end
            local function show(over) current = stubGp(over) Window:RefreshCurrent() return takesOf() end
            local rows6 = show()
            local gpS = current
            check(#rows6 == 6, "takes: a line for each of the six kinds")
            local labels = { "Honor", HL:GetBGDisplayName("AB"), "Gold", "Rank", "Level", "The League of Arathor" }
            for i, r in ipairs(rows6) do
                check(r.label:GetText() == labels[i] and r.value:GetText() == HL:GoalRowText(gpS.rows[i]), "takes: line " .. i .. " reads " .. labels[i])
                check(r.tick:IsShown() == (gpS.rows[i].met == true), "takes: line " .. i .. " tick only when met")
            end
            check(rows6[1].bar:IsShown() and rows6[1].bar.honorLogFraction == 0.24 and same(rows6[1].bar.honorLogColor, { 1, 0.82, 0.1 }) and rows6[1].note:GetText() == "about 6 games", "takes: honor: bar, and the games it takes")
            check(rows6[2].bar:IsShown() and rows6[2].bar.honorLogFraction == 1 and same(rows6[2].bar.honorLogColor, Kit.COLORS.green) and rows6[2].note:GetText() == "" and rows6[2].mark.honorLogBG == "AB", "takes: a met marks line has a full green bar and no note")
            check(rows6[3].bar:IsShown() and rows6[3].note:GetText() == "", "takes: gold has a bar")
            check(not rows6[4].bar:IsShown() and rows6[4].note:GetText() == Rank.FormatDate(DATE) and rows6[4].note:GetText() == "Dec 02", "takes: a rank has the rank plan's date")
            check(not rows6[5].bar:IsShown() and rows6[5].note:GetText() == "", "takes: a level has neither bar nor note")
            check(not rows6[6].bar:IsShown() and rows6[6].note:GetText() == "about 8 games", "takes: reputation has the games it takes")
            local function rankRow(over) local r = { kind = "rank", needed = 6, current = 3, met = false, known = true } for k, v in pairs(over) do r[k] = v end return r end
            local function withRank(over) local g = stubGp() g.rows[4] = rankRow(over) current = g Window:RefreshCurrent() return takesOf()[4] end
            check(withRank({ limitedBy = "cap", week = 4 }).note:GetText() == "opens in week 4", "takes: a rank held by the weekly cap says which week")
            check(withRank({ limitedBy = "level", plan = { limitedBy = "level", gateLevel = 40 } }).note:GetText() == "after level 40", "takes: a rank held by a level says so")
            check(withRank({ limitedBy = "pace" }).note:GetText() == "not this season", "takes: a rank with no date is not for this season")
            check(withRank({ met = true, current = 7 }).note:GetText() == "" and takesOf()[4].tick:IsShown(), "takes: a met rank has a tick and no note")
            local g1 = stubGp()
            g1.rows[1].games = 1
            current = g1
            Window:RefreshCurrent()
            check(takesOf()[1].note:GetText() == "about 1 game", "takes: one game is singular")
            local g0 = stubGp()
            g0.rows[1].needed, g0.rows[3].needed = 0, 0
            current = g0
            Window:RefreshCurrent()
            check(#takesOf() == 4, "takes: honor and gold lines are left out when nothing is needed")

            -- the date and why
            local reasons = {
                { "honor", "Honor is what takes longest." }, { "marks", "Marks are what take longest." }, { "rank", "The rank is what takes longest." },
                { "cap", "The weekly rank cap holds the rank back." }, { "level", "Your level is too low: reach level 55 first.", { level = { needed = 55 } } },
                { "rep", "Reputation is what takes longest." }, { "gold", "Only gold is short." },
                { "nopace", "No recent games to measure from. Play a game for a date.", { readyDate = false } },
                { "nopoints", "Your recent games gave no rank points, so the rank cannot be dated.", { readyDate = false } },
                { "season", "The rank cannot be reached this season.", { readyDate = false } },
                { "norep", "play a AB game to measure reputation", { readyText = "play a AB game to measure reputation", readyDate = false } },
            }
            for _, r in ipairs(reasons) do
                local over = { readyLimitedBy = r[1] }
                for k, v in pairs(r[3] or {}) do over[k] = v end
                show(over)
                check(detail.reason:GetText() == r[2] and detail.reason:IsShown() and detail.reason.__maxLines == 3, "ready: why, in plain words: " .. r[1])
            end
            show()
            check(detail.readyLabel:IsShown() and detail.readyLabel:GetText() == "Ready" and detail.readyValue:GetText() == "Dec 02" and same(textColor(detail.readyValue), Kit.COLORS.white), "ready: the date")
            show({ estimated = true })
            check(detail.readyValue:GetText() == "about Dec 02", "ready: an estimate says about")
            show({ readyDate = false })
            check(detail.readyValue:GetText() == "No date yet" and same(textColor(detail.readyValue), Kit.COLORS.grey), "ready: no date")
            show({ isComplete = true, readyLimitedBy = "ready" })
            check(detail.readyValue:GetText() == "Ready to purchase" and same(textColor(detail.readyValue), Kit.COLORS.green) and not detail.readyLabel:IsShown()
                and detail.reason:GetText() == "You have everything this needs.", "ready: a complete goal is ready to purchase, in green")

            -- who sells it
            show()
            local vendor1 = HL:GetVendorFor(BLUE)
            check(detail.link:IsShown() and detail.link.honorLogVendor.name == vendor1.name and detail.map:IsShown() and detail.map:GetText() == "Show on map" and not detail.noVendor:IsShown(), "sold by: the vendor as a place link and a map button")
            check(detail.place:GetText() == vendor1.place, "sold by: the place in grey")
            local shownFor, shownOn = {}, {}
            HL.ShowVendorForItem = function(_, id) shownFor[#shownFor + 1] = id return true end
            HL.ShowVendorOnMap = function(_, v) shownOn[#shownOn + 1] = v return true end
            click(detail.map)
            click(detail.link)
            check(shownFor[1] == BLUE and shownOn[1] and shownOn[1].name == vendor1.name, "sold by: both lead to the map")
            HL.ShowVendorForItem, HL.ShowVendorOnMap = save.showForItem, save.showOnMap
            HL.GetVendorFor = function() return nil end
            Window:RefreshCurrent()
            check(not detail.link:IsShown() and not detail.map:IsShown() and not detail.place:IsShown() and detail.noVendor:IsShown()
                and detail.noVendor:GetText() == "Vendor not known yet. Open a PvP vendor once and HonorLog remembers where it is.", "sold by: no known vendor, one grey sentence")
            HL.GetVendorFor = save.vendorFor
            HL.GetAllGoalsProgress = save.allGoals
            Window:RefreshCurrent()

            -- ── what you can get ──
            local limits = {}
            local function buyEntry(n) return { itemID = BLUE, name = "Test " .. n, honor = 1200, marks = { AV = 10, AB = 5 }, gold = 15000 } end
            HL.GetBuyableNow = function(_, limit) limits[#limits + 1] = limit return { buyEntry(1), buyEntry(2), buyEntry(3), buyEntry(4), buyEntry(5), buyEntry(6) } end
            Window:RefreshCurrent()
            check(limits[#limits] == 4 and right.headers[1]:IsShown() and right.headers[1].Label:GetText() == "You can buy today", "buyable: asks for four, under its header")
            local shownEntries = 0
            for _, e in ipairs(right.entries) do if e:IsShown() then shownEntries = shownEntries + 1 end end
            local shortAV, shortAB = HL:GetBGShortName("AV"), HL:GetBGShortName("AB")
            check(right.entries[1].icon.honorLogItemID == BLUE and right.entries[1].icon:GetWidth() == 24 and right.entries[1].name:GetText() == Kit:QualityHex(right.entries[1].icon.honorLogQuality) .. "Test 1|r"
                and right.entries[1].cost:GetText() == "1,200 honor, 10 " .. shortAV .. ", 5 " .. shortAB .. ", 1g", "buyable: icon, name and cost: " .. tostring(right.entries[1].cost:GetText()))
            check(not right.nothing:IsShown(), "buyable: no empty text when there are entries")
            HL.GetBuyableNow = function() return {} end
            Window:RefreshCurrent()
            check(right.nothing:IsShown() and right.nothing:GetText() == "Nothing yet.", "buyable: nothing yet")
            HL.GetBuyableNow = save.buyable
            check(not right.advice:IsShown(), "advice: none far from the cap")
            HL.GetHonorCapAdvice = function() return { text = "you'll reach the 25,000 honor cap in about 3 games and nothing on your list can be bought yet because of level, rank or reputation." } end
            Window:RefreshCurrent()
            check(right.advice:IsShown() and right.advice:GetText():find("^You'll reach the 25,000") and right.advice.__maxLines == 4 and same(textColor(right.advice), Kit.COLORS.orange), "advice: the cap advice in orange, at most four lines")
            HL.GetHonorCapAdvice = save.advice

            local function headerTexts() local out = {} for i = 2, 3 do if right.headers[i]:IsShown() then out[#out + 1] = right.headers[i].Label:GetText() end end return out end
            mock.rank.level = 3
            HL.GetBuyableNow = function() return {} end
            Window:RefreshCurrent()
            local expect = {}
            for n = 4, 14 do
                local ids = HL:GetRankUnlocks(n)
                if #ids > 0 and #expect < 2 then expect[#expect + 1] = { n, ids } end
            end
            local ht = headerTexts()
            check(#expect == 2 and ht[1] == "Rank " .. expect[1][1] .. " opens" and ht[2] == "Rank " .. expect[2][1] .. " opens", "unlocks: the next rank that opens something, then the next such rank: " .. table.concat(ht, "/"))
            local first = right.entries[1]
            check(first:IsShown() and first.icon.honorLogItemID == expect[1][2][1] and first.cost:GetText() ~= "", "unlocks: items as icon, name and cost")
            check(right.foot:GetText() == "Ctrl-click an icon to preview the item." and right.foot.__maxLines == 2, "right: the preview hint at the foot")
            mock.rank.level = 14
            Window:RefreshCurrent()
            check(#headerTexts() == 0, "unlocks: nothing when every rank is reached")
            mock.rank.level = 3
            Window:RefreshCurrent()
            HL.GetBuyableNow = save.buyable
            Window:RefreshCurrent()

            -- ═══ The vendor browser ═══
            click(list.add)
            check(Gear.mode == "vendors" and parts.vendorsRoot:IsShown() and not parts.goalsRoot:IsShown() and Window.current == "gear", "vendors: Add a goal switches to the vendor browser")
            local gv = parts.vendors
            local vlist, stock = gv.list, gv.stock
            local vendors = HL:GetVendorList()
            local quarter, supply = {}, {}
            for _, v in ipairs(vendors) do if v.kind == "supply" then supply[#supply + 1] = v else quarter[#quarter + 1] = v end end
            local ordered = {}
            for _, v in ipairs(quarter) do ordered[#ordered + 1] = v end
            for _, v in ipairs(supply) do ordered[#ordered + 1] = v end
            local titles, vrows = vlist.stack.pools.title, vlist.stack.pools.vendor
            check(vlist.stack.count == #vendors + 2 and titles[1].text:GetText() == quarter[1].place and titles[2].text:GetText() == "Battleground supply officers"
                and titles[1]:GetHeight() == 22, "vendors: two groups, the quartermasters under their place and the supply officers")
            for i, v in ipairs(ordered) do
                local r = vrows[i]
                check(r.name:GetText() == v.name and r.role:GetText() == v.role and r.count:GetText() == tostring(v.count) and r:GetHeight() == 40
                    and r.pin:IsShown() == not v.known and same(textColor(r.count), Kit.COLORS.gold), "vendors: row " .. i .. " is " .. v.name .. ", its role and its count")
            end
            check(vrows[1].name.__wrapWidth == 150 and vrows[1].role.__wrapWidth == 160 and vrows[1].count.__wrapWidth == 34, "vendors: the vendor texts have fixed widths")
            check(vlist.foot:GetText() == "Counts are what your class can use.", "vendors: the foot note")
            check(vrows[1].wash:IsShown() and vrows[1].edge:IsShown() and not vrows[2].wash:IsShown() and stock.name:GetText() == ordered[1].name, "vendors: with none chosen the first has the wash and edge, and its stock shows")
            -- a vendor with no position: none is left in the table, so one is blanked while the list is built
            local palanseer
            for _, v in ipairs(HL.VENDORS) do if v.npc == 12792 then palanseer = v end end
            local px, py = palanseer.x, palanseer.y
            palanseer.x, palanseer.y = nil, nil
            mock.faction = "Horde"
            Window:RefreshCurrent()
            local unknown
            for i, v in ipairs(HL:GetVendorList()) do if not v.known and v.kind ~= "supply" then unknown = vrows[i] break end end
            check(unknown and unknown.pin:IsShown(), "vendors: a vendor with no known position shows a pin")
            unknown.click.__scripts.OnEnter(unknown.click)
            check(tipText():find("Not found yet. Open this vendor once and HonorLog remembers where it is.", 1, true), "vendors: and says why in its tooltip")
            unknown.click.__scripts.OnLeave(unknown.click)
            palanseer.x, palanseer.y = px, py
            mock.faction = "Alliance"
            Window:RefreshCurrent()
            local armor
            for i, v in ipairs(ordered) do if v.kind == "armor" then armor = { index = i, vendor = v } end end
            click(vrows[2].click)
            check(S.windowVendor == ordered[2].key and vrows[2].wash:IsShown() and vrows[2].edge:IsShown() and not vrows[1].wash:IsShown() and not vrows[1].edge:IsShown()
                and stock.name:GetText() == ordered[2].name and stock.role:GetText() == ordered[2].role, "vendors: a click chooses a vendor and saves it")
            S.windowVendor = "Nobody"
            Window:RefreshCurrent()
            check(vrows[1].wash:IsShown() and stock.name:GetText() == ordered[1].name and S.windowVendor == "Nobody", "vendors: an unknown vendor falls back to the first")
            click(vrows[armor.index].click)
            check(S.windowVendor == armor.vendor.key and stock.name:GetText() == armor.vendor.name, "vendors: the armor vendor is chosen")
            check(stock.link:IsShown() and stock.link.honorLogVendor.key == armor.vendor.key and stock.map:GetText() == "Show on map" and stock.back:GetText() == "Back to goals", "vendors: the head has the place link and the buttons")
            local onMap = {}
            HL.ShowVendorOnMap = function(_, v) onMap[#onMap + 1] = v return true end
            click(stock.map)
            click(stock.link)
            check(onMap[1] and onMap[1].key == armor.vendor.key and #onMap == 2, "vendors: Show on map and the link lead to the vendor")
            HL.ShowVendorOnMap = save.showOnMap

            -- the stock, the set chips and the class toggle
            local rowsNow = HL:GetVendorStock(armor.vendor, {})
            check(stock.stack.count == #rowsNow and #rowsNow > 5 and not stock.empty:IsShown(), "stock: a row for each item the class can use")
            local sets = HL:GetVendorSets(armor.vendor)
            local sb = stock.setChips.honorLogButtons
            local shownChips = 0
            for _, c in ipairs(sb) do if c:IsShown() then shownChips = shownChips + 1 end end
            check(shownChips == 1 + math.min(5, #sets) and sb[1]:GetText() == "All" and sb[1].honorLogChosenFlag and stock.setChips.honorLogChosen == "all", "stock: All and at most five sets, All chosen")
            check(sb[2]:GetText():find(" " .. sets[1].count .. "$") and sb[2].honorLogTip == sets[1].name .. " (" .. sets[1].count .. ")", "stock: a set chip has its count, the full name as tooltip")
            check(not stock.totals:IsShown() and stock.area:GetHeight() == 334, "stock: no whole-set line with All")
            local cb = stock.classChips.honorLogButtons
            check(cb[1]:GetText() == "Warrior" and cb[2]:GetText() == "All classes" and stock.classChips.honorLogChosen == "player", "stock: the class toggle names the player's class and All classes")
            click(sb[2])
            local setRows = HL:GetVendorStock(armor.vendor, { set = sets[1].id })
            check(stock.stack.count == #setRows and #setRows == sets[1].count and stock.setChips.honorLogChosen == sets[1].id, "stock: a set chip filters the rows to the set")
            for _, f in ipairs(stock.stack.pools.item) do
                if f:IsShown() then check(f.honorLogEntry.row.set == sets[1].id, "stock: row " .. f.honorLogEntry.row.itemID .. " belongs to the set") end
            end
            local honor, marksAV, gold = 0, 0, 0
            for _, r in ipairs(setRows) do
                if not r.owned then honor = honor + (r.data.honor or 0) marksAV = marksAV + ((r.data.marks and r.data.marks.AV) or 0) gold = gold + (r.data.gold or 0) end
            end
            check(stock.totals:IsShown() and stock.totals.label:GetText() == "Whole set" and stock.totals.honor:GetText() == HL.Rank.FormatNumber(honor) .. " honor" and stock.area:GetHeight() == 310,
                "stock: a set shows the whole set's honor under the table: " .. tostring(stock.totals.honor:GetText()))
            if marksAV > 0 then check(stock.totals.marks.AV.icon:IsShown() and stock.totals.marks.AV.count:GetText() == tostring(marksAV), "stock: ...and its marks") end
            mock.bagContents = { setRows[1].itemID }
            Window:RefreshCurrent()
            local honorNow = 0
            for _, r in ipairs(HL:GetVendorStock(armor.vendor, { set = sets[1].id })) do if not r.owned then honorNow = honorNow + (r.data.honor or 0) end end
            check(stock.totals.honor:GetText() == HL.Rank.FormatNumber(honorNow) .. " honor" and honorNow < honor, "stock: the whole set leaves out what you already own")
            mock.bagContents = {}
            click(sb[1])
            check(stock.stack.count == #rowsNow and not stock.totals:IsShown(), "stock: All brings the whole stock back")
            click(cb[2])
            local allClass = HL:GetVendorStock(armor.vendor, { class = "ALL" })
            check(S.windowVendorClass == "all" and stock.stack.count == #allClass and #allClass > #rowsNow and stock.classChips.honorLogChosen == "all", "stock: All classes shows every class's items and saves the choice")
            local chipsAll = 0
            for _, c in ipairs(sb) do if c:IsShown() then chipsAll = chipsAll + 1 end end
            check(chipsAll == 1 and sb[1]:GetText() == "All" and #HL:GetVendorSets(armor.vendor, "ALL") >= #sets, "stock: with every class shown there are no set chips, only All")
            click(cb[1])
            check(S.windowVendorClass == "player" and stock.stack.count == #rowsNow, "stock: the player's class again")
            click(sb[2])
            click(cb[2])
            check(stock.setChips.honorLogChosen == "all" or stock.setChips.honorLogChosen == sets[1].id, "stock: a set the new filter still offers stays chosen")
            click(cb[1])
            click(stock.setChips.honorLogButtons[1])

            -- set chips drop the words every set name starts with
            local Lead = HL.GearVendors.SharedLead
            check(Lead({ { name = "Champion's Earthshaker" }, { name = "Champion's Thunderfist" }, { name = "Champion's Wartide" } }) == "Champion's ", "chips: the shared first word is dropped")
            check(Lead({ { name = "The Defiler's Will" }, { name = "The Defiler's Intent" } }) == "The Defiler's ", "chips: two shared words are dropped")
            check(Lead({ { name = "Champion's Battlegear" } }) == "" and Lead({}) == "", "chips: one set keeps its whole name")
            check(Lead({ { name = "Alpha" }, { name = "Alpha Beta" } }) == "" and Lead({ { name = "Warsong" }, { name = "Warlord" } }) == "", "chips: never a whole name, never half a word")

            -- the vendor list is counted once, not on every click; a vendor scan counts it again
            local realList, listCalls = HL.GetVendorList, 0
            HL.GetVendorList = function(...) listCalls = listCalls + 1 return realList(...) end
            Window:RefreshCurrent()
            Window:RefreshCurrent()
            check(listCalls == 0, "vendors: a refresh with nothing scanned since does not count the stock again")
            HonorLogDB.scannedVendors = HonorLogDB.scannedVendors or {}
            HonorLogDB.scannedVendors["Kept List Vendor"] = { timestamp = 12345, itemCount = 0 }
            Window:RefreshCurrent()
            check(listCalls == 1, "vendors: a new vendor scan counts it again")
            Window:RefreshCurrent()
            check(listCalls == 1, "vendors: and then it is kept again")
            HonorLogDB.scannedVendors["Kept List Vendor"] = nil
            HL.GetVendorList = realList
            Window:RefreshCurrent()

            -- the star: add, remove, and the row follows
            local function itemRow(id) for _, f in ipairs(stock.stack.pools.item) do if f:IsShown() and f.honorLogEntry.row.itemID == id then return f end end end
            local freeID
            for _, r in ipairs(HL:GetVendorStock(armor.vendor, {})) do if not r.isGoal and not r.owned and not freeID then freeID = r.itemID end end
            local fr = itemRow(freeID)
            check(fr and not fr.star:IsOn() and fr.star:IsShown() and not fr.tick:IsShown(), "star: an item that is no goal has a hollow star")
            click(fr.star)
            check(HL:IsGoal(freeID) and itemRow(freeID).star:IsOn(), "star: a click adds the goal and the row follows")
            click(itemRow(freeID).star)
            check(not HL:IsGoal(freeID) and not itemRow(freeID).star:IsOn(), "star: a second click removes it")
            check(itemRow(BLUE) and itemRow(BLUE).star:IsOn(), "star: an item that is a goal has a filled star")
            mock.bagContents = { freeID }
            Window:RefreshCurrent()
            fr = itemRow(freeID)
            check(fr.tick:IsShown() and fr.owned:IsShown() and fr.owned:GetText() == "Owned" and not fr.star:IsShown(), "star: an owned item shows a tick and Owned instead of a star")
            mock.bagContents = {}
            Window:RefreshCurrent()

            -- every column of a row
            HL.GetVendorStock = function()
                return {
                    { itemID = BLUE, name = "Test Helm", slot = "HEAD", set = 282, isGoal = false, owned = false,
                        data = { honor = 9000, gold = 0, marks = { AV = 15 }, rank = 4, reqLevel = 55 }, upgrade = { itemID = EPIC, sealID = SEAL, rank = 13, honor = 11650 } },
                    { itemID = REPGEAR, name = "Test Girdle", slot = "WAIST", isGoal = false, owned = false, data = { gold = 56764, reqLevel = 58 } },
                    { itemID = BLUE, name = "Test Mix", slot = "TWO_HAND", isGoal = false, owned = false, data = { honor = 1000, gold = 20000, marks = { AV = 5, AB = 6, WSG = 7 } } },
                    { itemID = BLUE, name = "Test Owned", slot = "FINGER", isGoal = false, owned = true, data = { honor = 500 } },
                    { itemID = BLUE, name = "Test Goal", slot = "BACK", isGoal = true, owned = false, data = { honor = 250, reqLevel = 70 } },
                }
            end
            Window:RefreshCurrent()
            local fr1, fr2, fr3, fr4, fr5 = unpack(stock.stack.pools.item, 1, 5)
            check(fr1.icon.honorLogItemID == BLUE and fr1.icon:GetWidth() == 24 and fr1.name:GetText() == Kit:QualityHex(fr1.icon.honorLogQuality) .. "Test Helm|r" and fr1.slot:GetText() == "Head" and fr1:GetHeight() == 30,
                "columns: the item's icon, its name in its quality colour and its slot")
            check(fr1.needs:GetText() == "R4 \194\183 L55" and same(textColor(fr1.needs), Kit.COLORS.orange) and fr1.needsCell.tip == "Rank 4 \194\183 Level 55", "columns: needs, orange while the rank is short")
            check(fr2.needs:GetText() == "L58" and same(textColor(fr2.needs), Kit.COLORS.grey), "columns: needs, grey when met")
            check(fr3.needs:GetText() == "-" and fr5.needs:GetText() == "L70" and same(textColor(fr5.needs), Kit.COLORS.orange), "columns: nothing needed is a dash, a level above yours is orange")
            check(fr1.honor:GetText() == "9,000" and not fr1.gold:IsShown(), "columns: honor with a thousands separator")
            check(fr2.honor:GetText() == HL:GoldShort(56764) and not fr2.gold:IsShown(), "columns: a gold-only cost stands in the honor cell")
            check(fr3.honor:GetText() == "1,000" and fr3.gold:IsShown() and fr3.gold:GetText() == "2g", "columns: honor and a gold price under it")
            check(fr4.honor:GetText() == "500" and fr1.slot.__wrapWidth == 64 and fr1.name.__wrapWidth == 156, "columns: fixed widths")
            check(fr1.marks[1].icon:IsShown() and fr1.marks[1].icon.honorLogBG == "AV" and fr1.marks[1].count:GetText() == "15" and not fr1.marks[2].icon:IsShown(), "columns: marks with their battleground")
            check(fr3.marks[1].icon.honorLogBG == "AV" and fr3.marks[2].icon.honorLogBG == "WSG" and fr3.marks[2].count:GetText() == "7" and fr3.marks[3] == nil, "columns: at most two battlegrounds")
            check(not fr2.marks[1].icon:IsShown(), "columns: no marks, no icon")
            check(fr1.upgradeCell:IsShown() and fr1.upgradeIcon.honorLogItemID == EPIC and fr1.upgradeIcon:GetWidth() == 18 and fr1.upgradeRank:GetText() == "Rank 13" and fr1.upgradeHonor:GetText() == "11,650", "columns: the epic upgrade, its rank and the Seal's honor")
            check(not fr2.upgradeCell:IsShown(), "columns: no upgrade cell without an upgrade")
            check(fr1.star:IsShown() and not fr1.star:IsOn() and fr5.star:IsOn() and fr4.tick:IsShown() and fr4.owned:GetText() == "Owned" and not fr4.star:IsShown(), "columns: the star, on for a goal, a tick for an owned item")
            check(fr1.stripe:IsShown() == false and fr2.stripe:IsShown() == true and fr3.stripe:IsShown() == false, "columns: stripes on every second row")
            mock.level = 40
            Window:RefreshCurrent()
            check(same(textColor(fr2.needs), Kit.COLORS.orange), "columns: needs follows the player's level")
            mock.level = 60
            HL.GetVendorStock = function() return {} end
            Window:RefreshCurrent()
            check(stock.empty:IsShown() and stock.empty:GetText() == "Nothing here for your class. Try All classes." and stock.stack.count == 0, "stock: nothing for the filter")
            HL.GetVendorStock = save.stock
            Window:RefreshCurrent()
            check(not stock.empty:IsShown() and stock.foot:GetText() == "The star adds a goal. Prices come from the vendor once you have opened it, otherwise from game data.", "stock: the foot note")
            check(stock.titles[1]:GetText() == "Item" and stock.titles[2]:GetText() == "Slot" and stock.titles[3]:GetText() == "Needs" and stock.titles[4]:GetText() == "Honor"
                and stock.titles[5]:GetText() == "Marks" and stock.titles[6]:GetText() == "Epic upgrade", "stock: the column titles")

            -- Back to goals, and the entry points
            click(stock.back)
            check(Gear.mode == "goals" and parts.goalsRoot:IsShown() and not parts.vendorsRoot:IsShown(), "vendors: Back to goals returns to the goals")
            Gear:Open("vendors")
            check(Gear.mode == "vendors" and parts.vendorsRoot:IsShown() and Window.current == "gear", "open: vendors mode")
            Gear:Open("goals", EPIC)
            check(Gear.mode == "goals" and S.windowGoal == EPIC and detail.icon.honorLogItemID == EPIC and Window.current == "gear" and parts.goalsRoot:IsShown(), "open: goals mode with an item chooses that goal")
            Gear:Open("anything")
            check(Gear.mode == "goals", "open: an unknown mode is goals")
            Window:Show("overview")
            Gear:Open("vendors")
            check(Window.current == "gear" and Window:IsShown() and parts.vendorsRoot:IsShown(), "open: from another screen it switches to Gear goals")
            Window:Hide()
            Gear:Open("goals", BLUE)
            check(Window:IsShown() and Window.current == "gear" and S.windowGoal == BLUE and detail.icon.honorLogItemID == BLUE, "open: it shows a closed window")
            check(Gear.request == nil, "open: the request is used up")

            -- the saved tab restores the screen
            S.windowTab = "gear"
            Window:Hide()
            Window.frame, Window.frames, Window.tabs, Window.current, _G.HonorLogWindow = nil, {}, nil, nil, nil
            Window:Show()
            check(Window.current == "gear" and Window.frames.gear:IsShown(), "tabs: the saved tab restores the Gear goals screen")
            parts = Window.frames.gear.honorLogParts

            -- ── Hygiene ──
            for _, mode in ipairs({ "goals", "vendors" }) do
                Gear:Open(mode)
                local inGear = function(f)
                    local hops = 0
                    while f and hops < 40 do
                        if f == Window.frames.gear then return true end
                        f, hops = f.__parent, hops + 1
                    end
                    return false
                end
                local onUpdates, foreign, templated = 0, {}, 0
                for _, f in ipairs(mock.frames) do
                    if inGear(f) then
                        if f.__scripts.OnUpdate then onUpdates = onUpdates + 1 end
                        if f.__template then
                            templated = templated + 1
                            for k in pairs(f) do
                                if type(k) == "string" and not k:find("^__") and not k:find("^honorLog") and k ~= "ScrollBar" then foreign[#foreign + 1] = k end
                            end
                        end
                    end
                end
                check(onUpdates == 0, "gear (" .. mode .. "): no OnUpdate anywhere (" .. onUpdates .. ")")
                check(templated > 10 and #foreign == 0, "gear (" .. mode .. "): only honorLog names are added to template frames: " .. table.concat(foreign, ","))
            end

            -- every client read gone or secret
            local errorsBefore = #mock.handledErrors
            local secret = mock.newSecret
            local savedReads = { level = _G.UnitLevel, class = _G.UnitClass, icon = C_Item.GetItemIconByID, quality = C_Item.GetItemQualityByID, info = C_MajorFactions.GetMajorFactionProgressionInfo,
                currency = C_CurrencyInfo.GetCurrencyInfo, count = C_Item.GetItemCount, money = _G.GetMoney, faction = _G.UnitFactionGroup, itemInfo = C_Item.GetItemInfo }
            for _, mode in ipairs({ "goals", "vendors" }) do
                Gear:Open(mode)
                _G.UnitLevel, _G.UnitClass, _G.UnitFactionGroup = function() return secret() end, function() return secret() end, function() return secret() end
                C_Item.GetItemIconByID, C_Item.GetItemQualityByID = function() return nil end, function() return secret() end
                C_MajorFactions.GetMajorFactionProgressionInfo = function() return { renownLevel = secret(), renownReputationEarned = secret() } end
                C_CurrencyInfo.GetCurrencyInfo, C_Item.GetItemCount, _G.GetMoney = function() return secret() end, function() return secret() end, function() return secret() end
                C_Item.GetItemInfo = function() return secret() end
                Window:RefreshCurrent()
                C_MajorFactions.GetMajorFactionProgressionInfo, C_CurrencyInfo.GetCurrencyInfo = function() return nil end, function() return nil end
                Window:RefreshCurrent()
                _G.UnitLevel, _G.UnitClass, _G.UnitFactionGroup = savedReads.level, savedReads.class, savedReads.faction
                C_Item.GetItemIconByID, C_Item.GetItemQualityByID, C_Item.GetItemInfo = savedReads.icon, savedReads.quality, savedReads.itemInfo
                C_MajorFactions.GetMajorFactionProgressionInfo, C_CurrencyInfo.GetCurrencyInfo = savedReads.info, savedReads.currency
                C_Item.GetItemCount, _G.GetMoney = savedReads.count, savedReads.money
            end
            check(#mock.handledErrors == errorsBefore, "gear: nothing raises when every client read is nil or secret: " .. tostring(mock.handledErrors[errorsBefore + 1]))

            -- put it back
            HL.GetBuyableNow, HL.GetHonorCapAdvice, HL.GetGoalsTotals, HL.GetAllGoalsProgress = save.buyable, save.advice, save.totals, save.allGoals
            HL.GetRankUnlocks, Rank.GetInfo, HL.GetVendorStock, HL.GetVendorFor = save.unlocks, save.rankInfo, save.stock, save.vendorFor
            HL.ShowVendorForItem, HL.ShowVendorOnMap = save.showForItem, save.showOnMap
            char.goals, char.history = save.goals, save.history
            S.windowGoal, S.windowVendor, S.windowVendorClass, S.windowTab = save.goal, save.vendor, save.class, "overview"
            mock.level, mock.currencies[1792].quantity, mock.money, mock.bagContents = save.level, save.honor, save.money, save.bags
            mock.rank.level, mock.rank.earned, mock.rank.threshold = 3, 120, 1050
            mock.rankWindow.cap, mock.rankWindow.prevCap, mock.rankWindow.week = 5, 3, 2
            Gear.mode, Gear.request = "goals", nil
            Window:Hide()
        end)()

        -- ═══ Battlegrounds: the kit's Stack, FixedText and Sequence, and the fourth screen ═══
        -- (a function of its own: the enclosing function is near Lua's limit of 200 locals)
        ;(function()
            local Kit, Vend, BG = HL.Kit, HL.GearVendors, HL.BattlegroundsScreen
            local S = HonorLogDB.settings
            local db = HL.db
            local save = { history = db.char.history, ghistory = db.global.history, model = HL.GetBattlegroundModel, days = HL.GetHonorByDay,
                hours = HL.GetWinRateByHour, rankText = HL.DescribeRankPoints, honorText = HL.DescribeHonor, tab = S.windowTab,
                bg = S.windowBattleground, result = S.windowResult, view = S.viewMode,
                count = C_Item.GetItemCount, currency = C_CurrencyInfo.GetCurrencyInfo, money = _G.GetMoney }
            local function textColor(fs) local c = fs.__textColor return c and { c[1], c[2], c[3] } end
            local function same(c, rgb) return c and c[1] == rgb[1] and c[2] == rgb[2] and c[3] == rgb[3] end
            local function click(f) f.__scripts.OnClick(f, "LeftButton") end
            local function tipLines()
                local t = {}
                for _, l in ipairs(mock.tip.lines) do t[#t + 1] = l.text end
                return t
            end
            local function tipText() return table.concat(tipLines(), "\n") end
            local function noErrors(label, fn)
                local before = #mock.handledErrors
                fn()
                check(#mock.handledErrors == before, label .. ": " .. tostring(mock.handledErrors[before + 1]))
            end
            local function hasLabel(chart, key, text)
                local list = chart.honorLogLabels[key] or {}
                for i = 1, chart.honorLogLabelsUsed[key] or 0 do
                    if list[i]:GetText() == text then return true end
                end
                return false
            end
            S.windowBattleground, S.windowResult, S.viewMode = "all", "all", "character"

            -- ── Kit:FixedText and Kit:Stack: the Gear screens' pieces, now in the kit ──
            local holder = CreateFrame("Frame", nil, UIParent)
            local fixed = Kit:FixedText(holder, "value", 120)
            check(fixed.__wrapWidth == 120 and Vend.fixedText(holder, "grey", 50).__wrapWidth == 50, "kit: FixedText is a one-line text of a set width, and the Gear screens use it")
            local made, updated = 0, 0
            local function stackMakers(rowHeight)
                return { a = { create = function() made = made + 1 end, update = function() updated = updated + 1 end } }, rowHeight
            end
            local makers = stackMakers()
            local kitStack, vendStack = Kit:Stack(holder, makers), Vend.Stack(holder, makers)
            local entries = { { kind = "a", height = 20 }, { kind = "a", height = 30 } }
            check(kitStack:SetData(entries) == 50 and vendStack:SetData(entries) == 50 and kitStack.count == 2 and #kitStack.pools.a == 2 and made == 4 and updated == 4,
                "kit: Stack lays rows out and returns their height; the Gear screens' Stack is the same")
            kitStack:SetData({ { kind = "a", height = 20 } })
            check(kitStack.count == 1 and not kitStack.pools.a[2]:IsShown() and kitStack.pools.a[1]:IsShown() and made == 4, "kit: Stack hides the rows it no longer needs and makes none twice")

            -- ── Kit:Sequence ──
            local seq = Kit:Sequence(holder, 10)
            check(#seq.honorLogSquares == 10 and seq.honorLogShown == 0 and not seq.honorLogSquares[1]:IsShown(), "sequence: ten squares, none shown before results")
            seq:SetResults({ "W", "L", "D", "X" })
            local sq = seq.honorLogSquares
            check(seq.honorLogShown == 4 and sq[1]:IsShown() and sq[4]:IsShown() and not sq[5]:IsShown() and not sq[10]:IsShown(), "sequence: four results show four squares, the rest are hidden")
            check(sq[1].honorLogLetter:GetText() == "W" and sq[2].honorLogLetter:GetText() == "L" and sq[3].honorLogLetter:GetText() == "D" and sq[4].honorLogLetter:GetText() == "X", "sequence: each square carries its letter, oldest at the left")
            check(same(textColor(sq[1].honorLogLetter), Kit.COLORS.green) and same(textColor(sq[2].honorLogLetter), Kit.COLORS.red)
                and same(textColor(sq[3].honorLogLetter), Kit.COLORS.grey) and same(textColor(sq[4].honorLogLetter), Kit.COLORS.orange), "sequence: green, red, grey and orange")
            check(sq[1].honorLogTint.__color and sq[1].honorLogTint.__color[2] > sq[1].honorLogTint.__color[1] and sq[2].honorLogTint.__color[1] > sq[2].honorLogTint.__color[2], "sequence: the square is tinted in its colour")
            local framesBefore2 = #mock.frames
            for _ = 1, 10 do seq:SetResults({ "W", "L", "D", "X", "W", "W" }) end
            check(#mock.frames == framesBefore2 and seq.honorLogShown == 6, "sequence: nothing is made after the first build")
            seq:SetResults({ "L", "L", "W", "W", "W", "W", "W", "W", "W", "W", "D", "X" })
            check(seq.honorLogShown == 10 and sq[1].honorLogLetter:GetText() == "W" and sq[10].honorLogLetter:GetText() == "X", "sequence: more results than squares keep the newest")
            seq:SetResults({ "W", "?", "L" })
            check(seq.honorLogShown == 2 and sq[2].honorLogLetter:GetText() == "L", "sequence: a letter that is not a result is skipped")
            seq:SetResults(nil)
            check(seq.honorLogShown == 0 and not sq[1]:IsShown(), "sequence: nothing hides every square")
            seq.__scripts.OnEnter(seq)
            check(tipText():find("W win, L loss, D draw, X left early", 1, true) and mock.tip.owner == seq, "sequence: the tooltip says what the letters mean")
            seq.__scripts.OnLeave(seq)
            check(not mock.tip.shown, "sequence: the tooltip goes away")

            -- ── the number and date helpers ──
            check(BG.Short(0) == "0" and BG.Short(999) == "999" and BG.Short(1234) == "1.2k" and BG.Short(1000) == "1k" and BG.Short(184000) == "184k"
                and BG.Short(1200000) == "1.2m" and BG.Short(12500000) == "12m" and BG.Short(nil) == "-" and BG.Short("x") == "-", "numbers: shortened as 184k and 1.2m, a missing one is a dash")
            local nowT = date("*t", time())
            local function at(daysBack, hour, min) return time({ year = nowT.year, month = nowT.month, day = nowT.day - daysBack, hour = hour, min = min }) end
            check(BG.When(at(0, 21, 14)) == "Today 21:14" and BG.When(at(1, 18, 2)) == "Yesterday 18:02", "when: Today and Yesterday with the time")
            check(BG.When(at(5, 21, 14)) == date("%b %d ", at(5, 21, 14)) .. "21:14" and BG.When(nil) == "-", "when: another day is the date and the time, a missing one a dash")

            -- ── the screen, over stubbed models ──
            local models = {
                AV = { bgType = "AV", name = "Alterac Valley", played = 31, wins = 17, losses = 12, draws = 1, left = 1, winRate = 58.6, honorPerGame = 1234.4,
                    avgDuration = 1352, sequence = { "W", "L", "W", "D", "X", "W", "W", "L", "W", "W" }, pointsPerWin = 52.4, pointsPerLoss = 18, marksHeld = 12 },
                WSG = { bgType = "WSG", name = "Warsong Gulch", played = 9, wins = 5, losses = 2, draws = 0, left = 2, winRate = 71.4, honorPerGame = 400,
                    avgDuration = 600, sequence = { "W", "W", "L", "X", "X" }, pointsPerWin = 40, marksHeld = 0 },
                AB = { bgType = "AB", name = "Arathi Basin", played = 2, wins = 0, losses = 0, draws = 2, left = 0, sequence = { "D", "D" }, marksHeld = 3 },
                DI = { bgType = "DI", name = "Darkspear Islands", played = 0, wins = 0, losses = 0, draws = 0, left = 0, sequence = {}, marksHeld = 7 },
            }
            local lastScope, modelCalls = nil, 0
            HL.GetBattlegroundModel = function(_, bg, sc) lastScope = sc modelCalls = modelCalls + 1 return models[bg] end
            local today = HL.Window and HL:GetDayKey()
            local dayList
            local function setDays(honors)
                dayList = {}
                local labels = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Today" }
                for i = 1, 7 do dayList[i] = { dayKey = tostring(i), label = labels[i], honor = honors[i] } end
            end
            setDays({ 0, 120, 0, 3400, 500, 0, 1200 })
            HL.GetHonorByDay = function() return dayList end
            local hourList
            local function setHours(spec)
                hourList = {}
                local labels = { "Night", "Morning", "Afternoon", "Evening" }
                for i = 1, 4 do
                    local played, wins = spec[i][1], spec[i][2]
                    hourList[i] = { key = "k" .. i, label = labels[i], played = played, wins = wins, winRate = played > 0 and wins / played * 100 or nil }
                end
            end
            setHours({ { 6, 2 }, { 10, 7 }, { 4, 4 }, { 0, 0 } })
            local hoursScope
            HL.GetWinRateByHour = function(_, sc) hoursScope = sc return hourList end
            db.char.history, db.global.history = {}, {}

            local errorsBefore = #mock.handledErrors
            Window:Show("battlegrounds")
            check(#mock.handledErrors == errorsBefore, "battlegrounds: it builds and draws without an error: " .. tostring(mock.handledErrors[errorsBefore + 1]))
            local scr = Window.frames.battlegrounds
            local P = scr.honorLogParts
            check(scr and Window.current == "battlegrounds" and S.windowTab == "battlegrounds" and Window:GetScreen("battlegrounds").title == "Battlegrounds" and Window:GetScreen("battlegrounds").order == 4,
                "tabs: Battlegrounds is a screen of its own with order 4")
            check(Window.screens[3].key == "gear" and Window.screens[4].key == "battlegrounds" and Window.tabs.list[4].honorLogKey == "battlegrounds" and Window.tabs.list[3].honorLogKey == "gear",
                "tabs: Battlegrounds comes after Gear goals")
            check(S.windowBattleground == "all" and S.windowResult == "all", "settings: both filters default to all")

            -- cards
            local cards = P.cards
            check(#cards == #HL.BG_ORDER and cards[1].bgType == "AV" and cards[4].bgType == "DI" and cards[1].root:GetWidth() == 211 and cards[1].root:GetHeight() == 132, "cards: one per battleground, side by side at equal widths")
            local av = cards[1]
            check(av.name:GetText() == "Alterac Valley" and av.name.__wrapWidth == 125 and av.mark.honorLogBG == "AV" and av.mark:GetWidth() == 20, "cards: the head has the battleground's mark and its name in a fixed width")
            check(av.heldText:GetText() == "12" and av.heldText.__wrapWidth == 36, "cards: the marks held")
            av.held.__scripts.OnEnter(av.held)
            check(tipText() == "In your bags", "cards: the marks tooltip: " .. tipText())
            check(av.record:GetText() == "17 - 12" and av.record:IsShown() and not av.none:IsShown(), "cards: the record, large")
            check(av.extras.honorLogStyle == "grey" and av.extras:GetText() == "1 draw, 1 left" and av.extras:IsShown() and av.extras.__wrapWidth == 191 - av.record:GetStringWidth() - 8,
                "cards: draws and games left early in grey beside the record, in the room it leaves")
            -- a long record is never cut: the extras give way and the tooltip keeps them (the mock measures a
            -- text at 6 px a character, so the record has to be very long to need the width)
            local avWins, avLosses = models.AV.wins, models.AV.losses
            models.AV.wins, models.AV.losses = 12345678901, 1234567890
            Window:RefreshCurrent()
            check(av.record:GetText() == "12345678901 - 1234567890" and av.record.__wrapWidth == nil and not av.extras:IsShown(), "cards: a record that needs the width is whole and hides the extras beside it")
            av.button.__scripts.OnEnter(av.button)
            check(tipText():find("1 draw, 1 left", 1, true), "cards: ...and the card's tooltip still has them: " .. tipText())
            av.button.__scripts.OnLeave(av.button)
            models.AV.wins, models.AV.losses = avWins, avLosses
            Window:RefreshCurrent()
            check(av.record:GetText() == "17 - 12" and av.extras:IsShown(), "cards: the extras come back when there is room")
            check(av.seq.honorLogShown == 10 and av.seq.honorLogSquares[1].honorLogLetter:GetText() == "W" and av.seq.honorLogSquares[5].honorLogLetter:GetText() == "X", "cards: the last results as a sequence")
            check(av.lines[1].label:GetText() == "Win rate" and av.lines[1].value:GetText() == "59%" and av.lines[2].label:GetText() == "Honor a game" and av.lines[2].value:GetText() == "1,234"
                and av.lines[3].label:GetText() == "Average length" and av.lines[3].value:GetText() == HL:FormatDuration(1352), "cards: win rate, honor a game, average length")
            check(av.rank:GetText() == "Rank points: 52 a win, 18 a loss" and av.rank.honorLogStyle == "grey", "cards: rank points both measured: " .. tostring(av.rank:GetText()))
            check(av.lines[1].value.__wrapWidth == 91 and av.lines[1].label.__wrapWidth == 100 and av.rank.__wrapWidth == 191, "cards: fixed widths that fit a 211 px card")
            local wsg, ab, di = cards[2], cards[3], cards[4]
            check(wsg.record:GetText() == "5 - 2" and wsg.extras:GetText() == "2 left" and wsg.rank:GetText() == "Rank points: 40 a win, not measured", "cards: left games alone, one side of the rank points measured: " .. tostring(wsg.rank:GetText()))
            check(ab.record:GetText() == "0 - 0" and ab.extras:GetText() == "2 draws" and ab.lines[1].value:GetText() == "-" and ab.lines[2].value:GetText() == "-" and ab.lines[3].value:GetText() == "-"
                and same(textColor(ab.lines[1].value), Kit.COLORS.grey) and ab.rank:GetText() == "Rank points not measured yet", "cards: no decided game gives dashes, no rank points 'not measured yet'")
            check(not di.record:IsShown() and not di.seq:IsShown() and not di.rank:IsShown() and not di.lines[1].value:IsShown() and not di.extras:IsShown() and di.none:IsShown() and di.none:GetText() == "No games yet."
                and di.name:GetText() == "Darkspear Islands" and di.heldText:GetText() == "7", "cards: a battleground with no games has its head and 'No games yet.'")
            models.WSG.pointsPerWin, models.WSG.pointsPerLoss = nil, 18.4
            Window:RefreshCurrent()
            check(wsg.rank:GetText() == "Rank points: not measured, 18 a loss", "cards: only the loss side measured: " .. tostring(wsg.rank:GetText()))
            models.WSG.pointsPerWin, models.WSG.pointsPerLoss = 40, nil
            check(lastScope == "character" and modelCalls >= 4, "cards: the models are read for the saved scope")

            -- a click filters the table
            check(not av.wash:IsShown() and not av.edges[1]:IsShown(), "cards: no card is chosen to begin with")
            av.button.__scripts.OnEnter(av.button)
            check(tipLines()[1] == "Alterac Valley" and tipLines()[2] == "Click to show only these games", "cards: the tooltip says what a click does: " .. tipText())
            click(wsg.button)
            check(S.windowBattleground == "WSG" and wsg.wash:IsShown() and wsg.edges[1]:IsShown() and wsg.edges[4]:IsShown() and not av.wash:IsShown() and not av.edges[2]:IsShown(), "cards: a click chooses the battleground, with a gold edge and a wash")
            check(P.games.bgChips.honorLogChosen == "WSG", "cards: the games table's battleground chip follows")
            click(wsg.button)
            check(S.windowBattleground == "all" and not wsg.wash:IsShown() and not wsg.edges[1]:IsShown() and P.games.bgChips.honorLogChosen == "all", "cards: a second click clears the filter")
            click(av.button)
            click(wsg.button)
            check(S.windowBattleground == "WSG" and not av.wash:IsShown(), "cards: a click on another card switches to it")
            click(wsg.button)

            -- honor by day
            local days = P.days
            local chart = days.chart
            check(chart.honorLogRectsUsed == 8, "days: a baseline and seven bars: " .. chart.honorLogRectsUsed)
            local bars = {}
            for i = 1, 7 do bars[i] = chart.honorLogRects[i + 1] end
            check(bars[1].__height == 1 and bars[3].__height == 1 and bars[6].__height == 1 and bars[4].__height == 56 and bars[2].__height > 1 and bars[2].__height < bars[5].__height and bars[5].__height < bars[4].__height,
                "days: a zero day is a 1 px line, the biggest bar is full height and the others follow in proportion")
            check(same(bars[7].__color, { 1, 0.82, 0 }) and bars[4].__color[1] == 0.55 and bars[4].__color[3] == 0.1 and bars[1].__color[1] == 0.55, "days: today's bar is gold, the others a dimmer gold")
            check(bars[1].__points[1][4] < bars[2].__points[1][4] and bars[6].__points[1][4] < bars[7].__points[1][4], "days: the oldest day is at the left")
            check(hasLabel(chart, "grey/grey", "Mon") and hasLabel(chart, "grey/grey", "Thu") and hasLabel(chart, "grey/gold", "Today"), "days: the day's label under each bar, today's in gold")
            check(hasLabel(chart, "grey/grey", "3,400") and hasLabel(chart, "grey/grey", "120") and hasLabel(chart, "grey/grey", "500") and hasLabel(chart, "grey/gold", "1,200"), "days: the amount above each bar that is not zero")
            check(chart.honorLogLabelsUsed["grey/grey"] == 6 + 3 and chart.honorLogLabelsUsed["grey/gold"] == 2, "days: no amount for a zero day (" .. tostring(chart.honorLogLabelsUsed["grey/grey"]) .. ")")
            check(days.total:GetText() == "7 days: 5,220 honor" and days.total:IsShown() and not days.empty:IsShown() and days.header.Label:GetText() == "Honor by day", "days: the header's total: " .. tostring(days.total:GetText()))
            local framesN, rectsN, labelsN = #mock.frames, #chart.honorLogRects, 0
            for _, list in pairs(chart.honorLogLabels) do labelsN = labelsN + #list end
            for _ = 1, 10 do Window:RefreshCurrent() end
            local labelsAfter = 0
            for _, list in pairs(chart.honorLogLabels) do labelsAfter = labelsAfter + #list end
            check(#mock.frames == framesN and #chart.honorLogRects == rectsN and labelsAfter == labelsN and chart.honorLogRectsUsed == 8, "days: ten refreshes make no more bars, labels or frames")
            setDays({ 0, 0, 0, 0, 0, 0, 0 })
            Window:RefreshCurrent()
            check(days.empty:IsShown() and days.empty:GetText() == "No honor in the last 7 days." and not days.total:IsShown() and chart.honorLogRectsUsed == 0 and days.empty.honorLogStyle == "grey", "days: no honor at all is a grey sentence")
            setDays({ 0, 0, 0, 0, 0, 0, 40 })
            Window:RefreshCurrent()
            check(not days.empty:IsShown() and chart.honorLogRects[8].__height == 56 and days.total:GetText() == "7 days: 40 honor", "days: only today's honor still draws the chart")
            setDays({ 0, 120, 0, 3400, 500, 0, 1200 })

            -- best hours
            local hours = P.hours
            local function hourRow(i) local r = hours.rows[i] return r.label:GetText(), r.percent:GetText(), r.games:GetText(), r.best:IsShown() end
            check(hours.header.Label:GetText() == "Your best hours" and hoursScope == "character", "hours: the header, read for the saved scope")
            local l1, p1, g1, b1 = hourRow(1)
            local l2, p2, g2, b2 = hourRow(2)
            local l3, p3, g3, b3 = hourRow(3)
            local l4, p4, g4, b4 = hourRow(4)
            check(l1 == "Night" and p1 == "33%" and g1 == "6 games" and not b1 and l2 == "Morning" and p2 == "70%" and g2 == "10 games" and b2, "hours: label, percent, games, and the best word on the best bucket")
            check(p3 == "100%" and not b3 and l4 == "Evening" and p4 == "-" and g4 == "0 games" and not b4, "hours: a bucket under 5 decided games is never best, an empty one is a dash")
            check(hours.rows[2].bar.honorLogFraction == 0.7 and hours.rows[4].bar.honorLogFraction == 0 and hours.rows[2].best:GetText() == "best" and hours.rows[2].best.honorLogStyle == "label"
                and same(textColor(hours.rows[4].percent), Kit.COLORS.grey), "hours: the bar is the win rate, 'best' is gold, a dash is grey")
            check(hours.foot:IsShown() and hours.foot:GetText() == "Win rate by when you played, 20 games." and not hours.few:IsShown() and hours.rows[1]:IsShown(), "hours: the foot says how many games it rests on")
            setHours({ { 3, 2 }, { 2, 0 }, { 0, 0 }, { 0, 0 } })
            Window:RefreshCurrent()
            local _, _, _, bb1 = hourRow(1)
            local _, _, _, bb2 = hourRow(2)
            check(hours.rows[1]:IsShown() and hours.foot:GetText() == "Win rate by when you played, 5 games." and not bb1 and not bb2, "hours: five decided games show the rows, but no bucket is best below 5")
            setHours({ { 5, 1 }, { 5, 4 }, { 5, 4 }, { 0, 0 } })
            Window:RefreshCurrent()
            local _, _, _, cb1 = hourRow(1)
            local _, _, _, cb2 = hourRow(2)
            local _, _, _, cb3 = hourRow(3)
            check(not cb1 and cb2 and not cb3, "hours: a tie goes to the earlier bucket, with 5 games it can be best")
            setHours({ { 1, 1 }, { 2, 1 }, { 1, 0 }, { 0, 0 } })
            Window:RefreshCurrent()
            check(not hours.rows[1]:IsShown() and not hours.rows[2]:IsShown() and not hours.foot:IsShown() and hours.few:IsShown() and hours.few:GetText() == "Play a few more games to see your best hours.", "hours: under 5 decided games it asks for a few more")
            setHours({ { 1, 1 }, { 4, 2 }, { 0, 0 }, { 0, 0 } })
            Window:RefreshCurrent()
            check(hours.rows[1].games:GetText() == "1 game", "hours: one game is '1 game'")
            setHours({ { 6, 2 }, { 10, 7 }, { 4, 4 }, { 0, 0 } })
            Window:RefreshCurrent()

            -- the games table: columns of a full record and a bare one
            local G = P.games
            local function game(extra)
                local g = { bgType = "AV", result = "win", win = true, duration = 1352, honor = 450, marks = 3, rankPoints = 100, rankState = "earned", timestamp = at(0, 21, 14),
                    kb = 5, hk = 20, deaths = 2, damage = 184000, healing = 1200000 }
                for k, v in pairs(extra or {}) do g[k] = v end
                return g
            end
            local full = game({ joinedInProgress = true })
            local bare = { bgType = "WSG", win = false, duration = 300, honor = 120, marks = 1, timestamp = at(1, 18, 2) }
            local drawn = game({ bgType = "AB", result = "draw", timestamp = at(5, 21, 14), rankPoints = 0, rankState = "zero", honorCapped = true })
            local left = game({ bgType = "DI", result = "left", win = false, timestamp = at(0, 20, 0) })
            db.char.history = { full, bare, drawn, left }
            db.global.history = { full }
            S.windowBattleground, S.windowResult = "all", "all"
            Window:RefreshCurrent()
            local pool = G.stack.pools.game
            check(G.stack.count == 4 and #pool == 4 and G.foot:GetText() == "4 games" and not G.empty:IsShown() and G.area.honorLogContentHeight == 80, "games: four rows of 20, and '4 games' under them")
            local r1, r2, r3, r4 = pool[1], pool[2], pool[3], pool[4]
            local c = r1.cells
            check(c.when:GetText() == "Today 21:14" and c.bg:GetText() == "AV" and c.result:GetText() == "Win" and same(textColor(c.result), Kit.COLORS.green) and c.length:GetText() == HL:FormatDuration(1352), "games: when, battleground, result word in green, length")
            check(c.honor:GetText() == "450" and c.rank:GetText() == "+100" and c.marks.icon.honorLogBG == "AV" and c.marks.icon:IsShown() and c.marks.text:GetText() == "3", "games: honor, rank points, marks with their icon")
            check(c.kb:GetText() == "5" and c.hk:GetText() == "20" and c.deaths:GetText() == "2" and c.damage:GetText() == "184k" and c.healing:GetText() == "1.2m", "games: KB, HK, deaths, and large numbers shortened")
            local b = r2.cells
            check(b.when:GetText() == "Yesterday 18:02" and b.bg:GetText() == "WSG" and b.result:GetText() == "Loss" and same(textColor(b.result), Kit.COLORS.red) and b.length:GetText() == HL:FormatDuration(300)
                and b.honor:GetText() == "120" and b.marks.text:GetText() == "1", "games: a record from before 2.0 shows what it has")
            check(b.rank:GetText() == "-" and b.kb:GetText() == "-" and b.hk:GetText() == "-" and b.deaths:GetText() == "-" and b.damage:GetText() == "-" and b.healing:GetText() == "-" and same(textColor(b.kb), Kit.COLORS.grey),
                "games: a number the record does not have is a dash")
            check(r3.cells.result:GetText() == "Draw" and same(textColor(r3.cells.result), Kit.COLORS.grey) and r4.cells.result:GetText() == "Left" and same(textColor(r4.cells.result), Kit.COLORS.orange)
                and r3.cells.when:GetText() == date("%b %d ", at(5, 21, 14)) .. "21:14" and r3.cells.honor:GetText() == "450*" and r3.cells.rank:GetText() == "0", "games: Draw in grey, Left in orange, an older day, a capped game's star, 0 rank points")
            local blank = { bgType = "AV" }
            db.char.history = { blank }
            Window:RefreshCurrent()
            local e = pool[1].cells
            check(e.when:GetText() == "-" and e.result:GetText() == "Loss" and e.length:GetText() == "-" and e.honor:GetText() == "-" and not e.marks.icon:IsShown() and e.marks.text:GetText() == "-" and e.damage:GetText() == "-",
                "games: a record with no field but its battleground draws dashes")
            db.char.history = { full, bare, drawn, left }
            Window:RefreshCurrent()
            check(r1.stripe:IsShown() == false and r2.stripe:IsShown() == true, "games: every second row is striped")
            local lastColumn = BG.COLUMNS[#BG.COLUMNS]
            check(lastColumn.x + lastColumn.w <= 830 and c.when.__wrapWidth == 104 and c.honor.__wrapWidth == 58 and c.damage.__wrapWidth == 64 and G.titles[1]:GetText() == "When" and G.titles[2]:GetText() == "Battleground"
                and G.titles[12]:GetText() == "Healing" and G.titles[6]:GetText() == "Rank pts", "games: the columns fit the table, and their titles")
            check(G.area:GetWidth() == 830 and G.area:GetHeight() == 154, "games: the scroll area")

            -- tooltips of a row
            r1.__scripts.OnEnter(r1)
            local t = tipLines()
            check(t[1] == "Alterac Valley" and t[2]:find("^%d%d%d%d%-%d%d%-%d%d 21:14$") and t[3] == "+100" and t[4] == "+450 honor" and t[5] == "Joined in progress" and mock.tip.owner == r1, "games: the row tooltip: " .. tipText())
            r2.__scripts.OnEnter(r2)
            check(tipText():find("Warsong Gulch", 1, true) and not tipText():find("Joined in progress", 1, true), "games: no 'Joined in progress' for a game that was not")
            HL.DescribeRankPoints, HL.DescribeHonor = function() return nil end, function() return nil end
            r1.__scripts.OnEnter(r1)
            check(#tipLines() == 3 and tipLines()[3] == "Joined in progress", "games: without the two descriptions the tooltip has the rest: " .. tipText())
            r2.__scripts.OnEnter(r2)
            check(#tipLines() == 2, "games: a bare tooltip is the name and the date")
            HL.DescribeRankPoints, HL.DescribeHonor = save.rankText, save.honorText
            r1.__scripts.OnLeave(r1)
            check(not mock.tip.shown, "games: the tooltip goes away")

            -- filters
            local function chipClick(chips, key)
                for _, bt in ipairs(chips.honorLogButtons) do
                    if bt:IsShown() and bt.honorLogKey == key then click(bt) return end
                end
                error("no chip " .. key)
            end
            local function rowBgs()
                local out = {}
                for i = 1, G.stack.count do out[#out + 1] = pool[i].cells.bg:GetText() end
                return table.concat(out, ",")
            end
            check(G.bgChips.honorLogButtons[1]:GetText() == "All" and G.bgChips.honorLogButtons[2]:GetText() == "AV" and G.bgChips.honorLogButtons[3]:GetText() == "WSG"
                and G.bgChips.honorLogButtons[5]:GetText() == "DI" and G.resultChips.honorLogButtons[2]:GetText() == "Wins" and G.resultChips.honorLogButtons[3]:GetText() == "Losses"
                and G.scopeChips.honorLogButtons[1]:GetText() == "This character" and G.scopeChips.honorLogButtons[2]:GetText() == "Account", "filters: the chips' words")
            chipClick(G.bgChips, "AV")
            check(S.windowBattleground == "AV" and rowBgs() == "AV", "filters: a battleground alone: " .. rowBgs())
            check(G.foot:GetText() == "1 game", "filters: the foot counts what matches (1 game)")
            chipClick(G.bgChips, "all")
            chipClick(G.resultChips, "win")
            check(S.windowResult == "win" and rowBgs() == "AV" and G.foot:GetText() == "1 game", "filters: wins alone")
            chipClick(G.resultChips, "loss")
            check(S.windowResult == "loss" and rowBgs() == "WSG", "filters: losses alone (a record without a result is read as a loss; a game left early is not a loss): " .. rowBgs())
            chipClick(G.resultChips, "all")
            chipClick(G.bgChips, "WSG")
            chipClick(G.resultChips, "win")
            check(rowBgs() == "" and G.empty:IsShown() and G.empty:GetText() == "No games match." and G.stack.count == 0 and G.foot:GetText() == "", "filters: combined, and nothing matches")
            chipClick(G.resultChips, "loss")
            check(rowBgs() == "WSG" and not G.empty:IsShown(), "filters: combined, one game")
            check(G.bgChips.honorLogChosen == "WSG" and G.resultChips.honorLogChosen == "loss" and S.windowBattleground == "WSG" and S.windowResult == "loss", "filters: both choices are saved")

            -- the saved filters come back with the window
            S.windowTab = "battlegrounds"
            Window:Hide()
            Window.frame, Window.frames, Window.tabs, Window.current, _G.HonorLogWindow = nil, {}, nil, nil, nil
            Window:Show()
            P = Window.frames.battlegrounds.honorLogParts
            G = P.games
            pool = G.stack.pools.game
            check(Window.current == "battlegrounds" and G.bgChips.honorLogChosen == "WSG" and G.resultChips.honorLogChosen == "loss" and G.stack.count == 1 and P.cards[2].wash:IsShown(), "tabs: the saved tab and the saved filters restore the screen")
            S.windowBattleground, S.windowResult = "XX", "nonsense"
            Window:RefreshCurrent()
            check(G.bgChips.honorLogChosen == "all" and G.resultChips.honorLogChosen == "all" and G.stack.count == 4 and S.windowBattleground == "XX", "filters: an unknown saved choice reads as all and is not rewritten")
            S.windowBattleground, S.windowResult = "all", "all"

            -- the scope chips
            lastScope, hoursScope = nil, nil
            chipClick(G.scopeChips, "account")
            check(S.viewMode == "account" and lastScope == "account" and hoursScope == "account" and G.stack.count == 1 and G.foot:GetText() == "1 game" and G.scopeChips.honorLogChosen == "account",
                "scope: Account sets the view mode and the cards, the hours and the table follow")
            chipClick(G.scopeChips, "character")
            check(S.viewMode == "character" and lastScope == "character" and hoursScope == "character" and G.stack.count == 4 and G.scopeChips.honorLogChosen == "character", "scope: This character goes back")

            -- the limit, the foot, the scroll position
            local many = {}
            for i = 1, 130 do many[i] = game({ timestamp = at(0, 12, 0) - i * 60, bgType = i % 2 == 0 and "AV" or "AB", honor = i }) end
            db.char.history = many
            Window:RefreshCurrent()
            check(G.stack.count == 100 and #pool == 100 and G.foot:GetText() == "Showing the latest 100 of 130. Export has them all." and G.area.honorLogContentHeight == 2000, "limit: 100 rows, and the foot says there are more")
            check(pool[1].cells.honor:GetText() == "1" and pool[100].cells.honor:GetText() == "100", "limit: the newest first")
            chipClick(G.bgChips, "AV")
            check(G.stack.count == 65 and G.foot:GetText() == "65 games" and #pool == 100, "limit: a filter under 100 shows them all with a plain foot")
            chipClick(G.bgChips, "all")
            G.area:SetVerticalScroll(400)
            Window:RefreshCurrent()
            check(G.area:GetVerticalScroll() == 400, "scroll: a refresh keeps the position")
            Window:OnDataChanged()
            check(G.area:GetVerticalScroll() == 400, "scroll: so does a recorded game")
            chipClick(G.resultChips, "win")
            check(G.area:GetVerticalScroll() == 0, "scroll: a filter change goes back to the top")
            G.area:SetVerticalScroll(300)
            click(P.cards[1].button)
            check(G.area:GetVerticalScroll() == 0, "scroll: so does a click on a card")
            click(P.cards[1].button)
            chipClick(G.resultChips, "all")
            local hundred = {}
            for i = 1, 100 do hundred[i] = many[i] end
            db.char.history = hundred
            Window:RefreshCurrent()
            check(G.foot:GetText() == "100 games", "limit: exactly 100 is a plain count")
            db.char.history, db.global.history = {}, {}
            Window:RefreshCurrent()
            check(G.empty:IsShown() and G.empty:GetText() == "No games recorded yet. HonorLog records every battleground you finish." and G.stack.count == 0 and G.foot:GetText() == "", "empty: no game at all")
            check(G.area.honorLogContentHeight == 0, "empty: the table is empty")
            db.char.history = { full }
            Window:RefreshCurrent()
            check(not G.empty:IsShown() and G.stack.count == 1, "empty: a game brings the table back")

            -- Export and Overview's way in
            if _G.HonorLogExportFrame then _G.HonorLogExportFrame:Hide() end
            click(G.export)
            check(_G.HonorLogExportFrame and _G.HonorLogExportFrame:IsShown(), "export: the button opens the export frame")
            _G.HonorLogExportFrame:Hide()
            Window:Show("overview")
            local ovGames = Window.frames.overview.honorLogParts.games
            check(ovGames.all:GetText() == "All games" and ovGames.all:GetWidth() == 80, "overview: Recent games has an All games button")
            click(ovGames.all)
            check(Window.current == "battlegrounds" and Window.frames.battlegrounds:IsShown() and not Window.frames.overview:IsShown(), "overview: All games opens the Battlegrounds screen")

            -- hygiene
            do
                local inScreen = function(f)
                    local hops = 0
                    while f and hops < 40 do
                        if f == Window.frames.battlegrounds then return true end
                        f, hops = f.__parent, hops + 1
                    end
                    return false
                end
                local onUpdates, foreign, templated = 0, {}, 0
                for _, f in ipairs(mock.frames) do
                    if inScreen(f) then
                        if f.__scripts.OnUpdate then onUpdates = onUpdates + 1 end
                        if f.__template then
                            templated = templated + 1
                            for k in pairs(f) do
                                if type(k) == "string" and not k:find("^__") and not k:find("^honorLog") and k ~= "ScrollBar" then foreign[#foreign + 1] = k end
                            end
                        end
                    end
                end
                check(onUpdates == 0, "battlegrounds: no OnUpdate anywhere (" .. onUpdates .. ")")
                check(templated > 10 and #foreign == 0, "battlegrounds: only honorLog names are added to template frames: " .. table.concat(foreign, ","))
            end

            -- every client read gone or secret; every model answering nothing
            local errorsMid = #mock.handledErrors
            local secret = mock.newSecret
            HL.GetBattlegroundModel, HL.GetHonorByDay, HL.GetWinRateByHour = save.model, save.days, save.hours
            db.char.history = { full, blank, { win = true }, {} }
            C_Item.GetItemCount, C_CurrencyInfo.GetCurrencyInfo, _G.GetMoney = function() return secret() end, function() return secret() end, function() return secret() end
            Window:RefreshCurrent()
            C_Item.GetItemCount, C_CurrencyInfo.GetCurrencyInfo = function() return nil end, function() return nil end
            Window:RefreshCurrent()
            HL.GetBattlegroundModel, HL.GetHonorByDay, HL.GetWinRateByHour = function() return nil end, function() return nil end, function() return nil end
            Window:RefreshCurrent()
            HL.GetBattlegroundModel, HL.GetHonorByDay, HL.GetWinRateByHour = function() error("model gone") end, function() error("days gone") end, function() error("hours gone") end
            noErrors("battlegrounds: a model that raises draws what it can", function() Window:RefreshCurrent() end)
            -- a part that fails outside the guarded reads is reported and leaves the others drawn
            HL.GetBattlegroundModel, HL.GetHonorByDay, HL.GetWinRateByHour = function(_, bg) return models[bg] end, function() return dayList end, function() return hourList end
            local realFormat = HL.Rank.FormatNumber
            HL.Rank.FormatNumber = function() error("format gone") end
            Window:RefreshCurrent()
            HL.Rank.FormatNumber = realFormat
            check(#mock.handledErrors > errorsMid and P.hours.foot:GetText() == "Win rate by when you played, 20 games." and P.cards[1].record:GetText() == "17 - 12",
                "battlegrounds: a failing part is reported and the others are still drawn")
            for i = #mock.handledErrors, errorsMid + 1, -1 do mock.handledErrors[i] = nil end
            HL.GetBattlegroundModel, HL.GetHonorByDay, HL.GetWinRateByHour = save.model, save.days, save.hours
            C_Item.GetItemCount, C_CurrencyInfo.GetCurrencyInfo, _G.GetMoney = save.count, save.currency, save.money
            -- the real models, over real saved stats
            db.char.battlegrounds.AB = HL.NewBGStats()
            local abStats = db.char.battlegrounds.AB
            abStats.played, abStats.wins, abStats.losses, abStats.totalDuration, abStats.honorLifetime = 3, 2, 1, 1800, 900
            db.char.history = { game({ bgType = "AB", result = "win" }), game({ bgType = "AB", result = "loss", rankPoints = 0, rankState = "zero" }), game({ bgType = "AB", result = "win" }) }
            Window:RefreshCurrent()
            local abCard = P.cards[3]
            check(abCard.record:GetText() == "2 - 1" and abCard.lines[1].value:GetText() == "67%" and abCard.lines[2].value:GetText() == "300" and abCard.lines[3].value:GetText() == HL:FormatDuration(600)
                and abCard.seq.honorLogSquares[1].honorLogLetter:GetText() == "W" and abCard.seq.honorLogShown == 3 and abCard.rank:GetText():find("^Rank points"), "real model: a card over saved stats: " .. tostring(abCard.record:GetText()) .. " / " .. tostring(abCard.rank:GetText()))
            abStats.played, abStats.wins, abStats.losses, abStats.totalDuration, abStats.honorLifetime = 0, 0, 0, 0, 0
            check(#mock.handledErrors == errorsMid, "battlegrounds: nothing raises when every client read is nil or secret: " .. tostring(mock.handledErrors[errorsMid + 1]))

            -- put it back
            HL.GetBattlegroundModel, HL.GetHonorByDay, HL.GetWinRateByHour = save.model, save.days, save.hours
            HL.DescribeRankPoints, HL.DescribeHonor = save.rankText, save.honorText
            db.char.history, db.global.history = save.history, save.ghistory
            S.windowTab, S.windowBattleground, S.windowResult, S.viewMode = "overview", save.bg, save.result, save.view
            Window:Hide()
        end)()

        -- ═══ Quests: the data, the shared read, the hand-in store, the list and the fifth screen ═══
        -- (a function of its own: the enclosing function is near Lua's limit of 200 locals)
        ;(function()
            local Q, Kit, Window = HL.Quests, HL.Kit, HL.Window
            local S = HL.db.settings
            local secret = mock.newSecret
            local errorsStart = #mock.handledErrors
            local function textColor(fs) local c = fs.__textColor return c and { c[1], c[2], c[3] } end
            local function same(c, rgb) return c and c[1] == rgb[1] and c[2] == rgb[2] and c[3] == rgb[3] end
            local function click(f) f.__scripts.OnClick(f, "LeftButton") end
            local function tipText()
                local t = {}
                for _, l in ipairs(mock.tip.lines) do t[#t + 1] = l.text end
                return table.concat(t, "\n")
            end
            local DB = HL.QuestDB
            local function ids(pred)
                local out = {}
                for id, q in pairs(DB) do if pred(q, id) then out[#out + 1] = id end end
                table.sort(out)
                return out
            end
            local function listIds(list)
                local out = {}
                for _, r in ipairs(list) do out[r.id] = r end
                return out
            end
            local prevScripts = mock.runShowScripts
            mock.runShowScripts = true
            local qlSaved, gSaved = {}, { GetQuestID = _G.GetQuestID, UnitLevel = _G.UnitLevel, GetRealZoneText = _G.GetRealZoneText,
                GetSubZoneText = _G.GetSubZoneText, GetMoney = _G.GetMoney, UnitFactionGroup = _G.UnitFactionGroup,
                count = C_Item.GetItemCount, currency = C_CurrencyInfo.GetCurrencyInfo, progress = C_MajorFactions.GetMajorFactionProgressionInfo }
            for k, v in pairs(C_QuestLog) do qlSaved[k] = v end
            local saved = { level = mock.level, faction = mock.faction, week = mock.rankWindow.week, money = mock.money,
                honor = mock.currencies[1792].quantity, earned = mock.rank.earned, wsg = mock.bagItems[20558], ab = mock.bagItems[20559],
                tab = S.windowTab, time = _G.time, npcGuid = mock.npcGuid, units = mock.units, map = mock.map, zone = mock.zone, subzone = mock.subzone }

            -- ── the data ──
            do
                local count, bad = 0, 0
                for _, q in pairs(DB) do
                    count = count + 1
                    local okBg = ({ AV = 1, WSG = 1, AB = 1, DI = 1, ALL = 1, SEASON = 1 })[q.bg]
                    local okKind = ({ offer = 1, ["repeat"] = 1, weekly = 1 })[q.kind]
                    if not (okBg and okKind and type(q.name) == "string") then bad = bad + 1 end
                end
                local source = 0
                for line in io.lines(ROOT .. "/tools/quests_source.json") do
                    if line:find('^%s*{"id":') then source = source + 1 end
                end
                check(count == source and count == 208 and bad == 0, "quest data: " .. count .. " quests, the source file has " .. source .. ", every row has a known battleground and kind")
                local weeklyOk = true
                for week = 1, 10 do
                    local q = DB[96911 + week]
                    if not (q and q.kind == "weekly" and q.week == week and q.bg == "SEASON" and q.faction == nil and q.name == "Field of Honor: Week " .. week) then weeklyOk = false end
                end
                check(weeklyOk and #ids(function(q) return q.kind == "weekly" end) == 10, "quest data: the ten weekly quests with their weeks")
                check(DB[5892].bg == "AV" and DB[5892].faction == "Alliance" and DB[5892].level == 55 and DB[5893].faction == "Horde"
                    and DB[8367].bg == "ALL" and DB[8367].faction == "Horde" and DB[8371].faction == "Alliance" and DB[99108].bg == "SEASON" and DB[96913].bg == "SEASON",
                    "quest data: known ids by battleground and faction")
            end

            -- ── the shared read ──
            mock.currencies[1792].quantity, mock.rank.earned, mock.money = 5000, 200, 99900
            mock.bagItems[20558], mock.bagItems[20559] = 12, 3
            local st = Q.ReadState()
            check(st.honor == 5000 and st.rank == HL.Rank:TotalForRank(mock.rank.level) + 200 and st.money == 99900 and st.marks.WSG == 12 and st.marks.AB == 3 and st.marks.AV == 0,
                "shared read: honor, rank points as one total, money and marks")
            local realInfo, realProgress, realCount, realMoney = C_CurrencyInfo.GetCurrencyInfo, C_MajorFactions.GetMajorFactionProgressionInfo, C_Item.GetItemCount, _G.GetMoney
            C_CurrencyInfo.GetCurrencyInfo, C_MajorFactions.GetMajorFactionProgressionInfo = function() return secret() end, function() return { renownLevel = secret(), renownReputationEarned = 5 } end
            C_Item.GetItemCount, _G.GetMoney = function() return secret() end, function() return nil end
            st = Q.ReadState()
            check(st.honor == nil and st.rank == nil and st.money == nil and next(st.marks) == nil, "shared read: a secret or missing answer is nil")
            C_CurrencyInfo.GetCurrencyInfo, C_MajorFactions.GetMajorFactionProgressionInfo, C_Item.GetItemCount, _G.GetMoney = realInfo, realProgress, realCount, realMoney

            -- ── the hand-in store ──
            HonorLogDB.questRewards = nil
            mock.npcGuid = "Creature-0-1-2-3-13777-0000"
            mock.units = { npc = { name = "Sergeant Durgen" } }
            mock.map, mock.zone, mock.subzone = { id = 1459, x = 0.368, y = 0.772 }, "Alterac Mountains", "Dun Baldar"
            mock.level = 58
            local function setUp() mock.currencies[1792].quantity, mock.rank.earned, mock.bagItems[20558], mock.money = 5000, 200, 12, 99900 end
            local function handIn(id, withWindow, gains)
                gains = gains or {}
                mock.deferTimers = true
                if withWindow then
                    mock.quest = { id = id }
                    mock.fireEvent("QUEST_COMPLETE")
                end
                mock.currencies[1792].quantity = mock.currencies[1792].quantity + (gains.honor or 0)
                mock.rank.earned = mock.rank.earned + (gains.rank or 0)
                mock.bagItems[20558] = mock.bagItems[20558] + (gains.marks or 0)
                mock.money = mock.money + (gains.money or 0)
                mock.fireEvent("QUEST_TURNED_IN", id, gains.xp or 0, gains.money or 0)
                mock.flushTimers()
                mock.deferTimers = false
                mock.quest = nil
            end
            setUp()
            handIn(5892, true, { honor = 1200, rank = 500, marks = 3, money = 4500, xp = 250 })
            local rec = HonorLogDB.questRewards[5892]
            check(rec and rec.count == 1 and rec.honor == 1200 and rec.rank == 500 and rec.marks.WSG == 3 and rec.money == 4500 and rec.xp == 250 and rec.level == 58 and type(rec.last) == "number",
                "hand-in with its window: every measured value is stored")
            check(rec.place.name == "Sergeant Durgen" and rec.place.npc == 13777 and rec.place.map == 1459 and rec.place.x == 36.8 and rec.place.y == 77.2
                and rec.place.zone == "Alterac Mountains" and rec.place.subzone == "Dun Baldar", "hand-in with its window: the place is stored")
            handIn(5892, true, { honor = 1300 })
            rec = HonorLogDB.questRewards[5892]
            check(rec.count == 2 and rec.honor == 1300 and rec.rank == 500 and rec.marks.WSG == 3, "a second hand-in raises the count and keeps what it did not measure")
            handIn(5893, false, { honor = 700 })
            rec = HonorLogDB.questRewards[5893]
            check(rec and rec.count == 1 and rec.honor == nil and rec.rank == nil and rec.place == nil and rec.level == 58, "hand-in without its window: counted only")
            handIn(9999, false, { honor = 700 })
            check(HonorLogDB.questRewards[9999] == nil, "an unlisted quest handed in without the window is not stored")
            handIn(9998, true, { honor = 800, rank = 5 })
            check(HonorLogDB.questRewards[9998] and HonorLogDB.questRewards[9998].honor == 800 and HonorLogDB.questRewards[9998].count == 1, "an unlisted quest that paid honor is learned")
            handIn(9997, true, { money = 100, xp = 90 })
            check(HonorLogDB.questRewards[9997] == nil, "an unlisted quest that paid no honor, rank points or marks is not stored")
            -- a quest that costs marks pays nothing in marks
            handIn(9996, true, { marks = -2 })
            check(HonorLogDB.questRewards[9996] == nil, "marks taken away are not a payment")
            -- secret and missing readings: left out, nothing raised
            C_CurrencyInfo.GetCurrencyInfo = function() return secret() end
            C_MajorFactions.GetMajorFactionProgressionInfo = function() return nil end
            local errs = #mock.handledErrors
            check(pcall(handIn, 5894, true, { honor = 5, marks = 2, xp = 7 }), "secret and missing readings raise nothing")
            C_CurrencyInfo.GetCurrencyInfo, C_MajorFactions.GetMajorFactionProgressionInfo = realInfo, realProgress
            rec = HonorLogDB.questRewards[5894]
            check(rec and rec.honor == nil and rec.rank == nil and rec.marks.WSG == 2 and rec.xp == 7 and #mock.handledErrors == errs, "secret and missing readings are left out, the rest is kept")
            mock.fireEvent("QUEST_TURNED_IN", secret(), 1, 1)
            mock.fireEvent("QUEST_TURNED_IN", nil, 1, 1)
            mock.quest = { id = secret() }
            check(pcall(mock.fireEvent, "QUEST_COMPLETE"), "a secret quest id raises nothing")
            mock.quest = nil
            -- the limit
            HonorLogDB.questRewards = {}
            local tick = 0
            _G.time = function() tick = tick + 1 return 1000 + tick end
            for i = 1, 410 do handIn(20000 + i, true, { honor = 10 }) end
            local n = 0
            for _ in pairs(HonorLogDB.questRewards) do n = n + 1 end
            check(n == Q.KEPT and Q.KEPT == 400 and HonorLogDB.questRewards[20001] == nil and HonorLogDB.questRewards[20010] == nil and HonorLogDB.questRewards[20011] ~= nil and HonorLogDB.questRewards[20410] ~= nil,
                "the store keeps 400 quests, oldest hand-in dropped first: " .. n)
            _G.time = saved.time
            HonorLogDB.questRewards = nil
            mock.level, mock.rank.earned = saved.level, saved.earned

            -- ── Rank:GetWeeklyQuest reads the new store before the probe's ──
            do
                mock.rankWindow.week = 2
                local probeStore = HonorLogDB.probe
                HonorLogDB.probe = { quests = { [96913] = { last = { rank = 90, t = 0 } } } }
                check(HL.Rank:GetWeeklyQuest().measured == 90, "weekly quest: the probe's store still answers when the new one is empty")
                HonorLogDB.questRewards = { [96912] = { rank = 75, last = 10 } }
                check(HL.Rank:GetWeeklyQuest().measured == 75, "weekly quest: the new store comes first, any week's quest")
                HonorLogDB.questRewards[96914] = { rank = 60, last = 50 }
                check(HL.Rank:GetWeeklyQuest().measured == 60, "weekly quest: the most recent of the ten")
                HonorLogDB.questRewards[96913] = { rank = 110, last = 1 }
                check(HL.Rank:GetWeeklyQuest().measured == 110, "weekly quest: this week's own hand-in wins")
                HonorLogDB.questRewards = { [96913] = { rank = 0, last = 1 } }
                check(HL.Rank:GetWeeklyQuest().measured == 90, "weekly quest: a hand-in that gave 0 falls back to the probe's store")
                HonorLogDB.questRewards, HonorLogDB.probe = nil, probeStore
            end

            -- ── the list ──
            mock.faction, mock.level, mock.rankWindow.week = "Alliance", 60, 2
            mock.questTitles, mock.questLog, mock.questsDone = {}, {}, {}
            HonorLogDB.questRewards = nil
            local list = Q:GetList()
            local byId = listIds(list)
            local allian = true
            for _, r in ipairs(list) do if DB[r.id].faction == "Horde" then allian = false end end
            check(#list > 0 and allian and byId[5893] == nil and byId[8371] ~= nil and byId[8367] == nil, "list: the player's faction and the quests with none")
            mock.faction = "Horde"
            check(listIds(Q:GetList())[5893] == nil and listIds(Q:GetList({ levels = "all" }))[5893] ~= nil and listIds(Q:GetList({ levels = "all" }))[5892] == nil, "list: a Horde player gets the Horde quests")
            mock.faction = "Alliance"
            local lv35 = ids(function(q) return q.level == 35 and (q.faction == "Alliance" or not q.faction) end)[1]
            local lv39 = ids(function(q) return q.level == 39 and (q.faction == "Alliance" or not q.faction) end)[1]
            local lv59 = ids(function(q) return q.level == 59 and (q.faction == "Alliance" or not q.faction) end)[1]
            local lv55 = 5892
            local lv60 = ids(function(q) return q.level == 60 and (q.faction == "Alliance" or not q.faction) end)[1]
            local nolv = 6846
            local function shows(id, level, filters)
                mock.level = level
                return listIds(Q:GetList(filters))[id] ~= nil
            end
            check(lv35 and lv39 and lv59 and lv60, "list: the test data has quests of levels 35, 39, 59 and 60")
            check(shows(lv35, 35) and shows(lv39, 35) and not shows(lv59, 35) and not shows(lv60, 35) and not shows(lv55, 35), "level range: at level 35 the 30s quests only")
            check(shows(lv59, 59) and shows(lv55, 59) and not shows(lv60, 59) and not shows(lv35, 59), "level range: at level 59 the 50s quests, not the level 60 ones")
            check(shows(lv60, 60) and not shows(lv59, 60) and not shows(lv55, 60), "level range: at level 60 only level 60 quests")
            check(shows(nolv, 35) and shows(nolv, 60), "level range: a quest with no level is always listed")
            check(shows(lv59, 35, { levels = "all" }) and shows(lv60, 35, { levels = "all" }), "level range: All levels lists every row")
            mock.questLog[lv59] = { objectives = {} }
            local logged = shows(lv59, 35)
            mock.questLog[lv59] = nil
            mock.questsDone[lv59] = true
            local doneShown = shows(lv59, 35)
            mock.questsDone[lv59] = nil
            HonorLogDB.questRewards = { [lv59] = { count = 1, last = 1 } }
            local paidShown = shows(lv59, 35)
            HonorLogDB.questRewards = nil
            check(logged and doneShown and paidShown and not shows(lv59, 35), "level range: a quest in the log, done or paid is listed at any level")
            mock.level = 60
            -- the weekly rule
            local function weeklies(week)
                mock.rankWindow.week = week
                local got = {}
                for id = 96912, 96921 do if listIds(Q:GetList())[id] then got[#got + 1] = id end end
                return got
            end
            check(#weeklies(2) == 2 and weeklies(2)[2] == 96913 and #weeklies(1) == 1 and #weeklies(10) == 10, "weekly rule: the current week and the weeks before it")
            mock.rankWindow.noData = true
            check(#weeklies(2) == 0, "weekly rule: no season data lists none")
            mock.rankWindow.noData, mock.rankWindow.week = false, 2
            -- states, titles, objectives, places and order
            local a, b, c, d2 = 8371, nil, 6781, nil
            local openId = ids(function(q, id) return (q.faction == "Alliance" or not q.faction) and q.level == 60 and id ~= 8371 and id ~= 6781 end)
            b, d2 = openId[1], openId[2]
            mock.questLog[a] = { complete = true, objectives = { { text = "Bring 10 supplies", finished = true } } }
            mock.questLog[b] = { complete = false, objectives = { { text = "Kill 5 wolves", finished = true }, { text = "Gather 3 hides", finished = false }, { text = "", finished = false } } }
            mock.questsDone[c] = true
            mock.questTitles[b] = "Wolf Hunt"
            HonorLogDB.questRewards = { [d2] = { count = 2, last = 5, honor = 100, place = { name = "Quartermaster", map = 1459, x = 36.8, y = 77.2, zone = "Alterac Mountains" } },
                [c] = { count = 1, last = 4, place = { name = "No Position", map = 1459 } } }
            list = Q:GetList()
            byId = listIds(list)
            check(byId[a].state == "ready" and byId[a].ready and byId[a].inLog and byId[b].state == "log" and not byId[b].ready and byId[c].state == "done" and byId[c].done and byId[d2].state == "open",
                "list: the four states")
            check(byId[b].title == "Wolf Hunt" and byId[a].title == DB[a].name, "list: the client's title, else the data's name")
            check(#byId[b].objectives == 2 and byId[b].objectives[1].text == "Kill 5 wolves" and byId[b].objectives[1].finished == true and byId[b].objectives[2].finished == false
                and byId[d2].objectives == nil and byId[c].objectives == nil, "list: objectives only for a quest in the log")
            check(byId[d2].place and byId[d2].place.map == 1459 and byId[d2].place.x == 36.8 and byId[d2].place.name == "Quartermaster" and byId[d2].paid.honor == 100
                and byId[c].place == nil and byId[c].paid and byId[a].paid == nil and byId[a].place == nil, "list: the place only with a map and a position, paid only when stored")
            local rank, lastState, orderOk = { ready = 1, log = 2, open = 3, done = 4 }, 0, true
            for _, r in ipairs(list) do
                if rank[r.state] < lastState then orderOk = false end
                lastState = rank[r.state]
            end
            check(orderOk and list[1].id == a and list[2].id == b, "list: ready, then in the log, then open, then done")
            local avRows, otherRows = Q:GetList({ bg = "AV", levels = "all" }), Q:GetList({ bg = "other", levels = "all" })
            local avOk, otherOk = #avRows > 0, #otherRows > 0
            for _, r in ipairs(avRows) do if r.bg ~= "AV" then avOk = false end end
            for _, r in ipairs(otherRows) do if r.bg ~= "ALL" and r.bg ~= "SEASON" then otherOk = false end end
            check(avOk and otherOk and #Q:GetList({ bg = "all", levels = "all" }) > #avRows + #otherRows, "list: the battleground filter, and Other is ALL and SEASON together")
            local counts = Q:GetCounts(list)
            check(counts.ready == 1 and counts.log == 1 and counts.done == 1 and counts.open == #list - 3, "counts: how many of each state")
            check(Q:GetCounts(nil).ready == 0 and Q:GetCounts({}).open == 0, "counts: an empty list")
            -- order inside a state: battleground, level, title, id
            local sorted = true
            local prev
            for _, r in ipairs(list) do
                if r.state == "open" then
                    if prev and prev.bg == r.bg and (prev.level or 1000) > (r.level or 1000) then sorted = false end
                    prev = r
                end
            end
            check(sorted, "list: inside a state by battleground, then level")
            -- every client read gone or secret
            local liveQL = C_QuestLog
            for k in pairs(qlSaved) do liveQL[k] = function() return secret() end end
            check(pcall(Q.GetList, Q), "list: secret quest log answers raise nothing")
            _G.C_QuestLog = nil
            check(pcall(Q.GetList, Q) and #Q:GetList() > 0, "list: no quest log at all still lists the data")
            _G.C_QuestLog = liveQL
            for k, v in pairs(qlSaved) do liveQL[k] = v end
            _G.UnitFactionGroup = function() return secret() end
            check(pcall(Q.GetList, Q), "list: a secret faction raises nothing")
            _G.UnitFactionGroup = gSaved.UnitFactionGroup

            -- ── the screen ──
            mock.level = 60
            S.windowQuestBG, S.windowQuestLevels, S.windowQuest = nil, nil, nil
            local errBefore = #mock.handledErrors
            Window:Show("quests")
            check(#mock.handledErrors == errBefore, "quests: it builds and draws without an error: " .. tostring(mock.handledErrors[errBefore + 1]))
            local scr = Window.frames.quests
            local P = scr.honorLogParts
            check(scr and Window.current == "quests" and S.windowTab == "quests" and Window:GetScreen("quests").title == "Quests" and Window:GetScreen("quests").order == 5
                and Window.screens[5].key == "quests" and Window.tabs.list[5].honorLogKey == "quests" and Window.tabs.list[4].honorLogKey == "battlegrounds", "tabs: Quests comes after Battlegrounds")
            S.windowTab = "overview"
            Window:Hide()
            Window:Show()
            check(Window.current == "overview", "tabs: the saved tab opens the window")
            S.windowTab = "quests"
            Window.frame, Window.frames, Window.tabs, Window.current, _G.HonorLogWindow = nil, {}, nil, nil, nil
            Window:Show()
            check(Window.current == "quests" and Window.frames.quests:IsShown(), "tabs: a saved Quests tab restores the screen")
            scr = Window.frames.quests
            P = scr.honorLogParts
            -- chips and their saved settings
            local bgBtn = P.bgChips.honorLogButtons
            check(#bgBtn == 6 and bgBtn[1]:GetText() == "All" and bgBtn[2].honorLogKey == "AV" and bgBtn[2]:GetText() == HL:GetBGShortName("AV") and bgBtn[5].honorLogKey == "DI" and bgBtn[6].honorLogKey == "other" and bgBtn[6]:GetText() == "Other",
                "chips: All, the four short names and Other")
            check(P.bgChips.honorLogChosen == "all" and P.levelChips.honorLogChosen == "mine" and S.windowQuestBG == nil, "chips: a missing key reads as All and Your level range, and is not saved by a read")
            check(P.levelChips.honorLogButtons[1]:GetText() == "Your level range" and P.levelChips.honorLogButtons[2]:GetText() == "All levels", "chips: the level range chips")
            -- list groups and rows
            local pools = P.list.stack.pools
            local function titles()
                local t = {}
                for i, row in ipairs(pools.title or {}) do if row:IsShown() then t[#t + 1] = row.text:GetText() end end
                return table.concat(t, "|")
            end
            check(titles() == "Ready to hand in|In your log|Not picked up|Done", "list: a group title over each non-empty group: " .. titles())
            local function rowOf(id)
                for _, row in ipairs(pools.quest or {}) do
                    if row:IsShown() and row.honorLogEntry.quest.id == id then return row end
                end
            end
            local rReady, rLog, rOpen, rDone = rowOf(a), rowOf(b), rowOf(d2), rowOf(c)
            check(rReady and rLog and rOpen and rDone and rReady:GetHeight() == 40, "list: a row of each state, 40 high")
            check(rReady.ready:IsShown() and rReady.ready:GetText() == "!" and same(textColor(rReady.ready), Kit.COLORS.gold) and not rReady.dot:IsShown() and not rReady.tick:IsShown(), "row: ready is a gold exclamation mark")
            check(rLog.dot:IsShown() and not rLog.ready:IsShown() and not rLog.tick:IsShown() and not rLog.ring[1]:IsShown(), "row: in the log is a white dot")
            check(rOpen.ring[1]:IsShown() and not rOpen.dot:IsShown() and not rOpen.ready:IsShown() and not rOpen.tick:IsShown(), "row: open is a hollow grey ring")
            check(rDone.tick:IsShown() and rDone.tick.__texture == "Interface\\RaidFrame\\ReadyCheck-Ready" and not rDone.ring[1]:IsShown(), "row: done is a tick")
            check(rLog.title:GetText() == "Wolf Hunt" and same(textColor(rLog.title), Kit.COLORS.white) and same(textColor(rDone.title), Kit.COLORS.grey) and rLog.title.__wrapWidth == 268,
                "row: the title on one line, white, grey when done, in a fixed width")
            check(rLog.sub:GetText() == HL:GetBGShortName(DB[b].bg) .. " \194\183 Level 60 \194\183 Gather 3 hides" and rOpen.sub:GetText() == HL:GetBGShortName(DB[d2].bg) .. " \194\183 Level 60",
                "row: under the title the battleground, the level and the first unfinished objective: " .. tostring(rLog.sub:GetText()))
            check(rOpen.paid[1].text:GetText() == "+100 honor" and same(textColor(rOpen.paid[1].text), Kit.COLORS.white) and not rOpen.paid[1].icon:IsShown() and not rOpen.paid[2].text:IsShown(),
                "row: what it paid, in short")
            check(rLog.paid[1].text:GetText() == "not measured yet" and same(textColor(rLog.paid[1].text), Kit.COLORS.grey) and rDone.paid[1].text:GetText() == "nothing measured",
                "row: grey not measured yet, or nothing measured for a hand-in that paid none of the three")
            HonorLogDB.questRewards[d2] = { count = 1, last = 5, honor = 100, rank = 500, marks = { WSG = 3, AV = 2 } }
            Window:RefreshCurrent()
            rOpen = rowOf(d2)
            check(rOpen.paid[1].text:GetText() == "+500 rank" and rOpen.paid[2].text:GetText() == "+100 honor" and not rOpen.paid[1].icon:IsShown(), "row: the largest two payments")
            HonorLogDB.questRewards[d2] = { count = 1, last = 5, marks = { WSG = 3, AV = 7 } }
            Window:RefreshCurrent()
            rOpen = rowOf(d2)
            check(rOpen.paid[1].icon:IsShown() and rOpen.paid[1].icon.honorLogBG == "AV" and rOpen.paid[1].text:GetText() == "+7" and rOpen.paid[2].icon.honorLogBG == "WSG" and rOpen.paid[2].text:GetText() == "+3",
                "row: a mark icon with the count")
            -- the chosen row
            check(S.windowQuest == nil and P.list.stack.pools.quest[1].honorLogEntry.chosen == true and rReady.wash:IsShown() and rReady.edge:IsShown() and not rLog.wash:IsShown(),
                "chosen: with nothing saved the first row, with the wash and the gold edge")
            local lookups = 0
            local realList = Q.GetList
            Q.GetList = function(...) lookups = lookups + 1 return realList(...) end
            click(rowOf(b).click)
            Q.GetList = realList
            check(S.windowQuest == b and lookups == 0 and rowOf(b).wash:IsShown() and rowOf(b).edge:IsShown() and not rowOf(a).wash:IsShown(), "chosen: a click saves it and draws it without asking the client again")
            rowOf(b).click.__scripts.OnEnter(rowOf(b).click)
            check(mock.tip.lines[1].text == "Wolf Hunt" and mock.tip.owner == rowOf(b), "row: the tooltip has the full title")
            rowOf(b).click.__scripts.OnLeave(rowOf(b).click)
            S.windowQuest = 123456
            Window:RefreshCurrent()
            check(S.windowQuest == 123456 and rowOf(a).wash:IsShown() and not rowOf(b).wash:IsShown(), "chosen: a saved quest that is not listed falls back to the first row")
            S.windowQuest = b
            Window:RefreshCurrent()
            -- the detail
            local D = P.detail
            check(D.title:GetText() == "Wolf Hunt" and D.title.__wrapWidth == 316 and D.state:GetText() == "In your log." and D.sub:GetText() == HL:GetBGDisplayName(DB[b].bg) .. " \194\183 Level 60",
                "detail: the title, the battleground and level, and one sentence for the state")
            D.titleHit.__scripts.OnEnter(D.titleHit)
            check(mock.tip.lines[1].text == "Wolf Hunt", "detail: the title's tooltip")
            check(D.objects[1]:IsShown() and D.objects[1].text:GetText() == "Kill 5 wolves" and D.objects[1].tick:IsShown() and D.objects[2].text:GetText() == "Gather 3 hides" and not D.objects[2].tick:IsShown()
                and D.objects[2].edges[1]:IsShown() and not D.objects[3]:IsShown() and not D.objNone:IsShown(), "detail: each objective, a tick when finished and an empty box when not")
            D.objects[2].__scripts.OnEnter(D.objects[2])
            check(mock.tip.lines[1].text == "Gather 3 hides", "detail: an objective's tooltip has its full text")
            check(D.paidNone:IsShown() and D.paidNone:GetText() == "Hand it in once and HonorLog remembers what it pays." and D.placeNone:IsShown()
                and D.placeNone:GetText() == "Hand it in once and HonorLog remembers where." and not D.link:IsShown() and not D.map:IsShown(), "detail: nothing stored, the two grey sentences")
            check(D.foot:GetText() == "HonorLog lists the PvP quests the game data names. Some may not be offered at your level.", "detail: the foot")
            click(rowOf(d2).click)
            D = P.detail
            check(D.state:GetText() == "Not picked up yet." and D.objNone:IsShown() and D.objNone:GetText() == "Pick it up to see its objectives." and not D.objects[1]:IsShown(), "detail: an open quest shows how to see its objectives")
            HonorLogDB.questRewards[d2] = { count = 3, last = time(), honor = 1200, rank = 500, marks = { WSG = 3 }, money = 12345, xp = 880,
                place = { name = "Quartermaster Fiery-Name", map = 1459, x = 36.8, y = 77.2, zone = "Alterac Mountains", subzone = "Dun Baldar" } }
            Window:RefreshCurrent()
            D = P.detail
            local lines = {}
            for _, p in ipairs(D.paidLines) do if p.label:IsShown() then lines[#lines + 1] = p.label:GetText() .. "=" .. p.value:GetText() end end
            check(table.concat(lines, ";") == "Honor=1,200;Rank points=500;" .. HL:GetBGShortName("WSG") .. " marks=3;Money=1g 23s 45c;Experience=880", "detail: label and value lines for what was measured: " .. table.concat(lines, ";"))
            check(D.paidLines[3].icon:IsShown() and D.paidLines[3].icon.honorLogBG == "WSG" and not D.paidLines[1].icon:IsShown(), "detail: the marks line has the mark icon")
            check(D.paidFoot:GetText() == "Handed in 3 times, last on " .. date("%Y-%m-%d", HonorLogDB.questRewards[d2].last) .. "." and not D.paidNone:IsShown(), "detail: how often and when")
            check(D.link:IsShown() and D.link.honorLogName:GetText() == "Quartermaster Fiery-Name" and D.zone:GetText() == "Alterac Mountains \194\183 Dun Baldar" and D.map:IsShown() and D.map:GetText() == "Show on map" and not D.placeNone:IsShown(),
                "detail: the place, its zone in grey and the Show on map button")
            local shownPlace
            local realShow = HL.ShowPlaceOnMap
            HL.ShowPlaceOnMap = function(_, place) shownPlace = place return true end
            click(D.map)
            check(shownPlace and shownPlace.map == 1459 and shownPlace.x == 36.8 and shownPlace.y == 77.2 and shownPlace.name == "Quartermaster Fiery-Name", "detail: Show on map calls the map with the stored place")
            shownPlace = nil
            click(D.link)
            check(shownPlace and shownPlace.map == 1459, "detail: the place link does the same")
            HL.ShowPlaceOnMap = realShow
            HonorLogDB.questRewards[d2].count = 1
            Window:RefreshCurrent()
            check(P.detail.paidFoot:GetText():find("^Handed in once, on "), "detail: a single hand-in reads as once")
            -- filters: saved, and they send the list back to the top
            for _, btn in ipairs(P.bgChips.honorLogButtons) do if btn.honorLogKey == "AV" then P.list.area:SetVerticalScroll(40) click(btn) end end
            check(S.windowQuestBG == "AV" and P.bgChips.honorLogChosen == "AV" and P.list.area:GetVerticalScroll() == 0, "filters: the battleground is saved and the list goes back to the top")
            local onlyAV = true
            for _, row in ipairs(pools.quest) do if row:IsShown() and row.honorLogEntry.quest.bg ~= "AV" then onlyAV = false end end
            check(onlyAV, "filters: only that battleground's rows")
            click(P.levelChips.honorLogButtons[2])
            check(S.windowQuestLevels == "all" and P.levelChips.honorLogChosen == "all", "filters: the level setting is saved")
            click(P.bgChips.honorLogButtons[1])
            check(S.windowQuestBG == "all" and #P.list.stack.pools.quest > 40, "filters: All levels lists many more rows")
            P.list.area:SetVerticalScroll(60)
            Window:RefreshCurrent()
            check(P.list.area:GetVerticalScroll() == 60, "scroll: kept across a refresh")
            click(P.levelChips.honorLogButtons[1])
            check(P.list.area:GetVerticalScroll() == 0, "scroll: reset when a filter changes")
            S.windowQuestBG, S.windowQuestLevels = "bogus", "bogus"
            Window:RefreshCurrent()
            check(P.bgChips.honorLogChosen == "all" and P.levelChips.honorLogChosen == "mine", "filters: an unknown saved value reads as the default")
            S.windowQuestBG, S.windowQuestLevels = "all", "mine"
            -- a hand-in rebuilds the list while this screen is open
            local rebuilt = 0
            Q.GetList = function(...) rebuilt = rebuilt + 1 return realList(...) end
            HonorLogDB.questRewards = nil
            HL:Fire("HonorLog_QuestPaid", d2)
            check(rebuilt == 1 and rowOf(d2).paid[1].text:GetText() == "not measured yet", "rebuilt: a stored hand-in refreshes the open screen")
            -- the quest log's event: one refresh a second at most, only while this is the open screen
            rebuilt = 0
            mock.deferTimers = true
            local timersBefore = #mock.timers
            check(scr.honorLogEvents.__events.QUEST_LOG_UPDATE == true, "log event: registered while the screen is drawn")
            for _ = 1, 5 do mock.fireEvent("QUEST_LOG_UPDATE") end
            check(rebuilt == 0 and #mock.timers == timersBefore + 1, "log event: a burst is answered by one timer")
            mock.questLog[d2] = { complete = true, objectives = {} }
            mock.flushTimers()
            check(rebuilt == 1 and rowOf(d2).ready:IsShown(), "log event: the screen is refreshed once, with the new state")
            mock.fireEvent("QUEST_LOG_UPDATE")
            Window:Show("overview")
            mock.flushTimers()
            check(rebuilt == 1, "log event: nothing is refreshed once another screen is open")
            mock.fireEvent("QUEST_LOG_UPDATE")
            mock.flushTimers()
            mock.deferTimers = false
            check(rebuilt == 1 and next(scr.honorLogEvents.__events) == nil, "log event: the screen stops listening when hidden")
            rebuilt = 0
            HL:Fire("HonorLog_QuestPaid", d2)
            check(rebuilt == 0, "rebuilt: a hand-in refreshes nothing while another screen is open")
            Q.GetList = realList
            mock.questLog = {}
            Window:Show("quests")
            -- empty
            local realDB = HL.QuestDB
            HL.QuestDB = {}
            Window:RefreshCurrent()
            check(P.list.empty:IsShown() and P.list.empty:GetText() == "No quests match." and P.detail.empty:IsShown() and P.detail.empty:GetText() == "Choose a quest on the left."
                and not P.detail.title:IsShown() and titles() == "", "empty: both grey sentences, no group titles")
            HL.QuestDB = realDB
            Window:RefreshCurrent()
            check(not P.list.empty:IsShown() and not P.detail.empty:IsShown() and P.detail.title:IsShown(), "empty: gone again with quests")
            -- long titles and objectives stay in their boxes
            mock.questTitles[b] = string.rep("Very long title ", 8)
            mock.questLog[b] = { objectives = { { text = string.rep("Slay the many creatures ", 6), finished = false } } }
            Window:RefreshCurrent()
            click(rowOf(b).click)
            check(rowOf(b).title.__wrapWidth == 268 and rowOf(b).sub.__wrapWidth == 268 and P.detail.title.__wrapWidth == 316 and P.detail.objects[1].text.__wrapWidth == 294, "widths: long texts sit in fixed widths")
            rowOf(b).click.__scripts.OnEnter(rowOf(b).click)
            check(mock.tip.lines[1].text == string.rep("Very long title ", 8), "widths: the row tooltip has the full title")
            mock.questTitles[b], mock.questLog[b] = nil, nil

            -- hygiene
            do
                local function inScreen(f)
                    local hops = 0
                    while f and hops < 40 do
                        if f == scr then return true end
                        f, hops = f.__parent, hops + 1
                    end
                    return false
                end
                local onUpdates, foreign, templated = 0, {}, 0
                for _, f in ipairs(mock.frames) do
                    if inScreen(f) then
                        if f.__scripts.OnUpdate then onUpdates = onUpdates + 1 end
                        if f.__template then
                            templated = templated + 1
                            for k in pairs(f) do
                                if type(k) == "string" and not k:find("^__") and not k:find("^honorLog") and k ~= "ScrollBar" then foreign[#foreign + 1] = k end
                            end
                        end
                    end
                end
                check(onUpdates == 0, "quests: no OnUpdate anywhere (" .. onUpdates .. ")")
                check(templated > 10 and #foreign == 0, "quests: only honorLog names are added to template frames (" .. templated .. "): " .. table.concat(foreign, ","))
                for _, file in ipairs({ "UI/Screens/Quests.lua", "Modules/Quests.lua" }) do
                    local source = io.open(ROOT .. "/" .. file):read("*a")
                    check(not source:find("OnUpdate", 1, true), "quests: " .. file .. " has no OnUpdate")
                end
            end

            -- every client read gone or secret
            local errorsMid = #mock.handledErrors
            C_Item.GetItemCount, C_CurrencyInfo.GetCurrencyInfo, _G.GetMoney = function() return secret() end, function() return secret() end, function() return secret() end
            _G.GetQuestID, _G.UnitLevel, _G.GetRealZoneText, _G.GetSubZoneText = function() return secret() end, function() return secret() end, function() return secret() end, function() return secret() end
            C_QuestLog.GetTitleForQuestID, C_QuestLog.IsOnQuest, C_QuestLog.GetQuestObjectives = function() return secret() end, function() return secret() end, function() return secret() end
            C_QuestLog.IsQuestFlaggedCompleted, C_QuestLog.IsComplete, C_QuestLog.ReadyForTurnIn = function() return secret() end, function() return secret() end, function() return secret() end
            mock.fireEvent("QUEST_COMPLETE")
            mock.fireEvent("QUEST_TURNED_IN", 5892, secret(), secret())
            Window:RefreshCurrent()
            C_QuestLog.GetTitleForQuestID, C_QuestLog.IsOnQuest, C_QuestLog.GetQuestObjectives = function() return nil end, function() return nil end, function() return nil end
            C_QuestLog.IsQuestFlaggedCompleted, C_QuestLog.IsComplete, C_QuestLog.ReadyForTurnIn = function() return nil end, function() return nil end, function() return nil end
            C_Item.GetItemCount, C_CurrencyInfo.GetCurrencyInfo = function() return nil end, function() return nil end
            _G.GetQuestID, _G.UnitLevel, _G.GetRealZoneText, _G.GetSubZoneText = function() return nil end, function() return nil end, function() return nil end, function() return nil end
            mock.fireEvent("QUEST_COMPLETE")
            mock.fireEvent("QUEST_TURNED_IN", 5892, nil, nil)
            Window:RefreshCurrent()
            check(#mock.handledErrors == errorsMid, "quests: nothing raises when every client read is nil or a secret: " .. tostring(mock.handledErrors[errorsMid + 1]))
            -- a failing part is reported and the others are still drawn
            C_QuestLog.GetTitleForQuestID = function(id) return mock.questTitles[id] end
            local realFormat = HL.Rank.FormatNumber
            HL.Rank.FormatNumber = function() error("format gone") end
            HonorLogDB.questRewards = { [d2] = { count = 1, last = 1, honor = 5 } }
            Window:RefreshCurrent()
            HL.Rank.FormatNumber = realFormat
            check(#mock.handledErrors > errorsMid and P.bgChips.honorLogChosen == "all", "quests: a failing part is reported and the others are still drawn")
            for i = #mock.handledErrors, errorsMid + 1, -1 do mock.handledErrors[i] = nil end
            check(#mock.handledErrors == errorsStart, "quests: the section left no error behind")

            -- put it back
            for k, v in pairs(qlSaved) do C_QuestLog[k] = v end
            for _, k in ipairs({ "GetQuestID", "UnitLevel", "GetRealZoneText", "GetSubZoneText", "GetMoney", "UnitFactionGroup" }) do _G[k] = gSaved[k] end
            C_Item.GetItemCount, C_CurrencyInfo.GetCurrencyInfo, C_MajorFactions.GetMajorFactionProgressionInfo = gSaved.count, gSaved.currency, gSaved.progress
            mock.runShowScripts = prevScripts
            HonorLogDB.questRewards = nil
            mock.level, mock.faction, mock.rankWindow.week, mock.money = saved.level, saved.faction, saved.week, saved.money
            mock.currencies[1792].quantity, mock.rank.earned, mock.bagItems[20558], mock.bagItems[20559] = saved.honor, saved.earned, saved.wsg, saved.ab
            mock.npcGuid, mock.units, mock.map, mock.zone, mock.subzone = saved.npcGuid, saved.units, saved.map, saved.zone, saved.subzone
            mock.questTitles, mock.questLog, mock.questsDone = {}, {}, {}
            S.windowTab, S.windowQuest, S.windowQuestBG, S.windowQuestLevels = "overview", nil, nil, nil
            Window:Hide()
        end)()

        -- ═══ Moments: Kit:Card, Announce quiet, and the report, rank-up and honor cap cards ═══
        -- (a function of its own: the enclosing function is near Lua's limit of 200 locals)
        ;(function()
            local Kit, M = HL.Kit, HL.Moments
            local S = HL.db.settings
            local db = HL.db
            local secret = mock.newSecret
            local function foreign(frame)
                local bad = {}
                for k in pairs(frame) do
                    if type(k) == "string" and not k:find("^__") and not k:find("^honorLog") then bad[#bad + 1] = k end
                end
                table.sort(bad)
                return table.concat(bad, ",")
            end
            local function noErrors(label, fn)
                local before = #mock.handledErrors
                fn()
                check(#mock.handledErrors == before, label .. ": " .. tostring(mock.handledErrors[before + 1]))
            end
            local function closeAll() for kind in pairs(M.states) do M:Close(kind) end end
            local function last(f) return f.__points and f.__points[#f.__points] end
            local save = { settings = { S.momentReport, S.momentRankUp, S.momentHonorCap, S.momentSeconds }, deferred = mock.deferTimers,
                history = db.char.history, bgs = db.char.battlegrounds, honor = HL.GetCurrentHonor, cap = HL.GetHonorCap,
                goals = HL.GetAllGoalsProgress, ready = HL.GoalReadyText, model = HL.GetBattlegroundModel, marks = HL.GetCurrentMarks,
                unlocks = HL.GetRankUnlocks, gear = HL.GetGearName, buy = HL.GetBuyableNow, advice = HL.GetHonorCapAdvice,
                showItem = HL.ShowVendorForItem, rankInfo = HL.Rank.GetInfo, pace = HL.Rank.GetPace, plan = HL.Rank.PlanToRank,
                describe = HL.DescribeRankPoints, currency = C_CurrencyInfo.GetCurrencyInfo, format = HL.Rank.FormatNumber }
            S.momentReport, S.momentRankUp, S.momentHonorCap, S.momentSeconds = true, true, true, 12
            mock.deferTimers, mock.timers, mock.combat = true, {}, false
            local framesBefore = #mock.frames

            -- ── defaults and the options ──
            check(save.settings[1] == true and save.settings[2] == true and save.settings[3] == true and save.settings[4] == 12, "moments: the saved settings start on, 12 seconds")
            for _, c in ipairs({ { "HonorLogMomentReportCheck", "momentReport" }, { "HonorLogMomentRankUpCheck", "momentRankUp" }, { "HonorLogMomentHonorCapCheck", "momentHonorCap" } }) do
                local box = _G[c[1]]
                check(box ~= nil and type(box.tooltipText) == "string" and box.tooltipText ~= "", "moments: the options have " .. c[1] .. " with a tooltip")
                rawset(box, "GetChecked", function() return false end)
                box.__scripts.OnClick(box)
                check(S[c[2]] == false, "moments: " .. c[1] .. " switches " .. c[2] .. " off")
                rawset(box, "GetChecked", function() return true end)
                box.__scripts.OnClick(box)
                check(S[c[2]] == true, "moments: " .. c[1] .. " switches " .. c[2] .. " on")
            end
            check(_G.HonorLogMomentReportCheck.Text:GetText() == "Game report card" and _G.HonorLogMomentRankUpCheck.Text:GetText() == "Rank-up card"
                and _G.HonorLogMomentHonorCapCheck.Text:GetText() == "Honor cap card", "moments: the three options are named for the cards")

            -- ── Kit:Card ──
            do
                local holder = CreateFrame("Frame", nil, UIParent)
                local card = Kit:Card("HonorLogTestCard", 300)
                check(not card:IsShown() and card.honorLogCloseTemplate == "UIPanelCloseButton" and foreign(card.honorLogClose) == "", "card: hidden, with Blizzard's close button carrying only honorLog names: " .. foreign(card.honorLogClose))
                card:SetTitle("Hello")
                check(card.honorLogTitle == "Hello" and card.honorLogTitleText:GetText() == "Hello", "card: SetTitle sets the gold title")
                check(card.honorLogBody ~= nil and card.honorLogBody.__parent == card and card.honorLogEdges and #card.honorLogEdges == 4, "card: a body frame and a 1 px edge")
                card:SetBodyHeight(100)
                check(card:GetHeight() == Kit.CARD_STRIP + 2 + 100 and card.honorLogBody:GetHeight() == 100 and card:GetWidth() == 300, "card: SetBodyHeight sizes the card")
                card:Show()
                card.honorLogClose.__scripts.OnClick(card.honorLogClose)
                check(not card:IsShown(), "card: the close button hides it")
                for _, name in ipairs(UISpecialFrames) do check(name ~= "HonorLogTestCard", "card: it is not registered for the Escape key") end
                mock.missingTemplates = { ["*"] = true }
                local plainCard = Kit:Card(nil, 300)
                mock.missingTemplates = {}
                check(plainCard.honorLogCloseTemplate == false and plainCard.honorLogClose.honorLogLabel:GetText() == "x", "card: without the template the close button is drawn with an x")
                plainCard:Show()
                plainCard.honorLogClose.__scripts.OnClick(plainCard.honorLogClose)
                check(not plainCard:IsShown(), "card: the drawn close button hides it")
                mock.hollowTemplates = { UIPanelCloseButton = true }
                local hollowCard = Kit:Card(nil, 300)
                mock.hollowTemplates = {}
                check(hollowCard.honorLogCloseTemplate == false, "card: a hollow template is treated as missing")
                check(holder ~= nil, "card: done")
            end

            -- ── Announce with and without quiet ──
            do
                local notices, errorLines, sounds = 0, 0, 0
                local realRaid, realBoss, realPlay = _G.RaidNotice_AddMessage, _G.RaidBossEmoteFrame, _G.PlaySound
                _G.RaidNotice_AddMessage, _G.RaidBossEmoteFrame = function() notices = notices + 1 end, {}
                _G.PlaySound = function() sounds = sounds + 1 end
                rawset(UIErrorsFrame, "AddMessage", function() errorLines = errorLines + 1 end)
                local before = #printed
                HL:Announce("Loud")
                check(notices == 1 and errorLines == 1 and sounds == 1 and #printed == before + 1, "announce: sound, notice, error line and chat line")
                HL:Announce("Quiet", nil, nil, nil, true)
                check(notices == 1 and errorLines == 1 and sounds == 2 and #printed == before + 2 and printed[#printed]:find("Quiet", 1, true), "announce: quiet keeps the sound and the chat line only")
                HL:Announce("False", nil, nil, nil, false)
                check(notices == 2 and errorLines == 2, "announce: quiet = false is the same as before")

                -- the moments: card on = quiet, card off = as before; the chat line always
                closeAll()
                S.momentHonorCap, S.momentRankUp = true, true
                S.honorCapWarning, db.char.honorCapWarned = true, false
                mock.currencies[1792].quantity = 24000
                notices, errorLines = 0, 0
                local lines = #printed
                HL:CheckHonorCap()
                check(notices == 0 and errorLines == 0 and printed[#printed]:find("Honor cap:", 1, true) and #printed == lines + 1, "moments: with the honor cap card on, no centre text and no error line, the chat line stays")
                check(M.states.honorCap and M.states.honorCap.card:IsShown(), "moments: the honor cap card shows on the event")
                closeAll()
                S.momentHonorCap, db.char.honorCapWarned = false, false
                HL:CheckHonorCap()
                check(notices == 1 and errorLines == 1 and not M.states.honorCap.card:IsShown(), "moments: with the honor cap card off, the centre text and the error line are as before and no card shows")
                S.momentHonorCap, db.char.honorCapWarned = true, false
                mock.currencies[1792].quantity = save.settings[3] and 18832 or 18832

                notices, errorLines = 0, 0
                db.char.rankCelebrated = 0
                lines = #printed
                HL.Rank:OnRenownChanged(2800, 9, 8)
                local rankLine
                for i = lines + 1, #printed do if printed[i]:find("Rank 9", 1, true) then rankLine = printed[i] end end
                check(notices == 0 and errorLines == 0 and rankLine, "moments: the rank-up chat line stays with the card on")
                check(M.states.rankUp and M.states.rankUp.card:IsShown() and M.states.rankUp.parts.rankNumber:GetText() == "9", "moments: the rank-up card shows on the event")
                closeAll()
                S.momentRankUp, db.char.rankCelebrated = false, 0
                HL.Rank:OnRenownChanged(2800, 10, 9)
                check(notices == 1 and errorLines == 1 and not M.states.rankUp.card:IsShown(), "moments: with the rank-up card off the notice is as before")
                S.momentRankUp = true
                db.char.rankCelebrated = 0
                _G.RaidNotice_AddMessage, _G.RaidBossEmoteFrame, _G.PlaySound = realRaid, realBoss, realPlay
                rawset(UIErrorsFrame, "AddMessage", nil)
            end

            -- ── the game recorded event, and the stack ──
            closeAll()
            HL.GetAllGoalsProgress, HL.GoalReadyText = function() return {} end, save.ready
            local rec = { bgType = "AB", result = "win", duration = 872, honor = 412, marks = 3, rankPoints = 25, rankState = "earned",
                kb = 6, hk = 20, timestamp = time(), rep = { faction = 509, gained = 200 },
                teams = { [0] = { score = 1180 }, [1] = { score = 1600 } } }
            S.momentReport = false
            HL:Fire("HonorLog_GameRecorded", rec)
            check(not (M.states.report and M.states.report.card:IsShown()), "moments: a recorded game shows no card with the report card off")
            S.momentReport = true
            HL:Fire("HonorLog_GameRecorded", rec)
            local report = M.states.report
            check(report and report.card:IsShown() and #M.order == 1, "moments: a recorded game shows the report card with it on")
            local pt = last(report.card)
            check(pt[1] == "TOP" and pt[2] == UIParent and pt[3] == "TOP" and pt[4] == 0 and pt[5] == -140, "moments: the first card hangs 140 px from the top centre")
            M:Show("rankUp", { rank = 3 })
            M:Show("honorCap", { current = 1000, cap = 25000 })
            local rank, cap = M.states.rankUp, M.states.honorCap
            local p2, p3 = last(rank.card), last(cap.card)
            check(M.order[1] == "report" and M.order[2] == "rankUp" and M.order[3] == "honorCap", "moments: cards stack in the order they were shown")
            check(p2[1] == "TOP" and p2[2] == report.card and p2[3] == "BOTTOM" and p2[5] == -8 and p3[2] == rank.card and p3[5] == -8, "moments: each card hangs 8 px under the one before")
            M:Close("report")
            pt, p2 = last(rank.card), last(cap.card)
            check(pt[2] == UIParent and pt[5] == -140 and p2[2] == rank.card and #M.order == 2 and not report.card:IsShown(), "moments: when a card closes the others move up")
            local framesCount = #mock.frames
            M:Show("rankUp", { rank = 4 })
            check(#M.order == 2 and #mock.frames == framesCount and rank.parts.rankNumber:GetText() == "4" and last(rank.card)[2] == UIParent, "moments: the same kind again replaces its content, keeps its place and builds nothing")
            closeAll()
            check(#M.order == 0 and not M:Shows("nonsense") and M:Show("nonsense") == false, "moments: unknown kinds are refused")

            -- ── a fight holds a card back ──
            do
                mock.combat = true
                check(M:Show("honorCap", { current = 24000, cap = 25000 }) == "waiting" and not M.states.honorCap.card:IsShown(), "moments: a card asked for in a fight waits")
                M:Show("honorCap", { current = 24500, cap = 25000 })
                M:Show("rankUp", { rank = 5 })
                check(not M.states.rankUp or not M.states.rankUp.card:IsShown(), "moments: the second waits too")
                mock.combat = false
                mock.fireEvent("PLAYER_REGEN_ENABLED")
                check(M.states.honorCap.card:IsShown() and M.states.rankUp.card:IsShown() and M.order[1] == "honorCap" and M.order[2] == "rankUp", "moments: both show, in order, when the fight ends")
                check(M.states.honorCap.parts.headText:GetText() == "Honor is at 24,500 / 25,000", "moments: the waiting card shows the newest data asked for")
                mock.fireEvent("PLAYER_REGEN_ENABLED")
                check(#M.order == 2, "moments: a second end of fight shows nothing more")
                closeAll()
                check(mock.knownEvents.PLAYER_REGEN_ENABLED and not mock.restrictedEvents.PLAYER_REGEN_ENABLED, "moments: the regen event is not restricted")
            end

            -- ── the timer ──
            do
                local card = function() return M.states.rankUp end
                M:Show("rankUp", { rank = 5 })
                local st = card()
                mock.advance(11.9)
                check(st.card:IsShown() and not st.fade.__playing, "timer: still up before momentSeconds")
                mock.advance(0.2)
                check(st.fade.__playing and st.card:IsShown(), "timer: the fade starts at momentSeconds")
                st.fade.__scripts.OnFinished(st.fade, true)
                check(st.card:IsShown(), "timer: a Stop() that reports finished does not hide the card")
                st.fade.__scripts.OnFinished(st.fade, false)
                check(not st.card:IsShown() and #M.order == 0 and st.card:GetAlpha() == 1, "timer: the card hides when the fade ends")
                check(st.fadeAlpha ~= nil and st.fade.__scripts.OnFinished ~= nil, "timer: fading is an animation group")

                S.momentSeconds = 0
                M:Show("rankUp", { rank = 5 })
                mock.advance(1000)
                check(st.card:IsShown() and not st.fade.__playing, "timer: 0 means the card stays until it is closed")
                S.momentSeconds = 12
                M:Show("rankUp", { rank = 5 })
                -- held under the mouse
                mock.advance(5)
                st.card.__scripts.OnEnter(st.card)
                mock.advance(100)
                check(st.card:IsShown() and not st.fade.__playing, "timer: held while the mouse is over the card")
                st.card.__scripts.OnLeave(st.card)
                mock.advance(3.9)
                check(not st.fade.__playing, "timer: four seconds after the mouse leaves, not before")
                mock.advance(0.2)
                check(st.fade.__playing, "timer: the fade starts four seconds after the mouse leaves")
                -- the mouse during a fade stops it
                st.card.__scripts.OnEnter(st.card)
                check(not st.fade.__playing and st.card:GetAlpha() == 1, "timer: the mouse over a fading card brings it back")
                -- leaving the card for one of its controls keeps it held
                rawset(st.card, "IsMouseOver", function() return true end)
                st.card.__scripts.OnLeave(st.card)
                mock.advance(100)
                check(not st.fade.__playing, "timer: moving onto a control of the card does not restart the timer")
                rawset(st.card, "IsMouseOver", nil)
                st.card.__scripts.OnLeave(st.card)
                mock.advance(4.1)
                check(st.fade.__playing, "timer: leaving for real restarts it")
                -- controls hold it too
                M:Show("rankUp", { rank = 5 })
                st.parts.button.__scripts.OnEnter(st.parts.button)
                mock.advance(100)
                check(not st.fade.__playing, "timer: the mouse over a button holds the timer")
                st.parts.button.__scripts.OnLeave(st.parts.button)
                mock.advance(4.1)
                check(st.fade.__playing, "timer: the button's leave restarts it")
                -- close at once
                M:Show("rankUp", { rank = 5 })
                st.card.honorLogClose.__scripts.OnClick(st.card.honorLogClose)
                check(not st.card:IsShown() and #M.order == 0, "timer: the close button hides the card at once")
                mock.advance(100)
                check(not st.card:IsShown(), "timer: an old timer does nothing after a close")
                -- an old timer does nothing after the card was shown again
                M:Show("rankUp", { rank = 5 })
                mock.advance(8)
                M:Show("rankUp", { rank = 6 })
                mock.advance(5)
                check(not st.fade.__playing, "timer: showing again restarts the time")
                mock.advance(8)
                check(st.fade.__playing, "timer: and it ends twelve seconds after the second showing")
                closeAll()
            end

            -- ── Moments.Highlight ──
            do
                local now = time()
                local function g(bgType, result, kb, ago) return { bgType = bgType, result = result, kb = kb, timestamp = now - (ago or 0) } end
                local r = g("AB", "loss", 3, 0)
                local text, kind = M.Highlight(r, { r, g("AB", "win", 1, 60), g("AB", "loss", 2, 120) })
                check(text == "3 killing blows, your best in Arathi Basin this week." and kind == "kills", "highlight: the most of three games this week: " .. tostring(text))
                check(M.Highlight(r, { r }) == nil and M.Highlight(r, { r, g("AB", "win", 1, 60) }) == nil, "highlight: a best of one or two games says nothing")
                check(M.Highlight(g("AB", "loss", 1), { g("AB", "win", 0, 60), g("AB", "loss", 0, 120) }) == nil, "highlight: one killing blow is not worth a line")
                r = g("AB", "loss", 6)
                check(M.Highlight(r, { r, g("AB", "win", 8, 3600), g("AB", "win", 1, 7200) }) == nil, "highlight: not the best of the week")
                check(M.Highlight(r, { r, g("AB", "win", 6, 100), g("AB", "win", 1, 200) }) == nil, "highlight: a tie is not a best")
                text = M.Highlight(r, { r, g("AB", "win", 8, 3600 * 24 * 9), g("WSG", "win", 20, 60), g("AB", "win", 5, 100), g("AB", "win", 2, 200) })
                check(text and text:find("^6 killing blows"), "highlight: an older week and another battleground do not count against it")
                check(M.Highlight(r, { r, g("AB", "win", 2, 3600 * 24 * 9), g("WSG", "win", 1, 60), g("AB", "win", 5, 100) }) == nil, "highlight: ...nor towards the three games")
                text = M.Highlight(r, { r, g("AB", "win", 8, 3600 * 24 * 2), g("AB", "win", 1, 60), g("AB", "win", 2, 120) }, now - 3600)
                check(text and text:find("^6 killing blows"), "highlight: the week start can be given")
                local same = { bgType = "AB", result = "loss", kb = 6, timestamp = r.timestamp }
                check(M.Highlight(same, { r, g("AB", "win", 1, 60), g("AB", "win", 2, 120) }) ~= nil, "highlight: a copy of the saved game is not counted against itself")
                local win = g("AV", "win", 0)
                text, kind = M.Highlight(win, { win, g("WSG", "win"), g("AB", "win") })
                check(text == "That is 3 wins in a row." and kind == "streak", "highlight: three wins in a row across battlegrounds: " .. tostring(text))
                check(M.Highlight(win, { win, g("WSG", "win") }) == nil, "highlight: two wins are not a run")
                check(M.Highlight(win, { win, g("WSG", "win"), g("AB", "draw"), g("AB", "win"), g("AB", "win") }) == nil, "highlight: a draw ends the run")
                text = M.Highlight(win, { win, g("WSG", "win"), g("AB", "win"), g("AB", "win") })
                check(text == "That is 4 wins in a row.", "highlight: four")
                check(M.Highlight(g("AV", "loss", 0), { g("WSG", "win"), g("AB", "win"), g("AB", "win") }) == nil, "highlight: a lost game has no run")
                local copy = { bgType = "AV", result = "win", timestamp = win.timestamp }
                text = M.Highlight(copy, { win, g("WSG", "win"), g("AB", "win") })
                check(text == "That is 3 wins in a row.", "highlight: a copy of a saved game is found by its time")
                local both = g("AB", "win", 5)
                text = M.Highlight(both, { both, g("AB", "win", 1, 60), g("AB", "win", 2, 120) })
                check(text:find("killing blows") ~= nil, "highlight: killing blows come before the run")
                check(M.Highlight(nil, nil) == nil and M.Highlight({}, nil) == nil, "highlight: nothing to say about no record")
            end

            -- ── the report card ──
            do
                local function reportOf(record)
                    closeAll()
                    M:Show("report", record)
                    return M.states.report.parts, M.states.report
                end
                mock.faction = "Alliance"
                HL.GetBattlegroundModel = function() return { honorPerGame = 398 } end
                HL.GetCurrentMarks = function() return 9 end
                db.char.history = { rec }
                local p, st = reportOf(rec)
                check(st.card.honorLogTitle == "HonorLog: game report" and st.card:GetWidth() == 480, "report: titled and 480 wide")
                check(p.word:GetText() == "Victory" and p.mark.honorLogKind == "up" and p.mark.honorLogColor == "green" and p.word.__textColor[2] > p.word.__textColor[1], "report: Victory in green with an up arrow")
                check(p.name:GetText() == "Arathi Basin", "report: the full battleground name")
                check(p.sub:GetText() == HL:FormatDuration(872) .. " \194\183 1,600 to 1,180", "report: length and score: " .. tostring(p.sub:GetText()))
                for result, spec in pairs({ loss = { "Defeat", "down" }, draw = { "Draw", "flat" }, left = { "Left early", "cross" } }) do
                    local copy = {} for k, v in pairs(rec) do copy[k] = v end
                    copy.result = result
                    p = reportOf(copy)
                    check(p.word:GetText() == spec[1] and p.mark.honorLogKind == spec[2], "report: " .. result .. " is the word " .. spec[1] .. " and the " .. spec[2] .. " mark")
                end
                p = reportOf({ bgType = "AB", win = true, duration = 60 })
                check(p.word:GetText() == "Victory", "report: an old record with win = true is a win")
                local noScore = {} for k, v in pairs(rec) do noScore[k] = v end
                noScore.teams = { [0] = { kb = 1 }, [1] = { kb = 2 } }
                p = reportOf(noScore)
                check(p.sub:GetText() == HL:FormatDuration(872), "report: without team scores the line is the length only: " .. tostring(p.sub:GetText()))
                noScore.teams, noScore.duration = nil, nil
                p = reportOf(noScore)
                check(p.sub:GetText() == "", "report: with neither, the line is empty")
                local noMark = Kit:Chart(UIParent)
                check(noMark.Line ~= nil, "report: the mark is a kit chart")
                -- a client without lines draws a letter for the slanted ones
                mock.noCreateLine = true
                p = reportOf(rec)
                check(p.mark.honorLogGlyph:IsShown() and p.mark.honorLogGlyph:GetText() == "^", "report: without Line regions a letter stands in for the arrow")
                mock.noCreateLine = false
                p = reportOf(rec)
                check(not p.mark.honorLogGlyph:IsShown(), "report: with Line regions no letter")

                -- tiles
                mock.reputation[509] = 4
                p = reportOf(rec)
                local t = p.tiles
                check(p.tileCount == 4 and t[1]:IsShown() and t[4]:IsShown() and t[1]:GetWidth() == 107 and t[4]:GetWidth() == 107, "report: four tiles of 107 px")
                check(t[1].label:GetText() == "Honor" and t[1].value:GetText() == "+412" and t[1].note:GetText() == "Average 398", "report: the honor tile and its average")
                check(t[2].label:GetText() == "Rank points" and t[2].value:GetText() == "+25" and t[2].note:GetText() == "+25" and t[2].honorLogTipButton.honorLogText == "+25", "report: the rank points tile with the whole text as tooltip")
                check(t[3].label:GetText() == "Marks" and t[3].value:GetText() == "+3" and t[3].note:GetText() == "9 in your bags" and p.markIcon.honorLogBG == "AB", "report: the marks tile with the battleground's mark")
                check(t[4].label:GetText() == "Reputation" and t[4].value:GetText() == "+200" and t[4].note:GetText() == "Faction 509", "report: the reputation tile names the faction: " .. tostring(t[4].note:GetText()))
                mock.reputation[509] = nil
                p = reportOf(rec)
                check(p.tiles[4].note:GetText() == "Arathi Basin", "report: an unknown faction name falls back to the battleground")
                local noRep = {} for k, v in pairs(rec) do noRep[k] = v end
                noRep.rep = nil
                p = reportOf(noRep)
                check(p.tileCount == 4 and p.tiles[4].label:GetText() == "Killing blows" and p.tiles[4].value:GetText() == "6" and p.tiles[4].note:GetText() == "20 honorable kills", "report: killing blows take the fourth tile when there is no reputation")
                noRep.kb = nil
                p = reportOf(noRep)
                check(p.tileCount == 3 and not p.tiles[4]:IsShown() and p.tiles[1]:GetWidth() == 146 and p.tiles[3]:GetWidth() == 146, "report: three tiles of 146 px when there is nothing for a fourth")
                noRep.kb, noRep.rep = 0, { faction = 509, gained = 0 }
                p = reportOf(noRep)
                check(p.tileCount == 3, "report: no killing blows and no reputation gain: three tiles")
                local capped = {} for k, v in pairs(rec) do capped[k] = v end
                capped.honorCapped, capped.rankPoints, capped.rankState = true, 0, "capped"
                p = reportOf(capped)
                check(p.tiles[1].note:GetText() == "At the honor cap" and p.tiles[2].value:GetText() == "0" and p.tiles[2].note:GetText() == "0, weekly cap reached"
                    and p.tiles[2].note.__textColor[1] == Kit.COLORS.orange[1], "report: the cap note, zero rank points and the reason in orange")
                local bare = { bgType = "WSG", result = "loss" }
                p = reportOf(bare)
                check(p.tiles[1].value:GetText() == "-" and p.tiles[2].value:GetText() == "-" and p.tiles[3].value:GetText() == "+0" and p.tileCount == 3, "report: a record without numbers draws dashes")
                HL.GetBattlegroundModel = function() return nil end
                p = reportOf(rec)
                check(p.tiles[1].note:GetText() == "", "report: no model, no average")
                HL.GetBattlegroundModel = function() return { honorPerGame = 398 } end

                -- the highlight
                db.char.history = { rec }
                p = reportOf(rec)
                check(not p.light:IsShown(), "report: one game this week earns no line")
                db.char.history = { rec, { bgType = rec.bgType, result = "loss", kb = 2, timestamp = time() - 600 }, { bgType = rec.bgType, result = "win", kb = 1, timestamp = time() - 1200 } }
                p = reportOf(rec)
                check(p.light:IsShown() and p.lightText:GetText() == "6 killing blows, your best in Arathi Basin this week." and p.lightTip.honorLogText == p.lightText:GetText(), "report: the killing blows line")
                local streak = { bgType = "AV", result = "win", timestamp = time() }
                db.char.history = { streak, { bgType = "AB", result = "win", timestamp = time() - 5 }, { bgType = "WSG", result = "win", timestamp = time() - 9 } }
                p = reportOf(streak)
                check(p.light:IsShown() and p.lightText:GetText() == "That is 3 wins in a row.", "report: the run line")
                db.char.history = { { bgType = "AV", result = "win", timestamp = time() } }
                p = reportOf(db.char.history[1])
                check(not p.light:IsShown(), "report: no line when neither applies")
                db.char.history = { rec, { bgType = rec.bgType, result = "loss", kb = 2, timestamp = time() - 600 }, { bgType = rec.bgType, result = "win", kb = 1, timestamp = time() - 1200 } }
                local sectionsBefore = select(2, reportOf(rec)).card:GetHeight()
                db.char.history = { { bgType = "AV", result = "win", timestamp = time() } }
                p, st = reportOf(db.char.history[1])
                check(st.card:GetHeight() < sectionsBefore, "report: the card is shorter without the line")

                -- next goal
                HL.GetAllGoalsProgress = function() return { { itemID = 272738, name = "Premier Cloak", isComplete = false }, { itemID = 20041, name = "Second" } } end
                HL.GoalReadyText = function() return "|cff40d860Ready at level 55|r" end
                p = reportOf(rec)
                check(p.goal:IsShown() and p.goalIcon.honorLogItemID == 272738 and p.goalName:GetText() == "Premier Cloak" and p.goalText:GetText() == "|cff40d860Ready at level 55|r"
                    and p.goalTip.honorLogText == "Premier Cloak\nReady at level 55" and p.goalIcon.honorLogTexture ~= nil, "report: the next goal with icon, name and ready text")
                HL.GetAllGoalsProgress = function() return {} end
                p = reportOf(rec)
                check(not p.goal:IsShown(), "report: without goals no goal section")
                HL.GetAllGoalsProgress = function() error("goals gone") end
                noErrors("report: a goals read that raises", function() p = reportOf(rec) end)
                check(not p.goal:IsShown() and p.tiles[1].value:GetText() == "+412", "report: and the rest is drawn")
                HL.GetAllGoalsProgress = function() return {} end

                -- the honor bar
                HL.GetCurrentHonor, HL.GetHonorCap = function() return 18832 end, function() return 25000 end
                p = reportOf(rec)
                check(p.honor:IsShown() and p.honorValue:GetText() == "18,832 / 25,000" and math.abs(p.honorBar.honorLogFraction - 18832 / 25000) < 1e-9, "report: honor held over the cap")
                HL.GetHonorCap = function() return nil end
                p = reportOf(rec)
                check(not p.honor:IsShown(), "report: no cap, no bar")
                HL.GetHonorCap, HL.GetCurrentHonor = function() return 25000 end, function() return secret() end
                p = reportOf(rec)
                check(not p.honor:IsShown(), "report: a secret honor, no bar")
                HL.GetCurrentHonor, HL.GetHonorCap = save.honor, save.cap

                -- the button
                p, st = reportOf(rec)
                check(p.button:GetText() == "All games", "report: the All games button")
                p.button.__scripts.OnClick(p.button)
                check(HL.Window.current == "battlegrounds" and not st.card:IsShown(), "report: it opens the Battlegrounds screen and the card goes")
                HL.Window:Hide()
                check(foreign(p.button) == "", "report: the button adds only honorLog names to the template frame")
            end

            -- ── the rank-up card ──
            do
                local function rankOf(data)
                    closeAll()
                    M:Show("rankUp", data)
                    return M.states.rankUp.parts, M.states.rankUp
                end
                local unlocks = { [3] = { 101 }, [5] = { 201, 202, 203 }, [6] = { 1, 2, 3, 4, 5, 6, 7 }, [8] = { 301, 302 } }
                HL.GetRankUnlocks = function(_, n) return unlocks[n] or {} end
                HL.GetGearName = function(_, id) return "Item " .. id end
                HL.Rank.GetInfo = function() return { rank = 3, seasonMaxRank = 14 } end
                HL.Rank.GetPace = function() return { estimated = false } end
                HL.Rank.PlanToRank = function() return { gamesNeeded = 120, limitedBy = "pace" } end
                local p, st = rankOf({ rank = 3, info = { rank = 3, seasonMaxRank = 14 } })
                check(st.card.honorLogTitle == "HonorLog: rank up" and st.card:GetWidth() == 360 and p.rankLabel:GetText() == "Rank" and p.rankNumber:GetText() == "3" and p.rankTitle:GetText() ~= "", "rank-up: Rank over the number with the title beside it")
                check(p.unlockCount == 1 and p.unlockIcons[1]:IsShown() and p.unlockIcons[1].honorLogItemID == 101 and not p.unlockIcons[2]:IsShown() and p.unlockName:GetText() == "Item 101", "rank-up: one unlock shows its icon and its name")
                check(not p.unlockNone:IsShown() and p.unlockIcons[1]:GetWidth() == 32, "rank-up: the icons are 32 px")
                check(p.next:IsShown() and p.nextLabel:GetText() == "Next: Rank 5" and p.nextIcons[3]:IsShown() and not p.nextIcons[4]:IsShown() and p.nextIcons[1]:GetWidth() == 24, "rank-up: the next rank that unlocks something, three icons at 24")
                check(p.nextLine:GetText() == "at " .. HL.Rank:TotalForRank(5) .. " points, ~120 games" or p.nextLine:GetText():find("^at [%d,]+ points, ~120 games$"), "rank-up: points and games: " .. tostring(p.nextLine:GetText()))
                HL.Rank.GetPace = function() return { estimated = true } end
                p = rankOf({ rank = 3, info = { rank = 3, seasonMaxRank = 14 } })
                check(p.nextLine:GetText():find("^at [%d,]+ points$"), "rank-up: an unmeasured pace says the points only: " .. tostring(p.nextLine:GetText()))
                HL.Rank.PlanToRank = function() return { gamesNeeded = nil, limitedBy = "level", gateLevel = 40 } end
                HL.Rank.GetPace = function() return { estimated = false } end
                p = rankOf({ rank = 3, info = { rank = 3, seasonMaxRank = 14 } })
                check(p.nextLine:GetText():find("^at [%d,]+ points$"), "rank-up: a plan with no games says the points only")
                p = rankOf({ rank = 5, info = { rank = 5, seasonMaxRank = 14 } })
                check(p.unlockCount == 3 and p.unlockIcons[3]:IsShown() and p.unlockName:GetText() == "" and p.unlockMore:GetText() == "", "rank-up: three unlocks show three icons and no name")
                check(p.nextLabel:GetText() == "Next: Rank 6" and p.nextIcons[5]:IsShown(), "rank-up: next is rank 6 with five icons of its seven")
                p = rankOf({ rank = 6, info = { rank = 6, seasonMaxRank = 14 } })
                check(p.unlockCount == 7 and p.unlockIcons[5]:IsShown() and p.unlockMore:GetText() == "+2", "rank-up: more than five show five and +2")
                p = rankOf({ rank = 4, info = { rank = 4, seasonMaxRank = 14 } })
                check(p.unlockCount == 0 and p.unlockNone:IsShown() and p.unlockNone:GetText() == "Nothing new at this rank." and not p.unlockIcons[1]:IsShown(), "rank-up: a rank with nothing says so")
                p = rankOf({ rank = 8, info = { rank = 8, seasonMaxRank = 14 } })
                check(not p.next:IsShown(), "rank-up: nothing ahead, no next section")
                p = rankOf({ rank = 14, info = { rank = 14, seasonMaxRank = 14 } })
                check(not p.next:IsShown(), "rank-up: nothing at the top rank")
                local s1 = select(2, rankOf({ rank = 3, info = { rank = 3, seasonMaxRank = 14 } })).card:GetHeight()
                local s2 = select(2, rankOf({ rank = 14, info = { rank = 14, seasonMaxRank = 14 } })).card:GetHeight()
                check(s2 < s1, "rank-up: the card is shorter without the next section")
                p = rankOf({ rank = 3, info = { rank = 3, seasonMaxRank = 14 } })
                check(p.button:GetText() == "Rank plan", "rank-up: the Rank plan button")
                p.button.__scripts.OnClick(p.button)
                check(HL.Window.current == "rank" and not M.states.rankUp.card:IsShown(), "rank-up: it opens the Rank plan and the card goes")
                HL.Window:Hide()
                p = rankOf({})
                check(p.rankNumber:GetText() == "-" and not p.next:IsShown() and p.unlockNone:IsShown(), "rank-up: no rank at all draws a dash")
                HL.GetRankUnlocks = function() error("unlocks gone") end
                noErrors("rank-up: an unlock read that raises", function() p = rankOf({ rank = 3 }) end)
                check(p.rankNumber:GetText() == "3", "rank-up: the rest is drawn")
                HL.GetRankUnlocks, HL.GetGearName = save.unlocks, save.gear
                HL.Rank.GetInfo, HL.Rank.GetPace, HL.Rank.PlanToRank = save.rankInfo, save.pace, save.plan
            end

            -- ── the honor cap card ──
            do
                local function capOf(data)
                    closeAll()
                    M:Show("honorCap", data)
                    return M.states.honorCap.parts, M.states.honorCap
                end
                local orange, gold = Kit.COLORS.orange, Kit.COLORS.gold
                db.char.battlegrounds = { WSG = { played = 10, honorLifetime = 4000, cappedPlayed = 0, cappedHonor = 0 } }
                HL.GetBuyableNow = function() return {} end
                HL.GetHonorCapAdvice = function() return nil end
                local p, st = capOf({ current = 20000, cap = 25000 })
                check(st.card.honorLogTitle == "HonorLog: honor cap" and st.card:GetWidth() == 360 and p.headText:GetText() == "Honor is at 20,000 / 25,000", "honor cap: the numbers")
                check(p.bar.honorLogColor[1] == gold[1] and p.bar.honorLogColor[2] == gold[2] and math.abs(p.bar.honorLogFraction - 0.8) < 1e-9, "honor cap: a gold bar below 90 percent")
                check(p.paceText:GetText() == "About 13 games until it stops counting.", "honor cap: the pace sentence: " .. tostring(p.paceText:GetText()))
                p = capOf({ current = 22500, cap = 25000 })
                check(p.bar.honorLogColor[1] == orange[1] and p.bar.honorLogColor[2] == orange[2], "honor cap: orange from 90 percent")
                p = capOf({ current = 25000, cap = 25000 })
                check(p.paceText:GetText() == "At the cap: more honor is wasted." and p.bar.honorLogFraction == 1, "honor cap: full")
                db.char.battlegrounds = {}
                p = capOf({ current = 20000, cap = 25000 })
                check(not p.pace:IsShown(), "honor cap: no measured pace, no sentence")
                -- nothing buyable
                check(p.buyNone:IsShown() and p.buyNone:GetText() == "Nothing on your list can be bought yet." and not p.buyMap:IsShown() and not p.buyIcons[1]:IsShown(), "honor cap: nothing buyable and no advice says so")
                HL.GetHonorCapAdvice = function() return { text = "you are near the cap and nothing can be bought yet." } end
                p = capOf({ current = 20000, cap = 25000 })
                check(p.buyNone:GetText() == "You are near the cap and nothing can be bought yet." and p.buyNoneTip.honorLogText == p.buyNone:GetText(), "honor cap: the advice text when there is one")
                -- buyable
                local shown
                HL.ShowVendorForItem = function(_, id) shown = id end
                HL.GetBuyableNow = function() return { { itemID = 11, name = "Premier Cloak", honor = 4500, marks = { AB = 10 }, gold = 0 }, { itemID = 12, name = "B", honor = 100 }, { itemID = 13, name = "C", honor = 50 } } end
                p = capOf({ current = 20000, cap = 25000 })
                check(p.buyIcons[3]:IsShown() and p.buyIcons[1].honorLogItemID == 11 and p.buyIcons[1]:GetWidth() == 28 and not p.buyNone:IsShown(), "honor cap: three icons at 28")
                check(p.buyName:GetText() == "Premier Cloak" and p.buyCost:GetText() == "4,500 honor, 10 Arathi Basin marks" and p.buyTip.honorLogText == "Premier Cloak\n4,500 honor, 10 Arathi Basin marks", "honor cap: the first one's name and cost")
                check(p.buyMap:IsShown() and p.buyMap:GetText() == "Show on map", "honor cap: the Show on map button")
                p.buyMap.__scripts.OnClick(p.buyMap)
                check(shown == 11, "honor cap: Show on map points at the first one")
                check(foreign(p.buyMap) == "" and foreign(p.button) == "", "honor cap: the buttons add only honorLog names to the template frames")
                HL.GetBuyableNow = function() return { { itemID = 12, name = "B" } } end
                p = capOf({ current = 20000, cap = 25000 })
                check(p.buyIcons[1]:IsShown() and not p.buyIcons[2]:IsShown() and p.buyCost:GetText() == "", "honor cap: one item")
                -- the button
                p, st = capOf({ current = 20000, cap = 25000 })
                check(p.button:GetText() == "Gear goals", "honor cap: the Gear goals button")
                p.button.__scripts.OnClick(p.button)
                check(HL.Window.current == "gear" and not st.card:IsShown(), "honor cap: it opens the gear goals and the card goes")
                HL.Window:Hide()
                -- no numbers: read from the client
                mock.currencies[1792].quantity = 21000
                p = capOf({})
                check(p.headText:GetText():find("^Honor is at 21,000 / "), "honor cap: without data in the event it reads the client")
                C_CurrencyInfo.GetCurrencyInfo = function() return secret() end
                noErrors("honor cap: a secret honor", function() p = capOf({}) end)
                check(not p.head:IsShown() and p.button:IsShown(), "honor cap: a secret honor hides the numbers and keeps the rest")
                C_CurrencyInfo.GetCurrencyInfo = save.currency
                HL.GetBuyableNow = function() error("buy gone") end
                noErrors("honor cap: a buyable read that raises", function() p = capOf({ current = 1, cap = 2 }) end)
                check(p.buyNone:IsShown() and p.headText:GetText() == "Honor is at 1 / 2", "honor cap: the rest is drawn")
                HL.GetBuyableNow, HL.GetHonorCapAdvice, HL.ShowVendorForItem = save.buy, save.advice, save.showItem
                db.char.battlegrounds = save.bgs
            end

            -- ── a part that fails, a read that raises or answers nothing ──
            do
                closeAll()
                HL.Rank.FormatNumber = function() error("format gone") end
                local before = #mock.handledErrors
                local ok = pcall(M.Show, M, "report", rec)
                check(ok and #mock.handledErrors > before, "moments: a failing part is reported and raises nothing")
                for i = #mock.handledErrors, before + 1, -1 do mock.handledErrors[i] = nil end
                HL.Rank.FormatNumber = save.format
                closeAll()
                HL.DescribeRankPoints = function() error("describe gone") end
                noErrors("moments: a model that raises", function() M:Show("report", rec) end)
                check(M.states.report.parts.tiles[1].value:GetText() == "+412" and M.states.report.parts.word:GetText() == "Victory", "moments: the other parts are drawn")
                HL.DescribeRankPoints = function() return nil end
                noErrors("moments: a model that answers nothing", function() M:Show("report", rec) end)
                HL.DescribeRankPoints = function() return secret(), secret() end
                noErrors("moments: a model that answers a secret", function() M:Show("report", rec) end)
                HL.DescribeRankPoints = save.describe
                noErrors("moments: a record full of secrets", function()
                    M:Show("report", { bgType = secret(), result = secret(), duration = secret(), honor = secret(), marks = secret(), rankPoints = secret(), kb = secret(), rep = { gained = secret() }, teams = { [0] = { score = secret() }, [1] = {} } })
                end)
                noErrors("moments: a record that is not a table", function() M:Show("report", nil) M:Show("report", 5) M:Show("rankUp", nil) M:Show("honorCap", "x") end)
                closeAll()
                -- a card that cannot be built is reported and never raises
                local realCard = Kit.Card
                for kind in pairs(M.states) do M.states[kind] = nil end
                Kit.Card = function() error("no card") end
                local before2 = #mock.handledErrors
                local okShow, result = pcall(M.Show, M, "honorCap", {})
                check(okShow and result == false and #mock.handledErrors == before2 + 1, "moments: a card that cannot be built is reported and Show returns false")
                for i = #mock.handledErrors, before2 + 1, -1 do mock.handledErrors[i] = nil end
                Kit.Card = realCard
                check(M.states.honorCap == nil, "moments: and nothing half-built is kept")
                -- an event whose listener raises
                local realShow = M.Show
                M.Show = function() error("show gone") end
                local before3 = #mock.handledErrors
                check(pcall(HL.Fire, HL, "HonorLog_GameRecorded", rec) and #mock.handledErrors > before3, "moments: a failing listener is reported and does not reach the caller")
                for i = #mock.handledErrors, before3 + 1, -1 do mock.handledErrors[i] = nil end
                M.Show = realShow
            end

            -- ── the three events, with the cards ──
            do
                closeAll()
                for _, key in ipairs({ "momentReport", "momentRankUp", "momentHonorCap" }) do S[key] = false end
                HL:Fire("HonorLog_GameRecorded", rec)
                HL:Fire("HonorLog_RankUp", 4, { rank = 4 })
                HL:Fire("HonorLog_HonorCapNear", 24000, 25000)
                check(#M.order == 0, "events: nothing shows with all three cards off")
                S.momentRankUp = true
                HL:Fire("HonorLog_RankUp", 4, { rank = 4 })
                check(M.order[1] == "rankUp" and M.states.rankUp.parts.rankNumber:GetText() == "4", "events: the rank-up event shows the rank-up card")
                S.momentHonorCap = true
                HL:Fire("HonorLog_HonorCapNear", 24000, 25000)
                check(M.order[2] == "honorCap" and M.states.honorCap.parts.headText:GetText() == "Honor is at 24,000 / 25,000", "events: the honor cap event shows the honor cap card")
                S.momentReport = true
                closeAll()
            end

            -- ── the slash command ──
            do
                closeAll()
                for _, key in ipairs({ "momentReport", "momentRankUp", "momentHonorCap" }) do S[key] = false end
                db.char.history = {}
                local lines = #printed
                SlashCmdList.HONORLOG("moment report")
                check(#M.order == 0 and printed[#printed]:find("No saved game", 1, true) and #printed == lines + 1, "slash: moment report with no saved game says so in chat")
                db.char.history = { rec }
                SlashCmdList.HONORLOG("moment report")
                check(M.order[1] == "report" and M.states.report.parts.tiles[1].value:GetText() == "+412", "slash: moment report shows the newest saved game, whatever the settings say")
                SlashCmdList.HONORLOG("moment rank")
                check(M.states.rankUp.card:IsShown() and M.states.rankUp.parts.rankNumber:GetText() == tostring(mock.rank.level), "slash: moment rank shows the current rank")
                SlashCmdList.HONORLOG("moment cap")
                check(M.states.honorCap.card:IsShown() and M.states.honorCap.parts.headText:GetText():find("^Honor is at "), "slash: moment cap shows the honor cap card from the current honor")
                lines = #printed
                SlashCmdList.HONORLOG("moment nonsense")
                check(printed[#printed]:find("Usage: /honorlog moment", 1, true), "slash: an unknown kind prints the usage")
                lines = #printed
                SlashCmdList.HONORLOG("help")
                local helpLine
                for i = lines + 1, #printed do if printed[i]:find("moment", 1, true) then helpLine = printed[i] end end
                check(helpLine, "slash: the help lists the moment command")
                closeAll()
                for _, key in ipairs({ "momentReport", "momentRankUp", "momentHonorCap" }) do S[key] = true end
            end

            -- ── nothing per frame, and only honorLog names on template frames ──
            do
                closeAll()
                for kind in pairs(M.states) do M.states[kind] = nil end
                local first = #mock.frames + 1
                HL.GetBuyableNow = function() return { { itemID = 11, name = "A", honor = 1 } } end
                HL.GetAllGoalsProgress = function() return { { itemID = 272738, name = "G" } } end
                M:Show("report", rec) M:Show("rankUp", { rank = 3 }) M:Show("honorCap", { current = 1, cap = 2 })
                local onUpdates, templated, bad = 0, 0, {}
                for i = first, #mock.frames do
                    local f = mock.frames[i]
                    if f.__scripts.OnUpdate then onUpdates = onUpdates + 1 end
                    if f.__template then
                        templated = templated + 1
                        for k in pairs(f) do
                            if type(k) == "string" and not k:find("^__") and not k:find("^honorLog") then bad[#bad + 1] = k end
                        end
                    end
                end
                check(onUpdates == 0, "moments: no OnUpdate on any frame (" .. onUpdates .. ")")
                check(templated > 10 and #bad == 0, "moments: only honorLog names are added to template frames (" .. templated .. "): " .. table.concat(bad, ","))
                for _, file in ipairs({ "UI/Moments.lua" }) do
                    local source = io.open(ROOT .. "/" .. file):read("*a")
                    check(not source:find("OnUpdate", 1, true), "moments: " .. file .. " has no OnUpdate")
                end
                check(#mock.frames >= first, "moments: frames counted")
                HL.GetBuyableNow, HL.GetAllGoalsProgress = save.buy, save.goals
                closeAll()
            end
            check(framesBefore <= #mock.frames, "moments: done")

            -- put it back
            HL.GetCurrentHonor, HL.GetHonorCap, HL.GetAllGoalsProgress, HL.GoalReadyText = save.honor, save.cap, save.goals, save.ready
            HL.GetBattlegroundModel, HL.GetCurrentMarks = save.model, save.marks
            db.char.history, db.char.battlegrounds = save.history, save.bgs
            S.momentReport, S.momentRankUp, S.momentHonorCap, S.momentSeconds = save.settings[1], save.settings[2], save.settings[3], save.settings[4]
            mock.deferTimers, mock.timers, mock.combat = save.deferred, {}, false
            HL.Window:Hide()
        end)()

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

    ----------------------------------------------------------------------
    -- Saved-data version 3: the migration chain, the character summaries and the weeks
    ----------------------------------------------------------------------
    ;(function()
        local DeepCopy = HL.Util.DeepCopy
        local realTime = time
        local function deepEqual(a, b)
            if type(a) ~= type(b) then return false end
            if type(a) ~= "table" then return a == b end
            for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
            for k in pairs(b) do if a[k] == nil then return false end end
            return true
        end
        local function setGlobal(name, value) _G[name] = value end
        -- What the sections below replace, put back at the end of each.
        local function keepStores()
            local kept = { db = HL.db, global = HonorLogDB, char = HonorLogCharDB, reload = HL.isReload,
                name = mock.playerName, level = mock.level, faction = mock.faction, reset = mock.weeklyReset,
                honor = mock.currencies[1792].quantity, rank = mock.rank, bags = mock.bagItems, deferred = mock.deferTimers }
            kept.window = { cap = mock.rankWindow.cap, week = mock.rankWindow.week, prevCap = mock.rankWindow.prevCap, noData = mock.rankWindow.noData }
            return kept
        end
        local function restoreStores(kept)
            HL.db, HonorLogDB, HonorLogCharDB, HL.isReload = kept.db, kept.global, kept.char, kept.reload
            mock.playerName, mock.level, mock.faction, mock.weeklyReset = kept.name, kept.level, kept.faction, kept.reset
            mock.currencies[1792].quantity, mock.rank, mock.bagItems, mock.deferTimers = kept.honor, kept.rank, kept.bags, kept.deferred
            mock.rankWindow.cap, mock.rankWindow.week, mock.rankWindow.prevCap = kept.window.cap, kept.window.week, kept.window.prevCap
            mock.rankWindow.noData = kept.window.noData
            mock.timers = {}
        end
        -- Run fn with a set of client globals replaced, then put them back.
        local function withGlobals(replacements, fn)
            local saved = {}
            for name, value in pairs(replacements) do saved[name] = _G[name]; setGlobal(name, value) end
            local ok, err = pcall(fn)
            for name in pairs(replacements) do setGlobal(name, saved[name]) end
            if not ok then error(err, 0) end
        end

        ;(function()
            local kept = keepStores()
            local errorsBefore = #mock.handledErrors

            -- 1 to 2 to 3: the TBC save goes through both steps, and what version 2 did is still true.
            local tbc = dofile(ROOT .. "/Tests/fixtures/tbc_savedvars.lua")
            local before = time()
            HL.MigrateStore(tbc.global, false)
            HL.MigrateStore(tbc.char, true)
            check(tbc.global.dbVersion == 3 and tbc.char.dbVersion == 3, "migration: a save with no version reaches 3")
            check(tbc.global.legacy.EotS.played == 8 and tbc.global.battlegrounds.EotS == nil and tbc.char.bgState == nil, "migration: step 2 ran on the way to 3")
            check(tbc.char.session.EotS == nil, "migration: step 2 dropped the EotS session")
            check(deepEqual(tbc.global.characters, { ["Oldchar-TestRealm"] = { name = "Oldchar-TestRealm" } }), "migration: the TBC account's character became a table")
            check(tbc.char.since == 1759980000, "migration: since is the oldest saved game")
            check(tbc.global.since == nil, "migration: the account store gets no since")

            -- a character store with no games dates from the migration
            local bare = { dbVersion = 2 }
            HL.MigrateStore(bare, true)
            check(bare.since >= before and bare.since <= time() and bare.dbVersion == 3, "migration: with no games, since is the time of the migration")
            local noStamp = { dbVersion = 2, history = { { honor = 5 }, { timestamp = mock.newSecret() } } }
            HL.MigrateStore(noStamp, true)
            check(noStamp.since >= before, "migration: games without a usable timestamp do not set since")
            -- with no dated game, the oldest "last seen" of an opponent or the first day of honor proves an earlier start
            local seen = { dbVersion = 2, history = {}, opponents = { A = { kills = 1, lastSeen = 1790000500 }, B = { deaths = 2, lastSeen = 1790000100 }, C = "junk" } }
            HL.MigrateStore(seen, true)
            check(seen.since == 1790000100, "migration: since falls back to the oldest opponent last seen: " .. tostring(seen.since))
            local days = { dbVersion = 2, history = {}, honorDays = { ["20261120"] = 500, ["20261118"] = 20, notADay = 1 } }
            HL.MigrateStore(days, true)
            check(days.since == realTime({ year = 2026, month = 11, day = 18, hour = 12 }), "migration: ...or to the first day of honor")
            local mixed = { dbVersion = 2, history = { { timestamp = 1790000900 } }, opponents = { A = { lastSeen = 1790000300 } }, honorDays = {} }
            HL.MigrateStore(mixed, true)
            check(mixed.since == 1790000300, "migration: the earliest of them wins")
            -- a key an early build made from a name and an empty realm is dropped; real keys become records
            local keys = { dbVersion = 2, characters = { ["Liquid Elements"] = true, ["Liquid-"] = true, [""] = true, ["Other-Some Realm"] = true, Kept = { name = "Kept", level = 60 } } }
            HL.MigrateStore(keys, false)
            check(keys.characters["Liquid-"] == nil and keys.characters[""] == nil and deepEqual(keys.characters["Liquid Elements"], { name = "Liquid Elements" })
                and deepEqual(keys.characters["Other-Some Realm"], { name = "Other-Some Realm" }) and keys.characters.Kept.level == 60, "migration: malformed character keys are dropped, the others become or stay records")

            -- 2 to 3: the going-back guarantee
            local v2 = dofile(ROOT .. "/Tests/fixtures/v2_savedvars.lua")
            local was = dofile(ROOT .. "/Tests/fixtures/v2_savedvars.lua")
            HL.MigrateStore(v2.global, false)
            HL.MigrateStore(v2.char, true)
            check(v2.global.dbVersion == 3 and v2.char.dbVersion == 3, "migration: version 2 reaches 3")
            check(deepEqual(v2.global.characters, { ["Fenwick Tally"] = { name = "Fenwick Tally" }, ["Marla Quill-Testrealm"] = { name = "Marla Quill-Testrealm" } }),
                "migration: characters = true became { name = key }")
            check(v2.char.since == 1789990000, "migration: since is the oldest saved game of the character")
            local globalCopy, wasGlobal = DeepCopy(v2.global), was.global
            globalCopy.characters, globalCopy.dbVersion, wasGlobal.characters, wasGlobal.dbVersion = nil, nil, nil, nil
            check(deepEqual(globalCopy, wasGlobal), "migration: every other account key is deep-equal to version 2")
            local charCopy, wasChar = DeepCopy(v2.char), was.char
            charCopy.since, charCopy.dbVersion, wasChar.dbVersion = nil, nil, nil
            check(deepEqual(charCopy, wasChar), "migration: every other character key is deep-equal to version 2")
            local pristine = dofile(ROOT .. "/Tests/fixtures/v2_savedvars.lua")
            local gainedChar, gainedGlobal = 0, 0
            for key in pairs(v2.char) do if pristine.char[key] == nil then gainedChar = gainedChar + 1 end end
            for key in pairs(v2.global) do if pristine.global[key] == nil then gainedGlobal = gainedGlobal + 1 end end
            check(gainedChar == 1 and v2.char.since ~= nil, "migration: the character store gained exactly one key (since)")
            check(gainedGlobal == 0, "migration: the account store gained no key")

            -- a second load changes nothing
            local once = DeepCopy(v2)
            HL.MigrateStore(v2.global, false)
            HL.MigrateStore(v2.char, true)
            check(deepEqual(v2, once), "migration: a second pass changes nothing")

            -- a save already at 3 is untouched; an unknown higher version is left alone
            local three = { dbVersion = 3, characters = { a = true }, extra = { 1, 2 } }
            local threeCopy = DeepCopy(three)
            HL.MigrateStore(three, false)
            check(deepEqual(three, threeCopy), "migration: a save at 3 is untouched")
            local future = { dbVersion = 7, characters = { a = true }, history = { { timestamp = 5 } } }
            local futureCopy = DeepCopy(future)
            HL.MigrateStore(future, true)
            HL.MigrateStore(future, false)
            check(deepEqual(future, futureCopy) and future.since == nil, "migration: an unknown higher version is left alone")

            -- the whole load on the version 2 save, twice
            local loaded = dofile(ROOT .. "/Tests/fixtures/v2_savedvars.lua")
            HonorLogDB, HonorLogCharDB = loaded.global, loaded.char
            HL:InitializeDB()
            local key = HL:GetCharacterKey()
            check(HonorLogDB.dbVersion == 3 and HonorLogCharDB.dbVersion == 3, "load: both stores at 3")
            check(type(HonorLogCharDB.weeks) == "table" and #HonorLogCharDB.weeks == 0, "load: the character store has weeks = {}")
            check(HonorLogDB.characters["Fenwick Tally"].name == "Fenwick Tally" and deepEqual(HonorLogDB.characters[key], { name = key }), "load: the current character gets a stub record")
            check(HonorLogCharDB.since == 1789990000, "load: since kept")
            local first = { chars = DeepCopy(HonorLogDB.characters), since = HonorLogCharDB.since, a = HonorLogDB.dbVersion, b = HonorLogCharDB.dbVersion }
            HL:InitializeDB()
            check(deepEqual(first.chars, HonorLogDB.characters) and first.since == HonorLogCharDB.since and first.a == 3 and first.b == 3, "load: a second load changes nothing")

            -- InitializeDB does not write over a record that is a table; it replaces a bare true
            HonorLogDB.characters[key] = { name = "Kept", honor = 5, lastSeen = 9 }
            HL:InitializeDB()
            check(HonorLogDB.characters[key].honor == 5 and HonorLogDB.characters[key].name == "Kept", "load: an existing record is kept")
            HonorLogDB.characters[key] = true
            HL:InitializeDB()
            check(deepEqual(HonorLogDB.characters[key], { name = key }), "load: a bare true is replaced by a stub")

            -- a fresh save starts at 3
            HonorLogDB, HonorLogCharDB = nil, nil
            HL:InitializeDB()
            check(HonorLogDB.dbVersion == 3 and HonorLogCharDB.dbVersion == 3, "load: a fresh save starts at 3")
            check(type(HonorLogCharDB.weeks) == "table" and HonorLogCharDB.since == nil, "load: a fresh character store has weeks and no since yet")
            HL.Weeks:Current()
            check(type(HonorLogCharDB.since) == "number", "load: the first week sets since on a fresh save")

            check(#mock.handledErrors == errorsBefore, "migration section reached no error handler: " .. tostring(mock.handledErrors[errorsBefore + 1]))
            restoreStores(kept)
        end)()

        --------------------------------------------------------------------
        -- Characters
        --------------------------------------------------------------------
        local clock = realTime({ year = 2026, month = 11, day = 18, hour = 10, min = 0, sec = 0 })
        setGlobal("time", function(t) if t then return realTime(t) end return clock end)

        ;(function()
            local kept = keepStores()
            local errorsBefore = #mock.handledErrors
            local Characters = HL.Characters
            HonorLogDB, HonorLogCharDB = nil, nil
            HL:InitializeDB()
            local alphaChar = HL.db.char
            mock.playerName = "Alpha"
            local key = HL:GetCharacterKey()
            check(key == "Alpha-TestRealm", "characters: the key is name and realm")
            mock.level, mock.faction = 58, "Horde"
            mock.currencies[1792].quantity = 12345
            mock.bagItems = { [20558] = 12, [20559] = 3 }
            mock.rank = { level = 4, earned = 300, threshold = 1200 }
            mock.rankWindow.cap, mock.rankWindow.week, mock.rankWindow.prevCap, mock.rankWindow.noData = 4, 3, 3, false
            mock.weeklyReset = 2 * 86400
            HL:RecordGame("WSG", true, 600, 100, 3)
            HL:RecordGame("AB", false, 500, 50, 1)
            local goalItem = next(HL.GearDB)
            check(HL:AddGoal(goalItem), "characters: a goal to point at")

            -- every field of a snapshot
            Characters:Snapshot()
            local rec = HonorLogDB.characters[key]
            local info = HL.Rank:GetInfo()
            local reading = HL.Quests.ReadState()
            check(info.capped == true, "characters: the setup is capped")
            check(rec.name == "Alpha" and rec.class == "WARRIOR" and rec.faction == "Horde" and rec.level == 58, "characters: name, class, faction and level")
            check(rec.rank == 4 and rec.rankPoints == info.totalPoints, "characters: rank and the running total")
            check(rec.capped == true and rec.capUntil == clock + 2 * 86400, "characters: capped, and the reset the cap holds until")
            check(rec.honor == 12345 and deepEqual(rec.marks, reading.marks) and rec.marks.WSG == 12, "characters: honor and marks")
            check(rec.nextGoal == goalItem and rec.goalPercent == HL:GetGoalPercent(HL:GetAllGoalsProgress()[1]), "characters: the first goal and how far it is")
            check(rec.games == 2 and rec.wins == 1, "characters: games and wins from the battleground stats")
            check(rec.lastSeen == clock, "characters: lastSeen")
            -- not capped: the cap clears
            mock.rank = { level = 3, earned = 100, threshold = 1050 }
            Characters:Snapshot()
            check(rec.capped == false and rec.capUntil == nil, "characters: not capped clears capUntil")
            mock.rank = { level = 4, earned = 300, threshold = 1200 }
            Characters:Snapshot()

            -- an unknown or secret value keeps what was stored
            local stored = DeepCopy(rec)
            mock.level, mock.rankWindow.noData = nil, true
            mock.currencies[1792].quantity = mock.newSecret()
            withGlobals({ UnitClass = function() return mock.newSecret(), mock.newSecret() end,
                UnitFactionGroup = function() return mock.newSecret(), mock.newSecret() end }, function()
                clock = clock + 5
                Characters:Snapshot()
            end)
            check(rec.lastSeen == clock, "characters: lastSeen moves on")
            stored.lastSeen = rec.lastSeen
            local differs = {}
            for k, v in pairs(rec) do if not deepEqual(v, stored[k]) then differs[#differs + 1] = k end end
            for k in pairs(stored) do if rec[k] == nil then differs[#differs + 1] = k end end
            check(deepEqual(rec, stored), "characters: unknown and secret reads keep the stored values (differs: " .. table.concat(differs, ",") .. ")")
            mock.level, mock.rankWindow.noData = 58, false
            mock.currencies[1792].quantity = 12345

            -- each moment that snapshots
            mock.deferTimers = true
            mock.timers = {}
            HonorLogDB.characters[key] = nil
            mock.level = 59
            mock.fireEvent("PLAYER_ENTERING_WORLD")
            rec = HonorLogDB.characters[key]
            check(rec and rec.level == 59 and rec.lastSeen == clock, "characters: entering the world snapshots")
            local late = false
            for _, t in ipairs(mock.timers) do if t.delay == 5 then late = true end end
            check(late, "characters: a second snapshot is scheduled five seconds later")
            mock.level = 60
            check(rec.level == 59, "characters: nothing changes before the five seconds are over")
            mock.advance(5)
            check(rec.level == 60, "characters: five seconds later snapshots again")
            mock.deferTimers, mock.timers = false, {}
            mock.level = 61
            HL:RecordGame("AV", true, 600, 90, 2)
            check(rec.level == 61 and rec.games == 3, "characters: a recorded game snapshots, with the new game counted")
            mock.level = 62
            HL:Fire("HonorLog_RankUp", 5, nil)
            check(rec.level == 62, "characters: a rank-up snapshots")
            mock.level = 63
            mock.fireEvent("PLAYER_LOGOUT")
            check(rec.level == 63, "characters: logout snapshots")

            -- two characters on one account
            local betaChar = DeepCopy(alphaChar)
            betaChar.goals.items = {}
            betaChar.battlegrounds = { WSG = { played = 5, wins = 4 } }
            HL.db.char = betaChar
            mock.playerName, mock.level, mock.faction = "Beta", 40, "Alliance"
            mock.currencies[1792].quantity = 700
            Characters:Snapshot()
            HL.db.char = alphaChar
            mock.playerName = "Alpha"
            local beta = HonorLogDB.characters["Beta-TestRealm"]
            check(beta and beta.name == "Beta" and beta.level == 40 and beta.faction == "Alliance" and beta.honor == 700 and beta.games == 5 and beta.wins == 4,
                "characters: a second character has its own record")
            check(beta.nextGoal == nil and rec.honor == 12345 and rec.level == 63 and rec.nextGoal == goalItem, "characters: the first character's record is untouched")

            -- the list, its order, current, stub and cappedNow
            local store = HonorLogDB.characters
            for k in pairs(store) do store[k] = nil end
            store[key] = { name = "Alpha", lastSeen = clock - 10, honor = 1000, capped = true, capUntil = clock + 500 }
            store["Beta-TestRealm"] = { name = "Beta", lastSeen = clock - 100, honor = 200, capped = true, capUntil = clock - 1 }
            store["Gamma-TestRealm"] = { name = "Gamma", lastSeen = clock - 50, capped = true, capUntil = clock + 1000 }
            store["Zed-TestRealm"] = { name = "Zed" }
            store["Abe-TestRealm"] = { name = "Abe" }
            store["Old"] = true
            local list = Characters:GetList()
            local order = {}
            for _, c in ipairs(list) do order[#order + 1] = c.name end
            check(table.concat(order, ",") == "Alpha,Gamma,Beta,Abe,Old,Zed", "characters: the current first, then newest seen, stubs last by name: " .. table.concat(order, ","))
            check(list[1].current and not list[2].current and list[1].key == key, "characters: current marks this character")
            check(not list[1].stub and not list[3].stub and list[4].stub and list[5].stub and list[6].stub, "characters: stub marks a record never snapshotted")
            check(list[1].cappedNow and list[2].cappedNow and not list[3].cappedNow and not list[4].cappedNow, "characters: cappedNow while capUntil is ahead")
            list[1].honor = 5
            check(store[key].honor == 1000, "characters: the list holds copies")
            local totals = Characters:GetTotals(list)
            check(totals.count == 6 and totals.honor == 205 and totals.cappedNow == 2, "characters: totals count, add the known honor and count the capped")
            check(Characters:GetTotals().count == 6 and Characters:GetTotals().honor == 1200, "characters: totals make the list when none is given")
            clock = clock + 2000
            list = Characters:GetList()
            check(not list[1].cappedNow and not list[2].cappedNow and Characters:GetTotals(list).cappedNow == 0, "characters: cappedNow ends with capUntil")
            store[key] = { name = "Alpha" }
            check(Characters:GetList()[1].current and Characters:GetList()[1].stub, "characters: the current character stays first even as a stub")
            store[key] = { name = "Alpha", lastSeen = clock }

            -- forget
            check(Characters:Forget("Beta-TestRealm") == true and store["Beta-TestRealm"] == nil, "characters: forget removes a deleted character")
            check(Characters:Forget(key) == false and store[key] ~= nil, "characters: forget refuses the current character")
            check(Characters:Forget("Nobody") == false and Characters:Forget(nil) == false, "characters: forget of nothing does nothing")
            check(Characters:Forget("Zed-TestRealm") == true, "characters: a stub can be forgotten")

            -- every client read nil, then every one a secret: nothing raises
            local nothing = function() end
            local secret = function() return mock.newSecret(), mock.newSecret(), mock.newSecret() end
            for _, answer in ipairs({ nothing, secret }) do
                withGlobals({
                    UnitClass = answer, UnitFactionGroup = answer, UnitLevel = answer, GetUnitName = answer, UnitName = answer,
                    GetRealmName = answer, GetMoney = answer,
                    C_CurrencyInfo = { GetCurrencyInfo = answer }, C_Item = { GetItemCount = answer },
                    C_MajorFactions = { GetMajorFactionProgressionInfo = answer, GetTotalReputationForRenownLevel = answer },
                    C_DateAndTime = { GetSecondsUntilWeeklyReset = answer }, C_SeasonInfo = { GetTimeUntilCurrentPVPSeasonEnd = answer },
                }, function()
                    local ok, err = pcall(Characters.Snapshot, Characters)
                    check(ok, "characters: a snapshot with every read unknown does not raise: " .. tostring(err))
                    check(pcall(Characters.GetList, Characters) and pcall(Characters.GetTotals, Characters), "characters: the readers do not raise either")
                end)
            end

            check(#mock.handledErrors == errorsBefore, "characters section reached no error handler: " .. tostring(mock.handledErrors[errorsBefore + 1]))
            restoreStores(kept)
        end)()

        --------------------------------------------------------------------
        -- Weeks
        --------------------------------------------------------------------
        ;(function()
            local kept = keepStores()
            local errorsBefore = #mock.handledErrors
            local Weeks = HL.Weeks
            local DAY = 86400
            HonorLogDB, HonorLogCharDB = nil, nil
            HL:InitializeDB()
            local c = HL.db.char
            mock.playerName = "Alpha"
            local T0 = realTime({ year = 2026, month = 11, day = 18, hour = 10, min = 0, sec = 0 })
            local ended = {}
            local listener = {}
            HL.RegisterCallback(listener, "HonorLog_WeekEnded", function(_, rec) ended[#ended + 1] = rec end)
            local function fresh(history)
                c.weeks, c.weeksFilled, c.since = {}, nil, nil
                c.history = history or {}
                c.honorLog = { day = 0, today = 0, weekEnd = 0, week = 0, session = 0 }
                c.rankWeeks = {}
                ended = {}
            end
            local function game(ts, bg, result, honor, marks)
                return { bgType = bg, result = result, win = result == "win", honor = honor, marks = marks, timestamp = ts, duration = 600 }
            end
            -- week 3, rank 4 with 300 points, cap 6, three days to the reset
            local function startWeek()
                clock = T0
                mock.weeklyReset = 3 * DAY
                setRank(4, 300, 6, 3, 5)
            end

            -- a week made with a real reset clock
            startWeek()
            fresh()
            local info = HL.Rank:GetInfo()
            local cur = Weeks:Current()
            check(cur.finish == T0 + 3 * DAY and cur.start == T0 - 4 * DAY and cur.estimated == nil, "weeks: a real clock gives a real finish, a week after the last reset")
            check(cur.number == 3 and cur.rankStart == info.totalPoints and cur.rankEnd == info.totalPoints, "weeks: number and the running total when it opens")
            check(c.weeks[1] == cur and #c.weeks == 1 and Weeks:GetCurrent() == cur and c.weeksFilled == true and type(c.since) == "number", "weeks: one record in the store, filled once, since set")
            check(cur.games == 0 and cur.honor == 0 and cur.bgHonor == 0 and next(cur.marks) == nil and cur.kills == 0 and cur.closed == nil, "weeks: it starts empty")

            -- a week with no clock is estimated, then corrected
            fresh()
            mock.weeklyReset = nil
            local est = Weeks:Current()
            check(est.estimated == true and est.start == T0 and est.finish == T0 + 7 * DAY and c.weeksFilled == nil, "weeks: with no clock the week is a guess of seven days")
            mock.weeklyReset = 0
            check(Weeks:Current() == est and est.estimated == true, "weeks: a reset clock of zero is no clock")
            clock = T0 + DAY
            mock.weeklyReset = 2 * DAY
            local fixed = Weeks:Current()
            check(fixed == est and fixed.estimated == nil and fixed.finish == clock + 2 * DAY and fixed.start == fixed.finish - 7 * DAY, "weeks: the first readable clock corrects the finish and the start")
            check(#c.weeks == 1 and #ended == 0 and c.weeksFilled == nil, "weeks: correcting turns nothing over, and the fill waits for a second reading of the clock")
            Weeks:Current()
            check(c.weeksFilled == true and #c.weeks == 1, "weeks: a second reading that agrees lets the fill run")

            -- the fill trusts no single reading of the reset clock
            startWeek()
            fresh()
            local firstSight = Weeks:Current()
            check(c.weeksFilled == nil, "weeks: the call that makes a record does not fill past weeks from its one reading")
            mock.weeklyReset = 3 * DAY - 2 * 3600
            check(Weeks:Current() == firstSight and c.weeksFilled == nil, "weeks: a second reading two hours off does not confirm it")
            mock.weeklyReset = 3 * DAY - 60
            clock = T0 + 60
            check(Weeks:Current() == firstSight and c.weeksFilled == true, "weeks: a later reading that names the same reset does")
            fresh()
            clock = T0
            mock.weeklyReset = 8 * DAY
            check(Weeks:Current().estimated == true, "weeks: a reset clock of more than a week is no clock")

            -- every accumulator
            startWeek()
            fresh()
            cur = Weeks:Current()
            local rankStart = cur.rankStart
            HL:RecordGame("WSG", true, 600, 100, 3, { result = "win" })
            setRank(5, 100, 6, 3, 5)
            HL:RecordGame("AV", false, 900, 250, 1, { result = "loss" })
            HL:RecordGame("AB", false, 300, 40, 0, { result = "draw" })
            HL:RecordGame("DI", false, 100, 0, 0, { result = "left" })
            check(cur.games == 4 and cur.wins == 1 and cur.losses == 1 and cur.draws == 1 and cur.left == 1, "weeks: each result in its own counter")
            check(cur.bgHonor == 390 and cur.honor == 0, "weeks: battleground honor from the games, not counted twice into honor")
            check(deepEqual(cur.marks, { WSG = 3, AV = 1 }), "weeks: marks by battleground")
            check(deepEqual(cur.best, { bgType = "AV", honor = 250, timestamp = clock }), "weeks: the best game is the one with the most honor")
            check(cur.rankStart == rankStart and cur.rankEnd == HL.Rank:GetInfo().totalPoints and cur.rankEnd > rankStart, "weeks: rankEnd follows a game, rankStart stays")
            local weekBefore = c.honorLog.week
            HL:AddHonorGain(50)
            HL:AddHonorGain(25)
            HL:AddHonorGain(-5)
            HL:AddHonorGain(0)
            HL:AddHonorGain("x")
            HL:AddHonorGain(mock.newSecret())
            check(cur.honor == 75 and c.honorLog.week == weekBefore + 75, "weeks: every positive honor gain through the hook, the original untouched")
            setRank(6, 0, 6, 3, 5)
            HL:Fire("HonorLog_RankUp", 6, HL.Rank:GetInfo())
            check(cur.rankEnd == HL.Rank:GetInfo().totalPoints, "weeks: a rank-up sets rankEnd")
            HL:Fire("HonorLog_WorldKill", { kb = true })
            HL:Fire("HonorLog_WorldKill", { kb = false })
            HL:Fire("HonorLog_WorldKill", "not a table")
            HL:Fire("HonorLog_WorldDeath", {})
            HL:Fire("HonorLog_WorldDeath")
            check(cur.kills == 3 and cur.killingBlows == 1 and cur.deaths == 2, "weeks: kills, killing blows and deaths")

            -- the recap of this week
            local recap = Weeks:GetRecap(0)
            check(recap.week == cur and recap.played == 4 and recap.wins == 1 and recap.losses == 1 and recap.draws == 1 and recap.left == 1, "recap: games and results")
            check(recap.honor == 75 and recap.honorPerGame == 97.5, "recap: honor, and battleground honor per game")
            check(deepEqual(recap.marks, { WSG = 3, AV = 1 }) and recap.marksTotal == 4, "recap: marks and their total")
            check(recap.rankGained == cur.rankEnd - cur.rankStart and recap.rankGained > 0, "recap: rank points gained")
            check(recap.best == cur.best and recap.kills == 3 and recap.deaths == 2 and recap.killingBlows == 1, "recap: best game, kills, deaths, killing blows")
            check(recap.nextCap and recap.nextCap.rank == 7 and deepEqual(recap.nextCap.unlocks, HL:GetRankUnlocks(7)), "recap: the cap of the week after, with what it unlocks")
            setRank(6, 0, 14, 3, 13)
            check(Weeks:GetRecap(0).nextCap == nil, "recap: no nextCap when the cap does not rise")
            setRank(6, 0, 6, 3, 5)
            cur.rankStart = nil
            mock.rankWindow.noData = true
            check(Weeks:GetRecap(0).rankGained == nil, "recap: no rank gain unless both totals are known")
            mock.rankWindow.noData = false
            cur.rankStart = rankStart
            check(Weeks:GetRecap(1) == nil and Weeks:GetRecap(-1) == nil and Weeks:GetRecap("x") == nil and Weeks:GetRecap(1.5) == nil, "recap: nil when there is no such week")

            -- turnover exactly at the reset
            clock = cur.finish - 1
            check(Weeks:Current() == cur and not cur.closed and #ended == 0, "weeks: one second before the reset nothing turns over")
            clock = cur.finish
            mock.weeklyReset = 7 * DAY
            setRank(6, 0, 7, 4, 6)
            local nextWeek = Weeks:Current()
            check(nextWeek ~= cur and cur.closed == true and #ended == 1 and ended[1] == cur, "weeks: at the reset the record closes and the event fires once with it")
            check(nextWeek.start == clock and nextWeek.finish == clock + 7 * DAY and nextWeek.estimated == nil and nextWeek.number == 4, "weeks: the new week starts at the reset")
            check(nextWeek.rankStart == cur.rankEnd and #c.weeks == 2 and c.weeks[1] == nextWeek and c.weeks[2] == cur, "weeks: the new week starts where the old one ended, newest first")
            Weeks:Current()
            Weeks:GetRecap(0)
            check(#ended == 1, "weeks: the event fires once")
            local last = Weeks:GetRecap(1)
            check(last.week == cur and last.played == 4 and last.honor == 75 and last.kills == 3 and last.nextCap and last.nextCap.rank == 7, "recap: the last closed week, with the cap that came after it")
            check(Weeks:GetRecap(2) == nil, "recap: nil past the oldest week")
            local now = Weeks:GetRecap(0)
            check(now.played == 0 and now.honorPerGame == nil and now.rankGained == 0 and now.best == nil and now.marksTotal == 0, "recap: an empty week")
            -- the client may still report the old week number just after a reset: it is not taken for the new week
            clock = nextWeek.finish
            mock.weeklyReset = 7 * DAY
            setRank(6, 0, 7, 4, 6)
            local stale = Weeks:Current()
            check(stale.number == nil and #ended == 2, "weeks: a week number equal to the last one's is not taken yet")
            setRank(6, 0, 7, 5, 6)
            check(Weeks:Current().number == 5 and Weeks:Current() == stale, "weeks: it is taken once the client moves on")

            -- a login after a missed reset: one new week, no empty ones
            clock = stale.finish + 20 * DAY
            mock.weeklyReset = 2 * DAY
            setRank(7, 0, 8, 9, 7)
            local back = Weeks:Current()
            check(#c.weeks == 4 and c.weeks[1] == back and c.weeks[2] == stale and #ended == 3 and ended[3] == stale, "weeks: three weeks away gives one new week")
            check(back.start == clock + 2 * DAY - 7 * DAY and back.finish == clock + 2 * DAY, "weeks: it starts at the most recent reset")
            -- a reset clock that already reads a new week while the stored finish is a moment away
            clock = back.finish - 1
            mock.weeklyReset = 7 * DAY
            local jumped = Weeks:Current()
            check(jumped ~= back and back.closed and #ended == 4 and jumped.start == back.finish, "weeks: a clock that has reset turns the week over a moment early, the new week starting where the old one was due to end")

            -- no clock: the chain of estimated weeks
            fresh()
            mock.weeklyReset = nil
            clock = T0
            local e1 = Weeks:Current()
            clock = T0 + 3 * DAY
            check(Weeks:Current() == e1 and #ended == 0, "weeks: an estimated week lasts seven days")
            clock = T0 + 17 * DAY
            local e2 = Weeks:Current()
            check(#c.weeks == 2 and e1.closed and e1.estimated == true and ended[1] == e1, "weeks: an estimated week closes and fires the event")
            check(e2.start == T0 + 14 * DAY and e2.finish == T0 + 21 * DAY and e2.estimated == true, "weeks: the next estimated week is the most recent boundary of the chain")

            -- the 26-record limit
            fresh()
            mock.weeklyReset = 7 * DAY
            clock = T0
            for _ = 1, 30 do
                clock = clock + 7 * DAY
                Weeks:Current()
            end
            check(#c.weeks == 26 and Weeks.KEPT == 26 and #ended == 29, "weeks: at most 26 records, the oldest dropped: " .. #c.weeks)
            local ordered = true
            for i = 1, #c.weeks - 1 do ordered = ordered and c.weeks[i].start > c.weeks[i + 1].start end
            check(ordered and c.weeks[1].start == clock and c.weeks[26].start == clock - 25 * 7 * DAY and not c.weeks[1].closed, "weeks: newest first, the newest open")

            -- the lazy fill (it runs on the second reading of the reset clock, so these read twice)
            local function twice() Weeks:Current() return Weeks:Current() end
            startWeek()
            local history = {
                game(T0 - 1 * DAY, "WSG", "win", 100, 3), game(T0 - 3 * DAY, "AV", "loss", 300, 1),
                game(T0 - 5 * DAY, "AB", "win", 150, 2), game(T0 - 6 * DAY, "AB", "loss", 50, 0),
                game(T0 - 19 * DAY, "WSG", "win", 80, 1),
            }
            fresh(DeepCopy(history))
            c.honorLog.weekEnd, c.honorLog.week = T0 + 3 * DAY + 1800, 777
            c.rankWeeks = { [3] = { startTotal = 3000, endTotal = 3500 }, [2] = { startTotal = 2400, endTotal = 3000 } }
            cur = twice()
            check(cur.games == 2 and cur.wins == 1 and cur.losses == 1 and cur.bgHonor == 400 and deepEqual(cur.marks, { WSG = 3, AV = 1 }) and cur.best.bgType == "AV" and cur.best.honor == 300,
                "fill: the current week is brought up to date from the saved games")
            check(cur.honor == 777 and cur.rankStart == 3000, "fill: honor from the honor log of the same week, the start total from the rank log")
            check(#c.weeks == 3 and c.weeksFilled == true, "fill: a record for each earlier week that has games")
            local prev, old = c.weeks[2], c.weeks[3]
            check(prev.filled and prev.closed and prev.start == cur.start - 7 * DAY and prev.finish == cur.start and prev.estimated == nil, "fill: an earlier week is filled and closed, with its dates")
            check(prev.games == 2 and prev.wins == 1 and prev.losses == 1 and prev.bgHonor == 200 and deepEqual(prev.marks, { AB = 2 }) and prev.best.bgType == "AB" and prev.best.honor == 150, "fill: its games, results, honor, marks and best")
            check(prev.number == 2 and prev.rankStart == 2400 and prev.rankEnd == 3000, "fill: its number and rank totals come from the rank log")
            check(prev.honor == nil and prev.kills == nil and prev.deaths == nil and prev.killingBlows == nil, "fill: what the saved games do not hold is left out")
            check(old.filled and old.start == cur.start - 21 * DAY and old.games == 1 and old.number == nil and old.rankStart == nil, "fill: a week before the first has no rank number to use, and the empty weeks between have no record")
            check(#ended == 0, "fill: it never fires the event")
            table.insert(c.history, game(T0 - 40 * DAY, "AV", "win", 10, 0))
            Weeks:Current()
            Weeks:GetRecap(0)
            check(#c.weeks == 3, "fill: it is done once")
            local filledRecap = Weeks:GetRecap(1)
            check(filledRecap.played == 2 and filledRecap.honor == nil and filledRecap.honorPerGame == 100 and filledRecap.kills == nil, "recap: a filled week leaves out what it does not know")

            -- a honor log of another week is not taken
            fresh(DeepCopy(history))
            c.honorLog.weekEnd, c.honorLog.week = T0 + 3 * DAY + 7200, 777
            check(twice().honor == 0 and c.weeksFilled == true, "fill: an honor log that ends at another reset is not taken")

            -- not while the finish is only a guess; then, once it is real, from the real start
            fresh(DeepCopy(history))
            mock.weeklyReset = nil
            local guess = Weeks:Current()
            check(guess.estimated and c.weeksFilled == nil and #c.weeks == 1 and guess.games == 0, "fill: not done while the finish is estimated")
            mock.weeklyReset = 3 * DAY
            check(Weeks:Current() == guess and guess.estimated == nil and guess.start == T0 - 4 * DAY and c.weeksFilled == nil, "fill: the reading that corrects the finish does not fill yet")
            check(Weeks:Current() == guess and guess.games == 2 and #c.weeks == 3, "fill: done once the finish is real and confirmed, from the real start of the week")

            -- a record that already covers an earlier week is not doubled
            fresh(DeepCopy(history))
            c.weeks = {
                { start = T0 - 4 * DAY, finish = T0 + 3 * DAY, games = 0, wins = 0, losses = 0, draws = 0, left = 0, honor = 0, bgHonor = 0, marks = {}, kills = 0, deaths = 0, killingBlows = 0 },
                { start = T0 - 11 * DAY, finish = T0 - 4 * DAY, closed = true, estimated = true, games = 9, wins = 0, losses = 0, draws = 0, left = 0, honor = 0, bgHonor = 0, marks = {} },
            }
            twice()
            check(#c.weeks == 3 and c.weeks[2].games == 9 and not c.weeks[2].filled and c.weeks[3].filled and c.weeks[3].games == 1, "fill: an existing record covering a week keeps it")

            -- the limit holds for the fill too
            local many = {}
            for k = 0, 39 do many[#many + 1] = game(T0 - 4 * DAY - k * 7 * DAY - DAY, "WSG", "win", 10, 0) end
            fresh(many)
            twice()
            check(#c.weeks == 26 and c.weeks[26].start == T0 - 4 * DAY - 25 * 7 * DAY and c.weeks[1].games == 0, "fill: at most 26 records, the oldest weeks dropped")

            -- the game and the honor gain whose call runs the fill are not counted twice
            fresh({ game(T0 - 1 * DAY, "WSG", "win", 100, 3) })
            Weeks:Current() -- makes the record; the fill still waits for a second reading
            local newGame = game(T0, "AB", "win", 200, 2)
            table.insert(c.history, 1, newGame) -- a recorded game is saved before its event fires
            Weeks:OnGame(newGame) -- the second reading: the fill runs inside this call
            check(c.weeksFilled == true and c.weeks[1].games == 2 and c.weeks[1].bgHonor == 300, "fill: the game whose event runs it is counted once: " .. tostring(c.weeks[1].games))
            Weeks:OnGame(game(T0, "AB", "loss", 50, 0))
            check(c.weeks[1].games == 3 and c.weeks[1].bgHonor == 350, "fill: ...and the next game is counted as usual")
            fresh({})
            c.honorLog.weekEnd, c.honorLog.week = T0 + 3 * DAY, 500 -- the honor log already holds the gain
            Weeks:Current()
            Weeks:OnHonor(40)
            check(c.weeksFilled == true and c.weeks[1].honor == 500, "fill: the honor gain whose call runs it is already in the honor log's total: " .. tostring(c.weeks[1].honor))
            Weeks:OnHonor(40)
            check(c.weeks[1].honor == 540, "fill: ...and the next gain is added")
            fresh({})
            c.honorLog.weekEnd, c.honorLog.week = T0 + 30 * DAY, 500 -- another week's log: not taken
            Weeks:Current()
            Weeks:OnHonor(40)
            check(c.weeksFilled == true and c.weeks[1].honor == 40, "fill: a gain is added when the fill took no honor total")

            -- entering the world turns the week over
            fresh()
            mock.fireEvent("PLAYER_ENTERING_WORLD")
            check(#c.weeks == 1, "weeks: entering the world makes the week")

            -- every client read nil, then every one a secret: nothing raises
            local nothing = function() end
            local secret = function() return mock.newSecret(), mock.newSecret(), mock.newSecret() end
            for _, answer in ipairs({ nothing, secret }) do
                fresh()
                withGlobals({
                    C_DateAndTime = { GetSecondsUntilWeeklyReset = answer },
                    C_MajorFactions = { GetMajorFactionProgressionInfo = answer, GetTotalReputationForRenownLevel = answer },
                    C_SeasonInfo = { GetTimeUntilCurrentPVPSeasonEnd = answer, GetCurrentDisplaySeasonID = answer },
                    GetCurrentArenaSeason = answer, UnitLevel = answer,
                }, function()
                    clock = T0
                    local ok, week = pcall(Weeks.Current, Weeks)
                    check(ok and week.estimated == true and week.number == nil and week.rankStart == nil, "weeks: with no readable client the week is a guess and has no rank data")
                    check(pcall(Weeks.GetRecap, Weeks, 0) and pcall(Weeks.GetRecap, Weeks, 1), "recap: the readers do not raise")
                    -- straight to this module's handlers: other listeners of these events are not under test here
                    Weeks:OnGame({ bgType = mock.newSecret(), result = mock.newSecret(), honor = mock.newSecret(), marks = mock.newSecret(), timestamp = mock.newSecret(), win = mock.newSecret() })
                    Weeks:OnGame(mock.newSecret())
                    Weeks:OnRankUp(mock.newSecret(), mock.newSecret())
                    HL:Fire("HonorLog_WorldKill", mock.newSecret())
                    HL:Fire("HonorLog_WorldKill", { kb = mock.newSecret() })
                    HL:Fire("HonorLog_WorldDeath", mock.newSecret())
                    HL:AddHonorGain(10)
                    check(week.games == 1 and week.wins == 0 and week.losses == 0 and week.bgHonor == 0 and next(week.marks) == nil and week.best == nil, "weeks: a game full of secrets counts as a game and nothing more")
                    check(week.kills == 2 and week.killingBlows == 0 and week.deaths == 1 and week.honor == 10, "weeks: secret kill, death and honor reads are counted or left out without raising")
                end)
            end

            HL.UnregisterCallback(listener, "HonorLog_WeekEnded")
            check(#mock.handledErrors == errorsBefore, "weeks section reached no error handler: " .. tostring(mock.handledErrors[errorsBefore + 1]))
            restoreStores(kept)
        end)()

        --------------------------------------------------------------------
        -- World log: the two events, the stored log, its readers, the weeks and the resets
        --------------------------------------------------------------------
        ;(function()
            local kept = keepStores()
            local errorsBefore = #mock.handledErrors
            local WorldLog = HL.WorldLog
            local DAY = 86400
            local T0 = realTime({ year = 2026, month = 11, day = 18, hour = 10, min = 0, sec = 0 })
            local saved = { zone = mock.zone, subzone = mock.subzone, map = { id = mock.map.id, x = mock.map.x, y = mock.map.y, restricted = mock.map.restricted },
                instance = mock.instance, target = mock.units.target, recap = mock.recap, hk = mock.pvp.sessionHK, clock = clock }
            HonorLogDB, HonorLogCharDB = nil, nil
            HL:InitializeDB()
            local c = HL.db.char
            mock.playerName = "Alpha"
            clock = T0
            mock.weeklyReset = 3 * DAY
            mock.zone, mock.subzone = "Hillsbrad Foothills", "Southshore"
            mock.map.id, mock.map.x, mock.map.y, mock.map.restricted = 1424, 0.5, 0.25, nil
            mock.units.target = nil
            mock.recap = {}
            mock.setInstance("Hillsbrad Foothills", "none", 0)

            check(type(c.worldLog) == "table" and #c.worldLog == 0 and WorldLog.KEPT == 500, "world log: a fresh character has an empty log, limit 500")

            local kills, deaths = {}, {}
            local listener = {}
            HL.RegisterCallback(listener, "HonorLog_WorldKill", function(_, entry) kills[#kills + 1] = entry end)
            HL.RegisterCallback(listener, "HonorLog_WorldDeath", function(_, entry) deaths[#deaths + 1] = entry end)

            -- the client's own sequence: a killing blow, the kill message, then the counter step
            mock.deferTimers = true
            mock.timers = {}
            mock.fireEvent("PLAYER_ENTERING_WORLD")
            local function step() mock.pvp.sessionHK = mock.pvp.sessionHK + 1; mock.fireEvent("PLAYER_PVP_KILLS_CHANGED"); mock.advance(3) end
            local function message(name, rank, honor)
                local text = rank and string.format(COMBATLOG_HONORGAIN, name, rank, honor) or string.format(COMBATLOG_HONORAWARD, honor)
                mock.fireEvent("CHAT_MSG_COMBAT_HONOR_GAIN", text)
            end
            local w = c.worldPvP

            -- a killing blow with a kill message
            mock.units.target = { name = "Evk", class = "MAGE", enemy = true, dead = false }
            mock.fireEvent("PARTY_KILL", "Player-1-1", "Player-2-77")
            message("Evk", "Corporal", 21)
            step()
            local e = kills[1]
            check(#kills == 1 and e.name == "Evk" and e.class == "MAGE" and e.kb == true and e.rank == "Corporal" and e.honor == 21, "events: a kill paired with its message carries name, class, killing blow, rank and honor")
            check(w.kills == 1 and w.killingBlows == 1 and w.honorKill == 21 and c.opponents.Evk.kills == 1, "events: the counters, the honor split and the opponents are as before")
            -- no killing blow
            message("Evl", "Private", 12)
            step()
            e = kills[2]
            check(e.name == "Evl" and e.kb == nil and e.rank == "Private" and e.honor == 12 and e.class == nil, "events: a kill without a killing blow has no kb, and no class when nobody in sight")
            -- no message: the dead enemy in sight
            mock.units.target = { name = "Evm", class = "ROGUE", enemy = true, dead = true }
            step()
            e = kills[3]
            check(e.name == "Evm" and e.class == "ROGUE" and e.rank == nil and e.honor == nil and e.kb == nil, "events: a kill with no message has no rank and honor")
            -- nobody
            mock.units.target = nil
            step()
            e = kills[4]
            check(#kills == 4 and e.name == nil and e.class == nil and e.rank == nil and e.honor == nil and w.unknownKills == 1, "events: a kill nobody could be named for has no name")
            -- an honor award is no kill
            message(nil, nil, 15)
            mock.advance(3)
            check(#kills == 4 and #deaths == 0 and w.honorAward == 15, "events: an honor award with no kill fires nothing")
            -- the direct call with no detail still works
            HL:RecordWorldKill("Direct", "WARRIOR", false)
            check(kills[5].name == "Direct" and kills[5].class == "WARRIOR" and kills[5].rank == nil and kills[5].honor == nil, "events: RecordWorldKill with no detail fires the entry without rank and honor")

            -- deaths
            mock.recap = { { timestamp = 103, sourceGUID = "Player-2-99", sourceName = "Evn" } }
            mock.fireEvent("PLAYER_DEAD")
            mock.advance(1.5)
            check(#deaths == 1 and deaths[1].name == "Evn" and deaths[1].class == "WARRIOR" and w.deaths == 1, "events: a death carries the killer's name and class")
            mock.recap = { { timestamp = 104, sourceGUID = "Player-2-98" } }
            mock.fireEvent("PLAYER_DEAD")
            mock.advance(1.5)
            check(#deaths == 2 and deaths[2].name == nil and deaths[2].class == "WARRIOR" and w.deaths == 2, "events: a death whose killer's name is unknown has no name")
            check(HL.db.char.opponents.Unknown == nil, "events: ...and no opponent called Unknown joins the tally")
            mock.recap = {}

            -- inside a battleground nothing fires
            mock.setInstance("Warsong Gulch", "pvp", 489)
            local killsBefore, deathsBefore, wKills, wDeaths = #kills, #deaths, w.kills, w.deaths
            mock.units.target = { name = "Evp", class = "MAGE", enemy = true, dead = true }
            mock.recap = { { timestamp = 105, sourceGUID = "Player-2-97", sourceName = "Evq" } }
            message("Evp", "Private", 10)
            step()
            mock.fireEvent("PARTY_KILL", "Player-1-1", "Player-2-77")
            mock.fireEvent("PLAYER_DEAD")
            mock.advance(5)
            check(#kills == killsBefore and #deaths == deathsBefore and w.kills == wKills and w.deaths == wDeaths, "events: inside a battleground nothing fires and nothing is counted")
            mock.recap, mock.units.target = {}, nil
            mock.setInstance("Hillsbrad Foothills", "none", 0)

            -- the log: every field of a kill and of a death
            local log = c.worldLog
            check(#log == #kills + #deaths and #log == 7, "log: one entry per kill and death: " .. #log)
            local first = log[#log] -- Evk, the oldest
            check(first.kind == "kill" and first.t == T0 and first.kb == true and first.name == "Evk" and first.class == "MAGE" and first.rank == "Corporal" and first.honor == 21, "log: a kill entry holds time, kind, killing blow, name, class, rank and honor")
            check(first.map == 1424 and first.x == 50 and first.y == 25 and first.zone == "Hillsbrad Foothills" and first.subzone == "Southshore", "log: and the place the client gave")
            local unnamed = log[#log - 3]
            check(unnamed.kind == "kill" and unnamed.name == nil and unnamed.kb == nil and unnamed.rank == nil and unnamed.honor == nil, "log: a kill nobody could be named for has no name, rank or honor")
            local death = log[2]
            check(death.kind == "death" and death.name == "Evn" and death.class == "WARRIOR" and death.kb == nil and death.rank == nil and death.honor == nil and death.zone == "Hillsbrad Foothills", "log: a death entry holds name, class and place only")
            check(log[1].kind == "death" and log[1].name == nil, "log: newest first")

            -- a place with no position, no map, no names
            mock.map.restricted = true
            mock.subzone = ""
            HL:RecordWorldKill("Nopos", "MAGE", false)
            e = log[1]
            check(e.name == "Nopos" and e.map == 1424 and e.x == nil and e.y == nil and e.zone == "Hillsbrad Foothills" and e.subzone == nil, "log: no position is left out, an empty subzone too")
            mock.map.restricted = nil
            withGlobals({
                GetRealZoneText = function() return mock.newSecret() end, GetSubZoneText = function() return mock.newSecret() end,
                C_Map = { GetBestMapForUnit = function() return mock.newSecret() end, GetPlayerMapPosition = function() return mock.newSecret() end },
            }, function()
                check(pcall(HL.RecordWorldKill, HL, "Secretplace", "MAGE", true), "log: a secret place raises nothing")
            end)
            e = log[1]
            check(e.name == "Secretplace" and e.kb == true and e.map == nil and e.x == nil and e.zone == nil and e.subzone == nil and e.t == T0, "log: a secret place is left out")
            local readLocation = HL.ReadVendorLocation
            HL.ReadVendorLocation = function() error("no reading") end
            check(pcall(HL.RecordWorldKill, HL, "Noread", "MAGE", false) and log[1].name == "Noread" and log[1].map == nil, "log: a failing place read still logs the entry")
            HL.ReadVendorLocation = nil
            check(pcall(HL.RecordWorldKill, HL, "Nofn", "MAGE", false) and log[1].name == "Nofn", "log: no place reader still logs the entry")
            HL.ReadVendorLocation = readLocation

            -- secret and wrong-typed entries
            local count = #log
            check(pcall(HL.Fire, HL, "HonorLog_WorldKill", { name = mock.newSecret(), class = mock.newSecret(), kb = mock.newSecret(), rank = mock.newSecret(), honor = mock.newSecret() }), "log: a kill of secrets raises nothing")
            e = log[1]
            check(#log == count + 1 and e.kind == "kill" and e.name == nil and e.class == nil and e.kb == nil and e.rank == nil and e.honor == nil, "log: secret values are left out")
            HL:Fire("HonorLog_WorldKill", { name = 5, class = {}, kb = "yes", rank = 7, honor = "12" })
            e = log[1]
            check(e.name == nil and e.class == nil and e.kb == nil and e.rank == nil and e.honor == nil, "log: values of the wrong type are left out")
            HL:Fire("HonorLog_WorldKill", mock.newSecret())
            HL:Fire("HonorLog_WorldKill", nil)
            HL:Fire("HonorLog_WorldDeath", mock.newSecret())
            HL:Fire("HonorLog_WorldDeath", { name = "", class = "" })
            check(#log == count + 6 and log[1].kind == "death" and log[1].name == nil and log[1].class == nil, "log: a secret or missing entry is a bare entry with the time and kind, an empty name is no name")

            -- the limit of 500, newest first
            for i = 1, 520 do HL:Fire("HonorLog_WorldKill", { name = "L" .. i }) end
            check(#log == 500 and log[1].name == "L520" and log[500].name == "L21", "log: at most 500 entries, the oldest dropped")
            HL:Fire("HonorLog_WorldDeath", { name = "Last" })
            check(#log == 500 and log[1].name == "Last" and log[500].name == "L22", "log: a death at the limit drops the oldest too")

            -- a listener that fails does not stop the counters, the tally or the log
            local errors = #mock.handledErrors
            local bad = {}
            HL.RegisterCallback(bad, "HonorLog_WorldKill", function() error("a failing listener") end)
            HL.RegisterCallback(bad, "HonorLog_WorldDeath", function() error("a failing listener") end)
            local k0, d0 = w.kills, w.deaths
            check(pcall(HL.RecordWorldKill, HL, "Failer", "MAGE", false), "failing listener: RecordWorldKill does not raise")
            check(pcall(HL.RecordWorldDeath, HL, "Failer", "MAGE"), "failing listener: RecordWorldDeath does not raise")
            check(w.kills == k0 + 1 and w.deaths == d0 + 1 and c.opponents.Failer.kills == 1 and c.opponents.Failer.deaths == 1, "failing listener: the counters and the opponents tally are updated")
            HL.UnregisterCallback(bad, "HonorLog_WorldKill")
            HL.UnregisterCallback(bad, "HonorLog_WorldDeath")
            HL.UnregisterCallback(listener, "HonorLog_WorldKill")
            HL.UnregisterCallback(listener, "HonorLog_WorldDeath")
            for i = #mock.handledErrors, errors + 1, -1 do table.remove(mock.handledErrors, i) end -- the failures above were on purpose

            -- the log's own handlers report a failure and never raise
            local failing = setmetatable({}, { __index = function() error("unreadable") end })
            local before = #mock.handledErrors
            check(pcall(HL.Fire, HL, "HonorLog_WorldKill", failing), "log: an entry that cannot be read raises nothing")
            check(#mock.handledErrors >= before, "log: the failure is for the error handler")
            for i = #mock.handledErrors, before + 1, -1 do table.remove(mock.handledErrors, i) end

            ----------------------------------------------------------------
            -- Readers, over a log made by hand
            ----------------------------------------------------------------
            local function at(t, kind, fields)
                local entry = { t = t, kind = kind }
                for k, v in pairs(fields or {}) do entry[k] = v end
                return entry
            end
            c.worldLog = {
                at(T0 - 60, "kill", { kb = true, name = "Alpha", honor = 20, zone = "Hillsbrad", subzone = "Tarren Mill", map = 1424, x = 50, y = 60 }),
                at(T0 - 120, "death", { name = "Bravo", zone = "Arathi", map = 1417 }),
                at(T0 - 180, "kill", { honor = 10, zone = "Hillsbrad", map = 1424, x = 40, y = 41 }),
                at(T0 - 240, "death", { name = "alphonse", zone = "Hillsbrad" }),
                at(T0 - DAY, "kill", { name = "Alpha", honor = 99, zone = "Arathi", subzone = "Refuge Pointe" }),
                at(T0 - DAY - 100, "death", { name = "Alpha" }),
                at(T0 - 2 * DAY, "kill", { name = "Charlie", subzone = "Lonely Hut" }),
                at(T0 - 3 * DAY, "death", { zone = "Alterac" }),
                at(T0 - 3 * DAY - 10, "death", { zone = "Alterac" }),
            }
            c.opponents = { Alpha = { class = "WARRIOR", kills = 3, deaths = 1, lastSeen = 1234 } }
            clock = T0

            -- GetToday
            local today = WorldLog:GetToday()
            check(today.kills == 2 and today.killingBlows == 1 and today.deaths == 2 and today.honor == 30 and today.named == 1, "today: kills, killing blows, deaths, honor and named kills")
            check(#today.deathZones == 2 and today.deathZones[1] == "Hillsbrad" and today.deathZones[2] == "Arathi", "today: the zones of today's deaths, in the order they happened")
            c.worldLog[3].kb = true
            check(WorldLog:GetToday().killingBlows == 2, "today: a second killing blow")
            c.worldLog[3].kb = nil
            -- the same zone twice is one zone; a death with no zone adds none
            table.insert(c.worldLog, 1, at(T0 - 30, "death", { zone = "Arathi" }))
            table.insert(c.worldLog, 1, at(T0 - 20, "death", {}))
            today = WorldLog:GetToday()
            check(today.deaths == 4 and #today.deathZones == 2, "today: each zone once, none for a death with no zone")
            table.remove(c.worldLog, 1); table.remove(c.worldLog, 1)
            -- midnight, with no reload
            clock = realTime({ year = 2026, month = 11, day = 18, hour = 23, min = 59, sec = 59 })
            check(WorldLog:GetToday().kills == 2, "today: one second before midnight it is still the same day")
            clock = clock + 1
            today = WorldLog:GetToday()
            check(today.kills == 0 and today.killingBlows == 0 and today.deaths == 0 and today.honor == 0 and today.named == 0 and #today.deathZones == 0, "today: at midnight the numbers start again")
            HL:RecordWorldKill("Newday", "MAGE", true, { rank = "Private", honor = 8 })
            today = WorldLog:GetToday()
            check(today.kills == 1 and today.killingBlows == 1 and today.honor == 8 and today.named == 1, "today: and count the new day's kill")
            table.remove(c.worldLog, 1)
            clock = T0

            -- GetList
            local rows = WorldLog:GetList()
            check(#rows == 9 and rows[1].name == "Alpha" and rows[9].zone == "Alterac" and rows[1].t > rows[2].t, "list: all rows, newest first")
            rows[1].name = "changed"
            check(c.worldLog[1].name == "Alpha", "list: rows are copies")
            check(#WorldLog:GetList({ kind = "all" }) == 9 and #WorldLog:GetList({ kind = "nonsense" }) == 9, "list: kind all, and an unknown kind is all")
            rows = WorldLog:GetList({ kind = "kill" })
            check(#rows == 4 and rows[1].kind == "kill" and rows[4].name == "Charlie", "list: kills only")
            rows = WorldLog:GetList({ kind = "death" })
            check(#rows == 5 and rows[1].name == "Bravo", "list: deaths only")
            rows = WorldLog:GetList({ name = "ALP" })
            check(#rows == 4 and rows[1].name == "Alpha" and rows[2].name == "alphonse", "list: a part of a name, in any case; unnamed rows never match")
            rows = WorldLog:GetList({ name = "alp", kind = "kill" })
            check(#rows == 2 and rows[1].t == T0 - 60 and rows[2].t == T0 - DAY, "list: kind and name together")
            check(#WorldLog:GetList({ name = "al.ha" }) == 0, "list: the name is not a pattern")
            check(#WorldLog:GetList({ name = "" }) == 9, "list: an empty name filters nothing")
            check(#WorldLog:GetList({ limit = 2 }) == 2 and #WorldLog:GetList({ limit = 0 }) == 0 and #WorldLog:GetList({ limit = 1000 }) == 9, "list: the limit")
            for i = 1, 150 do table.insert(c.worldLog, { t = T0 - 10 * DAY - i, kind = "kill" }) end
            check(#WorldLog:GetList() == 100 and #WorldLog:GetList({ limit = "x" }) == 100, "list: the default limit is 100")
            for _ = 1, 150 do table.remove(c.worldLog) end
            rows = WorldLog:GetList()
            check(rows[1].where == "Tarren Mill, Hillsbrad" and rows[2].where == "Arathi" and rows[7].where == "Lonely Hut" and rows[6].where == nil, "list: where as subzone and zone, either alone, or nothing")
            check(rows[1].place and rows[1].place.map == 1424 and rows[1].place.x == 50 and rows[1].place.y == 60 and rows[1].place.name == "Alpha" and rows[1].place.kind == "place" and rows[1].place.detail == "Tarren Mill, Hillsbrad", "list: a place with a map, a position and the player's name")
            check(rows[3].place and rows[3].place.name == "Unknown player", "list: an unnamed opponent is the unknown player")
            check(rows[2].place == nil and rows[4].place == nil and rows[5].place == nil, "list: no place without a position")
            check(HL:ShowPlaceOnMap(rows[1].place) == true, "list: the place is one the map pin accepts")
            HL:ClearMapPins()
            c.worldLog[2].x = mock.newSecret()
            check(WorldLog:GetList()[2].place == nil, "list: a position that is a secret is no place")
            c.worldLog[2].x = nil

            -- GetZones
            local zones = WorldLog:GetZones()
            check(#zones == 3 and zones[1].zone == "Hillsbrad" and zones[1].kills == 2 and zones[1].deaths == 1 and zones[1].total == 3, "zones: the zone with most fights first")
            check(zones[2].zone == "Alterac" and zones[2].total == 2 and zones[2].kills == 0 and zones[2].deaths == 2 and zones[3].zone == "Arathi" and zones[3].kills == 1 and zones[3].deaths == 1, "zones: equal fights by name; entries with no zone are in no row")
            check(#WorldLog:GetZones(1) == 1 and WorldLog:GetZones(1)[1].zone == "Hillsbrad" and #WorldLog:GetZones(0) == 0 and #WorldLog:GetZones(10) == 3, "zones: the limit")

            -- GetTotals
            c.since = T0 - 30 * DAY
            c.worldPvP = { kills = 7, deaths = 3, honor = 0, killingBlows = 4, unknownKills = 2 }
            HL.db.global.worldPvP = { kills = 70, deaths = 30, honor = 0, killingBlows = 40, unknownKills = 20 }
            local totals = WorldLog:GetTotals("character")
            check(totals.kills == 7 and totals.deaths == 3 and totals.killingBlows == 4 and totals.unknownKills == 2 and totals.since == T0 - 30 * DAY, "totals: the character's counters and since")
            totals = WorldLog:GetTotals("account")
            check(totals.kills == 70 and totals.deaths == 30 and totals.killingBlows == 40 and totals.unknownKills == 20 and totals.since == T0 - 30 * DAY, "totals: the account's counters, with this character's since")
            HL.db.settings.viewMode = "account"
            check(WorldLog:GetTotals().kills == 70, "totals: no scope is the saved view mode")
            HL.db.settings.viewMode = "character"
            check(WorldLog:GetTotals().kills == 7, "totals: ... character too")
            HL.db.char.worldPvP = {}
            check(WorldLog:GetTotals("character").kills == 0 and WorldLog:GetTotals("character").deaths == 0, "totals: a counter that is missing is zero")

            -- GetWith
            local with = WorldLog:GetWith("Alpha")
            check(with.name == "Alpha" and with.class == "WARRIOR" and with.kills == 3 and with.deaths == 1 and with.lastSeen == 1234, "with: the opponents tally")
            check(#with.rows == 3 and with.rows[1].t == T0 - 60 and with.rows[3].kind == "death" and with.rows[2].kind == "kill", "with: the log's rows with exactly that name, newest first")
            with = WorldLog:GetWith("Bravo")
            check(with.name == "Bravo" and with.kills == nil and with.deaths == nil and with.class == nil and with.lastSeen == nil and #with.rows == 1, "with: log rows but no tally")
            with = WorldLog:GetWith("Nobody")
            check(with.name == "Nobody" and with.kills == nil and #with.rows == 0, "with: nobody")
            check(#WorldLog:GetWith(nil).rows == 0 and #WorldLog:GetWith(5).rows == 0 and #WorldLog:GetWith(mock.newSecret()).rows == 0, "with: no usable name is nobody")
            c.opponents.Alpha = nil

            ----------------------------------------------------------------
            -- The weeks fill from the same two events
            ----------------------------------------------------------------
            c.weeks, c.weeksFilled, c.history = {}, nil, {}
            c.worldLog = {}
            c.worldPvP = HL.NewWorldStats()
            local week = HL.Weeks:Current()
            local wk0, wkb0, wd0 = week.kills, week.killingBlows, week.deaths
            mock.units.target = { name = "Wk1", class = "MAGE", enemy = true, dead = false }
            mock.fireEvent("PARTY_KILL", "Player-1-1", "Player-2-77")
            message("Wk1", "Private", 11)
            step()
            check(week.kills == wk0 + 1 and week.killingBlows == wkb0 + 1 and week.deaths == wd0, "weeks: a simulated kill with a killing blow is in the current week")
            message("Wk2", "Private", 11)
            step()
            check(week.kills == wk0 + 2 and week.killingBlows == wkb0 + 1, "weeks: a kill without a killing blow is a kill only")
            mock.recap = { { timestamp = 106, sourceGUID = "Player-2-96", sourceName = "Wk3" } }
            mock.fireEvent("PLAYER_DEAD")
            mock.advance(1.5)
            mock.recap = {}
            check(week.deaths == wd0 + 1 and HL.Weeks:Current() == week and #c.worldLog == 3, "weeks: a simulated death is in the current week, and the log has all three")
            mock.units.target = nil

            ----------------------------------------------------------------
            -- Resets
            ----------------------------------------------------------------
            c.history = { { timestamp = T0 - 10 * DAY, bgType = "AB", result = "win", honor = 100, marks = 1 } }
            check(#c.worldLog == 3 and #c.weeks >= 1, "resets: there is a log and there are weeks to reset")
            SlashCmdList.HONORLOG("reset character")
            check(#c.worldLog == 0 and #c.weeks == 0 and c.weeksFilled == true, "resets: /honorlog reset character empties the log and the weeks")
            c.history = { { timestamp = T0 - 10 * DAY, bgType = "AB", result = "win", honor = 100, marks = 1 } }
            local fresh = HL.Weeks:Current()
            check(#c.weeks == 1 and c.weeks[1] == fresh and fresh.games == 0 and not fresh.filled, "resets: no rebuild from saved games follows")
            -- the account reset leaves both
            HL:RecordWorldKill("Keep", "MAGE", false)
            local weekCount = #c.weeks
            SlashCmdList.HONORLOG("reset account")
            check(#c.worldLog == 1 and #c.weeks == weekCount, "resets: /honorlog reset account leaves the log and the weeks")
            -- today's reset too
            SlashCmdList.HONORLOG("reset today")
            check(#c.worldLog == 1 and #c.weeks == weekCount, "resets: /honorlog reset today leaves them as well")

            -- the small frame's menu
            local function entry(text)
                local list = {}
                mock.ddCollect = list
                _G.HonorLogContextMenu.__ddInit(_G.HonorLogContextMenu, 2, "RESET_STATS")
                mock.ddCollect = nil
                for _, info in ipairs(list) do if info.text == text then return info end end
                error("no menu entry " .. text)
            end
            HL:ShowContextMenu()
            c.history = {}
            HL.Weeks:Current()
            check(#c.worldLog == 1 and #c.weeks >= 1, "resets: the menu test starts with a log and weeks")
            entry("Account Stats").func()
            check(#c.worldLog == 1 and #c.weeks >= 1, "resets: the menu's account entry leaves both")
            entry("Character Stats").func()
            check(#c.worldLog == 0 and #c.weeks == 0 and c.weeksFilled == true, "resets: the menu's character entry empties the log and the weeks")
            c.history = { { timestamp = T0 - 10 * DAY, bgType = "AB", result = "win", honor = 100, marks = 1 } }
            fresh = HL.Weeks:Current()
            check(#c.weeks == 1 and not fresh.filled and fresh.games == 0, "resets: no rebuild follows the menu's reset either")

            -- with no database a reset and the readers do nothing and raise nothing
            local db = HL.db
            HL.db = nil
            check(pcall(WorldLog.Reset, WorldLog) and pcall(HL.Weeks.Reset, HL.Weeks) and #WorldLog:GetList() == 0 and WorldLog:GetToday().kills == 0, "resets: with no saved data they do nothing")
            HL.db = db

            check(#mock.handledErrors == errorsBefore, "world log section reached no error handler: " .. tostring(mock.handledErrors[errorsBefore + 1]))
            mock.zone, mock.subzone = saved.zone, saved.subzone
            mock.map.id, mock.map.x, mock.map.y, mock.map.restricted = saved.map.id, saved.map.x, saved.map.y, saved.map.restricted
            mock.instance, mock.units.target, mock.recap, mock.pvp.sessionHK, clock = saved.instance, saved.target, saved.recap, saved.hk, saved.clock
            restoreStores(kept)
        end)()
        --------------------------------------------------------------------
        -- Players met: the board event, the store, the readers and the resets
        --------------------------------------------------------------------
        ;(function()
            local kept = keepStores()
            local errorsBefore = #mock.handledErrors
            local Met = HL.Met
            HonorLogDB, HonorLogCharDB = nil, nil
            HL:InitializeDB()
            local c = HL.db.char
            mock.playerName = nil
            mock.deferTimers, mock.timers = true, {}
            resetPvP()
            local secret = mock.newSecret()

            local function brow(name, faction, kb, class)
                return { name = name, faction = faction, kb = kb or 0, hk = 0, deaths = 0, damage = 0, healing = 0, class = class }
            end
            local function fire(result, t, rows, me)
                HL:Fire("HonorLog_GameScoreboard", { rows = rows, me = me or brow("Tester", 1, 3), result = result, bgType = "WSG", timestamp = t })
            end
            check(type(c.met) == "table" and next(c.met) == nil and Met.KEPT == 1000 and Met:GetCount() == 0, "met: a fresh character has an empty store, limit 1000")

            -- a win, a loss, a draw
            fire("win", 1000, { brow("Tester", 1, 3, "WARRIOR"), brow("Ally", 1, 2, "MAGE"), brow("Foe", 0, 5, "ROGUE") })
            local ally, foe = Met:Get("Ally"), Met:Get("Foe")
            check(ally.with == 1 and ally.withWins == 1 and ally.against == 0 and ally.againstWins == 0 and ally.class == "MAGE" and ally.last == 1000, "met: a win with a teammate")
            check(foe.against == 1 and foe.againstWins == 1 and foe.with == 0 and foe.withWins == 0 and foe.kbBest == 5 and foe.class == "ROGUE", "met: a win against an opponent, their killing blows kept")
            check(Met:Get("Tester") == nil and Met:GetCount() == 2, "met: the player's own row is not stored")
            check(ally.kbBest == 0, "met: a teammate's killing blows are not an opponent's best")
            fire("loss", 2000, { brow("Tester", 1), brow("Ally", 1, 1), brow("Foe", 0, 3) })
            ally, foe = Met:Get("Ally"), Met:Get("Foe")
            check(ally.with == 2 and ally.withWins == 1 and foe.against == 2 and foe.againstWins == 1 and foe.kbBest == 5 and foe.last == 2000, "met: a loss counts the game and no win; kbBest only rises")
            check(ally.class == "MAGE" and foe.class == "ROGUE", "met: a row without a class does not erase it")
            fire("draw", 3000, { brow("Tester", 1), brow("Ally", 1), brow("Foe", 0, 8, "DRUID") })
            ally, foe = Met:Get("Ally"), Met:Get("Foe")
            check(ally.with == 3 and ally.withWins == 1 and foe.against == 3 and foe.againstWins == 1 and foe.kbBest == 8 and foe.class == "DRUID", "met: a draw counts the game with no win; kbBest rises; the class is the newest")
            fire("left", 4000, { brow("Tester", 1), brow("Ally", 1), brow("Foe", 0, 9), brow("Stranger", 0, 1) })
            check(Met:GetCount() == 2 and Met:Get("Ally").with == 3 and Met:Get("Foe").kbBest == 8 and Met:Get("Stranger") == nil, "met: a game left records nothing")
            fire("forfeit", 4000, { brow("Tester", 1), brow("Stranger", 0, 1) })
            check(Met:Get("Stranger") == nil, "met: an unknown result records nothing")

            -- the player's own row, with and without a realm suffix
            fire("win", 5000, { brow("Tester-Realm", 1, 1), brow("Tester", 1, 1), brow("Testerson", 1, 1), brow("Other-Realm", 0, 1) })
            check(Met:Get("Tester-Realm") == nil and Met:Get("Tester") == nil and Met:Get("Testerson") ~= nil and Met:Get("Other-Realm").against == 1,
                "met: the player's row is skipped with or without a realm suffix, a longer name is not the player")
            fire("win", 5001, { brow("Tester", 1, 1), brow("Mine", 1, 1) }, brow("Tester-Realm", 1, 3))
            fire("win", 5002, { brow("Tester-Realm", 1, 1), brow("Mine", 1, 1) }, brow("Tester", 1, 3))
            check(Met:Get("Tester") == nil and Met:Get("Tester-Realm") == nil and Met:Get("Mine").with == 2, "met: the board's own row is skipped as well")

            -- secret or malformed values are left out
            local before = Met:GetCount()
            local junk = { brow("Sec", 0, secret, "PRIEST"), { name = secret, faction = 0, kb = 1 }, { name = "NoFaction", kb = 1 }, { name = "TwoFaction", faction = 2 },
                { name = 7, faction = 0 }, "text", secret, { name = "", faction = 0 }, { name = "SecretFaction", faction = secret }, brow("Ok", 0, "many", secret) }
            check(pcall(fire, "win", 6000, junk), "met: a board with bad rows does not raise")
            local sec = Met:Get("Sec")
            check(sec and sec.against == 1 and sec.kbBest == 0 and sec.class == "PRIEST", "met: a secret killing-blow count is left out, the game still counts")
            check(Met:Get("Ok").against == 1 and Met:Get("Ok").kbBest == 0 and Met:Get("Ok").class == nil, "met: a killing-blow count that is not a number and a secret class are left out")
            check(Met:GetCount() == before + 2 and Met:Get("NoFaction") == nil and Met:Get("TwoFaction") == nil and Met:Get("") == nil and Met:Get("SecretFaction") == nil,
                "met: rows without a usable name or team are skipped")
            check(pcall(fire, "win", 6001, nil) and pcall(fire, "win", 6001, "x") and pcall(fire, "win", 6001, { brow("A", 0) }, secret) and pcall(fire, "win", 6001, { brow("A", 0) }, { name = "Tester" })
                and pcall(fire, secret, 6001, { brow("A", 0) }) and Met:Get("A") == nil,
                "met: a board without rows, without the player's row, or with a secret result raises nothing and stores nothing")
            fire("win", nil, { brow("NoTime", 0) })
            fire("win", secret, { brow("SecretTime", 0) })
            check(type(Met:Get("NoTime").last) == "number" and type(Met:Get("SecretTime").last) == "number" and not issecretvalue(Met:Get("SecretTime").last), "met: a board without a time, or with a secret one, is stamped with the current time")
            check(pcall(Met.OnScoreboard, Met, secret) and pcall(Met.OnScoreboard, Met, nil), "met: a secret or missing board raises nothing")

            -- the limit: the one seen longest ago goes, never one from the game being recorded
            c.met = {}
            local first, second = { brow("Tester", 1) }, {}
            for i = 1, 500 do first[#first + 1] = brow("P" .. i, 0) end
            for i = 501, 1000 do second[#second + 1] = brow("P" .. i, 0) end
            second[#second + 1] = brow("Tester", 1)
            fire("win", 100, first)
            fire("win", 200, second)
            check(Met:GetCount() == 1000, "met: a thousand players are kept")
            fire("win", 300, { brow("Tester", 1), brow("NewA", 0), brow("P3", 0) })
            check(Met:GetCount() == 1000 and Met:Get("P1") == nil and Met:Get("NewA") ~= nil and Met:Get("P3").last == 300 and Met:Get("P2") ~= nil,
                "met: the player seen longest ago is dropped (the earliest name among equals)")
            fire("win", 400, { brow("Tester", 1), brow("NewB", 0), brow("P2", 0) })
            check(Met:GetCount() == 1000 and Met:Get("P2").last == 400 and Met:Get("P10") == nil and Met:Get("NewB") ~= nil, "met: a player in the current game is never the one dropped")
            local many = { brow("Tester", 1) }
            for i = 1, 30 do many[#many + 1] = brow("Q" .. i, 0) end
            fire("win", 500, many)
            local gone = 0
            for i = 1, 500 do if Met:Get("P" .. i) == nil then gone = gone + 1 end end
            check(Met:GetCount() == 1000 and gone == 32 and Met:Get("Q30") ~= nil and Met:Get("P600") ~= nil, "met: thirty new players drop thirty of the oldest (" .. gone .. " gone)")
            c.met = {}

            -- the flow: the event after the game is saved, with every row
            local events, savedAtEvent = {}, {}
            local listener = {}
            HL.RegisterCallback(listener, "HonorLog_GameScoreboard", function(_, board)
                events[#events + 1] = board
                savedAtEvent[#savedAtEvent + 1] = #HL.db.char.history
            end)
            local function play(winner, ros)
                resetPvP()
                enter("Warsong Gulch", 489)
                mock.advance(100)
                mock.pvp.roster, mock.pvp.matchComplete = ros, true
                mock.fireEvent("PVP_MATCH_COMPLETE", winner, 300)
                mock.advance(25)
                leave()
            end
            local games0 = #c.history
            play(1, roster())
            check(#events == 1 and savedAtEvent[1] == games0 + 1 and #c.history == games0 + 1, "met flow: one event for the game, after it was saved")
            check(#events[1].rows == 4 and events[1].result == "win" and events[1].bgType == "WSG" and type(events[1].timestamp) == "number" and events[1].me.name == "Tester" and events[1].me.kb == 3,
                "met flow: the event carries every row, the player's own, the result, the battleground and a time")
            local a2, f1 = Met:Get("Ally2"), Met:Get("Foe1")
            check(a2.with == 1 and a2.withWins == 1 and f1.against == 1 and f1.againstWins == 1 and f1.kbBest == 5 and Met:Get("Foe2").kbBest == 2 and Met:Get("Tester") == nil and Met:GetCount() == 3,
                "met flow: the game's board is in the store")
            play(0, roster())
            check(#events == 2 and events[2].result == "loss" and Met:Get("Ally2").with == 2 and Met:Get("Ally2").withWins == 1 and Met:Get("Foe1").against == 2 and Met:Get("Foe1").againstWins == 1,
                "met flow: a lost game counts without a win")
            -- left before the end, and a board that never became readable
            resetPvP()
            enter("Warsong Gulch", 489)
            mock.advance(50)
            leave()
            local gamesLeft = #c.history
            check(#events == 2 and c.history[1].result == "left" and Met:Get("Ally2").with == 2, "met flow: a game left before the end fires nothing")
            resetPvP()
            enter("Warsong Gulch", 489)
            mock.advance(60)
            mock.pvp.roster, mock.pvp.scoresSecret, mock.pvp.matchComplete = roster(), true, true
            mock.fireEvent("PVP_MATCH_COMPLETE", 1, 300)
            mock.advance(25)
            leave()
            check(#c.history == gamesLeft + 1 and c.history[1].scoreboard == false and #events == 2 and Met:Get("Ally2").with == 2, "met flow: a board that was never readable fires nothing")

            -- a listener that raises changes nothing in the saved game and is reported once
            local function essence(g)
                return table.concat({ tostring(g.result), tostring(g.honor), tostring(g.marks), tostring(g.kb), tostring(g.hk), tostring(g.deaths), tostring(g.damage),
                    tostring(g.healing), tostring(g.duration), tostring(g.scoreboard), tostring(g.rankPoints), tostring(g.teams[1].players), tostring(g.teams[0].kb) }, "|")
            end
            play(1, roster())
            local plain = essence(c.history[1])
            local secureBefore = #mock.secureErrors
            local thrower = {}
            HL.RegisterCallback(thrower, "HonorLog_GameScoreboard", function() error("listener broke") end)
            local nGames = #c.history
            play(1, roster())
            check(#c.history == nGames + 1 and essence(c.history[1]) == plain, "met flow: a listener that raises leaves the saved game as it was")
            check(#mock.secureErrors == secureBefore + 1 and #mock.handledErrors == errorsBefore and Met:Get("Ally2").with == 4, "met flow: the failure is reported once and the store still got the game")
            HL.UnregisterCallback(thrower, "HonorLog_GameScoreboard")
            for i = #mock.secureErrors, secureBefore + 1, -1 do mock.secureErrors[i] = nil end
            local rowsSaved = false
            for _, g in ipairs(c.history) do
                for k, v in pairs(g) do
                    if k == "rows" or k == "players" or k == "board" then rowsSaved = true end
                    if type(v) == "table" and type(v[1]) == "table" and v[1].name then rowsSaved = true end
                end
                if g.teams and (g.teams[1][1] ~= nil or g.teams[0][1] ~= nil) then rowsSaved = true end
            end
            check(not rowsSaved, "met flow: no saved game holds a per-player row")

            -- a reload in the middle of the wait: the board comes back from bgState.match
            local foe2Before, eventsBefore = Met:Get("Foe2").against, #events
            resetPvP()
            enter("Warsong Gulch", 489)
            mock.advance(100)
            mock.pvp.roster, mock.pvp.matchComplete = roster(), true
            mock.fireEvent("PVP_MATCH_COMPLETE", 1, 300)
            local waiting = c.bgState
            check(waiting.isInBG and waiting.match.sbState == "accepted" and #waiting.match.sb.rows == 4, "met flow: the board waits in bgState.match, rows and all")
            local copy = HL.Util.DeepCopy(waiting.match)
            c.bgState = { isInBG = true, currentBG = copy.bgType, match = copy }
            mock.timers = {}
            local gamesBeforeReload = #c.history
            HL:RestoreBGState()
            mock.advance(25)
            check(#c.history == gamesBeforeReload + 1 and #events == eventsBefore + 1 and #events[#events].rows == 4 and Met:Get("Foe2").against == foe2Before + 1,
                "met flow: a reload before the game is recorded still gives the event and the records")
            leave()
            check(c.bgState.isInBG == false, "met flow: the board is gone from bgState once the game is over")
            HL.UnregisterCallback(listener, "HonorLog_GameScoreboard")

            -- an error inside the module is reported once and never raised
            local reported = #mock.handledErrors
            local boom = setmetatable({}, { __index = function() error("row broke") end })
            check(pcall(HL.Fire, HL, "HonorLog_GameScoreboard", { rows = { boom }, me = brow("Tester", 1), result = "win", timestamp = 1 }) and #mock.handledErrors == reported + 1,
                "met: a failure inside the module is reported once and not raised")
            mock.handledErrors[#mock.handledErrors] = nil

            -- the readers
            c.met = {
                alice = { class = "MAGE", with = 5, withWins = 4, against = 0, againstWins = 0, kbBest = 0, last = 10 },
                bob = { with = 5, withWins = 4, against = 4, againstWins = 0, kbBest = 7, last = 20 },
                carl = { with = 6, withWins = 4, against = 0, againstWins = 0, kbBest = 0, last = 30 },
                dan = { with = 10, withWins = 8, against = 3, againstWins = 1, kbBest = 9, last = 40 },
                eve = { with = 2, withWins = 2, against = 3, againstWins = 1, kbBest = 9, last = 50 },
                x = { with = 0, withWins = 0, against = 4, againstWins = 0, kbBest = 2, last = 60 },
                y = { with = 0, withWins = 0, against = 6, againstWins = 0, kbBest = 9, last = 70 },
                zed = { with = 0, withWins = 0, against = 3, againstWins = 1, kbBest = 12, last = 80 },
                zack = { with = 0, withWins = 0, against = 3, againstWins = 1, kbBest = 1, last = 90 },
                q = { with = 0, withWins = 0, against = 2, againstWins = 0, kbBest = 4, last = 95 },
                broken = "text", [5] = { with = 9 },
            }
            local function names(rows) local t = {} for i, r in ipairs(rows) do t[i] = r.name end return table.concat(t, ",") end
            check(names(Met:GetList("allies")) == "dan,alice,bob,carl", "readers: allies by win rate, then games, then name; three games at least: " .. names(Met:GetList("allies")))
            check(names(Met:GetList("allies", nil, 2)) == "eve,dan,alice,bob,carl", "readers: allies with minGames 2 adds the pair that played twice")
            check(names(Met:GetList("allies", 20, 6)) == "dan,carl", "readers: allies with minGames 6")
            check(names(Met:GetList("rivals")) == "y,bob,x,dan,eve,zack,zed", "readers: rivals by the lowest win rate, then games, then name: " .. names(Met:GetList("rivals")))
            check(names(Met:GetList("rivals", 20, 4)) == "y,bob,x" and names(Met:GetList("rivals", 20, 2)):sub(1, 3) == "y,b" and select(2, names(Met:GetList("rivals", 20, 2)):gsub(",", ",")) == 7, "readers: rivals with minGames 4 and 2")
            check(names(Met:GetList("killers")) == "zed,y,dan,eve,bob,q,x,zack", "readers: killers by killing blows, then games against, then name: " .. names(Met:GetList("killers")))
            check(names(Met:GetList("killers", 20, 4)) == "y,bob,x" and names(Met:GetList("killers", 20, 3)) == "zed,y,dan,eve,bob,x,zack", "readers: killers with minGames 4 and 3")
            local r1 = Met:GetList("allies")[1]
            check(r1.name == "dan" and r1.class == nil and r1.games == 10 and r1.wins == 8 and r1.rate == 0.8 and r1.kbBest == 9 and r1.last == 40, "readers: a row has name, class, games, wins, rate, kbBest, last")
            local k1 = Met:GetList("killers")[1]
            check(k1.name == "zed" and k1.games == 3 and k1.wins == 1 and k1.kbBest == 12 and math.abs(k1.rate - 1 / 3) < 1e-9, "readers: killers count the games against")
            local rv = Met:GetList("rivals")[1]
            check(rv.name == "y" and rv.games == 6 and rv.wins == 0 and rv.rate == 0, "readers: rivals count the games against, rate is the player's wins")
            check(Met:GetList("allies")[2].class == "MAGE", "readers: the class is passed on")
            check(#Met:GetList("allies", 2) == 2 and #Met:GetList("allies", 0) == 0 and #Met:GetList("allies", -3) == 0 and #Met:GetList("allies", "x") == 4 and #Met:GetList("allies", 2.9) == 2, "readers: the limit")
            check(#Met:GetList("nonsense") == 0 and #Met:GetList() == 0 and #Met:GetList(secret) == 0, "readers: an unknown kind is empty")
            check(Met:Get("alice").with == 5 and Met:Get("nobody") == nil and Met:Get(nil) == nil and Met:Get(5) == nil and Met:Get(secret) == nil, "readers: Get gives a known record and nil for others")
            local copyRec = Met:Get("alice")
            copyRec.with = 99
            check(c.met.alice.with == 5, "readers: Get gives a copy")
            check(Met:GetCount() == 10, "readers: GetCount counts the usable records")
            local big = {}
            for i = 1, 25 do big["k" .. i] = { against = 1, againstWins = 0, kbBest = i } end
            c.met = big
            check(#Met:GetList("killers") == 20 and Met:GetList("killers")[1].name == "k25" and #Met:GetList("killers", 25) == 25, "readers: the default limit is 20")
            c.met = {}
            check(#Met:GetList("allies") == 0 and #Met:GetList("rivals") == 0 and #Met:GetList("killers") == 0 and Met:GetCount() == 0, "readers: an empty store gives empty lists")

            -- the resets
            local function entry(text)
                local list = {}
                mock.ddCollect = list
                _G.HonorLogContextMenu.__ddInit(_G.HonorLogContextMenu, 2, "RESET_STATS")
                mock.ddCollect = nil
                for _, info in ipairs(list) do if info.text == text then return info end end
                error("no menu entry " .. text)
            end
            HL:ShowContextMenu()
            local function seed() c.met = { alice = { with = 1, withWins = 1, against = 0, againstWins = 0, kbBest = 0, last = 1 } } end
            seed()
            SlashCmdList.HONORLOG("reset account")
            check(Met:GetCount() == 1, "resets: /honorlog reset account leaves the players met")
            SlashCmdList.HONORLOG("reset character")
            check(Met:GetCount() == 0 and type(c.met) == "table", "resets: /honorlog reset character empties them")
            seed()
            entry("Account Stats").func()
            check(Met:GetCount() == 1, "resets: the menu's account entry leaves them")
            entry("Character Stats").func()
            check(Met:GetCount() == 0, "resets: the menu's character entry empties them")
            local db = HL.db
            HL.db = nil
            check(pcall(Met.Reset, Met) and pcall(Met.OnScoreboard, Met, { rows = {}, me = brow("Tester", 1), result = "win" }) and #Met:GetList("allies") == 0 and Met:GetCount() == 0 and Met:Get("a") == nil,
                "met: with no saved data everything does nothing")
            HL.db = db

            check(#mock.handledErrors == errorsBefore, "met section reached no error handler: " .. tostring(mock.handledErrors[errorsBefore + 1]))
            restoreStores(kept)
        end)()
        setGlobal("time", realTime)
    end)()

    -- A secret answer for the honor currency or the rank data is never indexed: the reads say "unknown"
    -- (honor 0, no cap, no rank data) and nothing that builds on them raises.
    ;(function()
        local realCurrency, realRank = C_CurrencyInfo.GetCurrencyInfo, C_MajorFactions.GetMajorFactionProgressionInfo
        local errorsBefore = #mock.handledErrors
        C_CurrencyInfo.GetCurrencyInfo = function() return mock.newSecret() end
        check(HL:GetCurrentHonor() == 0 and HL:GetHonorCap() == nil, "secret reads: a secret honor record reads as honor 0 and no cap")
        local summary = HL:GetHonorSummary()
        check(summary.current == 0 and summary.cap == 0 and summary.percent == 0, "secret reads: the honor summary holds no secret")
        check(pcall(HL.GetAllGoalsProgress, HL) and pcall(HL.GetHonorCapAdvice, HL), "secret reads: goal progress and the cap advice do not raise")
        C_CurrencyInfo.GetCurrencyInfo = function() return { quantity = mock.newSecret(), maxQuantity = mock.newSecret() } end
        check(HL:GetCurrentHonor() == 0 and HL:GetHonorCap() == nil and HL:GetHonorSummary().current == 0, "secret reads: secret amounts inside a readable record read as unknown")
        C_CurrencyInfo.GetCurrencyInfo = function() error("blocked") end
        check(HL:GetCurrentHonor() == 0 and HL:GetHonorCap() == nil, "secret reads: a currency read that raises reads as unknown")
        C_CurrencyInfo.GetCurrencyInfo = realCurrency
        C_MajorFactions.GetMajorFactionProgressionInfo = function() return mock.newSecret() end
        local ok, info = pcall(HL.Rank.GetInfo, HL.Rank)
        check(ok and info == nil, "secret reads: secret rank data reads as no rank data: " .. tostring(info))
        check(pcall(HL.Rank.GetPace, HL.Rank) and pcall(HL.GetAdvice, HL, 3), "secret reads: the pace and the advice do not raise without rank data")
        C_MajorFactions.GetMajorFactionProgressionInfo = realRank
        check(HL:GetCurrentHonor() == mock.currencies[1792].quantity and type(HL.Rank:GetInfo()) == "table", "secret reads: the real reads are back")
        check(#mock.handledErrors == errorsBefore, "secret reads: nothing reached the error handler: " .. tostring(mock.handledErrors[errorsBefore + 1]))
    end)()

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
