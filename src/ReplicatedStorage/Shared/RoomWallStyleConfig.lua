local RoomWallStyleConfig = {}

RoomWallStyleConfig.DEFAULT_WALL_STYLE_ID = "Default"

local STYLES = {
	{
		WallStyleId = "Default",
		DisplayName = "Default Walls",
		Description = "Use the wall finish built into the room template.",
		Group = "Starter",
		Pattern = "Default",
		IsDefault = true,
		IsStarter = true,
		CanPurchase = false,
		SortOrder = 10,
		Colors = {},
		Materials = {},
	},
	{
		WallStyleId = "Cream",
		DisplayName = "Cream Walls",
		Description = "A clean warm wall paint for starter rooms.",
		Group = "Starter",
		Pattern = "Plain",
		IsDefault = false,
		IsStarter = true,
		CanPurchase = false,
		SortOrder = 20,
		Colors = {
			Base = Color3.fromRGB(232, 220, 196),
		},
		Materials = {
			Base = Enum.Material.SmoothPlastic,
		},
	},
	{
		WallStyleId = "Blue",
		DisplayName = "Blue Walls",
		Description = "A quiet blue paint finish for calm room builds.",
		Group = "Classic",
		Pattern = "Plain",
		IsDefault = false,
		IsStarter = false,
		CanPurchase = true,
		CurrencyKey = "Dollars",
		Price = 80,
		SortOrder = 30,
		Colors = {
			Base = Color3.fromRGB(157, 184, 199),
		},
		Materials = {
			Base = Enum.Material.SmoothPlastic,
		},
	},
	{
		WallStyleId = "Mint",
		DisplayName = "Mint Walls",
		Description = "A fresh green wall finish with a soft hotel tone.",
		Group = "Classic",
		Pattern = "Plain",
		IsDefault = false,
		IsStarter = false,
		CanPurchase = true,
		CurrencyKey = "Dollars",
		Price = 80,
		SortOrder = 40,
		Colors = {
			Base = Color3.fromRGB(172, 203, 183),
		},
		Materials = {
			Base = Enum.Material.SmoothPlastic,
		},
	},
	{
		WallStyleId = "Rose",
		DisplayName = "Rose Walls",
		Description = "A muted rose paint finish for softer room styling.",
		Group = "Classic",
		Pattern = "Plain",
		IsDefault = false,
		IsStarter = false,
		CanPurchase = true,
		CurrencyKey = "Dollars",
		Price = 85,
		SortOrder = 50,
		Colors = {
			Base = Color3.fromRGB(207, 171, 178),
		},
		Materials = {
			Base = Enum.Material.SmoothPlastic,
		},
	},
	{
		WallStyleId = "Stripe",
		DisplayName = "Striped Walls",
		Description = "Simple vertical wall stripes for patterned rooms.",
		Group = "Pattern",
		Pattern = "Stripe",
		IsDefault = false,
		IsStarter = false,
		CanPurchase = true,
		CurrencyKey = "Dollars",
		Price = 115,
		SortOrder = 60,
		Colors = {
			Base = Color3.fromRGB(222, 214, 192),
			Stripe = Color3.fromRGB(150, 174, 188),
		},
		Materials = {
			Base = Enum.Material.SmoothPlastic,
			Stripe = Enum.Material.SmoothPlastic,
		},
	},
	{
		WallStyleId = "WallpaperPattern",
		DisplayName = "Wallpaper Pattern",
		Description = "A repeating wallpaper-inspired wall finish.",
		Group = "Pattern",
		Pattern = "WallpaperPattern",
		IsDefault = false,
		IsStarter = false,
		CanPurchase = true,
		CurrencyKey = "Dollars",
		Price = 135,
		SortOrder = 70,
		Colors = {
			Base = Color3.fromRGB(225, 214, 191),
			Accent = Color3.fromRGB(134, 112, 148),
			Border = Color3.fromRGB(177, 151, 103),
		},
		Materials = {
			Base = Enum.Material.SmoothPlastic,
			Accent = Enum.Material.SmoothPlastic,
			Border = Enum.Material.Wood,
		},
	},
	{
		WallStyleId = "Brick",
		DisplayName = "Brick Walls",
		Description = "A simple brick-style wall finish for textured rooms.",
		Group = "Pattern",
		Pattern = "Brick",
		IsDefault = false,
		IsStarter = false,
		CanPurchase = true,
		CurrencyKey = "Dollars",
		Price = 150,
		SortOrder = 80,
		Colors = {
			Base = Color3.fromRGB(143, 95, 76),
			Mortar = Color3.fromRGB(218, 201, 181),
		},
		Materials = {
			Base = Enum.Material.Brick,
			Mortar = Enum.Material.SmoothPlastic,
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

		return tostring(a.WallStyleId) < tostring(b.WallStyleId)
	end)

	return styles
end

for _, style in ipairs(STYLES) do
	stylesById[style.WallStyleId] = style
end

local function normalizeApplyPrice(style)
	local price = style and style.Price

	if typeof(price) ~= "number"
		or price ~= price
		or price < 0
		or price == math.huge then

		return 0
	end

	return math.floor(price)
end

function RoomWallStyleConfig.GetStyle(wallStyleId)
	if typeof(wallStyleId) ~= "string" or wallStyleId == "" then
		return nil
	end

	local style = stylesById[wallStyleId]

	if not style then
		return nil
	end

	return copyStyle(style)
end

function RoomWallStyleConfig.GetAllStyles()
	local styles = {}

	for _, style in ipairs(STYLES) do
		table.insert(styles, copyStyle(style))
	end

	return sortStyles(styles)
end

function RoomWallStyleConfig.GetDefaultStyle()
	local style = stylesById[RoomWallStyleConfig.DEFAULT_WALL_STYLE_ID]

	if not style then
		return nil
	end

	return copyStyle(style)
end

function RoomWallStyleConfig.GetDefaultStyleId()
	return RoomWallStyleConfig.DEFAULT_WALL_STYLE_ID
end

function RoomWallStyleConfig.GetStarterStyles()
	local styles = {}

	for _, style in ipairs(STYLES) do
		if style.IsStarter == true or style.IsDefault == true then
			table.insert(styles, copyStyle(style))
		end
	end

	return sortStyles(styles)
end

function RoomWallStyleConfig.GetPurchasableStyles()
	local styles = {}

	for _, style in ipairs(STYLES) do
		if style.CanPurchase == true then
			table.insert(styles, copyStyle(style))
		end
	end

	return sortStyles(styles)
end

function RoomWallStyleConfig.IsValidStyleId(wallStyleId)
	return typeof(wallStyleId) == "string" and stylesById[wallStyleId] ~= nil
end

function RoomWallStyleConfig.IsFreeStyle(wallStyleId)
	local style = stylesById[wallStyleId]

	if not style then
		return false
	end

	if style.IsDefault == true or style.IsStarter == true then
		return true
	end

	if style.CanPurchase ~= true then
		return true
	end

	return normalizeApplyPrice(style) <= 0
end

function RoomWallStyleConfig.GetApplyCost(wallStyleId)
	local style = stylesById[wallStyleId]

	if not style then
		return nil, nil, "Wall style not found."
	end

	if RoomWallStyleConfig.IsFreeStyle(wallStyleId) then
		return 0, style.CurrencyKey or "Dollars", "Wall style is free."
	end

	return normalizeApplyPrice(style), style.CurrencyKey or "Dollars", "Wall style has an apply cost."
end

function RoomWallStyleConfig.CanPreviewStyle(wallStyleId, context)
	local style = stylesById[wallStyleId]

	if not style then
		return false, "Wall style not found."
	end

	if typeof(context) == "table"
		and (context.AllowHiddenWallStyles == true or context.IsStudioPreview == true) then

		return true, "Wall style available for preview."
	end

	if style.Hidden == true or style.IsHidden == true or style.DevOnly == true then
		return false, "Wall style is not available."
	end

	return true, "Wall style available for preview."
end

function RoomWallStyleConfig.CanApplyWithoutPayment(wallStyleId, context)
	if not RoomWallStyleConfig.IsValidStyleId(wallStyleId) then
		return false, "Wall style not found."
	end

	if typeof(context) == "table" and context.AllowAllWallStyles == true then
		return true, "Wall style available."
	end

	if RoomWallStyleConfig.IsFreeStyle(wallStyleId) then
		return true, "Wall style can be applied for free."
	end

	return false, "Payment required to apply this wall style."
end

return RoomWallStyleConfig
