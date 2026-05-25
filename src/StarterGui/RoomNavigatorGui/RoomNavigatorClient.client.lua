-- Explorer/StarterGui/RoomNavigatorGui/RoomNavigatorClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local roomListRequest = remoteEvents:WaitForChild("RoomListRequest")
local roomListUpdate = remoteEvents:WaitForChild("RoomListUpdate")
local joinRoomRequest = remoteEvents:WaitForChild("JoinRoomRequest")
local joinRoomResult = remoteEvents:WaitForChild("JoinRoomResult")
local roomCreationResult = remoteEvents:WaitForChild("RoomCreationResult")

local DEFAULT_PUBLIC_CATEGORIES = {
	"Welcome Lounge",
	"Entertainment",
	"Outside Spaces",
	"Gamehall",
	"Cafes",
	"Restaurants",
	"Dance Clubs",
}

local GUEST_ROOM_CATEGORIES = {
	"Chat Rooms",
	"Maze Rooms",
	"Trading Rooms",
	"Help Centres",
	"Gaming & Race Rooms",
}

local TOP_TAB_PUBLIC = "PublicSpaces"
local TOP_TAB_ROOMS = "Rooms"
local ROOM_SUBTAB_SEARCH = "Search"
local ROOM_SUBTAB_OWN = "OwnRooms"
local ROOM_SUBTAB_FAVOURITES = "Favourites"
local ROOM_SUBTAB_GUEST = "GuestRooms"

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

local selectedTopTab = TOP_TAB_ROOMS
local selectedRoomSubtab = ROOM_SUBTAB_GUEST
local selectedGuestCategory = "Chat Rooms"
local selectedRoomData = nil
local selectedRow = nil
local latestRoomList = {}
local latestCurrentRoomName = player:GetAttribute("CurrentRoomName")
local searchQuery = ""

local function copyPublicRoomData(roomData)
	if typeof(roomData) ~= "table" then
		return nil
	end

	local publicRoomId = roomData.Id

	if typeof(publicRoomId) ~= "string" or publicRoomId == "" then
		return nil
	end

	local activeRoomName = "Public_" .. publicRoomId

	return {
		RoomType = "PublicSpace",
		Id = publicRoomId,
		PublicRoomId = publicRoomId,
		RoomKey = "PublicSpace:" .. publicRoomId,
		ActiveRoomName = activeRoomName,
		DisplayName = roomData.DisplayName or publicRoomId,
		Category = roomData.Category or "Public Spaces",
		Description = roomData.Description or "",
		MaxOccupancy = roomData.MaxOccupancy,
		SortOrder = roomData.SortOrder,
	}
end

local function addUniqueCategory(categories, categoryName)
	if typeof(categoryName) ~= "string" or categoryName == "" then
		return
	end

	for _, existingCategory in ipairs(categories) do
		if existingCategory == categoryName then
			return
		end
	end

	table.insert(categories, categoryName)
end

local function loadPublicConfig()
	local categories = {}
	local rooms = {}

	for _, categoryName in ipairs(DEFAULT_PUBLIC_CATEGORIES) do
		table.insert(categories, categoryName)
	end

	local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")

	if not sharedFolder then
		return categories, rooms
	end

	local configModule = sharedFolder:FindFirstChild("PublicRoomConfig")

	if not configModule or not configModule:IsA("ModuleScript") then
		return categories, rooms
	end

	local ok, config = pcall(require, configModule)

	if not ok or typeof(config) ~= "table" then
		return categories, rooms
	end

	if typeof(config.GetPublicCategories) == "function" then
		local categoriesOk, publicCategoriesResult = pcall(config.GetPublicCategories)

		if categoriesOk and typeof(publicCategoriesResult) == "table" then
			categories = {}

			for _, categoryName in ipairs(publicCategoriesResult) do
				addUniqueCategory(categories, categoryName)
			end
		end
	elseif typeof(config.Categories) == "table" then
		categories = {}

		for _, categoryName in ipairs(config.Categories) do
			addUniqueCategory(categories, categoryName)
		end
	end

	if #categories == 0 then
		for _, categoryName in ipairs(DEFAULT_PUBLIC_CATEGORIES) do
			table.insert(categories, categoryName)
		end
	end

	if typeof(config.GetPublicRoomsArray) == "function" then
		local roomsOk, publicRoomsResult = pcall(config.GetPublicRoomsArray)

		if roomsOk and typeof(publicRoomsResult) == "table" then
			for _, roomData in ipairs(publicRoomsResult) do
				local publicRoom = copyPublicRoomData(roomData)

				if publicRoom then
					addUniqueCategory(categories, publicRoom.Category)
					table.insert(rooms, publicRoom)
				end
			end
		end
	elseif typeof(config.PublicRooms) == "table" then
		for _, roomData in pairs(config.PublicRooms) do
			local publicRoom = copyPublicRoomData(roomData)

			if publicRoom then
				addUniqueCategory(categories, publicRoom.Category)
				table.insert(rooms, publicRoom)
			end
		end
	end

	table.sort(rooms, function(a, b)
		local aOrder = typeof(a.SortOrder) == "number" and a.SortOrder or math.huge
		local bOrder = typeof(b.SortOrder) == "number" and b.SortOrder or math.huge

		if aOrder == bOrder then
			return tostring(a.DisplayName or a.PublicRoomId) < tostring(b.DisplayName or b.PublicRoomId)
		end

		return aOrder < bOrder
	end)

	return categories, rooms
end

local publicCategories, publicRooms = loadPublicConfig()

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
openButton.BorderSizePixel = 0
openButton.Text = "Rooms"
openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
openButton.TextSize = 20
openButton.Font = Enum.Font.GothamBold
openButton.Visible = false
openButton.Parent = gui

createCorner(openButton, 10)

