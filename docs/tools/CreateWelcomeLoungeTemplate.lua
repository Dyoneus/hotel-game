-- Studio helper: create a detailed placeholder Welcome Lounge public room template.
--
-- Run this manually in Roblox Studio Command Bar or from a temporary Script.
-- The helper creates ReplicatedStorage.PublicRoomTemplates.Public_WelcomeLounge
-- or the TemplateName configured for WelcomeLounge in PublicRoomConfig.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TOOL_PREFIX = "[CreateWelcomeLoungeTemplate]"
local REPLACE_EXISTING = true

local PUBLIC_ROOM_ID = "WelcomeLounge"
local FALLBACK_TEMPLATE_NAME = "Public_WelcomeLounge"

local TILE_SIZE = 4
local GRID_WIDTH = 16
local GRID_DEPTH = 12
local FLOOR_SIZE = Vector3.new(GRID_WIDTH * TILE_SIZE, 0.5, GRID_DEPTH * TILE_SIZE)
local FLOOR_TOP_Y = FLOOR_SIZE.Y / 2
local MARKER_Y = FLOOR_TOP_Y + 2.75
local WALL_HEIGHT = 8
local WALL_THICKNESS = 1

local COLORS = {
	Floor = Color3.fromRGB(190, 188, 174),
	FloorAccent = Color3.fromRGB(156, 171, 160),
	Wall = Color3.fromRGB(214, 207, 188),
	WallPanel = Color3.fromRGB(180, 169, 148),
	Window = Color3.fromRGB(132, 178, 194),
	Trim = Color3.fromRGB(128, 96, 68),
	DarkTrim = Color3.fromRGB(76, 58, 43),
	Rug = Color3.fromRGB(118, 150, 155),
	RugBorder = Color3.fromRGB(82, 111, 119),
	Desk = Color3.fromRGB(124, 91, 61),
	DeskTop = Color3.fromRGB(156, 116, 78),
	Plant = Color3.fromRGB(72, 132, 76),
	PlantDark = Color3.fromRGB(46, 92, 55),
	Pot = Color3.fromRGB(122, 83, 58),
	PlaceholderChair = Color3.fromRGB(92, 119, 150),
	PlaceholderChairTrim = Color3.fromRGB(55, 75, 98),
	Gold = Color3.fromRGB(224, 184, 92),
	Light = Color3.fromRGB(255, 235, 180),
	Divider = Color3.fromRGB(151, 128, 94),
	Sign = Color3.fromRGB(56, 84, 100),
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

local function getWelcomeLoungeTemplateName()
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

local function createWall(parent, name, size, cframe)
	return createPart(parent, name, size, cframe, {
		CanCollide = true,
		CanTouch = false,
		CanQuery = true,
		Color = COLORS.Wall,
		Material = Enum.Material.SmoothPlastic,
	})
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

local function createSurfaceSign(parent, name, text, size, cframe, options)
	options = options or {}

	local signPart = createVisualPart(
		parent,
		name,
		size,
		cframe,
		options.Color or COLORS.Sign,
		options.Material or Enum.Material.SmoothPlastic
	)

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "SignGui"
	surfaceGui.Face = options.Face or Enum.NormalId.Front
	surfaceGui.LightInfluence = 0
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = options.PixelsPerStud or 45
	surfaceGui.Parent = signPart

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = options.Font or Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = options.TextColor or Color3.fromRGB(255, 247, 220)
	label.TextScaled = true
	label.TextWrapped = true
	label.Parent = surfaceGui

	return signPart
end

local function createPointLight(parentPart, brightness, range)
	local light = Instance.new("PointLight")
	light.Name = "WarmLight"
	light.Color = COLORS.Light
	light.Brightness = brightness or 0.55
	light.Range = range or 14
	light.Shadows = false
	light.Parent = parentPart

	return light
end

local function createPlant(parent, name, position, scale)
	scale = scale or 1

	local plantModel = Instance.new("Model")
	plantModel.Name = name
	plantModel.Parent = parent

	createDecorPart(
		plantModel,
		"Pot",
		Vector3.new(2.1, 1.2, 2.1) * scale,
		CFrame.new(position.X, FLOOR_TOP_Y + 0.6 * scale, position.Z),
		COLORS.Pot,
		true
	)

	local leaves = createVisualPart(
		plantModel,
		"Leaves",
		Vector3.new(2.9, 2.9, 2.9) * scale,
		CFrame.new(position.X, FLOOR_TOP_Y + 2.45 * scale, position.Z),
		COLORS.Plant,
		Enum.Material.Grass
	)
	leaves.Shape = Enum.PartType.Ball

	local leavesTop = createVisualPart(
		plantModel,
		"LeavesTop",
		Vector3.new(2.1, 2.1, 2.1) * scale,
		CFrame.new(position.X, FLOOR_TOP_Y + 3.55 * scale, position.Z),
		COLORS.PlantDark,
		Enum.Material.Grass
	)
	leavesTop.Shape = Enum.PartType.Ball

	return plantModel
end

local function createColumn(parent, name, position)
	local column = Instance.new("Model")
	column.Name = name
	column.Parent = parent

	createDecorPart(
		column,
		"Base",
		Vector3.new(2.8, 0.6, 2.8),
		CFrame.new(position.X, FLOOR_TOP_Y + 0.3, position.Z),
		COLORS.Trim,
		true
	)
	createDecorPart(
		column,
		"Shaft",
		Vector3.new(1.6, 5.8, 1.6),
		CFrame.new(position.X, FLOOR_TOP_Y + 3.2, position.Z),
		COLORS.WallPanel,
		true
	)
	createDecorPart(
		column,
		"Cap",
		Vector3.new(3, 0.6, 3),
		CFrame.new(position.X, FLOOR_TOP_Y + 6.2, position.Z),
		COLORS.Trim,
		true
	)

	return column
end

local function createWallSconce(parent, name, position, rotationY)
	local baseCFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(rotationY or 0), 0)
	local holder = createVisualPart(
		parent,
		name .. "_Holder",
		Vector3.new(0.35, 1.1, 0.18),
		baseCFrame,
		COLORS.DarkTrim,
		Enum.Material.Metal
	)

	local glow = createVisualPart(
		parent,
		name .. "_Glow",
		Vector3.new(0.8, 0.8, 0.22),
		baseCFrame * CFrame.new(0, 0.48, -0.12),
		COLORS.Light,
		Enum.Material.Neon
	)
	createPointLight(glow, 0.45, 12)

	return holder, glow
