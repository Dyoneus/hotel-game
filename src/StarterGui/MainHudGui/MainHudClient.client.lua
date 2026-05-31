-- StarterGui/MainHudGui/MainHudClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local currencyRequest = remoteEvents:WaitForChild("CurrencyRequest")
local currencyResult = remoteEvents:WaitForChild("CurrencyResult")
local activeRooms = workspace:WaitForChild("ActiveRooms")

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 110

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

local REQUEST_TIMEOUT_SECONDS = 6
local LOCAL_REQUEST_COOLDOWN_SECONDS = 0.6

local balances = {
	Coins = 0,
	Dollars = 0,
}

local currencyRequestInFlight = false
local currencyRequestSerial = 0
local lastCurrencyRequestAt = -math.huge
local refreshQueued = false

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

local currencyRefreshRequested = getOrCreateClientEvent("CurrencyRefreshRequested")
local currencyLocalDelta = getOrCreateClientEvent("CurrencyLocalDelta")
local closeMajorMenus = getOrCreateClientEvent("CloseMajorMenus")
local openRoomNavigator = getOrCreateClientEvent("OpenRoomNavigator")
local openInventory = getOrCreateClientEvent("OpenInventory")

local hud = {}

hud.RoomDetails = Instance.new("Frame")
hud.RoomDetails.Name = "RoomDetails"
hud.RoomDetails.AnchorPoint = Vector2.new(0.5, 1)
hud.RoomDetails.Position = UDim2.new(0.5, -72, 1, -82)
hud.RoomDetails.Size = UDim2.fromOffset(520, 48)
hud.RoomDetails.BackgroundColor3 = Color3.fromRGB(31, 37, 44)
hud.RoomDetails.BackgroundTransparency = 0.08
hud.RoomDetails.BorderSizePixel = 0
hud.RoomDetails.Visible = false
hud.RoomDetails.Parent = gui

createCorner(hud.RoomDetails, 8)
createStroke(hud.RoomDetails, Color3.fromRGB(255, 255, 255), 1, 0.72)

hud.RoomTitle = Instance.new("TextLabel")
hud.RoomTitle.Name = "RoomTitle"
hud.RoomTitle.Position = UDim2.fromOffset(14, 6)
hud.RoomTitle.Size = UDim2.new(1, -28, 0, 20)
hud.RoomTitle.BackgroundTransparency = 1
hud.RoomTitle.Text = "Room"
hud.RoomTitle.TextColor3 = Color3.fromRGB(255, 245, 215)
hud.RoomTitle.TextSize = 16
hud.RoomTitle.TextXAlignment = Enum.TextXAlignment.Left
hud.RoomTitle.TextTruncate = Enum.TextTruncate.AtEnd
hud.RoomTitle.Font = Enum.Font.GothamBold
hud.RoomTitle.Parent = hud.RoomDetails

hud.RoomOwner = Instance.new("TextLabel")
hud.RoomOwner.Name = "RoomOwner"
hud.RoomOwner.Position = UDim2.fromOffset(14, 26)
hud.RoomOwner.Size = UDim2.new(1, -28, 0, 16)
hud.RoomOwner.BackgroundTransparency = 1
hud.RoomOwner.Text = "Owner"
hud.RoomOwner.TextColor3 = Color3.fromRGB(205, 214, 222)
hud.RoomOwner.TextSize = 12
hud.RoomOwner.TextXAlignment = Enum.TextXAlignment.Left
hud.RoomOwner.TextTruncate = Enum.TextTruncate.AtEnd
hud.RoomOwner.Font = Enum.Font.Gotham
hud.RoomOwner.Parent = hud.RoomDetails

hud.Bar = Instance.new("Frame")
hud.Bar.Name = "MainHudBottomBar"
hud.Bar.AnchorPoint = Vector2.new(0.5, 1)
hud.Bar.Position = UDim2.new(0.5, 0, 1, -10)
hud.Bar.Size = UDim2.new(1, -34, 0, 66)
hud.Bar.BackgroundColor3 = Color3.fromRGB(24, 30, 36)
hud.Bar.BackgroundTransparency = 0.04
hud.Bar.BorderSizePixel = 0
hud.Bar.Visible = false
hud.Bar.Parent = gui

