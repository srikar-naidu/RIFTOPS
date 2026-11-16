# Valu — Toolchain & Project Conventions

Facts every later phase agent needs. Everything below was verified working on this machine on 2026-07-25.

## Toolchain (exact paths)

| Thing | Value |
|---|---|
| Godot binary | `/Applications/Godot.app/Contents/MacOS/Godot` (the cask also linked `/opt/homebrew/bin/godot`) |
| Godot version | `4.7.1.stable.official.a13da4feb` |
| Export templates | `~/Library/Application Support/Godot/export_templates/4.7.1.stable/` (`android_debug.apk` and `android_release.apk`; `version.txt` = `4.7.1.stable`) |
| JAVA_HOME | `/opt/homebrew/opt/openjdk@17` (OpenJDK 17.0.20, keg-only — NOT on PATH by default) |
| Android SDK | `/Users/dakshmor/Library/Android/sdk` |
| adb | `/Users/dakshmor/Library/Android/sdk/platform-tools/adb` (NOT on PATH) |
| apksigner / aapt2 / zipalign | `/Users/dakshmor/Library/Android/sdk/build-tools/35.0.0/` |
| Debug keystore | `~/.android/debug.keystore` (development builds only) |
| Release keystore | `~/keystores/valu-release.jks`, alias `valu` |
| Release credentials | `~/keystores/valu-release-credentials.txt` (mode 600; source this file for release exports) |
| Editor settings file | `~/Library/Application Support/Godot/editor_settings-4.7.tres` — already contains `export/android/android_sdk_path`, `export/android/java_sdk_path`, and debug keystore path/user/pass. Do not delete it. |

## The commands that work (copy-paste)

Always set `JAVA_HOME` and put its `bin` on `PATH` first — apksigner is a script that needs `java`:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export PATH="$JAVA_HOME/bin:$PATH"
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
PROJ="$PWD"

# 1. Import assets (REQUIRED after adding/changing any asset, before export or headless runs)
"$GODOT" --headless --path "$PROJ" --import

# 2. Load release-signing variables from the local credentials file
source "$HOME/keystores/valu-release-credentials.txt"

# 3. Export the release APK
"$GODOT" --headless --path "$PROJ" --export-release "Android" builds/Valu-1.0.0.apk

# 4. Verify the APK and print its signing certificate
/Users/dakshmor/Library/Android/sdk/build-tools/35.0.0/apksigner verify \
  --verbose --print-certs builds/Valu-1.0.0.apk

# 5. Headless smoke test (project must boot with exit code 0, no script/scene errors)
"$GODOT" --headless --path "$PROJ" --quit-after 3

# 6. Smoke-test a single scene
"$GODOT" --headless --path "$PROJ" res://maps/graybox/graybox.tscn --quit-after 3

# Install on a phone
/Users/dakshmor/Library/Android/sdk/platform-tools/adb install -r builds/Valu-1.0.0.apk
```

`export_presets.cfg` contains no keystore path, alias, or password. The credentials file exports `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER`, and `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`, which override the empty preset values without placing secrets in the project or shell command history. Never print these variables.

Back up **both** `~/keystores/valu-release.jks` and `~/keystores/valu-release-credentials.txt` to a secure location. Losing the keystore or its password means future APKs cannot update installations signed with this key.

## Android preset facts

- Preset name: `Android` (in `export_presets.cfg`), package `io.github.daksh_mor.valu`, name `Valu`, version `1.0.0` (`versionCode` 1).
- `arm64-v8a` only. `use_gradle_build=false` (plain template-based APK export — no Gradle, no cmdline-tools needed).
- minSdk = 24, targetSdk = **36** (baked into Godot 4.7.1's prebuilt templates; the plan said 35, but min/target can only be overridden when Gradle builds are enabled — leave `gradle_build/min_sdk`/`target_sdk` EMPTY or export fails validation).
- Permissions already enabled for LAN play: `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`.
- `exclude_filter="assets/_staging/*"` — `assets/_staging/` is scratch space for raw downloads (zips, scrapes); nothing there ever ships.
- Release output is `builds/Valu-1.0.0.apk`; `builds/` may also get a `.apk.idsig` sidecar (ignore it).

## Project structure & ownership

| Path | Owns |
|---|---|
| `autoload/` | Singletons: `net.gd` (Net), `game_state.gd` (GameState), `settings.gd` (Settings) |
| `scenes/` | `boot.tscn` = main scene (placeholder menu; Phase 2+ replaces). `scenes/ui/` for HUD/menus |
| `scripts/` | Shared/non-scene scripts (player controller etc.) |
| `weapons/` | Weapon scenes + data-driven weapon stats resources |
| `agents/` | Agent scenes, ability scripts |
| `maps/` | One folder per map; `maps/graybox/graybox.tscn` is the reference map |
| `assets/` | Art/audio/fonts (a parallel agent populates this; `assets/_staging/` = raw downloads, never referenced by scenes) |
| `builds/` | APK outputs (never commit; not that we use git yet) |
| `docs/` | This file + player-facing docs |

## Autoload responsibilities (singleton names)

- **Net** (`autoload/net.gd`): ALL networking. ENet host/join, UDP LAN discovery, connection signals. Nothing else touches `multiplayer.multiplayer_peer`.
- **GameState** (`autoload/game_state.gd`): round state machine, teams, economy, scores. Server-authoritative. Shared enums `Team`, `RoundPhase` and the competitive timing constants live here — use them, don't redeclare.
- **Settings** (`autoload/settings.gd`): sensitivity/audio/graphics options, persisted to `user://settings.cfg`.

