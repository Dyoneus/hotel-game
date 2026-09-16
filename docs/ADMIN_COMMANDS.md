# Admin And Debug Commands

This reference lists admin, debug, and Studio helper commands that currently
exist in the repo. It is documentation only. Do not treat examples here as new
runtime APIs.

## A. How To Run Commands

Use the right command context:

- Studio Edit Mode Command Bar: use for most `docs/tools/*.lua` helper scripts.
  Open the helper file, copy the full contents, and paste it into Studio's
  Command Bar. Play does not need to be running unless the helper says it needs
  an active room or player.
- Server Command Bar: use while Play is running when a snippet requires
  `game.ServerScriptService` or mutates profile data through `RoomPersistence`.
- Client Command Bar: use while Play is running only for client-side RemoteEvent
  smoke tests. Client Command Bar cannot access `ServerScriptService`.
- In-game chat or Admin Panel: admin chat commands are handled by
  `AdminCommandServer.server.lua`. Studio currently has server-side admin
  override enabled; live servers use `AdminConfig`.

Do not run server snippets in Client Command Bar. They will fail or silently
test the wrong context.

Safety warnings:

- Some commands mutate profile data and queue or perform saves.
- Some commands delete data, reset profiles, kick players, or ban accounts.
- Use Studio and test accounts first.
- Export or duplicate Studio-generated models before deleting or replacing
  generated instances.
- Do not use normal inventory helpers for room floor styles. Floors are room
  finishes, not furniture inventory items, and they are not marketplace items.
  Paid floors charge when applied from Room Settings.

## B. Room Layout Tools

Run these by pasting the full file contents into Studio Edit Mode Command Bar,
or from a temporary Script in Studio. The generators create or replace Studio
instances under `ReplicatedStorage`; validators do not modify instances.

| Helper | Preconditions | Expected output |
| --- | --- | --- |
| `docs/tools/CreateRoomLayout_Free_036_A.lua` | Rojo-synced game open in Studio. | Creates `ReplicatedStorage.RoomTemplates.RoomLayout_Free_036_A`; prints `[CreateRoomLayout_Free_036_A] Created ...` and marker positions. |
| `docs/tools/CreateRoomLayout_Free_080_A.lua` | Studio edit mode. | Creates `RoomLayout_Free_080_A`; prints grid, floor style, and next validation step. |
| `docs/tools/CreateRoomLayout_Free_080_B.lua` | Studio edit mode. | Creates `RoomLayout_Free_080_B`; prints grid, floor style, and next validation step. |
| `docs/tools/CreateRoomLayout_Free_084_A.lua` | Studio edit mode. | Creates `RoomLayout_Free_084_A`; prints grid, floor style, and next validation step. |
| `docs/tools/CreateRoomLayout_Free_104_A.lua` | Studio edit mode. | Creates `RoomLayout_Free_104_A`; prints grid, floor style, and next validation step. |
| `docs/tools/CreateRoomLayout_Free_320_A.lua` | Studio edit mode. | Creates `RoomLayout_Free_320_A`; prints grid, floor style, and next validation step. |
| `docs/tools/CreateRoomLayout_Free_352_A.lua` | Studio edit mode. | Creates `RoomLayout_Free_352_A`; prints grid, floor style, and next validation step. |
| `docs/tools/CreateRoomLayout_Free_384_A.lua` | Studio edit mode. | Creates `RoomLayout_Free_384_A`; prints grid, floor style, and next validation step. |
| `docs/tools/CreateRoomLayout_Free_416_A.lua` | Studio edit mode. | Creates `RoomLayout_Free_416_A`; prints grid, floor style, and next validation step. |
| `docs/tools/CreateRoomLayout_VIP_080_A.lua` | Studio edit mode. | Creates `RoomLayout_VIP_080_A`; prints VIP metadata and marker positions. |
| `docs/tools/CreateRoomLayout_VIP_208_A.lua` | Studio edit mode. | Creates `RoomLayout_VIP_208_A`; prints VIP metadata and marker positions. |
| `docs/tools/CreateRoomLayout_VIP_304_A.lua` | Studio edit mode. | Creates `RoomLayout_VIP_304_A`; prints VIP metadata and marker positions. |
| `docs/tools/CreateRoomLayout_MaskTest_Hole_036.lua` | Studio edit mode. Dev/test only. | Creates `RoomLayout_MaskTest_Hole_036`; prints TileMask and hole metadata. |
| `docs/tools/ValidateRoomLayoutTemplates.lua` | Studio edit mode after any layout generation. | Prints `[RoomLayoutTemplateValidator] Summary...`; missing future templates are warn-only. |
| `docs/tools/CreateRoomGridOverlay.lua` | Select one or more room template Models, or edit `ROOM_TEMPLATE_PATHS` in the file. | Creates or replaces `EditorHelpers.RoomGridOverlay`; prints `[RoomGridOverlay] ... Grid=...`. |

