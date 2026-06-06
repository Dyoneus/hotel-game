-- Studio helper: create the first real owned-room layout template.
--
-- Run this manually in Roblox Studio Command Bar or from a temporary Script.
-- The helper creates ReplicatedStorage.RoomTemplates.RoomLayout_Free_036_A.
--
-- This first layout is intentionally simple: a 6x6 free starter room with
-- 36 walkable tiles. Later layout generators can add non-rectangular shapes,
-- multi-level structures, holes, stairs, and VIP-only special areas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TOOL_PREFIX = "[CreateRoomLayout_Free_036_A]"
local REPLACE_EXISTING = true

local LAYOUT_ID = "Free_036_A"
local TEMPLATE_NAME = "RoomLayout_Free_036_A"
local DISPLAY_NAME = "Starter Studio"
local ACCESS_TIER = "Free"
local REQUIRES_VIP = false

local TILE_SIZE = 4
local GRID_WIDTH = 6
local GRID_DEPTH = 6
local TILE_COUNT = GRID_WIDTH * GRID_DEPTH
local FLOOR_SIZE = Vector3.new(GRID_WIDTH * TILE_SIZE, 0.5, GRID_DEPTH * TILE_SIZE)
local FLOOR_TOP_Y = FLOOR_SIZE.Y / 2
local MARKER_Y = FLOOR_TOP_Y + 2.75
local WALL_HEIGHT = 6.5
local WALL_THICKNESS = 1
local WALL_CENTER_Y = FLOOR_TOP_Y + WALL_HEIGHT / 2
local DOOR_OPENING_WIDTH = TILE_SIZE
local DOORWAY_COLLISION_CLEARANCE = TILE_SIZE / 2

