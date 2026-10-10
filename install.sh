#!/data/data/com.termux/files/usr/bin/bash
# Install or update from a verified Termux release. Also packaged as herdr-update.
set -euo pipefail
export LC_ALL=C

release=latest
repo=tensorlabresearch/herdr-termux
termux_prefix=/data/data/com.termux/files/usr
die() { printf 'herdr installer: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'EOF'
Usage: herdr-update [--version vVERSION-termux.REVISION]
       bash install.sh [--version vVERSION-termux.REVISION]

Installs or updates herdr on standard Termux, aarch64 Android API 24 or newer.
Defaults to the latest published Termux release. Uses pkg for installation.
Already installed versions are skipped; newer versions are never downgraded.
EOF
}
while (($#)); do
  case "$1" in
    --version)
      (($# >= 2)) || die 'Missing release tag after --version'
      release=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done
[[ $release == latest || $release =~ ^v[0-9]+\.[0-9]+\.[0-9]+-termux\.[0-9]+$ ]] || die 'Expected a release tag such as v0.9.3-termux.2'
[[ ${PREFIX:-} == "$termux_prefix" ]] || die "Run this inside standard Termux (PREFIX=$termux_prefix)"
[[ $(uname -s) == Linux && $(uname -m) == aarch64 ]] || die 'Only aarch64 Android is supported'
for tool in getprop dpkg dpkg-query dpkg-deb curl sha256sum pkg awk mktemp; do
  command -v "$tool" >/dev/null || die "Required command missing: $tool (install curl and coreutils with pkg)"
done
[[ $(dpkg --print-architecture) == aarch64 ]] || die 'This package requires aarch64 Termux'
api=$(getprop ro.build.version.sdk)
[[ $api =~ ^[0-9]+$ && $api -ge 24 ]] || die 'Android API 24 or newer is required'

curl_args=(--fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 120 --proto '=https' --proto-redir '=https' --tlsv1.2)
if [[ $release == latest ]]; then
  printf 'Checking the latest Herdr Termux release...\n'
  release_url=$(curl "${curl_args[@]}" --head --output /dev/null --write-out '%{url_effective}' "https://github.com/$repo/releases/latest") || die 'Could not check the latest release; try again when connected'
  [[ $release_url == "https://github.com/$repo/releases/tag/"* ]] || die 'Unexpected latest release URL'
  release=${release_url##*/}
fi
[[ $release =~ ^v([0-9]+\.[0-9]+\.[0-9]+)-termux\.([0-9]+)$ ]] || die 'Expected a release tag such as v0.9.3-termux.2'
package_version="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
installed=$(dpkg-query -W -f='${Status} ${Version}' herdr 2>/dev/null || true)
if [[ $installed == 'install ok installed '* ]]; then
  installed_version=${installed##* }
  if dpkg --compare-versions "$installed_version" ge "$package_version"; then
    printf 'Herdr %s is already installed (selected release: %s); nothing to update.\n' "$installed_version" "$package_version"
    exit 0
  fi
fi

asset="herdr_${package_version}_aarch64.deb"
base="https://github.com/$repo/releases/download/$release"
temp_dir=$(mktemp -d "${TMPDIR:-$PREFIX/tmp}/herdr-install.XXXXXXXX")
trap 'rm -rf -- "$temp_dir"' EXIT
fetch() {
  curl "${curl_args[@]}" --output "$temp_dir/$1" "$base/$1"
}
printf 'Downloading herdr %s for aarch64 Termux...\n' "$package_version"
fetch SHA256SUMS
fetch "$asset"
checksum=$(awk -v name="$asset" '$2 == name || $2 == "*" name {print $1}' "$temp_dir/SHA256SUMS")
[[ $checksum =~ ^[0-9a-fA-F]{64}$ ]] || die "Missing or ambiguous SHA256SUMS entry for $asset"
if ! (cd -- "$temp_dir" && printf '%s  %s\n' "$checksum" "$asset" | sha256sum --check --status); then
  die 'SHA-256 verification failed; package was not installed'
fi
[[ $(dpkg-deb -f "$temp_dir/$asset" Package) == herdr ]] || die 'Unexpected package name'
[[ $(dpkg-deb -f "$temp_dir/$asset" Architecture) == aarch64 ]] || die 'Unexpected package architecture'
[[ $(dpkg-deb -f "$temp_dir/$asset" Version) == "$package_version" ]] || die 'Unexpected package version'
printf 'Checksum verified. Installing through pkg...\n'
pkg install -y "$temp_dir/$asset"
printf 'Installed herdr %s. Future updates: herdr-update\n' "$package_version"
printf 'If Herdr is open, detach with Ctrl+B then Q and run herdr again to load the updated interface.\n'
