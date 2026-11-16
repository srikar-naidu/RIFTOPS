# Valu itch.io publishing kit

This directory contains the paste-ready page copy, recommended project metadata, store images, and a guarded APK upload script. No itch.io authentication or upload has been performed.

## Prepared release

- APK: `../../builds/Valu-1.0.0.apk`
- Version: `1.0.0`
- APK SHA-256: `83e641639354336680c57ef50d3129f08e7487e56e8c8efb0ef2bf5eae070323`
- Signature: valid APK Signature Scheme v2 and v3, one signer
- Cover: `images/cover.png` (630 × 500 PNG)
- Page copy: `PAGE.md`
- Project settings and checklist: `metadata.md`

## Butler

The official stable Apple Silicon build is installed at `/opt/homebrew/bin/butler`.

Installed version:

`v15.29.0, built on Jul 14 2026 @ 01:09:49`

It was installed from itch.io's stable broth channel:

`https://broth.itch.zone/butler/darwin-arm64/LATEST/archive/default`

## Final publish sequence

1. Sign in to itch.io as `daksh-mor`, open `https://itch.io/game/new`, create **Valu** with URL slug `valu`, and keep it in Draft.
2. In a terminal, run `butler login` and finish the browser authorization.
3. From the repository root, run:

   ```bash
   ./publishing/itch/publish.sh
   ```

   The script verifies the pinned APK SHA-256 and APK signature before it runs:

   ```bash
   butler push builds/Valu-1.0.0.apk "daksh-mor/valu:android" --userversion 1.0.0
   ```

4. Upload the cover and screenshots, apply `metadata.md`, paste `PAGE.md`, and confirm its source-code link opens the public repository.
5. Preview the page, test the draft download once, change visibility to Public, and click **Publish**.

Do not put an API key or other credential in `publish.sh`. Butler stores its own login after the browser authorization.
