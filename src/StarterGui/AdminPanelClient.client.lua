-- StarterGui/AdminPanelGui/AdminPanelClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
print("[AdminPanelClient] Started for", player.Name, player.UserId)

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10)

if not remoteEvents then
	warn("[AdminPanelClient] Missing ReplicatedStorage.RemoteEvents")
	return
end

local adminCommandRequest = remoteEvents:WaitForChild("AdminCommandRequest", 10)
local adminCommandResult = remoteEvents:WaitForChild("AdminCommandResult", 10)

if not adminCommandRequest then
	warn("[AdminPanelClient] Missing RemoteEvents.AdminCommandRequest")
	return
end

if not adminCommandResult then
	warn("[AdminPanelClient] Missing RemoteEvents.AdminCommandResult")
	return
end

print("[AdminPanelClient] Loaded admin RemoteEvents")

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 1000

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

local accessGranted = false
local requestInFlight = false

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

local function createLabel(parent, name, text, position, size, textSize)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(45, 45, 45)
	label.TextSize = textSize or 16
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.Gotham
	label.Parent = parent
	return label
end

local function createTextBox(parent, name, placeholder, position, size)
	local box = Instance.new("TextBox")
	box.Name = name
	box.Position = position
	box.Size = size
	box.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	box.BorderSizePixel = 0
	box.PlaceholderText = placeholder
	box.Text = ""
	box.TextColor3 = Color3.fromRGB(40, 40, 40)
	box.PlaceholderColor3 = Color3.fromRGB(140, 140, 140)
	box.TextSize = 16
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Gotham
	box.Parent = parent

	createCorner(box, 8)
	createStroke(box, Color3.fromRGB(210, 210, 210), 1, 0)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = box

	return box
end

