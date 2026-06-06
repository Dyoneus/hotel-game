-- Studio helper: create the VIP Marble Hall owned-room layout template.
--
-- Run this manually in Roblox Studio Command Bar or from a temporary Script.
-- The helper creates ReplicatedStorage.RoomTemplates.RoomLayout_VIP_304_A.
--
-- VIP Marble Hall is a simple rectangular 19x16 VIP room with 304 walkable
-- tiles. It keeps the current movement system safe with one flat WalkableFloor.
-- Premium stair, riser, balcony, and platform details are visual-only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TOOL_PREFIX = "[CreateRoomLayout_VIP_304_A]"
local REPLACE_EXISTING = true

local LAYOUT_ID = "VIP_304_A"
local TEMPLATE_NAME = "RoomLayout_VIP_304_A"
local DISPLAY_NAME = "VIP Marble Hall"
local ACCESS_TIER = "VIP"
local REQUIRES_VIP = true

local TILE_SIZE = 4
local GRID_WIDTH = 19
local GRID_DEPTH = 16
local TILE_COUNT = GRID_WIDTH * GRID_DEPTH
local FLOOR_SIZE = Vector3.new(GRID_WIDTH * TILE_SIZE, 0.5, GRID_DEPTH * TILE_SIZE)
local FLOOR_TOP_Y = FLOOR_SIZE.Y / 2
local MARKER_Y = FLOOR_TOP_Y + 2.75
local WALL_HEIGHT = 8
local WALL_THICKNESS = 1
local WALL_CENTER_Y = FLOOR_TOP_Y + WALL_HEIGHT / 2
local DOOR_OPENING_WIDTH = TILE_SIZE
local DOORWAY_COLLISION_CLEARANCE = TILE_SIZE / 2
local DOOR_TILE_INDEX = 10

local function getTileCenterX(tileIndex)
	return -FLOOR_SIZE.X / 2 + (tileIndex - 0.5) * TILE_SIZE
end

local DOOR_CENTER_X = getTileCenterX(DOOR_TILE_INDEX)

