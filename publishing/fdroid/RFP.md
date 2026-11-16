# Request for Packaging

## Issue title

New App: Valu (io.github.daksh_mor.valu)

## Issue body

Copy the following into a new issue at <https://gitlab.com/fdroid/rfp/-/issues/new>
after the public `v1.0.0` tag is available:

````markdown
* [x] The app complies with the [inclusion criteria](https://f-droid.org/docs/Inclusion_Policy/?title=Inclusion_Policy).
* [x] The app is not already listed in the repo or issue tracker.
* [x] The app has not already been requested.
* [x] The upstream source repository contains Fastlane metadata, images, and a version-code changelog.
* [x] The original app author has been notified; I am the upstream author.
* [ ] Optionally donated to support F-Droid.

#### APPLICATION ID: io.github.daksh_mor.valu

```yaml
Categories:
  - Shooter Game
License: MIT
AuthorName: Daksh Mor
AuthorWebSite: https://github.com/daksh-mor
WebSite: https://github.com/daksh-mor/valu
SourceCode: https://github.com/daksh-mor/valu
IssueTracker: https://github.com/daksh-mor/valu/issues
Changelog: https://github.com/daksh-mor/valu/releases
AutoName: Valu
RepoType: git
Repo: https://github.com/daksh-mor/valu.git
```

Why do you want this app added to F-Droid:

Valu is a privacy-respecting game that works without an account or hosted
service and can be built entirely from source.

Summary:

Original tactical FPS with LAN-only multiplayer

Description:

Valu is an original tactical first-person shooter built for team play on a
local network.

Players host a match or join another device on the same Wi-Fi or LAN. The game
offers objective-based rounds and team deathmatch, distinct combat roles,
weapons, equipment, tactical abilities, and landscape touch controls.

Multiplayer is LAN-only. There is no online matchmaking, hosted service,
advertising, tracking, analytics, account system, or in-app purchase.

### Packaging notes

- Release: `v1.0.0`, versionCode `1`, arm64-v8a only.
- The repository has about 105 MB of raw game assets, and the current arm64 APK
  is about 95 MB. Importing the assets and compiling Godot from source makes
  the first build large and slow; the draft allows up to four hours.
- `publishing/fdroid/io.github.daksh_mor.valu.yml` is a draft fdroiddata recipe.
  It uses `Godot@4.7.1-stable`, Java 21, and NDK `29.0.14206865`.
- The recipe builds the Linux Godot editor and arm64 Android release template
  from source with SCons and Gradle, injects that custom template, disables
  project signing, and emits an unsigned APK for F-Droid to sign. It downloads
  no prebuilt Godot editor or export-template binary and uses no upstream
  signing secret.
- The bundled glTF, texture, font, and audio files are game media, not
  executable dependencies or prebuilt native libraries.
- Android network permissions are used only for direct LAN discovery and
  matches. There are no anti-features.

### Licenses

- Project-authored source code, media (including artwork, icons, branding,
  UI, and audio), documentation, and repository/store metadata: MIT.
- Godot Engine: MIT, built from the F-Droid Godot srclib.
- Most third-party art, models, textures, sky, and audio: CC0 1.0 or public
  domain.
- Michel Baradari pain/death sounds: CC BY 3.0, with attribution included.
- Rajdhani font: SIL Open Font License 1.1, with the license text included.
- Third-party material is not relicensed; `CREDITS.md` and `docs/ASSETS.md`
  document each exception, source, attribution, and bundled license notice.

### Validation commands

After copying the draft recipe into an fdroiddata checkout as
`metadata/io.github.daksh_mor.valu.yml`:

```bash
fdroid readmeta
fdroid lint io.github.daksh_mor.valu
fdroid checkupdates --allow-dirty io.github.daksh_mor.valu
fdroid build --verbose io.github.daksh_mor.valu
```

The final command performs the intentionally long isolated source build. A
quick upstream project smoke test, with Godot 4.7.1 installed, is:

```bash
godot --headless --path . --import
godot --headless --path . --quit-after 3
```
````
