# RIFTOPS incremental development roadmap

2026-11-16. Product: locally bundled, original Android FPS; a participating Android host on a data-disabled hotspot remains the authoritative damage server. Retain Godot 4.7.1/GDScript/ENet. No cloud login, backend or runtime asset downloads.

## Confirmed product priorities

- **Primary experience: Free For All on TESTSITE-07.** Once implemented and tested, this is the default room configuration and main Play flow. Legacy Spike/TDM remain regression coverage, not competing development priorities. Do not expose a nonfunctional FFA option before the rules exist.
- The user's Nuketown reference defines compact suburban combat, frequent encounters, houses, street cover and flanking routes. Retain the original brief's requirement for an original layout/assets/identity rather than an exact Nuketown recreation. TESTSITE-07 remains the working map name.
- **Broad Android compatibility, not a phone-model whitelist.** Use responsive landscape layouts, safe areas, adjustable input and low/medium/high quality settings. Target 60 FPS on capable hardware and a 30 FPS fallback on lower-end supported hardware. Establish minimum Android version, CPU ABI, GPU/API and memory requirements from the actual engine/export and measurements; do not promise every Android phone can run the game. Review the inherited ARM64-only/Vulkan Mobile baseline and evaluate renderer/ABI alternatives before excluding otherwise viable devices.
- Device testing samples hardware classes and GPU vendors; it does not restrict the supported models to those tested. Include lower-end and capable phones, different aspect ratios and Android versions, with both host and client roles. No specific physical devices have yet been supplied.
- User reports no known installed Android SDK or export templates. Treat toolchain provisioning as a fresh setup, including matching Godot templates, JDK 17 and Android SDK tools. No existing installation paths are assumed.

## Delivery policy

Each increment must identify changed paths, preserve a recoverable prior build, pass import/boot and relevant regression tests, and record device-only checks separately. Keep failed gates visible. Do not call placeholders final art or a loopback test hotspot certification. Complete one FFA vertical slice before adding modes or weapon breadth.

## Milestone 0 — audited, reproducible baseline

Deliverables: `ARCHITECTURE_AUDIT.md`, `EXISTING_FEATURES.md`, `TECHNICAL_DEBT.md`, this roadmap and `docs/BASELINE_VALIDATION.md`.

1. Reconcile misplaced Git metadata with the parent source; compare bytes to HEAD before any repair. Recover the exact missing LICENSE. Preserve a snapshot.
2. Import using the pinned engine; run boot and both map smoke checks, Solstice validator, two-instance, Spike and three-instance tests. Capture command, version, exit code and log for each.
3. Restore/create the missing adaptive SVG inputs before generating launcher PNGs; obtain matching templates/JDK17/Android SDK, export a baseline APK and record SHA-256/signing identity without credentials.
4. Two phones, mobile data disabled: launch, discover, manual join, host participation, kill/respawn, finish/rematch, client leave, host leave. Record device/Android/GPU and app version.
5. Explain the unseen-map observation using explicit map paths and APK logs. Current source shows maps present; historical APK cause remains unknown.

Gate: desktop baseline passes; Android baseline is explicitly recorded as passed or blocked with reasons. No broad presentation replacement while unexplained baseline failures remain.

## Milestone 1 — frontend and design system

### Art direction

Original test-facility identity: graphite surfaces, warm ivory text, restrained safety-orange action accents, cool cyan connection feedback. Keep readable text and large touch targets; do not communicate connection solely by color. Use bundled Rajdhani initially with its OFL notice. Target 1280x720 logical layout, 16:9/18:9/20:9 landscape and notch-safe boundaries. Main action minimum 56 logical pixels; avoid tiny hover-only explanations. Use subtle short transitions with reduced-motion support, not expensive live menu rendering by default.

### Ordered implementation slices

1. Add shared `ui/theme/` resources and reusable button/panel/status components in `scenes/ui/components/`, with focused scripts under `scripts/ui/components/`. No transport changes.
2. Rebuild `main_menu.tscn` and `main_menu.gd` using containers. Play routes to host/join choice; Create Room routes to actual host setup; Join Room retains discovery and manual IP. Game Modes shows implemented modes truthfully; Profile edits local identity; Settings preserves existing keys.
3. Split settings UI out of `main_menu.gd`; add input, graphics, audio and credits sections with persist/reset semantics. Keep settings save compatible and verify after restart.
4. Rebuild lobby presentation behind existing host/join/leave signals. Show host, actual connected players/capacity, addresses and connection state. Retain agent/loadout and both legacy modes while regression testing.
5. Add real room name, ready status and replicated match settings as a separately reviewed protocol increment in `net.gd` and a small lobby-state module. Validate lengths/capacity/host ownership; clear readiness after settings changes. Never display fabricated ready states or internet-resolvable room codes.
6. Add local avatar choice from bundled original icons, status/error/empty states and transition polish. Protocol compatibility identifiers come before mixed-build sessions.

Validation: menu navigation, bad IP, canceled join, bind failure, stale discovery, room full, duplicate registration, disconnect, settings persistence, keyboard/gamepad focus if supported, multi-aspect screenshots and two-instance/Spike regressions. Confirm no RPC node path changes. Device check: keyboard, safe areas, tap targets, hotspot discovery and manual join.

## Milestone 2 — TESTSITE-07

