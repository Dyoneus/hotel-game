--Explorer/ServerScriptService/PlayerRoomServer.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RoomPersistence = require(ServerScriptService:WaitForChild("RoomPersistence"))

local playerRooms = {}
local playerRoomSlots = {}
local nextRoomSlot = 0

local roomCreationInFlightByUserId = {}

local roomTemplates = ReplicatedStorage:WaitForChild("RoomTemplates")
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local createRoomRequest = remoteEvents:WaitForChild("CreateRoomRequest")
local roomCreationResult = remoteEvents:WaitForChild("RoomCreationResult")
local characterCreationFinished = remoteEvents:WaitForChild("CharacterCreationFinished")
local roomListRequest = remoteEvents:WaitForChild("RoomListRequest")
local roomListUpdate = remoteEvents:WaitForChild("RoomListUpdate")
local joinRoomRequest = remoteEvents:WaitForChild("JoinRoomRequest")
local joinRoomResult = remoteEvents:WaitForChild("JoinRoomResult")

local tutorialFinishedRequest = remoteEvents:WaitForChild("TutorialFinishedRequest")

local activeRooms = workspace:WaitForChild("ActiveRooms")

local VALID_LAYOUTS = {
	Layout_01 = true,
	Layout_02 = true,
	Layout_03 = true,
}

local ROOM_SPACING = 200

local playerRooms = {}
local playerRoomSlots = {}
local nextRoomSlot = 0

local function getRoomName(player)
	return "Room_" .. player.UserId
end

local function getRoomPositionForPlayer(player)
	if not playerRoomSlots[player] then
		nextRoomSlot += 1
		playerRoomSlots[player] = nextRoomSlot
	end

	local slot = playerRoomSlots[player]

	return Vector3.new((slot - 1) * ROOM_SPACING, 0, 0)
end

local function removePlayerRoom(player)
	local existingRoom = playerRooms[player]

	if existingRoom and existingRoom.Parent then
		existingRoom:Destroy()
	end

	playerRooms[player] = nil
	playerRoomSlots[player] = nil
end

local function moveRoomAnchorToPosition(roomModel, targetAnchorPosition)
	local roomAnchor = roomModel:FindFirstChild("RoomAnchor", true)

	if not roomAnchor or not roomAnchor:IsA("BasePart") then
		warn("Room is missing RoomAnchor:", roomModel.Name)
		return false
	end

	local currentPivot = roomModel:GetPivot()
	local offset = targetAnchorPosition - roomAnchor.Position

	roomModel:PivotTo(currentPivot + offset)

	return true
end

local function cloneRoomForPlayer(player, layoutId)
	if not VALID_LAYOUTS[layoutId] then
		warn("Invalid layout requested:", layoutId)
		return nil
	end

	local template = roomTemplates:FindFirstChild(layoutId)

	if not template then
		warn("Missing room template:", layoutId)
		return nil
	end

	removePlayerRoom(player)

	local roomClone = template:Clone()
	roomClone.Name = getRoomName(player)
	roomClone.Parent = activeRooms
	
	if not roomClone:IsA("Model") then
		warn("Room template must be a Model, not a Folder:", layoutId)
		roomClone:Destroy()
		return nil
	end

	local roomOffset = getRoomPositionForPlayer(player)
	print("Room anchor position for", player.Name, "=", roomOffset)

	local moved = moveRoomAnchorToPosition(roomClone, roomOffset)

	if not moved then
		roomClone:Destroy()
		return nil
	end

	roomClone:SetAttribute("OwnerUserId", player.UserId)
	roomClone:SetAttribute("LayoutId", layoutId)

	playerRooms[player] = roomClone
	
	return roomClone
end

local function movePlayerToRoom(player, roomModel)
	local character = player.Character or player.CharacterAdded:Wait()

	local doorSpawn = roomModel:FindFirstChild("DoorSpawn", true)

	if not doorSpawn or not doorSpawn:IsA("BasePart") then
		warn("Room is missing DoorSpawn:", roomModel.Name)
		return
	end

	character:PivotTo(doorSpawn.CFrame)
