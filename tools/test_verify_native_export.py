from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import verify_native_export as subject


class NativeExportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.artifact = self.root / "game.x86_64"
        self.artifact.write_bytes(b"native executable")
        self.artifact.with_suffix(".pck").write_bytes(b"exact release pack")
        self.logs = self.root / "logs"

    def successful_process(self, command, **kwargs):
        self.assertEqual(Path(command[0]), self.artifact)
        self.assertNotIn("--quit-after", command)
        self.assertEqual(Path(command[command.index("--main-pack") + 1]), self.artifact.with_suffix(".pck"))
        self.assertNotIn("--path", command)
        empty = Path(kwargs["cwd"])
        self.assertEqual(list(empty.iterdir()), [])
        self.assertEqual(kwargs["cwd"], empty)
        self.assertTrue(Path(command[command.index("--script") + 1]).is_file())
        self.assertNotEqual(Path(kwargs["env"]["HOME"]), self.root)
        self.assertEqual(kwargs["env"]["NATIVE_EXPORT_VERSION"], "1.4.4")
        kwargs["stdout"].write("\n".join(subject.REQUIRED) + "\n")
        return subprocess.CompletedProcess(command, 0)

    def test_success_uses_exact_pack_empty_project_and_production_routes(self):
        with patch.object(subject.subprocess, "run", side_effect=self.successful_process) as run:
            receipt = subject.verify(self.artifact, self.logs, "1.4.4")
        self.assertEqual(run.call_count, 3)
        self.assertEqual([row["route"] for row in receipt["routes"]], list(subject.ROUTES))
        self.assertTrue(all(row["process_exited"] for row in receipt["routes"]))
        self.assertEqual(receipt["pack_sha256"], subject.sha(self.artifact.with_suffix(".pck")))
        self.assertTrue((self.logs / "receipt.json").is_file())
        self.assertEqual(receipt["execution_kind"], "native-external-driver")

    def test_standard_engine_receipt_does_not_claim_release_binary_execution(self):
        engine = self.root / "standard-engine"
        engine.write_bytes(b"standard editor engine")
        def success(command, **kwargs):
            self.assertEqual(Path(command[0]), engine)
            self.assertEqual(list(Path(kwargs["cwd"]).iterdir()), [])
            self.assertNotIn("--path", command)
            kwargs["stdout"].write("\n".join(subject.REQUIRED) + "\n")
            return subprocess.CompletedProcess(command, 0)
        with patch.object(subject.subprocess, "run", side_effect=success):
            receipt = subject.verify(self.artifact, self.logs, "1.4.4", engine=engine)
        self.assertEqual(receipt["execution_kind"], "standard-engine-exact-pack")
        self.assertEqual(receipt["runtime"], str(engine))
        self.assertEqual(receipt["runtime_sha256"], subject.sha(engine))
        self.assertNotEqual(receipt["runtime_sha256"], receipt["executable_sha256"])

    def test_standard_engine_drift_is_rejected_without_success_receipt(self):
        engine = self.root / "standard-engine"
        engine.write_bytes(b"standard editor engine")
        def mutated(command, **kwargs):
            kwargs["stdout"].write("\n".join(subject.REQUIRED) + "\n")
            engine.write_bytes(b"changed engine")
            return subprocess.CompletedProcess(command, 0)
        with patch.object(subject.subprocess, "run", side_effect=mutated):
            with self.assertRaisesRegex(ValueError, "runtime changed"):
                subject.verify(self.artifact, self.logs, "1.4.4", engine=engine)
        self.assertFalse((self.logs / "receipt.json").exists())

    def test_zero_exit_and_sentinels_with_leak_are_rejected(self):
        def leaked(command, **kwargs):
            result = self.successful_process(command, **kwargs)
            kwargs["stdout"].write("WARNING: 2 ObjectDB instances were leaked at exit.\n")
            return result
        with patch.object(subject.subprocess, "run", side_effect=leaked):
            with self.assertRaisesRegex(ValueError, "were leaked"):
                subject.verify(self.artifact, self.logs, "1.4.4")
        self.assertFalse((self.logs / "receipt.json").exists())

    def test_missing_progress_marker_is_rejected(self):
        with patch.object(subject.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)):
            with self.assertRaisesRegex(ValueError, "Missing success marker"):
                subject.verify(self.artifact, self.logs, "1.4.4")

    def test_progress_and_quit_without_icon_load_marker_are_rejected(self):
        def missing_icons(command, **kwargs):
            kwargs["stdout"].write("NATIVE EXPORT PROGRESS PASS\nNATIVE EXPORT QUIT DRAIN PASS\n")
            return subprocess.CompletedProcess(command, 0)
        with patch.object(subject.subprocess, "run", side_effect=missing_icons):
            with self.assertRaisesRegex(ValueError, "NATIVE EXPORT FONT AWESOME PASS"):
                subject.verify(self.artifact, self.logs, "1.4.4")
        self.assertFalse((self.logs / "receipt.json").exists())

    def test_source_fallback_is_unavailable_when_pack_is_missing(self):
        self.artifact.with_suffix(".pck").unlink()
        with patch.object(subject.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "game pack is missing"):
                subject.verify(self.artifact, self.logs, "1.4.4")
            run.assert_not_called()

    def test_release_pack_change_during_verification_is_rejected(self):
        def mutated(command, **kwargs):
            result = self.successful_process(command, **kwargs)
            self.artifact.with_suffix(".pck").write_bytes(b"new source packed during check")
            return result
        with patch.object(subject.subprocess, "run", side_effect=mutated):
            with self.assertRaisesRegex(ValueError, "pack changed"):
                subject.verify(self.artifact, self.logs, "1.4.4")

    def test_timeout_is_terminal_and_has_no_success_receipt(self):
        with patch.object(subject.subprocess, "run", side_effect=subprocess.TimeoutExpired("native", 60)):
            with self.assertRaises(subprocess.TimeoutExpired):
                subject.verify(self.artifact, self.logs, "1.4.4")
        self.assertFalse((self.logs / "receipt.json").exists())

    def test_mac_archive_wrong_metadata_is_rejected_before_launch(self):
        archive = self.root / "game.zip"
        with zipfile.ZipFile(archive, "w") as stream:
            stream.writestr("Game.app/Contents/Info.plist", plistlib.dumps({
                "CFBundleVersion": "0.3.0", "CFBundleShortVersionString": "0.3.0",
                "CFBundleExecutable": "Game"}))
        with patch.object(subject.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "metadata does not match"):
                subject.verify(archive, self.logs, "1.4.4")
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
