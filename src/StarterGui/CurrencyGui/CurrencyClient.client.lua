-- StarterGui/CurrencyGui/CurrencyClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local currencyRequest = remoteEvents:WaitForChild("CurrencyRequest")
local currencyResult = remoteEvents:WaitForChild("CurrencyResult")
local marketplaceResult = remoteEvents:WaitForChild("MarketplaceResult")

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 120

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

local LOCAL_REQUEST_COOLDOWN_SECONDS = 0.6
local REQUEST_TIMEOUT_SECONDS = 6
local MARKETPLACE_SALE_TOAST_SECONDS = 2
local DAILY_DOLLAR_ICON = ""
local TOP_CURRENCY_HUD_ENABLED = false

local DEFAULT_DAILY_REWARDS = {
	{ Day = 1, CurrencyKey = "Dollars", Amount = 50, Icon = DAILY_DOLLAR_ICON },
	{ Day = 2, CurrencyKey = "Dollars", Amount = 60, Icon = DAILY_DOLLAR_ICON },
	{ Day = 3, CurrencyKey = "Dollars", Amount = 70, Icon = DAILY_DOLLAR_ICON },
	{ Day = 4, CurrencyKey = "Dollars", Amount = 80, Icon = DAILY_DOLLAR_ICON },
	{ Day = 5, CurrencyKey = "Dollars", Amount = 90, Icon = DAILY_DOLLAR_ICON },
	{ Day = 6, CurrencyKey = "Dollars", Amount = 100, Icon = DAILY_DOLLAR_ICON },
	{ Day = 7, CurrencyKey = "Dollars", Amount = 150, Icon = DAILY_DOLLAR_ICON },
}

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
local dailyTimerRunning = false
local dailyAutoShownStatusKey = nil
local dailyHideSerial = 0
local marketplaceSaleToastSerial = 0

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
local closeMajorMenus = getOrCreateClientEvent("CloseMajorMenus")

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

local dailyOpenButton = Instance.new("TextButton")
dailyOpenButton.Name = "DailyRewardButton"
dailyOpenButton.AnchorPoint = Vector2.new(0, 0)
dailyOpenButton.Position = UDim2.new(0.5, 160, 0, 14)
dailyOpenButton.Size = UDim2.fromOffset(78, 34)
dailyOpenButton.BackgroundColor3 = Color3.fromRGB(65, 110, 150)
dailyOpenButton.BorderSizePixel = 0
dailyOpenButton.Text = "Daily"
dailyOpenButton.TextColor3 = Color3.fromRGB(255, 255, 255)
dailyOpenButton.TextSize = 14
dailyOpenButton.Font = Enum.Font.GothamBold
dailyOpenButton.Visible = false
dailyOpenButton.Parent = gui

createCorner(dailyOpenButton, 8)
createStroke(dailyOpenButton, Color3.fromRGB(255, 255, 255), 1, 0.55)

local marketplaceSaleToast = Instance.new("Frame")
marketplaceSaleToast.Name = "MarketplaceSaleToast"
marketplaceSaleToast.AnchorPoint = Vector2.new(1, 0)
marketplaceSaleToast.Position = UDim2.new(1, -16, 0, 62)
marketplaceSaleToast.Size = UDim2.fromOffset(320, 58)
marketplaceSaleToast.BackgroundColor3 = Color3.fromRGB(35, 48, 42)
marketplaceSaleToast.BackgroundTransparency = 1
marketplaceSaleToast.BorderSizePixel = 0
marketplaceSaleToast.Visible = false
marketplaceSaleToast.Parent = gui

createCorner(marketplaceSaleToast, 10)
local marketplaceSaleToastStroke = createStroke(
	marketplaceSaleToast,
	Color3.fromRGB(185, 235, 190),
	1,
	1
)

