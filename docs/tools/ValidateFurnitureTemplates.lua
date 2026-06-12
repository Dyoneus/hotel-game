-- Run this script from Roblox Studio Command Bar.
-- It inspects ReplicatedStorage.FurnitureTemplates and does not modify instances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TOOL_PREFIX = "[ValidateFurnitureTemplates]"
local SHARED_FOLDER_NAME = "Shared"
local FURNITURE_CATALOG_CONFIG_MODULE_NAME = "FurnitureCatalogConfig"
local FURNITURE_TEMPLATES_FOLDER_NAME = "FurnitureTemplates"
local PLACEMENT_BOUNDS_PART_NAME = "PlacementBounds"

local TILE_SIZE = 4
local FOOTPRINT_MARGIN = 0.4
local PLACEMENT_BOUNDS_TOLERANCE = 0.25
local VISUAL_OVERHANG_TOLERANCE = 0.05
local MAX_FOOTPRINT_TILES = 20
local EXTREME_BOUNDS_XZ_STUDS = TILE_SIZE * (MAX_FOOTPRINT_TILES + 4)
local EXTREME_BOUNDS_Y_STUDS = 80

local CLASSIFICATION = {
	StaticCatalog = "StaticCatalog",
	AutoCatalog = "AutoCatalog",
	InventoryOnlyOrTest = "InventoryOnlyOrTest",
	Unclassified = "Unclassified",
}

local VALID_CATALOG_CATEGORIES = {
	Bed = true,
	Chair = true,
	Divider = true,
	Floor = true,
	Food = true,
	Gate = true,
	Lighting = true,
	Music = true,
	Other = true,
	Pets = true,
	Present = true,
	Roller = true,
	Rug = true,
	Shelf = true,
	Table = true,
	["Wall Decoration"] = true,
	Wallpaper = true,
	Window = true,
}

local LEGACY_CATEGORY_ALIASES = {
	Beds = "Bed",
	Chairs = "Chair",
	Tables = "Table",
}

local KNOWN_LEGACY_STATIC_TEMPLATES = {
	Chair_01 = true,
	Table_01 = true,
	Bed_01 = true,
}

local KNOWN_SPECIAL_CASES = {
	Gate_Test_OpenClose = {
		FootprintWidth = 1,
		FootprintDepth = 1,
		Note = "inventory-only OpenClose test gate; runtime has a one-by-one footprint override path",
	},
	TestGate_01 = {
		FootprintWidth = 1,
		FootprintDepth = 1,
		Note = "known inventory-only/test gate template",
	},
}

local HELPER_PART_NAMES = {
	[PLACEMENT_BOUNDS_PART_NAME] = true,
	CollisionBuffer = true,
	SitPoint = true,
	SleepPoint = true,
	PlayPoint = true,
	EnterPoint = true,
	TalkPoint = true,
	ClickHitbox = true,
	RoomAnchor = true,
	DoorSpawn = true,
}

local ALLOW_UNANCHORED_ATTRIBUTES = {
	"AllowUnanchoredParts",
	"AllowUnanchoredVisualParts",
	"IntentionallyUnanchored",
}

local ALLOW_VISUAL_CAN_QUERY_ATTRIBUTES = {
	"AllowVisualCanQuery",
	"RequiresVisualCanQuery",
	"KeepVisualCanQuery",
}

local PUBLIC_INTERACTION_ATTRIBUTES = {
	"PublicUse",
	"PublicOpenClose",
	"AllowPublicOpenClose",
}

local function createSummary()
	return {
		TotalTemplates = 0,
		StaticCatalog = 0,
		AutoCatalog = 0,
		LegacyStatic = 0,
		StrictPublic = 0,
		InventoryOnlyOrTest = 0,
		Unclassified = 0,
		Passed = 0,
		WarningCount = 0,
		ErrorCount = 0,
		GlobalWarnings = {},
		GlobalErrors = {},
		TemplatesWithWarnings = {},
		TemplatesWithErrors = {},
	}
end

local summary = createSummary()

local function append(list, value)
	table.insert(list, value)
end

local function addGlobalWarning(message)
	summary.WarningCount = summary.WarningCount + 1
	append(summary.GlobalWarnings, message)
	warn(TOOL_PREFIX .. " [WARN] " .. message)
end

local function addGlobalError(message)
	summary.ErrorCount = summary.ErrorCount + 1
	append(summary.GlobalErrors, message)
	warn(TOOL_PREFIX .. " [ERROR] " .. message)
end

local function createReport(model, classification, catalogEntry, isLegacyStatic)
	return {
		Name = model.Name,
		Model = model,
		Classification = classification,
		CatalogEntry = catalogEntry,
		IsLegacyStatic = isLegacyStatic,
		Warnings = {},
		Errors = {},
	}
end

local function addWarning(report, message)
	summary.WarningCount = summary.WarningCount + 1
	append(report.Warnings, message)
	warn(TOOL_PREFIX .. " [WARN] " .. report.Name .. " [" .. report.Classification .. "] - " .. message)
end

local function addError(report, message)
	summary.ErrorCount = summary.ErrorCount + 1
	append(report.Errors, message)
	warn(TOOL_PREFIX .. " [ERROR] " .. report.Name .. " [" .. report.Classification .. "] - " .. message)
end

local function isPublicCatalogClassification(classification)
	return classification == CLASSIFICATION.StaticCatalog
		or classification == CLASSIFICATION.AutoCatalog
end

local function addCatalogErrorOtherwiseWarning(report, message)
	if isPublicCatalogClassification(report.Classification) then
		addError(report, message)
	else
		addWarning(report, message)
	end
