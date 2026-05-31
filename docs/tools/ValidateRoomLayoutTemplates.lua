-- Studio helper: validate configured room layout templates.
--
-- Run this manually in Roblox Studio Command Bar or from a temporary Script.
-- The helper reads ReplicatedStorage.RoomTemplates and checks TemplateName
-- for available layouts from RoomLayoutConfig. It does not create, delete,
-- or modify instances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TOOL_PREFIX = "[RoomLayoutTemplateValidator]"

local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
local roomLayoutConfigModule = sharedFolder and sharedFolder:FindFirstChild("RoomLayoutConfig")

if not roomLayoutConfigModule or not roomLayoutConfigModule:IsA("ModuleScript") then
	error(TOOL_PREFIX .. " Missing ReplicatedStorage.Shared.RoomLayoutConfig.")
end

local success, RoomLayoutConfig = pcall(require, roomLayoutConfigModule)

if not success or typeof(RoomLayoutConfig) ~= "table" then
	error(TOOL_PREFIX .. " Could not require RoomLayoutConfig: " .. tostring(RoomLayoutConfig))
end

local roomTemplates = ReplicatedStorage:FindFirstChild("RoomTemplates")

if not roomTemplates then
	warn(TOOL_PREFIX .. " ReplicatedStorage.RoomTemplates is missing.")
end

local availableLayouts = RoomLayoutConfig.GetSelectableLayouts()
local unavailableLayouts = RoomLayoutConfig.GetUnavailableLayouts()
local vipLayouts = RoomLayoutConfig.GetVipLayouts()
local missingTemplates = 0

print(TOOL_PREFIX .. " Validating " .. tostring(#availableLayouts) .. " available room layout template(s).")

for _, layout in ipairs(availableLayouts) do
	local templateName = layout.TemplateName
	local template = roomTemplates and roomTemplates:FindFirstChild(templateName)

	if template then
		print(string.format(
			"[OK] %s template=%s",
			tostring(layout.LayoutId),
			tostring(templateName)
		))
	else
		missingTemplates += 1
		warn(string.format(
			"[WARN] %s missing template=%s",
			tostring(layout.LayoutId),
			tostring(templateName)
		))
	end
end

print(string.format(
	"%s Summary: available layouts=%d missing templates=%d VIP layouts=%d unavailable layouts=%d",
	TOOL_PREFIX,
	#availableLayouts,
	missingTemplates,
	#vipLayouts,
	#unavailableLayouts
))
