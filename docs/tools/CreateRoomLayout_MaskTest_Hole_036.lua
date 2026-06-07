-- Studio helper: create a dev-only masked room layout test template.
--
-- Run this manually in Roblox Studio Command Bar or from a temporary Script.
-- The helper creates ReplicatedStorage.RoomTemplates.RoomLayout_MaskTest_Hole_036.
--
-- This layout is intentionally not registered in RoomLayoutConfig. It exists
-- only to validate Room/TileMask metadata before gameplay callers use masks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TOOL_PREFIX = "[CreateRoomLayout_MaskTest_Hole_036]"
local REPLACE_EXISTING = true

local LAYOUT_ID = "MaskTest_Hole_036"
local TEMPLATE_NAME = "RoomLayout_MaskTest_Hole_036"
local DISPLAY_NAME = "Mask Test Hole"

local TILE_SIZE = 4
local GRID_WIDTH = 6
local GRID_DEPTH = 6
local HOLE_TILE_X = 3
local HOLE_TILE_Z = 3
local TILE_COUNT = GRID_WIDTH * GRID_DEPTH - 1
local FLOOR_SIZE = Vector3.new(GRID_WIDTH * TILE_SIZE, 0.5, GRID_DEPTH * TILE_SIZE)
local FLOOR_TOP_Y = FLOOR_SIZE.Y / 2
local MARKER_Y = FLOOR_TOP_Y + 2.75
local WALL_HEIGHT = 6.5
local WALL_THICKNESS = 1
local WALL_CENTER_Y = FLOOR_TOP_Y + WALL_HEIGHT / 2
local DOOR_OPENING_WIDTH = TILE_SIZE
local DOOR_TILE_INDEX = 4

local COLORS = {
	Floor = Color3.fromRGB(191, 183, 166),
	GridLine = Color3.fromRGB(157, 146, 126),
	Wall = Color3.fromRGB(218, 208, 188),
	Trim = Color3.fromRGB(104, 75, 49),
	DarkTrim = Color3.fromRGB(69, 50, 36),
	Entrance = Color3.fromRGB(149, 132, 109),
	Hole = Color3.fromRGB(39, 35, 32),
	HoleRim = Color3.fromRGB(92, 70, 50),
}

local function getOrCreateFolder(parent, folderName)
	local folder = parent:FindFirstChild(folderName)

	if folder then
		if not folder:IsA("Folder") then
			error(TOOL_PREFIX .. " " .. folderName .. " exists but is not a Folder.")
		end

		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = parent

	return folder
end

local function configurePart(part, options)
	options = options or {}

	part.Anchored = options.Anchored ~= false
	part.CanCollide = options.CanCollide == true
	part.CanTouch = options.CanTouch == true
	part.CanQuery = options.CanQuery == true
	part.CastShadow = options.CastShadow == true
	part.Transparency = options.Transparency or 0
	part.Color = options.Color or Color3.fromRGB(190, 190, 190)
	part.Material = options.Material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function createPart(parent, name, size, cframe, options)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	configurePart(part, options)
	part.Parent = parent

	return part
end

local function getTileCenterX(tileX)
	return -FLOOR_SIZE.X / 2 + (tileX - 0.5) * TILE_SIZE
end

local function getTileCenterZ(tileZ)
	return -FLOOR_SIZE.Z / 2 + (tileZ - 0.5) * TILE_SIZE
end

local DOOR_CENTER_X = getTileCenterX(DOOR_TILE_INDEX)

local function createRoomFacingCFrame(position)
	return CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
end

local function setGridAttributes(instance)
	instance:SetAttribute("UsesTileGrid", true)
	instance:SetAttribute("UsesTileMask", true)
	instance:SetAttribute("TileSize", TILE_SIZE)
	instance:SetAttribute("GridWidth", GRID_WIDTH)
	instance:SetAttribute("GridDepth", GRID_DEPTH)
end

