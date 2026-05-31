-- StarterGui/MainHudGui/MainHudClient.lua
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local activeRooms = workspace:WaitForChild("ActiveRooms")

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 110

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

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

local closeMajorMenus = getOrCreateClientEvent("CloseMajorMenus")
local majorMenuOpened = getOrCreateClientEvent("MajorMenuOpened")
local openRoomNavigator = getOrCreateClientEvent("OpenRoomNavigator")
local openInventory = getOrCreateClientEvent("OpenInventory")
local openCatalog = getOrCreateClientEvent("OpenCatalog")
local toggleRoomMode = getOrCreateClientEvent("ToggleRoomMode")

local hud = {}
local menuExpanded = false
local ACTION_BUTTON_WIDTH = 82
local ACTION_BUTTON_HEIGHT = 42
local ACTION_BUTTON_GAP = 8
local ACTION_BUTTON_RIGHT_MARGIN = 12

hud.RoomDetails = Instance.new("Frame")
hud.RoomDetails.Name = "RoomDetails"
hud.RoomDetails.AnchorPoint = Vector2.new(0, 1)
hud.RoomDetails.Position = UDim2.new(0, 0, 0, -8)
hud.RoomDetails.Size = UDim2.fromOffset(312, 48)
hud.RoomDetails.BackgroundColor3 = Color3.fromRGB(31, 37, 44)
hud.RoomDetails.BackgroundTransparency = 0.08
hud.RoomDetails.BorderSizePixel = 0
hud.RoomDetails.Visible = false
hud.RoomDetails.Parent = gui

createCorner(hud.RoomDetails, 8)
createStroke(hud.RoomDetails, Color3.fromRGB(255, 255, 255), 1, 0.72)

hud.RoomTitle = Instance.new("TextLabel")
hud.RoomTitle.Name = "RoomTitle"
hud.RoomTitle.Position = UDim2.fromOffset(14, 6)
hud.RoomTitle.Size = UDim2.new(1, -28, 0, 20)
hud.RoomTitle.BackgroundTransparency = 1
hud.RoomTitle.Text = "Room"
hud.RoomTitle.TextColor3 = Color3.fromRGB(255, 245, 215)
hud.RoomTitle.TextSize = 16
hud.RoomTitle.TextXAlignment = Enum.TextXAlignment.Left
hud.RoomTitle.TextTruncate = Enum.TextTruncate.AtEnd
hud.RoomTitle.Font = Enum.Font.GothamBold
hud.RoomTitle.Parent = hud.RoomDetails

hud.RoomOwner = Instance.new("TextLabel")
hud.RoomOwner.Name = "RoomOwner"
hud.RoomOwner.Position = UDim2.fromOffset(14, 26)
hud.RoomOwner.Size = UDim2.new(1, -28, 0, 16)
hud.RoomOwner.BackgroundTransparency = 1
hud.RoomOwner.Text = "Owner"
hud.RoomOwner.TextColor3 = Color3.fromRGB(205, 214, 222)
hud.RoomOwner.TextSize = 12
hud.RoomOwner.TextXAlignment = Enum.TextXAlignment.Left
hud.RoomOwner.TextTruncate = Enum.TextTruncate.AtEnd
hud.RoomOwner.Font = Enum.Font.Gotham
hud.RoomOwner.Parent = hud.RoomDetails

hud.Bar = Instance.new("Frame")
hud.Bar.Name = "MainHudBottomBar"
hud.Bar.AnchorPoint = Vector2.new(0.5, 1)
hud.Bar.Position = UDim2.new(0.5, 0, 1, -10)
hud.Bar.Size = UDim2.new(1, -34, 0, 66)
hud.Bar.BackgroundColor3 = Color3.fromRGB(24, 30, 36)
hud.Bar.BackgroundTransparency = 0.04
hud.Bar.BorderSizePixel = 0
hud.Bar.Visible = false
hud.Bar.Parent = gui
hud.RoomDetails.Parent = hud.Bar

createCorner(hud.Bar, 10)
createStroke(hud.Bar, Color3.fromRGB(255, 255, 255), 1, 0.76)

local barSizeConstraint = Instance.new("UISizeConstraint")
barSizeConstraint.MinSize = Vector2.new(720, 66)
barSizeConstraint.MaxSize = Vector2.new(1220, 66)
barSizeConstraint.Parent = hud.Bar

