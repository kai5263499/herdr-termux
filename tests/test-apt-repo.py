#!/usr/bin/env python3
"""Exercise real APT authentication/downloads and isolated phone bootstrap failures."""

from contextlib import contextmanager
import getpass
import importlib.util
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load_script(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


fetch = load_script("fetch-apt-packages")
builder = load_script("build-apt-repo")


def run(*args, **kwargs):
    return subprocess.run(args, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, **kwargs)


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


@contextmanager
def serve(directory):
    server = ThreadingHTTPServer(("127.0.0.1", 0),
                                lambda *a, **kw: QuietHandler(*a, directory=str(directory), **kw))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}"
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


class RepositoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="herdr-apt-tests-")
        cls.root = Path(cls.temp.name)
        cls.gnupg = cls.root / "gnupg"
        cls.gnupg.mkdir(mode=0o700)
        cls.env = {**os.environ, "GNUPGHOME": str(cls.gnupg)}
        result = run("gpg", "--batch", "--pinentry-mode", "loopback", "--passphrase", "",
                     "--quick-generate-key", "Herdr test signing key", "rsa2048", "sign", "1d", env=cls.env)
        assert result.returncode == 0, result.stdout
        info = run("gpg", "--batch", "--with-colons", "--list-keys", env=cls.env).stdout
        cls.fingerprint = next(line.split(":")[9] for line in info.splitlines() if line.startswith("fpr:"))
        cls.key = cls.root / "key.gpg"
        cls.key.write_bytes(subprocess.check_output(["gpg", "--batch", "--export", cls.fingerprint], env=cls.env))
        cls.packages = cls.root / "packages"
        cls.packages.mkdir()
        for version in ("0.9.3-2", "0.9.3-10"):
            stage = cls.root / version
            (stage / "DEBIAN").mkdir(parents=True)
            (stage / "DEBIAN/control").write_text(
                f"Package: herdr\nVersion: {version}\nArchitecture: aarch64\n"
                "Maintainer: Test <test@example.invalid>\nDescription: APT fixture\n")
            (stage / "payload").write_text(version)
            result = run("dpkg-deb", "--root-owner-group", "--build", str(stage),
                         str(cls.packages / f"herdr_{version}_aarch64.deb"))
            assert result.returncode == 0, result.stdout
        cls.baseline = cls.root / "baseline"
        result = run("python3", str(ROOT / "scripts/build-apt-repo.py"),
                     "--packages", str(cls.packages), "--output", str(cls.baseline),
                     "--key", cls.fingerprint, "--public-key", str(cls.key), env=cls.env)
        assert result.returncode == 0, result.stdout

    @classmethod
    def tearDownClass(cls):
        run("gpgconf", "--kill", "gpg-agent", env=cls.env)
        cls.temp.cleanup()

    def setUp(self):
        self.temp_case = tempfile.TemporaryDirectory(dir=self.root)
        self.case = Path(self.temp_case.name)
        self.site = self.case / "site"
        shutil.copytree(self.baseline, self.site)
        self.apt_root = self.case / "apt"
        for directory in ("lists/partial", "archives/partial", "downloads"):
            (self.apt_root / directory).mkdir(parents=True)
        (self.apt_root / "status").touch()

    def tearDown(self):
        self.temp_case.cleanup()

    def apt(self, url, *args, tool="apt-get"):
        source = self.apt_root / "source.list"
        source.write_text(f"deb [arch=aarch64 signed-by={self.key}] {url} stable main\n")
        options = [
            f"Dir::Etc::sourcelist={source}", "Dir::Etc::sourceparts=-",
            f"Dir::State::status={self.apt_root / 'status'}",
            f"Dir::State::lists={self.apt_root / 'lists'}",
            f"Dir::Cache::archives={self.apt_root / 'archives'}",
            "Dir::Cache::pkgcache=", "Dir::Cache::srcpkgcache=",
            "APT::Architecture=aarch64", "APT::Architectures::=aarch64",
            f"APT::Sandbox::User={getpass.getuser()}",
            "Debug::NoLocking=1", "APT::Update::Error-Mode=any",
            "Acquire::Languages=none", "Acquire::Retries=0",
        ]
        command = [tool]
        for option in options:
            command += ["-o", option]
        return run(*command, *args, cwd=self.apt_root / "downloads")

    def test_authenticated_download_and_numeric_version_selection(self):
        with serve(self.site) as url:
            result = self.apt(url, "update")
            self.assertEqual(result.returncode, 0, result.stdout)
            policy = self.apt(url, "policy", "herdr", tool="apt-cache")
            self.assertIn("Candidate: 0.9.3-10", policy.stdout)
            download = self.apt(url, "download", "herdr")
            self.assertEqual(download.returncode, 0, download.stdout)
            self.assertEqual((self.apt_root / "downloads/herdr_0.9.3-10_aarch64.deb").read_bytes(),
                             (self.packages / "herdr_0.9.3-10_aarch64.deb").read_bytes())
            (self.apt_root / "status").write_text(
                "Package: herdr\nStatus: install ok installed\nArchitecture: aarch64\n"
                "Version: 0.9.3-2\nDescription: old fixture\n\n")
            upgrade = self.apt(url, "--simulate", "install", "herdr")
            self.assertEqual(upgrade.returncode, 0, upgrade.stdout)
            self.assertIn("Inst herdr [0.9.3-2] (0.9.3-10", upgrade.stdout)

    def test_tampered_signature_is_rejected(self):
        path = self.site / "dists/stable/InRelease"
        path.write_text(path.read_text().replace("Origin: Herdr Termux", "Origin: Malicious"))
        with serve(self.site) as url:
            result = self.apt(url, "update")
            self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_unsigned_repository_is_rejected(self):
        for name in ("InRelease", "Release.gpg"):
            (self.site / "dists/stable" / name).unlink()
        with serve(self.site) as url:
            result = self.apt(url, "update")
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("not signed", result.stdout)

    def test_tampered_index_is_rejected(self):
        for name in ("Packages", "Packages.gz"):
            path = self.site / "dists/stable/main/binary-aarch64" / name
            path.write_bytes(path.read_bytes() + b"tampered")
        with serve(self.site) as url:
            result = self.apt(url, "update")
            self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_tampered_package_is_rejected(self):
        path = self.site / "pool/main/h/herdr/herdr_0.9.3-10_aarch64.deb"
        data = bytearray(path.read_bytes())
        data[-1] ^= 1
        path.write_bytes(data)
        with serve(self.site) as url:
            result = self.apt(url, "update")
            self.assertEqual(result.returncode, 0, result.stdout)
            result = self.apt(url, "download", "herdr")
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("Hash Sum mismatch", result.stdout)

    def test_expired_metadata_is_rejected(self):
        release = self.site / "dists/stable/Release"
        lines = release.read_text().splitlines()
        release.write_text("\n".join(
            "Valid-Until: Wed, 01 Jan 2020 00:00:00 +0000" if line.startswith("Valid-Until:") else line
            for line in lines) + "\n")
        result = run("gpg", "--batch", "--yes", "--local-user", self.fingerprint,
                     "--output", str(release.parent / "InRelease"), "--clearsign", str(release), env=self.env)
        self.assertEqual(result.returncode, 0, result.stdout)
        with serve(self.site) as url:
            result = self.apt(url, "update")
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("expired", result.stdout)

    def test_mismatched_package_metadata_is_rejected(self):
        wrong = self.case / "herdr_0.9.3-9_aarch64.deb"
        shutil.copyfile(self.packages / "herdr_0.9.3-2_aarch64.deb", wrong)
        with self.assertRaisesRegex(ValueError, "Unexpected Version"):
            builder.validate_package(wrong)


