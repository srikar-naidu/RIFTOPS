class_name WeaponDB
extends RefCounted
## Static registry of all weapon resources.

const ALL: Dictionary = {
	&"knife": preload("res://weapons/knife.tres"),
	&"classic": preload("res://weapons/classic.tres"),
	&"sheriff": preload("res://weapons/sheriff.tres"),
	&"spectre": preload("res://weapons/spectre.tres"),
	&"phantom": preload("res://weapons/phantom.tres"),
	&"vandal": preload("res://weapons/vandal.tres"),
	&"operator": preload("res://weapons/operator.tres"),
}

const PRIMARIES: Array[StringName] = [&"spectre", &"phantom", &"vandal", &"operator"]
const SECONDARIES: Array[StringName] = [&"classic", &"sheriff"]


static func get_weapon(id: StringName) -> WeaponData:
	return ALL.get(id, null)


static func is_valid_primary(id: String) -> bool:
	return PRIMARIES.has(StringName(id))


static func is_valid_secondary(id: String) -> bool:
	return SECONDARIES.has(StringName(id))
