"""Media/preflight fixtures; no Docker daemon or VM start."""
import hashlib
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import doctor


class MediaTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="cmdop-win-ref-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.storage = self.root / "storage"
        self.storage.mkdir()
        self.iso = self.root / "fixture.iso"
        self.iso.write_bytes(b"fixture, not a Windows ISO")
        self.env = {
            "CMDOP_WINDOWS_STORAGE": str(self.storage),
            "CMDOP_WINDOWS_ISO": str(self.iso),
            "CMDOP_WINDOWS_ISO_SHA256": hashlib.sha256(self.iso.read_bytes()).hexdigest(),
        }

    def check(self, free=120 * doctor.GIB):
        with patch.dict(os.environ, self.env, clear=True):
            with patch.object(doctor.shutil, "disk_usage", return_value=SimpleNamespace(free=free)):
                doctor.check_media()

    def test_exact_media_and_new_storage_pass_without_writes(self):
        self.check()
        self.assertEqual(list(self.storage.iterdir()), [])

    def test_wrong_digest_refuses(self):
        self.env["CMDOP_WINDOWS_ISO_SHA256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            self.check()

    def test_low_space_refuses(self):
        with self.assertRaisesRegex(ValueError, "110 GiB"):
            self.check(50 * doctor.GIB)

    def test_nonempty_storage_refuses_without_touching_file(self):
        other = self.storage / "existing-data"
        other.write_bytes(b"keep")
        with self.assertRaisesRegex(ValueError, "empty storage"):
            self.check()
        self.assertEqual(other.read_bytes(), b"keep")

    def test_symlink_and_checkout_refused(self):
        link = self.root / "alias"
        link.symlink_to(self.storage)
        for path in (link, doctor.REPO, Path("/")):
            self.env["CMDOP_WINDOWS_STORAGE"] = str(path)
            with self.assertRaises(ValueError):
                self.check()

    def test_media_in_storage_refuses(self):
        iso = self.storage / "fixture.iso"
        iso.write_bytes(self.iso.read_bytes())
        self.env["CMDOP_WINDOWS_ISO"] = str(iso)
        with self.assertRaisesRegex(ValueError, "separate"):
            self.check()


if __name__ == "__main__":
    unittest.main(verbosity=2)