class ReleaseTests(unittest.TestCase):
    def test_only_complete_stable_releases_are_accepted(self):
        release = {"tag_name": "v0.9.3-termux.2", "draft": False, "prerelease": False,
                   "assets": [{"name": "herdr_0.9.3-2_aarch64.deb"}, {"name": "SHA256SUMS"}]}
        self.assertEqual(fetch.release_packages([release, {**release, "draft": True},
                                                {**release, "prerelease": True}]),
                         [("v0.9.3-termux.2", "herdr_0.9.3-2_aarch64.deb")])
        with self.assertRaises(ValueError):
            fetch.release_packages([{**release, "assets": []}])
        with self.assertRaises(ValueError):
            fetch.release_packages([release, release])

    def test_bad_and_ambiguous_release_checksums_are_rejected(self):
        digest = "0" * 64
        for manifest in ("", f"{digest}  package.deb", f"{digest}  package.deb\n{digest}  package.deb"):
            with self.assertRaises(ValueError):
                fetch.verify_checksum(manifest, "package.deb", b"package")


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="herdr-bootstrap-")
        self.root = Path(self.temp.name)
        self.prefix = self.root / "prefix"
        (self.prefix / "tmp").mkdir(parents=True)
        self.key = self.prefix / "etc/apt/keyrings/herdr-termux.gpg"
        self.source = self.prefix / "etc/apt/sources.list.d/herdr-termux.list"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        # Only the literal prefix is relocated for host isolation. Production
        # has no prefix override; real Termux integration runs the original file.
        self.script = self.root / "setup.sh"
        self.script.write_text((ROOT / "setup-repo.sh").read_text().replace(
            "termux_prefix=/data/data/com.termux/files/usr", f"termux_prefix={self.prefix}"))
        mocks = {
            "uname": 'case "$1" in -s) echo Linux;; -m) echo "${MOCK_ARCH:-aarch64}";; esac',
            "dpkg": 'echo aarch64',
            "getprop": 'echo "${MOCK_API:-35}"',
            "curl": '''[[ ${MOCK_DOWNLOAD_FAIL:-0} == 0 ]] || exit 22
while (($#)); do
  if [[ $1 == --output ]]; then cp -f "$MOCK_KEY" "$2"; exit; fi
  shift
done
exit 99''',
            "apt-get": 'printf "%s\\n" "$*" >> "$MOCK_APT_LOG"; exit "${MOCK_APT_FAIL:-0}"',
        }
        for name, body in mocks.items():
            path = self.bin / name
            path.write_text(f"#!/usr/bin/env bash\nset -euo pipefail\n{body}\n")
            path.chmod(0o755)
        self.env = {**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}",
                    "PREFIX": str(self.prefix), "TMPDIR": str(self.prefix / "tmp"),
                    "MOCK_KEY": str(ROOT / "apt/herdr-termux.gpg"),
                    "MOCK_APT_LOG": str(self.root / "apt.log")}

    def tearDown(self):
        self.temp.cleanup()

    def setup_repo(self, **env):
        return run("bash", str(self.script), env={**self.env, **env})

    def test_idempotent_setup_uses_scoped_key(self):
        for _ in range(2):
            result = self.setup_repo()
            self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.key.read_bytes(), (ROOT / "apt/herdr-termux.gpg").read_bytes())
        self.assertEqual(len(self.source.read_text().splitlines()), 1)
        self.assertIn(f"signed-by={self.key}", self.source.read_text())
        self.assertNotIn("trusted=yes", self.source.read_text())
        self.assertIn("APT::Update::Error-Mode=any", (self.root / "apt.log").read_text())

    def test_wrong_platform_fails_before_configuration(self):
        for env in ({"MOCK_ARCH": "x86_64"}, {"MOCK_API": "23"}, {"PREFIX": "/usr"}):
            self.assertNotEqual(self.setup_repo(**env).returncode, 0)
        self.assertFalse(self.source.exists())
        self.assertFalse((self.root / "apt.log").exists())

    def test_download_and_key_validation_fail_without_changes(self):
        bad_key = self.root / "bad-key"
        bad_key.write_text("untrusted")
        for env in ({"MOCK_DOWNLOAD_FAIL": "1"}, {"MOCK_KEY": str(bad_key)}):
            self.assertNotEqual(self.setup_repo(**env).returncode, 0)
        self.assertFalse(self.source.exists())
        self.assertFalse(self.key.exists())
        self.assertFalse((self.root / "apt.log").exists())

    def test_failed_refresh_rolls_back_new_configuration(self):
        result = self.setup_repo(MOCK_APT_FAIL="100")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.key.exists())
        self.assertFalse(self.source.exists())
        self.assertEqual(list((self.prefix / "tmp").iterdir()), [])

    def test_failed_refresh_restores_existing_configuration(self):
        self.key.parent.mkdir(parents=True)
        self.source.parent.mkdir(parents=True)
        self.key.write_bytes(b"previous-key")
        self.source.write_text("previous-source\n")
        result = self.setup_repo(MOCK_APT_FAIL="100")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.key.read_bytes(), b"previous-key")
        self.assertEqual(self.source.read_text(), "previous-source\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
