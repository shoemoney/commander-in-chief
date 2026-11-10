"""Review packaging boundaries. Fixtures do not represent game acceptance."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import assemble_release_review as subject


class ReleaseReviewTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        (self.root / "src").mkdir()
        (self.root / "src/main.gd").write_bytes(b"source fixture")
        (self.root / "project.godot").write_text('config/version="1.4.4"\n')
        (self.root / "export_presets.cfg").write_bytes(b"presets fixture")
        (self.root / "docs/steam-store").mkdir(parents=True)
        (self.root / "docs/steam-store/owner-review.md").write_bytes(b"open owner gates")
        for name in ("ASSETS.md", "NOTICE.md"):
            (self.root / name).write_bytes(b"reference fixture")
        self.addCleanup(patch.stopall)
        patch.object(subject, "validate_copy").start()
        files = subject.current_source_files(self.root)
        self.identity = {"revision": "a" * 40, "files": files, "project_version": "1.4.4",
                         "fingerprint_sha256": hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest(),
                         "dirty": True}
        self.builds = self.root / "candidates"
        self.builds.mkdir()
        exports = []
        for platform in ("macos", "linux", "windows"):
            folder = self.builds / platform
            folder.mkdir()
            (folder / "game.bin").write_bytes(platform.encode())
            (folder / "export.log").write_bytes(b"export completed")
            exports.append({"platform": platform, "files": {"game.bin": subject.sha(folder / "game.bin")},
                            "export_log_sha256": subject.sha(folder / "export.log")})
        self.build_manifest = {"source_before": copy.deepcopy(self.identity),
                               "source_after": copy.deepcopy(self.identity), "exports": exports}
        self.write_manifest(self.builds, self.build_manifest)
        self.output = self.root / "review"

    def write_manifest(self, folder, value):
        (folder / "manifest.json").write_text(json.dumps(value, indent=2) + "\n")

    def shots(self, identity=True):
        folder = self.root / "shots"
        folder.mkdir()
        (folder / "01.png").write_bytes(b"image fixture")
        manifest = {"screenshots": [{"file": "01.png", "sha256": subject.sha(folder / "01.png")}]}
        if identity:
            manifest["source_identity"] = copy.deepcopy(self.identity)
        self.write_manifest(folder, manifest)
        return folder, manifest

    def historical_art(self):
        folder = self.root / "art"
        (folder / "sources").mkdir(parents=True)
        (folder / "hero.png").write_bytes(b"historical image fixture")
        (folder / "sources/hero.blend").write_bytes(b"historical source fixture")
        self.write_manifest(folder, {"assets": [{"file": "hero.png", "sha256": subject.sha(folder / "hero.png"),
                                                "source_file": "sources/hero.blend",
                                                "source_sha256": subject.sha(folder / "sources/hero.blend")}]})
        return folder

    def trailer(self):
        folder = self.root / "trailer"
        folder.mkdir()
        for name in ("trailer.mp4", "poster.png", "cut-list.json"):
            (folder / name).write_bytes(name.encode())
        manifest = {"file": "trailer.mp4", "sha256": subject.sha(folder / "trailer.mp4"),
                    "source_identity": copy.deepcopy(self.identity),
                    "files": {name: subject.sha(folder / name) for name in ("poster.png", "cut-list.json")}}
        self.write_manifest(folder, manifest)
        return folder, manifest

    def evidence(self):
        folder = self.root / "evidence"
        folder.mkdir()
        (folder / "native.log").write_bytes(b"fixture only; no engine execution")
        manifest = {"source_identity": copy.deepcopy(self.identity),
                    "files": {"native.log": subject.sha(folder / "native.log")}}
        self.write_manifest(folder, manifest)
        return folder, manifest

    def test_explicit_fresh_artifacts_assemble_and_verify(self):
        shots, _ = self.shots()
        (shots / "unlisted-raw.png").write_bytes(b"not receipted")
        subject.assemble(self.root, self.output, {"builds": self.builds, "screenshots": shots,
                                               "art": self.historical_art()}, True)
        subject.verify(self.output)
        receipt = json.loads((self.output / "manifest.json").read_text())
        self.assertTrue(receipt["require_same_source"])
        self.assertEqual(receipt["selections"]["screenshots"]["source_relation"], "same source snapshot")
        self.assertEqual(receipt["selections"]["art"]["source_relation"], "historical art")
        self.assertFalse((self.output / "screenshots/unlisted-raw.png").exists())
        self.assertIn("historical art", (self.output / "START-HERE.md").read_text())
        self.assertIn("trailer: absent", (self.output / "START-HERE.md").read_text())

    def test_historical_candidates_without_identity_are_rejected(self):
        self.build_manifest.pop("source_before")
        self.build_manifest.pop("source_after")
        self.write_manifest(self.builds, self.build_manifest)
        with self.assertRaisesRegex(ValueError, "Fresh candidates require"):
            subject.assemble(self.root, self.output, {"builds": self.builds})
        self.assertFalse(self.output.exists())

    def test_source_drift_rejected_before_output_creation(self):
        (self.root / "src/main.gd").write_bytes(b"new code")
        with self.assertRaisesRegex(ValueError, "differs from the current source files"):
            subject.assemble(self.root, self.output, {"builds": self.builds})
        self.assertFalse(self.output.exists())

    def test_new_unrecorded_runtime_source_also_counts_as_drift(self):
        (self.root / "src/new.gd").write_bytes(b"unrecorded code")
        with self.assertRaisesRegex(ValueError, "differs from the current source files"):
            subject.plan(self.root, {"builds": self.builds})

    def test_before_after_source_disagreement_rejected(self):
        self.build_manifest["source_after"]["revision"] = "b" * 40
        self.write_manifest(self.builds, self.build_manifest)
        with self.assertRaisesRegex(ValueError, "Source changed between"):
            subject.plan(self.root, {"builds": self.builds})

    def test_candidate_needs_both_original_snapshots(self):
        self.build_manifest.pop("source_before")
        self.build_manifest.pop("source_after")
        self.build_manifest["source_identity"] = copy.deepcopy(self.identity)
        self.write_manifest(self.builds, self.build_manifest)
        with self.assertRaisesRegex(ValueError, "Fresh candidates require"):
            subject.plan(self.root, {"builds": self.builds})

    def test_conflicting_snapshot_and_identity_rejected(self):
        self.build_manifest["source_identity"] = copy.deepcopy(self.identity)
        self.build_manifest["source_identity"]["revision"] = "b" * 40
        self.write_manifest(self.builds, self.build_manifest)
        with self.assertRaisesRegex(ValueError, "conflicts with its recorded snapshots"):
            subject.plan(self.root, {"builds": self.builds})

    def test_invalid_source_fingerprint_rejected(self):
        for field in ("source_before", "source_after"):
            self.build_manifest[field]["fingerprint_sha256"] = "0" * 64
        self.write_manifest(self.builds, self.build_manifest)
        with self.assertRaisesRegex(ValueError, "fingerprint differs from its file map"):
            subject.plan(self.root, {"builds": self.builds})

    def test_wrong_project_version_rejected(self):
        for field in ("source_before", "source_after"):
            self.build_manifest[field]["project_version"] = "0.3.0"
        self.write_manifest(self.builds, self.build_manifest)
        with self.assertRaisesRegex(ValueError, "project version differs"):
            subject.plan(self.root, {"builds": self.builds})

    def test_artifact_hash_drift_rejected(self):
        (self.builds / "linux/game.bin").write_bytes(b"different executable")
        with self.assertRaisesRegex(ValueError, "checksum differs"):
            subject.plan(self.root, {"builds": self.builds})

    def test_missing_artifact_rejected(self):
        (self.builds / "windows/game.bin").unlink()
        with self.assertRaisesRegex(ValueError, "Missing/nonregular artifact"):
            subject.plan(self.root, {"builds": self.builds})

    def test_export_log_drift_or_missing_receipt_rejected(self):
        (self.builds / "macos/export.log").write_bytes(b"changed log")
        with self.assertRaisesRegex(ValueError, "checksum differs"):
            subject.plan(self.root, {"builds": self.builds})
        self.build_manifest["exports"][0].pop("export_log_sha256")
        self.write_manifest(self.builds, self.build_manifest)
        with self.assertRaisesRegex(ValueError, "missing its export log hash"):
            subject.plan(self.root, {"builds": self.builds})

    def test_unsafe_paths_rejected_on_every_host(self):
        for name in ("../outside", "/outside", "C:/outside", "..\\outside"):
            with self.subTest(name=name):
                self.build_manifest["exports"][0]["files"] = {name: "0" * 64}
                self.write_manifest(self.builds, self.build_manifest)
                with self.assertRaisesRegex(ValueError, "Unsafe artifact path"):
                    subject.plan(self.root, {"builds": self.builds})

    def test_symlinked_artifact_rejected(self):
        artifact = self.builds / "linux/game.bin"
        target = self.builds / "linux/actual.bin"
        target.write_bytes(artifact.read_bytes())
        artifact.unlink()
        artifact.symlink_to(target)
        with self.assertRaisesRegex(ValueError, "Missing/nonregular artifact"):
            subject.plan(self.root, {"builds": self.builds})

    def test_symlinked_supporting_directory_rejected(self):
        evidence, manifest = self.evidence()
        (evidence / "real").mkdir()
        (evidence / "native.log").rename(evidence / "real/native.log")
        (evidence / "linked").symlink_to(evidence / "real", target_is_directory=True)
        manifest["files"] = {"linked/native.log": subject.sha(evidence / "real/native.log")}
        self.write_manifest(evidence, manifest)
        with self.assertRaisesRegex(ValueError, "Missing/nonregular artifact"):
            subject.plan(self.root, {"builds": self.builds, "evidence": evidence})

    def test_different_media_source_cannot_satisfy_same_source_promise(self):
        shots, manifest = self.shots()
        manifest["source_identity"]["revision"] = "b" * 40
        self.write_manifest(shots, manifest)
        with self.assertRaisesRegex(ValueError, "Same-source promise failed for screenshots"):
            subject.plan(self.root, {"builds": self.builds, "screenshots": shots}, True)
        _, selections = subject.plan(self.root, {"builds": self.builds, "screenshots": shots})
        self.assertEqual(selections["screenshots"]["source_relation"], "different source snapshot")

    def test_partial_or_absent_media_identity_cannot_satisfy_same_source_promise(self):
        shots, manifest = self.shots(False)
        for identity in (None, {"source_revision": "a" * 40, "source_files": self.identity["files"]}):
            with self.subTest(identity=identity):
                if identity:
                    manifest.update(identity)
                self.write_manifest(shots, manifest)
                with self.assertRaisesRegex(ValueError, "Same-source promise failed"):
                    subject.plan(self.root, {"builds": self.builds, "screenshots": shots}, True)

    def test_declared_supporting_file_must_have_matching_bytes(self):
        shots, manifest = self.shots()
        manifest["files"] = {"missing-replay.bin": "0" * 64}
        self.write_manifest(shots, manifest)
        with self.assertRaisesRegex(ValueError, "Missing/nonregular artifact"):
            subject.plan(self.root, {"builds": self.builds, "screenshots": shots}, True)

    def test_trailer_and_runtime_evidence_keep_hashed_supporting_files(self):
        trailer, _ = self.trailer()
        evidence, _ = self.evidence()
        subject.assemble(self.root, self.output, {"builds": self.builds, "trailer": trailer,
                                               "evidence": evidence}, True)
        subject.verify(self.output)
        for path in ("trailer/trailer.mp4", "trailer/poster.png", "trailer/cut-list.json", "evidence/native.log"):
            self.assertTrue((self.output / path).is_file())

    def test_trailer_supporting_file_drift_rejected(self):
        trailer, _ = self.trailer()
        (trailer / "poster.png").write_bytes(b"changed poster")
        with self.assertRaisesRegex(ValueError, "checksum differs"):
            subject.plan(self.root, {"builds": self.builds, "trailer": trailer}, True)

    def test_trailer_video_cannot_conflict_with_flat_file_receipt(self):
        trailer, manifest = self.trailer()
        manifest["files"]["trailer.mp4"] = "0" * 64
        self.write_manifest(trailer, manifest)
        with self.assertRaisesRegex(ValueError, "Trailer hash conflicts"):
            subject.plan(self.root, {"builds": self.builds, "trailer": trailer}, True)

    def test_runtime_evidence_identity_drift_rejected(self):
        evidence, manifest = self.evidence()
        manifest["source_identity"]["revision"] = "b" * 40
        self.write_manifest(evidence, manifest)
        with self.assertRaisesRegex(ValueError, "Same-source promise failed for evidence"):
            subject.plan(self.root, {"builds": self.builds, "evidence": evidence}, True)

    def test_malformed_file_receipt_rejected(self):
        evidence, manifest = self.evidence()
        manifest["files"] = [["native.log", subject.sha(evidence / "native.log")]]
        self.write_manifest(evidence, manifest)
        with self.assertRaisesRegex(ValueError, "path-to-checksum dictionary"):
            subject.plan(self.root, {"builds": self.builds, "evidence": evidence})

    def test_unsafe_source_identity_path_rejected(self):
        shots, manifest = self.shots()
        manifest["source_identity"]["files"] = {"res://": "0" * 64}
        self.write_manifest(shots, manifest)
        with self.assertRaisesRegex(ValueError, "Unsafe or duplicate source path"):
            subject.plan(self.root, {"builds": self.builds, "screenshots": shots})

    def test_source_mutation_during_copy_has_no_success_manifest(self):
        copy_file = subject.shutil.copy2
        def mutate(source, destination):
            result = copy_file(source, destination)
            (self.root / "src/main.gd").write_bytes(b"concurrent change")
            return result
        with patch.object(subject.shutil, "copy2", side_effect=mutate):
            with self.assertRaisesRegex(ValueError, "Source changed during review assembly"):
                subject.assemble(self.root, self.output, {"builds": self.builds})
        self.assertFalse((self.output / "manifest.json").exists())

    def test_existing_output_is_preserved(self):
        self.output.mkdir()
        sentinel = self.output / "keep"
        sentinel.write_bytes(b"existing user output")
        with self.assertRaisesRegex(ValueError, "already exists"):
            subject.assemble(self.root, self.output, {"builds": self.builds})
        self.assertEqual(sentinel.read_bytes(), b"existing user output")

    def test_verify_rejects_false_same_source_relabeling(self):
        shots, manifest = self.shots()
        manifest["source_identity"]["revision"] = "b" * 40
        self.write_manifest(shots, manifest)
        subject.assemble(self.root, self.output, {"builds": self.builds, "screenshots": shots})
        receipt = json.loads((self.output / "manifest.json").read_text())
        receipt["selections"]["screenshots"]["source_relation"] = "same source snapshot"
        (self.output / "manifest.json").write_text(json.dumps(receipt))
        with zipfile.ZipFile(self.output.with_suffix(".zip"), "w") as archive:
            for path in self.output.rglob("*"):
                if path.is_file():
                    archive.write(path, path.relative_to(self.output).as_posix())
        with self.assertRaisesRegex(ValueError, "False same-source declaration"):
            subject.verify(self.output)


if __name__ == "__main__":
    unittest.main()
