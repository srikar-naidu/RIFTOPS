class_name SmokeTargetOverlay
extends Control
## Top-down targeting overlay for Ember's map-targeted Sky Smokes: a
## schematic rectangle of the map (bounds scanned from the loaded map's
## meshes) with plant zones, teammates, your position and the cast range
## ring. Click inside range to place; right-click / Esc cancels.

signal target_chosen(slot: int, world_pos: Vector3)
signal closed

var _slot := -1
var _player: Player = null
var _bounds := Rect2(-30, -30, 60, 60)  # world-space XZ
var _bounds_scanned := false


func _ready() -> void:
	UiUtil.full_rect(self)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func open(slot: int, p: Player) -> void:
	_slot = slot
	_player = p
	if not _bounds_scanned:
		_scan_bounds()
	visible = true
	queue_redraw()


func close_overlay() -> void:
	visible = false
	closed.emit()


func _scan_bounds() -> void:
	_bounds_scanned = true
	var map_root := get_tree().current_scene.get_node_or_null("MapRoot")
	if map_root == null:
		return
	var found := false
	var min_v := Vector2.ZERO
	var max_v := Vector2.ZERO
	for mi: Node in map_root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var aabb := m.global_transform * m.get_aabb()
		var lo := Vector2(aabb.position.x, aabb.position.z)
		var hi := Vector2(aabb.position.x + aabb.size.x, aabb.position.z + aabb.size.z)
		if not found:
			min_v = lo
			max_v = hi
			found = true
		else:
			min_v = min_v.min(lo)
			max_v = max_v.max(hi)
	if found:
		_bounds = Rect2(min_v, max_v - min_v)


func _map_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var pad := 90.0
	var avail := vp - Vector2(pad * 2.0, pad * 2.0)
	var s := minf(avail.x / _bounds.size.x, avail.y / _bounds.size.y)
	var size := _bounds.size * s
	return Rect2((vp - size) * 0.5, size)


func _world_to_screen(w: Vector3) -> Vector2:
	var r := _map_rect()
	return r.position + Vector2(
		(w.x - _bounds.position.x) / _bounds.size.x * r.size.x,
		(w.z - _bounds.position.y) / _bounds.size.y * r.size.y)


func _screen_to_world(s: Vector2) -> Vector3:
	var r := _map_rect()
	var fx := clampf((s.x - r.position.x) / r.size.x, 0.0, 1.0)
	var fy := clampf((s.y - r.position.y) / r.size.y, 0.0, 1.0)
	return Vector3(_bounds.position.x + fx * _bounds.size.x, 0.0,
		_bounds.position.y + fy * _bounds.size.y)


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.is_pressed():
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			close_overlay()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var world := _screen_to_world(mb.position)
			if _in_range(world):
				var s := _slot
				close_overlay()
				target_chosen.emit(s, world)
			accept_event()
	elif event is InputEventMouseMotion:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		close_overlay()
		accept_event()


func _in_range(world: Vector3) -> bool:
	if _player == null:
		return false
	var d := Vector2(world.x - _player.global_position.x, world.z - _player.global_position.z)
	return d.length() <= EffectsManager.SKY_SMOKE_RANGE


func _draw() -> void:
	if not visible:
		return
	draw_rect(get_viewport_rect(), Color(0.03, 0.05, 0.08, 0.85))
	var r := _map_rect()
	draw_rect(r, Color(0.1, 0.14, 0.19, 1.0))
	draw_rect(r, Color(0.4, 0.5, 0.6), false, 2.0)
	# grid every 10m
	var step_x := r.size.x / _bounds.size.x * 10.0
	var x := r.position.x
	while x <= r.position.x + r.size.x + 0.5:
		draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + r.size.y), Color(0.2, 0.25, 0.3, 0.6), 1.0)
		x += step_x
	var step_y := r.size.y / _bounds.size.y * 10.0
	var y := r.position.y
	while y <= r.position.y + r.size.y + 0.5:
		draw_line(Vector2(r.position.x, y), Vector2(r.position.x + r.size.x, y), Color(0.2, 0.25, 0.3, 0.6), 1.0)
		y += step_y
	# plant zones
	for entry: Array in [["plant_zone_a", "A", Color(0.3, 0.85, 0.4)], ["plant_zone_b", "B", Color(0.95, 0.6, 0.2)]]:
		for zone: Node in get_tree().get_nodes_in_group(String(entry[0])):
			var p := _world_to_screen((zone as Node3D).global_position)
			draw_rect(Rect2(p - Vector2(14, 14), Vector2(28, 28)), Color(entry[2], 0.35))
			draw_string(ThemeDB.fallback_font, p + Vector2(-5, 6), String(entry[1]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, entry[2])
	if _player != null:
		# range ring + self + allies
		var self_p := _world_to_screen(_player.global_position)
		var ring_px := EffectsManager.SKY_SMOKE_RANGE / _bounds.size.x * r.size.x
		draw_arc(self_p, ring_px, 0, TAU, 64, Color(0.95, 0.85, 0.45, 0.7), 2.0)
		for node: Node in get_tree().get_nodes_in_group("players"):
			var pl := node as Player
			if not pl.alive or pl.team != _player.team or pl == _player:
				continue
			draw_circle(_world_to_screen(pl.global_position), 5.0, Color(0.35, 0.8, 0.65))
		draw_circle(self_p, 6.0, Color.WHITE)
		# cursor validity
		var mouse := get_viewport().get_mouse_position()
		var world := _screen_to_world(mouse)
		var ok := _in_range(world)
		draw_arc(mouse, 12.0, 0, TAU, 32, Color(0.4, 1.0, 0.5) if ok else Color(1.0, 0.35, 0.3), 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(r.position.x, r.position.y - 18),
		"SKY SMOKE — click within the ring to place  ·  right-click to cancel",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.88, 0.92))
