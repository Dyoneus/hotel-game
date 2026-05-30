-- Studio helper: create a functional placeholder Cafe public room template.
--
-- Run this manually in Roblox Studio Command Bar or from a temporary Script.
-- The helper creates ReplicatedStorage.PublicRoomTemplates.Public_Cafe
-- or the TemplateName configured for Cafe in PublicRoomConfig.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TOOL_PREFIX = "[CreateCafeTemplate]"
local REPLACE_EXISTING = true

local PUBLIC_ROOM_ID = "Cafe"
local FALLBACK_TEMPLATE_NAME = "Public_Cafe"

local TILE_SIZE = 4
local GRID_WIDTH = 14
local GRID_DEPTH = 10
local FLOOR_SIZE = Vector3.new(GRID_WIDTH * TILE_SIZE, 0.5, GRID_DEPTH * TILE_SIZE)
local FLOOR_TOP_Y = FLOOR_SIZE.Y / 2
local MARKER_Y = FLOOR_TOP_Y + 2.75
local WALL_HEIGHT = 7
local WALL_THICKNESS = 1

local COLORS = {
	Floor = Color3.fromRGB(194, 183, 164),
	FloorAccent = Color3.fromRGB(160, 129, 104),
	Wall = Color3.fromRGB(221, 211, 190),
	WallPanel = Color3.fromRGB(176, 153, 124),
	Trim = Color3.fromRGB(112, 78, 52),
	DarkTrim = Color3.fromRGB(65, 47, 35),
	Counter = Color3.fromRGB(126, 82, 50),
	CounterTop = Color3.fromRGB(178, 129, 84),
	MenuBoard = Color3.fromRGB(52, 76, 69),
	Table = Color3.fromRGB(126, 86, 55),
	Plant = Color3.fromRGB(66, 132, 77),
	Pot = Color3.fromRGB(122, 76, 52),
	Chair = Color3.fromRGB(132, 93, 68),
	ChairTrim = Color3.fromRGB(78, 55, 42),
	Light = Color3.fromRGB(255, 232, 188),
	LightWarm = Color3.fromRGB(255, 218, 164),
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
	light.Name = name or "WarmPointLight"
	light.Color = color or COLORS.Light
	light.Brightness = brightness or 0.55
	light.Range = range or 12
	light.Shadows = false
	light.Parent = parentPart

	return light
end

local function createSurfaceLight(parentPart, face, color, brightness, range)
	local light = Instance.new("SurfaceLight")
	light.Name = "WarmSurfaceLight"
	light.Color = color or COLORS.Light
	light.Face = face or Enum.NormalId.Bottom
	light.Brightness = brightness or 0.8
	light.Range = range or 12
	light.Shadows = false
	light.Parent = parentPart

	return light
end

local function createHangingLight(parent, name, x, z, color, brightness, range)
	local fixture = Instance.new("Model")
	fixture.Name = name
	fixture.Parent = parent

	createVisualPart(
		fixture,
		"Cord",
		Vector3.new(0.16, 1.45, 0.16),
		CFrame.new(x, FLOOR_TOP_Y + 6.05, z),
		COLORS.DarkTrim,
		Enum.Material.Metal
	)

	createVisualPart(
		fixture,
		"Shade",
		Vector3.new(1.9, 0.42, 1.9),
		CFrame.new(x, FLOOR_TOP_Y + 5.25, z),
		COLORS.Trim,
		Enum.Material.Metal
	)

	local glow = createVisualPart(
		fixture,
		"Glow",
		Vector3.new(1.45, 0.18, 1.45),
		CFrame.new(x, FLOOR_TOP_Y + 5.02, z),
		color or COLORS.Light,
		Enum.Material.Neon
	)
	createPointLight(glow, "PendantPointLight", color or COLORS.Light, brightness or 0.65, range or 13)
	createSurfaceLight(glow, Enum.NormalId.Bottom, color or COLORS.Light, (brightness or 0.65) * 1.15, range or 13)

	return fixture
end

local function createPlant(parent, name, x, z)
	local plant = Instance.new("Model")
	plant.Name = name
	plant.Parent = parent

	createDecorPart(plant, "Pot", Vector3.new(2, 1.1, 2), CFrame.new(x, FLOOR_TOP_Y + 0.55, z), COLORS.Pot, true)

	local leaves = createVisualPart(plant, "Leaves", Vector3.new(2.8, 2.8, 2.8), CFrame.new(x, FLOOR_TOP_Y + 2.35, z), COLORS.Plant, Enum.Material.Grass)
	leaves.Shape = Enum.PartType.Ball

	return plant
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
	createWall(wallsFolder, "FrontWallLeft", Vector3.new(20, WALL_HEIGHT, WALL_THICKNESS), CFrame.new(-18, wallY, frontZ))
	createWall(wallsFolder, "FrontWallRight", Vector3.new(24, WALL_HEIGHT, WALL_THICKNESS), CFrame.new(16, wallY, frontZ))

	createVisualPart(wallsFolder, "DoorwayHeader", Vector3.new(12, 1.2, WALL_THICKNESS + 0.1), CFrame.new(-2, FLOOR_TOP_Y + 6.4, frontZ), COLORS.Trim)
	createDecorPart(wallsFolder, "DoorwayLeftPillar", Vector3.new(1.2, 6, 1.2), CFrame.new(-8.2, FLOOR_TOP_Y + 3, frontZ), COLORS.Trim, true)
	createDecorPart(wallsFolder, "DoorwayRightPillar", Vector3.new(1.2, 6, 1.2), CFrame.new(4.2, FLOOR_TOP_Y + 3, frontZ), COLORS.Trim, true)

	for _, x in ipairs({ -18, -6, 10, 22 }) do
		createVisualPart(wallsFolder, "BackWallPanel", Vector3.new(7, 3.8, 0.14), CFrame.new(x, FLOOR_TOP_Y + 4, backZ - 0.6), COLORS.WallPanel)
	end

	return wallsFolder
end

local function buildDecorativeFloor(roomFolder)
	local decorativeFloor = Instance.new("Folder")
	decorativeFloor.Name = "DecorativeFloor"
	decorativeFloor.Parent = roomFolder

	createWalkableFloorDecoration(decorativeFloor, "EntranceMat", Vector3.new(10, 0.08, 5), CFrame.new(-2, FLOOR_TOP_Y + 0.06, -17), COLORS.FloorAccent, Enum.Material.Fabric)
	createWalkableFloorDecoration(decorativeFloor, "CentralRunner", Vector3.new(8, 0.06, 24), CFrame.new(-2, FLOOR_TOP_Y + 0.05, -3), Color3.fromRGB(147, 111, 91), Enum.Material.Fabric)
	createWalkableFloorDecoration(decorativeFloor, "DiningRugLeft", Vector3.new(18, 0.05, 14), CFrame.new(-18, FLOOR_TOP_Y + 0.04, 1), Color3.fromRGB(133, 154, 127), Enum.Material.Fabric)
	createWalkableFloorDecoration(decorativeFloor, "DiningRugRight", Vector3.new(18, 0.05, 14), CFrame.new(18, FLOOR_TOP_Y + 0.04, 1), Color3.fromRGB(133, 154, 127), Enum.Material.Fabric)

	return decorativeFloor
end

local function anchorModelParts(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

local function findFurnitureTemplate(templateName)
	local furnitureTemplates = ReplicatedStorage:FindFirstChild("FurnitureTemplates")

	if not furnitureTemplates then
		return nil
	end

	return furnitureTemplates:FindFirstChild(templateName)
end

local function createPlaceholderChair(parent, name, cframe)
	local chair = Instance.new("Model")
	chair.Name = name
	chair.Parent = parent

	createDecorPart(chair, "Seat", Vector3.new(2.4, 0.4, 2.2), cframe * CFrame.new(0, FLOOR_TOP_Y + 0.45, 0), COLORS.Chair, true)
	createDecorPart(chair, "Back", Vector3.new(2.4, 2, 0.35), cframe * CFrame.new(0, FLOOR_TOP_Y + 1.35, 0.95), COLORS.ChairTrim, true)

	return chair
end

local function placeTemplateOrPlaceholder(parent, template, name, cframe, placeholderFactory)
	if template and (template:IsA("Model") or template:IsA("BasePart")) then
		local clone = template:Clone()
		clone.Name = name
		clone.Parent = parent

		if clone:IsA("Model") then
			anchorModelParts(clone)
			clone:PivotTo(cframe)
		else
			clone.Anchored = true
			clone.CFrame = cframe
		end

		return clone
	end

	return placeholderFactory(parent, name, cframe)
end

local function createPlaceholderTable(parent, name, cframe)
	local tableModel = Instance.new("Model")
	tableModel.Name = name
	tableModel.Parent = parent

	createDecorPart(tableModel, "Top", Vector3.new(4.2, 0.35, 4.2), cframe * CFrame.new(0, FLOOR_TOP_Y + 1.25, 0), COLORS.Table, true)
	createDecorPart(tableModel, "Base", Vector3.new(1.2, 1.2, 1.2), cframe * CFrame.new(0, FLOOR_TOP_Y + 0.55, 0), COLORS.DarkTrim, true)

	return tableModel
end

local function buildDecor(roomFolder)
	local decorFolder = Instance.new("Folder")
	decorFolder.Name = "Decor"
	decorFolder.Parent = roomFolder

	createDecorPart(decorFolder, "CafeCounter", Vector3.new(28, 2.2, 3.2), CFrame.new(-2, FLOOR_TOP_Y + 1.1, 16), COLORS.Counter, true)
	createDecorPart(decorFolder, "CounterTop", Vector3.new(29, 0.35, 4), CFrame.new(-2, FLOOR_TOP_Y + 2.35, 16), COLORS.CounterTop, true)
	createVisualPart(decorFolder, "MenuBoard", Vector3.new(19, 4, 0.25), CFrame.new(-2, FLOOR_TOP_Y + 4.2, 19.4), COLORS.MenuBoard)

	for index, x in ipairs({ -9, -3, 3 }) do
		createVisualPart(decorFolder, "MenuLine_" .. tostring(index), Vector3.new(4.5, 0.25, 0.18), CFrame.new(x, FLOOR_TOP_Y + 4.3, 19.2), COLORS.CounterTop)
	end

	createDecorPart(decorFolder, "PastryCase", Vector3.new(7, 1.6, 2.2), CFrame.new(18, FLOOR_TOP_Y + 0.8, 15.2), Color3.fromRGB(157, 117, 91), true)
	createVisualPart(decorFolder, "PastryGlass", Vector3.new(7.2, 1.2, 0.18), CFrame.new(18, FLOOR_TOP_Y + 1.7, 14.0), Color3.fromRGB(150, 204, 214), Enum.Material.Glass)

	createPlant(decorFolder, "Plant_FrontLeft", -24, -16)
	createPlant(decorFolder, "Plant_FrontRight", 24, -16)
	createPlant(decorFolder, "Plant_BackLeft", -24, 16)
	createPlant(decorFolder, "Plant_BackRight", 24, 16)

	createDecorPart(decorFolder, "LeftLowDivider", Vector3.new(1, 1.6, 12), CFrame.new(-10, FLOOR_TOP_Y + 0.8, -2), COLORS.Trim, true)
	createDecorPart(decorFolder, "RightLowDivider", Vector3.new(1, 1.6, 12), CFrame.new(10, FLOOR_TOP_Y + 0.8, -2), COLORS.Trim, true)

	for index, x in ipairs({ -14, -6, 2, 10 }) do
		createHangingLight(decorFolder, "CounterPendant_" .. tostring(index), x, 13.2, COLORS.LightWarm, 0.7, 13)
	end

	local tableLights = {
		{ Name = "TablePendant_LeftFront", X = -18, Z = -6 },
		{ Name = "TablePendant_RightFront", X = 18, Z = -6 },
		{ Name = "TablePendant_LeftBack", X = -18, Z = 6 },
		{ Name = "TablePendant_RightBack", X = 18, Z = 6 },
		{ Name = "CentralCafePendant", X = -2, Z = -3 },
	}

	for _, lightData in ipairs(tableLights) do
		createHangingLight(decorFolder, lightData.Name, lightData.X, lightData.Z, COLORS.Light, 0.6, 12)
	end

	return decorFolder
end

local function buildFurniture(template)
	local furnitureFolder = Instance.new("Folder")
	furnitureFolder.Name = "Furniture"
	furnitureFolder.Parent = template

	local chairTemplate = findFurnitureTemplate("Chair_01")
	local tableTemplate = findFurnitureTemplate("Table_01")

	if not chairTemplate then
		warn(TOOL_PREFIX .. " ReplicatedStorage.FurnitureTemplates.Chair_01 not found; using placeholder chairs without Sit support.")
	end

	local clusters = {
		{ X = -18, Z = -6 },
		{ X = 18, Z = -6 },
		{ X = -18, Z = 6 },
		{ X = 18, Z = 6 },
	}

	for index, cluster in ipairs(clusters) do
		local tableCFrame = CFrame.new(cluster.X, FLOOR_TOP_Y + 0.1, cluster.Z)
		placeTemplateOrPlaceholder(furnitureFolder, tableTemplate, "CafeTable_" .. tostring(index), tableCFrame, createPlaceholderTable)

		placeTemplateOrPlaceholder(
			furnitureFolder,
			chairTemplate,
			"CafeChair_" .. tostring(index) .. "_Left",
			CFrame.new(cluster.X - 4, FLOOR_TOP_Y + 0.1, cluster.Z) * CFrame.Angles(0, math.rad(90), 0),
			createPlaceholderChair
		)
		placeTemplateOrPlaceholder(
			furnitureFolder,
			chairTemplate,
			"CafeChair_" .. tostring(index) .. "_Right",
			CFrame.new(cluster.X + 4, FLOOR_TOP_Y + 0.1, cluster.Z) * CFrame.Angles(0, math.rad(-90), 0),
			createPlaceholderChair
		)
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
	template:SetAttribute("DisplayName", "Cafe")
	template:SetAttribute("RoomType", "PublicSpace")

	local roomAnchor = createMarker(template, "RoomAnchor", CFrame.new(0, 0, 0), false)
	local doorSpawn = createMarker(template, "DoorSpawn", CFrame.new(-2, MARKER_Y, -18), false)
	local entryWalkTarget = createMarker(template, "EntryWalkTarget", CFrame.new(-2, MARKER_Y, -14), false)
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

	local roomExitZone = createPart(roomFolder, "RoomExitZone", Vector3.new(10, 6, 3), CFrame.new(-2, FLOOR_TOP_Y + 3, -20.5), {
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
print(TOOL_PREFIX .. " Entrance lane kept clear from DoorSpawn to EntryWalkTarget to the central runner.")
print(TOOL_PREFIX .. " Next: run docs/tools/ValidatePublicRoomTemplates.lua, then test Cafe from the Room Navigator.")
