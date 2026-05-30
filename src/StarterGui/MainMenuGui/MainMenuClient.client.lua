local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
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

local openRoomNavigator = getOrCreateClientEvent("OpenRoomNavigator")

local MAIN_MENU_BACKGROUND_IMAGE = ""
local HOTEL_TITLE = "Hotel"
local HOTEL_SUBTITLE = "Choose a room and start exploring."
local HOTEL_STATUS_TEXT = "Pick a room from the Navigator."

local GAMEPLAY_GUI_NAMES_TO_HIDE = {
	InventoryGui = true,
	FurnitureCatalogGui = true,
	RoomModeGui = true,
	CurrencyGui = true,
	FurnitureMenuGui = true,
}

local suppressedGuiStates = {}
local MAIN_MENU_PANEL_Z_INDEX = 110
local MAIN_MENU_CONTROL_Z_INDEX = 112
local isWorkPanelOpen = false

local function disableDecorativeInput(guiObject)
	if not guiObject:IsA("GuiObject") then
		return
	end

	if guiObject:IsA("TextButton") or guiObject:IsA("ImageButton") then
		return
	end

	guiObject.Active = false
	guiObject.Selectable = false
end

local background = Instance.new("Frame")
background.Name = "Background"
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(20, 28, 32)
background.BorderSizePixel = 0
background.Visible = false
background.Parent = gui

local backgroundImage = Instance.new("ImageLabel")
backgroundImage.Name = "BackgroundImage"
backgroundImage.Size = UDim2.fromScale(1, 1)
backgroundImage.BackgroundTransparency = 1
backgroundImage.Image = MAIN_MENU_BACKGROUND_IMAGE
backgroundImage.ScaleType = Enum.ScaleType.Crop
backgroundImage.Visible = MAIN_MENU_BACKGROUND_IMAGE ~= ""
backgroundImage.Parent = background

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(21, 32, 37)),
	ColorSequenceKeypoint.new(0.42, Color3.fromRGB(46, 67, 68)),
	ColorSequenceKeypoint.new(0.72, Color3.fromRGB(88, 84, 62)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 29, 36)),
})
gradient.Rotation = 18
gradient.Parent = background

local imageShade = Instance.new("Frame")
imageShade.Name = "ImageShade"
imageShade.Size = UDim2.fromScale(1, 1)
imageShade.BackgroundColor3 = Color3.fromRGB(6, 10, 12)
imageShade.BackgroundTransparency = MAIN_MENU_BACKGROUND_IMAGE ~= "" and 0.38 or 0.82
imageShade.BorderSizePixel = 0
imageShade.Parent = background

local floorBand = Instance.new("Frame")
floorBand.Name = "LobbyFloorBand"
floorBand.AnchorPoint = Vector2.new(0, 1)
floorBand.Position = UDim2.fromScale(0, 1)
floorBand.Size = UDim2.new(1, 0, 0.28, 0)
floorBand.BackgroundColor3 = Color3.fromRGB(65, 58, 46)
floorBand.BackgroundTransparency = 0.2
floorBand.BorderSizePixel = 0
floorBand.Parent = background

local floorGradient = Instance.new("UIGradient")
floorGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(52, 55, 52)),
	ColorSequenceKeypoint.new(0.52, Color3.fromRGB(92, 78, 52)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 35, 39)),
})
floorGradient.Rotation = 0
floorGradient.Parent = floorBand

local skyline = Instance.new("Frame")
skyline.Name = "HotelBackdrop"
skyline.AnchorPoint = Vector2.new(0, 1)
skyline.Position = UDim2.new(0, 0, 1, -96)
skyline.Size = UDim2.new(0.54, 0, 0.32, 0)
skyline.BackgroundTransparency = 1
skyline.Visible = MAIN_MENU_BACKGROUND_IMAGE == ""
skyline.Parent = background

local function createBackdropBlock(name, xScale, yScale, widthScale, heightScale, color)
	local block = Instance.new("Frame")
	block.Name = name
	block.AnchorPoint = Vector2.new(0, 1)
	block.Position = UDim2.fromScale(xScale, yScale)
	block.Size = UDim2.fromScale(widthScale, heightScale)
	block.BackgroundColor3 = color
	block.BackgroundTransparency = 0.1
	block.BorderSizePixel = 0
	block.Parent = skyline

	local blockCorner = Instance.new("UICorner")
	blockCorner.CornerRadius = UDim.new(0, 6)
	blockCorner.Parent = block

	return block
