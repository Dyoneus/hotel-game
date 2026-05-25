# Room Grid Setup

## Starter Room Standard

Starter player rooms should use a 5x7 tile grid.

- `TileSize = 4`
- `GridWidth = 5`
- `GridDepth = 7`
- `WalkableFloor.Size.X = 20`
- `WalkableFloor.Size.Z = 28`

The `WalkableFloor` can use a Y size such as `0.5` or `1`.

## Required WalkableFloor Attributes

Set these attributes on `Room.WalkableFloor`:

- `TileSize = 4`
- `GridWidth = 5`
- `GridDepth = 7`
- `UsesTileGrid = true`

The shared `GridConfig.ValidateRoomGrid(roomModel)` helper checks these values and warns if the floor size does not match the grid attributes. It does not resize rooms or block room loading.

## Recommended Hierarchy

```text
Room
  WalkableFloor
  VisualFloorModel
```

`WalkableFloor` should be the authoritative clickable/grid floor used by hover, movement, and furniture placement.

Visual floor meshes, rugs, borders, or decorative parts should not replace `WalkableFloor` as the grid source.

## Walls And Boundaries

After resizing `WalkableFloor`, move and resize room walls, boundaries, and blocking parts to match the new 20 x 28 floor.

Walls and boundary parts should still prevent movement and furniture placement outside the intended room area.

## Public Spaces

Public spaces can either use custom grid settings or opt out:

- `UsesTileGrid = false`
- or custom `TileSize`, `GridWidth`, and `GridDepth`

Large public spaces that do not behave like normal rooms should set `UsesTileGrid = false`.

## Saved Furniture

- Existing saved furniture should not be auto-snapped.
- Old saved furniture keeps loading from its saved `RelativeCFrame`.
- Furniture snaps to the tile grid only when placed or moved again.

## Manual Studio Checklist

1. Open `ReplicatedStorage.RoomTemplates.Layout_01`.
2. Find `Room.WalkableFloor`.
3. Set `Size` to `20, 0.5, 28` or `20, 1, 28`.
4. Add attributes:
   - `TileSize = 4`
   - `GridWidth = 5`
   - `GridDepth = 7`
   - `UsesTileGrid = true`
5. Repeat for `Layout_02` and `Layout_03`.
6. Move/resize walls and boundaries to match.
7. Press Play.
8. Confirm floor hover shows 5 columns by 7 rows of possible tile centers.
9. Confirm click-to-move moves between those 5x7 tile centers.
10. Confirm furniture placement snaps to those tile centers.
