-- StarterGui/CurrencyGui/CurrencyClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local currencyRequest = remoteEvents:WaitForChild("CurrencyRequest")
local currencyResult = remoteEvents:WaitForChild("CurrencyResult")

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 120

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

local requestInFlight = false
local refreshQueued = false
local queuedRefreshForce = false
local lastCurrencyRequestAt = -math.huge
local requestSerial = 0
local hasLoadedCurrencies = false

local LOCAL_REQUEST_COOLDOWN_SECONDS = 0.6
local REQUEST_TIMEOUT_SECONDS = 6

local balances = {
	Coins = 0,
	Dollars = 0,
	Event = {},
}

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

local container = Instance.new("Frame")
container.Name = "CurrencyHud"
container.AnchorPoint = Vector2.new(0.5, 0)
container.Position = UDim2.new(0.5, 0, 0, 12)
container.Size = UDim2.fromOffset(300, 38)
container.BackgroundColor3 = Color3.fromRGB(34, 42, 50)
container.BackgroundTransparency = 0.08
container.BorderSizePixel = 0
container.Visible = false
container.Parent = gui

createCorner(container, 10)
createStroke(container, Color3.fromRGB(255, 255, 255), 1, 0.65)

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 12)
layout.Parent = container

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 14)
padding.PaddingRight = UDim.new(0, 14)
padding.Parent = container

local coinsLabel = Instance.new("TextLabel")
coinsLabel.Name = "CoinsLabel"
coinsLabel.LayoutOrder = 1
coinsLabel.Size = UDim2.fromOffset(130, 24)
coinsLabel.BackgroundTransparency = 1
coinsLabel.Text = "Coins: 0"
coinsLabel.TextColor3 = Color3.fromRGB(255, 235, 150)
coinsLabel.TextSize = 16
coinsLabel.TextXAlignment = Enum.TextXAlignment.Center
coinsLabel.Font = Enum.Font.GothamBold
coinsLabel.Parent = container

local dollarsLabel = Instance.new("TextLabel")
dollarsLabel.Name = "DollarsLabel"
dollarsLabel.LayoutOrder = 2
dollarsLabel.Size = UDim2.fromOffset(130, 24)
dollarsLabel.BackgroundTransparency = 1
dollarsLabel.Text = "Dollars: 0"
dollarsLabel.TextColor3 = Color3.fromRGB(170, 235, 185)
dollarsLabel.TextSize = 16
dollarsLabel.TextXAlignment = Enum.TextXAlignment.Center
dollarsLabel.Font = Enum.Font.GothamBold
dollarsLabel.Parent = container

local requestCurrencyRefresh = nil

local function isNonNegativeNumber(value)
	return typeof(value) == "number"
		and value == value
		and value >= 0
		and value < math.huge
end

local function normalizeBalance(value)
	if not isNonNegativeNumber(value) then
		return 0
	end

	return math.floor(value)
end

local function isSupportedLocalCurrencyKey(currencyKey)
	if currencyKey == "Coins" or currencyKey == "Dollars" then
		return true
	end

	local eventId = typeof(currencyKey) == "string" and currencyKey:match("^Event:(.+)$")

	return typeof(eventId) == "string"
		and eventId ~= ""
		and eventId:match("%S") ~= nil
end

local function renderBalances()
	coinsLabel.Text = "Coins: " .. tostring(normalizeBalance(balances.Coins))
	dollarsLabel.Text = "Dollars: " .. tostring(normalizeBalance(balances.Dollars))
end

local function applyCurrenciesSnapshot(currencies)
	if typeof(currencies) ~= "table" then
		return
	end

	balances.Coins = normalizeBalance(currencies.Coins)
	balances.Dollars = normalizeBalance(currencies.Dollars)

	if typeof(currencies.Event) == "table" then
		balances.Event = {}

		for eventId, balance in pairs(currencies.Event) do
			if typeof(eventId) == "string"
				and eventId ~= ""
				and eventId:match("%S") ~= nil
				and isNonNegativeNumber(balance)
				and balance > 0 then

				balances.Event[eventId] = math.floor(balance)
			end
		end
	end

	hasLoadedCurrencies = true
	renderBalances()
end

