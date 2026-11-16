# RIFTOPS

**An offline-first multiplayer FPS for Android and desktop.** RIFTOPS builds on Valu's Godot and ENet LAN foundation: one player hosts the match, and others connect over the same local Wi-Fi network. A mobile hotspot can provide that network without mobile data or an internet connection.

> **Project status:** RIFTOPS is in development. The repository currently contains Valu's playable foundation. Free For All is the planned primary mode, and TESTSITE-07 is the planned original suburban arena. Neither has been implemented yet. See the [development roadmap](DEVELOPMENT_ROADMAP.md) for scope and status.

## What works in the current project

- Godot 4.7.1, written in GDScript.
- ENet host and client sessions over local networks; the host also plays.
- LAN room discovery over UDP, with manual IP joining as a fallback.
- Host-authoritative weapon damage, health, deaths and match state.
- Existing Spike and team deathmatch modes, seven weapon definitions, four agents and their abilities.
- Two bundled maps: Solstice and Graybox.
- Mobile touch controls and desktop keyboard/mouse controls.

These are features found in the project and tested to the extent described in the [baseline validation report](docs/BASELINE_VALIDATION.md). Automated loopback tests do not certify phone-to-phone hotspot play or Android performance.

## Run on Windows desktop

1. Install the standard Godot **4.7.1** editor from the [official download archive](https://godotengine.org/download/archive/4.7.1-stable/).
2. Open `project.godot` from this folder in Godot and press **F6** to run the main project.
3. To try a two-instance local match, open two PowerShell windows. Replace the example executable path with the location of your Godot console executable.

Host a Solstice Spike match in the first window:

```powershell
& "C:\Godot\Godot_v4.7.1-stable_win64_console.exe" --path "$PWD" -- --host --map solstice --mode spike --start-when 2
```

Join from the second window:

```powershell
& "C:\Godot\Godot_v4.7.1-stable_win64_console.exe" --path "$PWD" -- --join 127.0.0.1
```

The host waits for a second player before starting. For touch controls in a desktop test, add `--touch` after the `--` separator.

## Play over a local network

1. Install the same game build on each device.
2. Connect the devices to the same Wi-Fi network, or connect them to one Android phone's hotspot. Mobile data is not required for the hotspot match.
3. On the host phone, start the game and choose **Host Game**.
4. On other phones, choose **Join Game** and select the discovered room. If discovery is unavailable on that network, enter the host's local IP address.

Game traffic uses UDP port `27015`; LAN discovery uses UDP port `27016`. Network isolation or firewall settings can block discovery, so manual IP joining is the fallback. See [Play on LAN](docs/PLAY_ON_LAN.md) for more troubleshooting.

## Android build status

The Android export preset is present, but this checkout has **not produced a verified Android APK**. The baseline export attempt could not find the matching Godot export templates, JDK 17, or Android SDK tools. The preset also references launcher icon files that are missing from the project. Follow the [baseline validation report](docs/BASELINE_VALIDATION.md) before attempting an Android export; do not use the old Valu release link as a RIFTOPS download.

The inherited Android package identifier is still `io.github.daksh_mor.valu` so a future RIFTOPS build can retain installation upgrade compatibility. Choose a new identifier only when preparing a release and handling existing installations deliberately.

## Run the existing multiplayer checks

The test scripts use Bash and Godot 4.7.1. From Git Bash on Windows, set `GODOT` to the console executable and run:

```bash
export GODOT='/c/Godot/Godot_v4.7.1-stable_win64_console.exe'
bash tests/two_instance_test.sh
bash tests/spike_test.sh
bash tests/three_instance_solstice_test.sh
```

These scripts start local headless host/client processes and verify scripted match flows. The three existing suites passed during the recorded baseline run. The Spike ability suite also reports shutdown resource-leak diagnostics; details and limits are in the [validation report](docs/BASELINE_VALIDATION.md).

## Project docs

- [Architecture audit](ARCHITECTURE_AUDIT.md)
- [Existing features](EXISTING_FEATURES.md)
- [Technical debt](TECHNICAL_DEBT.md)
- [Development roadmap](DEVELOPMENT_ROADMAP.md)
- [Baseline validation](docs/BASELINE_VALIDATION.md)
- [LAN setup](docs/PLAY_ON_LAN.md)
- [Asset sources and licenses](docs/ASSETS.md)
- [Third-party credits](CREDITS.md)

## License and asset notices

The root `LICENSE` file has been removed at the project owner's request. Bundled third-party assets remain subject to their own terms and attribution requirements; see [CREDITS.md](CREDITS.md), [the asset manifest](docs/ASSETS.md), and the license files beside the assets. Removing the root file does not change or revoke license grants made in earlier Valu releases.
