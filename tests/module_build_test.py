"""Portable build checks use only hand-written synthetic data."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import module_build as module
spec = importlib.util.spec_from_file_location('source_setup', ROOT / 'scripts/setup-source.py')
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


def block(data, size=None):
    stream = zlib.compressobj(wbits=-15)
    return b'\x11\x72' + (len(data) if size is None else size).to_bytes(4, 'big') + stream.compress(data) + stream.flush()


class DecoderTests(unittest.TestCase):
    def test_block_with_padding(self):
        for padding in (b'', b'\x00' * 15):
            self.assertEqual(module.decompress_bk_block(block(b'example') + padding), b'example')

    def test_bad_headers_and_lengths(self):
        for data in (b'', b'\x11\x72\x00', b'bad123', block(b'a', 0), block(b'a', 16777217),
                     block(b'example', 6), block(b'example', 8), block(b'example')[:-1]):
            with self.subTest(data=data), self.assertRaises((ValueError, zlib.error)):
                module.decompress_bk_block(data)

    def test_expansion_is_bounded(self):
        with self.assertRaises(ValueError):
            module.decompress_bk_block(block(b'a' * 100000, 4))

    def test_normalize_orders_and_original_unchanged(self):
        canonical = b'\x80\x37\x12\x40example!'
        lock = json.dumps({'rom': {'size': len(canonical), 'md5': hashlib.md5(canonical).hexdigest()}})
        with mock.patch.object(Path, 'read_text', return_value=lock):
            for size in (1, 2, 4):
                data = b''.join(canonical[n:n + size][::-1] for n in range(0, len(canonical), size))
                original = bytes(data)
                self.assertEqual(module.normalize_rom(data), canonical)
                self.assertEqual(data, original)
            with self.assertRaises(ValueError):
                module.normalize_rom(canonical[:-1])
            with self.assertRaises(ValueError):
                module.normalize_rom(canonical[:-1] + b'?')


class GeneratedTests(unittest.TestCase):
    def test_ledger_catches_changed_deleted_added_and_stale(self):
        with tempfile.TemporaryDirectory() as temporary, mock.patch.object(module, 'identity', return_value='contract'):
            folder = Path(temporary)
            files = ['RecompiledFuncs/lookup.cpp', 'RecompiledFuncs/recomp_overlays.inl',
                     'RecompiledFuncs/code.c', 'rsp/n_aspMain.cpp', 'RecompiledPatches/patches.c',
                     'RecompiledPatches/patches_bin.c']
            for name in files:
                file = folder / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_bytes(b'/* synthetic */\n')
            def stamp():
                (folder / 'module-inputs.json').write_text(json.dumps({'contract': 'contract', 'outputs': module.output_hashes(folder)}))
            stamp()
            module.check_generated(folder)
            (folder / files[0]).write_bytes(b'changed')
            with self.assertRaises(ValueError): module.check_generated(folder)
            stamp()
            (folder / files[0]).unlink()
            with self.assertRaises(ValueError): module.check_generated(folder)
            stamp()
            with self.assertRaises(ValueError): module.check_generated(folder)
            (folder / files[0]).write_bytes(b'/* synthetic */\n')
            stamp()
            (folder / 'unexpected.c').write_bytes(b'new')
            with self.assertRaises(ValueError): module.check_generated(folder)
            stamp()
            with mock.patch.object(module, 'identity', return_value='new-contract'), self.assertRaises(ValueError):
                module.check_generated(folder)

    def test_make_flags_rejects_unreviewed_variable(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'Makefile'
            path.write_text('GBI_DEFINE := -DF3DEX_GBI\nCPPFLAGS := -nostdinc $(GBI_DEFINE)\n')
            self.assertEqual(module.make_flags(path, 'CPPFLAGS'), ['-nostdinc', '-DF3DEX_GBI'])
            path.write_text('CPPFLAGS := $(UNREVIEWED)\n')
            with self.assertRaises(ValueError): module.make_flags(path, 'CPPFLAGS')

    def test_embedded_patch_has_exact_bytes_and_size(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            module.embed_patch(bytes([0, 127, 128, 255]), folder)
            self.assertIn('{0,127,-128,-1}', (folder / 'patches_bin.c').read_text())
            self.assertIn('sizeof(bk_patches_bin)', (folder / 'patches_bin.c').read_text())
            self.assertIn('extern const size_t bk_patches_bin_size', (folder / 'patches_bin.h').read_text())


class SourceTests(unittest.TestCase):
    def test_unrelated_dirty_source_is_preserved_and_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            subprocess.run(['git', 'init', '-q', str(folder)], check=True)
            (folder / 'input.cpp').write_bytes(b'one\r\ntwo\r\n')
            subprocess.run(['git', '-C', str(folder), '-c', 'core.autocrlf=false', 'add', '.'], check=True)
            subprocess.run(['git', '-C', str(folder), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                            'commit', '-qm', 'synthetic input'], check=True)
            pins = {'upstream': {'commit': setup.revision(folder)}, 'gitlinks': {}}
            (folder / 'input.cpp').write_bytes(b'one\ntwo\n')
            setup.verify_tracked_sources(folder, pins, [], True)
            (folder / 'input.cpp').write_bytes(b'user edit\n')
            with self.assertRaises(ValueError): setup.verify_tracked_sources(folder, pins, [], True)
            self.assertEqual((folder / 'input.cpp').read_bytes(), b'user edit\n')

    def test_selected_staging_keeps_verified_patch_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary) / 'source'
            folder.mkdir()
            subprocess.run(['git', 'init', '-q', str(folder)], check=True)
            (folder / 'header.h').write_bytes(b'original\n')
            subprocess.run(['git', '-C', str(folder), 'add', '.'], check=True)
            subprocess.run(['git', '-C', str(folder), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                            'commit', '-qm', 'synthetic input'], check=True)
            # setup-source verifies this reviewed patch before export_files is called.
            (folder / 'header.h').write_bytes(b'reviewed patched header\n')
            (folder / 'untracked.h').write_bytes(b'not an input\n')
            destination = Path(temporary) / 'stage'
            module.export_files(folder, destination, ['.'])
            self.assertEqual((destination / 'header.h').read_bytes(), b'reviewed patched header\n')
            self.assertFalse((destination / 'untracked.h').exists())

    def test_explicit_source_cache_never_prepares_or_repairs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, recipe = root / 'cache', root / 'recipe'
            source.mkdir(); recipe.mkdir()
            subprocess.run(['git', 'init', '-q', str(source)], check=True)
            (source / 'input.cpp').write_bytes(b'original\n')
            subprocess.run(['git', '-C', str(source), '-c', 'core.autocrlf=false', 'add', '.'], check=True)
            subprocess.run(['git', '-C', str(source), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                            'commit', '-qm', 'synthetic input'], check=True)
            pins = {'upstream': {'commit': setup.revision(source)}, 'gitlinks': {}}
            (recipe / 'sources.lock.json').write_text(json.dumps(pins))
            replay = setup.replay_module()
            def snapshot():
                return {str(p.relative_to(source)): p.read_bytes() for p in source.rglob('*') if p.is_file()}
            with mock.patch.object(setup, 'ROOT', recipe), mock.patch.object(setup, 'replay_module', return_value=replay), \
                    mock.patch.object(setup, 'prepare', side_effect=AssertionError('explicit cache must not prepare')):
                before = snapshot()
                self.assertEqual(setup.select_source(source), source.resolve())
                self.assertEqual(snapshot(), before)
                patch = recipe / 'patches/banjo/001.patch'
                patch.parent.mkdir(parents=True)
                patch.write_bytes(b'--- a/input.cpp\n+++ b/input.cpp\n@@ -1 +1 @@\n-original\n+patched\n')
                with self.assertRaisesRegex(ValueError, 'not fully applied'):
                    setup.select_source(source)
                self.assertEqual(snapshot(), before)
                (source / 'input.cpp').write_bytes(b'user edit\n')
                before = snapshot()
                with self.assertRaisesRegex(ValueError, 'Preserving unexpected'):
                    setup.select_source(source)
                self.assertEqual(snapshot(), before)
                pins['upstream']['commit'] = '0' * 40
                (recipe / 'sources.lock.json').write_text(json.dumps(pins))
                with self.assertRaisesRegex(ValueError, 'different revision'):
                    setup.select_source(source)
                self.assertEqual(snapshot(), before)



class WindowsCompilerTests(unittest.TestCase):
    def check_selection(self, host, arm_available, expected_arch):
        import types
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'Visual Studio 雪'
            installer = root / 'Microsoft Visual Studio/Installer/vswhere.exe'
            installer.parent.mkdir(parents=True); installer.touch()
            old, new = root / 'older-x64', root / 'newer-arm'
            for installation, arch in ((old, 'x64'), (new, 'arm64')):
                compiler = installation / f'VC/Tools/MSVC/14.44/bin/Host{arch}/{arch}/cl.exe'
                compiler.parent.mkdir(parents=True); compiler.touch()
            selected = new if expected_arch == 'arm64' else old
            calls = []
            def query(command, **kwargs):
                calls.append(command)
                self.assertIn("-utf8", command)
                self.assertEqual(kwargs.get("encoding"), "utf-8")
                return str(new if '-requiresAny' in command and arm_available else old)
            process = types.SimpleNamespace(stdout='PATH=prepared-compiler\nTEMP=C:/TEMP 雪\n')
            with mock.patch.object(module, 'os', types.SimpleNamespace(name='nt', environ={'ProgramFiles(x86)': str(root), 'TEMP': 'C:/TEMP 雪'})), \
                    mock.patch.object(module.platform, 'machine', return_value=host), \
                    mock.patch.object(module.shutil, 'which', side_effect=[None, 'cl.exe']), \
                    mock.patch.object(module.subprocess, 'check_output', side_effect=query), \
                    mock.patch.object(module.subprocess, 'run', return_value=process) as run:
                env = module.generator_environment()
            self.assertEqual(env['TEMP'], 'C:/TEMP 雪')
            self.assertIn(' /u ', run.call_args.args[0])
            self.assertEqual(run.call_args.kwargs['encoding'], 'utf-16le')
            self.assertEqual('-requiresAny' in calls[0], host == 'ARM64')
            self.assertIn(str(selected / 'VC/Auxiliary/Build/vcvarsall.bat'), run.call_args.args[0])
            self.assertIn(' ' + expected_arch + ' >nul', run.call_args.args[0])

    def test_newer_arm_only_install_does_not_hide_x64_compiler(self):
        self.check_selection('AMD64', True, 'x64')

    def test_arm_host_keeps_native_compiler_preference(self):
        self.check_selection('ARM64', True, 'arm64')

    def test_arm_host_keeps_x64_fallback(self):
        self.check_selection('ARM64', False, 'x64')


class UnicodeTests(unittest.TestCase):
    def test_windows_cli_status_and_error_streams(self):
        import types
        output, errors = io.BytesIO(), io.BytesIO()
        stdout = io.TextIOWrapper(output, encoding='cp1252')
        stderr = io.TextIOWrapper(errors, encoding='cp1252')
        with mock.patch.object(module, 'os', types.SimpleNamespace(name='nt')), \
                mock.patch.object(module.sys, 'stdout', stdout), \
                mock.patch.object(module.sys, 'stderr', stderr):
            module.configure_cli_streams()
            print('Private module: C:/Build 雪/Game.dylib')
            print('Preserving C:/Build 雪', file=sys.stderr)
        stdout.flush(); stderr.flush()
        self.assertEqual(output.getvalue().replace(b'\r\n', b'\n'), 'Private module: C:/Build 雪/Game.dylib\n'.encode('utf-8'))
        self.assertEqual(errors.getvalue().replace(b'\r\n', b'\n'), 'Preserving C:/Build 雪\n'.encode('utf-8'))

    def test_manifest_changes_source_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'sources.lock.json').write_bytes(b'{}')
            (root / 'scripts').mkdir()
            for name in ('module_build.py', 'module-identity.py', 'build-game-module.py', 'setup-source.py', 'apply-source-patches.py'):
                (root / 'scripts' / name).write_bytes(b'')
            path = root / 'cmake/module-host-tools/windows-utf8.manifest'
            path.parent.mkdir(parents=True)
            path.write_bytes(b'UTF-8')
            with mock.patch.object(module, 'ROOT', root):
                before = module.identity()
                path.write_bytes(b'changed')
                self.assertNotEqual(module.identity(), before)

if __name__ == '__main__':
    unittest.main()
