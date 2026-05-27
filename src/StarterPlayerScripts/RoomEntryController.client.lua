-- Habbo-style room entrance foundation.
-- Server placement stays authoritative at DoorSpawn.
-- Auto-walk from DoorSpawn to EntryWalkTarget is intentionally disabled.
-- Players stay in the doorway/cave on room join.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local activeRooms = workspace:WaitForChild("ActiveRooms")
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local leaveRoomRequest = remoteEvents:WaitForChild("LeaveRoomRequest")
local leaveRoomResult = remoteEvents:WaitForChild("LeaveRoomResult")
local EXIT_ARRIVAL_DISTANCE = 2.5
local LEAVE_WALK_TIMEOUT_SECONDS = 8
local FADE_OUT_SECONDS = 0.28
local EXIT_REACHED_DELAY_SECONDS = 0.35

local lastObservedRoomName = nil
local anyMajorMenuOpen = false
local leaveInProgress = false
local exitReadyLoggedByRoom = {}
local missingExitWarnedByRoom = {}
local pathPreviewFolder = nil

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

	local event = Instance.new("BindableEvent")
	event.Name = name
	event.Parent = clientEvents

	return event
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

local majorMenuStateChanged = getOrCreateClientEvent("MajorMenuStateChanged")
local roomTransitionRequest = getOrCreateClientEvent("RoomTransitionRequest")
local requestMoveToRoomExit = getOrCreateClientFunction("RequestMoveToRoomExit")
local ensureStandBeforeMovement = getOrCreateClientFunction("EnsureStandBeforeMovement")

local gui = Instance.new("ScreenGui")
gui.Name = "RoomLeavePromptGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 900
gui.Enabled = true
gui.Parent = playerGui

local shade = Instance.new("Frame")
shade.Name = "Shade"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shade.BackgroundTransparency = 0.45
shade.BorderSizePixel = 0
shade.Visible = false
shade.Parent = gui

local prompt = Instance.new("Frame")
prompt.Name = "LeavePrompt"
prompt.AnchorPoint = Vector2.new(0.5, 0.5)
prompt.Position = UDim2.fromScale(0.5, 0.5)
prompt.Size = UDim2.fromOffset(360, 188)
prompt.BackgroundColor3 = Color3.fromRGB(246, 248, 240)
prompt.BorderSizePixel = 0
prompt.Visible = false
prompt.Parent = gui

local promptCorner = Instance.new("UICorner")
promptCorner.CornerRadius = UDim.new(0, 10)
promptCorner.Parent = prompt

local promptStroke = Instance.new("UIStroke")
promptStroke.Color = Color3.fromRGB(70, 76, 68)
promptStroke.Thickness = 1
promptStroke.Transparency = 0.25
promptStroke.Parent = prompt

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Position = UDim2.fromOffset(20, 16)
titleLabel.Size = UDim2.new(1, -40, 0, 30)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Leave Room?"
titleLabel.TextColor3 = Color3.fromRGB(34, 39, 36)
titleLabel.TextSize = 22
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Parent = prompt

local messageLabel = Instance.new("TextLabel")
messageLabel.Name = "Message"
messageLabel.Position = UDim2.fromOffset(28, 58)
messageLabel.Size = UDim2.new(1, -56, 0, 46)
messageLabel.BackgroundTransparency = 1
messageLabel.Text = "Are you sure you want to leave the room?"
messageLabel.TextColor3 = Color3.fromRGB(66, 72, 67)
messageLabel.TextSize = 15
messageLabel.TextWrapped = true
messageLabel.Font = Enum.Font.GothamMedium
messageLabel.Parent = prompt

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.Position = UDim2.fromOffset(24, 108)
statusLabel.Size = UDim2.new(1, -48, 0, 20)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = ""
statusLabel.TextColor3 = Color3.fromRGB(177, 70, 58)
statusLabel.TextSize = 13
statusLabel.Font = Enum.Font.GothamMedium
statusLabel.Parent = prompt

