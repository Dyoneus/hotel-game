-- StarterGui/RoomSettingsGui/RoomSettingsClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local roomSettingsRequest = remoteEvents:WaitForChild("RoomSettingsRequest")
local roomSettingsResult = remoteEvents:WaitForChild("RoomSettingsResult")

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 165
gui.Enabled = true

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

local CATEGORY_OPTIONS = {
	"Chat Rooms",
	"Maze Rooms",
	"Trading Rooms",
	"Help Centres",
	"Gaming & Race Rooms",
}
local ROOM_NAME_MAX_LENGTH = 30
local ROOM_DESCRIPTION_MAX_LENGTH = 100
local TAB_BASIC = "Basic"
local TAB_RIGHTS = "Rights"
local TAB_FLOOR = "Floor"
local TAB_BANNED = "Banned Users"
local TAB_MODERATION = "Moderation"
local THEME = {
	Paper = Color3.fromRGB(246, 236, 207),
	Header = Color3.fromRGB(126, 100, 62),
	HeaderText = Color3.fromRGB(255, 250, 235),
	Panel = Color3.fromRGB(253, 245, 224),
	PanelAlt = Color3.fromRGB(255, 250, 236),
	PanelStroke = Color3.fromRGB(201, 179, 139),
	Text = Color3.fromRGB(61, 50, 38),
	SubtleText = Color3.fromRGB(93, 76, 55),
	Button = Color3.fromRGB(126, 100, 62),
	ButtonSelected = Color3.fromRGB(127, 101, 63),
	ButtonMuted = Color3.fromRGB(153, 142, 119),
	Close = Color3.fromRGB(141, 63, 49),
	Confirm = Color3.fromRGB(72, 143, 77),
	InputStroke = Color3.fromRGB(199, 177, 135),
	Error = Color3.fromRGB(151, 62, 48),
	Success = Color3.fromRGB(48, 126, 70),
}

local state = {
	isOpen = false,
	roomId = "Primary",
	activeTab = TAB_BASIC,
	category = "Chat Rooms",
	isPublic = true,
	editors = {},
	floorStyles = {},
	currentFloorStyleId = nil,
	editorRequestInFlight = false,
	settingsRequestInFlight = false,
	floorRequestInFlight = false,
	applyingFloorStyleId = nil,
	floorRequestId = 0,
	restoreNavigatorState = nil,
	openRoomName = nil,
}
local ui = {}

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

local openRoomSettings = getOrCreateClientEvent("OpenRoomSettings")
local openRoomNavigator = getOrCreateClientEvent("OpenRoomNavigator")
local closeMajorMenus = getOrCreateClientEvent("CloseMajorMenus")
local majorMenuOpened = getOrCreateClientEvent("MajorMenuOpened")

local function createTextButton(name, text, size, parent)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.BackgroundColor3 = THEME.Button
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = THEME.HeaderText
	button.TextSize = 13
	button.Font = Enum.Font.GothamBold
	button.Parent = parent

	createCorner(button, 6)
	createStroke(button, THEME.PanelStroke, 1, 0.35)

	return button
end

local function createLabel(name, text, position, size, parent, options)
	options = options or {}

	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = options.TextColor3 or THEME.Text
	label.TextSize = options.TextSize or 12
	label.TextXAlignment = options.TextXAlignment or Enum.TextXAlignment.Left
	label.TextYAlignment = options.TextYAlignment or Enum.TextYAlignment.Center
	label.TextWrapped = options.TextWrapped == true
	label.TextTruncate = options.TextTruncate or Enum.TextTruncate.None
	label.Font = options.Font or Enum.Font.Gotham
	label.Parent = parent

	return label
end

local function createInput(name, placeholder, position, size, parent, multiLine)
	local input = Instance.new("TextBox")
	input.Name = name
	input.Position = position
	input.Size = size
	input.BackgroundColor3 = Color3.fromRGB(255, 250, 236)
	input.BorderSizePixel = 0
	input.PlaceholderText = placeholder
	input.PlaceholderColor3 = Color3.fromRGB(126, 109, 82)
	input.Text = ""
	input.TextColor3 = THEME.Text
	input.TextSize = 13
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.TextYAlignment = multiLine and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center
	input.Font = Enum.Font.Gotham
	input.ClearTextOnFocus = false
	input.MultiLine = multiLine == true
	input.TextWrapped = multiLine == true
	input.Parent = parent

	createCorner(input, 6)
	createStroke(input, THEME.InputStroke, 1, 0)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 9)
	padding.PaddingRight = UDim.new(0, 9)
	padding.PaddingTop = UDim.new(0, multiLine and 6 or 0)
	padding.PaddingBottom = UDim.new(0, multiLine and 6 or 0)
	padding.Parent = input

	return input