local COLORS = {
	Floor = Color3.fromRGB(194, 184, 162),
	FloorTileA = Color3.fromRGB(204, 194, 174),
	FloorTileB = Color3.fromRGB(184, 174, 154),
	Wall = Color3.fromRGB(222, 211, 188),
	WallPanel = Color3.fromRGB(198, 181, 148),
	Trim = Color3.fromRGB(117, 82, 52),
	DarkTrim = Color3.fromRGB(74, 52, 36),
	Entrance = Color3.fromRGB(150, 134, 112),
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

local function createRoomFacingCFrame(position)
	return CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
end

local function setGridAttributes(instance)
	instance:SetAttribute("UsesTileGrid", true)
	instance:SetAttribute("TileSize", TILE_SIZE)
	instance:SetAttribute("GridWidth", GRID_WIDTH)
	instance:SetAttribute("GridDepth", GRID_DEPTH)
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

local function createInvisibleCollider(parent, name, size, cframe)
	return createPart(parent, name, size, cframe, {
		CanCollide = true,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
		Transparency = 1,
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
	local frontVisualSegmentWidth = (FLOOR_SIZE.X - DOOR_OPENING_WIDTH) / 2
	local frontCollisionSegmentWidth = math.max(0, frontVisualSegmentWidth - DOORWAY_COLLISION_CLEARANCE)
	local frontWallZ = -halfDepth - WALL_THICKNESS / 2

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

	createVisualPart(
		walls,
		"WallFrontLeft",
		Vector3.new(frontVisualSegmentWidth, WALL_HEIGHT, WALL_THICKNESS),
		CFrame.new(-(DOOR_OPENING_WIDTH / 2 + frontVisualSegmentWidth / 2), WALL_CENTER_Y, frontWallZ),
		COLORS.Wall,
		Enum.Material.SmoothPlastic
	)

	createVisualPart(
		walls,
		"WallFrontRight",
		Vector3.new(frontVisualSegmentWidth, WALL_HEIGHT, WALL_THICKNESS),
		CFrame.new(DOOR_OPENING_WIDTH / 2 + frontVisualSegmentWidth / 2, WALL_CENTER_Y, frontWallZ),
		COLORS.Wall,
		Enum.Material.SmoothPlastic
	)

	if frontCollisionSegmentWidth > 0 then
		local frontCollisionCenterX = DOOR_OPENING_WIDTH / 2 + DOORWAY_COLLISION_CLEARANCE + frontCollisionSegmentWidth / 2

		createInvisibleCollider(
			walls,
			"WallFrontLeftCollision",
			Vector3.new(frontCollisionSegmentWidth, WALL_HEIGHT, WALL_THICKNESS),
			CFrame.new(-frontCollisionCenterX, WALL_CENTER_Y, frontWallZ)
		)

		createInvisibleCollider(
			walls,
			"WallFrontRightCollision",
			Vector3.new(frontCollisionSegmentWidth, WALL_HEIGHT, WALL_THICKNESS),
			CFrame.new(frontCollisionCenterX, WALL_CENTER_Y, frontWallZ)
		)
	end

	createVisualPart(
		walls,
		"DoorOpeningTrimTop",
		Vector3.new(DOOR_OPENING_WIDTH + 0.5, 0.35, 0.7),
		CFrame.new(0, FLOOR_TOP_Y + WALL_HEIGHT - 0.6, frontWallZ),
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
		CFrame.new(0, FLOOR_TOP_Y + 0.04, -FLOOR_SIZE.Z / 2 + TILE_SIZE * 0.75),
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
			COLORS.FloorTileB
		)
	end

	for zIndex = 1, GRID_DEPTH - 1 do
		local z = -FLOOR_SIZE.Z / 2 + zIndex * TILE_SIZE

		createVisualPart(
			decorativeFloor,
			"GridLineZ_" .. tostring(zIndex),
			Vector3.new(FLOOR_SIZE.X, 0.03, 0.05),
			CFrame.new(0, FLOOR_TOP_Y + 0.026, z),
			COLORS.FloorTileB
		)
	end
end

local function buildDecor(roomFolder)
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = roomFolder

	local halfWidth = FLOOR_SIZE.X / 2
	local halfDepth = FLOOR_SIZE.Z / 2

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
	template:SetAttribute("AccessTier", ACCESS_TIER)
	template:SetAttribute("RequiresVip", REQUIRES_VIP)
	setGridAttributes(template)

	local roomAnchor = createMarker(template, "RoomAnchor", CFrame.new(0, 0, 0))
	local doorSpawnPosition = Vector3.new(0, MARKER_Y, -FLOOR_SIZE.Z / 2 - 2)
	local entryWalkTargetPosition = Vector3.new(0, MARKER_Y, -FLOOR_SIZE.Z / 2 + TILE_SIZE / 2)
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
		CFrame.new(0, FLOOR_TOP_Y + 3, -FLOOR_SIZE.Z / 2 - TILE_SIZE / 2),
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

	local furnitureFolder = Instance.new("Folder")
	furnitureFolder.Name = "Furniture"
	furnitureFolder.Parent = template

	template.Parent = templateFolder

	return template, roomAnchor, doorSpawn, entryWalkTarget
end

local roomTemplates = getOrCreateFolder(ReplicatedStorage, "RoomTemplates")
local template, roomAnchor, doorSpawn, entryWalkTarget = buildTemplate(roomTemplates)

print(TOOL_PREFIX .. " Created " .. template:GetFullName())
print(string.format(
	"%s LayoutId=%s TileCount=%d Grid=%dx%d TileSize=%d FloorSize=(%.1f, %.1f, %.1f)",
	TOOL_PREFIX,
	LAYOUT_ID,
	TILE_COUNT,
	GRID_WIDTH,
	GRID_DEPTH,
	TILE_SIZE,
	FLOOR_SIZE.X,
	FLOOR_SIZE.Y,
	FLOOR_SIZE.Z
))
print(TOOL_PREFIX .. " RoomAnchor position: " .. tostring(roomAnchor.Position))
print(TOOL_PREFIX .. " DoorSpawn position: " .. tostring(doorSpawn.Position))
print(TOOL_PREFIX .. " EntryWalkTarget position: " .. tostring(entryWalkTarget.Position))
print(string.format("%s Cave width = %.0f tile (%.1f studs).", TOOL_PREFIX, DOOR_OPENING_WIDTH / TILE_SIZE, DOOR_OPENING_WIDTH))
print(string.format("%s EntryWalkTarget remains first interior tile: z=%.1f.", TOOL_PREFIX, entryWalkTarget.Position.Z))
print(TOOL_PREFIX .. " Doorway trim is non-colliding; entrance-edge visuals do not block the character.")
print(TOOL_PREFIX .. " Entrance lane kept clear from DoorSpawn to EntryWalkTarget.")
print(TOOL_PREFIX .. " Next: run docs/tools/ValidateRoomLayoutTemplates.lua, then create and join Starter Studio from Room Planner.")
