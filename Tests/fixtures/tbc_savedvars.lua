-- A HonorLog 1.x (TBC Classic Anniversary) save, as the client wrote it, for the
-- migration test: Eye of the Storm and arena fields, old-style history entries
-- (win/duration/honor/marks only), a TBC mid-game bgState and a session that
-- still lists EotS. Version 2 must keep the history and move the rest to `legacy`.
local function bg(played, wins, losses, duration, honor, marks)
    return { played = played, wins = wins, losses = losses, totalDuration = duration,
        honorLifetime = honor, marksLifetime = marks }
end

local function makeHistory()
    return {
    { bgType = "EotS", win = true, duration = 900, honor = 310, marks = 3, timestamp = 1760000000, character = "Oldchar" },
    { bgType = "WSG", win = false, duration = 640, honor = 180, marks = 1, timestamp = 1759990000, character = "Oldchar" },
    { bgType = "AB", win = true, duration = 1100, honor = 420, marks = 3, timestamp = 1759980000, character = "Oldchar" },
    }
end

return {
    global = {
        battlegrounds = {
            AV = bg(10, 6, 4, 9000, 4100, 30),
            AB = bg(20, 12, 8, 16000, 7000, 50),
            WSG = bg(30, 15, 15, 18000, 8800, 40),
            EotS = bg(8, 5, 3, 7000, 2500, 20),
            Arena2v2 = bg(4, 2, 2, 800, 0, 0), -- arena aggregate some test builds kept
        },
        worldPvP = { kills = 14, deaths = 6, honor = 900 },
        history = makeHistory(),
        historyLimit = 200,
        characters = { ["Oldchar-TestRealm"] = true },
        settings = {
            frameVisible = true,
            viewMode = "character",
            visibleCards = { AV = true, AB = true, WSG = true, EotS = true, World = true },
        },
    },
    char = {
        battlegrounds = {
            AV = bg(10, 6, 4, 9000, 4100, 30),
            AB = bg(20, 12, 8, 16000, 7000, 50),
            WSG = bg(30, 15, 15, 18000, 8800, 40),
            EotS = bg(8, 5, 3, 7000, 2500, 20),
        },
        worldPvP = { kills = 14, deaths = 6, honor = 900 },
        history = makeHistory(),
        historyLimit = 200,
        goals = { items = {}, completed = {}, settings = { autoRemoveCompleted = false, showInLDB = true, celebrateCompletion = true } },
        session = {
            AV = { played = 0, wins = 0, losses = 0, honor = 0, marks = 0 },
            AB = { played = 1, wins = 1, losses = 0, honor = 400, marks = 3 },
            WSG = { played = 0, wins = 0, losses = 0, honor = 0, marks = 0 },
            EotS = { played = 1, wins = 1, losses = 0, honor = 300, marks = 3 },
            worldPvP = { kills = 2, deaths = 1, honor = 60 },
        },
        sessionDate = tonumber(os.date("%Y%m%d")),
        lastGameTime = 0,
        bgState = { currentBG = "EotS", bgStartTime = 123, bgStartHonor = 4000, bgHonorAccumulated = 150, isInBG = true },
    },
}
