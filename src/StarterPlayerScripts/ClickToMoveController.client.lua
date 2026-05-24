--Explorer/StarterPlayerScripts/ClickToMoveController
print("ClickToMoveController started")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local activeRooms = workspace:WaitForChild("ActiveRooms")
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local furnitureActionRequest = remoteEvents:WaitForChild("FurnitureActionRequest")
local furnitureActionResult = remoteEvents:WaitForChild("FurnitureActionResult")
local furnitureMenuRequest = remoteEvents:WaitForChild("FurnitureMenuRequest")

local playerGui = player:WaitForChild("PlayerGui")
local furnitureMenuGui = playerGui:WaitForChild("FurnitureMenuGui")
local menuFrame = furnitureMenuGui:WaitForChild("MenuFrame")
menuFrame.AnchorPoint = Vector2.new(0.5, 1)

local titleLabel = menuFrame:WaitForChild("TitleLabel")
local sitButton = menuFrame:WaitForChild("SitButton")
local closeButton = menuFrame:WaitForChild("CloseButton")
local moveButton = menuFrame:WaitForChild("MoveButton")
local rotateButton = menuFrame:WaitForChild("RotateButton")
local pickUpButton = menuFrame:FindFirstChild("PickUpButton")

if not pickUpButton then
	local verticalStep = rotateButton.Size.Y.Offset

	if verticalStep <= 0 then
		verticalStep = 42
	end

	pickUpButton = rotateButton:Clone()
	pickUpButton.Name = "PickUpButton"
	pickUpButton.Text = "Pick Up"
	pickUpButton.Position = UDim2.new(
		rotateButton.Position.X.Scale,
		rotateButton.Position.X.Offset,
		rotateButton.Position.Y.Scale,
		rotateButton.Position.Y.Offset + verticalStep + 6
	)
	pickUpButton.Parent = menuFrame

	if menuFrame.Size.Y.Scale == 0 and pickUpButton.Position.Y.Scale == 0 then
		local requiredHeight = pickUpButton.Position.Y.Offset
			+ pickUpButton.Size.Y.Offset
			+ 8

		if requiredHeight > menuFrame.Size.Y.Offset then
			menuFrame.Size = UDim2.new(
				menuFrame.Size.X.Scale,
				menuFrame.Size.X.Offset,
				0,
				requiredHeight
			)
		end
	end
end

pickUpButton.Visible = false

local function getCurrentRoomModel()
	local roomName = player:GetAttribute("CurrentRoomName")

	if not roomName then
		return nil
	end

	return activeRooms:FindFirstChild(roomName)
end

local function getCurrentRoomFolder()
	local roomModel = getCurrentRoomModel()

	if not roomModel then
		return nil
	end

	return roomModel:FindFirstChild("Room")
end

local function getCurrentFurnitureFolder()
	local roomModel = getCurrentRoomModel()

	if not roomModel then
		return nil
	end

	return roomModel:FindFirstChild("Furniture")
end

local function getCurrentFloor()
	local roomFolder = getCurrentRoomFolder()

	if not roomFolder then
		return nil
	end

	return roomFolder:FindFirstChild("WalkableFloor")
end

local function isEditMode()
	return player:GetAttribute("RoomMode") == "Edit"
end

local function isPlayMode()
	return not isEditMode()
end

local function getDefaultFurnitureAction(furnitureModel)
	local defaultAction = furnitureModel:GetAttribute("DefaultAction")

	if typeof(defaultAction) ~= "string" then
		return nil
	end

	if defaultAction == "" or defaultAction == "None" then
		return nil
	end

	return defaultAction
end

local function getFurnitureTemplateId(furnitureModel)
	if typeof(furnitureModel) ~= "Instance" then
		return nil
	end

	local templateId = furnitureModel:GetAttribute("TemplateId")

	if typeof(templateId) == "string" and templateId ~= "" and templateId:match("%S") then
		return templateId
	end

	local pickupTemplateId = furnitureModel:GetAttribute("PickupTemplateId")

	if typeof(pickupTemplateId) == "string"
		and pickupTemplateId ~= ""
		and pickupTemplateId:match("%S") then

		return pickupTemplateId
	end

	local persistentId = furnitureModel:GetAttribute("PersistentId")

	if typeof(persistentId) == "string" and persistentId ~= "" and persistentId:match("%S") then
		return persistentId
	end

	if furnitureModel.Name ~= "" then
		return furnitureModel.Name
	end

	return nil
end

local function actionRequiresStanding(actionName)
	return actionName == "Sit"
		or actionName == "Sleep"
		or actionName == "Run"
end