local COLORS = {
	Floor = Color3.fromRGB(226, 222, 213),
	FloorVein = Color3.fromRGB(184, 176, 164),
	FloorAccent = Color3.fromRGB(241, 236, 224),
	Wall = Color3.fromRGB(235, 228, 216),
	WallPanel = Color3.fromRGB(210, 198, 180),
	GoldTrim = Color3.fromRGB(207, 160, 62),
	DarkTrim = Color3.fromRGB(84, 61, 34),
	Entrance = Color3.fromRGB(88, 75, 62),
	EntranceEdge = Color3.fromRGB(205, 166, 76),
	Platform = Color3.fromRGB(218, 211, 199),
	PlatformEdge = Color3.fromRGB(174, 130, 52),
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
		Material = Enum.Material.Marble,
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
	local leftEdgeX = -halfWidth
	local rightEdgeX = halfWidth
	local doorLeftX = DOOR_CENTER_X - DOOR_OPENING_WIDTH / 2
	local doorRightX = DOOR_CENTER_X + DOOR_OPENING_WIDTH / 2
	local frontLeftVisualSegmentWidth = math.max(0, doorLeftX - leftEdgeX)
	local frontRightVisualSegmentWidth = math.max(0, rightEdgeX - doorRightX)
	local frontLeftCollisionSegmentWidth = math.max(0, doorLeftX - DOORWAY_COLLISION_CLEARANCE - leftEdgeX)
	local frontRightCollisionSegmentWidth = math.max(0, rightEdgeX - doorRightX - DOORWAY_COLLISION_CLEARANCE)
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
		Vector3.new(frontLeftVisualSegmentWidth, WALL_HEIGHT, WALL_THICKNESS),
		CFrame.new(leftEdgeX + frontLeftVisualSegmentWidth / 2, WALL_CENTER_Y, frontWallZ),
		COLORS.Wall,
		Enum.Material.Marble
	)

	createVisualPart(
		walls,
		"WallFrontRight",
		Vector3.new(frontRightVisualSegmentWidth, WALL_HEIGHT, WALL_THICKNESS),
		CFrame.new(doorRightX + frontRightVisualSegmentWidth / 2, WALL_CENTER_Y, frontWallZ),
		COLORS.Wall,
		Enum.Material.Marble
	)

	if frontLeftCollisionSegmentWidth > 0 then
		createInvisibleCollider(
			walls,
			"WallFrontLeftCollision",
			Vector3.new(frontLeftCollisionSegmentWidth, WALL_HEIGHT, WALL_THICKNESS),
			CFrame.new(leftEdgeX + frontLeftCollisionSegmentWidth / 2, WALL_CENTER_Y, frontWallZ)
		)
	end

	if frontRightCollisionSegmentWidth > 0 then
		createInvisibleCollider(
			walls,
			"WallFrontRightCollision",
			Vector3.new(frontRightCollisionSegmentWidth, WALL_HEIGHT, WALL_THICKNESS),
			CFrame.new(rightEdgeX - frontRightCollisionSegmentWidth / 2, WALL_CENTER_Y, frontWallZ)
		)
	end

	local doorTrimWidth = 0.3

	createVisualPart(
		walls,
		"DoorOpeningTrimTop",
		Vector3.new(DOOR_OPENING_WIDTH + doorTrimWidth * 2, 0.35, 0.7),
		CFrame.new(DOOR_CENTER_X, FLOOR_TOP_Y + WALL_HEIGHT - 0.65, frontWallZ),
		COLORS.GoldTrim,
		Enum.Material.Metal
	)

	createVisualPart(
		walls,
		"DoorOpeningTrimLeft",
		Vector3.new(doorTrimWidth, WALL_HEIGHT - 1, 0.55),
		CFrame.new(doorLeftX - doorTrimWidth / 2, FLOOR_TOP_Y + (WALL_HEIGHT - 1) / 2, frontWallZ),
		COLORS.GoldTrim,
		Enum.Material.Metal
	)

	createVisualPart(
		walls,
		"DoorOpeningTrimRight",
		Vector3.new(doorTrimWidth, WALL_HEIGHT - 1, 0.55),
		CFrame.new(doorRightX + doorTrimWidth / 2, FLOOR_TOP_Y + (WALL_HEIGHT - 1) / 2, frontWallZ),
		COLORS.GoldTrim,
		Enum.Material.Metal
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

	createVisualPart(
		decorativeFloor,
		"EntranceMatGoldEdge",
		Vector3.new(DOOR_OPENING_WIDTH, 0.04, 0.14),
		CFrame.new(DOOR_CENTER_X, FLOOR_TOP_Y + 0.075, -FLOOR_SIZE.Z / 2 + TILE_SIZE * 1.5),
		COLORS.EntranceEdge,
		Enum.Material.Metal
	)

	createVisualPart(
		decorativeFloor,
		"CentralMarbleInlay",
		Vector3.new(TILE_SIZE * 7, 0.035, TILE_SIZE * 8),
		CFrame.new(0, FLOOR_TOP_Y + 0.035, TILE_SIZE * 1.75),
		COLORS.FloorAccent,
		Enum.Material.Marble
	)

	createVisualPart(
		decorativeFloor,
		"CentralInlayGoldFront",
		Vector3.new(TILE_SIZE * 7 + 0.3, 0.04, 0.14),
		CFrame.new(0, FLOOR_TOP_Y + 0.06, -TILE_SIZE * 2.25),
		COLORS.GoldTrim,
		Enum.Material.Metal
	)

	createVisualPart(
		decorativeFloor,
		"CentralInlayGoldBack",
		Vector3.new(TILE_SIZE * 7 + 0.3, 0.04, 0.14),
		CFrame.new(0, FLOOR_TOP_Y + 0.06, TILE_SIZE * 5.75),
		COLORS.GoldTrim,
		Enum.Material.Metal
	)

	createVisualPart(
		decorativeFloor,
		"LeftMarbleVein",
		Vector3.new(0.08, 0.035, FLOOR_SIZE.Z - TILE_SIZE * 3),
		CFrame.new(-TILE_SIZE * 3.75, FLOOR_TOP_Y + 0.04, TILE_SIZE * 0.5),
		COLORS.FloorVein,
		Enum.Material.Marble
	)

	createVisualPart(
		decorativeFloor,
		"RightMarbleVein",
		Vector3.new(0.08, 0.035, FLOOR_SIZE.Z - TILE_SIZE * 3),
		CFrame.new(TILE_SIZE * 3.75, FLOOR_TOP_Y + 0.04, TILE_SIZE * 0.5),
		COLORS.FloorVein,
		Enum.Material.Marble
	)
end

local function buildDecor(roomFolder)
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = roomFolder

	local halfWidth = FLOOR_SIZE.X / 2
	local halfDepth = FLOOR_SIZE.Z / 2
	local leftEdgeX = -halfWidth
	local rightEdgeX = halfWidth
	local doorLeftX = DOOR_CENTER_X - DOOR_OPENING_WIDTH / 2
	local doorRightX = DOOR_CENTER_X + DOOR_OPENING_WIDTH / 2
	local frontLeftSegmentWidth = math.max(0, doorLeftX - leftEdgeX)
	local frontRightSegmentWidth = math.max(0, rightEdgeX - doorRightX)
	local frontLeftSegmentCenterX = leftEdgeX + frontLeftSegmentWidth / 2
	local frontRightSegmentCenterX = doorRightX + frontRightSegmentWidth / 2
	local frontZ = -halfDepth - 0.08
	local baseboardY = FLOOR_TOP_Y + 0.3
	local railY = FLOOR_TOP_Y + WALL_HEIGHT * 0.56
	local panelY = FLOOR_TOP_Y + WALL_HEIGHT * 0.43

	createVisualPart(
		decor,
		"BackWallBaseboard",
		Vector3.new(FLOOR_SIZE.X, 0.35, 0.35),
		CFrame.new(0, baseboardY, halfDepth + 0.08),
		COLORS.DarkTrim,
		Enum.Material.Wood
	)

	createVisualPart(
		decor,
		"LeftWallBaseboard",
		Vector3.new(0.35, 0.35, FLOOR_SIZE.Z),
		CFrame.new(-halfWidth - 0.08, baseboardY, 0),
		COLORS.DarkTrim,
		Enum.Material.Wood
	)

	createVisualPart(
		decor,
		"RightWallBaseboard",
		Vector3.new(0.35, 0.35, FLOOR_SIZE.Z),
		CFrame.new(halfWidth + 0.08, baseboardY, 0),
		COLORS.DarkTrim,
		Enum.Material.Wood
	)

	createVisualPart(
		decor,
		"FrontWallBaseboardLeft",
		Vector3.new(frontLeftSegmentWidth, 0.35, 0.3),
		CFrame.new(frontLeftSegmentCenterX, baseboardY, frontZ),
		COLORS.DarkTrim,
		Enum.Material.Wood
	)

	createVisualPart(
		decor,
		"FrontWallBaseboardRight",
		Vector3.new(frontRightSegmentWidth, 0.35, 0.3),
		CFrame.new(frontRightSegmentCenterX, baseboardY, frontZ),
		COLORS.DarkTrim,
		Enum.Material.Wood
	)

	createVisualPart(
		decor,
		"BackWallGoldChairRail",
		Vector3.new(FLOOR_SIZE.X - 2, 0.18, 0.2),
		CFrame.new(0, railY, halfDepth + 0.06),
		COLORS.GoldTrim,
		Enum.Material.Metal
	)

	createVisualPart(
		decor,
		"LeftWallGoldChairRail",
		Vector3.new(0.2, 0.18, FLOOR_SIZE.Z - 2),
		CFrame.new(-halfWidth - 0.06, railY, 0),
		COLORS.GoldTrim,
		Enum.Material.Metal
	)

	createVisualPart(
		decor,
		"RightWallGoldChairRail",
		Vector3.new(0.2, 0.18, FLOOR_SIZE.Z - 2),
		CFrame.new(halfWidth + 0.06, railY, 0),
		COLORS.GoldTrim,
		Enum.Material.Metal
	)

	createVisualPart(
		decor,
		"FrontWallGoldChairRailLeft",
		Vector3.new(frontLeftSegmentWidth, 0.18, 0.2),
		CFrame.new(frontLeftSegmentCenterX, railY, frontZ),
		COLORS.GoldTrim,
		Enum.Material.Metal
	)

	createVisualPart(
		decor,
		"FrontWallGoldChairRailRight",
		Vector3.new(frontRightSegmentWidth, 0.18, 0.2),
		CFrame.new(frontRightSegmentCenterX, railY, frontZ),
		COLORS.GoldTrim,
		Enum.Material.Metal
	)

	for panelIndex = 1, 5 do
		local panelX = (panelIndex - 3) * TILE_SIZE * 2.5

		createVisualPart(
			decor,
			"BackWallPanel_" .. tostring(panelIndex),
			Vector3.new(TILE_SIZE * 1.7, 2.4, 0.12),
			CFrame.new(panelX, panelY, halfDepth + 0.04),
			COLORS.WallPanel,
			Enum.Material.Marble
		)
	end

	createVisualPart(
		decor,
		"VisualVIPPlatformLeft",
		Vector3.new(TILE_SIZE * 3, 0.12, TILE_SIZE * 5),
		CFrame.new(-halfWidth + TILE_SIZE * 1.5, FLOOR_TOP_Y + 0.08, halfDepth - TILE_SIZE * 2.5),
		COLORS.Platform,
		Enum.Material.Marble
	)

	createVisualPart(
		decor,
		"VisualVIPPlatformRight",
		Vector3.new(TILE_SIZE * 3, 0.12, TILE_SIZE * 5),
		CFrame.new(halfWidth - TILE_SIZE * 1.5, FLOOR_TOP_Y + 0.08, halfDepth - TILE_SIZE * 2.5),
		COLORS.Platform,
		Enum.Material.Marble
	)

	createVisualPart(
		decor,
		"VisualPlatformGoldRailLeft",
		Vector3.new(0.18, 0.4, TILE_SIZE * 5),
		CFrame.new(-halfWidth + TILE_SIZE * 3, FLOOR_TOP_Y + 0.34, halfDepth - TILE_SIZE * 2.5),
		COLORS.PlatformEdge,
		Enum.Material.Metal
	)

	createVisualPart(
		decor,
		"VisualPlatformGoldRailRight",
		Vector3.new(0.18, 0.4, TILE_SIZE * 5),
		CFrame.new(halfWidth - TILE_SIZE * 3, FLOOR_TOP_Y + 0.34, halfDepth - TILE_SIZE * 2.5),
		COLORS.PlatformEdge,
		Enum.Material.Metal
	)

	for stepIndex = 1, 5 do
		createVisualPart(
			decor,
			"VisualLeftStairRiser_" .. tostring(stepIndex),
			Vector3.new(TILE_SIZE * 2, 0.08, 0.3),
			CFrame.new(
				-halfWidth + TILE_SIZE * 2.1,
				FLOOR_TOP_Y + 0.06 + stepIndex * 0.035,
				halfDepth - TILE_SIZE * 5.1 + stepIndex * 0.38
			),
			COLORS.GoldTrim,
			Enum.Material.Metal
		)

		createVisualPart(
			decor,
			"VisualRightStairRiser_" .. tostring(stepIndex),
			Vector3.new(TILE_SIZE * 2, 0.08, 0.3),
			CFrame.new(
				halfWidth - TILE_SIZE * 2.1,
				FLOOR_TOP_Y + 0.06 + stepIndex * 0.035,
				halfDepth - TILE_SIZE * 5.1 + stepIndex * 0.38
			),
			COLORS.GoldTrim,
			Enum.Material.Metal
		)
	end
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
	template:SetAttribute("HasStairs", true)
	template:SetAttribute("HasLevels", false)
	template:SetAttribute("HasHiddenArea", false)
	setGridAttributes(template)

	local roomAnchor = createMarker(template, "RoomAnchor", CFrame.new(0, 0, 0))
	local doorSpawnPosition = Vector3.new(DOOR_CENTER_X, MARKER_Y, -FLOOR_SIZE.Z / 2 - 2)
	local entryWalkTargetPosition = Vector3.new(DOOR_CENTER_X, MARKER_Y, -FLOOR_SIZE.Z / 2 + TILE_SIZE / 2)
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
		Material = Enum.Material.Marble,
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

	local furnitureFolder = Instance.new("Folder")
	furnitureFolder.Name = "Furniture"
	furnitureFolder.Parent = template

	template.Parent = templateFolder

	return template, roomAnchor, doorSpawn, entryWalkTarget, walkableFloor
end

local roomTemplates = getOrCreateFolder(ReplicatedStorage, "RoomTemplates")
local template, roomAnchor, doorSpawn, entryWalkTarget, walkableFloor = buildTemplate(roomTemplates)

print(TOOL_PREFIX .. " Created " .. template:GetFullName())
print(string.format(
	"%s LayoutId=%s TemplateName=%s DisplayName=%s TileCount=%d GridWidth/GridDepth=%dx%d TileSize=%d WalkableFloorSize=(%.1f, %.1f, %.1f)",
	TOOL_PREFIX,
	LAYOUT_ID,
	TEMPLATE_NAME,
	DISPLAY_NAME,
	TILE_COUNT,
	GRID_WIDTH,
	GRID_DEPTH,
	TILE_SIZE,
	walkableFloor.Size.X,
	walkableFloor.Size.Y,
	walkableFloor.Size.Z
))
print(string.format("%s AccessTier=%s RequiresVip=%s HasStairs=%s HasLevels=%s HasHiddenArea=%s.", TOOL_PREFIX, ACCESS_TIER, tostring(REQUIRES_VIP), "true", "false", "false"))
print(string.format("%s DoorTileIndex=%d DoorCenterX=%.1f.", TOOL_PREFIX, DOOR_TILE_INDEX, DOOR_CENTER_X))
print(TOOL_PREFIX .. " RoomAnchor position: " .. tostring(roomAnchor.Position))
print(TOOL_PREFIX .. " DoorSpawn position: " .. tostring(doorSpawn.Position))
print(TOOL_PREFIX .. " EntryWalkTarget position: " .. tostring(entryWalkTarget.Position))
print(string.format("%s cave width = %.0f tile (%.1f studs).", TOOL_PREFIX, DOOR_OPENING_WIDTH / TILE_SIZE, DOOR_OPENING_WIDTH))
print(string.format("%s EntryWalkTarget remains first interior tile: z=%.1f.", TOOL_PREFIX, entryWalkTarget.Position.Z))
print(TOOL_PREFIX .. " VIP platforms and stair/riser details are visual-only, non-colliding, non-touching, and non-querying.")
print(TOOL_PREFIX .. " Entrance lane kept clear from DoorSpawn to EntryWalkTarget.")
print(TOOL_PREFIX .. " Next: run docs/tools/ValidateRoomLayoutTemplates.lua.")
