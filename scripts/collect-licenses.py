#!/usr/bin/env python3
"""Collect original Cargo/Zig dependency notices alongside an Android build."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess


def notice_files(root):
    for current, dirs, files in os.walk(root):
        relative = Path(current).relative_to(root)
        dirs[:] = sorted(d for d in dirs if not d.startswith(".") and d not in ("target", "node_modules"))
        if len(relative.parts) >= 2:
            dirs.clear()
        for name in sorted(files):
            path = Path(current) / name
            if not path.is_symlink() and name.upper().startswith(("LICENSE", "LICENCE", "COPYING", "COPYRIGHT", "NOTICE")):
                yield path


def collect(root, destination):
    copied = []
    for path in notice_files(root):
        relative = path.relative_to(root)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        copied.append(str(relative))
    return copied


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=Path("upstream"))
    parser.add_argument("--output-dir", type=Path, default=Path("dist/licenses"))
    parser.add_argument("--zig-cache", type=Path, action="append", default=[])
    parser.add_argument("--zig-dir", type=Path, default=Path(".cache/zig-x86_64-linux-0.16.0"))
    args = parser.parse_args()
    source = args.source_dir.resolve()
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error("output directory must be empty to avoid stale notices")
    rust_root = Path(subprocess.check_output(["rustc", "--print", "sysroot"], text=True).strip())
    rust_doc = rust_root / "share/doc/rust"
    if not (rust_doc / "COPYRIGHT-library.html").is_file():
        parser.error("Rust runtime notices missing; install rust-docs for the pinned toolchain")
    if not (args.zig_dir / "LICENSE").is_file():
        parser.error("Zig toolchain notices missing; set --zig-dir to the pinned Zig directory")
    metadata = json.loads(subprocess.check_output([
        "cargo", "metadata", "--locked", "--offline", "--format-version", "1",
        "--filter-platform", "aarch64-linux-android", "--manifest-path", str(source / "Cargo.toml"),
    ], text=True))
    resolved = {node["id"] for node in metadata["resolve"]["nodes"]}
    output.mkdir(parents=True, exist_ok=True)
    records = []
    for package in sorted(metadata["packages"], key=lambda p: (p["name"], p["version"])):
        if package["id"] not in resolved:
            continue
        root = Path(package["manifest_path"]).parent
        subdir = Path("cargo") / f'{package["name"]}-{package["version"]}'
        notices = collect(root, output / subdir)
        if not notices:
            extra_root = Path(__file__).resolve().parent.parent / "licenses/extra"
            extra_name = "ratatui" if package["name"].startswith("ratatui") else package["name"]
            extra = extra_root / f"{extra_name}-LICENSE"
            if package["name"] == "ghostty-vt":
                extra = source / "LICENSE"
            if extra.is_file():
                destination = output / subdir / "UPSTREAM-LICENSE"
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(extra, destination)
                notices.append("UPSTREAM-LICENSE")
        license_file = package.get("license_file")
        if license_file:
            original = (root / license_file).resolve()
            if original.is_file() and license_file not in notices:
                destination = output / subdir / "DECLARED-LICENSE"
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(original, destination)
                notices.append("DECLARED-LICENSE")
        records.append({"name": package["name"], "version": package["version"],
                        "license": package.get("license"), "repository": package.get("repository"),
                        "source": package.get("source"), "directory": str(subdir), "notices": notices})
    collect(source / "vendor/libghostty-vt", output / "ghostty")
    vendored_packages = source / "vendor/libghostty-vt/zig-pkg"
    if vendored_packages.is_dir():
        for package in sorted(vendored_packages.iterdir()):
            if package.is_dir():
                collect(package, output / "zig" / package.name)
    if args.zig_dir.is_dir():
        collect(args.zig_dir, output / "zig-toolchain")
    extras = Path(__file__).resolve().parent.parent / "licenses/extra/sources.json"
    if extras.is_file():
        shutil.copyfile(extras, output / "extra-notice-sources.json")
    caches = args.zig_cache or [Path(os.environ.get("ZIG_GLOBAL_CACHE_DIR", Path.home() / ".cache/zig"))]
    for cache in caches:
        package_root = cache / "p"
        if package_root.is_dir():
            for package in sorted(package_root.iterdir()):
                if package.is_dir():
                    collect(package, output / "zig" / package.name)
    if rust_doc.is_dir():
        for path in rust_doc.iterdir():
            if path.is_file() and path.name.upper().startswith(("LICENSE", "COPYRIGHT")):
                target = output / "rust" / path.name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
        if (rust_doc / "licenses").is_dir():
            shutil.copytree(rust_doc / "licenses", output / "rust/licenses", dirs_exist_ok=True)
    (output / "cargo-dependencies.json").write_text(json.dumps(records, indent=2) + "\n")
    missing = [f'{r["name"]} {r["version"]}: {r["license"]}' for r in records if not r["notices"]]
    (output / "README.txt").write_text(
        "Original notices collected from the locked Android Cargo dependency graph,\n"
        "vendored Ghostty sources, fetched Zig packages, and the Rust toolchain.\n"
        "Build dependencies may be included even when not linked into the binary.\n"
        "cargo-dependencies.json records each crate's declared SPDX license and source.\n"
        "Crates without a separately packaged notice file:\n" + "\n".join(missing) + "\n")
    print(f"Collected notices for {len(records)} Cargo packages in {output}")
    if missing:
        parser.error(f"{len(missing)} crates have no separate notice file; review README.txt before packaging")


if __name__ == "__main__":
    main()
