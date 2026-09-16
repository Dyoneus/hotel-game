-- ServerScriptService/AdminCommandServer.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

print("[AdminCommandServer] Booting")

local AdminConfig = require(ServerScriptService:WaitForChild("AdminConfig"))
local AdminDataTools = require(ServerScriptService:WaitForChild("AdminDataTools"))
local RoomPersistence = require(ServerScriptService:WaitForChild("RoomPersistence"))

local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")

print("[AdminCommandServer] Script started")

if not remoteEvents then
	remoteEvents = Instance.new("Folder")
	remoteEvents.Name = "RemoteEvents"
	remoteEvents.Parent = ReplicatedStorage
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

local adminCommandRequest = getOrCreateRemoteEvent("AdminCommandRequest")
local adminCommandResult = getOrCreateRemoteEvent("AdminCommandResult")
local inventoryResult = getOrCreateRemoteEvent("InventoryResult")
local currencyResult = getOrCreateRemoteEvent("CurrencyResult")

local MODERATION_TOPIC = "AdminModeration_v1"
local SERVER_ID = game.JobId
local MAX_ADMIN_ITEM_QUANTITY = 999
local MAX_ADMIN_CURRENCY_AMOUNT = 999999999
local STUDIO_ADMIN_OVERRIDE_ENABLED = true

local VALID_ACTIONS = {
	GetAccess = true,
	LookupUser = true,
	ResetProfile = true,
	ExploitBan = true,
	Unban = true,
}

local REQUIRED_CONFIRMATION = {
	ResetProfile = "RESET",
	ExploitBan = "BAN",
	Unban = "UNBAN",
}

local lastRequestAtByUserId = {}
local commandInFlightByUserId = {}
local chatConnectionsByPlayer = {}
local lastChatCommandByUserId = {}
local studioAdminOverrideLoggedByUserId = {}

local function trim(text)
	text = tostring(text or "")
	return text:match("^%s*(.-)%s*$")
end

local function normalizeUserId(value)
	if typeof(value) == "number" then
		if value <= 0 then
			return nil
		end

		return math.floor(value)
	end

	if typeof(value) ~= "string" then
		return nil
	end

	local text = trim(value)

	if not text:match("^%d+$") then
		return nil
	end

	local numberValue = tonumber(text)

	if not numberValue or numberValue <= 0 then
		return nil
	end

	return math.floor(numberValue)
end

local function sanitizeReason(reason)
	if typeof(reason) ~= "string" then
		reason = ""
	end

	reason = reason:gsub("[%c]", " ")
	reason = reason:gsub("%s+", " ")
	reason = trim(reason)

	if #reason > AdminConfig.MAX_REASON_LENGTH then
		reason = reason:sub(1, AdminConfig.MAX_REASON_LENGTH)
	end

	return reason
end

local function sendResult(player, kind, success, message, data, commandName)
	if not player or player.Parent ~= Players then
		return
	end

	adminCommandResult:FireClient(player, {
		Kind = tostring(kind or "Unknown"),
		Success = success == true,
		Message = tostring(message or ""),
		Data = data or {},
		Command = commandName,
	})
end

