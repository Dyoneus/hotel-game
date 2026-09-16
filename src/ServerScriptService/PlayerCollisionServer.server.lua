-- ServerScriptService/PlayerCollisionServer.lua
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local PLAYER_COLLISION_GROUP = "Players"

local characterAddedConnections = {}
local descendantAddedConnections = {}

pcall(function()
	PhysicsService:RegisterCollisionGroup(PLAYER_COLLISION_GROUP)
end)

PhysicsService:CollisionGroupSetCollidable(
	PLAYER_COLLISION_GROUP,
	PLAYER_COLLISION_GROUP,
	false
)

local function assignPlayerCollisionGroup(instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = PLAYER_COLLISION_GROUP
	end
end

local function clearCharacterConnection(player)
	local connection = descendantAddedConnections[player]

	if connection then
		connection:Disconnect()
		descendantAddedConnections[player] = nil
	end
end

local function setupCharacter(player, character)
	clearCharacterConnection(player)

	for _, descendant in ipairs(character:GetDescendants()) do
		assignPlayerCollisionGroup(descendant)
	end

	descendantAddedConnections[player] = character.DescendantAdded:Connect(
		assignPlayerCollisionGroup
	)
end

local function setupPlayer(player)
	characterAddedConnections[player] = player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)

	if player.Character then
		setupCharacter(player, player.Character)
	end
end

local function cleanupPlayer(player)
	clearCharacterConnection(player)

	local connection = characterAddedConnections[player]

	if connection then
		connection:Disconnect()
		characterAddedConnections[player] = nil
	end
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(cleanupPlayer)

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end