Example, Studio Edit Mode Command Bar:

```lua
-- Paste/run docs/tools/CreateRoomLayout_Free_036_A.lua
```

Then:

```lua
-- Paste/run docs/tools/ValidateRoomLayoutTemplates.lua
```

Public room and scene helpers also exist:

| Helper | Preconditions | Expected output |
| --- | --- | --- |
| `docs/tools/CreateWelcomeLoungeTemplate.lua` | Studio edit mode. | Creates `ReplicatedStorage.PublicRoomTemplates.Public_WelcomeLounge` or configured template name; prints next validation step. |
| `docs/tools/CreateCafeTemplate.lua` | Studio edit mode. | Creates `Public_Cafe` or configured template name; prints grid and next validation step. |
| `docs/tools/CreateGameHallTemplate.lua` | Studio edit mode. | Creates `Public_GameHall` or configured template name; prints grid and next validation step. |
| `docs/tools/ValidatePublicRoomTemplates.lua` | Studio edit mode. | Prints `[PublicRoomTemplateValidator] Summary: total=... ok=... warn=... error=...`. |
| `docs/tools/CreateMainMenuHotelLobbyScene.lua` | Studio edit mode. | Creates `ReplicatedStorage.MainMenuScenes.HotelLobbyMainMenu`; prints camera marker names and positions. |

## C. Furniture Tools

Run these from Studio Edit Mode Command Bar unless noted.

### Prepare Imported Furniture

Where: Studio Edit Mode Command Bar.

Preconditions: Select exactly one furniture `Model`. The helper expects imported
templates to live under `ReplicatedStorage.FurnitureTemplates`.

```lua
-- Paste/run docs/tools/PrepareImportedFurnitureTemplate.lua
```

Expected output: `[PrepareImportedFurnitureTemplate] Prepared model: ...`,
attribute summary, `PlacementBounds` status, embedded script count, and
`Next: run docs/tools/ValidateFurnitureTemplates.lua in Studio.`

### Validate Furniture Templates

Where: Studio Edit Mode Command Bar.

Preconditions: `ReplicatedStorage.FurnitureTemplates` exists.

```lua
-- Paste/run docs/tools/ValidateFurnitureTemplates.lua
```

Expected output: `[ValidateFurnitureTemplates] Summary`, template counts, warning
count, error count, and `RESULT: PASS`, `RESULT: WARN`, or `RESULT: FAIL`.

### Create Open/Close Test Gate

Where: Studio Edit Mode Command Bar.

Preconditions: Studio edit mode. This is temporary development furniture.

```lua
-- Paste/run docs/tools/CreateGateTestOpenCloseTemplate.lua
```

Expected output: creates
`ReplicatedStorage.FurnitureTemplates.Gate_Test_OpenClose` and prints that it is
temporary test furniture for room-specific OpenClose permissions. It is
intentionally not added to the normal furniture catalog.

## D. Floor Style Tools

Current floor model:

- `Grid` is the default free floor for every new or migrated room.
- `Plain` is also free/starter when `RoomFloorStyleConfig` keeps it configured
  that way.
- Paid styles such as `Carpet`, `Wood`, `Checker`, `Pebble`, and `Stripe`
  charge each time they are applied to a room.
- Preview is free and does not save. The Room Settings client reverts previews
  on close or when switching away from the Floor tab unless the style is applied.
