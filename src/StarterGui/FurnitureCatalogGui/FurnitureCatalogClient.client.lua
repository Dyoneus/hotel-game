-- StarterGui/FurnitureCatalogGui/FurnitureCatalogClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local playerGui = player:WaitForChild("PlayerGui")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local furnitureCatalogRequest = remoteEvents:WaitForChild("FurnitureCatalogRequest")
local furnitureCatalogResult = remoteEvents:WaitForChild("FurnitureCatalogResult")
local marketplaceRequest = remoteEvents:WaitForChild("MarketplaceRequest")
local marketplaceResult = remoteEvents:WaitForChild("MarketplaceResult")
local currencyRequest = remoteEvents:WaitForChild("CurrencyRequest")
local currencyResult = remoteEvents:WaitForChild("CurrencyResult")
local GridConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GridConfig"))

local activeRooms = workspace:WaitForChild("ActiveRooms")
local furnitureTemplates = ReplicatedStorage:WaitForChild("FurnitureTemplates")

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 160

local ui = {}
ui.FloorFinishes = {
	Offers = {},
	RequestInFlight = false,
	Config = {
		PageName = "Room Finishes",
		SubcategoryName = "Floors",
	},
}
ui.placementMask = {}
ui.placementPreviewVisual = {}
ui.placementStartup = {
	StartId = 0,
	RoomName = nil,
	RoomModel = nil,
	Floor = nil,
	GridContext = nil,
}

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

local latestCatalogItems = {}
local requestInFlight = false
local activePurchaseButton = nil
local activePurchaseButtonText = nil
local selectedCategory = "All"
local catalogViewMode = "FrontPage"
local marketplaceViewMode = "Offers"
local catalogNavButtons = {}
local latestPublicMarketplaceListings = {}
local latestMarketplaceOfferGroups = {}
local latestMySalesListings = {}
local marketplacePublicListingsInFlight = false
local marketplaceMySalesInFlight = false
local marketplaceCancelInFlightByListingId = {}
local marketplaceClaimInFlightByListingId = {}
local marketplacePurchaseInFlightByListingId = {}
local marketplacePurchaseListing = nil
local marketplacePurchaseRequestInFlight = false
local marketplacePurchaseRequestSerial = 0
local pendingPurchaseRequestId = nil
local pendingPurchaseListingId = nil
local pendingPurchaseTemplateId = nil
local marketplaceLastRequestAt = -math.huge
local publicMarketplaceLastRequestAt = -math.huge
local mySalesLastRequestAt = -math.huge
local publicMarketplaceQueuedRefresh = false
local mySalesQueuedRefresh = false
local publicMarketplaceQueuedRefreshScheduled = false
local mySalesQueuedRefreshScheduled = false
local catalogCurrency = {
	Coins = 0,
	Dollars = 0,
	Loaded = false,
	RequestInFlight = false,
	LastRequestAt = -math.huge,
	Serial = 0,
}
local catalogNavExpanded = {
	Furniture = false,
	RoomFinishes = false,
	Marketplace = false,
}

local CATALOG_VIEW = {
	SHOP = "Shop",
	MARKETPLACE = "Marketplace",
	ROOM_FINISHES = "RoomFinishes",
	FRONT_PAGE = "FrontPage",
	PLACEHOLDER = "Placeholder",
}
local MARKETPLACE_VIEW = {
	OFFERS = "Offers",
	MY_LISTINGS = "MyListings",
	MY_SALES = "MySales",
	INSTRUCTIONS = "Instructions",
}
local CATALOG_PAGE = {
	FRONT = "FrontPage",
	COINS = "Coins",
	DOLLARS_INFO = "DollarsInfo",
	BEST_SELLERS = "BestSellers",
	VIP = "VIP",
	FURNITURE_SHOP = "FurnitureShop",
	FURNITURE_BED = "FurnitureBed",
	FURNITURE_CHAIR = "FurnitureChair",
	FURNITURE_DIVIDER = "FurnitureDivider",
	FURNITURE_FLOOR = "FurnitureFloor",
	FURNITURE_FOOD = "FurnitureFood",
	FURNITURE_GATE = "FurnitureGate",
	FURNITURE_LIGHTING = "FurnitureLighting",
	FURNITURE_MUSIC = "FurnitureMusic",
	FURNITURE_OTHER = "FurnitureOther",
	FURNITURE_PETS = "FurniturePets",
	FURNITURE_PRESENT = "FurniturePresent",
	FURNITURE_ROLLER = "FurnitureRoller",
	FURNITURE_RUG = "FurnitureRug",
	FURNITURE_SHELF = "FurnitureShelf",
	FURNITURE_TABLE = "FurnitureTable",
	FURNITURE_WALL_DECORATION = "FurnitureWallDecoration",
	FURNITURE_WALLPAPER = "FurnitureWallpaper",
	FURNITURE_WINDOW = "FurnitureWindow",
	ROOM_FINISHES_FLOORS = "RoomFinishesFloors",
	PETS = "Pets",
	SPECIAL_OFFERS = "SpecialOffers",
	MARKETPLACE_OFFERS = "MarketplaceOffers",
	MARKETPLACE_MY_LISTINGS = "MarketplaceMyListings",
	MARKETPLACE_MY_SALES = "MarketplaceMySales",
	MARKETPLACE_INSTRUCTIONS = "MarketplaceInstructions",
}
local MARKETPLACE_REQUEST_COOLDOWN_SECONDS = 0.7
local REQUEST_TIMEOUT_SECONDS = 6
local selectedCatalogPage = CATALOG_PAGE.FRONT
local placeholderCatalogPage = CATALOG_PAGE.BEST_SELLERS

local CATALOG_NAV_ITEMS = {
	{ Page = CATALOG_PAGE.FRONT, Label = "Front Page", Icon = "FP" },
	{ Page = CATALOG_PAGE.COINS, Label = "Coin Shop", Icon = "$" },
	{ Page = CATALOG_PAGE.DOLLARS_INFO, Label = "How to get Dollars", Icon = "D" },
	{ Page = CATALOG_PAGE.BEST_SELLERS, Label = "Best Sellers", Icon = "*" },
	{ Page = CATALOG_PAGE.VIP, Label = "VIP", Icon = "V" },
	{ Group = "Furniture", Label = "Furniture Shop", Icon = "F" },
	{ Group = "RoomFinishes", Label = "Room Finishes", Icon = "R" },
	{ Page = CATALOG_PAGE.PETS, Label = "Pets", Icon = "P" },
	{ Page = CATALOG_PAGE.SPECIAL_OFFERS, Label = "Special Offers", Icon = "!" },
	{ Group = "Marketplace", Label = "Marketplace", Icon = "M" },
}

local CATALOG_SHOP_CATEGORIES = {
	{ Page = CATALOG_PAGE.FURNITURE_BED, Label = "Bed", Category = "Bed" },
	{ Page = CATALOG_PAGE.FURNITURE_CHAIR, Label = "Chair", Category = "Chair" },
	{ Page = CATALOG_PAGE.FURNITURE_DIVIDER, Label = "Divider", Category = "Divider" },
	{ Page = CATALOG_PAGE.FURNITURE_FLOOR, Label = "Floor", Category = "Floor" },
	{ Page = CATALOG_PAGE.FURNITURE_FOOD, Label = "Food", Category = "Food" },
	{ Page = CATALOG_PAGE.FURNITURE_GATE, Label = "Gate", Category = "Gate" },
	{ Page = CATALOG_PAGE.FURNITURE_LIGHTING, Label = "Lighting", Category = "Lighting" },
	{ Page = CATALOG_PAGE.FURNITURE_MUSIC, Label = "Music", Category = "Music" },
	{ Page = CATALOG_PAGE.FURNITURE_OTHER, Label = "Other", Category = "Other" },
	{ Page = CATALOG_PAGE.FURNITURE_PETS, Label = "Pets", Category = "Pets" },
	{ Page = CATALOG_PAGE.FURNITURE_PRESENT, Label = "Present", Category = "Present" },
	{ Page = CATALOG_PAGE.FURNITURE_ROLLER, Label = "Roller", Category = "Roller" },
	{ Page = CATALOG_PAGE.FURNITURE_RUG, Label = "Rug", Category = "Rug" },
	{ Page = CATALOG_PAGE.FURNITURE_SHELF, Label = "Shelf", Category = "Shelf" },
	{ Page = CATALOG_PAGE.FURNITURE_TABLE, Label = "Table", Category = "Table" },
	{ Page = CATALOG_PAGE.FURNITURE_WALL_DECORATION, Label = "Wall Decoration", Category = "Wall Decoration" },
	{ Page = CATALOG_PAGE.FURNITURE_WALLPAPER, Label = "Wallpaper", Category = "Wallpaper" },
	{ Page = CATALOG_PAGE.FURNITURE_WINDOW, Label = "Window", Category = "Window" },
}

ui.FloorFinishes.Pages = {
	{
		Page = CATALOG_PAGE.ROOM_FINISHES_FLOORS,
		Label = ui.FloorFinishes.Config.SubcategoryName,
		Icon = "-",
	},
}

local SHOP_CATEGORY_NORMALIZATION = {
	Bed = "Bed",
	Beds = "Bed",
	Chair = "Chair",
	Chairs = "Chair",
	Seating = "Chair",
	Table = "Table",
	Tables = "Table",
	Lighting = "Lighting",
	Rug = "Rug",
	Rugs = "Rug",
	Decor = "Other",
	["Room Building"] = "Other",
	Plants = "Other",
	Extras = "Other",
	Furniture = "Other",
}

for _, category in ipairs(CATALOG_SHOP_CATEGORIES) do
	SHOP_CATEGORY_NORMALIZATION[category.Category] = category.Category
end

local CATALOG_MARKETPLACE_PAGES = {
	{ Page = CATALOG_PAGE.MARKETPLACE_OFFERS, Label = "Offers", Icon = "M" },
	{ Page = CATALOG_PAGE.MARKETPLACE_MY_LISTINGS, Label = "My Listings", Icon = "M" },
	{ Page = CATALOG_PAGE.MARKETPLACE_MY_SALES, Label = "My Sales", Icon = "M" },
	{ Page = CATALOG_PAGE.MARKETPLACE_INSTRUCTIONS, Label = "Instructions", Icon = "?" },
}

local PLACEHOLDER_PAGE_CONTENT = {
	[CATALOG_PAGE.BEST_SELLERS] = {
		Title = "Best Sellers",
		Body = "Popular furniture picks will be featured here soon.",
		Button = "Coming Soon",
	},
	[CATALOG_PAGE.VIP] = {
		Title = "VIP",
		Body = "VIP furniture and membership previews are coming later.",
		Button = "Coming Soon",
	},
	[CATALOG_PAGE.PETS] = {
		Title = "Pets",
		Body = "Pets are planned for a future catalog update.",
		Button = "Coming Soon",
	},
	[CATALOG_PAGE.SPECIAL_OFFERS] = {
		Title = "Special Offers",
		Body = "Limited-time catalog offers will appear here when available.",
		Button = "Coming Soon",
	},
}

local renderCatalog = nil
local renderMarketplace = nil
local selectCatalogPage = nil
local rebuildCatalogNavigation = nil
local requestMarketplaceOffers = nil
local requestMarketplaceMySales = nil

local placingItemData = nil
local placementPreview = nil
local placementPreviewHighlight = nil
local placementIsValid = false
local placementRotationY = 0
local placementBaseRotation = CFrame.new()
local placementSource = nil

local OVERLAP_SHRINK = 0.08
local PLACEMENT_BOUNDS_PART_NAME = "PlacementBounds"
local PREVIEW_PLACEMENT_BOUNDS_PART_NAME = "PreviewPlacementBounds"
local DEBUG_TILE_MASK_PLACEMENT = false
local DEBUG_PLACEMENT_ROOM_READY = false
local DEBUG_PLACEMENT_PREVIEW_VISUAL = false
local KNOWN_FOOTPRINT_OVERRIDES = {
	Gate_Test_OpenClose = {
		Width = 1,
		Depth = 1,
		Source = "TestGateOverride",
	},
}

local CATALOG_ROTATE_ACTION = "CatalogRotatePreview"
local CATALOG_CANCEL_ACTION = "CatalogCancelPlacement"

