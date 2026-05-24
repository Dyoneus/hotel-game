-- StarterGui/InventoryGui/InventoryClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local inventoryRequest = remoteEvents:WaitForChild("InventoryRequest")
local inventoryResult = remoteEvents:WaitForChild("InventoryResult")

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 155

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

local requestInFlight = false
local refreshQueued = false
local queuedRefreshForce = false
local lastInventoryRequestAt = -math.huge
local requestSerial = 0
local hasLoadedInventory = false
local latestInventory = {}
local latestInventoryDetails = {}

local LOCAL_REQUEST_COOLDOWN_SECONDS = 0.6
local REQUEST_TIMEOUT_SECONDS = 6

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

local startInventoryPlacement = getOrCreateClientEvent("StartInventoryPlacement")
local inventoryRefreshRequested = getOrCreateClientEvent("InventoryRefreshRequested")
local inventoryLocalDelta = getOrCreateClientEvent("InventoryLocalDelta")
local majorMenuOpened = getOrCreateClientEvent("MajorMenuOpened")
local closeMajorMenus = getOrCreateClientEvent("CloseMajorMenus")
local majorMenuStateChanged = getOrCreateClientEvent("MajorMenuStateChanged")

local MENU_NAME = "Inventory"
local anyMajorMenuOpen = false
local openMajorMenuName = nil

local openButton = Instance.new("TextButton")
openButton.Name = "OpenInventoryButton"
openButton.AnchorPoint = Vector2.new(1, 1)
openButton.Position = UDim2.new(1, -20, 1, -128)
openButton.Size = UDim2.fromOffset(150, 44)
openButton.BackgroundColor3 = Color3.fromRGB(80, 120, 90)
openButton.BorderSizePixel = 0
openButton.Text = "Inventory"
openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
openButton.TextScaled = true
openButton.Font = Enum.Font.GothamBold
openButton.Visible = false
openButton.Parent = gui

createCorner(openButton, 10)
createStroke(openButton, Color3.fromRGB(255, 255, 255), 1, 0.25)

local panel = Instance.new("Frame")
panel.Name = "InventoryPanel"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -24, 0.5, 0)
panel.Size = UDim2.fromOffset(360, 420)
panel.BackgroundColor3 = Color3.fromRGB(245, 245, 238)
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

createCorner(panel, 16)
createStroke(panel, Color3.fromRGB(255, 255, 255), 2, 0.1)

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Position = UDim2.fromOffset(18, 14)
titleLabel.Size = UDim2.new(1, -70, 0, 36)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Inventory"
titleLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
titleLabel.TextScaled = true
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -18, 0, 18)
closeButton.Size = UDim2.fromOffset(34, 34)
closeButton.BackgroundColor3 = Color3.fromRGB(160, 70, 70)
closeButton.BorderSizePixel = 0
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.TextScaled = true
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = panel

createCorner(closeButton, 8)

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Position = UDim2.fromOffset(18, 56)
statusLabel.Size = UDim2.new(1, -36, 0, 34)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = ""
statusLabel.TextColor3 = Color3.fromRGB(90, 90, 90)
statusLabel.TextWrapped = true
statusLabel.TextScaled = true
statusLabel.Font = Enum.Font.Gotham
statusLabel.Parent = panel

local listFrame = Instance.new("ScrollingFrame")
listFrame.Name = "InventoryList"
listFrame.Position = UDim2.fromOffset(18, 104)
listFrame.Size = UDim2.new(1, -36, 1, -164)
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

local refreshButton = Instance.new("TextButton")
refreshButton.Name = "RefreshButton"
refreshButton.AnchorPoint = Vector2.new(0.5, 1)
refreshButton.Position = UDim2.new(0.5, 0, 1, -22)
refreshButton.Size = UDim2.fromOffset(180, 38)
refreshButton.BackgroundColor3 = Color3.fromRGB(70, 120, 190)
refreshButton.BorderSizePixel = 0
refreshButton.Text = "Refresh"
refreshButton.TextColor3 = Color3.fromRGB(255, 255, 255)
refreshButton.TextScaled = true
refreshButton.Font = Enum.Font.GothamBold
refreshButton.Parent = panel

