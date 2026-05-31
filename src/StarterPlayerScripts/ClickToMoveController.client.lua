--Explorer/StarterPlayerScripts/ClickToMoveController
print("ClickToMoveController started")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local activeRooms = workspace:WaitForChild("ActiveRooms")
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local furnitureActionRequest = remoteEvents:WaitForChild("FurnitureActionRequest")
local furnitureActionResult = remoteEvents:WaitForChild("FurnitureActionResult")
local furnitureMenuRequest = remoteEvents:WaitForChild("FurnitureMenuRequest")
local GridConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GridConfig"))

local playerGui = player:WaitForChild("PlayerGui")

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

local function getOrCreateClientFunction(name)
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
		if not existing:IsA("BindableFunction") then
			error(name .. " exists but is not a BindableFunction.")
		end

		return existing
	end

	local bindableFunction = Instance.new("BindableFunction")
	bindableFunction.Name = name
	bindableFunction.Parent = clientEvents

	return bindableFunction
end

local inventoryRefreshRequested = getOrCreateClientEvent("InventoryRefreshRequested")
local inventoryLocalDelta = getOrCreateClientEvent("InventoryLocalDelta")
local requestGridMoveToPosition = getOrCreateClientEvent("RequestGridMoveToPosition")
local canGridMoveToPosition = getOrCreateClientFunction("CanGridMoveToPosition")
local requestMoveToRoomExit = getOrCreateClientFunction("RequestMoveToRoomExit")
local ensureStandBeforeMovement = getOrCreateClientFunction("EnsureStandBeforeMovement")

local function fireInventoryLocalDeltaFromPickUpResult(response)
	local templateId = response.TemplateId

	if typeof(templateId) ~= "string" or templateId == "" then
		return
	end

	local total = response.NewCount
	local details = response.InventoryDetails

	if typeof(details) == "table" and typeof(details.Total) == "number" then
		total = details.Total
	end

	if typeof(total) ~= "number" then
		return
	end

	local payload = {
		TemplateId = templateId,
		Total = total,
	}

	if typeof(details) == "table" then
		if typeof(details.Tradable) == "number" then
			payload.Tradable = details.Tradable
		end

		if typeof(details.Untradable) == "number" then
			payload.Untradable = details.Untradable
		end

		if typeof(details.Sellable) == "number" then
			payload.Sellable = details.Sellable
		end

		if typeof(details.Unsellable) == "number" then
			payload.Unsellable = details.Unsellable
		end
	end

	inventoryLocalDelta:Fire(payload)
end

local furnitureMenuGui = playerGui:WaitForChild("FurnitureMenuGui")
local menuFrame = furnitureMenuGui:WaitForChild("MenuFrame")
menuFrame.AnchorPoint = Vector2.new(0.5, 1)

local MENU_WIDTH = 248
local MENU_HEADER_HEIGHT = 68
local MENU_MARGIN = 12
local MENU_TOP_MARGIN = 56
local MENU_BUTTON_HEIGHT = 34
local MENU_BUTTON_GAP = 8
local MENU_BUTTON_RADIUS = 8
local MENU_CARD_RADIUS = 12
local MENU_TEXT_DARK = Color3.fromRGB(38, 42, 48)
local MENU_TEXT_MUTED = Color3.fromRGB(105, 110, 118)

local function ensureCorner(parent, radius)
	local corner = parent:FindFirstChildOfClass("UICorner")

	if not corner then
		corner = Instance.new("UICorner")
		corner.Parent = parent
	end

	corner.CornerRadius = UDim.new(0, radius)
	return corner
end

local function ensureStroke(parent, color, thickness, transparency)
	local stroke = parent:FindFirstChildOfClass("UIStroke")

	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = parent
	end

	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	return stroke
end

local function getOrCreateMenuTextLabel(name)
	local label = menuFrame:FindFirstChild(name)

	if label and label:IsA("TextLabel") then
		return label
	end

	if label then
		label:Destroy()
	end

	label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Parent = menuFrame
	return label
end

local function styleActionButton(button, backgroundColor)
	button.BackgroundColor3 = backgroundColor
	button.BackgroundTransparency = 0
	button.BorderSizePixel = 0
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextSize = 14
	button.Font = Enum.Font.GothamBold
	button.AutoButtonColor = true

	ensureCorner(button, MENU_BUTTON_RADIUS)
	ensureStroke(button, Color3.fromRGB(255, 255, 255), 1, 0.72)
end

local titleLabel = menuFrame:WaitForChild("TitleLabel")
local sitButton = menuFrame:WaitForChild("SitButton")
local closeButton = menuFrame:WaitForChild("CloseButton")
local moveButton = menuFrame:WaitForChild("MoveButton")
local rotateButton = menuFrame:WaitForChild("RotateButton")
local pickUpButton = menuFrame:FindFirstChild("PickUpButton")
local openCloseButton = menuFrame:FindFirstChild("OpenCloseButton")

if not pickUpButton then
	local verticalStep = rotateButton.Size.Y.Offset

	if verticalStep <= 0 then
		verticalStep = 42
	end

	pickUpButton = rotateButton:Clone()
	pickUpButton.Name = "PickUpButton"
	pickUpButton.Text = "Pick Up"
	pickUpButton.Position = UDim2.new(
		rotateButton.Position.X.Scale,
		rotateButton.Position.X.Offset,
		rotateButton.Position.Y.Scale,
		rotateButton.Position.Y.Offset + verticalStep + 6
	)
	pickUpButton.Parent = menuFrame

	if menuFrame.Size.Y.Scale == 0 and pickUpButton.Position.Y.Scale == 0 then
		local requiredHeight = pickUpButton.Position.Y.Offset
			+ pickUpButton.Size.Y.Offset
			+ 8

		if requiredHeight > menuFrame.Size.Y.Offset then
			menuFrame.Size = UDim2.new(
				menuFrame.Size.X.Scale,
				menuFrame.Size.X.Offset,
				0,
				requiredHeight
			)
		end
	end
end

pickUpButton.Visible = false

if not openCloseButton then
	openCloseButton = rotateButton:Clone()
	openCloseButton.Name = "OpenCloseButton"
	openCloseButton.Text = "Open"
	openCloseButton.Parent = menuFrame
end

openCloseButton.Visible = false

local subtitleLabel = getOrCreateMenuTextLabel("SubtitleLabel")
local occupiedBadge = getOrCreateMenuTextLabel("OccupiedBadge")

menuFrame.Size = UDim2.fromOffset(MENU_WIDTH, 164)
menuFrame.BackgroundColor3 = Color3.fromRGB(248, 249, 250)
menuFrame.BackgroundTransparency = 0
menuFrame.BorderSizePixel = 0
menuFrame.ClipsDescendants = false
menuFrame.Active = true

ensureCorner(menuFrame, MENU_CARD_RADIUS)
ensureStroke(menuFrame, Color3.fromRGB(30, 35, 42), 1, 0.82)

titleLabel.Position = UDim2.fromOffset(14, 12)
titleLabel.Size = UDim2.new(1, -62, 0, 22)
titleLabel.BackgroundTransparency = 1
titleLabel.TextColor3 = MENU_TEXT_DARK
titleLabel.TextSize = 16
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
titleLabel.Font = Enum.Font.GothamBold

subtitleLabel.Position = UDim2.fromOffset(14, 36)
subtitleLabel.Size = UDim2.new(1, -104, 0, 18)
subtitleLabel.TextColor3 = MENU_TEXT_MUTED
subtitleLabel.TextSize = 12
subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
subtitleLabel.TextTruncate = Enum.TextTruncate.AtEnd
subtitleLabel.Font = Enum.Font.GothamMedium

occupiedBadge.AnchorPoint = Vector2.new(1, 0)
occupiedBadge.Position = UDim2.new(1, -14, 0, 36)
occupiedBadge.Size = UDim2.fromOffset(76, 22)
occupiedBadge.BackgroundTransparency = 0
occupiedBadge.BackgroundColor3 = Color3.fromRGB(238, 209, 118)
occupiedBadge.Text = "Occupied"
occupiedBadge.TextColor3 = Color3.fromRGB(70, 54, 24)
occupiedBadge.TextSize = 11
occupiedBadge.Font = Enum.Font.GothamBold
occupiedBadge.Visible = false
ensureCorner(occupiedBadge, 11)

closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -12, 0, 10)
closeButton.Size = UDim2.fromOffset(28, 28)
closeButton.BackgroundColor3 = Color3.fromRGB(214, 91, 91)
closeButton.BackgroundTransparency = 0
closeButton.BorderSizePixel = 0
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.TextSize = 14
closeButton.Font = Enum.Font.GothamBold
ensureCorner(closeButton, 8)
ensureStroke(closeButton, Color3.fromRGB(255, 255, 255), 1, 0.7)

sitButton.Text = "Sit"
moveButton.Text = "Move"
rotateButton.Text = "Rotate"
pickUpButton.Text = "Pick Up"
openCloseButton.Text = "Open"

styleActionButton(sitButton, Color3.fromRGB(72, 143, 91))
styleActionButton(moveButton, Color3.fromRGB(76, 123, 181))
styleActionButton(rotateButton, Color3.fromRGB(76, 123, 181))
styleActionButton(pickUpButton, Color3.fromRGB(190, 102, 68))
styleActionButton(openCloseButton, Color3.fromRGB(86, 135, 98))

local permissionUi = {
	rows = {},
	entries = {},
	expanded = false,
	canManage = false,
}

permissionUi.accessButton = rotateButton:Clone()
permissionUi.accessButton.Name = "OpenCloseAccessButton"
permissionUi.accessButton.Text = "Access"
permissionUi.accessButton.Visible = false
permissionUi.accessButton.Parent = menuFrame
styleActionButton(permissionUi.accessButton, Color3.fromRGB(116, 104, 171))

permissionUi.panel = Instance.new("Frame")
permissionUi.panel.Name = "OpenCloseAccessPanel"
permissionUi.panel.BackgroundColor3 = Color3.fromRGB(235, 238, 241)
permissionUi.panel.BackgroundTransparency = 0
permissionUi.panel.BorderSizePixel = 0
permissionUi.panel.Visible = false
permissionUi.panel.Parent = menuFrame
ensureCorner(permissionUi.panel, 8)
ensureStroke(permissionUi.panel, Color3.fromRGB(177, 184, 194), 1, 0.25)

permissionUi.title = Instance.new("TextLabel")
permissionUi.title.Name = "Title"
permissionUi.title.BackgroundTransparency = 1
permissionUi.title.Position = UDim2.fromOffset(10, 8)
permissionUi.title.Size = UDim2.new(1, -20, 0, 18)
permissionUi.title.Text = "Open/Close Access"
permissionUi.title.TextColor3 = MENU_TEXT_DARK
permissionUi.title.TextSize = 12
permissionUi.title.TextXAlignment = Enum.TextXAlignment.Left
permissionUi.title.Font = Enum.Font.GothamBold
permissionUi.title.Parent = permissionUi.panel

permissionUi.input = Instance.new("TextBox")
permissionUi.input.Name = "UserIdInput"
permissionUi.input.Position = UDim2.fromOffset(10, 32)
permissionUi.input.Size = UDim2.new(1, -82, 0, 28)
permissionUi.input.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
permissionUi.input.BorderSizePixel = 0
permissionUi.input.PlaceholderText = "Username or UserId"
permissionUi.input.Text = ""
permissionUi.input.TextColor3 = MENU_TEXT_DARK
permissionUi.input.PlaceholderColor3 = MENU_TEXT_MUTED
permissionUi.input.TextSize = 12
permissionUi.input.Font = Enum.Font.GothamMedium
permissionUi.input.ClearTextOnFocus = false
permissionUi.input.Parent = permissionUi.panel
ensureCorner(permissionUi.input, 6)
ensureStroke(permissionUi.input, Color3.fromRGB(183, 190, 198), 1, 0.1)

permissionUi.addButton = Instance.new("TextButton")
permissionUi.addButton.Name = "AddButton"
permissionUi.addButton.Position = UDim2.new(1, -64, 0, 32)
permissionUi.addButton.Size = UDim2.fromOffset(54, 28)
permissionUi.addButton.Text = "Add"
permissionUi.addButton.Parent = permissionUi.panel
styleActionButton(permissionUi.addButton, Color3.fromRGB(72, 143, 91))

permissionUi.list = Instance.new("ScrollingFrame")
permissionUi.list.Name = "AllowedUsers"
permissionUi.list.Position = UDim2.fromOffset(10, 68)
permissionUi.list.Size = UDim2.new(1, -20, 0, 72)
permissionUi.list.BackgroundTransparency = 1
permissionUi.list.BorderSizePixel = 0
permissionUi.list.ScrollBarThickness = 4
permissionUi.list.CanvasSize = UDim2.fromOffset(0, 0)
permissionUi.list.Parent = permissionUi.panel

permissionUi.status = Instance.new("TextLabel")
permissionUi.status.Name = "Status"
permissionUi.status.BackgroundTransparency = 1
permissionUi.status.Position = UDim2.fromOffset(10, 142)
permissionUi.status.Size = UDim2.new(1, -20, 0, 18)
permissionUi.status.Text = ""
permissionUi.status.TextColor3 = MENU_TEXT_MUTED
permissionUi.status.TextSize = 11
permissionUi.status.TextXAlignment = Enum.TextXAlignment.Left
permissionUi.status.TextTruncate = Enum.TextTruncate.AtEnd
permissionUi.status.Font = Enum.Font.GothamMedium
permissionUi.status.Parent = permissionUi.panel

local function layoutFurnitureMenu(showSit, showMove, showRotate, showPickUp, showOpenClose, showAccess)
	local contentX = 14
	local contentWidth = MENU_WIDTH - 28
	local y = MENU_HEADER_HEIGHT
	local halfWidth = math.floor((contentWidth - MENU_BUTTON_GAP) / 2)

	sitButton.Visible = showSit == true
	moveButton.Visible = showMove == true
	rotateButton.Visible = showRotate == true
	pickUpButton.Visible = showPickUp == true
	openCloseButton.Visible = showOpenClose == true
	permissionUi.accessButton.Visible = showAccess == true
	permissionUi.panel.Visible = showAccess == true and permissionUi.expanded == true

	if showSit then
		sitButton.Position = UDim2.fromOffset(contentX, y)
		sitButton.Size = UDim2.fromOffset(contentWidth, MENU_BUTTON_HEIGHT)
		y += MENU_BUTTON_HEIGHT + MENU_BUTTON_GAP
	end

	if showMove or showRotate then
		moveButton.Position = UDim2.fromOffset(contentX, y)
		moveButton.Size = UDim2.fromOffset(halfWidth, MENU_BUTTON_HEIGHT)
		rotateButton.Position = UDim2.fromOffset(contentX + halfWidth + MENU_BUTTON_GAP, y)
		rotateButton.Size = UDim2.fromOffset(contentWidth - halfWidth - MENU_BUTTON_GAP, MENU_BUTTON_HEIGHT)
		y += MENU_BUTTON_HEIGHT + MENU_BUTTON_GAP
	end

	if showOpenClose then
		openCloseButton.Position = UDim2.fromOffset(contentX, y)
		openCloseButton.Size = UDim2.fromOffset(contentWidth, MENU_BUTTON_HEIGHT)
		y += MENU_BUTTON_HEIGHT + MENU_BUTTON_GAP
	end

	if showAccess then
		permissionUi.accessButton.Position = UDim2.fromOffset(contentX, y)
		permissionUi.accessButton.Size = UDim2.fromOffset(contentWidth, MENU_BUTTON_HEIGHT)
		y += MENU_BUTTON_HEIGHT + MENU_BUTTON_GAP
	end

	if showPickUp then
		pickUpButton.Position = UDim2.fromOffset(contentX, y)
		pickUpButton.Size = UDim2.fromOffset(contentWidth, MENU_BUTTON_HEIGHT)
		y += MENU_BUTTON_HEIGHT + MENU_BUTTON_GAP
	end

	if permissionUi.panel.Visible then
		permissionUi.panel.Position = UDim2.fromOffset(contentX, y)
		permissionUi.panel.Size = UDim2.fromOffset(contentWidth, 166)
		y += 166 + MENU_BUTTON_GAP
	end

	menuFrame.Size = UDim2.fromOffset(MENU_WIDTH, math.max(y + 6, 116))
