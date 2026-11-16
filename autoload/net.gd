extends Node
## Net (autoload singleton) — all LAN multiplayer goes through here.
##
## - ENet server/client lifecycle (server-authoritative model).
## - UDP broadcast beacon (port 27016) + listener for LAN host auto-discovery.
## - Player registry: peer_id -> {name, team, primary, secondary}, mirrored
##   to every peer via cl_players. Only the server mutates it.
##
## Other systems must never touch `multiplayer.multiplayer_peer` directly;
## they call `host_game()` / `join_game()` / `leave()` and listen to signals.

signal server_started
signal connected_to_server
signal connection_failed
signal disconnected_from_server
signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal player_list_changed
signal lan_servers_updated(servers: Array)
signal lobby_cfg_changed
signal action_denied(msg: String)

const GAME_ID := "valu"
const DEFAULT_PORT := 27015
const DISCOVERY_PORT := 27016
const MAX_PLAYERS := 10
const BEACON_INTERVAL := 1.0
const SERVER_STALE_SECS := 3.5

## peer_id -> {"name": String, "team": int, "primary": String, "secondary": String, "agent": String}
var players: Dictionary = {}
var lan_servers: Dictionary = {}
## Host's team-size setting, enforced server-side and replicated to clients.
var lobby_team_size := 5

