local RoomWallStyleConfig = require(script.Parent.RoomWallStyleConfig)

local RoomWallStyleRenderer = {}

local ROOM_FOLDER_NAME = "Room"
local WALLS_FOLDER_NAME = "Walls"
local WALKABLE_FLOOR_NAME = "WalkableFloor"
local DECORATIVE_WALLS_FOLDER_NAME = "DecorativeWalls"
local RUNTIME_WALL_STYLE_FOLDER_NAME = "RuntimeWallStyle"

local WALL_PANEL_THICKNESS = 0.035
local SURFACE_OFFSET = 0.018
local DETAIL_OFFSET = 0.014
local MIN_SURFACE_SIZE = 0.1
local MAX_STRIPE_BANDS_PER_SURFACE = 10
local MAX_WALLPAPER_MOTIFS_PER_SURFACE = 8
local MAX_BRICK_ROWS_PER_SURFACE = 5
local MAX_BRICK_COLUMNS_PER_SURFACE = 8

local DEFAULT_COLOR = Color3.fromRGB(222, 212, 193)
local DEFAULT_MATERIAL = Enum.Material.SmoothPlastic

local SKIP_NAME_TOKENS = {
	"collision",
	"trim",
	"baseboard",
	"chairrail",
	"chair_rail",
	"door",
	"entrance",
	"exit",
}

local function isInstance(value)
	return typeof(value) == "Instance"
end

local function isPositiveNumber(value)
	return typeof(value) == "number" and value > 0 and value == value and value < math.huge
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
	part:SetAttribute("IsRuntimeWallStyleVisual", true)
end

