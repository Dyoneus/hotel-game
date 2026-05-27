-- Explorer/StarterGui/RoomNavigatorGui/RoomNavigatorClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

print("[RoomNavigatorClient] Started")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local roomListRequest = remoteEvents:WaitForChild("RoomListRequest")
local roomListUpdate = remoteEvents:WaitForChild("RoomListUpdate")
local joinRoomRequest = remoteEvents:WaitForChild("JoinRoomRequest")
local joinRoomResult = remoteEvents:WaitForChild("JoinRoomResult")

local missingOptionalRemoteWarnings = {}
local optionalRemoteConnections = {}

local function getOptionalRemoteEvent(name)
	local remote = remoteEvents:FindFirstChild(name)

	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	if not missingOptionalRemoteWarnings[name] then
		missingOptionalRemoteWarnings[name] = true
		warn("[RoomNavigatorClient] Missing optional permission remote:", name)
	end

	return nil
end

local function connectOptionalRemoteEvent(name, handler)
	local function connect(remote)
		if optionalRemoteConnections[name] or not remote or not remote:IsA("RemoteEvent") then
			return
		end

		optionalRemoteConnections[name] = remote.OnClientEvent:Connect(handler)
	end

	connect(getOptionalRemoteEvent(name))

	remoteEvents.ChildAdded:Connect(function(child)
		if child.Name == name then
			connect(child)
		end
	end)
end

local roomCreationResult = getOptionalRemoteEvent("RoomCreationResult")
local roomSettingsRequest = getOptionalRemoteEvent("RoomSettingsRequest")
local roomSettingsResult = getOptionalRemoteEvent("RoomSettingsResult")
local roomNavigatorRequest = getOptionalRemoteEvent("RoomNavigatorRequest")
local roomNavigatorResult = getOptionalRemoteEvent("RoomNavigatorResult")

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
local ROOM_NAME_MAX_LENGTH = 30
local ROOM_DESCRIPTION_MAX_LENGTH = 100
local ROOM_JOIN_FADE_OUT_SECONDS = 0.28
local CONTENT_TOP_OFFSET = 124
local DETAIL_BOTTOM_OFFSET = 18
local DETAIL_GAP = 8
local DETAIL_HEIGHT_EMPTY = 96
local DETAIL_HEIGHT_SELECTED = 146
local DETAIL_HEIGHT_SETTINGS = 420
local ROOM_EDITOR_USER_ID_MAX_LENGTH = 20

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 180

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
local favouriteKeysByRoomKey = {}
local favouriteEntries = {}
local favouritesRequestInFlight = false
local favouritesLoaded = false
local pendingFavouriteToggleByRoomKey = {}
local searchQuery = ""
local selectedSettingsCategory = "Chat Rooms"
local selectedSettingsIsPublic = true
local roomSettingsRequestInFlight = false
local roomEditorsRequestInFlight = false
local roomEditorMutationInFlight = false
local roomEditorsUnavailable = false
local currentRoomEditors = {}
local joinRoomRequestInFlight = false
local joinRoomRequestToken = 0
local suppressSettingsTextChanged = false
local statusShakeTween = nil

local function refreshOptionalRemote(name, currentRemote)
	if currentRemote and currentRemote.Parent == remoteEvents and currentRemote:IsA("RemoteEvent") then
		return currentRemote
	end

	return getOptionalRemoteEvent(name)
end

local function getRoomSettingsRequestRemote()
	roomSettingsRequest = refreshOptionalRemote("RoomSettingsRequest", roomSettingsRequest)
	return roomSettingsRequest
end

local function getRoomSettingsResultRemote()
	roomSettingsResult = refreshOptionalRemote("RoomSettingsResult", roomSettingsResult)
	return roomSettingsResult
end

local function getRoomNavigatorRequestRemote()
	roomNavigatorRequest = refreshOptionalRemote("RoomNavigatorRequest", roomNavigatorRequest)
	return roomNavigatorRequest
end

local function getRoomNavigatorResultRemote()
	roomNavigatorResult = refreshOptionalRemote("RoomNavigatorResult", roomNavigatorResult)
	return roomNavigatorResult
end

local function areRoomSettingsRemotesAvailable()
	return getRoomSettingsRequestRemote() ~= nil and getRoomSettingsResultRemote() ~= nil
end

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
local roomTransitionRequest = getOrCreateClientEvent("RoomTransitionRequest")
local openRoomNavigator = getOrCreateClientEvent("OpenRoomNavigator")

local MENU_NAME = "Rooms"
local anyMajorMenuOpen = false
local openMajorMenuName = nil
local ui = {}

ui.openButton = Instance.new("TextButton")
ui.openButton.Name = "OpenRoomsButton"
ui.openButton.AnchorPoint = Vector2.new(0, 1)
ui.openButton.Position = UDim2.new(0, 18, 1, -18)
ui.openButton.Size = UDim2.fromOffset(130, 42)
ui.openButton.BackgroundColor3 = Color3.fromRGB(35, 45, 60)
ui.openButton.BorderSizePixel = 0
ui.openButton.Text = "Rooms"
ui.openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ui.openButton.TextSize = 20
ui.openButton.Font = Enum.Font.GothamBold
ui.openButton.Visible = false
ui.openButton.Parent = gui

createCorner(ui.openButton, 10)
print("[RoomNavigatorClient] Open button ready")

ui.panel = Instance.new("Frame")
ui.panel.Name = "HotelNavigatorPanel"
ui.panel.AnchorPoint = Vector2.new(0.5, 0.5)
ui.panel.Position = UDim2.fromScale(0.5, 0.5)
ui.panel.Size = UDim2.new(0.88, 0, 0.82, 0)
ui.panel.BackgroundColor3 = Color3.fromRGB(238, 240, 232)
ui.panel.BorderSizePixel = 0
ui.panel.Visible = false
ui.panel.Parent = gui

ui.panelSize = Instance.new("UISizeConstraint")
ui.panelSize.MaxSize = Vector2.new(920, 680)
ui.panelSize.MinSize = Vector2.new(360, 360)
ui.panelSize.Parent = ui.panel

createCorner(ui.panel, 10)
createStroke(ui.panel, Color3.fromRGB(180, 188, 176), 1, 0)

local PANEL_LAYOUT_NORMAL = "Normal"
local PANEL_LAYOUT_MAIN_MENU_DOCKED = "MainMenuDocked"
local currentPanelLayout = PANEL_LAYOUT_NORMAL

local function applyPanelLayout(layoutMode)
	currentPanelLayout = layoutMode == PANEL_LAYOUT_MAIN_MENU_DOCKED
		and PANEL_LAYOUT_MAIN_MENU_DOCKED
		or PANEL_LAYOUT_NORMAL

	if currentPanelLayout == PANEL_LAYOUT_MAIN_MENU_DOCKED then
		ui.panel.AnchorPoint = Vector2.new(1, 0.5)
		ui.panel.Position = UDim2.new(1, -24, 0.5, 0)
		ui.panel.Size = UDim2.new(0.48, 0, 0.82, 0)
		ui.panelSize.MaxSize = Vector2.new(620, 680)
		ui.panelSize.MinSize = Vector2.new(360, 360)
	else
		ui.panel.AnchorPoint = Vector2.new(0.5, 0.5)
		ui.panel.Position = UDim2.fromScale(0.5, 0.5)
		ui.panel.Size = UDim2.new(0.88, 0, 0.82, 0)
		ui.panelSize.MaxSize = Vector2.new(920, 680)
		ui.panelSize.MinSize = Vector2.new(360, 360)
	end
end

ui.titleBar = Instance.new("Frame")
ui.titleBar.Name = "TitleBar"
ui.titleBar.Size = UDim2.new(1, 0, 0, 58)
ui.titleBar.BackgroundColor3 = Color3.fromRGB(42, 67, 83)
ui.titleBar.BorderSizePixel = 0
ui.titleBar.Parent = ui.panel

createCorner(ui.titleBar, 10)

ui.titleCover = Instance.new("Frame")
ui.titleCover.Name = "TitleCover"
ui.titleCover.AnchorPoint = Vector2.new(0, 1)
ui.titleCover.Position = UDim2.new(0, 0, 1, 0)
ui.titleCover.Size = UDim2.new(1, 0, 0, 10)
ui.titleCover.BackgroundColor3 = ui.titleBar.BackgroundColor3
ui.titleCover.BorderSizePixel = 0
ui.titleCover.Parent = ui.titleBar

ui.titleLabel = Instance.new("TextLabel")
ui.titleLabel.Name = "TitleLabel"
ui.titleLabel.Position = UDim2.fromOffset(20, 12)
ui.titleLabel.Size = UDim2.new(1, -82, 0, 34)
ui.titleLabel.BackgroundTransparency = 1
ui.titleLabel.Text = "Hotel Navigator"
ui.titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
ui.titleLabel.TextSize = 24
ui.titleLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.titleLabel.Font = Enum.Font.GothamBold
ui.titleLabel.Parent = ui.titleBar

ui.closeButton = Instance.new("TextButton")
ui.closeButton.Name = "CloseButton"
ui.closeButton.AnchorPoint = Vector2.new(1, 0)
ui.closeButton.Position = UDim2.new(1, -16, 0, 14)
ui.closeButton.Size = UDim2.fromOffset(32, 30)
ui.closeButton.BackgroundColor3 = Color3.fromRGB(224, 230, 222)
ui.closeButton.BorderSizePixel = 0
ui.closeButton.Text = "X"
ui.closeButton.TextColor3 = Color3.fromRGB(45, 48, 45)
ui.closeButton.TextSize = 14
ui.closeButton.Font = Enum.Font.GothamBold
ui.closeButton.Parent = ui.titleBar

createCorner(ui.closeButton, 6)

ui.topTabsFrame = Instance.new("Frame")
ui.topTabsFrame.Name = "TopTabs"
ui.topTabsFrame.Position = UDim2.fromOffset(18, 70)
ui.topTabsFrame.Size = UDim2.new(1, -36, 0, 42)
ui.topTabsFrame.BackgroundTransparency = 1
ui.topTabsFrame.Parent = ui.panel

ui.topTabsLayout = Instance.new("UIListLayout")
ui.topTabsLayout.FillDirection = Enum.FillDirection.Horizontal
ui.topTabsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
ui.topTabsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
ui.topTabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
ui.topTabsLayout.Padding = UDim.new(0, 8)
ui.topTabsLayout.Parent = ui.topTabsFrame

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

ui.publicSpacesTab = createTextButton(
	"PublicSpacesTab",
	"Public Spaces",
	UDim2.fromOffset(150, 38),
	ui.topTabsFrame
)

ui.roomsTab = createTextButton(
	"RoomsTab",
	"Rooms",
	UDim2.fromOffset(120, 38),
	ui.topTabsFrame
)

ui.roomsNav = Instance.new("ScrollingFrame")
ui.roomsNav.Name = "RoomsNavigation"
ui.roomsNav.Position = UDim2.fromOffset(18, 124)
ui.roomsNav.Size = UDim2.new(0, 150, 1, -426)
ui.roomsNav.BackgroundColor3 = Color3.fromRGB(229, 232, 224)
ui.roomsNav.BorderSizePixel = 0
ui.roomsNav.CanvasSize = UDim2.fromOffset(0, 0)
ui.roomsNav.ScrollBarThickness = 5
ui.roomsNav.ScrollingDirection = Enum.ScrollingDirection.Y
ui.roomsNav.Parent = ui.panel

createCorner(ui.roomsNav, 8)
createStroke(ui.roomsNav, Color3.fromRGB(205, 212, 200), 1, 0)