end

local function getRoomOwnerPlayer(roomModel)
	local ownerUserId = roomModel:GetAttribute("OwnerUserId")

	if typeof(ownerUserId) ~= "number" then
		return nil
	end

	return Players:GetPlayerByUserId(ownerUserId)
end

local function getPlayerCountInRoom(roomName)
	local count = 0

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("CurrentRoomName") == roomName then
			count += 1
		end
	end

	return count
end

local function buildRoomList()
	local roomList = {}

	for _, roomModel in ipairs(activeRooms:GetChildren()) do
		if roomModel:IsA("Model") then
			local ownerUserId = roomModel:GetAttribute("OwnerUserId")
			local layoutId = roomModel:GetAttribute("LayoutId")
			local ownerPlayer = getRoomOwnerPlayer(roomModel)

			local ownerName = "Unknown"
			local ownerDisplayName = "Unknown"

			if ownerPlayer then
				ownerName = ownerPlayer.Name
				ownerDisplayName = ownerPlayer.DisplayName
			elseif typeof(ownerUserId) == "number" then
				ownerName = "User_" .. tostring(ownerUserId)
				ownerDisplayName = ownerName
			end

			table.insert(roomList, {
				RoomName = roomModel.Name,
				OwnerUserId = ownerUserId,
				OwnerName = ownerName,
				OwnerDisplayName = ownerDisplayName,
				LayoutId = layoutId or "Unknown",
				PlayerCount = getPlayerCountInRoom(roomModel.Name),
			})
		end
	end

	table.sort(roomList, function(a, b)
		return tostring(a.OwnerDisplayName) < tostring(b.OwnerDisplayName)
	end)

	return roomList
end

local function sendRoomListToPlayer(player)
	local roomList = buildRoomList()

	roomListUpdate:FireClient(player, roomList, player:GetAttribute("CurrentRoomName"))
end

local function sendRoomListToAll()
	local roomList = buildRoomList()

	for _, player in ipairs(Players:GetPlayers()) do
		roomListUpdate:FireClient(player, roomList, player:GetAttribute("CurrentRoomName"))
	end
end

local function enterSavedRoomForPlayer(player, profile)
	local roomState = profile.RoomState
	local layoutId = profile.CurrentLayoutId

	if typeof(roomState) == "table" and typeof(roomState.LayoutId) == "string" then
		layoutId = roomState.LayoutId
	end

	if typeof(layoutId) ~= "string" or not VALID_LAYOUTS[layoutId] then
		warn("Saved room has invalid layout:", layoutId)
		return false
	end

	local roomModel = cloneRoomForPlayer(player, layoutId)

	if not roomModel then
		return false
	end

	RoomPersistence.ApplyRoomState(roomModel, roomState)

	local success, errorMessage = pcall(function()
		movePlayerToRoom(player, roomModel)
	end)

	if not success then
		warn("Could not move player into saved room:", errorMessage)
		removePlayerRoom(player)
		return false
	end

	player:SetAttribute("CurrentRoomName", roomModel.Name)
	player:SetAttribute("CurrentLayoutId", layoutId)
	player:SetAttribute("HasCreatedRoom", true)
	player:SetAttribute("ProfileCreated", true)
	player:SetAttribute("CharacterCreatedThisSession", profile.CharacterCreated == true)
	player:SetAttribute("RoomMode", "Play")
	player:SetAttribute("ControlMode", "Hotel")

	local onboardingStep = profile.OnboardingStep

	if onboardingStep ~= "Tutorial" and onboardingStep ~= "Complete" then
		onboardingStep = "Complete"
	end

	player:SetAttribute("OnboardingStep", onboardingStep)

	roomCreationResult:FireClient(player, "Created", roomModel.Name)

	sendRoomListToAll()

	return true
end

local function getRoomByName(roomName)
	if typeof(roomName) ~= "string" then
		return nil
	end

	return activeRooms:FindFirstChild(roomName)
end

