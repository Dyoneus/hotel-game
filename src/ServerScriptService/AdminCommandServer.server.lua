-- ServerScriptService/AdminCommandServer.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")

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

local MODERATION_TOPIC = "AdminModeration_v1"
local SERVER_ID = game.JobId

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

local function sendResult(player, kind, success, message, data)
	if not player or player.Parent ~= Players then
		return
	end

	adminCommandResult:FireClient(player, {
		Kind = tostring(kind or "Unknown"),
		Success = success == true,
		Message = tostring(message or ""),
		Data = data or {},
	})
end

local function getAccessPayload(player)
	local rank = AdminConfig.GetRank(player.UserId)

	return {
		IsAdmin = rank > 0,
		Rank = rank,
		Permissions = AdminConfig.GetPermissionsForUser(player.UserId),
	}
end

local function checkAdminAccess(player, actionName)
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

local function initializePlayer(player)
	local accessPayload = getAccessPayload(player)

	print(
		"[AdminCommandServer] Checking admin access:",
		player.Name,
		player.UserId,
		"Rank:",
		AdminConfig.GetRank(player.UserId)
	)

	player:SetAttribute("IsAdmin", accessPayload.IsAdmin)

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
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.defer(initializePlayer, player)
end