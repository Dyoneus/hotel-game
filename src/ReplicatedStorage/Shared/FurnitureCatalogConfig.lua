local FurnitureCatalogConfig = {}

local ITEMS = {
	{
		Id = "Chair_01",
		TemplateName = "Chair_01",
		DisplayName = "Starter Chair",
		Description = "A basic chair for sitting.",
		MaxPerRoom = 12,
		Category = "Chairs",
		Price = 25,
		SellPrice = 10,
		PurchaseCurrency = "Dollars",
		TradableOnPurchase = false,
		Sellable = true,
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
		Price = 50,
		SellPrice = 20,
		PurchaseCurrency = "Dollars",
		TradableOnPurchase = false,
		Sellable = true,
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
		Price = 100,
		SellPrice = 40,
		PurchaseCurrency = "Dollars",
		TradableOnPurchase = false,
		Sellable = true,
		Featured = false,
		IsLimited = false,
	},
}

local PUBLIC_FIELDS = {
	"Id",
	"TemplateName",
	"DisplayName",
	"Description",
	"MaxPerRoom",
	"Category",
	"Price",
	"SellPrice",
	"PurchaseCurrency",
	"TradableOnPurchase",
	"Sellable",
	"Featured",
	"IsLimited",
	"LimitedQuantity",
	"RemainingStock",
}

local itemsById = {}
local itemsByTemplateName = {}

local function copyFields(item, fields)
	local copy = {}

	for _, fieldName in ipairs(fields) do
		copy[fieldName] = item[fieldName]
	end

	return copy
end

local function copyItem(item)
	local copy = {}

	for key, value in pairs(item) do
		copy[key] = value
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