local function getFurnitureOccupantHumanoid(furnitureModel)
	if typeof(furnitureModel) ~= "Instance" then
		return nil, nil
	end

	if not furnitureModel:IsA("Model") then
		return nil, nil
	end

	for _, descendant in ipairs(furnitureModel:GetDescendants()) do
		if descendant:IsA("Seat") or descendant:IsA("VehicleSeat") then
			if descendant.Occupant then
				return descendant.Occupant, descendant
			end
		end
	end

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		local character = otherPlayer.Character

		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")

			if humanoid
				and humanoid.SeatPart
				and humanoid.SeatPart:IsDescendantOf(furnitureModel) then

				return humanoid, humanoid.SeatPart
			end
		end
	end

	return nil, nil
end

local function isFurnitureOccupiedLocally(furnitureModel)
	local humanoid = getFurnitureOccupantHumanoid(furnitureModel)

	return humanoid ~= nil
end

local selectedFurniture = nil
local movingFurniture = nil
local placementPreview = nil
local placementPreviewHighlight = nil
local placementIsValid = false

local hiddenFurnitureParts = {}
local suppressFurnitureMenuUntil = 0

local lastPlayFurnitureActionAt = 0
local PLAY_FURNITURE_ACTION_COOLDOWN_SECONDS = 0.35

local selectedHighlight = Instance.new("Highlight")
selectedHighlight.Name = "SelectedFurnitureHighlight"
selectedHighlight.FillTransparency = 1
selectedHighlight.OutlineTransparency = 0
selectedHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
selectedHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
selectedHighlight.Enabled = false
selectedHighlight.Parent = workspace

local function highlightFurniture(furnitureModel)
	selectedHighlight.Adornee = furnitureModel
	selectedHighlight.Enabled = true
end

local function clearFurnitureHighlight()
	selectedHighlight.Adornee = nil
	selectedHighlight.Enabled = false
end

local function getHumanoid()
	local character = player.Character or player.CharacterAdded:Wait()
	return character:WaitForChild("Humanoid")
end

local currentMoveId = 0
local lastMoveTime = 0
local lastDestination = nil

local CLICK_MOVE_COOLDOWN = 0.2
local MIN_DESTINATION_DISTANCE = 2
local WAYPOINT_SKIP_DISTANCE = 2

local GRID_SIZE = 2
local PLACEMENT_GRID_SIZE = 2

local function snapToGrid(value)
	return math.floor((value / GRID_SIZE) + 0.5) * GRID_SIZE
end

local function snapToPlacementGrid(value)
	return math.floor((value / PLACEMENT_GRID_SIZE) + 0.5) * PLACEMENT_GRID_SIZE
end

local function getRoomBounds()
	local floor = getCurrentFloor()

	if not floor then
		return nil
	end

	local halfX = floor.Size.X / 2
	local halfZ = floor.Size.Z / 2

	return {
		minX = floor.Position.X - halfX + GRID_SIZE / 2,
		maxX = floor.Position.X + halfX - GRID_SIZE / 2,
		minZ = floor.Position.Z - halfZ + GRID_SIZE / 2,
		maxZ = floor.Position.Z + halfZ - GRID_SIZE / 2,
		y = floor.Position.Y + floor.Size.Y / 2 + 0.5,
	}
end

local function clampToRoom(position)
	local bounds = getRoomBounds()

	if not bounds then
		return position
	end

	local x = math.clamp(position.X, bounds.minX, bounds.maxX)
	local z = math.clamp(position.Z, bounds.minZ, bounds.maxZ)

	return Vector3.new(x, bounds.y, z)
end

local function isCellInsideRoom(cell)
	local bounds = getRoomBounds()

	if not bounds then
		return false
	end

	return cell.x >= bounds.minX
		and cell.x <= bounds.maxX
		and cell.z >= bounds.minZ
		and cell.z <= bounds.maxZ
end

local function worldToCell(position)
	local snappedX = snapToGrid(position.X)
	local snappedZ = snapToGrid(position.Z)

	return {
		x = snappedX,
		z = snappedZ
	}
end

local function cellToWorld(cell)
	local bounds = getRoomBounds()

	if not bounds then
		return Vector3.new(cell.x, 1, cell.z)
	end

	return Vector3.new(cell.x, bounds.y, cell.z)
end

local function cellKey(cell)
	return tostring(cell.x) .. "," .. tostring(cell.z)
end