local marketplaceSaleToastLabel = Instance.new("TextLabel")
marketplaceSaleToastLabel.Name = "Message"
marketplaceSaleToastLabel.Position = UDim2.fromOffset(14, 8)
marketplaceSaleToastLabel.Size = UDim2.new(1, -28, 1, -16)
marketplaceSaleToastLabel.BackgroundTransparency = 1
marketplaceSaleToastLabel.Text = ""
marketplaceSaleToastLabel.TextColor3 = Color3.fromRGB(235, 255, 235)
marketplaceSaleToastLabel.TextTransparency = 1
marketplaceSaleToastLabel.TextSize = 14
marketplaceSaleToastLabel.TextWrapped = true
marketplaceSaleToastLabel.TextXAlignment = Enum.TextXAlignment.Left
marketplaceSaleToastLabel.TextYAlignment = Enum.TextYAlignment.Center
marketplaceSaleToastLabel.Font = Enum.Font.GothamBold
marketplaceSaleToastLabel.Parent = marketplaceSaleToast

local modalOverlay = Instance.new("Frame")
modalOverlay.Name = "DailyRewardOverlay"
modalOverlay.Size = UDim2.fromScale(1, 1)
modalOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
modalOverlay.BackgroundTransparency = 0.42
modalOverlay.BorderSizePixel = 0
modalOverlay.Visible = false
modalOverlay.Parent = gui

local dailyPanel = Instance.new("Frame")
dailyPanel.Name = "DailyRewardPanel"
dailyPanel.AnchorPoint = Vector2.new(0.5, 0.5)
dailyPanel.Position = UDim2.fromScale(0.5, 0.5)
dailyPanel.Size = UDim2.fromOffset(640, 368)
dailyPanel.BackgroundColor3 = Color3.fromRGB(248, 250, 247)
dailyPanel.BorderSizePixel = 0
dailyPanel.Parent = modalOverlay

createCorner(dailyPanel, 12)
createStroke(dailyPanel, Color3.fromRGB(190, 205, 190), 1, 0)

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Position = UDim2.fromOffset(24, 18)
titleLabel.Size = UDim2.new(1, -88, 0, 34)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Daily Reward"
titleLabel.TextColor3 = Color3.fromRGB(32, 42, 36)
titleLabel.TextSize = 24
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Parent = dailyPanel

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Position = UDim2.new(1, -48, 0, 18)
closeButton.Size = UDim2.fromOffset(30, 30)
closeButton.BackgroundColor3 = Color3.fromRGB(225, 230, 225)
closeButton.BorderSizePixel = 0
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(45, 45, 45)
closeButton.TextSize = 14
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = dailyPanel

createCorner(closeButton, 6)

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Name = "SubtitleLabel"
subtitleLabel.Position = UDim2.fromOffset(24, 54)
subtitleLabel.Size = UDim2.new(1, -48, 0, 24)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Text = ""
subtitleLabel.TextColor3 = Color3.fromRGB(82, 90, 82)
subtitleLabel.TextSize = 15
subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
subtitleLabel.Font = Enum.Font.GothamMedium
subtitleLabel.Parent = dailyPanel

local rewardsFrame = Instance.new("Frame")
rewardsFrame.Name = "RewardsFrame"
rewardsFrame.Position = UDim2.fromOffset(24, 94)
rewardsFrame.Size = UDim2.new(1, -48, 0, 124)
rewardsFrame.BackgroundTransparency = 1
rewardsFrame.Parent = dailyPanel

local rewardsGrid = Instance.new("UIGridLayout")
rewardsGrid.CellPadding = UDim2.fromOffset(6, 0)
rewardsGrid.CellSize = UDim2.fromOffset(76, 118)
rewardsGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
rewardsGrid.SortOrder = Enum.SortOrder.LayoutOrder
rewardsGrid.Parent = rewardsFrame

local rewardSlots = {}

