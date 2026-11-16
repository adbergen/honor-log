-- HonorLog Rank
-- Plans the climb through Forever's 14-rank PvP system.
--
-- Rank is renown on major faction 2800 ("PvP Rank Points"). The client says
-- where the player stands, what this week's cap is and when the season ends;
-- this module adds what the client does not: how many games a target rank
-- takes at the player's measured pace and the earliest date the weekly cap
-- allows it. Maths follow Blizzard's own rank window (Camelot/PVPRankFrame.lua):
--   * my total = total points for the current rank + points earned in it;
--   * this week's cap total = total points for currentWeekProgressiveMaxLevel;
--   * the next reward is the first rank above the current one with rewards.
-- Every client call runs under pcall and every number is checked for secrecy
-- first (see Modules/Probe.lua); rank data is not secret, the habit is kept.

local ADDON_NAME, HonorLog = ...

local Rank = {}
HonorLog.Rank = Rank

local RANK_FACTION = 2800
local RANK_POINTS_CURRENCY = 3468
local MAX_RANK = 14
local DAY = 86400

-- Points to finish each rank (curve 103650); the fallback when the client
-- cannot give cumulative totals.
local CURVE = { 750, 900, 1050, 1200, 1350, 1500, 1650, 1800, 1950, 2100, 2350, 2500, 2650, 3000 }
-- Highest rank each week of the season allows (curve 102601).
local CAP_BY_WEEK = { 3, 5, 6, 7, 8, 9, 11, 12, 13, 14 }

-- Pace
local DEFAULT_WIN, DEFAULT_LOSS = 100, 25
local MIN_MEASURED = 5       -- below this the pace is an estimate
local POINTS_SAMPLE = 30     -- games averaged for points per win / loss
local RATE_SAMPLE = 50       -- decided games used for the win rate
local PACE_DAYS = 7
local WEEKS_KEPT = 20
local PLAN_WEEK_LIMIT = 60

--------------------------------------------------------------------------------
-- Safe readers
--------------------------------------------------------------------------------
local function isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function num(v)
    if isSecret(v) or type(v) ~= "number" then return nil end
    return v
end

local function str(v)
    if isSecret(v) or type(v) ~= "string" then return nil end
    return v
end

local function call(fn, ...)
    if type(fn) ~= "function" then return end
    local res = { pcall(fn, ...) }
    if not res[1] then return end
    return unpack(res, 2)
end

--------------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------------
function Rank.FormatNumber(n)
    n = math.floor((tonumber(n) or 0) + 0.5)
    local s, k = tostring(n), 0
    repeat
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return s
end
local commas = Rank.FormatNumber