end

createBackdropBlock("HotelWingLeft", 0.03, 1, 0.18, 0.62, Color3.fromRGB(49, 71, 69))
createBackdropBlock("HotelTower", 0.18, 1, 0.22, 0.9, Color3.fromRGB(66, 83, 74))
createBackdropBlock("HotelLobby", 0.37, 1, 0.27, 0.54, Color3.fromRGB(86, 78, 58))
createBackdropBlock("PalmBase", 0.66, 1, 0.08, 0.44, Color3.fromRGB(45, 72, 54))

local leftPanel = Instance.new("Frame")
leftPanel.Name = "BrandPanel"
leftPanel.Position = UDim2.fromScale(0.055, 0.16)
leftPanel.Size = UDim2.fromScale(0.38, 0.56)
leftPanel.BackgroundColor3 = Color3.fromRGB(244, 238, 214)
leftPanel.BackgroundTransparency = 0.06
leftPanel.BorderSizePixel = 0
leftPanel.ZIndex = MAIN_MENU_PANEL_Z_INDEX
leftPanel.Parent = background

local leftPanelSize = Instance.new("UISizeConstraint")
leftPanelSize.MinSize = Vector2.new(280, 240)
leftPanelSize.MaxSize = Vector2.new(520, 460)
leftPanelSize.Parent = leftPanel

local leftPanelCorner = Instance.new("UICorner")
leftPanelCorner.CornerRadius = UDim.new(0, 12)
leftPanelCorner.Parent = leftPanel

local leftPanelStroke = Instance.new("UIStroke")
leftPanelStroke.Color = Color3.fromRGB(255, 250, 226)
leftPanelStroke.Thickness = 1
leftPanelStroke.Transparency = 0.38
leftPanelStroke.Parent = leftPanel

local leftPanelPadding = Instance.new("UIPadding")
leftPanelPadding.PaddingTop = UDim.new(0, 26)
leftPanelPadding.PaddingBottom = UDim.new(0, 24)
leftPanelPadding.PaddingLeft = UDim.new(0, 26)
leftPanelPadding.PaddingRight = UDim.new(0, 26)
leftPanelPadding.Parent = leftPanel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.fromOffset(0, 0)
title.Size = UDim2.new(1, 0, 0, 58)
title.BackgroundTransparency = 1
title.Text = HOTEL_TITLE
title.TextColor3 = Color3.fromRGB(53, 61, 56)
title.TextSize = 48
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBlack
title.Parent = leftPanel

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Position = UDim2.fromOffset(0, 68)
subtitle.Size = UDim2.new(1, 0, 0, 54)
subtitle.BackgroundTransparency = 1
subtitle.Text = HOTEL_SUBTITLE
subtitle.TextColor3 = Color3.fromRGB(80, 88, 82)
subtitle.TextSize = 20
subtitle.TextWrapped = true
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Font = Enum.Font.GothamBold
subtitle.Parent = leftPanel

local helper = Instance.new("TextLabel")
helper.Name = "Helper"
helper.Position = UDim2.new(0, 0, 1, -50)
helper.Size = UDim2.new(1, 0, 0, 38)
helper.BackgroundTransparency = 1
helper.Text = HOTEL_STATUS_TEXT
helper.TextColor3 = Color3.fromRGB(91, 98, 92)
helper.TextSize = 15
helper.TextWrapped = true
helper.TextXAlignment = Enum.TextXAlignment.Left
helper.TextYAlignment = Enum.TextYAlignment.Top
helper.Font = Enum.Font.GothamMedium
helper.ZIndex = MAIN_MENU_CONTROL_Z_INDEX
helper.Parent = leftPanel

local statusCard = Instance.new("Frame")
statusCard.Name = "StatusCard"
statusCard.Position = UDim2.fromOffset(0, 144)
statusCard.Size = UDim2.new(1, 0, 0, 118)
statusCard.BackgroundColor3 = Color3.fromRGB(229, 219, 184)
statusCard.BorderSizePixel = 0
statusCard.ZIndex = MAIN_MENU_CONTROL_Z_INDEX
statusCard.Parent = leftPanel

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 10)
statusCorner.Parent = statusCard