local panel = Instance.new("Frame")
panel.Name = "HotelNavigatorPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.new(0.88, 0, 0.82, 0)
panel.BackgroundColor3 = Color3.fromRGB(238, 240, 232)
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

local panelSize = Instance.new("UISizeConstraint")
panelSize.MaxSize = Vector2.new(900, 620)
panelSize.MinSize = Vector2.new(620, 430)
panelSize.Parent = panel

createCorner(panel, 10)
createStroke(panel, Color3.fromRGB(180, 188, 176), 1, 0)

local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 58)
titleBar.BackgroundColor3 = Color3.fromRGB(42, 67, 83)
titleBar.BorderSizePixel = 0
titleBar.Parent = panel

createCorner(titleBar, 10)

local titleCover = Instance.new("Frame")
titleCover.Name = "TitleCover"
titleCover.AnchorPoint = Vector2.new(0, 1)
titleCover.Position = UDim2.new(0, 0, 1, 0)
titleCover.Size = UDim2.new(1, 0, 0, 10)
titleCover.BackgroundColor3 = titleBar.BackgroundColor3
titleCover.BorderSizePixel = 0
titleCover.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Position = UDim2.fromOffset(20, 12)
titleLabel.Size = UDim2.new(1, -82, 0, 34)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Hotel Navigator"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextSize = 24
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Parent = titleBar

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -16, 0, 14)
closeButton.Size = UDim2.fromOffset(32, 30)
closeButton.BackgroundColor3 = Color3.fromRGB(224, 230, 222)
closeButton.BorderSizePixel = 0
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(45, 48, 45)
closeButton.TextSize = 14
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = titleBar

createCorner(closeButton, 6)

local topTabsFrame = Instance.new("Frame")
topTabsFrame.Name = "TopTabs"
topTabsFrame.Position = UDim2.fromOffset(18, 70)
topTabsFrame.Size = UDim2.new(1, -36, 0, 42)
topTabsFrame.BackgroundTransparency = 1
topTabsFrame.Parent = panel

local topTabsLayout = Instance.new("UIListLayout")
topTabsLayout.FillDirection = Enum.FillDirection.Horizontal
topTabsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
topTabsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
topTabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
topTabsLayout.Padding = UDim.new(0, 8)
topTabsLayout.Parent = topTabsFrame

local function createTextButton(name, text, size, parent)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.BackgroundColor3 = Color3.fromRGB(216, 222, 214)
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = Color3.fromRGB(45, 48, 45)
	button.TextSize = 15
	button.Font = Enum.Font.GothamBold
	button.AutoButtonColor = true
	button.Parent = parent

	createCorner(button, 7)

	return button
end

local publicSpacesTab = createTextButton(
	"PublicSpacesTab",
	"Public Spaces",
	UDim2.fromOffset(150, 38),
	topTabsFrame
)

local roomsTab = createTextButton(
	"RoomsTab",
	"Rooms",
	UDim2.fromOffset(120, 38),
	topTabsFrame
)

local roomsNav = Instance.new("Frame")
roomsNav.Name = "RoomsNavigation"
roomsNav.Position = UDim2.fromOffset(18, 124)
roomsNav.Size = UDim2.new(0, 150, 1, -266)
roomsNav.BackgroundColor3 = Color3.fromRGB(229, 232, 224)
roomsNav.BorderSizePixel = 0
roomsNav.Parent = panel

createCorner(roomsNav, 8)
createStroke(roomsNav, Color3.fromRGB(205, 212, 200), 1, 0)

local roomsNavLayout = Instance.new("UIListLayout")
roomsNavLayout.SortOrder = Enum.SortOrder.LayoutOrder
roomsNavLayout.Padding = UDim.new(0, 6)
roomsNavLayout.Parent = roomsNav

local roomsNavPadding = Instance.new("UIPadding")
roomsNavPadding.PaddingTop = UDim.new(0, 10)
roomsNavPadding.PaddingLeft = UDim.new(0, 10)
roomsNavPadding.PaddingRight = UDim.new(0, 10)
roomsNavPadding.Parent = roomsNav

local searchSubtabButton = createTextButton("SearchSubtab", "Search", UDim2.new(1, 0, 0, 34), roomsNav)
local ownSubtabButton = createTextButton("OwnRoomsSubtab", "Own Room(s)", UDim2.new(1, 0, 0, 34), roomsNav)
local favouritesSubtabButton = createTextButton("FavouritesSubtab", "Favourites", UDim2.new(1, 0, 0, 34), roomsNav)
local guestSubtabButton = createTextButton("GuestRoomsSubtab", "Guest Rooms", UDim2.new(1, 0, 0, 34), roomsNav)

local contentFrame = Instance.new("Frame")
contentFrame.Name = "ContentFrame"
contentFrame.Position = UDim2.fromOffset(180, 124)
contentFrame.Size = UDim2.new(1, -198, 1, -266)
contentFrame.BackgroundColor3 = Color3.fromRGB(249, 250, 247)
contentFrame.BorderSizePixel = 0
contentFrame.Parent = panel

createCorner(contentFrame, 8)
createStroke(contentFrame, Color3.fromRGB(205, 212, 200), 1, 0)

local sectionTitle = Instance.new("TextLabel")
sectionTitle.Name = "SectionTitle"
sectionTitle.Position = UDim2.fromOffset(14, 8)
sectionTitle.Size = UDim2.new(1, -28, 0, 24)
sectionTitle.BackgroundTransparency = 1
sectionTitle.Text = ""
sectionTitle.TextColor3 = Color3.fromRGB(48, 54, 48)
sectionTitle.TextSize = 17
sectionTitle.TextXAlignment = Enum.TextXAlignment.Left
sectionTitle.Font = Enum.Font.GothamBold
sectionTitle.Parent = contentFrame

