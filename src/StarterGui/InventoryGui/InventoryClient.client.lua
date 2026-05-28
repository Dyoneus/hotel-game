-- StarterGui/InventoryGui/InventoryClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local inventoryRequest = remoteEvents:WaitForChild("InventoryRequest")
local inventoryResult = remoteEvents:WaitForChild("InventoryResult")
local marketplaceRequest = remoteEvents:WaitForChild("MarketplaceRequest")
local marketplaceResult = remoteEvents:WaitForChild("MarketplaceResult")
local setRoomModeRequest = remoteEvents:WaitForChild("SetRoomModeRequest")
local roomModeResult = remoteEvents:WaitForChild("RoomModeResult")
local activeRooms = workspace:WaitForChild("ActiveRooms")

local furnitureCatalogConfig = nil
local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")

if sharedFolder then
	local configModule = sharedFolder:FindFirstChild("FurnitureCatalogConfig")

	if configModule and configModule:IsA("ModuleScript") then
		local ok, result = pcall(require, configModule)

		if ok and typeof(result) == "table" then
			furnitureCatalogConfig = result
		else
			warn("Inventory category config failed to load.", result)
		end
	end
end

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 155

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

local requestInFlight = false
local refreshQueued = false
local queuedRefreshForce = false
local lastInventoryRequestAt = -math.huge
local requestSerial = 0
local hasLoadedInventory = false
local lastInventoryCacheUpdateAt = -math.huge
local latestInventory = {}
local latestInventoryDetails = {}
local selectedInventoryCategory = "All"
local selectedInventoryTemplateId = nil
local dropdownOpen = false
local currentInventoryCategories = { "All" }
local selectedSellQuantity = 1
local inventoryViewMode = "Items"
local marketplaceListingTemplateId = nil
local marketplaceListingQuantity = 1
local marketplaceCreateInFlight = false
local marketplaceCreateRequestSerial = 0
local pendingCreateListingRequestId = nil
local pendingCreateListingTemplateId = nil
local pendingCreateListingQuantity = 1
local pendingCreateListingUnitPriceCoins = nil
local marketplaceMyListingsInFlight = false
local myListingsLastRequestAt = -math.huge
local myListingsQueuedRefresh = false
local myListingsQueuedRefreshScheduled = false
local marketplacePublicListingsInFlight = false
local publicMarketplaceLastRequestAt = -math.huge
local publicMarketplaceQueuedRefresh = false
local publicMarketplaceQueuedRefreshScheduled = false
local marketplaceCancelInFlightByListingId = {}
local latestMarketplaceListings = {}
local latestPublicMarketplaceListings = {}
local pendingPlacementTemplateId = nil
local pendingPlaceAfterEdit = false
local inventoryPlacementRequestedEditMode = false
local inventoryPlacementEnteredEditMode = false
local inventoryPlacementExitEditRequested = false
local inventoryHideRequestedForPlacement = false
local inventoryHiddenForPlacement = false
local panelDragInput = nil
local panelDragStartInputPosition = nil
local panelDragStartPanelPosition = nil

local LOCAL_REQUEST_COOLDOWN_SECONDS = 0.75
local RESTORE_REFRESH_STALE_SECONDS = 1.25
local LOCAL_DELTA_REFRESH_SUPPRESS_SECONDS = 0.35
local REQUEST_TIMEOUT_SECONDS = 6
local EDIT_MODE_FAILURE_MESSAGE = "Go to a room you can edit to place this item."
local EDIT_MODE_PREPARING_MESSAGE = "Preparing room editing..."
local INVENTORY_CATEGORY_ALL = "All"
local INVENTORY_CATEGORY_OTHER = "Other"
local INVENTORY_VIEW_ITEMS = "Items"
local INVENTORY_VIEW_MY_LISTINGS = "MyListings"
local INVENTORY_VIEW_MARKETPLACE = "Marketplace"
local MARKETPLACE_MIN_UNIT_PRICE_COINS = 1
local MARKETPLACE_MAX_UNIT_PRICE_COINS = 999999
local MARKETPLACE_MAX_LISTING_QUANTITY = 99
local MY_LISTINGS_LOCAL_COOLDOWN_SECONDS = 0.7
local PUBLIC_MARKETPLACE_LOCAL_COOLDOWN_SECONDS = 0.7
local PANEL_SCREEN_MARGIN = 12

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

local MENU_NAME = "Inventory"
local anyMajorMenuOpen = false
local openMajorMenuName = nil
local renderInventory = nil
local setPanelVisible = nil
local hideInventoryForPlacement = nil
local restoreInventoryAfterPlacement = nil
local sellRequestInFlight = false
local ui = {}

ui.openButton = Instance.new("TextButton")
ui.openButton.Name = "OpenInventoryButton"
ui.openButton.AnchorPoint = Vector2.new(1, 1)
ui.openButton.Position = UDim2.new(1, -20, 1, -128)
ui.openButton.Size = UDim2.fromOffset(150, 44)
ui.openButton.BackgroundColor3 = Color3.fromRGB(80, 120, 90)
ui.openButton.BorderSizePixel = 0
ui.openButton.Text = "Inventory"
ui.openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ui.openButton.TextSize = 20
ui.openButton.Font = Enum.Font.GothamBold
ui.openButton.Visible = false
ui.openButton.Parent = gui

createCorner(ui.openButton, 10)
createStroke(ui.openButton, Color3.fromRGB(255, 255, 255), 1, 0.25)

ui.panel = Instance.new("Frame")
ui.panel.Name = "InventoryPanel"
ui.panel.AnchorPoint = Vector2.new(1, 0.5)
ui.panel.Position = UDim2.new(1, -24, 0.5, 0)
ui.panel.Size = UDim2.fromOffset(680, 460)
ui.panel.BackgroundColor3 = Color3.fromRGB(245, 245, 238)
ui.panel.BorderSizePixel = 0
ui.panel.Visible = false
ui.panel.Parent = gui

createCorner(ui.panel, 16)
createStroke(ui.panel, Color3.fromRGB(255, 255, 255), 2, 0.1)

ui.titleLabel = Instance.new("TextLabel")
ui.titleLabel.Name = "TitleLabel"
ui.titleLabel.Position = UDim2.fromOffset(18, 14)
ui.titleLabel.Size = UDim2.new(1, -70, 0, 36)
ui.titleLabel.BackgroundTransparency = 1
ui.titleLabel.Text = "Inventory"
ui.titleLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
ui.titleLabel.TextSize = 24
ui.titleLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.titleLabel.Font = Enum.Font.GothamBold
ui.titleLabel.Parent = ui.panel

ui.closeButton = Instance.new("TextButton")
ui.closeButton.Name = "CloseButton"
ui.closeButton.AnchorPoint = Vector2.new(1, 0)
ui.closeButton.Position = UDim2.new(1, -18, 0, 18)
ui.closeButton.Size = UDim2.fromOffset(34, 34)
ui.closeButton.BackgroundColor3 = Color3.fromRGB(160, 70, 70)
ui.closeButton.BorderSizePixel = 0
ui.closeButton.Text = "X"
ui.closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ui.closeButton.TextSize = 18
ui.closeButton.Font = Enum.Font.GothamBold
ui.closeButton.Parent = ui.panel

createCorner(ui.closeButton, 8)

ui.dragHandle = Instance.new("Frame")
ui.dragHandle.Name = "InventoryDragHandle"
ui.dragHandle.Position = UDim2.fromOffset(0, 0)
ui.dragHandle.Size = UDim2.new(1, -74, 0, 58)
ui.dragHandle.BackgroundTransparency = 1
ui.dragHandle.Active = true
ui.dragHandle.ZIndex = 5
ui.dragHandle.Parent = ui.panel

ui.statusLabel = Instance.new("TextLabel")
ui.statusLabel.Name = "StatusLabel"
ui.statusLabel.Position = UDim2.fromOffset(18, 56)
ui.statusLabel.Size = UDim2.new(1, -36, 0, 28)
ui.statusLabel.BackgroundTransparency = 1
ui.statusLabel.Text = ""
ui.statusLabel.TextColor3 = Color3.fromRGB(90, 90, 90)
ui.statusLabel.TextWrapped = true
ui.statusLabel.TextSize = 13
ui.statusLabel.Font = Enum.Font.Gotham
ui.statusLabel.Parent = ui.panel

ui.categoryButton = Instance.new("TextButton")
ui.categoryButton.Name = "CategoryDropdownButton"
ui.categoryButton.Position = UDim2.fromOffset(18, 92)
ui.categoryButton.Size = UDim2.new(0, 184, 0, 32)
ui.categoryButton.BackgroundColor3 = Color3.fromRGB(235, 238, 242)
ui.categoryButton.BorderSizePixel = 0
ui.categoryButton.Text = "Category: All"
ui.categoryButton.TextColor3 = Color3.fromRGB(45, 45, 45)
ui.categoryButton.TextSize = 14
ui.categoryButton.TextXAlignment = Enum.TextXAlignment.Left
ui.categoryButton.Font = Enum.Font.GothamBold
ui.categoryButton.ZIndex = 20
ui.categoryButton.Parent = ui.panel

createCorner(ui.categoryButton, 8)
createStroke(ui.categoryButton, Color3.fromRGB(210, 215, 220), 1, 0)

ui.myListingsButton = Instance.new("TextButton")
ui.myListingsButton.Name = "MyListingsButton"
ui.myListingsButton.Position = UDim2.fromOffset(210, 92)
ui.myListingsButton.Size = UDim2.new(0, 108, 0, 32)
ui.myListingsButton.BackgroundColor3 = Color3.fromRGB(235, 238, 242)
ui.myListingsButton.BorderSizePixel = 0
ui.myListingsButton.Text = "My Listings"
ui.myListingsButton.TextColor3 = Color3.fromRGB(45, 45, 45)
ui.myListingsButton.TextSize = 13
ui.myListingsButton.Font = Enum.Font.GothamBold
ui.myListingsButton.Parent = ui.panel

createCorner(ui.myListingsButton, 8)
createStroke(ui.myListingsButton, Color3.fromRGB(210, 215, 220), 1, 0)

ui.marketplaceBrowseButton = Instance.new("TextButton")
ui.marketplaceBrowseButton.Name = "MarketplaceBrowseButton"
ui.marketplaceBrowseButton.Position = UDim2.fromOffset(210, 128)
ui.marketplaceBrowseButton.Size = UDim2.new(0, 108, 0, 28)
ui.marketplaceBrowseButton.BackgroundColor3 = Color3.fromRGB(235, 238, 242)
ui.marketplaceBrowseButton.BorderSizePixel = 0
ui.marketplaceBrowseButton.Text = "Marketplace"
ui.marketplaceBrowseButton.TextColor3 = Color3.fromRGB(45, 45, 45)
ui.marketplaceBrowseButton.TextSize = 12
ui.marketplaceBrowseButton.Font = Enum.Font.GothamBold
ui.marketplaceBrowseButton.Visible = false
ui.marketplaceBrowseButton.Active = false
ui.marketplaceBrowseButton.Parent = ui.panel

createCorner(ui.marketplaceBrowseButton, 7)
createStroke(ui.marketplaceBrowseButton, Color3.fromRGB(210, 215, 220), 1, 0)

ui.categoryDropdown = Instance.new("ScrollingFrame")
ui.categoryDropdown.Name = "CategoryDropdownList"
ui.categoryDropdown.Position = UDim2.fromOffset(18, 128)
ui.categoryDropdown.Size = UDim2.fromOffset(184, 0)
ui.categoryDropdown.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
ui.categoryDropdown.BorderSizePixel = 0
ui.categoryDropdown.CanvasSize = UDim2.fromOffset(0, 0)
ui.categoryDropdown.ScrollBarThickness = 4
ui.categoryDropdown.Visible = false
ui.categoryDropdown.ZIndex = 30
ui.categoryDropdown.Parent = ui.panel

createCorner(ui.categoryDropdown, 8)
createStroke(ui.categoryDropdown, Color3.fromRGB(210, 215, 220), 1, 0)

ui.categoryDropdownLayout = Instance.new("UIListLayout")
ui.categoryDropdownLayout.SortOrder = Enum.SortOrder.LayoutOrder
ui.categoryDropdownLayout.Padding = UDim.new(0, 2)
ui.categoryDropdownLayout.Parent = ui.categoryDropdown

ui.listFrame = Instance.new("ScrollingFrame")
ui.listFrame.Name = "InventoryList"
ui.listFrame.Position = UDim2.fromOffset(18, 168)
ui.listFrame.Size = UDim2.new(0, 300, 1, -188)
ui.listFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
ui.listFrame.BorderSizePixel = 0
ui.listFrame.ScrollBarThickness = 6
ui.listFrame.CanvasSize = UDim2.fromOffset(0, 0)
ui.listFrame.Parent = ui.panel

createCorner(ui.listFrame, 12)
createStroke(ui.listFrame, Color3.fromRGB(220, 220, 220), 1, 0)

ui.gridLayout = Instance.new("UIGridLayout")
ui.gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
ui.gridLayout.CellSize = UDim2.fromOffset(86, 86)
ui.gridLayout.CellPadding = UDim2.fromOffset(8, 8)
ui.gridLayout.Parent = ui.listFrame

ui.listPadding = Instance.new("UIPadding")
ui.listPadding.PaddingTop = UDim.new(0, 10)
ui.listPadding.PaddingBottom = UDim.new(0, 10)
ui.listPadding.PaddingLeft = UDim.new(0, 10)
ui.listPadding.PaddingRight = UDim.new(0, 10)
ui.listPadding.Parent = ui.listFrame

ui.detailsPanel = Instance.new("Frame")
ui.detailsPanel.Name = "SelectedItemDetails"
ui.detailsPanel.Position = UDim2.new(0, 334, 0, 92)
ui.detailsPanel.Size = UDim2.new(1, -352, 1, -112)
ui.detailsPanel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
ui.detailsPanel.BorderSizePixel = 0
ui.detailsPanel.Parent = ui.panel

createCorner(ui.detailsPanel, 12)
createStroke(ui.detailsPanel, Color3.fromRGB(220, 220, 220), 1, 0)

ui.detailsTitle = Instance.new("TextLabel")
ui.detailsTitle.Name = "DetailsTitle"
ui.detailsTitle.Position = UDim2.fromOffset(16, 14)
ui.detailsTitle.Size = UDim2.new(1, -32, 0, 28)
ui.detailsTitle.BackgroundTransparency = 1
ui.detailsTitle.Text = "Select an item"
ui.detailsTitle.TextColor3 = Color3.fromRGB(40, 40, 40)
ui.detailsTitle.TextSize = 20
ui.detailsTitle.TextXAlignment = Enum.TextXAlignment.Left
ui.detailsTitle.TextTruncate = Enum.TextTruncate.AtEnd
ui.detailsTitle.Font = Enum.Font.GothamBold
ui.detailsTitle.Parent = ui.detailsPanel

ui.detailsSubtitle = Instance.new("TextLabel")
ui.detailsSubtitle.Name = "DetailsSubtitle"
ui.detailsSubtitle.Position = UDim2.fromOffset(16, 46)
ui.detailsSubtitle.Size = UDim2.new(1, -32, 0, 20)
ui.detailsSubtitle.BackgroundTransparency = 1
ui.detailsSubtitle.Text = ""
ui.detailsSubtitle.TextColor3 = Color3.fromRGB(85, 85, 85)
ui.detailsSubtitle.TextSize = 13
ui.detailsSubtitle.TextXAlignment = Enum.TextXAlignment.Left
ui.detailsSubtitle.TextTruncate = Enum.TextTruncate.AtEnd
ui.detailsSubtitle.Font = Enum.Font.Gotham
ui.detailsSubtitle.Parent = ui.detailsPanel