local statusStroke = Instance.new("UIStroke")
statusStroke.Color = Color3.fromRGB(178, 160, 107)
statusStroke.Thickness = 1
statusStroke.Transparency = 0.38
statusStroke.Parent = statusCard

local statusText = Instance.new("TextLabel")
statusText.Name = "StatusText"
statusText.Position = UDim2.fromOffset(18, 13)
statusText.Size = UDim2.new(1, -36, 0, 40)
statusText.BackgroundTransparency = 1
statusText.Text = "Welcome back. The Navigator is ready on the right."
statusText.TextColor3 = Color3.fromRGB(71, 69, 58)
statusText.TextSize = 15
statusText.TextWrapped = true
statusText.TextXAlignment = Enum.TextXAlignment.Left
statusText.TextYAlignment = Enum.TextYAlignment.Center
statusText.Font = Enum.Font.GothamMedium
statusText.ZIndex = MAIN_MENU_CONTROL_Z_INDEX + 1
statusText.Parent = statusCard

local workButton = Instance.new("TextButton")
workButton.Name = "WorkButton"
workButton.Position = UDim2.fromOffset(18, 64)
workButton.Size = UDim2.new(0, 142, 0, 38)
workButton.BackgroundColor3 = Color3.fromRGB(42, 67, 83)
workButton.BorderSizePixel = 0
workButton.Text = "Work"
workButton.TextColor3 = Color3.fromRGB(255, 255, 255)
workButton.TextSize = 18
workButton.Font = Enum.Font.GothamBold
workButton.ZIndex = MAIN_MENU_CONTROL_Z_INDEX + 2
workButton.Parent = statusCard

local workButtonCorner = Instance.new("UICorner")
workButtonCorner.CornerRadius = UDim.new(0, 8)
workButtonCorner.Parent = workButton

local workButtonStroke = Instance.new("UIStroke")
workButtonStroke.Color = Color3.fromRGB(255, 250, 226)
workButtonStroke.Thickness = 1
workButtonStroke.Transparency = 0.5
workButtonStroke.Parent = workButton

local workPanel = Instance.new("Frame")
workPanel.Name = "WorkPanel"
workPanel.Position = UDim2.fromOffset(0, 0)
workPanel.Size = UDim2.fromScale(1, 1)
workPanel.BackgroundTransparency = 1
workPanel.BorderSizePixel = 0
workPanel.Visible = false
workPanel.ZIndex = MAIN_MENU_CONTROL_Z_INDEX
workPanel.Parent = leftPanel

local workTitle = Instance.new("TextLabel")
workTitle.Name = "Title"
workTitle.Position = UDim2.fromOffset(0, 0)
workTitle.Size = UDim2.new(1, -96, 0, 48)
workTitle.BackgroundTransparency = 1
workTitle.Text = "Work"
workTitle.TextColor3 = Color3.fromRGB(53, 61, 56)
workTitle.TextSize = 42
workTitle.TextXAlignment = Enum.TextXAlignment.Left
workTitle.Font = Enum.Font.GothamBlack
workTitle.ZIndex = MAIN_MENU_CONTROL_Z_INDEX + 1
workTitle.Parent = workPanel

local workBackButton = Instance.new("TextButton")
workBackButton.Name = "BackButton"
workBackButton.AnchorPoint = Vector2.new(1, 0)
workBackButton.Position = UDim2.new(1, 0, 0, 8)
workBackButton.Size = UDim2.fromOffset(82, 34)
workBackButton.BackgroundColor3 = Color3.fromRGB(229, 219, 184)
workBackButton.BorderSizePixel = 0
workBackButton.Text = "Back"
workBackButton.TextColor3 = Color3.fromRGB(62, 64, 58)
workBackButton.TextSize = 15
workBackButton.Font = Enum.Font.GothamBold
workBackButton.ZIndex = MAIN_MENU_CONTROL_Z_INDEX + 2
workBackButton.Parent = workPanel

local workBackCorner = Instance.new("UICorner")
workBackCorner.CornerRadius = UDim.new(0, 8)
workBackCorner.Parent = workBackButton

local workBackStroke = Instance.new("UIStroke")
workBackStroke.Color = Color3.fromRGB(178, 160, 107)
workBackStroke.Thickness = 1
workBackStroke.Transparency = 0.34
workBackStroke.Parent = workBackButton

