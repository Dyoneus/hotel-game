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
local USE_ISOMETRIC_ROOM_CAMERA = true
local DEBUG_ISOMETRIC_CAMERA = false

local ISOMETRIC_CAMERA_FOV = 35
local ISOMETRIC_CAMERA_YAW_DEGREES = 45
local ISOMETRIC_CAMERA_PITCH_DEGREES = 35
local ISOMETRIC_CAMERA_DISTANCE = 24
local ISOMETRIC_CAMERA_DISTANCE_SCALE = 1.8
local ISOMETRIC_CAMERA_MIN_DISTANCE = 42
local ISOMETRIC_CAMERA_MAX_DISTANCE = 180
local ISOMETRIC_CAMERA_HEIGHT_OFFSET = 2
local ISOMETRIC_ROOM_CENTER_OFFSET = Vector3.new(0, 0, 0)

local LEGACY_ISOMETRIC_DIRECTION = Vector3.new(50, 45, 40).Unit
local LEGACY_FIELD_OF_VIEW = 50
local LEGACY_MIN_CAMERA_DISTANCE = 28
local LEGACY_MAX_CAMERA_DISTANCE = 90
local LEGACY_ROOM_DISTANCE_MULTIPLIER = 1.6
local CAMERA_LERP_ALPHA = 0.18

local targetCameraCFrame = nil

local function debugCamera(...)
	if DEBUG_ISOMETRIC_CAMERA then
		print("[FixedHotelCamera]", ...)
	end
end

local function shouldYieldToMainMenuCamera()
	if player:GetAttribute("MainMenuCameraActive") == true then
		return true
	end

	if player:GetAttribute("CurrentRoomName") ~= nil then
		return false
	end

	if player:GetAttribute("InHotelMainMenu") == true then
		return true
	end

	return player:GetAttribute("OnboardingStep") == "Complete"
end

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
		return Vector3.new(0, 0, 0), LEGACY_MIN_CAMERA_DISTANCE
	end

	local floor = getWalkableFloor(roomModel)

	if floor then
		local roomWidth, roomDepth = getFloorGridSize(roomModel, floor)
		local roomDiagonal = math.sqrt(roomWidth * roomWidth + roomDepth * roomDepth)
		local targetDistance = math.clamp(
			roomDiagonal * LEGACY_ROOM_DISTANCE_MULTIPLIER,
			LEGACY_MIN_CAMERA_DISTANCE,
			LEGACY_MAX_CAMERA_DISTANCE
		)

		return floor.Position, targetDistance
	end

	return roomModel:GetPivot().Position, LEGACY_MIN_CAMERA_DISTANCE
end

local function getIsometricCameraDirection()
	local yaw = math.rad(ISOMETRIC_CAMERA_YAW_DEGREES)
	local pitch = math.rad(ISOMETRIC_CAMERA_PITCH_DEGREES)
	local horizontalScale = math.cos(pitch)

	return Vector3.new(
		math.cos(yaw) * horizontalScale,
		math.sin(pitch),
		math.sin(yaw) * horizontalScale
	).Unit
end

local function getIsometricCameraFrame()
	local roomModel = getCurrentRoomModel()

	if not roomModel then
		return ISOMETRIC_ROOM_CENTER_OFFSET + Vector3.new(0, ISOMETRIC_CAMERA_HEIGHT_OFFSET, 0),
			ISOMETRIC_CAMERA_MIN_DISTANCE
	end

	local floor = getWalkableFloor(roomModel)
	local roomCenter
	local roomWidth
	local roomDepth

	if floor then
		roomCenter = floor.Position
		roomWidth, roomDepth = getFloorGridSize(roomModel, floor)
	else
		roomCenter = roomModel:GetPivot().Position

		local extentsSize = roomModel:GetExtentsSize()
		roomWidth = extentsSize.X
		roomDepth = extentsSize.Z
	end

	local roomExtent = math.max(roomWidth, roomDepth)
	local targetDistance = math.clamp(
		ISOMETRIC_CAMERA_DISTANCE + roomExtent * ISOMETRIC_CAMERA_DISTANCE_SCALE,
		ISOMETRIC_CAMERA_MIN_DISTANCE,
		ISOMETRIC_CAMERA_MAX_DISTANCE
	)
	local lookAtPosition = roomCenter
		+ ISOMETRIC_ROOM_CENTER_OFFSET
		+ Vector3.new(0, ISOMETRIC_CAMERA_HEIGHT_OFFSET, 0)

	debugCamera("roomExtent", roomExtent, "targetDistance", targetDistance)

	return lookAtPosition, targetDistance
end

local function updateCamera()
	if shouldYieldToMainMenuCamera() then
		targetCameraCFrame = nil
		return
	end

	local controlMode = player:GetAttribute("ControlMode") or "Hotel"

	if controlMode ~= "Hotel" then
		return
	end

	local lookAtPosition, targetDistance
	local cameraDirection
	local fieldOfView

	if USE_ISOMETRIC_ROOM_CAMERA then
		lookAtPosition, targetDistance = getIsometricCameraFrame()
		cameraDirection = getIsometricCameraDirection()
		fieldOfView = ISOMETRIC_CAMERA_FOV
	else
		lookAtPosition, targetDistance = getCameraFrame()
		cameraDirection = LEGACY_ISOMETRIC_DIRECTION
		fieldOfView = LEGACY_FIELD_OF_VIEW
	end

	local cameraOffset = cameraDirection * targetDistance

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = fieldOfView

	local shouldSnap = targetCameraCFrame == nil
	targetCameraCFrame = CFrame.lookAt(lookAtPosition + cameraOffset, lookAtPosition)

	if shouldSnap then
		camera.CFrame = targetCameraCFrame
	else
		camera.CFrame = camera.CFrame:Lerp(targetCameraCFrame, CAMERA_LERP_ALPHA)
	end
end

local function updateCameraMode()
	if shouldYieldToMainMenuCamera() then
		targetCameraCFrame = nil
		return
	end

	local controlMode = player:GetAttribute("ControlMode") or "Hotel"

	if controlMode ~= "Hotel" then
		camera.CameraType = Enum.CameraType.Custom
		targetCameraCFrame = nil
	end
end

player:GetAttributeChangedSignal("ControlMode"):Connect(updateCameraMode)
player:GetAttributeChangedSignal("CurrentRoomName"):Connect(function()
	targetCameraCFrame = nil
	updateCameraMode()
end)
player:GetAttributeChangedSignal("InHotelMainMenu"):Connect(updateCameraMode)
player:GetAttributeChangedSignal("MainMenuCameraActive"):Connect(updateCameraMode)
player:GetAttributeChangedSignal("OnboardingStep"):Connect(updateCameraMode)
updateCameraMode()

RunService:BindToRenderStep(
	"FixedHotelCamera",
	Enum.RenderPriority.Camera.Value + 1,
	updateCamera
)
