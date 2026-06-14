local RoomFloorStyleConfig = {}

RoomFloorStyleConfig.DEFAULT_FLOOR_STYLE_ID = "Grid"

local STYLES = {
	{
		FloorStyleId = "Grid",
		DisplayName = "Grid Floor",
		Description = "A clean tile planning grid for starter rooms.",
		Group = "Starter",
		Pattern = "Grid",
		IsDefault = true,
		IsStarter = true,
		CanPurchase = false,
		SortOrder = 10,
		Colors = {
			Base = Color3.fromRGB(176, 184, 178),
			Line = Color3.fromRGB(103, 126, 119),
			Border = Color3.fromRGB(78, 96, 90),
		},
		Materials = {
			Base = Enum.Material.SmoothPlastic,
			Line = Enum.Material.SmoothPlastic,
			Border = Enum.Material.SmoothPlastic,
		},
	},
	{
		FloorStyleId = "Plain",
		DisplayName = "Plain Floor",
		Description = "A simple warm finish without grid markings.",
		Group = "Starter",
		Pattern = "Plain",
		IsDefault = false,
		IsStarter = true,
		CanPurchase = false,
		SortOrder = 20,
		Colors = {
			Base = Color3.fromRGB(190, 178, 154),
			Border = Color3.fromRGB(124, 111, 91),
		},
		Materials = {
			Base = Enum.Material.SmoothPlastic,
			Border = Enum.Material.SmoothPlastic,
		},
	},
	{
		FloorStyleId = "Carpet",
		DisplayName = "Carpet Floor",
		Description = "A soft fabric floor finish with a subtle inset border.",
		Group = "Classic",
		Pattern = "Carpet",
		IsDefault = false,
		IsStarter = false,
		CanPurchase = true,
		CurrencyKey = "Dollars",
		Price = 75,
		SortOrder = 30,
		Colors = {
			Base = Color3.fromRGB(127, 101, 114),
			Panel = Color3.fromRGB(151, 121, 134),
			Border = Color3.fromRGB(91, 73, 84),
		},
		Materials = {
			Base = Enum.Material.Fabric,
			Panel = Enum.Material.Fabric,
			Border = Enum.Material.Fabric,
		},
	},
	{
		FloorStyleId = "Wood",
		DisplayName = "Wood Floor",
		Description = "A plank-style wood finish for warm room builds.",
		Group = "Classic",
		Pattern = "Wood",
		IsDefault = false,
		IsStarter = false,
		CanPurchase = true,
		CurrencyKey = "Dollars",
		Price = 90,
		SortOrder = 40,
		Colors = {
			Base = Color3.fromRGB(142, 101, 67),
			PlankA = Color3.fromRGB(155, 111, 72),
			PlankB = Color3.fromRGB(119, 82, 55),
			Line = Color3.fromRGB(86, 60, 42),
		},
		Materials = {
			Base = Enum.Material.Wood,
			Plank = Enum.Material.Wood,
			Line = Enum.Material.Wood,
		},
	},
	{
		FloorStyleId = "Checker",
		DisplayName = "Checker Floor",
		Description = "Alternating tile patches for bold patterned rooms.",
		Group = "Pattern",
		Pattern = "Checker",
		IsDefault = false,
		IsStarter = false,
		CanPurchase = true,
		CurrencyKey = "Dollars",
		Price = 110,
		SortOrder = 50,
		Colors = {
			TileA = Color3.fromRGB(225, 219, 199),
			TileB = Color3.fromRGB(92, 104, 109),
			Border = Color3.fromRGB(61, 72, 77),
		},
		Materials = {
			Tile = Enum.Material.SmoothPlastic,
			Border = Enum.Material.SmoothPlastic,
		},
	},
	{
		FloorStyleId = "Pebble",
		DisplayName = "Pebble Floor",
		Description = "A stone-pebble finish with deterministic surface accents.",
		Group = "Natural",
		Pattern = "Pebble",
		IsDefault = false,
		IsStarter = false,
		CanPurchase = true,
		CurrencyKey = "Dollars",
		Price = 125,
		SortOrder = 60,
		Colors = {
			Base = Color3.fromRGB(125, 128, 119),
			PebbleA = Color3.fromRGB(162, 162, 149),
			PebbleB = Color3.fromRGB(99, 105, 99),
			PebbleC = Color3.fromRGB(185, 179, 160),
		},
		Materials = {
			Base = Enum.Material.Slate,
			Pebble = Enum.Material.Slate,
		},
	},
	{
		FloorStyleId = "Stripe",
		DisplayName = "Stripe Floor",
		Description = "Long alternating bands for simple graphic room styling.",
		Group = "Pattern",
		Pattern = "Stripe",
		IsDefault = false,
		IsStarter = false,
		CanPurchase = true,
		CurrencyKey = "Dollars",
		Price = 95,
		SortOrder = 70,
		Colors = {
			StripeA = Color3.fromRGB(108, 132, 146),
			StripeB = Color3.fromRGB(182, 190, 183),
			Border = Color3.fromRGB(70, 91, 104),
		},
		Materials = {
			Stripe = Enum.Material.SmoothPlastic,
			Border = Enum.Material.SmoothPlastic,
		},
	},
}