- Floor styles are room finishes. They are not normal furniture inventory items
  and are not marketplace listings.
- `RoomDecorInventory.Floors` may still exist on older test profiles, but it no
  longer controls which floor styles can be used.

### Preview A Runtime Floor Style

Where: Studio Command Bar or temporary Script.

Preconditions: For active-room preview, Play must be running and a room should be
loaded under `workspace.ActiveRooms`. Select the active room Model or any
descendant, or let the helper use the first active room. Edit `FLOOR_STYLE_ID`
and `CLEAR_ONLY` at the top of the file before running.

```lua
-- Paste/run docs/tools/PreviewRoomFloorStyle.lua
```

Expected output: `[PreviewRoomFloorStyle] <room path> <message>`. This applies a
visual preview through `RoomFloorStyleRenderer` and does not save profile data.

### Debug Floor Style Persistence

Where: Server Command Bar while Play is running.

Preconditions: A player is in-game. Edit `PLAYER_NAME`, `ROOM_ID`,
`TEST_STYLE_ID`, `SET_STYLE`, and `APPLY_TO_ACTIVE_ROOM` at the top of the file
if needed. Do not run this from Client Command Bar.

```lua
-- Paste/run docs/tools/DebugRoomFloorStylePersistence.lua
```

Expected output: `[DebugRoomFloorStylePersistence]` lines showing player, API
availability, current room style, set result, and optional visual apply result.
If `SET_STYLE = true`, this mutates room style persistence. Use it for free
styles such as `Grid` or `Plain`; paid floor application should be tested
through Room Settings so the currency charge path is exercised.

### Catalog Room Finishes Info Page

Where: in-game Catalog while Play is running.

Preconditions: Open Catalog, then go to `Room Finishes` > `Floors`.

Expected output: floor styles show as browse/info cards with prices for paid
styles. There should be no Buy button, no Owned badge, no Place button, no Sell
button, and no marketplace listing button. Preview and apply floors from
`Room Settings` > `Floor`.

## E. Room Persistence And Debug Examples

All examples in this section run in Server Command Bar while Play is running.

### Load Or Inspect The Current Player Profile

Preconditions: At least one player is in-game.

```lua
local RP = require(game.ServerScriptService.RoomPersistence)
local player = game.Players:GetPlayers()[1]

local profile, loaded = RP.LoadProfile(player)
print("loaded", loaded, "hasProfile", profile ~= nil)
print("cached", RP.GetProfile(player) ~= nil)
```

Expected output: `loaded true hasProfile true` and `cached true`. In Studio,
`LoadProfile` may use a fallback profile if DataStore access is unavailable.

### Inspect Room Style

Preconditions: The player profile is loaded and the room exists.

```lua
local RP = require(game.ServerScriptService.RoomPersistence)
local player = game.Players:GetPlayers()[1]

local style, message = RP.GetRoomStyleForRoom(player, "Primary")
print(message, style and style.FloorStyleId)
print("floor", RP.GetRoomFloorStyle(player, "Primary"))
```

Expected output: `Room style loaded. Grid` for a default room, or the persisted
floor style id.

### Inspect Legacy Decor Inventory Compatibility

Preconditions: Play is running. This is a compatibility check only.
`RoomDecorInventory.Floors` no longer controls floor access.

```lua
local RP = require(game.ServerScriptService.RoomPersistence)
local player = game.Players:GetPlayers()[1]

print(RP.GetRoomDecorInventorySnapshot(player))
print("owned floor styles", RP.GetOwnedFloorStyles(player))
print("owns Wood", RP.PlayerOwnsFloorStyle(player, "Wood"))
```

Expected output: a snapshot table may include `Floors` for older test profiles,
but floor access ignores it. `GetOwnedFloorStyles` should not be used for the
current pay-per-apply model, and `PlayerOwnsFloorStyle` is legacy compatibility.

### Legacy GrantFloorStyle Compatibility

Do not use this as the normal workflow. Permanent floor unlocks are disabled.

Where: Server Command Bar while Play is running.

