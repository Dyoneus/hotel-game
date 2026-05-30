-- Client-only black void/background for Hotel rooms.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local activeRooms = Workspace:WaitForChild("ActiveRooms")

local originalLighting = {
	Ambient = Lighting.Ambient,
	OutdoorAmbient = Lighting.OutdoorAmbient,
	FogColor = Lighting.FogColor,
	FogStart = Lighting.FogStart,
	FogEnd = Lighting.FogEnd,
	Brightness = Lighting.Brightness,
	ClockTime = Lighting.ClockTime,
	ColorShift_Bottom = Lighting.ColorShift_Bottom,
	ColorShift_Top = Lighting.ColorShift_Top,
}

local originalAtmosphereProperties = {}

local VOID_FOLDER_NAME = "HotelVoidBackgroundLocal"
local VOID_PLANE_NAME = "HotelVoidPlane"

local BLACK = Color3.new(0, 0, 0)
local PLANE_THICKNESS = 0.12
local PLANE_BELOW_FLOOR = 0.45
local MIN_VOID_SIZE = 800
local MAX_VOID_SIZE = 6000
local VOID_SIZE_MULTIPLIER = 10
local UPDATE_INTERVAL_SECONDS = 0.25

local voidFolder = nil
local voidPlane = nil
local playerRoomVoidActive = false
local lastUpdateAt = 0

local function getCurrentRoomModel()
	local roomName = player:GetAttribute("CurrentRoomName")

	if typeof(roomName) ~= "string" or roomName == "" then
		return nil
	end

	return activeRooms:FindFirstChild(roomName)
end

