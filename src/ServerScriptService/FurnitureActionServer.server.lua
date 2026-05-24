--Explorer/ServerScriptService/FurnitureActionServer.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local RoomPersistence = require(ServerScriptService:WaitForChild("RoomPersistence"))

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local furnitureActionRequest = remoteEvents:WaitForChild("FurnitureActionRequest")

local function getOrCreateRemoteEvent(name)
	local existing = remoteEvents:FindFirstChild(name)

	if existing then
		if not existing:IsA("RemoteEvent") then
			error(name .. " exists but is not a RemoteEvent.")
		end

		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remoteEvents

	return remote
end

local furnitureActionResult = getOrCreateRemoteEvent("FurnitureActionResult")

local activeRooms = workspace:WaitForChild("ActiveRooms")

local GRID_SIZE = 2
local PLACEMENT_GRID_SIZE = 2

local SIT_STAND_COOLDOWN_SECONDS = 0.35

local seatActionInFlightByUserId = {}
local lastSeatActionAtByUserId = {}

local function getCurrentRoomModel(player)
	local roomName = player:GetAttribute("CurrentRoomName")

	if not roomName then
		return nil
	end

	return activeRooms:FindFirstChild(roomName)
end

local function getCurrentRoomFolder(player)
	local roomModel = getCurrentRoomModel(player)

	if not roomModel then
		return nil
	end

	return roomModel:FindFirstChild("Room")
end

local function getMovementRoomBounds(player)
	local roomFolder = getCurrentRoomFolder(player)

	if not roomFolder then
		return nil
	end

	local floor = roomFolder:FindFirstChild("WalkableFloor")

	if not floor or not floor:IsA("BasePart") then
		return nil
	end

	local halfX = floor.Size.X / 2
	local halfZ = floor.Size.Z / 2

	return {
		minX = floor.Position.X - halfX + GRID_SIZE / 2,
		maxX = floor.Position.X + halfX - GRID_SIZE / 2,
		minZ = floor.Position.Z - halfZ + GRID_SIZE / 2,
		maxZ = floor.Position.Z + halfZ - GRID_SIZE / 2,

		-- Match the client-side walking height.
		y = floor.Position.Y + floor.Size.Y / 2 + 0.5,
	}
end

local function isRoomOwner(player)
	local roomModel = getCurrentRoomModel(player)

	if not roomModel then
		return false
	end

	return roomModel:GetAttribute("OwnerUserId") == player.UserId
end

local function canEditRoom(player)
	return player:GetAttribute("RoomMode") == "Edit"
		and isRoomOwner(player)
end

local function sendPickUpResult(player, success, message, templateId, newCount, tradable)
	if not player or player.Parent ~= Players then
		return
	end

	furnitureActionResult:FireClient(player, {
		Kind = "PickUp",
		Success = success == true,
		Message = tostring(message or ""),
		TemplateId = templateId,
		NewCount = newCount,
		Tradable = tradable == true,
	})
end

local function isValidTemplateId(templateId)
	return typeof(templateId) == "string"
		and templateId ~= ""
		and templateId:match("%S") ~= nil
end

local function templateExists(templateId)
	if not isValidTemplateId(templateId) then
		return false
	end

	local furnitureTemplates = ReplicatedStorage:FindFirstChild("FurnitureTemplates")

	if not furnitureTemplates then
		return false
	end

	local template = furnitureTemplates:FindFirstChild(templateId)

	return template and template:IsA("Model")
end

local function resolvePickupTemplateId(furnitureModel)
	local templateId = furnitureModel:GetAttribute("TemplateId")

	if isValidTemplateId(templateId) then
		return templateId, false
	end

	local pickupTemplateId = furnitureModel:GetAttribute("PickupTemplateId")

	if isValidTemplateId(pickupTemplateId) then
		return pickupTemplateId, true
	end

	local persistentId = furnitureModel:GetAttribute("PersistentId")

	if templateExists(persistentId) then
		return persistentId, true
	end

	if templateExists(furnitureModel.Name) then
		return furnitureModel.Name, true
	end

	return nil, false
