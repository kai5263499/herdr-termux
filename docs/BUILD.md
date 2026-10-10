# Build and distribution

## Pinned inputs

| Input | Version |
| --- | --- |
| Herdr | v0.9.3, commit `7b116c05bfda646af39d2524c54e70c751f57ee8` |
| Rust | 1.98.0 |
| Zig | 0.16.0, archive SHA-256 verified by the build script |
| Android NDK | 28.2.13676358 (r28c) |
| Minimum Android API | 24 |
| Release package | `herdr_0.9.3-2_aarch64.deb` |

Use a Linux x86_64 host with `curl`, `git`, `tar`, `xz`, `python3`, `binutils`,
`dpkg-deb`, and `rustup`, plus the pinned Android NDK. On a host with the Android
SDK command-line tools, install the NDK with:

```sh
sdkmanager 'ndk;28.2.13676358'
```

Then, from this repository:

```sh
export ANDROID_NDK_HOME="$HOME/Android/Sdk/ndk/28.2.13676358"
bash scripts/build-android.sh
rustup component add --toolchain 1.98.0 rust-docs
RUSTUP_TOOLCHAIN=1.98.0 python3 scripts/collect-licenses.py --zig-cache .cache/zig-global
bash scripts/package-deb.sh --binary dist/herdr --source-dir upstream \
  --version 0.9.3-2 --output-dir dist --licenses-dir dist/licenses
bash tests/test-packaging.sh
```

`ANDROID_NDK_HOME` can instead point to your SDK's NDK installation. The build
script downloads Zig, installs the pinned Rust toolchain/Android target, clones
the pinned upstream revision, applies the patches, and builds with Cargo's
locked dependencies. Its default is four concurrent Cargo jobs; use
`CARGO_BUILD_JOBS=2` on a smaller host.

Generated source, caches, binaries, packages, and logs are ignored by Git.
`dist/build-info.txt` records source, compiler, patch hashes, ELF headers, and
the binary checksum. Delete the existing `dist/licenses` directory before
recollecting notices after a source/toolchain change.

## Android changes

The handoff identified the Zig target allowlist, but compilation and runtime
inspection also required Android platform routing and Termux shell paths.
The patch series:

- Adds Android API 24 targets and the NDK libc description for Ghostty's Zig build.
- Uses the Unix/Linux process, socket, and daemon implementation for Android
  while excluding Linux logind integration.
- Uses Termux shell and SSH configuration paths, and avoids an inaccessible
  `/tmp` fallback for SSH sockets.
- Keeps the package-managed Android binary from being replaced by upstream's
  unsupported self-updater.
- Opens the existing tab options on a tap, in both the tab bar and compact
  mobile switcher, while retaining mouse drag-to-reorder.

The executable has a Termux library RUNPATH and 16 KiB-compatible ELF segment
alignment. The package script inspects the ELF architecture, loader, and
`DT_NEEDED` entries, rejects unknown shared libraries, and includes original
licenses and dependency notices.

## Release procedure

Pushes to `main`, pull requests, manual dispatches, and downstream release tags
run the build/package workflow. The package is installed and its complete smoke
test runs in a pinned Termux container on a native ARM GitHub runner. This tests
the aarch64 binary without instruction translation. The container uses the
runner's Linux kernel, so separate Android app testing remains necessary.
Tag builds create a **draft** GitHub Release after those checks;
publish it after the Android runtime checks pass.

The workflow also runs the patched client shell tests on Linux. They exercise
the same downstream tap handlers as the Android build, including tab menu
actions, mobile layout, and drag-to-reorder. To run them locally after applying
the patches with the build script:

```sh
ZIG="$PWD/.cache/zig-x86_64-linux-0.16.0/zig" \
ZIG_GLOBAL_CACHE_DIR="$PWD/.cache/zig-global" \
CARGO_TARGET_DIR="$PWD/build/host-tests" CARGO_BUILD_JOBS=4 \
cargo +1.98.0 test --locked --manifest-path upstream/Cargo.toml \
  --bin herdr client::shell::tests:: -- --test-threads=4
```

The workflow currently builds the explicitly pinned upstream version. To move
to a newer upstream release, review/rebase the patches, update source and
toolchain pins as needed, update the package version in the packager, tests,
and workflow (including the exact-version updater check),
and repeat runtime validation before publication.

`install.sh` is also installed as `$PREFIX/bin/herdr-update`. It resolves
GitHub's latest published release once, then pins checksum and package downloads
to that tag. `--version` bypasses discovery for an exact release. Debian version
comparison skips installed equal/newer revisions. The package declares Bash,
curl, coreutils, dpkg, gawk, and termux-tools as dependencies for the updater. The first installation
still needs curl available to download the bootstrap script.

Release assets are the `.deb`, `install.sh`, `smoke-test.sh`, `build-info.txt`,
and `SHA256SUMS`. Regenerate the checksum list after copying the release scripts:

```sh
cp -f install.sh scripts/smoke-test.sh dist/
(cd dist && sha256sum herdr_0.9.3-2_aarch64.deb install.sh smoke-test.sh build-info.txt > SHA256SUMS)
```

On a phone or Android emulator running Termux:

```sh
sh smoke-test.sh "$(command -v herdr)"
```

The smoke test isolates its configuration and session, checks a real command
executed through a PTY, and stops/removes its test session.
