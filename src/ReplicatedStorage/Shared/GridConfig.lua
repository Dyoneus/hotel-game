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

-- Starter player-room standard:
-- TileSize = 4, GridWidth = 5, GridDepth = 7.
-- That means WalkableFloor.Size.X = 20 and WalkableFloor.Size.Z = 28.
-- Validation is warning-only; room templates must still be adjusted in Studio.

local MIN_FOOTPRINT_STUDS = 0.1

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
