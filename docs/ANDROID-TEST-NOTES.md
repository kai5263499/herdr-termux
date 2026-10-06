# Android runtime validation

Tested on October 6, 2026. No physical phone was connected.

## Environment

- Android emulator: the installed Samsung ZFold8 API36 AVD, started read-only
  without snapshots, using Android API36.1 Google APIs x86_64.
- Termux: official `termux/termux-app` GitHub debug APK v0.118.3, x86_64,
  with its standard bootstrap and `/data/data/com.termux/files/usr` prefix.
- ARM64 translation: the emulator's `libndk_translation.so` native bridge.
- Builds: upstream v0.9.3; local Android patches; Rust 1.98.0, Zig 0.16.0,
  Android NDK 28.2.13676358, Android API24 target.

Runtime commands were entered into the Termux terminal with Android input
events. They therefore ran under the actual app's SELinux and seccomp context.
`adb run-as com.termux` was used to copy binaries and retrieve logs, but its
less restrictive process context was not used to claim final app validation.

## Results

| Binary / execution context | Result |
| --- | --- |
| Official upstream x86_64 musl, Linux host | Full smoke passes; verifies the smoke script against unmodified upstream. |
| Official upstream x86_64 musl, Android `run-as` | Full smoke passes, but this is insufficient app-context evidence. |
| Official upstream x86_64 musl, actual Termux terminal | Direct `--version` exits159, corresponding to SIGSYS (signal31); smoke reports `Unknown signal 31`. |
| Official upstream aarch64 musl, Android native bridge | `--version` prints `herdr 0.9.3`; API requests crash with SIGSEGV in the translation runner. No successful ARM64 musl PTY/session result. |
| Patched aarch64 Android/Bionic, actual Termux terminal through native bridge | `--version`, server startup, API snapshot, standard HOME config socket paths, server shutdown, and update guard all pass. Creating a PTY stalls after `pane.spawn.start`; a forked translation runner remains blocked. |
| Patched x86_64 Android/Bionic, actual Termux terminal, native execution | Full smoke passes with exit0: version, named server/session, workspace creation, PTY shell command, shell PID, running session, server stop, and session delete. Interactive TUI also starts with a Bash pane, renders correctly, and executes keyboard input. |

The native x86_64 Android test binary SHA256 was
`1fd777b916b284f3fcba1236c8575b67eb3a924f384bc3b321dc5c5ea2d95b56`.
It was built from the initial Android runtime patches used for the ARM64
package candidate. These emulator smoke and TUI checks inherited the normal
Termux `SHELL=/data/data/com.termux/files/usr/bin/bash` environment.

For the interactive check, the TUI was launched normally from Termux with an
isolated config and named session. Its automatic daemon startup created the
first workspace and Bash pane. Typing `echo TUI_WORKS` into the TUI produced
the separate output line `TUI_WORKS`. A process query identified the foreground
shell as `/data/data/com.termux/files/usr/bin/bash` with its actual PID, command
line, process group, and home-directory cwd. This also verifies that Android
process inspection works for this app's own pane processes in the emulator.

The ARM64 default-location check created sockets with mode0600 at:

```text
/data/data/com.termux/files/home/.config/herdr/herdr.sock
/data/data/com.termux/files/home/.config/herdr/herdr-client.sock
```

Its API snapshot reported version `0.9.3`, protocol `22`. `herdr update`
exited1 and printed:

```text
self-update is disabled for Termux packages; rerun the herdr-termux installer to install a package update
```

## Reproducing the smoke test

Run from the normal Termux terminal after installing the package:

```sh
sh scripts/smoke-test.sh "$(command -v herdr)"
```

The script requires `timeout` from Termux's coreutils. It uses a private
temporary config/state directories and named session, clears inherited Herdr
routing, `HERDR_CONFIG_PATH`, and `SHELL`, and leaves existing sessions
untouched. Its config does not set
`terminal.default_shell`, so it exercises the platform's fallback shell path.
The output marker is assembled by the
shell command, so terminal input echo cannot produce a false pass. Failure logs
remain under the printed temporary directory; successful test state is removed.

## Additional gap found by native ARM64 CI

The first native ARM64 Termux container run installed the package successfully
but failed workspace creation because Herdr attempted to launch `/bin/sh`.
The container entrypoint clears `SHELL`; the original app-context checks had
therefore not exercised this fallback. The smoke script now explicitly unsets
`SHELL` for both its server and CLI processes. The source fallback fix and
subsequent native ARM64 results are recorded in the main validation report.

After the fix, a fresh read-only emulator instance and official Termux app were
used to rerun the final, unmodified smoke script in the actual app context.
With `SHELL` and `HERDR_CONFIG_PATH` explicitly cleared, all smoke checks passed
with exit0. A supplemental diagnostic run printed the pane process record and
confirmed both argv and command line were
`/data/data/com.termux/files/usr/bin/sh`; the fallback did not use `/bin/sh`.

The updated native x86_64 Android test binary SHA256 was
`c8c2270e410cbe78da68bf33856001af4c46dc5e56e1db9166dad3b28c4c22f1`.
The unmodified smoke script SHA256 was
`b0a12c8f5b79dd58a24a7a36321d38586ae9de82aa59bc4b2d20481ac804ccd8`.
Both hashes were verified on the emulator after copying. Local evidence is
retained under `build/runtime-validation/` as `smoke-unset-shell-ui.log`,
`fallback-process-ui.log`, and `fallback-test-sha256.txt`.

## Limits

The ARM64 PTY stall occurs only in the tested translation path; native x86_64
Android passes. This supports a native-bridge limitation, but is not proof that
the physical ARM64 phone works. The published ARM64 package still needs an
on-device check on the Samsung phone. Native ARM64 Termux container CI, where
available, checks the target binary and package userland but does not reproduce
Android app seccomp, SELinux, or phone lifecycle restrictions.

The original proposal to package an upstream musl binary merely because
`--version` succeeds is not an adequate compatibility gate.
