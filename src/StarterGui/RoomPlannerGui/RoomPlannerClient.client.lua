-- StarterGui/RoomPlannerGui/RoomPlannerClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local roomNavigatorRequest = remoteEvents:WaitForChild("RoomNavigatorRequest")
local roomNavigatorResult = remoteEvents:WaitForChild("RoomNavigatorResult")
local roomListRequest = remoteEvents:WaitForChild("RoomListRequest")
local roomListUpdate = remoteEvents:WaitForChild("RoomListUpdate")

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 170

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

local ROOM_NAME_MAX_LENGTH = 30
local ROOM_DESCRIPTION_MAX_LENGTH = 100
local MENU_NAME = "RoomPlanner"
local MAX_OWNED_ROOMS = 3
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
local LAYOUTS = {
	{
		Id = "StarterStudio",
		DisplayName = "Starter Studio",
		LayoutId = "Free_036_A",
		DefaultRoomName = "Starter Studio",
		SizeText = "36 tiles",
		Description = "A simple starter layout.",
		GridColumns = 5,
		GridRows = 7,
		IsCreatable = true,
	},
	{
		Id = "CozyCorner",
		DisplayName = "Cozy Corner",
		SizeText = "Coming Soon",
		Description = "A compact social layout.",
		GridColumns = 4,
		GridRows = 5,
		IsCreatable = false,
	},
	{
		Id = "WideSuite",
		DisplayName = "Wide Suite",
		SizeText = "Coming Soon",
		Description = "A larger room layout.",
		GridColumns = 7,
		GridRows = 5,
		IsCreatable = false,
	},
}

