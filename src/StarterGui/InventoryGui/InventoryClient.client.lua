-- StarterGui/InventoryGui/InventoryClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local inventoryRequest = remoteEvents:WaitForChild("InventoryRequest")
local inventoryResult = remoteEvents:WaitForChild("InventoryResult")
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

local openButton = Instance.new("TextButton")
openButton.Name = "OpenInventoryButton"
openButton.AnchorPoint = Vector2.new(1, 1)
openButton.Position = UDim2.new(1, -20, 1, -128)
openButton.Size = UDim2.fromOffset(150, 44)
openButton.BackgroundColor3 = Color3.fromRGB(80, 120, 90)
openButton.BorderSizePixel = 0
openButton.Text = "Inventory"
openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
openButton.TextSize = 20
openButton.Font = Enum.Font.GothamBold
openButton.Visible = false
openButton.Parent = gui

createCorner(openButton, 10)
createStroke(openButton, Color3.fromRGB(255, 255, 255), 1, 0.25)

local panel = Instance.new("Frame")
panel.Name = "InventoryPanel"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -24, 0.5, 0)
panel.Size = UDim2.fromOffset(680, 460)
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
titleLabel.Text = "Inventory"
titleLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
titleLabel.TextSize = 24
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
closeButton.TextSize = 18
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = panel

createCorner(closeButton, 8)

local dragHandle = Instance.new("Frame")
dragHandle.Name = "InventoryDragHandle"
dragHandle.Position = UDim2.fromOffset(0, 0)
dragHandle.Size = UDim2.new(1, -74, 0, 58)
dragHandle.BackgroundTransparency = 1
dragHandle.Active = true
dragHandle.ZIndex = 5
dragHandle.Parent = panel

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Position = UDim2.fromOffset(18, 56)
statusLabel.Size = UDim2.new(1, -36, 0, 28)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = ""
statusLabel.TextColor3 = Color3.fromRGB(90, 90, 90)
statusLabel.TextWrapped = true
statusLabel.TextSize = 13
statusLabel.Font = Enum.Font.Gotham
statusLabel.Parent = panel

local categoryButton = Instance.new("TextButton")
categoryButton.Name = "CategoryDropdownButton"
categoryButton.Position = UDim2.fromOffset(18, 92)
categoryButton.Size = UDim2.new(0, 300, 0, 32)
categoryButton.BackgroundColor3 = Color3.fromRGB(235, 238, 242)
categoryButton.BorderSizePixel = 0
categoryButton.Text = "Category: All"
categoryButton.TextColor3 = Color3.fromRGB(45, 45, 45)
categoryButton.TextSize = 14
categoryButton.TextXAlignment = Enum.TextXAlignment.Left
categoryButton.Font = Enum.Font.GothamBold
categoryButton.ZIndex = 20
categoryButton.Parent = panel

createCorner(categoryButton, 8)
createStroke(categoryButton, Color3.fromRGB(210, 215, 220), 1, 0)

local categoryDropdown = Instance.new("ScrollingFrame")
categoryDropdown.Name = "CategoryDropdownList"
categoryDropdown.Position = UDim2.fromOffset(18, 128)
categoryDropdown.Size = UDim2.fromOffset(300, 0)
categoryDropdown.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
categoryDropdown.BorderSizePixel = 0
categoryDropdown.CanvasSize = UDim2.fromOffset(0, 0)
categoryDropdown.ScrollBarThickness = 4
categoryDropdown.Visible = false
categoryDropdown.ZIndex = 30
categoryDropdown.Parent = panel

createCorner(categoryDropdown, 8)
createStroke(categoryDropdown, Color3.fromRGB(210, 215, 220), 1, 0)

local categoryDropdownLayout = Instance.new("UIListLayout")
categoryDropdownLayout.SortOrder = Enum.SortOrder.LayoutOrder
categoryDropdownLayout.Padding = UDim.new(0, 2)
categoryDropdownLayout.Parent = categoryDropdown

local listFrame = Instance.new("ScrollingFrame")
listFrame.Name = "InventoryList"
listFrame.Position = UDim2.fromOffset(18, 138)
listFrame.Size = UDim2.new(0, 300, 1, -158)
listFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 6
listFrame.CanvasSize = UDim2.fromOffset(0, 0)
listFrame.Parent = panel

