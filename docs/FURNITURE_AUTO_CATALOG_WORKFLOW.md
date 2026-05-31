# Furniture Auto-Catalog Workflow

Regular Dollar furniture can be added to the Catalog by placing a template model in
`ReplicatedStorage.FurnitureTemplates` and enabling catalog attributes on that model.

## Basic Setup

1. Add a model under `ReplicatedStorage.FurnitureTemplates`.
2. Name the model with the template id, for example `Sofa_01`.
3. Add a `PlacementBounds` part inside the model.
4. Set the model attributes:

```lua
AutoCatalogEnabled = true
DisplayName = "Cozy Sofa"
Description = "A comfy sofa for your room."
Category = "Seating"
CurrencyKey = "Dollars"
Price = 120
SellPrice = 30
TradableOnPurchase = false
SellableOnPurchase = true
FootprintWidth = 2
FootprintDepth = 1
DefaultAction = "Sit"
```

Only models with `AutoCatalogEnabled = true` are added automatically. Static
entries in `FurnitureCatalogConfig.lua` still work and win if they use the same
item id.

## Required Attributes

- `AutoCatalogEnabled = true`
- `CurrencyKey = "Dollars"`
- `Price` as a positive integer

Useful optional attributes:

- `DisplayName`, defaults to the model name
- `Description`, defaults to blank
- `Category`, defaults to `Furniture`
- `SellPrice`, defaults to `0`
- `TradableOnPurchase`, defaults to `false`
- `SellableOnPurchase`, defaults to `true`
- `FootprintWidth`, defaults to `1`
- `FootprintDepth`, defaults to `1`

Dollar auto-catalog furniture is untradable by default and sellable by default.
Coin and Robux purchase backends are not part of this workflow.

## Placement Bounds

Every placeable furniture model should include a `PlacementBounds` part. The
validator warns when it is missing. The model should also set
`FootprintWidth` and `FootprintDepth` to match the intended grid footprint.

## Sit Furniture

For furniture with `DefaultAction = "Sit"`:

- Add a `Seat` or another seat-compatible part when appropriate.
- Add a `SitPoint` marker so click-to-sit behavior has a clear target.

## Doors and Gates

For open/close furniture:

```lua
SupportsOpenClose = true
PermissionActions = "OpenClose"
OpenCloseTargetName = "DoorPanel"
```

The target named by `OpenCloseTargetName` should exist inside the template.

## Testing

1. Run `docs/tools/ValidateFurnitureTemplates.lua` in Studio Command Bar.
2. Open Catalog > Furniture Shop.
3. Confirm the item appears in the expected category.
4. Buy the item and confirm Dollars decrease.
5. Confirm the item appears in Inventory as untradable unless explicitly configured.
6. Place, move, rotate, and pick up the item in an owned room.
