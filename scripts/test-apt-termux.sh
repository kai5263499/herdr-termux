#!/data/data/com.termux/files/usr/bin/bash
# Run only in the disposable native ARM CI container. /site is read-only.
set -euo pipefail
export TERMUX_PKG_NO_MIRROR_SELECT=true
mode=${1:-candidate}
[[ $mode == candidate || $mode == live ]] || exit 2
[[ $PREFIX == /data/data/com.termux/files/usr && $(dpkg --print-architecture) == aarch64 ]]

if [[ $mode == candidate ]]; then
  install -d -m 755 "$PREFIX/etc/apt/keyrings"
  install -m 644 /site/apt/herdr-termux.gpg "$PREFIX/etc/apt/keyrings/herdr-termux.gpg"
  printf 'deb [arch=aarch64 signed-by=%s] file:/site/apt stable main\n' \
    "$PREFIX/etc/apt/keyrings/herdr-termux.gpg" > "$PREFIX/etc/apt/sources.list.d/herdr-termux.list"
  apt-get -o APT::Update::Error-Mode=any update
else
  pkg install -y curl
  # termux-docker has no Android property service. Only getprop is a fixture;
  # architecture, APT, dpkg, setup, and the application run natively.
  property_fixture=$(mktemp -d)
  trap 'rm -rf -- "$property_fixture"' EXIT
  # shellcheck disable=SC2016 # The generated script must evaluate its own $1.
  printf '#!%s/bin/sh\n[ "$1" = ro.build.version.sdk ] || exit 1\nprintf "24\\n"\n' "$PREFIX" > "$property_fixture/getprop"
  chmod +x "$property_fixture/getprop"
  export PATH="$property_fixture:$PATH"
  curl -fL --retry 3 https://tensorlabresearch.github.io/herdr-termux/setup-repo.sh -o "$property_fixture/setup-repo.sh"
  cmp /site/setup-repo.sh "$property_fixture/setup-repo.sh"
  bash "$property_fixture/setup-repo.sh"
  bash "$property_fixture/setup-repo.sh"
fi

candidate=$(apt-cache policy herdr | sed -n 's/^[[:space:]]*Candidate: //p')
[[ $candidate =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$ ]]
pkg install -y herdr
[[ $(dpkg-query -W -f='${Version}' herdr) == "$candidate" ]]
sh /site/smoke-test.sh "$(command -v herdr)"
printf 'PASS: clean install of %s through signed APT\n' "$candidate"

# Keep the initial published package in the repository as the migration fixture.
pkg uninstall -y herdr
pkg install -y herdr=0.9.3-1
[[ $(dpkg-query -W -f='${Version}' herdr) == 0.9.3-1 ]]
pkg upgrade -y herdr
[[ $(dpkg-query -W -f='${Version}' herdr) == "$candidate" ]]
herdr-update --help
sh /site/smoke-test.sh "$(command -v herdr)"
printf 'PASS: pkg upgrade migrated 0.9.3-1 to %s\n' "$candidate"
