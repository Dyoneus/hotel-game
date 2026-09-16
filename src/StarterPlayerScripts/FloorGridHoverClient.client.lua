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
local FLOOR_HOVER_CENTER_OFFSET = HOVER_BOX_HEIGHT / 2 + 0.01
local DECORATION_HOVER_CENTER_OFFSET = 0.06
local FLOOR_DECORATION_MAX_HEIGHT = 0.35
local FLOOR_DECORATION_MAX_CENTER_OFFSET = 0.75
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

local function instanceHasWalkableSurfaceAttribute(instance)
	if typeof(instance) ~= "Instance" then
		return false
	end

	return instance:GetAttribute("WalkableSurface") == true
		or instance:GetAttribute("IsWalkableSurface") == true
		or instance:GetAttribute("IsWalkableDecoration") == true
		or instance:GetAttribute("BlocksMovement") == false
end

local function getWalkableSurfaceMarker(instance, roomModel)
	local current = instance

	while current and current ~= Workspace do
		if instanceHasWalkableSurfaceAttribute(current) then
			return current
		end

		if current == roomModel then
			break
		end

		current = current.Parent
	end

	return nil
end

local function nameLooksLikeWalkableDecoration(name)
	if typeof(name) ~= "string" then
		return false
	end

	local lowerName = string.lower(name)

	return string.find(lowerName, "rug", 1, true) ~= nil
		or string.find(lowerName, "mat", 1, true) ~= nil
		or string.find(lowerName, "carpet", 1, true) ~= nil
		or string.find(lowerName, "decorativefloor", 1, true) ~= nil
end

local function hasGeneratedFloorDecorationName(instance, roomModel)
	local current = instance

	while current and current ~= Workspace do
		if nameLooksLikeWalkableDecoration(current.Name) then
			return true
		end

		if current == roomModel then
			break
		end

		current = current.Parent
	end

	return false
end

local function isLowFloorLikePart(part, floor)
	if not floor then
		return false
	end

	if part.Size.Y > FLOOR_DECORATION_MAX_HEIGHT then
		return false
	end

	local localCenter = floor.CFrame:PointToObjectSpace(part.Position)
	local floorTopLocalY = floor.Size.Y / 2

	return math.abs(localCenter.Y - floorTopLocalY) <= FLOOR_DECORATION_MAX_CENTER_OFFSET
end

local function isWalkableSurfacePart(part, roomModel, floor)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return false
	end

	if part == floor then
		return true
	end

	return roomModel ~= nil
		and part:IsDescendantOf(roomModel)
		and (
			getWalkableSurfaceMarker(part, roomModel) ~= nil
			or (
				hasGeneratedFloorDecorationName(part, roomModel)
				and isLowFloorLikePart(part, floor)
			)
		)
end

local function getTileMaskFolder(roomModel)
	local roomFolder = roomModel and roomModel:FindFirstChild("Room")
	local tileMaskFolder = roomFolder and roomFolder:FindFirstChild("TileMask")

	if tileMaskFolder and tileMaskFolder:IsA("Folder") then
		return tileMaskFolder
	end

	return nil
end

local function isTileMaskMarkerPart(part, tileMaskFolder)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return false
	end

	if part:GetAttribute("IsWalkableTile") ~= true then
		return false
	end

	return tileMaskFolder == nil or part:IsDescendantOf(tileMaskFolder)
end

local function getIntegerAttribute(instance, attributeName)
	if typeof(instance) ~= "Instance" then
		return nil
	end

	local value = instance:GetAttribute(attributeName)

	if typeof(value) == "number" and value == value and value > 0 and value < math.huge and math.floor(value) == value then
		return value
	end

	return nil
end

local function getTileMaskMarkerCell(part, context, tileMaskFolder)
	if not context or not isTileMaskMarkerPart(part, tileMaskFolder) then
		return nil, nil
	end

	local tileX = getIntegerAttribute(part, "TileX")
	local tileZ = getIntegerAttribute(part, "TileZ")

	if not tileX or not tileZ then
		return nil, nil
	end

	if tileX < 1 or tileX > context.GridWidth or tileZ < 1 or tileZ > context.GridDepth then
		return nil, nil
	end

	return tileX, tileZ
end

local function shouldIgnoreHoverRaycastPart(part, roomModel, floor)
	if part == floor or isWalkableSurfacePart(part, roomModel, floor) then
		return false
	end

	return part.Transparency >= 1 and part.CanCollide == false
end

