local GridConfig = {}

-- Shared grid configuration for the 4-stud tile system.
-- Public spaces may opt out by setting UsesTileGrid = false.

GridConfig.TILE_SIZE = 4
GridConfig.DEFAULT_GRID_WIDTH = 5
GridConfig.DEFAULT_GRID_DEPTH = 7
GridConfig.HOVER_TILE_SIZE = 4
GridConfig.FOOTPRINT_MARGIN = 0.4
GridConfig.MAX_FOOTPRINT_TILES = 20
GridConfig.RECOMMENDED_PLACEMENT_BOUNDS_HEIGHT = 4
GridConfig.GRID_VALIDATION_TOLERANCE = 0.05

GridConfig.TILE_SIZE_ATTRIBUTE = "TileSize"
GridConfig.GRID_WIDTH_ATTRIBUTE = "GridWidth"
GridConfig.GRID_DEPTH_ATTRIBUTE = "GridDepth"
GridConfig.USES_TILE_GRID_ATTRIBUTE = "UsesTileGrid"
GridConfig.USES_TILE_MASK_ATTRIBUTE = "UsesTileMask"
GridConfig.TILE_MASK_FOLDER_NAME = "TileMask"
GridConfig.WALKABLE_TILE_ATTRIBUTE = "IsWalkableTile"
GridConfig.TILE_X_ATTRIBUTE = "TileX"
GridConfig.TILE_Z_ATTRIBUTE = "TileZ"
GridConfig.DEBUG_TILE_MASK = false

-- Starter player-room standard:
-- TileSize = 4, GridWidth = 5, GridDepth = 7.
-- That means WalkableFloor.Size.X = 20 and WalkableFloor.Size.Z = 28.
-- Validation is warning-only; room templates must still be adjusted in Studio.

local MIN_FOOTPRINT_STUDS = 0.1
local tileMaskCache = setmetatable({}, { __mode = "k" })

local function isInstance(value)
	return typeof(value) == "Instance"
end

local function isPositiveNumber(value)
	return typeof(value) == "number" and value > 0 and value == value
end

local function isPositiveInteger(value)
	return isPositiveNumber(value) and value % 1 == 0
end

local function getPositiveNumberAttribute(instance, attributeName)
	if not isInstance(instance) then
		return nil
	end

	local value = instance:GetAttribute(attributeName)

	if isPositiveNumber(value) then
		return value
	end

	return nil
end

local function getPositiveIntegerAttribute(instance, attributeName)
	if not isInstance(instance) then
		return nil
	end

	local value = instance:GetAttribute(attributeName)

	if isPositiveInteger(value) then
		return value
	end

	return nil
end

local function findWalkableFloor(roomModel)
	if not isInstance(roomModel) then
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

local function findRoomModelFromInstance(instance)
	if not isInstance(instance) then
		return nil
	end

	local current = instance

	while current do
		if current:IsA("Model") and findWalkableFloor(current) then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function resolveRoomModelAndFloor(roomModelOrFloor)
	if typeof(roomModelOrFloor) == "table" then
		local roomModel = roomModelOrFloor.RoomModel
		local floor = roomModelOrFloor.Floor

		if isInstance(roomModel) and isInstance(floor) and floor:IsA("BasePart") then
			return roomModel, floor
		end

		if isInstance(floor) and floor:IsA("BasePart") then
			return findRoomModelFromInstance(floor), floor
		end

		if isInstance(roomModel) and roomModel:IsA("Model") then
			return roomModel, findWalkableFloor(roomModel)
		end

		return nil, nil
	end

	if not isInstance(roomModelOrFloor) then
		return nil, nil
	end

	if roomModelOrFloor:IsA("BasePart") then
		return findRoomModelFromInstance(roomModelOrFloor), roomModelOrFloor
	end

	if roomModelOrFloor:IsA("Model") then
		return roomModelOrFloor, findWalkableFloor(roomModelOrFloor)
	end

	return nil, nil
end

local function getTileMaskCacheKey(roomModel, floor)
	if isInstance(roomModel) then
		return roomModel
	end

	if isInstance(floor) then
		return floor
	end

	return nil
