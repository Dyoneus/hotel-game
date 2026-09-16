-- Studio helper: create a functional placeholder Game Hall public room template.
--
-- Run this manually in Roblox Studio Command Bar or from a temporary Script.
-- The helper creates ReplicatedStorage.PublicRoomTemplates.Public_GameHall
-- or the TemplateName configured for GameHall in PublicRoomConfig.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TOOL_PREFIX = "[CreateGameHallTemplate]"
local REPLACE_EXISTING = true

local PUBLIC_ROOM_ID = "GameHall"
local FALLBACK_TEMPLATE_NAME = "Public_GameHall"

local TILE_SIZE = 4
local GRID_WIDTH = 20
local GRID_DEPTH = 14
local FLOOR_SIZE = Vector3.new(GRID_WIDTH * TILE_SIZE, 0.5, GRID_DEPTH * TILE_SIZE)
local FLOOR_TOP_Y = FLOOR_SIZE.Y / 2
local MARKER_Y = FLOOR_TOP_Y + 2.75
local WALL_HEIGHT = 8
local WALL_THICKNESS = 1

local COLORS = {
	Floor = Color3.fromRGB(176, 180, 184),
	Runner = Color3.fromRGB(92, 113, 130),
	Wall = Color3.fromRGB(188, 194, 198),
	WallPanel = Color3.fromRGB(99, 116, 132),
	Trim = Color3.fromRGB(54, 63, 75),
	ArcadeBlue = Color3.fromRGB(63, 111, 171),
	ArcadeRed = Color3.fromRGB(167, 74, 70),
	ArcadeGreen = Color3.fromRGB(73, 142, 94),
	ArcadeYellow = Color3.fromRGB(214, 175, 72),
	Screen = Color3.fromRGB(38, 49, 61),
	Booth = Color3.fromRGB(102, 83, 142),
	Seat = Color3.fromRGB(73, 98, 126),
	SeatTrim = Color3.fromRGB(45, 59, 76),
	Board = Color3.fromRGB(42, 61, 72),
	BoardLine = Color3.fromRGB(219, 214, 145),
	BaseLight = Color3.fromRGB(232, 241, 255),
	CyanLight = Color3.fromRGB(89, 220, 255),
	MagentaLight = Color3.fromRGB(242, 107, 255),
	GreenLight = Color3.fromRGB(110, 255, 172),
}

local function getPublicRoomConfig()
	local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
	local configModule = sharedFolder and sharedFolder:FindFirstChild("PublicRoomConfig")

	if not configModule or not configModule:IsA("ModuleScript") then
		warn(TOOL_PREFIX .. " PublicRoomConfig not found; using fallback template name.")
		return nil
	end

	local ok, config = pcall(require, configModule)

	if not ok or typeof(config) ~= "table" then
		warn(TOOL_PREFIX .. " Could not require PublicRoomConfig; using fallback template name.")
		return nil
	end

	return config
end

local function getTemplateName()
	local config = getPublicRoomConfig()
	local roomConfig = nil

	if config then
		if typeof(config.GetPublicRoom) == "function" then
			roomConfig = config.GetPublicRoom(PUBLIC_ROOM_ID)
		elseif typeof(config.PublicRooms) == "table" then
			roomConfig = config.PublicRooms[PUBLIC_ROOM_ID]
		end
	end

	if typeof(roomConfig) == "table"
		and typeof(roomConfig.TemplateName) == "string"
		and roomConfig.TemplateName ~= "" then

		return roomConfig.TemplateName
	end

	return FALLBACK_TEMPLATE_NAME
end

local function getOrCreateFolder(parent, folderName)
	local folder = parent:FindFirstChild(folderName)

	if folder then
		if not folder:IsA("Folder") then
			error(TOOL_PREFIX .. " " .. folder:GetFullName() .. " exists but is not a Folder.")
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
	part.CastShadow = options.CastShadow ~= false
	part.Material = options.Material or Enum.Material.SmoothPlastic
	part.Color = options.Color or Color3.fromRGB(180, 180, 180)
	part.Transparency = options.Transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	return part
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

