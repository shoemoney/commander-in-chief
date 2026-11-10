"""Inspect exact native bindings and rehearse a private Mac install replacement."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import time
import datetime
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FINAL = ROOT / "build/completion-audit/release/final-20261004-02"
OLD = ROOT / "build/native-current.3Qly07/CommanderInChief-macos.zip"
OLD_SHA = "6dbb702d09e860a07f36abaa184cc99e13ddb68589356641da23c38575d119fc"
USER_DIR = "Library/Application Support/Godot/app_userdata/Commander In Chief"
DIAGNOSTICS = re.compile(r"SCRIPT ERROR|Parse Error|Compile Error|(?:^|\s)ERROR:|was leaked|were leaked|resources still in use at exit", re.M)
PROBE = '''extends Node

func _ready() -> void:
	var report := {"engine": Engine.get_version_info(), "initialized_steam": false,
		"operational_methods_invoked": [], "missing": [], "passed": false,
		"auto_initialize": ProjectSettings.get_setting("steam/initialization/processes/initialize_on_startup"),
		"embed_callbacks": ProjectSettings.get_setting("steam/initialization/processes/embed_callbacks")}
	if report.auto_initialize != false or report.embed_callbacks != false:
		report.missing.append("unsafe initialization settings")
	elif not Engine.has_singleton("Steam"):
		report.missing.append("native singleton missing")
	else:
		var steam := Engine.get_singleton("Steam")
		var source := FileAccess.get_file_as_string("res://bridge.txt")
		var pattern := RegEx.new()
		pattern.compile('_call\\\\("([A-Za-z_][A-Za-z_0-9]*)"')
		var names := {}
		for hit in pattern.search_all(source):
			names[hit.get_string(1)] = true
		var methods := {}
		for entry in steam.get_method_list():
			if names.has(entry.name):
				methods[entry.name] = entry
		for name in names:
			if not methods.has(name):
				report.missing.append("method:" + name)
		var mock = load("res://mock.gd").new()
		for name in names:
			if not mock.has_method(name):
				report.missing.append("mock-method:" + name)
		for entry in mock.get_method_list():
			if not names.has(entry.name) or not methods.has(entry.name):
				continue
			var native: Dictionary = methods[entry.name]
			if entry.args.size() != native.args.size():
				report.missing.append("mock-arity:" + str(entry.name))
			else:
				for i in entry.args.size():
					if entry.args[i].type != native.args[i].type:
						report.missing.append("mock-argument-type:%s:%d" % [entry.name, i])
		pattern.compile('_call\\\\("connect", \\\\["([A-Za-z_][A-Za-z_0-9]*)"')
		var signals := {}
		for hit in pattern.search_all(source):
			var name := hit.get_string(1)
			if not steam.has_signal(name):
				report.missing.append("signal:" + name)
			if not mock.has_signal(name):
				report.missing.append("mock-signal:" + name)
			for entry in steam.get_signal_list():
				if entry.name != name:
					continue
				signals[name] = entry
				for mocked in mock.get_signal_list():
					if mocked.name != name:
						continue
					if mocked.args.size() != entry.args.size():
						report.missing.append("mock-signal-arity:" + name)
					else:
						for i in entry.args.size():
							if mocked.args[i].type != entry.args[i].type:
								report.missing.append("mock-signal-type:%s:%d" % [name, i])
		if names.is_empty() or signals.is_empty():
			report.missing.append("missing bridge inspection input")
		report.methods = methods
		report.signals = signals
		report.method_count = names.size()
		report.signal_count = signals.size()
	report.passed = report.missing.is_empty()
	var file := FileAccess.open(OS.get_environment("STEAM_API_REPORT"), FileAccess.WRITE)
	if file == null:
		print("STEAM TEMPLATE FAIL report write failed")
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(report, "\\t") + "\\n")
	file.close()
	print("STEAM TEMPLATE ", "PASS" if report.passed else "FAIL", " missing=", report.missing)
	get_tree().quit(0 if report.passed else 1)
'''


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def dump(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + "\n")


def snapshot(directory):
    if not directory.exists():
        return {}
    return {str(p.relative_to(directory)): {"sha256": sha(p), "bytes": p.stat().st_size}
            for p in sorted(directory.rglob("*")) if p.is_file() and not p.is_symlink()}


def source_check(source):
    changed = [name for name, expected in source["files"].items()
               if not (ROOT / name).is_file() or sha(ROOT / name) != expected]
    if changed:
        raise ValueError("Export source bytes changed: " + ", ".join(changed))


def extract(archive, expected, destination):
    if sha(archive) != expected:
        raise ValueError("Archive digest mismatch")
    if destination.exists():
        raise ValueError("Extraction destination already exists")
    with zipfile.ZipFile(archive) as package:
        members = package.infolist()
        names = set()
        for member in members:
            path = PurePosixPath(member.filename)
            mode = member.external_attr >> 16
            if path.is_absolute() or ".." in path.parts or "\\" in member.filename or member.filename in names:
                raise ValueError("Unsafe or duplicate ZIP member")
            if stat.S_ISLNK(mode):
                raise ValueError("ZIP symlink rejected")
            names.add(member.filename)
        if package.testzip() is not None:
            raise ValueError("Archive CRC failed")
        destination.mkdir(parents=True)
        for member in members:
            target = destination / member.filename
            if member.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with package.open(member) as source, target.open("wb") as output:
                shutil.copyfileobj(source, output)
            mode = (member.external_attr >> 16) & 0o777
            if mode:
                target.chmod(mode)
    app = next(destination.glob("*.app"))
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    return {"archive": str(archive), "archive_sha256": expected,
            "version": info["CFBundleShortVersionString"], "app_name": app.name,
            "executable_name": info["CFBundleExecutable"], "files": snapshot(destination)}


def verify_tree(directory, candidate):
    if directory.is_symlink() or any(p.is_symlink() for p in directory.rglob("*")):
        raise ValueError("Installed candidate contains a symlink")
    if snapshot(directory) != candidate["files"]:
        raise ValueError("Installed candidate differs from original archive")


def private_env(profile):
    env = os.environ.copy()
    for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        env.pop(key, None)
    env["HOME"] = str(profile.resolve())
    return env


def prepare(output):
    if output.exists():
        raise ValueError("Output already exists")
    manifests = {key: json.loads((FINAL / folder / "manifest.json").read_text())
                 for key, folder in (("stock", "native-candidates-02"), ("steam", "steam-candidates"))}
    for manifest in manifests.values():
        source_check(manifest["source_after"])
    output.mkdir(parents=True)
    candidates = {}
    for key, folder in (("current", "native-candidates-02"), ("steam", "steam-candidates")):
        manifest = manifests["stock" if key == "current" else "steam"]
        export = next(e for e in manifest["exports"] if e["platform"] == "macos")
        name, digest = next(iter(export["files"].items()))
        candidates[key] = extract(FINAL / folder / "macos" / name, digest, output / ("staged-current" if key == "current" else "steam-original"))
    candidates["old"] = extract(OLD, OLD_SHA, output / "active")
    if candidates["old"]["version"] != "0.3.0" or candidates["current"]["version"] != "1.4.4":
        raise ValueError("Unexpected upgrade versions")
    profile = output / "private-profile"
    user = profile / USER_DIR
    user.mkdir(parents=True)
    fixture = ROOT / "build/completion-audit/full-run/final-packaged-common-matrix/campaign_controller_solo"
    fixture_files = {}
    for source_name, target_name in (("campaign_controller_solo.cfg", "ikari_best.cfg"), ("campaign_controller_solo.replay", "last_run.replay")):
        source = fixture / source_name
        shutil.copy2(source, user / target_name)
        fixture_files[target_name] = {"source": str(source), "sha256": sha(source)}
    (output / "empty-cwd").mkdir()
    real_user = Path.home() / USER_DIR
    state = {"schema": 1, "active": "old", "candidates": candidates,
             "source": manifests["stock"]["source_after"], "profile": str(profile),
             "save_before": snapshot(user), "fixture_files": fixture_files,
             "actual_user_path": str(real_user), "actual_user_before": snapshot(real_user),
             "operations": [], "limitations": ["Local Mac filesystem installation, not Steam client installation.",
             "Private saved Campaign fixture was produced by 1.4.4. Loading it in the old app is an explicit downgrade compatibility observation.",
             "Native visual load must be observed separately. File parity alone does not prove Watch playback."]}
    dump(output / "state.json", state)
    print("PREPARE PASS", output)


def switch(output, selected):
    state = json.loads((output / "state.json").read_text())
    if selected == state["active"]:
        raise ValueError("Requested candidate is already active")
    for running in output.glob("native-*/running.json"):
        if (running.parent / "receipt.json").exists():
            continue
        pid = json.loads(running.read_text())["pid"]
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            continue
        raise ValueError("Native launch is still running")
    active = output / "active"
    incoming = output / ("staged-current" if selected == "current" and (output / "staged-current").exists() else "retained-" + selected)
    retained = output / ("retained-" + state["active"])
    verify_tree(active, state["candidates"][state["active"]])
    verify_tree(incoming, state["candidates"][selected])
    if retained.exists():
        raise ValueError("Retained candidate destination already exists")
    saves = snapshot(Path(state["profile"]) / USER_DIR)
    active.rename(retained)
    try:
        incoming.rename(active)
    except OSError:
        retained.rename(active)
        raise
    verify_tree(active, state["candidates"][selected])
    if snapshot(Path(state["profile"]) / USER_DIR) != saves:
        raise ValueError("Installation changed private saves")
    state["operations"].append({"operation": "replace_install", "from": state["active"], "to": selected,
                                "archive_sha256": state["candidates"][selected]["archive_sha256"], "saves_unchanged": True})
    state["active"] = selected
    dump(output / "state.json", state)
    print("INSTALL SWITCH PASS", selected)


def wait_owned_process(process, timeout, grace=10):
    result = {"timed_out": False, "signals_sent": [], "cleanup_errors": []}
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        result["timed_out"] = True
    except BaseException as error:
        result["cleanup_errors"].append(type(error).__name__ + ": " + str(error))
    finally:
        if process.poll() is None:
            try:
                process.terminate()
                result["signals_sent"].append("TERM")
            except OSError as error:
                result["cleanup_errors"].append("terminate: " + str(error))
            try:
                process.wait(timeout=grace)
            except subprocess.TimeoutExpired:
                try:
                    process.kill()
                    result["signals_sent"].append("KILL")
                except OSError as error:
                    result["cleanup_errors"].append("kill: " + str(error))
                try:
                    process.wait(timeout=grace)
                except BaseException as error:
                    result["cleanup_errors"].append("kill wait: " + str(error))
            except BaseException as error:
                result["cleanup_errors"].append("terminate wait: " + str(error))
                if process.poll() is None:
                    try:
                        process.kill()
                        result["signals_sent"].append("KILL")
                        process.wait(timeout=grace)
                    except BaseException as cleanup_error:
                        result["cleanup_errors"].append("final kill wait: " + str(cleanup_error))
        result["exit_code"] = process.poll()
        result["terminal"] = result["exit_code"] is not None
    return result


def launch(output, label, timeout):
    state = json.loads((output / "state.json").read_text())
    candidate = state["candidates"][state["active"]]
    verify_tree(output / "active", candidate)
    run = output / ("native-" + label)
    run.mkdir()
    profile = Path(state["profile"])
    before = snapshot(profile / USER_DIR)
    executable = output / "active" / candidate["app_name"] / "Contents/MacOS" / candidate["executable_name"]
    command = [str(executable), "--rendering-method", "gl_compatibility", "--resolution", "1280x720", "--position", "40,40"]
    launch_errors = []
    lifecycle = None
    with (run / "process.log").open("w") as log:
        process = subprocess.Popen(command, cwd=output / "empty-cwd", env=private_env(profile), stdout=log, stderr=subprocess.STDOUT)
        try:
            dump(run / "running.json", {"pid": process.pid, "command": command, "profile": str(profile),
                 "candidate": state["active"], "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                 "deadline_seconds": timeout, "runner_sha256": sha(Path(__file__))})
            print("NATIVE PROCESS RUNNING", process.pid, label, flush=True)
            lifecycle = wait_owned_process(process, timeout)
        except BaseException as error:
            launch_errors.append(type(error).__name__ + ": " + str(error))
        finally:
            if lifecycle is None:
                lifecycle = wait_owned_process(process, 0)
    problems = launch_errors + lifecycle["cleanup_errors"]
    if lifecycle["exit_code"] != 0 or lifecycle["timed_out"] or not lifecycle["terminal"]:
        problems.append("Native process did not exit cleanly")
    receipt = {"candidate": state["active"], "command": command, "pid": process.pid,
               **lifecycle, "problems": problems,
               "archive_sha256": candidate["archive_sha256"], "save_before": before, "native_execution": True,
               "visual_load_verified": False, "watch_playback_verified": False}
    try:
        receipt["executable_sha256"] = sha(executable)
        receipt["log_sha256"] = sha(run / "process.log")
        receipt["save_after"] = snapshot(profile / USER_DIR)
        problems.extend(DIAGNOSTICS.findall((run / "process.log").read_text(errors="replace")))
        source_check(state["source"])
    except BaseException as error:
        problems.append(type(error).__name__ + ": " + str(error))
    finally:
        dump(run / "receipt.json", receipt)
    if problems:
        raise ValueError("Native process failed: " + str(problems))
    print("NATIVE PROCESS PASS", label)


def lifetime_install_controls(output):
    destination = output / "lifetime-install-controls"
    destination.mkdir()
    outcomes = []
    ready = destination / "ignored-term-ready.txt"
    command = [sys.executable, "-c", "import signal,time,pathlib,sys; signal.signal(signal.SIGTERM,signal.SIG_IGN); pathlib.Path(sys.argv[1]).write_text('ready'); time.sleep(30)", str(ready)]
    with (destination / "ignored-term.log").open("w") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        result = None
        try:
            deadline = time.monotonic() + 5
            while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.01)
            if not ready.exists():
                raise ValueError("Ignored-TERM fixture did not become ready")
            result = wait_owned_process(process, 0.05, grace=0.05)
        finally:
            if result is None:
                result = wait_owned_process(process, 0, grace=0.05)
            dump(destination / "ignored-term-receipt.json", {"synthetic_python_child": True, "pid": process.pid,
                 "command": command, **result, "native_runtime_verified": False})
    outcomes.append({"case": "ignored-term", "passed": result["timed_out"] and result["terminal"]
                     and result["signals_sent"] == ["TERM", "KILL"] and result["exit_code"] == -9
                     and not result["cleanup_errors"]})
    install = destination / "fixture-install"
    install.mkdir()
    target = install / "original.txt"
    target.write_text("unchanged fixture bytes\n")
    candidate = {"files": snapshot(install)}
    verify_tree(install, candidate)
    (install / "extra-link").symlink_to("original.txt")
    rejected = False
    try:
        verify_tree(install, candidate)
    except ValueError as error:
        rejected = str(error) == "Installed candidate contains a symlink"
        outcomes.append({"case": "extra-install-symlink", "passed": rejected and snapshot(install) == candidate["files"],
                         "exact_error": str(error), "original_bytes_unchanged": snapshot(install) == candidate["files"]})
    dump(destination / "receipt.json", {"schema": 1, "runner_sha256": sha(Path(__file__)),
         "cases": outcomes, "native_runtime_verified": False,
         "verdict": "VERIFIED" if len(outcomes) == 2 and all(x["passed"] for x in outcomes) else "FAILED"})
    if len(outcomes) != 2 or not all(x["passed"] for x in outcomes):
        raise ValueError("Lifetime or install symlink control failed")
    print("LIFETIME AND INSTALL CONTROLS PASS; Python child and small-file fixtures only")


def finalize(output):
    state = json.loads((output / "state.json").read_text())
    source_check(state["source"])
    actual = snapshot(Path(state["actual_user_path"]))
    current = snapshot(Path(state["profile"]) / USER_DIR)
    receipts = {}
    guards = {}
    for path in output.glob("native-*/receipt.json"):
        value = json.loads(path.read_text())
        (receipts if value.get("native_execution") else guards)[path.parent.name] = value
    report = {"schema": 1, "source_current": True, "actual_user_unchanged": actual == state["actual_user_before"],
              "actual_user_progress_unchanged": all(actual.get(k) == v for k, v in state["actual_user_before"].items()
                                                   if not k.startswith(("logs/", "shader_cache/"))),
              "saved_fixture_unchanged": all(current.get(k) == v for k, v in state["save_before"].items()),
              "active": state["active"], "operations": state["operations"],
              "native_processes": receipts, "synthetic_guard_controls": guards,
              "native_install_update_rollback_verified": False,
              "native_playback_verified": False,
              "limitations": state["limitations"] + ["Native UI observations require process identity guards and separately retained visual evidence."]}
    dump(output / "install-summary.json", report)
    if not report["actual_user_unchanged"]:
        raise ValueError("Actual user tree changed; read the receipt's narrower progress-file comparison")
    print("INSTALL RECEIPT WRITTEN", output / "install-summary.json")


def observer_identity(running, rows, home):
    owned = [command for pid, command in rows if pid == running["pid"]]
    if not owned:
        raise ValueError("Owned native process is terminal")
    executable = running["command"][0]
    if len(owned) != 1 or not (owned[0] == executable or owned[0].startswith(executable + " ")):
        raise ValueError("Owned PID does not execute the selected candidate")
    native = [pid for pid, command in rows if command.startswith("/") and "/Commander In Chief.app/Contents/MacOS/Commander In Chief" in command]
    if native != [running["pid"]]:
        raise ValueError("Native app observation is ambiguous")
    if home != str(Path(running["profile"]).resolve()):
        raise ValueError("Owned native process has the wrong HOME")
    return {"pid": running["pid"], "command": owned[0], "home": home, "only_native_app": True}


def observe_guard(output, label):
    run = output / ("native-" + label)
    running = json.loads((run / "running.json").read_text())
    if (run / "receipt.json").exists():
        raise ValueError("Native process already has a terminal receipt; no UI observation allowed")
    listing = subprocess.check_output(["ps", "-axo", "pid=,command="], text=True)
    rows = [(int(fields[0]), fields[1]) for line in listing.splitlines() if len(fields := line.strip().split(None, 1)) == 2]
    process_env = subprocess.run(["ps", "eww", "-p", str(running["pid"]), "-o", "command="], capture_output=True, text=True)
    match = re.search(r"(?:^|\s)HOME=(.*?)(?=\s[A-Za-z_][A-Za-z_0-9]*=|$)", process_env.stdout)
    home = match.group(1).strip() if match else None
    identity = observer_identity(running, rows, home)
    state = json.loads((output / "state.json").read_text())
    verify_tree(output / "active", state["candidates"][running["candidate"]])
    number = len(list(run.glob("observer-guard-*.json"))) + 1
    identity["utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    identity["scope"] = "Read-only OS liveness and executable/profile guard. This does not itself bind a CUA target to a PID."
    dump(run / ("observer-guard-%03d.json" % number), identity)
    print("OBSERVER HANDLE PASS", running["pid"], "one selected native app, expected private HOME")


def observer_controls(output):
    executable = "/private/rehearsal/Commander In Chief.app/Contents/MacOS/Commander In Chief"
    profile = "/private/rehearsal/profile"
    running = {"pid": 41, "command": [executable], "profile": profile}
    good = [(41, executable + " --resolution 1280x720")]
    assert observer_identity(running, good, profile)["pid"] == 41
    cases = [("terminal-handle", [], profile, "Owned native process is terminal"),
             ("reused-pid", [(41, "/usr/bin/python3 unrelated")], profile, "Owned PID does not execute the selected candidate"),
             ("duplicate-app", good + [(42, executable)], profile, "Native app observation is ambiguous"),
             ("wrong-profile", good, "/Users/example", "Owned native process has the wrong HOME")]
    results = []
    for name, rows, home, expected in cases:
        try:
            observer_identity(running, rows, home)
            raise AssertionError("Observer accepted " + name)
        except ValueError as error:
            if str(error) != expected:
                raise AssertionError(str(error))
            results.append({"case": name, "rejected": True, "exact_error": str(error)})
    dump(output / "observer-controls.json", {"synthetic_metadata_fixtures": True,
         "positive": True, "rejections": results, "native_runtime_verified": False})
    print("OBSERVER CONTROLS PASS; synthetic metadata fixtures only")


def controls(output):
    destination = output / "archive-negative-controls"
    suffix = 2
    while destination.exists():
        destination = output / ("archive-negative-controls-" + str(suffix))
        suffix += 1
    destination.mkdir()
    state = json.loads((output / "state.json").read_text())
    active_before = snapshot(output / "active")
    saves_before = snapshot(Path(state["profile"]) / USER_DIR)
    original = FINAL / "native-candidates-02/macos/CommanderInChief-macos.zip"
    digest = state["candidates"]["current"]["archive_sha256"]
    damaged = destination / "truncated-candidate.zip"
    with original.open("rb") as source:
        damaged.write_bytes(source.read(1024))
    outcomes = []
    for name, archive, expected in (("wrong-digest", original, "0" * 64), ("truncated-package", damaged, digest)):
        target = destination / (name + "-install")
        try:
            extract(archive, expected, target)
        except ValueError as error:
            outcomes.append({"case": name, "rejected": str(error) == "Archive digest mismatch", "error": str(error), "wrote_install": target.exists()})
    unsafe = destination / "unsafe.zip"
    with zipfile.ZipFile(unsafe, "w") as package:
        package.writestr("../outside.txt", "must not escape")
    target = destination / "unsafe-install"
    try:
        extract(unsafe, sha(unsafe), target)
    except ValueError as error:
        outcomes.append({"case": "path-traversal", "rejected": str(error) == "Unsafe or duplicate ZIP member", "error": str(error), "wrote_install": target.exists()})
    unchanged = {"active_install_unchanged": snapshot(output / "active") == active_before,
                 "private_saves_unchanged": snapshot(Path(state["profile"]) / USER_DIR) == saves_before}
    dump(destination / "receipt.json", {"cases": outcomes, **unchanged})
    if len(outcomes) != 3 or any(not x["rejected"] or x["wrote_install"] for x in outcomes) or not all(unchanged.values()):
        raise ValueError("Archive controls failed")
    print("ARCHIVE NEGATIVE CONTROLS PASS")


def binding_prepare(output):
    state = json.loads((output / "state.json").read_text())
    source_check(state["source"])
    binding = output / "binding"
    binding.mkdir()
    origins = {}
    for key, directory in (("steam", "steam-original"), ("stock", "staged-current")):
        candidate = state["candidates"]["steam" if key == "steam" else "current"]
        app = output / directory / candidate["app_name"]
        origins[key] = app / "Contents/MacOS" / candidate["executable_name"]
    library = next((output / "steam-original").rglob("libsteam_api.dylib"))
    for name, engine in (("positive", "steam"), ("absent-singleton", "stock"), ("absent-method", "steam")):
        run = binding / name
        run.mkdir()
        executable = run / "SteamProbe"
        shutil.copy2(origins[engine], executable)
        if engine == "steam":
            shutil.copy2(library, run / library.name)
    for name in ("positive", "absent-method"):
        project = binding / (name + "-project")
        shutil.copytree(ROOT / "tools/steam_template_probe", project)
        shutil.copy2(ROOT / "src/steam/steam_bridge.gd", project / "bridge.txt")
        shutil.copy2(ROOT / "tests/mock_steam_singleton.gd", project / "mock.gd")
        (project / "probe.gd").write_text(PROBE)
        if name == "absent-method":
            with (project / "bridge.txt").open("a") as stream:
                stream.write('\n_call("cic_missing_release_control_20261004")\n')
            with (project / "mock.gd").open("a") as stream:
                stream.write('\nfunc cic_missing_release_control_20261004() -> void:\n\tpass\n')
    dump(binding / "inputs.json", {"steam_archive_sha256": state["candidates"]["steam"]["archive_sha256"],
         "stock_archive_sha256": state["candidates"]["current"]["archive_sha256"],
         "steam_executable_sha256": sha(origins["steam"]), "stock_executable_sha256": sha(origins["stock"]),
         "steam_library_sha256": sha(library), "bridge_sha256": sha(ROOT / "src/steam/steam_bridge.gd"),
         "mock_sha256": sha(ROOT / "tests/mock_steam_singleton.gd"),
         "scope": "Unchanged exact exported engines run a separate adjacent inspection PCK. No game or bridge instance, operational Steam calls, initialization, or callbacks."})
    print("BINDING PREPARE PASS", binding)


def binding_run(output, godot):
    state = json.loads((output / "state.json").read_text())
    source_check(state["source"])
    binding = output / "binding"
    inputs = json.loads((binding / "inputs.json").read_text())
    if sha(ROOT / "src/steam/steam_bridge.gd") != inputs["bridge_sha256"] or sha(ROOT / "tests/mock_steam_singleton.gd") != inputs["mock_sha256"]:
        raise ValueError("Binding inspection inputs changed")
    commands = []
    profile = binding / "private-profile"
    profile.mkdir()
    env = private_env(profile)
    for key in ("SteamAppId", "SteamGameId", "SteamAppID"):
        env.pop(key, None)
    for name in ("positive", "absent-method"):
        project = binding / (name + "-project")
        for step, arguments in (("import", ["--import"]), ("export", ["--export-pack", "Probe", str(binding / name / "SteamProbe.pck")])):
            command = [str(godot), "--headless", "--path", str(project)] + arguments
            log = binding / (name + "-" + step + ".log")
            result = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=90)
            log.write_text(result.stdout)
            commands.append({"command": command, "exit_code": result.returncode, "log_sha256": sha(log)})
            if result.returncode or DIAGNOSTICS.search(result.stdout):
                raise ValueError("Inspection project import or export failed")
    shutil.copy2(binding / "positive/SteamProbe.pck", binding / "absent-singleton/SteamProbe.pck")
    results = []
    for name in ("positive", "absent-singleton", "absent-method"):
        run = binding / name
        expected_engine = inputs["stock_executable_sha256" if name == "absent-singleton" else "steam_executable_sha256"]
        if sha(run / "SteamProbe") != expected_engine:
            raise ValueError("Probe executable differs from exported engine")
        if name != "absent-singleton" and sha(run / "libsteam_api.dylib") != inputs["steam_library_sha256"]:
            raise ValueError("Probe library differs from exported library")
        env["STEAM_API_REPORT"] = str(run / "reflection.json")
        command = [str(run / "SteamProbe"), "--headless"]
        result = subprocess.run(command, cwd=run, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60)
        (run / "process.log").write_text(result.stdout)
        report = json.loads((run / "reflection.json").read_text())
        expected_missing = [] if name == "positive" else ["native singleton missing" if name == "absent-singleton" else "method:cic_missing_release_control_20261004"]
        passed = result.returncode == (0 if name == "positive" else 1) and report["missing"] == expected_missing
        passed = passed and not DIAGNOSTICS.search(result.stdout) and report["auto_initialize"] is False and report["embed_callbacks"] is False
        if name == "positive":
            passed = passed and report["method_count"] == 22 and report["signal_count"] == 5
        results.append({"case": name, "verdict": "VERIFIED" if passed else "FAILED", "exit_code": result.returncode,
                        "command": command, "pack_sha256": sha(run / "SteamProbe.pck"), "executable_sha256": sha(run / "SteamProbe"),
                        "log_sha256": sha(run / "process.log"), "reflection_sha256": sha(run / "reflection.json"),
                        "missing": report["missing"]})
    source_check(state["source"])
    if sha(ROOT / "tests/mock_steam_singleton.gd") != inputs["mock_sha256"]:
        raise ValueError("Binding mock changed during inspection")
    dump(binding / "summary.json", {"schema": 1, "inputs": inputs, "commands": commands, "cases": results,
         "source_current": True, "initialized_steam": False, "live_account_verified": False,
         "verdict": "VERIFIED" if all(x["verdict"] == "VERIFIED" for x in results) else "FAILED"})
    if any(x["verdict"] != "VERIFIED" for x in results):
        raise ValueError("Native binding contract failed")
    print("EXACT NATIVE BINDING PASS with two precise negative controls")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("prepare", "switch", "launch", "finalize", "controls", "binding-prepare", "binding-run", "observe-guard", "observer-controls", "lifetime-install-controls"))
    parser.add_argument("output", type=Path)
    parser.add_argument("--to", choices=("old", "current"))
    parser.add_argument("--label")
    parser.add_argument("--timeout", type=float, default=900)
    parser.add_argument("--godot", type=Path, default=Path("/Applications/Godot.app/Contents/MacOS/Godot"))
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / "build/completion-audit/remaining-release"):
        parser.error("Only a new remaining-release output directory is allowed")
    if args.operation == "prepare":
        prepare(output)
    elif args.operation == "switch":
        if args.to is None:
            parser.error("--to is required")
        switch(output, args.to)
    elif args.operation == "launch":
        if args.label is None or not re.fullmatch(r"[a-z0-9-]+", args.label):
            parser.error("--label requires lowercase letters, digits, and hyphens")
        launch(output, args.label, args.timeout)
    elif args.operation == "controls":
        controls(output)
    elif args.operation == "binding-prepare":
        binding_prepare(output)
    elif args.operation == "binding-run":
        binding_run(output, args.godot)
    elif args.operation == "observe-guard":
        if args.label is None or not re.fullmatch(r"[a-z0-9-]+", args.label):
            parser.error("--label requires lowercase letters, digits, and hyphens")
        observe_guard(output, args.label)
    elif args.operation == "observer-controls":
        observer_controls(output)
    elif args.operation == "lifetime-install-controls":
        lifetime_install_controls(output)
    else:
        finalize(output)
