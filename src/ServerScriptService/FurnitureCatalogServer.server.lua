-- Explorer/ServerScriptService/FurnitureCatalogServer.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

local RoomPersistence = require(ServerScriptService:WaitForChild("RoomPersistence"))
local shared = ReplicatedStorage:WaitForChild("Shared")
local FurnitureCatalogConfig = require(shared:WaitForChild("FurnitureCatalogConfig"))
local GridConfig = require(shared:WaitForChild("GridConfig"))
local RoomFloorStyleConfig = require(shared:WaitForChild("RoomFloorStyleConfig"))
local RoomWallStyleConfig = require(shared:WaitForChild("RoomWallStyleConfig"))

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local activeRooms = workspace:WaitForChild("ActiveRooms")

local furnitureTemplates = ReplicatedStorage:FindFirstChild("FurnitureTemplates")

if not furnitureTemplates then
	furnitureTemplates = Instance.new("Folder")
	furnitureTemplates.Name = "FurnitureTemplates"
	furnitureTemplates.Parent = ReplicatedStorage

	warn(
		"[FurnitureCatalogServer] ReplicatedStorage.FurnitureTemplates was missing, " ..
			"so an empty folder was created. Add models such as Chair_01 inside it."
	)
end

local PLACE_COOLDOWN_SECONDS = 0.75
local ADD_TO_INVENTORY_COOLDOWN_SECONDS = 0.5
local MAX_PURCHASE_QUANTITY = 99

-- Lets furniture sit directly beside other furniture without edge-touch
-- being treated as a collision.
local OVERLAP_SHRINK = 0.08
local PLACEMENT_BOUNDS_PART_NAME = "PlacementBounds"
local PLACEMENT_CONTAINMENT_EPSILON = GridConfig.GRID_VALIDATION_TOLERANCE or 0.05
local TEST_GATE_TEMPLATE_NAME = "Gate_Test_OpenClose"
local KNOWN_FOOTPRINT_OVERRIDES = {
	[TEST_GATE_TEMPLATE_NAME] = {
		Width = 1,
		Depth = 1,
	},
}

local function getOrCreateRemoteEvent(name)
	local existing = remoteEvents:FindFirstChild(name)

	if existing then
		if not existing:IsA("RemoteEvent") then
			error(name .. " exists but is not a RemoteEvent.")
		end

		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remoteEvents

	return remote
end

local furnitureCatalogRequest = getOrCreateRemoteEvent("FurnitureCatalogRequest")
local furnitureCatalogResult = getOrCreateRemoteEvent("FurnitureCatalogResult")

local lastPlaceRequestAtByUserId = {}
local lastAddToInventoryRequestAtByUserId = {}

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

local function sendResult(player, kind, success, message, data)
	if not player or player.Parent ~= Players then
		return
	end

	furnitureCatalogResult:FireClient(player, {
		Kind = tostring(kind or "Unknown"),
		Success = success == true,
		Message = tostring(message or ""),
		Data = data or {},
	})
end

local function sendFloorStyleOffersResult(player, success, message, styles)
	if not player or player.Parent ~= Players then
		return
	end

	styles = typeof(styles) == "table" and styles or {}

	furnitureCatalogResult:FireClient(player, {
		Kind = "GetFloorStyleOffers",
		Success = success == true,
		Message = tostring(message or ""),
		Styles = styles,
		Data = {
			Styles = styles,
		},
	})
end

local function sendWallStyleOffersResult(player, success, message, styles)
	if not player or player.Parent ~= Players then
		return
	end

	styles = typeof(styles) == "table" and styles or {}

	furnitureCatalogResult:FireClient(player, {
		Kind = "GetWallStyleOffers",
		Success = success == true,
		Message = tostring(message or ""),
		Styles = styles,
		Data = {
			Styles = styles,
		},
	})
end

local function sendPurchaseFloorStyleResult(player, success, message, result)
	if not player or player.Parent ~= Players then
		return
	end

	result = typeof(result) == "table" and result or {}

	furnitureCatalogResult:FireClient(player, {
		Kind = "PurchaseFloorStyle",
		Success = success == true,
		Message = tostring(message or ""),
		FloorStyleId = result.FloorStyleId,
		DisplayName = result.DisplayName,
		CurrencyKey = result.CurrencyKey,
		Price = result.Price,
		NewCurrencyBalance = result.NewCurrencyBalance,
		Data = result,
	})
end

local function buildFloorStyleOffer(_player, style)
	if typeof(style) ~= "table"
		or typeof(style.FloorStyleId) ~= "string"
		or not RoomFloorStyleConfig.IsValidStyleId(style.FloorStyleId) then

		return nil
	end

	if style.Hidden == true or style.IsHidden == true or style.DevOnly == true then
		return nil
	end

	local isStarter = style.IsDefault == true or style.IsStarter == true
	local applyPrice, applyCurrencyKey = RoomFloorStyleConfig.GetApplyCost(style.FloorStyleId)

	return {
		FloorStyleId = style.FloorStyleId,
		DisplayName = style.DisplayName,
		Description = style.Description,
		Pattern = style.Pattern,
		CurrencyKey = style.CurrencyKey,
		Price = style.Price,
		ApplyPrice = applyPrice,
		ApplyCost = applyPrice,
		ApplyCurrencyKey = applyCurrencyKey,
		CanPurchase = style.CanPurchase == true,
		Starter = isStarter,
		IsStarter = isStarter,
		IsFree = RoomFloorStyleConfig.IsFreeStyle(style.FloorStyleId),
		InfoOnly = true,
		SortOrder = style.SortOrder,
	}
end

