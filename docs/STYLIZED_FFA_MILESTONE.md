# Stylized hero and playable FFA milestone

## Direction
RIFTOPS now targets a colorful stylized hero-shooter presentation. FRAG, T3 Arena and Ace Force are visual references; no proprietary models or extracted game content are bundled. The first hero is VOLT, based on the licensed Quaternius Punk mesh. See assets/characters/modular/PROVENANCE.md.

## Character implementation
- scripts/art/operator.gd now loads an authored skinned mesh with face, hair, earrings, fingers, layered vest, trousers and shoes, replacing the assembled primitive operator.
- Navy/teal/orange palette, normalized player height, natural lobby arm pose, breathing motion, procedural locomotion and rifle presentation.
- scripts/ui/operator_stage.gd frames the hero from the front; scripts/ui/lobby.gd identifies VOLT / STREET RUNNER.
- The same hero is used for FFA remote players. Gameplay hitboxes remain separate and unchanged.
- Downloaded models: Punk.glb (active), Swat.glb (evaluated alternative). Both CC0, bundled locally, with provenance and notice.

## Playable work carried forward
- TESTSITE-07: deterministic suburban arena, enterable houses, roof terraces, stair ramps, garden routes, cover vehicles, eight spawn points, distant scenery and textured materials.
- scripts/ui/minimap.gd: schematic building footprints and player heading. No omniscient enemy markers.
- Original RX-24 rifle presentation, existing recoil/ADS/reload/fire feedback retained.
- Real FFA mode: individual kills/deaths, kill limit, timer, scoreboard, respawns and replicated match result. Lobby defaults to TESTSITE-07, FFA, 30 kills.
- Legacy modes and maps retained internally for regression compatibility; no mode/team/agent/loadout selectors reintroduced.
- FFA ability casting disabled on both local and server paths. Opponent labels no longer appear through walls merely because all FFA players share team NONE.
- Shared material batching reduces separate mesh submissions while preserving collision transforms. Larger batches trade culling granularity for fewer draw calls.

## Verification
Godot 4.7.2, Windows Intel UHD:
- Lobby smoke passed for Play -> TESTSITE-07 -> return -> Leave.
- tests/ffa_network_smoke.gd passed in two real ENet processes: same-team-ID damage, one direct pipeline kill, respawn, host raycast kill, kill-limit end and client replication of kills/deaths/end.
- Captured and inspected lobby at 1280x720: builds/hero-final.png.
- Captured and inspected arena + rifle + minimap: builds/testsite-final.png. That capture precedes the final sky-fog adjustment and stair collision ramp.
- Arena capture after batching: 79 draw calls, about 108k submitted primitives, 153.5 MB reported VRAM, 38 FPS. This is one desktop capture, not a benchmark or Android claim.
- Lobby capture: 154 draw calls, about 49k submitted primitives, 32 FPS on this PC. Optimization remains necessary.
- No Android build was produced. Editor reports missing Android build-tools.

## Remaining work — not complete
- This is one hero foundation, not a finished roster or T3 Arena-quality art package.
- The mirror omits the original animation clips. Current animation is procedural; authored firing, reload, jump and death animation integration remains.
- First-person hands, expressive facial animation, polished weapon grip, hero-specific outfits and comprehensive animation blending remain.
- Arena needs more visual detail, human playtesting of sightlines and spawn fairness, and device performance work.
- Spawn selection currently maximizes distance to living players; it does not yet score visibility or grant spawn protection.
- FFA countdown, configurable limits/capacity UI, disconnected-player result retention and additional mode polish remain.
- Physical Android hotspot, multitouch, thermal and frame-rate validation remain required. Loopback testing does not establish hotspot performance.

## Run
Stop the previous game with F8, press F5, Host Game, then Play. No SDK is needed for desktop editor testing.
