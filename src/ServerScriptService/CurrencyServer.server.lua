-- ServerScriptService/CurrencyServer.lua
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

local currencyRequest = getOrCreateRemoteEvent("CurrencyRequest")
local currencyResult = getOrCreateRemoteEvent("CurrencyResult")

local REQUEST_COOLDOWN_SECONDS = 0.5
local lastRequestAtByUserId = {}

local function sendResult(player, payload)
	if not player or player.Parent ~= Players then
		return
	end

	payload = payload or {}
	payload.Kind = tostring(payload.Kind or "Unknown")
	payload.Success = payload.Success == true
	payload.Message = tostring(payload.Message or "")

	currencyResult:FireClient(player, payload)
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

currencyRequest.OnServerEvent:Connect(function(player, actionName, payload)
	if actionName == "GetDailyRewardStatus" then
		sendResult(player, {
			Kind = "DailyRewardStatus",
			Success = true,
			Status = RoomPersistence.GetDailyRewardStatus(player),
			Message = "Daily reward status loaded.",
		})
		return
	end

	if actionName == "ClaimDailyReward" then
		local success, message, rewardAmount, newDollarBalance, status =
			RoomPersistence.ClaimDailyReward(player)

		if success then
			sendResult(player, {
				Kind = "DailyRewardClaim",
				Success = true,
				Message = message or "Daily reward claimed.",
				RewardAmount = rewardAmount,
				NewCurrencyBalance = newDollarBalance,
				CurrencyKey = "Dollars",
				Status = status,
			})
		else
			sendResult(player, {
				Kind = "DailyRewardClaim",
				Success = false,
				Message = message or "Could not claim daily reward.",
				Status = status,
			})
		end

		return
	end

	if not checkCooldown(player) then
		sendResult(player, {
			Kind = "Coins",
			Success = false,
			Coins = RoomPersistence.GetCoins(player),
			Message = "Slow down before requesting currency.",
		})
		return
	end

	if actionName == "GetCoins" then
		sendResult(player, {
			Kind = "Coins",
			Success = true,
			Coins = RoomPersistence.GetCoins(player),
			Message = "Coins loaded.",
		})
		return
	end

	if actionName == "GetCurrencies" then
		sendResult(player, {
			Kind = "Currencies",
			Success = true,
			Currencies = RoomPersistence.GetCurrenciesSnapshot(player),
			Message = "Currencies loaded.",
		})
		return
	end

	if actionName == "GetCurrency" then
		if typeof(payload) ~= "table" then
			sendResult(player, {
				Kind = "Currency",
				Success = false,
				Message = "Invalid currency request.",
			})
			return
		end

		local currencyKey = payload.CurrencyKey
		local balance, message = RoomPersistence.GetCurrency(player, currencyKey)

		if typeof(balance) ~= "number" then
			sendResult(player, {
				Kind = "Currency",
				Success = false,
				CurrencyKey = currencyKey,
				Message = message or "Invalid currency key.",
			})
			return
		end

		sendResult(player, {
			Kind = "Currency",
			Success = true,
			CurrencyKey = currencyKey,
			Balance = balance,
			Message = "Currency loaded.",
		})
		return
	end

	sendResult(player, {
		Kind = "Unknown",
		Success = false,
		Message = "Unknown currency action.",
	})
end)

Players.PlayerRemoving:Connect(function(player)
	lastRequestAtByUserId[player.UserId] = nil
end)
