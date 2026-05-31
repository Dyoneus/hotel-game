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
	Furniture = true,
	Marketplace = true,
}

local CATALOG_VIEW = {
	SHOP = "Shop",
	MARKETPLACE = "Marketplace",
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
	FURNITURE_ALL = "FurnitureAll",
	FURNITURE_SEATING = "FurnitureSeating",
	FURNITURE_TABLES = "FurnitureTables",
	FURNITURE_BEDS = "FurnitureBeds",
	FURNITURE_DECOR = "FurnitureDecor",
	FURNITURE_ROOM_BUILDING = "FurnitureRoomBuilding",
	FURNITURE_RUGS = "FurnitureRugs",
	FURNITURE_PLANTS = "FurniturePlants",
	FURNITURE_LIGHTING = "FurnitureLighting",
	FURNITURE_EXTRAS = "FurnitureExtras",
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
	{ Page = CATALOG_PAGE.PETS, Label = "Pets", Icon = "P" },
	{ Page = CATALOG_PAGE.SPECIAL_OFFERS, Label = "Special Offers", Icon = "!" },
	{ Group = "Marketplace", Label = "Marketplace", Icon = "M" },
}

local CATALOG_SHOP_CATEGORIES = {
	{ Page = CATALOG_PAGE.FURNITURE_ALL, Label = "All", Category = "All" },
	{ Page = CATALOG_PAGE.FURNITURE_SEATING, Label = "Seating", Category = "Chairs" },
	{ Page = CATALOG_PAGE.FURNITURE_TABLES, Label = "Tables", Category = "Tables" },
	{ Page = CATALOG_PAGE.FURNITURE_BEDS, Label = "Beds", Category = "Beds" },
	{ Page = CATALOG_PAGE.FURNITURE_DECOR, Label = "Decor", Category = "Decor" },
	{ Page = CATALOG_PAGE.FURNITURE_ROOM_BUILDING, Label = "Room Building", Category = "Room Building" },
	{ Page = CATALOG_PAGE.FURNITURE_RUGS, Label = "Rugs", Category = "Rugs" },
	{ Page = CATALOG_PAGE.FURNITURE_PLANTS, Label = "Plants", Category = "Plants" },
	{ Page = CATALOG_PAGE.FURNITURE_LIGHTING, Label = "Lighting", Category = "Lighting" },
	{ Page = CATALOG_PAGE.FURNITURE_EXTRAS, Label = "Extras", Category = "Extras" },
}

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

local updateOpenButton = nil
local destroyCatalogPlacementPreview = nil
local renderCatalog = nil
local renderMarketplace = nil
local selectCatalogPage = nil
local rebuildCatalogNavigation = nil
local requestMarketplaceOffers = nil
local requestMarketplaceMySales = nil
local cancelMarketplaceSale = nil
local claimMarketplaceSale = nil
local requestMarketplacePurchase = nil

local placingItemData = nil
local placementPreview = nil
local placementPreviewHighlight = nil
local placementIsValid = false
local placementRotationY = 0
local placementBaseRotation = CFrame.new()
local placementSource = nil

local OVERLAP_SHRINK = 0.08
local PLACEMENT_BOUNDS_PART_NAME = "PlacementBounds"

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

	if updateOpenButton then
		updateOpenButton()
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

	if not roomFolder then
		return nil
	end

	local floor = roomFolder:FindFirstChild("WalkableFloor")

	if floor and floor:IsA("BasePart") then
		return floor
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

	if updateOpenButton then
		updateOpenButton()
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
		elseif key == "MarketplaceGroup" and catalogViewMode == CATALOG_VIEW.MARKETPLACE then
			isSelected = true
		end

		styleCatalogNavButton(button, isSelected)
	end
end

local function updateCatalogChrome()
	local showingMarketplace = catalogViewMode == CATALOG_VIEW.MARKETPLACE
	local showingShop = catalogViewMode == CATALOG_VIEW.SHOP
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

	if showingShop or (showingMarketplace and showingOffers) then
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

