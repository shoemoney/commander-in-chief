extends SceneTree
## replay-validated-leaderboards: headless anti-cheat gate for a submitted
## Daily/Endless leaderboard replay. Loads a .replay file, re-simulates its
## recorded inputs from scratch (the deterministic sim is the only source of
## truth), and confirms the score it actually produces matches the score the
## file claims. This is the same check Replay.save_and_verify runs
## automatically on every local save; run this one against a replay a player
## submitted from elsewhere before trusting its score on a shared board.
##
## The decision itself lives in Replay.validate_file() (unit-tested in
## tests/test_leaderboard.gd) -- this script is just its CLI shell: parse the
## arg, print a human-readable line, exit with the matching code.
##
## Run:  godot --headless -s res://tools/validate_replay.gd -- <replay_path>
## Exit codes:
##   0 = score verified
##   1 = missing or malformed replay file (can't even attempt verification)
##   2 = loaded fine but CHEAT DETECTED -- the recorded inputs do not earn
##       the score the file claims
##   3 = replay format/ruleset is recognized but unsupported by this build

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: godot --headless -s res://tools/validate_replay.gd -- <replay_path>")
		quit(1)
		return
	var result := Replay.validate_file(args[0])
	match result["code"]:
		0:
			print("VALID mode=%s score=%d frames=%d" % [result["mode"], result["score"], result["frames"]])
		1:
			printerr("VALIDATION FAILED: could not load replay '%s'" % args[0])
		2:
			printerr("CHEAT DETECTED: claimed=%d actual=%d -- replay's recorded inputs do not earn the claimed score"
				% [result["claimed"], result["actual"]])
		3:
			# A replay from another simulation ruleset cannot be judged by this
			# executable. This is a compatibility result, never evidence of tampering.
			printerr("UNSUPPORTED REPLAY VERSION/RULESET: this build cannot validate '%s'; use a compatible game build"
				% args[0])
		_:
			# Replay.validate_file() only returns the documented codes above today. This
			# branch exists
			# so an unrecognized future code fails LOUD (exit 1, "can't verify") instead
			# of silently falling through to the success-printing path.
			printerr("VALIDATION FAILED: unrecognized result code %s from Replay.validate_file()" % [result.get("code", "?")])
			quit(1)
			return
	quit(result["code"])
