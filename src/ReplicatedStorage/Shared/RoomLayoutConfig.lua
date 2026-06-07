local RoomLayoutConfig = {}

RoomLayoutConfig.ACCESS_FREE = "Free"
RoomLayoutConfig.ACCESS_VIP = "VIP"
RoomLayoutConfig.ACCESS_DEV = "Dev"

RoomLayoutConfig.STATUS_AVAILABLE = "Available"
RoomLayoutConfig.STATUS_UNAVAILABLE = "Unavailable"

local ACCESS_FREE = RoomLayoutConfig.ACCESS_FREE
local ACCESS_VIP = RoomLayoutConfig.ACCESS_VIP
local ACCESS_DEV = RoomLayoutConfig.ACCESS_DEV
local STATUS_AVAILABLE = RoomLayoutConfig.STATUS_AVAILABLE
local STATUS_UNAVAILABLE = RoomLayoutConfig.STATUS_UNAVAILABLE

-- MaxVisitors is a first-pass planning value. Exact capacity limits can be
-- tuned per layout after room templates and performance budgets exist.
local LAYOUTS = {
	{
		LayoutId = "Free_104_A",
		DisplayName = "Courtyard Studio",
		TileCount = 104,
		TileSize = 4,
		GridWidth = 13,
		GridDepth = 8,
		AccessTier = ACCESS_FREE,
		RequiresVip = false,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_Free_104_A",
		PreviewKey = "free_104_a",
		SizeClass = "Small",
		MaxVisitors = 25,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = false,
		Notes = "Free starter-scale layout with an open social center.",
	},
	{
		LayoutId = "Free_094_A",
		DisplayName = "Corner Nook",
		TileCount = 94,
		AccessTier = ACCESS_FREE,
		RequiresVip = false,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_Free_094_A",
		PreviewKey = "free_094_a",
		SizeClass = "Small",
		MaxVisitors = 25,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = false,
		Notes = "Free compact layout with an asymmetric footprint.",
	},
	{
		LayoutId = "Free_036_A",
		DisplayName = "Pocket Room",
		TileCount = 36,
		TileSize = 4,
		GridWidth = 6,
		GridDepth = 6,
		AccessTier = ACCESS_FREE,
		RequiresVip = false,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_Free_036_A",
		PreviewKey = "free_036_a",
		SizeClass = "Small",
		MaxVisitors = 25,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = false,
		Notes = "Free minimal layout for focused decoration.",
	},
	{
		LayoutId = "MaskTest_Hole_036",
		DisplayName = "DEV Mask Test Hole",
		TileCount = 35,
		TileSize = 4,
		GridWidth = 6,
		GridDepth = 6,
		AccessTier = ACCESS_DEV,
		RequiresVip = false,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		IsDevOnly = true,
		TemplateName = "RoomLayout_MaskTest_Hole_036",
		PreviewKey = "mask_test_hole_036",
		SizeClass = "Dev",
		MaxVisitors = 25,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = false,
		UsesTileMask = true,
		Notes = "Studio/admin-only TileMask test layout with one hole.",
	},
	{
		LayoutId = "Free_084_A",
		DisplayName = "Side Hall",
		TileCount = 84,
		TileSize = 4,
		GridWidth = 7,
		GridDepth = 12,
		AccessTier = ACCESS_FREE,
		RequiresVip = false,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_Free_084_A",
		PreviewKey = "free_084_a",
		SizeClass = "Small",
		MaxVisitors = 25,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = false,
		Notes = "Free layout with a narrow side-wing shape.",
	},
	{
		LayoutId = "Free_080_A",
		DisplayName = "Twin Alcove A",
		TileCount = 80,
		TileSize = 4,
		GridWidth = 10,
		GridDepth = 8,
		AccessTier = ACCESS_FREE,
		RequiresVip = false,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_Free_080_A",
		PreviewKey = "free_080_a",
		SizeClass = "Small",
		MaxVisitors = 25,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = false,
		Notes = "Free 80-tile variant with one layout shape.",
	},
	{
		LayoutId = "Free_080_B",
		DisplayName = "Twin Alcove B",
		TileCount = 80,
		TileSize = 4,
		GridWidth = 8,
		GridDepth = 10,
		AccessTier = ACCESS_FREE,
		RequiresVip = false,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_Free_080_B",
		PreviewKey = "free_080_b",
		SizeClass = "Small",
		MaxVisitors = 25,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = false,
		Notes = "Free 80-tile variant with a different shape from Free_080_A.",
	},
	{
		LayoutId = "Free_416_A",
		DisplayName = "Grand Gallery",
		TileCount = 416,
		TileSize = 4,
		GridWidth = 26,
		GridDepth = 16,
		AccessTier = ACCESS_FREE,
		RequiresVip = false,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_Free_416_A",
		PreviewKey = "free_416_a",
		SizeClass = "Large",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = false,
		Notes = "Free large social layout.",
	},
	{
		LayoutId = "Free_320_A",
		DisplayName = "Terrace Hall",
		TileCount = 320,
		TileSize = 4,
		GridWidth = 20,
		GridDepth = 16,
		AccessTier = ACCESS_FREE,
		RequiresVip = false,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_Free_320_A",
		PreviewKey = "free_320_a",
		SizeClass = "Large",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = false,
		Notes = "Free large layout with broad decorating zones.",
	},
	{
		LayoutId = "Free_448_A",
		DisplayName = "Atrium Span",
		TileCount = 448,
		AccessTier = ACCESS_FREE,
		RequiresVip = false,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_Free_448_A",
		PreviewKey = "free_448_a",
		SizeClass = "Large",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = false,
		Notes = "Free extra-large layout for busy rooms.",
	},
	{
		LayoutId = "Free_352_A",
		DisplayName = "Open Arcade",
		TileCount = 352,
		TileSize = 4,
		GridWidth = 22,
		GridDepth = 16,
		AccessTier = ACCESS_FREE,
		RequiresVip = false,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_Free_352_A",
		PreviewKey = "free_352_a",
		SizeClass = "Large",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = false,
		Notes = "Free large layout with room for activity zones.",
	},
	{
		LayoutId = "Free_384_A",
		DisplayName = "Cross Court",
		TileCount = 384,
		TileSize = 4,
		GridWidth = 24,
		GridDepth = 16,
		AccessTier = ACCESS_FREE,
		RequiresVip = false,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_Free_384_A",
		PreviewKey = "free_384_a",
		SizeClass = "Large",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = false,
		Notes = "Free large layout with a cross-shaped planning reference.",
	},
	{
		LayoutId = "Free_372_A",
		DisplayName = "Wide Landing",
		TileCount = 372,
		AccessTier = ACCESS_FREE,
		RequiresVip = false,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_Free_372_A",
		PreviewKey = "free_372_a",
		SizeClass = "Large",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = false,
		Notes = "Free large layout with a wide landing area.",
	},
	{
		LayoutId = "VIP_080_A",
		DisplayName = "VIP Split Nook",
		TileCount = 80,
		TileSize = 4,
		GridWidth = 8,
		GridDepth = 10,
		AccessTier = ACCESS_VIP,
		RequiresVip = true,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_VIP_080_A",
		PreviewKey = "vip_080_a",
		SizeClass = "Small",
		MaxVisitors = 25,
		OwnerExtraSlot = true,
		HasStairs = true,
		HasLevels = true,
		HasHiddenArea = false,
		Notes = "VIP compact layout with a raised area.",
	},
	{
		LayoutId = "VIP_074_A",
		DisplayName = "VIP Hidden Nook",
		TileCount = 74,
		AccessTier = ACCESS_VIP,
		RequiresVip = true,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_VIP_074_A",
		PreviewKey = "vip_074_a",
		SizeClass = "Small",
		MaxVisitors = 25,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = true,
		Notes = "VIP compact layout with a secret side area.",
	},
	{
		LayoutId = "VIP_416_A",
		DisplayName = "VIP Skyline Gallery",
		TileCount = 416,
		AccessTier = ACCESS_VIP,
		RequiresVip = true,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_VIP_416_A",
		PreviewKey = "vip_416_a",
		SizeClass = "Large",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = true,
		HasLevels = true,
		HasHiddenArea = false,
		Notes = "VIP large layout planned for multi-level decorating.",
	},
	{
		LayoutId = "VIP_352_A",
		DisplayName = "VIP Sunken Court",
		TileCount = 352,
		AccessTier = ACCESS_VIP,
		RequiresVip = true,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_VIP_352_A",
		PreviewKey = "vip_352_a",
		SizeClass = "Large",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = true,
		HasLevels = true,
		HasHiddenArea = true,
		Notes = "VIP large layout planned with stairs and a hidden pocket.",
	},
	{
		LayoutId = "VIP_304_A",
		DisplayName = "VIP Bridge Room",
		TileCount = 304,
		TileSize = 4,
		GridWidth = 19,
		GridDepth = 16,
		AccessTier = ACCESS_VIP,
		RequiresVip = true,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_VIP_304_A",
		PreviewKey = "vip_304_a",
		SizeClass = "Large",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = true,
		HasLevels = true,
		HasHiddenArea = false,
		Notes = "VIP large layout planned around split platforms.",
	},
	{
		LayoutId = "VIP_336_A",
		DisplayName = "VIP Crescent Hall",
		TileCount = 336,
		AccessTier = ACCESS_VIP,
		RequiresVip = true,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_VIP_336_A",
		PreviewKey = "vip_336_a",
		SizeClass = "Large",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = true,
		HasLevels = true,
		HasHiddenArea = true,
		Notes = "VIP large layout with a concealed side zone planned.",
	},
	{
		LayoutId = "VIP_748_A",
		DisplayName = "VIP Grand Maze",
		TileCount = 748,
		AccessTier = ACCESS_VIP,
		RequiresVip = true,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_VIP_748_A",
		PreviewKey = "vip_748_a",
		SizeClass = "Huge",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = true,
		HasLevels = true,
		HasHiddenArea = true,
		Notes = "VIP huge layout planned for complex paths and secret areas.",
	},
	{
		LayoutId = "VIP_438_A",
		DisplayName = "VIP Tower Walk",
		TileCount = 438,
		AccessTier = ACCESS_VIP,
		RequiresVip = true,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_VIP_438_A",
		PreviewKey = "vip_438_a",
		SizeClass = "Large",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = true,
		HasLevels = true,
		HasHiddenArea = false,
		Notes = "VIP large layout planned with tall platform movement.",
	},
	{
		LayoutId = "VIP_540_A",
		DisplayName = "VIP Deep Atrium",
		TileCount = 540,
		AccessTier = ACCESS_VIP,
		RequiresVip = true,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_VIP_540_A",
		PreviewKey = "vip_540_a",
		SizeClass = "Huge",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = true,
		HasLevels = true,
		HasHiddenArea = true,
		Notes = "VIP huge layout planned for multi-level social rooms.",
	},
	{
		LayoutId = "VIP_512_A",
		DisplayName = "VIP Upper Plaza",
		TileCount = 512,
		AccessTier = ACCESS_VIP,
		RequiresVip = true,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_VIP_512_A",
		PreviewKey = "vip_512_a",
		SizeClass = "Huge",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = true,
		HasLevels = true,
		HasHiddenArea = false,
		Notes = "VIP huge layout planned with upper and lower build zones.",
	},
	{
		LayoutId = "VIP_396_A",
		DisplayName = "VIP Stepped Loft",
		TileCount = 396,
		AccessTier = ACCESS_VIP,
		RequiresVip = true,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_VIP_396_A",
		PreviewKey = "vip_396_a",
		SizeClass = "Large",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = true,
		HasLevels = true,
		HasHiddenArea = false,
		Notes = "VIP large layout planned around stepped elevation changes.",
	},
	{
		LayoutId = "VIP_440_A",
		DisplayName = "VIP Hidden Terrace",
		TileCount = 440,
		AccessTier = ACCESS_VIP,
		RequiresVip = true,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_VIP_440_A",
		PreviewKey = "vip_440_a",
		SizeClass = "Large",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = true,
		HasLevels = true,
		HasHiddenArea = true,
		Notes = "VIP large layout planned with a secret terrace.",
	},
	{
		LayoutId = "VIP_456_A",
		DisplayName = "VIP Layered Square",
		TileCount = 456,
		AccessTier = ACCESS_VIP,
		RequiresVip = true,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_VIP_456_A",
		PreviewKey = "vip_456_a",
		SizeClass = "Large",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = true,
		HasLevels = true,
		HasHiddenArea = false,
		Notes = "VIP large layout planned for layered room builds.",
	},
	{
		LayoutId = "VIP_208_A",
		DisplayName = "VIP Hollow Hall",
		TileCount = 208,
		TileSize = 4,
		GridWidth = 13,
		GridDepth = 16,
		AccessTier = ACCESS_VIP,
		RequiresVip = true,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_VIP_208_A",
		PreviewKey = "vip_208_a",
		SizeClass = "Medium",
		MaxVisitors = 25,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = true,
		Notes = "VIP medium layout planned with an internal hole or void.",
	},
	{
		LayoutId = "VIP_1009_A",
		DisplayName = "VIP Monument Room",
		TileCount = 1009,
		AccessTier = ACCESS_VIP,
		RequiresVip = true,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_VIP_1009_A",
		PreviewKey = "vip_1009_a",
		SizeClass = "Huge",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = true,
		HasLevels = true,
		HasHiddenArea = true,
		Notes = "VIP very large layout planned for showpiece rooms.",
	},
	{
		LayoutId = "VIP_1044_A",
		DisplayName = "VIP Skyline Estate",
		TileCount = 1044,
		AccessTier = ACCESS_VIP,
		RequiresVip = true,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_VIP_1044_A",
		PreviewKey = "vip_1044_a",
		SizeClass = "Huge",
		MaxVisitors = 50,
		OwnerExtraSlot = true,
		HasStairs = true,
		HasLevels = true,
		HasHiddenArea = true,
		Notes = "VIP very large layout planned with multiple distinct zones.",
	},
	{
		LayoutId = "VIP_183_A",
		DisplayName = "VIP Secret Steps",
		TileCount = 183,
		AccessTier = ACCESS_VIP,
		RequiresVip = true,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_VIP_183_A",
		PreviewKey = "vip_183_a",
		SizeClass = "Medium",
		MaxVisitors = 25,
		OwnerExtraSlot = true,
		HasStairs = true,
		HasLevels = true,
		HasHiddenArea = true,
		Notes = "VIP medium layout planned with stairs and a hidden area.",
	},
	{
		LayoutId = "VIP_254_A",
		DisplayName = "VIP Split Garden",
		TileCount = 254,
		AccessTier = ACCESS_VIP,
		RequiresVip = true,
		Status = STATUS_AVAILABLE,
		IsSelectable = true,
		TemplateName = "RoomLayout_VIP_254_A",
		PreviewKey = "vip_254_a",
		SizeClass = "Medium",
		MaxVisitors = 25,
		OwnerExtraSlot = true,
		HasStairs = true,
		HasLevels = true,
		HasHiddenArea = false,
		Notes = "VIP medium layout planned with split-level decoration areas.",
	},
	{
		LayoutId = "Legacy_035_StarterV1",
		DisplayName = "Legacy Starter V1",
		TileCount = 35,
		AccessTier = ACCESS_FREE,
		RequiresVip = false,
		Status = STATUS_UNAVAILABLE,
		IsSelectable = false,
		TemplateName = "RoomLayout_Legacy_035_StarterV1",
		PreviewKey = "legacy_035_starter_v1",
		SizeClass = "Small",
		MaxVisitors = 25,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = false,
		Notes = "Unavailable legacy 35-tile starter room V1.",
	},
	{
		LayoutId = "Legacy_080_StarterV2Furnished",
		DisplayName = "Legacy Starter V2 Furnished",
		TileCount = 80,
		AccessTier = ACCESS_FREE,
		RequiresVip = false,
		Status = STATUS_UNAVAILABLE,
		IsSelectable = false,
		TemplateName = "RoomLayout_Legacy_080_StarterV2Furnished",
		PreviewKey = "legacy_080_starter_v2_furnished",
		SizeClass = "Small",
		MaxVisitors = 25,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = false,
		Notes = "Unavailable legacy 80-tile starter room V2 with preloaded furniture.",
	},
	{
		LayoutId = "Legacy_180_BundleVoyage",
		DisplayName = "Legacy Voyage Bundle",
		TileCount = 180,
		AccessTier = ACCESS_FREE,
		RequiresVip = false,
		Status = STATUS_UNAVAILABLE,
		IsSelectable = false,
		TemplateName = "RoomLayout_Legacy_180_BundleVoyage",
		PreviewKey = "legacy_180_bundle_voyage",
		SizeClass = "Medium",
		MaxVisitors = 25,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = false,
		Notes = "Unavailable legacy 180-tile captain-style bundle reference.",
	},
	{
		LayoutId = "Legacy_156_BundleShadow",
		DisplayName = "Legacy Shadow Bundle",
		TileCount = 156,
		AccessTier = ACCESS_FREE,
		RequiresVip = false,
		Status = STATUS_UNAVAILABLE,
		IsSelectable = false,
		TemplateName = "RoomLayout_Legacy_156_BundleShadow",
		PreviewKey = "legacy_156_bundle_shadow",
		SizeClass = "Medium",
		MaxVisitors = 25,
		OwnerExtraSlot = true,
		HasStairs = false,
		HasLevels = false,
		HasHiddenArea = true,
		Notes = "Unavailable legacy 156-tile bogeyman-style bundle reference.",
	},
}