createCorner(refreshButton, 9)

local function shouldShowInventoryButton()
	local currentRoomName = player:GetAttribute("CurrentRoomName")

	return player:GetAttribute("OnboardingStep") == "Complete"
		and (player:GetAttribute("ControlMode") or "Hotel") == "Hotel"
		and typeof(currentRoomName) == "string"
		and currentRoomName ~= ""
end

local function updateOpenButton()
	openButton.Visible = (not panel.Visible)
		and not anyMajorMenuOpen
		and shouldShowInventoryButton()
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

local function setStatus(text, success)
	statusLabel.Text = tostring(text or "")

	if success == true then
		statusLabel.TextColor3 = Color3.fromRGB(50, 110, 60)
	elseif success == false then
		statusLabel.TextColor3 = Color3.fromRGB(150, 60, 60)
	else
		statusLabel.TextColor3 = Color3.fromRGB(90, 90, 90)
	end
end

local function isNonNegativeCount(value)
	return typeof(value) == "number"
		and value == value
		and value >= 0
		and value < math.huge
end

local function isFiniteNumber(value)
	return typeof(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function clearRows()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local function createEmptyState()
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyInventoryLabel"
	emptyLabel.Size = UDim2.new(1, -4, 0, 52)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Text = "Inventory is empty."
	emptyLabel.TextColor3 = Color3.fromRGB(95, 95, 95)
	emptyLabel.TextScaled = true
	emptyLabel.TextWrapped = true
	emptyLabel.Font = Enum.Font.Gotham
	emptyLabel.Parent = listFrame
end

local function createInventoryRow(templateId, count, details, layoutOrder)
	local untradableCount = 0

	if typeof(details) == "table" and typeof(details.Untradable) == "number" then
		untradableCount = details.Untradable
	end

	local row = Instance.new("TextButton")
	row.Name = tostring(templateId)
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.new(1, -4, 0, 64)
	row.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
	row.BorderSizePixel = 0
	row.Text = ""
	row.AutoButtonColor = true
	row.Parent = listFrame

	createCorner(row, 10)
	createStroke(row, Color3.fromRGB(220, 220, 220), 1, 0)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Position = UDim2.fromOffset(12, 8)
	nameLabel.Size = UDim2.new(1, -100, 0, 26)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = tostring(templateId)
	nameLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
	nameLabel.TextSize = 18
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = row

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "CountLabel"
	countLabel.Position = UDim2.new(1, -82, 0, 8)
	countLabel.Size = UDim2.fromOffset(70, 26)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "x" .. tostring(count)
	countLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
	countLabel.TextSize = 18
	countLabel.TextXAlignment = Enum.TextXAlignment.Right
	countLabel.Font = Enum.Font.GothamBold
	countLabel.Parent = row

	local noteLabel = Instance.new("TextLabel")
	noteLabel.Name = "UntradableLabel"
	noteLabel.Position = UDim2.fromOffset(12, 36)
	noteLabel.Size = UDim2.new(1, -24, 0, 18)
	noteLabel.BackgroundTransparency = 1
	noteLabel.Text = untradableCount > 0 and "Untradable: " .. tostring(untradableCount) or ""
	noteLabel.TextColor3 = Color3.fromRGB(105, 105, 105)
	noteLabel.TextSize = 13
	noteLabel.TextXAlignment = Enum.TextXAlignment.Left
	noteLabel.Font = Enum.Font.Gotham
	noteLabel.Parent = row

	row.MouseButton1Click:Connect(function()
		if count <= 0 then
			return
		end

		local currentRoomName = player:GetAttribute("CurrentRoomName")

		if (player:GetAttribute("ControlMode") or "Hotel") ~= "Hotel"
			or typeof(currentRoomName) ~= "string"
			or currentRoomName == ""
			or player:GetAttribute("RoomMode") ~= "Edit" then

			setStatus("Enter Edit Mode to place furniture.", false)
			return
		end

		startInventoryPlacement:Fire({
			Id = templateId,
			TemplateName = templateId,
			DisplayName = templateId,
			Source = "Inventory",
		})
	end)
end

local function renderInventory(inventory, inventoryDetails)
	latestInventory = inventory or {}
	latestInventoryDetails = inventoryDetails or {}
	clearRows()

	local entries = {}

	if typeof(latestInventory) == "table" then
		for templateId, count in pairs(latestInventory) do
			if typeof(templateId) == "string" and typeof(count) == "number" and count > 0 then
				table.insert(entries, {
					TemplateId = templateId,
					Count = count,
					Details = latestInventoryDetails[templateId],
				})
			end
		end
	end

	table.sort(entries, function(a, b)
		return a.TemplateId < b.TemplateId
	end)

	if #entries == 0 then
		createEmptyState()
	else
		for index, entry in ipairs(entries) do
			createInventoryRow(entry.TemplateId, entry.Count, entry.Details, index)
		end
	end

	task.defer(function()
		listFrame.CanvasSize = UDim2.fromOffset(
			0,
			listLayout.AbsoluteContentSize.Y + 20
		)
	end)
end

local function applyInventoryLocalDelta(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local templateId = payload.TemplateId

	if typeof(templateId) ~= "string" or templateId == "" or not templateId:match("%S") then
		return
	end

	if typeof(latestInventory) ~= "table" then
		latestInventory = {}
	end

	if typeof(latestInventoryDetails) ~= "table" then
		latestInventoryDetails = {}
	end

	local currentTotal = 0

	if isNonNegativeCount(latestInventory[templateId]) then
		currentTotal = math.floor(latestInventory[templateId])
	end

	local existingDetails = latestInventoryDetails[templateId]
	local untradable = 0

	if typeof(existingDetails) == "table" and isNonNegativeCount(existingDetails.Untradable) then
		untradable = math.min(math.floor(existingDetails.Untradable), currentTotal)
	end

	local total = nil

	if isFiniteNumber(payload.DeltaTotal) then
		local deltaTotal = math.floor(payload.DeltaTotal)
		local newTotal = math.max(currentTotal + deltaTotal, 0)

		if deltaTotal < 0 then
			local removeCount = math.min(-deltaTotal, currentTotal)

			if payload.ConsumeUntradableFirst == true then
				local removeUntradable = math.min(untradable, removeCount)
				untradable -= removeUntradable
			end
		end

		if isFiniteNumber(payload.DeltaUntradable) then
			untradable += math.floor(payload.DeltaUntradable)
		end

		total = newTotal
	elseif isNonNegativeCount(payload.Total) then
		total = math.floor(payload.Total)

		if isNonNegativeCount(payload.Untradable) then
			untradable = math.floor(payload.Untradable)
		elseif isNonNegativeCount(payload.Tradable) then
			untradable = total - math.floor(payload.Tradable)
		end
	else
		return
	end

	total = math.max(total, 0)
	untradable = math.clamp(untradable, 0, total)
	local tradable = total - untradable

	if total > 0 then
		latestInventory[templateId] = total
		latestInventoryDetails[templateId] = {
			Total = total,
			Tradable = tradable,
			Untradable = untradable,
		}
	else
		latestInventory[templateId] = nil
		latestInventoryDetails[templateId] = nil
	end

	hasLoadedInventory = true

	if panel.Visible then
		renderInventory(latestInventory, latestInventoryDetails)
	end
end

local requestInventoryRefresh = nil

local function setRequestInFlight(isInFlight)
	requestInFlight = isInFlight
	refreshButton.Active = not isInFlight
	refreshButton.AutoButtonColor = not isInFlight

	if isInFlight then
		refreshButton.Text = "Loading..."
		refreshButton.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
	else
		refreshButton.Text = "Refresh"
		refreshButton.BackgroundColor3 = Color3.fromRGB(70, 120, 190)
	end
end

local function queueInventoryRefresh(reason, delaySeconds, force)
	if refreshQueued then
		queuedRefreshForce = queuedRefreshForce or force == true
		return
	end

	refreshQueued = true
	queuedRefreshForce = force == true

	task.delay(delaySeconds, function()
		refreshQueued = false
		local shouldForce = queuedRefreshForce
		queuedRefreshForce = false

		if requestInventoryRefresh then
			requestInventoryRefresh(reason or "queued", shouldForce)
		end
	end)
end

requestInventoryRefresh = function(reason, force)
	if requestInFlight then
		queueInventoryRefresh(reason, force == true and 0.05 or LOCAL_REQUEST_COOLDOWN_SECONDS, force)
		return
	end

	local now = os.clock()
	local elapsed = now - lastInventoryRequestAt

	if force ~= true and elapsed < LOCAL_REQUEST_COOLDOWN_SECONDS then
		queueInventoryRefresh(
			reason,
			LOCAL_REQUEST_COOLDOWN_SECONDS - elapsed + 0.05,
			force
		)
		return
	end

	setRequestInFlight(true)
	lastInventoryRequestAt = now
	requestSerial += 1

	local thisRequestSerial = requestSerial

	if panel.Visible and (reason == "manual" or not hasLoadedInventory) then
		setStatus("Loading inventory.", nil)
	end

	inventoryRequest:FireServer("GetInventory")

	task.delay(REQUEST_TIMEOUT_SECONDS, function()
		if requestInFlight and requestSerial == thisRequestSerial then
			setRequestInFlight(false)
			setStatus("Inventory request timed out.", false)
		end
	end)
end

local function setPanelVisible(isVisible)
	local wasVisible = panel.Visible

	if isVisible then
		publishMajorMenuState(true)
		majorMenuOpened:Fire(MENU_NAME)
	end

	panel.Visible = isVisible
	updateOpenButton()

	if isVisible then
		if hasLoadedInventory then
			renderInventory(latestInventory, latestInventoryDetails)
		end

		requestInventoryRefresh("open")
	elseif wasVisible or openMajorMenuName == MENU_NAME then
		publishMajorMenuState(false)
	end
end

openButton.MouseButton1Click:Connect(function()
	setPanelVisible(true)
end)

closeButton.MouseButton1Click:Connect(function()
	setPanelVisible(false)
end)

refreshButton.MouseButton1Click:Connect(function()
	requestInventoryRefresh("manual")
end)

inventoryRefreshRequested.Event:Connect(function(options)
	local reason = "event"
	local force = false

	if typeof(options) == "table" then
		if typeof(options.Reason) == "string" and options.Reason ~= "" then
			reason = options.Reason
		end

		force = options.Force == true or options.Priority == true
	elseif typeof(options) == "string" and options ~= "" then
		reason = options
	end

	requestInventoryRefresh(reason, force)
end)

inventoryLocalDelta.Event:Connect(function(payload)
	applyInventoryLocalDelta(payload)
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

inventoryResult.OnClientEvent:Connect(function(response)
	if typeof(response) ~= "table" then
		return
	end

	setRequestInFlight(false)

	local success = response.Success == true
	local message = tostring(response.Message or "")

	if success and typeof(response.Inventory) == "table" then
		hasLoadedInventory = true
		renderInventory(response.Inventory, response.InventoryDetails)
		setStatus(message ~= "" and message or "Inventory loaded.", true)
	elseif message == "Slow down before requesting inventory." then
		warn(message)
		queueInventoryRefresh("serverCooldown", LOCAL_REQUEST_COOLDOWN_SECONDS)
	else
		setStatus(message ~= "" and message or "Could not load inventory.", false)
	end
end)

local function handleVisibilityChanged()
	if panel.Visible and not shouldShowInventoryButton() then
		setPanelVisible(false)
	else
		updateOpenButton()
	end
end

player:GetAttributeChangedSignal("OnboardingStep"):Connect(handleVisibilityChanged)
player:GetAttributeChangedSignal("ControlMode"):Connect(handleVisibilityChanged)
player:GetAttributeChangedSignal("CurrentRoomName"):Connect(handleVisibilityChanged)

renderInventory({})
task.defer(updateOpenButton)