local function joinRoom(player, roomName)
	local roomModel = getRoomByName(roomName)

	if not roomModel or not roomModel:IsA("Model") then
		joinRoomResult:FireClient(player, false, "Room not found.")
		return
	end

	local ownerUserId = roomModel:GetAttribute("OwnerUserId")

	if typeof(ownerUserId) ~= "number" then
		joinRoomResult:FireClient(player, false, "Room has no owner.")
		return
	end

	player:SetAttribute("CurrentRoomName", roomModel.Name)
	player:SetAttribute("RoomMode", "Play")

	local success, errorMessage = pcall(function()
		movePlayerToRoom(player, roomModel)
	end)

	if not success then
		warn("Join room failed:", errorMessage)
		joinRoomResult:FireClient(player, false, "Could not enter room.")
		return
	end

	joinRoomResult:FireClient(player, true, "Joined room.", roomModel.Name)

	sendRoomListToAll()
end

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("HasCreatedRoom", false)

	player.CharacterAdded:Connect(function()
		local roomName = player:GetAttribute("CurrentRoomName")

		if roomName then
			local roomModel = activeRooms:FindFirstChild(roomName)

			if roomModel then
				task.wait(0.2)
				movePlayerToRoom(player, roomModel)
			end
		end
	end)

	player:SetAttribute("RoomMode", "Play")
	player:SetAttribute("ControlMode", "Hotel")

	local profile, loaded = RoomPersistence.LoadProfile(player)

	if not loaded or not profile then
		player:Kick("Could not load your profile. Please rejoin.")
		return
	end

	local grantedStarterDollars, starterDollarsMessage =
		RoomPersistence.GrantStarterDollarsIfNeeded(player)

	if not grantedStarterDollars then
		warn("Starter Dollars grant failed for", player.Name, starterDollarsMessage)
	end

	player:SetAttribute("ProfileCreated", profile.ProfileCreated == true)
	player:SetAttribute("CharacterCreatedThisSession", profile.CharacterCreated == true)

	if profile.ProfileCreated == true then
		local enteredSavedRoom = enterSavedRoomForPlayer(player, profile)

		if enteredSavedRoom then
			return
		end

		-- Safer than overwriting saved data with a new room.
		player:Kick("Your saved room could not load. Please rejoin.")
		return
	end

	if profile.CharacterCreated == true then
		player:SetAttribute("OnboardingStep", "RoomCreation")
		roomCreationResult:FireClient(player, "ShowCreation")
	else
		player:SetAttribute("OnboardingStep", "CharacterCreation")
		roomCreationResult:FireClient(player, "ShowCharacterCreation")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	roomCreationInFlightByUserId[player.UserId] = nil
	
	if RoomPersistence.IsWriteBlocked(player) then
		RoomPersistence.ReleasePlayer(player)

		removePlayerRoom(player)
		playerRoomSlots[player] = nil

		task.defer(function()
			sendRoomListToAll()
		end)

		return
	end

	local ownedRoom = playerRooms[player]

	if ownedRoom and ownedRoom.Parent then
		RoomPersistence.CaptureRoomState(player, ownedRoom)
	end

	RoomPersistence.SavePlayer(player)
	RoomPersistence.ReleasePlayer(player)

	removePlayerRoom(player)
	playerRoomSlots[player] = nil

	task.defer(function()
		sendRoomListToAll()
	end)
end)

characterCreationFinished.OnServerEvent:Connect(function(player, characterData)
	if player:GetAttribute("HasCreatedRoom") then
		return
	end

	if player:GetAttribute("CharacterCreatedThisSession") then
		return
	end

	-- Temporary validation.
	-- Later, validate actual hair, clothes, skin tone, accessories, etc.
	if typeof(characterData) ~= "table" then
		characterData = {}
	end

	player:SetAttribute("CharacterCreatedThisSession", true)
	player:SetAttribute("OnboardingStep", "RoomCreation")

	local profile = RoomPersistence.GetProfile(player)

	if profile then
		profile.CharacterCreated = true
		profile.OnboardingStep = "RoomCreation"
		RoomPersistence.QueueSave(player)
	end

	roomCreationResult:FireClient(player, "ShowCreation")
end)

