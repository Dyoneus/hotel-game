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
local GridConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GridConfig"))

local activeRooms = workspace:WaitForChild("ActiveRooms")
local furnitureTemplates = ReplicatedStorage:WaitForChild("FurnitureTemplates")

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 160

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
local catalogViewMode = "Shop"
local marketplaceViewMode = "Offers"
local categoryButtons = {}
local latestPublicMarketplaceListings = {}
local latestMySalesListings = {}
local marketplacePublicListingsInFlight = false
local marketplaceMySalesInFlight = false
local marketplaceCancelInFlightByListingId = {}
local marketplacePurchaseInFlightByListingId = {}
local marketplacePurchaseListing = nil
local marketplacePurchaseRequestInFlight = false
local marketplacePurchaseRequestSerial = 0
local pendingPurchaseRequestId = nil
local pendingPurchaseListingId = nil
local marketplaceLastRequestAt = -math.huge
local publicMarketplaceLastRequestAt = -math.huge
local mySalesLastRequestAt = -math.huge
local publicMarketplaceQueuedRefresh = false
local mySalesQueuedRefresh = false
local publicMarketplaceQueuedRefreshScheduled = false
local mySalesQueuedRefreshScheduled = false

local CATEGORY_ORDER = {
	"All",
	"Featured",
	"Chairs",
	"Tables",
	"Beds",
}

local CATALOG_VIEW_SHOP = "Shop"
local CATALOG_VIEW_MARKETPLACE = "Marketplace"
local MARKETPLACE_VIEW_OFFERS = "Offers"
local MARKETPLACE_VIEW_MY_SALES = "MySales"
local MARKETPLACE_REQUEST_COOLDOWN_SECONDS = 0.7
local REQUEST_TIMEOUT_SECONDS = 6

local updateOpenButton = nil
local destroyCatalogPlacementPreview = nil
local renderCatalog = nil
local renderMarketplace = nil
local requestMarketplaceOffers = nil
local requestMarketplaceMySales = nil
local cancelMarketplaceSale = nil
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

local openButton = Instance.new("TextButton")
openButton.Name = "OpenFurnitureCatalogButton"
openButton.AnchorPoint = Vector2.new(1, 1)
openButton.Position = UDim2.new(1, -20, 1, -74)
openButton.Size = UDim2.fromOffset(150, 44)
openButton.BackgroundColor3 = Color3.fromRGB(60, 110, 170)
openButton.BorderSizePixel = 0
openButton.Text = "Shop"
openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
openButton.TextScaled = true
openButton.Font = Enum.Font.GothamBold
openButton.Visible = false
openButton.Parent = gui

createCorner(openButton, 10)
createStroke(openButton, Color3.fromRGB(255, 255, 255), 1, 0.25)

local panel = Instance.new("Frame")
panel.Name = "FurnitureCatalogPanel"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -24, 0.5, 0)
panel.Size = UDim2.fromOffset(390, 500)
panel.BackgroundColor3 = Color3.fromRGB(245, 245, 238)
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

createCorner(panel, 16)
createStroke(panel, Color3.fromRGB(255, 255, 255), 2, 0.1)

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Position = UDim2.fromOffset(18, 14)
titleLabel.Size = UDim2.new(1, -70, 0, 36)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Furniture Shop"
titleLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
titleLabel.TextScaled = true
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -18, 0, 18)
closeButton.Size = UDim2.fromOffset(34, 34)
closeButton.BackgroundColor3 = Color3.fromRGB(160, 70, 70)
closeButton.BorderSizePixel = 0
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.TextScaled = true
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = panel

createCorner(closeButton, 8)

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Position = UDim2.fromOffset(18, 56)
statusLabel.Size = UDim2.new(1, -36, 0, 42)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Choose furniture to add to your Inventory."
statusLabel.TextColor3 = Color3.fromRGB(90, 90, 90)
statusLabel.TextWrapped = true
statusLabel.TextScaled = true
statusLabel.Font = Enum.Font.Gotham
statusLabel.Parent = panel

local sectionFrame = Instance.new("Frame")
sectionFrame.Name = "ShopSectionTabs"
sectionFrame.Position = UDim2.fromOffset(18, 104)
sectionFrame.Size = UDim2.new(1, -36, 0, 30)
sectionFrame.BackgroundTransparency = 1
sectionFrame.Parent = panel

local sectionLayout = Instance.new("UIListLayout")
sectionLayout.FillDirection = Enum.FillDirection.Horizontal
sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
sectionLayout.Padding = UDim.new(0, 6)
sectionLayout.Parent = sectionFrame