```lua
local RP = require(game.ServerScriptService.RoomPersistence)
local player = game.Players:GetPlayers()[1]

local ok, message, entry = RP.GrantFloorStyle(player, "Wood", {
	Source = "Debug",
	SaveNow = true,
})

print(ok, message, entry)
```

Expected output: a compatibility rejection such as
`false Permanent floor style unlocks are no longer supported. nil`. Use
`Room Settings` > `Floor` to preview and apply paid floors.

### Apply Or Reset A Free Persisted Floor Style

Preconditions: The player profile is loaded and the room exists. Direct
persistence set is for free styles such as `Grid` and `Plain`. It may not repaint
an already loaded active room unless the renderer is also called.

```lua
local RP = require(game.ServerScriptService.RoomPersistence)
local player = game.Players:GetPlayers()[1]

print(RP.SetRoomFloorStyleForRoom(player, "Primary", "Grid"))
print(RP.SetRoomFloorStyleForRoom(player, "Primary", "Plain"))
print(RP.SetRoomFloorStyleForRoom(player, "Primary", "Wood"))
```

Expected output: `Grid` and `Plain` succeed when configured as free/starter
styles. `Wood` should reject with a message such as
`Paid floor styles must be applied from Room Settings.` Paid apply needs the
Room Settings server action so currency is charged and rollback is handled.

### Preview A Floor Visually

Where: Server Command Bar while Play is running.

Preconditions: The player has joined an owned room and
`workspace.ActiveRooms` contains their active room model.

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local RoomFloorStyleRenderer = require(sharedFolder:WaitForChild("RoomFloorStyleRenderer"))

local player = game.Players:GetPlayers()[1]
local activeRooms = workspace:FindFirstChild("ActiveRooms")
local currentRoomName = player and player:GetAttribute("CurrentRoomName")
local activeRoom = activeRooms and currentRoomName and activeRooms:FindFirstChild(currentRoomName)

if not activeRoom then
	warn("No active room found.")
else
	print(RoomFloorStyleRenderer.ApplyFloorStyle(activeRoom, "Wood", {
		IsStudioPreview = true,
	}))
end
```

Expected output: `true <message>` and the active room visually changes to Wood.
This is preview-only. It does not save, does not charge Dollars, and does not
create inventory.

### Revert Preview To The Saved Floor

Where: Server Command Bar while Play is running.

Preconditions: The player is still in the active room that was previewed.

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RP = require(game.ServerScriptService.RoomPersistence)
local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local RoomFloorStyleRenderer = require(sharedFolder:WaitForChild("RoomFloorStyleRenderer"))

local player = game.Players:GetPlayers()[1]
local roomId = "Primary"
local style = RP.GetRoomStyleForRoom(player, roomId)
local savedFloorStyleId = style and style.FloorStyleId or "Grid"

local activeRooms = workspace:FindFirstChild("ActiveRooms")
local currentRoomName = player and player:GetAttribute("CurrentRoomName")
local activeRoom = activeRooms and currentRoomName and activeRooms:FindFirstChild(currentRoomName)

if not activeRoom then
	warn("No active room found.")
else
	print(RoomFloorStyleRenderer.ApplyFloorStyle(activeRoom, savedFloorStyleId))
end
```

Expected output: `true <message>` and the active room returns to the saved floor,
usually `Grid` for a new room.

### Test Paid Apply Through Room Settings

Where: in-game UI while Play is running.

Preconditions: Join an owned room. Give yourself Dollars first if needed, for
example with `/givedollars <yourName> 500`.

Workflow:

```text
Room Settings > Floor > Wood > Preview
Room Settings > Floor > Wood > Apply - 100 Dollars
```

Expected output: preview changes the room without charging. Apply subtracts
Dollars, saves `Rooms[roomId].Style.FloorStyleId = "Wood"`, repaints the active
room, and shows the floor as current. Applying Wood again while it is already
current should not charge again.

### Legacy PurchaseFloorStyle Compatibility

Do not use this as the normal workflow. Catalog floor purchases no longer unlock
floor access.

Where: Server Command Bar while Play is running.

