-- Studio helper: create a placeholder 3D hotel lobby scene for the future main menu cinematic.
--
-- Run this manually in Roblox Studio Command Bar or from a temporary Script.
-- The helper creates ReplicatedStorage.MainMenuScenes.HotelLobbyMainMenu.
-- Camera markers are visible for setup and can be manually moved/rotated after generation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TOOL_PREFIX = "[CreateMainMenuHotelLobbyScene]"
local REPLACE_EXISTING = true

local SCENE_FOLDER_NAME = "MainMenuScenes"
local SCENE_NAME = "HotelLobbyMainMenu"

local COLORS = {
	Floor = Color3.fromRGB(176, 168, 152),
	FloorTrim = Color3.fromRGB(112, 102, 88),
	Runner = Color3.fromRGB(116, 54, 48),
	RunnerTrim = Color3.fromRGB(190, 152, 82),
	Wall = Color3.fromRGB(211, 202, 184),
	WallPanel = Color3.fromRGB(151, 124, 91),
	DarkWood = Color3.fromRGB(82, 56, 39),
	Wood = Color3.fromRGB(126, 83, 50),
	WoodLight = Color3.fromRGB(164, 112, 67),
	Door = Color3.fromRGB(94, 56, 36),
	Gold = Color3.fromRGB(222, 178, 88),
	Paper = Color3.fromRGB(244, 232, 198),
	PaperInk = Color3.fromRGB(64, 56, 47),
	Plant = Color3.fromRGB(58, 118, 66),
	PlantDark = Color3.fromRGB(37, 78, 45),
	Pot = Color3.fromRGB(112, 70, 50),
	Chair = Color3.fromRGB(68, 91, 112),
	ChairTrim = Color3.fromRGB(45, 58, 74),
	Light = Color3.fromRGB(255, 227, 165),
	MarkerAnchor = Color3.fromRGB(230, 230, 230),
	MarkerStart = Color3.fromRGB(88, 185, 255),
	MarkerConcierge = Color3.fromRGB(255, 198, 78),
	MarkerNavigator = Color3.fromRGB(95, 220, 140),
	MarkerWork = Color3.fromRGB(210, 120, 255),
	MarkerTarget = Color3.fromRGB(255, 245, 120),
}

local function cframeLookAt(position, target)
	return CFrame.lookAt(position, target)
end

local function setDecorativeDefaults(instance)
	if not instance:IsA("BasePart") then
		return
	end

	instance.Anchored = true
	instance.CanCollide = false
	instance.CanTouch = false
	instance.CanQuery = false
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
end