local function createHudButton(name, text, xOffset, width)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0, 0.5)
	button.Position = UDim2.new(0, xOffset, 0.5, 0)
	button.Size = UDim2.fromOffset(width, 42)
	button.BackgroundColor3 = Color3.fromRGB(52, 65, 78)
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = Color3.fromRGB(245, 248, 250)
	button.TextSize = 15
	button.Font = Enum.Font.GothamBold
	button.Parent = hud.Bar

	createCorner(button, 8)
	createStroke(button, Color3.fromRGB(255, 255, 255), 1, 0.78)

	return button
end

hud.MenuButton = createHudButton("MenuButton", "Menu", 12, 82)

hud.MenuList = Instance.new("Frame")
hud.MenuList.Name = "MenuList"
hud.MenuList.AnchorPoint = Vector2.new(0, 1)
hud.MenuList.Position = UDim2.new(0, 12, 0, -8)
hud.MenuList.Size = UDim2.fromOffset(156, 116)
hud.MenuList.BackgroundColor3 = Color3.fromRGB(34, 42, 50)
hud.MenuList.BackgroundTransparency = 0.02
hud.MenuList.BorderSizePixel = 0
hud.MenuList.Visible = false
hud.MenuList.ZIndex = 20
hud.MenuList.Parent = hud.Bar

createCorner(hud.MenuList, 9)
createStroke(hud.MenuList, Color3.fromRGB(255, 255, 255), 1, 0.7)

hud.MenuListLayout = Instance.new("UIListLayout")
hud.MenuListLayout.SortOrder = Enum.SortOrder.LayoutOrder
hud.MenuListLayout.Padding = UDim.new(0, 6)
hud.MenuListLayout.Parent = hud.MenuList

hud.MenuListPadding = Instance.new("UIPadding")
hud.MenuListPadding.PaddingTop = UDim.new(0, 8)
hud.MenuListPadding.PaddingBottom = UDim.new(0, 8)
hud.MenuListPadding.PaddingLeft = UDim.new(0, 8)
hud.MenuListPadding.PaddingRight = UDim.new(0, 8)
hud.MenuListPadding.Parent = hud.MenuList

local function createMenuEntry(name, text, layoutOrder)
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = layoutOrder
	button.Size = UDim2.new(1, 0, 0, 28)
	button.BackgroundColor3 = Color3.fromRGB(58, 70, 82)
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = Color3.fromRGB(245, 248, 250)
	button.TextSize = 13
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.Font = Enum.Font.GothamBold
	button.ZIndex = 21
	button.Parent = hud.MenuList

	createCorner(button, 7)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.Parent = button

	return button
end

hud.MenuRoomsButton = createMenuEntry("MenuRoomsButton", "Rooms", 1)
hud.MenuInventoryButton = createMenuEntry("MenuInventoryButton", "Inventory", 2)
hud.MenuCatalogButton = createMenuEntry("MenuCatalogButton", "Catalog", 3)

hud.ChatFrame = Instance.new("Frame")
hud.ChatFrame.Name = "ChatPlaceholder"
hud.ChatFrame.Position = UDim2.new(0, 106, 0.5, -21)
hud.ChatFrame.Size = UDim2.new(1, -392, 0, 42)
hud.ChatFrame.BackgroundColor3 = Color3.fromRGB(245, 248, 250)
hud.ChatFrame.BorderSizePixel = 0
hud.ChatFrame.Parent = hud.Bar

createCorner(hud.ChatFrame, 8)
createStroke(hud.ChatFrame, Color3.fromRGB(0, 0, 0), 1, 0.82)

hud.ChatLabel = Instance.new("TextLabel")
hud.ChatLabel.Name = "ChatLabel"
hud.ChatLabel.Position = UDim2.fromOffset(14, 0)
hud.ChatLabel.Size = UDim2.new(1, -28, 1, 0)
hud.ChatLabel.BackgroundTransparency = 1
hud.ChatLabel.Text = "Chat coming soon..."
hud.ChatLabel.TextColor3 = Color3.fromRGB(86, 96, 104)
hud.ChatLabel.TextSize = 15
hud.ChatLabel.TextXAlignment = Enum.TextXAlignment.Left
hud.ChatLabel.Font = Enum.Font.Gotham
hud.ChatLabel.Parent = hud.ChatFrame

