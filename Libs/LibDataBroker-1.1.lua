-- LibDataBroker-1.1 - A simple data broker library
-- https://github.com/tekkub/libdatabroker-1-1

local MAJOR, MINOR = "LibDataBroker-1.1", 4
local LibDataBroker, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not LibDataBroker then return end

LibDataBroker.callbacks = LibDataBroker.callbacks or {}
LibDataBroker.attributestorage = LibDataBroker.attributestorage or {}
LibDataBroker.namestorage = LibDataBroker.namestorage or {}
LibDataBroker.proxystorage = LibDataBroker.proxystorage or {}

local attributestorage = LibDataBroker.attributestorage
local namestorage = LibDataBroker.namestorage
local proxystorage = LibDataBroker.proxystorage
local callbacks = LibDataBroker.callbacks

local domt = {
    __metatable = "access denied",
    __index = function(self, key) return attributestorage[self] and attributestorage[self][key] end,
}

function domt:__newindex(key, value)
    if not attributestorage[self] then attributestorage[self] = {} end
    if attributestorage[self][key] == value then return end
    attributestorage[self][key] = value
    local name = namestorage[self]
    if not name then return end
    for callback in pairs(callbacks) do
        local ok, err = pcall(callback, name, key, value, self)
        if not ok then geterrorhandler()(err) end
    end
end

function LibDataBroker:NewDataObject(name, dataobj)
    if proxystorage[name] then return end

    if dataobj then
        assert(type(dataobj) == "table", "Invalid dataobj provided to NewDataObject, must be a table or nil")
    end

    local proxy = {}
    proxystorage[name] = proxy
    namestorage[proxy] = name
    attributestorage[proxy] = dataobj or {}
    setmetatable(proxy, domt)
    return proxy
end

function LibDataBroker:GetDataObjectByName(name)
    return proxystorage[name]
end

function LibDataBroker:GetNameByDataObject(dataobj)
    return namestorage[dataobj]
end

function LibDataBroker:DataObjectIterator()
    return pairs(proxystorage)
end

function LibDataBroker:RegisterCallback(func)
    callbacks[func] = true
end

function LibDataBroker:UnregisterCallback(func)
    callbacks[func] = nil
end

function LibDataBroker:UnregisterAllCallbacks()
    wipe(callbacks)
end