local function getFloorStyleOffers(player)
	local offers = {}

	for _, style in ipairs(RoomFloorStyleConfig.GetAllStyles()) do
		local offer = buildFloorStyleOffer(player, style)

		if offer then
			table.insert(offers, offer)
		end
	end

	return offers
end

local function buildWallStyleOffer(_player, style)
	if typeof(style) ~= "table"
		or typeof(style.WallStyleId) ~= "string"
		or not RoomWallStyleConfig.IsValidStyleId(style.WallStyleId) then

		return nil
	end

	if style.Hidden == true or style.IsHidden == true or style.DevOnly == true then
		return nil
	end

	local isStarter = style.IsDefault == true or style.IsStarter == true

	return {
		WallStyleId = style.WallStyleId,
		DisplayName = style.DisplayName,
		Description = style.Description,
		Group = style.Group,
		Pattern = style.Pattern,
		IsStarter = isStarter,
		Starter = isStarter,
		IsDefault = style.IsDefault == true,
		IsFree = RoomWallStyleConfig.IsFreeStyle(style.WallStyleId),
		CanPurchase = style.CanPurchase == true,
		CurrencyKey = style.CurrencyKey,
		Price = style.Price,
		InfoOnly = true,
		SortOrder = style.SortOrder,
	}
end

local function getWallStyleOffers(player)
	local offers = {}

	for _, style in ipairs(RoomWallStyleConfig.GetAllStyles()) do
		local offer = buildWallStyleOffer(player, style)

		if offer then
			table.insert(offers, offer)
		end
	end

	return offers
end

local function getCurrentRoomModel(player)
	local roomName = player:GetAttribute("CurrentRoomName")

	if typeof(roomName) ~= "string" or roomName == "" then
		return nil
	end

	local roomModel = activeRooms:FindFirstChild(roomName)

	if not roomModel or not roomModel:IsA("Model") then
		return nil
	end

	return roomModel
end

local function getRoomFolder(roomModel)
	return roomModel and roomModel:FindFirstChild("Room")
end

local function getFurnitureFolder(roomModel)
	return roomModel and roomModel:FindFirstChild("Furniture")
end

local function getWalkableFloor(roomModel)
	local roomFolder = getRoomFolder(roomModel)

	if not roomFolder then
		return nil
	end

	local floor = roomFolder:FindFirstChild("WalkableFloor")

	if floor and floor:IsA("BasePart") then
		return floor
	end

	return nil
end

local function isRoomOwner(player, roomModel)
	return roomModel
		and roomModel:GetAttribute("OwnerUserId") == player.UserId
end

local function canUseCatalog(player)
	local roomModel = getCurrentRoomModel(player)

	if not roomModel then
		return false, nil
	end

	if player:GetAttribute("RoomMode") ~= "Edit" then
		return false, roomModel
	end

	if not isRoomOwner(player, roomModel) then
		return false, roomModel
	end

	return true, roomModel
end

local function checkPlaceCooldown(player)
	local now = os.clock()
	local previous = lastPlaceRequestAtByUserId[player.UserId]

	if previous and now - previous < PLACE_COOLDOWN_SECONDS then
		return false
	end

	lastPlaceRequestAtByUserId[player.UserId] = now
	return true
end

local function checkAddToInventoryCooldown(player)
	local now = os.clock()
	local previous = lastAddToInventoryRequestAtByUserId[player.UserId]

	if previous and now - previous < ADD_TO_INVENTORY_COOLDOWN_SECONDS then
		return false
	end

	lastAddToInventoryRequestAtByUserId[player.UserId] = now
	return true
end

local function getTemplate(templateName)
	if typeof(templateName) ~= "string" or templateName == "" then
		return nil
	end

	local template = furnitureTemplates:FindFirstChild(templateName)

	if template and template:IsA("Model") then
		return template
	end

	return nil
end

local function getStringAttribute(instance, attributeName, defaultValue)
	if not instance then
		return defaultValue
	end

	local value = instance:GetAttribute(attributeName)

	if typeof(value) == "string" and value ~= "" then
		return value
	end

	return defaultValue
end

local function getBooleanAttribute(instance, attributeName, defaultValue)
	if not instance then
		return defaultValue
	end

	local value = instance:GetAttribute(attributeName)

	if typeof(value) == "boolean" then
		return value
	end

	return defaultValue
end

local function getPositiveIntegerAttributeStrict(instance, attributeName)
	if not instance then
		return nil
	end

	local value = instance:GetAttribute(attributeName)

	if typeof(value) == "number"
		and value == value
		and value > 0
		and value < math.huge
		and math.floor(value) == value then

		return value
	end

	return nil
end

local function getNonNegativeIntegerAttributeStrict(instance, attributeName, defaultValue)
	if not instance then
		return defaultValue
	end

	local value = instance:GetAttribute(attributeName)

	if typeof(value) == "number"
		and value == value
		and value >= 0
		and value < math.huge
		and math.floor(value) == value then

		return value
	end

	return defaultValue
end

local function autoCatalogKeyMatches(template, key)
	if typeof(key) ~= "string" or key == "" then
		return false
	end

	if template.Name == key then
		return true
	end

	local id = getStringAttribute(template, "Id", nil)
	local templateName = getStringAttribute(template, "TemplateName", nil)
	local templateId = getStringAttribute(template, "TemplateId", nil)

	return id == key
		or templateName == key
		or templateId == key
end

local function findAutoCatalogTemplateByKey(key)
	if typeof(key) ~= "string" or key == "" then
		return nil
	end

	for _, child in ipairs(furnitureTemplates:GetChildren()) do
		if child:IsA("Model")
			and child:GetAttribute("AutoCatalogEnabled") == true
			and autoCatalogKeyMatches(child, key) then

			return child
		end
	end

	return nil