end

local function getCurrentRoomModel()
	local roomName = player:GetAttribute("CurrentRoomName")

	if not roomName then
		return nil
	end

	return activeRooms:FindFirstChild(roomName)
end

local function getCurrentRoomFolder()
	local roomModel = getCurrentRoomModel()

	if not roomModel then
		return nil
	end

	return roomModel:FindFirstChild("Room")
end

local function getCurrentFurnitureFolder()
	local roomModel = getCurrentRoomModel()

	if not roomModel then
		return nil
	end

	return roomModel:FindFirstChild("Furniture")
end

local function getCurrentFloor()
	local roomFolder = getCurrentRoomFolder()

	if not roomFolder then
		return nil
	end

	return roomFolder:FindFirstChild("WalkableFloor")
end

local function instanceHasWalkableSurfaceAttribute(instance)
	if typeof(instance) ~= "Instance" then
		return false
	end

	return instance:GetAttribute("WalkableSurface") == true
		or instance:GetAttribute("IsWalkableSurface") == true
		or instance:GetAttribute("IsWalkableDecoration") == true
end

local function isWalkableSurfacePart(part)
	return typeof(part) == "Instance"
		and part:IsA("BasePart")
		and (
			part.Name == "WalkableFloor"
			or instanceHasWalkableSurfaceAttribute(part)
		)
end

local function getWalkableSurfaceFloor(part)
	if not isWalkableSurfacePart(part) then
		return nil
	end

	local floor = getCurrentFloor()

	if not floor then
		return nil
	end

	if part == floor then
		return floor
	end

	local roomModel = getCurrentRoomModel()

	if roomModel and part:IsDescendantOf(roomModel) then
		return floor
	end

	return nil
end

local function furnitureModelIsWalkableDecoration(furnitureModel)
	if typeof(furnitureModel) ~= "Instance" or not furnitureModel:IsA("Model") then
		return false
	end

	if instanceHasWalkableSurfaceAttribute(furnitureModel) then
		return true
	end

	for _, descendant in ipairs(furnitureModel:GetDescendants()) do
		if instanceHasWalkableSurfaceAttribute(descendant) then
			return true
		end
	end

	return false
end

local function isEditMode()
	return player:GetAttribute("RoomMode") == "Edit"
end

local publicFurnitureRules = {}

function publicFurnitureRules.isCurrentRoomPublicSpace()
	local roomModel = getCurrentRoomModel()

	return roomModel ~= nil and roomModel:GetAttribute("RoomType") == "PublicSpace"
end

local function getDefaultFurnitureAction(furnitureModel)
	local defaultAction = furnitureModel:GetAttribute("DefaultAction")

	if typeof(defaultAction) ~= "string" then
		return nil
	end

	if defaultAction == "" or defaultAction == "None" then
		return nil
	end

	return defaultAction
end

local function permissionActionsIncludeOpenClose(permissionActions)
	if typeof(permissionActions) ~= "string" then
		return false
	end

	for actionName in string.gmatch(permissionActions, "([^,]+)") do
		local normalizedActionName = actionName:match("^%s*(.-)%s*$")

		if normalizedActionName == "OpenClose" then
			return true
		end
	end

	return false
end

local function furnitureHasOpenCloseTarget(furnitureModel)
	local configuredTargetName = furnitureModel:GetAttribute("OpenCloseTargetName")

	if typeof(configuredTargetName) == "string"
		and configuredTargetName ~= ""
		and furnitureModel:FindFirstChild(configuredTargetName, true) then

		return true
	end

	return furnitureModel:FindFirstChild("OpenClosePart", true) ~= nil
		or furnitureModel:FindFirstChild("DoorPanel", true) ~= nil
		or furnitureModel:FindFirstChild("GatePanel", true) ~= nil
		or furnitureModel:FindFirstChild("Panel", true) ~= nil
end

local function furnitureSupportsOpenCloseBestEffort(furnitureModel)
	if typeof(furnitureModel) ~= "Instance" or not furnitureModel:IsA("Model") then
		return false
	end

	if furnitureModel:GetAttribute("SupportsOpenClose") == true then
		return true
	end

	if permissionActionsIncludeOpenClose(furnitureModel:GetAttribute("PermissionActions")) then
		return true
	end

	return furnitureHasOpenCloseTarget(furnitureModel)
end

function publicFurnitureRules.allowsOpenClose(furnitureModel)
	if typeof(furnitureModel) ~= "Instance" or not furnitureModel:IsA("Model") then
		return false
	end

	return furnitureModel:GetAttribute("PublicUse") == true
		or furnitureModel:GetAttribute("PublicOpenClose") == true
		or furnitureModel:GetAttribute("AllowPublicOpenClose") == true
end

function publicFurnitureRules.hasSitPoint(furnitureModel)
	if typeof(furnitureModel) ~= "Instance" or not furnitureModel:IsA("Model") then
		return false
	end

	local seat = furnitureModel:FindFirstChild("Seat", true)
	local sitPoint = furnitureModel:FindFirstChild("SitPoint", true)

	return seat ~= nil
		and seat:IsA("Seat")
		and sitPoint ~= nil
		and (sitPoint:IsA("BasePart") or sitPoint:IsA("Attachment"))
end

function publicFurnitureRules.supportsSit(furnitureModel)
	return getDefaultFurnitureAction(furnitureModel) == "Sit"
		or publicFurnitureRules.hasSitPoint(furnitureModel)
end

function publicFurnitureRules.supportsOpenClose(furnitureModel)
	return publicFurnitureRules.allowsOpenClose(furnitureModel)
		and furnitureSupportsOpenCloseBestEffort(furnitureModel)
end

local function updateOpenCloseButtonText(furnitureModel, isOpenOverride)
	local isOpen = isOpenOverride

	if typeof(isOpen) ~= "boolean" then
		isOpen = furnitureModel and furnitureModel:GetAttribute("IsOpen") == true
	end

	openCloseButton.Text = isOpen and "Close" or "Open"
end

local function resolveFurniturePickupTemplateId(furnitureModel)
	if typeof(furnitureModel) ~= "Instance" then
		return nil, false
	end

	local templateId = furnitureModel:GetAttribute("TemplateId")

	if typeof(templateId) == "string" and templateId ~= "" and templateId:match("%S") then
		return templateId, false
	end

	local pickupTemplateId = furnitureModel:GetAttribute("PickupTemplateId")

	if typeof(pickupTemplateId) == "string"
		and pickupTemplateId ~= ""
		and pickupTemplateId:match("%S") then

		return pickupTemplateId, true
	end

	local persistentId = furnitureModel:GetAttribute("PersistentId")

	if typeof(persistentId) == "string" and persistentId ~= "" and persistentId:match("%S") then
		return persistentId, true
	end

	if furnitureModel.Name ~= "" and furnitureModel.Name:match("%S") then
		return furnitureModel.Name, true
	end

	return nil, false
end

local function getFurnitureTemplateId(furnitureModel)
	local templateId = resolveFurniturePickupTemplateId(furnitureModel)

	return templateId
end

local function isFurniturePickupOptimisticallyUntradable(furnitureModel, resolvedThroughFallback)
	if furnitureModel:GetAttribute("Tradable") == false then
		return true
	end

	if furnitureModel:GetAttribute("IsTradable") == false then
		return true
	end

	return resolvedThroughFallback == true
end

local function isFurniturePickupOptimisticallyUnsellable(furnitureModel, resolvedThroughFallback)
	if furnitureModel:GetAttribute("Sellable") == false then
		return true
	end

	if furnitureModel:GetAttribute("CanSell") == false then
		return true
	end

	return resolvedThroughFallback == true
end

local function actionRequiresStanding(actionName)
	return actionName == "Sit"
		or actionName == "Sleep"
		or actionName == "Run"
end

local function getFurnitureOccupantHumanoid(furnitureModel)
	if typeof(furnitureModel) ~= "Instance" then
		return nil, nil
	end

	if not furnitureModel:IsA("Model") then
		return nil, nil
	end

	for _, descendant in ipairs(furnitureModel:GetDescendants()) do
		if descendant:IsA("Seat") or descendant:IsA("VehicleSeat") then
			if descendant.Occupant then
				return descendant.Occupant, descendant
			end
		end
	end

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		local character = otherPlayer.Character

		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")

			if humanoid
				and humanoid.SeatPart
				and humanoid.SeatPart:IsDescendantOf(furnitureModel) then

				return humanoid, humanoid.SeatPart
			end
		end
	end

	return nil, nil
end

local function isFurnitureOccupiedLocally(furnitureModel)
	local humanoid = getFurnitureOccupantHumanoid(furnitureModel)

	return humanoid ~= nil
end

local selectedFurniture = nil
local movingFurniture = nil
local placementPreview = nil
local placementPreviewHighlight = nil
local placementIsValid = false
local movePreviewState = {
	rotationOffsetY = 0,
	hintGui = nil,
	hintLabel = nil,
	helperUi = {
		mainHudGuiName = "MainHudGui",
		mainHudBarName = "MainHudBottomBar",
		fallbackBottomOffset = 180,
		hudMargin = 12,
		topMargin = 8,
		candidateBarNames = { "BottomBar", "HudBar", "MainBar" },
		labels = setmetatable({}, {
			__mode = "k",
		}),
	},
}

do
	local helperUi = movePreviewState.helperUi

	function helperUi.isVisible(guiObject)
		local current = guiObject

		while current and current ~= playerGui do
			if current:IsA("ScreenGui") and current.Enabled == false then
				return false
			end

			if current:IsA("GuiObject") and current.Visible == false then
				return false
			end

			current = current.Parent
		end

		return true
	end

	function helperUi.findHudBar()
		local mainHudGui = playerGui:FindFirstChild(helperUi.mainHudGuiName)

		if not mainHudGui then
			return nil
		end

		local namedBar = mainHudGui:FindFirstChild(helperUi.mainHudBarName, true)

		if namedBar and namedBar:IsA("GuiObject") and helperUi.isVisible(namedBar) then
			return namedBar
		end

		for _, candidateName in ipairs(helperUi.candidateBarNames) do
			local candidate = mainHudGui:FindFirstChild(candidateName, true)

			if candidate and candidate:IsA("GuiObject") and helperUi.isVisible(candidate) then
				return candidate
			end
		end

		for _, descendant in ipairs(mainHudGui:GetDescendants()) do
			if descendant:IsA("GuiObject")
				and helperUi.isVisible(descendant)
				and descendant:FindFirstChild("MenuButton")
				and descendant:FindFirstChild("ChatPlaceholder")
				and descendant:FindFirstChild("InventoryButton")
				and descendant:FindFirstChild("CatalogButton")
				and descendant:FindFirstChild("EditButton") then

				return descendant
			end
		end

		return nil
	end

	function helperUi.getScreenPosition(label)
		local camera = workspace.CurrentCamera
		local viewportSize = camera and camera.ViewportSize or Vector2.zero
		local viewportWidth = viewportSize.X
		local viewportHeight = viewportSize.Y

		if viewportWidth <= 0 or viewportHeight <= 0 then
			return nil
		end

		local labelHeight = label.AbsoluteSize.Y

		if labelHeight <= 0 then
			labelHeight = label.Size.Y.Offset
		end

		if labelHeight <= 0 then
			labelHeight = 34
		end

		local hudBar = helperUi.findHudBar()
		local helperBottomY = viewportHeight - helperUi.fallbackBottomOffset

		if hudBar then
			helperBottomY = hudBar.AbsolutePosition.Y - helperUi.hudMargin
		end

		local minBottomY = labelHeight + helperUi.topMargin
		local maxBottomY = viewportHeight - helperUi.topMargin
		helperBottomY = math.clamp(helperBottomY, minBottomY, maxBottomY)

		return viewportWidth / 2, helperBottomY
	end

	function helperUi.position(label)
		if typeof(label) ~= "Instance" or not label:IsA("GuiObject") then
			return
		end

		local helperX, helperY = helperUi.getScreenPosition(label)

		label.AnchorPoint = Vector2.new(0.5, 1)

		if helperX and helperY then
			label.Position = UDim2.fromOffset(helperX, helperY)
		else
			label.Position = UDim2.new(0.5, 0, 1, -helperUi.fallbackBottomOffset)
		end
	end

	function helperUi.register(label)
		if typeof(label) ~= "Instance" or not label:IsA("GuiObject") then
			return
		end

		helperUi.labels[label] = true
		helperUi.position(label)
	end

	function helperUi.update()
		for label in pairs(helperUi.labels) do
			if label.Parent then
				helperUi.position(label)
			else
				helperUi.labels[label] = nil
			end
		end
	end

	playerGui.DescendantAdded:Connect(function(descendant)
		if descendant.Name == "PlacementHintLabel" and descendant:IsA("GuiObject") then
			helperUi.register(descendant)
		end
	end)

	task.defer(function()
		for _, descendant in ipairs(playerGui:GetDescendants()) do
			if descendant.Name == "PlacementHintLabel" and descendant:IsA("GuiObject") then
				helperUi.register(descendant)
			end
		end
	end)
end

local hiddenFurnitureParts = {}
local suppressFurnitureMenuUntil = 0

local lastPlayFurnitureActionAt = 0
local PLAY_FURNITURE_ACTION_COOLDOWN_SECONDS = 0.35

local selectedHighlight = Instance.new("Highlight")
selectedHighlight.Name = "SelectedFurnitureHighlight"
selectedHighlight.FillTransparency = 1
selectedHighlight.OutlineTransparency = 0
selectedHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
selectedHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
selectedHighlight.Enabled = false
selectedHighlight.Parent = workspace

local function highlightFurniture(furnitureModel)
	selectedHighlight.Adornee = furnitureModel
	selectedHighlight.Enabled = true
end

local function clearFurnitureHighlight()
	selectedHighlight.Adornee = nil
	selectedHighlight.Enabled = false
end

function permissionUi.getPersistentId(furnitureModel)
	if typeof(furnitureModel) ~= "Instance" or not furnitureModel:IsA("Model") then
		return nil
	end

	local persistentId = furnitureModel:GetAttribute("PersistentId")

	if typeof(persistentId) ~= "string" or persistentId == "" or not persistentId:match("%S") then
		return nil
	end

	return persistentId
end

function permissionUi.applyLayout()
	layoutFurnitureMenu(
		permissionUi.showSit,
		permissionUi.showMove,
		permissionUi.showRotate,
		permissionUi.showPickUp,
		permissionUi.showOpenClose,
		permissionUi.canManage
	)
end

function permissionUi.setStatus(message, isError)
	permissionUi.status.Text = tostring(message or "")
	permissionUi.status.TextColor3 = isError and Color3.fromRGB(178, 72, 58) or MENU_TEXT_MUTED
