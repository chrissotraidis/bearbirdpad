"""Portable private generation for the pinned BearBirdPad runtime."""
import concurrent.futures
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import uuid
import zlib

ROOT = Path(__file__).resolve().parents[1]


def identity():
    paths = [ROOT / 'sources.lock.json']
    for folder, extensions in (('ios', ('.h', '.hpp', '.cpp', '.mm')),
                               ('patches', ('.patch',)), ('cmake', ('.cmake', '.txt', '.manifest'))):
        paths.extend(path for path in (ROOT / folder).rglob('*') if path.suffix in extensions)
    paths.extend(ROOT / 'scripts' / name for name in (
        'module_build.py', 'module-identity.py', 'build-game-module.py',
        'setup-source.py', 'apply-source-patches.py'))
    digest = hashlib.sha256()
    for path in sorted(paths, key=lambda p: p.relative_to(ROOT).as_posix()):
        digest.update(path.relative_to(ROOT).as_posix().encode() + b'\0')
        digest.update(path.read_bytes().replace(b'\r\n', b'\n') + b'\0')
    return digest.hexdigest()


def normalize_rom(data):
    expected = json.loads((ROOT / 'sources.lock.json').read_text())['rom']
    if len(data) != expected['size']:
        raise ValueError('Supply your complete 16 MiB Banjo-Kazooie US 1.0 ROM.')
    if data[:4] == b'\x37\x80\x40\x12':
        swapped = bytearray(len(data))
        swapped[0::2], swapped[1::2] = data[1::2], data[0::2]
        data = bytes(swapped)
    elif data[:4] == b'\x40\x12\x37\x80':
        swapped = bytearray(len(data))
        for index in range(4):
            swapped[index::4] = data[3 - index::4]
        data = bytes(swapped)
    if data[:4] != b'\x80\x37\x12\x40' or hashlib.md5(data).hexdigest() != expected['md5']:
        raise ValueError('The ROM is not the supported US 1.0 revision; your original was not changed.')
    return data


def decompress_bk_block(data):
    """Pinned bk_rom_decompress format: magic, big-endian size, raw DEFLATE."""
    if len(data) < 6 or data[:2] != b'\x11\x72':
        raise ValueError('Invalid BK compressed block header')
    size = int.from_bytes(data[2:6], 'big')
    if not 0 < size <= 16 * 1024 * 1024:
        raise ValueError('Invalid BK decompressed block size')
    decoder = zlib.decompressobj(-zlib.MAX_WBITS)
    out = decoder.decompress(data[6:], size + 1)
    if len(out) != size or not decoder.eof or decoder.unconsumed_tail:
        raise ValueError('Incomplete or oversized BK compressed block')
    return out


def decompress_rom(data):
    # The reviewed upstream Rust decompressor supplies these US 1.0 ranges.
    # Keep its ordering and exact output identity; no Rust toolchain is needed.
    overlays = ((0xF19250, 0x1D09B), (0xF37F90, 0x64B50), (0xFA3FD0, 0x1DC6),
                (0xFA5F50, 0x2D96), (0xFA9150, 0x512E), (0xFAE860, 0x328B),
                (0xFB24A0, 0x1E39), (0xFB44E0, 0x5130), (0xFB9A30, 0x4BB2),
                (0xFBEBE0, 0x540F), (0xFC4810, 0x23FF), (0xFC6F20, 0x1BDC),
                (0xFC9150, 0x6548), (0xFD0420, 0x5640), (0xFD6190, 0x416F),
                (0xFDAA10, 0xE))
    offsets = [value for start, delta in overlays for value in (start, start + delta)] + [0xFDAA30]
    blocks = [decompress_bk_block(data[start:end]) for start, end in zip(offsets, offsets[1:])]
    blocks[6], blocks[8] = blocks[8], blocks[6]
    blocks[7], blocks[9] = blocks[9], blocks[7]
    output = data[:offsets[0]] + b''.join(blocks)
    expected = json.loads((ROOT / 'sources.lock.json').read_text())['rom']['decompressed_sha1']
    if hashlib.sha1(output).hexdigest() != expected:
        raise ValueError('ROM decompression did not produce the pinned build input')
    return output


