local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Player-facing floor tile styling. Designers can set UsesTileGrid = false on
-- custom/decorative floors that should not show tile seams.
local FLOOR_GRID_LINES_ENABLED = true
local DEBUG_GRID_LINES = false

local GRID_LINE_COLOR = Color3.fromRGB(120, 120, 120)
local GRID_LINE_TRANSPARENCY = 0.55
local GRID_LINE_THICKNESS = 0.06
local GRID_LINE_HEIGHT = 0.03
local GRID_LINE_Y_OFFSET = 0.08
local GRID_LINE_MATERIAL = Enum.Material.Neon

local OVERLAY_FOLDER_NAME = "FloorGridLinesOverlay"
local OLD_DEBUG_OVERLAY_FOLDER_NAME = "GridDebugOverlay"
local MAX_TOTAL_GRID_LINES = 80

local player = Players.LocalPlayer
local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local GridConfig = require(sharedFolder:WaitForChild("GridConfig"))
local activeRooms = Workspace:WaitForChild("ActiveRooms")

local overlayFolder = nil
local lastRenderSignature = nil
local lastDebugSignature = nil
local lastWarningSignature = nil
local refreshToken = 0

local function debugPrint(signature, ...)
	if not DEBUG_GRID_LINES or lastDebugSignature == signature then
		return
	end

	lastDebugSignature = signature
	print("[FloorGridLines]", ...)
end

local function debugWarn(signature, ...)
	if not DEBUG_GRID_LINES or lastWarningSignature == signature then
		return
	end

	lastWarningSignature = signature
	warn("[FloorGridLines]", ...)
end

local function destroyFolderByName(folderName)
	for _, child in ipairs(Workspace:GetChildren()) do
		if child.Name == folderName then
			child:Destroy()
		end
	end
end

local function resetRenderState()
	lastRenderSignature = nil
end

local function clearOverlay()
	if overlayFolder then
		overlayFolder:Destroy()
		overlayFolder = nil
	end

	resetRenderState()
	destroyFolderByName(OLD_DEBUG_OVERLAY_FOLDER_NAME)
	destroyFolderByName(OVERLAY_FOLDER_NAME)
end

local function getOverlayFolder()
	if overlayFolder and overlayFolder.Parent then
		return overlayFolder
	end

	destroyFolderByName(OVERLAY_FOLDER_NAME)
	destroyFolderByName(OLD_DEBUG_OVERLAY_FOLDER_NAME)

	overlayFolder = Instance.new("Folder")
	overlayFolder.Name = OVERLAY_FOLDER_NAME
	overlayFolder.Parent = Workspace

	return overlayFolder
end

local function getCurrentRoomModel()
	local roomName = player:GetAttribute("CurrentRoomName")

	if typeof(roomName) ~= "string" or roomName == "" then
		return nil
	end

	return activeRooms:FindFirstChild(roomName)
end

local function getWalkableFloor(roomModel)
	if not roomModel then
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

local function configureGridPart(part, transparency)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = GRID_LINE_MATERIAL
	part.Color = GRID_LINE_COLOR
	part.Transparency = transparency
	part.Reflectance = 0
	part.Locked = true
end

local function createGridLine(name, size, cframe, transparency)
	local line = Instance.new("Part")
	line.Name = name
	line.Size = size
	line.CFrame = cframe
	configureGridPart(line, transparency)
	line.Parent = getOverlayFolder()

	return line
end

local function getRenderSignature(roomName, roomModel, floor)
	local tileSize = GridConfig.GetTileSize(roomModel, floor)
	local gridWidth = GridConfig.GetGridWidth(roomModel, floor)
	local gridDepth = GridConfig.GetGridDepth(roomModel, floor)

	return table.concat({
		tostring(roomName),
		roomModel:GetFullName(),
		floor:GetFullName(),
		tostring(tileSize),
		tostring(gridWidth),
		tostring(gridDepth),
		tostring(floor.Size.X),
		tostring(floor.Size.Y),
		tostring(floor.Size.Z),
		tostring(floor.CFrame),
	}, "|"), tileSize, gridWidth, gridDepth
end

