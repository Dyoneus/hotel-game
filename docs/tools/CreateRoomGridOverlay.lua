-- Studio helper: create tile-grid overlay parts for room templates.
--
-- Run this manually in Roblox Studio Command Bar or from a temporary Script.
-- Select one or more room template Models, or set ROOM_TEMPLATE_PATHS below.
-- The helper only creates/replaces EditorHelpers.RoomGridOverlay.

local Selection = game:GetService("Selection")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GridConfig = nil
local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
local gridConfigModule = sharedFolder and sharedFolder:FindFirstChild("GridConfig")

if gridConfigModule and gridConfigModule:IsA("ModuleScript") then
	local success, result = pcall(require, gridConfigModule)

	if success and typeof(result) == "table" then
		GridConfig = result
	end
end

local ROOM_TEMPLATE_PATHS = {
	-- Example fallback when nothing is selected:
	-- "ReplicatedStorage.RoomTemplates.Layout_01",
}

local TILE_SIZE_DEFAULT = GridConfig and GridConfig.TILE_SIZE or 4
local GRID_WIDTH_DEFAULT = GridConfig and GridConfig.DEFAULT_GRID_WIDTH or 5
local GRID_DEPTH_DEFAULT = GridConfig and GridConfig.DEFAULT_GRID_DEPTH or 7
local LINE_THICKNESS = 0.06
local LINE_HEIGHT = 0.04
local LINE_Y_OFFSET = 0.05
local CENTER_MARKER_SIZE = 0.28
local LINE_COLOR = Color3.fromRGB(130, 190, 255)
local CENTER_COLOR = Color3.fromRGB(255, 235, 140)
local TRANSPARENCY = 0.5
local CREATE_CENTER_MARKERS = true
local CREATE_AXIS_LABELS = true

local function resolvePath(path)
	local current = game

	for segment in string.gmatch(path, "[^%.]+") do
		current = current:FindFirstChild(segment)

		if not current then
			return nil
		end
	end

	return current
end

local function getPositiveNumberAttribute(instance, attributeName, fallback)
	local value = instance:GetAttribute(attributeName)

	if typeof(value) == "number" and value > 0 and value < math.huge then
		return value
	end

	return fallback
end

local function getPositiveIntegerAttribute(instance, attributeName, fallback)
	local value = getPositiveNumberAttribute(instance, attributeName, fallback)

	return math.max(1, math.floor(value + 0.5))
end

local function findWalkableFloor(roomTemplate)
	local roomFolder = roomTemplate:FindFirstChild("Room")
	local floor = roomFolder and roomFolder:FindFirstChild("WalkableFloor")

	if floor and floor:IsA("BasePart") then
		return floor
	end

	floor = roomTemplate:FindFirstChild("WalkableFloor", true)

	if floor and floor:IsA("BasePart") then
		return floor
	end

	return nil
end