createCorner(listFrame, 12)
createStroke(listFrame, Color3.fromRGB(220, 220, 220), 1, 0)

local gridLayout = Instance.new("UIGridLayout")
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.CellSize = UDim2.fromOffset(86, 86)
gridLayout.CellPadding = UDim2.fromOffset(8, 8)
gridLayout.Parent = listFrame

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 10)
listPadding.PaddingBottom = UDim.new(0, 10)
listPadding.PaddingLeft = UDim.new(0, 10)
listPadding.PaddingRight = UDim.new(0, 10)
listPadding.Parent = listFrame

local detailsPanel = Instance.new("Frame")
detailsPanel.Name = "SelectedItemDetails"
detailsPanel.Position = UDim2.new(0, 334, 0, 92)
detailsPanel.Size = UDim2.new(1, -352, 1, -112)
detailsPanel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
detailsPanel.BorderSizePixel = 0
detailsPanel.Parent = panel

createCorner(detailsPanel, 12)
createStroke(detailsPanel, Color3.fromRGB(220, 220, 220), 1, 0)

local detailsTitle = Instance.new("TextLabel")
detailsTitle.Name = "DetailsTitle"
detailsTitle.Position = UDim2.fromOffset(16, 14)
detailsTitle.Size = UDim2.new(1, -32, 0, 28)
detailsTitle.BackgroundTransparency = 1
detailsTitle.Text = "Select an item"
detailsTitle.TextColor3 = Color3.fromRGB(40, 40, 40)
detailsTitle.TextSize = 20
detailsTitle.TextXAlignment = Enum.TextXAlignment.Left
detailsTitle.TextTruncate = Enum.TextTruncate.AtEnd
detailsTitle.Font = Enum.Font.GothamBold
detailsTitle.Parent = detailsPanel

local detailsSubtitle = Instance.new("TextLabel")
detailsSubtitle.Name = "DetailsSubtitle"
detailsSubtitle.Position = UDim2.fromOffset(16, 46)
detailsSubtitle.Size = UDim2.new(1, -32, 0, 20)
detailsSubtitle.BackgroundTransparency = 1
detailsSubtitle.Text = ""
detailsSubtitle.TextColor3 = Color3.fromRGB(85, 85, 85)
detailsSubtitle.TextSize = 13
detailsSubtitle.TextXAlignment = Enum.TextXAlignment.Left
detailsSubtitle.TextTruncate = Enum.TextTruncate.AtEnd
detailsSubtitle.Font = Enum.Font.Gotham
detailsSubtitle.Parent = detailsPanel

local detailsDescription = Instance.new("TextLabel")
detailsDescription.Name = "DetailsDescription"
detailsDescription.Position = UDim2.fromOffset(16, 72)
detailsDescription.Size = UDim2.new(1, -32, 0, 44)
detailsDescription.BackgroundTransparency = 1
detailsDescription.Text = "Choose an owned furniture item to see details."
detailsDescription.TextColor3 = Color3.fromRGB(90, 90, 90)
detailsDescription.TextSize = 13
detailsDescription.TextWrapped = true
detailsDescription.TextXAlignment = Enum.TextXAlignment.Left
detailsDescription.TextYAlignment = Enum.TextYAlignment.Top
detailsDescription.Font = Enum.Font.Gotham
detailsDescription.Parent = detailsPanel

local ownershipLabel = Instance.new("TextLabel")
ownershipLabel.Name = "OwnershipLabel"
ownershipLabel.Position = UDim2.fromOffset(16, 126)
ownershipLabel.Size = UDim2.new(1, -32, 0, 84)
ownershipLabel.BackgroundTransparency = 1
ownershipLabel.Text = ""
ownershipLabel.TextColor3 = Color3.fromRGB(55, 60, 55)
ownershipLabel.TextSize = 13
ownershipLabel.TextWrapped = true
ownershipLabel.TextXAlignment = Enum.TextXAlignment.Left
ownershipLabel.TextYAlignment = Enum.TextYAlignment.Top
ownershipLabel.Font = Enum.Font.GothamMedium
ownershipLabel.Parent = detailsPanel