local function drawGrid(roomName, roomModel, floor, tileSize, gridWidth, gridDepth)
	local totalLineCount = gridWidth + gridDepth + 2

	if totalLineCount > MAX_TOTAL_GRID_LINES then
		debugWarn("too-large:" .. tostring(roomName), string.format(
			"[FloorGridLines] Grid too large to draw safely: %dx%d.",
			gridWidth,
			gridDepth
		))
		return
	end

	local _, warnings = GridConfig.ValidateRoomGrid(roomModel)

	for _, warningMessage in ipairs(warnings) do
		debugWarn(
			"validation:" .. tostring(roomName) .. ":" .. tostring(warningMessage),
			tostring(warningMessage)
		)
	end

	local widthStuds = floor.Size.X
	local depthStuds = floor.Size.Z
	local halfWidth = widthStuds / 2
	local halfDepth = depthStuds / 2
	local yOffset = floor.Size.Y / 2 + GRID_LINE_Y_OFFSET
	local createdLineCount = 0

	for xIndex = 0, gridWidth do
		local localX = -halfWidth + (widthStuds / gridWidth) * xIndex

		createGridLine(
			"FloorGridLineX_" .. tostring(xIndex),
			Vector3.new(GRID_LINE_THICKNESS, GRID_LINE_HEIGHT, depthStuds),
			floor.CFrame * CFrame.new(localX, yOffset, 0),
			GRID_LINE_TRANSPARENCY
		)

		createdLineCount += 1
	end

	for zIndex = 0, gridDepth do
		local localZ = -halfDepth + (depthStuds / gridDepth) * zIndex

		createGridLine(
			"FloorGridLineZ_" .. tostring(zIndex),
			Vector3.new(widthStuds, GRID_LINE_HEIGHT, GRID_LINE_THICKNESS),
			floor.CFrame * CFrame.new(0, yOffset, localZ),
			GRID_LINE_TRANSPARENCY
		)

		createdLineCount += 1
	end

	return createdLineCount
end

local function refreshOverlay()
	if not FLOOR_GRID_LINES_ENABLED then
		debugPrint("disabled", "disabled")
		clearOverlay()
		return
	end

	local controlMode = player:GetAttribute("ControlMode") or "Hotel"

	if controlMode ~= "Hotel" then
		debugPrint("not-hotel:" .. tostring(controlMode), "hidden; ControlMode =", tostring(controlMode))
		clearOverlay()
		return
	end

	local roomName = player:GetAttribute("CurrentRoomName")
	local roomModel = getCurrentRoomModel()
	local floor = getWalkableFloor(roomModel)

	if not roomModel or not floor then
		debugPrint(
			"missing:" .. tostring(roomName) .. ":" .. tostring(roomModel ~= nil) .. ":" .. tostring(floor ~= nil),
			"attempt",
			"roomName =", tostring(roomName),
			"roomFound =", tostring(roomModel ~= nil),
			"floorFound =", tostring(floor ~= nil)
		)
		clearOverlay()
		return
	end

	local usesTileGrid = GridConfig.UsesTileGrid(roomModel, floor)

	if usesTileGrid == false then
		debugPrint(
			"no-grid:" .. tostring(roomName),
			"attempt",
			"roomName =", tostring(roomName),
			"roomFound = true",
			"floorFound = true",
			"UsesTileGrid = false"
		)
		clearOverlay()
		return
	end

	local signature, tileSize, gridWidth, gridDepth = getRenderSignature(roomName, roomModel, floor)

	if signature == lastRenderSignature and overlayFolder and overlayFolder.Parent then
		return
	end

	clearOverlay()
	lastRenderSignature = signature
	local createdLineCount = drawGrid(roomName, roomModel, floor, tileSize, gridWidth, gridDepth) or 0

	debugPrint(
		"built:" .. signature,
		"attempt",
		"roomName =", tostring(roomName),
		"roomFound = true",
		"floorFound = true",
		"UsesTileGrid =", tostring(usesTileGrid),
		"tileSize =", tostring(tileSize),
		"grid =", tostring(gridWidth) .. "x" .. tostring(gridDepth),
		"lineCount =", tostring(createdLineCount)
	)
end

local function scheduleOverlayRefresh(clearFirst)
	refreshToken += 1
	local token = refreshToken

	if clearFirst then
		clearOverlay()
	else
		resetRenderState()
	end

	task.defer(function()
		if token == refreshToken then
			refreshOverlay()
		end
	end)

	task.delay(0.25, function()
		if token == refreshToken then
			refreshOverlay()
		end
	end)

	task.delay(1, function()
		if token == refreshToken then
			refreshOverlay()
		end
	end)
end

player:GetAttributeChangedSignal("CurrentRoomName"):Connect(function()
	scheduleOverlayRefresh(true)
end)

player:GetAttributeChangedSignal("ControlMode"):Connect(function()
	scheduleOverlayRefresh(true)
end)

player.CharacterAdded:Connect(function()
	scheduleOverlayRefresh(true)
end)

activeRooms.ChildAdded:Connect(function()
	scheduleOverlayRefresh(false)
end)

activeRooms.ChildRemoved:Connect(function()
	scheduleOverlayRefresh(true)
end)

script.Destroying:Connect(clearOverlay)

refreshOverlay()
task.delay(1, refreshOverlay)
task.delay(3, refreshOverlay)
