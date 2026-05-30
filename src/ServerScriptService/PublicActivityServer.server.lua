-- ServerScriptService/PublicActivityServer.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local PublicActivityConfig = require(sharedFolder:WaitForChild("PublicActivityConfig"))

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

local publicActivityRequest = getOrCreateRemoteEvent("PublicActivityRequest")
local publicActivityResult = getOrCreateRemoteEvent("PublicActivityResult")

local REQUEST_COOLDOWN_SECONDS = 0.25
local DEFAULT_PROXIMITY_STUDS = 10
local ATTEMPT_EXPIRY_GRACE_SECONDS = 10

local activeAttempts = {}
local cooldowns = {}
local lastRequestByUserId = {}

local activeRooms = workspace:WaitForChild("ActiveRooms")

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

	publicActivityResult:FireClient(player, payload)
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

local function getPlayerRootPart(player)
	local character = player.Character

	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function getCurrentPublicRoom(player)
	local currentRoomName = player:GetAttribute("CurrentRoomName")

	if typeof(currentRoomName) ~= "string" or currentRoomName == "" then
		return nil, "You must be in a public room to do this activity."
	end

	local roomModel = activeRooms:FindFirstChild(currentRoomName)

	if not roomModel then
		return nil, "Current room is not available."
	end

	if roomModel:GetAttribute("RoomType") ~= "PublicSpace" then
		return nil, "You must be in a public room to do this activity."
	end

	return roomModel, nil
end

local function getActivityMarker(roomModel, activity)
	local markerName = activity.MarkerName

	if typeof(markerName) ~= "string" or markerName == "" then
		return nil
	end

	return roomModel:FindFirstChild(markerName, true)
end

local function getMarkerPosition(marker)
	if marker:IsA("BasePart") then
		return marker.Position
	end

	if marker:IsA("Model") then
		return marker:GetPivot().Position
	end

	return nil
end

local function validateActivityContext(player, activity)
	local roomModel, roomMessage = getCurrentPublicRoom(player)

	if not roomModel then
		return false, roomMessage
	end

	if roomModel:GetAttribute("PublicRoomId") ~= activity.PublicRoomId then
		return false, "This activity is not available in this room."
	end

	local rootPart = getPlayerRootPart(player)

	if not rootPart then
		return false, "Character is not ready."
	end

	local marker = getActivityMarker(roomModel, activity)

	if not marker then
		return false, "Activity marker is missing."
	end

	local markerPosition = getMarkerPosition(marker)

	if not markerPosition then
		return false, "Activity marker is missing."
	end

	local maxDistance = typeof(activity.ProximityStuds) == "number"
		and activity.ProximityStuds
		or DEFAULT_PROXIMITY_STUDS

	if (rootPart.Position - markerPosition).Magnitude > maxDistance then
		return false, "Move closer to the activity."
	end

	return true, nil, roomModel, marker
end

local function validateActivity(activityId)
	local activity = PublicActivityConfig.GetActivity(activityId)

	if not activity then
		return nil, "Unknown activity."
	end

	if activity.Enabled ~= true then
		return nil, "This activity is not available."
	end

	return activity, nil
end

local function buildCooldownsForActivities(userId, activities)
	local activityCooldowns = {}

	for _, activity in ipairs(activities) do
		activityCooldowns[activity.ActivityId] = getCooldownRemaining(userId, activity.ActivityId)
	end

	return activityCooldowns
end

local function handleGetActivities(player, payload)
	local publicRoomId = payload.PublicRoomId
	local activities

	if typeof(publicRoomId) == "string" and publicRoomId ~= "" then
		activities = PublicActivityConfig.GetActivitiesForPublicRoom(publicRoomId)
	else
		activities = PublicActivityConfig.GetAllActivities()
	end

	sendResult(player, {
		Kind = "Activities",
		Success = true,
		Message = "Activities loaded.",
		Activities = activities,
		Cooldowns = buildCooldownsForActivities(player.UserId, activities),
	})
end

