--Explorer/StarterGui/RoomCreationGui/RoomCreationClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local createRoomRequest = remoteEvents:WaitForChild("CreateRoomRequest")
local roomCreationResult = remoteEvents:WaitForChild("RoomCreationResult")

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

-- Clear old UI
for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

local selectedLayoutId = nil
local selectedCard = nil

player:SetAttribute("RoomCreationUiOpen", false)

local createRoomRequestInFlight = false
local createRoomRequestToken = 0

local layoutData = {
	{
		id = "Layout_01",
		name = "Layout 1",
		description = "Balanced starter room with a clean hotel feel.",
		previewColor = Color3.fromRGB(120, 170, 220),
	},
	{
		id = "Layout_02",
		name = "Layout 2",
		description = "A cozy room style with warmer colors.",
		previewColor = Color3.fromRGB(220, 170, 110),
	},
	{
		id = "Layout_03",
		name = "Layout 3",
		description = "A calm room style with cooler tones.",
		previewColor = Color3.fromRGB(120, 210, 190),
	},
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

local function createPadding(parent, left, right, top, bottom)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, left)
	padding.PaddingRight = UDim.new(0, right)
	padding.PaddingTop = UDim.new(0, top)
	padding.PaddingBottom = UDim.new(0, bottom)
	padding.Parent = parent
	return padding
end

-- Dark transparent background
local dimBackground = Instance.new("Frame")
dimBackground.Name = "DimBackground"
dimBackground.Size = UDim2.fromScale(1, 1)
dimBackground.Position = UDim2.fromScale(0, 0)
dimBackground.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dimBackground.BackgroundTransparency = 0.35
dimBackground.Visible = false
dimBackground.Parent = gui

-- Main panel
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.Position = UDim2.fromScale(0.5, 0.5)
mainFrame.Size = UDim2.fromOffset(720, 430)
mainFrame.BackgroundColor3 = Color3.fromRGB(245, 245, 238)
mainFrame.BorderSizePixel = 0
mainFrame.Visible = false
mainFrame.Parent = dimBackground

createCorner(mainFrame, 18)
createStroke(mainFrame, Color3.fromRGB(255, 255, 255), 2, 0.1)
createPadding(mainFrame, 24, 24, 22, 22)

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.new(1, 0, 0, 42)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Choose Your First Room"
titleLabel.TextColor3 = Color3.fromRGB(45, 45, 45)
titleLabel.TextScaled = true
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Parent = mainFrame

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Name = "SubtitleLabel"
subtitleLabel.Position = UDim2.fromOffset(0, 45)
subtitleLabel.Size = UDim2.new(1, 0, 0, 28)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Text = "Pick a starting layout. You can decorate and customize it later."
subtitleLabel.TextColor3 = Color3.fromRGB(95, 95, 95)
subtitleLabel.TextScaled = true
subtitleLabel.Font = Enum.Font.Gotham
subtitleLabel.Parent = mainFrame

local cardsFrame = Instance.new("Frame")
cardsFrame.Name = "CardsFrame"
cardsFrame.Position = UDim2.fromOffset(0, 95)
cardsFrame.Size = UDim2.new(1, 0, 0, 220)
cardsFrame.BackgroundTransparency = 1
cardsFrame.Parent = mainFrame

local cardsLayout = Instance.new("UIListLayout")
cardsLayout.FillDirection = Enum.FillDirection.Horizontal
cardsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
cardsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
cardsLayout.Padding = UDim.new(0, 18)
cardsLayout.Parent = cardsFrame

local confirmButton = Instance.new("TextButton")
confirmButton.Name = "ConfirmButton"
confirmButton.AnchorPoint = Vector2.new(0.5, 1)
confirmButton.Position = UDim2.new(0.5, 0, 1, -32)
confirmButton.Size = UDim2.fromOffset(260, 48)
confirmButton.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
confirmButton.Text = "Select a Room"
confirmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
confirmButton.TextScaled = true
confirmButton.Font = Enum.Font.GothamBold
confirmButton.AutoButtonColor = false
confirmButton.Parent = mainFrame

createCorner(confirmButton, 12)

local function setCreateRoomRequestInFlight(isInFlight)
	createRoomRequestInFlight = isInFlight

	confirmButton.Active = not isInFlight
	confirmButton.AutoButtonColor = not isInFlight