local shopSectionButton = Instance.new("TextButton")
shopSectionButton.Name = "ShopSectionButton"
shopSectionButton.LayoutOrder = 1
shopSectionButton.Size = UDim2.fromOffset(86, 28)
shopSectionButton.BorderSizePixel = 0
shopSectionButton.Text = "Shop"
shopSectionButton.TextSize = 13
shopSectionButton.Font = Enum.Font.GothamBold
shopSectionButton.Parent = sectionFrame

createCorner(shopSectionButton, 7)

local marketplaceSectionButton = Instance.new("TextButton")
marketplaceSectionButton.Name = "MarketplaceSectionButton"
marketplaceSectionButton.LayoutOrder = 2
marketplaceSectionButton.Size = UDim2.fromOffset(116, 28)
marketplaceSectionButton.BorderSizePixel = 0
marketplaceSectionButton.Text = "Marketplace"
marketplaceSectionButton.TextSize = 13
marketplaceSectionButton.Font = Enum.Font.GothamBold
marketplaceSectionButton.Parent = sectionFrame

createCorner(marketplaceSectionButton, 7)

local categoryFrame = Instance.new("Frame")
categoryFrame.Name = "CategoryTabs"
categoryFrame.Position = UDim2.fromOffset(18, 140)
categoryFrame.Size = UDim2.new(1, -36, 0, 32)
categoryFrame.BackgroundTransparency = 1
categoryFrame.Parent = panel

local categoryLayout = Instance.new("UIListLayout")
categoryLayout.FillDirection = Enum.FillDirection.Horizontal
categoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
categoryLayout.Padding = UDim.new(0, 6)
categoryLayout.Parent = categoryFrame

local marketplaceTabsFrame = Instance.new("Frame")
marketplaceTabsFrame.Name = "MarketplaceTabs"
marketplaceTabsFrame.Position = UDim2.fromOffset(18, 140)
marketplaceTabsFrame.Size = UDim2.new(1, -36, 0, 32)
marketplaceTabsFrame.BackgroundTransparency = 1
marketplaceTabsFrame.Visible = false
marketplaceTabsFrame.Parent = panel

local marketplaceTabsLayout = Instance.new("UIListLayout")
marketplaceTabsLayout.FillDirection = Enum.FillDirection.Horizontal
marketplaceTabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
marketplaceTabsLayout.Padding = UDim.new(0, 6)
marketplaceTabsLayout.Parent = marketplaceTabsFrame

local marketplaceOffersButton = Instance.new("TextButton")
marketplaceOffersButton.Name = "MarketplaceOffersButton"
marketplaceOffersButton.LayoutOrder = 1
marketplaceOffersButton.Size = UDim2.fromOffset(78, 30)
marketplaceOffersButton.BorderSizePixel = 0
marketplaceOffersButton.Text = "Offers"
marketplaceOffersButton.TextSize = 13
marketplaceOffersButton.Font = Enum.Font.GothamBold
marketplaceOffersButton.Parent = marketplaceTabsFrame

createCorner(marketplaceOffersButton, 8)

local marketplaceMySalesButton = Instance.new("TextButton")
marketplaceMySalesButton.Name = "MarketplaceMySalesButton"
marketplaceMySalesButton.LayoutOrder = 2
marketplaceMySalesButton.Size = UDim2.fromOffset(86, 30)
marketplaceMySalesButton.BorderSizePixel = 0
marketplaceMySalesButton.Text = "My Sales"
marketplaceMySalesButton.TextSize = 13
marketplaceMySalesButton.Font = Enum.Font.GothamBold
marketplaceMySalesButton.Parent = marketplaceTabsFrame

createCorner(marketplaceMySalesButton, 8)

local marketplaceRefreshButton = Instance.new("TextButton")
marketplaceRefreshButton.Name = "MarketplaceRefreshButton"
marketplaceRefreshButton.LayoutOrder = 3
marketplaceRefreshButton.Size = UDim2.fromOffset(72, 30)
marketplaceRefreshButton.BackgroundColor3 = Color3.fromRGB(70, 135, 90)
marketplaceRefreshButton.BorderSizePixel = 0
marketplaceRefreshButton.Text = "Refresh"
marketplaceRefreshButton.TextColor3 = Color3.fromRGB(255, 255, 255)
marketplaceRefreshButton.TextSize = 12
marketplaceRefreshButton.Font = Enum.Font.GothamBold
marketplaceRefreshButton.Parent = marketplaceTabsFrame

createCorner(marketplaceRefreshButton, 8)

