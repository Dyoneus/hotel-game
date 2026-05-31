local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FurnitureCatalogConfig = {}

local ITEMS = {
	{
		Id = "Chair_01",
		TemplateName = "Chair_01",
		DisplayName = "Starter Chair",
		Description = "A basic chair for sitting.",
		MaxPerRoom = 12,
		Category = "Chairs",
		FootprintWidth = 1,
		FootprintDepth = 1,
		Price = 25,
		SellPrice = 10,
		CurrencyKey = "Dollars",
		PurchaseCurrency = "Dollars",
		TradableOnPurchase = false,
		Sellable = true,
		PermissionActions = {},
		Featured = true,
		IsLimited = false,
	},
	{
		Id = "Table_01",
		TemplateName = "Table_01",
		DisplayName = "Starter Table",
		Description = "A simple table decoration.",
		MaxPerRoom = 8,
		Category = "Tables",
		FootprintWidth = 1,
		FootprintDepth = 1,
		Price = 50,
		SellPrice = 20,
		CurrencyKey = "Dollars",
		PurchaseCurrency = "Dollars",
		TradableOnPurchase = false,
		Sellable = true,
		PermissionActions = {},
		Featured = false,
		IsLimited = false,
	},
	{
		Id = "Bed_01",
		TemplateName = "Bed_01",
		DisplayName = "Starter Bed",
		Description = "A basic bed. Sleep action can be added later.",
		MaxPerRoom = 4,
		Category = "Beds",
		FootprintWidth = 2,
		FootprintDepth = 3,
		Price = 100,
		SellPrice = 40,
		CurrencyKey = "Dollars",
		PurchaseCurrency = "Dollars",
		TradableOnPurchase = false,
		Sellable = true,
		PermissionActions = {},
		Featured = false,
		IsLimited = false,
	},
}

-- Future door/gate items can opt into permissioned actions without changing
-- normal furniture. Example shape only; do not add entries until templates exist:
-- {
-- 	Id = "Door_01",
-- 	TemplateName = "Door_01",
-- 	DisplayName = "Door",
-- 	Category = "Doors",
-- 	PermissionActions = { "OpenClose" },
-- 	SupportsOpenClose = true,
-- }
-- {
-- 	Id = "BarGate_01",
-- 	TemplateName = "BarGate_01",
-- 	DisplayName = "Bar Counter Gate",
-- 	Category = "Gates",
-- 	PermissionActions = { "OpenClose" },
-- 	SupportsOpenClose = true,
-- }

local PUBLIC_FIELDS = {
	"Id",
	"TemplateName",
	"DisplayName",
	"Description",
	"MaxPerRoom",
	"Category",
	"FootprintWidth",
	"FootprintDepth",
	"Price",
	"SellPrice",
	"CurrencyKey",
	"PurchaseCurrency",
	"TradableOnPurchase",
	"Sellable",
	"PermissionActions",
	"SupportsOpenClose",
	"DefaultAction",
	"OpenCloseTargetName",
	"Featured",
	"IsLimited",
	"LimitedQuantity",
	"RemainingStock",
}

local itemsById = {}
local itemsByTemplateName = {}
local warnedAutoCatalogIssues = {}

local function copyValue(value)
	if typeof(value) ~= "table" then
		return value
	end

	local copy = {}

	for key, child in pairs(value) do
		copy[key] = copyValue(child)
	end

	return copy
end

local function copyFields(item, fields)
	local copy = {}

	for _, fieldName in ipairs(fields) do
		copy[fieldName] = copyValue(item[fieldName])
	end

	return copy
end

local function copyItem(item)
	local copy = {}

	for key, value in pairs(item) do
		copy[key] = copyValue(value)
	end

	return copy
end

for _, item in ipairs(ITEMS) do
	itemsById[item.Id] = item
	itemsByTemplateName[item.TemplateName] = item
end

local function warnOnce(key, message)
	if warnedAutoCatalogIssues[key] then
		return
	end

	warnedAutoCatalogIssues[key] = true
	warn(message)
end

local function getFurnitureTemplatesFolder()
	return ReplicatedStorage:FindFirstChild("FurnitureTemplates")
end

local function getStringAttribute(instance, attributeName, defaultValue)
	local value = instance:GetAttribute(attributeName)

	if typeof(value) == "string" and value ~= "" then
		return value
	end

	return defaultValue
end

local function getPositiveIntegerAttribute(instance, attributeName, defaultValue)
	local value = instance:GetAttribute(attributeName)

	if typeof(value) ~= "number"
		or value ~= value
		or value < 1
		or value == math.huge then

		return defaultValue, false
	end

	return math.floor(value), true
end

local function getNonNegativeIntegerAttribute(instance, attributeName, defaultValue)
	local value = instance:GetAttribute(attributeName)

	if typeof(value) ~= "number"
		or value ~= value
		or value < 0
		or value == math.huge then

		return defaultValue, false
	end

	return math.floor(value), true
end

local function getBooleanAttribute(instance, attributeName, defaultValue)
	local value = instance:GetAttribute(attributeName)

	if typeof(value) == "boolean" then
		return value
	end

	return defaultValue
end

