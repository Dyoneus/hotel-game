# Furniture Import Pipeline

Use this workflow when adding Meshy, Roblox, or other imported furniture models
to the game. The goal is to make imported furniture safe for Catalog purchase,
Inventory placement, TileMask rooms, movement, rotation, saving, selling, and
marketplace rules.

## Roblox Assistant Procedural Furniture

Roblox Assistant or procedural model output should be treated as a source draft,
not as the runtime furniture template. The runtime furniture pipeline expects a
stable direct-child `Model` under `ReplicatedStorage.FurnitureTemplates`.

Recommended workflow:

1. Generate the draft with Roblox Assistant or the procedural model tool.
2. Bake, convert, or finalize the generated procedural object into a normal
   `Model` with `BasePart` or `MeshPart` descendants.
3. Move the baked `Model` under `ReplicatedStorage.FurnitureTemplates`.
4. Rename it with a stable ASCII template id, for example `Chair_Hotel_002`.
5. Select the baked model and run `docs/tools/PrepareImportedFurnitureTemplate.lua`.
6. Set or review the metadata: `DisplayName`, `Description`, `Category`,
   `CurrencyKey`, `Price`, `SellPrice`, `TradableOnPurchase`,
   `SellableOnPurchase`, `FootprintWidth`, and `FootprintDepth`.
7. Confirm `PlacementBounds`, pivot, `PrimaryPart`, and visual part collision
   settings.
8. Run `docs/tools/ValidateFurnitureTemplates.lua`.
9. Test purchase, inventory placement, move, rotate, TileMask rejection,
   save/rejoin, sell, and marketplace behavior in Studio.
10. Export/source-control the baked template as `.rbxmx`.
11. Set `AutoCatalogEnabled = true` only after validation and in-game tests pass.

Raw `ProceduralModel` roots are not supported as runtime templates because:

- Catalog lookup and auto-catalog discovery check for `Model` templates.
- Placement uses model pivots, model bounds, `PivotTo`, footprint attributes,
  and `PlacementBounds`.
- Room persistence restores saved catalog furniture from `Model` templates.
- Source control should store stable baked `.rbxmx` model assets.
- Raw procedural roots may serialize unpredictably or contain unsupported
  internal state.

Do not:

- Do not place raw `ProceduralModel` roots directly under
  `ReplicatedStorage.FurnitureTemplates`.
- Do not enable `AutoCatalogEnabled` on procedural drafts.
- Do not rely on procedural model bounds for placement.
- Do not skip `PlacementBounds`.
- Do not publish before validation and in-game tests.

Prompt examples for Roblox Assistant:

- Stylized hotel chair: "Create a compact stylized hotel lounge chair for a
  Roblox room, low-poly, warm fabric cushion, simple wooden legs, fits one 4x4
  stud tile."
- Small table: "Create a small square hotel side table for Roblox, stylized,
  clean silhouette, wood top, fits one 4x4 stud tile."
- Bed: "Create a stylized single hotel bed for Roblox, simple headboard,
  blanket and pillow shapes, fits a compact grid footprint."
- Lamp: "Create a small bedside lamp for Roblox, stylized base and shade,
  simple mesh parts, suitable for a hotel room."

## 1. Add the Template

Place every runtime furniture template under:

```text
ReplicatedStorage.FurnitureTemplates
```

Each direct child should be one furniture `Model`. Do not place imported shop
templates in room templates, StarterGui, ServerScriptService, or workspace-only
folders. Do not place raw `ProceduralModel` roots here; bake or convert them to
normal `Model` templates first.

Optional setup helper: after placing and selecting one imported model in Studio,
run `docs/tools/PrepareImportedFurnitureTemplate.lua` from the Command Bar. It
adds baseline attributes, creates `PlacementBounds`, sets safe visual collision
defaults, and leaves `AutoCatalogEnabled = false` for review.

## 2. Name the Model

Use stable ASCII model names:

- No spaces.
- No punctuation that is unsafe in ids.
- Use readable type/category prefixes.
- Keep the name stable after release because saves and inventory can refer to it.

Good examples:

- `Chair_Modern_001`
- `Sofa_Lounge_001`
- `Table_Cafe_001`

Avoid names like `Modern Chair`, `chair-final!!`, or `Meshy import 03`.

## 3. Configure Normal Shop Attributes

For normal Dollar shop furniture, set these attributes on the model:

```lua
AutoCatalogEnabled = true
DisplayName = "Modern Chair"
Description = "A clean chair for compact rooms."
Category = "Chair"
CurrencyKey = "Dollars"
Price = 100
SellPrice = 25
TradableOnPurchase = false
SellableOnPurchase = true
FootprintWidth = 1
FootprintDepth = 1
```

