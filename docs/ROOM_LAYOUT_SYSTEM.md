# Room Layout System

Room layouts describe the structure and shape of owned rooms. They are metadata records for room footprints, tile counts, access rules, visitor limits, and future template names.

This patch only adds layout metadata. It does not add room templates, multiple owned room persistence, room creation, or Room Planner integration.

## Access Tiers

Layouts use two in-game access categories:

- `Free`: available to all players when selectable.
- `VIP`: reserved for future VIP membership.

VIP membership is not implemented yet. VIP layouts are metadata-locked through `RequiresVip = true` so future create-room flows can enforce access once VIP status exists.

## Layout Features

VIP layouts may include special room structures:

- stairs
- holes or void areas
- multi-level structures
- hidden or secret areas

Free layouts are currently simpler metadata targets. Actual templates can still decide their final geometry in a later asset/import patch.

## Tile Counts And Shapes

Tile count is not a unique layout id. Multiple layouts can have the same tile count with different shapes. For example, `Free_080_A` and `Free_080_B` are separate records so Room Planner can eventually show different 80-tile shapes.

Each layout has an original `LayoutId`, `TemplateName`, and `PreviewKey`. The current placeholders do not depend on outside branding, images, or copied assets.

## Template Status

`RoomLayoutConfig` tracks both selectable and unavailable layouts:

- Available layouts use `Status = "Available"` and `IsSelectable = true`.
- Unavailable legacy layouts use `Status = "Unavailable"` and `IsSelectable = false`.

Unavailable layouts remain in metadata for save compatibility, migration planning, and future admin tooling, but they should not appear as selectable choices for new rooms.

## Visitors

Visitor limits are first-pass metadata:

- smaller rooms usually use `MaxVisitors = 25`
- larger rooms usually use `MaxVisitors = 50`
- `OwnerExtraSlot = true` means the owner can be counted separately from visitor capacity

Exact limits can be tuned per layout after templates, performance budgets, and gameplay expectations are known.

## Future Patches

Future patches should use this foundation to:

- generate or import actual `RoomTemplates`
- show layout previews in Room Planner
- create multiple owned rooms
- save each owned room by room id
- enforce VIP restrictions when VIP membership exists

## Generating Free_036_A

`Free_036_A` is the first real owned-room layout template. It is a simple 6 x 6 starter room with 36 walkable tiles and the configured template name `RoomLayout_Free_036_A`.

After Rojo sync, run this in Studio Command Bar:

```lua
-- Paste/run docs/tools/CreateRoomLayout_Free_036_A.lua
```

Then run:

```lua
-- Paste/run docs/tools/ValidateRoomLayoutTemplates.lua
```

Expected validation behavior:

- `Free_036_A` / `RoomLayout_Free_036_A` reports `[OK]` after the generator has run.
- Other available layouts can still warn as missing until their templates are generated.
- Unavailable legacy layouts are tracked in metadata but are not required.

Manual gameplay check:

- create a Starter Studio room from Room Planner
- join the created room
- verify DoorSpawn, EntryWalkTarget, grid hover, click-to-move, exit flow, furniture placement, and room-specific furniture persistence
- join Primary and confirm Primary remains unchanged

## Manual Check

After Rojo sync, run this in Studio Command Bar:

```lua
local Layouts = require(game.ReplicatedStorage.Shared.RoomLayoutConfig)
print(#Layouts.GetSelectableLayouts())
print(Layouts.GetLayout("Free_104_A"))
print(Layouts.CanUseLayout("VIP_748_A", { HasVip = false }))
print(Layouts.CanUseLayout("VIP_748_A", { HasVip = true }))
```

Expected behavior:

- free layouts load
- VIP layouts reject when `HasVip = false`
- VIP layouts allow when `HasVip = true`
- unavailable layouts are not selectable

If using `docs/tools/ValidateRoomLayoutTemplates.lua`, missing template warnings are expected until actual room template models are generated or imported.