```lua
local RP = require(game.ServerScriptService.RoomPersistence)
local player = game.Players:GetPlayers()[1]

local ok, message, result = RP.PurchaseFloorStyle(player, "Wood")
print(ok, message)
print(result and result.FloorStyleId, result and result.Owned)
```

Expected output: a compatibility rejection such as
`false Preview and apply floors from Room Settings.` It should not subtract
currency, unlock the floor, save an ownership record, or create inventory.

### Delete A Non-Primary Owned Room For Debugging

Risky: this deletes room data and saves immediately. It cannot delete `Primary`.

Preconditions: Play is running and `roomId` is a non-primary owned room id.

```lua
local RP = require(game.ServerScriptService.RoomPersistence)
local player = game.Players:GetPlayers()[1]

local ok, message, rooms, saved = RP.DeleteOwnedRoomForDebug(player, "Room_Example")
print(ok, message, saved)
print(rooms)
```

Expected output: `true Room deleted. true`, or a rejection such as
`Primary room cannot be deleted.` or `Room not found.`

## F. Inventory, Currency, And Admin Commands

### In-Game Admin Chat Commands

Where: in-game chat, Admin Panel command box, or Client Command Bar via
`AdminCommandRequest`.

Preconditions: Play is running. In Studio, admin override is enabled by
`AdminCommandServer.server.lua`. In live servers, the actor must be configured in
`AdminConfig`. Target player must be online and have a loaded profile.

Available chat commands:

```text
/giveitem playerName itemId quantity tradable|untradable sellable|unsellable
/itemdetails playerName itemId
/setitem playerName itemId total untradable unsellable
/givecoins playerName amount
/givedollars playerName amount
```

Examples:

```text
/givedollars OJY2000 500
/givecoins OJY2000 100
/giveitem OJY2000 Chair_Hotel_001 1 untradable unsellable
/itemdetails OJY2000 Chair_Hotel_001
/setitem OJY2000 Chair_Hotel_001 3 1 0
```

Expected output: admin command result messages such as `Gave OJY2000 500
Dollars. New balance: ...`, plus inventory or currency refresh events for the
target player.

Client Command Bar remote example:

```lua
local events = game.ReplicatedStorage:WaitForChild("RemoteEvents")
local result = events:WaitForChild("AdminCommandResult")
local request = events:WaitForChild("AdminCommandRequest")

local conn
conn = result.OnClientEvent:Connect(function(payload)
	print(payload.Command, payload.Success, payload.Message)
	conn:Disconnect()
end)

request:FireServer("RunCommand", {
	CommandText = "/givedollars " .. game.Players.LocalPlayer.Name .. " 500",
})
```

Expected output: `givedollars true Gave <name> 500 Dollars. New balance: ...`.

### Direct Currency Helpers

Where: Server Command Bar while Play is running.

Preconditions: Profile is loaded. These mutate profile currency and queue saves.

```lua
local RP = require(game.ServerScriptService.RoomPersistence)
local player = game.Players:GetPlayers()[1]

print(RP.AddDollars(player, 500, "Debug"))
print(RP.AddCoins(player, 100, "Debug"))
print(RP.SetDollars(player, 1000, "Debug"))
print(RP.GetCurrenciesSnapshot(player))
```

Expected output: `true Currency added. <balance>`,
`true Currency set. 1000`, and a currency snapshot table.

### Direct Inventory Helpers

Where: Server Command Bar while Play is running.

Preconditions: Profile is loaded. These mutate normal furniture inventory and
queue saves. Do not use these for floor styles.

```lua
local RP = require(game.ServerScriptService.RoomPersistence)
local player = game.Players:GetPlayers()[1]

print(RP.AddInventoryItem(player, "Chair_Hotel_001", 1, {
	Tradable = false,
	Sellable = false,
}))

print(RP.GetInventoryDetailsSnapshot(player))
```

Expected output: `true Inventory item added. <newCount> <details>` and an
inventory details table.

### Profile Reset, Ban, And Unban

Risky: these are moderation/data-destruction helpers. Use test accounts first.

Where: Admin Panel, admin remotes, or Server Command Bar through
`AdminDataTools`.

Server Command Bar examples:

