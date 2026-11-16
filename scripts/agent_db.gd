class_name AgentDB
extends RefCounted
## Static registry of all agent resources.
## Agent -> character model mapping is documented in docs/CONVENTIONS.md.

const ALL: Dictionary = {
	&"gale": preload("res://agents/gale.tres"),
	&"ember": preload("res://agents/ember.tres"),
	&"warden": preload("res://agents/warden.tres"),
	&"flint": preload("res://agents/flint.tres"),
}

const IDS: Array[StringName] = [&"gale", &"ember", &"warden", &"flint"]
const DEFAULT_AGENT := "gale"


static func get_agent(id: StringName) -> AgentData:
	return ALL.get(id, null)


static func is_valid(id: String) -> bool:
	return ALL.has(StringName(id))


static func ability(agent_id: String, slot: int) -> AbilityData:
	var a := get_agent(StringName(agent_id))
	return a.ability(slot) if a != null else null
