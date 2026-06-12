-- Run this script from Roblox Studio Command Bar.
-- It prepares one selected imported furniture Model for the furniture pipeline.
-- It modifies only the selected model and does not enable public catalog by default.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")

local TOOL_PREFIX = "[PrepareImportedFurnitureTemplate]"
local FURNITURE_TEMPLATES_FOLDER_NAME = "FurnitureTemplates"
local PLACEMENT_BOUNDS_PART_NAME = "PlacementBounds"
local TILE_SIZE = 4
local FOOTPRINT_MARGIN = 0.4
local PLACEMENT_BOUNDS_HEIGHT = 4

local MOVE_TO_TEMPLATE_FOLDER = false
local AUTO_CATALOG_ENABLED = false
local DEFAULT_CATEGORY = "Other"
local DEFAULT_CURRENCY_KEY = "Dollars"
local DEFAULT_PRICE = 1
local DEFAULT_SELL_PRICE = 0
local DEFAULT_FOOTPRINT_WIDTH = 1
local DEFAULT_FOOTPRINT_DEPTH = 1
local SET_VISUAL_COLLISION = true
local CREATE_PLACEMENT_BOUNDS = true
local SET_PRIMARY_PART_TO_PLACEMENT_BOUNDS = true

local RENAME_UNSAFE_MODEL = false
local REMOVE_EMBEDDED_SCRIPTS = false

local function formatValue(value)
	if typeof(value) == "string" then
		return string.format("%q", value)
	end

	return tostring(value)
end

local function printInfo(message)
	print(TOOL_PREFIX .. " " .. message)
end

local function printWarning(message)
	warn(TOOL_PREFIX .. " [WARN] " .. message)
end

local function stopWithInstructions(message)
	if message then
		printWarning(message)
	end

	printInfo("Select exactly one furniture Model under ReplicatedStorage.FurnitureTemplates, then run this script again.")
end

local function isSafeNameCharacter(byte)
	return byte == 95
		or (byte >= 48 and byte <= 57)
		or (byte >= 65 and byte <= 90)
		or (byte >= 97 and byte <= 122)
end

local function isSafeModelName(name)
	if typeof(name) ~= "string" or name == "" then
		return false
	end

	for index = 1, #name do
		if not isSafeNameCharacter(string.byte(name, index)) then
			return false
		end
	end

	return true
end

local function sanitizeModelName(name)
	local output = {}
	local lastWasUnderscore = false

	for index = 1, #name do
		local byte = string.byte(name, index)

		if isSafeNameCharacter(byte) then
			table.insert(output, string.char(byte))
			lastWasUnderscore = byte == 95
		elseif not lastWasUnderscore then
			table.insert(output, "_")
			lastWasUnderscore = true
		end
	end

	local sanitized = table.concat(output):gsub("^_+", ""):gsub("_+$", "")

	if sanitized == "" then
		sanitized = "ImportedFurniture"
	end

	local firstByte = string.byte(sanitized, 1)

	if firstByte and firstByte >= 48 and firstByte <= 57 then
		sanitized = "Furniture_" .. sanitized
	end

	return sanitized
end

local function getUniqueChildName(parent, preferredName, instanceToIgnore)
	local candidate = preferredName
	local suffix = 2

	while true do
		local existing = parent:FindFirstChild(candidate)

		if not existing or existing == instanceToIgnore then
			return candidate
		end

		candidate = preferredName .. "_" .. tostring(suffix)
		suffix += 1
	end
end

local function getFurnitureTemplatesFolder(createIfMissing)
	local folder = ReplicatedStorage:FindFirstChild(FURNITURE_TEMPLATES_FOLDER_NAME)

	if folder then
		if not folder:IsA("Folder") then
			printWarning("ReplicatedStorage." .. FURNITURE_TEMPLATES_FOLDER_NAME .. " exists but is not a Folder.")
			return nil
		end

		return folder
	end

	if not createIfMissing then
		printWarning("ReplicatedStorage." .. FURNITURE_TEMPLATES_FOLDER_NAME .. " is missing.")
		return nil
	end

	folder = Instance.new("Folder")
	folder.Name = FURNITURE_TEMPLATES_FOLDER_NAME
	folder.Parent = ReplicatedStorage

	printInfo("Created ReplicatedStorage." .. FURNITURE_TEMPLATES_FOLDER_NAME .. ".")
	return folder
end

