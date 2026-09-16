-- Studio helper: validate configured owned-room layout templates.
--
-- Run this manually in Roblox Studio Command Bar or from a temporary Script.
-- The helper reads ReplicatedStorage.RoomTemplates and checks TemplateName
-- for available layouts from RoomLayoutConfig. Missing templates are WARN-only
-- because most future layouts have not been generated yet.
--
-- The helper does not create, delete, or modify instances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TOOL_PREFIX = "[RoomLayoutTemplateValidator]"
local DEFAULT_TILE_SIZE = 4
local FLOOR_SIZE_TOLERANCE = 0.15
local TILE_MARKER_SIZE_TOLERANCE = 0.25

local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
local roomLayoutConfigModule = sharedFolder and sharedFolder:FindFirstChild("RoomLayoutConfig")

if not roomLayoutConfigModule or not roomLayoutConfigModule:IsA("ModuleScript") then
	error(TOOL_PREFIX .. " Missing ReplicatedStorage.Shared.RoomLayoutConfig.")
end

local success, RoomLayoutConfig = pcall(require, roomLayoutConfigModule)

if not success or typeof(RoomLayoutConfig) ~= "table" then
	error(TOOL_PREFIX .. " Could not require RoomLayoutConfig: " .. tostring(RoomLayoutConfig))
end

local function findBasePart(root, name)
	local instance = root and root:FindFirstChild(name, true)

	if instance and instance:IsA("BasePart") then
		return instance
	end

	return nil
end

local function findRoomExitPart(root)
	local namedExit = findBasePart(root, "RoomExitZone")

	if namedExit then
		return namedExit
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("IsRoomExit") == true then
			return descendant
		end
	end

	return nil
end

local function findWalkableFloor(templateModel)
	local roomFolder = templateModel:FindFirstChild("Room")
	local floor = roomFolder and roomFolder:FindFirstChild("WalkableFloor")

	if floor and floor:IsA("BasePart") then
		return floor, false
	end

	local descendantFloor = templateModel:FindFirstChild("WalkableFloor", true)

	if descendantFloor and descendantFloor:IsA("BasePart") then
		return descendantFloor, true
	end

	return nil, false
end

local function appendIssue(issues, message)
	table.insert(issues, message)
end

local function appendSummary(issues, message)
	table.insert(issues.summaries, message)
end

local function isPositiveInteger(value)
	return typeof(value) == "number"
		and value == value
		and value > 0
		and value < math.huge
		and math.floor(value) == value
end