local marketplaceSearchBox = Instance.new("TextBox")
marketplaceSearchBox.Name = "MarketplaceSearchBox"
marketplaceSearchBox.Position = UDim2.fromOffset(18, 178)
marketplaceSearchBox.Size = UDim2.new(1, -36, 0, 30)
marketplaceSearchBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
marketplaceSearchBox.BorderSizePixel = 0
marketplaceSearchBox.ClearTextOnFocus = false
marketplaceSearchBox.PlaceholderText = "Search marketplace"
marketplaceSearchBox.Text = ""
marketplaceSearchBox.TextColor3 = Color3.fromRGB(40, 40, 40)
marketplaceSearchBox.PlaceholderColor3 = Color3.fromRGB(135, 135, 135)
marketplaceSearchBox.TextSize = 13
marketplaceSearchBox.TextXAlignment = Enum.TextXAlignment.Left
marketplaceSearchBox.Font = Enum.Font.Gotham
marketplaceSearchBox.Visible = false
marketplaceSearchBox.Parent = panel

createCorner(marketplaceSearchBox, 8)
createStroke(marketplaceSearchBox, Color3.fromRGB(220, 220, 220), 1, 0)

local placementHintLabel = Instance.new("TextLabel")
placementHintLabel.Name = "PlacementHintLabel"
placementHintLabel.AnchorPoint = Vector2.new(0.5, 1)
placementHintLabel.Position = UDim2.new(0.5, 0, 1, -24)
placementHintLabel.Size = UDim2.fromOffset(560, 46)
placementHintLabel.BackgroundColor3 = Color3.fromRGB(35, 45, 60)
placementHintLabel.BackgroundTransparency = 0.08
placementHintLabel.BorderSizePixel = 0
placementHintLabel.Text = ""
placementHintLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
placementHintLabel.TextScaled = true
placementHintLabel.TextWrapped = true
placementHintLabel.Font = Enum.Font.GothamBold
placementHintLabel.Visible = false
placementHintLabel.Parent = gui

createCorner(placementHintLabel, 12)
createStroke(placementHintLabel, Color3.fromRGB(255, 255, 255), 1, 0.35)

local itemList = Instance.new("ScrollingFrame")
itemList.Name = "ItemList"
itemList.Position = UDim2.fromOffset(18, 184)
itemList.Size = UDim2.new(1, -36, 1, -204)
itemList.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
itemList.BorderSizePixel = 0
itemList.ScrollBarThickness = 6
itemList.CanvasSize = UDim2.fromOffset(0, 0)
itemList.Parent = panel

createCorner(itemList, 12)
createStroke(itemList, Color3.fromRGB(220, 220, 220), 1, 0)

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = itemList

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 10)
listPadding.PaddingBottom = UDim.new(0, 10)
listPadding.PaddingLeft = UDim.new(0, 10)
listPadding.PaddingRight = UDim.new(0, 10)
listPadding.Parent = itemList

local marketplacePurchaseOverlay = Instance.new("Frame")
marketplacePurchaseOverlay.Name = "MarketplacePurchaseOverlay"
marketplacePurchaseOverlay.Position = UDim2.fromOffset(0, 0)
marketplacePurchaseOverlay.Size = UDim2.fromScale(1, 1)
marketplacePurchaseOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
marketplacePurchaseOverlay.BackgroundTransparency = 0.45
marketplacePurchaseOverlay.BorderSizePixel = 0
marketplacePurchaseOverlay.Visible = false
marketplacePurchaseOverlay.ZIndex = 80
marketplacePurchaseOverlay.Parent = panel

local marketplacePurchaseWindow = Instance.new("Frame")
marketplacePurchaseWindow.Name = "MarketplacePurchaseConfirm"
marketplacePurchaseWindow.AnchorPoint = Vector2.new(0.5, 0.5)
marketplacePurchaseWindow.Position = UDim2.fromScale(0.5, 0.5)
marketplacePurchaseWindow.Size = UDim2.fromOffset(322, 188)
marketplacePurchaseWindow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
marketplacePurchaseWindow.BorderSizePixel = 0
marketplacePurchaseWindow.ZIndex = 81
marketplacePurchaseWindow.Parent = marketplacePurchaseOverlay

createCorner(marketplacePurchaseWindow, 12)
createStroke(marketplacePurchaseWindow, Color3.fromRGB(210, 215, 220), 1, 0)

local marketplacePurchaseTitle = Instance.new("TextLabel")
marketplacePurchaseTitle.Name = "PurchaseTitle"
marketplacePurchaseTitle.Position = UDim2.fromOffset(16, 14)
marketplacePurchaseTitle.Size = UDim2.new(1, -32, 0, 26)
marketplacePurchaseTitle.BackgroundTransparency = 1
marketplacePurchaseTitle.Text = "Buy Marketplace Item"
marketplacePurchaseTitle.TextColor3 = Color3.fromRGB(40, 40, 40)
marketplacePurchaseTitle.TextSize = 18
marketplacePurchaseTitle.TextXAlignment = Enum.TextXAlignment.Left
marketplacePurchaseTitle.Font = Enum.Font.GothamBold
marketplacePurchaseTitle.ZIndex = 82
marketplacePurchaseTitle.Parent = marketplacePurchaseWindow

