-- ServerScriptService/WorkActivityServer.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local WorkActivityConfig = require(sharedFolder:WaitForChild("WorkActivityConfig"))

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

	local remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = name
	remoteEvent.Parent = remoteEvents

	return remoteEvent
end

local workActivityRequest = getOrCreateRemoteEvent("WorkActivityRequest")
local workActivityResult = getOrCreateRemoteEvent("WorkActivityResult")

local REQUEST_COOLDOWN_SECONDS = 0.25
local ATTEMPT_EXPIRY_GRACE_SECONDS = 10

local activeAttempts = {}
local cooldowns = {}
local lastRequestByUserId = {}

local VALID_ACTIONS = {
	GetActivities = true,
	StartActivity = true,
	CompleteActivity = true,
	GetCooldowns = true,
}

local function sendResult(player, payload)
	if not player or player.Parent ~= Players then
		return
	end

	payload = payload or {}
	payload.Kind = tostring(payload.Kind or "Unknown")
	payload.Success = payload.Success == true
	payload.Message = tostring(payload.Message or "")

	workActivityResult:FireClient(player, payload)
end

local function getSafeActionName(actionName)
	if typeof(actionName) ~= "string" or not VALID_ACTIONS[actionName] then
		return "Unknown"
	end

	return actionName
end

local function getSafePayload(payload)
	if typeof(payload) == "table" then
		return payload
	end

	return {}
end

local function isRequestRateLimited(player, actionName)
	local now = os.clock()
	local previous = lastRequestByUserId[player.UserId]

	if previous
		and previous.ActionName == actionName
		and now - previous.RequestedAt < REQUEST_COOLDOWN_SECONDS then

		return true
	end

	lastRequestByUserId[player.UserId] = {
		ActionName = actionName,
		RequestedAt = now,
	}

	return false
end

local function getUserActivityTable(container, userId)
	local userTable = container[userId]

	if not userTable then
		userTable = {}
		container[userId] = userTable
	end

	return userTable
end

local function getCooldownRemaining(userId, activityId)
	local userCooldowns = cooldowns[userId]

	if not userCooldowns then
		return 0
	end

	local expiresAt = userCooldowns[activityId]

	if typeof(expiresAt) ~= "number" then
		return 0
	end

	local remaining = expiresAt - os.clock()

	if remaining <= 0 then
		userCooldowns[activityId] = nil
		return 0
	end

	return remaining
end

local function validateActivity(activityId)
	local activity = WorkActivityConfig.GetActivity(activityId)

	if not activity then
		return nil, "Unknown work activity."
	end

	if activity.Enabled ~= true then
		return nil, "This work activity is not available."
	end

	return activity, nil
end

local function validateWorkStartLocation(player)
	if player:GetAttribute("InHotelMainMenu") ~= true then
		return false, "Work can only start from the Main Menu."
	end

	if player:GetAttribute("CurrentRoomName") ~= nil then
		return false, "Work can only start from the Main Menu."
	end

	return true, nil
end

local function buildCooldownsForActivities(userId, activities)
	local activityCooldowns = {}

	for _, activity in ipairs(activities) do
		activityCooldowns[activity.ActivityId] = getCooldownRemaining(userId, activity.ActivityId)
	end

	return activityCooldowns
end

local function handleGetActivities(player)
	local activities = WorkActivityConfig.GetAllActivities()

	sendResult(player, {
		Kind = "Activities",
		Success = true,
		Message = "Work activities loaded.",
		Activities = activities,
		Cooldowns = buildCooldownsForActivities(player.UserId, activities),
	})
end

local function handleGetCooldowns(player)
	local activities = WorkActivityConfig.GetAllActivities()

	sendResult(player, {
		Kind = "Cooldowns",
		Success = true,
		Message = "Work cooldowns loaded.",
		Cooldowns = buildCooldownsForActivities(player.UserId, activities),
	})
end

