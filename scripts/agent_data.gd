class_name AgentData
extends Resource
## Static definition of one playable agent (see agents/*.tres).
## abilities[0..2] bind to input actions ability_1 (Q), ability_2 (E),
## ability_3 (X) in that order.

@export var id: StringName = &""
@export var display_name: String = ""
@export var role: String = ""
@export var description: String = ""
## Third-person character model (Quaternius GLTF; mapping in docs/CONVENTIONS.md).
@export var model_path: String = ""
@export var tint: Color = Color(0.8, 0.85, 0.9)
## Exactly 3 AbilityData entries (untyped Array for simple .tres serialization).
@export var abilities: Array = []


func ability(slot: int) -> AbilityData:
	if slot < 0 or slot >= abilities.size():
		return null
	return abilities[slot] as AbilityData