local searchBox = Instance.new("TextBox")
searchBox.Name = "SearchBox"
searchBox.Position = UDim2.fromOffset(14, 40)
searchBox.Size = UDim2.new(1, -28, 0, 34)
searchBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
searchBox.BorderSizePixel = 0
searchBox.PlaceholderText = "Search rooms or owners"
searchBox.Text = ""
searchBox.TextColor3 = Color3.fromRGB(40, 40, 40)
searchBox.PlaceholderColor3 = Color3.fromRGB(130, 130, 130)
searchBox.TextSize = 14
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.Font = Enum.Font.Gotham
searchBox.ClearTextOnFocus = false
searchBox.Visible = false
searchBox.Parent = contentFrame

createCorner(searchBox, 6)
createStroke(searchBox, Color3.fromRGB(215, 220, 214), 1, 0)

local searchPadding = Instance.new("UIPadding")
searchPadding.PaddingLeft = UDim.new(0, 10)
searchPadding.PaddingRight = UDim.new(0, 10)
searchPadding.Parent = searchBox

local categoryBar = Instance.new("Frame")
categoryBar.Name = "GuestCategoryBar"
categoryBar.Position = UDim2.fromOffset(14, 40)
categoryBar.Size = UDim2.new(1, -28, 0, 38)
categoryBar.BackgroundTransparency = 1
categoryBar.Visible = false
categoryBar.Parent = contentFrame

local categoryLayout = Instance.new("UIListLayout")
categoryLayout.FillDirection = Enum.FillDirection.Horizontal
categoryLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
categoryLayout.VerticalAlignment = Enum.VerticalAlignment.Center
categoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
categoryLayout.Padding = UDim.new(0, 6)
categoryLayout.Parent = categoryBar

local listFrame = Instance.new("ScrollingFrame")
listFrame.Name = "NavigatorList"
listFrame.Position = UDim2.fromOffset(14, 84)
listFrame.Size = UDim2.new(1, -28, 1, -98)
listFrame.BackgroundTransparency = 1
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 6
listFrame.CanvasSize = UDim2.fromOffset(0, 0)
listFrame.Parent = contentFrame

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = listFrame

local detailPanel = Instance.new("Frame")
detailPanel.Name = "SelectedRoomDetails"
detailPanel.AnchorPoint = Vector2.new(0, 1)
detailPanel.Position = UDim2.new(0, 18, 1, -18)
detailPanel.Size = UDim2.new(1, -36, 0, 116)
detailPanel.BackgroundColor3 = Color3.fromRGB(224, 230, 220)
detailPanel.BorderSizePixel = 0
detailPanel.Parent = panel

createCorner(detailPanel, 8)
createStroke(detailPanel, Color3.fromRGB(190, 200, 186), 1, 0)

local detailTitle = Instance.new("TextLabel")
detailTitle.Name = "DetailTitle"
detailTitle.Position = UDim2.fromOffset(14, 10)
detailTitle.Size = UDim2.new(1, -260, 0, 24)
detailTitle.BackgroundTransparency = 1
detailTitle.Text = "Select a room"
detailTitle.TextColor3 = Color3.fromRGB(42, 48, 42)
detailTitle.TextSize = 17
detailTitle.TextXAlignment = Enum.TextXAlignment.Left
detailTitle.TextTruncate = Enum.TextTruncate.AtEnd
detailTitle.Font = Enum.Font.GothamBold
detailTitle.Parent = detailPanel

local detailOwner = Instance.new("TextLabel")
detailOwner.Name = "DetailOwner"
detailOwner.Position = UDim2.fromOffset(14, 38)
detailOwner.Size = UDim2.new(1, -260, 0, 20)
detailOwner.BackgroundTransparency = 1
detailOwner.Text = "Owner: -"
detailOwner.TextColor3 = Color3.fromRGB(82, 88, 82)
detailOwner.TextSize = 13
detailOwner.TextXAlignment = Enum.TextXAlignment.Left
detailOwner.TextTruncate = Enum.TextTruncate.AtEnd
detailOwner.Font = Enum.Font.Gotham
detailOwner.Parent = detailPanel

local detailMeta = Instance.new("TextLabel")
detailMeta.Name = "DetailMeta"
detailMeta.Position = UDim2.fromOffset(14, 62)
detailMeta.Size = UDim2.new(1, -260, 0, 20)
detailMeta.BackgroundTransparency = 1
detailMeta.Text = "Occupancy: -"
detailMeta.TextColor3 = Color3.fromRGB(82, 88, 82)
detailMeta.TextSize = 13
detailMeta.TextXAlignment = Enum.TextXAlignment.Left
detailMeta.TextTruncate = Enum.TextTruncate.AtEnd
detailMeta.Font = Enum.Font.Gotham
detailMeta.Parent = detailPanel

local detailStatus = Instance.new("TextLabel")
detailStatus.Name = "DetailStatus"
detailStatus.Position = UDim2.fromOffset(14, 86)
detailStatus.Size = UDim2.new(1, -260, 0, 18)
detailStatus.BackgroundTransparency = 1
detailStatus.Text = ""
detailStatus.TextColor3 = Color3.fromRGB(105, 90, 55)
detailStatus.TextSize = 12
detailStatus.TextXAlignment = Enum.TextXAlignment.Left
detailStatus.Font = Enum.Font.GothamMedium
detailStatus.Parent = detailPanel

local favouriteButton = createTextButton(
	"FavouriteButton",
	"Favourites Soon",
	UDim2.fromOffset(130, 36),
	detailPanel
)
favouriteButton.AnchorPoint = Vector2.new(1, 0)
favouriteButton.Position = UDim2.new(1, -144, 0, 40)
favouriteButton.BackgroundColor3 = Color3.fromRGB(180, 185, 180)
favouriteButton.TextColor3 = Color3.fromRGB(245, 245, 245)
favouriteButton.Active = false
favouriteButton.AutoButtonColor = false

