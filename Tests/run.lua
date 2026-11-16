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
        "Modules/DI.lua", "Modules/VendorScanner.lua", "Modules/Probe.lua",
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
    mock.rank = { level = 3, earned = 1000, threshold = 1050 }
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
    check(game.rankPoints == 90, "rank delta across a level: 50 left + 40 into the next = " .. tostring(game.rankPoints))
    check(game.marks == 1 and game.honor == 120, "DI marks and honor")
    check(HL.db.char.battlegrounds.DI.losses == 1 and HL.db.char.battlegrounds.DI.wins == 0, "DI stats")
    check(HL.RankDelta({ level = 2, earned = 100, threshold = 900 }, { level = 5, earned = 10 }) == 800 + 1050 + 1200 + 10, "rank delta spans skipped levels with the curve")

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

    -- 11. Migration: a TBC-era save with EotS and arena fields loads, migrates, keeps its history.
    local fixture = dofile(ROOT .. "/Tests/fixtures/tbc_savedvars.lua")
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
