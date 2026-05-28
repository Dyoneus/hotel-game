-- Studio helper: validate configured public room templates.
--
-- Run this manually in Roblox Studio Command Bar or from a temporary Script.
-- The helper reads ReplicatedStorage.PublicRoomTemplates first, then falls back
-- to ReplicatedStorage.RoomTemplates for template names from PublicRoomConfig.
-- It does not create, delete, or modify instances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TOOL_PREFIX = "[PublicRoomTemplateValidator]"
local DEFAULT_TILE_SIZE = 4
local FLOOR_SIZE_TOLERANCE = 0.15

local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
local publicRoomConfigModule = sharedFolder and sharedFolder:FindFirstChild("PublicRoomConfig")

if not publicRoomConfigModule or not publicRoomConfigModule:IsA("ModuleScript") then
	error(TOOL_PREFIX .. " Missing ReplicatedStorage.Shared.PublicRoomConfig.")
end

local success, PublicRoomConfig = pcall(require, publicRoomConfigModule)

if not success or typeof(PublicRoomConfig) ~= "table" then
	error(TOOL_PREFIX .. " Could not require PublicRoomConfig: " .. tostring(PublicRoomConfig))
end

local function getRoomsArray()
	if typeof(PublicRoomConfig.GetPublicRoomsArray) == "function" then
		return PublicRoomConfig.GetPublicRoomsArray()
	end

	local rooms = {}

	if typeof(PublicRoomConfig.PublicRooms) == "table" then
		for _, roomConfig in pairs(PublicRoomConfig.PublicRooms) do
			table.insert(rooms, roomConfig)
		end
	end

	table.sort(rooms, function(a, b)
		local aOrder = typeof(a.SortOrder) == "number" and a.SortOrder or math.huge
		local bOrder = typeof(b.SortOrder) == "number" and b.SortOrder or math.huge

		if aOrder == bOrder then
			return tostring(a.DisplayName or a.Id) < tostring(b.DisplayName or b.Id)
		end

		return aOrder < bOrder
	end)

	return rooms
end

local function getAttribute(instance, attributeName)
	if not instance then
		return nil
	end

	return instance:GetAttribute(attributeName)
end

local function getBooleanAttribute(model, floor, attributeName)
	local modelValue = getAttribute(model, attributeName)

	if typeof(modelValue) == "boolean" then
		return modelValue
	end

	local floorValue = getAttribute(floor, attributeName)

	if typeof(floorValue) == "boolean" then
		return floorValue
	end

	return nil
end

local function getPositiveNumberAttribute(model, floor, attributeName)
	local modelValue = getAttribute(model, attributeName)

	if typeof(modelValue) == "number" and modelValue > 0 and modelValue < math.huge then
		return modelValue
	end

	local floorValue = getAttribute(floor, attributeName)

	if typeof(floorValue) == "number" and floorValue > 0 and floorValue < math.huge then
		return floorValue
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

local function findTemplate(templateName)
	local publicTemplates = ReplicatedStorage:FindFirstChild("PublicRoomTemplates")

	if publicTemplates then
		local template = publicTemplates:FindFirstChild(templateName)

		if template then
			return template, "ReplicatedStorage.PublicRoomTemplates"
		end
	end

	local roomTemplates = ReplicatedStorage:FindFirstChild("RoomTemplates")

	if roomTemplates then
		local template = roomTemplates:FindFirstChild(templateName)

		if template then
			return template, "ReplicatedStorage.RoomTemplates"
		end
	end

	return nil, nil
end

local function appendIssue(issues, message)
	table.insert(issues, message)
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

local function validateGrid(templateModel, floor, issues)
	local usesTileGrid = getBooleanAttribute(templateModel, floor, "UsesTileGrid")

	if usesTileGrid == false then
		appendIssue(
			issues.warnings,
			"UsesTileGrid = false; current public room movement is still grid-oriented."
		)
		return
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

	if tileSize and gridWidth and gridDepth then
		local expectedX = gridWidth * tileSize
		local expectedZ = gridDepth * tileSize
		local xDelta = math.abs(floor.Size.X - expectedX)
		local zDelta = math.abs(floor.Size.Z - expectedZ)

		if xDelta > FLOOR_SIZE_TOLERANCE then
			appendIssue(
				issues.warnings,
				string.format(
					"WalkableFloor.Size.X is %.2f, expected about %.2f from GridWidth * TileSize.",
					floor.Size.X,
					expectedX
				)
			)
		end

		if zDelta > FLOOR_SIZE_TOLERANCE then
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
end

