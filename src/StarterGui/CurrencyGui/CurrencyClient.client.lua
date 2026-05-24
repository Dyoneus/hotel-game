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
local dailyStatusRequestInFlight = false
local dailyStatusRefreshQueued = false
local lastDailyStatusRequestAt = -math.huge
local hasLoadedDailyStatus = false
local dailyRewardStatus = nil
local dailyClaimInFlight = false
local dailyMessageText = ""

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

local dailyContainer = Instance.new("Frame")
dailyContainer.Name = "DailyRewardHud"
dailyContainer.AnchorPoint = Vector2.new(0.5, 0)
dailyContainer.Position = UDim2.new(0.5, 0, 0, 54)
dailyContainer.Size = UDim2.fromOffset(320, 34)
dailyContainer.BackgroundTransparency = 1
dailyContainer.Visible = false
dailyContainer.Parent = gui

local dailyClaimButton = Instance.new("TextButton")
dailyClaimButton.Name = "DailyClaimButton"
dailyClaimButton.Position = UDim2.fromOffset(0, 0)
dailyClaimButton.Size = UDim2.fromOffset(142, 32)
dailyClaimButton.BackgroundColor3 = Color3.fromRGB(70, 135, 90)
dailyClaimButton.BorderSizePixel = 0
dailyClaimButton.Text = "Daily..."
dailyClaimButton.TextColor3 = Color3.fromRGB(255, 255, 255)
dailyClaimButton.TextSize = 13
dailyClaimButton.Font = Enum.Font.GothamBold
dailyClaimButton.Active = false
dailyClaimButton.AutoButtonColor = false
dailyClaimButton.Parent = dailyContainer

createCorner(dailyClaimButton, 8)
createStroke(dailyClaimButton, Color3.fromRGB(255, 255, 255), 1, 0.45)

local dailyMessageLabel = Instance.new("TextLabel")
dailyMessageLabel.Name = "DailyMessageLabel"
dailyMessageLabel.Position = UDim2.fromOffset(152, 0)
dailyMessageLabel.Size = UDim2.new(1, -152, 0, 32)
dailyMessageLabel.BackgroundTransparency = 1
dailyMessageLabel.Text = ""
dailyMessageLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
dailyMessageLabel.TextSize = 13
dailyMessageLabel.TextXAlignment = Enum.TextXAlignment.Left
dailyMessageLabel.TextWrapped = true
dailyMessageLabel.Font = Enum.Font.GothamMedium
dailyMessageLabel.Parent = dailyContainer

local requestCurrencyRefresh = nil
local requestDailyRewardStatus = nil

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

local function normalizeDailyRewardStatus(status)
	if typeof(status) ~= "table" then
		return nil
	end

	local rewardAmount = normalizeBalance(status.RewardAmount)
	local streak = normalizeBalance(status.Streak)

	return {
		CanClaim = status.CanClaim == true,
		LastClaimDay = status.LastClaimDay,
		TodayKey = status.TodayKey,
		Streak = streak,
		RewardAmount = rewardAmount > 0 and rewardAmount or 50,
	}
end

local function renderDailyReward()
	local canClaim = false
	local rewardAmount = 50

	if dailyRewardStatus then
		canClaim = dailyRewardStatus.CanClaim == true
		rewardAmount = dailyRewardStatus.RewardAmount
	end

	if dailyClaimInFlight then
		dailyClaimButton.Text = "Claiming..."
		dailyClaimButton.Active = false
		dailyClaimButton.AutoButtonColor = false
		dailyClaimButton.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
	elseif canClaim then
		dailyClaimButton.Text = "Claim Daily +" .. tostring(rewardAmount)
		dailyClaimButton.Active = true
		dailyClaimButton.AutoButtonColor = true
		dailyClaimButton.BackgroundColor3 = Color3.fromRGB(70, 135, 90)
	elseif hasLoadedDailyStatus then
		dailyClaimButton.Text = "Daily Claimed"
		dailyClaimButton.Active = false
		dailyClaimButton.AutoButtonColor = false
		dailyClaimButton.BackgroundColor3 = Color3.fromRGB(95, 100, 105)
	else
		dailyClaimButton.Text = "Daily..."
		dailyClaimButton.Active = false
		dailyClaimButton.AutoButtonColor = false
		dailyClaimButton.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
	end

	dailyMessageLabel.Text = dailyMessageText
