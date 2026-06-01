-- Central server-side helpers for room and furniture permissions.
-- Patch 10F adds furniture-specific permission metadata checks only.
-- Open/Close gameplay handlers are intentionally added later.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RoomPersistence = require(ServerScriptService:WaitForChild("RoomPersistence"))
local FurnitureCatalogConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FurnitureCatalogConfig"))

local RoomPermissionService = {}

local activeRooms = workspace:WaitForChild("ActiveRooms")
local SUPPORT_ATTRIBUTE_BY_ACTION = {
	OpenClose = "SupportsOpenClose",
	Open = "SupportsOpen",
	Close = "SupportsClose",
	ToggleOpen = "SupportsToggleOpen",
	Rotate = "SupportsRotate",
	Use = "SupportsUse",
}
local SUPPORT_ACTION_ORDER = {
	"OpenClose",
	"Open",
	"Close",
	"ToggleOpen",
	"Rotate",
	"Use",
}

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

local function normalizeActionName(actionName)
	if typeof(actionName) ~= "string" then
		return nil
	end

	local normalized = actionName:match("^%s*(.-)%s*$")

	if not normalized or normalized == "" then
		return nil
	end

	return normalized
end

local function copyActionList(actionList)
	local copy = {}

	if typeof(actionList) ~= "table" then
		return copy
	end

	for _, actionName in ipairs(actionList) do
		local normalizedActionName = normalizeActionName(actionName)

		if normalizedActionName then
			table.insert(copy, normalizedActionName)
		end
	end

	return copy
end

local function addActionIfMissing(actions, seenActions, actionName)
	local normalizedActionName = normalizeActionName(actionName)

	if not normalizedActionName or seenActions[normalizedActionName] then
		return
	end

	seenActions[normalizedActionName] = true
	table.insert(actions, normalizedActionName)
end

local function parsePermissionActionsAttribute(value)
	local actions = {}
	local seenActions = {}

	if typeof(value) ~= "string" then
		return nil
	end

	for actionName in string.gmatch(value, "([^,]+)") do
		addActionIfMissing(actions, seenActions, actionName)
	end

	return actions
end

local function getSupportAttributeActions(furnitureModel)
	local actions = {}
	local seenActions = {}

	for _, actionName in ipairs(SUPPORT_ACTION_ORDER) do
		local attributeName = SUPPORT_ATTRIBUTE_BY_ACTION[actionName]

		if attributeName and furnitureModel:GetAttribute(attributeName) == true then
			addActionIfMissing(actions, seenActions, actionName)
		end
	end

	return actions
end

local function getFurnitureCatalogItem(furnitureModel)
	if not isModel(furnitureModel) then
		return nil
	end

	local candidateIds = {
		furnitureModel:GetAttribute("TemplateId"),
		furnitureModel:GetAttribute("PickupTemplateId"),
		furnitureModel.Name,
	}

	for _, candidateId in ipairs(candidateIds) do
		if typeof(candidateId) == "string"
			and candidateId ~= ""
			and candidateId:match("%S") then

			local item = FurnitureCatalogConfig.GetItem(candidateId)

			if typeof(item) == "table" then
				return item
			end
		end
	end

	return nil
end

local function getCatalogPermissionActions(furnitureModel)
	local item = getFurnitureCatalogItem(furnitureModel)

	if typeof(item) ~= "table" then
		return {}
	end

	local actions = copyActionList(item.PermissionActions)

	if item.SupportsOpenClose == true then
		local seenActions = {}

		for _, actionName in ipairs(actions) do
			seenActions[actionName] = true
		end

		addActionIfMissing(actions, seenActions, "OpenClose")
	end

	return actions
end

function RoomPermissionService.GetRoomOwnerUserId(roomModel)
	if not isModel(roomModel) then
		return nil
	end

	local ownerUserId = roomModel:GetAttribute("OwnerUserId")

	if isPositiveInteger(ownerUserId) then
		return ownerUserId
	end

	local roomName = tostring(roomModel.Name)
	local fallbackUserId = tonumber(roomName:match("^Room_(%d+)$") or roomName:match("^Room_(%d+)_[%w_-]+$"))

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

	local roomName = tostring(roomModel.Name)
	return roomName:match("^Room_%d+$") ~= nil or roomName:match("^Room_%d+_[%w_-]+$") ~= nil
end

function RoomPermissionService.IsPublicRoom(roomModel)
	return isModel(roomModel) and roomModel:GetAttribute("RoomType") == "PublicSpace"
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

