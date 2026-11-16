class_name Cli
extends RefCounted
## Parses user CLI args (everything after "--" on the Godot command line).
## Test/dev hooks, documented in docs/CONVENTIONS.md:
##   --host [--map graybox] [--start-when N] [--tdm-target N] [--port N]
##   --join <ip> [--port N]
##   --name <player name>  --seed <int>
##   --spawn-dummy --test-shot --autoquit <seconds>
## Spike-mode hooks (Phase 3):
##   --mode <tdm|spike>           autostart mode for --host
##   --spike-fast                 short timers (buy 3s, live 20s, detonate 15s, end 2s)
##   --buy-time/--live-time/--detonate-time N   explicit timer overrides (secs)
##   --rounds-to-win N            first-to-N (halftime after N-1)
##   --carrier <peer_id>          force the spike carrier each round
##   --team <attacker|defender>   join-time team preference
##   --agent <id>                 agent pick (gale/ember/warden/flint)
##   --spike-script <a|b>         scripted scenarios (see tests/spike_test.sh)

static var _args: Dictionary = {}
static var _parsed := false


static func _parse() -> void:
	if _parsed:
		return
	_parsed = true
	var raw := OS.get_cmdline_user_args()
	var i := 0
	while i < raw.size():
		var a := raw[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			var val := ""
			if key.contains("="):
				val = key.get_slice("=", 1)
				key = key.get_slice("=", 0)
			elif i + 1 < raw.size() and not raw[i + 1].begins_with("--"):
				val = raw[i + 1]
				i += 1
			_args[key] = val
		i += 1


static func has_flag(name: String) -> bool:
	_parse()
	return _args.has(name)


static func value(name: String, default := "") -> String:
	_parse()
	var v := String(_args.get(name, ""))
	return v if v != "" else default


static func value_int(name: String, default: int) -> int:
	_parse()
	var v := String(_args.get(name, ""))
	return int(v) if v.is_valid_int() else default


static func test_mode() -> bool:
	return has_flag("autoquit") or has_flag("spawn-dummy") or has_flag("test-shot")