local goButton = createTextButton("GoButton", "Go", UDim2.fromOffset(108, 36), detailPanel)
goButton.AnchorPoint = Vector2.new(1, 0)
goButton.Position = UDim2.new(1, -20, 0, 40)
goButton.BackgroundColor3 = Color3.fromRGB(110, 115, 110)
goButton.TextColor3 = Color3.fromRGB(255, 255, 255)
goButton.Active = false
goButton.AutoButtonColor = false

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.AnchorPoint = Vector2.new(1, 0)
statusLabel.Position = UDim2.new(1, -20, 0, 84)
statusLabel.Size = UDim2.fromOffset(230, 20)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = ""
statusLabel.TextColor3 = Color3.fromRGB(90, 90, 90)
statusLabel.TextSize = 12
statusLabel.TextXAlignment = Enum.TextXAlignment.Right
statusLabel.Font = Enum.Font.Gotham
statusLabel.Parent = detailPanel

local categoryButtons = {}

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

local renderNavigator = nil

local function setPanelVisible(isVisible)
	local wasVisible = panel.Visible

	if isVisible then
		publishMajorMenuState(true)
		majorMenuOpened:Fire(MENU_NAME)
	end

	panel.Visible = isVisible
	updateOpenButton()

	if isVisible then
		roomListRequest:FireServer()

		if renderNavigator then
			renderNavigator()
		end
	end

	if not isVisible and (wasVisible or openMajorMenuName == MENU_NAME) then
		publishMajorMenuState(false)
	end
end

local function getRoomDisplayName(roomData)
	if typeof(roomData.DisplayName) == "string" and roomData.DisplayName ~= "" then
		return roomData.DisplayName
	end

	local ownerDisplayName = roomData.OwnerDisplayName or roomData.OwnerName or "Unknown"
	return tostring(ownerDisplayName) .. "'s Room"
end

local function getRoomOwnerText(roomData)
	if roomData.RoomType == "PublicSpace" then
		return "Hotel"
	end

	local owner = roomData.OwnerDisplayName or roomData.OwnerName or "Unknown"
	return tostring(owner)
end

local function getOccupancyText(roomData)
	local occupancy = roomData.Occupancy or roomData.PlayerCount
	local maxOccupancy = roomData.MaxOccupancy

	if typeof(occupancy) == "number" and typeof(maxOccupancy) == "number" then
		return tostring(occupancy) .. "/" .. tostring(maxOccupancy)
	end

	if typeof(maxOccupancy) == "number" then
		return "Max " .. tostring(maxOccupancy)
	end

	return tostring(occupancy or 0)
end

local function isEntryCurrentRoom(entry)
	if typeof(entry) ~= "table" then
		return false
	end

	local currentRoomName = player:GetAttribute("CurrentRoomName") or latestCurrentRoomName

	if typeof(currentRoomName) ~= "string" or currentRoomName == "" then
		return false
	end

	if entry.IsCurrentRoom == true then
		return true
	end

	if typeof(entry.RoomName) == "string" and entry.RoomName == currentRoomName then
		return true
	end

	if typeof(entry.ActiveRoomName) == "string" and entry.ActiveRoomName == currentRoomName then
		return true
	end

	local publicRoomId = entry.PublicRoomId or entry.Id

	if typeof(publicRoomId) == "string"
		and publicRoomId ~= ""
		and "Public_" .. publicRoomId == currentRoomName then

		return true
	end

	return false
end

local function updateTopTabButton(button, isSelected)
	button.BackgroundColor3 = isSelected and Color3.fromRGB(72, 119, 143) or Color3.fromRGB(216, 222, 214)
	button.TextColor3 = isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(45, 48, 45)
end

local function updateSubtabButton(button, isSelected)
	button.BackgroundColor3 = isSelected and Color3.fromRGB(88, 128, 102) or Color3.fromRGB(244, 246, 242)
	button.TextColor3 = isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(48, 54, 48)
end

local function updateCategoryButtons()
	for categoryName, button in pairs(categoryButtons) do
		local isSelected = categoryName == selectedGuestCategory
		button.BackgroundColor3 = isSelected and Color3.fromRGB(74, 118, 148) or Color3.fromRGB(228, 234, 226)
		button.TextColor3 = isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(45, 50, 45)
	end
end

local function updateNavigationState()
	updateTopTabButton(publicSpacesTab, selectedTopTab == TOP_TAB_PUBLIC)
	updateTopTabButton(roomsTab, selectedTopTab == TOP_TAB_ROOMS)

	roomsNav.Visible = selectedTopTab == TOP_TAB_ROOMS

	updateSubtabButton(searchSubtabButton, selectedRoomSubtab == ROOM_SUBTAB_SEARCH)
	updateSubtabButton(ownSubtabButton, selectedRoomSubtab == ROOM_SUBTAB_OWN)
	updateSubtabButton(favouritesSubtabButton, selectedRoomSubtab == ROOM_SUBTAB_FAVOURITES)
	updateSubtabButton(guestSubtabButton, selectedRoomSubtab == ROOM_SUBTAB_GUEST)
	updateCategoryButtons()

	if selectedTopTab == TOP_TAB_ROOMS then
		contentFrame.Position = UDim2.fromOffset(180, 124)
		contentFrame.Size = UDim2.new(1, -198, 1, -266)
	else
		contentFrame.Position = UDim2.fromOffset(18, 124)
		contentFrame.Size = UDim2.new(1, -36, 1, -266)
	end
end

local function clearList()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function updateCanvasSize()
	task.defer(function()
		listFrame.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 12)
	end)
end

local function setRowSelected(row, isSelected)
	local stroke = row:FindFirstChild("RowStroke")

	if stroke then
		stroke.Color = isSelected and Color3.fromRGB(68, 128, 166) or Color3.fromRGB(213, 220, 210)
		stroke.Thickness = isSelected and 2 or 1
	end

	row.BackgroundColor3 = isSelected and Color3.fromRGB(231, 243, 249) or Color3.fromRGB(255, 255, 255)
