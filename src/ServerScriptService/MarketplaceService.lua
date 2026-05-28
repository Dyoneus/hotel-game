-- Server-side Marketplace foundation.
-- Patch 1C supports seller-owned create/cancel/listing escrow only. Public
-- browsing, purchases, Coins movement, and global marketplace DataStores are
-- still intentionally deferred. Future purchase patches must use idempotent
-- transaction records because buying touches listing state, buyer inventory,
-- buyer Coins, and seller proceeds.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RoomPersistence = require(ServerScriptService:WaitForChild("RoomPersistence"))
local FurnitureCatalogConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FurnitureCatalogConfig"))

local MarketplaceService = {}

MarketplaceService.MARKETPLACE_CURRENCY_KEY = "Coins"
MarketplaceService.MIN_UNIT_PRICE_COINS = 1
MarketplaceService.MAX_UNIT_PRICE_COINS = 999999
MarketplaceService.MAX_LISTING_QUANTITY = 99
MarketplaceService.MAX_ACTIVE_LISTINGS_PER_PLAYER = 50

MarketplaceService.STATUS_ACTIVE = "Active"
MarketplaceService.STATUS_RESERVED = "Reserved"
MarketplaceService.STATUS_SOLD = "Sold"
MarketplaceService.STATUS_CANCELLED = "Cancelled"
MarketplaceService.STATUS_EXPIRED = "Expired"

local LISTINGS_DISABLED_MESSAGE = "Marketplace listings are not enabled yet."

local function trimString(value)
	if typeof(value) ~= "string" then
		return nil
	end

	return value:match("^%s*(.-)%s*$") or ""
end

local function isPositiveInteger(value)
	return typeof(value) == "number"
		and value == value
		and value > 0
		and value < math.huge
		and value == math.floor(value)
end

local function normalizePositiveInteger(value)
	if typeof(value) == "string" then
		local trimmed = trimString(value)

		if not trimmed or trimmed == "" then
			return nil
		end

		value = tonumber(trimmed)
	end

	if not isPositiveInteger(value) then
		return nil
	end

	return math.floor(value)
end

local function normalizeTemplateId(templateId)
	local normalized = trimString(templateId)

	if not normalized or normalized == "" then
		return nil
	end

	return normalized
end

local function normalizeListingQuantity(quantity)
	local normalizedQuantity = normalizePositiveInteger(quantity)

	if not normalizedQuantity or normalizedQuantity > MarketplaceService.MAX_LISTING_QUANTITY then
		return nil
	end

	return normalizedQuantity
end

local function normalizeUnitPriceCoins(unitPriceCoins)
	local normalizedUnitPriceCoins = normalizePositiveInteger(unitPriceCoins)

	if not normalizedUnitPriceCoins
		or normalizedUnitPriceCoins < MarketplaceService.MIN_UNIT_PRICE_COINS
		or normalizedUnitPriceCoins > MarketplaceService.MAX_UNIT_PRICE_COINS then

		return nil
	end

	return normalizedUnitPriceCoins
end

local function getLoadedProfile(player)
	if typeof(RoomPersistence.GetProfile) ~= "function" then
		return nil
	end

	return RoomPersistence.GetProfile(player)
end

local function getCatalogItem(templateId)
	local item = FurnitureCatalogConfig.GetItem(templateId)

	if not item then
		return nil
	end

	local normalizedTemplateId = item.TemplateName or item.Id

	if typeof(normalizedTemplateId) ~= "string" or normalizedTemplateId == "" then
		return nil
	end

	return item, normalizedTemplateId
end

local function playerIsValid(player)
	return typeof(player) == "Instance"
		and player:IsA("Player")
		and player.Parent == Players
end

local function getTradableCount(details)
	if typeof(details) ~= "table" then
		return 0
	end

	return typeof(details.Tradable) == "number"
		and math.max(math.floor(details.Tradable), 0)
		or 0
end

local function countActiveListings(listings)
	local count = 0

	if typeof(listings) ~= "table" then
		return count
	end

	for _, listing in pairs(listings) do
		if typeof(listing) == "table" and listing.Status == MarketplaceService.STATUS_ACTIVE then
			count += 1
		end
	end

	return count
end

local function normalizeListingId(listingId)
	local normalized = trimString(listingId)

	if not normalized or normalized == "" then
		return nil
	end

	return normalized
end

function MarketplaceService.PlayerCanListItem(player, templateId, quantity)
	if not playerIsValid(player) then
		return false, "Invalid player.", nil
	end

	local normalizedTemplateId = normalizeTemplateId(templateId)

	if not normalizedTemplateId then
		return false, "Invalid item.", nil
	end

	local normalizedQuantity = normalizePositiveInteger(quantity)

	if not normalizedQuantity then
		return false, "Invalid quantity.", nil
	end

	if not getLoadedProfile(player) then
		return false, "Profile is not loaded.", nil
	end

	local detailsSnapshot = RoomPersistence.GetInventoryDetailsSnapshot(player)
	local details = detailsSnapshot[normalizedTemplateId]
	local tradableCount = getTradableCount(details)

	if tradableCount < normalizedQuantity then
		return false, "You do not have enough tradable copies to list.", details
	end

	return true, "Item can be listed.", details
