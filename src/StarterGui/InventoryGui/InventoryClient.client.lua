-- StarterGui/InventoryGui/InventoryClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local inventoryRequest = remoteEvents:WaitForChild("InventoryRequest")
local inventoryResult = remoteEvents:WaitForChild("InventoryResult")
local setRoomModeRequest = remoteEvents:WaitForChild("SetRoomModeRequest")
local roomModeResult = remoteEvents:WaitForChild("RoomModeResult")

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
local latestInventory = {}
local latestInventoryDetails = {}
local inventoryRequestedEditMode = false
local inventoryEnteredEditMode = false
local inventoryExitEditWhenPlacementEnds = false
local selectedInventoryCategory = "All"
local dropdownOpen = false
local currentInventoryCategories = { "All" }

local LOCAL_REQUEST_COOLDOWN_SECONDS = 0.6
local REQUEST_TIMEOUT_SECONDS = 6
local EDIT_MODE_FAILURE_MESSAGE = "Enter your own room to place furniture."
local EDIT_MODE_REQUIRED_MESSAGE = "Enter Edit Mode to place furniture."
local INVENTORY_CATEGORY_ALL = "All"
local INVENTORY_CATEGORY_OTHER = "Other"

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
panel.Size = UDim2.fromOffset(360, 420)
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
categoryButton.Size = UDim2.new(1, -36, 0, 32)
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
categoryDropdown.Size = UDim2.new(1, -36, 0, 0)
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
listFrame.Size = UDim2.new(1, -36, 1, -158)
listFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 6
listFrame.CanvasSize = UDim2.fromOffset(0, 0)
listFrame.Parent = panel

createCorner(listFrame, 12)
createStroke(listFrame, Color3.fromRGB(220, 220, 220), 1, 0)

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = listFrame

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 10)
listPadding.PaddingBottom = UDim.new(0, 10)
listPadding.PaddingLeft = UDim.new(0, 10)
listPadding.PaddingRight = UDim.new(0, 10)
listPadding.Parent = listFrame

local function shouldShowInventoryButton()
	return player:GetAttribute("OnboardingStep") == "Complete"
		and (player:GetAttribute("ControlMode") or "Hotel") == "Hotel"
end

local function updateOpenButton()
	openButton.Visible = (not panel.Visible)
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
		categoryDropdown.Size = UDim2.new(1, -36, 0, dropdownHeight)
	else
		categoryDropdown.Size = UDim2.new(1, -36, 0, 0)
	end
end

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

local function shouldRequestEditModeForInventory()
	local currentRoomName = player:GetAttribute("CurrentRoomName")

	return player:GetAttribute("RoomMode") ~= "Edit"
		and (player:GetAttribute("ControlMode") or "Hotel") == "Hotel"
		and typeof(currentRoomName) == "string"
		and currentRoomName ~= ""
end

local function requestEditModeForInventory()
	if player:GetAttribute("RoomMode") == "Edit" then
		inventoryRequestedEditMode = false
		return
	end

	if inventoryRequestedEditMode or not shouldRequestEditModeForInventory() then
		return
	end

	inventoryRequestedEditMode = true
	inventoryEnteredEditMode = false
	setRoomModeRequest:FireServer("Edit")
end

local function requestPlayModeIfInventoryEnteredEditMode()
	if not inventoryEnteredEditMode then
		if inventoryRequestedEditMode then
			return
		end

		inventoryExitEditWhenPlacementEnds = false
		return
	end

	if player:GetAttribute("RoomMode") ~= "Edit" then
		inventoryRequestedEditMode = false
		inventoryEnteredEditMode = false
		inventoryExitEditWhenPlacementEnds = false
		return
	end

	if player:GetAttribute("CatalogPlacementActive") == true then
		inventoryExitEditWhenPlacementEnds = true
		return
	end

	inventoryRequestedEditMode = false
	inventoryEnteredEditMode = false
	inventoryExitEditWhenPlacementEnds = false
	setRoomModeRequest:FireServer("Play")
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

