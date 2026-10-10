# Signed Termux package repository plan

Requested on 2026-10-10. Execution and follow-up status live in Hermes task
`t_82f9128c`; this file records the design, implementation sequence, and acceptance
criteria rather than duplicating the task board.

## Outcome

After one setup command inside standard aarch64 Termux, users can install Herdr
with `pkg install herdr` and receive updates with `pkg upgrade`. Existing
installations upgrade in place. No compiler, root access, or GitHub account is
needed on the phone. The current `herdr-update` command remains compatible.

## Architecture

Host a signed APT repository at
`https://tensorlabresearch.github.io/herdr-termux/apt/` using GitHub Pages.
Reuse the already published, tested Android `.deb` packages. Keep the package
name `herdr`, architecture `aarch64`, and existing Debian version ordering.

Generate `Packages`, compressed indexes, `Release`, `InRelease`, and
`Release.gpg`. Sign the metadata with a dedicated repository key. Publish only
non-draft, non-prerelease Herdr Termux releases with verified asset checksums
and matching package metadata. Retain published versions for package downloads.
GitHub Pages publishes the complete repository as one deployment.

Store the private signing key outside the checkout and in a dedicated GitHub
Actions secret. Commit only the public key and fingerprint. The phone setup
script pins the public key checksum and registers it with `signed-by`, limiting
its trust to this repository. Never use `trusted=yes` or disable authentication.

## Implementation sequence

1. Implement release retrieval and repository generation with strict package
   validation. Add checks covering genuine APT signature/index/package
   verification, rejection of tampering, and version selection.
2. Implement an idempotent phone setup script. Validate standard Termux,
   aarch64, and Android API 24 or newer before changing configuration. Download
   and verify the public key, install the scoped source configuration, and
   refresh this repository. Restore previous configuration if validation fails.
3. Add a publication workflow for published releases, manual runs, and weekly
   metadata refresh. Use expiring metadata, a dedicated signing secret, and
   serialized Pages deployments. Run host tests and native ARM Termux install
   and upgrade checks before deployment.
4. Generate and back up the dedicated signing key, provision the CI secret,
   enable Pages, and publish the existing reviewed release. Verify the live
   HTTPS repository using APT and verify installation in native Termux userland.
5. Document phone setup, ordinary updates, migration, removal, release
   publication, signing-key maintenance, and recovery. Commit and push the
   implementation and record evidence in `docs/VALIDATION.md` and Hermes.

## Validation and acceptance

The repository must authenticate successfully with its scoped public key.
Modified metadata and packages must be rejected. A clean Termux environment
must install Herdr by name; an older installed package must upgrade to the
published version. Repeated setup must not duplicate sources. Failed key
downloads or authentication must not leave broken configuration behind.

Run the existing packaging/installer tests, shell lint, and new repository
checks. Reuse the tested binary when only distribution code changes; rerun the
native ARM package/runtime smoke test through APT. A physical-phone check
remains separate from container validation and is tracked in `t_9db389a7`.

## Maintenance and boundaries

Weekly publication refreshes the metadata expiration without changing package
versions. Key renewal or rotation requires updating the CI secret, public key,
setup checksum, and migration instructions before the old key expires. Keep
recovery material outside Git. Ordinary releases retain the existing build,
test, and reviewed-publication process before entering APT.

Official Termux inclusion is a separate optional project: adapt the source build
to `termux-packages`, satisfy its packaging policy, test supported architectures,
and submit it for maintainer review. It is not required for `pkg` to use this
repository and is outside this initial implementation.

## References

- [Termux repository tooling](https://github.com/termux/termux-apt-repo)
- [APT sources and scoped signing keys](https://manpages.debian.org/stable/apt/sources.list.5.en.html)
- [GitHub Pages workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
- [Termux contribution requirements](https://github.com/termux/termux-packages/blob/master/CONTRIBUTING.md)
