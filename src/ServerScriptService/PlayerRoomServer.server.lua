--Explorer/ServerScriptService/PlayerRoomServer.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TextService = game:GetService("TextService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local AdminConfig = require(ServerScriptService:WaitForChild("AdminConfig"))
local RoomPersistence = require(ServerScriptService:WaitForChild("RoomPersistence"))
local RoomPermissionService = require(ServerScriptService:WaitForChild("RoomPermissionService"))
local PublicRoomConfig = require(sharedFolder:WaitForChild("PublicRoomConfig"))
local RoomLayoutConfig = require(sharedFolder:WaitForChild("RoomLayoutConfig"))
local RoomFloorStyleConfig = require(sharedFolder:WaitForChild("RoomFloorStyleConfig"))
local RoomFloorStyleRenderer = require(sharedFolder:WaitForChild("RoomFloorStyleRenderer"))
local RoomTextPolicyConfig = require(sharedFolder:WaitForChild("RoomTextPolicyConfig"))
local GridConfig = require(sharedFolder:WaitForChild("GridConfig"))

local playerRooms = {}
local playerRoomSlots = {}
local nextRoomSlot = 0

local roomCreationInFlightByUserId = {}
local DEBUG_FLOOR_STYLE_OWNERSHIP = false

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
local LAYOUT_TEMPLATE_FALLBACKS = {
	Free_036_A = "Layout_01",
}
local ROOM_LAYOUT_TEMPLATE_NOT_READY_MESSAGE = "Room layout template is not ready yet."
local PRIMARY_ROOM_ID = "Primary"
local DEBUG_ROOM_LIST_TRACE = false
local DEBUG_ROOM_LIST_PAYLOAD = false

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

local function normalizeRoomId(roomId)
	if roomId == nil or roomId == "" then
		return PRIMARY_ROOM_ID
	end

	if typeof(roomId) ~= "string" then
		return nil
	end

	if not roomId:match("^[%w_-]+$") then
		return nil
	end

	return roomId
end

local function getPlayerByUserId(ownerUserId)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == ownerUserId then
			return player
		end
	end

	if ownerUserId < 0 then
		return nil
	end

	return Players:GetPlayerByUserId(ownerUserId)
end

local function getPlayerRoomName(ownerUserId, roomId)
	local normalizedRoomId = normalizeRoomId(roomId)
	local resolvedOwnerUserId = ownerUserId

	if typeof(ownerUserId) == "Instance" and ownerUserId:IsA("Player") then
		resolvedOwnerUserId = ownerUserId.UserId
	end

	local numericOwnerUserId = tonumber(resolvedOwnerUserId)

	if not normalizedRoomId
		or not numericOwnerUserId
		or numericOwnerUserId ~= numericOwnerUserId
		or math.abs(numericOwnerUserId) >= math.huge
		or numericOwnerUserId ~= math.floor(numericOwnerUserId) then

		return nil
	end

	if normalizedRoomId == PRIMARY_ROOM_ID then
		return "Room_" .. tostring(math.floor(numericOwnerUserId))
	end

	return "Room_" .. tostring(math.floor(numericOwnerUserId)) .. "_" .. normalizedRoomId
end

local function parsePlayerRoomName(roomName)
	if typeof(roomName) ~= "string" or roomName == "" then
		return nil, nil
	end

	local ownerUserIdText, roomId = roomName:match("^Room_(-?%d+)_([%w_-]+)$")

	if ownerUserIdText then
		return tonumber(ownerUserIdText), normalizeRoomId(roomId)
	end

	ownerUserIdText = roomName:match("^Room_(-?%d+)$")

	if ownerUserIdText then
		return tonumber(ownerUserIdText), PRIMARY_ROOM_ID
	end

	return nil, nil
end

local function canTestVipLayouts(player)
	if RunService:IsStudio() then
		return true
	end

	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	if player:GetAttribute("CanTestVipLayouts") == true or player:GetAttribute("IsAdmin") == true then
		return true
	end

	return AdminConfig.IsAdmin(player.UserId)
end

local function playerHasVip(player)
	if typeof(player) == "Instance"
		and player:IsA("Player")
		and player:GetAttribute("HasVip") == true then

		return true
	end

	return false
end

local function playerHasVipLayoutAccess(player)
	return playerHasVip(player) or canTestVipLayouts(player)
end

local function canUseDevLayouts(player)
	if RunService:IsStudio() then
		return true
	end

	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	if player:GetAttribute("CanUseDevLayouts") == true
		or player:GetAttribute("CanTestDevLayouts") == true
		or player:GetAttribute("IsAdmin") == true then

		return true
	end

	return AdminConfig.IsAdmin(player.UserId)
end

local function getLayoutAccessContext(player)
	local canUseVipLayouts = playerHasVipLayoutAccess(player)
	local canUseDevLayoutAccess = canUseDevLayouts(player)

	return {
		HasVip = playerHasVip(player),
		CanUseVipLayouts = canUseVipLayouts,
		CanTestVipLayouts = canTestVipLayouts(player),
		CanUseDevLayouts = canUseDevLayoutAccess,
		CanTestDevLayouts = canUseDevLayoutAccess,
	}
end

local function getRoomName(player)
	return getPlayerRoomName(player.UserId, PRIMARY_ROOM_ID)
end

local function resolveOwnedRoomTemplate(layoutId, warnOnFallback, player)
	if typeof(layoutId) ~= "string" or layoutId == "" then
		return nil, ROOM_LAYOUT_TEMPLATE_NOT_READY_MESSAGE
	end

	local layout = RoomLayoutConfig.GetLayout(layoutId)

	if typeof(layout) == "table" then
		local canUseLayout, layoutMessage = RoomLayoutConfig.CanUseLayout(layoutId, getLayoutAccessContext(player))

		if not canUseLayout then
			return nil, layoutMessage or ROOM_LAYOUT_TEMPLATE_NOT_READY_MESSAGE
		end

		local templateName = layout.TemplateName

		if typeof(templateName) == "string" and templateName ~= "" then
			local template = roomTemplates:FindFirstChild(templateName)

			if template then
				return template, nil, templateName
			end
		end

		if layoutId == "Free_036_A" then
			local fallbackTemplateName = LAYOUT_TEMPLATE_FALLBACKS[layoutId]
			local fallbackTemplate = fallbackTemplateName and roomTemplates:FindFirstChild(fallbackTemplateName) or nil

			if fallbackTemplate then
				if warnOnFallback then
					warn("RoomLayout_Free_036_A missing; using Layout_01 fallback.")
				end

				return fallbackTemplate, nil, fallbackTemplateName
			end
		end

		return nil, ROOM_LAYOUT_TEMPLATE_NOT_READY_MESSAGE
	end

	if VALID_LAYOUTS[layoutId] then
		local template = roomTemplates:FindFirstChild(layoutId)

		if template then
			return template, nil, layoutId
		end
	end

	return nil, ROOM_LAYOUT_TEMPLATE_NOT_READY_MESSAGE
end

local function resolveTemplateNameForLayout(layoutId, warnOnFallback, player)
	local _, errorMessage, templateName = resolveOwnedRoomTemplate(layoutId, warnOnFallback, player)
	return templateName, errorMessage
end

local function getOwnedLayoutJoinability(layoutId, player)
	local template, errorMessage = resolveOwnedRoomTemplate(layoutId, false, player)
	return template ~= nil, errorMessage
end

local function isJoinableOwnedLayout(layoutId, player)
	local isJoinable = getOwnedLayoutJoinability(layoutId, player)
	return isJoinable == true
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
		or numericUserId == 0
		or math.abs(numericUserId) >= math.huge
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

	local normalizedUsername = string.lower(username)

	for _, candidatePlayer in ipairs(Players:GetPlayers()) do
		if string.lower(candidatePlayer.Name) == normalizedUsername
			or string.lower(candidatePlayer.DisplayName) == normalizedUsername then

			return candidatePlayer.UserId, nil, candidatePlayer.Name
		end
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
	local targetPlayer = getPlayerByUserId(userId)

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

	local primaryRoomName = getRoomName(player)
	local activePrimaryRoom = primaryRoomName and activeRooms:FindFirstChild(primaryRoomName)

	if activePrimaryRoom and activePrimaryRoom ~= existingRoom then
		activePrimaryRoom:Destroy()
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

local function applyOwnedRoomFloorStyle(roomModel, ownerPlayer, roomId)
	if not roomModel or not roomModel:IsA("Model") then
		return
	end

	local floorStyleId = RoomPersistence.GetRoomFloorStyle(ownerPlayer, roomId)
	local success, applied, message = pcall(function()
		return RoomFloorStyleRenderer.ApplyFloorStyle(roomModel, floorStyleId)
	end)

	if not success then
		warn(
			"Could not apply owned room floor style:",
			ownerPlayer and ownerPlayer.Name or "unknown",
			tostring(roomId),
			applied
		)
		return
	end

	if not applied then
		warn(
			"Could not apply owned room floor style:",
			ownerPlayer and ownerPlayer.Name or "unknown",
			tostring(roomId),
			message
		)
	end
end

local function cloneRoomForPlayer(player, layoutId, roomId)
	local template, templateError, templateName = resolveOwnedRoomTemplate(layoutId, true, player)

	if not template then
		warn("Invalid layout requested:", layoutId, templateError)
		return nil
	end

	local normalizedRoomId = normalizeRoomId(roomId)

	if not normalizedRoomId then
		warn("Invalid room id requested:", roomId)
		return nil
	end

	removePlayerRoom(player)

	local roomClone = template:Clone()
	local roomName = getPlayerRoomName(player.UserId, normalizedRoomId)

	if typeof(roomName) ~= "string" or roomName == "" then
		warn("Could not resolve active room name for", player.Name, "room id:", normalizedRoomId)
		roomName = "Room_" .. tostring(player.UserId)
	end

	roomClone.Name = roomName
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
	roomClone:SetAttribute("TemplateName", templateName)
	roomClone:SetAttribute("RoomType", "PlayerRoom")
	roomClone:SetAttribute("RoomId", normalizedRoomId)
	roomClone:SetAttribute("RoomKey", roomClone.Name)
	roomClone:SetAttribute("DisplayName", player.DisplayName .. "'s Room")
	applyOwnedRoomFloorStyle(roomClone, player, normalizedRoomId)
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
	setCurrentRoomContextAttributes(player, "PublicSpace", nil, publicRoomId)
end

local function forceStandPlayer(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	local character = player.Character

	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not humanoid then
		return
	end

	if humanoid.Sit ~= true and humanoid.SeatPart == nil then
		return
	end

	humanoid.Sit = false
	humanoid.PlatformStand = false
	humanoid.Jump = true

	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end)

	task.wait()
end

local function movePlayerToRoom(player, roomModel)
	forceStandPlayer(player)

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
	forceStandPlayer(player)

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
	forceStandPlayer(player)

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

	return getPlayerByUserId(ownerUserId)
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

local function getSettingsPayloadRoomId(payload)
	if typeof(payload) ~= "table" or payload.RoomId == nil then
		return PRIMARY_ROOM_ID
	end

	return normalizeRoomId(payload.RoomId)
end

local function getActiveOwnedRoomModel(ownerPlayer, roomId)
	local normalizedRoomId = normalizeRoomId(roomId)

	if typeof(ownerPlayer) ~= "Instance" or not ownerPlayer:IsA("Player") or not normalizedRoomId then
		return nil
	end

	local function isMatchingOwnedRoom(roomModel)
		return roomModel
			and roomModel:IsA("Model")
			and roomModel:GetAttribute("RoomType") ~= "PublicSpace"
			and roomModel:GetAttribute("OwnerUserId") == ownerPlayer.UserId
			and normalizeRoomId(roomModel:GetAttribute("RoomId")) == normalizedRoomId
	end

	local activeRoomName = getPlayerRoomName(ownerPlayer.UserId, normalizedRoomId)
	local roomModel = activeRoomName and activeRooms:FindFirstChild(activeRoomName) or nil

	if isMatchingOwnedRoom(roomModel) then
		return roomModel
	end

	for _, candidate in ipairs(activeRooms:GetChildren()) do
		if isMatchingOwnedRoom(candidate) then
			return candidate
		end
	end

	return nil
end

local function playerOccupiesRoomModel(player, roomModel)
	if typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or typeof(roomModel) ~= "Instance"
		or not roomModel:IsA("Model") then

		return false
	end

	if player:GetAttribute("CurrentRoomName") == roomModel.Name then
		return true
	end

	if player:GetAttribute("CurrentRoomType") ~= "PlayerRoom" then
		return false
	end

	local ownerUserId = roomModel:GetAttribute("OwnerUserId")

	return player:GetAttribute("CurrentRoomId") == roomModel:GetAttribute("RoomId")
		and typeof(ownerUserId) == "number"
		and player:GetAttribute("CurrentRoomOwnerUserId") == ownerUserId
end

local function roomModelHasOccupants(roomModel)
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if playerOccupiesRoomModel(otherPlayer, roomModel) then
			return true
		end
	end

	return false
end

local function destroyOwnedRoomCloneIfEmpty(roomModel)
	if typeof(roomModel) ~= "Instance"
		or not roomModel:IsA("Model")
		or roomModel:GetAttribute("RoomType") == "PublicSpace"
		or roomModelHasOccupants(roomModel) then

		return false
	end

	local ownerUserId = roomModel:GetAttribute("OwnerUserId")

	if typeof(ownerUserId) ~= "number" then
		return false
	end

	local ownerPlayer = getPlayerByUserId(ownerUserId)

	if ownerPlayer and playerRooms[ownerPlayer] == roomModel then
		playerRooms[ownerPlayer] = nil
	end

	roomModel:Destroy()
	return true
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

local function getRoomRecordMetadata(roomRecord, ownerDisplayName)
	local fallback = getFallbackRoomMetadata(ownerDisplayName)

	if typeof(roomRecord) ~= "table" then
		return fallback
	end

	local roomId = roomRecord.RoomId
	if typeof(roomId) ~= "string" or roomId == "" then
		roomId = fallback.RoomId
	end

	local displayName = roomRecord.DisplayName
	if typeof(displayName) ~= "string" or displayName == "" then
		displayName = fallback.DisplayName
	end

	local category = roomRecord.Category
	if typeof(category) ~= "string" or category == "" then
		category = fallback.Category
	end

	local isPublic = roomRecord.IsPublic
	if typeof(isPublic) ~= "boolean" then
		isPublic = fallback.IsPublic
	end

	local maxOccupancy = roomRecord.MaxOccupancy
	if typeof(maxOccupancy) ~= "number"
		or maxOccupancy ~= maxOccupancy
		or maxOccupancy <= 0
		or maxOccupancy >= math.huge
		or maxOccupancy ~= math.floor(maxOccupancy) then

		maxOccupancy = fallback.MaxOccupancy
	end

	local description = roomRecord.Description
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
		Tags = copyRoomTags(roomRecord.Tags),
	}
