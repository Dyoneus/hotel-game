-- Explorer/ServerScriptService/RoomModeServer.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local setRoomModeRequest = remoteEvents:WaitForChild("SetRoomModeRequest")
local roomModeResult = remoteEvents:WaitForChild("RoomModeResult")

local activeRooms = workspace:WaitForChild("ActiveRooms")
local RoomPermissionService = require(ServerScriptService:WaitForChild("RoomPermissionService"))

local VALID_ROOM_MODES = {
	Play = true,
	Edit = true,
}

local REQUEST_COOLDOWN_SECONDS = 0.5
local lastRequestAtByUserId = {}

local function getCurrentRoomModel(player)
	local roomName = player:GetAttribute("CurrentRoomName")

	if typeof(roomName) ~= "string" or roomName == "" then
		return nil
	end

	local roomModel = activeRooms:FindFirstChild(roomName)

	if not roomModel or not roomModel:IsA("Model") then
		return nil
	end

	return roomModel
end

local function sendResult(player, success, message, roomMode)
	if not player or player.Parent ~= Players then
		return
	end

	roomModeResult:FireClient(
		player,
		success == true,
		tostring(message or ""),
		roomMode or player:GetAttribute("RoomMode") or "Play"
	)
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

local function setRoomMode(player, requestedMode)
	if typeof(requestedMode) ~= "string" then
		sendResult(player, false, "Invalid room mode.")
		return
	end

	if not VALID_ROOM_MODES[requestedMode] then
		sendResult(player, false, "Invalid room mode.")
		return
	end

	local roomModel = getCurrentRoomModel(player)

	if not roomModel then
		player:SetAttribute("RoomMode", "Play")
		sendResult(player, false, "You are not inside a valid room.", "Play")
		return
	end

	-- Anyone can return to Play mode. This prevents players from getting stuck.
	if requestedMode == "Play" then
		player:SetAttribute("RoomMode", "Play")
		sendResult(player, true, "Returned to Play Mode.", "Play")
		return
	end

	-- Edit mode is owner-only and only after onboarding is complete.
	if requestedMode == "Edit" then
		if player:GetAttribute("OnboardingStep") ~= "Complete" then
			player:SetAttribute("RoomMode", "Play")
			sendResult(player, false, "Finish onboarding before editing your room.", "Play")
			return
		end

		if not RoomPermissionService.CanEditRoom(player, roomModel) then
			player:SetAttribute("RoomMode", "Play")
			sendResult(player, false, "You do not have permission to edit this room.", "Play")
			return
		end

		player:SetAttribute("RoomMode", "Edit")
		sendResult(player, true, "Entered Edit Mode.", "Edit")
		return
	end
end

setRoomModeRequest.OnServerEvent:Connect(function(player, requestedMode)
	if not checkCooldown(player) then
		sendResult(player, false, "Slow down before changing room mode.")
		return
	end

	setRoomMode(player, requestedMode)
end)

Players.PlayerAdded:Connect(function(player)
	player:GetAttributeChangedSignal("CurrentRoomName"):Connect(function()
		-- Joining or leaving rooms should always drop the player back to Play mode.
		player:SetAttribute("RoomMode", "Play")
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	lastRequestAtByUserId[player.UserId] = nil
end)
