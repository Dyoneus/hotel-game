-- ServerScriptService/InventoryServer.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RoomPersistence = require(ServerScriptService:WaitForChild("RoomPersistence"))
local FurnitureCatalogConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FurnitureCatalogConfig"))

local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")

if not remoteEvents then
	remoteEvents = Instance.new("Folder")
	remoteEvents.Name = "RemoteEvents"
	remoteEvents.Parent = ReplicatedStorage
elseif not remoteEvents:IsA("Folder") then
	error("ReplicatedStorage.RemoteEvents exists but is not a Folder.")
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

local inventoryRequest = getOrCreateRemoteEvent("InventoryRequest")
local inventoryResult = getOrCreateRemoteEvent("InventoryResult")

local REQUEST_COOLDOWN_SECONDS = 0.5
local SELL_COOLDOWN_SECONDS = 0.35
local MAX_SELL_QUANTITY = 99
local DEBUG_GET_INVENTORY = false
local DEBUG_GET_INVENTORY_TEMPLATE_ID = "Chair_01"
local lastRequestAtByUserId = {}
local lastSellRequestAtByUserId = {}

local function sendResult(player, kind, success, message, inventory, inventoryDetails)
	if not player or player.Parent ~= Players then
		return
	end

	inventoryResult:FireClient(player, {
		Kind = tostring(kind or "Inventory"),
		Success = success == true,
		Inventory = inventory or {},
		InventoryDetails = inventoryDetails or {},
		Message = tostring(message or ""),
	})
end

local function sendPayload(player, payload)
	if not player or player.Parent ~= Players then
		return
	end

	payload = payload or {}
	payload.Kind = tostring(payload.Kind or "Unknown")
	payload.Success = payload.Success == true
	payload.Message = tostring(payload.Message or "")

	inventoryResult:FireClient(player, payload)
end

local function debugGetInventorySnapshot(player, inventory, inventoryDetails)
	if not DEBUG_GET_INVENTORY then
		return
	end

	local templateId = DEBUG_GET_INVENTORY_TEMPLATE_ID
	local details = typeof(inventoryDetails) == "table" and inventoryDetails[templateId] or nil

	print(
		"InventoryServer GetInventory",
		"userId=", player.UserId,
		"Inventory." .. templateId .. "=", typeof(inventory) == "table" and inventory[templateId] or nil,
		"Total=", typeof(details) == "table" and details.Total or nil,
		"Tradable=", typeof(details) == "table" and details.Tradable or nil
	)
end

local function getCurrentInventoryPayload(player)
	if not RoomPersistence.GetProfile(player) then
		return false, "Profile is not loaded.", {}, {}
	end

	local inventory = RoomPersistence.GetInventorySnapshot(player)
	local inventoryDetails = RoomPersistence.GetInventoryDetailsSnapshot(player)

	debugGetInventorySnapshot(player, inventory, inventoryDetails)

	return true, "Inventory loaded.", inventory, inventoryDetails
end

local function checkCooldown(player)
	local now = os.clock()
	local previous = lastRequestAtByUserId[player.UserId]

	if previous and now - previous < REQUEST_COOLDOWN_SECONDS then
		return false
	end

	lastRequestAtByUserId[player.UserId] = now
	return true
end

local function checkSellCooldown(player)
	local now = os.clock()
	local previous = lastSellRequestAtByUserId[player.UserId]

	if previous and now - previous < SELL_COOLDOWN_SECONDS then
		return false
	end

	lastSellRequestAtByUserId[player.UserId] = now
	return true
end

local function isPositiveInteger(value)
	return typeof(value) == "number"
		and value == value
		and value > 0
		and value < math.huge
		and value == math.floor(value)
end

local function getSellPrice(item)
	local sellPrice = item and item.SellPrice

	if typeof(sellPrice) ~= "number"
		or sellPrice ~= sellPrice
		or sellPrice <= 0
		or sellPrice >= math.huge then

		return nil
	end

	return math.floor(sellPrice)
end

local function restoreSoldInventory(player, templateId, quantity, details)
	if typeof(details) ~= "table" then
		RoomPersistence.AddInventoryItem(player, templateId, quantity, {
			Sellable = true,
		})
		return
	end

	local untradableCount = 0

	if typeof(details.ConsumedUntradableCount) == "number" then
		untradableCount = math.clamp(math.floor(details.ConsumedUntradableCount), 0, quantity)
	end

	local tradableCount = quantity - untradableCount

	if untradableCount > 0 then
		RoomPersistence.AddInventoryItem(player, templateId, untradableCount, {
			Tradable = false,
			Sellable = true,
		})
	end

	if tradableCount > 0 then
		RoomPersistence.AddInventoryItem(player, templateId, tradableCount, {
			Tradable = true,
			Sellable = true,
		})
	end
