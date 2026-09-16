-- Server-side Marketplace foundation.
-- Patch 1F supports seller-owned listing escrow, read-only public browsing,
-- and same-server purchases while buyer and seller profiles are loaded.
-- Global marketplace DataStores, cross-server/offline seller purchases, taxes,
-- and claim/proceeds flows are intentionally deferred.

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

local marketplaceMutationLocksByUserId = {}

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

local function isFiniteInteger(value)
	return typeof(value) == "number"
		and value == value
		and value > -math.huge
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

local function normalizeUserId(userId)
	if typeof(userId) == "string" then
		local trimmed = trimString(userId)

		if not trimmed or trimmed == "" then
			return nil
		end

		userId = tonumber(trimmed)
	end

	if not isFiniteInteger(userId) then
		return nil
	end

	return math.floor(userId)
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

local function getInventoryDetailsForTemplate(player, templateId)
	local detailsSnapshot = RoomPersistence.GetInventoryDetailsSnapshot(player)
	local details = detailsSnapshot[templateId]

	if typeof(details) == "table" then
		return details
	end

	return {
		Total = 0,
		Tradable = 0,
		Untradable = 0,
		Sellable = 0,
		Unsellable = 0,
	}
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

local function beginMarketplaceMutation(player)
	if not playerIsValid(player) then
		return false, "Invalid player."
	end

	local userId = player.UserId

	if marketplaceMutationLocksByUserId[userId] then
		return false, "Marketplace is busy. Please try again."
	end

	marketplaceMutationLocksByUserId[userId] = true
	return true, nil
end

local function finishMarketplaceMutation(player)
	if player and typeof(player.UserId) == "number" then
		marketplaceMutationLocksByUserId[player.UserId] = nil
	end
end

local function runMarketplaceMutation(player, callback)
	local locked, lockMessage = beginMarketplaceMutation(player)

	if not locked then
		return false, lockMessage
	end

	local success,
		resultSuccess,
		resultMessage,
		resultListing,
		resultInventoryDetails,
		resultNewCurrencyBalance,
		resultExtra =
		pcall(callback)

	finishMarketplaceMutation(player)

	if not success then
		warn("Marketplace mutation failed:", resultSuccess)
		return false, "Marketplace request failed."
	end

	return resultSuccess,
		resultMessage,
		resultListing,
		resultInventoryDetails,
		resultNewCurrencyBalance,
		resultExtra
end

local function beginMarketplaceMutations(playersToLock)
	local uniqueByUserId = {}
	local lockList = {}

	for _, player in ipairs(playersToLock) do
		if not playerIsValid(player) then
			return false, "Invalid player.", nil
		end

		if not uniqueByUserId[player.UserId] then
			uniqueByUserId[player.UserId] = player
			table.insert(lockList, player)
		end
	end

	table.sort(lockList, function(a, b)
		return a.UserId < b.UserId
	end)

	local lockedPlayers = {}

	for _, player in ipairs(lockList) do
		local locked, lockMessage = beginMarketplaceMutation(player)

		if not locked then
			for _, lockedPlayer in ipairs(lockedPlayers) do
				finishMarketplaceMutation(lockedPlayer)
			end

			return false, lockMessage or "Marketplace is busy. Please try again.", nil
		end

		table.insert(lockedPlayers, player)
	end

	return true, nil, lockedPlayers
end

local function finishMarketplaceMutations(lockedPlayers)
	if typeof(lockedPlayers) ~= "table" then
		return
	end

	for _, player in ipairs(lockedPlayers) do
		finishMarketplaceMutation(player)
	end
end

local function findLoadedSellerListing(listingId)
	for _, sellerPlayer in ipairs(Players:GetPlayers()) do
		if getLoadedProfile(sellerPlayer) then
			local listing = RoomPersistence.GetMarketplaceListing(sellerPlayer, listingId)

			if typeof(listing) == "table" then
				return sellerPlayer, listing
			end
		end
	end

	return nil, nil
end

local function generateTransactionId(sellerUserId, buyerUserId)
	return tostring(sellerUserId)
		.. "-"
		.. tostring(buyerUserId)
		.. "-"
		.. tostring(os.time())
		.. "-"
		.. HttpService:GenerateGUID(false)
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

	if tradableCount <= 0
		and typeof(details) == "table"
		and typeof(details.Total) == "number"
		and details.Total > 0 then

		return false, "This item is untradable and cannot be listed.", details
	end

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
	local normalizedSellerUserId = normalizeUserId(sellerUserId) or 0
	local guid = HttpService:GenerateGUID(false)

	return tostring(normalizedSellerUserId)
		.. "-"
		.. tostring(os.time())
		.. "-"
		.. guid