end

local function addImportReadinessIssue(report, message)
	if report.IsLegacyStatic then
		addWarning(report, message .. " Legacy static starter furniture should be normalized in a future cleanup patch.")
	elseif isPublicCatalogClassification(report.Classification) then
		addError(report, message)
	else
		addWarning(report, message)
	end
end

local function isPositiveInteger(value)
	return typeof(value) == "number"
		and value == value
		and value > 0
		and value < math.huge
		and math.floor(value) == value
end

local function isNonNegativeInteger(value)
	return typeof(value) == "number"
		and value == value
		and value >= 0
		and value < math.huge
		and math.floor(value) == value
end

local function isNonEmptyString(value)
	return typeof(value) == "string" and value:match("%S") ~= nil
end

local function hasTrueAttribute(instance, attributeNames)
	for _, attributeName in ipairs(attributeNames) do
		if instance:GetAttribute(attributeName) == true then
			return true, attributeName
		end
	end

	return false, nil
end

local staticCatalogLookup = {}

local function registerCatalogEntry(lookup, item)
	if typeof(item) ~= "table" then
		return
	end

	local keyFields = {
		"Id",
		"TemplateName",
		"TemplateId",
	}

	for _, fieldName in ipairs(keyFields) do
		local value = item[fieldName]

		if isNonEmptyString(value) then
			lookup[value] = item
		end
	end
end

local function loadFurnitureCatalogConfig()
	local sharedFolder = ReplicatedStorage:FindFirstChild(SHARED_FOLDER_NAME)

	if not sharedFolder then
		addGlobalWarning("ReplicatedStorage.Shared was not found; static catalog classification is unavailable.")
		return nil, nil
	end

	local catalogModule = sharedFolder:FindFirstChild(FURNITURE_CATALOG_CONFIG_MODULE_NAME)

	if not catalogModule then
		addGlobalWarning(
			"ReplicatedStorage.Shared.FurnitureCatalogConfig was not found; static catalog classification is unavailable."
		)
		return nil, nil
	end

	if not catalogModule:IsA("ModuleScript") then
		addGlobalWarning(
			"ReplicatedStorage.Shared.FurnitureCatalogConfig exists but is a "
				.. catalogModule.ClassName
				.. "; static catalog classification is unavailable."
		)
		return nil, catalogModule
	end

	local ok, catalogConfig = pcall(require, catalogModule)

	if not ok then
		addGlobalWarning(
			"Could not require ReplicatedStorage.Shared.FurnitureCatalogConfig: "
				.. tostring(catalogConfig)
		)
		return nil, catalogModule
	end

	if typeof(catalogConfig) ~= "table" then
		addGlobalWarning(
			"ReplicatedStorage.Shared.FurnitureCatalogConfig did not return a table; static catalog classification is unavailable."
		)
		return nil, catalogModule
	end

	return catalogConfig, catalogModule
end

local function collectStaticCatalogKeysFromSource(catalogModule)
	if not catalogModule or not catalogModule:IsA("ModuleScript") then
		return nil
	end

	local ok, source = pcall(function()
		return catalogModule.Source
	end)

	if not ok or not isNonEmptyString(source) then
		return nil
	end

	local _, itemsStart = string.find(source, "local%s+ITEMS%s*=%s*{")

	if not itemsStart then
		return nil
	end

	local staticBlockEnd = string.find(source, "%-%-%s+Future", itemsStart + 1) or #source
	local staticBlock = string.sub(source, itemsStart + 1, staticBlockEnd - 1)
	local keys = {}
	local foundKey = false

	for fieldName, value in string.gmatch(staticBlock, "([%w_]+)%s*=%s*\"([^\"]+)\"") do
		if fieldName == "Id" or fieldName == "TemplateName" or fieldName == "TemplateId" then
			keys[value] = true
			foundKey = true
		end
	end

	if not foundKey then
		return nil
	end

	return keys
end

local function getCatalogItems(catalogConfig)
	if typeof(catalogConfig) ~= "table" then
		return nil
	end

	local getItems = catalogConfig.GetItemsArray or catalogConfig.GetPublicCatalog

	if typeof(getItems) ~= "function" then
		return nil
	end

	local ok, items = pcall(getItems)

	if not ok or typeof(items) ~= "table" then
		return nil
	end

	return items
end

local function getCatalogItem(catalogConfig, key)
	if typeof(catalogConfig) ~= "table" or not isNonEmptyString(key) then
		return nil
	end

	if typeof(catalogConfig.GetItem) == "function" then
		local ok, item = pcall(catalogConfig.GetItem, key)

		if ok and typeof(item) == "table" then
			return item
		end
	end

	local items = getCatalogItems(catalogConfig)

	if not items then
		return nil
	end

	for _, item in ipairs(items) do
		if typeof(item) == "table"
			and (
				item.Id == key
				or item.TemplateName == key
				or item.TemplateId == key
			) then

			return item
		end
	end

	return nil
end