Required normal shop attributes:

- `AutoCatalogEnabled = true`
- `DisplayName`
- `Description`
- `Category`
- `CurrencyKey = "Dollars"`
- `Price`
- `SellPrice`
- `TradableOnPurchase = false`
- `SellableOnPurchase = true` or `false`
- `FootprintWidth`
- `FootprintDepth`

Auto-catalog imported furniture is validated strictly. Missing purchase
metadata, missing footprint attributes, or malformed economy fields should be
fixed before the item is treated as ready.

## 4. Use a PlacementBounds Part

Every imported template should include one `BasePart` named exactly:

```text
PlacementBounds
```

Recommended `PlacementBounds` settings:

- `Anchored = true`
- `Transparency = 1`
- `CanCollide = false`
- `CanTouch = false`
- `CanQuery = true`
- Centered on the intended occupied grid footprint.
- Tall enough to cover the usable furniture volume, usually `Y = 4`.
- Separate from visual mesh parts.

Use tile size `4` studs and margin `0.4` studs.

Size formula:

```text
X = FootprintWidth * 4 - 0.4
Z = FootprintDepth * 4 - 0.4
```

Examples:

- `1x1` footprint: `3.6 x 4 x 3.6`
- `2x1` footprint: `7.6 x 4 x 3.6`
- `2x3` footprint: `7.6 x 4 x 11.6`

Do not rely on imported mesh bounds for placement. Mesh bounds can be noisy,
rotated, oversized, or too tight. `PlacementBounds` is the intentional placement
contract.

## 5. Separate Visual Size From Gameplay Footprint

`FootprintWidth`, `FootprintDepth`, and `PlacementBounds` define the gameplay
footprint: where the item may be placed, how TileMask holes are checked, and how
nearby furniture is blocked.

The visual mesh may be slightly larger than that footprint when the overhang is
intentional. This is useful for stylized furniture with soft cushions, high
backs, arms, crowns, or decorative trim. Do not change the global grid size just
to fit one furniture item.

Use these optional attributes when visual overhang is intentional:

```lua
AllowVisualOverhang = true
VisualOverhangStudsX = 0.4
VisualOverhangStudsZ = 0.3
```

`VisualOverhangStudsX` and `VisualOverhangStudsZ` are documentation/validator
metadata for reviewers. Runtime placement still uses `PlacementBounds` and the
footprint attributes.

Sizing examples:

- Simple chair: usually `1x1` with little or no overhang.
- Chunky armchair: `1x1` with small overhang, or `2x1` / `2x2` if truly large.
- Throne: often `1x1` with visual overhang, or `2x1` if wide.
- Sofa: usually `2x1`, `3x1`, or `3x2`.
- Bed: usually around `3x4` for larger imported beds.

Always test nearby placement visually. Even allowed overhang should not make two
adjacent items look badly intersected.

## 6. Set Pivot and PrimaryPart

Set a stable model pivot before testing.

Recommended setup:

- Align the model bottom to the room floor.
- Put the pivot at the intended placement center.
- Prefer `PrimaryPart = PlacementBounds` or a deliberate invisible root part.
- Keep pivot behavior stable after scaling or regrouping mesh parts.

The preview, placement, move, rotate, and saved CFrame behavior all depend on a
predictable pivot.

## 7. Prepare Visual Mesh Parts

For visual `MeshPart` and `BasePart` descendants:

- Keep them `Anchored = true`.
- Set `CanTouch = false`.
- Set `CanQuery = false` unless a visual part must be raycast/query target.
- Set `CanCollide = false` unless the furniture intentionally blocks movement.
- Use `PlacementBounds` for placement size instead of mesh bounds.
- Keep mesh visuals separate from `PlacementBounds`.

Some furniture intentionally blocks movement. In that case, keep collision
deliberate and test that avatars cannot become trapped.

## 8. Choose a Supported Category

Use one of the supported catalog categories:

- `Bed`
- `Chair`
- `Divider`
- `Floor`
- `Food`
- `Gate`
- `Lighting`
- `Music`
- `Other`
- `Pets`
- `Present`
- `Roller`
- `Rug`
- `Shelf`
- `Table`
- `Wall Decoration`
- `Wallpaper`
- `Window`

Use singular categories such as `Chair`, `Table`, and `Bed` for new imports.

## 9. Keep Trading and Marketplace Rules Intentional

Normal Dollar furniture should usually be:

```lua
TradableOnPurchase = false
SellableOnPurchase = true
```

Do not set imported Dollar furniture as tradable unless it is intentionally a
premium, event, or trading item. Always set `SellableOnPurchase` explicitly so
the item does not inherit an accidental default.

