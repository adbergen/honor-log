-- HonorLog Util
-- Helpers every file shares: secret-safe readers, table copies, chat output and
-- the string table.
--
-- Loaded first (after the libraries). Rule for every value the client may hand
-- back as a secret: check it with isSecret() before comparing, adding,
-- concatenating, indexing or storing it (see Modules/Probe.lua).

local _, HonorLog = ...
HonorLog = HonorLog or {}

local Util = {}
HonorLog.Util = Util

local PREFIX = "|cff00ff00[HonorLog]|r "

function Util.isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end
local isSecret = Util.isSecret

-- The number, or nil when v is secret or not a number.
function Util.num(v)
    if isSecret(v) or type(v) ~= "number" then return nil end
    return v
end

-- The string, or nil when v is secret or not a string.
function Util.str(v)
    if isSecret(v) or type(v) ~= "string" then return nil end
    return v
end

-- pcall(fn, ...) returning the results, or nothing when the call errors.
function Util.call(fn, ...)
    if type(fn) ~= "function" then return end
    local res = { pcall(fn, ...) }
    if not res[1] then return end
    return unpack(res, 2)
end

-- Deep copy utility
function Util.DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = Util.DeepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

-- Deep merge (target inherits missing keys from source)
function Util.DeepMerge(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            Util.DeepMerge(target[k], v)
        elseif target[k] == nil then
            target[k] = Util.DeepCopy(v)
        end
    end
end

-- One chat line with the addon prefix.
function HonorLog:Say(text)
    print(PREFIX .. text)
end

-- Sound, centre-screen notice, error-frame line and chat: the same four steps
-- the goal, rank-cap and honor-cap alerts use.
function HonorLog:Announce(text, r, g, b)
    PlaySound(878)
    if RaidNotice_AddMessage and RaidBossEmoteFrame then
        RaidNotice_AddMessage(RaidBossEmoteFrame, "|cffffd700" .. text .. "|r", ChatTypeInfo["RAID_WARNING"])
    end
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage("|cffffd700[HonorLog]|r " .. text, r or 1, g or 0.82, b or 0, 1, 3)
    end
    print("|cffffd700[HonorLog]|r " .. text)
end

-- User-facing text. The key is the English sentence, with format placeholders;
-- a language that has no entry shows the key.
HonorLog.L = setmetatable({}, { __index = function(_, key) return key end })