## Physics layers (3D)

| # | Name | Use |
|---|---|---|
| 1 | world | Static level geometry, floors, walls, crates, buy barriers |
| 2 | players | Player character bodies |
| 3 | hitboxes | Head/body/leg hurtboxes (shot raycasts scan 1|3, movement collides 1|2) |
| 4 | utility | Ability projectiles/walls/smokes |
| 5 | triggers | Area3D zones (plant zones etc.) |

## Input actions (all defined in project.godot — desktop bindings; touch added in mobile-ux phase)

`move_forward` (W), `move_back` (S), `move_left` (A), `move_right` (D), `jump` (Space), `crouch` (Ctrl or C), `walk` (Shift), `fire` (LMB), `ads` (RMB), `reload` (R), `interact` (F — plant/defuse), `ability_1` (Q), `ability_2` (E), `ability_3` (X), `weapon_primary` (1), `weapon_secondary` (2), `weapon_knife` (3), `buy_menu` (B), `scoreboard` (Tab), `pause` (Esc).

All keys are bound via physical keycodes. Add new actions to `project.godot`, not at runtime.

## Map contract (every map MUST provide this; graybox.tscn is the reference)

- Scale: **1 unit = 1 meter**. Corridors ≥ 3 m wide, walls ~4 m high. Graybox floor is 60×60 m centered on origin; attackers at −Z, defenders at +Z.
- Root is a `Node3D`. All static geometry: `StaticBody3D` with collision on **layer 1**.
- Spawns: `Marker3D` nodes — 5 in group `spawn_attacker`, 5 in group `spawn_defender`. Markers sit ON the floor (y=0) with −Z facing the enemy side; spawn code must add the character's own capsule offset.
- Plant zones: `Area3D` in groups `plant_zone_a` and `plant_zone_b`, collision layer 5 (triggers), mask 2 (players), ~6×6 m footprint, shape ~2 m tall.
- Buy barriers: `StaticBody3D` in groups `buy_barrier_attacker` and `buy_barrier_defender`, near each spawn. Game code toggles `visible` + `collision_layer` (0 ↔ 1) at buy-phase start/end. In graybox they are full-width translucent walls; real maps should barrier individual chokepoints (multiple nodes per group is allowed — always use `get_tree().get_nodes_in_group(...)`).
- Lighting: `DirectionalLight3D` (shadows on) + `WorldEnvironment` with a sky. Renderer is **Forward Mobile** on all platforms (`renderer/rendering_method="mobile"`), so keep light counts low; map-art phase adds LightmapGI.

## Gotchas hit in Phase 1 (don't rediscover these)

1. **`gradle_build/min_sdk`/`target_sdk` MUST stay `""`** in `export_presets.cfg` when `use_gradle_build=false`, or export aborts with "can only be overridden when Use Gradle Build is enabled".
2. **ETC2/ASTC is mandatory for Android**: `textures/vram_compression/import_etc2_astc=true` under `[rendering]` in `project.godot` (already set). Without it export fails.
3. Run `--import` before `--export-debug` or headless runs whenever assets changed; export itself won't import new files.
4. The log line `cannot connect to daemon at tcp:5037: Connection refused` is Godot pinging adb — harmless, not an error.
5. `Could not find version of build tools that matches Target SDK, using 35.0.0` during export is a benign warning (templates target 36, newest local build-tools is 35.0.0 — signing/aligning still works).
6. This Homebrew version removed `--no-quarantine`; quarantine was stripped manually with `xattr -dr com.apple.quarantine /Applications/Godot.app`. If Godot is ever reinstalled, repeat that or the binary may be Gatekeeper-blocked.
7. Godot 4.7 auto-detected the Android SDK and Java paths on first editor run and auto-creates its own debug keystore under `~/Library/Application Support/Godot/keystores/` — we standardized on `~/.android/debug.keystore` instead (set in editor settings + preset). APK cert SHA-256 starts `8a613242…`.
8. Godot writes `.uid` sidecar files next to scripts/scenes — leave them alone (they keep references stable).
9. `project.godot` declares `config/features=PackedStringArray("4.7", "Mobile")` — keep in sync if the engine is ever upgraded, and reinstall matching export templates for any new version.