```lua
local AdminDataTools = require(game.ServerScriptService.AdminDataTools)

print(AdminDataTools.ResetProfileByUserId(123456789, 0))
print(AdminDataTools.UnbanByUserId(123456789, 0))
```

Expected output: `true Profile reset complete.` or `true Unban complete.`.
`ResetProfileByUserId` deletes saved profile data and kicks an online target.

Ban example, only for real moderation testing:

```lua
local AdminDataTools = require(game.ServerScriptService.AdminDataTools)
print(AdminDataTools.ExploitBanByUserId(123456789, 0, "Exploit test reason"))
```

Expected output: `true Ban and profile deletion complete.` or an error from
Roblox ban/profile APIs. This permanently bans through `Players:BanAsync` with
`Duration = -1`.

Admin remote action names also exist for `GetAccess`, `LookupUser`,
`ResetProfile`, `ExploitBan`, and `Unban`. Destructive remote actions require
confirmation strings: `RESET`, `BAN`, or `UNBAN`.

## G. Common Workflows

### Generate A Room Template

Where: Studio Edit Mode Command Bar.

Preconditions: Rojo sync complete.

```lua
-- Paste/run one generator, for example:
-- docs/tools/CreateRoomLayout_Free_036_A.lua

-- Then paste/run:
-- docs/tools/ValidateRoomLayoutTemplates.lua
```

Expected output: generator prints `Created ...`; validator prints a summary.
Missing future templates can warn until those templates exist.

### Validate Room Templates Only

Where: Studio Edit Mode Command Bar.

```lua
-- Paste/run docs/tools/ValidateRoomLayoutTemplates.lua
```

Expected output: `[RoomLayoutTemplateValidator] Summary: ...`.

### Prepare Imported Furniture

Where: Studio Edit Mode Command Bar.

Preconditions: Select exactly one imported furniture `Model`.

```lua
-- Paste/run docs/tools/PrepareImportedFurnitureTemplate.lua
-- Then paste/run docs/tools/ValidateFurnitureTemplates.lua
```

Expected output: prepare summary, then furniture validation result.

### Validate Furniture Only

Where: Studio Edit Mode Command Bar.

```lua
-- Paste/run docs/tools/ValidateFurnitureTemplates.lua
```

Expected output: `[ValidateFurnitureTemplates] RESULT: PASS`, `WARN`, or `FAIL`.

### Test Floor Style Persistence

Where: Server Command Bar while Play is running.

Preconditions: Join an owned room first.

```lua
-- Paste/run docs/tools/DebugRoomFloorStylePersistence.lua
```

Expected output: current style, set result, and optional renderer apply result.
Use free styles for direct persistence tests. Test paid floors through Room
Settings so the apply charge path runs.

### Reset Or Apply A Free Floor Style

Where: Server Command Bar while Play is running.

```lua
local RP = require(game.ServerScriptService.RoomPersistence)
local player = game.Players:GetPlayers()[1]

print(RP.SetRoomFloorStyleForRoom(player, "Primary", "Grid"))
print(RP.SetRoomFloorStyleForRoom(player, "Primary", "Plain"))
```

Expected output: free styles succeed and persist to
`Rooms.Primary.Style.FloorStyleId`. Direct persistence set may not repaint the
active room unless the renderer is called. Paid floors should be previewed and
applied from `Room Settings` > `Floor`.

### Preview And Apply A Paid Floor

Where: in-game UI while Play is running.

Preconditions: Join an owned room and make sure the player has enough Dollars.

```text
Room Settings > Floor > Wood > Preview
Room Settings > Floor > Wood > Apply - 100 Dollars
```

Expected output: preview is free and reversible. Apply charges Dollars each time
the room changes to a paid style, saves the room floor, and does not create any
inventory or marketplace item.

### Give Yourself Test Furniture

Where: in-game chat, Admin Panel command box, or Client Command Bar remote.

Preconditions: Play running, admin access or Studio override.

```text
/giveitem OJY2000 Chair_Hotel_001 1 untradable unsellable
```

Expected output: admin success message and updated inventory. This creates a
normal furniture inventory item. Do not use it for room floor styles.