end

local footerLabel = Instance.new("TextLabel")
footerLabel.Name = "FooterLabel"
footerLabel.AnchorPoint = Vector2.new(0.5, 1)
footerLabel.Position = UDim2.new(0.5, 0, 1, 0)
footerLabel.Size = UDim2.new(1, 0, 0, 22)
footerLabel.BackgroundTransparency = 1
footerLabel.Text = "This choice will become your starter room."
footerLabel.TextColor3 = Color3.fromRGB(115, 115, 115)
footerLabel.TextScaled = true
footerLabel.Font = Enum.Font.Gotham
footerLabel.Parent = mainFrame

local function updateConfirmButton()
	if selectedLayoutId then
		confirmButton.Text = "Create Room"
		confirmButton.BackgroundColor3 = Color3.fromRGB(70, 150, 255)
	else
		confirmButton.Text = "Select a Room"
		confirmButton.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
	end
end

local function setCardSelected(card, isSelected)
	local stroke = card:FindFirstChild("CardStroke")
	local selectedBadge = card:FindFirstChild("SelectedBadge")

	if stroke then
		if isSelected then
			stroke.Color = Color3.fromRGB(70, 150, 255)
			stroke.Thickness = 4
			stroke.Transparency = 0
		else
			stroke.Color = Color3.fromRGB(210, 210, 210)
			stroke.Thickness = 2
			stroke.Transparency = 0
		end
	end

	if selectedBadge then
		selectedBadge.Visible = isSelected
	end
end

local function selectLayout(layoutId, card)
	if selectedCard then
		setCardSelected(selectedCard, false)
	end

	selectedLayoutId = layoutId
	selectedCard = card

	setCardSelected(card, true)
	updateConfirmButton()
end

local function createLayoutCard(data)
	local card = Instance.new("TextButton")
	card.Name = data.id .. "_Card"
	card.Size = UDim2.fromOffset(200, 210)
	card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	card.Text = ""
	card.AutoButtonColor = false
	card.Parent = cardsFrame

	createCorner(card, 14)

	local stroke = createStroke(card, Color3.fromRGB(210, 210, 210), 2, 0)
	stroke.Name = "CardStroke"

	local preview = Instance.new("Frame")
	preview.Name = "Preview"
	preview.Position = UDim2.fromOffset(14, 14)
	preview.Size = UDim2.new(1, -28, 0, 95)
	preview.BackgroundColor3 = data.previewColor
	preview.BorderSizePixel = 0
	preview.Parent = card

	createCorner(preview, 10)

	local fakeFloor = Instance.new("Frame")
	fakeFloor.Name = "FakeFloor"
	fakeFloor.AnchorPoint = Vector2.new(0.5, 0.5)
	fakeFloor.Position = UDim2.fromScale(0.5, 0.55)
	fakeFloor.Size = UDim2.fromOffset(105, 52)
	fakeFloor.Rotation = -12
	fakeFloor.BackgroundColor3 = Color3.fromRGB(245, 245, 235)
	fakeFloor.BorderSizePixel = 0
	fakeFloor.Parent = preview

	createCorner(fakeFloor, 4)

	local fakeWallBack = Instance.new("Frame")
	fakeWallBack.Name = "FakeWallBack"
	fakeWallBack.Position = UDim2.fromOffset(32, 18)
	fakeWallBack.Size = UDim2.fromOffset(110, 10)
	fakeWallBack.BackgroundColor3 = Color3.fromRGB(210, 225, 225)
	fakeWallBack.BorderSizePixel = 0
	fakeWallBack.Parent = preview

	local fakeWallLeft = Instance.new("Frame")
	fakeWallLeft.Name = "FakeWallLeft"
	fakeWallLeft.Position = UDim2.fromOffset(31, 18)
	fakeWallLeft.Size = UDim2.fromOffset(10, 60)
	fakeWallLeft.BackgroundColor3 = Color3.fromRGB(195, 215, 215)
	fakeWallLeft.BorderSizePixel = 0
	fakeWallLeft.Parent = preview

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Position = UDim2.fromOffset(12, 120)
	nameLabel.Size = UDim2.new(1, -24, 0, 28)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = data.name
	nameLabel.TextColor3 = Color3.fromRGB(45, 45, 45)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = card

	local descriptionLabel = Instance.new("TextLabel")
	descriptionLabel.Name = "DescriptionLabel"
	descriptionLabel.Position = UDim2.fromOffset(14, 150)
	descriptionLabel.Size = UDim2.new(1, -28, 0, 42)
	descriptionLabel.BackgroundTransparency = 1
	descriptionLabel.Text = data.description
	descriptionLabel.TextColor3 = Color3.fromRGB(95, 95, 95)
	descriptionLabel.TextScaled = true
	descriptionLabel.TextWrapped = true
	descriptionLabel.Font = Enum.Font.Gotham
	descriptionLabel.Parent = card

	local selectedBadge = Instance.new("TextLabel")
	selectedBadge.Name = "SelectedBadge"
	selectedBadge.AnchorPoint = Vector2.new(1, 0)
	selectedBadge.Position = UDim2.new(1, -10, 0, 10)
	selectedBadge.Size = UDim2.fromOffset(76, 24)
	selectedBadge.BackgroundColor3 = Color3.fromRGB(70, 150, 255)
	selectedBadge.Text = "Selected"
	selectedBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
	selectedBadge.TextScaled = true
	selectedBadge.Font = Enum.Font.GothamBold
	selectedBadge.Visible = false
	selectedBadge.Parent = card

	createCorner(selectedBadge, 8)

	card.MouseEnter:Connect(function()
		if selectedCard ~= card then
			TweenService:Create(
				card,
				TweenInfo.new(0.12),
				{ BackgroundColor3 = Color3.fromRGB(248, 252, 255) }
			):Play()
		end
	end)

	card.MouseLeave:Connect(function()
		if selectedCard ~= card then
			TweenService:Create(
				card,
				TweenInfo.new(0.12),
				{ BackgroundColor3 = Color3.fromRGB(255, 255, 255) }
			):Play()
		end
	end)

	card.MouseButton1Click:Connect(function()
		selectLayout(data.id, card)
	end)

	return card
