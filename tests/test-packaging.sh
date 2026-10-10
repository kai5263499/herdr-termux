#!/usr/bin/env bash
# Real Android ELF/package fixtures; all installer network and pkg calls are mocked.
# No package is installed and nothing is written outside a temporary directory.
set -euo pipefail
export LC_ALL=C
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/herdr-packaging-test.XXXXXXXX")
trap 'rm -rf -- "$test_dir"' EXIT
test_count=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { test_count=$((test_count + 1)); printf 'ok %s - %s\n' "$test_count" "$*"; }
expect_failure() {
  local expected=$1
  shift
  if "$@" >"$test_dir/failure.log" 2>&1; then
    fail "Command unexpectedly succeeded: $*"
  fi
  grep -Fq -- "$expected" "$test_dir/failure.log" || {
    cat "$test_dir/failure.log" >&2
    fail "Expected diagnostic: $expected"
  }
}

android_cc=${TEST_ANDROID_CC:-}
if [[ -z $android_cc ]]; then
  ndk=${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}
  if [[ -n $ndk ]]; then
    android_cc="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang"
  else
    for candidate in "${ANDROID_HOME:-$HOME/Android/Sdk}"/ndk/*/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang; do
      [[ ! -x $candidate ]] || android_cc=$candidate
    done
  fi
fi
[[ -n $android_cc && -x $android_cc ]] || fail 'Set ANDROID_NDK_HOME or TEST_ANDROID_CC to run ELF packaging tests'
mkdir -p "$test_dir/source" "$test_dir/licenses" "$test_dir/release" "$test_dir/mockbin" "$test_dir/tmp"
printf 'Upstream license fixture\n' >"$test_dir/source/LICENSE"
printf 'Third-party license fixture\n' >"$test_dir/licenses/NOTICE"
printf 'int main(void) { return 0; }\n' >"$test_dir/main.c"
"$android_cc" "$test_dir/main.c" -o "$test_dir/herdr"
package=(bash "$repo_dir/scripts/package-deb.sh" --source-dir "$test_dir/source" --licenses-dir "$test_dir/licenses" --output-dir "$test_dir/release")
SOURCE_DATE_EPOCH=1700000000 "${package[@]}" --binary "$test_dir/herdr" >"$test_dir/package.log"
deb="$test_dir/release/herdr_0.9.3-2_aarch64.deb"
[[ $(dpkg-deb -f "$deb" Package) == herdr ]] || fail 'Wrong package name'
[[ $(dpkg-deb -f "$deb" Architecture) == aarch64 ]] || fail 'Wrong package architecture'
[[ $(dpkg-deb -f "$deb" Version) == 0.9.3-2 ]] || fail 'Wrong package version'
[[ $(dpkg-deb -f "$deb" Depends) == 'bash, coreutils, curl, dpkg, gawk, termux-tools' ]] || fail 'Wrong updater dependencies or bionic libraries added as apt dependencies'
pass 'real Android ELF includes updater dependencies without guessed bionic dependencies'

dpkg-deb -x "$deb" "$test_dir/extracted"
[[ -x $test_dir/extracted/data/data/com.termux/files/usr/bin/herdr ]] || fail 'Executable missing or not executable'
updater="$test_dir/extracted/data/data/com.termux/files/usr/bin/herdr-update"
[[ -x $updater ]] || fail 'Packaged updater missing or not executable'
cmp -s "$repo_dir/install.sh" "$updater" || fail 'Packaged updater differs from installer'
[[ -f $test_dir/extracted/data/data/com.termux/files/usr/share/doc/herdr/copyright ]] || fail 'Upstream license missing'
[[ -f $test_dir/extracted/data/data/com.termux/files/usr/share/doc/herdr/licenses/NOTICE ]] || fail 'Dependency notices missing'
while IFS= read -r file; do
  [[ $file == data/data/com.termux/files/usr/* ]] || fail "Package installs outside Termux prefix: $file"
done < <(cd "$test_dir/extracted" && find . -type f -printf '%P\n')
pass 'package files and licenses install exclusively under the standard Termux prefix'

first_sha=$(sha256sum "$deb" | awk '{print $1}')
SOURCE_DATE_EPOCH=1700000000 "${package[@]}" --binary "$test_dir/herdr" >"$test_dir/package.log"
[[ $(sha256sum "$deb" | awk '{print $1}') == "$first_sha" ]] || fail 'Package output is not reproducible'
(cd "$test_dir/release" && sha256sum -c SHA256SUMS >/dev/null)
pass 'fixed timestamps produce a reproducible package and matching SHA256SUMS'

expect_failure '64-bit AArch64 ELF' "${package[@]}" --binary /bin/true
pass 'packager rejects a host architecture binary'
"$android_cc" "$test_dir/main.c" -Wl,--dynamic-linker=/lib/ld-linux-aarch64.so.1 -o "$test_dir/linux-herdr"
expect_failure 'Expected Android interpreter' "${package[@]}" --binary "$test_dir/linux-herdr"
pass 'packager rejects a Linux loader even on an aarch64 ELF'

printf 'int custom(void) { return 0; }\n' >"$test_dir/custom.c"
"$android_cc" -shared -fPIC "$test_dir/custom.c" -Wl,-soname,libherdr-test-unknown.so -o "$test_dir/libherdr-test-unknown.so"
printf 'extern int custom(void); int main(void) { return custom(); }\n' >"$test_dir/custom-main.c"
"$android_cc" "$test_dir/custom-main.c" -L"$test_dir" -lherdr-test-unknown -o "$test_dir/unknown-herdr"
expect_failure 'Unmapped ELF dependency: libherdr-test-unknown.so' "${package[@]}" --binary "$test_dir/unknown-herdr"
pass 'packager refuses unrecognized shared libraries'

"$android_cc" "$test_dir/main.c" -Wl,--no-as-needed -lc++_shared -Wl,-rpath,/data/data/com.termux/files/usr/lib -o "$test_dir/cpp-herdr"
"${package[@]}" --binary "$test_dir/cpp-herdr" --output-dir "$test_dir/cpp-release" >"$test_dir/package.log"
[[ $(dpkg-deb -f "$test_dir/cpp-release/herdr_0.9.3-2_aarch64.deb" Depends) == 'bash, coreutils, curl, dpkg, gawk, libc++, termux-tools' ]] || fail 'C++ runtime dependency was not mapped'
"$android_cc" "$test_dir/main.c" -Wl,--no-as-needed -lc++_shared -o "$test_dir/no-rpath-herdr"
expect_failure 'Termux shared libraries require RUNPATH' "${package[@]}" --binary "$test_dir/no-rpath-herdr"
pass 'C++ runtime maps to libc++ and requires the Termux library search path'

cat >"$test_dir/mockbin/uname" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  -s) printf '%s\n' "${MOCK_OS:-Linux}" ;;
  -m) printf '%s\n' "${MOCK_ARCH:-aarch64}" ;;
  *) exit 99 ;;
esac
EOF
cat >"$test_dir/mockbin/dpkg" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --print-architecture) printf '%s\n' "${MOCK_DPKG_ARCH:-aarch64}" ;;
  --compare-versions) exec "$REAL_DPKG" "$@" ;;
  *) exit 99 ;;
esac
EOF
cat >"$test_dir/mockbin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
[[ $* == '-W -f=${Status} ${Version} herdr' ]] || exit 99
[[ -n ${MOCK_INSTALLED:-} ]] || exit 1
printf '%s %s' "${MOCK_INSTALLED_STATUS:-install ok installed}" "$MOCK_INSTALLED"
EOF
cat >"$test_dir/mockbin/getprop" <<'EOF'
#!/usr/bin/env bash
[[ $1 == ro.build.version.sdk ]] || exit 99
printf '%s\n' "${MOCK_API:-35}"
EOF
cat >"$test_dir/mockbin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
destination=''
url=''
while (($#)); do
  case "$1" in
    --output) destination=$2; shift 2 ;;
    --retry|--proto|--proto-redir|--connect-timeout|--max-time|--write-out) shift 2 ;;
    --fail|--location|--silent|--show-error|--tlsv1.2|--head) shift ;;
    https://*) url=$1; shift ;;
    *) exit 98 ;;
  esac
done
printf '%s\n' "$url" >>"$MOCK_NETWORK_LOG"
if [[ $url == https://github.com/tensorlabresearch/herdr-termux/releases/latest ]]; then
  [[ ${MOCK_LATEST_FAIL:-0} == 0 ]] || exit 22
  printf '%s' "${MOCK_LATEST_URL:-https://github.com/tensorlabresearch/herdr-termux/releases/tag/${MOCK_RELEASE:-v0.9.3-termux.2}}"
  exit 0
fi
case "$url" in
  "https://github.com/tensorlabresearch/herdr-termux/releases/download/${MOCK_RELEASE:-v0.9.3-termux.2}/"*) ;;
  *) printf 'Unexpected URL: %s\n' "$url" >&2; exit 99 ;;
esac
cp -f -- "$MOCK_RELEASE_DIR/${url##*/}" "$destination"
if [[ ${MOCK_TAMPER:-0} == 1 && $destination == *.deb ]]; then
  printf 'tampered\n' >>"$destination"
