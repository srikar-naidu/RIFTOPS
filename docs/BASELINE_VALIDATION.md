# Baseline validation record

Date: 2026-11-16. Source root: `D:/personal projects/RIFTOPS`. Test copy: `builds/audit-baseline`. Original gameplay, networking, scene, resource and export files were not edited. LICENSE was subsequently recovered exactly from Git HEAD. This record does not assert a finished RIFTOPS milestone or Android readiness.

## Engine and reproducible commands

Official Windows editor downloaded from the Godot GitHub 4.7.1-stable release. Executable reports `4.7.1.stable.official.a13da4feb`.

```powershell
$godot = 'C:/Users/pjnai/AppData/Local/Temp/riftops-godot-baseline/Godot_v4.7.1-stable_win64_console.exe'
$baseline = 'D:/personal projects/RIFTOPS/builds/audit-baseline'
& $godot --version
& $godot --headless --path $baseline --import
& $godot --headless --path $baseline --quit-after 3
& $godot --headless --path $baseline --script res://maps/solstice/tools/validate_map.gd
```

For existing tests, set `GODOT` to this executable, change to the baseline directory, then run each suite with Git Bash (`C:/Program Files/Git/bin/bash.exe`). They create `tests/logs` inside the copy. Run sequentially because they use the same default game port.

## Results

| Check | Result | Evidence |
|---|---|---|
| Source inventory / tracked-path comparison | 707 tracked paths; only LICENSE absent initially | `git -C valu ls-tree -r --name-only HEAD`; parent path existence comparison |
| glTF external dependency check | PASS, all 85 parsed; no missing external buffer/image URI | PowerShell JSON parse and relative-file existence scan |
| Literal resource-path scan | No missing literal runtime resources found; icon generator inputs/outputs absent | `.gd`, `.tscn`, `.tres`, project configuration scan; dynamic paths require runtime coverage |
| Initial sandbox import | Imports completed, but user/editor directory permission errors | `builds/baseline-import.log`; not a clean pass |
| Initial sandbox boot | FAIL: data/log directory creation denied, engine crash | `builds/baseline-boot.log`; environment failure, not attributed to gameplay |
| Import with normal directory access | PASS, exit 0; no ERROR/SCRIPT ERROR matches | `builds/baseline-import-retry.log` |
| Boot after completed import | PASS, exit 0; no script/scene errors logged | `builds/baseline-boot-retry.log` |
| Solstice map validator | PASS, exit 0 | `builds/baseline-map-validation.log` |
| Two-instance suite | PASS, host/client exit 0 | `builds/baseline-two-instance.log`, baseline `tests/logs/host.log` and `client.log` |
| Spike suite | Functional assertions PASS; teardown diagnostics require follow-up | `builds/baseline-spike.log`; baseline `tests/logs/spike_b_host.log` |
| Three-instance Solstice | PASS, host and both clients exit 0 | `builds/baseline-three-instance.log`, baseline `tests/logs/solstice3_*.log` |
| Android debug export | FAIL, exit 1; no APK produced | `builds/baseline-android-export.log` |
| Physical Android / data-disabled hotspot | NOT RUN | No device session available |
| Visual screenshot/renderer/performance | NOT RUN | Headless tests are not visual or FPS tests |

Solstice validator reports 528 nodes, 172 MeshInstance3D nodes, 111 unique meshes, 50 unique materials and 137 StaticBody3D nodes. These are scene inventory counts, not measured draw calls. It passed team spawn count/orientation/separation, zones, buy barriers, world collision, sunlight, environment, LightmapGI presence and ambient audio checks. LightmapGI presence does not prove baked data exists.

The two-instance suite establishes actual local ENet connection, two replicated player nodes, host-side dummy damage and kill-feed delivery to both peers. It does not establish Android LAN discovery, two real players' complete movement/fire behavior, packet-loss tolerance or Wi-Fi hotspot support.

Spike scenario B reports six leaked ObjectDB instances and three resources still in use on host exit, and ten instances/five resources on client exit. The functional suite passes, but this is not a clean lifecycle pass. Diagnose with verbose teardown logging before claiming the baseline has no runtime diagnostics. These warnings were observed before any game-code edits.

`builds/.gdignore` prevents Godot from importing the audit copy as duplicate project classes when opening the root project. The audit copy can still be opened as its own project. Source-hash comparison after the tests found no changes to the 57 recorded source/resource files.

## Android export failure details

Command: pinned Godot `--headless --path <baseline> --export-debug Android D:/personal projects/RIFTOPS/builds/Valu-baseline-debug.apk`.

Exporter reports missing `4.7.1.stable/android_debug.apk` and `android_release.apk` templates, no valid Java SDK path, and missing Android platform-tools/adb and build-tools/apksigner paths. Missing launcher icon resources were independently identified by the audit; toolchain failure occurs before a complete export can establish further issues. No APK or signing success is claimed.

User follow-up confirms no known prior Android SDK/templates installation; provision a fresh toolchain. The requested support scope is broad Android hardware, not specific named phones. Physical models remain unspecified, and representative-device testing is still required to establish minimum requirements and performance rather than to define a model whitelist. FFA on the original Nuketown-inspired TESTSITE-07 arena is the confirmed primary experience.

## Gates before UI replacement

All three existing functional suites passed. Investigate the Spike teardown diagnostics without broad refactoring, repair packaging inputs, configure the Android toolchain and produce a baseline artifact. Keep Git metadata repair independent from game changes. Physical phone verification remains mandatory before claiming offline mobile play or 60/30 FPS.

## Milestone 0 handoff

- Delivered the four requested audit/roadmap documents, this validation record and source-hash inventory.
- Restored `LICENSE` exactly from upstream; no existing game scripts, scenes, assets, network protocol or export configuration changed.
- Preserved and tested the existing ENet implementation in an isolated copy. Actual functional loopback suites passed, including Solstice plant/defuse/detonation with three peers.
- Android export remains blocked by toolchain setup, and packaging icon sources remain incomplete. No APK was produced.
- Milestone 1 implementation has not started: baseline release/build gates and lifecycle diagnostics remain unresolved. Its component boundaries, screen behavior, integration order and acceptance checks are specified in `DEVELOPMENT_ROADMAP.md`.
- Required physical checks: offline first launch, mobile-data-disabled hotspot discovery/manual join, participating host combat, remote combat/respawn/results/rematch, disconnect/recovery, multitouch/safe areas and sustained thermal/performance testing.
