# Validation evidence

Validation started October 6, 2026. This document distinguishes host packaging
checks, an Android emulator, and the physical phone.

## Packaging and installer

Thirteen host checks pass using real Android ELF fixtures built with the NDK
and isolated mocks for network/package-manager operations. They cover package
paths and permissions, license inclusion, reproducible archives, CPU and loader
rejection, shared-library dependency mapping, unsupported installer environments,
tampered/ambiguous checksums, package metadata validation, and versioned updates.
These checks do not claim a phone installation.

## Android runtime

The available test device is an API 36.1 x86_64 Android emulator with an arm64
native bridge, running the official Termux app. No physical phone is connected.

Upstream musl `--version` can succeed under Android, but this is not sufficient
acceptance for a Termux package. An ADB shell has different permissions from the
Termux app. `run-as` also differs from execution launched through the actual
Termux terminal, notably in seccomp filtering. Tests must identify their context.

The upstream x86_64 musl binary passed the isolated shell-pane smoke via
`run-as`, then failed with SIGSYS through the actual Termux terminal. The arm64
musl binary prints its version through the terminal's native bridge, but its
full runtime remains a separate check. These results do not establish whether
the upstream arm64 musl binary works on a physical arm64 phone.

The Android aarch64 cross-build succeeded. Its interpreter is
`/system/bin/linker64` and its dynamic dependencies are `libc.so`, `libdl.so`,
and `libm.so`, all provided by Android. Through the emulator's arm64 translation,
the actual Termux app can start the patched server, query its API, use default
socket paths with mode 0600, and stop the server. The translation stalls at PTY
creation. A native x86_64 Android build of the same patches passes the full smoke
test in the actual Termux terminal, including PTY shell command execution.
See [the Android test notes](ANDROID-TEST-NOTES.md) for context and hashes.

Native ARM package installation and runtime are checked separately in CI using
the pinned Termux Docker image on a native ARM GitHub runner. The container
validates the target binary and userland, but does not duplicate Android app
seccomp/SELinux enforcement.

[CI run 37503145293](https://github.com/tensorlabresearch/herdr-termux/actions/runs/37503145293)
passed the independent build, all 13 package/installer checks, and a clean native
ARM `pkg install` followed by the full shell/session smoke test with `SHELL`
unset. The release uses the exact `.deb` from that run.

Release package: `herdr_0.9.3-1_aarch64.deb` (5,289,576 bytes).
SHA-256: `634fc754539a665970f569613e3413fadb6cd231c9ab5b54487690c9ce4ded8c`.
Packaged binary SHA-256:
`2925165e65a885fdbe0a3639620928ed31acbee08c0483efa0b2c58ae94a450f`.
The binary and patch hashes were checked against the CI build metadata, and
the release installer and smoke script match the source at commit `5e31cbe`.
The repository moved to `tensorlabresearch` on October 7, 2026; published
release assets retain their original checksums, and their previous download
URLs redirect to the organization's repository.

The first native ARM run installed the package successfully and exposed a shell
fallback defect when `SHELL` was absent: pane creation selected `/bin/sh`. The
source now selects Termux's `sh`, and the smoke test always clears `SHELL` and
inherited config routing. Retesting inside the actual Android app passed; a
process query confirmed `/data/data/com.termux/files/usr/bin/sh` was executing.

## Scope of checks

The upstream `just check` suite was not run: `just`/`cargo-nextest` and the
Windows SDK used by that cross-platform suite were not installed. This port
changes Android compile gates and platform paths. Validation instead includes
both Android architecture builds, formatting checks on changed Rust files,
ShellCheck, the 13 package/installer tests, and runtime tests of the changed
platform paths. No claim is made about running upstream's entire regression
suite.

## Phone acceptance

The Samsung Galaxy Z Fold (`SM_F976U1`) has not been accessed in this session.
The installation instructions and smoke-test asset are provided for a final
physical-device check. Phone-specific keyboard, touch, display resizing, and
Android background-process behavior require hands-on validation.

## Tab touch update — October 10, 2026

Patch `0003-termux-tab-options.patch` was validated with 299 passing client
shell tests (2 existing ignored tests), including active/inactive tab taps,
the compact mobile switcher, rename targeting, absence of clipboard writes,
drag-to-reorder, and context-menu dismissal. CI now runs this client suite.
All 13 packaging/installer checks, changed-file Rust formatting, patch source
verification, and Android aarch64/x86_64 release builds passed. The full upstream
`just check` was not run for the tool/Windows SDK reasons described above.

The native x86_64 build passed the full shell/session smoke test in the actual
Termux v0.118.3 app on a fresh read-only API 36.1 emulator. Android touch events
opened the tab menu; tapping Rename opened the existing dialog, saving changed
the tab name, and an outside tap dismissed the menu. Evidence is retained
locally in `build/tab-options-runtime/`. Resizing to 840×1700 also confirmed
that tapping a tab in the compact switcher opens the same three-item menu.

The local ARM64 update package is
`dist/tab-options/herdr_0.9.3-2_aarch64.deb`, SHA-256
`2f46e57bfa81051c17d015b21a73cf04966acd36872126c254cb3d22842ec28a`.
It has not been published as a GitHub Release or installed on the physical
phone. The existing `v0.9.3-termux.1` release assets are unchanged.
