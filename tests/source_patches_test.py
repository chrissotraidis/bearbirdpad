"""Synthetic regression for overlapping source patches and preserving local edits."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('patches', Path(__file__).resolve().parents[1] / 'scripts/apply-source-patches.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SourcePatchesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / 'source'
        self.repo.mkdir()
        self.git('init', '-q')
        self.git('config', 'core.autocrlf', 'false')
        self.git('config', 'user.name', 'Synthetic test')
        self.git('config', 'user.email', 'test@example.invalid')
        (self.repo / 'file.txt').write_bytes(b'original\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')
        self.stack = []
        for index, (before, after) in enumerate([('original', 'first'), ('first', 'final')]):
            patch = self.root / f'{index}.patch'
            patch.write_text(f'--- a/file.txt\n+++ b/file.txt\n@@ -1 +1 @@\n-{before}\n+{after}\n')
            self.stack.append(f'{self.repo}|{patch}')

    def git(self, *args):
        subprocess.run(['git', '-C', str(self.repo), *args], check=True, capture_output=True)

    def test_fresh_and_repeated_stack(self):
        MODULE.apply(self.repo, self.stack)
        self.assertEqual((self.repo / 'file.txt').read_text(), 'final\n')
        MODULE.apply(self.repo, self.stack)
        self.assertEqual((self.repo / 'file.txt').read_text(), 'final\n')

    def test_crlf_patch_files_match_lf_source_blobs(self):
        for index in range(2):
            patch = self.root / f'{index}.patch'
            patch.write_bytes(patch.read_text().replace('\n', '\r\n').encode())
        MODULE.apply(self.repo, self.stack)
        self.assertEqual((self.repo / 'file.txt').read_bytes(), b'final\n')

    def test_existing_known_crlf_source_can_upgrade(self):
        MODULE.apply(self.repo, self.stack[:1])
        (self.repo / 'file.txt').write_bytes(b'first\r\n')
        MODULE.apply(self.repo, self.stack)
        self.assertEqual((self.repo / 'file.txt').read_bytes(), b'final\n')

    def test_preserves_unexpected_local_edit(self):
        (self.repo / 'file.txt').write_text('my work\n')
        with self.assertRaisesRegex(ValueError, 'Preserving unexpected'):
            MODULE.apply(self.repo, self.stack)
        self.assertEqual((self.repo / 'file.txt').read_text(), 'my work\n')

    def test_upgrade_from_earlier_patch_stack(self):
        MODULE.apply(self.repo, self.stack[:1])
        MODULE.apply(self.repo, self.stack)
        self.assertEqual((self.repo / 'file.txt').read_text(), 'final\n')

    def test_broken_patch_leaves_source_untouched(self):
        (self.root / '1.patch').write_text('invalid patch\n')
        with self.assertRaises(subprocess.CalledProcessError):
            MODULE.apply(self.repo, self.stack)
        self.assertEqual((self.repo / 'file.txt').read_text(), 'original\n')

    def test_verification_does_not_repair_old_sources(self):
        with self.assertRaisesRegex(ValueError, 'not fully applied'):
            MODULE.apply(self.repo, self.stack, verify_only=True)
        self.assertEqual((self.repo / 'file.txt').read_text(), 'original\n')
        MODULE.apply(self.repo, self.stack)
        MODULE.apply(self.repo, self.stack, verify_only=True)


if __name__ == '__main__':
    unittest.main()