local function parsePermissionActions(value)
	local actions = {}

	if typeof(value) == "table" then
		for _, actionName in ipairs(value) do
			if typeof(actionName) == "string" and actionName ~= "" then
				table.insert(actions, actionName)
			end
		end
	elseif typeof(value) == "string" then
		for actionName in string.gmatch(value, "[^,%s;]+") do
			if actionName ~= "" then
				table.insert(actions, actionName)
			end
		end
	end

	return actions
end

local function hasPlacementBounds(model)
	return model:FindFirstChild("PlacementBounds", true) ~= nil
end

local function buildAutoCatalogItem(model)
	if not model:IsA("Model") or model:GetAttribute("AutoCatalogEnabled") ~= true then
		return nil
	end

	local itemId = model.Name

	if itemsById[itemId] or itemsByTemplateName[itemId] then
		warnOnce(
			"duplicate:" .. itemId,
			"[FurnitureCatalogConfig] Static catalog entry wins over AutoCatalogEnabled template: " .. itemId
		)
		return nil
	end

	local price, validPrice = getPositiveIntegerAttribute(model, "Price", nil)

	if not validPrice then
		warnOnce(
			"price:" .. itemId,
			"[FurnitureCatalogConfig] Skipping auto-catalog template "
				.. itemId
				.. ": Price must be a positive integer."
		)
		return nil
	end

	local currencyKey = getStringAttribute(model, "CurrencyKey", "Dollars")

	if currencyKey ~= "Dollars" then
		warnOnce(
			"currency:" .. itemId,
			"[FurnitureCatalogConfig] Skipping auto-catalog template "
				.. itemId
				.. ": only Dollars currency is supported for auto-catalog furniture."
		)
		return nil
	end

	local footprintWidth, validFootprintWidth = getPositiveIntegerAttribute(model, "FootprintWidth", 1)
	local footprintDepth, validFootprintDepth = getPositiveIntegerAttribute(model, "FootprintDepth", 1)

	if not validFootprintWidth or not validFootprintDepth then
		warnOnce(
			"footprint:" .. itemId,
			"[FurnitureCatalogConfig] Auto-catalog template "
				.. itemId
				.. " has invalid FootprintWidth/FootprintDepth; defaulting to 1 x 1."
		)
	end

	if not hasPlacementBounds(model) then
		warnOnce(
			"bounds:" .. itemId,
			"[FurnitureCatalogConfig] Auto-catalog template "
				.. itemId
				.. " is missing PlacementBounds."
		)
	end

	local sellPrice = getNonNegativeIntegerAttribute(model, "SellPrice", 0)
	local permissionActions = parsePermissionActions(model:GetAttribute("PermissionActions"))
	local defaultAction = getStringAttribute(model, "DefaultAction", nil)
	local openCloseTargetName = getStringAttribute(model, "OpenCloseTargetName", nil)

	return {
		Id = itemId,
		TemplateName = itemId,
		DisplayName = getStringAttribute(model, "DisplayName", itemId),
		Description = getStringAttribute(model, "Description", ""),
		MaxPerRoom = nil,
		Category = getStringAttribute(model, "Category", "Furniture"),
		FootprintWidth = footprintWidth,
		FootprintDepth = footprintDepth,
		Price = price,
		SellPrice = sellPrice,
		CurrencyKey = currencyKey,
		PurchaseCurrency = currencyKey,
		TradableOnPurchase = getBooleanAttribute(model, "TradableOnPurchase", false),
		Sellable = getBooleanAttribute(model, "SellableOnPurchase", true),
		PermissionActions = permissionActions,
		DefaultAction = defaultAction,
		SupportsOpenClose = getBooleanAttribute(model, "SupportsOpenClose", false),
		OpenCloseTargetName = openCloseTargetName,
		Featured = getBooleanAttribute(model, "Featured", false),
		IsLimited = false,
	}
end

local function getMergedItems()
	local items = {}
	local includedById = {}

	for _, item in ipairs(ITEMS) do
		table.insert(items, item)
		includedById[item.Id] = true
	end

	local furnitureTemplates = getFurnitureTemplatesFolder()

	if furnitureTemplates then
		local autoItems = {}

		for _, child in ipairs(furnitureTemplates:GetChildren()) do
			local item = buildAutoCatalogItem(child)

			if item and not includedById[item.Id] then
				table.insert(autoItems, item)
				includedById[item.Id] = true
			end
		end

		table.sort(autoItems, function(a, b)
			return tostring(a.DisplayName) < tostring(b.DisplayName)
		end)

		for _, item in ipairs(autoItems) do
			table.insert(items, item)
		end
	end

	return items
end

function FurnitureCatalogConfig.GetItem(itemId)
	if typeof(itemId) ~= "string" then
		return nil
	end

	local item = itemsById[itemId] or itemsByTemplateName[itemId]

	if not item then
		for _, catalogItem in ipairs(getMergedItems()) do
			if catalogItem.Id == itemId or catalogItem.TemplateName == itemId then
				item = catalogItem
				break
			end
		end
	end

	if not item then
		return nil
	end

	return copyItem(item)
end

function FurnitureCatalogConfig.GetItemsArray()
	local items = {}

	for _, item in ipairs(getMergedItems()) do
		table.insert(items, copyItem(item))
	end

	return items
end

function FurnitureCatalogConfig.GetPublicCatalog()
	local publicItems = {}

	for _, item in ipairs(getMergedItems()) do
		table.insert(publicItems, copyFields(item, PUBLIC_FIELDS))
	end

	return publicItems
end

return FurnitureCatalogConfig
