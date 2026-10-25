#!/usr/bin/env python3
"""Replay the complete patch stack privately, then update only known source bytes.

Later patches change earlier patch context, so checking each patch in reverse
against the final working tree cannot reliably detect an already-patched tree.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def apply(checkout, stack, verify_only=False):
    checkout = checkout.resolve()
    patches = [(Path(folder).resolve(), Path(patch).resolve()) for folder, patch in
               (item.split('|', 1) for item in stack)]
    originals = {}
    for folder, patch in patches:
        for name in re.findall(r'^(?:--- a/|\+\+\+ b/)([^\t\n]+)', patch.read_text(), re.M):
            path = folder / name
            relative = path.relative_to(checkout)
            if relative in originals:
                continue
            # Resolve files inside nested submodules against their own pinned HEAD.
            parent = path.parent
            while not parent.exists():
                parent = parent.parent
            repo = Path(subprocess.check_output(['git', '-C', str(parent),
                                                 'rev-parse', '--show-toplevel'], text=True).strip())
            result = subprocess.run(['git', '-C', str(repo), 'show',
                                     'HEAD:' + path.relative_to(repo).as_posix()], capture_output=True)
            originals[relative] = result.stdout if result.returncode == 0 else None
    with tempfile.TemporaryDirectory(prefix='bearbirdpad-patches-') as temporary:
        staged = Path(temporary)
        for relative, content in originals.items():
            path = staged / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            if content is not None:
                path.write_bytes(content)
        known = {relative: {content} for relative, content in originals.items()}
        for folder, patch in patches:
            destination = staged / folder.relative_to(checkout)
            destination.mkdir(parents=True, exist_ok=True)
            # Git blobs are LF even when the recipe checkout converts patches to CRLF.
            patch_bytes = patch.read_bytes().replace(b'\r\n', b'\n')
            subprocess.run(['git', '-c', 'core.autocrlf=false', 'apply', '-'],
                           input=patch_bytes, cwd=destination, check=True)
            # An existing checkout may have an earlier complete prefix of the
            # stack. Accept only bytes reproduced from pinned HEAD and patches.
            for relative in originals:
                path = staged / relative
                known[relative].add(path.read_bytes() if path.exists() else None)
        updates = []
        for relative, original in originals.items():
            actual = checkout / relative
            expected_path = staged / relative
            expected = expected_path.read_bytes() if expected_path.exists() else None
            current = actual.read_bytes() if actual.exists() else None
            # Older Windows runs may have emitted CRLF under global Git settings.
            # Accept only the same known text, never unrelated source edits.
            normalized = None if current is None else current.replace(b'\r\n', b'\n')
            known_text = {None if data is None else data.replace(b'\r\n', b'\n') for data in known[relative]}
            if actual.is_symlink() or normalized not in known_text:
                raise ValueError(f'Preserving unexpected local source changes: {relative}')
            if current != expected:
                updates.append((actual, expected))
        if verify_only and updates:
            raise ValueError('Pinned source patches are not fully applied; run setup-source.py again.')
        # Validate the entire stack before changing any real source file.
        for path, content in updates:
            if content is None:
                path.unlink()
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
        print(f'Patch stack verified; {len(updates)} source files updated.')


if __name__ == '__main__':
    try:
        apply(Path(sys.argv[1]).resolve(), sys.argv[2:])
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
