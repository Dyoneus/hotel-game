local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FADE_TIME = 0.28
local HOLD_TIME = 0.08
local DISPLAY_ORDER = 99990

local function getOrCreateClientEvent(name)
	local clientEvents = playerGui:FindFirstChild("ClientEvents")

	if clientEvents then
		if not clientEvents:IsA("Folder") then
			error("PlayerGui.ClientEvents exists but is not a Folder.")
		end
	else
		clientEvents = Instance.new("Folder")
		clientEvents.Name = "ClientEvents"
		clientEvents.Parent = playerGui
	end

	local existing = clientEvents:FindFirstChild(name)

	if existing then
		if not existing:IsA("BindableEvent") then
			error(name .. " exists but is not a BindableEvent.")
		end

		return existing
	end

	local event = Instance.new("BindableEvent")
	event.Name = name
	event.Parent = clientEvents

	return event
end

local transitionRequest = getOrCreateClientEvent("RoomTransitionRequest")
local transitionFinished = getOrCreateClientEvent("RoomTransitionFinished")

local gui = Instance.new("ScreenGui")
gui.Name = "RoomTransitionGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = DISPLAY_ORDER
gui.Enabled = true
gui.Parent = playerGui

local fadeFrame = Instance.new("Frame")
fadeFrame.Name = "Fade"
fadeFrame.Size = UDim2.fromScale(1, 1)
fadeFrame.BackgroundColor3 = Color3.new(0, 0, 0)
fadeFrame.BackgroundTransparency = 1
fadeFrame.BorderSizePixel = 0
fadeFrame.Visible = false
fadeFrame.Parent = gui

local activeTween = nil
local transitionSerial = 0
local lastRoomName = player:GetAttribute("CurrentRoomName")

local function parsePayload(payload)
	if typeof(payload) == "string" then
		return payload, FADE_TIME, HOLD_TIME
	end

	if typeof(payload) == "table" then
		local action = payload.Action or payload.Kind or payload[1]
		local duration = tonumber(payload.Duration) or FADE_TIME
		local hold = tonumber(payload.HoldTime) or HOLD_TIME

		return action, math.max(0, duration), math.max(0, hold)
	end

	return nil, FADE_TIME, HOLD_TIME
end

local function tweenFade(targetTransparency, duration, finishedAction)
	transitionSerial += 1
	local thisSerial = transitionSerial

	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end

	fadeFrame.Visible = true

	activeTween = TweenService:Create(
		fadeFrame,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			BackgroundTransparency = targetTransparency,
		}
	)

	activeTween.Completed:Connect(function()
		if transitionSerial ~= thisSerial then
			return
		end

		activeTween = nil

		if targetTransparency >= 1 then
			fadeFrame.Visible = false
		end

		if finishedAction then
			transitionFinished:Fire(finishedAction)
		end
	end)

	activeTween:Play()

	return thisSerial
end

local function fadeOut(duration)
	tweenFade(0, duration or FADE_TIME, "FadeOut")
end

local function fadeIn(duration)
	tweenFade(1, duration or FADE_TIME, "FadeIn")
end

local function fadeOutIn(duration, hold)
	local thisSerial = tweenFade(0, duration or FADE_TIME, "FadeOut")

	task.delay((duration or FADE_TIME) + (hold or HOLD_TIME), function()
		if transitionSerial == thisSerial then
			fadeIn(duration or FADE_TIME)
		end
	end)
end

transitionRequest.Event:Connect(function(payload)
	local action, duration, hold = parsePayload(payload)

	if action == "FadeOut" then
		fadeOut(duration)
	elseif action == "FadeIn" then
		fadeIn(duration)
	elseif action == "FadeOutIn" then
		fadeOutIn(duration, hold)
	end
end)

player:GetAttributeChangedSignal("CurrentRoomName"):Connect(function()
	local currentRoomName = player:GetAttribute("CurrentRoomName")

	if currentRoomName == lastRoomName then
		return
	end

	lastRoomName = currentRoomName

	if fadeFrame.Visible and fadeFrame.BackgroundTransparency < 0.98 then
		task.delay(0.08, function()
			if fadeFrame.Visible and fadeFrame.BackgroundTransparency < 0.98 then
				fadeIn(FADE_TIME)
			end
		end)
	end
end)