end

function permissionUi.clearRows()
	for _, row in ipairs(permissionUi.rows) do
		if row and row.Parent then
			row:Destroy()
		end
	end

	permissionUi.rows = {}
end

function permissionUi.setEntries(entries)
	permissionUi.entries = typeof(entries) == "table" and entries or {}
	permissionUi.clearRows()

	if #permissionUi.entries == 0 then
		local row = Instance.new("TextLabel")
		row.Name = "Empty"
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromOffset(0, 0)
		row.Size = UDim2.new(1, -4, 0, 24)
		row.Text = "No users added."
		row.TextColor3 = MENU_TEXT_MUTED
		row.TextSize = 11
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Font = Enum.Font.GothamMedium
		row.Parent = permissionUi.list
		table.insert(permissionUi.rows, row)
		permissionUi.list.CanvasSize = UDim2.fromOffset(0, 28)
		return
	end

	for index, entry in ipairs(permissionUi.entries) do
		local userId = tonumber(entry.UserId)
		local row = Instance.new("Frame")
		row.Name = "User_" .. tostring(userId or index)
		row.Position = UDim2.fromOffset(0, (index - 1) * 30)
		row.Size = UDim2.new(1, -4, 0, 26)
		row.BackgroundColor3 = Color3.fromRGB(247, 248, 249)
		row.BorderSizePixel = 0
		row.Parent = permissionUi.list
		ensureCorner(row, 5)

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(6, 0)
		label.Size = UDim2.new(1, -70, 1, 0)
		label.Text = entry.DisplayName or entry.Name or tostring(userId)
		label.TextColor3 = MENU_TEXT_DARK
		label.TextSize = 11
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Font = Enum.Font.GothamMedium
		label.Parent = row

		local removeButton = Instance.new("TextButton")
		removeButton.Name = "Remove"
		removeButton.AnchorPoint = Vector2.new(1, 0.5)
		removeButton.Position = UDim2.new(1, -4, 0.5, 0)
		removeButton.Size = UDim2.fromOffset(56, 20)
		removeButton.Text = "Remove"
		removeButton.Parent = row
		styleActionButton(removeButton, Color3.fromRGB(190, 102, 68))
		removeButton.TextSize = 10
		removeButton.MouseButton1Click:Connect(function()
			if not selectedFurniture or not userId then
				return
			end

			remoteEvents:WaitForChild("RoomPermissionRequest"):FireServer("SetFurniturePermission", {
				Furniture = selectedFurniture,
				ActionName = "OpenClose",
				TargetUserId = userId,
				IsAllowed = false,
			})
		end)

		table.insert(permissionUi.rows, row)
	end

	permissionUi.list.CanvasSize = UDim2.fromOffset(0, #permissionUi.entries * 30)
end

function permissionUi.requestCurrent()
	if not selectedFurniture then
		return
	end

	permissionUi.setStatus("Loading...")
	remoteEvents:WaitForChild("RoomPermissionRequest"):FireServer("GetFurniturePermissions", {
		Furniture = selectedFurniture,
		ActionName = "OpenClose",
	})
end

function permissionUi.resetForMenu(furnitureModel, showSit, showMove, showRotate, showPickUp, showOpenClose)
	permissionUi.showSit = showSit
	permissionUi.showMove = showMove
	permissionUi.showRotate = showRotate
	permissionUi.showPickUp = showPickUp
	permissionUi.showOpenClose = showOpenClose
	permissionUi.canManage = false
	permissionUi.expanded = false
	permissionUi.input.Text = ""
	permissionUi.setStatus("")
	permissionUi.setEntries({})
end

function permissionUi.requestActionAccess()
	if not selectedFurniture then
		return
	end

	remoteEvents:WaitForChild("RoomPermissionRequest"):FireServer("GetFurnitureActionAccess", {
		Furniture = selectedFurniture,
	})
end

function permissionUi.applyActionAccess(response)
	if typeof(response) ~= "table" or response.Kind ~= "FurnitureActionAccess" then
		return false
	end

	if not selectedFurniture or not menuFrame.Visible or response.Furniture ~= selectedFurniture then
		return true
	end

	local editing = isEditMode()

	permissionUi.showOpenClose = response.SupportsOpenClose == true and response.CanOpenClose == true
	permissionUi.canManage = response.CanManageOpenClose == true
	permissionUi.showMove = editing and response.CanMove == true
	permissionUi.showRotate = editing and response.CanRotate == true
	permissionUi.showPickUp = editing and response.CanPickUp == true and getFurnitureTemplateId(selectedFurniture) ~= nil

	if not permissionUi.canManage then
		permissionUi.expanded = false
		permissionUi.setEntries({})
		permissionUi.setStatus("")
	end

	if not editing and not permissionUi.showSit and not permissionUi.showOpenClose then
		selectedFurniture = nil
		menuFrame.Visible = false
		permissionUi.expanded = false
		permissionUi.canManage = false
		clearFurnitureHighlight()
		return true
	end

	updateOpenCloseButtonText(selectedFurniture)
	permissionUi.applyLayout()

	return true
end

function permissionUi.handleResult(response)
	if permissionUi.applyActionAccess(response) then
		return
	end

	if typeof(response) ~= "table" or response.Kind ~= "FurniturePermissions" then
		return
	end

	if not selectedFurniture or not menuFrame.Visible then
		return
	end

	local persistentId = permissionUi.getPersistentId(selectedFurniture)

	if response.FurniturePersistentId ~= persistentId or response.ActionName ~= "OpenClose" then
		return
	end

	if response.Success == true then
		permissionUi.setEntries(response.Entries)
		local message = response.Message or "Updated."

		if response.ResolvedUserId then
			local resolvedLabel = tostring(response.ResolvedUserId)

			if typeof(response.ResolvedName) == "string" and response.ResolvedName ~= "" then
				resolvedLabel = response.ResolvedName .. " (" .. resolvedLabel .. ")"
			end

			message = message .. " " .. resolvedLabel
		end

		permissionUi.setStatus(message)
	else
		permissionUi.setStatus(response.Message or "Could not update access.", true)
	end
end

local currentMoveId = 0
local lastMoveTime = 0

local CLICK_MOVE_COOLDOWN = 0.2
local SNAP_CHARACTER_FACING_TO_GRID = true
local HOTEL_GRID_WALK_SPEED = 12
local ENTRY_BRIDGE_REACHED_DISTANCE = 3
local EXIT_TARGET_REACHED_DISTANCE = 3.5
local EXIT_DIRECT_MOVE_TIMEOUT_SECONDS = 4
local EXIT_ENTRY_MOVE_TIMEOUT_SECONDS = 8
local STAND_UP_TIMEOUT_SECONDS = 2
local STAND_SETTLE_CHECK_SECONDS = 0.05

local warnedTileGridDisabled = false
local activeGridFacingMoveId = nil
local activeGridFacingHumanoid = nil
local activeGridFacingPreviousAutoRotate = nil
local activeGridFacingPreviousWalkSpeed = nil
local activeGridFacingRootPart = nil
local activeGridFacingDirection = nil
local entranceBridgeDiagnosticsLogged = {}
local lastSeatedStandCompletedAt = 0
local roomMovementState = {
	caveTransitionActive = false,
	lastEntranceReachWarningAt = 0,
}

local function getMovementGridContext()
	local roomModel = getCurrentRoomModel()
	local floor = getCurrentFloor()

	if not roomModel or not floor or not floor:IsA("BasePart") then
		return nil
	end

	if not GridConfig.UsesTileGrid(roomModel, floor) then
		return nil, "Tile grid movement is disabled for this room."
	end

	local tileBounds = GridConfig.GetTileBounds(roomModel, floor)
	local floorTopY = GridConfig.GetFloorTopY(floor)

	if not tileBounds or not floorTopY then
		return nil
	end

	return {
		roomModel = roomModel,
		floor = floor,
		tileSize = tileBounds.TileSize,
		gridWidth = tileBounds.GridWidth,
		gridDepth = tileBounds.GridDepth,
		halfWidthStuds = tileBounds.HalfWidthStuds,
		halfDepthStuds = tileBounds.HalfDepthStuds,
		floorTopY = floorTopY,
		moveY = floorTopY + 0.5,
		floorRotation = floor.CFrame - floor.CFrame.Position,
	}
end

local function localAxisToCellIndex(value, tileSize, tileCount, halfStuds)
	local minCenter = -halfStuds + tileSize / 2
	local index = math.floor(((value - minCenter) / tileSize) + 0.5)

	return math.clamp(index, 0, tileCount - 1)
end

local function cellIndexToLocalAxis(index, tileSize, halfStuds)
	return -halfStuds + tileSize / 2 + index * tileSize
end

local function worldToCell(position, context)
	local localPosition = GridConfig.WorldToFloorLocal(context.floor, position)

	if not localPosition then
		return nil
	end

	return {
		x = localAxisToCellIndex(localPosition.X, context.tileSize, context.gridWidth, context.halfWidthStuds),
		z = localAxisToCellIndex(localPosition.Z, context.tileSize, context.gridDepth, context.halfDepthStuds),
	}
end

local function cellToWorld(cell, context)
	local localX = cellIndexToLocalAxis(cell.x, context.tileSize, context.halfWidthStuds)
	local localZ = cellIndexToLocalAxis(cell.z, context.tileSize, context.halfDepthStuds)
	local localPosition = Vector3.new(localX, context.floor.Size.Y / 2 + 0.5, localZ)
	local worldPosition = GridConfig.FloorLocalToWorld(context.floor, localPosition)

	if not worldPosition then
		return Vector3.new(0, context.moveY, 0)
	end

	return Vector3.new(worldPosition.X, context.moveY, worldPosition.Z)
end

local function findCurrentRoomMarker(markerName)
	local roomModel = getCurrentRoomModel()

	if not roomModel then
		return nil
	end

	local marker = roomModel:FindFirstChild(markerName, true)

	if marker and (marker:IsA("BasePart") or marker:IsA("Attachment")) then
		return marker
	end

	return nil
end

local function getMarkerWorldPosition(marker)
	if not marker then
		return nil
	end

	if marker:IsA("Attachment") then
		return marker.WorldPosition
	end

	if marker:IsA("BasePart") then
		return marker.Position
	end

	return nil
end

local function getCurrentDoorSpawn()
	return findCurrentRoomMarker("DoorSpawn")
end

local function getCurrentEntryWalkTarget()
	return findCurrentRoomMarker("EntryWalkTarget")
end

function roomMovementState.setCaveTransitionActive(isActive)
	roomMovementState.caveTransitionActive = isActive == true
end

function roomMovementState.positionIsInsideOrNearPart(position, part, margin)
	if typeof(position) ~= "Vector3" or not part or not part:IsA("BasePart") then
		return false
	end

	local localPosition = part.CFrame:PointToObjectSpace(position)
	local halfSize = part.Size / 2
	local outsideX = math.max(math.abs(localPosition.X) - halfSize.X, 0)
	local outsideY = math.max(math.abs(localPosition.Y) - halfSize.Y, 0)
	local outsideZ = math.max(math.abs(localPosition.Z) - halfSize.Z, 0)

	return Vector3.new(outsideX, outsideY, outsideZ).Magnitude <= (margin or 0)
end

function roomMovementState.isRoomExitInstance(instance)
	local current = instance
	local roomModel = getCurrentRoomModel()

	while current and current ~= workspace do
		if current.Name == "RoomExitZone" or current:GetAttribute("IsRoomExit") == true then
			return roomModel == nil or current:IsDescendantOf(roomModel) or current == roomModel
		end

		if current == roomModel then
			break
		end

		current = current.Parent
	end

	return false
end

function roomMovementState.positionIsInsideOrNearRoomExitZone(position, distance)
	local roomModel = getCurrentRoomModel()

	if typeof(position) ~= "Vector3" or not roomModel then
		return false
	end

	for _, descendant in ipairs(roomModel:GetDescendants()) do
		if descendant:IsA("BasePart")
			and roomMovementState.isRoomExitInstance(descendant)
			and roomMovementState.positionIsInsideOrNearPart(position, descendant, distance) then

			return true
		end
	end

	return false
end

function roomMovementState.isPlayerAtDoorSpawn(rootPosition)
	local position = rootPosition

	if typeof(position) ~= "Vector3" then
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")

		if not rootPart then
			return false
		end

		position = rootPart.Position
	end

	local doorSpawnPosition = getMarkerWorldPosition(getCurrentDoorSpawn())

	if not doorSpawnPosition then
		return false
	end

	if (position - doorSpawnPosition).Magnitude <= EXIT_TARGET_REACHED_DISTANCE then
		return true
	end

	local doorSpawn = getCurrentDoorSpawn()

	if doorSpawn
		and doorSpawn:IsA("BasePart")
		and roomMovementState.positionIsInsideOrNearPart(position, doorSpawn, 0.5) then

		return true
	end

	-- RoomExitZone is only a prompt area. It only counts as cave state when the
	-- character is also physically at DoorSpawn.
	return roomMovementState.positionIsInsideOrNearRoomExitZone(position, 0.5)
		and (position - doorSpawnPosition).Magnitude <= EXIT_TARGET_REACHED_DISTANCE
end

function roomMovementState.isPlayerNearDoorCave(rootPosition)
	return roomMovementState.isPlayerAtDoorSpawn(rootPosition)
end

function roomMovementState.characterReachedMarkerPosition(marker, distance)
	local markerPosition = getMarkerWorldPosition(marker)

	if not markerPosition then
		return false
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	return rootPart ~= nil and (rootPart.Position - markerPosition).Magnitude <= distance
end

function roomMovementState.waitForCurrentRoomReady(options)
	options = typeof(options) == "table" and options or {}

	local timeoutSeconds = options.TimeoutSeconds or 1.25
	local requireDoorSpawn = options.RequireDoorSpawn == true
	local startTime = os.clock()

	while os.clock() - startTime < timeoutSeconds do
		local roomName = player:GetAttribute("CurrentRoomName")
		local roomModel = nil

		if typeof(roomName) == "string" and roomName ~= "" then
			roomModel = activeRooms:FindFirstChild(roomName)
		end

		local roomFolder = roomModel and roomModel:FindFirstChild("Room")
		local floor = roomFolder and roomFolder:FindFirstChild("WalkableFloor")
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local doorSpawnReady = not requireDoorSpawn

		if requireDoorSpawn and roomModel and roomModel:FindFirstChild("DoorSpawn", true) then
			doorSpawnReady = true
		end

		if roomModel and floor and floor:IsA("BasePart") and humanoid and rootPart and doorSpawnReady then
			return true
		end

		task.wait(0.05)
	end

	return false
end

local function worldPositionIsInsideGridBounds(position, context)
	local localPosition = GridConfig.WorldToFloorLocal(context.floor, position)

	if not localPosition then
		return false
	end

	local tolerance = 0.05

	return localPosition.X >= -context.halfWidthStuds - tolerance
		and localPosition.X <= context.halfWidthStuds + tolerance
		and localPosition.Z >= -context.halfDepthStuds - tolerance
		and localPosition.Z <= context.halfDepthStuds + tolerance
end

local function rootPartIsNearPosition(rootPart, position, distance)
	return rootPart
		and rootPart:IsA("BasePart")
		and typeof(position) == "Vector3"
		and (rootPart.Position - position).Magnitude <= distance
end

local function waitForRootNearPosition(rootPart, position, distance, maxSeconds, moveId, arrivalCheck)
	local startTime = os.clock()

	while os.clock() - startTime < maxSeconds do
		if moveId and moveId ~= currentMoveId then
			return false
		end

		if not rootPart or not rootPart.Parent then
			return false
		end

		if arrivalCheck and arrivalCheck() == true then
			return true
		end

		if rootPartIsNearPosition(rootPart, position, distance) then
			return true
		end

		task.wait(0.05)
	end

	if arrivalCheck and arrivalCheck() == true then
		return true
	end

	return rootPartIsNearPosition(rootPart, position, distance)
end

local function moveHumanoidDirectToPosition(humanoid, rootPart, targetPosition, distance, timeoutSeconds, moveId, arrivalCheck)
	if not humanoid or not rootPart or typeof(targetPosition) ~= "Vector3" then
		return false
	end

	local function hasArrived()
		if arrivalCheck and arrivalCheck() == true then
			return true
		end

		return rootPartIsNearPosition(rootPart, targetPosition, distance)
	end

	if hasArrived() then
		return true
	end

	humanoid:MoveTo(targetPosition)

	local startTime = os.clock()

	while os.clock() - startTime < timeoutSeconds do
		if moveId and moveId ~= currentMoveId then
			return false
		end

		if hasArrived() then
			return true
		end

		task.wait(0.05)
	end

	return hasArrived()
end

function roomMovementState.moveHumanoidToMarker(marker, options)
	options = typeof(options) == "table" and options or {}

	local markerPosition = getMarkerWorldPosition(marker)

	if not markerPosition then
		return false
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local distance = options.Distance or ENTRY_BRIDGE_REACHED_DISTANCE
	local timeoutSeconds = options.TimeoutSeconds or 3
	local moveId = options.MoveId

	if not humanoid or not rootPart then
		return false
	end

	return moveHumanoidDirectToPosition(
		humanoid,
		rootPart,
		markerPosition,
		distance,
		timeoutSeconds,
		moveId,
		function()
			return roomMovementState.characterReachedMarkerPosition(marker, distance)
		end
	)
end

local function signCellDelta(value)
	if value > 0 then
		return 1
	end

	if value < 0 then
		return -1
	end

	return 0
end

local function getWorldFacingDirectionFromCells(fromCell, toCell, context)
	if not fromCell or not toCell or not context or not context.floor then
		return nil
	end

	local deltaX = toCell.x - fromCell.x
	local deltaZ = toCell.z - fromCell.z
	local localDirection = nil

	if math.abs(deltaX) >= math.abs(deltaZ) and deltaX ~= 0 then
		localDirection = Vector3.new(signCellDelta(deltaX), 0, 0)
	elseif deltaZ ~= 0 then
		localDirection = Vector3.new(0, 0, signCellDelta(deltaZ))
	else
		return nil
	end

	local worldDirection = context.floor.CFrame:VectorToWorldSpace(localDirection)
	local flatDirection = Vector3.new(worldDirection.X, 0, worldDirection.Z)

	if flatDirection.Magnitude < 0.001 then
		return nil
	end

	return flatDirection.Unit
end

local function snapCharacterToGridFacing(rootPart, worldPosition, worldDirection)
	if not SNAP_CHARACTER_FACING_TO_GRID then
		return
	end

	if not rootPart or not rootPart:IsA("BasePart") or typeof(worldDirection) ~= "Vector3" then
		return
	end

	local character = rootPart.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid and (humanoid.Sit or humanoid.SeatPart) then
		return
	end

	local flatDirection = Vector3.new(worldDirection.X, 0, worldDirection.Z)

	if flatDirection.Magnitude < 0.001 then
		return
	end

	local position = typeof(worldPosition) == "Vector3" and worldPosition or rootPart.Position
	rootPart.AssemblyAngularVelocity = Vector3.zero
	rootPart.CFrame = CFrame.lookAt(position, position + flatDirection.Unit)
end

local function beginGridFacingControl(humanoid, moveId)
	if not SNAP_CHARACTER_FACING_TO_GRID or not humanoid then
		return
	end

	if activeGridFacingHumanoid and activeGridFacingHumanoid ~= humanoid then
		if activeGridFacingPreviousAutoRotate ~= nil then
			activeGridFacingHumanoid.AutoRotate = activeGridFacingPreviousAutoRotate
		end

		if activeGridFacingPreviousWalkSpeed ~= nil then
			activeGridFacingHumanoid.WalkSpeed = activeGridFacingPreviousWalkSpeed
		end

		activeGridFacingHumanoid = nil
		activeGridFacingPreviousAutoRotate = nil
		activeGridFacingPreviousWalkSpeed = nil
		activeGridFacingRootPart = nil
		activeGridFacingDirection = nil
		activeGridFacingMoveId = nil
	end

	if activeGridFacingHumanoid ~= humanoid then
		activeGridFacingHumanoid = humanoid
		activeGridFacingPreviousAutoRotate = humanoid.AutoRotate
		activeGridFacingPreviousWalkSpeed = humanoid.WalkSpeed
	end

	activeGridFacingMoveId = moveId
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = HOTEL_GRID_WALK_SPEED
end

local function setActiveGridFacingSegment(moveId, rootPart, worldDirection)
	if activeGridFacingMoveId ~= moveId
		or not rootPart
		or not rootPart:IsA("BasePart")
		or typeof(worldDirection) ~= "Vector3" then

		return
	end

	local flatDirection = Vector3.new(worldDirection.X, 0, worldDirection.Z)

	if flatDirection.Magnitude < 0.001 then
		return
	end

	activeGridFacingRootPart = rootPart
	activeGridFacingDirection = flatDirection.Unit
	rootPart.AssemblyAngularVelocity = Vector3.zero
	snapCharacterToGridFacing(rootPart, rootPart.Position, activeGridFacingDirection)
end

local function clearActiveGridFacingSegment()
	activeGridFacingRootPart = nil
	activeGridFacingDirection = nil
end

local function finishGridFacingControl(moveId)
	if not SNAP_CHARACTER_FACING_TO_GRID then
		return
	end

	if activeGridFacingMoveId ~= moveId then
		return
	end

	if activeGridFacingHumanoid and activeGridFacingPreviousAutoRotate ~= nil then
		activeGridFacingHumanoid.AutoRotate = activeGridFacingPreviousAutoRotate
	end

	if activeGridFacingHumanoid and activeGridFacingPreviousWalkSpeed ~= nil then
		activeGridFacingHumanoid.WalkSpeed = activeGridFacingPreviousWalkSpeed
	end

	activeGridFacingMoveId = nil
	activeGridFacingHumanoid = nil
	activeGridFacingPreviousAutoRotate = nil
	activeGridFacingPreviousWalkSpeed = nil
	clearActiveGridFacingSegment()
end

local function maintainActiveGridFacing()
	if not activeGridFacingRootPart
		or not activeGridFacingRootPart.Parent
		or not activeGridFacingDirection then

		return
	end

	if activeGridFacingMoveId ~= currentMoveId then
		clearActiveGridFacingSegment()
		return
	end

	activeGridFacingRootPart.AssemblyAngularVelocity = Vector3.zero
	snapCharacterToGridFacing(
		activeGridFacingRootPart,
		activeGridFacingRootPart.Position,
		activeGridFacingDirection
	)
end

local function clampToRoom(position, context)
	local cell = worldToCell(position, context)

	if not cell then
		return position
	end

	return cellToWorld(cell, context)
end

local function isCellInsideRoom(cell, context)
	return cell.x >= 0
		and cell.x < context.gridWidth
		and cell.z >= 0
		and cell.z < context.gridDepth
end

function roomMovementState.isPlayerInRoomGrid(rootPosition, context)
	local position = rootPosition

	if typeof(position) ~= "Vector3" then
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")

		if not rootPart then
			return false
		end

		position = rootPart.Position
	end

	if roomMovementState.isPlayerAtDoorSpawn(position) then
		return false
	end

	local movementContext = context

	if not movementContext then
		movementContext = getMovementGridContext()
	end

	if not movementContext or not worldPositionIsInsideGridBounds(position, movementContext) then
		return false
	end

	local cell = worldToCell(position, movementContext)

	return cell ~= nil and isCellInsideRoom(cell, movementContext)
end

local function cellKey(cell)
	return tostring(cell.x) .. "," .. tostring(cell.z)
end

local movementIgnoredFurniturePartNames = {
	CollisionBuffer = true,
	PlacementBounds = true,
	SitPoint = true,
	SleepPoint = true,
	PlayPoint = true,
	EnterPoint = true,
	TalkPoint = true,
	ClickHitbox = true,
}

local entranceMarkerPartNames = {
	DoorSpawn = true,
	EntryWalkTarget = true,
	RoomExitZone = true,
}

local function isMovementIgnoredFurniturePart(part)
	return movementIgnoredFurniturePartNames[part.Name] == true
end

local function isEntranceMarkerPart(part)
	return typeof(part) == "Instance"
		and part:IsA("BasePart")
		and (
			entranceMarkerPartNames[part.Name] == true
			or part:GetAttribute("IsRoomExit") == true
			or part:GetAttribute("IsEntranceMarker") == true
			or part:GetAttribute("IsDoorSpawn") == true
			or part:GetAttribute("IsEntryWalkTarget") == true
		)
end

local function getFurnitureFootprintCenter(furnitureModel)
	local placementBoundsPositionSum = Vector3.zero
	local placementBoundsCount = 0

	for _, descendant in ipairs(furnitureModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == "PlacementBounds" then
			placementBoundsPositionSum += descendant.Position
			placementBoundsCount += 1
		end
	end

	if placementBoundsCount > 0 then
		return placementBoundsPositionSum / placementBoundsCount
	end

	return furnitureModel:GetPivot().Position
end

local function getRotatedFurnitureFootprint(furnitureModel, context)
	local footprintWidth, footprintDepth = GridConfig.GetFurnitureFootprint(furnitureModel)

	-- Patch 9G will clean up template footprint attributes. For now, this supports
	-- future rectangular footprints while defaulting current furniture to 1x1.
	if footprintWidth ~= footprintDepth then
		local localLookVector = context.floor.CFrame:VectorToObjectSpace(furnitureModel:GetPivot().LookVector)

		if math.abs(localLookVector.X) > math.abs(localLookVector.Z) then
			footprintWidth, footprintDepth = footprintDepth, footprintWidth
		end
	end

	return footprintWidth, footprintDepth
end

local function cellIsInsideFurnitureFootprint(cell, centerCell, footprintWidth, footprintDepth)
	local minX = centerCell.x - math.floor((footprintWidth - 1) / 2)
	local maxX = minX + footprintWidth - 1
	local minZ = centerCell.z - math.floor((footprintDepth - 1) / 2)
	local maxZ = minZ + footprintDepth - 1

	return cell.x >= minX
		and cell.x <= maxX
		and cell.z >= minZ
		and cell.z <= maxZ
end

local function isCellBlockedByFurnitureFootprint(cell, context, furnitureFolder)
	for _, furnitureModel in ipairs(furnitureFolder:GetChildren()) do
		if furnitureModel:IsA("Model") and not furnitureModelIsWalkableDecoration(furnitureModel) then
			local footprintCenter = getFurnitureFootprintCenter(furnitureModel)
			local centerCell = worldToCell(footprintCenter, context)

			if centerCell then
				local footprintWidth, footprintDepth = getRotatedFurnitureFootprint(furnitureModel, context)

				if cellIsInsideFurnitureFootprint(cell, centerCell, footprintWidth, footprintDepth) then
					return true
				end
			end
		end
	end

	return false
end

local worldPositionIsInsideCell

local function addBlockingName(blockingNames, instance)
	if not instance then
		return
	end

	local name = instance.Name

	if not blockingNames[name] then
		blockingNames[name] = true
	end
end

local function getFurnitureFootprintBlockingNames(cell, context, furnitureFolder)
	local blockingNames = {}

	for _, furnitureModel in ipairs(furnitureFolder:GetChildren()) do
		if furnitureModel:IsA("Model") and not furnitureModelIsWalkableDecoration(furnitureModel) then
			local footprintCenter = getFurnitureFootprintCenter(furnitureModel)
			local centerCell = worldToCell(footprintCenter, context)

			if centerCell then
				local footprintWidth, footprintDepth = getRotatedFurnitureFootprint(furnitureModel, context)

				if cellIsInsideFurnitureFootprint(cell, centerCell, footprintWidth, footprintDepth) then
					addBlockingName(blockingNames, furnitureModel)
				end
			end
		end
	end

	return blockingNames
end

local function getOverlapBlockingPartNames(cell, context, roomFolder, furnitureFolder)
	local blockingNames = {}
	local center = cellToWorld(cell, context)
	local boxSize = Vector3.new(context.tileSize * 0.4, 5, context.tileSize * 0.4)
	local boxCFrame = CFrame.new(center) * context.floorRotation
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	local ignoreList = {}

	if player.Character then
		table.insert(ignoreList, player.Character)
	end

	overlapParams.FilterDescendantsInstances = ignoreList

	local parts = workspace:GetPartBoundsInBox(boxCFrame, boxSize, overlapParams)

	for _, part in ipairs(parts) do
		if isEntranceMarkerPart(part) then
			continue
		end

		if isWalkableSurfacePart(part) then
			continue
		end

		if isMovementIgnoredFurniturePart(part) then
			continue
		end

		if part:IsDescendantOf(furnitureFolder) then
			continue
		end

		if part:IsA("BasePart") and part.CanCollide == false then
			continue
		end

		if part:IsDescendantOf(roomFolder) then
			if part.Name:find("Boundary") or part.Name:find("Wall") then
				if worldPositionIsInsideCell(part.Position, cell, context) then
					addBlockingName(blockingNames, part)
				end

				continue
			end
		end
	end

	return blockingNames
end

local function namesDictionaryToList(namesDictionary)
	local names = {}

	for name in pairs(namesDictionary) do
		table.insert(names, name)
	end

	table.sort(names)
	return names
end

local function getCellBlockingNames(cell, context)
	local roomFolder = getCurrentRoomFolder()
	local furnitureFolder = getCurrentFurnitureFolder()
	local blockingNames = {}

	if not roomFolder then
		blockingNames.MissingRoomFolder = true
	end

	if not furnitureFolder then
		blockingNames.MissingFurnitureFolder = true
	end

	if not roomFolder or not furnitureFolder then
		return namesDictionaryToList(blockingNames)
	end

	for name in pairs(getFurnitureFootprintBlockingNames(cell, context, furnitureFolder)) do
		blockingNames[name] = true
	end

	for name in pairs(getOverlapBlockingPartNames(cell, context, roomFolder, furnitureFolder)) do
		blockingNames[name] = true
	end

	return namesDictionaryToList(blockingNames)
end

function worldPositionIsInsideCell(worldPosition, cell, context)
	local localPosition = GridConfig.WorldToFloorLocal(context.floor, worldPosition)

	if not localPosition then
		return false
	end

	local localCellX = cellIndexToLocalAxis(cell.x, context.tileSize, context.halfWidthStuds)
	local localCellZ = cellIndexToLocalAxis(cell.z, context.tileSize, context.halfDepthStuds)
	local halfCell = context.tileSize / 2

	return localPosition.X > localCellX - halfCell
		and localPosition.X < localCellX + halfCell
		and localPosition.Z > localCellZ - halfCell
		and localPosition.Z < localCellZ + halfCell
end

local function isCellBlocked(cell, context)
	local roomFolder = getCurrentRoomFolder()
	local furnitureFolder = getCurrentFurnitureFolder()

	if not roomFolder or not furnitureFolder then
		return true
	end

	if isCellBlockedByFurnitureFootprint(cell, context, furnitureFolder) then
		return true
	end

	local center = cellToWorld(cell, context)

	local boxSize = Vector3.new(context.tileSize * 0.4, 5, context.tileSize * 0.4)
	local boxCFrame = CFrame.new(center) * context.floorRotation

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	local ignoreList = {}

	if player.Character then
		table.insert(ignoreList, player.Character)
	end

	overlapParams.FilterDescendantsInstances = ignoreList

	local parts = workspace:GetPartBoundsInBox(boxCFrame, boxSize, overlapParams)

	for _, part in ipairs(parts) do
		if isEntranceMarkerPart(part) then
			continue
		end

		if isWalkableSurfacePart(part) then
			continue
		end

		if isMovementIgnoredFurniturePart(part) then
			continue
		end

		if part:IsDescendantOf(furnitureFolder) then
			continue
		end

		if part:IsA("BasePart") and part.CanCollide == false then
			continue
		end

		if part:IsDescendantOf(roomFolder) then
			if part.Name:find("Boundary") or part.Name:find("Wall") then
				if worldPositionIsInsideCell(part.Position, cell, context) then
					return true
				end

				continue
			end
		end
	end

	return false
end

local function getNearestValidStartCellFromPosition(rootPosition, context)
	if typeof(rootPosition) ~= "Vector3" or not context then
		return nil
	end

	local currentCell = worldToCell(rootPosition, context)

	if currentCell
		and isCellInsideRoom(currentCell, context)
		and not isCellBlocked(currentCell, context) then

		return currentCell
	end

	if not currentCell or not isCellInsideRoom(currentCell, context) then
		return nil
	end

	local bestCell = nil
	local bestDistance = math.huge
	local maxDistance = context.tileSize * 1.5

	for radius = 1, 2 do
		for x = currentCell.x - radius, currentCell.x + radius do
			for z = currentCell.z - radius, currentCell.z + radius do
				local cell = { x = x, z = z }

				if isCellInsideRoom(cell, context) and not isCellBlocked(cell, context) then
					local worldPosition = cellToWorld(cell, context)
					local distance = (Vector3.new(worldPosition.X, rootPosition.Y, worldPosition.Z) - rootPosition).Magnitude

					if distance < bestDistance then
						bestDistance = distance
						bestCell = cell
					end
				end
			end
		end

		if bestCell and bestDistance <= maxDistance then
			return bestCell
		end
	end

	return nil
end

local function formatVector3(position)
	if typeof(position) ~= "Vector3" then
		return "nil"
	end

	return string.format("%.2f, %.2f, %.2f", position.X, position.Y, position.Z)
end

local function formatCell(cell)
	if not cell then
		return "nil"
	end

	return tostring(cell.x) .. "," .. tostring(cell.z)
end

local function logEntranceBridgeBlocked(reason, context, entryWalkTarget, bridgeCell)
	local roomName = player:GetAttribute("CurrentRoomName") or "UnknownRoom"
	local key = tostring(roomName) .. ":" .. tostring(reason)

	if entranceBridgeDiagnosticsLogged[key] then
		return
	end

	entranceBridgeDiagnosticsLogged[key] = true

	local entryPosition = getMarkerWorldPosition(entryWalkTarget)
	local blockingNames = {}

	if bridgeCell then
		blockingNames = getCellBlockingNames(bridgeCell, context)
	end

	if #blockingNames == 0 then
		blockingNames = { "none reported" }
	end

	warn(string.format(
		"[ClickToMoveController] Room entrance is blocked. Reason=%s EntryWalkTarget=%s EntryWalkTargetPosition=(%s) bridgeCell=%s blockers=%s",
		tostring(reason),
		entryWalkTarget and "found" or "missing",
		formatVector3(entryPosition),
		formatCell(bridgeCell),
		table.concat(blockingNames, ", ")
	))
end

function roomMovementState.warnCouldNotReachEntrance()
	local now = os.clock()

	if now - roomMovementState.lastEntranceReachWarningAt < 2 then
		return
	end

	roomMovementState.lastEntranceReachWarningAt = now
	warn("Could not reach room entrance.")
end

local function getBridgeStartCellIfNeeded(rootPosition, context)
	local rootInsideGrid = worldPositionIsInsideGridBounds(rootPosition, context)
	local atDoorSpawn = roomMovementState.isPlayerAtDoorSpawn(rootPosition)
	local inRoomGrid = roomMovementState.isPlayerInRoomGrid(rootPosition, context)

	if inRoomGrid or (rootInsideGrid and not atDoorSpawn) then
		return nil, nil, nil
	end

	if not atDoorSpawn then
		return nil, nil, "Cannot enter room grid from current position."
	end

	local entryWalkTarget = getCurrentEntryWalkTarget()
	local entryPosition = getMarkerWorldPosition(entryWalkTarget)

	if entryPosition then
		local entryCell = worldToCell(entryPosition, context)

		if not entryCell or not isCellInsideRoom(entryCell, context) then
			return nil, nil, "Cannot enter room grid from current position."
		end

		if isCellBlocked(entryCell, context) then
			logEntranceBridgeBlocked("EntryWalkTargetBlocked", context, entryWalkTarget, entryCell)
			return nil, nil, "Room entrance is blocked."
		end

		return entryCell, Vector3.new(entryPosition.X, context.moveY, entryPosition.Z), nil
	end

	return nil, nil, "Could not reach room entrance."
end

local function getNeighbors(cell)
	return {
		{ x = cell.x + 1, z = cell.z },
		{ x = cell.x - 1, z = cell.z },
		{ x = cell.x, z = cell.z + 1 },
		{ x = cell.x, z = cell.z - 1 },
	}
end

local function getCellDistance(a, b)
	return math.abs(a.x - b.x) + math.abs(a.z - b.z)
end

local function cellsAreSame(a, b)
	return a.x == b.x and a.z == b.z
end

local function findGridPath(startCell, goalCell, context)
	local queue = {}
	local cameFrom = {}
	local visited = {}

	local closestCell = startCell
	local closestDistance = getCellDistance(startCell, goalCell)

	table.insert(queue, startCell)
	visited[cellKey(startCell)] = true

	while #queue > 0 do
		local current = table.remove(queue, 1)

		local currentDistance = getCellDistance(current, goalCell)

		if currentDistance < closestDistance then
			closestDistance = currentDistance
			closestCell = current
		end

		if cellsAreSame(current, goalCell) then
			local path = {}
			local step = current

			while step do
				table.insert(path, 1, step)
				step = cameFrom[cellKey(step)]
			end

			return path, true
		end

		for _, neighbor in ipairs(getNeighbors(current)) do
			local key = cellKey(neighbor)

			if not visited[key]
				and isCellInsideRoom(neighbor, context)
				and not isCellBlocked(neighbor, context) then

				visited[key] = true
				cameFrom[key] = current
				table.insert(queue, neighbor)
			end
		end
	end

	-- If the clicked tile cannot be reached, walk to the closest reachable tile.
	local fallbackPath = {}
	local step = closestCell

	while step do
		table.insert(fallbackPath, 1, step)
		step = cameFrom[cellKey(step)]
	end

	return fallbackPath, false
end

local function compressGridPath(path)
	if not path or #path <= 2 then
		return path
	end

	local compressedPath = {}

	table.insert(compressedPath, path[1])

	local lastDirection = nil

	for index = 2, #path do
		local previousCell = path[index - 1]
		local currentCell = path[index]

		local direction = {
			x = currentCell.x - previousCell.x,
			z = currentCell.z - previousCell.z
		}

		if lastDirection
			and (direction.x ~= lastDirection.x or direction.z ~= lastDirection.z) then

			-- Add the cell before the turn.
			table.insert(compressedPath, previousCell)
		end

		lastDirection = direction
	end

	-- Always include final destination.
	table.insert(compressedPath, path[#path])

	return compressedPath
end

local function moveCharacterTo(destination, options)
	options = typeof(options) == "table" and options or {}

	if roomMovementState.caveTransitionActive and options.AllowDuringCaveTransition ~= true then
		return false
	end

	local requestedRoomName = player:GetAttribute("CurrentRoomName")

	if not roomMovementState.waitForCurrentRoomReady()
		or player:GetAttribute("CurrentRoomName") ~= requestedRoomName then

		return false
	end

	local now = os.clock()

	if now - lastMoveTime < CLICK_MOVE_COOLDOWN then
		return false
	end

	lastMoveTime = now

	currentMoveId += 1
	local moveId = currentMoveId
	local expectedRoomName = player:GetAttribute("CurrentRoomName")

	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")

	local context, contextMessage = getMovementGridContext()

	if not context then
		if contextMessage and not warnedTileGridDisabled then
			warn(contextMessage)
			warnedTileGridDisabled = true
		end

		return false
	end

	character = player.Character or character
	humanoid = character and character:FindFirstChildOfClass("Humanoid")
	rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then
		return false
	end

	local clampedDestination = clampToRoom(destination, context)

	local startCell = worldToCell(rootPart.Position, context)
	local goalCell = worldToCell(clampedDestination, context)
	local bridgeCell, bridgeWorldPosition, bridgeMessage = getBridgeStartCellIfNeeded(rootPart.Position, context)

	if not goalCell then
		return false
	end

	if bridgeMessage then
		warn(bridgeMessage)
		return false
	end

	if bridgeCell then
		startCell = bridgeCell
	elseif startCell
		and isCellBlocked(startCell, context)
		and os.clock() - lastSeatedStandCompletedAt <= 2.5 then

		local adjustedStartCell = getNearestValidStartCellFromPosition(rootPart.Position, context)

		if adjustedStartCell then
			startCell = adjustedStartCell
		else
			warn("Could not find a valid movement start tile after standing")
			return false
		end
	end

	if not startCell then
		return false
	end

	if startCell.x == goalCell.x and startCell.z == goalCell.z and not bridgeCell then
		return true
	end

	local path, reachedGoal = findGridPath(startCell, goalCell, context)

	if not path or #path == 0 then
		warn("No grid path found")
		return false
	end

	if not reachedGoal and options.SuppressBlockedWarning ~= true then
		warn("Clicked tile is blocked, moving to closest reachable tile")
	end

	local movementPath = compressGridPath(path)
	local ownsCaveTransition = false

	if bridgeCell then
		if not roomMovementState.caveTransitionActive then
			roomMovementState.setCaveTransitionActive(true)
			ownsCaveTransition = true
		end

		if moveId ~= currentMoveId or player:GetAttribute("CurrentRoomName") ~= expectedRoomName then
			if ownsCaveTransition then
				roomMovementState.setCaveTransitionActive(false)
			end

			return false
		end

		local entryWalkTarget = getCurrentEntryWalkTarget()
		local reachedBridge = false

		if entryWalkTarget then
			reachedBridge = roomMovementState.moveHumanoidToMarker(entryWalkTarget, {
				Distance = ENTRY_BRIDGE_REACHED_DISTANCE,
				TimeoutSeconds = EXIT_ENTRY_MOVE_TIMEOUT_SECONDS,
				MoveId = moveId,
			})
		else
			reachedBridge = moveHumanoidDirectToPosition(
				humanoid,
				rootPart,
				bridgeWorldPosition,
				ENTRY_BRIDGE_REACHED_DISTANCE,
				EXIT_ENTRY_MOVE_TIMEOUT_SECONDS,
				moveId
			)
		end

		if moveId ~= currentMoveId or player:GetAttribute("CurrentRoomName") ~= expectedRoomName then
			if ownsCaveTransition then
				roomMovementState.setCaveTransitionActive(false)
			end

			return false
		end

		if not reachedBridge then

			local blockingNames = getCellBlockingNames(bridgeCell, context)

			if #blockingNames > 0 then
				logEntranceBridgeBlocked("BridgeMoveFailed", context, entryWalkTarget, bridgeCell)
				warn("Room entrance is blocked.")
			else
				roomMovementState.warnCouldNotReachEntrance()
			end

			if ownsCaveTransition then
				roomMovementState.setCaveTransitionActive(false)
			end

			return false
		end

		if cellsAreSame(bridgeCell, goalCell) then
			if ownsCaveTransition then
				roomMovementState.setCaveTransitionActive(false)
			end

			return true
		end
	end

	beginGridFacingControl(humanoid, moveId)

	for index, cell in ipairs(movementPath) do
		if moveId ~= currentMoveId or player:GetAttribute("CurrentRoomName") ~= expectedRoomName then
			finishGridFacingControl(moveId)
			if ownsCaveTransition then
				roomMovementState.setCaveTransitionActive(false)
			end

			return false
		end

		-- Skip the starting tile.
		if index == 1 then
			continue
		end

		local previousCell = movementPath[index - 1]
		local worldPosition = cellToWorld(cell, context)
		local facingDirection = getWorldFacingDirectionFromCells(previousCell, cell, context)

		if facingDirection then
			setActiveGridFacingSegment(moveId, rootPart, facingDirection)
			snapCharacterToGridFacing(rootPart, rootPart.Position, facingDirection)
		end

		humanoid:MoveTo(worldPosition)

		local reached = humanoid.MoveToFinished:Wait()

		if moveId ~= currentMoveId then
			finishGridFacingControl(moveId)
			if ownsCaveTransition then
				roomMovementState.setCaveTransitionActive(false)
			end

			return false
		end

		if not reached then
			warn("Could not reach movement segment")
			finishGridFacingControl(moveId)
			if ownsCaveTransition then
				roomMovementState.setCaveTransitionActive(false)
			end

			return false
		end

		if facingDirection then
			local reachedPosition = Vector3.new(worldPosition.X, rootPart.Position.Y, worldPosition.Z)
			snapCharacterToGridFacing(rootPart, reachedPosition, facingDirection)
		end
	end

	finishGridFacingControl(moveId)
	if ownsCaveTransition then
		roomMovementState.setCaveTransitionActive(false)
	end

	return reachedGoal == true
end

local furnitureInteraction = {}

function furnitureInteraction.getModelFromTarget(target)
	if not target then
		return nil
	end

	local furnitureFolder = getCurrentFurnitureFolder()

	if not furnitureFolder then
		return nil
	end

	local current = target

	while current and current ~= workspace do
		if current:IsA("Model") and current:IsDescendantOf(furnitureFolder) then
			return current
		end

		current = current.Parent
	end

	return nil
end

function furnitureInteraction.getTopPosition(furnitureModel)
	local modelCFrame, modelSize = furnitureModel:GetBoundingBox()

	local topPosition = modelCFrame.Position + Vector3.new(0, modelSize.Y / 2 + 2, 0)

	return topPosition
end

function furnitureInteraction.getSitPoint(furnitureModel)
	if typeof(furnitureModel) ~= "Instance" or not furnitureModel:IsA("Model") then
		return nil
	end

	local sitPoint = furnitureModel:FindFirstChild("SitPoint", true)

	if sitPoint and (sitPoint:IsA("Attachment") or sitPoint:IsA("BasePart")) then
		return sitPoint
	end

	return nil
end

function furnitureInteraction.getSitPointWorldPosition(sitPoint)
	if not sitPoint then
		return nil
	end

	if sitPoint:IsA("Attachment") then
		return sitPoint.WorldPosition
	end

	if sitPoint:IsA("BasePart") then
		return sitPoint.Position
	end

	return nil
end

local function getCurrentWalkableSurfaceParts()
	local currentFloor = getCurrentFloor()

	if not currentFloor or not currentFloor:IsA("BasePart") then
		return {}
	end

	local walkableSurfaces = {
		currentFloor,
	}

	local roomModel = getCurrentRoomModel()

	if roomModel then
		for _, descendant in ipairs(roomModel:GetDescendants()) do
			if descendant ~= currentFloor and isWalkableSurfacePart(descendant) then
				table.insert(walkableSurfaces, descendant)
			end
		end
	end

	return walkableSurfaces
end

local function getMouseFloorRaycastResult()
	local walkableSurfaces = getCurrentWalkableSurfaceParts()

	if #walkableSurfaces == 0 then
		return nil
	end

	local camera = workspace.CurrentCamera

	if not camera then
		return nil
	end

	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = walkableSurfaces

	return workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)
end

local function getMouseFloorPosition()
	local floorRaycastResult = getMouseFloorRaycastResult()

	if not floorRaycastResult then
		return nil
	end

	return floorRaycastResult.Position
end

local function getGridSnappedFloorPosition(floorPosition)
	local roomModel = getCurrentRoomModel()
	local floor = getCurrentFloor()

	if not roomModel or not floor or not floor:IsA("BasePart") then
		return nil
	end

	if not GridConfig.UsesTileGrid(roomModel, floor) then
		return nil
	end

	local tileSize = GridConfig.GetTileSize(roomModel, floor)
	local snappedWorldPosition = GridConfig.SnapWorldToTileCenter(floor, floorPosition, tileSize)

	if not snappedWorldPosition then
		return nil
	end

	return Vector3.new(snappedWorldPosition.X, floorPosition.Y, snappedWorldPosition.Z)
end

local function getFloorPlacementBounds()
	local floor = getCurrentFloor()

	if not floor then
		return nil
	end

	local halfX = floor.Size.X / 2
	local halfZ = floor.Size.Z / 2

	return {
		minX = floor.Position.X - halfX,
		maxX = floor.Position.X + halfX,
		minZ = floor.Position.Z - halfZ,
		maxZ = floor.Position.Z + halfZ,
	}
end

local helperPartNames = {
	CollisionBuffer = true,
	ClickHitbox = true,
	SitPoint = true,
	SleepPoint = true,
	PlayPoint = true,
	EnterPoint = true,
	TalkPoint = true,
}

local function shouldUsePartForPlacementBounds(part)
	if not part:IsA("BasePart") then
		return false
	end

	if helperPartNames[part.Name] == true then
		return false
	end

	-- Include real furniture body parts and collision buffers.
	if part.CanCollide then
		return true
	end

	if part.Transparency < 1 then
		return true
	end

	return false
end

local function getPlacementBoundsParts(model)
	local parts = {}

	if not model then
		return parts
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart")
			and descendant.Name == "PlacementBounds" then

			table.insert(parts, descendant)
		end
	end

	return parts
end

local function getPlacementCheckParts(model)
	local placementBoundsParts = getPlacementBoundsParts(model)

	if #placementBoundsParts > 0 then
		return placementBoundsParts
	end

	local fallbackParts = {}

	for _, descendant in ipairs(model:GetDescendants()) do
		if shouldUsePartForPlacementBounds(descendant) then
			table.insert(fallbackParts, descendant)
		end
	end

	return fallbackParts
end

local function getFurnitureModelFromDescendant(instance, furnitureFolder)
	local current = instance

	while current and current ~= furnitureFolder do
		if current:IsA("Model") and current.Parent == furnitureFolder then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function shouldIgnoreTouchedFurniturePart(touchingPart, furnitureFolder)
	local touchedFurnitureModel = getFurnitureModelFromDescendant(
		touchingPart,
		furnitureFolder
	)

	if not touchedFurnitureModel then
		return false
	end

	if #getPlacementBoundsParts(touchedFurnitureModel) > 0
		and touchingPart.Name ~= "PlacementBounds" then

		return true
	end

	return false
end

local function getOverlapCheckSize(size)
	return Vector3.new(
		math.max(size.X - 0.08, 0.05),
		math.max(size.Y - 0.08, 0.05),
		math.max(size.Z - 0.08, 0.05)
	)
end

local PLACEMENT_CONTAINMENT_EPSILON = GridConfig.GRID_VALIDATION_TOLERANCE or 0.05

local function getPartWorldCornersFromCFrame(cframe, size)
	local halfSize = size / 2

	local localCorners = {
		Vector3.new(-halfSize.X, -halfSize.Y, -halfSize.Z),
		Vector3.new(-halfSize.X, -halfSize.Y, halfSize.Z),
		Vector3.new(-halfSize.X, halfSize.Y, -halfSize.Z),
		Vector3.new(-halfSize.X, halfSize.Y, halfSize.Z),
		Vector3.new(halfSize.X, -halfSize.Y, -halfSize.Z),
		Vector3.new(halfSize.X, -halfSize.Y, halfSize.Z),
		Vector3.new(halfSize.X, halfSize.Y, -halfSize.Z),
		Vector3.new(halfSize.X, halfSize.Y, halfSize.Z),
	}

	local worldCorners = {}

	for _, localCorner in ipairs(localCorners) do
		table.insert(worldCorners, cframe:PointToWorldSpace(localCorner))
	end

	return worldCorners
end

local function getModelXZBoundsAtCFrame(model, targetCFrame)
	local currentPivot = model:GetPivot()

	local minX = math.huge
	local maxX = -math.huge
	local minZ = math.huge
	local maxZ = -math.huge

	local foundPart = false

	for _, descendant in ipairs(getPlacementCheckParts(model)) do
		foundPart = true

		local relativeCFrame = currentPivot:ToObjectSpace(descendant.CFrame)
		local predictedCFrame = targetCFrame * relativeCFrame

		for _, corner in ipairs(getPartWorldCornersFromCFrame(predictedCFrame, descendant.Size)) do
			minX = math.min(minX, corner.X)
			maxX = math.max(maxX, corner.X)
			minZ = math.min(minZ, corner.Z)
			maxZ = math.max(maxZ, corner.Z)
		end
	end

	if not foundPart then
		return nil
	end

	return {
		minX = minX,
		maxX = maxX,
		minZ = minZ,
		maxZ = maxZ,
	}
end

local function clampFurnitureCFrameInsideRoom(model, targetCFrame)
	local floorBounds = getFloorPlacementBounds()
	local modelBounds = getModelXZBoundsAtCFrame(model, targetCFrame)

	if not floorBounds or not modelBounds then
		return targetCFrame
	end

	local offsetX = 0
	local offsetZ = 0

	if modelBounds.minX < floorBounds.minX - PLACEMENT_CONTAINMENT_EPSILON then
		offsetX = floorBounds.minX - modelBounds.minX
	elseif modelBounds.maxX > floorBounds.maxX + PLACEMENT_CONTAINMENT_EPSILON then
		offsetX = floorBounds.maxX - modelBounds.maxX
	end

	if modelBounds.minZ < floorBounds.minZ - PLACEMENT_CONTAINMENT_EPSILON then
		offsetZ = floorBounds.minZ - modelBounds.minZ
	elseif modelBounds.maxZ > floorBounds.maxZ + PLACEMENT_CONTAINMENT_EPSILON then
		offsetZ = floorBounds.maxZ - modelBounds.maxZ
	end

	return targetCFrame + Vector3.new(offsetX, 0, offsetZ)
end

local function getSnappedPlacementPosition()
	local floorPosition = getMouseFloorPosition()

	if not floorPosition then
		return nil
	end

	local snappedFloorPosition = getGridSnappedFloorPosition(floorPosition)

	if not snappedFloorPosition then
		return nil
	end

	if not movingFurniture then
		return snappedFloorPosition
	end

	local currentPivot = movingFurniture:GetPivot()
	local currentRotation = currentPivot - currentPivot.Position

	local targetPosition = Vector3.new(
		snappedFloorPosition.X,
		currentPivot.Position.Y,
		snappedFloorPosition.Z
	)

	local targetCFrame = CFrame.new(targetPosition) * currentRotation

	return Vector3.new(
		targetCFrame.Position.X,
		floorPosition.Y,
		targetCFrame.Position.Z
	)
end

local function getPartWorldCorners(part)
	local halfSize = part.Size / 2

	local localCorners = {
		Vector3.new(-halfSize.X, -halfSize.Y, -halfSize.Z),
		Vector3.new(-halfSize.X, -halfSize.Y, halfSize.Z),
		Vector3.new(-halfSize.X, halfSize.Y, -halfSize.Z),
		Vector3.new(-halfSize.X, halfSize.Y, halfSize.Z),
		Vector3.new(halfSize.X, -halfSize.Y, -halfSize.Z),
		Vector3.new(halfSize.X, -halfSize.Y, halfSize.Z),
		Vector3.new(halfSize.X, halfSize.Y, -halfSize.Z),
		Vector3.new(halfSize.X, halfSize.Y, halfSize.Z),
	}

	local worldCorners = {}

	for _, localCorner in ipairs(localCorners) do
		table.insert(worldCorners, part.CFrame:PointToWorldSpace(localCorner))
	end

	return worldCorners
end

local function getModelXZBounds(model)
	local minX = math.huge
	local maxX = -math.huge
	local minZ = math.huge
	local maxZ = -math.huge

	local foundPart = false

	for _, descendant in ipairs(getPlacementCheckParts(model)) do
		foundPart = true

		for _, corner in ipairs(getPartWorldCorners(descendant)) do
			minX = math.min(minX, corner.X)
			maxX = math.max(maxX, corner.X)
			minZ = math.min(minZ, corner.Z)
			maxZ = math.max(maxZ, corner.Z)
		end
	end

	if not foundPart then
		return nil
	end

	return {
		minX = minX,
		maxX = maxX,
		minZ = minZ,
		maxZ = maxZ,
	}
end

local function isPreviewInsideRoom(previewModel)
	local previewBounds = getModelXZBounds(previewModel)
	local floorBounds = getFloorPlacementBounds()

	if not previewBounds or not floorBounds then
		return false
	end

	return previewBounds.minX >= floorBounds.minX - PLACEMENT_CONTAINMENT_EPSILON
		and previewBounds.maxX <= floorBounds.maxX + PLACEMENT_CONTAINMENT_EPSILON
		and previewBounds.minZ >= floorBounds.minZ - PLACEMENT_CONTAINMENT_EPSILON
		and previewBounds.maxZ <= floorBounds.maxZ + PLACEMENT_CONTAINMENT_EPSILON
end

local function isPreviewBlocked(previewModel)
	local roomFolder = getCurrentRoomFolder()
	local furnitureFolder = getCurrentFurnitureFolder()

	if not roomFolder or not furnitureFolder then
		return true
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	local ignoreList = {
		previewModel,
		movingFurniture,
	}

	if player.Character then
		table.insert(ignoreList, player.Character)
	end

	overlapParams.FilterDescendantsInstances = ignoreList

	for _, descendant in ipairs(getPlacementCheckParts(previewModel)) do
		local touchingParts = workspace:GetPartBoundsInBox(
			descendant.CFrame,
			getOverlapCheckSize(descendant.Size),
			overlapParams
		)

		for _, part in ipairs(touchingParts) do
			if part.Name == "WalkableFloor" then
				continue
			end

			if helperPartNames[part.Name] == true then
				continue
			end

			if part:IsDescendantOf(furnitureFolder) then
				if shouldIgnoreTouchedFurniturePart(part, furnitureFolder) then
					continue
				end

				if part.Name ~= "PlacementBounds"
					and part:IsA("BasePart")
					and part.CanCollide == false then

					continue
				end

				return true
			end

			if part:IsDescendantOf(roomFolder) then
				if part.Name:find("Boundary") or part.Name:find("Wall") then
					return true
				end

				if part:IsA("BasePart") and part.CanCollide then
					return true
				end
			end
		end
	end

	return false
end

local function playerIsInSameRoom(otherPlayer)
	return otherPlayer:GetAttribute("CurrentRoomName") == player:GetAttribute("CurrentRoomName")
end

local function isPreviewBlockedByPlayer(previewModel)
	local ignoredCharacter = nil

	if movingFurniture then
		local occupyingHumanoid = getFurnitureOccupantHumanoid(movingFurniture)

		if occupyingHumanoid then
			ignoredCharacter = occupyingHumanoid.Parent
		end
	end

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if playerIsInSameRoom(otherPlayer) then
			local character = otherPlayer.Character

			if character and character ~= ignoredCharacter then
				local overlapParams = OverlapParams.new()
				overlapParams.FilterType = Enum.RaycastFilterType.Include
				overlapParams.FilterDescendantsInstances = { character }

				for _, descendant in ipairs(getPlacementCheckParts(previewModel)) do
					local touchingParts = workspace:GetPartBoundsInBox(
						descendant.CFrame,
						getOverlapCheckSize(descendant.Size),
						overlapParams
					)

					if #touchingParts > 0 then
						return true
					end
				end
			end
		end
	end

	return false
end

local function setPlacementPreviewValidity(isValid)
	placementIsValid = isValid

	local fillColor
	local outlineColor

	if isValid then
		-- Bright cyan/blue is easier to see against green walls.
		fillColor = Color3.fromRGB(0, 190, 255)
		outlineColor = Color3.fromRGB(255, 255, 255)
	else
		fillColor = Color3.fromRGB(255, 60, 60)
		outlineColor = Color3.fromRGB(255, 255, 255)
	end

	if placementPreviewHighlight then
		placementPreviewHighlight.Enabled = true
		placementPreviewHighlight.FillColor = fillColor
		placementPreviewHighlight.OutlineColor = outlineColor
		placementPreviewHighlight.FillTransparency = 0.35
		placementPreviewHighlight.OutlineTransparency = 0
		placementPreviewHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	end

	if placementPreview then
		for _, descendant in ipairs(placementPreview:GetDescendants()) do
			if descendant:IsA("BasePart") then
				if descendant.Name ~= "SitPoint"
					and descendant.Name ~= "SleepPoint"
					and descendant.Name ~= "PlayPoint"
					and descendant.Name ~= "EnterPoint"
					and descendant.Name ~= "TalkPoint" then

					descendant.Color = fillColor
					descendant.Transparency = 0.35
					descendant.Material = Enum.Material.Neon
				end
			end
		end
	end
end

local function checkPlacementPreviewValidity()
	if not placementPreview then
		return false
	end

	if not isPreviewInsideRoom(placementPreview) then
		return false
	end

	if isPreviewBlocked(placementPreview) then
		return false
	end

	if isPreviewBlockedByPlayer(placementPreview) then
		return false
	end

	return true
end

local function setMovingFurnitureIgnored(shouldIgnore)
	if shouldIgnore and movingFurniture then
		mouse.TargetFilter = movingFurniture
	else
		mouse.TargetFilter = nil
	end
end

local function showOriginalFurniture()
	for part, oldLocalTransparencyModifier in pairs(hiddenFurnitureParts) do
		if part and part.Parent then
			part.LocalTransparencyModifier = oldLocalTransparencyModifier
		end
	end

	hiddenFurnitureParts = {}
end

function movePreviewState.ensureHint()
	if movePreviewState.hintGui and movePreviewState.hintGui.Parent then
		return
	end

	local hintGui = Instance.new("ScreenGui")
	hintGui.Name = "FurnitureMovePreviewHintGui"
	hintGui.ResetOnSpawn = false
	hintGui.IgnoreGuiInset = true
	hintGui.DisplayOrder = 210
	hintGui.Enabled = false
	hintGui.Parent = playerGui

	local hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "Hint"
	hintLabel.AnchorPoint = Vector2.new(0.5, 1)
	hintLabel.Position = UDim2.new(0.5, 0, 1, -movePreviewState.helperUi.fallbackBottomOffset)
	hintLabel.Size = UDim2.fromOffset(220, 34)
	hintLabel.BackgroundColor3 = Color3.fromRGB(32, 38, 46)
	hintLabel.BackgroundTransparency = 0.12
	hintLabel.BorderSizePixel = 0
	hintLabel.Text = "R to rotate  C to cancel"
	hintLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	hintLabel.TextSize = 14
	hintLabel.Font = Enum.Font.GothamBold
	hintLabel.Active = false
	hintLabel.Selectable = false
	hintLabel.Parent = hintGui
	ensureCorner(hintLabel, 8)
	ensureStroke(hintLabel, Color3.fromRGB(255, 255, 255), 1, 0.72)

	movePreviewState.hintGui = hintGui
	movePreviewState.hintLabel = hintLabel
	movePreviewState.helperUi.register(hintLabel)
end

function movePreviewState.showHint()
	movePreviewState.ensureHint()
	movePreviewState.hintGui.Enabled = true
end

function movePreviewState.hideHint()
	if movePreviewState.hintGui then
		movePreviewState.hintGui.Enabled = false
	end
end

function movePreviewState.reset()
	movePreviewState.rotationOffsetY = 0
	movePreviewState.hideHint()
end

local function destroyPlacementPreview()
	if placementPreview then
		placementPreview:Destroy()
		placementPreview = nil
	end

	if placementPreviewHighlight then
		placementPreviewHighlight:Destroy()
		placementPreviewHighlight = nil
	end

	placementIsValid = false
	movePreviewState.hideHint()

	showOriginalFurniture()
	setMovingFurnitureIgnored(false)
end

local function dimOriginalFurniture(furnitureModel)
	hiddenFurnitureParts = {}

	if not furnitureModel then
		return
	end

	for _, descendant in ipairs(furnitureModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			hiddenFurnitureParts[descendant] = descendant.LocalTransparencyModifier

			-- Keep the original visible, but faded.
			descendant.LocalTransparencyModifier = math.max(
				descendant.LocalTransparencyModifier,
				0.65
			)
		end
	end
end

local function createPlacementPreview(furnitureModel)
	destroyPlacementPreview()

	if not furnitureModel then
		return
	end

	placementPreview = furnitureModel:Clone()
	placementPreview.Name = "PlacementPreview"

	for _, descendant in ipairs(placementPreview:GetDescendants()) do
		if descendant:IsA("Script")
			or descendant:IsA("LocalScript")
			or descendant:IsA("ClickDetector") then

			descendant:Destroy()

		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Transparency = math.max(descendant.Transparency, 0.55)
		end
	end

	placementPreview.Parent = workspace
	
	placementPreviewHighlight = Instance.new("Highlight")
	placementPreviewHighlight.Name = "PlacementPreviewHighlight"
	placementPreviewHighlight.Adornee = placementPreview
	placementPreviewHighlight.FillTransparency = 0.45
	placementPreviewHighlight.OutlineTransparency = 0
	placementPreviewHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	placementPreviewHighlight.Parent = placementPreview

	setPlacementPreviewValidity(false)
end

local function updatePlacementPreview()
	if not movingFurniture or not placementPreview then
		return
	end

	local placementPosition = getSnappedPlacementPosition()

	if not placementPosition then
		return
	end

	local currentPivot = movingFurniture:GetPivot()
	local currentRotation = currentPivot - currentPivot.Position
	local previewRotation =
		currentRotation * CFrame.Angles(0, math.rad(movePreviewState.rotationOffsetY), 0)

	local previewPosition = Vector3.new(
		placementPosition.X,
		currentPivot.Position.Y,
		placementPosition.Z
	)

	placementPreview:PivotTo(CFrame.new(previewPosition) * previewRotation)

	local isValid = checkPlacementPreviewValidity()
	setPlacementPreviewValidity(isValid)
end

local function updateMenuPosition()
	if not selectedFurniture then
		return
	end

	if not menuFrame.Visible then
		return
	end

	local camera = workspace.CurrentCamera
	local worldPosition = furnitureInteraction.getTopPosition(selectedFurniture)

	local screenPosition, onScreen = camera:WorldToScreenPoint(worldPosition)

	if onScreen then
		local menuSize = menuFrame.AbsoluteSize

		if menuSize.X <= 0 or menuSize.Y <= 0 then
			menuSize = Vector2.new(menuFrame.Size.X.Offset, menuFrame.Size.Y.Offset)
		end

		local viewportSize = camera.ViewportSize
		local minX = menuSize.X / 2 + MENU_MARGIN
		local maxX = viewportSize.X - menuSize.X / 2 - MENU_MARGIN
		local minY = menuSize.Y + MENU_TOP_MARGIN
		local maxY = viewportSize.Y - MENU_MARGIN
		local targetX = screenPosition.X
		local targetY = screenPosition.Y - 10

		if maxX < minX then
			minX = viewportSize.X / 2
			maxX = minX
		end

		if maxY < minY then
			minY = viewportSize.Y / 2
			maxY = minY
		end

		menuFrame.Position = UDim2.fromOffset(
			math.clamp(targetX, minX, maxX),
			math.clamp(targetY, minY, maxY)
		)
	else
		menuFrame.Visible = false
	end
end

RunService.RenderStepped:Connect(updateMenuPosition)
RunService.RenderStepped:Connect(updatePlacementPreview)
RunService.RenderStepped:Connect(movePreviewState.helperUi.update)
RunService.RenderStepped:Connect(maintainActiveGridFacing)

local function openFurnitureMenu(furnitureModel)
	selectedFurniture = furnitureModel
	local editing = isEditMode()
	local occupied = isFurnitureOccupiedLocally(furnitureModel)
	local defaultAction = getDefaultFurnitureAction(furnitureModel)
	local inPublicRoom = publicFurnitureRules.isCurrentRoomPublicSpace()
	local potentialOpenClose = furnitureSupportsOpenCloseBestEffort(furnitureModel)

	if inPublicRoom then
		potentialOpenClose = publicFurnitureRules.supportsOpenClose(furnitureModel)
	end

	local showSit = not editing
		and (
			(inPublicRoom and publicFurnitureRules.supportsSit(furnitureModel))
			or (not inPublicRoom and defaultAction ~= nil)
		)
	local showMove = false
	local showRotate = false
	local showPickUp = false
	local showOpenClose = false

	if not editing and not defaultAction and not potentialOpenClose then
		selectedFurniture = nil
		menuFrame.Visible = false
		clearFurnitureHighlight()
		return
	end

	titleLabel.Text = furnitureModel.Name
	subtitleLabel.Text = editing and "Edit actions" or "Choose an action"
	occupiedBadge.Visible = occupied == true
	updateOpenCloseButtonText(furnitureModel)
	permissionUi.resetForMenu(furnitureModel, showSit, showMove, showRotate, showPickUp, showOpenClose)
	permissionUi.applyLayout()

	if editing and occupied then
		subtitleLabel.Text = "Edit actions"
	elseif occupied then
		subtitleLabel.Text = "Currently occupied"
	end

	highlightFurniture(furnitureModel)

	local camera = workspace.CurrentCamera
	local worldPosition = furnitureInteraction.getTopPosition(furnitureModel)

	local screenPosition, onScreen = camera:WorldToScreenPoint(worldPosition)

	if onScreen then
		menuFrame.Visible = true
		updateMenuPosition()
		permissionUi.requestActionAccess()
	else
		menuFrame.Visible = false
	end
end

local function closeFurnitureMenu()
	selectedFurniture = nil
	movingFurniture = nil
	menuFrame.Visible = false
	permissionUi.expanded = false
	permissionUi.canManage = false

	destroyPlacementPreview()
	clearFurnitureHighlight()
end

function movePreviewState.cancelActive()
	if not movingFurniture then
		return
	end

	movingFurniture = nil
	movePreviewState.reset()
	destroyPlacementPreview()
	closeFurnitureMenu()
end

function movePreviewState.rotateActive()
	if not movingFurniture then
		return
	end

	movePreviewState.rotationOffsetY = (movePreviewState.rotationOffsetY + 90) % 360
	updatePlacementPreview()
end

function movePreviewState.confirmActive()
	if not movingFurniture then
		return
	end

	local placementPosition = getSnappedPlacementPosition()

	if placementPosition and placementIsValid then
		local furnitureModel = movingFurniture

		suppressFurnitureMenuUntil = os.clock() + 0.25
		furnitureActionRequest:FireServer("Move", furnitureModel, {
			TargetPosition = placementPosition,
			RotationOffsetY = movePreviewState.rotationOffsetY,
		})

		movingFurniture = nil
		movePreviewState.reset()
		destroyPlacementPreview()
		closeFurnitureMenu()
	else
		warn("Invalid furniture placement")
	end
end


local function isHotelMode()
	local controlMode = player:GetAttribute("ControlMode")

	if controlMode == nil then
		return true
	end

	return controlMode == "Hotel"
end

local function clickIsOnFurnitureMenu()
	if not menuFrame.Visible then
		return false
	end

	local guiObjects = playerGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y)

	for _, guiObject in ipairs(guiObjects) do
		if guiObject == menuFrame or guiObject:IsDescendantOf(menuFrame) then
			return true
		end
	end

	return false
end

local function guiObjectConsumesClick(guiObject)
	if not guiObject.Visible then
		return false
	end

	if guiObject:IsA("TextButton")
		or guiObject:IsA("ImageButton")
		or guiObject:IsA("TextBox") then

		return true
	end

	if guiObject.Active then
		return true
	end

	if guiObject:IsA("TextLabel") and guiObject.Text ~= "" and guiObject.TextTransparency < 1 then
		return true
	end

	if guiObject:IsA("ImageLabel") and guiObject.Image ~= "" and guiObject.ImageTransparency < 1 then
		return true
	end

	return guiObject.BackgroundTransparency < 1
end

local function clickIsOnPlayerGui()
	local guiObjects = playerGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y)

	for _, guiObject in ipairs(guiObjects) do
		if guiObject:IsDescendantOf(playerGui) and guiObjectConsumesClick(guiObject) then
			return true
		end
	end

	return false
end

local function clickTargetsWalkableSurface(target, floorRaycastResult)
	if not floorRaycastResult or not isWalkableSurfacePart(floorRaycastResult.Instance) then
		return false
	end

	if not getWalkableSurfaceFloor(floorRaycastResult.Instance) then
		return false
	end

	if not target then
		return true
	end

	return target == floorRaycastResult.Instance
		or isWalkableSurfacePart(target)
end

local function getCurrentlySeatedFurniture()
	local character = player.Character

	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not humanoid then
		return nil
	end

	local seatPart = humanoid.SeatPart

	if not seatPart then
		return nil
	end

	local furnitureFolder = getCurrentFurnitureFolder()

	if not furnitureFolder then
		return nil
	end

	local current = seatPart

	while current and current ~= workspace do
		if current:IsA("Model") and current:IsDescendantOf(furnitureFolder) then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function standUpIfSeated()
	local character = player.Character

	if not character then
		return true
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoid then
		return true
	end

	if humanoid.Sit or humanoid.SeatPart then
		local originalRootPosition = rootPart and rootPart.Position
		furnitureActionRequest:FireServer("Stand")

		-- Give the server time to unseat and move the player to SitPoint before pathing.
		local startTime = os.clock()
		local unseated = false

		while os.clock() - startTime < STAND_UP_TIMEOUT_SECONDS do
			if not humanoid.Parent then
				return false
			end

			if not humanoid.Sit and humanoid.SeatPart == nil then
				unseated = true
				break
			end

			task.wait(0.05)
		end

		if not unseated then
			return false
		end

		RunService.Heartbeat:Wait()
		task.wait(STAND_SETTLE_CHECK_SECONDS)

		local settledDeadline = os.clock() + 0.75
		local hasNearbyStartCell = false

		while os.clock() < settledDeadline do
			character = player.Character
			humanoid = character and character:FindFirstChildOfClass("Humanoid")
			rootPart = character and character:FindFirstChild("HumanoidRootPart")

			if not humanoid or not rootPart then
				return false
			end

			if humanoid.Sit or humanoid.SeatPart then
				return false
			end

			local context = getMovementGridContext()

			if not context then
				lastSeatedStandCompletedAt = os.clock()
				return true
			end

			local rootCell = worldToCell(rootPart.Position, context)

			if rootCell and isCellInsideRoom(rootCell, context) and not isCellBlocked(rootCell, context) then
				lastSeatedStandCompletedAt = os.clock()
				return true
			end

			hasNearbyStartCell = getNearestValidStartCellFromPosition(rootPart.Position, context) ~= nil

			if originalRootPosition
				and (rootPart.Position - originalRootPosition).Magnitude > 0.25
				and hasNearbyStartCell then

				lastSeatedStandCompletedAt = os.clock()
				return true
			end

			task.wait(0.05)
		end

		if hasNearbyStartCell
			and originalRootPosition
			and rootPart
			and (rootPart.Position - originalRootPosition).Magnitude > 0.25 then

			lastSeatedStandCompletedAt = os.clock()
			return true
		end

		return false
	end

	return true
end

function furnitureInteraction.requestSitAfterPathingToSitPoint(furnitureModel)
	if typeof(furnitureModel) ~= "Instance" or not furnitureModel:IsA("Model") then
		return false
	end

	local sitPoint = furnitureInteraction.getSitPoint(furnitureModel)
	local sitPointPosition = furnitureInteraction.getSitPointWorldPosition(sitPoint)

	if not standUpIfSeated() then
		return false
	end

	if sitPointPosition then
		local reachedSitPoint = moveCharacterTo(sitPointPosition, {
			SuppressBlockedWarning = true,
		})

		if not reachedSitPoint then
			warn("Cannot reach the seat.")
			return false
		end
	end

	furnitureActionRequest:FireServer("Sit", furnitureModel)
	return true
end

local function getGridPathToPosition(targetPosition)
	if typeof(targetPosition) ~= "Vector3" then
		return {
			Success = false,
			Path = {},
			Message = "Invalid target position.",
		}
	end

	if not isHotelMode() then
		return {
			Success = false,
			Path = {},
			Message = "Grid movement is unavailable.",
		}
	end

	if player:GetAttribute("CatalogPlacementActive") == true then
		return {
			Success = false,
			Path = {},
			Message = "Grid movement is unavailable during placement.",
		}
	end

	local requestedRoomName = player:GetAttribute("CurrentRoomName")

	if not roomMovementState.waitForCurrentRoomReady()
		or player:GetAttribute("CurrentRoomName") ~= requestedRoomName then

		return {
			Success = false,
			Path = {},
			Message = "Character is not ready.",
		}
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if not rootPart then
		return {
			Success = false,
			Path = {},
			Message = "Character is not ready.",
		}
	end

	local context, contextMessage = getMovementGridContext()

	if not context then
		return {
			Success = false,
			Path = {},
			Message = contextMessage or "Grid movement is unavailable.",
		}
	end

	local clampedDestination = clampToRoom(targetPosition, context)
	local startCell = worldToCell(rootPart.Position, context)
	local goalCell = worldToCell(clampedDestination, context)

	if not startCell or not goalCell then
		return {
			Success = false,
			Path = {},
			Message = "No grid path found.",
		}
	end

	if cellsAreSame(startCell, goalCell) then
		return {
			Success = true,
			Path = { cellToWorld(startCell, context) },
			Message = "Already at target.",
		}
	end

	local path, reachedGoal = findGridPath(startCell, goalCell, context)

	if not path or #path == 0 or not reachedGoal then
		return {
			Success = false,
			Path = {},
			Message = "The exit is blocked.",
		}
	end

	local worldPath = {}

	for _, cell in ipairs(path) do
		table.insert(worldPath, cellToWorld(cell, context))
	end

	return {
		Success = true,
		Path = worldPath,
		Message = "Path available.",
	}
end

local function moveToRoomExit()
	if not isHotelMode() then
		return {
			Success = false,
			Message = "Grid movement is unavailable.",
		}
	end

	if player:GetAttribute("CatalogPlacementActive") == true then
		return {
			Success = false,
			Message = "Grid movement is unavailable during placement.",
		}
	end

	if roomMovementState.caveTransitionActive then
		return {
			Success = false,
			Message = "Please wait.",
		}
	end

	local requestedRoomName = player:GetAttribute("CurrentRoomName")

	if not roomMovementState.waitForCurrentRoomReady({
		RequireDoorSpawn = true,
		TimeoutSeconds = 1.5,
	}) or player:GetAttribute("CurrentRoomName") ~= requestedRoomName then
		local roomModel = getCurrentRoomModel()

		if roomModel and not roomModel:FindFirstChild("DoorSpawn", true) then
			return {
				Success = false,
				Message = "This room is missing DoorSpawn.",
			}
		end

		return {
			Success = false,
			Message = "Character is not ready.",
		}
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local doorSpawn = getCurrentDoorSpawn()
	local doorSpawnPosition = getMarkerWorldPosition(doorSpawn)

	if not humanoid or not rootPart then
		return {
			Success = false,
			Message = "Character is not ready.",
		}
	end

	if not doorSpawnPosition then
		return {
			Success = false,
			Message = "This room is missing DoorSpawn.",
		}
	end

	closeFurnitureMenu()

	if not standUpIfSeated() then
		return {
			Success = false,
			Message = "Could not leave while seated.",
		}
	end

	character = player.Character
	humanoid = character and character:FindFirstChildOfClass("Humanoid")
	rootPart = character and character:FindFirstChild("HumanoidRootPart")
	doorSpawn = getCurrentDoorSpawn()
	doorSpawnPosition = getMarkerWorldPosition(doorSpawn)

	if not humanoid or not rootPart then
		return {
			Success = false,
			Message = "Character is not ready.",
		}
	end

	if not doorSpawnPosition then
		return {
			Success = false,
			Message = "This room is missing DoorSpawn.",
		}
	end

	if roomMovementState.isPlayerAtDoorSpawn(rootPart.Position) then
		return {
			Success = true,
			Message = "Reached exit.",
		}
	end

	roomMovementState.setCaveTransitionActive(true)

	local entryWalkTarget = getCurrentEntryWalkTarget()
	local entryPosition = getMarkerWorldPosition(entryWalkTarget)

	if not entryPosition then
		roomMovementState.setCaveTransitionActive(false)
		return {
			Success = false,
			Message = "This room is missing EntryWalkTarget.",
		}
	end

	if not rootPartIsNearPosition(rootPart, entryPosition, ENTRY_BRIDGE_REACHED_DISTANCE) then

		local pathCheck = getGridPathToPosition(entryPosition)

		if typeof(pathCheck) ~= "table" or pathCheck.Success ~= true then
			roomMovementState.setCaveTransitionActive(false)
			return {
				Success = false,
				Message = "The exit is blocked.",
			}
		end

		moveCharacterTo(entryPosition, {
			AllowDuringCaveTransition = true,
			SuppressBlockedWarning = true,
		})

		if not waitForRootNearPosition(
			rootPart,
			entryPosition,
			ENTRY_BRIDGE_REACHED_DISTANCE,
			EXIT_ENTRY_MOVE_TIMEOUT_SECONDS,
			nil,
			function()
				return roomMovementState.characterReachedMarkerPosition(entryWalkTarget, ENTRY_BRIDGE_REACHED_DISTANCE)
			end
		) then

			roomMovementState.setCaveTransitionActive(false)
			return {
				Success = false,
				Message = "Could not reach the exit.",
			}
		end
	end

	currentMoveId += 1
	local exitMoveId = currentMoveId

	local reachedDoorSpawn = roomMovementState.moveHumanoidToMarker(doorSpawn, {
		Distance = EXIT_TARGET_REACHED_DISTANCE,
		TimeoutSeconds = EXIT_DIRECT_MOVE_TIMEOUT_SECONDS,
		MoveId = exitMoveId,
	})

	if not reachedDoorSpawn then
		roomMovementState.setCaveTransitionActive(false)
		return {
			Success = false,
			Message = "Could not reach the exit.",
		}
	end

	roomMovementState.setCaveTransitionActive(false)

	return {
		Success = true,
		Message = "Reached exit.",
	}
end

canGridMoveToPosition.OnInvoke = function(targetPosition)
	return getGridPathToPosition(targetPosition)
end

ensureStandBeforeMovement.OnInvoke = function()
	return standUpIfSeated()
end

requestMoveToRoomExit.OnInvoke = function()
	return moveToRoomExit()
end

requestGridMoveToPosition.Event:Connect(function(targetPosition)
	if typeof(targetPosition) ~= "Vector3" then
		return
	end

	if not isHotelMode() or player:GetAttribute("CatalogPlacementActive") == true then
		return
	end

	if roomMovementState.caveTransitionActive then
		return
	end

	if not standUpIfSeated() then
		return
	end

	closeFurnitureMenu()
	moveCharacterTo(targetPosition)
end)

function furnitureInteraction.handleClickInPlayMode(furnitureModel)
	if roomMovementState.caveTransitionActive then
		return
	end

	if publicFurnitureRules.isCurrentRoomPublicSpace() then
		if publicFurnitureRules.supportsSit(furnitureModel)
			or publicFurnitureRules.supportsOpenClose(furnitureModel) then

			openFurnitureMenu(furnitureModel)
		else
			closeFurnitureMenu()
		end

		return
	end

	if furnitureSupportsOpenCloseBestEffort(furnitureModel) then
		openFurnitureMenu(furnitureModel)
		return
	end

	local actionName = getDefaultFurnitureAction(furnitureModel)

	if not actionName then
		closeFurnitureMenu()
		return
	end

	local now = os.clock()

	if now - lastPlayFurnitureActionAt < PLAY_FURNITURE_ACTION_COOLDOWN_SECONDS then
		return
	end

	lastPlayFurnitureActionAt = now

	-- Important:
	-- If the player clicks the same chair they are already sitting on,
	-- do not send Stand and do not send another Sit.
	if actionName == "Sit" then
		local seatedFurniture = getCurrentlySeatedFurniture()

		if seatedFurniture == furnitureModel then
			closeFurnitureMenu()
			return
		end

		furnitureInteraction.requestSitAfterPathingToSitPoint(furnitureModel)
		closeFurnitureMenu()
		return
	end

	if actionRequiresStanding(actionName) then
		if not standUpIfSeated() then
			return
		end
	end

	furnitureActionRequest:FireServer(actionName, furnitureModel)
	closeFurnitureMenu()
end

furnitureMenuRequest.OnClientEvent:Connect(function(furnitureModel)
	if movingFurniture then
		return
	end

	if roomMovementState.caveTransitionActive then
		return
	end

	if os.clock() < suppressFurnitureMenuUntil then
		return
	end

	if not isHotelMode() then
		return
	end

	if typeof(furnitureModel) ~= "Instance" then
		return
	end

	if not furnitureModel:IsA("Model") then
		return
	end

	local currentFurnitureFolder = getCurrentFurnitureFolder()

	if not currentFurnitureFolder then
		return
	end

	if not furnitureModel:IsDescendantOf(currentFurnitureFolder) then
		return
	end

	-- Browsing furniture should not force the player to stand.
	if isEditMode() then
		openFurnitureMenu(furnitureModel)
	else
		furnitureInteraction.handleClickInPlayMode(furnitureModel)
	end
end)

mouse.Button1Down:Connect(function()
	if not isHotelMode() then
		return
	end

	if clickIsOnFurnitureMenu and clickIsOnFurnitureMenu() then
		return
	end

	if clickIsOnPlayerGui() then
		return
	end
	
	if player:GetAttribute("CatalogPlacementActive") == true then
		return
	end

	if roomMovementState.caveTransitionActive then
		return
	end

	local target = mouse.Target
	local floorRaycastResult = getMouseFloorRaycastResult()
	local walkableSurfaceClicked = clickTargetsWalkableSurface(target, floorRaycastResult)

	-- IMPORTANT:
	-- If we are moving furniture, handle placement before checking furniture clicks.
	-- This prevents the original furniture from blocking its own placement.
	if movingFurniture then
		movePreviewState.confirmActive()
		return
	end

	-- Furniture clicks are handled by FurnitureClickServer through ClickDetectors.
	-- Do not move or close the menu here if the clicked target is furniture.
	local furnitureModel = furnitureInteraction.getModelFromTarget(target)

	if furnitureModel then
		if getDefaultFurnitureAction(furnitureModel) or not walkableSurfaceClicked then
			return
		end
	end

	if walkableSurfaceClicked then
		if not standUpIfSeated() then
			return
		end

		closeFurnitureMenu()

		moveCharacterTo(floorRaycastResult.Position)
		return
	end

	closeFurnitureMenu()
end)

game:GetService("UserInputService").InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not movingFurniture then
		return
	end

	local userInputService = game:GetService("UserInputService")

	if userInputService:GetFocusedTextBox() then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	if input.KeyCode == Enum.KeyCode.R then
		movePreviewState.rotateActive()
	elseif input.KeyCode == Enum.KeyCode.C then
		movePreviewState.cancelActive()
	end
end)

player:GetAttributeChangedSignal("RoomMode"):Connect(function()
	if movingFurniture and not isEditMode() then
		movePreviewState.cancelActive()
	end
end)

player:GetAttributeChangedSignal("CurrentRoomName"):Connect(function()
	if activeGridFacingMoveId then
		finishGridFacingControl(activeGridFacingMoveId)
	end

	if activeGridFacingHumanoid then
		if activeGridFacingPreviousAutoRotate ~= nil then
			activeGridFacingHumanoid.AutoRotate = activeGridFacingPreviousAutoRotate
		end

		if activeGridFacingPreviousWalkSpeed ~= nil then
			activeGridFacingHumanoid.WalkSpeed = activeGridFacingPreviousWalkSpeed
		end
	end

	activeGridFacingMoveId = nil
	activeGridFacingHumanoid = nil
	activeGridFacingPreviousAutoRotate = nil
	activeGridFacingPreviousWalkSpeed = nil
	clearActiveGridFacingSegment()

	currentMoveId += 1
	lastMoveTime = 0
	lastSeatedStandCompletedAt = 0
	entranceBridgeDiagnosticsLogged = {}
	roomMovementState.setCaveTransitionActive(false)
	roomMovementState.lastEntranceReachWarningAt = 0
	mouse.TargetFilter = nil

	if movingFurniture then
		movePreviewState.cancelActive()
	else
		closeFurnitureMenu()
	end
end)

permissionUi.accessButton.MouseButton1Click:Connect(function()
	if not selectedFurniture or not permissionUi.canManage then
		return
	end

	permissionUi.expanded = not permissionUi.expanded
	permissionUi.applyLayout()

	if permissionUi.expanded then
		permissionUi.requestCurrent()
	end
end)

permissionUi.addButton.MouseButton1Click:Connect(function()
	if not selectedFurniture or not permissionUi.canManage then
		return
	end

	local targetUserInput = (permissionUi.input.Text or ""):match("^%s*(.-)%s*$") or ""

	if targetUserInput == "" then
		permissionUi.setStatus("Invalid user.", true)
		return
	end

	if tonumber(targetUserInput) == player.UserId then
		permissionUi.setStatus("You already own this furniture.", true)
		return
	end

	permissionUi.setStatus("Updating...")
	remoteEvents:WaitForChild("RoomPermissionRequest"):FireServer("SetFurniturePermission", {
		Furniture = selectedFurniture,
		ActionName = "OpenClose",
		TargetUserInput = targetUserInput,
		IsAllowed = true,
	})
end)

sitButton.MouseButton1Click:Connect(function()
	if not selectedFurniture then
		warn("Client: No furniture selected")
		return
	end

	furnitureInteraction.requestSitAfterPathingToSitPoint(selectedFurniture)
	closeFurnitureMenu()
end)

closeButton.MouseButton1Click:Connect(function()
	closeFurnitureMenu()
end)

moveButton.MouseButton1Click:Connect(function()
	if not selectedFurniture then
		return
	end

	movingFurniture = selectedFurniture
	movePreviewState.rotationOffsetY = 0

	-- Create preview first because createPlacementPreview() calls destroyPlacementPreview().
	createPlacementPreview(movingFurniture)

	-- Then fade and ignore the original furniture.
	dimOriginalFurniture(movingFurniture)
	setMovingFurnitureIgnored(true)

	menuFrame.Visible = false
	clearFurnitureHighlight()
	movePreviewState.showHint()
end)

rotateButton.MouseButton1Click:Connect(function()
	if not selectedFurniture then
		return
	end

	furnitureActionRequest:FireServer("Rotate", selectedFurniture)
end)

openCloseButton.MouseButton1Click:Connect(function()
	if not selectedFurniture then
		return
	end

	furnitureActionRequest:FireServer("OpenClose", selectedFurniture)
end)

pickUpButton.MouseButton1Click:Connect(function()
	if not selectedFurniture then
		return
	end

	local templateId, resolvedThroughFallback = resolveFurniturePickupTemplateId(selectedFurniture)

	if not templateId then
		warn("Cannot pick up starter furniture.")
		closeFurnitureMenu()
		return
	end

	local optimisticPayload = {
		TemplateId = templateId,
		DeltaTotal = 1,
		Optimistic = true,
		Reason = "PickUpPending",
	}

	if isFurniturePickupOptimisticallyUntradable(selectedFurniture, resolvedThroughFallback) then
		optimisticPayload.DeltaUntradable = 1
	end

	if isFurniturePickupOptimisticallyUnsellable(selectedFurniture, resolvedThroughFallback) then
		optimisticPayload.DeltaUnsellable = 1
	end

	inventoryLocalDelta:Fire(optimisticPayload)
	furnitureActionRequest:FireServer("PickUp", selectedFurniture)
	closeFurnitureMenu()
end)

remoteEvents:WaitForChild("RoomPermissionResult").OnClientEvent:Connect(function(response)
	permissionUi.handleResult(response)
end)

furnitureActionResult.OnClientEvent:Connect(function(response)
	if typeof(response) ~= "table" then
		return
	end

	if response.Kind == "OpenClose" then
		local message = tostring(response.Message or "")

		if response.Success == true then
			if selectedFurniture and menuFrame.Visible then
				updateOpenCloseButtonText(selectedFurniture, response.IsOpen == true)
			end
		elseif message ~= "" then
			warn(message)
		end

		return
	end

	if response.Kind ~= "PickUp" then
		return
	end

	local message = tostring(response.Message or "")

	if response.Success == true then
		print(message)
		closeFurnitureMenu()
		fireInventoryLocalDeltaFromPickUpResult(response)
		inventoryRefreshRequested:Fire()
	else
		warn(message)
		inventoryRefreshRequested:Fire({
			Reason = "PickUpFailed",
			Force = true,
		})
	end
end)
