# Valu — Asset Manifest

All third-party assets, their sources, licenses, and which files we kept.
Everything lives under `assets/`. Total size: ~105 MB raw.

**License summary:** bundled third-party assets are CC0 (public domain) except
the death grunts (CC BY 3.0, attribution below) and the Rajdhani font (SIL OFL
1.1). Valu's project-authored branding, icons, UI art, game-specific artwork,
and synthesized audio are available under the repository's MIT License; see
`CREDITS.md` for the exact scope.

---

## 1. Characters — `assets/characters/`

### Ultimate Animated Character Pack (Quaternius) — CC0
- **Author:** Quaternius — https://quaternius.com/packs/ultimatedanimatedcharacter.html
- **License:** CC0 1.0 (license text: `characters/LICENSE_Quaternius_CC0.txt`)
- **Files kept:** `Ninja_Male.gltf`, `Knight_Male.gltf`, `Soldier_Male.gltf`,
  `Soldier_Female.gltf`, `BlueSoldier_Male.gltf`, `Suit_Male.gltf`
  (single-file glTF, textures + rig + animations embedded, ~1.8 MB each)
- **Animations (identical set on every character):** `Death`, `Defeat`, `Idle`, `Jump`,
  `PickUp`, `Punch`, `RecieveHit`, `Roll`, `Run`, `Run_Carry`, `Shoot_OneHanded`,
  `SitDown`, `StandUp`, `SwordSlash`, `Victory`, `Walk`, `Walk_Carry`
  (`Suit_Male` lacks `Punch`)
- **Suggested agent mapping:** Gale = Ninja_Male (Roll doubles as dash),
  Ember = Soldier_Male, Warden = Knight_Male, Flint = Suit_Male or BlueSoldier_Male;
  Soldier_Female as extra skin. Distinct silhouettes + easy material recolors in Godot.

### Toon Shooter Game Kit characters (Quaternius) — CC0
- **Author:** Quaternius — https://quaternius.com/packs/toonshootergamekit.html
- **License:** CC0 1.0
- **Files kept:** `Character_Soldier.gltf`, `Character_Enemy.gltf`, `Character_Hazmat.gltf`
- **Animations:** `Death`, `Duck`, `HitReact`, `Idle`, `Idle_Shoot`, `Jump`, `Jump_Idle`,
  `Jump_Land`, `No`, `Punch`, `Run`, `Run_Gun`, `Run_Shoot`, `Walk`, `Walk_Shoot`,
  `Wave`, `Yes` — shooter-specific (two-handed gun poses). Good alternates/extra skins.

