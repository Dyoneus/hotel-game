--Explorer/ServerScriptService/PlayerRoomServer.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TextService = game:GetService("TextService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local RoomPersistence = require(ServerScriptService:WaitForChild("RoomPersistence"))
local RoomPermissionService = require(ServerScriptService:WaitForChild("RoomPermissionService"))
local PublicRoomConfig = require(sharedFolder:WaitForChild("PublicRoomConfig"))
local RoomTextPolicyConfig = require(sharedFolder:WaitForChild("RoomTextPolicyConfig"))
local GridConfig = require(sharedFolder:WaitForChild("GridConfig"))

local playerRooms = {}
local playerRoomSlots = {}
local nextRoomSlot = 0

local roomCreationInFlightByUserId = {}

local roomTemplates = ReplicatedStorage:WaitForChild("RoomTemplates")
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local function getOrCreateRemoteEvent(name)
	local existing = remoteEvents:FindFirstChild(name)

	if existing then
		if not existing:IsA("RemoteEvent") then
			error(name .. " exists but is not a RemoteEvent.")
		end

		return existing
	end

	local remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = name
	remoteEvent.Parent = remoteEvents

	return remoteEvent
end

local createRoomRequest = remoteEvents:WaitForChild("CreateRoomRequest")
local roomCreationResult = remoteEvents:WaitForChild("RoomCreationResult")
local characterCreationFinished = remoteEvents:WaitForChild("CharacterCreationFinished")
local roomListRequest = remoteEvents:WaitForChild("RoomListRequest")
local roomListUpdate = remoteEvents:WaitForChild("RoomListUpdate")
local joinRoomRequest = remoteEvents:WaitForChild("JoinRoomRequest")
local joinRoomResult = remoteEvents:WaitForChild("JoinRoomResult")
local roomSettingsRequest = getOrCreateRemoteEvent("RoomSettingsRequest")
local roomSettingsResult = getOrCreateRemoteEvent("RoomSettingsResult")
local roomNavigatorRequest = getOrCreateRemoteEvent("RoomNavigatorRequest")
local roomNavigatorResult = getOrCreateRemoteEvent("RoomNavigatorResult")
local leaveRoomRequest = getOrCreateRemoteEvent("LeaveRoomRequest")
local leaveRoomResult = getOrCreateRemoteEvent("LeaveRoomResult")
local mainMenuIntroCompleteRequest = getOrCreateRemoteEvent("MainMenuIntroCompleteRequest")
local roomPermissionRequest = getOrCreateRemoteEvent("RoomPermissionRequest")
local roomPermissionResult = getOrCreateRemoteEvent("RoomPermissionResult")

local tutorialFinishedRequest = remoteEvents:WaitForChild("TutorialFinishedRequest")

local activeRooms = workspace:WaitForChild("ActiveRooms")

local VALID_LAYOUTS = {
	Layout_01 = true,
	Layout_02 = true,
	Layout_03 = true,
}
local PRIMARY_ROOM_ID = "Primary"

local ROOM_DISPLAY_NAME_MAX_LENGTH = 30
local ROOM_DESCRIPTION_MAX_LENGTH = 100
local ROOM_SETTINGS_COOLDOWN_SECONDS = 1
local ROOM_USERNAME_LOOKUP_COOLDOWN_SECONDS = 2
local BLOCKED_ROOM_TEXT_POLICY = RoomTextPolicyConfig.BlockedTerms or {}
local ROOM_TEXT_CONTEXT_TERMS = RoomTextPolicyConfig.ContextTerms or {}
local ROOM_TEXT_COMBINATION_RULES = RoomTextPolicyConfig.CombinationRules or {}
local ROOM_TEXT_LEET_REPLACEMENTS = RoomTextPolicyConfig.LeetReplacements or {}

local PLAYER_ROOM_ZONE_ORIGIN = Vector3.new(0, 0, 0)
local PLAYER_ROOM_SPACING = 1000
local PUBLIC_ROOM_ZONE_ORIGIN = Vector3.new(100000, 0, 0)
local PUBLIC_ROOM_SPACING = 10000
-- Public rooms are intentionally isolated from player rooms. Large public
-- spaces should set WorldPosition and FootprintRadius in PublicRoomConfig.
local MAIN_MENU_HOLDING_AREA_NAME = "MainMenuHoldingArea"
local MAIN_MENU_HOLDING_PLATFORM_NAME = "MainMenuHoldingPlatform"
local MAIN_MENU_HOLDING_SPAWN_NAME = "MainMenuHoldingSpawn"
local MAIN_MENU_HOLDING_POSITION = Vector3.new(0, -500, 0)
local MAIN_MENU_HOLDING_CHARACTER_Y_OFFSET = 2.5
local MAIN_MENU_INTRO_FIRST_VISIT = "FirstVisit"
local MAIN_MENU_INTRO_FIRST_VISIT_ONBOARDING = "FirstVisitOnboarding"
local MAIN_MENU_INTRO_RETURNING = "Returning"

local playerRooms = {}
local playerRoomSlots = {}
local nextRoomSlot = 0
local roomSettingsLastRequestAtByUserId = {}
local roomPermissionLastRequestAtByUserId = {}
local roomUsernameLookupLastRequestAtByUserId = {}

local function getRoomName(player)
	return "Room_" .. player.UserId
end

local function getRoomPositionForPlayer(player)
	if not playerRoomSlots[player] then
		nextRoomSlot += 1
		playerRoomSlots[player] = nextRoomSlot
	end

	local slot = playerRoomSlots[player]

	return PLAYER_ROOM_ZONE_ORIGIN + Vector3.new((slot - 1) * PLAYER_ROOM_SPACING, 0, 0)
end

local function trimRoomText(value)
	if typeof(value) ~= "string" then
		return value
	end

	return value:match("^%s*(.-)%s*$") or ""
end

local function normalizeRoomTextForPolicy(text)
	if typeof(text) ~= "string" then
		return ""
	end

	local normalizedCharacters = {}

	for character in string.lower(text):gmatch(".") do
		character = ROOM_TEXT_LEET_REPLACEMENTS[character] or character

		if character:match("%w") then
			table.insert(normalizedCharacters, character)
		end
	end

	return table.concat(normalizedCharacters)
end

local function collapseRepeatedCharacters(text)
	if typeof(text) ~= "string" or text == "" then
		return ""
	end

	local collapsed = {}
	local previousCharacter = nil

	for character in text:gmatch(".") do
		if character ~= previousCharacter then
			table.insert(collapsed, character)
			previousCharacter = character
		end
	end

	return table.concat(collapsed)
end

local function normalizedTextContainsTerm(normalizedText, collapsedText, term)
	local normalizedTerm = normalizeRoomTextForPolicy(term)
	local collapsedTerm = collapseRepeatedCharacters(normalizedTerm)

	if normalizedTerm == "" then
		return false
	end

	return string.find(normalizedText, normalizedTerm, 1, true) ~= nil
		or string.find(collapsedText, normalizedTerm, 1, true) ~= nil
		or (collapsedTerm ~= "" and string.find(normalizedText, collapsedTerm, 1, true) ~= nil)
		or (collapsedTerm ~= "" and string.find(collapsedText, collapsedTerm, 1, true) ~= nil)
end

local function normalizedTextContainsAnyTerm(normalizedText, collapsedText, terms)
	for _, term in ipairs(terms) do
		if normalizedTextContainsTerm(normalizedText, collapsedText, term) then
			return true
		end
	end

	return false
end

local function containsBlockedRoomText(text)
	if typeof(text) ~= "string" or text == "" then
		return false
	end

	local normalizedText = normalizeRoomTextForPolicy(text)
	local collapsedText = collapseRepeatedCharacters(normalizedText)

	if normalizedText == "" then
		return false
	end

	for category, blockedTerms in pairs(BLOCKED_ROOM_TEXT_POLICY) do
		for _, blockedTerm in ipairs(blockedTerms) do
			if normalizedTextContainsTerm(normalizedText, collapsedText, blockedTerm) then
				return true, category
			end
		end
	end

	return false
end

local function warnRoomTextRejected(player, stage, reasonCategory, textLength)
	warn(string.format(
		"Room text rejected: userId=%s stage=%s category=%s length=%d",
		tostring(player and player.UserId or "unknown"),
		tostring(stage or "Unknown"),
		tostring(reasonCategory or "Policy"),
		tonumber(textLength) or 0
	))
end

local function validateRoomTextPolicy(displayName, description)
	local safeDisplayName = typeof(displayName) == "string" and trimRoomText(displayName) or ""
	local safeDescription = typeof(description) == "string" and trimRoomText(description) or ""
	local combinedText = safeDisplayName .. " " .. safeDescription
	local normalizedText = normalizeRoomTextForPolicy(combinedText)
	local collapsedText = collapseRepeatedCharacters(normalizedText)

	if normalizedText == "" then
		return true, nil, nil, 0
	end

	for category, blockedTerms in pairs(BLOCKED_ROOM_TEXT_POLICY) do
		if normalizedTextContainsAnyTerm(normalizedText, collapsedText, blockedTerms) then
			return false, "Room text is not appropriate for public rooms.", category, #combinedText
		end
	end

	local matchedContexts = {}

	for contextName, contextTerms in pairs(ROOM_TEXT_CONTEXT_TERMS) do
		if typeof(contextTerms) == "table" then
			matchedContexts[contextName] =
				normalizedTextContainsAnyTerm(normalizedText, collapsedText, contextTerms)
		end
	end

	for _, rule in ipairs(ROOM_TEXT_COMBINATION_RULES) do
		if typeof(rule) == "table" then
			local allContexts = rule.AllContexts
			local ruleMatched = typeof(allContexts) == "table" and #allContexts > 0

			if ruleMatched then
				for _, contextName in ipairs(allContexts) do
					if not matchedContexts[contextName] then
						ruleMatched = false
						break
					end
				end
			end

			if ruleMatched and typeof(rule.AnyTerms) == "table" and #rule.AnyTerms > 0 then
				ruleMatched = normalizedTextContainsAnyTerm(normalizedText, collapsedText, rule.AnyTerms)
			end

			if ruleMatched then
				return false,
					"Room text is not appropriate for public rooms.",
					rule.Category or rule.Name or "CombinationRule",
					#combinedText
			end
		end
	end

	return true, nil, nil, #combinedText
end

local function hasFilterReplacementCharacters(text)
	return typeof(text) == "string" and string.find(text, "#", 1, true) ~= nil
end

local function filterRoomTextForNavigator(player, rawText, fieldName, maxLength, allowEmpty)
	if typeof(rawText) ~= "string" then
		return false, fieldName .. " must be text."
	end

	local text = trimRoomText(rawText)

	if text == "" and not allowEmpty then
		return false, fieldName .. " cannot be empty."
	end

	if #text > maxLength then
		return false, fieldName .. " too long. Maximum " .. tostring(maxLength) .. " characters."
	end

	local rawBlocked, rawBlockedCategory = containsBlockedRoomText(text)

	if rawBlocked then
		warnRoomTextRejected(player, fieldName .. "Raw", rawBlockedCategory, #text)
		return false, "Room text contains blocked words."
	end

	if text == "" then
		return true, nil, ""
	end

	local success, filteredText = pcall(function()
		local filterResult = TextService:FilterStringAsync(
			text,
			player.UserId,
			Enum.TextFilterContext.PublicChat
		)

		return filterResult:GetNonChatStringForBroadcastAsync()
	end)

	if not success or typeof(filteredText) ~= "string" then
		warn("Room text filtering failed:", filteredText)
		return false, "Could not filter room text. Please try again."
	end

	filteredText = trimRoomText(filteredText)

	if filteredText == "" and not allowEmpty then
		return false, fieldName .. " was blocked by filtering."
	end

	if hasFilterReplacementCharacters(filteredText) then
		warnRoomTextRejected(player, fieldName .. "Filtered", "RobloxFilterReplacement", #filteredText)
		return false, "Room text could not be used. Please try different wording."
	end

	if #filteredText > maxLength then
		return false, fieldName .. " too long. Maximum " .. tostring(maxLength) .. " characters."
	end

	local filteredBlocked, filteredBlockedCategory = containsBlockedRoomText(filteredText)

	if filteredBlocked then
		warnRoomTextRejected(player, fieldName .. "Filtered", filteredBlockedCategory, #filteredText)
		return false, "Room text contains blocked words."
	end

	return true, nil, filteredText
end

local function isRoomSettingsRequestRateLimited(player)
	local now = os.clock()
	local lastRequestAt = roomSettingsLastRequestAtByUserId[player.UserId]

	if lastRequestAt and now - lastRequestAt < ROOM_SETTINGS_COOLDOWN_SECONDS then
		return true
	end

	roomSettingsLastRequestAtByUserId[player.UserId] = now

	return false
end

local function isRoomPermissionRequestRateLimited(player)
	local now = os.clock()
	local lastRequestAt = roomPermissionLastRequestAtByUserId[player.UserId]

	if lastRequestAt and now - lastRequestAt < ROOM_SETTINGS_COOLDOWN_SECONDS then
		return true
	end

	roomPermissionLastRequestAtByUserId[player.UserId] = now

	return false
end

local function isUsernameLookupRateLimited(player)
	local now = os.clock()
	local lastRequestAt = roomUsernameLookupLastRequestAtByUserId[player.UserId]

	if lastRequestAt and now - lastRequestAt < ROOM_USERNAME_LOOKUP_COOLDOWN_SECONDS then
		return true
	end

	roomUsernameLookupLastRequestAtByUserId[player.UserId] = now

	return false
end

local function normalizeTargetUserId(value)
	local numericUserId = nil

	if typeof(value) == "number" then
		numericUserId = value
	elseif typeof(value) == "string" then
		numericUserId = tonumber(trimRoomText(value))
	end

	if typeof(numericUserId) ~= "number"
		or numericUserId ~= numericUserId
		or numericUserId <= 0
		or numericUserId >= math.huge
		or numericUserId ~= math.floor(numericUserId) then

		return nil
	end

	return math.floor(numericUserId)
end

local function resolveUserInputToUserId(player, inputText)
	local targetUserId = normalizeTargetUserId(inputText)

	if targetUserId then
		return targetUserId, nil, nil
	end

	if typeof(inputText) ~= "string" then
		return nil, "Invalid user.", nil
	end

	local username = trimRoomText(inputText)

	if username == "" or #username < 3 or #username > 20 then
		return nil, "Invalid user.", nil
	end

	if isUsernameLookupRateLimited(player) then
		return nil, "Please wait before searching another user.", nil
	end

	local success, resolvedUserId = pcall(function()
		return Players:GetUserIdFromNameAsync(username)
	end)

	if not success or typeof(resolvedUserId) ~= "number" or resolvedUserId <= 0 then
		return nil, "User not found.", nil
	end

	return math.floor(resolvedUserId), nil, username
end

local function getPermissionTargetInput(payload)
	if typeof(payload) ~= "table" then
		return nil
	end

	if payload.TargetUserInput ~= nil then
		return payload.TargetUserInput
	end

	return payload.TargetUserId
end

local function getResolvedUserName(userId, fallbackName)
	local targetPlayer = Players:GetPlayerByUserId(userId)

	if targetPlayer then
		return targetPlayer.Name
	end

	if typeof(fallbackName) == "string" and fallbackName ~= "" then
		return fallbackName
	end

	return nil
end

local function targetUserIsCurrentPlayer(player, targetUserId, inputText, resolvedInputName)
	if targetUserId == player.UserId then
		return true
	end

	local inputName = resolvedInputName

	if not inputName and typeof(inputText) == "string" and not normalizeTargetUserId(inputText) then
		inputName = trimRoomText(inputText)
	end

	if typeof(inputName) == "string"
		and inputName ~= ""
		and string.lower(inputName) == string.lower(player.Name) then

		return true
	end

	if player.UserId <= 0 and targetUserId > 0 and not resolvedInputName then
		local success, resolvedPlayerUserId = pcall(function()
			return Players:GetUserIdFromNameAsync(player.Name)
		end)

		if success and resolvedPlayerUserId == targetUserId then
			return true
		end
	end

	return false
end

local function getPublicRoomActiveName(publicRoomId)
	return "Public_" .. publicRoomId
end

local function getPublicRoomIndex(publicRoomId, config)
	local sortOrder = config.SortOrder

	if typeof(sortOrder) == "number"
		and sortOrder == math.floor(sortOrder)
		and sortOrder > 0
		and sortOrder < math.huge then

		return sortOrder
	end

	local rooms = PublicRoomConfig.GetPublicRoomsArray()

	for index, room in ipairs(rooms) do
		if room.Id == publicRoomId then
			return index
		end
	end

	return 1
end

local function getRoomPositionForPublicRoom(publicRoomId, config)
	if typeof(config.WorldPosition) == "Vector3" then
		return config.WorldPosition
	end

	local publicIndex = getPublicRoomIndex(publicRoomId, config)

	return PUBLIC_ROOM_ZONE_ORIGIN + Vector3.new((publicIndex - 1) * PUBLIC_ROOM_SPACING, 0, 0)
end

local function removePlayerRoom(player)
	local existingRoom = playerRooms[player]

	if existingRoom and existingRoom.Parent then
		existingRoom:Destroy()
	end

	playerRooms[player] = nil
	playerRoomSlots[player] = nil
end

local function moveRoomAnchorToPosition(roomModel, targetAnchorPosition)
	local roomAnchor = roomModel:FindFirstChild("RoomAnchor", true)

	if not roomAnchor or not roomAnchor:IsA("BasePart") then
		warn("Room is missing RoomAnchor:", roomModel.Name)
		return false
	end

	local currentPivot = roomModel:GetPivot()
	local offset = targetAnchorPosition - roomAnchor.Position

	roomModel:PivotTo(currentPivot + offset)

	return true
end

local function warnRoomGridValidation(roomModel, context)
	local _, warnings = GridConfig.ValidateRoomGrid(roomModel)

	if typeof(warnings) ~= "table" or #warnings == 0 then
		return
	end

	for _, warningMessage in ipairs(warnings) do
		warn(string.format(
			"[RoomGrid] %s %s: %s",
			tostring(context or "Room"),
			tostring(roomModel and roomModel.Name or "unknown"),
			tostring(warningMessage)
		))
	end
end

local function removeEditorHelpers(roomModel)
	local editorHelpers = roomModel:FindFirstChild("EditorHelpers")

	if editorHelpers then
		editorHelpers:Destroy()
	end
end

local function cloneRoomForPlayer(player, layoutId)
	if not VALID_LAYOUTS[layoutId] then
		warn("Invalid layout requested:", layoutId)
		return nil
	end

	local template = roomTemplates:FindFirstChild(layoutId)

	if not template then
		warn("Missing room template:", layoutId)
		return nil
	end

	removePlayerRoom(player)

	local roomClone = template:Clone()
	roomClone.Name = getRoomName(player)
	roomClone.Parent = activeRooms
	
	if not roomClone:IsA("Model") then
		warn("Room template must be a Model, not a Folder:", layoutId)
		roomClone:Destroy()
		return nil
	end

	removeEditorHelpers(roomClone)

	local roomOffset = getRoomPositionForPlayer(player)
	print("Room anchor position for", player.Name, "=", roomOffset)

	local moved = moveRoomAnchorToPosition(roomClone, roomOffset)

	if not moved then
		roomClone:Destroy()
		return nil
	end

	roomClone:SetAttribute("OwnerUserId", player.UserId)
	roomClone:SetAttribute("LayoutId", layoutId)
	roomClone:SetAttribute("RoomType", "PlayerRoom")
	roomClone:SetAttribute("RoomId", PRIMARY_ROOM_ID)
	warnRoomGridValidation(roomClone, "PlayerRoom")

	playerRooms[player] = roomClone
	
	return roomClone
end

local function setCurrentRoomContextAttributes(player, roomType, ownerUserId, roomId)
	player:SetAttribute("CurrentRoomType", roomType)
	player:SetAttribute("CurrentRoomOwnerUserId", ownerUserId)
	player:SetAttribute("CurrentRoomId", roomId)
end

local function setCurrentPlayerRoomContext(player, ownerUserId, roomId)
	setCurrentRoomContextAttributes(
		player,
		"PlayerRoom",
		ownerUserId,
		roomId or PRIMARY_ROOM_ID
	)
end

local function setCurrentPublicRoomContext(player, publicRoomId)
	setCurrentRoomContextAttributes(player, "PublicSpace", 0, publicRoomId)
end

local function movePlayerToRoom(player, roomModel)
	local character = player.Character or player.CharacterAdded:Wait()

	local doorSpawn = roomModel:FindFirstChild("DoorSpawn", true)

	if not doorSpawn or not doorSpawn:IsA("BasePart") then
		warn("Room is missing DoorSpawn:", roomModel.Name)
		return
	end

	character:PivotTo(doorSpawn.CFrame)
end

local function getPlayerRootPart(player)
	local character = player.Character

	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function configureHoldingPart(part, size, cframe, canCollide)
	part.Anchored = true
	part.CanCollide = canCollide == true
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = size
	part.CFrame = cframe
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function getOrCreateHoldingPart(parent, name, size, cframe, canCollide)
	local existing = parent:FindFirstChild(name)
	local part = existing

	if part and not part:IsA("BasePart") then
		part:Destroy()
		part = nil
	end

	if not part then
		part = Instance.new("Part")
		part.Name = name
		part.Parent = parent
	end

	configureHoldingPart(part, size, cframe, canCollide)

	return part
end

local function getOrCreateMainMenuHoldingArea()
	local holdingArea = workspace:FindFirstChild(MAIN_MENU_HOLDING_AREA_NAME)

	if holdingArea and not holdingArea:IsA("Folder") then
		warn("Main Menu holding area name is occupied by a non-Folder instance.")
		return nil, nil
	end

	if not holdingArea then
		holdingArea = Instance.new("Folder")
		holdingArea.Name = MAIN_MENU_HOLDING_AREA_NAME
		holdingArea.Parent = workspace
	end

	getOrCreateHoldingPart(
		holdingArea,
		MAIN_MENU_HOLDING_PLATFORM_NAME,
		Vector3.new(80, 1, 80),
		CFrame.new(MAIN_MENU_HOLDING_POSITION),
		true
	)

	local spawnPart = getOrCreateHoldingPart(
		holdingArea,
		MAIN_MENU_HOLDING_SPAWN_NAME,
		Vector3.new(2, 1, 2),
		CFrame.new(MAIN_MENU_HOLDING_POSITION + Vector3.new(0, 4, 0)),
		false
	)

	return holdingArea, spawnPart
end

local function getCharacterForParking(player)
	local character = player.Character
	local deadline = os.clock() + 3

	while not character and player.Parent == Players and os.clock() < deadline do
		task.wait(0.05)
		character = player.Character
	end

	return character
end

local function clearCharacterVelocities(character)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function parkCharacterInMainMenu(player)
	local _, holdingSpawn = getOrCreateMainMenuHoldingArea()

	if not holdingSpawn then
		return false
	end

	local character = getCharacterForParking(player)

	if not character then
		return false
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not rootPart or not rootPart:IsA("BasePart") then
		rootPart = character:WaitForChild("HumanoidRootPart", 3)
	end

	if not rootPart or not rootPart:IsA("BasePart") then
		warn("Could not park character in Main Menu; missing HumanoidRootPart:", player.Name)
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		humanoid.Sit = false
		humanoid.PlatformStand = false
	end

	clearCharacterVelocities(character)
	character:PivotTo(holdingSpawn.CFrame + Vector3.new(0, MAIN_MENU_HOLDING_CHARACTER_Y_OFFSET, 0))
	clearCharacterVelocities(character)

	return true
end

local function isRoomExitInstance(instance)
	local current = instance

	while current do
		if current.Name == "RoomExitZone" or current:GetAttribute("IsRoomExit") == true then
			return true
		end

		current = current.Parent
	end

	return false
end

local function getRoomExitParts(roomModel)
	local exitParts = {}

	for _, descendant in ipairs(roomModel:GetDescendants()) do
		if descendant:IsA("BasePart") and isRoomExitInstance(descendant) then
			table.insert(exitParts, descendant)
		end
	end

	return exitParts
end

local function positionIsNearPart(position, part, maxDistance)
	local localPosition = part.CFrame:PointToObjectSpace(position)
	local halfSize = part.Size / 2
	local outsideX = math.max(math.abs(localPosition.X) - halfSize.X, 0)
	local outsideY = math.max(math.abs(localPosition.Y) - halfSize.Y, 0)
	local outsideZ = math.max(math.abs(localPosition.Z) - halfSize.Z, 0)

	return Vector3.new(outsideX, outsideY, outsideZ).Magnitude <= maxDistance
end

local function playerIsNearRoomExit(player, roomModel, maxDistance)
	local rootPart = getPlayerRootPart(player)

	if not rootPart then
		return false, "Character is not ready."
	end

	local doorSpawn = roomModel:FindFirstChild("DoorSpawn", true)

	if not doorSpawn or not doorSpawn:IsA("BasePart") then
		return false, "Room is missing DoorSpawn."
	end

	if positionIsNearPart(rootPart.Position, doorSpawn, maxDistance) then
		return true
	end

	return false, "Move closer to the room exit first."
end

local function setPlayerInHotelMainMenu(player, isInMainMenu)
	player:SetAttribute("InHotelMainMenu", isInMainMenu == true)
end

local function enterMainMenuForPlayer(player, introVariant, pendingOnboardingAfterIntro)
	player:SetAttribute("RoomMode", "Play")
	player:SetAttribute("ControlMode", "Hotel")
	player:SetAttribute("CurrentRoomName", nil)
	player:SetAttribute("CurrentRoomId", nil)
	player:SetAttribute("CurrentRoomOwnerUserId", nil)
	player:SetAttribute("CurrentRoomType", nil)
	player:SetAttribute("MainMenuIntroVariant", introVariant or MAIN_MENU_INTRO_RETURNING)
	player:SetAttribute("PendingOnboardingAfterIntro", pendingOnboardingAfterIntro == true)
	player:SetAttribute("OnboardingUiAllowed", false)

	if player:GetAttribute("CanEditCurrentRoom") ~= nil then
		player:SetAttribute("CanEditCurrentRoom", false)
	end

	setPlayerInHotelMainMenu(player, true)
	parkCharacterInMainMenu(player)
end

local function getRoomOwnerPlayer(roomModel)
	local ownerUserId = roomModel:GetAttribute("OwnerUserId")

	if typeof(ownerUserId) ~= "number" then
		return nil
	end

	return Players:GetPlayerByUserId(ownerUserId)
end

local function getOwnPlayerRoomForSettings(player)
	local roomModel = playerRooms[player] or activeRooms:FindFirstChild(getRoomName(player))

	if not roomModel or not roomModel:IsA("Model") then
		return nil
	end

	if roomModel:GetAttribute("RoomType") == "PublicSpace" then
		return nil
	end

	if roomModel:GetAttribute("OwnerUserId") ~= player.UserId then
		return nil
	end

	return roomModel
end

local function getPlayerCountInRoom(roomName)
	local count = 0

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("CurrentRoomName") == roomName then
			count += 1
		end
	end

	return count
end

local function copyRoomTags(tags)
	local copy = {}

	if typeof(tags) ~= "table" then
		return copy
	end

	for _, tag in ipairs(tags) do
		if typeof(tag) == "string" and tag ~= "" and tag:match("%S") ~= nil then
			table.insert(copy, tag)
		end
	end

	return copy
end

local function getFallbackRoomMetadata(ownerDisplayName)
	return {
		RoomId = "Primary",
		DisplayName = tostring(ownerDisplayName) .. "'s Room",
		Category = "Chat Rooms",
		IsPublic = true,
		MaxOccupancy = 25,
		Description = "",
		Tags = {},
	}
end

local function getRoomMetadata(ownerPlayer, ownerDisplayName)
	local metadata = ownerPlayer and RoomPersistence.GetRoomDirectorySnapshot(ownerPlayer) or nil
	local fallback = getFallbackRoomMetadata(ownerDisplayName)

	if typeof(metadata) ~= "table" then
		return fallback
	end

	local roomId = metadata.RoomId
	if typeof(roomId) ~= "string" or roomId == "" then
		roomId = fallback.RoomId
	end

	local displayName = metadata.DisplayName
	if typeof(displayName) ~= "string" or displayName == "" then
		displayName = fallback.DisplayName
	end

	local category = metadata.Category
	if typeof(category) ~= "string" or category == "" then
		category = fallback.Category
	end

	local isPublic = metadata.IsPublic
	if typeof(isPublic) ~= "boolean" then
		isPublic = fallback.IsPublic
	end

	local maxOccupancy = metadata.MaxOccupancy
	if typeof(maxOccupancy) ~= "number"
		or maxOccupancy ~= maxOccupancy
		or maxOccupancy <= 0
		or maxOccupancy >= math.huge
		or maxOccupancy ~= math.floor(maxOccupancy) then

		maxOccupancy = fallback.MaxOccupancy
	end

	local description = metadata.Description
	if typeof(description) ~= "string" then
		description = fallback.Description
	end

	return {
		RoomId = roomId,
		DisplayName = displayName,
		Category = category,
		IsPublic = isPublic,
		MaxOccupancy = maxOccupancy,
		Description = description,
		Tags = copyRoomTags(metadata.Tags),
	}
end

local function applyPlayerRoomMetadataAttributes(roomModel, metadata)
	if not roomModel or not roomModel:IsA("Model") or typeof(metadata) ~= "table" then
		return
	end

	roomModel:SetAttribute("RoomType", "PlayerRoom")
	roomModel:SetAttribute("RoomId", metadata.RoomId or "Primary")
	roomModel:SetAttribute("DisplayName", metadata.DisplayName)
	roomModel:SetAttribute("Category", metadata.Category)
	roomModel:SetAttribute("IsPublic", metadata.IsPublic == true)
	roomModel:SetAttribute("MaxOccupancy", metadata.MaxOccupancy)
	roomModel:SetAttribute("Description", metadata.Description)
end

local function getPublicRoomEntry(player, publicRoomId, config)
	if typeof(publicRoomId) ~= "string" or publicRoomId == "" or typeof(config) ~= "table" then
		return nil
	end

	local activeRoomName = getPublicRoomActiveName(publicRoomId)
	local activeRoom = activeRooms:FindFirstChild(activeRoomName)
	local occupancy = getPlayerCountInRoom(activeRoomName)
	local maxOccupancy = typeof(config.MaxOccupancy) == "number"
		and config.MaxOccupancy > 0
		and math.floor(config.MaxOccupancy) == config.MaxOccupancy
		and config.MaxOccupancy
		or 25
	local roomKey = "PublicSpace:" .. publicRoomId

	return {
		RoomType = "PublicSpace",
		RoomKey = roomKey,
		Id = publicRoomId,
		PublicRoomId = publicRoomId,
		ActiveRoomName = activeRoomName,
		DisplayName = config.DisplayName or publicRoomId,
		TemplateName = config.TemplateName,
		Category = config.Category or "Public Spaces",
		Description = config.Description or "",
		ShortLabel = config.ShortLabel,
		Theme = config.Theme,
		Tags = copyRoomTags(config.Tags),
		IconImageId = config.IconImageId,
		ThumbnailImageId = config.ThumbnailImageId,
		Occupancy = occupancy,
		PlayerCount = occupancy,
		MaxOccupancy = maxOccupancy,
		IsFavourite = player and RoomPersistence.IsRoomFavourite(player, roomKey) == true or false,
		IsOpen = config.IsOpen ~= false,
		IsAvailable = config.IsOpen ~= false,
		IsCurrentRoom = player and player:GetAttribute("CurrentRoomName") == activeRoomName or false,
		SortOrder = config.SortOrder,
		PublicRoomActive = activeRoom ~= nil,
	}
end

local function buildRoomList(viewerPlayer)
	local roomList = {}
	local currentRoomName = viewerPlayer and viewerPlayer:GetAttribute("CurrentRoomName") or nil

	for _, roomModel in ipairs(activeRooms:GetChildren()) do
		if roomModel:IsA("Model") then
			if roomModel:GetAttribute("RoomType") == "PublicSpace" then
				continue
			end

			local ownerUserId = roomModel:GetAttribute("OwnerUserId")
			local layoutId = roomModel:GetAttribute("LayoutId")
			local ownerPlayer = getRoomOwnerPlayer(roomModel)

			local ownerName = "Unknown"
			local ownerDisplayName = "Unknown"

			if ownerPlayer then
				ownerName = ownerPlayer.Name
				ownerDisplayName = ownerPlayer.DisplayName
			elseif typeof(ownerUserId) == "number" then
				ownerName = "User_" .. tostring(ownerUserId)
				ownerDisplayName = ownerName
			end

			local metadata = getRoomMetadata(ownerPlayer, ownerDisplayName)
			applyPlayerRoomMetadataAttributes(roomModel, metadata)

			local isOwner = typeof(ownerUserId) == "number"
				and viewerPlayer
				and viewerPlayer.UserId == ownerUserId

			if metadata.IsPublic or isOwner then
				local playerCount = getPlayerCountInRoom(roomModel.Name)
				local roomId = metadata.RoomId
				local roomKey = "PlayerRoom:" .. tostring(ownerUserId) .. ":" .. roomId

				table.insert(roomList, {
					RoomName = roomModel.Name,
					OwnerUserId = ownerUserId,
					OwnerName = ownerName,
					OwnerDisplayName = ownerDisplayName,
					LayoutId = layoutId or "Unknown",
					PlayerCount = playerCount,

					RoomType = "PlayerRoom",
					RoomId = roomId,
					RoomKey = roomKey,
					DisplayName = metadata.DisplayName,
					Category = metadata.Category,
					IsPublic = metadata.IsPublic,
					Occupancy = playerCount,
					MaxOccupancy = metadata.MaxOccupancy,
					Description = metadata.Description,
					Tags = metadata.Tags,
					IsOwner = isOwner == true,
					IsCurrentRoom = roomModel.Name == currentRoomName,
					IsFavourite = viewerPlayer and RoomPersistence.IsRoomFavourite(viewerPlayer, roomKey) == true or false,
					IsAvailable = true,
				})
			end
		end
	end

	table.sort(roomList, function(a, b)
		return tostring(a.DisplayName or a.OwnerDisplayName) < tostring(b.DisplayName or b.OwnerDisplayName)
	end)

	for _, config in ipairs(PublicRoomConfig.GetAllPublicRooms()) do
		local publicRoomId = config.PublicRoomId or config.Id
		local publicRoomEntry = getPublicRoomEntry(viewerPlayer, publicRoomId, config)

		if publicRoomEntry then
			table.insert(roomList, publicRoomEntry)
		end
	end

	return roomList
end

local function getFavouriteKeysArray(player)
	local favourites = RoomPersistence.GetFavouriteRoomsSnapshot(player)
	local favouriteKeys = {}

	for roomKey, isFavourite in pairs(favourites) do
		if isFavourite == true then
			table.insert(favouriteKeys, roomKey)
		end
	end

	table.sort(favouriteKeys)

	return favouriteKeys
end

local function getFavouriteEntries(player)
	local favouriteKeys = getFavouriteKeysArray(player)
	local entries = {}
	local activePlayerRoomsByKey = {}

	for _, roomEntry in ipairs(buildRoomList(player)) do
		if typeof(roomEntry.RoomKey) == "string" then
			activePlayerRoomsByKey[roomEntry.RoomKey] = roomEntry
		end
	end

	for _, roomKey in ipairs(favouriteKeys) do
		local publicRoomId = string.match(roomKey, "^PublicSpace:(.+)$")

		if publicRoomId then
			local config = PublicRoomConfig.GetPublicRoom(publicRoomId)
			local entry = getPublicRoomEntry(player, publicRoomId, config)

			if entry then
				entry.IsFavourite = true
				table.insert(entries, entry)
			end
		else
			local playerRoomEntry = activePlayerRoomsByKey[roomKey]

			if playerRoomEntry then
				playerRoomEntry.IsFavourite = true
				playerRoomEntry.IsAvailable = true
				table.insert(entries, playerRoomEntry)
			end
		end
	end

	return favouriteKeys, entries
end

local function canFavouriteRoomKey(player, roomKey)
	local publicRoomId = string.match(roomKey, "^PublicSpace:(.+)$")

	if publicRoomId then
		return PublicRoomConfig.GetPublicRoom(publicRoomId) ~= nil
	end

	if string.match(roomKey, "^PlayerRoom:") then
		for _, roomEntry in ipairs(buildRoomList(player)) do
			if roomEntry.RoomKey == roomKey then
				return true
			end
		end
	end

	return false
end

local function sendRoomListToPlayer(player)
	local roomList = buildRoomList(player)

	roomListUpdate:FireClient(player, roomList, player:GetAttribute("CurrentRoomName"))
end

local function sendRoomListToAll()
	for _, player in ipairs(Players:GetPlayers()) do
		local roomList = buildRoomList(player)
		roomListUpdate:FireClient(player, roomList, player:GetAttribute("CurrentRoomName"))
	end
end

local function buildRoomEditorsList(ownerPlayer)
	local roomPermissions = RoomPersistence.GetRoomPermissionsSnapshot(ownerPlayer)
	local editors = {}

	if typeof(roomPermissions) ~= "table" or typeof(roomPermissions.Editors) ~= "table" then
		return editors
	end

	for userIdKey, isAllowed in pairs(roomPermissions.Editors) do
		if isAllowed == true then
			local userId = tonumber(userIdKey)

			if userId and userId > 0 and userId ~= ownerPlayer.UserId then
				local editorPlayer = Players:GetPlayerByUserId(userId)
				local entry = {
					UserId = userId,
				}

				if editorPlayer then
					entry.Name = editorPlayer.Name
					entry.DisplayName = editorPlayer.DisplayName
				end

				table.insert(editors, entry)
			end
		end
	end

	table.sort(editors, function(a, b)
		return a.UserId < b.UserId
	end)

	return editors
end

local function sendRoomEditorsResult(player, actionName, success, message, resolvedUserId, resolvedName)
	local response = {
		Kind = "RoomSettings",
		Action = actionName,
		Success = success == true,
		Message = message,
		Editors = buildRoomEditorsList(player),
	}

	if resolvedUserId then
		response.ResolvedUserId = resolvedUserId
		response.ResolvedName = resolvedName
	end

	roomSettingsResult:FireClient(player, response)
end

local function getCurrentPlayerRoomForFurniturePermissions(player)
	local roomName = player:GetAttribute("CurrentRoomName")

	if typeof(roomName) ~= "string" or roomName == "" then
		return nil
	end

	local roomModel = activeRooms:FindFirstChild(roomName)

	if not roomModel or not roomModel:IsA("Model") then
		return nil
	end

	if roomModel:GetAttribute("RoomType") == "PublicSpace" then
		return nil
	end

	if roomModel:GetAttribute("OwnerUserId") ~= player.UserId then
		return nil
	end

	return roomModel
end

local function getFurnitureFolder(roomModel)
	if not roomModel then
		return nil
	end

	return roomModel:FindFirstChild("Furniture")
end

local function validateOpenClosePermissionTarget(player, payload)
	if typeof(payload) ~= "table" then
		return nil, nil, nil, "Invalid furniture permission request."
	end

	if payload.ActionName ~= "OpenClose" then
		return nil, nil, nil, "Unsupported furniture permission action."
	end

	local roomModel = getCurrentPlayerRoomForFurniturePermissions(player)

	if not roomModel then
		return nil, nil, nil, "Only the room owner can manage furniture permissions."
	end

	if not RoomPermissionService.IsPlayerRoom(roomModel) then
		return nil, nil, nil, "Furniture permissions are only available in player rooms."
	end

	local furnitureModel = payload.Furniture

	if typeof(furnitureModel) ~= "Instance" or not furnitureModel:IsA("Model") then
		return nil, nil, nil, "Invalid furniture."
	end

	local furnitureFolder = getFurnitureFolder(roomModel)

	if not furnitureFolder or not furnitureModel:IsDescendantOf(furnitureFolder) then
		return nil, nil, nil, "Invalid furniture."
	end

	if not RoomPermissionService.FurnitureSupportsPermission(furnitureModel, "OpenClose") then
		return nil, nil, nil, "This furniture does not support Open/Close permissions."
	end

	local persistentId = RoomPermissionService.GetFurniturePersistentId(furnitureModel)

	if not persistentId then
		return nil, nil, nil, "This furniture is missing a persistent id."
	end

	return roomModel, furnitureModel, persistentId, nil
end

local function validateFurnitureActionAccessTarget(player, payload)
	if typeof(payload) ~= "table" then
		return nil, nil, "Invalid furniture action access request."
	end

	local roomName = player:GetAttribute("CurrentRoomName")

	if typeof(roomName) ~= "string" or roomName == "" then
		return nil, nil, "You are not in a room."
	end

	local roomModel = activeRooms:FindFirstChild(roomName)

	if not roomModel or not roomModel:IsA("Model") then
		return nil, nil, "Current room is unavailable."
	end

	local furnitureModel = payload.Furniture

	if typeof(furnitureModel) ~= "Instance" or not furnitureModel:IsA("Model") then
		return nil, nil, "Invalid furniture."
	end

	local furnitureFolder = getFurnitureFolder(roomModel)

	if not furnitureFolder or not furnitureModel:IsDescendantOf(furnitureFolder) then
		return nil, nil, "Invalid furniture."
	end

	return roomModel, furnitureModel, nil
end

local function sendFurnitureActionAccessResult(player, success, message, furnitureModel, accessSummary)
	local response = {
		Kind = "FurnitureActionAccess",
		Success = success == true,
		Furniture = furnitureModel,
		SupportsOpenClose = false,
		CanOpenClose = false,
		CanManageOpenClose = false,
		CanMove = false,
		CanRotate = false,
		CanPickUp = false,
		Message = message,
	}

	if typeof(accessSummary) == "table" then
		response.SupportsOpenClose = accessSummary.SupportsOpenClose == true
		response.CanOpenClose = accessSummary.CanOpenClose == true
		response.CanManageOpenClose = accessSummary.CanManageOpenClose == true
		response.CanMove = accessSummary.CanMove == true
		response.CanRotate = accessSummary.CanRotate == true
		response.CanPickUp = accessSummary.CanPickUp == true
	end

	roomPermissionResult:FireClient(player, response)
end

local function buildFurnitureActionAccessSummary(player, roomModel, furnitureModel)
	local supportsOpenClose = RoomPermissionService.FurnitureSupportsPermission(furnitureModel, "OpenClose")
	local persistentId = RoomPermissionService.GetFurniturePersistentId(furnitureModel)

	return {
		SupportsOpenClose = supportsOpenClose,
		CanOpenClose = supportsOpenClose and RoomPermissionService.CanOpenCloseFurniture(player, furnitureModel) or false,
		CanManageOpenClose = RoomPermissionService.IsPlayerRoom(roomModel)
			and RoomPermissionService.IsRoomOwner(player, roomModel)
			and supportsOpenClose
			and persistentId ~= nil,
		CanMove = RoomPermissionService.CanMoveFurniture(player, furnitureModel),
		CanRotate = RoomPermissionService.CanRotateFurniture(player, furnitureModel),
		CanPickUp = RoomPermissionService.CanPickUpFurniture(player, furnitureModel),
	}
end

local function buildFurniturePermissionEntries(ownerPlayer, persistentId, actionName)
	local roomPermissions = RoomPersistence.GetRoomPermissionsSnapshot(ownerPlayer)
	local entries = {}

	if typeof(roomPermissions) ~= "table"
		or typeof(roomPermissions.FurniturePermissions) ~= "table" then

		return entries
	end

	local furniturePermissions = roomPermissions.FurniturePermissions[persistentId]

	if typeof(furniturePermissions) ~= "table" then
		return entries
	end

	local actionPermissions = furniturePermissions[actionName]

	if typeof(actionPermissions) ~= "table" then
		return entries
	end

	for userIdKey, isAllowed in pairs(actionPermissions) do
		if isAllowed == true then
			local userId = tonumber(userIdKey)

			if userId and userId > 0 and userId ~= ownerPlayer.UserId then
				local targetPlayer = Players:GetPlayerByUserId(userId)
				local entry = {
					UserId = userId,
				}

				if targetPlayer then
					entry.Name = targetPlayer.Name
					entry.DisplayName = targetPlayer.DisplayName
				end

				table.insert(entries, entry)
			end
		end
	end

	table.sort(entries, function(a, b)
		return a.UserId < b.UserId
	end)

	return entries
end

local function sendFurniturePermissionResult(player, requestAction, success, message, persistentId, entries, resolvedUserId, resolvedName)
	local response = {
		Kind = "FurniturePermissions",
		RequestAction = requestAction,
		Success = success == true,
		Message = message,
		FurniturePersistentId = persistentId,
		ActionName = "OpenClose",
		Entries = entries or {},
	}

	if resolvedUserId then
		response.ResolvedUserId = resolvedUserId
		response.ResolvedName = resolvedName
	end

	roomPermissionResult:FireClient(player, response)
end

local function tableHasEntries(value)
	if typeof(value) ~= "table" then
		return false
	end

	for _ in pairs(value) do
		return true
	end

	return false
end

local function roomStateHasFurnitureList(roomState)
	return typeof(roomState) == "table" and typeof(roomState.Furniture) == "table"
end

local function shouldUseLegacyRoomState(primaryRoomState, legacyRoomState)
	if typeof(primaryRoomState) ~= "table" then
		return typeof(legacyRoomState) == "table"
	end

	if roomStateHasFurnitureList(primaryRoomState) then
		return false
	end

	return roomStateHasFurnitureList(legacyRoomState)
		or (not tableHasEntries(primaryRoomState) and tableHasEntries(legacyRoomState))
end

local function getPrimarySavedRoom(player, profile)
	local primaryRoomId = RoomPersistence.GetPrimaryRoomId(player)

	if typeof(primaryRoomId) ~= "string" or primaryRoomId == "" then
		primaryRoomId = PRIMARY_ROOM_ID
	end

	local roomRecord = RoomPersistence.GetRoomRecord(player, primaryRoomId)

	if not roomRecord and primaryRoomId ~= PRIMARY_ROOM_ID then
		primaryRoomId = PRIMARY_ROOM_ID
		roomRecord = RoomPersistence.GetRoomRecord(player, primaryRoomId)
	end

	local primaryRoomState = RoomPersistence.GetRoomStateForRoom(player, primaryRoomId)
	local legacyRoomState = profile and profile.RoomState
	local roomState = primaryRoomState

	if shouldUseLegacyRoomState(primaryRoomState, legacyRoomState) then
		roomState = legacyRoomState
	end

	local layoutId = roomRecord and roomRecord.LayoutId

	if typeof(layoutId) ~= "string" or layoutId == "" then
		layoutId = profile and profile.CurrentLayoutId
	end

	if (typeof(layoutId) ~= "string" or not VALID_LAYOUTS[layoutId])
		and typeof(roomState) == "table"
		and typeof(roomState.LayoutId) == "string" then

		layoutId = roomState.LayoutId
	end

	return {
		RoomId = primaryRoomId,
		RoomRecord = roomRecord,
		RoomState = roomState,
		LayoutId = layoutId,
	}
end

local function capturePrimaryRoomState(player, roomModel)
	local roomState = RoomPersistence.CaptureRoomState(player, roomModel)

	if typeof(roomState) == "table" then
		local success, message = RoomPersistence.SetRoomStateForRoom(
			player,
			PRIMARY_ROOM_ID,
			roomState,
			roomState.LayoutId
		)

		if not success then
			warn("Could not save Primary room state for", player.Name, message)
		end
	end

	return roomState
end

local function enterSavedRoomForPlayer(player, profile)
	local savedRoom = getPrimarySavedRoom(player, profile)
	local roomState = savedRoom.RoomState
	local layoutId = savedRoom.LayoutId

	if typeof(layoutId) ~= "string" or not VALID_LAYOUTS[layoutId] then
		warn("Saved room has invalid layout:", layoutId)
		return false
	end

	local roomModel = cloneRoomForPlayer(player, layoutId)

	if not roomModel then
		return false
	end

	RoomPersistence.ApplyRoomState(roomModel, roomState)

	local success, errorMessage = pcall(function()
		movePlayerToRoom(player, roomModel)
	end)

	if not success then
		warn("Could not move player into saved room:", errorMessage)
		removePlayerRoom(player)
		return false
	end

	player:SetAttribute("CurrentRoomName", roomModel.Name)
	player:SetAttribute("CurrentLayoutId", layoutId)
	setCurrentPlayerRoomContext(player, player.UserId, savedRoom.RoomId)
	player:SetAttribute("HasCreatedRoom", true)
	player:SetAttribute("ProfileCreated", true)
	player:SetAttribute("CharacterCreatedThisSession", profile.CharacterCreated == true)
	player:SetAttribute("RoomMode", "Play")
	player:SetAttribute("ControlMode", "Hotel")
	player:SetAttribute("MainMenuIntroVariant", nil)
	player:SetAttribute("PendingOnboardingAfterIntro", false)
	player:SetAttribute("OnboardingUiAllowed", false)
	setPlayerInHotelMainMenu(player, false)

	local onboardingStep = profile.OnboardingStep

	if onboardingStep ~= "Tutorial" and onboardingStep ~= "Complete" then
		onboardingStep = "Complete"
	end

	player:SetAttribute("OnboardingStep", onboardingStep)

	roomCreationResult:FireClient(player, "Created", roomModel.Name)

	sendRoomListToAll()

	return true
end

local function prepareSavedRoomForMainMenu(player, profile)
	local savedRoom = getPrimarySavedRoom(player, profile)
	local roomState = savedRoom.RoomState
	local layoutId = savedRoom.LayoutId

	if typeof(layoutId) ~= "string" or not VALID_LAYOUTS[layoutId] then
		warn("Saved room has invalid layout:", layoutId)
		return false
	end

	local roomModel = cloneRoomForPlayer(player, layoutId)

	if not roomModel then
		return false
	end

	RoomPersistence.ApplyRoomState(roomModel, roomState)

	player:SetAttribute("CurrentLayoutId", layoutId)
	player:SetAttribute("HasCreatedRoom", true)
	player:SetAttribute("ProfileCreated", true)
	player:SetAttribute("CharacterCreatedThisSession", profile.CharacterCreated == true)
	player:SetAttribute("OnboardingStep", "Complete")

	return true
end

local function getPublicRoomTemplate(templateName)
	if typeof(templateName) ~= "string" or templateName == "" then
		return nil
	end

	local publicRoomTemplates = ReplicatedStorage:FindFirstChild("PublicRoomTemplates")

	if publicRoomTemplates then
		local publicTemplate = publicRoomTemplates:FindFirstChild(templateName)

		if publicTemplate then
			return publicTemplate
		end
	end

	return roomTemplates:FindFirstChild(templateName)
end

local function getPublicRoomMaxOccupancy(config)
	local maxOccupancy = config.MaxOccupancy

	if typeof(maxOccupancy) ~= "number"
		or maxOccupancy ~= maxOccupancy
		or maxOccupancy <= 0
		or maxOccupancy >= math.huge
		or maxOccupancy ~= math.floor(maxOccupancy) then

		return 25
	end

	return maxOccupancy
end

local function applyPublicRoomAttributes(roomModel, publicRoomId, config)
	roomModel:SetAttribute("RoomType", "PublicSpace")
	roomModel:SetAttribute("PublicRoomId", publicRoomId)
	roomModel:SetAttribute("RoomId", publicRoomId)
	roomModel:SetAttribute("DisplayName", config.DisplayName)
	roomModel:SetAttribute("ShortLabel", config.ShortLabel)
	roomModel:SetAttribute("MaxOccupancy", getPublicRoomMaxOccupancy(config))
	roomModel:SetAttribute("Category", config.Category)
	roomModel:SetAttribute("Description", config.Description)
	roomModel:SetAttribute("Theme", config.Theme)
	roomModel:SetAttribute("IsOpen", config.IsOpen ~= false)
	roomModel:SetAttribute("OwnerUserId", 0)
end

local function getOrCreatePublicRoom(publicRoomId, config)
	local activeRoomName = getPublicRoomActiveName(publicRoomId)
	local existingRoom = activeRooms:FindFirstChild(activeRoomName)

	if existingRoom then
		if not existingRoom:IsA("Model") then
			return nil, "Public room is not a model."
		end

		applyPublicRoomAttributes(existingRoom, publicRoomId, config)
		return existingRoom
	end

	local template = getPublicRoomTemplate(config.TemplateName)

	if not template then
		return nil, "Public room template is missing."
	end

	local roomClone = template:Clone()

	if not roomClone:IsA("Model") then
		roomClone:Destroy()
		return nil, "Public room template must be a Model."
	end

	removeEditorHelpers(roomClone)

	roomClone.Name = activeRoomName
	roomClone.Parent = activeRooms

	local moved = moveRoomAnchorToPosition(roomClone, getRoomPositionForPublicRoom(publicRoomId, config))

	if not moved then
		roomClone:Destroy()
		return nil, "Public room is missing RoomAnchor."
	end

	applyPublicRoomAttributes(roomClone, publicRoomId, config)

	return roomClone
end

local function joinPublicRoom(player, publicRoomId)
	if typeof(publicRoomId) ~= "string" or publicRoomId == "" then
		joinRoomResult:FireClient(player, false, "Invalid public room.")
		return
	end

	local config = PublicRoomConfig.GetPublicRoom(publicRoomId)

	if typeof(config) ~= "table" then
		joinRoomResult:FireClient(player, false, "Public room not found.")
		return
	end

	if config.IsOpen == false then
		joinRoomResult:FireClient(player, false, "This public room is currently closed.")
		return
	end

	local roomModel, createError = getOrCreatePublicRoom(publicRoomId, config)

	if not roomModel then
		warn("Could not create public room:", publicRoomId, createError)
		joinRoomResult:FireClient(player, false, createError or "Could not open public room.")
		return
	end

	local maxOccupancy = getPublicRoomMaxOccupancy(config)
	local currentOccupancy = getPlayerCountInRoom(roomModel.Name)
	local alreadyInRoom = player:GetAttribute("CurrentRoomName") == roomModel.Name

	if not alreadyInRoom and currentOccupancy >= maxOccupancy then
		joinRoomResult:FireClient(player, false, "Public room is full.")
		return
	end

	local success, errorMessage = pcall(function()
		movePlayerToRoom(player, roomModel)
	end)

	if not success then
		warn("Join public room failed:", errorMessage)
		joinRoomResult:FireClient(player, false, "Could not enter public room.")
		return
	end

	player:SetAttribute("CurrentRoomName", roomModel.Name)
	player:SetAttribute("RoomMode", "Play")
	player:SetAttribute("ControlMode", "Hotel")
	setCurrentPublicRoomContext(player, publicRoomId)
	player:SetAttribute("MainMenuIntroVariant", nil)
	player:SetAttribute("PendingOnboardingAfterIntro", false)
	player:SetAttribute("OnboardingUiAllowed", false)
	setPlayerInHotelMainMenu(player, false)

	joinRoomResult:FireClient(player, true, "Joined public space.", roomModel.Name)

	sendRoomListToAll()
end

local function getRoomByName(roomName)
	if typeof(roomName) ~= "string" then
		return nil
	end

	return activeRooms:FindFirstChild(roomName)
end

local function joinRoom(player, roomName)
	local roomModel = getRoomByName(roomName)

	if not roomModel or not roomModel:IsA("Model") then
		joinRoomResult:FireClient(player, false, "Room not found.")
		return
	end

	if roomModel:GetAttribute("RoomType") == "PublicSpace" then
		joinPublicRoom(player, roomModel:GetAttribute("PublicRoomId"))
		return
	end

	local ownerUserId = roomModel:GetAttribute("OwnerUserId")

	if typeof(ownerUserId) ~= "number" then
		joinRoomResult:FireClient(player, false, "Room has no owner.")
		return
	end

	local ownerPlayer = getRoomOwnerPlayer(roomModel)
	local isOwner = player.UserId == ownerUserId
	local ownerDisplayName = ownerPlayer and ownerPlayer.DisplayName or ("User_" .. tostring(ownerUserId))
	local metadata = getRoomMetadata(ownerPlayer, ownerDisplayName)

	if not metadata.IsPublic and not isOwner then
		joinRoomResult:FireClient(player, false, "Room is private.")
		return
	end

	player:SetAttribute("CurrentRoomName", roomModel.Name)
	player:SetAttribute("RoomMode", "Play")
	player:SetAttribute("ControlMode", "Hotel")
	setCurrentPlayerRoomContext(player, ownerUserId, roomModel:GetAttribute("RoomId") or PRIMARY_ROOM_ID)
	player:SetAttribute("MainMenuIntroVariant", nil)
	player:SetAttribute("PendingOnboardingAfterIntro", false)
	player:SetAttribute("OnboardingUiAllowed", false)
	setPlayerInHotelMainMenu(player, false)

	local success, errorMessage = pcall(function()
		movePlayerToRoom(player, roomModel)
	end)

	if not success then
		warn("Join room failed:", errorMessage)
		joinRoomResult:FireClient(player, false, "Could not enter room.")
		return
	end

	joinRoomResult:FireClient(player, true, "Joined room.", roomModel.Name)

	sendRoomListToAll()
end

local function leaveCurrentRoom(player)
	local currentRoomName = player:GetAttribute("CurrentRoomName")

	if typeof(currentRoomName) ~= "string" or currentRoomName == "" then
		leaveRoomResult:FireClient(player, false, "You are not in a room.")
		return
	end

	local roomModel = activeRooms:FindFirstChild(currentRoomName)

	if not roomModel or not roomModel:IsA("Model") then
		leaveRoomResult:FireClient(player, false, "Room not found.")
		return
	end

	local nearExit, nearExitMessage = playerIsNearRoomExit(player, roomModel, 8)

	if not nearExit then
		leaveRoomResult:FireClient(player, false, nearExitMessage or "Move closer to the room exit first.")
		return
	end

	local ownerUserId = roomModel:GetAttribute("OwnerUserId")

	if typeof(ownerUserId) == "number"
		and ownerUserId == player.UserId
		and roomModel:GetAttribute("RoomType") ~= "PublicSpace" then

		capturePrimaryRoomState(player, roomModel)
		RoomPersistence.QueueSave(player)
	end

	enterMainMenuForPlayer(player, MAIN_MENU_INTRO_RETURNING)

	leaveRoomResult:FireClient(player, true, "Left room.")
	sendRoomListToAll()
end

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("HasCreatedRoom", false)

	player.CharacterAdded:Connect(function()
		local roomName = player:GetAttribute("CurrentRoomName")

		if roomName then
			local roomModel = activeRooms:FindFirstChild(roomName)

			if roomModel then
				task.wait(0.2)
				movePlayerToRoom(player, roomModel)
			end
		elseif player:GetAttribute("InHotelMainMenu") == true then
			task.wait(0.2)
			parkCharacterInMainMenu(player)
		end
	end)

	player:SetAttribute("RoomMode", "Play")
	player:SetAttribute("ControlMode", "Hotel")
	player:SetAttribute("MainMenuIntroVariant", nil)
	player:SetAttribute("PendingOnboardingAfterIntro", false)
	player:SetAttribute("OnboardingUiAllowed", false)
	setPlayerInHotelMainMenu(player, false)

	local profile, loaded = RoomPersistence.LoadProfile(player)

	if not loaded or not profile then
		player:Kick("Could not load your profile. Please rejoin.")
		return
	end

	local grantedStarterDollars, starterDollarsMessage =
		RoomPersistence.GrantStarterDollarsIfNeeded(player)

	if not grantedStarterDollars then
		warn("Starter Dollars grant failed for", player.Name, starterDollarsMessage)
	end

	player:SetAttribute("ProfileCreated", profile.ProfileCreated == true)
	player:SetAttribute("CharacterCreatedThisSession", profile.CharacterCreated == true)

	if not RoomPersistence.HasSeenHotelIntro(player) then
		local pendingOnboarding = profile.ProfileCreated ~= true
			or profile.OnboardingStep ~= "Complete"

		if pendingOnboarding then
			player:SetAttribute("OnboardingStep", "HotelIntro")
			player:SetAttribute("OnboardingUiAllowed", false)
			enterMainMenuForPlayer(player, MAIN_MENU_INTRO_FIRST_VISIT_ONBOARDING, true)
			sendRoomListToAll()
			return
		end

		local roomPrepared = prepareSavedRoomForMainMenu(player, profile)

		if not roomPrepared then
			player:Kick("Your saved room could not load. Please rejoin.")
			return
		end

		enterMainMenuForPlayer(player, MAIN_MENU_INTRO_FIRST_VISIT)
		sendRoomListToAll()
		return
	end

	if profile.ProfileCreated == true then
		local enteredSavedRoom = enterSavedRoomForPlayer(player, profile)

		if enteredSavedRoom then
			return
		end

		-- Safer than overwriting saved data with a new room.
		player:Kick("Your saved room could not load. Please rejoin.")
		return
	end

	player:SetAttribute("OnboardingUiAllowed", true)

	if profile.CharacterCreated == true then
		player:SetAttribute("OnboardingStep", "RoomCreation")
		roomCreationResult:FireClient(player, "ShowCreation")
	else
		player:SetAttribute("OnboardingStep", "CharacterCreation")
		roomCreationResult:FireClient(player, "ShowCharacterCreation")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	roomCreationInFlightByUserId[player.UserId] = nil
	roomSettingsLastRequestAtByUserId[player.UserId] = nil
	roomPermissionLastRequestAtByUserId[player.UserId] = nil
	roomUsernameLookupLastRequestAtByUserId[player.UserId] = nil
	
	if RoomPersistence.IsWriteBlocked(player) then
		RoomPersistence.ReleasePlayer(player)

		removePlayerRoom(player)
		playerRoomSlots[player] = nil

		task.defer(function()
			sendRoomListToAll()
		end)

		return
	end

	local ownedRoom = playerRooms[player]

	if ownedRoom and ownedRoom.Parent then
		capturePrimaryRoomState(player, ownedRoom)
	end

	RoomPersistence.SavePlayer(player)
	RoomPersistence.ReleasePlayer(player)

	removePlayerRoom(player)
	playerRoomSlots[player] = nil

	task.defer(function()
		sendRoomListToAll()
	end)
end)

local function showOnboardingAfterHotelIntro(player, profile)
	player:SetAttribute("PendingOnboardingAfterIntro", false)
	player:SetAttribute("OnboardingUiAllowed", true)
	player:SetAttribute("MainMenuIntroVariant", nil)
	player:SetAttribute("CurrentRoomName", nil)
	player:SetAttribute("CurrentRoomId", nil)
	player:SetAttribute("CurrentRoomOwnerUserId", nil)
	player:SetAttribute("CurrentRoomType", nil)
	setPlayerInHotelMainMenu(player, false)

	if profile.CharacterCreated == true
		or profile.OnboardingStep == "RoomCreation" then

		player:SetAttribute("CharacterCreatedThisSession", profile.CharacterCreated == true)
		player:SetAttribute("OnboardingStep", "RoomCreation")
		roomCreationResult:FireClient(player, "ShowCreation")
	else
		player:SetAttribute("CharacterCreatedThisSession", false)
		player:SetAttribute("OnboardingStep", "CharacterCreation")
		roomCreationResult:FireClient(player, "ShowCharacterCreation")
	end
end

characterCreationFinished.OnServerEvent:Connect(function(player, characterData)
	if player:GetAttribute("PendingOnboardingAfterIntro") == true then
		return
	end

	if player:GetAttribute("HasCreatedRoom") then
		return
	end

	if player:GetAttribute("CharacterCreatedThisSession") then
		return
	end

	-- Temporary validation.
	-- Later, validate actual hair, clothes, skin tone, accessories, etc.
	if typeof(characterData) ~= "table" then
		characterData = {}
	end

	player:SetAttribute("CharacterCreatedThisSession", true)
	player:SetAttribute("OnboardingStep", "RoomCreation")

	local profile = RoomPersistence.GetProfile(player)

	if profile then
		profile.CharacterCreated = true
		profile.OnboardingStep = "RoomCreation"
		RoomPersistence.QueueSave(player)
	end

	roomCreationResult:FireClient(player, "ShowCreation")
end)

createRoomRequest.OnServerEvent:Connect(function(player, layoutId)
	print("Server: CreateRoomRequest from", player.Name, layoutId)

	local function sendCreationResult(status, roomName)
		if player.Parent == Players then
			roomCreationResult:FireClient(player, status, roomName)
		end
	end

	if player:GetAttribute("PendingOnboardingAfterIntro") == true then
		return
	end

	if roomCreationInFlightByUserId[player.UserId] then
		warn("Server: Ignoring duplicate CreateRoomRequest from", player.Name)
		return
	end

	if typeof(layoutId) ~= "string" then
		warn("Server: Invalid layoutId type")
		sendCreationResult("Failed")
		return
	end

	if not VALID_LAYOUTS[layoutId] then
		warn(player.Name .. " tried invalid layout:", layoutId)
		sendCreationResult("Failed")
		return
	end

	if player:GetAttribute("HasCreatedRoom") then
		warn(player.Name .. " already created a room this session")
		sendCreationResult("Created", player:GetAttribute("CurrentRoomName"))
		return
	end

	if not player:GetAttribute("CharacterCreatedThisSession") then
		warn(player.Name .. " tried to create a room before character creation")
		sendCreationResult("ShowCharacterCreation")
		return
	end

	roomCreationInFlightByUserId[player.UserId] = true

	local function clearRoomCreationLock()
		roomCreationInFlightByUserId[player.UserId] = nil
	end

	local roomModel = cloneRoomForPlayer(player, layoutId)

	if not roomModel then
		warn("Server: Room clone failed")
		clearRoomCreationLock()
		sendCreationResult("Failed")
		return
	end

	print("Server: Room cloned:", roomModel.Name)

	local success, errorMessage = pcall(function()
		movePlayerToRoom(player, roomModel)
	end)

	if not success then
		warn("Server: movePlayerToRoom failed:", errorMessage)
		clearRoomCreationLock()
		sendCreationResult("Failed")
		return
	end

	if player.Parent ~= Players then
		clearRoomCreationLock()
		return
	end

	-- Important:
	-- These must be set after the room is fully created and the player is moved.
	player:SetAttribute("CurrentRoomName", roomModel.Name)
	player:SetAttribute("CurrentLayoutId", layoutId)
	setCurrentPlayerRoomContext(player, player.UserId, PRIMARY_ROOM_ID)
	player:SetAttribute("HasCreatedRoom", true)
	player:SetAttribute("ProfileCreated", true)

	-- New players should enter their room first, then complete tutorial.
	player:SetAttribute("OnboardingStep", "Tutorial")
	player:SetAttribute("RoomMode", "Play")
	player:SetAttribute("ControlMode", "Hotel")
	player:SetAttribute("MainMenuIntroVariant", nil)
	player:SetAttribute("PendingOnboardingAfterIntro", false)
	player:SetAttribute("OnboardingUiAllowed", false)
	setPlayerInHotelMainMenu(player, false)

	local profile = RoomPersistence.GetProfile(player)

	if profile then
		profile.ProfileCreated = true
		profile.CharacterCreated = true
		profile.OnboardingStep = "Tutorial"
		profile.CurrentLayoutId = layoutId
		RoomPersistence.EnsureRoomsSchema(profile)
	end

	capturePrimaryRoomState(player, roomModel)
	RoomPersistence.SavePlayer(player)

	print("Server: Room created successfully, telling client")
	print("Server: OnboardingStep =", player:GetAttribute("OnboardingStep"))

	clearRoomCreationLock()

	sendCreationResult("Created", roomModel.Name)

	sendRoomListToAll()
end)

roomListRequest.OnServerEvent:Connect(function(player)
	sendRoomListToPlayer(player)
end)

roomPermissionRequest.OnServerEvent:Connect(function(player, actionName, payload)
	local safeActionName = typeof(actionName) == "string" and actionName or "Unknown"

	if safeActionName ~= "GetFurniturePermissions"
		and safeActionName ~= "SetFurniturePermission"
		and safeActionName ~= "GetFurnitureActionAccess" then

		sendFurniturePermissionResult(player, safeActionName, false, "Unknown permission action.")
		return
	end

	if safeActionName ~= "GetFurnitureActionAccess" and isRoomPermissionRequestRateLimited(player) then
		sendFurniturePermissionResult(
			player,
			safeActionName,
			false,
			"Please wait a moment before updating furniture permissions."
		)
		return
	end

	if safeActionName == "GetFurnitureActionAccess" then
		local roomModel, furnitureModel, validationMessage = validateFurnitureActionAccessTarget(player, payload)

		if validationMessage then
			sendFurnitureActionAccessResult(
				player,
				false,
				validationMessage,
				typeof(payload) == "table" and payload.Furniture or nil
			)
			return
		end

		sendFurnitureActionAccessResult(
			player,
			true,
			"Furniture action access loaded.",
			furnitureModel,
			buildFurnitureActionAccessSummary(player, roomModel, furnitureModel)
		)
		return
	end

	local _, _, persistentId, validationMessage = validateOpenClosePermissionTarget(player, payload)

	if validationMessage then
		sendFurniturePermissionResult(player, safeActionName, false, validationMessage)
		return
	end

	if safeActionName == "GetFurniturePermissions" then
		sendFurniturePermissionResult(
			player,
			safeActionName,
			true,
			"Furniture permissions loaded.",
			persistentId,
			buildFurniturePermissionEntries(player, persistentId, "OpenClose")
		)
		return
	end

	local targetUserInput = getPermissionTargetInput(payload)
	local targetUserId, targetUserMessage, resolvedInputName =
		resolveUserInputToUserId(player, targetUserInput)

	if not targetUserId then
		sendFurniturePermissionResult(player, safeActionName, false, targetUserMessage or "Invalid user.", persistentId)
		return
	end

	if targetUserIsCurrentPlayer(player, targetUserId, targetUserInput, resolvedInputName) then
		sendFurniturePermissionResult(
			player,
			safeActionName,
			false,
			"You already have access as the room owner.",
			persistentId,
			buildFurniturePermissionEntries(player, persistentId, "OpenClose")
		)
		return
	end

	local success, message = RoomPersistence.SetFurniturePermission(
		player,
		persistentId,
		"OpenClose",
		targetUserId,
		payload.IsAllowed == true
	)
	local resolvedName = getResolvedUserName(targetUserId, resolvedInputName)

	sendFurniturePermissionResult(
		player,
		safeActionName,
		success == true,
		success and (payload.IsAllowed == true and "Open/Close access added." or "Open/Close access removed.")
			or (message or "Could not update furniture permission."),
		persistentId,
		buildFurniturePermissionEntries(player, persistentId, "OpenClose"),
		success and targetUserId or nil,
		success and resolvedName or nil
	)
end)

roomSettingsRequest.OnServerEvent:Connect(function(player, actionName, payload)
	local safeActionName = typeof(actionName) == "string" and actionName or "Unknown"

	if safeActionName == "UpdateSettings" and isRoomSettingsRequestRateLimited(player) then
		roomSettingsResult:FireClient(player, {
			Kind = "RoomSettings",
			Action = safeActionName,
			Success = false,
			Message = "Please wait a moment before updating room settings.",
		})
		return
	end

	if (safeActionName == "AddRoomEditor" or safeActionName == "RemoveRoomEditor")
		and isRoomPermissionRequestRateLimited(player) then

		roomSettingsResult:FireClient(player, {
			Kind = "RoomSettings",
			Action = safeActionName,
			Success = false,
			Message = "Please wait a moment before updating room editors.",
		})
		return
	end

	if safeActionName == "GetRoomEditors" then
		if not getOwnPlayerRoomForSettings(player) then
			roomSettingsResult:FireClient(player, {
				Kind = "RoomSettings",
				Action = "GetRoomEditors",
				Success = false,
				Message = "Only the room owner can manage editors.",
			})
			return
		end

		roomSettingsResult:FireClient(player, {
			Kind = "RoomSettings",
			Action = "GetRoomEditors",
			Success = true,
			Message = "Room editors loaded.",
			Editors = buildRoomEditorsList(player),
		})
		return
	end

	if safeActionName == "AddRoomEditor" or safeActionName == "RemoveRoomEditor" then
		local roomModel = getOwnPlayerRoomForSettings(player)

		if not roomModel then
			roomSettingsResult:FireClient(player, {
				Kind = "RoomSettings",
				Action = safeActionName,
				Success = false,
				Message = "Only the room owner can manage editors.",
			})
			return
		end

		if typeof(payload) ~= "table" then
			roomSettingsResult:FireClient(player, {
				Kind = "RoomSettings",
				Action = safeActionName,
				Success = false,
				Message = "Invalid user.",
			})
			return
		end

		local targetUserInput = getPermissionTargetInput(payload)
		local targetUserId, targetUserMessage, resolvedInputName =
			resolveUserInputToUserId(player, targetUserInput)

		if not targetUserId then
			roomSettingsResult:FireClient(player, {
				Kind = "RoomSettings",
				Action = safeActionName,
				Success = false,
				Message = targetUserMessage or "Invalid user.",
			})
			return
		end

		if targetUserIsCurrentPlayer(player, targetUserId, targetUserInput, resolvedInputName) then
			roomSettingsResult:FireClient(player, {
				Kind = "RoomSettings",
				Action = safeActionName,
				Success = false,
				Message = "You are already the room owner.",
			})
			return
		end

		local shouldAllow = safeActionName == "AddRoomEditor"
		local success, message = RoomPersistence.SetRoomEditorPermission(player, targetUserId, shouldAllow)
		local resolvedName = getResolvedUserName(targetUserId, resolvedInputName)

		if success and not shouldAllow then
			local removedPlayer = Players:GetPlayerByUserId(targetUserId)

			if removedPlayer
				and removedPlayer.UserId ~= player.UserId
				and removedPlayer:GetAttribute("CurrentRoomName") == roomModel.Name
				and removedPlayer:GetAttribute("RoomMode") == "Edit" then

				removedPlayer:SetAttribute("RoomMode", "Play")
			end
		end

		sendRoomEditorsResult(
			player,
			safeActionName,
			success == true,
			success and (shouldAllow and "Editor added." or "Editor removed.")
				or (message or "Could not update room editors."),
			success and targetUserId or nil,
			success and resolvedName or nil
		)
		return
	end

	if safeActionName == "GetSettings" then
		local settings = RoomPersistence.GetRoomDirectorySnapshot(player)

		if typeof(settings) ~= "table" then
			roomSettingsResult:FireClient(player, {
				Kind = "RoomSettings",
				Action = "GetSettings",
				Success = false,
				Message = "Room settings are not loaded.",
			})
			return
		end

		roomSettingsResult:FireClient(player, {
			Kind = "RoomSettings",
			Action = "GetSettings",
			Success = true,
			Message = "Room settings loaded.",
			Settings = settings,
		})
		return
	end

	if safeActionName == "UpdateSettings" then
		if typeof(payload) ~= "table" then
			roomSettingsResult:FireClient(player, {
				Kind = "RoomSettings",
				Action = "UpdateSettings",
				Success = false,
				Message = "Invalid room settings.",
			})
			return
		end

		local rawDescription = payload.Description

		if rawDescription == nil then
			rawDescription = ""
		end

		if typeof(payload.DisplayName) == "string" and typeof(rawDescription) == "string" then
			local rawPolicyOk, rawPolicyMessage, rawPolicyCategory, rawPolicyLength =
				validateRoomTextPolicy(payload.DisplayName, rawDescription)

			if not rawPolicyOk then
				warnRoomTextRejected(player, "CombinedRaw", rawPolicyCategory, rawPolicyLength)
				roomSettingsResult:FireClient(player, {
					Kind = "RoomSettings",
					Action = "UpdateSettings",
					Success = false,
					Message = rawPolicyMessage,
				})
				return
			end
		end

		local displayNameOk, displayNameMessage, filteredDisplayName = filterRoomTextForNavigator(
			player,
			payload.DisplayName,
			"Room name",
			ROOM_DISPLAY_NAME_MAX_LENGTH,
			false
		)

		if not displayNameOk then
			roomSettingsResult:FireClient(player, {
				Kind = "RoomSettings",
				Action = "UpdateSettings",
				Success = false,
				Message = displayNameMessage,
			})
			return
		end

		local descriptionOk, descriptionMessage, filteredDescription = filterRoomTextForNavigator(
			player,
			rawDescription,
			"Description",
			ROOM_DESCRIPTION_MAX_LENGTH,
			true
		)

		if not descriptionOk then
			roomSettingsResult:FireClient(player, {
				Kind = "RoomSettings",
				Action = "UpdateSettings",
				Success = false,
				Message = descriptionMessage,
			})
			return
		end

		local filteredPolicyOk, filteredPolicyMessage, filteredPolicyCategory, filteredPolicyLength =
			validateRoomTextPolicy(filteredDisplayName, filteredDescription)

		if not filteredPolicyOk then
			warnRoomTextRejected(player, "CombinedFiltered", filteredPolicyCategory, filteredPolicyLength)
			roomSettingsResult:FireClient(player, {
				Kind = "RoomSettings",
				Action = "UpdateSettings",
				Success = false,
				Message = filteredPolicyMessage,
			})
			return
		end

		local success, message, settings = RoomPersistence.UpdateRoomDirectory(player, {
			DisplayName = filteredDisplayName,
			Category = payload.Category,
			Description = filteredDescription,
			IsPublic = payload.IsPublic,
		})

		if success then
			local roomModel = playerRooms[player] or activeRooms:FindFirstChild(getRoomName(player))

			if roomModel and roomModel:IsA("Model") then
				applyPlayerRoomMetadataAttributes(roomModel, settings)
			end

			sendRoomListToAll()
		end

		roomSettingsResult:FireClient(player, {
			Kind = "RoomSettings",
			Action = "UpdateSettings",
			Success = success == true,
			Message = message or (success and "Room settings saved." or "Could not save room settings."),
			Settings = settings,
		})
		return
	end

	roomSettingsResult:FireClient(player, {
		Kind = "RoomSettings",
		Action = safeActionName,
		Success = false,
		Message = "Unknown room settings action.",
	})
end)

roomNavigatorRequest.OnServerEvent:Connect(function(player, actionName, payload)
	local safeActionName = typeof(actionName) == "string" and actionName or "Unknown"

	if safeActionName == "GetFavourites" then
		local favouriteKeys, entries = getFavouriteEntries(player)

		roomNavigatorResult:FireClient(player, {
			Kind = "Favourites",
			Success = true,
			Message = "Favourites loaded.",
			FavouriteKeys = favouriteKeys,
			Entries = entries,
		})
		return
	end

	if safeActionName == "ToggleFavourite" then
		if typeof(payload) ~= "table" or typeof(payload.RoomKey) ~= "string" then
			roomNavigatorResult:FireClient(player, {
				Kind = "ToggleFavourite",
				Success = false,
				Message = "Invalid favourite room.",
			})
			return
		end

		local roomKey = payload.RoomKey

		if not canFavouriteRoomKey(player, roomKey) then
			roomNavigatorResult:FireClient(player, {
				Kind = "ToggleFavourite",
				Success = false,
				RoomKey = roomKey,
				IsFavourite = false,
				Message = "This room cannot be favourited.",
			})
			return
		end

		local success, message, isFavourite = RoomPersistence.ToggleRoomFavourite(player, roomKey)

		roomNavigatorResult:FireClient(player, {
			Kind = "ToggleFavourite",
			Success = success == true,
			RoomKey = roomKey,
			IsFavourite = isFavourite == true,
			Message = message or (success and "Favourite updated." or "Could not update favourite."),
		})

		if success then
			sendRoomListToPlayer(player)
		end

		return
	end

	roomNavigatorResult:FireClient(player, {
		Kind = "Unknown",
		Success = false,
		Message = "Unknown room navigator action.",
	})
end)

joinRoomRequest.OnServerEvent:Connect(function(player, payload)
	if typeof(payload) == "table" then
		if payload.RoomType == "PublicSpace" then
			joinPublicRoom(player, payload.PublicRoomId)
		else
			joinRoomResult:FireClient(player, false, "Unknown room type.")
		end

		return
	end

	joinRoom(player, payload)
end)

leaveRoomRequest.OnServerEvent:Connect(function(player)
	leaveCurrentRoom(player)
end)

mainMenuIntroCompleteRequest.OnServerEvent:Connect(function(player)
	local profile = RoomPersistence.GetProfile(player)

	if not profile then
		return
	end

	local introVariant = player:GetAttribute("MainMenuIntroVariant")

	if introVariant == MAIN_MENU_INTRO_FIRST_VISIT_ONBOARDING then
		if player:GetAttribute("PendingOnboardingAfterIntro") == true then
			showOnboardingAfterHotelIntro(player, profile)
		end

		return
	end

	if introVariant ~= MAIN_MENU_INTRO_FIRST_VISIT then
		return
	end

	local success, message = RoomPersistence.MarkHotelIntroSeen(player)

	if not success then
		warn("Could not mark hotel intro seen for", player.Name, message)
		return
	end

	player:SetAttribute("MainMenuIntroVariant", MAIN_MENU_INTRO_RETURNING)
end)

tutorialFinishedRequest.OnServerEvent:Connect(function(player)
	if player:GetAttribute("OnboardingStep") ~= "Tutorial" then
		return
	end

	player:SetAttribute("OnboardingStep", "Complete")
	
	local profile = RoomPersistence.GetProfile(player)

	if profile then
		profile.OnboardingStep = "Complete"
		RoomPersistence.QueueSave(player)
	end

	if not RoomPersistence.HasSeenHotelIntro(player) then
		local success, message = RoomPersistence.MarkHotelIntroSeen(player)

		if not success then
			warn("Could not mark hotel intro seen after onboarding for", player.Name, message)
		end
	end

	-- Refresh this player’s navigator button/list availability.
	sendRoomListToPlayer(player)
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local ownedRoom = playerRooms[player]

		if ownedRoom and ownedRoom.Parent then
			capturePrimaryRoomState(player, ownedRoom)
		end

		RoomPersistence.SavePlayer(player)
	end
end)