end

local function clearGuiObjects(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

ui.backdrop = Instance.new("Frame")
ui.backdrop.Name = "Backdrop"
ui.backdrop.Size = UDim2.fromScale(1, 1)
ui.backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
ui.backdrop.BackgroundTransparency = 0.45
ui.backdrop.Visible = false
ui.backdrop.Parent = gui

ui.window = Instance.new("Frame")
ui.window.Name = "RoomSettingsWindow"
ui.window.AnchorPoint = Vector2.new(0.5, 0.5)
ui.window.Position = UDim2.fromScale(0.5, 0.5)
ui.window.Size = UDim2.fromOffset(650, 510)
ui.window.BackgroundColor3 = THEME.Paper
ui.window.BorderSizePixel = 0
ui.window.Parent = ui.backdrop

createCorner(ui.window, 8)
createStroke(ui.window, THEME.Header, 2, 0)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(360, 320)
sizeConstraint.MaxSize = Vector2.new(760, 560)
sizeConstraint.Parent = ui.window

ui.header = Instance.new("Frame")
ui.header.Name = "Header"
ui.header.Size = UDim2.new(1, 0, 0, 48)
ui.header.BackgroundColor3 = THEME.Header
ui.header.BorderSizePixel = 0
ui.header.Parent = ui.window

createCorner(ui.header, 8)

ui.title = createLabel(
	"Title",
	"Room Settings",
	UDim2.fromOffset(18, 0),
	UDim2.new(1, -72, 1, 0),
	ui.header,
	{
		TextColor3 = THEME.HeaderText,
		TextSize = 17,
		Font = Enum.Font.GothamBold,
	}
)

ui.closeButton = createTextButton("CloseButton", "X", UDim2.fromOffset(32, 30), ui.header)
ui.closeButton.AnchorPoint = Vector2.new(1, 0.5)
ui.closeButton.Position = UDim2.new(1, -12, 0.5, 0)
ui.closeButton.BackgroundColor3 = THEME.Close

ui.tabBar = Instance.new("Frame")
ui.tabBar.Name = "TabBar"
ui.tabBar.Position = UDim2.fromOffset(14, 60)
ui.tabBar.Size = UDim2.new(1, -28, 0, 38)
ui.tabBar.BackgroundTransparency = 1
ui.tabBar.Parent = ui.window

ui.tabLayout = Instance.new("UIListLayout")
ui.tabLayout.FillDirection = Enum.FillDirection.Horizontal
ui.tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
ui.tabLayout.Padding = UDim.new(0, 8)
ui.tabLayout.Parent = ui.tabBar

ui.tabs = {}
for index, tabName in ipairs({ TAB_BASIC, TAB_RIGHTS, TAB_FLOOR, TAB_BANNED, TAB_MODERATION }) do
	local button = createTextButton("Tab_" .. tabName:gsub("%W", ""), tabName, UDim2.new(0.2, -7, 1, 0), ui.tabBar)
	button.LayoutOrder = index
	button.TextTruncate = Enum.TextTruncate.AtEnd
	ui.tabs[tabName] = button
end

ui.content = Instance.new("ScrollingFrame")
ui.content.Name = "Content"
ui.content.Position = UDim2.fromOffset(14, 108)
ui.content.Size = UDim2.new(1, -28, 1, -150)
ui.content.BackgroundColor3 = THEME.Panel
ui.content.BorderSizePixel = 0
ui.content.ScrollBarThickness = 6
ui.content.ScrollingDirection = Enum.ScrollingDirection.Y
ui.content.CanvasSize = UDim2.fromOffset(0, 0)
ui.content.Parent = ui.window

createCorner(ui.content, 7)
createStroke(ui.content, THEME.PanelStroke, 1, 0.15)

ui.status = createLabel(
	"Status",
	"",
	UDim2.new(0, 16, 1, -34),
	UDim2.new(1, -32, 0, 22),
	ui.window,
	{ TextColor3 = THEME.SubtleText, TextSize = 12, Font = Enum.Font.GothamMedium }
)

local function setStatus(message, isError)
	ui.status.Text = tostring(message or "")
	ui.status.TextColor3 = isError and THEME.Error or THEME.Success
end

local function getViewportSize()
	local camera = workspace.CurrentCamera

	if camera then
		return camera.ViewportSize
	end

	return gui.AbsoluteSize
end

local function applyWindowLayout()
	local viewportSize = getViewportSize()
	local availableWidth = math.max(360, viewportSize.X - 48)
	local availableHeight = math.max(320, viewportSize.Y - 48)
	local windowWidth = availableWidth >= 520 and math.min(availableWidth, 760) or availableWidth
	local windowHeight = availableHeight >= 430 and math.min(availableHeight, 560) or availableHeight
	local compactTabs = windowWidth < 590

	ui.window.Size = UDim2.fromOffset(windowWidth, windowHeight)
	ui.tabBar.Position = UDim2.fromOffset(14, 60)
	ui.tabBar.Size = UDim2.new(1, -28, 0, 38)
	ui.content.Position = UDim2.fromOffset(14, 108)
	ui.content.Size = UDim2.new(1, -28, 1, -150)

	for _, button in pairs(ui.tabs) do
		button.TextSize = compactTabs and 11 or 13
	end
end

local function getCurrentRoomId(payload)
	if typeof(payload) == "table" and typeof(payload.RoomId) == "string" and payload.RoomId ~= "" then
		return payload.RoomId
	end

	local currentRoomId = player:GetAttribute("CurrentRoomId")

	if typeof(currentRoomId) == "string" and currentRoomId ~= "" then
		return currentRoomId
	end

	return "Primary"
end

local function setCategory(categoryName)
	local normalized = "Chat Rooms"

	for _, allowedCategory in ipairs(CATEGORY_OPTIONS) do
		if allowedCategory == categoryName then
			normalized = categoryName
			break
		end
	end

	state.category = normalized

	if ui.categoryButton then
		ui.categoryButton.Text = "Category: " .. normalized
	end
end

local function setVisibility(isPublic)
	state.isPublic = isPublic == true

	if ui.visibilityButton then
		ui.visibilityButton.Text = state.isPublic and "Public" or "Private"
		ui.visibilityButton.BackgroundColor3 = state.isPublic
			and THEME.Confirm
			or THEME.ButtonMuted
	end
end

local function updateTabs()
	for tabName, button in pairs(ui.tabs) do
		local selected = state.activeTab == tabName
		button.BackgroundColor3 = selected and THEME.ButtonSelected or THEME.Button
		button.TextColor3 = selected and THEME.HeaderText or Color3.fromRGB(255, 246, 224)
	end
end

local function requestSettings()
	state.settingsRequestInFlight = true
	setStatus("Loading room settings...", false)
	roomSettingsRequest:FireServer("GetSettings", {
		RoomId = state.roomId,
	})
end

local function requestEditors()
	state.editorRequestInFlight = true
	roomSettingsRequest:FireServer("GetRoomEditors", {
		RoomId = state.roomId,
	})
end

local function nextFloorRequestId()
	state.floorRequestId = state.floorRequestId + 1
	return state.floorRequestId
end

local function requestFloorStyles(options)
	options = options or {}

	state.floorRequestInFlight = true
	state.applyingFloorStyleId = nil
	local requestId = nextFloorRequestId()

	if options.ClearStyles ~= false then
		state.floorStyles = {}
	end

	if options.SetStatus ~= false then
		setStatus("Loading floor styles...", false)
	end

	roomSettingsRequest:FireServer("GetRoomFloorStyles", {
		RoomId = state.roomId,
		RequestId = requestId,
		Silent = options.Silent == true,
	})
end

local function enforceTextLimit(textBox, maxLength)
	local text = textBox.Text or ""

	if #text > maxLength then
		textBox.Text = string.sub(text, 1, maxLength)
	end
end

local renderActiveTab

local function renderBasicTab()
	clearGuiObjects(ui.content)
	ui.content.CanvasPosition = Vector2.zero
	ui.content.CanvasSize = UDim2.fromOffset(0, 348)

	createLabel("RoomNameLabel", "Room Name", UDim2.fromOffset(18, 16), UDim2.new(1, -36, 0, 18), ui.content, {
		Font = Enum.Font.GothamBold,
		TextSize = 12,
	})
	ui.nameInput = createInput("RoomNameInput", "Room name", UDim2.fromOffset(18, 38), UDim2.new(1, -36, 0, 36), ui.content)

	createLabel("DescriptionLabel", "Room Description", UDim2.fromOffset(18, 88), UDim2.new(1, -36, 0, 18), ui.content, {
		Font = Enum.Font.GothamBold,
		TextSize = 12,
	})
	ui.descriptionInput = createInput(
		"RoomDescriptionInput",
		"Room description",
		UDim2.fromOffset(18, 110),
		UDim2.new(1, -36, 0, 76),
		ui.content,
		true
	)

	createLabel("CategoryLabel", "Room Category", UDim2.fromOffset(18, 202), UDim2.new(1, -36, 0, 18), ui.content, {
		Font = Enum.Font.GothamBold,
		TextSize = 12,
	})
	ui.categoryButton = createTextButton("CategoryButton", "Category: Chat Rooms", UDim2.new(1, -36, 0, 34), ui.content)
	ui.categoryButton.Position = UDim2.fromOffset(18, 224)
	ui.categoryButton.TextXAlignment = Enum.TextXAlignment.Left

	local categoryPadding = Instance.new("UIPadding")
	categoryPadding.PaddingLeft = UDim.new(0, 10)
	categoryPadding.Parent = ui.categoryButton

	ui.categoryButton.MouseButton1Click:Connect(function()
		local currentIndex = 1

		for index, categoryName in ipairs(CATEGORY_OPTIONS) do
			if categoryName == state.category then
				currentIndex = index
				break
			end
		end

		local nextIndex = currentIndex + 1

		if nextIndex > #CATEGORY_OPTIONS then
			nextIndex = 1
		end

		setCategory(CATEGORY_OPTIONS[nextIndex])
	end)

	createLabel("VisibilityLabel", "Visibility", UDim2.fromOffset(18, 272), UDim2.new(1, -36, 0, 18), ui.content, {
		Font = Enum.Font.GothamBold,
		TextSize = 12,
	})
	ui.visibilityButton = createTextButton("VisibilityButton", "Public", UDim2.fromOffset(120, 34), ui.content)
	ui.visibilityButton.Position = UDim2.fromOffset(18, 294)
	ui.visibilityButton.MouseButton1Click:Connect(function()
		setVisibility(not state.isPublic)
	end)

	ui.saveButton = createTextButton("SaveButton", "Save", UDim2.fromOffset(116, 34), ui.content)
	ui.saveButton.AnchorPoint = Vector2.new(1, 0)
	ui.saveButton.Position = UDim2.new(1, -18, 0, 294)
	ui.saveButton.BackgroundColor3 = THEME.Confirm
	ui.saveButton.MouseButton1Click:Connect(function()
		local roomName = ui.nameInput.Text or ""

		if roomName:match("^%s*$") then
			setStatus("Room name cannot be empty.", true)
			return
		end

		state.settingsRequestInFlight = true
		ui.saveButton.Active = false
		ui.saveButton.AutoButtonColor = false
		setStatus("Saving settings...", false)
		roomSettingsRequest:FireServer("UpdateSettings", {
			RoomId = state.roomId,
			DisplayName = roomName,
			Description = ui.descriptionInput.Text or "",
			Category = state.category,
			IsPublic = state.isPublic,
		})
	end)

	ui.nameInput:GetPropertyChangedSignal("Text"):Connect(function()
		enforceTextLimit(ui.nameInput, ROOM_NAME_MAX_LENGTH)
	end)
	ui.descriptionInput:GetPropertyChangedSignal("Text"):Connect(function()
		enforceTextLimit(ui.descriptionInput, ROOM_DESCRIPTION_MAX_LENGTH)
	end)
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

local function renderEditorRows()
	clearGuiObjects(ui.editorList)

	if #state.editors == 0 then
		createLabel("NoEditors", "No editors yet.", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 26), ui.editorList, {
			TextColor3 = THEME.SubtleText,
		})
		ui.editorList.CanvasSize = UDim2.fromOffset(0, 36)
		return
	end

	for index, editorEntry in ipairs(state.editors) do
		local row = Instance.new("Frame")
		row.Name = "EditorRow_" .. tostring(editorEntry.UserId or index)
		row.Position = UDim2.fromOffset(0, (index - 1) * 34)
		row.Size = UDim2.new(1, -8, 0, 30)
		row.BackgroundColor3 = THEME.PanelAlt
		row.BorderSizePixel = 0
		row.Parent = ui.editorList

		createCorner(row, 5)

		createLabel(
			"EditorName",
			getEditorDisplayText(editorEntry),
			UDim2.fromOffset(10, 0),
			UDim2.new(1, -102, 1, 0),
			row,
			{ TextTruncate = Enum.TextTruncate.AtEnd }
		)

		local removeButton = createTextButton("RemoveEditor", "Remove", UDim2.fromOffset(76, 24), row)
		removeButton.AnchorPoint = Vector2.new(1, 0.5)
		removeButton.Position = UDim2.new(1, -6, 0.5, 0)
		removeButton.BackgroundColor3 = THEME.Close
		removeButton.TextSize = 11
		removeButton.MouseButton1Click:Connect(function()
			if state.editorRequestInFlight then
				return
			end

			state.editorRequestInFlight = true
			setStatus("Removing editor...", false)
			roomSettingsRequest:FireServer("RemoveRoomEditor", {
				RoomId = state.roomId,
				TargetUserId = editorEntry.UserId,
			})
		end)
	end

	ui.editorList.CanvasSize = UDim2.fromOffset(0, (#state.editors * 34) + 8)
end

local function renderRightsTab()
	clearGuiObjects(ui.content)
	ui.content.CanvasPosition = Vector2.zero
	ui.content.CanvasSize = UDim2.fromOffset(0, 320)

	createLabel("RightsTitle", "Room Editors", UDim2.fromOffset(18, 16), UDim2.new(1, -36, 0, 24), ui.content, {
		Font = Enum.Font.GothamBold,
		TextSize = 14,
	})
	createLabel(
		"RightsNote",
		"Editors can help modify this room.",
		UDim2.fromOffset(18, 40),
		UDim2.new(1, -36, 0, 20),
		ui.content,
		{ TextColor3 = THEME.SubtleText, TextSize = 12 }
	)

	ui.editorInput = createInput(
		"EditorInput",
		"Username or UserId",
		UDim2.fromOffset(18, 76),
		UDim2.new(1, -150, 0, 34),
		ui.content
	)
	ui.editorAddButton = createTextButton("AddEditorButton", "Add", UDim2.fromOffset(104, 34), ui.content)
	ui.editorAddButton.AnchorPoint = Vector2.new(1, 0)
	ui.editorAddButton.Position = UDim2.new(1, -18, 0, 76)
	ui.editorAddButton.BackgroundColor3 = THEME.Confirm
	ui.editorAddButton.MouseButton1Click:Connect(function()
		if state.editorRequestInFlight then
			return
		end

		local targetInput = (ui.editorInput.Text or ""):match("^%s*(.-)%s*$")

		if targetInput == "" then
			setStatus("Invalid user.", true)
			return
		end

		state.editorRequestInFlight = true
		setStatus("Adding editor...", false)
		roomSettingsRequest:FireServer("AddRoomEditor", {
			RoomId = state.roomId,
			TargetUserInput = targetInput,
		})
	end)

	ui.editorList = Instance.new("ScrollingFrame")
	ui.editorList.Name = "EditorList"
	ui.editorList.Position = UDim2.fromOffset(18, 130)
	ui.editorList.Size = UDim2.new(1, -36, 1, -148)
	ui.editorList.BackgroundTransparency = 1
	ui.editorList.BorderSizePixel = 0
	ui.editorList.ScrollBarThickness = 6
	ui.editorList.CanvasSize = UDim2.fromOffset(0, 0)
	ui.editorList.Parent = ui.content

	renderEditorRows()
end

local function renderFloorTab()
	clearGuiObjects(ui.content)
	ui.content.CanvasPosition = Vector2.zero

	local styles = typeof(state.floorStyles) == "table" and state.floorStyles or {}
	local cardHeight = 96
	local cardGap = 10
	local contentHeight = math.max(150, 72 + (#styles * (cardHeight + cardGap)))

	ui.content.CanvasSize = UDim2.fromOffset(0, contentHeight)

	createLabel("FloorTitle", "Floor Style", UDim2.fromOffset(18, 16), UDim2.new(1, -36, 0, 24), ui.content, {
		Font = Enum.Font.GothamBold,
		TextSize = 14,
	})
	createLabel(
		"FloorNote",
		"Choose a floor style for this room.",
		UDim2.fromOffset(18, 40),
		UDim2.new(1, -36, 0, 20),
		ui.content,
		{ TextColor3 = THEME.SubtleText, TextSize = 12 }
	)

	if #styles == 0 then
		createLabel(
			"FloorEmpty",
			state.floorRequestInFlight and "Loading floor styles..." or "Room styling is only available in your own rooms.",
			UDim2.fromOffset(18, 78),
			UDim2.new(1, -36, 0, 26),
			ui.content,
			{ TextColor3 = THEME.SubtleText, TextSize = 12, Font = Enum.Font.GothamMedium }
		)
		return
	end

	for index, style in ipairs(styles) do
		local floorStyleId = tostring(style.FloorStyleId or "")
		local isCurrent = style.Current == true or floorStyleId == state.currentFloorStyleId
		local isApplying = state.applyingFloorStyleId == floorStyleId
		local isUsable = style.Usable ~= false
		local lockedReason = tostring(style.LockedReason or "Not owned")
		local y = 72 + ((index - 1) * (cardHeight + cardGap))

		local card = Instance.new("Frame")
		card.Name = "FloorStyleCard_" .. floorStyleId
		card.Position = UDim2.fromOffset(18, y)
		card.Size = UDim2.new(1, -36, 0, cardHeight)
		card.BackgroundColor3 = isCurrent
			and THEME.PanelAlt
			or (isUsable and Color3.fromRGB(255, 248, 230) or Color3.fromRGB(238, 232, 216))
		card.BorderSizePixel = 0
		card.Parent = ui.content

		createCorner(card, 6)
		createStroke(
			card,
			isCurrent and THEME.Confirm or THEME.PanelStroke,
			1,
			isCurrent and 0.1 or (isUsable and 0.25 or 0.45)
		)

		createLabel(
			"StyleName",
			tostring(style.DisplayName or floorStyleId),
			UDim2.fromOffset(12, 8),
			UDim2.new(1, -132, 0, 22),
			card,
			{ Font = Enum.Font.GothamBold, TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd }
		)
		createLabel(
			"StyleDescription",
			tostring(style.Description or ""),
			UDim2.fromOffset(12, 32),
			UDim2.new(1, -132, 0, 40),
			card,
			{ TextColor3 = THEME.SubtleText, TextSize = 11, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }
		)

		if isCurrent then
			local currentBadge = createTextButton("CurrentBadge", "Current", UDim2.fromOffset(86, 28), card)
			currentBadge.AnchorPoint = Vector2.new(1, 0)
			currentBadge.Position = UDim2.new(1, -12, 0, 10)
			currentBadge.BackgroundColor3 = THEME.Confirm
			currentBadge.Active = false
			currentBadge.AutoButtonColor = false
		elseif isUsable then
			local applyButton = createTextButton(
				"ApplyButton",
				isApplying and "Applying..." or "Apply",
				UDim2.fromOffset(92, 30),
				card
			)
			applyButton.AnchorPoint = Vector2.new(1, 0)
			applyButton.Position = UDim2.new(1, -12, 0, 10)
			applyButton.BackgroundColor3 = THEME.Confirm
			applyButton.Active = state.floorRequestInFlight ~= true
			applyButton.AutoButtonColor = applyButton.Active
			applyButton.MouseButton1Click:Connect(function()
				if state.floorRequestInFlight then
					return
				end

				state.floorRequestInFlight = true
				state.applyingFloorStyleId = floorStyleId
				local requestId = nextFloorRequestId()
				applyButton.Text = "Applying..."
				applyButton.Active = false
				applyButton.AutoButtonColor = false
				setStatus("Applying floor style...", false)
				roomSettingsRequest:FireServer("ApplyRoomFloorStyle", {
					RoomId = state.roomId,
					FloorStyleId = floorStyleId,
					RequestId = requestId,
				})
			end)
		else
			local lockedBadge = createTextButton("LockedBadge", "Locked", UDim2.fromOffset(92, 30), card)
			lockedBadge.AnchorPoint = Vector2.new(1, 0)
			lockedBadge.Position = UDim2.new(1, -12, 0, 10)
			lockedBadge.BackgroundColor3 = THEME.ButtonMuted
			lockedBadge.Active = false
			lockedBadge.AutoButtonColor = false

			createLabel(
				"LockedReason",
				lockedReason,
				UDim2.new(1, -116, 0, 44),
				UDim2.fromOffset(104, 34),
				card,
				{
					TextColor3 = THEME.SubtleText,
					TextSize = 11,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Right,
					TextYAlignment = Enum.TextYAlignment.Top,
				}
			)
		end
	end
end

local function renderPlaceholderTab(message, includeDisabledOptions)
	clearGuiObjects(ui.content)
	ui.content.CanvasPosition = Vector2.zero
	ui.content.CanvasSize = UDim2.fromOffset(0, includeDisabledOptions and 210 or 90)

	createLabel(
		"PlaceholderMessage",
		message,
		UDim2.fromOffset(24, 24),
		UDim2.new(1, -48, 0, 26),
		ui.content,
		{ Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = THEME.Text }
	)

	if includeDisabledOptions then
		local labels = {
			"Who can mute",
			"Who can kick",
			"Who can ban",
		}

		for index, labelText in ipairs(labels) do
			local button = createTextButton(
				"DisabledOption" .. tostring(index),
				labelText .. ": Coming Soon",
				UDim2.new(1, -48, 0, 34),
				ui.content
			)
			button.Position = UDim2.fromOffset(24, 64 + ((index - 1) * 42))
			button.BackgroundColor3 = THEME.ButtonMuted
			button.Active = false
			button.AutoButtonColor = false
		end
	end
end

renderActiveTab = function()
	updateTabs()

	if state.activeTab == TAB_BASIC then
		renderBasicTab()
		requestSettings()
	elseif state.activeTab == TAB_RIGHTS then
		renderRightsTab()
		requestEditors()
	elseif state.activeTab == TAB_FLOOR then
		requestFloorStyles()
		renderFloorTab()
	elseif state.activeTab == TAB_BANNED then
		renderPlaceholderTab("Banned users are coming soon.", false)
	elseif state.activeTab == TAB_MODERATION then
		renderPlaceholderTab("Moderation settings are coming soon.", true)
	end
end

local function applySettings(settings)
	if typeof(settings) ~= "table" then
		return
	end

	if typeof(settings.RoomId) == "string" and settings.RoomId ~= "" then
		state.roomId = settings.RoomId
	end

	if ui.nameInput then
		ui.nameInput.Text = tostring(settings.DisplayName or "")
	end

	if ui.descriptionInput then
		ui.descriptionInput.Text = tostring(settings.Description or "")
	end

	setCategory(settings.Category or state.category)
	setVisibility(settings.IsPublic == true)
end

local function applyFloorStyles(response)
	if typeof(response.CurrentFloorStyleId) == "string" then
		state.currentFloorStyleId = response.CurrentFloorStyleId
	end

	if typeof(response.Styles) == "table" then
		state.floorStyles = response.Styles
	end

	if state.activeTab == TAB_FLOOR then
		renderFloorTab()
	end
end

local function openWindow(payload)
	state.isOpen = true
	state.roomId = getCurrentRoomId(payload)
	state.activeTab = TAB_BASIC
	state.editors = {}
	state.floorStyles = {}
	state.currentFloorStyleId = nil
	state.editorRequestInFlight = false
	state.settingsRequestInFlight = false
	state.floorRequestInFlight = false
	state.applyingFloorStyleId = nil
	state.restoreNavigatorState = nil
	state.openRoomName = player:GetAttribute("CurrentRoomName")

	if typeof(payload) == "table"
		and payload.Source == "RoomNavigator"
		and typeof(payload.RestoreState) == "table" then

		state.restoreNavigatorState = payload.RestoreState
	end

	ui.backdrop.Visible = true
	applyWindowLayout()
	setStatus("", false)
	majorMenuOpened:Fire("RoomSettings")
	renderActiveTab()

	if state.activeTab ~= TAB_FLOOR then
		requestFloorStyles({
			ClearStyles = false,
			SetStatus = false,
			Silent = true,
		})
	end
end

local function closeWindow(options)
	local shouldRestoreNavigator = state.restoreNavigatorState ~= nil
		and (typeof(options) ~= "table" or options.RestoreNavigator ~= false)
	local restoreState = state.restoreNavigatorState

	state.isOpen = false
	state.restoreNavigatorState = nil
	state.openRoomName = nil
	ui.backdrop.Visible = false
	setStatus("", false)

	if shouldRestoreNavigator then
		openRoomNavigator:Fire({
			Mode = restoreState.Mode,
			RestoreState = restoreState,
		})
	end
end

for tabName, button in pairs(ui.tabs) do
	button.MouseButton1Click:Connect(function()
		if state.activeTab == tabName then
			return
		end

		state.activeTab = tabName
		setStatus("", false)
		renderActiveTab()
	end)
end

ui.closeButton.MouseButton1Click:Connect(function()
	closeWindow()
end)

openRoomSettings.Event:Connect(openWindow)

closeMajorMenus.Event:Connect(function()
	if state.isOpen then
		closeWindow({ RestoreNavigator = false })
	end
end)

majorMenuOpened.Event:Connect(function(menuName)
	if state.isOpen and menuName ~= "RoomSettings" then
		closeWindow({ RestoreNavigator = false })
	end
end)

local function closeForRoomChange()
	if state.isOpen and player:GetAttribute("CurrentRoomName") ~= state.openRoomName then
		closeWindow({ RestoreNavigator = false })
	end
end

player:GetAttributeChangedSignal("CurrentRoomName"):Connect(closeForRoomChange)
player:GetAttributeChangedSignal("CurrentRoomType"):Connect(closeForRoomChange)

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if state.isOpen then
		applyWindowLayout()
	end
end)

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if state.isOpen then
			applyWindowLayout()
		end
	end)
end

roomSettingsResult.OnClientEvent:Connect(function(response)
	if not state.isOpen or typeof(response) ~= "table" then
		return
	end

	local responseKind = response.Kind
	local action = response.Action

	if responseKind == "GetRoomFloorStyles" then
		action = "GetRoomFloorStyles"
	elseif responseKind == "ApplyRoomFloorStyle" then
		action = "ApplyRoomFloorStyle"
	elseif responseKind ~= "RoomSettings" then
		return
	end

	local responseRoomId = response.RoomId

	if typeof(response.Settings) == "table" then
		responseRoomId = response.Settings.RoomId or responseRoomId
	end

	if typeof(responseRoomId) == "string" and responseRoomId ~= "" and responseRoomId ~= state.roomId then
		return
	end

	if action == "GetRoomFloorStyles" or action == "ApplyRoomFloorStyle" then
		local responseRequestId = response.RequestId

		if typeof(responseRequestId) == "number" and responseRequestId < state.floorRequestId then
			return
		end
	end

	if action == "GetSettings" or action == "UpdateSettings" then
		state.settingsRequestInFlight = false

		if ui.saveButton then
			ui.saveButton.Active = true
			ui.saveButton.AutoButtonColor = true
		end
	elseif action == "GetRoomEditors" or action == "AddRoomEditor" or action == "RemoveRoomEditor" then
		state.editorRequestInFlight = false
	elseif action == "GetRoomFloorStyles" or action == "ApplyRoomFloorStyle" then
		state.floorRequestInFlight = false
		state.applyingFloorStyleId = nil
	end

	if response.Success ~= true then
		if action == "GetRoomFloorStyles" or action == "ApplyRoomFloorStyle" then
			applyFloorStyles(response)
		end

		setStatus(response.Message or "Room settings update failed.", true)
		return
	end

	if action == "GetRoomFloorStyles" or action == "ApplyRoomFloorStyle" then
		applyFloorStyles(response)

		if action == "ApplyRoomFloorStyle" then
			setStatus(response.Message or "Floor updated.", false)
			requestFloorStyles({
				ClearStyles = false,
				SetStatus = false,
				Silent = true,
			})
		elseif response.Silent ~= true then
			setStatus("", false)
		end

		return
	end

	if typeof(response.Settings) == "table" then
		applySettings(response.Settings)
	end

	if typeof(response.Editors) == "table" then
		state.editors = response.Editors

		if state.activeTab == TAB_RIGHTS and ui.editorList then
			renderEditorRows()
		end
	end

	if action == "UpdateSettings" then
		setStatus(response.Message or "Room settings saved.", false)
	elseif action == "AddRoomEditor" or action == "RemoveRoomEditor" then
		if action == "AddRoomEditor" and ui.editorInput then
			ui.editorInput.Text = ""
		end

		setStatus("Auto saved.", false)
	elseif action == "GetSettings" or action == "GetRoomEditors" then
		setStatus("", false)
	end
end)