end

local function debugTileMaskWarning(message)
	if GridConfig.DEBUG_TILE_MASK == true then
		warn("[GridConfig.TileMask] " .. tostring(message))
	end
end

local function hasTileMaskEnabled(roomModel, floor)
	if isInstance(roomModel) and roomModel:GetAttribute(GridConfig.USES_TILE_MASK_ATTRIBUTE) == true then
		return true
	end

	if isInstance(floor) and floor:GetAttribute(GridConfig.USES_TILE_MASK_ATTRIBUTE) == true then
		return true
	end

	return false
end

local function findTileMaskFolder(roomModel, floor)
	local roomFolder = isInstance(roomModel) and roomModel:FindFirstChild("Room") or nil
	local tileMaskFolder = roomFolder and roomFolder:FindFirstChild(GridConfig.TILE_MASK_FOLDER_NAME) or nil

	if tileMaskFolder and tileMaskFolder:IsA("Folder") then
		return tileMaskFolder
	end

	if isInstance(floor) and floor.Parent then
		tileMaskFolder = floor.Parent:FindFirstChild(GridConfig.TILE_MASK_FOLDER_NAME)

		if tileMaskFolder and tileMaskFolder:IsA("Folder") then
			return tileMaskFolder
		end
	end

	return nil
end

local function getBaseGridContext(roomModelOrFloor)
	if typeof(roomModelOrFloor) == "table"
		and isInstance(roomModelOrFloor.Floor)
		and roomModelOrFloor.Floor:IsA("BasePart")
		and isPositiveNumber(roomModelOrFloor.TileSize)
		and isPositiveInteger(roomModelOrFloor.GridWidth)
		and isPositiveInteger(roomModelOrFloor.GridDepth) then

		return {
			RoomModel = isInstance(roomModelOrFloor.RoomModel) and roomModelOrFloor.RoomModel or nil,
			Floor = roomModelOrFloor.Floor,
			TileSize = roomModelOrFloor.TileSize,
			GridWidth = roomModelOrFloor.GridWidth,
			GridDepth = roomModelOrFloor.GridDepth,
			UsesTileMask = false,
			Mask = nil,
		}
	end

	local roomModel, floor = resolveRoomModelAndFloor(roomModelOrFloor)

	if not isInstance(floor) or not floor:IsA("BasePart") then
		return nil
	end

	local tileSize = GridConfig.GetTileSize(roomModel, floor)
	local gridWidth = GridConfig.GetGridWidth(roomModel, floor)
	local gridDepth = GridConfig.GetGridDepth(roomModel, floor)

	return {
		RoomModel = roomModel,
		Floor = floor,
		TileSize = tileSize,
		GridWidth = gridWidth,
		GridDepth = gridDepth,
		UsesTileMask = false,
		Mask = nil,
	}
end

local function roundToPositiveInteger(value)
	if not isPositiveNumber(value) then
		return nil
	end

	local rounded = math.floor(value + 0.5)

	if rounded < 1 then
		return nil
	end

	return rounded
end

local function normalizePositiveInteger(value, defaultValue, maxValue)
	local normalized = isPositiveInteger(value) and value or defaultValue

	normalized = math.floor(normalized)

	if normalized < 1 then
		normalized = 1
	end

	if isPositiveInteger(maxValue) then
		normalized = math.min(normalized, maxValue)
	end

	return normalized
end

local function snapAxisToTileCenter(value, tileSize, tileCount)
	if isPositiveInteger(tileCount) then
		local halfStuds = tileCount * tileSize / 2
		local minCenter = -halfStuds + tileSize / 2
		local maxIndex = tileCount - 1
		local index = math.floor(((value - minCenter) / tileSize) + 0.5)
		index = math.clamp(index, 0, maxIndex)

		return minCenter + index * tileSize
	end

	return math.floor((value / tileSize) + 0.5) * tileSize
end

function GridConfig.GetTileSize(roomModel, floor)
	return getPositiveNumberAttribute(floor, GridConfig.TILE_SIZE_ATTRIBUTE)
		or getPositiveNumberAttribute(roomModel, GridConfig.TILE_SIZE_ATTRIBUTE)
		or GridConfig.TILE_SIZE
