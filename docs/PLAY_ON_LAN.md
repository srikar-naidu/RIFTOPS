# Valu — Play on your phones (LAN)

One page to get a match running between phones on the same WiFi.

## 1. Install the APK on each phone

The release build is `builds/Valu-1.0.0.apk` (package `io.github.daksh_mor.valu`, signed with the Valu release key).

**Option A — USB + adb (developer way):**
1. On the phone: Settings → About phone → tap *Build number* 7 times, then enable *USB debugging* under Developer options.
2. Plug into the Mac and run:
   ```
   ~/Library/Android/sdk/platform-tools/adb install -r builds/Valu-1.0.0.apk
   ```

**Option B — file share / sideload (no cable):**
1. Get the APK onto the phone any way you like: AirDrop-to-Android alternatives (LocalSend), Google Drive, email to yourself, or USB file copy.
2. Tap the APK in the phone's Files app.
3. Android will ask to allow **"Install unknown apps"** for that app (Files/Drive/browser) — allow it once, then install. A sideload warning is expected because this APK is distributed outside an app store.

## 2. Host a match

1. Put every phone on the **same WiFi network** (or one phone's personal hotspot — that works too, the hotspot phone can host or join).
2. Open Valu → **HOST GAME**.
3. You land in the lobby. As host you pick:
   - **Mode** — *Spike* (plant/defuse rounds, buy menu, first to 13) or *TDM* (respawn deathmatch).
   - **Map** — *solstice* (the real map) or *graybox* (test box).
   - **Team size** — 1v1 up to 5v5.
4. The lobby shows **"Your IP for manual join: 192.168.x.x"** — read it out if auto-discovery doesn't find you (see below).
5. Everyone picks a **team** (Attackers/Defenders) and an **agent** (Gale / Ember / Warden / Flint — long-press a button on desktop to see the kit).
6. **START MATCH.**

## 3. Join a match

1. Open Valu → **JOIN GAME**.
2. Hosts on your network appear in the list automatically within a second or two — tap one, then **JOIN**.
3. **If the list stays empty:** type the host's IP into the box and press JOIN. The host's IP is shown in their lobby ("Your IP for manual join"), or in the host phone's WiFi settings (tap the connected network → IP address).

## 4. Troubleshooting

| Problem | Fix |
|---|---|
| Host never appears in the join list | Many routers/hotel/office APs have **AP/client isolation** which blocks UDP broadcast. Use the **manual IP** box instead — that usually still works. If joining by IP also fails, the router isolates clients completely: use a **personal hotspot** from one of the phones. |
| Join by IP fails | Both devices must be on the **same subnet** (IPs look alike, e.g. both 192.168.1.x). The game uses **UDP ports 27015 (game) and 27016 (discovery)** — nothing else should be bound to them. |
| Mac hosting, phones can't join | Allow incoming connections for Godot/Valu in macOS System Settings → Network → Firewall. |
| Lag / rubber-banding | Stay near the router; 2.4 GHz WiFi with many devices gets noisy. The host phone does the most work — use the strongest phone as host. |
| Controls feel too fast/slow | Settings → *Touch sensitivity* and *ADS sensitivity scale*. |
| Phone runs hot / drops frames | Settings → *3D resolution scale* down to 0.7–0.85. |

Have fun. Plant the spike responsibly.
