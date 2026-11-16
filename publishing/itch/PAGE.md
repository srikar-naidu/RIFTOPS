# Valu

**A free, open-source tactical FPS for Android, built for local Wi-Fi matches.**

Valu is an original, mobile-first tactical shooter for up to 5v5 players. One device hosts the match and the other players join over the same Wi-Fi network—no external server or online account required.

There are no ads, analytics, tracking, or in-app purchases.

## Features

- Round-based objective mode with planting, defusing, side swaps, shields, and a full buy economy
- Team deathmatch for quick warm-ups
- Seven weapons with distinct handling, alternate fire, movement error, recoil, and range falloff
- Four playable agents with twelve server-validated abilities
- Solstice, a two-site competitive map
- Mobile-first touch controls with adjustable aim sensitivity and 3D resolution scale
- Server-authoritative LAN play with automatic host discovery and manual-IP joining

## Install and play

1. Download `Valu-1.0.0.apk` on each Android phone.
2. Open the APK and allow **Install unknown apps** for your browser or file manager when Android asks. The sideload warning is expected for a game distributed outside an app store.
3. Put every phone on the same Wi-Fi network. A personal hotspot also works.
4. On one phone, open Valu and choose **HOST GAME**. Pick the mode, map, team size, team, and agent.
5. On the other phones, choose **JOIN GAME**, select the discovered host, and join.

## Touch controls

- Left joystick: move
- Drag on the right side: aim
- FIRE buttons: shoot
- JUMP, CRCH, RLD, and SWAP: jump, crouch, reload, and change weapon
- ADS, ZOOM, or BURST: weapon-specific alternate fire
- Q, E, and X: agent abilities
- BUY and SCORE: open the shop and scoreboard

Optional desktop controls when building from source: WASD + mouse, Shift to walk, Ctrl/C to crouch, right mouse for alternate fire or aim, R to reload, F to interact, Q/E/X for abilities, B for the shop, and Tab for the scoreboard.

## Requirements

- Android 7.0 or later (API level 24+)
- 64-bit ARM device (`arm64-v8a`)
- Landscape orientation
- All players on the same Wi-Fi network or personal hotspot
- For the best match, use the strongest phone as host

## If the host does not appear

Enter the host's IP address in the manual-IP field. The host can read it from the lobby under **Your IP for manual join**.

Both devices must be on the same subnet. Some hotel, school, office, and guest networks isolate connected devices; if manual IP also fails, use a personal hotspot instead. Valu uses UDP port `27015` for the game and `27016` for discovery.

## Source, license, and credits

Source code: **https://github.com/daksh-mor/valu**

Valu's project-authored code, media (including artwork, icons, branding, UI, and audio), documentation, and store metadata are released under the MIT License. Third-party assets retain their respective free licenses; most are CC0, with attributed pain/death sounds by Michel Baradari under CC BY 3.0 and the Rajdhani font under the SIL Open Font License 1.1. Full credits and the asset manifest are included with the source.
