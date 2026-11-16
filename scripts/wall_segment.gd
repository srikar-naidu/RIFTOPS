class_name WallSegment
extends StaticBody3D
## One destructible segment of Warden's Barrier Wall. Lives on physics
## layer 1 on EVERY peer (blocks movement locally and bullets on the server).
## HP is server-authoritative via the EffectsManager.

var effect_id := 0
var seg_index := 0
var manager: Node = null


func server_bullet_hit(dmg: int) -> void:
	if manager != null:
		manager.server_wall_damage(effect_id, seg_index, dmg)
