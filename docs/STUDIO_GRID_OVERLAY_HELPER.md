# Studio Grid Overlay Helper

This helper creates an editor-only tile overlay for room templates so doors, wall holes, `DoorSpawn`, and `EntryWalkTarget` can be aligned to the 4-stud room grid.

Runtime room clones remove `EditorHelpers`, so these helper parts should not appear in `workspace.ActiveRooms`.

## Run The Helper

1. Open Roblox Studio with Rojo synced.
2. Select one or more room template models, for example:
   `ReplicatedStorage.RoomTemplates.Layout_01`
3. Open `docs/tools/CreateRoomGridOverlay.lua`.
4. Paste and run the script in the Studio Command Bar, or run it as a temporary Studio Script.
5. Confirm the template now contains:
   `EditorHelpers.RoomGridOverlay`

If nothing is selected, the helper falls back to `ReplicatedStorage.RoomTemplates.Layout_01`. You can also edit `ROOM_TEMPLATE_PATHS` in the script for specific template paths.

## What It Creates

For each selected room template, the helper:

- Finds `Room.WalkableFloor`, or falls back to any descendant named `WalkableFloor`.
- Reads `TileSize`, `GridWidth`, and `GridDepth`.
- Falls back to a 4-stud, 5x7 grid if attributes are missing.
- Creates boundary lines, tile lines, center markers, and optional coordinate labels.
- Prints expected floor size and actual floor size.
- Warns if `WalkableFloor.Size.X/Z` does not match `GridWidth * TileSize` and `GridDepth * TileSize`.

Overlay parts are anchored, non-colliding, non-touching, non-querying, and editor-only.

## Aligning Entrances

Recommended starter room setup:

- `TileSize = 4`
- `GridWidth = 5`
- `GridDepth = 7`
- `WalkableFloor.Size.X = 20`
- `WalkableFloor.Size.Z = 28`
- `UsesTileGrid = true`

Use the tile-center markers to place:

- `DoorSpawn`: inside or just behind the wall hole/cave entrance.
- `EntryWalkTarget`: on the first valid walkable tile inside the room.

The server still teleports players to `DoorSpawn`. `RoomEntryController` then walks them toward `EntryWalkTarget` if both markers exist.

## Doorway Layout

For Habbo-style wall holes or cave entrances, split the wall into pieces:

- Left wall piece
- Right wall piece
- Top lintel piece
- Optional back/cave side pieces

Leave a clear opening aligned to the tile grid. Put `DoorSpawn` in the cave/hole area and `EntryWalkTarget` on a visible walkable tile inside the room.

## Runtime Cleanup

`PlayerRoomServer` removes any direct child named `EditorHelpers` from cloned runtime rooms. This applies to player room templates and public room templates cloned into `workspace.ActiveRooms`.

Do not place gameplay objects inside `EditorHelpers`; it is for Studio design helpers only.
