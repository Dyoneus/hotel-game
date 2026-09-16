-- ServerScriptService/AdminConfig.lua
local AdminConfig = {}

-- Replace 123456789 with your actual Roblox UserId.
-- Keep this server-side only. Do not put admin IDs in a LocalScript.
AdminConfig.USERS = {
	[37382153] = {
		Rank = 100,
		Label = "Owner",
	},
}

AdminConfig.PERMISSIONS = {
	GetAccess = 1,
	LookupUser = 50,
	ResetProfile = 90,
	ExploitBan = 100,
	Unban = 100,
}

AdminConfig.RATE_LIMIT_SECONDS = 1.5
AdminConfig.MIN_BAN_REASON_LENGTH = 5
AdminConfig.MAX_REASON_LENGTH = 220

AdminConfig.DISALLOW_SELF_MODERATION = true

-- In live servers, destructive actions should broadcast a cross-server
-- write-block/kick before deleting profile data.
AdminConfig.REQUIRE_CROSS_SERVER_BLOCK_IN_LIVE = true

local function normalizeUserId(userId)
	userId = tonumber(userId)

	if not userId or userId <= 0 then
		return nil
	end

	return math.floor(userId)
end

function AdminConfig.GetAdminInfo(userId)
	userId = normalizeUserId(userId)

	if not userId then
		return nil
	end

	return AdminConfig.USERS[userId]
end

function AdminConfig.GetRank(userId)
	local info = AdminConfig.GetAdminInfo(userId)

	if typeof(info) == "table" then
		return tonumber(info.Rank) or 0
	end

	if typeof(info) == "number" then
		return info
	end

	if info == true then
		return 100
	end

	return 0
end

function AdminConfig.IsAdmin(userId)
	return AdminConfig.GetRank(userId) > 0
end

function AdminConfig.CanRun(userId, actionName)
	local requiredRank = AdminConfig.PERMISSIONS[actionName]

	if typeof(requiredRank) ~= "number" then
		return false
	end

	return AdminConfig.GetRank(userId) >= requiredRank
end

function AdminConfig.TargetIsProtected(actorUserId, targetUserId)
	local actorRank = AdminConfig.GetRank(actorUserId)
	local targetRank = AdminConfig.GetRank(targetUserId)

	if targetRank <= 0 then
		return false
	end

	return targetRank >= actorRank
end

function AdminConfig.GetPermissionsForUser(userId)
	local permissions = {}

	for actionName in pairs(AdminConfig.PERMISSIONS) do
		permissions[actionName] = AdminConfig.CanRun(userId, actionName)
	end

	return permissions
end

return AdminConfig