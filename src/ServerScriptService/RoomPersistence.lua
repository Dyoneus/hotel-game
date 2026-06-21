-- Explorer/ServerScriptService/RoomPersistence.lua
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")

local RoomPersistence = {}

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local RoomLayoutConfig = require(sharedFolder:WaitForChild("RoomLayoutConfig"))
local RoomFloorStyleConfig = require(sharedFolder:WaitForChild("RoomFloorStyleConfig"))

local DATASTORE_NAME = "PlayerProfiles_v1"
local SAVE_DELAY_SECONDS = 12
local STARTER_DOLLARS = 150
local MAX_OWNED_ROOMS = 3
local DAILY_REWARD_CURRENCY_KEY = "Dollars"
local DAILY_REWARD_ICON = ""
local CLAIM_COOLDOWN_SECONDS = 24 * 60 * 60
local CLAIM_GRACE_WINDOW_SECONDS = 24 * 60 * 60
local DAILY_REWARD_SCHEDULE = {
	50,
	60,
	70,
	80,
	90,
	100,
	150,
}
local ROOM_DIRECTORY_CATEGORIES = {
	["Chat Rooms"] = true,
	["Maze Rooms"] = true,
	["Trading Rooms"] = true,
	["Help Centres"] = true,
	["Gaming & Race Rooms"] = true,
}
local PRIMARY_ROOM_ID = "Primary"
local DEFAULT_PRIMARY_LAYOUT_ID = "Layout_01"
local DEFAULT_ROOM_DISPLAY_NAME = "My Room"
local ROOM_DISPLAY_NAME_MAX_LENGTH = 30
local ROOM_DESCRIPTION_MAX_LENGTH = 100
local PROFILE_COULD_NOT_LOAD_FLOOR_STYLE_MESSAGE = "Profile is not loaded and could not be loaded."
local DEBUG_ROOM_DELETE_TRACE = false
local DEBUG_ROOM_SAVE_TRACE = false
local DEBUG_PROFILE_CACHE = false

RoomPersistence.MAX_OWNED_ROOMS = MAX_OWNED_ROOMS

local profileStore = DataStoreService:GetDataStore(DATASTORE_NAME)

local profilesByPlayer = {}
local saveScheduled = {}
local saveRunning = {}
local writeBlockedByUserId = {}

local function traceProfileCache(...)
	if DEBUG_PROFILE_CACHE then
		warn("RoomPersistence profile cache:", ...)
	end
end

local function getProfileDebugId(profile)
	if typeof(profile) ~= "table" then
		return "nil"
	end

	return tostring(profile)
end

local function createEmptyRoomPermissions()
	return {
		Editors = {},
		RoomActions = {},
		FurniturePermissions = {},
	}
end

local function createDefaultProfile()
	local now = os.time()

	return {
		Version = 1,

		ProfileCreated = false,
		CharacterCreated = false,
		OnboardingStep = "CharacterCreation",

		CurrentLayoutId = nil,
		StarterDollarsGranted = false,
		HasSeenHotelIntro = false,

		RoomState = nil,
		RoomDirectory = {
			RoomIds = { PRIMARY_ROOM_ID },
			PrimaryRoomId = PRIMARY_ROOM_ID,
			SelectedRoomId = PRIMARY_ROOM_ID,
			RoomId = PRIMARY_ROOM_ID,
			DisplayName = nil,
			Category = "Chat Rooms",
			IsPublic = true,
			MaxOccupancy = 25,
			Description = "",
			Tags = {},
		},
		Rooms = {
			[PRIMARY_ROOM_ID] = {
				RoomId = PRIMARY_ROOM_ID,
				DisplayName = DEFAULT_ROOM_DISPLAY_NAME,
				LayoutId = DEFAULT_PRIMARY_LAYOUT_ID,
				RoomState = {},
				Style = {
					FloorStyleId = RoomFloorStyleConfig.GetDefaultStyleId(),
					UpdatedAt = now,
				},
				Category = "Chat Rooms",
				IsPublic = true,
				MaxOccupancy = 25,
				Description = "",
				Tags = {},
				CreatedAt = now,
				UpdatedAt = now,
				IsPrimary = true,
				SortOrder = 1,
				Permissions = createEmptyRoomPermissions(),
			},
		},
		FavouriteRooms = {},
		RoomPermissions = createEmptyRoomPermissions(),
		MarketplaceListings = {},
		RoomDecorInventory = {
			Floors = {},
		},
		Inventory = {},
		InventoryUntradable = {},
		InventoryUnsellable = {},
		Currencies = {
			Coins = 0,
			Dollars = 0,
			Event = {},
		},
		DailyReward = {
			LastClaimUnix = nil,
			Streak = 0,
		},
		WorkActivityCooldowns = {},

		UpdatedAt = now,
	}
end

local function deepCopy(value)
	if typeof(value) ~= "table" then
		return value
	end

	local copy = {}

	for key, child in pairs(value) do
		copy[key] = deepCopy(child)
	end

	return copy
end

local function isValidTemplateId(templateId)
	return typeof(templateId) == "string"
		and templateId ~= ""
		and templateId:match("%S") ~= nil
end

