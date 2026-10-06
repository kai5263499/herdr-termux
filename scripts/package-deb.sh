#!/usr/bin/env bash
# Build a standard-prefix Termux package without executing the target binary.
set -euo pipefail
export LC_ALL=C

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
binary="$repo_dir/dist/herdr"
source_dir="$repo_dir/upstream"
output_dir="$repo_dir/dist"
licenses_dir="$repo_dir/dist/licenses"
version=0.9.3-1
prefix=/data/data/com.termux/files/usr
readelf=${READELF:-readelf}

usage() {
  cat <<'EOF'
Usage: scripts/package-deb.sh [options]
  --binary PATH       Android aarch64 executable (default: dist/herdr)
  --source-dir PATH   Pinned upstream checkout (default: upstream)
  --version VERSION   Debian version (default: 0.9.3-1)
  --output-dir PATH   Artifact directory (default: dist)
  --licenses-dir PATH Third-party license notices (default: dist/licenses)

Requires readelf, dpkg-deb, and license notices from scripts/collect-licenses.py.
READELF may name llvm-readelf. SOURCE_DATE_EPOCH controls package timestamps.
EOF
}
die() { printf 'package-deb: %s\n' "$*" >&2; exit 1; }
while (($#)); do
  case "$1" in
    --binary|--source-dir|--version|--output-dir|--licenses-dir)
      (($# >= 2)) || die "Missing value for $1"
      case "$1" in
        --binary) binary=$2 ;;
        --source-dir) source_dir=$2 ;;
        --version) version=$2 ;;
        --output-dir) output_dir=$2 ;;
        --licenses-dir) licenses_dir=$2 ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$ ]] || die "Expected version such as 0.9.3-1"
[[ -f $binary ]] || die "Binary not found: $binary"
[[ -f $source_dir/LICENSE ]] || die "Upstream LICENSE not found in $source_dir"
[[ -d $licenses_dir && -n $(ls -A -- "$licenses_dir") ]] || die "Third-party notices missing: run scripts/collect-licenses.py first"
for tool in "$readelf" dpkg-deb sha256sum; do
  command -v "$tool" >/dev/null || die "Required tool missing: $tool"
done

elf_header=$("$readelf" -h -- "$binary")
[[ $elf_header == *'AArch64'* && $elf_header == *'ELF64'* ]] || die "Binary must be a 64-bit AArch64 ELF"
elf_programs=$("$readelf" -l -- "$binary")
interpreter=$(sed -n 's/.*Requesting program interpreter: \([^]]*\)].*/\1/p' <<<"$elf_programs")
[[ $interpreter == /system/bin/linker64 ]] || die "Expected Android interpreter /system/bin/linker64; found ${interpreter:-none}"
elf_dynamic=$("$readelf" -d -- "$binary")
mapfile -t needed < <(sed -n 's/.*(NEEDED).*\[\([^]]*\)\].*/\1/p' <<<"$elf_dynamic" | sort -u)
dependencies=()
for library in "${needed[@]}"; do
  case "$library" in
    # Android public NDK libraries, supplied by the OS, not apt packages.
    libc.so|libdl.so|libm.so|liblog.so|libandroid.so|libz.so) ;;
    # Termux ships the NDK shared C++ runtime in package libc++.
    libc++_shared.so) dependencies+=(libc++) ;;
    *) die "Unmapped ELF dependency: $library (add a verified Termux package mapping)" ;;
  esac
done
depends=''
if ((${#dependencies[@]})); then
  depends=$(printf '%s\n' "${dependencies[@]}" | sort -u | paste -sd, -)
  rpaths=$(sed -n 's/.*(\(RUNPATH\|RPATH\)).*\[\([^]]*\)\].*/\2/p' <<<"$elf_dynamic")
  [[ :$rpaths: == *":$prefix/lib:"* ]] || die "Termux shared libraries require RUNPATH $prefix/lib"
fi

mkdir -p -- "$output_dir"
output_dir=$(cd -- "$output_dir" && pwd)
stage=$(mktemp -d "${TMPDIR:-/tmp}/herdr-deb.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
doc_dir="$stage$prefix/share/doc/herdr"
install -d -- "$stage/DEBIAN" "$stage$prefix/bin" "$doc_dir/licenses"
install -m 755 -- "$binary" "$stage$prefix/bin/herdr"
install -m 644 -- "$source_dir/LICENSE" "$doc_dir/copyright"
cp -rf -- "$licenses_dir/." "$doc_dir/licenses/"
for vendor in libghostty-vt portable-pty; do
  for license_file in "$source_dir/vendor/$vendor/LICENSE" "$source_dir/vendor/$vendor/LICENSE.md"; do
    if [[ -f $license_file ]]; then
      install -m 644 -- "$license_file" "$doc_dir/licenses/$vendor-LICENSE"
    fi
  done
done
if [[ -f $(dirname -- "$binary")/build-info.txt ]]; then
  install -m 644 -- "$(dirname -- "$binary")/build-info.txt" "$doc_dir/build-info.txt"
fi
cat >"$doc_dir/README.termux" <<EOF
Herdr $version for Termux on aarch64 Android (API 24 or newer).
Upstream: https://github.com/herdrdev/herdr
Packaging, patches, and build instructions: https://github.com/kai5263499/herdr-termux
Updates: rerun that repository's release installer with --version RELEASE_TAG.
EOF
installed_size=$(du -sk -- "$stage$prefix" | awk '{print $1}')
cat >"$stage/DEBIAN/control" <<EOF
Package: herdr
Version: $version
Architecture: aarch64
Maintainer: Herdr Termux maintainers <herdr-termux@users.noreply.github.com>
Installed-Size: $installed_size
Section: utils
Priority: optional
Homepage: https://github.com/kai5263499/herdr-termux
Description: terminal workspace manager for AI coding agents
 Patched Android build for standard-prefix Termux on aarch64.
EOF
if [[ -n $depends ]]; then
  printf 'Depends: %s\n' "$depends" >>"$stage/DEBIAN/control"
fi

if [[ -z ${SOURCE_DATE_EPOCH:-} ]]; then
  SOURCE_DATE_EPOCH=$(git -C "$source_dir" show -s --format=%ct HEAD 2>/dev/null || printf 0)
fi
[[ $SOURCE_DATE_EPOCH =~ ^[0-9]+$ ]] || die "SOURCE_DATE_EPOCH must be a non-negative integer"
export SOURCE_DATE_EPOCH
# Normalize permissions and mtimes for reproducible archives.
chmod -R u=rwX,go=rX -- "$stage"
find "$stage" -print0 | xargs -0 touch -h -d "@$SOURCE_DATE_EPOCH"
asset="herdr_${version}_aarch64.deb"
dpkg-deb --root-owner-group -Zxz --build "$stage" "$output_dir/$asset"
(cd -- "$output_dir" && sha256sum "$asset" >SHA256SUMS)
printf 'ELF dependencies: %s\n' "${needed[*]:-none}"
printf 'Termux Depends: %s\n' "${depends:-none (Android system libraries only)}"
printf 'Package: %s/%s\n' "$output_dir" "$asset"
