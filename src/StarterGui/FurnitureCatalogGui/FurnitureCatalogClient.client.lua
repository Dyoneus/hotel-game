-- StarterGui/FurnitureCatalogGui/FurnitureCatalogClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local furnitureCatalogRequest = remoteEvents:WaitForChild("FurnitureCatalogRequest")
local furnitureCatalogResult = remoteEvents:WaitForChild("FurnitureCatalogResult")

local activeRooms = workspace:WaitForChild("ActiveRooms")
local furnitureTemplates = ReplicatedStorage:WaitForChild("FurnitureTemplates")

local gui = script.Parent
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 160

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

local latestCatalogItems = {}
local requestInFlight = false

local updateOpenButton = nil
local destroyCatalogPlacementPreview = nil

local placingItemData = nil
local placementPreview = nil
local placementPreviewHighlight = nil
local placementIsValid = false
local placementRotationY = 0
local placementBaseRotation = CFrame.new()

local PLACEMENT_GRID_SIZE = 2
local OVERLAP_SHRINK = 0.08
local PLACEMENT_BOUNDS_PART_NAME = "PlacementBounds"

local CATALOG_ROTATE_ACTION = "CatalogRotatePreview"
local CATALOG_CANCEL_ACTION = "CatalogCancelPlacement"

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

local function getCurrentRoomModel()
	local roomName = player:GetAttribute("CurrentRoomName")

	if typeof(roomName) ~= "string" or roomName == "" then
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

	local floor = roomFolder:FindFirstChild("WalkableFloor")

	if floor and floor:IsA("BasePart") then
		return floor
	end

	return nil
end

local function isCurrentRoomOwner()
	local roomModel = getCurrentRoomModel()

	if not roomModel then
		return false
	end

	return roomModel:GetAttribute("OwnerUserId") == player.UserId
end

local function shouldShowCatalogButton()
	local currentRoomName = player:GetAttribute("CurrentRoomName")

	return typeof(currentRoomName) == "string"
		and currentRoomName ~= ""
		and (player:GetAttribute("ControlMode") or "Hotel") == "Hotel"
		and player:GetAttribute("RoomMode") == "Edit"
end

local openButton = Instance.new("TextButton")
openButton.Name = "OpenFurnitureCatalogButton"
openButton.AnchorPoint = Vector2.new(1, 1)
openButton.Position = UDim2.new(1, -20, 1, -74)
openButton.Size = UDim2.fromOffset(150, 44)
openButton.BackgroundColor3 = Color3.fromRGB(60, 110, 170)
openButton.BorderSizePixel = 0
openButton.Text = "Catalog"
openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
openButton.TextScaled = true
openButton.Font = Enum.Font.GothamBold
openButton.Visible = false
openButton.Parent = gui

createCorner(openButton, 10)
createStroke(openButton, Color3.fromRGB(255, 255, 255), 1, 0.25)

local panel = Instance.new("Frame")
panel.Name = "FurnitureCatalogPanel"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -24, 0.5, 0)
panel.Size = UDim2.fromOffset(390, 500)
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
titleLabel.Text = "Furniture Catalog"
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
statusLabel.Size = UDim2.new(1, -36, 0, 42)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Place furniture into your room. Use Move after placing."
statusLabel.TextColor3 = Color3.fromRGB(90, 90, 90)
statusLabel.TextWrapped = true
statusLabel.TextScaled = true
statusLabel.Font = Enum.Font.Gotham
statusLabel.Parent = panel

local placementHintLabel = Instance.new("TextLabel")
placementHintLabel.Name = "PlacementHintLabel"
placementHintLabel.AnchorPoint = Vector2.new(0.5, 1)
placementHintLabel.Position = UDim2.new(0.5, 0, 1, -24)
placementHintLabel.Size = UDim2.fromOffset(560, 46)
placementHintLabel.BackgroundColor3 = Color3.fromRGB(35, 45, 60)
placementHintLabel.BackgroundTransparency = 0.08
placementHintLabel.BorderSizePixel = 0
placementHintLabel.Text = ""
placementHintLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
placementHintLabel.TextScaled = true
placementHintLabel.TextWrapped = true
placementHintLabel.Font = Enum.Font.GothamBold
placementHintLabel.Visible = false
placementHintLabel.Parent = gui

createCorner(placementHintLabel, 12)
createStroke(placementHintLabel, Color3.fromRGB(255, 255, 255), 1, 0.35)

local itemList = Instance.new("ScrollingFrame")
itemList.Name = "ItemList"
itemList.Position = UDim2.fromOffset(18, 112)
itemList.Size = UDim2.new(1, -36, 1, -132)
itemList.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
itemList.BorderSizePixel = 0
itemList.ScrollBarThickness = 6
itemList.CanvasSize = UDim2.fromOffset(0, 0)
itemList.Parent = panel