---

# Phase 2 additions (core FPS + LAN multiplayer)

## Net protocol (autoload/net.gd owns ALL of this)

- **ENet game port: 27015** (`Net.DEFAULT_PORT`), max 10 peers, server-authoritative.
- **UDP discovery port: 27016** (`Net.DISCOVERY_PORT`). While hosting, Net broadcasts a JSON beacon to 255.255.255.255:27016 once per second:
  `{"game":"valu","name":<host name>,"players":N,"max":10,"port":27015,"map":"graybox"}`.
  Clients call `Net.start_discovery()` (binds 27016) and listen to `lan_servers_updated(servers)`; entries stale after 3.5 s are pruned. Manual IP entry is the fallback.
- **Player registry**: `Net.players = {peer_id: {name, team, primary, secondary}}`, mutated ONLY on the server (`srv_register/srv_set_team/srv_set_loadout`), mirrored to everyone via `cl_players`. Team auto-balance on join. Listen to `player_list_changed`.
- **RPC surface rules**: autoload-level RPCs live on Net (registry) and GameState (match lifecycle: `cl_start_match`, `cl_kill_feed`, `cl_match_end`, `cl_time`). Per-player combat RPCs live on the Player node (`srv_fire/srv_reload/srv_switch` client→server; `cl_health/cl_tag/cl_die/cl_respawn/cl_ammo/cl_hit_confirm/cl_shot_fx` server→clients). Server-side direct calls use sender id 0 == host; helpers `request_fire()` etc. route local-vs-RPC automatically.
- **Movement is owner-authoritative**: each client simulates itself; `MultiplayerSynchronizer` (25 Hz, `sync_position/yaw/pitch/crouched/slot` + spawn-only identity fields) replicates to others, remote peers interpolate (lerp factor 14/s, snap at >4 m). Combat is SERVER-authoritative: clients send eye origin + center-ray direction; the server computes spread/spray from a per-player seeded RNG (`hash([match_seed, peer_id])`), validates fire-rate/ammo/alive, raycasts on layers 1|3 with `collide_with_areas`, applies damage and broadcasts FX/kill feed.

## Match flow contract

boot.tscn (main menu / lobby UI, scripts in `scripts/ui/`) → host presses Start → `GameState.host_start_match(map_path, mode, team_size)` → `cl_start_match` on every peer changes scene (DEFERRED — never call `change_scene_to_file` directly inside a signal chain) to `scenes/match.tscn` → each client RPCs `srv_client_ready` → the server spawns everyone only after ALL registered peers are ready (8 s safety timeout), via `MultiplayerSpawner` under `Match/Players`, node name == peer id. This barrier avoids the spawner-vs-scene-load race; keep it for future modes. TDM: respawn 3 s (`match.gd`), first to 40 kills or 10 min. Buy barriers from the map contract are disabled at match start in TDM; Spike mode will toggle them per round phase.

## Player rig facts (agents/abilities phases will need these)

- CharacterBody3D, layer 2, mask 1|2. Capsule r=0.35, h=1.8 (crouched 1.3), origin at feet. Eye height 1.6 (crouch 1.15). Run 6.75 m/s × weapon `move_speed_mult`, walk 3.6, crouch 3.0, jump apex 0.9 m, gravity 18.
- Hurtboxes (`HitboxRegion` Area3D, layer 3/value 4, mask 0): head sphere r=0.14 @ y1.56 (follows crouch), torso capsule r=0.26 h=0.85 @ y1.12, legs box 0.42×0.8×0.34 @ y0.42. Shot rays scan mask `0b101`.
- Tagging: on bullet hit victims run at 27.5% speed, recovering in ~0.5 s (`tag_mult`).
- Player capsule shape is `duplicate()`d in `_ready` — .tscn subresources are shared across instances; do the same for any per-instance-resized shape.

## Weapon data conventions

- `WeaponData` resource script: `scripts/weapon_data.gd`; one `.tres` per weapon in `weapons/`; ALL weapons must be registered in `scripts/weapon_db.gd` (`WeaponDB.ALL` + PRIMARIES/SECONDARIES). Stats use a July 2026 balance snapshot; spray patterns are hand-tuned approximations. `damage_bands` = Array[Vector4] (x=max range m, y/z/w=head/body/legs).
- Asset auto-pickup (checked at runtime with `ResourceLoader.exists`, placeholders otherwise — safe while the asset agent works in parallel): viewmodels via `viewmodel_path` (Quaternius guns in `assets/weapons/*.gltf`, mapping per docs/ASSETS.md), gun SFX via explicit `fire_sound_path` in each .tres (wired to the Free Firearm Sound Library WAVs) with `assets/audio/guns/{weapon_id}_fire.ogg|wav` as the generic fallback, UI/foley cues via `Sfx.UI_ASSET_CANDIDATES` (hitmarker tick, headshot bell, dry click, reload foley, death grunts), third-person model `assets/characters/Character_Soldier.gltf`. Missing files silently fall back to synthesized placeholder sounds / placeholder meshes.