local function clampPreviewCFrameInsideRoom(model, targetCFrame)
	local floorBounds = getFloorPlacementBounds()
	local modelBounds = getModelXZBoundsAtCFrame(model, targetCFrame)

	if not floorBounds or not modelBounds then
		return targetCFrame
	end

	local offsetX = 0
	local offsetZ = 0

	if modelBounds.minX < floorBounds.minX then
		offsetX = floorBounds.minX - modelBounds.minX
	elseif modelBounds.maxX > floorBounds.maxX then
		offsetX = floorBounds.maxX - modelBounds.maxX
	end

	if modelBounds.minZ < floorBounds.minZ then
		offsetZ = floorBounds.minZ - modelBounds.minZ
	elseif modelBounds.maxZ > floorBounds.maxZ then
		offsetZ = floorBounds.maxZ - modelBounds.maxZ
	end

	return targetCFrame + Vector3.new(offsetX, 0, offsetZ)
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

local function getPreviewPlacementCFrame(model)
	local floorPosition = getMouseFloorPosition()
	local roomModel, floor = getCurrentPlacementGrid()

	if not floorPosition or not floor then
		return nil
	end

	local tileSize = GridConfig.GetTileSize(roomModel, floor)
	local snappedWorldPosition = GridConfig.SnapWorldToTileCenter(floor, floorPosition, tileSize)
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

	return targetCFrame
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

local function setPlacementPreviewValidity(isValid)
	placementIsValid = isValid

	local fillColor

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
	end

	if placementPreview then
		for _, descendant in ipairs(placementPreview:GetDescendants()) do
			if descendant:IsA("BasePart")
				and not isHelperPart(descendant)
				and descendant.Name ~= PLACEMENT_BOUNDS_PART_NAME then
				descendant.Color = fillColor
				descendant.Transparency = 0.35
				descendant.Material = Enum.Material.Neon
			end
		end
	end
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
		destroyCatalogPlacementPreview()
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
	if placementPreviewHighlight then
		placementPreviewHighlight:Destroy()
		placementPreviewHighlight = nil
	end

	if placementPreview then
		placementPreview:Destroy()
		placementPreview = nil
	end
end

destroyCatalogPlacementPreview = function()
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

	if updateOpenButton then
		updateOpenButton()
	end
end

local function createCatalogPlacementPreview(itemData)
	destroyCatalogPlacementPreview()

	local _, _, gridError = getCurrentPlacementGrid()

	if gridError then
		setStatus(gridError)
		return
	end

	local templateName = itemData.TemplateName or itemData.Id
	local template = furnitureTemplates:FindFirstChild(templateName)

	if not template or not template:IsA("Model") then
		setStatus("Missing furniture template: " .. tostring(templateName))
		return
	end

	local source = itemData.Source == "Inventory" and "Inventory" or "Catalog"

	placingItemData = itemData
	placementSource = source
	placementRotationY = 0
	placementBaseRotation = CFrame.new()
	player:SetAttribute("CatalogPlacementActive", true)

	bindCatalogPlacementControls()

	placementPreview = template:Clone()
	placementPreview.Name = "CatalogPlacementPreview"

	local templatePivot = placementPreview:GetPivot()
	placementBaseRotation = templatePivot - templatePivot.Position

	for _, descendant in ipairs(placementPreview:GetDescendants()) do
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

	placementPreview.Parent = workspace

	placementPreviewHighlight = Instance.new("Highlight")
	placementPreviewHighlight.Name = "CatalogPlacementPreviewHighlight"
	placementPreviewHighlight.Adornee = placementPreview
	placementPreviewHighlight.FillTransparency = 0.45
	placementPreviewHighlight.OutlineTransparency = 0
	placementPreviewHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	placementPreviewHighlight.Parent = placementPreview

	setPlacementPreviewValidity(false)

	setPanelVisible(false)
	ui.OpenButton.Visible = false

	if placementSource == "Inventory" then
		setStatus("Move your cursor over the floor to place an owned item.")
	else
		setStatus("Move your cursor over the floor. Click to place, R to rotate, C to cancel.")
	end

	setPlacementHint(getActivePlacementHint(false))
end