end

function GridConfig.GetGridWidth(roomModel, floor)
	local attributeValue = getPositiveIntegerAttribute(floor, GridConfig.GRID_WIDTH_ATTRIBUTE)
		or getPositiveIntegerAttribute(roomModel, GridConfig.GRID_WIDTH_ATTRIBUTE)

	if attributeValue then
		return attributeValue
	end

	if isInstance(floor) and floor:IsA("BasePart") then
		local tileSize = GridConfig.GetTileSize(roomModel, floor)
		local derivedWidth = roundToPositiveInteger(floor.Size.X / tileSize)

		if derivedWidth then
			return derivedWidth
		end
	end

	return GridConfig.DEFAULT_GRID_WIDTH
end

function GridConfig.GetGridDepth(roomModel, floor)
	local attributeValue = getPositiveIntegerAttribute(floor, GridConfig.GRID_DEPTH_ATTRIBUTE)
		or getPositiveIntegerAttribute(roomModel, GridConfig.GRID_DEPTH_ATTRIBUTE)

	if attributeValue then
		return attributeValue
	end

	if isInstance(floor) and floor:IsA("BasePart") then
		local tileSize = GridConfig.GetTileSize(roomModel, floor)
		local derivedDepth = roundToPositiveInteger(floor.Size.Z / tileSize)

		if derivedDepth then
			return derivedDepth
		end
	end

	return GridConfig.DEFAULT_GRID_DEPTH
end

function GridConfig.UsesTileGrid(roomModel, floor)
	if isInstance(floor) and floor:GetAttribute(GridConfig.USES_TILE_GRID_ATTRIBUTE) == false then
		return false
	end

	if isInstance(roomModel) and roomModel:GetAttribute(GridConfig.USES_TILE_GRID_ATTRIBUTE) == false then
		return false
	end

	return true
end

function GridConfig.GetFloorTopY(floor)
	if not isInstance(floor) or not floor:IsA("BasePart") then
		return nil
	end

	return floor.Position.Y + floor.Size.Y / 2
end

function GridConfig.WorldToFloorLocal(floor, worldPosition)
	if not isInstance(floor) or not floor:IsA("BasePart") or typeof(worldPosition) ~= "Vector3" then
		return nil
	end

	return floor.CFrame:PointToObjectSpace(worldPosition)
end

function GridConfig.FloorLocalToWorld(floor, localPosition)
	if not isInstance(floor) or not floor:IsA("BasePart") or typeof(localPosition) ~= "Vector3" then
		return nil
	end

	return floor.CFrame:PointToWorldSpace(localPosition)
end

function GridConfig.SnapLocalToTileCenter(localPosition, tileSize, gridWidth, gridDepth)
	if typeof(localPosition) ~= "Vector3" then
		return nil
	end

	local resolvedTileSize = isPositiveNumber(tileSize) and tileSize or GridConfig.TILE_SIZE
	local snappedX = snapAxisToTileCenter(localPosition.X, resolvedTileSize, gridWidth)
	local snappedZ = snapAxisToTileCenter(localPosition.Z, resolvedTileSize, gridDepth)

	return Vector3.new(snappedX, localPosition.Y, snappedZ)
end

function GridConfig.SnapWorldToTileCenter(floor, worldPosition, tileSize)
	if not isInstance(floor) or not floor:IsA("BasePart") or typeof(worldPosition) ~= "Vector3" then
		return nil, nil
	end

	local resolvedTileSize = isPositiveNumber(tileSize) and tileSize or GridConfig.GetTileSize(nil, floor)
	local localPosition = GridConfig.WorldToFloorLocal(floor, worldPosition)

	if not localPosition then
		return nil, nil
	end

	local gridWidth = GridConfig.GetGridWidth(nil, floor)
	local gridDepth = GridConfig.GetGridDepth(nil, floor)
	local snappedLocalPosition = GridConfig.SnapLocalToTileCenter(localPosition, resolvedTileSize, gridWidth, gridDepth)

	if not snappedLocalPosition then
		return nil, nil
	end

	local worldY = worldPosition.Y
	local floorTopY = GridConfig.GetFloorTopY(floor)

	if floorTopY then
		worldY = math.max(worldY, floorTopY)
	end

	local snappedWorldPosition = GridConfig.FloorLocalToWorld(
		floor,
		Vector3.new(snappedLocalPosition.X, localPosition.Y, snappedLocalPosition.Z)
	)

	if not snappedWorldPosition then
		return nil, nil
	end

	snappedWorldPosition = Vector3.new(snappedWorldPosition.X, worldY, snappedWorldPosition.Z)

	return snappedWorldPosition, snappedLocalPosition