for day = 1, 7 do
	local slot = Instance.new("Frame")
	slot.Name = "Day" .. tostring(day)
	slot.LayoutOrder = day
	slot.BackgroundColor3 = Color3.fromRGB(238, 242, 236)
	slot.BorderSizePixel = 0
	slot.Parent = rewardsFrame

	createCorner(slot, 8)
	createStroke(slot, Color3.fromRGB(206, 214, 204), 1, 0)

	local dayLabel = Instance.new("TextLabel")
	dayLabel.Name = "DayLabel"
	dayLabel.Position = UDim2.fromOffset(6, 6)
	dayLabel.Size = UDim2.new(1, -12, 0, 18)
	dayLabel.BackgroundTransparency = 1
	dayLabel.Text = "Day " .. tostring(day)
	dayLabel.TextColor3 = Color3.fromRGB(55, 60, 55)
	dayLabel.TextSize = 12
	dayLabel.Font = Enum.Font.GothamBold
	dayLabel.Parent = slot

	local iconImage = Instance.new("ImageLabel")
	iconImage.Name = "RewardIcon"
	iconImage.Position = UDim2.fromOffset(20, 30)
	iconImage.Size = UDim2.fromOffset(36, 36)
	iconImage.BackgroundTransparency = 1
	iconImage.Image = ""
	iconImage.Visible = false
	iconImage.Parent = slot

	local iconFallback = Instance.new("TextLabel")
	iconFallback.Name = "RewardIconFallback"
	iconFallback.Position = UDim2.fromOffset(20, 28)
	iconFallback.Size = UDim2.fromOffset(36, 38)
	iconFallback.BackgroundColor3 = Color3.fromRGB(210, 238, 205)
	iconFallback.BorderSizePixel = 0
	iconFallback.Text = "$"
	iconFallback.TextColor3 = Color3.fromRGB(54, 124, 70)
	iconFallback.TextSize = 24
	iconFallback.Font = Enum.Font.GothamBold
	iconFallback.Parent = slot

	createCorner(iconFallback, 18)

	local amountLabel = Instance.new("TextLabel")
	amountLabel.Name = "AmountLabel"
	amountLabel.Position = UDim2.fromOffset(5, 70)
	amountLabel.Size = UDim2.new(1, -10, 0, 22)
	amountLabel.BackgroundTransparency = 1
	amountLabel.Text = "+0 Dollars"
	amountLabel.TextColor3 = Color3.fromRGB(45, 75, 48)
	amountLabel.TextSize = 11
	amountLabel.TextWrapped = true
	amountLabel.Font = Enum.Font.GothamBold
	amountLabel.Parent = slot

	local stateLabel = Instance.new("TextLabel")
	stateLabel.Name = "StateLabel"
	stateLabel.Position = UDim2.fromOffset(5, 94)
	stateLabel.Size = UDim2.new(1, -10, 0, 18)
	stateLabel.BackgroundTransparency = 1
	stateLabel.Text = ""
	stateLabel.TextColor3 = Color3.fromRGB(96, 100, 96)
	stateLabel.TextSize = 10
	stateLabel.Font = Enum.Font.GothamMedium
	stateLabel.Parent = slot

	rewardSlots[day] = {
		Frame = slot,
		Stroke = slot:FindFirstChildOfClass("UIStroke"),
		DayLabel = dayLabel,
		IconImage = iconImage,
		IconFallback = iconFallback,
		AmountLabel = amountLabel,
		StateLabel = stateLabel,
	}
end

local dailyMessageLabel = Instance.new("TextLabel")
dailyMessageLabel.Name = "DailyMessageLabel"
dailyMessageLabel.Position = UDim2.fromOffset(24, 232)
dailyMessageLabel.Size = UDim2.new(1, -48, 0, 26)
dailyMessageLabel.BackgroundTransparency = 1
dailyMessageLabel.Text = ""
dailyMessageLabel.TextColor3 = Color3.fromRGB(60, 105, 66)
dailyMessageLabel.TextSize = 14
dailyMessageLabel.TextXAlignment = Enum.TextXAlignment.Center
dailyMessageLabel.Font = Enum.Font.GothamMedium
dailyMessageLabel.Parent = dailyPanel

