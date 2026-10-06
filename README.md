# Herdr for Termux

A downstream Android/aarch64 package of [Herdr](https://github.com/herdrdev/herdr),
for running local terminal workspaces on an Android phone in Termux.
The initial package is based on Herdr 0.9.3 and uses the standard Termux prefix,
`/data/data/com.termux/files/usr`.

## Install on your phone

Use the standard `com.termux` app installed from an
[official Termux source](https://github.com/termux/termux-app#installation).
Run these commands **inside Termux on your aarch64 phone**:

```sh
pkg update
pkg install curl
curl -fL https://github.com/kai5263499/herdr-termux/releases/download/v0.9.3-termux.1/install.sh -o install-herdr.sh
bash install-herdr.sh
herdr --version
herdr
```

The installer checks the Termux prefix and architecture, downloads the `.deb`,
verifies its SHA-256 checksum, and installs it with the package manager.
The download and checksums come from the same HTTPS GitHub Release; this checks
download integrity and relies on the GitHub repository as the distribution trust source.
No Rust or Zig compiler is required on the phone.

`Ctrl+B`, then `Q`, detaches. Run `herdr` again to reattach.

## Update or remove

For a later published release, download its installer from the
[releases page](https://github.com/kai5263499/herdr-termux/releases)
and run it, or use the existing installer with `--version RELEASE_TAG`.
For example, the initial version is `v0.9.3-termux.1`.
This distribution is installed as a local Debian package; normal `pkg upgrade`
does not discover new Herdr releases without an apt repository.
Use this distribution's installer to update; upstream's release binaries do not
include this Android build.

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