end

function MarketplaceService.BuildListingRecord(sellerUserId, templateId, quantity, unitPriceCoins)
	local normalizedSellerUserId = normalizeUserId(sellerUserId)
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
		SoldAt = listing.SoldAt,
		ExpiresAt = listing.ExpiresAt,
		BuyerUserId = listing.BuyerUserId,
		Escrowed = listing.Escrowed == true,
		LegacyNoEscrow = listing.LegacyNoEscrow == true,
	}
end

local function getListingCatalogMetadata(templateId)
	local displayName = templateId
	local category = nil
	local item = getCatalogItem(templateId)

	if item then
		if typeof(item.DisplayName) == "string" and item.DisplayName ~= "" then
			displayName = item.DisplayName
		end

		if typeof(item.Category) == "string" and item.Category ~= "" then
			category = item.Category
		end
	end

	return displayName, category
end

local function getListingCatalogGroupMetadata(templateId)
	local displayName, category = getListingCatalogMetadata(templateId)
	local description = ""
	local item = getCatalogItem(templateId)

	if item and typeof(item.Description) == "string" then
		description = item.Description
	end

	return displayName, description, category
end

local function getSoldUnitPriceForAverage(listing)
	if typeof(listing) ~= "table" or listing.Status ~= MarketplaceService.STATUS_SOLD then
		return nil
	end

	if typeof(listing.SoldAt) ~= "number" or listing.SoldAt <= 0 then
		return nil
	end

	local soldUnitPrice = normalizeUnitPriceCoins(listing.SoldUnitPriceCoins)

	if soldUnitPrice then
		return soldUnitPrice
	end

	local soldTotal = normalizePositiveInteger(listing.SoldTotalCoins)
	local quantity = normalizeListingQuantity(listing.Quantity)

	if soldTotal and quantity and soldTotal % quantity == 0 then
		local unitPrice = soldTotal / quantity

		if normalizeUnitPriceCoins(unitPrice) then
			return unitPrice
		end
	end

	return normalizeUnitPriceCoins(listing.UnitPriceCoins)
end

