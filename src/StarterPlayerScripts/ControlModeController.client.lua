--Explorer/StarterPlayerScripts/ControlModeController
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local controls = nil

local function getControls()
	if controls then
		return controls
	end

	local playerScripts = player:WaitForChild("PlayerScripts")
	local playerModule = require(playerScripts:WaitForChild("PlayerModule"))

	controls = playerModule:GetControls()
	return controls
end

local function applyControlMode()
	local controlMode = player:GetAttribute("ControlMode")

	if controlMode == nil then
		controlMode = "Hotel"
		player:SetAttribute("ControlMode", controlMode)
	end

	local currentControls = getControls()

	if controlMode == "Hotel" then
		currentControls:Disable()
	elseif controlMode == "Minigame" then
		currentControls:Enable()
	else
		warn("Unknown ControlMode:", controlMode)
		currentControls:Disable()
	end
end

applyControlMode()

player:GetAttributeChangedSignal("ControlMode"):Connect(function()
	applyControlMode()
end)

player.CharacterAdded:Connect(function()
	task.wait(0.2)
	applyControlMode()
end)