createCorner(itemList, 12)
createStroke(itemList, Color3.fromRGB(220, 220, 220), 1, 0)

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = itemList

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 10)
listPadding.PaddingBottom = UDim.new(0, 10)
listPadding.PaddingLeft = UDim.new(0, 10)
listPadding.PaddingRight = UDim.new(0, 10)
listPadding.Parent = itemList

local function setPanelVisible(isVisible)
	panel.Visible = isVisible
	openButton.Visible = (not isVisible) and shouldShowCatalogButton()
end

local function setStatus(text)
	statusLabel.Text = tostring(text or "")
end

local function setPlacementHint(text)
	text = tostring(text or "")

	placementHintLabel.Text = text
	placementHintLabel.Visible = text ~= ""
end

local helperPartNames = {
	CollisionBuffer = true,
	SitPoint = true,
	SleepPoint = true,
	PlayPoint = true,
	EnterPoint = true,
	TalkPoint = true,
	ClickHitbox = true,
	RoomAnchor = true,
	DoorSpawn = true,
}

local function snapToPlacementGrid(value)
	return math.floor((value / PLACEMENT_GRID_SIZE) + 0.5) * PLACEMENT_GRID_SIZE
end

local function isHelperPart(part)
	return helperPartNames[part.Name] == true
end

local function shouldUsePartForPlacementBounds(part)
	if not part:IsA("BasePart") then
		return false
	end

	if isHelperPart(part) then
		return false
	end

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
			and descendant.Name == PLACEMENT_BOUNDS_PART_NAME then

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

local function modelHasPlacementBounds(model)
	return #getPlacementBoundsParts(model) > 0
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

	-- If the touched furniture has PlacementBounds, ignore its visual parts.
	-- The PlacementBounds part itself will handle the collision rule.
	if modelHasPlacementBounds(touchedFurnitureModel)
		and touchingPart.Name ~= PLACEMENT_BOUNDS_PART_NAME then

		return true
	end

	return false
end

local function getOverlapCheckSize(size)
	return Vector3.new(
		math.max(size.X - OVERLAP_SHRINK, 0.05),
		math.max(size.Y - OVERLAP_SHRINK, 0.05),
		math.max(size.Z - OVERLAP_SHRINK, 0.05)
	)
end

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

local function getFloorPlacementBounds()
	local floor = getCurrentFloor()

	if not floor then
		return nil
	end

	local halfX = floor.Size.X / 2
	local halfZ = floor.Size.Z / 2
	local edgeMargin = 0.05

	return {
		minX = floor.Position.X - halfX + edgeMargin,
		maxX = floor.Position.X + halfX - edgeMargin,
		minZ = floor.Position.Z - halfZ + edgeMargin,
		maxZ = floor.Position.Z + halfZ - edgeMargin,
	}
end

local function clampPreviewCFrameInsideRoom(model, targetCFrame)
	local floorBounds = getFloorPlacementBounds()
	local modelBounds = getModelXZBoundsAtCFrame(model, targetCFrame)

	if not floorBounds or not modelBounds then
		return targetCFrame
	end

	local offsetX = 0
	local offsetZ = 0

	if modelBounds.minX < floorBounds.minX then
		offsetX = floorBounds.minX - modelBounds.minX
	elseif modelBounds.maxX > floorBounds.maxX then
		offsetX = floorBounds.maxX - modelBounds.maxX
	end

	if modelBounds.minZ < floorBounds.minZ then
		offsetZ = floorBounds.minZ - modelBounds.minZ
	elseif modelBounds.maxZ > floorBounds.maxZ then
		offsetZ = floorBounds.maxZ - modelBounds.maxZ
	end

	return targetCFrame + Vector3.new(offsetX, 0, offsetZ)
end

local function getMouseFloorPosition()
	local floor = getCurrentFloor()
	local camera = workspace.CurrentCamera

	if not floor or not camera then
		return nil
	end

	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { floor }

	local result = workspace:Raycast(
		unitRay.Origin,
		unitRay.Direction * 1000,
		raycastParams
	)

	if result then
		return result.Position
	end

	return nil
end