ui.detailsDescription = Instance.new("TextLabel")
ui.detailsDescription.Name = "DetailsDescription"
ui.detailsDescription.Position = UDim2.fromOffset(16, 72)
ui.detailsDescription.Size = UDim2.new(1, -32, 0, 44)
ui.detailsDescription.BackgroundTransparency = 1
ui.detailsDescription.Text = "Choose an owned furniture item to see details."
ui.detailsDescription.TextColor3 = Color3.fromRGB(90, 90, 90)
ui.detailsDescription.TextSize = 13
ui.detailsDescription.TextWrapped = true
ui.detailsDescription.TextXAlignment = Enum.TextXAlignment.Left
ui.detailsDescription.TextYAlignment = Enum.TextYAlignment.Top
ui.detailsDescription.Font = Enum.Font.Gotham
ui.detailsDescription.Parent = ui.detailsPanel

ui.ownershipLabel = Instance.new("TextLabel")
ui.ownershipLabel.Name = "OwnershipLabel"
ui.ownershipLabel.Position = UDim2.fromOffset(16, 126)
ui.ownershipLabel.Size = UDim2.new(1, -32, 0, 84)
ui.ownershipLabel.BackgroundTransparency = 1
ui.ownershipLabel.Text = ""
ui.ownershipLabel.TextColor3 = Color3.fromRGB(55, 60, 55)
ui.ownershipLabel.TextSize = 13
ui.ownershipLabel.TextWrapped = true
ui.ownershipLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.ownershipLabel.TextYAlignment = Enum.TextYAlignment.Top
ui.ownershipLabel.Font = Enum.Font.GothamMedium
ui.ownershipLabel.Parent = ui.detailsPanel

ui.placeButton = Instance.new("TextButton")
ui.placeButton.Name = "PlaceToRoomButton"
ui.placeButton.Position = UDim2.new(0, 16, 0, 218)
ui.placeButton.Size = UDim2.new(1, -32, 0, 34)
ui.placeButton.BackgroundColor3 = Color3.fromRGB(70, 135, 90)
ui.placeButton.BorderSizePixel = 0
ui.placeButton.Text = "Place to room"
ui.placeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ui.placeButton.TextSize = 15
ui.placeButton.Font = Enum.Font.GothamBold
ui.placeButton.Parent = ui.detailsPanel

createCorner(ui.placeButton, 8)

ui.sellControlsFrame = Instance.new("Frame")
ui.sellControlsFrame.Name = "SellControls"
ui.sellControlsFrame.Position = UDim2.new(0, 16, 0, 264)
ui.sellControlsFrame.Size = UDim2.new(1, -32, 0, 34)
ui.sellControlsFrame.BackgroundTransparency = 1
ui.sellControlsFrame.Parent = ui.detailsPanel

ui.sellDecreaseButton = Instance.new("TextButton")
ui.sellDecreaseButton.Name = "DecreaseSellQuantityButton"
ui.sellDecreaseButton.Position = UDim2.fromOffset(0, 0)
ui.sellDecreaseButton.Size = UDim2.fromOffset(34, 34)
ui.sellDecreaseButton.BackgroundColor3 = Color3.fromRGB(230, 235, 240)
ui.sellDecreaseButton.BorderSizePixel = 0
ui.sellDecreaseButton.Text = "<"
ui.sellDecreaseButton.TextColor3 = Color3.fromRGB(45, 45, 45)
ui.sellDecreaseButton.TextSize = 15
ui.sellDecreaseButton.Font = Enum.Font.GothamBold
ui.sellDecreaseButton.Parent = ui.sellControlsFrame

createCorner(ui.sellDecreaseButton, 8)

ui.sellQuantityLabel = Instance.new("TextLabel")
ui.sellQuantityLabel.Name = "SellQuantityLabel"
ui.sellQuantityLabel.Position = UDim2.fromOffset(40, 0)
ui.sellQuantityLabel.Size = UDim2.fromOffset(42, 34)
ui.sellQuantityLabel.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
ui.sellQuantityLabel.BorderSizePixel = 0
ui.sellQuantityLabel.Text = "1"
ui.sellQuantityLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
ui.sellQuantityLabel.TextSize = 14
ui.sellQuantityLabel.Font = Enum.Font.GothamBold
ui.sellQuantityLabel.Parent = ui.sellControlsFrame

createCorner(ui.sellQuantityLabel, 8)

ui.sellIncreaseButton = Instance.new("TextButton")
ui.sellIncreaseButton.Name = "IncreaseSellQuantityButton"
ui.sellIncreaseButton.Position = UDim2.fromOffset(88, 0)
ui.sellIncreaseButton.Size = UDim2.fromOffset(34, 34)
ui.sellIncreaseButton.BackgroundColor3 = Color3.fromRGB(230, 235, 240)
ui.sellIncreaseButton.BorderSizePixel = 0
ui.sellIncreaseButton.Text = ">"
ui.sellIncreaseButton.TextColor3 = Color3.fromRGB(45, 45, 45)
ui.sellIncreaseButton.TextSize = 15
ui.sellIncreaseButton.Font = Enum.Font.GothamBold
ui.sellIncreaseButton.Parent = ui.sellControlsFrame

createCorner(ui.sellIncreaseButton, 8)

ui.sellButton = Instance.new("TextButton")
ui.sellButton.Name = "SellForDollarsButton"
ui.sellButton.Position = UDim2.new(0, 132, 0, 0)
ui.sellButton.Size = UDim2.new(1, -132, 0, 34)
ui.sellButton.BackgroundColor3 = Color3.fromRGB(70, 135, 90)
ui.sellButton.BorderSizePixel = 0
ui.sellButton.Text = "Sell for Dollars"
ui.sellButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ui.sellButton.TextSize = 14
ui.sellButton.Font = Enum.Font.GothamBold
ui.sellButton.Parent = ui.sellControlsFrame

createCorner(ui.sellButton, 8)

ui.marketplaceButton = Instance.new("TextButton")
ui.marketplaceButton.Name = "SellInMarketplaceButton"
ui.marketplaceButton.Position = UDim2.new(0, 16, 0, 310)
ui.marketplaceButton.Size = UDim2.new(1, -32, 0, 32)
ui.marketplaceButton.BackgroundColor3 = Color3.fromRGB(70, 120, 170)
ui.marketplaceButton.BorderSizePixel = 0
ui.marketplaceButton.Text = "Sell in Marketplace"
ui.marketplaceButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ui.marketplaceButton.TextSize = 14
ui.marketplaceButton.Font = Enum.Font.GothamBold
ui.marketplaceButton.Active = true
ui.marketplaceButton.AutoButtonColor = true
ui.marketplaceButton.Parent = ui.detailsPanel

createCorner(ui.marketplaceButton, 8)

ui.myListingsPanel = Instance.new("Frame")
ui.myListingsPanel.Name = "MyListingsPanel"
ui.myListingsPanel.Position = ui.detailsPanel.Position
ui.myListingsPanel.Size = ui.detailsPanel.Size
ui.myListingsPanel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
ui.myListingsPanel.BorderSizePixel = 0
ui.myListingsPanel.Visible = false
ui.myListingsPanel.Parent = ui.panel

createCorner(ui.myListingsPanel, 12)
createStroke(ui.myListingsPanel, Color3.fromRGB(220, 220, 220), 1, 0)

ui.myListingsTitle = Instance.new("TextLabel")
ui.myListingsTitle.Name = "MyListingsTitle"
ui.myListingsTitle.Position = UDim2.fromOffset(16, 14)
ui.myListingsTitle.Size = UDim2.new(1, -154, 0, 28)
ui.myListingsTitle.BackgroundTransparency = 1
ui.myListingsTitle.Text = "My Listings"
ui.myListingsTitle.TextColor3 = Color3.fromRGB(40, 40, 40)
ui.myListingsTitle.TextSize = 20
ui.myListingsTitle.TextXAlignment = Enum.TextXAlignment.Left
ui.myListingsTitle.TextTruncate = Enum.TextTruncate.AtEnd
ui.myListingsTitle.Font = Enum.Font.GothamBold
ui.myListingsTitle.Parent = ui.myListingsPanel

ui.myListingsBackButton = Instance.new("TextButton")
ui.myListingsBackButton.Name = "BackToItemsButton"
ui.myListingsBackButton.AnchorPoint = Vector2.new(1, 0)
ui.myListingsBackButton.Position = UDim2.new(1, -16, 0, 14)
ui.myListingsBackButton.Size = UDim2.fromOffset(58, 28)
ui.myListingsBackButton.BackgroundColor3 = Color3.fromRGB(235, 238, 242)
ui.myListingsBackButton.BorderSizePixel = 0
ui.myListingsBackButton.Text = "Items"
ui.myListingsBackButton.TextColor3 = Color3.fromRGB(45, 45, 45)
ui.myListingsBackButton.TextSize = 12
ui.myListingsBackButton.Font = Enum.Font.GothamBold
ui.myListingsBackButton.Parent = ui.myListingsPanel

createCorner(ui.myListingsBackButton, 7)

ui.myListingsRefreshButton = Instance.new("TextButton")
ui.myListingsRefreshButton.Name = "RefreshListingsButton"
ui.myListingsRefreshButton.AnchorPoint = Vector2.new(1, 0)
ui.myListingsRefreshButton.Position = UDim2.new(1, -82, 0, 14)
ui.myListingsRefreshButton.Size = UDim2.fromOffset(64, 28)
ui.myListingsRefreshButton.BackgroundColor3 = Color3.fromRGB(70, 135, 90)
ui.myListingsRefreshButton.BorderSizePixel = 0
ui.myListingsRefreshButton.Text = "Refresh"
ui.myListingsRefreshButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ui.myListingsRefreshButton.TextSize = 12
ui.myListingsRefreshButton.Font = Enum.Font.GothamBold
ui.myListingsRefreshButton.Parent = ui.myListingsPanel

createCorner(ui.myListingsRefreshButton, 7)

ui.myListingsStatusLabel = Instance.new("TextLabel")
ui.myListingsStatusLabel.Name = "MyListingsStatusLabel"
ui.myListingsStatusLabel.Position = UDim2.fromOffset(16, 48)
ui.myListingsStatusLabel.Size = UDim2.new(1, -32, 0, 22)
ui.myListingsStatusLabel.BackgroundTransparency = 1
ui.myListingsStatusLabel.Text = ""
ui.myListingsStatusLabel.TextColor3 = Color3.fromRGB(85, 85, 85)
ui.myListingsStatusLabel.TextSize = 13
ui.myListingsStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.myListingsStatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
ui.myListingsStatusLabel.Font = Enum.Font.Gotham
ui.myListingsStatusLabel.Parent = ui.myListingsPanel

ui.myListingsListFrame = Instance.new("ScrollingFrame")
ui.myListingsListFrame.Name = "MyListingsList"
ui.myListingsListFrame.Position = UDim2.fromOffset(16, 78)
ui.myListingsListFrame.Size = UDim2.new(1, -32, 1, -94)
ui.myListingsListFrame.BackgroundColor3 = Color3.fromRGB(248, 248, 248)
ui.myListingsListFrame.BorderSizePixel = 0
ui.myListingsListFrame.ScrollBarThickness = 5
ui.myListingsListFrame.CanvasSize = UDim2.fromOffset(0, 0)
ui.myListingsListFrame.Parent = ui.myListingsPanel

createCorner(ui.myListingsListFrame, 8)
createStroke(ui.myListingsListFrame, Color3.fromRGB(225, 225, 225), 1, 0)

ui.myListingsListLayout = Instance.new("UIListLayout")
ui.myListingsListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ui.myListingsListLayout.Padding = UDim.new(0, 8)
ui.myListingsListLayout.Parent = ui.myListingsListFrame

ui.myListingsListPadding = Instance.new("UIPadding")
ui.myListingsListPadding.PaddingTop = UDim.new(0, 8)
ui.myListingsListPadding.PaddingBottom = UDim.new(0, 8)
ui.myListingsListPadding.PaddingLeft = UDim.new(0, 8)
ui.myListingsListPadding.PaddingRight = UDim.new(0, 8)
ui.myListingsListPadding.Parent = ui.myListingsListFrame

ui.publicMarketplacePanel = Instance.new("Frame")
ui.publicMarketplacePanel.Name = "PublicMarketplacePanel"
ui.publicMarketplacePanel.Position = ui.detailsPanel.Position
ui.publicMarketplacePanel.Size = ui.detailsPanel.Size
ui.publicMarketplacePanel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
ui.publicMarketplacePanel.BorderSizePixel = 0
ui.publicMarketplacePanel.Visible = false
ui.publicMarketplacePanel.Parent = ui.panel

createCorner(ui.publicMarketplacePanel, 12)
createStroke(ui.publicMarketplacePanel, Color3.fromRGB(220, 220, 220), 1, 0)

ui.publicMarketplaceTitle = Instance.new("TextLabel")
ui.publicMarketplaceTitle.Name = "PublicMarketplaceTitle"
ui.publicMarketplaceTitle.Position = UDim2.fromOffset(16, 14)
ui.publicMarketplaceTitle.Size = UDim2.new(1, -154, 0, 28)
ui.publicMarketplaceTitle.BackgroundTransparency = 1
ui.publicMarketplaceTitle.Text = "Marketplace"
ui.publicMarketplaceTitle.TextColor3 = Color3.fromRGB(40, 40, 40)
ui.publicMarketplaceTitle.TextSize = 20
ui.publicMarketplaceTitle.TextXAlignment = Enum.TextXAlignment.Left
ui.publicMarketplaceTitle.TextTruncate = Enum.TextTruncate.AtEnd
ui.publicMarketplaceTitle.Font = Enum.Font.GothamBold
ui.publicMarketplaceTitle.Parent = ui.publicMarketplacePanel

ui.publicMarketplaceBackButton = Instance.new("TextButton")
ui.publicMarketplaceBackButton.Name = "BackToItemsFromMarketplaceButton"
ui.publicMarketplaceBackButton.AnchorPoint = Vector2.new(1, 0)
ui.publicMarketplaceBackButton.Position = UDim2.new(1, -16, 0, 14)
ui.publicMarketplaceBackButton.Size = UDim2.fromOffset(58, 28)
ui.publicMarketplaceBackButton.BackgroundColor3 = Color3.fromRGB(235, 238, 242)
ui.publicMarketplaceBackButton.BorderSizePixel = 0
ui.publicMarketplaceBackButton.Text = "Items"
ui.publicMarketplaceBackButton.TextColor3 = Color3.fromRGB(45, 45, 45)
ui.publicMarketplaceBackButton.TextSize = 12
ui.publicMarketplaceBackButton.Font = Enum.Font.GothamBold
ui.publicMarketplaceBackButton.Parent = ui.publicMarketplacePanel

createCorner(ui.publicMarketplaceBackButton, 7)

ui.publicMarketplaceRefreshButton = Instance.new("TextButton")
ui.publicMarketplaceRefreshButton.Name = "RefreshMarketplaceButton"
ui.publicMarketplaceRefreshButton.AnchorPoint = Vector2.new(1, 0)
ui.publicMarketplaceRefreshButton.Position = UDim2.new(1, -82, 0, 14)
ui.publicMarketplaceRefreshButton.Size = UDim2.fromOffset(64, 28)
ui.publicMarketplaceRefreshButton.BackgroundColor3 = Color3.fromRGB(70, 135, 90)
ui.publicMarketplaceRefreshButton.BorderSizePixel = 0
ui.publicMarketplaceRefreshButton.Text = "Refresh"
ui.publicMarketplaceRefreshButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ui.publicMarketplaceRefreshButton.TextSize = 12
ui.publicMarketplaceRefreshButton.Font = Enum.Font.GothamBold
ui.publicMarketplaceRefreshButton.Parent = ui.publicMarketplacePanel

createCorner(ui.publicMarketplaceRefreshButton, 7)

