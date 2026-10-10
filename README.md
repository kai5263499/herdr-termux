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
curl -fL https://tensorlabresearch.github.io/herdr-termux/setup-repo.sh -o setup-herdr-repo.sh && bash setup-herdr-repo.sh
pkg install herdr
herdr --version
herdr
```

The setup script checks the Termux prefix, architecture, and Android API level,
verifies the pinned repository public key, and registers a signed APT source.
APT authenticates the repository metadata and package downloads. The initial
setup script is trusted through HTTPS GitHub Pages. No Rust or Zig compiler,
root access, or GitHub login is required on the phone.

`Ctrl+B`, then `Q`, detaches. Run `herdr` again to reattach.

Run setup once per Termux installation. It is safe to repeat, and existing
installations (including `v0.9.3-termux.1`) upgrade in place with `pkg install herdr`.
The [repository guide](docs/PKG-REPOSITORY.md) covers trust, troubleshooting,
removal, and maintenance. The [implementation plan](docs/PKG-REPOSITORY-PLAN.md)
records the design and acceptance criteria.

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
pkg upgrade
```

This updates all installed Termux packages, including Herdr. To refresh the
package lists and update only Herdr, run `pkg update && pkg install herdr`.
New reviewed releases are published automatically to the signed repository.

After an update, detach an open Herdr client with **Ctrl+B**, then **Q**, and
run `herdr` again to load the new interface. Updating does not stop running
servers or pane processes. This release changes the client interface; future
server changes may have additional restart guidance in their release notes.

For a specific newer release, use `herdr-update --version v0.9.3-termux.2`.
Check the installed downstream revision with `dpkg-query -W herdr`;
`herdr --version` reports the upstream version (`0.9.3`).

The packaged `herdr-update` command remains available as a direct GitHub Release
fallback; it skips installed equal/newer versions. Upstream's `herdr update`
does not install Android builds. To remove the package and its updater:

```sh
pkg uninstall herdr
```

If you prefer not to register the APT repository, the original installer is
still available; future updates on that path use `herdr-update`:

```sh
curl -fL https://github.com/tensorlabresearch/herdr-termux/releases/latest/download/install.sh -o install-herdr.sh && bash install-herdr.sh
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