end

local function applyPlayerRoomMetadataAttributes(roomModel, metadata, ownerUserId, layoutId)
	if not roomModel or not roomModel:IsA("Model") or typeof(metadata) ~= "table" then
		return
	end

	local roomId = normalizeRoomId(metadata.RoomId) or PRIMARY_ROOM_ID
	local resolvedOwnerUserId = tonumber(ownerUserId) or roomModel:GetAttribute("OwnerUserId")

	roomModel:SetAttribute("RoomType", "PlayerRoom")
	roomModel:SetAttribute("RoomId", roomId)
	roomModel:SetAttribute("OwnerUserId", resolvedOwnerUserId)
	roomModel:SetAttribute("RoomKey", getPlayerRoomName(resolvedOwnerUserId, roomId))
	if typeof(layoutId) == "string" and layoutId ~= "" then
		roomModel:SetAttribute("LayoutId", layoutId)
	end
	roomModel:SetAttribute("DisplayName", metadata.DisplayName)
	roomModel:SetAttribute("Category", metadata.Category)
	roomModel:SetAttribute("IsPublic", metadata.IsPublic == true)
	roomModel:SetAttribute("MaxOccupancy", metadata.MaxOccupancy)
	roomModel:SetAttribute("Description", metadata.Description)
end

local function getOwnedRoomActiveName(ownerPlayer, roomId)
	return getPlayerRoomName(ownerPlayer.UserId, roomId)
end

