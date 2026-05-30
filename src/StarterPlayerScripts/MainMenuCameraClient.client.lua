local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local DEBUG_MAIN_MENU_CAMERA = true
local SCENE_FOLDER_NAME = "MainMenuScenes"
local SCENE_TEMPLATE_NAME = "HotelLobbyMainMenu"
local LOCAL_SCENE_NAME = "MainMenuSceneLocal"
local MAIN_MENU_SCENE_WORLD_CFRAME = CFrame.new(100000, 5000, 100000)

local CAMERA_FIELD_OF_VIEW = 50
local CAMERA_CONCIERGE_TWEEN_SECONDS = 2.5
local CAMERA_NAVIGATOR_TWEEN_SECONDS = 1.5

local FALLBACK_CFRAMES = {
	CameraStart = MAIN_MENU_SCENE_WORLD_CFRAME
		* CFrame.lookAt(Vector3.new(0, 7.2, 45), Vector3.new(0, 4.1, -24)),
	CameraConcierge = MAIN_MENU_SCENE_WORLD_CFRAME
		* CFrame.lookAt(Vector3.new(0, 6.6, 12), Vector3.new(0, 4.2, -22.2)),
	CameraNavigatorDesk = MAIN_MENU_SCENE_WORLD_CFRAME
		* CFrame.lookAt(Vector3.new(13.5, 7.25, -11.5), Vector3.new(10.5, 4.25, -21.6)),
}

local camera = Workspace.CurrentCamera
local sceneClone = nil
local activeTween = nil
local refreshQueued = false
local isActive = false
local isTweening = false
local activationSerial = 0
local holdCameraCFrame = nil
local missingSceneWarned = false
local missingMarkerWarned = {}

local function debugPrint(...)
	if DEBUG_MAIN_MENU_CAMERA then
		print("[MainMenuCameraClient]", ...)
	end
end

local function getCamera()
	camera = Workspace.CurrentCamera or camera
	return camera
end

local function setMainMenuCameraActive(active)
	if player:GetAttribute("MainMenuCameraActive") ~= active then
		player:SetAttribute("MainMenuCameraActive", active)
	end
end

local function setMainMenuIntroPlaying(playing)
	if player:GetAttribute("MainMenuIntroPlaying") ~= playing then
		player:SetAttribute("MainMenuIntroPlaying", playing)
	end
end

local function setMainMenuIntroComplete(complete)
	if player:GetAttribute("MainMenuIntroComplete") ~= complete then
		player:SetAttribute("MainMenuIntroComplete", complete)
	end
end

local function setMainMenuIntroState(playing, complete)
	setMainMenuIntroPlaying(playing == true)
	setMainMenuIntroComplete(complete == true)
end

local function applyCameraOwnership()
	local currentCamera = getCamera()

	if not currentCamera then
		return
	end

	currentCamera.CameraType = Enum.CameraType.Scriptable
	currentCamera.FieldOfView = CAMERA_FIELD_OF_VIEW

	if not isTweening and holdCameraCFrame then
		currentCamera.CFrame = holdCameraCFrame
	end
end

local function shouldUseMainMenuCamera()
	local currentRoomName = player:GetAttribute("CurrentRoomName")

	if currentRoomName ~= nil then
		return false
	end

	if player:GetAttribute("OnboardingStep") ~= "Complete" then
		return false
	end

	return player:GetAttribute("InHotelMainMenu") == true
		or currentRoomName == nil
end

local function destroyLocalScenes()
	for _, child in ipairs(Workspace:GetChildren()) do
		if child.Name == LOCAL_SCENE_NAME then
			debugPrint("Destroying old local scene", child:GetFullName())
			child:Destroy()
		end
	end

	sceneClone = nil
end

