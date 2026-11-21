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

        -- The waypoint.
        mock.waypoint, mock.superTracked = nil, nil
        before = #printed
        v = HL:GetVendorFor(BLUE)
        check(HL:ShowVendorOnMap(v) == true, "ShowVendorOnMap with coordinates returns true")
        check(mock.waypoint and mock.waypoint.uiMapID == 1453 and near(mock.waypoint.position.x, 0.744, 1e-6) and near(mock.waypoint.position.y, 0.675, 1e-6), "the waypoint is set at x / 100, y / 100")
        check(mock.superTracked == true, "the waypoint is super-tracked")
        check(table.concat(printed, "\n", before + 1):find("Captain Dirgehammer, Champions' Hall, Stormwind City", 1, true), "one line names the vendor and place")
        mock.waypoint = nil
        mock.faction = "Horde"
        before = #printed
        check(HL:ShowVendorOnMap(HL:GetVendorFor(HORDE_ARMOR)) == false and mock.waypoint == nil, "no coordinates: false, no waypoint")
        check(table.concat(printed, "\n", before + 1):find("Lady Palanseer, Hall of Legends, Orgrimmar: open this vendor once and HonorLog will remember where it stands.", 1, true), "…and the line says to open the vendor once")
        mock.faction = "Alliance"
        mock.waypointBlocked = true
        check(HL:ShowVendorOnMap(v) == false and mock.waypoint == nil, "a map that cannot take a waypoint: false")
        mock.waypointBlocked = false
        local savedSuper = C_SuperTrack
        C_SuperTrack = nil
        check(HL:ShowVendorOnMap(v) == true and mock.waypoint ~= nil, "without C_SuperTrack the waypoint is still set")
        C_SuperTrack = savedSuper
        local savedMapAPI = C_Map
        C_Map = nil
        check(HL:ShowVendorOnMap(v) == false, "without C_Map: false, no error")
        C_Map = savedMapAPI
        check(HL:ShowVendorOnMap(nil) == false, "no vendor: false")

        -- Tooltips and Alt+Click on a goal card and a picker row.
        HL:AddGoal(BLUE)
        HL:UpdateGoalsPanel()
        card = goalsPanel.goalCards[1]
        tipLines = {}
        card:GetScript("OnEnter")(card)
        check(tipHas("Sold by Captain Dirgehammer, Champions' Hall, Stormwind City") and tipHas("Alt+Click to show the vendor on the map"), "goal card tooltip: sold by, and the Alt+Click hint")
        mock.waypoint = nil
        card:GetScript("OnMouseUp")(card, "LeftButton")
        check(mock.waypoint == nil, "a plain click on a card sets no waypoint")
        mock.alt = true
        card:GetScript("OnMouseUp")(card, "LeftButton")
        check(mock.waypoint and mock.waypoint.uiMapID == 1453, "Alt+Click on a goal card sets the waypoint")
        mock.alt = false
        HL:RemoveGoal(BLUE)
        picker.filters.class = "WARRIOR"
        picker:RefreshItems()
        local prow = pickerRow(BLUE)
        check(prow ~= nil, "the picker lists the helm again")
        tipLines = {}
        prow:GetScript("OnEnter")(prow)
        check(tipHas("Sold by Captain Dirgehammer, Champions' Hall, Stormwind City") and tipHas("Alt+Click to show the vendor on the map"), "picker row tooltip: sold by, and the Alt+Click hint")
        mock.waypoint, mock.alt = nil, true
        prow:GetScript("OnMouseUp")(prow, "LeftButton")
        check(mock.waypoint and mock.waypoint.uiMapID == 1453, "Alt+Click on a picker row sets the waypoint")
        mock.alt = false
        picker:Hide()

        -- /honorlog vendor
        HL:AddGoal(EPIC)
        mock.waypoint = nil
        before = #printed
        slash("vendor 1")
        check(mock.waypoint and mock.waypoint.uiMapID == 1453, "/honorlog vendor 1: the first goal's vendor")
        mock.waypoint = nil
        slash("vendor item " .. BLUE)
        check(mock.waypoint and table.concat(printed, "\n", before + 1):find("Waypoint set for Captain Dirgehammer", 1, true), "/honorlog vendor <item name>: any gear item")
        mock.waypoint = nil
        slash("vendor zzz no such thing")
        check(mock.waypoint == nil and table.concat(printed, "\n", before + 1):find("No gear item matches", 1, true), "/honorlog vendor: an unknown name says so")
        slash("vendor")
        check(table.concat(printed, "\n", before + 1):find("Usage: /honorlog vendor", 1, true), "/honorlog vendor with nothing prints the usage")
        slash("goal vendor 1")
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
        slash("probe off")
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
