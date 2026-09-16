--Explorer/StarterGui/TutorialGui/TutorialClient.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

print("TutorialClient started")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local tutorialFinishedRequest = remoteEvents:WaitForChild("TutorialFinishedRequest")
local roomCreationResult = remoteEvents:WaitForChild("RoomCreationResult")

print("TutorialClient loaded RemoteEvents")

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

gui.DisplayOrder = 100

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

local tutorialSteps = {
	{
		title = "Welcome Home",
		body = "This is your first room. You can decorate it, invite others, and interact with furniture.",
	},
	{
		title = "Move Around",
		body = "Click the floor to move. Your character moves on a grid, like an isometric room game.",
	},
	{
		title = "Use Furniture",
		body = "Click a chair to sit. Later, beds, treadmills, doors, and other furniture will have their own actions.",
	},
	{
		title = "Edit Your Room",
		body = "Room editing is owner-only. Later, use Edit Mode to move, rotate, and place furniture.",
	},
}

local currentStep = 1
local tutorialShowRequestId = 0

local function createCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local dimBackground = Instance.new("Frame")
dimBackground.Name = "DimBackground"
dimBackground.Size = UDim2.fromScale(1, 1)
dimBackground.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dimBackground.BackgroundTransparency = 0.4
dimBackground.Visible = false
dimBackground.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "TutorialPanel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -40)
panel.Size = UDim2.fromOffset(560, 210)
panel.BackgroundColor3 = Color3.fromRGB(245, 245, 238)
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = dimBackground

createCorner(panel, 16)

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Position = UDim2.fromOffset(24, 18)
titleLabel.Size = UDim2.new(1, -48, 0, 36)
titleLabel.BackgroundTransparency = 1
titleLabel.TextColor3 = Color3.fromRGB(45, 45, 45)
titleLabel.TextScaled = true
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Parent = panel

local bodyLabel = Instance.new("TextLabel")
bodyLabel.Name = "BodyLabel"
bodyLabel.Position = UDim2.fromOffset(28, 62)
bodyLabel.Size = UDim2.new(1, -56, 0, 74)
bodyLabel.BackgroundTransparency = 1
bodyLabel.TextColor3 = Color3.fromRGB(85, 85, 85)
bodyLabel.TextScaled = true
bodyLabel.TextWrapped = true
bodyLabel.Font = Enum.Font.Gotham
bodyLabel.Parent = panel

local stepLabel = Instance.new("TextLabel")
stepLabel.Name = "StepLabel"
stepLabel.Position = UDim2.fromOffset(28, 145)
stepLabel.Size = UDim2.fromOffset(160, 30)
stepLabel.BackgroundTransparency = 1
stepLabel.TextColor3 = Color3.fromRGB(110, 110, 110)
stepLabel.TextScaled = true
stepLabel.Font = Enum.Font.Gotham
stepLabel.Parent = panel

local nextButton = Instance.new("TextButton")
nextButton.Name = "NextButton"
nextButton.AnchorPoint = Vector2.new(1, 1)
nextButton.Position = UDim2.new(1, -24, 1, -24)
nextButton.Size = UDim2.fromOffset(160, 42)
nextButton.BackgroundColor3 = Color3.fromRGB(70, 150, 255)
nextButton.TextColor3 = Color3.fromRGB(255, 255, 255)
nextButton.TextScaled = true
nextButton.Font = Enum.Font.GothamBold
nextButton.AutoButtonColor = true
nextButton.Parent = panel

createCorner(nextButton, 10)

local skipButton = Instance.new("TextButton")
skipButton.Name = "SkipButton"
skipButton.AnchorPoint = Vector2.new(1, 1)
skipButton.Position = UDim2.new(1, -196, 1, -24)
skipButton.Size = UDim2.fromOffset(110, 42)
skipButton.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
skipButton.Text = "Skip"
skipButton.TextColor3 = Color3.fromRGB(45, 45, 45)
skipButton.TextScaled = true
skipButton.Font = Enum.Font.GothamBold
skipButton.AutoButtonColor = true
skipButton.Parent = panel

createCorner(skipButton, 10)

local function updateTutorialText()
	local step = tutorialSteps[currentStep]

	titleLabel.Text = step.title
	bodyLabel.Text = step.body
	stepLabel.Text = "Step " .. tostring(currentStep) .. " of " .. tostring(#tutorialSteps)

	if currentStep >= #tutorialSteps then
		nextButton.Text = "Finish"
	else
		nextButton.Text = "Next"
	end
end

local function showTutorial()
	currentStep = 1
	updateTutorialText()

	dimBackground.Visible = true
	panel.Visible = true
end

local function hideTutorial()
	panel.Visible = false
	dimBackground.Visible = false
end

local function finishTutorial()
	hideTutorial()
	tutorialFinishedRequest:FireServer()
end

nextButton.MouseButton1Click:Connect(function()
	if currentStep >= #tutorialSteps then
		finishTutorial()
		return
	end

	currentStep += 1
	updateTutorialText()
end)

skipButton.MouseButton1Click:Connect(function()
	finishTutorial()
end)

local function queueTutorialShowWhenRoomCreationClosed()
	tutorialShowRequestId += 1
	local thisRequestId = tutorialShowRequestId

	task.spawn(function()
		while tutorialShowRequestId == thisRequestId
			and player:GetAttribute("OnboardingStep") == "Tutorial"
			and player:GetAttribute("RoomCreationUiOpen") == true do

			task.wait(0.05)
		end

		task.wait(0.15)

		if tutorialShowRequestId ~= thisRequestId then
			return
		end

		if player:GetAttribute("OnboardingStep") ~= "Tutorial" then
			return
		end

		if player:GetAttribute("RoomCreationUiOpen") == true then
			return
		end

		showTutorial()
	end)
end

local function refreshFromOnboardingStep()
	local step = player:GetAttribute("OnboardingStep")

	if step == "Tutorial" then
		queueTutorialShowWhenRoomCreationClosed()
	else
		tutorialShowRequestId += 1
		hideTutorial()
	end
end

player:GetAttributeChangedSignal("OnboardingStep"):Connect(refreshFromOnboardingStep)

player:GetAttributeChangedSignal("RoomCreationUiOpen"):Connect(refreshFromOnboardingStep)

roomCreationResult.OnClientEvent:Connect(function(status)
	if status == "Created" then
		queueTutorialShowWhenRoomCreationClosed()
	end
end)

task.defer(refreshFromOnboardingStep)