local function createPromptButton(name, text, position, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = UDim2.fromOffset(132, 36)
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextSize = 16
	button.Font = Enum.Font.GothamBold
	button.Parent = prompt

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	return button
end

local noButton = createPromptButton("NoButton", "No", UDim2.fromOffset(48, 138), Color3.fromRGB(89, 98, 96))
local yesButton = createPromptButton("YesButton", "Yes", UDim2.new(1, -180, 0, 138), Color3.fromRGB(58, 130, 86))

local function isHotelMode()
	local controlMode = player:GetAttribute("ControlMode")

	if controlMode == nil then
		return true
	end

	return controlMode == "Hotel"
end

local function findRoomMarker(roomModel, markerName)
	local marker = roomModel:FindFirstChild(markerName, true)

	if marker and (marker:IsA("BasePart") or marker:IsA("Attachment")) then
		return marker
	end

	return nil
end

local function getMarkerPosition(marker)
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

local function getCurrentRoomModel()
	local roomName = player:GetAttribute("CurrentRoomName")

	if typeof(roomName) ~= "string" or roomName == "" then
		return nil
	end

	return activeRooms:FindFirstChild(roomName)
end

local function getCharacterParts()
	local character = player.Character

	if not character then
		return nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then
		return nil, nil
	end

	return humanoid, rootPart
end

local function standUpIfSeatedForExit()
	local ok, result = pcall(function()
		return ensureStandBeforeMovement:Invoke()
	end)

	if ok and result == true then
		return true
	end

	local humanoid = getCharacterParts()

	if not humanoid then
		return false
	end

	return not humanoid.Sit and humanoid.SeatPart == nil
end

local function isRoomExitMarker(instance)
	return typeof(instance) == "Instance"
		and (
			instance.Name == "RoomExitZone"
			or instance:GetAttribute("IsRoomExit") == true
		)
end

local function hasRoomExitMarkerInAncestry(instance, roomModel)
	local current = instance

	while current and current ~= workspace do
		if isRoomExitMarker(current) then
			return roomModel == nil or current:IsDescendantOf(roomModel) or current == roomModel
		end

		if current == roomModel then
			break
		end

		current = current.Parent
	end

	return false
end

local function isRoomExitInstance(instance)
	return hasRoomExitMarkerInAncestry(instance, getCurrentRoomModel())
end

local function getRoomExitParts(roomModel)
	local parts = {}

	if not roomModel then
		return parts
	end

	for _, descendant in ipairs(roomModel:GetDescendants()) do
		if descendant:IsA("BasePart") and hasRoomExitMarkerInAncestry(descendant, roomModel) then
			table.insert(parts, descendant)
		end
	end

	return parts
end

local function getMouseExitRaycastResult()
	local roomModel = getCurrentRoomModel()
	local exitParts = getRoomExitParts(roomModel)

	if #exitParts == 0 then
		return nil
	end

	local camera = workspace.CurrentCamera

	if not camera then
		return nil
	end

	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = exitParts

	return workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)
end

local function clickIsOnPlayerGui()
	for _, guiObject in ipairs(playerGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y)) do
		if guiObject.Visible
			and guiObject:IsDescendantOf(playerGui)
			and (
				guiObject:IsA("TextButton")
				or guiObject:IsA("ImageButton")
				or guiObject:IsA("TextBox")
				or guiObject.Active
				or guiObject.BackgroundTransparency < 1
			) then

			return true
		end
	end

	return false
end

local function showPrompt(statusText)
	statusLabel.Text = statusText or ""
	shade.Visible = true
	prompt.Visible = true
end

local function closePrompt()
	shade.Visible = false
	prompt.Visible = false
	statusLabel.Text = ""
end

local function clearPathPreview()
	if pathPreviewFolder then
		pathPreviewFolder:Destroy()
		pathPreviewFolder = nil
	end
end

local function positionIsInsidePart(part, position)
	local localPosition = part.CFrame:PointToObjectSpace(position)
	local halfSize = part.Size / 2

	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y
		and math.abs(localPosition.Z) <= halfSize.Z
end

local function positionIsInsideExitZone(position, roomModel)
	for _, exitPart in ipairs(getRoomExitParts(roomModel)) do
		if positionIsInsidePart(exitPart, position) then
			return true
		end
	end

	return false
end

local function waitUntilAtDoorSpawn(position, roomModel, expectedRoomName, maxSeconds)
	local startTime = os.clock()

	while os.clock() - startTime < maxSeconds do
		if player:GetAttribute("CurrentRoomName") ~= expectedRoomName then
			return false
		end

		local _, rootPart = getCharacterParts()

		if not rootPart then
			return false
		end

		if (rootPart.Position - position).Magnitude <= EXIT_ARRIVAL_DISTANCE
			or positionIsInsideExitZone(rootPart.Position, roomModel) then

			return true
		end

		task.wait(0.1)
	end

	return false
end