ui.roomsNavLayout = Instance.new("UIListLayout")
ui.roomsNavLayout.SortOrder = Enum.SortOrder.LayoutOrder
ui.roomsNavLayout.Padding = UDim.new(0, 6)
ui.roomsNavLayout.Parent = ui.roomsNav

ui.roomsNavPadding = Instance.new("UIPadding")
ui.roomsNavPadding.PaddingTop = UDim.new(0, 10)
ui.roomsNavPadding.PaddingLeft = UDim.new(0, 10)
ui.roomsNavPadding.PaddingRight = UDim.new(0, 10)
ui.roomsNavPadding.Parent = ui.roomsNav

ui.searchSubtabButton = createTextButton("SearchSubtab", "Search", UDim2.new(1, 0, 0, 34), ui.roomsNav)
ui.ownSubtabButton = createTextButton("OwnRoomsSubtab", "Own Room(s)", UDim2.new(1, 0, 0, 34), ui.roomsNav)
ui.favouritesSubtabButton = createTextButton("FavouritesSubtab", "Favourites", UDim2.new(1, 0, 0, 34), ui.roomsNav)
ui.guestSubtabButton = createTextButton("GuestRoomsSubtab", "Guest Rooms", UDim2.new(1, 0, 0, 34), ui.roomsNav)

ui.contentFrame = Instance.new("Frame")
ui.contentFrame.Name = "ContentFrame"
ui.contentFrame.Position = UDim2.fromOffset(180, 124)
ui.contentFrame.Size = UDim2.new(1, -198, 1, -426)
ui.contentFrame.BackgroundColor3 = Color3.fromRGB(249, 250, 247)
ui.contentFrame.BorderSizePixel = 0
ui.contentFrame.Parent = ui.panel

createCorner(ui.contentFrame, 8)
createStroke(ui.contentFrame, Color3.fromRGB(205, 212, 200), 1, 0)

ui.sectionTitle = Instance.new("TextLabel")
ui.sectionTitle.Name = "SectionTitle"
ui.sectionTitle.Position = UDim2.fromOffset(14, 8)
ui.sectionTitle.Size = UDim2.new(1, -28, 0, 24)
ui.sectionTitle.BackgroundTransparency = 1
ui.sectionTitle.Text = ""
ui.sectionTitle.TextColor3 = Color3.fromRGB(48, 54, 48)
ui.sectionTitle.TextSize = 17
ui.sectionTitle.TextXAlignment = Enum.TextXAlignment.Left
ui.sectionTitle.Font = Enum.Font.GothamBold
ui.sectionTitle.Parent = ui.contentFrame

ui.searchBox = Instance.new("TextBox")
ui.searchBox.Name = "SearchBox"
ui.searchBox.Position = UDim2.fromOffset(14, 40)
ui.searchBox.Size = UDim2.new(1, -28, 0, 34)
ui.searchBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
ui.searchBox.BorderSizePixel = 0
ui.searchBox.PlaceholderText = "Search rooms or owners"
ui.searchBox.Text = ""
ui.searchBox.TextColor3 = Color3.fromRGB(40, 40, 40)
ui.searchBox.PlaceholderColor3 = Color3.fromRGB(130, 130, 130)
ui.searchBox.TextSize = 14
ui.searchBox.TextXAlignment = Enum.TextXAlignment.Left
ui.searchBox.Font = Enum.Font.Gotham
ui.searchBox.ClearTextOnFocus = false
ui.searchBox.Visible = false
ui.searchBox.Parent = ui.contentFrame

createCorner(ui.searchBox, 6)
createStroke(ui.searchBox, Color3.fromRGB(215, 220, 214), 1, 0)

ui.searchPadding = Instance.new("UIPadding")
ui.searchPadding.PaddingLeft = UDim.new(0, 10)
ui.searchPadding.PaddingRight = UDim.new(0, 10)
ui.searchPadding.Parent = ui.searchBox

ui.categoryBar = Instance.new("ScrollingFrame")
ui.categoryBar.Name = "GuestCategoryBar"
ui.categoryBar.Position = UDim2.fromOffset(14, 40)
ui.categoryBar.Size = UDim2.new(1, -28, 0, 38)
ui.categoryBar.BackgroundTransparency = 1
ui.categoryBar.BorderSizePixel = 0
ui.categoryBar.CanvasSize = UDim2.fromOffset(0, 0)
ui.categoryBar.ScrollBarThickness = 4
ui.categoryBar.ScrollingDirection = Enum.ScrollingDirection.X
ui.categoryBar.Visible = false
ui.categoryBar.Parent = ui.contentFrame

ui.categoryLayout = Instance.new("UIListLayout")
ui.categoryLayout.FillDirection = Enum.FillDirection.Horizontal
ui.categoryLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
ui.categoryLayout.VerticalAlignment = Enum.VerticalAlignment.Center
ui.categoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
ui.categoryLayout.Padding = UDim.new(0, 6)
ui.categoryLayout.Parent = ui.categoryBar

ui.listFrame = Instance.new("ScrollingFrame")
ui.listFrame.Name = "NavigatorList"
ui.listFrame.Position = UDim2.fromOffset(14, 84)
ui.listFrame.Size = UDim2.new(1, -28, 1, -98)
ui.listFrame.BackgroundTransparency = 1
ui.listFrame.BorderSizePixel = 0
ui.listFrame.ScrollBarThickness = 6
ui.listFrame.CanvasSize = UDim2.fromOffset(0, 0)
ui.listFrame.Parent = ui.contentFrame

ui.listLayout = Instance.new("UIListLayout")
ui.listLayout.SortOrder = Enum.SortOrder.LayoutOrder
ui.listLayout.Padding = UDim.new(0, 8)
ui.listLayout.Parent = ui.listFrame

ui.detailPanel = Instance.new("ScrollingFrame")
ui.detailPanel.Name = "SelectedRoomDetails"
ui.detailPanel.AnchorPoint = Vector2.new(0, 1)
ui.detailPanel.Position = UDim2.new(0, 18, 1, -18)
ui.detailPanel.Size = UDim2.new(1, -36, 0, 276)
ui.detailPanel.BackgroundColor3 = Color3.fromRGB(224, 230, 220)
ui.detailPanel.BorderSizePixel = 0
ui.detailPanel.CanvasSize = UDim2.fromOffset(0, 0)
ui.detailPanel.ScrollBarThickness = 5
ui.detailPanel.ScrollingDirection = Enum.ScrollingDirection.Y
ui.detailPanel.Parent = ui.panel

createCorner(ui.detailPanel, 8)
createStroke(ui.detailPanel, Color3.fromRGB(190, 200, 186), 1, 0)

ui.detailTitle = Instance.new("TextLabel")
ui.detailTitle.Name = "DetailTitle"
ui.detailTitle.Position = UDim2.fromOffset(14, 10)
ui.detailTitle.Size = UDim2.new(1, -260, 0, 24)
ui.detailTitle.BackgroundTransparency = 1
ui.detailTitle.Text = "Select a room"
ui.detailTitle.TextColor3 = Color3.fromRGB(42, 48, 42)
ui.detailTitle.TextSize = 17
ui.detailTitle.TextXAlignment = Enum.TextXAlignment.Left
ui.detailTitle.TextTruncate = Enum.TextTruncate.AtEnd
ui.detailTitle.Font = Enum.Font.GothamBold
ui.detailTitle.Parent = ui.detailPanel

ui.detailOwner = Instance.new("TextLabel")
ui.detailOwner.Name = "DetailOwner"
ui.detailOwner.Position = UDim2.fromOffset(14, 38)
ui.detailOwner.Size = UDim2.new(1, -260, 0, 20)
ui.detailOwner.BackgroundTransparency = 1
ui.detailOwner.Text = "Owner: -"
ui.detailOwner.TextColor3 = Color3.fromRGB(82, 88, 82)
ui.detailOwner.TextSize = 13
ui.detailOwner.TextXAlignment = Enum.TextXAlignment.Left
ui.detailOwner.TextTruncate = Enum.TextTruncate.AtEnd
ui.detailOwner.Font = Enum.Font.Gotham
ui.detailOwner.Parent = ui.detailPanel

ui.detailMeta = Instance.new("TextLabel")
ui.detailMeta.Name = "DetailMeta"
ui.detailMeta.Position = UDim2.fromOffset(14, 62)
ui.detailMeta.Size = UDim2.new(1, -260, 0, 20)
ui.detailMeta.BackgroundTransparency = 1
ui.detailMeta.Text = "Occupancy: -"
ui.detailMeta.TextColor3 = Color3.fromRGB(82, 88, 82)
ui.detailMeta.TextSize = 13
ui.detailMeta.TextXAlignment = Enum.TextXAlignment.Left
ui.detailMeta.TextTruncate = Enum.TextTruncate.AtEnd
ui.detailMeta.Font = Enum.Font.Gotham
ui.detailMeta.Parent = ui.detailPanel

ui.detailDescription = Instance.new("TextLabel")
ui.detailDescription.Name = "DetailDescription"
ui.detailDescription.Position = UDim2.fromOffset(14, 84)
ui.detailDescription.Size = UDim2.new(1, -260, 0, 18)
ui.detailDescription.BackgroundTransparency = 1
ui.detailDescription.Text = ""
ui.detailDescription.TextColor3 = Color3.fromRGB(82, 88, 82)
ui.detailDescription.TextSize = 12
ui.detailDescription.TextXAlignment = Enum.TextXAlignment.Left
ui.detailDescription.TextTruncate = Enum.TextTruncate.AtEnd
ui.detailDescription.Font = Enum.Font.Gotham
ui.detailDescription.Parent = ui.detailPanel

ui.detailStatus = Instance.new("TextLabel")
ui.detailStatus.Name = "DetailStatus"
ui.detailStatus.Position = UDim2.fromOffset(14, 376)
ui.detailStatus.Size = UDim2.new(1, -260, 0, 18)
ui.detailStatus.BackgroundTransparency = 1
ui.detailStatus.Text = ""
ui.detailStatus.TextColor3 = Color3.fromRGB(105, 90, 55)
ui.detailStatus.TextSize = 12
ui.detailStatus.TextXAlignment = Enum.TextXAlignment.Left
ui.detailStatus.Font = Enum.Font.GothamMedium
ui.detailStatus.Parent = ui.detailPanel

ui.favouriteButton = createTextButton(
	"FavouriteButton",
	"Add to Favourites",
	UDim2.fromOffset(130, 36),
	ui.detailPanel
)
ui.favouriteButton.AnchorPoint = Vector2.new(1, 0)
ui.favouriteButton.Position = UDim2.new(1, -144, 0, 40)
ui.favouriteButton.BackgroundColor3 = Color3.fromRGB(180, 185, 180)
ui.favouriteButton.TextColor3 = Color3.fromRGB(245, 245, 245)
ui.favouriteButton.Active = false
ui.favouriteButton.AutoButtonColor = false

ui.goButton = createTextButton("GoButton", "Go", UDim2.fromOffset(108, 36), ui.detailPanel)
ui.goButton.AnchorPoint = Vector2.new(1, 0)
ui.goButton.Position = UDim2.new(1, -20, 0, 40)
ui.goButton.BackgroundColor3 = Color3.fromRGB(110, 115, 110)
ui.goButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ui.goButton.Active = false
ui.goButton.AutoButtonColor = false

ui.statusLabel = Instance.new("TextLabel")
ui.statusLabel.Name = "StatusLabel"
ui.statusLabel.AnchorPoint = Vector2.new(1, 0)
ui.statusLabel.Position = UDim2.new(1, -20, 0, 366)
ui.statusLabel.Size = UDim2.fromOffset(300, 28)
ui.statusLabel.BackgroundTransparency = 1
ui.statusLabel.Text = ""
ui.statusLabel.TextColor3 = Color3.fromRGB(90, 90, 90)
ui.statusLabel.TextSize = 12
ui.statusLabel.TextXAlignment = Enum.TextXAlignment.Right
ui.statusLabel.TextWrapped = true
ui.statusLabel.Font = Enum.Font.Gotham
ui.statusLabel.Parent = ui.detailPanel

