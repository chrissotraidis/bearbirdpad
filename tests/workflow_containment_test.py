"""Keep CI build proof without publishing an IPA while releases are paused."""
from pathlib import Path
import re
import unittest


WORKFLOW = Path(__file__).resolve().parents[1] / ".github/workflows/ios-rom-free.yml"


class WorkflowContainmentTest(unittest.TestCase):
    def test_paused_ci_does_not_upload_an_app(self):
        self.assertIsNone(re.search(
            r"(?m)^\s*(?:-\s*)?uses:\s*actions/upload-artifact@", WORKFLOW.read_text()),
            "The Simulator proof IPA stays in the runner while publication is paused.")

    def test_stub_compile_audit_and_package_checks_remain(self):
        workflow = WORKFLOW.read_text()
        for command in ("scripts/build-host-tools.sh",
                        "scripts/build-ios.sh --simulator --stub --config Release",
                        'scripts/package-audit.sh "$app"',
                        'scripts/package-ios.sh "$app" build/ci/BearBirdPad-CIStub-simulator.ipa'):
            self.assertIn(command, workflow)


if __name__ == "__main__":
    unittest.main()