local dailyClaimButton = Instance.new("TextButton")
dailyClaimButton.Name = "ClaimButton"
dailyClaimButton.AnchorPoint = Vector2.new(0.5, 0)
dailyClaimButton.Position = UDim2.new(0.5, 0, 0, 272)
dailyClaimButton.Size = UDim2.fromOffset(180, 42)
dailyClaimButton.BackgroundColor3 = Color3.fromRGB(70, 135, 90)
dailyClaimButton.BorderSizePixel = 0
dailyClaimButton.Text = "Claim"
dailyClaimButton.TextColor3 = Color3.fromRGB(255, 255, 255)
dailyClaimButton.TextSize = 17
dailyClaimButton.Font = Enum.Font.GothamBold
dailyClaimButton.Parent = dailyPanel

createCorner(dailyClaimButton, 8)

local requestCurrencyRefresh = nil
local requestDailyRewardStatus = nil
local setDailyModalVisible = nil
local renderDailyReward = nil

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

local function formatDuration(seconds)
	local totalSeconds = math.max(math.floor(tonumber(seconds) or 0), 0)
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	local remainingSeconds = totalSeconds % 60

	return string.format("%02d:%02d:%02d", hours, minutes, remainingSeconds)
end

local function getSecondsUntilNextClaim()
	if not dailyRewardStatus then
		return 0
	end

	if dailyRewardStatus.CanClaim then
		return 0
	end

	if isNonNegativeNumber(dailyRewardStatus.NextClaimUnix) then
		return math.max(math.floor(dailyRewardStatus.NextClaimUnix - os.time()), 0)
	end

	return normalizeBalance(dailyRewardStatus.SecondsUntilNextClaim)
end

local function renderBalances()
	coinsLabel.Text = "Coins: " .. tostring(normalizeBalance(balances.Coins))
	dollarsLabel.Text = "Dollars: " .. tostring(normalizeBalance(balances.Dollars))
end

local function normalizeRewardEntry(entry, fallbackDay)
	if typeof(entry) ~= "table" then
		local fallback = DEFAULT_DAILY_REWARDS[fallbackDay]

		return {
			Day = fallback.Day,
			CurrencyKey = fallback.CurrencyKey,
			Amount = fallback.Amount,
			Icon = fallback.Icon,
		}
	end

	local day = normalizeBalance(entry.Day)

	if day <= 0 then
		day = fallbackDay
	end

	local amount = normalizeBalance(entry.Amount)

	if amount <= 0 then
		amount = DEFAULT_DAILY_REWARDS[fallbackDay].Amount
	end

	local currencyKey = entry.CurrencyKey

	if typeof(currencyKey) ~= "string" or currencyKey == "" then
		currencyKey = "Dollars"
	end

	local icon = entry.Icon

	if typeof(icon) ~= "string" then
		icon = DAILY_DOLLAR_ICON
	end

	return {
		Day = day,
		CurrencyKey = currencyKey,
		Amount = amount,
		Icon = icon,
	}
end

local function normalizeRewards(rewards)
	local normalized = {}

	for day = 1, 7 do
		local entry = nil

		if typeof(rewards) == "table" then
			entry = rewards[day]
		end

		normalized[day] = normalizeRewardEntry(entry, day)
	end

	return normalized
end

local function normalizeDailyRewardStatus(status)
	if typeof(status) ~= "table" then
		return nil
	end

	local rewardAmount = normalizeBalance(status.RewardAmount)
	local streak = normalizeBalance(status.Streak)
	local currentDayIndex = normalizeBalance(status.CurrentDayIndex)

	if currentDayIndex < 1 then
		currentDayIndex = math.clamp(streak + 1, 1, 7)
	else
		currentDayIndex = math.clamp(currentDayIndex, 1, 7)
	end

	if rewardAmount <= 0 then
		rewardAmount = DEFAULT_DAILY_REWARDS[currentDayIndex].Amount
	end

	return {
		CanClaim = status.CanClaim == true,
		ClaimedToday = status.ClaimedToday == true,
		LastClaimUnix = status.LastClaimUnix,
		Streak = streak,
		CurrentDayIndex = currentDayIndex,
		RewardAmount = rewardAmount,
		NextClaimUnix = status.NextClaimUnix,
		SecondsUntilNextClaim = normalizeBalance(status.SecondsUntilNextClaim),
		StreakResetPending = status.StreakResetPending == true,
		Rewards = normalizeRewards(status.Rewards),
	}