ui.settingsFrame = Instance.new("Frame")
ui.settingsFrame.Name = "RoomSettingsEditor"
ui.settingsFrame.Position = UDim2.fromOffset(14, 108)
ui.settingsFrame.Size = UDim2.new(1, -28, 0, 250)
ui.settingsFrame.BackgroundTransparency = 1
ui.settingsFrame.Visible = false
ui.settingsFrame.Parent = ui.detailPanel

ui.settingsNameLabel = Instance.new("TextLabel")
ui.settingsNameLabel.Name = "RoomNameLabel"
ui.settingsNameLabel.Position = UDim2.fromOffset(0, 0)
ui.settingsNameLabel.Size = UDim2.new(0.38, -8, 0, 14)
ui.settingsNameLabel.BackgroundTransparency = 1
ui.settingsNameLabel.Text = "Room Name"
ui.settingsNameLabel.TextColor3 = Color3.fromRGB(72, 78, 72)
ui.settingsNameLabel.TextSize = 11
ui.settingsNameLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.settingsNameLabel.Font = Enum.Font.GothamBold
ui.settingsNameLabel.Parent = ui.settingsFrame

ui.settingsNameCounter = Instance.new("TextLabel")
ui.settingsNameCounter.Name = "RoomNameCounter"
ui.settingsNameCounter.AnchorPoint = Vector2.new(1, 0)
ui.settingsNameCounter.Position = UDim2.new(0.38, -8, 0, 0)
ui.settingsNameCounter.Size = UDim2.fromOffset(54, 14)
ui.settingsNameCounter.BackgroundTransparency = 1
ui.settingsNameCounter.Text = "0/30"
ui.settingsNameCounter.TextColor3 = Color3.fromRGB(82, 88, 82)
ui.settingsNameCounter.TextSize = 11
ui.settingsNameCounter.TextXAlignment = Enum.TextXAlignment.Right
ui.settingsNameCounter.Font = Enum.Font.GothamMedium
ui.settingsNameCounter.Parent = ui.settingsFrame

ui.settingsCategoryLabel = Instance.new("TextLabel")
ui.settingsCategoryLabel.Name = "CategoryLabel"
ui.settingsCategoryLabel.Position = UDim2.new(0.38, 0, 0, 0)
ui.settingsCategoryLabel.Size = UDim2.new(0.27, -8, 0, 14)
ui.settingsCategoryLabel.BackgroundTransparency = 1
ui.settingsCategoryLabel.Text = "Category"
ui.settingsCategoryLabel.TextColor3 = Color3.fromRGB(72, 78, 72)
ui.settingsCategoryLabel.TextSize = 11
ui.settingsCategoryLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.settingsCategoryLabel.Font = Enum.Font.GothamBold
ui.settingsCategoryLabel.Parent = ui.settingsFrame

ui.settingsVisibilityLabel = Instance.new("TextLabel")
ui.settingsVisibilityLabel.Name = "VisibilityLabel"
ui.settingsVisibilityLabel.Position = UDim2.new(0.65, 0, 0, 0)
ui.settingsVisibilityLabel.Size = UDim2.new(0.18, -8, 0, 14)
ui.settingsVisibilityLabel.BackgroundTransparency = 1
ui.settingsVisibilityLabel.Text = "Visibility"
ui.settingsVisibilityLabel.TextColor3 = Color3.fromRGB(72, 78, 72)
ui.settingsVisibilityLabel.TextSize = 11
ui.settingsVisibilityLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.settingsVisibilityLabel.Font = Enum.Font.GothamBold
ui.settingsVisibilityLabel.Parent = ui.settingsFrame

ui.settingsNameBox = Instance.new("TextBox")
ui.settingsNameBox.Name = "RoomNameBox"
ui.settingsNameBox.Position = UDim2.fromOffset(0, 16)
ui.settingsNameBox.Size = UDim2.new(0.38, -8, 0, 28)
ui.settingsNameBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
ui.settingsNameBox.BorderSizePixel = 0
ui.settingsNameBox.PlaceholderText = "Room name"
ui.settingsNameBox.Text = ""
ui.settingsNameBox.TextColor3 = Color3.fromRGB(42, 48, 42)
ui.settingsNameBox.PlaceholderColor3 = Color3.fromRGB(130, 135, 130)
ui.settingsNameBox.TextSize = 13
ui.settingsNameBox.TextXAlignment = Enum.TextXAlignment.Left
ui.settingsNameBox.Font = Enum.Font.Gotham
ui.settingsNameBox.ClearTextOnFocus = false
ui.settingsNameBox.ClipsDescendants = true
ui.settingsNameBox.TextTruncate = Enum.TextTruncate.AtEnd
ui.settingsNameBox.Parent = ui.settingsFrame

createCorner(ui.settingsNameBox, 5)
createStroke(ui.settingsNameBox, Color3.fromRGB(195, 204, 190), 1, 0)

ui.settingsNamePadding = Instance.new("UIPadding")
ui.settingsNamePadding.PaddingLeft = UDim.new(0, 8)
ui.settingsNamePadding.PaddingRight = UDim.new(0, 8)
ui.settingsNamePadding.Parent = ui.settingsNameBox

ui.settingsCategoryButton = createTextButton(
	"CategoryDropdownButton",
	"Category: Chat Rooms",
	UDim2.new(0.27, -8, 0, 28),
	ui.settingsFrame
)
ui.settingsCategoryButton.Position = UDim2.new(0.38, 0, 0, 16)
ui.settingsCategoryButton.TextSize = 12

ui.settingsPublicButton = createTextButton(
	"PublicToggleButton",
	"Public",
	UDim2.new(0.18, -8, 0, 28),
	ui.settingsFrame
)
ui.settingsPublicButton.Position = UDim2.new(0.65, 0, 0, 16)
ui.settingsPublicButton.TextSize = 12

ui.settingsSaveButton = createTextButton(
	"SaveRoomSettingsButton",
	"Save",
	UDim2.new(0.17, 0, 0, 28),
	ui.settingsFrame
)
ui.settingsSaveButton.Position = UDim2.new(0.83, 0, 0, 16)
ui.settingsSaveButton.BackgroundColor3 = Color3.fromRGB(68, 143, 82)
ui.settingsSaveButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ui.settingsSaveButton.TextSize = 13

ui.settingsDescriptionLabel = Instance.new("TextLabel")
ui.settingsDescriptionLabel.Name = "DescriptionLabel"
ui.settingsDescriptionLabel.Position = UDim2.fromOffset(0, 50)
ui.settingsDescriptionLabel.Size = UDim2.new(1, 0, 0, 14)
ui.settingsDescriptionLabel.BackgroundTransparency = 1
ui.settingsDescriptionLabel.Text = "Description"
ui.settingsDescriptionLabel.TextColor3 = Color3.fromRGB(72, 78, 72)
ui.settingsDescriptionLabel.TextSize = 11
ui.settingsDescriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.settingsDescriptionLabel.Font = Enum.Font.GothamBold
ui.settingsDescriptionLabel.Parent = ui.settingsFrame

ui.settingsDescriptionCounter = Instance.new("TextLabel")
ui.settingsDescriptionCounter.Name = "DescriptionCounter"
ui.settingsDescriptionCounter.AnchorPoint = Vector2.new(1, 0)
ui.settingsDescriptionCounter.Position = UDim2.new(1, 0, 0, 50)
ui.settingsDescriptionCounter.Size = UDim2.fromOffset(64, 14)
ui.settingsDescriptionCounter.BackgroundTransparency = 1
ui.settingsDescriptionCounter.Text = "0/100"
ui.settingsDescriptionCounter.TextColor3 = Color3.fromRGB(82, 88, 82)
ui.settingsDescriptionCounter.TextSize = 11
ui.settingsDescriptionCounter.TextXAlignment = Enum.TextXAlignment.Right
ui.settingsDescriptionCounter.Font = Enum.Font.GothamMedium
ui.settingsDescriptionCounter.Parent = ui.settingsFrame

ui.settingsDescriptionBox = Instance.new("TextBox")
ui.settingsDescriptionBox.Name = "DescriptionBox"
ui.settingsDescriptionBox.Position = UDim2.fromOffset(0, 66)
ui.settingsDescriptionBox.Size = UDim2.new(1, 0, 0, 56)
ui.settingsDescriptionBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
ui.settingsDescriptionBox.BorderSizePixel = 0
ui.settingsDescriptionBox.PlaceholderText = "Description"
ui.settingsDescriptionBox.Text = ""
ui.settingsDescriptionBox.TextColor3 = Color3.fromRGB(42, 48, 42)
ui.settingsDescriptionBox.PlaceholderColor3 = Color3.fromRGB(130, 135, 130)
ui.settingsDescriptionBox.TextSize = 13
ui.settingsDescriptionBox.TextXAlignment = Enum.TextXAlignment.Left
ui.settingsDescriptionBox.TextYAlignment = Enum.TextYAlignment.Top
ui.settingsDescriptionBox.Font = Enum.Font.Gotham
ui.settingsDescriptionBox.ClearTextOnFocus = false
ui.settingsDescriptionBox.ClipsDescendants = true
ui.settingsDescriptionBox.MultiLine = true
ui.settingsDescriptionBox.TextWrapped = true
ui.settingsDescriptionBox.Parent = ui.settingsFrame

createCorner(ui.settingsDescriptionBox, 5)
createStroke(ui.settingsDescriptionBox, Color3.fromRGB(195, 204, 190), 1, 0)

ui.settingsDescriptionPadding = Instance.new("UIPadding")
ui.settingsDescriptionPadding.PaddingLeft = UDim.new(0, 8)
ui.settingsDescriptionPadding.PaddingRight = UDim.new(0, 8)
ui.settingsDescriptionPadding.PaddingTop = UDim.new(0, 5)
ui.settingsDescriptionPadding.PaddingBottom = UDim.new(0, 5)
ui.settingsDescriptionPadding.Parent = ui.settingsDescriptionBox

ui.editorsLabel = Instance.new("TextLabel")
ui.editorsLabel.Name = "EditorsLabel"
ui.editorsLabel.Position = UDim2.fromOffset(0, 132)
ui.editorsLabel.Size = UDim2.new(1, 0, 0, 16)
ui.editorsLabel.BackgroundTransparency = 1
ui.editorsLabel.Text = "Editors"
ui.editorsLabel.TextColor3 = Color3.fromRGB(72, 78, 72)
ui.editorsLabel.TextSize = 11
ui.editorsLabel.TextXAlignment = Enum.TextXAlignment.Left
ui.editorsLabel.Font = Enum.Font.GothamBold
ui.editorsLabel.Parent = ui.settingsFrame

ui.editorUserIdBox = Instance.new("TextBox")
ui.editorUserIdBox.Name = "EditorUserIdBox"
ui.editorUserIdBox.Position = UDim2.fromOffset(0, 152)
ui.editorUserIdBox.Size = UDim2.new(1, -116, 0, 28)
ui.editorUserIdBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
ui.editorUserIdBox.BorderSizePixel = 0
ui.editorUserIdBox.PlaceholderText = "UserId"
ui.editorUserIdBox.Text = ""
ui.editorUserIdBox.TextColor3 = Color3.fromRGB(42, 48, 42)
ui.editorUserIdBox.PlaceholderColor3 = Color3.fromRGB(130, 135, 130)
ui.editorUserIdBox.TextSize = 13
ui.editorUserIdBox.TextXAlignment = Enum.TextXAlignment.Left
ui.editorUserIdBox.Font = Enum.Font.Gotham
ui.editorUserIdBox.ClearTextOnFocus = false
ui.editorUserIdBox.ClipsDescendants = true
ui.editorUserIdBox.TextTruncate = Enum.TextTruncate.AtEnd
ui.editorUserIdBox.Parent = ui.settingsFrame

