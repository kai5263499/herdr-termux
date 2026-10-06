#!/data/data/com.termux/files/usr/bin/bash
# Download and verify an exact release before passing it to Termux's pkg.
set -euo pipefail
export LC_ALL=C

release=v0.9.3-termux.1
repo=kai5263499/herdr-termux
termux_prefix=/data/data/com.termux/files/usr
die() { printf 'herdr installer: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'EOF'
Usage: bash install.sh [--version vVERSION-termux.REVISION]

Installs herdr on standard Termux, aarch64 Android API 24 or newer.
Default release: v0.9.3-termux.1
Rerun with a newer release tag to update. Uses pkg to resolve dependencies.
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
[[ $release =~ ^v([0-9]+\.[0-9]+\.[0-9]+)-termux\.([0-9]+)$ ]] || die 'Expected a release tag such as v0.9.3-termux.1'
package_version="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
[[ ${PREFIX:-} == "$termux_prefix" ]] || die "Run this inside standard Termux (PREFIX=$termux_prefix)"
[[ $(uname -s) == Linux && $(uname -m) == aarch64 ]] || die 'Only aarch64 Android is supported'
for tool in getprop dpkg dpkg-deb curl sha256sum pkg awk mktemp; do
  command -v "$tool" >/dev/null || die "Required command missing: $tool (install curl and coreutils with pkg)"
done
[[ $(dpkg --print-architecture) == aarch64 ]] || die 'This package requires aarch64 Termux'
api=$(getprop ro.build.version.sdk)
[[ $api =~ ^[0-9]+$ && $api -ge 24 ]] || die 'Android API 24 or newer is required'

asset="herdr_${package_version}_aarch64.deb"
base="https://github.com/$repo/releases/download/$release"
temp_dir=$(mktemp -d "${TMPDIR:-$PREFIX/tmp}/herdr-install.XXXXXXXX")
trap 'rm -rf -- "$temp_dir"' EXIT
fetch() {
  curl --fail --location --silent --show-error --retry 3 --proto '=https' --tlsv1.2 --output "$temp_dir/$1" "$base/$1"
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
printf 'Installed herdr %s. Run: herdr --version\nThen start a workspace with: herdr\n' "$package_version"