local function requestRoomExitMovement()
	local ok, result = pcall(function()
		return requestMoveToRoomExit:Invoke()
	end)

	if not ok or typeof(result) ~= "table" or result.Success ~= true then
		local message = "Could not reach the exit."

		if typeof(result) == "table" and typeof(result.Message) == "string" and result.Message ~= "" then
			message = result.Message
		end

		return false, message
	end

	return true, result.Message
end

local function startLeaveRoomSequence()
	if leaveInProgress then
		return
	end

	local roomModel = getCurrentRoomModel()

	if not roomModel or not isHotelMode() then
		return
	end

	local doorSpawn = findRoomMarker(roomModel, "DoorSpawn")
	local doorSpawnPosition = getMarkerPosition(doorSpawn)

	if not doorSpawnPosition then
		showPrompt("This room is missing DoorSpawn.")
		return
	end

	closePrompt()

	leaveInProgress = true
	clearPathPreview()

	task.spawn(function()
		if not leaveInProgress then
			clearPathPreview()
			return
		end

		clearPathPreview()

		if not standUpIfSeatedForExit() then
			leaveInProgress = false
			showPrompt("Could not leave while seated.")
			return
		end

		local movedToExit, moveMessage = requestRoomExitMovement()

		if not leaveInProgress then
			return
		end

		if not movedToExit then
			leaveInProgress = false
			showPrompt(moveMessage or "Could not reach the exit.")
			return
		end

		local reachedDoor = waitUntilAtDoorSpawn(
			doorSpawnPosition,
			roomModel,
			player:GetAttribute("CurrentRoomName"),
			1
		)

		if not reachedDoor then
			leaveInProgress = false
			showPrompt("Could not reach the exit.")
			return
		end

		task.wait(EXIT_REACHED_DELAY_SECONDS)

		if not leaveInProgress or player:GetAttribute("CurrentRoomName") ~= roomModel.Name then
			return
		end

		roomTransitionRequest:Fire("FadeOut")
		task.wait(FADE_OUT_SECONDS)
		leaveRoomRequest:FireServer()
	end)
end

local function observeRoomEntry(roomName)
	if typeof(roomName) ~= "string" or roomName == "" then
		lastObservedRoomName = nil
		return
	end

	if not isHotelMode() or lastObservedRoomName == roomName then
		return
	end

	lastObservedRoomName = roomName

	task.spawn(function()
		local roomModel = activeRooms:FindFirstChild(roomName)

		if not roomModel then
			roomModel = activeRooms:WaitForChild(roomName, 5)
		end

		if not roomModel or not roomModel:IsA("Model") then
			return
		end

		-- Keep this lookup as a future hook for doorway/cave effects. Missing
		-- markers are allowed; PlayerRoomServer handles DoorSpawn placement.
		findRoomMarker(roomModel, "DoorSpawn")

		local exitParts = getRoomExitParts(roomModel)

		if #exitParts > 0 then
			if not exitReadyLoggedByRoom[roomName] then
				print("[RoomEntryController] RoomExitZone ready.")
				exitReadyLoggedByRoom[roomName] = true
			end
		elseif not missingExitWarnedByRoom[roomName] then
			warn("[RoomEntryController] No RoomExitZone found in current room.")
			missingExitWarnedByRoom[roomName] = true
		end
	end)
end

mouse.Button1Down:Connect(function()
	if leaveInProgress
		or prompt.Visible
		or not isHotelMode()
		or player:GetAttribute("CurrentRoomName") == nil
		or player:GetAttribute("CatalogPlacementActive") == true
		or anyMajorMenuOpen
		or clickIsOnPlayerGui() then

		return
	end

	if isRoomExitInstance(mouse.Target) or getMouseExitRaycastResult() then
		showPrompt()
	end
end)

noButton.MouseButton1Click:Connect(function()
	clearPathPreview()
	closePrompt()
end)

yesButton.MouseButton1Click:Connect(function()
	startLeaveRoomSequence()
end)

leaveRoomResult.OnClientEvent:Connect(function(success, message)
	leaveInProgress = false
	clearPathPreview()

	if success == true then
		closePrompt()
	else
		roomTransitionRequest:Fire("FadeIn")
		showPrompt(message or "Could not leave the room.")
	end
end)

majorMenuStateChanged.Event:Connect(function(isOpen)
	anyMajorMenuOpen = isOpen == true
end)

local function handleCurrentRoomChanged()
	clearPathPreview()
	closePrompt()
	leaveInProgress = false
	observeRoomEntry(player:GetAttribute("CurrentRoomName"))
end

player:GetAttributeChangedSignal("CurrentRoomName"):Connect(handleCurrentRoomChanged)

task.defer(handleCurrentRoomChanged)
