# Existing features and reuse decisions

2026-11-16. “Implemented” below means found in source and supplied resources. Runtime results are tracked separately in `docs/BASELINE_VALIDATION.md`; no row implies Android verification.

| System | Existing implementation | Gaps for RIFTOPS | Decision |
|---|---|---|---|
| Offline sessions | ENet host/client and playable host, `autoload/net.gd` | Protocol/content compatibility negotiation, explicit room identity | Retain transport |
| Discovery/join | UDP beacon and manual IP, `net.gd`, `ui/main_menu.gd` | Discovered custom port is not passed by current UI join signal; capacity advertisement is fixed | Preserve and harden |
| Lobby | Host marker, names, teams, agents, loadouts, map/mode/team size, start/leave; `ui/lobby.gd` | No player-ready protocol, avatars, room name/code; mode/map selection only fully distributed on match start | Rebuild presentation; add real server fields separately |
| Player | Capsule movement, gravity, jump, crouch, walk/run, camera, `player.gd` | Client-owned motion; dedicated sprint and validation policy | Retain initially |
| Combat | Server ammo/cadence/raycast/damage/shields/death, `player.gd` | Trusted movement/spread flags, origin tolerance, no rewind | Retain and test adversarial inputs |
| Movement replication | 25 Hz MoveSync, interpolation, `player.tscn`, `player.gd` | No prediction reconciliation; host view uses smoothed client state | Measure before redesign |
| Weapons | Seven resources, GLTF models, recoil/ADS/scopes/burst, `weapons/`, `weapon_*.gd` | Original flagship rifle, rigged hands, authored reload, polished muzzle effects/casings | Reuse data/combat; replace presentation |
| Characters | Four agent definitions, imported animated models | Idle/Run integration only, fixed gun mount, primitive corpse; no complete remote action state | Keep as regression assets |
| Abilities | Twelve casts, charges, walls/smokes/fire/flash/heal/recon/movement, ability/effect scripts | Late join does not reconstruct all active effects | Preserve existing modes; don't expand scope |
| TDM | Team kills, timer, target, respawn | No FFA; individual stats omitted by TDM early return | Preserve regression mode |
| Spike | Buy/live/planted/end phases, economy, halftime, elimination, plant/defuse, late join | Team-oriented and coupled to GameState | Preserve, extract carefully later |
| FFA | Not implemented: `Mode` contains TDM/SPIKE only | Individual rules, capacity, countdown, winner/ties, safe spawns | Implement dedicated module in M4 |
| HUD | Health/armor/ammo/weapon/crosshair/timer/team score/feed/pause/hit feedback, `ui/hud.gd` | Unified styling, individual K/D and FFA state | Modular redesign |
| Score/results | Team scoreboard, Spike K/D/A/economy, result overlay, automatic lobby return | Ranked individual final standings and K/D ratio | Extend with FFA result snapshot |
| Touch | Indexed multitouch, floating joystick, drag aim, two fire buttons, jump/reload/ADS/crouch/pause/abilities | Layout editor and sprint; physical overlap/gesture validation | Reuse routing and safe-area code |
| Settings/profile | Local name/loadout, mouse/touch/ADS sensitivity, inversion, touch mode, render scale | Profile screen, audio buses/sliders, control editing, graphics tiers/FPS fallback | Preserve ConfigFile migration |
| Maps | Graybox plus textured Solstice; `maps/` | Original suburban TESTSITE-07 absent | Keep originals, add map |
| Lighting | HDR sky, directional shadows, fog, materials; Solstice LightmapGI node | Bake data absent; unsupported renderer features need profiling | Improve based on device budget |
| Audio | Local recordings, positional shots/steps, ambience, UI cues, fallback synthesis | Cohesive mix, surface-aware steps, audio options | Reuse licensed sources |
| Effects | Tracers, impact particles, muzzle flash, status/explosion effects | Pooling, richer elimination/respawn, shell casings | Upgrade cosmetic layer only |
| Packaging | Android preset, publishing scripts and store metadata | Missing icons/LICENSE, local toolchain setup, new identity/signing | Restore baseline before release changes |
| Tests | Two-instance, Spike, three-instance Solstice, screenshot and map tools | Android/hotspot, hostile RPCs, packet loss, disconnect, UI flows | Retain and extend |

## Features that must not be called complete

Original RIFTOPS art, TESTSITE-07, FFA, custom controls, ready status, room codes, first-person hands, full action animation, a premium redesigned frontend, measured 60/30 FPS and a tested RIFTOPS APK are all outstanding. Bundled animation clips and fallback meshes do not satisfy finished art requirements. A test script's presence is not evidence that it passed.
