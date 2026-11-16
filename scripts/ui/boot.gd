extends Control
## Boot / frontend controller: swaps between main menu and lobby, wires Net
## signals, and drives the CLI test hooks (--host / --join, auto-start).

const MAIN_MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const LOBBY_SCENE := preload("res://scenes/ui/lobby.tscn")

var menu: Control
var lobby: Control

var _auto_map := ""
var _start_when := 0
var _auto_started := false
var _join_ip := ""
var _join_attempts := 0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.07, 0.09, 0.12)
	add_child(bg)
	menu = MAIN_MENU_SCENE.instantiate()
	add_child(menu)
	lobby = LOBBY_SCENE.instantiate()
	add_child(lobby)
	menu.host_requested.connect(_on_host_requested)
	menu.join_requested.connect(_on_join_requested)
	lobby.leave_requested.connect(_on_lobby_leave)
	Net.connected_to_server.connect(_show_lobby)
	Net.connection_failed.connect(_on_connection_failed)
	Net.disconnected_from_server.connect(_on_server_lost)
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if Net.is_active():
		_show_lobby()  # back from a match, session still up
	else:
		_show_menu()
	_handle_cli()


static func map_path_for(map_name: String) -> String:
	return "res://maps/%s/%s.tscn" % [map_name, map_name]


func _handle_cli() -> void:
	if Cli.has_flag("host"):
		_auto_map = map_path_for(Cli.value("map", "graybox"))
		_start_when = maxi(Cli.value_int("start-when", 2), 1)
		var err := Net.host_game(Cli.value_int("port", Net.DEFAULT_PORT))
		if err != OK:
			print("[TEST] FAIL host error %s" % error_string(err))
			if Cli.test_mode():
				get_tree().quit(6)
			return
		if Cli.test_mode():
			print("[TEST] server_started port=%d" % Cli.value_int("port", Net.DEFAULT_PORT))
		_show_lobby()
		Net.player_list_changed.connect(_check_autostart)
		_check_autostart()
	elif Cli.has_flag("join"):
		_join_ip = Cli.value("join", "127.0.0.1")
		_join_attempts = 10
		_try_join()


func _check_autostart() -> void:
	if _auto_started or _auto_map == "" or not multiplayer.is_server():
		return
	if Net.players.size() >= _start_when:
		_auto_started = true
		var mode := GameState.Mode.SPIKE if Cli.value("mode", "tdm") == "spike" else GameState.Mode.TDM
		GameState.host_start_match(_auto_map, mode, Net.lobby_team_size, Cli.value_int("tdm-target", GameState.TDM_TARGET_KILLS))


func _try_join() -> void:
	Net.join_game(_join_ip, Cli.value_int("port", Net.DEFAULT_PORT))


func _on_connection_failed() -> void:
	if _join_attempts > 0:
		_join_attempts -= 1
		print("[NET] connection failed, retrying (%d left)..." % _join_attempts)
		get_tree().create_timer(1.5).timeout.connect(_try_join)
		return
	_show_menu()
	menu.set_status("Connection failed.")


func _on_server_lost() -> void:
	GameState.reset_match_state()
	_show_menu()
	menu.set_status("Disconnected from host.")


func _on_host_requested() -> void:
	if Net.host_game() == OK:
		_show_lobby()
	else:
		menu.set_status("Could not start server (port in use?).")


func _on_join_requested(ip: String) -> void:
	_join_attempts = 0
	menu.set_status("Connecting to %s ..." % ip)
	Net.join_game(ip)


func _on_lobby_leave() -> void:
	Net.leave()
	_show_menu()


func _show_menu() -> void:
	menu.visible = true
	lobby.visible = false


func _show_lobby() -> void:
	menu.visible = false
	lobby.visible = true
