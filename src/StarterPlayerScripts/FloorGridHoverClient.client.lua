local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GridConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GridConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local activeRooms = Workspace:WaitForChild("ActiveRooms")

local HOVER_BOX_HEIGHT = 0.06
local RAYCAST_DISTANCE = 5000

local anyMajorMenuOpen = false
local openMajorMenuName = nil
local hoverPart = nil
local renderConnection = nil
local hoverRefreshToken = 0

local function getOrCreateClientEvent(name)
	local clientEvents = playerGui:FindFirstChild("ClientEvents")

	if clientEvents then
		if not clientEvents:IsA("Folder") then
			error("PlayerGui.ClientEvents exists but is not a Folder.")
		end
	else
		clientEvents = Instance.new("Folder")
		clientEvents.Name = "ClientEvents"
		clientEvents.Parent = playerGui
	end

	local existing = clientEvents:FindFirstChild(name)

	if existing then
		if not existing:IsA("BindableEvent") then
			error(name .. " exists but is not a BindableEvent.")
		end

		return existing
	end

	local bindableEvent = Instance.new("BindableEvent")
	bindableEvent.Name = name
	bindableEvent.Parent = clientEvents

	return bindableEvent
end

local majorMenuStateChanged = getOrCreateClientEvent("MajorMenuStateChanged")

majorMenuStateChanged.Event:Connect(function(isOpen, menuName)
	if isOpen == true then
		anyMajorMenuOpen = true
		openMajorMenuName = menuName
	elseif openMajorMenuName == menuName then
		anyMajorMenuOpen = false
		openMajorMenuName = nil
	end
end)

local function getHoverPart()
	if hoverPart and hoverPart.Parent then
		return hoverPart
	end

	hoverPart = Instance.new("Part")
	hoverPart.Name = "FloorGridHoverPreview"
	hoverPart.Anchored = true
	hoverPart.CanCollide = false
	hoverPart.CanTouch = false
	hoverPart.CanQuery = false
	hoverPart.CastShadow = false
	hoverPart.Material = Enum.Material.Neon
	hoverPart.Color = Color3.fromRGB(80, 210, 255)
	hoverPart.Transparency = 0.48
	hoverPart.Size = Vector3.new(GridConfig.HOVER_TILE_SIZE, HOVER_BOX_HEIGHT, GridConfig.HOVER_TILE_SIZE)
	hoverPart.Parent = Workspace

	return hoverPart
end

local function hideHover()
	if hoverPart then
		hoverPart.Transparency = 1
	end
end

local updateHover = nil

local function refreshHoverNow()
	hideHover()
	updateHover()
end

local function showHover(cframe, tileSize)
	local part = getHoverPart()
	part.CFrame = cframe
	part.Size = Vector3.new(tileSize, HOVER_BOX_HEIGHT, tileSize)
	part.Transparency = 0.48
end

local function getCurrentRoomModel()
	local roomName = player:GetAttribute("CurrentRoomName")

	if typeof(roomName) ~= "string" or roomName == "" then
		return nil
	end

	return activeRooms:FindFirstChild(roomName)
end

local function getCurrentFloor(roomModel)
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

local function shouldHideHover()
	return player:GetAttribute("ControlMode") ~= "Hotel"
		or player:GetAttribute("CatalogPlacementActive") == true
		or anyMajorMenuOpen == true
end

local function getMouseFloorHit(floor)
	local camera = Workspace.CurrentCamera

	if not camera then
		return nil
	end

	local mousePosition = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePosition.X, mousePosition.Y)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { floor }
	raycastParams.IgnoreWater = true

	local result = Workspace:Raycast(ray.Origin, ray.Direction * RAYCAST_DISTANCE, raycastParams)

	if result and result.Instance == floor then
		return result.Position
	end

	return nil
end

updateHover = function()
	if shouldHideHover() then
		hideHover()
		return
	end

	local roomModel = getCurrentRoomModel()

	if not roomModel then
		hideHover()
		return
	end

	local floor = getCurrentFloor(roomModel)

	if not floor then
		hideHover()
		return
	end

	if not GridConfig.UsesTileGrid(roomModel, floor) then
		hideHover()
		return
	end

	local floorTopY = GridConfig.GetFloorTopY(floor)

	if not floorTopY then
		hideHover()
		return
	end

	local hitPosition = getMouseFloorHit(floor)

	if not hitPosition then
		hideHover()
		return
	end

	local tileSize = GridConfig.GetTileSize(roomModel, floor)
	local _, snappedLocalPosition = GridConfig.SnapWorldToTileCenter(floor, hitPosition, tileSize)

	if not snappedLocalPosition then
		hideHover()
		return
	end

	local localY = floor.Size.Y / 2 + HOVER_BOX_HEIGHT / 2 + 0.01
	local worldPosition = GridConfig.FloorLocalToWorld(
		floor,
		Vector3.new(snappedLocalPosition.X, localY, snappedLocalPosition.Z)
	)

	if not worldPosition then
		hideHover()
		return
	end

	worldPosition = Vector3.new(worldPosition.X, floorTopY + HOVER_BOX_HEIGHT / 2 + 0.01, worldPosition.Z)

	local floorRotation = floor.CFrame - floor.CFrame.Position

	showHover(CFrame.new(worldPosition) * floorRotation, tileSize)
end

local function scheduleHoverRefresh()
	hoverRefreshToken += 1
	local token = hoverRefreshToken

	hideHover()
	task.defer(function()
		if token == hoverRefreshToken then
			updateHover()
		end
	end)

	task.delay(0.25, function()
		if token == hoverRefreshToken then
			updateHover()
		end
	end)

	task.delay(1, function()
		if token == hoverRefreshToken then
			updateHover()
		end
	end)
end

renderConnection = RunService.RenderStepped:Connect(updateHover)

player:GetAttributeChangedSignal("CurrentRoomName"):Connect(scheduleHoverRefresh)
player:GetAttributeChangedSignal("ControlMode"):Connect(scheduleHoverRefresh)
player.CharacterAdded:Connect(scheduleHoverRefresh)

activeRooms.ChildAdded:Connect(function()
	task.defer(refreshHoverNow)
end)

activeRooms.ChildRemoved:Connect(function()
	task.defer(refreshHoverNow)
end)

script.Destroying:Connect(function()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	if hoverPart then
		hoverPart:Destroy()
		hoverPart = nil
	end
end)
