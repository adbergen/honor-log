-- A HonorLog 2.0 save (saved-data version 2), synthetic: invented names only. The version 3 migration must
-- change only `dbVersion`, the account's `characters` values (true -> { name = key }) and add `since` to the
-- character store; every other key must come out deep-equal to what it is here (the going-back guarantee).
local function bg(played, wins, losses, draws, left, duration, honor, marks)
    return { played = played, wins = wins, losses = losses, draws = draws, left = left, totalDuration = duration,
        honorLifetime = honor, marksLifetime = marks, cappedPlayed = 0, cappedHonor = 0 }
end

local function makeHistory()
    return {
        { bgType = "WSG", win = true, result = "win", duration = 700, honor = 250, marks = 3, timestamp = 1790000300,
            character = "Fenwick Tally", kb = 2, hk = 9, deaths = 1, rankPoints = 40 },
        { bgType = "AB", win = false, result = "loss", duration = 900, honor = 120, marks = 1, timestamp = 1790000200,
            character = "Fenwick Tally", rankState = { level = 2 } },
        { bgType = "AV", win = true, result = "win", duration = 1500, honor = 400, marks = 3, timestamp = 1789990000,
            character = "Fenwick Tally", honorCapped = true },
    }
end

return {
    global = {
        battlegrounds = {
            AV = bg(10, 6, 3, 1, 0, 9000, 4100, 30), AB = bg(20, 12, 7, 0, 1, 16000, 7000, 50),
            WSG = bg(30, 15, 14, 0, 1, 18000, 8800, 40), DI = bg(2, 1, 1, 0, 0, 900, 300, 2),
        },
        worldPvP = { kills = 14, deaths = 6, honor = 900, honorKill = 700, honorAward = 200, killingBlows = 5, unknownKills = 1 },
        history = makeHistory(),
        historyLimit = 200,
        scannedGear = { [272738] = { honor = 1000, seen = 5 } },
        scannedVendors = {},
        characters = { ["Fenwick Tally"] = true, ["Marla Quill-Testrealm"] = true },
        legacy = { EotS = bg(8, 5, 3, 0, 0, 7000, 2500, 20) },
        questRewards = { [96912] = { count = 2, last = 1789999999, level = 60 } },
        settings = {
            frameVisible = true, viewMode = "account",
            visibleCards = { AV = true, AB = true, WSG = true, DI = true, World = true },
        },
        dbVersion = 2,
    },
    char = {
        battlegrounds = {
            AV = bg(10, 6, 3, 1, 0, 9000, 4100, 30), AB = bg(20, 12, 7, 0, 1, 16000, 7000, 50),
            WSG = bg(30, 15, 14, 0, 1, 18000, 8800, 40), DI = bg(2, 1, 1, 0, 0, 900, 300, 2),
        },
        worldPvP = { kills = 14, deaths = 6, honor = 900, honorKill = 700, honorAward = 200, killingBlows = 5, unknownKills = 1 },
        history = makeHistory(),
        historyLimit = 200,
        legacy = { EotS = bg(8, 5, 3, 0, 0, 7000, 2500, 20) },
        opponents = { Villain = { class = "MAGE", kills = 2, deaths = 1, lastSeen = 1790000100 } },
        honorLog = { day = 20261120, today = 150, weekEnd = 1790500000, week = 900, session = 150 },
        honorDays = { ["20261120"] = 150 },
        honorCapWarned = false,
        rankWeeks = { [3] = { startTotal = 2400, endTotal = 3100, games = 12, capRank = 6 } },
        rankCapAlertWeek = 3,
        rankCelebrated = 3,
        goals = {
            items = { { itemID = 272738, addedAt = 1, priority = 1 } }, completed = {},
            settings = { autoRemoveCompleted = false, showInLDB = true, celebrateCompletion = true },
        },
        session = {
            AV = { played = 0, wins = 0, losses = 0, draws = 0, left = 0, honor = 0, marks = 0 },
            AB = { played = 1, wins = 0, losses = 1, draws = 0, left = 0, honor = 120, marks = 1 },
            WSG = { played = 1, wins = 1, losses = 0, draws = 0, left = 0, honor = 250, marks = 3 },
            DI = { played = 0, wins = 0, losses = 0, draws = 0, left = 0, honor = 0, marks = 0 },
            worldPvP = { kills = 2, deaths = 1, honor = 60 },
        },
        sessionDate = 20261120,
        lastGameTime = 100,
        bgState = { isInBG = false },
        dbVersion = 2,
    },
}
