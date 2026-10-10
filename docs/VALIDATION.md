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

The initial local ARM64 update candidate was
`dist/tab-options/herdr_0.9.3-2_aarch64.deb`, SHA-256
`2f46e57bfa81051c17d015b21a73cf04966acd36872126c254cb3d22842ec28a`.
It was superseded by the published package below, which also includes the
updater. The existing `v0.9.3-termux.1` release assets are unchanged.

## Published updater release — October 10, 2026

[v0.9.3-termux.2](https://github.com/tensorlabresearch/herdr-termux/releases/tag/v0.9.3-termux.2)
ships the tab touch patch and the packaged `herdr-update` command, from source
commit `afb1b8b47417358cef8837e6931231e472fbbd61`.

All 18 host packaging/updater checks and ShellCheck passed. Coverage includes
latest-release resolution, upgrading an older installation, equal/newer-version
no-ops, Debian version ordering, removed-package handling, failed discovery,
checksum rejection, and executable/dependency inclusion.

The Android build, 299 client tests, and packaging checks passed in
[build run 38069514040](https://github.com/tensorlabresearch/herdr-termux/actions/runs/38069514040).
The initial container updater check exposed the container's missing Android
property service. Its corrected test supplies only an API 24 `getprop` fixture;
native architecture, package installation, version comparison, and execution
remain real. Using the exact same build artifact,
[runtime recheck 38070127586](https://github.com/tensorlabresearch/herdr-termux/actions/runs/38070127586)
passed package installation, the installed updater's help/no-op path, and the
complete PTY shell/session smoke test. The phone installer retains its Android
API check.

Published package: `herdr_0.9.3-2_aarch64.deb` (5,296,632 bytes).
SHA-256: `9e9d459708b24e02543311b4f3c97b08a606f943c2b78681b8ed2ed7baadebf6`.
The public latest-installer URL and all five release assets were downloaded
without authentication and checked against the release checksums/source.
The package's updater matches `install.sh`; all patch hashes match the build
metadata. The local copy under `dist/tab-options/` now matches the release.
No physical phone was accessed.

## Signed APT repository — October 10, 2026

The [implementation plan](PKG-REPOSITORY-PLAN.md) and
[setup/maintenance guide](PKG-REPOSITORY.md) accompany the signed repository at
`https://tensorlabresearch.github.io/herdr-termux/apt/`.

[Publication run 38074234791](https://github.com/tensorlabresearch/herdr-termux/actions/runs/38074234791)
passed every job from commit `d8dca8b`: host checks, repository signing, native
ARM installation/upgrade, Pages deployment, and public HTTPS validation.
The first run exposed a missing `sources.list.d` directory in the disposable
container test harness; it stopped before deployment. The corrected harness
creates that directory, as the phone setup script already does.

All 14 repository/bootstrap tests and 18 existing packaging/installer tests
passed locally. ShellCheck and actionlint passed. The repository tests exercise
real APT signature validation, numeric version selection, authenticated package
downloads, upgrade resolution, and rejection of unsigned, expired, or modified
metadata and modified packages. Bootstrap checks cover repeated setup, platform
validation, pinned-key rejection, and restoring previous configuration after a
failed refresh.

Both native ARM CI checks installed `herdr` by name, ran the complete PTY
shell/session smoke test, installed the initial `0.9.3-1` release, and upgraded
to `0.9.3-2` with `pkg upgrade`. The post-deployment check downloaded the original
setup script from Pages, ran it twice successfully, and installed/upgraded from
the public HTTPS repository. Its only platform fixture supplies Android's API
level because the Linux container has no Android property service. APT, dpkg,
architecture checks, package installation, and application execution are native.

Public downloads of `setup-repo.sh` and the exported signing key matched the
committed files. The public `InRelease` signature verified with fingerprint
`9B9647411E81AA82EDA9E1302C544B16E40B2A1C`. The repository contains the original
published revision 1 and revision 2 packages; no binary was rebuilt or release
asset replaced for this distribution change. Weekly refresh and published-release
events renew the 30-day repository metadata. The signing key expires on
2029-10-09; renewal and recovery procedures are in the maintenance guide.

Local evidence: `build/apt-repository-tests.log`, `build/apt-packaging-tests.log`,
`build/apt-candidate-runtime.log`, `build/apt-live-runtime.log`, and
`build/apt-live/`. Physical-phone acceptance remains tracked in Hermes
`t_9db389a7`; no phone was accessed during this work.