local function isCellBlocked(cell)
	local roomFolder = getCurrentRoomFolder()
	local furnitureFolder = getCurrentFurnitureFolder()

	if not roomFolder or not furnitureFolder then
		return true
	end

	local center = cellToWorld(cell)

	local boxSize = Vector3.new(GRID_SIZE * 0.8, 5, GRID_SIZE * 0.8)
	local boxCFrame = CFrame.new(center)

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	local ignoreList = {}

	if player.Character then
		table.insert(ignoreList, player.Character)
	end

	overlapParams.FilterDescendantsInstances = ignoreList

	local parts = workspace:GetPartBoundsInBox(boxCFrame, boxSize, overlapParams)

	for _, part in ipairs(parts) do
		if part.Name == "WalkableFloor" then
			continue
		end

		if part.Name == "SitPoint"
			or part.Name == "SleepPoint"
			or part.Name == "PlayPoint"
			or part.Name == "EnterPoint"
			or part.Name == "TalkPoint" then
			continue
		end

		if part:IsA("BasePart") and part.CanCollide == false then
			continue
		end

		if part:IsDescendantOf(furnitureFolder) then
			return true
		end

		if part:IsDescendantOf(roomFolder) then
			if part.Name:find("Boundary") or part.Name:find("Wall") then
				return true
			end
		end
	end

	return false
end

local function getNeighbors(cell)
	return {
		{ x = cell.x + GRID_SIZE, z = cell.z },
		{ x = cell.x - GRID_SIZE, z = cell.z },
		{ x = cell.x, z = cell.z + GRID_SIZE },
		{ x = cell.x, z = cell.z - GRID_SIZE },
	}
end

local function getCellDistance(a, b)
	return math.abs(a.x - b.x) + math.abs(a.z - b.z)
end

local function cellsAreSame(a, b)
	return a.x == b.x and a.z == b.z
end

local function findGridPath(startCell, goalCell)
	local queue = {}
	local cameFrom = {}
	local visited = {}

	local closestCell = startCell
	local closestDistance = getCellDistance(startCell, goalCell)

	table.insert(queue, startCell)
	visited[cellKey(startCell)] = true

	while #queue > 0 do
		local current = table.remove(queue, 1)

		local currentDistance = getCellDistance(current, goalCell)

		if currentDistance < closestDistance then
			closestDistance = currentDistance
			closestCell = current
		end

		if cellsAreSame(current, goalCell) then
			local path = {}
			local step = current

			while step do
				table.insert(path, 1, step)
				step = cameFrom[cellKey(step)]
			end

			return path, true
		end

		for _, neighbor in ipairs(getNeighbors(current)) do
			local key = cellKey(neighbor)

			if not visited[key]
				and isCellInsideRoom(neighbor)
				and not isCellBlocked(neighbor) then

				visited[key] = true
				cameFrom[key] = current
				table.insert(queue, neighbor)
			end
		end
	end

	-- If the clicked tile cannot be reached, walk to the closest reachable tile.
	local fallbackPath = {}
	local step = closestCell

	while step do
		table.insert(fallbackPath, 1, step)
		step = cameFrom[cellKey(step)]
	end

	return fallbackPath, false
end