var _beacon: PacketPeerUDP = null
var _listener: PacketPeerUDP = null
var _host_port := DEFAULT_PORT
var _beacon_accum := 0.0
var _prune_accum := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game(port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("Net: failed to host on port %d (%s)" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	players = {1: _local_info()}
	_host_port = port
	_start_beacon()
	print("[NET] hosting on port %d" % port)
	server_started.emit()
	player_list_changed.emit()
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("Net: failed to start client for %s:%d (%s)" % [address, port, error_string(err)])
		connection_failed.emit()
		return err
	multiplayer.multiplayer_peer = peer
	print("[NET] connecting to %s:%d ..." % [address, port])
	return OK


func leave() -> void:
	_stop_beacon()
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	player_list_changed.emit()


## True when this instance is the authoritative host (also true offline).
func is_server() -> bool:
	return multiplayer.is_server()


## True while an actual network session (host or client) is up.
func is_active() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not (p is OfflineMultiplayerPeer) \
		and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func my_id() -> int:
	return multiplayer.get_unique_id()


func my_info() -> Dictionary:
	return players.get(my_id(), _local_info())


func set_my_team(team: int) -> void:
	if multiplayer.is_server():
		srv_set_team(team)
	else:
		rpc_id(1, "srv_set_team", team)


func set_my_loadout(primary: String, secondary: String) -> void:
	if multiplayer.is_server():
		srv_set_loadout(primary, secondary)
	else:
		rpc_id(1, "srv_set_loadout", primary, secondary)


func set_my_agent(agent: String) -> void:
	if multiplayer.is_server():
		srv_set_agent(agent)
	else:
		rpc_id(1, "srv_set_agent", agent)


## Host-only: change the lobby team size; replicated to every client.
func set_lobby_team_size(n: int) -> void:
	if not multiplayer.is_server():
		return
	lobby_team_size = clampi(n, 1, 5)
	rpc("cl_lobby_cfg", lobby_team_size)
	lobby_cfg_changed.emit()


func team_count(team: int) -> int:
	var n := 0
	for id: int in players:
		if int(players[id].get("team", 0)) == team:
			n += 1
	return n


func _local_info() -> Dictionary:
	var agent := Cli.value("agent", AgentDB.DEFAULT_AGENT)
	return {
		"name": Settings.player_name,
		"team": GameState.Team.ATTACKERS,
		"primary": Settings.loadout_primary,
		"secondary": Settings.loadout_secondary,
		"agent": agent if AgentDB.is_valid(agent) else AgentDB.DEFAULT_AGENT,
	}


## Team auto-assign honoring the host's team-size cap. Returns Team.NONE when
## both sides are full (the join is then refused).
func _pick_team(preferred := 0) -> int:
	var a := team_count(GameState.Team.ATTACKERS)
	var b := team_count(GameState.Team.DEFENDERS)
	if preferred == GameState.Team.ATTACKERS and a < lobby_team_size:
		return GameState.Team.ATTACKERS
	if preferred == GameState.Team.DEFENDERS and b < lobby_team_size:
		return GameState.Team.DEFENDERS
	if a <= b and a < lobby_team_size:
		return GameState.Team.ATTACKERS
	if b < lobby_team_size:
		return GameState.Team.DEFENDERS
	if a < lobby_team_size:
		return GameState.Team.ATTACKERS
	return GameState.Team.NONE


func _sender_id() -> int:
	var id := multiplayer.get_remote_sender_id()
	return 1 if id == 0 else id


# --- connection callbacks ---

func _on_peer_connected(_id: int) -> void:
	pass  # registry entry is created when the peer sends srv_register


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if players.erase(id):
		rpc("cl_players", players)
		player_list_changed.emit()
		player_left.emit(id)
		print("[NET] peer %d left" % id)


func _on_connected_to_server() -> void:
	print("[NET] connected to server (my id %d)" % my_id())
	if Cli.test_mode():
		print("[TEST] connected_to_server id=%d" % my_id())
	var team_pref := 0
	match Cli.value("team", ""):
		"attacker": team_pref = GameState.Team.ATTACKERS
		"defender": team_pref = GameState.Team.DEFENDERS
	rpc_id(1, "srv_register", Settings.player_name, Settings.loadout_primary,
		Settings.loadout_secondary, Cli.value("agent", AgentDB.DEFAULT_AGENT), team_pref)
	connected_to_server.emit()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	print("[NET] server disconnected")
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	player_list_changed.emit()
	disconnected_from_server.emit()


# --- registry RPCs ---

@rpc("any_peer", "call_remote", "reliable")
func srv_register(pname: String, primary: String, secondary: String, agent := "", team_pref := 0) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	var team := _pick_team(team_pref)
	if team == GameState.Team.NONE:
		# Both teams full for the host's team size: refuse the join.
		rpc_id(id, "cl_denied", "Match is full (%dv%d)." % [lobby_team_size, lobby_team_size])
		get_tree().create_timer(0.4).timeout.connect(func() -> void:
			if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
				multiplayer.multiplayer_peer.disconnect_peer(id))
		print("[NET] peer %d refused (teams full)" % id)
		return
	players[id] = {
		"name": pname.strip_edges().substr(0, 20),
		"team": team,
		"primary": primary if WeaponDB.is_valid_primary(primary) else "vandal",
		"secondary": secondary if WeaponDB.is_valid_secondary(secondary) else "classic",
		"agent": agent if AgentDB.is_valid(agent) else AgentDB.DEFAULT_AGENT,
	}
	rpc("cl_players", players)
	rpc_id(id, "cl_lobby_cfg", lobby_team_size)
	player_list_changed.emit()
	player_joined.emit(id)
	print("[NET] peer %d registered as '%s' team %d" % [id, players[id].name, players[id].team])
	if Cli.test_mode():
		print("[TEST] peer_connected id=%d name=%s team=%d" % [id, players[id].name, players[id].team])


@rpc("any_peer", "call_remote", "reliable")
func srv_set_team(team: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	if not players.has(id) or (team != GameState.Team.ATTACKERS and team != GameState.Team.DEFENDERS):
		return
	if int(players[id].team) == team:
		return
	if team_count(team) >= lobby_team_size:
		var msg := "%s is full (%d/%d)." % [GameState.team_name(team), team_count(team), lobby_team_size]
		if id == 1:
			action_denied.emit(msg)
		else:
			rpc_id(id, "cl_denied", msg)
		return
	players[id].team = team
	rpc("cl_players", players)
	player_list_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func srv_set_agent(agent: String) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	if not players.has(id) or not AgentDB.is_valid(agent):
		return
	players[id].agent = agent
	rpc("cl_players", players)
	player_list_changed.emit()


@rpc("authority", "call_remote", "reliable")
func cl_lobby_cfg(size: int) -> void:
	lobby_team_size = size
	lobby_cfg_changed.emit()


@rpc("authority", "call_remote", "reliable")
func cl_denied(msg: String) -> void:
	action_denied.emit(msg)


@rpc("any_peer", "call_remote", "reliable")
func srv_set_loadout(primary: String, secondary: String) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	if not players.has(id):
		return
	if WeaponDB.is_valid_primary(primary):
		players[id].primary = primary
	if WeaponDB.is_valid_secondary(secondary):
		players[id].secondary = secondary
	rpc("cl_players", players)
	player_list_changed.emit()


@rpc("authority", "call_remote", "reliable")
func cl_players(d: Dictionary) -> void:
	players = d
	player_list_changed.emit()


# --- LAN discovery ---

func _start_beacon() -> void:
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_beacon_accum = BEACON_INTERVAL


func _stop_beacon() -> void:
	if _beacon != null:
		_beacon.close()
		_beacon = null


func start_discovery() -> void:
	if _listener != null:
		return
	_listener = PacketPeerUDP.new()
	var err := _listener.bind(DISCOVERY_PORT)
	if err != OK:
		push_warning("Net: discovery listen failed on %d (%s) — manual IP entry still works" % [DISCOVERY_PORT, error_string(err)])
		_listener = null


func stop_discovery() -> void:
	if _listener != null:
		_listener.close()
		_listener = null
	lan_servers.clear()


func get_lan_server_list() -> Array:
	var out: Array = []
	for ip: String in lan_servers:
		out.append(lan_servers[ip])
	return out


func _process(delta: float) -> void:
	if _beacon != null and multiplayer.is_server() and is_active():
		_beacon_accum += delta
		if _beacon_accum >= BEACON_INTERVAL:
			_beacon_accum = 0.0
			var info := {
				"game": GAME_ID,
				"name": String(players.get(1, {}).get("name", "Host")),
				"players": players.size(),
				"max": MAX_PLAYERS,
				"port": _host_port,
				"map": GameState.map_display_name(),
			}
			_beacon.put_packet(JSON.stringify(info).to_utf8_buffer())
	if _listener != null:
		var changed := false
		while _listener.get_available_packet_count() > 0:
			var pkt := _listener.get_packet()
			var ip := _listener.get_packet_ip()
			var parsed: Variant = JSON.parse_string(pkt.get_string_from_utf8())
			if parsed is Dictionary and String(parsed.get("game", "")) == GAME_ID:
				parsed["ip"] = ip
				parsed["last_seen"] = Time.get_ticks_msec()
				lan_servers[ip] = parsed
				changed = true
		_prune_accum += delta
		if _prune_accum >= 1.0:
			_prune_accum = 0.0
			var now := Time.get_ticks_msec()
			for ip: String in lan_servers.keys():
				if now - int(lan_servers[ip].last_seen) > int(SERVER_STALE_SECS * 1000.0):
					lan_servers.erase(ip)
					changed = true
		if changed:
			lan_servers_updated.emit(get_lan_server_list())
