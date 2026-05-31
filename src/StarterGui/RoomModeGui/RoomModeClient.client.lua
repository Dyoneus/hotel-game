--Explorer/StarterGui/RoomModeGui/RoomModeClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local setRoomModeRequest = remoteEvents:WaitForChild("SetRoomModeRequest")
local roomModeResult = remoteEvents:WaitForChild("RoomModeResult")

local activeRooms = workspace:WaitForChild("ActiveRooms")

local requestInFlight = false

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

local toggleRoomMode = getOrCreateClientEvent("ToggleRoomMode")

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

local modeButton = Instance.new("TextButton")
modeButton.Name = "ModeButton"
modeButton.AnchorPoint = Vector2.new(1, 1)
modeButton.Position = UDim2.new(1, -20, 1, -20)
modeButton.Size = UDim2.fromOffset(150, 44)
modeButton.BackgroundColor3 = Color3.fromRGB(35, 45, 60)
modeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
modeButton.TextScaled = true
modeButton.Font = Enum.Font.GothamBold
modeButton.AutoButtonColor = true
modeButton.Visible = false
modeButton.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = modeButton

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 255, 255)
stroke.Thickness = 1
stroke.Transparency = 0.25
stroke.Parent = modeButton

local function getCurrentRoomModel()
	local roomName = player:GetAttribute("CurrentRoomName")

	if not roomName then
		return nil
	end

	return activeRooms:FindFirstChild(roomName)
end

local function isCurrentRoomOwner()
	local roomModel = getCurrentRoomModel()

	if not roomModel then
		return false
	end

	return roomModel:GetAttribute("OwnerUserId") == player.UserId
end

local function updateButton()
	local roomMode = player:GetAttribute("RoomMode") or "Play"
	local onboardingStep = player:GetAttribute("OnboardingStep")
	local controlMode = player:GetAttribute("ControlMode") or "Hotel"

	local shouldShow = isCurrentRoomOwner()
		and player:GetAttribute("CurrentRoomName") ~= nil
		and onboardingStep == "Complete"
		and controlMode == "Hotel"

	modeButton.Visible = false

	if not shouldShow then
		return
	end

	if requestInFlight then
		modeButton.Text = "Changing..."
		modeButton.AutoButtonColor = false
		modeButton.Active = false
		modeButton.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
		return
	end

	modeButton.AutoButtonColor = true
	modeButton.Active = true

	if roomMode == "Edit" then
		modeButton.Text = "Exit Edit"
		modeButton.BackgroundColor3 = Color3.fromRGB(200, 90, 60)
	else
		modeButton.Text = "Edit Room"
		modeButton.BackgroundColor3 = Color3.fromRGB(35, 45, 60)
	end
end

local function requestRoomModeToggle()
	if requestInFlight then
		return
	end

	if not isCurrentRoomOwner()
		or player:GetAttribute("CurrentRoomName") == nil
		or player:GetAttribute("OnboardingStep") ~= "Complete"
		or (player:GetAttribute("ControlMode") or "Hotel") ~= "Hotel" then

		return
	end

	local currentMode = player:GetAttribute("RoomMode") or "Play"
	local requestedMode

	if currentMode == "Edit" then
		requestedMode = "Play"
	else
		requestedMode = "Edit"
	end

	requestInFlight = true
	updateButton()

	setRoomModeRequest:FireServer(requestedMode)

	task.delay(3, function()
		if requestInFlight then
			requestInFlight = false
			updateButton()
		end
	end)
end

modeButton.MouseButton1Click:Connect(requestRoomModeToggle)
toggleRoomMode.Event:Connect(requestRoomModeToggle)

roomModeResult.OnClientEvent:Connect(function(success, result)
	requestInFlight = false

	if not success then
		warn(result)
	end

	updateButton()
end)

player:GetAttributeChangedSignal("CurrentRoomName"):Connect(updateButton)
player:GetAttributeChangedSignal("RoomMode"):Connect(updateButton)
player:GetAttributeChangedSignal("OnboardingStep"):Connect(updateButton)
player:GetAttributeChangedSignal("ControlMode"):Connect(updateButton)

activeRooms.ChildAdded:Connect(function()
	task.defer(updateButton)
end)

activeRooms.ChildRemoved:Connect(function()
	task.defer(updateButton)
end)

task.defer(updateButton)