createCorner(hud.Bar, 10)
createStroke(hud.Bar, Color3.fromRGB(255, 255, 255), 1, 0.76)

local barSizeConstraint = Instance.new("UISizeConstraint")
barSizeConstraint.MinSize = Vector2.new(720, 66)
barSizeConstraint.MaxSize = Vector2.new(1220, 66)
barSizeConstraint.Parent = hud.Bar

local function createHudButton(name, text, xOffset, width)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0, 0.5)
	button.Position = UDim2.new(0, xOffset, 0.5, 0)
	button.Size = UDim2.fromOffset(width, 42)
	button.BackgroundColor3 = Color3.fromRGB(52, 65, 78)
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = Color3.fromRGB(245, 248, 250)
	button.TextSize = 15
	button.Font = Enum.Font.GothamBold
	button.Parent = hud.Bar

	createCorner(button, 8)
	createStroke(button, Color3.fromRGB(255, 255, 255), 1, 0.78)

	return button
end

hud.MenuButton = createHudButton("MenuButton", "Menu", 12, 82)

hud.ChatFrame = Instance.new("Frame")
hud.ChatFrame.Name = "ChatPlaceholder"
hud.ChatFrame.Position = UDim2.new(0, 106, 0.5, -21)
hud.ChatFrame.Size = UDim2.new(1, -438, 0, 42)
hud.ChatFrame.BackgroundColor3 = Color3.fromRGB(245, 248, 250)
hud.ChatFrame.BorderSizePixel = 0
hud.ChatFrame.Parent = hud.Bar

createCorner(hud.ChatFrame, 8)
createStroke(hud.ChatFrame, Color3.fromRGB(0, 0, 0), 1, 0.82)

hud.ChatLabel = Instance.new("TextLabel")
hud.ChatLabel.Name = "ChatLabel"
hud.ChatLabel.Position = UDim2.fromOffset(14, 0)
hud.ChatLabel.Size = UDim2.new(1, -28, 1, 0)
hud.ChatLabel.BackgroundTransparency = 1
hud.ChatLabel.Text = "Chat coming soon..."
hud.ChatLabel.TextColor3 = Color3.fromRGB(86, 96, 104)
hud.ChatLabel.TextSize = 15
hud.ChatLabel.TextXAlignment = Enum.TextXAlignment.Left
hud.ChatLabel.Font = Enum.Font.Gotham
hud.ChatLabel.Parent = hud.ChatFrame

hud.InventoryButton = Instance.new("TextButton")
hud.InventoryButton.Name = "InventoryButton"
hud.InventoryButton.AnchorPoint = Vector2.new(1, 0.5)
hud.InventoryButton.Position = UDim2.new(1, -250, 0.5, 0)
hud.InventoryButton.Size = UDim2.fromOffset(104, 42)
hud.InventoryButton.BackgroundColor3 = Color3.fromRGB(63, 98, 78)
hud.InventoryButton.BorderSizePixel = 0
hud.InventoryButton.Text = "Inventory"
hud.InventoryButton.TextColor3 = Color3.fromRGB(245, 248, 250)
hud.InventoryButton.TextSize = 14
hud.InventoryButton.Font = Enum.Font.GothamBold
hud.InventoryButton.Parent = hud.Bar

createCorner(hud.InventoryButton, 8)
createStroke(hud.InventoryButton, Color3.fromRGB(255, 255, 255), 1, 0.78)

hud.CurrencyPanel = Instance.new("TextButton")
hud.CurrencyPanel.Name = "CurrencyDisplay"
hud.CurrencyPanel.AnchorPoint = Vector2.new(1, 0.5)
hud.CurrencyPanel.Position = UDim2.new(1, -12, 0.5, 0)
hud.CurrencyPanel.Size = UDim2.fromOffset(224, 42)
hud.CurrencyPanel.BackgroundColor3 = Color3.fromRGB(55, 48, 40)
hud.CurrencyPanel.BorderSizePixel = 0
hud.CurrencyPanel.Text = ""
hud.CurrencyPanel.AutoButtonColor = true
hud.CurrencyPanel.Parent = hud.Bar

createCorner(hud.CurrencyPanel, 8)
createStroke(hud.CurrencyPanel, Color3.fromRGB(255, 255, 255), 1, 0.78)