end

local function resolveTemplateModel(templateName)
	local template = getTemplate(templateName)

	if template then
		return template
	end

	return findAutoCatalogTemplateByKey(templateName)
end

local function getCatalogTemplateName(item)
	if typeof(item) ~= "table" then
		return nil
	end

	if typeof(item.TemplateName) == "string" and item.TemplateName ~= "" then
		return item.TemplateName
	end

	if typeof(item.TemplateId) == "string" and item.TemplateId ~= "" then
		return item.TemplateId
	end

	if typeof(item.Id) == "string" and item.Id ~= "" then
		return item.Id
	end

	return nil
end

local function buildAutoCatalogItemFromTemplate(template)
	if not template
		or not template:IsA("Model")
		or template:GetAttribute("AutoCatalogEnabled") ~= true then

		return nil, "Unknown catalog item."
	end

	local price = getPositiveIntegerAttributeStrict(template, "Price")

	if not price then
		return nil, "Catalog item is missing a valid price."
	end

	local currencyKey = getStringAttribute(template, "CurrencyKey", nil)
	local purchaseCurrency = getStringAttribute(template, "PurchaseCurrency", nil)
	local resolvedCurrency = purchaseCurrency or currencyKey

	if not resolvedCurrency then
		return nil, "Catalog item is missing a purchase currency."
	end

	local itemId = getStringAttribute(template, "Id", template.Name)
	local templateName =
		getStringAttribute(template, "TemplateName", getStringAttribute(template, "TemplateId", template.Name))
	local sellPrice = getNonNegativeIntegerAttributeStrict(template, "SellPrice", 0)

	return {
		Id = itemId,
		TemplateName = templateName,
		DisplayName = getStringAttribute(template, "DisplayName", template.Name),
		Description = getStringAttribute(template, "Description", ""),
		MaxPerRoom = nil,
		Category = getStringAttribute(template, "Category", "Other"),
		FootprintWidth = getPositiveIntegerAttributeStrict(template, "FootprintWidth"),
		FootprintDepth = getPositiveIntegerAttributeStrict(template, "FootprintDepth"),
		Price = price,
		SellPrice = sellPrice,
		CurrencyKey = currencyKey or resolvedCurrency,
		PurchaseCurrency = resolvedCurrency,
		TradableOnPurchase = getBooleanAttribute(template, "TradableOnPurchase", false),
		Sellable = getBooleanAttribute(template, "SellableOnPurchase", true),
		PermissionActions = {},
		SupportsOpenClose = getBooleanAttribute(template, "SupportsOpenClose", false),
		DefaultAction = getStringAttribute(template, "DefaultAction", nil),
		OpenCloseTargetName = getStringAttribute(template, "OpenCloseTargetName", nil),
		Featured = getBooleanAttribute(template, "Featured", false),
		IsLimited = false,
	}, nil
end

local function resolveCatalogItemById(itemId)
	if typeof(itemId) ~= "string" or itemId == "" then
		return nil, "Invalid item.", nil
	end

	local item = FurnitureCatalogConfig.GetItem(itemId)

	if item then
		local templateName = getCatalogTemplateName(item)
		local template = resolveTemplateModel(templateName)

		if not template then
			return nil, "Missing furniture template: " .. tostring(templateName), nil
		end

		if template:GetAttribute("AutoCatalogEnabled") == true then
			local autoItem, autoMessage = buildAutoCatalogItemFromTemplate(template)

			if not autoItem then
				return nil, autoMessage, template
			end

			return autoItem, nil, template
		end

		return item, nil, template
	end

	local autoTemplate = findAutoCatalogTemplateByKey(itemId)

	if autoTemplate then
		local autoItem, autoMessage = buildAutoCatalogItemFromTemplate(autoTemplate)

		if not autoItem then
			return nil, autoMessage, autoTemplate
		end

		return autoItem, nil, autoTemplate
	end

	return nil, "Unknown catalog item.", nil
end

local function resolveCatalogItemByTemplateName(templateName)
	return resolveCatalogItemById(templateName)
end

local function getInventoryOnlyTestItem(itemId)
	if itemId ~= TEST_GATE_TEMPLATE_NAME then
		return nil
	end

	local template = getTemplate(TEST_GATE_TEMPLATE_NAME)

	if not template then
		return nil
	end

	return {
		Id = TEST_GATE_TEMPLATE_NAME,
		TemplateName = TEST_GATE_TEMPLATE_NAME,
		DisplayName = getStringAttribute(template, "DisplayName", "Test Gate"),
		Category = getStringAttribute(template, "Category", "Gate"),
		FootprintWidth = 1,
		FootprintDepth = 1,
		SupportsOpenClose = getBooleanAttribute(template, "SupportsOpenClose", true),
		DefaultAction = getStringAttribute(template, "DefaultAction", "OpenClose"),
		OpenCloseTargetName = getStringAttribute(template, "OpenCloseTargetName", "GatePanel"),
	}
end

local function applyKnownFootprintOverride(model, templateName)
	if not model or typeof(templateName) ~= "string" then
		return
	end

	local footprintOverride = KNOWN_FOOTPRINT_OVERRIDES[templateName]

	if not footprintOverride then
		return
	end

	model:SetAttribute("FootprintWidth", footprintOverride.Width)
	model:SetAttribute("FootprintDepth", footprintOverride.Depth)
end