local function applyCurrencyLocalDelta(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local currencyKey = payload.CurrencyKey

	if not isSupportedLocalCurrencyKey(currencyKey) then
		return
	end

	local currentBalance = 0

	if currencyKey == "Coins" or currencyKey == "Dollars" then
		currentBalance = normalizeBalance(balances[currencyKey])
	elseif currencyKey:sub(1, 6) == "Event:" then
		local eventId = currencyKey:sub(7)
		currentBalance = normalizeBalance(balances.Event[eventId])
	end

	local newBalance = nil

	if isNonNegativeNumber(payload.Balance) then
		newBalance = math.floor(payload.Balance)
	elseif typeof(payload.Delta) == "number"
		and payload.Delta == payload.Delta
		and payload.Delta > -math.huge
		and payload.Delta < math.huge then

		newBalance = math.max(currentBalance + math.floor(payload.Delta), 0)
	end

	if not newBalance then
		return
	end

	if currencyKey == "Coins" or currencyKey == "Dollars" then
		balances[currencyKey] = newBalance
	elseif currencyKey:sub(1, 6) == "Event:" then
		local eventId = currencyKey:sub(7)

		if newBalance > 0 then
			balances.Event[eventId] = newBalance
		else
			balances.Event[eventId] = nil
		end
	end

	hasLoadedCurrencies = true
	renderBalances()
end

local function shouldShowCurrencyHud()
	return player:GetAttribute("OnboardingStep") == "Complete"
		and (player:GetAttribute("ControlMode") or "Hotel") ~= "Minigame"
end

local function setRequestInFlight(isInFlight)
	requestInFlight = isInFlight
end

local function queueCurrencyRefresh(reason, delaySeconds, force)
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

		if requestCurrencyRefresh then
			requestCurrencyRefresh(reason or "queued", shouldForce)
		end
	end)
end

requestCurrencyRefresh = function(reason, force)
	if requestInFlight then
		queueCurrencyRefresh(reason, force == true and 0.05 or LOCAL_REQUEST_COOLDOWN_SECONDS, force)
		return
	end

	local now = os.clock()
	local elapsed = now - lastCurrencyRequestAt

	if force ~= true and elapsed < LOCAL_REQUEST_COOLDOWN_SECONDS then
		queueCurrencyRefresh(
			reason,
			LOCAL_REQUEST_COOLDOWN_SECONDS - elapsed + 0.05,
			force
		)
		return
	end

	setRequestInFlight(true)
	lastCurrencyRequestAt = now
	requestSerial += 1

	local thisRequestSerial = requestSerial

	currencyRequest:FireServer("GetCurrencies")

	task.delay(REQUEST_TIMEOUT_SECONDS, function()
		if requestInFlight and requestSerial == thisRequestSerial then
			setRequestInFlight(false)
		end
	end)
end

local function updateVisibility()
	local shouldShow = shouldShowCurrencyHud()
	local wasVisible = container.Visible

	container.Visible = shouldShow

	if shouldShow and (not wasVisible or not hasLoadedCurrencies) then
		requestCurrencyRefresh("visible")
	end
end

currencyRefreshRequested.Event:Connect(function(options)
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

	requestCurrencyRefresh(reason, force)
end)

currencyLocalDelta.Event:Connect(function(payload)
	applyCurrencyLocalDelta(payload)
end)

currencyResult.OnClientEvent:Connect(function(response)
	if typeof(response) ~= "table" then
		return
	end

	setRequestInFlight(false)

	local success = response.Success == true
	local kind = response.Kind
	local message = tostring(response.Message or "")

	if success and kind == "Currencies" then
		applyCurrenciesSnapshot(response.Currencies)
	elseif success and kind == "Coins" then
		applyCurrencyLocalDelta({
			CurrencyKey = "Coins",
			Balance = response.Coins,
		})
	elseif success and kind == "Currency" then
		applyCurrencyLocalDelta({
			CurrencyKey = response.CurrencyKey,
			Balance = response.Balance,
		})
	elseif message:find("Slow down", 1, true) then
		warn(message)
		queueCurrencyRefresh("serverCooldown", LOCAL_REQUEST_COOLDOWN_SECONDS)
	end
end)

player:GetAttributeChangedSignal("OnboardingStep"):Connect(updateVisibility)
player:GetAttributeChangedSignal("ControlMode"):Connect(updateVisibility)

renderBalances()
task.defer(updateVisibility)