local function getOwnedRoomEntry(ownerPlayer, roomRecord, currentRoomName)
	if typeof(ownerPlayer) ~= "Instance"
		or not ownerPlayer:IsA("Player")
		or typeof(roomRecord) ~= "table" then

		return nil
	end

	local ownerName = ownerPlayer.Name
	local ownerDisplayName = ownerPlayer.DisplayName
	local metadata = getRoomRecordMetadata(roomRecord, ownerDisplayName)
	local roomId = metadata.RoomId
	local activeRoomName = getOwnedRoomActiveName(ownerPlayer, roomId)
	local activeRoom = activeRoomName and activeRooms:FindFirstChild(activeRoomName) or nil
	local occupancy = activeRoom and getPlayerCountInRoom(activeRoom.Name) or 0
	local layoutId = roomRecord.LayoutId

	if (typeof(layoutId) ~= "string" or layoutId == "")
		and activeRoom
		and typeof(activeRoom:GetAttribute("LayoutId")) == "string" then

		layoutId = activeRoom:GetAttribute("LayoutId")
	end

	if typeof(layoutId) ~= "string" or layoutId == "" then
		layoutId = "Unknown"
	end

	local isJoinable, joinDisabledReason = getOwnedLayoutJoinability(layoutId, ownerPlayer)

	if activeRoom and activeRoom:IsA("Model") then
		applyPlayerRoomMetadataAttributes(activeRoom, metadata, ownerPlayer.UserId, layoutId)
	end

	local roomKey = "PlayerRoom:" .. tostring(ownerPlayer.UserId) .. ":" .. roomId
	local isCurrentRoom = activeRoomName ~= nil and activeRoomName == currentRoomName

	return {
		RoomName = activeRoom and activeRoom.Name or nil,
		Name = activeRoom and activeRoom.Name or roomKey,
		Owner = ownerName,
		OwnerUserId = ownerPlayer.UserId,
		OwnerName = ownerName,
		OwnerDisplayName = ownerDisplayName,
		LayoutId = layoutId,
		PlayerCount = occupancy,

		RoomType = "PlayerRoom",
		RoomId = roomId,
		Id = roomId,
		RoomKey = roomKey,
		DisplayName = metadata.DisplayName,
		RoomDisplayName = metadata.DisplayName,
		Category = metadata.Category,
		IsPublic = metadata.IsPublic,
		Occupancy = occupancy,
		MaxOccupancy = metadata.MaxOccupancy,
		Description = metadata.Description,
		Tags = metadata.Tags,
		IsOwner = true,
		IsPrimary = roomRecord.IsPrimary == true or roomId == PRIMARY_ROOM_ID,
		SortOrder = roomRecord.SortOrder,
		IsActive = activeRoom ~= nil,
		IsCurrentRoom = isCurrentRoom,
		Current = isCurrentRoom,
		IsFavourite = RoomPersistence.IsRoomFavourite(ownerPlayer, roomKey) == true,
		IsJoinable = isJoinable,
		IsAvailable = isJoinable,
		JoinDisabledReason = isJoinable and nil or joinDisabledReason,
	}
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
	local seenPlayerRoomKeys = {}
	local validOwnedRoomIds = {}
	local ownedRoomIds = {}

	if viewerPlayer then
		local profile = RoomPersistence.GetProfile(viewerPlayer)

		if profile and profile.ProfileCreated == true then
			local ownedRoomSnapshot = RoomPersistence.GetOwnedRoomsSnapshot(viewerPlayer)

			if DEBUG_ROOM_LIST_TRACE and #ownedRoomSnapshot == 0 then
				warn("RoomList snapshot unexpectedly had no owned rooms for", viewerPlayer.Name)
			end

			for _, roomRecord in ipairs(ownedRoomSnapshot) do
				local roomId = normalizeRoomId(roomRecord.RoomId)

				if roomId then
					validOwnedRoomIds[roomId] = true
					table.insert(ownedRoomIds, roomId)
				end

				local ownedRoomEntry = getOwnedRoomEntry(viewerPlayer, roomRecord, currentRoomName)

				if ownedRoomEntry then
					seenPlayerRoomKeys[ownedRoomEntry.RoomKey] = true
					table.insert(roomList, ownedRoomEntry)
				end
			end

			if DEBUG_ROOM_LIST_TRACE then
				local profileRoomIds = {}
				local directoryRoomIds = {}

				if typeof(profile.Rooms) == "table" then
					for profileRoomId in pairs(profile.Rooms) do
						table.insert(profileRoomIds, tostring(profileRoomId))
					end
				end

				if typeof(profile.RoomDirectory) == "table" and typeof(profile.RoomDirectory.RoomIds) == "table" then
					for _, directoryRoomId in ipairs(profile.RoomDirectory.RoomIds) do
						table.insert(directoryRoomIds, tostring(directoryRoomId))
					end
				end

				warn(string.format(
					"RoomList snapshot for %s: profileRooms=%s directoryRoomIds=%s snapshotOwned=%s",
					viewerPlayer.Name,
					table.concat(profileRoomIds, ","),
					table.concat(directoryRoomIds, ","),
					table.concat(ownedRoomIds, ",")
				))
			end
		end
	end

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

			local roomId = normalizeRoomId(roomModel:GetAttribute("RoomId")) or PRIMARY_ROOM_ID
			local roomRecord = ownerPlayer and RoomPersistence.GetRoomRecord(ownerPlayer, roomId) or nil

			if not roomRecord then
				if DEBUG_ROOM_LIST_TRACE then
					warn(string.format(
						"Skipping active player room without persisted room record: %s owner=%s roomId=%s",
						roomModel.Name,
						tostring(ownerUserId),
						tostring(roomId)
					))
				end

				continue
			end

			local metadata = getRoomRecordMetadata(roomRecord, ownerDisplayName)
			roomId = metadata.RoomId
			applyPlayerRoomMetadataAttributes(roomModel, metadata, ownerUserId, layoutId)

			local isOwner = typeof(ownerUserId) == "number"
				and viewerPlayer
				and viewerPlayer.UserId == ownerUserId

			if isOwner and not validOwnedRoomIds[roomId] then
				if DEBUG_ROOM_LIST_TRACE then
					warn(string.format(
						"Skipping active owned room not in latest owned snapshot: %s owner=%s roomId=%s",
						roomModel.Name,
						tostring(ownerUserId),
						tostring(roomId)
					))
				end

				continue
			end

			if metadata.IsPublic or isOwner then
				local playerCount = getPlayerCountInRoom(roomModel.Name)
				local roomKey = "PlayerRoom:" .. tostring(ownerUserId) .. ":" .. roomId
				local isJoinable, joinDisabledReason = getOwnedLayoutJoinability(layoutId, viewerPlayer)

				if not seenPlayerRoomKeys[roomKey] then
					if DEBUG_ROOM_LIST_TRACE and not isOwner then
						warn(string.format(
							"RoomList guest row from ActiveRooms: viewer=%s owner=%s roomId=%s roomName=%s",
							viewerPlayer and viewerPlayer.Name or "Unknown",
							tostring(ownerUserId),
							tostring(roomId),
							roomModel.Name
						))
					end

					table.insert(roomList, {
						RoomName = roomModel.Name,
						Name = roomModel.Name,
						Owner = ownerName,
						OwnerUserId = ownerUserId,
						OwnerName = ownerName,
						OwnerDisplayName = ownerDisplayName,
						LayoutId = layoutId or "Unknown",
						PlayerCount = playerCount,

						RoomType = "PlayerRoom",
						RoomId = roomId,
						Id = roomId,
						RoomKey = roomKey,
						DisplayName = metadata.DisplayName,
						RoomDisplayName = metadata.DisplayName,
						Category = metadata.Category,
						IsPublic = metadata.IsPublic,
						Occupancy = playerCount,
						MaxOccupancy = metadata.MaxOccupancy,
						Description = metadata.Description,
						Tags = metadata.Tags,
						IsOwner = isOwner == true,
						IsPrimary = roomId == PRIMARY_ROOM_ID,
						IsActive = true,
						IsCurrentRoom = roomModel.Name == currentRoomName,
						Current = roomModel.Name == currentRoomName,
						IsFavourite = viewerPlayer and RoomPersistence.IsRoomFavourite(viewerPlayer, roomKey) == true or false,
						IsJoinable = isJoinable,
						IsAvailable = isJoinable,
						JoinDisabledReason = isJoinable and nil or joinDisabledReason,
					})
				end
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

	return roomList, ownedRoomIds
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

local function getSortedDictionaryKeys(dictionary)
	local keys = {}

	if typeof(dictionary) == "table" then
		for key in pairs(dictionary) do
			table.insert(keys, tostring(key))
		end
	end

	table.sort(keys)
	return keys
end

local function getOwnedRoomRowIds(roomList)
	local ownedRowIds = {}

	for _, roomEntry in ipairs(roomList or {}) do
		if roomEntry.IsOwner == true and typeof(roomEntry.RoomId) == "string" then
			table.insert(ownedRowIds, roomEntry.RoomId)
		end
	end

	table.sort(ownedRowIds)
	return ownedRowIds
end

local function ensureRoomListProfile(player)
	local profile = RoomPersistence.GetProfile(player)

	if not profile then
		profile = RoomPersistence.LoadProfile(player)
	end

	if profile and RoomPersistence.EnsureRoomsSchema then
		RoomPersistence.EnsureRoomsSchema(profile)
	end

	return profile
end

local function buildRoomListMetadata(ownedRoomIds)
	return {
		OwnedRoomIds = table.clone(ownedRoomIds or {}),
		RoomListVersion = os.clock(),
	}
end

local function traceRoomListPayload(player, roomList, ownedRoomIds, metadata)
	if not DEBUG_ROOM_LIST_PAYLOAD then
		return
	end

	local profile = RoomPersistence.GetProfile(player)
	local profileRoomIds = profile and getSortedDictionaryKeys(profile.Rooms) or {}
	local directoryRoomIds = {}
	local snapshotRoomIds = {}

	if profile and typeof(profile.RoomDirectory) == "table" and typeof(profile.RoomDirectory.RoomIds) == "table" then
		for _, roomId in ipairs(profile.RoomDirectory.RoomIds) do
			table.insert(directoryRoomIds, tostring(roomId))
		end
	end

	for _, roomRecord in ipairs(RoomPersistence.GetOwnedRoomsSnapshot(player)) do
		table.insert(snapshotRoomIds, tostring(roomRecord.RoomId))
	end

	table.sort(directoryRoomIds)
	table.sort(snapshotRoomIds)

	warn(string.format(
		"RoomList payload player=%s userId=%s version=%s profileRooms=%s directoryRoomIds=%s snapshotOwned=%s sentOwnedRows=%s metaOwned=%s",
		player.Name,
		tostring(player.UserId),
		tostring(metadata and metadata.RoomListVersion),
		table.concat(profileRoomIds, ","),
		table.concat(directoryRoomIds, ","),
		table.concat(snapshotRoomIds, ","),
		table.concat(getOwnedRoomRowIds(roomList), ","),
		table.concat(metadata and metadata.OwnedRoomIds or {}, ",")
	))