local marketplacePurchaseMessage = Instance.new("TextLabel")
marketplacePurchaseMessage.Name = "PurchaseMessage"
marketplacePurchaseMessage.Position = UDim2.fromOffset(16, 48)
marketplacePurchaseMessage.Size = UDim2.new(1, -32, 0, 54)
marketplacePurchaseMessage.BackgroundTransparency = 1
marketplacePurchaseMessage.Text = ""
marketplacePurchaseMessage.TextColor3 = Color3.fromRGB(70, 70, 70)
marketplacePurchaseMessage.TextSize = 14
marketplacePurchaseMessage.TextWrapped = true
marketplacePurchaseMessage.TextXAlignment = Enum.TextXAlignment.Left
marketplacePurchaseMessage.Font = Enum.Font.Gotham
marketplacePurchaseMessage.ZIndex = 82
marketplacePurchaseMessage.Parent = marketplacePurchaseWindow

local marketplacePurchaseStatus = Instance.new("TextLabel")
marketplacePurchaseStatus.Name = "PurchaseStatus"
marketplacePurchaseStatus.Position = UDim2.fromOffset(16, 106)
marketplacePurchaseStatus.Size = UDim2.new(1, -32, 0, 24)
marketplacePurchaseStatus.BackgroundTransparency = 1
marketplacePurchaseStatus.Text = ""
marketplacePurchaseStatus.TextColor3 = Color3.fromRGB(85, 85, 85)
marketplacePurchaseStatus.TextSize = 12
marketplacePurchaseStatus.TextXAlignment = Enum.TextXAlignment.Left
marketplacePurchaseStatus.TextTruncate = Enum.TextTruncate.AtEnd
marketplacePurchaseStatus.Font = Enum.Font.Gotham
marketplacePurchaseStatus.ZIndex = 82
marketplacePurchaseStatus.Parent = marketplacePurchaseWindow

local marketplacePurchaseCancelButton = Instance.new("TextButton")
marketplacePurchaseCancelButton.Name = "PurchaseCancelButton"
marketplacePurchaseCancelButton.Position = UDim2.new(1, -160, 1, -44)
marketplacePurchaseCancelButton.Size = UDim2.fromOffset(64, 30)
marketplacePurchaseCancelButton.BackgroundColor3 = Color3.fromRGB(235, 238, 242)
marketplacePurchaseCancelButton.BorderSizePixel = 0
marketplacePurchaseCancelButton.Text = "Cancel"
marketplacePurchaseCancelButton.TextColor3 = Color3.fromRGB(45, 45, 45)
marketplacePurchaseCancelButton.TextSize = 12
marketplacePurchaseCancelButton.Font = Enum.Font.GothamBold
marketplacePurchaseCancelButton.ZIndex = 82
marketplacePurchaseCancelButton.Parent = marketplacePurchaseWindow

createCorner(marketplacePurchaseCancelButton, 7)

local marketplacePurchaseConfirmButton = Instance.new("TextButton")
marketplacePurchaseConfirmButton.Name = "PurchaseConfirmButton"
marketplacePurchaseConfirmButton.Position = UDim2.new(1, -88, 1, -44)
marketplacePurchaseConfirmButton.Size = UDim2.fromOffset(72, 30)
marketplacePurchaseConfirmButton.BackgroundColor3 = Color3.fromRGB(70, 150, 255)
marketplacePurchaseConfirmButton.BorderSizePixel = 0
marketplacePurchaseConfirmButton.Text = "Confirm"
marketplacePurchaseConfirmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
marketplacePurchaseConfirmButton.TextSize = 12
marketplacePurchaseConfirmButton.Font = Enum.Font.GothamBold
marketplacePurchaseConfirmButton.ZIndex = 82
marketplacePurchaseConfirmButton.Parent = marketplacePurchaseWindow

createCorner(marketplacePurchaseConfirmButton, 7)

local function setPanelVisible(isVisible)
	local wasVisible = panel.Visible

	if isVisible then
		publishMajorMenuState(true)
		majorMenuOpened:Fire(MENU_NAME)
	end

	panel.Visible = isVisible

	if updateOpenButton then
		updateOpenButton()
	else
		openButton.Visible = (not isVisible)
			and not anyMajorMenuOpen
			and shouldShowCatalogButton()
	end

	if not isVisible and (wasVisible or openMajorMenuName == MENU_NAME) then
		publishMajorMenuState(false)
	end
end

local function setStatus(text)
	statusLabel.Text = tostring(text or "")
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