local state = {
	isOpen = false,
	selectedLayoutId = "StarterStudio",
	requestInFlight = false,
	roomCountKnown = false,
	ownedRoomCount = 0,
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

local openRoomPlanner = getOrCreateClientEvent("OpenRoomPlanner")
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

local function getLayoutById(layoutId)
	for _, layoutInfo in ipairs(LAYOUTS) do
		if layoutInfo.Id == layoutId then
			return layoutInfo
		end
	end

	return LAYOUTS[1]
end

local function setStatus(message, isError)
	ui.status.Text = tostring(message or "")
	ui.status.TextColor3 = isError and THEME.Error or THEME.Success
end

local function isMaxRoomLimitReached()
	return state.roomCountKnown == true and state.ownedRoomCount >= MAX_OWNED_ROOMS
end

local function showLimitPrompt()
	if ui.limitPrompt then
		ui.limitPrompt.Visible = true
	end

	setStatus("Maximum room limit reached.", true)
end

local function enforceTextLimit(textBox, maxLength)
	local text = textBox.Text or ""

	if #text > maxLength then
		textBox.Text = string.sub(text, 1, maxLength)
	end
end

local function drawPreviewGrid(parent, layoutInfo)
	local columns = layoutInfo.GridColumns or 5
	local rows = layoutInfo.GridRows or 5
	local cellSize = math.floor(math.min(88 / columns, 72 / rows))
	local gridWidth = cellSize * columns
	local gridHeight = cellSize * rows
	local grid = Instance.new("Frame")
	grid.Name = "GridPreview"
	grid.AnchorPoint = Vector2.new(1, 0.5)
	grid.Position = UDim2.new(1, -12, 0.5, 0)
	grid.Size = UDim2.fromOffset(gridWidth, gridHeight)
	grid.BackgroundColor3 = Color3.fromRGB(214, 190, 146)
	grid.BorderSizePixel = 0
	grid.Parent = parent

	createCorner(grid, 4)

	for rowIndex = 1, rows do
		for columnIndex = 1, columns do
			local cell = Instance.new("Frame")
			cell.Name = "Cell"
			cell.Position = UDim2.fromOffset((columnIndex - 1) * cellSize + 1, (rowIndex - 1) * cellSize + 1)
			cell.Size = UDim2.fromOffset(math.max(2, cellSize - 2), math.max(2, cellSize - 2))
			cell.BackgroundColor3 = Color3.fromRGB(251, 239, 206)
			cell.BorderSizePixel = 0
			cell.Parent = grid
		end
	end
end

local function updateCreateButton()
	local selectedLayout = getLayoutById(state.selectedLayoutId)
	local canCreate = selectedLayout.IsCreatable == true and not state.requestInFlight
	local atMaxRooms = isMaxRoomLimitReached()

	ui.createButton.Active = canCreate
	ui.createButton.AutoButtonColor = canCreate
	ui.createButton.Text = state.requestInFlight and "Creating..." or (atMaxRooms and "Limit Reached" or "Create Room")
	ui.createButton.BackgroundColor3 = canCreate
		and (atMaxRooms and THEME.ButtonMuted or THEME.Confirm)
		or THEME.ButtonMuted
end

local function renderLayoutCards()
	for _, child in ipairs(ui.layoutList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for index, layoutInfo in ipairs(LAYOUTS) do
		local isSelected = layoutInfo.Id == state.selectedLayoutId
		local isCreatable = layoutInfo.IsCreatable == true
		local card = Instance.new("TextButton")
		card.Name = layoutInfo.Id .. "Card"
		card.LayoutOrder = index
		card.Size = UDim2.new(1, 0, 0, 92)
		card.BackgroundColor3 = isSelected and Color3.fromRGB(248, 235, 200) or THEME.PanelAlt
		card.BorderSizePixel = 0
		card.Text = ""
		card.AutoButtonColor = isCreatable
		card.Parent = ui.layoutList

		createCorner(card, 7)
		createStroke(
			card,
			isSelected and Color3.fromRGB(138, 102, 58) or THEME.PanelStroke,
			isSelected and 2 or 1,
			isCreatable and 0 or 0.35
		)
		card.MouseButton1Click:Connect(function()
			if not isCreatable then
				setStatus(layoutInfo.DisplayName .. " is coming soon.", true)
				return
			end

			state.selectedLayoutId = layoutInfo.Id
			if isMaxRoomLimitReached() then
				setStatus("Maximum room limit reached.", true)
			else
				setStatus("Ready to create " .. layoutInfo.DisplayName .. ".", false)
			end
			renderLayoutCards()
			updateCreateButton()
		end)

		createLabel("Name", layoutInfo.DisplayName, UDim2.fromOffset(12, 8), UDim2.new(1, -128, 0, 18), card, {
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		createLabel(
			"Meta",
			"Size: " .. layoutInfo.SizeText,
			UDim2.fromOffset(12, 30),
			UDim2.new(1, -128, 0, 16),
			card,
			{ TextColor3 = THEME.SubtleText, TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd }
		)
		createLabel(
			"Description",
			layoutInfo.Description,
			UDim2.fromOffset(12, 50),
			UDim2.new(1, -128, 0, 34),
			card,
			{ TextColor3 = THEME.SubtleText, TextSize = 11, TextWrapped = true }
		)

		drawPreviewGrid(card, layoutInfo)

		local statusBadge = createLabel(
			"SelectionStatus",
			isSelected and "Selected" or (isCreatable and "Click card" or "Coming Soon"),
			UDim2.new(1, -92, 1, -30),
			UDim2.fromOffset(80, 22),
			card,
			{
				TextColor3 = isCreatable and THEME.HeaderText or THEME.SubtleText,
				TextSize = 11,
				Font = Enum.Font.GothamBold,
				TextXAlignment = Enum.TextXAlignment.Center,
			}
		)
		statusBadge.BackgroundColor3 = isSelected and THEME.ButtonSelected or (isCreatable and THEME.Button or Color3.fromRGB(214, 204, 185))
		statusBadge.BackgroundTransparency = 0
		createCorner(statusBadge, 5)
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
ui.window.Name = "RoomPlannerWindow"
ui.window.AnchorPoint = Vector2.new(0.5, 0.5)
ui.window.Position = UDim2.fromScale(0.5, 0.5)
ui.window.Size = UDim2.fromOffset(760, 520)
ui.window.BackgroundColor3 = THEME.Paper
ui.window.BorderSizePixel = 0
ui.window.Parent = ui.backdrop

createCorner(ui.window, 8)
createStroke(ui.window, THEME.Header, 2, 0)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(360, 330)
sizeConstraint.MaxSize = Vector2.new(840, 620)
sizeConstraint.Parent = ui.window

ui.header = Instance.new("Frame")
ui.header.Name = "Header"
ui.header.Size = UDim2.new(1, 0, 0, 50)
ui.header.BackgroundColor3 = THEME.Header
ui.header.BorderSizePixel = 0
ui.header.Parent = ui.window

createCorner(ui.header, 8)

createLabel("Title", "Room Planner", UDim2.fromOffset(18, 0), UDim2.new(1, -72, 1, 0), ui.header, {
	TextColor3 = THEME.HeaderText,
	TextSize = 18,
	Font = Enum.Font.GothamBold,
})

ui.closeButton = createTextButton("CloseButton", "X", UDim2.fromOffset(32, 30), ui.header)
ui.closeButton.AnchorPoint = Vector2.new(1, 0.5)
ui.closeButton.Position = UDim2.new(1, -12, 0.5, 0)
ui.closeButton.BackgroundColor3 = THEME.Close

ui.body = Instance.new("ScrollingFrame")
ui.body.Name = "Body"
ui.body.Position = UDim2.fromOffset(18, 68)
ui.body.Size = UDim2.new(1, -36, 1, -142)
ui.body.BackgroundTransparency = 1
ui.body.BorderSizePixel = 0
ui.body.ScrollBarThickness = 6
ui.body.ScrollingDirection = Enum.ScrollingDirection.Y
ui.body.CanvasSize = UDim2.fromOffset(0, 0)
ui.body.Parent = ui.window

ui.leftPanel = Instance.new("Frame")
ui.leftPanel.Name = "RoomDetails"
ui.leftPanel.Position = UDim2.fromOffset(0, 0)
ui.leftPanel.Size = UDim2.new(0.42, -12, 1, -8)
ui.leftPanel.BackgroundColor3 = THEME.Panel
ui.leftPanel.BorderSizePixel = 0
ui.leftPanel.Parent = ui.body

createCorner(ui.leftPanel, 7)
createStroke(ui.leftPanel, THEME.PanelStroke, 1, 0.15)

createLabel("DetailsTitle", "Room Details", UDim2.fromOffset(16, 14), UDim2.new(1, -32, 0, 22), ui.leftPanel, {
	Font = Enum.Font.GothamBold,
	TextSize = 15,
})
createLabel("NameLabel", "Room Name", UDim2.fromOffset(16, 54), UDim2.new(1, -32, 0, 18), ui.leftPanel, {
	Font = Enum.Font.GothamBold,
	TextSize = 12,
})
ui.nameInput = createInput("RoomNameInput", "Room name", UDim2.fromOffset(16, 76), UDim2.new(1, -32, 0, 36), ui.leftPanel)

createLabel("DescriptionLabel", "Description", UDim2.fromOffset(16, 128), UDim2.new(1, -32, 0, 18), ui.leftPanel, {
	Font = Enum.Font.GothamBold,
	TextSize = 12,
})
ui.descriptionInput = createInput(
	"RoomDescriptionInput",
	"Optional description",
	UDim2.fromOffset(16, 150),
	UDim2.new(1, -32, 0, 86),
	ui.leftPanel,
	true
)

createLabel("CategoryLabel", "Category", UDim2.fromOffset(16, 252), UDim2.new(1, -32, 0, 18), ui.leftPanel, {
	Font = Enum.Font.GothamBold,
	TextSize = 12,
})
ui.categoryButton = createTextButton("CategoryPlaceholder", "Category: Chat Rooms", UDim2.new(1, -32, 0, 34), ui.leftPanel)
ui.categoryButton.Position = UDim2.fromOffset(16, 274)
ui.categoryButton.BackgroundColor3 = THEME.ButtonMuted
ui.categoryButton.TextXAlignment = Enum.TextXAlignment.Left
ui.categoryButton.Active = false
ui.categoryButton.AutoButtonColor = false

local categoryPadding = Instance.new("UIPadding")
categoryPadding.PaddingLeft = UDim.new(0, 10)
categoryPadding.Parent = ui.categoryButton

createLabel(
	"CategoryNote",
	"More room categories and requirements will be added later.",
	UDim2.fromOffset(16, 316),
	UDim2.new(1, -32, 0, 40),
	ui.leftPanel,
	{ TextWrapped = true, TextColor3 = THEME.SubtleText, TextSize = 12 }
)

ui.rightPanel = Instance.new("Frame")
ui.rightPanel.Name = "LayoutPanel"
ui.rightPanel.Position = UDim2.new(0.42, 12, 0, 0)
ui.rightPanel.Size = UDim2.new(0.58, -12, 1, -8)
ui.rightPanel.BackgroundColor3 = THEME.Panel
ui.rightPanel.BorderSizePixel = 0
ui.rightPanel.Parent = ui.body

createCorner(ui.rightPanel, 7)
createStroke(ui.rightPanel, THEME.PanelStroke, 1, 0.15)

createLabel("LayoutTitle", "Choose Layout", UDim2.fromOffset(16, 14), UDim2.new(1, -32, 0, 22), ui.rightPanel, {
	Font = Enum.Font.GothamBold,
	TextSize = 15,
})

ui.layoutList = Instance.new("Frame")
ui.layoutList.Name = "LayoutCards"
ui.layoutList.Position = UDim2.fromOffset(16, 48)
ui.layoutList.Size = UDim2.new(1, -32, 1, -64)
ui.layoutList.BackgroundTransparency = 1
ui.layoutList.Parent = ui.rightPanel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 10)
layout.Parent = ui.layoutList

ui.footer = Instance.new("Frame")
ui.footer.Name = "Footer"
ui.footer.AnchorPoint = Vector2.new(0, 1)
ui.footer.Position = UDim2.new(0, 18, 1, -16)
ui.footer.Size = UDim2.new(1, -36, 0, 56)
ui.footer.BackgroundTransparency = 1
ui.footer.Parent = ui.window

createLabel(
	"RequirementNote",
	"Cost: Free for now. Requirements are checked by the server.",
	UDim2.fromOffset(0, 5),
	UDim2.new(1, -160, 0, 22),
	ui.footer,
	{ TextColor3 = THEME.SubtleText, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd }
)
ui.status = createLabel(
	"Status",
	"",
	UDim2.fromOffset(0, 29),
	UDim2.new(1, -160, 0, 20),
	ui.footer,
	{ TextColor3 = THEME.Success, TextSize = 12, Font = Enum.Font.GothamMedium }
)

ui.createButton = createTextButton("CreateRoomButton", "Create Room", UDim2.fromOffset(138, 36), ui.footer)
ui.createButton.AnchorPoint = Vector2.new(1, 0.5)
ui.createButton.Position = UDim2.new(1, 0, 0.5, 0)
ui.createButton.BackgroundColor3 = THEME.Confirm

ui.limitPrompt = Instance.new("Frame")
ui.limitPrompt.Name = "RoomLimitPrompt"
ui.limitPrompt.AnchorPoint = Vector2.new(0.5, 0.5)
ui.limitPrompt.Position = UDim2.fromScale(0.5, 0.5)
ui.limitPrompt.Size = UDim2.fromOffset(360, 156)
ui.limitPrompt.BackgroundColor3 = THEME.Panel
ui.limitPrompt.BorderSizePixel = 0
ui.limitPrompt.Visible = false
ui.limitPrompt.ZIndex = 20
ui.limitPrompt.Parent = ui.backdrop

createCorner(ui.limitPrompt, 8)
createStroke(ui.limitPrompt, THEME.Header, 2, 0)

local promptTitle = createLabel("PromptTitle", "Room limit reached", UDim2.fromOffset(18, 14), UDim2.new(1, -36, 0, 24), ui.limitPrompt, {
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextColor3 = THEME.Text,
})
promptTitle.ZIndex = 21

local promptMessage = createLabel(
	"PromptMessage",
	"You have reached the maximum number of rooms.",
	UDim2.fromOffset(18, 48),
	UDim2.new(1, -36, 0, 42),
	ui.limitPrompt,
	{ TextWrapped = true, TextColor3 = THEME.SubtleText, TextSize = 13 }
)
promptMessage.ZIndex = 21

ui.limitPromptOkButton = createTextButton("PromptOkButton", "OK", UDim2.fromOffset(96, 32), ui.limitPrompt)
ui.limitPromptOkButton.AnchorPoint = Vector2.new(0.5, 1)
ui.limitPromptOkButton.Position = UDim2.new(0.5, 0, 1, -16)
ui.limitPromptOkButton.ZIndex = 21
ui.limitPromptOkButton.MouseButton1Click:Connect(function()
	ui.limitPrompt.Visible = false
end)

ui.nameInput:GetPropertyChangedSignal("Text"):Connect(function()
	enforceTextLimit(ui.nameInput, ROOM_NAME_MAX_LENGTH)
end)
ui.descriptionInput:GetPropertyChangedSignal("Text"):Connect(function()
	enforceTextLimit(ui.descriptionInput, ROOM_DESCRIPTION_MAX_LENGTH)
end)

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
	local availableHeight = math.max(330, viewportSize.Y - 48)
	local windowWidth = availableWidth >= 520 and math.min(availableWidth, 840) or availableWidth
	local windowHeight = availableHeight >= 430 and math.min(availableHeight, 620) or availableHeight
	local isNarrow = windowWidth < 700
	local bodyHeight = windowHeight - 142

	ui.window.Size = UDim2.fromOffset(windowWidth, windowHeight)
	ui.body.Position = UDim2.fromOffset(18, 68)
	ui.body.Size = UDim2.new(1, -36, 1, -142)
	ui.footer.Position = UDim2.new(0, 18, 1, -16)
	ui.footer.Size = UDim2.new(1, -36, 0, 56)

	if isNarrow then
		ui.leftPanel.Position = UDim2.fromOffset(0, 0)
		ui.leftPanel.Size = UDim2.new(1, -12, 0, 372)
		ui.rightPanel.Position = UDim2.fromOffset(0, 386)
		ui.rightPanel.Size = UDim2.new(1, -12, 0, 346)
		ui.body.CanvasSize = UDim2.fromOffset(0, 748)
	else
		local panelHeight = math.max(bodyHeight - 8, 372)

		ui.leftPanel.Position = UDim2.fromOffset(0, 0)
		ui.leftPanel.Size = UDim2.new(0.42, -12, 0, panelHeight)
		ui.rightPanel.Position = UDim2.new(0.42, 12, 0, 0)
		ui.rightPanel.Size = UDim2.new(0.58, -12, 0, panelHeight)
		ui.body.CanvasSize = UDim2.fromOffset(0, panelHeight + 8)
	end
end

local function countOwnedRooms(roomList)
	if typeof(roomList) ~= "table" then
		return nil
	end

	local count = 0

	for _, roomData in ipairs(roomList) do
		if typeof(roomData) == "table"
			and roomData.RoomType == "PlayerRoom"
			and roomData.IsOwner == true then

			count += 1
		end
	end

	return count
end

local function refreshRoomLimitStatus()
	if state.requestInFlight then
		updateCreateButton()
		return
	end

	if isMaxRoomLimitReached() then
		setStatus("Maximum room limit reached.", true)
	else
		local selectedLayout = getLayoutById(state.selectedLayoutId)

		if selectedLayout.IsCreatable == true then
			setStatus("Ready to create " .. selectedLayout.DisplayName .. ".", false)
		else
			setStatus(selectedLayout.DisplayName .. " is coming soon.", true)
		end
	end

	updateCreateButton()
end

local function applyRoomList(roomList)
	local ownedRoomCount = countOwnedRooms(roomList)

	if ownedRoomCount == nil then
		return
	end

	state.roomCountKnown = true
	state.ownedRoomCount = ownedRoomCount

	if state.isOpen then
		refreshRoomLimitStatus()
	end
end

local function isMaxLimitMessage(message)
	if typeof(message) ~= "string" then
		return false
	end

	return string.find(string.lower(message), "maximum room limit", 1, true) ~= nil
end

local function openWindow(payload)
	state.isOpen = true
	state.requestInFlight = false
	state.selectedLayoutId = "StarterStudio"
	state.restoreNavigatorState = nil
	state.openRoomName = player:GetAttribute("CurrentRoomName")

	if typeof(payload) == "table"
		and payload.Source == "RoomNavigator"
		and typeof(payload.RestoreState) == "table" then

		state.restoreNavigatorState = payload.RestoreState
	end

	ui.nameInput.Text = "Starter Studio"
	ui.descriptionInput.Text = ""
	ui.backdrop.Visible = true
	ui.limitPrompt.Visible = false
	ui.body.CanvasPosition = Vector2.zero
	applyWindowLayout()
	if state.roomCountKnown then
		refreshRoomLimitStatus()
	else
		setStatus("Checking room slots...", false)
	end
	renderLayoutCards()
	updateCreateButton()
	roomListRequest:FireServer()
	majorMenuOpened:Fire(MENU_NAME)
end

local function closeWindow(options)
	local shouldRestoreNavigator = state.restoreNavigatorState ~= nil
		and (typeof(options) ~= "table" or options.RestoreNavigator ~= false)
	local restoreState = state.restoreNavigatorState

	state.isOpen = false
	state.requestInFlight = false
	state.restoreNavigatorState = nil
	state.openRoomName = nil
	ui.backdrop.Visible = false
	ui.limitPrompt.Visible = false
	setStatus("", false)
	updateCreateButton()

	if shouldRestoreNavigator then
		openRoomNavigator:Fire({
			Mode = restoreState.Mode,
			RestoreState = restoreState,
		})
	end
end

ui.closeButton.MouseButton1Click:Connect(function()
	closeWindow()
end)
ui.createButton.MouseButton1Click:Connect(function()
	if state.requestInFlight then
		return
	end

	local selectedLayout = getLayoutById(state.selectedLayoutId)

	if selectedLayout.IsCreatable ~= true then
		setStatus(selectedLayout.DisplayName .. " is coming soon.", true)
		return
	end

	if isMaxRoomLimitReached() then
		showLimitPrompt()
		updateCreateButton()
		return
	end

	local roomName = ui.nameInput.Text or ""

	if roomName:match("^%s*$") then
		setStatus("Room name cannot be empty.", true)
		return
	end

	state.requestInFlight = true
	setStatus("Creating room...", false)
	updateCreateButton()
	roomNavigatorRequest:FireServer("CreateOwnedRoom", {
		LayoutId = selectedLayout.LayoutId,
		DisplayName = roomName,
		Category = "Chat Rooms",
		Description = ui.descriptionInput.Text or "",
		IsPublic = true,
	})
end)

openRoomPlanner.Event:Connect(openWindow)

closeMajorMenus.Event:Connect(function()
	if state.isOpen then
		closeWindow({ RestoreNavigator = false })
	end
end)

majorMenuOpened.Event:Connect(function(menuName)
	if state.isOpen and menuName ~= MENU_NAME then
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

roomListUpdate.OnClientEvent:Connect(function(roomList)
	applyRoomList(roomList)
end)

roomNavigatorResult.OnClientEvent:Connect(function(response)
	if not state.isOpen or not state.requestInFlight then
		return
	end

	if typeof(response) ~= "table" or response.Kind ~= "CreateOwnedRoom" then
		return
	end

	state.requestInFlight = false

	if typeof(response.Rooms) == "table" then
		applyRoomList(response.Rooms)
	end

	updateCreateButton()

	if response.Success == true then
		setStatus(response.Message or "Room created.", false)
		roomListRequest:FireServer()

		task.delay(0.65, function()
			if state.isOpen and not state.requestInFlight then
				closeWindow()
			end
		end)
	else
		if isMaxLimitMessage(response.Message) then
			showLimitPrompt()
		else
			setStatus(response.Message or "Could not create room.", true)
		end
	end
end)
