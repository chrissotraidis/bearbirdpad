#!/usr/bin/env python3
"""Prepare exact public source pins without replacing unrelated local changes."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PATCH_TREES = {
    'banjo': '', 'nmr': 'lib/N64ModernRuntime',
    'sljit': 'lib/N64ModernRuntime/N64Recomp/lib/sljit',
    'rt64': 'lib/rt64', 'hlslpp': 'lib/rt64/src/contrib/hlslpp',
    'plume': 'lib/rt64/src/contrib/plume',
    'nfd': 'lib/rt64/src/contrib/nativefiledialog-extended',
    'frontend': 'lib/RecompFrontend',
}
MODULES = ('BanjoRecompSyms', 'lib/N64ModernRuntime', 'lib/bk-decomp', 'lib/rt64')


def patch_stack(source, module_only):
    stack = []
    for label, relative in PATCH_TREES.items():
        if module_only and label not in ('banjo', 'nmr', 'sljit', 'rt64'):
            continue
        stack.extend(f'{source / relative}|{patch}' for patch in sorted((ROOT / 'patches' / label).glob('*.patch')))
    return stack


def verify_tracked_sources(source, pins, stack, module_only):
    allowed = {}
    for item in stack:
        folder, patch = item.split('|', 1)
        names = re.findall(r'^(?:--- a/|\+\+\+ b/)([^\t\n]+)', Path(patch).read_text(), re.M)
        allowed.setdefault(Path(folder), set()).update(names)
    repositories = {'': pins['upstream']['commit'], **pins['gitlinks']}
    for name, pin in repositories.items():
        if name and module_only and not (name in MODULES or name.startswith('lib/N64ModernRuntime/')):
            continue
        path = source / name
        if revision(path) != pin:
            raise ValueError(f'Preserving dependency with a different revision: {name}')
        dirty = subprocess.check_output(['git', '-C', str(path), 'diff', 'HEAD', '--name-only',
                                         '--ignore-submodules=all'], text=True,
                                        env=dict(os.environ, GIT_OPTIONAL_LOCKS='0')).splitlines()
        unknown = set(dirty) - allowed.get(path, set())
        # Git may report checkout line-ending conversion as dirty on Windows
        # (and one pinned dependency itself stores CRLF). Do not rewrite it.
        for name in tuple(unknown):
            file = path / name
            original = subprocess.check_output(['git', '-C', str(path), 'show', f'HEAD:{name}'])
            if (file.is_file() and not file.is_symlink()
                    and file.read_bytes().replace(b'\r\n', b'\n') == original.replace(b'\r\n', b'\n')):
                unknown.remove(name)
        if unknown:
            raise ValueError(f'Preserving unexpected tracked source changes in {path}: {sorted(unknown)}')


def replay_module():
    spec = importlib.util.spec_from_file_location('bearbird_patch_replay', ROOT / 'scripts/apply-source-patches.py')
    replay = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(replay)
    return replay


def verify(module_only=False, source=None):
    source = (Path(source) if source is not None else ROOT / 'sources/banjo').resolve()
    pins = json.loads((ROOT / 'sources.lock.json').read_text())
    stack = patch_stack(source, module_only)
    verify_tracked_sources(source, pins, stack, module_only)
    replay_module().apply(source, stack, verify_only=True)
    return source


def select_source(source=None):
    # An explicit cache is read-only: do not initialize Git metadata, fetch,
    # replay patches, or normalize any bytes in that directory.
    return verify(module_only=True, source=source) if source is not None else prepare(module_only=True)


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def revision(path):
    return subprocess.check_output(['git', '-C', str(path), 'rev-parse', 'HEAD'], text=True).strip()


def prepare(module_only=False):
    pins = json.loads((ROOT / 'sources.lock.json').read_text())
    source = ROOT / 'sources/banjo'
    if not (source / '.git').exists():
        if source.exists() and any(source.iterdir()):
            raise ValueError(f'Preserving non-Git source folder: {source}')
        source.parent.mkdir(parents=True, exist_ok=True)
        run('git', 'clone', '--no-checkout', '-c', 'core.autocrlf=false', pins['upstream']['url'], source)
        run('git', '-C', source, 'checkout', '--detach', pins['upstream']['commit'])
    if revision(source) != pins['upstream']['commit']:
        raise ValueError(f'Preserving source with a different revision: {source}')
    # Verify existing initialized dependencies before Git can change any of them.
    for name, pin in pins['gitlinks'].items():
        path = source / name
        if (path / '.git').exists() and revision(path) != pin:
            raise ValueError(f'Preserving dependency with a different revision: {name}')
    if module_only:
        run('git', '-C', source, '-c', 'core.autocrlf=false', 'submodule', 'update', '--init', '--', *MODULES)
        run('git', '-C', source, '-c', 'core.autocrlf=false', 'submodule', 'update', '--init', '--recursive', '--', 'lib/N64ModernRuntime')
    else:
        run('git', '-C', source, '-c', 'core.autocrlf=false', 'submodule', 'update', '--init', '--recursive')
    for name, pin in pins['gitlinks'].items():
        if module_only and not (name in MODULES or name.startswith('lib/N64ModernRuntime/')):
            continue
        if revision(source / name) != pin:
            raise ValueError(f'Dependency does not match its reviewed pin: {name}')
    stack = patch_stack(source, module_only)
    verify_tracked_sources(source, pins, stack, module_only)
    replay_module().apply(source, stack)
    return source


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--module-only', action='store_true')
    args = parser.parse_args()
    try:
        print(prepare(args.module_only))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