local function createCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function createStroke(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	stroke.Parent = parent
	return stroke
end

local function getOrCreateClientEvent(name)
	local clientEvents = playerGui:FindFirstChild("ClientEvents")

	if clientEvents then
		if not clientEvents:IsA("Folder") then
			error("PlayerGui.ClientEvents exists but is not a Folder.")
		end
	else
		clientEvents = Instance.new("Folder")
		clientEvents.Name = "ClientEvents"
		clientEvents.Parent = playerGui
	end

	local existing = clientEvents:FindFirstChild(name)

	if existing then
		if not existing:IsA("BindableEvent") then
			error(name .. " exists but is not a BindableEvent.")
		end

		return existing
	end

	local bindableEvent = Instance.new("BindableEvent")
	bindableEvent.Name = name
	bindableEvent.Parent = clientEvents

	return bindableEvent
end

local startInventoryPlacement = getOrCreateClientEvent("StartInventoryPlacement")
local inventoryRefreshRequested = getOrCreateClientEvent("InventoryRefreshRequested")
local inventoryLocalDelta = getOrCreateClientEvent("InventoryLocalDelta")
local currencyRefreshRequested = getOrCreateClientEvent("CurrencyRefreshRequested")
local currencyLocalDelta = getOrCreateClientEvent("CurrencyLocalDelta")
local majorMenuOpened = getOrCreateClientEvent("MajorMenuOpened")
local closeMajorMenus = getOrCreateClientEvent("CloseMajorMenus")
local majorMenuStateChanged = getOrCreateClientEvent("MajorMenuStateChanged")
local openCatalog = getOrCreateClientEvent("OpenCatalog")

local MENU_NAME = "Shop"
local anyMajorMenuOpen = false
local openMajorMenuName = nil

local function setLocalMajorMenuState(isOpen, menuName)
	if isOpen then
		anyMajorMenuOpen = true
		openMajorMenuName = menuName
	elseif openMajorMenuName == menuName then
		anyMajorMenuOpen = false
		openMajorMenuName = nil
	end

	if ui.UpdateOpenButton then
		ui.UpdateOpenButton()
	end
end

local function publishMajorMenuState(isOpen)
	setLocalMajorMenuState(isOpen, MENU_NAME)
	majorMenuStateChanged:Fire(isOpen, MENU_NAME)
end

local function fireInventoryOptimisticPlacementDelta(itemData)
	if typeof(itemData) ~= "table" then
		return
	end

	local templateId = itemData.TemplateName or itemData.Id

	if typeof(templateId) ~= "string" or templateId == "" then
		return
	end

	inventoryLocalDelta:Fire({
		TemplateId = templateId,
		DeltaTotal = -1,
		ConsumeUntradableFirst = true,
		Optimistic = true,
		Reason = "PlaceInventoryItemPending",
	})
end

local function fireInventoryLocalDeltaFromPlacementData(data)
	if typeof(data) ~= "table" then
		return
	end

	local templateId = data.TemplateId

	if typeof(templateId) ~= "string" or templateId == "" then
		return
	end

	local total = data.RemainingCount
	local details = data.InventoryDetails

	if typeof(details) == "table" and typeof(details.Total) == "number" then
		total = details.Total
	end

	if typeof(total) ~= "number" then
		return
	end

	local payload = {
		TemplateId = templateId,
		Total = total,
	}

	if typeof(details) == "table" then
		if typeof(details.Tradable) == "number" then
			payload.Tradable = details.Tradable
		end

		if typeof(details.Untradable) == "number" then
			payload.Untradable = details.Untradable
		end
	end

	inventoryLocalDelta:Fire(payload)
end

local function fireInventoryLocalDeltaFromAddToInventoryResult(response)
	if typeof(response) ~= "table" then
		return
	end

	local data = response.Data
	local templateId = response.TemplateId
	local total = response.NewCount
	local details = response.InventoryDetails

	if typeof(data) == "table" then
		templateId = templateId or data.TemplateId
		total = total or data.NewCount
		details = details or data.InventoryDetails
	end

	if typeof(templateId) ~= "string" or templateId == "" then
		return
	end

	if typeof(details) == "table" and typeof(details.Total) == "number" then
		total = details.Total
	end

	if typeof(total) ~= "number" then
		return
	end

	local payload = {
		TemplateId = templateId,
		Total = total,
	}

	if typeof(details) == "table" then
		if typeof(details.Tradable) == "number" then
			payload.Tradable = details.Tradable
		end

		if typeof(details.Untradable) == "number" then
			payload.Untradable = details.Untradable
		end
	end

	inventoryLocalDelta:Fire(payload)
end

local function fireCurrencyLocalDeltaFromAddToInventoryResult(response)
	if typeof(response) ~= "table" then
		return
	end

	local data = response.Data
	local currencyKey = response.CurrencyKey
	local balance = response.NewCurrencyBalance

	if typeof(data) == "table" then
		currencyKey = currencyKey or data.CurrencyKey
		balance = balance or data.NewCurrencyBalance
	end

	if typeof(currencyKey) ~= "string" or currencyKey == "" then
		return
	end

	if typeof(balance) ~= "number" then
		return
	end

	currencyLocalDelta:Fire({
		CurrencyKey = currencyKey,
		Balance = balance,
	})
end

local function getCurrentRoomModel()
	local roomName = player:GetAttribute("CurrentRoomName")

	if typeof(roomName) ~= "string" or roomName == "" then
		return nil
	end

	return activeRooms:FindFirstChild(roomName)
end

local function getCurrentRoomFolder()
	local roomModel = getCurrentRoomModel()

	if not roomModel then
		return nil
	end

	return roomModel:FindFirstChild("Room")
end

local function getCurrentFurnitureFolder()
	local roomModel = getCurrentRoomModel()

	if not roomModel then
		return nil
	end

	return roomModel:FindFirstChild("Furniture")
end

local function getCurrentFloor()
	local roomFolder = getCurrentRoomFolder()
	local roomModel = getCurrentRoomModel()

	local floor = roomFolder and roomFolder:FindFirstChild("WalkableFloor")

	if floor and floor:IsA("BasePart") then
		return floor
	end

	if roomModel then
		floor = roomModel:FindFirstChild("WalkableFloor", true)

		if floor and floor:IsA("BasePart") then
			return floor
		end
	end

	return nil
end

local function getCurrentPlacementGrid()
	local roomModel = getCurrentRoomModel()
	local floor = getCurrentFloor()

	if not roomModel or not floor then
		return nil, nil, "Click a valid floor tile to place this furniture."
	end

	if not GridConfig.UsesTileGrid(roomModel, floor) then
		return nil, nil, "Furniture can only be placed in grid rooms."
	end

	return roomModel, floor, nil
end

function ui.placementMask.isWalkableMarkerPart(part)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return false
	end

	local tileX = part:GetAttribute(GridConfig.TILE_X_ATTRIBUTE)
	local tileZ = part:GetAttribute(GridConfig.TILE_Z_ATTRIBUTE)

	return part:GetAttribute(GridConfig.WALKABLE_TILE_ATTRIBUTE) == true
		and typeof(tileX) == "number"
		and typeof(tileZ) == "number"
		and tileX == math.floor(tileX)
		and tileZ == math.floor(tileZ)
end

local function isCurrentRoomOwner()
	local roomModel = getCurrentRoomModel()

	if not roomModel then
		return false
	end

	return roomModel:GetAttribute("OwnerUserId") == player.UserId
end

local function shouldShowCatalogButton()
	return player:GetAttribute("OnboardingStep") == "Complete"
		and (player:GetAttribute("ControlMode") or "Hotel") == "Hotel"
end

local function canContinueInventoryPlacement()
	local currentRoomName = player:GetAttribute("CurrentRoomName")

	return (player:GetAttribute("ControlMode") or "Hotel") == "Hotel"
		and typeof(currentRoomName) == "string"
		and currentRoomName ~= ""
		and player:GetAttribute("RoomMode") == "Edit"
end

ui.OpenButton = Instance.new("TextButton")
ui.OpenButton.Name = "OpenFurnitureCatalogButton"
ui.OpenButton.AnchorPoint = Vector2.new(1, 1)
ui.OpenButton.Position = UDim2.new(1, -20, 1, -74)
ui.OpenButton.Size = UDim2.fromOffset(150, 44)
ui.OpenButton.BackgroundColor3 = Color3.fromRGB(92, 72, 48)
ui.OpenButton.BorderSizePixel = 0
ui.OpenButton.Text = "Catalog"
ui.OpenButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ui.OpenButton.TextSize = 17
ui.OpenButton.Font = Enum.Font.GothamBold
ui.OpenButton.Visible = false
ui.OpenButton.Parent = gui

createCorner(ui.OpenButton, 10)
createStroke(ui.OpenButton, Color3.fromRGB(255, 255, 255), 1, 0.25)

ui.Panel = Instance.new("Frame")
ui.Panel.Name = "FurnitureCatalogPanel"
ui.Panel.AnchorPoint = Vector2.new(0.5, 0.5)
ui.Panel.Position = UDim2.fromScale(0.5, 0.5)
ui.Panel.Size = UDim2.fromOffset(760, 560)
ui.Panel.BackgroundColor3 = Color3.fromRGB(238, 229, 198)
ui.Panel.BorderSizePixel = 0
ui.Panel.Visible = false
ui.Panel.Parent = gui

createCorner(ui.Panel, 10)
createStroke(ui.Panel, Color3.fromRGB(84, 68, 48), 2, 0.08)

ui.PanelSize = Instance.new("UISizeConstraint")
ui.PanelSize.MinSize = Vector2.new(680, 500)
ui.PanelSize.MaxSize = Vector2.new(820, 620)
ui.PanelSize.Parent = ui.Panel

ui.SpiralFrame = Instance.new("Frame")
ui.SpiralFrame.Name = "SpiralBinding"
ui.SpiralFrame.Position = UDim2.fromOffset(18, 8)
ui.SpiralFrame.Size = UDim2.new(1, -36, 0, 22)
ui.SpiralFrame.BackgroundTransparency = 1
ui.SpiralFrame.Parent = ui.Panel

for index = 1, 17 do
	local ring = Instance.new("Frame")
	ring.Name = "Spiral_" .. tostring(index)
	ring.Position = UDim2.new((index - 1) / 16, -5, 0, 2)
	ring.Size = UDim2.fromOffset(10, 18)
	ring.BackgroundColor3 = Color3.fromRGB(77, 70, 62)
	ring.BorderSizePixel = 0
	ring.Parent = ui.SpiralFrame

	createCorner(ring, 5)
end

ui.TitleLabel = Instance.new("TextLabel")
ui.TitleLabel.Name = "TitleLabel"
ui.TitleLabel.Position = UDim2.fromOffset(22, 34)
ui.TitleLabel.Size = UDim2.new(1, -230, 0, 34)
ui.TitleLabel.BackgroundTransparency = 1
ui.TitleLabel.Text = "Catalog"
ui.TitleLabel.TextColor3 = Color3.fromRGB(62, 48, 34)
ui.TitleLabel.TextSize = 28
ui.TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.TitleLabel.Font = Enum.Font.GothamBold
ui.TitleLabel.Parent = ui.Panel

ui.CloseButton = Instance.new("TextButton")
ui.CloseButton.Name = "CloseButton"
ui.CloseButton.AnchorPoint = Vector2.new(1, 0)
ui.CloseButton.Position = UDim2.new(1, -18, 0, 34)
ui.CloseButton.Size = UDim2.fromOffset(34, 34)
ui.CloseButton.BackgroundColor3 = Color3.fromRGB(132, 70, 58)
ui.CloseButton.BorderSizePixel = 0
ui.CloseButton.Text = "X"
ui.CloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ui.CloseButton.TextSize = 16
ui.CloseButton.Font = Enum.Font.GothamBold
ui.CloseButton.Parent = ui.Panel

createCorner(ui.CloseButton, 7)

ui.StatusLabel = Instance.new("TextLabel")
ui.StatusLabel.Name = "StatusLabel"
ui.StatusLabel.Position = UDim2.fromOffset(22, 68)
ui.StatusLabel.Size = UDim2.new(1, -230, 0, 34)
ui.StatusLabel.BackgroundTransparency = 1
ui.StatusLabel.Text = "Browse the latest hotel furniture and marketplace offers."
ui.StatusLabel.TextColor3 = Color3.fromRGB(95, 80, 62)
ui.StatusLabel.TextWrapped = true
ui.StatusLabel.TextSize = 14
ui.StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.StatusLabel.Font = Enum.Font.Gotham
ui.StatusLabel.Parent = ui.Panel

ui.MarketplaceSalesHeaderNote = Instance.new("Frame")
ui.MarketplaceSalesHeaderNote.Name = "MarketplaceSalesHeaderNote"
ui.MarketplaceSalesHeaderNote.Position = UDim2.fromOffset(22, 68)
ui.MarketplaceSalesHeaderNote.Size = UDim2.new(1, -230, 0, 38)
ui.MarketplaceSalesHeaderNote.BackgroundColor3 = Color3.fromRGB(246, 239, 209)
ui.MarketplaceSalesHeaderNote.BorderSizePixel = 0
ui.MarketplaceSalesHeaderNote.Visible = false
ui.MarketplaceSalesHeaderNote.Parent = ui.Panel

createCorner(ui.MarketplaceSalesHeaderNote, 8)
createStroke(ui.MarketplaceSalesHeaderNote, Color3.fromRGB(154, 129, 88), 1, 0.38)

ui.MarketplaceSalesHeaderTitle = Instance.new("TextLabel")
ui.MarketplaceSalesHeaderTitle.Name = "MarketplaceSalesHeaderTitle"
ui.MarketplaceSalesHeaderTitle.Position = UDim2.fromOffset(10, 3)
ui.MarketplaceSalesHeaderTitle.Size = UDim2.new(1, -20, 0, 16)
ui.MarketplaceSalesHeaderTitle.BackgroundTransparency = 1
ui.MarketplaceSalesHeaderTitle.Text = "Manage your marketplace sales."
ui.MarketplaceSalesHeaderTitle.TextColor3 = Color3.fromRGB(65, 55, 42)
ui.MarketplaceSalesHeaderTitle.TextSize = 12
ui.MarketplaceSalesHeaderTitle.TextXAlignment = Enum.TextXAlignment.Left
ui.MarketplaceSalesHeaderTitle.Font = Enum.Font.GothamBold
ui.MarketplaceSalesHeaderTitle.Parent = ui.MarketplaceSalesHeaderNote

ui.MarketplaceSalesHeaderBody = Instance.new("TextLabel")
ui.MarketplaceSalesHeaderBody.Name = "MarketplaceSalesHeaderBody"
ui.MarketplaceSalesHeaderBody.Position = UDim2.fromOffset(10, 20)
ui.MarketplaceSalesHeaderBody.Size = UDim2.new(1, -20, 0, 14)
ui.MarketplaceSalesHeaderBody.BackgroundTransparency = 1
ui.MarketplaceSalesHeaderBody.Text = "Sale history will be cleared within 30 days."
ui.MarketplaceSalesHeaderBody.TextColor3 = Color3.fromRGB(92, 82, 65)
ui.MarketplaceSalesHeaderBody.TextSize = 11
ui.MarketplaceSalesHeaderBody.TextXAlignment = Enum.TextXAlignment.Left
ui.MarketplaceSalesHeaderBody.TextTruncate = Enum.TextTruncate.AtEnd
ui.MarketplaceSalesHeaderBody.Font = Enum.Font.Gotham
ui.MarketplaceSalesHeaderBody.Parent = ui.MarketplaceSalesHeaderNote

ui.SectionFrame = Instance.new("Frame")
ui.SectionFrame.Name = "ShopSectionTabs"
ui.SectionFrame.Position = UDim2.fromOffset(18, 104)
ui.SectionFrame.Size = UDim2.new(1, -36, 0, 30)
ui.SectionFrame.BackgroundTransparency = 1
ui.SectionFrame.Visible = false
ui.SectionFrame.Parent = ui.Panel

ui.SectionLayout = Instance.new("UIListLayout")
ui.SectionLayout.FillDirection = Enum.FillDirection.Horizontal
ui.SectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
ui.SectionLayout.Padding = UDim.new(0, 6)
ui.SectionLayout.Parent = ui.SectionFrame

ui.ShopSectionButton = Instance.new("TextButton")
ui.ShopSectionButton.Name = "ShopSectionButton"
ui.ShopSectionButton.LayoutOrder = 1
ui.ShopSectionButton.Size = UDim2.fromOffset(86, 28)
ui.ShopSectionButton.BorderSizePixel = 0
ui.ShopSectionButton.Text = "Shop"
ui.ShopSectionButton.TextSize = 13
ui.ShopSectionButton.Font = Enum.Font.GothamBold
ui.ShopSectionButton.Parent = ui.SectionFrame

createCorner(ui.ShopSectionButton, 7)

ui.MarketplaceSectionButton = Instance.new("TextButton")
ui.MarketplaceSectionButton.Name = "MarketplaceSectionButton"
ui.MarketplaceSectionButton.LayoutOrder = 2
ui.MarketplaceSectionButton.Size = UDim2.fromOffset(116, 28)
ui.MarketplaceSectionButton.BorderSizePixel = 0
ui.MarketplaceSectionButton.Text = "Marketplace"
ui.MarketplaceSectionButton.TextSize = 13
ui.MarketplaceSectionButton.Font = Enum.Font.GothamBold
ui.MarketplaceSectionButton.Parent = ui.SectionFrame

createCorner(ui.MarketplaceSectionButton, 7)

ui.CategoryFrame = Instance.new("Frame")
ui.CategoryFrame.Name = "CategoryTabs"
ui.CategoryFrame.Position = UDim2.fromOffset(22, 112)
ui.CategoryFrame.Size = UDim2.new(1, -226, 0, 32)
ui.CategoryFrame.BackgroundTransparency = 1
ui.CategoryFrame.Parent = ui.Panel

ui.CategoryLayout = Instance.new("UIListLayout")
ui.CategoryLayout.FillDirection = Enum.FillDirection.Horizontal
ui.CategoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
ui.CategoryLayout.Padding = UDim.new(0, 6)
ui.CategoryLayout.Parent = ui.CategoryFrame

ui.MarketplaceTabsFrame = Instance.new("Frame")
ui.MarketplaceTabsFrame.Name = "MarketplaceTabs"
ui.MarketplaceTabsFrame.Position = UDim2.fromOffset(18, 140)
ui.MarketplaceTabsFrame.Size = UDim2.new(1, -36, 0, 32)
ui.MarketplaceTabsFrame.BackgroundTransparency = 1
ui.MarketplaceTabsFrame.Visible = false
ui.MarketplaceTabsFrame.Parent = ui.Panel

ui.MarketplaceTabsLayout = Instance.new("UIListLayout")
ui.MarketplaceTabsLayout.FillDirection = Enum.FillDirection.Horizontal
ui.MarketplaceTabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
ui.MarketplaceTabsLayout.Padding = UDim.new(0, 6)
ui.MarketplaceTabsLayout.Parent = ui.MarketplaceTabsFrame

ui.MarketplaceOffersButton = Instance.new("TextButton")
ui.MarketplaceOffersButton.Name = "MarketplaceOffersButton"
ui.MarketplaceOffersButton.LayoutOrder = 1
ui.MarketplaceOffersButton.Size = UDim2.fromOffset(78, 30)
ui.MarketplaceOffersButton.BorderSizePixel = 0
ui.MarketplaceOffersButton.Text = "Offers"
ui.MarketplaceOffersButton.TextSize = 13
ui.MarketplaceOffersButton.Font = Enum.Font.GothamBold
ui.MarketplaceOffersButton.Parent = ui.MarketplaceTabsFrame

createCorner(ui.MarketplaceOffersButton, 8)

ui.MarketplaceMySalesButton = Instance.new("TextButton")
ui.MarketplaceMySalesButton.Name = "MarketplaceMySalesButton"
ui.MarketplaceMySalesButton.LayoutOrder = 2
ui.MarketplaceMySalesButton.Size = UDim2.fromOffset(86, 30)
ui.MarketplaceMySalesButton.BorderSizePixel = 0
ui.MarketplaceMySalesButton.Text = "My Sales"
ui.MarketplaceMySalesButton.TextSize = 13
ui.MarketplaceMySalesButton.Font = Enum.Font.GothamBold
ui.MarketplaceMySalesButton.Parent = ui.MarketplaceTabsFrame

createCorner(ui.MarketplaceMySalesButton, 8)

ui.MarketplaceRefreshButton = Instance.new("TextButton")
ui.MarketplaceRefreshButton.Name = "MarketplaceRefreshButton"
ui.MarketplaceRefreshButton.LayoutOrder = 3
ui.MarketplaceRefreshButton.Size = UDim2.fromOffset(72, 30)
ui.MarketplaceRefreshButton.BackgroundColor3 = Color3.fromRGB(70, 135, 90)
ui.MarketplaceRefreshButton.BorderSizePixel = 0
ui.MarketplaceRefreshButton.Text = "Refresh"
ui.MarketplaceRefreshButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ui.MarketplaceRefreshButton.TextSize = 12
ui.MarketplaceRefreshButton.Font = Enum.Font.GothamBold
ui.MarketplaceRefreshButton.Parent = ui.MarketplaceTabsFrame

createCorner(ui.MarketplaceRefreshButton, 8)

ui.MarketplaceSearchBox = Instance.new("TextBox")
ui.MarketplaceSearchBox.Name = "MarketplaceSearchBox"
ui.MarketplaceSearchBox.Position = UDim2.fromOffset(22, 112)
ui.MarketplaceSearchBox.Size = UDim2.new(1, -226, 0, 30)
ui.MarketplaceSearchBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
ui.MarketplaceSearchBox.BorderSizePixel = 0
ui.MarketplaceSearchBox.ClearTextOnFocus = false
ui.MarketplaceSearchBox.PlaceholderText = "Search marketplace"
ui.MarketplaceSearchBox.Text = ""
ui.MarketplaceSearchBox.TextColor3 = Color3.fromRGB(40, 40, 40)
ui.MarketplaceSearchBox.PlaceholderColor3 = Color3.fromRGB(135, 135, 135)
ui.MarketplaceSearchBox.TextSize = 13
ui.MarketplaceSearchBox.TextXAlignment = Enum.TextXAlignment.Left
ui.MarketplaceSearchBox.Font = Enum.Font.Gotham
ui.MarketplaceSearchBox.Visible = false
ui.MarketplaceSearchBox.Parent = ui.Panel

createCorner(ui.MarketplaceSearchBox, 8)
createStroke(ui.MarketplaceSearchBox, Color3.fromRGB(220, 220, 220), 1, 0)

ui.CatalogNavFrame = Instance.new("ScrollingFrame")
ui.CatalogNavFrame.Name = "CatalogCategoryNavigation"
ui.CatalogNavFrame.AnchorPoint = Vector2.new(1, 0)
ui.CatalogNavFrame.Position = UDim2.new(1, -18, 0, 78)
ui.CatalogNavFrame.Size = UDim2.fromOffset(164, 454)
ui.CatalogNavFrame.BackgroundColor3 = Color3.fromRGB(218, 205, 170)
ui.CatalogNavFrame.BorderSizePixel = 0
ui.CatalogNavFrame.CanvasSize = UDim2.fromOffset(0, 0)
ui.CatalogNavFrame.ScrollBarThickness = 4
ui.CatalogNavFrame.Parent = ui.Panel

createCorner(ui.CatalogNavFrame, 9)
createStroke(ui.CatalogNavFrame, Color3.fromRGB(101, 80, 55), 1, 0.18)

ui.NavPadding = Instance.new("UIPadding")
ui.NavPadding.PaddingTop = UDim.new(0, 8)
ui.NavPadding.PaddingBottom = UDim.new(0, 8)
ui.NavPadding.PaddingLeft = UDim.new(0, 8)
ui.NavPadding.PaddingRight = UDim.new(0, 8)
ui.NavPadding.Parent = ui.CatalogNavFrame

ui.NavLayout = Instance.new("UIListLayout")
ui.NavLayout.SortOrder = Enum.SortOrder.LayoutOrder
ui.NavLayout.Padding = UDim.new(0, 4)
ui.NavLayout.Parent = ui.CatalogNavFrame

local function addCatalogNavButton(key, label, icon, layoutOrder, options)
	options = options or {}

	local button = Instance.new("TextButton")
	button.Name = tostring(key) .. "CatalogNavButton"
	button.LayoutOrder = layoutOrder
	button.Size = UDim2.new(1, 0, 0, options.Height or 24)
	button.BackgroundColor3 = Color3.fromRGB(239, 229, 194)
	button.BorderSizePixel = 0
	button.TextColor3 = Color3.fromRGB(63, 54, 44)
	button.TextSize = options.TextSize or 12
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.TextTruncate = Enum.TextTruncate.AtEnd
	button.Font = options.Font or Enum.Font.GothamBold
	button.Parent = ui.CatalogNavFrame

	local prefix = options.Indent == true and "   " or ""
	local caret = options.Caret or ""

	button.Text = prefix .. tostring(icon or "") .. "  " .. tostring(label or key) .. caret

	createCorner(button, 7)
	createStroke(button, Color3.fromRGB(154, 129, 88), 1, 0.45)

	if options.Page then
		button.MouseButton1Click:Connect(function()
			if selectCatalogPage then
				selectCatalogPage(options.Page)
			end
		end)
	elseif options.Group then
		button.MouseButton1Click:Connect(function()
			catalogNavExpanded[options.Group] = not catalogNavExpanded[options.Group]
			rebuildCatalogNavigation()

			if options.Group == "Furniture" and selectCatalogPage then
				selectCatalogPage(CATALOG_PAGE.FURNITURE_SHOP)
			elseif options.Group == "RoomFinishes" and selectCatalogPage then
				selectCatalogPage(CATALOG_PAGE.ROOM_FINISHES_FLOORS)
			end
		end)
	end

	catalogNavButtons[key] = button
	return button
end

rebuildCatalogNavigation = function()
	for _, child in ipairs(ui.CatalogNavFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	table.clear(catalogNavButtons)

	local order = 0

	for _, navItem in ipairs(CATALOG_NAV_ITEMS) do
		order += 1

		if navItem.Group == "Furniture" then
			addCatalogNavButton(
				"FurnitureGroup",
				navItem.Label,
				navItem.Icon,
				order,
				{
					Group = "Furniture",
					Caret = catalogNavExpanded.Furniture and "  v" or "  >",
				}
			)

			if catalogNavExpanded.Furniture then
				for _, category in ipairs(CATALOG_SHOP_CATEGORIES) do
					order += 1
					addCatalogNavButton(
						category.Page,
						category.Label,
						"-",
						order,
						{
							Page = category.Page,
							Indent = true,
							Height = 22,
							TextSize = 11,
							Font = Enum.Font.Gotham,
						}
					)
				end
			end
		elseif navItem.Group == "RoomFinishes" then
			addCatalogNavButton(
				"RoomFinishesGroup",
				navItem.Label,
				navItem.Icon,
				order,
				{
					Group = "RoomFinishes",
					Caret = catalogNavExpanded.RoomFinishes and "  v" or "  >",
				}
			)

			if catalogNavExpanded.RoomFinishes then
				for _, page in ipairs(ui.FloorFinishes.Pages) do
					order += 1
					addCatalogNavButton(
						page.Page,
						page.Label,
						page.Icon or "-",
						order,
						{
							Page = page.Page,
							Indent = true,
							Height = 22,
							TextSize = 11,
							Font = Enum.Font.Gotham,
						}
					)
				end
			end
		elseif navItem.Group == "Marketplace" then
			addCatalogNavButton(
				"MarketplaceGroup",
				navItem.Label,
				navItem.Icon,
				order,
				{
					Group = "Marketplace",
					Caret = catalogNavExpanded.Marketplace and "  v" or "  >",
				}
			)

			if catalogNavExpanded.Marketplace then
				for _, page in ipairs(CATALOG_MARKETPLACE_PAGES) do
					order += 1
					addCatalogNavButton(
						page.Page,
						page.Label,
						"-",
						order,
						{
							Page = page.Page,
							Indent = true,
							Height = 22,
							TextSize = 11,
							Font = Enum.Font.Gotham,
						}
					)
				end
			end
		elseif navItem.Page then
			addCatalogNavButton(navItem.Page, navItem.Label, navItem.Icon, order, {
				Page = navItem.Page,
			})
		end
	end

	task.defer(function()
		ui.CatalogNavFrame.CanvasSize = UDim2.fromOffset(0, ui.NavLayout.AbsoluteContentSize.Y + 18)
	end)
end

rebuildCatalogNavigation()

ui.CatalogCurrencyPanel = Instance.new("Frame")
ui.CatalogCurrencyPanel.Name = "CatalogCurrencyPanel"
ui.CatalogCurrencyPanel.AnchorPoint = Vector2.new(0, 1)
ui.CatalogCurrencyPanel.Position = UDim2.new(0, 22, 1, -18)
ui.CatalogCurrencyPanel.Size = UDim2.new(1, -226, 0, 42)
ui.CatalogCurrencyPanel.BackgroundColor3 = Color3.fromRGB(218, 205, 170)
ui.CatalogCurrencyPanel.BorderSizePixel = 0
ui.CatalogCurrencyPanel.Parent = ui.Panel

createCorner(ui.CatalogCurrencyPanel, 9)
createStroke(ui.CatalogCurrencyPanel, Color3.fromRGB(101, 80, 55), 1, 0.18)

ui.CatalogCurrencyLayout = Instance.new("UIListLayout")
ui.CatalogCurrencyLayout.FillDirection = Enum.FillDirection.Horizontal
ui.CatalogCurrencyLayout.SortOrder = Enum.SortOrder.LayoutOrder
ui.CatalogCurrencyLayout.VerticalAlignment = Enum.VerticalAlignment.Center
ui.CatalogCurrencyLayout.Padding = UDim.new(0, 8)
ui.CatalogCurrencyLayout.Parent = ui.CatalogCurrencyPanel

ui.CatalogCurrencyPadding = Instance.new("UIPadding")
ui.CatalogCurrencyPadding.PaddingLeft = UDim.new(0, 10)
ui.CatalogCurrencyPadding.PaddingRight = UDim.new(0, 10)
ui.CatalogCurrencyPadding.Parent = ui.CatalogCurrencyPanel

ui.CatalogCoinsBox = Instance.new("Frame")
ui.CatalogCoinsBox.Name = "CatalogCoinsBox"
ui.CatalogCoinsBox.LayoutOrder = 1
ui.CatalogCoinsBox.Size = UDim2.fromOffset(222, 26)
ui.CatalogCoinsBox.BackgroundColor3 = Color3.fromRGB(246, 239, 209)
ui.CatalogCoinsBox.BorderSizePixel = 0
ui.CatalogCoinsBox.Parent = ui.CatalogCurrencyPanel

createCorner(ui.CatalogCoinsBox, 7)
createStroke(ui.CatalogCoinsBox, Color3.fromRGB(154, 129, 88), 1, 0.38)

ui.CatalogCoinsLabel = Instance.new("TextLabel")
ui.CatalogCoinsLabel.Name = "CatalogCoinsLabel"
ui.CatalogCoinsLabel.Position = UDim2.fromOffset(10, 0)
ui.CatalogCoinsLabel.Size = UDim2.fromOffset(82, 26)
ui.CatalogCoinsLabel.BackgroundTransparency = 1
ui.CatalogCoinsLabel.BorderSizePixel = 0
ui.CatalogCoinsLabel.Text = "Coins: 0"
ui.CatalogCoinsLabel.TextColor3 = Color3.fromRGB(62, 48, 34)
ui.CatalogCoinsLabel.TextSize = 13
ui.CatalogCoinsLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.CatalogCoinsLabel.Font = Enum.Font.GothamBold
ui.CatalogCoinsLabel.Parent = ui.CatalogCoinsBox

ui.CatalogGetCoinsButton = Instance.new("TextButton")
ui.CatalogGetCoinsButton.Name = "CatalogGetCoinsButton"
ui.CatalogGetCoinsButton.AnchorPoint = Vector2.new(1, 0)
ui.CatalogGetCoinsButton.Position = UDim2.new(1, -10, 0, 0)
ui.CatalogGetCoinsButton.Size = UDim2.fromOffset(102, 26)
ui.CatalogGetCoinsButton.BackgroundTransparency = 1
ui.CatalogGetCoinsButton.BorderSizePixel = 0
ui.CatalogGetCoinsButton.Text = "Get Coins >>"
ui.CatalogGetCoinsButton.TextColor3 = Color3.fromRGB(94, 73, 48)
ui.CatalogGetCoinsButton.TextSize = 12
ui.CatalogGetCoinsButton.TextXAlignment = Enum.TextXAlignment.Right
ui.CatalogGetCoinsButton.Font = Enum.Font.GothamBold
ui.CatalogGetCoinsButton.Parent = ui.CatalogCoinsBox

ui.CatalogDollarsBox = Instance.new("Frame")
ui.CatalogDollarsBox.Name = "CatalogDollarsBox"
ui.CatalogDollarsBox.LayoutOrder = 2
ui.CatalogDollarsBox.Size = UDim2.fromOffset(250, 26)
ui.CatalogDollarsBox.BackgroundColor3 = Color3.fromRGB(246, 239, 209)
ui.CatalogDollarsBox.BorderSizePixel = 0
ui.CatalogDollarsBox.Parent = ui.CatalogCurrencyPanel

createCorner(ui.CatalogDollarsBox, 7)
createStroke(ui.CatalogDollarsBox, Color3.fromRGB(154, 129, 88), 1, 0.38)

ui.CatalogDollarsLabel = Instance.new("TextLabel")
ui.CatalogDollarsLabel.Name = "CatalogDollarsLabel"
ui.CatalogDollarsLabel.Position = UDim2.fromOffset(10, 0)
ui.CatalogDollarsLabel.Size = UDim2.fromOffset(106, 26)
ui.CatalogDollarsLabel.BackgroundTransparency = 1
ui.CatalogDollarsLabel.BorderSizePixel = 0
ui.CatalogDollarsLabel.Text = "Dollars: 0"
ui.CatalogDollarsLabel.TextColor3 = Color3.fromRGB(62, 48, 34)
ui.CatalogDollarsLabel.TextSize = 13
ui.CatalogDollarsLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.CatalogDollarsLabel.Font = Enum.Font.GothamBold
ui.CatalogDollarsLabel.Parent = ui.CatalogDollarsBox

ui.CatalogHowToGetButton = Instance.new("TextButton")
ui.CatalogHowToGetButton.Name = "CatalogHowToGetButton"
ui.CatalogHowToGetButton.AnchorPoint = Vector2.new(1, 0)
ui.CatalogHowToGetButton.Position = UDim2.new(1, -10, 0, 0)
ui.CatalogHowToGetButton.Size = UDim2.fromOffset(112, 26)
ui.CatalogHowToGetButton.BackgroundTransparency = 1
ui.CatalogHowToGetButton.BorderSizePixel = 0
ui.CatalogHowToGetButton.Text = "How to get >>"
ui.CatalogHowToGetButton.TextColor3 = Color3.fromRGB(94, 73, 48)
ui.CatalogHowToGetButton.TextSize = 12
ui.CatalogHowToGetButton.TextXAlignment = Enum.TextXAlignment.Right
ui.CatalogHowToGetButton.Font = Enum.Font.GothamBold
ui.CatalogHowToGetButton.Parent = ui.CatalogDollarsBox

ui.PlacementHintLabel = Instance.new("TextLabel")
ui.PlacementHintLabel.Name = "PlacementHintLabel"
ui.PlacementHintLabel.AnchorPoint = Vector2.new(0.5, 1)
ui.PlacementHintLabel.Position = UDim2.new(0.5, 0, 1, -24)
ui.PlacementHintLabel.Size = UDim2.fromOffset(560, 46)
ui.PlacementHintLabel.BackgroundColor3 = Color3.fromRGB(35, 45, 60)
ui.PlacementHintLabel.BackgroundTransparency = 0.08
ui.PlacementHintLabel.BorderSizePixel = 0
ui.PlacementHintLabel.Text = ""
ui.PlacementHintLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
ui.PlacementHintLabel.TextScaled = true
ui.PlacementHintLabel.TextWrapped = true
ui.PlacementHintLabel.Font = Enum.Font.GothamBold
ui.PlacementHintLabel.Visible = false
ui.PlacementHintLabel.Parent = gui

createCorner(ui.PlacementHintLabel, 12)
createStroke(ui.PlacementHintLabel, Color3.fromRGB(255, 255, 255), 1, 0.35)

ui.ItemList = Instance.new("ScrollingFrame")
ui.ItemList.Name = "ItemList"
ui.ItemList.Position = UDim2.fromOffset(22, 112)
ui.ItemList.Size = UDim2.new(1, -226, 1, -184)
ui.ItemList.BackgroundColor3 = Color3.fromRGB(251, 247, 229)
ui.ItemList.BorderSizePixel = 0
ui.ItemList.ScrollBarThickness = 6
ui.ItemList.CanvasSize = UDim2.fromOffset(0, 0)
ui.ItemList.Parent = ui.Panel

createCorner(ui.ItemList, 9)
createStroke(ui.ItemList, Color3.fromRGB(174, 153, 112), 1, 0.22)

ui.ListLayout = Instance.new("UIListLayout")
ui.ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ui.ListLayout.Padding = UDim.new(0, 8)
ui.ListLayout.Parent = ui.ItemList

ui.ListPadding = Instance.new("UIPadding")
ui.ListPadding.PaddingTop = UDim.new(0, 10)
ui.ListPadding.PaddingBottom = UDim.new(0, 28)
ui.ListPadding.PaddingLeft = UDim.new(0, 10)
ui.ListPadding.PaddingRight = UDim.new(0, 10)
ui.ListPadding.Parent = ui.ItemList

ui.MarketplacePurchaseOverlay = Instance.new("Frame")
ui.MarketplacePurchaseOverlay.Name = "MarketplacePurchaseOverlay"
ui.MarketplacePurchaseOverlay.Position = UDim2.fromOffset(0, 0)
ui.MarketplacePurchaseOverlay.Size = UDim2.fromScale(1, 1)
ui.MarketplacePurchaseOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
ui.MarketplacePurchaseOverlay.BackgroundTransparency = 0.45
ui.MarketplacePurchaseOverlay.BorderSizePixel = 0
ui.MarketplacePurchaseOverlay.Visible = false
ui.MarketplacePurchaseOverlay.ZIndex = 80
ui.MarketplacePurchaseOverlay.Parent = ui.Panel

ui.MarketplacePurchaseWindow = Instance.new("Frame")
ui.MarketplacePurchaseWindow.Name = "MarketplacePurchaseConfirm"
ui.MarketplacePurchaseWindow.AnchorPoint = Vector2.new(0.5, 0.5)
ui.MarketplacePurchaseWindow.Position = UDim2.fromScale(0.5, 0.5)
ui.MarketplacePurchaseWindow.Size = UDim2.fromOffset(322, 188)
ui.MarketplacePurchaseWindow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
ui.MarketplacePurchaseWindow.BorderSizePixel = 0
ui.MarketplacePurchaseWindow.ZIndex = 81
ui.MarketplacePurchaseWindow.Parent = ui.MarketplacePurchaseOverlay

createCorner(ui.MarketplacePurchaseWindow, 12)
createStroke(ui.MarketplacePurchaseWindow, Color3.fromRGB(210, 215, 220), 1, 0)

ui.MarketplacePurchaseTitle = Instance.new("TextLabel")
ui.MarketplacePurchaseTitle.Name = "PurchaseTitle"
ui.MarketplacePurchaseTitle.Position = UDim2.fromOffset(16, 14)
ui.MarketplacePurchaseTitle.Size = UDim2.new(1, -32, 0, 26)
ui.MarketplacePurchaseTitle.BackgroundTransparency = 1
ui.MarketplacePurchaseTitle.Text = "Buy Marketplace Item"
ui.MarketplacePurchaseTitle.TextColor3 = Color3.fromRGB(40, 40, 40)
ui.MarketplacePurchaseTitle.TextSize = 18
ui.MarketplacePurchaseTitle.TextXAlignment = Enum.TextXAlignment.Left
ui.MarketplacePurchaseTitle.Font = Enum.Font.GothamBold
ui.MarketplacePurchaseTitle.ZIndex = 82
ui.MarketplacePurchaseTitle.Parent = ui.MarketplacePurchaseWindow

ui.MarketplacePurchaseMessage = Instance.new("TextLabel")
ui.MarketplacePurchaseMessage.Name = "PurchaseMessage"
ui.MarketplacePurchaseMessage.Position = UDim2.fromOffset(16, 48)
ui.MarketplacePurchaseMessage.Size = UDim2.new(1, -32, 0, 54)
ui.MarketplacePurchaseMessage.BackgroundTransparency = 1
ui.MarketplacePurchaseMessage.Text = ""
ui.MarketplacePurchaseMessage.TextColor3 = Color3.fromRGB(70, 70, 70)
ui.MarketplacePurchaseMessage.TextSize = 14
ui.MarketplacePurchaseMessage.TextWrapped = true
ui.MarketplacePurchaseMessage.TextXAlignment = Enum.TextXAlignment.Left
ui.MarketplacePurchaseMessage.Font = Enum.Font.Gotham
ui.MarketplacePurchaseMessage.ZIndex = 82
ui.MarketplacePurchaseMessage.Parent = ui.MarketplacePurchaseWindow

ui.MarketplacePurchaseStatus = Instance.new("TextLabel")
ui.MarketplacePurchaseStatus.Name = "PurchaseStatus"
ui.MarketplacePurchaseStatus.Position = UDim2.fromOffset(16, 106)
ui.MarketplacePurchaseStatus.Size = UDim2.new(1, -32, 0, 24)
ui.MarketplacePurchaseStatus.BackgroundTransparency = 1
ui.MarketplacePurchaseStatus.Text = ""
ui.MarketplacePurchaseStatus.TextColor3 = Color3.fromRGB(85, 85, 85)
ui.MarketplacePurchaseStatus.TextSize = 12
ui.MarketplacePurchaseStatus.TextXAlignment = Enum.TextXAlignment.Left
ui.MarketplacePurchaseStatus.TextTruncate = Enum.TextTruncate.AtEnd
ui.MarketplacePurchaseStatus.Font = Enum.Font.Gotham
ui.MarketplacePurchaseStatus.ZIndex = 82
ui.MarketplacePurchaseStatus.Parent = ui.MarketplacePurchaseWindow

ui.MarketplacePurchaseCancelButton = Instance.new("TextButton")
ui.MarketplacePurchaseCancelButton.Name = "PurchaseCancelButton"
ui.MarketplacePurchaseCancelButton.Position = UDim2.new(1, -160, 1, -44)
ui.MarketplacePurchaseCancelButton.Size = UDim2.fromOffset(64, 30)
ui.MarketplacePurchaseCancelButton.BackgroundColor3 = Color3.fromRGB(235, 238, 242)
ui.MarketplacePurchaseCancelButton.BorderSizePixel = 0
ui.MarketplacePurchaseCancelButton.Text = "Cancel"
ui.MarketplacePurchaseCancelButton.TextColor3 = Color3.fromRGB(45, 45, 45)
ui.MarketplacePurchaseCancelButton.TextSize = 12
ui.MarketplacePurchaseCancelButton.Font = Enum.Font.GothamBold
ui.MarketplacePurchaseCancelButton.ZIndex = 82
ui.MarketplacePurchaseCancelButton.Parent = ui.MarketplacePurchaseWindow

createCorner(ui.MarketplacePurchaseCancelButton, 7)

ui.MarketplacePurchaseConfirmButton = Instance.new("TextButton")
ui.MarketplacePurchaseConfirmButton.Name = "PurchaseConfirmButton"
ui.MarketplacePurchaseConfirmButton.Position = UDim2.new(1, -88, 1, -44)
ui.MarketplacePurchaseConfirmButton.Size = UDim2.fromOffset(72, 30)
ui.MarketplacePurchaseConfirmButton.BackgroundColor3 = Color3.fromRGB(70, 150, 255)
ui.MarketplacePurchaseConfirmButton.BorderSizePixel = 0
ui.MarketplacePurchaseConfirmButton.Text = "Confirm"
ui.MarketplacePurchaseConfirmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ui.MarketplacePurchaseConfirmButton.TextSize = 12
ui.MarketplacePurchaseConfirmButton.Font = Enum.Font.GothamBold
ui.MarketplacePurchaseConfirmButton.ZIndex = 82
ui.MarketplacePurchaseConfirmButton.Parent = ui.MarketplacePurchaseWindow

createCorner(ui.MarketplacePurchaseConfirmButton, 7)

local function setPanelVisible(isVisible)
	local wasVisible = ui.Panel.Visible

	if isVisible then
		publishMajorMenuState(true)
		majorMenuOpened:Fire(MENU_NAME)
	end

	ui.Panel.Visible = isVisible

	if ui.UpdateOpenButton then
		ui.UpdateOpenButton()
	else
		ui.OpenButton.Visible = false
	end

	if not isVisible and (wasVisible or openMajorMenuName == MENU_NAME) then
		publishMajorMenuState(false)
	end
end

local function setStatus(text)
	ui.StatusLabel.Text = tostring(text or "")
end

function ui.placementStartup.debug(...)
	if DEBUG_PLACEMENT_ROOM_READY == true then
		warn("[FurnitureCatalog.PlacementRoomReady]", ...)
	end
end

function ui.placementStartup.getContext()
	local roomName = player:GetAttribute("CurrentRoomName")

	if typeof(roomName) ~= "string" or roomName == "" then
		return nil, "CurrentRoomName is missing"
	end

	local playerRoomType = player:GetAttribute("CurrentRoomType")

	if typeof(playerRoomType) == "string"
		and playerRoomType ~= ""
		and playerRoomType ~= "PlayerRoom" then

		return nil, "CurrentRoomType is " .. playerRoomType
	end

	if not activeRooms or not activeRooms.Parent then
		return nil, "workspace.ActiveRooms is missing"
	end

	local roomModel = activeRooms:FindFirstChild(roomName)

	if not roomModel or not roomModel:IsA("Model") then
		return nil, "Active room model is missing"
	end

	local roomType = roomModel:GetAttribute("RoomType")

	if typeof(roomType) == "string"
		and roomType ~= ""
		and roomType ~= "PlayerRoom" then

		return nil, "Active room type is " .. roomType
	end

	local floor = getCurrentFloor()

	if not floor or not floor:IsA("BasePart") then
		return nil, "WalkableFloor is missing"
	end

	local success, gridContext = pcall(GridConfig.GetGridContext, roomModel)

	if not success or not gridContext then
		return nil, "Grid context is not ready"
	end

	ui.placementStartup.debug(
		"ready",
		"CurrentRoomName",
		roomName,
		"room",
		roomModel.Name,
		"floor",
		floor.Name,
		"UsesTileMask",
		tostring(gridContext.UsesTileMask)
	)

	return {
		RoomName = roomName,
		RoomModel = roomModel,
		Floor = floor,
		GridContext = gridContext,
	}, nil
end

function ui.placementStartup.waitForPlacementRoomContext(timeoutSeconds, startId)
	local timeoutAt = os.clock() + (timeoutSeconds or 2.5)
	local lastReason = nil

	while os.clock() <= timeoutAt do
		if ui.placementStartup.StartId ~= startId then
			ui.placementStartup.debug("stale token ignored", startId, ui.placementStartup.StartId)
			return nil, "stale"
		end

		local context, reason = ui.placementStartup.getContext()

		if context then
			ui.placementStartup.RoomName = context.RoomName
			ui.placementStartup.RoomModel = context.RoomModel
			ui.placementStartup.Floor = context.Floor
			ui.placementStartup.GridContext = context.GridContext
			return context, nil
		end

		lastReason = reason
		ui.placementStartup.debug(
			"waiting",
			"CurrentRoomName",
			tostring(player:GetAttribute("CurrentRoomName")),
			tostring(reason)
		)
		task.wait(0.05)
	end

	ui.placementStartup.debug("timeout", tostring(lastReason))
	return nil, lastReason or "timeout"
end

function ui.placementStartup.cancelPending(reason)
	ui.placementStartup.StartId += 1
	ui.placementStartup.RoomName = nil
	ui.placementStartup.RoomModel = nil
	ui.placementStartup.Floor = nil
	ui.placementStartup.GridContext = nil
	ui.placementStartup.debug("cancel", tostring(reason), ui.placementStartup.StartId)
end

local function normalizeCatalogCurrencyBalance(value)
	if typeof(value) ~= "number"
		or value ~= value
		or value < 0
		or value == math.huge then

		return 0
	end

	return math.floor(value)
end

local function updateCatalogCurrencyDisplay()
	ui.CatalogCoinsLabel.Text = "Coins: " .. tostring(normalizeCatalogCurrencyBalance(catalogCurrency.Coins))
	ui.CatalogDollarsLabel.Text = "Dollars: " .. tostring(normalizeCatalogCurrencyBalance(catalogCurrency.Dollars))
end

local function applyCatalogCurrencySnapshot(currencies)
	if typeof(currencies) ~= "table" then
		return
	end

	catalogCurrency.Coins = normalizeCatalogCurrencyBalance(currencies.Coins)
	catalogCurrency.Dollars = normalizeCatalogCurrencyBalance(currencies.Dollars)
	catalogCurrency.Loaded = true
	updateCatalogCurrencyDisplay()
end

local function applyCatalogCurrencyLocalDelta(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local currencyKey = payload.CurrencyKey

	if currencyKey ~= "Coins" and currencyKey ~= "Dollars" then
		return
	end

	local currentBalance = normalizeCatalogCurrencyBalance(catalogCurrency[currencyKey])
	local newBalance = nil

	if typeof(payload.Balance) == "number" then
		newBalance = normalizeCatalogCurrencyBalance(payload.Balance)
	elseif typeof(payload.Delta) == "number" then
		newBalance = math.max(currentBalance + math.floor(payload.Delta), 0)
	end

	if not newBalance then
		return
	end

	catalogCurrency[currencyKey] = newBalance
	catalogCurrency.Loaded = true
	updateCatalogCurrencyDisplay()
end

local function requestCatalogCurrencySnapshot(force)
	if catalogCurrency.RequestInFlight then
		return
	end

	local now = os.clock()

	if force ~= true and now - catalogCurrency.LastRequestAt < 1 then
		return
	end

	catalogCurrency.RequestInFlight = true
	catalogCurrency.LastRequestAt = now
	catalogCurrency.Serial += 1

	local requestSerial = catalogCurrency.Serial
	currencyRequest:FireServer("GetCurrencies")

	task.delay(REQUEST_TIMEOUT_SECONDS, function()
		if catalogCurrency.RequestInFlight and catalogCurrency.Serial == requestSerial then
			catalogCurrency.RequestInFlight = false
		end
	end)
end

local function styleToggleButton(button, isSelected)
	if isSelected then
		button.BackgroundColor3 = Color3.fromRGB(70, 150, 255)
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
	else
		button.BackgroundColor3 = Color3.fromRGB(235, 238, 242)
		button.TextColor3 = Color3.fromRGB(55, 55, 55)
	end
end

local function styleCatalogNavButton(button, isSelected)
	if isSelected then
		button.BackgroundColor3 = Color3.fromRGB(94, 73, 48)
		button.TextColor3 = Color3.fromRGB(255, 247, 219)
	else
		button.BackgroundColor3 = Color3.fromRGB(239, 229, 194)
		button.TextColor3 = Color3.fromRGB(63, 54, 44)
	end
end

local function updateCatalogNavigation()
	for key, button in pairs(catalogNavButtons) do
		local isSelected = key == selectedCatalogPage

		if key == "FurnitureGroup" and catalogViewMode == CATALOG_VIEW.SHOP then
			isSelected = true
		elseif key == "RoomFinishesGroup" and catalogViewMode == CATALOG_VIEW.ROOM_FINISHES then
			isSelected = true
		elseif key == "MarketplaceGroup" and catalogViewMode == CATALOG_VIEW.MARKETPLACE then
			isSelected = true
		end

		styleCatalogNavButton(button, isSelected)
	end
end

local function updateCatalogChrome()
	local showingMarketplace = catalogViewMode == CATALOG_VIEW.MARKETPLACE
	local showingShop = catalogViewMode == CATALOG_VIEW.SHOP
	local showingRoomFinishes = catalogViewMode == CATALOG_VIEW.ROOM_FINISHES
	local showingFrontPage = catalogViewMode == CATALOG_VIEW.FRONT_PAGE
	local showingPlaceholder = catalogViewMode == CATALOG_VIEW.PLACEHOLDER
	local showingOffers = marketplaceViewMode == MARKETPLACE_VIEW.OFFERS
	local showingMyListings = marketplaceViewMode == MARKETPLACE_VIEW.MY_LISTINGS
	local showingMySales = marketplaceViewMode == MARKETPLACE_VIEW.MY_SALES
	local showingInstructions = marketplaceViewMode == MARKETPLACE_VIEW.INSTRUCTIONS
	local marketplaceBusy = showingOffers
		and marketplacePublicListingsInFlight
		or ((showingMyListings or showingMySales) and marketplaceMySalesInFlight)

	ui.TitleLabel.Text = "Catalog"
	ui.StatusLabel.Visible = not (showingMarketplace and showingMySales)
	ui.MarketplaceSalesHeaderNote.Visible = showingMarketplace and showingMySales
	ui.SectionFrame.Visible = false
	ui.CategoryFrame.Visible = false
	ui.MarketplaceTabsFrame.Visible = false
	ui.MarketplaceSearchBox.Visible = showingMarketplace and showingOffers
	updateCatalogNavigation()

	if showingShop or showingRoomFinishes or (showingMarketplace and showingOffers) then
		ui.ItemList.Position = UDim2.fromOffset(22, 154)
		ui.ItemList.Size = UDim2.new(1, -226, 1, -226)
	else
		ui.ItemList.Position = UDim2.fromOffset(22, 112)
		ui.ItemList.Size = UDim2.new(1, -226, 1, -184)
	end

	styleToggleButton(ui.ShopSectionButton, not showingMarketplace)
	styleToggleButton(ui.MarketplaceSectionButton, showingMarketplace)
	styleToggleButton(ui.MarketplaceOffersButton, showingMarketplace and showingOffers)
	styleToggleButton(ui.MarketplaceMySalesButton, showingMarketplace and showingMySales)

	ui.MarketplaceRefreshButton.Visible = showingMarketplace and not showingInstructions
	ui.MarketplaceRefreshButton.Active = showingMarketplace and not showingInstructions and not marketplaceBusy
	ui.MarketplaceRefreshButton.AutoButtonColor = showingMarketplace and not showingInstructions and not marketplaceBusy
	ui.MarketplaceRefreshButton.Text = marketplaceBusy and "Loading..." or "Refresh"
	ui.MarketplaceRefreshButton.BackgroundColor3 = marketplaceBusy
		and Color3.fromRGB(155, 160, 155)
		or Color3.fromRGB(70, 135, 90)

	if showingFrontPage then
		setStatus("Read the latest catalog highlights.")
	elseif showingPlaceholder then
		local placeholder = PLACEHOLDER_PAGE_CONTENT[placeholderCatalogPage]
		setStatus(placeholder and placeholder.Title or "Coming soon.")
	end
end

local function setPlacementHint(text)
	text = tostring(text or "")

	ui.PlacementHintLabel.Text = text
	ui.PlacementHintLabel.Visible = text ~= ""
end

local function getActivePlacementHint(isBlocked)
	if placementSource == "Inventory" then
		if isBlocked then
			return "That spot is blocked. Move cursor. R rotate. C cancel"
		end

		return "Placing owned item. Click to place. R rotate. C cancel"
	end

	if isBlocked then
		return "That spot is blocked. Move cursor. R rotate. C cancel"
	end

	return "Click to place. R rotate. C cancel"
end

local helperPartNames = {
	CollisionBuffer = true,
	[PREVIEW_PLACEMENT_BOUNDS_PART_NAME] = true,
	SitPoint = true,
	SleepPoint = true,
	PlayPoint = true,
	EnterPoint = true,
	TalkPoint = true,
	ClickHitbox = true,
	RoomAnchor = true,
	DoorSpawn = true,
}

local function isHelperPart(part)
	return helperPartNames[part.Name] == true
end

local function shouldUsePartForPlacementBounds(part)
	if not part:IsA("BasePart") then
		return false
	end

	if isHelperPart(part) then
		return false
	end

	if part.CanCollide then
		return true
	end

	if part.Transparency < 1 then
		return true
	end

	return false
end

local function getPlacementBoundsParts(model)
	local parts = {}

	if not model then
		return parts
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart")
			and descendant.Name == PLACEMENT_BOUNDS_PART_NAME then

			table.insert(parts, descendant)
		end
	end

	return parts
end

local function getPlacementCheckParts(model)
	local placementBoundsParts = getPlacementBoundsParts(model)

	if #placementBoundsParts > 0 then
		return placementBoundsParts
	end

	local fallbackParts = {}

	for _, descendant in ipairs(model:GetDescendants()) do
		if shouldUsePartForPlacementBounds(descendant) then
			table.insert(fallbackParts, descendant)
		end
	end

	return fallbackParts
end

local function modelHasPlacementBounds(model)
	return #getPlacementBoundsParts(model) > 0
end

local function getFurnitureModelFromDescendant(instance, furnitureFolder)
	local current = instance

	while current and current ~= furnitureFolder do
		if current:IsA("Model") and current.Parent == furnitureFolder then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function shouldIgnoreTouchedFurniturePart(touchingPart, furnitureFolder)
	local touchedFurnitureModel = getFurnitureModelFromDescendant(
		touchingPart,
		furnitureFolder
	)

	if not touchedFurnitureModel then
		return false
	end

	-- If the touched furniture has PlacementBounds, ignore its visual parts.
	-- The PlacementBounds part itself will handle the collision rule.
	if modelHasPlacementBounds(touchedFurnitureModel)
		and touchingPart.Name ~= PLACEMENT_BOUNDS_PART_NAME then

		return true
	end

	return false
end

local function getOverlapCheckSize(size)
	return Vector3.new(
		math.max(size.X - OVERLAP_SHRINK, 0.05),
		math.max(size.Y - OVERLAP_SHRINK, 0.05),
		math.max(size.Z - OVERLAP_SHRINK, 0.05)
	)
end

local function getPartWorldCornersFromCFrame(cframe, size)
	local halfSize = size / 2

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
		table.insert(worldCorners, cframe:PointToWorldSpace(localCorner))
	end

	return worldCorners
end

local function getModelXZBoundsAtCFrame(model, targetCFrame)
	local currentPivot = model:GetPivot()

	local minX = math.huge
	local maxX = -math.huge
	local minZ = math.huge
	local maxZ = -math.huge
	local foundPart = false

	for _, descendant in ipairs(getPlacementCheckParts(model)) do
		foundPart = true

		local relativeCFrame = currentPivot:ToObjectSpace(descendant.CFrame)
		local predictedCFrame = targetCFrame * relativeCFrame

		for _, corner in ipairs(getPartWorldCornersFromCFrame(predictedCFrame, descendant.Size)) do
			minX = math.min(minX, corner.X)
			maxX = math.max(maxX, corner.X)
			minZ = math.min(minZ, corner.Z)
			maxZ = math.max(maxZ, corner.Z)
		end
	end

	if not foundPart then
		return nil
	end

	return {
		minX = minX,
		maxX = maxX,
		minZ = minZ,
		maxZ = maxZ,
	}
end

function ui.placementPreviewVisual.debug(...)
	if DEBUG_PLACEMENT_PREVIEW_VISUAL == true then
		warn("[FurnitureCatalog.PlacementPreviewVisual]", ...)
	end
end

function ui.placementPreviewVisual.getPlacementBounds(model)
	local placementBoundsParts = getPlacementBoundsParts(model)

	if #placementBoundsParts > 0 then
		return placementBoundsParts[1], "PlacementBounds"
	end

	return nil, nil
end

function ui.placementPreviewVisual.getCurrentWorldBounds(model)
	local minX = math.huge
	local minY = math.huge
	local minZ = math.huge
	local maxX = -math.huge
	local maxY = -math.huge
	local maxZ = -math.huge
	local foundPart = false

	for _, part in ipairs(getPlacementCheckParts(model)) do
		foundPart = true

		for _, corner in ipairs(getPartWorldCornersFromCFrame(part.CFrame, part.Size)) do
			minX = math.min(minX, corner.X)
			minY = math.min(minY, corner.Y)
			minZ = math.min(minZ, corner.Z)
			maxX = math.max(maxX, corner.X)
			maxY = math.max(maxY, corner.Y)
			maxZ = math.max(maxZ, corner.Z)
		end
	end

	if not foundPart then
		return nil
	end

	return {
		Center = Vector3.new(
			(minX + maxX) / 2,
			(minY + maxY) / 2,
			(minZ + maxZ) / 2
		),
		Size = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ),
		Min = Vector3.new(minX, minY, minZ),
		Max = Vector3.new(maxX, maxY, maxZ),
	}
end

function ui.placementPreviewVisual.getExplicitBoundsSize(model)
	if not ui.placementMask.getPositiveIntegerAttribute(model, "FootprintWidth")
		and not ui.placementMask.getPositiveIntegerAttribute(model, "FootprintDepth") then

		return nil
	end

	local footprintWidth, footprintDepth = GridConfig.GetFurnitureFootprint(model)

	return GridConfig.GetRecommendedPlacementBoundsSize(
		footprintWidth,
		footprintDepth,
		GridConfig.TILE_SIZE
	)
end

function ui.placementPreviewVisual.createBoundsProxy(model)
	local worldBounds = ui.placementPreviewVisual.getCurrentWorldBounds(model)

	if not worldBounds then
		return nil, "No placement or visual bounds available"
	end

	local boundsSize = ui.placementPreviewVisual.getExplicitBoundsSize(model)

	if not boundsSize then
		boundsSize = Vector3.new(
			math.max(worldBounds.Size.X, 0.2),
			math.max(worldBounds.Size.Y, GridConfig.RECOMMENDED_PLACEMENT_BOUNDS_HEIGHT or 4),
			math.max(worldBounds.Size.Z, 0.2)
		)
	end

	local proxy = Instance.new("Part")
	proxy.Name = PREVIEW_PLACEMENT_BOUNDS_PART_NAME
	proxy.Size = boundsSize
	proxy.CFrame = CFrame.new(
		worldBounds.Center.X,
		worldBounds.Min.Y + boundsSize.Y / 2,
		worldBounds.Center.Z
	) * (model:GetPivot() - model:GetPivot().Position)
	proxy.Transparency = 1
	proxy.Anchored = true
	proxy.CanCollide = false
	proxy.CanTouch = false
	proxy.CanQuery = false
	proxy.CastShadow = false
	proxy:SetAttribute("PreviewOnly", true)
	proxy:SetAttribute("IgnoreForPlacementBounds", true)
	proxy.Parent = model

	return proxy, "PreviewPlacementBounds"
end

function ui.placementPreviewVisual.ensureBoundsVisual(previewModel)
	local boundsPart, boundsSource = ui.placementPreviewVisual.getPlacementBounds(previewModel)

	if not boundsPart then
		boundsPart, boundsSource = ui.placementPreviewVisual.createBoundsProxy(previewModel)
	end

	if not boundsPart then
		ui.placementPreviewVisual.debug(
			"failed",
			previewModel and previewModel.Name or "nil",
			tostring(boundsSource)
		)
		return false, boundsSource or "Missing placement bounds"
	end

	for _, descendant in ipairs(previewModel:GetDescendants()) do
		if descendant.Name == "CatalogPlacementBoundsSelectionBox"
			and descendant:IsA("SelectionBox") then

			descendant:Destroy()
		end
	end

	local selectionBox = Instance.new("SelectionBox")
	selectionBox.Name = "CatalogPlacementBoundsSelectionBox"
	selectionBox.Adornee = boundsPart
	selectionBox.Color3 = Color3.fromRGB(0, 190, 255)
	selectionBox.SurfaceColor3 = Color3.fromRGB(0, 190, 255)
	selectionBox.SurfaceTransparency = 0.65
	selectionBox.Transparency = 0
	selectionBox.LineThickness = 0.06
	selectionBox.Parent = previewModel

	ui.placementPreviewVisual.debug(
		"created",
		"preview",
		previewModel.Name,
		"source",
		tostring(boundsSource),
		"adornee",
		boundsPart.Name,
		"visual",
		selectionBox.ClassName
	)

	return true, nil
end

function ui.placementPreviewVisual.countVisuals(model)
	if not model then
		return 0
	end

	local count = 0

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("SelectionBox")
			or descendant:IsA("BoxHandleAdornment")
			or descendant.Name == PREVIEW_PLACEMENT_BOUNDS_PART_NAME then

			count += 1
		end
	end

	return count
end

local function getFloorPlacementBounds()
	local floor = getCurrentFloor()

	if not floor then
		return nil
	end

	local halfX = floor.Size.X / 2
	local halfZ = floor.Size.Z / 2
	local edgeMargin = 0.05

	return {
		minX = floor.Position.X - halfX + edgeMargin,
		maxX = floor.Position.X + halfX - edgeMargin,
		minZ = floor.Position.Z - halfZ + edgeMargin,
		maxZ = floor.Position.Z + halfZ - edgeMargin,
	}
end

local function getMouseFloorPosition()
	local floor = getCurrentFloor()
	local camera = workspace.CurrentCamera

	if not floor or not camera then
		return nil
	end

	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { floor }

	local result = workspace:Raycast(
		unitRay.Origin,
		unitRay.Direction * 1000,
		raycastParams
	)

	if result then
		return result.Position
	end

	return nil
end

function ui.placementMask.getTarget(roomModel, floor, floorPosition)
	if not roomModel or not floor then
		return nil
	end

	local gridContext = GridConfig.GetGridContext(roomModel)

	if not gridContext or gridContext.UsesTileMask ~= true then
		return nil
	end

	local markerPart = nil

	if ui.placementMask.isWalkableMarkerPart(mouse.Target)
		and mouse.Target:IsDescendantOf(roomModel) then

		markerPart = mouse.Target
	end

	local cellX = nil
	local cellZ = nil

	if markerPart then
		cellX = markerPart:GetAttribute(GridConfig.TILE_X_ATTRIBUTE)
		cellZ = markerPart:GetAttribute(GridConfig.TILE_Z_ATTRIBUTE)
	elseif floorPosition then
		cellX, cellZ = GridConfig.WorldToCell(gridContext, floorPosition)
	end

	if not cellX or not cellZ then
		return nil
	end

	local cellWorldPosition = GridConfig.CellToWorld(gridContext, cellX, cellZ)

	if not cellWorldPosition then
		return nil
	end

	return {
		Context = gridContext,
		HitPart = markerPart or floor,
		HitPosition = floorPosition,
		CellX = cellX,
		CellZ = cellZ,
		CellWalkable = GridConfig.CellIsWalkable(gridContext, cellX, cellZ),
		Position = cellWorldPosition,
	}
end

local function getPreviewPlacementCFrame(model)
	local floorPosition = getMouseFloorPosition()
	local roomModel, floor = getCurrentPlacementGrid()

	if not floorPosition or not floor then
		return nil
	end

	local maskTarget = ui.placementMask.getTarget(roomModel, floor, floorPosition)
	local tileSize = GridConfig.GetTileSize(roomModel, floor)
	local snappedWorldPosition = maskTarget and maskTarget.Position
		or GridConfig.SnapWorldToTileCenter(floor, floorPosition, tileSize)
	local floorTopY = GridConfig.GetFloorTopY(floor)

	if not snappedWorldPosition or not floorTopY then
		return nil
	end

	local boundingCFrame, boundingSize = model:GetBoundingBox()
	local bottomY = boundingCFrame.Position.Y - boundingSize.Y / 2
	local pivotYOffsetFromBottom = model:GetPivot().Position.Y - bottomY

	local targetCFrame =
		CFrame.new(
			snappedWorldPosition.X,
			floorTopY + pivotYOffsetFromBottom,
			snappedWorldPosition.Z
		)
		* CFrame.Angles(0, math.rad(placementRotationY), 0)
		* placementBaseRotation

	return targetCFrame, maskTarget
end

function ui.placementMask.getPositiveIntegerAttribute(instance, attributeName)
	if not instance then
		return nil
	end

	local value = instance:GetAttribute(attributeName)

	if typeof(value) == "number"
		and value == value
		and value > 0
		and value < math.huge
		and math.floor(value) == value then

		return value
	end

	return nil
end

function ui.placementMask.getTemplateKey(model)
	if not model then
		return nil
	end

	local catalogTemplateName = model:GetAttribute("CatalogTemplateName")

	if typeof(catalogTemplateName) == "string" and catalogTemplateName ~= "" then
		return catalogTemplateName
	end

	local templateId = model:GetAttribute("TemplateId")

	if typeof(templateId) == "string" and templateId ~= "" then
		return templateId
	end

	return model.Name
end

function ui.placementMask.getFootprintOverride(model)
	local templateKey = ui.placementMask.getTemplateKey(model)

	if typeof(templateKey) ~= "string" then
		return nil
	end

	return KNOWN_FOOTPRINT_OVERRIDES[templateKey]
end

function ui.placementMask.applyFootprintOverride(model)
	local footprintOverride = ui.placementMask.getFootprintOverride(model)

	if not footprintOverride then
		return
	end

	model:SetAttribute("FootprintWidth", footprintOverride.Width)
	model:SetAttribute("FootprintDepth", footprintOverride.Depth)
end

function ui.placementMask.getExplicitFootprint(model)
	local footprintOverride = ui.placementMask.getFootprintOverride(model)

	if footprintOverride then
		return footprintOverride.Width, footprintOverride.Depth, footprintOverride.Source
	end

	if ui.placementMask.getPositiveIntegerAttribute(model, "FootprintWidth")
		or ui.placementMask.getPositiveIntegerAttribute(model, "FootprintDepth") then

		local footprintWidth, footprintDepth = GridConfig.GetFurnitureFootprint(model)
		return footprintWidth, footprintDepth, "Attributes"
	end

	return nil, nil
end

function ui.placementMask.getDerivedFootprint(model, floor, tileSize)
	local minX = math.huge
	local maxX = -math.huge
	local minZ = math.huge
	local maxZ = -math.huge
	local foundPart = false

	for _, descendant in ipairs(getPlacementCheckParts(model)) do
		foundPart = true

		local halfSize = descendant.Size / 2
		local localCorners = {
			Vector3.new(-halfSize.X, 0, -halfSize.Z),
			Vector3.new(-halfSize.X, 0, halfSize.Z),
			Vector3.new(halfSize.X, 0, -halfSize.Z),
			Vector3.new(halfSize.X, 0, halfSize.Z),
		}

		for _, localCorner in ipairs(localCorners) do
			local worldCorner = descendant.CFrame:PointToWorldSpace(localCorner)
			local floorLocalCorner = floor.CFrame:PointToObjectSpace(worldCorner)

			minX = math.min(minX, floorLocalCorner.X)
			maxX = math.max(maxX, floorLocalCorner.X)
			minZ = math.min(minZ, floorLocalCorner.Z)
			maxZ = math.max(maxZ, floorLocalCorner.Z)
		end
	end

	if not foundPart then
		return 1, 1
	end

	local resolvedTileSize = tileSize or GridConfig.TILE_SIZE
	local widthStuds = math.max(maxX - minX, resolvedTileSize)
	local depthStuds = math.max(maxZ - minZ, resolvedTileSize)
	local widthTiles = math.max(1, math.ceil((widthStuds - GridConfig.GRID_VALIDATION_TOLERANCE) / resolvedTileSize))
	local depthTiles = math.max(1, math.ceil((depthStuds - GridConfig.GRID_VALIDATION_TOLERANCE) / resolvedTileSize))

	return widthTiles, depthTiles
end

function ui.placementMask.getRotatedFootprint(model, gridContext)
	local footprintWidth, footprintDepth, source = ui.placementMask.getExplicitFootprint(model)

	if not footprintWidth or not footprintDepth then
		source = "PlacementBounds"

		if not gridContext or not gridContext.Floor then
			return 1, 1, 1, 1, source
		end

		footprintWidth, footprintDepth = ui.placementMask.getDerivedFootprint(
			model,
			gridContext.Floor,
			gridContext.TileSize or GridConfig.TILE_SIZE
		)

		return footprintWidth, footprintDepth, footprintWidth, footprintDepth, source
	end

	local originalFootprintWidth = footprintWidth
	local originalFootprintDepth = footprintDepth

	if footprintWidth ~= footprintDepth and gridContext and gridContext.Floor then
		local localLookVector = gridContext.Floor.CFrame:VectorToObjectSpace(model:GetPivot().LookVector)

		if math.abs(localLookVector.X) > math.abs(localLookVector.Z) then
			footprintWidth, footprintDepth = footprintDepth, footprintWidth
		end
	end

	return footprintWidth, footprintDepth, originalFootprintWidth, originalFootprintDepth, source
end

function ui.placementMask.isFootprintWalkable(model, maskTarget)
	if not maskTarget or not maskTarget.Context then
		return true, nil
	end

	if maskTarget.CellWalkable ~= true then
		return false, {
			FootprintWidth = 0,
			FootprintDepth = 0,
			OriginalFootprintWidth = 0,
			OriginalFootprintDepth = 0,
			FootprintSource = "TargetCell",
			OccupiedCells = {},
			FirstFailedCell = {
				X = maskTarget.CellX,
				Z = maskTarget.CellZ,
			},
		}
	end

	local footprintWidth, footprintDepth, originalFootprintWidth, originalFootprintDepth, source =
		ui.placementMask.getRotatedFootprint(model, maskTarget.Context)
	local footprintWalkable, occupiedCells = GridConfig.FootprintCellsAreWalkable(
		maskTarget.Context,
		maskTarget.CellX,
		maskTarget.CellZ,
		footprintWidth,
		footprintDepth,
		0
	)
	local firstFailedCell = nil

	if footprintWalkable ~= true then
		for _, cell in ipairs(occupiedCells) do
			if not GridConfig.CellIsWalkable(maskTarget.Context, cell.X, cell.Z) then
				firstFailedCell = cell
				break
			end
		end
	end

	return footprintWalkable == true, {
		FootprintWidth = footprintWidth,
		FootprintDepth = footprintDepth,
		OriginalFootprintWidth = originalFootprintWidth,
		OriginalFootprintDepth = originalFootprintDepth,
		FootprintSource = source,
		OccupiedCells = occupiedCells,
		FirstFailedCell = firstFailedCell,
	}
end

local function isPreviewInsideRoom(model)
	local targetCFrame = model:GetPivot()
	local floorBounds = getFloorPlacementBounds()
	local modelBounds = getModelXZBoundsAtCFrame(model, targetCFrame)

	if not floorBounds or not modelBounds then
		return false
	end

	return modelBounds.minX >= floorBounds.minX
		and modelBounds.maxX <= floorBounds.maxX
		and modelBounds.minZ >= floorBounds.minZ
		and modelBounds.maxZ <= floorBounds.maxZ
end

local function isPreviewBlocked(model)
	local roomFolder = getCurrentRoomFolder()
	local furnitureFolder = getCurrentFurnitureFolder()

	if not roomFolder or not furnitureFolder then
		return true
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	local ignoreList = { model }

	if player.Character then
		table.insert(ignoreList, player.Character)
	end

	overlapParams.FilterDescendantsInstances = ignoreList

	for _, descendant in ipairs(getPlacementCheckParts(model)) do
		local touchingParts = workspace:GetPartBoundsInBox(
			descendant.CFrame,
			getOverlapCheckSize(descendant.Size),
			overlapParams
		)

		for _, touchingPart in ipairs(touchingParts) do
			if touchingPart.Name == "WalkableFloor" then
				continue
			end

			if isHelperPart(touchingPart) then
				continue
			end

			if touchingPart:IsDescendantOf(furnitureFolder) then
				if shouldIgnoreTouchedFurniturePart(touchingPart, furnitureFolder) then
					continue
				end

				if touchingPart.Name ~= PLACEMENT_BOUNDS_PART_NAME
					and touchingPart:IsA("BasePart")
					and touchingPart.CanCollide == false then

					continue
				end

				return true
			end

			if touchingPart:IsDescendantOf(roomFolder) then
				if touchingPart.Name:find("Boundary")
					or touchingPart.Name:find("Wall") then

					return true
				end

				if touchingPart:IsA("BasePart") and touchingPart.CanCollide then
					return true
				end
			end
		end
	end

	return false
end

local function playerIsInSameRoom(otherPlayer)
	return otherPlayer:GetAttribute("CurrentRoomName")
		== player:GetAttribute("CurrentRoomName")
end

local function isPreviewBlockedByPlayer(model)
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if playerIsInSameRoom(otherPlayer) then
			local character = otherPlayer.Character

			if character then
				local overlapParams = OverlapParams.new()
				overlapParams.FilterType = Enum.RaycastFilterType.Include
				overlapParams.FilterDescendantsInstances = { character }

				for _, descendant in ipairs(getPlacementCheckParts(model)) do
					local touchingParts = workspace:GetPartBoundsInBox(
						descendant.CFrame,
						getOverlapCheckSize(descendant.Size),
						overlapParams
					)

					if #touchingParts > 0 then
						return true
					end
				end
			end
		end
	end

	return false
end

function ui.placementMask.setPreviewVisualState(isValid, reason)
	local fillColor
	local tintedParts = 0
	local tintedHighlights = 0
	local tintedSelectionBoxes = 0

	if isValid then
		fillColor = Color3.fromRGB(0, 190, 255)
	else
		fillColor = Color3.fromRGB(255, 60, 60)
	end

	if placementPreviewHighlight then
		placementPreviewHighlight.Enabled = true
		placementPreviewHighlight.FillColor = fillColor
		placementPreviewHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
		placementPreviewHighlight.FillTransparency = 0.35
		placementPreviewHighlight.OutlineTransparency = 0
		placementPreviewHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		tintedHighlights += 1
	end

	if placementPreview then
		for _, descendant in ipairs(placementPreview:GetDescendants()) do
			if descendant:IsA("BasePart") and not isHelperPart(descendant) then
				local shouldTintPart = descendant.Name ~= PLACEMENT_BOUNDS_PART_NAME
					or descendant.Transparency < 1

				if shouldTintPart then
					descendant.Color = fillColor
					descendant.Transparency = 0.35
					descendant.Material = Enum.Material.Neon
					tintedParts += 1
				end
			elseif descendant:IsA("Highlight") then
				if not descendant.Adornee or not descendant.Adornee:IsDescendantOf(placementPreview) then
					descendant.Adornee = placementPreview
				end

				descendant.Enabled = true
				descendant.FillColor = fillColor
				descendant.OutlineColor = Color3.fromRGB(255, 255, 255)
				descendant.FillTransparency = 0.35
				descendant.OutlineTransparency = 0
				descendant.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				tintedHighlights += 1
			elseif descendant:IsA("SelectionBox") then
				descendant.Color3 = fillColor
				descendant.SurfaceColor3 = fillColor
				descendant.SurfaceTransparency = 0.65
				descendant.Transparency = 0
				tintedSelectionBoxes += 1
			elseif descendant:IsA("BoxHandleAdornment") then
				descendant.Color3 = fillColor
				descendant.Transparency = 0.35
				tintedSelectionBoxes += 1
			end
		end
	end

	if DEBUG_TILE_MASK_PLACEMENT == true then
		warn(
			"[FurnitureCatalog.TileMaskPlacement]",
			"visualState",
			isValid and "valid-blue" or "invalid-red",
			"reason",
			tostring(reason),
			"previewModel",
			placementPreview and placementPreview.Name or "nil",
			"highlightColor",
			tostring(placementPreviewHighlight and placementPreviewHighlight.FillColor),
			"previewPartsTinted",
			tostring(tintedParts),
			"highlightsTinted",
			tostring(tintedHighlights),
			"selectionBoxesTinted",
			tostring(tintedSelectionBoxes)
		)
	end

	ui.placementPreviewVisual.debug(
		"visualState",
		isValid and "valid-blue" or "invalid-red",
		"reason",
		tostring(reason),
		"selectionBoxesTinted",
		tostring(tintedSelectionBoxes)
	)
end

local function setPlacementPreviewValidity(isValid, reason)
	placementIsValid = isValid
	ui.placementMask.setPreviewVisualState(isValid, reason)
end

local function unbindCatalogPlacementControls()
	ContextActionService:UnbindAction(CATALOG_ROTATE_ACTION)
	ContextActionService:UnbindAction(CATALOG_CANCEL_ACTION)
end

local function handleCatalogPlacementAction(actionName, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end

	if not placingItemData then
		return Enum.ContextActionResult.Pass
	end

	if requestInFlight then
		return Enum.ContextActionResult.Sink
	end

	if actionName == CATALOG_ROTATE_ACTION then
		placementRotationY = (placementRotationY + 90) % 360
		setStatus("Rotated preview.")
		setPlacementHint(getActivePlacementHint(false))
		return Enum.ContextActionResult.Sink
	end

	if actionName == CATALOG_CANCEL_ACTION then
		ui.DestroyCatalogPlacementPreview()
		setStatus("Placement cancelled.")
		return Enum.ContextActionResult.Sink
	end

	return Enum.ContextActionResult.Sink
end

local function bindCatalogPlacementControls()
	unbindCatalogPlacementControls()

	ContextActionService:BindActionAtPriority(
		CATALOG_ROTATE_ACTION,
		handleCatalogPlacementAction,
		false,
		3000,
		Enum.KeyCode.R
	)

	ContextActionService:BindActionAtPriority(
		CATALOG_CANCEL_ACTION,
		handleCatalogPlacementAction,
		false,
		3000,
		Enum.KeyCode.C
	)
end

local function clearPlacementPreviewVisualsOnly()
	local cleanupCount = ui.placementPreviewVisual.countVisuals(placementPreview)

	if placementPreviewHighlight then
		placementPreviewHighlight:Destroy()
		placementPreviewHighlight = nil
	end

	if placementPreview then
		placementPreview:Destroy()
		placementPreview = nil
	end

	ui.placementPreviewVisual.debug("cleanup count", cleanupCount)
end

ui.DestroyCatalogPlacementPreview = function()
	clearPlacementPreviewVisualsOnly()

	unbindCatalogPlacementControls()

	placingItemData = nil
	placementIsValid = false
	placementRotationY = 0
	placementBaseRotation = CFrame.new()
	placementSource = nil
	requestInFlight = false

	setPlacementHint("")

	player:SetAttribute("CatalogPlacementActive", false)

	if ui.UpdateOpenButton then
		ui.UpdateOpenButton()
	end
end

local function createCatalogPlacementPreview(itemData, roomContext)
	ui.DestroyCatalogPlacementPreview()

	if roomContext and roomContext.RoomName ~= player:GetAttribute("CurrentRoomName") then
		setStatus("Room changed. Try placing again.")
		return false
	end

	local _, _, gridError = getCurrentPlacementGrid()

	if gridError then
		setStatus(gridError)
		return false
	end

	local templateName = itemData.TemplateName or itemData.Id
	local template = furnitureTemplates:FindFirstChild(templateName)

	if not template or not template:IsA("Model") then
		setStatus("Missing furniture template: " .. tostring(templateName))
		return false
	end

	local source = itemData.Source == "Inventory" and "Inventory" or "Catalog"
	local previewModel = template:Clone()

	previewModel.Name = "CatalogPlacementPreview"
	previewModel:SetAttribute("CatalogTemplateName", templateName)
	ui.placementMask.applyFootprintOverride(previewModel)

	local templatePivot = previewModel:GetPivot()
	placementBaseRotation = templatePivot - templatePivot.Position

	for _, descendant in ipairs(previewModel:GetDescendants()) do
		if descendant:IsA("Script")
			or descendant:IsA("LocalScript")
			or descendant:IsA("ClickDetector") then

			descendant:Destroy()

		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Transparency = math.max(descendant.Transparency, 0.55)
		end
	end

	local boundsVisualReady, boundsVisualMessage =
		ui.placementPreviewVisual.ensureBoundsVisual(previewModel)

	if not boundsVisualReady then
		previewModel:Destroy()
		setStatus(boundsVisualMessage or "Furniture preview visual setup failed.")
		return false
	end

	placementPreviewHighlight = Instance.new("Highlight")
	placementPreviewHighlight.Name = "CatalogPlacementPreviewHighlight"
	placementPreviewHighlight.Adornee = previewModel
	placementPreviewHighlight.FillTransparency = 0.45
	placementPreviewHighlight.OutlineTransparency = 0
	placementPreviewHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	placementPreviewHighlight.Parent = previewModel

	if not placementPreviewHighlight.Parent then
		previewModel:Destroy()
		setStatus("Furniture preview visual setup failed.")
		return false
	end

	placingItemData = itemData
	placementSource = source
	placementRotationY = 0
	placementPreview = previewModel
	placementPreview.Parent = workspace
	player:SetAttribute("CatalogPlacementActive", true)

	bindCatalogPlacementControls()

	setPlacementPreviewValidity(false)

	setPanelVisible(false)
	ui.OpenButton.Visible = false

	if placementSource == "Inventory" then
		setStatus("Move your cursor over the floor to place an owned item.")
	else
		setStatus("Move your cursor over the floor. Click to place, R to rotate, C to cancel.")
	end

	setPlacementHint(getActivePlacementHint(false))
	return true
end

local function updateCatalogPlacementPreview()
	if not placingItemData or not placementPreview then
		return
	end

	local targetCFrame, maskTarget = getPreviewPlacementCFrame(placementPreview)

	if not targetCFrame then
		setPlacementPreviewValidity(false, "NoPlacementTarget")
		return
	end

	placementPreview:PivotTo(targetCFrame)

	local maskFootprintWalkable, maskFootprintDebug =
		ui.placementMask.isFootprintWalkable(placementPreview, maskTarget)
	local invalidReason = nil

	if maskTarget and maskTarget.CellWalkable == false then
		invalidReason = "TileMaskTargetNotWalkable"
	elseif maskTarget and maskFootprintWalkable ~= true then
		invalidReason = "TileMaskFootprintNotWalkable"
	end

	local isValid = maskFootprintWalkable == true
		and isPreviewInsideRoom(placementPreview)
		and not isPreviewBlocked(placementPreview)
		and not isPreviewBlockedByPlayer(placementPreview)

	if not isValid and not invalidReason then
		invalidReason = "BlockedPlacement"
	end

	if DEBUG_TILE_MASK_PLACEMENT == true and maskTarget then
		local occupiedCellText = "none"
		local firstFailedCellText = "none"

		if maskFootprintDebug then
			local occupiedCellLabels = {}

			for _, cell in ipairs(maskFootprintDebug.OccupiedCells or {}) do
				table.insert(occupiedCellLabels, tostring(cell.X) .. "," .. tostring(cell.Z))
			end

			if #occupiedCellLabels > 0 then
				occupiedCellText = table.concat(occupiedCellLabels, " ")
			end

			if maskFootprintDebug.FirstFailedCell then
				firstFailedCellText = tostring(maskFootprintDebug.FirstFailedCell.X)
					.. ","
					.. tostring(maskFootprintDebug.FirstFailedCell.Z)
			end
		end

		warn(
			"[FurnitureCatalog.TileMaskPlacement]",
			"template",
			tostring(placingItemData and (placingItemData.TemplateName or placingItemData.Id) or placementPreview.Name),
			"furnitureName",
			tostring(placementPreview.Name),
			"footprintBeforeRotation",
			maskFootprintDebug
				and (tostring(maskFootprintDebug.OriginalFootprintWidth)
					.. "x"
					.. tostring(maskFootprintDebug.OriginalFootprintDepth))
				or "nil",
			"footprintAfterRotation",
			maskFootprintDebug
				and (tostring(maskFootprintDebug.FootprintWidth)
					.. "x"
					.. tostring(maskFootprintDebug.FootprintDepth))
				or "nil",
			"footprintSource",
			tostring(maskFootprintDebug and maskFootprintDebug.FootprintSource),
			"hitPart",
			maskTarget.HitPart and maskTarget.HitPart.Name or "nil",
			"hitPosition",
			tostring(maskTarget.HitPosition),
			"maskCell",
			tostring(maskTarget.CellX) .. "," .. tostring(maskTarget.CellZ),
			"UsesTileMask",
			tostring(maskTarget.Context and maskTarget.Context.UsesTileMask),
			"CellIsWalkable",
			tostring(maskTarget.CellWalkable),
			"FootprintCellsAreWalkable",
			tostring(maskFootprintWalkable),
			"occupiedCells",
			occupiedCellText,
			"firstFailedCell",
			firstFailedCellText,
			"finalCanPlace",
			tostring(isValid),
			"invalidReason",
			tostring(invalidReason)
		)
	end

	setPlacementPreviewValidity(isValid, invalidReason)
end

local function confirmCatalogPlacement()
	if not placingItemData or not placementPreview then
		return
	end

	if requestInFlight then
		return
	end

	if not placementIsValid then
		setStatus("That spot is blocked.")
		setPlacementHint(getActivePlacementHint(true))
		return
	end

	if placementSource ~= "Inventory" then
		setStatus("Open Inventory to place furniture.")
		ui.DestroyCatalogPlacementPreview()
		return
	end

	requestInFlight = true

	local itemId = placingItemData.Id
	local targetPosition = placementPreview:GetPivot().Position

	setStatus("Placing " .. tostring(placingItemData.DisplayName or itemId) .. "...")

	local payload = {
		ItemId = itemId,
		TargetPosition = targetPosition,
		RotationY = placementRotationY,
	}

	fireInventoryOptimisticPlacementDelta(placingItemData)

	furnitureCatalogRequest:FireServer("PlaceInventoryItem", payload)
	clearPlacementPreviewVisualsOnly()
	setStatus("Placing...")
end

local function clearItemRows()
	for _, child in ipairs(ui.ItemList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function setActivePurchaseButton(button, defaultText)
	if activePurchaseButton and activePurchaseButton.Parent then
		activePurchaseButton.Active = true
		activePurchaseButton.AutoButtonColor = true
		activePurchaseButton.Text = activePurchaseButtonText or "Buy"
	end

	activePurchaseButton = button
	activePurchaseButtonText = defaultText

	if button then
		button.Active = false
		button.AutoButtonColor = false
		button.Text = "Buying..."
	end
end

local function resetActivePurchaseButton()
	setActivePurchaseButton(nil, nil)
end

local function getPurchaseCurrencyForItem(itemData)
	local purchaseCurrency = itemData.PurchaseCurrency

	if typeof(purchaseCurrency) ~= "string" or purchaseCurrency == "" then
		return "Dollars"
	end

	return purchaseCurrency
end

local function itemMatchesSelectedCategory(itemData)
	if selectedCategory == "All" then
		return true
	end

	if selectedCategory == "Featured" then
		return itemData.Featured == true
	end

	local category = tostring(itemData.Category or "")
	local normalizedCategory = SHOP_CATEGORY_NORMALIZATION[category] or "Other"

	return normalizedCategory == selectedCategory
end

local function getShopCategoryForPage(page)
	for _, category in ipairs(CATALOG_SHOP_CATEGORIES) do
		if category.Page == page then
			return category.Category or "All"
		end
	end

	return nil
end

local function updateCategoryTabs()
	for _, child in ipairs(ui.CategoryFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function createEmptyCatalogState(message)
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyCatalogLabel"
	emptyLabel.Size = UDim2.new(1, -4, 0, 56)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Text = tostring(message or "No shop items found.")
	emptyLabel.TextColor3 = Color3.fromRGB(95, 95, 95)
	emptyLabel.TextSize = 15
	emptyLabel.TextWrapped = true
	emptyLabel.Font = Enum.Font.Gotham
	emptyLabel.Parent = ui.ItemList
end

local function createPageLabel(name, text, size, textSize, font, color)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.BackgroundTransparency = 1
	label.Text = tostring(text or "")
	label.TextColor3 = color or Color3.fromRGB(62, 53, 42)
	label.TextSize = textSize
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Font = font
	label.Parent = ui.ItemList
	return label
end

local function createPageButton(name, text, size)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.BackgroundColor3 = Color3.fromRGB(94, 73, 48)
	button.BorderSizePixel = 0
	button.Text = tostring(text or "Open")
	button.TextColor3 = Color3.fromRGB(255, 247, 219)
	button.TextSize = 14
	button.Font = Enum.Font.GothamBold
	button.Parent = ui.ItemList

	createCorner(button, 8)

	return button
end

local function createFrontPageOfferCard(title, body, order, accentColor)
	local card = Instance.new("Frame")
	card.Name = "FeaturedOfferCard"
	card.LayoutOrder = order
	card.Size = UDim2.new(1, -4, 0, 74)
	card.BackgroundColor3 = Color3.fromRGB(246, 239, 209)
	card.BorderSizePixel = 0
	card.Parent = ui.ItemList

	createCorner(card, 9)
	createStroke(card, Color3.fromRGB(176, 153, 110), 1, 0.3)

	local swatch = Instance.new("Frame")
	swatch.Name = "OfferSwatch"
	swatch.Position = UDim2.fromOffset(12, 13)
	swatch.Size = UDim2.fromOffset(48, 48)
	swatch.BackgroundColor3 = accentColor
	swatch.BorderSizePixel = 0
	swatch.Parent = card

	createCorner(swatch, 8)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "OfferTitle"
	titleLabel.Position = UDim2.fromOffset(72, 10)
	titleLabel.Size = UDim2.new(1, -88, 0, 22)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = title
	titleLabel.TextColor3 = Color3.fromRGB(59, 48, 34)
	titleLabel.TextSize = 15
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = card

	local bodyLabel = Instance.new("TextLabel")
	bodyLabel.Name = "OfferBody"
	bodyLabel.Position = UDim2.fromOffset(72, 34)
	bodyLabel.Size = UDim2.new(1, -88, 0, 30)
	bodyLabel.BackgroundTransparency = 1
	bodyLabel.Text = body
	bodyLabel.TextColor3 = Color3.fromRGB(88, 76, 60)
	bodyLabel.TextSize = 12
	bodyLabel.TextWrapped = true
	bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
	bodyLabel.Font = Enum.Font.Gotham
	bodyLabel.Parent = card
end

local function createFrontPageFeatureCard(parent, title, subtitle, accentColor, layoutOrder)
	local card = Instance.new("TextButton")
	card.Name = title:gsub("%W+", "") .. "FeatureCard"
	card.LayoutOrder = layoutOrder
	card.Size = UDim2.new(1, 0, 0, 68)
	card.BackgroundColor3 = Color3.fromRGB(247, 239, 209)
	card.BorderSizePixel = 0
	card.Text = ""
	card.Parent = parent

	createCorner(card, 8)
	createStroke(card, Color3.fromRGB(176, 153, 110), 1, 0.25)

	local graphic = Instance.new("Frame")
	graphic.Name = "Graphic"
	graphic.Position = UDim2.fromOffset(8, 8)
	graphic.Size = UDim2.fromOffset(52, 52)
	graphic.BackgroundColor3 = accentColor
	graphic.BorderSizePixel = 0
	graphic.Parent = card

	createCorner(graphic, 8)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Position = UDim2.fromOffset(68, 8)
	titleLabel.Size = UDim2.new(1, -76, 0, 22)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = title
	titleLabel.TextColor3 = Color3.fromRGB(59, 48, 34)
	titleLabel.TextSize = 13
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = card

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "Subtitle"
	subtitleLabel.Position = UDim2.fromOffset(68, 31)
	subtitleLabel.Size = UDim2.new(1, -76, 0, 28)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Text = subtitle
	subtitleLabel.TextColor3 = Color3.fromRGB(88, 76, 60)
	subtitleLabel.TextSize = 11
	subtitleLabel.TextWrapped = true
	subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	subtitleLabel.Font = Enum.Font.Gotham
	subtitleLabel.Parent = card

	card.MouseButton1Click:Connect(function()
		if title == "Fresh Lobby Looks" and selectCatalogPage then
			selectCatalogPage(CATALOG_PAGE.FURNITURE_SHOP)
		else
			setStatus("Coming soon.")
		end
	end)

	return card
end

local function renderFrontPage()
	updateCatalogChrome()
	clearItemRows()
	setStatus("Read the latest catalog highlights.")

	local header = Instance.new("Frame")
	header.Name = "FrontPageHeader"
	header.LayoutOrder = 1
	header.Size = UDim2.new(1, -4, 0, 48)
	header.BackgroundColor3 = Color3.fromRGB(96, 75, 49)
	header.BorderSizePixel = 0
	header.Parent = ui.ItemList

	createCorner(header, 9)

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Name = "Title"
	headerTitle.Position = UDim2.fromOffset(16, 5)
	headerTitle.Size = UDim2.new(1, -32, 0, 24)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Text = "Catalog Front Page"
	headerTitle.TextColor3 = Color3.fromRGB(255, 247, 219)
	headerTitle.TextSize = 20
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.Font = Enum.Font.GothamBlack
	headerTitle.Parent = header

	local headerSubtitle = Instance.new("TextLabel")
	headerSubtitle.Name = "Subtitle"
	headerSubtitle.Position = UDim2.fromOffset(16, 28)
	headerSubtitle.Size = UDim2.new(1, -32, 0, 16)
	headerSubtitle.BackgroundTransparency = 1
	headerSubtitle.Text = "Featured furniture, room ideas, and hotel offers"
	headerSubtitle.TextColor3 = Color3.fromRGB(235, 224, 190)
	headerSubtitle.TextSize = 12
	headerSubtitle.TextXAlignment = Enum.TextXAlignment.Left
	headerSubtitle.Font = Enum.Font.Gotham
	headerSubtitle.Parent = header

	local featureArea = Instance.new("Frame")
	featureArea.Name = "FeatureArea"
	featureArea.LayoutOrder = 2
	featureArea.Size = UDim2.new(1, -4, 0, 234)
	featureArea.BackgroundTransparency = 1
	featureArea.Parent = ui.ItemList

	local mainFeature = Instance.new("Frame")
	mainFeature.Name = "MainFeature"
	mainFeature.Position = UDim2.fromOffset(0, 0)
	mainFeature.Size = UDim2.new(0.61, -6, 1, 0)
	mainFeature.BackgroundColor3 = Color3.fromRGB(74, 97, 132)
	mainFeature.BorderSizePixel = 0
	mainFeature.Parent = featureArea

	createCorner(mainFeature, 10)
	createStroke(mainFeature, Color3.fromRGB(59, 48, 34), 1, 0.18)

	local mainTitle = Instance.new("TextLabel")
	mainTitle.Name = "MainTitle"
	mainTitle.Position = UDim2.fromOffset(16, 14)
	mainTitle.Size = UDim2.new(1, -32, 0, 30)
	mainTitle.BackgroundTransparency = 1
	mainTitle.Text = "NEW FURNI: Studio Set"
	mainTitle.TextColor3 = Color3.fromRGB(255, 247, 219)
	mainTitle.TextSize = 21
	mainTitle.TextXAlignment = Enum.TextXAlignment.Left
	mainTitle.Font = Enum.Font.GothamBlack
	mainTitle.Parent = mainFeature

	local mainSubtitle = Instance.new("TextLabel")
	mainSubtitle.Name = "MainSubtitle"
	mainSubtitle.Position = UDim2.fromOffset(16, 46)
	mainSubtitle.Size = UDim2.new(1, -32, 0, 42)
	mainSubtitle.BackgroundTransparency = 1
	mainSubtitle.Text = "Build your own broadcast room!"
	mainSubtitle.TextColor3 = Color3.fromRGB(235, 229, 198)
	mainSubtitle.TextSize = 15
	mainSubtitle.TextWrapped = true
	mainSubtitle.TextXAlignment = Enum.TextXAlignment.Left
	mainSubtitle.Font = Enum.Font.GothamBold
	mainSubtitle.Parent = mainFeature

	for index = 1, 4 do
		local prop = Instance.new("Frame")
		prop.Name = "StudioProp_" .. tostring(index)
		prop.Position = UDim2.fromOffset(24 + index * 38, 120 - (index % 2) * 18)
		prop.Size = UDim2.fromOffset(32 + index * 4, 44 + index * 6)
		prop.BackgroundColor3 = index % 2 == 0
			and Color3.fromRGB(244, 207, 95)
			or Color3.fromRGB(180, 205, 220)
		prop.BorderSizePixel = 0
		prop.Parent = mainFeature

		createCorner(prop, 7)
	end

	local viewCollection = Instance.new("TextButton")
	viewCollection.Name = "ViewCollectionButton"
	viewCollection.Position = UDim2.fromOffset(16, 188)
	viewCollection.Size = UDim2.fromOffset(132, 32)
	viewCollection.BackgroundColor3 = Color3.fromRGB(244, 207, 95)
	viewCollection.BorderSizePixel = 0
	viewCollection.Text = "View Collection"
	viewCollection.TextColor3 = Color3.fromRGB(62, 48, 34)
	viewCollection.TextSize = 13
	viewCollection.Font = Enum.Font.GothamBold
	viewCollection.Parent = mainFeature

	createCorner(viewCollection, 8)

	viewCollection.MouseButton1Click:Connect(function()
		if selectCatalogPage then
			selectCatalogPage(CATALOG_PAGE.FURNITURE_SHOP)
		end
	end)

	local rightStack = Instance.new("Frame")
	rightStack.Name = "FeatureStack"
	rightStack.Position = UDim2.new(0.61, 8, 0, 0)
	rightStack.Size = UDim2.new(0.39, -8, 1, 0)
	rightStack.BackgroundTransparency = 1
	rightStack.Parent = featureArea

	local rightLayout = Instance.new("UIListLayout")
	rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rightLayout.Padding = UDim.new(0, 8)
	rightLayout.Parent = rightStack

	createFrontPageFeatureCard(rightStack, "Fresh Lobby Looks", "Clean welcomes for every guest.", Color3.fromRGB(84, 132, 98), 1)
	createFrontPageFeatureCard(rightStack, "Cozy Cafe Collection", "Warm seats and soft details.", Color3.fromRGB(132, 82, 70), 2)
	createFrontPageFeatureCard(rightStack, "Become a VIP Member", "Member perks are coming later.", Color3.fromRGB(112, 94, 150), 3)

	local voucherFrame = Instance.new("Frame")
	voucherFrame.Name = "VoucherStrip"
	voucherFrame.LayoutOrder = 3
	voucherFrame.Size = UDim2.new(1, -4, 0, 58)
	voucherFrame.BackgroundColor3 = Color3.fromRGB(246, 239, 209)
	voucherFrame.BorderSizePixel = 0
	voucherFrame.Parent = ui.ItemList

	createCorner(voucherFrame, 9)
	createStroke(voucherFrame, Color3.fromRGB(176, 153, 110), 1, 0.28)

	local voucherBox = Instance.new("TextBox")
	voucherBox.Name = "VoucherBox"
	voucherBox.Position = UDim2.fromOffset(14, 13)
	voucherBox.Size = UDim2.new(1, -126, 0, 32)
	voucherBox.BackgroundColor3 = Color3.fromRGB(255, 252, 235)
	voucherBox.BorderSizePixel = 0
	voucherBox.ClearTextOnFocus = false
	voucherBox.PlaceholderText = "Redeem a voucher code here..."
	voucherBox.Text = ""
	voucherBox.TextColor3 = Color3.fromRGB(62, 48, 34)
	voucherBox.PlaceholderColor3 = Color3.fromRGB(122, 106, 82)
	voucherBox.TextSize = 13
	voucherBox.TextXAlignment = Enum.TextXAlignment.Left
	voucherBox.Font = Enum.Font.Gotham
	voucherBox.Parent = voucherFrame

	createCorner(voucherBox, 8)
	createStroke(voucherBox, Color3.fromRGB(176, 153, 110), 1, 0.3)

	local redeemButton = Instance.new("TextButton")
	redeemButton.Name = "RedeemVoucherButton"
	redeemButton.AnchorPoint = Vector2.new(1, 0)
	redeemButton.Position = UDim2.new(1, -14, 0, 13)
	redeemButton.Size = UDim2.fromOffset(96, 32)
	redeemButton.BackgroundColor3 = Color3.fromRGB(94, 73, 48)
	redeemButton.BorderSizePixel = 0
	redeemButton.Text = "Redeem"
	redeemButton.TextColor3 = Color3.fromRGB(255, 247, 219)
	redeemButton.TextSize = 13
	redeemButton.Font = Enum.Font.GothamBold
	redeemButton.Parent = voucherFrame

	createCorner(redeemButton, 8)

	redeemButton.MouseButton1Click:Connect(function()
		setStatus("Vouchers are coming soon.")
	end)

	task.defer(function()
		ui.ItemList.CanvasSize = UDim2.fromOffset(0, ui.ListLayout.AbsoluteContentSize.Y + 48)
	end)
end

local function createCoinPackageCard(parent, amount, priceText, layoutOrder)
	local card = Instance.new("Frame")
	card.Name = tostring(amount) .. "CoinPackage"
	card.LayoutOrder = layoutOrder
	card.Size = UDim2.fromOffset(138, 164)
	card.BackgroundColor3 = Color3.fromRGB(247, 239, 209)
	card.BorderSizePixel = 0
	card.Parent = parent

	createCorner(card, 10)
	createStroke(card, Color3.fromRGB(176, 153, 110), 1, 0.24)

	local coinGraphic = Instance.new("Frame")
	coinGraphic.Name = "CoinGraphic"
	coinGraphic.AnchorPoint = Vector2.new(0.5, 0)
	coinGraphic.Position = UDim2.new(0.5, 0, 0, 12)
	coinGraphic.Size = UDim2.fromOffset(54, 54)
	coinGraphic.BackgroundColor3 = Color3.fromRGB(244, 207, 95)
	coinGraphic.BorderSizePixel = 0
	coinGraphic.Parent = card

	createCorner(coinGraphic, 27)
	createStroke(coinGraphic, Color3.fromRGB(124, 92, 38), 1, 0.18)

	local amountLabel = Instance.new("TextLabel")
	amountLabel.Name = "Amount"
	amountLabel.Position = UDim2.fromOffset(10, 70)
	amountLabel.Size = UDim2.new(1, -20, 0, 22)
	amountLabel.BackgroundTransparency = 1
	amountLabel.Text = tostring(amount) .. " Coins"
	amountLabel.TextColor3 = Color3.fromRGB(62, 48, 34)
	amountLabel.TextSize = 15
	amountLabel.Font = Enum.Font.GothamBold
	amountLabel.Parent = card

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "Price"
	priceLabel.Position = UDim2.fromOffset(10, 92)
	priceLabel.Size = UDim2.new(1, -20, 0, 18)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Text = priceText
	priceLabel.TextColor3 = Color3.fromRGB(88, 76, 60)
	priceLabel.TextSize = 12
	priceLabel.Font = Enum.Font.Gotham
	priceLabel.Parent = card

	local noteLabel = Instance.new("TextLabel")
	noteLabel.Name = "Note"
	noteLabel.Position = UDim2.fromOffset(10, 110)
	noteLabel.Size = UDim2.new(1, -20, 0, 16)
	noteLabel.BackgroundTransparency = 1
	noteLabel.Text = "Robux purchase coming soon."
	noteLabel.TextColor3 = Color3.fromRGB(116, 98, 72)
	noteLabel.TextSize = 10
	noteLabel.TextTruncate = Enum.TextTruncate.AtEnd
	noteLabel.Font = Enum.Font.Gotham
	noteLabel.Parent = card

	local buyButton = Instance.new("TextButton")
	buyButton.Name = "BuyButton"
	buyButton.AnchorPoint = Vector2.new(0.5, 1)
	buyButton.Position = UDim2.new(0.5, 0, 1, -12)
	buyButton.Size = UDim2.fromOffset(84, 26)
	buyButton.BackgroundColor3 = Color3.fromRGB(94, 73, 48)
	buyButton.BorderSizePixel = 0
	buyButton.Text = "Buy"
	buyButton.TextColor3 = Color3.fromRGB(255, 247, 219)
	buyButton.TextSize = 12
	buyButton.Font = Enum.Font.GothamBold
	buyButton.Parent = card

	createCorner(buyButton, 7)

	buyButton.MouseButton1Click:Connect(function()
		setStatus("Coin purchases are coming soon.")
	end)
end

local function renderCoinShopPage()
	updateCatalogChrome()
	clearItemRows()
	setStatus("Coin purchases are coming soon.")

	createPageLabel(
		"CoinShopTitle",
		"Coin Shop",
		UDim2.new(1, -4, 0, 32),
		22,
		Enum.Font.GothamBold,
		Color3.fromRGB(62, 48, 34)
	).LayoutOrder = 1
	createPageLabel(
		"CoinShopSubtitle",
		"Buy Coins to use for premium furniture and Marketplace purchases.",
		UDim2.new(1, -4, 0, 42),
		14,
		Enum.Font.Gotham,
		Color3.fromRGB(88, 76, 60)
	).LayoutOrder = 2

	local packageRow = Instance.new("ScrollingFrame")
	packageRow.Name = "CoinPackageRow"
	packageRow.LayoutOrder = 3
	packageRow.Size = UDim2.new(1, -4, 0, 184)
	packageRow.BackgroundColor3 = Color3.fromRGB(246, 239, 209)
	packageRow.BorderSizePixel = 0
	packageRow.ScrollBarThickness = 5
	packageRow.ScrollingDirection = Enum.ScrollingDirection.X
	packageRow.CanvasSize = UDim2.fromOffset(612, 0)
	packageRow.Parent = ui.ItemList

	createCorner(packageRow, 10)
	createStroke(packageRow, Color3.fromRGB(176, 153, 110), 1, 0.28)

	local packageLayout = Instance.new("UIListLayout")
	packageLayout.FillDirection = Enum.FillDirection.Horizontal
	packageLayout.SortOrder = Enum.SortOrder.LayoutOrder
	packageLayout.Padding = UDim.new(0, 10)
	packageLayout.Parent = packageRow

	local packagePadding = Instance.new("UIPadding")
	packagePadding.PaddingTop = UDim.new(0, 9)
	packagePadding.PaddingBottom = UDim.new(0, 9)
	packagePadding.PaddingLeft = UDim.new(0, 10)
	packagePadding.PaddingRight = UDim.new(0, 10)
	packagePadding.Parent = packageRow

	createCoinPackageCard(packageRow, 50, "49 Robux", 1)
	createCoinPackageCard(packageRow, 100, "89 Robux", 2)
	createCoinPackageCard(packageRow, 250, "199 Robux", 3)
	createCoinPackageCard(packageRow, 500, "349 Robux", 4)

	createFrontPageOfferCard(
		"About Coins",
		"Coins are used for premium furniture and Marketplace purchases. Real purchases will be enabled in a later patch.",
		4,
		Color3.fromRGB(244, 207, 95)
	)

	task.defer(function()
		packageRow.CanvasSize = UDim2.fromOffset(packageLayout.AbsoluteContentSize.X + 28, 0)
		ui.ItemList.CanvasSize = UDim2.fromOffset(0, ui.ListLayout.AbsoluteContentSize.Y + 48)
	end)
end

local function renderDollarsInfoPage()
	updateCatalogChrome()
	clearItemRows()
	setStatus("Dollars are earned through hotel activities.")

	createPageLabel(
		"DollarsInfoTitle",
		"How to get Dollars",
		UDim2.new(1, -4, 0, 32),
		22,
		Enum.Font.GothamBold,
		Color3.fromRGB(62, 48, 34)
	).LayoutOrder = 1
	createPageLabel(
		"DollarsInfoSubtitle",
		"Dollars are the regular furniture currency.",
		UDim2.new(1, -4, 0, 34),
		14,
		Enum.Font.Gotham,
		Color3.fromRGB(88, 76, 60)
	).LayoutOrder = 2

	createFrontPageOfferCard("Work Mode", "Earn Dollars through Work Mode.", 3, Color3.fromRGB(112, 150, 101))
	createFrontPageOfferCard("Daily Rewards", "Claim Daily rewards when they are available.", 4, Color3.fromRGB(84, 132, 98))
	createFrontPageOfferCard("Furniture", "Use Dollars for regular furniture. Dollar furniture is usually untradable.", 5, Color3.fromRGB(132, 82, 70))

	local infoButton = createPageButton("DollarsInfoActionButton", "Go to Main Menu to Work", UDim2.fromOffset(206, 34))
	infoButton.LayoutOrder = 6
	infoButton.MouseButton1Click:Connect(function()
		setStatus("Go to the Main Menu to open Work.")
	end)

	task.defer(function()
		ui.ItemList.CanvasSize = UDim2.fromOffset(0, ui.ListLayout.AbsoluteContentSize.Y + 48)
	end)
end

do
	local floorFinishes = ui.FloorFinishes

	floorFinishes.getPriceText = function(styleData)
		local currencyKey = tostring(styleData.ApplyCurrencyKey or styleData.CurrencyKey or "Dollars")
		local price = styleData.ApplyPrice or styleData.ApplyCost or styleData.Price

		if typeof(price) ~= "number"
			or price ~= price
			or price < 0
			or price == math.huge then

			price = 0
		end

		return tostring(math.floor(price)) .. " " .. currencyKey
	end

	floorFinishes.requestOffers = function(options)
		options = options or {}

		if floorFinishes.RequestInFlight then
			return
		end

		floorFinishes.RequestInFlight = true

		if options.SetStatus ~= false then
			setStatus("Loading floor finishes...")
		end

		furnitureCatalogRequest:FireServer("GetFloorStyleOffers", {})

		task.delay(REQUEST_TIMEOUT_SECONDS, function()
			if floorFinishes.RequestInFlight then
				floorFinishes.RequestInFlight = false

				if catalogViewMode == CATALOG_VIEW.ROOM_FINISHES then
					floorFinishes.renderPage()
					setStatus("Floor finishes request timed out.")
				end
			end
		end)
	end

	floorFinishes.createCard = function(styleData, layoutOrder)
		local floorStyleId = tostring(styleData.FloorStyleId or "")
		local isStarter = styleData.Starter == true or styleData.IsStarter == true
		local isFree = styleData.IsFree == true or isStarter or floorFinishes.getPriceText(styleData) == "0 Dollars"

		local card = Instance.new("Frame")
		card.Name = "FloorStyleOffer_" .. floorStyleId
		card.LayoutOrder = layoutOrder
		card.Size = UDim2.new(1, -4, 0, 124)
		card.BackgroundColor3 = Color3.fromRGB(246, 239, 209)
		card.BorderSizePixel = 0
		card.Parent = ui.ItemList

		createCorner(card, 10)
		createStroke(card, Color3.fromRGB(176, 153, 110), 1, 0.28)

		local swatch = Instance.new("Frame")
		swatch.Name = "PatternSwatch"
		swatch.Position = UDim2.fromOffset(12, 14)
		swatch.Size = UDim2.fromOffset(54, 54)
		swatch.BackgroundColor3 = isFree and Color3.fromRGB(94, 126, 86) or Color3.fromRGB(132, 105, 76)
		swatch.BorderSizePixel = 0
		swatch.Parent = card

		createCorner(swatch, 8)
		createStroke(swatch, Color3.fromRGB(84, 68, 48), 1, 0.2)

		local swatchText = Instance.new("TextLabel")
		swatchText.Name = "PatternText"
		swatchText.Size = UDim2.fromScale(1, 1)
		swatchText.BackgroundTransparency = 1
		swatchText.Text = tostring(styleData.Pattern or "?")
		swatchText.TextColor3 = Color3.fromRGB(255, 247, 219)
		swatchText.TextSize = 11
		swatchText.TextWrapped = true
		swatchText.Font = Enum.Font.GothamBold
		swatchText.Parent = swatch

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "Name"
		nameLabel.Position = UDim2.fromOffset(78, 10)
		nameLabel.Size = UDim2.new(1, -210, 0, 24)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = tostring(styleData.DisplayName or floorStyleId)
		nameLabel.TextColor3 = Color3.fromRGB(59, 48, 34)
		nameLabel.TextSize = 15
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.Parent = card

		local descriptionLabel = Instance.new("TextLabel")
		descriptionLabel.Name = "Description"
		descriptionLabel.Position = UDim2.fromOffset(78, 36)
		descriptionLabel.Size = UDim2.new(1, -210, 0, 36)
		descriptionLabel.BackgroundTransparency = 1
		descriptionLabel.Text = tostring(styleData.Description or "Room floor finish.")
		descriptionLabel.TextColor3 = Color3.fromRGB(88, 76, 60)
		descriptionLabel.TextSize = 12
		descriptionLabel.TextWrapped = true
		descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
		descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
		descriptionLabel.Font = Enum.Font.Gotham
		descriptionLabel.Parent = card

		local metaParts = {
			"Pattern: " .. tostring(styleData.Pattern or "Floor"),
		}

		if isStarter then
			table.insert(metaParts, "Starter")
		elseif styleData.CanPurchase == true then
			table.insert(metaParts, "Apply: " .. floorFinishes.getPriceText(styleData))
		else
			table.insert(metaParts, "Free")
		end

		local metaLabel = Instance.new("TextLabel")
		metaLabel.Name = "Metadata"
		metaLabel.Position = UDim2.fromOffset(78, 76)
		metaLabel.Size = UDim2.new(1, -210, 0, 18)
		metaLabel.BackgroundTransparency = 1
		metaLabel.Text = table.concat(metaParts, " | ")
		metaLabel.TextColor3 = Color3.fromRGB(116, 98, 72)
		metaLabel.TextSize = 11
		metaLabel.TextXAlignment = Enum.TextXAlignment.Left
		metaLabel.TextTruncate = Enum.TextTruncate.AtEnd
		metaLabel.Font = Enum.Font.GothamMedium
		metaLabel.Parent = card

		local helperLabel = Instance.new("TextLabel")
		helperLabel.Name = "Helper"
		helperLabel.Position = UDim2.fromOffset(78, 96)
		helperLabel.Size = UDim2.new(1, -210, 0, 16)
		helperLabel.BackgroundTransparency = 1
		helperLabel.Text = "Preview and apply floors from Room Settings."
		helperLabel.TextColor3 = Color3.fromRGB(116, 98, 72)
		helperLabel.TextSize = 10
		helperLabel.TextXAlignment = Enum.TextXAlignment.Left
		helperLabel.TextTruncate = Enum.TextTruncate.AtEnd
		helperLabel.Font = Enum.Font.Gotham
		helperLabel.Parent = card

		local badge = Instance.new("TextLabel")
		badge.Name = "StatusBadge"
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, -12, 0, 12)
		badge.Size = UDim2.fromOffset(92, 24)
		badge.BackgroundColor3 = isStarter and Color3.fromRGB(142, 112, 66) or Color3.fromRGB(84, 132, 98)
		badge.BorderSizePixel = 0
		badge.Text = isStarter and "Starter" or (isFree and "Free" or "Paid")
		badge.TextColor3 = Color3.fromRGB(255, 247, 219)
		badge.TextSize = 11
		badge.Font = Enum.Font.GothamBold
		badge.Parent = card

		createCorner(badge, 7)

		local actionButton = Instance.new("TextButton")
		actionButton.Name = "FloorStyleActionButton"
		actionButton.AnchorPoint = Vector2.new(1, 1)
		actionButton.Position = UDim2.new(1, -12, 1, -12)
		actionButton.Size = UDim2.fromOffset(104, 30)
		actionButton.BorderSizePixel = 0
		actionButton.TextSize = 12
		actionButton.Font = Enum.Font.GothamBold
		actionButton.Parent = card

		actionButton.BackgroundColor3 = Color3.fromRGB(155, 160, 155)
		actionButton.Text = "Room Settings"
		actionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		actionButton.Active = false
		actionButton.AutoButtonColor = false

		createCorner(actionButton, 7)
	end

	floorFinishes.renderPage = function()
		updateCatalogChrome()
		clearItemRows()

		createPageLabel(
			"RoomFinishesTitle",
			"Room Finishes: Floors",
			UDim2.new(1, -4, 0, 32),
			22,
			Enum.Font.GothamBold,
			Color3.fromRGB(62, 48, 34)
		).LayoutOrder = 1

		createPageLabel(
			"RoomFinishesSubtitle",
			"Browse room finishes here. Preview and apply floors from Room Settings.",
			UDim2.new(1, -4, 0, 42),
			14,
			Enum.Font.Gotham,
			Color3.fromRGB(88, 76, 60)
		).LayoutOrder = 2

		local offers = floorFinishes.Offers

		if floorFinishes.RequestInFlight and #offers == 0 then
			createEmptyCatalogState("Loading floor finishes...")
		elseif #offers == 0 then
			createEmptyCatalogState("No floor finishes found.")
		end

		for index, styleData in ipairs(offers) do
			floorFinishes.createCard(styleData, index + 2)
		end

		if floorFinishes.RequestInFlight then
			setStatus("Loading floor finishes...")
		elseif #offers > 0 then
			setStatus("Preview and apply floors from Room Settings.")
		end

		task.defer(function()
			ui.ItemList.CanvasSize = UDim2.fromOffset(0, ui.ListLayout.AbsoluteContentSize.Y + 20)
		end)
	end
end

local function renderPlaceholderPage(page)
	local placeholder = PLACEHOLDER_PAGE_CONTENT[page] or PLACEHOLDER_PAGE_CONTENT[CATALOG_PAGE.BEST_SELLERS]

	updateCatalogChrome()
	clearItemRows()
	setStatus(placeholder.Title .. " is coming soon.")

	createPageLabel(
		"PlaceholderTitle",
		placeholder.Title,
		UDim2.new(1, -4, 0, 32),
		22,
		Enum.Font.GothamBold,
		Color3.fromRGB(62, 48, 34)
	).LayoutOrder = 1
	createPageLabel(
		"PlaceholderBody",
		placeholder.Body,
		UDim2.new(1, -4, 0, 58),
		15,
		Enum.Font.Gotham,
		Color3.fromRGB(88, 76, 60)
	).LayoutOrder = 2

	local button = createPageButton("PlaceholderActionButton", placeholder.Button, UDim2.fromOffset(158, 34))
	button.LayoutOrder = 3
	button.MouseButton1Click:Connect(function()
		setStatus(placeholder.Title .. " is coming soon.")
	end)

	task.defer(function()
		ui.ItemList.CanvasSize = UDim2.fromOffset(0, ui.ListLayout.AbsoluteContentSize.Y + 20)
	end)
end

local function renderMarketplaceInstructions()
	updateCatalogChrome()
	clearItemRows()
	setStatus("Read how Marketplace listings work.")

	createPageLabel(
		"InstructionsTitle",
		"Marketplace Instructions",
		UDim2.new(1, -4, 0, 32),
		22,
		Enum.Font.GothamBold,
		Color3.fromRGB(62, 48, 34)
	).LayoutOrder = 1

	local instructions = {
		"List tradable items from your Inventory.",
		"Buy Marketplace items with Coins.",
		"Untradable items cannot be listed.",
	}

	for index, text in ipairs(instructions) do
		createFrontPageOfferCard(tostring(index) .. ". " .. text, "Marketplace systems stay server-authoritative.", index + 1, Color3.fromRGB(94, 73, 48))
	end

	task.defer(function()
		ui.ItemList.CanvasSize = UDim2.fromOffset(0, ui.ListLayout.AbsoluteContentSize.Y + 20)
	end)
end

local function getMarketplaceWaitMessage(message)
	local normalizedMessage = tostring(message or "")

	if normalizedMessage:find("Slow down", 1, true)
		or normalizedMessage:find("busy", 1, true)
		or normalizedMessage:find("try again", 1, true) then

		return "Please wait a moment."
	end

	return normalizedMessage
end

local function formatListingCreatedAt(createdAt)
	if typeof(createdAt) ~= "number" or createdAt <= 0 then
		return ""
	end

	local ok, formatted = pcall(os.date, "%m/%d %H:%M", math.floor(createdAt))

	if ok and typeof(formatted) == "string" then
		return formatted
	end

	return ""
end

local function getMarketplaceStatusColor(status)
	if status == "Active" then
		return Color3.fromRGB(45, 110, 65)
	end

	if status == "Sold" then
		return Color3.fromRGB(55, 95, 150)
	end

	if status == "Cancelled" then
		return Color3.fromRGB(130, 95, 65)
	end

	return Color3.fromRGB(105, 105, 105)
end

local function getMarketplaceSaleStatusText(listing)
	local status = tostring(listing and listing.Status or "Unknown")
	local createdText = formatListingCreatedAt(listing and listing.CreatedAt)
	local updatedText = formatListingCreatedAt(listing and listing.UpdatedAt)
	local soldText = formatListingCreatedAt(listing and listing.SoldAt)
	local detailText = ""

	if status == "Active" and createdText ~= "" then
		detailText = "Created " .. createdText
	elseif status == "Sold" and soldText ~= "" then
		detailText = "Sold " .. soldText
	elseif status == "Sold" and updatedText ~= "" then
		detailText = "Sold " .. updatedText
	elseif status == "Cancelled" and updatedText ~= "" then
		detailText = "Cancelled " .. updatedText
	elseif createdText ~= "" then
		detailText = "Created " .. createdText
	end

	if detailText ~= "" then
		return status .. " | " .. detailText
	end

	return status
end

local function getMarketplaceClaimableCoins(listing)
	if typeof(listing) ~= "table" then
		return nil
	end

	local claimableCoins = listing.ClaimableCoins

	if typeof(claimableCoins) == "number"
		and claimableCoins == claimableCoins
		and claimableCoins > 0
		and claimableCoins < math.huge then

		return math.floor(claimableCoins)
	end

	return nil
end

local function isMarketplaceSaleUnclaimed(listing)
	return typeof(listing) == "table"
		and tostring(listing.Status or "") == "Sold"
		and listing.ProceedsClaimed ~= true
		and getMarketplaceClaimableCoins(listing) ~= nil
end

local function shouldShowMarketplaceSaleHistory(listing)
	if isMarketplaceSaleUnclaimed(listing) then
		return true
	end

	local status = tostring(listing and listing.Status or "")

	if status ~= "Sold" then
		return false
	end

	local historyTime = nil

	historyTime = listing.ClaimedAt or listing.SoldAt or listing.UpdatedAt

	if typeof(historyTime) ~= "number" or historyTime <= 0 then
		return true
	end

	return os.time() - historyTime <= 30 * 24 * 60 * 60
end

local function getMarketplaceListingDisplayName(listing)
	if typeof(listing) == "table"
		and typeof(listing.DisplayName) == "string"
		and listing.DisplayName ~= "" then

		return listing.DisplayName
	end

	local templateId = listing and listing.TemplateId

	if typeof(templateId) == "string" then
		for _, itemData in ipairs(latestCatalogItems) do
			if typeof(itemData) == "table"
				and (itemData.TemplateName == templateId or itemData.Id == templateId)
				and typeof(itemData.DisplayName) == "string"
				and itemData.DisplayName ~= "" then

				return itemData.DisplayName
			end
		end
	end

	return tostring(templateId or "Marketplace item")
end

local function getMarketplaceSellerText(listing)
	local sellerName = listing and (listing.SellerDisplayName or listing.SellerName)

	if typeof(sellerName) ~= "string" or sellerName == "" then
		sellerName = "Unknown seller"
	end

	if listing and listing.IsOwnListing == true then
		return sellerName .. " (You)"
	end

	return sellerName
end

local function fireInventoryLocalDeltaFromMarketplaceDetails(templateId, details)
	if typeof(templateId) ~= "string" or templateId == "" or typeof(details) ~= "table" then
		return
	end

	inventoryLocalDelta:Fire({
		TemplateId = templateId,
		Total = details.Total,
		Tradable = details.Tradable,
		Untradable = details.Untradable,
		Sellable = details.Sellable,
		Unsellable = details.Unsellable,
	})
end

local function getMarketplaceListingTotalPrice(listing)
	if typeof(listing) ~= "table" then
		return 0
	end

	local quantity = listing.Quantity
	local unitPriceCoins = listing.UnitPriceCoins

	if typeof(quantity) ~= "number"
		or typeof(unitPriceCoins) ~= "number"
		or quantity <= 0
		or unitPriceCoins <= 0 then

		return 0
	end

	return math.floor(quantity) * math.floor(unitPriceCoins)
end

local function getMarketplacePurchaseKey(listing)
	if typeof(listing) ~= "table" then
		return nil
	end

	if listing.IsOfferGroup == true and typeof(listing.TemplateId) == "string" and listing.TemplateId ~= "" then
		return "Group:" .. listing.TemplateId
	end

	if typeof(listing.ListingId) == "string" and listing.ListingId ~= "" then
		return listing.ListingId
	end

	return nil
end

local function truncateMarketplaceDescription(description)
	local text = tostring(description or "")
	local maxLength = 92

	if #text <= maxLength then
		return text
	end

	return string.sub(text, 1, maxLength - 3) .. "..."
end

local function setMarketplacePurchaseStatus(text, isError)
	ui.MarketplacePurchaseStatus.Text = tostring(text or "")
	ui.MarketplacePurchaseStatus.TextColor3 = isError == true
		and Color3.fromRGB(150, 60, 60)
		or Color3.fromRGB(85, 85, 85)
end

local function closeMarketplacePurchaseModal()
	if marketplacePurchaseRequestInFlight then
		return
	end

	ui.MarketplacePurchaseOverlay.Visible = false
	marketplacePurchaseListing = nil
	setMarketplacePurchaseStatus("", false)
end

local function updateMarketplacePurchaseModal()
	local listing = marketplacePurchaseListing
	local isInFlight = marketplacePurchaseRequestInFlight
	local itemName = getMarketplaceListingDisplayName(listing)
	local totalPrice = getMarketplaceListingTotalPrice(listing)

	if typeof(listing) == "table" and listing.IsOfferGroup == true then
		ui.MarketplacePurchaseMessage.Text = "Buy "
			.. itemName
			.. " for " .. tostring(totalPrice)
			.. " Coins?"
	else
		local quantity = typeof(listing) == "table" and listing.Quantity or 0

		ui.MarketplacePurchaseMessage.Text = "Buy "
			.. itemName
			.. " x" .. tostring(quantity)
			.. " for " .. tostring(totalPrice)
			.. " Coins?"
	end

	ui.MarketplacePurchaseConfirmButton.Text = isInFlight and "Buying..." or "Confirm"
	ui.MarketplacePurchaseConfirmButton.Active = not isInFlight
	ui.MarketplacePurchaseConfirmButton.AutoButtonColor = not isInFlight
	ui.MarketplacePurchaseConfirmButton.BackgroundColor3 = isInFlight
		and Color3.fromRGB(155, 160, 155)
		or Color3.fromRGB(70, 150, 255)
	ui.MarketplacePurchaseCancelButton.Active = not isInFlight
	ui.MarketplacePurchaseCancelButton.AutoButtonColor = not isInFlight
end

local function openMarketplacePurchaseModal(listing)
	if typeof(listing) ~= "table" or not getMarketplacePurchaseKey(listing) then
		setStatus("Invalid marketplace listing.")
		return
	end

	if listing.IsOwnListing == true then
		setStatus("You cannot buy your own listing.")
		return
	end

	if tostring(listing.Status or "") ~= "Active" then
		setStatus("This listing is no longer available.")
		return
	end

	marketplacePurchaseListing = listing
	ui.MarketplacePurchaseOverlay.Visible = true
	setMarketplacePurchaseStatus("", false)
	updateMarketplacePurchaseModal()
end

local function removePublicMarketplaceListing(listingId)
	if typeof(listingId) ~= "string" or listingId == "" then
		return
	end

	for index = #latestPublicMarketplaceListings, 1, -1 do
		local listing = latestPublicMarketplaceListings[index]

		if typeof(listing) == "table" and listing.ListingId == listingId then
			table.remove(latestPublicMarketplaceListings, index)
		end
	end
end

local function createItemRow(itemData, layoutOrder)
	local price = 0

	if typeof(itemData.Price) == "number"
		and itemData.Price == itemData.Price
		and itemData.Price >= 0
		and itemData.Price < math.huge then

		price = math.floor(itemData.Price)
	end

	local maxQuantity = 99

	if typeof(itemData.MaxPurchaseQuantity) == "number"
		and itemData.MaxPurchaseQuantity == itemData.MaxPurchaseQuantity
		and itemData.MaxPurchaseQuantity > 0
		and itemData.MaxPurchaseQuantity < math.huge then

		local maxPurchaseQuantity = math.floor(itemData.MaxPurchaseQuantity)

		if maxPurchaseQuantity >= 1 then
			maxQuantity = math.min(maxPurchaseQuantity, 99)
		end
	end

	local selectedQuantity = 1
	local purchaseCurrency = getPurchaseCurrencyForItem(itemData)

	local row = Instance.new("Frame")
	row.Name = tostring(itemData.Id)
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.new(1, -4, 0, 142)
	row.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
	row.BorderSizePixel = 0
	row.Parent = ui.ItemList

	createCorner(row, 10)
	createStroke(row, Color3.fromRGB(220, 220, 220), 1, 0)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Position = UDim2.fromOffset(12, 8)
	nameLabel.Size = UDim2.new(1, -24, 0, 24)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = tostring(itemData.DisplayName or itemData.Id)
	nameLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
	nameLabel.TextSize = 16
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = row

	local descriptionLabel = Instance.new("TextLabel")
	descriptionLabel.Name = "DescriptionLabel"
	descriptionLabel.Position = UDim2.fromOffset(12, 36)
	descriptionLabel.Size = UDim2.new(1, -24, 0, 22)
	descriptionLabel.BackgroundTransparency = 1
	descriptionLabel.Text = tostring(itemData.Description or "Add this item to your Inventory.")
	descriptionLabel.TextColor3 = Color3.fromRGB(95, 95, 95)
	descriptionLabel.TextSize = 12
	descriptionLabel.TextWrapped = true
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.Font = Enum.Font.Gotham
	descriptionLabel.Parent = row

	local metadataParts = {}

	if typeof(itemData.Category) == "string" and itemData.Category ~= "" then
		table.insert(metadataParts, itemData.Category)
	end

	table.insert(metadataParts, "Price: " .. tostring(price) .. " " .. purchaseCurrency)

	if itemData.Featured == true then
		table.insert(metadataParts, "Featured")
	end

	if itemData.IsLimited == true then
		table.insert(metadataParts, "Limited")

		if typeof(itemData.RemainingStock) == "number" then
			table.insert(metadataParts, "Stock: " .. tostring(itemData.RemainingStock))
		elseif typeof(itemData.LimitedQuantity) == "number" then
			table.insert(metadataParts, "Stock: " .. tostring(itemData.LimitedQuantity))
		end
	end

	local metadataLabel = Instance.new("TextLabel")
	metadataLabel.Name = "MetadataLabel"
	metadataLabel.Position = UDim2.fromOffset(12, 62)
	metadataLabel.Size = UDim2.new(1, -24, 0, 20)
	metadataLabel.BackgroundTransparency = 1
	metadataLabel.Text = table.concat(metadataParts, " | ")
	metadataLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
	metadataLabel.TextSize = 12
	metadataLabel.TextXAlignment = Enum.TextXAlignment.Left
	metadataLabel.Font = Enum.Font.GothamMedium
	metadataLabel.Parent = row

	local totalLabel = Instance.new("TextLabel")
	totalLabel.Name = "TotalLabel"
	totalLabel.Position = UDim2.fromOffset(12, 86)
	totalLabel.Size = UDim2.new(1, -24, 0, 20)
	totalLabel.BackgroundTransparency = 1
	totalLabel.TextColor3 = Color3.fromRGB(70, 70, 70)
	totalLabel.TextSize = 14
	totalLabel.TextXAlignment = Enum.TextXAlignment.Left
	totalLabel.Font = Enum.Font.GothamBold
	totalLabel.Parent = row

	local buyButtonText = price > 0 and "Buy" or "Get Item"

	local function createSmallButton(name, text, position, size)
		local button = Instance.new("TextButton")
		button.Name = name
		button.Position = position
		button.Size = size
		button.BackgroundColor3 = Color3.fromRGB(230, 235, 240)
		button.BorderSizePixel = 0
		button.Text = text
		button.TextColor3 = Color3.fromRGB(45, 45, 45)
		button.TextSize = 16
		button.Font = Enum.Font.GothamBold
		button.Parent = row

		createCorner(button, 6)

		return button
	end

	local controlsRight = -12
	local controlsY = 108
	local buyButton = createSmallButton(
		"BuyButton",
		buyButtonText,
		UDim2.new(1, controlsRight - 72, 0, controlsY),
		UDim2.fromOffset(72, 28)
	)
	buyButton.BackgroundColor3 = Color3.fromRGB(70, 150, 255)
	buyButton.TextColor3 = Color3.fromRGB(255, 255, 255)

	local rightButton = createSmallButton(
		"IncreaseQuantityButton",
		">",
		UDim2.new(1, controlsRight - 108, 0, controlsY),
		UDim2.fromOffset(28, 28)
	)

	local quantityLabel = Instance.new("TextLabel")
	quantityLabel.Name = "QuantityLabel"
	quantityLabel.Position = UDim2.new(1, controlsRight - 148, 0, controlsY)
	quantityLabel.Size = UDim2.fromOffset(34, 28)
	quantityLabel.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
	quantityLabel.BorderSizePixel = 0
	quantityLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
	quantityLabel.TextSize = 16
	quantityLabel.Font = Enum.Font.GothamBold
	quantityLabel.Parent = row

	createCorner(quantityLabel, 6)

	local leftButton = createSmallButton(
		"DecreaseQuantityButton",
		"<",
		UDim2.new(1, controlsRight - 184, 0, controlsY),
		UDim2.fromOffset(28, 28)
	)

	local function updateQuantityDisplay()
		quantityLabel.Text = tostring(selectedQuantity)
		totalLabel.Text = "Total: " .. tostring(price * selectedQuantity) .. " " .. purchaseCurrency
		leftButton.Active = selectedQuantity > 1
		leftButton.AutoButtonColor = selectedQuantity > 1
		rightButton.Active = selectedQuantity < maxQuantity
		rightButton.AutoButtonColor = selectedQuantity < maxQuantity
	end

	leftButton.MouseButton1Click:Connect(function()
		if requestInFlight or selectedQuantity <= 1 then
			return
		end

		selectedQuantity -= 1
		updateQuantityDisplay()
	end)

	rightButton.MouseButton1Click:Connect(function()
		if requestInFlight or selectedQuantity >= maxQuantity then
			return
		end

		selectedQuantity += 1
		updateQuantityDisplay()
	end)

	buyButton.MouseButton1Click:Connect(function()
		if requestInFlight then
			return
		end

		requestInFlight = true
		setActivePurchaseButton(buyButton, buyButtonText)
		setStatus("Buying " .. tostring(itemData.DisplayName or itemData.Id) .. " x" .. tostring(selectedQuantity) .. "...")

		furnitureCatalogRequest:FireServer("AddToInventory", {
			ItemId = itemData.Id,
			Quantity = selectedQuantity,
		})
	end)

	updateQuantityDisplay()
end

local function createMarketplaceOfferRow(listing, layoutOrder)
	local quantity = listing.Quantity or 0
	local unitPriceCoins = listing.UnitPriceCoins or 0
	local status = tostring(listing.Status or "Unknown")
	local createdText = formatListingCreatedAt(listing.CreatedAt)
	local listingId = listing.ListingId
	local isOwnListing = listing.IsOwnListing == true
	local isActive = status == "Active"
	local isPurchaseInFlight = marketplacePurchaseInFlightByListingId[listingId] == true

	local row = Instance.new("Frame")
	row.Name = "MarketplaceOfferRow"
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.new(1, -4, 0, 106)
	row.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
	row.BorderSizePixel = 0
	row.Parent = ui.ItemList

	createCorner(row, 10)
	createStroke(row, Color3.fromRGB(220, 220, 220), 1, 0)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "OfferName"
	nameLabel.Position = UDim2.fromOffset(12, 8)
	nameLabel.Size = UDim2.new(1, -120, 0, 22)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = getMarketplaceListingDisplayName(listing)
	nameLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = row

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "OfferPrice"
	priceLabel.Position = UDim2.fromOffset(12, 32)
	priceLabel.Size = UDim2.new(1, -120, 0, 18)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Text = "x" .. tostring(quantity) .. " @ " .. tostring(unitPriceCoins) .. " Coins"
	priceLabel.TextColor3 = Color3.fromRGB(70, 70, 70)
	priceLabel.TextSize = 12
	priceLabel.TextXAlignment = Enum.TextXAlignment.Left
	priceLabel.TextTruncate = Enum.TextTruncate.AtEnd
	priceLabel.Font = Enum.Font.Gotham
	priceLabel.Parent = row

	local sellerLabel = Instance.new("TextLabel")
	sellerLabel.Name = "OfferSeller"
	sellerLabel.Position = UDim2.fromOffset(12, 52)
	sellerLabel.Size = UDim2.new(1, -120, 0, 18)
	sellerLabel.BackgroundTransparency = 1
	sellerLabel.Text = "Seller: " .. getMarketplaceSellerText(listing)
	sellerLabel.TextColor3 = listing.IsOwnListing == true
		and Color3.fromRGB(45, 110, 65)
		or Color3.fromRGB(85, 85, 85)
	sellerLabel.TextSize = 12
	sellerLabel.TextXAlignment = Enum.TextXAlignment.Left
	sellerLabel.TextTruncate = Enum.TextTruncate.AtEnd
	sellerLabel.Font = Enum.Font.Gotham
	sellerLabel.Parent = row

	local listingStatusLabel = Instance.new("TextLabel")
	listingStatusLabel.Name = "OfferStatus"
	listingStatusLabel.Position = UDim2.fromOffset(12, 72)
	listingStatusLabel.Size = UDim2.new(1, -120, 0, 18)
	listingStatusLabel.BackgroundTransparency = 1
	listingStatusLabel.Text = createdText ~= "" and (status .. " | " .. createdText) or status
	listingStatusLabel.TextColor3 = Color3.fromRGB(105, 105, 105)
	listingStatusLabel.TextSize = 11
	listingStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	listingStatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	listingStatusLabel.Font = Enum.Font.GothamMedium
	listingStatusLabel.Parent = row

	local actionButton = Instance.new("TextButton")
	actionButton.Name = isOwnListing and "OwnListingButton" or "BuyMarketplaceListingButton"
	actionButton.AnchorPoint = Vector2.new(1, 0.5)
	actionButton.Position = UDim2.new(1, -12, 0.5, 0)
	actionButton.Size = UDim2.fromOffset(92, 30)
	actionButton.BorderSizePixel = 0
	actionButton.TextSize = 12
	actionButton.Font = Enum.Font.GothamBold
	actionButton.Parent = row

	if isOwnListing then
		actionButton.BackgroundColor3 = Color3.fromRGB(155, 160, 155)
		actionButton.Text = "Your Listing"
		actionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		actionButton.Active = false
		actionButton.AutoButtonColor = false
	elseif isActive then
		actionButton.BackgroundColor3 = isPurchaseInFlight
			and Color3.fromRGB(155, 160, 155)
			or Color3.fromRGB(70, 150, 255)
		actionButton.Text = isPurchaseInFlight and "Buying..." or "Buy"
		actionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		actionButton.Active = not isPurchaseInFlight
		actionButton.AutoButtonColor = not isPurchaseInFlight

		actionButton.MouseButton1Click:Connect(function()
			if not isPurchaseInFlight then
				openMarketplacePurchaseModal(listing)
			end
		end)
	else
		actionButton.BackgroundColor3 = Color3.fromRGB(155, 160, 155)
		actionButton.Text = status
		actionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		actionButton.Active = false
		actionButton.AutoButtonColor = false
	end

	createCorner(actionButton, 7)
end

local function createMarketplaceOfferGroupRow(offerGroup, layoutOrder)
	local templateId = offerGroup.TemplateId
	local displayName = tostring(offerGroup.DisplayName or templateId or "Marketplace item")
	local description = truncateMarketplaceDescription(offerGroup.Description)
	local lowestPrice = offerGroup.LowestUnitPriceCoins
	local averagePrice = offerGroup.AverageSalePriceCoins
	local offersCount = offerGroup.OffersCount or 0
	local isOwnOnly = offerGroup.IsOwnOnly == true
	local purchaseKey = typeof(templateId) == "string" and ("Group:" .. templateId) or nil
	local isPurchaseInFlight = purchaseKey and marketplacePurchaseInFlightByListingId[purchaseKey] == true

	local row = Instance.new("Frame")
	row.Name = "MarketplaceOfferGroupRow"
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.new(1, -4, 0, 116)
	row.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
	row.BorderSizePixel = 0
	row.Parent = ui.ItemList

	createCorner(row, 10)
	createStroke(row, Color3.fromRGB(220, 220, 220), 1, 0)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "OfferName"
	nameLabel.Position = UDim2.fromOffset(12, 8)
	nameLabel.Size = UDim2.new(1, -128, 0, 22)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = displayName
	nameLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
	nameLabel.TextSize = 15
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = row

	local descriptionLabel = Instance.new("TextLabel")
	descriptionLabel.Name = "OfferDescription"
	descriptionLabel.Position = UDim2.fromOffset(12, 32)
	descriptionLabel.Size = UDim2.new(1, -128, 0, 18)
	descriptionLabel.BackgroundTransparency = 1
	descriptionLabel.Text = description ~= "" and description or "Marketplace furniture offer."
	descriptionLabel.TextColor3 = Color3.fromRGB(85, 85, 85)
	descriptionLabel.TextSize = 12
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.TextTruncate = Enum.TextTruncate.AtEnd
	descriptionLabel.Font = Enum.Font.Gotham
	descriptionLabel.Parent = row

	local priceText = typeof(lowestPrice) == "number"
		and ("Price: " .. tostring(lowestPrice) .. " Coins")
		or "Price: -"
	local averageText = typeof(averagePrice) == "number"
		and ("Average: " .. tostring(averagePrice) .. " Coins")
		or "Average: -"
	local offersText = "Offers: " .. tostring(offersCount)

	local metaLabel = Instance.new("TextLabel")
	metaLabel.Name = "OfferMeta"
	metaLabel.Position = UDim2.fromOffset(12, 56)
	metaLabel.Size = UDim2.new(1, -128, 0, 18)
	metaLabel.BackgroundTransparency = 1
	metaLabel.Text = priceText .. "  |  " .. averageText .. "  |  " .. offersText
	metaLabel.TextColor3 = Color3.fromRGB(70, 70, 70)
	metaLabel.TextSize = 12
	metaLabel.TextXAlignment = Enum.TextXAlignment.Left
	metaLabel.TextTruncate = Enum.TextTruncate.AtEnd
	metaLabel.Font = Enum.Font.GothamMedium
	metaLabel.Parent = row

	local ownershipLabel = Instance.new("TextLabel")
	ownershipLabel.Name = "Ownership"
	ownershipLabel.Position = UDim2.fromOffset(12, 78)
	ownershipLabel.Size = UDim2.new(1, -128, 0, 18)
	ownershipLabel.BackgroundTransparency = 1
	ownershipLabel.Text = offerGroup.HasOwnListing == true and "Includes your listing." or tostring(offerGroup.Category or "")
	ownershipLabel.TextColor3 = offerGroup.HasOwnListing == true
		and Color3.fromRGB(45, 110, 65)
		or Color3.fromRGB(105, 105, 105)
	ownershipLabel.TextSize = 11
	ownershipLabel.TextXAlignment = Enum.TextXAlignment.Left
	ownershipLabel.TextTruncate = Enum.TextTruncate.AtEnd
	ownershipLabel.Font = Enum.Font.Gotham
	ownershipLabel.Parent = row

	local buyButton = Instance.new("TextButton")
	buyButton.Name = isOwnOnly and "OwnMarketplaceOfferButton" or "BuyMarketplaceOfferButton"
	buyButton.AnchorPoint = Vector2.new(1, 0.5)
	buyButton.Position = UDim2.new(1, -14, 0.5, 0)
	buyButton.Size = UDim2.fromOffset(104, 34)
	buyButton.BorderSizePixel = 0
	buyButton.TextSize = 12
	buyButton.Font = Enum.Font.GothamBold
	buyButton.Parent = row

	if isOwnOnly then
		buyButton.BackgroundColor3 = Color3.fromRGB(155, 160, 155)
		buyButton.Text = "Your Listing"
		buyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		buyButton.Active = false
		buyButton.AutoButtonColor = false
	else
		buyButton.BackgroundColor3 = isPurchaseInFlight
			and Color3.fromRGB(155, 160, 155)
			or Color3.fromRGB(70, 150, 255)
		buyButton.Text = isPurchaseInFlight and "Buying..." or "Buy"
		buyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		buyButton.Active = not isPurchaseInFlight
		buyButton.AutoButtonColor = not isPurchaseInFlight

		buyButton.MouseButton1Click:Connect(function()
			if isPurchaseInFlight then
				return
			end

			openMarketplacePurchaseModal({
				IsOfferGroup = true,
				ListingId = offerGroup.LowestListingId or purchaseKey,
				TemplateId = templateId,
				DisplayName = displayName,
				Quantity = 1,
				UnitPriceCoins = lowestPrice,
				Status = "Active",
				IsOwnListing = false,
			})
		end)
	end

	createCorner(buyButton, 7)
end

local function createMarketplaceSaleRow(listing, layoutOrder)
	local listingId = listing.ListingId
	local quantity = listing.Quantity or 0
	local unitPriceCoins = listing.UnitPriceCoins or 0
	local status = tostring(listing.Status or "Unknown")
	local isActive = status == "Active"
	local isSoldUnclaimed = isMarketplaceSaleUnclaimed(listing)
	local isClaimedSale = status == "Sold" and listing.ProceedsClaimed == true
	local isCancelInFlight = marketplaceCancelInFlightByListingId[listingId] == true
	local isClaimInFlight = marketplaceClaimInFlightByListingId[listingId] == true
	local claimableCoins = getMarketplaceClaimableCoins(listing)
	local statusColor = getMarketplaceStatusColor(status)
	local hasActionButton = isActive or isSoldUnclaimed

	local row = Instance.new("Frame")
	row.Name = "MarketplaceSaleRow"
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.new(1, -4, 0, 104)
	row.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
	row.BorderSizePixel = 0
	row.Parent = ui.ItemList

	createCorner(row, 10)
	createStroke(row, Color3.fromRGB(220, 220, 220), 1, 0)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "SaleName"
	nameLabel.Position = UDim2.fromOffset(12, 8)
	nameLabel.Size = UDim2.new(1, hasActionButton and -120 or -24, 0, 22)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = getMarketplaceListingDisplayName(listing)
	nameLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = row

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "SalePrice"
	priceLabel.Position = UDim2.fromOffset(12, 32)
	priceLabel.Size = UDim2.new(1, hasActionButton and -120 or -24, 0, 18)
	priceLabel.BackgroundTransparency = 1
	if isSoldUnclaimed and claimableCoins then
		priceLabel.Text = "Claim: " .. tostring(claimableCoins) .. " Coins"
	elseif isClaimedSale then
		priceLabel.Text = "Claimed"
	else
		priceLabel.Text = "x" .. tostring(quantity) .. " @ " .. tostring(unitPriceCoins) .. " Coins"
	end
	priceLabel.TextColor3 = Color3.fromRGB(70, 70, 70)
	priceLabel.TextSize = 12
	priceLabel.TextXAlignment = Enum.TextXAlignment.Left
	priceLabel.TextTruncate = Enum.TextTruncate.AtEnd
	priceLabel.Font = Enum.Font.Gotham
	priceLabel.Parent = row

	local listingStatusLabel = Instance.new("TextLabel")
	listingStatusLabel.Name = "SaleStatus"
	listingStatusLabel.Position = UDim2.fromOffset(12, 54)
	listingStatusLabel.Size = UDim2.new(1, hasActionButton and -120 or -24, 0, 18)
	listingStatusLabel.BackgroundTransparency = 1
	listingStatusLabel.Text = getMarketplaceSaleStatusText(listing)
	listingStatusLabel.TextColor3 = statusColor
	listingStatusLabel.TextSize = 12
	listingStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	listingStatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	listingStatusLabel.Font = Enum.Font.GothamMedium
	listingStatusLabel.Parent = row

	local historyLabel = Instance.new("TextLabel")
	historyLabel.Name = "SaleHistoryNote"
	historyLabel.Position = UDim2.fromOffset(12, 76)
	historyLabel.Size = UDim2.new(1, hasActionButton and -120 or -24, 0, 16)
	historyLabel.BackgroundTransparency = 1
	historyLabel.Text = listing.LegacyPaid == true and "Legacy sale paid." or ""
	historyLabel.TextColor3 = Color3.fromRGB(115, 115, 115)
	historyLabel.TextSize = 10
	historyLabel.TextXAlignment = Enum.TextXAlignment.Left
	historyLabel.TextTruncate = Enum.TextTruncate.AtEnd
	historyLabel.Font = Enum.Font.Gotham
	historyLabel.Parent = row

	if isActive then
		local cancelButton = Instance.new("TextButton")
		cancelButton.Name = "CancelMarketplaceSaleButton"
		cancelButton.AnchorPoint = Vector2.new(1, 0.5)
		cancelButton.Position = UDim2.new(1, -12, 0.5, 0)
		cancelButton.Size = UDim2.fromOffset(92, 30)
		cancelButton.BackgroundColor3 = Color3.fromRGB(160, 70, 70)
		cancelButton.BorderSizePixel = 0
		cancelButton.Text = isCancelInFlight and "Cancelling..." or "Cancel"
		cancelButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		cancelButton.TextSize = 12
		cancelButton.Font = Enum.Font.GothamBold
		cancelButton.Active = not isCancelInFlight
		cancelButton.AutoButtonColor = not isCancelInFlight
		cancelButton.Parent = row

		createCorner(cancelButton, 7)

		cancelButton.MouseButton1Click:Connect(function()
			if ui.CancelMarketplaceSale then
				ui.CancelMarketplaceSale(listingId)
			end
		end)
	elseif isSoldUnclaimed then
		local claimButton = Instance.new("TextButton")
		claimButton.Name = "ClaimMarketplaceSaleButton"
		claimButton.AnchorPoint = Vector2.new(1, 0.5)
		claimButton.Position = UDim2.new(1, -12, 0.5, 0)
		claimButton.Size = UDim2.fromOffset(92, 30)
		claimButton.BackgroundColor3 = isClaimInFlight
			and Color3.fromRGB(155, 160, 155)
			or Color3.fromRGB(70, 150, 255)
		claimButton.BorderSizePixel = 0
		claimButton.Text = isClaimInFlight and "Claiming..." or "Claim"
		claimButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		claimButton.TextSize = 12
		claimButton.Font = Enum.Font.GothamBold
		claimButton.Active = not isClaimInFlight
		claimButton.AutoButtonColor = not isClaimInFlight
		claimButton.Parent = row

		createCorner(claimButton, 7)

		claimButton.MouseButton1Click:Connect(function()
			if ui.ClaimMarketplaceSale then
				ui.ClaimMarketplaceSale(listingId)
			end
		end)
	end
end

local function upsertMySaleListing(listing)
	if typeof(listing) ~= "table"
		or typeof(listing.ListingId) ~= "string"
		or listing.ListingId == "" then

		return
	end

	for index, existingListing in ipairs(latestMySalesListings) do
		if typeof(existingListing) == "table" and existingListing.ListingId == listing.ListingId then
			latestMySalesListings[index] = listing
			return
		end
	end

	table.insert(latestMySalesListings, listing)
end

local function sortMySaleListings()
	table.sort(latestMySalesListings, function(a, b)
		local aUnclaimed = isMarketplaceSaleUnclaimed(a)
		local bUnclaimed = isMarketplaceSaleUnclaimed(b)

		if aUnclaimed ~= bUnclaimed then
			return aUnclaimed
		end

		local aStatus = tostring(a and a.Status or "")
		local bStatus = tostring(b and b.Status or "")

		if aStatus ~= bStatus then
			if aStatus == "Active" then
				return true
			end

			if bStatus == "Active" then
				return false
			end
		end

		local aTime = typeof(a) == "table" and (a.UpdatedAt or a.CreatedAt or 0) or 0
		local bTime = typeof(b) == "table" and (b.UpdatedAt or b.CreatedAt or 0) or 0

		if aStatus == "Sold" then
			aTime = a.SoldAt or a.ClaimedAt or a.UpdatedAt or a.CreatedAt or 0
		end

		if bStatus == "Sold" then
			bTime = b.SoldAt or b.ClaimedAt or b.UpdatedAt or b.CreatedAt or 0
		end

		if aTime == bTime then
			local aId = typeof(a) == "table" and a.ListingId or ""
			local bId = typeof(b) == "table" and b.ListingId or ""

			return tostring(aId or "") > tostring(bId or "")
		end

		return aTime > bTime
	end)
end

renderMarketplace = function()
	if catalogViewMode ~= CATALOG_VIEW.MARKETPLACE then
		return
	end

	updateCatalogChrome()
	clearItemRows()

	if marketplaceViewMode == MARKETPLACE_VIEW.INSTRUCTIONS then
		renderMarketplaceInstructions()
		return
	end

	if marketplaceViewMode == MARKETPLACE_VIEW.OFFERS then
		if marketplacePublicListingsInFlight then
			setStatus("Loading marketplace offers...")
		elseif #latestMarketplaceOfferGroups == 0 then
			setStatus("Browse Marketplace offers.")
			createEmptyCatalogState("No active offers right now.")
		else
			setStatus("Browse Marketplace offers.")
		end

		for index, offerGroup in ipairs(latestMarketplaceOfferGroups) do
			if typeof(offerGroup) == "table" then
				createMarketplaceOfferGroupRow(offerGroup, index)
			end
		end
	elseif marketplaceViewMode == MARKETPLACE_VIEW.MY_LISTINGS then
		sortMySaleListings()
		local activeListings = {}

		for _, listing in ipairs(latestMySalesListings) do
			if typeof(listing) == "table" and tostring(listing.Status or "") == "Active" then
				table.insert(activeListings, listing)
			end
		end

		if marketplaceMySalesInFlight then
			setStatus("Loading active marketplace listings...")
		elseif #activeListings == 0 then
			setStatus("Manage your active marketplace listings.")
			createEmptyCatalogState("No active listings yet.")
		else
			setStatus("Manage your active marketplace listings.")
		end

		for index, listing in ipairs(activeListings) do
			createMarketplaceSaleRow(listing, index)
		end
	elseif marketplaceViewMode == MARKETPLACE_VIEW.MY_SALES then
		sortMySaleListings()
		local visibleSales = {}

		for _, listing in ipairs(latestMySalesListings) do
			if typeof(listing) == "table"
				and tostring(listing.Status or "") == "Sold"
				and shouldShowMarketplaceSaleHistory(listing) then

				table.insert(visibleSales, listing)
			end
		end

		if marketplaceMySalesInFlight then
			setStatus("")
		elseif #visibleSales == 0 then
			setStatus("")
			createEmptyCatalogState("No marketplace sales yet.")
		else
			setStatus("")
		end

		for index, listing in ipairs(visibleSales) do
			createMarketplaceSaleRow(listing, index)
		end
	end

	task.defer(function()
		ui.ItemList.CanvasSize = UDim2.fromOffset(
			0,
			ui.ListLayout.AbsoluteContentSize.Y + 20
		)
	end)
end

renderCatalog = function(items)
	latestCatalogItems = items or {}
	if catalogViewMode ~= CATALOG_VIEW.SHOP then
		return
	end

	updateCatalogChrome()
	clearItemRows()
	updateCategoryTabs(latestCatalogItems)

	local visibleItems = {}

	for _, itemData in ipairs(latestCatalogItems) do
		if itemMatchesSelectedCategory(itemData) then
			table.insert(visibleItems, itemData)
		end
	end

	if #latestCatalogItems == 0 then
		setStatus("No shop items found. Check ReplicatedStorage/FurnitureTemplates.")
		createEmptyCatalogState("No shop items found.")
	elseif #visibleItems == 0 then
		setStatus("No items in " .. selectedCategory .. ".")
		createEmptyCatalogState("No items in " .. selectedCategory .. ".")
	else
		setStatus("Select an item to buy it with Dollars.")
	end

	for index, itemData in ipairs(visibleItems) do
		createItemRow(itemData, index)
	end

	task.defer(function()
		ui.ItemList.CanvasSize = UDim2.fromOffset(
			0,
			ui.ListLayout.AbsoluteContentSize.Y + 20
		)
	end)
end

local function scheduleQueuedMarketplaceOffersRefresh(delaySeconds)
	if publicMarketplaceQueuedRefreshScheduled then
		return
	end

	publicMarketplaceQueuedRefreshScheduled = true

	task.delay(math.max(delaySeconds or 0, 0), function()
		publicMarketplaceQueuedRefreshScheduled = false

		if publicMarketplaceQueuedRefresh and requestMarketplaceOffers then
			requestMarketplaceOffers({
				FromQueue = true,
			})
		end
	end)
end

local function scheduleQueuedMySalesRefresh(delaySeconds)
	if mySalesQueuedRefreshScheduled then
		return
	end

	mySalesQueuedRefreshScheduled = true

	task.delay(math.max(delaySeconds or 0, 0), function()
		mySalesQueuedRefreshScheduled = false

		if mySalesQueuedRefresh and requestMarketplaceMySales then
			requestMarketplaceMySales({
				FromQueue = true,
			})
		end
	end)
end

requestMarketplaceOffers = function(options)
	local queueIfBlocked = typeof(options) == "table" and options.Queue == true
	local fromQueue = typeof(options) == "table" and options.FromQueue == true

	if marketplacePublicListingsInFlight then
		if queueIfBlocked then
			publicMarketplaceQueuedRefresh = true
		end

		renderMarketplace()
		return
	end

	local now = os.clock()
	local cooldownRemaining = MARKETPLACE_REQUEST_COOLDOWN_SECONDS - (now - marketplaceLastRequestAt)

	if cooldownRemaining > 0 then
		if queueIfBlocked or fromQueue then
			publicMarketplaceQueuedRefresh = true
			scheduleQueuedMarketplaceOffersRefresh(cooldownRemaining)
		else
			setStatus("Please wait a moment.")
			renderMarketplace()
		end

		return
	end

	publicMarketplaceQueuedRefresh = false
	marketplacePublicListingsInFlight = true
	marketplaceLastRequestAt = now
	publicMarketplaceLastRequestAt = now
	renderMarketplace()
	marketplaceRequest:FireServer("GetMarketplaceOfferGroups", {
		SearchText = ui.MarketplaceSearchBox.Text,
		MaxResults = 50,
	})

	local requestStartedAt = publicMarketplaceLastRequestAt

	task.delay(REQUEST_TIMEOUT_SECONDS, function()
		if marketplacePublicListingsInFlight and publicMarketplaceLastRequestAt == requestStartedAt then
			marketplacePublicListingsInFlight = false
			setStatus("Marketplace offers request timed out.")
			renderMarketplace()
		end
	end)
end

requestMarketplaceMySales = function(options)
	local queueIfBlocked = typeof(options) == "table" and options.Queue == true
	local fromQueue = typeof(options) == "table" and options.FromQueue == true

	if marketplaceMySalesInFlight then
		if queueIfBlocked then
			mySalesQueuedRefresh = true
		end

		renderMarketplace()
		return
	end

	local now = os.clock()
	local cooldownRemaining = MARKETPLACE_REQUEST_COOLDOWN_SECONDS - (now - marketplaceLastRequestAt)

	if cooldownRemaining > 0 then
		if queueIfBlocked or fromQueue then
			mySalesQueuedRefresh = true
			scheduleQueuedMySalesRefresh(cooldownRemaining)
		else
			setStatus("Please wait a moment.")
			renderMarketplace()
		end

		return
	end

	mySalesQueuedRefresh = false
	marketplaceMySalesInFlight = true
	marketplaceLastRequestAt = now
	mySalesLastRequestAt = now
	renderMarketplace()
	marketplaceRequest:FireServer("GetMyListings")

	local requestStartedAt = mySalesLastRequestAt

	task.delay(REQUEST_TIMEOUT_SECONDS, function()
		if marketplaceMySalesInFlight and mySalesLastRequestAt == requestStartedAt then
			marketplaceMySalesInFlight = false
			setStatus(marketplaceViewMode == MARKETPLACE_VIEW.MY_LISTINGS
				and "Marketplace listings request timed out."
				or "Marketplace sales request timed out.")
			renderMarketplace()
		end
	end)
end

ui.CancelMarketplaceSale = function(listingId)
	if typeof(listingId) ~= "string" or listingId == "" then
		setStatus("Invalid marketplace listing.")
		return
	end

	if marketplaceCancelInFlightByListingId[listingId] then
		return
	end

	local now = os.clock()
	local cooldownRemaining = MARKETPLACE_REQUEST_COOLDOWN_SECONDS - (now - marketplaceLastRequestAt)

	if cooldownRemaining > 0 then
		setStatus("Please wait a moment.")
		renderMarketplace()
		return
	end

	marketplaceCancelInFlightByListingId[listingId] = true
	marketplaceLastRequestAt = now
	renderMarketplace()
	marketplaceRequest:FireServer("CancelListing", {
		ListingId = listingId,
	})

	task.delay(REQUEST_TIMEOUT_SECONDS, function()
		if marketplaceCancelInFlightByListingId[listingId] then
			marketplaceCancelInFlightByListingId[listingId] = nil
			setStatus("Cancel listing request timed out.")
			renderMarketplace()
		end
	end)
end

ui.ClaimMarketplaceSale = function(listingId)
	if typeof(listingId) ~= "string" or listingId == "" then
		setStatus("Invalid marketplace sale.")
		return
	end

	if marketplaceClaimInFlightByListingId[listingId] then
		return
	end

	local now = os.clock()
	local cooldownRemaining = MARKETPLACE_REQUEST_COOLDOWN_SECONDS - (now - marketplaceLastRequestAt)

	if cooldownRemaining > 0 then
		setStatus("Please wait a moment.")
		renderMarketplace()
		return
	end

	marketplaceClaimInFlightByListingId[listingId] = true
	marketplaceLastRequestAt = now
	renderMarketplace()
	marketplaceRequest:FireServer("ClaimSale", {
		ListingId = listingId,
	})

	task.delay(REQUEST_TIMEOUT_SECONDS, function()
		if marketplaceClaimInFlightByListingId[listingId] then
			marketplaceClaimInFlightByListingId[listingId] = nil
			setStatus("Claim sale request timed out.")
			renderMarketplace()
		end
	end)
end

ui.RequestMarketplacePurchase = function()
	if marketplacePurchaseRequestInFlight then
		return
	end

	local listing = marketplacePurchaseListing

	if typeof(listing) ~= "table" or not getMarketplacePurchaseKey(listing) then
		setMarketplacePurchaseStatus("Invalid marketplace listing.", true)
		return
	end

	if listing.IsOwnListing == true then
		setMarketplacePurchaseStatus("You cannot buy your own listing.", true)
		return
	end

	if tostring(listing.Status or "") ~= "Active" then
		setMarketplacePurchaseStatus("This listing is no longer available.", true)
		return
	end

	local purchaseKey = getMarketplacePurchaseKey(listing)

	if marketplacePurchaseInFlightByListingId[purchaseKey] then
		return
	end

	local now = os.clock()
	local cooldownRemaining = MARKETPLACE_REQUEST_COOLDOWN_SECONDS - (now - marketplaceLastRequestAt)

	if cooldownRemaining > 0 then
		setMarketplacePurchaseStatus("Please wait a moment.", true)
		return
	end

	marketplacePurchaseRequestSerial += 1
	pendingPurchaseRequestId = tostring(marketplacePurchaseRequestSerial)
	pendingPurchaseListingId = purchaseKey
	pendingPurchaseTemplateId = listing.TemplateId
	marketplacePurchaseRequestInFlight = true
	marketplacePurchaseInFlightByListingId[purchaseKey] = true
	marketplaceLastRequestAt = now
	setMarketplacePurchaseStatus("Purchasing...", false)
	updateMarketplacePurchaseModal()
	renderMarketplace()

	if listing.IsOfferGroup == true then
		marketplaceRequest:FireServer("PurchaseMarketplaceOffer", {
			TemplateId = listing.TemplateId,
			RequestId = pendingPurchaseRequestId,
		})
	else
		marketplaceRequest:FireServer("PurchaseListing", {
			ListingId = listing.ListingId,
			RequestId = pendingPurchaseRequestId,
		})
	end

	local requestId = pendingPurchaseRequestId

	task.delay(REQUEST_TIMEOUT_SECONDS, function()
		if marketplacePurchaseRequestInFlight and pendingPurchaseRequestId == requestId then
			marketplacePurchaseRequestInFlight = false

			if pendingPurchaseListingId then
				marketplacePurchaseInFlightByListingId[pendingPurchaseListingId] = nil
			end

			pendingPurchaseRequestId = nil
			pendingPurchaseListingId = nil
			pendingPurchaseTemplateId = nil
			setMarketplacePurchaseStatus("Purchase request timed out.", true)
			updateMarketplacePurchaseModal()
			renderMarketplace()
		end
	end)
end

selectCatalogPage = function(page)
	selectedCatalogPage = page or CATALOG_PAGE.FRONT

	if selectedCatalogPage == CATALOG_PAGE.FRONT then
		catalogViewMode = CATALOG_VIEW.FRONT_PAGE
		renderFrontPage()
		return
	end

	if selectedCatalogPage == CATALOG_PAGE.COINS then
		catalogViewMode = CATALOG_VIEW.PLACEHOLDER
		placeholderCatalogPage = selectedCatalogPage
		renderCoinShopPage()
		return
	end

	if selectedCatalogPage == CATALOG_PAGE.DOLLARS_INFO then
		catalogViewMode = CATALOG_VIEW.PLACEHOLDER
		placeholderCatalogPage = selectedCatalogPage
		renderDollarsInfoPage()
		return
	end

	if selectedCatalogPage == CATALOG_PAGE.FURNITURE_SHOP then
		catalogViewMode = CATALOG_VIEW.SHOP
		selectedCategory = "All"
		rebuildCatalogNavigation()
		renderCatalog(latestCatalogItems)

		if #latestCatalogItems == 0 then
			setStatus("Loading catalog furniture...")
			furnitureCatalogRequest:FireServer("GetCatalog", {})
		end

		return
	end

	local shopCategory = getShopCategoryForPage(selectedCatalogPage)

	if shopCategory then
		catalogNavExpanded.Furniture = true
		catalogViewMode = CATALOG_VIEW.SHOP
		selectedCategory = shopCategory
		rebuildCatalogNavigation()
		renderCatalog(latestCatalogItems)

		if #latestCatalogItems == 0 then
			setStatus("Loading catalog furniture...")
			furnitureCatalogRequest:FireServer("GetCatalog", {})
		end

		return
	end

	if selectedCatalogPage == CATALOG_PAGE.ROOM_FINISHES_FLOORS then
		catalogNavExpanded.RoomFinishes = true
		catalogViewMode = CATALOG_VIEW.ROOM_FINISHES
		rebuildCatalogNavigation()
		ui.FloorFinishes.renderPage()

		if #ui.FloorFinishes.Offers == 0 then
			ui.FloorFinishes.requestOffers({
				SetStatus = true,
			})
		else
			ui.FloorFinishes.requestOffers({
				SetStatus = false,
			})
		end

		return
	end

	if selectedCatalogPage == CATALOG_PAGE.MARKETPLACE_OFFERS then
		catalogNavExpanded.Marketplace = true
		catalogViewMode = CATALOG_VIEW.MARKETPLACE
		marketplaceViewMode = MARKETPLACE_VIEW.OFFERS
		rebuildCatalogNavigation()
		renderMarketplace()
		requestMarketplaceOffers({
			Queue = true,
		})
		return
	end

	if selectedCatalogPage == CATALOG_PAGE.MARKETPLACE_MY_LISTINGS then
		catalogNavExpanded.Marketplace = true
		catalogViewMode = CATALOG_VIEW.MARKETPLACE
		marketplaceViewMode = MARKETPLACE_VIEW.MY_LISTINGS
		rebuildCatalogNavigation()
		renderMarketplace()
		requestMarketplaceMySales({
			Queue = true,
		})
		return
	end

	if selectedCatalogPage == CATALOG_PAGE.MARKETPLACE_MY_SALES then
		catalogNavExpanded.Marketplace = true
		catalogViewMode = CATALOG_VIEW.MARKETPLACE
		marketplaceViewMode = MARKETPLACE_VIEW.MY_SALES
		rebuildCatalogNavigation()
		renderMarketplace()
		requestMarketplaceMySales({
			Queue = true,
		})
		return
	end

	if selectedCatalogPage == CATALOG_PAGE.MARKETPLACE_INSTRUCTIONS then
		catalogNavExpanded.Marketplace = true
		catalogViewMode = CATALOG_VIEW.MARKETPLACE
		marketplaceViewMode = MARKETPLACE_VIEW.INSTRUCTIONS
		rebuildCatalogNavigation()
		renderMarketplaceInstructions()
		return
	end

	catalogViewMode = CATALOG_VIEW.PLACEHOLDER
	placeholderCatalogPage = selectedCatalogPage
	renderPlaceholderPage(selectedCatalogPage)
end

ui.UpdateOpenButton = function()
	ui.OpenButton.Visible = false
end

ui.ShopSectionButton.MouseButton1Click:Connect(function()
	selectCatalogPage(CATALOG_PAGE.FURNITURE_SHOP)
end)

ui.MarketplaceSectionButton.MouseButton1Click:Connect(function()
	selectCatalogPage(CATALOG_PAGE.MARKETPLACE_OFFERS)
end)

ui.MarketplaceOffersButton.MouseButton1Click:Connect(function()
	if marketplaceViewMode == MARKETPLACE_VIEW.OFFERS then
		return
	end

	selectCatalogPage(CATALOG_PAGE.MARKETPLACE_OFFERS)
end)

ui.MarketplaceMySalesButton.MouseButton1Click:Connect(function()
	if marketplaceViewMode == MARKETPLACE_VIEW.MY_SALES then
		return
	end

	selectCatalogPage(CATALOG_PAGE.MARKETPLACE_MY_SALES)
end)

ui.MarketplaceRefreshButton.MouseButton1Click:Connect(function()
	if catalogViewMode ~= CATALOG_VIEW.MARKETPLACE then
		return
	end

	if marketplaceViewMode == MARKETPLACE_VIEW.OFFERS then
		requestMarketplaceOffers({
			Queue = true,
		})
	elseif marketplaceViewMode == MARKETPLACE_VIEW.MY_LISTINGS
		or marketplaceViewMode == MARKETPLACE_VIEW.MY_SALES then

		requestMarketplaceMySales({
			Queue = true,
		})
	end
end)

ui.MarketplaceSearchBox.FocusLost:Connect(function(enterPressed)
	if enterPressed
		and catalogViewMode == CATALOG_VIEW.MARKETPLACE
		and marketplaceViewMode == MARKETPLACE_VIEW.OFFERS then

		requestMarketplaceOffers({
			Queue = true,
		})
	end
end)

ui.MarketplacePurchaseCancelButton.MouseButton1Click:Connect(closeMarketplacePurchaseModal)

ui.MarketplacePurchaseConfirmButton.MouseButton1Click:Connect(function()
	if ui.RequestMarketplacePurchase then
		ui.RequestMarketplacePurchase()
	end
end)

ui.CatalogGetCoinsButton.MouseButton1Click:Connect(function()
	if selectCatalogPage then
		selectCatalogPage(CATALOG_PAGE.COINS)
	end
end)

ui.CatalogHowToGetButton.MouseButton1Click:Connect(function()
	if selectCatalogPage then
		selectCatalogPage(CATALOG_PAGE.DOLLARS_INFO)
	end
end)

local function openCatalogPanel()
	if not shouldShowCatalogButton() then
		return
	end

	catalogNavExpanded.Furniture = false
	catalogNavExpanded.Marketplace = false
	rebuildCatalogNavigation()
	setPanelVisible(true)
	selectCatalogPage(CATALOG_PAGE.FRONT)
	requestCatalogCurrencySnapshot(true)
	furnitureCatalogRequest:FireServer("GetCatalog", {})
end

ui.OpenButton.MouseButton1Click:Connect(openCatalogPanel)
openCatalog.Event:Connect(openCatalogPanel)

ui.CloseButton.MouseButton1Click:Connect(function()
	setPanelVisible(false)
end)

majorMenuOpened.Event:Connect(function(menuName)
	if menuName == MENU_NAME then
		return
	end

	if ui.Panel.Visible then
		setPanelVisible(false)
	end

	if placingItemData then
		ui.DestroyCatalogPlacementPreview()
	end
end)

closeMajorMenus.Event:Connect(function()
	if ui.Panel.Visible then
		setPanelVisible(false)
	end

	if placingItemData then
		ui.DestroyCatalogPlacementPreview()
	end
end)

majorMenuStateChanged.Event:Connect(function(isOpen, menuName)
	setLocalMajorMenuState(isOpen == true, menuName)
end)

startInventoryPlacement.Event:Connect(function(itemData)
	if typeof(itemData) ~= "table" then
		return
	end

	if requestInFlight then
		return
	end

	if not canContinueInventoryPlacement() then

		setStatus("Enter Edit Mode to place furniture.")
		return
	end

	ui.placementStartup.StartId += 1

	local startId = ui.placementStartup.StartId

	setStatus("Preparing room...")

	task.spawn(function()
		local roomContext, waitMessage =
			ui.placementStartup.waitForPlacementRoomContext(2.5, startId)

		if ui.placementStartup.StartId ~= startId then
			ui.placementStartup.debug("stale placement start ignored", startId)
			return
		end

		if not roomContext then
			if waitMessage ~= "stale" then
				setStatus("Room is still loading. Try again.")
			end

			return
		end

		if not canContinueInventoryPlacement() then
			setStatus("Enter Edit Mode to place furniture.")
			return
		end

		createCatalogPlacementPreview(itemData, roomContext)
	end)
end)

RunService.RenderStepped:Connect(updateCatalogPlacementPreview)

mouse.Button1Down:Connect(function()
	if not placingItemData then
		return
	end

	confirmCatalogPlacement()
end)

currencyLocalDelta.Event:Connect(applyCatalogCurrencyLocalDelta)

currencyResult.OnClientEvent:Connect(function(response)
	if typeof(response) ~= "table" then
		return
	end

	local kind = response.Kind

	if kind == "Currencies" or kind == "Currency" or kind == "Coins" then
		catalogCurrency.RequestInFlight = false
	end

	if response.Success ~= true then
		return
	end

	if kind == "Currencies" then
		applyCatalogCurrencySnapshot(response.Currencies)
	elseif kind == "Currency" then
		applyCatalogCurrencyLocalDelta({
			CurrencyKey = response.CurrencyKey,
			Balance = response.Balance,
		})
	elseif kind == "Coins" then
		applyCatalogCurrencyLocalDelta({
			CurrencyKey = "Coins",
			Balance = response.Coins,
		})
	end
end)

marketplaceResult.OnClientEvent:Connect(function(response)
	if typeof(response) ~= "table" then
		return
	end

	local kind = response.Kind
	local success = response.Success == true
	local message = getMarketplaceWaitMessage(response.Message)

	if kind == "MarketplaceOfferGroups" or kind == "GetMarketplaceOfferGroups" then
		marketplacePublicListingsInFlight = false
		local shouldRunQueuedRefresh = publicMarketplaceQueuedRefresh == true

		if success then
			latestMarketplaceOfferGroups = {}

			if typeof(response.Offers) == "table" then
				for _, offerGroup in ipairs(response.Offers) do
					if typeof(offerGroup) == "table" and typeof(offerGroup.TemplateId) == "string" then
						table.insert(latestMarketplaceOfferGroups, offerGroup)
					end
				end
			end

			message = ""
		else
			shouldRunQueuedRefresh = false
			publicMarketplaceQueuedRefresh = false

			if message == "" then
				message = "Could not load marketplace offers."
			end
		end

		if catalogViewMode == CATALOG_VIEW.MARKETPLACE
			and marketplaceViewMode == MARKETPLACE_VIEW.OFFERS then

			renderMarketplace()

			if message ~= "" then
				setStatus(message)
			end
		else
			updateCatalogChrome()
		end

		if shouldRunQueuedRefresh then
			scheduleQueuedMarketplaceOffersRefresh(
				MARKETPLACE_REQUEST_COOLDOWN_SECONDS - (os.clock() - publicMarketplaceLastRequestAt)
			)
		end

		return
	end

	if kind == "PublicListings" or kind == "GetPublicListings" then
		marketplacePublicListingsInFlight = false

		if success then
			latestPublicMarketplaceListings = {}

			if typeof(response.Listings) == "table" then
				for _, listing in ipairs(response.Listings) do
					if typeof(listing) == "table" and tostring(listing.Status or "") == "Active" then
						table.insert(latestPublicMarketplaceListings, listing)
					end
				end
			end
		else
			publicMarketplaceQueuedRefresh = false
		end

		if catalogViewMode == CATALOG_VIEW.MARKETPLACE
			and marketplaceViewMode == MARKETPLACE_VIEW.OFFERS then

			renderMarketplace()

			if message ~= "" then
				setStatus(message)
			end
		else
			updateCatalogChrome()
		end

		return
	end

	if kind == "MyListings" or kind == "GetMyListings" then
		marketplaceMySalesInFlight = false
		local shouldRunQueuedRefresh = mySalesQueuedRefresh == true

		if success then
			latestMySalesListings = typeof(response.Listings) == "table"
				and response.Listings
				or {}
			sortMySaleListings()
			message = ""
		else
			shouldRunQueuedRefresh = false
			mySalesQueuedRefresh = false

			if message == "" then
				message = marketplaceViewMode == MARKETPLACE_VIEW.MY_LISTINGS
					and "Could not load marketplace listings."
					or "Could not load marketplace sales."
			end
		end

		if catalogViewMode == CATALOG_VIEW.MARKETPLACE
			and (
				marketplaceViewMode == MARKETPLACE_VIEW.MY_LISTINGS
				or marketplaceViewMode == MARKETPLACE_VIEW.MY_SALES
			) then

			renderMarketplace()

			if message ~= "" then
				setStatus(message)
			end
		else
			updateCatalogChrome()
		end

		if shouldRunQueuedRefresh then
			scheduleQueuedMySalesRefresh(
				MARKETPLACE_REQUEST_COOLDOWN_SECONDS - (os.clock() - mySalesLastRequestAt)
			)
		end

		return
	end

	if kind == "ListingSold" then
		local listing = response.Listing
		local listingId = nil

		if typeof(listing) == "table" then
			listingId = listing.ListingId
			upsertMySaleListing(listing)
		end

		if typeof(listingId) == "string" then
			removePublicMarketplaceListing(listingId)
		end

		if catalogViewMode == CATALOG_VIEW.MARKETPLACE then
			renderMarketplace()
			setStatus(message ~= "" and message or "Your listing sold.")
		else
			updateCatalogChrome()
		end

		if requestMarketplaceMySales then
			task.delay(0.5, function()
				requestMarketplaceMySales({
					Queue = true,
				})
			end)
		end

		if requestMarketplaceOffers then
			task.delay(0.5, function()
				requestMarketplaceOffers({
					Queue = true,
				})
			end)
		end

		return
	end

	if kind == "PurchaseListing" or kind == "PurchaseMarketplaceOffer" then
		local responseRequestId = response.RequestId

		if pendingPurchaseRequestId
			and responseRequestId ~= nil
			and tostring(responseRequestId) ~= pendingPurchaseRequestId then

			return
		end

		local listing = response.Listing
		local pendingPurchaseKey = pendingPurchaseListingId
		local listingId = pendingPurchaseListingId
		local templateId = response.TemplateId or pendingPurchaseTemplateId

		if typeof(listing) == "table" then
			listingId = listing.ListingId or listingId
			templateId = listing.TemplateId
		elseif typeof(marketplacePurchaseListing) == "table" then
			templateId = marketplacePurchaseListing.TemplateId
		end

		marketplacePurchaseRequestInFlight = false

		if typeof(pendingPurchaseKey) == "string" then
			marketplacePurchaseInFlightByListingId[pendingPurchaseKey] = nil
		end

		if typeof(listingId) == "string" then
			marketplacePurchaseInFlightByListingId[listingId] = nil
		end

		pendingPurchaseRequestId = nil
		pendingPurchaseListingId = nil
		pendingPurchaseTemplateId = nil

		if success then
			if typeof(listingId) == "string" then
				removePublicMarketplaceListing(listingId)
			end

			fireInventoryLocalDeltaFromMarketplaceDetails(templateId, response.InventoryDetails)

			if typeof(response.NewCoinBalance) == "number" then
				currencyLocalDelta:Fire({
					CurrencyKey = response.CurrencyKey or "Coins",
					Balance = response.NewCoinBalance,
				})
			end

			inventoryRefreshRequested:Fire({
				Reason = "MarketplacePurchase",
				Force = true,
			})
			currencyRefreshRequested:Fire()
			ui.MarketplacePurchaseOverlay.Visible = false
			marketplacePurchaseListing = nil
			setMarketplacePurchaseStatus("", false)
			renderMarketplace()
			setStatus("Purchase successful. Item added to your Inventory.")

			if requestMarketplaceOffers then
				task.delay(0.5, function()
					requestMarketplaceOffers({
						Queue = true,
					})
				end)
			end

			if requestMarketplaceMySales
				and catalogViewMode == CATALOG_VIEW.MARKETPLACE
				and marketplaceViewMode == MARKETPLACE_VIEW.MY_SALES then

				task.delay(0.5, function()
					requestMarketplaceMySales({
						Queue = true,
					})
				end)
			end
		else
			local errorMessage = message ~= "" and message or "Could not complete purchase."

			if ui.MarketplacePurchaseOverlay.Visible then
				setMarketplacePurchaseStatus(errorMessage, true)
				updateMarketplacePurchaseModal()
				renderMarketplace()
			else
				renderMarketplace()
				setStatus(errorMessage)
			end
		end

		return
	end

	if kind == "ClaimSale" then
		marketplaceClaimInFlightByListingId = {}

		local listing = response.Listing

		if typeof(listing) == "table" then
			upsertMySaleListing(listing)
		end

		if success then
			if typeof(response.NewCoinBalance) == "number" then
				currencyLocalDelta:Fire({
					CurrencyKey = response.CurrencyKey or "Coins",
					Balance = response.NewCoinBalance,
				})
			elseif typeof(response.ClaimedCoins) == "number" then
				currencyLocalDelta:Fire({
					CurrencyKey = response.CurrencyKey or "Coins",
					Amount = response.ClaimedCoins,
					Reason = "MarketplaceClaim",
				})
			end

			currencyRefreshRequested:Fire()
			setStatus("Sale claimed.")

			if requestMarketplaceMySales then
				task.delay(0.4, function()
					requestMarketplaceMySales({
						Queue = true,
					})
				end)
			end
		else
			setStatus(message ~= "" and message or "Could not claim sale.")
		end

		if catalogViewMode == CATALOG_VIEW.MARKETPLACE then
			renderMarketplace()
		else
			updateCatalogChrome()
		end

		return
	end

	if kind == "CancelListing" then
		marketplaceCancelInFlightByListingId = {}

		local listing = response.Listing
		local templateId = nil

		if typeof(listing) == "table" then
			templateId = listing.TemplateId
			upsertMySaleListing(listing)
		end

		if success then
			fireInventoryLocalDeltaFromMarketplaceDetails(templateId, response.InventoryDetails)
			inventoryRefreshRequested:Fire({
				Reason = "MarketplaceCancelListing",
				Force = true,
			})
			setStatus("Listing cancelled.")

			if requestMarketplaceMySales then
				task.delay(0.4, function()
					requestMarketplaceMySales({
						Queue = true,
					})
				end)
			end

			if requestMarketplaceOffers then
				task.delay(0.5, function()
					requestMarketplaceOffers({
						Queue = true,
					})
				end)
			end
		else
			setStatus(message ~= "" and message or "Could not cancel listing.")
		end

		if catalogViewMode == CATALOG_VIEW.MARKETPLACE then
			renderMarketplace()
		end
	end
end)

furnitureCatalogResult.OnClientEvent:Connect(function(response)
	if typeof(response) ~= "table" then
		return
	end

	local kind = response.Kind
	local success = response.Success == true
	local message = tostring(response.Message or "")
	local data = response.Data

	if kind == "Catalog" then
		if success and typeof(data) == "table" and typeof(data.Items) == "table" then
			renderCatalog(data.Items)
		else
			renderCatalog({})

			if catalogViewMode == CATALOG_VIEW.SHOP then
				setStatus(message)
			end
		end

		return
	end

	if kind == "GetFloorStyleOffers" then
		ui.FloorFinishes.RequestInFlight = false

		local styles = response.Styles

		if typeof(data) == "table" and typeof(data.Styles) == "table" then
			styles = data.Styles
		end

		if success and typeof(styles) == "table" then
			ui.FloorFinishes.Offers = styles
		elseif not success then
			ui.FloorFinishes.Offers = {}
		end

		if catalogViewMode == CATALOG_VIEW.ROOM_FINISHES then
			ui.FloorFinishes.renderPage()

			if not success then
				setStatus(message ~= "" and message or "Could not load floor finishes.")
			end
		end

		return
	end

	if kind == "PurchaseFloorStyle" then
		if catalogViewMode == CATALOG_VIEW.ROOM_FINISHES then
			ui.FloorFinishes.renderPage()
			setStatus(message ~= "" and message or "Preview and apply floors from Room Settings.")
		end

		return
	end

	if kind == "AddToInventory" then
		requestInFlight = false
		resetActivePurchaseButton()

		if message == "Slow down before getting another item." then
			message = "Please wait a moment."
		end

		setStatus(message)
		fireCurrencyLocalDeltaFromAddToInventoryResult(response)

		if success then
			fireInventoryLocalDeltaFromAddToInventoryResult(response)
			inventoryRefreshRequested:Fire()
			currencyRefreshRequested:Fire()
		end

		return
	end

	if kind == "PlaceItem" or kind == "PlaceInventoryItem" then
		local placedFromInventory = kind == "PlaceInventoryItem"
			or (typeof(data) == "table" and data.Source == "Inventory")

		ui.DestroyCatalogPlacementPreview()
		setStatus(message)

		if success then
			if placedFromInventory then
				fireInventoryLocalDeltaFromPlacementData(data)
				inventoryRefreshRequested:Fire()
			else
				-- Refresh in case future catalog limits hide or update items.
				furnitureCatalogRequest:FireServer("GetCatalog", {})
			end
		elseif placedFromInventory then
			inventoryRefreshRequested:Fire({
				Reason = "PlaceInventoryItemFailed",
				Force = true,
			})
		end

		return
	end

	requestInFlight = false
	setStatus(message)
end)

ui.HandleCatalogVisibilityChanged = function()
	local canShowShop = shouldShowCatalogButton()

	if ui.Panel.Visible and not canShowShop then
		setPanelVisible(false)
	end

	if placingItemData
		and (
			not canShowShop
			or (
				placementSource == "Inventory"
				and not canContinueInventoryPlacement()
			)
		) then
		ui.DestroyCatalogPlacementPreview()
	end

	ui.UpdateOpenButton()
end

player:GetAttributeChangedSignal("CurrentRoomName"):Connect(function()
	ui.placementStartup.cancelPending("CurrentRoomName changed")

	if placingItemData then
		ui.DestroyCatalogPlacementPreview()
	end

	ui.HandleCatalogVisibilityChanged()
end)
player:GetAttributeChangedSignal("RoomMode"):Connect(ui.HandleCatalogVisibilityChanged)
player:GetAttributeChangedSignal("OnboardingStep"):Connect(ui.HandleCatalogVisibilityChanged)
player:GetAttributeChangedSignal("ControlMode"):Connect(ui.HandleCatalogVisibilityChanged)
player:GetAttributeChangedSignal("HasCreatedRoom"):Connect(ui.HandleCatalogVisibilityChanged)

activeRooms.ChildAdded:Connect(function()
	task.defer(ui.UpdateOpenButton)
end)

activeRooms.ChildRemoved:Connect(function(child)
	if child.Name == player:GetAttribute("CurrentRoomName") then
		ui.placementStartup.cancelPending("active room removed")

		if placingItemData then
			ui.DestroyCatalogPlacementPreview()
		end
	end

	task.defer(ui.UpdateOpenButton)
end)

task.defer(ui.UpdateOpenButton)
