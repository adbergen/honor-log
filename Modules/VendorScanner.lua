-- HonorLog Vendor Scanner
-- Dev tool for scanning PvP vendors to build accurate gear database
-- Usage: /honorlog scan - Scans current vendor
--        /honorlog scan export - Exports scanned data as Lua table
--        /honorlog scan clear - Clears scanned data

local ADDON_NAME, HonorLog = ...

-- Mark item IDs for identifying mark costs
local MARK_IDS = {
    [20560] = "AV",   -- Alterac Valley Mark of Honor
    [20559] = "AB",   -- Arathi Basin Mark of Honor
    [20558] = "WSG",  -- Warsong Gulch Mark of Honor
    [29024] = "EotS", -- Eye of the Storm Mark of Honor
}

-- Honor texture patterns (TBC Classic uses textures to identify honor currency)
local HONOR_TEXTURES = {
    "PVPCurrency%-Honor",
    "PVP%-Currency%-Alliance",
    "PVP%-Currency%-Horde",
    "Spell_Holy_ChampionsBond",  -- Alternative honor icon
}

-- Arena points texture patterns
local ARENA_TEXTURES = {
    "PVPCurrency%-Conquest",
    "PVP%-ArenaPoints",
    "Ability_Warrior_RallyingCry",  -- Alternative arena icon
}

-- Slot mapping from inventory type
local INVTYPE_TO_SLOT = {
    INVTYPE_HEAD = "HEAD",
    INVTYPE_NECK = "NECK",
    INVTYPE_SHOULDER = "SHOULDER",
    INVTYPE_CLOAK = "BACK",
    INVTYPE_CHEST = "CHEST",
    INVTYPE_ROBE = "CHEST",
    INVTYPE_WRIST = "WRIST",
    INVTYPE_HAND = "HANDS",
    INVTYPE_WAIST = "WAIST",
    INVTYPE_LEGS = "LEGS",
    INVTYPE_FEET = "FEET",
    INVTYPE_FINGER = "FINGER",
    INVTYPE_TRINKET = "TRINKET",
    INVTYPE_WEAPON = "MAIN_HAND",
    INVTYPE_WEAPONMAINHAND = "MAIN_HAND",
    INVTYPE_WEAPONOFFHAND = "OFF_HAND",
    INVTYPE_HOLDABLE = "OFF_HAND",
    INVTYPE_SHIELD = "OFF_HAND",
    INVTYPE_2HWEAPON = "TWO_HAND",
    INVTYPE_RANGED = "RANGED",
    INVTYPE_RANGEDRIGHT = "RANGED",
    INVTYPE_THROWN = "RANGED",
    INVTYPE_RELIC = "RELIC",
}

-- Class restrictions from subclass
local CLASS_RESTRICTIONS = {
    ["Plate"] = { "WARRIOR", "PALADIN" },
    ["Mail"] = { "HUNTER", "SHAMAN" },
    ["Leather"] = { "ROGUE", "DRUID" },
    ["Cloth"] = { "PRIEST", "MAGE", "WARLOCK" },
}

--------------------------------------------------------------------------------
-- SCANNER FUNCTIONS
--------------------------------------------------------------------------------

-- Debug mode for troubleshooting
local SCANNER_DEBUG = false

-- Initialize scanner data storage
function HonorLog:InitScanner()
    if not HonorLogDB then HonorLogDB = {} end
    if not HonorLogDB.scannedGear then
        HonorLogDB.scannedGear = {}
    end
    if not HonorLogDB.scannedVendors then
        HonorLogDB.scannedVendors = {}
    end
end