local function updateCatalogPlacementPreview()
	if not placingItemData or not placementPreview then
		return
	end

	local targetCFrame = getPreviewPlacementCFrame(placementPreview)

	if not targetCFrame then
		setPlacementPreviewValidity(false)
		return
	end

	placementPreview:PivotTo(targetCFrame)

	local isValid = isPreviewInsideRoom(placementPreview)
		and not isPreviewBlocked(placementPreview)
		and not isPreviewBlockedByPlayer(placementPreview)

	setPlacementPreviewValidity(isValid)
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
		destroyCatalogPlacementPreview()
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

	if selectedCategory == "Chairs" then
		return itemData.Category == "Chairs" or itemData.Category == "Seating"
	end

	return itemData.Category == selectedCategory
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
			selectCatalogPage(CATALOG_PAGE.FURNITURE_ALL)
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
			selectCatalogPage(CATALOG_PAGE.FURNITURE_ALL)
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
	nameLabel.Size = UDim2.new(1, -200, 0, 22)
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
	descriptionLabel.Size = UDim2.new(1, -200, 0, 18)
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
	metaLabel.Size = UDim2.new(1, -200, 0, 18)
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
	ownershipLabel.Size = UDim2.new(1, -200, 0, 18)
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

	local infoButton = Instance.new("TextButton")
	infoButton.Name = "MarketplaceItemInfoButton"
	infoButton.AnchorPoint = Vector2.new(1, 0)
	infoButton.Position = UDim2.new(1, -112, 0, 22)
	infoButton.Size = UDim2.fromOffset(94, 28)
	infoButton.BackgroundColor3 = Color3.fromRGB(225, 228, 224)
	infoButton.BorderSizePixel = 0
	infoButton.Text = "Item Info"
	infoButton.TextColor3 = Color3.fromRGB(55, 58, 55)
	infoButton.TextSize = 11
	infoButton.Font = Enum.Font.GothamBold
	infoButton.Parent = row

	createCorner(infoButton, 7)

	infoButton.MouseButton1Click:Connect(function()
		setStatus("Item info is coming soon.")
	end)

	local buyButton = Instance.new("TextButton")
	buyButton.Name = isOwnOnly and "OwnMarketplaceOfferButton" or "BuyMarketplaceOfferButton"
	buyButton.AnchorPoint = Vector2.new(1, 0)
	buyButton.Position = UDim2.new(1, -12, 0, 22)
	buyButton.Size = UDim2.fromOffset(92, 28)
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
			if cancelMarketplaceSale then
				cancelMarketplaceSale(listingId)
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
			if claimMarketplaceSale then
				claimMarketplaceSale(listingId)
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

cancelMarketplaceSale = function(listingId)
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

claimMarketplaceSale = function(listingId)
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

requestMarketplacePurchase = function()
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
		selectedCatalogPage = CATALOG_PAGE.FURNITURE_ALL
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

updateOpenButton = function()
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
	if requestMarketplacePurchase then
		requestMarketplacePurchase()
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
		destroyCatalogPlacementPreview()
	end
end)

closeMajorMenus.Event:Connect(function()
	if ui.Panel.Visible then
		setPanelVisible(false)
	end

	if placingItemData then
		destroyCatalogPlacementPreview()
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

	createCatalogPlacementPreview(itemData)
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

		destroyCatalogPlacementPreview()
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

local function handleCatalogVisibilityChanged()
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
		destroyCatalogPlacementPreview()
	end

	updateOpenButton()
end

player:GetAttributeChangedSignal("CurrentRoomName"):Connect(handleCatalogVisibilityChanged)
player:GetAttributeChangedSignal("RoomMode"):Connect(handleCatalogVisibilityChanged)
player:GetAttributeChangedSignal("OnboardingStep"):Connect(handleCatalogVisibilityChanged)
player:GetAttributeChangedSignal("ControlMode"):Connect(handleCatalogVisibilityChanged)
player:GetAttributeChangedSignal("HasCreatedRoom"):Connect(handleCatalogVisibilityChanged)

activeRooms.ChildAdded:Connect(function()
	task.defer(updateOpenButton)
end)

activeRooms.ChildRemoved:Connect(function()
	task.defer(updateOpenButton)
end)

task.defer(updateOpenButton)