end

local function sendRoomListToPlayer(player)
	ensureRoomListProfile(player)

	local roomList, ownedRoomIds = buildRoomList(player)
	local metadata = buildRoomListMetadata(ownedRoomIds)

	if DEBUG_ROOM_LIST_TRACE then
		local sentOwnedRoomIds = {}

		for _, roomEntry in ipairs(roomList) do
			if roomEntry.IsOwner == true and typeof(roomEntry.RoomId) == "string" then
				table.insert(sentOwnedRoomIds, roomEntry.RoomId)
			end
		end

		warn(string.format(
			"RoomList send to %s: snapshotOwned=%s sentOwnedRows=%s",
			player.Name,
			table.concat(ownedRoomIds or {}, ","),
			table.concat(sentOwnedRoomIds, ",")
		))
	end

	traceRoomListPayload(player, roomList, ownedRoomIds, metadata)
	roomListUpdate:FireClient(player, roomList, player:GetAttribute("CurrentRoomName"), metadata)
end

local function sendRoomListToAll()
	for _, player in ipairs(Players:GetPlayers()) do
		ensureRoomListProfile(player)

		local roomList, ownedRoomIds = buildRoomList(player)
		local metadata = buildRoomListMetadata(ownedRoomIds)

		if DEBUG_ROOM_LIST_TRACE then
			local sentOwnedRoomIds = {}

			for _, roomEntry in ipairs(roomList) do
				if roomEntry.IsOwner == true and typeof(roomEntry.RoomId) == "string" then
					table.insert(sentOwnedRoomIds, roomEntry.RoomId)
				end
			end

			warn(string.format(
				"RoomList send to %s: snapshotOwned=%s sentOwnedRows=%s",
				player.Name,
				table.concat(ownedRoomIds or {}, ","),
				table.concat(sentOwnedRoomIds, ",")
			))
		end

		traceRoomListPayload(player, roomList, ownedRoomIds, metadata)
		roomListUpdate:FireClient(player, roomList, player:GetAttribute("CurrentRoomName"), metadata)
	end
end

local function buildRoomEditorsList(ownerPlayer, roomId)
	return RoomPersistence.GetRoomEditorsForRoom(ownerPlayer, roomId)
end

local function sendRoomEditorsResult(player, actionName, roomId, success, message, resolvedUserId, resolvedName)
	local response = {
		Kind = "RoomSettings",
		Action = actionName,
		Success = success == true,
		Message = message,
		RoomId = roomId,
		Editors = buildRoomEditorsList(player, roomId),
	}

	if resolvedUserId then
		response.ResolvedUserId = resolvedUserId
		response.ResolvedName = resolvedName
	end

	roomSettingsResult:FireClient(player, response)
end

local function getCurrentActiveRoomModel(player)
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

local function getRoomFloorStyleRequestId(payload)
	if typeof(payload) ~= "table" then
		return nil
	end

	if typeof(payload.RequestId) == "number" then
		return payload.RequestId
	end

	return nil
end

local function buildRoomFloorStyleEntry(ownerPlayer, style, currentFloorStyleId)
	if typeof(style) ~= "table" or typeof(style.FloorStyleId) ~= "string" then
		return nil
	end

	if not RoomFloorStyleConfig.IsValidStyleId(style.FloorStyleId) then
		return nil
	end

	if style.Hidden == true or style.IsHidden == true or style.DevOnly == true then
		return nil
	end

	local isStarter = style.IsDefault == true or style.IsStarter == true
	local isFree = RoomFloorStyleConfig.IsFreeStyle(style.FloorStyleId)
	local applyPrice, currencyKey = RoomFloorStyleConfig.GetApplyCost(style.FloorStyleId)
	applyPrice = typeof(applyPrice) == "number" and math.floor(applyPrice) or 0
	currencyKey = typeof(currencyKey) == "string" and currencyKey or "Dollars"

	local canPreview = RoomFloorStyleConfig.CanPreviewStyle(style.FloorStyleId)
	local intentionallyUnavailable = style.Unavailable == true
		or style.IsUnavailable == true
		or style.Available == false
	local isCurrent = style.FloorStyleId == currentFloorStyleId
	local previewable = canPreview == true and not intentionallyUnavailable
	local applyCost = isCurrent and 0 or applyPrice
	local canApply = false
	local unavailable = false
	local unavailableReason = nil

	if isCurrent then
		canApply = false
	elseif intentionallyUnavailable then
		unavailable = true
		unavailableReason = style.UnavailableReason or "Unavailable"
	elseif isFree then
		canApply = true
	elseif style.CanPurchase ~= true then
		unavailable = true
		unavailableReason = "Unavailable"
	elseif applyPrice <= 0 then
		unavailable = true
		unavailableReason = "Unavailable"
	elseif currencyKey ~= "Dollars" then
		unavailable = true
		unavailableReason = "Unavailable"
	else
		local currencies = ownerPlayer and RoomPersistence.GetCurrenciesSnapshot(ownerPlayer) or nil
		local dollarsBalance = typeof(currencies) == "table" and currencies.Dollars or 0

		if typeof(dollarsBalance) ~= "number" then
			dollarsBalance = 0
		end

		if dollarsBalance >= applyPrice then
			canApply = true
		else
			unavailable = true
			unavailableReason = "Not enough Dollars"
		end
	end

	if DEBUG_FLOOR_STYLE_OWNERSHIP then
		print(
			"Floor style apply",
			ownerPlayer and ownerPlayer.Name or "nil",
			style.FloorStyleId,
			"isFree=" .. tostring(isFree),
			"price=" .. tostring(applyPrice),
			"currency=" .. tostring(currencyKey),
			"canApply=" .. tostring(canApply),
			"unavailable=" .. tostring(unavailable),
			"reason=" .. tostring(unavailableReason)
		)
	end

	return {
		FloorStyleId = style.FloorStyleId,
		DisplayName = style.DisplayName,
		Description = style.Description,
		Pattern = style.Pattern,
		IsStarter = isStarter,
		CanPurchase = style.CanPurchase == true,
		Price = typeof(style.Price) == "number" and style.Price or (applyPrice or 0),
		CurrencyKey = currencyKey or style.CurrencyKey or "Dollars",
		ApplyPrice = applyPrice,
		ApplyCost = applyCost,
		ApplyCurrencyKey = currencyKey,
		IsFree = isFree,
		CanPreview = previewable == true,
		Previewable = previewable == true,
		CanApply = canApply,
		AlreadyCurrent = isCurrent,
		Unavailable = unavailable == true,
		UnavailableReason = unavailableReason,
		SortOrder = style.SortOrder,
		Current = isCurrent,
	}
end

local function buildRoomFloorStyleEntries(ownerPlayer, currentFloorStyleId)
	local entries = {}

	for _, style in ipairs(RoomFloorStyleConfig.GetAllStyles()) do
		local entry = buildRoomFloorStyleEntry(ownerPlayer, style, currentFloorStyleId)

		if entry then
			table.insert(entries, entry)
		end
	end

	return entries
end

local function getEditableFloorStyleTarget(player, payload)
	local roomId = getSettingsPayloadRoomId(payload)

	if not roomId then
		return nil, nil, nil, nil, "Room not found."
	end

	local currentRoomModel = getCurrentActiveRoomModel(player)

	if currentRoomModel then
		local currentRoomId = normalizeRoomId(currentRoomModel:GetAttribute("RoomId"))

		if currentRoomId == roomId then
			if currentRoomModel:GetAttribute("RoomType") == "PublicSpace" then
				return nil, roomId, nil, nil, "Room styling is only available in your own rooms."
			end

			if RoomPermissionService.CanEditRoom(player, currentRoomModel) then
				local ownerPlayer = getRoomOwnerPlayer(currentRoomModel)

				if not ownerPlayer then
					return nil, roomId, nil, currentRoomModel, "Room owner is not available."
				end

				local roomRecord = RoomPersistence.GetRoomRecord(ownerPlayer, roomId)

				if typeof(roomRecord) ~= "table" then
					return nil, roomId, nil, currentRoomModel, "Room not found."
				end

				return ownerPlayer, roomId, roomRecord, currentRoomModel, nil
			end
		end
	end

	local roomRecord = RoomPersistence.GetRoomRecord(player, roomId)

	if typeof(roomRecord) == "table" then
		return player, roomId, roomRecord, getActiveOwnedRoomModel(player, roomId), nil
	end

	return nil, roomId, nil, nil, "Room styling is only available in your own rooms."
end

