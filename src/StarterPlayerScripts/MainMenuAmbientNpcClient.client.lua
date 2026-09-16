local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local DEBUG_MAIN_MENU_NPCS = false
local LOCAL_SCENE_NAME = "MainMenuSceneLocal"
local AMBIENT_NPC_PREFIX = "AmbientNPC_"

local LOBBY_MIN_X = -39
local LOBBY_MAX_X = 39
local LOBBY_MIN_Z = -32
local LOBBY_MAX_Z = 31

local activeRun = nil

local function debugPrint(...)
	if DEBUG_MAIN_MENU_NPCS then
		print("[MainMenuAmbientNpcClient]", ...)
	end
end

local function getFirstBasePart(instance)
	if instance:IsA("BasePart") then
		return instance
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function makeModelVisualOnly(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
end

local function isRunActive(run)
	return activeRun == run
		and run.Active == true
		and run.Scene ~= nil
		and run.Scene.Parent ~= nil
end

local function waitWhileActive(run, seconds)
	local endTime = os.clock() + seconds

	while isRunActive(run) and os.clock() < endTime do
		task.wait(math.min(0.15, endTime - os.clock()))
	end
end

local function clampLobbyLocalPosition(localPosition)
	return Vector3.new(
		math.clamp(localPosition.X, LOBBY_MIN_X, LOBBY_MAX_X),
		localPosition.Y,
		math.clamp(localPosition.Z, LOBBY_MIN_Z, LOBBY_MAX_Z)
	)
end

local function getSceneAnchorCFrame(scene)
	local anchor = scene:FindFirstChild("MainMenuAnchor", true)

	if anchor and anchor:IsA("BasePart") then
		return anchor.CFrame
	end

	return scene:GetPivot()
end

local function localLookAt(run, localPosition, localTarget)
	local position = run.AnchorCFrame:PointToWorldSpace(localPosition)
	local target = run.AnchorCFrame:PointToWorldSpace(localTarget)
	local flatTarget = Vector3.new(target.X, position.Y, target.Z)

	if (flatTarget - position).Magnitude < 0.05 then
		flatTarget = position + run.AnchorCFrame.LookVector
	end

	return CFrame.lookAt(position, flatTarget)
end

local function createPivotController(run, model)
	local pivotValue = Instance.new("CFrameValue")
	pivotValue.Name = "MainMenuNpcPivot"
	pivotValue.Value = model:GetPivot()
	pivotValue.Parent = nil

	local controller = {
		Model = model,
		PivotValue = pivotValue,
		Tween = nil,
		Connection = nil,
	}

	controller.Connection = pivotValue:GetPropertyChangedSignal("Value"):Connect(function()
		if isRunActive(run) and model:IsDescendantOf(run.Scene) then
			model:PivotTo(pivotValue.Value)
		end
	end)

	table.insert(run.Controllers, controller)

	return controller
end

local function cleanupController(controller)
	if controller.Tween then
		controller.Tween:Cancel()
		controller.Tween = nil
	end

	if controller.Connection then
		controller.Connection:Disconnect()
		controller.Connection = nil
	end

	if controller.PivotValue then
		controller.PivotValue:Destroy()
		controller.PivotValue = nil
	end
end

local function tweenModel(run, controller, targetCFrame, durationSeconds)
	if not isRunActive(run) or not controller.Model:IsDescendantOf(run.Scene) then
		return false
	end

	if controller.Tween then
		controller.Tween:Cancel()
		controller.Tween = nil
	end

	controller.PivotValue.Value = controller.Model:GetPivot()

	local tween = TweenService:Create(
		controller.PivotValue,
		TweenInfo.new(durationSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{
			Value = targetCFrame,
		}
	)

	controller.Tween = tween
	tween:Play()
	local playbackState = tween.Completed:Wait()

	if controller.Tween == tween then
		controller.Tween = nil
	end

	return playbackState == Enum.PlaybackState.Completed and isRunActive(run)
end

local function getAmbientNpcIndex(model)
	local suffix = string.match(model.Name, "^" .. AMBIENT_NPC_PREFIX .. "(%d+)$")
	return tonumber(suffix) or 1
end

local function isNearDeskCameraLane(localPosition)
	return localPosition.Z > -18
		and localPosition.Z < -5
		and math.abs(localPosition.X) < 22
end

local function startAmbientNpcLoop(run, model)
	if not getFirstBasePart(model) then
		return
	end

	makeModelVisualOnly(model)

	local index = getAmbientNpcIndex(model)
	local controller = createPivotController(run, model)
	local originCFrame = model:GetPivot()
	local originLocal = run.AnchorCFrame:PointToObjectSpace(originCFrame.Position)
	local nearCameraLane = isNearDeskCameraLane(originLocal)
	local stride = nearCameraLane and 0.65 or (2.2 + (index % 3) * 0.45)
	local side = index % 2 == 0 and 1 or -1
	local forward = math.floor(index / 2) % 2 == 0 and 1 or -1
	local deskLocal = Vector3.new(0, originLocal.Y, -24)

	local offsets = {
		Vector3.new(side * stride, 0, forward * stride * 0.55),
		Vector3.new(side * stride * 0.45, 0, -forward * stride * 0.65),
		Vector3.new(-side * stride * 0.75, 0, forward * stride * 0.35),
		Vector3.new(0, 0, 0),
	}

	task.spawn(function()
		waitWhileActive(run, 0.25 + (index % 9) * 0.22)

		local stepIndex = 1

		while isRunActive(run) and model:IsDescendantOf(run.Scene) do
			local offset = offsets[((stepIndex - 1) % #offsets) + 1]
			local targetLocal = clampLobbyLocalPosition(originLocal + offset)
			local faceLocal = stepIndex % 2 == 0 and originLocal or deskLocal
			local targetCFrame = localLookAt(run, targetLocal, faceLocal)
			local distance = (model:GetPivot().Position - targetCFrame.Position).Magnitude
			local duration = math.clamp(distance / 2.2, 0.7, 2.5)

			tweenModel(run, controller, targetCFrame, duration)
			waitWhileActive(run, 0.75 + (index % 4) * 0.28)

			local idleAngle = ((index + stepIndex) % 2 == 0) and 5 or -5
			tweenModel(run, controller, targetCFrame * CFrame.Angles(0, math.rad(idleAngle), 0), 0.7)
			waitWhileActive(run, 0.35 + (index % 3) * 0.18)

			stepIndex += 1
		end
	end)
end

local function startConciergeIdle(run, model)
	if not model or not model:IsA("Model") or not getFirstBasePart(model) then
		return
	end

	makeModelVisualOnly(model)

	local controller = createPivotController(run, model)
	local originCFrame = model:GetPivot()
	local idleAngles = { -4, 2, 0, 3, -2, 0 }

	task.spawn(function()
		waitWhileActive(run, 0.5)

		local index = 1

		while isRunActive(run) and model:IsDescendantOf(run.Scene) do
			local angle = idleAngles[((index - 1) % #idleAngles) + 1]
			tweenModel(run, controller, originCFrame * CFrame.Angles(0, math.rad(angle), 0), 1.1)
			waitWhileActive(run, 0.65)
			index += 1
		end
	end)
end

local function cleanupRun(run)
	if not run or run.Cleaned then
		return
	end

	run.Cleaned = true
	run.Active = false

	for _, connection in ipairs(run.Connections) do
		connection:Disconnect()
	end

	for _, controller in ipairs(run.Controllers) do
		cleanupController(controller)
	end

	if activeRun == run then
		activeRun = nil
	end

	debugPrint("Stopped NPC ambience")
end

local function findAmbientNpcContainer(scene)
	local container = scene:FindFirstChild("AmbientNPCs", true)

	if container and (container:IsA("Folder") or container:IsA("Model")) then
		return container
	end

	return nil
end

local function startScene(scene)
	if activeRun and activeRun.Scene == scene and activeRun.Active then
		return
	end

	if activeRun then
		cleanupRun(activeRun)
	end

	if not scene or not scene:IsA("Model") then
		return
	end

	local run = {
		Scene = scene,
		AnchorCFrame = getSceneAnchorCFrame(scene),
		Active = true,
		Cleaned = false,
		Connections = {},
		Controllers = {},
	}

	activeRun = run

	table.insert(run.Connections, scene.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanupRun(run)
		end
	end))

	local ambientContainer = findAmbientNpcContainer(scene)

	if ambientContainer then
		for _, child in ipairs(ambientContainer:GetChildren()) do
			if child:IsA("Model") and string.sub(child.Name, 1, #AMBIENT_NPC_PREFIX) == AMBIENT_NPC_PREFIX then
				startAmbientNpcLoop(run, child)
			end
		end
	end

	local conciergeNpc = scene:FindFirstChild("ConciergeNPC", true)
	startConciergeIdle(run, conciergeNpc)

	debugPrint("Started NPC ambience")
end

local function syncScene()
	local scene = Workspace:FindFirstChild(LOCAL_SCENE_NAME)

	if scene and scene:IsA("Model") then
		startScene(scene)
	elseif activeRun then
		cleanupRun(activeRun)
	end
end

Workspace.ChildAdded:Connect(function(child)
	if child.Name == LOCAL_SCENE_NAME then
		task.defer(syncScene)
	end
end)

Workspace.ChildRemoved:Connect(function(child)
	if activeRun and activeRun.Scene == child then
		cleanupRun(activeRun)
	end
end)

task.defer(syncScene)