Before release, test:

- Purchased item is untradable when `TradableOnPurchase = false`.
- Selling is enabled or disabled according to `SellableOnPurchase`.
- Marketplace listing behavior is disabled or enabled only as intended.

## 10. Configure Interactive Furniture

### Sit Furniture

For furniture that should be clickable as a seat:

```lua
DefaultAction = "Sit"
```

Also add:

- A `Seat` when the furniture should use Roblox seat behavior.
- A `SitPoint` marker so the click-to-sit target is clear.

Test the entry point, sitting pose, standing behavior, and room transition
unseat behavior.

### Open/Close Furniture

For open/close furniture:

```lua
SupportsOpenClose = true
PermissionActions = "OpenClose"
DefaultAction = "OpenClose"
OpenCloseTargetName = "DoorPanel"
OpenAngleDegrees = 90
OpenCloseAxis = "Y"
```

Requirements:

- `OpenCloseTargetName` should resolve to a child `BasePart` or `Model`.
- `OpenAngleDegrees` should be intentional.
- `OpenCloseAxis` should match the model orientation.
- Public interaction attributes such as `PublicUse`, `PublicOpenClose`, or
  `AllowPublicOpenClose` should only be set deliberately.

## 11. Validate the Template

Run this Studio tool after adding or changing furniture:

```text
docs/tools/ValidateFurnitureTemplates.lua
```

The validator inspects every direct child model under
`ReplicatedStorage.FurnitureTemplates`, including static catalog furniture,
auto-catalog imports, inventory-only furniture, and test templates.

Result meanings:

- `PASS`: no warnings or errors.
- `WARN`: cleanup is needed, but no blocking errors were found.
- `FAIL`: at least one blocking error must be fixed.

Legacy starter templates may still warn while they are being normalized. New
`AutoCatalogEnabled = true` imported furniture should pass strict checks before
being treated as ready.

## 12. Test In Studio

Use this checklist for every imported item:

- Appears in Catalog.
- Can be bought.
- Dollars decrease by the configured `Price`.
- Appears in Inventory.
- Can be placed in a rectangular room.
- Can be moved and rotated.
- Move/rotate preview uses the intended footprint.
- Placement and move/rotate previews respect TileMask holes.
- Invalid TileMask placement is red/invalid.
- Save, leave, rejoin, and confirm the item persists.
- Pick up behavior returns the expected inventory item.
- Sell behavior matches `SellableOnPurchase`.
- Trade/marketplace behavior matches `TradableOnPurchase`.
- Interactive actions such as Sit or OpenClose still work after save/rejoin.

## 13. Meshy and Imported Model Tips

Before importing:

- Check scale against the 4x4 stud grid.
- Reduce polygon count if the asset is too heavy.
- Remove embedded scripts, LocalScripts, and ModuleScripts.
- Check orientation so the front of the model faces the intended direction.
- Simplify collisions and avoid complex mesh collision where possible.

After importing into Studio:

- Group visuals into one furniture `Model`.
- Add a clean `PlacementBounds` part instead of depending on mesh bounds.
- Keep textures and materials readable under the room lighting.
- Verify mesh parts are anchored.
- Disable `CanTouch` on visual parts.
- Disable `CanQuery` on visual parts unless needed.
- Disable `CanCollide` on visuals unless the furniture should block movement.
- Recheck pivot and floor alignment after scaling.

Meshy imports may arrive with the wrong pivot or scale. Run
`docs/tools/PrepareImportedFurnitureTemplate.lua` after manual scaling, or enable
`AUTO_SCALE_TO_TARGET_SIZE` in that helper for a selected model. Manual visual
scale remains preferred per item. For chunky plush armchairs, prefer a `2x2`
footprint only when the chair is truly large; otherwise a `1x1` footprint with
intentional `AllowVisualOverhang = true` may fit better. Target visual height is
usually around `5.0` to `5.5` studs. `PlacementBounds` should align to the visual
bottom of the model, not to an imported pivot that may be floating away from the
mesh.

## 14. Release Checklist

Before merging or shipping an imported furniture item:

1. Template is under `ReplicatedStorage.FurnitureTemplates`.
2. Model name is stable ASCII with no spaces.
3. Normal shop metadata is complete.
4. `PlacementBounds` exists and matches the footprint.
5. Pivot and PrimaryPart are deliberate.
6. Validator result is acceptable for the item type.
7. Catalog purchase works.
8. Inventory placement works.
9. Move/rotate preview uses the correct footprint.
10. TileMask holes are respected.
11. Save/rejoin persistence works.
12. Sell/trade/marketplace behavior is intentional.
