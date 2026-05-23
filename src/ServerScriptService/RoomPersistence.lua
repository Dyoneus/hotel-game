-- Explorer/ServerScriptService/RoomPersistence.lua
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")

local RoomPersistence = {}

local DATASTORE_NAME = "PlayerProfiles_v1"
local SAVE_DELAY_SECONDS = 12

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

		RoomState = nil,

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
				furnitureModel:PivotTo(roomAnchor.CFrame * relativeCFrame)
			end
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