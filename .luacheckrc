-- Luacheck configuration for HonorLog.
-- Lua 5.1 (the WoW runtime) plus the WoW Forever API surface the addon touches.

std = "lua51"
codes = true
max_line_length = false -- long chat strings and data rows are normal here

-- Embedded libraries and CI tool installs are not ours to lint.
exclude_files = { "Libs/", ".luarocks/", ".lua/", ".install/", ".claude/" }

ignore = {
    "212", -- unused argument (event handlers ignore args)
    "213", -- unused loop variable
    "431", -- shadowing an upvalue (common in nested UI closures)
    "432", -- shadowing an upvalue argument (self in nested script handlers)
    -- Style noise in code that Rounds 1-3 replace; targeted so real bugs still show.
    "211", -- unused local/function (unused ADDON_NAME, event-handler returns, dead helpers)
    "311", -- value assigned then overwritten (defensive initialisers)
    "421", "422", -- shadowing a local in a nested scope
    "542", -- empty if branch (placeholder branches in Modules/AB.lua and MainFrame.lua)
}

-- Globals the addon intentionally writes.
globals = {
    "HonorLogDB", "HonorLogCharDB",
    "SLASH_HONORLOG1", "SLASH_HONORLOG2", "SlashCmdList",
    "HonorLogWindow", "HonorLog_ToggleWindow", "HonorLog_OnAddonCompartmentClick",
    "BINDING_HEADER_HONORLOG", "BINDING_NAME_HONORLOG_TOGGLE",
}

-- WoW API the addon reads.
read_globals = {
    "CreateFrame", "UIParent", "GameTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "WorldFrame",
    "GameFontHighlightSmall", "UIErrorsFrame", "RaidBossEmoteFrame", "MerchantFrame", "DressUpFrame", "DEFAULT_CHAT_FRAME",
    "C_Timer", "C_AddOns", "C_Container", "C_CurrencyInfo", "C_Item", "C_PvP", "C_MajorFactions",
    "C_SeasonInfo", "C_RestrictedActions", "C_DeathRecap", "C_DateAndTime", "C_MerchantFrame", "C_Reputation", "Enum", "Settings",
    "C_Map", "WorldMapFrame", "ShowUIPanel", "InCombatLockdown", "IsInInstance", "UnitPosition", "GetPlayerFacing",
    "GetBindingKey", "CreateVector2D", "GetItemIcon", "GetSubZoneText", "IsAltKeyDown",
    "LibStub", "hooksecurefunc", "wipe", "unpack", "bit", "date", "time",
    "issecretvalue", "GetTime", "GetBuildInfo", "GetRealmName", "GetRealZoneText", "GetInstanceInfo",
    "UnitName", "UnitClass", "UnitRace", "UnitFactionGroup", "UnitLevel", "UnitGUID", "GetPlayerInfoByGUID",
    "UnitExists", "UnitIsPlayer", "UnitIsEnemy", "UnitIsDeadOrGhost", "UnitIsFeignDeath",
    "COMBATLOG_HONORGAIN", "COMBATLOG_HONORGAIN_NO_RANK", "COMBATLOG_HONORGAIN_EXHAUSTION1", "COMBATLOG_HONORAWARD",
    "GetInventoryItemID", "GetCursorPosition", "SetCursor", "ResetCursor",
    "IsShiftKeyDown", "IsControlKeyDown", "PlaySound", "SOUNDKIT", "ChatTypeInfo", "BreakUpLargeNumbers",
    "CreateColor", "GetMoney", "C_Texture", "GetText", "UnitSex", "GetCurrentArenaSeason",
    "PVP_RANK_0_NAME", "PVP_RANK_REWARDS_VENDOR_HORDE", "PVP_RANK_REWARDS_VENDOR_ALLIANCE",
    -- UIDropDownMenu (Blizzard_SharedXML)
    "UIDropDownMenu_AddButton", "UIDropDownMenu_CreateInfo", "UIDropDownMenu_Initialize",
    "UIDropDownMenu_SetSelectedValue", "UIDropDownMenu_SetText", "UIDropDownMenu_SetWidth",
    "ToggleDropDownMenu", "CloseDropDownMenus",
    -- PvP globals the Forever UI itself uses
    "GetNumBattlegroundTypes", "GetBattlefieldWinner", "GetNumBattlefieldScores", "GetBattlefieldStatus",
    "GetMaxBattlefieldID", "GetBattlefieldArenaFaction", "RequestBattlefieldScoreData",
    "GetPVPSessionStats", "GetPVPLifetimeStats", "GetPVPYesterdayStats",
    -- Absent on Forever, kept behind existence checks for older clients and optional fallbacks
    "GetAddOnMetadata", "GetItemInfo", "GetItemCount", "GetContainerNumSlots", "GetContainerItemID",
    "GetContainerItemInfo", "GetHonorCurrency", "GetPVPCurrency", "GetArenaCurrency", "GetBattlefieldScore",
    "UnitHonor", "HONOR_CURRENCY", "InterfaceOptions_AddCategory", "InterfaceOptionsFrame_OpenToCategory",
    "RaidNotice_AddMessage", "DressUpItemLink", "CombatLogGetCurrentEventInfo",
    "COMBATLOG_OBJECT_REACTION_HOSTILE",
    "GetMerchantNumItems", "GetMerchantItemInfo", "GetMerchantItemLink", "GetMerchantItemCostInfo",
    "GetMerchantItemCostItem", "GameTooltip_ShowCompareItem",
    -- the full window (UI/Kit.lua): every one is behind an existence check
    "UISpecialFrames", "ChatEdit_InsertLink", "ITEM_QUALITY_COLORS", "CooldownFrame_SetDisplayAsPercentage",
    "PanelTemplates_SelectTab", "PanelTemplates_DeselectTab", "PanelTemplates_TabResize", "geterrorhandler",
}