end

local function isPickupTradable(furnitureModel, resolvedThroughFallback)
	if furnitureModel:GetAttribute("Tradable") == false then
		return false
	end

	if furnitureModel:GetAttribute("IsTradable") == false then
		return false
	end

	if resolvedThroughFallback then
		return false
	end

	return true
end

local function getCurrentFurnitureFolder(player)
	local roomModel = getCurrentRoomModel(player)

	if not roomModel then
		return nil
	end

	return roomModel:FindFirstChild("Furniture")
end

local function isValidFurnitureForPlayer(player, furnitureModel)
	if typeof(furnitureModel) ~= "Instance" then
		return false
	end

	if not furnitureModel:IsA("Model") then
		return false
	end

	local furnitureFolder = getCurrentFurnitureFolder(player)

	if not furnitureFolder then
		return false
	end

	return furnitureModel:IsDescendantOf(furnitureFolder)
end

local function getPlayerHumanoidAndRootPart(player)
	local character = player.Character

	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	return humanoid, rootPart, character
end

local function anchorFurnitureParts(furnitureModel)
	if typeof(furnitureModel) ~= "Instance" then
		return
	end

	if not furnitureModel:IsA("Model") then
		return
	end

	for _, descendant in ipairs(furnitureModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

local function isPlayerAlreadySeatedOnFurniture(player, furnitureModel)
	local humanoid = getPlayerHumanoidAndRootPart(player)

	if not humanoid then
		return false
	end

	local seatPart = humanoid.SeatPart

	if not seatPart then
		return false
	end

	return seatPart:IsDescendantOf(furnitureModel)
end

local function beginSeatAction(player)
	if not player or player.Parent ~= Players then
		return false
	end

	local now = os.clock()
	local previous = lastSeatActionAtByUserId[player.UserId]

	if seatActionInFlightByUserId[player.UserId] then
		return false
	end

	if previous and now - previous < SIT_STAND_COOLDOWN_SECONDS then
		return false
	end

	seatActionInFlightByUserId[player.UserId] = true
	lastSeatActionAtByUserId[player.UserId] = now

	return true
end

local function endSeatAction(player)
	if not player then
		return
	end

	seatActionInFlightByUserId[player.UserId] = nil
end

local function getFurnitureOccupantHumanoid(furnitureModel)
	if typeof(furnitureModel) ~= "Instance" then
		return nil, nil
	end

	if not furnitureModel:IsA("Model") then
		return nil, nil
	end

	-- Primary check: Roblox Seat / VehicleSeat occupancy.
	for _, descendant in ipairs(furnitureModel:GetDescendants()) do
		if descendant:IsA("Seat") or descendant:IsA("VehicleSeat") then
			if descendant.Occupant then
				return descendant.Occupant, descendant
			end
		end
	end

	-- Fallback check:
	-- If Roblox's Seat.Occupant has not updated yet, check each player's Humanoid.SeatPart.
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

local function isFurnitureOccupied(furnitureModel)
	local humanoid, seatPart = getFurnitureOccupantHumanoid(furnitureModel)

	return humanoid ~= nil, humanoid, seatPart
end

local function getOccupantNameFromHumanoid(humanoid)
	if not humanoid then
		return "Unknown"
	end

	local character = humanoid.Parent

	if not character then
		return "Unknown"
	end

	local occupyingPlayer = Players:GetPlayerFromCharacter(character)

	if occupyingPlayer then
		return occupyingPlayer.Name
	end

	return character.Name
end

-- Supports either:
-- 1. A BasePart named SitPoint
-- 2. An Attachment named SitPoint

-- This is important for future furniture moving/rotating.
-- As long as SitPoint is inside the furniture model, it will move/rotate with the model.

local function getInteractionWorldCFrame(furnitureModel, pointName)
	local point = furnitureModel:FindFirstChild(pointName, true)

	if not point then
		return nil
	end

	if point:IsA("Attachment") then
		return point.WorldCFrame
	end

	if point:IsA("BasePart") then
		return point.CFrame
	end

	return nil
end

local function getInteractionWorldPosition(furnitureModel, pointName)
	local pointCFrame = getInteractionWorldCFrame(furnitureModel, pointName)

	if not pointCFrame then
		return nil
	end

	return pointCFrame.Position
end

local function snapToGrid(value)
	return math.floor((value / GRID_SIZE) + 0.5) * GRID_SIZE
end

local function snapToPlacementGrid(value)
	return math.floor((value / PLACEMENT_GRID_SIZE) + 0.5) * PLACEMENT_GRID_SIZE
end

local function clampToRoom(player, position)
	local bounds = getMovementRoomBounds(player)

	if not bounds then
		return nil
	end

	local x = math.clamp(position.X, bounds.minX, bounds.maxX)
	local z = math.clamp(position.Z, bounds.minZ, bounds.maxZ)

	return Vector3.new(x, bounds.y, z)
end

local function worldToCell(position)
	local snappedX = snapToGrid(position.X)
	local snappedZ = snapToGrid(position.Z)

	return {
		x = snappedX,
		z = snappedZ
	}
end

local function cellToWorld(player, cell)
	local bounds = getMovementRoomBounds(player)

	if not bounds then
		return nil
	end

	return Vector3.new(cell.x, bounds.y, cell.z)
end

local function cellKey(cell)
	return tostring(cell.x) .. "," .. tostring(cell.z)
end

local function isCellInsideRoom(player, cell)
	local bounds = getMovementRoomBounds(player)

	if not bounds then
		return false
	end

	return cell.x >= bounds.minX
		and cell.x <= bounds.maxX
		and cell.z >= bounds.minZ
		and cell.z <= bounds.maxZ
end

local function isCellBlocked(player, cell, furnitureToIgnore)
	local roomFolder = getCurrentRoomFolder(player)
	local furnitureFolder = getCurrentFurnitureFolder(player)

	if not roomFolder or not furnitureFolder then
		return true
	end

	local center = cellToWorld(player, cell)

	if not center then
		return true
	end

	local boxSize = Vector3.new(GRID_SIZE * 0.8, 5, GRID_SIZE * 0.8)
	local boxCFrame = CFrame.new(center)

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	local ignoreList = {}

	if furnitureToIgnore then
		table.insert(ignoreList, furnitureToIgnore)
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

local function findGridPath(player, startCell, goalCell, furnitureToIgnoreForGoalOnly)
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

			if not visited[key] and isCellInsideRoom(player, neighbor) then
				local neighborIsGoal = cellsAreSame(neighbor, goalCell)

				local blocked

				if neighborIsGoal then
					-- For the final SitPoint cell, ignore only the furniture being interacted with.
					-- This lets a chair own its SitPoint.
					blocked = isCellBlocked(player, neighbor, furnitureToIgnoreForGoalOnly)
				else
					-- For all other cells, do not ignore the furniture.
					-- This prevents walking through the chair/table/bed.
					blocked = isCellBlocked(player, neighbor, nil)
				end

				if not blocked then
					visited[key] = true
					cameFrom[key] = current
					table.insert(queue, neighbor)
				end
			end
		end
	end

	-- Goal was not reachable.
	-- Walk to the closest reachable cell instead.
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

			table.insert(compressedPath, previousCell)
		end

		lastDirection = direction
	end

	table.insert(compressedPath, path[#path])

	return compressedPath
end

local function moveCharacterToGridPoint(player, character, destination, furnitureToIgnore)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then
		return false
	end

	local clampedDestination = clampToRoom(player, destination)

	if not clampedDestination then
		return false
	end

	local startCell = worldToCell(rootPart.Position)
	local goalCell = worldToCell(clampedDestination)

	if startCell.x == goalCell.x and startCell.z == goalCell.z then
		return true
	end

	local path, reachedGoal = findGridPath(player, startCell, goalCell, furnitureToIgnore)

	if not path or #path == 0 then
		warn("No grid path found at all")
		return false
	end

	local movementPath = compressGridPath(path)

	for index, cell in ipairs(movementPath) do
		if index == 1 then
			continue
		end

		local worldPosition = cellToWorld(player, cell)

		if not worldPosition then
			return false
		end

		humanoid:MoveTo(worldPosition)

		local reached = humanoid.MoveToFinished:Wait()

		if not reached then
			-- Physical movement got blocked.
			-- This is fine for Habbo-style movement: stop here.
			return false
		end
	end

	return reachedGoal
end



local function sitPlayerOnChair(player, furnitureModel)
	if not isValidFurnitureForPlayer(player, furnitureModel) then
		warn("Invalid furniture")
		return
	end

	anchorFurnitureParts(furnitureModel)

	local seat = furnitureModel:FindFirstChild("Seat", true)

	if not seat or not seat:IsA("Seat") then
		warn("Furniture has no Roblox Seat named Seat:", furnitureModel.Name)
		return
	end

	local sitPointPosition = getInteractionWorldPosition(furnitureModel, "SitPoint")

	if not sitPointPosition then
		warn("Furniture has no valid SitPoint:", furnitureModel.Name)
		return
	end

	local humanoid, rootPart, character = getPlayerHumanoidAndRootPart(player)

	if not humanoid or not rootPart or not character then
		warn("No humanoid or root part")
		return
	end

	-- Idempotent rule:
	-- Clicking the same chair while already seated should do nothing.
	if humanoid.SeatPart and humanoid.SeatPart:IsDescendantOf(furnitureModel) then
		return
	end

	-- Do not allow Sit to chain from one seat to another directly.
	-- The client should request Stand first when changing seats.
	if humanoid.Sit or humanoid.SeatPart then
		warn("Sit denied: player is already seated somewhere else")
		return
	end

	if seat.Occupant then
		if seat.Occupant == humanoid then
			return
		end

		warn("Seat is already occupied")
		return
	end

	print("Server: Moving to SitPoint using no-diagonal grid movement")

	local reachedSitPoint = moveCharacterToGridPoint(player, character, sitPointPosition, furnitureModel)

	local distanceToSitPoint = (rootPart.Position - sitPointPosition).Magnitude
	local closeEnoughToSit = distanceToSitPoint <= 5

	if not reachedSitPoint and not closeEnoughToSit then
		warn("Server: SitPoint is blocked, stopping at closest reachable tile")
		return
	end

	-- Habbo-style rule:
	-- Do not reserve the seat.
	-- Whoever reaches the chair first gets it.
	if seat.Occupant and seat.Occupant ~= humanoid then
		warn("Seat was taken by another player first")
		return
	end

	if humanoid.SeatPart and humanoid.SeatPart:IsDescendantOf(furnitureModel) then
		return
	end

	if humanoid.Sit or humanoid.SeatPart then
		warn("Sit cancelled: player became seated before reaching chair")
		return
	end

	print("Server: Sitting player")
	seat:Sit(humanoid)

	task.wait(0.1)

	if seat.Occupant ~= humanoid then
		warn("Player failed to sit, seat may have been taken")
		return
	end
end



local function getFurnitureModelFromDescendant(player, instance)
	local furnitureFolder = getCurrentFurnitureFolder(player)

	if not furnitureFolder then
		return nil
	end

	local current = instance

	while current and current ~= workspace do
		if current:IsA("Model") and current:IsDescendantOf(furnitureFolder) then
			return current
		end

		current = current.Parent
	end

	return nil
end



local function standPlayer(player)
	local character = player.Character

	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then
		return
	end
	
	if not humanoid.Sit and not humanoid.SeatPart then
		return
	end

	local seatPart = humanoid.SeatPart
	local standCFrame = nil

	if seatPart then
		local furnitureModel = getFurnitureModelFromDescendant(player, seatPart)

		if furnitureModel then
			standCFrame = getInteractionWorldCFrame(furnitureModel, "SitPoint")
		end
	end

	-- Unseat the player first.
	humanoid.Sit = false
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	task.wait(0.05)

	-- Move the player exactly to SitPoint.
	if standCFrame then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero

		character:PivotTo(standCFrame)
	end
end



local function getCurrentFloor(player)
	local roomFolder = getCurrentRoomFolder(player)

	if not roomFolder then
		return nil
	end

	return roomFolder:FindFirstChild("WalkableFloor")
end

local function getRoomBounds(player)
	local floor = getCurrentFloor(player)

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
	}
end

local function getFurnitureRoomBounds(player)
	local floor = getCurrentFloor(player)

	if not floor then
		return nil
	end

	local halfX = floor.Size.X / 2
	local halfZ = floor.Size.Z / 2

	-- Small margin so furniture is not allowed to visually hang over the floor.
	-- Increase to 0.25 or 0.5 if you want a little border.
	local edgeMargin = 0.05

	return {
		minX = floor.Position.X - halfX + edgeMargin,
		maxX = floor.Position.X + halfX - edgeMargin,
		minZ = floor.Position.Z - halfZ + edgeMargin,
		maxZ = floor.Position.Z + halfZ - edgeMargin,
	}
end

local function snapPositionInsideRoom(player, position)
	local floor = getCurrentFloor(player)

	if not floor then
		return nil
	end

	local snappedX = snapToPlacementGrid(position.X)
	local snappedZ = snapToPlacementGrid(position.Z)

	return Vector3.new(snappedX, position.Y, snappedZ)
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

local function shouldUsePartForFurnitureBounds(part)
	if not part:IsA("BasePart") then
		return false
	end

	if isHelperPart(part) then
		return false
	end

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

	local corners = {}

	for _, localCorner in ipairs(localCorners) do
		table.insert(corners, cframe:PointToWorldSpace(localCorner))
	end

	return corners
end

local function getModelXZBoundsAtCFrame(furnitureModel, targetCFrame)
	local currentPivot = furnitureModel:GetPivot()

	local minX = math.huge
	local maxX = -math.huge
	local minZ = math.huge
	local maxZ = -math.huge

	local foundPart = false

	for _, descendant in ipairs(furnitureModel:GetDescendants()) do
		if shouldUsePartForFurnitureBounds(descendant) then
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

local function modelFitsInsideRoom(player, furnitureModel, targetCFrame)
	local roomBounds = getFurnitureRoomBounds(player)
	local modelBounds = getModelXZBoundsAtCFrame(furnitureModel, targetCFrame)

	if not roomBounds or not modelBounds then
		return false
	end

	if modelBounds.minX < roomBounds.minX then
		return false
	end

	if modelBounds.maxX > roomBounds.maxX then
		return false
	end

	if modelBounds.minZ < roomBounds.minZ then
		return false
	end

	if modelBounds.maxZ > roomBounds.maxZ then
		return false
	end

	return true
end

local function clampFurnitureCFrameInsideRoom(player, furnitureModel, targetCFrame)
	local roomBounds = getFurnitureRoomBounds(player)
	local modelBounds = getModelXZBoundsAtCFrame(furnitureModel, targetCFrame)

	if not roomBounds or not modelBounds then
		return nil
	end

	local offsetX = 0
	local offsetZ = 0

	if modelBounds.minX < roomBounds.minX then
		offsetX = roomBounds.minX - modelBounds.minX
	elseif modelBounds.maxX > roomBounds.maxX then
		offsetX = roomBounds.maxX - modelBounds.maxX
	end

	if modelBounds.minZ < roomBounds.minZ then
		offsetZ = roomBounds.minZ - modelBounds.minZ
	elseif modelBounds.maxZ > roomBounds.maxZ then
		offsetZ = roomBounds.maxZ - modelBounds.maxZ
	end

	return targetCFrame + Vector3.new(offsetX, 0, offsetZ)
end

local function modelBlockedAtCFrame(player, furnitureModel, targetCFrame)
	local roomFolder = getCurrentRoomFolder(player)
	local furnitureFolder = getCurrentFurnitureFolder(player)

	if not roomFolder or not furnitureFolder then
		return true
	end

	local currentPivot = furnitureModel:GetPivot()

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	local ignoreList = {
		furnitureModel
	}

	if player.Character then
		table.insert(ignoreList, player.Character)
	end

	overlapParams.FilterDescendantsInstances = ignoreList

	for _, descendant in ipairs(furnitureModel:GetDescendants()) do
		if shouldUsePartForFurnitureBounds(descendant) then
			local relativeCFrame = currentPivot:ToObjectSpace(descendant.CFrame)
			local predictedCFrame = targetCFrame * relativeCFrame

			local parts = workspace:GetPartBoundsInBox(
				predictedCFrame,
				descendant.Size,
				overlapParams
			)

			for _, part in ipairs(parts) do
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

local function playerIsInSameRoom(editorPlayer, otherPlayer)
	return editorPlayer:GetAttribute("CurrentRoomName") == otherPlayer:GetAttribute("CurrentRoomName")
end

local function modelWouldOverlapCharacter(editorPlayer, furnitureModel, targetCFrame)
	local currentPivot = furnitureModel:GetPivot()

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if playerIsInSameRoom(editorPlayer, otherPlayer) then
			local character = otherPlayer.Character

			if character then
				local overlapParams = OverlapParams.new()
				overlapParams.FilterType = Enum.RaycastFilterType.Include
				overlapParams.FilterDescendantsInstances = { character }

				for _, descendant in ipairs(furnitureModel:GetDescendants()) do
					if shouldUsePartForFurnitureBounds(descendant) then
						local relativeCFrame = currentPivot:ToObjectSpace(descendant.CFrame)
						local predictedCFrame = targetCFrame * relativeCFrame

						local parts = workspace:GetPartBoundsInBox(
							predictedCFrame,
							descendant.Size,
							overlapParams
						)

						if #parts > 0 then
							return true, otherPlayer
						end
					end
				end
			end
		end
	end

	return false, nil
end

local function moveFurniture(player, furnitureModel, targetPosition)
	if not canEditRoom(player) then
		warn("Move denied: player is not in edit mode or is not room owner")
		return
	end
	
	if not isValidFurnitureForPlayer(player, furnitureModel) then
		warn("Invalid furniture move request")
		return
	end

	local occupied, occupyingHumanoid = isFurnitureOccupied(furnitureModel)

	if occupied then
		warn(
			"Furniture move blocked: furniture is occupied by",
			getOccupantNameFromHumanoid(occupyingHumanoid)
		)
		return
	end

	if typeof(targetPosition) ~= "Vector3" then
		warn("Invalid furniture target position")
		return
	end

	local currentPivot = furnitureModel:GetPivot()
	local snappedPosition = snapPositionInsideRoom(player, targetPosition)

	if not snappedPosition then
		return
	end

	local finalPosition = Vector3.new(
		snappedPosition.X,
		currentPivot.Position.Y,
		snappedPosition.Z
	)

	local currentRotation = currentPivot - currentPivot.Position
	local targetCFrame = CFrame.new(finalPosition) * currentRotation

	targetCFrame = clampFurnitureCFrameInsideRoom(player, furnitureModel, targetCFrame)

	if not targetCFrame then
		return
	end

	if not modelFitsInsideRoom(player, furnitureModel, targetCFrame) then
		warn("Furniture move blocked: model would be outside room")
		return
	end

	if modelBlockedAtCFrame(player, furnitureModel, targetCFrame) then
		warn("Furniture move blocked: model would overlap something")
		return
	end
	
	local overlapsPlayer, blockingPlayer = modelWouldOverlapCharacter(player, furnitureModel, targetCFrame)

	if overlapsPlayer then
		warn("Furniture move blocked: would overlap player", blockingPlayer and blockingPlayer.Name)
		return
	end

	furnitureModel:PivotTo(targetCFrame)

	RoomPersistence.CaptureRoomState(player, getCurrentRoomModel(player))
end

local function rotateFurniture(player, furnitureModel)
	if not canEditRoom(player) then
		warn("Rotate denied: player is not in edit mode or is not room owner")
		return
	end

	if not isValidFurnitureForPlayer(player, furnitureModel) then
		warn("Invalid furniture rotate request")
		return
	end
	
	local occupied, occupyingHumanoid = isFurnitureOccupied(furnitureModel)

	if occupied then
		warn(
			"Furniture rotate blocked: furniture is occupied by",
			getOccupantNameFromHumanoid(occupyingHumanoid)
		)
		return
	end

	local currentPivot = furnitureModel:GetPivot()
	local rotation = CFrame.Angles(0, math.rad(90), 0)

	local targetCFrame = currentPivot * rotation

	if not modelFitsInsideRoom(player, furnitureModel, targetCFrame) then
		warn("Furniture rotate blocked: model would be outside room")
		return
	end

	if modelBlockedAtCFrame(player, furnitureModel, targetCFrame) then
		warn("Furniture rotate blocked: model would overlap something")
		return
	end

	local overlapsPlayer, blockingPlayer = modelWouldOverlapCharacter(player, furnitureModel, targetCFrame)

	if overlapsPlayer then
		warn("Furniture rotate blocked: would overlap player", blockingPlayer and blockingPlayer.Name)
		return
	end

	furnitureModel:PivotTo(targetCFrame)

	RoomPersistence.CaptureRoomState(player, getCurrentRoomModel(player))
end

local function pickUpFurniture(player, furnitureModel)
	if not canEditRoom(player) then
		sendPickUpResult(player, false, "Pick Up denied: enter Edit Mode in your own room first.")
		return
	end

	local roomModel = getCurrentRoomModel(player)

	if not roomModel then
		sendPickUpResult(player, false, "Pick Up denied: no current room.")
		return
	end

	if not isValidFurnitureForPlayer(player, furnitureModel) then
		sendPickUpResult(player, false, "Pick Up denied: invalid furniture.")
		return
	end

	local occupied, occupyingHumanoid = isFurnitureOccupied(furnitureModel)

	if occupied then
		sendPickUpResult(
			player,
			false,
			"Pick Up denied: furniture is occupied by "
				.. getOccupantNameFromHumanoid(occupyingHumanoid)
				.. "."
		)
		return
	end

	local templateId, resolvedThroughFallback = resolvePickupTemplateId(furnitureModel)

	if not templateId then
		sendPickUpResult(player, false, "This furniture cannot be picked up.")
		return
	end

	local isTradable = isPickupTradable(furnitureModel, resolvedThroughFallback)
	local added, message, newCount = RoomPersistence.AddInventoryItem(player, templateId, 1, {
		Tradable = isTradable,
	})

	if not added then
		sendPickUpResult(
			player,
			false,
			message or "Could not add item to inventory.",
			templateId,
			nil,
			isTradable
		)
		return
	end

	furnitureModel:Destroy()

	local roomState = RoomPersistence.CaptureRoomState(player, roomModel)
	local saved = false

	if roomState then
		saved = RoomPersistence.SavePlayer(player)

		if not saved then
			warn("Pick Up save flush failed for", player.Name, templateId)
		end
	else
		warn("Pick Up room capture failed for", player.Name, templateId)
	end

	local resultMessage = "Picked up " .. templateId .. "."

	if not saved then
		resultMessage = resultMessage .. " Save may be delayed."
	end

	sendPickUpResult(
		player,
		true,
		resultMessage,
		templateId,
		newCount,
		isTradable
	)
end

furnitureActionRequest.OnServerEvent:Connect(function(player, actionName, furnitureModel, extraData)
	if actionName == "Sit" or actionName == "Stand" then
		if not beginSeatAction(player) then
			return
		end

		local success, errorMessage = pcall(function()
			if actionName == "Sit" then
				sitPlayerOnChair(player, furnitureModel)
			else
				standPlayer(player)
			end
		end)

		endSeatAction(player)

		if not success then
			warn("Furniture seat action failed:", errorMessage)
		end

		return
	end

	if actionName == "Move" then
		moveFurniture(player, furnitureModel, extraData)

	elseif actionName == "Rotate" then
		rotateFurniture(player, furnitureModel)

	elseif actionName == "PickUp" then
		pickUpFurniture(player, furnitureModel)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	seatActionInFlightByUserId[player.UserId] = nil
	lastSeatActionAtByUserId[player.UserId] = nil
end)
