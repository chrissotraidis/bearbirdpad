#!/usr/bin/env python3
"""Build a private iOS game module with PadMint's portable toolchain."""
import argparse
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from module_build import ROOT, check_patch_tools, configure_cli_streams, generate, generator_environment, normalize_rom, run


def main():
    configure_cli_streams()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rom', type=Path, required=True)
    parser.add_argument('--toolchain', type=Path)
    parser.add_argument('--source-dir', type=Path, default=os.environ.get('BEARBIRDPAD_SOURCE_DIR'), help='Read-only prepared public source cache; exact pins and patches are required')
    parser.add_argument('--llvm', type=Path, default=os.environ.get('PADMINT_LLVM_ROOT'))
    parser.add_argument('--build-dir', type=Path, default=ROOT / 'work/module')
    parser.add_argument('--generate-only', action='store_true')
    parser.add_argument('--jobs', type=int, choices=range(1, 17), default=4)
    args = parser.parse_args()
    if not args.generate_only:
        if not args.toolchain or not args.toolchain.is_file():
            parser.error('--toolchain must name PadMint’s existing iOS module toolchain')
        include = args.toolchain.parent / 'usr/include'
        if not all((include / name).is_file() for name in ('assert.h', 'sys/mman.h')):
            parser.error('This SDK needs the PadMint portable-module header update; update PadMint and recreate its SDK.')
    if not args.llvm or not args.llvm.is_dir():
        parser.error('PadMint must supply PADMINT_LLVM_ROOT, or pass --llvm with its LLVM folder')
    if args.rom.stat().st_size != 16777216:
        parser.error('Supply your complete 16 MiB Banjo-Kazooie US 1.0 ROM.')
    rom = normalize_rom(args.rom.read_bytes())
    check_patch_tools(args.llvm.resolve(), os.environ)
    env = generator_environment()
    spec = importlib.util.spec_from_file_location('bearbird_source_setup', ROOT / 'scripts/setup-source.py')
    setup = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(setup)
    source = setup.select_source(args.source_dir)
    work = args.build_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    generated = generate(source, rom, work, args.llvm.resolve(), args.jobs, env)
    if args.generate_only:
        return
    run('cmake', '--fresh', '-S', ROOT / 'cmake/game-module', '-B', work / 'module', '-G', 'Ninja',
        f'-DCMAKE_TOOLCHAIN_FILE={args.toolchain.resolve()}', '-DCMAKE_BUILD_TYPE=Release',
        f'-DBEARBIRDPAD_GENERATED={generated}', f'-DBEARBIRDPAD_SOURCE={source}',
        f'-DPython3_EXECUTABLE={sys.executable}')
    run('cmake', '--build', work / 'module', '--parallel', args.jobs)
    print(f'Private module: {work / "module/BearBirdPadGame.dylib"}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