hud.CoinsLabel = Instance.new("TextLabel")
hud.CoinsLabel.Name = "Coins"
hud.CoinsLabel.Position = UDim2.fromOffset(12, 0)
hud.CoinsLabel.Size = UDim2.fromOffset(96, 42)
hud.CoinsLabel.BackgroundTransparency = 1
hud.CoinsLabel.Text = "Coins: 0"
hud.CoinsLabel.TextColor3 = Color3.fromRGB(255, 224, 104)
hud.CoinsLabel.TextSize = 13
hud.CoinsLabel.TextXAlignment = Enum.TextXAlignment.Left
hud.CoinsLabel.Font = Enum.Font.GothamBold
hud.CoinsLabel.Parent = hud.CurrencyPanel

hud.DollarsLabel = Instance.new("TextLabel")
hud.DollarsLabel.Name = "Dollars"
hud.DollarsLabel.Position = UDim2.fromOffset(112, 0)
hud.DollarsLabel.Size = UDim2.new(1, -122, 1, 0)
hud.DollarsLabel.BackgroundTransparency = 1
hud.DollarsLabel.Text = "Dollars: 0"
hud.DollarsLabel.TextColor3 = Color3.fromRGB(158, 226, 172)
hud.DollarsLabel.TextSize = 13
hud.DollarsLabel.TextXAlignment = Enum.TextXAlignment.Left
hud.DollarsLabel.TextTruncate = Enum.TextTruncate.AtEnd
hud.DollarsLabel.Font = Enum.Font.GothamBold
hud.DollarsLabel.Parent = hud.CurrencyPanel

local function normalizeBalance(value)
	if typeof(value) ~= "number"
		or value ~= value
		or value < 0
		or value == math.huge then

		return 0
	end

	return math.floor(value)
end

local function renderCurrency()
	hud.CoinsLabel.Text = "Coins: " .. tostring(normalizeBalance(balances.Coins))
	hud.DollarsLabel.Text = "Dollars: " .. tostring(normalizeBalance(balances.Dollars))
end

local function applyCurrenciesSnapshot(currencies)
	if typeof(currencies) ~= "table" then
		return
	end

	balances.Coins = normalizeBalance(currencies.Coins)
	balances.Dollars = normalizeBalance(currencies.Dollars)
	renderCurrency()
end

local function applyCurrencyDelta(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local currencyKey = payload.CurrencyKey

	if currencyKey ~= "Coins" and currencyKey ~= "Dollars" then
		return
	end

	local newBalance = nil

	if typeof(payload.Balance) == "number" then
		newBalance = normalizeBalance(payload.Balance)
	elseif typeof(payload.Delta) == "number" or typeof(payload.Amount) == "number" then
		local delta = typeof(payload.Delta) == "number" and payload.Delta or payload.Amount
		newBalance = math.max(normalizeBalance(balances[currencyKey]) + math.floor(delta), 0)
	end

	if not newBalance then
		return
	end

	balances[currencyKey] = newBalance
	renderCurrency()
end

local function queueCurrencyRefresh(delaySeconds)
	if refreshQueued then
		return
	end

	refreshQueued = true

	task.delay(delaySeconds, function()
		refreshQueued = false
		if hud.Bar.Visible then
			currencyRequest:FireServer("GetCurrencies")
		end
	end)
end

local function requestCurrencyRefresh(force)
	if currencyRequestInFlight then
		queueCurrencyRefresh(LOCAL_REQUEST_COOLDOWN_SECONDS)
		return
	end

	local now = os.clock()
	local elapsed = now - lastCurrencyRequestAt

	if force ~= true and elapsed < LOCAL_REQUEST_COOLDOWN_SECONDS then
		queueCurrencyRefresh(LOCAL_REQUEST_COOLDOWN_SECONDS - elapsed + 0.05)
		return
	end

	currencyRequestInFlight = true
	lastCurrencyRequestAt = now
	currencyRequestSerial += 1

	local requestSerial = currencyRequestSerial
	currencyRequest:FireServer("GetCurrencies")

	task.delay(REQUEST_TIMEOUT_SECONDS, function()
		if currencyRequestInFlight and currencyRequestSerial == requestSerial then
			currencyRequestInFlight = false
		end
	end)
end

local function getCurrentRoom()
	local roomName = player:GetAttribute("CurrentRoomName")

	if typeof(roomName) ~= "string" or roomName == "" then
		return nil, nil
	end

	return activeRooms:FindFirstChild(roomName), roomName
end

local function getOwnerText(roomModel)
	if not roomModel then
		return ""
	end

	if roomModel:GetAttribute("RoomType") == "PublicSpace" then
		return "Public Space"
	end

	local ownerUserId = roomModel:GetAttribute("OwnerUserId")

	if typeof(ownerUserId) == "number" and ownerUserId > 0 then
		local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)

		if ownerPlayer then
			return "Owner: " .. tostring(ownerPlayer.DisplayName or ownerPlayer.Name)
		end

		return "Owner: User_" .. tostring(ownerUserId)
	end

	return "Owner: Unknown"