function MarketplaceService.GetMyListingSnapshot(listing)
	if typeof(listing) ~= "table" then
		return nil
	end

	local displayName, category = getListingCatalogMetadata(listing.TemplateId)
	local legacyPaid = listing.Status == MarketplaceService.STATUS_SOLD
		and listing.ProceedsClaimed == nil
		and listing.ClaimableCoins == nil
	local proceedsClaimed = listing.ProceedsClaimed == true or legacyPaid == true

	return {
		ListingId = listing.ListingId,
		TemplateId = listing.TemplateId,
		DisplayName = displayName,
		Category = category,
		Quantity = listing.Quantity,
		UnitPriceCoins = listing.UnitPriceCoins,
		CurrencyKey = listing.CurrencyKey or MarketplaceService.MARKETPLACE_CURRENCY_KEY,
		Status = listing.Status,
		CreatedAt = listing.CreatedAt,
		UpdatedAt = listing.UpdatedAt,
		SoldAt = listing.SoldAt,
		BuyerUserId = listing.BuyerUserId,
		SoldUnitPriceCoins = listing.SoldUnitPriceCoins,
		SoldTotalCoins = listing.SoldTotalCoins,
		ClaimableCoins = listing.ClaimableCoins,
		ProceedsClaimed = proceedsClaimed,
		ClaimedAt = listing.ClaimedAt,
		LegacyPaid = legacyPaid or nil,
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
	return runMarketplaceMutation(player, function()
		local function failCreateListing(stage, reason, inventoryDetails)
			local failureReason = tostring(reason or "Unknown error.")

			warn("[MarketplaceService] CreateListing failed stage=" .. stage .. " reason=" .. failureReason)

			return false,
				"CreateListing failed at " .. stage .. ": " .. failureReason,
				nil,
				inventoryDetails
		end

		local valid, validationMessage, listingData =
			MarketplaceService.ValidateListingRequest(player, templateId, quantity, unitPriceCoins)

		if not valid then
			local validationDetails = typeof(listingData) == "table"
				and listingData.InventoryDetails
				or nil

			return failCreateListing(
				"ValidateListingRequest",
				validationMessage or "Invalid listing request.",
				validationDetails
			)
		end

		local listings = RoomPersistence.GetMarketplaceListingsSnapshot(player)

		if countActiveListings(listings) >= MarketplaceService.MAX_ACTIVE_LISTINGS_PER_PLAYER then
			return failCreateListing(
				"ActiveListingCountCheck",
				"You have too many active marketplace listings.",
				listingData.InventoryDetails
			)
		end

		local beforeDetails = getInventoryDetailsForTemplate(player, listingData.TemplateId)
		local beforeTradable = getTradableCount(beforeDetails)

		if beforeTradable < listingData.Quantity then
			local notEnoughMessage = "You do not have enough tradable copies to list."

			if beforeTradable <= 0
				and typeof(beforeDetails.Total) == "number"
				and beforeDetails.Total > 0 then

				notEnoughMessage = "This item is untradable and cannot be listed."
			end

			return failCreateListing(
				"ActiveListingCountCheck",
				notEnoughMessage,
				beforeDetails
			)
		end

		local removed, removeMessage, _, inventoryDetails =
			RoomPersistence.RemoveMarketplaceListableInventoryItem(
				player,
				listingData.TemplateId,
				listingData.Quantity
			)

		if not removed then
			return failCreateListing(
				"RemoveEscrowInventory",
				removeMessage or "Could not escrow item for listing.",
				inventoryDetails
			)
		end

		local afterDetails = typeof(inventoryDetails) == "table"
			and inventoryDetails
			or getInventoryDetailsForTemplate(player, listingData.TemplateId)
		local afterTradable = getTradableCount(afterDetails)

		if afterTradable ~= beforeTradable - listingData.Quantity
			or afterTradable >= beforeTradable then

			warn(
				"Marketplace CreateListing escrow verification failed",
				"player=", player.UserId,
				"templateId=", listingData.TemplateId,
				"oldTradable=", beforeTradable,
				"quantity=", listingData.Quantity,
				"afterTradable=", afterTradable,
				"expectedAfterTradable=", beforeTradable - listingData.Quantity
			)

			local returned, _, _, returnDetails =
				RoomPersistence.ReturnMarketplaceListableInventoryItem(
					player,
					listingData.TemplateId,
					listingData.Quantity,
					{
						ReturnTradable = true,
						ReturnSellable = true,
					}
				)

			return failCreateListing(
				"RemoveEscrowInventory",
				"Marketplace escrow failed. Please try again.",
				returned and returnDetails or afterDetails
			)
		end

		inventoryDetails = afterDetails

		local listingRecord = MarketplaceService.BuildListingRecord(
			player.UserId,
			listingData.TemplateId,
			listingData.Quantity,
			listingData.UnitPriceCoins
		)

		if not listingRecord then
			local returned, _, _, returnDetails =
				RoomPersistence.ReturnMarketplaceListableInventoryItem(
					player,
					listingData.TemplateId,
					listingData.Quantity,
					{
						ReturnTradable = true,
						ReturnSellable = true,
					}
				)

			return failCreateListing(
				"BuildListingRecord",
				"Could not build marketplace listing record.",
				returned and returnDetails or inventoryDetails
			)
		end

		listingRecord.Escrowed = true
		listingRecord.ReturnTradable = true
		listingRecord.ReturnSellable = true

		local added, addMessage = RoomPersistence.AddMarketplaceListing(player, listingRecord)

		if not added then
			local returned, _, _, returnDetails =
				RoomPersistence.ReturnMarketplaceListableInventoryItem(
					player,
					listingData.TemplateId,
					listingData.Quantity,
					{
						ReturnTradable = listingRecord.ReturnTradable,
						ReturnSellable = listingRecord.ReturnSellable,
					}
				)
			local restoredDetails = getInventoryDetailsForTemplate(player, listingData.TemplateId)

			if getTradableCount(restoredDetails) < beforeTradable then
				warn(
					"Marketplace listing save failed and escrow rollback did not restore tradable inventory for",
					player.UserId,
					listingData.TemplateId
				)
			end

			return failCreateListing(
				"AddMarketplaceListing",
				addMessage or "Could not save marketplace listing.",
				returned and returnDetails or restoredDetails
			)
		end

		local listingSnapshot = MarketplaceService.GetPublicListingSnapshot(listingRecord)

		if not listingSnapshot then
			local cancelled, _, _, returnDetails =
				RoomPersistence.CancelMarketplaceListingWithEscrowReturn(
					player,
					listingRecord.ListingId,
					player.UserId
				)

			return failCreateListing(
				"BuildPublicSnapshot",
				"Could not build marketplace listing snapshot.",
				cancelled and returnDetails or inventoryDetails
			)
		end

		return true,
			"Marketplace listing created.",
			listingSnapshot,
			inventoryDetails
	end)
end

function MarketplaceService.CancelListing(player, listingId)
	return runMarketplaceMutation(player, function()
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

		if listing.Escrowed ~= true then
			local legacyCancelled, legacyMessage, legacyListing =
				RoomPersistence.CancelLegacyMarketplaceListingWithoutEscrowReturn(
					player,
					normalizedListingId,
					player.UserId
				)

			if not legacyCancelled then
				return false, legacyMessage or "Could not cancel legacy marketplace listing."
			end

			return true,
				"Legacy marketplace listing cancelled.",
				MarketplaceService.GetPublicListingSnapshot(legacyListing),
				nil
		end

		local cancelled, cancelMessage, cancelledListing, inventoryDetails =
			RoomPersistence.CancelMarketplaceListingWithEscrowReturn(
				player,
				normalizedListingId,
				player.UserId
			)

		if not cancelled then
			return false, cancelMessage or "Could not cancel marketplace listing.", nil, inventoryDetails
		end

		return true,
			"Marketplace listing cancelled.",
			MarketplaceService.GetPublicListingSnapshot(cancelledListing),
			inventoryDetails
	end)
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
		local snapshot = MarketplaceService.GetMyListingSnapshot(listing)

		if snapshot then
			table.insert(snapshots, snapshot)
		end
	end

	table.sort(snapshots, function(a, b)
		local aSort = a.UpdatedAt or a.CreatedAt or 0
		local bSort = b.UpdatedAt or b.CreatedAt or 0

		if aSort == bSort then
			return tostring(a.ListingId or "") > tostring(b.ListingId or "")
		end

		return aSort > bSort
	end)

	return true, "Marketplace listings loaded.", snapshots
end

local function getPublicListingFilterValue(filters, key)
	if typeof(filters) ~= "table" then
		return nil
	end

	local value = trimString(filters[key])

	if not value or value == "" then
		return nil
	end

	return value
end

local function getPublicListingMaxResults(filters)
	local maxResults = 50

	if typeof(filters) == "table" and typeof(filters.MaxResults) == "number" then
		if filters.MaxResults == filters.MaxResults and filters.MaxResults > 0 then
			maxResults = math.floor(filters.MaxResults)
		end
	end

	return math.clamp(maxResults, 1, 100)
end

local function publicListingMatchesSearch(snapshot, searchText)
	if not searchText then
		return true
	end

	local needle = string.lower(searchText)
	local values = {
		snapshot.TemplateId,
		snapshot.DisplayName,
		snapshot.Category,
		snapshot.SellerName,
		snapshot.SellerDisplayName,
	}

	for _, value in ipairs(values) do
		if typeof(value) == "string" and string.find(string.lower(value), needle, 1, true) then
			return true
		end
	end

	return false
end

local function marketplaceOfferGroupMatchesSearch(group, searchText)
	if not searchText then
		return true
	end

	local needle = string.lower(searchText)
	local values = {
		group.TemplateId,
		group.DisplayName,
		group.Description,
		group.Category,
	}

	for _, value in ipairs(values) do
		if typeof(value) == "string" and string.find(string.lower(value), needle, 1, true) then
			return true
		end
	end

	return false
end

local function isActiveEscrowedListing(listing)
	return typeof(listing) == "table"
		and listing.Status == MarketplaceService.STATUS_ACTIVE
		and listing.Escrowed == true
		and listing.CurrencyKey == MarketplaceService.MARKETPLACE_CURRENCY_KEY
		and normalizeTemplateId(listing.TemplateId) ~= nil
		and normalizeUnitPriceCoins(listing.UnitPriceCoins) ~= nil
		and normalizeListingId(listing.ListingId) ~= nil
end

local function listingSortsBefore(firstListing, secondListing)
	if not secondListing then
		return true
	end

	local firstPrice = normalizeUnitPriceCoins(firstListing.UnitPriceCoins) or math.huge
	local secondPrice = normalizeUnitPriceCoins(secondListing.UnitPriceCoins) or math.huge

	if firstPrice ~= secondPrice then
		return firstPrice < secondPrice
	end

	local firstCreatedAt = typeof(firstListing.CreatedAt) == "number" and firstListing.CreatedAt or math.huge
	local secondCreatedAt = typeof(secondListing.CreatedAt) == "number" and secondListing.CreatedAt or math.huge

	if firstCreatedAt ~= secondCreatedAt then
		return firstCreatedAt < secondCreatedAt
	end

	return tostring(firstListing.ListingId or "") < tostring(secondListing.ListingId or "")
end

local function findLowestLoadedListingForTemplate(templateId, buyerPlayer)
	local normalizedTemplateId = normalizeTemplateId(templateId)

	if not normalizedTemplateId then
		return nil, nil, nil, "Invalid marketplace item."
	end

	local lowestOwnSeller = nil
	local lowestOwnListing = nil
	local lowestSeller = nil
	local lowestListing = nil
	local sawOwnListing = false

	for _, sellerPlayer in ipairs(Players:GetPlayers()) do
		if getLoadedProfile(sellerPlayer) then
			local sellerListings = RoomPersistence.GetMarketplaceListingsSnapshot(sellerPlayer)

			for _, listing in pairs(sellerListings) do
				if isActiveEscrowedListing(listing) and listing.TemplateId == normalizedTemplateId then
					local isOwnListing = buyerPlayer and listing.SellerUserId == buyerPlayer.UserId

					if isOwnListing then
						sawOwnListing = true

						if listingSortsBefore(listing, lowestOwnListing) then
							lowestOwnSeller = sellerPlayer
							lowestOwnListing = listing
						end
					elseif listingSortsBefore(listing, lowestListing) then
						lowestSeller = sellerPlayer
						lowestListing = listing
					end
				end
			end
		end
	end

	if lowestSeller and lowestListing then
		return lowestSeller, lowestListing, false, nil
	end

	if lowestOwnSeller and lowestOwnListing then
		return lowestOwnSeller, lowestOwnListing, sawOwnListing, "You cannot buy your own listing."
	end

	return nil, nil, sawOwnListing, "This marketplace offer is no longer available."
end

local function getPublicListingSnapshot(requestingPlayer, sellerPlayer, listing)
	if typeof(listing) ~= "table" or listing.Status ~= MarketplaceService.STATUS_ACTIVE then
		return nil
	end

	local item = getCatalogItem(listing.TemplateId)
	local displayName = listing.TemplateId
	local category = nil

	if item then
		if typeof(item.DisplayName) == "string" and item.DisplayName ~= "" then
			displayName = item.DisplayName
		end

		if typeof(item.Category) == "string" and item.Category ~= "" then
			category = item.Category
		end
	end

	return {
		ListingId = listing.ListingId,
		SellerUserId = listing.SellerUserId,
		SellerName = sellerPlayer and sellerPlayer.Name or nil,
		SellerDisplayName = sellerPlayer and sellerPlayer.DisplayName or nil,
		TemplateId = listing.TemplateId,
		DisplayName = displayName,
		Category = category,
		Quantity = listing.Quantity,
		UnitPriceCoins = listing.UnitPriceCoins,
		CurrencyKey = listing.CurrencyKey or MarketplaceService.MARKETPLACE_CURRENCY_KEY,
		Status = listing.Status,
		CreatedAt = listing.CreatedAt,
		IsOwnListing = requestingPlayer and listing.SellerUserId == requestingPlayer.UserId or false,
	}
end

function MarketplaceService.GetPublicListings(player, filters)
	if not playerIsValid(player) then
		return false, "Invalid player.", {}
	end

	if not getLoadedProfile(player) then
		return false, "Profile is not loaded.", {}
	end

	local templateIdFilter = getPublicListingFilterValue(filters, "TemplateId")
	local categoryFilter = getPublicListingFilterValue(filters, "Category")
	local searchText = getPublicListingFilterValue(filters, "SearchText")
	local maxResults = getPublicListingMaxResults(filters)
	local categoryFilterLower = categoryFilter and string.lower(categoryFilter) or nil
	local listings = {}

	-- Patch 1F still reads active listings from currently loaded profiles only.
	-- A true global/cross-server marketplace index belongs in a later patch.
	for _, sellerPlayer in ipairs(Players:GetPlayers()) do
		if getLoadedProfile(sellerPlayer) then
			local sellerListings = RoomPersistence.GetMarketplaceListingsSnapshot(sellerPlayer)

			for _, listing in pairs(sellerListings) do
				local snapshot = getPublicListingSnapshot(player, sellerPlayer, listing)

				if snapshot
					and (not templateIdFilter or snapshot.TemplateId == templateIdFilter)
					and (not categoryFilterLower or string.lower(tostring(snapshot.Category or "")) == categoryFilterLower)
					and publicListingMatchesSearch(snapshot, searchText) then

					table.insert(listings, snapshot)
				end
			end
		end
	end

	table.sort(listings, function(a, b)
		return (a.CreatedAt or 0) > (b.CreatedAt or 0)
	end)

	while #listings > maxResults do
		table.remove(listings)
	end

	return true, "Marketplace listings loaded.", listings
end

function MarketplaceService.GetMarketplaceOfferGroups(player, filters)
	if not playerIsValid(player) then
		return false, "Invalid player.", {}
	end

	if not getLoadedProfile(player) then
		return false, "Profile is not loaded.", {}
	end

	local categoryFilter = getPublicListingFilterValue(filters, "Category")
	local searchText = getPublicListingFilterValue(filters, "SearchText")
	local maxResults = getPublicListingMaxResults(filters)
	local categoryFilterLower = categoryFilter and string.lower(categoryFilter) or nil
	local groupsByTemplateId = {}

	-- This patch intentionally reads currently loaded player profiles only.
	-- A cross-server/offline marketplace index belongs in a later patch.
	for _, sellerPlayer in ipairs(Players:GetPlayers()) do
		if getLoadedProfile(sellerPlayer) then
			local sellerListings = RoomPersistence.GetMarketplaceListingsSnapshot(sellerPlayer)

			for _, listing in pairs(sellerListings) do
				if isActiveEscrowedListing(listing) then
					local templateId = listing.TemplateId
					local group = groupsByTemplateId[templateId]

					if not group then
						local displayName, description, category = getListingCatalogGroupMetadata(templateId)

						group = {
							TemplateId = templateId,
							DisplayName = displayName,
							Description = description,
							Category = category,
							OffersCount = 0,
							LowestListing = nil,
							LowestOwnListing = nil,
							HasOwnListing = false,
							SoldTotal = 0,
							SoldCount = 0,
						}
						groupsByTemplateId[templateId] = group
					end

					group.OffersCount += 1

					if listing.SellerUserId == player.UserId then
						group.HasOwnListing = true

						if listingSortsBefore(listing, group.LowestOwnListing) then
							group.LowestOwnListing = listing
						end
					elseif listingSortsBefore(listing, group.LowestListing) then
						group.LowestListing = listing
					end
				elseif typeof(listing) == "table"
					and listing.Status == MarketplaceService.STATUS_SOLD
					and normalizeTemplateId(listing.TemplateId) then

					local soldUnitPrice = getSoldUnitPriceForAverage(listing)
					local templateId = listing.TemplateId

					if not soldUnitPrice then
						continue
					end

					local group = groupsByTemplateId[templateId]

					if not group then
						local displayName, description, category = getListingCatalogGroupMetadata(templateId)

						group = {
							TemplateId = templateId,
							DisplayName = displayName,
							Description = description,
							Category = category,
							OffersCount = 0,
							LowestListing = nil,
							LowestOwnListing = nil,
							HasOwnListing = false,
							SoldTotal = 0,
							SoldCount = 0,
						}
						groupsByTemplateId[templateId] = group
					end

					group.SoldTotal += soldUnitPrice
					group.SoldCount += 1
				end
			end
		end
	end

	local groups = {}

	for _, group in pairs(groupsByTemplateId) do
		if group.OffersCount > 0 then
			local lowestListing = group.LowestListing or group.LowestOwnListing
			local isOwnOnly = group.LowestListing == nil and group.HasOwnListing == true
			local averageSalePrice = nil

			if group.SoldCount > 0 then
				averageSalePrice = math.floor((group.SoldTotal / group.SoldCount) + 0.5)
			end

			local snapshot = {
				TemplateId = group.TemplateId,
				DisplayName = group.DisplayName,
				Description = group.Description,
				Category = group.Category,
				OffersCount = group.OffersCount,
				LowestUnitPriceCoins = lowestListing and lowestListing.UnitPriceCoins or nil,
				LowestListingId = lowestListing and lowestListing.ListingId or nil,
				AverageSalePriceCoins = averageSalePrice,
				HasOwnListing = group.HasOwnListing == true,
				IsOwnOnly = isOwnOnly,
				CurrencyKey = MarketplaceService.MARKETPLACE_CURRENCY_KEY,
			}

			if (not categoryFilterLower or string.lower(tostring(snapshot.Category or "")) == categoryFilterLower)
				and marketplaceOfferGroupMatchesSearch(snapshot, searchText) then

				table.insert(groups, snapshot)
			end
		end
	end

	table.sort(groups, function(a, b)
		local aPrice = typeof(a.LowestUnitPriceCoins) == "number" and a.LowestUnitPriceCoins or math.huge
		local bPrice = typeof(b.LowestUnitPriceCoins) == "number" and b.LowestUnitPriceCoins or math.huge

		if aPrice ~= bPrice then
			return aPrice < bPrice
		end

		return tostring(a.DisplayName or a.TemplateId or "") < tostring(b.DisplayName or b.TemplateId or "")
	end)

	while #groups > maxResults do
		table.remove(groups)
	end

	return true, "Marketplace offers loaded.", groups
end

function MarketplaceService.PurchaseMarketplaceOffer(player, templateId)
	if not playerIsValid(player) then
		return false, "Invalid player."
	end

	if not getLoadedProfile(player) then
		return false, "Profile is not loaded."
	end

	local _, listing, isOwnOnly, message = findLowestLoadedListingForTemplate(templateId, player)

	if isOwnOnly == true then
		return false, message or "You cannot buy your own listing."
	end

	if not listing then
		return false, message or "This marketplace offer is no longer available."
	end

	return MarketplaceService.PurchaseListing(player, listing.ListingId)
end

function MarketplaceService.PurchaseListing(player, listingId)
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

	local sellerPlayer, listing = findLoadedSellerListing(normalizedListingId)

	if not sellerPlayer or not listing then
		return false, "This listing is not available right now."
	end

	if listing.SellerUserId ~= sellerPlayer.UserId then
		return false, "This listing is not available right now."
	end

	if listing.SellerUserId == player.UserId then
		return false, "You cannot buy your own listing."
	end

	local locked, lockMessage, lockedPlayers = beginMarketplaceMutations({
		player,
		sellerPlayer,
	})

	if not locked then
		return false, lockMessage or "Marketplace is busy. Please try again."
	end

	local ok,
		resultSuccess,
		resultMessage,
		resultListing,
		resultInventoryDetails,
		resultCoinBalance,
		resultSaleInfo =
		pcall(function()
			if not getLoadedProfile(player) or not getLoadedProfile(sellerPlayer) then
				return false, "This listing is not available right now."
			end

			local currentListing = RoomPersistence.GetMarketplaceListing(sellerPlayer, normalizedListingId)

			if not currentListing or currentListing.SellerUserId ~= sellerPlayer.UserId then
				return false, "This listing is not available right now."
			end

			if currentListing.SellerUserId == player.UserId then
				return false, "You cannot buy your own listing."
			end

			if currentListing.Status ~= MarketplaceService.STATUS_ACTIVE
				or currentListing.Escrowed ~= true then

				return false, "This listing is no longer available."
			end

			if currentListing.CurrencyKey ~= MarketplaceService.MARKETPLACE_CURRENCY_KEY then
				return false, "This listing is not available right now."
			end

			local totalPrice = MarketplaceService.GetListingTotalPrice(currentListing)

			if not totalPrice then
				return false, "This listing is not available right now."
			end

			local currentBuyerCoins = RoomPersistence.GetCurrency(
				player,
				MarketplaceService.MARKETPLACE_CURRENCY_KEY
			)

			if typeof(currentBuyerCoins) ~= "number" then
				return false, "Profile is not loaded."
			end

			if currentBuyerCoins < totalPrice then
				return false, "You do not have enough Coins."
			end

			local removedCoins, removeCoinsMessage, buyerCoinBalance =
				RoomPersistence.RemoveCurrency(
					player,
					MarketplaceService.MARKETPLACE_CURRENCY_KEY,
					totalPrice,
					"MarketplacePurchase:" .. normalizedListingId
				)

			if not removedCoins then
				if removeCoinsMessage == "Not enough currency." then
					return false, "You do not have enough Coins."
				end

				return false, removeCoinsMessage or "Could not complete purchase."
			end

			local addedInventory, addInventoryMessage, _, inventoryDetails =
				RoomPersistence.AddInventoryItem(
					player,
					currentListing.TemplateId,
					currentListing.Quantity,
					{
						Tradable = true,
						Sellable = true,
					}
				)

			if not addedInventory then
				local refunded = RoomPersistence.AddCurrency(
					player,
					MarketplaceService.MARKETPLACE_CURRENCY_KEY,
					totalPrice,
					"MarketplacePurchaseInventoryRollback:" .. normalizedListingId
				)

				if not refunded then
					warn("Marketplace purchase failed to refund buyer after inventory add failure", player.UserId, normalizedListingId)
				end

				return false, addInventoryMessage or "Could not deliver purchased item."
			end

			local now = os.time()
			local sold, soldMessage, soldListing =
				RoomPersistence.UpdateMarketplaceListing(
					sellerPlayer,
					normalizedListingId,
					{
						Status = MarketplaceService.STATUS_SOLD,
						Escrowed = false,
						BuyerUserId = player.UserId,
						SoldAt = now,
						SoldUnitPriceCoins = currentListing.UnitPriceCoins,
						SoldTotalCoins = totalPrice,
						ProceedsClaimed = false,
						ClaimableCoins = totalPrice,
						ClaimedAt = false,
						TransactionId = generateTransactionId(sellerPlayer.UserId, player.UserId),
					}
				)

			if not sold then
				local removedInventory = RoomPersistence.RemoveInventoryItem(
					player,
					currentListing.TemplateId,
					currentListing.Quantity,
					{
						ConsumeTradableFirst = true,
					}
				)
				local refunded = RoomPersistence.AddCurrency(
					player,
					MarketplaceService.MARKETPLACE_CURRENCY_KEY,
					totalPrice,
					"MarketplacePurchaseListingRollback:" .. normalizedListingId
				)

				if not removedInventory or not refunded then
					warn("Marketplace purchase rollback failed after listing sale update failure", player.UserId, normalizedListingId)
				end

				return false, soldMessage or "Could not complete purchase."
			end

			return true,
				"Purchase complete.",
				MarketplaceService.GetPublicListingSnapshot(soldListing),
				inventoryDetails,
				buyerCoinBalance,
				{
					SellerPlayer = sellerPlayer,
					SellerUserId = sellerPlayer.UserId,
					TotalCoins = totalPrice,
					TemplateId = currentListing.TemplateId,
					Quantity = currentListing.Quantity,
				}
		end)

	finishMarketplaceMutations(lockedPlayers)

	if not ok then
		warn("Marketplace purchase failed:", resultSuccess)
		return false, "Marketplace request failed."
	end

	return resultSuccess,
		resultMessage,
		resultListing,
		resultInventoryDetails,
		resultCoinBalance,
		resultSaleInfo
end

function MarketplaceService.ClaimSale(player, listingId)
	return runMarketplaceMutation(player, function()
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
			return false, "Only the seller can claim this sale."
		end

		if listing.Status ~= MarketplaceService.STATUS_SOLD then
			return false, "Only sold listings can be claimed."
		end

		if listing.ProceedsClaimed == true then
			return false, "This sale has already been claimed."
		end

		if listing.ProceedsClaimed == nil and listing.ClaimableCoins == nil then
			return false, "This sale has already been claimed."
		end

		if listing.CurrencyKey ~= MarketplaceService.MARKETPLACE_CURRENCY_KEY then
			return false, "This sale cannot be claimed."
		end

		local claimableCoins = normalizePositiveInteger(listing.ClaimableCoins)

		if not claimableCoins then
			return false, "This sale cannot be claimed."
		end

		local now = os.time()
		local markedClaimed, markMessage, markedListing =
			RoomPersistence.UpdateMarketplaceListing(
				player,
				normalizedListingId,
				{
					ProceedsClaimed = true,
					ClaimedAt = now,
				}
			)

		if not markedClaimed then
			return false, markMessage or "Could not claim sale."
		end

		local addedCoins, addCoinsMessage, newCoinBalance =
			RoomPersistence.AddCurrency(
				player,
				MarketplaceService.MARKETPLACE_CURRENCY_KEY,
				claimableCoins,
				"MarketplaceClaim:" .. normalizedListingId
			)

		if not addedCoins then
			RoomPersistence.UpdateMarketplaceListing(
				player,
				normalizedListingId,
				{
					ProceedsClaimed = false,
					ClaimedAt = false,
				}
			)

			return false, addCoinsMessage or "Could not claim sale."
		end

		return true,
			"Sale claimed.",
			MarketplaceService.GetMyListingSnapshot(markedListing),
			nil,
			newCoinBalance,
			{
				ClaimedCoins = claimableCoins,
			}
	end)
end

Players.PlayerRemoving:Connect(function(player)
	marketplaceMutationLocksByUserId[player.UserId] = nil
end)

return MarketplaceService
