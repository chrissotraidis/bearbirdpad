#!/usr/bin/env python3
"""Build the opt-in empty iOS shell on a Mac; preserve the existing static route."""
import argparse
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from module_build import ROOT, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', type=int, choices=range(1, 17), default=4)
    parser.add_argument('--simulator', action='store_true')
    args = parser.parse_args()
    if sys.platform != 'darwin':
        parser.error('The maintainer shell build requires macOS and Xcode.')
    spec = importlib.util.spec_from_file_location('bearbird_source_setup', ROOT / 'scripts/setup-source.py')
    setup = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(setup)
    setup.prepare()
    env = dict(os.environ, CMAKE_BUILD_PARALLEL_LEVEL=str(args.jobs))
    run(ROOT / 'scripts/build-host-tools.sh', env=env)
    run(ROOT / 'scripts/build-ios.sh', '--simulator' if args.simulator else '--device', '--module-shell', env=env)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