end

function MarketplaceService.ValidateListingRequest(player, templateId, quantity, unitPriceCoins)
	if not playerIsValid(player) then
		return false, "Invalid player.", nil
	end

	local requestedTemplateId = normalizeTemplateId(templateId)

	if not requestedTemplateId then
		return false, "Invalid item.", nil
	end

	local normalizedQuantity = normalizePositiveInteger(quantity)

	if not normalizedQuantity then
		return false, "Invalid quantity.", nil
	end

	if normalizedQuantity > MarketplaceService.MAX_LISTING_QUANTITY then
		return false, "Quantity is too high.", nil
	end

	local normalizedUnitPriceCoins = normalizePositiveInteger(unitPriceCoins)

	if not normalizedUnitPriceCoins then
		return false, "Invalid Coin price.", nil
	end

	if normalizedUnitPriceCoins < MarketplaceService.MIN_UNIT_PRICE_COINS
		or normalizedUnitPriceCoins > MarketplaceService.MAX_UNIT_PRICE_COINS then

		return false, "Coin price is out of range.", nil
	end

	local item, normalizedTemplateId = getCatalogItem(requestedTemplateId)

	if not item then
		return false, "Unknown inventory item.", nil
	end

	if not getLoadedProfile(player) then
		return false, "Profile is not loaded.", nil
	end

	local canList, canListMessage, details =
		MarketplaceService.PlayerCanListItem(player, normalizedTemplateId, normalizedQuantity)

	if not canList then
		return false, canListMessage or "Item cannot be listed.", {
			Item = item,
			TemplateId = normalizedTemplateId,
			Quantity = normalizedQuantity,
			UnitPriceCoins = normalizedUnitPriceCoins,
			InventoryDetails = details,
		}
	end

	return true, "Listing request is valid.", {
		Item = item,
		TemplateId = normalizedTemplateId,
		Quantity = normalizedQuantity,
		UnitPriceCoins = normalizedUnitPriceCoins,
		CurrencyKey = MarketplaceService.MARKETPLACE_CURRENCY_KEY,
		InventoryDetails = details,
	}
end

function MarketplaceService.GenerateListingId(sellerUserId)
	local normalizedSellerUserId = normalizePositiveInteger(sellerUserId) or 0
	local guid = HttpService:GenerateGUID(false)

	return tostring(normalizedSellerUserId)
		.. "-"
		.. tostring(os.time())
		.. "-"
		.. guid
end

function MarketplaceService.BuildListingRecord(sellerUserId, templateId, quantity, unitPriceCoins)
	local normalizedSellerUserId = normalizePositiveInteger(sellerUserId)
	local normalizedTemplateId = normalizeTemplateId(templateId)
	local normalizedQuantity = normalizeListingQuantity(quantity)
	local normalizedUnitPriceCoins = normalizeUnitPriceCoins(unitPriceCoins)

	if not normalizedSellerUserId
		or not normalizedTemplateId
		or not normalizedQuantity
		or not normalizedUnitPriceCoins then

		return nil
	end

	local now = os.time()

	return {
		ListingId = MarketplaceService.GenerateListingId(normalizedSellerUserId),
		SellerUserId = normalizedSellerUserId,
		TemplateId = normalizedTemplateId,
		Quantity = normalizedQuantity,
		UnitPriceCoins = normalizedUnitPriceCoins,
		CurrencyKey = MarketplaceService.MARKETPLACE_CURRENCY_KEY,
		Status = MarketplaceService.STATUS_ACTIVE,
		CreatedAt = now,
		UpdatedAt = now,
		ExpiresAt = nil,
		BuyerUserId = nil,
		TransactionId = nil,
	}
end

function MarketplaceService.GetPublicListingSnapshot(listing)
	if typeof(listing) ~= "table" then
		return nil
	end

	return {
		ListingId = listing.ListingId,
		SellerUserId = listing.SellerUserId,
		TemplateId = listing.TemplateId,
		Quantity = listing.Quantity,
		UnitPriceCoins = listing.UnitPriceCoins,
		CurrencyKey = listing.CurrencyKey or MarketplaceService.MARKETPLACE_CURRENCY_KEY,
		Status = listing.Status,
		CreatedAt = listing.CreatedAt,
		ExpiresAt = listing.ExpiresAt,
	}
end

function MarketplaceService.GetListingTotalPrice(listingOrQuantity, unitPriceCoins)
	local quantity = nil
	local price = nil

	if typeof(listingOrQuantity) == "table" then
		quantity = normalizeListingQuantity(listingOrQuantity.Quantity)
		price = normalizeUnitPriceCoins(listingOrQuantity.UnitPriceCoins)
	else
		quantity = normalizeListingQuantity(listingOrQuantity)
		price = normalizeUnitPriceCoins(unitPriceCoins)
	end

	if not quantity or not price then
		return nil
	end

	local total = quantity * price

	if total ~= total or total <= 0 or total >= math.huge or total ~= math.floor(total) then
		return nil
	end

	return total