local workSubtitle = Instance.new("TextLabel")
workSubtitle.Name = "Subtitle"
workSubtitle.Position = UDim2.fromOffset(0, 58)
workSubtitle.Size = UDim2.new(1, 0, 0, 48)
workSubtitle.BackgroundTransparency = 1
workSubtitle.Text = "Earn Dollars by completing simple jobs."
workSubtitle.TextColor3 = Color3.fromRGB(80, 88, 82)
workSubtitle.TextSize = 18
workSubtitle.TextWrapped = true
workSubtitle.TextXAlignment = Enum.TextXAlignment.Left
workSubtitle.Font = Enum.Font.GothamBold
workSubtitle.ZIndex = MAIN_MENU_CONTROL_Z_INDEX + 1
workSubtitle.Parent = workPanel

local workInfoCard = Instance.new("Frame")
workInfoCard.Name = "InfoCard"
workInfoCard.Position = UDim2.fromOffset(0, 122)
workInfoCard.Size = UDim2.new(1, 0, 0, 136)
workInfoCard.BackgroundColor3 = Color3.fromRGB(229, 219, 184)
workInfoCard.BorderSizePixel = 0
workInfoCard.ZIndex = MAIN_MENU_CONTROL_Z_INDEX + 1
workInfoCard.Parent = workPanel

local workInfoCorner = Instance.new("UICorner")
workInfoCorner.CornerRadius = UDim.new(0, 10)
workInfoCorner.Parent = workInfoCard

local workInfoStroke = Instance.new("UIStroke")
workInfoStroke.Color = Color3.fromRGB(178, 160, 107)
workInfoStroke.Thickness = 1
workInfoStroke.Transparency = 0.38
workInfoStroke.Parent = workInfoCard

local workBody = Instance.new("TextLabel")
workBody.Name = "Body"
workBody.Position = UDim2.fromOffset(18, 14)
workBody.Size = UDim2.new(1, -36, 0, 34)
workBody.BackgroundTransparency = 1
workBody.Text = "Jobs are coming soon."
workBody.TextColor3 = Color3.fromRGB(71, 69, 58)
workBody.TextSize = 16
workBody.TextWrapped = true
workBody.TextXAlignment = Enum.TextXAlignment.Left
workBody.TextYAlignment = Enum.TextYAlignment.Center
workBody.Font = Enum.Font.GothamMedium
workBody.ZIndex = MAIN_MENU_CONTROL_Z_INDEX + 2
workBody.Parent = workInfoCard

local placeholderCard = Instance.new("Frame")
placeholderCard.Name = "HotelHelperCard"
placeholderCard.Position = UDim2.fromOffset(18, 58)
placeholderCard.Size = UDim2.new(1, -36, 0, 60)
placeholderCard.BackgroundColor3 = Color3.fromRGB(245, 239, 215)
placeholderCard.BorderSizePixel = 0
placeholderCard.ZIndex = MAIN_MENU_CONTROL_Z_INDEX + 2
placeholderCard.Parent = workInfoCard

local placeholderCorner = Instance.new("UICorner")
placeholderCorner.CornerRadius = UDim.new(0, 8)
placeholderCorner.Parent = placeholderCard

local placeholderTitle = Instance.new("TextLabel")
placeholderTitle.Name = "Title"
placeholderTitle.Position = UDim2.fromOffset(14, 8)
placeholderTitle.Size = UDim2.new(1, -28, 0, 22)
placeholderTitle.BackgroundTransparency = 1
placeholderTitle.Text = "Hotel Helper"
placeholderTitle.TextColor3 = Color3.fromRGB(53, 61, 56)
placeholderTitle.TextSize = 16
placeholderTitle.TextXAlignment = Enum.TextXAlignment.Left
placeholderTitle.Font = Enum.Font.GothamBold
placeholderTitle.ZIndex = MAIN_MENU_CONTROL_Z_INDEX + 3
placeholderTitle.Parent = placeholderCard