local function createInventoryRow(templateId, count, details, layoutOrder)
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

	local sellPrice = getInventorySellPrice(templateId)
	local canSell = sellableCount > 0 and typeof(sellPrice) == "number" and sellPrice > 0
	local maxSellQuantity = math.min(sellableCount, 99)
	local selectedSellQuantity = 1

	local row = Instance.new("TextButton")
	row.Name = tostring(templateId)
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.new(1, -4, 0, canSell and 96 or 72)
	row.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
	row.BorderSizePixel = 0
	row.Text = ""
	row.AutoButtonColor = true
	row.Parent = listFrame

	createCorner(row, 10)
	createStroke(row, Color3.fromRGB(220, 220, 220), 1, 0)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Position = UDim2.fromOffset(12, 8)
	nameLabel.Size = UDim2.new(1, -104, 0, 24)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = tostring(templateId)
	nameLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
	nameLabel.TextSize = 17
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = row

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "CountLabel"
	countLabel.Position = UDim2.new(1, -82, 0, 8)
	countLabel.Size = UDim2.fromOffset(70, 24)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "x" .. tostring(count)
	countLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
	countLabel.TextSize = 17
	countLabel.TextXAlignment = Enum.TextXAlignment.Right
	countLabel.Font = Enum.Font.GothamBold
	countLabel.Parent = row

	local noteLabel = Instance.new("TextLabel")
	noteLabel.Name = "DetailsLabel"
	noteLabel.Position = UDim2.fromOffset(12, 34)
	noteLabel.Size = UDim2.new(1, -24, 0, 20)
	noteLabel.BackgroundTransparency = 1
	local detailParts = {}

	if untradableCount > 0 then
		table.insert(detailParts, "Untradable: " .. tostring(untradableCount))
	end

	if unsellableCount > 0 then
		table.insert(detailParts, "Unsellable: " .. tostring(unsellableCount))
	end

	if sellableCount > 0 and sellPrice then
		table.insert(detailParts, "Sellable: " .. tostring(sellableCount))
	elseif sellableCount <= 0 and unsellableCount > 0 and #detailParts == 0 then
		table.insert(detailParts, "Unsellable")
	end

	noteLabel.Text = table.concat(detailParts, " | ")
	noteLabel.TextColor3 = Color3.fromRGB(105, 105, 105)
	noteLabel.TextSize = 13
	noteLabel.TextXAlignment = Enum.TextXAlignment.Left
	noteLabel.TextTruncate = Enum.TextTruncate.AtEnd
	noteLabel.Font = Enum.Font.Gotham
	noteLabel.Parent = row

	if canSell then
		local sellInfoLabel = Instance.new("TextLabel")
		sellInfoLabel.Name = "SellInfoLabel"
		sellInfoLabel.Position = UDim2.fromOffset(12, 62)
		sellInfoLabel.Size = UDim2.new(1, -190, 0, 24)
		sellInfoLabel.BackgroundTransparency = 1
		sellInfoLabel.Text = "Sell: " .. tostring(sellPrice) .. " Dollars each"
		sellInfoLabel.TextColor3 = Color3.fromRGB(65, 95, 70)
		sellInfoLabel.TextSize = 13
		sellInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
		sellInfoLabel.TextTruncate = Enum.TextTruncate.AtEnd
		sellInfoLabel.Font = Enum.Font.GothamBold
		sellInfoLabel.Parent = row

		local function createSellButton(name, text, position, size)
			local button = Instance.new("TextButton")
			button.Name = name
			button.Position = position
			button.Size = size
			button.BackgroundColor3 = Color3.fromRGB(230, 235, 240)
			button.BorderSizePixel = 0
			button.Text = text
			button.TextColor3 = Color3.fromRGB(45, 45, 45)
			button.TextSize = 14
			button.Font = Enum.Font.GothamBold
			button.Parent = row

			createCorner(button, 6)

			return button
		end

		local controlsY = 60
		local sellButton = createSellButton(
			"SellButton",
			"Sell",
			UDim2.new(1, -72, 0, controlsY),
			UDim2.fromOffset(58, 28)
		)
		sellButton.BackgroundColor3 = Color3.fromRGB(70, 135, 90)
		sellButton.TextColor3 = Color3.fromRGB(255, 255, 255)

		local rightButton = createSellButton(
			"IncreaseSellQuantityButton",
			">",
			UDim2.new(1, -108, 0, controlsY),
			UDim2.fromOffset(28, 28)
		)

		local quantityLabel = Instance.new("TextLabel")
		quantityLabel.Name = "SellQuantityLabel"
		quantityLabel.Position = UDim2.new(1, -148, 0, controlsY)
		quantityLabel.Size = UDim2.fromOffset(34, 28)
		quantityLabel.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
		quantityLabel.BorderSizePixel = 0
		quantityLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
		quantityLabel.TextSize = 14
		quantityLabel.Font = Enum.Font.GothamBold
		quantityLabel.Parent = row

		createCorner(quantityLabel, 6)

		local leftButton = createSellButton(
			"DecreaseSellQuantityButton",
			"<",
			UDim2.new(1, -184, 0, controlsY),
			UDim2.fromOffset(28, 28)
		)

		local function updateSellControls()
			quantityLabel.Text = tostring(selectedSellQuantity)
			leftButton.Active = not sellRequestInFlight and selectedSellQuantity > 1
			leftButton.AutoButtonColor = leftButton.Active
			rightButton.Active = not sellRequestInFlight and selectedSellQuantity < maxSellQuantity
			rightButton.AutoButtonColor = rightButton.Active
			sellButton.Active = not sellRequestInFlight
			sellButton.AutoButtonColor = not sellRequestInFlight
			sellButton.Text = sellRequestInFlight and "..." or "Sell"
		end

		leftButton.MouseButton1Click:Connect(function()
			if sellRequestInFlight or selectedSellQuantity <= 1 then
				return
			end

			selectedSellQuantity -= 1
			updateSellControls()
		end)

		rightButton.MouseButton1Click:Connect(function()
			if sellRequestInFlight or selectedSellQuantity >= maxSellQuantity then
				return
			end

			selectedSellQuantity += 1
			updateSellControls()
		end)

		sellButton.MouseButton1Click:Connect(function()
			if sellRequestInFlight then
				return
			end

			sellRequestInFlight = true
			setStatus("", nil)
			updateSellControls()
			inventoryRequest:FireServer("SellInventoryItem", {
				ItemId = templateId,
				Quantity = selectedSellQuantity,
			})
		end)

		updateSellControls()
	end

	row.MouseButton1Click:Connect(function()
		if count <= 0 then
			return
		end

		local currentRoomName = player:GetAttribute("CurrentRoomName")

		if (player:GetAttribute("ControlMode") or "Hotel") ~= "Hotel"
			or typeof(currentRoomName) ~= "string"
			or currentRoomName == ""
			or player:GetAttribute("RoomMode") ~= "Edit" then

			setStatus(EDIT_MODE_REQUIRED_MESSAGE, false)
			return
		end

		startInventoryPlacement:Fire({
			Id = templateId,
			TemplateName = templateId,
			DisplayName = templateId,
			Source = "Inventory",
		})
	end)