end

function GridConfig.GetTileBounds(roomModel, floor)
	local tileSize = GridConfig.GetTileSize(roomModel, floor)
	local gridWidth = GridConfig.GetGridWidth(roomModel, floor)
	local gridDepth = GridConfig.GetGridDepth(roomModel, floor)

	return {
		TileSize = tileSize,
		GridWidth = gridWidth,
		GridDepth = gridDepth,
		HalfWidthStuds = gridWidth * tileSize / 2,
		HalfDepthStuds = gridDepth * tileSize / 2,
	}
end

function GridConfig.CellKey(cellX, cellZ)
	return tostring(cellX) .. "," .. tostring(cellZ)
end

local function getIntegerTileAttribute(marker, attributeName)
	if not isInstance(marker) then
		return nil
	end

	local value = marker:GetAttribute(attributeName)

	if isPositiveInteger(value) then
		return value
	end

	return nil
end

local function getCellLocalX(context, cellX)
	return -(context.GridWidth * context.TileSize) / 2 + context.TileSize / 2 + (cellX - 1) * context.TileSize
end

local function getCellLocalZ(context, cellZ)
	return -(context.GridDepth * context.TileSize) / 2 + context.TileSize / 2 + (cellZ - 1) * context.TileSize
end

local function buildTileMask(context)
	if typeof(context) ~= "table" or not hasTileMaskEnabled(context.RoomModel, context.Floor) then
		return nil
	end

	local tileMaskFolder = findTileMaskFolder(context.RoomModel, context.Floor)

	if not tileMaskFolder then
		debugTileMaskWarning("UsesTileMask is true but Room/TileMask folder is missing.")
		return nil
	end

	local cells = {}
	local cellList = {}

	for _, marker in ipairs(tileMaskFolder:GetChildren()) do
		if not marker:IsA("BasePart") then
			debugTileMaskWarning("Ignoring non-BasePart tile marker: " .. marker.Name)
			continue
		end

		if marker:GetAttribute(GridConfig.WALKABLE_TILE_ATTRIBUTE) ~= true then
			debugTileMaskWarning("Ignoring marker without IsWalkableTile = true: " .. marker.Name)
			continue
		end

		local tileX = getIntegerTileAttribute(marker, GridConfig.TILE_X_ATTRIBUTE)
		local tileZ = getIntegerTileAttribute(marker, GridConfig.TILE_Z_ATTRIBUTE)

		if not tileX or not tileZ then
			debugTileMaskWarning("Ignoring marker with invalid TileX/TileZ: " .. marker.Name)
			continue
		end

		if tileX < 1 or tileX > context.GridWidth or tileZ < 1 or tileZ > context.GridDepth then
			debugTileMaskWarning("Ignoring out-of-range tile marker: " .. marker.Name)
			continue
		end

		local key = GridConfig.CellKey(tileX, tileZ)

		if not cells[key] then
			cells[key] = true
			table.insert(cellList, {
				X = tileX,
				Z = tileZ,
			})
		end
	end

	if #cellList == 0 then
		debugTileMaskWarning("UsesTileMask is true but no valid tile markers were found.")
		return nil
	end

	table.sort(cellList, function(a, b)
		if a.Z ~= b.Z then
			return a.Z < b.Z
		end

		return a.X < b.X
	end)

	return {
		Cells = cells,
		CellList = cellList,
		Count = #cellList,
		Folder = tileMaskFolder,
	}
end