local layoutsById = {}

for _, layout in ipairs(LAYOUTS) do
	layoutsById[layout.LayoutId] = layout
end

local function copyLayout(layout)
	if typeof(layout) ~= "table" then
		return nil
	end

	local copy = {}

	for key, value in pairs(layout) do
		copy[key] = value
	end

	return copy
end

local function shouldIncludeLayout(layout, options)
	options = typeof(options) == "table" and options or {}

	if options.IncludeUnavailable == false and layout.Status == STATUS_UNAVAILABLE then
		return false
	end

	if options.SelectableOnly == true and layout.IsSelectable ~= true then
		return false
	end

	if layout.IsDevOnly == true and options.IncludeDevOnly ~= true then
		return false
	end

	if typeof(options.AccessTier) == "string" and options.AccessTier ~= "" then
		return layout.AccessTier == options.AccessTier
	end

	return true
end

local function getAccessSortOrder(accessTier)
	if accessTier == ACCESS_FREE then
		return 1
	elseif accessTier == ACCESS_VIP then
		return 2
	elseif accessTier == ACCESS_DEV then
		return 3
	end

	return 4
end

local function sortLayouts(layouts)
	table.sort(layouts, function(a, b)
		local aSelectable = a.IsSelectable == true
		local bSelectable = b.IsSelectable == true

		if aSelectable ~= bSelectable then
			return aSelectable
		end

		local aAccessOrder = getAccessSortOrder(a.AccessTier)
		local bAccessOrder = getAccessSortOrder(b.AccessTier)

		if aAccessOrder ~= bAccessOrder then
			return aAccessOrder < bAccessOrder
		end

		if a.TileCount ~= b.TileCount then
			return a.TileCount < b.TileCount
		end

		return tostring(a.LayoutId) < tostring(b.LayoutId)
	end)

	return layouts
