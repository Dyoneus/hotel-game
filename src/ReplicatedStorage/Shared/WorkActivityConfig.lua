local WorkActivityConfig = {}

-- Work rewards are server-authoritative. Clients may request work activity
-- state, but they must never decide reward amount, currency, or success.
-- Coins should not be used for normal work rewards.
local ACTIVITY_DEFINITIONS = {
	HotelHelper = {
		ActivityId = "HotelHelper",
		DisplayName = "Hotel Helper",
		Description = "Complete a short helper task to earn Dollars.",
		DurationSeconds = 5,
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
		DurationSeconds = activity.DurationSeconds,
		CooldownSeconds = activity.CooldownSeconds,
		RewardCurrency = activity.RewardCurrency,
		RewardAmount = activity.RewardAmount,
		Enabled = activity.Enabled == true,
	}
end

local function findActivity(activityId)
	if typeof(activityId) ~= "string" or activityId == "" then
		return nil
	end

	return ACTIVITY_DEFINITIONS[activityId]
end

function WorkActivityConfig.GetActivity(activityId)
	return copyActivity(findActivity(activityId))
end

function WorkActivityConfig.GetAllActivities()
	local activities = {}

	for _, activity in pairs(ACTIVITY_DEFINITIONS) do
		table.insert(activities, copyActivity(activity))
	end

	table.sort(activities, function(a, b)
		return tostring(a.DisplayName or a.ActivityId) < tostring(b.DisplayName or b.ActivityId)
	end)

	return activities
end

return WorkActivityConfig