local function getPublicCatalog()
	local publicItems = {}

	for _, item in ipairs(FurnitureCatalogConfig.GetPublicCatalog()) do
		local itemId = item.Id or item.TemplateName
		local resolvedItem = itemId and resolveCatalogItemById(itemId)

		if resolvedItem then
			table.insert(publicItems, item)
		end
	end

	return publicItems
end

local function shouldUsePartForPlacementBounds(instance)
	if not instance:IsA("BasePart") then
		return false
	end

	if helperPartNames[instance.Name] then
		return false
	end

	return true
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

local function partFitsInsideFloor(part, floor)
	local floorHalfX = floor.Size.X / 2
	local floorHalfZ = floor.Size.Z / 2

	local partHalfX = part.Size.X / 2
	local partHalfZ = part.Size.Z / 2

	local corners = {
		Vector3.new(-partHalfX, 0, -partHalfZ),
		Vector3.new(-partHalfX, 0, partHalfZ),
		Vector3.new(partHalfX, 0, -partHalfZ),
		Vector3.new(partHalfX, 0, partHalfZ),
	}

	for _, localCorner in ipairs(corners) do
		local worldCorner = part.CFrame:PointToWorldSpace(localCorner)
		local floorLocalCorner = floor.CFrame:PointToObjectSpace(worldCorner)

		if math.abs(floorLocalCorner.X) > floorHalfX + PLACEMENT_CONTAINMENT_EPSILON then
			return false
		end

		if math.abs(floorLocalCorner.Z) > floorHalfZ + PLACEMENT_CONTAINMENT_EPSILON then
			return false
		end
	end

	return true
end

local function modelFitsInsideRoom(model, floor)
	local placementParts = getPlacementCheckParts(model)

	if #placementParts == 0 then
		return false
	end

	for _, descendant in ipairs(placementParts) do
		if not partFitsInsideFloor(descendant, floor) then
			return false
		end
	end

	return true
end

local function modelBlockedAtCurrentCFrame(roomModel, model)
	local roomFolder = getRoomFolder(roomModel)
	local furnitureFolder = getFurnitureFolder(roomModel)

	if not roomFolder or not furnitureFolder then
		return true
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { model }

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

			if helperPartNames[touchingPart.Name] then
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

local function modelWouldOverlapCharacter(roomModel, model)
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer:GetAttribute("CurrentRoomName") == roomModel.Name then
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

local function getPositiveIntegerAttribute(instance, attributeName)
	if not instance then
		return nil
	end

	local value = instance:GetAttribute(attributeName)

	if typeof(value) == "number"
		and value == value
		and value > 0
		and value < math.huge
		and math.floor(value) == value then

		return value
	end

	return nil
end

local function getExplicitFurnitureFootprint(model)
	local templateId = model and model:GetAttribute("TemplateId")
	local footprintOverride = typeof(templateId) == "string" and KNOWN_FOOTPRINT_OVERRIDES[templateId] or nil

	if footprintOverride then
		return footprintOverride.Width, footprintOverride.Depth
	end

	if getPositiveIntegerAttribute(model, "FootprintWidth")
		or getPositiveIntegerAttribute(model, "FootprintDepth") then

		return GridConfig.GetFurnitureFootprint(model)
	end

	return nil, nil
end

local function getDerivedCurrentFootprint(model, floor, tileSize)
	local minX = math.huge
	local maxX = -math.huge
	local minZ = math.huge
	local maxZ = -math.huge
	local foundPart = false

	for _, descendant in ipairs(getPlacementCheckParts(model)) do
		foundPart = true
		local halfSize = descendant.Size / 2
		local localCorners = {
			Vector3.new(-halfSize.X, 0, -halfSize.Z),
			Vector3.new(-halfSize.X, 0, halfSize.Z),
			Vector3.new(halfSize.X, 0, -halfSize.Z),
			Vector3.new(halfSize.X, 0, halfSize.Z),
		}

		for _, localCorner in ipairs(localCorners) do
			local worldCorner = descendant.CFrame:PointToWorldSpace(localCorner)
			local floorLocalCorner = floor.CFrame:PointToObjectSpace(worldCorner)

			minX = math.min(minX, floorLocalCorner.X)
			maxX = math.max(maxX, floorLocalCorner.X)
			minZ = math.min(minZ, floorLocalCorner.Z)
			maxZ = math.max(maxZ, floorLocalCorner.Z)
		end
	end

	if not foundPart then
		return 1, 1
	end

	local widthStuds = math.max(maxX - minX, tileSize)
	local depthStuds = math.max(maxZ - minZ, tileSize)
	local widthTiles = math.max(1, math.ceil((widthStuds - PLACEMENT_CONTAINMENT_EPSILON) / tileSize))
	local depthTiles = math.max(1, math.ceil((depthStuds - PLACEMENT_CONTAINMENT_EPSILON) / tileSize))

	return widthTiles, depthTiles
end

local function getCurrentFootprintForMask(model, floor, gridContext)
	local footprintWidth, footprintDepth = getExplicitFurnitureFootprint(model)

	if footprintWidth and footprintDepth then
		if footprintWidth ~= footprintDepth then
			local localLookVector = floor.CFrame:VectorToObjectSpace(model:GetPivot().LookVector)

			if math.abs(localLookVector.X) > math.abs(localLookVector.Z) then
				footprintWidth, footprintDepth = footprintDepth, footprintWidth
			end
		end

		return footprintWidth, footprintDepth
	end

	return getDerivedCurrentFootprint(model, floor, gridContext.TileSize or GridConfig.TILE_SIZE)
end

