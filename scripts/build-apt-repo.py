#!/usr/bin/env python3
"""Build a signed APT repository from verified Herdr Termux packages."""

import argparse
from datetime import datetime, timedelta, timezone
from email.utils import format_datetime
import gzip
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def validate_package(package):
    match = re.fullmatch(r"herdr_([0-9]+\.[0-9]+\.[0-9]+-[0-9]+)_aarch64\.deb", package.name)
    if not match:
        raise ValueError(f"Unexpected package filename: {package.name}")
    for field, expected in (("Package", "herdr"), ("Version", match[1]),
                            ("Architecture", "aarch64")):
        actual = subprocess.check_output(["dpkg-deb", "-f", str(package), field], text=True).strip()
        if actual != expected:
            raise ValueError(f"Unexpected {field} in {package.name}: {actual}")


def build(packages, output, key, public_key):
    if not re.fullmatch(r"[0-9A-F]{40}", key):
        raise ValueError("Use the full uppercase signing key fingerprint")
    key_info = subprocess.check_output([
        "gpg", "--batch", "--with-colons", "--show-keys", str(public_key),
    ], text=True)
    fingerprints = [line.split(":")[9] for line in key_info.splitlines() if line.startswith("fpr:")]
    primary_keys = [line for line in key_info.splitlines() if line.startswith("pub:")]
    if not fingerprints or fingerprints[0] != key or len(primary_keys) != 1:
        raise ValueError("Public key does not match the selected signing key")
    debs = sorted(packages.glob("*.deb"))
    if not debs:
        raise ValueError("No packages found")
    for package in debs:
        validate_package(package)
    if output.exists():
        raise ValueError("Output must not already exist; publish a fresh complete artifact")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="herdr-apt-", dir=output.parent) as temp:
        root = Path(temp) / "apt"
        pool = root / "pool/main/h/herdr"
        pool.mkdir(parents=True)
        for package in debs:
            shutil.copyfile(package, pool / package.name)
        suite = root / "dists/stable"
        index_dir = suite / "main/binary-aarch64"
        index_dir.mkdir(parents=True)
        index = subprocess.check_output(["apt-ftparchive", "packages", "pool"], cwd=root)
        (index_dir / "Packages").write_bytes(index)
        (index_dir / "Packages.gz").write_bytes(gzip.compress(index, mtime=0))
        now = datetime.now(timezone.utc).replace(microsecond=0)
        release = (
            "Origin: Herdr Termux\nLabel: Herdr Termux\nSuite: stable\nCodename: stable\n"
            f"Date: {format_datetime(now)}\n"
            f"Valid-Until: {format_datetime(now + timedelta(days=30))}\n"
            "Architectures: aarch64\nComponents: main\n"
            "Description: Herdr for standard aarch64 Termux\n"
        )
        for name, algorithm in (("SHA256", "sha256"), ("SHA512", "sha512")):
            release += f"{name}:\n"
            for path in sorted(index_dir.iterdir()):
                data = path.read_bytes()
                digest = hashlib.new(algorithm, data).hexdigest()
                release += f" {digest} {len(data)} {path.relative_to(suite)}\n"
        (suite / "Release").write_text(release)
        sign = ["gpg", "--batch", "--yes", "--local-user", f"{key}!", "--digest-algo", "SHA256"]
        subprocess.run([*sign, "--output", str(suite / "InRelease"),
                        "--clearsign", str(suite / "Release")], check=True)
        subprocess.run([*sign, "--armor", "--output", str(suite / "Release.gpg"),
                        "--detach-sign", str(suite / "Release")], check=True)
        shutil.copyfile(public_key, root / "herdr-termux.gpg")
        subprocess.run(["gpgv", "--keyring", str(public_key.resolve()),
                        str(suite / "InRelease")], check=True)
        root.rename(output)
    print(f"Signed repository: {output} ({len(debs)} packages)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packages", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--public-key", type=Path, required=True)
    args = parser.parse_args()
    build(args.packages, args.output, args.key, args.public_key)


if __name__ == "__main__":
    main()
