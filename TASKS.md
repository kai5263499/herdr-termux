# Herdr for Termux implementation tasks

Source: `/home/wes/herdr-termux-plan.md`, prepared October 6, 2026.
Target: Samsung Galaxy Z Fold, aarch64 Android, standard Termux prefix.

This document records the requested implementation work and acceptance criteria.
Live progress and follow-up work are tracked on the Hermes `herdr-termux` board.

| Hermes task | Responsibility |
| --- | --- |
| `t_19ebfbb0` | Pinned Android build and patches |
| `t_4b9be6bb` | Package, installer, and packaging checks |
| `t_5dd1d762` | Runtime patches and Android smoke testing |
| `t_2f47e12e` | Integration, notices, CI, documentation, and publication |
| `t_a721f502` | Fix the missing-SHELL fallback exposed by native ARM testing |

| Work | Acceptance criteria | Owner |
| --- | --- | --- |
| Inspect upstream and available phone/emulator access | Pin v0.9.3 and record whether the upstream musl binary can actually run on Android. | Integration/runtime |
| Build for Android | Reproducible patched build produces an aarch64 Android binary; record toolchain versions and source revision. | Build agent |
| Package for Termux | `.deb` installs under `/data/data/com.termux/files/usr`; dependencies come from ELF analysis. | Packaging agent |
| Install and update | Download installer verifies checksums, checks architecture/platform, and supports installing subsequent releases. | Packaging agent |
| Exercise runtime | Check version, server/session lifecycle and a shell pane in available Android environment; distinguish emulator results from physical-phone results. | Runtime agent |
| Automate releases | CI builds and validates packages using a documented, supported toolchain; publish reviewed artifacts through selected distribution channel. | Runtime/integration |
| Deliver | Commit and push source; publish downloadable package and exact phone installation commands; record unresolved device-only checks in Hermes. | Integration |

## Decisions and constraints

- The explicit request to install on the phone establishes intent for local Termux use.
- Upstream latest release is still v0.9.3 as verified with GitHub on October 6, 2026.
- No ADB device is connected initially. Android NDK r27 and r28 are installed locally.
- Distribution uses GitHub Releases and a versioned install/update script.
- Do not modify V3SP3R, Tab-Recorder, the macOS installation, or the dotfiles SSH helper.
- Never label an emulator or host test as a successful physical-phone test.

## Implementation handoff

The downstream source repository is
[tensorlabresearch/herdr-termux](https://github.com/tensorlabresearch/herdr-termux).
The build, package, installer, dependency notices, Android smoke script, and CI
are implemented. Thirteen package/installer checks pass. A native x86_64 Android
build passes full shell/session testing in the actual Termux application.
The aarch64 package also passes clean installation and full shell/session
testing on a native ARM runner in CI, including the missing-SHELL regression.
See [validation evidence](docs/VALIDATION.md) for the separate ARM checks and
execution-context limits.

Remaining follow-ups are tracked in Hermes: `t_9db389a7` for physical Galaxy Z
Fold verification and `t_9aeb30f1` for reviewing future upstream releases.

Installable release: [v0.9.3-termux.1](https://github.com/tensorlabresearch/herdr-termux/releases/tag/v0.9.3-termux.1).
Phone installation commands are in [README.md](README.md).