local function createMarker(parent, name, cframe)
	local marker = createPart(parent, name, Vector3.new(1, 1, 1), cframe, {
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
		Transparency = 1,
	})

	if name == "DoorSpawn" then
		marker:SetAttribute("IsDoorSpawn", true)
	elseif name == "EntryWalkTarget" then
		marker:SetAttribute("IsEntryWalkTarget", true)
	end

	return marker
end

local function createWall(parent, name, size, cframe)
	return createPart(parent, name, size, cframe, {
		CanCollide = true,
		CanTouch = false,
		CanQuery = false,
		Color = COLORS.Wall,
		Material = Enum.Material.SmoothPlastic,
	})
end

local function createVisualPart(parent, name, size, cframe, color, material)
	return createPart(parent, name, size, cframe, {
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

local function buildWalls(roomFolder)
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = roomFolder

	local halfWidth = FLOOR_SIZE.X / 2
	local halfDepth = FLOOR_SIZE.Z / 2
	local frontWallZ = -halfDepth - WALL_THICKNESS / 2
	local doorLeftEdge = DOOR_CENTER_X - DOOR_OPENING_WIDTH / 2
	local doorRightEdge = DOOR_CENTER_X + DOOR_OPENING_WIDTH / 2
	local floorLeftEdge = -halfWidth
	local floorRightEdge = halfWidth
	local leftSegmentWidth = math.max(0, doorLeftEdge - floorLeftEdge)
	local rightSegmentWidth = math.max(0, floorRightEdge - doorRightEdge)

	createWall(
		walls,
		"WallBack",
		Vector3.new(FLOOR_SIZE.X + WALL_THICKNESS * 2, WALL_HEIGHT, WALL_THICKNESS),
		CFrame.new(0, WALL_CENTER_Y, halfDepth + WALL_THICKNESS / 2)
	)

	createWall(
		walls,
		"WallLeft",
		Vector3.new(WALL_THICKNESS, WALL_HEIGHT, FLOOR_SIZE.Z),
		CFrame.new(-halfWidth - WALL_THICKNESS / 2, WALL_CENTER_Y, 0)
	)

	createWall(
		walls,
		"WallRight",
		Vector3.new(WALL_THICKNESS, WALL_HEIGHT, FLOOR_SIZE.Z),
		CFrame.new(halfWidth + WALL_THICKNESS / 2, WALL_CENTER_Y, 0)
	)

	if leftSegmentWidth > 0 then
		createWall(
			walls,
			"WallFrontLeft",
			Vector3.new(leftSegmentWidth, WALL_HEIGHT, WALL_THICKNESS),
			CFrame.new(floorLeftEdge + leftSegmentWidth / 2, WALL_CENTER_Y, frontWallZ)
		)
	end

	if rightSegmentWidth > 0 then
		createWall(
			walls,
			"WallFrontRight",
			Vector3.new(rightSegmentWidth, WALL_HEIGHT, WALL_THICKNESS),
			CFrame.new(doorRightEdge + rightSegmentWidth / 2, WALL_CENTER_Y, frontWallZ)
		)
	end

	createVisualPart(
		walls,
		"DoorOpeningTrimTop",
		Vector3.new(DOOR_OPENING_WIDTH + 0.5, 0.35, 0.7),
		CFrame.new(DOOR_CENTER_X, FLOOR_TOP_Y + WALL_HEIGHT - 0.6, frontWallZ),
		COLORS.Trim,
		Enum.Material.Wood
	)

	createVisualPart(
		walls,
		"DoorOpeningTrimLeft",
		Vector3.new(0.35, WALL_HEIGHT - 0.7, 0.55),
		CFrame.new(doorLeftEdge - 0.18, FLOOR_TOP_Y + (WALL_HEIGHT - 0.7) / 2, frontWallZ),
		COLORS.Trim,
		Enum.Material.Wood
	)

	createVisualPart(
		walls,
		"DoorOpeningTrimRight",
		Vector3.new(0.35, WALL_HEIGHT - 0.7, 0.55),
		CFrame.new(doorRightEdge + 0.18, FLOOR_TOP_Y + (WALL_HEIGHT - 0.7) / 2, frontWallZ),
		COLORS.Trim,
		Enum.Material.Wood
	)
end

local function buildDecorativeFloor(roomFolder)
	local decorativeFloor = Instance.new("Folder")
	decorativeFloor.Name = "DecorativeFloor"
	decorativeFloor.Parent = roomFolder

	createVisualPart(
		decorativeFloor,
		"EntranceMat",
		Vector3.new(DOOR_OPENING_WIDTH, 0.06, TILE_SIZE * 1.5),
		CFrame.new(DOOR_CENTER_X, FLOOR_TOP_Y + 0.04, -FLOOR_SIZE.Z / 2 + TILE_SIZE * 0.75),
		COLORS.Entrance,
		Enum.Material.Fabric
	)

	for xIndex = 1, GRID_WIDTH - 1 do
		local x = -FLOOR_SIZE.X / 2 + xIndex * TILE_SIZE

		createVisualPart(
			decorativeFloor,
			"GridLineX_" .. tostring(xIndex),
			Vector3.new(0.05, 0.03, FLOOR_SIZE.Z),
			CFrame.new(x, FLOOR_TOP_Y + 0.025, 0),
			COLORS.GridLine
		)
	end

	for zIndex = 1, GRID_DEPTH - 1 do
		local z = -FLOOR_SIZE.Z / 2 + zIndex * TILE_SIZE

		createVisualPart(
			decorativeFloor,
			"GridLineZ_" .. tostring(zIndex),
			Vector3.new(FLOOR_SIZE.X, 0.03, 0.05),
			CFrame.new(0, FLOOR_TOP_Y + 0.026, z),
			COLORS.GridLine
		)
	end
end

local function buildDecor(roomFolder)
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = roomFolder

	local halfWidth = FLOOR_SIZE.X / 2
	local halfDepth = FLOOR_SIZE.Z / 2
	local holeX = getTileCenterX(HOLE_TILE_X)
	local holeZ = getTileCenterZ(HOLE_TILE_Z)

	createVisualPart(
		decor,
		"HoleVisual",
		Vector3.new(TILE_SIZE - 0.35, 0.08, TILE_SIZE - 0.35),
		CFrame.new(holeX, FLOOR_TOP_Y + 0.035, holeZ),
		COLORS.Hole,
		Enum.Material.Slate
	)

	createVisualPart(
		decor,
		"HoleRimFront",
		Vector3.new(TILE_SIZE, 0.08, 0.16),
		CFrame.new(holeX, FLOOR_TOP_Y + 0.08, holeZ - TILE_SIZE / 2 + 0.08),
		COLORS.HoleRim,
		Enum.Material.Wood
	)

	createVisualPart(
		decor,
		"HoleRimBack",
		Vector3.new(TILE_SIZE, 0.08, 0.16),
		CFrame.new(holeX, FLOOR_TOP_Y + 0.08, holeZ + TILE_SIZE / 2 - 0.08),
		COLORS.HoleRim,
		Enum.Material.Wood
	)

	createVisualPart(
		decor,
		"HoleRimLeft",
		Vector3.new(0.16, 0.08, TILE_SIZE),
		CFrame.new(holeX - TILE_SIZE / 2 + 0.08, FLOOR_TOP_Y + 0.081, holeZ),
		COLORS.HoleRim,
		Enum.Material.Wood
	)

	createVisualPart(
		decor,
		"HoleRimRight",
		Vector3.new(0.16, 0.08, TILE_SIZE),
		CFrame.new(holeX + TILE_SIZE / 2 - 0.08, FLOOR_TOP_Y + 0.081, holeZ),
		COLORS.HoleRim,
		Enum.Material.Wood
	)

	createVisualPart(
		decor,
		"BackWallBaseboard",
		Vector3.new(FLOOR_SIZE.X, 0.35, 0.35),
		CFrame.new(0, FLOOR_TOP_Y + 0.3, halfDepth + 0.08),
		COLORS.DarkTrim,
		Enum.Material.Wood
	)

	createVisualPart(
		decor,
		"LeftWallBaseboard",
		Vector3.new(0.35, 0.35, FLOOR_SIZE.Z),
		CFrame.new(-halfWidth - 0.08, FLOOR_TOP_Y + 0.3, 0),
		COLORS.DarkTrim,
		Enum.Material.Wood
	)

	createVisualPart(
		decor,
		"RightWallBaseboard",
		Vector3.new(0.35, 0.35, FLOOR_SIZE.Z),
		CFrame.new(halfWidth + 0.08, FLOOR_TOP_Y + 0.3, 0),
		COLORS.DarkTrim,
		Enum.Material.Wood
	)
end

local function buildTileMask(roomFolder)
	local tileMaskFolder = Instance.new("Folder")
	tileMaskFolder.Name = "TileMask"
	tileMaskFolder.Parent = roomFolder

	local markerCount = 0

	for tileZ = 1, GRID_DEPTH do
		for tileX = 1, GRID_WIDTH do
			if tileX ~= HOLE_TILE_X or tileZ ~= HOLE_TILE_Z then
				local marker = createPart(
					tileMaskFolder,
					string.format("Tile_%d_%d", tileX, tileZ),
					Vector3.new(TILE_SIZE, 0.1, TILE_SIZE),
					CFrame.new(getTileCenterX(tileX), FLOOR_TOP_Y + 0.05, getTileCenterZ(tileZ)),
					{
						Anchored = true,
						CanCollide = false,
						CanTouch = false,
						CanQuery = true,
						CastShadow = false,
						Transparency = 1,
					}
				)

				marker:SetAttribute("IsWalkableTile", true)
				marker:SetAttribute("TileX", tileX)
				marker:SetAttribute("TileZ", tileZ)
				markerCount += 1
			end
		end
	end

	return tileMaskFolder, markerCount
end

local function buildTemplate(templateFolder)
	local existingTemplate = templateFolder:FindFirstChild(TEMPLATE_NAME)

	if existingTemplate then
		if not REPLACE_EXISTING then
			error(TOOL_PREFIX .. " Template already exists and REPLACE_EXISTING is false: " .. TEMPLATE_NAME)
		end

		existingTemplate:Destroy()
	end

	local template = Instance.new("Model")
	template.Name = TEMPLATE_NAME
	template:SetAttribute("LayoutId", LAYOUT_ID)
	template:SetAttribute("TemplateName", TEMPLATE_NAME)
	template:SetAttribute("DisplayName", DISPLAY_NAME)
	template:SetAttribute("TileCount", TILE_COUNT)
	setGridAttributes(template)

	local roomAnchor = createMarker(template, "RoomAnchor", CFrame.new(0, 0, 0))
	local doorSpawnPosition = Vector3.new(DOOR_CENTER_X, MARKER_Y, getTileCenterZ(1))
	local entryWalkTargetPosition = Vector3.new(DOOR_CENTER_X, MARKER_Y, getTileCenterZ(2))
	local doorSpawn = createMarker(template, "DoorSpawn", createRoomFacingCFrame(doorSpawnPosition))
	local entryWalkTarget = createMarker(template, "EntryWalkTarget", createRoomFacingCFrame(entryWalkTargetPosition))
	template.PrimaryPart = roomAnchor

	local roomFolder = Instance.new("Folder")
	roomFolder.Name = "Room"
	roomFolder.Parent = template

	local walkableFloor = createPart(roomFolder, "WalkableFloor", FLOOR_SIZE, CFrame.new(0, 0, 0), {
		CanCollide = true,
		CanTouch = false,
		CanQuery = true,
		Color = COLORS.Floor,
		Material = Enum.Material.SmoothPlastic,
	})
	setGridAttributes(walkableFloor)

	local roomExitZone = createPart(
		roomFolder,
		"RoomExitZone",
		Vector3.new(DOOR_OPENING_WIDTH, 6, TILE_SIZE),
		CFrame.new(DOOR_CENTER_X, FLOOR_TOP_Y + 3, -FLOOR_SIZE.Z / 2 - TILE_SIZE / 2),
		{
			CanCollide = false,
			CanTouch = false,
			CanQuery = true,
			CastShadow = false,
			Transparency = 1,
		}
	)
	roomExitZone:SetAttribute("IsRoomExit", true)

	buildWalls(roomFolder)
	buildDecorativeFloor(roomFolder)
	buildDecor(roomFolder)
	local tileMaskFolder, markerCount = buildTileMask(roomFolder)

	local furnitureFolder = Instance.new("Folder")
	furnitureFolder.Name = "Furniture"
	furnitureFolder.Parent = template

	template.Parent = templateFolder

	return template, roomAnchor, doorSpawn, entryWalkTarget, walkableFloor, tileMaskFolder, markerCount
end

local roomTemplates = getOrCreateFolder(ReplicatedStorage, "RoomTemplates")
local template, roomAnchor, doorSpawn, entryWalkTarget, walkableFloor, tileMaskFolder, markerCount =
	buildTemplate(roomTemplates)

print(TOOL_PREFIX .. " Created " .. template:GetFullName())
print(string.format("%s LayoutId=%s", TOOL_PREFIX, LAYOUT_ID))
print(string.format("%s TileCount=%d", TOOL_PREFIX, TILE_COUNT))
print(string.format("%s GridWidth/GridDepth=%d/%d", TOOL_PREFIX, GRID_WIDTH, GRID_DEPTH))
print(string.format("%s TileSize=%d", TOOL_PREFIX, TILE_SIZE))
print(string.format(
	"%s WalkableFloor size=(%.1f, %.1f, %.1f)",
	TOOL_PREFIX,
	walkableFloor.Size.X,
	walkableFloor.Size.Y,
	walkableFloor.Size.Z
))
print(string.format("%s UsesTileMask=true TileMask=%s", TOOL_PREFIX, tileMaskFolder:GetFullName()))
print(string.format("%s Mask markers=%d expected=%d", TOOL_PREFIX, markerCount, TILE_COUNT))
print(string.format("%s HoleTile=(%d, %d)", TOOL_PREFIX, HOLE_TILE_X, HOLE_TILE_Z))
print(string.format("%s DoorTileIndex=%d", TOOL_PREFIX, DOOR_TILE_INDEX))
print(string.format("%s DoorCenterX=%.2f", TOOL_PREFIX, DOOR_CENTER_X))
print(string.format("%s DoorSpawn position=%s", TOOL_PREFIX, tostring(doorSpawn.Position)))
print(string.format("%s EntryWalkTarget position=%s", TOOL_PREFIX, tostring(entryWalkTarget.Position)))
print(string.format("%s Cave width = %.0f tile (%.1f studs).", TOOL_PREFIX, DOOR_OPENING_WIDTH / TILE_SIZE, DOOR_OPENING_WIDTH))
print(TOOL_PREFIX .. " DoorSpawn is on TileX=" .. tostring(DOOR_TILE_INDEX) .. " TileZ=1, which is walkable.")
print(TOOL_PREFIX .. " EntryWalkTarget is on TileX=" .. tostring(DOOR_TILE_INDEX) .. " TileZ=2, which is walkable.")
print(TOOL_PREFIX .. " This dev template is not registered in RoomLayoutConfig and should not appear in Room Planner.")
print(TOOL_PREFIX .. " Next: run docs/tools/ValidateRoomLayoutTemplates.lua.")