end

renderInventory = function(inventory, inventoryDetails)
	latestInventory = inventory or {}
	latestInventoryDetails = inventoryDetails or {}

	local entries = {}

	if typeof(latestInventory) == "table" then
		for templateId, count in pairs(latestInventory) do
			if typeof(templateId) == "string" and typeof(count) == "number" and count > 0 then
				table.insert(entries, {
					TemplateId = templateId,
					Count = count,
					Details = latestInventoryDetails[templateId],
					Category = getInventoryCategory(templateId),
				})
			end
		end
	end

	local categories = buildInventoryCategories(entries)
	updateCategoryDropdown(categories)
	clearRows()

	table.sort(entries, function(a, b)
		return a.TemplateId < b.TemplateId
	end)

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
			createInventoryRow(entry.TemplateId, entry.Count, entry.Details, index)
		end
	end

	task.defer(function()
		listFrame.CanvasSize = UDim2.fromOffset(
			0,
			listLayout.AbsoluteContentSize.Y + 20
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

	if panel.Visible then
		renderInventory(latestInventory, latestInventoryDetails)
	end
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
		queueInventoryRefresh(reason, force == true and 0.05 or LOCAL_REQUEST_COOLDOWN_SECONDS, force)
		return
	end

	local now = os.clock()
	local elapsed = now - lastInventoryRequestAt

	if force ~= true and elapsed < LOCAL_REQUEST_COOLDOWN_SECONDS then
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

local function setPanelVisible(isVisible)
	local wasVisible = panel.Visible

	if isVisible then
		if not wasVisible then
			selectedInventoryCategory = INVENTORY_CATEGORY_ALL
			setDropdownOpen(false)
		end

		publishMajorMenuState(true)
		majorMenuOpened:Fire(MENU_NAME)
	end

	panel.Visible = isVisible
	updateOpenButton()

	if isVisible then
		if hasLoadedInventory then
			renderInventory(latestInventory, latestInventoryDetails)
		end

		requestEditModeForInventory()
		requestInventoryRefresh("open")
	elseif wasVisible or openMajorMenuName == MENU_NAME then
		setDropdownOpen(false)
		publishMajorMenuState(false)

		if wasVisible then
			requestPlayModeIfInventoryEnteredEditMode()
		end
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

	requestInventoryRefresh(reason, force)
end)

inventoryLocalDelta.Event:Connect(function(payload)
	applyInventoryLocalDelta(payload)
end)

roomModeResult.OnClientEvent:Connect(function(success, message, roomMode)
	if not inventoryRequestedEditMode then
		return
	end

	if success == true or roomMode == "Edit" then
		inventoryRequestedEditMode = false
		inventoryEnteredEditMode = true

		if not panel.Visible then
			requestPlayModeIfInventoryEnteredEditMode()
		end

		return
	end

	inventoryRequestedEditMode = false
	inventoryEnteredEditMode = false
	inventoryExitEditWhenPlacementEnds = false

	message = tostring(message or "")

	if message == "Slow down before changing room mode." then
		warn(message)
		return
	end

	if panel.Visible then
		setStatus(EDIT_MODE_FAILURE_MESSAGE, false)
	end
end)

player:GetAttributeChangedSignal("RoomMode"):Connect(function()
	local roomMode = player:GetAttribute("RoomMode")

	if inventoryRequestedEditMode and roomMode == "Edit" then
		inventoryRequestedEditMode = false
		inventoryEnteredEditMode = true

		if not panel.Visible then
			requestPlayModeIfInventoryEnteredEditMode()
		end
	elseif inventoryEnteredEditMode and roomMode ~= "Edit" then
		inventoryRequestedEditMode = false
		inventoryEnteredEditMode = false
		inventoryExitEditWhenPlacementEnds = false
	end
end)

player:GetAttributeChangedSignal("CatalogPlacementActive"):Connect(function()
	if inventoryExitEditWhenPlacementEnds
		and player:GetAttribute("CatalogPlacementActive") ~= true then

		requestPlayModeIfInventoryEnteredEditMode()
	end
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
				warn(message)
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
			and statusLabel.Text ~= EDIT_MODE_REQUIRED_MESSAGE then

			setStatus("", nil)
		end
	elseif message == "Slow down before requesting inventory." then
		warn(message)
		queueInventoryRefresh("serverCooldown", LOCAL_REQUEST_COOLDOWN_SECONDS)
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
player:GetAttributeChangedSignal("ControlMode"):Connect(handleVisibilityChanged)
player:GetAttributeChangedSignal("CurrentRoomName"):Connect(handleVisibilityChanged)

renderInventory({})
task.defer(updateOpenButton)
