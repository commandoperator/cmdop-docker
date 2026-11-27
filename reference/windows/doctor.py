#!/usr/bin/env python3
"""Read-only host and media preflight for the Windows reference."""
import hashlib
import os
import platform
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys

GIB = 1024**3
ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
MIN_FREE = 110 * GIB


def external_path(name):
    raw = os.environ.get(name)
    if not raw:
        raise ValueError(f"set {name}")
    path = Path(raw)
    if not path.is_absolute() or path.resolve(strict=True) != path:
        raise ValueError(f"{name} must be an existing absolute canonical path")
    if path == Path("/") or path == REPO or REPO in path.parents or path in REPO.parents:
        raise ValueError(f"{name} must not be the checkout or its ancestor")
    return path


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def check_media():
    storage = external_path("CMDOP_WINDOWS_STORAGE")
    iso = external_path("CMDOP_WINDOWS_ISO")
    if not storage.is_dir() or not iso.is_file() or iso.suffix.lower() != ".iso":
        raise ValueError("expected a storage directory and a Windows .iso file")
    if storage in iso.parents or iso in storage.parents:
        raise ValueError("ISO and persistent VM storage must be separate")
    expected = os.environ.get("CMDOP_WINDOWS_ISO_SHA256", "").lower()
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError("set CMDOP_WINDOWS_ISO_SHA256 from the verified media")
    # A first install must not reuse another guest or a project directory.
    if any(storage.iterdir()):
        raise ValueError("first provisioning requires a dedicated empty storage directory")
    if shutil.disk_usage(storage).free < MIN_FREE:
        raise ValueError("Windows storage needs 110 GiB free before first provisioning")
    if digest(iso) != expected:
        raise ValueError("ISO SHA-256 mismatch")
    print("Storage reserve and installation media digest: OK")


def main():
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "AMD64"):
        raise ValueError("this reference needs a Linux x86-64 Docker Engine host with KVM")
    for name in ("/dev/kvm", "/dev/net/tun"):
        if not stat.S_ISCHR(Path(name).stat().st_mode):
            raise ValueError(f"{name} is not a character device")
    docker = shutil.which("docker")
    if not docker:
        raise ValueError("Docker Engine CLI not found")
    engine = subprocess.check_output(
        [docker, "info", "--format", "{{.OSType}} {{.Architecture}}"],
        text=True, timeout=15,
    ).strip()
    if engine not in ("linux x86_64", "linux amd64"):
        raise ValueError("Docker daemon is not the expected Linux amd64 engine")
    subprocess.run([docker, "compose", "-f", str(ROOT / "compose.yaml"), "config", "--quiet"],
                   check=True, timeout=15)
    check_media()
    print("Compose, host devices and media preflight passed. KVM creation and native boot still need runtime evidence.")
    print("No VM started. Confirm the Windows license and run the documented Compose command.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"Windows reference preflight refused: {error}", file=sys.stderr)
        sys.exit(1)
