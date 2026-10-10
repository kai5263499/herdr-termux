# Herdr through Termux pkg

## Phone setup and updates

Inside standard aarch64 Termux on Android API 24 or newer:

```sh
pkg update
pkg install -y curl
curl -fL https://tensorlabresearch.github.io/herdr-termux/setup-repo.sh -o setup-herdr-repo.sh && bash setup-herdr-repo.sh
pkg install herdr
herdr
```

Setup is needed once, including for an existing installation made with
`install.sh`. Repeating it replaces the same configuration files and does not
add duplicate sources. It restores the previous configuration if repository
authentication or refresh fails. It changes only Herdr's source and key files.

For normal updates, run `pkg upgrade`. This updates all installed packages.
For only Herdr, use `pkg update && pkg install herdr`. Check the downstream
version with `dpkg-query -W herdr`. After updating the interface, detach with
Ctrl+B then Q and run `herdr` again. See each release's notes for server changes.

The existing `herdr-update` command continues to fetch published GitHub Releases
and does not require the APT source. Both methods use the same package name and
Debian versions; switching to APT does not require uninstalling Herdr.

## Repository and trust

APT URL: `https://tensorlabresearch.github.io/herdr-termux/apt/`.
Suite: `stable`. Component: `main`. Architecture: `aarch64`.

Setup installs these files:

- `$PREFIX/etc/apt/keyrings/herdr-termux.gpg`
- `$PREFIX/etc/apt/sources.list.d/herdr-termux.list`

The source uses `signed-by` to scope the dedicated public key to Herdr's
repository. It does not install a globally trusted APT key. The setup script
pins the exported key's SHA-256 checksum. The initial script download relies on
HTTPS and control of this GitHub repository/Pages deployment.

Signing fingerprint: `9B9647411E81AA82EDA9E1302C544B16E40B2A1C`.
Key expiry: October 9, 2029. The exported public key and identity are in
[`apt/`](../apt/). The private key is never a release or Pages artifact.

The signed release metadata authenticates index hashes; the indexes authenticate
package hashes. Metadata expires after 30 days. Weekly publication refreshes it
without changing the application version. Users should never work around an
authentication failure with `trusted=yes` or `--allow-unauthenticated`.

## Publishing releases

The existing build workflow produces a draft release after build and runtime
tests. Review and publish that release normally. The separate
[`apt.yml`](../.github/workflows/apt.yml) workflow then:

1. Runs repository and bootstrap tests.
2. Downloads stable published Herdr Termux release packages, verifies their
   checksums, and validates package name, architecture, and version.
3. Generates and signs the complete repository, retaining published versions.
4. Installs by package name and upgrades from `0.9.3-1` in native ARM Termux
   userland; runs the shell/session smoke test on both current installations.
5. Deploys the complete artifact to GitHub Pages and repeats setup, installation,
   and upgrade against public HTTPS URLs.

Drafts and prereleases are excluded. Do not replace assets of a published
version; publish a higher Debian revision instead. Package checksums in GitHub
Releases are the publisher's input trust boundary before APT signing.

The workflow also runs weekly and supports manual recovery:

```sh
gh workflow run apt.yml --repo tensorlabresearch/herdr-termux --ref main
gh run list --repo tensorlabresearch/herdr-termux --workflow apt.yml
```

A release published by another workflow's default `GITHUB_TOKEN` does not
trigger a new workflow automatically; that publishing workflow must dispatch
`apt.yml` explicitly. The existing draft/review/publish process works with the
release event. Scheduling and manual dispatch also discover published releases.

GitHub Actions must remain enabled for weekly metadata refreshes. If schedules
are disabled after repository inactivity, enable the workflow and dispatch it.
Failure before deployment leaves the previously deployed repository intact.

## Signing key maintenance

The CI secret is `HERDR_APT_SIGNING_KEY`, containing the ASCII-armored dedicated
private signing key. It is imported into a temporary GNUPG directory for signing
and removed afterward. Signing and deployment never run for pull requests.
GitHub Pages uses an Actions publishing source and the `github-pages`
environment. Workflow concurrency serializes publications.

The initial local key backup and revocation certificate are under
`~/.config/herdr-termux/apt-signing/`, outside this checkout, with private
permissions. Store an additional encrypted offline backup under the maintainer's
control. Renew or rotate the key well before expiry. Export the updated public
key, update its pinned checksum in `setup-repo.sh`, and update the CI secret.
For a new key, provide an overlap/migration release while the old key remains
valid, and instruct existing users to rerun the new setup script. Updating the
script on the server alone does not update keys already installed on phones.

For suspected key compromise, stop publication, rotate the signing key and CI
secret, and publish explicit recovery instructions through the GitHub repository.

## Troubleshooting and removal

An expired Release file means publication needs to be refreshed; dispatch the
workflow and retry `pkg update`. For signature/key failures, verify the phone's
clock and compare the published fingerprint, then follow any key migration
instructions. Download failures or transient hash mismatches during a deployment
can be retried with `pkg update` after publication finishes.

To remove Herdr:

```sh
pkg uninstall herdr
```

To stop using this repository as well:

```sh
rm -f "$PREFIX/etc/apt/sources.list.d/herdr-termux.list"
rm -f "$PREFIX/etc/apt/keyrings/herdr-termux.gpg"
pkg update
```

Removing the source does not remove Herdr or its user data. The direct-release
installer and `herdr-update` remain an alternative if the repository is unavailable.

## Local validation

Host prerequisites: Python 3, Bash, GnuPG, APT tools (`apt-utils` on Debian/Ubuntu),
dpkg, curl, GitHub CLI, and ShellCheck. Run:

```sh
python3 -B tests/test-apt-repo.py
shellcheck setup-repo.sh scripts/test-apt-termux.sh
bash tests/test-packaging.sh
```

Packaging tests additionally require the Android NDK. Repository tests use
temporary keys, packages, HTTP servers, and isolated APT state. They never
install fixture packages on the host. Bootstrap tests relocate the literal
Termux prefix in a temporary script copy; the shipped script has no prefix
override. Native CI tests use the unmodified script; only Android's absent
property service is supplied by a `getprop` fixture in the Linux container.