local function sendRoomFloorStylesResult(player, ownerPlayer, roomId, success, message, requestId, silent)
	local currentFloorStyleId = ownerPlayer and RoomPersistence.GetRoomFloorStyle(ownerPlayer, roomId) or nil

	roomSettingsResult:FireClient(player, {
		Kind = "GetRoomFloorStyles",
		Action = "GetRoomFloorStyles",
		RequestId = requestId,
		Silent = silent == true,
		Success = success == true,
		Message = message,
		RoomId = roomId,
		CurrentFloorStyleId = currentFloorStyleId,
		Styles = success and buildRoomFloorStyleEntries(ownerPlayer, currentFloorStyleId) or {},
	})
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
		return nil, nil, nil, nil, "Invalid furniture permission request."
	end

	if payload.ActionName ~= "OpenClose" then
		return nil, nil, nil, nil, "Unsupported furniture permission action."
	end

	local roomModel = getCurrentPlayerRoomForFurniturePermissions(player)

	if not roomModel then
		return nil, nil, nil, nil, "Only the room owner can manage furniture permissions."
	end

	if not RoomPermissionService.IsPlayerRoom(roomModel) then
		return nil, nil, nil, nil, "Furniture permissions are only available in player rooms."
	end

	local requestedRoomId = normalizeRoomId(payload.RoomId)

	if not requestedRoomId then
		return nil, nil, nil, nil, "Invalid room id."
	end

	local activeRoomId = normalizeRoomId(roomModel:GetAttribute("RoomId"))

	if activeRoomId ~= requestedRoomId then
		return nil, nil, nil, requestedRoomId, "Room mismatch."
	end

	if not RoomPersistence.GetRoomRecord(player, requestedRoomId) then
		return nil, nil, nil, requestedRoomId, "Room not found."
	end

	local furnitureModel = payload.Furniture

	if typeof(furnitureModel) ~= "Instance" or not furnitureModel:IsA("Model") then
		return nil, nil, nil, requestedRoomId, "Invalid furniture."
	end

	local furnitureFolder = getFurnitureFolder(roomModel)

	if not furnitureFolder or not furnitureModel:IsDescendantOf(furnitureFolder) then
		return nil, nil, nil, requestedRoomId, "Invalid furniture."
	end

	if not RoomPermissionService.FurnitureSupportsPermission(furnitureModel, "OpenClose") then
		return nil, nil, nil, requestedRoomId, "This furniture does not support Open/Close permissions."
	end

	local persistentId = RoomPermissionService.GetFurniturePersistentId(furnitureModel)

	if not persistentId then
		return nil, nil, nil, requestedRoomId, "This furniture is missing a persistent id."
	end

	return roomModel, furnitureModel, persistentId, requestedRoomId, nil
end

local function validateFurnitureActionAccessTarget(player, payload)
	if typeof(payload) ~= "table" then
		return nil, nil, nil, nil, "Invalid furniture action access request."
	end

	local roomName = player:GetAttribute("CurrentRoomName")

	if typeof(roomName) ~= "string" or roomName == "" then
		return nil, nil, nil, nil, "You are not in a room."
	end

	local roomModel = activeRooms:FindFirstChild(roomName)

	if not roomModel or not roomModel:IsA("Model") then
		return nil, nil, nil, nil, "Current room is unavailable."
	end

	local requestedRoomId = normalizeRoomId(payload.RoomId)

	if not requestedRoomId then
		return nil, nil, nil, nil, "Invalid room id."
	end

	local roomModelRoomId = roomModel:GetAttribute("RoomId")
	local activeRoomId = normalizeRoomId(roomModelRoomId)

	if roomModel:GetAttribute("RoomType") == "PublicSpace"
		and (typeof(roomModelRoomId) ~= "string" or roomModelRoomId == "") then

		activeRoomId = normalizeRoomId(player:GetAttribute("CurrentRoomId")) or requestedRoomId
	end

	if activeRoomId ~= requestedRoomId then
		return nil, nil, requestedRoomId, nil, "Room mismatch."
	end

	local furnitureModel = payload.Furniture

	if typeof(furnitureModel) ~= "Instance" or not furnitureModel:IsA("Model") then
		return nil, nil, requestedRoomId, nil, "Invalid furniture."
	end

	local furnitureFolder = getFurnitureFolder(roomModel)

	if not furnitureFolder or not furnitureModel:IsDescendantOf(furnitureFolder) then
		return nil, nil, requestedRoomId, nil, "Invalid furniture."
	end

	return roomModel, furnitureModel, requestedRoomId, RoomPermissionService.GetFurniturePersistentId(furnitureModel), nil
end