end

local function updateRoomDetails()
	local roomModel, roomName = getCurrentRoom()

	if not roomModel then
		hud.RoomTitle.Text = "Room"
		hud.RoomOwner.Text = ""
		return
	end

	local displayName = roomModel:GetAttribute("DisplayName")

	if typeof(displayName) ~= "string" or displayName == "" then
		displayName = roomName or roomModel.Name
	end

	hud.RoomTitle.Text = tostring(displayName)
	hud.RoomOwner.Text = getOwnerText(roomModel)
end

local function shouldShowHud()
	local currentRoomName = player:GetAttribute("CurrentRoomName")

	return player:GetAttribute("OnboardingStep") == "Complete"
		and player:GetAttribute("InHotelMainMenu") ~= true
		and typeof(currentRoomName) == "string"
		and currentRoomName ~= ""
		and (player:GetAttribute("ControlMode") or "Hotel") == "Hotel"
end

local function updateVisibility()
	local shouldShow = shouldShowHud()
	local wasVisible = hud.Bar.Visible

	hud.Bar.Visible = shouldShow
	hud.RoomDetails.Visible = shouldShow

	if shouldShow then
		updateRoomDetails()

		if not wasVisible then
			requestCurrencyRefresh(true)
		end
	end
end

hud.MenuButton.MouseButton1Click:Connect(function()
	openRoomNavigator:Fire()
end)

hud.InventoryButton.MouseButton1Click:Connect(function()
	openInventory:Fire()
end)

hud.CurrencyPanel.MouseButton1Click:Connect(function()
	requestCurrencyRefresh(true)
end)

currencyRefreshRequested.Event:Connect(function(options)
	local force = false

	if typeof(options) == "table" then
		force = options.Force == true or options.Priority == true
	end

	requestCurrencyRefresh(force)
end)

currencyLocalDelta.Event:Connect(applyCurrencyDelta)

currencyResult.OnClientEvent:Connect(function(response)
	if typeof(response) ~= "table" then
		return
	end

	local success = response.Success == true
	local kind = response.Kind

	if kind == "Currencies" or kind == "Currency" or kind == "Coins" then
		currencyRequestInFlight = false
	end

	if not success then
		return
	end

	if kind == "Currencies" then
		applyCurrenciesSnapshot(response.Currencies)
	elseif kind == "Currency" then
		applyCurrencyDelta({
			CurrencyKey = response.CurrencyKey,
			Balance = response.Balance,
		})
	elseif kind == "Coins" then
		applyCurrencyDelta({
			CurrencyKey = "Coins",
			Balance = response.Coins,
		})
	end
end)

player:GetAttributeChangedSignal("CurrentRoomName"):Connect(updateVisibility)
player:GetAttributeChangedSignal("OnboardingStep"):Connect(updateVisibility)
player:GetAttributeChangedSignal("ControlMode"):Connect(updateVisibility)
player:GetAttributeChangedSignal("InHotelMainMenu"):Connect(updateVisibility)

activeRooms.ChildAdded:Connect(function(child)
	if child.Name == player:GetAttribute("CurrentRoomName") then
		task.defer(updateVisibility)
	end
end)

activeRooms.ChildRemoved:Connect(function(child)
	if child.Name == player:GetAttribute("CurrentRoomName") then
		task.defer(updateVisibility)
	end
end)

Players.PlayerAdded:Connect(updateRoomDetails)
Players.PlayerRemoving:Connect(updateRoomDetails)

renderCurrency()
task.defer(updateVisibility)