Add `maps/testsite_07/testsite_07.tscn`, explicit map metadata and a contract validator. Original asymmetric suburban testing compound: staggered two-house footprints, offset street, central maintenance shelter/vehicle cover, backyard loops and side passages. Avoid a recognizable recreation of the reference map.

Design steps: annotated route/sightline plan → traversal/collision prototype → network spawn/geometry validation → authored buildings and props → materials/lighting → device profile. Prototype geometry stays marked development-only and cannot satisfy the final-art gate.

Separate static collision from decorative detail. Add multiple entrances and bounded upper-floor positions, cover across long sightlines, blocked views between initial spawn areas, and FFA spawn markers distributed across routes. Retain existing team markers for regression matches before M4. No per-client random collision geometry. Add map/content identifier to match configuration.

Acceptance: every interior/route traversable; no gaps/fall-through/spawn trapping; identical collision on all peers; no unavoidable spawn sightline; no missing resources; real geometry/materials replace prototype art. Keep Graybox and Solstice selectable for diagnostics. Benchmark draw calls, triangles, GPU/CPU frame time, memory and loading on phone; actual budgets follow measurement.

## Milestone 3 — one excellent rifle and character set

Create original scoped asset briefs and a provenance ledger before acquisition. New assets in `assets/riftops/characters/`, `weapons/`, `animations/` and `audio/`, with source files, export settings, LOD/collision notes and licenses. Prioritize one rifle, rigged first-person arms, readable third-person silhouette and at least two distinguishable appearances.

Keep `WeaponData` damage/cadence contract and server raycasts stable. Separate presentation pivots and animation states from combat. Introduce animation presenter modules instead of extending `player.gd`. Implement walk/run/jump/fire/reload/death/respawn with correct interruption and authoritative action cues. Add bounded muzzle/impact/casing/audio effects with distance/quality limits.

Acceptance: all art loads and is licensed; hands align through ADS/reload; camera does not clip; remote action states agree with host; client rejection corrects presentation; repeated fire/death/respawn does not leak nodes; legacy combat tests pass. Phone check: responsiveness, silhouettes, audio mix and sustained combat FPS.

## Milestone 4 — authoritative FFA vertical slice

Add a focused FFA rule module under `scripts/modes/`, with GameState dispatching mode lifecycle rather than another monolithic branch. Keep stable legacy enum values. Add host-owned configurable capacity, duration and kill limit, countdown, elapsed time, per-player kills/deaths, feed, respawn and final result snapshot. Define tie behavior and zero-death K/D display explicitly.

Dependencies: team damage gate in `player.gd`, team assignment/capacity in Net, respawns in `match.gd`, mode-specific weapon defaults, HUD/scoreboard/result presentation. FFA players must be individually hostile even if old team metadata exists. Match end must run once, freeze scoring, preserve results across departures and return everyone to the same live lobby.

Host chooses respawn from valid markers using occupancy, opponent distance, LOS and recent-use penalties; client never chooses its own spawn. Add deliberate protection behavior only with clear UI and server rules.

Tests: two/three peers, self/environment kill, simultaneous lethal hits, limit/time tie, duplicate death, score replication, late join/countdown, disconnected leader, host loss, respawn interruption, rematch. Verify both host and remote player can win. No teams in FFA UI or scoring. Run old-mode regression suites.

## Milestone 5 — polish and measured mobile performance

Add configurable controls/sprint, layout reset, audio mixing, graphics tiers and 30/60 FPS choice. Keep same input actions and host combat. Audit multi-finger aim/move/fire/jump/reload and modal input cancellation. Use instancing for repeated props and pools for measured hot spots; do not optimize by compromising authoritative state.

Profile at least a lower-end and capable ARM64 phone with host and client roles. Record CPU/GPU frame-time distributions, memory, temperature/throttling, draw calls, triangles, packets/bytes per second, battery trend and load time during sustained maximum-player action. Target 16.7 ms at 60 FPS or 33.3 ms at 30 FPS; these are targets, not results. Adjust shadow ranges, render scale, texture/LOD/effect limits based on measurements.

Acceptance: cohesive final art/UI, no placeholders, readable HUD, no input starvation, stable repeated matches and documented performance settings per device. Test phone background/foreground, Wi-Fi changes and interrupted host.

## Milestone 6 — release candidate

Rebrand project/export/store identity without removing Valu notices; select a stable RIFTOPS application ID and establish owner-controlled signing securely. Bundle license notices and all essential assets. Produce versioned APK, hashes, install guide, LAN troubleshooting and release notes.

Release gates: clean import/export; no errors or missing assets; verified APK signature; offline first launch after installation; 2+ Android devices on data-disabled hotspot with no laptop; discovery and manual join; complete FFA/rematch; host/client disconnections; device performance/thermal matrix; asset license review; fresh-install and upgrade settings behavior. Archive source revision, engine/template/SDK versions, APK and test evidence. No claim of commercial readiness until these gates pass.

## Milestone report template

- Implemented behavior and deliberate scope.
- Files created/modified; resource/protocol migrations.
- Existing behavior preserved, with evidence.
- Tests: commands, versions, results and logs.
- Build artifact, hash and signing status (no secrets).
- Known defects and blocked gates.
- Outstanding physical Android tests and device matrix.
