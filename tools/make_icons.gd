extends SceneTree
## Dev tool: rasterize the SVG icon sources into the PNGs the Android export
## preset references (launcher + adaptive icons). Run headless:
##   godot --headless --path . --script res://tools/make_icons.gd

const JOBS := [
	["res://icon.svg", "res://assets/icons/icon_main_192.png", 192],
	["res://assets/icons/icon_fg.svg", "res://assets/icons/icon_fg_432.png", 432],
	["res://assets/icons/icon_bg.svg", "res://assets/icons/icon_bg_432.png", 432],
	["res://assets/icons/icon_mono.svg", "res://assets/icons/icon_mono_432.png", 432],
]


func _init() -> void:
	var ok := true
	for job: Array in JOBS:
		ok = _rasterize(String(job[0]), String(job[1]), int(job[2])) and ok
	quit(0 if ok else 1)


func _rasterize(src: String, dst: String, size: int) -> bool:
	var svg := FileAccess.get_file_as_string(src)
	if svg == "":
		push_error("cannot read %s" % src)
		return false
	var img := Image.new()
	var err := img.load_svg_from_string(svg, float(size) / 432.0)
	if err != OK:
		push_error("svg rasterize failed for %s: %d" % [src, err])
		return false
	if img.get_width() != size or img.get_height() != size:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	err = img.save_png(ProjectSettings.globalize_path(dst))
	print("ICON %s -> %s (%dx%d) err=%d" % [src, dst, size, size, err])
	return err == OK