function RoomPermissionService.GetFurniturePermissionActions(furnitureModel)
	if not isModel(furnitureModel) then
		return {}
	end

	local permissionActionsAttribute = furnitureModel:GetAttribute("PermissionActions")

	if typeof(permissionActionsAttribute) == "string" then
		return parsePermissionActionsAttribute(permissionActionsAttribute)
	end

	local attributeActions = getSupportAttributeActions(furnitureModel)

	if #attributeActions > 0 then
		return attributeActions
	end

	return getCatalogPermissionActions(furnitureModel)
end

function RoomPermissionService.FurnitureSupportsPermission(furnitureModel, actionName)
	local normalizedActionName = normalizeActionName(actionName)

	if not isModel(furnitureModel) or not normalizedActionName then
		return false
	end

	for _, supportedActionName in ipairs(RoomPermissionService.GetFurniturePermissionActions(furnitureModel)) do
		if supportedActionName == normalizedActionName then
			return true
		end
	end

	return false
end

function RoomPermissionService.FurnitureAllowsPublicUse(furnitureModel, actionName)
	if not isModel(furnitureModel) then
		return false
	end

	local normalizedActionName = normalizeActionName(actionName)

	if normalizedActionName == "OpenClose" then
		return furnitureModel:GetAttribute("PublicUse") == true
			or furnitureModel:GetAttribute("PublicOpenClose") == true
			or furnitureModel:GetAttribute("AllowPublicOpenClose") == true
	end

	return furnitureModel:GetAttribute("PublicUse") == true
end

function RoomPermissionService.FurnitureSupportsPublicSit(furnitureModel)
	if not isModel(furnitureModel) then
		return false
	end

	if furnitureModel:GetAttribute("DefaultAction") == "Sit" then
		return true
	end

	local seat = furnitureModel:FindFirstChild("Seat", true)
	local sitPoint = furnitureModel:FindFirstChild("SitPoint", true)

	return seat ~= nil
		and seat:IsA("Seat")
		and sitPoint ~= nil
		and (sitPoint:IsA("BasePart") or sitPoint:IsA("Attachment"))
end

function RoomPermissionService.GetSupportedFurniturePermissionSummary(furnitureModel)
	local actions = RoomPermissionService.GetFurniturePermissionActions(furnitureModel)

	return {
		SupportsOpenClose = RoomPermissionService.FurnitureSupportsPermission(furnitureModel, "OpenClose"),
		PermissionActions = copyActionList(actions),
	}
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

function RoomPermissionService.CanOpenCloseFurniture(actorPlayer, furnitureModel)
	if not isPlayerInstance(actorPlayer) or not isModel(furnitureModel) then
		return false
	end

	if not RoomPermissionService.FurnitureSupportsPermission(furnitureModel, "OpenClose") then
		return false
	end

	local roomModel = RoomPermissionService.GetRoomModelFromFurniture(furnitureModel)

	if not roomModel then
		return false
	end

	if RoomPermissionService.IsPublicRoom(roomModel) then
		return RoomPermissionService.FurnitureAllowsPublicUse(furnitureModel, "OpenClose")
	end

	if RoomPermissionService.IsRoomOwner(actorPlayer, roomModel) then
		return true
	end

	if RoomPermissionService.CanEditRoom(actorPlayer, roomModel) then
		return true
	end

	local ownerPlayer = RoomPermissionService.GetRoomOwnerPlayer(roomModel)
	local persistentId = RoomPermissionService.GetFurniturePersistentId(furnitureModel)

	if not ownerPlayer or not persistentId then
		return false
	end

	return RoomPersistence.IsFurnitureActionAllowed(
		ownerPlayer,
		persistentId,
		"OpenClose",
		actorPlayer.UserId
	)
end

function RoomPermissionService.CanUseFurniture(actorPlayer, furnitureModel, actionName)
	if not isPlayerInstance(actorPlayer) or not isModel(furnitureModel) then
		return false
	end

	local roomModel = RoomPermissionService.GetRoomModelFromFurniture(furnitureModel)
	local currentRoomName = actorPlayer:GetAttribute("CurrentRoomName")

	if not roomModel or typeof(currentRoomName) ~= "string" or currentRoomName == "" then
		return false
	end

	if roomModel.Name ~= currentRoomName then
		return false
	end

	if RoomPermissionService.IsPublicRoom(roomModel) then
		local normalizedActionName = normalizeActionName(actionName)

		if normalizedActionName == "Sit" then
			return RoomPermissionService.FurnitureSupportsPublicSit(furnitureModel)
		end

		if normalizedActionName == "OpenClose" then
			return RoomPermissionService.CanOpenCloseFurniture(actorPlayer, furnitureModel)
		end

		return RoomPermissionService.FurnitureAllowsPublicUse(furnitureModel, normalizedActionName)
	end

	return true
end

return RoomPermissionService