hud.InventoryButton = Instance.new("TextButton")
hud.InventoryButton.Name = "InventoryButton"
hud.InventoryButton.AnchorPoint = Vector2.new(1, 0.5)
hud.InventoryButton.Position = UDim2.new(
	1,
	-(ACTION_BUTTON_RIGHT_MARGIN + (ACTION_BUTTON_WIDTH + ACTION_BUTTON_GAP) * 2),
	0.5,
	0
)
hud.InventoryButton.Size = UDim2.fromOffset(ACTION_BUTTON_WIDTH, ACTION_BUTTON_HEIGHT)
hud.InventoryButton.BackgroundColor3 = Color3.fromRGB(63, 98, 78)
hud.InventoryButton.BorderSizePixel = 0
hud.InventoryButton.Text = "Bag"
hud.InventoryButton.TextColor3 = Color3.fromRGB(245, 248, 250)
hud.InventoryButton.TextSize = 14
hud.InventoryButton.Font = Enum.Font.GothamBold
hud.InventoryButton.Parent = hud.Bar

createCorner(hud.InventoryButton, 8)
createStroke(hud.InventoryButton, Color3.fromRGB(255, 255, 255), 1, 0.78)

hud.CatalogButton = Instance.new("TextButton")
hud.CatalogButton.Name = "CatalogButton"
hud.CatalogButton.AnchorPoint = Vector2.new(1, 0.5)
hud.CatalogButton.Position = UDim2.new(
	1,
	-(ACTION_BUTTON_RIGHT_MARGIN + ACTION_BUTTON_WIDTH + ACTION_BUTTON_GAP),
	0.5,
	0
)
hud.CatalogButton.Size = UDim2.fromOffset(ACTION_BUTTON_WIDTH, ACTION_BUTTON_HEIGHT)
hud.CatalogButton.BackgroundColor3 = Color3.fromRGB(92, 72, 48)
hud.CatalogButton.BorderSizePixel = 0
hud.CatalogButton.Text = "Catalog"
hud.CatalogButton.TextColor3 = Color3.fromRGB(245, 248, 250)
hud.CatalogButton.TextSize = 13
hud.CatalogButton.Font = Enum.Font.GothamBold
hud.CatalogButton.Parent = hud.Bar

createCorner(hud.CatalogButton, 8)
createStroke(hud.CatalogButton, Color3.fromRGB(255, 255, 255), 1, 0.78)

hud.EditButton = Instance.new("TextButton")
hud.EditButton.Name = "EditButton"
hud.EditButton.AnchorPoint = Vector2.new(1, 0.5)
hud.EditButton.Position = UDim2.new(1, -ACTION_BUTTON_RIGHT_MARGIN, 0.5, 0)
hud.EditButton.Size = UDim2.fromOffset(ACTION_BUTTON_WIDTH, ACTION_BUTTON_HEIGHT)
hud.EditButton.BackgroundColor3 = Color3.fromRGB(49, 63, 78)
hud.EditButton.BorderSizePixel = 0
hud.EditButton.Text = "Edit"
hud.EditButton.TextColor3 = Color3.fromRGB(245, 248, 250)
hud.EditButton.TextSize = 13
hud.EditButton.Font = Enum.Font.GothamBold
hud.EditButton.Parent = hud.Bar

createCorner(hud.EditButton, 8)
createStroke(hud.EditButton, Color3.fromRGB(255, 255, 255), 1, 0.78)

local function setMenuExpanded(isExpanded)
	menuExpanded = isExpanded == true
	hud.MenuList.Visible = menuExpanded and hud.Bar.Visible
	hud.RoomDetails.Visible = hud.Bar.Visible and not menuExpanded
end

local function getCurrentRoom()
	local roomName = player:GetAttribute("CurrentRoomName")

	if typeof(roomName) ~= "string" or roomName == "" then
		return nil, nil
	end

	return activeRooms:FindFirstChild(roomName), roomName
end

local function getOwnerText(roomModel)
	if not roomModel then
		return ""
	end

	if roomModel:GetAttribute("RoomType") == "PublicSpace" then
		return "Public Space"
	end

	local ownerUserId = roomModel:GetAttribute("OwnerUserId")

	if typeof(ownerUserId) == "number" and ownerUserId > 0 then
		local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)

		if ownerPlayer then
			return "Owner: " .. tostring(ownerPlayer.DisplayName or ownerPlayer.Name)
		end

		return "Owner: User_" .. tostring(ownerUserId)
	end

	return "Owner: Unknown"
end