local function getSelectedModel()
	local selected = Selection:Get()

	if #selected ~= 1 then
		stopWithInstructions("Expected one selected Model; found " .. tostring(#selected) .. " selected instances.")
		return nil
	end

	local selectedInstance = selected[1]

	if not selectedInstance:IsA("Model") then
		stopWithInstructions("Selected instance is a " .. selectedInstance.ClassName .. ", not a Model.")
		return nil
	end

	return selectedInstance
end

local function ensureTemplateFolderMembership(model)
	local furnitureTemplates = getFurnitureTemplatesFolder(MOVE_TO_TEMPLATE_FOLDER)

	if not furnitureTemplates then
		return false
	end

	if model.Parent == furnitureTemplates then
		return true
	end

	if not MOVE_TO_TEMPLATE_FOLDER then
		printWarning(
			model.Name
				.. " is not a direct child of ReplicatedStorage."
				.. FURNITURE_TEMPLATES_FOLDER_NAME
				.. "."
		)
		printInfo("Set MOVE_TO_TEMPLATE_FOLDER = true near the top of this tool if you want it moved automatically.")
		return false
	end

	model.Parent = furnitureTemplates
	printInfo("Moved " .. model.Name .. " to ReplicatedStorage." .. FURNITURE_TEMPLATES_FOLDER_NAME .. ".")
	return true
end

local function validateOrRenameModel(model)
	if isSafeModelName(model.Name) then
		return
	end

	printWarning("Model name '" .. model.Name .. "' contains spaces, non-ASCII, or unsafe characters.")

	if not RENAME_UNSAFE_MODEL then
		printInfo("Set RENAME_UNSAFE_MODEL = true near the top of this tool to auto-sanitize the model name.")
		return
	end

	local parent = model.Parent
	local sanitizedName = sanitizeModelName(model.Name)

	if parent then
		sanitizedName = getUniqueChildName(parent, sanitizedName, model)
	end

	printInfo("Renamed model from '" .. model.Name .. "' to '" .. sanitizedName .. "'.")
	model.Name = sanitizedName
end

local function ensureAttributes(model)
	local added = {}
	local kept = {}
	local attributes = {
		{ Name = "AutoCatalogEnabled", Value = AUTO_CATALOG_ENABLED },
		{ Name = "DisplayName", Value = model.Name },
		{ Name = "Description", Value = "" },
		{ Name = "Category", Value = DEFAULT_CATEGORY },
		{ Name = "CurrencyKey", Value = DEFAULT_CURRENCY_KEY },
		{ Name = "Price", Value = DEFAULT_PRICE },
		{ Name = "SellPrice", Value = DEFAULT_SELL_PRICE },
		{ Name = "TradableOnPurchase", Value = false },
		{ Name = "SellableOnPurchase", Value = true },
		{ Name = "FootprintWidth", Value = DEFAULT_FOOTPRINT_WIDTH },
		{ Name = "FootprintDepth", Value = DEFAULT_FOOTPRINT_DEPTH },
	}

	for _, attribute in ipairs(attributes) do
		local currentValue = model:GetAttribute(attribute.Name)

		if currentValue == nil then
			model:SetAttribute(attribute.Name, attribute.Value)
			table.insert(added, attribute.Name .. "=" .. formatValue(attribute.Value))
		else
			table.insert(kept, attribute.Name .. "=" .. formatValue(currentValue))
		end
	end

	return added, kept
end

local function getPositiveIntegerAttribute(model, attributeName, fallbackValue)
	local value = model:GetAttribute(attributeName)

	if typeof(value) == "number"
		and value == value
		and value > 0
		and value < math.huge
		and math.floor(value) == value then

		return value
	end

	printWarning(attributeName .. " is missing or invalid; using " .. tostring(fallbackValue) .. " for PlacementBounds sizing.")
	return fallbackValue
end

local function findPlacementBounds(model)
	local boundsParts = {}
	local nonPartMatches = {}

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant.Name == PLACEMENT_BOUNDS_PART_NAME then
			if descendant:IsA("BasePart") then
				table.insert(boundsParts, descendant)
			else
				table.insert(nonPartMatches, descendant)
			end
		end
	end

	for _, instance in ipairs(nonPartMatches) do
		printWarning(
			instance:GetFullName()
				.. " is named "
				.. PLACEMENT_BOUNDS_PART_NAME
				.. " but is a "
				.. instance.ClassName
				.. "."
		)
	end

	if #boundsParts > 1 then
		printWarning("Multiple BaseParts named " .. PLACEMENT_BOUNDS_PART_NAME .. " found; updating the first one.")
	end

	return boundsParts[1]
end

local function ensurePlacementBounds(model)
	if not CREATE_PLACEMENT_BOUNDS then
		printInfo("CREATE_PLACEMENT_BOUNDS = false; PlacementBounds was not created or updated.")
		return nil, "skipped"
	end

	local bounds = findPlacementBounds(model)
	local status = "updated"

	if not bounds then
		bounds = Instance.new("Part")
		bounds.Name = PLACEMENT_BOUNDS_PART_NAME
		bounds.Parent = model
		status = "created"
	end

	local footprintWidth = getPositiveIntegerAttribute(model, "FootprintWidth", DEFAULT_FOOTPRINT_WIDTH)
	local footprintDepth = getPositiveIntegerAttribute(model, "FootprintDepth", DEFAULT_FOOTPRINT_DEPTH)
	local size = Vector3.new(
		footprintWidth * TILE_SIZE - FOOTPRINT_MARGIN,
		PLACEMENT_BOUNDS_HEIGHT,
		footprintDepth * TILE_SIZE - FOOTPRINT_MARGIN
	)

	bounds.Size = size
	bounds.CFrame = model:GetPivot() * CFrame.new(0, PLACEMENT_BOUNDS_HEIGHT / 2, 0)
	bounds.Transparency = 1
	bounds.Anchored = true
	bounds.CanCollide = false
	bounds.CanTouch = false
	bounds.CanQuery = true
	bounds.CastShadow = false
	bounds.TopSurface = Enum.SurfaceType.Smooth
	bounds.BottomSurface = Enum.SurfaceType.Smooth

	return bounds, status
end

local function hasTrueAttribute(instance, attributeNames)
	for _, attributeName in ipairs(attributeNames) do
		if instance:GetAttribute(attributeName) == true then
			return true
		end
	end

	return false
end

local function setPropertyIfDifferent(instance, propertyName, value)
	if instance[propertyName] == value then
		return false
	end

	instance[propertyName] = value
	return true
end

local function prepareVisualParts(model)
	if not SET_VISUAL_COLLISION then
		return 0, 0, 0
	end

	local visualPartCount = 0
	local adjustedCount = 0
	local seatCount = 0

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart")
			and descendant.Name ~= PLACEMENT_BOUNDS_PART_NAME then

			visualPartCount += 1
			local changed = false

			if descendant:IsA("Seat") or descendant:IsA("VehicleSeat") then
				seatCount += 1
				changed = setPropertyIfDifferent(descendant, "Anchored", true) or changed
			else
				changed = setPropertyIfDifferent(descendant, "Anchored", true) or changed
				changed = setPropertyIfDifferent(descendant, "CanTouch", false) or changed

				if not hasTrueAttribute(descendant, { "KeepCanQuery", "InteractivePart" }) then
					changed = setPropertyIfDifferent(descendant, "CanQuery", false) or changed
				end

				if not hasTrueAttribute(descendant, { "BlocksMovement", "KeepCanCollide" }) then
					changed = setPropertyIfDifferent(descendant, "CanCollide", false) or changed
				end
			end

			if changed then
				adjustedCount += 1
			end
		end
	end

	return adjustedCount, visualPartCount, seatCount
end

local function detectEmbeddedScripts(model)
	local scripts = {}

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Script")
			or descendant:IsA("LocalScript")
			or descendant:IsA("ModuleScript") then

			table.insert(scripts, descendant)
		end
	end

	if #scripts <= 0 then
		return scripts, 0
	end

	printWarning("Embedded scripts were detected. Review imported assets before using this template.")

	for _, scriptInstance in ipairs(scripts) do
		printWarning("Script descendant: " .. scriptInstance:GetFullName() .. " (" .. scriptInstance.ClassName .. ")")
	end

	if not REMOVE_EMBEDDED_SCRIPTS then
		printInfo("Set REMOVE_EMBEDDED_SCRIPTS = true near the top of this tool to remove embedded scripts automatically.")
		return scripts, 0
	end

	local removedCount = 0

	for _, scriptInstance in ipairs(scripts) do
		scriptInstance:Destroy()
		removedCount += 1
	end

	printInfo("Removed " .. tostring(removedCount) .. " embedded script descendants.")
	return scripts, removedCount
end

local function formatList(list)
	if #list <= 0 then
		return "none"
	end

	return table.concat(list, ", ")
end

local model = getSelectedModel()

if not model then
	return
end

printInfo("Preparing selected model: " .. model.Name)

if not ensureTemplateFolderMembership(model) then
	return
end

validateOrRenameModel(model)

local addedAttributes, keptAttributes = ensureAttributes(model)
local placementBounds, placementBoundsStatus = ensurePlacementBounds(model)
local primaryPartResult = "unchanged"

if SET_PRIMARY_PART_TO_PLACEMENT_BOUNDS then
	if placementBounds then
		model.PrimaryPart = placementBounds
		primaryPartResult = placementBounds:GetFullName()
	else
		primaryPartResult = "not set; PlacementBounds is unavailable"
	end
end

local adjustedVisualParts, visualPartCount, seatCount = prepareVisualParts(model)
local scriptsDetected, scriptsRemoved = detectEmbeddedScripts(model)

printInfo("Prepared model: " .. model.Name)
printInfo("Attributes added: " .. formatList(addedAttributes))
printInfo("Attributes kept: " .. formatList(keptAttributes))

if placementBounds then
	printInfo(
		"PlacementBounds "
			.. placementBoundsStatus
			.. "; Size = "
			.. tostring(placementBounds.Size)
	)
else
	printInfo("PlacementBounds " .. placementBoundsStatus .. ".")
end

printInfo("PrimaryPart: " .. primaryPartResult)
printInfo(
	"Visual parts adjusted: "
		.. tostring(adjustedVisualParts)
		.. " / "
		.. tostring(visualPartCount)
		.. "; Seat parts preserved: "
		.. tostring(seatCount)
)
printInfo(
	"Embedded scripts detected: "
		.. tostring(#scriptsDetected)
		.. "; removed: "
		.. tostring(scriptsRemoved)
)
printInfo("AutoCatalogEnabled defaults to false. Review the template before enabling public catalog exposure.")
printInfo("Next: run docs/tools/ValidateFurnitureTemplates.lua in Studio.")
