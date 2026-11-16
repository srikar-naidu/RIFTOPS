# Technical debt and release risks

2026-11-16. P0 = baseline/release blocker; P1 = correctness or core-product risk; P2 = quality/performance debt. Findings are source-supported unless explicitly marked hypothesis. Fixes are proposed, not silently applied.

| Priority | Finding and evidence | Consequence | Bounded remedy and verification |
|---|---|---|---|
| P0 | Git worktree separated from `valu/.git`; 707 tracked paths reported deleted there | Unsafe reset/clean; no reliable root diff | Reconcile copy against HEAD, archive initial hashes, establish root worktree deliberately |
| Resolved | Root `LICENSE` initially absent; tracked in HEAD, linked from README/CREDITS | Incomplete upstream notice | Restored exact blob `eee0a0abb53a8bc8a5f9ddb10464e9451947b564`; all third-party notices retained |
| P0 | Four launcher PNGs referenced in `export_presets.cfg` and three generator SVG inputs absent | Export cannot be assumed valid | Restore/create licensed adaptive SVG inputs, then run `tools/make_icons.gd`, import and verify export |
| P0 | No verified local Android templates/SDK/JDK17 or APK | Android build status unproven | Install pinned toolchain, export debug APK, inspect manifest, verify signature/install |
| P1 | Owning client controls MoveSync position; `player.gd::_enter_tree`, `_physics_process` | Host damage validation cannot prove legal movement | Add bounded motion checks with explicit teleport/respawn exceptions; test host/client movement and lag |
| P1 | `_server_fire` trusts airborne/crouch/speed/ADS flags and allows origin within 3m | Accuracy/origin exploitation possible | Derive verifiable flags from host state, finite-vector checks and tighter tested origin policy |
| P1 | In-match scene has no connection to `Net.disconnected_from_server`; boot owns it | Host loss may leave clients stranded | Persistent disconnect coordinator; test host termination during lobby/live/results |
| P1 | `server_report_kill` returns in TDM before individual stats | Scoreboard individual K/D stays default in TDM; unusable base for FFA stats | Separate common stats from mode scoring; death/kill/disconnect/tie tests |
| P1 | `_mark_ready` records sender without checking `Net.players` or duplicate-ready intent | Readiness RPC can trigger invalid/default spawn or repeated late-join initialization | Require registered peer and idempotent scene-ready token; rejection tests |
| P1 | No match content/protocol handshake; discovery GAME_ID remains `valu` | Incompatible builds can discover/connect | Versioned handshake with map/content identifier; reject with clear message, keep ENet |
| P1 | Lobby map/mode selection not continuously replicated; ready state absent | Clients cannot confirm shared settings before start | Host-owned lobby settings revision and ready invalidation, independently tested |
| P1 | Discovery max always 10; manual/discovered join UI emits only IP | Capacity misleading; custom-port host discovery cannot join correctly | Display configured capacity and pass port through frontend contract |
| P1 | Active effects missing from late-join snapshot, `effects_manager.gd` | Different visible/collidable temporary world | Snapshot server effects with remaining lifetime before player enable; compare peers |
| P1 | `match.gd` continues after map load failure, spawns default at origin if no markers | Empty/unplayable match instead of actionable error | Validate map resource/contract before start and return room error on failure |
| P1 | No user-ready match countdown or FFA safe spawn selection | Requested FFA behavior absent | Dedicated FFA rules and host-selected scored spawns; LOS/proximity tests |
| P2 | `player.gd` 1109 lines; GameState 1072; effects 779; HUD 741 | Broad change surface and coupled concerns | Extract one tested responsibility at a time, preserve RPC node paths |
| P2 | Third-person animation Idle/Run; fixed gun mount; capsule corpse | Limited combat readability | Animation presenter driven by approved state, bone attachment and authored death |
| P2 | `WeaponView.play_reload` tween and `_process` both write rotation.x | Competing animation writers, suspect reload presentation | Dedicated animation pivot; verify firing/reload/equip interruption visually |
| P2 | Map selection scans directories; default/ordering implicit | Graybox can appear despite Solstice being present | Explicit map catalog with deterministic default and exported-build test |
| P2 | Solstice LightmapGI has no baked data; 85m shadow range | Lighting/performance budget uncertain | Bake/measure supported solution; profile mobile renderer and thermal runs |
| P2 | Per-shot transient node/material/audio creation in `fx.gd` | Allocation spikes under sustained combat | Profile then pool bounded cosmetic effects; never let pool affect damage |
| P2 | Fixed-size UI panels and many independent font/color constants | Narrow-screen clipping and inconsistent styling | Shared theme, containers, scroll panels, safe-area layouts, screenshot matrix |
| P2 | Touch layout fixed; no configurable sprint/control editor | Requested mobile controls incomplete | Persist layout presets with reset and multi-finger cancellation tests |
| P2 | Spike explosion lacks LOS filtering (documented and implemented radius behavior) | Blast passes through cover | Preserve until design decision; test explicitly if behavior changes |
| P2 | License manifest is documentation, not per-file verified release ledger | Attribution/package omissions possible | Record per-asset source/license/hash/use; include notices in app and APK |
| P2 | Spike ability test exits with 6 leaked ObjectDB instances / 3 resources in use despite functional suite success | Baseline is not free of lifecycle diagnostics | Reproduce with `--verbose`, identify surviving effect/audio/timer resources; distinguish test teardown from repeated-match leak before fixing |

## Test limitations

Current shell suites exercise scripted scenarios, often server-injected actions and teleports. They do not prove ordinary remote-player fire validation, hostile RPC safety, LAN discovery across hotspot devices, phone suspend/resume, or rendering performance. Keep their value as regression checks while adding end-to-end human-input and device coverage. Do not rewrite transport in response to these gaps.
