local PublicRoomConfig = {}

-- Large public spaces should use explicit WorldPosition and FootprintRadius values
-- so they do not overlap player rooms or future public spaces in the same server.
local PUBLIC_ROOMS = {
	WelcomeLounge = {
		Id = "WelcomeLounge",
		DisplayName = "Welcome Lounge",
		Category = "Welcome Lounge",
		TemplateName = "Public_WelcomeLounge",
		MaxOccupancy = 50,
		Description = "Meet other players in the hotel lobby.",
		SortOrder = 1,
		WorldPosition = Vector3.new(100000, 0, 0),
		FootprintRadius = 4000,
	},

	GameHall = {
		Id = "GameHall",
		DisplayName = "Game Hall",
		Category = "Gamehall",
		TemplateName = "Public_GameHall",
		MaxOccupancy = 40,
		Description = "Find games, races, and hotel activities.",
		SortOrder = 2,
		WorldPosition = Vector3.new(110000, 0, 0),
		FootprintRadius = 4000,
	},

	Cafe = {
		Id = "Cafe",
		DisplayName = "Cafe",
		Category = "Cafes",
		TemplateName = "Public_Cafe",
		MaxOccupancy = 30,
		Description = "Hang out with friends over a quick drink.",
		SortOrder = 3,
		WorldPosition = Vector3.new(120000, 0, 0),
		FootprintRadius = 4000,
	},
}

local CATEGORIES = {
	"Welcome Lounge",
	"Entertainment",
	"Outside Spaces",
	"Gamehall",
	"Cafes",
	"Restaurants",
	"Dance Clubs",
}

PublicRoomConfig.PublicRooms = PUBLIC_ROOMS
PublicRoomConfig.Categories = CATEGORIES

local function copyPublicRoom(room)
	return {
		Id = room.Id,
		DisplayName = room.DisplayName,
		Category = room.Category,
		TemplateName = room.TemplateName,
		MaxOccupancy = room.MaxOccupancy,
		Description = room.Description,
		SortOrder = room.SortOrder,
		WorldPosition = room.WorldPosition,
		FootprintRadius = room.FootprintRadius,
	}
end

function PublicRoomConfig.GetPublicRoom(publicRoomId)
	local room = PUBLIC_ROOMS[publicRoomId]

	if not room then
		return nil
	end

	return copyPublicRoom(room)
end

function PublicRoomConfig.GetPublicRoomsArray()
	local rooms = {}

	for _, room in pairs(PUBLIC_ROOMS) do
		table.insert(rooms, copyPublicRoom(room))
	end

	table.sort(rooms, function(a, b)
		local aOrder = typeof(a.SortOrder) == "number" and a.SortOrder or math.huge
		local bOrder = typeof(b.SortOrder) == "number" and b.SortOrder or math.huge

		if aOrder == bOrder then
			return tostring(a.DisplayName or a.Id) < tostring(b.DisplayName or b.Id)
		end

		return aOrder < bOrder
	end)

	return rooms
end

function PublicRoomConfig.GetPublicCategories()
	local categories = {}

	for _, categoryName in ipairs(CATEGORIES) do
		table.insert(categories, categoryName)
	end

	return categories
end

return PublicRoomConfig
