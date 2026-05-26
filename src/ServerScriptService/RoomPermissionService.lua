-- Foundation service for future room/furniture permissions.
-- Patch 10B only defines helpers; gameplay scripts are not integrated yet.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local RoomPersistence = require(ServerScriptService:WaitForChild("RoomPersistence"))

local RoomPermissionService = {}

local activeRooms = workspace:WaitForChild("ActiveRooms")

local function isPlayerInstance(value)
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function isModel(value)
	return typeof(value) == "Instance" and value:IsA("Model")
end

local function isPositiveInteger(value)
	return typeof(value) == "number"
		and value == value
		and value > 0
		and value < math.huge
		and value == math.floor(value)
end

function RoomPermissionService.GetRoomOwnerUserId(roomModel)
	if not isModel(roomModel) then
		return nil
	end

	local ownerUserId = roomModel:GetAttribute("OwnerUserId")

	if isPositiveInteger(ownerUserId) then
		return ownerUserId
	end

	local fallbackUserId = tonumber(tostring(roomModel.Name):match("^Room_(%d+)$"))

	if isPositiveInteger(fallbackUserId) then
		return fallbackUserId
	end

	return nil
end

function RoomPermissionService.IsPlayerRoom(roomModel)
	if not isModel(roomModel) then
		return false
	end

	local roomType = roomModel:GetAttribute("RoomType")

	if roomType == "PlayerRoom" then
		return true
	end

	if roomType == "PublicSpace" then
		return false
	end

	return tostring(roomModel.Name):match("^Room_%d+$") ~= nil
end

function RoomPermissionService.GetRoomOwnerPlayer(roomModel)
	local ownerUserId = RoomPermissionService.GetRoomOwnerUserId(roomModel)

	if not ownerUserId then
		return nil
	end

	return Players:GetPlayerByUserId(ownerUserId)
end

function RoomPermissionService.GetRoomOwnerProfile(roomModel)
	local ownerPlayer = RoomPermissionService.GetRoomOwnerPlayer(roomModel)

	if not ownerPlayer then
		return nil
	end

	return RoomPersistence.GetProfile(ownerPlayer)
end

function RoomPermissionService.IsRoomOwner(actorPlayer, roomModel)
	if not isPlayerInstance(actorPlayer) then
		return false
	end

	return RoomPermissionService.GetRoomOwnerUserId(roomModel) == actorPlayer.UserId
end

function RoomPermissionService.CanEditRoom(actorPlayer, roomModel)
	if not isPlayerInstance(actorPlayer) or not RoomPermissionService.IsPlayerRoom(roomModel) then
		return false
	end

	if RoomPermissionService.IsRoomOwner(actorPlayer, roomModel) then
		return true
	end

	local ownerPlayer = RoomPermissionService.GetRoomOwnerPlayer(roomModel)

	if not ownerPlayer or not RoomPermissionService.GetRoomOwnerProfile(roomModel) then
		return false
	end

	return RoomPersistence.IsRoomEditor(ownerPlayer, actorPlayer.UserId)
end

function RoomPermissionService.CanPlaceFurniture(actorPlayer, roomModel)
	-- Future patches may split Place from Edit with RoomActions.Place.
	return RoomPermissionService.CanEditRoom(actorPlayer, roomModel)
end

function RoomPermissionService.GetRoomModelFromFurniture(furnitureModel)
	if not isModel(furnitureModel) then
		return nil
	end

	local current = furnitureModel

	while current and current ~= workspace do
		if current:IsA("Model") and current.Parent == activeRooms then
			return current
		end

		current = current.Parent
	end

	return nil
end

function RoomPermissionService.GetFurniturePersistentId(furnitureModel)
	if not isModel(furnitureModel) then
		return nil
	end

	local persistentId = furnitureModel:GetAttribute("PersistentId")

	if typeof(persistentId) ~= "string" or persistentId == "" or persistentId:match("%S") == nil then
		return nil
	end

	return persistentId
end

function RoomPermissionService.CanMoveFurniture(actorPlayer, furnitureModel)
	local roomModel = RoomPermissionService.GetRoomModelFromFurniture(furnitureModel)

	if not roomModel then
		return false
	end

	return RoomPermissionService.CanEditRoom(actorPlayer, roomModel)
end

function RoomPermissionService.CanRotateFurniture(actorPlayer, furnitureModel)
	if not isPlayerInstance(actorPlayer) then
		return false
	end

	local roomModel = RoomPermissionService.GetRoomModelFromFurniture(furnitureModel)

	if not roomModel then
		return false
	end

	if RoomPermissionService.CanEditRoom(actorPlayer, roomModel) then
		return true
	end

	local ownerPlayer = RoomPermissionService.GetRoomOwnerPlayer(roomModel)
	local persistentId = RoomPermissionService.GetFurniturePersistentId(furnitureModel)

	if not ownerPlayer or not persistentId then
		return false
	end

	return RoomPersistence.IsFurnitureActionAllowed(ownerPlayer, persistentId, "Rotate", actorPlayer.UserId)
end

function RoomPermissionService.CanPickUpFurniture(actorPlayer, furnitureModel)
	-- Owner-only for now. Room editors should not be able to remove furniture
	-- until explicit pickup/ownership rules exist.
	local roomModel = RoomPermissionService.GetRoomModelFromFurniture(furnitureModel)

	return RoomPermissionService.IsRoomOwner(actorPlayer, roomModel)
end

function RoomPermissionService.CanUseFurniture(actorPlayer, furnitureModel, actionName)
	-- Current behavior remains broad use for furniture in the actor's current room.
	-- Future patches can add furniture opt-in attributes and per-action enforcement.
	if not isPlayerInstance(actorPlayer) or not isModel(furnitureModel) then
		return false
	end

	local roomModel = RoomPermissionService.GetRoomModelFromFurniture(furnitureModel)
	local currentRoomName = actorPlayer:GetAttribute("CurrentRoomName")

	if not roomModel or typeof(currentRoomName) ~= "string" or currentRoomName == "" then
		return false
	end

	return roomModel.Name == currentRoomName
end

return RoomPermissionService
