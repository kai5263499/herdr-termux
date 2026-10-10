# Herdr for Termux

A downstream Android/aarch64 package of [Herdr](https://github.com/herdrdev/herdr),
for running local terminal workspaces on an Android phone in Termux.
The package is based on Herdr 0.9.3 and uses the standard Termux prefix,
`/data/data/com.termux/files/usr`.

## Install on your phone

Use the standard `com.termux` app installed from an
[official Termux source](https://github.com/termux/termux-app#installation).
Run these commands **inside Termux on your aarch64 phone**:

```sh
pkg update
pkg install -y curl
curl -fL https://github.com/tensorlabresearch/herdr-termux/releases/latest/download/install.sh -o install-herdr.sh && bash install-herdr.sh
herdr --version
herdr
```

The installer checks the Termux prefix and architecture, downloads the `.deb`,
verifies its SHA-256 checksum, and installs it with the package manager.
The download and checksums come from the same HTTPS GitHub Release; this checks
download integrity and relies on the GitHub repository as the distribution trust source.
No Rust or Zig compiler is required on the phone.

`Ctrl+B`, then `Q`, detaches. Run `herdr` again to reattach.

The same commands upgrade an existing installation, including
`v0.9.3-termux.1`, and install the `herdr-update` command for future updates.

## Tab touch controls

Tap a tab to select it and open **New tab / Rename / Close**. In the compact
phone layout, open the switcher and tap a tab in its **tabs** section. Tap
outside the menu or press Escape to dismiss it. Tab dragging with a mouse
still reorders tabs.

Available starting with `v0.9.3-termux.2`.
Keep Herdr's `[ui] mouse_capture = true` enabled (the default) so Termux sends
taps to Herdr. Use a quick tap: a long press invokes Termux's Android text
selection, which is handled by the Termux app.

## Installation smoke test

To check the local server and shell automatically after installation:

```sh
curl -fL https://github.com/tensorlabresearch/herdr-termux/releases/latest/download/smoke-test.sh -o smoke-test.sh
sh smoke-test.sh "$(command -v herdr)"
```

This creates and removes an isolated test session and prints `PASS` on success.

## Update or remove

From any Termux shell, run:

```sh
herdr-update
```

It finds the latest published release from this repository, verifies the
package checksum and metadata, and installs through `pkg`. If your installed
version is current or newer, it reports that there is nothing to update.
No GitHub login or compiler is needed. The updater is part of the package and
updates along with Herdr.

After an update, detach an open Herdr client with **Ctrl+B**, then **Q**, and
run `herdr` again to load the new interface. The updater does not stop running
servers or pane processes. This release changes the client interface; future
server changes may have additional restart guidance in their release notes.

For a specific newer release, use `herdr-update --version v0.9.3-termux.2`.
Check the installed downstream revision with `dpkg-query -W herdr`;
`herdr --version` reports the upstream version (`0.9.3`).

Use `herdr-update` for this distribution. Normal `pkg upgrade` does not discover
GitHub releases, and upstream's `herdr update` does not install Android builds.
To remove the package and its updater:

```sh
pkg uninstall herdr
```

## Build and package

The build pins the upstream source and toolchain. See
[build details](docs/BUILD.md) for commands and the patch rationale, and
[validation](docs/VALIDATION.md) for the exact checks performed and their limits.
[TASKS.md](TASKS.md) contains the implementation tasks requested for this work;
the `herdr-termux` Hermes board holds live task status and follow-ups.

The original handoff's suggestion to use `termux/termux-docker` on an ordinary
x86 GitHub runner needs architecture handling: the default image follows the
host architecture. This project instead cross-compiles an Android binary with
the Android NDK and tests it in an Android/Termux environment.

## Source and licensing

Herdr is Apache-2.0 licensed. This repository contains build/distribution scripts
and patches, with original upstream and dependency notices included in the
package. Source is pinned to upstream commit
`7b116c05bfda646af39d2524c54e70c751f57ee8` (v0.9.3).
This is an independent downstream distribution.
