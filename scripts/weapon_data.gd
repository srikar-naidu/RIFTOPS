class_name WeaponData
extends Resource
## Data-driven weapon definition. Stat values in weapons/*.tres use
## contemporary tactical-shooter reference values recorded in July 2026.
## Spray pattern offsets are hand-tuned for each weapon's intended feel.

enum FireMode { SEMI, AUTO, BOLT, MELEE }
enum Slot { PRIMARY, SECONDARY, KNIFE }

@export_group("Identity")
@export var id: StringName = &""
@export var display_name: String = ""
@export var price: int = 0
@export var category: String = "Rifle"
@export var slot: Slot = Slot.PRIMARY

@export_group("Firing")
@export var fire_mode: FireMode = FireMode.AUTO
@export var fire_rate: float = 10.0
## mag_size 0 means no ammo tracking (melee).
@export var mag_size: int = 30
@export var reserve_ammo: int = 90
@export var reload_time: float = 2.5
@export var equip_time: float = 1.0
@export var max_range: float = 120.0

@export_group("Damage")
## One Vector4 per falloff band: x = band max distance (m), y = head, z = body, w = legs.
## Bands must be sorted by distance; beyond the last band the last values apply.
@export var damage_bands: Array[Vector4] = []
@export var melee_back_multiplier: float = 1.0
@export var applies_tag: bool = true

@export_group("Accuracy (degrees)")
@export var first_shot_spread: float = 0.25
@export var crouch_spread_mult: float = 0.85
@export var max_spread: float = 2.0
## Additive inaccuracy while moving in each state.
@export var spread_crouch_move: float = 0.3
@export var spread_walk: float = 1.0
@export var spread_run: float = 2.0
@export var spread_air: float = 7.0

@export_group("Spray")
## Deterministic per-shot recoil offsets in degrees (x = yaw right, y = pitch up).
## Shots past the end of the pattern get pseudo-random offsets near the last entry.
@export var spray_pattern: Array[Vector2] = []
@export var spray_random_spread: float = 1.0
@export var spray_growth_per_shot: float = 0.05
## Seconds without firing before the spray index resets.
@export var recovery_time: float = 0.4
@export var recoil_kick_deg: float = 0.35

@export_group("ADS")
## 0 = weapon has no ADS. Otherwise the camera FOV is divided by this factor.
@export var ads_zoom: float = 0.0
## Second zoom stage (Operator). 0 = single-stage ADS. When set, the ADS
## input cycles hip -> ads_zoom -> ads_zoom_2 -> hip.
@export var ads_zoom_2: float = 0.0
@export var ads_spread_mult: float = 1.0
@export var ads_fire_rate_mult: float = 1.0
@export var ads_move_mult: float = 0.76
@export var ads_time: float = 0.2

@export_group("Alt fire (burst)")
## >1 = the ADS input triggers an N-round burst instead of aiming (Classic).
@export var alt_burst_count: int = 0
## Seconds between burst rounds / after the burst before the next shot.
@export var alt_burst_interval: float = 0.08
@export var alt_burst_cooldown: float = 0.45
## Extra spread (degrees) applied to every burst round.
@export var alt_burst_spread: float = 2.2

@export_group("Handling")
## Multiplier on base run speed (6.75 m/s) while this weapon is equipped.
@export var move_speed_mult: float = 0.8

@export_group("Presentation")
@export var viewmodel_path: String = ""
@export var viewmodel_scale: float = 1.0
@export var viewmodel_tint: Color = Color(0.75, 0.78, 0.85)
@export var fire_sound_path: String = ""
## Phantom-style silencer: others don't see your tracers.
@export var tracer_visible_to_others: bool = true


func has_ads() -> bool:
	return ads_zoom > 0.0


## Classic-style right-click burst.
func has_burst_alt() -> bool:
	return alt_burst_count > 1


## Operator-style two-stage zoom.
func has_zoom_stages() -> bool:
	return has_ads() and ads_zoom_2 > 0.0


func zoom_for_stage(stage: int) -> float:
	return ads_zoom_2 if stage >= 2 and has_zoom_stages() else ads_zoom


func is_melee() -> bool:
	return fire_mode == FireMode.MELEE


func is_semi() -> bool:
	return fire_mode == FireMode.SEMI or fire_mode == FireMode.BOLT


func fire_interval_ms(ads: bool) -> int:
	var rate := fire_rate
	if ads and has_ads():
		rate *= ads_fire_rate_mult
	return int(round(1000.0 / maxf(rate, 0.01)))


func damage_for(distance: float, region: int) -> int:
	if damage_bands.is_empty():
		return 0
	var band: Vector4 = damage_bands[damage_bands.size() - 1]
	for b in damage_bands:
		if distance <= b.x:
			band = b
			break
	match region:
		HitboxRegion.Region.HEAD:
			return int(band.y)
		HitboxRegion.Region.LEGS:
			return int(band.w)
		_:
			return int(band.z)


## Total inaccuracy cone (degrees) for the next shot:
## first-shot error + movement error + spray bloom, reduced by crouch/ADS.
## speed_frac is horizontal speed as a fraction of base run speed (6.75);
## below the 0.275 movement deadzone, movement adds no error.
func compute_spread_deg(ads: bool, crouched: bool, airborne: bool, speed_frac: float, spray_index: int) -> float:
	var s := first_shot_spread * (crouch_spread_mult if crouched else 1.0)
	s += minf(float(spray_index) * spray_growth_per_shot, maxf(max_spread - first_shot_spread, 0.0))
	if airborne:
		s += spread_air
	elif speed_frac > 0.62:
		s += spread_run
	elif speed_frac > 0.275:
		s += spread_crouch_move if crouched else spread_walk
	if ads and has_ads():
		s *= ads_spread_mult
	return maxf(s, 0.0)


func spray_offset_deg(index: int, rng: RandomNumberGenerator) -> Vector2:
	if spray_pattern.is_empty():
		return Vector2.ZERO
	if index < spray_pattern.size():
		return spray_pattern[index]
	var last: Vector2 = spray_pattern[spray_pattern.size() - 1]
	return last + Vector2(
		rng.randf_range(-1.0, 1.0) * spray_random_spread,
		rng.randf_range(-0.3, 0.5) * spray_random_spread * 0.5)


## Applies a deterministic spray offset plus a uniform random cone to a direction.
static func deviate(dir: Vector3, offset_deg: Vector2, spread_deg: float, rng: RandomNumberGenerator) -> Vector3:
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right := dir.cross(up).normalized()
	var real_up := right.cross(dir).normalized()
	var d := dir.normalized()
	if offset_deg != Vector2.ZERO:
		d = d.rotated(real_up, deg_to_rad(-offset_deg.x))
		d = d.rotated(right, deg_to_rad(offset_deg.y))
	if spread_deg > 0.0:
		var ang := rng.randf() * TAU
		var axis := (real_up * cos(ang) + right * sin(ang)).normalized()
		d = d.rotated(axis, sqrt(rng.randf()) * deg_to_rad(spread_deg))
	return d.normalized()