end

local function anchorModelParts(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

local function createPlaceholderChair(parent, name, cframe)
	local chair = Instance.new("Model")
	chair.Name = name
	chair.Parent = parent

	createDecorPart(
		chair,
		"Seat",
		Vector3.new(2.6, 0.4, 2.4),
		cframe * CFrame.new(0, FLOOR_TOP_Y + 0.45, 0),
		COLORS.PlaceholderChair,
		true
	)

	createDecorPart(
		chair,
		"Back",
		Vector3.new(2.6, 2.4, 0.35),
		cframe * CFrame.new(0, FLOOR_TOP_Y + 1.45, 1.0),
		COLORS.PlaceholderChairTrim,
		true
	)

	for _, offset in ipairs({
		Vector3.new(-0.95, FLOOR_TOP_Y + 0.05, -0.75),
		Vector3.new(0.95, FLOOR_TOP_Y + 0.05, -0.75),
		Vector3.new(-0.95, FLOOR_TOP_Y + 0.05, 0.75),
		Vector3.new(0.95, FLOOR_TOP_Y + 0.05, 0.75),
	}) do
		createDecorPart(
			chair,
			"Leg",
			Vector3.new(0.25, 0.8, 0.25),
			cframe * CFrame.new(offset),
			COLORS.DarkTrim,
			true
		)
	end

	return chair
end

local function createBench(parent, name, cframe, length)
	local bench = Instance.new("Model")
	bench.Name = name
	bench.Parent = parent

	createDecorPart(
		bench,
		"Seat",
		Vector3.new(length, 0.55, 2.2),
		cframe * CFrame.new(0, FLOOR_TOP_Y + 0.55, 0),
		COLORS.PlaceholderChair,
		true
	)
	createDecorPart(
		bench,
		"Back",
		Vector3.new(length, 2.2, 0.45),
		cframe * CFrame.new(0, FLOOR_TOP_Y + 1.55, 1.05),
		COLORS.PlaceholderChairTrim,
		true
	)
	createDecorPart(
		bench,
		"Base",
		Vector3.new(length - 0.8, 0.45, 1.4),
		cframe * CFrame.new(0, FLOOR_TOP_Y + 0.25, -0.1),
		COLORS.DarkTrim,
		true
	)

	return bench
end

local function findChairTemplate()
	local furnitureTemplates = ReplicatedStorage:FindFirstChild("FurnitureTemplates")

	if not furnitureTemplates then
		return nil
	end

	local chairTemplate = furnitureTemplates:FindFirstChild("Chair_01")

	if chairTemplate then
		return chairTemplate
	end

	return nil
end

local function placeChair(parent, chairTemplate, name, cframe)
	if chairTemplate then
		if not chairTemplate:IsA("Model") and not chairTemplate:IsA("BasePart") then
			warn(TOOL_PREFIX .. " Chair_01 is not a Model or BasePart; using placeholder chair for " .. name .. ".")
			return createPlaceholderChair(parent, name, cframe)
		end

		local chair = chairTemplate:Clone()
		chair.Name = name
		chair.Parent = parent

		if chair:IsA("Model") then
			anchorModelParts(chair)
			chair:PivotTo(cframe)
		elseif chair:IsA("BasePart") then
			chair.Anchored = true
			chair.CFrame = cframe
		end

		return chair
	end

	return createPlaceholderChair(parent, name, cframe)
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
	createWall(wallsFolder, "FrontWallLeft", Vector3.new(25, WALL_HEIGHT, WALL_THICKNESS), CFrame.new(-19.5, wallY, frontZ))
	createWall(wallsFolder, "FrontWallRight", Vector3.new(25, WALL_HEIGHT, WALL_THICKNESS), CFrame.new(19.5, wallY, frontZ))

	createVisualPart(
		wallsFolder,
		"DoorwayHeader",
		Vector3.new(13, 1.4, WALL_THICKNESS + 0.1),
		CFrame.new(0, FLOOR_TOP_Y + 7.3, frontZ),
		COLORS.Trim,
		Enum.Material.SmoothPlastic
	)

	createDecorPart(wallsFolder, "DoorwayLeftPillar", Vector3.new(1.5, 7, 1.5), CFrame.new(-7.1, FLOOR_TOP_Y + 3.5, frontZ), COLORS.Trim, true)
	createDecorPart(wallsFolder, "DoorwayRightPillar", Vector3.new(1.5, 7, 1.5), CFrame.new(7.1, FLOOR_TOP_Y + 3.5, frontZ), COLORS.Trim, true)

	for _, x in ipairs({ -23, -11, 11, 23 }) do
		createVisualPart(
			wallsFolder,
			"BackWallPanel",
			Vector3.new(7, 4.2, 0.16),
			CFrame.new(x, FLOOR_TOP_Y + 4.4, backZ - 0.58),
			COLORS.WallPanel,
			Enum.Material.SmoothPlastic
		)
	end

	for _, x in ipairs({ -17, 17 }) do
		createVisualPart(
			wallsFolder,
			"BackWindow",
			Vector3.new(8, 3.5, 0.18),
			CFrame.new(x, FLOOR_TOP_Y + 4.5, backZ - 0.66),
			COLORS.Window,
			Enum.Material.Glass
		)
	end

	for _, z in ipairs({ -14, 0, 14 }) do
		createVisualPart(
			wallsFolder,
			"LeftWallPanel",
			Vector3.new(0.16, 4.2, 7),
			CFrame.new(leftX + 0.58, FLOOR_TOP_Y + 4.4, z),
			COLORS.WallPanel,
			Enum.Material.SmoothPlastic
		)
		createVisualPart(
			wallsFolder,
			"RightWallPanel",
			Vector3.new(0.16, 4.2, 7),
			CFrame.new(rightX - 0.58, FLOOR_TOP_Y + 4.4, z),
			COLORS.WallPanel,
			Enum.Material.SmoothPlastic
		)
	end

	return wallsFolder
end

local function buildDecorativeFloor(roomFolder)
	local decorativeFloor = Instance.new("Folder")
	decorativeFloor.Name = "DecorativeFloor"
	decorativeFloor.Parent = roomFolder

	createVisualPart(decorativeFloor, "MainCarpet", Vector3.new(30, 0.08, 20), CFrame.new(-2, FLOOR_TOP_Y + 0.05, 0), COLORS.Rug, Enum.Material.Fabric)
	createVisualPart(decorativeFloor, "MainCarpetBorder", Vector3.new(32, 0.06, 22), CFrame.new(-2, FLOOR_TOP_Y + 0.035, 0), COLORS.RugBorder, Enum.Material.Fabric)
	createVisualPart(decorativeFloor, "EntranceMat", Vector3.new(10, 0.08, 5), CFrame.new(-2, FLOOR_TOP_Y + 0.06, -21.5), Color3.fromRGB(94, 112, 120), Enum.Material.Fabric)
	createVisualPart(decorativeFloor, "ReceptionRunner", Vector3.new(22, 0.07, 5), CFrame.new(0, FLOOR_TOP_Y + 0.06, 13), Color3.fromRGB(166, 150, 115), Enum.Material.Fabric)

	for _, x in ipairs({ -30, -26, 26, 30 }) do
		createVisualPart(
			decorativeFloor,
			"CornerTileAccent",
			Vector3.new(3.5, 0.05, 3.5),
			CFrame.new(x, FLOOR_TOP_Y + 0.07, 22),
			COLORS.FloorAccent,
			Enum.Material.SmoothPlastic
		)
	end

	return decorativeFloor
end

local function buildDecor(roomFolder)
	local decorFolder = Instance.new("Folder")
	decorFolder.Name = "Decor"
	decorFolder.Parent = roomFolder

	createDecorPart(decorFolder, "ReceptionDesk", Vector3.new(21, 2.2, 3.2), CFrame.new(0, FLOOR_TOP_Y + 1.1, 18), COLORS.Desk, true)
	createDecorPart(decorFolder, "ReceptionCounterTop", Vector3.new(22, 0.35, 4), CFrame.new(0, FLOOR_TOP_Y + 2.35, 18), COLORS.DeskTop, true)
	createDecorPart(decorFolder, "ReceptionSideLeft", Vector3.new(3, 1.8, 5.8), CFrame.new(-10, FLOOR_TOP_Y + 0.9, 15.6), COLORS.Desk, true)
	createDecorPart(decorFolder, "ReceptionSideRight", Vector3.new(3, 1.8, 5.8), CFrame.new(10, FLOOR_TOP_Y + 0.9, 15.6), COLORS.Desk, true)

	createSurfaceSign(
		decorFolder,
		"WelcomeLoungeSign",
		"Welcome Lounge",
		Vector3.new(18, 3.2, 0.35),
		CFrame.new(0, FLOOR_TOP_Y + 6.1, 23.35),
		{ TextColor = Color3.fromRGB(255, 238, 185), PixelsPerStud = 42 }
	)

	createSurfaceSign(
		decorFolder,
		"HelpDeskSign",
		"Help Desk",
		Vector3.new(7, 1.7, 0.25),
		CFrame.new(0, FLOOR_TOP_Y + 3.6, 15.65),
		{ TextColor = Color3.fromRGB(255, 247, 220), PixelsPerStud = 48 }
	)

	createSurfaceSign(
		decorFolder,
		"NavigatorBoard",
		"Navigator",
		Vector3.new(8, 4.8, 0.35),
		CFrame.new(-25.6, FLOOR_TOP_Y + 3.1, 8) * CFrame.Angles(0, math.rad(90), 0),
		{ TextColor = Color3.fromRGB(230, 250, 255), PixelsPerStud = 40 }
	)

	createDecorPart(decorFolder, "NavigatorKioskBase", Vector3.new(4, 1.1, 3), CFrame.new(-24, FLOOR_TOP_Y + 0.55, 5), COLORS.DarkTrim, true)
	createDecorPart(decorFolder, "NavigatorKioskScreen", Vector3.new(3.2, 3.2, 0.3), CFrame.new(-24, FLOOR_TOP_Y + 2.5, 3.4), COLORS.Sign, true)

	for _, position in ipairs({
		Vector3.new(-27, 0, -18),
		Vector3.new(27, 0, -18),
		Vector3.new(-27, 0, 18),
		Vector3.new(27, 0, 18),
		Vector3.new(-12, 0, 19),
		Vector3.new(12, 0, 19),
	}) do
		createPlant(decorFolder, "PottedPlant", position)
	end

	for _, columnPosition in ipairs({
		Vector3.new(-28, 0, -8),
		Vector3.new(28, 0, -8),
		Vector3.new(-28, 0, 10),
		Vector3.new(28, 0, 10),
	}) do
		createColumn(decorFolder, "LoungeColumn", columnPosition)
	end

	createDecorPart(decorFolder, "LeftLowDivider", Vector3.new(1, 1.8, 18), CFrame.new(-10, FLOOR_TOP_Y + 0.9, 0), COLORS.Divider, true)
	createDecorPart(decorFolder, "RightLowDivider", Vector3.new(1, 1.8, 18), CFrame.new(10, FLOOR_TOP_Y + 0.9, 0), COLORS.Divider, true)
	createVisualPart(decorFolder, "LeftDividerTrim", Vector3.new(1.2, 0.22, 18.5), CFrame.new(-10, FLOOR_TOP_Y + 1.9, 0), COLORS.Gold, Enum.Material.Metal)
	createVisualPart(decorFolder, "RightDividerTrim", Vector3.new(1.2, 0.22, 18.5), CFrame.new(10, FLOOR_TOP_Y + 1.9, 0), COLORS.Gold, Enum.Material.Metal)

	createBench(decorFolder, "LeftSofa", CFrame.new(-22, 0, -8) * CFrame.Angles(0, math.rad(90), 0), 7)
	createBench(decorFolder, "RightSofa", CFrame.new(22, 0, -8) * CFrame.Angles(0, math.rad(-90), 0), 7)
	createBench(decorFolder, "BackSofaLeft", CFrame.new(-18, 0, 11), 8)
	createBench(decorFolder, "BackSofaRight", CFrame.new(18, 0, 11), 8)

	createDecorPart(decorFolder, "LeftCoffeeTable", Vector3.new(4, 0.9, 6), CFrame.new(-20, FLOOR_TOP_Y + 0.45, 0), Color3.fromRGB(104, 76, 52), true)
	createDecorPart(decorFolder, "RightCoffeeTable", Vector3.new(4, 0.9, 6), CFrame.new(20, FLOOR_TOP_Y + 0.45, 0), Color3.fromRGB(104, 76, 52), true)

	createWallSconce(decorFolder, "BackLightLeft", Vector3.new(-24, FLOOR_TOP_Y + 5.4, 23.38), 0)
	createWallSconce(decorFolder, "BackLightRight", Vector3.new(24, FLOOR_TOP_Y + 5.4, 23.38), 0)
	createWallSconce(decorFolder, "LeftLight", Vector3.new(-32.38, FLOOR_TOP_Y + 5.2, -2), 90)
	createWallSconce(decorFolder, "RightLight", Vector3.new(32.38, FLOOR_TOP_Y + 5.2, -2), -90)

	return decorFolder
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
		{ Name = "PublicChair_Left_01", CFrame = CFrame.new(-26, FLOOR_TOP_Y + 0.1, -4) * CFrame.Angles(0, math.rad(90), 0) },
		{ Name = "PublicChair_Left_02", CFrame = CFrame.new(-26, FLOOR_TOP_Y + 0.1, 4) * CFrame.Angles(0, math.rad(90), 0) },
		{ Name = "PublicChair_Left_03", CFrame = CFrame.new(-18, FLOOR_TOP_Y + 0.1, -12) },
		{ Name = "PublicChair_Right_01", CFrame = CFrame.new(26, FLOOR_TOP_Y + 0.1, -4) * CFrame.Angles(0, math.rad(-90), 0) },
		{ Name = "PublicChair_Right_02", CFrame = CFrame.new(26, FLOOR_TOP_Y + 0.1, 4) * CFrame.Angles(0, math.rad(-90), 0) },
		{ Name = "PublicChair_Right_03", CFrame = CFrame.new(18, FLOOR_TOP_Y + 0.1, -12) },
		{ Name = "PublicChair_Back_01", CFrame = CFrame.new(-14, FLOOR_TOP_Y + 0.1, 7) },
		{ Name = "PublicChair_Back_02", CFrame = CFrame.new(14, FLOOR_TOP_Y + 0.1, 7) },
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
	template:SetAttribute("DisplayName", "Welcome Lounge")
	template:SetAttribute("RoomType", "PublicSpace")

	local roomAnchor = createMarker(template, "RoomAnchor", CFrame.new(0, 0, 0), false)
	local doorSpawn = createMarker(template, "DoorSpawn", CFrame.new(-2, MARKER_Y, -22), false)
	local entryWalkTarget = createMarker(template, "EntryWalkTarget", CFrame.new(-2, MARKER_Y, -18), false)
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

	local roomExitZone = createPart(roomFolder, "RoomExitZone", Vector3.new(10, 6, 3), CFrame.new(-2, FLOOR_TOP_Y + 3, -24.5), {
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

	return template, roomAnchor, doorSpawn, entryWalkTarget
end

local publicRoomTemplates = getOrCreateFolder(ReplicatedStorage, "PublicRoomTemplates")
local templateName = getWelcomeLoungeTemplateName()
local template, roomAnchor, doorSpawn, entryWalkTarget = buildTemplate(templateName, publicRoomTemplates)

print(TOOL_PREFIX .. " Created detailed template: " .. template:GetFullName())
print(string.format(
	"%s Grid: %dx%d tiles, TileSize=%d, FloorSize=(%.1f, %.1f, %.1f)",
	TOOL_PREFIX,
	GRID_WIDTH,
	GRID_DEPTH,
	TILE_SIZE,
	FLOOR_SIZE.X,
	FLOOR_SIZE.Y,
	FLOOR_SIZE.Z
))
print(TOOL_PREFIX .. " DoorSpawn position: " .. tostring(doorSpawn.Position))
print(TOOL_PREFIX .. " EntryWalkTarget position: " .. tostring(entryWalkTarget.Position))
print(TOOL_PREFIX .. " RoomAnchor position: " .. tostring(roomAnchor.Position))
print(TOOL_PREFIX .. " Entrance lane kept clear from DoorSpawn to EntryWalkTarget to the main floor.")
print(TOOL_PREFIX .. " Next: run docs/tools/ValidatePublicRoomTemplates.lua, then test Welcome Lounge from the Room Navigator.")