local function buildStaticCatalogLookup(catalogConfig, catalogModule, furnitureTemplates)
	local lookup = {}
	local sourceKeys = collectStaticCatalogKeysFromSource(catalogModule)

	if sourceKeys then
		for key in pairs(sourceKeys) do
			registerCatalogEntry(lookup, getCatalogItem(catalogConfig, key))
		end

		return lookup
	end

	local items = getCatalogItems(catalogConfig)

	if not items then
		addGlobalWarning("Could not read catalog items; static catalog classification is unavailable.")
		return lookup
	end

	for _, item in ipairs(items) do
		local templateName = item.TemplateName or item.TemplateId or item.Id
		local matchingTemplate = isNonEmptyString(templateName) and furnitureTemplates:FindFirstChild(templateName) or nil
		local isAutoCatalogTemplate = matchingTemplate
			and matchingTemplate:IsA("Model")
			and matchingTemplate:GetAttribute("AutoCatalogEnabled") == true

		if not isAutoCatalogTemplate then
			registerCatalogEntry(lookup, item)
		end
	end

	print(
		TOOL_PREFIX
			.. " [INFO] Could not inspect FurnitureCatalogConfig source; static catalog lookup was built from public catalog entries excluding AutoCatalogEnabled=true templates."
	)

	return lookup
end

local function getStaticCatalogEntryForModel(model)
	local candidates = {}

	append(candidates, model.Name)

	local attributeNames = {
		"Id",
		"TemplateId",
		"TemplateName",
	}

	for _, attributeName in ipairs(attributeNames) do
		local attributeValue = model:GetAttribute(attributeName)

		if isNonEmptyString(attributeValue) then
			append(candidates, attributeValue)
		end
	end

	for _, candidate in ipairs(candidates) do
		if staticCatalogLookup[candidate] then
			return staticCatalogLookup[candidate]
		end
	end

	return nil
end

local function classifyTemplate(model)
	local autoCatalogEnabled = model:GetAttribute("AutoCatalogEnabled")
	local staticCatalogEntry = getStaticCatalogEntryForModel(model)

	if staticCatalogEntry then
		return CLASSIFICATION.StaticCatalog, staticCatalogEntry
	end

	if autoCatalogEnabled == true then
		return CLASSIFICATION.AutoCatalog, nil
	end

	if autoCatalogEnabled == false then
		return CLASSIFICATION.InventoryOnlyOrTest, nil
	end

	if KNOWN_SPECIAL_CASES[model.Name] then
		return CLASSIFICATION.InventoryOnlyOrTest, nil
	end

	return CLASSIFICATION.Unclassified, nil
end

local function isLegacyStaticTemplate(model, classification)
	return classification == CLASSIFICATION.StaticCatalog
		and model:GetAttribute("AutoCatalogEnabled") == nil
		and KNOWN_LEGACY_STATIC_TEMPLATES[model.Name] == true
end

local function reportClassificationIssues(report, model)
	local autoCatalogEnabled = model:GetAttribute("AutoCatalogEnabled")

	if report.Classification == CLASSIFICATION.StaticCatalog then
		if report.IsLegacyStatic then
			addWarning(
				report,
				"Known legacy static starter furniture; import-readiness issues are warnings until the starter templates are normalized."
			)
		end

		if autoCatalogEnabled == true then
			addWarning(
				report,
				"Template is listed in static FurnitureCatalogConfig and also has AutoCatalogEnabled=true; static catalog metadata is being used by this validator."
			)
		end

		return
	end

	if report.Classification == CLASSIFICATION.InventoryOnlyOrTest
		and KNOWN_SPECIAL_CASES[model.Name] then

		if autoCatalogEnabled == nil then
			addWarning(
				report,
				"AutoCatalogEnabled is missing, but this is classified as InventoryOnlyOrTest because it is a known test template."
			)
		elseif typeof(autoCatalogEnabled) ~= "boolean" then
			addWarning(
				report,
				"AutoCatalogEnabled should be a boolean, but this is classified as InventoryOnlyOrTest because it is a known test template."
			)
		end

		return
	end

	if autoCatalogEnabled == nil then
		addWarning(
			report,
			"AutoCatalogEnabled is missing; classified as Unclassified. Set true for public catalog or false for inventory-only/test furniture."
		)
	elseif typeof(autoCatalogEnabled) ~= "boolean" then
		addWarning(
			report,
			"AutoCatalogEnabled should be a boolean; classified as Unclassified because it is "
				.. typeof(autoCatalogEnabled)
				.. "."
		)
	end
end

local function hasNonAsciiCharacter(value)
	for index = 1, #value do
		local byte = string.byte(value, index)

		if byte < 32 or byte > 126 then
			return true
		end
	end

	return false
end

local function usesOnlySafeNameCharacters(value)
	return value:match("^[A-Za-z0-9_]+$") ~= nil
end

local function matchesRecommendedNamePattern(value)
	return value:match("^[A-Z][A-Za-z0-9]*_[A-Za-z0-9][A-Za-z0-9_]*$") ~= nil
		and value:find("__", 1, true) == nil
end

local function validateName(report, model)
	local templateName = model.Name

	if templateName == "" then
		addCatalogErrorOtherwiseWarning(report, "Template name is empty.")
		return
	end

	if hasNonAsciiCharacter(templateName) then
		addCatalogErrorOtherwiseWarning(report, "Template name should use stable ASCII characters only.")
	end

	if templateName:find("%s") then
		addCatalogErrorOtherwiseWarning(report, "Template name should not contain spaces.")
	end

	if not usesOnlySafeNameCharacters(templateName) then
		addCatalogErrorOtherwiseWarning(
			report,
			"Template name should contain only letters, numbers, and underscores."
		)
	elseif not matchesRecommendedNamePattern(templateName) then
		addWarning(
			report,
			"Template name is safe but does not match the recommended pattern, for example Chair_Modern_001 or Gate_Test_OpenClose."
		)
	end
end

local function getRelativePath(root, instance)
	local names = {}
	local current = instance

	while current and current ~= root do
		table.insert(names, 1, current.Name)
		current = current.Parent
	end

	return table.concat(names, ".")