local function createButton(parent, name, text, position, size, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextSize = 16
	button.TextWrapped = true
	button.Font = Enum.Font.GothamBold
	button.AutoButtonColor = true
	button.Parent = parent

	createCorner(button, 9)

	return button
end

local openButton = Instance.new("TextButton")
openButton.Name = "OpenAdminButton"
openButton.AnchorPoint = Vector2.new(1, 0)
openButton.Position = UDim2.new(1, -18, 0, 18)
openButton.Size = UDim2.fromOffset(120, 38)
openButton.BackgroundColor3 = Color3.fromRGB(90, 50, 50)
openButton.BorderSizePixel = 0
openButton.Text = "Admin"
openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
openButton.TextSize = 16
openButton.Font = Enum.Font.GothamBold
openButton.Visible = false
openButton.Parent = gui

createCorner(openButton, 10)

local dimBackground = Instance.new("Frame")
dimBackground.Name = "DimBackground"
dimBackground.Size = UDim2.fromScale(1, 1)
dimBackground.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dimBackground.BackgroundTransparency = 0.35
dimBackground.Visible = false
dimBackground.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "AdminPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(620, 540)
panel.BackgroundColor3 = Color3.fromRGB(245, 245, 238)
panel.BorderSizePixel = 0
panel.Parent = dimBackground

createCorner(panel, 16)
createStroke(panel, Color3.fromRGB(255, 255, 255), 2, 0.1)

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.fromOffset(24, 18)
title.Size = UDim2.new(1, -70, 0, 34)
title.BackgroundTransparency = 1
title.Text = "Admin Panel"
title.TextColor3 = Color3.fromRGB(35, 35, 35)
title.TextSize = 24
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.Parent = panel

local closeButton = createButton(
	panel,
	"CloseButton",
	"X",
	UDim2.new(1, -52, 0, 18),
	UDim2.fromOffset(32, 32),
	Color3.fromRGB(150, 70, 70)
)

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Position = UDim2.fromOffset(24, 60)
statusLabel.Size = UDim2.new(1, -48, 0, 46)
statusLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.BorderSizePixel = 0
statusLabel.Text = "Enter a numeric UserId. Dangerous actions require confirmation."
statusLabel.TextColor3 = Color3.fromRGB(70, 70, 70)
statusLabel.TextSize = 15
statusLabel.TextWrapped = true
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Font = Enum.Font.Gotham
statusLabel.Parent = panel

createCorner(statusLabel, 8)
createStroke(statusLabel, Color3.fromRGB(220, 220, 220), 1, 0)

local statusPadding = Instance.new("UIPadding")
statusPadding.PaddingLeft = UDim.new(0, 10)
statusPadding.PaddingRight = UDim.new(0, 10)
statusPadding.Parent = statusLabel

createLabel(
	panel,
	"TargetLabel",
	"Target UserId",
	UDim2.fromOffset(24, 122),
	UDim2.fromOffset(200, 24),
	15
)

local targetBox = createTextBox(
	panel,
	"TargetUserIdBox",
	"Example: 123456789",
	UDim2.fromOffset(24, 148),
	UDim2.new(1, -48, 0, 40)
)

createLabel(
	panel,
	"ReasonLabel",
	"Reason / Private moderation note",
	UDim2.fromOffset(24, 204),
	UDim2.fromOffset(300, 24),
	15
)

local reasonBox = createTextBox(
	panel,
	"ReasonBox",
	"Required for exploit ban",
	UDim2.fromOffset(24, 230),
	UDim2.new(1, -48, 0, 40)
)

createLabel(
	panel,
	"ConfirmLabel",
	"Confirmation word",
	UDim2.fromOffset(24, 286),
	UDim2.fromOffset(300, 24),
	15
)

local confirmBox = createTextBox(
	panel,
	"ConfirmBox",
	"Type RESET, BAN, or UNBAN",
	UDim2.fromOffset(24, 312),
	UDim2.new(1, -48, 0, 40)
)

local lookupButton = createButton(
	panel,
	"LookupButton",
	"Lookup User",
	UDim2.fromOffset(24, 376),
	UDim2.fromOffset(135, 42),
	Color3.fromRGB(70, 120, 190)
)

local resetButton = createButton(
	panel,
	"ResetButton",
	"Reset Profile",
	UDim2.fromOffset(174, 376),
	UDim2.fromOffset(135, 42),
	Color3.fromRGB(210, 140, 60)
)

local banButton = createButton(
	panel,
	"BanButton",
	"Exploit Ban",
	UDim2.fromOffset(324, 376),
	UDim2.fromOffset(135, 42),
	Color3.fromRGB(190, 65, 65)
)

local unbanButton = createButton(
	panel,
	"UnbanButton",
	"Unban",
	UDim2.fromOffset(474, 376),
	UDim2.fromOffset(90, 42),
	Color3.fromRGB(85, 150, 90)
)

local warningLabel = Instance.new("TextLabel")
warningLabel.Name = "WarningLabel"
warningLabel.Position = UDim2.fromOffset(24, 438)
warningLabel.Size = UDim2.new(1, -48, 0, 78)
warningLabel.BackgroundTransparency = 1
warningLabel.TextColor3 = Color3.fromRGB(110, 70, 70)
warningLabel.TextSize = 14
warningLabel.TextWrapped = true
warningLabel.TextXAlignment = Enum.TextXAlignment.Left
warningLabel.Font = Enum.Font.Gotham
warningLabel.Text =
	"Security note: this GUI does not grant permissions. The server re-checks admin rank, target rank, UserId validity, confirmation text, cooldowns, and destructive-action safety."
warningLabel.Parent = panel

local function setPanelVisible(isVisible)
	if not accessGranted then
		dimBackground.Visible = false
		return
	end

	dimBackground.Visible = isVisible
end

local function setStatus(text, success)
	statusLabel.Text = tostring(text or "")

	if success == true then
		statusLabel.TextColor3 = Color3.fromRGB(50, 110, 60)
	elseif success == false then
		statusLabel.TextColor3 = Color3.fromRGB(150, 60, 60)
	else
		statusLabel.TextColor3 = Color3.fromRGB(70, 70, 70)
	end
end

local function getPayload()
	return {
		TargetUserId = targetBox.Text,
		Reason = reasonBox.Text,
		Confirm = confirmBox.Text,
	}
end

local function sendCommand(actionName)
	if not accessGranted then
		setStatus("No admin access.", false)
		return
	end

	if requestInFlight then
		setStatus("A command is already running.", false)
		return
	end

	requestInFlight = true
	setStatus("Sending " .. tostring(actionName) .. "...", nil)

	adminCommandRequest:FireServer(actionName, getPayload())

	task.delay(10, function()
		if requestInFlight then
			requestInFlight = false
			setStatus("Command timed out locally. Check server Output.", false)
		end
	end)
end

openButton.MouseButton1Click:Connect(function()
	setPanelVisible(true)
end)

closeButton.MouseButton1Click:Connect(function()
	setPanelVisible(false)
end)

lookupButton.MouseButton1Click:Connect(function()
	sendCommand("LookupUser")
end)

resetButton.MouseButton1Click:Connect(function()
	if confirmBox.Text ~= "RESET" then
		setStatus("Type RESET in the confirmation box first.", false)
		return
	end

	sendCommand("ResetProfile")
end)

banButton.MouseButton1Click:Connect(function()
	if confirmBox.Text ~= "BAN" then
		setStatus("Type BAN in the confirmation box first.", false)
		return
	end

	if #reasonBox.Text < 5 then
		setStatus("Enter a ban reason first.", false)
		return
	end

	sendCommand("ExploitBan")
end)

unbanButton.MouseButton1Click:Connect(function()
	if confirmBox.Text ~= "UNBAN" then
		setStatus("Type UNBAN in the confirmation box first.", false)
		return
	end

	sendCommand("Unban")
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.F4 and accessGranted then
		setPanelVisible(not dimBackground.Visible)
	end
end)

adminCommandResult.OnClientEvent:Connect(function(response)
	if typeof(response) ~= "table" then
		return
	end

	local kind = response.Kind
	local success = response.Success == true
	local message = tostring(response.Message or "")
	local data = response.Data

	requestInFlight = false

	if kind == "Access" then
		accessGranted = success and typeof(data) == "table" and data.IsAdmin == true
		openButton.Visible = accessGranted

		if not accessGranted then
			setPanelVisible(false)
		end

		return
	end

	if kind == "LookupUser" and success and typeof(data) == "table" then
		local onlineText = data.IsOnline and "Online" or "Offline"
		local protectedText = data.IsProtectedFromYou and "Protected" or "Not protected"

		setStatus(
			"User: "
				.. tostring(data.Username)
				.. " | UserId: "
				.. tostring(data.UserId)
				.. " | "
				.. onlineText
				.. " | AdminRank: "
				.. tostring(data.TargetAdminRank)
				.. " | "
				.. protectedText,
			true
		)

		return
	end

	setStatus(message, success)
end)

task.defer(function()
	adminCommandRequest:FireServer("GetAccess", {})
end)

local function applyAccessFromAttribute()
	if player:GetAttribute("IsAdmin") == true then
		accessGranted = true
		openButton.Visible = true
		print("[AdminPanelClient] Admin access from IsAdmin attribute")
	end
end

player:GetAttributeChangedSignal("IsAdmin"):Connect(applyAccessFromAttribute)
applyAccessFromAttribute()

task.delay(1, function()
	print("[AdminPanelClient] Requesting admin access")
	adminCommandRequest:FireServer("GetAccess", {})
end)