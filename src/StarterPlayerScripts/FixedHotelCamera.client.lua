--Explorer/StarterPlayerScripts/FixedHotelCamera.lua
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local activeRooms = workspace:WaitForChild("ActiveRooms")

-- Camera settings
local CAMERA_OFFSET = Vector3.new(50, 45, 40)
local FIELD_OF_VIEW = 50
--local cameraPosition = Vector3.new(50, 45, 40)
--local lookAtPosition = Vector3.new(0, 0, 0)
--local fieldOfView = 50

local function getCurrentRoomModel()
	local roomName = player:GetAttribute("CurrentRoomName")

	if not roomName then
		return nil
	end

	return activeRooms:FindFirstChild(roomName)
end

local function getLookAtPosition()
	local roomModel = getCurrentRoomModel()

	if not roomModel then
		return Vector3.new(0, 0, 0)
	end

	local roomFolder = roomModel:FindFirstChild("Room")

	if not roomFolder then
		return roomModel:GetPivot().Position
	end

	local floor = roomFolder:FindFirstChild("WalkableFloor")

	if floor then
		return floor.Position
	end

	return roomModel:GetPivot().Position
end

local function updateCamera()
	local controlMode = player:GetAttribute("ControlMode") or "Hotel"

	if controlMode ~= "Hotel" then
		return
	end

	local lookAtPosition = getLookAtPosition()

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FIELD_OF_VIEW
	camera.CFrame = CFrame.lookAt(lookAtPosition + CAMERA_OFFSET, lookAtPosition)
end

local function updateCameraMode()
	local controlMode = player:GetAttribute("ControlMode") or "Hotel"

	if controlMode ~= "Hotel" then
		camera.CameraType = Enum.CameraType.Custom
	end
end

player:GetAttributeChangedSignal("ControlMode"):Connect(updateCameraMode)
updateCameraMode()

RunService:BindToRenderStep(
	"FixedHotelCamera",
	Enum.RenderPriority.Camera.Value + 1,
	updateCamera
)