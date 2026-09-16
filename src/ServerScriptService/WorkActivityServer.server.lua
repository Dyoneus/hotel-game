-- ServerScriptService/WorkActivityServer.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local WorkActivityConfig = require(sharedFolder:WaitForChild("WorkActivityConfig"))
local RoomPersistence = require(ServerScriptService:WaitForChild("RoomPersistence"))

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

local DEBUG_WORK_ACTIVITY = false
local REQUEST_COOLDOWN_SECONDS = 0.25
local ATTEMPT_EXPIRY_GRACE_SECONDS = 10

local activeAttempts = {}
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

local function debugLog(...)
	if DEBUG_WORK_ACTIVITY then
		print("[WorkActivity]", ...)
	end
end

local function debugPlayerName(player)
	return player and player.Name or "UnknownPlayer"
end

local function getPayloadActivityId(payload)
	if typeof(payload) == "table" and typeof(payload.ActivityId) == "string" and payload.ActivityId ~= "" then
		return payload.ActivityId
	end

	return nil
end

local function sendFailure(player, kind, message, activityId, extra)
	local payload = extra or {}
	payload.Kind = kind
	payload.Success = false
	payload.Message = message

	if activityId ~= nil then
		payload.ActivityId = activityId
	end

	debugLog(
		tostring(kind) .. " denied",
		debugPlayerName(player),
		activityId or "no activity",
		message,
		payload.RemainingCooldown and ("cooldown=" .. tostring(payload.RemainingCooldown)) or ""
	)

	sendResult(player, payload)
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

local function getProfileCooldownRemaining(player, activityId)
	local remainingCooldown, cooldownRecord, cooldownMessage = RoomPersistence.GetWorkActivityCooldown(player, activityId)

	if typeof(remainingCooldown) ~= "number" then
		return nil, cooldownMessage or "Profile is not loaded.", cooldownRecord
	end

	return remainingCooldown, nil, cooldownRecord
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
		return false, "Work can only be started from the Main Menu."
	end

	if player:GetAttribute("CurrentRoomName") ~= nil then
		return false, "Work can only be started from the Main Menu."
	end

	return true, nil
end

local function validateWorkReward(activity)
	if activity.RewardCurrency ~= "Dollars" then
		return false, "Invalid work reward currency."
	end

	local rewardAmount = activity.RewardAmount

	if typeof(rewardAmount) ~= "number"
		or rewardAmount ~= rewardAmount
		or rewardAmount <= 0
		or rewardAmount >= math.huge
		or rewardAmount ~= math.floor(rewardAmount) then

		return false, "Invalid work reward amount."
	end

	return true, nil, rewardAmount
end

local function validateWorkCooldown(activity)
	local cooldownSeconds = activity.CooldownSeconds

	if typeof(cooldownSeconds) ~= "number"
		or cooldownSeconds ~= cooldownSeconds
		or cooldownSeconds < 0
		or cooldownSeconds >= math.huge then

		return false, "Invalid work cooldown."
	end

	return true, nil, math.max(0, math.ceil(cooldownSeconds))
end

local function buildCooldownsForActivities(player, activities)
	local activityCooldowns = {}
	local cooldownSnapshot = RoomPersistence.GetWorkActivityCooldownSnapshot(player)
	local now = os.time()

	for _, activity in ipairs(activities) do
		local cooldownRecord = cooldownSnapshot[activity.ActivityId]
		local remainingCooldown = 0

		if typeof(cooldownRecord) == "table" then
			if typeof(cooldownRecord.RemainingCooldown) == "number" then
				remainingCooldown = math.max(0, math.ceil(cooldownRecord.RemainingCooldown))
			elseif typeof(cooldownRecord.NextAvailableUnix) == "number" then
				remainingCooldown = math.max(0, math.ceil(cooldownRecord.NextAvailableUnix - now))
			end
		end

		activityCooldowns[activity.ActivityId] = remainingCooldown
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
		Cooldowns = buildCooldownsForActivities(player, activities),
	})
end

local function handleGetCooldowns(player)
	local activities = WorkActivityConfig.GetAllActivities()

	sendResult(player, {
		Kind = "Cooldowns",
		Success = true,
		Message = "Work cooldowns loaded.",
		Cooldowns = buildCooldownsForActivities(player, activities),
	})
end

