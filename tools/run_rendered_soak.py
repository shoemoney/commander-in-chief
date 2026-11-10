"""Run real-time rendered production replay cycles with isolated profiles and receipts."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import time

from run_completion_checks import ROOT, changed_sources, contract_problems, source_hashes
from verify_runtime_log import check_log

FIXTURES = ROOT / "build/completion-audit/full-run/final-common-matrix-04"
ENGINE = Path("/Applications/Godot.app/Contents/MacOS/Godot")
CAMPAIGNS = ("campaign_controller_solo", "campaign_controller_coop", "arcade_controller_solo")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dependencies() -> dict[str, str]:
    result = source_hashes()
    for name in ("tools/run_rendered_soak.py", "tools/verify_rendered_soak.gd", "tools/verify_rendered_soak.gd.uid", "tools/verify_runtime_log.py", "icon.png", "icon.png.import", "override.cfg", "default_bus_layout.tres"):
        path = ROOT / name
        if path.exists():
            result[name] = sha(path)
    for path in (ROOT / "locale").rglob("*"):
        if path.is_file():
            result[str(path.relative_to(ROOT))] = sha(path)
    return result


def write_json(path: Path, data: dict) -> None:
    temporary = path.with_name(path.name + ".writing")
    temporary.write_text(json.dumps(data, indent=2) + "\n")
    temporary.replace(path)


def coverage_problems(rows: list[dict], start: float, end: float, label: str) -> list[str]:
    times = [row.get("elapsed_seconds") for row in rows]
    if not times or any(not isinstance(value, (int, float)) or not math.isfinite(value) for value in times):
        return [f"missing or invalid {label} sample coverage"]
    if times[0] - start > 7.5 or end - times[-1] > 7.5 or any(b <= a or b - a > 7.5 for a, b in zip(times, times[1:])):
        return [f"incomplete or nonmonotonic {label} sample coverage"]
    return []


def memory_gate(samples: list[dict], process_samples: list[dict], elapsed_seconds: float) -> dict:
    problems = coverage_problems(samples, 0, elapsed_seconds, "engine")
    process_samples = [row for row in process_samples if row["elapsed_seconds"] >= 0]
    problems.extend(coverage_problems(process_samples, 0, elapsed_seconds, "OS resident memory"))
    warm = [row for row in samples if row["completed_replays"] >= 3]
    if not warm:
        return {"verified": False, "problems": problems + ["no three-replay warmed memory baseline"]}
    warm_end = warm[0]["elapsed_seconds"] + 180
    baseline = [row for row in warm if row["elapsed_seconds"] <= warm_end]
    late = [row for row in warm if row["elapsed_seconds"] > warm_end]
    if not late:
        return {"verified": False, "problems": problems + ["no sustained measurements after warmed baseline"]}
    problems.extend(coverage_problems(baseline, warm[0]["elapsed_seconds"], warm_end, "180-second warmed baseline"))
    problems.extend(coverage_problems(late, warm_end, elapsed_seconds, "post-warm engine"))
    allowances = {"static_memory_bytes": 16 * 1024 * 1024, "objects": 128, "resources": 32, "nodes": 8, "orphan_nodes": 0}
    peaks = {}
    for field, allowance in allowances.items():
        initial = max(row[field] for row in baseline)
        observed = max(row[field] for row in late)
        peaks[field] = {"warmed_peak": initial, "later_peak": observed, "allowance": allowance}
        if observed > initial + allowance:
            problems.append(f"{field} exceeded declared warmed ceiling")
    rss_before = [row for row in process_samples if warm[0]["elapsed_seconds"] <= row["elapsed_seconds"] <= warm_end]
    rss_after = [row for row in process_samples if row["elapsed_seconds"] > warm_end]
    if not rss_before or not rss_after:
        problems.append("missing warmed OS resident-memory samples")
    else:
        problems.extend(coverage_problems(rss_before, warm[0]["elapsed_seconds"], warm_end, "warmed OS resident memory"))
        problems.extend(coverage_problems(rss_after, warm_end, elapsed_seconds, "post-warm OS resident memory"))
        initial = max(row["rss_bytes"] for row in rss_before)
        observed = max(row["rss_bytes"] for row in rss_after)
        allowance = 128 * 1024 * 1024
        peaks["os_rss_bytes"] = {"warmed_peak": initial, "later_peak": observed, "allowance": allowance}
        if observed > initial + allowance:
            problems.append("OS resident memory exceeded declared warmed ceiling")
    return {"verified": not problems, "warm_window_seconds": 180, "first_warmed_sample_seconds": warm[0]["elapsed_seconds"], "baseline_samples": len(baseline), "later_samples": len(late), "peaks": peaks, "problems": problems}


def run(args: argparse.Namespace) -> dict:
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    profile = output / "profile"
    profile.mkdir()
    before = dependencies()
    cases = []
    names = ("endless_controller_solo",) if args.pilot else CAMPAIGNS
    for name in names:
        report_path = FIXTURES / (name + ".json")
        original = json.loads(report_path.read_text())
        if original.get("verdict") != "VERIFIED" or contract_problems(name, original):
            raise ValueError("soak requires an originally verified normal fixture")
        original_replay = FIXTURES / (name + (".partial.replay" if args.pilot else ".replay"))
        envelope = json.loads(original_replay.read_text())
        expected_config = {"magic": "DETERMINISTIC_REPLAY_2", "ruleset": 1, "seed": original["seed"], "mode": original["mode"], "players": original["player_count"], "assist": False, "hard": False, "chapter": 1, "start_vest": False, "start_chest": 0, "start_tokens": 0, "score": original["end_state"]["score"], "verified": not args.pilot, "slow_mode": False}
        if any(envelope.get(key, False if key == "slow_mode" else None) != value for key, value in expected_config.items()) or len(envelope.get("frames", [])) != original["replay"]["frames"] or any(len(frame) != original["player_count"] for frame in envelope["frames"]) or any(change.get("settings", {}).get("slow_mode", False) for change in envelope.get("accessibility_changes", [])):
            raise ValueError("fixture replay mode, players, seed, configuration or recorded count mismatch")
        destination = output / original_replay.name
        destination.write_bytes(original_replay.read_bytes())
        end = original["end_state"]
        cases.append({"name": name, "replay": str(destination), "replay_sha256": sha(destination), "original_report_sha256": sha(report_path), "config": expected_config, "starting_checksum": str(original["starting_state"]["checksum"]), "frames": original["replay"]["frames"], "tick": end["tick"], "score": end["score"] + args.score_offset, "checksum": str(end["checksum"]), "victory": end["victory"]})
    spec = {"schema": 1, "profile": str(profile), "duration_seconds": args.duration, "minimum_completed_replays": 1 if args.pilot else 3, "minimum_completed_campaigns": 0 if args.pilot else 3, "cases": cases, "declared_mode": "bounded pilot" if args.pilot else "three-hour finite campaign replay endurance", "score_offset_negative_control": args.score_offset, "pilot_fault": args.fault}
    write_json(output / "spec.json", spec)
    report_path = output / "engine-report.json"
    command = [str(ENGINE), "--path", str(ROOT), "--rendering-method", "gl_compatibility", "--resolution", "1280x720", "-s", "res://tools/verify_rendered_soak.gd", "--", "--spec=" + str(output / "spec.json"), "--output=" + str(report_path)]
    environment = dict(os.environ)
    for name in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        environment.pop(name, None)
    environment["HOME"] = str(profile)
    samples = []
    began = time.monotonic()
    origin_unix = time.time()
    timed_out = False
    fault_injected = False
    log_path = output / "engine.log"
    with log_path.open("w") as log:
        process = subprocess.Popen(command, cwd=ROOT, env=environment, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        running = {"verdict": "RUNNING", "pid": process.pid, "command": command, "engine_sha256": sha(ENGINE), "process_origin_unix_seconds": origin_unix, "source_before": before, "spec": spec}
        write_json(output / "process-receipt.json", running)
        print(f"RENDERED SOAK PID={process.pid} output={output}", flush=True)
        deadline = began + args.duration + 120
        while process.poll() is None:
            elapsed = time.monotonic() - began
            result = subprocess.run(["ps", "-o", "rss=", "-p", str(process.pid)], capture_output=True, text=True, check=False)
            if result.returncode == 0 and result.stdout.strip():
                samples.append({"elapsed_seconds": round(elapsed, 3), "rss_bytes": int(result.stdout.strip()) * 1024})
            if args.fault == "suspend-process" and not fault_injected and elapsed >= 5 and report_path.exists():
                os.kill(process.pid, signal.SIGSTOP)
                time.sleep(3)
                os.kill(process.pid, signal.SIGCONT)
                fault_injected = True
            write_json(output / "process-samples.json", {"pid": process.pid, "origin_unix_seconds": origin_unix, "samples": samples})
            if time.monotonic() > deadline:
                timed_out = True
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                break
            time.sleep(5)
        process.wait()
    after = dependencies()
    engine_report = json.loads(report_path.read_text()) if report_path.exists() else {}
    negative = bool(args.score_offset or args.fault)
    problems = check_log(log_path.read_text(errors="replace"), ["RENDERED SOAK FAIL" if negative else "RENDERED SOAK PASS"])
    problems.extend(changed_sources(before, after))
    if timed_out:
        problems.append("process exceeded wall-clock watchdog")
    if negative:
        expected_failure = {"disabled-physics": "production_physics_disabled", "muted-audio": "audio_path_muted_or_disabled", "suspend-process": "frame_activity_gap_exceeded", "disabled-render": "render_loop_disabled", "quiet-sfx": "audio_path_muted_or_disabled"}.get(args.fault, "terminal_score_mismatch")
        if process.returncode != 1 or engine_report.get("failures") != [expected_failure] or engine_report.get("live", {}).get("tick", 0) <= 0 or engine_report.get("process_frames", 0) <= 0:
            problems.append("control did not reject only the expected injected fault after real progression")
        if args.fault == "suspend-process" and not fault_injected:
            problems.append("process suspension fault was not injected")
    elif process.returncode != 0 or engine_report.get("verdict") != "VERIFIED":
        problems.append("rendered engine run did not finish successfully")
    origin_offset = origin_unix - engine_report.get("render_origin_unix_seconds", origin_unix)
    normalized_samples = [{**row, "elapsed_seconds": row["elapsed_seconds"] + origin_offset} for row in samples]
    memory = {"verified": False, "scope": "pilot does not establish a long-session memory ceiling"} if args.pilot else memory_gate(engine_report.get("samples", []), normalized_samples, engine_report.get("elapsed_seconds", 0))
    if not args.pilot:
        problems.extend(memory.get("problems", []))
        if args.duration < 10800:
            problems.append("full endurance duration must be at least three hours")
    receipt = {**running, "verdict": "VERIFIED" if not problems else "NOT VERIFIED", "process_exit": process.returncode, "timed_out": timed_out, "wall_seconds": round(time.monotonic() - began, 3), "engine_report_sha256": sha(report_path) if report_path.exists() else None, "source_after": after, "source_drift": changed_sources(before, after), "problems": problems, "memory_gate": memory, "completed_replays": len(engine_report.get("completed_replays", [])), "process_sample_count": len(samples), "negative_control": negative, "fault_injected": fault_injected or engine_report.get("pilot_fault_injected", False), "local_mac_only": True, "native_release_or_deck_performance_verified": False}
    write_json(output / "process-receipt.json", receipt)
    print(json.dumps({key: receipt[key] for key in ("verdict", "process_exit", "wall_seconds", "completed_replays", "problems")}), flush=True)
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--duration", type=float, default=10800)
    parser.add_argument("--pilot", action="store_true")
    parser.add_argument("--score-offset", type=int, default=0)
    parser.add_argument("--fault", choices=("disabled-physics", "muted-audio", "suspend-process", "disabled-render", "quiet-sfx"), default="")
    options = parser.parse_args()
    if options.duration <= 0 or (options.score_offset or options.fault) and not options.pilot or options.score_offset and options.fault:
        parser.error("duration must be positive; only one fault control is allowed, only for the bounded pilot")
    result = run(options)
    raise SystemExit(0 if result["verdict"] == "VERIFIED" else 1)
