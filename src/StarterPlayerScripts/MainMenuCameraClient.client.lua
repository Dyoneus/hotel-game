local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local mainMenuIntroCompleteRequest = remoteEvents:WaitForChild("MainMenuIntroCompleteRequest")

local DEBUG_MAIN_MENU_CAMERA = true
local SCENE_FOLDER_NAME = "MainMenuScenes"
local SCENE_TEMPLATE_NAME = "HotelLobbyMainMenu"
local LOCAL_SCENE_NAME = "MainMenuSceneLocal"
local MAIN_MENU_SCENE_WORLD_CFRAME = CFrame.new(100000, 5000, 100000)

local CAMERA_FIELD_OF_VIEW = 50
local CAMERA_CONCIERGE_TWEEN_SECONDS = 2.5
local CAMERA_NAVIGATOR_TWEEN_SECONDS = 1.5
local CAMERA_VIEW_TWEEN_SECONDS = 0.85
local RETURNING_INTRO_TWEEN_SECONDS = 0.9
local ENTRANCE_DOOR_TWEEN_SECONDS = 1.25
local ENTRANCE_DOOR_CAMERA_DELAY_SECONDS = 0.35
local IDLE_CAMERA_SWAY_POSITION = 0.045
local IDLE_CAMERA_SWAY_ROTATION = math.rad(0.28)
local CONCIERGE_SUBTITLE_DELAY_SECONDS = 1.05
local CONCIERGE_SUBTITLE_DURATION_SECONDS = 2.6
local CONCIERGE_WELCOME_SUBTITLE = "Welcome to the Hotel. The Navigator is ready for you."
local CONCIERGE_CHECK_IN_SUBTITLE = "Welcome to the Hotel. Let's get you checked in."
local CONCIERGE_VOICE_SOUND_ID = "" -- Future placeholder: use only an owned/approved Roblox audio asset.

local INTRO_VARIANT_FIRST_VISIT = "FirstVisit"
local INTRO_VARIANT_FIRST_VISIT_ONBOARDING = "FirstVisitOnboarding"
local INTRO_VARIANT_RETURNING = "Returning"
local VIEW_NAVIGATOR = "Navigator"
local VIEW_WORK = "Work"

local FALLBACK_CFRAMES = {
	CameraStart = MAIN_MENU_SCENE_WORLD_CFRAME
		* CFrame.lookAt(Vector3.new(0, 7.2, 45), Vector3.new(0, 4.1, -24)),
	CameraConcierge = MAIN_MENU_SCENE_WORLD_CFRAME
		* CFrame.lookAt(Vector3.new(0, 6.6, 12), Vector3.new(0, 4.2, -22.2)),
	CameraNavigatorDesk = MAIN_MENU_SCENE_WORLD_CFRAME
		* CFrame.lookAt(Vector3.new(13.5, 7.25, -11.5), Vector3.new(10.5, 4.25, -21.6)),
	CameraWorkDesk = MAIN_MENU_SCENE_WORLD_CFRAME
		* CFrame.lookAt(Vector3.new(-13.5, 7.25, -11.5), Vector3.new(-10.5, 4.25, -21.6)),
}

local camera = Workspace.CurrentCamera
local sceneClone = nil
local activeTween = nil
local activeDoorTweens = {}
local activeTweenSerial = 0
local refreshQueued = false
local isActive = false
local isTweening = false
local activationSerial = 0
local holdCameraCFrame = nil
local idleBaseCFrame = nil
local idleStartedAt = 0
local missingSceneWarned = false
local missingMarkerWarned = {}
local missingDoorWarned = {}
local isCurrentActivation = nil

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

	local bindableEvent = Instance.new("BindableEvent")
	bindableEvent.Name = name
	bindableEvent.Parent = clientEvents

	return bindableEvent
end

local mainMenuCameraViewRequest = getOrCreateClientEvent("MainMenuCameraViewRequest")
local mainMenuSubtitleRequest = getOrCreateClientEvent("MainMenuSubtitleRequest")

local function debugPrint(...)
	if DEBUG_MAIN_MENU_CAMERA then
		print("[MainMenuCameraClient]", ...)
	end
end

local function getCamera()
	camera = Workspace.CurrentCamera or camera
	return camera
end