createCorner(ui.editorUserIdBox, 5)
createStroke(ui.editorUserIdBox, Color3.fromRGB(195, 204, 190), 1, 0)

ui.editorUserIdPadding = Instance.new("UIPadding")
ui.editorUserIdPadding.PaddingLeft = UDim.new(0, 8)
ui.editorUserIdPadding.PaddingRight = UDim.new(0, 8)
ui.editorUserIdPadding.Parent = ui.editorUserIdBox

ui.editorAddButton = createTextButton(
	"AddRoomEditorButton",
	"Add",
	UDim2.fromOffset(104, 28),
	ui.settingsFrame
)
ui.editorAddButton.AnchorPoint = Vector2.new(1, 0)
ui.editorAddButton.Position = UDim2.new(1, 0, 0, 152)
ui.editorAddButton.BackgroundColor3 = Color3.fromRGB(68, 143, 82)
ui.editorAddButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ui.editorAddButton.TextSize = 13

ui.editorsListFrame = Instance.new("ScrollingFrame")
ui.editorsListFrame.Name = "EditorsList"
ui.editorsListFrame.Position = UDim2.fromOffset(0, 188)
ui.editorsListFrame.Size = UDim2.new(1, 0, 0, 58)
ui.editorsListFrame.BackgroundColor3 = Color3.fromRGB(241, 244, 238)
ui.editorsListFrame.BorderSizePixel = 0
ui.editorsListFrame.CanvasSize = UDim2.fromOffset(0, 0)
ui.editorsListFrame.ScrollBarThickness = 4
ui.editorsListFrame.ScrollingDirection = Enum.ScrollingDirection.Y
ui.editorsListFrame.Parent = ui.settingsFrame

createCorner(ui.editorsListFrame, 5)
createStroke(ui.editorsListFrame, Color3.fromRGB(205, 214, 200), 1, 0)

ui.editorsListLayout = Instance.new("UIListLayout")
ui.editorsListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ui.editorsListLayout.Padding = UDim.new(0, 4)
ui.editorsListLayout.Parent = ui.editorsListFrame

ui.editorsListPadding = Instance.new("UIPadding")
ui.editorsListPadding.PaddingTop = UDim.new(0, 5)
ui.editorsListPadding.PaddingBottom = UDim.new(0, 5)
ui.editorsListPadding.PaddingLeft = UDim.new(0, 6)
ui.editorsListPadding.PaddingRight = UDim.new(0, 6)
ui.editorsListPadding.Parent = ui.editorsListFrame

ui.settingsCategoryDropdown = Instance.new("Frame")
ui.settingsCategoryDropdown.Name = "CategoryDropdown"
ui.settingsCategoryDropdown.Position = UDim2.new(0.38, 0, 0, 46)
ui.settingsCategoryDropdown.Size = UDim2.new(0.27, -8, 0, 122)
ui.settingsCategoryDropdown.BackgroundColor3 = Color3.fromRGB(248, 250, 246)
ui.settingsCategoryDropdown.BorderSizePixel = 0
ui.settingsCategoryDropdown.Visible = false
ui.settingsCategoryDropdown.ZIndex = 5
ui.settingsCategoryDropdown.Parent = ui.settingsFrame

createCorner(ui.settingsCategoryDropdown, 5)
createStroke(ui.settingsCategoryDropdown, Color3.fromRGB(185, 195, 182), 1, 0)

ui.settingsCategoryDropdownLayout = Instance.new("UIListLayout")
ui.settingsCategoryDropdownLayout.SortOrder = Enum.SortOrder.LayoutOrder
ui.settingsCategoryDropdownLayout.Padding = UDim.new(0, 2)
ui.settingsCategoryDropdownLayout.Parent = ui.settingsCategoryDropdown

ui.settingsCategoryDropdownPadding = Instance.new("UIPadding")
ui.settingsCategoryDropdownPadding.PaddingTop = UDim.new(0, 4)
ui.settingsCategoryDropdownPadding.PaddingLeft = UDim.new(0, 4)
ui.settingsCategoryDropdownPadding.PaddingRight = UDim.new(0, 4)
ui.settingsCategoryDropdownPadding.Parent = ui.settingsCategoryDropdown

local categoryButtons = {}

local function shouldShowRoomsButton()
	return player:GetAttribute("OnboardingStep") == "Complete"
		and player:GetAttribute("ControlMode") == "Hotel"
end

local function isMainMenuActive()
	if player:GetAttribute("OnboardingStep") ~= "Complete" then
		return false
	end

	if typeof(player:GetAttribute("CurrentRoomName")) == "string" then
		return false
	end

	return player:GetAttribute("InHotelMainMenu") == true
		or player:GetAttribute("CurrentRoomName") == nil
end

local function updateCloseButtonForMode()
	local locked = isMainMenuActive()

	ui.closeButton.Visible = not locked
	ui.closeButton.Active = not locked
	ui.closeButton.AutoButtonColor = not locked
	ui.titleLabel.Size = locked
		and UDim2.new(1, -40, 0, 34)
		or UDim2.new(1, -82, 0, 34)
end

local function updateOpenButton()
	if isMainMenuActive() then
		ui.openButton.Visible = false
		return
	end

	ui.openButton.Visible = (not ui.panel.Visible)
		and not anyMajorMenuOpen
		and shouldShowRoomsButton()
end

local function setLocalMajorMenuState(isOpen, menuName)
	if isOpen then
		anyMajorMenuOpen = true
		openMajorMenuName = menuName
	elseif menuName == nil or openMajorMenuName == menuName then
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

local function requestFavourites(forceRefresh)
	if favouritesRequestInFlight then
		return
	end

	if not forceRefresh and favouritesLoaded then
		return
	end

	local requestRemote = getRoomNavigatorRequestRemote()

	if not requestRemote or not getRoomNavigatorResultRemote() then
		favouritesRequestInFlight = false
		favouritesLoaded = true
		favouriteEntries = {}
		return
	end

	favouritesRequestInFlight = true
	requestRemote:FireServer("GetFavourites")
end

local function setPanelVisible(isVisible, options)
	local forceClose = typeof(options) == "table" and options.ForceClose == true

	if not isVisible and isMainMenuActive() and not forceClose then
		applyPanelLayout(PANEL_LAYOUT_MAIN_MENU_DOCKED)
		isVisible = true
	end

	local wasVisible = ui.panel.Visible

	if isVisible then
		publishMajorMenuState(true)
		majorMenuOpened:Fire(MENU_NAME)
	end

	ui.panel.Visible = isVisible
	updateCloseButtonForMode()
	updateOpenButton()

	if isVisible then
		roomListRequest:FireServer()
		requestFavourites(true)

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

local function getOccupancyValue(roomData)
	local occupancy = roomData.Occupancy or roomData.PlayerCount

	if typeof(occupancy) == "number" and occupancy == occupancy and occupancy > 0 then
		return occupancy
	end

	return 0
end

local function normalizeSearchText(value)
	if typeof(value) ~= "string" then
		return ""
	end

	local trimmed = value:match("^%s*(.-)%s*$") or ""
	return string.lower(trimmed)
end

local function isPublicPlayerRoom(roomData)
	return typeof(roomData) == "table"
		and roomData.RoomType ~= "PublicSpace"
		and roomData.IsPublic == true
end

local function getRoomKey(roomData)
	if typeof(roomData) ~= "table" then
		return nil
	end

	if typeof(roomData.RoomKey) == "string" and roomData.RoomKey ~= "" then
		return roomData.RoomKey
	end

	return nil
end

local function isRoomFavourite(roomData)
	local roomKey = getRoomKey(roomData)

	if not roomKey then
		return false
	end

	return favouriteKeysByRoomKey[roomKey] == true or roomData.IsFavourite == true
end

local function applyCachedFavouriteState(roomData)
	local roomKey = getRoomKey(roomData)

	if roomKey then
		roomData.IsFavourite = favouriteKeysByRoomKey[roomKey] == true
	end

	return roomData
end

local function setCachedFavourite(roomKey, isFavourite)
	if typeof(roomKey) ~= "string" or roomKey == "" then
		return
	end

	favouriteKeysByRoomKey[roomKey] = isFavourite == true or nil

	for _, roomData in ipairs(latestRoomList) do
		if roomData.RoomKey == roomKey then
			roomData.IsFavourite = isFavourite == true
		end
	end

	for index = #favouriteEntries, 1, -1 do
		local entry = favouriteEntries[index]

		if entry.RoomKey == roomKey then
			if isFavourite == true then
				entry.IsFavourite = true
			else
				table.remove(favouriteEntries, index)
			end
		end
	end

	if selectedRoomData and selectedRoomData.RoomKey == roomKey then
		selectedRoomData.IsFavourite = isFavourite == true
	end
end

local function syncFavouriteKeys(favouriteKeys)
	favouriteKeysByRoomKey = {}

	if typeof(favouriteKeys) ~= "table" then
		return
	end

	for _, roomKey in ipairs(favouriteKeys) do
		if typeof(roomKey) == "string" and roomKey ~= "" then
			favouriteKeysByRoomKey[roomKey] = true
		end
	end

	for _, roomData in ipairs(latestRoomList) do
		applyCachedFavouriteState(roomData)
	end

	for _, publicRoomData in ipairs(publicRooms) do
		applyCachedFavouriteState(publicRoomData)
	end
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

local function isSameRoomEntry(firstEntry, secondEntry)
	if typeof(firstEntry) ~= "table" or typeof(secondEntry) ~= "table" then
		return false
	end

	local firstRoomKey = getRoomKey(firstEntry)
	local secondRoomKey = getRoomKey(secondEntry)

	if firstRoomKey and secondRoomKey then
		return firstRoomKey == secondRoomKey
	end

	if typeof(firstEntry.RoomName) == "string"
		and typeof(secondEntry.RoomName) == "string"
		and firstEntry.RoomName == secondEntry.RoomName then

		return true
	end

	local firstPublicRoomId = firstEntry.PublicRoomId or firstEntry.Id
	local secondPublicRoomId = secondEntry.PublicRoomId or secondEntry.Id

	return typeof(firstPublicRoomId) == "string"
		and typeof(secondPublicRoomId) == "string"
		and firstPublicRoomId == secondPublicRoomId
end

local function sortRoomsForBrowsing(rooms)
	table.sort(rooms, function(firstRoom, secondRoom)
		local firstIsCurrent = isEntryCurrentRoom(firstRoom)
		local secondIsCurrent = isEntryCurrentRoom(secondRoom)

		if firstIsCurrent ~= secondIsCurrent then
			return firstIsCurrent
		end

		local firstOccupancy = getOccupancyValue(firstRoom)
		local secondOccupancy = getOccupancyValue(secondRoom)

		if firstOccupancy ~= secondOccupancy then
			return firstOccupancy > secondOccupancy
		end

		return normalizeSearchText(getRoomDisplayName(firstRoom))
			< normalizeSearchText(getRoomDisplayName(secondRoom))
	end)

	return rooms
end

