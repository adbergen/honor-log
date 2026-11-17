-- HonorLog Vendor Scanner
-- Reads the costs a PvP vendor really charges and keeps them in HonorLogDB.scannedGear, where
-- they override the generated gear database (HonorLog:GetGearItem). Costs are hotfixed from time
-- to time; a scan is how the addon learns of it and of items the generated data calls retired.
-- Usage: /honorlog scan          - scan the open vendor
--        /honorlog scan export   - print what differs from the generated data
--        /honorlog scan clear    - forget scanned data
--        /honorlog scan status   - what has been scanned

local ADDON_NAME, HonorLog = ...

local HONOR_CURRENCY = 1792

local SCANNER_DEBUG = false

local function say(text) print("|cff40d860HonorLog|r " .. text) end

function HonorLog:InitScanner()
    if type(HonorLogDB) ~= "table" then return end
    HonorLogDB.scannedGear = HonorLogDB.scannedGear or {}
    HonorLogDB.scannedVendors = HonorLogDB.scannedVendors or {}
end

function HonorLog:ToggleScannerDebug()
    SCANNER_DEBUG = not SCANNER_DEBUG
    say("Scanner debug mode: " .. (SCANNER_DEBUG and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end

local function IDFromLink(link, kind)
    if type(link) ~= "string" then return nil end
    local id = link:match(kind .. ":(%d+)")
    return id and tonumber(id) or nil
end

-- Battleground key for a mark item id (HonorLog.MARK_ITEMS maps the other way).
local function MarkType(itemID)
    for bgType, markID in pairs(HonorLog.MARK_ITEMS or {}) do
        if markID == itemID then return bgType end
    end
    return nil
end

-- What one merchant slot costs: honor (currency 1792 among the cost items), marks (the mark items)
-- and gold (the price, in copper). Returns itemID, cost or nil for a slot with no readable item.
function HonorLog:ReadMerchantCost(index)
    local link = GetMerchantItemLink and GetMerchantItemLink(index)
    local itemID = IDFromLink(link, "item")
    if not itemID then return nil end
    local name, _, price, _, _, _, _, hasExtendedCost = HonorLog.Compat.GetMerchantItemInfo(index)
    local cost = { honor = 0, marks = {}, gold = tonumber(price) or 0, name = name, extended = hasExtendedCost and true or false }

    local numCosts = GetMerchantItemCostInfo and GetMerchantItemCostInfo(index) or 0
    for c = 1, numCosts do
        local texture, count, costLink, costName = GetMerchantItemCostItem(index, c)
        count = tonumber(count) or 0
        if SCANNER_DEBUG then
            say(string.format("[debug] %s cost %d: texture=%s count=%s link=%s name=%s", tostring(name), c,
                tostring(texture), tostring(count), tostring(costLink), tostring(costName)))
        end
        local currencyID = IDFromLink(costLink, "currency")
        local costItemID = IDFromLink(costLink, "item")
        local markType = costItemID and MarkType(costItemID)
        if markType then
            cost.marks[markType] = (cost.marks[markType] or 0) + count
        elseif currencyID == HONOR_CURRENCY or (not currencyID and not costItemID and type(costName) == "string" and costName:lower():find("honor", 1, true)) then
            cost.honor = cost.honor + count
        elseif SCANNER_DEBUG then
            say("[debug] unrecognised cost: " .. tostring(costLink or costName))
        end
    end
    return itemID, cost
end

function HonorLog:ScanCurrentVendor()
    if not (MerchantFrame and MerchantFrame:IsShown()) then
        say("|cffff6666Error:|r No vendor window open. Talk to a PvP vendor first.")
        return 0
    end
    if not (GetMerchantNumItems and GetMerchantItemLink) then
        say("|cffff6666Error:|r this client has no merchant cost functions.")
        return 0
    end
    self:InitScanner()

    local vendor = UnitName("npc") or "Unknown Vendor"
    local numItems = GetMerchantNumItems()
    local kept = 0
    for i = 1, numItems do
        local itemID, cost = self:ReadMerchantCost(i)
        -- Keep what the database knows and anything bought with honor or marks (new PvP items).
        local known = self.GearDB and self.GearDB[itemID]
        if itemID and (known or cost.honor > 0 or next(cost.marks)) then
            HonorLogDB.scannedGear[itemID] = {
                honor = cost.honor, marks = cost.marks, gold = cost.gold,
                seen = time(), npc = UnitName("npc"),
            }
            kept = kept + 1
        end
    end
    HonorLogDB.scannedVendors[vendor] = { timestamp = time(), itemCount = kept }

    say(string.format("Scanned |cffffffff%s|r: %d PvP items of %d.", vendor, kept, numItems))
    if self.OnDataUpdated then self:OnDataUpdated() end
    return kept
end

local function MarksText(marks)
    local parts = {}
    for _, bgType in ipairs(HonorLog.BG_ORDER or {}) do
        if marks and marks[bgType] then parts[#parts + 1] = bgType .. " " .. marks[bgType] end
    end
    return #parts > 0 and table.concat(parts, ", ") or "none"
end

local function SameMarks(a, b)
    a, b = a or {}, b or {}
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

-- The differences between what vendors charge and what the generated data says: the input for
-- fixing tools/gear_rules.py. Returns the number of differing items.
function HonorLog:ExportScannedData()
    self:InitScanner()
    local data = HonorLogDB and HonorLogDB.scannedGear
    if not data or not next(data) then
        say("|cffff6666No scanned data to export.|r Scan a vendor first with /honorlog scan")
        return 0
    end
    local ids = {}
    for itemID in pairs(data) do ids[#ids + 1] = itemID end
    table.sort(ids)

    say("------ BEGIN EXPORT (scan vs generated data) ------")
    local differing = 0
    for _, itemID in ipairs(ids) do
        local scan, base = data[itemID], self.GearDB and self.GearDB[itemID]
        local label = (base and base.name) or ("item " .. itemID)
        if not base then
            differing = differing + 1
            print(string.format("[%d] NEW %s: honor %d, marks %s, gold %d", itemID, label, scan.honor or 0, MarksText(scan.marks), scan.gold or 0))
        else
            local diffs = {}
            if (scan.honor or 0) ~= (base.honor or 0) then diffs[#diffs + 1] = string.format("honor %d -> %d", base.honor or 0, scan.honor or 0) end
            if not SameMarks(scan.marks, base.marks) then diffs[#diffs + 1] = string.format("marks %s -> %s", MarksText(base.marks), MarksText(scan.marks)) end
            if (scan.gold or 0) ~= (base.gold or 0) then diffs[#diffs + 1] = string.format("gold %d -> %d", base.gold or 0, scan.gold or 0) end
            if base.legacy then diffs[#diffs + 1] = "stocked (generated data says legacy)" end
            if #diffs > 0 then
                differing = differing + 1
                print(string.format("[%d] %s: %s", itemID, label, table.concat(diffs, "; ")))
            end
        end
    end
    print(string.format("------ END EXPORT: %d of %d scanned items differ ------", differing, #ids))
    return differing
end

function HonorLog:ClearScannedData()
    self:InitScanner()
    HonorLogDB.scannedGear = {}
    HonorLogDB.scannedVendors = {}
    say("Scanned data cleared.")
    if self.OnDataUpdated then self:OnDataUpdated() end
end

function HonorLog:ShowScanStatus()
    self:InitScanner()
    local itemCount, vendorCount = 0, 0
    for _ in pairs(HonorLogDB.scannedGear or {}) do itemCount = itemCount + 1 end
    for _ in pairs(HonorLogDB.scannedVendors or {}) do vendorCount = vendorCount + 1 end

    say("Scanner Status:")
    print("  Items scanned: |cffffffff" .. itemCount .. "|r")
    print("  Vendors visited: |cffffffff" .. vendorCount .. "|r")
    for name, info in pairs(HonorLogDB.scannedVendors or {}) do
        print("    - " .. name .. " (" .. info.itemCount .. " items)")
    end
    say("Commands:")
    print("  |cffffffff/honorlog scan|r - Scan current vendor")
    print("  |cffffffff/honorlog scan export|r - Print differences from the generated data")
    print("  |cffffffff/honorlog scan clear|r - Clear scanned data")
end