local function getTileMaskForContext(context)
	if typeof(context) ~= "table" then
		return nil
	end

	if not hasTileMaskEnabled(context.RoomModel, context.Floor) then
		return nil
	end

	local cacheKey = getTileMaskCacheKey(context.RoomModel, context.Floor)

	if cacheKey and tileMaskCache[cacheKey] then
		return tileMaskCache[cacheKey]
	end

	local mask = buildTileMask(context)

	if cacheKey and mask then
		tileMaskCache[cacheKey] = mask
	end

	return mask
end

function GridConfig.GetTileMask(roomModelOrFloor)
	if typeof(roomModelOrFloor) == "table"
		and roomModelOrFloor.UsesTileMask == true
		and typeof(roomModelOrFloor.Mask) == "table" then

		return roomModelOrFloor.Mask
	end

	local context = getBaseGridContext(roomModelOrFloor)

	if not context then
		return nil
	end

	return getTileMaskForContext(context)
end

function GridConfig.UsesTileMask(roomModelOrFloor)
	return GridConfig.GetTileMask(roomModelOrFloor) ~= nil
end

function GridConfig.GetGridContext(floorOrRoomModel)
	local context = getBaseGridContext(floorOrRoomModel)

	if not context then
		return nil
	end

	local mask = getTileMaskForContext(context)
	context.Mask = mask
	context.UsesTileMask = mask ~= nil

	return context
end

local function getResolvedGridContext(contextOrRoomModelOrFloor)
	if typeof(contextOrRoomModelOrFloor) == "table"
		and isInstance(contextOrRoomModelOrFloor.Floor)
		and contextOrRoomModelOrFloor.Floor:IsA("BasePart")
		and isPositiveNumber(contextOrRoomModelOrFloor.TileSize)
		and isPositiveInteger(contextOrRoomModelOrFloor.GridWidth)
		and isPositiveInteger(contextOrRoomModelOrFloor.GridDepth) then

		if contextOrRoomModelOrFloor.UsesTileMask == true and typeof(contextOrRoomModelOrFloor.Mask) == "table" then
			return contextOrRoomModelOrFloor
		end

		local mask = getTileMaskForContext(contextOrRoomModelOrFloor)
		local resolvedContext = {
			RoomModel = contextOrRoomModelOrFloor.RoomModel,
			Floor = contextOrRoomModelOrFloor.Floor,
			TileSize = contextOrRoomModelOrFloor.TileSize,
			GridWidth = contextOrRoomModelOrFloor.GridWidth,
			GridDepth = contextOrRoomModelOrFloor.GridDepth,
			Mask = mask,
			UsesTileMask = mask ~= nil,
		}

		return resolvedContext
	end

	return GridConfig.GetGridContext(contextOrRoomModelOrFloor)
end

function GridConfig.CellIsWalkable(contextOrRoomModelOrFloor, cellX, cellZ)
	if not isPositiveInteger(cellX) or not isPositiveInteger(cellZ) then
		return false
	end

	local context = getResolvedGridContext(contextOrRoomModelOrFloor)

	if not context then
		return false
	end

	if context.UsesTileMask == true and context.Mask then
		return context.Mask.Cells[GridConfig.CellKey(cellX, cellZ)] == true
	end

	return cellX >= 1
		and cellX <= context.GridWidth
		and cellZ >= 1
		and cellZ <= context.GridDepth
end

function GridConfig.GetWalkableCells(contextOrRoomModelOrFloor)
	local context = getResolvedGridContext(contextOrRoomModelOrFloor)
	local cellList = {}

	if not context then
		return cellList
	end

	if context.UsesTileMask == true and context.Mask then
		for _, cell in ipairs(context.Mask.CellList) do
			table.insert(cellList, {
				X = cell.X,
				Z = cell.Z,
			})
		end

		return cellList
	end

	for tileZ = 1, context.GridDepth do
		for tileX = 1, context.GridWidth do
			table.insert(cellList, {
				X = tileX,
				Z = tileZ,
			})
		end
	end

	return cellList
end