local stylesById = {}

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

local function copyStyle(style)
	return copyValue(style)
end

local function sortStyles(styles)
	table.sort(styles, function(a, b)
		local aOrder = typeof(a.SortOrder) == "number" and a.SortOrder or math.huge
		local bOrder = typeof(b.SortOrder) == "number" and b.SortOrder or math.huge

		if aOrder ~= bOrder then
			return aOrder < bOrder
		end

		return tostring(a.FloorStyleId) < tostring(b.FloorStyleId)
	end)

	return styles
end

local function hasContextUnlock(floorStyleId, context)
	if typeof(context) ~= "table" then
		return false
	end

	if context.AllowAllFloorStyles == true
		or context.AllowPurchasableStyles == true
		or context.IsStudioPreview == true then

		return true
	end

	local ownedStyles = context.OwnedFloorStyles
		or context.UnlockedFloorStyles
		or context.FloorStyles

	if typeof(ownedStyles) ~= "table" then
		return false
	end

	local entry = ownedStyles[floorStyleId]

	if entry == true then
		return true
	end

	if typeof(entry) == "table" then
		if entry.Unlocked == true then
			return true
		end

		if typeof(entry.Count) == "number" and entry.Count > 0 then
			return true
		end
	end

	return false
end

for _, style in ipairs(STYLES) do
	stylesById[style.FloorStyleId] = style
end

function RoomFloorStyleConfig.GetStyle(floorStyleId)
	if typeof(floorStyleId) ~= "string" or floorStyleId == "" then
		return nil
	end

	local style = stylesById[floorStyleId]

	if not style then
		return nil
	end

	return copyStyle(style)
end

function RoomFloorStyleConfig.GetAllStyles()
	local styles = {}

	for _, style in ipairs(STYLES) do
		table.insert(styles, copyStyle(style))
	end

	return sortStyles(styles)
end

function RoomFloorStyleConfig.GetDefaultStyle()
	local style = stylesById[RoomFloorStyleConfig.DEFAULT_FLOOR_STYLE_ID]

	if not style then
		return nil
	end

	return copyStyle(style)
end

function RoomFloorStyleConfig.GetDefaultStyleId()
	return RoomFloorStyleConfig.DEFAULT_FLOOR_STYLE_ID
end

function RoomFloorStyleConfig.GetStarterStyles()
	local styles = {}

	for _, style in ipairs(STYLES) do
		if style.IsStarter == true or style.IsDefault == true then
			table.insert(styles, copyStyle(style))
		end
	end

	return sortStyles(styles)
end

function RoomFloorStyleConfig.GetPurchasableStyles()
	local styles = {}

	for _, style in ipairs(STYLES) do
		if style.CanPurchase == true then
			table.insert(styles, copyStyle(style))
		end
	end

	return sortStyles(styles)
end

function RoomFloorStyleConfig.IsValidStyleId(floorStyleId)
	return typeof(floorStyleId) == "string" and stylesById[floorStyleId] ~= nil
end

function RoomFloorStyleConfig.CanUseStyle(floorStyleId, context)
	if typeof(floorStyleId) ~= "string" or floorStyleId == "" then
		return false, "Floor style not found."
	end

	local style = stylesById[floorStyleId]

	if not style then
		return false, "Floor style not found."
	end

	if style.IsDefault == true or style.IsStarter == true or style.CanPurchase ~= true then
		return true, "Floor style available."
	end

	if hasContextUnlock(style.FloorStyleId, context) then
		return true, "Floor style available."
	end

	return false, "Floor style is reserved for future purchase support."
end

return RoomFloorStyleConfig