local function getIntroVariant()
	if player:GetAttribute("MainMenuIntroVariant") == INTRO_VARIANT_FIRST_VISIT_ONBOARDING then
		return INTRO_VARIANT_FIRST_VISIT_ONBOARDING
	end

	if player:GetAttribute("MainMenuIntroVariant") == INTRO_VARIANT_FIRST_VISIT then
		return INTRO_VARIANT_FIRST_VISIT
	end

	return INTRO_VARIANT_RETURNING
end

local function setHoldCameraCFrame(cframe)
	holdCameraCFrame = cframe
	idleBaseCFrame = cframe
	idleStartedAt = os.clock()
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

local function requestSubtitleHide()
	mainMenuSubtitleRequest:Fire({
		Action = "Hide",
	})
end

local function requestSubtitleShow(text, durationSeconds)
	mainMenuSubtitleRequest:Fire({
		Action = "Show",
		Text = text,
		DurationSeconds = durationSeconds,
		SoundId = CONCIERGE_VOICE_SOUND_ID,
	})
end

local function requestConciergeSubtitle(serial)
	task.delay(CONCIERGE_SUBTITLE_DELAY_SECONDS, function()
		if not isCurrentActivation(serial)
			or player:GetAttribute("MainMenuIntroPlaying") ~= true
			or player:GetAttribute("MainMenuIntroComplete") == true then

			return
		end

		requestSubtitleShow(CONCIERGE_WELCOME_SUBTITLE, CONCIERGE_SUBTITLE_DURATION_SECONDS)
	end)
end

local function setMainMenuView(viewName)
	if player:GetAttribute("MainMenuView") ~= viewName then
		player:SetAttribute("MainMenuView", viewName)
	end
end

local function clearMainMenuView()
	if player:GetAttribute("MainMenuView") ~= nil then
		player:SetAttribute("MainMenuView", nil)
	end
end

local function applyCameraOwnership()
	local currentCamera = getCamera()

	if not currentCamera then
		return
	end

	currentCamera.CameraType = Enum.CameraType.Scriptable
	currentCamera.FieldOfView = CAMERA_FIELD_OF_VIEW

	if not isTweening and holdCameraCFrame then
		if player:GetAttribute("MainMenuIntroComplete") == true and idleBaseCFrame then
			local elapsed = os.clock() - idleStartedAt
			local offsetX = math.sin(elapsed * 0.55) * IDLE_CAMERA_SWAY_POSITION
			local offsetY = math.sin(elapsed * 0.37) * IDLE_CAMERA_SWAY_POSITION * 0.35
			local yaw = math.sin(elapsed * 0.42) * IDLE_CAMERA_SWAY_ROTATION
			local pitch = math.sin(elapsed * 0.31) * IDLE_CAMERA_SWAY_ROTATION * 0.45

			currentCamera.CFrame = idleBaseCFrame
				* CFrame.new(offsetX, offsetY, 0)
				* CFrame.Angles(pitch, yaw, 0)
		else
			currentCamera.CFrame = holdCameraCFrame
		end
	end
end

local function shouldUseMainMenuCamera()
	local currentRoomName = player:GetAttribute("CurrentRoomName")

	if currentRoomName ~= nil then
		return false
	end

	local introVariant = getIntroVariant()
	local isFirstVisitIntro = (
			introVariant == INTRO_VARIANT_FIRST_VISIT
			or introVariant == INTRO_VARIANT_FIRST_VISIT_ONBOARDING
		)
		and player:GetAttribute("InHotelMainMenu") == true

	if player:GetAttribute("OnboardingStep") ~= "Complete" and not isFirstVisitIntro then
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

local function cancelDoorTweens()
	for _, tween in ipairs(activeDoorTweens) do
		tween:Cancel()
	end

	table.clear(activeDoorTweens)
end

isCurrentActivation = function(serial)
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
	activeTweenSerial = serial
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

	if activeTweenSerial == serial then
		isTweening = false
	end

	if isCurrentActivation(serial) then
		setHoldCameraCFrame(targetCFrame)
		currentCamera.CameraType = Enum.CameraType.Scriptable
		currentCamera.FieldOfView = CAMERA_FIELD_OF_VIEW
		currentCamera.CFrame = targetCFrame
	end

	debugPrint("Camera tween finishes", tostring(playbackState))

	return isCurrentActivation(serial)
end

local function getDoorPart(partName)
	local part = sceneClone and sceneClone:FindFirstChild(partName, true)

	if part and part:IsA("BasePart") then
		return part
	end

	if DEBUG_MAIN_MENU_CAMERA and not missingDoorWarned[partName] then
		missingDoorWarned[partName] = true
		warn("MainMenuCameraClient: missing entrance door part " .. partName .. "; skipping door animation.")
	end

	return nil