end

function MarketplaceService.CreateListing(player, templateId, quantity, unitPriceCoins)
	local valid, validationMessage, listingData =
		MarketplaceService.ValidateListingRequest(player, templateId, quantity, unitPriceCoins)

	if not valid then
		return false, validationMessage or "Invalid listing request."
	end

	local listings = RoomPersistence.GetMarketplaceListingsSnapshot(player)

	if countActiveListings(listings) >= MarketplaceService.MAX_ACTIVE_LISTINGS_PER_PLAYER then
		return false, "You have too many active marketplace listings."
	end

	local removed, removeMessage, _, inventoryDetails =
		RoomPersistence.RemoveMarketplaceListableInventoryItem(
			player,
			listingData.TemplateId,
			listingData.Quantity
		)

	if not removed then
		return false, removeMessage or "Could not escrow item for listing.", nil, inventoryDetails
	end

	local listingRecord = MarketplaceService.BuildListingRecord(
		player.UserId,
		listingData.TemplateId,
		listingData.Quantity,
		listingData.UnitPriceCoins
	)

	if not listingRecord then
		RoomPersistence.ReturnMarketplaceListableInventoryItem(
			player,
			listingData.TemplateId,
			listingData.Quantity
		)

		return false, "Could not create marketplace listing.", nil, inventoryDetails
	end

	local added, addMessage = RoomPersistence.AddMarketplaceListing(player, listingRecord)

	if not added then
		local returned, _, _, returnDetails =
			RoomPersistence.ReturnMarketplaceListableInventoryItem(
				player,
				listingData.TemplateId,
				listingData.Quantity
			)

		return false,
			addMessage or "Could not save marketplace listing.",
			nil,
			returned and returnDetails or inventoryDetails
	end

	return true,
		"Marketplace listing created.",
		MarketplaceService.GetPublicListingSnapshot(listingRecord),
		inventoryDetails
end

function MarketplaceService.CancelListing(player, listingId)
	if not playerIsValid(player) then
		return false, "Invalid player."
	end

	if not getLoadedProfile(player) then
		return false, "Profile is not loaded."
	end

	local normalizedListingId = normalizeListingId(listingId)

	if not normalizedListingId then
		return false, "Invalid marketplace listing."
	end

	local listing = RoomPersistence.GetMarketplaceListing(player, normalizedListingId)

	if not listing then
		return false, "Marketplace listing not found."
	end

	if listing.SellerUserId ~= player.UserId then
		return false, "Only the seller can cancel this listing."
	end

	if listing.Status ~= MarketplaceService.STATUS_ACTIVE then
		return false, "This listing is no longer active."
	end

	local updated, updateMessage =
		RoomPersistence.UpdateMarketplaceListing(player, normalizedListingId, {
			Status = MarketplaceService.STATUS_CANCELLED,
		})

	if not updated then
		return false, updateMessage or "Could not cancel marketplace listing."
	end

	local returned, returnMessage, _, inventoryDetails =
		RoomPersistence.ReturnMarketplaceListableInventoryItem(
			player,
			listing.TemplateId,
			listing.Quantity,
			{
				ReturnSellable = listing.ReturnSellable,
			}
		)

	if not returned then
		RoomPersistence.UpdateMarketplaceListing(player, normalizedListingId, {
			Status = MarketplaceService.STATUS_ACTIVE,
		})

		return false, returnMessage or "Could not return listed item.", nil, inventoryDetails
	end

	local cancelledListing = RoomPersistence.GetMarketplaceListing(player, normalizedListingId) or listing

	return true,
		"Marketplace listing cancelled.",
		MarketplaceService.GetPublicListingSnapshot(cancelledListing),
		inventoryDetails
end

function MarketplaceService.GetMyListings(player)
	if not playerIsValid(player) then
		return false, "Invalid player.", {}
	end

	if not getLoadedProfile(player) then
		return false, "Profile is not loaded.", {}
	end

	local listings = RoomPersistence.GetMarketplaceListingsSnapshot(player)
	local snapshots = {}

	for _, listing in pairs(listings) do
		local snapshot = MarketplaceService.GetPublicListingSnapshot(listing)

		if snapshot then
			table.insert(snapshots, snapshot)
		end
	end

	table.sort(snapshots, function(a, b)
		return (a.CreatedAt or 0) > (b.CreatedAt or 0)
	end)

	return true, "Marketplace listings loaded.", snapshots
end

function MarketplaceService.GetPublicListings(player, filters)
	return false, LISTINGS_DISABLED_MESSAGE, {}
end

function MarketplaceService.PurchaseListing(player, listingId)
	return false, "Marketplace purchases are not enabled yet."
end

return MarketplaceService