end

for _, data in ipairs(layoutData) do
	createLayoutCard(data)
end

confirmButton.MouseButton1Click:Connect(function()
	if createRoomRequestInFlight then
		return
	end

	if not selectedLayoutId then
		return
	end

	setCreateRoomRequestInFlight(true)

	createRoomRequestToken += 1
	local thisRequestToken = createRoomRequestToken

	confirmButton.Text = "Creating."
	confirmButton.BackgroundColor3 = Color3.fromRGB(90, 90, 90)

	createRoomRequest:FireServer(selectedLayoutId)

	task.delay(8, function()
		if createRoomRequestInFlight and createRoomRequestToken == thisRequestToken then
			setCreateRoomRequestInFlight(false)

			confirmButton.Text = "Try Again"
			confirmButton.BackgroundColor3 = Color3.fromRGB(190, 70, 70)

			warn("Room creation timed out waiting for server response")
		end
	end)
end)

local function showCreationGui()
	player:SetAttribute("RoomCreationUiOpen", true)

	dimBackground.Visible = true
	mainFrame.Visible = true

	mainFrame.Size = UDim2.fromOffset(680, 390)
	mainFrame.BackgroundTransparency = 0.08

	TweenService:Create(
		mainFrame,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = UDim2.fromOffset(720, 520),
			BackgroundTransparency = 0,
		}
	):Play()
end

local function hideCreationGui()
	mainFrame.Visible = false
	dimBackground.Visible = false

	player:SetAttribute("RoomCreationUiOpen", false)
end

roomCreationResult.OnClientEvent:Connect(function(status, roomName)
	print("Client: RoomCreationResult =", status, roomName)

	createRoomRequestToken += 1
	setCreateRoomRequestInFlight(false)
	
	if status == "ShowCreation" then
		confirmButton.Text = "Select a Room"
		updateConfirmButton()
		showCreationGui()

	elseif status == "Created" then
		hideCreationGui()

	elseif status == "Failed" then
		if selectedCard then
			setCardSelected(selectedCard, false)
		end

		selectedLayoutId = nil
		selectedCard = nil

		confirmButton.Text = "Try Again"
		confirmButton.BackgroundColor3 = Color3.fromRGB(190, 70, 70)

		showCreationGui()
		warn("Room creation failed")
	end
end)

updateConfirmButton()