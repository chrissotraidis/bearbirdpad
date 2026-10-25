#!/usr/bin/env python3
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from module_build import check_generated
try:
    import importlib.util
    spec = importlib.util.spec_from_file_location('bearbird_source_setup', Path(__file__).with_name('setup-source.py'))
    setup = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(setup)
    setup.verify(module_only=True, source=Path(sys.argv[2]) if len(sys.argv) > 2 else None)
    check_generated(Path(sys.argv[1]))
except (OSError, ValueError) as error:
    sys.exit(str(error))