local function createVisualPart(parent, name, size, cframe, color, material, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	configureVisualPart(part, color, material, transparency)
	part.Parent = parent

	return part
end

local function sanitizeName(name)
	local sanitized = tostring(name or "Wall"):gsub("%W", "_")

	if sanitized == "" then
		return "Wall"
	end

	return sanitized
end

local function shouldSkipWallPart(part)
	if not part:IsA("BasePart") then
		return true
	end

	local lowerName = string.lower(part.Name)

	if not string.find(lowerName, "wall", 1, true) then
		return true
	end

	for _, token in ipairs(SKIP_NAME_TOKENS) do
		if string.find(lowerName, token, 1, true) then
			return true
		end
	end

	if part.Transparency >= 0.95 then
		return true
	end

	local size = part.Size

	if not isPositiveNumber(size.X)
		or not isPositiveNumber(size.Y)
		or not isPositiveNumber(size.Z) then

		return true
	end

	return false
end

local function resolveRoomWallInfo(roomModel, createFolders)
	if not isInstance(roomModel) or not roomModel:IsA("Model") then
		return nil, "roomModel must be a Model."
	end

	local roomFolder = roomModel:FindFirstChild(ROOM_FOLDER_NAME)

	if not roomFolder then
		return nil, "Room folder is missing."
	end

	local wallsFolder = roomFolder:FindFirstChild(WALLS_FOLDER_NAME)

	if not wallsFolder or not wallsFolder:IsA("Folder") then
		return nil, "Room.Walls is missing or is not a Folder."
	end

	local decorativeWalls = roomFolder:FindFirstChild(DECORATIVE_WALLS_FOLDER_NAME)

	if decorativeWalls and not decorativeWalls:IsA("Folder") then
		return nil, "Room.DecorativeWalls exists but is not a Folder."
	end

	if not decorativeWalls and createFolders == true then
		decorativeWalls = createFolder(roomFolder, DECORATIVE_WALLS_FOLDER_NAME)
	end

	local runtimeWallStyle = decorativeWalls and decorativeWalls:FindFirstChild(RUNTIME_WALL_STYLE_FOLDER_NAME) or nil

	if runtimeWallStyle and not runtimeWallStyle:IsA("Folder") then
		return nil, "Room.DecorativeWalls.RuntimeWallStyle exists but is not a Folder."
	end

	if not runtimeWallStyle and decorativeWalls and createFolders == true then
		runtimeWallStyle = createFolder(decorativeWalls, RUNTIME_WALL_STYLE_FOLDER_NAME)
	end

	local walkableFloor = roomFolder:FindFirstChild(WALKABLE_FLOOR_NAME)
	local roomCenter = roomModel:GetPivot().Position

	if walkableFloor and walkableFloor:IsA("BasePart") then
		roomCenter = walkableFloor.Position
	end

	return {
		RoomModel = roomModel,
		RoomFolder = roomFolder,
		WallsFolder = wallsFolder,
		DecorativeWalls = decorativeWalls,
		RuntimeWallStyle = runtimeWallStyle,
		WalkableFloor = walkableFloor,
		RoomCenter = roomCenter,
	}, "Wall info resolved."
end

local function getNormalAxis(part)
	local size = part.Size

	if size.X <= size.Z then
		return "X", size.X, size.Z, part.CFrame.RightVector
	end

	return "Z", size.Z, size.X, part.CFrame.LookVector
end

local function createSurfaceInfo(info, part)
	local normalAxis, thickness, horizontalLength, axisVector = getNormalAxis(part)
	local height = part.Size.Y

	if thickness <= MIN_SURFACE_SIZE
		or horizontalLength <= MIN_SURFACE_SIZE
		or height <= MIN_SURFACE_SIZE then

		return nil
	end

	local towardCenter = info.RoomCenter - part.Position
	local normal = axisVector

	if towardCenter:Dot(axisVector) < 0 then
		normal = -axisVector
	end

	local overlayOffset = thickness / 2 + WALL_PANEL_THICKNESS / 2 + SURFACE_OFFSET

	return {
		Part = part,
		Name = sanitizeName(part.Name),
		NormalAxis = normalAxis,
		Normal = normal,
		OverlayCFrame = part.CFrame + normal * overlayOffset,
		HorizontalLength = horizontalLength,
		Height = height,
		Thickness = thickness,
	}
end

local function collectWallSurfaces(info)
	local surfaces = {}

	for _, child in ipairs(info.WallsFolder:GetChildren()) do
		if not shouldSkipWallPart(child) then
			local surface = createSurfaceInfo(info, child)

			if surface then
				table.insert(surfaces, surface)
			end
		end
	end

	table.sort(surfaces, function(a, b)
		return a.Name < b.Name
	end)

	return surfaces
end

local function createPanel(parent, surface, name, horizontalLength, verticalHeight, localHorizontalOffset, localVerticalOffset, color, material, transparency, extraNormalOffset)
	local offsetCFrame = surface.OverlayCFrame
	local localCFrame

	if surface.NormalAxis == "X" then
		localCFrame = CFrame.new(0, localVerticalOffset or 0, localHorizontalOffset or 0)
	else
		localCFrame = CFrame.new(localHorizontalOffset or 0, localVerticalOffset or 0, 0)
	end

	local cframe = offsetCFrame * localCFrame

	if typeof(extraNormalOffset) == "number" and extraNormalOffset ~= 0 then
		cframe = cframe + surface.Normal * extraNormalOffset
	end

	local size

	if surface.NormalAxis == "X" then
		size = Vector3.new(WALL_PANEL_THICKNESS, verticalHeight, horizontalLength)
	else
		size = Vector3.new(horizontalLength, verticalHeight, WALL_PANEL_THICKNESS)
	end

	return createVisualPart(parent, name, size, cframe, color, material, transparency)
end

local function renderBasePanel(parent, surface, prefix, color, material, transparency)
	return createPanel(
		parent,
		surface,
		prefix .. surface.Name .. "_Base",
		surface.HorizontalLength,
		surface.Height,
		0,
		0,
		color,
		material,
		transparency,
		0
	)
end

local function renderDefault()
	-- Default intentionally leaves template-owned walls visible.
end

local function renderPlain(parent, info, style)
	local baseColor = getStyleColor(style, "Base")
	local baseMaterial = getStyleMaterial(style, "Base")

	for _, surface in ipairs(info.WallSurfaces) do
		renderBasePanel(parent, surface, "PlainWall_", baseColor, baseMaterial)
	end
end

local function renderStripe(parent, info, style)
	local baseColor = getStyleColor(style, "Base")
	local stripeColor = getStyleColor(style, "Stripe", baseColor)
	local baseMaterial = getStyleMaterial(style, "Base")
	local stripeMaterial = getStyleMaterial(style, "Stripe", baseMaterial)

	for _, surface in ipairs(info.WallSurfaces) do
		renderBasePanel(parent, surface, "StripeWall_", baseColor, baseMaterial)

		local bandCount = math.max(2, math.min(MAX_STRIPE_BANDS_PER_SURFACE, math.floor(surface.HorizontalLength / 2.4)))
		local bandWidth = surface.HorizontalLength / bandCount
		local stripeWidth = math.max(0.18, bandWidth * 0.38)

		for bandIndex = 1, bandCount do
			if bandIndex % 2 == 0 then
				local localOffset = -surface.HorizontalLength / 2 + (bandIndex - 0.5) * bandWidth

				createPanel(
					parent,
					surface,
					string.format("StripeWall_%s_Band_%02d", surface.Name, bandIndex),
					stripeWidth,
					surface.Height,
					localOffset,
					0,
					stripeColor,
					stripeMaterial,
					nil,
					DETAIL_OFFSET
				)
			end
		end
	end
end

local function renderWallpaperPattern(parent, info, style)
	local baseColor = getStyleColor(style, "Base")
	local accentColor = getStyleColor(style, "Accent", baseColor)
	local borderColor = getStyleColor(style, "Border", accentColor)
	local baseMaterial = getStyleMaterial(style, "Base")
	local accentMaterial = getStyleMaterial(style, "Accent", baseMaterial)
	local borderMaterial = getStyleMaterial(style, "Border", accentMaterial)

	for _, surface in ipairs(info.WallSurfaces) do
		renderBasePanel(parent, surface, "WallpaperWall_", baseColor, baseMaterial)

		local borderHeight = math.min(0.16, math.max(0.08, surface.Height * 0.035))
		local topOffset = surface.Height / 2 - borderHeight * 1.5
		local bottomOffset = -surface.Height / 2 + borderHeight * 1.5

		createPanel(
			parent,
			surface,
			"WallpaperWall_" .. surface.Name .. "_TopBorder",
			surface.HorizontalLength,
			borderHeight,
			0,
			topOffset,
			borderColor,
			borderMaterial,
			nil,
			DETAIL_OFFSET
		)
		createPanel(
			parent,
			surface,
			"WallpaperWall_" .. surface.Name .. "_BottomBorder",
			surface.HorizontalLength,
			borderHeight,
			0,
			bottomOffset,
			borderColor,
			borderMaterial,
			nil,
			DETAIL_OFFSET
		)

		local motifCount = math.max(2, math.min(MAX_WALLPAPER_MOTIFS_PER_SURFACE, math.floor(surface.HorizontalLength / 3.5)))
		local motifSpacing = surface.HorizontalLength / motifCount
		local motifWidth = math.min(0.35, math.max(0.18, motifSpacing * 0.18))
		local motifHeight = math.min(0.9, math.max(0.45, surface.Height * 0.12))

		for motifIndex = 1, motifCount do
			local localOffset = -surface.HorizontalLength / 2 + (motifIndex - 0.5) * motifSpacing

			createPanel(
				parent,
				surface,
				string.format("WallpaperWall_%s_Motif_%02d", surface.Name, motifIndex),
				motifWidth,
				motifHeight,
				localOffset,
				0,
				accentColor,
				accentMaterial,
				nil,
				DETAIL_OFFSET * 2
			)
		end
	end
end

local function renderBrick(parent, info, style)
	local baseColor = getStyleColor(style, "Base")
	local mortarColor = getStyleColor(style, "Mortar", Color3.fromRGB(215, 203, 186))
	local baseMaterial = getStyleMaterial(style, "Base", Enum.Material.Brick)
	local mortarMaterial = getStyleMaterial(style, "Mortar")
	local mortarThickness = 0.055

	for _, surface in ipairs(info.WallSurfaces) do
		renderBasePanel(parent, surface, "BrickWall_", baseColor, baseMaterial)

		local rowCount = math.max(2, math.min(MAX_BRICK_ROWS_PER_SURFACE, math.floor(surface.Height / 1.1)))
		local columnCount = math.max(2, math.min(MAX_BRICK_COLUMNS_PER_SURFACE, math.floor(surface.HorizontalLength / 2.6)))
		local rowHeight = surface.Height / rowCount
		local columnWidth = surface.HorizontalLength / columnCount

		for rowIndex = 1, rowCount - 1 do
			local verticalOffset = -surface.Height / 2 + rowIndex * rowHeight

			createPanel(
				parent,
				surface,
				string.format("BrickWall_%s_RowMortar_%02d", surface.Name, rowIndex),
				surface.HorizontalLength,
				mortarThickness,
				0,
				verticalOffset,
				mortarColor,
				mortarMaterial,
				nil,
				DETAIL_OFFSET
			)
		end

		for rowIndex = 1, rowCount do
			local rowCenter = -surface.Height / 2 + (rowIndex - 0.5) * rowHeight
			local stagger = if rowIndex % 2 == 0 then columnWidth / 2 else 0

			for columnIndex = 1, columnCount - 1 do
				local horizontalOffset = -surface.HorizontalLength / 2 + columnIndex * columnWidth + stagger

				if horizontalOffset < surface.HorizontalLength / 2 - mortarThickness then
					createPanel(
						parent,
						surface,
						string.format("BrickWall_%s_ColumnMortar_%02d_%02d", surface.Name, rowIndex, columnIndex),
						mortarThickness,
						math.max(0.2, rowHeight - mortarThickness),
						horizontalOffset,
						rowCenter,
						mortarColor,
						mortarMaterial,
						nil,
						DETAIL_OFFSET * 2
					)
				end
			end
		end
	end
end

local RENDERERS_BY_PATTERN = {
	Default = renderDefault,
	Plain = renderPlain,
	Stripe = renderStripe,
	WallpaperPattern = renderWallpaperPattern,
	Brick = renderBrick,
}

function RoomWallStyleRenderer.GetRoomWallInfo(roomModel)
	local info, message = resolveRoomWallInfo(roomModel, false)

	if info then
		info.WallSurfaces = collectWallSurfaces(info)
	end

	return info, message
end

function RoomWallStyleRenderer.GetRuntimeWallStyleFolder(roomModel)
	local info, message = resolveRoomWallInfo(roomModel, true)

	if not info then
		return nil, message
	end

	return info.RuntimeWallStyle, "RuntimeWallStyle folder resolved.", info
end

function RoomWallStyleRenderer.ClearRuntimeWallStyle(roomModel)
	local info, message = resolveRoomWallInfo(roomModel, false)

	if not info then
		return false, message
	end

	if not info.RuntimeWallStyle then
		return true, "No RuntimeWallStyle folder to clear.", info
	end

	clearFolder(info.RuntimeWallStyle)
	info.RuntimeWallStyle:SetAttribute("WallStyleId", nil)
	info.RuntimeWallStyle:SetAttribute("WallStyleAppliedAt", nil)
	info.RuntimeWallStyle:SetAttribute("WallStylePartCount", nil)

	if isInstance(info.RoomModel) then
		info.RoomModel:SetAttribute("WallStyleId", nil)
		info.RoomModel:SetAttribute("WallStyleAppliedAt", nil)
	end

	return true, "RuntimeWallStyle cleared.", info
end

function RoomWallStyleRenderer.ApplyWallStyle(roomModel, wallStyleId, options)
	options = typeof(options) == "table" and options or {}

	local resolvedStyleId = wallStyleId

	if typeof(resolvedStyleId) ~= "string" or resolvedStyleId == "" then
		resolvedStyleId = RoomWallStyleConfig.GetDefaultStyleId()
	end

	local style = RoomWallStyleConfig.GetStyle(resolvedStyleId)

	if not style then
		return false, "Unknown wall style: " .. tostring(wallStyleId)
	end

	local renderer = RENDERERS_BY_PATTERN[style.Pattern]

	if not renderer then
		return false, "Unsupported wall style pattern: " .. tostring(style.Pattern)
	end

	local info, message = resolveRoomWallInfo(roomModel, true)

	if not info then
		return false, message
	end

	info.WallSurfaces = collectWallSurfaces(info)

	if #info.WallSurfaces == 0 and style.Pattern ~= "Default" then
		return false, "No wall surfaces found.", info
	end

	clearFolder(info.RuntimeWallStyle)

	local ok, renderError = pcall(renderer, info.RuntimeWallStyle, info, style, options)

	if not ok then
		clearFolder(info.RuntimeWallStyle)
		return false, "Failed to render wall style: " .. tostring(renderError), info
	end

	local appliedAt = os.time()
	local partCount = #info.RuntimeWallStyle:GetChildren()

	info.RuntimeWallStyle:SetAttribute("WallStyleId", style.WallStyleId)
	info.RuntimeWallStyle:SetAttribute("WallStyleAppliedAt", appliedAt)
	info.RuntimeWallStyle:SetAttribute("WallStylePartCount", partCount)
	info.RoomModel:SetAttribute("WallStyleId", style.WallStyleId)
	info.RoomModel:SetAttribute("WallStyleAppliedAt", appliedAt)

	return true, string.format("Applied wall style %s with %d visual parts.", style.WallStyleId, partCount), info
end

return RoomWallStyleRenderer
