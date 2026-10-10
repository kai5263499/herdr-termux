#!/data/data/com.termux/files/usr/bin/bash
# Register the signed Herdr repository; package installation stays with pkg.
set -euo pipefail
export LC_ALL=C

termux_prefix=/data/data/com.termux/files/usr
repo_url=https://tensorlabresearch.github.io/herdr-termux/apt
key_sha256=5be6c45a95ae82350a94f1e3dfa84107cdbd8cd2563c5c22ce66afbfef6979fc
die() { printf 'herdr repository setup: %s\n' "$*" >&2; exit 1; }
if [[ $# == 1 && ( $1 == --help || $1 == -h ) ]]; then
  printf 'Usage: bash setup-repo.sh\nRegisters the signed Herdr APT repository on aarch64 Termux (Android API 24+).\nThen use pkg install herdr and pkg upgrade.\n'
  exit 0
fi
[[ $# == 0 ]] || die 'No arguments expected (use --help for usage)'
[[ ${PREFIX:-} == "$termux_prefix" ]] || die "Run this inside standard Termux (PREFIX=$termux_prefix)"
[[ $(uname -s) == Linux && $(uname -m) == aarch64 ]] || die 'Only aarch64 Android is supported'
for tool in getprop dpkg curl sha256sum apt-get mktemp install; do
  command -v "$tool" >/dev/null || die "Required command missing: $tool (install curl and coreutils with pkg)"
done
[[ $(dpkg --print-architecture) == aarch64 ]] || die 'This repository requires aarch64 Termux'
api=$(getprop ro.build.version.sdk)
[[ $api =~ ^[0-9]+$ && $api -ge 24 ]] || die 'Android API 24 or newer is required'

key_dir="$PREFIX/etc/apt/keyrings"
source_dir="$PREFIX/etc/apt/sources.list.d"
key_file="$key_dir/herdr-termux.gpg"
source_file="$source_dir/herdr-termux.list"
[[ ! -L $key_file && ! -L $source_file ]] || die 'Refusing to replace symlinked repository configuration'
temp_dir=$(mktemp -d "${TMPDIR:-$PREFIX/tmp}/herdr-repo.XXXXXXXX")
changed=0
committed=0
staged_key=''
staged_source=''
cleanup() {
  local result=$?
  if ((changed && !committed)); then
    if [[ -f $temp_dir/previous-key ]]; then
      cp -f -- "$temp_dir/previous-key" "$key_file"
    else
      rm -f -- "$key_file"
    fi
    if [[ -f $temp_dir/previous-source ]]; then
      cp -f -- "$temp_dir/previous-source" "$source_file"
    else
      rm -f -- "$source_file"
    fi
    printf 'Previous Herdr repository configuration restored.\n' >&2
  fi
  [[ -z $staged_key ]] || rm -f -- "$staged_key"
  [[ -z $staged_source ]] || rm -f -- "$staged_source"
  rm -rf -- "$temp_dir"
  return "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
curl --fail --location --silent --show-error --retry 3 \
  --connect-timeout 15 --max-time 120 --proto '=https' --proto-redir '=https' \
  --output "$temp_dir/key.gpg" "$repo_url/herdr-termux.gpg"
printf '%s  %s\n' "$key_sha256" "$temp_dir/key.gpg" | sha256sum --check --status || die 'Repository key checksum mismatch'

[[ ! -f $key_file ]] || cp -f -- "$key_file" "$temp_dir/previous-key"
[[ ! -f $source_file ]] || cp -f -- "$source_file" "$temp_dir/previous-source"
install -d -m 755 -- "$key_dir" "$source_dir"
staged_key=$(mktemp "$key_dir/.herdr-key.XXXXXXXX")
staged_source=$(mktemp "$source_dir/.herdr-source.XXXXXXXX")
install -m 644 -- "$temp_dir/key.gpg" "$staged_key"
printf 'deb [arch=aarch64 signed-by=%s] %s stable main\n' "$key_file" "$repo_url" >"$staged_source"
chmod 644 "$staged_source"
changed=1
mv -f -- "$staged_key" "$key_file"
mv -f -- "$staged_source" "$source_file"

# Validate this source only. Any network or authentication failure is fatal;
# unrelated configured repositories do not prevent setup or affect rollback.
apt-get -o "Dir::Etc::sourcelist=$source_file" -o 'Dir::Etc::sourceparts=-' \
  -o APT::Update::Error-Mode=any -o Acquire::AllowInsecureRepositories=false \
  -o Acquire::AllowDowngradeToInsecureRepositories=false update || die 'Repository refresh failed'
committed=1
printf '\nHerdr repository configured and authenticated.\nInstall or update Herdr: pkg install herdr\nUpdate all packages: pkg upgrade\n'