ui.publicMarketplaceSearchBox = Instance.new("TextBox")
ui.publicMarketplaceSearchBox.Name = "MarketplaceSearchBox"
ui.publicMarketplaceSearchBox.Position = UDim2.fromOffset(16, 50)
ui.publicMarketplaceSearchBox.Size = UDim2.new(1, -32, 0, 30)
ui.publicMarketplaceSearchBox.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
ui.publicMarketplaceSearchBox.BorderSizePixel = 0
ui.publicMarketplaceSearchBox.ClearTextOnFocus = false
ui.publicMarketplaceSearchBox.PlaceholderText = "Search listings"
ui.publicMarketplaceSearchBox.Text = ""
ui.publicMarketplaceSearchBox.TextColor3 = Color3.fromRGB(40, 40, 40)
ui.publicMarketplaceSearchBox.PlaceholderColor3 = Color3.fromRGB(135, 135, 135)
ui.publicMarketplaceSearchBox.TextSize = 13
ui.publicMarketplaceSearchBox.TextXAlignment = Enum.TextXAlignment.Left
ui.publicMarketplaceSearchBox.Font = Enum.Font.Gotham
ui.publicMarketplaceSearchBox.Parent = ui.publicMarketplacePanel

createCorner(ui.publicMarketplaceSearchBox, 7)

ui.publicMarketplaceStatusLabel = Instance.new("TextLabel")
ui.publicMarketplaceStatusLabel.Name = "PublicMarketplaceStatusLabel"
ui.publicMarketplaceStatusLabel.Position = UDim2.fromOffset(16, 82)
ui.publicMarketplaceStatusLabel.Size = UDim2.new(1, -32, 0, 20)
ui.publicMarketplaceStatusLabel.BackgroundTransparency = 1
ui.publicMarketplaceStatusLabel.Text = ""
ui.publicMarketplaceStatusLabel.TextColor3 = Color3.fromRGB(85, 85, 85)
ui.publicMarketplaceStatusLabel.TextSize = 12
ui.publicMarketplaceStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.publicMarketplaceStatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
ui.publicMarketplaceStatusLabel.Font = Enum.Font.Gotham
ui.publicMarketplaceStatusLabel.Parent = ui.publicMarketplacePanel

ui.publicMarketplaceListFrame = Instance.new("ScrollingFrame")
ui.publicMarketplaceListFrame.Name = "PublicMarketplaceList"
ui.publicMarketplaceListFrame.Position = UDim2.fromOffset(16, 108)
ui.publicMarketplaceListFrame.Size = UDim2.new(1, -32, 1, -124)
ui.publicMarketplaceListFrame.BackgroundColor3 = Color3.fromRGB(248, 248, 248)
ui.publicMarketplaceListFrame.BorderSizePixel = 0
ui.publicMarketplaceListFrame.ScrollBarThickness = 5
ui.publicMarketplaceListFrame.CanvasSize = UDim2.fromOffset(0, 0)
ui.publicMarketplaceListFrame.Parent = ui.publicMarketplacePanel

createCorner(ui.publicMarketplaceListFrame, 8)
createStroke(ui.publicMarketplaceListFrame, Color3.fromRGB(225, 225, 225), 1, 0)

ui.publicMarketplaceListLayout = Instance.new("UIListLayout")
ui.publicMarketplaceListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ui.publicMarketplaceListLayout.Padding = UDim.new(0, 8)
ui.publicMarketplaceListLayout.Parent = ui.publicMarketplaceListFrame

ui.publicMarketplaceListPadding = Instance.new("UIPadding")
ui.publicMarketplaceListPadding.PaddingTop = UDim.new(0, 8)
ui.publicMarketplaceListPadding.PaddingBottom = UDim.new(0, 8)
ui.publicMarketplaceListPadding.PaddingLeft = UDim.new(0, 8)
ui.publicMarketplaceListPadding.PaddingRight = UDim.new(0, 8)
ui.publicMarketplaceListPadding.Parent = ui.publicMarketplaceListFrame

ui.marketplaceModalOverlay = Instance.new("Frame")
ui.marketplaceModalOverlay.Name = "MarketplaceListingModalOverlay"
ui.marketplaceModalOverlay.Position = UDim2.fromScale(0, 0)
ui.marketplaceModalOverlay.Size = UDim2.fromScale(1, 1)
ui.marketplaceModalOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
ui.marketplaceModalOverlay.BackgroundTransparency = 0.35
ui.marketplaceModalOverlay.BorderSizePixel = 0
ui.marketplaceModalOverlay.Visible = false
ui.marketplaceModalOverlay.Active = true
ui.marketplaceModalOverlay.ZIndex = 100
ui.marketplaceModalOverlay.Parent = ui.panel

ui.marketplaceModalWindow = Instance.new("Frame")
ui.marketplaceModalWindow.Name = "MarketplaceListingModal"
ui.marketplaceModalWindow.AnchorPoint = Vector2.new(0.5, 0.5)
ui.marketplaceModalWindow.Position = UDim2.fromScale(0.5, 0.5)
ui.marketplaceModalWindow.Size = UDim2.fromOffset(360, 314)
ui.marketplaceModalWindow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
ui.marketplaceModalWindow.BorderSizePixel = 0
ui.marketplaceModalWindow.ZIndex = 101
ui.marketplaceModalWindow.Parent = ui.marketplaceModalOverlay

createCorner(ui.marketplaceModalWindow, 12)
createStroke(ui.marketplaceModalWindow, Color3.fromRGB(230, 230, 230), 1, 0)

ui.listingModalTitle = Instance.new("TextLabel")
ui.listingModalTitle.Name = "ListingModalTitle"
ui.listingModalTitle.Position = UDim2.fromOffset(18, 14)
ui.listingModalTitle.Size = UDim2.new(1, -36, 0, 26)
ui.listingModalTitle.BackgroundTransparency = 1
ui.listingModalTitle.Text = "List in Marketplace"
ui.listingModalTitle.TextColor3 = Color3.fromRGB(40, 40, 40)
ui.listingModalTitle.TextSize = 20
ui.listingModalTitle.TextXAlignment = Enum.TextXAlignment.Left
ui.listingModalTitle.Font = Enum.Font.GothamBold
ui.listingModalTitle.ZIndex = 102
ui.listingModalTitle.Parent = ui.marketplaceModalWindow

ui.listingModalItemLabel = Instance.new("TextLabel")
ui.listingModalItemLabel.Name = "ListingModalItemLabel"
ui.listingModalItemLabel.Position = UDim2.fromOffset(18, 48)
ui.listingModalItemLabel.Size = UDim2.new(1, -36, 0, 22)
ui.listingModalItemLabel.BackgroundTransparency = 1
ui.listingModalItemLabel.Text = ""
ui.listingModalItemLabel.TextColor3 = Color3.fromRGB(55, 55, 55)
ui.listingModalItemLabel.TextSize = 14
ui.listingModalItemLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.listingModalItemLabel.TextTruncate = Enum.TextTruncate.AtEnd
ui.listingModalItemLabel.Font = Enum.Font.GothamBold
ui.listingModalItemLabel.ZIndex = 102
ui.listingModalItemLabel.Parent = ui.marketplaceModalWindow

ui.listingModalAvailableLabel = Instance.new("TextLabel")
ui.listingModalAvailableLabel.Name = "ListingModalAvailableLabel"
ui.listingModalAvailableLabel.Position = UDim2.fromOffset(18, 72)
ui.listingModalAvailableLabel.Size = UDim2.new(1, -36, 0, 22)
ui.listingModalAvailableLabel.BackgroundTransparency = 1
ui.listingModalAvailableLabel.Text = ""
ui.listingModalAvailableLabel.TextColor3 = Color3.fromRGB(80, 80, 80)
ui.listingModalAvailableLabel.TextSize = 13
ui.listingModalAvailableLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.listingModalAvailableLabel.Font = Enum.Font.Gotham
ui.listingModalAvailableLabel.ZIndex = 102
ui.listingModalAvailableLabel.Parent = ui.marketplaceModalWindow

ui.listingQuantityLabel = Instance.new("TextLabel")
ui.listingQuantityLabel.Name = "ListingQuantityText"
ui.listingQuantityLabel.Position = UDim2.fromOffset(18, 108)
ui.listingQuantityLabel.Size = UDim2.fromOffset(96, 28)
ui.listingQuantityLabel.BackgroundTransparency = 1
ui.listingQuantityLabel.Text = "Quantity"
ui.listingQuantityLabel.TextColor3 = Color3.fromRGB(55, 55, 55)
ui.listingQuantityLabel.TextSize = 13
ui.listingQuantityLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.listingQuantityLabel.Font = Enum.Font.GothamMedium
ui.listingQuantityLabel.ZIndex = 102
ui.listingQuantityLabel.Parent = ui.marketplaceModalWindow

ui.listingQuantityDecreaseButton = Instance.new("TextButton")
ui.listingQuantityDecreaseButton.Name = "DecreaseListingQuantityButton"
ui.listingQuantityDecreaseButton.Position = UDim2.fromOffset(128, 104)
ui.listingQuantityDecreaseButton.Size = UDim2.fromOffset(34, 34)
ui.listingQuantityDecreaseButton.BackgroundColor3 = Color3.fromRGB(230, 235, 240)
ui.listingQuantityDecreaseButton.BorderSizePixel = 0
ui.listingQuantityDecreaseButton.Text = "<"
ui.listingQuantityDecreaseButton.TextColor3 = Color3.fromRGB(45, 45, 45)
ui.listingQuantityDecreaseButton.TextSize = 15
ui.listingQuantityDecreaseButton.Font = Enum.Font.GothamBold
ui.listingQuantityDecreaseButton.ZIndex = 102
ui.listingQuantityDecreaseButton.Parent = ui.marketplaceModalWindow

createCorner(ui.listingQuantityDecreaseButton, 8)

ui.listingQuantityValueLabel = Instance.new("TextLabel")
ui.listingQuantityValueLabel.Name = "ListingQuantityValue"
ui.listingQuantityValueLabel.Position = UDim2.fromOffset(168, 104)
ui.listingQuantityValueLabel.Size = UDim2.fromOffset(48, 34)
ui.listingQuantityValueLabel.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
ui.listingQuantityValueLabel.BorderSizePixel = 0
ui.listingQuantityValueLabel.Text = "1"
ui.listingQuantityValueLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
ui.listingQuantityValueLabel.TextSize = 14
ui.listingQuantityValueLabel.Font = Enum.Font.GothamBold
ui.listingQuantityValueLabel.ZIndex = 102
ui.listingQuantityValueLabel.Parent = ui.marketplaceModalWindow

createCorner(ui.listingQuantityValueLabel, 8)

ui.listingQuantityIncreaseButton = Instance.new("TextButton")
ui.listingQuantityIncreaseButton.Name = "IncreaseListingQuantityButton"
ui.listingQuantityIncreaseButton.Position = UDim2.fromOffset(222, 104)
ui.listingQuantityIncreaseButton.Size = UDim2.fromOffset(34, 34)
ui.listingQuantityIncreaseButton.BackgroundColor3 = Color3.fromRGB(230, 235, 240)
ui.listingQuantityIncreaseButton.BorderSizePixel = 0
ui.listingQuantityIncreaseButton.Text = ">"
ui.listingQuantityIncreaseButton.TextColor3 = Color3.fromRGB(45, 45, 45)
ui.listingQuantityIncreaseButton.TextSize = 15
ui.listingQuantityIncreaseButton.Font = Enum.Font.GothamBold
ui.listingQuantityIncreaseButton.ZIndex = 102
ui.listingQuantityIncreaseButton.Parent = ui.marketplaceModalWindow

createCorner(ui.listingQuantityIncreaseButton, 8)

ui.unitPriceLabel = Instance.new("TextLabel")
ui.unitPriceLabel.Name = "UnitPriceText"
ui.unitPriceLabel.Position = UDim2.fromOffset(18, 154)
ui.unitPriceLabel.Size = UDim2.fromOffset(124, 28)
ui.unitPriceLabel.BackgroundTransparency = 1
ui.unitPriceLabel.Text = "Unit price"
ui.unitPriceLabel.TextColor3 = Color3.fromRGB(55, 55, 55)
ui.unitPriceLabel.TextSize = 13
ui.unitPriceLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.unitPriceLabel.Font = Enum.Font.GothamMedium
ui.unitPriceLabel.ZIndex = 102
ui.unitPriceLabel.Parent = ui.marketplaceModalWindow

ui.unitPriceTextBox = Instance.new("TextBox")
ui.unitPriceTextBox.Name = "UnitPriceCoinsTextBox"
ui.unitPriceTextBox.Position = UDim2.fromOffset(128, 150)
ui.unitPriceTextBox.Size = UDim2.fromOffset(144, 34)
ui.unitPriceTextBox.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
ui.unitPriceTextBox.BorderSizePixel = 0
ui.unitPriceTextBox.ClearTextOnFocus = false
ui.unitPriceTextBox.PlaceholderText = "Coins"
ui.unitPriceTextBox.Text = "1"
ui.unitPriceTextBox.TextColor3 = Color3.fromRGB(40, 40, 40)
ui.unitPriceTextBox.PlaceholderColor3 = Color3.fromRGB(135, 135, 135)
ui.unitPriceTextBox.TextSize = 14
ui.unitPriceTextBox.TextXAlignment = Enum.TextXAlignment.Left
ui.unitPriceTextBox.Font = Enum.Font.GothamBold
ui.unitPriceTextBox.ZIndex = 102
ui.unitPriceTextBox.Parent = ui.marketplaceModalWindow

createCorner(ui.unitPriceTextBox, 8)

ui.unitPriceCoinsLabel = Instance.new("TextLabel")
ui.unitPriceCoinsLabel.Name = "UnitPriceCoinsLabel"
ui.unitPriceCoinsLabel.Position = UDim2.fromOffset(278, 154)
ui.unitPriceCoinsLabel.Size = UDim2.fromOffset(58, 26)
ui.unitPriceCoinsLabel.BackgroundTransparency = 1
ui.unitPriceCoinsLabel.Text = "Coins"
ui.unitPriceCoinsLabel.TextColor3 = Color3.fromRGB(80, 80, 80)
ui.unitPriceCoinsLabel.TextSize = 13
ui.unitPriceCoinsLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.unitPriceCoinsLabel.Font = Enum.Font.Gotham
ui.unitPriceCoinsLabel.ZIndex = 102
ui.unitPriceCoinsLabel.Parent = ui.marketplaceModalWindow

ui.listingTotalPriceLabel = Instance.new("TextLabel")
ui.listingTotalPriceLabel.Name = "ListingTotalPriceLabel"
ui.listingTotalPriceLabel.Position = UDim2.fromOffset(18, 198)
ui.listingTotalPriceLabel.Size = UDim2.new(1, -36, 0, 24)
ui.listingTotalPriceLabel.BackgroundTransparency = 1
ui.listingTotalPriceLabel.Text = "Total: 1 Coins"
ui.listingTotalPriceLabel.TextColor3 = Color3.fromRGB(50, 90, 60)
ui.listingTotalPriceLabel.TextSize = 14
ui.listingTotalPriceLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.listingTotalPriceLabel.Font = Enum.Font.GothamBold
ui.listingTotalPriceLabel.ZIndex = 102
ui.listingTotalPriceLabel.Parent = ui.marketplaceModalWindow

ui.listingModalMessageLabel = Instance.new("TextLabel")
ui.listingModalMessageLabel.Name = "ListingModalMessage"
ui.listingModalMessageLabel.Position = UDim2.fromOffset(18, 226)
ui.listingModalMessageLabel.Size = UDim2.new(1, -36, 0, 26)
ui.listingModalMessageLabel.BackgroundTransparency = 1
ui.listingModalMessageLabel.Text = ""
ui.listingModalMessageLabel.TextColor3 = Color3.fromRGB(150, 60, 60)
ui.listingModalMessageLabel.TextSize = 12
ui.listingModalMessageLabel.TextWrapped = true
ui.listingModalMessageLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.listingModalMessageLabel.Font = Enum.Font.Gotham
ui.listingModalMessageLabel.ZIndex = 102
ui.listingModalMessageLabel.Parent = ui.marketplaceModalWindow