local function handleStartActivity(player, payload)
	local activityId = payload.ActivityId
	local activity, activityMessage = validateActivity(activityId)

	if not activity then
		sendResult(player, {
			Kind = "StartActivity",
			Success = false,
			Message = activityMessage,
			ActivityId = activityId,
		})
		return
	end

	local locationValid, locationMessage = validateWorkStartLocation(player)

	if not locationValid then
		sendResult(player, {
			Kind = "StartActivity",
			Success = false,
			Message = locationMessage,
			ActivityId = activity.ActivityId,
		})
		return
	end

	local remainingCooldown = getCooldownRemaining(player.UserId, activity.ActivityId)

	if remainingCooldown > 0 then
		sendResult(player, {
			Kind = "StartActivity",
			Success = false,
			Message = "Please wait before working again.",
			ActivityId = activity.ActivityId,
			RemainingCooldown = remainingCooldown,
		})
		return
	end

	local userAttempts = getUserActivityTable(activeAttempts, player.UserId)
	local existingAttempt = userAttempts[activity.ActivityId]
	local now = os.clock()

	if existingAttempt and typeof(existingAttempt.ExpiresAt) == "number" and now < existingAttempt.ExpiresAt then
		sendResult(player, {
			Kind = "StartActivity",
			Success = false,
			Message = "Work already started.",
			ActivityId = activity.ActivityId,
			DurationSeconds = activity.DurationSeconds,
		})
		return
	end

	userAttempts[activity.ActivityId] = {
		StartedAt = now,
		ExpiresAt = now + activity.DurationSeconds + ATTEMPT_EXPIRY_GRACE_SECONDS,
	}

	sendResult(player, {
		Kind = "StartActivity",
		Success = true,
		Message = "Work started.",
		ActivityId = activity.ActivityId,
		DurationSeconds = activity.DurationSeconds,
	})
end

local function handleCompleteActivity(player, payload)
	local activityId = payload.ActivityId
	local activity, activityMessage = validateActivity(activityId)

	if not activity then
		sendResult(player, {
			Kind = "CompleteActivity",
			Success = false,
			Message = activityMessage,
			ActivityId = activityId,
		})
		return
	end

	local userAttempts = activeAttempts[player.UserId]
	local attempt = userAttempts and userAttempts[activity.ActivityId]

	if not attempt then
		sendResult(player, {
			Kind = "CompleteActivity",
			Success = false,
			Message = "No active work attempt.",
			ActivityId = activity.ActivityId,
		})
		return
	end

	local now = os.clock()

	if now - attempt.StartedAt < activity.DurationSeconds then
		sendResult(player, {
			Kind = "CompleteActivity",
			Success = false,
			Message = "Work is not complete yet.",
			ActivityId = activity.ActivityId,
		})
		return
	end

	if now > attempt.ExpiresAt then
		userAttempts[activity.ActivityId] = nil

		sendResult(player, {
			Kind = "CompleteActivity",
			Success = false,
			Message = "Work attempt expired.",
			ActivityId = activity.ActivityId,
		})
		return
	end

	userAttempts[activity.ActivityId] = nil
	getUserActivityTable(cooldowns, player.UserId)[activity.ActivityId] = now + activity.CooldownSeconds

	sendResult(player, {
		Kind = "CompleteActivity",
		Success = true,
		Message = "Work complete. Rewards are not enabled yet.",
		ActivityId = activity.ActivityId,
		RewardAmount = activity.RewardAmount,
		RewardCurrency = activity.RewardCurrency,
		RemainingCooldown = activity.CooldownSeconds,
	})
end

local function handleRequest(player, actionName, payload)
	if not player or player.Parent ~= Players then
		return
	end

	local safeActionName = getSafeActionName(actionName)

	if safeActionName == "Unknown" then
		sendResult(player, {
			Kind = "Unknown",
			Success = false,
			Message = "Unknown work activity action.",
		})
		return
	end

	if isRequestRateLimited(player, safeActionName) then
		sendResult(player, {
			Kind = safeActionName,
			Success = false,
			Message = "Please slow down before requesting work activities.",
		})
		return
	end

	local safePayload = getSafePayload(payload)

	if safeActionName == "GetActivities" then
		handleGetActivities(player)
	elseif safeActionName == "StartActivity" then
		handleStartActivity(player, safePayload)
	elseif safeActionName == "CompleteActivity" then
		handleCompleteActivity(player, safePayload)
	elseif safeActionName == "GetCooldowns" then
		handleGetCooldowns(player)
	end
end

workActivityRequest.OnServerEvent:Connect(function(player, actionName, payload)
	local success, errorMessage = pcall(function()
		handleRequest(player, actionName, payload)
	end)

	if not success then
		warn("WorkActivityServer request failed:", errorMessage)

		sendResult(player, {
			Kind = getSafeActionName(actionName),
			Success = false,
			Message = "Work activity request failed.",
		})
	end
end)

Players.PlayerRemoving:Connect(function(player)
	activeAttempts[player.UserId] = nil
	cooldowns[player.UserId] = nil
	lastRequestByUserId[player.UserId] = nil
end)