local function createPart(parent, name, size, cframe, color, material, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	setDecorativeDefaults(part)
	part.Parent = parent
	return part
end

local function createCylinder(parent, name, size, cframe, color, material, transparency)
	local part = createPart(parent, name, size, cframe, color, material, transparency)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function createBall(parent, name, size, cframe, color, material, transparency)
	local part = createPart(parent, name, size, cframe, color, material, transparency)
	part.Shape = Enum.PartType.Ball
	return part
end

local function addSurfaceText(part, text, face, textColor, backgroundTransparency)
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "SurfaceText"
	surfaceGui.Face = face or Enum.NormalId.Front
	surfaceGui.CanvasSize = Vector2.new(700, 260)
	surfaceGui.AlwaysOnTop = false
	surfaceGui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = backgroundTransparency or 1
	label.Text = text
	label.TextColor3 = textColor or Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = surfaceGui

	return surfaceGui
end

local function addBillboardLabel(part, text)
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "MarkerLabel"
	billboardGui.Adornee = part
	billboardGui.AlwaysOnTop = true
	billboardGui.Size = UDim2.fromOffset(180, 38)
	billboardGui.StudsOffset = Vector3.new(0, 1.45, 0)
	billboardGui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.25
	label.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextSize = 13
	label.Font = Enum.Font.GothamBold
	label.Parent = billboardGui
end

local function createMarker(parent, name, cframe, color)
	local marker = createPart(
		parent,
		name,
		Vector3.new(1.4, 1.4, 1.4),
		cframe,
		color,
		Enum.Material.Neon,
		0.5
	)
	marker:SetAttribute("MainMenuSceneMarker", true)
	marker:SetAttribute("MarkerCFrame", tostring(cframe))
	addBillboardLabel(marker, name)
	return marker
end

local function createTargetMarker(parent, name, position)
	local marker = createPart(
		parent,
		name,
		Vector3.new(0.7, 0.7, 0.7),
		CFrame.new(position),
		COLORS.MarkerTarget,
		Enum.Material.Neon,
		0.45
	)
	marker:SetAttribute("MainMenuSceneMarker", true)
	marker:SetAttribute("DeskPaperTarget", true)
	addBillboardLabel(marker, name)
	return marker
end

local function createPointLightFixture(parent, name, position, color, brightness, range)
	local fixture = createCylinder(
		parent,
		name,
		Vector3.new(2.2, 0.25, 2.2),
		CFrame.new(position),
		color,
		Enum.Material.Neon,
		0
	)

	local light = Instance.new("PointLight")
	light.Name = "WarmPointLight"
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = fixture

	return fixture
end

local function createSurfaceLightFixture(parent, name, position, size, color, brightness, range)
	local fixture = createPart(
		parent,
		name,
		size,
		CFrame.new(position),
		color,
		Enum.Material.Neon,
		0
	)

	local light = Instance.new("SurfaceLight")
	light.Name = "WarmSurfaceLight"
	light.Face = Enum.NormalId.Bottom
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = fixture

	return fixture
end

local function createChair(parent, name, position, yaw)
	local chair = Instance.new("Model")
	chair.Name = name
	chair.Parent = parent

	local base = CFrame.new(position) * CFrame.Angles(0, yaw or 0, 0)
	createPart(chair, "Seat", Vector3.new(3, 0.45, 2.5), base * CFrame.new(0, 1.15, 0), COLORS.Chair, Enum.Material.Fabric, 0)
	createPart(chair, "Back", Vector3.new(3, 2.8, 0.45), base * CFrame.new(0, 2.25, 1.05), COLORS.ChairTrim, Enum.Material.Fabric, 0)

	for x = -1, 1, 2 do
		for z = -1, 1, 2 do
			createPart(
				chair,
				"Leg",
				Vector3.new(0.25, 1.2, 0.25),
				base * CFrame.new(x * 1.1, 0.5, z * 0.85),
				COLORS.DarkWood,
				Enum.Material.Wood,
				0
			)
		end
	end

	return chair
end

local function createCoffeeTable(parent, name, position)
	local tableModel = Instance.new("Model")
	tableModel.Name = name
	tableModel.Parent = parent

	createPart(tableModel, "Top", Vector3.new(6, 0.35, 3), CFrame.new(position + Vector3.new(0, 1.55, 0)), COLORS.WoodLight, Enum.Material.Wood, 0)

	for x = -1, 1, 2 do
		for z = -1, 1, 2 do
			createPart(
				tableModel,
				"Leg",
				Vector3.new(0.28, 1.4, 0.28),
				CFrame.new(position + Vector3.new(x * 2.45, 0.75, z * 1.05)),
				COLORS.DarkWood,
				Enum.Material.Wood,
				0
			)
		end
	end

	createPart(tableModel, "Magazine", Vector3.new(2.1, 0.06, 1.25), CFrame.new(position + Vector3.new(-1.2, 1.77, 0.15)), COLORS.Paper, Enum.Material.SmoothPlastic, 0)
	createPart(tableModel, "Cup", Vector3.new(0.55, 0.45, 0.55), CFrame.new(position + Vector3.new(1.5, 1.9, -0.35)), Color3.fromRGB(235, 228, 210), Enum.Material.SmoothPlastic, 0)

	return tableModel
end

local function createPlant(parent, name, position)
	local plant = Instance.new("Model")
	plant.Name = name
	plant.Parent = parent

	createCylinder(plant, "Pot", Vector3.new(1.7, 1.5, 1.7), CFrame.new(position + Vector3.new(0, 0.75, 0)), COLORS.Pot, Enum.Material.SmoothPlastic, 0)
	createPart(plant, "Stem", Vector3.new(0.25, 2.4, 0.25), CFrame.new(position + Vector3.new(0, 2.25, 0)), COLORS.PlantDark, Enum.Material.SmoothPlastic, 0)

	local leafOffsets = {
		Vector3.new(0, 3.25, 0),
		Vector3.new(0.75, 2.9, 0.2),
		Vector3.new(-0.7, 2.85, -0.15),
		Vector3.new(0.15, 2.8, 0.75),
		Vector3.new(-0.15, 2.95, -0.7),
	}

	for index, offset in ipairs(leafOffsets) do
		createBall(
			plant,
			"Leaf_" .. string.format("%02d", index),
			Vector3.new(1.35, 0.65, 1.0),
			CFrame.new(position + offset),
			index % 2 == 0 and COLORS.Plant or COLORS.PlantDark,
			Enum.Material.SmoothPlastic,
			0
		)
	end

	return plant
end

local function createNpc(parent, name, position, yaw, bodyColor, accentColor)
	local npc = Instance.new("Model")
	npc.Name = name
	npc.Parent = parent

	local base = CFrame.new(position) * CFrame.Angles(0, yaw or 0, 0)
	local torsoColor = bodyColor or Color3.fromRGB(54, 73, 91)
	local limbColor = accentColor or Color3.fromRGB(42, 48, 54)
	local skinColor = Color3.fromRGB(210, 172, 132)

	createPart(npc, "Torso", Vector3.new(1.15, 1.45, 0.55), base * CFrame.new(0, 2.35, 0), torsoColor, Enum.Material.SmoothPlastic, 0)
	createBall(npc, "Head", Vector3.new(0.78, 0.78, 0.78), base * CFrame.new(0, 3.5, 0), skinColor, Enum.Material.SmoothPlastic, 0)
	createPart(npc, "LeftArm", Vector3.new(0.32, 1.25, 0.32), base * CFrame.new(-0.82, 2.35, 0), limbColor, Enum.Material.SmoothPlastic, 0)
	createPart(npc, "RightArm", Vector3.new(0.32, 1.25, 0.32), base * CFrame.new(0.82, 2.35, 0), limbColor, Enum.Material.SmoothPlastic, 0)
	createPart(npc, "LeftLeg", Vector3.new(0.36, 1.35, 0.36), base * CFrame.new(-0.32, 0.9, 0), limbColor, Enum.Material.SmoothPlastic, 0)
	createPart(npc, "RightLeg", Vector3.new(0.36, 1.35, 0.36), base * CFrame.new(0.32, 0.9, 0), limbColor, Enum.Material.SmoothPlastic, 0)
	createPart(npc, "Hair", Vector3.new(0.78, 0.2, 0.7), base * CFrame.new(0, 3.96, -0.02), Color3.fromRGB(43, 31, 25), Enum.Material.SmoothPlastic, 0)

	npc:SetAttribute("MainMenuNPC", true)
	npc:SetAttribute("AmbientMovementPlaceholder", name ~= "ConciergeNPC")

	return npc
end

local sceneFolder = ReplicatedStorage:FindFirstChild(SCENE_FOLDER_NAME)

if not sceneFolder then
	sceneFolder = Instance.new("Folder")
	sceneFolder.Name = SCENE_FOLDER_NAME
	sceneFolder.Parent = ReplicatedStorage
elseif not sceneFolder:IsA("Folder") then
	error(TOOL_PREFIX .. " ReplicatedStorage." .. SCENE_FOLDER_NAME .. " exists but is not a Folder.")
end

local existingScene = sceneFolder:FindFirstChild(SCENE_NAME)

if existingScene then
	if REPLACE_EXISTING then
		existingScene:Destroy()
	else
		error(TOOL_PREFIX .. " " .. SCENE_NAME .. " already exists. Set REPLACE_EXISTING = true to rebuild.")
	end
end

local scene = Instance.new("Model")
scene.Name = SCENE_NAME
scene:SetAttribute("GeneratedBy", "CreateMainMenuHotelLobbyScene")
scene:SetAttribute("RuntimeImplemented", false)
scene.Parent = sceneFolder

local mainMenuAnchor = createMarker(scene, "MainMenuAnchor", CFrame.new(0, 1.2, 0), COLORS.MarkerAnchor)
scene.PrimaryPart = mainMenuAnchor

local navigatorPaperTargetPosition = Vector3.new(10.5, 4.25, -21.6)
local workPaperTargetPosition = Vector3.new(-10.5, 4.25, -21.6)

-- Camera markers use full CFrame orientation. Move and rotate these markers manually
-- after generation to tune the cinematic camera path. The desk views are in front of
-- the concierge desk and look down at the paper targets, not at the concierge NPC.
local cameraStart = createMarker(
	scene,
	"CameraStart",
	cframeLookAt(Vector3.new(0, 7.2, 45), Vector3.new(0, 4.1, -24)),
	COLORS.MarkerStart
)
local cameraConcierge = createMarker(
	scene,
	"CameraConcierge",
	cframeLookAt(Vector3.new(0, 6.6, 12), Vector3.new(0, 4.2, -22.2)),
	COLORS.MarkerConcierge
)
local cameraNavigatorDesk = createMarker(
	scene,
	"CameraNavigatorDesk",
	cframeLookAt(Vector3.new(13.5, 7.25, -11.5), navigatorPaperTargetPosition),
	COLORS.MarkerNavigator
)
local cameraWorkDesk = createMarker(
	scene,
	"CameraWorkDesk",
	cframeLookAt(Vector3.new(-13.5, 7.25, -11.5), workPaperTargetPosition),
	COLORS.MarkerWork
)
local navigatorPaperTarget = createTargetMarker(scene, "NavigatorPaperTarget", navigatorPaperTargetPosition)
local workPaperTarget = createTargetMarker(scene, "WorkPaperTarget", workPaperTargetPosition)

local floorModel = Instance.new("Model")
floorModel.Name = "Floor"
floorModel.Parent = scene

createPart(floorModel, "LobbyFloor", Vector3.new(88, 0.4, 78), CFrame.new(0, 0, 0), COLORS.Floor, Enum.Material.Slate, 0)
createPart(floorModel, "EntrancePath", Vector3.new(14, 0.08, 62), CFrame.new(0, 0.26, 8), COLORS.Runner, Enum.Material.Fabric, 0)
createPart(floorModel, "EntrancePathGoldLeft", Vector3.new(0.35, 0.1, 62), CFrame.new(-7.4, 0.32, 8), COLORS.RunnerTrim, Enum.Material.Metal, 0)
createPart(floorModel, "EntrancePathGoldRight", Vector3.new(0.35, 0.1, 62), CFrame.new(7.4, 0.32, 8), COLORS.RunnerTrim, Enum.Material.Metal, 0)

for x = -36, 36, 12 do
	createPart(floorModel, "FloorTileLineX", Vector3.new(0.08, 0.07, 78), CFrame.new(x, 0.33, 0), COLORS.FloorTrim, Enum.Material.SmoothPlastic, 0.55)
end

for z = -30, 30, 12 do
	createPart(floorModel, "FloorTileLineZ", Vector3.new(88, 0.07, 0.08), CFrame.new(0, 0.34, z), COLORS.FloorTrim, Enum.Material.SmoothPlastic, 0.55)
end

local props = Instance.new("Folder")
props.Name = "Props"
props.Parent = scene

createPart(props, "BackWall", Vector3.new(88, 12, 1), CFrame.new(0, 6, -38.5), COLORS.Wall, Enum.Material.SmoothPlastic, 0)
createPart(props, "LeftWall", Vector3.new(1, 10, 78), CFrame.new(-44.5, 5, 0), COLORS.Wall, Enum.Material.SmoothPlastic, 0)
createPart(props, "RightWall", Vector3.new(1, 10, 78), CFrame.new(44.5, 5, 0), COLORS.Wall, Enum.Material.SmoothPlastic, 0)
createPart(props, "EntranceFrameTop", Vector3.new(24, 2, 1), CFrame.new(0, 9.5, 38.5), COLORS.WallPanel, Enum.Material.SmoothPlastic, 0)
createPart(props, "EntranceFrameLeft", Vector3.new(2, 9, 1), CFrame.new(-13, 4.5, 38.5), COLORS.WallPanel, Enum.Material.SmoothPlastic, 0)
createPart(props, "EntranceFrameRight", Vector3.new(2, 9, 1), CFrame.new(13, 4.5, 38.5), COLORS.WallPanel, Enum.Material.SmoothPlastic, 0)

local hotelSign = createPart(props, "HotelSign", Vector3.new(20, 3, 0.25), CFrame.new(0, 9.2, -37.85), COLORS.DarkWood, Enum.Material.Wood, 0)
addSurfaceText(hotelSign, "HOTEL", Enum.NormalId.Front, COLORS.Gold)

for x = -32, 32, 16 do
	createPart(props, "WallPanel", Vector3.new(8, 5.5, 0.18), CFrame.new(x, 4.8, -37.75), COLORS.WallPanel, Enum.Material.Wood, 0.15)
end

for x = -34, 34, 68 do
	createCylinder(props, "LobbyColumn", Vector3.new(2.2, 10, 2.2), CFrame.new(x, 5, -22), COLORS.WallPanel, Enum.Material.SmoothPlastic, 0)
	createCylinder(props, "LobbyColumnBase", Vector3.new(3.2, 0.7, 3.2), CFrame.new(x, 0.55, -22), COLORS.DarkWood, Enum.Material.Wood, 0)
	createCylinder(props, "LobbyColumnCap", Vector3.new(3.2, 0.7, 3.2), CFrame.new(x, 9.45, -22), COLORS.DarkWood, Enum.Material.Wood, 0)
end

createPlant(props, "Plant_LeftEntrance", Vector3.new(-36, 0.2, 29))
createPlant(props, "Plant_RightEntrance", Vector3.new(36, 0.2, 29))
createPlant(props, "Plant_LeftDesk", Vector3.new(-30, 0.2, -28))
createPlant(props, "Plant_RightDesk", Vector3.new(30, 0.2, -28))

local entrance = Instance.new("Model")
entrance.Name = "Entrance"
entrance.Parent = scene

-- Door panels and open-position markers are used by MainMenuCameraClient for
-- the first-time onboarding check-in intro. Adjust the closed panels or marker
-- CFrames in Studio if you retune the entrance camera path.
local entranceDoorLeft = createPart(
	entrance,
	"EntranceDoorLeft",
	Vector3.new(5.8, 7.2, 0.35),
	CFrame.new(-2.95, 3.75, 38.05),
	COLORS.Door,
	Enum.Material.Wood,
	0
)
local entranceDoorRight = createPart(
	entrance,
	"EntranceDoorRight",
	Vector3.new(5.8, 7.2, 0.35),
	CFrame.new(2.95, 3.75, 38.05),
	COLORS.Door,
	Enum.Material.Wood,
	0
)

local entranceDoorLeftOpen = createPart(
	entrance,
	"EntranceDoorLeftOpen",
	Vector3.new(1, 1, 1),
	CFrame.new(-7.2, 3.75, 36.35) * CFrame.Angles(0, math.rad(-72), 0),
	COLORS.MarkerTarget,
	Enum.Material.Neon,
	1
)
local entranceDoorRightOpen = createPart(
	entrance,
	"EntranceDoorRightOpen",
	Vector3.new(1, 1, 1),
	CFrame.new(7.2, 3.75, 36.35) * CFrame.Angles(0, math.rad(72), 0),
	COLORS.MarkerTarget,
	Enum.Material.Neon,
	1
)
local doorOpenFocus = createPart(
	entrance,
	"DoorOpenFocus",
	Vector3.new(0.8, 0.8, 0.8),
	CFrame.new(0, 4.1, 34),
	COLORS.MarkerTarget,
	Enum.Material.Neon,
	1
)

entranceDoorLeft:SetAttribute("AnimatedEntranceDoor", true)
entranceDoorRight:SetAttribute("AnimatedEntranceDoor", true)
entranceDoorLeftOpen:SetAttribute("MainMenuSceneMarker", true)
entranceDoorRightOpen:SetAttribute("MainMenuSceneMarker", true)
doorOpenFocus:SetAttribute("MainMenuSceneMarker", true)

local desk = Instance.new("Model")
desk.Name = "Desk"
desk.Parent = scene

createPart(desk, "ConciergeDeskFront", Vector3.new(30, 3.4, 3.2), CFrame.new(0, 1.9, -24), COLORS.Wood, Enum.Material.Wood, 0)
createPart(desk, "ConciergeDeskTop", Vector3.new(32, 0.45, 5), CFrame.new(0, 3.85, -24), COLORS.WoodLight, Enum.Material.Wood, 0)
createPart(desk, "ConciergeDeskLeftReturn", Vector3.new(3.2, 3.2, 8), CFrame.new(-16.4, 1.8, -27.2), COLORS.Wood, Enum.Material.Wood, 0)
createPart(desk, "ConciergeDeskRightReturn", Vector3.new(3.2, 3.2, 8), CFrame.new(16.4, 1.8, -27.2), COLORS.Wood, Enum.Material.Wood, 0)

local conciergeSign = createPart(desk, "ConciergeSign", Vector3.new(16, 1.5, 0.18), CFrame.new(0, 3.05, -21.88), COLORS.DarkWood, Enum.Material.Wood, 0)
addSurfaceText(conciergeSign, "CONCIERGE", Enum.NormalId.Front, COLORS.Gold)

local navigatorPaper = createPart(desk, "NavigatorPaperPlaceholder", Vector3.new(9, 0.08, 6), CFrame.new(10.5, 4.12, -21.6) * CFrame.Angles(0, math.rad(-8), 0), COLORS.Paper, Enum.Material.SmoothPlastic, 0)
addSurfaceText(navigatorPaper, "Navigator", Enum.NormalId.Top, COLORS.PaperInk)

local workPaper = createPart(desk, "WorkPaperPlaceholder", Vector3.new(9, 0.08, 6), CFrame.new(-10.5, 4.12, -21.6) * CFrame.Angles(0, math.rad(8), 0), COLORS.Paper, Enum.Material.SmoothPlastic, 0)
addSurfaceText(workPaper, "Work", Enum.NormalId.Top, COLORS.PaperInk)

createPointLightFixture(desk, "DeskLamp_Left", Vector3.new(-10.5, 4.85, -22.2), COLORS.Light, 1.2, 16)
createPointLightFixture(desk, "DeskLamp_Right", Vector3.new(10.5, 4.85, -22.2), COLORS.Light, 1.2, 16)

local seating = Instance.new("Model")
seating.Name = "Seating"
seating.Parent = scene

createChair(seating, "LeftLoungeChair_01", Vector3.new(-30, 0, 10), math.rad(35))
createChair(seating, "LeftLoungeChair_02", Vector3.new(-20, 0, 4), math.rad(-30))
createChair(seating, "LeftLoungeChair_03", Vector3.new(-33, 0, -4), math.rad(80))
createChair(seating, "RightLoungeChair_01", Vector3.new(30, 0, 10), math.rad(-35))
createChair(seating, "RightLoungeChair_02", Vector3.new(20, 0, 4), math.rad(30))
createChair(seating, "RightLoungeChair_03", Vector3.new(33, 0, -4), math.rad(-80))

local coffeeTables = Instance.new("Model")
coffeeTables.Name = "CoffeeTables"
coffeeTables.Parent = scene

createCoffeeTable(coffeeTables, "LeftCoffeeTable", Vector3.new(-26, 0, 4))
createCoffeeTable(coffeeTables, "RightCoffeeTable", Vector3.new(26, 0, 4))

local lighting = Instance.new("Folder")
lighting.Name = "Lighting"
lighting.Parent = scene

createSurfaceLightFixture(lighting, "CeilingLight_Entrance", Vector3.new(0, 9.8, 28), Vector3.new(11, 0.25, 4), COLORS.Light, 1.4, 24)
createSurfaceLightFixture(lighting, "CeilingLight_Lobby", Vector3.new(0, 9.8, 2), Vector3.new(14, 0.25, 5), COLORS.Light, 1.8, 30)
createSurfaceLightFixture(lighting, "CeilingLight_Desk", Vector3.new(0, 9.8, -24), Vector3.new(16, 0.25, 5), COLORS.Light, 2.0, 34)
createPointLightFixture(lighting, "WallLamp_Left", Vector3.new(-40.5, 5.2, -9), COLORS.Light, 1.0, 18)
createPointLightFixture(lighting, "WallLamp_Right", Vector3.new(40.5, 5.2, -9), COLORS.Light, 1.0, 18)

local conciergeNpc = createNpc(scene, "ConciergeNPC", Vector3.new(0, 0.4, -29.2), math.rad(180), Color3.fromRGB(36, 46, 56), COLORS.Gold)
conciergeNpc:SetAttribute("Role", "Concierge")

local ambientNpcs = Instance.new("Folder")
ambientNpcs.Name = "AmbientNPCs"
ambientNpcs.Parent = scene

local ambientNpcPositions = {
	Vector3.new(-34, 0.4, 22), Vector3.new(-26, 0.4, 18), Vector3.new(-18, 0.4, 15),
	Vector3.new(34, 0.4, 22), Vector3.new(26, 0.4, 18), Vector3.new(18, 0.4, 15),
	Vector3.new(-36, 0.4, 4), Vector3.new(-28, 0.4, -2), Vector3.new(-20, 0.4, -9),
	Vector3.new(36, 0.4, 4), Vector3.new(28, 0.4, -2), Vector3.new(20, 0.4, -9),
	Vector3.new(-38, 0.4, -18), Vector3.new(-28, 0.4, -22), Vector3.new(-17, 0.4, -31),
	Vector3.new(38, 0.4, -18), Vector3.new(28, 0.4, -22), Vector3.new(17, 0.4, -31),
	Vector3.new(-10, 0.4, 26), Vector3.new(10, 0.4, 26), Vector3.new(-7, 0.4, 9),
	Vector3.new(7, 0.4, 9), Vector3.new(-12, 0.4, -8), Vector3.new(12, 0.4, -8),
}

local npcPalette = {
	Color3.fromRGB(67, 91, 110),
	Color3.fromRGB(95, 70, 104),
	Color3.fromRGB(90, 102, 70),
	Color3.fromRGB(116, 80, 62),
}

for index, position in ipairs(ambientNpcPositions) do
	local yaw = math.rad((index * 37) % 360)
	local bodyColor = npcPalette[((index - 1) % #npcPalette) + 1]
	local accentColor = Color3.fromRGB(42 + (index % 3) * 16, 48 + (index % 4) * 10, 56 + (index % 5) * 8)

	createNpc(
		ambientNpcs,
		"AmbientNPC_" .. string.format("%02d", index),
		position,
		yaw,
		bodyColor,
		accentColor
	)
end

print(TOOL_PREFIX .. " Created ReplicatedStorage." .. SCENE_FOLDER_NAME .. "." .. SCENE_NAME)
print(TOOL_PREFIX .. " Markers: MainMenuAnchor, CameraStart, CameraConcierge, CameraNavigatorDesk, CameraWorkDesk")
print(TOOL_PREFIX .. " Entrance doors: Entrance.EntranceDoorLeft/Right with EntranceDoorLeftOpen/RightOpen markers")
print(TOOL_PREFIX .. " Desk targets: NavigatorPaperTarget=" .. tostring(navigatorPaperTarget.Position) .. ", WorkPaperTarget=" .. tostring(workPaperTarget.Position))
print(TOOL_PREFIX .. " CameraStart=" .. tostring(cameraStart.Position))
print(TOOL_PREFIX .. " CameraConcierge=" .. tostring(cameraConcierge.Position))
print(TOOL_PREFIX .. " CameraNavigatorDesk=" .. tostring(cameraNavigatorDesk.Position))
print(TOOL_PREFIX .. " CameraWorkDesk=" .. tostring(cameraWorkDesk.Position))
print(TOOL_PREFIX .. " Runtime cinematic camera uses these markers when the template is cloned locally.")
