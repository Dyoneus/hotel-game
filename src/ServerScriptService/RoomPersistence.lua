-- Explorer/ServerScriptService/RoomPersistence.lua
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")

local RoomPersistence = {}

local DATASTORE_NAME = "PlayerProfiles_v1"
local SAVE_DELAY_SECONDS = 12
local STARTER_DOLLARS = 150
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

local profileStore = DataStoreService:GetDataStore(DATASTORE_NAME)

local profilesByPlayer = {}
local saveScheduled = {}
local saveRunning = {}
local writeBlockedByUserId = {}

local function createDefaultProfile()
	return {
		Version = 1,

		ProfileCreated = false,
		CharacterCreated = false,
		OnboardingStep = "CharacterCreation",

		CurrentLayoutId = nil,
		StarterDollarsGranted = false,

		RoomState = nil,
		RoomDirectory = {
			RoomId = "Primary",
			DisplayName = nil,
			Category = "Chat Rooms",
			IsPublic = true,
			MaxOccupancy = 25,
			Description = "",
			Tags = {},
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

		UpdatedAt = os.time(),
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

local function isPositiveInteger(value)
	return typeof(value) == "number"
		and value == value
		and value > 0
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

local function ensureInventory(profile)
	local inventory = normalizeInventoryCounts(profile.Inventory)
	local untradable = normalizeInventoryCounts(profile.InventoryUntradable)
	local unsellable = normalizeInventoryCounts(profile.InventoryUnsellable)

	for templateId, untradableCount in pairs(untradable) do
		local totalCount = inventory[templateId] or 0

		if totalCount <= 0 then
			untradable[templateId] = nil
		elseif untradableCount > totalCount then
			untradable[templateId] = totalCount
		end
	end

	for templateId, unsellableCount in pairs(unsellable) do
		local totalCount = inventory[templateId] or 0

		if totalCount <= 0 then
			unsellable[templateId] = nil
		elseif unsellableCount > totalCount then
			unsellable[templateId] = totalCount
		end
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
	local untradableCount = math.min(untradable[templateId] or 0, total)
	local tradableCount = total - untradableCount
	local unsellableCount = math.min(unsellable[templateId] or 0, total)
	local sellableCount = total - unsellableCount

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

local function ensureRoomDirectory(profile)
	local roomDirectory = profile.RoomDirectory

	if typeof(roomDirectory) ~= "table" then
		roomDirectory = {}
	end

	if typeof(roomDirectory.RoomId) ~= "string" or roomDirectory.RoomId == "" then
		roomDirectory.RoomId = "Primary"
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

local function fillDefaults(profile)
	local defaults = createDefaultProfile()

	if typeof(profile) ~= "table" then
		return defaults
	end

	for key, defaultValue in pairs(defaults) do
		if profile[key] == nil then
			profile[key] = defaultValue
		end
	end

	ensureInventory(profile)
	ensureCurrencies(profile)
	ensureDailyReward(profile)
	ensureRoomDirectory(profile)

	if profile.StarterDollarsGranted ~= true then
		profile.StarterDollarsGranted = false
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
	local success, data = pcall(function()
		return profileStore:GetAsync(getKey(player))
	end)

	if not success then
		warn("RoomPersistence: profile load failed for", player.Name, data)

		-- Studio fallback keeps development usable if API access is disabled.
		-- Real persistence still requires Studio API access / live server DataStores.
		if RunService:IsStudio() then
			local fallbackProfile = createDefaultProfile()
			profilesByPlayer[player] = fallbackProfile
			return fallbackProfile, true
		end

		return nil, false
	end

	local profile = fillDefaults(data)
	profilesByPlayer[player] = profile

	return profile, true
end

function RoomPersistence.GetProfile(player)
	return profilesByPlayer[player]
end

function RoomPersistence.GetRoomDirectorySnapshot(player)
	local profile = profilesByPlayer[player]

	if not profile then
		return nil
	end

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
	roomDirectory.RoomId = "Primary"
	roomDirectory.Tags = normalizeRoomTags(roomDirectory.Tags)

	profile.UpdatedAt = os.time()
	RoomPersistence.QueueSave(player)

	return true, "Room settings saved.", deepCopy(roomDirectory)
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
		untradable[templateId] = (untradable[templateId] or 0) + amount
	end

	if typeof(options) == "table" and options.Sellable == false then
		unsellable[templateId] = (unsellable[templateId] or 0) + amount
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

	if newUntradable > 0 and newCount > 0 then
		untradable[templateId] = math.min(newUntradable, newCount)
	else
		untradable[templateId] = nil
	end

	if newUnsellable > 0 and newCount > 0 then
		unsellable[templateId] = math.min(newUnsellable, newCount)
	else
		unsellable[templateId] = nil
	end

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

	if newUntradable > 0 and newCount > 0 then
		untradable[templateId] = math.min(newUntradable, newCount)
	else
		untradable[templateId] = nil
	end

	if newUnsellable > 0 and newCount > 0 then
		unsellable[templateId] = math.min(newUnsellable, newCount)
	else
		unsellable[templateId] = nil
	end

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
		return false
	end
	
	local profile = profilesByPlayer[player]

	if not profile then
		return false
	end

	if saveRunning[player] then
		return false
	end

	profile.UpdatedAt = os.time()

	local profileSnapshot = deepCopy(profile)

	saveRunning[player] = true

	local success, errorMessage = pcall(function()
		profileStore:UpdateAsync(getKey(player), function()
			return profileSnapshot
		end)
	end)

	saveRunning[player] = nil

	if not success then
		warn("RoomPersistence: profile save failed for", player.Name, errorMessage)
	end

	return success
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
	profile.CurrentLayoutId = roomState.LayoutId
	profile.RoomState = roomState
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