local function sendFurnitureActionAccessResult(
	player,
	success,
	message,
	furnitureModel,
	accessSummary,
	requestId,
	roomId,
	persistentId
)
	local response = {
		Kind = "FurnitureActionAccess",
		Success = success == true,
		Furniture = furnitureModel,
		RequestId = requestId,
		RoomId = roomId,
		FurniturePersistentId = persistentId,
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

local function buildFurniturePermissionEntries(ownerPlayer, roomId, persistentId, actionName)
	local furniturePermissions = RoomPersistence.GetFurniturePermissionsForRoom(ownerPlayer, roomId, persistentId)
	local entries = {}

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

			if userId and userId ~= 0 and userId ~= ownerPlayer.UserId then
				local targetPlayer = getPlayerByUserId(userId)
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

local function sendFurniturePermissionResult(
	player,
	requestAction,
	success,
	message,
	persistentId,
	entries,
	resolvedUserId,
	resolvedName,
	roomId
)
	local response = {
		Kind = "FurniturePermissions",
		RequestAction = requestAction,
		Success = success == true,
		Message = message,
		FurniturePersistentId = persistentId,
		RoomId = roomId,
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

local function getSavedRoom(player, profile, roomId)
	local normalizedRoomId = normalizeRoomId(roomId)

	if not normalizedRoomId then
		return nil
	end

	local roomRecord = RoomPersistence.GetRoomRecord(player, normalizedRoomId)

	if not roomRecord then
		return nil
	end

	local primaryRoomState = RoomPersistence.GetRoomStateForRoom(player, normalizedRoomId)
	local legacyRoomState = profile and profile.RoomState
	local roomState = primaryRoomState

	if normalizedRoomId == PRIMARY_ROOM_ID and shouldUseLegacyRoomState(primaryRoomState, legacyRoomState) then
		roomState = legacyRoomState
	end

	local layoutId = roomRecord and roomRecord.LayoutId

	if normalizedRoomId == PRIMARY_ROOM_ID and (typeof(layoutId) ~= "string" or layoutId == "") then
		layoutId = profile and profile.CurrentLayoutId
	end

	if normalizedRoomId == PRIMARY_ROOM_ID
		and (typeof(layoutId) ~= "string" or not isJoinableOwnedLayout(layoutId, player))
		and typeof(roomState) == "table"
		and typeof(roomState.LayoutId) == "string" then

		layoutId = roomState.LayoutId
	end

	return {
		RoomId = normalizedRoomId,
		RoomRecord = roomRecord,
		RoomState = roomState,
		LayoutId = layoutId,
	}
end

local function getPrimarySavedRoom(player, profile)
	local primaryRoomId = normalizeRoomId(RoomPersistence.GetPrimaryRoomId(player)) or PRIMARY_ROOM_ID
	local savedRoom = getSavedRoom(player, profile, primaryRoomId)

	if not savedRoom and primaryRoomId ~= PRIMARY_ROOM_ID then
		savedRoom = getSavedRoom(player, profile, PRIMARY_ROOM_ID)
	end

	return savedRoom
end

local function capturePlayerRoomState(player, roomModel)
	local roomState = RoomPersistence.CaptureRoomState(player, roomModel)

	if typeof(roomState) ~= "table" then
		return roomState
	end

	local roomId = normalizeRoomId(roomModel and roomModel:GetAttribute("RoomId"))
		or normalizeRoomId(player:GetAttribute("CurrentRoomId"))
		or PRIMARY_ROOM_ID

	if not RoomPersistence.GetRoomRecord(player, roomId) then
		warn("Could not save room state for", player.Name, "room not found:", roomId)
	end


	return roomState
end

local function enterSavedRoomForPlayer(player, profile)
	local savedRoom = getPrimarySavedRoom(player, profile)

	if not savedRoom then
		warn("Saved primary room record is missing for", player.Name)
		return false
	end

	local roomState = savedRoom.RoomState
	local layoutId = savedRoom.LayoutId

	if typeof(layoutId) ~= "string" or not isJoinableOwnedLayout(layoutId, player) then
		warn("Saved room has invalid layout:", layoutId)
		return false
	end

	local roomModel = cloneRoomForPlayer(player, layoutId, savedRoom.RoomId)

	if not roomModel then
		return false
	end

	RoomPersistence.ApplyRoomState(roomModel, roomState)
	applyPlayerRoomMetadataAttributes(
		roomModel,
		getRoomRecordMetadata(savedRoom.RoomRecord, player.DisplayName),
		player.UserId,
		layoutId
	)

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

	if not savedRoom then
		warn("Saved primary room record is missing for", player.Name)
		return false
	end

	local roomState = savedRoom.RoomState
	local layoutId = savedRoom.LayoutId

	if typeof(layoutId) ~= "string" or not isJoinableOwnedLayout(layoutId, player) then
		warn("Saved room has invalid layout:", layoutId)
		return false
	end

	local roomModel = cloneRoomForPlayer(player, layoutId, savedRoom.RoomId)

	if not roomModel then
		return false
	end

	RoomPersistence.ApplyRoomState(roomModel, roomState)
	applyPlayerRoomMetadataAttributes(
		roomModel,
		getRoomRecordMetadata(savedRoom.RoomRecord, player.DisplayName),
		player.UserId,
		layoutId
	)

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
	local parsedOwnerUserId, parsedRoomId = parsePlayerRoomName(roomName)

	if parsedOwnerUserId and parsedRoomId then
		local ownerPlayer = getPlayerByUserId(parsedOwnerUserId)
		local roomRecord = ownerPlayer and RoomPersistence.GetRoomRecord(ownerPlayer, parsedRoomId) or nil

		if DEBUG_ROOM_LIST_TRACE then
			warn(string.format(
				"Join validation parsed room name: player=%s roomName=%s owner=%s roomId=%s exists=%s",
				player.Name,
				tostring(roomName),
				tostring(parsedOwnerUserId),
				tostring(parsedRoomId),
				tostring(roomRecord ~= nil)
			))
		end

		if not roomRecord then
			joinRoomResult:FireClient(player, false, "Room not found.")
			return
		end
	end

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
	local roomId = normalizeRoomId(roomModel:GetAttribute("RoomId")) or PRIMARY_ROOM_ID
	local roomRecord = ownerPlayer and RoomPersistence.GetRoomRecord(ownerPlayer, roomId) or nil

	if DEBUG_ROOM_LIST_TRACE then
		warn(string.format(
			"Join validation by room name: player=%s roomName=%s owner=%s roomId=%s exists=%s",
			player.Name,
			tostring(roomName),
			tostring(ownerUserId),
			tostring(roomId),
			tostring(roomRecord ~= nil)
		))
	end

	if not roomRecord then
		joinRoomResult:FireClient(player, false, "Room not found.")
		return
	end

	local metadata = getRoomRecordMetadata(roomRecord, ownerDisplayName)

	if not metadata.IsPublic and not isOwner then
		joinRoomResult:FireClient(player, false, "Room is private.")
		return
	end

	applyPlayerRoomMetadataAttributes(
		roomModel,
		metadata,
		ownerUserId,
		roomModel:GetAttribute("LayoutId")
	)

	forceStandPlayer(player)

	player:SetAttribute("CurrentRoomName", roomModel.Name)
	player:SetAttribute("RoomMode", "Play")
	player:SetAttribute("ControlMode", "Hotel")
	setCurrentPlayerRoomContext(player, ownerUserId, roomId)
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

local function joinOwnedRoomById(player, roomId)
	local normalizedRoomId = normalizeRoomId(roomId)

	if not normalizedRoomId then
		joinRoomResult:FireClient(player, false, "Room not found.")
		return
	end

	local profile = RoomPersistence.GetProfile(player)
	local savedRoom = getSavedRoom(player, profile, normalizedRoomId)

	if DEBUG_ROOM_LIST_TRACE then
		warn(string.format(
			"Join validation own room: player=%s roomId=%s exists=%s",
			player.Name,
			tostring(normalizedRoomId),
			tostring(savedRoom ~= nil)
		))
	end

	if not savedRoom then
		joinRoomResult:FireClient(player, false, "Room not found.")
		return
	end

	local layoutId = savedRoom.LayoutId
	local isJoinable, joinDisabledReason = getOwnedLayoutJoinability(layoutId, player)

	if typeof(layoutId) ~= "string" or not isJoinable then
		joinRoomResult:FireClient(player, false, joinDisabledReason or ROOM_LAYOUT_TEMPLATE_NOT_READY_MESSAGE)
		return
	end

	local activeRoomName = getPlayerRoomName(player.UserId, normalizedRoomId)
	local activeRoom = activeRoomName and activeRooms:FindFirstChild(activeRoomName) or nil
	local currentOwnedRoom = playerRooms[player]

	if currentOwnedRoom and currentOwnedRoom.Parent and currentOwnedRoom.Name ~= activeRoomName then
		forceStandPlayer(player)
		capturePlayerRoomState(player, currentOwnedRoom)
		currentOwnedRoom:Destroy()
		playerRooms[player] = nil
	end

	if activeRoom and activeRoom:IsA("Model") then
		playerRooms[player] = activeRoom
		joinRoom(player, activeRoom.Name)
		return
	end

	local roomModel = cloneRoomForPlayer(player, layoutId, normalizedRoomId)

	if not roomModel then
		joinRoomResult:FireClient(player, false, ROOM_LAYOUT_TEMPLATE_NOT_READY_MESSAGE)
		return
	end

	RoomPersistence.ApplyRoomState(roomModel, savedRoom.RoomState)
	applyPlayerRoomMetadataAttributes(
		roomModel,
		getRoomRecordMetadata(savedRoom.RoomRecord, player.DisplayName),
		player.UserId,
		layoutId
	)

	joinRoom(player, roomModel.Name)
end

local function joinPlayerRoomById(player, ownerUserId, roomId)
	local normalizedRoomId = normalizeRoomId(roomId)
	local numericOwnerUserId = tonumber(ownerUserId)

	if not normalizedRoomId
		or not numericOwnerUserId
		or numericOwnerUserId ~= numericOwnerUserId
		or math.abs(numericOwnerUserId) >= math.huge
		or numericOwnerUserId ~= math.floor(numericOwnerUserId) then

		joinRoomResult:FireClient(player, false, "Room not found.")
		return
	end

	numericOwnerUserId = math.floor(numericOwnerUserId)

	if numericOwnerUserId == player.UserId then
		joinOwnedRoomById(player, normalizedRoomId)
		return
	end

	local ownerPlayer = getPlayerByUserId(numericOwnerUserId)
	local ownerRoomRecord = ownerPlayer and RoomPersistence.GetRoomRecord(ownerPlayer, normalizedRoomId) or nil

	if DEBUG_ROOM_LIST_TRACE then
		warn(string.format(
			"Join validation player room: player=%s owner=%s roomId=%s exists=%s",
			player.Name,
			tostring(numericOwnerUserId),
			tostring(normalizedRoomId),
			tostring(ownerRoomRecord ~= nil)
		))
	end

	if not ownerPlayer or not ownerRoomRecord then
		joinRoomResult:FireClient(player, false, "Room not found.")
		return
	end

	local activeRoomName = getPlayerRoomName(numericOwnerUserId, normalizedRoomId)

	if not activeRoomName then
		joinRoomResult:FireClient(player, false, "Room not found.")
		return
	end

	joinRoom(player, activeRoomName)
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
	local shouldDestroyEmptyOwnedRoom = typeof(ownerUserId) == "number"
		and ownerUserId == player.UserId
		and roomModel:GetAttribute("RoomType") ~= "PublicSpace"

	if shouldDestroyEmptyOwnedRoom then
		capturePlayerRoomState(player, roomModel)
		RoomPersistence.QueueSave(player)
	end

	enterMainMenuForPlayer(player, MAIN_MENU_INTRO_RETURNING)

	if shouldDestroyEmptyOwnedRoom then
		destroyOwnedRoomCloneIfEmpty(roomModel)
	end

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
		capturePlayerRoomState(player, ownedRoom)
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

	local roomModel = cloneRoomForPlayer(player, layoutId, PRIMARY_ROOM_ID)

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

	capturePlayerRoomState(player, roomModel)
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
		local requestId = typeof(payload) == "table" and tonumber(payload.RequestId) or nil
		local roomModel, furnitureModel, roomId, persistentId, validationMessage =
			validateFurnitureActionAccessTarget(player, payload)

		if validationMessage then
			sendFurnitureActionAccessResult(
				player,
				false,
				validationMessage,
				typeof(payload) == "table" and payload.Furniture or nil,
				nil,
				requestId,
				roomId,
				persistentId
			)
			return
		end

		sendFurnitureActionAccessResult(
			player,
			true,
			"Furniture action access loaded.",
			furnitureModel,
			buildFurnitureActionAccessSummary(player, roomModel, furnitureModel),
			requestId,
			roomId,
			persistentId
		)
		return
	end

	local _, _, persistentId, roomId, validationMessage = validateOpenClosePermissionTarget(player, payload)

	if validationMessage then
		sendFurniturePermissionResult(player, safeActionName, false, validationMessage, persistentId, nil, nil, nil, roomId)
		return
	end

	if safeActionName == "GetFurniturePermissions" then
		sendFurniturePermissionResult(
			player,
			safeActionName,
			true,
			"Furniture permissions loaded.",
			persistentId,
			buildFurniturePermissionEntries(player, roomId, persistentId, "OpenClose"),
			nil,
			nil,
			roomId
		)
		return
	end

	local targetUserInput = getPermissionTargetInput(payload)
	local targetUserId, targetUserMessage, resolvedInputName =
		resolveUserInputToUserId(player, targetUserInput)

	if not targetUserId then
		sendFurniturePermissionResult(
			player,
			safeActionName,
			false,
			targetUserMessage or "Invalid user.",
			persistentId,
			nil,
			nil,
			nil,
			roomId
		)
		return
	end

	if targetUserIsCurrentPlayer(player, targetUserId, targetUserInput, resolvedInputName) then
		sendFurniturePermissionResult(
			player,
			safeActionName,
			false,
			"You already have access as the room owner.",
			persistentId,
			buildFurniturePermissionEntries(player, roomId, persistentId, "OpenClose"),
			nil,
			nil,
			roomId
		)
		return
	end

	local success, message = RoomPersistence.SetFurniturePermissionForRoom(
		player,
		roomId,
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
		buildFurniturePermissionEntries(player, roomId, persistentId, "OpenClose"),
		success and targetUserId or nil,
		success and resolvedName or nil,
		roomId
	)
end)

roomSettingsRequest.OnServerEvent:Connect(function(player, actionName, payload)
	local safeActionName = typeof(actionName) == "string" and actionName or "Unknown"

	if (safeActionName == "UpdateSettings" or safeActionName == "ApplyRoomFloorStyle")
		and isRoomSettingsRequestRateLimited(player) then

		roomSettingsResult:FireClient(player, {
			Kind = safeActionName == "ApplyRoomFloorStyle" and "ApplyRoomFloorStyle" or "RoomSettings",
			Action = safeActionName,
			Success = false,
			Message = safeActionName == "ApplyRoomFloorStyle"
				and "Please wait a moment before updating floor style."
				or "Please wait a moment before updating room settings.",
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

	if safeActionName == "GetRoomFloorStyles" then
		local requestId = getRoomFloorStyleRequestId(payload)
		local silent = typeof(payload) == "table" and payload.Silent == true
		local ownerPlayer, roomId, _, _, targetMessage = getEditableFloorStyleTarget(player, payload)

		if not ownerPlayer then
			roomSettingsResult:FireClient(player, {
				Kind = "GetRoomFloorStyles",
				Action = "GetRoomFloorStyles",
				RequestId = requestId,
				Silent = silent,
				Success = false,
				Message = targetMessage or "Room styling is only available in your own rooms.",
				RoomId = roomId,
				Styles = {},
			})
			return
		end

		sendRoomFloorStylesResult(player, ownerPlayer, roomId, true, "Floor styles loaded.", requestId, silent)
		return
	end

	if safeActionName == "PreviewRoomFloorStyle" then
		local requestId = getRoomFloorStyleRequestId(payload)

		if typeof(payload) ~= "table" then
			roomSettingsResult:FireClient(player, {
				Kind = "PreviewRoomFloorStyle",
				Action = "PreviewRoomFloorStyle",
				RequestId = requestId,
				Success = false,
				Message = "Invalid floor style request.",
			})
			return
		end

		local ownerPlayer, roomId, _, activeRoomModel, targetMessage = getEditableFloorStyleTarget(player, payload)

		if not ownerPlayer or not activeRoomModel then
			roomSettingsResult:FireClient(player, {
				Kind = "PreviewRoomFloorStyle",
				Action = "PreviewRoomFloorStyle",
				RequestId = requestId,
				Success = false,
				Message = targetMessage or "Join the room before previewing floor styles.",
				RoomId = roomId,
			})
			return
		end

		local floorStyleId = typeof(payload.FloorStyleId) == "string" and trimRoomText(payload.FloorStyleId) or nil
		local canPreview, previewMessage = RoomFloorStyleConfig.CanPreviewStyle(floorStyleId)

		if not canPreview then
			roomSettingsResult:FireClient(player, {
				Kind = "PreviewRoomFloorStyle",
				Action = "PreviewRoomFloorStyle",
				RequestId = requestId,
				Success = false,
				Message = previewMessage or "Floor style not found.",
				RoomId = roomId,
				CurrentFloorStyleId = RoomPersistence.GetRoomFloorStyle(ownerPlayer, roomId),
			})
			return
		end

		local renderOk, applied, renderMessage = pcall(function()
			return RoomFloorStyleRenderer.ApplyFloorStyle(activeRoomModel, floorStyleId, {
				IsPreview = true,
			})
		end)
		local success = renderOk and applied == true

		roomSettingsResult:FireClient(player, {
			Kind = "PreviewRoomFloorStyle",
			Action = "PreviewRoomFloorStyle",
			RequestId = requestId,
			Success = success,
			Message = success and "Previewing floor. Apply to save." or (renderOk and renderMessage or tostring(applied)),
			RoomId = roomId,
			PreviewFloorStyleId = success and floorStyleId or nil,
			CurrentFloorStyleId = RoomPersistence.GetRoomFloorStyle(ownerPlayer, roomId),
			Styles = buildRoomFloorStyleEntries(ownerPlayer, RoomPersistence.GetRoomFloorStyle(ownerPlayer, roomId)),
		})
		return
	end

	if safeActionName == "CancelRoomFloorStylePreview" then
		local requestId = getRoomFloorStyleRequestId(payload)
		local silent = typeof(payload) == "table" and payload.Silent == true
		local ownerPlayer, roomId, _, activeRoomModel, targetMessage = getEditableFloorStyleTarget(player, payload)

		if not ownerPlayer or not activeRoomModel then
			roomSettingsResult:FireClient(player, {
				Kind = "CancelRoomFloorStylePreview",
				Action = "CancelRoomFloorStylePreview",
				RequestId = requestId,
				Silent = silent,
				Success = false,
				Message = targetMessage or "Join the room before reverting floor preview.",
				RoomId = roomId,
			})
			return
		end

		local currentFloorStyleId = RoomPersistence.GetRoomFloorStyle(ownerPlayer, roomId)
		local renderOk, applied, renderMessage = pcall(function()
			return RoomFloorStyleRenderer.ApplyFloorStyle(activeRoomModel, currentFloorStyleId)
		end)
		local success = renderOk and applied == true

		roomSettingsResult:FireClient(player, {
			Kind = "CancelRoomFloorStylePreview",
			Action = "CancelRoomFloorStylePreview",
			RequestId = requestId,
			Silent = silent,
			Success = success,
			Message = success and "Floor preview reverted." or (renderOk and renderMessage or tostring(applied)),
			RoomId = roomId,
			CurrentFloorStyleId = currentFloorStyleId,
			Styles = buildRoomFloorStyleEntries(ownerPlayer, currentFloorStyleId),
		})
		return
	end

	if safeActionName == "ApplyRoomFloorStyle" then
		local requestId = getRoomFloorStyleRequestId(payload)

		if typeof(payload) ~= "table" then
			roomSettingsResult:FireClient(player, {
				Kind = "ApplyRoomFloorStyle",
				Action = "ApplyRoomFloorStyle",
				RequestId = requestId,
				Success = false,
				Message = "Invalid floor style request.",
			})
			return
		end

		local ownerPlayer, roomId, _, activeRoomModel, targetMessage = getEditableFloorStyleTarget(player, payload)

		if not ownerPlayer then
			roomSettingsResult:FireClient(player, {
				Kind = "ApplyRoomFloorStyle",
				Action = "ApplyRoomFloorStyle",
				RequestId = requestId,
				Success = false,
				Message = targetMessage or "Room styling is only available in your own rooms.",
				RoomId = roomId,
			})
			return
		end

		local floorStyleId = typeof(payload.FloorStyleId) == "string" and trimRoomText(payload.FloorStyleId) or nil
		local styleConfig = floorStyleId and RoomFloorStyleConfig.GetStyle(floorStyleId) or nil

		if typeof(styleConfig) ~= "table" then
			roomSettingsResult:FireClient(player, {
				Kind = "ApplyRoomFloorStyle",
				Action = "ApplyRoomFloorStyle",
				RequestId = requestId,
				Success = false,
				Message = "Floor style not found.",
				RoomId = roomId,
				CurrentFloorStyleId = RoomPersistence.GetRoomFloorStyle(ownerPlayer, roomId),
			})
			return
		end

		local success, message, applyResult = RoomPersistence.ApplyRoomFloorStylePaid(ownerPlayer, roomId, floorStyleId)
		local currentFloorStyleId = RoomPersistence.GetRoomFloorStyle(ownerPlayer, roomId)

		if success and activeRoomModel then
			local renderOk, applied, renderMessage = pcall(function()
				return RoomFloorStyleRenderer.ApplyFloorStyle(activeRoomModel, floorStyleId)
			end)

			if not renderOk or not applied then
				success = false
				message = renderOk
					and (renderMessage or "Floor style saved, but the active room could not update.")
					or tostring(applied)
			end
		end

		roomSettingsResult:FireClient(player, {
			Kind = "ApplyRoomFloorStyle",
			Action = "ApplyRoomFloorStyle",
			RequestId = requestId,
			Success = success == true,
			Message = success and (message or "Floor updated.") or (message or "Could not update floor style."),
			RoomId = roomId,
			CurrentFloorStyleId = currentFloorStyleId,
			Style = buildRoomFloorStyleEntry(ownerPlayer, styleConfig, currentFloorStyleId),
			Styles = buildRoomFloorStyleEntries(ownerPlayer, currentFloorStyleId),
			Charged = typeof(applyResult) == "table" and applyResult.Charged == true,
			ChargedAmount = typeof(applyResult) == "table" and applyResult.ChargedAmount or nil,
			CurrencyKey = typeof(applyResult) == "table" and applyResult.CurrencyKey or nil,
			Price = typeof(applyResult) == "table" and applyResult.Price or nil,
			NewCurrencyBalance = typeof(applyResult) == "table" and applyResult.NewCurrencyBalance or nil,
		})
		return
	end

	if safeActionName == "GetRoomEditors" then
		local roomId = getSettingsPayloadRoomId(payload)

		if not roomId or not RoomPersistence.GetRoomRecord(player, roomId) then
			roomSettingsResult:FireClient(player, {
				Kind = "RoomSettings",
				Action = "GetRoomEditors",
				Success = false,
				Message = "Room not found.",
			})
			return
		end

		roomSettingsResult:FireClient(player, {
			Kind = "RoomSettings",
			Action = "GetRoomEditors",
			Success = true,
			Message = "Room editors loaded.",
			RoomId = roomId,
			Editors = buildRoomEditorsList(player, roomId),
		})
		return
	end

	if safeActionName == "AddRoomEditor" or safeActionName == "RemoveRoomEditor" then
		if typeof(payload) ~= "table" then
			roomSettingsResult:FireClient(player, {
				Kind = "RoomSettings",
				Action = safeActionName,
				Success = false,
				Message = "Invalid user.",
			})
			return
		end

		local roomId = getSettingsPayloadRoomId(payload)

		if not roomId or not RoomPersistence.GetRoomRecord(player, roomId) then
			roomSettingsResult:FireClient(player, {
				Kind = "RoomSettings",
				Action = safeActionName,
				Success = false,
				Message = "Room not found.",
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
		local success, message =
			RoomPersistence.SetRoomEditorPermissionForRoom(player, roomId, targetUserId, shouldAllow)
		local resolvedName = getResolvedUserName(targetUserId, resolvedInputName)

		if success and not shouldAllow then
			local removedPlayer = Players:GetPlayerByUserId(targetUserId)
			local roomModel = getActiveOwnedRoomModel(player, roomId)

			if removedPlayer
				and removedPlayer.UserId ~= player.UserId
				and roomModel
				and removedPlayer:GetAttribute("CurrentRoomName") == roomModel.Name
				and removedPlayer:GetAttribute("RoomMode") == "Edit" then

				removedPlayer:SetAttribute("RoomMode", "Play")
			end
		end

		sendRoomEditorsResult(
			player,
			safeActionName,
			roomId,
			success == true,
			success and (shouldAllow and "Editor added." or "Editor removed.")
				or (message or "Could not update room editors."),
			success and targetUserId or nil,
			success and resolvedName or nil
		)
		return
	end

	if safeActionName == "GetSettings" then
		local roomId = getSettingsPayloadRoomId(payload)

		if not roomId then
			roomSettingsResult:FireClient(player, {
				Kind = "RoomSettings",
				Action = "GetSettings",
				Success = false,
				Message = "Room not found.",
			})
			return
		end

		local settings = RoomPersistence.GetRoomSettingsForRoom(player, roomId)

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

		local roomId = getSettingsPayloadRoomId(payload)

		if not roomId then
			roomSettingsResult:FireClient(player, {
				Kind = "RoomSettings",
				Action = "UpdateSettings",
				Success = false,
				Message = "Room not found.",
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

		local success, message, settings = RoomPersistence.UpdateRoomSettingsForRoom(player, roomId, {
			DisplayName = filteredDisplayName,
			Category = payload.Category,
			Description = filteredDescription,
			IsPublic = payload.IsPublic,
		})

		if success then
			local roomModel = getActiveOwnedRoomModel(player, roomId)

			if roomModel and roomModel:IsA("Model") then
				applyPlayerRoomMetadataAttributes(
					roomModel,
					settings,
					player.UserId,
					roomModel:GetAttribute("LayoutId") or settings.LayoutId
				)
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

local function sendCreateOwnedRoomResult(player, success, message, roomRecord)
	roomNavigatorResult:FireClient(player, {
		Kind = "CreateOwnedRoom",
		Action = "CreateOwnedRoom",
		Success = success == true,
		Message = message or (success and "Room created." or "Could not create room."),
		Room = roomRecord,
		Rooms = RoomPersistence.GetOwnedRoomsSnapshot(player),
	})
end

local function sendDeleteOwnedRoomResult(player, success, message, roomId, result)
	local response = {
		Kind = "DeleteOwnedRoom",
		Action = "DeleteOwnedRoom",
		Success = success == true,
		Message = message or (success and "Room deleted." or "Could not delete room."),
		RoomId = roomId,
	}

	if typeof(result) == "table" then
		response.RoomId = result.RoomId or response.RoomId
		response.Rooms = result.Rooms
		response.ReturnedItems = result.ReturnedItems
		response.ReturnedCount = result.ReturnedCount
	end

	roomNavigatorResult:FireClient(player, response)
end

local function handleCreateOwnedRoomRequest(player, payload)
	if typeof(payload) ~= "table" then
		sendCreateOwnedRoomResult(player, false, "Invalid room options.")
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
			warnRoomTextRejected(player, "CreateOwnedRoomRaw", rawPolicyCategory, rawPolicyLength)
			sendCreateOwnedRoomResult(player, false, rawPolicyMessage)
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
		sendCreateOwnedRoomResult(player, false, displayNameMessage)
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
		sendCreateOwnedRoomResult(player, false, descriptionMessage)
		return
	end

	local filteredPolicyOk, filteredPolicyMessage, filteredPolicyCategory, filteredPolicyLength =
		validateRoomTextPolicy(filteredDisplayName, filteredDescription)

	if not filteredPolicyOk then
		warnRoomTextRejected(player, "CreateOwnedRoomFiltered", filteredPolicyCategory, filteredPolicyLength)
		sendCreateOwnedRoomResult(player, false, filteredPolicyMessage)
		return
	end

	local requestedLayout = RoomLayoutConfig.GetLayout(payload.LayoutId)
	local requestedLayoutNeedsDevAccess = typeof(requestedLayout) == "table"
		and (requestedLayout.IsDevOnly == true or requestedLayout.AccessTier == RoomLayoutConfig.ACCESS_DEV)

	if typeof(requestedLayout) == "table" then
		local canUseLayout, layoutMessage = RoomLayoutConfig.CanUseLayout(payload.LayoutId, getLayoutAccessContext(player))

		if not canUseLayout then
			sendCreateOwnedRoomResult(player, false, layoutMessage or ROOM_LAYOUT_TEMPLATE_NOT_READY_MESSAGE)
			return
		end

		if requestedLayout.RequiresVip == true or requestedLayoutNeedsDevAccess then
			local template, templateError = resolveOwnedRoomTemplate(payload.LayoutId, false, player)

			if not template then
				sendCreateOwnedRoomResult(player, false, templateError or ROOM_LAYOUT_TEMPLATE_NOT_READY_MESSAGE)
				return
			end
		end
	end

	local createOptions = {
		LayoutId = payload.LayoutId,
		DisplayName = filteredDisplayName,
		Category = payload.Category,
		Description = filteredDescription,
		IsPublic = payload.IsPublic,
		AllowVipTesting = canTestVipLayouts(player),
		CanUseDevLayouts = canUseDevLayouts(player),
	}
	local success = nil
	local message = nil
	local roomRecord = nil

	if requestedLayoutNeedsDevAccess then
		success, message, roomRecord = RoomLayoutConfig.WithDevLayoutAccess(function()
			return RoomPersistence.CreateOwnedRoom(player, createOptions)
		end)
	else
		success, message, roomRecord = RoomPersistence.CreateOwnedRoom(player, createOptions)
	end

	sendCreateOwnedRoomResult(player, success, message, roomRecord)

	if success then
		sendRoomListToPlayer(player)
	end
end

local function handleDeleteOwnedRoomRequest(player, payload)
	if typeof(payload) ~= "table" then
		sendDeleteOwnedRoomResult(player, false, "Invalid room options.", nil, nil)
		return
	end

	local roomId = typeof(payload.RoomId) == "string" and payload.RoomId or nil
	local success, message, result = RoomPersistence.DeleteOwnedRoom(player, roomId, {
		ConfirmDisplayName = payload.ConfirmDisplayName,
		RequireDisplayNameConfirmation = true,
	})

	sendDeleteOwnedRoomResult(player, success, message, roomId, result)

	if success then
		sendRoomListToPlayer(player)
	end
end

roomNavigatorRequest.OnServerEvent:Connect(function(player, actionName, payload)
	local safeActionName = typeof(actionName) == "string" and actionName or "Unknown"

	if safeActionName == "CreateOwnedRoom" then
		handleCreateOwnedRoomRequest(player, payload)
		return
	end

	if safeActionName == "DeleteOwnedRoom" then
		handleDeleteOwnedRoomRequest(player, payload)
		return
	end

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
	if DEBUG_ROOM_LIST_TRACE then
		if typeof(payload) == "table" then
			warn(string.format(
				"JoinRoom request from %s: type=%s owner=%s roomId=%s roomName=%s",
				player.Name,
				tostring(payload.RoomType),
				tostring(payload.OwnerUserId),
				tostring(payload.RoomId),
				tostring(payload.RoomName)
			))
		else
			warn(string.format(
				"JoinRoom request from %s: legacyPayload=%s",
				player.Name,
				tostring(payload)
			))
		end
	end

	if typeof(payload) == "table" then
		if payload.RoomType == "PublicSpace" then
			joinPublicRoom(player, payload.PublicRoomId)
		elseif payload.RoomType == "PlayerRoom" or payload.RoomId ~= nil or payload.OwnerUserId ~= nil then
			joinPlayerRoomById(player, payload.OwnerUserId or player.UserId, payload.RoomId or PRIMARY_ROOM_ID)
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
			capturePlayerRoomState(player, ownedRoom)
		end

		RoomPersistence.SavePlayer(player)
	end
end)