end

local function updateDetailPanel()
	if not selectedRoomData then
		detailTitle.Text = "Select a room"
		detailOwner.Text = "Owner: -"
		detailMeta.Text = "Occupancy: -"
		detailStatus.Text = ""
		goButton.Text = "Go"
		goButton.BackgroundColor3 = Color3.fromRGB(110, 115, 110)
		goButton.Active = false
		goButton.AutoButtonColor = false
		return
	end

	detailTitle.Text = getRoomDisplayName(selectedRoomData)
	detailOwner.Text = "Owner: " .. getRoomOwnerText(selectedRoomData)
	detailMeta.Text = "Occupancy: "
		.. getOccupancyText(selectedRoomData)
		.. "  -  Category: "
		.. tostring(selectedRoomData.Category or "Guest Rooms")
	local isCurrentRoom = isEntryCurrentRoom(selectedRoomData)

	detailStatus.Text = isCurrentRoom and "You are here." or ""

	if isCurrentRoom then
		goButton.Active = false
		goButton.AutoButtonColor = false
		goButton.BackgroundColor3 = Color3.fromRGB(110, 115, 110)
		goButton.Text = "Here"
		return
	end

	local canGo = (typeof(selectedRoomData.RoomName) == "string" and selectedRoomData.RoomName ~= "")
		or (
			selectedRoomData.RoomType == "PublicSpace"
			and typeof(selectedRoomData.PublicRoomId) == "string"
			and selectedRoomData.PublicRoomId ~= ""
		)

	goButton.Active = canGo
	goButton.AutoButtonColor = canGo
	goButton.BackgroundColor3 = canGo and Color3.fromRGB(68, 143, 82) or Color3.fromRGB(110, 115, 110)
	goButton.Text = canGo and "Go" or "Unavailable"
end

local function selectRoom(roomData, row)
	if selectedRow then
		setRowSelected(selectedRow, false)
	end

	selectedRoomData = roomData
	selectedRow = row

	if selectedRow then
		setRowSelected(selectedRow, true)
	end

	updateDetailPanel()
end

local function joinSelectedRoom()
	if not selectedRoomData then
		return
	end

	if isEntryCurrentRoom(selectedRoomData) then
		return
	end

	if selectedRoomData.RoomType == "PublicSpace" then
		local publicRoomId = selectedRoomData.PublicRoomId

		if typeof(publicRoomId) ~= "string" or publicRoomId == "" then
			statusLabel.Text = "This public space is not available yet."
			return
		end

		statusLabel.Text = "Joining..."
		goButton.Text = "Joining..."
		goButton.Active = false
		goButton.AutoButtonColor = false
		goButton.BackgroundColor3 = Color3.fromRGB(110, 115, 110)

		joinRoomRequest:FireServer({
			RoomType = "PublicSpace",
			PublicRoomId = publicRoomId,
		})

		return
	end

	local roomName = selectedRoomData.RoomName

	if typeof(roomName) ~= "string" or roomName == "" then
		statusLabel.Text = "This room is not available yet."
		return
	end

	statusLabel.Text = "Joining..."
	goButton.Text = "Joining..."
	goButton.Active = false
	goButton.AutoButtonColor = false
	goButton.BackgroundColor3 = Color3.fromRGB(110, 115, 110)

	joinRoomRequest:FireServer(roomName)
end

local function createEmptyState(message)
	local emptyFrame = Instance.new("Frame")
	emptyFrame.Name = "EmptyState"
	emptyFrame.Size = UDim2.new(1, -4, 0, 76)
	emptyFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	emptyFrame.BorderSizePixel = 0
	emptyFrame.Parent = listFrame

	createCorner(emptyFrame, 8)
	createStroke(emptyFrame, Color3.fromRGB(220, 226, 218), 1, 0)

	local label = Instance.new("TextLabel")
	label.Name = "Message"
	label.Position = UDim2.fromOffset(14, 12)
	label.Size = UDim2.new(1, -28, 1, -24)
	label.BackgroundTransparency = 1
	label.Text = message
	label.TextColor3 = Color3.fromRGB(90, 96, 90)
	label.TextSize = 14
	label.TextWrapped = true
	label.Font = Enum.Font.Gotham
	label.Parent = emptyFrame
end