local function updateCatalogChrome()
	local showingMarketplace = catalogViewMode == CATALOG_VIEW_MARKETPLACE
	local showingOffers = marketplaceViewMode == MARKETPLACE_VIEW_OFFERS
	local marketplaceBusy = showingOffers
		and marketplacePublicListingsInFlight
		or marketplaceMySalesInFlight

	titleLabel.Text = showingMarketplace and "Marketplace" or "Furniture Shop"
	categoryFrame.Visible = not showingMarketplace
	marketplaceTabsFrame.Visible = showingMarketplace
	marketplaceSearchBox.Visible = showingMarketplace and showingOffers

	if showingMarketplace and showingOffers then
		itemList.Position = UDim2.fromOffset(18, 218)
		itemList.Size = UDim2.new(1, -36, 1, -238)
	else
		itemList.Position = UDim2.fromOffset(18, 184)
		itemList.Size = UDim2.new(1, -36, 1, -204)
	end

	styleToggleButton(shopSectionButton, not showingMarketplace)
	styleToggleButton(marketplaceSectionButton, showingMarketplace)
	styleToggleButton(marketplaceOffersButton, showingMarketplace and showingOffers)
	styleToggleButton(marketplaceMySalesButton, showingMarketplace and marketplaceViewMode == MARKETPLACE_VIEW_MY_SALES)

	marketplaceRefreshButton.Active = not marketplaceBusy
	marketplaceRefreshButton.AutoButtonColor = not marketplaceBusy
	marketplaceRefreshButton.Text = marketplaceBusy and "Loading..." or "Refresh"
	marketplaceRefreshButton.BackgroundColor3 = marketplaceBusy
		and Color3.fromRGB(155, 160, 155)
		or Color3.fromRGB(70, 135, 90)
end

