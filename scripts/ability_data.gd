class_name AbilityData
extends Resource
## Static definition of one agent ability (see agents/*.tres).
## Behavior numbers (radii, durations, damage) live in the server-side
## executor (scripts/effects_manager.gd) keyed by ability id; this resource
## carries identity + shop/charge data used by the buy menu and HUD.

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
## Credits per charge in the buy menu. Signature abilities are not purchasable.
@export var cost: int = 200
@export var max_charges: int = 1
## Signature abilities refill to at least 1 charge at the start of every round.
@export var signature: bool = false
## Reserved for abilities with in-round cooldowns (unused by the v1 kits).
@export var cooldown: float = 0.0
## True for map-targeted casts (opens the top-down targeting overlay).
@export var map_targeted: bool = false
## HUD accent color (also used for placeholder icons).
@export var icon_color: Color = Color(0.8, 0.85, 0.9)
