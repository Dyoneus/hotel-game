local RoomFloorStyleConfig = require(script.Parent.RoomFloorStyleConfig)
local GridConfig = require(script.Parent.GridConfig)

local RoomFloorStyleRenderer = {}

local ROOM_FOLDER_NAME = "Room"
local WALKABLE_FLOOR_NAME = "WalkableFloor"
local DECORATIVE_FLOOR_FOLDER_NAME = "DecorativeFloor"
local RUNTIME_FLOOR_STYLE_FOLDER_NAME = "RuntimeFloorStyle"

local BASE_HEIGHT = 0.028
local BASE_Y_OFFSET = 0.043
local DETAIL_HEIGHT = 0.022
local DETAIL_Y_OFFSET = 0.052
local BORDER_THICKNESS = 0.12
local GRID_LINE_THICKNESS = 0.055
local MAX_CHECKER_PARTS = 320
local MAX_PEBBLE_PARTS = 180
local MAX_STRIPE_BANDS = 32
local MAX_WOOD_PLANKS = 40

local DEFAULT_COLOR = Color3.fromRGB(178, 178, 166)
local DEFAULT_MATERIAL = Enum.Material.SmoothPlastic

local function isInstance(value)
	return typeof(value) == "Instance"
end

local function isPositiveNumber(value)
	return typeof(value) == "number" and value > 0 and value == value and value < math.huge
end

local function isPositiveInteger(value)
	return isPositiveNumber(value) and value % 1 == 0
end

local function getPositiveInteger(value, fallback)
	if isPositiveInteger(value) then
		return math.floor(value)
	end

	return fallback
end

local function getStyleColor(style, colorName, fallback)
	local colors = typeof(style.Colors) == "table" and style.Colors or nil
	local color = colors and colors[colorName] or nil

	if typeof(color) == "Color3" then
		return color
	end

	return fallback or DEFAULT_COLOR
end

local function getStyleMaterial(style, materialName, fallback)
	local materials = typeof(style.Materials) == "table" and style.Materials or nil
	local material = materials and materials[materialName] or nil

	if typeof(material) == "EnumItem" then
		return material
	end

	return fallback or DEFAULT_MATERIAL
end

local function configureVisualPart(part, color, material, transparency)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Color = color or DEFAULT_COLOR
	part.Material = material or DEFAULT_MATERIAL
	part.Transparency = typeof(transparency) == "number" and transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("IsRuntimeFloorStyleVisual", true)
end

local function floorCFrame(info, localX, topOffset, localZ)
	local localY = info.WalkableFloor.Size.Y / 2 + topOffset

	return info.WalkableFloor.CFrame * CFrame.new(localX, localY, localZ)
end