local function handleGetCooldowns(player, payload)
	local publicRoomId = payload.PublicRoomId
	local activities

	if typeof(publicRoomId) == "string" and publicRoomId ~= "" then
		activities = PublicActivityConfig.GetActivitiesForPublicRoom(publicRoomId)
	else
		activities = PublicActivityConfig.GetAllActivities()
	end

	sendResult(player, {
		Kind = "Cooldowns",
		Success = true,
		Message = "Cooldowns loaded.",
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

	local remainingCooldown = getCooldownRemaining(player.UserId, activity.ActivityId)

	if remainingCooldown > 0 then
		sendResult(player, {
			Kind = "StartActivity",
			Success = false,
			Message = "Please wait before doing this activity again.",
			ActivityId = activity.ActivityId,
			Activity = activity,
			RemainingCooldown = remainingCooldown,
		})
		return
	end

	local validContext, contextMessage = validateActivityContext(player, activity)

	if not validContext then
		sendResult(player, {
			Kind = "StartActivity",
			Success = false,
			Message = contextMessage,
			ActivityId = activity.ActivityId,
			Activity = activity,
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
			Message = "Activity already started.",
			ActivityId = activity.ActivityId,
			Activity = activity,
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
		Message = "Activity started.",
		ActivityId = activity.ActivityId,
		Activity = activity,
		DurationSeconds = activity.DurationSeconds,
		RewardAmount = activity.RewardAmount,
		RewardCurrency = activity.RewardCurrency,
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
			Message = "No active activity attempt.",
			ActivityId = activity.ActivityId,
			Activity = activity,
		})
		return
	end

	local now = os.clock()

	if now - attempt.StartedAt < activity.DurationSeconds then
		sendResult(player, {
			Kind = "CompleteActivity",
			Success = false,
			Message = "Activity is not complete yet.",
			ActivityId = activity.ActivityId,
			Activity = activity,
		})
		return
	end

	if now > attempt.ExpiresAt then
		userAttempts[activity.ActivityId] = nil

		sendResult(player, {
			Kind = "CompleteActivity",
			Success = false,
			Message = "Activity attempt expired.",
			ActivityId = activity.ActivityId,
			Activity = activity,
		})
		return
	end

	local validContext, contextMessage = validateActivityContext(player, activity)

	if not validContext then
		sendResult(player, {
			Kind = "CompleteActivity",
			Success = false,
			Message = contextMessage,
			ActivityId = activity.ActivityId,
			Activity = activity,
		})
		return
	end

	userAttempts[activity.ActivityId] = nil

	local cooldownExpiresAt = now + activity.CooldownSeconds
	getUserActivityTable(cooldowns, player.UserId)[activity.ActivityId] = cooldownExpiresAt

	sendResult(player, {
		Kind = "CompleteActivity",
		Success = true,
		Message = "Activity complete. Rewards are not enabled yet.",
		ActivityId = activity.ActivityId,
		Activity = activity,
		RemainingCooldown = activity.CooldownSeconds,
		RewardAmount = activity.RewardAmount,
		RewardCurrency = activity.RewardCurrency,
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
			Message = "Unknown public activity action.",
		})
		return
	end

	if isRequestRateLimited(player, safeActionName) then
		sendResult(player, {
			Kind = safeActionName,
			Success = false,
			Message = "Please slow down before requesting activities.",
		})
		return
	end

	local safePayload = getSafePayload(payload)

	if safeActionName == "GetActivities" then
		handleGetActivities(player, safePayload)
	elseif safeActionName == "StartActivity" then
		handleStartActivity(player, safePayload)
	elseif safeActionName == "CompleteActivity" then
		handleCompleteActivity(player, safePayload)
	elseif safeActionName == "GetCooldowns" then
		handleGetCooldowns(player, safePayload)
	end
end

publicActivityRequest.OnServerEvent:Connect(function(player, actionName, payload)
	local success, errorMessage = pcall(function()
		handleRequest(player, actionName, payload)
	end)

	if not success then
		warn("PublicActivityServer request failed:", errorMessage)

		sendResult(player, {
			Kind = getSafeActionName(actionName),
			Success = false,
			Message = "Activity request failed.",
		})
	end
end)

Players.PlayerRemoving:Connect(function(player)
	activeAttempts[player.UserId] = nil
	cooldowns[player.UserId] = nil
	lastRequestByUserId[player.UserId] = nil
end)