### Universal Animation Library (Quaternius) — CC0
- **Author:** Quaternius — https://quaternius.com/packs/universalanimationlibrary.html
- **License:** CC0 1.0
- **Files kept:** `UAL1_Standard.glb` (Godot/Unreal export, no root motion, 120+ clips
  incl. rifle/pistol locomotion, browse at https://quaternius.com/animviewer.html),
  `UAL1_Godot_Setup.png` (official Godot retarget setup guide)
- **Use:** shared retargetable animation library if we later want one anim set across
  all skins (Godot BoneMap retarget). The baked per-character sets above are enough for v1.

## 2. Weapons — `assets/weapons/`

### Toon Shooter Game Kit guns (Quaternius) — CC0
- **Author:** Quaternius — https://quaternius.com/packs/toonshootergamekit.html
- **License:** CC0 1.0
- **Files kept (single-file glTF, 30–115 KB each):**
  - `Pistol.gltf` → Classic
  - `Revolver.gltf` → Sheriff
  - `SMG.gltf` → Spectre
  - `AK.gltf` → Vandal
  - `Sniper_2.gltf` → Phantom (scoped AR look) — or swap with `AK`
  - `Sniper.gltf` → Operator (bolt sniper)
  - `Shotgun.gltf` → spare (Judge-like, if a shotgun is added)
  - `Knife_1.gltf` → melee
  - `Grenade.gltf`, `FireGrenade.gltf` → ability projectiles (flash / molly)
- Stylized low-poly, hold up well close-up in first person with flat-color materials.

## 3. Environment textures — `assets/textures/`

### ambientCG PBR materials — CC0
- **Author:** ambientCG (Lennart Demes) — https://ambientcg.com
- **License:** CC0 1.0
- **Kept maps:** `_Color`, `_NormalGL`, `_Roughness` JPG per material (AO/displacement dropped).
  All 1K except the hero floor (2K).

| Material | Use | Source |
|---|---|---|
| `Plaster001_1K` | main plaster walls | https://ambientcg.com/view?id=Plaster001 |
| `PaintedPlaster017_1K` | colored accent walls | https://ambientcg.com/view?id=PaintedPlaster017 |
| `PavingStones138_2K` | plaza floor (hero surface) | https://ambientcg.com/view?id=PavingStones138 |
| `Concrete034_1K` | concrete floors/ramps | https://ambientcg.com/view?id=Concrete034 |
| `Planks037A_1K` | rough wood (crates/stalls) | https://ambientcg.com/view?id=Planks037A |
| `WoodFloor043_1K` | interior wood floors | https://ambientcg.com/view?id=WoodFloor043 |
| `PaintedMetal004_1K` | metal doors/trims | https://ambientcg.com/view?id=PaintedMetal004 |
| `DiamondPlate009_1K` | industrial metal (site B) | https://ambientcg.com/view?id=DiamondPlate009 |
| `RoofingTiles013A_1K` | terracotta roofs | https://ambientcg.com/view?id=RoofingTiles013A |
| `Bricks075A_1K` | brick walls | https://ambientcg.com/view?id=Bricks075A |
| `Fabric030_1K` | sandbags/awnings cloth | https://ambientcg.com/view?id=Fabric030 |
| `Ground054_1K` | dirt ground areas | https://ambientcg.com/view?id=Ground054 |

## 4. Props — `assets/props/`

### Medieval Village MegaKit, Standard (Quaternius) — CC0 — `props/medieval_kit/`
- **Author:** Quaternius — https://quaternius.com/packs/medievalvillagemegakit.html
- **License:** CC0 1.0 (`props/medieval_kit/LICENSE.txt`)
- **Files kept:** 39 modular building pieces (glTF + .bin) — plaster/brick walls
  (straight, door, window variants), `Wall_Arch`, doors + round/flat door frames,
  windows + shutters, round-tile roof slabs, exterior stairs, plaster overhangs
  (double as market awnings), brick floors — plus the shared texture set
  (`T_Plaster_*`, `T_Brick_*`, `T_UnevenBrick_*`, `T_RoundTiles_*`, `T_RockTrim_*`,
  `T_WoodTrim_*`, `T_MetalOrnaments_*`), downscaled to 1K for mobile.
- **Use:** the Mediterranean building vocabulary for the map.

### Fantasy Props MegaKit, Standard (Quaternius) — CC0 — `props/fantasy_props/`
- **Author:** Quaternius — https://quaternius.com/packs/fantasypropsmegakit.html
- **License:** CC0 1.0 (`props/fantasy_props/LICENSE.txt`)
- **Files kept:** 27 props (glTF + .bin) + shared trim textures (1K):
  crates (`Crate_Wooden`, `Crate_Metal`, `FarmCrate_Empty`), `Barrel`, `Barrel_Holder`,
  sacks (`Bag`, `Pouch_Large` — our stylized "sandbags"), market stalls
  (`Stall_Empty`, `Stall_Cart_Empty`), planters (`Vase_2`, `Vase_4`, `Vase_Rubble_Medium`),
  `Bench`, `Table_Large`, `Chest_Wood`, buckets, `Rope_1`, `Chain_Coil`,
  wall banners, `Lantern_Wall`, `Torch_Metal`, `Workbench`, `Dummy`.

## 5. Sky — `assets/sky/`

### Kloofendal 48d Partly Cloudy (Pure Sky) — CC0
- **Author:** Greg Zaal / Poly Haven — https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky
- **License:** CC0 1.0
- **File kept:** `kloofendal_48d_partly_cloudy_puresky_2k.hdr` (2K Radiance HDR, 5.5 MB) —
  outdoor daylight, works directly in a Godot `PanoramaSkyMaterial`.

## 6. Audio — `assets/audio/`

### The Free Firearm Sound Library — CC0 — `audio/guns/`
- **Author:** Sound Effects Library / freefirearmsfx.com team —
  https://opengameart.org/content/the-free-firearm-sound-library
- **License:** CC0 (stated by the authors on the OGA page)
- **Files kept (processed):** real recordings, trimmed to a single ~2 s shot,
  converted to 16-bit 44.1 kHz mono WAV (~170 KB each):
  - `gun_pistol_classic.wav` (Walther PPQ) — Classic
  - `gun_pistol_sheriff.wav` (S&W 642 revolver) — Sheriff
  - `gun_smg.wav` (Carl Gustav M45) — Spectre
  - `gun_rifle_phantom.wav` (AR-15) — Phantom
  - `gun_rifle_vandal.wav` (AK-47) — Vandal
  - `gun_sniper.wav` (Tikka bolt-action) — Operator

### Kenney audio packs — CC0 — `audio/foley/`, `audio/ui/`, `audio/music/`
- **Author:** Kenney — https://kenney.nl/assets (packs: Impact Sounds, Interface Sounds,
  RPG Audio, Sci-Fi Sounds, Music Jingles)
