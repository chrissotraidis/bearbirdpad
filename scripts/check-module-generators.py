#!/usr/bin/env python3
"""Build the pinned host generators and run a hand-written emitter fixture; no ROM."""
import argparse
import importlib.util
import json
import os
import shutil
import struct
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from module_build import ROOT, build_generators, configure_cli_streams, generator_environment, run


def check_paths(folder, env):
    """Exercise real CLI, TOML and output paths using public instructions only."""
    suffix = ".exe" if os.name == "nt" else ""
    with tempfile.TemporaryDirectory(prefix="BearBirdPad paths \u96ea ") as temporary:
        work = Path(temporary).resolve()
        if os.name == "nt":
            mt = shutil.which("mt", path=env.get("Path", env.get("PATH")))
            if not mt:
                raise RuntimeError("Visual Studio did not provide the manifest inspection tool")
            for name in ("N64Recomp", "RSPRecomp"):
                manifest = work / (name + ".manifest")
                subprocess.run([mt, "-nologo", "-inputresource:" + str(folder / (name + suffix)) + ";#1",
                                "-out:" + str(manifest)], env=env, capture_output=True, check=True)
                tree = ET.parse(manifest)
                codepage = tree.find(".//{http://schemas.microsoft.com/SMI/2019/WindowsSettings}activeCodePage")
                execution = tree.find(".//{urn:schemas-microsoft-com:asm.v3}requestedExecutionLevel")
                if codepage is None or codepage.text != "UTF-8" or execution is None or execution.get("level") != "asInvoker":
                    raise RuntimeError("Host generator lost UTF-8 paths or ordinary execution privileges")
        name = lambda filename: json.dumps(str(work / filename), ensure_ascii=False)
        # addiu v0,zero,7; jr ra; addiu v0,v0,1.
        (work / "cpu \u96ea.bin").write_bytes(bytes(0x1000) + struct.pack(">3I", 0x24020007, 0x03E00008, 0x24420001))
        (work / "symbols \u96ea.toml").write_text('''[[section]]
name = ".text"
rom = 0x1000
vram = 0x80001000
size = 12
functions = [{ name = "recomp_entrypoint", vram = 0x80001000, rom = 0x1000, size = 12 }]
''', encoding="utf-8")
        config = work / "cpu \u96ea.toml"
        config.write_text('[input]\nentrypoint = 0x80001000\nsymbols_file_path = ' + name("symbols \u96ea.toml")
                          + '\nrom_file_path = ' + name("cpu \u96ea.bin")
                          + '\noutput_func_path = ' + name("output \u96ea") + '\n', encoding="utf-8")
        run(folder / ("N64Recomp" + suffix), config, cwd=work, env=env)
        generated = list((work / "output \u96ea").glob("funcs_*.c"))
        if len(generated) != 1 or b"recomp_entrypoint" not in generated[0].read_bytes():
            raise RuntimeError("The public CPU path probe did not produce its function")
        (work / "rsp \u96ea.bin").write_bytes(struct.pack(">I", 13))  # RSP BREAK.
        config = work / "rsp \u96ea.toml"
        config.write_text('text_offset = 0\ntext_size = 4\ntext_address = 0x04001000\nrom_file_path = '
                          + name("rsp \u96ea.bin") + '\noutput_file_path = ' + name("rsp \u96ea.cpp")
                          + '\noutput_function_name = "synthetic_audio"\n', encoding="utf-8")
        run(folder / ("RSPRecomp" + suffix), config, cwd=work, env=env)
        if b"RspExitReason::Broke" not in (work / "rsp \u96ea.cpp").read_bytes():
            raise RuntimeError("The public RSP path probe did not emit BREAK")


def main():
    configure_cli_streams()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', type=int, choices=range(1, 17), default=4)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('bearbird_source_setup', ROOT / 'scripts/setup-source.py')
    setup = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(setup)
    source = setup.prepare(module_only=True)
    # Pass real Unicode TEMP/TMP values through vcvars, not only a dummy probe.
    with tempfile.TemporaryDirectory(prefix='BearBirdPad environment 雪 ') as temporary:
        previous = {name: os.environ.get(name) for name in ('TEMP', 'TMP')}
        try:
            os.environ.update(TEMP=temporary, TMP=temporary)
            env = generator_environment()
        finally:
            for name, value in previous.items():
                if value is None:
                    os.environ.pop(name, None)
                else:
                    os.environ[name] = value
        if any(env.get(name) != temporary for name in previous):
            raise RuntimeError('Visual Studio setup corrupted the Unicode temporary directory')
        work = ROOT / 'work/public-generators 雪'
        work.mkdir(parents=True, exist_ok=True)
        n64, _rsp = build_generators(source, work, args.jobs, env)
        check_paths(n64.parent, env)
    print('Public emitter and Unicode generator paths passed.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