-- Toggle debug mode
function HonorLog:ToggleScannerDebug()
    SCANNER_DEBUG = not SCANNER_DEBUG
    print("|cff40d860HonorLog|r Scanner debug mode: " .. (SCANNER_DEBUG and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end

-- Get item ID from item link
local function GetItemIDFromLink(link)
    if not link then return nil end
    local itemID = link:match("item:(%d+)")
    return itemID and tonumber(itemID) or nil
end

-- Get slot from item
local function GetItemSlot(itemID)
    local _, _, _, _, _, _, _, _, invType = GetItemInfo(itemID)
    return INVTYPE_TO_SLOT[invType] or nil
end

-- Detect class restriction from item (simplified - checks name patterns)
local function DetectClassRestriction(itemName, itemID)
    -- Check tooltip for class restriction
    local tooltip = CreateFrame("GameTooltip", "HonorLogScanTooltip", nil, "GameTooltipTemplate")
    tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tooltip:SetItemByID(itemID)

    for i = 1, tooltip:NumLines() do
        local line = _G["HonorLogScanTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text then
                -- Check for class restrictions
                if text:match("Classes: (.+)") then
                    local classes = text:match("Classes: (.+)")
                    -- Parse class list
                    if classes:match("Warrior") then return "WARRIOR" end
                    if classes:match("Paladin") then return "PALADIN" end
                    if classes:match("Hunter") then return "HUNTER" end
                    if classes:match("Rogue") then return "ROGUE" end
                    if classes:match("Priest") then return "PRIEST" end
                    if classes:match("Shaman") then return "SHAMAN" end
                    if classes:match("Mage") then return "MAGE" end
                    if classes:match("Warlock") then return "WARLOCK" end
                    if classes:match("Druid") then return "DRUID" end
                end
            end
        end
    end

    return nil -- Any class
end

-- Scan the current merchant
function HonorLog:ScanCurrentVendor()
    if not MerchantFrame or not MerchantFrame:IsShown() then
        print("|cff40d860HonorLog|r |cffff6666Error:|r No vendor window open. Talk to a PvP vendor first.")
        return
    end

    self:InitScanner()

    local vendorName = UnitName("npc") or "Unknown Vendor"
    local numItems = GetMerchantNumItems()
    local scannedCount = 0
    local pvpItemCount = 0

    print("|cff40d860HonorLog|r Scanning vendor: |cffffffff" .. vendorName .. "|r (" .. numItems .. " items)")

    for i = 1, numItems do
        local name, texture, price, quantity, numAvailable, isPurchasable, isUsable, extendedCost = GetMerchantItemInfo(i)
        local link = GetMerchantItemLink(i)
        local itemID = GetItemIDFromLink(link)

        if itemID and extendedCost then
            -- This item has extended cost (honor/marks/arena points)
            local itemData = {
                name = name,
                vendor = vendorName,
                slot = nil,
                class = nil,
                honor = 0,
                arena = 0,
                marks = {},
                gold = price or 0,
            }

            -- Get slot info
            itemData.slot = GetItemSlot(itemID)

            -- Get class restriction
            itemData.class = DetectClassRestriction(name, itemID)

            -- Get cost breakdown
            local numCosts = GetMerchantItemCostInfo(i)

            if SCANNER_DEBUG then
                print("|cff40d860[DEBUG]|r Item: " .. name .. " has " .. numCosts .. " cost types")
            end

            for c = 1, numCosts do
                local costTexture, costCount, costLink, costName = GetMerchantItemCostItem(i, c)
                local textureStr = costTexture and tostring(costTexture) or ""

                if SCANNER_DEBUG then
                    print(string.format("|cff40d860[DEBUG]|r   Cost %d: texture=%s, count=%s, link=%s, name=%s",
                        c,
                        tostring(costTexture),
                        tostring(costCount),
                        tostring(costLink),
                        tostring(costName)
                    ))
                end

                -- Check if costLink is a proper item link (contains "item:")
                local costItemID = GetItemIDFromLink(costLink)

                if costItemID and MARK_IDS[costItemID] then
                    -- It's an item (mark of honor)
                    itemData.marks[MARK_IDS[costItemID]] = costCount
                else
                    -- It's a currency - try name first, then texture
                    local identified = false

                    -- Try by name
                    if costName and costName ~= "" then
                        local lowerName = costName:lower()
                        if lowerName:match("honor") then
                            itemData.honor = costCount
                            identified = true
                        elseif lowerName:match("arena") then
                            itemData.arena = costCount
                            identified = true
                        end
                    end

                    -- Fallback: try by texture pattern
                    if not identified and textureStr ~= "" then
                        -- Check honor textures
                        for _, pattern in ipairs(HONOR_TEXTURES) do
                            if textureStr:match(pattern) then
                                itemData.honor = costCount
                                identified = true
                                break
                            end
                        end

                        -- Check arena textures
                        if not identified then
                            for _, pattern in ipairs(ARENA_TEXTURES) do
                                if textureStr:match(pattern) then
                                    itemData.arena = costCount
                                    identified = true
                                    break
                                end
                            end
                        end
                    end

                    -- Debug: if still not identified, log it
                    if not identified and costCount and costCount > 0 then
                        -- Unknown currency - might be honor/arena with different texture
                        -- Store as honor if count is large (>100), likely honor
                        if costCount >= 100 then
                            itemData.honor = costCount
                        end
                    end
                end
            end

            -- Store the item
            HonorLogDB.scannedGear[itemID] = itemData
            pvpItemCount = pvpItemCount + 1
        end

        scannedCount = scannedCount + 1
    end

    -- Record vendor as scanned
    HonorLogDB.scannedVendors[vendorName] = {
        timestamp = time(),
        itemCount = pvpItemCount,
    }

    print("|cff40d860HonorLog|r Scan complete: |cffffffff" .. pvpItemCount .. "|r PvP items found (with extended cost)")
    print("|cff40d860HonorLog|r Use |cffffffff/honorlog scan export|r to output the data")
end

-- Export scanned data as Lua table
function HonorLog:ExportScannedData()
    self:InitScanner()

    local data = HonorLogDB.scannedGear
    if not data or not next(data) then
        print("|cff40d860HonorLog|r |cffff6666No scanned data to export.|r Scan vendors first with /honorlog scan")
        return
    end

    -- Count items
    local count = 0
    for _ in pairs(data) do count = count + 1 end

    print("|cff40d860HonorLog|r Exporting |cffffffff" .. count .. "|r items...")
    print("|cff40d860HonorLog|r Copy the output from your chat frame or WoW\\Logs\\")
    print("------ BEGIN EXPORT ------")

    -- Sort by itemID for consistent output
    local sortedIDs = {}
    for itemID in pairs(data) do
        table.insert(sortedIDs, itemID)
    end
    table.sort(sortedIDs)

    -- Output as Lua table
    for _, itemID in ipairs(sortedIDs) do
        local item = data[itemID]
        local marksStr = "nil"

        if next(item.marks) then
            local markParts = {}
            for bg, count in pairs(item.marks) do
                table.insert(markParts, bg .. " = " .. count)
            end
            marksStr = "{ " .. table.concat(markParts, ", ") .. " }"
        end

        local classStr = item.class and ('"' .. item.class .. '"') or "nil"
        local slotStr = item.slot and ('"' .. item.slot .. '"') or '"UNKNOWN"'

        -- Format: [itemID] = { slot = "SLOT", class = "CLASS", honor = N, arena = N, marks = { BG = N }, season = nil, name = "Name" },
        local line = string.format(
            '[%d] = { slot = %s, class = %s, honor = %d, arena = %d, marks = %s, season = nil, name = "%s" },',
            itemID,
            slotStr,
            classStr,
            item.honor or 0,
            item.arena or 0,
            marksStr,
            item.name:gsub('"', '\\"')
        )
        print(line)
    end

    print("------ END EXPORT ------")
    print("|cff40d860HonorLog|r Export complete. Copy from chat or check WoW\\Logs\\")
end

-- Clear scanned data
function HonorLog:ClearScannedData()
    self:InitScanner()
    HonorLogDB.scannedGear = {}
    HonorLogDB.scannedVendors = {}
    print("|cff40d860HonorLog|r Scanned data cleared.")
end

-- Show scan status
function HonorLog:ShowScanStatus()
    self:InitScanner()

    local itemCount = 0
    for _ in pairs(HonorLogDB.scannedGear or {}) do
        itemCount = itemCount + 1
    end

    local vendorCount = 0
    for _ in pairs(HonorLogDB.scannedVendors or {}) do
        vendorCount = vendorCount + 1
    end

    print("|cff40d860HonorLog|r Scanner Status:")
    print("  Items scanned: |cffffffff" .. itemCount .. "|r")
    print("  Vendors visited: |cffffffff" .. vendorCount .. "|r")

    if vendorCount > 0 then
        print("  Vendors:")
        for name, info in pairs(HonorLogDB.scannedVendors) do
            print("    - " .. name .. " (" .. info.itemCount .. " items)")
        end
    end

    print("|cff40d860HonorLog|r Commands:")
    print("  |cffffffff/honorlog scan|r - Scan current vendor")
    print("  |cffffffff/honorlog scan export|r - Export as Lua table")
    print("  |cffffffff/honorlog scan clear|r - Clear scanned data")
end

--------------------------------------------------------------------------------
-- AUTO-SCAN ON VENDOR OPEN (optional, disabled by default)
--------------------------------------------------------------------------------

-- Create scanner event frame
local scannerFrame = CreateFrame("Frame")
scannerFrame:RegisterEvent("MERCHANT_SHOW")
scannerFrame:SetScript("OnEvent", function(self, event)
    -- Auto-scan is disabled by default
    -- Uncomment next line to enable auto-scanning PvP vendors
    -- HonorLog:ScanCurrentVendor()
end)