local function createMarker(parent, name, cframe, canQuery)
	return createPart(parent, name, Vector3.new(1, 1, 1), cframe, {
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = canQuery == true,
		CastShadow = false,
		Transparency = 1,
	})
end

local function setGridAttributes(instance)
	instance:SetAttribute("UsesTileGrid", true)
	instance:SetAttribute("TileSize", TILE_SIZE)
	instance:SetAttribute("GridWidth", GRID_WIDTH)
	instance:SetAttribute("GridDepth", GRID_DEPTH)
end

local function createDecorPart(parent, name, size, cframe, color, canCollide, material)
	return createPart(parent, name, size, cframe, {
		CanCollide = canCollide == true,
		CanTouch = false,
		CanQuery = canCollide == true,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
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

local function markWalkableDecorationPart(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part:SetAttribute("IsWalkableDecoration", true)
	part:SetAttribute("WalkableSurface", true)
	part:SetAttribute("BlocksMovement", false)

	return part
end

local function createWalkableFloorDecoration(parent, name, size, cframe, color, material)
	return markWalkableDecorationPart(createVisualPart(parent, name, size, cframe, color, material))
end

local function createPointLight(parentPart, name, color, brightness, range)
	local light = Instance.new("PointLight")
	light.Name = name or "PointLight"
	light.Color = color or COLORS.BaseLight
	light.Brightness = brightness or 0.55
	light.Range = range or 12
	light.Shadows = false
	light.Parent = parentPart

	return light
end

local function createSurfaceLight(parentPart, face, color, brightness, range)
	local light = Instance.new("SurfaceLight")
	light.Name = "SurfaceLight"
	light.Color = color or COLORS.BaseLight
	light.Face = face or Enum.NormalId.Bottom
	light.Brightness = brightness or 0.9
	light.Range = range or 14
	light.Shadows = false
	light.Parent = parentPart

	return light
end

local function createCeilingLight(parent, name, position, color, brightness, range)
	local fixture = Instance.new("Model")
	fixture.Name = name
	fixture.Parent = parent

	createVisualPart(
		fixture,
		"CeilingPlate",
		Vector3.new(3.4, 0.18, 3.4),
		CFrame.new(position.X, position.Y + 0.1, position.Z),
		COLORS.Trim,
		Enum.Material.Metal
	)

	local glow = createVisualPart(
		fixture,
		"GlowPanel",
		Vector3.new(2.6, 0.16, 2.6),
		CFrame.new(position.X, position.Y - 0.05, position.Z),
		color or COLORS.BaseLight,
		Enum.Material.Neon
	)
	createPointLight(glow, "BasePointLight", color or COLORS.BaseLight, brightness or 0.85, range or 18)
	createSurfaceLight(glow, Enum.NormalId.Bottom, color or COLORS.BaseLight, (brightness or 0.85) * 1.2, range or 18)

	return fixture
end

local function createAccentLightFixture(parent, name, position, color, brightness, range)
	local fixture = Instance.new("Model")
	fixture.Name = name
	fixture.Parent = parent

	createVisualPart(
		fixture,
		"Bracket",
		Vector3.new(1.2, 0.22, 1.2),
		CFrame.new(position.X, position.Y + 0.18, position.Z),
		COLORS.Trim,
		Enum.Material.Metal
	)

	local glow = createVisualPart(
		fixture,
		"AccentGlow",
		Vector3.new(1.5, 0.2, 1.5),
		CFrame.new(position),
		color,
		Enum.Material.Neon
	)
	createPointLight(glow, "AccentPointLight", color, brightness or 0.35, range or 10)
	createSurfaceLight(glow, Enum.NormalId.Bottom, color, brightness or 0.35, range or 10)

	return fixture
end

local function createWall(parent, name, size, cframe)
	return createDecorPart(parent, name, size, cframe, COLORS.Wall, true)
end

local function buildWalls(roomFolder)
	local wallsFolder = Instance.new("Folder")
	wallsFolder.Name = "Walls"
	wallsFolder.Parent = roomFolder

	local wallY = FLOOR_TOP_Y + WALL_HEIGHT / 2
	local frontZ = -FLOOR_SIZE.Z / 2 - WALL_THICKNESS / 2
	local backZ = FLOOR_SIZE.Z / 2 + WALL_THICKNESS / 2
	local leftX = -FLOOR_SIZE.X / 2 - WALL_THICKNESS / 2
	local rightX = FLOOR_SIZE.X / 2 + WALL_THICKNESS / 2

	createWall(wallsFolder, "BackWall", Vector3.new(FLOOR_SIZE.X + 2, WALL_HEIGHT, WALL_THICKNESS), CFrame.new(0, wallY, backZ))
	createWall(wallsFolder, "LeftWall", Vector3.new(WALL_THICKNESS, WALL_HEIGHT, FLOOR_SIZE.Z), CFrame.new(leftX, wallY, 0))
	createWall(wallsFolder, "RightWall", Vector3.new(WALL_THICKNESS, WALL_HEIGHT, FLOOR_SIZE.Z), CFrame.new(rightX, wallY, 0))
	createWall(wallsFolder, "FrontWallLeft", Vector3.new(32, WALL_HEIGHT, WALL_THICKNESS), CFrame.new(-24, wallY, frontZ))
	createWall(wallsFolder, "FrontWallRight", Vector3.new(32, WALL_HEIGHT, WALL_THICKNESS), CFrame.new(24, wallY, frontZ))
	createVisualPart(wallsFolder, "DoorwayHeader", Vector3.new(16, 1.2, WALL_THICKNESS + 0.1), CFrame.new(0, FLOOR_TOP_Y + 7.2, frontZ), COLORS.Trim)

	for _, x in ipairs({ -28, -12, 12, 28 }) do
		createVisualPart(wallsFolder, "BackWallPanel", Vector3.new(10, 4.4, 0.14), CFrame.new(x, FLOOR_TOP_Y + 4.4, backZ - 0.6), COLORS.WallPanel)
	end

	return wallsFolder
end

local function buildDecorativeFloor(roomFolder)
	local decorativeFloor = Instance.new("Folder")
	decorativeFloor.Name = "DecorativeFloor"
	decorativeFloor.Parent = roomFolder

	createWalkableFloorDecoration(decorativeFloor, "CentralWalkway", Vector3.new(14, 0.08, 44), CFrame.new(-2, FLOOR_TOP_Y + 0.06, -2), COLORS.Runner, Enum.Material.SmoothPlastic)
	createWalkableFloorDecoration(decorativeFloor, "EntrancePad", Vector3.new(12, 0.08, 6), CFrame.new(-2, FLOOR_TOP_Y + 0.07, -25), Color3.fromRGB(74, 91, 111), Enum.Material.SmoothPlastic)
	createWalkableFloorDecoration(decorativeFloor, "ArcadeZoneLeft", Vector3.new(20, 0.05, 42), CFrame.new(-28, FLOOR_TOP_Y + 0.04, 0), Color3.fromRGB(153, 164, 172), Enum.Material.SmoothPlastic)
	createWalkableFloorDecoration(decorativeFloor, "BoothZoneRight", Vector3.new(20, 0.05, 42), CFrame.new(28, FLOOR_TOP_Y + 0.04, 0), Color3.fromRGB(153, 164, 172), Enum.Material.SmoothPlastic)

	return decorativeFloor
end

local function createArcadeMachine(parent, name, x, z, color)
	local machine = Instance.new("Model")
	machine.Name = name
	machine.Parent = parent

	createDecorPart(machine, "Cabinet", Vector3.new(3.2, 4.2, 2.4), CFrame.new(x, FLOOR_TOP_Y + 2.1, z), color, true)
	local screen = createVisualPart(machine, "Screen", Vector3.new(2.4, 1.4, 0.16), CFrame.new(x, FLOOR_TOP_Y + 3.0, z - 1.25), COLORS.Screen, Enum.Material.Neon)
	createPointLight(screen, "ScreenGlow", color, 0.18, 7)
	local marquee = createVisualPart(machine, "MarqueeGlow", Vector3.new(2.7, 0.35, 0.18), CFrame.new(x, FLOOR_TOP_Y + 4.25, z - 1.25), color, Enum.Material.Neon)
	createPointLight(marquee, "MarqueeGlowLight", color, 0.24, 8)
	createDecorPart(machine, "Base", Vector3.new(3.6, 0.5, 2.8), CFrame.new(x, FLOOR_TOP_Y + 0.25, z), COLORS.Trim, true)

	return machine
end

local function createActivityBooth(parent, name, x, z, color)
	local booth = Instance.new("Model")
	booth.Name = name
	booth.Parent = parent

	createDecorPart(booth, "Counter", Vector3.new(6, 2, 2.4), CFrame.new(x, FLOOR_TOP_Y + 1, z), color, true)
	createVisualPart(booth, "Panel", Vector3.new(5.5, 2.8, 0.18), CFrame.new(x, FLOOR_TOP_Y + 3.2, z + 1.25), COLORS.Board, Enum.Material.SmoothPlastic)
	local panelLine = createVisualPart(booth, "PanelLine", Vector3.new(4.6, 0.22, 0.12), CFrame.new(x, FLOOR_TOP_Y + 3.35, z + 1.05), COLORS.BoardLine, Enum.Material.Neon)
	createPointLight(panelLine, "PanelAccentLight", COLORS.BoardLine, 0.18, 7)

	return booth
end

local function createBench(parent, name, cframe)
	local bench = Instance.new("Model")
	bench.Name = name
	bench.Parent = parent

	createDecorPart(bench, "Seat", Vector3.new(8, 0.55, 2.2), cframe * CFrame.new(0, FLOOR_TOP_Y + 0.55, 0), COLORS.Seat, true)
	createDecorPart(bench, "Back", Vector3.new(8, 2.1, 0.45), cframe * CFrame.new(0, FLOOR_TOP_Y + 1.55, 1.05), COLORS.SeatTrim, true)

	return bench
end

local function buildDecor(roomFolder)
	local decorFolder = Instance.new("Folder")
	decorFolder.Name = "Decor"
	decorFolder.Parent = roomFolder

	local arcadeColors = { COLORS.ArcadeBlue, COLORS.ArcadeRed, COLORS.ArcadeGreen, COLORS.ArcadeYellow }
	local arcadeZValues = { -18, -10, -2, 6, 14, 22 }

	for index, z in ipairs(arcadeZValues) do
		createArcadeMachine(decorFolder, "ArcadeMachine_" .. tostring(index), -34, z, arcadeColors[((index - 1) % #arcadeColors) + 1])
	end

	local boothZValues = { -18, -10, -2, 6, 14 }

	for index, z in ipairs(boothZValues) do
		createActivityBooth(decorFolder, "ActivityBooth_" .. tostring(index), 34, z, COLORS.Booth)
	end

	for index, z in ipairs({ -22, -10, 2, 14, 24 }) do
		createCeilingLight(decorFolder, "BaseCeilingLight_" .. tostring(index), Vector3.new(-2, FLOOR_TOP_Y + 7.35, z), COLORS.BaseLight, 0.9, 20)
	end

	local accentLights = {
		{ Name = "ArcadeAccent_CyanFront", Position = Vector3.new(-28, FLOOR_TOP_Y + 6.5, -14), Color = COLORS.CyanLight },
		{ Name = "ArcadeAccent_MagentaCenter", Position = Vector3.new(-28, FLOOR_TOP_Y + 6.5, 2), Color = COLORS.MagentaLight },
		{ Name = "ArcadeAccent_GreenBack", Position = Vector3.new(-28, FLOOR_TOP_Y + 6.5, 18), Color = COLORS.GreenLight },
		{ Name = "BoothAccent_MagentaFront", Position = Vector3.new(28, FLOOR_TOP_Y + 6.5, -14), Color = COLORS.MagentaLight },
		{ Name = "BoothAccent_CyanCenter", Position = Vector3.new(28, FLOOR_TOP_Y + 6.5, 2), Color = COLORS.CyanLight },
		{ Name = "BoothAccent_GreenBack", Position = Vector3.new(28, FLOOR_TOP_Y + 6.5, 18), Color = COLORS.GreenLight },
	}

	for _, lightData in ipairs(accentLights) do
		createAccentLightFixture(decorFolder, lightData.Name, lightData.Position, lightData.Color, 0.32, 11)
	end

	createVisualPart(decorFolder, "LeaderboardBoard", Vector3.new(20, 5, 0.3), CFrame.new(0, FLOOR_TOP_Y + 4, 27.4), COLORS.Board)

	for index, x in ipairs({ -7, -2, 3, 8 }) do
		createVisualPart(decorFolder, "LeaderboardLine_" .. tostring(index), Vector3.new(3.6, 0.25, 0.18), CFrame.new(x, FLOOR_TOP_Y + 4.1, 27.2), COLORS.BoardLine, Enum.Material.Neon)
	end

	createBench(decorFolder, "WaitingBench_Left", CFrame.new(-18, 0, -18))
	createBench(decorFolder, "WaitingBench_Right", CFrame.new(18, 0, -18))
	createBench(decorFolder, "BackBench_Left", CFrame.new(-22, 0, 22))
	createBench(decorFolder, "BackBench_Right", CFrame.new(22, 0, 22))

	createDecorPart(decorFolder, "LeftQueueDivider", Vector3.new(1, 1.4, 20), CFrame.new(-10, FLOOR_TOP_Y + 0.7, 2), COLORS.Trim, true)
	createDecorPart(decorFolder, "RightQueueDivider", Vector3.new(1, 1.4, 20), CFrame.new(10, FLOOR_TOP_Y + 0.7, 2), COLORS.Trim, true)

	return decorFolder
end

local function anchorModelParts(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

local function findChairTemplate()
	local furnitureTemplates = ReplicatedStorage:FindFirstChild("FurnitureTemplates")

	if not furnitureTemplates then
		return nil
	end

	return furnitureTemplates:FindFirstChild("Chair_01")
end

local function createPlaceholderChair(parent, name, cframe)
	local chair = Instance.new("Model")
	chair.Name = name
	chair.Parent = parent

	createDecorPart(chair, "Seat", Vector3.new(2.4, 0.4, 2.2), cframe * CFrame.new(0, FLOOR_TOP_Y + 0.45, 0), COLORS.Seat, true)
	createDecorPart(chair, "Back", Vector3.new(2.4, 2, 0.35), cframe * CFrame.new(0, FLOOR_TOP_Y + 1.35, 0.95), COLORS.SeatTrim, true)

	return chair
end

local function placeChair(parent, chairTemplate, name, cframe)
	if chairTemplate and (chairTemplate:IsA("Model") or chairTemplate:IsA("BasePart")) then
		local chair = chairTemplate:Clone()
		chair.Name = name
		chair.Parent = parent

		if chair:IsA("Model") then
			anchorModelParts(chair)
			chair:PivotTo(cframe)
		else
			chair.Anchored = true
			chair.CFrame = cframe
		end

		return chair
	end

	return createPlaceholderChair(parent, name, cframe)
end

local function buildFurniture(template)
	local furnitureFolder = Instance.new("Folder")
	furnitureFolder.Name = "Furniture"
	furnitureFolder.Parent = template

	local chairTemplate = findChairTemplate()

	if not chairTemplate then
		warn(TOOL_PREFIX .. " ReplicatedStorage.FurnitureTemplates.Chair_01 not found; using placeholder chairs without Sit support.")
	end

	local chairPlacements = {
		{ Name = "WaitingChair_Left_01", CFrame = CFrame.new(-26, FLOOR_TOP_Y + 0.1, -18) * CFrame.Angles(0, math.rad(90), 0) },
		{ Name = "WaitingChair_Left_02", CFrame = CFrame.new(-22, FLOOR_TOP_Y + 0.1, -18) * CFrame.Angles(0, math.rad(90), 0) },
		{ Name = "WaitingChair_Right_01", CFrame = CFrame.new(22, FLOOR_TOP_Y + 0.1, -18) * CFrame.Angles(0, math.rad(-90), 0) },
		{ Name = "WaitingChair_Right_02", CFrame = CFrame.new(26, FLOOR_TOP_Y + 0.1, -18) * CFrame.Angles(0, math.rad(-90), 0) },
		{ Name = "BackChair_Left", CFrame = CFrame.new(-14, FLOOR_TOP_Y + 0.1, 20) },
		{ Name = "BackChair_Right", CFrame = CFrame.new(14, FLOOR_TOP_Y + 0.1, 20) },
	}

	for _, placement in ipairs(chairPlacements) do
		placeChair(furnitureFolder, chairTemplate, placement.Name, placement.CFrame)
	end

	return furnitureFolder
end

local function buildTemplate(templateName, templateFolder)
	local existingTemplate = templateFolder:FindFirstChild(templateName)

	if existingTemplate then
		if not REPLACE_EXISTING then
			error(TOOL_PREFIX .. " Template already exists and REPLACE_EXISTING is false: " .. templateName)
		end

		existingTemplate:Destroy()
	end

	local template = Instance.new("Model")
	template.Name = templateName
	setGridAttributes(template)
	template:SetAttribute("PublicRoomId", PUBLIC_ROOM_ID)
	template:SetAttribute("DisplayName", "Game Hall")
	template:SetAttribute("RoomType", "PublicSpace")

	local roomAnchor = createMarker(template, "RoomAnchor", CFrame.new(0, 0, 0), false)
	local doorSpawn = createMarker(template, "DoorSpawn", CFrame.new(-2, MARKER_Y, -26), false)
	local entryWalkTarget = createMarker(template, "EntryWalkTarget", CFrame.new(-2, MARKER_Y, -22), false)
	template.PrimaryPart = roomAnchor

	local roomFolder = Instance.new("Folder")
	roomFolder.Name = "Room"
	roomFolder.Parent = template

	local walkableFloor = createPart(roomFolder, "WalkableFloor", FLOOR_SIZE, CFrame.new(0, 0, 0), {
		CanCollide = true,
		CanTouch = false,
		CanQuery = true,
		Color = COLORS.Floor,
	})
	setGridAttributes(walkableFloor)

	local roomExitZone = createPart(roomFolder, "RoomExitZone", Vector3.new(12, 6, 3), CFrame.new(-2, FLOOR_TOP_Y + 3, -28.5), {
		CanCollide = false,
		CanTouch = false,
		CanQuery = true,
		CastShadow = false,
		Transparency = 1,
	})
	roomExitZone:SetAttribute("IsRoomExit", true)

	buildWalls(roomFolder)
	buildDecorativeFloor(roomFolder)
	buildDecor(roomFolder)
	buildFurniture(template)

	template.Parent = templateFolder

	return template, doorSpawn, entryWalkTarget
end

local publicRoomTemplates = getOrCreateFolder(ReplicatedStorage, "PublicRoomTemplates")
local templateName = getTemplateName()
local template, doorSpawn, entryWalkTarget = buildTemplate(templateName, publicRoomTemplates)

print(TOOL_PREFIX .. " Created template: " .. template:GetFullName())
print(string.format("%s Grid: %dx%d, TileSize=%d, FloorSize=(%.1f, %.1f, %.1f)", TOOL_PREFIX, GRID_WIDTH, GRID_DEPTH, TILE_SIZE, FLOOR_SIZE.X, FLOOR_SIZE.Y, FLOOR_SIZE.Z))
print(TOOL_PREFIX .. " DoorSpawn position: " .. tostring(doorSpawn.Position))
print(TOOL_PREFIX .. " EntryWalkTarget position: " .. tostring(entryWalkTarget.Position))
print(TOOL_PREFIX .. " Wide central walkway kept clear from entrance to leaderboard area.")
print(TOOL_PREFIX .. " Next: run docs/tools/ValidatePublicRoomTemplates.lua, then test Game Hall from the Room Navigator.")