local function setPlacementHint(text)
	text = tostring(text or "")

	placementHintLabel.Text = text
	placementHintLabel.Visible = text ~= ""
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
	openButton.Visible = false

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
	for _, child in ipairs(itemList:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextButton") or child:IsA("TextLabel") then
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

local function categoryHasItems(categoryName, items)
	if categoryName == "All" then
		return true
	end

	for _, itemData in ipairs(items or {}) do
		if categoryName == "Featured" then
			if itemData.Featured == true then
				return true
			end
		elseif itemData.Category == categoryName then
			return true
		end
	end

	return false
end

local function itemMatchesSelectedCategory(itemData)
	if selectedCategory == "All" then
		return true
	end

	if selectedCategory == "Featured" then
		return itemData.Featured == true
	end

	return itemData.Category == selectedCategory
end

local function styleCategoryButton(button, isSelected)
	if isSelected then
		button.BackgroundColor3 = Color3.fromRGB(70, 150, 255)
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
	else
		button.BackgroundColor3 = Color3.fromRGB(235, 238, 242)
		button.TextColor3 = Color3.fromRGB(55, 55, 55)
	end
end

local function clearCategoryButtons()
	for _, child in ipairs(categoryFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	table.clear(categoryButtons)
end

local function updateCategoryTabs(items)
	local availableCategories = {}
	local selectedCategoryAvailable = false

	for _, categoryName in ipairs(CATEGORY_ORDER) do
		if categoryName ~= "Featured" or categoryHasItems(categoryName, items) then
			table.insert(availableCategories, categoryName)

			if selectedCategory == categoryName then
				selectedCategoryAvailable = true
			end
		end
	end

	if not selectedCategoryAvailable then
		selectedCategory = "All"
	end

	clearCategoryButtons()

	for index, categoryName in ipairs(availableCategories) do
		local button = Instance.new("TextButton")
		button.Name = categoryName .. "CategoryButton"
		button.LayoutOrder = index
		button.Size = UDim2.fromOffset(categoryName == "Featured" and 76 or 62, 30)
		button.BorderSizePixel = 0
		button.Text = categoryName
		button.TextSize = 13
		button.Font = Enum.Font.GothamBold
		button.Parent = categoryFrame

		createCorner(button, 8)
		styleCategoryButton(button, selectedCategory == categoryName)

		button.MouseButton1Click:Connect(function()
			if selectedCategory == categoryName then
				return
			end

			selectedCategory = categoryName

			if renderCatalog then
				renderCatalog(latestCatalogItems)
			end
		end)

		categoryButtons[categoryName] = button
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
	emptyLabel.Parent = itemList
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

local function setMarketplacePurchaseStatus(text, isError)
	marketplacePurchaseStatus.Text = tostring(text or "")
	marketplacePurchaseStatus.TextColor3 = isError == true
		and Color3.fromRGB(150, 60, 60)
		or Color3.fromRGB(85, 85, 85)
end

local function closeMarketplacePurchaseModal()
	if marketplacePurchaseRequestInFlight then
		return
	end

	marketplacePurchaseOverlay.Visible = false
	marketplacePurchaseListing = nil
	setMarketplacePurchaseStatus("", false)
end

local function updateMarketplacePurchaseModal()
	local listing = marketplacePurchaseListing
	local isInFlight = marketplacePurchaseRequestInFlight
	local itemName = getMarketplaceListingDisplayName(listing)
	local quantity = typeof(listing) == "table" and listing.Quantity or 0
	local totalPrice = getMarketplaceListingTotalPrice(listing)

	marketplacePurchaseMessage.Text = "Buy "
		.. itemName
		.. " x" .. tostring(quantity)
		.. " for " .. tostring(totalPrice)
		.. " Coins?"
	marketplacePurchaseConfirmButton.Text = isInFlight and "Buying..." or "Confirm"
	marketplacePurchaseConfirmButton.Active = not isInFlight
	marketplacePurchaseConfirmButton.AutoButtonColor = not isInFlight
	marketplacePurchaseConfirmButton.BackgroundColor3 = isInFlight
		and Color3.fromRGB(155, 160, 155)
		or Color3.fromRGB(70, 150, 255)
	marketplacePurchaseCancelButton.Active = not isInFlight
	marketplacePurchaseCancelButton.AutoButtonColor = not isInFlight
end

local function openMarketplacePurchaseModal(listing)
	if typeof(listing) ~= "table" or typeof(listing.ListingId) ~= "string" or listing.ListingId == "" then
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
	marketplacePurchaseOverlay.Visible = true
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
	row.Parent = itemList

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
	row.Parent = itemList

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

local function createMarketplaceSaleRow(listing, layoutOrder)
	local listingId = listing.ListingId
	local quantity = listing.Quantity or 0
	local unitPriceCoins = listing.UnitPriceCoins or 0
	local status = tostring(listing.Status or "Unknown")
	local isActive = status == "Active"
	local isCancelInFlight = marketplaceCancelInFlightByListingId[listingId] == true
	local createdText = formatListingCreatedAt(listing.CreatedAt)

	local row = Instance.new("Frame")
	row.Name = "MarketplaceSaleRow"
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.new(1, -4, 0, 94)
	row.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
	row.BorderSizePixel = 0
	row.Parent = itemList

	createCorner(row, 10)
	createStroke(row, Color3.fromRGB(220, 220, 220), 1, 0)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "SaleName"
	nameLabel.Position = UDim2.fromOffset(12, 8)
	nameLabel.Size = UDim2.new(1, isActive and -120 or -24, 0, 22)
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
	priceLabel.Size = UDim2.new(1, isActive and -120 or -24, 0, 18)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Text = "x" .. tostring(quantity) .. " @ " .. tostring(unitPriceCoins) .. " Coins"
	priceLabel.TextColor3 = Color3.fromRGB(70, 70, 70)
	priceLabel.TextSize = 12
	priceLabel.TextXAlignment = Enum.TextXAlignment.Left
	priceLabel.TextTruncate = Enum.TextTruncate.AtEnd
	priceLabel.Font = Enum.Font.Gotham
	priceLabel.Parent = row

	local listingStatusLabel = Instance.new("TextLabel")
	listingStatusLabel.Name = "SaleStatus"
	listingStatusLabel.Position = UDim2.fromOffset(12, 54)
	listingStatusLabel.Size = UDim2.new(1, isActive and -120 or -24, 0, 18)
	listingStatusLabel.BackgroundTransparency = 1
	listingStatusLabel.Text = createdText ~= "" and (status .. " | " .. createdText) or status
	listingStatusLabel.TextColor3 = isActive and Color3.fromRGB(45, 110, 65) or Color3.fromRGB(105, 105, 105)
	listingStatusLabel.TextSize = 12
	listingStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	listingStatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	listingStatusLabel.Font = Enum.Font.GothamMedium
	listingStatusLabel.Parent = row

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

renderMarketplace = function()
	updateCatalogChrome()
	clearItemRows()

	if marketplaceViewMode == MARKETPLACE_VIEW_OFFERS then
		if marketplacePublicListingsInFlight then
			setStatus("Loading marketplace offers...")
		elseif #latestPublicMarketplaceListings == 0 then
			setStatus("No active marketplace offers.")
			createEmptyCatalogState("No active marketplace offers.")
		else
			setStatus("Browse marketplace offers.")
		end

		for index, listing in ipairs(latestPublicMarketplaceListings) do
			createMarketplaceOfferRow(listing, index)
		end
	else
		if marketplaceMySalesInFlight then
			setStatus("Loading marketplace sales...")
		elseif #latestMySalesListings == 0 then
			setStatus("No marketplace sales yet.")
			createEmptyCatalogState("No marketplace sales yet.")
		else
			setStatus("Manage your marketplace sales.")
		end

		for index, listing in ipairs(latestMySalesListings) do
			createMarketplaceSaleRow(listing, index)
		end
	end

	task.defer(function()
		itemList.CanvasSize = UDim2.fromOffset(
			0,
			listLayout.AbsoluteContentSize.Y + 20
		)
	end)
end

renderCatalog = function(items)
	latestCatalogItems = items or {}
	if catalogViewMode ~= CATALOG_VIEW_SHOP then
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
		itemList.CanvasSize = UDim2.fromOffset(
			0,
			listLayout.AbsoluteContentSize.Y + 20
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
	marketplaceRequest:FireServer("GetPublicListings", {
		SearchText = marketplaceSearchBox.Text,
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
			setStatus("Marketplace sales request timed out.")
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

requestMarketplacePurchase = function()
	if marketplacePurchaseRequestInFlight then
		return
	end

	local listing = marketplacePurchaseListing

	if typeof(listing) ~= "table" or typeof(listing.ListingId) ~= "string" or listing.ListingId == "" then
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

	local listingId = listing.ListingId

	if marketplacePurchaseInFlightByListingId[listingId] then
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
	pendingPurchaseListingId = listingId
	marketplacePurchaseRequestInFlight = true
	marketplacePurchaseInFlightByListingId[listingId] = true
	marketplaceLastRequestAt = now
	setMarketplacePurchaseStatus("Purchasing...", false)
	updateMarketplacePurchaseModal()
	renderMarketplace()
	marketplaceRequest:FireServer("PurchaseListing", {
		ListingId = listingId,
		RequestId = pendingPurchaseRequestId,
	})

	local requestId = pendingPurchaseRequestId

	task.delay(REQUEST_TIMEOUT_SECONDS, function()
		if marketplacePurchaseRequestInFlight and pendingPurchaseRequestId == requestId then
			marketplacePurchaseRequestInFlight = false

			if pendingPurchaseListingId then
				marketplacePurchaseInFlightByListingId[pendingPurchaseListingId] = nil
			end

			pendingPurchaseRequestId = nil
			pendingPurchaseListingId = nil
			setMarketplacePurchaseStatus("Purchase request timed out.", true)
			updateMarketplacePurchaseModal()
			renderMarketplace()
		end
	end)
end

updateOpenButton = function()
	if placingItemData then
		openButton.Visible = false
		return
	end

	if panel.Visible or anyMajorMenuOpen then
		openButton.Visible = false
	else
		openButton.Visible = shouldShowCatalogButton()
	end
end

shopSectionButton.MouseButton1Click:Connect(function()
	if catalogViewMode == CATALOG_VIEW_SHOP then
		return
	end

	catalogViewMode = CATALOG_VIEW_SHOP
	selectedCategory = "All"
	renderCatalog(latestCatalogItems)

	if #latestCatalogItems == 0 then
		setStatus("Loading shop...")
		furnitureCatalogRequest:FireServer("GetCatalog", {})
	end
end)

marketplaceSectionButton.MouseButton1Click:Connect(function()
	catalogViewMode = CATALOG_VIEW_MARKETPLACE
	marketplaceViewMode = MARKETPLACE_VIEW_OFFERS
	renderMarketplace()
	requestMarketplaceOffers({
		Queue = true,
	})
end)

marketplaceOffersButton.MouseButton1Click:Connect(function()
	if marketplaceViewMode == MARKETPLACE_VIEW_OFFERS then
		return
	end

	marketplaceViewMode = MARKETPLACE_VIEW_OFFERS
	renderMarketplace()
	requestMarketplaceOffers({
		Queue = true,
	})
end)

marketplaceMySalesButton.MouseButton1Click:Connect(function()
	if marketplaceViewMode == MARKETPLACE_VIEW_MY_SALES then
		return
	end

	marketplaceViewMode = MARKETPLACE_VIEW_MY_SALES
	renderMarketplace()
	requestMarketplaceMySales({
		Queue = true,
	})
end)

marketplaceRefreshButton.MouseButton1Click:Connect(function()
	if catalogViewMode ~= CATALOG_VIEW_MARKETPLACE then
		return
	end

	if marketplaceViewMode == MARKETPLACE_VIEW_OFFERS then
		requestMarketplaceOffers({
			Queue = true,
		})
	else
		requestMarketplaceMySales({
			Queue = true,
		})
	end
end)

marketplaceSearchBox.FocusLost:Connect(function(enterPressed)
	if enterPressed
		and catalogViewMode == CATALOG_VIEW_MARKETPLACE
		and marketplaceViewMode == MARKETPLACE_VIEW_OFFERS then

		requestMarketplaceOffers({
			Queue = true,
		})
	end
end)

marketplacePurchaseCancelButton.MouseButton1Click:Connect(closeMarketplacePurchaseModal)

marketplacePurchaseConfirmButton.MouseButton1Click:Connect(function()
	if requestMarketplacePurchase then
		requestMarketplacePurchase()
	end
end)

openButton.MouseButton1Click:Connect(function()
	catalogViewMode = CATALOG_VIEW_SHOP
	selectedCategory = "All"
	setPanelVisible(true)
	updateCatalogChrome()
	renderCatalog(latestCatalogItems)
	setStatus("Loading shop...")
	furnitureCatalogRequest:FireServer("GetCatalog", {})
end)

closeButton.MouseButton1Click:Connect(function()
	setPanelVisible(false)
end)

majorMenuOpened.Event:Connect(function(menuName)
	if menuName == MENU_NAME then
		return
	end

	if panel.Visible then
		setPanelVisible(false)
	end

	if placingItemData then
		destroyCatalogPlacementPreview()
	end
end)

closeMajorMenus.Event:Connect(function()
	if panel.Visible then
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

marketplaceResult.OnClientEvent:Connect(function(response)
	if typeof(response) ~= "table" then
		return
	end

	local kind = response.Kind
	local success = response.Success == true
	local message = getMarketplaceWaitMessage(response.Message)

	if kind == "PublicListings" or kind == "GetPublicListings" then
		marketplacePublicListingsInFlight = false
		local shouldRunQueuedRefresh = publicMarketplaceQueuedRefresh == true

		if success then
			latestPublicMarketplaceListings = typeof(response.Listings) == "table"
				and response.Listings
				or {}
			message = ""
		else
			shouldRunQueuedRefresh = false
			publicMarketplaceQueuedRefresh = false

			if message == "" then
				message = "Could not load marketplace offers."
			end
		end

		if catalogViewMode == CATALOG_VIEW_MARKETPLACE
			and marketplaceViewMode == MARKETPLACE_VIEW_OFFERS then

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

	if kind == "MyListings" or kind == "GetMyListings" then
		marketplaceMySalesInFlight = false
		local shouldRunQueuedRefresh = mySalesQueuedRefresh == true

		if success then
			latestMySalesListings = typeof(response.Listings) == "table"
				and response.Listings
				or {}
			message = ""
		else
			shouldRunQueuedRefresh = false
			mySalesQueuedRefresh = false

			if message == "" then
				message = "Could not load marketplace sales."
			end
		end

		if catalogViewMode == CATALOG_VIEW_MARKETPLACE
			and marketplaceViewMode == MARKETPLACE_VIEW_MY_SALES then

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

		if catalogViewMode == CATALOG_VIEW_MARKETPLACE then
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

		return
	end

	if kind == "PurchaseListing" then
		local responseRequestId = response.RequestId

		if pendingPurchaseRequestId
			and responseRequestId ~= nil
			and tostring(responseRequestId) ~= pendingPurchaseRequestId then

			return
		end

		local listing = response.Listing
		local listingId = pendingPurchaseListingId
		local templateId = nil

		if typeof(listing) == "table" then
			listingId = listing.ListingId or listingId
			templateId = listing.TemplateId
		elseif typeof(marketplacePurchaseListing) == "table" then
			templateId = marketplacePurchaseListing.TemplateId
		end

		marketplacePurchaseRequestInFlight = false

		if typeof(listingId) == "string" then
			marketplacePurchaseInFlightByListingId[listingId] = nil
		end

		pendingPurchaseRequestId = nil
		pendingPurchaseListingId = nil

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
			marketplacePurchaseOverlay.Visible = false
			marketplacePurchaseListing = nil
			setMarketplacePurchaseStatus("", false)
			renderMarketplace()
			setStatus("Purchase complete.")

			if requestMarketplaceOffers then
				task.delay(0.5, function()
					requestMarketplaceOffers({
						Queue = true,
					})
				end)
			end

			if requestMarketplaceMySales
				and catalogViewMode == CATALOG_VIEW_MARKETPLACE
				and marketplaceViewMode == MARKETPLACE_VIEW_MY_SALES then

				task.delay(0.5, function()
					requestMarketplaceMySales({
						Queue = true,
					})
				end)
			end
		else
			local errorMessage = message ~= "" and message or "Could not complete purchase."

			if marketplacePurchaseOverlay.Visible then
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

		if catalogViewMode == CATALOG_VIEW_MARKETPLACE then
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

			if catalogViewMode == CATALOG_VIEW_SHOP then
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

	if panel.Visible and not canShowShop then
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
