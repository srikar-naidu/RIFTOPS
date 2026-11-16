class_name HitboxRegion
extends Area3D
## Hurtbox region on a shootable rig (player or dummy). Lives on physics
## layer 3 (hitboxes); shot raycasts scan layers 1|3. `receiver` must expose
## take_damage_server(amount, region, attacker, weapon) -> Dictionary.

enum Region { HEAD, BODY, LEGS }

@export var region: Region = Region.BODY

var receiver: Node = null
