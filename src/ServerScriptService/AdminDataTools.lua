-- Explorer/ServerScriptService/AdminDataTools.lua
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local RoomPersistence = require(ServerScriptService:WaitForChild("RoomPersistence"))

local AdminDataTools = {}

local function normalizeUserId(userId)
	userId = tonumber(userId)

	if not userId or userId <= 0 then
		return nil
	end

	return math.floor(userId)
end

function AdminDataTools.ResetProfileByUserId(targetUserId, moderatorUserId)
	targetUserId = normalizeUserId(targetUserId)

	if not targetUserId then
		return false, "Invalid target UserId."
	end

	local success, result = RoomPersistence.DeleteProfileByUserId(targetUserId)

	if not success then
		return false, "Profile reset failed: " .. tostring(result)
	end

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)

	if targetPlayer then
		targetPlayer:Kick("Your profile was reset. Please rejoin to start fresh.")
	end

	print(
		"ADMIN RESET PROFILE:",
		"TargetUserId =", targetUserId,
		"ModeratorUserId =", moderatorUserId or "Unknown"
	)

	return true, "Profile reset complete."
end

function AdminDataTools.ExploitBanByUserId(targetUserId, moderatorUserId, privateReason)
	targetUserId = normalizeUserId(targetUserId)

	if not targetUserId then
		return false, "Invalid target UserId."
	end

	privateReason = tostring(privateReason or "Exploit ban")
	moderatorUserId = moderatorUserId or 0

	RoomPersistence.BlockWritesForUserId(targetUserId)

	local banSuccess, banError = pcall(function()
		Players:BanAsync({
			UserIds = { targetUserId },

			-- -1 means permanent ban.
			Duration = -1,

			DisplayReason = "You have been banned from this experience.",

			PrivateReason = "Moderator "
				.. tostring(moderatorUserId)
				.. ": "
				.. privateReason,

			-- false allows Roblox's alt-account propagation.
			ExcludeAltAccounts = false,

			-- true applies to all places in this experience/universe.
			ApplyToUniverse = true,
		})
	end)

	if not banSuccess then
		RoomPersistence.UnblockWritesForUserId(targetUserId)
		return false, "Ban failed: " .. tostring(banError)
	end

	local deleteSuccess, deleteResult = RoomPersistence.DeleteProfileByUserId(targetUserId)

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)

	if targetPlayer then
		targetPlayer:Kick("You have been banned from this experience.")
	end

	if not deleteSuccess then
		warn(
			"Player was banned, but profile deletion failed:",
			targetUserId,
			deleteResult
		)

		if not targetPlayer then
			RoomPersistence.UnblockWritesForUserId(targetUserId)
		end

		return true, "Ban succeeded, but profile deletion failed: " .. tostring(deleteResult)
	end

	print(
		"ADMIN EXPLOIT BAN:",
		"TargetUserId =", targetUserId,
		"ModeratorUserId =", moderatorUserId,
		"Reason =", privateReason
	)

	return true, "Ban and profile deletion complete."
end

function AdminDataTools.UnbanByUserId(targetUserId, moderatorUserId)
	targetUserId = normalizeUserId(targetUserId)

	if not targetUserId then
		return false, "Invalid target UserId."
	end

	local success, result = pcall(function()
		Players:UnbanAsync({
			UserIds = { targetUserId },
			ApplyToUniverse = true,
		})
	end)

	if not success then
		return false, "Unban failed: " .. tostring(result)
	end

	print(
		"ADMIN UNBAN:",
		"TargetUserId =", targetUserId,
		"ModeratorUserId =", moderatorUserId or "Unknown"
	)

	return true, "Unban complete."
end

return AdminDataTools