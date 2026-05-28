# Public Room Template Setup

Public rooms are developer-made hotel spaces. They are joined through the Room Navigator, cloned by `PlayerRoomServer`, and marked with `RoomType = "PublicSpace"` at runtime. Normal players should not edit these rooms, and public room state is not saved to player profiles.

## Template Location

Put public room templates in:

```text
ReplicatedStorage
  PublicRoomTemplates
    Public_WelcomeLounge
    Public_GameHall
    Public_Cafe
```

`PlayerRoomServer` currently checks `ReplicatedStorage.PublicRoomTemplates` first.

If a template is not found there, it falls back to:

```text
ReplicatedStorage.RoomTemplates
```

`default.project.json` does not currently map `PublicRoomTemplates`, so create that folder in Studio for manual testing or add a mapping in a later patch when templates are moved into source control.

## Required Model Structure

Each public room config entry points to a template by `TemplateName`. The model name should match that value, for example `Public_WelcomeLounge`.

Recommended structure:

```text
Public_WelcomeLounge
  RoomAnchor
  DoorSpawn
  EntryWalkTarget
  Room
    WalkableFloor
    RoomExitZone
  Furniture
```

`Furniture` is recommended for public seating, props, and later public interactions.

## PublicRoomConfig Metadata

Each public room should define stable metadata for the Room Navigator and server payloads:

- `PublicRoomId`
- `DisplayName`
- `ShortLabel`
- `Category`
- `Description`
- `TemplateName`
- `MaxOccupancy`
- `SortOrder`
- `IsOpen`
- `Tags`
- `Theme`
- `IconImageId` or `ThumbnailImageId` placeholder

Closed rooms should set `IsOpen = false`. The Navigator can show them as closed, and the server should reject joining them with a safe message.

## Required Markers

- `RoomAnchor`: required. The server positions the cloned room by this marker.
- `DoorSpawn`: required. Players are teleported here when they join.
- `RoomExitZone` or a descendant with `IsRoomExit = true`: required for the exit prompt and leave validation.
- `EntryWalkTarget`: required for the current doorway/exit walk flow.
- `Room/WalkableFloor`: required for camera framing, click-to-move, grid hover, and grid lines.
- `Furniture`: recommended. Warn if missing.

## Grid Requirements

For now, public rooms should usually use the tile grid.

- `UsesTileGrid = true` is recommended.
- `UsesTileGrid = false` should be reserved for a future no-grid movement patch.
- `TileSize = 4` is recommended.

Suggested room sizes:

- Welcome Lounge: `GridWidth = 16`, `GridDepth = 12`
- Game Hall: `GridWidth = 20`, `GridDepth = 14`
- Cafe: `GridWidth = 14`, `GridDepth = 10`

Set grid attributes on `Room.WalkableFloor` or the template model:

```text
TileSize = 4
GridWidth = 16
GridDepth = 12
UsesTileGrid = true
```

The floor should roughly match:

```text
WalkableFloor.Size.X = GridWidth * TileSize
WalkableFloor.Size.Z = GridDepth * TileSize
```

## Marker Properties

Use invisible, non-blocking marker parts unless actively debugging.

### DoorSpawn

- `Anchored = true`
- `CanCollide = false`
- `CanTouch = false`
- `CanQuery = false`
- `Transparency = 1`

### EntryWalkTarget

- `Anchored = true`
- `CanCollide = false`
- `CanTouch = false`
- `CanQuery = false`
- `Transparency = 1`

### RoomExitZone

- `Anchored = true`
- `CanCollide = false`
- `CanTouch = false`
- `CanQuery = true`
- `IsRoomExit = true`
- `Transparency = 1` after testing

## Public Room Behavior

- Public rooms should not show the player-room black void when `RoomType = "PublicSpace"` is set.
- The fixed hotel camera frames `Room.WalkableFloor`.
- Grid hover and grid lines appear when `UsesTileGrid` is true.
- Current click-to-move is grid-oriented, so no-grid public rooms need later movement support.
- Normal players cannot edit public rooms through player-room permissions.
- Sitting and public furniture interactions should be tested per furniture type.
- Public room state is not saved to player profiles.

## Validator

Run this Studio Command Bar helper after creating or changing templates:

```text
docs/tools/ValidatePublicRoomTemplates.lua
```

It reads `PublicRoomConfig`, checks each configured public template, and prints `[OK]`, `[WARN]`, or `[ERROR]` rows. The tool does not modify templates.

## Manual Testing Checklist

1. Confirm each public room appears in the Room Navigator.
2. Join the room.
3. Confirm the player spawns at `DoorSpawn`.
4. Confirm the camera frames the `WalkableFloor`.
5. Confirm no black void appears.
6. Confirm grid hover and grid lines appear for grid rooms.
7. Click-to-move across the floor.
8. Walk to `RoomExitZone` and confirm the exit prompt appears.
9. Leave the room and confirm return to the Main Menu.
10. Confirm normal players cannot enter edit mode or move/pick up public furniture.
11. Test intended sitting/interactions.
12. Join with multiple players and check spawn crowding.