fi
EOF
cat >"$test_dir/mockbin/pkg" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ $# == 3 && $1 == install && $2 == -y && -f $3 ]] || exit 99
printf '%s\n' "$*" >>"$MOCK_PKG_LOG"
EOF
chmod +x "$test_dir/mockbin/"*
installer=(env "PATH=$test_dir/mockbin:$PATH" "REAL_DPKG=$(command -v dpkg)" PREFIX=/data/data/com.termux/files/usr "TMPDIR=$test_dir/tmp" "MOCK_RELEASE_DIR=$test_dir/release" "MOCK_NETWORK_LOG=$test_dir/network.log" "MOCK_PKG_LOG=$test_dir/pkg.log")

expect_failure 'Only aarch64 Android is supported' "${installer[@]}" MOCK_ARCH=x86_64 bash "$repo_dir/install.sh"
expect_failure 'Only aarch64 Android is supported' "${installer[@]}" MOCK_OS=Darwin bash "$repo_dir/install.sh"
[[ ! -f $test_dir/network.log && ! -f $test_dir/pkg.log ]] || fail 'Invalid architecture caused network or installation effects'
expect_failure 'requires aarch64 Termux' "${installer[@]}" MOCK_DPKG_ARCH=arm bash "$repo_dir/install.sh"
expect_failure 'Run this inside standard Termux' "${installer[@]}" PREFIX=/usr bash "$repo_dir/install.sh"
expect_failure 'Android API 24 or newer' "${installer[@]}" MOCK_API=23 bash "$repo_dir/install.sh"
expect_failure 'Expected a release tag' "${installer[@]}" bash "$repo_dir/install.sh" --version ../latest
pass 'installer rejects unsupported OS, architecture, prefix, and release selections before download'

