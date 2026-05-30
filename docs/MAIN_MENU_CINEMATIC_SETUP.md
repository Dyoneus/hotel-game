# Main Menu Cinematic Setup

This is a setup guide for the future 3D main-menu hotel lobby. Patch 1B only adds a Studio generator and documentation. It does not change runtime Main Menu, camera, Room Navigator, or Work behavior.

## Generate The Scene

1. Start Rojo sync.
2. Open `docs/tools/CreateMainMenuHotelLobbyScene.lua`.
3. Copy the full script into Roblox Studio Command Bar.
4. Run it.
5. Confirm this hierarchy exists:

```text
ReplicatedStorage
  MainMenuScenes
    HotelLobbyMainMenu
      MainMenuAnchor
      CameraStart
      CameraConcierge
      CameraNavigatorDesk
      CameraWorkDesk
      Entrance
        EntranceDoorLeft
        EntranceDoorRight
        EntranceDoorLeftOpen
        EntranceDoorRightOpen
      ConciergeNPC
      AmbientNPCs
      Desk
      Seating
      CoffeeTables
      Props
      Lighting
      Floor
```

The generator uses `REPLACE_EXISTING = true`, so running it again rebuilds `HotelLobbyMainMenu`.

## Camera Markers

Markers are visible and labeled for setup. They use full `CFrame` orientation, so rotate them in Studio when tuning the future cinematic path.

- `MainMenuAnchor`: scene origin and future placement reference.
- `CameraStart`: near the hotel entrance, facing the concierge desk.
- `CameraConcierge`: closer to the concierge NPC for the welcome beat.
- `CameraNavigatorDesk`: angled down toward the right-side desk paper for Hotel Navigator.
- `CameraWorkDesk`: angled left toward the Work paper.

Future runtime camera code should read these marker CFrames, hide marker visuals, and tween the camera while the player is in Main Menu.

## Entrance Door Animation

The generated `Entrance` model includes visible `EntranceDoorLeft` and `EntranceDoorRight` panels plus invisible `EntranceDoorLeftOpen` and `EntranceDoorRightOpen` marker parts. `MainMenuCameraClient` tweens the visible door panels to those marker CFrames during the first-time onboarding intro only.

The open marker parts are non-colliding, non-querying, and hidden at runtime. Move or rotate them in Studio to tune how wide the doors open. Returning Main Menu visits use the shorter returning camera flow and do not replay the door-opening animation.

## Scene Purpose

The scene is intended to be visual-only and cloned locally by a future client script. It should not affect gameplay collisions, pathing, room joins, public rooms, or Work rewards.

Current placeholder parts are non-colliding, non-touching, and non-querying. The generated marker parts are visible for testing and also non-colliding/non-querying.

## Placeholder Content

The generated lobby includes:

- Entrance floor path
- First-visit entrance door panels with open-position markers
- Concierge helpdesk
- Back and side walls
- Side coffee tables and chairs
- Plants and columns
- Right-side `Navigator` paper placeholder
- Left-side `Work` paper placeholder
- Warm lobby lights
- `ConciergeNPC` placeholder
- Ambient NPC placeholders named `AmbientNPC_01`, `AmbientNPC_02`, and so on
- Signs for `HOTEL`, `CONCIERGE`, `Navigator`, and `Work`

No NPC AI, camera animation, subtitles, audio, or UI integration is included in this patch.

## IP Safety

Future secret/noir hotel easter eggs should use original names, characters, outfits, and lore. Avoid exact copyrighted names, likenesses, logos, or direct character copies.

## Manual Check

After generation:

1. Inspect `ReplicatedStorage.MainMenuScenes.HotelLobbyMainMenu`.
2. Confirm the scene resembles a rough hotel lobby.
3. Confirm camera markers are easy to identify.
4. Press Play.
5. Confirm current Main Menu behavior is unchanged.
6. Check Output for errors.
