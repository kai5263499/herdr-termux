#!/usr/bin/env python3
"""Fetch checksum-verified packages from published downstream GitHub releases."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

REPO = "tensorlabresearch/herdr-termux"
TAG = re.compile(r"v([0-9]+\.[0-9]+\.[0-9]+)-termux\.([0-9]+)")


def release_packages(releases):
    """Return only stable downstream releases, with unambiguous expected assets."""
    selected = []
    versions = set()
    for release in releases:
        match = TAG.fullmatch(release["tag_name"])
        if release["draft"] or release["prerelease"] or not match:
            continue
        version = f"{match[1]}-{match[2]}"
        if version in versions:
            raise ValueError(f"Duplicate package version: {version}")
        versions.add(version)
        name = f"herdr_{version}_aarch64.deb"
        assets = [asset["name"] for asset in release["assets"]]
        if assets.count(name) != 1 or assets.count("SHA256SUMS") != 1:
            raise ValueError(f"Missing or ambiguous assets: {release['tag_name']}")
        selected.append((release["tag_name"], name))
    if not selected:
        raise ValueError("No published stable Termux packages found")
    return sorted(selected)


def verify_checksum(manifest, name, package):
    matches = []
    for line in manifest.splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[1].lstrip("*") == name:
            matches.append(fields[0])
    if len(matches) != 1 or not re.fullmatch(r"[0-9a-fA-F]{64}", matches[0]):
        raise ValueError(f"Missing or ambiguous checksum: {name}")
    if hashlib.sha256(package).hexdigest() != matches[0].lower():
        raise ValueError(f"Checksum mismatch: {name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    # gh reads GH_TOKEN for the API, but asset downloads below are public HTTPS.
    pages = json.loads(subprocess.check_output([
        "gh", "api", "--paginate", "--slurp", f"repos/{REPO}/releases?per_page=100",
    ]))
    selected = release_packages([release for page in pages for release in page])
    args.output.mkdir(parents=True, exist_ok=True)
    if any(args.output.iterdir()):
        raise ValueError("Output directory must be empty")
    for tag, name in selected:
        base = f"https://github.com/{REPO}/releases/download/{tag}"
        curl = ["curl", "--fail", "--location", "--silent", "--show-error",
                "--retry", "3", "--retry-all-errors", "--connect-timeout", "15", "--max-time", "180",
                "--proto", "=https", "--proto-redir", "=https"]
        # A named output lets curl truncate partial downloads when retrying.
        with tempfile.TemporaryDirectory(dir=args.output) as temporary:
            stage = Path(temporary)
            for asset in ("SHA256SUMS", name):
                subprocess.run([*curl, "--output", str(stage / asset), f"{base}/{asset}"], check=True)
            verify_checksum((stage / "SHA256SUMS").read_text(), name, (stage / name).read_bytes())
            (stage / name).rename(args.output / name)
        print(f"Verified {tag}: {name}", flush=True)


if __name__ == "__main__":
    main()