end

local function createDoorTween(doorName, openMarkerName)
	local doorPart = getDoorPart(doorName)
	local openMarker = getDoorPart(openMarkerName)

	if not doorPart or not openMarker then
		return nil
	end

	local tween = TweenService:Create(
		doorPart,
		TweenInfo.new(ENTRANCE_DOOR_TWEEN_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{
			CFrame = openMarker.CFrame,
		}
	)

	table.insert(activeDoorTweens, tween)

	return tween
end

local function playEntranceDoorOpenAnimation(serial)
	if not sceneClone or not isCurrentActivation(serial) then
		return false
	end

	cancelDoorTweens()

	local leftTween = createDoorTween("EntranceDoorLeft", "EntranceDoorLeftOpen")
	local rightTween = createDoorTween("EntranceDoorRight", "EntranceDoorRightOpen")

	if not leftTween and not rightTween then
		return false
	end

	debugPrint("Entrance door animation starts")

	if leftTween then
		leftTween:Play()
	end

	if rightTween then
		rightTween:Play()
	end

	return true
end

local function waitDuringActivation(seconds, serial)
	local endsAt = os.clock() + seconds

	while os.clock() < endsAt do
		if not isCurrentActivation(serial) then
			return false
		end

		task.wait()
	end

	return true
end

local function playFirstVisitIntro(serial)
	local currentCamera = getCamera()

	if not currentCamera or not sceneClone or not isCurrentActivation(serial) then
		if isCurrentActivation(serial) then
			setMainMenuIntroState(false, false)
		end

		return
	end

	setMainMenuIntroState(true, false)
	requestSubtitleHide()
	requestConciergeSubtitle(serial)

	local startCFrame = getMarkerCFrame("CameraStart")
	local conciergeCFrame = getMarkerCFrame("CameraConcierge")
	local navigatorCFrame = getMarkerCFrame("CameraNavigatorDesk")

	setHoldCameraCFrame(startCFrame)
	applyCameraOwnership()
	currentCamera.CFrame = startCFrame

	if not tweenCameraTo(conciergeCFrame, CAMERA_CONCIERGE_TWEEN_SECONDS, serial) then
		if isCurrentActivation(serial) then
			requestSubtitleHide()
			setMainMenuIntroState(false, false)
		end

		return
	end

	if tweenCameraTo(navigatorCFrame, CAMERA_NAVIGATOR_TWEEN_SECONDS, serial) then
		setHoldCameraCFrame(navigatorCFrame)
		applyCameraOwnership()
		setMainMenuView(VIEW_NAVIGATOR)
		requestSubtitleHide()
		setMainMenuIntroState(false, true)
		mainMenuIntroCompleteRequest:FireServer()
		debugPrint("First-visit intro complete at CameraNavigatorDesk")
	elseif isCurrentActivation(serial) then
		requestSubtitleHide()
		setMainMenuIntroState(false, false)
	end
end

local function playFirstVisitOnboardingIntro(serial)
	local currentCamera = getCamera()

	if not currentCamera or not sceneClone or not isCurrentActivation(serial) then
		if isCurrentActivation(serial) then
			setMainMenuIntroState(false, false)
		end

		return
	end

	setMainMenuIntroState(true, false)
	requestSubtitleHide()
	clearMainMenuView()

	local startCFrame = getMarkerCFrame("CameraStart")
	local conciergeCFrame = getMarkerCFrame("CameraConcierge")

	setHoldCameraCFrame(startCFrame)
	applyCameraOwnership()
	currentCamera.CFrame = startCFrame

	if playEntranceDoorOpenAnimation(serial)
		and not waitDuringActivation(ENTRANCE_DOOR_CAMERA_DELAY_SECONDS, serial) then

		return
	end

	if not tweenCameraTo(conciergeCFrame, CAMERA_CONCIERGE_TWEEN_SECONDS, serial) then
		if isCurrentActivation(serial) then
			requestSubtitleHide()
			setMainMenuIntroState(false, false)
		end

		return
	end

	requestSubtitleShow(CONCIERGE_CHECK_IN_SUBTITLE, CONCIERGE_SUBTITLE_DURATION_SECONDS)

	local subtitleEndsAt = os.clock() + CONCIERGE_SUBTITLE_DURATION_SECONDS

	while os.clock() < subtitleEndsAt do
		if not isCurrentActivation(serial) then
			return
		end

		task.wait()
	end

	if isCurrentActivation(serial) then
		requestSubtitleHide()
		setHoldCameraCFrame(conciergeCFrame)
		applyCameraOwnership()
		setMainMenuIntroState(false, true)
		mainMenuIntroCompleteRequest:FireServer()
		debugPrint("First-visit onboarding intro complete at CameraConcierge")
	end
end

local function playReturningIntro(serial)
	local currentCamera = getCamera()

	if not currentCamera or not sceneClone or not isCurrentActivation(serial) then
		if isCurrentActivation(serial) then
			setMainMenuIntroState(false, false)
		end

		return
	end

	setMainMenuIntroState(true, false)
	requestSubtitleHide()

	local navigatorCFrame = getMarkerCFrame("CameraNavigatorDesk")
	local driftStartCFrame = navigatorCFrame
		* CFrame.new(0.35, 0.08, 0.25)
		* CFrame.Angles(math.rad(-0.6), math.rad(1), 0)

	setHoldCameraCFrame(driftStartCFrame)
	applyCameraOwnership()
	currentCamera.CFrame = driftStartCFrame

	if tweenCameraTo(navigatorCFrame, RETURNING_INTRO_TWEEN_SECONDS, serial) then
		setHoldCameraCFrame(navigatorCFrame)
		applyCameraOwnership()
		setMainMenuView(VIEW_NAVIGATOR)
		setMainMenuIntroState(false, true)
		debugPrint("Returning intro complete at CameraNavigatorDesk")
	elseif isCurrentActivation(serial) then
		setMainMenuIntroState(false, false)
	end
end

local function playIntro(serial)
	local introVariant = getIntroVariant()

	if introVariant == INTRO_VARIANT_FIRST_VISIT_ONBOARDING then
		playFirstVisitOnboardingIntro(serial)
	elseif introVariant == INTRO_VARIANT_FIRST_VISIT then
		playFirstVisitIntro(serial)
	else
		playReturningIntro(serial)
	end
end

local function deactivate()
	if not isActive
		and not sceneClone
		and player:GetAttribute("MainMenuCameraActive") ~= true
		and player:GetAttribute("MainMenuIntroPlaying") ~= true
		and player:GetAttribute("MainMenuIntroComplete") ~= true
		and player:GetAttribute("MainMenuView") == nil then

		return
	end

	activationSerial += 1
	isActive = false
	isTweening = false
	holdCameraCFrame = nil
	idleBaseCFrame = nil
	idleStartedAt = 0
	cancelTween()
	cancelDoorTweens()
	destroyLocalScenes()
	setMainMenuCameraActive(false)
	setMainMenuIntroState(false, false)
	requestSubtitleHide()
	clearMainMenuView()
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
	idleBaseCFrame = nil
	idleStartedAt = 0
	setMainMenuCameraActive(true)
	setMainMenuIntroState(true, false)
	clearMainMenuView()
	debugPrint("Cinematic activates", getIntroVariant())

	task.spawn(function()
		playIntro(serial)
	end)
end

local function getViewMarkerName(viewName)
	if viewName == VIEW_WORK then
		return "CameraWorkDesk"
	end

	if viewName == VIEW_NAVIGATOR then
		return "CameraNavigatorDesk"
	end

	return nil
end

local function requestView(viewName)
	local markerName = getViewMarkerName(viewName)

	if not markerName then
		return
	end

	if not isActive
		or not sceneClone
		or not shouldUseMainMenuCamera()
		or player:GetAttribute("MainMenuIntroPlaying") == true
		or player:GetAttribute("MainMenuIntroComplete") ~= true then

		return
	end

	activationSerial += 1
	local serial = activationSerial
	local markerCFrame = getMarkerCFrame(markerName)

	if not markerCFrame then
		return
	end

	setMainMenuView(viewName)
	debugPrint("View switch requested", viewName)

	task.spawn(function()
		if tweenCameraTo(markerCFrame, CAMERA_VIEW_TWEEN_SECONDS, serial) then
			setHoldCameraCFrame(markerCFrame)
			applyCameraOwnership()
			setMainMenuView(viewName)
			debugPrint("View switch complete", viewName)
		end
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
clearMainMenuView()

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
player:GetAttributeChangedSignal("MainMenuIntroVariant"):Connect(scheduleRefresh)

mainMenuCameraViewRequest.Event:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	requestView(payload.View)
end)

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
