-- Studio helper: preview a runtime room floor finish without saving it.
--
-- Run this manually in Roblox Studio Command Bar or from a temporary Script.
-- Select an active room Model, any descendant inside it, or let the helper use
-- the first Model under workspace.ActiveRooms.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")

local FLOOR_STYLE_ID = "Wood"
local CLEAR_ONLY = false

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local RoomFloorStyleRenderer = require(sharedFolder:WaitForChild("RoomFloorStyleRenderer"))

local function isRoomModel(model)
	if not model or not model:IsA("Model") then
		return false
	end

	local roomFolder = model:FindFirstChild("Room")
	local walkableFloor = roomFolder and roomFolder:FindFirstChild("WalkableFloor")

	return walkableFloor ~= nil and walkableFloor:IsA("BasePart")
end

local function findRoomModelFromInstance(instance)
	local current = instance

	while current do
		if isRoomModel(current) then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function getSelectedRoomModel()
	for _, instance in ipairs(Selection:Get()) do
		local roomModel = findRoomModelFromInstance(instance)

		if roomModel then
			return roomModel
		end
	end

	return nil
end

local function getFirstActiveRoomModel()
	local activeRooms = workspace:FindFirstChild("ActiveRooms")

	if not activeRooms then
		return nil
	end

	for _, child in ipairs(activeRooms:GetChildren()) do
		if isRoomModel(child) then
			return child
		end
	end

	return nil
end

local roomModel = getSelectedRoomModel() or getFirstActiveRoomModel()

if not roomModel then
	warn("[PreviewRoomFloorStyle] Select an active room model or join a room first.")
else
	local success, message

	if CLEAR_ONLY then
		success, message = RoomFloorStyleRenderer.ClearRuntimeFloorStyle(roomModel)
	else
		success, message = RoomFloorStyleRenderer.ApplyFloorStyle(roomModel, FLOOR_STYLE_ID, {
			IsStudioPreview = true,
		})
	end

	if success then
		print(string.format("[PreviewRoomFloorStyle] %s %s", roomModel:GetFullName(), message))
	else
		warn(string.format("[PreviewRoomFloorStyle] %s %s", roomModel:GetFullName(), message))
	end
end
