class_name UiUtil
extends RefCounted
## Small UI helpers shared by the menus/HUD.


## Anchor a control to the center of its parent with explicit symmetric
## offsets (in logical pixels), independent of when the parent gets sized.
## Never combine PRESET_CENTER with a later `position = ...` — Control
## positions are parent-relative and turn into garbage offsets if the parent
## already has its final size (latent popup-off-screen bug).
## Anchor a control to fill its parent, with offsets explicitly zeroed.
## set_anchors_preset(PRESET_FULL_RECT) is NOT equivalent: called on a node
## already inside a sized parent it keeps the current (often 0x0) rect by
## writing compensating offsets — a latent "invisible UI" bug.
static func full_rect(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH


static func center(c: Control, w: float, h: float, x_shift := 0.0, y_shift := 0.0) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 0.5
	c.anchor_bottom = 0.5
	c.offset_left = -w * 0.5 + x_shift
	c.offset_right = w * 0.5 + x_shift
	c.offset_top = -h * 0.5 + y_shift
	c.offset_bottom = h * 0.5 + y_shift
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