-- "3d 4h", "5h 12m", "9m".
function Rank.FormatSpan(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local d = math.floor(seconds / DAY)
    local h = math.floor((seconds % DAY) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

function Rank.FormatDate(ts)
    if not ts then return "-" end
    return date("%b %d", ts)
end

--------------------------------------------------------------------------------
-- Client reads
--------------------------------------------------------------------------------
local function db()
    return HonorLog.db
end

-- Title for a rank, for the player's faction and sex, as Blizzard builds it.
function Rank:TitleForRank(n)
    n = num(n)
    if not n or n <= 0 then
        return str(PVP_RANK_0_NAME) or "Unranked"
    end
    local first = (Enum and Enum.PvPRanks and num(Enum.PvPRanks.Rank_1)) or 5
    local faction01 = (call(UnitFactionGroup, "player") == "Alliance") and 1 or 0
    local key = "PVP_RANK_" .. tostring(first + n - 1) .. "_" .. tostring(faction01)
    local gender = UnitSex and call(UnitSex, "player") or nil
    if gender and isSecret(gender) then gender = nil end
    local text = GetText and str(call(GetText, key, gender)) or nil
    if text and text ~= "" and text ~= key then return text end
    return "Rank " .. n
end

-- Cumulative points needed to reach rank n (rank 0 is unranked, so rank n costs the
-- first n curve entries). The client knows; the curve is the fallback.
function Rank:TotalForRank(n)
    n = num(n)
    if not n or n <= 0 then return 0 end
    local api = C_MajorFactions
    if api and api.GetTotalReputationForRenownLevel then
        local total = num(call(api.GetTotalReputationForRenownLevel, RANK_FACTION, n))
        if total then return total end
    end
    local sum = 0
    for level = 1, math.min(n, #CURVE) do sum = sum + CURVE[level] end
    return sum
end

local function readSeason()
    local season = GetCurrentArenaSeason and num(call(GetCurrentArenaSeason))
    if not season and C_SeasonInfo and C_SeasonInfo.GetCurrentDisplaySeasonID then
        season = num(call(C_SeasonInfo.GetCurrentDisplaySeasonID))
    end
    return season or 0
end

-- nil when the client has no rank data (a low-level character, data not loaded).
function Rank:GetInfo()
    local api = C_MajorFactions
    if not (api and api.GetMajorFactionProgressionInfo) then return nil end
    local p = call(api.GetMajorFactionProgressionInfo, RANK_FACTION)
    if type(p) ~= "table" then return nil end
    local rank, earned = num(p.renownLevel), num(p.renownReputationEarned)
    if not rank or not earned then return nil end

    local threshold = num(p.renownLevelThreshold) or 0
    local seasonMax = num(p.maxLevel)
    if not seasonMax or seasonMax <= 0 then seasonMax = MAX_RANK end
    local capRank = num(p.currentWeekProgressiveMaxLevel) or 0
    local week = num(p.weekNumber)
    if not week or week < 1 then week = 1 end

    local total = self:TotalForRank(rank) + earned
    local capTotal = capRank > 0 and self:TotalForRank(capRank) or 0
    local seasonSeconds = C_SeasonInfo and num(call(C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd)) or 0
    local resetSeconds = C_DateAndTime and num(call(C_DateAndTime.GetSecondsUntilWeeklyReset)) or 0

    return {
        rank = rank,
        title = self:TitleForRank(rank),
        points = earned,
        threshold = threshold,
        percent = threshold > 0 and math.min(100, earned / threshold * 100) or 100,
        totalPoints = total,
        weekCapRank = capRank,
        weekCapTotal = capTotal,
        prevWeekCapRank = num(p.previousWeekProgressiveMaxLevel) or 0,
        seasonMaxRank = seasonMax,
        weekNumber = week,
        season = readSeason(),
        secondsToSeasonEnd = seasonSeconds,
        secondsToWeeklyReset = resetSeconds,
        capped = capTotal > 0 and total >= capTotal,
        pointsLeftThisWeek = capTotal > 0 and math.max(0, capTotal - total) or nil,
    }
end

--------------------------------------------------------------------------------
-- The weekly cap
--------------------------------------------------------------------------------

-- Highest rank week w allows. The current week is the client's own number; later
-- weeks follow the season curve, shifted so the current week agrees with it.
function Rank:CapRankForWeek(w, info)
    info = info or self:GetInfo()
    if not info then return 0 end
    w = math.floor(tonumber(w) or info.weekNumber)
    local seasonMax = info.seasonMaxRank
    local clientCap = info.weekCapRank
    if clientCap <= 0 then return seasonMax end -- the client names no cap
    if w <= info.weekNumber then
        if w == info.weekNumber then return math.min(clientCap, seasonMax) end
        return math.min(info.prevWeekCapRank > 0 and info.prevWeekCapRank or clientCap, seasonMax)
    end
    local offset = 0
    for k, cap in ipairs(CAP_BY_WEEK) do
        if cap == clientCap then offset = k - info.weekNumber break end
    end
    local idx = math.max(1, math.min(#CAP_BY_WEEK, w + offset))
    return math.min(math.max(CAP_BY_WEEK[idx], clientCap), seasonMax)
end

--------------------------------------------------------------------------------
-- Pace, measured from the games HonorLog recorded
--------------------------------------------------------------------------------
function Rank:GetPace()
    local char = db() and db().char
    local history = char and char.history or {}
    local now = time()

    -- history[1] is the newest game.
    local winSum, winN, lossSum, lossN, measured = 0, 0, 0, 0, 0
    for _, g in ipairs(history) do
        if type(g.rankPoints) == "number" then
            measured = measured + 1
            if g.result == "win" then winSum, winN = winSum + g.rankPoints, winN + 1
            elseif g.result == "loss" then lossSum, lossN = lossSum + g.rankPoints, lossN + 1 end
            if measured >= POINTS_SAMPLE then break end
        end
    end

    local wins, losses, decided = 0, 0, 0
    for _, g in ipairs(history) do
        if g.result == "win" then wins, decided = wins + 1, decided + 1
        elseif g.result == "loss" then losses, decided = losses + 1, decided + 1 end
        if decided >= RATE_SAMPLE then break end
    end

    local cutoff = now - PACE_DAYS * DAY
    local recent, oldest = 0, now
    for _, g in ipairs(history) do
        local ts = type(g.timestamp) == "number" and g.timestamp or nil
        if ts then
            if ts >= cutoff then recent = recent + 1 end
            if ts < oldest then oldest = ts end
        end
    end
    local days = PACE_DAYS
    if oldest > cutoff then days = math.max(1, (now - oldest) / DAY) end

    local estimated = measured < MIN_MEASURED
    local perWin = (not estimated and winN > 0) and winSum / winN or DEFAULT_WIN
    local perLoss = (not estimated and lossN > 0) and lossSum / lossN or DEFAULT_LOSS
    local rate = decided > 0 and wins / decided or 0.5

    return {
        pointsPerWin = perWin,
        pointsPerLoss = perLoss,
        winRate = rate,
        gamesPerDay = recent / days,
        measuredGames = measured,
        estimated = estimated,
        pointsPerGame = rate * perWin + (1 - rate) * perLoss,
    }
end

--------------------------------------------------------------------------------
-- Plans
--------------------------------------------------------------------------------

-- What reaching rank n takes. info and pace may be passed in to avoid re-reading
-- them for every row of a table.
function Rank:PlanToRank(n, info, pace)
    info = info or self:GetInfo()
    if not info then return nil end
    pace = pace or self:GetPace()
    n = math.floor(tonumber(n) or 0)
    if n < 1 then n = 1 end
    local now = time()

    local plan = { target = n, reached = info.rank >= n, pointsNeeded = 0, gamesNeeded = 0 }
    if plan.reached then
        plan.limitedBy = "reached"
        return plan
    end
    plan.pointsNeeded = math.max(0, self:TotalForRank(n) - info.totalPoints)
    plan.gamesNeeded = pace.pointsPerGame > 0 and math.ceil(plan.pointsNeeded / pace.pointsPerGame) or 0

    if n > info.seasonMaxRank then
        plan.limitedBy = "season"
        return plan
    end

    local week
    for w = info.weekNumber, info.weekNumber + PLAN_WEEK_LIMIT do
        if self:CapRankForWeek(w, info) >= n then week = w break end
    end
    plan.earliestWeekByCap = week
    if week then
        if week == info.weekNumber then
            plan.earliestDateByCap = now
        else
            plan.earliestDateByCap = now + info.secondsToWeeklyReset + (week - info.weekNumber - 1) * 7 * DAY
        end
    end
    if pace.gamesPerDay > 0 then
        plan.projectedDateAtPace = now + math.floor(plan.gamesNeeded / pace.gamesPerDay * DAY)
    end

    local capDate, paceDate = plan.earliestDateByCap, plan.projectedDateAtPace
    if not capDate then
        plan.limitedBy = "season"
        return plan
    end
    plan.date = math.max(capDate, paceDate or capDate)
    if info.secondsToSeasonEnd > 0 and plan.date > now + info.secondsToSeasonEnd then
        plan.limitedBy = "season"
    elseif capDate > now and capDate >= (paceDate or 0) then
        plan.limitedBy = "cap"
    else
        plan.limitedBy = "pace"
    end
    return plan
end

--------------------------------------------------------------------------------
-- Rewards
--------------------------------------------------------------------------------
function Rank:GetRewards(n)
    local api = C_MajorFactions
    if not (api and api.GetRenownRewardsForLevel) then return {} end
    local raw = call(api.GetRenownRewardsForLevel, RANK_FACTION, n)
    local out = {}
    if type(raw) ~= "table" then return out end
    for _, r in ipairs(raw) do
        if type(r) == "table" then
            out[#out + 1] = {
                icon = r.icon, itemID = num(r.itemID),
                name = str(r.name), description = str(r.description) or str(r.name),
            }
        end
    end
    return out
end

-- The first rank above the current one that has rewards: rank, rewards.
function Rank:NextReward(info)
    info = info or self:GetInfo()
    if not info then return nil end
    for n = info.rank + 1, info.seasonMaxRank do
        local rewards = self:GetRewards(n)
        if #rewards > 0 then return n, rewards end
    end
    return nil
end

local function vendorHint()
    local key = (call(UnitFactionGroup, "player") == "Horde") and "PVP_RANK_REWARDS_VENDOR_HORDE"
        or "PVP_RANK_REWARDS_VENDOR_ALLIANCE"
    return str(_G[key])
end

--------------------------------------------------------------------------------
-- Alerts
--------------------------------------------------------------------------------

-- Sound, centre-screen notice, error-frame line and chat: the same four steps
-- the goal and honor-cap alerts use.
function Rank:Announce(text, r, g, b)
    PlaySound(878)
    if RaidNotice_AddMessage and RaidBossEmoteFrame then
        RaidNotice_AddMessage(RaidBossEmoteFrame, "|cffffd700" .. text .. "|r", ChatTypeInfo["RAID_WARNING"])
    end
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage("|cffffd700[HonorLog]|r " .. text, r or 1, g or 0.82, b or 0, 1, 3)
    end
    print("|cffffd700[HonorLog]|r " .. text)
end

-- MAJOR_FACTION_RENOWN_LEVEL_CHANGED: one celebration per rank gained.
function Rank:OnRenownChanged(factionID, newLevel, oldLevel)
    if num(factionID) ~= RANK_FACTION then return end
    newLevel, oldLevel = num(newLevel), num(oldLevel)
    local char = db() and db().char
    if newLevel and char and (not oldLevel or newLevel > oldLevel) and char.rankCelebrated ~= newLevel then
        char.rankCelebrated = newLevel
        self:Announce(string.format("Rank %d \226\128\148 %s", newLevel, self:TitleForRank(newLevel)))
        local info = self:GetInfo()
        local nextRank, rewards = self:NextReward(info or { rank = newLevel, seasonMaxRank = MAX_RANK })
        if nextRank then
            local names = {}
            for _, r in ipairs(rewards) do names[#names + 1] = r.description or r.name or "reward" end
            print(string.format("|cffffd700[HonorLog]|r Next reward at Rank %d: %s", nextRank, table.concat(names, ", ")))
        end
        local hint = vendorHint()
        if hint then print("|cffffd700[HonorLog]|r " .. hint) end
    end
    self:Refresh()
end

-- Once per week, the first time the cap is reached.
function Rank:CheckCapAlert(info)
    local d = db()
    if not (d and info and info.capped) then return end
    if d.settings.rankCapAlert == false then return end
    if d.char.rankCapAlertWeek == info.weekNumber then return end
    d.char.rankCapAlertWeek = info.weekNumber
    local text = string.format("Weekly rank cap reached (Rank %d).", info.weekCapRank)
    if info.weekCapRank < info.seasonMaxRank then
        text = string.format("Weekly rank cap reached (Rank %d). Rank %d opens in %s",
            info.weekCapRank, info.weekCapRank + 1, Rank.FormatSpan(info.secondsToWeeklyReset))
    end
    self:Announce(text)
end

--------------------------------------------------------------------------------
-- Weekly log: char.rankWeeks[week] = { startTotal, endTotal, games, capRank }
--------------------------------------------------------------------------------
function Rank:UpdateWeekLog(info)
    local char = db() and db().char
    if not (char and info) then return end
    char.rankWeeks = char.rankWeeks or {}
    local weeks = char.rankWeeks
    local entry = weeks[info.weekNumber]
    if not entry then
        -- A week starts where the last known one ended.
        local prevEnd, prevWeek
        for w, e in pairs(weeks) do
            if w < info.weekNumber and (not prevWeek or w > prevWeek) then prevWeek, prevEnd = w, e.endTotal end
        end
        entry = { startTotal = prevEnd or info.totalPoints, endTotal = info.totalPoints, games = 0, capRank = info.weekCapRank }
        weeks[info.weekNumber] = entry
    end
    entry.endTotal = info.totalPoints
    entry.capRank = info.weekCapRank

    local weekStart = time() + info.secondsToWeeklyReset - 7 * DAY
    local games = 0
    for _, g in ipairs(char.history or {}) do
        if type(g.timestamp) == "number" and g.timestamp >= weekStart then games = games + 1 end
    end
    entry.games = games

    local keys = {}
    for w in pairs(weeks) do keys[#keys + 1] = w end
    if #keys > WEEKS_KEPT then
        table.sort(keys)
        for i = 1, #keys - WEEKS_KEPT do weeks[keys[i]] = nil end
    end
end

-- Re-read everything: the week log, the cap alert, the UI and the broker text.
function Rank:Refresh()
    local info = self:GetInfo()
    if info and db() then
        self:UpdateWeekLog(info)
        self:CheckCapAlert(info)
    end
    if HonorLog.UpdateRankUI then HonorLog:UpdateRankUI(info) end
    if HonorLog.UpdateLDB then HonorLog:UpdateLDB() end
    return info
end

--------------------------------------------------------------------------------
-- Text for the broker, the tooltips and /honorlog rank
--------------------------------------------------------------------------------

-- "R7 Knight-Captain · 62%" when the player chose the rank format, else nil.
function Rank:BrokerText()
    local settings = db() and db().settings
    if not settings or settings.ldbFormat ~= "rank" then return nil end
    local info = self:GetInfo()
    if not info then return nil end
    local head = info.rank > 0 and string.format("R%d %s", info.rank, info.title) or info.title
    return string.format("%s \194\183 %d%%", head, math.floor(info.percent))
end

local TAG_TEXT = { cap = "cap", pace = "pace", season = "season", reached = "reached" }
Rank.TAG_TEXT = TAG_TEXT

local function planLine(self, plan)
    if plan.reached then return "reached" end
    local parts = { commas(plan.pointsNeeded) .. " pts", "~" .. commas(plan.gamesNeeded) .. " games" }
    if plan.date then parts[#parts + 1] = Rank.FormatDate(plan.date) end
    parts[#parts + 1] = "(" .. (TAG_TEXT[plan.limitedBy] or "?") .. ")"
    return table.concat(parts, " \194\183 ")
end

-- Fill a tooltip (the rank bar's and the broker's share this).
function Rank:AddTooltipLines(tooltip)
    local info = self:GetInfo()
    if not info then return false end
    local pace = self:GetPace()
    local head = info.rank > 0 and string.format("Rank %d \226\128\148 %s", info.rank, info.title) or info.title
    tooltip:AddLine(head, 1, 0.82, 0)
    if info.threshold > 0 then
        tooltip:AddDoubleLine("Progress", string.format("%s / %s (%d%%)", commas(info.points),
            commas(info.threshold), math.floor(info.percent)), 1, 1, 1, 1, 1, 1)
    end
    if info.weekCapRank > 0 then
        local capText = "Rank " .. info.weekCapRank
        if info.capped then capText = capText .. " (reached)"
        elseif info.pointsLeftThisWeek then capText = capText .. " (" .. commas(info.pointsLeftThisWeek) .. " pts left)" end
        tooltip:AddDoubleLine("This week's cap", capText, 1, 1, 1, 1, 0.82, 0)
    end

    local shown = 0
    for n = info.rank + 1, info.seasonMaxRank do
        if shown == 0 then tooltip:AddLine(" ") tooltip:AddLine("Next ranks" .. (pace.estimated and " (estimate)" or ""), 0.7, 0.7, 0.8) end
        local plan = self:PlanToRank(n, info, pace)
        tooltip:AddDoubleLine(string.format("R%d %s", n, self:TitleForRank(n)), planLine(self, plan), 1, 1, 1, 0.8, 0.8, 0.85)
        shown = shown + 1
        if shown >= 3 then break end
    end

    local nextRank, rewards = self:NextReward(info)
    if nextRank then
        tooltip:AddLine(" ")
        tooltip:AddLine("Next reward: Rank " .. nextRank, 0.7, 0.7, 0.8)
        for _, r in ipairs(rewards) do
            local icon = r.icon and ("|T" .. tostring(r.icon) .. ":14:14:0:0|t ") or ""
            tooltip:AddLine(icon .. (r.description or r.name or "Reward"), 1, 1, 1)
        end
    end

    tooltip:AddLine(" ")
    if info.secondsToSeasonEnd > 0 then
        tooltip:AddDoubleLine("Season ends in", Rank.FormatSpan(info.secondsToSeasonEnd), 1, 1, 1, 0.8, 0.8, 0.85)
    end
    if info.secondsToWeeklyReset > 0 then
        tooltip:AddDoubleLine("Weekly reset in", Rank.FormatSpan(info.secondsToWeeklyReset), 1, 1, 1, 0.8, 0.8, 0.85)
    end
    return true
end

local function say(text) print("|cff00ff00[HonorLog]|r " .. text) end

-- /honorlog rank [n]
function Rank:PrintSlash(arg)
    local info = self:GetInfo()
    if not info then
        say("No PvP rank data from the client yet.")
        return
    end
    local pace = self:GetPace()
    local target = tonumber(arg and arg:match("%d+"))
    if target then
        local plan = self:PlanToRank(target, info, pace)
        local title = string.format("Rank %d %s", plan.target, self:TitleForRank(plan.target))
        if plan.reached then
            say(title .. ": already reached.")
        elseif plan.limitedBy == "season" and not plan.date then
            say(string.format("%s: %s points to go, but this season tops out at Rank %d.",
                title, commas(plan.pointsNeeded), info.seasonMaxRank))
        else
            say(string.format("%s: %s points, about %s games%s. Earliest by cap: %s. At your pace: %s. Limited by %s.",
                title, commas(plan.pointsNeeded), commas(plan.gamesNeeded), pace.estimated and " (estimate)" or "",
                plan.earliestDateByCap and (plan.earliestDateByCap <= time() and "now" or Rank.FormatDate(plan.earliestDateByCap)) or "never this season",
                plan.projectedDateAtPace and Rank.FormatDate(plan.projectedDateAtPace) or "no games lately",
                TAG_TEXT[plan.limitedBy] or "?"))
        end
        return
    end

    local head = info.rank > 0 and string.format("Rank %d %s", info.rank, info.title) or info.title
    if info.threshold > 0 then
        say(string.format("%s: %s / %s (%d%%), %s points in total.", head, commas(info.points),
            commas(info.threshold), math.floor(info.percent), commas(info.totalPoints)))
    else
        say(string.format("%s: %s points in total.", head, commas(info.totalPoints)))
    end
    if info.weekCapRank > 0 then
        if info.capped then
            say(string.format("Week %d cap: Rank %d reached. %s", info.weekNumber, info.weekCapRank,
                info.weekCapRank < info.seasonMaxRank and
                    string.format("Rank %d opens in %s.", info.weekCapRank + 1, Rank.FormatSpan(info.secondsToWeeklyReset)) or ""))
        else
            say(string.format("Week %d cap: Rank %d, %s points to go. Next cap in %s.", info.weekNumber,
                info.weekCapRank, commas(info.pointsLeftThisWeek or 0), Rank.FormatSpan(info.secondsToWeeklyReset)))
        end
    end
    if info.secondsToSeasonEnd > 0 then say("Season ends in " .. Rank.FormatSpan(info.secondsToSeasonEnd) .. ".") end
    local nextRank, rewards = self:NextReward(info)
    if nextRank then
        local names = {}
        for _, r in ipairs(rewards) do names[#names + 1] = r.description or r.name or "reward" end
        say(string.format("Next reward at Rank %d: %s", nextRank, table.concat(names, ", ")))
    end
    say(string.format("Pace: %d per win, %d per loss, %d%% wins, %.1f games a day%s.", math.floor(pace.pointsPerWin + 0.5),
        math.floor(pace.pointsPerLoss + 0.5), math.floor(pace.winRate * 100 + 0.5), pace.gamesPerDay,
        pace.estimated and " (estimate: fewer than " .. MIN_MEASURED .. " measured games)" or ""))
    if info.rank < info.seasonMaxRank then
        local plan = self:PlanToRank(info.rank + 1, info, pace)
        say(string.format("Rank %d: %s points, about %s games, %s (%s).", plan.target, commas(plan.pointsNeeded),
            commas(plan.gamesNeeded), plan.date and Rank.FormatDate(plan.date) or "no date",
            TAG_TEXT[plan.limitedBy] or "?"))
    end
end

Rank.RANK_FACTION = RANK_FACTION
Rank.RANK_POINTS_CURRENCY = RANK_POINTS_CURRENCY
Rank.MAX_RANK = MAX_RANK