local function makePart(name, parent, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = TRANSPARENCY
	part.Parent = parent

	return part
end

local function addLabel(name, parent, text, worldCFrame)
	local labelPart = makePart(name, parent, CENTER_COLOR)
	labelPart.Size = Vector3.new(0.1, 0.1, 0.1)
	labelPart.CFrame = worldCFrame
	labelPart.Transparency = 1

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(52, 18)
	billboard.AlwaysOnTop = true
	billboard.Parent = labelPart

	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.Text = text
	textLabel.TextColor3 = CENTER_COLOR
	textLabel.TextStrokeTransparency = 0.25
	textLabel.TextSize = 10
	textLabel.Font = Enum.Font.Code
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.Parent = billboard
end

local function localAxisCenter(index, tileSize, halfStuds)
	return -halfStuds + tileSize / 2 + index * tileSize
end

local function buildOverlay(roomTemplate)
	if not roomTemplate:IsA("Model") then
		warn("[RoomGridOverlay] Skipping non-model:", roomTemplate:GetFullName())
		return
	end

	local floor = findWalkableFloor(roomTemplate)

	if not floor then
		warn("[RoomGridOverlay] Missing WalkableFloor:", roomTemplate:GetFullName())
		return
	end

	local tileSize = getPositiveNumberAttribute(floor, "TileSize", TILE_SIZE_DEFAULT)
	local gridWidth = getPositiveIntegerAttribute(floor, "GridWidth", math.floor(floor.Size.X / tileSize + 0.5))
	local gridDepth = getPositiveIntegerAttribute(floor, "GridDepth", math.floor(floor.Size.Z / tileSize + 0.5))

	gridWidth = gridWidth > 0 and gridWidth or GRID_WIDTH_DEFAULT
	gridDepth = gridDepth > 0 and gridDepth or GRID_DEPTH_DEFAULT

	local expectedX = gridWidth * tileSize
	local expectedZ = gridDepth * tileSize
	local floorTopLocalY = floor.Size.Y / 2 + LINE_Y_OFFSET
	local floorRotation = floor.CFrame - floor.CFrame.Position

	local editorHelpers = roomTemplate:FindFirstChild("EditorHelpers")

	if not editorHelpers then
		editorHelpers = Instance.new("Folder")
		editorHelpers.Name = "EditorHelpers"
		editorHelpers.Parent = roomTemplate
	end

	local existingOverlay = editorHelpers:FindFirstChild("RoomGridOverlay")

	if existingOverlay then
		existingOverlay:Destroy()
	end

	local overlay = Instance.new("Folder")
	overlay.Name = "RoomGridOverlay"
	overlay.Parent = editorHelpers

	for xIndex = 0, gridWidth do
		local localX = -expectedX / 2 + xIndex * tileSize
		local localPosition = Vector3.new(localX, floorTopLocalY, 0)
		local line = makePart("GridLine_X_" .. tostring(xIndex), overlay, LINE_COLOR)

		line.Size = Vector3.new(LINE_THICKNESS, LINE_HEIGHT, expectedZ)
		line.CFrame = CFrame.new(floor.CFrame:PointToWorldSpace(localPosition)) * floorRotation
	end

	for zIndex = 0, gridDepth do
		local localZ = -expectedZ / 2 + zIndex * tileSize
		local localPosition = Vector3.new(0, floorTopLocalY, localZ)
		local line = makePart("GridLine_Z_" .. tostring(zIndex), overlay, LINE_COLOR)

		line.Size = Vector3.new(expectedX, LINE_HEIGHT, LINE_THICKNESS)
		line.CFrame = CFrame.new(floor.CFrame:PointToWorldSpace(localPosition)) * floorRotation
	end

	if CREATE_CENTER_MARKERS then
		local halfWidthStuds = expectedX / 2
		local halfDepthStuds = expectedZ / 2

		for x = 0, gridWidth - 1 do
			for z = 0, gridDepth - 1 do
				local localX = localAxisCenter(x, tileSize, halfWidthStuds)
				local localZ = localAxisCenter(z, tileSize, halfDepthStuds)
				local marker = makePart(
					string.format("TileCenter_%02d_%02d", x + 1, z + 1),
					overlay,
					CENTER_COLOR
				)

				marker.Size = Vector3.new(CENTER_MARKER_SIZE, LINE_HEIGHT, CENTER_MARKER_SIZE)
				marker.CFrame = CFrame.new(
					floor.CFrame:PointToWorldSpace(Vector3.new(localX, floorTopLocalY + 0.01, localZ))
				) * floorRotation

				if CREATE_AXIS_LABELS and (x == 0 or z == 0) then
					addLabel(
						string.format("TileLabel_%02d_%02d", x + 1, z + 1),
						overlay,
						string.format("%d,%d", x + 1, z + 1),
						CFrame.new(floor.CFrame:PointToWorldSpace(Vector3.new(localX, floorTopLocalY + 0.45, localZ)))
					)
				end
			end
		end
	end

	print(string.format(
		"[RoomGridOverlay] %s TileSize=%.2f Grid=%dx%d ExpectedFloor=%.2fx%.2f ActualFloor=%.2fx%.2f",
		roomTemplate.Name,
		tileSize,
		gridWidth,
		gridDepth,
		expectedX,
		expectedZ,
		floor.Size.X,
		floor.Size.Z
	))

	if math.abs(floor.Size.X - expectedX) > 0.05 or math.abs(floor.Size.Z - expectedZ) > 0.05 then
		warn(string.format(
			"[RoomGridOverlay] %s floor size mismatch. Expected X/Z %.2f/%.2f, got %.2f/%.2f.",
			roomTemplate.Name,
			expectedX,
			expectedZ,
			floor.Size.X,
			floor.Size.Z
		))
	end
end

local targets = {}

for _, instance in ipairs(Selection:Get()) do
	if instance:IsA("Model") then
		table.insert(targets, instance)
	end
end

if #targets == 0 then
	for _, path in ipairs(ROOM_TEMPLATE_PATHS) do
		local target = resolvePath(path)

		if target and target:IsA("Model") then
			table.insert(targets, target)
		else
			warn("[RoomGridOverlay] Could not resolve model path:", path)
		end
	end
end

if #targets == 0 then
	local fallback = ReplicatedStorage:FindFirstChild("RoomTemplates")
		and ReplicatedStorage.RoomTemplates:FindFirstChild("Layout_01")

	if fallback and fallback:IsA("Model") then
		table.insert(targets, fallback)
	else
		warn("[RoomGridOverlay] Select a room template Model or set ROOM_TEMPLATE_PATHS.")
	end
end

for _, roomTemplate in ipairs(targets) do
	buildOverlay(roomTemplate)
end