end

local function applyDailyRewardStatus(status)
	local normalizedStatus = normalizeDailyRewardStatus(status)

	if not normalizedStatus then
		return
	end

	dailyRewardStatus = normalizedStatus
	hasLoadedDailyStatus = true

	if dailyRewardStatus.CanClaim and dailyMessageText == "Come back tomorrow." then
		dailyMessageText = ""
	elseif not dailyRewardStatus.CanClaim and dailyMessageText == "" then
		dailyMessageText = "Come back tomorrow."
	end

	renderDailyReward()
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

local function queueDailyRewardStatusRefresh(delaySeconds)
	if dailyStatusRefreshQueued then
		return
	end

	dailyStatusRefreshQueued = true

	task.delay(delaySeconds, function()
		dailyStatusRefreshQueued = false

		if requestDailyRewardStatus then
			requestDailyRewardStatus()
		end
	end)
end

requestDailyRewardStatus = function()
	if dailyStatusRequestInFlight or dailyClaimInFlight then
		queueDailyRewardStatusRefresh(LOCAL_REQUEST_COOLDOWN_SECONDS)
		return
	end

	local now = os.clock()
	local elapsed = now - lastDailyStatusRequestAt

	if elapsed < LOCAL_REQUEST_COOLDOWN_SECONDS then
		queueDailyRewardStatusRefresh(LOCAL_REQUEST_COOLDOWN_SECONDS - elapsed + 0.05)
		return
	end

	dailyStatusRequestInFlight = true
	lastDailyStatusRequestAt = now
	currencyRequest:FireServer("GetDailyRewardStatus")

	task.delay(REQUEST_TIMEOUT_SECONDS, function()
		if dailyStatusRequestInFlight then
			dailyStatusRequestInFlight = false
			renderDailyReward()
		end
	end)
end

local function updateVisibility()
	local shouldShow = shouldShowCurrencyHud()
	local wasVisible = container.Visible

	container.Visible = shouldShow
	dailyContainer.Visible = shouldShow

	if shouldShow and (not wasVisible or not hasLoadedCurrencies) then
		requestCurrencyRefresh("visible")
	end

	if shouldShow and (not wasVisible or not hasLoadedDailyStatus) then
		requestDailyRewardStatus()
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

dailyClaimButton.MouseButton1Click:Connect(function()
	if dailyClaimInFlight
		or not dailyRewardStatus
		or dailyRewardStatus.CanClaim ~= true then

		return
	end

	dailyClaimInFlight = true
	dailyMessageText = ""
	renderDailyReward()

	currencyRequest:FireServer("ClaimDailyReward")
end)

currencyResult.OnClientEvent:Connect(function(response)
	if typeof(response) ~= "table" then
		return
	end

	local success = response.Success == true
	local kind = response.Kind
	local message = tostring(response.Message or "")

	if kind ~= "DailyRewardStatus" and kind ~= "DailyRewardClaim" then
		setRequestInFlight(false)
	end

	if success and kind == "Currencies" then
		applyCurrenciesSnapshot(response.Currencies)
	elseif kind == "DailyRewardStatus" then
		dailyStatusRequestInFlight = false

		if success then
			applyDailyRewardStatus(response.Status)
		end
	elseif kind == "DailyRewardClaim" then
		dailyClaimInFlight = false
		dailyStatusRequestInFlight = false

		if success then
			applyCurrencyLocalDelta({
				CurrencyKey = response.CurrencyKey or "Dollars",
				Balance = response.NewCurrencyBalance,
			})

			applyDailyRewardStatus(response.Status)
			dailyMessageText = "Claimed " .. tostring(normalizeBalance(response.RewardAmount)) .. " Dollars!"
			renderDailyReward()
			requestCurrencyRefresh("dailyRewardClaim", true)
		else
			if typeof(response.Status) == "table" then
				applyDailyRewardStatus(response.Status)
			end

			dailyMessageText = message ~= "" and message or "Daily reward unavailable."
			renderDailyReward()
		end
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
