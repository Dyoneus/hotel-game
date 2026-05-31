-- Run this script from Roblox Studio Command Bar.
-- It inspects ReplicatedStorage.FurnitureTemplates and does not modify instances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local furnitureTemplates = ReplicatedStorage:FindFirstChild("FurnitureTemplates")

local function logOk(templateName, message)
	print("[OK]", templateName, message)
end

local function logWarn(templateName, message)
	warn("[WARN] " .. templateName .. " - " .. message)
end

local function logError(templateName, message)
	warn("[ERROR] " .. templateName .. " - " .. message)
end

local function isPositiveInteger(value)
	return typeof(value) == "number"
		and value == value
		and value > 0
		and value < math.huge
		and math.floor(value) == value
end

local function isNonNegativeInteger(value)
	return typeof(value) == "number"
		and value == value
		and value >= 0
		and value < math.huge
		and math.floor(value) == value
end

local function hasNamedDescendant(root, descendantName)
	return root:FindFirstChild(descendantName, true) ~= nil
end

local function hasSeat(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Seat") or descendant:IsA("VehicleSeat") then
			return true
		end
	end

	return false
end

local function permissionActionsIncludeOpenClose(value)
	if typeof(value) ~= "string" then
		return false
	end

	for actionName in string.gmatch(value, "[^,%s;]+") do
		if actionName == "OpenClose" then
			return true
		end
	end

	return false
end

local function validateTemplate(model)
	local templateName = model.Name
	local hasError = false

	if model:GetAttribute("AutoCatalogEnabled") ~= true then
		return
	end

	if not isPositiveInteger(model:GetAttribute("Price")) then
		logError(templateName, "Price must be a positive integer.")
		hasError = true
	end

	if model:GetAttribute("CurrencyKey") ~= "Dollars" then
		logError(templateName, "CurrencyKey must be \"Dollars\" for this patch.")
		hasError = true
	end

	if not isNonNegativeInteger(model:GetAttribute("SellPrice") or 0) then
		logWarn(templateName, "SellPrice should be a non-negative integer.")
	end

	if not isPositiveInteger(model:GetAttribute("FootprintWidth")) then
		logWarn(templateName, "FootprintWidth should be a positive integer.")
	end

	if not isPositiveInteger(model:GetAttribute("FootprintDepth")) then
		logWarn(templateName, "FootprintDepth should be a positive integer.")
	end

	if not hasNamedDescendant(model, "PlacementBounds") then
		logWarn(templateName, "Missing PlacementBounds part.")
	end

	if model:GetAttribute("DefaultAction") == "Sit" then
		if not hasNamedDescendant(model, "SitPoint") then
			logWarn(templateName, "DefaultAction is Sit but SitPoint is missing.")
		end

		if not hasSeat(model) then
			logWarn(templateName, "DefaultAction is Sit but no Seat or VehicleSeat was found.")
		end
	end

	if model:GetAttribute("SupportsOpenClose") == true then
		if not permissionActionsIncludeOpenClose(model:GetAttribute("PermissionActions")) then
			logWarn(templateName, "SupportsOpenClose is true but PermissionActions does not include OpenClose.")
		end

		local targetName = model:GetAttribute("OpenCloseTargetName")

		if typeof(targetName) ~= "string" or targetName == "" then
			logWarn(templateName, "SupportsOpenClose is true but OpenCloseTargetName is missing.")
		elseif not hasNamedDescendant(model, targetName) then
			logWarn(templateName, "OpenCloseTargetName target was not found: " .. targetName)
		end
	end

	if not hasError then
		logOk(templateName, "Auto-catalog attributes are valid enough to load.")
	end
end

if not furnitureTemplates then
	warn("[ERROR] ReplicatedStorage.FurnitureTemplates was not found.")
	return
end

local checkedCount = 0

for _, child in ipairs(furnitureTemplates:GetChildren()) do
	if child:IsA("Model") and child:GetAttribute("AutoCatalogEnabled") == true then
		checkedCount += 1
		validateTemplate(child)
	end
end

print("[OK] ValidateFurnitureTemplates complete. Auto-catalog templates checked:", checkedCount)
