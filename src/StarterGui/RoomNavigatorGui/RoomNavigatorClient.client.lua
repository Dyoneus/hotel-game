--Explorer/StarterGui/RoomNavigatorGui/RoomCreationClient.lua
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local roomListRequest = remoteEvents:WaitForChild("RoomListRequest")
local roomListUpdate = remoteEvents:WaitForChild("RoomListUpdate")
local joinRoomRequest = remoteEvents:WaitForChild("JoinRoomRequest")
local joinRoomResult = remoteEvents:WaitForChild("JoinRoomResult")
local roomCreationResult = remoteEvents:WaitForChild("RoomCreationResult")

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

local selectedRoomName = nil
local selectedRow = nil
local latestRoomList = {}

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

local majorMenuOpened = getOrCreateClientEvent("MajorMenuOpened")
local closeMajorMenus = getOrCreateClientEvent("CloseMajorMenus")
local majorMenuStateChanged = getOrCreateClientEvent("MajorMenuStateChanged")

local MENU_NAME = "Rooms"
local anyMajorMenuOpen = false
local openMajorMenuName = nil

local openButton = Instance.new("TextButton")
openButton.Name = "OpenRoomsButton"
openButton.AnchorPoint = Vector2.new(0, 1)
openButton.Position = UDim2.new(0, 18, 1, -18)
openButton.Size = UDim2.fromOffset(130, 42)
openButton.BackgroundColor3 = Color3.fromRGB(35, 45, 60)
openButton.Text = "Rooms"
openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
openButton.TextScaled = true
openButton.Font = Enum.Font.GothamBold
openButton.Visible = false
openButton.Parent = gui

createCorner(openButton, 10)

local panel = Instance.new("Frame")
panel.Name = "RoomNavigatorPanel"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -24, 0.5, 0)
panel.Size = UDim2.fromOffset(380, 520)
panel.BackgroundColor3 = Color3.fromRGB(245, 245, 238)
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

createCorner(panel, 16)
createStroke(panel, Color3.fromRGB(255, 255, 255), 2, 0.1)

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Position = UDim2.fromOffset(18, 14)
titleLabel.Size = UDim2.new(1, -36, 0, 36)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Rooms in This Server"
titleLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
titleLabel.TextScaled = true
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Parent = panel

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Position = UDim2.fromOffset(18, 52)
statusLabel.Size = UDim2.new(1, -36, 0, 24)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Select a room to join."
statusLabel.TextColor3 = Color3.fromRGB(95, 95, 95)
statusLabel.TextScaled = true
statusLabel.Font = Enum.Font.Gotham
statusLabel.Parent = panel

local listFrame = Instance.new("ScrollingFrame")
listFrame.Name = "RoomList"
listFrame.Position = UDim2.fromOffset(18, 88)
listFrame.Size = UDim2.new(1, -36, 1, -170)
listFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 6
listFrame.CanvasSize = UDim2.fromOffset(0, 0)
listFrame.Parent = panel

createCorner(listFrame, 12)
createStroke(listFrame, Color3.fromRGB(220, 220, 220), 1, 0)

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = listFrame

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 10)
listPadding.PaddingBottom = UDim.new(0, 10)
listPadding.PaddingLeft = UDim.new(0, 10)
listPadding.PaddingRight = UDim.new(0, 10)
listPadding.Parent = listFrame

local joinButton = Instance.new("TextButton")
joinButton.Name = "JoinButton"
joinButton.AnchorPoint = Vector2.new(0.5, 1)
joinButton.Position = UDim2.new(0.5, 0, 1, -64)
joinButton.Size = UDim2.fromOffset(250, 42)
joinButton.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
joinButton.Text = "Select a Room"
joinButton.TextColor3 = Color3.fromRGB(255, 255, 255)
joinButton.TextScaled = true
joinButton.Font = Enum.Font.GothamBold
joinButton.AutoButtonColor = false
joinButton.Parent = panel

createCorner(joinButton, 10)

