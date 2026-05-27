--Explorer/ServerScriptService/FurnitureActionServer.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local RoomPersistence = require(ServerScriptService:WaitForChild("RoomPersistence"))
local RoomPermissionService = require(ServerScriptService:WaitForChild("RoomPermissionService"))
local GridConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GridConfig"))

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

local SIT_STAND_COOLDOWN_SECONDS = 0.35
local ENTRANCE_BRIDGE_DISTANCE = 8
local ENTRANCE_BRIDGE_REACHED_DISTANCE = 3
local ENTRANCE_BRIDGE_TIMEOUT_SECONDS = 5

local seatActionInFlightByUserId = {}
local lastSeatActionAtByUserId = {}
local openCloseClosedCFrames = setmetatable({}, {
	__mode = "k",
})

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

local function findCurrentRoomMarker(player, markerName)
	local roomModel = getCurrentRoomModel(player)

	if not roomModel then
		return nil
	end

	local marker = roomModel:FindFirstChild(markerName, true)

	if marker and (marker:IsA("BasePart") or marker:IsA("Attachment")) then
		return marker
	end

	return nil
end

local function getMarkerWorldPosition(marker)
	if not marker then
		return nil
	end

	if marker:IsA("Attachment") then
		return marker.WorldPosition
	end

	if marker:IsA("BasePart") then
		return marker.Position
	end

	return nil
end

local function getCurrentDoorSpawn(player)
	return findCurrentRoomMarker(player, "DoorSpawn")
end

local function getCurrentEntryWalkTarget(player)
	return findCurrentRoomMarker(player, "EntryWalkTarget")
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

local function sendPickUpResult(player, success, message, templateId, newCount, tradable, sellable, inventoryDetails)
	if not player or player.Parent ~= Players then
		return
	end

	if typeof(sellable) == "table" and inventoryDetails == nil then
		inventoryDetails = sellable
		sellable = nil
	end

	furnitureActionResult:FireClient(player, {
		Kind = "PickUp",
		Success = success == true,
		Message = tostring(message or ""),
		TemplateId = templateId,
		NewCount = newCount,
		Tradable = tradable == true,
		Sellable = sellable == true,
		InventoryDetails = inventoryDetails,
	})
end