end

local function handleSellInventoryItem(player, payload)
	if not checkSellCooldown(player) then
		sendPayload(player, {
			Kind = "SellInventoryItem",
			Success = false,
			Message = "Please wait a moment.",
		})
		return
	end

	if typeof(payload) ~= "table" then
		sendPayload(player, {
			Kind = "SellInventoryItem",
			Success = false,
			Message = "Invalid sell request.",
		})
		return
	end

	local itemId = payload.ItemId

	if typeof(itemId) ~= "string" or itemId == "" then
		sendPayload(player, {
			Kind = "SellInventoryItem",
			Success = false,
			Message = "Invalid item.",
		})
		return
	end

	local quantity = payload.Quantity or 1

	if not isPositiveInteger(quantity) then
		sendPayload(player, {
			Kind = "SellInventoryItem",
			Success = false,
			Message = "Invalid quantity.",
			ItemId = itemId,
		})
		return
	end

	if quantity > MAX_SELL_QUANTITY then
		sendPayload(player, {
			Kind = "SellInventoryItem",
			Success = false,
			Message = "Quantity is too high.",
			ItemId = itemId,
			Quantity = quantity,
		})
		return
	end

	local item = FurnitureCatalogConfig.GetItem(itemId)

	if not item then
		sendPayload(player, {
			Kind = "SellInventoryItem",
			Success = false,
			Message = "Unknown inventory item.",
			ItemId = itemId,
			Quantity = quantity,
		})
		return
	end

	local sellPrice = getSellPrice(item)
	local templateId = item.TemplateName or item.Id

	if not sellPrice then
		sendPayload(player, {
			Kind = "SellInventoryItem",
			Success = false,
			Message = "This item cannot be sold.",
			ItemId = item.Id,
			TemplateId = templateId,
			Quantity = quantity,
		})
		return
	end

	local removed, removeMessage, newCount, inventoryDetails =
		RoomPersistence.RemoveSellableInventoryItem(player, templateId, quantity)

	if not removed then
		sendPayload(player, {
			Kind = "SellInventoryItem",
			Success = false,
			Message = removeMessage or "No sellable items.",
			ItemId = item.Id,
			TemplateId = templateId,
			Quantity = quantity,
			UnitSellPrice = sellPrice,
			InventoryDetails = inventoryDetails,
			NewCount = newCount,
		})
		return
	end

	local totalDollars = sellPrice * quantity
	local added, addMessage, newDollarBalance =
		RoomPersistence.AddCurrency(player, "Dollars", totalDollars, "SellFurniture:" .. item.Id .. "x" .. tostring(quantity))

	if not added then
		warn("Inventory sell currency grant failed for", player.Name, item.Id, addMessage)
		restoreSoldInventory(player, templateId, quantity, inventoryDetails)

		sendPayload(player, {
			Kind = "SellInventoryItem",
			Success = false,
			Message = addMessage or "Could not sell item.",
			ItemId = item.Id,
			TemplateId = templateId,
			Quantity = quantity,
			UnitSellPrice = sellPrice,
			TotalDollars = totalDollars,
		})
		return
	end

	sendPayload(player, {
		Kind = "SellInventoryItem",
		Success = true,
		Message = "Sold " .. tostring(item.Id) .. " x" .. tostring(quantity) .. ".",
		ItemId = item.Id,
		TemplateId = templateId,
		Quantity = quantity,
		UnitSellPrice = sellPrice,
		TotalDollars = totalDollars,
		NewCount = newCount,
		InventoryDetails = inventoryDetails,
		NewCurrencyBalance = newDollarBalance,
		CurrencyKey = "Dollars",
	})
end

inventoryRequest.OnServerEvent:Connect(function(player, actionName, payload)
	if actionName == "SellInventoryItem" then
		handleSellInventoryItem(player, payload)
		return
	end

	if not checkCooldown(player) then
		sendResult(player, "Inventory", false, "Slow down before requesting inventory.")
		return
	end

	if actionName == "GetInventory" then
		local success, message, inventory, inventoryDetails = getCurrentInventoryPayload(player)

		sendResult(player, "Inventory", success, message, inventory, inventoryDetails)
		return
	end

	sendResult(player, "Unknown", false, "Unknown inventory action.")
end)

Players.PlayerRemoving:Connect(function(player)
	lastRequestAtByUserId[player.UserId] = nil
	lastSellRequestAtByUserId[player.UserId] = nil
end)