local function isStudioAdmin(player)
	if not STUDIO_ADMIN_OVERRIDE_ENABLED or not RunService:IsStudio() then
		return false
	end

	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	local isAllowed = player.UserId == 37382153
		or player.Name == "OJY2000"
		or player.Name:sub(1, #"Player") == "Player"

	if isAllowed and not studioAdminOverrideLoggedByUserId[player.UserId] then
		studioAdminOverrideLoggedByUserId[player.UserId] = true
		print("[AdminCommandServer] Studio admin override granted to " .. player.Name)
	end

	return isAllowed
end

local function getStudioAdminPermissions()
	local permissions = {}

	for actionName in pairs(AdminConfig.PERMISSIONS) do
		permissions[actionName] = true
	end

	return permissions
end

local function getAccessPayload(player)
	if isStudioAdmin(player) then
		return {
			IsAdmin = true,
			Rank = 100,
			Permissions = getStudioAdminPermissions(),
			AccessReason = "StudioOverride",
		}
	end

	local rank = AdminConfig.GetRank(player.UserId)

	return {
		IsAdmin = rank > 0,
		Rank = rank,
		Permissions = AdminConfig.GetPermissionsForUser(player.UserId),
		AccessReason = rank > 0 and "AdminConfig" or "None",
	}
end

local function checkAdminAccess(player, actionName)
	if isStudioAdmin(player) then
		return true, nil
	end

	if not AdminConfig.IsAdmin(player.UserId) then
		return false, "Access denied."
	end

	if not AdminConfig.CanRun(player.UserId, actionName) then
		return false, "You do not have permission to run " .. tostring(actionName) .. "."
	end

	return true, nil
end

local function checkTargetAllowed(player, actionName, targetUserId)
	if not targetUserId then
		return false, "Invalid target UserId."
	end

	if AdminConfig.DISALLOW_SELF_MODERATION and targetUserId == player.UserId then
		return false, "You cannot run moderation actions on yourself from this panel."
	end

	if AdminConfig.TargetIsProtected(player.UserId, targetUserId) then
		return false, "You cannot target an admin with equal or higher rank."
	end

	return true, nil
end

local function checkCooldown(player)
	local now = os.clock()
	local previous = lastRequestAtByUserId[player.UserId]

	if previous and now - previous < AdminConfig.RATE_LIMIT_SECONDS then
		return false
	end

	lastRequestAtByUserId[player.UserId] = now

	return true
end

local function sendAdminCommandResult(player, success, message, data, commandName, source)
	sendResult(player, "AdminCommand", success, message, data, commandName)
end

local function sendInventorySnapshot(player, message)
	if not player or player.Parent ~= Players then
		return
	end

	inventoryResult:FireClient(player, {
		Kind = "AdminInventoryUpdate",
		Success = true,
		Inventory = RoomPersistence.GetInventorySnapshot(player),
		InventoryDetails = RoomPersistence.GetInventoryDetailsSnapshot(player),
		Message = tostring(message or "Inventory updated."),
	})
end

local function sendCurrencySnapshot(player, message)
	if not player or player.Parent ~= Players then
		return
	end

	currencyResult:FireClient(player, {
		Kind = "Currencies",
		Success = true,
		Currencies = RoomPersistence.GetCurrenciesSnapshot(player),
		Message = tostring(message or "Currencies updated."),
	})
end

local function splitCommandText(text)
	local args = {}

	for token in tostring(text or ""):gmatch("%S+") do
		table.insert(args, token)
	end

	return args
end

local function parsePositiveInteger(value, maxValue)
	local numberValue = tonumber(value)

	if not numberValue
		or numberValue ~= numberValue
		or numberValue <= 0
		or numberValue >= math.huge
		or numberValue ~= math.floor(numberValue) then

		return nil
	end

	numberValue = math.floor(numberValue)

	if maxValue and numberValue > maxValue then
		return nil
	end

	return numberValue
end

local function parseNonNegativeInteger(value, maxValue)
	local numberValue = tonumber(value)

	if not numberValue
		or numberValue ~= numberValue
		or numberValue < 0
		or numberValue >= math.huge
		or numberValue ~= math.floor(numberValue) then

		return nil
	end

	numberValue = math.floor(numberValue)

	if maxValue and numberValue > maxValue then
		return nil
	end

	return numberValue
end

local function parseTradableFlag(value)
	local normalized = string.lower(trim(value))

	if normalized == "tradable" then
		return true
	end

	if normalized == "untradable" then
		return false
	end

	return nil
end

local function parseSellableFlag(value)
	local normalized = string.lower(trim(value))

	if normalized == "sellable" then
		return true
	end

	if normalized == "unsellable" then
		return false
	end

	return nil
end

local function getInventoryDetailsForTemplate(player, templateId)
	local snapshot = RoomPersistence.GetInventoryDetailsSnapshot(player)
	local details = snapshot[templateId]

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

local function findOnlineTargetPlayer(actorPlayer, targetText)
	local target = trim(targetText)

	if target == "" then
		return nil, "Enter a target player."
	end

	if string.lower(target) == "me" then
		return actorPlayer, nil
	end

	local targetUserId = normalizeUserId(target)

	if targetUserId then
		local player = Players:GetPlayerByUserId(targetUserId)

		if player then
			return player, nil
		end

		return nil, "Target player is not online."
	end

	local targetLower = string.lower(target)
	local exactMatch = nil
	local partialMatches = {}

	for _, candidate in ipairs(Players:GetPlayers()) do
		local nameLower = string.lower(candidate.Name)
		local displayLower = string.lower(candidate.DisplayName)

		if nameLower == targetLower or displayLower == targetLower then
			exactMatch = candidate
			break
		end

		if nameLower:sub(1, #targetLower) == targetLower
			or displayLower:sub(1, #targetLower) == targetLower then

			table.insert(partialMatches, candidate)
		end
	end

	if exactMatch then
		return exactMatch, nil
	end

	if #partialMatches == 1 then
		return partialMatches[1], nil
	end

	if #partialMatches > 1 then
		return nil, "Target player name is ambiguous."
	end

	return nil, "Target player is not online."
end

local function checkAdminChatCommandAccess(actorPlayer, targetPlayer)
	if not isStudioAdmin(actorPlayer) and not AdminConfig.IsAdmin(actorPlayer.UserId) then
		return false, "Access denied."
	end

	if targetPlayer
		and targetPlayer.UserId ~= actorPlayer.UserId
		and AdminConfig.TargetIsProtected(actorPlayer.UserId, targetPlayer.UserId) then

		return false, "You cannot target an admin with equal or higher rank."
	end

	return true, nil
end

local function logAdminTestCommand(actorPlayer, targetPlayer, commandName, details)
	print(
		"[AdminCommand]",
		"adminUserId=", actorPlayer.UserId,
		"targetUserId=", targetPlayer and targetPlayer.UserId or "nil",
		"command=", commandName,
		"details=", tostring(details or "")
	)
end

local function getUserSummary(actorPlayer, targetUserId)
	local onlinePlayer = Players:GetPlayerByUserId(targetUserId)

	local username = "Unknown"
	local displayName = "Unknown"
	local isOnline = onlinePlayer ~= nil

	if onlinePlayer then
		username = onlinePlayer.Name
		displayName = onlinePlayer.DisplayName
	else
		local success, result = pcall(function()
			return Players:GetNameFromUserIdAsync(targetUserId)
		end)

		if success and typeof(result) == "string" then
			username = result
			displayName = result
		end
	end

	return {
		UserId = targetUserId,
		Username = username,
		DisplayName = displayName,
		IsOnline = isOnline,
		TargetAdminRank = AdminConfig.GetRank(targetUserId),
		IsProtectedFromYou = AdminConfig.TargetIsProtected(actorPlayer.UserId, targetUserId),
	}
end

local function handleModerationPayload(data)
	if typeof(data) ~= "table" then
		return
	end

	local targetUserId = normalizeUserId(data.UserId)

	if not targetUserId then
		return
	end

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)

	-- Only create a local write block if this server actually has the player.
	-- This avoids leaving stale blocks for users who were never in this server.
	if not targetPlayer then
		return
	end

	RoomPersistence.BlockWritesForUserId(targetUserId)

	local kickMessage = tostring(data.KickMessage or "You have been removed by an administrator.")
	targetPlayer:Kick(kickMessage)
end

local function publishModerationBlock(targetUserId, kickMessage, issuedByUserId, actionName)
	local payload = {
		Type = "BlockWritesAndKick",
		UserId = targetUserId,
		KickMessage = kickMessage,
		IssuedByUserId = issuedByUserId,
		Action = actionName,
		ServerId = SERVER_ID,
		Time = os.time(),
	}

	-- Apply locally immediately.
	handleModerationPayload(payload)

	local success, errorMessage = pcall(function()
		MessagingService:PublishAsync(MODERATION_TOPIC, payload)
	end)

	if not success then
		warn("Admin moderation broadcast failed:", errorMessage)

		if AdminConfig.REQUIRE_CROSS_SERVER_BLOCK_IN_LIVE and not RunService:IsStudio() then
			return false, "Cross-server write-block failed. Destructive action cancelled."
		end
	end

	-- Give other servers a short moment to block writes before profile deletion.
	task.wait(0.5)

	return true, nil
end

local subscribeSuccess, subscribeError = pcall(function()
	MessagingService:SubscribeAsync(MODERATION_TOPIC, function(message)
		handleModerationPayload(message.Data)
	end)
end)

if not subscribeSuccess then
	warn("Admin moderation subscribe failed:", subscribeError)
end

local executeAdminCommand = nil

local function validateConfirmation(actionName, payload)
	local required = REQUIRED_CONFIRMATION[actionName]

	if not required then
		return true, nil
	end

	local confirm = trim(payload.Confirm or payload.confirm or "")

	if confirm ~= required then
		return false, "Type " .. required .. " in the confirmation box first."
	end

	return true, nil
end

local function processAction(player, actionName, payload)
	if actionName == "GetAccess" then
		local accessPayload = getAccessPayload(player)
		sendResult(
			player,
			"Access",
			accessPayload.IsAdmin,
			accessPayload.IsAdmin and "Admin access granted." or "No admin access.",
			accessPayload
		)
		return
	end

	local accessOk, accessMessage = checkAdminAccess(player, actionName)

	if not accessOk then
		sendResult(player, actionName, false, accessMessage, getAccessPayload(player))
		return
	end

	if typeof(payload) ~= "table" then
		payload = {}
	end

	local targetUserId = normalizeUserId(payload.TargetUserId or payload.targetUserId)

	if actionName == "LookupUser" then
		if not targetUserId then
			sendResult(player, actionName, false, "Enter a valid numeric UserId.")
			return
		end

		sendResult(player, actionName, true, "Lookup complete.", getUserSummary(player, targetUserId))
		return
	end

	local targetOk, targetMessage = checkTargetAllowed(player, actionName, targetUserId)

	if not targetOk then
		sendResult(player, actionName, false, targetMessage)
		return
	end

	local confirmOk, confirmMessage = validateConfirmation(actionName, payload)

	if not confirmOk then
		sendResult(player, actionName, false, confirmMessage)
		return
	end

	if actionName == "ResetProfile" then
		local broadcastOk, broadcastMessage = publishModerationBlock(
			targetUserId,
			"Your profile was reset. Please rejoin to start fresh.",
			player.UserId,
			actionName
		)

		if not broadcastOk then
			sendResult(player, actionName, false, broadcastMessage)
			return
		end

		local success, message = AdminDataTools.ResetProfileByUserId(targetUserId, player.UserId)
		sendResult(player, actionName, success, message, getUserSummary(player, targetUserId))
		return
	end

	if actionName == "ExploitBan" then
		local reason = sanitizeReason(payload.Reason or payload.reason)

		if #reason < AdminConfig.MIN_BAN_REASON_LENGTH then
			sendResult(
				player,
				actionName,
				false,
				"Enter a reason with at least "
					.. tostring(AdminConfig.MIN_BAN_REASON_LENGTH)
					.. " characters."
			)
			return
		end

		local broadcastOk, broadcastMessage = publishModerationBlock(
			targetUserId,
			"You have been banned from this experience.",
			player.UserId,
			actionName
		)

		if not broadcastOk then
			sendResult(player, actionName, false, broadcastMessage)
			return
		end

		local success, message = AdminDataTools.ExploitBanByUserId(targetUserId, player.UserId, reason)
		sendResult(player, actionName, success, message, getUserSummary(player, targetUserId))
		return
	end

	if actionName == "Unban" then
		local success, message = AdminDataTools.UnbanByUserId(targetUserId, player.UserId)
		sendResult(player, actionName, success, message, getUserSummary(player, targetUserId))
		return
	end

	sendResult(player, actionName, false, "Unknown action.")
end

adminCommandRequest.OnServerEvent:Connect(function(player, actionName, payload)
	if typeof(actionName) == "string" then
		local commandText = trim(actionName)

		if commandText == "" or commandText:sub(1, 1) == "/" then
			executeAdminCommand(player, actionName, "RemoteEvent")
			return
		end
	end

	if typeof(actionName) == "string"
		and actionName == "RunCommand"
		and typeof(payload) == "table"
		and typeof(payload.CommandText) == "string" then

		executeAdminCommand(player, payload.CommandText, "RemoteEvent")
		return
	end

	if typeof(actionName) ~= "string" or not VALID_ACTIONS[actionName] then
		sendResult(player, "Invalid", false, "Invalid admin action.")
		return
	end

	if not checkCooldown(player) then
		sendResult(player, actionName, false, "Slow down before sending another admin command.")
		return
	end

	if commandInFlightByUserId[player.UserId] then
		sendResult(player, actionName, false, "Another admin command is still running.")
		return
	end

	commandInFlightByUserId[player.UserId] = true

	local success, errorMessage = pcall(function()
		processAction(player, actionName, payload)
	end)

	commandInFlightByUserId[player.UserId] = nil

	if not success then
		warn("Admin command error:", player.Name, actionName, errorMessage)
		sendResult(player, actionName, false, "Internal admin command error.")
	end
end)

local function handleGiveItemCommand(actorPlayer, args)
	if #args ~= 6 then
		return false, "Usage: /giveitem playerName itemId quantity tradable|untradable sellable|unsellable"
	end

	local targetPlayer, targetMessage = findOnlineTargetPlayer(actorPlayer, args[2])

	if not targetPlayer then
		return false, targetMessage
	end

	local accessOk, accessMessage = checkAdminChatCommandAccess(actorPlayer, targetPlayer)

	if not accessOk then
		return false, accessMessage
	end

	local itemId = trim(args[3])

	if itemId == "" or #itemId > 100 then
		return false, "Invalid itemId."
	end

	local quantity = parsePositiveInteger(args[4], MAX_ADMIN_ITEM_QUANTITY)

	if not quantity then
		return false, "Quantity must be a positive integer up to " .. tostring(MAX_ADMIN_ITEM_QUANTITY) .. "."
	end

	local tradable = parseTradableFlag(args[5])

	if tradable == nil then
		return false, "Use tradable or untradable."
	end

	local sellable = parseSellableFlag(args[6])

	if sellable == nil then
		return false, "Use sellable or unsellable."
	end

	local success, message =
		RoomPersistence.AddInventoryItem(targetPlayer, itemId, quantity, {
			Tradable = tradable,
			Sellable = sellable,
		})

	if not success then
		return false, message or "Could not give item."
	end

	sendInventorySnapshot(targetPlayer, "Inventory updated by admin.")
	logAdminTestCommand(
		actorPlayer,
		targetPlayer,
		"giveitem",
		itemId
			.. " x" .. tostring(quantity)
			.. " "
			.. (tradable and "tradable" or "untradable")
			.. " "
			.. (sellable and "sellable" or "unsellable")
	)

	return true,
		"Gave "
			.. targetPlayer.Name
			.. " "
			.. itemId
			.. " x"
			.. tostring(quantity)
			.. "."
end

local function handleItemDetailsCommand(actorPlayer, args)
	if #args ~= 3 then
		return false, "Usage: /itemdetails playerName itemId"
	end

	local targetPlayer, targetMessage = findOnlineTargetPlayer(actorPlayer, args[2])

	if not targetPlayer then
		return false, targetMessage
	end

	local accessOk, accessMessage = checkAdminChatCommandAccess(actorPlayer, targetPlayer)

	if not accessOk then
		return false, accessMessage
	end

	local itemId = trim(args[3])

	if itemId == "" or #itemId > 100 then
		return false, "Invalid itemId."
	end

	if not RoomPersistence.GetProfile(targetPlayer) then
		return false, "Target profile is not loaded."
	end

	local details = getInventoryDetailsForTemplate(targetPlayer, itemId)
	local message = itemId
		.. " Total="
		.. tostring(details.Total or 0)
		.. " Tradable="
		.. tostring(details.Tradable or 0)
		.. " Untradable="
		.. tostring(details.Untradable or 0)
		.. " Sellable="
		.. tostring(details.Sellable or 0)
		.. " Unsellable="
		.. tostring(details.Unsellable or 0)

	logAdminTestCommand(actorPlayer, targetPlayer, "itemdetails", itemId)
	print("[AdminCommand] itemdetails", "targetUserId=", targetPlayer.UserId, message)

	return true, message, details
end

local function setRawInventoryCount(profile, itemId, total, untradable, unsellable)
	profile.Inventory = profile.Inventory or {}
	profile.InventoryUntradable = profile.InventoryUntradable or {}
	profile.InventoryUnsellable = profile.InventoryUnsellable or {}

	if total <= 0 then
		profile.Inventory[itemId] = nil
		profile.InventoryUntradable[itemId] = nil
		profile.InventoryUnsellable[itemId] = nil
	else
		profile.Inventory[itemId] = total

		if untradable > 0 then
			profile.InventoryUntradable[itemId] = math.min(untradable, total)
		else
			profile.InventoryUntradable[itemId] = nil
		end

		if unsellable > 0 then
			profile.InventoryUnsellable[itemId] = math.min(unsellable, total)
		else
			profile.InventoryUnsellable[itemId] = nil
		end
	end

	profile.UpdatedAt = os.time()
end

local function handleSetItemCommand(actorPlayer, args)
	if #args ~= 6 then
		return false, "Usage: /setitem playerName itemId total untradable unsellable"
	end

	local targetPlayer, targetMessage = findOnlineTargetPlayer(actorPlayer, args[2])

	if not targetPlayer then
		return false, targetMessage
	end

	local accessOk, accessMessage = checkAdminChatCommandAccess(actorPlayer, targetPlayer)

	if not accessOk then
		return false, accessMessage
	end

	local itemId = trim(args[3])

	if itemId == "" or #itemId > 100 then
		return false, "Invalid itemId."
	end

	local total = parseNonNegativeInteger(args[4], MAX_ADMIN_ITEM_QUANTITY)
	local untradable = parseNonNegativeInteger(args[5], MAX_ADMIN_ITEM_QUANTITY)
	local unsellable = parseNonNegativeInteger(args[6], MAX_ADMIN_ITEM_QUANTITY)

	if total == nil or untradable == nil or unsellable == nil then
		return false, "Counts must be whole numbers from 0 to " .. tostring(MAX_ADMIN_ITEM_QUANTITY) .. "."
	end

	if untradable > total or unsellable > total then
		return false, "Subset counts cannot exceed total."
	end

	local profile = RoomPersistence.GetProfile(targetPlayer)

	if not profile then
		return false, "Target profile is not loaded."
	end

	setRawInventoryCount(profile, itemId, total, untradable, unsellable)
	RoomPersistence.QueueSave(targetPlayer)
	sendInventorySnapshot(targetPlayer, "Inventory updated by admin.")
	logAdminTestCommand(
		actorPlayer,
		targetPlayer,
		"setitem",
		itemId
			.. " total=" .. tostring(total)
			.. " untradable=" .. tostring(untradable)
			.. " unsellable=" .. tostring(unsellable)
	)

	local details = getInventoryDetailsForTemplate(targetPlayer, itemId)

	return true,
		"Set "
			.. targetPlayer.Name
			.. " "
			.. itemId
			.. " Total="
			.. tostring(details.Total or 0)
			.. " Tradable="
			.. tostring(details.Tradable or 0)
			.. " Untradable="
			.. tostring(details.Untradable or 0)
			.. " Sellable="
			.. tostring(details.Sellable or 0)
			.. " Unsellable="
			.. tostring(details.Unsellable or 0),
		details
end

local function handleGiveCurrencyCommand(actorPlayer, args, currencyKey, commandName)
	if #args ~= 3 then
		return false, "Usage: /" .. commandName .. " playerName amount"
	end

	local targetPlayer, targetMessage = findOnlineTargetPlayer(actorPlayer, args[2])

	if not targetPlayer then
		return false, targetMessage
	end

	local accessOk, accessMessage = checkAdminChatCommandAccess(actorPlayer, targetPlayer)

	if not accessOk then
		return false, accessMessage
	end

	local amount = parsePositiveInteger(args[3], MAX_ADMIN_CURRENCY_AMOUNT)

	if not amount then
		return false, "Amount must be a positive integer up to " .. tostring(MAX_ADMIN_CURRENCY_AMOUNT) .. "."
	end

	local success, message, newBalance =
		RoomPersistence.AddCurrency(targetPlayer, currencyKey, amount, "AdminCommand")

	if not success then
		return false, message or "Could not give currency."
	end

	sendCurrencySnapshot(targetPlayer, "Currencies updated by admin.")
	logAdminTestCommand(
		actorPlayer,
		targetPlayer,
		commandName,
		currencyKey .. " +" .. tostring(amount)
	)

	return true,
		"Gave "
			.. targetPlayer.Name
			.. " "
			.. tostring(amount)
			.. " "
			.. currencyKey
			.. ". New balance: "
			.. tostring(newBalance)
end

executeAdminCommand = function(player, commandText, source)
	local normalizedCommandText = trim(commandText)
	local args = splitCommandText(normalizedCommandText)
	local commandName = args[1]

	if normalizedCommandText == "" then
		sendAdminCommandResult(player, false, "Enter an admin command.", {}, nil, source)
		return true
	end

	if typeof(commandName) ~= "string" or commandName:sub(1, 1) ~= "/" then
		sendAdminCommandResult(player, false, "Admin commands must start with /.", {}, nil, source)
		return true
	end

	commandName = string.lower(commandName:sub(2))

	if commandName ~= "giveitem"
		and commandName ~= "itemdetails"
		and commandName ~= "setitem"
		and commandName ~= "givecoins"
		and commandName ~= "givedollars" then

		sendAdminCommandResult(player, false, "Unknown admin command.", {}, commandName, source)
		return true
	end

	local now = os.clock()
	local previous = lastChatCommandByUserId[player.UserId]

	if previous
		and previous.Text == normalizedCommandText
		and now - previous.At < 0.25 then

		return true
	end

	lastChatCommandByUserId[player.UserId] = {
		Text = normalizedCommandText,
		At = now,
	}

	if not isStudioAdmin(player) and not AdminConfig.IsAdmin(player.UserId) then
		sendAdminCommandResult(player, false, "Access denied.", {}, commandName, source)
		return true
	end

	if not checkCooldown(player) then
		sendAdminCommandResult(
			player,
			false,
			"Slow down before sending another admin command.",
			{},
			commandName,
			source
		)
		return true
	end

	if commandInFlightByUserId[player.UserId] then
		sendAdminCommandResult(player, false, "Another admin command is still running.", {}, commandName, source)
		return true
	end

	commandInFlightByUserId[player.UserId] = true

	local ok, success, resultMessage, resultData = pcall(function()
		if commandName == "giveitem" then
			return handleGiveItemCommand(player, args)
		end

		if commandName == "itemdetails" then
			return handleItemDetailsCommand(player, args)
		end

		if commandName == "setitem" then
			return handleSetItemCommand(player, args)
		end

		if commandName == "givecoins" then
			return handleGiveCurrencyCommand(player, args, "Coins", commandName)
		end

		return handleGiveCurrencyCommand(player, args, "Dollars", commandName)
	end)

	commandInFlightByUserId[player.UserId] = nil

	if not ok then
		warn("Admin chat command error:", player.Name, commandName, success)
		sendAdminCommandResult(player, false, "Internal admin command error.", {}, commandName, source)
		return true
	end

	sendAdminCommandResult(player, success, resultMessage, resultData, commandName, source)
	return true
end

local function connectTextChatCommand(commandName)
	local commandInstance = TextChatService:FindFirstChild("Admin" .. commandName .. "Command")

	if commandInstance and not commandInstance:IsA("TextChatCommand") then
		warn("Admin text chat command name is occupied:", commandInstance.Name)
		return
	end

	if not commandInstance then
		local createdOk, createdCommand = pcall(function()
			return Instance.new("TextChatCommand")
		end)

		if not createdOk or not createdCommand then
			warn("Admin text chat commands are unavailable:", createdCommand)
			return
		end

		commandInstance = createdCommand
		commandInstance.Name = "Admin" .. commandName .. "Command"
		commandInstance.PrimaryAlias = "/" .. string.lower(commandName)
		commandInstance.Parent = TextChatService
	end

	local connectedOk, connectError = pcall(function()
		commandInstance.Triggered:Connect(function(textSource, unfilteredText)
			local player = textSource and Players:GetPlayerByUserId(textSource.UserId)

			if not player then
				return
			end

			local text = tostring(unfilteredText or "")

			if text:sub(1, 1) ~= "/" then
				text = "/" .. string.lower(commandName) .. (text ~= "" and (" " .. text) or "")
			end

			executeAdminCommand(player, text, "TextChatCommand")
		end)
	end)

	if not connectedOk then
		warn("Admin text chat command connection failed:", commandInstance.Name, connectError)
	end
end

for _, commandName in ipairs({
	"giveitem",
	"itemdetails",
	"setitem",
	"givecoins",
	"givedollars",
}) do
	connectTextChatCommand(commandName)
end

local function initializePlayer(player)
	local accessPayload = getAccessPayload(player)

	print(
		"[AdminCommandServer] Checking admin access:",
		player.Name,
		player.UserId,
		"Rank:",
		accessPayload.Rank,
		"Reason:",
		accessPayload.AccessReason
	)

	player:SetAttribute("IsAdmin", accessPayload.IsAdmin)
	player:SetAttribute("AdminAccessReason", accessPayload.AccessReason)

	if chatConnectionsByPlayer[player] then
		chatConnectionsByPlayer[player]:Disconnect()
	end

	chatConnectionsByPlayer[player] = player.Chatted:Connect(function(message)
		executeAdminCommand(player, message, "PlayerChatted")
	end)

	task.delay(1, function()
		if player.Parent == Players then
			sendResult(
				player,
				"Access",
				accessPayload.IsAdmin,
				accessPayload.IsAdmin and "Admin access granted." or "No admin access.",
				accessPayload
			)
		end
	end)
end

Players.PlayerAdded:Connect(initializePlayer)

Players.PlayerRemoving:Connect(function(player)
	lastRequestAtByUserId[player.UserId] = nil
	commandInFlightByUserId[player.UserId] = nil
	lastChatCommandByUserId[player.UserId] = nil
	studioAdminOverrideLoggedByUserId[player.UserId] = nil

	if chatConnectionsByPlayer[player] then
		chatConnectionsByPlayer[player]:Disconnect()
		chatConnectionsByPlayer[player] = nil
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.defer(initializePlayer, player)
end