function GridConfig.WorldToCell(contextOrFloor, worldPosition)
	if typeof(worldPosition) ~= "Vector3" then
		return nil, nil
	end

	local context = getResolvedGridContext(contextOrFloor)

	if not context then
		return nil, nil
	end

	local localPosition = GridConfig.WorldToFloorLocal(context.Floor, worldPosition)

	if not localPosition then
		return nil, nil
	end

	local minCenterX = getCellLocalX(context, 1)
	local minCenterZ = getCellLocalZ(context, 1)
	local cellX = math.floor(((localPosition.X - minCenterX) / context.TileSize) + 0.5) + 1
	local cellZ = math.floor(((localPosition.Z - minCenterZ) / context.TileSize) + 0.5) + 1

	cellX = math.clamp(cellX, 1, context.GridWidth)
	cellZ = math.clamp(cellZ, 1, context.GridDepth)

	return cellX, cellZ
end

function GridConfig.CellToWorld(contextOrFloor, cellX, cellZ)
	if not isPositiveInteger(cellX) or not isPositiveInteger(cellZ) then
		return nil
	end

	local context = getResolvedGridContext(contextOrFloor)

	if not context then
		return nil
	end

	local localPosition = Vector3.new(
		getCellLocalX(context, cellX),
		context.Floor.Size.Y / 2,
		getCellLocalZ(context, cellZ)
	)

	return GridConfig.FloorLocalToWorld(context.Floor, localPosition)
end

function GridConfig.FootprintCellsAreWalkable(
	contextOrFloor,
	centerCellX,
	centerCellZ,
	footprintWidth,
	footprintDepth,
	rotationQuarterTurns
)
	local context = getResolvedGridContext(contextOrFloor)
	local cells = {}

	if not context
		or not isPositiveInteger(centerCellX)
		or not isPositiveInteger(centerCellZ) then

		return false, cells
	end

	local resolvedWidth = normalizePositiveInteger(footprintWidth, 1, GridConfig.MAX_FOOTPRINT_TILES)
	local resolvedDepth = normalizePositiveInteger(footprintDepth, 1, GridConfig.MAX_FOOTPRINT_TILES)
	local resolvedQuarterTurns = typeof(rotationQuarterTurns) == "number" and math.floor(rotationQuarterTurns) or 0

	if math.abs(resolvedQuarterTurns) % 2 == 1 then
		resolvedWidth, resolvedDepth = resolvedDepth, resolvedWidth
	end

	local minX = centerCellX - math.floor((resolvedWidth - 1) / 2)
	local minZ = centerCellZ - math.floor((resolvedDepth - 1) / 2)
	local allWalkable = true

	for tileZ = minZ, minZ + resolvedDepth - 1 do
		for tileX = minX, minX + resolvedWidth - 1 do
			table.insert(cells, {
				X = tileX,
				Z = tileZ,
			})

			if not GridConfig.CellIsWalkable(context, tileX, tileZ) then
				allWalkable = false
			end
		end
	end

	return allWalkable, cells
end

function GridConfig.ClearTileMaskCache(roomModelOrFloor)
	local roomModel, floor = resolveRoomModelAndFloor(roomModelOrFloor)
	local cacheKey = getTileMaskCacheKey(roomModel, floor)

	if cacheKey then
		tileMaskCache[cacheKey] = nil
	end
end

function GridConfig.GetFootprintStudSize(footprintWidth, footprintDepth, tileSize)
	local resolvedTileSize = isPositiveNumber(tileSize) and tileSize or GridConfig.TILE_SIZE
	local resolvedFootprintWidth = normalizePositiveInteger(footprintWidth, 1, GridConfig.MAX_FOOTPRINT_TILES)
	local resolvedFootprintDepth = normalizePositiveInteger(footprintDepth, 1, GridConfig.MAX_FOOTPRINT_TILES)
	local widthStuds = math.max(
		resolvedFootprintWidth * resolvedTileSize - GridConfig.FOOTPRINT_MARGIN,
		MIN_FOOTPRINT_STUDS
	)
	local depthStuds = math.max(
		resolvedFootprintDepth * resolvedTileSize - GridConfig.FOOTPRINT_MARGIN,
		MIN_FOOTPRINT_STUDS
	)

	return Vector3.new(widthStuds, 0, depthStuds), widthStuds, depthStuds