local function modelFitsTileMask(roomModel, model)
	local floor = getWalkableFloor(roomModel)

	if not floor then
		return false
	end

	local gridContext = GridConfig.GetGridContext(roomModel)

	if not gridContext or gridContext.UsesTileMask ~= true then
		return true
	end

	local cellX, cellZ = GridConfig.WorldToCell(gridContext, model:GetPivot().Position)

	if not cellX or not cellZ then
		return false
	end

	if not GridConfig.CellIsWalkable(gridContext, cellX, cellZ) then
		return false
	end

	local footprintWidth, footprintDepth = getCurrentFootprintForMask(model, floor, gridContext)
	local footprintWalkable = GridConfig.FootprintCellsAreWalkable(
		gridContext,
		cellX,
		cellZ,
		footprintWidth,
		footprintDepth,
		0
	)

	return footprintWalkable == true
end

local function countCatalogItemInRoom(furnitureFolder, templateName)
	local count = 0

	for _, furnitureModel in ipairs(furnitureFolder:GetChildren()) do
		if furnitureModel:IsA("Model") then
			if furnitureModel:GetAttribute("TemplateId") == templateName then
				count += 1
			end
		end
	end

	return count
end

local function findPlacementCFrame(roomModel, furnitureModel)
	local floor = getWalkableFloor(roomModel)

	if not floor then
		return nil
	end

	if not GridConfig.UsesTileGrid(roomModel, floor) then
		return nil
	end

	local originalPivot = furnitureModel:GetPivot()
	local originalRotation = originalPivot - originalPivot.Position

	local boundingCFrame, boundingSize = furnitureModel:GetBoundingBox()
	local bottomY = boundingCFrame.Position.Y - boundingSize.Y / 2
	local floorTopY = GridConfig.GetFloorTopY(floor)
	local pivotYOffsetFromBottom = originalPivot.Position.Y - bottomY
	local tileBounds = GridConfig.GetTileBounds(roomModel, floor)
	local gridContext = GridConfig.GetGridContext(roomModel)

	if not floorTopY or not tileBounds or not gridContext then
		return nil
	end

	local centerX = (tileBounds.GridWidth - 1) / 2
	local centerZ = (tileBounds.GridDepth - 1) / 2
	local candidates = {}

	if gridContext.UsesTileMask == true then
		for _, cell in ipairs(GridConfig.GetWalkableCells(gridContext)) do
			table.insert(candidates, {
				cellX = cell.X,
				cellZ = cell.Z,
				distance = math.abs((cell.X - 1) - centerX) + math.abs((cell.Z - 1) - centerZ),
			})
		end
	else
		for xIndex = 0, tileBounds.GridWidth - 1 do
			for zIndex = 0, tileBounds.GridDepth - 1 do
				table.insert(candidates, {
					xIndex = xIndex,
					zIndex = zIndex,
					distance = math.abs(xIndex - centerX) + math.abs(zIndex - centerZ),
				})
			end
		end
	end

	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)

	for _, candidate in ipairs(candidates) do
		local worldPosition = nil

		if gridContext.UsesTileMask == true then
			worldPosition = GridConfig.CellToWorld(gridContext, candidate.cellX, candidate.cellZ)
		else
			local localFloorPosition = Vector3.new(
				-tileBounds.HalfWidthStuds + tileBounds.TileSize / 2 + candidate.xIndex * tileBounds.TileSize,
				0,
				-tileBounds.HalfDepthStuds + tileBounds.TileSize / 2 + candidate.zIndex * tileBounds.TileSize
			)

			worldPosition = GridConfig.FloorLocalToWorld(floor, localFloorPosition)
		end

		if worldPosition then
			local candidateCFrame =
				CFrame.new(
					worldPosition.X,
					floorTopY + pivotYOffsetFromBottom,
					worldPosition.Z
				)
				* originalRotation

			furnitureModel:PivotTo(candidateCFrame)

			if modelFitsInsideRoom(furnitureModel, floor)
				and modelFitsTileMask(roomModel, furnitureModel)
				and not modelBlockedAtCurrentCFrame(roomModel, furnitureModel)
				and not modelWouldOverlapCharacter(roomModel, furnitureModel) then

				return candidateCFrame
			end
		end
	end

	return nil
end

local function normalizeRotationY(rotationY)
	if typeof(rotationY) ~= "number" then
		return 0
	end

	rotationY = math.floor((rotationY / 90) + 0.5) * 90
	rotationY = rotationY % 360

	return rotationY
end

local function getRequestedPlacementCFrame(roomModel, furnitureModel, targetPosition, rotationY)
	if typeof(targetPosition) ~= "Vector3" then
		return nil, "Click a valid floor tile to place this furniture."
	end

	local floor = getWalkableFloor(roomModel)

	if not floor then
		return nil, "Click a valid floor tile to place this furniture."
	end

	if not GridConfig.UsesTileGrid(roomModel, floor) then
		return nil, "Furniture can only be placed in grid rooms."
	end

	local gridContext = GridConfig.GetGridContext(roomModel)
	local snappedWorldPosition = nil

	if gridContext and gridContext.UsesTileMask == true then
		local cellX, cellZ = GridConfig.WorldToCell(gridContext, targetPosition)

		if not cellX or not cellZ or not GridConfig.CellIsWalkable(gridContext, cellX, cellZ) then
			return nil, "Invalid placement position."
		end

		snappedWorldPosition = GridConfig.CellToWorld(gridContext, cellX, cellZ)
	else
		local tileSize = GridConfig.GetTileSize(roomModel, floor)
		snappedWorldPosition = GridConfig.SnapWorldToTileCenter(floor, targetPosition, tileSize)
	end

	local floorTopY = GridConfig.GetFloorTopY(floor)

	if not snappedWorldPosition or not floorTopY then
		return nil, "Invalid placement position."
	end

	local originalPivot = furnitureModel:GetPivot()
	local originalRotation = originalPivot - originalPivot.Position

	local boundingCFrame, boundingSize = furnitureModel:GetBoundingBox()
	local bottomY = boundingCFrame.Position.Y - boundingSize.Y / 2
	local pivotYOffsetFromBottom = originalPivot.Position.Y - bottomY

	local yawRotation = CFrame.Angles(0, math.rad(normalizeRotationY(rotationY)), 0)

	return CFrame.new(
		snappedWorldPosition.X,
		floorTopY + pivotYOffsetFromBottom,
		snappedWorldPosition.Z
	) * yawRotation * originalRotation
