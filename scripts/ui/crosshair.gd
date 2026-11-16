class_name Crosshair
extends Control
## Dynamic crosshair: gap follows the live spread cone (converted to pixels by
## the HUD), plus hitmarker flashes (white = hit, red = kill).

var spread_px := 8.0
var _hit_t := 0.0
var _hit_kill := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_hitmarker(kill: bool) -> void:
	_hit_t = 1.0
	_hit_kill = kill


func _process(delta: float) -> void:
	if _hit_t > 0.0:
		_hit_t = maxf(_hit_t - delta * 4.5, 0.0)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var col := Color(0.35, 1.0, 0.85, 0.95)
	var gap := 4.0 + spread_px
	var len := 7.0
	var th := 2.0
	draw_line(c + Vector2(gap, 0), c + Vector2(gap + len, 0), col, th)
	draw_line(c - Vector2(gap, 0), c - Vector2(gap + len, 0), col, th)
	draw_line(c + Vector2(0, gap), c + Vector2(0, gap + len), col, th)
	draw_line(c - Vector2(0, gap), c - Vector2(0, gap + len), col, th)
	draw_circle(c, 1.2, col)
	if _hit_t > 0.0:
		var hcol := Color(1.0, 0.25, 0.2, _hit_t) if _hit_kill else Color(1, 1, 1, _hit_t)
		var r1 := 6.0
		var r2 := 14.0
		for q: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + q * r1, c + q * r2, hcol, 2.5)
