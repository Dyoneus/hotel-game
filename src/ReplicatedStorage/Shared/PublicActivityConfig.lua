local PublicActivityConfig = {}

-- Public activity rewards are server-authoritative. Clients may request an
-- activity, but they must never decide reward amount, currency, or success.
-- Coins should not be used for normal public activity rewards.
local ACTIVITY_DEFINITIONS = {
	HelpDeskTask = {
		ActivityId = "HelpDeskTask",
		DisplayName = "Help Desk Task",
		Description = "Help the hotel desk for a small Dollar reward.",
		PublicRoomId = "WelcomeLounge",
		MarkerName = "HelpDeskActivity",
		DurationSeconds = 4,
		CooldownSeconds = 60,
		RewardCurrency = "Dollars",
		RewardAmount = 10,
		Enabled = true,
	},
}

local function copyActivity(activity)
	if typeof(activity) ~= "table" then
		return nil
	end

	return {
		ActivityId = activity.ActivityId,
		DisplayName = activity.DisplayName,
		Description = activity.Description,
		PublicRoomId = activity.PublicRoomId,
		MarkerName = activity.MarkerName,
		DurationSeconds = activity.DurationSeconds,
		CooldownSeconds = activity.CooldownSeconds,
		RewardCurrency = activity.RewardCurrency,
		RewardAmount = activity.RewardAmount,
		Enabled = activity.Enabled == true,
	}
end

local function copyActivityMap(activitiesById)
	local activityMap = {}

	for activityId, activity in pairs(activitiesById) do
		activityMap[activityId] = copyActivity(activity)
	end

	return activityMap
end

local function findActivity(activityId)
	if typeof(activityId) ~= "string" or activityId == "" then
		return nil
	end

	return ACTIVITY_DEFINITIONS[activityId]
end

function PublicActivityConfig.GetActivity(activityId)
	return copyActivity(findActivity(activityId))
end

function PublicActivityConfig.GetActivitiesForPublicRoom(publicRoomId)
	local activities = {}

	if typeof(publicRoomId) ~= "string" or publicRoomId == "" then
		return activities
	end

	for _, activity in pairs(ACTIVITY_DEFINITIONS) do
		if activity.PublicRoomId == publicRoomId then
			table.insert(activities, copyActivity(activity))
		end
	end

	table.sort(activities, function(a, b)
		return tostring(a.DisplayName or a.ActivityId) < tostring(b.DisplayName or b.ActivityId)
	end)

	return activities
end

function PublicActivityConfig.GetAllActivities()
	local activities = {}

	for _, activity in pairs(ACTIVITY_DEFINITIONS) do
		table.insert(activities, copyActivity(activity))
	end

	table.sort(activities, function(a, b)
		return tostring(a.DisplayName or a.ActivityId) < tostring(b.DisplayName or b.ActivityId)
	end)

	return activities
end

PublicActivityConfig.Activities = copyActivityMap(ACTIVITY_DEFINITIONS)

return PublicActivityConfig
