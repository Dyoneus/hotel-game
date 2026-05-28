-- Server-only remote wrapper for marketplace listing management.
-- Patch 1C exposes own-listing create/cancel/list actions only. Purchase flow,
-- public browsing, Coins movement, and client UI are intentionally not included.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MarketplaceService = require(ServerScriptService:WaitForChild("MarketplaceService"))

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

local marketplaceRequest = getOrCreateRemoteEvent("MarketplaceRequest")
local marketplaceResult = getOrCreateRemoteEvent("MarketplaceResult")

local REQUEST_COOLDOWN_SECONDS = 0.5
local lastRequestAtByUserId = {}

local function sendResult(player, payload)
	if not player or player.Parent ~= Players then
		return
	end

	payload = payload or {}
	payload.Kind = tostring(payload.Kind or "Marketplace")
	payload.Success = payload.Success == true
	payload.Message = tostring(payload.Message or "")

	marketplaceResult:FireClient(player, payload)
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

local function handleCreateListing(player, payload)
	if typeof(payload) ~= "table" then
		sendResult(player, {
			Kind = "CreateListing",
			Success = false,
			Message = "Invalid marketplace listing request.",
		})
		return
	end

	local success, message, listing, inventoryDetails =
		MarketplaceService.CreateListing(
			player,
			payload.TemplateId,
			payload.Quantity,
			payload.UnitPriceCoins
		)

	sendResult(player, {
		Kind = "CreateListing",
		Success = success,
		Message = message,
		Listing = listing,
		InventoryDetails = success and inventoryDetails or nil,
		RequestId = payload.RequestId,
	})
end

local function handleCancelListing(player, payload)
	if typeof(payload) ~= "table" then
		sendResult(player, {
			Kind = "CancelListing",
			Success = false,
			Message = "Invalid marketplace cancel request.",
		})
		return
	end

	local success, message, listing, inventoryDetails =
		MarketplaceService.CancelListing(player, payload.ListingId)

	sendResult(player, {
		Kind = "CancelListing",
		Success = success,
		Message = message,
		Listing = listing,
		InventoryDetails = success and inventoryDetails or nil,
		RequestId = payload.RequestId,
	})
end

local function handleGetMyListings(player)
	local success, message, listings = MarketplaceService.GetMyListings(player)

	sendResult(player, {
		Kind = "MyListings",
		Success = success,
		Message = message,
		Listings = listings or {},
	})
end

marketplaceRequest.OnServerEvent:Connect(function(player, actionName, payload)
	if not checkCooldown(player) then
		sendResult(player, {
			Kind = typeof(actionName) == "string" and actionName or "Marketplace",
			Success = false,
			Message = "Slow down before using the marketplace.",
			RequestId = typeof(payload) == "table" and payload.RequestId or nil,
		})
		return
	end

	if actionName == "CreateListing" then
		handleCreateListing(player, payload)
		return
	end

	if actionName == "CancelListing" then
		handleCancelListing(player, payload)
		return
	end

	if actionName == "GetMyListings" then
		handleGetMyListings(player)
		return
	end

	sendResult(player, {
		Kind = typeof(actionName) == "string" and actionName or "Marketplace",
		Success = false,
		Message = "Unknown marketplace action.",
	})
end)

Players.PlayerRemoving:Connect(function(player)
	lastRequestAtByUserId[player.UserId] = nil
end)