ui.listingCancelButton = Instance.new("TextButton")
ui.listingCancelButton.Name = "CancelListingModalButton"
ui.listingCancelButton.Position = UDim2.fromOffset(18, 264)
ui.listingCancelButton.Size = UDim2.fromOffset(142, 34)
ui.listingCancelButton.BackgroundColor3 = Color3.fromRGB(235, 238, 242)
ui.listingCancelButton.BorderSizePixel = 0
ui.listingCancelButton.Text = "Cancel"
ui.listingCancelButton.TextColor3 = Color3.fromRGB(45, 45, 45)
ui.listingCancelButton.TextSize = 14
ui.listingCancelButton.Font = Enum.Font.GothamBold
ui.listingCancelButton.ZIndex = 102
ui.listingCancelButton.Parent = ui.marketplaceModalWindow

createCorner(ui.listingCancelButton, 8)

ui.listingConfirmButton = Instance.new("TextButton")
ui.listingConfirmButton.Name = "ConfirmListingButton"
ui.listingConfirmButton.Position = UDim2.fromOffset(176, 264)
ui.listingConfirmButton.Size = UDim2.fromOffset(166, 34)
ui.listingConfirmButton.BackgroundColor3 = Color3.fromRGB(70, 135, 90)
ui.listingConfirmButton.BorderSizePixel = 0
ui.listingConfirmButton.Text = "Confirm"
ui.listingConfirmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ui.listingConfirmButton.TextSize = 14
ui.listingConfirmButton.Font = Enum.Font.GothamBold
ui.listingConfirmButton.ZIndex = 102
ui.listingConfirmButton.Parent = ui.marketplaceModalWindow

createCorner(ui.listingConfirmButton, 8)

local function shouldShowInventoryButton()
	return player:GetAttribute("OnboardingStep") == "Complete"
		and (player:GetAttribute("ControlMode") or "Hotel") == "Hotel"
end

local function updateOpenButton()
	ui.openButton.Visible = (not ui.panel.Visible)
		and not inventoryHiddenForPlacement
		and player:GetAttribute("CatalogPlacementActive") ~= true
		and not anyMajorMenuOpen
		and shouldShowInventoryButton()
end

local function setLocalMajorMenuState(isOpen, menuName)
	if isOpen then
		anyMajorMenuOpen = true
		openMajorMenuName = menuName
	elseif openMajorMenuName == menuName then
		anyMajorMenuOpen = false
		openMajorMenuName = nil
	end

	updateOpenButton()
end

local function publishMajorMenuState(isOpen)
	setLocalMajorMenuState(isOpen, MENU_NAME)
	majorMenuStateChanged:Fire(isOpen, MENU_NAME)
end

local function setStatus(text, success)
	ui.statusLabel.Text = tostring(text or "")

	if success == true then
		ui.statusLabel.TextColor3 = Color3.fromRGB(50, 110, 60)
	elseif success == false then
		ui.statusLabel.TextColor3 = Color3.fromRGB(150, 60, 60)
	else
		ui.statusLabel.TextColor3 = Color3.fromRGB(90, 90, 90)
	end
end

local function setMyListingsStatus(text, success)
	ui.myListingsStatusLabel.Text = tostring(text or "")

	if success == true then
		ui.myListingsStatusLabel.TextColor3 = Color3.fromRGB(50, 110, 60)
	elseif success == false then
		ui.myListingsStatusLabel.TextColor3 = Color3.fromRGB(150, 60, 60)
	else
		ui.myListingsStatusLabel.TextColor3 = Color3.fromRGB(85, 85, 85)
	end
end

local function setPublicMarketplaceStatus(text, success)
	ui.publicMarketplaceStatusLabel.Text = tostring(text or "")

	if success == true then
		ui.publicMarketplaceStatusLabel.TextColor3 = Color3.fromRGB(50, 110, 60)
	elseif success == false then
		ui.publicMarketplaceStatusLabel.TextColor3 = Color3.fromRGB(150, 60, 60)
	else
		ui.publicMarketplaceStatusLabel.TextColor3 = Color3.fromRGB(85, 85, 85)
	end
end

local function getCatalogItem(templateId)
	if typeof(templateId) ~= "string" or not furnitureCatalogConfig then
		return nil
	end

	if typeof(furnitureCatalogConfig.GetItem) ~= "function" then
		return nil
	end

	local ok, item = pcall(furnitureCatalogConfig.GetItem, templateId)

	if ok and typeof(item) == "table" then
		return item
	end

	return nil
end

local function getInventoryCategory(templateId)
	local item = getCatalogItem(templateId)

	if item and typeof(item.Category) == "string" and item.Category ~= "" then
		return item.Category
	end

	return INVENTORY_CATEGORY_OTHER
end

local function getInventorySellPrice(templateId)
	local item = getCatalogItem(templateId)
	local sellPrice = item and item.SellPrice

	if typeof(sellPrice) ~= "number"
		or sellPrice ~= sellPrice
		or sellPrice <= 0
		or sellPrice >= math.huge then

		return nil
	end

	return math.floor(sellPrice)
end

local function addCategory(categories, seenCategories, categoryName)
	if typeof(categoryName) ~= "string" or categoryName == "" then
		return
	end

	if seenCategories[categoryName] then
		return
	end

	seenCategories[categoryName] = true
	table.insert(categories, categoryName)
end

local function buildInventoryCategories(entries)
	local categories = { INVENTORY_CATEGORY_ALL }
	local seenCategories = {
		[INVENTORY_CATEGORY_ALL] = true,
	}

	if furnitureCatalogConfig and typeof(furnitureCatalogConfig.GetItemsArray) == "function" then
		local ok, configItems = pcall(furnitureCatalogConfig.GetItemsArray)

		if ok and typeof(configItems) == "table" then
			for _, item in ipairs(configItems) do
				if typeof(item) == "table" then
					addCategory(categories, seenCategories, item.Category)
				end
			end
		end
	end

	local hasOther = false

	for _, entry in ipairs(entries) do
		if entry.Category == INVENTORY_CATEGORY_OTHER then
			hasOther = true
		else
			addCategory(categories, seenCategories, entry.Category)
		end
	end

	if hasOther then
		addCategory(categories, seenCategories, INVENTORY_CATEGORY_OTHER)
	end

	return categories
end

local function categoryExists(categoryName, categories)
	for _, existingCategory in ipairs(categories) do
		if existingCategory == categoryName then
			return true
		end
	end

	return false
end

local function updateCategoryButton()
	ui.categoryButton.Text = "  Category: " .. tostring(selectedInventoryCategory) .. " v"
end

local function clearCategoryDropdown()
	for _, child in ipairs(ui.categoryDropdown:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function setDropdownOpen(isOpen)
	dropdownOpen = isOpen == true
	ui.categoryDropdown.Visible = dropdownOpen

	if dropdownOpen then
		local dropdownHeight = math.min(#currentInventoryCategories * 30 + 8, 156)
		ui.categoryDropdown.Size = UDim2.fromOffset(184, dropdownHeight)
	else
		ui.categoryDropdown.Size = UDim2.fromOffset(184, 0)
	end
end

local function updateInventoryViewMode()
	local showingMyListings = inventoryViewMode == INVENTORY_VIEW_MY_LISTINGS
	local showingMarketplace = inventoryViewMode == INVENTORY_VIEW_MARKETPLACE

	ui.detailsPanel.Visible = not showingMyListings and not showingMarketplace
	ui.myListingsPanel.Visible = showingMyListings
	ui.publicMarketplacePanel.Visible = showingMarketplace
	ui.myListingsButton.BackgroundColor3 = showingMyListings
		and Color3.fromRGB(70, 150, 210)
		or Color3.fromRGB(235, 238, 242)
	ui.myListingsButton.TextColor3 = showingMyListings
		and Color3.fromRGB(255, 255, 255)
		or Color3.fromRGB(45, 45, 45)
	ui.marketplaceBrowseButton.BackgroundColor3 = showingMarketplace
		and Color3.fromRGB(70, 150, 210)
		or Color3.fromRGB(235, 238, 242)
	ui.marketplaceBrowseButton.TextColor3 = showingMarketplace
		and Color3.fromRGB(255, 255, 255)
		or Color3.fromRGB(45, 45, 45)

	if showingMyListings or showingMarketplace then
		setDropdownOpen(false)
	end
end

local function markInventoryCacheUpdated()
	lastInventoryCacheUpdateAt = os.clock()
end

local function clearPendingPlacementState(clearEditModeCause)
	pendingPlacementTemplateId = nil
	pendingPlaceAfterEdit = false
	inventoryHideRequestedForPlacement = false

	if clearEditModeCause == true then
		inventoryPlacementRequestedEditMode = false
		inventoryPlacementEnteredEditMode = false
		inventoryPlacementExitEditRequested = false
	end
end

local function requestPlayModeIfInventoryCausedEdit()
	if inventoryPlacementExitEditRequested
		or not inventoryPlacementEnteredEditMode
		or player:GetAttribute("RoomMode") ~= "Edit"
		or player:GetAttribute("CatalogPlacementActive") == true then

		return
	end

	inventoryPlacementExitEditRequested = true
	setRoomModeRequest:FireServer("Play")

	task.delay(0.9, function()
		if inventoryPlacementEnteredEditMode
			and player:GetAttribute("RoomMode") == "Edit"
			and player:GetAttribute("CatalogPlacementActive") ~= true
			and not ui.panel.Visible then

			setRoomModeRequest:FireServer("Play")
		end

		inventoryPlacementRequestedEditMode = false
		inventoryPlacementEnteredEditMode = false
		inventoryPlacementExitEditRequested = false
	end)
end

local function clearPlacementFlowForRoomChange()
	clearPendingPlacementState(true)
	inventoryHiddenForPlacement = false
	updateOpenButton()
end

local function getScreenSize()
	local screenSize = gui.AbsoluteSize

	if screenSize.X > 0 and screenSize.Y > 0 then
		return screenSize
	end

	local camera = workspace.CurrentCamera

	if camera then
		return camera.ViewportSize
	end

	return Vector2.new(1280, 720)
end

local function getPanelSize()
	local panelSize = ui.panel.AbsoluteSize

	if panelSize.X > 0 and panelSize.Y > 0 then
		return panelSize
	end

	return Vector2.new(ui.panel.Size.X.Offset, ui.panel.Size.Y.Offset)
end

local function clampPanelPosition(position)
	local screenSize = getScreenSize()
	local panelSize = getPanelSize()
	local rawX = screenSize.X * position.X.Scale + position.X.Offset
	local rawY = screenSize.Y * position.Y.Scale + position.Y.Offset
	local minX = panelSize.X + PANEL_SCREEN_MARGIN
	local maxX = screenSize.X - PANEL_SCREEN_MARGIN
	local minY = panelSize.Y / 2 + PANEL_SCREEN_MARGIN
	local maxY = screenSize.Y - panelSize.Y / 2 - PANEL_SCREEN_MARGIN

	if maxX < minX then
		minX = math.max(PANEL_SCREEN_MARGIN, screenSize.X - PANEL_SCREEN_MARGIN)
		maxX = minX
	end

	if maxY < minY then
		minY = screenSize.Y / 2
		maxY = minY
	end

	return UDim2.fromOffset(
		math.clamp(rawX, minX, maxX),
		math.clamp(rawY, minY, maxY)
	)
end

local function clampPanelToScreen()
	ui.panel.Position = clampPanelPosition(ui.panel.Position)
end

local function beginPanelDrag(input)
	panelDragInput = input
	panelDragStartInputPosition = input.Position
	panelDragStartPanelPosition = ui.panel.Position

	input.Changed:Connect(function()
		if input.UserInputState == Enum.UserInputState.End and panelDragInput == input then
			panelDragInput = nil
			panelDragStartInputPosition = nil
			panelDragStartPanelPosition = nil
			clampPanelToScreen()
		end
	end)
end

ui.dragHandle.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then

		return
	end

	beginPanelDrag(input)
end)

UserInputService.InputChanged:Connect(function(input)
	if not panelDragInput
		or not panelDragStartInputPosition
		or not panelDragStartPanelPosition then

		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then

		return
	end

	local delta = input.Position - panelDragStartInputPosition

	ui.panel.Position = clampPanelPosition(UDim2.new(
		panelDragStartPanelPosition.X.Scale,
		panelDragStartPanelPosition.X.Offset + delta.X,
		panelDragStartPanelPosition.Y.Scale,
		panelDragStartPanelPosition.Y.Offset + delta.Y
	))
end)

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if ui.panel.Visible then
		clampPanelToScreen()
	end
end)

local function updateCategoryDropdown(categories)
	currentInventoryCategories = categories or { INVENTORY_CATEGORY_ALL }

	if not categoryExists(selectedInventoryCategory, currentInventoryCategories) then
		selectedInventoryCategory = INVENTORY_CATEGORY_ALL
	end

	updateCategoryButton()
	clearCategoryDropdown()

	for index, categoryName in ipairs(currentInventoryCategories) do
		local optionButton = Instance.new("TextButton")
		optionButton.Name = tostring(categoryName) .. "CategoryOption"
		optionButton.LayoutOrder = index
		optionButton.Size = UDim2.new(1, -8, 0, 28)
		optionButton.BackgroundColor3 = categoryName == selectedInventoryCategory
			and Color3.fromRGB(70, 150, 255)
			or Color3.fromRGB(245, 245, 245)
		optionButton.BorderSizePixel = 0
		optionButton.Text = tostring(categoryName)
		optionButton.TextColor3 = categoryName == selectedInventoryCategory
			and Color3.fromRGB(255, 255, 255)
			or Color3.fromRGB(45, 45, 45)
		optionButton.TextSize = 13
		optionButton.Font = Enum.Font.GothamBold
		optionButton.ZIndex = 31
		optionButton.Parent = ui.categoryDropdown

		createCorner(optionButton, 6)

		optionButton.MouseButton1Click:Connect(function()
			selectedInventoryCategory = categoryName
			setDropdownOpen(false)

			if renderInventory then
				renderInventory(latestInventory, latestInventoryDetails)
			end
		end)
	end

	task.defer(function()
		ui.categoryDropdown.CanvasSize = UDim2.fromOffset(
			0,
			ui.categoryDropdownLayout.AbsoluteContentSize.Y + 8
		)
	end)

	setDropdownOpen(dropdownOpen)
end

local function getCurrentRoomModel()
	local currentRoomName = player:GetAttribute("CurrentRoomName")

	if typeof(currentRoomName) ~= "string" or currentRoomName == "" then
		return nil
	end

	return activeRooms:FindFirstChild(currentRoomName)
end

local function canPlaceInCurrentRoom()
	local currentRoomName = player:GetAttribute("CurrentRoomName")

	if (player:GetAttribute("ControlMode") or "Hotel") ~= "Hotel"
		or typeof(currentRoomName) ~= "string"
		or currentRoomName == "" then

		return false
	end

	local roomModel = getCurrentRoomModel()

	if not roomModel then
		return false
	end

	if roomModel:GetAttribute("OwnerUserId") == player.UserId then
		return true
	end

	if player:GetAttribute("CanEditCurrentRoom") == true then
		return true
	end

	return false
end

local function isNonNegativeCount(value)
	return typeof(value) == "number"
		and value == value
		and value >= 0
		and value < math.huge
end

