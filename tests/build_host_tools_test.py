"""Run the actual POSIX entrypoint in disposable, source-free fixtures."""

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/build-host-tools.sh"
STOP_AT_BUILD = 73
INVALID_LIMIT = "Host-tool job limit must be a positive integer without leading zeros."
MISSING_SOURCES = "Pinned sources are missing. Run scripts/fetch-sources.sh first."
SOURCE_DIRS = ("lib/N64ModernRuntime/N64Recomp", "lib/rt64")

FAKE_TOOL = r'''import json
import os
from pathlib import Path
import sys

tool = Path(sys.argv[0]).name
with open(os.environ["FIXTURE_CALLS"], "a") as log:
    log.write(json.dumps([tool] + sys.argv[1:]) + "\n")
if tool == "sysctl":
    output = os.environ["FIXTURE_CPU"]
    if output:
        print(output)
    sys.exit(int(os.environ["FIXTURE_SYSCTL_STATUS"]))
if tool == "cmake":
    if sys.argv[1] == "--build":
        sys.exit(73)  # Stop before producing or verifying any real host tools.
    Path(sys.argv[sys.argv.index("-B") + 1]).mkdir()
    sys.exit(0)
sys.exit(99)  # Any other build, download, source, or verification tool is forbidden.
'''


class BuildHostToolsTest(unittest.TestCase):
    def run_fixture(self, limit=None, cpu="8", sysctl_status=0, sources=SOURCE_DIRS):
        with tempfile.TemporaryDirectory(prefix="bearbirdpad-host-tools-test-") as temp:
            temp = Path(temp)
            root = temp / "repo"
            scripts = root / "scripts"
            scripts.mkdir(parents=True)
            entrypoint = scripts / SCRIPT.name
            shutil.copyfile(SCRIPT, entrypoint)
            for source in sources:
                (root / "sources/banjo" / source).mkdir(parents=True)
            fake_bin = temp / "bin"
            fake_bin.mkdir()
            for tool in ("cmake", "sysctl", "file", "curl", "wget", "git", "ninja",
                         "make", "mkdir", "tar", "rsync"):
                fake = fake_bin / tool
                fake.write_text("#!" + sys.executable + "\n" + FAKE_TOOL)
                fake.chmod(0o755)
            calls_path = temp / "calls.jsonl"
            env = {
                "PATH": str(fake_bin) + ":/usr/bin:/bin",
                "LC_ALL": "C",
                "FIXTURE_CALLS": str(calls_path),
                "FIXTURE_CPU": cpu,
                "FIXTURE_SYSCTL_STATUS": str(sysctl_status),
            }
            if limit is not None:
                env["CMAKE_BUILD_PARALLEL_LEVEL"] = limit

            def snapshot():
                return {
                    str(path.relative_to(root)): path.read_bytes() if path.is_file() else None
                    for path in root.rglob("*")
                }

            before = snapshot()
            result = subprocess.run(
                ["/bin/sh", str(entrypoint)], cwd=root, env=env,
                capture_output=True, text=True, timeout=10,
            )
            calls = [json.loads(line) for line in calls_path.read_text().splitlines()] \
                if calls_path.exists() else []
            return result, calls, root, before, snapshot()

    def assert_build(self, fixture, jobs, probe):
        result, calls, root, before, after = fixture
        self.assertEqual(result.returncode, STOP_AT_BUILD, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "")
        expected = [["sysctl", "-n", "hw.logicalcpu"]] if probe else []
        expected += [
            ["cmake", "-S", str(root / "cmake/host-tools"),
             "-B", str(root / "build-host"), "-G", "Ninja",
             "-DCMAKE_BUILD_TYPE=Release",
             "-DBEARBIRDPAD_SOURCE_ROOT=" + str(root / "sources/banjo")],
            ["cmake", "--build", str(root / "build-host"), "--target",
             "N64RecompCLI", "RSPRecomp", "file_to_c", "spirv_cross_msl", "rom_xxh3",
             "--parallel", jobs],
        ]
        self.assertEqual(calls, expected)
        self.assertEqual(after, {**before, "build-host": None})

    def assert_rejected(self, fixture, message, calls=()):
        result, actual_calls, _, before, after = fixture
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, message + "\n")
        self.assertEqual(actual_calls, list(calls))
        self.assertEqual(after, before, "Rejected invocation changed fixture files")

    def test_standard_two_jobs_skips_sysctl(self):
        self.assert_build(self.run_fixture(limit="2", sysctl_status=99), "2", probe=False)

    def test_other_canonical_standard_limits(self):
        for limit in ("1", "12"):
            with self.subTest(limit=limit):
                self.assert_build(self.run_fixture(limit=limit), limit, probe=False)

    def test_unset_and_empty_standard_limit_use_cpu_count(self):
        for limit in (None, ""):
            with self.subTest(limit=limit):
                self.assert_build(self.run_fixture(limit=limit, cpu="6"), "6", probe=True)

    def test_sysctl_failure_retains_four_job_fallback(self):
        for limit in (None, ""):
            with self.subTest(limit=limit):
                self.assert_build(
                    self.run_fixture(limit=limit, cpu="", sysctl_status=1), "4", probe=True,
                )

    def test_invalid_standard_limits_fail_before_any_side_effect(self):
        for limit in ("0", "00", "02", "-2", "+2", "2.0", "1e2", "two",
                      " ", " 2", "2 ", "\t2", "2\n", "2\n3", "2/3", "2;true"):
            with self.subTest(limit=limit):
                self.assert_rejected(self.run_fixture(limit=limit), INVALID_LIMIT)

    def test_invalid_cpu_counts_fail_before_configure(self):
        for cpu in ("", "0", "02", "-2", "two", "2\n3"):
            with self.subTest(cpu=cpu):
                self.assert_rejected(
                    self.run_fixture(cpu=cpu), INVALID_LIMIT,
                    calls=[["sysctl", "-n", "hw.logicalcpu"]],
                )

    def test_invalid_limit_is_rejected_even_without_sources(self):
        self.assert_rejected(self.run_fixture(limit="02", sources=()), INVALID_LIMIT)

    def test_source_guard_still_fails_closed_for_either_missing_directory(self):
        for sources in ((), SOURCE_DIRS[:1], SOURCE_DIRS[1:]):
            with self.subTest(sources=sources):
                self.assert_rejected(
                    self.run_fixture(limit="2", sources=sources), MISSING_SOURCES,
                )


if __name__ == "__main__":
    unittest.main()