-- The headless test harness deliberately defines stand-ins for WoW globals.
files["Tests/"] = {
    globals = {
        "CreateFrame", "hooksecurefunc", "C_Timer", "C_AddOns", "C_PvP", "C_MajorFactions", "C_CurrencyInfo",
        "C_SeasonInfo", "C_Item", "C_Container", "C_MerchantFrame", "C_Reputation", "C_RestrictedActions", "Enum",
        "MerchantFrame", "GetMerchantNumItems", "GetMerchantItemLink", "GetMerchantItemCostInfo", "GetMerchantItemCostItem",
        "Settings", "SlashCmdList", "LibStub", "UIParent", "Minimap", "GameTooltip", "UIErrorsFrame",
        "DressUpFrame", "issecretvalue", "geterrorhandler", "unpack", "wipe", "bit", "date", "time",
        "GetNumBattlegroundTypes", "GetBattlefieldWinner", "GetNumBattlefieldScores", "GetBattlefieldStatus",
        "GetMaxBattlefieldID", "GetBattlefieldArenaFaction", "GetPVPSessionStats", "GetPVPLifetimeStats",
        "GetPVPYesterdayStats", "GetInventoryItemID", "UnitHonor", "UnitName", "UnitFactionGroup", "UnitLevel",
        "UnitClass", "UnitRace", "UnitGUID", "GetRealmName", "GetRealZoneText", "GetInstanceInfo", "GetBuildInfo",
        "GetMoney", "GetTime", "PlaySound", "SOUNDKIT", "IsShiftKeyDown", "IsControlKeyDown",
        "GetCursorPosition", "SetCursor", "ResetCursor", "BreakUpLargeNumbers", "CreateColor", "ChatTypeInfo",
        "C_Texture", "GetText", "UnitSex", "GetCurrentArenaSeason", "PVP_RANK_0_NAME",
        "PVP_RANK_REWARDS_VENDOR_HORDE", "PVP_RANK_REWARDS_VENDOR_ALLIANCE", "UISpecialFrames",
        "COMBATLOG_HONORGAIN", "COMBATLOG_HONORGAIN_NO_RANK", "COMBATLOG_HONORAWARD",
        "C_DateAndTime", "C_DeathRecap", "UnitExists", "UnitIsPlayer", "UnitIsEnemy", "UnitIsDeadOrGhost",
        "UnitIsFeignDeath", "GetPlayerInfoByGUID", "RequestBattlefieldScoreData",
        "UIDropDownMenu_CreateInfo", "UIDropDownMenu_AddButton", "UIDropDownMenu_Initialize",
        "UIDropDownMenu_SetSelectedValue", "UIDropDownMenu_SetText", "UIDropDownMenu_SetWidth",
        "ToggleDropDownMenu", "CloseDropDownMenus", "print", "securecallfunction",
        "strmatch", "strfind", "strsub", "strlen", "strlower", "strupper", "strrep", "strbyte", "strchar",
        "strtrim", "format", "gsub", "gmatch", "tinsert", "tremove", "sort", "floor", "ceil", "abs", "min", "max",
        "HonorLogDB", "HonorLogCharDB", "SLASH_HONORLOG1", "SLASH_HONORLOG2",
        "C_Map", "C_SuperTrack", "UiMapPoint", "GetSubZoneText", "IsAltKeyDown",
        "WorldMapFrame", "ShowUIPanel", "InCombatLockdown", "IsInInstance", "UnitPosition", "GetPlayerFacing",
        "GetBindingKey", "CreateVector2D",
        "GetQuestID", "GetTitleText", "GetRewardMoney", "GetRewardXP", "GetRewardHonor", "GetNumQuestRewards",
        "GetNumQuestChoices", "GetQuestItemInfo", "C_QuestInfoSystem", "C_QuestOffer",
        "C_ChatInfo", "IsInGuild", "IsInGroup", "IsInRaid",
    },
}