local function makeSceneClientSafe(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false

			if descendant:GetAttribute("MainMenuSceneMarker") == true then
				descendant.Transparency = 1
			end
		elseif descendant:IsA("BillboardGui") and descendant.Name == "MarkerLabel" then
			descendant.Enabled = false
		end
	end
end

local function getPartPosition(model, partName)
	local part = model:FindFirstChild(partName, true)

	if part and part:IsA("BasePart") then
		return part.Position
	end

	return nil
end

local function pivotSceneToIsolatedLocation(model)
	local anchor = model:FindFirstChild("MainMenuAnchor", true)

	if anchor and anchor:IsA("BasePart") then
		local currentPivot = model:GetPivot()
		local sceneOffset = MAIN_MENU_SCENE_WORLD_CFRAME * anchor.CFrame:Inverse()
		model:PivotTo(sceneOffset * currentPivot)
	else
		warn("MainMenuCameraClient: MainMenuAnchor is missing; using model pivot for isolated placement.")
		model:PivotTo(MAIN_MENU_SCENE_WORLD_CFRAME)
	end

	debugPrint("Scene placed at", MAIN_MENU_SCENE_WORLD_CFRAME.Position)
	debugPrint("CameraStart position", getPartPosition(model, "CameraStart"))
	debugPrint("CameraNavigatorDesk position", getPartPosition(model, "CameraNavigatorDesk"))
end

local function getSceneTemplate()
	local sceneFolder = ReplicatedStorage:FindFirstChild(SCENE_FOLDER_NAME)

	if not sceneFolder then
		if not missingSceneWarned then
			missingSceneWarned = true
			warn(
				"MainMenuCameraClient: ReplicatedStorage."
					.. SCENE_FOLDER_NAME
					.. " is missing. Run docs/tools/CreateMainMenuHotelLobbyScene.lua in Studio."
			)
		end

		return nil
	end

	local template = sceneFolder:FindFirstChild(SCENE_TEMPLATE_NAME)

	if not template or not template:IsA("Model") then
		if not missingSceneWarned then
			missingSceneWarned = true
			warn(
				"MainMenuCameraClient: "
					.. SCENE_TEMPLATE_NAME
					.. " template is missing. Run docs/tools/CreateMainMenuHotelLobbyScene.lua in Studio."
			)
		end

		return nil
	end

	debugPrint("Scene template found", template:GetFullName())
	return template
end

local function cloneScene()
	local template = getSceneTemplate()

	if not template then
		return nil
	end

	destroyLocalScenes()

	local clone = template:Clone()
	clone.Name = LOCAL_SCENE_NAME
	makeSceneClientSafe(clone)
	clone.Parent = Workspace
	pivotSceneToIsolatedLocation(clone)
	sceneClone = clone
	debugPrint("Scene cloned", clone:GetFullName())

	return clone
end

local function getMarkerCFrame(markerName)
	local marker = sceneClone and sceneClone:FindFirstChild(markerName, true)

	if marker and marker:IsA("BasePart") then
		debugPrint("Camera marker found", markerName, marker.CFrame)
		return marker.CFrame
	end

	if not missingMarkerWarned[markerName] then
		missingMarkerWarned[markerName] = true
		debugPrint("Camera marker missing", markerName)
		warn("MainMenuCameraClient: missing camera marker " .. markerName .. "; using fallback CFrame.")
	end

	return FALLBACK_CFRAMES[markerName]
end

local function cancelTween()
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
end

local function isCurrentActivation(serial)
	return isActive and activationSerial == serial and shouldUseMainMenuCamera()
end

local function tweenCameraTo(targetCFrame, durationSeconds, serial)
	local currentCamera = getCamera()

	if not currentCamera or not targetCFrame or not isCurrentActivation(serial) then
		return false
	end

	cancelTween()
	debugPrint("Camera tween starts", tostring(durationSeconds) .. "s", targetCFrame)

	local completed = false
	local playbackState = nil
	local tween = TweenService:Create(
		currentCamera,
		TweenInfo.new(durationSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{
			CFrame = targetCFrame,
		}
	)
	local completedConnection = tween.Completed:Connect(function(state)
		playbackState = state
		completed = true
	end)

	activeTween = tween
	isTweening = true
	tween:Play()

	while not completed do
		if not isCurrentActivation(serial) then
			tween:Cancel()
			break
		end

		task.wait()
	end

	completedConnection:Disconnect()

	if activeTween == tween then
		activeTween = nil
	end

	isTweening = false

	if isCurrentActivation(serial) then
		holdCameraCFrame = targetCFrame
		currentCamera.CameraType = Enum.CameraType.Scriptable
		currentCamera.FieldOfView = CAMERA_FIELD_OF_VIEW
		currentCamera.CFrame = targetCFrame
	end

	debugPrint("Camera tween finishes", tostring(playbackState))

	return isCurrentActivation(serial)
end

local function playIntro(serial)
	local currentCamera = getCamera()

	if not currentCamera or not sceneClone or not isCurrentActivation(serial) then
		if isCurrentActivation(serial) then
			setMainMenuIntroState(false, false)
		end

		return
	end

	setMainMenuIntroState(true, false)

	local startCFrame = getMarkerCFrame("CameraStart")
	local conciergeCFrame = getMarkerCFrame("CameraConcierge")
	local navigatorCFrame = getMarkerCFrame("CameraNavigatorDesk")

	holdCameraCFrame = startCFrame
	applyCameraOwnership()
	currentCamera.CFrame = startCFrame

	if not tweenCameraTo(conciergeCFrame, CAMERA_CONCIERGE_TWEEN_SECONDS, serial) then
		if isCurrentActivation(serial) then
			setMainMenuIntroState(false, false)
		end

		return
	end

	if tweenCameraTo(navigatorCFrame, CAMERA_NAVIGATOR_TWEEN_SECONDS, serial) then
		holdCameraCFrame = navigatorCFrame
		applyCameraOwnership()
		setMainMenuIntroState(false, true)
		debugPrint("Intro complete at CameraNavigatorDesk")
	elseif isCurrentActivation(serial) then
		setMainMenuIntroState(false, false)
	end
end

local function deactivate()
	if not isActive
		and not sceneClone
		and player:GetAttribute("MainMenuCameraActive") ~= true
		and player:GetAttribute("MainMenuIntroPlaying") ~= true
		and player:GetAttribute("MainMenuIntroComplete") ~= true then

		return
	end

	activationSerial += 1
	isActive = false
	isTweening = false
	holdCameraCFrame = nil
	cancelTween()
	destroyLocalScenes()
	setMainMenuCameraActive(false)
	setMainMenuIntroState(false, false)
	debugPrint("Cinematic deactivates")

	local currentCamera = getCamera()
	local currentRoomName = player:GetAttribute("CurrentRoomName")
	local controlMode = player:GetAttribute("ControlMode") or "Hotel"

	if currentCamera and currentRoomName == nil and controlMode ~= "Hotel" then
		currentCamera.CameraType = Enum.CameraType.Custom
	end
end

local function activate()
	if isActive and sceneClone then
		applyCameraOwnership()
		return
	end

	local clone = cloneScene()

	if not clone then
		deactivate()
		return
	end

	activationSerial += 1
	local serial = activationSerial
	isActive = true
	setMainMenuCameraActive(true)
	setMainMenuIntroState(true, false)
	debugPrint("Cinematic activates")

	task.spawn(function()
		playIntro(serial)
	end)
end

local function refresh()
	refreshQueued = false

	if shouldUseMainMenuCamera() then
		activate()
	else
		deactivate()
	end
end

local function scheduleRefresh()
	if refreshQueued then
		return
	end

	refreshQueued = true
	task.defer(refresh)
end

setMainMenuCameraActive(false)
setMainMenuIntroState(false, false)

RunService:BindToRenderStep(
	"MainMenuCameraClient",
	Enum.RenderPriority.Camera.Value + 2,
	function()
		if isActive and shouldUseMainMenuCamera() then
			applyCameraOwnership()
		end
	end
)

player:GetAttributeChangedSignal("InHotelMainMenu"):Connect(scheduleRefresh)
player:GetAttributeChangedSignal("CurrentRoomName"):Connect(scheduleRefresh)
player:GetAttributeChangedSignal("OnboardingStep"):Connect(scheduleRefresh)
player:GetAttributeChangedSignal("ControlMode"):Connect(scheduleRefresh)

local function observeSceneFolder(sceneFolder)
	if not sceneFolder or not sceneFolder:IsA("Folder") then
		return
	end

	sceneFolder.ChildAdded:Connect(function(child)
		if child.Name == SCENE_TEMPLATE_NAME then
			missingSceneWarned = false
			scheduleRefresh()
		end
	end)
end

observeSceneFolder(ReplicatedStorage:FindFirstChild(SCENE_FOLDER_NAME))

ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == SCENE_FOLDER_NAME then
		missingSceneWarned = false
		observeSceneFolder(child)
		scheduleRefresh()
	end
end)

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	camera = Workspace.CurrentCamera

	if isActive then
		applyCameraOwnership()
	end
end)

task.defer(scheduleRefresh)
