--Explorer/ServerScriptService/FurnitureClickServer.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local furnitureMenuRequest = remoteEvents:WaitForChild("FurnitureMenuRequest")

local activeRooms = workspace:WaitForChild("ActiveRooms")

local connectedClickDetectors = {}

local ignoredPartNames = {
	CollisionBuffer = true,
	SitPoint = true,
	SleepPoint = true,
	PlayPoint = true,
	EnterPoint = true,
	TalkPoint = true,
	ClickHitbox = true,
}

local function getCurrentRoomModel(player)
	local roomName = player:GetAttribute("CurrentRoomName")

	if not roomName then
		return nil
	end

	return activeRooms:FindFirstChild(roomName)
end

local function getFurnitureModelFromDescendant(instance)
	local current = instance

	while current and current ~= workspace do
		if current:IsA("Model") then
			local parent = current.Parent

			if parent and parent.Name == "Furniture" then
				return current
			end
		end

		current = current.Parent
	end

	return nil
end

local function getRoomModelFromDescendant(instance)
	local current = instance

	while current and current ~= workspace do
		if current:IsA("Model") and current.Parent == activeRooms then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function isFurnitureClickablePart(part)
	if not part:IsA("BasePart") then
		return false
	end

	if ignoredPartNames[part.Name] then
		return false
	end

	if part.Transparency >= 1 then
		return false
	end

	local furnitureModel = getFurnitureModelFromDescendant(part)

	if not furnitureModel then
		return false
	end

	return true
end

local function setupClickDetectorForPart(part)
	if not isFurnitureClickablePart(part) then
		return
	end

	local clickDetector = part:FindFirstChildOfClass("ClickDetector")

	if not clickDetector then
		clickDetector = Instance.new("ClickDetector")
		clickDetector.Parent = part
	end

	clickDetector.MaxActivationDistance = 100

	if connectedClickDetectors[clickDetector] then
		return
	end

	connectedClickDetectors[clickDetector] = true

	clickDetector.MouseClick:Connect(function(player)
		local furnitureModel = getFurnitureModelFromDescendant(part)
		local clickedRoom = getRoomModelFromDescendant(part)
		local playerRoom = getCurrentRoomModel(player)

		if not furnitureModel or not clickedRoom or not playerRoom then
			return
		end

		-- Security check:
		-- Player can only select furniture inside their current room.
		if clickedRoom ~= playerRoom then
			return
		end

		furnitureMenuRequest:FireClient(player, furnitureModel)
	end)
end

local function setupAllFurnitureClickDetectors()
	for _, descendant in ipairs(activeRooms:GetDescendants()) do
		setupClickDetectorForPart(descendant)
	end
end

setupAllFurnitureClickDetectors()

activeRooms.DescendantAdded:Connect(function(descendant)
	task.defer(function()
		setupClickDetectorForPart(descendant)

		-- When a whole furniture model is parented into the room,
		-- make sure all of its existing parts get ClickDetectors too.
		if descendant:IsA("Model") then
			for _, child in ipairs(descendant:GetDescendants()) do
				setupClickDetectorForPart(child)
			end
		end
	end)
end)