local function sendOpenCloseResult(player, success, message, isOpen)
	if not player or player.Parent ~= Players then
		return
	end

	furnitureActionResult:FireClient(player, {
		Kind = "OpenClose",
		Success = success == true,
		Message = tostring(message or ""),
		IsOpen = isOpen == true,
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

local function isPickupSellable(furnitureModel, resolvedThroughFallback)
	if furnitureModel:GetAttribute("Sellable") == false then
		return false
	end

	if furnitureModel:GetAttribute("CanSell") == false then
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

local function getCharacterRootPartFromHumanoid(humanoid)
	if not humanoid then
		return nil, nil
	end

	local character = humanoid.Parent

	if not character then
		return nil, nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not rootPart then
		return nil, nil
	end

	return character, rootPart
end

local function getOccupiedSeatCFrame(furnitureModel, humanoid, seatPart)
	local humanoidSeatPart = humanoid and humanoid.SeatPart

	if humanoidSeatPart
		and humanoidSeatPart:IsA("BasePart")
		and humanoidSeatPart:IsDescendantOf(furnitureModel) then

		return humanoidSeatPart.CFrame
	end

	if seatPart
		and seatPart:IsA("BasePart")
		and seatPart:IsDescendantOf(furnitureModel)
		and (seatPart:IsA("Seat") or seatPart:IsA("VehicleSeat")) then

		return seatPart.CFrame
	end

	return nil
end

local function findNamedSeatCFrame(furnitureModel)
	for _, descendant in ipairs(furnitureModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == "Seat" then
			return descendant.CFrame, descendant
		end
	end

	return nil, nil
end

local function getStandFloor(player)
	local roomFolder = getCurrentRoomFolder(player)

	if not roomFolder then
		return nil
	end

	local floor = roomFolder:FindFirstChild("WalkableFloor")

	if floor and floor:IsA("BasePart") then
		return floor
	end

	return nil
end

local function getSafeStandCFrameFromSource(player, humanoid, rootPart, sourceCFrame)
	if not sourceCFrame then
		return nil
	end

	local rotation = sourceCFrame - sourceCFrame.Position
	local sourcePosition = sourceCFrame.Position
	local targetY = sourcePosition.Y + 3
	local floor = getStandFloor(player)

	if floor then
		local floorTopY = floor.Position.Y + floor.Size.Y / 2
		local rootHalfY = rootPart.Size.Y / 2

		targetY = math.max(
			sourcePosition.Y,
			floorTopY + humanoid.HipHeight + rootHalfY + 0.1
		)
	end

	local position = Vector3.new(sourcePosition.X, targetY, sourcePosition.Z)

	return CFrame.new(position) * rotation
end

-- Forced unseats happen when occupied furniture is moved or picked up. In that case,
-- use the actual Seat first so the occupant exits from the furniture's current seat.
local function getFurnitureStandCFrame(player, furnitureModel, humanoid, rootPart, seatPart)
	local baseCFrame = getOccupiedSeatCFrame(furnitureModel, humanoid, seatPart)

	if not baseCFrame then
		local seatCFrame = findNamedSeatCFrame(furnitureModel)

		if seatCFrame then
			baseCFrame = seatCFrame
		end
	end

	if not baseCFrame then
		baseCFrame = getInteractionWorldCFrame(furnitureModel, "SitPoint")
	end

	if not baseCFrame then
		baseCFrame = furnitureModel:GetPivot()
	end

	return getSafeStandCFrameFromSource(player, humanoid, rootPart, baseCFrame)
end

local warnedNormalSitPointPlacement = setmetatable({}, {
	__mode = "k",
})

local standPointIgnoredPartNames = {
	SitPoint = true,
	SleepPoint = true,
	PlayPoint = true,
	EnterPoint = true,
	TalkPoint = true,
}

local function warnIfNormalSitPointMayBeBlocked(player, furnitureModel, standCFrame, character)
	if warnedNormalSitPointPlacement[furnitureModel] then
		return
	end

	local roomFolder = getCurrentRoomFolder(player)
	local furnitureFolder = getCurrentFurnitureFolder(player)

	if not roomFolder or not furnitureFolder then
		return
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = character and { character } or {}

	local parts = workspace:GetPartBoundsInBox(
		standCFrame,
		Vector3.new(1.5, 4, 1.5),
		overlapParams
	)

	for _, part in ipairs(parts) do
		if part.Name == "WalkableFloor" then
			continue
		end

		if standPointIgnoredPartNames[part.Name] then
			continue
		end

		if part:IsA("BasePart") and part.CanCollide == false then
			continue
		end

		if part:IsDescendantOf(roomFolder) or part:IsDescendantOf(furnitureFolder) then
			warn("SitPoint may be incorrectly placed")
			warnedNormalSitPointPlacement[furnitureModel] = true
			return
		end
	end
end

-- Normal Stand is the player's intentional chair exit. It should use SitPoint first
-- so click-to-move starts from the walkable tile beside the chair, not the Seat tile.
local function getNormalStandCFrame(player, furnitureModel, humanoid, rootPart, seatPart, character)
	local sitPointCFrame = getInteractionWorldCFrame(furnitureModel, "SitPoint")

	if sitPointCFrame then
		local standCFrame = getSafeStandCFrameFromSource(player, humanoid, rootPart, sitPointCFrame)

		if standCFrame then
			warnIfNormalSitPointMayBeBlocked(player, furnitureModel, standCFrame, character)
			return standCFrame
		end
	end

	local fallbackCFrame = getOccupiedSeatCFrame(furnitureModel, humanoid, seatPart)

	if not fallbackCFrame then
		local seatCFrame = findNamedSeatCFrame(furnitureModel)

		if seatCFrame then
			fallbackCFrame = seatCFrame
		end
	end

	if not fallbackCFrame then
		fallbackCFrame = furnitureModel:GetPivot()
	end

	return getSafeStandCFrameFromSource(player, humanoid, rootPart, fallbackCFrame)
end

local function standOccupantFromFurniture(player, furnitureModel, humanoid, seatPart, standCFrame)
	local character, rootPart = getCharacterRootPartFromHumanoid(humanoid)

	if not character or not rootPart then
		return false
	end

	standCFrame = standCFrame
		or getFurnitureStandCFrame(player, furnitureModel, humanoid, rootPart, seatPart)

	humanoid.Sit = false
	humanoid.PlatformStand = false
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	task.wait(0.03)

	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(standCFrame)

	task.wait(0.03)

	if rootPart.Parent then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
		rootPart.CFrame = standCFrame
	end

	return true
end

local function alignCharacterToSeatFacing(rootPart, seat)
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	if not seat or not seat:IsA("BasePart") then
		return
	end

	local lookVector = seat.CFrame.LookVector
	local flatLookVector = Vector3.new(lookVector.X, 0, lookVector.Z)

	if flatLookVector.Magnitude < 0.001 then
		return
	end

	rootPart.AssemblyAngularVelocity = Vector3.zero
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flatLookVector.Unit)
end

local function snapToGrid(value)
	return math.floor((value / GRID_SIZE) + 0.5) * GRID_SIZE
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

local function positionIsInsideMovementBounds(player, position)
	local bounds = getMovementRoomBounds(player)

	if not bounds or typeof(position) ~= "Vector3" then
		return false
	end

	local tolerance = 0.05

	return position.X >= bounds.minX - tolerance
		and position.X <= bounds.maxX + tolerance
		and position.Z >= bounds.minZ - tolerance
		and position.Z <= bounds.maxZ + tolerance
end

local function playerIsNearDoorSpawn(player, rootPosition)
	local doorSpawnPosition = getMarkerWorldPosition(getCurrentDoorSpawn(player))

	if not doorSpawnPosition or typeof(rootPosition) ~= "Vector3" then
		return false
	end

	return (rootPosition - doorSpawnPosition).Magnitude <= ENTRANCE_BRIDGE_DISTANCE
end

local entranceMarkerPartNames = {
	DoorSpawn = true,
	EntryWalkTarget = true,
	RoomExitZone = true,
}

local sitPathIgnoredPartNames = {
	SitPoint = true,
	SleepPoint = true,
	PlayPoint = true,
	EnterPoint = true,
	TalkPoint = true,
	ClickHitbox = true,
	PlacementBounds = true,
	CollisionBuffer = true,
	DoorSpawn = true,
	EntryWalkTarget = true,
	RoomExitZone = true,
}

local warnedSitPointInsideFurnitureFootprint = setmetatable({}, {
	__mode = "k",
})

local function isEntranceMarkerPart(part)
	return typeof(part) == "Instance"
		and part:IsA("BasePart")
		and (
			entranceMarkerPartNames[part.Name] == true
			or part:GetAttribute("IsRoomExit") == true
			or part:GetAttribute("IsEntranceMarker") == true
			or part:GetAttribute("IsDoorSpawn") == true
			or part:GetAttribute("IsEntryWalkTarget") == true
		)
end

local function isPartIgnoredForSitPath(part, targetFurnitureModel)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return false
	end

	if isEntranceMarkerPart(part) then
		return true
	end

	if sitPathIgnoredPartNames[part.Name] == true then
		return true
	end

	if part:GetAttribute("IsEntranceMarker") == true
		or part:GetAttribute("IsDoorSpawn") == true
		or part:GetAttribute("IsEntryWalkTarget") == true
		or part:GetAttribute("IsRoomExit") == true then

		return true
	end

	if targetFurnitureModel and part:IsDescendantOf(targetFurnitureModel) then
		return sitPathIgnoredPartNames[part.Name] == true
	end

	return false
end

local function getFurniturePathFootprintCenterPosition(furnitureModel)
	if not furnitureModel or not furnitureModel:IsA("Model") then
		return nil
	end

	local placementBoundsPositionSum = Vector3.zero
	local placementBoundsCount = 0

	for _, descendant in ipairs(furnitureModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == "PlacementBounds" then
			placementBoundsPositionSum += descendant.Position
			placementBoundsCount += 1
		end
	end

	if placementBoundsCount > 0 then
		return placementBoundsPositionSum / placementBoundsCount
	end

	return furnitureModel:GetPivot().Position
end

local function targetFurnitureOccupiesSitPathCell(furnitureModel, cell)
	local footprintCenter = getFurniturePathFootprintCenterPosition(furnitureModel)

	if not footprintCenter then
		return false
	end

	local centerCell = worldToCell(footprintCenter)

	return centerCell.x == cell.x and centerCell.z == cell.z
end

local function warnIfSitPointInsideFurnitureFootprint(player, furnitureModel, sitPointPosition)
	if warnedSitPointInsideFurnitureFootprint[furnitureModel] then
		return
	end

	if typeof(sitPointPosition) ~= "Vector3" then
		return
	end

	local sitPointCell = worldToCell(sitPointPosition)

	if targetFurnitureOccupiesSitPathCell(furnitureModel, sitPointCell) then
		warn("SitPoint appears to be inside the furniture footprint.")
		warnedSitPointInsideFurnitureFootprint[furnitureModel] = true
	end
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

local function isCellBlocked(player, cell, targetFurnitureModel)
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

	overlapParams.FilterDescendantsInstances = {}

	local parts = workspace:GetPartBoundsInBox(boxCFrame, boxSize, overlapParams)

	for _, part in ipairs(parts) do
		if part.Name == "WalkableFloor" then
			continue
		end

		if isPartIgnoredForSitPath(part, targetFurnitureModel) then
			continue
		end

		if targetFurnitureModel and part:IsDescendantOf(targetFurnitureModel) then
			if targetFurnitureOccupiesSitPathCell(targetFurnitureModel, cell) then
				return true
			end

			continue
		end

		if part:IsDescendantOf(furnitureFolder) then
			return true
		end

		if part:IsA("BasePart") and part.CanCollide == false then
			continue
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

local function moveHumanoidDirectToPosition(humanoid, rootPart, targetPosition, distance, timeoutSeconds)
	if not humanoid or not rootPart or typeof(targetPosition) ~= "Vector3" then
		return false
	end

	if (rootPart.Position - targetPosition).Magnitude <= distance then
		return true
	end

	local finished = false
	local connection = humanoid.MoveToFinished:Connect(function()
		finished = true
	end)

	humanoid:MoveTo(targetPosition)

	local startTime = os.clock()

	while os.clock() - startTime < timeoutSeconds do
		if not rootPart.Parent then
			connection:Disconnect()
			return false
		end

		if (rootPart.Position - targetPosition).Magnitude <= distance then
			connection:Disconnect()
			return true
		end

		if finished then
			break
		end

		task.wait(0.05)
	end

	connection:Disconnect()

	return (rootPart.Position - targetPosition).Magnitude <= distance
end

local function getEntryBridgeCellIfNeeded(player, rootPart)
	if not rootPart then
		return nil, nil, nil
	end

	local rootPosition = rootPart.Position
	local rootInsideRoom = positionIsInsideMovementBounds(player, rootPosition)
	local startCell = worldToCell(rootPosition)
	local startBlocked = isCellInsideRoom(player, startCell)
		and isCellBlocked(player, startCell, nil)

	if rootInsideRoom and not startBlocked then
		return nil, nil, nil
	end

	if not playerIsNearDoorSpawn(player, rootPosition) then
		return nil, nil, nil
	end

	local entryWalkTarget = getCurrentEntryWalkTarget(player)
	local entryPosition = getMarkerWorldPosition(entryWalkTarget)

	if not entryPosition then
		return nil, nil, nil
	end

	local entryCell = worldToCell(entryPosition)

	if not isCellInsideRoom(player, entryCell) then
		return nil, nil, "Cannot enter room grid from current position."
	end

	if isCellBlocked(player, entryCell, nil) then
		return nil, nil, "Room entrance is blocked."
	end

	local entryWorldPosition = cellToWorld(player, entryCell)

	if not entryWorldPosition then
		return nil, nil, "Cannot enter room grid from current position."
	end

	return entryCell, entryWorldPosition, nil
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
	local bridgeCell, bridgeWorldPosition, bridgeMessage = getEntryBridgeCellIfNeeded(player, rootPart)

	if bridgeMessage then
		return false, bridgeMessage
	end

	if bridgeCell then
		local reachedBridge = moveHumanoidDirectToPosition(
			humanoid,
			rootPart,
			bridgeWorldPosition,
			ENTRANCE_BRIDGE_REACHED_DISTANCE,
			ENTRANCE_BRIDGE_TIMEOUT_SECONDS
		)

		if not reachedBridge then
			local message = "Could not reach room entrance."
			return false, message
		end

		startCell = bridgeCell
	end

	if startCell.x == goalCell.x and startCell.z == goalCell.z then
		return true, nil
	end

	local path, reachedGoal = findGridPath(player, startCell, goalCell, furnitureToIgnore)

	if not path or #path == 0 then
		warn("No grid path found at all")
		return false, nil
	end

	local movementPath = compressGridPath(path)

	for index, cell in ipairs(movementPath) do
		if index == 1 then
			continue
		end

		local worldPosition = cellToWorld(player, cell)

		if not worldPosition then
			return false, nil
		end

		humanoid:MoveTo(worldPosition)

		local reached = humanoid.MoveToFinished:Wait()

		if not reached then
			-- Physical movement got blocked.
			-- This is fine for Habbo-style movement: stop here.
			return false, nil
		end
	end

	return reachedGoal, nil
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

	warnIfSitPointInsideFurnitureFootprint(player, furnitureModel, sitPointPosition)

	local function getHorizontalDistanceToSitPoint()
		return (
			Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
			- Vector3.new(sitPointPosition.X, 0, sitPointPosition.Z)
		).Magnitude
	end

	local closeEnoughToSit = getHorizontalDistanceToSitPoint() <= 3
	local reachedSitPoint = closeEnoughToSit
	local movementFailureMessage = nil

	if not reachedSitPoint then
		reachedSitPoint, movementFailureMessage = moveCharacterToGridPoint(
			player,
			character,
			sitPointPosition,
			furnitureModel
		)
	end

	closeEnoughToSit = getHorizontalDistanceToSitPoint() <= 3

	if not reachedSitPoint and not closeEnoughToSit then
		if movementFailureMessage then
			warn(movementFailureMessage)
		else
			warn("Cannot reach the seat.")
		end

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

	alignCharacterToSeatFacing(rootPart, seat)
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
			standCFrame = getNormalStandCFrame(player, furnitureModel, humanoid, rootPart, seatPart, character)
		end
	end

	-- Unseat the player first.
	humanoid.Sit = false
	humanoid.PlatformStand = false
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	task.wait(0.05)

	-- Normal chair exits use SitPoint. Occupied Move/PickUp use the Seat-first
	-- forced unseat helper instead.
	if standCFrame then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero

		character:PivotTo(standCFrame)

		task.wait(0.03)

		if rootPart.Parent then
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
			rootPart.CFrame = standCFrame
		end
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
	local roomModel = getCurrentRoomModel(player)
	local floor = getCurrentFloor(player)

	if not roomModel or not floor or not floor:IsA("BasePart") then
		return nil, "Invalid furniture target position"
	end

	if not GridConfig.UsesTileGrid(roomModel, floor) then
		return nil, "Furniture can only be moved in grid rooms."
	end

	local tileSize = GridConfig.GetTileSize(roomModel, floor)
	local snappedWorldPosition = GridConfig.SnapWorldToTileCenter(floor, position, tileSize)

	if not snappedWorldPosition then
		return nil, "Invalid furniture target position"
	end

	return Vector3.new(snappedWorldPosition.X, position.Y, snappedWorldPosition.Z)
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

local function modelWouldOverlapCharacter(editorPlayer, furnitureModel, targetCFrame, characterToIgnore)
	local currentPivot = furnitureModel:GetPivot()

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if playerIsInSameRoom(editorPlayer, otherPlayer) then
			local character = otherPlayer.Character

			if character and character ~= characterToIgnore then
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

local function modelWouldOverlapStandCFrame(furnitureModel, targetCFrame, standCFrame)
	local modelBounds = getModelXZBoundsAtCFrame(furnitureModel, targetCFrame)

	if not modelBounds or not standCFrame then
		return false
	end

	local position = standCFrame.Position
	local buffer = 1

	return position.X >= modelBounds.minX - buffer
		and position.X <= modelBounds.maxX + buffer
		and position.Z >= modelBounds.minZ - buffer
		and position.Z <= modelBounds.maxZ + buffer
end

local function getPersistencePlayerForRoomAction(roomModel)
	if not roomModel then
		return nil, "no current room"
	end

	local ownerPlayer = RoomPermissionService.GetRoomOwnerPlayer(roomModel)

	if not ownerPlayer then
		return nil, "room owner is not available"
	end

	if not RoomPersistence.GetProfile(ownerPlayer) then
		return nil, "room owner profile is not loaded"
	end

	return ownerPlayer
end

local function isOpenCloseTarget(instance)
	return typeof(instance) == "Instance"
		and (
			instance:IsA("BasePart")
			or instance:IsA("Model")
		)
end

local function findOpenCloseTargetByName(furnitureModel, targetName)
	if typeof(targetName) ~= "string" or targetName == "" or not targetName:match("%S") then
		return nil
	end

	local target = furnitureModel:FindFirstChild(targetName, true)

	if isOpenCloseTarget(target) then
		return target
	end

	return nil
end

local function getOpenCloseTarget(furnitureModel)
	local configuredTargetName = furnitureModel:GetAttribute("OpenCloseTargetName")
	local configuredTarget = findOpenCloseTargetByName(furnitureModel, configuredTargetName)

	if configuredTarget then
		return configuredTarget
	end

	local fallbackNames = {
		"OpenClosePart",
		"DoorPanel",
		"GatePanel",
		"Panel",
	}

	for _, targetName in ipairs(fallbackNames) do
		local target = findOpenCloseTargetByName(furnitureModel, targetName)

		if target then
			return target
		end
	end

	return nil
end

local function getOpenCloseTargetCFrame(target)
	if target:IsA("Model") then
		return target:GetPivot()
	end

	return target.CFrame
end

local function setOpenCloseTargetCFrame(target, targetCFrame)
	if target:IsA("Model") then
		target:PivotTo(targetCFrame)
	else
		target.CFrame = targetCFrame
	end
end

local function getOpenCloseRotation(furnitureModel)
	local angleDegrees = furnitureModel:GetAttribute("OpenAngleDegrees")

	if typeof(angleDegrees) ~= "number" then
		angleDegrees = 90
	end

	local angleRadians = math.rad(angleDegrees)
	local axis = furnitureModel:GetAttribute("OpenCloseAxis")

	if axis == "X" then
		return CFrame.Angles(angleRadians, 0, 0)
	end

	if axis == "Z" then
		return CFrame.Angles(0, 0, angleRadians)
	end

	return CFrame.Angles(0, angleRadians, 0)
end

local function openCloseFurniture(player, furnitureModel)
	if not isValidFurnitureForPlayer(player, furnitureModel) then
		sendOpenCloseResult(player, false, "Open/Close denied: invalid furniture.", false)
		return
	end

	if not RoomPermissionService.CanOpenCloseFurniture(player, furnitureModel) then
		sendOpenCloseResult(player, false, "Open/Close denied.", furnitureModel:GetAttribute("IsOpen") == true)
		return
	end

	local target = getOpenCloseTarget(furnitureModel)

	if not target then
		sendOpenCloseResult(
			player,
			false,
			"This furniture has no open/close target.",
			furnitureModel:GetAttribute("IsOpen") == true
		)
		return
	end

	local closedCFrame = openCloseClosedCFrames[target]

	if not closedCFrame then
		closedCFrame = getOpenCloseTargetCFrame(target)
		openCloseClosedCFrames[target] = closedCFrame
	end

	local currentlyOpen = furnitureModel:GetAttribute("IsOpen") == true

	-- OpenClose state is runtime-only for now and resets when the room reloads.
	-- Persisting door/gate state can be added later without changing placement CFrames.
	if currentlyOpen then
		setOpenCloseTargetCFrame(target, closedCFrame)
		furnitureModel:SetAttribute("IsOpen", false)
		sendOpenCloseResult(player, true, "Closed.", false)
	else
		local openCFrame = closedCFrame * getOpenCloseRotation(furnitureModel)

		setOpenCloseTargetCFrame(target, openCFrame)
		furnitureModel:SetAttribute("IsOpen", true)
		sendOpenCloseResult(player, true, "Opened.", true)
	end
end

local function moveFurniture(player, furnitureModel, targetPosition)
	if player:GetAttribute("RoomMode") ~= "Edit"
		or not RoomPermissionService.CanMoveFurniture(player, furnitureModel) then

		warn("Move denied: player does not have permission")
		return
	end
	
	if not isValidFurnitureForPlayer(player, furnitureModel) then
		warn("Invalid furniture move request")
		return
	end

	local roomModel = getCurrentRoomModel(player)
	local persistencePlayer, persistenceError = getPersistencePlayerForRoomAction(roomModel)

	if not persistencePlayer then
		warn("Move denied:", persistenceError)
		return
	end

	if typeof(targetPosition) ~= "Vector3" then
		warn("Invalid furniture target position")
		return
	end

	local currentPivot = furnitureModel:GetPivot()
	local snappedPosition, snapError = snapPositionInsideRoom(player, targetPosition)

	if not snappedPosition then
		warn(snapError or "Invalid furniture target position")
		return
	end

	local finalPosition = Vector3.new(
		snappedPosition.X,
		currentPivot.Position.Y,
		snappedPosition.Z
	)

	local currentRotation = currentPivot - currentPivot.Position
	local targetCFrame = CFrame.new(finalPosition) * currentRotation
	-- Keep the final pivot on the GridConfig tile center. If the model does not fit
	-- at that tile, validation below rejects it instead of clamping off-grid.

	if not modelFitsInsideRoom(player, furnitureModel, targetCFrame) then
		warn("Furniture move blocked: model would be outside room")
		return
	end

	if modelBlockedAtCFrame(player, furnitureModel, targetCFrame) then
		warn("Furniture move blocked: model would overlap something")
		return
	end

	local occupied, occupyingHumanoid, occupiedSeatPart = isFurnitureOccupied(furnitureModel)
	local occupyingCharacter = nil
	local occupantStandCFrame = nil

	if occupied and occupyingHumanoid then
		local occupyingRootPart = nil

		occupyingCharacter, occupyingRootPart = getCharacterRootPartFromHumanoid(occupyingHumanoid)

		if not occupyingRootPart then
			warn("Furniture move blocked: could not safely stand seated occupant")
			return
		end

		occupantStandCFrame =
			getFurnitureStandCFrame(player, furnitureModel, occupyingHumanoid, occupyingRootPart, occupiedSeatPart)
	end

	local overlapsPlayer, blockingPlayer =
		modelWouldOverlapCharacter(player, furnitureModel, targetCFrame, occupyingCharacter)

	if overlapsPlayer then
		warn("Furniture move blocked: would overlap player", blockingPlayer and blockingPlayer.Name)
		return
	end

	if occupied and modelWouldOverlapStandCFrame(furnitureModel, targetCFrame, occupantStandCFrame) then
		warn("Furniture move blocked: target overlaps seated player's stand position")
		return
	end

	if occupied and occupyingHumanoid then
		standOccupantFromFurniture(player, furnitureModel, occupyingHumanoid, occupiedSeatPart, occupantStandCFrame)
	end

	furnitureModel:PivotTo(targetCFrame)

	RoomPersistence.CaptureRoomState(persistencePlayer, roomModel)
end

local function rotateFurniture(player, furnitureModel)
	if player:GetAttribute("RoomMode") ~= "Edit"
		or not RoomPermissionService.CanRotateFurniture(player, furnitureModel) then

		warn("Rotate denied: player does not have permission")
		return
	end

	if not isValidFurnitureForPlayer(player, furnitureModel) then
		warn("Invalid furniture rotate request")
		return
	end

	local roomModel = getCurrentRoomModel(player)
	local persistencePlayer, persistenceError = getPersistencePlayerForRoomAction(roomModel)

	if not persistencePlayer then
		warn("Rotate denied:", persistenceError)
		return
	end
	
	local _, occupyingHumanoid = isFurnitureOccupied(furnitureModel)
	local occupyingCharacter = nil

	if occupyingHumanoid then
		occupyingCharacter = occupyingHumanoid.Parent
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

	local overlapsPlayer, blockingPlayer =
		modelWouldOverlapCharacter(player, furnitureModel, targetCFrame, occupyingCharacter)

	if overlapsPlayer then
		warn("Furniture rotate blocked: would overlap player", blockingPlayer and blockingPlayer.Name)
		return
	end

	furnitureModel:PivotTo(targetCFrame)

	RoomPersistence.CaptureRoomState(persistencePlayer, roomModel)
end

local function pickUpFurniture(player, furnitureModel)
	if player:GetAttribute("RoomMode") ~= "Edit"
		or not RoomPermissionService.CanPickUpFurniture(player, furnitureModel) then

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

	local occupied, occupyingHumanoid, occupiedSeatPart = isFurnitureOccupied(furnitureModel)

	local templateId, resolvedThroughFallback = resolvePickupTemplateId(furnitureModel)

	if not templateId then
		sendPickUpResult(player, false, "This furniture cannot be picked up.")
		return
	end

	if occupied and occupyingHumanoid then
		local _, occupantRootPart = getCharacterRootPartFromHumanoid(occupyingHumanoid)

		if not occupantRootPart then
			sendPickUpResult(player, false, "Could not safely stand the seated player.", templateId)
			return
		end
	end

	local isTradable = isPickupTradable(furnitureModel, resolvedThroughFallback)
	local isSellable = isPickupSellable(furnitureModel, resolvedThroughFallback)
	local added, message, newCount, inventoryDetails = RoomPersistence.AddInventoryItem(player, templateId, 1, {
		Tradable = isTradable,
		Sellable = isSellable,
	})

	if not added then
		sendPickUpResult(
			player,
			false,
			message or "Could not add item to inventory.",
			templateId,
			nil,
			isTradable,
			isSellable
		)
		return
	end

	if occupied and occupyingHumanoid then
		standOccupantFromFurniture(player, furnitureModel, occupyingHumanoid, occupiedSeatPart)
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
		isTradable,
		isSellable,
		inventoryDetails
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

	elseif actionName == "OpenClose" then
		openCloseFurniture(player, furnitureModel)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	seatActionInFlightByUserId[player.UserId] = nil
	lastSeatActionAtByUserId[player.UserId] = nil
end)