expect_failure 'SHA-256 verification failed' "${installer[@]}" MOCK_TAMPER=1 bash "$repo_dir/install.sh"
[[ ! -f $test_dir/pkg.log ]] || fail 'Installer invoked pkg for tampered download'
pass 'installer refuses a tampered download before invoking pkg'

cp -f "$test_dir/release/SHA256SUMS" "$test_dir/original-sums"
cat "$test_dir/original-sums" >>"$test_dir/release/SHA256SUMS"
expect_failure 'Missing or ambiguous SHA256SUMS entry' "${installer[@]}" bash "$repo_dir/install.sh"
[[ ! -f $test_dir/pkg.log ]] || fail 'Installer invoked pkg for ambiguous checksum'
cp -f "$test_dir/original-sums" "$test_dir/release/SHA256SUMS"
pass 'installer rejects an ambiguous checksum manifest'

dpkg-deb -R "$deb" "$test_dir/wrong-package"
sed -i 's/^Architecture: aarch64$/Architecture: arm/' "$test_dir/wrong-package/DEBIAN/control"
mkdir -p "$test_dir/wrong-release"
dpkg-deb --root-owner-group -Zxz --build "$test_dir/wrong-package" "$test_dir/wrong-release/herdr_0.9.3-2_aarch64.deb" >/dev/null
(cd "$test_dir/wrong-release" && sha256sum herdr_0.9.3-2_aarch64.deb >SHA256SUMS)
expect_failure 'Unexpected package architecture' "${installer[@]}" "MOCK_RELEASE_DIR=$test_dir/wrong-release" bash "$repo_dir/install.sh"
[[ ! -f $test_dir/pkg.log ]] || fail 'Installer invoked pkg for package with wrong metadata'
pass 'installer checks Debian metadata even after a successful checksum match'