local function getPreviewPlacementCFrame(model)
	local floorPosition = getMouseFloorPosition()
	local floor = getCurrentFloor()

	if not floorPosition or not floor then
		return nil
	end

	local snappedX = snapToPlacementGrid(floorPosition.X)
	local snappedZ = snapToPlacementGrid(floorPosition.Z)

	local boundingCFrame, boundingSize = model:GetBoundingBox()
	local bottomY = boundingCFrame.Position.Y - boundingSize.Y / 2
	local floorTopY = floor.Position.Y + floor.Size.Y / 2
	local pivotYOffsetFromBottom = model:GetPivot().Position.Y - bottomY

	local targetCFrame =
		CFrame.new(
			snappedX,
			floorTopY + pivotYOffsetFromBottom,
			snappedZ
		)
		* CFrame.Angles(0, math.rad(placementRotationY), 0)
		* placementBaseRotation

	return clampPreviewCFrameInsideRoom(model, targetCFrame)
end

local function isPreviewInsideRoom(model)
	local targetCFrame = model:GetPivot()
	local floorBounds = getFloorPlacementBounds()
	local modelBounds = getModelXZBoundsAtCFrame(model, targetCFrame)

	if not floorBounds or not modelBounds then
		return false
	end

	return modelBounds.minX >= floorBounds.minX
		and modelBounds.maxX <= floorBounds.maxX
		and modelBounds.minZ >= floorBounds.minZ
		and modelBounds.maxZ <= floorBounds.maxZ
end

local function isPreviewBlocked(model)
	local roomFolder = getCurrentRoomFolder()
	local furnitureFolder = getCurrentFurnitureFolder()

	if not roomFolder or not furnitureFolder then
		return true
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	local ignoreList = { model }

	if player.Character then
		table.insert(ignoreList, player.Character)
	end

	overlapParams.FilterDescendantsInstances = ignoreList

	for _, descendant in ipairs(getPlacementCheckParts(model)) do
		local touchingParts = workspace:GetPartBoundsInBox(
			descendant.CFrame,
			getOverlapCheckSize(descendant.Size),
			overlapParams
		)

		for _, touchingPart in ipairs(touchingParts) do
			if touchingPart.Name == "WalkableFloor" then
				continue
			end

			if isHelperPart(touchingPart) then
				continue
			end

			if touchingPart:IsDescendantOf(furnitureFolder) then
				if shouldIgnoreTouchedFurniturePart(touchingPart, furnitureFolder) then
					continue
				end

				if touchingPart.Name ~= PLACEMENT_BOUNDS_PART_NAME
					and touchingPart:IsA("BasePart")
					and touchingPart.CanCollide == false then

					continue
				end

				return true
			end

			if touchingPart:IsDescendantOf(roomFolder) then
				if touchingPart.Name:find("Boundary")
					or touchingPart.Name:find("Wall") then

					return true
				end

				if touchingPart:IsA("BasePart") and touchingPart.CanCollide then
					return true
				end
			end
		end
	end

	return false
end

local function playerIsInSameRoom(otherPlayer)
	return otherPlayer:GetAttribute("CurrentRoomName")
		== player:GetAttribute("CurrentRoomName")
end

local function isPreviewBlockedByPlayer(model)
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if playerIsInSameRoom(otherPlayer) then
			local character = otherPlayer.Character

			if character then
				local overlapParams = OverlapParams.new()
				overlapParams.FilterType = Enum.RaycastFilterType.Include
				overlapParams.FilterDescendantsInstances = { character }

				for _, descendant in ipairs(getPlacementCheckParts(model)) do
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

	if isValid then
		fillColor = Color3.fromRGB(0, 190, 255)
	else
		fillColor = Color3.fromRGB(255, 60, 60)
	end

	if placementPreviewHighlight then
		placementPreviewHighlight.Enabled = true
		placementPreviewHighlight.FillColor = fillColor
		placementPreviewHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
		placementPreviewHighlight.FillTransparency = 0.35
		placementPreviewHighlight.OutlineTransparency = 0
		placementPreviewHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	end

	if placementPreview then
		for _, descendant in ipairs(placementPreview:GetDescendants()) do
			if descendant:IsA("BasePart")
				and not isHelperPart(descendant)
				and descendant.Name ~= PLACEMENT_BOUNDS_PART_NAME then
				descendant.Color = fillColor
				descendant.Transparency = 0.35
				descendant.Material = Enum.Material.Neon
			end
		end
	end
end

local function unbindCatalogPlacementControls()
	ContextActionService:UnbindAction(CATALOG_ROTATE_ACTION)
	ContextActionService:UnbindAction(CATALOG_CANCEL_ACTION)
end