local function isValidRoomFavouriteKey(roomKey)
	local playerRoomPrefix = "PlayerRoom:"
	local publicSpacePrefix = "PublicSpace:"

	return typeof(roomKey) == "string"
		and roomKey ~= ""
		and #roomKey <= 120
		and (
			(string.sub(roomKey, 1, #playerRoomPrefix) == playerRoomPrefix and #roomKey > #playerRoomPrefix)
			or (string.sub(roomKey, 1, #publicSpacePrefix) == publicSpacePrefix and #roomKey > #publicSpacePrefix)
		)
end

local function isValidWorkActivityId(activityId)
	return typeof(activityId) == "string"
		and activityId ~= ""
		and activityId:match("%S") ~= nil
end

local function isPositiveInteger(value)
	return typeof(value) == "number"
		and value == value
		and value > 0
		and value < math.huge
		and value == math.floor(value)
end

local function isFiniteInteger(value)
	return typeof(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
		and value == math.floor(value)
end

local function isNonNegativeInteger(value)
	return typeof(value) == "number"
		and value == value
		and value >= 0
		and value < math.huge
		and value == math.floor(value)
end

local function normalizeInventoryCounts(inventory)
	local normalized = {}

	if typeof(inventory) ~= "table" then
		return normalized
	end

	for templateId, count in pairs(inventory) do
		if isValidTemplateId(templateId) and isNonNegativeInteger(count) and count > 0 then
			normalized[templateId] = count
		end
	end

	return normalized
end

local function normalizeInventorySubsetCount(subsetCount, totalCount)
	if not isPositiveInteger(totalCount) then
		return nil
	end

	if not isPositiveInteger(subsetCount) then
		return nil
	end

	-- Equality is valid: all remaining copies can be untradable or unsellable.
	return math.min(subsetCount, totalCount)
end

local function setInventorySubsetCount(subsetInventory, templateId, subsetCount, totalCount)
	local normalizedCount = normalizeInventorySubsetCount(subsetCount, totalCount)

	if normalizedCount then
		subsetInventory[templateId] = normalizedCount
	else
		subsetInventory[templateId] = nil
	end

	return normalizedCount or 0
end

local function ensureInventory(profile)
	local inventory = normalizeInventoryCounts(profile.Inventory)
	local untradable = normalizeInventoryCounts(profile.InventoryUntradable)
	local unsellable = normalizeInventoryCounts(profile.InventoryUnsellable)

	for templateId, untradableCount in pairs(untradable) do
		local totalCount = inventory[templateId] or 0

		setInventorySubsetCount(untradable, templateId, untradableCount, totalCount)
	end

	for templateId, unsellableCount in pairs(unsellable) do
		local totalCount = inventory[templateId] or 0

		setInventorySubsetCount(unsellable, templateId, unsellableCount, totalCount)
	end

	profile.Inventory = inventory
	profile.InventoryUntradable = untradable
	profile.InventoryUnsellable = unsellable

	return profile.Inventory, profile.InventoryUntradable, profile.InventoryUnsellable
end

local function isValidCurrencyKey(currencyKey)
	if typeof(currencyKey) ~= "string"
		or currencyKey == ""
		or currencyKey:match("%S") == nil then

		return false
	end

	if currencyKey == "Coins" or currencyKey == "Dollars" then
		return true
	end

	local eventId = currencyKey:match("^Event:(.+)$")

	return typeof(eventId) == "string"
		and eventId ~= ""
		and eventId:match("%S") ~= nil
end

local function parseCurrencyKey(currencyKey)
	if not isValidCurrencyKey(currencyKey) then
		return nil, nil
	end

	if currencyKey == "Coins" or currencyKey == "Dollars" then
		return "Base", currencyKey
	end

	return "Event", currencyKey:sub(7)
end

local function normalizeEventCurrencies(eventCurrencies)
	local normalized = {}

	if typeof(eventCurrencies) ~= "table" then
		return normalized
	end

	for eventId, balance in pairs(eventCurrencies) do
		if typeof(eventId) == "string"
			and eventId ~= ""
			and eventId:match("%S") ~= nil
			and isNonNegativeInteger(balance)
			and balance > 0 then

			normalized[eventId] = balance
		end
	end

	return normalized
end

local function ensureCurrencies(profile)
	local currencies = profile.Currencies

	if typeof(currencies) ~= "table" then
		currencies = {}
	end

	local coins = currencies.Coins

	if isNonNegativeInteger(profile.Coins)
		and (
			not isNonNegativeInteger(coins)
			or profile.Coins > coins
		) then

		coins = profile.Coins
	end

	currencies.Coins = isNonNegativeInteger(coins) and coins or 0
	currencies.Dollars = isNonNegativeInteger(currencies.Dollars) and currencies.Dollars or 0
	currencies.Event = normalizeEventCurrencies(currencies.Event)

	profile.Currencies = currencies
	profile.Coins = nil

	return profile.Currencies
end

local function getCurrencyBalance(profile, currencyKey)
	local currencyType, currencyId = parseCurrencyKey(currencyKey)

	if not currencyType then
		return nil
	end

	local currencies = ensureCurrencies(profile)

	if currencyType == "Base" then
		return currencies[currencyId] or 0
	end

	return currencies.Event[currencyId] or 0
end

local function setCurrencyBalance(profile, currencyKey, amount)
	local currencyType, currencyId = parseCurrencyKey(currencyKey)

	if not currencyType then
		return false
	end

	local currencies = ensureCurrencies(profile)

	if currencyType == "Base" then
		currencies[currencyId] = amount
	else
		if amount > 0 then
			currencies.Event[currencyId] = amount
		else
			currencies.Event[currencyId] = nil
		end
	end

	return true
end

local function getUtcDayKey(timeValue)
	return os.date("!%Y-%m-%d", timeValue or os.time())
end

local function getLegacyDailyRewardUnix(dailyReward, now)
	local lastClaimDay = dailyReward.LastClaimDay

	if typeof(lastClaimDay) ~= "string" or lastClaimDay == "" then
		return nil
	end

	if lastClaimDay == getUtcDayKey(now) then
		return now
	end

	local year, month, day = lastClaimDay:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")

	if not year then
		return nil
	end

	return os.time({
		year = tonumber(year),
		month = tonumber(month),
		day = tonumber(day),
		hour = 12,
		min = 0,
		sec = 0,
	})
end

local function ensureDailyReward(profile)
	local dailyReward = profile.DailyReward
	local now = os.time()

	if typeof(dailyReward) ~= "table" then
		dailyReward = {}
	end

	if isNonNegativeInteger(dailyReward.LastClaimUnix) and dailyReward.LastClaimUnix > 0 then
		dailyReward.LastClaimUnix = math.floor(dailyReward.LastClaimUnix)
	else
		dailyReward.LastClaimUnix = getLegacyDailyRewardUnix(dailyReward, now)
	end

	if typeof(dailyReward.LastClaimDay) ~= "string" or dailyReward.LastClaimDay == "" then
		dailyReward.LastClaimDay = nil
	end

	dailyReward.Streak = isNonNegativeInteger(dailyReward.Streak) and dailyReward.Streak or 0
	profile.DailyReward = dailyReward

	return profile.DailyReward
end

local function normalizeWorkActivityCooldowns(cooldowns, now)
	local normalized = {}

	if typeof(cooldowns) ~= "table" then
		return normalized
	end

	now = now or os.time()

	for activityId, cooldownRecord in pairs(cooldowns) do
		if isValidWorkActivityId(activityId) and typeof(cooldownRecord) == "table" then
			local nextAvailableUnix = cooldownRecord.NextAvailableUnix

			if isNonNegativeInteger(nextAvailableUnix) and nextAvailableUnix > now then
				normalized[activityId] = {
					LastCompletedUnix = isNonNegativeInteger(cooldownRecord.LastCompletedUnix)
						and math.floor(cooldownRecord.LastCompletedUnix)
						or nil,
					NextAvailableUnix = math.floor(nextAvailableUnix),
				}
			end
		end
	end

	return normalized
end

local function ensureWorkActivityCooldowns(profile)
	profile.WorkActivityCooldowns = normalizeWorkActivityCooldowns(profile.WorkActivityCooldowns)

	return profile.WorkActivityCooldowns
end

local function getDailyRewardDayIndex(streak)
	if not isPositiveInteger(streak) then
		return 1
	end

	return math.clamp(streak, 1, #DAILY_REWARD_SCHEDULE)
end

local function getNextDailyRewardDayIndex(streak)
	local nextStreak = (isNonNegativeInteger(streak) and streak or 0) + 1

	return getDailyRewardDayIndex(nextStreak)
end

local function getDailyRewardAmountForDay(dayIndex)
	return DAILY_REWARD_SCHEDULE[getDailyRewardDayIndex(dayIndex)] or DAILY_REWARD_SCHEDULE[1]
end

local function getDailyRewardScheduleSnapshot()
	local rewards = {}

	for day, amount in ipairs(DAILY_REWARD_SCHEDULE) do
		table.insert(rewards, {
			Day = day,
			CurrencyKey = DAILY_REWARD_CURRENCY_KEY,
			Amount = amount,
			Icon = DAILY_REWARD_ICON,
		})
	end

	return rewards
end

local function getDailyRewardClaimState(dailyReward, now)
	local streak = isNonNegativeInteger(dailyReward.Streak) and dailyReward.Streak or 0
	local lastClaimUnix = dailyReward.LastClaimUnix

	if not isNonNegativeInteger(lastClaimUnix) or lastClaimUnix <= 0 then
		return {
			CanClaim = true,
			LastClaimUnix = nil,
			Streak = 0,
			CurrentDayIndex = 1,
			RewardAmount = getDailyRewardAmountForDay(1),
			NextClaimUnix = nil,
			SecondsUntilNextClaim = 0,
			StreakResetPending = false,
		}
	end

	local elapsed = math.max(now - lastClaimUnix, 0)
	local nextClaimUnix = lastClaimUnix + CLAIM_COOLDOWN_SECONDS
	local currentDayIndex = getNextDailyRewardDayIndex(streak)

	if elapsed < CLAIM_COOLDOWN_SECONDS then
		return {
			CanClaim = false,
			LastClaimUnix = lastClaimUnix,
			Streak = streak,
			CurrentDayIndex = currentDayIndex,
			RewardAmount = getDailyRewardAmountForDay(currentDayIndex),
			NextClaimUnix = nextClaimUnix,
			SecondsUntilNextClaim = math.max(math.ceil(CLAIM_COOLDOWN_SECONDS - elapsed), 0),
			StreakResetPending = false,
		}
	end

	if elapsed < CLAIM_COOLDOWN_SECONDS + CLAIM_GRACE_WINDOW_SECONDS then
		return {
			CanClaim = true,
			LastClaimUnix = lastClaimUnix,
			Streak = streak,
			CurrentDayIndex = currentDayIndex,
			RewardAmount = getDailyRewardAmountForDay(currentDayIndex),
			NextClaimUnix = nil,
			SecondsUntilNextClaim = 0,
			StreakResetPending = false,
		}
	end

	return {
		CanClaim = true,
		LastClaimUnix = lastClaimUnix,
		Streak = streak,
		CurrentDayIndex = 1,
		RewardAmount = getDailyRewardAmountForDay(1),
		NextClaimUnix = nil,
		SecondsUntilNextClaim = 0,
		StreakResetPending = true,
	}
end

local function getInventoryCountDetails(profile, templateId)
	local inventory, untradable, unsellable = ensureInventory(profile)
	local total = inventory[templateId] or 0
	local untradableCount = normalizeInventorySubsetCount(untradable[templateId], total) or 0
	local tradableCount = math.max(0, total - untradableCount)
	local unsellableCount = normalizeInventorySubsetCount(unsellable[templateId], total) or 0
	local sellableCount = math.max(0, total - unsellableCount)

	return {
		Total = total,
		Tradable = tradableCount,
		Untradable = untradableCount,
		Sellable = sellableCount,
		Unsellable = unsellableCount,
	}
end

local function normalizeRoomTags(tags)
	local normalized = {}

	if typeof(tags) ~= "table" then
		return normalized
	end

	for _, tag in ipairs(tags) do
		if typeof(tag) == "string" and tag ~= "" and tag:match("%S") ~= nil then
			table.insert(normalized, tag)
		end
	end

	return normalized
end

local function trimString(value)
	if typeof(value) ~= "string" then
		return value
	end

	return value:match("^%s*(.-)%s*$") or ""
end

local function normalizeRoomId(roomId)
	if roomId == nil then
		return PRIMARY_ROOM_ID
	end

	if typeof(roomId) ~= "string" then
		return nil
	end

	local normalized = trimString(roomId)

	if normalized == "" or not normalized:match("^[%w_%-]+$") then
		return nil
	end

	return normalized
end

local function isValidRoomId(roomId)
	return normalizeRoomId(roomId) ~= nil
end

local function roomIdArrayContains(roomIds, roomId)
	if typeof(roomIds) ~= "table" then
		return false
	end

	for _, existingRoomId in ipairs(roomIds) do
		if existingRoomId == roomId then
			return true
		end
	end

	return false
end

local function normalizeRoomIds(roomIds)
	local normalizedRoomIds = {}
	local seenRoomIds = {}

	if typeof(roomIds) == "table" then
		for _, roomId in ipairs(roomIds) do
			local normalizedRoomId = normalizeRoomId(roomId)

			if normalizedRoomId and not seenRoomIds[normalizedRoomId] then
				seenRoomIds[normalizedRoomId] = true
				table.insert(normalizedRoomIds, normalizedRoomId)
			end
		end
	end

	if not seenRoomIds[PRIMARY_ROOM_ID] then
		table.insert(normalizedRoomIds, 1, PRIMARY_ROOM_ID)
	end

	return normalizedRoomIds
end

local function normalizeRoomIdsForExistingRooms(roomIds, rooms)
	local normalizedRoomIds = {}
	local seenRoomIds = {}

	if typeof(roomIds) == "table" and typeof(rooms) == "table" then
		for _, roomId in ipairs(roomIds) do
			local normalizedRoomId = normalizeRoomId(roomId)

			if normalizedRoomId
				and typeof(rooms[normalizedRoomId]) == "table"
				and not seenRoomIds[normalizedRoomId] then

				seenRoomIds[normalizedRoomId] = true
				table.insert(normalizedRoomIds, normalizedRoomId)
			end
		end
	end

	if not seenRoomIds[PRIMARY_ROOM_ID] then
		table.insert(normalizedRoomIds, 1, PRIMARY_ROOM_ID)
	end

	return normalizedRoomIds
end

local function roomIdArrayToSet(roomIds)
	local roomIdSet = {}

	if typeof(roomIds) == "table" then
		for _, roomId in ipairs(roomIds) do
			local normalizedRoomId = normalizeRoomId(roomId)

			if normalizedRoomId then
				roomIdSet[normalizedRoomId] = true
			end
		end
	end

	return roomIdSet
end

local function removeRoomIdFromDirectory(roomDirectory, roomId)
	local normalizedRoomId = normalizeRoomId(roomId)

	if not normalizedRoomId or typeof(roomDirectory) ~= "table" then
		return false
	end

	local nextRoomIds = {}
	local removed = false

	for _, existingRoomId in ipairs(normalizeRoomIds(roomDirectory.RoomIds)) do
		if existingRoomId == normalizedRoomId then
			removed = true
		else
			table.insert(nextRoomIds, existingRoomId)
		end
	end

	if not roomIdArrayContains(nextRoomIds, PRIMARY_ROOM_ID) then
		table.insert(nextRoomIds, 1, PRIMARY_ROOM_ID)
	end

	roomDirectory.RoomIds = nextRoomIds

	if normalizeRoomId(roomDirectory.SelectedRoomId) == normalizedRoomId then
		roomDirectory.SelectedRoomId = PRIMARY_ROOM_ID
	end

	if normalizeRoomId(roomDirectory.PrimaryRoomId) == nil then
		roomDirectory.PrimaryRoomId = PRIMARY_ROOM_ID
	end

	roomDirectory.RoomId = PRIMARY_ROOM_ID

	return removed
end

local function normalizePermissionUserId(userId)
	local numericUserId = nil

	if typeof(userId) == "number" then
		numericUserId = userId
	elseif typeof(userId) == "string" then
		numericUserId = tonumber(trimString(userId))
	end

	if typeof(numericUserId) ~= "number"
		or numericUserId ~= numericUserId
		or numericUserId == 0
		or math.abs(numericUserId) >= math.huge
		or numericUserId ~= math.floor(numericUserId) then

		return nil
	end

	return tostring(math.floor(numericUserId))
end

local function normalizePermissionActionName(actionName)
	if typeof(actionName) ~= "string" then
		return nil
	end

	local normalized = trimString(actionName)

	if normalized == "" then
		return nil
	end

	return normalized
end

local function normalizePermissionPersistentId(persistentId)
	if typeof(persistentId) ~= "string" then
		return nil
	end

	local normalized = trimString(persistentId)

	if normalized == "" then
		return nil
	end

	return normalized
end

local function normalizePermissionUserDictionary(userDictionary)
	local normalized = {}

	if typeof(userDictionary) ~= "table" then
		return normalized
	end

	for userId, isAllowed in pairs(userDictionary) do
		local normalizedUserId = normalizePermissionUserId(userId)

		if normalizedUserId and isAllowed == true then
			normalized[normalizedUserId] = true
		end
	end

	return normalized
end

local function dictionaryHasEntries(dictionary)
	for _ in pairs(dictionary) do
		return true
	end

	return false
end

local function normalizeRoomPermissions(roomPermissions)
	if typeof(roomPermissions) ~= "table" then
		roomPermissions = {}
	end

	local normalized = {}
	normalized.Editors = normalizePermissionUserDictionary(roomPermissions.Editors)

	local normalizedRoomActions = {}

	if typeof(roomPermissions.RoomActions) == "table" then
		for actionName, userDictionary in pairs(roomPermissions.RoomActions) do
			local normalizedActionName = normalizePermissionActionName(actionName)
			local normalizedUsers = normalizePermissionUserDictionary(userDictionary)

			if normalizedActionName and dictionaryHasEntries(normalizedUsers) then
				normalizedRoomActions[normalizedActionName] = normalizedUsers
			end
		end
	end

	normalized.RoomActions = normalizedRoomActions

	local normalizedFurniturePermissions = {}

	if typeof(roomPermissions.FurniturePermissions) == "table" then
		for persistentId, actionPermissions in pairs(roomPermissions.FurniturePermissions) do
			local normalizedPersistentId = normalizePermissionPersistentId(persistentId)
			local normalizedActionPermissions = {}

			if normalizedPersistentId and typeof(actionPermissions) == "table" then
				for actionName, userDictionary in pairs(actionPermissions) do
					local normalizedActionName = normalizePermissionActionName(actionName)
					local normalizedUsers = normalizePermissionUserDictionary(userDictionary)

					if normalizedActionName and dictionaryHasEntries(normalizedUsers) then
						normalizedActionPermissions[normalizedActionName] = normalizedUsers
					end
				end
			end

			if normalizedPersistentId and dictionaryHasEntries(normalizedActionPermissions) then
				normalizedFurniturePermissions[normalizedPersistentId] = normalizedActionPermissions
			end
		end
	end

	normalized.FurniturePermissions = normalizedFurniturePermissions

	return normalized
end

local function ensureRoomDirectory(profile)
	local roomDirectory = profile.RoomDirectory

	if typeof(roomDirectory) ~= "table" then
		roomDirectory = {}
	end

	if typeof(roomDirectory.RoomId) ~= "string" or roomDirectory.RoomId == "" then
		roomDirectory.RoomId = PRIMARY_ROOM_ID
	end

	roomDirectory.RoomIds = normalizeRoomIds(roomDirectory.RoomIds)

	if not roomIdArrayContains(roomDirectory.RoomIds, PRIMARY_ROOM_ID) then
		table.insert(roomDirectory.RoomIds, 1, PRIMARY_ROOM_ID)
	end

	if normalizeRoomId(roomDirectory.PrimaryRoomId) == nil then
		roomDirectory.PrimaryRoomId = PRIMARY_ROOM_ID
	else
		roomDirectory.PrimaryRoomId = normalizeRoomId(roomDirectory.PrimaryRoomId)
	end

	if not roomIdArrayContains(roomDirectory.RoomIds, roomDirectory.PrimaryRoomId) then
		roomDirectory.PrimaryRoomId = PRIMARY_ROOM_ID
	end

	if normalizeRoomId(roomDirectory.SelectedRoomId) == nil then
		roomDirectory.SelectedRoomId = roomDirectory.PrimaryRoomId
	else
		roomDirectory.SelectedRoomId = normalizeRoomId(roomDirectory.SelectedRoomId)
	end

	if not roomIdArrayContains(roomDirectory.RoomIds, roomDirectory.SelectedRoomId) then
		roomDirectory.SelectedRoomId = roomDirectory.PrimaryRoomId
	end

	if typeof(roomDirectory.DisplayName) ~= "string" or roomDirectory.DisplayName == "" then
		roomDirectory.DisplayName = nil
	end

	if typeof(roomDirectory.Category) ~= "string"
		or roomDirectory.Category == ""
		or not ROOM_DIRECTORY_CATEGORIES[roomDirectory.Category] then

		roomDirectory.Category = "Chat Rooms"
	end

	if typeof(roomDirectory.IsPublic) ~= "boolean" then
		roomDirectory.IsPublic = true
	end

	if not isPositiveInteger(roomDirectory.MaxOccupancy) then
		roomDirectory.MaxOccupancy = 25
	end

	if typeof(roomDirectory.Description) ~= "string" then
		roomDirectory.Description = ""
	end

	roomDirectory.Tags = normalizeRoomTags(roomDirectory.Tags)
	profile.RoomDirectory = roomDirectory

	return profile.RoomDirectory
end

local function ensureFavouriteRooms(profile)
	local favouriteRooms = profile.FavouriteRooms
	local normalized = {}

	if typeof(favouriteRooms) == "table" then
		for roomKey, isFavourite in pairs(favouriteRooms) do
			if isFavourite == true and isValidRoomFavouriteKey(roomKey) then
				normalized[roomKey] = true
			end
		end
	end

	profile.FavouriteRooms = normalized

	return profile.FavouriteRooms
end

local function ensureRoomPermissions(profile)
	profile.RoomPermissions = normalizeRoomPermissions(profile.RoomPermissions)

	return profile.RoomPermissions
end

local function isNonEmptyString(value)
	return typeof(value) == "string" and value ~= "" and value:match("%S") ~= nil
end

local function tableHasEntries(value)
	if typeof(value) ~= "table" then
		return false
	end

	for _ in pairs(value) do
		return true
	end

	return false
end

local function getRoomStateLayoutId(roomState)
	if typeof(roomState) ~= "table" then
		return nil
	end

	return isNonEmptyString(roomState.LayoutId) and roomState.LayoutId or nil
end

local function getDefaultFloorStyleId()
	local defaultStyleId = RoomFloorStyleConfig.GetDefaultStyleId()

	if isNonEmptyString(defaultStyleId) and RoomFloorStyleConfig.IsValidStyleId(defaultStyleId) then
		return defaultStyleId
	end

	return "Grid"
end

local function isRoomDecorFloorEntryUnlocked(entry)
	if entry == true then
		return true
	end

	if typeof(entry) ~= "table" then
		return false
	end

	if entry.Unlocked == true then
		return true
	end

	return isPositiveInteger(entry.Count)
end

local function normalizeRoomDecorFloorEntry(entry, now)
	if entry == true then
		return {
			Unlocked = true,
			AcquiredAt = now,
			UpdatedAt = now,
		}
	end

	if typeof(entry) ~= "table" then
		return nil
	end

	local unlocked = entry.Unlocked == true or isPositiveInteger(entry.Count)

	if not unlocked then
		return nil
	end

	local acquiredAt = isNonNegativeInteger(entry.AcquiredAt)
		and math.floor(entry.AcquiredAt)
		or now
	local updatedAt = isNonNegativeInteger(entry.UpdatedAt)
		and math.floor(entry.UpdatedAt)
		or acquiredAt

	local normalized = {
		Unlocked = true,
		AcquiredAt = acquiredAt,
		UpdatedAt = updatedAt,
	}

	if isPositiveInteger(entry.Count) then
		normalized.Count = math.floor(entry.Count)
	end

	if isNonEmptyString(entry.Source) then
		normalized.Source = trimString(entry.Source)
	end

	return normalized
end

local function ensureRoomDecorInventory(profile)
	local decorInventory = typeof(profile.RoomDecorInventory) == "table" and profile.RoomDecorInventory or {}
	local sourceFloors = typeof(decorInventory.Floors) == "table" and decorInventory.Floors or {}
	local floors = {}
	local now = os.time()

	for floorStyleId, entry in pairs(sourceFloors) do
		local normalizedFloorStyleId = trimString(floorStyleId)

		if isNonEmptyString(normalizedFloorStyleId)
			and RoomFloorStyleConfig.IsValidStyleId(normalizedFloorStyleId) then

			local normalizedEntry = normalizeRoomDecorFloorEntry(entry, now)

			if normalizedEntry then
				floors[normalizedFloorStyleId] = normalizedEntry
			end
		end
	end

	decorInventory.Floors = floors
	profile.RoomDecorInventory = decorInventory

	return profile.RoomDecorInventory
end

local function normalizeRoomStyle(style, defaults)
	defaults = defaults or {}

	if typeof(style) ~= "table" then
		style = {}
	end

	if not isNonEmptyString(style.FloorStyleId)
		or not RoomFloorStyleConfig.IsValidStyleId(style.FloorStyleId) then

		style.FloorStyleId = isNonEmptyString(defaults.FloorStyleId)
			and RoomFloorStyleConfig.IsValidStyleId(defaults.FloorStyleId)
			and defaults.FloorStyleId
			or getDefaultFloorStyleId()
	end

	local now = os.time()
	style.UpdatedAt = isNonNegativeInteger(style.UpdatedAt)
		and math.floor(style.UpdatedAt)
		or defaults.UpdatedAt
		or now

	return style
end

local function normalizeRoomStyleForRecord(roomRecord, defaults)
	defaults = defaults or {}

	local style = roomRecord.Style
	local styleDefaults = defaults.Style

	if typeof(style) ~= "table" and typeof(styleDefaults) == "table" then
		style = deepCopy(styleDefaults)
	end

	roomRecord.Style = normalizeRoomStyle(style, {
		FloorStyleId = typeof(styleDefaults) == "table" and styleDefaults.FloorStyleId or nil,
		UpdatedAt = typeof(styleDefaults) == "table" and styleDefaults.UpdatedAt or roomRecord.UpdatedAt,
	})

	return roomRecord.Style
end

local function ensureIntegerOrDefault(value, defaultValue)
	if isFiniteInteger(value) then
		return math.floor(value)
	end

	return defaultValue
end

local function normalizeRoomRecord(roomRecord, roomId, defaults)
	defaults = defaults or {}

	if typeof(roomRecord) ~= "table" then
		roomRecord = {}
	end

	roomRecord.RoomId = roomId

	if not isNonEmptyString(roomRecord.DisplayName) then
		roomRecord.DisplayName = defaults.DisplayName
	end

	if not isNonEmptyString(roomRecord.LayoutId) then
		roomRecord.LayoutId = defaults.LayoutId or DEFAULT_PRIMARY_LAYOUT_ID
	end

	if typeof(roomRecord.RoomState) ~= "table" then
		roomRecord.RoomState = defaults.RoomState and deepCopy(defaults.RoomState) or {}
	end

	if typeof(roomRecord.Category) ~= "string"
		or roomRecord.Category == ""
		or not ROOM_DIRECTORY_CATEGORIES[roomRecord.Category] then

		roomRecord.Category = defaults.Category or "Chat Rooms"
	end

	if typeof(roomRecord.IsPublic) ~= "boolean" then
		roomRecord.IsPublic = defaults.IsPublic

		if typeof(roomRecord.IsPublic) ~= "boolean" then
			roomRecord.IsPublic = true
		end
	end

	if not isPositiveInteger(roomRecord.MaxOccupancy) then
		roomRecord.MaxOccupancy = defaults.MaxOccupancy or 25
	end

	if typeof(roomRecord.Description) ~= "string" then
		roomRecord.Description = defaults.Description or ""
	end

	roomRecord.Tags = normalizeRoomTags(roomRecord.Tags or defaults.Tags)

	local now = os.time()
	roomRecord.CreatedAt = isNonNegativeInteger(roomRecord.CreatedAt)
		and math.floor(roomRecord.CreatedAt)
		or defaults.CreatedAt
		or now
	roomRecord.UpdatedAt = isNonNegativeInteger(roomRecord.UpdatedAt)
		and math.floor(roomRecord.UpdatedAt)
		or defaults.UpdatedAt
		or roomRecord.CreatedAt
		or now
	normalizeRoomStyleForRecord(roomRecord, defaults)
	roomRecord.IsPrimary = roomId == PRIMARY_ROOM_ID
	roomRecord.SortOrder = ensureIntegerOrDefault(
		roomRecord.SortOrder,
		roomId == PRIMARY_ROOM_ID and 1 or defaults.SortOrder or 1000
	)
	roomRecord.Permissions = normalizeRoomPermissions(roomRecord.Permissions or defaults.Permissions)

	return roomRecord
end

local function copyLegacyDirectoryMetadata(roomDirectory)
	return {
		DisplayName = isNonEmptyString(roomDirectory.DisplayName)
			and roomDirectory.DisplayName
			or DEFAULT_ROOM_DISPLAY_NAME,
		Category = roomDirectory.Category,
		IsPublic = roomDirectory.IsPublic,
		MaxOccupancy = roomDirectory.MaxOccupancy,
		Description = roomDirectory.Description,
		Tags = roomDirectory.Tags,
	}
end

local function syncPrimaryRoomFromLegacy(profile, primaryRoom)
	local roomDirectory = ensureRoomDirectory(profile)
	local roomPermissions = ensureRoomPermissions(profile)
	local legacyMetadata = copyLegacyDirectoryMetadata(roomDirectory)
	local legacyRoomState = typeof(profile.RoomState) == "table" and profile.RoomState or nil
	local legacyLayoutId = isNonEmptyString(profile.CurrentLayoutId) and profile.CurrentLayoutId or nil

	if not legacyLayoutId then
		legacyLayoutId = getRoomStateLayoutId(legacyRoomState)
	end

	if legacyRoomState then
		primaryRoom.RoomState = deepCopy(legacyRoomState)
	elseif typeof(primaryRoom.RoomState) ~= "table" then
		primaryRoom.RoomState = {}
	end

	if legacyLayoutId then
		primaryRoom.LayoutId = legacyLayoutId
	elseif getRoomStateLayoutId(primaryRoom.RoomState) then
		primaryRoom.LayoutId = getRoomStateLayoutId(primaryRoom.RoomState)
	elseif not isNonEmptyString(primaryRoom.LayoutId) then
		primaryRoom.LayoutId = DEFAULT_PRIMARY_LAYOUT_ID
	end

	primaryRoom.DisplayName = legacyMetadata.DisplayName
	primaryRoom.Category = legacyMetadata.Category
	primaryRoom.IsPublic = legacyMetadata.IsPublic
	primaryRoom.MaxOccupancy = legacyMetadata.MaxOccupancy
	primaryRoom.Description = legacyMetadata.Description
	primaryRoom.Tags = deepCopy(legacyMetadata.Tags)
	primaryRoom.Permissions = deepCopy(roomPermissions)

	return normalizeRoomRecord(primaryRoom, PRIMARY_ROOM_ID, {
		DisplayName = legacyMetadata.DisplayName,
		LayoutId = legacyLayoutId or DEFAULT_PRIMARY_LAYOUT_ID,
		RoomState = legacyRoomState,
		Category = legacyMetadata.Category,
		IsPublic = legacyMetadata.IsPublic,
		MaxOccupancy = legacyMetadata.MaxOccupancy,
		Description = legacyMetadata.Description,
		Tags = legacyMetadata.Tags,
		Permissions = roomPermissions,
		SortOrder = 1,
		CreatedAt = profile.UpdatedAt,
		UpdatedAt = profile.UpdatedAt,
	})
end

local function mirrorPrimaryRoomToLegacy(profile, primaryRoom)
	if typeof(primaryRoom) ~= "table" then
		return
	end

	if typeof(profile.RoomState) == "table" or tableHasEntries(primaryRoom.RoomState) then
		profile.RoomState = deepCopy(primaryRoom.RoomState)
	end

	if isNonEmptyString(profile.CurrentLayoutId) or typeof(profile.RoomState) == "table" then
		profile.CurrentLayoutId = primaryRoom.LayoutId
	end

	profile.RoomPermissions = deepCopy(primaryRoom.Permissions)
end

local function ensureRoomsSchema(profile)
	if typeof(profile) ~= "table" then
		return profile
	end

	ensureRoomDecorInventory(profile)

	local roomDirectory = ensureRoomDirectory(profile)
	local roomPermissions = ensureRoomPermissions(profile)

	if typeof(profile.Rooms) ~= "table" then
		profile.Rooms = {}
	end

	local primaryRoom = profile.Rooms[PRIMARY_ROOM_ID]

	if typeof(primaryRoom) ~= "table" then
		primaryRoom = {
			RoomId = PRIMARY_ROOM_ID,
			RoomState = typeof(profile.RoomState) == "table" and deepCopy(profile.RoomState) or {},
			LayoutId = isNonEmptyString(profile.CurrentLayoutId)
				and profile.CurrentLayoutId
				or getRoomStateLayoutId(profile.RoomState)
				or DEFAULT_PRIMARY_LAYOUT_ID,
			Permissions = deepCopy(roomPermissions),
		}
	end

	profile.Rooms[PRIMARY_ROOM_ID] = syncPrimaryRoomFromLegacy(profile, primaryRoom)

	for roomId, roomRecord in pairs(profile.Rooms) do
		local normalizedRoomId = normalizeRoomId(roomId)

		if normalizedRoomId and typeof(roomRecord) == "table" then
			profile.Rooms[roomId] = normalizeRoomRecord(roomRecord, normalizedRoomId, {
				Permissions = roomId == PRIMARY_ROOM_ID and roomPermissions or createEmptyRoomPermissions(),
			})

			if not roomIdArrayContains(roomDirectory.RoomIds, normalizedRoomId) then
				table.insert(roomDirectory.RoomIds, normalizedRoomId)
			end
		end
	end

	local previousDirectoryRoomIds = DEBUG_ROOM_DELETE_TRACE and roomIdArrayToSet(roomDirectory.RoomIds) or nil
	roomDirectory.RoomIds = normalizeRoomIdsForExistingRooms(roomDirectory.RoomIds, profile.Rooms)

	if DEBUG_ROOM_DELETE_TRACE and previousDirectoryRoomIds then
		local normalizedDirectoryRoomIds = roomIdArrayToSet(roomDirectory.RoomIds)

		for previousRoomId in pairs(previousDirectoryRoomIds) do
			if previousRoomId ~= PRIMARY_ROOM_ID and normalizedDirectoryRoomIds[previousRoomId] ~= true then
				warn("RoomPersistence: removed missing room id from RoomDirectory.RoomIds:", previousRoomId)
			end
		end
	end

	roomDirectory.PrimaryRoomId = PRIMARY_ROOM_ID

	if not profile.Rooms[roomDirectory.SelectedRoomId] then
		roomDirectory.SelectedRoomId = PRIMARY_ROOM_ID
	end

	roomDirectory.RoomId = PRIMARY_ROOM_ID
	profile.RoomDirectory = roomDirectory
	mirrorPrimaryRoomToLegacy(profile, profile.Rooms[PRIMARY_ROOM_ID])

	return profile
end

local function getMutableRoomRecord(profile, roomId)
	if typeof(profile) ~= "table" then
		return nil
	end

	local normalizedRoomId = normalizeRoomId(roomId)

	if not normalizedRoomId then
		return nil
	end

	ensureRoomsSchema(profile)

	local roomRecord = profile.Rooms and profile.Rooms[normalizedRoomId]

	if typeof(roomRecord) ~= "table" then
		return nil
	end

	return roomRecord, normalizedRoomId
end

local function getSortedOwnedRoomRecords(profile)
	ensureRoomsSchema(profile)

	local rooms = {}

	if typeof(profile.Rooms) ~= "table" then
		return rooms
	end

	for roomId, roomRecord in pairs(profile.Rooms) do
		if normalizeRoomId(roomId) and typeof(roomRecord) == "table" then
			table.insert(rooms, roomRecord)
		end
	end

	table.sort(rooms, function(a, b)
		local aSortOrder = isFiniteInteger(a.SortOrder) and a.SortOrder or math.huge
		local bSortOrder = isFiniteInteger(b.SortOrder) and b.SortOrder or math.huge

		if aSortOrder ~= bSortOrder then
			return aSortOrder < bSortOrder
		end

		local aCreatedAt = isNonNegativeInteger(a.CreatedAt) and a.CreatedAt or math.huge
		local bCreatedAt = isNonNegativeInteger(b.CreatedAt) and b.CreatedAt or math.huge

		if aCreatedAt ~= bCreatedAt then
			return aCreatedAt < bCreatedAt
		end

		return tostring(a.RoomId) < tostring(b.RoomId)
	end)

	return rooms
end

local function getOwnedRoomCount(profile)
	return #getSortedOwnedRoomRecords(profile)
end

local function getNextOwnedRoomSortOrder(profile)
	local nextSortOrder = 1

	for _, roomRecord in ipairs(getSortedOwnedRoomRecords(profile)) do
		if isFiniteInteger(roomRecord.SortOrder) and roomRecord.SortOrder >= nextSortOrder then
			nextSortOrder = roomRecord.SortOrder + 1
		end
	end

	return nextSortOrder
end

local function setRoomStateForRoomProfile(profile, roomId, roomState, layoutId)
	local roomRecord, normalizedRoomId = getMutableRoomRecord(profile, roomId)

	if not roomRecord then
		if DEBUG_ROOM_SAVE_TRACE then
			warn("RoomPersistence: refused room state save for missing room id:", tostring(roomId))
		end

		return false, "Room not found."
	end

	if typeof(roomState) ~= "table" then
		return false, "Invalid room state."
	end

	local roomStateCopy = deepCopy(roomState)

	roomRecord.RoomState = roomStateCopy

	local nextLayoutId = isNonEmptyString(layoutId) and layoutId or getRoomStateLayoutId(roomStateCopy)

	if nextLayoutId then
		roomRecord.LayoutId = nextLayoutId
	end

	roomRecord.UpdatedAt = os.time()

	if normalizedRoomId == PRIMARY_ROOM_ID then
		profile.RoomState = deepCopy(roomStateCopy)

		if isNonEmptyString(roomRecord.LayoutId) then
			profile.CurrentLayoutId = roomRecord.LayoutId
		end
	end

	return true, "Room state saved.", roomRecord, normalizedRoomId
end

local function setRoomPermissionsForRoomProfile(profile, roomId, permissions)
	local roomRecord, normalizedRoomId = getMutableRoomRecord(profile, roomId)

	if not roomRecord then
		return false, "Room not found."
	end

	local normalizedPermissions = normalizeRoomPermissions(permissions)

	roomRecord.Permissions = normalizedPermissions
	roomRecord.UpdatedAt = os.time()

	if normalizedRoomId == PRIMARY_ROOM_ID then
		profile.RoomPermissions = deepCopy(normalizedPermissions)
	end

	return true, "Room permissions saved.", roomRecord, normalizedRoomId
end

local function getRoomSettingsSnapshot(roomRecord)
	if typeof(roomRecord) ~= "table" then
		return nil
	end

	return {
		RoomId = roomRecord.RoomId,
		DisplayName = roomRecord.DisplayName,
		Category = roomRecord.Category,
		Description = roomRecord.Description,
		IsPublic = roomRecord.IsPublic,
		MaxOccupancy = roomRecord.MaxOccupancy,
		LayoutId = roomRecord.LayoutId,
		IsPrimary = roomRecord.IsPrimary == true or roomRecord.RoomId == PRIMARY_ROOM_ID,
		CreatedAt = roomRecord.CreatedAt,
		UpdatedAt = roomRecord.UpdatedAt,
		SortOrder = roomRecord.SortOrder,
	}
end

local function getRoomStyleSnapshot(roomRecord)
	if typeof(roomRecord) ~= "table" then
		return nil
	end

	return deepCopy(normalizeRoomStyleForRecord(roomRecord, {
		UpdatedAt = roomRecord.UpdatedAt,
	}))
end

local function mirrorPrimaryRoomSettingsToLegacy(profile, roomRecord)
	if typeof(profile) ~= "table" or typeof(roomRecord) ~= "table" then
		return
	end

	local roomDirectory = ensureRoomDirectory(profile)

	roomDirectory.DisplayName = isNonEmptyString(roomRecord.DisplayName)
		and roomRecord.DisplayName
		or DEFAULT_ROOM_DISPLAY_NAME
	roomDirectory.Category = roomRecord.Category
	roomDirectory.Description = roomRecord.Description
	roomDirectory.IsPublic = roomRecord.IsPublic == true
	roomDirectory.MaxOccupancy = roomRecord.MaxOccupancy
	roomDirectory.RoomId = PRIMARY_ROOM_ID
	roomDirectory.PrimaryRoomId = PRIMARY_ROOM_ID
	roomDirectory.Tags = normalizeRoomTags(roomDirectory.Tags)
	profile.RoomDirectory = roomDirectory
end

local function updateRoomSettingsForRoomProfile(profile, roomId, updates)
	if typeof(updates) ~= "table" then
		return false, "Invalid room settings.", nil, nil
	end

	ensureRoomsSchema(profile)

	local roomRecord, normalizedRoomId = getMutableRoomRecord(profile, roomId)

	if not roomRecord then
		return false, "Room not found.", nil, nil
	end

	if updates.DisplayName ~= nil then
		if typeof(updates.DisplayName) ~= "string" then
			return false, "Room name must be text.", nil, nil
		end

		local displayName = trimString(updates.DisplayName)

		if displayName == "" then
			return false, "Room name cannot be empty.", nil, nil
		end

		if #displayName > ROOM_DISPLAY_NAME_MAX_LENGTH then
			return false,
				"Room name too long. Maximum " .. tostring(ROOM_DISPLAY_NAME_MAX_LENGTH) .. " characters.",
				nil,
				nil
		end

		roomRecord.DisplayName = displayName
	end

	if updates.Description ~= nil then
		if typeof(updates.Description) ~= "string" then
			return false, "Description must be text.", nil, nil
		end

		local description = trimString(updates.Description)

		if #description > ROOM_DESCRIPTION_MAX_LENGTH then
			return false,
				"Description too long. Maximum " .. tostring(ROOM_DESCRIPTION_MAX_LENGTH) .. " characters.",
				nil,
				nil
		end

		roomRecord.Description = description
	end

	if updates.Category ~= nil then
		if typeof(updates.Category) ~= "string" or not ROOM_DIRECTORY_CATEGORIES[updates.Category] then
			return false, "Invalid room category.", nil, nil
		end

		roomRecord.Category = updates.Category
	end

	if updates.IsPublic ~= nil then
		if typeof(updates.IsPublic) ~= "boolean" then
			return false, "Public setting must be true or false.", nil, nil
		end

		roomRecord.IsPublic = updates.IsPublic
	end

	-- MaxOccupancy is displayed but not client-editable yet.

	local now = os.time()
	roomRecord.UpdatedAt = now
	profile.UpdatedAt = now

	if normalizedRoomId == PRIMARY_ROOM_ID then
		mirrorPrimaryRoomSettingsToLegacy(profile, roomRecord)
	end

	return true, "Room settings saved.", getRoomSettingsSnapshot(roomRecord), normalizedRoomId
end

local MARKETPLACE_LISTING_FIELDS = {
	ListingId = true,
	SellerUserId = true,
	TemplateId = true,
	Quantity = true,
	UnitPriceCoins = true,
	CurrencyKey = true,
	Status = true,
	CreatedAt = true,
	UpdatedAt = true,
	ExpiresAt = true,
	SoldAt = true,
	SoldUnitPriceCoins = true,
	SoldTotalCoins = true,
	BuyerUserId = true,
	TransactionId = true,
	Escrowed = true,
	ReturnTradable = true,
	ReturnSellable = true,
	LegacyNoEscrow = true,
	ProceedsClaimed = true,
	ClaimableCoins = true,
	ClaimedAt = true,
}

local function isValidListingRecord(listingRecord)
	return typeof(listingRecord) == "table"
		and typeof(listingRecord.ListingId) == "string"
		and listingRecord.ListingId ~= ""
		and isFiniteInteger(listingRecord.SellerUserId)
		and isValidTemplateId(listingRecord.TemplateId)
		and isPositiveInteger(listingRecord.Quantity)
		and isPositiveInteger(listingRecord.UnitPriceCoins)
		and typeof(listingRecord.CurrencyKey) == "string"
		and listingRecord.CurrencyKey ~= ""
		and typeof(listingRecord.Status) == "string"
		and listingRecord.Status ~= ""
		and (listingRecord.Escrowed == nil or typeof(listingRecord.Escrowed) == "boolean")
		and (listingRecord.ReturnTradable == nil or typeof(listingRecord.ReturnTradable) == "boolean")
		and (listingRecord.ReturnSellable == nil or typeof(listingRecord.ReturnSellable) == "boolean")
		and (listingRecord.LegacyNoEscrow == nil or typeof(listingRecord.LegacyNoEscrow) == "boolean")
		and (listingRecord.ProceedsClaimed == nil or typeof(listingRecord.ProceedsClaimed) == "boolean")
		and (listingRecord.ClaimableCoins == nil or isPositiveInteger(listingRecord.ClaimableCoins))
end

local function copyMarketplaceListing(listingRecord)
	local copy = {}

	for fieldName in pairs(MARKETPLACE_LISTING_FIELDS) do
		local value = listingRecord[fieldName]

		if value ~= nil then
			copy[fieldName] = deepCopy(value)
		end
	end

	return copy
end

local function ensureMarketplaceListings(profile)
	local listings = {}

	if typeof(profile.MarketplaceListings) == "table" then
		for listingId, listingRecord in pairs(profile.MarketplaceListings) do
			local normalizedListingId = nil

			if typeof(listingId) == "string" and listingId ~= "" then
				normalizedListingId = listingId
			elseif typeof(listingRecord) == "table"
				and typeof(listingRecord.ListingId) == "string"
				and listingRecord.ListingId ~= "" then

				normalizedListingId = listingRecord.ListingId
			end

			if normalizedListingId and isValidListingRecord(listingRecord) then
				local copy = copyMarketplaceListing(listingRecord)
				copy.ListingId = normalizedListingId
				listings[normalizedListingId] = copy
			end
		end
	end

	profile.MarketplaceListings = listings

	return profile.MarketplaceListings
end

local function fillDefaults(profile)
	local defaults = createDefaultProfile()

	if typeof(profile) ~= "table" then
		return ensureRoomsSchema(defaults)
	end

	local hasHotelIntroFlag = profile.HasSeenHotelIntro ~= nil
	local existingOnboardingStep = profile.OnboardingStep

	for key, defaultValue in pairs(defaults) do
		if profile[key] == nil then
			profile[key] = defaultValue
		end
	end

	ensureInventory(profile)
	ensureCurrencies(profile)
	ensureDailyReward(profile)
	ensureWorkActivityCooldowns(profile)
	ensureRoomDecorInventory(profile)
	ensureRoomDirectory(profile)
	ensureFavouriteRooms(profile)
	ensureRoomPermissions(profile)
	ensureRoomsSchema(profile)
	ensureMarketplaceListings(profile)

	if profile.StarterDollarsGranted ~= true then
		profile.StarterDollarsGranted = false
	end

	if hasHotelIntroFlag then
		profile.HasSeenHotelIntro = profile.HasSeenHotelIntro == true
	else
		profile.HasSeenHotelIntro = existingOnboardingStep == "Complete"
	end

	return profile
end

local function getKeyFromUserId(userId)
	return "Player_" .. tostring(userId)
end

local function getKey(player)
	return getKeyFromUserId(player.UserId)
end

local function cframeToArray(cframe)
	return { cframe:GetComponents() }
end

local function arrayToCFrame(array)
	if typeof(array) ~= "table" then
		return nil
	end

	if #array ~= 12 then
		return nil
	end

	for _, value in ipairs(array) do
		if typeof(value) ~= "number" then
			return nil
		end
	end

	return CFrame.new(table.unpack(array))
end

local function getRoomAnchor(roomModel)
	local roomAnchor = roomModel and roomModel:FindFirstChild("RoomAnchor", true)

	if roomAnchor and roomAnchor:IsA("BasePart") then
		return roomAnchor
	end

	return nil
end

local function getFurnitureFolder(roomModel)
	if not roomModel then
		return nil
	end

	return roomModel:FindFirstChild("Furniture")
end

local function getFurnitureTemplateById(templateId)
	if typeof(templateId) ~= "string" or templateId == "" then
		return nil
	end

	local furnitureTemplates = ReplicatedStorage:FindFirstChild("FurnitureTemplates")

	if not furnitureTemplates then
		return nil
	end

	local template = furnitureTemplates:FindFirstChild(templateId)

	if template and template:IsA("Model") then
		return template
	end

	return nil
end

local function ensureFurniturePersistentIds(furnitureFolder)
	local usedIds = {}

	for _, furnitureModel in ipairs(furnitureFolder:GetChildren()) do
		if furnitureModel:IsA("Model") then
			local persistentId = furnitureModel:GetAttribute("PersistentId")

			if typeof(persistentId) ~= "string" or persistentId == "" then
				persistentId = furnitureModel.Name
			end

			local baseId = persistentId
			local suffix = 2

			while usedIds[persistentId] do
				persistentId = baseId .. "_" .. tostring(suffix)
				suffix += 1
			end

			usedIds[persistentId] = true
			furnitureModel:SetAttribute("PersistentId", persistentId)
		end
	end
end

local function serializeRoom(roomModel)
	local roomAnchor = getRoomAnchor(roomModel)
	local furnitureFolder = getFurnitureFolder(roomModel)

	if not roomAnchor or not furnitureFolder then
		warn(
			"RoomPersistence: cannot serialize room; missing RoomAnchor or Furniture folder:",
			roomModel and roomModel.Name
		)

		return nil
	end

	ensureFurniturePersistentIds(furnitureFolder)

	local furnitureItems = {}

	for _, furnitureModel in ipairs(furnitureFolder:GetChildren()) do
		if furnitureModel:IsA("Model") then
			local persistentId = furnitureModel:GetAttribute("PersistentId")
			local relativeCFrame = roomAnchor.CFrame:ToObjectSpace(furnitureModel:GetPivot())

			table.insert(furnitureItems, {
				Id = persistentId,
				Name = furnitureModel.Name,

				-- TemplateId is needed for catalog-spawned furniture.
				-- Starter layout furniture can leave this nil.
				TemplateId = furnitureModel:GetAttribute("TemplateId"),
				Tradable = furnitureModel:GetAttribute("Tradable"),
				Sellable = furnitureModel:GetAttribute("Sellable"),

				RelativeCFrame = cframeToArray(relativeCFrame),
			})
		end
	end

	table.sort(furnitureItems, function(a, b)
		return tostring(a.Id) < tostring(b.Id)
	end)

	return {
		LayoutId = roomModel:GetAttribute("LayoutId"),
		Furniture = furnitureItems,
		SavedAt = os.time(),
	}
end

local function retryAsync(label, attempts, callback)
	local lastError = nil

	for attempt = 1, attempts do
		local success, result = pcall(callback)

		if success then
			return true, result
		end

		lastError = result
		warn(label .. " failed, attempt " .. tostring(attempt) .. ":", result)

		if attempt < attempts then
			task.wait(math.min(2 ^ attempt, 8))
		end
	end

	return false, lastError
end

function RoomPersistence.ApplyRoomState(roomModel, roomState)
	if typeof(roomState) ~= "table" then
		return
	end

	local roomAnchor = getRoomAnchor(roomModel)
	local furnitureFolder = getFurnitureFolder(roomModel)

	if not roomAnchor or not furnitureFolder then
		warn(
			"RoomPersistence: cannot apply room state; missing RoomAnchor or Furniture folder:",
			roomModel and roomModel.Name
		)

		return
	end

	if typeof(roomState.Furniture) ~= "table" then
		return
	end

	ensureFurniturePersistentIds(furnitureFolder)

	local furnitureById = {}
	local furnitureByName = {}

	for _, furnitureModel in ipairs(furnitureFolder:GetChildren()) do
		if furnitureModel:IsA("Model") then
			local persistentId = furnitureModel:GetAttribute("PersistentId")

			if typeof(persistentId) == "string" and persistentId ~= "" then
				furnitureById[persistentId] = furnitureModel
			end

			furnitureByName[furnitureModel.Name] = furnitureModel
		end
	end

	local restoredFurnitureModels = {}

	for _, savedItem in ipairs(roomState.Furniture) do
		if typeof(savedItem) == "table" then
			local relativeCFrame = arrayToCFrame(savedItem.RelativeCFrame)

			if not relativeCFrame then
				continue
			end

			local savedId = savedItem.Id
			local templateId = savedItem.TemplateId
			local furnitureModel = nil

			if typeof(savedId) == "string" and savedId ~= "" then
				furnitureModel = furnitureById[savedId]
			end

			-- Catalog-spawned furniture may not exist in the starter layout.
			-- If it has a TemplateId and was not found by PersistentId, recreate it.
			if not furnitureModel
				and typeof(templateId) == "string"
				and templateId ~= "" then

				local template = getFurnitureTemplateById(templateId)

				if template then
					furnitureModel = template:Clone()

					if typeof(savedItem.Name) == "string" and savedItem.Name ~= "" then
						furnitureModel.Name = savedItem.Name
					else
						furnitureModel.Name = template.Name
					end

					furnitureModel:SetAttribute("TemplateId", templateId)

					if typeof(savedId) == "string" and savedId ~= "" then
						furnitureModel:SetAttribute("PersistentId", savedId)
						furnitureById[savedId] = furnitureModel
					end

					furnitureModel.Parent = furnitureFolder
				else
					warn("RoomPersistence: missing furniture template for saved item:", templateId)
				end
			end

			-- Old saves / starter layout furniture fallback.
			-- Only use name fallback for non-catalog items.
			if not furnitureModel
				and (typeof(templateId) ~= "string" or templateId == "")
				and typeof(savedItem.Name) == "string" then

				furnitureModel = furnitureByName[savedItem.Name]
			end

			if furnitureModel then
				restoredFurnitureModels[furnitureModel] = true

				if typeof(savedItem.Tradable) == "boolean" then
					furnitureModel:SetAttribute("Tradable", savedItem.Tradable)
				end

				if typeof(savedItem.Sellable) == "boolean" then
					furnitureModel:SetAttribute("Sellable", savedItem.Sellable)
				end

				furnitureModel:PivotTo(roomAnchor.CFrame * relativeCFrame)
			end
		end
	end

	for _, furnitureModel in ipairs(furnitureFolder:GetChildren()) do
		if furnitureModel:IsA("Model") and not restoredFurnitureModels[furnitureModel] then
			furnitureModel:Destroy()
		end
	end
end

function RoomPersistence.LoadProfile(player)
	local cachedProfile = profilesByPlayer[player]

	if cachedProfile then
		cachedProfile = ensureRoomsSchema(cachedProfile)
		profilesByPlayer[player] = cachedProfile
		traceProfileCache("LoadProfile cache hit", player.Name, getProfileDebugId(cachedProfile))
		return cachedProfile, true
	end

	local success, data = pcall(function()
		return profileStore:GetAsync(getKey(player))
	end)

	if not success then
		warn("RoomPersistence: profile load failed for", player.Name, data)

		-- Studio fallback keeps development usable if API access is disabled.
		-- Real persistence still requires Studio API access / live server DataStores.
		if RunService:IsStudio() then
			local fallbackProfile = createDefaultProfile()
			ensureRoomsSchema(fallbackProfile)
			profilesByPlayer[player] = fallbackProfile
			traceProfileCache("LoadProfile studio fallback", player.Name, getProfileDebugId(fallbackProfile))
			return fallbackProfile, true
		end

		return nil, false
	end

	local profile = fillDefaults(data)
	profilesByPlayer[player] = profile
	traceProfileCache("LoadProfile loaded", player.Name, getProfileDebugId(profile))

	return profile, true
end

function RoomPersistence.GetProfile(player)
	local profile = profilesByPlayer[player]

	if not profile then
		traceProfileCache("GetProfile miss", player and player.Name or "nil")
		return nil
	end

	profile = ensureRoomsSchema(profile)
	profilesByPlayer[player] = profile
	traceProfileCache("GetProfile hit", player.Name, getProfileDebugId(profile))

	return profile
end

local function getOrLoadProfileForFloorStyle(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, "Invalid player."
	end

	local profile = RoomPersistence.GetProfile(player)

	if profile then
		return profile, nil
	end

	local loadedProfile, loaded = RoomPersistence.LoadProfile(player)

	if loaded and loadedProfile then
		profile = RoomPersistence.GetProfile(player) or loadedProfile
	end

	if not profile then
		return nil, PROFILE_COULD_NOT_LOAD_FLOOR_STYLE_MESSAGE
	end

	return profile, nil
end

function RoomPersistence.EnsureRoomsSchema(profile)
	return ensureRoomsSchema(profile)
end

function RoomPersistence.GetRoomDecorInventorySnapshot(player)
	local profile = getOrLoadProfileForFloorStyle(player)

	if not profile then
		return {
			Floors = {},
		}
	end

	return deepCopy(ensureRoomDecorInventory(profile))
end

function RoomPersistence.GetOwnedFloorStyles(player)
	local profile = getOrLoadProfileForFloorStyle(player)

	if profile then
		ensureRoomDecorInventory(profile)
	end

	return {}
end

function RoomPersistence.PlayerOwnsFloorStyle(player, floorStyleId)
	return false
end

function RoomPersistence.GrantFloorStyle(player, floorStyleId, options)
	return false, "Permanent floor style unlocks are no longer supported.", nil
end

function RoomPersistence.PurchaseFloorStyle(player, floorStyleId)
	local normalizedFloorStyleId = trimString(floorStyleId)
	local style = RoomFloorStyleConfig.GetStyle(normalizedFloorStyleId)

	return false, "Preview and apply floors from Room Settings.", {
		FloorStyleId = normalizedFloorStyleId,
		DisplayName = style and style.DisplayName or nil,
		CurrencyKey = style and style.CurrencyKey or nil,
		Price = style and style.Price or nil,
	}
end

function RoomPersistence.GetMaxOwnedRooms(_player)
	return MAX_OWNED_ROOMS
end

function RoomPersistence.GenerateRoomId(player)
	local profile = profilesByPlayer[player]

	if not profile then
		return nil
	end

	ensureRoomsSchema(profile)

	local timestamp = os.time()

	for attempt = 1, 9999 do
		local roomId = "Room_" .. tostring(timestamp) .. "_" .. tostring(attempt)

		if roomId ~= PRIMARY_ROOM_ID and not profile.Rooms[roomId] then
			return roomId
		end
	end

	return nil
end

function RoomPersistence.GetOwnedRoomsSnapshot(player)
	local profile = profilesByPlayer[player]

	if not profile then
		return {}
	end

	ensureRoomsSchema(profile)

	local snapshot = {}

	for _, roomRecord in ipairs(getSortedOwnedRoomRecords(profile)) do
		table.insert(snapshot, deepCopy(roomRecord))
	end

	return snapshot
end

function RoomPersistence.GetRoomRecord(player, roomId)
	local profile = profilesByPlayer[player]

	if not profile then
		return nil
	end

	ensureRoomsSchema(profile)

	local roomRecord = getMutableRoomRecord(profile, roomId)

	if not roomRecord then
		return nil
	end

	return deepCopy(roomRecord)
end

function RoomPersistence.GetRoomSettingsForRoom(player, roomId)
	local profile = profilesByPlayer[player]

	if not profile then
		return nil
	end

	ensureRoomsSchema(profile)

	local roomRecord = getMutableRoomRecord(profile, roomId)

	if not roomRecord then
		return nil
	end

	return getRoomSettingsSnapshot(roomRecord)
end

function RoomPersistence.GetRoomStyleForRoom(player, roomId)
	local profile, profileMessage = getOrLoadProfileForFloorStyle(player)

	if not profile then
		return nil, profileMessage
	end

	ensureRoomsSchema(profile)

	local roomRecord = getMutableRoomRecord(profile, roomId)

	if not roomRecord then
		return nil, "Room not found."
	end

	return getRoomStyleSnapshot(roomRecord), "Room style loaded."
end

function RoomPersistence.GetRoomFloorStyle(player, roomId)
	local defaultStyleId = getDefaultFloorStyleId()
	local profile = getOrLoadProfileForFloorStyle(player)

	if not profile then
		return defaultStyleId
	end

	ensureRoomsSchema(profile)

	local roomRecord = getMutableRoomRecord(profile, roomId)

	if not roomRecord then
		return defaultStyleId
	end

	local style = normalizeRoomStyleForRecord(roomRecord, {
		UpdatedAt = roomRecord.UpdatedAt,
	})
	local floorStyleId = style and style.FloorStyleId

	if RoomFloorStyleConfig.IsValidStyleId(floorStyleId) then
		return floorStyleId
	end

	return defaultStyleId
end

function RoomPersistence.SetRoomFloorStyleForRoom(player, roomId, floorStyleId, _options)
	local profile, profileMessage = getOrLoadProfileForFloorStyle(player)

	if not profile then
		return false, profileMessage, nil
	end

	ensureRoomsSchema(profile)

	local roomRecord = getMutableRoomRecord(profile, roomId)

	if not roomRecord then
		return false, "Room not found.", nil
	end

	local normalizedFloorStyleId = trimString(floorStyleId)

	if not isNonEmptyString(normalizedFloorStyleId)
		or not RoomFloorStyleConfig.IsValidStyleId(normalizedFloorStyleId) then

		return false, "Floor style not found.", nil
	end

	local canUseStyle = RoomFloorStyleConfig.CanApplyWithoutPayment(normalizedFloorStyleId)

	if not canUseStyle then
		return false, "Paid floor styles must be applied from Room Settings.", nil
	end

	local now = os.time()
	local style = normalizeRoomStyleForRecord(roomRecord, {
		UpdatedAt = roomRecord.UpdatedAt,
	})

	style.FloorStyleId = normalizedFloorStyleId
	style.UpdatedAt = now
	roomRecord.UpdatedAt = now
	profile.UpdatedAt = now

	RoomPersistence.QueueSave(player)

	return true, "Floor style saved.", deepCopy(style)
end

function RoomPersistence.ApplyRoomFloorStylePaid(player, roomId, floorStyleId, options)
	local normalizedFloorStyleId = trimString(floorStyleId)

	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "Invalid player.", nil
	end

	if not isNonEmptyString(normalizedFloorStyleId)
		or not RoomFloorStyleConfig.IsValidStyleId(normalizedFloorStyleId) then

		return false, "Floor style not found.", nil
	end

	local styleConfig = RoomFloorStyleConfig.GetStyle(normalizedFloorStyleId)

	if typeof(styleConfig) ~= "table" then
		return false, "Floor style not found.", nil
	end

	local profile, profileMessage = getOrLoadProfileForFloorStyle(player)

	if not profile then
		return false, profileMessage, nil
	end

	ensureRoomsSchema(profile)
	ensureCurrencies(profile)

	local roomRecord = getMutableRoomRecord(profile, roomId)

	if not roomRecord then
		return false, "Room not found.", nil
	end

	local currentStyle = normalizeRoomStyleForRecord(roomRecord, {
		UpdatedAt = roomRecord.UpdatedAt,
	})

	if currentStyle.FloorStyleId == normalizedFloorStyleId then
		return true, "This floor is already applied.", {
			FloorStyleId = normalizedFloorStyleId,
			CurrentFloorStyleId = normalizedFloorStyleId,
			Style = deepCopy(currentStyle),
			Charged = false,
			ChargedAmount = 0,
			CurrencyKey = styleConfig.CurrencyKey or "Dollars",
			Price = styleConfig.Price or 0,
			NewCurrencyBalance = getCurrencyBalance(profile, styleConfig.CurrencyKey or "Dollars"),
		}
	end

	local isFreeStyle = RoomFloorStyleConfig.IsFreeStyle(normalizedFloorStyleId)
	local price, currencyKey = RoomFloorStyleConfig.GetApplyCost(normalizedFloorStyleId)
	price = typeof(price) == "number" and math.floor(price) or 0
	currencyKey = trimString(currencyKey)

	if isFreeStyle then
		local now = os.time()

		currentStyle.FloorStyleId = normalizedFloorStyleId
		currentStyle.UpdatedAt = now
		roomRecord.UpdatedAt = now
		profile.UpdatedAt = now

		RoomPersistence.QueueSave(player)

		return true, "Floor updated.", {
			FloorStyleId = normalizedFloorStyleId,
			CurrentFloorStyleId = normalizedFloorStyleId,
			Style = deepCopy(currentStyle),
			Charged = false,
			ChargedAmount = 0,
			CurrencyKey = currencyKey ~= "" and currencyKey or "Dollars",
			Price = 0,
			NewCurrencyBalance = getCurrencyBalance(profile, currencyKey ~= "" and currencyKey or "Dollars"),
		}
	end

	if not isValidCurrencyKey(currencyKey) then
		return false, "This floor style is not available yet.", {
			FloorStyleId = normalizedFloorStyleId,
			CurrencyKey = currencyKey,
			Price = price,
			Charged = false,
		}
	end

	if currencyKey ~= "Dollars" then
		return false, "This floor style uses an unsupported currency.", {
			FloorStyleId = normalizedFloorStyleId,
			CurrencyKey = currencyKey,
			Price = price,
			Charged = false,
		}
	end

	if not isPositiveInteger(price) then
		return false, "This floor style is missing a valid price.", {
			FloorStyleId = normalizedFloorStyleId,
			CurrencyKey = currencyKey,
			Price = price,
			Charged = false,
		}
	end

	local currentBalance = getCurrencyBalance(profile, currencyKey)

	if currentBalance < price then
		return false, "Not enough Dollars.", {
			FloorStyleId = normalizedFloorStyleId,
			CurrencyKey = currencyKey,
			Price = price,
			Charged = false,
			NewCurrencyBalance = currentBalance,
		}
	end

	local rollbackSnapshot = {
		Currencies = deepCopy(profile.Currencies),
		RoomStyle = deepCopy(roomRecord.Style),
		RoomUpdatedAt = roomRecord.UpdatedAt,
		ProfileUpdatedAt = profile.UpdatedAt,
	}
	local now = os.time()
	local newBalance = currentBalance - price

	setCurrencyBalance(profile, currencyKey, newBalance)
	currentStyle.FloorStyleId = normalizedFloorStyleId
	currentStyle.UpdatedAt = now
	roomRecord.UpdatedAt = now
	profile.UpdatedAt = now

	local saveOk, saveMessage = RoomPersistence.SavePlayer(player)

	if not saveOk then
		profile.Currencies = deepCopy(rollbackSnapshot.Currencies)
		roomRecord.Style = deepCopy(rollbackSnapshot.RoomStyle)
		roomRecord.UpdatedAt = rollbackSnapshot.RoomUpdatedAt
		profile.UpdatedAt = rollbackSnapshot.ProfileUpdatedAt
		ensureCurrencies(profile)
		normalizeRoomStyleForRecord(roomRecord, {
			UpdatedAt = roomRecord.UpdatedAt,
		})

		return false, "Floor style apply failed: " .. tostring(saveMessage), {
			FloorStyleId = normalizedFloorStyleId,
			CurrencyKey = currencyKey,
			Price = price,
			Charged = false,
			NewCurrencyBalance = currentBalance,
		}
	end

	return true, "Floor updated.", {
		FloorStyleId = normalizedFloorStyleId,
		CurrentFloorStyleId = normalizedFloorStyleId,
		Style = deepCopy(currentStyle),
		Charged = true,
		ChargedAmount = price,
		CurrencyKey = currencyKey,
		Price = price,
		NewCurrencyBalance = newBalance,
	}
end

function RoomPersistence.UpdateRoomSettingsForRoom(player, roomId, updates)
	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded.", nil, nil
	end

	local success, message, settings, normalizedRoomId =
		updateRoomSettingsForRoomProfile(profile, roomId, updates)

	if not success then
		return false, message, nil, normalizedRoomId
	end

	RoomPersistence.QueueSave(player)

	return true, message, deepCopy(settings), normalizedRoomId
end

-- Internal migration helper. This returns the actual profile table record.
function RoomPersistence.GetMutableRoomRecord(profile, roomId)
	return getMutableRoomRecord(profile, roomId)
end

function RoomPersistence.GetPrimaryRoomId(player)
	local profile = profilesByPlayer[player]

	if not profile then
		return PRIMARY_ROOM_ID
	end

	ensureRoomsSchema(profile)

	local primaryRoomId = profile.RoomDirectory and profile.RoomDirectory.PrimaryRoomId

	return normalizeRoomId(primaryRoomId) or PRIMARY_ROOM_ID
end

function RoomPersistence.GetSelectedRoomId(player)
	local profile = profilesByPlayer[player]

	if not profile then
		return PRIMARY_ROOM_ID
	end

	ensureRoomsSchema(profile)

	local selectedRoomId = profile.RoomDirectory and profile.RoomDirectory.SelectedRoomId
	local normalizedSelectedRoomId = normalizeRoomId(selectedRoomId)

	if normalizedSelectedRoomId and profile.Rooms and profile.Rooms[normalizedSelectedRoomId] then
		return normalizedSelectedRoomId
	end

	return RoomPersistence.GetPrimaryRoomId(player)
end

function RoomPersistence.SetSelectedRoomId(player, roomId)
	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded.", nil
	end

	local roomRecord, normalizedRoomId = getMutableRoomRecord(profile, roomId)

	if not roomRecord then
		return false, "Room not found.", nil
	end

	local roomDirectory = ensureRoomDirectory(profile)
	roomDirectory.SelectedRoomId = normalizedRoomId
	profile.UpdatedAt = os.time()

	RoomPersistence.QueueSave(player)

	return true, "Selected room saved.", normalizedRoomId
end

function RoomPersistence.GetRoomStateForRoom(player, roomId)
	local profile = profilesByPlayer[player]

	if not profile then
		return nil
	end

	local roomRecord = getMutableRoomRecord(profile, roomId)

	if not roomRecord then
		return nil
	end

	return deepCopy(roomRecord.RoomState)
end

function RoomPersistence.SetRoomStateForRoom(player, roomId, roomState, layoutId)
	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded.", nil
	end

	local success, message, roomRecord, normalizedRoomId =
		setRoomStateForRoomProfile(profile, roomId, roomState, layoutId)

	if not success then
		return false, message, nil
	end

	profile.UpdatedAt = os.time()
	RoomPersistence.QueueSave(player)

	return true, message, deepCopy(roomRecord), normalizedRoomId
end

function RoomPersistence.GetRoomPermissionsForRoom(player, roomId)
	local profile = profilesByPlayer[player]

	if not profile then
		return nil
	end

	local roomRecord, normalizedRoomId = getMutableRoomRecord(profile, roomId)

	if not roomRecord then
		return nil
	end

	if normalizedRoomId == PRIMARY_ROOM_ID and typeof(roomRecord.Permissions) ~= "table" then
		return deepCopy(ensureRoomPermissions(profile))
	end

	return deepCopy(normalizeRoomPermissions(roomRecord.Permissions))
end

function RoomPersistence.SetRoomPermissionsForRoom(player, roomId, permissions)
	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded.", nil
	end

	local success, message, roomRecord, normalizedRoomId =
		setRoomPermissionsForRoomProfile(profile, roomId, permissions)

	if not success then
		return false, message, nil
	end

	profile.UpdatedAt = os.time()
	RoomPersistence.QueueSave(player)

	return true, message, deepCopy(roomRecord.Permissions), normalizedRoomId
end

function RoomPersistence.CreateOwnedRoom(player, options)
	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded.", nil
	end

	if typeof(options) ~= "table" then
		return false, "Invalid room options.", nil
	end

	ensureRoomsSchema(profile)

	if getOwnedRoomCount(profile) >= MAX_OWNED_ROOMS then
		return false, "Maximum room limit reached.", nil
	end

	local layoutId = options.LayoutId

	if not isNonEmptyString(layoutId) then
		return false, "Layout not found.", nil
	end

	local layout = RoomLayoutConfig.GetLayout(layoutId)

	if not layout then
		return false, "Layout not found.", nil
	end

	if layout.IsSelectable ~= true then
		return false, "This layout is currently unavailable.", nil
	end

	local canUseLayout, layoutMessage = RoomLayoutConfig.CanUseLayout(layoutId, {
		HasVip = player:GetAttribute("HasVip") == true or options.AllowVipTesting == true,
		IncludeUnavailable = false,
	})

	if not canUseLayout then
		return false, layoutMessage or "This layout is currently unavailable.", nil
	end

	if typeof(options.DisplayName) ~= "string" then
		return false, "Room name must be text.", nil
	end

	local displayName = trimString(options.DisplayName)

	if displayName == "" then
		return false, "Room name cannot be empty.", nil
	end

	if #displayName > ROOM_DISPLAY_NAME_MAX_LENGTH then
		return false, "Room name too long. Maximum " .. tostring(ROOM_DISPLAY_NAME_MAX_LENGTH) .. " characters.", nil
	end

	local category = options.Category

	if typeof(category) ~= "string" or category == "" then
		category = "Chat Rooms"
	elseif not ROOM_DIRECTORY_CATEGORIES[category] then
		return false, "Invalid room category.", nil
	end

	local description = options.Description

	if description == nil then
		description = ""
	end

	if typeof(description) ~= "string" then
		return false, "Description must be text.", nil
	end

	description = trimString(description)

	if #description > ROOM_DESCRIPTION_MAX_LENGTH then
		return false, "Description too long. Maximum " .. tostring(ROOM_DESCRIPTION_MAX_LENGTH) .. " characters.", nil
	end

	local isPublic = options.IsPublic

	if isPublic == nil then
		isPublic = true
	elseif typeof(isPublic) ~= "boolean" then
		return false, "Public setting must be true or false.", nil
	end

	local roomId = RoomPersistence.GenerateRoomId(player)

	if not roomId then
		return false, "Could not create room id.", nil
	end

	local now = os.time()
	local maxOccupancy = layout.MaxVisitors

	if not isPositiveInteger(maxOccupancy) then
		maxOccupancy = 25
	end

	local sortOrder = getNextOwnedRoomSortOrder(profile)
	local roomRecord = normalizeRoomRecord({
		RoomId = roomId,
		DisplayName = displayName,
		LayoutId = layoutId,
		RoomState = {},
		Category = category,
		IsPublic = isPublic,
		MaxOccupancy = maxOccupancy,
		Description = description,
		Tags = {},
		CreatedAt = now,
		UpdatedAt = now,
		IsPrimary = false,
		SortOrder = sortOrder,
		Permissions = createEmptyRoomPermissions(),
	}, roomId, {
		DisplayName = displayName,
		LayoutId = layoutId,
		RoomState = {},
		Category = category,
		IsPublic = isPublic,
		MaxOccupancy = maxOccupancy,
		Description = description,
		Tags = {},
		CreatedAt = now,
		UpdatedAt = now,
		SortOrder = sortOrder,
		Permissions = createEmptyRoomPermissions(),
	})

	profile.Rooms[roomId] = roomRecord

	local roomDirectory = ensureRoomDirectory(profile)

	if not roomIdArrayContains(roomDirectory.RoomIds, roomId) then
		table.insert(roomDirectory.RoomIds, roomId)
	end

	roomDirectory.PrimaryRoomId = PRIMARY_ROOM_ID
	roomDirectory.RoomId = PRIMARY_ROOM_ID
	profile.UpdatedAt = now

	RoomPersistence.QueueSave(player)

	return true, "Room created.", deepCopy(roomRecord)
end

local function waitForProfileSaveSlot(player, timeoutSeconds)
	local timeoutAt = os.clock() + (timeoutSeconds or 6)

	while saveRunning[player] and os.clock() < timeoutAt do
		task.wait(0.1)
	end

	return saveRunning[player] ~= true
end

local function normalizeRequiredRoomId(roomId)
	if typeof(roomId) ~= "string" then
		return nil
	end

	local trimmedRoomId = trimString(roomId)

	if trimmedRoomId == "" then
		return nil
	end

	return normalizeRoomId(trimmedRoomId)
end

local function getActiveOwnedRoomName(player, roomId)
	local normalizedRoomId = normalizeRoomId(roomId)
	local numericUserId = player and tonumber(player.UserId)

	if not normalizedRoomId
		or not numericUserId
		or numericUserId ~= numericUserId
		or math.abs(numericUserId) >= math.huge
		or numericUserId ~= math.floor(numericUserId) then

		return nil
	end

	if normalizedRoomId == PRIMARY_ROOM_ID then
		return "Room_" .. tostring(math.floor(numericUserId))
	end

	return "Room_" .. tostring(math.floor(numericUserId)) .. "_" .. normalizedRoomId
end

local function getActiveOwnedRoom(player, roomId)
	local activeRooms = workspace:FindFirstChild("ActiveRooms")
	local activeRoomName = getActiveOwnedRoomName(player, roomId)

	if not activeRooms or not activeRoomName then
		return nil, activeRoomName
	end

	return activeRooms:FindFirstChild(activeRoomName), activeRoomName
end

local function playerOccupiesRoomModel(player, roomModel)
	if typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or typeof(roomModel) ~= "Instance"
		or not roomModel:IsA("Model") then

		return false
	end

	if player:GetAttribute("CurrentRoomName") == roomModel.Name then
		return true
	end

	if player:GetAttribute("CurrentRoomType") ~= "PlayerRoom" then
		return false
	end

	local ownerUserId = roomModel:GetAttribute("OwnerUserId")

	return player:GetAttribute("CurrentRoomId") == roomModel:GetAttribute("RoomId")
		and typeof(ownerUserId) == "number"
		and player:GetAttribute("CurrentRoomOwnerUserId") == ownerUserId
end

local function getRoomModelOccupantCount(roomModel)
	local occupantCount = 0

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if playerOccupiesRoomModel(otherPlayer, roomModel) then
			occupantCount += 1
		end
	end

	return occupantCount
end

local function clearDeletedRoomContextAttributes(roomModel)
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if playerOccupiesRoomModel(otherPlayer, roomModel) then
			otherPlayer:SetAttribute("CurrentRoomName", nil)
			otherPlayer:SetAttribute("CurrentRoomId", nil)
			otherPlayer:SetAttribute("CurrentRoomOwnerUserId", nil)
			otherPlayer:SetAttribute("CurrentRoomType", nil)
		end
	end
end

local function isInventoryAcceptedFurnitureTemplateId(templateId)
	if not isValidTemplateId(templateId) then
		return false
	end

	local furnitureTemplates = ReplicatedStorage:FindFirstChild("FurnitureTemplates")

	if furnitureTemplates then
		local template = furnitureTemplates:FindFirstChild(templateId)

		if template and template:IsA("Model") then
			return true
		end
	end

	-- AddInventoryItem is the existing source of truth for inventory keys.
	return isValidTemplateId(templateId)
end

local function buildOwnedRoomFurnitureReturnAudit(roomRecord)
	local roomState = roomRecord and roomRecord.RoomState
	local furnitureRecords = typeof(roomState) == "table" and roomState.Furniture or nil
	local groupedReturnsByKey = {}
	local returnedCount = 0
	local audit = {}

	if typeof(furnitureRecords) ~= "table" then
		return true, nil, {}, 0, audit
	end

	for index, furnitureRecord in ipairs(furnitureRecords) do
		local auditEntry = {
			Index = index,
		}

		if typeof(furnitureRecord) ~= "table" then
			auditEntry.InvalidReason = "Invalid furniture record."
			table.insert(audit, auditEntry)
			return false, "Room contains furniture that cannot be returned to inventory.", nil, nil, audit
		end

		auditEntry.Id = furnitureRecord.Id
		auditEntry.Name = furnitureRecord.Name
		auditEntry.TemplateId = furnitureRecord.TemplateId

		if not isInventoryAcceptedFurnitureTemplateId(furnitureRecord.TemplateId) then
			auditEntry.InvalidReason = "Invalid TemplateId."
			table.insert(audit, auditEntry)
			return false, "Room contains furniture that cannot be returned to inventory.", nil, nil, audit
		end

		if furnitureRecord.Tradable ~= nil and typeof(furnitureRecord.Tradable) ~= "boolean" then
			auditEntry.InvalidReason = "Invalid Tradable flag."
			table.insert(audit, auditEntry)
			return false, "Room contains furniture that cannot be returned to inventory.", nil, nil, audit
		end

		if furnitureRecord.Sellable ~= nil and typeof(furnitureRecord.Sellable) ~= "boolean" then
			auditEntry.InvalidReason = "Invalid Sellable flag."
			table.insert(audit, auditEntry)
			return false, "Room contains furniture that cannot be returned to inventory.", nil, nil, audit
		end

		local returnedItem = {
			TemplateId = furnitureRecord.TemplateId,
			Tradable = furnitureRecord.Tradable == true,
			Sellable = furnitureRecord.Sellable == true,
		}

		local groupKey = table.concat({
			returnedItem.TemplateId,
			tostring(returnedItem.Tradable),
			tostring(returnedItem.Sellable),
		}, "|")
		local groupedReturn = groupedReturnsByKey[groupKey]

		if not groupedReturn then
			groupedReturn = {
				TemplateId = returnedItem.TemplateId,
				Quantity = 0,
				Tradable = returnedItem.Tradable,
				Sellable = returnedItem.Sellable,
			}
			groupedReturnsByKey[groupKey] = groupedReturn
		end

		groupedReturn.Quantity += 1
		returnedCount += 1
		auditEntry.ReturnedAs = deepCopy(groupedReturn)
		table.insert(audit, auditEntry)
	end

	local returnedItems = {}

	for _, returnedItem in pairs(groupedReturnsByKey) do
		table.insert(returnedItems, returnedItem)
	end

	table.sort(returnedItems, function(a, b)
		if a.TemplateId ~= b.TemplateId then
			return tostring(a.TemplateId) < tostring(b.TemplateId)
		end

		if a.Tradable ~= b.Tradable then
			return a.Tradable == false
		end

		return a.Sellable == false and b.Sellable == true
	end)

	return true, nil, returnedItems, returnedCount, audit
end

local function createDeleteOwnedRoomRollbackSnapshot(profile)
	return {
		Rooms = deepCopy(profile.Rooms),
		RoomDirectory = deepCopy(profile.RoomDirectory),
		Inventory = deepCopy(profile.Inventory),
		InventoryDetails = deepCopy(profile.InventoryDetails),
		InventoryUntradable = deepCopy(profile.InventoryUntradable),
		InventoryUnsellable = deepCopy(profile.InventoryUnsellable),
		FavouriteRooms = deepCopy(profile.FavouriteRooms),
		Favourites = deepCopy(profile.Favourites),
		UpdatedAt = profile.UpdatedAt,
	}
end

local function restoreDeleteOwnedRoomRollbackSnapshot(profile, snapshot)
	if typeof(profile) ~= "table" or typeof(snapshot) ~= "table" then
		return
	end

	profile.Rooms = deepCopy(snapshot.Rooms)
	profile.RoomDirectory = deepCopy(snapshot.RoomDirectory)
	profile.Inventory = deepCopy(snapshot.Inventory)
	profile.InventoryDetails = deepCopy(snapshot.InventoryDetails)
	profile.InventoryUntradable = deepCopy(snapshot.InventoryUntradable)
	profile.InventoryUnsellable = deepCopy(snapshot.InventoryUnsellable)
	profile.FavouriteRooms = deepCopy(snapshot.FavouriteRooms)
	profile.Favourites = deepCopy(snapshot.Favourites)
	profile.UpdatedAt = snapshot.UpdatedAt

	ensureInventory(profile)
	ensureFavouriteRooms(profile)
	ensureRoomsSchema(profile)
end

function RoomPersistence.DeleteOwnedRoom(player, roomId, options)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "Invalid player.", nil
	end

	local profile = RoomPersistence.GetProfile(player)

	if not profile then
		local loadedProfile, loaded = RoomPersistence.LoadProfile(player)

		if not loaded or not loadedProfile then
			return false, "Profile is not loaded.", nil
		end

		profile = loadedProfile
	end

	ensureRoomsSchema(profile)

	local normalizedRoomId = normalizeRequiredRoomId(roomId)

	if not normalizedRoomId then
		return false, "Invalid room id.", nil
	end

	local roomRecord = profile.Rooms and profile.Rooms[normalizedRoomId]

	if typeof(roomRecord) ~= "table" then
		return false, "Room not found.", nil
	end

	if normalizedRoomId == PRIMARY_ROOM_ID or roomRecord.IsPrimary == true then
		return false, "Primary room cannot be deleted.", nil
	end

	local deleteOptions = typeof(options) == "table" and options or {}

	if deleteOptions.RequireDisplayNameConfirmation ~= false
		and deleteOptions.ConfirmDisplayName ~= roomRecord.DisplayName then

		return false, "Room name confirmation does not match.", nil
	end

	local activeRoom = getActiveOwnedRoom(player, normalizedRoomId)
	local staleActiveRoom = nil

	if activeRoom then
		if not activeRoom:IsA("Model") or getRoomModelOccupantCount(activeRoom) > 0 then
			return false, "Leave this room before deleting it.", {
				RoomId = normalizedRoomId,
				DisplayName = roomRecord.DisplayName,
				Rooms = RoomPersistence.GetOwnedRoomsSnapshot(player),
			}
		end

		local captureOk, capturedRoomState = pcall(function()
			return RoomPersistence.CaptureRoomState(player, activeRoom)
		end)

		if not captureOk or typeof(capturedRoomState) ~= "table" then
			return false, "Room could not be prepared for deletion.", {
				RoomId = normalizedRoomId,
				DisplayName = roomRecord.DisplayName,
				Rooms = RoomPersistence.GetOwnedRoomsSnapshot(player),
			}
		end

		staleActiveRoom = activeRoom
		roomRecord = profile.Rooms and profile.Rooms[normalizedRoomId]

		if typeof(roomRecord) ~= "table" then
			return false, "Room not found.", nil
		end
	end

	local auditOk, auditMessage, returnedItems, returnedCount, audit =
		buildOwnedRoomFurnitureReturnAudit(roomRecord)

	if not auditOk then
		return false, auditMessage, {
			RoomId = normalizedRoomId,
			DisplayName = roomRecord.DisplayName,
			Audit = audit,
			Rooms = RoomPersistence.GetOwnedRoomsSnapshot(player),
		}
	end

	local oldDisplayName = roomRecord.DisplayName
	local rollbackSnapshot = createDeleteOwnedRoomRollbackSnapshot(profile)

	for _, returnedItem in ipairs(returnedItems) do
		local addOk, addMessage = RoomPersistence.AddInventoryItem(
			player,
			returnedItem.TemplateId,
			returnedItem.Quantity,
			{
				Tradable = returnedItem.Tradable,
				Sellable = returnedItem.Sellable,
			}
		)

		if not addOk then
			restoreDeleteOwnedRoomRollbackSnapshot(profile, rollbackSnapshot)
			saveScheduled[player] = nil

			return false, "Could not return furniture to inventory: " .. tostring(addMessage), {
				RoomId = normalizedRoomId,
				DisplayName = oldDisplayName,
				ReturnedItems = deepCopy(returnedItems),
				ReturnedCount = returnedCount,
				Rooms = RoomPersistence.GetOwnedRoomsSnapshot(player),
			}
		end
	end

	profile.Rooms[normalizedRoomId] = nil

	local roomDirectory = ensureRoomDirectory(profile)
	removeRoomIdFromDirectory(roomDirectory, normalizedRoomId)
	roomDirectory.RoomIds = normalizeRoomIdsForExistingRooms(roomDirectory.RoomIds, profile.Rooms)
	roomDirectory.PrimaryRoomId = PRIMARY_ROOM_ID
	roomDirectory.RoomId = PRIMARY_ROOM_ID

	if normalizeRoomId(roomDirectory.SelectedRoomId) == normalizedRoomId
		or not profile.Rooms[roomDirectory.SelectedRoomId] then

		roomDirectory.SelectedRoomId = PRIMARY_ROOM_ID
	end

	profile.RoomDirectory = roomDirectory

	local favouriteRooms = ensureFavouriteRooms(profile)
	local ownerFavouriteKey = "PlayerRoom:" .. tostring(player.UserId) .. ":" .. normalizedRoomId
	favouriteRooms[ownerFavouriteKey] = nil

	profile.UpdatedAt = os.time()

	if not waitForProfileSaveSlot(player, 6) then
		restoreDeleteOwnedRoomRollbackSnapshot(profile, rollbackSnapshot)
		saveScheduled[player] = nil

		return false, "Could not delete room because a profile save is still running.", {
			RoomId = normalizedRoomId,
			DisplayName = oldDisplayName,
			ReturnedItems = deepCopy(returnedItems),
			ReturnedCount = returnedCount,
			Rooms = RoomPersistence.GetOwnedRoomsSnapshot(player),
		}
	end

	saveScheduled[player] = nil

	local saveOk, saveMessage = RoomPersistence.SavePlayer(player)

	if not saveOk then
		restoreDeleteOwnedRoomRollbackSnapshot(profile, rollbackSnapshot)
		saveScheduled[player] = nil

		return false, "Could not save deleted room: " .. tostring(saveMessage), {
			RoomId = normalizedRoomId,
			DisplayName = oldDisplayName,
			ReturnedItems = deepCopy(returnedItems),
			ReturnedCount = returnedCount,
			Rooms = RoomPersistence.GetOwnedRoomsSnapshot(player),
		}
	end

	if staleActiveRoom and staleActiveRoom.Parent then
		clearDeletedRoomContextAttributes(staleActiveRoom)
		staleActiveRoom:Destroy()
	end

	return true, "Room deleted.", {
		RoomId = normalizedRoomId,
		DisplayName = oldDisplayName,
		ReturnedItems = deepCopy(returnedItems),
		ReturnedCount = returnedCount,
		Rooms = RoomPersistence.GetOwnedRoomsSnapshot(player),
	}
end

function RoomPersistence.DeleteOwnedRoomForDebug(player, roomId)
	local profile = RoomPersistence.GetProfile(player)

	if not profile then
		local loadedProfile, loaded = RoomPersistence.LoadProfile(player)

		if not loaded or not loadedProfile then
			return false, "Profile is not loaded.", {}, false
		end

		profile = loadedProfile
	end

	local normalizedRoomId = normalizeRoomId(roomId)

	if not normalizedRoomId then
		return false, "Invalid room id.", RoomPersistence.GetOwnedRoomsSnapshot(player), false
	end

	if normalizedRoomId == PRIMARY_ROOM_ID then
		return false, "Primary room cannot be deleted.", RoomPersistence.GetOwnedRoomsSnapshot(player), false
	end

	ensureRoomsSchema(profile)

	if typeof(profile.Rooms) ~= "table" or typeof(profile.Rooms[normalizedRoomId]) ~= "table" then
		removeRoomIdFromDirectory(ensureRoomDirectory(profile), normalizedRoomId)
		ensureRoomsSchema(profile)
		return false, "Room not found.", RoomPersistence.GetOwnedRoomsSnapshot(player), false
	end

	profile.Rooms[normalizedRoomId] = nil

	local roomDirectory = ensureRoomDirectory(profile)
	removeRoomIdFromDirectory(roomDirectory, normalizedRoomId)
	roomDirectory.RoomIds = normalizeRoomIdsForExistingRooms(roomDirectory.RoomIds, profile.Rooms)
	roomDirectory.PrimaryRoomId = PRIMARY_ROOM_ID
	roomDirectory.RoomId = PRIMARY_ROOM_ID

	if normalizeRoomId(roomDirectory.SelectedRoomId) == normalizedRoomId
		or not profile.Rooms[roomDirectory.SelectedRoomId] then

		roomDirectory.SelectedRoomId = PRIMARY_ROOM_ID
	end

	profile.RoomDirectory = roomDirectory
	profile.UpdatedAt = os.time()

	if DEBUG_ROOM_DELETE_TRACE then
		warn("RoomPersistence: DeleteOwnedRoomForDebug deleted room", player.Name, normalizedRoomId)
	end

	if not waitForProfileSaveSlot(player, 6) then
		return false, "Room deleted in memory, but a profile save is still running.", RoomPersistence.GetOwnedRoomsSnapshot(player), false
	end

	saveScheduled[player] = nil

	local saveOk, saveMessage = RoomPersistence.SavePlayer(player)

	if not saveOk then
		if DEBUG_ROOM_DELETE_TRACE then
			warn("RoomPersistence: DeleteOwnedRoomForDebug save failed", player.Name, normalizedRoomId, saveMessage)
		end

		return false, "Room deleted in memory, but save failed: " .. tostring(saveMessage), RoomPersistence.GetOwnedRoomsSnapshot(player), false
	end

	if DEBUG_ROOM_DELETE_TRACE then
		warn("RoomPersistence: DeleteOwnedRoomForDebug save succeeded", player.Name, normalizedRoomId)
	end

	return true, "Room deleted.", RoomPersistence.GetOwnedRoomsSnapshot(player), true
end

function RoomPersistence.HasSeenHotelIntro(player)
	local profile = profilesByPlayer[player]

	if not profile then
		return false
	end

	return profile.HasSeenHotelIntro == true
end

function RoomPersistence.MarkHotelIntroSeen(player)
	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded."
	end

	if profile.HasSeenHotelIntro == true then
		return true, "Hotel intro already seen."
	end

	profile.HasSeenHotelIntro = true
	profile.UpdatedAt = os.time()

	RoomPersistence.QueueSave(player)

	return true, "Hotel intro marked seen."
end

function RoomPersistence.GetMarketplaceListingsSnapshot(player)
	local profile = profilesByPlayer[player]

	if not profile then
		return {}
	end

	return deepCopy(ensureMarketplaceListings(profile))
end

function RoomPersistence.GetMarketplaceListing(player, listingId)
	if typeof(listingId) ~= "string" or listingId == "" then
		return nil
	end

	local profile = profilesByPlayer[player]

	if not profile then
		return nil
	end

	local listings = ensureMarketplaceListings(profile)
	local listingRecord = listings[listingId]

	if not listingRecord then
		return nil
	end

	return deepCopy(listingRecord)
end

function RoomPersistence.AddMarketplaceListing(player, listingRecord)
	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded."
	end

	if not isValidListingRecord(listingRecord) then
		return false, "Invalid marketplace listing."
	end

	local listings = ensureMarketplaceListings(profile)
	local listingId = listingRecord.ListingId

	if listings[listingId] ~= nil then
		return false, "Marketplace listing already exists."
	end

	listings[listingId] = copyMarketplaceListing(listingRecord)
	profile.UpdatedAt = os.time()

	RoomPersistence.QueueSave(player)

	return true, "Marketplace listing added."
end

function RoomPersistence.UpdateMarketplaceListing(player, listingId, updates)
	if typeof(listingId) ~= "string" or listingId == "" then
		return false, "Invalid marketplace listing."
	end

	if typeof(updates) ~= "table" then
		return false, "Invalid marketplace listing updates."
	end

	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded."
	end

	local listings = ensureMarketplaceListings(profile)
	local listingRecord = listings[listingId]

	if not listingRecord then
		return false, "Marketplace listing not found."
	end

	if updates.Status ~= nil then
		if typeof(updates.Status) ~= "string" or updates.Status == "" then
			return false, "Invalid marketplace listing status."
		end

		listingRecord.Status = updates.Status
	end

	if updates.ExpiresAt ~= nil then
		if updates.ExpiresAt ~= false
			and (typeof(updates.ExpiresAt) ~= "number"
				or updates.ExpiresAt ~= updates.ExpiresAt
				or updates.ExpiresAt < 0
				or updates.ExpiresAt >= math.huge) then

			return false, "Invalid marketplace listing expiration."
		end

		if updates.ExpiresAt == false then
			listingRecord.ExpiresAt = nil
		else
			listingRecord.ExpiresAt = math.floor(updates.ExpiresAt)
		end
	end

	if updates.SoldAt ~= nil then
		if updates.SoldAt ~= false
			and (typeof(updates.SoldAt) ~= "number"
				or updates.SoldAt ~= updates.SoldAt
				or updates.SoldAt < 0
				or updates.SoldAt >= math.huge) then

			return false, "Invalid marketplace listing sale time."
		end

		if updates.SoldAt == false then
			listingRecord.SoldAt = nil
		else
			listingRecord.SoldAt = math.floor(updates.SoldAt)
		end
	end

	if updates.SoldUnitPriceCoins ~= nil then
		if updates.SoldUnitPriceCoins ~= false and not isPositiveInteger(updates.SoldUnitPriceCoins) then
			return false, "Invalid marketplace sold unit price."
		end

		if updates.SoldUnitPriceCoins == false then
			listingRecord.SoldUnitPriceCoins = nil
		else
			listingRecord.SoldUnitPriceCoins = math.floor(updates.SoldUnitPriceCoins)
		end
	end

	if updates.SoldTotalCoins ~= nil then
		if updates.SoldTotalCoins ~= false and not isPositiveInteger(updates.SoldTotalCoins) then
			return false, "Invalid marketplace sold total."
		end

		if updates.SoldTotalCoins == false then
			listingRecord.SoldTotalCoins = nil
		else
			listingRecord.SoldTotalCoins = math.floor(updates.SoldTotalCoins)
		end
	end

	if updates.BuyerUserId ~= nil then
		if updates.BuyerUserId ~= false and not isFiniteInteger(updates.BuyerUserId) then
			return false, "Invalid marketplace listing buyer."
		end

		if updates.BuyerUserId == false then
			listingRecord.BuyerUserId = nil
		else
			listingRecord.BuyerUserId = math.floor(updates.BuyerUserId)
		end
	end

	if updates.TransactionId ~= nil then
		if updates.TransactionId ~= false
			and (typeof(updates.TransactionId) ~= "string" or updates.TransactionId == "") then

			return false, "Invalid marketplace transaction."
		end

		if updates.TransactionId == false then
			listingRecord.TransactionId = nil
		else
			listingRecord.TransactionId = updates.TransactionId
		end
	end

	if updates.Escrowed ~= nil then
		if typeof(updates.Escrowed) ~= "boolean" then
			return false, "Invalid marketplace escrow state."
		end

		listingRecord.Escrowed = updates.Escrowed
	end

	if updates.ReturnTradable ~= nil then
		if typeof(updates.ReturnTradable) ~= "boolean" then
			return false, "Invalid marketplace tradable return state."
		end

		listingRecord.ReturnTradable = updates.ReturnTradable
	end

	if updates.ReturnSellable ~= nil then
		if typeof(updates.ReturnSellable) ~= "boolean" then
			return false, "Invalid marketplace sellable return state."
		end

		listingRecord.ReturnSellable = updates.ReturnSellable
	end

	if updates.LegacyNoEscrow ~= nil then
		if typeof(updates.LegacyNoEscrow) ~= "boolean" then
			return false, "Invalid marketplace legacy escrow state."
		end

		listingRecord.LegacyNoEscrow = updates.LegacyNoEscrow
	end

	if updates.ProceedsClaimed ~= nil then
		if typeof(updates.ProceedsClaimed) ~= "boolean" then
			return false, "Invalid marketplace claim state."
		end

		listingRecord.ProceedsClaimed = updates.ProceedsClaimed
	end

	if updates.ClaimableCoins ~= nil then
		if updates.ClaimableCoins ~= false and not isPositiveInteger(updates.ClaimableCoins) then
			return false, "Invalid marketplace claim amount."
		end

		if updates.ClaimableCoins == false then
			listingRecord.ClaimableCoins = nil
		else
			listingRecord.ClaimableCoins = math.floor(updates.ClaimableCoins)
		end
	end

	if updates.ClaimedAt ~= nil then
		if updates.ClaimedAt ~= false
			and (typeof(updates.ClaimedAt) ~= "number"
				or updates.ClaimedAt ~= updates.ClaimedAt
				or updates.ClaimedAt < 0
				or updates.ClaimedAt >= math.huge) then

			return false, "Invalid marketplace claim time."
		end

		if updates.ClaimedAt == false then
			listingRecord.ClaimedAt = nil
		else
			listingRecord.ClaimedAt = math.floor(updates.ClaimedAt)
		end
	end

	listingRecord.UpdatedAt = os.time()
	profile.UpdatedAt = os.time()

	RoomPersistence.QueueSave(player)

	return true, "Marketplace listing updated.", deepCopy(listingRecord)
end

function RoomPersistence.CancelMarketplaceListingWithEscrowReturn(player, listingId, sellerUserId)
	if typeof(listingId) ~= "string" or listingId == "" then
		return false, "Invalid marketplace listing.", nil, nil
	end

	if not isFiniteInteger(sellerUserId) then
		return false, "Invalid marketplace seller.", nil, nil
	end

	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded.", nil, nil
	end

	local listings = ensureMarketplaceListings(profile)
	local listingRecord = listings[listingId]

	if not listingRecord then
		return false, "Marketplace listing not found.", nil, nil
	end

	if listingRecord.SellerUserId ~= sellerUserId then
		return false, "Only the seller can cancel this listing.", nil, nil
	end

	if listingRecord.Status ~= "Active" then
		return false, "This listing is no longer active.", nil, nil
	end

	if listingRecord.Escrowed ~= true then
		return false, "Marketplace listing is not escrowed.", nil, nil
	end

	local returned, returnMessage, _, inventoryDetails =
		RoomPersistence.ReturnMarketplaceListableInventoryItem(
			player,
			listingRecord.TemplateId,
			listingRecord.Quantity,
			{
				ReturnTradable = listingRecord.ReturnTradable,
				ReturnSellable = listingRecord.ReturnSellable,
			}
		)

	if not returned then
		return false, returnMessage or "Could not return listed item.", nil, inventoryDetails
	end

	local now = os.time()
	listingRecord.Status = "Cancelled"
	listingRecord.Escrowed = false
	listingRecord.UpdatedAt = now
	profile.UpdatedAt = now

	RoomPersistence.QueueSave(player)

	return true, "Marketplace listing cancelled.", deepCopy(listingRecord), inventoryDetails
end

function RoomPersistence.CancelLegacyMarketplaceListingWithoutEscrowReturn(player, listingId, sellerUserId)
	if typeof(listingId) ~= "string" or listingId == "" then
		return false, "Invalid marketplace listing.", nil
	end

	if not isFiniteInteger(sellerUserId) then
		return false, "Invalid marketplace seller.", nil
	end

	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded.", nil
	end

	local listings = ensureMarketplaceListings(profile)
	local listingRecord = listings[listingId]

	if not listingRecord then
		return false, "Marketplace listing not found.", nil
	end

	if listingRecord.SellerUserId ~= sellerUserId then
		return false, "Only the seller can cancel this listing.", nil
	end

	if listingRecord.Status ~= "Active" then
		return false, "This listing is no longer active.", nil
	end

	if listingRecord.Escrowed == true then
		return false, "Marketplace listing is escrowed.", nil
	end

	local now = os.time()
	listingRecord.Status = "Cancelled"
	listingRecord.Escrowed = false
	listingRecord.LegacyNoEscrow = true
	listingRecord.UpdatedAt = now
	profile.UpdatedAt = now

	RoomPersistence.QueueSave(player)

	return true, "Legacy marketplace listing cancelled.", deepCopy(listingRecord)
end

function RoomPersistence.GetRoomDirectorySnapshot(player)
	local profile = profilesByPlayer[player]

	if not profile then
		return nil
	end

	ensureRoomsSchema(profile)

	return deepCopy(ensureRoomDirectory(profile))
end

function RoomPersistence.UpdateRoomDirectory(player, updates)
	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded."
	end

	if typeof(updates) ~= "table" then
		return false, "Invalid room settings."
	end

	local roomDirectory = ensureRoomDirectory(profile)

	if updates.DisplayName ~= nil then
		if typeof(updates.DisplayName) ~= "string" then
			return false, "Room name must be text."
		end

		local displayName = trimString(updates.DisplayName)

		if #displayName > 140 then
			return false, "Room name is too long."
		end

		roomDirectory.DisplayName = displayName ~= "" and displayName or nil
	end

	if updates.Description ~= nil then
		if typeof(updates.Description) ~= "string" then
			return false, "Description must be text."
		end

		local description = trimString(updates.Description)

		if #description > 160 then
			return false, "Description is too long."
		end

		roomDirectory.Description = description
	end

	if updates.Category ~= nil then
		if typeof(updates.Category) ~= "string" or not ROOM_DIRECTORY_CATEGORIES[updates.Category] then
			return false, "Invalid room category."
		end

		roomDirectory.Category = updates.Category
	end

	if updates.IsPublic ~= nil then
		if typeof(updates.IsPublic) ~= "boolean" then
			return false, "Public setting must be true or false."
		end

		roomDirectory.IsPublic = updates.IsPublic
	end

	-- MaxOccupancy is intentionally not client-editable yet.
	roomDirectory.MaxOccupancy = 25
	roomDirectory.RoomId = PRIMARY_ROOM_ID
	roomDirectory.Tags = normalizeRoomTags(roomDirectory.Tags)
	ensureRoomsSchema(profile)

	profile.UpdatedAt = os.time()
	RoomPersistence.QueueSave(player)

	return true, "Room settings saved.", deepCopy(roomDirectory)
end

function RoomPersistence.GetFavouriteRoomsSnapshot(player)
	local profile = profilesByPlayer[player]

	if not profile then
		return {}
	end

	return deepCopy(ensureFavouriteRooms(profile))
end

function RoomPersistence.IsRoomFavourite(player, roomKey)
	if not isValidRoomFavouriteKey(roomKey) then
		return false
	end

	local profile = profilesByPlayer[player]

	if not profile then
		return false
	end

	return ensureFavouriteRooms(profile)[roomKey] == true
end

function RoomPersistence.SetRoomFavourite(player, roomKey, isFavourite)
	if not isValidRoomFavouriteKey(roomKey) then
		return false, "Invalid room favourite.", false
	end

	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded.", false
	end

	local favouriteRooms = ensureFavouriteRooms(profile)
	local newFavouriteState = isFavourite == true

	if newFavouriteState then
		favouriteRooms[roomKey] = true
	else
		favouriteRooms[roomKey] = nil
	end

	profile.UpdatedAt = os.time()
	RoomPersistence.QueueSave(player)

	return true,
		newFavouriteState and "Room added to favourites." or "Room removed from favourites.",
		newFavouriteState
end

function RoomPersistence.ToggleRoomFavourite(player, roomKey)
	if not isValidRoomFavouriteKey(roomKey) then
		return false, "Invalid room favourite.", false
	end

	local currentlyFavourite = RoomPersistence.IsRoomFavourite(player, roomKey)

	return RoomPersistence.SetRoomFavourite(player, roomKey, not currentlyFavourite)
end

local function getLoadedProfileByUserId(userId)
	local normalizedUserId = normalizePermissionUserId(userId)

	if not normalizedUserId then
		return nil, nil
	end

	local numericUserId = tonumber(normalizedUserId)

	for player, profile in pairs(profilesByPlayer) do
		if player.UserId == numericUserId then
			return ensureRoomsSchema(profile), player
		end
	end

	return nil, nil
end

local function getLoadedProfileForPlayer(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end

	local profile = profilesByPlayer[player]

	if not profile then
		return nil
	end

	return ensureRoomsSchema(profile)
end

local function savePermissionMutation(ownerPlayer, profile)
	local now = os.time()
	local roomPermissions = ensureRoomPermissions(profile)
	local primaryRoom = getMutableRoomRecord(profile, PRIMARY_ROOM_ID)

	if primaryRoom then
		primaryRoom.Permissions = deepCopy(roomPermissions)
		primaryRoom.UpdatedAt = now
	end

	profile.UpdatedAt = now
	RoomPersistence.QueueSave(ownerPlayer)
end

local function getRoomEditorsSnapshot(roomRecord, ownerUserId)
	local editors = {}

	if typeof(roomRecord) ~= "table" then
		return editors
	end

	roomRecord.Permissions = normalizeRoomPermissions(roomRecord.Permissions)

	for userIdKey, isAllowed in pairs(roomRecord.Permissions.Editors) do
		if isAllowed == true then
			local userId = tonumber(userIdKey)

			if userId and userId ~= 0 and userId ~= ownerUserId then
				local editorPlayer = nil

				for _, candidatePlayer in ipairs(Players:GetPlayers()) do
					if candidatePlayer.UserId == userId then
						editorPlayer = candidatePlayer
						break
					end
				end

				local entry = {
					UserId = userId,
					Allowed = true,
				}

				if editorPlayer then
					entry.Name = editorPlayer.Name
					entry.DisplayName = editorPlayer.DisplayName
				end

				table.insert(editors, entry)
			end
		end
	end

	table.sort(editors, function(a, b)
		return a.UserId < b.UserId
	end)

	return editors
end

local function getLoadedProfileFromOwner(ownerPlayerOrUserId)
	if typeof(ownerPlayerOrUserId) == "Instance" and ownerPlayerOrUserId:IsA("Player") then
		return getLoadedProfileForPlayer(ownerPlayerOrUserId), ownerPlayerOrUserId
	end

	return getLoadedProfileByUserId(ownerPlayerOrUserId)
end

function RoomPersistence.GetRoomPermissionsSnapshot(player)
	local profile = profilesByPlayer[player]

	if not profile then
		return nil
	end

	return deepCopy(ensureRoomPermissions(profile))
end

function RoomPersistence.GetRoomPermissionsSnapshotByUserId(ownerUserId)
	local profile = getLoadedProfileByUserId(ownerUserId)

	if not profile then
		return nil
	end

	return deepCopy(ensureRoomPermissions(profile))
end

function RoomPersistence.GetRoomEditorsForRoom(player, roomId)
	local profile = getLoadedProfileForPlayer(player)

	if not profile then
		return {}
	end

	ensureRoomsSchema(profile)

	local roomRecord = getMutableRoomRecord(profile, roomId)

	if not roomRecord then
		return {}
	end

	return deepCopy(getRoomEditorsSnapshot(roomRecord, player.UserId))
end

function RoomPersistence.SetRoomEditorPermissionForRoom(ownerPlayer, roomId, targetUserId, isAllowed)
	local targetUserIdKey = normalizePermissionUserId(targetUserId)

	if not targetUserIdKey then
		return false, "Invalid target user."
	end

	local profile = getLoadedProfileForPlayer(ownerPlayer)

	if not profile then
		return false, "Owner profile is not loaded."
	end

	if tonumber(targetUserIdKey) == ownerPlayer.UserId then
		return false, "You are already the room owner."
	end

	ensureRoomsSchema(profile)

	local roomRecord, normalizedRoomId = getMutableRoomRecord(profile, roomId)

	if not roomRecord then
		return false, "Room not found."
	end

	roomRecord.Permissions = normalizeRoomPermissions(roomRecord.Permissions)

	if isAllowed == true then
		roomRecord.Permissions.Editors[targetUserIdKey] = true
	else
		roomRecord.Permissions.Editors[targetUserIdKey] = nil
	end

	local now = os.time()
	roomRecord.UpdatedAt = now
	profile.UpdatedAt = now

	if normalizedRoomId == PRIMARY_ROOM_ID then
		local legacyRoomPermissions = ensureRoomPermissions(profile)
		legacyRoomPermissions.Editors = deepCopy(roomRecord.Permissions.Editors)
		profile.RoomPermissions = legacyRoomPermissions
	end

	RoomPersistence.QueueSave(ownerPlayer)

	return true, isAllowed == true and "Room editor permission granted." or "Room editor permission removed."
end

function RoomPersistence.IsRoomEditorForRoom(ownerPlayerOrUserId, roomId, targetUserId)
	local targetUserIdKey = normalizePermissionUserId(targetUserId)

	if not targetUserIdKey then
		return false
	end

	local profile = getLoadedProfileFromOwner(ownerPlayerOrUserId)

	if not profile then
		return false
	end

	ensureRoomsSchema(profile)

	local roomRecord, normalizedRoomId = getMutableRoomRecord(profile, roomId)

	if not roomRecord then
		return false
	end

	if normalizedRoomId == PRIMARY_ROOM_ID and typeof(roomRecord.Permissions) ~= "table" then
		return ensureRoomPermissions(profile).Editors[targetUserIdKey] == true
	end

	roomRecord.Permissions = normalizeRoomPermissions(roomRecord.Permissions)

	return roomRecord.Permissions.Editors[targetUserIdKey] == true
end

function RoomPersistence.SetRoomEditorPermission(ownerPlayer, targetUserId, isAllowed)
	return RoomPersistence.SetRoomEditorPermissionForRoom(ownerPlayer, PRIMARY_ROOM_ID, targetUserId, isAllowed)
end

function RoomPersistence.IsRoomEditor(ownerPlayer, targetUserId)
	return RoomPersistence.IsRoomEditorForRoom(ownerPlayer, PRIMARY_ROOM_ID, targetUserId)
end

function RoomPersistence.SetRoomActionPermission(ownerPlayer, actionName, targetUserId, isAllowed)
	local normalizedActionName = normalizePermissionActionName(actionName)
	local targetUserIdKey = normalizePermissionUserId(targetUserId)

	if not normalizedActionName then
		return false, "Invalid action name."
	end

	if not targetUserIdKey then
		return false, "Invalid target user."
	end

	local profile = getLoadedProfileForPlayer(ownerPlayer)

	if not profile then
		return false, "Owner profile is not loaded."
	end

	local roomPermissions = ensureRoomPermissions(profile)

	if isAllowed == true then
		roomPermissions.RoomActions[normalizedActionName] =
			roomPermissions.RoomActions[normalizedActionName] or {}
		roomPermissions.RoomActions[normalizedActionName][targetUserIdKey] = true
	else
		local actionPermissions = roomPermissions.RoomActions[normalizedActionName]

		if actionPermissions then
			actionPermissions[targetUserIdKey] = nil

			if not dictionaryHasEntries(actionPermissions) then
				roomPermissions.RoomActions[normalizedActionName] = nil
			end
		end
	end

	savePermissionMutation(ownerPlayer, profile)

	return true, isAllowed == true and "Room action permission granted." or "Room action permission removed."
end

function RoomPersistence.IsRoomActionAllowed(ownerPlayer, actionName, targetUserId)
	local normalizedActionName = normalizePermissionActionName(actionName)
	local targetUserIdKey = normalizePermissionUserId(targetUserId)

	if not normalizedActionName or not targetUserIdKey then
		return false
	end

	local profile = getLoadedProfileForPlayer(ownerPlayer)

	if not profile then
		return false
	end

	local roomPermissions = ensureRoomPermissions(profile)
	local actionPermissions = roomPermissions.RoomActions[normalizedActionName]

	return typeof(actionPermissions) == "table" and actionPermissions[targetUserIdKey] == true
end

function RoomPersistence.GetFurniturePermissionsForRoom(ownerPlayer, roomId, persistentId)
	local normalizedPersistentId = normalizePermissionPersistentId(persistentId)

	if not normalizedPersistentId then
		return {}
	end

	local profile = getLoadedProfileForPlayer(ownerPlayer)

	if not profile then
		return {}
	end

	ensureRoomsSchema(profile)

	local roomRecord, normalizedRoomId = getMutableRoomRecord(profile, roomId)

	if not roomRecord then
		return {}
	end

	roomRecord.Permissions = normalizeRoomPermissions(roomRecord.Permissions)

	if normalizedRoomId == PRIMARY_ROOM_ID then
		local legacyRoomPermissions = ensureRoomPermissions(profile)
		local primaryFurniturePermissions = roomRecord.Permissions.FurniturePermissions

		if not primaryFurniturePermissions[normalizedPersistentId]
			and typeof(legacyRoomPermissions.FurniturePermissions) == "table"
			and typeof(legacyRoomPermissions.FurniturePermissions[normalizedPersistentId]) == "table" then

			primaryFurniturePermissions[normalizedPersistentId] =
				deepCopy(legacyRoomPermissions.FurniturePermissions[normalizedPersistentId])
			roomRecord.Permissions.FurniturePermissions = primaryFurniturePermissions
		end
	end

	return deepCopy(roomRecord.Permissions.FurniturePermissions[normalizedPersistentId] or {})
end

function RoomPersistence.SetFurniturePermissionForRoom(ownerPlayer, roomId, persistentId, actionName, targetUserId, isAllowed)
	local normalizedPersistentId = normalizePermissionPersistentId(persistentId)
	local normalizedActionName = normalizePermissionActionName(actionName)
	local targetUserIdKey = normalizePermissionUserId(targetUserId)

	if not normalizedPersistentId then
		return false, "Invalid furniture id."
	end

	if not normalizedActionName then
		return false, "Invalid action name."
	end

	if not targetUserIdKey then
		return false, "Invalid target user."
	end

	local profile = getLoadedProfileForPlayer(ownerPlayer)

	if not profile then
		return false, "Owner profile is not loaded."
	end

	ensureRoomsSchema(profile)

	local roomRecord, normalizedRoomId = getMutableRoomRecord(profile, roomId)

	if not roomRecord then
		return false, "Room not found."
	end

	roomRecord.Permissions = normalizeRoomPermissions(roomRecord.Permissions)
	local furniturePermissionsById = roomRecord.Permissions.FurniturePermissions

	if normalizedRoomId == PRIMARY_ROOM_ID then
		local legacyRoomPermissions = ensureRoomPermissions(profile)

		if typeof(legacyRoomPermissions.FurniturePermissions) == "table" then
			for legacyPersistentId, legacyActionPermissions in pairs(legacyRoomPermissions.FurniturePermissions) do
				if typeof(legacyActionPermissions) == "table"
					and typeof(furniturePermissionsById[legacyPersistentId]) ~= "table" then

					furniturePermissionsById[legacyPersistentId] = deepCopy(legacyActionPermissions)
				end
			end
		end
	end

	if isAllowed == true then
		furniturePermissionsById[normalizedPersistentId] =
			furniturePermissionsById[normalizedPersistentId] or {}
		furniturePermissionsById[normalizedPersistentId][normalizedActionName] =
			furniturePermissionsById[normalizedPersistentId][normalizedActionName] or {}
		furniturePermissionsById[normalizedPersistentId][normalizedActionName][targetUserIdKey] = true
	else
		local furniturePermissions = furniturePermissionsById[normalizedPersistentId]
		local actionPermissions = furniturePermissions and furniturePermissions[normalizedActionName]

		if actionPermissions then
			actionPermissions[targetUserIdKey] = nil

			if not dictionaryHasEntries(actionPermissions) then
				furniturePermissions[normalizedActionName] = nil
			end

			if not dictionaryHasEntries(furniturePermissions) then
				furniturePermissionsById[normalizedPersistentId] = nil
			end
		end
	end

	roomRecord.Permissions.FurniturePermissions = furniturePermissionsById

	local now = os.time()
	roomRecord.UpdatedAt = now
	profile.UpdatedAt = now

	if normalizedRoomId == PRIMARY_ROOM_ID then
		local legacyRoomPermissions = ensureRoomPermissions(profile)
		legacyRoomPermissions.FurniturePermissions = deepCopy(roomRecord.Permissions.FurniturePermissions)
		profile.RoomPermissions = legacyRoomPermissions
	end

	RoomPersistence.QueueSave(ownerPlayer)

	return true, isAllowed == true and "Furniture permission granted." or "Furniture permission removed."
end

function RoomPersistence.IsFurnitureActionAllowedForRoom(ownerPlayerOrUserId, roomId, persistentId, actionName, targetUserId)
	local normalizedPersistentId = normalizePermissionPersistentId(persistentId)
	local normalizedActionName = normalizePermissionActionName(actionName)
	local targetUserIdKey = normalizePermissionUserId(targetUserId)

	if not normalizedPersistentId or not normalizedActionName or not targetUserIdKey then
		return false
	end

	local profile = getLoadedProfileFromOwner(ownerPlayerOrUserId)

	if not profile then
		return false
	end

	ensureRoomsSchema(profile)

	local roomRecord, normalizedRoomId = getMutableRoomRecord(profile, roomId)

	if not roomRecord then
		return false
	end

	roomRecord.Permissions = normalizeRoomPermissions(roomRecord.Permissions)

	if normalizedRoomId == PRIMARY_ROOM_ID then
		local legacyRoomPermissions = ensureRoomPermissions(profile)

		if not roomRecord.Permissions.FurniturePermissions[normalizedPersistentId]
			and typeof(legacyRoomPermissions.FurniturePermissions) == "table"
			and typeof(legacyRoomPermissions.FurniturePermissions[normalizedPersistentId]) == "table" then

			roomRecord.Permissions.FurniturePermissions[normalizedPersistentId] =
				deepCopy(legacyRoomPermissions.FurniturePermissions[normalizedPersistentId])
		end
	end

	local furniturePermissions = roomRecord.Permissions.FurniturePermissions[normalizedPersistentId]
	local actionPermissions = furniturePermissions and furniturePermissions[normalizedActionName]

	return typeof(actionPermissions) == "table" and actionPermissions[targetUserIdKey] == true
end

function RoomPersistence.SetFurniturePermission(ownerPlayer, persistentId, actionName, targetUserId, isAllowed)
	return RoomPersistence.SetFurniturePermissionForRoom(
		ownerPlayer,
		PRIMARY_ROOM_ID,
		persistentId,
		actionName,
		targetUserId,
		isAllowed
	)
end

function RoomPersistence.IsFurnitureActionAllowed(ownerPlayer, persistentId, actionName, targetUserId)
	return RoomPersistence.IsFurnitureActionAllowedForRoom(
		ownerPlayer,
		PRIMARY_ROOM_ID,
		persistentId,
		actionName,
		targetUserId
	)
end

function RoomPersistence.GetCurrency(player, currencyKey)
	if not isValidCurrencyKey(currencyKey) then
		return nil, "Invalid currency key."
	end

	local profile = profilesByPlayer[player]

	if not profile then
		return nil, "Profile is not loaded."
	end

	return getCurrencyBalance(profile, currencyKey)
end

function RoomPersistence.GetCurrenciesSnapshot(player)
	local profile = profilesByPlayer[player]

	if not profile then
		return {
			Coins = 0,
			Dollars = 0,
			Event = {},
		}
	end

	return deepCopy(ensureCurrencies(profile))
end

function RoomPersistence.AddCurrency(player, currencyKey, amount, reason)
	if not isValidCurrencyKey(currencyKey) then
		return false, "Invalid currency key.", nil
	end

	if not isPositiveInteger(amount) then
		return false, "Amount must be a positive integer.", nil
	end

	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded.", nil
	end

	local newBalance = getCurrencyBalance(profile, currencyKey) + amount
	setCurrencyBalance(profile, currencyKey, newBalance)
	profile.UpdatedAt = os.time()

	RoomPersistence.QueueSave(player)

	return true, "Currency added.", newBalance
end

function RoomPersistence.RemoveCurrency(player, currencyKey, amount, reason)
	if not isValidCurrencyKey(currencyKey) then
		return false, "Invalid currency key.", nil
	end

	if not isPositiveInteger(amount) then
		return false, "Amount must be a positive integer.", nil
	end

	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded.", nil
	end

	local currentBalance = getCurrencyBalance(profile, currencyKey)

	if currentBalance < amount then
		return false, "Not enough currency.", currentBalance
	end

	local newBalance = currentBalance - amount
	setCurrencyBalance(profile, currencyKey, newBalance)
	profile.UpdatedAt = os.time()

	RoomPersistence.QueueSave(player)

	return true, "Currency removed.", newBalance
end

function RoomPersistence.SetCurrency(player, currencyKey, amount, reason)
	if not isValidCurrencyKey(currencyKey) then
		return false, "Invalid currency key.", nil
	end

	if not isNonNegativeInteger(amount) then
		return false, "Amount must be a non-negative integer.", nil
	end

	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded.", nil
	end

	setCurrencyBalance(profile, currencyKey, amount)
	profile.UpdatedAt = os.time()

	RoomPersistence.QueueSave(player)

	return true, "Currency set.", amount
end

function RoomPersistence.GetCoins(player)
	return RoomPersistence.GetCurrency(player, "Coins") or 0
end

function RoomPersistence.AddCoins(player, amount, reason)
	return RoomPersistence.AddCurrency(player, "Coins", amount, reason)
end

function RoomPersistence.RemoveCoins(player, amount, reason)
	return RoomPersistence.RemoveCurrency(player, "Coins", amount, reason)
end

function RoomPersistence.SetCoins(player, amount, reason)
	return RoomPersistence.SetCurrency(player, "Coins", amount, reason)
end

function RoomPersistence.GetDollars(player)
	return RoomPersistence.GetCurrency(player, "Dollars") or 0
end

function RoomPersistence.AddDollars(player, amount, reason)
	return RoomPersistence.AddCurrency(player, "Dollars", amount, reason)
end

function RoomPersistence.RemoveDollars(player, amount, reason)
	return RoomPersistence.RemoveCurrency(player, "Dollars", amount, reason)
end

function RoomPersistence.SetDollars(player, amount, reason)
	return RoomPersistence.SetCurrency(player, "Dollars", amount, reason)
end

function RoomPersistence.GetWorkActivityCooldownSnapshot(player)
	local profile = profilesByPlayer[player]

	if not profile then
		return {}
	end

	local now = os.time()
	local cooldowns = ensureWorkActivityCooldowns(profile)
	local snapshot = {}
	local removedExpired = false

	for activityId, cooldownRecord in pairs(cooldowns) do
		local nextAvailableUnix = cooldownRecord.NextAvailableUnix
		local remainingSeconds = typeof(nextAvailableUnix) == "number"
			and math.max(0, math.ceil(nextAvailableUnix - now))
			or 0

		if remainingSeconds > 0 then
			snapshot[activityId] = {
				LastCompletedUnix = cooldownRecord.LastCompletedUnix,
				NextAvailableUnix = nextAvailableUnix,
				RemainingCooldown = remainingSeconds,
			}
		else
			cooldowns[activityId] = nil
			removedExpired = true
		end
	end

	if removedExpired then
		profile.UpdatedAt = now
		RoomPersistence.QueueSave(player)
	end

	return deepCopy(snapshot)
end

function RoomPersistence.GetWorkActivityCooldown(player, activityId)
	if not isValidWorkActivityId(activityId) then
		return nil, nil, "Invalid work activity."
	end

	local profile = profilesByPlayer[player]

	if not profile then
		return nil, nil, "Profile is not loaded."
	end

	local cooldowns = ensureWorkActivityCooldowns(profile)
	local cooldownRecord = cooldowns[activityId]

	if not cooldownRecord then
		return 0, nil, nil
	end

	local remainingSeconds = math.max(0, math.ceil(cooldownRecord.NextAvailableUnix - os.time()))

	if remainingSeconds <= 0 then
		cooldowns[activityId] = nil
		profile.UpdatedAt = os.time()
		RoomPersistence.QueueSave(player)

		return 0, nil, nil
	end

	return remainingSeconds, deepCopy(cooldownRecord), nil
end

function RoomPersistence.SetWorkActivityCooldown(player, activityId, cooldownSeconds)
	if not isValidWorkActivityId(activityId) then
		return false, "Invalid work activity.", nil, nil
	end

	if typeof(cooldownSeconds) ~= "number"
		or cooldownSeconds ~= cooldownSeconds
		or cooldownSeconds < 0
		or cooldownSeconds >= math.huge then

		return false, "Invalid work cooldown.", nil, nil
	end

	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded.", nil, nil
	end

	local now = os.time()
	local normalizedCooldownSeconds = math.max(0, math.ceil(cooldownSeconds))
	local cooldownRecord = {
		LastCompletedUnix = now,
		NextAvailableUnix = now + normalizedCooldownSeconds,
	}
	local cooldowns = ensureWorkActivityCooldowns(profile)
	cooldowns[activityId] = cooldownRecord
	profile.UpdatedAt = now

	RoomPersistence.QueueSave(player)

	local savedNow = RoomPersistence.SavePlayer(player)
	local message = savedNow
		and "Work cooldown saved."
		or "Work cooldown queued; immediate save failed."

	return true, message, normalizedCooldownSeconds, deepCopy(cooldownRecord)
end

function RoomPersistence.GrantStarterDollarsIfNeeded(player)
	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded.", nil
	end

	local currentDollars = getCurrencyBalance(profile, "Dollars")

	if profile.StarterDollarsGranted == true then
		return true, "Starter Dollars already granted.", currentDollars
	end

	local newBalance = currentDollars + STARTER_DOLLARS

	setCurrencyBalance(profile, "Dollars", newBalance)
	profile.StarterDollarsGranted = true
	profile.UpdatedAt = os.time()

	RoomPersistence.QueueSave(player)

	return true, "Starter Dollars granted.", newBalance
end

function RoomPersistence.GetDailyRewardStatus(player)
	local now = os.time()
	local profile = profilesByPlayer[player]

	if not profile then
		return {
			CanClaim = false,
			ClaimedToday = false,
			LastClaimUnix = nil,
			Streak = 0,
			CurrentDayIndex = 1,
			RewardAmount = getDailyRewardAmountForDay(1),
			NextClaimUnix = nil,
			SecondsUntilNextClaim = 0,
			StreakResetPending = false,
			Rewards = getDailyRewardScheduleSnapshot(),
		}
	end

	local dailyReward = ensureDailyReward(profile)
	local claimState = getDailyRewardClaimState(dailyReward, now)

	return {
		CanClaim = claimState.CanClaim,
		ClaimedToday = false,
		LastClaimUnix = claimState.LastClaimUnix,
		Streak = claimState.Streak,
		CurrentDayIndex = claimState.CurrentDayIndex,
		RewardAmount = claimState.RewardAmount,
		NextClaimUnix = claimState.NextClaimUnix,
		SecondsUntilNextClaim = claimState.SecondsUntilNextClaim,
		StreakResetPending = claimState.StreakResetPending,
		Rewards = getDailyRewardScheduleSnapshot(),
	}
end

function RoomPersistence.ClaimDailyReward(player)
	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded.", nil, nil, RoomPersistence.GetDailyRewardStatus(player)
	end

	local now = os.time()
	local dailyReward = ensureDailyReward(profile)
	local claimState = getDailyRewardClaimState(dailyReward, now)
	local hadLastClaimUnix = isNonNegativeInteger(dailyReward.LastClaimUnix)
		and dailyReward.LastClaimUnix > 0

	if not claimState.CanClaim then
		return false, "Daily reward is not ready.", nil, getCurrencyBalance(profile, "Dollars"), RoomPersistence.GetDailyRewardStatus(player)
	end

	local rewardAmount = getDailyRewardAmountForDay(claimState.CurrentDayIndex)
	local added, message, newDollarBalance =
		RoomPersistence.AddCurrency(player, DAILY_REWARD_CURRENCY_KEY, rewardAmount, "DailyReward:" .. tostring(now))

	if not added then
		return false, message or "Could not claim daily reward.", nil, newDollarBalance, RoomPersistence.GetDailyRewardStatus(player)
	end

	dailyReward.LastClaimUnix = now
	local shouldResetStreak = claimState.StreakResetPending or not hadLastClaimUnix
	dailyReward.Streak = shouldResetStreak
		and 1
		or math.clamp((dailyReward.Streak or 0) + 1, 1, #DAILY_REWARD_SCHEDULE)
	profile.UpdatedAt = os.time()

	RoomPersistence.QueueSave(player)

	return true,
		"Claimed " .. tostring(rewardAmount) .. " Dollars!",
		rewardAmount,
		newDollarBalance,
		RoomPersistence.GetDailyRewardStatus(player)
end

function RoomPersistence.GetInventorySnapshot(player)
	local profile = profilesByPlayer[player]

	if not profile then
		return {}
	end

	return deepCopy(ensureInventory(profile))
end

function RoomPersistence.GetInventoryDetailsSnapshot(player)
	local profile = profilesByPlayer[player]

	if not profile then
		return {}
	end

	local inventory = ensureInventory(profile)
	local snapshot = {}

	for templateId in pairs(inventory) do
		snapshot[templateId] = getInventoryCountDetails(profile, templateId)
	end

	return snapshot
end

function RoomPersistence.AddInventoryItem(player, templateId, amount, options)
	if not isValidTemplateId(templateId) then
		return false, "Invalid TemplateId.", nil
	end

	if not isPositiveInteger(amount) then
		return false, "Amount must be a positive integer.", nil
	end

	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded.", nil
	end

	local inventory, untradable, unsellable = ensureInventory(profile)
	local currentCount = inventory[templateId] or 0
	local newCount = currentCount + amount

	inventory[templateId] = newCount

	if typeof(options) == "table" and options.Tradable == false then
		setInventorySubsetCount(untradable, templateId, (untradable[templateId] or 0) + amount, newCount)
	end

	if typeof(options) == "table" and options.Sellable == false then
		setInventorySubsetCount(unsellable, templateId, (unsellable[templateId] or 0) + amount, newCount)
	end

	local details = getInventoryCountDetails(profile, templateId)
	profile.UpdatedAt = os.time()

	RoomPersistence.QueueSave(player)

	return true, "Inventory item added.", newCount, details
end

function RoomPersistence.RemoveInventoryItem(player, templateId, amount, options)
	if not isValidTemplateId(templateId) then
		return false, "Invalid TemplateId.", nil
	end

	if not isPositiveInteger(amount) then
		return false, "Amount must be a positive integer.", nil
	end

	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded.", nil
	end

	local inventory, untradable, unsellable = ensureInventory(profile)
	local currentCount = inventory[templateId] or 0

	if currentCount < amount then
		return false, "Not enough inventory.", currentCount, getInventoryCountDetails(profile, templateId)
	end

	local currentUntradable = math.min(untradable[templateId] or 0, currentCount)
	local currentUnsellable = math.min(unsellable[templateId] or 0, currentCount)
	local untradableUnsellable = math.min(currentUntradable, currentUnsellable)
	local untradableSellable = currentUntradable - untradableUnsellable
	local tradableUnsellable = currentUnsellable - untradableUnsellable
	local tradableSellable = currentCount
		- untradableUnsellable
		- untradableSellable
		- tradableUnsellable
	local consumedUntradable = 0
	local consumedTradable = 0
	local consumedUnsellable = 0
	local remainingToConsume = amount

	local function consumeFromBucket(bucketCount, isUntradable, isUnsellable)
		local consumed = math.min(remainingToConsume, bucketCount)

		if consumed <= 0 then
			return
		end

		remainingToConsume -= consumed

		if isUntradable then
			consumedUntradable += consumed
		else
			consumedTradable += consumed
		end

		if isUnsellable then
			consumedUnsellable += consumed
		end
	end

	if typeof(options) == "table" and options.ConsumeTradableFirst == true then
		consumeFromBucket(tradableSellable, false, false)
		consumeFromBucket(tradableUnsellable, false, true)
		consumeFromBucket(untradableSellable, true, false)
		consumeFromBucket(untradableUnsellable, true, true)
	else
		consumeFromBucket(untradableUnsellable, true, true)
		consumeFromBucket(untradableSellable, true, false)
		consumeFromBucket(tradableUnsellable, false, true)
		consumeFromBucket(tradableSellable, false, false)
	end

	local newCount = currentCount - amount
	local newUntradable = currentUntradable - consumedUntradable
	local newUnsellable = currentUnsellable - consumedUnsellable

	if newCount > 0 then
		inventory[templateId] = newCount
	else
		inventory[templateId] = nil
	end

	setInventorySubsetCount(untradable, templateId, newUntradable, newCount)
	setInventorySubsetCount(unsellable, templateId, newUnsellable, newCount)

	local details = getInventoryCountDetails(profile, templateId)
	details.ConsumedTradable = consumedTradable > 0
	details.ConsumedTradableCount = consumedTradable
	details.ConsumedUntradableCount = consumedUntradable
	details.ConsumedUntradable = consumedUntradable > 0
	details.ConsumedUnsellableCount = consumedUnsellable
	details.ConsumedUnsellable = consumedUnsellable > 0

	profile.UpdatedAt = os.time()

	RoomPersistence.QueueSave(player)

	return true, "Inventory item removed.", newCount, details
end

function RoomPersistence.RemoveMarketplaceListableInventoryItem(player, templateId, amount)
	if not isValidTemplateId(templateId) then
		return false, "Invalid TemplateId.", nil
	end

	if not isPositiveInteger(amount) then
		return false, "Amount must be a positive integer.", nil
	end

	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded.", nil
	end

	ensureInventory(profile)

	local inventory = profile.Inventory
	local untradable = profile.InventoryUntradable
	local unsellable = profile.InventoryUnsellable
	local oldTotal = inventory[templateId] or 0
	local oldUntradable = untradable[templateId] or 0
	local oldUnsellable = unsellable[templateId] or 0
	local oldTradable = math.max(0, oldTotal - oldUntradable)

	if oldTradable < amount then
		return false, "You do not have enough tradable copies to list.", oldTotal, getInventoryCountDetails(profile, templateId)
	end

	local newTotal = oldTotal - amount
	local newUntradable = math.min(oldUntradable, newTotal)
	local newUnsellable = math.min(oldUnsellable, newTotal)

	if newTotal > 0 then
		inventory[templateId] = newTotal
	else
		inventory[templateId] = nil
	end

	if newUntradable > 0 then
		untradable[templateId] = newUntradable
	else
		untradable[templateId] = nil
	end

	if newUnsellable > 0 then
		unsellable[templateId] = newUnsellable
	else
		unsellable[templateId] = nil
	end

	local afterTotal = inventory[templateId] or 0
	local afterUntradable = untradable[templateId] or 0
	local afterTradable = math.max(0, afterTotal - afterUntradable)
	local expectedAfterTradable = oldTradable - amount

	if afterTotal ~= newTotal
		or afterUntradable ~= newUntradable
		or afterTradable ~= expectedAfterTradable then

		warn(
			"Marketplace escrow verification failed",
			"templateId=", templateId,
			"oldTotal=", oldTotal,
			"oldUntradable=", oldUntradable,
			"oldTradable=", oldTradable,
			"quantity=", amount,
			"newTotal=", newTotal,
			"newUntradable=", newUntradable,
			"afterTotal=", afterTotal,
			"afterUntradable=", afterUntradable,
			"afterTradable=", afterTradable,
			"expectedAfterTradable=", expectedAfterTradable
		)

		if oldTotal > 0 then
			inventory[templateId] = oldTotal
		else
			inventory[templateId] = nil
		end

		if oldUntradable > 0 then
			untradable[templateId] = oldUntradable
		else
			untradable[templateId] = nil
		end

		if oldUnsellable > 0 then
			unsellable[templateId] = oldUnsellable
		else
			unsellable[templateId] = nil
		end

		return false,
			"Marketplace escrow failed. Please try again.",
			oldTotal,
			getInventoryCountDetails(profile, templateId)
	end

	local updatedDetails = getInventoryCountDetails(profile, templateId)
	profile.UpdatedAt = os.time()

	RoomPersistence.QueueSave(player)

	return true, "Marketplace tradable inventory item removed.", newTotal, updatedDetails
end

function RoomPersistence.ReturnMarketplaceListableInventoryItem(player, templateId, amount, options)
	local returnTradable = true
	local returnSellable = true

	-- Current marketplace escrow stores aggregate counts; future item-instance
	-- tracking can set ReturnSellable to preserve the exact sellable state.
	if typeof(options) == "table" and typeof(options.ReturnTradable) == "boolean" then
		returnTradable = options.ReturnTradable
	end

	if typeof(options) == "table" and typeof(options.ReturnSellable) == "boolean" then
		returnSellable = options.ReturnSellable
	end

	return RoomPersistence.AddInventoryItem(player, templateId, amount, {
		Tradable = returnTradable,
		Sellable = returnSellable,
	})
end

function RoomPersistence.RemoveSellableInventoryItem(player, templateId, amount)
	if not isValidTemplateId(templateId) then
		return false, "Invalid TemplateId.", nil
	end

	if not isPositiveInteger(amount) then
		return false, "Amount must be a positive integer.", nil
	end

	local profile = profilesByPlayer[player]

	if not profile then
		return false, "Profile is not loaded.", nil
	end

	local inventory, untradable, unsellable = ensureInventory(profile)
	local currentCount = inventory[templateId] or 0
	local currentUntradable = math.min(untradable[templateId] or 0, currentCount)
	local currentUnsellable = math.min(unsellable[templateId] or 0, currentCount)
	local currentSellable = currentCount - currentUnsellable

	if currentSellable < amount then
		return false, "No sellable items.", currentCount, getInventoryCountDetails(profile, templateId)
	end

	local untradableUnsellable = math.min(currentUntradable, currentUnsellable)
	local untradableSellable = currentUntradable - untradableUnsellable
	local consumedUntradable = math.min(amount, untradableSellable)
	local consumedTradable = amount - consumedUntradable
	local newCount = currentCount - amount
	local newUntradable = currentUntradable - consumedUntradable
	local newUnsellable = currentUnsellable

	if newCount > 0 then
		inventory[templateId] = newCount
	else
		inventory[templateId] = nil
	end

	setInventorySubsetCount(untradable, templateId, newUntradable, newCount)
	setInventorySubsetCount(unsellable, templateId, newUnsellable, newCount)

	local details = getInventoryCountDetails(profile, templateId)
	details.ConsumedTradable = consumedTradable > 0
	details.ConsumedTradableCount = consumedTradable
	details.ConsumedUntradableCount = consumedUntradable
	details.ConsumedUntradable = consumedUntradable > 0
	details.ConsumedUnsellableCount = 0
	details.ConsumedUnsellable = false

	profile.UpdatedAt = os.time()

	RoomPersistence.QueueSave(player)

	return true, "Sellable inventory item removed.", newCount, details
end

function RoomPersistence.QueueSave(player)
	if saveScheduled[player] then
		return
	end

	saveScheduled[player] = true

	task.delay(SAVE_DELAY_SECONDS, function()
		saveScheduled[player] = nil

		if profilesByPlayer[player] and not RoomPersistence.IsWriteBlocked(player) then
			RoomPersistence.SavePlayer(player)
		end
	end)
end

function RoomPersistence.SavePlayer(player)
	if RoomPersistence.IsWriteBlocked(player) then
		traceProfileCache("SavePlayer blocked", player and player.Name or "nil")
		return false, "Writes are blocked."
	end
	
	local profile = profilesByPlayer[player]

	if not profile then
		traceProfileCache("SavePlayer missing profile", player and player.Name or "nil")
		return false, "Profile is not loaded."
	end

	if saveRunning[player] then
		traceProfileCache("SavePlayer already running", player.Name, getProfileDebugId(profile))
		return false, "A profile save is already running."
	end

	profile = ensureRoomsSchema(profile)
	profilesByPlayer[player] = profile
	profile.UpdatedAt = os.time()

	local profileSnapshot = deepCopy(profile)

	saveRunning[player] = true
	traceProfileCache("SavePlayer start", player.Name, getProfileDebugId(profile), "updatedAt", tostring(profile.UpdatedAt))

	local success, errorMessage = pcall(function()
		profileStore:UpdateAsync(getKey(player), function()
			return profileSnapshot
		end)
	end)

	saveRunning[player] = nil

	if not success then
		warn("RoomPersistence: profile save failed for", player.Name, errorMessage)
		traceProfileCache("SavePlayer failed", player.Name, tostring(errorMessage))
		return false, tostring(errorMessage)
	end

	traceProfileCache("SavePlayer success", player.Name, getProfileDebugId(profile))

	return true, "Profile saved."
end

function RoomPersistence.CaptureRoomState(player, roomModel)
	if RoomPersistence.IsWriteBlocked(player) then
		return nil
	end
	
	local profile = profilesByPlayer[player]

	if not profile then
		return nil
	end

	local roomState = serializeRoom(roomModel)

	if not roomState then
		return nil
	end

	profile.ProfileCreated = true
	profile.CharacterCreated = true

	local roomId = PRIMARY_ROOM_ID

	if roomModel and roomModel.GetAttribute then
		roomId = normalizeRoomId(roomModel:GetAttribute("RoomId")) or roomId
	end

	if roomId == PRIMARY_ROOM_ID then
		local currentRoomId = normalizeRoomId(player:GetAttribute("CurrentRoomId"))

		if currentRoomId then
			roomId = currentRoomId
		end
	end

	local roomStateSaved = setRoomStateForRoomProfile(
		profile,
		roomId,
		roomState,
		roomState.LayoutId
	)

	if not roomStateSaved and roomId == PRIMARY_ROOM_ID then
		profile.CurrentLayoutId = roomState.LayoutId
		profile.RoomState = roomState
	elseif not roomStateSaved then
		if DEBUG_ROOM_SAVE_TRACE then
			warn("RoomPersistence: room state capture skipped for missing room", player.Name, roomId)
		end

		return nil
	end

	profile.UpdatedAt = os.time()

	RoomPersistence.QueueSave(player)

	return roomState
end

function RoomPersistence.IsWriteBlocked(player)
	if not player then
		return false
	end

	return writeBlockedByUserId[player.UserId] == true
end

function RoomPersistence.BlockWritesForUserId(userId)
	userId = tonumber(userId)

	if not userId then
		return
	end

	writeBlockedByUserId[userId] = true
end

function RoomPersistence.UnblockWritesForUserId(userId)
	userId = tonumber(userId)

	if not userId then
		return
	end

	writeBlockedByUserId[userId] = nil
end


function RoomPersistence.DeleteProfileByUserId(userId)
	userId = tonumber(userId)

	if not userId or userId <= 0 then
		return false, "Invalid UserId."
	end

	RoomPersistence.BlockWritesForUserId(userId)

	local onlinePlayer = Players:GetPlayerByUserId(userId)

	if onlinePlayer then
		-- Stop delayed saves from recreating the deleted profile.
		profilesByPlayer[onlinePlayer] = nil
		saveScheduled[onlinePlayer] = nil

		-- If a save is already running, let it finish, then delete after it.
		local timeoutAt = os.clock() + 6

		while saveRunning[onlinePlayer] and os.clock() < timeoutAt do
			task.wait(0.1)
		end
	end

	local key = getKeyFromUserId(userId)

	local success, result = retryAsync("Remove profile " .. key, 3, function()
		return profileStore:RemoveAsync(key)
	end)

	if not success then
		-- Deletion failed, so allow normal saves again.
		-- Otherwise the online player could lose unsaved progress without the reset actually happening.
		RoomPersistence.UnblockWritesForUserId(userId)
		return false, result
	end
	
	-- If the player is offline, no PlayerRemoving save can happen,
	-- so we can unblock immediately.
	if not onlinePlayer then
		RoomPersistence.UnblockWritesForUserId(userId)
	end

	return true, result
end

function RoomPersistence.ResetOnlinePlayer(player, message)
	if not player then
		return false, "Missing player."
	end

	local success, result = RoomPersistence.DeleteProfileByUserId(player.UserId)

	if not success then
		return false, result
	end

	player:Kick(message or "Your profile was reset. Please rejoin to start fresh.")

	return true, result
end


function RoomPersistence.ReleasePlayer(player)
	profilesByPlayer[player] = nil
	saveScheduled[player] = nil
	saveRunning[player] = nil
	writeBlockedByUserId[player.UserId] = nil
end

return RoomPersistence
