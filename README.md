# Hotel Game

Habbo-inspired social room game.

Important rules:
- Server is authoritative.
- Never trust client furniture placement.
- Owners only can edit their own rooms.
- Guests can visit and interact, but not edit.
- Furniture uses TemplateId for catalog/inventory identity.
- Furniture uses PersistentId for placed furniture identity.
- Placement uses a 2-stud grid.
- PlacementBounds controls furniture placement footprint.
- RoomPersistence is the saved profile source of truth.
- Ask before changing major systems.

Current systems:
- Room creation
- Tutorial
- Fixed hotel camera
- Click-to-move
- Furniture sit/move/rotate
- Furniture catalog ghost placement
- Admin panel
- Room persistence