local function currentRoomIsPlayerRoom(roomModel)
	if not roomModel then
		return false
	end

	local roomType = roomModel:GetAttribute("RoomType")

	if roomType == "PlayerRoom" then
		return true
	end

	if roomType == "PublicSpace" then
		return false
	end

	if roomModel.Name:sub(1, #"Public_") == "Public_" then
		return false
	end

	if roomModel.Name:sub(1, #"Room_") == "Room_" then
		return true
	end

	return false
end

local function shouldUsePlayerRoomVoid()
	local controlMode = player:GetAttribute("ControlMode") or "Hotel"

	if controlMode ~= "Hotel" then
		return false
	end

	return currentRoomIsPlayerRoom(getCurrentRoomModel())
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

local function getOrCreateVoidFolder()
	if voidFolder and voidFolder.Parent then
		return voidFolder
	end

	local existingFolder = Workspace:FindFirstChild(VOID_FOLDER_NAME)

	if existingFolder and existingFolder:IsA("Folder") then
		voidFolder = existingFolder
		return voidFolder
	end

	voidFolder = Instance.new("Folder")
	voidFolder.Name = VOID_FOLDER_NAME
	voidFolder.Parent = Workspace

	return voidFolder
end

local function nameStartsWithHotelVoid(instance)
	return typeof(instance.Name) == "string" and instance.Name:sub(1, #"HotelVoid") == "HotelVoid"
end

local function cleanupLegacyVoidObjects(preserveActivePlane)
	local activePlane = preserveActivePlane and voidPlane or nil
	local currentCamera = Workspace.CurrentCamera

	if voidFolder and voidFolder.Parent then
		for _, child in ipairs(voidFolder:GetChildren()) do
			if child ~= activePlane and nameStartsWithHotelVoid(child) then
				child:Destroy()
			end
		end
	end

	if currentCamera then
		for _, descendant in ipairs(currentCamera:GetDescendants()) do
			if descendant ~= activePlane and nameStartsWithHotelVoid(descendant) then
				descendant:Destroy()
			end
		end
	end

	for _, child in ipairs(Workspace:GetChildren()) do
		if child ~= voidFolder and child ~= activePlane and nameStartsWithHotelVoid(child) then
			child:Destroy()
		end
	end
end

local function destroyVoidGeometry()
	if voidFolder and voidFolder.Parent then
		voidFolder:Destroy()
	end

	voidFolder = nil
	voidPlane = nil

	cleanupLegacyVoidObjects(false)
end

local function configureVoidPart(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = BLACK
	part.Reflectance = 0
	part.Transparency = 0
	part.Locked = true
end

local function createVoidPart(name)
	local part = Instance.new("Part")
	part.Name = name
	configureVoidPart(part)
	part.Parent = getOrCreateVoidFolder()

	return part
end

local function getVoidPlane()
	if voidPlane and voidPlane.Parent then
		return voidPlane
	end

	local folder = getOrCreateVoidFolder()
	local existingPlane = folder:FindFirstChild(VOID_PLANE_NAME)

	if existingPlane and existingPlane:IsA("BasePart") then
		voidPlane = existingPlane
		configureVoidPart(voidPlane)
		return voidPlane
	end

	voidPlane = createVoidPart(VOID_PLANE_NAME)
	return voidPlane
end

local function setVoidVisible(isVisible)
	local folder = voidFolder or Workspace:FindFirstChild(VOID_FOLDER_NAME)

	if folder and folder:IsA("Folder") then
		voidFolder = folder
	end

	if voidPlane then
		voidPlane.Transparency = isVisible and 0 or 1
	elseif voidFolder then
		local existingPlane = voidFolder:FindFirstChild(VOID_PLANE_NAME)

		if existingPlane and existingPlane:IsA("BasePart") then
			voidPlane = existingPlane
			configureVoidPart(voidPlane)
			voidPlane.Transparency = isVisible and 0 or 1
		end
	end

	if voidFolder then
		for _, child in ipairs(voidFolder:GetChildren()) do
			if child ~= voidPlane and nameStartsWithHotelVoid(child) then
				child:Destroy()
			end
		end
	end
end

local function rememberAtmosphere(atmosphere)
	if originalAtmosphereProperties[atmosphere] then
		return
	end

	originalAtmosphereProperties[atmosphere] = {
		Density = atmosphere.Density,
		Offset = atmosphere.Offset,
		Color = atmosphere.Color,
		Decay = atmosphere.Decay,
		Glare = atmosphere.Glare,
		Haze = atmosphere.Haze,
	}
end

local function suppressAtmosphereGradient()
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Atmosphere") then
			rememberAtmosphere(child)
			child.Density = 0
			child.Offset = 0
			child.Glare = 0
			child.Haze = 0
		end
	end
end

local function restoreAtmospheres()
	for atmosphere, properties in pairs(originalAtmosphereProperties) do
		if atmosphere.Parent then
			atmosphere.Density = properties.Density
			atmosphere.Offset = properties.Offset
			atmosphere.Color = properties.Color
			atmosphere.Decay = properties.Decay
			atmosphere.Glare = properties.Glare
			atmosphere.Haze = properties.Haze
		end
	end
end

local function restoreLighting()
	Lighting.Ambient = originalLighting.Ambient
	Lighting.OutdoorAmbient = originalLighting.OutdoorAmbient
	Lighting.FogColor = originalLighting.FogColor
	Lighting.FogStart = originalLighting.FogStart
	Lighting.FogEnd = originalLighting.FogEnd
	Lighting.Brightness = originalLighting.Brightness
	Lighting.ClockTime = originalLighting.ClockTime
	Lighting.ColorShift_Bottom = originalLighting.ColorShift_Bottom
	Lighting.ColorShift_Top = originalLighting.ColorShift_Top

	restoreAtmospheres()
end

local function applyPlayerRoomVoidLighting()
	Lighting.Ambient = originalLighting.Ambient
	Lighting.OutdoorAmbient = originalLighting.OutdoorAmbient
	Lighting.FogColor = BLACK
	Lighting.FogStart = 100000
	Lighting.FogEnd = 100001
	Lighting.Brightness = originalLighting.Brightness
	Lighting.ClockTime = originalLighting.ClockTime
	Lighting.ColorShift_Bottom = originalLighting.ColorShift_Bottom
	Lighting.ColorShift_Top = originalLighting.ColorShift_Top

	suppressAtmosphereGradient()
end

local function getReferenceFrame()
	local roomModel = getCurrentRoomModel()

	if not roomModel then
		return nil, nil, nil
	end

	local floor = getWalkableFloor(roomModel)

	if floor then
		return floor.CFrame, floor.Size, floor.Position
	end

	local pivot = roomModel:GetPivot()
	local _, roomSize = roomModel:GetBoundingBox()

	return pivot, roomSize, pivot.Position
end

local function updateVoidGeometry()
	if not shouldUsePlayerRoomVoid() then
		restoreLighting()
		destroyVoidGeometry()
		return
	end

	local referenceCFrame, referenceSize = getReferenceFrame()

	if not referenceCFrame or not referenceSize then
		destroyVoidGeometry()
		applyPlayerRoomVoidLighting()
		return
	end

	local maxDimension = math.max(referenceSize.X, referenceSize.Z)
	local voidSize = math.clamp(maxDimension * VOID_SIZE_MULTIPLIER, MIN_VOID_SIZE, MAX_VOID_SIZE)
	local floorBottomLocalY = -referenceSize.Y / 2

	applyPlayerRoomVoidLighting()
	cleanupLegacyVoidObjects(true)

	local plane = getVoidPlane()
	plane.Size = Vector3.new(voidSize, PLANE_THICKNESS, voidSize)
	plane.CFrame = referenceCFrame * CFrame.new(0, floorBottomLocalY - PLANE_THICKNESS / 2 - PLANE_BELOW_FLOOR, 0)

	setVoidVisible(true)
end

local function setPlayerRoomVoidActive(isActive)
	if playerRoomVoidActive == isActive then
		if playerRoomVoidActive then
			updateVoidGeometry()
		else
			restoreLighting()
			destroyVoidGeometry()
		end

		return
	end

	playerRoomVoidActive = isActive

	if playerRoomVoidActive then
		updateVoidGeometry()
	else
		restoreLighting()
		destroyVoidGeometry()
	end
end

local function refreshMode()
	setPlayerRoomVoidActive(shouldUsePlayerRoomVoid())
end

player:GetAttributeChangedSignal("ControlMode"):Connect(refreshMode)
player:GetAttributeChangedSignal("CurrentRoomName"):Connect(function()
	lastUpdateAt = 0
	destroyVoidGeometry()
	refreshMode()
end)

activeRooms.ChildAdded:Connect(function()
	lastUpdateAt = 0
	refreshMode()
end)

activeRooms.ChildRemoved:Connect(function()
	lastUpdateAt = 0
	refreshMode()
end)

RunService.RenderStepped:Connect(function()
	if not playerRoomVoidActive then
		return
	end

	local now = os.clock()

	if now - lastUpdateAt < UPDATE_INTERVAL_SECONDS then
		return
	end

	lastUpdateAt = now
	updateVoidGeometry()
end)

script.Destroying:Connect(function()
	restoreLighting()
	destroyVoidGeometry()
end)

cleanupLegacyVoidObjects(false)
refreshMode()