end

local function createPersistentId(player, templateName)
	return templateName
		.. "_"
		.. tostring(player.UserId)
		.. "_"
		.. HttpService:GenerateGUID(false)
end

local function getItemPrice(item)
	local price = item and item.Price

	if typeof(price) ~= "number"
		or price ~= price
		or price < 0
		or price == math.huge then

		return 0
	end

	return math.floor(price)
end

local function getPurchaseCurrency(item)
	local currencyKey = item and item.PurchaseCurrency

	if typeof(currencyKey) ~= "string" or currencyKey == "" then
		return "Dollars"
	end

	return currencyKey
end

local function getMaxPurchaseQuantity(item)
	local maxPurchaseQuantity = item and item.MaxPurchaseQuantity

	if typeof(maxPurchaseQuantity) == "number"
		and maxPurchaseQuantity == maxPurchaseQuantity
		and maxPurchaseQuantity > 0
		and maxPurchaseQuantity < math.huge then

		local maxValue = math.floor(maxPurchaseQuantity)

		if maxValue >= 1 then
			return math.min(maxValue, MAX_PURCHASE_QUANTITY)
		end
	end

	return MAX_PURCHASE_QUANTITY
end

local function getRequestedPurchaseQuantity(payload, item)
	local quantity = payload.Quantity

	if quantity == nil then
		quantity = 1
	end

	if typeof(quantity) ~= "number"
		or quantity ~= quantity
		or quantity <= 0
		or quantity >= math.huge
		or quantity ~= math.floor(quantity) then

		return nil, "Quantity must be a positive integer."
	end

	local maxPurchaseQuantity = getMaxPurchaseQuantity(item)

	if quantity > maxPurchaseQuantity then
		return nil, "Quantity is too high."
	end

	return quantity
end

local function sendAddToInventoryResult(
	player,
	success,
	message,
	item,
	templateId,
	newCount,
	inventoryDetails,
	extraData
)
	if not player or player.Parent ~= Players then
		return
	end

	extraData = extraData or {}

	local data = {
		ItemId = item and item.Id or nil,
		TemplateId = templateId,
		Quantity = extraData.Quantity,
		UnitPrice = extraData.UnitPrice,
		NewCount = newCount,
		InventoryDetails = inventoryDetails,
		Price = extraData.Price,
		CurrencyKey = extraData.CurrencyKey,
		Tradable = extraData.Tradable,
		Sellable = extraData.Sellable,
		NewCurrencyBalance = extraData.NewCurrencyBalance,
	}

	furnitureCatalogResult:FireClient(player, {
		Kind = "AddToInventory",
		Success = success == true,
		Message = tostring(message or ""),
		ItemId = data.ItemId,
		TemplateId = data.TemplateId,
		Quantity = data.Quantity,
		UnitPrice = data.UnitPrice,
		NewCount = data.NewCount,
		InventoryDetails = data.InventoryDetails,
		Price = data.Price,
		CurrencyKey = data.CurrencyKey,
		Tradable = data.Tradable,
		Sellable = data.Sellable,
		NewCurrencyBalance = data.NewCurrencyBalance,
		Data = data,
	})
end

