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
	"PurchaseCurrency",
	"TradableOnPurchase",
	"Sellable",
	"PermissionActions",
	"SupportsOpenClose",
	"Featured",
	"IsLimited",
	"LimitedQuantity",
	"RemainingStock",
}

local itemsById = {}
local itemsByTemplateName = {}

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

function FurnitureCatalogConfig.GetItem(itemId)
	if typeof(itemId) ~= "string" then
		return nil
	end

	local item = itemsById[itemId] or itemsByTemplateName[itemId]

	if not item then
		return nil
	end

	return copyItem(item)
end

function FurnitureCatalogConfig.GetItemsArray()
	local items = {}

	for _, item in ipairs(ITEMS) do
		table.insert(items, copyItem(item))
	end

	return items
end

function FurnitureCatalogConfig.GetPublicCatalog()
	local publicItems = {}

	for _, item in ipairs(ITEMS) do
		table.insert(publicItems, copyFields(item, PUBLIC_FIELDS))
	end

	return publicItems
end

return FurnitureCatalogConfig
