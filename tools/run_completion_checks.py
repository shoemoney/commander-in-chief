#!/usr/bin/env python3
"""Run production full-run cases with separate normal, debug, and staged verdicts."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
CASES = (
    "campaign_solo", "campaign_coop", "arcade_solo", "boss_rush_solo",
    "daily_solo", "endless_solo", "campaign_debug_traversal",
    "staged_finale_victory", "staged_last_stand_wipe",
    "campaign_controller_solo",
    "campaign_controller_coop", "arcade_controller_solo", "boss_rush_controller_solo",
    "daily_controller_solo", "endless_controller_solo",
)
NORMAL_CAMPAIGN_CASES = ("campaign_solo", "campaign_coop", "campaign_controller_solo", "campaign_controller_coop")
SHORT_RUN_FINISH_FAILURES = {
    "deadline_before_required_finish", "victory_debrief_not_reached", "last_stand_not_reached",
    "colossus_engage_event_not_seen_once", "victory_event_not_seen_once",
    "full_ordered_gate_sequence_not_seen", "full_ordered_gate_open_events_not_seen",
}
UNEXPECTED = re.compile(
    r"SCRIPT ERROR:|(?:^|\n)ERROR:|was leaked|were leaked|resources still in use at exit|leaked \d+ bytes",
    re.MULTILINE,
)


def contract_problems(name: str, report: dict) -> list[str]:
    problems = []
    staged = name.startswith("staged_")
    debug = name == "campaign_debug_traversal"
    expected_players = 2 if name.endswith("_coop") else 1
    expected_mode = "arcade" if name.startswith("arcade") or name == "staged_finale_victory" else (
        "boss_rush" if name.startswith("boss_rush") else "endless" if name.startswith("endless") else "campaign")
    if report.get("schema") != 1 or report.get("mode") != expected_mode or report.get("player_count") != expected_players:
        problems.append("case identity, mode, or player count evidence does not match contract")
    if report.get("god_mode") != debug or report.get("staged") != staged:
        problems.append("case staging declaration does not match contract")
    if not debug and not staged and (report.get("mutations") or not report.get("normal_full_run_eligible")):
        problems.append("normal case used forbidden state alteration")
    if (debug or staged) and report.get("normal_full_campaign_verified"):
        problems.append("altered case was mislabeled as normal campaign completion")
    if name not in NORMAL_CAMPAIGN_CASES and report.get("normal_full_campaign_verified"):
        problems.append("non-Campaign case was mislabeled as normal campaign completion")
    end = report.get("end_state", {})
    replay = report.get("replay", {})
    events = report.get("event_counts", {})
    save = report.get("save", {})
    if not isinstance(end, dict) or not isinstance(replay, dict) or not isinstance(events, dict) or not isinstance(save, dict):
        return problems + ["case report lacks typed end-state, replay, event, or save evidence"]
    if not isinstance(end.get("tick"), (int, float)) or end.get("tick", 0) <= 0:
        problems.append("case recorded no actual simulation progress")
    if replay.get("frames") != end.get("tick"):
        problems.append("replay does not cover every actual simulation tick")
    if not debug and not staged and not all(replay.get(field) is True for field in (
            "sample_checksums_match", "final_checksum_match", "score_match")):
        problems.append("normal run replay comparison is incomplete or does not match")
    if not staged and expected_mode != "endless":
        last_gate = 4 if expected_mode == "boss_rush" else 6
        if not all(end.get(field) is True for field in ("victory", "last_stand", "debrief")):
            problems.append("full run lacks victory, Last Stand, or debrief evidence")
        if report.get("observed_open_gate_sequence") != list(range(1, last_gate + 1)):
            problems.append("full run lacks ordered opening evidence for every gate")
        if report.get("gate_open_event_sequence") != list(range(1, last_gate)):
            problems.append("full run lacks ordered checkpoint events")
        if events.get("colossus_engage") != 1 or events.get("victory") != 1:
            problems.append("full run lacks one Colossus engage and victory event")
    if expected_mode == "endless":
        if end.get("wave", 0) < 3 or events.get("wave_clear", 0) < 2:
            problems.append("normal Endless case lacks two completed waves")
        if end.get("victory") is not False:
            problems.append("Endless case incorrectly reached finite campaign victory")
    if name == "staged_finale_victory" and not all(end.get(field) is True for field in ("victory", "last_stand", "debrief")):
        problems.append("staged finale lacks victory, Last Stand, or debrief evidence")
    if name == "staged_last_stand_wipe" and not all(end.get(field) is True for field in ("wiped", "last_stand", "debrief")):
        problems.append("staged wipe lacks wiped, Last Stand, or debrief evidence")
    if end.get("debrief") and report.get("debrief_freeze_verified") is not True:
        problems.append("debrief did not prove the production simulation freeze")
    if end.get("debrief") and not debug and not staged:
        if not all(save.get(field) is True for field in (
                "config_loaded", "production_replay_saved", "production_replay_score_valid",
                "saved_replay_verified_flag", "watch_playback_final_checksum_match",
                "relaunch_last_score_match", "relaunch_watched_score_match", "relaunch_hall_entry_match")):
            problems.append("normal terminal run lacks production save, playback, or relaunch evidence")
        if save.get("saved_score") != end.get("score") or save.get("hall_latest", {}).get("score") != end.get("score"):
            problems.append("persisted terminal score does not match the actual run")
    if name.startswith("daily_") and report.get("daily_spent_on_start") is not True:
        problems.append("Daily case lacks evidence that the one attempt was consumed")
    if "_controller_" in name:
        intents = report.get("controller_intents", {})
        if not isinstance(intents, dict) or not intents or not all(isinstance(count, int) and count >= 0 for count in intents.values()):
            problems.append("legal-controller case lacks typed input decision evidence")
        elif sum(intents.values()) != replay.get("frames", -1) * expected_players:
            problems.append("legal-controller decisions do not cover every player input tick")
        player_intents = report.get("controller_player_intents", {})
        if not isinstance(player_intents, dict) or set(player_intents) != {str(index) for index in range(expected_players)}:
            problems.append("legal-controller case lacks separate decision evidence for every player")
        else:
            for player, counts in player_intents.items():
                if not isinstance(counts, dict) or not counts or not all(isinstance(count, int) and count >= 0 for count in counts.values()):
                    problems.append(f"legal-controller player {player} has malformed decision evidence")
                elif sum(counts.values()) != replay.get("frames", -1):
                    problems.append(f"legal-controller player {player} decisions do not cover every actual tick")
        if not report.get("observation_policy") or report.get("p2_independent_human_input_verified") is not False:
            problems.append("legal-controller observation or physical-input scope is missing")
    return problems


def inspect_run(name: str, report: dict | None, log: str, returncode: int | None,
                timed_out: bool, negative: bool = False) -> list[str]:
    problems = []
    if timed_out:
        problems.append("process deadline exceeded")
    if UNEXPECTED.search(log):
        problems.append("unexpected engine error or shutdown leak")
    if not isinstance(report, dict) or report.get("case") != name:
        problems.append("missing or wrong case report")
        return problems
    if negative:
        if returncode != 1:
            problems.append("short-run control did not exit with expected failure")
        if report.get("verdict") != "NOT VERIFIED":
            problems.append("short-run control did not reject incomplete run")
        failure_list = report.get("failures")
        if not isinstance(failure_list, list) or "deadline_before_required_finish" not in failure_list:
            problems.append("short-run control failed for an unrelated reason")
        if not isinstance(failure_list, list) or not all(isinstance(reason, str) for reason in failure_list) or not set(failure_list) <= SHORT_RUN_FINISH_FAILURES:
            problems.append("short-run control includes a failure unrelated to required finish")
        end = report.get("end_state", {})
        replay = report.get("replay", {})
        if not isinstance(end, dict) or not isinstance(replay, dict):
            problems.append("short-run control lacks typed progress evidence")
        else:
            if any(type(value) is not int or value != 30 for value in (
                    report.get("tick_limit"), end.get("tick"), replay.get("frames"))):
                problems.append("short-run control did not execute and record exactly 30 simulation ticks")
            if not all(replay.get(field) is True for field in (
                    "sample_checksums_match", "final_checksum_match", "score_match")):
                problems.append("short-run control lacks matching recorded-input replay evidence")
            if not all(end.get(field) is False for field in ("victory", "last_stand", "debrief", "wiped")):
                problems.append("short-run control reached an unrelated terminal or finale state")
        if report.get("schema") != 1 or report.get("mode") != "campaign" or report.get("player_count") != 1 \
                or report.get("god_mode") is not False or report.get("staged") is not False \
                or report.get("normal_full_run_eligible") is not True or report.get("mutations"):
            problems.append("short-run control was not an unaltered solo Campaign")
        if f"FULL RUN NOT VERIFIED: {name}" not in log:
            problems.append("short-run rejection sentinel missing")
        if "FULL RUN PASS:" in log or report.get("normal_full_campaign_verified"):
            problems.append("short-run control was accepted as complete")
    else:
        if returncode != 0:
            problems.append(f"process exited {returncode}")
        if report.get("verdict") != "VERIFIED":
            problems.append("case acceptance rules were not met")
        if f"FULL RUN PASS: {name}" not in log:
            problems.append("required success sentinel missing")
        if report.get("failures"):
            problems.extend(str(reason) for reason in report["failures"])
        problems.extend(contract_problems(name, report))
        if name in NORMAL_CAMPAIGN_CASES and not report.get("normal_full_campaign_verified"):
            problems.append("normal full campaign not verified")
    return problems


def supervise_process(command: list[str], log_path: Path, timeout: float,
                      cwd: Path = ROOT) -> tuple[int, bool]:
    timed_out = False
    with log_path.open("w", encoding="utf-8") as log_file:
        process = subprocess.Popen(command, cwd=cwd, stdout=log_file,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            returncode = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
            returncode = process.returncode
    return returncode, timed_out


def source_hashes() -> dict[str, str]:
    source_paths = set(path for path in (ROOT / "src").rglob("*") if path.is_file())
    source_paths.update(path for path in (ROOT / "assets").rglob("*") if path.is_file())
    source_paths.update(path for path in (ROOT / ".godot/imported").rglob("*") if path.is_file())
    source_paths.update(ROOT / path for path in (
        "project.godot", "tools/verify_full_run.gd", "tools/run_completion_checks.py",
        "tools/full_run_input.gd", "tools/run_tests.sh", "tools/quiesce.gd",
        "tools/verify_full_run.gd.uid", "tools/full_run_input.gd.uid", "tools/quiesce.gd.uid",
        "tools/versions.lock",
        ".godot/global_script_class_cache.cfg", ".godot/uid_cache.bin",
    ) if (ROOT / path).is_file())
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(source_paths)}


def changed_sources(before: dict[str, str], after: dict[str, str]) -> list[str]:
    return sorted(path for path in before.keys() | after.keys() if before.get(path) != after.get(path))


def source_problems(before: dict[str, str], after: dict[str, str]) -> list[str]:
    changes = changed_sources(before, after)
    return ["source or class-cache dependencies changed during the run: " + ", ".join(changes)] if changes else []


def batch_source_problems(cases: list[dict], final_source: dict[str, str]) -> list[str]:
    if not cases:
        return ["no cases were selected"]
    common_source = cases[0]["source_before"]
    problems = []
    if not any(case.get("negative_control") for case in cases):
        problems.append("selected batch lacks its own incomplete-run rejection control")
    for case in cases:
        if case["source_before"] != common_source or case["source_after"] != common_source:
            problems.append("selected batch did not use one common source and dependency snapshot")
            break
    if final_source != common_source:
        problems.append("current source and dependencies do not match the selected batch snapshot")
    return problems


def execute(name: str, out: Path, timeout: float, max_ticks: int | None,
            seed: int, negative: bool = False) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    report_path = out / f"{name}.json"
    if report_path.exists():
        report_path.unlink()
    command = [
        str(ROOT / "tools/run_tests.sh"), "-s", "res://tools/verify_full_run.gd", "--",
        f"--case={name}", f"--output={report_path}", f"--seed={seed}",
    ]
    if max_ticks is not None:
        command.append(f"--max-ticks={max_ticks}")
    source_before = source_hashes()
    started = time.monotonic()
    log_path = out / f"{name}.log"
    returncode, timed_out = supervise_process(command, log_path, timeout)
    log = log_path.read_text(encoding="utf-8", errors="replace")
    report = None
    if report_path.exists():
        try:
            report = json.loads(report_path.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            pass
    problems = inspect_run(name, report, log, returncode, timed_out, negative)
    source_after = source_hashes()
    source_changes = changed_sources(source_before, source_after)
    problems.extend(source_problems(source_before, source_after))
    result = {"case": name, "negative_control": negative,
              "verdict": "VERIFIED" if not problems else "NOT VERIFIED",
              "process_exit": returncode, "timed_out": timed_out,
              "process_deadline_seconds": timeout, "command": command,
              "wall_seconds": round(time.monotonic() - started, 3),
              "report": str(report_path), "log": str(log_path), "problems": problems,
              "source_before": source_before, "source_after": source_after,
              "source_changed_during_run": source_changes}
    print(f"COMPLETION CASE {result['verdict']}: {name}" + (" rejection control" if negative else ""), flush=True)
    for problem in problems:
        print(f"  {problem}", flush=True)
    return result


def self_test() -> int:
    complete = {"case": "campaign_solo", "verdict": "VERIFIED", "failures": [],
                "normal_full_campaign_verified": True, "schema": 1, "mode": "campaign",
                "player_count": 1, "staged": False, "god_mode": False,
                "normal_full_run_eligible": True, "mutations": [],
                "end_state": {"tick": 6000, "score": 1000, "last_stand": True, "victory": True, "debrief": True},
                "replay": {"frames": 6000, "sample_checksums_match": True, "final_checksum_match": True, "score_match": True},
                "observed_open_gate_sequence": list(range(1, 7)), "gate_open_event_sequence": list(range(1, 6)),
                "event_counts": {"colossus_engage": 1, "victory": 1}, "debrief_freeze_verified": True,
                "save": {"config_loaded": True, "production_replay_saved": True, "production_replay_score_valid": True,
                         "saved_replay_verified_flag": True, "watch_playback_final_checksum_match": True,
                         "relaunch_last_score_match": True, "relaunch_watched_score_match": True,
                         "relaunch_hall_entry_match": True, "saved_score": 1000, "hall_latest": {"score": 1000}}}
    passing = "FULL RUN PASS: campaign_solo\n"
    assert not inspect_run("campaign_solo", complete, passing, 0, False)
    assert inspect_run("campaign_solo", complete, "", 0, False)
    assert inspect_run("campaign_solo", complete, passing, 1, False)
    assert inspect_run("campaign_solo", complete, passing + "SCRIPT ERROR: planted\n", 0, False)
    assert inspect_run("campaign_solo", complete, passing + "ERROR: planted\n", 0, False)
    assert inspect_run("campaign_solo", complete, passing + "2 ObjectDB instances were leaked\n", 0, False)
    assert inspect_run("campaign_solo", complete, passing, 0, True)
    for field, missing_value in (("end_state", {}), ("replay", {}), ("save", {}), ("observed_open_gate_sequence", [1])):
        assert inspect_run("campaign_solo", {**complete, field: missing_value}, passing, 0, False)
    assert inspect_run("campaign_solo", {**complete, "god_mode": True}, passing, 0, False)
    assert inspect_run("campaign_solo", {**complete, "mutations": [{"changes": "force victory"}]}, passing, 0, False)
    for name in ("campaign_controller_solo", "campaign_controller_coop", "arcade_controller_solo",
                 "boss_rush_controller_solo", "daily_controller_solo", "endless_controller_solo"):
        controller = json.loads(json.dumps(complete))
        controller["case"] = name
        controller["normal_full_campaign_verified"] = name in NORMAL_CAMPAIGN_CASES
        controller["player_count"] = 2 if name.endswith("_coop") else 1
        controller["controller_intents"] = {"ADVANCE": 6000 * controller["player_count"]}
        controller["controller_player_intents"] = {str(index): {"ADVANCE": 6000} for index in range(controller["player_count"])}
        controller["observation_policy"] = "Current visible state only"
        controller["p2_independent_human_input_verified"] = False
        if name.startswith("arcade"):
            controller["mode"] = "arcade"
        elif name.startswith("boss_rush"):
            controller["mode"] = "boss_rush"
            controller["observed_open_gate_sequence"] = list(range(1, 5))
            controller["gate_open_event_sequence"] = list(range(1, 4))
        elif name.startswith("daily"):
            controller["daily_spent_on_start"] = True
        elif name.startswith("endless"):
            controller["mode"] = "endless"
            controller["end_state"].update({"victory": False, "last_stand": False, "debrief": False, "wave": 3})
            controller["event_counts"] = {"wave_clear": 2}
        assert not inspect_run(name, controller, f"FULL RUN PASS: {name}\n", 0, False)
        assert inspect_run(name, {**controller, "controller_intents": {}}, f"FULL RUN PASS: {name}\n", 0, False)
        assert inspect_run(name, {**controller, "controller_player_intents": {}}, f"FULL RUN PASS: {name}\n", 0, False)
        if name.endswith("_coop"):
            assert inspect_run(name, {**controller, "controller_player_intents": {"0": {"ADVANCE": 12000}, "1": {"ADVANCE": 0}}}, f"FULL RUN PASS: {name}\n", 0, False)
    incomplete = {"case": "campaign_solo", "verdict": "NOT VERIFIED", "schema": 1,
                  "mode": "campaign", "player_count": 1, "god_mode": False, "staged": False,
                  "normal_full_run_eligible": True, "mutations": [], "tick_limit": 30,
                  "end_state": {"tick": 30, "victory": False, "last_stand": False, "debrief": False, "wiped": False},
                  "replay": {"frames": 30, "sample_checksums_match": True, "final_checksum_match": True, "score_match": True},
                  "failures": ["deadline_before_required_finish"], "normal_full_campaign_verified": False}
    rejecting = "FULL RUN NOT VERIFIED: campaign_solo\n"
    assert not inspect_run("campaign_solo", incomplete, rejecting, 1, False, True)
    assert inspect_run("campaign_solo", incomplete, rejecting, 0, False, True)
    assert inspect_run("campaign_solo", incomplete, rejecting, 1, True, True)
    assert inspect_run("campaign_solo", {**incomplete, "end_state": {**incomplete["end_state"], "tick": 0},
                       "replay": {**incomplete["replay"], "frames": 0}}, rejecting, 1, False, True)
    assert inspect_run("campaign_solo", {**incomplete, "tick_limit": 1}, rejecting, 1, False, True)
    assert inspect_run("campaign_solo", {**incomplete, "failures": ["deadline_before_required_finish", "production_physics_stalled_before_required_finish"]}, rejecting, 1, False, True)
    assert not changed_sources({"a.gd": "same"}, {"a.gd": "same"})
    assert changed_sources({"a.gd": "old"}, {"a.gd": "new"}) == ["a.gd"]
    assert changed_sources({"a.gd": "same"}, {"a.gd": "same", "added.gd": "new"}) == ["added.gd"]
    assert changed_sources({"removed.gd": "old"}, {}) == ["removed.gd"]
    assert not source_problems({"a.gd": "same"}, {"a.gd": "same"})
    assert source_problems({"a.gd": "old"}, {"a.gd": "new"})
    assert source_problems({}, {"added.gd": "new"})
    assert source_problems({"removed.gd": "old"}, {})
    stable_case = {"source_before": {"a.gd": "same"}, "source_after": {"a.gd": "same"}, "negative_control": False}
    stable_control = {**stable_case, "negative_control": True}
    assert not batch_source_problems([stable_control, stable_case], {"a.gd": "same"})
    assert batch_source_problems([stable_case], {"a.gd": "same"})
    changed_case = {"source_before": {"a.gd": "other"}, "source_after": {"a.gd": "other"}}
    assert batch_source_problems([stable_case, changed_case], {"a.gd": "other"})
    assert batch_source_problems([stable_case], {"a.gd": "new"})
    with tempfile.TemporaryDirectory(prefix="cic-supervisor-control-") as control_dir:
        code, timed_out = supervise_process([sys.executable, "-c", "import time; time.sleep(60)"],
                                           Path(control_dir) / "timeout.log", 0.05)
        assert timed_out and code != 0
    print("COMPLETION SUPERVISOR SELF TEST PASS: missing sentinel, wrong exit, errors, leaks, timeout, and incomplete run rejected")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=CASES, action="append", help="Repeat to select cases. Default runs all cases serially.")
    parser.add_argument("--output", type=Path, default=ROOT / "build/completion-audit/full-run")
    parser.add_argument("--process-timeout", type=float, default=300)
    parser.add_argument("--max-ticks", type=int)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=0xC0FFEE)
    parser.add_argument("--self-test", action="store_true", help="Exercise supervisor rejection rules without launching Godot.")
    parser.add_argument("--negative-control-only", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.process_timeout <= 0 or (args.max_ticks is not None and args.max_ticks <= 0):
        parser.error("deadlines must be positive")
    out = args.output.resolve()
    cases = []
    cases.append(execute("campaign_solo", out / "negative-control", args.process_timeout,
                         30, args.seed, negative=True))
    if not args.negative_control_only:
        for name in args.case or CASES:
            cases.append(execute(name, out, args.process_timeout, args.max_ticks, args.seed))
    normal_campaign = any(case["case"] in NORMAL_CAMPAIGN_CASES and not case["negative_control"]
                          and case["verdict"] == "VERIFIED" for case in cases)
    final_source = source_hashes()
    batch_problems = batch_source_problems(cases, final_source)
    result = {"schema": 1, "verdict": "VERIFIED" if cases and all(
        case["verdict"] == "VERIFIED" for case in cases) and not batch_problems else "NOT VERIFIED",
        "normal_full_campaign_verified": normal_campaign and not batch_problems, "cases": cases,
        "batch_problems": batch_problems, "final_source": final_source,
        "source_fingerprint": hashlib.sha256(json.dumps(cases[0]["source_before"] if cases else {}, sort_keys=True).encode()).hexdigest(),
        "scope": "Selected production entry paths and recorded acceptance rules only. Headless results do not establish rendering, audio perception, physical controllers, live Steam, or independent human co-op."}
    out.mkdir(parents=True, exist_ok=True)
    (out / "summary.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"COMPLETION CHECKS {result['verdict']}", flush=True)
    return 0 if result["verdict"] == "VERIFIED" else 1


if __name__ == "__main__":
    sys.exit(main())
