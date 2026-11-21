extends Node3D
## Original proportioned tactical operator. Cosmetic, never used as a hitbox.
const P = preload("res://scripts/art/mesh_parts.gd")
var torso: Node3D
var legs: Array[Node3D] = []
var clock := 0.0
var locomotion := 0.0
func _ready() -> void:
	var cloth := P.material("374848")
	var armor := P.material("525c50",.15)
	var dark := P.material("1b272b",.2)
	var trim := P.material("9fa885",.25)
	var visor := P.material("263c48",.75,.15)
	for side in [-1,1]:
		var leg := Node3D.new()
		leg.position = Vector3(side*.12,.88,0)
		add_child(leg)
		legs.append(leg)
		P.capsule(leg,Vector3(0,-.22,0),.095,.46,cloth)
		P.capsule(leg,Vector3(0,-.59,.02),.075,.42,cloth)
		P.capsule(leg,Vector3(0,-.43,-.065),.075,.16,armor)
		P.box(leg,Vector3(0,-.80,-.055),Vector3(.15,.14,.27),dark)
	torso = Node3D.new()
	add_child(torso)
	P.capsule(torso,Vector3(0,1.20,0),.23,.67,cloth)
	P.box(torso,Vector3(0,1.28,-.14),Vector3(.37,.37,.16),armor)
	P.box(torso,Vector3(0,1.28,.16),Vector3(.32,.39,.14),dark)
	for x in [-.12,0,.12]:
		P.box(torso,Vector3(x,1.19,-.24),Vector3(.095,.17,.07),cloth)
		P.box(torso,Vector3(x,1.25,-.28),Vector3(.085,.018,.012),trim)
	P.box(torso,Vector3(0,.94,0),Vector3(.40,.07,.25),dark)
	P.capsule(torso,Vector3(0,1.64,0),.125,.29,dark)
	P.capsule(torso,Vector3(0,1.73,.015),.15,.23,armor)
	P.box(torso,Vector3(0,1.67,-.119),Vector3(.225,.072,.045),visor)
	P.box(torso,Vector3(0,1.58,-.12),Vector3(.15,.085,.055),cloth)
	for side in [-1,1]:
		P.capsule(torso,Vector3(side*.28,1.30,0),.085,.31,cloth,Vector3(0,0,side*.18))
		P.capsule(torso,Vector3(side*.29,1.10,-.12),.07,.30,cloth,Vector3(1.0,0,side*.2))
		P.capsule(torso,Vector3(side*.24,1.06,-.24),.072,.14,dark,Vector3(PI/2,0,0))
		P.capsule(torso,Vector3(side*.28,1.41,0),.095,.14,armor)
	P.box(torso,Vector3(.1,1.42,-.231),Vector3(.075,.04,.008),trim)
	var gun := preload("res://assets/weapons/rx24.tscn").instantiate()
	torso.add_child(gun)
	gun.position = Vector3(.13,1.1,-.29)
	gun.rotation.y = -.35
	gun.scale = Vector3.ONE*.85

func _process(delta: float) -> void:
	clock += delta
	var owner_player := get_parent().get_parent()
	if owner_player is CharacterBody3D:
		locomotion = float(owner_player.observed_velocity.length())
	for i in legs.size():
		legs[i].rotation.x = sin(clock*9+i*PI)*minf(locomotion*.12,.5)
	torso.position.y = sin(clock*2)*.006