local function handleStartActivity(player, payload)
	local activityId = payload.ActivityId
	local activity, activityMessage = validateActivity(activityId)

	if not activity then
		sendFailure(player, "StartActivity", activityMessage, activityId)
		return
	end

	local locationValid, locationMessage = validateWorkStartLocation(player)

	if not locationValid then
		sendFailure(player, "StartActivity", locationMessage, activity.ActivityId)
		return
	end

	local remainingCooldown, cooldownMessage = getProfileCooldownRemaining(player, activity.ActivityId)

	if remainingCooldown == nil then
		sendFailure(player, "StartActivity", cooldownMessage, activity.ActivityId)
		return
	end

	if remainingCooldown > 0 then
		sendFailure(player, "StartActivity", "Please wait before working again.", activity.ActivityId, {
			RemainingCooldown = remainingCooldown,
		})
		return
	end

	local userAttempts = getUserActivityTable(activeAttempts, player.UserId)
	local existingAttempt = userAttempts[activity.ActivityId]
	local now = os.clock()

	if existingAttempt and typeof(existingAttempt.ExpiresAt) == "number" and now < existingAttempt.ExpiresAt then
		sendFailure(player, "StartActivity", "Work already started.", activity.ActivityId, {
			DurationSeconds = activity.DurationSeconds,
		})
		return
	end

	userAttempts[activity.ActivityId] = {
		StartedAt = now,
		ExpiresAt = now + activity.DurationSeconds + ATTEMPT_EXPIRY_GRACE_SECONDS,
	}

	debugLog("StartActivity accepted", debugPlayerName(player), activity.ActivityId)

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
		sendFailure(player, "CompleteActivity", activityMessage, activityId)
		return
	end

	local userAttempts = activeAttempts[player.UserId]
	local attempt = userAttempts and userAttempts[activity.ActivityId]

	if not attempt then
		sendFailure(player, "CompleteActivity", "No active work attempt.", activity.ActivityId)
		return
	end

	local now = os.clock()

	if now - attempt.StartedAt < activity.DurationSeconds then
		sendFailure(player, "CompleteActivity", "Work is not complete yet.", activity.ActivityId)
		return
	end

	if now > attempt.ExpiresAt then
		userAttempts[activity.ActivityId] = nil

		sendFailure(player, "CompleteActivity", "Work attempt expired.", activity.ActivityId)
		return
	end

	local locationValid, locationMessage = validateWorkStartLocation(player)

	if not locationValid then
		userAttempts[activity.ActivityId] = nil

		sendFailure(player, "CompleteActivity", locationMessage, activity.ActivityId)
		return
	end

	local remainingCooldown, cooldownMessage = getProfileCooldownRemaining(player, activity.ActivityId)

	if remainingCooldown == nil then
		userAttempts[activity.ActivityId] = nil

		sendFailure(player, "CompleteActivity", cooldownMessage, activity.ActivityId)
		return
	end

	if remainingCooldown > 0 then
		userAttempts[activity.ActivityId] = nil

		sendFailure(player, "CompleteActivity", "Please wait before working again.", activity.ActivityId, {
			RemainingCooldown = remainingCooldown,
		})
		return
	end

	local rewardValid, rewardMessage, rewardAmount = validateWorkReward(activity)

	if not rewardValid then
		userAttempts[activity.ActivityId] = nil

		sendFailure(player, "CompleteActivity", rewardMessage, activity.ActivityId)
		return
	end

	local cooldownValid, cooldownValidationMessage, cooldownSeconds = validateWorkCooldown(activity)

	if not cooldownValid then
		userAttempts[activity.ActivityId] = nil

		sendFailure(player, "CompleteActivity", cooldownValidationMessage, activity.ActivityId)
		return
	end

	userAttempts[activity.ActivityId] = nil

	local grantSuccess, grantMessage, newDollarBalance = RoomPersistence.AddDollars(
		player,
		rewardAmount,
		"WorkActivity:" .. activity.ActivityId
	)

	if not grantSuccess then
		sendFailure(player, "CompleteActivity", grantMessage or "Could not grant work reward.", activity.ActivityId)
		return
	end

	debugLog(
		"CompleteActivity reward granted",
		debugPlayerName(player),
		activity.ActivityId,
		rewardAmount,
		"Dollars",
		"balance=" .. tostring(newDollarBalance)
	)

	local cooldownSuccess, cooldownSaveMessage, savedRemainingCooldown = RoomPersistence.SetWorkActivityCooldown(
		player,
		activity.ActivityId,
		cooldownSeconds
	)

	if not cooldownSuccess then
		debugLog(
			"CompleteActivity cooldown save failed",
			debugPlayerName(player),
			activity.ActivityId,
			tostring(cooldownSaveMessage)
		)

		sendFailure(player, "CompleteActivity", cooldownSaveMessage or "Could not save work cooldown.", activity.ActivityId, {
			Warning = cooldownSaveMessage,
		})
		return
	end

	debugLog(
		"CompleteActivity accepted",
		debugPlayerName(player),
		activity.ActivityId,
		"cooldown=" .. tostring(savedRemainingCooldown or cooldownSeconds)
	)

	sendResult(player, {
		Kind = "CompleteActivity",
		Success = true,
		Message = "Work complete! You earned " .. tostring(rewardAmount) .. " Dollars.",
		ActivityId = activity.ActivityId,
		RewardAmount = rewardAmount,
		RewardCurrency = "Dollars",
		NewCurrencyBalance = newDollarBalance,
		RemainingCooldown = savedRemainingCooldown or cooldownSeconds,
	})
end

local function handleRequest(player, actionName, payload)
	if not player or player.Parent ~= Players then
		return
	end

	local safeActionName = getSafeActionName(actionName)

	if safeActionName == "Unknown" then
		sendFailure(player, "Unknown", "Unknown work activity action.", getPayloadActivityId(payload))
		return
	end

	if isRequestRateLimited(player, safeActionName) then
		sendFailure(
			player,
			safeActionName,
			"Please slow down before requesting work activities.",
			getPayloadActivityId(payload)
		)
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

		sendFailure(
			player,
			getSafeActionName(actionName),
			"Work activity request failed.",
			getPayloadActivityId(payload)
		)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	activeAttempts[player.UserId] = nil
	lastRequestByUserId[player.UserId] = nil
end)