local function updateRoomDetails()
	local roomModel, roomName = getCurrentRoom()

	if not roomModel then
		hud.RoomTitle.Text = "Room"
		hud.RoomOwner.Text = ""
		return
	end

	local displayName = roomModel:GetAttribute("DisplayName")

	if typeof(displayName) ~= "string" or displayName == "" then
		displayName = roomName or roomModel.Name
	end

	hud.RoomTitle.Text = tostring(displayName)
	hud.RoomOwner.Text = getOwnerText(roomModel)
end

local function canEditCurrentRoom()
	local roomModel = getCurrentRoom()

	if not roomModel then
		return false
	end

	if roomModel:GetAttribute("RoomType") == "PublicSpace" then
		return false
	end

	return roomModel:GetAttribute("OwnerUserId") == player.UserId
end

local function updateEditButton()
	local canEdit = canEditCurrentRoom()
	local roomMode = player:GetAttribute("RoomMode") or "Play"

	hud.EditButton.Active = canEdit
	hud.EditButton.AutoButtonColor = canEdit
	hud.EditButton.Text = canEdit and (roomMode == "Edit" and "Done" or "Edit") or "Edit"
	hud.EditButton.TextColor3 = canEdit
		and Color3.fromRGB(245, 248, 250)
		or Color3.fromRGB(165, 174, 182)
	hud.EditButton.BackgroundColor3 = not canEdit
		and Color3.fromRGB(42, 49, 56)
		or roomMode == "Edit"
			and Color3.fromRGB(160, 72, 54)
			or Color3.fromRGB(49, 63, 78)
end

local function shouldShowHud()
	local currentRoomName = player:GetAttribute("CurrentRoomName")

	return player:GetAttribute("OnboardingStep") == "Complete"
		and player:GetAttribute("InHotelMainMenu") ~= true
		and typeof(currentRoomName) == "string"
		and currentRoomName ~= ""
		and (player:GetAttribute("ControlMode") or "Hotel") == "Hotel"
end

local function updateVisibility()
	local shouldShow = shouldShowHud()

	hud.Bar.Visible = shouldShow
	hud.RoomDetails.Visible = shouldShow and not menuExpanded
	hud.MenuList.Visible = shouldShow and menuExpanded

	if shouldShow then
		updateRoomDetails()
		updateEditButton()
	else
		setMenuExpanded(false)
	end
end

hud.MenuButton.MouseButton1Click:Connect(function()
	setMenuExpanded(not menuExpanded)
end)

hud.MenuRoomsButton.MouseButton1Click:Connect(function()
	setMenuExpanded(false)
	openRoomNavigator:Fire()
end)

local function openInventoryMenu()
	setMenuExpanded(false)
	openInventory:Fire()
end

hud.MenuInventoryButton.MouseButton1Click:Connect(openInventoryMenu)
hud.InventoryButton.MouseButton1Click:Connect(openInventoryMenu)

local function openCatalogMenu()
	setMenuExpanded(false)
	openCatalog:Fire()
end

hud.MenuCatalogButton.MouseButton1Click:Connect(openCatalogMenu)
hud.CatalogButton.MouseButton1Click:Connect(openCatalogMenu)

hud.EditButton.MouseButton1Click:Connect(function()
	setMenuExpanded(false)
	toggleRoomMode:Fire()
end)

majorMenuOpened.Event:Connect(function(menuName)
	if menuName ~= "MainHudMenu" then
		setMenuExpanded(false)
	end
end)

closeMajorMenus.Event:Connect(function()
	setMenuExpanded(false)
end)

player:GetAttributeChangedSignal("CurrentRoomName"):Connect(updateVisibility)
player:GetAttributeChangedSignal("OnboardingStep"):Connect(updateVisibility)
player:GetAttributeChangedSignal("ControlMode"):Connect(updateVisibility)
player:GetAttributeChangedSignal("InHotelMainMenu"):Connect(updateVisibility)
player:GetAttributeChangedSignal("RoomMode"):Connect(updateVisibility)
player:GetAttributeChangedSignal("CanEditCurrentRoom"):Connect(updateVisibility)

activeRooms.ChildAdded:Connect(function(child)
	if child.Name == player:GetAttribute("CurrentRoomName") then
		task.defer(updateVisibility)
	end
end)

activeRooms.ChildRemoved:Connect(function(child)
	if child.Name == player:GetAttribute("CurrentRoomName") then
		task.defer(updateVisibility)
	end
end)

Players.PlayerAdded:Connect(updateRoomDetails)
Players.PlayerRemoving:Connect(updateRoomDetails)

task.defer(updateVisibility)