local function createPublicSpaceRow(publicRoomData, order)
	local row = Instance.new("TextButton")
	row.Name = tostring(publicRoomData.PublicRoomId or publicRoomData.DisplayName or "PublicSpace")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -4, 0, 82)
	row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	row.BorderSizePixel = 0
	row.Text = ""
	row.AutoButtonColor = true
	row.Parent = listFrame

	createCorner(row, 8)

	local stroke = createStroke(row, Color3.fromRGB(220, 226, 218), 1, 0)
	stroke.Name = "RowStroke"

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Position = UDim2.fromOffset(14, 8)
	nameLabel.Size = UDim2.new(1, -140, 0, 22)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = tostring(publicRoomData.DisplayName or publicRoomData.PublicRoomId)
	nameLabel.TextColor3 = Color3.fromRGB(45, 50, 45)
	nameLabel.TextSize = 16
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = row

	local noteLabel = Instance.new("TextLabel")
	noteLabel.Name = "NoteLabel"
	noteLabel.Position = UDim2.fromOffset(14, 32)
	noteLabel.Size = UDim2.new(1, -150, 0, 18)
	noteLabel.BackgroundTransparency = 1
	noteLabel.Text = tostring(publicRoomData.Description or "")
	noteLabel.TextColor3 = Color3.fromRGB(95, 100, 95)
	noteLabel.TextSize = 12
	noteLabel.TextXAlignment = Enum.TextXAlignment.Left
	noteLabel.TextTruncate = Enum.TextTruncate.AtEnd
	noteLabel.Font = Enum.Font.Gotham
	noteLabel.Parent = row

	local categoryLabel = Instance.new("TextLabel")
	categoryLabel.Name = "Category"
	categoryLabel.Position = UDim2.fromOffset(14, 56)
	categoryLabel.Size = UDim2.new(1, -150, 0, 16)
	categoryLabel.BackgroundTransparency = 1
	categoryLabel.Text = tostring(publicRoomData.Category or "Public Spaces")
	categoryLabel.TextColor3 = Color3.fromRGB(102, 108, 102)
	categoryLabel.TextSize = 11
	categoryLabel.TextXAlignment = Enum.TextXAlignment.Left
	categoryLabel.TextTruncate = Enum.TextTruncate.AtEnd
	categoryLabel.Font = Enum.Font.GothamMedium
	categoryLabel.Parent = row

	local occupancyLabel = Instance.new("TextLabel")
	occupancyLabel.Name = "Occupancy"
	occupancyLabel.AnchorPoint = Vector2.new(1, 0)
	occupancyLabel.Position = UDim2.new(1, -84, 0, 11)
	occupancyLabel.Size = UDim2.fromOffset(70, 20)
	occupancyLabel.BackgroundTransparency = 1
	occupancyLabel.Text = getOccupancyText(publicRoomData)
	occupancyLabel.TextColor3 = Color3.fromRGB(60, 90, 70)
	occupancyLabel.TextSize = 14
	occupancyLabel.TextXAlignment = Enum.TextXAlignment.Right
	occupancyLabel.Font = Enum.Font.GothamBold
	occupancyLabel.Parent = row

	if isEntryCurrentRoom(publicRoomData) then
		local hereBadge = Instance.new("TextLabel")
		hereBadge.Name = "HereBadge"
		hereBadge.AnchorPoint = Vector2.new(1, 1)
		hereBadge.Position = UDim2.new(1, -14, 1, -10)
		hereBadge.Size = UDim2.fromOffset(58, 28)
		hereBadge.BackgroundColor3 = Color3.fromRGB(77, 126, 164)
		hereBadge.BorderSizePixel = 0
		hereBadge.Text = "Here"
		hereBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
		hereBadge.TextSize = 12
		hereBadge.Font = Enum.Font.GothamBold
		hereBadge.Parent = row

		createCorner(hereBadge, 5)
	else
		local rowGoButton = createTextButton("RowGoButton", "Go", UDim2.fromOffset(58, 28), row)
		rowGoButton.AnchorPoint = Vector2.new(1, 1)
		rowGoButton.Position = UDim2.new(1, -14, 1, -10)
		rowGoButton.BackgroundColor3 = Color3.fromRGB(68, 143, 82)
		rowGoButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		rowGoButton.TextSize = 13

		rowGoButton.MouseButton1Click:Connect(function()
			selectRoom(publicRoomData, row)
			joinSelectedRoom()
		end)
	end

	row.MouseButton1Click:Connect(function()
		selectRoom(publicRoomData, row)
	end)

	if selectedRoomData and selectedRoomData.RoomKey == publicRoomData.RoomKey then
		selectedRow = row
		setRowSelected(row, true)
	end
end

local function createPublicCategoryPlaceholderRow(categoryName, order)
	local row = Instance.new("Frame")
	row.Name = tostring(categoryName)
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -4, 0, 62)
	row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	row.BorderSizePixel = 0
	row.Parent = listFrame

	createCorner(row, 8)
	createStroke(row, Color3.fromRGB(220, 226, 218), 1, 0)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Position = UDim2.fromOffset(14, 8)
	nameLabel.Size = UDim2.new(1, -140, 0, 22)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = tostring(categoryName)
	nameLabel.TextColor3 = Color3.fromRGB(45, 50, 45)
	nameLabel.TextSize = 16
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = row

	local noteLabel = Instance.new("TextLabel")
	noteLabel.Name = "NoteLabel"
	noteLabel.Position = UDim2.fromOffset(14, 32)
	noteLabel.Size = UDim2.new(1, -140, 0, 18)
	noteLabel.BackgroundTransparency = 1
	noteLabel.Text = "Developer public spaces coming soon."
	noteLabel.TextColor3 = Color3.fromRGB(95, 100, 95)
	noteLabel.TextSize = 12
	noteLabel.TextXAlignment = Enum.TextXAlignment.Left
	noteLabel.Font = Enum.Font.Gotham
	noteLabel.Parent = row

	local soonBadge = Instance.new("TextLabel")
	soonBadge.Name = "SoonBadge"
	soonBadge.AnchorPoint = Vector2.new(1, 0.5)
	soonBadge.Position = UDim2.new(1, -14, 0.5, 0)
	soonBadge.Size = UDim2.fromOffset(104, 28)
	soonBadge.BackgroundColor3 = Color3.fromRGB(205, 210, 205)
	soonBadge.BorderSizePixel = 0
	soonBadge.Text = "Coming soon"
	soonBadge.TextColor3 = Color3.fromRGB(78, 82, 78)
	soonBadge.TextSize = 12
	soonBadge.Font = Enum.Font.GothamBold
	soonBadge.Parent = row

	createCorner(soonBadge, 6)
end

