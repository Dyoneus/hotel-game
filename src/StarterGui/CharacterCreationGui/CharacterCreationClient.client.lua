--Explorer/StarterGui/CharacterCreationGui/CharacterCreationClient.lua
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

print("CharacterCreationClient started")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local roomCreationResult = remoteEvents:WaitForChild("RoomCreationResult")
local characterCreationFinished = remoteEvents:WaitForChild("CharacterCreationFinished")

print("CharacterCreationClient loaded RemoteEvents")

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

local isSubmitting = false

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

local dimBackground = Instance.new("Frame")
dimBackground.Name = "DimBackground"
dimBackground.Size = UDim2.fromScale(1, 1)
dimBackground.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dimBackground.BackgroundTransparency = 0.35
dimBackground.Visible = false
dimBackground.Parent = gui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.Position = UDim2.fromScale(0.5, 0.5)
mainFrame.Size = UDim2.fromOffset(560, 420)
mainFrame.BackgroundColor3 = Color3.fromRGB(245, 245, 238)
mainFrame.BorderSizePixel = 0
mainFrame.Visible = false
mainFrame.Parent = dimBackground

createCorner(mainFrame, 18)
createStroke(mainFrame, Color3.fromRGB(255, 255, 255), 2, 0.1)

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Position = UDim2.fromOffset(28, 24)
titleLabel.Size = UDim2.new(1, -56, 0, 42)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Create Your Character"
titleLabel.TextColor3 = Color3.fromRGB(45, 45, 45)
titleLabel.TextScaled = true
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Parent = mainFrame

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Name = "SubtitleLabel"
subtitleLabel.Position = UDim2.fromOffset(36, 72)
subtitleLabel.Size = UDim2.new(1, -72, 0, 48)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Text = "Character customization will be added later. For now, we’ll create a default character profile."
subtitleLabel.TextColor3 = Color3.fromRGB(95, 95, 95)
subtitleLabel.TextScaled = true
subtitleLabel.TextWrapped = true
subtitleLabel.Font = Enum.Font.Gotham
subtitleLabel.Parent = mainFrame

local avatarPreview = Instance.new("Frame")
avatarPreview.Name = "AvatarPreview"
avatarPreview.AnchorPoint = Vector2.new(0.5, 0)
avatarPreview.Position = UDim2.new(0.5, 0, 0, 145)
avatarPreview.Size = UDim2.fromOffset(170, 170)
avatarPreview.BackgroundColor3 = Color3.fromRGB(230, 235, 240)
avatarPreview.BorderSizePixel = 0
avatarPreview.Parent = mainFrame

createCorner(avatarPreview, 16)
createStroke(avatarPreview, Color3.fromRGB(210, 210, 210), 2, 0)

local avatarIcon = Instance.new("TextLabel")
avatarIcon.Name = "AvatarIcon"
avatarIcon.Size = UDim2.fromScale(1, 1)
avatarIcon.BackgroundTransparency = 1
avatarIcon.Text = "☺"
avatarIcon.TextColor3 = Color3.fromRGB(70, 80, 95)
avatarIcon.TextScaled = true
avatarIcon.Font = Enum.Font.GothamBold
avatarIcon.Parent = avatarPreview

local noteLabel = Instance.new("TextLabel")
noteLabel.Name = "NoteLabel"
noteLabel.AnchorPoint = Vector2.new(0.5, 0)
noteLabel.Position = UDim2.new(0.5, 0, 0, 325)
noteLabel.Size = UDim2.fromOffset(460, 32)
noteLabel.BackgroundTransparency = 1
noteLabel.Text = "Next: choose your starter room layout."
noteLabel.TextColor3 = Color3.fromRGB(105, 105, 105)
noteLabel.TextScaled = true
noteLabel.Font = Enum.Font.Gotham
noteLabel.Parent = mainFrame

local continueButton = Instance.new("TextButton")
continueButton.Name = "ContinueButton"
continueButton.AnchorPoint = Vector2.new(0.5, 1)
continueButton.Position = UDim2.new(0.5, 0, 1, -28)
continueButton.Size = UDim2.fromOffset(240, 46)
continueButton.BackgroundColor3 = Color3.fromRGB(70, 150, 255)
continueButton.Text = "Continue"
continueButton.TextColor3 = Color3.fromRGB(255, 255, 255)
continueButton.TextScaled = true
continueButton.Font = Enum.Font.GothamBold
continueButton.AutoButtonColor = false
continueButton.Parent = mainFrame

createCorner(continueButton, 12)

local function showGui()
	isSubmitting = false
	continueButton.Text = "Continue"
	continueButton.BackgroundColor3 = Color3.fromRGB(70, 150, 255)

	dimBackground.Visible = true
	mainFrame.Visible = true

	mainFrame.Size = UDim2.fromOffset(520, 390)

	TweenService:Create(
		mainFrame,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(560, 420) }
	):Play()
end

local function hideGui()
	mainFrame.Visible = false
	dimBackground.Visible = false
end

continueButton.MouseButton1Click:Connect(function()
	if isSubmitting then
		return
	end

	isSubmitting = true
	continueButton.Text = "Loading..."
	continueButton.BackgroundColor3 = Color3.fromRGB(90, 90, 90)

	characterCreationFinished:FireServer({
		BodyType = "Default",
	})
end)

roomCreationResult.OnClientEvent:Connect(function(status)
	if status == "ShowCharacterCreation" then
		showGui()

	elseif status == "ShowCreation" then
		hideGui()

	elseif status == "Created" then
		hideGui()
	end
end)

local function refreshFromOnboardingStep()
	local step = player:GetAttribute("OnboardingStep")

	if step == "CharacterCreation" then
		showGui()
	else
		hideGui()
	end
end

player:GetAttributeChangedSignal("OnboardingStep"):Connect(refreshFromOnboardingStep)

task.defer(refreshFromOnboardingStep)