local function sortOwnRooms(rooms)
	table.sort(rooms, function(firstRoom, secondRoom)
		local firstIsCurrent = isEntryCurrentRoom(firstRoom)
		local secondIsCurrent = isEntryCurrentRoom(secondRoom)

		if firstIsCurrent ~= secondIsCurrent then
			return firstIsCurrent
		end

		return normalizeSearchText(getRoomDisplayName(firstRoom))
			< normalizeSearchText(getRoomDisplayName(secondRoom))
	end)

	return rooms
end

local function clearSelectionIfMissing(entries)
	if not selectedRoomData then
		return
	end

	for _, entry in ipairs(entries) do
		if isSameRoomEntry(selectedRoomData, entry) then
			return
		end
	end

	selectedRoomData = nil
	selectedRow = nil
end

local function getGuestCategoryCounts()
	local counts = {}

	for _, categoryName in ipairs(GUEST_ROOM_CATEGORIES) do
		counts[categoryName] = 0
	end

	for _, roomData in ipairs(latestRoomList) do
		if isPublicPlayerRoom(roomData) then
			local categoryName = roomData.Category or "Chat Rooms"
			counts[categoryName] = (counts[categoryName] or 0) + 1
		end
	end

	return counts
end

local function isSettingsEditableRoom(entry)
	return selectedTopTab == TOP_TAB_ROOMS
		and selectedRoomSubtab == ROOM_SUBTAB_OWN
		and typeof(entry) == "table"
		and entry.RoomType ~= "PublicSpace"
		and entry.IsOwner == true
end

local function setSettingsCategory(categoryName)
	local isAllowed = false

	for _, allowedCategory in ipairs(GUEST_ROOM_CATEGORIES) do
		if allowedCategory == categoryName then
			isAllowed = true
			break
		end
	end

	selectedSettingsCategory = isAllowed and categoryName or "Chat Rooms"
	ui.settingsCategoryButton.Text = "Category: " .. selectedSettingsCategory
	ui.settingsCategoryDropdown.Visible = false
end

local function setSettingsPublic(isPublic)
	selectedSettingsIsPublic = isPublic == true
	ui.settingsPublicButton.Text = selectedSettingsIsPublic and "Public" or "Private"
	ui.settingsPublicButton.BackgroundColor3 = selectedSettingsIsPublic
		and Color3.fromRGB(88, 128, 102)
		or Color3.fromRGB(128, 104, 88)
	ui.settingsPublicButton.TextColor3 = Color3.fromRGB(255, 255, 255)
end

local function updateSettingsCounter(counter, currentLength, maxLength)
	counter.Text = tostring(currentLength) .. "/" .. tostring(maxLength)
	counter.TextColor3 = currentLength >= maxLength
		and Color3.fromRGB(180, 55, 55)
		or Color3.fromRGB(82, 88, 82)
end