local placeholderReward = Instance.new("TextLabel")
placeholderReward.Name = "Reward"
placeholderReward.Position = UDim2.fromOffset(14, 32)
placeholderReward.Size = UDim2.new(1, -28, 0, 20)
placeholderReward.BackgroundTransparency = 1
placeholderReward.Text = "Reward: Dollars  |  Coming soon"
placeholderReward.TextColor3 = Color3.fromRGB(91, 98, 92)
placeholderReward.TextSize = 14
placeholderReward.TextXAlignment = Enum.TextXAlignment.Left
placeholderReward.Font = Enum.Font.GothamMedium
placeholderReward.ZIndex = MAIN_MENU_CONTROL_Z_INDEX + 3
placeholderReward.Parent = placeholderCard

local worldInputBlocker = Instance.new("Frame")
worldInputBlocker.Name = "WorldInputBlocker"
worldInputBlocker.Position = UDim2.fromScale(0, 0)
worldInputBlocker.Size = UDim2.fromScale(1, 1)
worldInputBlocker.BackgroundTransparency = 1
worldInputBlocker.BorderSizePixel = 0
worldInputBlocker.Active = true
worldInputBlocker.Selectable = false
worldInputBlocker.Visible = false
worldInputBlocker.ZIndex = 100
worldInputBlocker.Parent = gui

disableDecorativeInput(background)

for _, descendant in ipairs(background:GetDescendants()) do
	disableDecorativeInput(descendant)
end

local welcomePanelObjects = {
	title,
	subtitle,
	helper,
	statusCard,
}

local function setWorkPanelOpen(isOpen)
	isWorkPanelOpen = isOpen == true and background.Visible == true

	for _, guiObject in ipairs(welcomePanelObjects) do
		guiObject.Visible = not isWorkPanelOpen
	end

	workPanel.Visible = isWorkPanelOpen
	workButton.Active = not isWorkPanelOpen
	workButton.AutoButtonColor = not isWorkPanelOpen
end

local function shouldShowMainMenu()
	if player:GetAttribute("OnboardingStep") ~= "Complete" then
		return false
	end

	if typeof(player:GetAttribute("CurrentRoomName")) == "string" then
		return false
	end

	return player:GetAttribute("InHotelMainMenu") == true
		or player:GetAttribute("CurrentRoomName") == nil
end

local function suppressGameplayGui(screenGui)
	if not screenGui or not screenGui:IsA("ScreenGui") then
		return
	end

	if not GAMEPLAY_GUI_NAMES_TO_HIDE[screenGui.Name] then
		return
	end

	if not suppressedGuiStates[screenGui] then
		suppressedGuiStates[screenGui] = {
			Enabled = screenGui.Enabled,
		}
	end

	screenGui.Enabled = false
end

local function updateGameplayGuiSuppression(isMainMenuActive)
	if isMainMenuActive then
		for _, child in ipairs(playerGui:GetChildren()) do
			suppressGameplayGui(child)
		end

		return
	end

	for screenGui, state in pairs(suppressedGuiStates) do
		if screenGui.Parent then
			screenGui.Enabled = state.Enabled
		end
	end

	suppressedGuiStates = {}
end

local function requestNavigatorOpen()
	local payload = {
		Mode = "MainMenuDocked",
	}

	for attempt = 1, 4 do
		task.delay((attempt - 1) * 0.35, function()
			if not background.Visible then
				return
			end

			openRoomNavigator:Fire(payload)
		end)
	end
end

local function updateMainMenu()
	local shouldShow = shouldShowMainMenu()
	local wasVisible = background.Visible

	if not shouldShow or not wasVisible then
		setWorkPanelOpen(false)
	end

	background.Visible = shouldShow
	worldInputBlocker.Visible = shouldShow
	updateGameplayGuiSuppression(shouldShow)

	if shouldShow and not wasVisible then
		requestNavigatorOpen()
	elseif shouldShow then
		requestNavigatorOpen()
	end
end

workButton.MouseButton1Click:Connect(function()
	if not shouldShowMainMenu() then
		return
	end

	setWorkPanelOpen(true)
end)

workBackButton.MouseButton1Click:Connect(function()
	setWorkPanelOpen(false)
end)

playerGui.ChildAdded:Connect(function(child)
	if background.Visible then
		suppressGameplayGui(child)
	end
end)

player:GetAttributeChangedSignal("InHotelMainMenu"):Connect(updateMainMenu)
player:GetAttributeChangedSignal("CurrentRoomName"):Connect(updateMainMenu)
player:GetAttributeChangedSignal("OnboardingStep"):Connect(updateMainMenu)

task.defer(updateMainMenu)