local function isFiniteNumber(value)
	return typeof(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function clearRows()
	for _, child in ipairs(ui.listFrame:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local function createEmptyState(message)
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyInventoryLabel"
	emptyLabel.Size = UDim2.new(1, -4, 0, 52)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Text = tostring(message or "Inventory is empty.")
	emptyLabel.TextColor3 = Color3.fromRGB(95, 95, 95)
	emptyLabel.TextSize = 15
	emptyLabel.TextWrapped = true
	emptyLabel.Font = Enum.Font.Gotham
	emptyLabel.Parent = ui.listFrame
end

local function getInventoryCounts(templateId)
	local count = 0
	local details = nil

	if typeof(templateId) ~= "string" or templateId == "" then
		return {
			Total = 0,
			Tradable = 0,
			Untradable = 0,
			Sellable = 0,
			Unsellable = 0,
		}
	end

	if typeof(latestInventory) == "table" and isNonNegativeCount(latestInventory[templateId]) then
		count = math.floor(latestInventory[templateId])
	end

	if typeof(latestInventoryDetails) == "table" then
		details = latestInventoryDetails[templateId]
	end

	local untradableCount = 0
	local unsellableCount = 0
	local sellableCount = count

	if typeof(details) == "table" and typeof(details.Untradable) == "number" then
		untradableCount = details.Untradable
	end

	if typeof(details) == "table" and typeof(details.Unsellable) == "number" then
		unsellableCount = details.Unsellable
	end

	if typeof(details) == "table" and typeof(details.Sellable) == "number" then
		sellableCount = details.Sellable
	else
		sellableCount = count - unsellableCount
	end

	untradableCount = math.clamp(math.floor(untradableCount), 0, count)
	unsellableCount = math.clamp(math.floor(unsellableCount), 0, count)
	sellableCount = math.clamp(math.floor(sellableCount), 0, count)
	local tradableCount = math.clamp(count - untradableCount, 0, count)

	return {
		Total = count,
		Tradable = tradableCount,
		Untradable = untradableCount,
		Sellable = sellableCount,
		Unsellable = unsellableCount,
	}
end

local function getInventoryDisplayName(templateId)
	local item = getCatalogItem(templateId)

	if item and typeof(item.DisplayName) == "string" and item.DisplayName ~= "" then
		return item.DisplayName
	end

	return tostring(templateId)
end

local function buildInventoryEntries()
	local entries = {}

	if typeof(latestInventory) == "table" then
		for templateId, count in pairs(latestInventory) do
			if typeof(templateId) == "string" and typeof(count) == "number" and count > 0 then
				table.insert(entries, {
					TemplateId = templateId,
					Count = count,
					Details = latestInventoryDetails[templateId],
					Category = getInventoryCategory(templateId),
					DisplayName = getInventoryDisplayName(templateId),
				})
			end
		end
	end

	table.sort(entries, function(a, b)
		return tostring(a.DisplayName) < tostring(b.DisplayName)
	end)

	return entries
end

local function getSelectedInventoryEntry()
	if typeof(selectedInventoryTemplateId) ~= "string" then
		return nil
	end

	local count = latestInventory[selectedInventoryTemplateId]

	if not isNonNegativeCount(count) or count <= 0 then
		return nil
	end

	return {
		TemplateId = selectedInventoryTemplateId,
		Count = math.floor(count),
		Details = latestInventoryDetails[selectedInventoryTemplateId],
		Category = getInventoryCategory(selectedInventoryTemplateId),
		DisplayName = getInventoryDisplayName(selectedInventoryTemplateId),
	}
end

local function setButtonEnabled(button, isEnabled, enabledColor)
	button.Active = isEnabled == true
	button.AutoButtonColor = isEnabled == true
	button.BackgroundColor3 = isEnabled == true
		and enabledColor
		or Color3.fromRGB(155, 160, 155)
end

local function updateSelectedItemDetails()
	updateInventoryViewMode()

	if inventoryViewMode ~= INVENTORY_VIEW_ITEMS then
		return
	end

	local entry = getSelectedInventoryEntry()

	if not entry then
		ui.detailsTitle.Text = "Select an item"
		ui.detailsSubtitle.Text = ""
		ui.detailsDescription.Text = "Choose an owned furniture item to see details."
		ui.ownershipLabel.Text = ""
		setButtonEnabled(ui.placeButton, false, Color3.fromRGB(70, 135, 90))
		ui.sellControlsFrame.Visible = false
		ui.marketplaceButton.Visible = false
		pendingPlacementTemplateId = nil
		return
	end

	local templateId = entry.TemplateId
	local item = getCatalogItem(templateId) or {}
	local counts = getInventoryCounts(templateId)
	local sellPrice = getInventorySellPrice(templateId)
	local canSell = counts.Sellable > 0 and typeof(sellPrice) == "number" and sellPrice > 0
	local maxSellQuantity = math.min(counts.Sellable, 99)

	if maxSellQuantity <= 0 then
		selectedSellQuantity = 1
	else
		selectedSellQuantity = math.clamp(selectedSellQuantity, 1, maxSellQuantity)
	end

	ui.detailsTitle.Text = entry.DisplayName
	ui.detailsSubtitle.Text = tostring(templateId) .. "  -  " .. tostring(entry.Category or INVENTORY_CATEGORY_OTHER)
	ui.detailsDescription.Text = typeof(item.Description) == "string" and item.Description ~= ""
		and item.Description
		or "No description available."

	local statusLines = {
		"Owned: " .. tostring(counts.Total),
	}

	if counts.Tradable > 0 and counts.Untradable > 0 then
		table.insert(statusLines, "Tradable: " .. tostring(counts.Tradable))
		table.insert(statusLines, "Untradable: " .. tostring(counts.Untradable))
	elseif counts.Tradable > 0 then
		table.insert(statusLines, "Tradable")
	else
		table.insert(statusLines, "Untradable")
	end

	if counts.Sellable > 0 and counts.Unsellable > 0 then
		table.insert(statusLines, "Sellable: " .. tostring(counts.Sellable))
		table.insert(statusLines, "Unsellable: " .. tostring(counts.Unsellable))
	elseif counts.Sellable > 0 then
		table.insert(statusLines, "Sellable: " .. tostring(counts.Sellable))
	elseif counts.Unsellable > 0 then
		table.insert(statusLines, "Unsellable")
	end

	if sellPrice then
		table.insert(statusLines, "Sell price: " .. tostring(sellPrice) .. " Dollars")
	end

	ui.ownershipLabel.Text = table.concat(statusLines, "\n")

	setButtonEnabled(ui.placeButton, counts.Total > 0, Color3.fromRGB(70, 135, 90))
	ui.placeButton.Text = pendingPlacementTemplateId == templateId and "Preparing..." or "Place to room"

	ui.sellControlsFrame.Visible = canSell
	ui.sellQuantityLabel.Text = tostring(selectedSellQuantity)
	setButtonEnabled(ui.sellDecreaseButton, canSell and not sellRequestInFlight and selectedSellQuantity > 1, Color3.fromRGB(230, 235, 240))
	setButtonEnabled(ui.sellIncreaseButton, canSell and not sellRequestInFlight and selectedSellQuantity < maxSellQuantity, Color3.fromRGB(230, 235, 240))
	setButtonEnabled(ui.sellButton, canSell and not sellRequestInFlight, Color3.fromRGB(70, 135, 90))
	ui.sellButton.Text = sellRequestInFlight and "Selling..." or "Sell for Dollars"

	ui.marketplaceButton.Visible = counts.Tradable > 0
	setButtonEnabled(ui.marketplaceButton, counts.Tradable > 0 and not marketplaceCreateInFlight, Color3.fromRGB(70, 120, 170))
	ui.marketplaceButton.Text = marketplaceCreateInFlight and "Listing..." or "Sell in Marketplace"
end

local function createInventoryCard(entry, layoutOrder)
	local templateId = entry.TemplateId
	local count = entry.Count
	local isSelected = selectedInventoryTemplateId == templateId

	local card = Instance.new("TextButton")
	card.Name = tostring(templateId)
	card.LayoutOrder = layoutOrder
	card.Size = UDim2.fromOffset(86, 86)
	card.BackgroundColor3 = isSelected
		and Color3.fromRGB(220, 238, 250)
		or Color3.fromRGB(250, 250, 250)
	card.BorderSizePixel = 0
	card.Text = ""
	card.AutoButtonColor = true
	card.Parent = ui.listFrame

	createCorner(card, 9)
	createStroke(
		card,
		isSelected and Color3.fromRGB(70, 150, 210) or Color3.fromRGB(220, 220, 220),
		isSelected and 2 or 1,
		0
	)

	local iconFrame = Instance.new("Frame")
	iconFrame.Name = "ItemIcon"
	iconFrame.Position = UDim2.fromOffset(15, 9)
	iconFrame.Size = UDim2.fromOffset(56, 46)
	iconFrame.BackgroundColor3 = Color3.fromRGB(232, 236, 232)
	iconFrame.BorderSizePixel = 0
	iconFrame.Parent = card

	createCorner(iconFrame, 8)

	local iconText = Instance.new("TextLabel")
	iconText.Name = "ItemIconText"
	iconText.Size = UDim2.fromScale(1, 1)
	iconText.BackgroundTransparency = 1
	iconText.Text = string.sub(tostring(templateId), 1, 1)
	iconText.TextColor3 = Color3.fromRGB(70, 80, 70)
	iconText.TextSize = 22
	iconText.Font = Enum.Font.GothamBold
	iconText.Parent = iconFrame

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Position = UDim2.fromOffset(6, 58)
	nameLabel.Size = UDim2.new(1, -12, 0, 20)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = entry.DisplayName
	nameLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
	nameLabel.TextSize = 11
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = card

	local countBadge = Instance.new("TextLabel")
	countBadge.Name = "QuantityBadge"
	countBadge.AnchorPoint = Vector2.new(1, 0)
	countBadge.Position = UDim2.new(1, -5, 0, 5)
	countBadge.Size = UDim2.fromOffset(30, 20)
	countBadge.BackgroundColor3 = Color3.fromRGB(50, 60, 70)
	countBadge.BorderSizePixel = 0
	countBadge.Text = "x" .. tostring(count)
	countBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
	countBadge.TextSize = 11
	countBadge.Font = Enum.Font.GothamBold
	countBadge.Parent = card

	createCorner(countBadge, 10)

	card.MouseButton1Click:Connect(function()
		selectedInventoryTemplateId = templateId
		selectedSellQuantity = 1
		inventoryViewMode = INVENTORY_VIEW_ITEMS
		setStatus("", nil)

		if renderInventory then
			renderInventory(latestInventory, latestInventoryDetails)
		else
			updateSelectedItemDetails()
		end
	end)
end

renderInventory = function(inventory, inventoryDetails)
	latestInventory = inventory or {}
	latestInventoryDetails = inventoryDetails or {}
	markInventoryCacheUpdated()

	local entries = buildInventoryEntries()
	local categories = buildInventoryCategories(entries)
	updateCategoryDropdown(categories)
	clearRows()

	if selectedInventoryTemplateId and not getSelectedInventoryEntry() then
		selectedInventoryTemplateId = nil
		selectedSellQuantity = 1
	end

	if #entries == 0 then
		createEmptyState("Inventory is empty.")
	else
		local visibleEntries = {}

		for _, entry in ipairs(entries) do
			if selectedInventoryCategory == INVENTORY_CATEGORY_ALL
				or entry.Category == selectedInventoryCategory then

				table.insert(visibleEntries, entry)
			end
		end

		if #visibleEntries == 0 then
			createEmptyState("No items in this category.")
		end

		for index, entry in ipairs(visibleEntries) do
			createInventoryCard(entry, index)
		end
	end

	updateSelectedItemDetails()

	task.defer(function()
		ui.listFrame.CanvasSize = UDim2.fromOffset(
			0,
			ui.gridLayout.AbsoluteContentSize.Y + 20
		)
	end)
end

local function applyInventoryLocalDelta(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local templateId = payload.TemplateId

	if typeof(templateId) ~= "string" or templateId == "" or not templateId:match("%S") then
		return
	end

	if typeof(latestInventory) ~= "table" then
		latestInventory = {}
	end

	if typeof(latestInventoryDetails) ~= "table" then
		latestInventoryDetails = {}
	end

	local currentTotal = 0

	if isNonNegativeCount(latestInventory[templateId]) then
		currentTotal = math.floor(latestInventory[templateId])
	end

	local existingDetails = latestInventoryDetails[templateId]
	local untradable = 0
	local unsellable = 0

	if typeof(existingDetails) == "table" and isNonNegativeCount(existingDetails.Untradable) then
		untradable = math.min(math.floor(existingDetails.Untradable), currentTotal)
	end

	if typeof(existingDetails) == "table" and isNonNegativeCount(existingDetails.Unsellable) then
		unsellable = math.min(math.floor(existingDetails.Unsellable), currentTotal)
	end

	local total = nil

	if isFiniteNumber(payload.DeltaTotal) then
		local deltaTotal = math.floor(payload.DeltaTotal)
		local newTotal = math.max(currentTotal + deltaTotal, 0)

		if deltaTotal < 0 then
			local removeCount = math.min(-deltaTotal, currentTotal)

			if payload.ConsumeUntradableFirst == true then
				local removeUnsellableUntradable = math.min(untradable, unsellable, removeCount)
				untradable -= removeUnsellableUntradable
				unsellable -= removeUnsellableUntradable

				local remainingRemoveCount = removeCount - removeUnsellableUntradable
				local removeUntradable = math.min(untradable, remainingRemoveCount)
				untradable -= removeUntradable
			end
		end

		if isFiniteNumber(payload.DeltaUntradable) then
			untradable += math.floor(payload.DeltaUntradable)
		end

		if isFiniteNumber(payload.DeltaUnsellable) then
			unsellable += math.floor(payload.DeltaUnsellable)
		end

		total = newTotal
	elseif isNonNegativeCount(payload.Total) then
		total = math.floor(payload.Total)

		if isNonNegativeCount(payload.Untradable) then
			untradable = math.floor(payload.Untradable)
		elseif isNonNegativeCount(payload.Tradable) then
			untradable = total - math.floor(payload.Tradable)
		end

		if isNonNegativeCount(payload.Unsellable) then
			unsellable = math.floor(payload.Unsellable)
		elseif isNonNegativeCount(payload.Sellable) then
			unsellable = total - math.floor(payload.Sellable)
		end
	else
		return
	end

	total = math.max(total, 0)
	untradable = math.clamp(untradable, 0, total)
	unsellable = math.clamp(unsellable, 0, total)
	local tradable = total - untradable
	local sellable = total - unsellable

	if total > 0 then
		latestInventory[templateId] = total
		latestInventoryDetails[templateId] = {
			Total = total,
			Tradable = tradable,
			Untradable = untradable,
			Sellable = sellable,
			Unsellable = unsellable,
		}
	else
		latestInventory[templateId] = nil
		latestInventoryDetails[templateId] = nil
	end

	hasLoadedInventory = true
	markInventoryCacheUpdated()

	if ui.panel.Visible then
		renderInventory(latestInventory, latestInventoryDetails)
	end
end

local function normalizeIntegerText(text, minValue, maxValue, emptyMessage)
	if typeof(text) ~= "string" then
		return nil, emptyMessage
	end

	local trimmed = text:match("^%s*(.-)%s*$") or ""

	if trimmed == "" then
		return nil, emptyMessage
	end

	if not trimmed:match("^%d+$") then
		return nil, "Use whole Coins only."
	end

	local value = tonumber(trimmed)

	if not value or value ~= value or value < minValue or value > maxValue then
		return nil, "Price must be 1 to 999999 Coins."
	end

	value = math.floor(value)

	if value < minValue or value > maxValue then
		return nil, "Price must be 1 to 999999 Coins."
	end

	return value, nil
end

local function parseListingUnitPrice()
	return normalizeIntegerText(
		ui.unitPriceTextBox.Text,
		MARKETPLACE_MIN_UNIT_PRICE_COINS,
		MARKETPLACE_MAX_UNIT_PRICE_COINS,
		"Enter a Coin price."
	)
end

local function getMarketplaceListingMaxQuantity(templateId)
	local counts = getInventoryCounts(templateId)

	return math.min(counts.Tradable, MARKETPLACE_MAX_LISTING_QUANTITY)
end

local function setListingModalMessage(message, success)
	ui.listingModalMessageLabel.Text = tostring(message or "")

	if success == true then
		ui.listingModalMessageLabel.TextColor3 = Color3.fromRGB(50, 110, 60)
	elseif success == false then
		ui.listingModalMessageLabel.TextColor3 = Color3.fromRGB(150, 60, 60)
	else
		ui.listingModalMessageLabel.TextColor3 = Color3.fromRGB(85, 85, 85)
	end
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

local function updateListingModal()
	if not ui.marketplaceModalOverlay.Visible then
		return
	end

	local templateId = marketplaceListingTemplateId
	local maxQuantity = getMarketplaceListingMaxQuantity(templateId)
	local counts = getInventoryCounts(templateId)
	local unitPrice, priceMessage = parseListingUnitPrice()

	if maxQuantity <= 0 then
		marketplaceListingQuantity = 1
	else
		marketplaceListingQuantity = math.clamp(
			math.floor(marketplaceListingQuantity),
			1,
			maxQuantity
		)
	end

	ui.listingModalItemLabel.Text = getInventoryDisplayName(templateId)
	ui.listingModalAvailableLabel.Text = "Tradable available: " .. tostring(counts.Tradable)
	ui.listingQuantityValueLabel.Text = tostring(marketplaceListingQuantity)

	if unitPrice then
		ui.listingTotalPriceLabel.Text = "Total: "
			.. tostring(marketplaceListingQuantity * unitPrice)
			.. " Coins"

		if not marketplaceCreateInFlight then
			setListingModalMessage("", nil)
		end
	else
		ui.listingTotalPriceLabel.Text = "Total: -"

		if not marketplaceCreateInFlight then
			setListingModalMessage(priceMessage, false)
		end
	end

	setButtonEnabled(
		ui.listingQuantityDecreaseButton,
		not marketplaceCreateInFlight and marketplaceListingQuantity > 1,
		Color3.fromRGB(230, 235, 240)
	)
	setButtonEnabled(
		ui.listingQuantityIncreaseButton,
		not marketplaceCreateInFlight and maxQuantity > 0 and marketplaceListingQuantity < maxQuantity,
		Color3.fromRGB(230, 235, 240)
	)
	setButtonEnabled(ui.listingCancelButton, true, Color3.fromRGB(235, 238, 242))
	setButtonEnabled(
		ui.listingConfirmButton,
		not marketplaceCreateInFlight and maxQuantity > 0 and unitPrice ~= nil,
		Color3.fromRGB(70, 135, 90)
	)

	ui.listingConfirmButton.Text = marketplaceCreateInFlight and "Listing..." or "Confirm"
	ui.unitPriceTextBox.TextEditable = not marketplaceCreateInFlight
end

local function closeMarketplaceListingModal()
	ui.marketplaceModalOverlay.Visible = false
	setListingModalMessage("", nil)

	if not marketplaceCreateInFlight then
		marketplaceListingTemplateId = nil
		marketplaceListingQuantity = 1
	end

	updateSelectedItemDetails()
end

local function openMarketplaceListingModal()
	local entry = getSelectedInventoryEntry()

	if not entry then
		setStatus("Select an item first.", false)
		return
	end

	local counts = getInventoryCounts(entry.TemplateId)
	local maxQuantity = math.min(counts.Tradable, MARKETPLACE_MAX_LISTING_QUANTITY)

	if maxQuantity <= 0 then
		setStatus("This item is untradable.", false)
		return
	end

	marketplaceListingTemplateId = entry.TemplateId
	marketplaceListingQuantity = 1
	ui.unitPriceTextBox.Text = tostring(MARKETPLACE_MIN_UNIT_PRICE_COINS)
	setListingModalMessage("", nil)
	ui.marketplaceModalOverlay.Visible = true
	updateListingModal()
end

local function updateMarketplaceListingQuantity(delta)
	if marketplaceCreateInFlight or not ui.marketplaceModalOverlay.Visible then
		return
	end

	local maxQuantity = getMarketplaceListingMaxQuantity(marketplaceListingTemplateId)

	if maxQuantity <= 0 then
		marketplaceListingQuantity = 1
	else
		marketplaceListingQuantity = math.clamp(
			marketplaceListingQuantity + delta,
			1,
			maxQuantity
		)
	end

	updateListingModal()
end

local function applyMarketplaceInventoryDetails(templateId, details)
	if typeof(templateId) ~= "string" or templateId == "" or typeof(details) ~= "table" then
		return
	end

	applyInventoryLocalDelta({
		TemplateId = templateId,
		Total = details.Total,
		Tradable = details.Tradable,
		Untradable = details.Untradable,
		Sellable = details.Sellable,
		Unsellable = details.Unsellable,
	})
end

local requestMyListings = nil
local cancelMarketplaceListing = nil
local requestPublicMarketplaceListings = nil

local function scheduleQueuedMyListingsRefresh(delaySeconds)
	if myListingsQueuedRefreshScheduled then
		return
	end

	myListingsQueuedRefreshScheduled = true

	task.delay(math.max(delaySeconds or 0, 0), function()
		myListingsQueuedRefreshScheduled = false

		if myListingsQueuedRefresh and requestMyListings then
			requestMyListings({
				FromQueue = true,
			})
		end
	end)
end

local function clearMyListingRows()
	for _, child in ipairs(ui.myListingsListFrame:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
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

local function createMyListingsEmptyState(message)
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyMyListingsLabel"
	emptyLabel.Size = UDim2.new(1, -16, 0, 52)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Text = tostring(message or "No marketplace listings yet.")
	emptyLabel.TextColor3 = Color3.fromRGB(95, 95, 95)
	emptyLabel.TextSize = 14
	emptyLabel.TextWrapped = true
	emptyLabel.Font = Enum.Font.Gotham
	emptyLabel.Parent = ui.myListingsListFrame
end

local function upsertMarketplaceListing(listing)
	if typeof(listing) ~= "table"
		or typeof(listing.ListingId) ~= "string"
		or listing.ListingId == "" then

		return
	end

	local replaced = false

	for index, existingListing in ipairs(latestMarketplaceListings) do
		if typeof(existingListing) == "table" and existingListing.ListingId == listing.ListingId then
			latestMarketplaceListings[index] = listing
			replaced = true
			break
		end
	end

	if not replaced then
		table.insert(latestMarketplaceListings, listing)
	end
end

local function renderMyListingsPanel()
	updateInventoryViewMode()
	clearMyListingRows()

	setButtonEnabled(ui.myListingsRefreshButton, not marketplaceMyListingsInFlight, Color3.fromRGB(70, 135, 90))
	ui.myListingsRefreshButton.Text = marketplaceMyListingsInFlight and "Loading..." or "Refresh"

	local listings = {}

	if typeof(latestMarketplaceListings) == "table" then
		for _, listing in ipairs(latestMarketplaceListings) do
			if typeof(listing) == "table" then
				table.insert(listings, listing)
			end
		end
	end

	table.sort(listings, function(a, b)
		local aActiveRank = a.Status == "Active" and 0 or 1
		local bActiveRank = b.Status == "Active" and 0 or 1

		if aActiveRank ~= bActiveRank then
			return aActiveRank < bActiveRank
		end

		return (a.CreatedAt or 0) > (b.CreatedAt or 0)
	end)

	if #listings == 0 then
		createMyListingsEmptyState(marketplaceMyListingsInFlight and "Loading listings..." or "No marketplace listings yet.")
	else
		for index, listing in ipairs(listings) do
			local listingId = listing.ListingId
			local templateId = listing.TemplateId
			local quantity = listing.Quantity or 0
			local unitPriceCoins = listing.UnitPriceCoins or 0
			local status = tostring(listing.Status or "Unknown")
			local isActive = status == "Active"
			local isCancelInFlight = marketplaceCancelInFlightByListingId[listingId] == true

			local row = Instance.new("Frame")
			row.Name = "ListingRow"
			row.LayoutOrder = index
			row.Size = UDim2.new(1, -16, 0, 74)
			row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			row.BorderSizePixel = 0
			row.Parent = ui.myListingsListFrame

			createCorner(row, 8)
			createStroke(row, Color3.fromRGB(225, 225, 225), 1, 0)

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "ListingName"
			nameLabel.Position = UDim2.fromOffset(10, 8)
			nameLabel.Size = UDim2.new(1, isActive and -104 or -20, 0, 20)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = getInventoryDisplayName(templateId)
			nameLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
			nameLabel.TextSize = 13
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.Parent = row

			local priceLabel = Instance.new("TextLabel")
			priceLabel.Name = "ListingPrice"
			priceLabel.Position = UDim2.fromOffset(10, 30)
			priceLabel.Size = UDim2.new(1, isActive and -104 or -20, 0, 18)
			priceLabel.BackgroundTransparency = 1
			priceLabel.Text = "x" .. tostring(quantity)
				.. " @ " .. tostring(unitPriceCoins)
				.. " Coins"
			priceLabel.TextColor3 = Color3.fromRGB(70, 70, 70)
			priceLabel.TextSize = 12
			priceLabel.TextXAlignment = Enum.TextXAlignment.Left
			priceLabel.TextTruncate = Enum.TextTruncate.AtEnd
			priceLabel.Font = Enum.Font.Gotham
			priceLabel.Parent = row

			local createdText = formatListingCreatedAt(listing.CreatedAt)
			local statusLabel = Instance.new("TextLabel")
			statusLabel.Name = "ListingStatus"
			statusLabel.Position = UDim2.fromOffset(10, 50)
			statusLabel.Size = UDim2.new(1, isActive and -104 or -20, 0, 18)
			statusLabel.BackgroundTransparency = 1
			statusLabel.Text = createdText ~= ""
				and (status .. "  -  " .. createdText)
				or status
			statusLabel.TextColor3 = isActive
				and Color3.fromRGB(45, 110, 65)
				or Color3.fromRGB(105, 105, 105)
			statusLabel.TextSize = 12
			statusLabel.TextXAlignment = Enum.TextXAlignment.Left
			statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
			statusLabel.Font = Enum.Font.GothamMedium
			statusLabel.Parent = row

			if isActive then
				local cancelButton = Instance.new("TextButton")
				cancelButton.Name = "CancelListingButton"
				cancelButton.AnchorPoint = Vector2.new(1, 0.5)
				cancelButton.Position = UDim2.new(1, -10, 0.5, 0)
				cancelButton.Size = UDim2.fromOffset(82, 30)
				cancelButton.BackgroundColor3 = Color3.fromRGB(160, 70, 70)
				cancelButton.BorderSizePixel = 0
				cancelButton.Text = isCancelInFlight and "Cancelling..." or "Cancel"
				cancelButton.TextColor3 = Color3.fromRGB(255, 255, 255)
				cancelButton.TextSize = 12
				cancelButton.Font = Enum.Font.GothamBold
				cancelButton.Parent = row

				createCorner(cancelButton, 7)
				setButtonEnabled(cancelButton, not isCancelInFlight, Color3.fromRGB(160, 70, 70))

				cancelButton.MouseButton1Click:Connect(function()
					if cancelMarketplaceListing then
						cancelMarketplaceListing(listingId)
					end
				end)
			end
		end
	end

	task.defer(function()
		ui.myListingsListFrame.CanvasSize = UDim2.fromOffset(
			0,
			ui.myListingsListLayout.AbsoluteContentSize.Y + 16
		)
	end)
end

local function scheduleQueuedPublicMarketplaceRefresh(delaySeconds)
	if publicMarketplaceQueuedRefreshScheduled then
		return
	end

	publicMarketplaceQueuedRefreshScheduled = true

	task.delay(math.max(delaySeconds or 0, 0), function()
		publicMarketplaceQueuedRefreshScheduled = false

		if publicMarketplaceQueuedRefresh and requestPublicMarketplaceListings then
			requestPublicMarketplaceListings({
				FromQueue = true,
			})
		end
	end)
end

local function clearPublicMarketplaceRows()
	for _, child in ipairs(ui.publicMarketplaceListFrame:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local function createPublicMarketplaceEmptyState(message)
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyPublicMarketplaceLabel"
	emptyLabel.Size = UDim2.new(1, -16, 0, 52)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Text = tostring(message or "No active marketplace listings.")
	emptyLabel.TextColor3 = Color3.fromRGB(95, 95, 95)
	emptyLabel.TextSize = 14
	emptyLabel.TextWrapped = true
	emptyLabel.Font = Enum.Font.Gotham
	emptyLabel.Parent = ui.publicMarketplaceListFrame
end

local function getPublicListingDisplayName(listing)
	if typeof(listing) == "table"
		and typeof(listing.DisplayName) == "string"
		and listing.DisplayName ~= "" then

		return listing.DisplayName
	end

	return getInventoryDisplayName(listing and listing.TemplateId)
end

local function renderPublicMarketplacePanel()
	updateInventoryViewMode()
	clearPublicMarketplaceRows()

	setButtonEnabled(ui.publicMarketplaceRefreshButton, not marketplacePublicListingsInFlight, Color3.fromRGB(70, 135, 90))
	ui.publicMarketplaceRefreshButton.Text = marketplacePublicListingsInFlight and "Loading..." or "Refresh"

	local listings = {}

	if typeof(latestPublicMarketplaceListings) == "table" then
		for _, listing in ipairs(latestPublicMarketplaceListings) do
			if typeof(listing) == "table" then
				table.insert(listings, listing)
			end
		end
	end

	table.sort(listings, function(a, b)
		return (a.CreatedAt or 0) > (b.CreatedAt or 0)
	end)

	if #listings == 0 then
		createPublicMarketplaceEmptyState(marketplacePublicListingsInFlight and "Loading listings..." or "No active marketplace listings.")
	else
		for index, listing in ipairs(listings) do
			local quantity = listing.Quantity or 0
			local unitPriceCoins = listing.UnitPriceCoins or 0
			local status = tostring(listing.Status or "Unknown")
			local sellerName = tostring(listing.SellerDisplayName or listing.SellerName or "Unknown seller")
			local sellerSuffix = listing.IsOwnListing == true and " (You)" or ""

			local row = Instance.new("Frame")
			row.Name = "PublicMarketplaceListingRow"
			row.LayoutOrder = index
			row.Size = UDim2.new(1, -16, 0, 86)
			row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			row.BorderSizePixel = 0
			row.Parent = ui.publicMarketplaceListFrame

			createCorner(row, 8)
			createStroke(row, Color3.fromRGB(225, 225, 225), 1, 0)

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "MarketplaceListingName"
			nameLabel.Position = UDim2.fromOffset(10, 8)
			nameLabel.Size = UDim2.new(1, -112, 0, 20)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = getPublicListingDisplayName(listing)
			nameLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
			nameLabel.TextSize = 13
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.Parent = row

			local priceLabel = Instance.new("TextLabel")
			priceLabel.Name = "MarketplaceListingPrice"
			priceLabel.Position = UDim2.fromOffset(10, 30)
			priceLabel.Size = UDim2.new(1, -112, 0, 18)
			priceLabel.BackgroundTransparency = 1
			priceLabel.Text = "x" .. tostring(quantity)
				.. " @ " .. tostring(unitPriceCoins)
				.. " Coins"
			priceLabel.TextColor3 = Color3.fromRGB(70, 70, 70)
			priceLabel.TextSize = 12
			priceLabel.TextXAlignment = Enum.TextXAlignment.Left
			priceLabel.TextTruncate = Enum.TextTruncate.AtEnd
			priceLabel.Font = Enum.Font.Gotham
			priceLabel.Parent = row

			local sellerLabel = Instance.new("TextLabel")
			sellerLabel.Name = "MarketplaceListingSeller"
			sellerLabel.Position = UDim2.fromOffset(10, 50)
			sellerLabel.Size = UDim2.new(1, -112, 0, 18)
			sellerLabel.BackgroundTransparency = 1
			sellerLabel.Text = "Seller: " .. sellerName .. sellerSuffix
			sellerLabel.TextColor3 = listing.IsOwnListing == true
				and Color3.fromRGB(45, 110, 65)
				or Color3.fromRGB(85, 85, 85)
			sellerLabel.TextSize = 12
			sellerLabel.TextXAlignment = Enum.TextXAlignment.Left
			sellerLabel.TextTruncate = Enum.TextTruncate.AtEnd
			sellerLabel.Font = Enum.Font.Gotham
			sellerLabel.Parent = row

			local createdText = formatListingCreatedAt(listing.CreatedAt)
			local statusLabel = Instance.new("TextLabel")
			statusLabel.Name = "MarketplaceListingStatus"
			statusLabel.Position = UDim2.fromOffset(10, 68)
			statusLabel.Size = UDim2.new(1, -112, 0, 16)
			statusLabel.BackgroundTransparency = 1
			statusLabel.Text = createdText ~= ""
				and (status .. "  -  " .. createdText)
				or status
			statusLabel.TextColor3 = Color3.fromRGB(105, 105, 105)
			statusLabel.TextSize = 11
			statusLabel.TextXAlignment = Enum.TextXAlignment.Left
			statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
			statusLabel.Font = Enum.Font.GothamMedium
			statusLabel.Parent = row

			local buyingSoonButton = Instance.new("TextButton")
			buyingSoonButton.Name = "BuyingSoonButton"
			buyingSoonButton.AnchorPoint = Vector2.new(1, 0.5)
			buyingSoonButton.Position = UDim2.new(1, -10, 0.5, 0)
			buyingSoonButton.Size = UDim2.fromOffset(92, 30)
			buyingSoonButton.BackgroundColor3 = Color3.fromRGB(155, 160, 155)
			buyingSoonButton.BorderSizePixel = 0
			buyingSoonButton.Text = "Buying Soon"
			buyingSoonButton.TextColor3 = Color3.fromRGB(255, 255, 255)
			buyingSoonButton.TextSize = 11
			buyingSoonButton.Font = Enum.Font.GothamBold
			buyingSoonButton.Active = false
			buyingSoonButton.AutoButtonColor = false
			buyingSoonButton.Parent = row

			createCorner(buyingSoonButton, 7)
		end
	end

	task.defer(function()
		ui.publicMarketplaceListFrame.CanvasSize = UDim2.fromOffset(
			0,
			ui.publicMarketplaceListLayout.AbsoluteContentSize.Y + 16
		)
	end)
end

requestMyListings = function(options)
	local queueIfBlocked = typeof(options) == "table" and options.Queue == true
	local fromQueue = typeof(options) == "table" and options.FromQueue == true

	if marketplaceMyListingsInFlight then
		if queueIfBlocked then
			myListingsQueuedRefresh = true
		end

		renderMyListingsPanel()
		return
	end

	local now = os.clock()
	local cooldownRemaining = MY_LISTINGS_LOCAL_COOLDOWN_SECONDS - (now - myListingsLastRequestAt)

	if cooldownRemaining > 0 then
		if queueIfBlocked or fromQueue then
			myListingsQueuedRefresh = true
			scheduleQueuedMyListingsRefresh(cooldownRemaining)
		else
			setMyListingsStatus("Please wait a moment.", false)
			renderMyListingsPanel()
		end

		return
	end

	myListingsQueuedRefresh = false
	marketplaceMyListingsInFlight = true
	myListingsLastRequestAt = now
	setMyListingsStatus("Loading listings...", nil)
	renderMyListingsPanel()
	marketplaceRequest:FireServer("GetMyListings")

	local requestStartedAt = myListingsLastRequestAt

	task.delay(REQUEST_TIMEOUT_SECONDS, function()
		if marketplaceMyListingsInFlight and myListingsLastRequestAt == requestStartedAt then
			marketplaceMyListingsInFlight = false
			setMyListingsStatus("Marketplace listings request timed out.", false)
			renderMyListingsPanel()
		end
	end)
end

requestPublicMarketplaceListings = function(options)
	local queueIfBlocked = typeof(options) == "table" and options.Queue == true
	local fromQueue = typeof(options) == "table" and options.FromQueue == true

	if marketplacePublicListingsInFlight then
		if queueIfBlocked then
			publicMarketplaceQueuedRefresh = true
		end

		renderPublicMarketplacePanel()
		return
	end

	local now = os.clock()
	local cooldownRemaining = PUBLIC_MARKETPLACE_LOCAL_COOLDOWN_SECONDS - (now - publicMarketplaceLastRequestAt)

	if cooldownRemaining > 0 then
		if queueIfBlocked or fromQueue then
			publicMarketplaceQueuedRefresh = true
			scheduleQueuedPublicMarketplaceRefresh(cooldownRemaining)
		else
			setPublicMarketplaceStatus("Please wait a moment.", false)
			renderPublicMarketplacePanel()
		end

		return
	end

	publicMarketplaceQueuedRefresh = false
	marketplacePublicListingsInFlight = true
	publicMarketplaceLastRequestAt = now
	setPublicMarketplaceStatus("Loading listings...", nil)
	renderPublicMarketplacePanel()
	marketplaceRequest:FireServer("GetPublicListings", {
		SearchText = ui.publicMarketplaceSearchBox.Text,
		MaxResults = 50,
	})

	local requestStartedAt = publicMarketplaceLastRequestAt

	task.delay(REQUEST_TIMEOUT_SECONDS, function()
		if marketplacePublicListingsInFlight and publicMarketplaceLastRequestAt == requestStartedAt then
			marketplacePublicListingsInFlight = false
			setPublicMarketplaceStatus("Marketplace listings request timed out.", false)
			renderPublicMarketplacePanel()
		end
	end)
end

local function openMyListingsPanel()
	inventoryViewMode = INVENTORY_VIEW_MY_LISTINGS
	setStatus("", nil)
	renderMyListingsPanel()
	requestMyListings()
end

local function openPublicMarketplacePanel()
	inventoryViewMode = INVENTORY_VIEW_MARKETPLACE
	setStatus("", nil)
	renderPublicMarketplacePanel()
	requestPublicMarketplaceListings()
end

local function showInventoryItemsPanel()
	inventoryViewMode = INVENTORY_VIEW_ITEMS
	setMyListingsStatus("", nil)
	setPublicMarketplaceStatus("", nil)
	updateInventoryViewMode()
	updateSelectedItemDetails()
end

cancelMarketplaceListing = function(listingId)
	if typeof(listingId) ~= "string" or listingId == "" then
		setMyListingsStatus("Invalid marketplace listing.", false)
		return
	end

	if marketplaceCancelInFlightByListingId[listingId] then
		return
	end

	marketplaceCancelInFlightByListingId[listingId] = true
	setMyListingsStatus("", nil)
	renderMyListingsPanel()
	marketplaceRequest:FireServer("CancelListing", {
		ListingId = listingId,
	})

	task.delay(REQUEST_TIMEOUT_SECONDS, function()
		if marketplaceCancelInFlightByListingId[listingId] then
			marketplaceCancelInFlightByListingId[listingId] = nil
			setMyListingsStatus("Cancel listing request timed out.", false)
			renderMyListingsPanel()
		end
	end)
end

local function confirmMarketplaceListing()
	if marketplaceCreateInFlight then
		return
	end

	local templateId = marketplaceListingTemplateId
	local maxQuantity = getMarketplaceListingMaxQuantity(templateId)
	local unitPrice, priceMessage = parseListingUnitPrice()

	if typeof(templateId) ~= "string" or templateId == "" then
		setListingModalMessage("Select an item first.", false)
		return
	end

	if maxQuantity <= 0 then
		setListingModalMessage("You do not have enough tradable copies to list.", false)
		return
	end

	if not unitPrice then
		setListingModalMessage(priceMessage, false)
		updateListingModal()
		return
	end

	marketplaceListingQuantity = math.clamp(
		math.floor(marketplaceListingQuantity),
		1,
		maxQuantity
	)
	marketplaceCreateRequestSerial += 1
	marketplaceCreateInFlight = true
	pendingCreateListingRequestId = tostring(marketplaceCreateRequestSerial)
	pendingCreateListingTemplateId = templateId
	pendingCreateListingQuantity = marketplaceListingQuantity
	pendingCreateListingUnitPriceCoins = unitPrice
	setListingModalMessage("Listing item...", nil)
	setStatus("", nil)
	updateListingModal()
	updateSelectedItemDetails()
	marketplaceRequest:FireServer("CreateListing", {
		TemplateId = templateId,
		Quantity = marketplaceListingQuantity,
		UnitPriceCoins = unitPrice,
		RequestId = pendingCreateListingRequestId,
	})

	local requestId = pendingCreateListingRequestId

	task.delay(REQUEST_TIMEOUT_SECONDS, function()
		if marketplaceCreateInFlight and pendingCreateListingRequestId == requestId then
			marketplaceCreateInFlight = false
			pendingCreateListingRequestId = nil
			pendingCreateListingTemplateId = nil
			pendingCreateListingQuantity = 1
			pendingCreateListingUnitPriceCoins = nil

			if ui.marketplaceModalOverlay.Visible then
				setListingModalMessage("Marketplace listing request timed out.", false)
			else
				setStatus("Marketplace listing request timed out.", false)
			end

			updateListingModal()
			updateSelectedItemDetails()
		end
	end)
end

local function fireInventoryPlacement(templateId)
	local counts = getInventoryCounts(templateId)

	if counts.Total <= 0 then
		setStatus("This item is no longer in your inventory.", false)
		clearPendingPlacementState(false)
		updateSelectedItemDetails()
		return
	end

	pendingPlacementTemplateId = nil
	pendingPlaceAfterEdit = false
	setStatus("Choose a floor tile to place this item.", true)
	inventoryHideRequestedForPlacement = ui.panel.Visible == true

	startInventoryPlacement:Fire({
		Id = templateId,
		TemplateName = templateId,
		DisplayName = getInventoryDisplayName(templateId),
		Source = "Inventory",
	})

	if player:GetAttribute("CatalogPlacementActive") == true and hideInventoryForPlacement then
		hideInventoryForPlacement()
	end

	task.defer(function()
		if player:GetAttribute("CatalogPlacementActive") ~= true
			and inventoryHideRequestedForPlacement
			and not inventoryHiddenForPlacement then

			inventoryHideRequestedForPlacement = false
			updateOpenButton()
		end
	end)

	updateSelectedItemDetails()
end

local function requestPlacementForSelectedItem()
	local entry = getSelectedInventoryEntry()

	if not entry then
		setStatus("Select an item first.", false)
		return
	end

	if not canPlaceInCurrentRoom() then
		setStatus(EDIT_MODE_FAILURE_MESSAGE, false)
		return
	end

	if player:GetAttribute("RoomMode") == "Edit" then
		inventoryPlacementRequestedEditMode = false
		inventoryPlacementEnteredEditMode = false
		inventoryPlacementExitEditRequested = false
		pendingPlaceAfterEdit = false
		fireInventoryPlacement(entry.TemplateId)
		return
	end

	pendingPlacementTemplateId = entry.TemplateId
	pendingPlaceAfterEdit = true
	inventoryPlacementRequestedEditMode = true
	inventoryPlacementEnteredEditMode = false
	inventoryPlacementExitEditRequested = false
	setStatus(EDIT_MODE_PREPARING_MESSAGE, nil)
	updateSelectedItemDetails()
	setRoomModeRequest:FireServer("Edit")
end

local function updateSellQuantity(delta)
	local entry = getSelectedInventoryEntry()

	if not entry or sellRequestInFlight then
		return
	end

	local counts = getInventoryCounts(entry.TemplateId)
	local maxSellQuantity = math.min(counts.Sellable, 99)

	if maxSellQuantity <= 0 then
		selectedSellQuantity = 1
	else
		selectedSellQuantity = math.clamp(selectedSellQuantity + delta, 1, maxSellQuantity)
	end

	updateSelectedItemDetails()
end

local function sellSelectedItem()
	local entry = getSelectedInventoryEntry()

	if not entry or sellRequestInFlight then
		return
	end

	local counts = getInventoryCounts(entry.TemplateId)
	local sellPrice = getInventorySellPrice(entry.TemplateId)
	local maxSellQuantity = math.min(counts.Sellable, 99)

	if counts.Sellable <= 0 or not sellPrice or sellPrice <= 0 then
		setStatus("This item cannot be sold for Dollars.", false)
		return
	end

	selectedSellQuantity = math.clamp(selectedSellQuantity, 1, maxSellQuantity)
	sellRequestInFlight = true
	setStatus("", nil)
	updateSelectedItemDetails()
	inventoryRequest:FireServer("SellInventoryItem", {
		ItemId = entry.TemplateId,
		Quantity = selectedSellQuantity,
	})
end

local requestInventoryRefresh = nil

local function setRequestInFlight(isInFlight)
	requestInFlight = isInFlight
end

local function queueInventoryRefresh(reason, delaySeconds, force)
	if refreshQueued then
		queuedRefreshForce = queuedRefreshForce or force == true
		return
	end

	refreshQueued = true
	queuedRefreshForce = force == true

	task.delay(delaySeconds, function()
		refreshQueued = false
		local shouldForce = queuedRefreshForce
		queuedRefreshForce = false

		if requestInventoryRefresh then
			requestInventoryRefresh(reason or "queued", shouldForce)
		end
	end)
end

requestInventoryRefresh = function(reason, force)
	if requestInFlight then
		queueInventoryRefresh(reason, LOCAL_REQUEST_COOLDOWN_SECONDS, force)
		return
	end

	local now = os.clock()
	local elapsed = now - lastInventoryRequestAt

	if elapsed < LOCAL_REQUEST_COOLDOWN_SECONDS then
		queueInventoryRefresh(
			reason,
			LOCAL_REQUEST_COOLDOWN_SECONDS - elapsed + 0.05,
			force
		)
		return
	end

	setRequestInFlight(true)
	lastInventoryRequestAt = now
	requestSerial += 1

	local thisRequestSerial = requestSerial

	inventoryRequest:FireServer("GetInventory")

	task.delay(REQUEST_TIMEOUT_SECONDS, function()
		if requestInFlight and requestSerial == thisRequestSerial then
			setRequestInFlight(false)
			setStatus("Inventory request timed out.", false)
		end
	end)
end

setPanelVisible = function(isVisible, options)
	local wasVisible = ui.panel.Visible
	local preserveInventoryView = typeof(options) == "table" and options.PreserveInventoryView == true
	local skipInventoryRefresh = typeof(options) == "table" and options.SkipInventoryRefresh == true

	if isVisible then
		if not wasVisible and not preserveInventoryView then
			selectedInventoryCategory = INVENTORY_CATEGORY_ALL
			inventoryViewMode = INVENTORY_VIEW_ITEMS
			setDropdownOpen(false)
		elseif not wasVisible then
			setDropdownOpen(false)
		end

		publishMajorMenuState(true)
		majorMenuOpened:Fire(MENU_NAME)
	end

	ui.panel.Visible = isVisible
	updateOpenButton()

	if isVisible then
		inventoryHideRequestedForPlacement = false
		inventoryHiddenForPlacement = false
		clampPanelToScreen()

		if hasLoadedInventory then
			renderInventory(latestInventory, latestInventoryDetails)
		else
			updateInventoryViewMode()
		end

		if not skipInventoryRefresh then
			requestInventoryRefresh("open")
		end
	elseif wasVisible or openMajorMenuName == MENU_NAME then
		if not marketplaceCreateInFlight then
			ui.marketplaceModalOverlay.Visible = false
			marketplaceListingTemplateId = nil
			marketplaceListingQuantity = 1
		end

		clearPendingPlacementState(false)
		inventoryHideRequestedForPlacement = false
		inventoryHiddenForPlacement = false
		setDropdownOpen(false)
		publishMajorMenuState(false)
		requestPlayModeIfInventoryCausedEdit()
	end
end

hideInventoryForPlacement = function()
	if inventoryHiddenForPlacement
		or not inventoryHideRequestedForPlacement
		or not ui.panel.Visible then

		return
	end

	inventoryHiddenForPlacement = true
	ui.panel.Visible = false
	setDropdownOpen(false)
	publishMajorMenuState(false)
	updateOpenButton()
end

restoreInventoryAfterPlacement = function()
	if not inventoryHiddenForPlacement then
		inventoryHideRequestedForPlacement = false
		updateOpenButton()
		return
	end

	inventoryHiddenForPlacement = false
	inventoryHideRequestedForPlacement = false
	setPanelVisible(true, {
		PreserveInventoryView = true,
		SkipInventoryRefresh = true,
	})

	if renderInventory then
		renderInventory(latestInventory, latestInventoryDetails)
	end

	if os.clock() - lastInventoryCacheUpdateAt > RESTORE_REFRESH_STALE_SECONDS then
		queueInventoryRefresh("placementFinished", LOCAL_REQUEST_COOLDOWN_SECONDS, false)
	end
end

ui.openButton.MouseButton1Click:Connect(function()
	setPanelVisible(true)
end)

ui.closeButton.MouseButton1Click:Connect(function()
	setPanelVisible(false)
end)

ui.categoryButton.MouseButton1Click:Connect(function()
	setDropdownOpen(not dropdownOpen)
end)

ui.placeButton.MouseButton1Click:Connect(requestPlacementForSelectedItem)

ui.sellDecreaseButton.MouseButton1Click:Connect(function()
	updateSellQuantity(-1)
end)

ui.sellIncreaseButton.MouseButton1Click:Connect(function()
	updateSellQuantity(1)
end)

ui.sellButton.MouseButton1Click:Connect(sellSelectedItem)

ui.marketplaceButton.MouseButton1Click:Connect(openMarketplaceListingModal)

ui.myListingsButton.MouseButton1Click:Connect(openMyListingsPanel)

ui.myListingsBackButton.MouseButton1Click:Connect(showInventoryItemsPanel)

ui.publicMarketplaceBackButton.MouseButton1Click:Connect(showInventoryItemsPanel)

ui.myListingsRefreshButton.MouseButton1Click:Connect(function()
	if inventoryViewMode ~= INVENTORY_VIEW_MY_LISTINGS then
		inventoryViewMode = INVENTORY_VIEW_MY_LISTINGS
		renderMyListingsPanel()
	end

	requestMyListings({
		Queue = true,
	})
end)

ui.publicMarketplaceRefreshButton.MouseButton1Click:Connect(function()
	if inventoryViewMode ~= INVENTORY_VIEW_MARKETPLACE then
		inventoryViewMode = INVENTORY_VIEW_MARKETPLACE
		renderPublicMarketplacePanel()
	end

	requestPublicMarketplaceListings({
		Queue = true,
	})
end)

ui.publicMarketplaceSearchBox.FocusLost:Connect(function(enterPressed)
	if enterPressed and inventoryViewMode == INVENTORY_VIEW_MARKETPLACE then
		requestPublicMarketplaceListings({
			Queue = true,
		})
	end
end)

ui.listingQuantityDecreaseButton.MouseButton1Click:Connect(function()
	updateMarketplaceListingQuantity(-1)
end)

ui.listingQuantityIncreaseButton.MouseButton1Click:Connect(function()
	updateMarketplaceListingQuantity(1)
end)

ui.unitPriceTextBox:GetPropertyChangedSignal("Text"):Connect(updateListingModal)

ui.listingCancelButton.MouseButton1Click:Connect(closeMarketplaceListingModal)

ui.listingConfirmButton.MouseButton1Click:Connect(confirmMarketplaceListing)

inventoryRefreshRequested.Event:Connect(function(options)
	local reason = "event"
	local force = false

	if typeof(options) == "table" then
		if typeof(options.Reason) == "string" and options.Reason ~= "" then
			reason = options.Reason
		end

		force = options.Force == true or options.Priority == true
	elseif typeof(options) == "string" and options ~= "" then
		reason = options
	end

	if reason == "event"
		and force == false
		and os.clock() - lastInventoryCacheUpdateAt < LOCAL_DELTA_REFRESH_SUPPRESS_SECONDS then

		return
	end

	requestInventoryRefresh(reason, force)
end)

inventoryLocalDelta.Event:Connect(function(payload)
	applyInventoryLocalDelta(payload)
end)

roomModeResult.OnClientEvent:Connect(function(success, message, roomMode)
	if not pendingPlacementTemplateId then
		return
	end

	if success == true or roomMode == "Edit" then
		if inventoryPlacementRequestedEditMode then
			inventoryPlacementEnteredEditMode = true
		end

		pendingPlaceAfterEdit = false
		fireInventoryPlacement(pendingPlacementTemplateId)
		return
	end

	clearPendingPlacementState(true)

	message = tostring(message or "")

	if message == "Slow down before changing room mode." then
		warn(message)
		return
	end

	if ui.panel.Visible then
		setStatus(EDIT_MODE_FAILURE_MESSAGE, false)
		updateSelectedItemDetails()
	end
end)

player:GetAttributeChangedSignal("RoomMode"):Connect(function()
	if pendingPlacementTemplateId and player:GetAttribute("RoomMode") == "Edit" then
		if inventoryPlacementRequestedEditMode then
			inventoryPlacementEnteredEditMode = true
		end

		pendingPlaceAfterEdit = false
		fireInventoryPlacement(pendingPlacementTemplateId)
	elseif player:GetAttribute("RoomMode") ~= "Edit" then
		inventoryPlacementRequestedEditMode = false
		inventoryPlacementEnteredEditMode = false
		inventoryPlacementExitEditRequested = false
	end
end)

player:GetAttributeChangedSignal("CatalogPlacementActive"):Connect(function()
	if player:GetAttribute("CatalogPlacementActive") == true then
		if hideInventoryForPlacement then
			hideInventoryForPlacement()
		end
	elseif restoreInventoryAfterPlacement then
		restoreInventoryAfterPlacement()
	end

	updateOpenButton()
end)

majorMenuOpened.Event:Connect(function(menuName)
	if menuName ~= MENU_NAME and ui.panel.Visible then
		setPanelVisible(false)
	end
end)

closeMajorMenus.Event:Connect(function()
	if ui.panel.Visible then
		setPanelVisible(false)
	end
end)

majorMenuStateChanged.Event:Connect(function(isOpen, menuName)
	setLocalMajorMenuState(isOpen == true, menuName)
end)

marketplaceResult.OnClientEvent:Connect(function(response)
	if typeof(response) ~= "table" then
		return
	end

	local kind = response.Kind
	local success = response.Success == true
	local message = tostring(response.Message or "")

	if kind == "CreateListing" then
		local listing = response.Listing
		local responseRequestId = response.RequestId

		if pendingCreateListingRequestId
			and responseRequestId ~= nil
			and tostring(responseRequestId) ~= pendingCreateListingRequestId then

			return
		end

		local templateId = pendingCreateListingTemplateId or marketplaceListingTemplateId
		local quantity = pendingCreateListingQuantity or marketplaceListingQuantity
		local unitPriceCoins = pendingCreateListingUnitPriceCoins

		if typeof(listing) == "table" then
			if typeof(listing.TemplateId) == "string" and listing.TemplateId ~= "" then
				templateId = listing.TemplateId
			end

			if typeof(listing.Quantity) == "number" then
				quantity = math.floor(listing.Quantity)
			end

			if typeof(listing.UnitPriceCoins) == "number" then
				unitPriceCoins = math.floor(listing.UnitPriceCoins)
			end
		end

		if not unitPriceCoins then
			unitPriceCoins = parseListingUnitPrice()
		end

		marketplaceCreateInFlight = false
		pendingCreateListingRequestId = nil
		pendingCreateListingTemplateId = nil
		pendingCreateListingQuantity = 1
		pendingCreateListingUnitPriceCoins = nil

		if success then
			applyMarketplaceInventoryDetails(templateId, response.InventoryDetails)
			ui.marketplaceModalOverlay.Visible = false
			marketplaceListingTemplateId = nil
			marketplaceListingQuantity = 1
			setListingModalMessage("", nil)

			if typeof(listing) == "table" then
				upsertMarketplaceListing(listing)
			end

			local listedMessage = "Listed "
				.. getInventoryDisplayName(templateId)
				.. " x" .. tostring(quantity or 1)
				.. " for " .. tostring(unitPriceCoins or 0)
				.. " Coins."

			setStatus(listedMessage, true)
			inventoryRefreshRequested:Fire({
				Reason = "CreateListing",
				Force = true,
			})

			if inventoryViewMode == INVENTORY_VIEW_MY_LISTINGS then
				renderMyListingsPanel()
				task.delay(0.6, function()
					if inventoryViewMode == INVENTORY_VIEW_MY_LISTINGS and requestMyListings then
						requestMyListings({
							Queue = true,
						})
					end
				end)
			elseif inventoryViewMode == INVENTORY_VIEW_MARKETPLACE then
				renderPublicMarketplacePanel()
				task.delay(0.6, function()
					if inventoryViewMode == INVENTORY_VIEW_MARKETPLACE and requestPublicMarketplaceListings then
						requestPublicMarketplaceListings({
							Queue = true,
						})
					end
				end)
			end
		else
			applyMarketplaceInventoryDetails(templateId, response.InventoryDetails)
			local errorMessage = message ~= "" and message or "Could not create marketplace listing."

			if ui.marketplaceModalOverlay.Visible then
				setListingModalMessage(errorMessage, false)
			else
				setStatus(errorMessage, false)
			end
		end

		updateListingModal()
		updateSelectedItemDetails()
		return
	end

	if kind == "MyListings" or kind == "GetMyListings" then
		marketplaceMyListingsInFlight = false
		local shouldRunQueuedRefresh = myListingsQueuedRefresh == true

		if success then
			latestMarketplaceListings = typeof(response.Listings) == "table"
				and response.Listings
				or {}
			setMyListingsStatus("", nil)
		else
			shouldRunQueuedRefresh = false
			myListingsQueuedRefresh = false

			local errorMessage = getMarketplaceWaitMessage(message)

			if errorMessage == "" then
				errorMessage = "Could not load marketplace listings."
			end

			setMyListingsStatus(errorMessage, false)
		end

		renderMyListingsPanel()

		if shouldRunQueuedRefresh then
			scheduleQueuedMyListingsRefresh(
				MY_LISTINGS_LOCAL_COOLDOWN_SECONDS - (os.clock() - myListingsLastRequestAt)
			)
		end

		return
	end

	if kind == "PublicListings" or kind == "GetPublicListings" then
		-- Public marketplace browsing now belongs to the Shop/Catalog UI.
		-- Inventory still owns listing creation and temporary My Listings.
		return
	end

	if kind == "CancelListing" then
		marketplaceCancelInFlightByListingId = {}

		local listing = response.Listing
		local templateId = nil

		if typeof(listing) == "table" then
			if typeof(listing.TemplateId) == "string" and listing.TemplateId ~= "" then
				templateId = listing.TemplateId
			end

			upsertMarketplaceListing(listing)
		end

		if success then
			applyMarketplaceInventoryDetails(templateId, response.InventoryDetails)
			setMyListingsStatus("Listing cancelled.", true)
			setStatus("Listing cancelled.", true)
			inventoryRefreshRequested:Fire({
				Reason = "CancelListing",
				Force = true,
			})

			task.delay(0.6, function()
				if inventoryViewMode == INVENTORY_VIEW_MY_LISTINGS and requestMyListings then
					requestMyListings({
						Queue = true,
					})
				elseif inventoryViewMode == INVENTORY_VIEW_MARKETPLACE and requestPublicMarketplaceListings then
					requestPublicMarketplaceListings({
						Queue = true,
					})
				end
			end)
		else
			setMyListingsStatus(message ~= "" and message or "Could not cancel listing.", false)
		end

		renderMyListingsPanel()
		if inventoryViewMode == INVENTORY_VIEW_MARKETPLACE then
			renderPublicMarketplacePanel()
		end
	end
end)

inventoryResult.OnClientEvent:Connect(function(response)
	if typeof(response) ~= "table" then
		return
	end

	setRequestInFlight(false)

	local success = response.Success == true
	local kind = response.Kind
	local message = tostring(response.Message or "")

	if kind == "SellInventoryItem" then
		sellRequestInFlight = false

		if success then
			local details = response.InventoryDetails
			local localDelta = {
				TemplateId = response.TemplateId,
				Total = response.NewCount,
			}

			if typeof(details) == "table" then
				localDelta.Tradable = details.Tradable
				localDelta.Untradable = details.Untradable
				localDelta.Sellable = details.Sellable
				localDelta.Unsellable = details.Unsellable
			end

			applyInventoryLocalDelta(localDelta)

			if typeof(response.NewCurrencyBalance) == "number" then
				currencyLocalDelta:Fire({
					CurrencyKey = response.CurrencyKey or "Dollars",
					Balance = response.NewCurrencyBalance,
				})
			end

			local soldMessage = "Sold " .. tostring(response.TemplateId or response.ItemId or "item")
				.. " x" .. tostring(response.Quantity or 1)
				.. " for " .. tostring(response.TotalDollars or 0) .. " Dollars."

			setStatus(soldMessage, true)
			inventoryRefreshRequested:Fire({
				Reason = "SellInventoryItem",
				Force = true,
			})
			currencyRefreshRequested:Fire({
				Reason = "SellInventoryItem",
				Force = true,
			})
		else
			if message:find("Slow down", 1, true) then
				message = "Please wait a moment."
			end

			setStatus(message ~= "" and message or "Could not sell item.", false)

			if ui.panel.Visible then
				renderInventory(latestInventory, latestInventoryDetails)
			end
		end

		return
	end

	if success and typeof(response.Inventory) == "table" then
		hasLoadedInventory = true
		renderInventory(response.Inventory, response.InventoryDetails)

		if ui.statusLabel.Text ~= EDIT_MODE_FAILURE_MESSAGE
			and ui.statusLabel.Text ~= EDIT_MODE_PREPARING_MESSAGE then

			setStatus("", nil)
		end
	elseif message == "Slow down before requesting inventory." then
		queueInventoryRefresh("serverCooldown", LOCAL_REQUEST_COOLDOWN_SECONDS + 0.25, false)
	else
		setStatus(message ~= "" and message or "Could not load inventory.", false)
	end
end)

local function handleVisibilityChanged()
	if ui.panel.Visible and not shouldShowInventoryButton() then
		setPanelVisible(false)
	else
		updateOpenButton()
	end
end

player:GetAttributeChangedSignal("OnboardingStep"):Connect(handleVisibilityChanged)
player:GetAttributeChangedSignal("ControlMode"):Connect(function()
	if (player:GetAttribute("ControlMode") or "Hotel") ~= "Hotel" then
		clearPlacementFlowForRoomChange()
	end

	handleVisibilityChanged()
end)
player:GetAttributeChangedSignal("CurrentRoomName"):Connect(function()
	clearPlacementFlowForRoomChange()
	handleVisibilityChanged()
end)
player:GetAttributeChangedSignal("CanEditCurrentRoom"):Connect(function()
	if not canPlaceInCurrentRoom() then
		requestPlayModeIfInventoryCausedEdit()
		clearPendingPlacementState(true)
		updateSelectedItemDetails()
	end
end)

renderInventory({})
task.defer(updateOpenButton)
