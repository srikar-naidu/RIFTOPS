extends Control
## Cheap schematic map: real arena footprints + local position, no wallhack dots.
var tick := 0.0
func _ready() -> void:
	position = Vector2(22,22)
	size = Vector2(180,204)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	tick += delta
	if tick > .1:
		tick = 0
		queue_redraw()

func point(world: Vector3) -> Vector2:
	return Vector2(90,90)+Vector2(world.x,world.z)*2.4

func _draw() -> void:
	var arena := get_tree().get_first_node_in_group("arena_map")
	if arena == null:
		return
	draw_rect(Rect2(0,0,180,204),Color(.025,.045,.055,.85))
	draw_rect(Rect2(5,5,170,170),Color("52635b"))
	draw_rect(Rect2(78,10,24,160),Color("29363e"))
	for footprint: Rect2 in arena.footprints:
		draw_rect(Rect2(Vector2(90,90)+footprint.position*2.4,footprint.size*2.4),Color("b8c5bd"))
	draw_rect(Rect2(5,5,170,170),Color("899a93"),false,1)
	draw_string(ThemeDB.fallback_font,Vector2(12,194),"TESTSITE-07  /  N ↑",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("e1ed53"))
	var player: Node3D = GameState.local_player
	if is_instance_valid(player):
		var pos := point(player.global_position)
		var direction := Vector2(-sin(player.rotation.y),-cos(player.rotation.y))
		draw_circle(pos,4,Color("e1ed53"))
		draw_line(pos,pos+direction*12,Color.WHITE,2)