end

local function shouldShowCurrencyHud()
	return TOP_CURRENCY_HUD_ENABLED
		and player:GetAttribute("OnboardingStep") == "Complete"
		and (player:GetAttribute("ControlMode") or "Hotel") ~= "Minigame"
end

local function updateDailyButton()
	local canClaim = dailyRewardStatus and dailyRewardStatus.CanClaim == true
	local rewardAmount = dailyRewardStatus and dailyRewardStatus.RewardAmount or 0

	if dailyClaimInFlight then
		dailyOpenButton.Text = "Daily..."
		dailyOpenButton.BackgroundColor3 = Color3.fromRGB(115, 120, 125)
	elseif canClaim then
		dailyOpenButton.Text = "Daily!"
		dailyOpenButton.BackgroundColor3 = Color3.fromRGB(70, 135, 90)
	elseif hasLoadedDailyStatus then
		dailyOpenButton.Text = "Daily"
		dailyOpenButton.BackgroundColor3 = Color3.fromRGB(65, 110, 150)
	else
		dailyOpenButton.Text = "Daily"
		dailyOpenButton.BackgroundColor3 = Color3.fromRGB(115, 120, 125)
	end

	dailyOpenButton.Active = shouldShowCurrencyHud()
	dailyOpenButton.AutoButtonColor = dailyOpenButton.Active

	if canClaim and rewardAmount > 0 then
		dailyOpenButton.Text = "Daily!"
	end
end

local function ensureDailyTimer()
	if dailyTimerRunning then
		return
	end

	if not modalOverlay.Visible
		or not dailyRewardStatus
		or dailyRewardStatus.CanClaim then

		return
	end

	dailyTimerRunning = true

	task.spawn(function()
		while modalOverlay.Visible and dailyRewardStatus and not dailyRewardStatus.CanClaim do
			if renderDailyReward then
				renderDailyReward()
			end

			if getSecondsUntilNextClaim() <= 0 then
				if requestDailyRewardStatus then
					requestDailyRewardStatus()
				end

				break
			end

			task.wait(1)
		end

		dailyTimerRunning = false
	end)
end