end

function GridConfig.GetRecommendedPlacementBoundsSize(footprintWidth, footprintDepth, tileSize)
	local footprintStudSize, widthStuds, depthStuds =
		GridConfig.GetFootprintStudSize(footprintWidth, footprintDepth, tileSize)

	return Vector3.new(
		footprintStudSize.X,
		GridConfig.RECOMMENDED_PLACEMENT_BOUNDS_HEIGHT,
		footprintStudSize.Z
	), widthStuds, depthStuds
end

function GridConfig.GetFurnitureFootprint(furnitureModel)
	local footprintWidth = normalizePositiveInteger(
		getPositiveIntegerAttribute(furnitureModel, "FootprintWidth"),
		1,
		GridConfig.MAX_FOOTPRINT_TILES
	)
	local footprintDepth = normalizePositiveInteger(
		getPositiveIntegerAttribute(furnitureModel, "FootprintDepth"),
		1,
		GridConfig.MAX_FOOTPRINT_TILES
	)

	return footprintWidth, footprintDepth
end

function GridConfig.ValidateRoomGrid(roomModel)
	local warnings = {}

	if not isInstance(roomModel) or not roomModel:IsA("Model") then
		table.insert(warnings, "Room grid validation skipped: roomModel is not a Model.")
		return false, warnings
	end

	local floor = findWalkableFloor(roomModel)

	if not floor then
		table.insert(warnings, "Room grid validation failed: WalkableFloor is missing.")
		return false, warnings
	end

	if GridConfig.UsesTileGrid(roomModel, floor) == false then
		table.insert(warnings, "UsesTileGrid is false; room does not use tile grid.")
		return true, warnings
	end

	if floor:GetAttribute(GridConfig.USES_TILE_GRID_ATTRIBUTE) == nil
		and roomModel:GetAttribute(GridConfig.USES_TILE_GRID_ATTRIBUTE) == nil then

		table.insert(warnings, "UsesTileGrid attribute is missing; defaulting to true.")
	end

	if not getPositiveNumberAttribute(floor, GridConfig.TILE_SIZE_ATTRIBUTE)
		and not getPositiveNumberAttribute(roomModel, GridConfig.TILE_SIZE_ATTRIBUTE) then

		table.insert(warnings, "TileSize attribute is missing or invalid; using default.")
	end

	if not getPositiveIntegerAttribute(floor, GridConfig.GRID_WIDTH_ATTRIBUTE)
		and not getPositiveIntegerAttribute(roomModel, GridConfig.GRID_WIDTH_ATTRIBUTE) then

		table.insert(warnings, "GridWidth attribute is missing or invalid; deriving from floor size.")
	end

	if not getPositiveIntegerAttribute(floor, GridConfig.GRID_DEPTH_ATTRIBUTE)
		and not getPositiveIntegerAttribute(roomModel, GridConfig.GRID_DEPTH_ATTRIBUTE) then

		table.insert(warnings, "GridDepth attribute is missing or invalid; deriving from floor size.")
	end

	local tileSize = GridConfig.GetTileSize(roomModel, floor)
	local gridWidth = GridConfig.GetGridWidth(roomModel, floor)
	local gridDepth = GridConfig.GetGridDepth(roomModel, floor)
	local expectedFloorX = gridWidth * tileSize
	local expectedFloorZ = gridDepth * tileSize
	local tolerance = GridConfig.GRID_VALIDATION_TOLERANCE

	if math.abs(floor.Size.X - expectedFloorX) > tolerance then
		table.insert(warnings, string.format(
			"WalkableFloor Size.X %.2f does not match GridWidth * TileSize %.2f.",
			floor.Size.X,
			expectedFloorX
		))
	end

	if math.abs(floor.Size.Z - expectedFloorZ) > tolerance then
		table.insert(warnings, string.format(
			"WalkableFloor Size.Z %.2f does not match GridDepth * TileSize %.2f.",
			floor.Size.Z,
			expectedFloorZ
		))
	end

	return #warnings == 0, warnings
end

return GridConfig
