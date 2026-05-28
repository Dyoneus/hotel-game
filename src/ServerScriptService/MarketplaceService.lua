-- Server-side Marketplace foundation.
-- Patch 1E supports seller-owned listing escrow plus read-only public browsing
-- from currently loaded player profiles. Purchases, Coins movement, buyer
-- inventory transfer, seller proceeds, and global marketplace DataStores are
-- intentionally deferred. Future purchase patches must use idempotent
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

local PURCHASES_DISABLED_MESSAGE = "Marketplace purchases are not enabled yet."
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

	local success, resultSuccess, resultMessage, resultListing, resultInventoryDetails =
		pcall(callback)

	finishMarketplaceMutation(player)

	if not success then
		warn("Marketplace mutation failed:", resultSuccess)
		return false, "Marketplace request failed."
	end

	return resultSuccess, resultMessage, resultListing, resultInventoryDetails
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
		Escrowed = true,
		ReturnTradable = true,
		ReturnSellable = true,
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
		Escrowed = listing.Escrowed == true,
		LegacyNoEscrow = listing.LegacyNoEscrow == true,
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
		local valid, validationMessage, listingData =
			MarketplaceService.ValidateListingRequest(player, templateId, quantity, unitPriceCoins)

		if not valid then
			return false, validationMessage or "Invalid listing request."
		end

		local listings = RoomPersistence.GetMarketplaceListingsSnapshot(player)

		if countActiveListings(listings) >= MarketplaceService.MAX_ACTIVE_LISTINGS_PER_PLAYER then
			return false, "You have too many active marketplace listings."
		end

		local beforeDetails = getInventoryDetailsForTemplate(player, listingData.TemplateId)
		local beforeTradable = getTradableCount(beforeDetails)

		if beforeTradable < listingData.Quantity then
			return false, "You do not have enough tradable copies to list."
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

			return false,
				"Marketplace escrow failed. Please try again.",
				nil,
				returned and returnDetails or afterDetails
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

			return false,
				"Could not create marketplace listing.",
				nil,
				returned and returnDetails or inventoryDetails
		end

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

			return false,
				addMessage or "Could not save marketplace listing.",
				nil,
				returned and returnDetails or restoredDetails
		end

		return true,
			"Marketplace listing created.",
			MarketplaceService.GetPublicListingSnapshot(listingRecord),
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

	-- Patch 1E reads active listings from currently loaded profiles only.
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

function MarketplaceService.PurchaseListing(player, listingId)
	return false, PURCHASES_DISABLED_MESSAGE
end

Players.PlayerRemoving:Connect(function(player)
	marketplaceMutationLocksByUserId[player.UserId] = nil
end)

return MarketplaceService