renderDailyReward = function()
	updateDailyButton()

	if not modalOverlay.Visible then
		return
	end

	local status = dailyRewardStatus
	local canClaim = status and status.CanClaim == true
	local currentDayIndex = status and status.CurrentDayIndex or 1
	local streak = status and (status.StreakResetPending and 0 or status.Streak) or 0
	local rewards = status and status.Rewards or DEFAULT_DAILY_REWARDS

	if dailyClaimInFlight then
		subtitleLabel.Text = "Claiming your daily reward..."
	elseif canClaim and status and status.StreakResetPending then
		subtitleLabel.Text = "Your streak reset. Day 1 reward is ready!"
	elseif canClaim then
		subtitleLabel.Text = "Your daily reward is ready!"
	elseif status then
		subtitleLabel.Text = "Next reward in " .. formatDuration(getSecondsUntilNextClaim())
	else
		subtitleLabel.Text = "Loading daily reward..."
	end

	for day = 1, 7 do
		local slot = rewardSlots[day]
		local reward = rewards[day] or DEFAULT_DAILY_REWARDS[day]
		local isReady = canClaim and day == currentDayIndex
		local isClaimed = day <= math.clamp(streak, 0, 7)
		local isFuture = not isClaimed and not isReady
		local icon = reward.Icon

		slot.DayLabel.Text = "Day " .. tostring(day)
		slot.AmountLabel.Text = "+" .. tostring(normalizeBalance(reward.Amount)) .. " " .. tostring(reward.CurrencyKey or "Dollars")
		slot.IconImage.Image = typeof(icon) == "string" and icon or ""
		slot.IconImage.Visible = typeof(icon) == "string" and icon ~= ""
		slot.IconFallback.Visible = not slot.IconImage.Visible

		if isReady then
			slot.Frame.BackgroundColor3 = Color3.fromRGB(224, 244, 220)
			slot.Stroke.Color = Color3.fromRGB(70, 150, 86)
			slot.Stroke.Thickness = 2
			slot.StateLabel.Text = "Ready"
			slot.StateLabel.TextColor3 = Color3.fromRGB(42, 118, 62)
		elseif isClaimed then
			slot.Frame.BackgroundColor3 = Color3.fromRGB(232, 238, 232)
			slot.Stroke.Color = Color3.fromRGB(145, 165, 145)
			slot.Stroke.Thickness = 1
			slot.StateLabel.Text = "Claimed"
			slot.StateLabel.TextColor3 = Color3.fromRGB(86, 105, 86)
		elseif isFuture then
			slot.Frame.BackgroundColor3 = Color3.fromRGB(238, 238, 238)
			slot.Stroke.Color = Color3.fromRGB(216, 216, 216)
			slot.Stroke.Thickness = 1
			slot.StateLabel.Text = "Soon"
			slot.StateLabel.TextColor3 = Color3.fromRGB(130, 130, 130)
		end

		slot.Frame.BackgroundTransparency = isFuture and 0.18 or 0
		slot.AmountLabel.TextColor3 = isFuture and Color3.fromRGB(120, 120, 120) or Color3.fromRGB(45, 75, 48)
		slot.DayLabel.TextColor3 = isFuture and Color3.fromRGB(120, 120, 120) or Color3.fromRGB(55, 60, 55)
	end

	dailyMessageLabel.Text = dailyMessageText

	if dailyClaimInFlight then
		dailyClaimButton.Text = "Claiming..."
		dailyClaimButton.Active = false
		dailyClaimButton.AutoButtonColor = false
		dailyClaimButton.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
	elseif canClaim then
		dailyClaimButton.Text = "Claim"
		dailyClaimButton.Active = true
		dailyClaimButton.AutoButtonColor = true
		dailyClaimButton.BackgroundColor3 = Color3.fromRGB(70, 135, 90)
	elseif hasLoadedDailyStatus then
		dailyClaimButton.Text = "Claimed"
		dailyClaimButton.Active = false
		dailyClaimButton.AutoButtonColor = false
		dailyClaimButton.BackgroundColor3 = Color3.fromRGB(95, 100, 105)
	else
		dailyClaimButton.Text = "Loading..."
		dailyClaimButton.Active = false
		dailyClaimButton.AutoButtonColor = false
		dailyClaimButton.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
	end

	ensureDailyTimer()
end

setDailyModalVisible = function(isVisible, shouldRequestStatus)
	if isVisible then
		if not shouldShowCurrencyHud() then
			return
		end

		closeMajorMenus:Fire()
		modalOverlay.Visible = true

		if shouldRequestStatus and requestDailyRewardStatus then
			requestDailyRewardStatus()
		end
	else
		modalOverlay.Visible = false

		if dailyMessageText:match("^Claimed ") then
			dailyMessageText = ""
		end
	end

	renderDailyReward()
end

local function applyDailyRewardStatus(status)
	local normalizedStatus = normalizeDailyRewardStatus(status)

	if not normalizedStatus then
		return
	end

	dailyRewardStatus = normalizedStatus
	hasLoadedDailyStatus = true

	if dailyRewardStatus.CanClaim then
		if dailyMessageText == "Come back later." then
			dailyMessageText = ""
		end

		local autoShowKey = tostring(dailyRewardStatus.LastClaimUnix or "fresh")
			.. ":"
			.. tostring(dailyRewardStatus.CurrentDayIndex)
			.. ":"
			.. tostring(dailyRewardStatus.StreakResetPending)

		if shouldShowCurrencyHud()
			and dailyAutoShownStatusKey ~= autoShowKey then

			dailyAutoShownStatusKey = autoShowKey
			setDailyModalVisible(true, false)
		end
	elseif dailyMessageText == "" then
		dailyMessageText = "Come back later."
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