local function handleAddToInventory(player, payload)
	if not checkAddToInventoryCooldown(player) then
		sendAddToInventoryResult(player, false, "Slow down before getting another item.")
		return
	end

	if typeof(payload) ~= "table" then
		sendAddToInventoryResult(player, false, "Invalid catalog request.")
		return
	end

	local itemId = payload.ItemId

	if typeof(itemId) ~= "string" then
		sendAddToInventoryResult(player, false, "Invalid item.")
		return
	end

	local item, itemMessage = resolveCatalogItemById(itemId)

	if not item then
		sendAddToInventoryResult(player, false, itemMessage or "Unknown catalog item.")
		return
	end

	local templateId = getCatalogTemplateName(item)
	local template = resolveTemplateModel(templateId)

	if not template then
		sendAddToInventoryResult(
			player,
			false,
			"Missing furniture template: " .. tostring(templateId),
			item,
			templateId
		)
		return
	end

	local quantity, quantityMessage = getRequestedPurchaseQuantity(payload, item)
	local unitPrice = getItemPrice(item)
	local totalPrice = unitPrice
	local currencyKey = getPurchaseCurrency(item)
	local isTradable = item.TradableOnPurchase == true
	local isSellable = item.Sellable ~= false

	if not quantity then
		sendAddToInventoryResult(
			player,
			false,
			quantityMessage or "Invalid quantity.",
			item,
			templateId,
			nil,
			nil,
			{
				Quantity = payload.Quantity,
				UnitPrice = unitPrice,
				Price = totalPrice,
				CurrencyKey = currencyKey,
				Tradable = isTradable,
				Sellable = isSellable,
			}
		)
		return
	end

	totalPrice = unitPrice * quantity

	if currencyKey ~= "Dollars" then
		sendAddToInventoryResult(
			player,
			false,
			"This item is not available yet.",
			item,
			templateId,
			nil,
			nil,
			{
				Quantity = quantity,
				UnitPrice = unitPrice,
				Price = totalPrice,
				CurrencyKey = currencyKey,
				Tradable = isTradable,
				Sellable = isSellable,
			}
		)
		return
	end

	local newDollarBalance = RoomPersistence.GetCurrency(player, currencyKey)

	if totalPrice > 0 then
		local removed, removeMessage, balance =
			RoomPersistence.RemoveCurrency(
				player,
				currencyKey,
				totalPrice,
				"ShopPurchase:" .. item.Id .. "x" .. tostring(quantity)
			)

		newDollarBalance = balance

		if not removed then
			local purchaseMessage = "Not enough Dollars."

			if removeMessage and removeMessage ~= "Not enough currency." then
				purchaseMessage = removeMessage
			end

			sendAddToInventoryResult(
				player,
				false,
				purchaseMessage,
				item,
				templateId,
				nil,
				nil,
				{
					Quantity = quantity,
					UnitPrice = unitPrice,
					Price = totalPrice,
					CurrencyKey = currencyKey,
					Tradable = isTradable,
					Sellable = isSellable,
					NewCurrencyBalance = newDollarBalance,
				}
			)
			return
		end
	end

	local added, message, newCount, inventoryDetails =
		RoomPersistence.AddInventoryItem(player, templateId, quantity, {
			Tradable = isTradable,
			Sellable = isSellable,
		})

	if not added then
		local refundedBalance = newDollarBalance

		if totalPrice > 0 then
			local refunded, refundMessage, balance =
				RoomPersistence.AddCurrency(
					player,
					currencyKey,
					totalPrice,
					"ShopPurchaseRefund:" .. item.Id .. "x" .. tostring(quantity)
				)

			refundedBalance = balance or refundedBalance

			if not refunded then
				warn(
					"Shop purchase refund failed for",
					player.Name,
					item.Id,
					refundMessage
				)
			end
		end

		warn("Shop purchase inventory add failed for", player.Name, item.Id, message)

		sendAddToInventoryResult(
			player,
			false,
			message or "Could not add item to inventory.",
			item,
			templateId,
			newCount,
			inventoryDetails,
			{
				Quantity = quantity,
				UnitPrice = unitPrice,
				Price = totalPrice,
				CurrencyKey = currencyKey,
				Tradable = isTradable,
				Sellable = isSellable,
				NewCurrencyBalance = refundedBalance,
			}
		)
		return
	end

	if totalPrice <= 0 then
		newDollarBalance = RoomPersistence.GetCurrency(player, currencyKey)
	end

	local itemName = tostring(item.DisplayName or item.Id)

	sendAddToInventoryResult(
		player,
		true,
		"Purchased " .. itemName .. " x" .. tostring(quantity) .. ".",
		item,
		templateId,
		newCount,
		inventoryDetails,
		{
			Quantity = quantity,
			UnitPrice = unitPrice,
			Price = totalPrice,
			CurrencyKey = currencyKey,
			Tradable = isTradable,
			Sellable = isSellable,
			NewCurrencyBalance = newDollarBalance,
		}
	)
end