end

local function formatInstanceSamples(root, instances, limit)
	local samples = {}
	local sampleLimit = math.min(#instances, limit)

	for index = 1, sampleLimit do
		append(samples, getRelativePath(root, instances[index]))
	end

	if #instances > limit then
		append(samples, "+" .. tostring(#instances - limit) .. " more")
	end

	return table.concat(samples, ", ")
end

local function validateEmbeddedScripts(report, model)
	local scripts = {}

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Script")
			or descendant:IsA("LocalScript")
			or descendant:IsA("ModuleScript") then

			append(scripts, descendant)
		end
	end

	if #scripts > 0 then
		addError(
			report,
			"Embedded Script, LocalScript, or ModuleScript instances are not allowed in furniture templates: "
				.. formatInstanceSamples(model, scripts, 6)
		)
	end
end

local function getBasePartsNamed(model, partName)
	local namedInstances = {}
	local baseParts = {}

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant.Name == partName then
			append(namedInstances, descendant)

			if descendant:IsA("BasePart") then
				append(baseParts, descendant)
			end
		end
	end

	return namedInstances, baseParts
end

local function addFootprintIssue(report, model, message)
	local specialCase = KNOWN_SPECIAL_CASES[model.Name]

	if report.IsLegacyStatic then
		addImportReadinessIssue(report, message)
	elseif isPublicCatalogClassification(report.Classification) then
		addError(report, message)
	elseif specialCase then
		addWarning(report, message .. " Known special case: " .. specialCase.Note .. ".")
	else
		addWarning(report, message)
	end
end

local function validateFootprint(report, model)
	local width = model:GetAttribute("FootprintWidth")
	local depth = model:GetAttribute("FootprintDepth")
	local validWidth = nil
	local validDepth = nil

	if width == nil then
		addFootprintIssue(report, model, "Missing FootprintWidth.")
	elseif not isPositiveInteger(width) then
		addFootprintIssue(report, model, "FootprintWidth must be a positive integer.")
	elseif width > MAX_FOOTPRINT_TILES then
		addFootprintIssue(
			report,
			model,
			"FootprintWidth should be between 1 and " .. tostring(MAX_FOOTPRINT_TILES) .. "."
		)
	else
		validWidth = width
	end

	if depth == nil then
		addFootprintIssue(report, model, "Missing FootprintDepth.")
	elseif not isPositiveInteger(depth) then
		addFootprintIssue(report, model, "FootprintDepth must be a positive integer.")
	elseif depth > MAX_FOOTPRINT_TILES then
		addFootprintIssue(
			report,
			model,
			"FootprintDepth should be between 1 and " .. tostring(MAX_FOOTPRINT_TILES) .. "."
		)
	else
		validDepth = depth
	end

	return validWidth, validDepth
end

local function validatePlacementBounds(report, model, footprintWidth, footprintDepth)
	local namedBounds, boundsParts = getBasePartsNamed(model, PLACEMENT_BOUNDS_PART_NAME)

	if #namedBounds == 0 then
		addImportReadinessIssue(report, "Missing BasePart named PlacementBounds.")
		return nil
	end

	if #boundsParts == 0 then
		addImportReadinessIssue(report, "PlacementBounds exists but is not a BasePart.")
		return nil
	end

	if #boundsParts > 1 then
		addWarning(
			report,
			"Multiple BaseParts named PlacementBounds were found; placement should use one clear bounds part."
		)
	end

	if #namedBounds > #boundsParts then
		addWarning(report, "A non-BasePart instance named PlacementBounds was also found.")
	end

	local bounds = boundsParts[1]

	if bounds.Anchored ~= true then
		addImportReadinessIssue(report, "PlacementBounds.Anchored should be true.")
	end

	if bounds.Transparency ~= 1 then
		addImportReadinessIssue(report, "PlacementBounds.Transparency should be 1.")
	end

	if bounds.CanCollide ~= false then
		addImportReadinessIssue(report, "PlacementBounds.CanCollide should be false.")
	end

	if bounds.CanTouch ~= false then
		addImportReadinessIssue(report, "PlacementBounds.CanTouch should be false.")
	end

	if bounds.CanQuery ~= true then
		addImportReadinessIssue(report, "PlacementBounds.CanQuery should be true.")
	end

	local size = bounds.Size

	if size.X > EXTREME_BOUNDS_XZ_STUDS
		or size.Z > EXTREME_BOUNDS_XZ_STUDS
		or size.Y > EXTREME_BOUNDS_Y_STUDS then

		addImportReadinessIssue(
			report,
			string.format(
				"PlacementBounds is extremely oversized at %.2f x %.2f x %.2f studs.",
				size.X,
				size.Y,
				size.Z
			)
		)
	end

	if footprintWidth then
		local expectedX = footprintWidth * TILE_SIZE - FOOTPRINT_MARGIN
		local xDelta = math.abs(size.X - expectedX)

		if xDelta > PLACEMENT_BOUNDS_TOLERANCE then
			addImportReadinessIssue(
				report,
				string.format(
					"PlacementBounds.Size.X should be about %.2f for FootprintWidth=%d; found %.2f.",
					expectedX,
					footprintWidth,
					size.X
				)
			)
		end
	end

	if footprintDepth then
		local expectedZ = footprintDepth * TILE_SIZE - FOOTPRINT_MARGIN
		local zDelta = math.abs(size.Z - expectedZ)

		if zDelta > PLACEMENT_BOUNDS_TOLERANCE then
			addImportReadinessIssue(
				report,
				string.format(
					"PlacementBounds.Size.Z should be about %.2f for FootprintDepth=%d; found %.2f.",
					expectedZ,
					footprintDepth,
					size.Z
				)
			)
		end
	end

	return bounds
end

local function hasRootStrategy(model, placementBounds)
	if model.PrimaryPart then
		return true
	end

	if placementBounds then
		return true
	end

	local candidateNames = {
		"Root",
		"RootPart",
		"Pivot",
		"PivotPart",
	}

	for _, candidateName in ipairs(candidateNames) do
		local candidate = model:FindFirstChild(candidateName, true)

		if candidate and candidate:IsA("BasePart") then
			return true
		end
	end

	return false
end

local function validateRootStrategy(report, model, placementBounds)
	if not hasRootStrategy(model, placementBounds) then
		addWarning(
			report,
			"Model has no PrimaryPart, PlacementBounds, or obvious root/pivot BasePart."
		)
	end
end

local function getEffectiveMetadataValue(report, model, fieldName)
	local attributeValue = model:GetAttribute(fieldName)

	if attributeValue ~= nil then
		return attributeValue, "model"
	end

	if report.Classification == CLASSIFICATION.StaticCatalog and report.CatalogEntry then
		local catalogValue = report.CatalogEntry[fieldName]

		if catalogValue ~= nil then
			return catalogValue, "static catalog"
		end

		if fieldName == "SellableOnPurchase" and report.CatalogEntry.Sellable ~= nil then
			return report.CatalogEntry.Sellable, "static catalog"
		end
	end

	return nil, nil
end

local function getCurrencyInfo(report, model)
	local currencyKey = getEffectiveMetadataValue(report, model, "CurrencyKey")
	local purchaseCurrency = getEffectiveMetadataValue(report, model, "PurchaseCurrency")
	local hasCurrencyKey = isNonEmptyString(currencyKey)
	local hasPurchaseCurrency = isNonEmptyString(purchaseCurrency)
	local resolvedCurrency = nil

	if hasCurrencyKey then
		resolvedCurrency = currencyKey
	elseif hasPurchaseCurrency then
		resolvedCurrency = purchaseCurrency
	end

	return resolvedCurrency, hasCurrencyKey, hasPurchaseCurrency, currencyKey, purchaseCurrency
end

local function validatePublicCatalogMetadata(report, model)
	if not isPublicCatalogClassification(report.Classification) then
		return
	end

	if not isNonEmptyString(getEffectiveMetadataValue(report, model, "DisplayName")) then
		addError(report, report.Classification .. " templates must provide DisplayName.")
	end

	if not isNonEmptyString(getEffectiveMetadataValue(report, model, "Description")) then
		addError(report, report.Classification .. " templates must provide Description.")
	end

	local category = getEffectiveMetadataValue(report, model, "Category")

	if not isNonEmptyString(category) then
		addError(report, report.Classification .. " templates must provide Category.")
	else
		local normalizedCategory = LEGACY_CATEGORY_ALIASES[category] or category

		if normalizedCategory ~= category then
			addWarning(
				report,
				"Uses legacy category alias " .. category .. "; normalized to " .. normalizedCategory .. " for validation."
			)
		end

		if not VALID_CATALOG_CATEGORIES[normalizedCategory] then
			if report.Classification == CLASSIFICATION.AutoCatalog then
				addError(report, "Category is not in the supported furniture category list: " .. tostring(category))
			else
				addWarning(report, "Category is not in the supported furniture category list: " .. tostring(category))
			end
		end
	end

	if not isPositiveInteger(getEffectiveMetadataValue(report, model, "Price")) then
		addError(report, report.Classification .. " templates must provide Price as a positive integer.")
	end

	if not isNonNegativeInteger(getEffectiveMetadataValue(report, model, "SellPrice")) then
		addError(report, report.Classification .. " templates must provide SellPrice as a non-negative integer.")
	end

	local resolvedCurrency, hasCurrencyKey, hasPurchaseCurrency, currencyKey, purchaseCurrency = getCurrencyInfo(report, model)

	if not resolvedCurrency then
		addError(report, report.Classification .. " templates must provide CurrencyKey or PurchaseCurrency.")
	elseif hasCurrencyKey and hasPurchaseCurrency and currencyKey ~= purchaseCurrency then
		addWarning(
			report,
			"CurrencyKey and PurchaseCurrency differ; confirm the intended purchase currency."
		)
	end

	if report.Classification == CLASSIFICATION.AutoCatalog and not hasCurrencyKey and hasPurchaseCurrency then
		addWarning(
			report,
			"PurchaseCurrency is set but CurrencyKey is missing; current auto-catalog runtime reads CurrencyKey."
		)
	end

	if typeof(getEffectiveMetadataValue(report, model, "TradableOnPurchase")) ~= "boolean" then
		addError(report, report.Classification .. " templates must explicitly provide TradableOnPurchase.")
	end

end

local function validateTradableSafety(report, model)
	local resolvedCurrency = getCurrencyInfo(report, model)
	local tradable = getEffectiveMetadataValue(report, model, "TradableOnPurchase")

	if tradable == true then
		if isPublicCatalogClassification(report.Classification) and resolvedCurrency == "Dollars" then
			addError(
				report,
				"Dollar public shop furniture must not set TradableOnPurchase=true."
			)
		else
			addWarning(report, "TradableOnPurchase=true; confirm this template is intentionally marketplace-tradable.")
		end
	end

	if resolvedCurrency == "Dollars" and tradable ~= false then
		if isPublicCatalogClassification(report.Classification) then
			addError(report, "Dollar public shop furniture must explicitly set TradableOnPurchase=false.")
		else
			addWarning(report, "Dollar furniture should explicitly set TradableOnPurchase=false.")
		end
	end

	if typeof(getEffectiveMetadataValue(report, model, "SellableOnPurchase")) ~= "boolean" then
		if isPublicCatalogClassification(report.Classification) then
			addError(report, "SellableOnPurchase must be explicitly set to true or false.")
		else
			addWarning(report, "SellableOnPurchase should be explicitly set to true or false.")
		end
	end
end

local function hasNamedDescendant(root, descendantName)
	return root:FindFirstChild(descendantName, true) ~= nil
end

local function hasSeat(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Seat") or descendant:IsA("VehicleSeat") then
			return true
		end
	end

	return false
end

local function parsePermissionActions(value)
	local actions = {}

	if typeof(value) == "string" then
		for actionName in string.gmatch(value, "[^,%s;]+") do
			if actionName ~= "" then
				append(actions, actionName)
			end
		end
	elseif typeof(value) == "table" then
		for _, actionName in ipairs(value) do
			if typeof(actionName) == "string" and actionName ~= "" then
				append(actions, actionName)
			end
		end
	end

	return actions
end

local function permissionActionsInclude(actions, expectedAction)
	for _, actionName in ipairs(actions) do
		if actionName == expectedAction then
			return true
		end
	end

	return false
end

local function isOpenCloseTarget(instance)
	return typeof(instance) == "Instance"
		and (
			instance:IsA("BasePart")
			or instance:IsA("Model")
		)
end

local function validateSitMetadata(report, model)
	if model:GetAttribute("DefaultAction") ~= "Sit" then
		return
	end

	if not hasNamedDescendant(model, "SitPoint") then
		addWarning(report, "DefaultAction is Sit but SitPoint is missing.")
	end

	if not hasSeat(model) then
		addWarning(report, "DefaultAction is Sit but no Seat or VehicleSeat was found.")
	end
end

local function validateOpenCloseMetadata(report, model)
	local permissionActions = parsePermissionActions(model:GetAttribute("PermissionActions"))
	local supportsOpenClose = model:GetAttribute("SupportsOpenClose") == true
	local defaultAction = model:GetAttribute("DefaultAction")

	if supportsOpenClose then
		if not permissionActionsInclude(permissionActions, "OpenClose") then
			addWarning(report, "SupportsOpenClose is true but PermissionActions does not include OpenClose.")
		end

		if defaultAction ~= "OpenClose" then
			addWarning(report, "SupportsOpenClose is true but DefaultAction is not OpenClose.")
		end

		local targetName = model:GetAttribute("OpenCloseTargetName")

		if not isNonEmptyString(targetName) then
			addWarning(report, "SupportsOpenClose is true but OpenCloseTargetName is missing.")
		else
			local target = model:FindFirstChild(targetName, true)

			if not target then
				addWarning(report, "OpenCloseTargetName does not resolve to a child instance: " .. targetName)
			elseif not isOpenCloseTarget(target) then
				addWarning(
					report,
					"OpenCloseTargetName resolves to "
						.. target.ClassName
						.. ", but OpenClose targets should be BasePart or Model."
				)
			end
		end

		local openAngleDegrees = model:GetAttribute("OpenAngleDegrees")

		if openAngleDegrees == nil then
			addWarning(report, "OpenAngleDegrees is missing; runtime defaults to 90 degrees.")
		elseif typeof(openAngleDegrees) ~= "number" or openAngleDegrees ~= openAngleDegrees then
			addWarning(report, "OpenAngleDegrees should be a number.")
		elseif openAngleDegrees == 0 then
			addWarning(report, "OpenAngleDegrees is 0; OpenClose may appear to do nothing.")
		elseif math.abs(openAngleDegrees) > 180 then
			addWarning(report, "OpenAngleDegrees is outside the expected -180 to 180 range.")
		end

		local openCloseAxis = model:GetAttribute("OpenCloseAxis")

		if openCloseAxis == nil then
			addWarning(report, "OpenCloseAxis is missing; runtime defaults to Y.")
		elseif openCloseAxis ~= "X" and openCloseAxis ~= "Y" and openCloseAxis ~= "Z" then
			addWarning(report, "OpenCloseAxis should be X, Y, or Z.")
		end
	else
		if permissionActionsInclude(permissionActions, "OpenClose") then
			addWarning(report, "PermissionActions includes OpenClose but SupportsOpenClose is not true.")
		end

		if defaultAction == "OpenClose" then
			addWarning(report, "DefaultAction is OpenClose but SupportsOpenClose is not true.")
		end
	end
end

local function validatePublicInteractionFlags(report, model)
	for _, attributeName in ipairs(PUBLIC_INTERACTION_ATTRIBUTES) do
		if model:GetAttribute(attributeName) == true then
			addWarning(
				report,
				attributeName .. "=true; public furniture interaction should be intentional."
			)
		end
	end
end

local function isHelperPart(part)
	return HELPER_PART_NAMES[part.Name] == true
end

local function isVisualPart(part)
	return part:IsA("BasePart") and not isHelperPart(part)
end

local function getVisualBoundsParts(model)
	local visibleParts = {}
	local fallbackParts = {}

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart")
			and descendant.Name ~= PLACEMENT_BOUNDS_PART_NAME
			and descendant:GetAttribute("IgnoreForPlacementBounds") ~= true then

			if isVisualPart(descendant) then
				if descendant.Transparency < 1
					or descendant:IsA("Seat")
					or descendant:IsA("VehicleSeat") then

					append(visibleParts, descendant)
				else
					append(fallbackParts, descendant)
				end
			end
		end
	end

	if #visibleParts > 0 then
		return visibleParts
	end

	return fallbackParts
end

local function getPartWorldCorners(part)
	local halfSize = part.Size / 2
	local localCorners = {
		Vector3.new(-halfSize.X, -halfSize.Y, -halfSize.Z),
		Vector3.new(-halfSize.X, -halfSize.Y, halfSize.Z),
		Vector3.new(-halfSize.X, halfSize.Y, -halfSize.Z),
		Vector3.new(-halfSize.X, halfSize.Y, halfSize.Z),
		Vector3.new(halfSize.X, -halfSize.Y, -halfSize.Z),
		Vector3.new(halfSize.X, -halfSize.Y, halfSize.Z),
		Vector3.new(halfSize.X, halfSize.Y, -halfSize.Z),
		Vector3.new(halfSize.X, halfSize.Y, halfSize.Z),
	}
	local worldCorners = {}

	for _, localCorner in ipairs(localCorners) do
		append(worldCorners, part.CFrame:PointToWorldSpace(localCorner))
	end

	return worldCorners
end

local function getVisualBoundsRelativeToPlacementBounds(model, placementBounds)
	if not placementBounds then
		return nil
	end

	local visualParts = getVisualBoundsParts(model)

	if #visualParts == 0 then
		return nil
	end

	local minX = math.huge
	local minZ = math.huge
	local maxX = -math.huge
	local maxZ = -math.huge

	for _, part in ipairs(visualParts) do
		for _, worldCorner in ipairs(getPartWorldCorners(part)) do
			local boundsLocalCorner = placementBounds.CFrame:PointToObjectSpace(worldCorner)

			minX = math.min(minX, boundsLocalCorner.X)
			minZ = math.min(minZ, boundsLocalCorner.Z)
			maxX = math.max(maxX, boundsLocalCorner.X)
			maxZ = math.max(maxZ, boundsLocalCorner.Z)
		end
	end

	return {
		SizeX = maxX - minX,
		SizeZ = maxZ - minZ,
		PartCount = #visualParts,
	}
end

local function getOptionalNumberAttribute(report, model, attributeName)
	local value = model:GetAttribute(attributeName)

	if value == nil then
		return nil
	end

	if typeof(value) ~= "number" or value ~= value or value < 0 or value >= math.huge then
		addWarning(report, attributeName .. " should be a non-negative number when set.")
		return nil
	end

	return value
end

local function validateVisualOverhang(report, model, placementBounds)
	if not placementBounds then
		return
	end

	local visualBounds = getVisualBoundsRelativeToPlacementBounds(model, placementBounds)

	if not visualBounds then
		return
	end

	local excessX = math.max(0, visualBounds.SizeX - placementBounds.Size.X)
	local excessZ = math.max(0, visualBounds.SizeZ - placementBounds.Size.Z)

	if excessX <= VISUAL_OVERHANG_TOLERANCE and excessZ <= VISUAL_OVERHANG_TOLERANCE then
		return
	end

	local declaredOverhangX = getOptionalNumberAttribute(report, model, "VisualOverhangStudsX")
	local declaredOverhangZ = getOptionalNumberAttribute(report, model, "VisualOverhangStudsZ")
	local details = string.format(
		" Visual X/Z %.2f x %.2f, PlacementBounds X/Z %.2f x %.2f, excess %.2f x %.2f.",
		visualBounds.SizeX,
		visualBounds.SizeZ,
		placementBounds.Size.X,
		placementBounds.Size.Z,
		excessX,
		excessZ
	)

	if declaredOverhangX or declaredOverhangZ then
		details = details
			.. string.format(
				" Declared overhang X/Z %.2f x %.2f.",
				declaredOverhangX or 0,
				declaredOverhangZ or 0
			)
	end

	if model:GetAttribute("AllowVisualOverhang") == true then
		addWarning(
			report,
			"Visual overhang allowed; verify it does not overlap nearby furniture badly." .. details
		)
	else
		addWarning(
			report,
			"Visual mesh extends beyond PlacementBounds. Set AllowVisualOverhang=true if intentional." .. details
		)
	end
end

local function isUnanchoredAllowed(model, part)
	local modelAllows = hasTrueAttribute(model, ALLOW_UNANCHORED_ATTRIBUTES)
	local partAllows = hasTrueAttribute(part, ALLOW_UNANCHORED_ATTRIBUTES)

	return modelAllows or partAllows
end

local function validateCollisionAndQuery(report, model)
	local visualParts = {}
	local canTouchParts = {}
	local canQueryParts = {}
	local collidingParts = {}
	local unanchoredParts = {}

	for _, descendant in ipairs(model:GetDescendants()) do
		if isVisualPart(descendant) then
			append(visualParts, descendant)

			if descendant.CanTouch == true then
				append(canTouchParts, descendant)
			end

			if descendant.CanQuery == true then
				append(canQueryParts, descendant)
			end

			if descendant.CanCollide == true then
				append(collidingParts, descendant)
			end

			if descendant.Anchored ~= true and not isUnanchoredAllowed(model, descendant) then
				append(unanchoredParts, descendant)
			end
		end
	end

	if #unanchoredParts > 0 then
		addWarning(
			report,
			"Visual parts are unanchored without an explicit allow attribute: "
				.. formatInstanceSamples(model, unanchoredParts, 6)
		)
	end

	if #canTouchParts > 0 then
		addWarning(
			report,
			"Visual parts have CanTouch=true; disable touch on furniture visuals unless needed: "
				.. formatInstanceSamples(model, canTouchParts, 6)
		)
	end

	local visualQueryAllowed = hasTrueAttribute(model, ALLOW_VISUAL_CAN_QUERY_ATTRIBUTES)
	local manyVisualParts = math.max(4, math.ceil(#visualParts * 0.5))

	if #canQueryParts >= manyVisualParts and #canQueryParts > 0 and not visualQueryAllowed then
		addWarning(
			report,
			"Many visual parts have CanQuery=true ("
				.. tostring(#canQueryParts)
				.. "/"
				.. tostring(#visualParts)
				.. "); prefer PlacementBounds for placement queries unless visual querying is intentional."
		)
	end

	if model:GetAttribute("BlocksMovement") == false and #collidingParts > 0 then
		addWarning(
			report,
			"BlocksMovement=false but visual parts still collide: "
				.. formatInstanceSamples(model, collidingParts, 6)
		)
	end
end

local function validateTemplate(model)
	local classification, catalogEntry = classifyTemplate(model)
	local isLegacyStatic = isLegacyStaticTemplate(model, classification)
	local report = createReport(model, classification, catalogEntry, isLegacyStatic)

	summary.TotalTemplates = summary.TotalTemplates + 1
	summary[classification] = summary[classification] + 1

	if isLegacyStatic then
		summary.LegacyStatic = summary.LegacyStatic + 1
	elseif isPublicCatalogClassification(classification) then
		summary.StrictPublic = summary.StrictPublic + 1
	end

	reportClassificationIssues(report, model)
	validateName(report, model)
	validateEmbeddedScripts(report, model)

	local footprintWidth, footprintDepth = validateFootprint(report, model)
	local placementBounds = validatePlacementBounds(report, model, footprintWidth, footprintDepth)

	validateRootStrategy(report, model, placementBounds)
	validateVisualOverhang(report, model, placementBounds)
	validatePublicCatalogMetadata(report, model)
	validateTradableSafety(report, model)
	validateSitMetadata(report, model)
	validateOpenCloseMetadata(report, model)
	validatePublicInteractionFlags(report, model)
	validateCollisionAndQuery(report, model)

	if #report.Errors == 0 then
		summary.Passed = summary.Passed + 1
	end

	if #report.Errors > 0 then
		append(summary.TemplatesWithErrors, report.Name)
	end

	if #report.Warnings > 0 then
		append(summary.TemplatesWithWarnings, report.Name)
	end

	if #report.Errors == 0 and #report.Warnings == 0 then
		print(TOOL_PREFIX .. " [OK] " .. report.Name .. " [" .. report.Classification .. "]")
	end
end

local function formatList(values)
	if #values == 0 then
		return "(none)"
	end

	table.sort(values)

	return table.concat(values, ", ")
end

local function printSummary()
	print(TOOL_PREFIX .. " Summary")
	print("  total templates scanned:", summary.TotalTemplates)
	print("  StaticCatalog:", summary.StaticCatalog)
	print("  AutoCatalog:", summary.AutoCatalog)
	print("  LegacyStatic:", summary.LegacyStatic)
	print("  StrictPublic:", summary.StrictPublic)
	print("  InventoryOnlyOrTest:", summary.InventoryOnlyOrTest)
	print("  Unclassified:", summary.Unclassified)
	print("  passed (no errors):", summary.Passed)
	print("  warnings:", summary.WarningCount)
	print("  errors:", summary.ErrorCount)
	print("  templates with errors:", formatList(summary.TemplatesWithErrors))
	print("  templates with warnings:", formatList(summary.TemplatesWithWarnings))

	if #summary.GlobalWarnings > 0 then
		print("  global warnings:", formatList(summary.GlobalWarnings))
	end

	if #summary.GlobalErrors > 0 then
		print("  global errors:", formatList(summary.GlobalErrors))
	end

	if summary.ErrorCount > 0 then
		warn(TOOL_PREFIX .. " RESULT: FAIL")
	elseif summary.WarningCount > 0 then
		warn(TOOL_PREFIX .. " RESULT: WARN")
	else
		print(TOOL_PREFIX .. " RESULT: PASS")
	end
end

local furnitureTemplates = ReplicatedStorage:FindFirstChild(FURNITURE_TEMPLATES_FOLDER_NAME)

if not furnitureTemplates then
	addGlobalError("ReplicatedStorage." .. FURNITURE_TEMPLATES_FOLDER_NAME .. " was not found.")
	printSummary()
	return
end

if not furnitureTemplates:IsA("Folder") then
	addGlobalError("ReplicatedStorage." .. FURNITURE_TEMPLATES_FOLDER_NAME .. " exists but is not a Folder.")
	printSummary()
	return
end

local catalogConfig, catalogModule = loadFurnitureCatalogConfig()
staticCatalogLookup = buildStaticCatalogLookup(catalogConfig, catalogModule, furnitureTemplates)

for _, child in ipairs(furnitureTemplates:GetChildren()) do
	if child:IsA("Model") then
		validateTemplate(child)
	else
		addGlobalWarning(
			"Direct child "
				.. child.Name
				.. " is a "
				.. child.ClassName
				.. "; furniture templates should be direct child Models."
		)
	end
end

if summary.TotalTemplates == 0 then
	addGlobalError("No direct child Model templates were found under ReplicatedStorage.FurnitureTemplates.")
end

printSummary()
