local PublicRoomConfig = {}

-- Large public spaces should use explicit WorldPosition and FootprintRadius values
-- so they do not overlap player rooms or future public spaces in the same server.
local PUBLIC_ROOMS = {
	WelcomeLounge = {
		Id = "WelcomeLounge",
		PublicRoomId = "WelcomeLounge",
		DisplayName = "Welcome Lounge",
		ShortLabel = "Lounge",
		Category = "Social",
		TemplateName = "Public_WelcomeLounge",
		MaxOccupancy = 50,
		Description = "Meet other players, relax, and start your hotel adventure.",
		SortOrder = 1,
		IsOpen = true,
		Tags = { "Social", "New Players", "Featured" },
		Theme = "Lounge",
		LightingPreset = "WarmLounge",
		IconImageId = "",
		ThumbnailImageId = "",
		WorldPosition = Vector3.new(100000, 0, 0),
		FootprintRadius = 4000,
	},

	GameHall = {
		Id = "GameHall",
		PublicRoomId = "GameHall",
		DisplayName = "Game Hall",
		ShortLabel = "Games",
		Category = "Games",
		TemplateName = "Public_GameHall",
		MaxOccupancy = 40,
		Description = "Find mini-games, activities, and future competitions.",
		SortOrder = 2,
		IsOpen = true,
		Tags = { "Games", "Activities" },
		Theme = "Games",
		LightingPreset = "Arcade",
		IconImageId = "",
		ThumbnailImageId = "",
		WorldPosition = Vector3.new(110000, 0, 0),
		FootprintRadius = 4000,
	},

	Cafe = {
		Id = "Cafe",
		PublicRoomId = "Cafe",
		DisplayName = "Cafe",
		ShortLabel = "Cafe",
		Category = "Food",
		TemplateName = "Public_Cafe",
		MaxOccupancy = 30,
		Description = "Hang out with friends in a cozy cafe space.",
		SortOrder = 3,
		IsOpen = true,
		Tags = { "Cafe", "Social" },
		Theme = "Cafe",
		LightingPreset = "CozyCafe",
		IconImageId = "",
		ThumbnailImageId = "",
		WorldPosition = Vector3.new(120000, 0, 0),
		FootprintRadius = 4000,
	},
}

local CATEGORIES = {
	"Social",
	"Games",
	"Food",
	"Entertainment",
	"Outside Spaces",
	"Restaurants",
	"Dance Clubs",
	"Trading",
	"Help",
}

PublicRoomConfig.PublicRooms = PUBLIC_ROOMS
PublicRoomConfig.Categories = CATEGORIES

local function copyStringArray(values)
	local copy = {}

	if typeof(values) ~= "table" then
		return copy
	end

	for _, value in ipairs(values) do
		if typeof(value) == "string" and value ~= "" and value:match("%S") ~= nil then
			table.insert(copy, value)
		end
	end

	return copy
end

local function copyPublicRoom(room)
	local publicRoomId = room.PublicRoomId or room.Id

	return {
		Id = publicRoomId,
		PublicRoomId = publicRoomId,
		DisplayName = room.DisplayName,
		ShortLabel = room.ShortLabel,
		Category = room.Category,
		TemplateName = room.TemplateName,
		MaxOccupancy = room.MaxOccupancy,
		Description = room.Description,
		SortOrder = room.SortOrder,
		IsOpen = room.IsOpen ~= false,
		Tags = copyStringArray(room.Tags),
		Theme = room.Theme,
		LightingPreset = room.LightingPreset,
		AmbiencePreset = room.AmbiencePreset,
		IconImageId = room.IconImageId,
		ThumbnailImageId = room.ThumbnailImageId,
		WorldPosition = room.WorldPosition,
		FootprintRadius = room.FootprintRadius,
	}
end

local function findPublicRoom(publicRoomId)
	if typeof(publicRoomId) ~= "string" or publicRoomId == "" then
		return nil
	end

	local directRoom = PUBLIC_ROOMS[publicRoomId]

	if directRoom then
		return directRoom
	end

	for _, room in pairs(PUBLIC_ROOMS) do
		if room.PublicRoomId == publicRoomId or room.Id == publicRoomId then
			return room
		end
	end

	return nil
end

function PublicRoomConfig.GetPublicRoom(publicRoomId)
	local room = findPublicRoom(publicRoomId)

	if not room then
		return nil
	end

	return copyPublicRoom(room)
end

function PublicRoomConfig.GetAllPublicRooms()
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

function PublicRoomConfig.GetPublicRoomsArray()
	return PublicRoomConfig.GetAllPublicRooms()
end

function PublicRoomConfig.GetOpenPublicRooms()
	local rooms = {}

	for _, room in ipairs(PublicRoomConfig.GetAllPublicRooms()) do
		if room.IsOpen ~= false then
			table.insert(rooms, room)
		end
	end

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