"${installer[@]}" bash "$repo_dir/install.sh" >"$test_dir/install.log"
[[ $(wc -l <"$test_dir/pkg.log") == 1 ]] || fail 'Verified package was not installed exactly once'
grep -Fq 'herdr_0.9.3-2_aarch64.deb' "$test_dir/pkg.log" || fail 'Wrong package passed to pkg'
[[ -z $(ls -A "$test_dir/tmp") ]] || fail 'Installer did not remove temporary downloads'
pass 'installer hands a verified package to pkg and cleans temporary files'

"${package[@]}" --binary "$test_dir/herdr" --version 0.9.4-2 --output-dir "$test_dir/update-release" >"$test_dir/package.log"
"${installer[@]}" MOCK_RELEASE=v0.9.4-termux.2 "MOCK_RELEASE_DIR=$test_dir/update-release" bash "$repo_dir/install.sh" --version v0.9.4-termux.2 >"$test_dir/install.log"
grep -Fq 'herdr_0.9.4-2_aarch64.deb' "$test_dir/pkg.log" || fail 'Update did not select requested package revision'
pass 'explicit update tag selects the matching package version and revision'

rm -f "$test_dir/network.log" "$test_dir/pkg.log"
"${installer[@]}" MOCK_INSTALLED=0.9.3-1 bash "$updater" >"$test_dir/install.log"
[[ $(wc -l <"$test_dir/pkg.log") == 1 ]] || fail 'Packaged updater did not upgrade older installation'
grep -Fq '/releases/latest' "$test_dir/network.log" || fail 'Updater did not discover the latest release'
grep -Fq '/releases/download/v0.9.3-termux.2/herdr_0.9.3-2_aarch64.deb' "$test_dir/network.log" || fail 'Updater did not pin downloads to the resolved release'
pass 'packaged updater discovers latest and upgrades an older installation'

for installed in 0.9.3-2 0.9.3-10 0.10.0-1; do
  rm -f "$test_dir/network.log" "$test_dir/pkg.log"
  "${installer[@]}" "MOCK_INSTALLED=$installed" bash "$updater" >"$test_dir/install.log"
  [[ ! -f $test_dir/pkg.log ]] || fail 'Updater reinstalled or downgraded an equal/newer version'
  [[ $(wc -l <"$test_dir/network.log") == 1 ]] || fail 'No-op updater downloaded package assets'
  grep -Fq 'nothing to update' "$test_dir/install.log" || fail 'No-op update was not explained'
done
pass 'equal/newer installations skip downloads and installation using Debian version ordering'

rm -f "$test_dir/network.log"
"${installer[@]}" MOCK_INSTALLED=0.9.3-2 bash "$updater" --version v0.9.3-termux.2 >"$test_dir/install.log"
[[ ! -f $test_dir/network.log && ! -f $test_dir/pkg.log ]] || fail 'Exact installed version triggered network or installation'
pass 'exact installed version is a no-op without network access'

"${installer[@]}" MOCK_INSTALLED=0.9.3-2 MOCK_INSTALLED_STATUS='deinstall ok config-files' bash "$updater" >"$test_dir/install.log"
[[ $(wc -l <"$test_dir/pkg.log") == 1 ]] || fail 'Removed package was mistaken for an installed version'
pass 'a removed package with remaining configuration is installed again'

rm -f "$test_dir/network.log" "$test_dir/pkg.log"
expect_failure 'Could not check the latest release' "${installer[@]}" MOCK_LATEST_FAIL=1 bash "$updater"
expect_failure 'Unexpected latest release URL' "${installer[@]}" MOCK_LATEST_URL=https://example.com/v0.9.3-termux.2 bash "$updater"
expect_failure 'Expected a release tag' "${installer[@]}" MOCK_LATEST_URL=https://github.com/tensorlabresearch/herdr-termux/releases/tag/preview-test bash "$updater"
[[ ! -f $test_dir/pkg.log ]] || fail 'Failed discovery caused installation'
[[ -z $(ls -A "$test_dir/tmp") ]] || fail 'Updater left temporary files'
pass 'failed discovery and unexpected latest release redirects fail before installation'
printf 'All %s packaging and installer checks passed.\n' "$test_count"
