# Furniture Footprints

## Tile Standard

- `TileSize = 4` studs.
- One R6 avatar occupies one tile.
- A 5x7 starter room uses a `WalkableFloor` size of 20 x 28 studs.

## Required Template Attributes

Set these attributes on each furniture template model in `ReplicatedStorage.FurnitureTemplates`:

- `TemplateId` when the model should identify its inventory/catalog item.
- `FootprintWidth` as a positive integer tile width.
- `FootprintDepth` as a positive integer tile depth.
- `DefaultAction` when the furniture has an action such as `Sit`.
- `Tradable` / `Sellable` when the template has an explicit economy rule.
- `PickupTemplateId` for starter layout furniture that should return to inventory.

## PlacementBounds Rules

Each furniture template should include a part named `PlacementBounds`.

Recommended `PlacementBounds` settings:

- `Anchored = true`
- `Transparency = 1`
- `CanCollide = false`
- `CanTouch = false`
- `CanQuery = true`
- Centered on the furniture footprint.
- X/Z size equals the footprint tile size minus the footprint margin.

The shared margin is `GridConfig.FOOTPRINT_MARGIN`, currently `0.4` studs.

## Example PlacementBounds Sizes

- 1x1 tile: `3.6 x 4 x 3.6`
- 2x1 tile: `7.6 x 4 x 3.6`
- 2x3 tile: `7.6 x 4 x 11.6`

## Current Furniture Standards

- `Chair_01` = 1x1
- `Table_01` = 1x1
- `Bed_01` = 2x3

## Studio Asset Checklist

### Chair_01

- Set `FootprintWidth = 1`.
- Set `FootprintDepth = 1`.
- Set `PlacementBounds.Size` to about `3.6, 4, 3.6`.
- Center `PlacementBounds` on the occupied tile.

### Table_01

- Set `FootprintWidth = 1`.
- Set `FootprintDepth = 1`.
- Set `PlacementBounds.Size` to about `3.6, 4, 3.6`.
- Center `PlacementBounds` on the occupied tile.

### Bed_01

- Set `FootprintWidth = 2`.
- Set `FootprintDepth = 3`.
- Set `PlacementBounds.Size` to about `7.6, 4, 11.6`.
- Center `PlacementBounds` on the occupied footprint.

### Starter Layout Furniture

Apply matching footprint attributes to starter layout furniture in `ReplicatedStorage.RoomTemplates` when those starter items are pickable or movable.

For starter furniture that can be picked up, also confirm:

- `PickupTemplateId` points to the inventory template id.
- `Tradable = false` when it should return as untradable.
- `Sellable = false` when it should remain unsellable.
- `DefaultAction` is set when the furniture should support an action such as `Sit`.

## Saved Furniture Notes

- Existing saved furniture should not be auto-snapped.
- Old saved furniture keeps loading from its saved `RelativeCFrame`.
- Furniture snaps to the tile grid only when placed or moved again.
- Public spaces may set `UsesTileGrid = false`.
