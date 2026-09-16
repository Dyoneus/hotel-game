-- Client-only lighting polish for public rooms.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local activeRooms = Workspace:WaitForChild("ActiveRooms")
local shared = ReplicatedStorage:WaitForChild("Shared")
local PublicRoomConfig = require(shared:WaitForChild("PublicRoomConfig"))

local originalLighting = {
	Ambient = Lighting.Ambient,
	OutdoorAmbient = Lighting.OutdoorAmbient,
	Brightness = Lighting.Brightness,
	ClockTime = Lighting.ClockTime,
	FogColor = Lighting.FogColor,
	FogStart = Lighting.FogStart,
	FogEnd = Lighting.FogEnd,
	ColorShift_Top = Lighting.ColorShift_Top,
	ColorShift_Bottom = Lighting.ColorShift_Bottom,
}

local LIGHTING_PRESETS = {
	WarmLounge = {
		Ambient = Color3.fromRGB(218, 209, 194),
		OutdoorAmbient = Color3.fromRGB(190, 181, 168),
		Brightness = 3,
		ClockTime = 15.75,
		FogColor = Color3.fromRGB(255, 242, 224),
		FogStart = 600,
		FogEnd = 2800,
		ColorShift_Top = Color3.fromRGB(255, 244, 222),
		ColorShift_Bottom = Color3.fromRGB(190, 172, 152),
	},

	CozyCafe = {
		Ambient = Color3.fromRGB(220, 206, 184),
		OutdoorAmbient = Color3.fromRGB(196, 181, 160),
		Brightness = 2.85,
		ClockTime = 15.25,
		FogColor = Color3.fromRGB(255, 241, 218),
		FogStart = 550,
		FogEnd = 2600,
		ColorShift_Top = Color3.fromRGB(255, 238, 211),
		ColorShift_Bottom = Color3.fromRGB(176, 150, 122),
	},

	Arcade = {
		Ambient = Color3.fromRGB(190, 201, 221),
		OutdoorAmbient = Color3.fromRGB(162, 174, 198),
		Brightness = 2.75,
		ClockTime = 14.5,
		FogColor = Color3.fromRGB(225, 233, 248),
		FogStart = 650,
		FogEnd = 3000,
		ColorShift_Top = Color3.fromRGB(220, 238, 255),
		ColorShift_Bottom = Color3.fromRGB(158, 154, 205),
	},
}

local activePresetName = nil
local refreshSerial = 0

local function applyLighting(values)
	for propertyName, value in pairs(values) do
		Lighting[propertyName] = value
	end
end

local function restoreOriginalLighting()
	activePresetName = nil
	applyLighting(originalLighting)
end

local function releaseLightingToPlayerRoomVoid()
	activePresetName = nil
	Lighting.Ambient = originalLighting.Ambient
	Lighting.OutdoorAmbient = originalLighting.OutdoorAmbient
	Lighting.Brightness = originalLighting.Brightness
	Lighting.ClockTime = originalLighting.ClockTime
	Lighting.ColorShift_Top = originalLighting.ColorShift_Top
	Lighting.ColorShift_Bottom = originalLighting.ColorShift_Bottom
end

local function getCurrentRoomName()
	local roomName = player:GetAttribute("CurrentRoomName")

	if typeof(roomName) ~= "string" or roomName == "" then
		return nil
	end

	return roomName
end

local function getCurrentRoomModel(roomName)
	if typeof(roomName) ~= "string" or roomName == "" then
		return nil
	end

	local roomModel = activeRooms:FindFirstChild(roomName)

	if roomModel and roomModel:IsA("Model") then
		return roomModel
	end

	return nil
end

local function getPublicRoomId(roomModel, roomName)
	if roomModel then
		local publicRoomId = roomModel:GetAttribute("PublicRoomId")

		if typeof(publicRoomId) == "string" and publicRoomId ~= "" then
			return publicRoomId
		end
	end

	if typeof(roomName) == "string" then
		local publicRoomId = string.match(roomName, "^Public_(.+)$")

		if typeof(publicRoomId) == "string" and publicRoomId ~= "" then
			return publicRoomId
		end
	end

	return nil
end

local function isPlayerRoom(roomModel, roomName)
	if roomModel then
		local roomType = roomModel:GetAttribute("RoomType")

		if roomType == "PlayerRoom" then
			return true
		end

		if roomType == "PublicSpace" then
			return false
		end
	end

	return typeof(roomName) == "string" and string.sub(roomName, 1, #"Room_") == "Room_"
end

local function getPresetName(publicRoomId)
	local roomConfig = PublicRoomConfig.GetPublicRoom(publicRoomId)

	if typeof(roomConfig) ~= "table" then
		return nil
	end

	local presetName = roomConfig.LightingPreset or roomConfig.AmbiencePreset

	if typeof(presetName) == "string" and LIGHTING_PRESETS[presetName] then
		return presetName
	end

	return nil
end

local function applyPublicRoomAmbience(publicRoomId)
	local presetName = getPresetName(publicRoomId)

	if not presetName then
		restoreOriginalLighting()
		return
	end

	local preset = LIGHTING_PRESETS[presetName]

	activePresetName = presetName
	applyLighting(preset)
end

local function refreshAmbience()
	refreshSerial += 1
	local thisRefresh = refreshSerial
	local controlMode = player:GetAttribute("ControlMode") or "Hotel"
	local roomName = getCurrentRoomName()
	local roomModel = getCurrentRoomModel(roomName)

	local publicRoomId = getPublicRoomId(roomModel, roomName)

	if publicRoomId then
		task.defer(function()
			if refreshSerial ~= thisRefresh then
				return
			end

			local latestRoomName = getCurrentRoomName()
			local latestRoomModel = getCurrentRoomModel(latestRoomName)

			if getPublicRoomId(latestRoomModel, latestRoomName) ~= publicRoomId then
				return
			end

			applyPublicRoomAmbience(publicRoomId)
		end)

		return
	end

	if isPlayerRoom(roomModel, roomName) then
		if controlMode ~= "Hotel" then
			restoreOriginalLighting()
			return
		end

		-- Player-room lighting is owned by HotelVoidBackgroundClient while in Hotel mode.
		releaseLightingToPlayerRoomVoid()
		return
	end

	restoreOriginalLighting()
end

player:GetAttributeChangedSignal("CurrentRoomName"):Connect(refreshAmbience)
player:GetAttributeChangedSignal("ControlMode"):Connect(refreshAmbience)

activeRooms.ChildAdded:Connect(function(child)
	if child.Name == getCurrentRoomName() then
		refreshAmbience()
	end
end)

activeRooms.ChildRemoved:Connect(function(child)
	if child.Name == getCurrentRoomName() then
		refreshAmbience()
	end
end)

script.Destroying:Connect(function()
	if activePresetName then
		restoreOriginalLighting()
	end
end)

refreshAmbience()