local placeButton = Instance.new("TextButton")
placeButton.Name = "PlaceToRoomButton"
placeButton.Position = UDim2.new(0, 16, 0, 218)
placeButton.Size = UDim2.new(1, -32, 0, 34)
placeButton.BackgroundColor3 = Color3.fromRGB(70, 135, 90)
placeButton.BorderSizePixel = 0
placeButton.Text = "Place to room"
placeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
placeButton.TextSize = 15
placeButton.Font = Enum.Font.GothamBold
placeButton.Parent = detailsPanel

createCorner(placeButton, 8)

local sellControlsFrame = Instance.new("Frame")
sellControlsFrame.Name = "SellControls"
sellControlsFrame.Position = UDim2.new(0, 16, 0, 264)
sellControlsFrame.Size = UDim2.new(1, -32, 0, 34)
sellControlsFrame.BackgroundTransparency = 1
sellControlsFrame.Parent = detailsPanel

local sellDecreaseButton = Instance.new("TextButton")
sellDecreaseButton.Name = "DecreaseSellQuantityButton"
sellDecreaseButton.Position = UDim2.fromOffset(0, 0)
sellDecreaseButton.Size = UDim2.fromOffset(34, 34)
sellDecreaseButton.BackgroundColor3 = Color3.fromRGB(230, 235, 240)
sellDecreaseButton.BorderSizePixel = 0
sellDecreaseButton.Text = "<"
sellDecreaseButton.TextColor3 = Color3.fromRGB(45, 45, 45)
sellDecreaseButton.TextSize = 15
sellDecreaseButton.Font = Enum.Font.GothamBold
sellDecreaseButton.Parent = sellControlsFrame

createCorner(sellDecreaseButton, 8)

local sellQuantityLabel = Instance.new("TextLabel")
sellQuantityLabel.Name = "SellQuantityLabel"
sellQuantityLabel.Position = UDim2.fromOffset(40, 0)
sellQuantityLabel.Size = UDim2.fromOffset(42, 34)
sellQuantityLabel.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
sellQuantityLabel.BorderSizePixel = 0
sellQuantityLabel.Text = "1"
sellQuantityLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
sellQuantityLabel.TextSize = 14
sellQuantityLabel.Font = Enum.Font.GothamBold
sellQuantityLabel.Parent = sellControlsFrame

createCorner(sellQuantityLabel, 8)

local sellIncreaseButton = Instance.new("TextButton")
sellIncreaseButton.Name = "IncreaseSellQuantityButton"
sellIncreaseButton.Position = UDim2.fromOffset(88, 0)
sellIncreaseButton.Size = UDim2.fromOffset(34, 34)
sellIncreaseButton.BackgroundColor3 = Color3.fromRGB(230, 235, 240)
sellIncreaseButton.BorderSizePixel = 0
sellIncreaseButton.Text = ">"
sellIncreaseButton.TextColor3 = Color3.fromRGB(45, 45, 45)
sellIncreaseButton.TextSize = 15
sellIncreaseButton.Font = Enum.Font.GothamBold
sellIncreaseButton.Parent = sellControlsFrame

createCorner(sellIncreaseButton, 8)

local sellButton = Instance.new("TextButton")
sellButton.Name = "SellForDollarsButton"
sellButton.Position = UDim2.new(0, 132, 0, 0)
sellButton.Size = UDim2.new(1, -132, 0, 34)
sellButton.BackgroundColor3 = Color3.fromRGB(70, 135, 90)
sellButton.BorderSizePixel = 0
sellButton.Text = "Sell for Dollars"
sellButton.TextColor3 = Color3.fromRGB(255, 255, 255)
sellButton.TextSize = 14
sellButton.Font = Enum.Font.GothamBold
sellButton.Parent = sellControlsFrame

createCorner(sellButton, 8)

local marketplaceButton = Instance.new("TextButton")
marketplaceButton.Name = "MarketplaceSoonButton"
marketplaceButton.Position = UDim2.new(0, 16, 0, 310)
marketplaceButton.Size = UDim2.new(1, -32, 0, 32)
marketplaceButton.BackgroundColor3 = Color3.fromRGB(165, 170, 175)
marketplaceButton.BorderSizePixel = 0
marketplaceButton.Text = "Marketplace Soon"
marketplaceButton.TextColor3 = Color3.fromRGB(255, 255, 255)
marketplaceButton.TextSize = 14
marketplaceButton.Font = Enum.Font.GothamBold
marketplaceButton.Active = false
marketplaceButton.AutoButtonColor = false
marketplaceButton.Parent = detailsPanel