local function createVisualPart(parent, name, size, cframe, color, material, transparency, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe

	if shape then
		part.Shape = shape
	end

	configureVisualPart(part, color, material, transparency)
	part.Parent = parent

	return part
end

local function createFolder(parent, name)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent

	return folder
end

local function clearFolder(folder)
	for _, child in ipairs(folder:GetChildren()) do
		child:Destroy()
	end
end

local function resolveRoomFloorInfo(roomModel, createFolders)
	if not isInstance(roomModel) or not roomModel:IsA("Model") then
		return nil, "roomModel must be a Model."
	end

	local roomFolder = roomModel:FindFirstChild(ROOM_FOLDER_NAME)

	if not roomFolder then
		return nil, "Room folder is missing."
	end

	local walkableFloor = roomFolder:FindFirstChild(WALKABLE_FLOOR_NAME)

	if not walkableFloor or not walkableFloor:IsA("BasePart") then
		return nil, "Room.WalkableFloor is missing or is not a BasePart."
	end

	if not isPositiveNumber(walkableFloor.Size.X) or not isPositiveNumber(walkableFloor.Size.Z) then
		return nil, "WalkableFloor has invalid X/Z size."
	end

	local decorativeFloor = roomFolder:FindFirstChild(DECORATIVE_FLOOR_FOLDER_NAME)

	if decorativeFloor and not decorativeFloor:IsA("Folder") then
		return nil, "Room.DecorativeFloor exists but is not a Folder."
	end

	if not decorativeFloor and createFolders == true then
		decorativeFloor = createFolder(roomFolder, DECORATIVE_FLOOR_FOLDER_NAME)
	end

	local runtimeFloorStyle = decorativeFloor and decorativeFloor:FindFirstChild(RUNTIME_FLOOR_STYLE_FOLDER_NAME) or nil

	if runtimeFloorStyle and not runtimeFloorStyle:IsA("Folder") then
		return nil, "Room.DecorativeFloor.RuntimeFloorStyle exists but is not a Folder."
	end

	if not runtimeFloorStyle and decorativeFloor and createFolders == true then
		runtimeFloorStyle = createFolder(decorativeFloor, RUNTIME_FLOOR_STYLE_FOLDER_NAME)
	end

	local tileSize = GridConfig.GetTileSize(roomModel, walkableFloor)
	local gridWidth = GridConfig.GetGridWidth(roomModel, walkableFloor)
	local gridDepth = GridConfig.GetGridDepth(roomModel, walkableFloor)

	if not isPositiveNumber(tileSize) then
		tileSize = GridConfig.TILE_SIZE
	end

	gridWidth = getPositiveInteger(gridWidth, math.max(1, math.floor(walkableFloor.Size.X / tileSize + 0.5)))
	gridDepth = getPositiveInteger(gridDepth, math.max(1, math.floor(walkableFloor.Size.Z / tileSize + 0.5)))

	local tileWidth = walkableFloor.Size.X / gridWidth
	local tileDepth = walkableFloor.Size.Z / gridDepth
	local warnings = {}
	local expectedWidth = gridWidth * tileSize
	local expectedDepth = gridDepth * tileSize

	if math.abs(walkableFloor.Size.X - expectedWidth) > GridConfig.GRID_VALIDATION_TOLERANCE then
		table.insert(warnings, string.format(
			"WalkableFloor Size.X %.2f does not match GridWidth * TileSize %.2f.",
			walkableFloor.Size.X,
			expectedWidth
		))
	end

	if math.abs(walkableFloor.Size.Z - expectedDepth) > GridConfig.GRID_VALIDATION_TOLERANCE then
		table.insert(warnings, string.format(
			"WalkableFloor Size.Z %.2f does not match GridDepth * TileSize %.2f.",
			walkableFloor.Size.Z,
			expectedDepth
		))
	end

	local gridContext = GridConfig.GetGridContext(roomModel)
	local usesTileMask = gridContext and gridContext.UsesTileMask == true
	local walkableCells = nil

	if usesTileMask then
		walkableCells = GridConfig.GetWalkableCells(gridContext)
	end

	return {
		RoomModel = roomModel,
		RoomFolder = roomFolder,
		WalkableFloor = walkableFloor,
		DecorativeFloor = decorativeFloor,
		RuntimeFloorStyle = runtimeFloorStyle,
		TileSize = tileSize,
		GridWidth = gridWidth,
		GridDepth = gridDepth,
		TileWidth = tileWidth,
		TileDepth = tileDepth,
		FloorSize = walkableFloor.Size,
		FloorCFrame = walkableFloor.CFrame,
		GridContext = gridContext,
		UsesTileMask = usesTileMask,
		WalkableCells = walkableCells,
		Warnings = warnings,
	}, "Floor info resolved."
end

local function getCellLocalCenter(info, tileX, tileZ)
	local localX = -info.FloorSize.X / 2 + info.TileWidth / 2 + (tileX - 1) * info.TileWidth
	local localZ = -info.FloorSize.Z / 2 + info.TileDepth / 2 + (tileZ - 1) * info.TileDepth

	return localX, localZ
end

local function createFill(parent, info, prefix, color, material, transparency)
	if info.UsesTileMask == true and typeof(info.WalkableCells) == "table" then
		for _, cell in ipairs(info.WalkableCells) do
			local localX, localZ = getCellLocalCenter(info, cell.X, cell.Z)

			createVisualPart(
				parent,
				string.format("%sTile_%02d_%02d", prefix, cell.X, cell.Z),
				Vector3.new(info.TileWidth, BASE_HEIGHT, info.TileDepth),
				floorCFrame(info, localX, BASE_Y_OFFSET, localZ),
				color,
				material,
				transparency
			)
		end

		return
	end

	createVisualPart(
		parent,
		prefix .. "Base",
		Vector3.new(info.FloorSize.X, BASE_HEIGHT, info.FloorSize.Z),
		floorCFrame(info, 0, BASE_Y_OFFSET, 0),
		color,
		material,
		transparency
	)
end

local function createBorder(parent, info, prefix, color, material)
	local halfWidth = info.FloorSize.X / 2
	local halfDepth = info.FloorSize.Z / 2

	createVisualPart(
		parent,
		prefix .. "FrontBorder",
		Vector3.new(info.FloorSize.X, DETAIL_HEIGHT, BORDER_THICKNESS),
		floorCFrame(info, 0, DETAIL_Y_OFFSET, -halfDepth + BORDER_THICKNESS / 2),
		color,
		material
	)

	createVisualPart(
		parent,
		prefix .. "BackBorder",
		Vector3.new(info.FloorSize.X, DETAIL_HEIGHT, BORDER_THICKNESS),
		floorCFrame(info, 0, DETAIL_Y_OFFSET, halfDepth - BORDER_THICKNESS / 2),
		color,
		material
	)

	createVisualPart(
		parent,
		prefix .. "LeftBorder",
		Vector3.new(BORDER_THICKNESS, DETAIL_HEIGHT, info.FloorSize.Z),
		floorCFrame(info, -halfWidth + BORDER_THICKNESS / 2, DETAIL_Y_OFFSET, 0),
		color,
		material
	)

	createVisualPart(
		parent,
		prefix .. "RightBorder",
		Vector3.new(BORDER_THICKNESS, DETAIL_HEIGHT, info.FloorSize.Z),
		floorCFrame(info, halfWidth - BORDER_THICKNESS / 2, DETAIL_Y_OFFSET, 0),
		color,
		material
	)
end

local function renderGrid(parent, info, style)
	local baseColor = getStyleColor(style, "Base")
	local lineColor = getStyleColor(style, "Line", baseColor)
	local borderColor = getStyleColor(style, "Border", lineColor)
	local baseMaterial = getStyleMaterial(style, "Base")
	local lineMaterial = getStyleMaterial(style, "Line", baseMaterial)
	local borderMaterial = getStyleMaterial(style, "Border", lineMaterial)

	createFill(parent, info, "GridFloor", baseColor, baseMaterial)

	for xIndex = 1, info.GridWidth - 1 do
		local localX = -info.FloorSize.X / 2 + xIndex * info.TileWidth

		createVisualPart(
			parent,
			"GridLineX_" .. tostring(xIndex),
			Vector3.new(GRID_LINE_THICKNESS, DETAIL_HEIGHT, info.FloorSize.Z),
			floorCFrame(info, localX, DETAIL_Y_OFFSET, 0),
			lineColor,
			lineMaterial
		)
	end

	for zIndex = 1, info.GridDepth - 1 do
		local localZ = -info.FloorSize.Z / 2 + zIndex * info.TileDepth

		createVisualPart(
			parent,
			"GridLineZ_" .. tostring(zIndex),
			Vector3.new(info.FloorSize.X, DETAIL_HEIGHT, GRID_LINE_THICKNESS),
			floorCFrame(info, 0, DETAIL_Y_OFFSET + 0.001, localZ),
			lineColor,
			lineMaterial
		)
	end

	createBorder(parent, info, "Grid", borderColor, borderMaterial)
end

local function renderPlain(parent, info, style)
	local baseColor = getStyleColor(style, "Base")
	local borderColor = getStyleColor(style, "Border", baseColor)
	local baseMaterial = getStyleMaterial(style, "Base")
	local borderMaterial = getStyleMaterial(style, "Border", baseMaterial)

	createFill(parent, info, "PlainFloor", baseColor, baseMaterial)
	createBorder(parent, info, "Plain", borderColor, borderMaterial)
end

local function renderCarpet(parent, info, style)
	local baseColor = getStyleColor(style, "Base")
	local panelColor = getStyleColor(style, "Panel", baseColor)
	local borderColor = getStyleColor(style, "Border", baseColor)
	local baseMaterial = getStyleMaterial(style, "Base", Enum.Material.Fabric)
	local panelMaterial = getStyleMaterial(style, "Panel", baseMaterial)
	local borderMaterial = getStyleMaterial(style, "Border", baseMaterial)

	createFill(parent, info, "CarpetFloor", baseColor, baseMaterial)

	local panelInsetX = math.min(info.TileWidth, math.max(0, info.FloorSize.X / 5))
	local panelInsetZ = math.min(info.TileDepth, math.max(0, info.FloorSize.Z / 5))

	createVisualPart(
		parent,
		"CarpetCenterPanel",
		Vector3.new(
			math.max(info.TileWidth, info.FloorSize.X - panelInsetX),
			BASE_HEIGHT,
			math.max(info.TileDepth, info.FloorSize.Z - panelInsetZ)
		),
		floorCFrame(info, 0, BASE_Y_OFFSET + 0.002, 0),
		panelColor,
		panelMaterial
	)

	createBorder(parent, info, "Carpet", borderColor, borderMaterial)
end

local function renderWood(parent, info, style)
	local plankA = getStyleColor(style, "PlankA", getStyleColor(style, "Base"))
	local plankB = getStyleColor(style, "PlankB", plankA)
	local lineColor = getStyleColor(style, "Line", plankB)
	local plankMaterial = getStyleMaterial(style, "Plank", getStyleMaterial(style, "Base", Enum.Material.Wood))
	local lineMaterial = getStyleMaterial(style, "Line", plankMaterial)
	local plankCount = math.min(info.GridWidth, MAX_WOOD_PLANKS)
	local plankWidth = info.FloorSize.X / plankCount

	for plankIndex = 1, plankCount do
		local localX = -info.FloorSize.X / 2 + (plankIndex - 0.5) * plankWidth
		local color = if plankIndex % 2 == 0 then plankA else plankB

		createVisualPart(
			parent,
			"WoodPlank_" .. tostring(plankIndex),
			Vector3.new(plankWidth + 0.02, BASE_HEIGHT, info.FloorSize.Z),
			floorCFrame(info, localX, BASE_Y_OFFSET, 0),
			color,
			plankMaterial
		)
	end

	for seamIndex = 1, plankCount - 1 do
		local localX = -info.FloorSize.X / 2 + seamIndex * plankWidth

		createVisualPart(
			parent,
			"WoodSeam_" .. tostring(seamIndex),
			Vector3.new(0.035, DETAIL_HEIGHT, info.FloorSize.Z),
			floorCFrame(info, localX, DETAIL_Y_OFFSET, 0),
			lineColor,
			lineMaterial
		)
	end
end

local function getCheckerPatchSpan(info)
	local totalTiles = info.GridWidth * info.GridDepth

	if totalTiles <= MAX_CHECKER_PARTS then
		return 1
	end

	return math.max(1, math.ceil(math.sqrt(totalTiles / MAX_CHECKER_PARTS)))
end

local function renderChecker(parent, info, style)
	local tileA = getStyleColor(style, "TileA")
	local tileB = getStyleColor(style, "TileB", tileA)
	local borderColor = getStyleColor(style, "Border", tileB)
	local tileMaterial = getStyleMaterial(style, "Tile")
	local borderMaterial = getStyleMaterial(style, "Border", tileMaterial)
	local patchSpan = getCheckerPatchSpan(info)

	for startX = 1, info.GridWidth, patchSpan do
		for startZ = 1, info.GridDepth, patchSpan do
			local endX = math.min(info.GridWidth, startX + patchSpan - 1)
			local endZ = math.min(info.GridDepth, startZ + patchSpan - 1)
			local patchWidth = (endX - startX + 1) * info.TileWidth
			local patchDepth = (endZ - startZ + 1) * info.TileDepth
			local centerX = -info.FloorSize.X / 2 + (startX - 1) * info.TileWidth + patchWidth / 2
			local centerZ = -info.FloorSize.Z / 2 + (startZ - 1) * info.TileDepth + patchDepth / 2
			local color = tileA

			if (math.floor((startX - 1) / patchSpan) + math.floor((startZ - 1) / patchSpan)) % 2 ~= 0 then
				color = tileB
			end

			createVisualPart(
				parent,
				string.format("CheckerPatch_%02d_%02d", startX, startZ),
				Vector3.new(patchWidth, BASE_HEIGHT, patchDepth),
				floorCFrame(info, centerX, BASE_Y_OFFSET, centerZ),
				color,
				tileMaterial
			)
		end
	end

	createBorder(parent, info, "Checker", borderColor, borderMaterial)
end

local function deterministicUnit(tileX, tileZ, salt)
	local value = (tileX * 73856093 + tileZ * 19349663 + salt * 83492791) % 1000

	return value / 1000
end

local function renderPebble(parent, info, style)
	local baseColor = getStyleColor(style, "Base")
	local pebbleColors = {
		getStyleColor(style, "PebbleA", baseColor),
		getStyleColor(style, "PebbleB", baseColor),
		getStyleColor(style, "PebbleC", baseColor),
	}
	local baseMaterial = getStyleMaterial(style, "Base", Enum.Material.Slate)
	local pebbleMaterial = getStyleMaterial(style, "Pebble", baseMaterial)
	local totalTiles = info.GridWidth * info.GridDepth
	local cellSpan = math.max(1, math.ceil(math.sqrt(totalTiles / MAX_PEBBLE_PARTS)))

	createFill(parent, info, "PebbleFloor", baseColor, baseMaterial)

	for tileX = 1, info.GridWidth, cellSpan do
		for tileZ = 1, info.GridDepth, cellSpan do
			local width = math.min(cellSpan, info.GridWidth - tileX + 1) * info.TileWidth
			local depth = math.min(cellSpan, info.GridDepth - tileZ + 1) * info.TileDepth
			local baseX = -info.FloorSize.X / 2 + (tileX - 1) * info.TileWidth
			local baseZ = -info.FloorSize.Z / 2 + (tileZ - 1) * info.TileDepth
			local offsetX = deterministicUnit(tileX, tileZ, 1) * width
			local offsetZ = deterministicUnit(tileX, tileZ, 2) * depth
			local diameter = math.max(0.35, math.min(info.TileWidth, info.TileDepth) * (0.22 + deterministicUnit(tileX, tileZ, 3) * 0.18))
			local colorIndex = math.floor(deterministicUnit(tileX, tileZ, 4) * #pebbleColors) + 1
			local localX = baseX + offsetX
			local localZ = baseZ + offsetZ

			createVisualPart(
				parent,
				string.format("Pebble_%02d_%02d", tileX, tileZ),
				Vector3.new(diameter, DETAIL_HEIGHT, diameter),
				floorCFrame(info, localX, DETAIL_Y_OFFSET, localZ),
				pebbleColors[colorIndex],
				pebbleMaterial,
				0,
				Enum.PartType.Cylinder
			)
		end
	end
end

local function renderStripe(parent, info, style)
	local stripeA = getStyleColor(style, "StripeA")
	local stripeB = getStyleColor(style, "StripeB", stripeA)
	local borderColor = getStyleColor(style, "Border", stripeB)
	local stripeMaterial = getStyleMaterial(style, "Stripe")
	local borderMaterial = getStyleMaterial(style, "Border", stripeMaterial)
	local bandCount = math.min(info.GridDepth, MAX_STRIPE_BANDS)
	local bandDepth = info.FloorSize.Z / bandCount

	for bandIndex = 1, bandCount do
		local localZ = -info.FloorSize.Z / 2 + (bandIndex - 0.5) * bandDepth
		local color = if bandIndex % 2 == 0 then stripeA else stripeB

		createVisualPart(
			parent,
			"StripeBand_" .. tostring(bandIndex),
			Vector3.new(info.FloorSize.X, BASE_HEIGHT, bandDepth + 0.02),
			floorCFrame(info, 0, BASE_Y_OFFSET, localZ),
			color,
			stripeMaterial
		)
	end

	createBorder(parent, info, "Stripe", borderColor, borderMaterial)
end

local RENDERERS_BY_PATTERN = {
	Grid = renderGrid,
	Plain = renderPlain,
	Carpet = renderCarpet,
	Wood = renderWood,
	Checker = renderChecker,
	Pebble = renderPebble,
	Stripe = renderStripe,
}

function RoomFloorStyleRenderer.GetRoomFloorInfo(roomModel)
	return resolveRoomFloorInfo(roomModel, false)
end

function RoomFloorStyleRenderer.GetRuntimeFloorStyleFolder(roomModel)
	local info, message = resolveRoomFloorInfo(roomModel, true)

	if not info then
		return nil, message
	end

	return info.RuntimeFloorStyle, "RuntimeFloorStyle folder resolved.", info
end

function RoomFloorStyleRenderer.ClearRuntimeFloorStyle(roomModel)
	local info, message = resolveRoomFloorInfo(roomModel, false)

	if not info then
		return false, message
	end

	if not info.RuntimeFloorStyle then
		return true, "No RuntimeFloorStyle folder to clear.", info
	end

	clearFolder(info.RuntimeFloorStyle)
	info.RuntimeFloorStyle:SetAttribute("FloorStyleId", nil)
	info.RuntimeFloorStyle:SetAttribute("FloorStyleAppliedAt", nil)
	info.RuntimeFloorStyle:SetAttribute("FloorStylePartCount", nil)

	if isInstance(info.RoomModel) then
		info.RoomModel:SetAttribute("FloorStyleId", nil)
		info.RoomModel:SetAttribute("FloorStyleAppliedAt", nil)
	end

	return true, "RuntimeFloorStyle cleared.", info
end

function RoomFloorStyleRenderer.ApplyFloorStyle(roomModel, floorStyleId, options)
	options = typeof(options) == "table" and options or {}

	local resolvedStyleId = floorStyleId

	if typeof(resolvedStyleId) ~= "string" or resolvedStyleId == "" then
		resolvedStyleId = RoomFloorStyleConfig.GetDefaultStyleId()
	end

	local style = RoomFloorStyleConfig.GetStyle(resolvedStyleId)

	if not style then
		return false, "Unknown floor style: " .. tostring(floorStyleId)
	end

	local renderer = RENDERERS_BY_PATTERN[style.Pattern]

	if not renderer then
		return false, "Unsupported floor style pattern: " .. tostring(style.Pattern)
	end

	local info, message = resolveRoomFloorInfo(roomModel, true)

	if not info then
		return false, message
	end

	clearFolder(info.RuntimeFloorStyle)

	local ok, renderError = pcall(renderer, info.RuntimeFloorStyle, info, style, options)

	if not ok then
		clearFolder(info.RuntimeFloorStyle)
		return false, "Failed to render floor style: " .. tostring(renderError), info
	end

	local appliedAt = os.time()
	local partCount = #info.RuntimeFloorStyle:GetChildren()

	info.RuntimeFloorStyle:SetAttribute("FloorStyleId", style.FloorStyleId)
	info.RuntimeFloorStyle:SetAttribute("FloorStyleAppliedAt", appliedAt)
	info.RuntimeFloorStyle:SetAttribute("FloorStylePartCount", partCount)
	info.RoomModel:SetAttribute("FloorStyleId", style.FloorStyleId)
	info.RoomModel:SetAttribute("FloorStyleAppliedAt", appliedAt)

	if #info.Warnings > 0 then
		return true, "Floor style applied with warnings: " .. table.concat(info.Warnings, " "), info
	end

	return true, string.format("Applied floor style %s with %d visual parts.", style.FloorStyleId, partCount), info
end

return RoomFloorStyleRenderer