local refreshButton = Instance.new("TextButton")
refreshButton.Name = "RefreshButton"
refreshButton.Position = UDim2.new(0, 18, 1, -48)
refreshButton.Size = UDim2.fromOffset(100, 32)
refreshButton.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
refreshButton.Text = "Refresh"
refreshButton.TextColor3 = Color3.fromRGB(45, 45, 45)
refreshButton.TextScaled = true
refreshButton.Font = Enum.Font.GothamBold
refreshButton.Parent = panel

createCorner(refreshButton, 8)

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -18, 1, -48)
closeButton.Size = UDim2.fromOffset(100, 32)
closeButton.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
closeButton.Text = "Close"
closeButton.TextColor3 = Color3.fromRGB(45, 45, 45)
closeButton.TextScaled = true
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = panel

createCorner(closeButton, 8)

local function shouldShowRoomsButton()
	return player:GetAttribute("OnboardingStep") == "Complete"
end

local function updateOpenButton()
	openButton.Visible = (not panel.Visible)
		and not anyMajorMenuOpen
		and shouldShowRoomsButton()
end

local function setLocalMajorMenuState(isOpen, menuName)
	if isOpen then
		anyMajorMenuOpen = true
		openMajorMenuName = menuName
	elseif openMajorMenuName == menuName then
		anyMajorMenuOpen = false
		openMajorMenuName = nil
	end

	updateOpenButton()
end

local function publishMajorMenuState(isOpen)
	setLocalMajorMenuState(isOpen, MENU_NAME)
	majorMenuStateChanged:Fire(isOpen, MENU_NAME)
end

local function setPanelVisible(isVisible)
	local wasVisible = panel.Visible

	if isVisible then
		publishMajorMenuState(true)
		majorMenuOpened:Fire(MENU_NAME)
	end

	panel.Visible = isVisible
	updateOpenButton()

	if not isVisible and (wasVisible or openMajorMenuName == MENU_NAME) then
		publishMajorMenuState(false)
	end
end

local function updateJoinButton()
	if selectedRoomName then
		joinButton.Text = "Join Room"
		joinButton.BackgroundColor3 = Color3.fromRGB(70, 150, 255)
	else
		joinButton.Text = "Select a Room"
		joinButton.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
	end
end

local function setRowSelected(row, isSelected)
	local stroke = row:FindFirstChild("RowStroke")

	if stroke then
		if isSelected then
			stroke.Color = Color3.fromRGB(70, 150, 255)
			stroke.Thickness = 3
		else
			stroke.Color = Color3.fromRGB(220, 220, 220)
			stroke.Thickness = 1
		end
	end

	if isSelected then
		row.BackgroundColor3 = Color3.fromRGB(235, 245, 255)
	else
		row.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
	end
end

local function clearRows()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function createRoomRow(roomData, currentRoomName, order)
	local row = Instance.new("TextButton")
	row.Name = roomData.RoomName
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -4, 0, 74)
	row.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
	row.Text = ""
	row.AutoButtonColor = false
	row.Parent = listFrame

	createCorner(row, 10)

	local stroke = createStroke(row, Color3.fromRGB(220, 220, 220), 1, 0)
	stroke.Name = "RowStroke"

	local ownerLabel = Instance.new("TextLabel")
	ownerLabel.Name = "OwnerLabel"
	ownerLabel.Position = UDim2.fromOffset(12, 8)
	ownerLabel.Size = UDim2.new(1, -24, 0, 24)
	ownerLabel.BackgroundTransparency = 1
	ownerLabel.TextXAlignment = Enum.TextXAlignment.Left
	ownerLabel.Text = roomData.OwnerDisplayName .. "'s Room"
	ownerLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
	ownerLabel.TextScaled = true
	ownerLabel.Font = Enum.Font.GothamBold
	ownerLabel.Parent = row

	local infoLabel = Instance.new("TextLabel")
	infoLabel.Name = "InfoLabel"
	infoLabel.Position = UDim2.fromOffset(12, 36)
	infoLabel.Size = UDim2.new(1, -24, 0, 22)
	infoLabel.BackgroundTransparency = 1
	infoLabel.TextXAlignment = Enum.TextXAlignment.Left
	infoLabel.TextColor3 = Color3.fromRGB(95, 95, 95)
	infoLabel.TextScaled = true
	infoLabel.Font = Enum.Font.Gotham
	infoLabel.Text = roomData.LayoutId .. "  •  " .. tostring(roomData.PlayerCount) .. " player(s)"
	infoLabel.Parent = row

	if roomData.RoomName == currentRoomName then
		local hereBadge = Instance.new("TextLabel")
		hereBadge.Name = "HereBadge"
		hereBadge.AnchorPoint = Vector2.new(1, 0)
		hereBadge.Position = UDim2.new(1, -10, 0, 10)
		hereBadge.Size = UDim2.fromOffset(60, 22)
		hereBadge.BackgroundColor3 = Color3.fromRGB(70, 150, 255)
		hereBadge.Text = "Here"
		hereBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
		hereBadge.TextScaled = true
		hereBadge.Font = Enum.Font.GothamBold
		hereBadge.Parent = row

		createCorner(hereBadge, 8)
	end

	row.MouseButton1Click:Connect(function()
		if selectedRow then
			setRowSelected(selectedRow, false)
		end

		selectedRoomName = roomData.RoomName
		selectedRow = row

		setRowSelected(row, true)
		updateJoinButton()
	end)

	return row