local function compressGridPath(path)
	if not path or #path <= 2 then
		return path
	end

	local compressedPath = {}

	table.insert(compressedPath, path[1])

	local lastDirection = nil

	for index = 2, #path do
		local previousCell = path[index - 1]
		local currentCell = path[index]

		local direction = {
			x = currentCell.x - previousCell.x,
			z = currentCell.z - previousCell.z
		}

		if lastDirection
			and (direction.x ~= lastDirection.x or direction.z ~= lastDirection.z) then

			-- Add the cell before the turn.
			table.insert(compressedPath, previousCell)
		end

		lastDirection = direction
	end

	-- Always include final destination.
	table.insert(compressedPath, path[#path])

	return compressedPath
end

local function moveCharacterTo(destination)
	local now = os.clock()

	if now - lastMoveTime < CLICK_MOVE_COOLDOWN then
		return
	end

	lastMoveTime = now

	currentMoveId += 1
	local moveId = currentMoveId

	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")

	local clampedDestination = clampToRoom(destination)

	local startCell = worldToCell(rootPart.Position)
	local goalCell = worldToCell(clampedDestination)

	if startCell.x == goalCell.x and startCell.z == goalCell.z then
		return
	end

	local path, reachedGoal = findGridPath(startCell, goalCell)

	if not path or #path == 0 then
		warn("No grid path found")
		return
	end

	if not reachedGoal then
		warn("Clicked tile is blocked, moving to closest reachable tile")
	end

	local movementPath = compressGridPath(path)

	for index, cell in ipairs(movementPath) do
		if moveId ~= currentMoveId then
			return
		end

		-- Skip the starting tile.
		if index == 1 then
			continue
		end

		local worldPosition = cellToWorld(cell)

		humanoid:MoveTo(worldPosition)

		local reached = humanoid.MoveToFinished:Wait()

		if not reached then
			warn("Could not reach movement segment")
			return
		end
	end
end

local function getFurnitureModelFromTarget(target)
	if not target then
		return nil
	end

	local furnitureFolder = getCurrentFurnitureFolder()

	if not furnitureFolder then
		return nil
	end

	local current = target

	while current and current ~= workspace do
		if current:IsA("Model") and current:IsDescendantOf(furnitureFolder) then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function getFurnitureTopPosition(furnitureModel)
	local modelCFrame, modelSize = furnitureModel:GetBoundingBox()

	local topPosition = modelCFrame.Position + Vector3.new(0, modelSize.Y / 2 + 2, 0)

	return topPosition
end

local function getMouseFloorPosition()
	local currentFloor = getCurrentFloor()

	if not currentFloor then
		return nil
	end

	if mouse.Target ~= currentFloor then
		return nil
	end

	-- Do not clamp here.
	-- Furniture placement will clamp based on the whole model size instead.
	return mouse.Hit.Position
end

local function getFloorPlacementBounds()
	local floor = getCurrentFloor()

	if not floor then
		return nil
	end

	local halfX = floor.Size.X / 2
	local halfZ = floor.Size.Z / 2

	local edgeMargin = 0.05

	return {
		minX = floor.Position.X - halfX + edgeMargin,
		maxX = floor.Position.X + halfX - edgeMargin,
		minZ = floor.Position.Z - halfZ + edgeMargin,
		maxZ = floor.Position.Z + halfZ - edgeMargin,
	}
end

local helperPartNames = {
	SitPoint = true,
	SleepPoint = true,
	PlayPoint = true,
	EnterPoint = true,
	TalkPoint = true,
}

local function isHelperPart(part)
	return helperPartNames[part.Name] == true
end

local function shouldUsePartForPlacementBounds(part)
	if not part:IsA("BasePart") then
		return false
	end

	if isHelperPart(part) then
		return false
	end

	-- Include real furniture body parts and collision buffers.
	if part.CanCollide then
		return true
	end

	if part.Transparency < 1 then
		return true
	end

	return false
end

local function getPartWorldCornersFromCFrame(cframe, size)
	local halfSize = size / 2

	local localCorners = {
		Vector3.new(-halfSize.X, -halfSize.Y, -halfSize.Z),
		Vector3.new(-halfSize.X, -halfSize.Y, halfSize.Z),
		Vector3.new(-halfSize.X, halfSize.Y, -halfSize.Z),
		Vector3.new(-halfSize.X, halfSize.Y, halfSize.Z),
		Vector3.new(halfSize.X, -halfSize.Y, -halfSize.Z),
		Vector3.new(halfSize.X, -halfSize.Y, halfSize.Z),
		Vector3.new(halfSize.X, halfSize.Y, -halfSize.Z),
		Vector3.new(halfSize.X, halfSize.Y, halfSize.Z),
	}

	local worldCorners = {}

	for _, localCorner in ipairs(localCorners) do
		table.insert(worldCorners, cframe:PointToWorldSpace(localCorner))
	end

	return worldCorners
end

local function getModelXZBoundsAtCFrame(model, targetCFrame)
	local currentPivot = model:GetPivot()

	local minX = math.huge
	local maxX = -math.huge
	local minZ = math.huge
	local maxZ = -math.huge

	local foundPart = false

	for _, descendant in ipairs(model:GetDescendants()) do
		if shouldUsePartForPlacementBounds(descendant) then
			foundPart = true

			local relativeCFrame = currentPivot:ToObjectSpace(descendant.CFrame)
			local predictedCFrame = targetCFrame * relativeCFrame

			for _, corner in ipairs(getPartWorldCornersFromCFrame(predictedCFrame, descendant.Size)) do
				minX = math.min(minX, corner.X)
				maxX = math.max(maxX, corner.X)
				minZ = math.min(minZ, corner.Z)
				maxZ = math.max(maxZ, corner.Z)
			end
		end
	end

	if not foundPart then
		return nil
	end

	return {
		minX = minX,
		maxX = maxX,
		minZ = minZ,
		maxZ = maxZ,
	}
end

local function clampFurnitureCFrameInsideRoom(model, targetCFrame)
	local floorBounds = getFloorPlacementBounds()
	local modelBounds = getModelXZBoundsAtCFrame(model, targetCFrame)

	if not floorBounds or not modelBounds then
		return targetCFrame
	end

	local offsetX = 0
	local offsetZ = 0

	if modelBounds.minX < floorBounds.minX then
		offsetX = floorBounds.minX - modelBounds.minX
	elseif modelBounds.maxX > floorBounds.maxX then
		offsetX = floorBounds.maxX - modelBounds.maxX
	end

	if modelBounds.minZ < floorBounds.minZ then
		offsetZ = floorBounds.minZ - modelBounds.minZ
	elseif modelBounds.maxZ > floorBounds.maxZ then
		offsetZ = floorBounds.maxZ - modelBounds.maxZ
	end

	return targetCFrame + Vector3.new(offsetX, 0, offsetZ)
end

local function getSnappedPlacementPosition()
	local floorPosition = getMouseFloorPosition()

	if not floorPosition then
		return nil
	end

	local snappedX = snapToPlacementGrid(floorPosition.X)
	local snappedZ = snapToPlacementGrid(floorPosition.Z)

	if not movingFurniture then
		return Vector3.new(snappedX, floorPosition.Y, snappedZ)
	end

	local currentPivot = movingFurniture:GetPivot()
	local currentRotation = currentPivot - currentPivot.Position

	local targetPosition = Vector3.new(
		snappedX,
		currentPivot.Position.Y,
		snappedZ
	)

	local targetCFrame = CFrame.new(targetPosition) * currentRotation
	local clampedCFrame = clampFurnitureCFrameInsideRoom(movingFurniture, targetCFrame)

	return Vector3.new(
		clampedCFrame.Position.X,
		floorPosition.Y,
		clampedCFrame.Position.Z
	)
end

local function getPartWorldCorners(part)
	local halfSize = part.Size / 2

	local localCorners = {
		Vector3.new(-halfSize.X, -halfSize.Y, -halfSize.Z),
		Vector3.new(-halfSize.X, -halfSize.Y, halfSize.Z),
		Vector3.new(-halfSize.X, halfSize.Y, -halfSize.Z),
		Vector3.new(-halfSize.X, halfSize.Y, halfSize.Z),
		Vector3.new(halfSize.X, -halfSize.Y, -halfSize.Z),
		Vector3.new(halfSize.X, -halfSize.Y, halfSize.Z),
		Vector3.new(halfSize.X, halfSize.Y, -halfSize.Z),
		Vector3.new(halfSize.X, halfSize.Y, halfSize.Z),
	}

	local worldCorners = {}

	for _, localCorner in ipairs(localCorners) do
		table.insert(worldCorners, part.CFrame:PointToWorldSpace(localCorner))
	end

	return worldCorners
end

local function getModelXZBounds(model)
	local minX = math.huge
	local maxX = -math.huge
	local minZ = math.huge
	local maxZ = -math.huge

	local foundPart = false

	for _, descendant in ipairs(model:GetDescendants()) do
		if shouldUsePartForPlacementBounds(descendant) then
			foundPart = true

			for _, corner in ipairs(getPartWorldCorners(descendant)) do
				minX = math.min(minX, corner.X)
				maxX = math.max(maxX, corner.X)
				minZ = math.min(minZ, corner.Z)
				maxZ = math.max(maxZ, corner.Z)
			end
		end
	end

	if not foundPart then
		return nil
	end

	return {
		minX = minX,
		maxX = maxX,
		minZ = minZ,
		maxZ = maxZ,
	}
end

local function isPreviewInsideRoom(previewModel)
	local previewBounds = getModelXZBounds(previewModel)
	local floorBounds = getFloorPlacementBounds()

	if not previewBounds or not floorBounds then
		return false
	end

	if previewBounds.minX < floorBounds.minX then
		return false
	end

	if previewBounds.maxX > floorBounds.maxX then
		return false
	end

	if previewBounds.minZ < floorBounds.minZ then
		return false
	end

	if previewBounds.maxZ > floorBounds.maxZ then
		return false
	end

	return true
end

local function isPreviewBlocked(previewModel)
	local roomFolder = getCurrentRoomFolder()
	local furnitureFolder = getCurrentFurnitureFolder()

	if not roomFolder or not furnitureFolder then
		return true
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	local ignoreList = {
		previewModel,
		movingFurniture,
	}

	if player.Character then
		table.insert(ignoreList, player.Character)
	end

	overlapParams.FilterDescendantsInstances = ignoreList

	for _, descendant in ipairs(previewModel:GetDescendants()) do
		if shouldUsePartForPlacementBounds(descendant) then
			local touchingParts = workspace:GetPartBoundsInBox(
				descendant.CFrame,
				descendant.Size,
				overlapParams
			)

			for _, part in ipairs(touchingParts) do
				if part.Name == "WalkableFloor" then
					continue
				end

				if isHelperPart(part) then
					continue
				end

				if part:IsA("BasePart") and part.CanCollide == false then
					continue
				end

				if part:IsDescendantOf(furnitureFolder) then
					return true
				end

				if part:IsDescendantOf(roomFolder) then
					if part.Name:find("Boundary") or part.Name:find("Wall") then
						return true
					end
				end
			end
		end
	end

	return false
end

local function playerIsInSameRoom(otherPlayer)
	return otherPlayer:GetAttribute("CurrentRoomName") == player:GetAttribute("CurrentRoomName")
end

local function isPreviewBlockedByPlayer(previewModel)
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if playerIsInSameRoom(otherPlayer) then
			local character = otherPlayer.Character

			if character then
				local overlapParams = OverlapParams.new()
				overlapParams.FilterType = Enum.RaycastFilterType.Include
				overlapParams.FilterDescendantsInstances = { character }

				for _, descendant in ipairs(previewModel:GetDescendants()) do
					if shouldUsePartForPlacementBounds(descendant) then
						local touchingParts = workspace:GetPartBoundsInBox(
							descendant.CFrame,
							descendant.Size,
							overlapParams
						)

						if #touchingParts > 0 then
							return true
						end
					end
				end
			end
		end
	end

	return false
end

local function setPlacementPreviewValidity(isValid)
	placementIsValid = isValid

	local fillColor
	local outlineColor

	if isValid then
		-- Bright cyan/blue is easier to see against green walls.
		fillColor = Color3.fromRGB(0, 190, 255)
		outlineColor = Color3.fromRGB(255, 255, 255)
	else
		fillColor = Color3.fromRGB(255, 60, 60)
		outlineColor = Color3.fromRGB(255, 255, 255)
	end

	if placementPreviewHighlight then
		placementPreviewHighlight.Enabled = true
		placementPreviewHighlight.FillColor = fillColor
		placementPreviewHighlight.OutlineColor = outlineColor
		placementPreviewHighlight.FillTransparency = 0.35
		placementPreviewHighlight.OutlineTransparency = 0
		placementPreviewHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	end

	if placementPreview then
		for _, descendant in ipairs(placementPreview:GetDescendants()) do
			if descendant:IsA("BasePart") then
				if descendant.Name ~= "SitPoint"
					and descendant.Name ~= "SleepPoint"
					and descendant.Name ~= "PlayPoint"
					and descendant.Name ~= "EnterPoint"
					and descendant.Name ~= "TalkPoint" then

					descendant.Color = fillColor
					descendant.Transparency = 0.35
					descendant.Material = Enum.Material.Neon
				end
			end
		end
	end
end

local function checkPlacementPreviewValidity()
	if not placementPreview then
		return false
	end

	if not isPreviewInsideRoom(placementPreview) then
		return false
	end

	if isPreviewBlocked(placementPreview) then
		return false
	end

	if isPreviewBlockedByPlayer(placementPreview) then
		return false
	end

	return true
end

local function setMovingFurnitureIgnored(shouldIgnore)
	if shouldIgnore and movingFurniture then
		mouse.TargetFilter = movingFurniture
	else
		mouse.TargetFilter = nil
	end
end

local function showOriginalFurniture()
	for part, oldLocalTransparencyModifier in pairs(hiddenFurnitureParts) do
		if part and part.Parent then
			part.LocalTransparencyModifier = oldLocalTransparencyModifier
		end
	end

	hiddenFurnitureParts = {}
end

local function destroyPlacementPreview()
	if placementPreview then
		placementPreview:Destroy()
		placementPreview = nil
	end

	if placementPreviewHighlight then
		placementPreviewHighlight:Destroy()
		placementPreviewHighlight = nil
	end

	placementIsValid = false

	showOriginalFurniture()
	setMovingFurnitureIgnored(false)
end

local function dimOriginalFurniture(furnitureModel)
	hiddenFurnitureParts = {}

	if not furnitureModel then
		return
	end

	for _, descendant in ipairs(furnitureModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			hiddenFurnitureParts[descendant] = descendant.LocalTransparencyModifier

			-- Keep the original visible, but faded.
			descendant.LocalTransparencyModifier = math.max(
				descendant.LocalTransparencyModifier,
				0.65
			)
		end
	end
end

local function createPlacementPreview(furnitureModel)
	destroyPlacementPreview()

	if not furnitureModel then
		return
	end

	placementPreview = furnitureModel:Clone()
	placementPreview.Name = "PlacementPreview"

	for _, descendant in ipairs(placementPreview:GetDescendants()) do
		if descendant:IsA("Script")
			or descendant:IsA("LocalScript")
			or descendant:IsA("ClickDetector") then

			descendant:Destroy()

		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Transparency = math.max(descendant.Transparency, 0.55)
		end
	end

	placementPreview.Parent = workspace
	
	placementPreviewHighlight = Instance.new("Highlight")
	placementPreviewHighlight.Name = "PlacementPreviewHighlight"
	placementPreviewHighlight.Adornee = placementPreview
	placementPreviewHighlight.FillTransparency = 0.45
	placementPreviewHighlight.OutlineTransparency = 0
	placementPreviewHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	placementPreviewHighlight.Parent = placementPreview

	setPlacementPreviewValidity(false)
end

local function updatePlacementPreview()
	if not movingFurniture or not placementPreview then
		return
	end

	local placementPosition = getSnappedPlacementPosition()

	if not placementPosition then
		return
	end

	local currentPivot = movingFurniture:GetPivot()
	local currentRotation = currentPivot - currentPivot.Position

	local previewPosition = Vector3.new(
		placementPosition.X,
		currentPivot.Position.Y,
		placementPosition.Z
	)

	placementPreview:PivotTo(CFrame.new(previewPosition) * currentRotation)

	local isValid = checkPlacementPreviewValidity()
	setPlacementPreviewValidity(isValid)
end

local function updateMenuPosition()
	if not selectedFurniture then
		return
	end

	if not menuFrame.Visible then
		return
	end

	local camera = workspace.CurrentCamera
	local worldPosition = getFurnitureTopPosition(selectedFurniture)

	local screenPosition, onScreen = camera:WorldToScreenPoint(worldPosition)

	if onScreen then
		menuFrame.Position = UDim2.fromOffset(screenPosition.X, screenPosition.Y)
	else
		menuFrame.Visible = false
	end
end

RunService.RenderStepped:Connect(updateMenuPosition)
RunService.RenderStepped:Connect(updatePlacementPreview)

local function openFurnitureMenu(furnitureModel)
	selectedFurniture = furnitureModel
	titleLabel.Text = furnitureModel.Name
	
	local editing = isEditMode()
	local occupied = isFurnitureOccupiedLocally(furnitureModel)

	sitButton.Visible = false
	moveButton.Visible = editing and not occupied
	rotateButton.Visible = editing and not occupied
	pickUpButton.Visible = editing
		and not occupied
		and getFurnitureTemplateId(furnitureModel) ~= nil

	if editing and occupied then
		titleLabel.Text = furnitureModel.Name .. " (Occupied)"
	end

	highlightFurniture(furnitureModel)

	local camera = workspace.CurrentCamera
	local worldPosition = getFurnitureTopPosition(furnitureModel)

	local screenPosition, onScreen = camera:WorldToScreenPoint(worldPosition)

	if onScreen then
		menuFrame.Position = UDim2.fromOffset(screenPosition.X, screenPosition.Y)
		menuFrame.Visible = true
	else
		menuFrame.Visible = false
	end
end

local function closeFurnitureMenu()
	selectedFurniture = nil
	movingFurniture = nil
	menuFrame.Visible = false

	destroyPlacementPreview()
	clearFurnitureHighlight()
end


local function isHotelMode()
	local controlMode = player:GetAttribute("ControlMode")

	if controlMode == nil then
		return true
	end

	return controlMode == "Hotel"
end

local function clickIsOnFurnitureMenu()
	if not menuFrame.Visible then
		return false
	end

	local guiObjects = playerGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y)

	for _, guiObject in ipairs(guiObjects) do
		if guiObject == menuFrame or guiObject:IsDescendantOf(menuFrame) then
			return true
		end
	end

	return false
end

local function getCurrentlySeatedFurniture()
	local character = player.Character

	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not humanoid then
		return nil
	end

	local seatPart = humanoid.SeatPart

	if not seatPart then
		return nil
	end

	local furnitureFolder = getCurrentFurnitureFolder()

	if not furnitureFolder then
		return nil
	end

	local current = seatPart

	while current and current ~= workspace do
		if current:IsA("Model") and current:IsDescendantOf(furnitureFolder) then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function standUpIfSeated()
	local character = player.Character

	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not humanoid then
		return
	end

	if humanoid.Sit or humanoid.SeatPart then
		furnitureActionRequest:FireServer("Stand")

		-- Give the server a moment to unseat and teleport the player to SitPoint.
		task.wait(0.5)
	end
end

local function handleFurnitureClickInPlayMode(furnitureModel)
	local actionName = getDefaultFurnitureAction(furnitureModel)

	if not actionName then
		closeFurnitureMenu()
		return
	end

	-- Important:
	-- If the player clicks the same chair they are already sitting on,
	-- do not send Stand and do not send another Sit.
	if actionName == "Sit" then
		local seatedFurniture = getCurrentlySeatedFurniture()

		if seatedFurniture == furnitureModel then
			closeFurnitureMenu()
			return
		end
	end

	local now = os.clock()

	if now - lastPlayFurnitureActionAt < PLAY_FURNITURE_ACTION_COOLDOWN_SECONDS then
		return
	end

	lastPlayFurnitureActionAt = now

	if actionRequiresStanding(actionName) then
		standUpIfSeated()
	end

	furnitureActionRequest:FireServer(actionName, furnitureModel)
	closeFurnitureMenu()
end

furnitureMenuRequest.OnClientEvent:Connect(function(furnitureModel)
	if movingFurniture then
		return
	end

	if os.clock() < suppressFurnitureMenuUntil then
		return
	end

	if not isHotelMode() then
		return
	end

	if typeof(furnitureModel) ~= "Instance" then
		return
	end

	if not furnitureModel:IsA("Model") then
		return
	end

	local currentFurnitureFolder = getCurrentFurnitureFolder()

	if not currentFurnitureFolder then
		return
	end

	if not furnitureModel:IsDescendantOf(currentFurnitureFolder) then
		return
	end

	-- Browsing furniture should not force the player to stand.
	if isEditMode() then
		openFurnitureMenu(furnitureModel)
	else
		handleFurnitureClickInPlayMode(furnitureModel)
	end
end)

mouse.Button1Down:Connect(function()
	print(
		"World click:",
		mouse.Target and mouse.Target:GetFullName(),
		"CurrentRoomName:",
		player:GetAttribute("CurrentRoomName"),
		"RoomMode:",
		player:GetAttribute("RoomMode"),
		"ControlMode:",
		player:GetAttribute("ControlMode"),
		"OnboardingStep:",
		player:GetAttribute("OnboardingStep")
	)
	
	if not isHotelMode() then
		return
	end

	if clickIsOnFurnitureMenu and clickIsOnFurnitureMenu() then
		return
	end
	
	if player:GetAttribute("CatalogPlacementActive") == true then
		return
	end

	local target = mouse.Target
	local hitPosition = mouse.Hit.Position

	if not target then
		standUpIfSeated()
		closeFurnitureMenu()
		return
	end

	local currentFloor = getCurrentFloor()

	-- IMPORTANT:
	-- If we are moving furniture, handle placement before checking furniture clicks.
	-- This prevents the original furniture from blocking its own placement.
	if movingFurniture then
		local placementPosition = getSnappedPlacementPosition()

		if placementPosition and placementIsValid then
			suppressFurnitureMenuUntil = os.clock() + 0.25

			furnitureActionRequest:FireServer("Move", movingFurniture, placementPosition)

			movingFurniture = nil
			destroyPlacementPreview()
			closeFurnitureMenu()
		else
			warn("Invalid furniture placement")
		end

		return
	end

	-- Furniture clicks are handled by FurnitureClickServer through ClickDetectors.
	-- Do not move or close the menu here if the clicked target is furniture.
	local furnitureModel = getFurnitureModelFromTarget(target)

	if furnitureModel then
		return
	end

	if target == currentFloor then
		standUpIfSeated()
		closeFurnitureMenu()

		moveCharacterTo(hitPosition)
		return
	end

	standUpIfSeated()
	closeFurnitureMenu()
end)

sitButton.MouseButton1Click:Connect(function()
	print("Client: Sit button clicked")

	if not selectedFurniture then
		warn("Client: No furniture selected")
		return
	end

	print("Client: Requesting Sit on", selectedFurniture.Name)

	-- If already seated, only stand up when choosing to sit somewhere else.
	standUpIfSeated()

	furnitureActionRequest:FireServer("Sit", selectedFurniture)
	closeFurnitureMenu()
end)

closeButton.MouseButton1Click:Connect(function()
	closeFurnitureMenu()
end)

moveButton.MouseButton1Click:Connect(function()
	if not selectedFurniture then
		return
	end

	if isFurnitureOccupiedLocally(selectedFurniture) then
		warn("Cannot move occupied furniture.")
		closeFurnitureMenu()
		return
	end

	movingFurniture = selectedFurniture

	-- Create preview first because createPlacementPreview() calls destroyPlacementPreview().
	createPlacementPreview(movingFurniture)

	-- Then fade and ignore the original furniture.
	dimOriginalFurniture(movingFurniture)
	setMovingFurnitureIgnored(true)

	menuFrame.Visible = false
	clearFurnitureHighlight()
end)

rotateButton.MouseButton1Click:Connect(function()
	if not selectedFurniture then
		return
	end

	if isFurnitureOccupiedLocally(selectedFurniture) then
		warn("Cannot rotate occupied furniture.")
		closeFurnitureMenu()
		return
	end

	furnitureActionRequest:FireServer("Rotate", selectedFurniture)
end)

pickUpButton.MouseButton1Click:Connect(function()
	if not selectedFurniture then
		return
	end

	if isFurnitureOccupiedLocally(selectedFurniture) then
		warn("Cannot pick up occupied furniture.")
		closeFurnitureMenu()
		return
	end

	if not getFurnitureTemplateId(selectedFurniture) then
		warn("Cannot pick up starter furniture.")
		closeFurnitureMenu()
		return
	end

	furnitureActionRequest:FireServer("PickUp", selectedFurniture)
	closeFurnitureMenu()
end)

furnitureActionResult.OnClientEvent:Connect(function(response)
	if typeof(response) ~= "table" then
		return
	end

	if response.Kind ~= "PickUp" then
		return
	end

	local message = tostring(response.Message or "")

	if response.Success == true then
		print(message)
	else
		warn(message)
	end
end)