local function handlePlaceItem(player, payload, options)
	options = options or {}

	local resultKind = options.ResultKind or "PlaceItem"
	local consumeInventory = options.ConsumeInventory == true

	if not checkPlaceCooldown(player) then
		sendResult(player, resultKind, false, "Slow down before placing another item.")
		return
	end

	if typeof(payload) ~= "table" then
		sendResult(player, resultKind, false, "Invalid catalog request.")
		return
	end

	local itemId = payload.ItemId

	if typeof(itemId) ~= "string" then
		sendResult(player, resultKind, false, "Invalid item.")
		return
	end

	local item, itemMessage = resolveCatalogItemByTemplateName(itemId)

	if not item and consumeInventory then
		item = getInventoryOnlyTestItem(itemId)
		itemMessage = nil
	end

	if not item then
		sendResult(player, resultKind, false, itemMessage or "Unknown catalog item.")
		return
	end

	local canUse, roomModel = canUseCatalog(player)

	if not canUse then
		sendResult(player, resultKind, false, "Enter Edit Mode in your own room first.")
		return
	end

	local furnitureFolder = getFurnitureFolder(roomModel)

	if not furnitureFolder then
		sendResult(player, resultKind, false, "This room has no Furniture folder.")
		return
	end

	local templateName = getCatalogTemplateName(item)

	if item.MaxPerRoom then
		local currentCount = countCatalogItemInRoom(furnitureFolder, templateName)

		if currentCount >= item.MaxPerRoom then
			sendResult(
				player,
				resultKind,
				false,
				"You already placed the maximum amount of this item."
			)
			return
		end
	end

	local template = resolveTemplateModel(templateName)

	if not template then
		sendResult(player, resultKind, false, "Missing furniture template: " .. tostring(templateName))
		return
	end

	local targetPosition = payload.TargetPosition

	if typeof(targetPosition) ~= "Vector3" then
		sendResult(player, resultKind, false, "Click a valid floor tile to place this furniture.")
		return
	end

	local furnitureClone = template:Clone()
	furnitureClone.Name = template.Name
	furnitureClone:SetAttribute("TemplateId", templateName)
	applyKnownFootprintOverride(furnitureClone, templateName)
	furnitureClone:SetAttribute("PersistentId", createPersistentId(player, templateName))
	furnitureClone:SetAttribute("Tradable", true)
	furnitureClone:SetAttribute("Sellable", true)

	local placementCFrame, placementError = getRequestedPlacementCFrame(
		roomModel,
		furnitureClone,
		targetPosition,
		payload.RotationY
	)

	if not placementCFrame then
		furnitureClone:Destroy()
		sendResult(player, resultKind, false, placementError or "Invalid placement position.")
		return
	end

	furnitureClone:PivotTo(placementCFrame)

	local floor = getWalkableFloor(roomModel)

	if not floor or not modelFitsInsideRoom(furnitureClone, floor) then
		furnitureClone:Destroy()
		sendResult(player, resultKind, false, "Furniture must stay inside the room.")
		return
	end

	if not modelFitsTileMask(roomModel, furnitureClone) then
		furnitureClone:Destroy()
		sendResult(player, resultKind, false, "Furniture must stay inside the room.")
		return
	end

	if modelBlockedAtCurrentCFrame(roomModel, furnitureClone) then
		furnitureClone:Destroy()
		sendResult(player, resultKind, false, "That spot is blocked.")
		return
	end

	if modelWouldOverlapCharacter(roomModel, furnitureClone) then
		furnitureClone:Destroy()
		sendResult(player, resultKind, false, "Cannot place furniture on top of a player.")
		return
	end

	local remainingCount = nil
	local placedTradable = true
	local placedSellable = true
	local placementInventoryDetails = nil

	if consumeInventory then
		local templateId = templateName
		local removed, _, newCount, inventoryDetails =
			RoomPersistence.RemoveInventoryItem(player, templateId, 1)

		if not removed then
			furnitureClone:Destroy()
			sendResult(
				player,
				resultKind,
				false,
				"You do not own enough of that item.",
				{
					ItemId = item.Id,
					TemplateId = templateId,
					Source = "Inventory",
					RemainingCount = newCount or 0,
				}
			)
			return
		end

		remainingCount = newCount
		placementInventoryDetails = inventoryDetails
		placedTradable = not (
			typeof(inventoryDetails) == "table"
			and typeof(inventoryDetails.ConsumedUntradableCount) == "number"
			and inventoryDetails.ConsumedUntradableCount > 0
		)
		placedSellable = not (
			typeof(inventoryDetails) == "table"
			and typeof(inventoryDetails.ConsumedUnsellableCount) == "number"
			and inventoryDetails.ConsumedUnsellableCount > 0
		)
	end

	furnitureClone:SetAttribute("Tradable", placedTradable)
	furnitureClone:SetAttribute("Sellable", placedSellable)

	furnitureClone.Parent = furnitureFolder

	local roomState = RoomPersistence.CaptureRoomState(player, roomModel)
	local saved = false

	if roomState then
		saved = RoomPersistence.SavePlayer(player)

		if not saved then
			warn("Furniture placement save flush failed for", player.Name, templateName)
		end
	else
		warn("Furniture placement room capture failed for", player.Name, templateName)
	end

	local saveMessageSuffix = ""

	if not saved then
		saveMessageSuffix = " Save may be delayed."
	end

	if consumeInventory then
		sendResult(
			player,
			resultKind,
			true,
			item.DisplayName .. " placed from inventory." .. saveMessageSuffix,
			{
				ItemId = item.Id,
				TemplateId = templateName,
				Source = "Inventory",
				RemainingCount = remainingCount,
				InventoryDetails = placementInventoryDetails,
				Sellable = placedSellable,
			}
		)
		return
	end

	sendResult(
		player,
		"PlaceItem",
		true,
		item.DisplayName .. " placed. Use Move to reposition it." .. saveMessageSuffix,
		{
			ItemId = item.Id,
			PersistentId = furnitureClone:GetAttribute("PersistentId"),
			Sellable = true,
		}
	)
end

furnitureCatalogRequest.OnServerEvent:Connect(function(player, actionName, payload)
	if actionName == "GetCatalog" then
		sendResult(player, "Catalog", true, "Catalog loaded.", {
			Items = getPublicCatalog(),
		})
		return
	end

	if actionName == "GetFloorStyleOffers" then
		sendFloorStyleOffersResult(player, true, "Floor styles loaded.", getFloorStyleOffers(player))
		return
	end

	if actionName == "GetWallStyleOffers" then
		sendWallStyleOffersResult(player, true, "Wall styles loaded.", getWallStyleOffers(player))
		return
	end

	if actionName == "PurchaseFloorStyle" then
		if typeof(payload) ~= "table" or typeof(payload.FloorStyleId) ~= "string" then
			sendPurchaseFloorStyleResult(player, false, "Invalid floor style request.", nil)
			return
		end

		local style = RoomFloorStyleConfig.GetStyle(payload.FloorStyleId)
		sendPurchaseFloorStyleResult(player, false, "Preview and apply floors from Room Settings.", {
			FloorStyleId = payload.FloorStyleId,
			DisplayName = style and style.DisplayName or nil,
			CurrencyKey = style and style.CurrencyKey or nil,
			Price = style and style.Price or nil,
		})
		return
	end

	if actionName == "PlaceItem" then
		sendResult(player, "PlaceItem", false, "Catalog items are now added to Inventory first.")
		return
	end

	if actionName == "AddToInventory" then
		handleAddToInventory(player, payload)
		return
	end

	if actionName == "PlaceInventoryItem" then
		handlePlaceItem(player, payload, {
			ResultKind = "PlaceInventoryItem",
			ConsumeInventory = true,
		})
		return
	end

	sendResult(player, "Unknown", false, "Unknown catalog action.")
end)

Players.PlayerRemoving:Connect(function(player)
	lastPlaceRequestAtByUserId[player.UserId] = nil
	lastAddToInventoryRequestAtByUserId[player.UserId] = nil
end)