createCorner(marketplaceButton, 8)

local function shouldShowInventoryButton()
	return player:GetAttribute("OnboardingStep") == "Complete"
		and (player:GetAttribute("ControlMode") or "Hotel") == "Hotel"
end

local function updateOpenButton()
	openButton.Visible = (not panel.Visible)
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
	statusLabel.Text = tostring(text or "")

	if success == true then
		statusLabel.TextColor3 = Color3.fromRGB(50, 110, 60)
	elseif success == false then
		statusLabel.TextColor3 = Color3.fromRGB(150, 60, 60)
	else
		statusLabel.TextColor3 = Color3.fromRGB(90, 90, 90)
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
	categoryButton.Text = "  Category: " .. tostring(selectedInventoryCategory) .. " v"
end

local function clearCategoryDropdown()
	for _, child in ipairs(categoryDropdown:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function setDropdownOpen(isOpen)
	dropdownOpen = isOpen == true
	categoryDropdown.Visible = dropdownOpen

	if dropdownOpen then
		local dropdownHeight = math.min(#currentInventoryCategories * 30 + 8, 156)
		categoryDropdown.Size = UDim2.fromOffset(300, dropdownHeight)
	else
		categoryDropdown.Size = UDim2.fromOffset(300, 0)
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
			and not panel.Visible then

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
	local panelSize = panel.AbsoluteSize

	if panelSize.X > 0 and panelSize.Y > 0 then
		return panelSize
	end

	return Vector2.new(panel.Size.X.Offset, panel.Size.Y.Offset)
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
	panel.Position = clampPanelPosition(panel.Position)
end

local function beginPanelDrag(input)
	panelDragInput = input
	panelDragStartInputPosition = input.Position
	panelDragStartPanelPosition = panel.Position

	input.Changed:Connect(function()
		if input.UserInputState == Enum.UserInputState.End and panelDragInput == input then
			panelDragInput = nil
			panelDragStartInputPosition = nil
			panelDragStartPanelPosition = nil
			clampPanelToScreen()
		end
	end)
end

dragHandle.InputBegan:Connect(function(input)
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

	panel.Position = clampPanelPosition(UDim2.new(
		panelDragStartPanelPosition.X.Scale,
		panelDragStartPanelPosition.X.Offset + delta.X,
		panelDragStartPanelPosition.Y.Scale,
		panelDragStartPanelPosition.Y.Offset + delta.Y
	))
end)

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if panel.Visible then
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
		optionButton.Parent = categoryDropdown

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
		categoryDropdown.CanvasSize = UDim2.fromOffset(
			0,
			categoryDropdownLayout.AbsoluteContentSize.Y + 8
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
	for _, child in ipairs(listFrame:GetChildren()) do
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
	emptyLabel.Parent = listFrame
end

local function getInventoryCounts(templateId)
	local count = 0
	local details = nil

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
	local entry = getSelectedInventoryEntry()

	if not entry then
		detailsTitle.Text = "Select an item"
		detailsSubtitle.Text = ""
		detailsDescription.Text = "Choose an owned furniture item to see details."
		ownershipLabel.Text = ""
		setButtonEnabled(placeButton, false, Color3.fromRGB(70, 135, 90))
		sellControlsFrame.Visible = false
		marketplaceButton.Visible = false
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

	detailsTitle.Text = entry.DisplayName
	detailsSubtitle.Text = tostring(templateId) .. "  -  " .. tostring(entry.Category or INVENTORY_CATEGORY_OTHER)
	detailsDescription.Text = typeof(item.Description) == "string" and item.Description ~= ""
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

	ownershipLabel.Text = table.concat(statusLines, "\n")

	setButtonEnabled(placeButton, counts.Total > 0, Color3.fromRGB(70, 135, 90))
	placeButton.Text = pendingPlacementTemplateId == templateId and "Preparing..." or "Place to room"

	sellControlsFrame.Visible = canSell
	sellQuantityLabel.Text = tostring(selectedSellQuantity)
	setButtonEnabled(sellDecreaseButton, canSell and not sellRequestInFlight and selectedSellQuantity > 1, Color3.fromRGB(230, 235, 240))
	setButtonEnabled(sellIncreaseButton, canSell and not sellRequestInFlight and selectedSellQuantity < maxSellQuantity, Color3.fromRGB(230, 235, 240))
	setButtonEnabled(sellButton, canSell and not sellRequestInFlight, Color3.fromRGB(70, 135, 90))
	sellButton.Text = sellRequestInFlight and "Selling..." or "Sell for Dollars"

	marketplaceButton.Visible = counts.Tradable > 0
	marketplaceButton.Text = counts.Tradable > 0 and "Marketplace Soon" or "Untradable"
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
	card.Parent = listFrame

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
		listFrame.CanvasSize = UDim2.fromOffset(
			0,
			gridLayout.AbsoluteContentSize.Y + 20
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

	if panel.Visible then
		renderInventory(latestInventory, latestInventoryDetails)
	end
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
	inventoryHideRequestedForPlacement = panel.Visible == true

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
	local wasVisible = panel.Visible
	local preserveInventoryView = typeof(options) == "table" and options.PreserveInventoryView == true
	local skipInventoryRefresh = typeof(options) == "table" and options.SkipInventoryRefresh == true

	if isVisible then
		if not wasVisible and not preserveInventoryView then
			selectedInventoryCategory = INVENTORY_CATEGORY_ALL
			setDropdownOpen(false)
		elseif not wasVisible then
			setDropdownOpen(false)
		end

		publishMajorMenuState(true)
		majorMenuOpened:Fire(MENU_NAME)
	end

	panel.Visible = isVisible
	updateOpenButton()

	if isVisible then
		inventoryHideRequestedForPlacement = false
		inventoryHiddenForPlacement = false
		clampPanelToScreen()

		if hasLoadedInventory then
			renderInventory(latestInventory, latestInventoryDetails)
		end

		if not skipInventoryRefresh then
			requestInventoryRefresh("open")
		end
	elseif wasVisible or openMajorMenuName == MENU_NAME then
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
		or not panel.Visible then

		return
	end

	inventoryHiddenForPlacement = true
	panel.Visible = false
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

openButton.MouseButton1Click:Connect(function()
	setPanelVisible(true)
end)

closeButton.MouseButton1Click:Connect(function()
	setPanelVisible(false)
end)

categoryButton.MouseButton1Click:Connect(function()
	setDropdownOpen(not dropdownOpen)
end)

placeButton.MouseButton1Click:Connect(requestPlacementForSelectedItem)

sellDecreaseButton.MouseButton1Click:Connect(function()
	updateSellQuantity(-1)
end)

sellIncreaseButton.MouseButton1Click:Connect(function()
	updateSellQuantity(1)
end)

sellButton.MouseButton1Click:Connect(sellSelectedItem)

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

	if panel.Visible then
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
	if menuName ~= MENU_NAME and panel.Visible then
		setPanelVisible(false)
	end
end)

closeMajorMenus.Event:Connect(function()
	if panel.Visible then
		setPanelVisible(false)
	end
end)

majorMenuStateChanged.Event:Connect(function(isOpen, menuName)
	setLocalMajorMenuState(isOpen == true, menuName)
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

			if panel.Visible then
				renderInventory(latestInventory, latestInventoryDetails)
			end
		end

		return
	end

	if success and typeof(response.Inventory) == "table" then
		hasLoadedInventory = true
		renderInventory(response.Inventory, response.InventoryDetails)

		if statusLabel.Text ~= EDIT_MODE_FAILURE_MESSAGE
			and statusLabel.Text ~= EDIT_MODE_PREPARING_MESSAGE then

			setStatus("", nil)
		end
	elseif message == "Slow down before requesting inventory." then
		queueInventoryRefresh("serverCooldown", LOCAL_REQUEST_COOLDOWN_SECONDS + 0.25, false)
	else
		setStatus(message ~= "" and message or "Could not load inventory.", false)
	end
end)

local function handleVisibilityChanged()
	if panel.Visible and not shouldShowInventoryButton() then
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
