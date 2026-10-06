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

The Android aarch64 cross-build has succeeded. Its interpreter is
`/system/bin/linker64` and its dynamic dependencies are `libc.so`, `libdl.so`,
and `libm.so`, all provided by Android. Candidate runtime and package installation
checks are in progress; final results will be recorded before publication.

## Phone acceptance

The Samsung Galaxy Z Fold (`SM_F976U1`) has not been accessed in this session.
The installation instructions and smoke-test asset are provided for a final
physical-device check. Phone-specific keyboard, touch, display resizing, and
Android background-process behavior require hands-on validation.