local function showMarketplaceSaleToast(message)
	marketplaceSaleToastSerial += 1
	local toastSerial = marketplaceSaleToastSerial

	marketplaceSaleToastLabel.Text = tostring(message or "")
	marketplaceSaleToast.Visible = true
	marketplaceSaleToast.BackgroundTransparency = 1
	marketplaceSaleToastStroke.Transparency = 1
	marketplaceSaleToastLabel.TextTransparency = 1

	TweenService:Create(
		marketplaceSaleToast,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			BackgroundTransparency = 0.08,
		}
	):Play()

	TweenService:Create(
		marketplaceSaleToastStroke,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Transparency = 0.25,
		}
	):Play()

	TweenService:Create(
		marketplaceSaleToastLabel,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			TextTransparency = 0,
		}
	):Play()

	task.delay(MARKETPLACE_SALE_TOAST_SECONDS, function()
		if marketplaceSaleToastSerial ~= toastSerial then
			return
		end

		TweenService:Create(
			marketplaceSaleToast,
			TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{
				BackgroundTransparency = 1,
			}
		):Play()

		TweenService:Create(
			marketplaceSaleToastStroke,
			TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{
				Transparency = 1,
			}
		):Play()

		TweenService:Create(
			marketplaceSaleToastLabel,
			TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{
				TextTransparency = 1,
			}
		):Play()

		task.delay(0.36, function()
			if marketplaceSaleToastSerial == toastSerial then
				marketplaceSaleToast.Visible = false
			end
		end)
	end)
end

local function handleMarketplaceListingSold(response)
	if typeof(response) ~= "table" then
		return
	end

	if isNonNegativeNumber(response.NewCoinBalance) then
		applyCurrencyLocalDelta({
			CurrencyKey = response.CurrencyKey or "Coins",
			Balance = response.NewCoinBalance,
		})
	else
		requestCurrencyRefresh("marketplaceListingSold", true)
	end

	showMarketplaceSaleToast("One of your listings has been sold.")
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
	dailyOpenButton.Visible = shouldShow

	if not shouldShow then
		setDailyModalVisible(false, false)
		return
	end

	if shouldShow and (not wasVisible or not hasLoadedCurrencies) then
		requestCurrencyRefresh("visible")
	end

	if shouldShow and (not wasVisible or not hasLoadedDailyStatus) then
		requestDailyRewardStatus()
	end

	renderDailyReward()
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

marketplaceResult.OnClientEvent:Connect(function(response)
	if typeof(response) ~= "table" then
		return
	end

	if response.Success == true and response.Kind == "ListingSold" then
		handleMarketplaceListingSold(response)
	end
end)

dailyOpenButton.MouseButton1Click:Connect(function()
	local shouldRefreshStatus = not hasLoadedDailyStatus

	if dailyRewardStatus
		and dailyRewardStatus.CanClaim ~= true
		and getSecondsUntilNextClaim() <= 0 then

		shouldRefreshStatus = true
	end

	setDailyModalVisible(true, shouldRefreshStatus)
end)

closeButton.MouseButton1Click:Connect(function()
	setDailyModalVisible(false, false)
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
		elseif modalOverlay.Visible then
			dailyMessageText = message ~= "" and message or "Daily reward unavailable."
			renderDailyReward()
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

			dailyHideSerial += 1
			local hideSerial = dailyHideSerial

			task.delay(0.8, function()
				if dailyHideSerial == hideSerial then
					setDailyModalVisible(false, false)
				end
			end)
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