local function enforceSettingsTextLimit(textBox, counter, maxLength)
	local text = textBox.Text or ""

	if #text > maxLength then
		text = string.sub(text, 1, maxLength)
		textBox.Text = text
	end

	updateSettingsCounter(counter, #text, maxLength)
end

local function updateSettingsCounters()
	updateSettingsCounter(ui.settingsNameCounter, #(ui.settingsNameBox.Text or ""), ROOM_NAME_MAX_LENGTH)
	updateSettingsCounter(
		ui.settingsDescriptionCounter,
		#(ui.settingsDescriptionBox.Text or ""),
		ROOM_DESCRIPTION_MAX_LENGTH
	)
end

local function setStatusMessage(message, kind)
	ui.statusLabel.Text = message or ""

	if kind == "error" then
		ui.statusLabel.TextColor3 = Color3.fromRGB(190, 45, 45)
		ui.statusLabel.Font = Enum.Font.GothamBold
	elseif kind == "success" then
		ui.statusLabel.TextColor3 = Color3.fromRGB(48, 126, 70)
		ui.statusLabel.Font = Enum.Font.GothamMedium
	else
		ui.statusLabel.TextColor3 = Color3.fromRGB(90, 90, 90)
		ui.statusLabel.Font = Enum.Font.Gotham
	end
end

local function shakeStatusLabel()
	if statusShakeTween then
		statusShakeTween:Cancel()
		statusShakeTween = nil
	end

	local originalPosition = ui.statusLabel.Position
	local offsets = { -8, 8, -6, 6, 0 }
	local index = 1

	local function playNext()
		local offset = offsets[index]

		if not offset then
			ui.statusLabel.Position = originalPosition
			statusShakeTween = nil
			return
		end

		index += 1
		statusShakeTween = TweenService:Create(
			ui.statusLabel,
			TweenInfo.new(0.045, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = UDim2.new(
					originalPosition.X.Scale,
					originalPosition.X.Offset + offset,
					originalPosition.Y.Scale,
					originalPosition.Y.Offset
				),
			}
		)
		statusShakeTween.Completed:Once(playNext)
		statusShakeTween:Play()
	end

	playNext()
end

local function showSettingsError(message)
	setStatusMessage(message, "error")
	ui.detailPanel.CanvasPosition = Vector2.new(0, 10000)
	shakeStatusLabel()
end

local function populateSettingsFromEntry(entry)
	suppressSettingsTextChanged = true

	if typeof(entry) ~= "table" then
		ui.settingsNameBox.Text = ""
		ui.settingsDescriptionBox.Text = ""
		setSettingsCategory("Chat Rooms")
		setSettingsPublic(true)
		suppressSettingsTextChanged = false
		updateSettingsCounters()
		return
	end

	ui.settingsNameBox.Text = string.sub(getRoomDisplayName(entry), 1, ROOM_NAME_MAX_LENGTH)
	ui.settingsDescriptionBox.Text = string.sub(tostring(entry.Description or ""), 1, ROOM_DESCRIPTION_MAX_LENGTH)
	setSettingsCategory(entry.Category or "Chat Rooms")
	setSettingsPublic(entry.IsPublic ~= false)
	suppressSettingsTextChanged = false
	updateSettingsCounters()
end

local function setSettingsEditorVisible(isVisible)
	ui.settingsFrame.Visible = isVisible == true
	ui.settingsCategoryDropdown.Visible = false

	if isVisible then
		ui.detailStatus.Text = "Edit room settings below."
	end
end

local function requestRoomSettings()
	if roomSettingsRequestInFlight then
		return
	end

	local requestRemote = getRoomSettingsRequestRemote()

	if not requestRemote or not getRoomSettingsResultRemote() then
		showSettingsError("Room settings are unavailable.")
		return
	end

	roomSettingsRequestInFlight = true
	requestRemote:FireServer("GetSettings")
end

local function setRoomEditorControlsEnabled(isEnabled)
	local enabled = isEnabled == true
		and roomEditorMutationInFlight ~= true
		and areRoomSettingsRemotesAvailable()

	ui.editorUserIdBox.Active = enabled
	ui.editorAddButton.Active = enabled
	ui.editorAddButton.AutoButtonColor = enabled
	ui.editorAddButton.BackgroundColor3 = enabled
		and Color3.fromRGB(68, 143, 82)
		or Color3.fromRGB(150, 158, 148)
end

local function updateEditorsCanvas()
	task.defer(function()
		ui.editorsListFrame.CanvasSize = UDim2.fromOffset(0, ui.editorsListLayout.AbsoluteContentSize.Y + 12)
	end)
end

local function clearEditorsList()
	for _, child in ipairs(ui.editorsListFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function getEditorDisplayText(editorEntry)
	if typeof(editorEntry) ~= "table" then
		return "Unknown editor"
	end

	local userId = editorEntry.UserId
	local name = typeof(editorEntry.Name) == "string" and editorEntry.Name or nil
	local displayName = typeof(editorEntry.DisplayName) == "string" and editorEntry.DisplayName or nil

	if name and displayName and displayName ~= name then
		return string.format("%s (@%s) - %s", displayName, name, tostring(userId))
	end

	if name then
		return string.format("@%s - %s", name, tostring(userId))
	end

	return "UserId " .. tostring(userId)
end

local function renderRoomEditors()
	clearEditorsList()

	if not isSettingsEditableRoom(selectedRoomData) then
		currentRoomEditors = {}
		updateEditorsCanvas()
		return
	end

	if roomEditorsUnavailable then
		local unavailableLabel = Instance.new("TextLabel")
		unavailableLabel.Name = "EditorsUnavailable"
		unavailableLabel.Size = UDim2.new(1, 0, 0, 24)
		unavailableLabel.BackgroundTransparency = 1
		unavailableLabel.Text = "Editor management unavailable."
		unavailableLabel.TextColor3 = Color3.fromRGB(150, 80, 70)
		unavailableLabel.TextSize = 12
		unavailableLabel.TextXAlignment = Enum.TextXAlignment.Left
		unavailableLabel.Font = Enum.Font.GothamMedium
		unavailableLabel.Parent = ui.editorsListFrame
		updateEditorsCanvas()
		return
	end

	if roomEditorsRequestInFlight then
		local loadingLabel = Instance.new("TextLabel")
		loadingLabel.Name = "EditorsLoading"
		loadingLabel.Size = UDim2.new(1, 0, 0, 24)
		loadingLabel.BackgroundTransparency = 1
		loadingLabel.Text = "Loading editors..."
		loadingLabel.TextColor3 = Color3.fromRGB(92, 98, 92)
		loadingLabel.TextSize = 12
		loadingLabel.TextXAlignment = Enum.TextXAlignment.Left
		loadingLabel.Font = Enum.Font.Gotham
		loadingLabel.Parent = ui.editorsListFrame
		updateEditorsCanvas()
		return
	end

	if #currentRoomEditors == 0 then
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Name = "NoEditors"
		emptyLabel.Size = UDim2.new(1, 0, 0, 24)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Text = "No editors yet."
		emptyLabel.TextColor3 = Color3.fromRGB(92, 98, 92)
		emptyLabel.TextSize = 12
		emptyLabel.TextXAlignment = Enum.TextXAlignment.Left
		emptyLabel.Font = Enum.Font.Gotham
		emptyLabel.Parent = ui.editorsListFrame
		updateEditorsCanvas()
		return
	end

	for index, editorEntry in ipairs(currentRoomEditors) do
		local row = Instance.new("Frame")
		row.Name = "EditorRow_" .. tostring(editorEntry.UserId or index)
		row.Size = UDim2.new(1, 0, 0, 28)
		row.BackgroundTransparency = 1
		row.LayoutOrder = index
		row.Parent = ui.editorsListFrame

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "EditorName"
		nameLabel.Position = UDim2.fromOffset(0, 0)
		nameLabel.Size = UDim2.new(1, -86, 1, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = getEditorDisplayText(editorEntry)
		nameLabel.TextColor3 = Color3.fromRGB(45, 50, 45)
		nameLabel.TextSize = 12
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Font = Enum.Font.Gotham
		nameLabel.Parent = row

		local removeButton = createTextButton(
			"RemoveEditorButton",
			"Remove",
			UDim2.fromOffset(76, 24),
			row
		)
		removeButton.AnchorPoint = Vector2.new(1, 0.5)
		removeButton.Position = UDim2.new(1, 0, 0.5, 0)
		removeButton.BackgroundColor3 = Color3.fromRGB(151, 82, 82)
		removeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		removeButton.TextSize = 11
		removeButton.Active = roomEditorMutationInFlight ~= true
		removeButton.AutoButtonColor = removeButton.Active

		removeButton.MouseButton1Click:Connect(function()
			if roomEditorMutationInFlight then
				return
			end

			if not isSettingsEditableRoom(selectedRoomData) then
				showSettingsError("Only the room owner can manage editors.")
				return
			end

			local targetUserId = editorEntry.UserId

			if typeof(targetUserId) ~= "number" or targetUserId <= 0 then
				showSettingsError("Invalid UserId.")
				return
			end

			local requestRemote = getRoomSettingsRequestRemote()

			if not requestRemote or not getRoomSettingsResultRemote() then
				roomEditorsUnavailable = true
				showSettingsError("Editor management unavailable.")
				renderRoomEditors()
				return
			end

			roomEditorMutationInFlight = true
			setRoomEditorControlsEnabled(false)
			renderRoomEditors()
			setStatusMessage("Removing editor...")

			requestRemote:FireServer("RemoveRoomEditor", {
				TargetUserId = targetUserId,
			})
		end)
	end

	updateEditorsCanvas()
end

local function requestRoomEditors()
	if roomEditorsRequestInFlight then
		return
	end

	if not isSettingsEditableRoom(selectedRoomData) then
		currentRoomEditors = {}
		roomEditorsUnavailable = false
		renderRoomEditors()
		return
	end

	local requestRemote = getRoomSettingsRequestRemote()

	if not requestRemote or not getRoomSettingsResultRemote() then
		currentRoomEditors = {}
		roomEditorsRequestInFlight = false
		roomEditorsUnavailable = true
		renderRoomEditors()
		return
	end

	roomEditorsUnavailable = false
	roomEditorsRequestInFlight = true
	renderRoomEditors()
	requestRemote:FireServer("GetRoomEditors")
end

local function setRoomEditors(editors)
	roomEditorsUnavailable = false
	currentRoomEditors = {}

	if typeof(editors) == "table" then
		for _, editorEntry in ipairs(editors) do
			if typeof(editorEntry) == "table" and typeof(editorEntry.UserId) == "number" then
				table.insert(currentRoomEditors, editorEntry)
			end
		end
	end

	table.sort(currentRoomEditors, function(a, b)
		return a.UserId < b.UserId
	end)

	renderRoomEditors()
end

local function parseEditorUserIdInput()
	local rawText = ui.editorUserIdBox.Text or ""
	local trimmed = rawText:match("^%s*(.-)%s*$") or ""
	local userId = tonumber(trimmed)

	if not userId
		or userId ~= userId
		or userId <= 0
		or userId >= math.huge
		or userId ~= math.floor(userId) then

		return nil
	end

	return math.floor(userId)
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
	local categoryCounts = getGuestCategoryCounts()

	for categoryName, button in pairs(categoryButtons) do
		local isSelected = categoryName == selectedGuestCategory
		button.Text = string.format("%s (%d)", categoryName, categoryCounts[categoryName] or 0)
		button.BackgroundColor3 = isSelected and Color3.fromRGB(74, 118, 148) or Color3.fromRGB(228, 234, 226)
		button.TextColor3 = isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(45, 50, 45)
	end
end

local function getRawDetailHeight()
	if not selectedRoomData then
		return DETAIL_HEIGHT_EMPTY
	end

	if isSettingsEditableRoom(selectedRoomData) then
		return DETAIL_HEIGHT_SETTINGS
	end

	return DETAIL_HEIGHT_SELECTED
end

local function getDesiredDetailHeight()
	local desiredHeight = getRawDetailHeight()
	local panelHeight = ui.panel.AbsoluteSize.Y

	if panelHeight > 0 then
		local maxDetailHeight = panelHeight - CONTENT_TOP_OFFSET - DETAIL_BOTTOM_OFFSET - DETAIL_GAP - 64
		maxDetailHeight = math.max(DETAIL_HEIGHT_EMPTY, maxDetailHeight)
		desiredHeight = math.min(desiredHeight, maxDetailHeight)
	end

	return desiredHeight
end

local function updateRoomsNavCanvas()
	task.defer(function()
		ui.roomsNav.CanvasSize = UDim2.fromOffset(0, ui.roomsNavLayout.AbsoluteContentSize.Y + 24)
	end)
end

local function updateCategoryCanvas()
	task.defer(function()
		ui.categoryBar.CanvasSize = UDim2.fromOffset(ui.categoryLayout.AbsoluteContentSize.X + 16, 0)
	end)
end

local function updateNavigationState()
	updateTopTabButton(ui.publicSpacesTab, selectedTopTab == TOP_TAB_PUBLIC)
	updateTopTabButton(ui.roomsTab, selectedTopTab == TOP_TAB_ROOMS)

	ui.roomsNav.Visible = selectedTopTab == TOP_TAB_ROOMS

	updateSubtabButton(ui.searchSubtabButton, selectedRoomSubtab == ROOM_SUBTAB_SEARCH)
	updateSubtabButton(ui.ownSubtabButton, selectedRoomSubtab == ROOM_SUBTAB_OWN)
	updateSubtabButton(ui.favouritesSubtabButton, selectedRoomSubtab == ROOM_SUBTAB_FAVOURITES)
	updateSubtabButton(ui.guestSubtabButton, selectedRoomSubtab == ROOM_SUBTAB_GUEST)
	updateCategoryButtons()
	updateRoomsNavCanvas()
	updateCategoryCanvas()

	local detailHeight = getDesiredDetailHeight()
	local contentBottomOffset = CONTENT_TOP_OFFSET + detailHeight + DETAIL_BOTTOM_OFFSET + DETAIL_GAP

	ui.detailPanel.Size = UDim2.new(1, -36, 0, detailHeight)
	ui.detailPanel.CanvasSize = UDim2.fromOffset(0, getRawDetailHeight() + 12)

	if selectedTopTab == TOP_TAB_ROOMS then
		ui.contentFrame.Position = UDim2.fromOffset(180, 124)
		ui.contentFrame.Size = UDim2.new(1, -198, 1, -contentBottomOffset)
		ui.roomsNav.Size = UDim2.new(0, 150, 1, -contentBottomOffset)
	else
		ui.contentFrame.Position = UDim2.fromOffset(18, 124)
		ui.contentFrame.Size = UDim2.new(1, -36, 1, -contentBottomOffset)
	end
end

local function clearList()
	for _, child in ipairs(ui.listFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	selectedRow = nil
end

local function updateCanvasSize()
	task.defer(function()
		ui.listFrame.CanvasSize = UDim2.fromOffset(0, ui.listLayout.AbsoluteContentSize.Y + 12)
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
		ui.detailTitle.Text = "Select a room"
		ui.detailTitle.Size = UDim2.new(1, -28, 0, 24)
		ui.detailOwner.Text = "Owner: -"
		ui.detailMeta.Text = "Occupancy: -"
		ui.detailDescription.Text = ""
		ui.detailStatus.Text = ""
		ui.goButton.Text = "Go"
		ui.goButton.BackgroundColor3 = Color3.fromRGB(110, 115, 110)
		ui.goButton.Active = false
		ui.goButton.AutoButtonColor = false
		ui.detailOwner.Visible = false
		ui.detailMeta.Visible = false
		ui.detailDescription.Visible = false
		ui.detailStatus.Visible = false
		ui.favouriteButton.Visible = false
		ui.goButton.Visible = false
		ui.statusLabel.Visible = false
		setSettingsEditorVisible(false)
		return
	end

	ui.detailTitle.Size = UDim2.new(1, -260, 0, 24)
	ui.detailOwner.Visible = true
	ui.detailMeta.Visible = true
	ui.detailDescription.Visible = true
	ui.detailStatus.Visible = true
	ui.favouriteButton.Visible = true
	ui.goButton.Visible = true
	ui.statusLabel.Visible = true

	ui.detailTitle.Text = getRoomDisplayName(selectedRoomData)
	ui.detailOwner.Text = "Owner: " .. getRoomOwnerText(selectedRoomData)
	ui.detailMeta.Text = "Occupancy: "
		.. getOccupancyText(selectedRoomData)
		.. "  -  Category: "
		.. tostring(selectedRoomData.Category or "Guest Rooms")
	ui.detailDescription.Text = tostring(selectedRoomData.Description or "")
	local isCurrentRoom = isEntryCurrentRoom(selectedRoomData)
	local canEditSettings = isSettingsEditableRoom(selectedRoomData)
	local roomKey = getRoomKey(selectedRoomData)
	local canFavourite = roomKey ~= nil
	local isFavourite = isRoomFavourite(selectedRoomData)

	ui.detailStatus.Text = isCurrentRoom and "You are here." or ""

	ui.favouriteButton.Visible = canFavourite
	ui.favouriteButton.Active = canFavourite and pendingFavouriteToggleByRoomKey[roomKey] ~= true
	ui.favouriteButton.AutoButtonColor = ui.favouriteButton.Active
	ui.favouriteButton.BackgroundColor3 = canFavourite
		and (isFavourite and Color3.fromRGB(151, 102, 82) or Color3.fromRGB(86, 126, 151))
		or Color3.fromRGB(180, 185, 180)
	ui.favouriteButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	ui.favouriteButton.Text = isFavourite and "Remove Favourite" or "Add to Favourites"

	if canEditSettings then
		populateSettingsFromEntry(selectedRoomData)
		setSettingsEditorVisible(true)
		roomEditorsUnavailable = not areRoomSettingsRemotesAvailable()
		setRoomEditorControlsEnabled(true)
		renderRoomEditors()
		ui.detailStatus.Text = isCurrentRoom
			and "Editing your current room settings."
			or "You can edit this room's settings."
	else
		setSettingsEditorVisible(false)
		currentRoomEditors = {}
		setRoomEditorControlsEnabled(false)
	end

	if isCurrentRoom then
		ui.goButton.Active = false
		ui.goButton.AutoButtonColor = false
		ui.goButton.BackgroundColor3 = Color3.fromRGB(110, 115, 110)
		ui.goButton.Text = "Here"
		return
	end

	if joinRoomRequestInFlight then
		ui.goButton.Active = false
		ui.goButton.AutoButtonColor = false
		ui.goButton.BackgroundColor3 = Color3.fromRGB(110, 115, 110)
		ui.goButton.Text = "Joining..."
		return
	end

	local canGo = (typeof(selectedRoomData.RoomName) == "string" and selectedRoomData.RoomName ~= "")
		or (
			selectedRoomData.RoomType == "PublicSpace"
			and typeof(selectedRoomData.PublicRoomId) == "string"
			and selectedRoomData.PublicRoomId ~= ""
		)

	ui.goButton.Active = canGo
	ui.goButton.AutoButtonColor = canGo
	ui.goButton.BackgroundColor3 = canGo and Color3.fromRGB(68, 143, 82) or Color3.fromRGB(110, 115, 110)
	ui.goButton.Text = canGo and "Go" or "Unavailable"
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

	updateNavigationState()
	updateDetailPanel()

	if isSettingsEditableRoom(roomData) then
		requestRoomSettings()
		requestRoomEditors()
	else
		currentRoomEditors = {}
		renderRoomEditors()
	end
end

local function joinSelectedRoom()
	if joinRoomRequestInFlight then
		return
	end

	if not selectedRoomData then
		return
	end

	if isEntryCurrentRoom(selectedRoomData) then
		return
	end

	local joinPayload = nil

	if selectedRoomData.RoomType == "PublicSpace" then
		local publicRoomId = selectedRoomData.PublicRoomId

		if typeof(publicRoomId) ~= "string" or publicRoomId == "" then
			showSettingsError("This public space is not available yet.")
			return
		end

		joinPayload = {
			RoomType = "PublicSpace",
			PublicRoomId = publicRoomId,
		}
	else
		local roomName = selectedRoomData.RoomName

		if typeof(roomName) ~= "string" or roomName == "" then
			showSettingsError("This room is not available yet.")
			return
		end

		joinPayload = roomName
	end

	joinRoomRequestInFlight = true
	joinRoomRequestToken += 1
	local thisRequestToken = joinRoomRequestToken

	setStatusMessage("Joining...")
	ui.goButton.Text = "Joining..."
	ui.goButton.Active = false
	ui.goButton.AutoButtonColor = false
	ui.goButton.BackgroundColor3 = Color3.fromRGB(110, 115, 110)

	roomTransitionRequest:Fire("FadeOut")

	task.delay(ROOM_JOIN_FADE_OUT_SECONDS, function()
		if not joinRoomRequestInFlight or joinRoomRequestToken ~= thisRequestToken then
			return
		end

		joinRoomRequest:FireServer(joinPayload)
	end)

	task.delay(8, function()
		if joinRoomRequestInFlight and joinRoomRequestToken == thisRequestToken then
			joinRoomRequestInFlight = false
			joinRoomRequestToken += 1
			roomTransitionRequest:Fire("FadeIn")
			showSettingsError("Room join timed out. Please try again.")
			updateDetailPanel()
		end
	end)
end

local function createEmptyState(message)
	local emptyFrame = Instance.new("Frame")
	emptyFrame.Name = "EmptyState"
	emptyFrame.Size = UDim2.new(1, -4, 0, 76)
	emptyFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	emptyFrame.BorderSizePixel = 0
	emptyFrame.Parent = ui.listFrame

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

local function addFavouriteMarker(row, yOffset)
	local marker = Instance.new("TextLabel")
	marker.Name = "FavouriteMarker"
	marker.AnchorPoint = Vector2.new(1, 0)
	marker.Position = UDim2.new(1, -84, 0, yOffset or 34)
	marker.Size = UDim2.fromOffset(58, 18)
	marker.BackgroundColor3 = Color3.fromRGB(235, 211, 125)
	marker.BorderSizePixel = 0
	marker.Text = "Fav"
	marker.TextColor3 = Color3.fromRGB(84, 67, 24)
	marker.TextSize = 11
	marker.Font = Enum.Font.GothamBold
	marker.Parent = row

	createCorner(marker, 5)
end

local function createPublicSpaceRow(publicRoomData, order)
	applyCachedFavouriteState(publicRoomData)

	local row = Instance.new("TextButton")
	row.Name = tostring(publicRoomData.PublicRoomId or publicRoomData.DisplayName or "PublicSpace")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -4, 0, 82)
	row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	row.BorderSizePixel = 0
	row.Text = ""
	row.AutoButtonColor = true
	row.Parent = ui.listFrame

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

	if isRoomFavourite(publicRoomData) then
		addFavouriteMarker(row, 34)
	end

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
		selectedRoomData = publicRoomData
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
	row.Parent = ui.listFrame

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
	applyCachedFavouriteState(roomData)

	local row = Instance.new("TextButton")
	row.Name = tostring(roomData.RoomName or roomData.RoomKey or "Room")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -4, 0, 72)
	row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	row.BorderSizePixel = 0
	row.Text = ""
	row.AutoButtonColor = true
	row.Parent = ui.listFrame

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

	if isRoomFavourite(roomData) then
		addFavouriteMarker(row, 34)
	end

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
		selectedRoomData = roomData
		selectedRow = row
		setRowSelected(row, true)
	end

	return row
end

local function filterRoomsByCategory(categoryName)
	local rooms = {}

	for _, roomData in ipairs(latestRoomList) do
		local category = roomData.Category or "Chat Rooms"

		if isPublicPlayerRoom(roomData) and category == categoryName then
			table.insert(rooms, roomData)
		end
	end

	return sortRoomsForBrowsing(rooms)
end

local function filterOwnRooms()
	local rooms = {}

	for _, roomData in ipairs(latestRoomList) do
		if roomData.IsOwner == true then
			table.insert(rooms, roomData)
		end
	end

	return sortOwnRooms(rooms)
end

local function filterSearchRooms()
	local query = normalizeSearchText(searchQuery)
	local rooms = {}

	for _, roomData in ipairs(latestRoomList) do
		if isPublicPlayerRoom(roomData) then
			local displayName = normalizeSearchText(getRoomDisplayName(roomData))
			local ownerName = normalizeSearchText(tostring(roomData.OwnerName or ""))
			local ownerDisplayName = normalizeSearchText(tostring(roomData.OwnerDisplayName or ""))
			local category = normalizeSearchText(tostring(roomData.Category or ""))
			local description = normalizeSearchText(tostring(roomData.Description or ""))

			if query == ""
				or string.find(displayName, query, 1, true)
				or string.find(ownerName, query, 1, true)
				or string.find(ownerDisplayName, query, 1, true)
				or string.find(category, query, 1, true)
				or string.find(description, query, 1, true) then

				table.insert(rooms, roomData)
			end
		end
	end

	return sortRoomsForBrowsing(rooms)
end

local function renderRoomRows(rooms, emptyMessage)
	clearSelectionIfMissing(rooms)

	if #rooms == 0 then
		createEmptyState(emptyMessage)
		return
	end

	for index, roomData in ipairs(rooms) do
		createRoomRow(roomData, index)
	end
end

local function renderFavouriteRows()
	if favouritesRequestInFlight and #favouriteEntries == 0 then
		clearSelectionIfMissing({})
		createEmptyState("Loading favourites...")
		return
	end

	clearSelectionIfMissing(favouriteEntries)

	if #favouriteEntries == 0 then
		createEmptyState("No favourite rooms yet.")
		return
	end

	for index, entry in ipairs(favouriteEntries) do
		entry.IsFavourite = true

		if entry.RoomType == "PublicSpace" then
			createPublicSpaceRow(entry, index)
		else
			createRoomRow(entry, index)
		end
	end
end

local function renderPublicSpaces()
	ui.sectionTitle.Text = "Public Spaces"
	ui.searchBox.Visible = false
	ui.categoryBar.Visible = false
	ui.listFrame.Position = UDim2.fromOffset(14, 44)
	ui.listFrame.Size = UDim2.new(1, -28, 1, -58)

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
	ui.listFrame.Size = UDim2.new(1, -28, 1, -98)
	ui.searchBox.Visible = selectedRoomSubtab == ROOM_SUBTAB_SEARCH
	ui.categoryBar.Visible = selectedRoomSubtab == ROOM_SUBTAB_GUEST

	if selectedRoomSubtab == ROOM_SUBTAB_SEARCH then
		ui.sectionTitle.Text = "Search Rooms"
		ui.listFrame.Position = UDim2.fromOffset(14, 84)
		renderRoomRows(filterSearchRooms(), "No rooms found.")
	elseif selectedRoomSubtab == ROOM_SUBTAB_OWN then
		ui.sectionTitle.Text = "Own Room(s)"
		ui.listFrame.Position = UDim2.fromOffset(14, 44)
		ui.listFrame.Size = UDim2.new(1, -28, 1, -58)
		renderRoomRows(filterOwnRooms(), "You do not have an active room yet.")
	elseif selectedRoomSubtab == ROOM_SUBTAB_FAVOURITES then
		ui.sectionTitle.Text = "Favourites"
		ui.listFrame.Position = UDim2.fromOffset(14, 44)
		ui.listFrame.Size = UDim2.new(1, -28, 1, -58)
		requestFavourites()
		renderFavouriteRows()
	else
		ui.sectionTitle.Text = "Guest Rooms"
		ui.listFrame.Position = UDim2.fromOffset(14, 84)
		renderRoomRows(
			filterRoomsByCategory(selectedGuestCategory),
			"No active rooms in this category."
		)
	end
end

local function buildCategoryButtons()
	for _, child in ipairs(ui.categoryBar:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	categoryButtons = {}

	for _, categoryName in ipairs(GUEST_ROOM_CATEGORIES) do
		local button = createTextButton(
			"Category_" .. categoryName:gsub("%W", ""),
			categoryName,
			UDim2.fromOffset(categoryName == "Gaming & Race Rooms" and 168 or 126, 32),
			ui.categoryBar
		)
		button.TextSize = 11
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

local function buildSettingsCategoryDropdown()
	for _, child in ipairs(ui.settingsCategoryDropdown:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	for index, categoryName in ipairs(GUEST_ROOM_CATEGORIES) do
		local button = createTextButton(
			"SettingsCategory_" .. categoryName:gsub("%W", ""),
			categoryName,
			UDim2.new(1, 0, 0, 20),
			ui.settingsCategoryDropdown
		)
		button.LayoutOrder = index
		button.TextSize = 11
		button.ZIndex = 6

		button.MouseButton1Click:Connect(function()
			setSettingsCategory(categoryName)
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
buildSettingsCategoryDropdown()

ui.publicSpacesTab.MouseButton1Click:Connect(function()
	selectedTopTab = TOP_TAB_PUBLIC
	selectedRoomData = nil
	selectedRow = nil
	renderNavigator()
end)

ui.roomsTab.MouseButton1Click:Connect(function()
	selectedTopTab = TOP_TAB_ROOMS
	selectedRoomData = nil
	selectedRow = nil
	renderNavigator()
end)

ui.searchSubtabButton.MouseButton1Click:Connect(function()
	selectedRoomSubtab = ROOM_SUBTAB_SEARCH
	selectedRoomData = nil
	selectedRow = nil
	renderNavigator()
end)

ui.ownSubtabButton.MouseButton1Click:Connect(function()
	selectedRoomSubtab = ROOM_SUBTAB_OWN
	selectedRoomData = nil
	selectedRow = nil
	renderNavigator()
end)

ui.favouritesSubtabButton.MouseButton1Click:Connect(function()
	selectedRoomSubtab = ROOM_SUBTAB_FAVOURITES
	selectedRoomData = nil
	selectedRow = nil
	renderNavigator()
end)

ui.guestSubtabButton.MouseButton1Click:Connect(function()
	selectedRoomSubtab = ROOM_SUBTAB_GUEST
	selectedRoomData = nil
	selectedRow = nil
	renderNavigator()
end)

ui.searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	searchQuery = ui.searchBox.Text

	if selectedTopTab == TOP_TAB_ROOMS and selectedRoomSubtab == ROOM_SUBTAB_SEARCH then
		renderNavigator()
	end
end)

ui.panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	updateNavigationState()
	updateCanvasSize()
end)

ui.goButton.MouseButton1Click:Connect(joinSelectedRoom)

ui.favouriteButton.MouseButton1Click:Connect(function()
	if not selectedRoomData then
		return
	end

	local roomKey = getRoomKey(selectedRoomData)

	if not roomKey then
		showSettingsError("This room cannot be favourited.")
		return
	end

	if pendingFavouriteToggleByRoomKey[roomKey] then
		return
	end

	local requestRemote = getRoomNavigatorRequestRemote()

	if not requestRemote or not getRoomNavigatorResultRemote() then
		showSettingsError("Favourites are unavailable.")
		return
	end

	pendingFavouriteToggleByRoomKey[roomKey] = true
	ui.favouriteButton.Active = false
	ui.favouriteButton.AutoButtonColor = false
	setStatusMessage("Updating favourite...")

	requestRemote:FireServer("ToggleFavourite", {
		RoomKey = roomKey,
	})
end)

ui.settingsCategoryButton.MouseButton1Click:Connect(function()
	ui.settingsCategoryDropdown.Visible = not ui.settingsCategoryDropdown.Visible
end)

ui.settingsPublicButton.MouseButton1Click:Connect(function()
	setSettingsPublic(not selectedSettingsIsPublic)
end)

ui.settingsNameBox:GetPropertyChangedSignal("Text"):Connect(function()
	if suppressSettingsTextChanged then
		return
	end

	enforceSettingsTextLimit(ui.settingsNameBox, ui.settingsNameCounter, ROOM_NAME_MAX_LENGTH)
end)

ui.settingsDescriptionBox:GetPropertyChangedSignal("Text"):Connect(function()
	if suppressSettingsTextChanged then
		return
	end

	enforceSettingsTextLimit(
		ui.settingsDescriptionBox,
		ui.settingsDescriptionCounter,
		ROOM_DESCRIPTION_MAX_LENGTH
	)
end)

ui.editorUserIdBox:GetPropertyChangedSignal("Text"):Connect(function()
	local digitsOnly = (ui.editorUserIdBox.Text or ""):gsub("%D", "")

	if #digitsOnly > ROOM_EDITOR_USER_ID_MAX_LENGTH then
		digitsOnly = string.sub(digitsOnly, 1, ROOM_EDITOR_USER_ID_MAX_LENGTH)
	end

	if ui.editorUserIdBox.Text ~= digitsOnly then
		ui.editorUserIdBox.Text = digitsOnly
	end
end)

ui.editorAddButton.MouseButton1Click:Connect(function()
	if roomEditorMutationInFlight then
		return
	end

	if not isSettingsEditableRoom(selectedRoomData) then
		showSettingsError("Only the room owner can manage editors.")
		return
	end

	local targetUserId = parseEditorUserIdInput()

	if not targetUserId then
		showSettingsError("Invalid UserId.")
		return
	end

	if targetUserId == player.UserId then
		showSettingsError("You are already the room owner.")
		return
	end

	local requestRemote = getRoomSettingsRequestRemote()

	if not requestRemote or not getRoomSettingsResultRemote() then
		roomEditorsUnavailable = true
		showSettingsError("Editor management unavailable.")
		renderRoomEditors()
		return
	end

	roomEditorMutationInFlight = true
	setRoomEditorControlsEnabled(false)
	renderRoomEditors()
	setStatusMessage("Adding editor...")

	requestRemote:FireServer("AddRoomEditor", {
		TargetUserId = targetUserId,
	})
end)

ui.settingsSaveButton.MouseButton1Click:Connect(function()
	if not isSettingsEditableRoom(selectedRoomData) then
		showSettingsError("Select your own room first.")
		return
	end

	local roomName = ui.settingsNameBox.Text or ""

	if roomName:match("^%s*$") then
		showSettingsError("Room name cannot be empty.")
		return
	end

	setStatusMessage("Saving settings...")
	ui.settingsSaveButton.Active = false
	ui.settingsSaveButton.AutoButtonColor = false

	local requestRemote = getRoomSettingsRequestRemote()

	if not requestRemote or not getRoomSettingsResultRemote() then
		ui.settingsSaveButton.Active = true
		ui.settingsSaveButton.AutoButtonColor = true
		showSettingsError("Room settings are unavailable.")
		return
	end

	requestRemote:FireServer("UpdateSettings", {
		DisplayName = roomName,
		Category = selectedSettingsCategory,
		Description = ui.settingsDescriptionBox.Text,
		IsPublic = selectedSettingsIsPublic,
	})
end)

ui.openButton.MouseButton1Click:Connect(function()
	applyPanelLayout(PANEL_LAYOUT_NORMAL)
	setPanelVisible(true)
end)

ui.closeButton.MouseButton1Click:Connect(function()
	if isMainMenuActive() then
		applyPanelLayout(PANEL_LAYOUT_MAIN_MENU_DOCKED)
		setPanelVisible(true)
		return
	end

	setPanelVisible(false)
end)

local function syncMainMenuNavigatorState()
	if isMainMenuActive() then
		applyPanelLayout(PANEL_LAYOUT_MAIN_MENU_DOCKED)

		if not ui.panel.Visible then
			setPanelVisible(true)
		else
			updateCloseButtonForMode()
			updateOpenButton()
		end

		return
	end

	if currentPanelLayout == PANEL_LAYOUT_MAIN_MENU_DOCKED then
		applyPanelLayout(PANEL_LAYOUT_NORMAL)
	end

	updateCloseButtonForMode()
	updateOpenButton()
end

openRoomNavigator.Event:Connect(function(payload)
	local mode = nil

	if typeof(payload) == "table" then
		mode = payload.Mode
	elseif typeof(payload) == "string" then
		mode = payload
	end

	applyPanelLayout(mode == PANEL_LAYOUT_MAIN_MENU_DOCKED
		and PANEL_LAYOUT_MAIN_MENU_DOCKED
		or PANEL_LAYOUT_NORMAL)
	setPanelVisible(true)
	syncMainMenuNavigatorState()
end)

majorMenuOpened.Event:Connect(function(menuName)
	if isMainMenuActive() then
		syncMainMenuNavigatorState()
		return
	end

	if menuName ~= MENU_NAME and ui.panel.Visible then
		setPanelVisible(false)
	end
end)

closeMajorMenus.Event:Connect(function()
	if isMainMenuActive() then
		syncMainMenuNavigatorState()
		return
	end

	if ui.panel.Visible then
		setPanelVisible(false)
	end
end)

majorMenuStateChanged.Event:Connect(function(isOpen, menuName)
	setLocalMajorMenuState(isOpen == true, menuName)
end)

roomListUpdate.OnClientEvent:Connect(function(roomList, currentRoomName)
	latestRoomList = typeof(roomList) == "table" and roomList or {}
	latestCurrentRoomName = currentRoomName

	for _, roomData in ipairs(latestRoomList) do
		if typeof(roomData.RoomKey) == "string" and roomData.RoomKey ~= "" then
			if roomData.IsFavourite == true then
				favouriteKeysByRoomKey[roomData.RoomKey] = true
			elseif roomData.IsFavourite == false then
				favouriteKeysByRoomKey[roomData.RoomKey] = nil
			end
		end
	end

	if ui.panel.Visible then
		renderNavigator()
	end

	updateOpenButton()
end)

joinRoomResult.OnClientEvent:Connect(function(success, message)
	joinRoomRequestInFlight = false
	joinRoomRequestToken += 1
	roomTransitionRequest:Fire("FadeIn")

	if success then
		setStatusMessage(message or "Joined room.", "success")
		setPanelVisible(false, { ForceClose = true })
	else
		showSettingsError(message or "Could not join room.")
		updateDetailPanel()
	end

	roomListRequest:FireServer()
end)

local function handleRoomNavigatorResult(response)
	if typeof(response) ~= "table" then
		showSettingsError("Could not update favourites.")
		return
	end

	if response.Kind == "Favourites" then
		favouritesRequestInFlight = false

		if response.Success == true then
			favouritesLoaded = true
			syncFavouriteKeys(response.FavouriteKeys)
			favouriteEntries = typeof(response.Entries) == "table" and response.Entries or {}

			for _, entry in ipairs(favouriteEntries) do
				entry.IsFavourite = true
			end
		else
			favouritesLoaded = true
			showSettingsError(response.Message or "Could not load favourites.")
		end

		if ui.panel.Visible and renderNavigator then
			renderNavigator()
		end

		return
	end

	if response.Kind == "ToggleFavourite" then
		local roomKey = response.RoomKey

		if typeof(roomKey) == "string" then
			pendingFavouriteToggleByRoomKey[roomKey] = nil
		end

		if response.Success == true then
			setCachedFavourite(roomKey, response.IsFavourite == true)
			setStatusMessage(response.Message or "Favourite updated.", "success")
			favouritesLoaded = false
			requestFavourites(true)
		else
			showSettingsError(response.Message or "Could not update favourite.")
		end

		if ui.panel.Visible and renderNavigator then
			renderNavigator()
		else
			updateDetailPanel()
		end

		return
	end

	showSettingsError(response.Message or "Unknown room navigator response.")
end

local function handleRoomSettingsResult(response)
	if typeof(response) ~= "table" then
		roomSettingsRequestInFlight = false
		roomEditorsRequestInFlight = false
		roomEditorMutationInFlight = false
		ui.settingsSaveButton.Active = true
		ui.settingsSaveButton.AutoButtonColor = true
		setRoomEditorControlsEnabled(isSettingsEditableRoom(selectedRoomData))
		showSettingsError("Could not load room settings.")
		return
	end

	local action = response.Action
	local isSettingsAction = action == "GetSettings" or action == "UpdateSettings"
	local isEditorListAction = action == "GetRoomEditors"
	local isEditorMutationAction = action == "AddRoomEditor" or action == "RemoveRoomEditor"

	if isSettingsAction then
		roomSettingsRequestInFlight = false
		ui.settingsSaveButton.Active = true
		ui.settingsSaveButton.AutoButtonColor = true
	end

	if isEditorListAction then
		roomEditorsRequestInFlight = false
	end

	if isEditorMutationAction then
		roomEditorMutationInFlight = false
		setRoomEditorControlsEnabled(isSettingsEditableRoom(selectedRoomData))
	end

	if response.Success ~= true then
		showSettingsError(response.Message or "Could not save room settings.")

		if isEditorListAction then
			currentRoomEditors = {}
		end

		if isEditorListAction or isEditorMutationAction then
			renderRoomEditors()
		end

		return
	end

	if isEditorListAction or isEditorMutationAction then
		if typeof(response.Editors) == "table" then
			setRoomEditors(response.Editors)
		else
			requestRoomEditors()
		end

		if isEditorMutationAction then
			if action == "AddRoomEditor" then
				ui.editorUserIdBox.Text = ""
			end

			setStatusMessage(response.Message or "Room editors updated.", "success")
		else
			setStatusMessage("")
		end

		return
	end

	local settings = response.Settings

	if typeof(settings) == "table" then
		if selectedRoomData and selectedRoomData.IsOwner == true then
			selectedRoomData.DisplayName = settings.DisplayName
			selectedRoomData.Category = settings.Category or selectedRoomData.Category
			selectedRoomData.Description = settings.Description or ""
			selectedRoomData.IsPublic = settings.IsPublic == true
			selectedRoomData.MaxOccupancy = settings.MaxOccupancy or selectedRoomData.MaxOccupancy
			populateSettingsFromEntry(selectedRoomData)
		else
			populateSettingsFromEntry(settings)
		end
	end

	if response.Action == "UpdateSettings" then
		setStatusMessage(response.Message or "Room settings saved.", "success")
		roomListRequest:FireServer()
	else
		setStatusMessage("")
	end

	if renderNavigator then
		renderNavigator()
	end
end

local function handleRoomCreationResult(status)
	if status == "Created"
		or status == "ShowCharacterCreation"
		or status == "ShowCreation" then

		setPanelVisible(false)
		ui.openButton.Visible = false
	end
end

connectOptionalRemoteEvent("RoomNavigatorResult", handleRoomNavigatorResult)
connectOptionalRemoteEvent("RoomSettingsResult", handleRoomSettingsResult)
connectOptionalRemoteEvent("RoomCreationResult", handleRoomCreationResult)

player:GetAttributeChangedSignal("OnboardingStep"):Connect(function()
	syncMainMenuNavigatorState()

	if ui.panel.Visible and not shouldShowRoomsButton() and not isMainMenuActive() then
		setPanelVisible(false)
	else
		updateOpenButton()
	end
end)

player:GetAttributeChangedSignal("ControlMode"):Connect(function()
	if ui.panel.Visible and not shouldShowRoomsButton() and not isMainMenuActive() then
		setPanelVisible(false)
	else
		syncMainMenuNavigatorState()
		updateOpenButton()
	end
end)

player:GetAttributeChangedSignal("CurrentRoomName"):Connect(function()
	latestCurrentRoomName = player:GetAttribute("CurrentRoomName")
	syncMainMenuNavigatorState()

	if ui.panel.Visible and renderNavigator then
		renderNavigator()
	else
		updateDetailPanel()
	end
end)

player:GetAttributeChangedSignal("InHotelMainMenu"):Connect(syncMainMenuNavigatorState)

renderNavigator()
syncMainMenuNavigatorState()
updateOpenButton()
