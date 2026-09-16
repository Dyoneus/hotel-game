local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local MAX_LOADING_TIME = 10
local CORE_WAIT_TIME = 8
local STATE_WAIT_TIME = 8
local FADE_OUT_TIME = 0.45

local player = Players.LocalPlayer

while not player do
	task.wait()
	player = Players.LocalPlayer
end

local playerGui = player:WaitForChild("PlayerGui", CORE_WAIT_TIME)

local loadingGui = nil
local background = nil
local titleLabel = nil
local statusLabel = nil
local progressLabel = nil

local function setStatus(statusText, progressText)
	if statusLabel then
		statusLabel.Text = statusText or ""
	end

	if progressLabel then
		progressLabel.Text = progressText or ""
	end
end

local function createLoadingGui()
	if not playerGui then
		return
	end

	loadingGui = Instance.new("ScreenGui")
	loadingGui.Name = "HotelLoadingGui"
	loadingGui.IgnoreGuiInset = true
	loadingGui.ResetOnSpawn = false
	loadingGui.DisplayOrder = 100000
	loadingGui.Parent = playerGui

	background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.new(0, 0, 0)
	background.BackgroundTransparency = 0
	background.BorderSizePixel = 0
	background.Parent = loadingGui

	local centerFrame = Instance.new("Frame")
	centerFrame.Name = "Center"
	centerFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	centerFrame.Position = UDim2.fromScale(0.5, 0.5)
	centerFrame.Size = UDim2.fromOffset(420, 150)
	centerFrame.BackgroundTransparency = 1
	centerFrame.Parent = background

	titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0, 40)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Loading Hotel..."
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextSize = 28
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = centerFrame

	statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Position = UDim2.fromOffset(0, 52)
	statusLabel.Size = UDim2.new(1, 0, 0, 26)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Preparing your room..."
	statusLabel.TextColor3 = Color3.fromRGB(210, 215, 220)
	statusLabel.TextSize = 16
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.Parent = centerFrame

	progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "Progress"
	progressLabel.Position = UDim2.fromOffset(0, 84)
	progressLabel.Size = UDim2.new(1, 0, 0, 22)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Text = ""
	progressLabel.TextColor3 = Color3.fromRGB(150, 160, 170)
	progressLabel.TextSize = 13
	progressLabel.Font = Enum.Font.GothamMedium
	progressLabel.Parent = centerFrame
end

createLoadingGui()
pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local function waitForChildTimeout(parent, childName, timeoutSeconds)
	if not parent then
		return nil
	end

	local child = parent:FindFirstChild(childName)
	local deadline = os.clock() + timeoutSeconds

	while not child and os.clock() < deadline do
		task.wait(0.05)
		child = parent:FindFirstChild(childName)
	end

	return child
end

local function addTarget(targets, instance)
	if instance then
		table.insert(targets, instance)
	end
end

local function collectPreloadTargets()
	local targets = {}

	addTarget(targets, ReplicatedStorage:FindFirstChild("RoomTemplates"))
	addTarget(targets, ReplicatedStorage:FindFirstChild("FurnitureTemplates"))
	addTarget(targets, ReplicatedStorage:FindFirstChild("Shared"))

	for _, descendant in ipairs(ReplicatedStorage:GetDescendants()) do
		if descendant:IsA("ImageLabel")
			or descendant:IsA("ImageButton")
			or descendant:IsA("Decal")
			or descendant:IsA("Texture")
			or descendant:IsA("Sound")
			or descendant:IsA("MeshPart")
			or descendant:IsA("SpecialMesh") then

			addTarget(targets, descendant)
		end
	end

	for _, descendant in ipairs(StarterGui:GetDescendants()) do
		if descendant:IsA("ImageLabel")
			or descendant:IsA("ImageButton")
			or descendant:IsA("Decal")
			or descendant:IsA("Texture")
			or descendant:IsA("Sound") then

			addTarget(targets, descendant)
		end
	end

	return targets
end

local function preloadCriticalAssets()
	setStatus("Loading assets...", "0%")

	local preloadDone = false
	local preloadOk = true
	local preloadStart = os.clock()

	task.spawn(function()
		local targets = collectPreloadTargets()

		local ok, err = pcall(function()
			if #targets > 0 then
				ContentProvider:PreloadAsync(targets)
			end
		end)

		if not ok then
			preloadOk = false
			warn("LoadingClient: asset preload skipped after error:", err)
		end

		preloadDone = true
	end)

	while not preloadDone and os.clock() - preloadStart < MAX_LOADING_TIME do
		local alpha = math.clamp((os.clock() - preloadStart) / MAX_LOADING_TIME, 0, 1)
		setStatus("Loading assets...", tostring(math.floor(alpha * 100)) .. "%")
		task.wait(0.1)
	end

	if not preloadDone then
		warn("LoadingClient: asset preload timed out; continuing.")
	elseif not preloadOk then
		setStatus("Preparing your room...", "")
	end
end

local function waitForCoreObjects()
	setStatus("Connecting to hotel services...", "")

	waitForChildTimeout(ReplicatedStorage, "RemoteEvents", CORE_WAIT_TIME)
	waitForChildTimeout(Workspace, "ActiveRooms", CORE_WAIT_TIME)
end

local function waitForInitialClientState()
	setStatus("Preparing your room...", "")

	local deadline = os.clock() + STATE_WAIT_TIME

	while os.clock() < deadline do
		local currentRoomName = player:GetAttribute("CurrentRoomName")

		if typeof(currentRoomName) == "string" and currentRoomName ~= "" then
			return
		end

		if player:GetAttribute("OnboardingStep") ~= nil
			or player:GetAttribute("RoomCreationUiOpen") ~= nil
			or player:GetAttribute("CharacterCreationUiOpen") ~= nil then

			return
		end

		task.wait(0.1)
	end

	warn("LoadingClient: initial state wait timed out; continuing.")
end

local function fadeOutAndDestroy()
	if not loadingGui or not background then
		return
	end

	setStatus("Ready.", "")

	local tween = TweenService:Create(
		background,
		TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			BackgroundTransparency = 1,
		}
	)

	for _, descendant in ipairs(background:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			TweenService:Create(
				descendant,
				TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{
					TextTransparency = 1,
				}
			):Play()
		end
	end

	tween:Play()
	tween.Completed:Wait()

	if loadingGui then
		loadingGui:Destroy()
	end
end

preloadCriticalAssets()
waitForCoreObjects()
waitForInitialClientState()
fadeOutAndDestroy()
