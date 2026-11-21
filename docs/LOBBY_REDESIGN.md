# Lobby redesign verification

The live `scenes/ui/lobby.tscn` uses the replacement `scripts/ui/lobby.gd`.

## Implemented
- Full-screen 3D hangar and bundled animated soldier through `scripts/ui/operator_stage.gd`.
- Custom dark panels, yellow Play action, player roster, host badge, private IP display and Leave action.
- Removed selectable agents, weapons, teams, team size, modes and maps from this screen.
- Retained the existing Net room lifecycle and GameState match-start entry point.
- Hidden lobby rendering pauses; headless instances skip the visual stage.

## Verification
Godot 4.7.2 on Windows:
- `tests/lobby_ui_smoke.gd` passed: no selectors, host Play launches Solstice, return to lobby preserves session, Leave disconnects.
- Two real ENet instances connected over loopback and displayed both players. Client showed Waiting for Host.
- Rendered and inspected 1280x720 host and 1600x720 client screenshots in builds/lobby-final-host.png and builds/lobby-final-client.png.

## Outstanding
This is a lobby presentation milestone. It uses the bundled stylized soldier, not a completed original character. The current match remains Solstice Team Deathmatch and is labeled accordingly. FFA and the new suburban arena are not implemented by this change. Main menu redesign remains outstanding.

Android appearance, hotspot connections and performance require device testing. Two simultaneous desktop renderers reported 13–20 FPS on Intel UHD; this is not a valid Android performance result or a completed optimization pass.
