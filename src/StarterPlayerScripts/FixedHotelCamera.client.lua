--Explorer/StarterPlayerScripts/FixedHotelCamera.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local activeRooms = workspace:WaitForChild("ActiveRooms")
local shared = ReplicatedStorage:FindFirstChild("Shared")
local GridConfig = shared and shared:FindFirstChild("GridConfig") and require(shared.GridConfig) or nil

-- Camera settings
local ISOMETRIC_DIRECTION = Vector3.new(50, 45, 40).Unit
local FIELD_OF_VIEW = 50
local MIN_CAMERA_DISTANCE = 28
local MAX_CAMERA_DISTANCE = 90
local ROOM_DISTANCE_MULTIPLIER = 1.6
local CAMERA_LERP_ALPHA = 0.18

local targetCameraCFrame = nil

local function getCurrentRoomModel()
	local roomName = player:GetAttribute("CurrentRoomName")

	if not roomName then
		return nil
	end

	return activeRooms:FindFirstChild(roomName)
end

local function getWalkableFloor(roomModel)
	if not roomModel then
		return nil
	end

	local roomFolder = roomModel:FindFirstChild("Room")
	local floor = roomFolder and roomFolder:FindFirstChild("WalkableFloor")

	if floor and floor:IsA("BasePart") then
		return floor
	end

	local descendantFloor = roomModel:FindFirstChild("WalkableFloor", true)

	if descendantFloor and descendantFloor:IsA("BasePart") then
		return descendantFloor
	end

	return nil
end

local function getFloorGridSize(roomModel, floor)
	if GridConfig then
		local tileSize = GridConfig.GetTileSize(roomModel, floor)
		local gridWidth = GridConfig.GetGridWidth(roomModel, floor)
		local gridDepth = GridConfig.GetGridDepth(roomModel, floor)

		return gridWidth * tileSize, gridDepth * tileSize
	end

	return floor.Size.X, floor.Size.Z
end

local function getCameraFrame()
	local roomModel = getCurrentRoomModel()

	if not roomModel then
		return Vector3.new(0, 0, 0), MIN_CAMERA_DISTANCE
	end

	local floor = getWalkableFloor(roomModel)

	if floor then
		local roomWidth, roomDepth = getFloorGridSize(roomModel, floor)
		local roomDiagonal = math.sqrt(roomWidth * roomWidth + roomDepth * roomDepth)
		local targetDistance = math.clamp(
			roomDiagonal * ROOM_DISTANCE_MULTIPLIER,
			MIN_CAMERA_DISTANCE,
			MAX_CAMERA_DISTANCE
		)

		return floor.Position, targetDistance
	end

	return roomModel:GetPivot().Position, MIN_CAMERA_DISTANCE
end

local function updateCamera()
	local controlMode = player:GetAttribute("ControlMode") or "Hotel"

	if controlMode ~= "Hotel" then
		return
	end

	local lookAtPosition, targetDistance = getCameraFrame()
	local cameraOffset = ISOMETRIC_DIRECTION * targetDistance

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FIELD_OF_VIEW

	local shouldSnap = targetCameraCFrame == nil
	targetCameraCFrame = CFrame.lookAt(lookAtPosition + cameraOffset, lookAtPosition)

	if shouldSnap then
		camera.CFrame = targetCameraCFrame
	else
		camera.CFrame = camera.CFrame:Lerp(targetCameraCFrame, CAMERA_LERP_ALPHA)
	end
end

local function updateCameraMode()
	local controlMode = player:GetAttribute("ControlMode") or "Hotel"

	if controlMode ~= "Hotel" then
		camera.CameraType = Enum.CameraType.Custom
		targetCameraCFrame = nil
	end
end

player:GetAttributeChangedSignal("ControlMode"):Connect(updateCameraMode)
player:GetAttributeChangedSignal("CurrentRoomName"):Connect(function()
	targetCameraCFrame = nil
end)
updateCameraMode()

RunService:BindToRenderStep(
	"FixedHotelCamera",
	Enum.RenderPriority.Camera.Value + 1,
	updateCamera
)