local function isInteger(value)
	return typeof(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
		and math.floor(value) == value
end

local function cellKey(tileX, tileZ)
	return tostring(tileX) .. "," .. tostring(tileZ)
end

local function getBooleanAttribute(model, floor, attributeName)
	local value = model:GetAttribute(attributeName)

	if typeof(value) == "boolean" then
		return value
	end

	if floor then
		value = floor:GetAttribute(attributeName)

		if typeof(value) == "boolean" then
			return value
		end
	end

	return nil
end

local function getPositiveNumberAttribute(model, floor, attributeName)
	local value = model:GetAttribute(attributeName)

	if typeof(value) ~= "number" and floor then
		value = floor:GetAttribute(attributeName)
	end

	if typeof(value) == "number" and value == value and value > 0 and value < math.huge then
		return value
	end

	return nil
end

local function getPositiveIntegerAttribute(model, floor, attributeName)
	local value = getPositiveNumberAttribute(model, floor, attributeName)

	if not value then
		return nil
	end

	return math.max(1, math.floor(value + 0.5))
end

local function getExpectedTileCount(layout, templateModel, floor)
	if isPositiveInteger(layout.TileCount) then
		return layout.TileCount
	end

	local templateTileCount = getPositiveIntegerAttribute(templateModel, floor, "TileCount")
	if templateTileCount then
		return templateTileCount
	end

	return nil
end

local function findTileMaskFolder(roomFolder)
	local tileMaskFolder = roomFolder and roomFolder:FindFirstChild("TileMask")

	if tileMaskFolder and tileMaskFolder:IsA("Folder") then
		return tileMaskFolder
	end

	return nil
end

local function validateInvisibleMarker(part, markerName, issues, expectedCanQuery)
	if not part then
		return
	end

	if part.Anchored ~= true then
		appendIssue(issues.warnings, markerName .. " should be Anchored = true.")
	end

	if part.CanCollide ~= false then
		appendIssue(issues.warnings, markerName .. " should be CanCollide = false.")
	end

	if part.CanTouch ~= false then
		appendIssue(issues.warnings, markerName .. " should be CanTouch = false.")
	end

	if part.CanQuery ~= expectedCanQuery then
		appendIssue(issues.warnings, markerName .. " should be CanQuery = " .. tostring(expectedCanQuery) .. ".")
	end

	if part.Transparency < 1 then
		appendIssue(issues.warnings, markerName .. " is visible; set Transparency = 1 after testing.")
	end
end

local function validateTileMaskMarkerProperties(marker, tileSize, issues)
	if marker.Anchored ~= true then
		appendIssue(issues.warnings, marker.Name .. " should be Anchored = true.")
	end

	if marker.CanCollide ~= false then
		appendIssue(issues.warnings, marker.Name .. " should be CanCollide = false.")
	end

	if marker.CanTouch ~= false then
		appendIssue(issues.warnings, marker.Name .. " should be CanTouch = false.")
	end

	if marker.CanQuery ~= true then
		appendIssue(issues.warnings, marker.Name .. " should be CanQuery = true.")
	end

	if marker.Transparency < 1 then
		appendIssue(issues.warnings, marker.Name .. " should use Transparency = 1.")
	end

	if tileSize then
		if math.abs(marker.Size.X - tileSize) > TILE_MARKER_SIZE_TOLERANCE then
			appendIssue(
				issues.warnings,
				string.format("%s Size.X is %.2f, expected about TileSize %.2f.", marker.Name, marker.Size.X, tileSize)
			)
		end

		if math.abs(marker.Size.Z - tileSize) > TILE_MARKER_SIZE_TOLERANCE then
			appendIssue(
				issues.warnings,
				string.format("%s Size.Z is %.2f, expected about TileSize %.2f.", marker.Name, marker.Size.Z, tileSize)
			)
		end
	end
end

local function getEntryWalkTargetCell(floor, entryWalkTarget, tileSize, gridWidth, gridDepth)
	if not floor or not entryWalkTarget or not tileSize or not gridWidth or not gridDepth then
		return nil, nil
	end

	local localPosition = floor.CFrame:PointToObjectSpace(entryWalkTarget.Position)
	local minCenterX = -(gridWidth * tileSize) / 2 + tileSize / 2
	local minCenterZ = -(gridDepth * tileSize) / 2 + tileSize / 2
	local tileX = math.floor(((localPosition.X - minCenterX) / tileSize) + 0.5) + 1
	local tileZ = math.floor(((localPosition.Z - minCenterZ) / tileSize) + 0.5) + 1

	return tileX, tileZ
end

local function validateEntryWalkTargetMaskCell(entryWalkTarget, floor, gridInfo, cells, issues)
	if not entryWalkTarget then
		return
	end

	local tileX, tileZ = getEntryWalkTargetCell(
		floor,
		entryWalkTarget,
		gridInfo.TileSize,
		gridInfo.GridWidth,
		gridInfo.GridDepth
	)

	if not tileX or not tileZ then
		appendIssue(issues.warnings, "Could not map EntryWalkTarget to a TileMask cell.")
		return
	end

	if tileX < 1 or tileX > gridInfo.GridWidth or tileZ < 1 or tileZ > gridInfo.GridDepth then
		appendIssue(
			issues.warnings,
			string.format("EntryWalkTarget maps outside TileMask grid at TileX=%d TileZ=%d.", tileX, tileZ)
		)
		return
	end

	if cells[cellKey(tileX, tileZ)] ~= true then
		appendIssue(
			issues.warnings,
			string.format("EntryWalkTarget maps to non-walkable TileMask cell TileX=%d TileZ=%d.", tileX, tileZ)
		)
	end
end

local function validateTileMaskMarker(marker, gridInfo, cells, stats, issues)
	if not marker:IsA("BasePart") then
		stats.invalidMarkers += 1
		appendIssue(issues.errors, marker.Name .. " in Room/TileMask must be a BasePart.")
		return
	end

	local rawTileX = marker:GetAttribute("TileX")
	local rawTileZ = marker:GetAttribute("TileZ")
	local hasValidTileX = isInteger(rawTileX)
	local hasValidTileZ = isInteger(rawTileZ)
	local isWalkableTile = marker:GetAttribute("IsWalkableTile") == true
	local hasCoordinateError = false

	if not hasValidTileX then
		hasCoordinateError = true
		appendIssue(issues.errors, marker.Name .. " has missing or non-integer TileX.")
	end

	if not hasValidTileZ then
		hasCoordinateError = true
		appendIssue(issues.errors, marker.Name .. " has missing or non-integer TileZ.")
	end

	if not isWalkableTile then
		if hasValidTileX and hasValidTileZ then
			appendIssue(issues.warnings, marker.Name .. " has TileX/TileZ but missing IsWalkableTile = true.")
		else
			appendIssue(issues.errors, marker.Name .. " is missing IsWalkableTile = true.")
		end
	end

	if hasCoordinateError or not isWalkableTile then
		stats.invalidMarkers += 1
		return
	end

	if rawTileX < 1 or rawTileX > gridInfo.GridWidth then
		stats.invalidMarkers += 1
		appendIssue(
			issues.errors,
			string.format("%s TileX=%d is outside GridWidth 1..%d.", marker.Name, rawTileX, gridInfo.GridWidth)
		)
		return
	end

	if rawTileZ < 1 or rawTileZ > gridInfo.GridDepth then
		stats.invalidMarkers += 1
		appendIssue(
			issues.errors,
			string.format("%s TileZ=%d is outside GridDepth 1..%d.", marker.Name, rawTileZ, gridInfo.GridDepth)
		)
		return
	end

	local key = cellKey(rawTileX, rawTileZ)

	if cells[key] == true then
		stats.duplicates += 1
		appendIssue(issues.errors, string.format("Duplicate TileMask cell TileX=%d TileZ=%d.", rawTileX, rawTileZ))
		return
	end

	cells[key] = true
	stats.validCells += 1
	validateTileMaskMarkerProperties(marker, gridInfo.TileSize, issues)
end

local function validateTileMask(layout, templateModel, roomFolder, floor, entryWalkTarget, gridInfo, issues)
	local expectedTileCount = getExpectedTileCount(layout, templateModel, floor)
	local tileMaskFolder = findTileMaskFolder(roomFolder)
	local stats = {
		validCells = 0,
		duplicates = 0,
		invalidMarkers = 0,
	}

	if not tileMaskFolder then
		appendIssue(issues.errors, "UsesTileMask = true requires Room/TileMask folder.")
		appendSummary(issues, "TileMask: cells=0 expected=" .. tostring(expectedTileCount or "unknown") .. " duplicates=0 invalid=0")
		return
	end

	if not gridInfo.TileSize then
		appendIssue(issues.errors, "UsesTileMask = true requires positive TileSize.")
	end

	if not gridInfo.GridWidth then
		appendIssue(issues.errors, "UsesTileMask = true requires positive GridWidth.")
	end

	if not gridInfo.GridDepth then
		appendIssue(issues.errors, "UsesTileMask = true requires positive GridDepth.")
	end

	if not expectedTileCount then
		appendIssue(issues.errors, "UsesTileMask = true requires positive TileCount.")
	end

	if not gridInfo.TileSize or not gridInfo.GridWidth or not gridInfo.GridDepth then
		appendSummary(
			issues,
			"TileMask: cells=0 expected=" .. tostring(expectedTileCount or "unknown") .. " duplicates=0 invalid=0"
		)
		return
	end

	local cells = {}

	for _, marker in ipairs(tileMaskFolder:GetChildren()) do
		validateTileMaskMarker(marker, gridInfo, cells, stats, issues)
	end

	if expectedTileCount and stats.validCells ~= expectedTileCount then
		appendIssue(
			issues.errors,
			string.format("TileMask has %d unique walkable cell(s), expected TileCount %d.", stats.validCells, expectedTileCount)
		)
	end

	validateEntryWalkTargetMaskCell(entryWalkTarget, floor, gridInfo, cells, issues)
	appendSummary(
		issues,
		string.format(
			"TileMask: cells=%d expected=%s duplicates=%d invalid=%d",
			stats.validCells,
			tostring(expectedTileCount or "unknown"),
			stats.duplicates,
			stats.invalidMarkers
		)
	)
end

local function validateGrid(layout, templateModel, floor, issues)
	local usesTileGrid = getBooleanAttribute(templateModel, floor, "UsesTileGrid")
	local usesTileMask = getBooleanAttribute(templateModel, floor, "UsesTileMask") == true

	if usesTileGrid == false then
		appendIssue(issues.warnings, "UsesTileGrid = false; current owned-room movement is grid-oriented.")
		return {
			TileSize = nil,
			GridWidth = nil,
			GridDepth = nil,
			UsesTileMask = false,
		}
	end

	if usesTileGrid == nil then
		appendIssue(issues.warnings, "Missing UsesTileGrid attribute; recommended value is true.")
	end

	local tileSize = getPositiveNumberAttribute(templateModel, floor, "TileSize")
	local gridWidth = getPositiveIntegerAttribute(templateModel, floor, "GridWidth")
	local gridDepth = getPositiveIntegerAttribute(templateModel, floor, "GridDepth")

	if not tileSize then
		appendIssue(issues.warnings, "Missing positive TileSize attribute; recommended value is 4.")
		tileSize = DEFAULT_TILE_SIZE
	end

	if not gridWidth then
		appendIssue(issues.warnings, "Missing positive GridWidth attribute.")
	end

	if not gridDepth then
		appendIssue(issues.warnings, "Missing positive GridDepth attribute.")
	end

	if tileSize and gridWidth and gridDepth and usesTileMask ~= true then
		local expectedX = gridWidth * tileSize
		local expectedZ = gridDepth * tileSize

		if math.abs(floor.Size.X - expectedX) > FLOOR_SIZE_TOLERANCE then
			appendIssue(
				issues.warnings,
				string.format(
					"WalkableFloor.Size.X is %.2f, expected about %.2f from GridWidth * TileSize.",
					floor.Size.X,
					expectedX
				)
			)
		end

		if math.abs(floor.Size.Z - expectedZ) > FLOOR_SIZE_TOLERANCE then
			appendIssue(
				issues.warnings,
				string.format(
					"WalkableFloor.Size.Z is %.2f, expected about %.2f from GridDepth * TileSize.",
					floor.Size.Z,
					expectedZ
				)
			)
		end
	end

	if layout.LayoutId == "Free_036_A" then
		if tileSize ~= 4 then
			appendIssue(issues.warnings, "Free_036_A should use TileSize = 4.")
		end

		if gridWidth ~= 6 then
			appendIssue(issues.warnings, "Free_036_A should use GridWidth = 6.")
		end

		if gridDepth ~= 6 then
			appendIssue(issues.warnings, "Free_036_A should use GridDepth = 6.")
		end
	elseif layout.LayoutId == "Free_080_A" then
		if tileSize ~= 4 then
			appendIssue(issues.warnings, "Free_080_A should use TileSize = 4.")
		end

		if gridWidth ~= 10 then
			appendIssue(issues.warnings, "Free_080_A should use GridWidth = 10.")
		end

		if gridDepth ~= 8 then
			appendIssue(issues.warnings, "Free_080_A should use GridDepth = 8.")
		end
	elseif layout.LayoutId == "Free_080_B" then
		if tileSize ~= 4 then
			appendIssue(issues.warnings, "Free_080_B should use TileSize = 4.")
		end

		if gridWidth ~= 8 then
			appendIssue(issues.warnings, "Free_080_B should use GridWidth = 8.")
		end

		if gridDepth ~= 10 then
			appendIssue(issues.warnings, "Free_080_B should use GridDepth = 10.")
		end
	elseif layout.LayoutId == "VIP_080_A" then
		if tileSize ~= 4 then
			appendIssue(issues.warnings, "VIP_080_A should use TileSize = 4.")
		end

		if gridWidth ~= 8 then
			appendIssue(issues.warnings, "VIP_080_A should use GridWidth = 8.")
		end

		if gridDepth ~= 10 then
			appendIssue(issues.warnings, "VIP_080_A should use GridDepth = 10.")
		end
	elseif layout.LayoutId == "VIP_208_A" then
		if tileSize ~= 4 then
			appendIssue(issues.warnings, "VIP_208_A should use TileSize = 4.")
		end

		if gridWidth ~= 13 then
			appendIssue(issues.warnings, "VIP_208_A should use GridWidth = 13.")
		end

		if gridDepth ~= 16 then
			appendIssue(issues.warnings, "VIP_208_A should use GridDepth = 16.")
		end
	elseif layout.LayoutId == "VIP_304_A" then
		if tileSize ~= 4 then
			appendIssue(issues.warnings, "VIP_304_A should use TileSize = 4.")
		end

		if gridWidth ~= 19 then
			appendIssue(issues.warnings, "VIP_304_A should use GridWidth = 19.")
		end

		if gridDepth ~= 16 then
			appendIssue(issues.warnings, "VIP_304_A should use GridDepth = 16.")
		end
	elseif layout.LayoutId == "Free_084_A" then
		if tileSize ~= 4 then
			appendIssue(issues.warnings, "Free_084_A should use TileSize = 4.")
		end

		if gridWidth ~= 7 then
			appendIssue(issues.warnings, "Free_084_A should use GridWidth = 7.")
		end

		if gridDepth ~= 12 then
			appendIssue(issues.warnings, "Free_084_A should use GridDepth = 12.")
		end
	elseif layout.LayoutId == "Free_104_A" then
		if tileSize ~= 4 then
			appendIssue(issues.warnings, "Free_104_A should use TileSize = 4.")
		end

		if gridWidth ~= 13 then
			appendIssue(issues.warnings, "Free_104_A should use GridWidth = 13.")
		end

		if gridDepth ~= 8 then
			appendIssue(issues.warnings, "Free_104_A should use GridDepth = 8.")
		end
	elseif layout.LayoutId == "Free_320_A" then
		if tileSize ~= 4 then
			appendIssue(issues.warnings, "Free_320_A should use TileSize = 4.")
		end

		if gridWidth ~= 20 then
			appendIssue(issues.warnings, "Free_320_A should use GridWidth = 20.")
		end

		if gridDepth ~= 16 then
			appendIssue(issues.warnings, "Free_320_A should use GridDepth = 16.")
		end
	elseif layout.LayoutId == "Free_352_A" then
		if tileSize ~= 4 then
			appendIssue(issues.warnings, "Free_352_A should use TileSize = 4.")
		end

		if gridWidth ~= 22 then
			appendIssue(issues.warnings, "Free_352_A should use GridWidth = 22.")
		end

		if gridDepth ~= 16 then
			appendIssue(issues.warnings, "Free_352_A should use GridDepth = 16.")
		end
	elseif layout.LayoutId == "Free_384_A" then
		if tileSize ~= 4 then
			appendIssue(issues.warnings, "Free_384_A should use TileSize = 4.")
		end

		if gridWidth ~= 24 then
			appendIssue(issues.warnings, "Free_384_A should use GridWidth = 24.")
		end

		if gridDepth ~= 16 then
			appendIssue(issues.warnings, "Free_384_A should use GridDepth = 16.")
		end
	elseif layout.LayoutId == "Free_416_A" then
		if tileSize ~= 4 then
			appendIssue(issues.warnings, "Free_416_A should use TileSize = 4.")
		end

		if gridWidth ~= 26 then
			appendIssue(issues.warnings, "Free_416_A should use GridWidth = 26.")
		end

		if gridDepth ~= 16 then
			appendIssue(issues.warnings, "Free_416_A should use GridDepth = 16.")
		end
	end

	return {
		TileSize = tileSize,
		GridWidth = gridWidth,
		GridDepth = gridDepth,
		UsesTileMask = usesTileMask,
	}
end

local function validateTemplate(layout, templateModel)
	local issues = {
		errors = {},
		warnings = {},
		summaries = {},
	}

	if not templateModel:IsA("Model") then
		appendIssue(issues.errors, "Template must be a Model.")
		return issues
	end

	local roomAnchor = findBasePart(templateModel, "RoomAnchor")
	local doorSpawn = findBasePart(templateModel, "DoorSpawn")
	local entryWalkTarget = findBasePart(templateModel, "EntryWalkTarget")
	local roomExitZone = findRoomExitPart(templateModel)
	local walkableFloor, descendantFloorFallback = findWalkableFloor(templateModel)
	local roomFolder = templateModel:FindFirstChild("Room")
	local furnitureFolder = templateModel:FindFirstChild("Furniture")

	if not roomAnchor then
		appendIssue(issues.errors, "Missing RoomAnchor BasePart.")
	end

	if not doorSpawn then
		appendIssue(issues.errors, "Missing DoorSpawn BasePart.")
	end

	if not entryWalkTarget then
		appendIssue(issues.errors, "Missing EntryWalkTarget BasePart.")
	end

	if not roomFolder or not roomFolder:IsA("Folder") then
		appendIssue(issues.errors, "Missing Room folder.")
	end

	if not walkableFloor then
		appendIssue(issues.errors, "Missing Room/WalkableFloor BasePart.")
	elseif descendantFloorFallback then
		appendIssue(issues.warnings, "WalkableFloor exists outside Room folder; prefer Room.WalkableFloor.")
	end

	if not roomExitZone then
		appendIssue(issues.errors, "Missing RoomExitZone BasePart or BasePart with IsRoomExit = true.")
	elseif roomExitZone:GetAttribute("IsRoomExit") ~= true then
		appendIssue(issues.warnings, "RoomExitZone should have IsRoomExit = true.")
	end

	if not furnitureFolder then
		appendIssue(issues.warnings, "Missing recommended Furniture folder.")
	elseif not furnitureFolder:IsA("Folder") then
		appendIssue(issues.warnings, "Furniture exists but is not a Folder.")
	end

	validateInvisibleMarker(roomAnchor, "RoomAnchor", issues, false)
	validateInvisibleMarker(doorSpawn, "DoorSpawn", issues, false)
	validateInvisibleMarker(entryWalkTarget, "EntryWalkTarget", issues, false)
	validateInvisibleMarker(roomExitZone, "RoomExitZone", issues, true)

	if walkableFloor then
		if walkableFloor.Anchored ~= true then
			appendIssue(issues.warnings, "WalkableFloor should be Anchored = true.")
		end

		if walkableFloor.CanCollide ~= true then
			appendIssue(issues.warnings, "WalkableFloor should be CanCollide = true.")
		end

		if walkableFloor.CanTouch ~= false then
			appendIssue(issues.warnings, "WalkableFloor should be CanTouch = false.")
		end

		if walkableFloor.CanQuery ~= true then
			appendIssue(issues.warnings, "WalkableFloor should be CanQuery = true.")
		end

		local gridInfo = validateGrid(layout, templateModel, walkableFloor, issues)

		if gridInfo and gridInfo.UsesTileMask == true then
			validateTileMask(layout, templateModel, roomFolder, walkableFloor, entryWalkTarget, gridInfo, issues)
		end
	end

	return issues
end

local function templateUsesTileMask(templateModel)
	if not templateModel or not templateModel:IsA("Model") then
		return false
	end

	local walkableFloor = findWalkableFloor(templateModel)

	return getBooleanAttribute(templateModel, walkableFloor, "UsesTileMask") == true
end

local roomTemplates = ReplicatedStorage:FindFirstChild("RoomTemplates")

if not roomTemplates then
	warn(TOOL_PREFIX .. " ReplicatedStorage.RoomTemplates is missing.")
end

local availableLayouts = RoomLayoutConfig.GetSelectableLayouts()
local unavailableLayouts = RoomLayoutConfig.GetUnavailableLayouts()
local vipLayouts = RoomLayoutConfig.GetVipLayouts()
local configuredTemplateNames = {}
local missingTemplates = 0
local validatedTemplates = 0
local templatesWithErrors = 0
local structuralWarnings = 0
local devMaskedTemplates = 0
local devMaskedTemplatesWithErrors = 0
local devMaskedWarnings = 0

local function addConfiguredTemplateNames(layouts)
	for _, layout in ipairs(layouts) do
		if typeof(layout.TemplateName) == "string" then
			configuredTemplateNames[layout.TemplateName] = true
		end
	end
end

addConfiguredTemplateNames(availableLayouts)
addConfiguredTemplateNames(unavailableLayouts)

print(TOOL_PREFIX .. " Validating " .. tostring(#availableLayouts) .. " available room layout template(s).")

for _, layout in ipairs(availableLayouts) do
	local templateName = layout.TemplateName
	local template = roomTemplates and roomTemplates:FindFirstChild(templateName)

	if not template then
		missingTemplates += 1
		warn(string.format(
			"[WARN] %s missing template=%s",
			tostring(layout.LayoutId),
			tostring(templateName)
		))
	else
		local issues = validateTemplate(layout, template)
		validatedTemplates += 1

		if #issues.errors == 0 and #issues.warnings == 0 then
			print(string.format(
				"[OK] %s template=%s",
				tostring(layout.LayoutId),
				tostring(templateName)
			))
		else
			if #issues.errors > 0 then
				templatesWithErrors += 1
				warn(string.format(
					"[ERROR] %s template=%s has %d structural error(s).",
					tostring(layout.LayoutId),
					tostring(templateName),
					#issues.errors
				))

				for _, message in ipairs(issues.errors) do
					warn("  - " .. message)
				end
			end

			if #issues.warnings > 0 then
				structuralWarnings += #issues.warnings
				warn(string.format(
					"[WARN] %s template=%s has %d warning(s).",
					tostring(layout.LayoutId),
					tostring(templateName),
					#issues.warnings
				))

				for _, message in ipairs(issues.warnings) do
					warn("  - " .. message)
				end
			end
		end

		for _, message in ipairs(issues.summaries) do
			print("  - " .. message)
		end
	end
end

if roomTemplates then
	for _, template in ipairs(roomTemplates:GetChildren()) do
		if template:IsA("Model")
			and configuredTemplateNames[template.Name] ~= true
			and templateUsesTileMask(template) then

			local walkableFloor = findWalkableFloor(template)
			local layout = {
				LayoutId = template:GetAttribute("LayoutId") or template.Name,
				TemplateName = template:GetAttribute("TemplateName") or template.Name,
				TileCount = getPositiveIntegerAttribute(template, walkableFloor, "TileCount"),
			}
			local issues = validateTemplate(layout, template)

			devMaskedTemplates += 1

			if #issues.errors == 0 and #issues.warnings == 0 then
				print(string.format(
					"[OK] [DEV] %s template=%s",
					tostring(layout.LayoutId),
					tostring(layout.TemplateName)
				))
			else
				if #issues.errors > 0 then
					devMaskedTemplatesWithErrors += 1
					warn(string.format(
						"[ERROR] [DEV] %s template=%s has %d structural error(s).",
						tostring(layout.LayoutId),
						tostring(layout.TemplateName),
						#issues.errors
					))

					for _, message in ipairs(issues.errors) do
						warn("  - " .. message)
					end
				end

				if #issues.warnings > 0 then
					devMaskedWarnings += #issues.warnings
					warn(string.format(
						"[WARN] [DEV] %s template=%s has %d warning(s).",
						tostring(layout.LayoutId),
						tostring(layout.TemplateName),
						#issues.warnings
					))

					for _, message in ipairs(issues.warnings) do
						warn("  - " .. message)
					end
				end
			end

			for _, message in ipairs(issues.summaries) do
				print("  - " .. message)
			end
		end
	end
end

print(string.format(
	"%s Summary: available layouts=%d validated templates=%d missing templates=%d templates with errors=%d structural warnings=%d VIP layouts=%d unavailable layouts=%d dev masked templates=%d dev masked templates with errors=%d dev masked warnings=%d",
	TOOL_PREFIX,
	#availableLayouts,
	validatedTemplates,
	missingTemplates,
	templatesWithErrors,
	structuralWarnings,
	#vipLayouts,
	#unavailableLayouts,
	devMaskedTemplates,
	devMaskedTemplatesWithErrors,
	devMaskedWarnings
))