local function handleCatalogPlacementAction(actionName, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end

	if not placingItemData then
		return Enum.ContextActionResult.Pass
	end

	if actionName == CATALOG_ROTATE_ACTION then
		placementRotationY = (placementRotationY + 90) % 360
		setStatus("Rotated preview.")
		setPlacementHint("Click to place • R to rotate • C to cancel")
		return Enum.ContextActionResult.Sink
	end

	if actionName == CATALOG_CANCEL_ACTION then
		destroyCatalogPlacementPreview()
		setStatus("Placement cancelled.")
		return Enum.ContextActionResult.Sink
	end

	return Enum.ContextActionResult.Sink
end

local function bindCatalogPlacementControls()
	unbindCatalogPlacementControls()

	ContextActionService:BindActionAtPriority(
		CATALOG_ROTATE_ACTION,
		handleCatalogPlacementAction,
		false,
		3000,
		Enum.KeyCode.R
	)

	ContextActionService:BindActionAtPriority(
		CATALOG_CANCEL_ACTION,
		handleCatalogPlacementAction,
		false,
		3000,
		Enum.KeyCode.C
	)
end

destroyCatalogPlacementPreview = function()
	if placementPreview then
		placementPreview:Destroy()
		placementPreview = nil
	end

	if placementPreviewHighlight then
		placementPreviewHighlight:Destroy()
		placementPreviewHighlight = nil
	end

	unbindCatalogPlacementControls()

	placingItemData = nil
	placementIsValid = false
	placementRotationY = 0
	placementBaseRotation = CFrame.new()
	requestInFlight = false

	setPlacementHint("")

	player:SetAttribute("CatalogPlacementActive", false)

	if updateOpenButton then
		updateOpenButton()
	end
end

local function createCatalogPlacementPreview(itemData)
	destroyCatalogPlacementPreview()

	local templateName = itemData.TemplateName or itemData.Id
	local template = furnitureTemplates:FindFirstChild(templateName)

	if not template or not template:IsA("Model") then
		setStatus("Missing furniture template: " .. tostring(templateName))
		return
	end

	placingItemData = itemData
	placementRotationY = 0
	placementBaseRotation = CFrame.new()
	player:SetAttribute("CatalogPlacementActive", true)

	bindCatalogPlacementControls()

	placementPreview = template:Clone()
	placementPreview.Name = "CatalogPlacementPreview"

	local templatePivot = placementPreview:GetPivot()
	placementBaseRotation = templatePivot - templatePivot.Position

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
	placementPreviewHighlight.Name = "CatalogPlacementPreviewHighlight"
	placementPreviewHighlight.Adornee = placementPreview
	placementPreviewHighlight.FillTransparency = 0.45
	placementPreviewHighlight.OutlineTransparency = 0
	placementPreviewHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	placementPreviewHighlight.Parent = placementPreview

	setPlacementPreviewValidity(false)

	panel.Visible = false
	openButton.Visible = false

	setStatus("Move your cursor over the floor. Click to place, R to rotate, C to cancel.")
	setPlacementHint("Click to place • R to rotate • C to cancel")
end

local function updateCatalogPlacementPreview()
	if not placingItemData or not placementPreview then
		return
	end

	local targetCFrame = getPreviewPlacementCFrame(placementPreview)

	if not targetCFrame then
		setPlacementPreviewValidity(false)
		return
	end

	placementPreview:PivotTo(targetCFrame)

	local isValid = isPreviewInsideRoom(placementPreview)
		and not isPreviewBlocked(placementPreview)
		and not isPreviewBlockedByPlayer(placementPreview)

	setPlacementPreviewValidity(isValid)
end

local function confirmCatalogPlacement()
	if not placingItemData or not placementPreview then
		return
	end

	if requestInFlight then
		return
	end

	if not placementIsValid then
		setStatus("That spot is blocked.")
		setPlacementHint("That spot is blocked • Move cursor • R to rotate • C to cancel")
		return
	end

	requestInFlight = true

	local itemId = placingItemData.Id
	local targetPosition = placementPreview:GetPivot().Position

	setStatus("Placing " .. tostring(placingItemData.DisplayName or itemId) .. "...")

	furnitureCatalogRequest:FireServer("PlaceItem", {
		ItemId = itemId,
		TargetPosition = targetPosition,
		RotationY = placementRotationY,
	})
end

local function clearItemRows()
	for _, child in ipairs(itemList:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function createItemRow(itemData, layoutOrder)
	local row = Instance.new("TextButton")
	row.Name = tostring(itemData.Id)
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.new(1, -4, 0, 78)
	row.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
	row.BorderSizePixel = 0
	row.Text = ""
	row.AutoButtonColor = true
	row.Parent = itemList

	createCorner(row, 10)
	createStroke(row, Color3.fromRGB(220, 220, 220), 1, 0)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Position = UDim2.fromOffset(12, 8)
	nameLabel.Size = UDim2.new(1, -24, 0, 24)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = tostring(itemData.DisplayName or itemData.Id)
	nameLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = row

	local descriptionLabel = Instance.new("TextLabel")
	descriptionLabel.Name = "DescriptionLabel"
	descriptionLabel.Position = UDim2.fromOffset(12, 36)
	descriptionLabel.Size = UDim2.new(1, -24, 0, 20)
	descriptionLabel.BackgroundTransparency = 1
	descriptionLabel.Text = tostring(itemData.Description or "Place this item.")
	descriptionLabel.TextColor3 = Color3.fromRGB(95, 95, 95)
	descriptionLabel.TextScaled = true
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.Font = Enum.Font.Gotham
	descriptionLabel.Parent = row

	local placeLabel = Instance.new("TextLabel")
	placeLabel.Name = "PlaceLabel"
	placeLabel.AnchorPoint = Vector2.new(1, 1)
	placeLabel.Position = UDim2.new(1, -12, 1, -8)
	placeLabel.Size = UDim2.fromOffset(120, 20)
	placeLabel.BackgroundTransparency = 1
	placeLabel.Text = "Click to place"
	placeLabel.TextColor3 = Color3.fromRGB(70, 150, 255)
	placeLabel.TextScaled = true
	placeLabel.TextXAlignment = Enum.TextXAlignment.Right
	placeLabel.Font = Enum.Font.GothamBold
	placeLabel.Parent = row

	row.MouseButton1Click:Connect(function()
		if requestInFlight then
			return
		end

		createCatalogPlacementPreview(itemData)
	end)
end

local function renderCatalog(items)
	latestCatalogItems = items or {}
	clearItemRows()

	if #latestCatalogItems == 0 then
		setStatus("No furniture templates found in ReplicatedStorage/FurnitureTemplates.")
	else
		setStatus("Click an item to place it. Then use Move to reposition it.")
	end

	for index, itemData in ipairs(latestCatalogItems) do
		createItemRow(itemData, index)
	end

	task.defer(function()
		itemList.CanvasSize = UDim2.fromOffset(
			0,
			listLayout.AbsoluteContentSize.Y + 20
		)
	end)
end

updateOpenButton = function()
	if placingItemData then
		openButton.Visible = false
		return
	end

	if panel.Visible then
		openButton.Visible = false
	else
		openButton.Visible = shouldShowCatalogButton()
	end
end

openButton.MouseButton1Click:Connect(function()
	setPanelVisible(true)
	setStatus("Loading catalog...")
	furnitureCatalogRequest:FireServer("GetCatalog", {})
end)

closeButton.MouseButton1Click:Connect(function()
	setPanelVisible(false)
end)

RunService.RenderStepped:Connect(updateCatalogPlacementPreview)

mouse.Button1Down:Connect(function()
	if not placingItemData then
		return
	end

	confirmCatalogPlacement()
end)

furnitureCatalogResult.OnClientEvent:Connect(function(response)
	if typeof(response) ~= "table" then
		return
	end

	local kind = response.Kind
	local success = response.Success == true
	local message = tostring(response.Message or "")
	local data = response.Data

	if kind == "Catalog" then
		if success and typeof(data) == "table" and typeof(data.Items) == "table" then
			renderCatalog(data.Items)
		else
			renderCatalog({})
			setStatus(message)
		end

		return
	end

	if kind == "PlaceItem" then
		requestInFlight = false
		setStatus(message)

		if success then
			destroyCatalogPlacementPreview()

			-- Refresh in case future catalog limits hide or update items.
			furnitureCatalogRequest:FireServer("GetCatalog", {})
		end

		return
	end

	requestInFlight = false
	setStatus(message)
end)

local function handleCatalogVisibilityChanged()
	if placingItemData and not shouldShowCatalogButton() then
		destroyCatalogPlacementPreview()
	end

	updateOpenButton()
end

player:GetAttributeChangedSignal("CurrentRoomName"):Connect(handleCatalogVisibilityChanged)
player:GetAttributeChangedSignal("RoomMode"):Connect(handleCatalogVisibilityChanged)
player:GetAttributeChangedSignal("OnboardingStep"):Connect(handleCatalogVisibilityChanged)
player:GetAttributeChangedSignal("ControlMode"):Connect(handleCatalogVisibilityChanged)
player:GetAttributeChangedSignal("HasCreatedRoom"):Connect(handleCatalogVisibilityChanged)

activeRooms.ChildAdded:Connect(function()
	task.defer(updateOpenButton)
end)

activeRooms.ChildRemoved:Connect(function()
	task.defer(updateOpenButton)
end)

task.defer(updateOpenButton)