end

local function renderRoomList(roomList, currentRoomName)
	latestRoomList = roomList
	selectedRoomName = nil
	selectedRow = nil

	clearRows()

	if #roomList == 0 then
		statusLabel.Text = "No rooms are available yet."
	else
		statusLabel.Text = "Select a room to join."
	end

	for index, roomData in ipairs(roomList) do
		createRoomRow(roomData, currentRoomName, index)
	end

	task.defer(function()
		listFrame.CanvasSize = UDim2.fromOffset(
			0,
			listLayout.AbsoluteContentSize.Y + 20
		)
	end)

	updateJoinButton()
end

openButton.MouseButton1Click:Connect(function()
	setPanelVisible(true)
	roomListRequest:FireServer()
end)

closeButton.MouseButton1Click:Connect(function()
	setPanelVisible(false)
end)

majorMenuOpened.Event:Connect(function(menuName)
	if menuName ~= MENU_NAME and panel.Visible then
		setPanelVisible(false)
	end
end)

closeMajorMenus.Event:Connect(function()
	if panel.Visible then
		setPanelVisible(false)
	end
end)

majorMenuStateChanged.Event:Connect(function(isOpen, menuName)
	setLocalMajorMenuState(isOpen == true, menuName)
end)

refreshButton.MouseButton1Click:Connect(function()
	roomListRequest:FireServer()
end)

joinButton.MouseButton1Click:Connect(function()
	if not selectedRoomName then
		return
	end

	joinButton.Text = "Joining..."
	joinButton.BackgroundColor3 = Color3.fromRGB(90, 90, 90)

	joinRoomRequest:FireServer(selectedRoomName)
end)

roomListUpdate.OnClientEvent:Connect(function(roomList, currentRoomName)
	renderRoomList(roomList, currentRoomName)

	-- Only show the Rooms button when the player should have access to navigator.
	-- For now, hide it during onboarding/tutorial flow.
	updateOpenButton()
end)

joinRoomResult.OnClientEvent:Connect(function(success, message, roomName)
	if success then
		statusLabel.Text = message or "Joined room."
		setPanelVisible(false)
	else
		statusLabel.Text = message or "Could not join room."
	end

	updateJoinButton()
	roomListRequest:FireServer()
end)

roomCreationResult.OnClientEvent:Connect(function(status)
	if status == "Created" then
		-- New player just finished onboarding.
		-- Do NOT open the room navigator.
		setPanelVisible(false)
		openButton.Visible = false

	elseif status == "ShowCharacterCreation" then
		-- New player is in character creation.
		setPanelVisible(false)
		openButton.Visible = false

	elseif status == "ShowCreation" then
		-- New player is choosing a starter room.
		setPanelVisible(false)
		openButton.Visible = false
	end
end)

player:GetAttributeChangedSignal("OnboardingStep"):Connect(function()
	if panel.Visible and not shouldShowRoomsButton() then
		setPanelVisible(false)
	else
		updateOpenButton()
	end
end)