local function createRoomRow(roomData, order)
	local row = Instance.new("TextButton")
	row.Name = tostring(roomData.RoomName or roomData.RoomKey or "Room")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -4, 0, 72)
	row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	row.BorderSizePixel = 0
	row.Text = ""
	row.AutoButtonColor = true
	row.Parent = listFrame

	createCorner(row, 8)

	local stroke = createStroke(row, Color3.fromRGB(213, 220, 210), 1, 0)
	stroke.Name = "RowStroke"

	local roomNameLabel = Instance.new("TextLabel")
	roomNameLabel.Name = "RoomName"
	roomNameLabel.Position = UDim2.fromOffset(14, 8)
	roomNameLabel.Size = UDim2.new(1, -170, 0, 22)
	roomNameLabel.BackgroundTransparency = 1
	roomNameLabel.Text = getRoomDisplayName(roomData)
	roomNameLabel.TextColor3 = Color3.fromRGB(38, 44, 38)
	roomNameLabel.TextSize = 16
	roomNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	roomNameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	roomNameLabel.Font = Enum.Font.GothamBold
	roomNameLabel.Parent = row

	local ownerLabel = Instance.new("TextLabel")
	ownerLabel.Name = "Owner"
	ownerLabel.Position = UDim2.fromOffset(14, 32)
	ownerLabel.Size = UDim2.new(1, -170, 0, 18)
	ownerLabel.BackgroundTransparency = 1
	ownerLabel.Text = "Owner: " .. getRoomOwnerText(roomData)
	ownerLabel.TextColor3 = Color3.fromRGB(82, 88, 82)
	ownerLabel.TextSize = 12
	ownerLabel.TextXAlignment = Enum.TextXAlignment.Left
	ownerLabel.TextTruncate = Enum.TextTruncate.AtEnd
	ownerLabel.Font = Enum.Font.Gotham
	ownerLabel.Parent = row

	local categoryLabel = Instance.new("TextLabel")
	categoryLabel.Name = "Category"
	categoryLabel.Position = UDim2.fromOffset(14, 52)
	categoryLabel.Size = UDim2.new(1, -170, 0, 16)
	categoryLabel.BackgroundTransparency = 1
	categoryLabel.Text = tostring(roomData.Category or "Guest Rooms")
	categoryLabel.TextColor3 = Color3.fromRGB(102, 108, 102)
	categoryLabel.TextSize = 11
	categoryLabel.TextXAlignment = Enum.TextXAlignment.Left
	categoryLabel.TextTruncate = Enum.TextTruncate.AtEnd
	categoryLabel.Font = Enum.Font.GothamMedium
	categoryLabel.Parent = row

	local occupancyLabel = Instance.new("TextLabel")
	occupancyLabel.Name = "Occupancy"
	occupancyLabel.AnchorPoint = Vector2.new(1, 0)
	occupancyLabel.Position = UDim2.new(1, -84, 0, 11)
	occupancyLabel.Size = UDim2.fromOffset(70, 20)
	occupancyLabel.BackgroundTransparency = 1
	occupancyLabel.Text = getOccupancyText(roomData)
	occupancyLabel.TextColor3 = Color3.fromRGB(60, 90, 70)
	occupancyLabel.TextSize = 14
	occupancyLabel.TextXAlignment = Enum.TextXAlignment.Right
	occupancyLabel.Font = Enum.Font.GothamBold
	occupancyLabel.Parent = row

	if isEntryCurrentRoom(roomData) then
		local hereBadge = Instance.new("TextLabel")
		hereBadge.Name = "HereBadge"
		hereBadge.AnchorPoint = Vector2.new(1, 1)
		hereBadge.Position = UDim2.new(1, -14, 1, -10)
		hereBadge.Size = UDim2.fromOffset(58, 28)
		hereBadge.BackgroundColor3 = Color3.fromRGB(77, 126, 164)
		hereBadge.BorderSizePixel = 0
		hereBadge.Text = "Here"
		hereBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
		hereBadge.TextSize = 12
		hereBadge.Font = Enum.Font.GothamBold
		hereBadge.Parent = row

		createCorner(hereBadge, 5)
	else
		local rowGoButton = createTextButton("RowGoButton", "Go", UDim2.fromOffset(58, 28), row)
		rowGoButton.AnchorPoint = Vector2.new(1, 1)
		rowGoButton.Position = UDim2.new(1, -14, 1, -10)
		rowGoButton.BackgroundColor3 = Color3.fromRGB(68, 143, 82)
		rowGoButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		rowGoButton.TextSize = 13

		rowGoButton.MouseButton1Click:Connect(function()
			selectRoom(roomData, row)
			joinSelectedRoom()
		end)
	end

	row.MouseButton1Click:Connect(function()
		selectRoom(roomData, row)
	end)

	if selectedRoomData and selectedRoomData.RoomKey == roomData.RoomKey then
		selectedRow = row
		setRowSelected(row, true)
	end

	return row
end

local function filterRoomsByCategory(categoryName)
	local rooms = {}

	for _, roomData in ipairs(latestRoomList) do
		local category = roomData.Category or "Chat Rooms"

		if category == categoryName then
			table.insert(rooms, roomData)
		end
	end

	return rooms
end

local function filterOwnRooms()
	local rooms = {}

	for _, roomData in ipairs(latestRoomList) do
		if roomData.IsOwner == true then
			table.insert(rooms, roomData)
		end
	end

	return rooms
end

local function filterSearchRooms()
	local query = string.lower(searchQuery or "")
	local rooms = {}

	for _, roomData in ipairs(latestRoomList) do
		local displayName = string.lower(getRoomDisplayName(roomData))
		local ownerName = string.lower(tostring(roomData.OwnerName or ""))
		local ownerDisplayName = string.lower(tostring(roomData.OwnerDisplayName or ""))

		if query == ""
			or string.find(displayName, query, 1, true)
			or string.find(ownerName, query, 1, true)
			or string.find(ownerDisplayName, query, 1, true) then

			table.insert(rooms, roomData)
		end
	end

	return rooms
end

local function renderRoomRows(rooms, emptyMessage)
	if #rooms == 0 then
		createEmptyState(emptyMessage)
		return
	end

	for index, roomData in ipairs(rooms) do
		createRoomRow(roomData, index)
	end
end