end

function RoomLayoutConfig.GetLayout(layoutId)
	if typeof(layoutId) ~= "string" or layoutId == "" then
		return nil
	end

	return copyLayout(layoutsById[layoutId])
end

function RoomLayoutConfig.GetAllLayouts(options)
	local layouts = {}

	for _, layout in ipairs(LAYOUTS) do
		if shouldIncludeLayout(layout, options) then
			table.insert(layouts, copyLayout(layout))
		end
	end

	return sortLayouts(layouts)
end

function RoomLayoutConfig.GetSelectableLayouts(options)
	options = typeof(options) == "table" and options or {}

	local query = {}

	for key, value in pairs(options) do
		query[key] = value
	end

	query.SelectableOnly = true
	query.IncludeUnavailable = false

	return RoomLayoutConfig.GetAllLayouts(query)
end

function RoomLayoutConfig.GetLayoutsByAccessTier(accessTier)
	return RoomLayoutConfig.GetAllLayouts({
		AccessTier = accessTier,
	})
end

function RoomLayoutConfig.GetFreeLayouts()
	return RoomLayoutConfig.GetLayoutsByAccessTier(ACCESS_FREE)
end

function RoomLayoutConfig.GetVipLayouts()
	return RoomLayoutConfig.GetLayoutsByAccessTier(ACCESS_VIP)
end

function RoomLayoutConfig.GetUnavailableLayouts()
	local layouts = {}

	for _, layout in ipairs(LAYOUTS) do
		if layout.Status == STATUS_UNAVAILABLE then
			table.insert(layouts, copyLayout(layout))
		end
	end

	return sortLayouts(layouts)
end

function RoomLayoutConfig.IsValidLayoutId(layoutId)
	return typeof(layoutId) == "string" and layoutsById[layoutId] ~= nil
end

function RoomLayoutConfig.CanUseLayout(layoutId, context)
	local layout = layoutsById[layoutId]

	if not layout then
		return false, "Layout not found."
	end

	context = typeof(context) == "table" and context or {}

	if layout.Status == STATUS_UNAVAILABLE and context.IncludeUnavailable ~= true then
		return false, "This layout is currently unavailable."
	end

	if layout.IsDevOnly == true and context.CanUseDevOnly ~= true and context.HasVip ~= true then
		return false, "This layout is only available for testing."
	end

	if layout.RequiresVip == true and context.HasVip ~= true then
		return false, "This layout requires VIP."
	end

	return true, "Layout available."
end

return RoomLayoutConfig