## CLI test hooks & test commands (parse in scripts/cli.gd)

User args go after `--`. Flags: `--host [--map <name>] [--port N] [--start-when N]`, `--join <ip>`, `--name <s>`, `--seed <int>`, `--tdm-target N`, `--expect-players N`, `--spawn-dummy`, `--test-shot`, `--autoquit <sec>` (exit 2 on timeout, 0 on pass). Map names resolve to `res://maps/<name>/<name>.tscn`.

```bash
# solo scripted combat smoke (spawns dummy, server-side shots, kill feed):
"$GODOT" --headless --path "$PROJ" -- --host --map graybox --start-when 1 \
  --expect-players 1 --spawn-dummy --test-shot --seed 42 --autoquit 20
# two-instance LAN test (host+client, asserts connect/replication/damage/kill feed):
bash tests/two_instance_test.sh          # logs in tests/logs/, exits 0 on PASS
# manual desktop instances:
"$GODOT" --path "$PROJ" -- --host --map graybox --start-when 1
"$GODOT" --path "$PROJ" -- --join 127.0.0.1
```

## Phase 2 gotchas

10. Headless/CLI runs need `user://` writable (Godot writes logs/settings there) — sandboxed shells that block `~/Library/Application Support/Godot` writes make Godot crash on startup with a bogus signal-11 backtrace. Run Godot commands unsandboxed.
11. `get_tree().change_scene_to_file()` inside an RPC/signal chain triggers "Parent node is busy" — always `call_deferred` it.
12. `Settings.player_name` is overridden in-memory by `--name` but NOT saved; two instances sharing `user://settings.cfg` on one machine is fine.
13. Sibling headless `--import` runs can collide when several agents work concurrently — transient `.godot` cache errors fix themselves on retry.

---

# Solstice map (Phase 2B — map-art)

The competitive two-site map: `res://maps/solstice/solstice.tscn` (resolves via the CLI hook as `--map solstice`). Fully satisfies the MAP CONTRACT — `maps/solstice/tools/validate_map.gd` is the canonical checker (run headless, prints PASS/FAIL, exits 0 on pass).

## Authoring model — NEVER hand-edit solstice.tscn

The scene is GENERATED by `maps/solstice/tools/build_map.gd` (SceneTree script; layout, materials, props and lighting are data tables in that file). Edit the generator and re-run:

```bash
"$GODOT" --headless --path "$PROJ" --script res://maps/solstice/tools/build_map.gd   # regenerate
"$GODOT" --headless --path "$PROJ" --script res://maps/solstice/tools/validate_map.gd # re-verify
```

`tools/probe_props.gd` prints GLTF prop AABBs (used to size the `PROP_BASE` table). If a sandbox blocks `~/Library` writes (gotcha 10), prefix commands with `HOME=$PROJ/.godot_home`.

## Layout & callouts (x = east, z = north; attackers south / defenders north)