local function getHoverRaycastParts(roomModel, floor, context, tileMaskFolder)
	local parts = {}

	if floor and floor:IsA("BasePart") then
		table.insert(parts, floor)
	end

	if not roomModel then
		return parts
	end

	local activeTileMaskFolder = tileMaskFolder

	if not activeTileMaskFolder and context and context.UsesTileMask == true then
		activeTileMaskFolder = getTileMaskFolder(roomModel)
	end

	for _, descendant in ipairs(roomModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= floor and descendant.CanQuery then
			if activeTileMaskFolder and isTileMaskMarkerPart(descendant, activeTileMaskFolder) then
				table.insert(parts, descendant)
			elseif not shouldIgnoreHoverRaycastPart(descendant, roomModel, floor) then
				table.insert(parts, descendant)
			end
		end
	end

	return parts
end

local function getMouseFloorHit(roomModel, floor, context, tileMaskFolder)
	local camera = Workspace.CurrentCamera

	if not camera then
		return nil
	end

	local raycastParts = getHoverRaycastParts(roomModel, floor, context, tileMaskFolder)

	if #raycastParts == 0 then
		return nil
	end

	local mousePosition = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePosition.X, mousePosition.Y)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = raycastParts
	raycastParams.IgnoreWater = true

	local result = Workspace:Raycast(ray.Origin, ray.Direction * RAYCAST_DISTANCE, raycastParams)

	if result
		and (
			isWalkableSurfacePart(result.Instance, roomModel, floor)
			or (tileMaskFolder ~= nil and isTileMaskMarkerPart(result.Instance, tileMaskFolder))
		) then

		return result
	end

	return nil
end

local function getHoverCenterY(floorTopY, hitResult, floor, tileMaskFolder)
	if not hitResult
		or hitResult.Instance == floor
		or (tileMaskFolder ~= nil and isTileMaskMarkerPart(hitResult.Instance, tileMaskFolder)) then

		return floorTopY + FLOOR_HOVER_CENTER_OFFSET
	end

	local surfaceY = math.max(floorTopY, hitResult.Position.Y)
	local hitPart = hitResult.Instance

	if hitPart and hitPart:IsA("BasePart") then
		surfaceY = math.max(surfaceY, hitPart.Position.Y + hitPart.Size.Y / 2)
	end

	return surfaceY + DECORATION_HOVER_CENTER_OFFSET
end

local function getMaskedHoverCell(hitResult, context, tileMaskFolder)
	local markerCellX, markerCellZ = getTileMaskMarkerCell(hitResult.Instance, context, tileMaskFolder)

	if markerCellX and markerCellZ then
		return markerCellX, markerCellZ
	end

	return GridConfig.WorldToCell(context, hitResult.Position)
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

	local context = GridConfig.GetGridContext(roomModel)

	if not context then
		hideHover()
		return
	end

	local floorTopY = GridConfig.GetFloorTopY(floor)

	if not floorTopY then
		hideHover()
		return
	end

	local tileMaskFolder = context.UsesTileMask == true and getTileMaskFolder(roomModel) or nil
	local hitResult = getMouseFloorHit(roomModel, floor, context, tileMaskFolder)

	if not hitResult then
		hideHover()
		return
	end

	local tileSize = context.TileSize or GridConfig.GetTileSize(roomModel, floor)
	local worldPosition = nil

	if context.UsesTileMask == true then
		local cellX, cellZ = getMaskedHoverCell(hitResult, context, tileMaskFolder)

		if not cellX or not cellZ or not GridConfig.CellIsWalkable(context, cellX, cellZ) then
			hideHover()
			return
		end

		local cellWorldPosition = GridConfig.CellToWorld(context, cellX, cellZ)

		if not cellWorldPosition then
			hideHover()
			return
		end

		worldPosition = cellWorldPosition
	else
		local _, snappedLocalPosition = GridConfig.SnapWorldToTileCenter(floor, hitResult.Position, tileSize)

		if not snappedLocalPosition then
			hideHover()
			return
		end

		local localY = floor.Size.Y / 2 + FLOOR_HOVER_CENTER_OFFSET
		worldPosition = GridConfig.FloorLocalToWorld(
			floor,
			Vector3.new(snappedLocalPosition.X, localY, snappedLocalPosition.Z)
		)
	end

	if not worldPosition then
		hideHover()
		return
	end

	worldPosition = Vector3.new(worldPosition.X, getHoverCenterY(floorTopY, hitResult, floor, tileMaskFolder), worldPosition.Z)

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
