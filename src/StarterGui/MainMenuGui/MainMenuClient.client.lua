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

local GAMEPLAY_GUI_NAMES_TO_HIDE = {
	InventoryGui = true,
	FurnitureCatalogGui = true,
	RoomModeGui = true,
	CurrencyGui = true,
	FurnitureMenuGui = true,
}

local suppressedGuiStates = {}

local background = Instance.new("Frame")
background.Name = "Background"
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(19, 27, 39)
background.BorderSizePixel = 0
background.Visible = false
background.Parent = gui

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(11, 16, 26)),
	ColorSequenceKeypoint.new(0.52, Color3.fromRGB(33, 52, 68)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 18, 30)),
})
gradient.Rotation = 25
gradient.Parent = background

local leftPanel = Instance.new("Frame")
leftPanel.Name = "BrandPanel"
leftPanel.Position = UDim2.fromScale(0.06, 0.16)
leftPanel.Size = UDim2.fromScale(0.38, 0.68)
leftPanel.BackgroundTransparency = 1
leftPanel.Parent = background

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.fromScale(0, 0.08)
title.Size = UDim2.new(1, 0, 0, 62)
title.BackgroundTransparency = 1
title.Text = "Hotel"
title.TextColor3 = Color3.fromRGB(255, 245, 212)
title.TextSize = 52
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBlack
title.Parent = leftPanel

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Position = UDim2.new(0, 0, 0, 82)
subtitle.Size = UDim2.new(1, 0, 0, 58)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Hotel Main Menu"
subtitle.TextColor3 = Color3.fromRGB(225, 232, 230)
subtitle.TextSize = 24
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Font = Enum.Font.GothamBold
subtitle.Parent = leftPanel

local helper = Instance.new("TextLabel")
helper.Name = "Helper"
helper.Position = UDim2.new(0, 0, 0, 150)
helper.Size = UDim2.new(0.88, 0, 0, 80)
helper.BackgroundTransparency = 1
helper.Text = "Choose a room from the Navigator."
helper.TextColor3 = Color3.fromRGB(184, 199, 204)
helper.TextSize = 16
helper.TextWrapped = true
helper.TextXAlignment = Enum.TextXAlignment.Left
helper.TextYAlignment = Enum.TextYAlignment.Top
helper.Font = Enum.Font.GothamMedium
helper.Parent = leftPanel

local placeholder = Instance.new("Frame")
placeholder.Name = "ImagePlaceholder"
placeholder.AnchorPoint = Vector2.new(0, 1)
placeholder.Position = UDim2.new(0, 0, 1, -34)
placeholder.Size = UDim2.new(0.72, 0, 0, 190)
placeholder.BackgroundColor3 = Color3.fromRGB(46, 70, 83)
placeholder.BorderSizePixel = 0
placeholder.Parent = leftPanel

local placeholderCorner = Instance.new("UICorner")
placeholderCorner.CornerRadius = UDim.new(0, 12)
placeholderCorner.Parent = placeholder

local placeholderStroke = Instance.new("UIStroke")
placeholderStroke.Color = Color3.fromRGB(103, 135, 150)
placeholderStroke.Thickness = 1
placeholderStroke.Transparency = 0.2
placeholderStroke.Parent = placeholder

local placeholderText = Instance.new("TextLabel")
placeholderText.Name = "PlaceholderText"
placeholderText.Size = UDim2.fromScale(1, 1)
placeholderText.BackgroundTransparency = 1
placeholderText.Text = "Background image placeholder"
placeholderText.TextColor3 = Color3.fromRGB(211, 224, 226)
placeholderText.TextSize = 15
placeholderText.Font = Enum.Font.GothamMedium
placeholderText.Parent = placeholder

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

	background.Visible = shouldShow
	updateGameplayGuiSuppression(shouldShow)

	if shouldShow and not wasVisible then
		requestNavigatorOpen()
	elseif shouldShow then
		requestNavigatorOpen()
	end
end

playerGui.ChildAdded:Connect(function(child)
	if background.Visible then
		suppressGameplayGui(child)
	end
end)

player:GetAttributeChangedSignal("InHotelMainMenu"):Connect(updateMainMenu)
player:GetAttributeChangedSignal("CurrentRoomName"):Connect(updateMainMenu)
player:GetAttributeChangedSignal("OnboardingStep"):Connect(updateMainMenu)

task.defer(updateMainMenu)