~70×62 m footprint. **Attacker spawn** (south strip) exits to: **A lobby** (SE) → **A main** (long 8 m-wide lane up the east edge), **mid** (central courtyard, fountain block splits the long N–S Operator lane), **B lobby** (SW) → **B main** (long lane, west edge). **Mid doors** (east) → **A link** (L-shape into A site's west door); **market** (west, stall + awnings) → **B site** south door; **mid north door** → **defender link** corridor → **defender spawn** (north strip). **A site** (NE): "generator" metal block (plant cover), crate stack, **A heaven** = 1.5 m wood platform in the NW corner reached by a ramp from defender spawn (through the heaven door — deliberately NO lintel there, platform floor is 1.5 m) and a ramp down into the site. **B site** (NW): double crate stack on the plant zone, 4 m brick back-pillar for wrap-around plays, metal crate at B main door. Attacker→site run ≈ 65 m (~10 s at 6.75 m/s); spawn centroids 53.4 m apart.

- Plant zones: 6×6×2 m Area3D, layer 16/mask 2, translucent fill + emissive yellow frame (green = A, orange = B, matching graybox).
- Buy barriers: 3 attacker (A main entry z=-12, mid top z=-16, B main entry z=-14 — attackers own spawn + both lobbies pre-round), 5 defender (A main door, A link door, mid north door, market door, B main door — defenders own sites + def link). Toggle exactly like graybox.
- Color language: warm plaster + terracotta accents = A side; cool plaster/stone + teal accents = B side; brick + green awnings = mid. Emissive skirting trims point routes to sites; Label3D "A"/"B" signs at every site entrance + painted floor letters on the sites (font: `assets/fonts/Rajdhani-Bold.ttf`).

## Lighting: realtime now, lightmap-ready later

Ships with realtime lighting tuned for Forward Mobile: one warm `DirectionalLight3D` (energy 1.3, shadows on, 2 PSSM splits, 85 m max distance, `BAKE_STATIC`), Poly Haven HDRI sky (`assets/sky/`) driving ambient + reflections, filmic tonemap, subtle glow (intensity 0.45) and very light depth fog (density 0.0016).

A configured `LightmapGI` node (medium quality, 2 bounces, non-directional, 4096 atlas, probes subdiv-8, scene-sky environment) is in the scene and every generated primitive has UV2 (`add_uv2`). **Godot 4.7 has NO script/headless bake API** (`LightmapGI.bake()` doesn't exist outside the editor toolbar — verified; EditorScript CLI runs don't execute either). To bake: open `solstice.tscn` in the editor, select **LightmapGI**, click **Bake Lightmaps** in the 3D toolbar; data saves under `maps/solstice/`, then re-run validate + smoke. Note: the Quaternius GLTF props have no lightmap UV2s (import-setting change would be needed in `assets/`, owned by the asset pipeline) — if the bake ever complains, set their wrappers to dynamic GI; the primitives that form all walls/floors bake fine.

## Perf & structure facts

- 172 MeshInstance3D / 111 unique meshes / 50 unique materials (21 map materials — triplanar world-UV StandardMaterial3D over ambientCG 1K sets, plus ~29 brought in by the CC0 prop imports) / 137 StaticBody3D / 527 nodes. Textures ≤1K except the 2K hero paving floor (per docs/ASSETS.md).
- ALL gameplay cover is primitive boxes/cylinders with exact-size collision (layer 1); CC0 models are scaled to fit INSIDE those colliders, so cover geometry is deterministic even if assets change.
- Group `decor_nocollide` marks intentionally non-solid visuals (trims, hedges, signs, small clutter, water) — validate_map.gd skips them in the "every mesh has collision" audit. Keep using it for future decor.
- Group `ambient_audio`: 4 positioned, autoplay `AudioStreamPlayer3D`s with EMPTY streams (mid fountain, market stall, A generator hum, B wind) — the audio phase just assigns loops (none exist in `assets/audio/` yet; Kenney packs there are one-shots).

---

# Phase 3 additions (Spike mode + agents/abilities)

## Spike round state machine (GameState owns it; server drives, cl_* replicate)

`RoundPhase`: `BUY (30s) → ACTIVE (100s) → [plant] PLANTED (45s) → ROUND_END (7s) → next round`. All transitions happen server-side in `GameState._spike_server_tick()`; every transition broadcasts `cl_phase(phase, time_left, round, score_att, score_def)`. `match_time_left` is reused as "time left in current phase" in Spike mode (cl_time keeps peers corrected every 2 s).

- **Plant**: hold `interact` (clients stream held-state via `srv_interact(bool)`) for 4 s while carrying the spike inside `plant_zone_a/b`, "on ground & mostly stationary" = `observed_velocity < 1.2 m/s` (position-delta based, works for remote nodes where `is_on_floor()` is meaningless). Progress resets fully on release. Plant pays +300 to EVERY attacker immediately.
- **Defuse**: defender within 1.9 m of the spike, same speed gate, 7 s with the 3.5 s checkpoint. The checkpoint locks the moment progress crosses 3.5 and persists for the whole defending team for that round (any defender resumes from 3.5).
- **Win conditions**: elimination (skipped for a side with 0 registered players — degenerate test configs), detonation (attackers, even if all dead — post-plant attacker elimination does NOT end the round), defuse, timeout with no plant (defenders). First to 13 (`--rounds-to-win` overrides); halftime after round 12 (`rounds_to_win - 1`).
- **Halftime**: `_halftime_swap()` flips every `Net.players[*].team`, swaps side-keyed round scores with them (so `score_att` is always "rounds won by current attackers"), resets loss streaks, forces a pistol-round economy/loadout reset. `cl_swap_teams` syncs live player nodes to the registry (never blind-flip: see gotcha 16).
- **Spike lifecycle** (`GameState.spike` dict, `cl_spike`): CARRIED (auto-assigned to a random attacker each round, `--carrier N` forces) → DROPPED on carrier death/disconnect (pickup scan: alive attacker within 1.4 m) → PLANTED → DEFUSED/DETONATED. `scripts/spike_entity.gd` renders it per-peer from replicated state only (carrier back / dropped hover / planted with escalating beeps — `spike_beep.wav`, `spike_beep_fast.wav` under 10 s, pitch-up under 5 s). Detonation: lethal ≤5 m (999), linear 150→50 out to 9 m, both teams, NO line-of-sight check (documented simplification).
- **Economy** (all server-side, replicated via `cl_economy`): 800 pistol rounds, +200/kill, +300/plant (each attacker), +3000/round win, loss streak 1900/2400/2900 (resets on win + at halftime), cap 9000. Survivors keep guns + REMAINING armor; players who died get classic-only next round; bought ability charges persist through death; signature abilities refill to 1 free charge each round. Sell-back not implemented.
- **Shields**: Light 25/400cr, Heavy 50/1000cr. Damage pipeline (`Player._server_damage_core`) has armor absorb `round(damage * 0.66)` capped by remaining armor, with the rest applied to health; effectively +25/+50 EHP. Applies to bullets, abilities and the spike. Glass SFX on armor break.
- **Buys**: `GameState.request_buy("weapon:<id>" | "shield:light|heavy" | "ability:<slot>")` → `srv_buy` validates phase==BUY, credits, ownership/max-charges, then pushes `cl_loadout`/`cl_health`/`cl_charges`. Buy menu (B) opens only during BUY.
- **Freezetime/edge behavior** (pragmatic, crash-free bar): dying during BUY or ROUND_END just leaves you dead until the next round (elimination is only checked during ACTIVE/PLANTED; loadout-loss snapshot happens at round start). Disconnect mid-round: carrier drops the spike; an emptied team forfeits the round immediately and the match ends at the next round boundary if still empty. Late join: `cl_start_match` is NOT resent — the peer loads the match via the normal flow, gets a `cl_sync` state snapshot when ready, spawns live if it's still BUY, otherwise spawns dead ("STANDBY") until next round. Active smokes/walls at join time are NOT resent (they expire within seconds; documented gap).

## Agents & ability framework

- Data: `scripts/agent_data.gd` (AgentData) + `scripts/ability_data.gd` (AbilityData: id/name/desc/cost/max_charges/signature/cooldown/map_targeted/icon_color) as `.tres` in `agents/`; registry `scripts/agent_db.gd` (`AgentDB.ALL/IDS`). Behavior numbers live in `scripts/effects_manager.gd` constants keyed by ability id. Ability slots 0/1/2 bind to `ability_1(Q)/ability_2(E)/ability_3(X)`.
- **Agent → character model mapping** (Quaternius, assets/characters): Gale=`Ninja_Male.gltf`, Ember=`Soldier_Male.gltf`, Warden=`Knight_Male.gltf`, Flint=`Suit_Male.gltf` (Soldier_Female/BlueSoldier spare skins). Selection lives in `Net.players[*].agent` (`srv_set_agent`, duplicates allowed), picked in the lobby, shown in lobby list + scoreboard.
- Cast pipeline: `AbilityController` (node inside player.tscn, so its RPCs follow the Player-node ownership rules): owner input → `srv_cast(slot, origin, dir, target)` → server validates alive/phase/charges → `EffectsManager.server_execute()` → charge consumed + `cl_charges` to owner. Dash/updraft are movement, so after server validation the OWNER applies them locally (`cl_cast_motion`) — movement stays owner-authoritative.
- `EffectsManager` (match.tscn `Effects` node, group `effects_manager`): server owns ALL effect state (projectile authority, fire ticks, wall HP, recon pulses, expiries — all `_physics_process`-driven, no async timers) and broadcasts `cl_spawn/cl_event/cl_end` so every peer builds identical local visuals/collision. Projectiles (`scripts/ability_projectile.gd`) are spawned on every peer with identical params and simulated deterministically; only the server's instance reports back. All effects are cleared at every BUY phase start.
- Zone queries run LOCALLY per peer from the replicated effect list (`slow_mult_for`, `stim_active_for`) because movement is owner-authoritative; the server uses the same queries for fire-rate (stim) and its own players. Smokes are opaque `CULL_DISABLED` spheres (identical for all peers, occlude nametags via normal depth-testing) and block flash/recon line-of-sight checks (`_smoke_blocks`).
- Friend/foe conventions (documented choices): flashes + concusses affect allies too; molly damages enemies at ~8 dps (0.5 s ticks of 4), allies half; slow orb slows everyone; stim buffs the caster's team only (+15% fire rate & speed); heal restores 100 hp over 5 s, including self-heal; wall = 4 × (1.25×2.5 m) segments, 400 hp each, layer 1 (blocks movement locally on every peer + bullets on the server via `WallSegment.server_bullet_hit`), placement denied if it would trap a player. Recon: 2 pulses 1.5 s apart, enemies ≤15 m with world+smoke LOS get a through-wall outline (no-depth-test overlay) for 2 s; dummies (`dummy_targets` group) are pingable for tests. Concuss: 65% slow + `+3°` spread + no ADS for 4 s (server enforces ADS/spread; owner mirrors).
- Ember Sky Smokes use a schematic top-down overlay (`scripts/ui/smoke_target_overlay.gd`): map bounds scanned from MapRoot mesh AABBs, plant zones/allies/range ring drawn, click-to-place within 50 m; smoke lands after 1 s.
- Remote players render a third-person gun (`Player._update_tp_gun`) from `sync_slot` + replicated loadout ids — reading Operators works.

## Team size + lobby

`Net.lobby_team_size` (host-set via `set_lobby_team_size`, replicated via `cl_lobby_cfg`) is enforced server-side: `srv_set_team` denies switching into a full team (`cl_denied` → lobby toast), auto-balance respects the cap, and a join is refused (message + disconnect) when both sides are full. `--team attacker|defender` is a join-time preference.

## New CLI flags (Phase 3; parse in scripts/cli.gd)

`--mode <tdm|spike>` (autostart mode), `--spike-fast` (buy 3 s / live 20 s / detonate 15 s / round-end 2 s; plant/defuse/checkpoint stay REAL at 4/7/3.5 s), `--buy-time/--live-time/--detonate-time N`, `--rounds-to-win N`, `--carrier <peer>`, `--team <attacker|defender>`, `--agent <id>`, `--spike-script <a|b>` (scripted scenarios in `scripts/spike_test_hooks.gd`).

```bash
# spike-mode automated test (2 scenarios × host+client, 66 assertions):
bash tests/spike_test.sh                 # logs in tests/logs/spike_*.log
# quick manual spike match on desktop:
"$GODOT" --path "$PROJ" -- --host --map graybox --mode spike --start-when 2
"$GODOT" --path "$PROJ" -- --join 127.0.0.1 --agent ember
```

## Phase 3 gotchas

14. **MultiplayerSpawner spawn state is NOT applied on the peer that owns the node's synchronizer.** The owning client's copy of its own player node kept default exports (name "Player", team 1, position origin) — latent since Phase 2. Fix: the server sends `cl_identity(...)` to the owner right after spawning (match.gd). If you add spawn-replicated identity fields, extend `cl_identity` too.
15. Late-join safety: `MoveSync.public_visibility=false` in player.tscn; the SERVER opens per-peer visibility (`set_visibility_for`) only for peers that reported `srv_client_ready`, so spawner packets never race a peer's scene load. Owning CLIENTS set their own `public_visibility=true` in `_enter_tree` (they must broadcast movement). Keep this pattern for any new spawnable scene.
16. **ENet client peer ids are RANDOM ints** (e.g. 1519525372), not 2/3/4 — never hardcode client ids in tests/logic; the host is always 1. Test patterns use `peer=[0-9]{2,}` to mean "some client".
17. `Area3D.overlaps_body()` needs a physics frame after a teleport — scripted plant/defuse tests wait ~0.3 s after warping before holding interact.
18. Script-class typed arrays in hand-written `.tres` are fragile; `AgentData.abilities` is a plain untyped `Array` on purpose (elements still get the AbilityData script via `SubResource`).
19. Ogg loops: `.loop` must be set at runtime on a `duplicate()` of the loaded stream (import defaults are non-looping and the resource is shared) — see the molly fire loop. EXCEPTION: the ambient loops in `assets/audio/ambient/` have `loop=true` set in their `.import` files instead, so the shared imported resource loops everywhere (used by the generated Solstice scene).
20. GameState round logic never touches scene nodes directly except through `get_tree().current_scene.pick_spawn(team, idx)` (match.gd public API) and the `players` group — keep that contract if the match scene is restructured.

---

# Phase 4 additions (mobile UX, perf, ship)

## Touch input architecture

- `Settings.touch_enabled()`: AUTO (on for `OS.has_feature("mobile")`), forced ON/OFF via Settings menu, or `--touch` CLI flag for desktop testing. `Settings.gameplay_input_active()` is the unified "is gameplay input live" gate (mouse capture on desktop, `touch_block_gameplay` — maintained by the HUD from `modal_ui_open()` — on touch); WeaponManager/AbilityController use it instead of checking mouse capture.
- `TouchControls` (`scripts/ui/touch_controls.gd`, child of HUD): floating left-zone joystick (deflection < 0.55 = walk), right-zone drag aim (`AIM_DEG_PER_PX * touch_sensitivity`, FOV-ratio + `ads_sensitivity_scale` while ADS), dual FIRE buttons, ADS/BURST/ZOOM context button, jump, crouch toggle, reload, weapon-cycle, 3 ability buttons with charge pips + `icon_color` rings, contextual PLANT/DEFUSE hold button, BUY (buy phase only), SCORE toggle, pause. All buttons synthesize the existing input actions via `Input.action_press/release`; the joystick writes `Player.touch_move/touch_walk` (read by `Player.move_input()`).
- With touch enabled, Settings strips the mouse-button bindings from `fire`/`ads` (restores them if touch is turned off) so Android's emulated-mouse-from-touch can't fire the gun through GUI taps. Display: 1280x720 base, `canvas_items` stretch + `expand` aspect (2400x1080 phone = 1600x720 logical), `sensor_landscape` lock, `emulate_touch_from_mouse` on for desktop testing.
- Weapon alt-fire (the ADS input): `WeaponData.alt_burst_count>1` = Classic 3-round burst (client `_tick_burst`, server validates per-round burst timing at 70% interval, `srv_fire`'s trailing `alt` arg); `ads_zoom_2>0` = Operator zoom stages (press cycles hip/2.5x/5x). Touch always uses toggle-ADS.
- Dead players in Spike get a simple chase-cam spectate of a living teammate (HUD `_tick_spectate`); `cl_round_spawn/cl_respawn` re-`make_current()` the player camera.
- Footsteps: `Player._tick_footsteps` — louder when running (h-speed > 4.2 m/s), silent when walking/crouching (competitive-gameplay critical), concrete set only, works for local + remote via `observed_velocity`.

## Dev/verification CLI (Phase 4; parse in scripts/cli.gd)

`--touch` (force touch UI), `--screenshot <path>` + `--shot-delay N` + `--shot-in-match` + `--shot-ui buy|score` + `--shot-weapon <id>` + `--shot-stay` (ScreenshotProbe, prints `[SHOT] draw_calls=...`), `--touch-selftest` (injects synthetic ScreenTouch/Drag events; asserts joystick/aim/fire/crouch/jump all work — see `[TOUCHTEST]` lines).

```bash
bash tests/screenshot_pass.sh 2400x1080         # windowed screenshot batch -> builds/screenshots/
bash tests/three_instance_solstice_test.sh      # 3-player spike round on the real map
```

## Ship facts

- Icons: SVG sources (`icon.svg`, `assets/icons/icon_{fg,bg,mono}.svg`) rasterized by `tools/make_icons.gd` into the PNGs referenced by the Android preset (launcher + adaptive). Boot splash = flat `#0b0f17`, no image.
- Export excludes (preset `Android`): docs/, tests/, tools/, maps/*/tools/, builds/, assets/icons/, *.md, unused fonts (Rajdhani-Regular/Medium) and unused character models (UAL1, Enemy, Hazmat, Soldier_Female, BlueSoldier). Godot 4.7 embeds a SPARSE pck (`assets/` entries inside the APK), so `unzip -l` can audit the shipped file list directly.
- Perf: 60fps cap, MSAA 2x, mobile shadow overrides (2048 directional/positional atlas), `Settings.resolution_scale` (0.7-1.0, default 0.85 on Android) applied to `viewport.scaling_3d_scale`. Solstice in-match: ~350-420 draw calls / ~55K primitives with HUD.

## Phase 4 gotchas

21. **`set_anchors_preset(...)` on a Control that is ALREADY inside a sized parent keeps its current (usually 0x0) rect** by writing compensating offsets — controls that set their own anchors in `_ready` (after `add_child`) silently collapse; the same call on a parentless control zeroes offsets and works. This broke the buy menu/scoreboard (latent since Phase 3) and the touch layer. Always use `UiUtil.full_rect()` / `UiUtil.center()` (explicit anchors + offsets), never preset-then-`position`.
22. The agent sandbox blocks UDP even on loopback (`enet_socket_send` "Sending failed!") — run any test that hosts/joins with network permissions. Export/adb also need the REAL `$HOME` (the `.godot_home` redirect has no Android templates or SDK editor settings).
23. Adding a new `class_name` script requires a `--import` pass before headless/CLI runs see it (global class cache), or every script referencing it fails to parse.
24. zsh does not word-split unquoted variables — `$args` passed to Godot becomes ONE argument (flags silently ignored). Use bash for test scripts or `${=args}`.
25. GPU-less emulator images (Android ATD, SwiftShader) boot the game fine but spam "Couldn't present to Vulkan queue (VkResult error 5)" — emulator artifact, not an app bug; verify rendering on a real phone or a GPU-enabled AVD.
26. Godot's `monkey`-style launch fails (no MONKEY category); use `adb shell am start -n io.github.daksh_mor.valu/com.godot.game.GodotAppLauncher` (the `GodotApp` activity itself is not exported).