local function renderPublicSpaces()
	sectionTitle.Text = "Public Spaces"
	searchBox.Visible = false
	categoryBar.Visible = false
	listFrame.Position = UDim2.fromOffset(14, 44)
	listFrame.Size = UDim2.new(1, -28, 1, -58)

	if #publicRooms > 0 then
		for index, publicRoomData in ipairs(publicRooms) do
			createPublicSpaceRow(publicRoomData, index)
		end
	elseif #publicCategories > 0 then
		for index, categoryName in ipairs(publicCategories) do
			createPublicCategoryPlaceholderRow(categoryName, index)
		end
	else
		createEmptyState("Public spaces are coming soon.")
	end
end

local function renderRooms()
	listFrame.Size = UDim2.new(1, -28, 1, -98)
	searchBox.Visible = selectedRoomSubtab == ROOM_SUBTAB_SEARCH
	categoryBar.Visible = selectedRoomSubtab == ROOM_SUBTAB_GUEST

	if selectedRoomSubtab == ROOM_SUBTAB_SEARCH then
		sectionTitle.Text = "Search Rooms"
		listFrame.Position = UDim2.fromOffset(14, 84)
		renderRoomRows(filterSearchRooms(), "No active rooms match your search.")
	elseif selectedRoomSubtab == ROOM_SUBTAB_OWN then
		sectionTitle.Text = "Own Room(s)"
		listFrame.Position = UDim2.fromOffset(14, 44)
		listFrame.Size = UDim2.new(1, -28, 1, -58)
		renderRoomRows(filterOwnRooms(), "You do not have an active room yet.")
	elseif selectedRoomSubtab == ROOM_SUBTAB_FAVOURITES then
		sectionTitle.Text = "Favourites"
		listFrame.Position = UDim2.fromOffset(14, 44)
		listFrame.Size = UDim2.new(1, -28, 1, -58)
		selectedRoomData = nil
		selectedRow = nil
		updateDetailPanel()
		createEmptyState("Favourites coming soon.")
	else
		sectionTitle.Text = "Guest Rooms"
		listFrame.Position = UDim2.fromOffset(14, 84)
		renderRoomRows(
			filterRoomsByCategory(selectedGuestCategory),
			"No active rooms in this category."
		)
	end
end

local function buildCategoryButtons()
	for _, child in ipairs(categoryBar:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	categoryButtons = {}

	for _, categoryName in ipairs(GUEST_ROOM_CATEGORIES) do
		local button = createTextButton(
			"Category_" .. categoryName:gsub("%W", ""),
			categoryName,
			UDim2.fromOffset(categoryName == "Gaming & Race Rooms" and 150 or 112, 32),
			categoryBar
		)
		button.TextSize = 12
		categoryButtons[categoryName] = button

		button.MouseButton1Click:Connect(function()
			selectedGuestCategory = categoryName
			selectedRoomData = nil
			selectedRow = nil

			if renderNavigator then
				renderNavigator()
			end
		end)
	end
end

renderNavigator = function()
	updateNavigationState()
	clearList()

	if selectedTopTab == TOP_TAB_PUBLIC then
		renderPublicSpaces()
	else
		renderRooms()
	end

	updateCanvasSize()
	updateDetailPanel()
end

buildCategoryButtons()

publicSpacesTab.MouseButton1Click:Connect(function()
	selectedTopTab = TOP_TAB_PUBLIC
	selectedRoomData = nil
	selectedRow = nil
	renderNavigator()
end)

roomsTab.MouseButton1Click:Connect(function()
	selectedTopTab = TOP_TAB_ROOMS
	selectedRoomData = nil
	selectedRow = nil
	renderNavigator()
end)

searchSubtabButton.MouseButton1Click:Connect(function()
	selectedRoomSubtab = ROOM_SUBTAB_SEARCH
	selectedRoomData = nil
	selectedRow = nil
	renderNavigator()
end)

ownSubtabButton.MouseButton1Click:Connect(function()
	selectedRoomSubtab = ROOM_SUBTAB_OWN
	selectedRoomData = nil
	selectedRow = nil
	renderNavigator()
end)

favouritesSubtabButton.MouseButton1Click:Connect(function()
	selectedRoomSubtab = ROOM_SUBTAB_FAVOURITES
	selectedRoomData = nil
	selectedRow = nil
	renderNavigator()
end)

guestSubtabButton.MouseButton1Click:Connect(function()
	selectedRoomSubtab = ROOM_SUBTAB_GUEST
	selectedRoomData = nil
	selectedRow = nil
	renderNavigator()
end)

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	searchQuery = searchBox.Text

	if selectedTopTab == TOP_TAB_ROOMS and selectedRoomSubtab == ROOM_SUBTAB_SEARCH then
		renderNavigator()
	end
end)

goButton.MouseButton1Click:Connect(joinSelectedRoom)

favouriteButton.MouseButton1Click:Connect(function()
	statusLabel.Text = "Favourites are coming soon."
end)

openButton.MouseButton1Click:Connect(function()
	setPanelVisible(true)
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

roomListUpdate.OnClientEvent:Connect(function(roomList, currentRoomName)
	latestRoomList = typeof(roomList) == "table" and roomList or {}
	latestCurrentRoomName = currentRoomName

	if panel.Visible then
		renderNavigator()
	end

	updateOpenButton()
end)

joinRoomResult.OnClientEvent:Connect(function(success, message)
	if success then
		statusLabel.Text = message or "Joined room."
		setPanelVisible(false)
	else
		statusLabel.Text = message or "Could not join room."
		updateDetailPanel()
	end

	roomListRequest:FireServer()
end)

roomCreationResult.OnClientEvent:Connect(function(status)
	if status == "Created"
		or status == "ShowCharacterCreation"
		or status == "ShowCreation" then

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

player:GetAttributeChangedSignal("CurrentRoomName"):Connect(function()
	latestCurrentRoomName = player:GetAttribute("CurrentRoomName")

	if panel.Visible and renderNavigator then
		renderNavigator()
	else
		updateDetailPanel()
	end
end)

renderNavigator()
updateOpenButton()
