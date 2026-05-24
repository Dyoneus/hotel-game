-- ServerScriptService/InventoryServer.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

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

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remoteEvents

	return remote
end

local inventoryRequest = getOrCreateRemoteEvent("InventoryRequest")
local inventoryResult = getOrCreateRemoteEvent("InventoryResult")

local REQUEST_COOLDOWN_SECONDS = 0.5
local lastRequestAtByUserId = {}

local function sendResult(player, kind, success, message, inventory, inventoryDetails)
	if not player or player.Parent ~= Players then
		return
	end

	inventoryResult:FireClient(player, {
		Kind = tostring(kind or "Inventory"),
		Success = success == true,
		Inventory = inventory or {},
		InventoryDetails = inventoryDetails or {},
		Message = tostring(message or ""),
	})
end

local function checkCooldown(player)
	local now = os.clock()
	local previous = lastRequestAtByUserId[player.UserId]

	if previous and now - previous < REQUEST_COOLDOWN_SECONDS then
		return false
	end

	lastRequestAtByUserId[player.UserId] = now
	return true
end

inventoryRequest.OnServerEvent:Connect(function(player, actionName)
	if not checkCooldown(player) then
		sendResult(player, "Inventory", false, "Slow down before requesting inventory.")
		return
	end

	if actionName == "GetInventory" then
		local snapshot = RoomPersistence.GetInventorySnapshot(player)
		local detailsSnapshot = RoomPersistence.GetInventoryDetailsSnapshot(player)

		sendResult(player, "Inventory", true, "Inventory loaded.", snapshot, detailsSnapshot)
		return
	end

	sendResult(player, "Unknown", false, "Unknown inventory action.")
end)

Players.PlayerRemoving:Connect(function(player)
	lastRequestAtByUserId[player.UserId] = nil
end)
