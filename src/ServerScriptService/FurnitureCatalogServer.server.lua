-- Explorer/ServerScriptService/FurnitureCatalogServer.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

local RoomPersistence = require(ServerScriptService:WaitForChild("RoomPersistence"))
local shared = ReplicatedStorage:WaitForChild("Shared")
local FurnitureCatalogConfig = require(shared:WaitForChild("FurnitureCatalogConfig"))

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

local GRID_SIZE = 2
local PLACE_COOLDOWN_SECONDS = 0.75
local ADD_TO_INVENTORY_COOLDOWN_SECONDS = 0.5
local MAX_PURCHASE_QUANTITY = 99

-- Lets furniture sit directly beside other furniture without edge-touch
-- being treated as a collision.
local OVERLAP_SHRINK = 0.08
local PLACEMENT_BOUNDS_PART_NAME = "PlacementBounds"

local catalogById = {}
local catalogByTemplateName = {}

for _, item in ipairs(FurnitureCatalogConfig.GetItemsArray()) do
	catalogById[item.Id] = item
	catalogByTemplateName[item.TemplateName] = item
end

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

local function getPublicCatalog()
	local publicItems = {}

	for _, item in ipairs(FurnitureCatalogConfig.GetPublicCatalog()) do
		if getTemplate(item.TemplateName) then
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

		if math.abs(floorLocalCorner.X) > floorHalfX then
			return false
		end

		if math.abs(floorLocalCorner.Z) > floorHalfZ then
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

	local originalPivot = furnitureModel:GetPivot()
	local originalRotation = originalPivot - originalPivot.Position

	local boundingCFrame, boundingSize = furnitureModel:GetBoundingBox()
	local bottomY = boundingCFrame.Position.Y - boundingSize.Y / 2
	local floorTopY = floor.Position.Y + floor.Size.Y / 2
	local pivotYOffsetFromBottom = originalPivot.Position.Y - bottomY

	local maxXSteps = math.max(
		0,
		math.floor((floor.Size.X / 2 - GRID_SIZE) / GRID_SIZE)
	)

	local maxZSteps = math.max(
		0,
		math.floor((floor.Size.Z / 2 - GRID_SIZE) / GRID_SIZE)
	)

	local maxRadius = math.max(maxXSteps, maxZSteps)

	for radius = 0, maxRadius do
		for xStep = -radius, radius do
			for zStep = -radius, radius do
				local isOuterRing = math.abs(xStep) == radius
					or math.abs(zStep) == radius

				if isOuterRing
					and math.abs(xStep) <= maxXSteps
					and math.abs(zStep) <= maxZSteps then

					local localFloorPosition = Vector3.new(
						xStep * GRID_SIZE,
						0,
						zStep * GRID_SIZE
					)

					local worldPosition = floor.CFrame:PointToWorldSpace(localFloorPosition)

					local candidateCFrame =
						CFrame.new(
							worldPosition.X,
							floorTopY + pivotYOffsetFromBottom,
							worldPosition.Z
						)
						* originalRotation

					furnitureModel:PivotTo(candidateCFrame)

					if modelFitsInsideRoom(furnitureModel, floor)
						and not modelBlockedAtCurrentCFrame(roomModel, furnitureModel)
						and not modelWouldOverlapCharacter(roomModel, furnitureModel) then

						return candidateCFrame
					end
				end
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
		return nil
	end

	local floor = getWalkableFloor(roomModel)

	if not floor then
		return nil
	end

	local snappedX = math.floor((targetPosition.X / GRID_SIZE) + 0.5) * GRID_SIZE
	local snappedZ = math.floor((targetPosition.Z / GRID_SIZE) + 0.5) * GRID_SIZE

	local originalPivot = furnitureModel:GetPivot()
	local originalRotation = originalPivot - originalPivot.Position

	local boundingCFrame, boundingSize = furnitureModel:GetBoundingBox()
	local bottomY = boundingCFrame.Position.Y - boundingSize.Y / 2
	local floorTopY = floor.Position.Y + floor.Size.Y / 2
	local pivotYOffsetFromBottom = originalPivot.Position.Y - bottomY

	local yawRotation = CFrame.Angles(0, math.rad(normalizeRotationY(rotationY)), 0)

	return CFrame.new(
		snappedX,
		floorTopY + pivotYOffsetFromBottom,
		snappedZ
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

	local item = FurnitureCatalogConfig.GetItem(itemId)

	if not item then
		sendAddToInventoryResult(player, false, "Unknown catalog item.")
		return
	end

	local templateId = item.TemplateName or item.Id

	if not getTemplate(templateId) then
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

	local item = catalogById[itemId] or catalogByTemplateName[itemId]

	if not item then
		sendResult(player, resultKind, false, "Unknown catalog item.")
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

	if item.MaxPerRoom then
		local currentCount = countCatalogItemInRoom(furnitureFolder, item.TemplateName)

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

	local template = getTemplate(item.TemplateName)

	if not template then
		sendResult(player, resultKind, false, "Missing furniture template: " .. item.TemplateName)
		return
	end

	local targetPosition = payload.TargetPosition

	if typeof(targetPosition) ~= "Vector3" then
		sendResult(player, resultKind, false, "Click a valid floor tile to place this furniture.")
		return
	end

	local furnitureClone = template:Clone()
	furnitureClone.Name = template.Name
	furnitureClone:SetAttribute("TemplateId", item.TemplateName)
	furnitureClone:SetAttribute("PersistentId", createPersistentId(player, item.TemplateName))
	furnitureClone:SetAttribute("Tradable", true)
	furnitureClone:SetAttribute("Sellable", true)

	local placementCFrame = getRequestedPlacementCFrame(
		roomModel,
		furnitureClone,
		targetPosition,
		payload.RotationY
	)

	if not placementCFrame then
		furnitureClone:Destroy()
		sendResult(player, resultKind, false, "Invalid placement position.")
		return
	end

	furnitureClone:PivotTo(placementCFrame)

	local floor = getWalkableFloor(roomModel)

	if not floor or not modelFitsInsideRoom(furnitureClone, floor) then
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
		local templateId = item.TemplateName or item.Id
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
			warn("Furniture placement save flush failed for", player.Name, item.TemplateName)
		end
	else
		warn("Furniture placement room capture failed for", player.Name, item.TemplateName)
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
				TemplateId = item.TemplateName,
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
