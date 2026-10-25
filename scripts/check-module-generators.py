#!/usr/bin/env python3
"""Build the pinned host generators and run a hand-written emitter fixture; no ROM."""
import argparse
import importlib.util
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from module_build import ROOT, build_generators, generator_environment


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', type=int, choices=range(1, 17), default=4)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('bearbird_source_setup', ROOT / 'scripts/setup-source.py')
    setup = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(setup)
    env = generator_environment()
    source = setup.prepare(module_only=True)
    work = ROOT / 'work/public-generators'
    work.mkdir(parents=True, exist_ok=True)
    build_generators(source, work, args.jobs, env)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