local function validateTemplate(roomConfig)
	local issues = {
		errors = {},
		warnings = {},
	}

	local publicRoomId = tostring(roomConfig.PublicRoomId or roomConfig.Id or "")
	local templateName = roomConfig.TemplateName

	if typeof(roomConfig.PublicRoomId) ~= "string" or roomConfig.PublicRoomId == "" then
		appendIssue(issues.warnings, "Missing PublicRoomId metadata.")
	end

	if typeof(roomConfig.DisplayName) ~= "string" or roomConfig.DisplayName == "" then
		appendIssue(issues.warnings, "Missing DisplayName metadata.")
	end

	if typeof(roomConfig.Category) ~= "string" or roomConfig.Category == "" then
		appendIssue(issues.warnings, "Missing Category metadata.")
	end

	if typeof(roomConfig.Description) ~= "string" or roomConfig.Description == "" then
		appendIssue(issues.warnings, "Missing Description metadata.")
	end

	if typeof(roomConfig.MaxOccupancy) ~= "number"
		or roomConfig.MaxOccupancy <= 0
		or roomConfig.MaxOccupancy ~= math.floor(roomConfig.MaxOccupancy) then

		appendIssue(issues.warnings, "Missing positive integer MaxOccupancy metadata.")
	end

	if typeof(roomConfig.SortOrder) ~= "number" then
		appendIssue(issues.warnings, "Missing numeric SortOrder metadata.")
	end

	if typeof(roomConfig.IsOpen) ~= "boolean" then
		appendIssue(issues.warnings, "Missing boolean IsOpen metadata.")
	end

	if typeof(roomConfig.Tags) ~= "table" or #roomConfig.Tags == 0 then
		appendIssue(issues.warnings, "Missing Tags metadata.")
	end

	if typeof(roomConfig.Theme) ~= "string" or roomConfig.Theme == "" then
		appendIssue(issues.warnings, "Missing Theme metadata.")
	end

	if typeof(roomConfig.IconImageId) ~= "string"
		and typeof(roomConfig.ThumbnailImageId) ~= "string" then

		appendIssue(issues.warnings, "Missing optional IconImageId or ThumbnailImageId placeholder.")
	end

	if typeof(templateName) ~= "string" or templateName == "" then
		appendIssue(issues.errors, "Missing TemplateName in PublicRoomConfig.")
		return nil, nil, issues
	end

	local templateModel, templateSource = findTemplate(templateName)

	if not templateModel then
		appendIssue(
			issues.errors,
			"Missing template " .. templateName .. " in PublicRoomTemplates or RoomTemplates."
		)
		return nil, nil, issues
	end

	if not templateModel:IsA("Model") then
		appendIssue(issues.errors, "Template " .. templateName .. " must be a Model.")
		return templateModel, templateSource, issues
	end

	local roomAnchor = findBasePart(templateModel, "RoomAnchor")
	local doorSpawn = findBasePart(templateModel, "DoorSpawn")
	local entryWalkTarget = findBasePart(templateModel, "EntryWalkTarget")
	local roomExitZone = findRoomExitPart(templateModel)
	local walkableFloor, descendantFloorFallback = findWalkableFloor(templateModel)
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

	if not roomExitZone then
		appendIssue(issues.errors, "Missing RoomExitZone BasePart or BasePart with IsRoomExit = true.")
	end

	if not walkableFloor then
		appendIssue(issues.errors, "Missing Room/WalkableFloor BasePart.")
	elseif descendantFloorFallback then
		appendIssue(issues.warnings, "WalkableFloor exists outside Room folder; prefer Room.WalkableFloor.")
	end

	if not furnitureFolder then
		appendIssue(issues.warnings, "Missing recommended Furniture folder.")
	elseif not furnitureFolder:IsA("Folder") then
		appendIssue(issues.warnings, "Furniture exists but is not a Folder.")
	end

	if roomExitZone and roomExitZone:GetAttribute("IsRoomExit") ~= true then
		appendIssue(issues.warnings, "RoomExitZone should have IsRoomExit = true.")
	end

	validateInvisibleMarker(roomAnchor, "RoomAnchor", issues, false)
	validateInvisibleMarker(doorSpawn, "DoorSpawn", issues, false)
	validateInvisibleMarker(entryWalkTarget, "EntryWalkTarget", issues, false)
	validateInvisibleMarker(roomExitZone, "RoomExitZone", issues, true)

	if walkableFloor then
		validateGrid(templateModel, walkableFloor, issues)
	end

	if publicRoomId == "" then
		appendIssue(issues.warnings, "Public room config has an empty Id.")
	end

	return templateModel, templateSource, issues
end

local publicTemplates = ReplicatedStorage:FindFirstChild("PublicRoomTemplates")

if not publicTemplates then
	warn(TOOL_PREFIX .. " ReplicatedStorage.PublicRoomTemplates is missing; fallback RoomTemplates will be checked.")
end

local rooms = getRoomsArray()
local totalRooms = 0
local okRooms = 0
local warnRooms = 0
local errorRooms = 0

print(TOOL_PREFIX .. " Validating " .. tostring(#rooms) .. " public room template(s).")

for _, roomConfig in ipairs(rooms) do
	totalRooms += 1

	local publicRoomId = tostring(roomConfig.Id or roomConfig.DisplayName or "UnknownPublicRoom")
	local templateModel, templateSource, issues = validateTemplate(roomConfig)
	local errorCount = #issues.errors
	local warningCount = #issues.warnings
	local status = "[OK]"

	if errorCount > 0 then
		status = "[ERROR]"
		errorRooms += 1
	elseif warningCount > 0 then
		status = "[WARN]"
		warnRooms += 1
	else
		okRooms += 1
	end

	print(string.format(
		"%s %s template=%s source=%s",
		status,
		publicRoomId,
		tostring(roomConfig.TemplateName),
		tostring(templateSource or "missing")
	))

	if templateModel then
		print("    model=" .. templateModel:GetFullName())
	end

	for _, message in ipairs(issues.errors) do
		warn(string.format("    [ERROR] %s: %s", publicRoomId, message))
	end

	for _, message in ipairs(issues.warnings) do
		warn(string.format("    [WARN] %s: %s", publicRoomId, message))
	end
end

print(string.format(
	"%s Summary: total=%d ok=%d warn=%d error=%d",
	TOOL_PREFIX,
	totalRooms,
	okRooms,
	warnRooms,
	errorRooms
))
