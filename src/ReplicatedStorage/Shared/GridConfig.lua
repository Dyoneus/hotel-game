local GridConfig = {}

-- Foundation-only shared grid configuration.
-- Existing movement, hover, and furniture placement scripts still use the old
-- 2-stud grid until later patches explicitly migrate them to this module.
-- Public spaces may opt out by setting UsesTileGrid = false.

GridConfig.TILE_SIZE = 4
GridConfig.DEFAULT_GRID_WIDTH = 5
GridConfig.DEFAULT_GRID_DEPTH = 7
GridConfig.HOVER_TILE_SIZE = 4
GridConfig.FOOTPRINT_MARGIN = 0.4

GridConfig.TILE_SIZE_ATTRIBUTE = "TileSize"
GridConfig.GRID_WIDTH_ATTRIBUTE = "GridWidth"
GridConfig.GRID_DEPTH_ATTRIBUTE = "GridDepth"
GridConfig.USES_TILE_GRID_ATTRIBUTE = "UsesTileGrid"

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
	local resolvedFootprintWidth = isPositiveInteger(footprintWidth) and footprintWidth or 1
	local resolvedFootprintDepth = isPositiveInteger(footprintDepth) and footprintDepth or 1
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

function GridConfig.GetFurnitureFootprint(furnitureModel)
	local footprintWidth = getPositiveIntegerAttribute(furnitureModel, "FootprintWidth") or 1
	local footprintDepth = getPositiveIntegerAttribute(furnitureModel, "FootprintDepth") or 1

	return footprintWidth, footprintDepth
end

return GridConfig
