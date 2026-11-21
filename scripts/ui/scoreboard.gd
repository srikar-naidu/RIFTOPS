class_name Scoreboard
extends Control
## Match scoreboard (hold Tab; auto-shown between rounds / at match end in
## Spike mode). Per player: agent, name, K/D/A, credits, spike-carrier icon;
## team sections show round score + current side.

var _panel: PanelContainer
var _rows_box: VBoxContainer


static func _font() -> Font:
	var p := "res://assets/fonts/Rajdhani-SemiBold.ttf"
	if ResourceLoader.exists(p):
		return load(p)
	return null


func _mk_label(text: String, size_px: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	var f := _font()
	if f != null:
		l.add_theme_font_override("font", f)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _ready() -> void:
	UiUtil.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.04, 0.06, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_panel = PanelContainer.new()
	UiUtil.center(_panel, 720, 480)
	_panel.custom_minimum_size = Vector2(720, 480)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 4)
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_rows_box)
	GameState.stats_changed.connect(_maybe_refresh)
	GameState.economy_changed.connect(_maybe_refresh)
	GameState.spike_changed.connect(_maybe_refresh)
	GameState.team_scores_changed.connect(_maybe_refresh)
	Net.player_list_changed.connect(_maybe_refresh)


func open() -> void:
	visible = true
	_refresh()


func close() -> void:
	visible = false


func _maybe_refresh() -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	for c in _rows_box.get_children():
		c.free()
	if GameState.mode == GameState.Mode.FFA:
		_ffa_rows()
		return
	var title := _mk_label("SCOREBOARD — ROUND %d" % maxi(GameState.round_number, 1), 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows_box.add_child(title)
	if GameState.mode == GameState.Mode.SPIKE:
		_add_team_section(GameState.Team.ATTACKERS, GameState.score_att)
		_add_team_section(GameState.Team.DEFENDERS, GameState.score_def)
	else:
		_add_team_section(GameState.Team.ATTACKERS, GameState.kills_a)
		_add_team_section(GameState.Team.DEFENDERS, GameState.kills_b)


func _add_team_section(team: int, score: int) -> void:
	_rows_box.add_child(HSeparator.new())
	var side := "ATK" if team == GameState.Team.ATTACKERS else "DEF"
	var mine := GameState.local_player != null and int(GameState.local_player.team) == team
	var header := _mk_label("%s  [%s]%s   —   %d" % [
		GameState.team_name(team).to_upper(), side, "  (YOUR TEAM)" if mine else "", score],
		22, GameState.team_color(team))
	_rows_box.add_child(header)
	var head_row := _mk_label("    AGENT        PLAYER                    K / D / A        CREDITS", 15, Color(0.55, 0.6, 0.66))
	_rows_box.add_child(head_row)
	var ids: Array = Net.players.keys()
	ids.sort()
	for id: int in ids:
		var info: Dictionary = Net.players[id]
		if int(info.get("team", 0)) != team:
			continue
		var st: Dictionary = GameState.stats.get(id, {"k": 0, "d": 0, "a": 0})
		var agent := AgentDB.get_agent(StringName(String(info.get("agent", "gale"))))
		var carrier := GameState.mode == GameState.Mode.SPIKE \
			and int(GameState.spike.get("carrier", 0)) == id \
			and int(GameState.spike.get("state", -1)) == GameState.SpikeState.CARRIED
		var row := _mk_label("    %-12s %-22s %2d / %2d / %2d       ¤ %-6d %s%s" % [
			agent.display_name if agent != null else "?",
			String(info.get("name", "?")) + (" [HOST]" if id == 1 else ""),
			int(st.k), int(st.d), int(st.a),
			int(GameState.economy.get(id, 0)) if GameState.mode == GameState.Mode.SPIKE else 0,
			"⦿ " if carrier else "",
			"◄ YOU" if id == Net.my_id() else ""],
			17, Color(1, 1, 1) if id != Net.my_id() else Color(0.95, 0.9, 0.5))
		_rows_box.add_child(row)

func _ffa_rows() -> void:
	_rows_box.add_child(_mk_label("FREE FOR ALL / TESTSITE-07", 28, Color("e1ed53")))
	_rows_box.add_child(_mk_label("PLAYER                              KILLS     DEATHS     K/D", 18))
	var ids: Array = Net.players.keys()
	ids.sort_custom(func(a: int, b: int) -> bool:
		var sa: Dictionary = GameState.stats.get(a, {"k":0,"d":0})
		var sb: Dictionary = GameState.stats.get(b, {"k":0,"d":0})
		return int(sa.k)>int(sb.k) if int(sa.k)!=int(sb.k) else int(sa.d)<int(sb.d))
	for id: int in ids:
		var st: Dictionary = GameState.stats.get(id, {"k":0,"d":0})
		_rows_box.add_child(_mk_label("%-24s       %d          %d         %.2f" % [String(Net.players[id].name).left(20),int(st.k),int(st.d),float(st.k)/maxi(int(st.d),1)],22,Color("e1ed53") if id == Net.my_id() else Color.WHITE))
