-- Studio Server Command Bar helper for owned-room floor style persistence.
-- Run from the Server Command Bar while Play is running. Client Command Bar
-- cannot access ServerScriptService.

local PLAYER_NAME = nil
local ROOM_ID = "Primary"
local TEST_STYLE_ID = "Plain"
local SET_STYLE = true
local APPLY_TO_ACTIVE_ROOM = true

local RunService = game:GetService("RunService")

if RunService:IsClient() then
	warn("[DebugRoomFloorStylePersistence] Run this from the Studio Server Command Bar, not the Client Command Bar.")
else
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")

	local RoomPersistence = require(ServerScriptService:WaitForChild("RoomPersistence"))
	local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
	local RoomFloorStyleRenderer = require(sharedFolder:WaitForChild("RoomFloorStyleRenderer"))

	local function findPlayer()
		if typeof(PLAYER_NAME) == "string" and PLAYER_NAME ~= "" then
			local namedPlayer = Players:FindFirstChild(PLAYER_NAME)

			if namedPlayer then
				return namedPlayer
			end

			for _, player in ipairs(Players:GetPlayers()) do
				if player.Name == PLAYER_NAME or player.DisplayName == PLAYER_NAME then
					return player
				end
			end

			return nil
		end

		return Players:GetPlayers()[1]
	end

	local function functionStatus(name)
		return typeof(RoomPersistence[name]) == "function" and "available" or "missing"
	end

	local function getOrLoadProfile(player)
		local profile = RoomPersistence.GetProfile(player)

		if profile then
			return profile, "cached"
		end

		if typeof(RoomPersistence.LoadProfile) ~= "function" then
			return nil, "LoadProfile missing"
		end

		local loadedProfile, loaded = RoomPersistence.LoadProfile(player)

		if loaded and loadedProfile then
			return RoomPersistence.GetProfile(player) or loadedProfile, "loaded"
		end

		return nil, "failed"
	end

	local function findActiveOwnedRoom(player, roomId)
		local activeRooms = workspace:FindFirstChild("ActiveRooms")

		if not activeRooms then
			return nil
		end

		local currentRoomName = player:GetAttribute("CurrentRoomName")

		if typeof(currentRoomName) == "string" and currentRoomName ~= "" then
			local currentRoom = activeRooms:FindFirstChild(currentRoomName)

			if currentRoom
				and currentRoom:IsA("Model")
				and currentRoom:GetAttribute("OwnerUserId") == player.UserId
				and currentRoom:GetAttribute("RoomId") == roomId then

				return currentRoom
			end
		end

		for _, roomModel in ipairs(activeRooms:GetChildren()) do
			if roomModel:IsA("Model")
				and roomModel:GetAttribute("OwnerUserId") == player.UserId
				and roomModel:GetAttribute("RoomId") == roomId
				and roomModel:GetAttribute("RoomType") ~= "PublicSpace" then

				return roomModel
			end
		end

		return nil
	end

	local player = findPlayer()

	if not player then
		warn("[DebugRoomFloorStylePersistence] No player found. Start Play and join with a player first.")
	else
		print(string.format("[DebugRoomFloorStylePersistence] Player=%s RoomId=%s", player.Name, tostring(ROOM_ID)))
		print(string.format(
			"[DebugRoomFloorStylePersistence] API GetProfile=%s LoadProfile=%s GetRoomStyleForRoom=%s GetRoomFloorStyle=%s SetRoomFloorStyleForRoom=%s",
			functionStatus("GetProfile"),
			functionStatus("LoadProfile"),
			functionStatus("GetRoomStyleForRoom"),
			functionStatus("GetRoomFloorStyle"),
			functionStatus("SetRoomFloorStyleForRoom")
		))

		local profile, profileSource = getOrLoadProfile(player)

		if not profile then
			warn(string.format(
				"[DebugRoomFloorStylePersistence] Profile is not loaded and could not be loaded. status=%s",
				tostring(profileSource)
			))
		else
			if profileSource == "cached" then
				print("[DebugRoomFloorStylePersistence] Using cached profile.")
			else
				print("[DebugRoomFloorStylePersistence] Loaded profile via RoomPersistence.LoadProfile.")
			end

			local style, styleMessage = RoomPersistence.GetRoomStyleForRoom(player, ROOM_ID)
			local floorStyleId = RoomPersistence.GetRoomFloorStyle(player, ROOM_ID)

			print(string.format(
				"[DebugRoomFloorStylePersistence] Current style message=%s snapshot=%s floorStyleId=%s",
				tostring(styleMessage),
				style and tostring(style.FloorStyleId) or "nil",
				tostring(floorStyleId)
			))

			if SET_STYLE then
				local ok, setMessage, updatedStyle = RoomPersistence.SetRoomFloorStyleForRoom(player, ROOM_ID, TEST_STYLE_ID, {
					AllowStarter = true,
				})

				print(string.format(
					"[DebugRoomFloorStylePersistence] SetRoomFloorStyleForRoom(%s) ok=%s message=%s snapshot=%s",
					tostring(TEST_STYLE_ID),
					tostring(ok),
					tostring(setMessage),
					updatedStyle and tostring(updatedStyle.FloorStyleId) or "nil"
				))

				if ok and updatedStyle then
					floorStyleId = updatedStyle.FloorStyleId
				else
					floorStyleId = RoomPersistence.GetRoomFloorStyle(player, ROOM_ID)
				end

				print(string.format(
					"[DebugRoomFloorStylePersistence] GetRoomFloorStyle after set=%s",
					tostring(RoomPersistence.GetRoomFloorStyle(player, ROOM_ID))
				))
			end

			if APPLY_TO_ACTIVE_ROOM then
				local activeRoom = findActiveOwnedRoom(player, ROOM_ID)

				if not activeRoom then
					warn("[DebugRoomFloorStylePersistence] No active owned room model found for visual apply.")
				else
					local applied, applyMessage = RoomFloorStyleRenderer.ApplyFloorStyle(activeRoom, floorStyleId)

					print(string.format(
						"[DebugRoomFloorStylePersistence] ApplyFloorStyle room=%s style=%s ok=%s message=%s",
						activeRoom:GetFullName(),
						tostring(floorStyleId),
						tostring(applied),
						tostring(applyMessage)
					))
				end
			end
		end
	end
end