- **License:** CC0 1.0 (`audio/LICENSE_Kenney_CC0.txt`)
- **foley/** — footsteps ×2+ surfaces: `footstep_concrete_000-004`, `footstep_wood_000-004`,
  `footstep_grass_000-002`; body impacts: `impactPunch_medium_000-002`, `impactPunch_heavy_000`;
  headshot ding: `impactBell_heavy_000/001`; glass/shield break: `impactGlass_heavy_000-002`;
  bullet-surface hits: `impactMetal_light_000/001`, `impactPlank_medium_000/001`;
  reload foley: `beltHandle1/2`, `metalLatch`; dry-fire click: `metalClick`;
  knife equip: `drawKnife1/2`; spike plant cloth: `cloth1`; buy/credits: `handleCoins`;
  map doors: `doorOpen_1`, `doorClose_1`; explosion (spike detonation):
  `explosionCrunch_000/001`, distant boom `lowFrequency_explosion_000`;
  dash whoosh: `thrusterFire_000/001`; Warden wall / shield: `forceField_000/001`
- **ui/** — buttons `click_001-003`, `select_001/002`, `back_001`; buy confirm/deny
  `confirmation_001/002`, `error_001/002`; hitmarker tick `tick_001/002`;
  round gong `bong_001`; buy-menu prompt `question_001`
- **music/** — round stingers (start/win/lose picks): `jingles_STEEL00/02/04/07/10/14`,
  `jingles_PIZZI00/04/07`

### Fire Crackling — CC0 — `audio/foley/fire_loop.ogg`
- **Author:** AntumDeluge — https://opengameart.org/content/fire-crackling
- **License:** CC0 1.0. Loopable; for Ember's molotov area-denial.

### 11 male human pain/death sounds — CC-BY 3.0 — `audio/foley/grunt_*.wav`
- **Author:** Michel Baradari — https://opengameart.org/content/11-male-human-paindeath-sounds
- **License:** CC-BY 3.0 — **ATTRIBUTION REQUIRED in game credits:**
  "Pain/death sounds by Michel Baradari (opengameart.org), CC-BY 3.0"
- **Files kept:** `grunt_deathh.wav`, `grunt_die1.wav`, `grunt_die2.wav`,
  `grunt_pain1.wav`, `grunt_pain2.wav`
- If we want a zero-attribution build, delete these and ship without grunts.

### Project-authored (MIT) — `audio/ui/spike_beep.wav`, `spike_beep_fast.wav`
- 880 Hz / 1174 Hz decaying sine beeps generated with Python for the spike arm/detonation
  countdown (fast variant for the final seconds).

## 7. Font — `assets/fonts/`

### Rajdhani — SIL OFL 1.1
- **Author:** Indian Type Foundry — https://fonts.google.com/specimen/Rajdhani
  (fetched from https://github.com/google/fonts/tree/main/ofl/rajdhani)
- **License:** SIL Open Font License 1.1 (`fonts/Rajdhani-OFL.txt`) — free for commercial
  use, embedding allowed; keep the OFL file with the font.
- **Files kept:** `Rajdhani-Regular.ttf`, `Rajdhani-Medium.ttf`, `Rajdhani-SemiBold.ttf`,
  `Rajdhani-Bold.ttf` — squared/condensed tactical look for the HUD.

---

## 8. Ambient loops (positional emitters) — `assets/audio/ambient/`

Seamless loops for the 4 map emitters in `maps/solstice` plus one global bed.
All processed to mono 22.05 kHz OGG Vorbis (sources decoded from 16-bit OGG/WAV),
each well under 1 MB. Loop seams verified numerically on the *decoded* files
(boundary sample step ≤ 99.9th-percentile sample-to-sample delta; no RMS dip
across the seam). Processing done in Python (`soundfile`/`numpy`; no ffmpeg on
this machine, and macOS `afconvert` lacks Vorbis): steadiest-segment selection,
circular FFT band-shaping (loop-safe by construction), then an equal-power
0.5–1 s tail-into-head crossfade.

| File | Use | Source material | License |
|---|---|---|---|
| `amb_fountain_water.ogg` (5.9 s) | fountain / running water | `sfx100v2_loop_water_01` from **"100 CC0 SFX #2"** by rubberduck — https://opengameart.org/content/100-cc0-sfx-2 | CC0 |
| `amb_plaza_wind_light.ogg` (15 s) | plaza emitter (light, distant wind) | `wind2.wav` from **"wind1"** by Luke.RUSTLTD — https://opengameart.org/content/wind1 | CC0 / public domain |
| `amb_generator_hum.ogg` (6.6 s) | electrical/generator hum | `sfx100v2_loop_machine_01` from **"100 CC0 SFX #2"** by rubberduck (same pack as above) | CC0 |
| `amb_wind_soft.ogg` (17 s) | soft wind, exposed site | `wind1.wav` from **"wind1"** by Luke.RUSTLTD (same pack as above) | CC0 / public domain |
| `amb_town_bed.ogg` (7.6 s) | optional global town-ambience bed | `ambient_01` from **"30 CC0 SFX loops"** by rubberduck — https://opengameart.org/content/30-cc0-sfx-loops | CC0 |

Extra processing notes:
- `amb_generator_hum.ogg` is tonal, so it was rebuilt period-aligned: trimmed to
  438 whole cycles of its ~66.8 Hz fundamental with an equal-gain (linear) crossfade
  to avoid phase cancellation — decoded seam step 0.006 vs 0.016 typical.
- The two winds come from different source files (`wind1.wav` / `wind2.wav`) and are
  EQ'd differently (plaza: 300–2500 Hz band, −2 dB/oct tilt, quieter; site: fuller
  100–4000 Hz), so they read as distinct emitters.
- Levels are normalized with headroom (peak 0.4–0.5); final mix levels belong to the
  `AudioStreamPlayer3D` setup.

## Known gaps / substitutions

- **Military sandbags:** no CC0 stylized sandbag model found in the scripted-download
  sources; using `Bag.gltf` / `Pouch_Large.gltf` (stacked) as stylized equivalents.
  Fallback if real sandbags are wanted: Kenney "Blaster Kit"-era props or model a
  6-face blob with `Fabric030` texture.
- **Second distinct assault rifle:** the Toon Shooter kit has one AK; `Sniper_2.gltf`
  (scoped, magazine-fed) is the Phantom stand-in. Fallback: Quaternius "Ultimate Guns Pack"
  (CC0, 40 guns) exists but only in FBX/OBJ via Google Drive — Godot 4.3+ imports FBX,
  so it's a viable upgrade later.
- **Round-start stinger:** using one of the Kenney jingles; if a more "tactical" stinger
  is wanted, synthesize a two-note motif or check Kenney "Music Loops" packs.
- **Outdoor market murmur:** no CC0/CC-BY crowd-walla loop found (the closest match,
  Gregor Quendel's "Free General Ambience Sounds", is CC-BY-**SA** 4.0 — rejected under
  our license rules; BigSoundBank blocks scripted downloads). Used the spec's allowed
  alternative: light plaza wind (`amb_plaza_wind_light.ogg`). If real murmur is wanted
  later, BigSoundBank "Village, city center" (CC0) via a manual browser download is the
  best candidate.
- All `.import` files in these folders are generated by Godot, not part of the source packs.