createRoomRequest.OnServerEvent:Connect(function(player, layoutId)
	print("Server: CreateRoomRequest from", player.Name, layoutId)

	local function sendCreationResult(status, roomName)
		if player.Parent == Players then
			roomCreationResult:FireClient(player, status, roomName)
		end
	end

	if roomCreationInFlightByUserId[player.UserId] then
		warn("Server: Ignoring duplicate CreateRoomRequest from", player.Name)
		return
	end

	if typeof(layoutId) ~= "string" then
		warn("Server: Invalid layoutId type")
		sendCreationResult("Failed")
		return
	end

	if not VALID_LAYOUTS[layoutId] then
		warn(player.Name .. " tried invalid layout:", layoutId)
		sendCreationResult("Failed")
		return
	end

	if player:GetAttribute("HasCreatedRoom") then
		warn(player.Name .. " already created a room this session")
		sendCreationResult("Created", player:GetAttribute("CurrentRoomName"))
		return
	end

	if not player:GetAttribute("CharacterCreatedThisSession") then
		warn(player.Name .. " tried to create a room before character creation")
		sendCreationResult("ShowCharacterCreation")
		return
	end

	roomCreationInFlightByUserId[player.UserId] = true

	local function clearRoomCreationLock()
		roomCreationInFlightByUserId[player.UserId] = nil
	end

	local roomModel = cloneRoomForPlayer(player, layoutId)

	if not roomModel then
		warn("Server: Room clone failed")
		clearRoomCreationLock()
		sendCreationResult("Failed")
		return
	end

	print("Server: Room cloned:", roomModel.Name)

	local success, errorMessage = pcall(function()
		movePlayerToRoom(player, roomModel)
	end)

	if not success then
		warn("Server: movePlayerToRoom failed:", errorMessage)
		clearRoomCreationLock()
		sendCreationResult("Failed")
		return
	end

	if player.Parent ~= Players then
		clearRoomCreationLock()
		return
	end

	-- Important:
	-- These must be set after the room is fully created and the player is moved.
	player:SetAttribute("CurrentRoomName", roomModel.Name)
	player:SetAttribute("CurrentLayoutId", layoutId)
	player:SetAttribute("HasCreatedRoom", true)
	player:SetAttribute("ProfileCreated", true)

	-- New players should enter their room first, then complete tutorial.
	player:SetAttribute("OnboardingStep", "Tutorial")
	player:SetAttribute("RoomMode", "Play")
	player:SetAttribute("ControlMode", "Hotel")

	local profile = RoomPersistence.GetProfile(player)

	if profile then
		profile.ProfileCreated = true
		profile.CharacterCreated = true
		profile.OnboardingStep = "Tutorial"
		profile.CurrentLayoutId = layoutId
	end

	RoomPersistence.CaptureRoomState(player, roomModel)
	RoomPersistence.SavePlayer(player)

	print("Server: Room created successfully, telling client")
	print("Server: OnboardingStep =", player:GetAttribute("OnboardingStep"))

	clearRoomCreationLock()

	sendCreationResult("Created", roomModel.Name)

	sendRoomListToAll()
end)

roomListRequest.OnServerEvent:Connect(function(player)
	sendRoomListToPlayer(player)
end)

joinRoomRequest.OnServerEvent:Connect(function(player, roomName)
	joinRoom(player, roomName)
end)

tutorialFinishedRequest.OnServerEvent:Connect(function(player)
	if player:GetAttribute("OnboardingStep") ~= "Tutorial" then
		return
	end

	player:SetAttribute("OnboardingStep", "Complete")
	
	local profile = RoomPersistence.GetProfile(player)

	if profile then
		profile.OnboardingStep = "Complete"
		RoomPersistence.QueueSave(player)
	end

	-- Refresh this player’s navigator button/list availability.
	sendRoomListToPlayer(player)
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local ownedRoom = playerRooms[player]

		if ownedRoom and ownedRoom.Parent then
			RoomPersistence.CaptureRoomState(player, ownedRoom)
		end

		RoomPersistence.SavePlayer(player)
	end
end)