def run(*args, cwd=ROOT, env=None):
    subprocess.run([str(arg) for arg in args], cwd=cwd, env=env, check=True)

def configure_cli_streams():
    if os.name == "nt":
        for stream in (sys.stdout, sys.stderr):
            stream.reconfigure(encoding="utf-8")


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def generator_environment():
    env = dict(os.environ)
    if os.name != "nt" or shutil.which("cl", path=env.get("PATH")):
        return env
    installer = Path(env.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "Microsoft Visual Studio/Installer/vswhere.exe"
    if not installer.is_file():
        raise ValueError("Install Visual Studio Build Tools with Desktop development with C++ and a Windows SDK, then try again.")
    native_arm64 = platform.machine().lower() in ("arm64", "aarch64")
    requirements = ["-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64"]
    if native_arm64:
        requirements = ["-requiresAny", *requirements, "Microsoft.VisualStudio.Component.VC.Tools.ARM64"]
    installation = subprocess.check_output([str(installer), "-latest", "-products", "*", *requirements,
                                            "-property", "installationPath", "-utf8"], text=True, encoding="utf-8").strip()
    versions = sorted((Path(installation) / "VC/Tools/MSVC").glob("*"), reverse=True)
    arm = native_arm64 and any(
        (version / "bin/Hostarm64/arm64/cl.exe").is_file() for version in versions)
    arch = "arm64" if arm else "x64"
    if not any((version / f"bin/Host{arch}/{arch}/cl.exe").is_file() for version in versions):
        raise ValueError(f"Visual Studio is missing its {arch} C++ compiler; add Desktop development with C++ and a Windows SDK.")
    script = Path(installation) / "VC/Auxiliary/Build/vcvarsall.bat"
    command = subprocess.list2cmdline([env.get("COMSPEC", "cmd.exe")]) + f' /u /d /s /c ""{script}" {arch} >nul && set"'
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-16le", check=True, env=env)
    for line in result.stdout.splitlines():
        key, separator, value = line.partition("=")
        if separator and key:
            existing = next((name for name in env if name.casefold() == key.casefold()), key)
            env[existing] = value
    if not shutil.which("cl", path=env.get("Path", env.get("PATH"))):
        raise ValueError("Visual Studio could not prepare its C++ compiler. Check the Windows SDK components.")
    return env

def patch_tools(llvm, env):
    suffix = ".exe" if os.name == "nt" else ""
    compiler = Path(env.get("PADMINT_MIPS_CC", str(llvm / ("bin/clang" + suffix))))
    linker = llvm / ("bin/ld.lld" + suffix)
    for tool in (compiler, linker):
        if not tool.is_file():
            raise ValueError(f"PadMint's patch tool is missing: {tool}")
    return compiler, linker

def check_patch_tools(llvm, env):
    """Check real MIPS2/o32 code generation before fetching or translating inputs."""
    compiler, linker = patch_tools(llvm, env)
    targets = subprocess.check_output([str(compiler), "--print-targets"], text=True, env=env)
    if not re.search(r"^\s*mips\s+-", targets, re.M):
        raise ValueError("This LLVM compiler has no MIPS backend. BearBirdPad needs PadMint's mips-clang tool "
                         "(PADMINT_MIPS_CC); its normal iOS compiler can remain unchanged.")
    with tempfile.TemporaryDirectory(prefix="BearBirdPad MIPS probe ") as temporary:
        folder = Path(temporary)
        source, obj, linked = folder / "probe.c", folder / "probe.o", folder / "linked.o"
        source.write_text("int bearbirdpad_probe(int value) { return value * 3 + 7; }\n")
        run(compiler, "-target", "mips", "-mips2", "-mabi=32", "-mno-abicalls", "-G0",
            "-mno-odd-spreg", "-mno-check-zero-division", "-c", source, "-o", obj, env=env)
        run(linker, "-m", "elf32btsmip", "-r", obj, "-o", linked, env=env)
        header = linked.read_bytes()[:52]
        if (len(header) != 52 or header[:6] != b"\x7fELF\x01\x02" or header[18:20] != b"\0\x08"
                or int.from_bytes(header[36:40], "big") & 0xF000F000 != 0x10001000):
            raise ValueError("Patch tools did not produce the required big-endian MIPS2/o32 ELF")

def export_files(source, destination, paths):
    """Select tracked files, then copy the already-verified patched source bytes."""
    archive = subprocess.check_output(["git", "-C", str(source), "archive", "HEAD", "--", *paths])
    with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
        for member in bundle:
            relative = Path(member.name)
            if relative.is_absolute() or ".." in relative.parts or not (member.isfile() or member.isdir()):
                raise ValueError(f"Unsupported source archive entry: {member.name}")
            path = destination / relative
            if member.isdir():
                path.mkdir(parents=True, exist_ok=True)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                current = source / relative
                if current.is_symlink() or not current.is_file():
                    raise ValueError(f'Verified source input is missing or a symlink: {current}')
                path.write_bytes(current.read_bytes())

def output_hashes(folder):
    return {path.relative_to(folder).as_posix(): sha256(path)
            for path in sorted(folder.rglob("*")) if path.is_file() and path.name != "module-inputs.json"}


def make_flags(makefile, name):
    text = makefile.read_text().replace('\\\n', ' ')
    variables = dict(re.findall(r'^(\w+)\s*:=\s*(.*)$', text, re.M))
    value = variables[name]
    value = value.replace('$(GBI_DEFINE)', variables.get('GBI_DEFINE', ''))
    if '$' in value:
        raise ValueError(f'Review the changed pinned patch Makefile variable: {name}')
    return shlex.split(value)


def embed_patch(data, folder):
    folder.mkdir(parents=True, exist_ok=True)
    values = ','.join(str(byte if byte < 128 else byte - 256) for byte in data)
    source = ('#include <stddef.h>\n'
              f'extern const char bk_patches_bin[{len(data)}];\n'
              f'const char bk_patches_bin[{len(data)}] = {{{values}}};\n'
              'extern const size_t bk_patches_bin_size;\n'
              'const size_t bk_patches_bin_size = sizeof(bk_patches_bin);\n')
    (folder / 'patches_bin.c').write_bytes(source.encode('ascii'))
    (folder / 'patches_bin.h').write_bytes(
        ('#include <stddef.h>\n#ifdef __cplusplus\nextern "C" {\n#endif\n'
         f'extern const char bk_patches_bin[{len(data)}];\n'
         'extern const size_t bk_patches_bin_size;\n#ifdef __cplusplus\n}\n#endif\n').encode('ascii'))


def check_generated(folder):
    record = json.loads((folder / 'module-inputs.json').read_text())
    if record.get('contract') != identity() or record.get('outputs') != output_hashes(folder):
        raise ValueError('Generated module inputs changed or became stale; rebuild with your supported ROM.')
    required = ('RecompiledFuncs/lookup.cpp', 'RecompiledFuncs/recomp_overlays.inl', 'rsp/n_aspMain.cpp',
                'RecompiledPatches/patches.c', 'RecompiledPatches/patches_bin.c')
    if not all((folder / name).is_file() for name in required) or not list((folder / 'RecompiledFuncs').glob('*.c')):
        raise ValueError('Generated module inputs are incomplete')
    return record


def build_generators(source, work, jobs, env):
    suffix = '.exe' if os.name == 'nt' else ''
    host = work / ('host-' + platform.system().lower() + '-' + platform.machine().lower())
    run('cmake', '--fresh', '-S', ROOT / 'cmake/module-host-tools', '-B', host, '-G', 'Ninja',
        '-DCMAKE_BUILD_TYPE=Release', f'-DBEARBIRDPAD_SOURCE={source}', env=env)
    run('cmake', '--build', host, '--target', 'N64RecompCLI', 'RSPRecomp', 'BearBirdPadGeneratorTest',
        '--parallel', jobs, env=env)
    run(host / ('BearBirdPadGeneratorTest' + suffix), env=env)
    return host / ('N64Recomp' + suffix), host / ('RSPRecomp' + suffix)


def generate(source, rom, work, llvm, jobs, env):
    compiler, linker = patch_tools(llvm, env)
    n64, rsp = build_generators(source, work, jobs, env)
    inputs = {'contract': identity(), 'rom': hashlib.sha256(rom).hexdigest(),
              'tools': {str(tool): sha256(tool) for tool in (n64, rsp, compiler, linker)}}
    generated = work / 'generated'
    if generated.is_dir():
        try:
            if check_generated(generated).get('inputs') == inputs:
                return generated
        except (OSError, ValueError):
            pass
    with tempfile.TemporaryDirectory(prefix='generation-', dir=work) as temporary:
        stage = Path(temporary) / 'source'
        export_files(source, stage, ['banjo.us.rev0.toml', 'n_aspMain.us.rev0.toml', 'patches.toml',
                                    'patches', 'include', 'src/main/register_overlays.cpp', 'src/main/register_patches.cpp'])
        export_files(source / 'BanjoRecompSyms', stage / 'BanjoRecompSyms', ['.'])
        decomp = source / 'lib/bk-decomp'
        headers = subprocess.check_output(['git', '-C', str(decomp), 'ls-files', 'src/*.h', 'src/**/*.h'], text=True).splitlines()
        export_files(decomp, stage / 'lib/bk-decomp', ['include', *headers])
        export_files(source / 'lib/rt64', stage / 'lib/rt64', ['include'])
        export_files(source / 'lib/N64ModernRuntime', stage / 'lib/N64ModernRuntime', ['ultramodern/include'])
        registration = stage / 'src/main/register_patches.cpp'
        registration.write_bytes(registration.read_bytes().replace(b'#include "librecomp/game.hpp"\n', b''))
        (stage / 'banjo.us.v10.decompressed.z64').write_bytes(decompress_rom(rom))
        (stage / 'rsp').mkdir(exist_ok=True)
        run(n64, 'banjo.us.rev0.toml', cwd=stage, env=env)
        run(rsp, 'n_aspMain.us.rev0.toml', cwd=stage, env=env)
        patches = stage / 'patches'
        flags = make_flags(patches / 'Makefile', 'CFLAGS') + make_flags(patches / 'Makefile', 'CPPFLAGS')
        sources = sorted(patches.glob('*.c'), key=lambda path: path.name)
        def compile_patch(path):
            run(compiler, *flags, path.name, '-c', '-o', path.with_suffix('.o').name, cwd=patches, env=env)
        with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
            list(pool.map(compile_patch, sources))
        run(linker, *[path.with_suffix('.o').name for path in sources],
            *make_flags(patches / 'Makefile', 'LDFLAGS'), '-o', 'patches.elf', cwd=patches, env=env)
        run(n64, 'patches.toml', cwd=stage, env=env)
        embed_patch((patches / 'patches.bin').read_bytes(), stage / 'RecompiledPatches')
        # ofstream uses CRLF on Windows. Keep source bytes and ledger stable.
        for path in stage.rglob('*'):
            if path.is_file() and path.suffix in ('.c', '.cpp', '.h', '.hpp', '.inl', '.toml', '.ld'):
                path.write_bytes(path.read_bytes().replace(b'\r\n', b'\n'))
        record = {'contract': identity(), 'inputs': inputs, 'outputs': output_hashes(stage)}
        (stage / 'module-inputs.json').write_bytes((json.dumps(record, indent=2) + '\n').encode('utf-8'))
        check_generated(stage)
        if generated.exists():
            preserved = generated.with_name('generated.recovered-' + uuid.uuid4().hex[:12])
            generated.rename(preserved)
            print(f'Preserved previous generated inputs: {preserved}', flush=True)
        stage.rename(generated)
    return generated
