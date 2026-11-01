#!/usr/bin/env python3
"""Native Mac ABI and patch precedence check using synthetic code only."""
import json
from pathlib import Path
import subprocess
import tempfile
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from module_build import ROOT

RUNTIME = ROOT / "sources/banjo/lib/N64ModernRuntime"
INCLUDES = [ROOT / "ios/module", RUNTIME / "N64Recomp/include",
            RUNTIME / "librecomp/include", RUNTIME / "ultramodern/include",
            RUNTIME / "thirdparty", RUNTIME / "thirdparty/sse2neon"]
FLAGS = ["xcrun", "clang++", "-std=c++20", '-DBEARBIRDPAD_MODULE_ID="test-contract"',
         *["-I" + str(path) for path in INCLUDES]]
MODULE = r'''
#include "game_module.h"
extern "C" void recomp_entrypoint(uint8_t*, recomp_context*);
extern "C" void test_host_callback(int);
static gpr address() { return 123; }
static RspExitReason audio(uint8_t*, uint32_t n) { return n == 456 ? RspExitReason::Broke : RspExitReason::Invalid; }
static void overlays() { test_host_callback(1); }
static void patches() { test_host_callback(2); }
extern "C" __attribute__((visibility("default")))
const BearBirdPadGameModule* bearbirdpad_get_game_module() {
    static BearBirdPadGameModule table{bearbirdpad_game_module_version, sizeof(BearBirdPadGameModule),
        "test-contract", address, recomp_entrypoint, audio, overlays, patches};
    /*MUTATE*/
    return &table;
}
'''
MAIN = r'''
#include "game_module.h"
#include <cstdio>
extern "C" void recomp_entrypoint(uint8_t*, recomp_context*);
gpr get_entrypoint_address();
RspExitReason n_aspMain(uint8_t*, uint32_t);
namespace banjo { void register_bk_overlays(); void register_bk_patches(); }
static int calls = 0;
extern "C" __attribute__((visibility("default"))) void test_host_callback(int n) { calls += n; }
int main(int argc, char** argv) {
    if (bearbirdpad_game_module_ready() || get_entrypoint_address() != 0) return 10;
    if (argc == 3) {
        if (!bearbirdpad_load_game_module(argv[1])) return 11;
        ++argv; --argc;
    }
    const char* error = bearbirdpad_load_game_module(argc > 1 ? argv[1] : nullptr);
    if (error) { std::puts(error); return 2; }
    if (!bearbirdpad_game_module_ready() || get_entrypoint_address() != 123) return 12;
    uint8_t bytes[1] = {0}; recomp_context ctx{};
    recomp_entrypoint(bytes, &ctx);
    if (bytes[0] != 7) return 13; // The strong patch must beat the weak original.
    if (n_aspMain(bytes, 456) != RspExitReason::Broke) return 14;
    banjo::register_bk_overlays(); banjo::register_bk_patches();
    if (calls != 3) return 15; // Module callbacks resolve to the one app runtime.
    if (bearbirdpad_load_game_module("missing-after-success")) return 17;
}
'''


def main():
    cases = {"good": "", "bad_version": "table.version = 99;", "bad_size": "table.size = 0;",
             "bad_identity": 'table.identity = "other-build";', "null_identity": "table.identity = nullptr;",
             "null_address": "table.entrypoint_address = nullptr;", "null_entry": "table.entrypoint = nullptr;",
             "null_audio": "table.audio = nullptr;", "null_overlays": "table.register_overlays = nullptr;",
             "null_patches": "table.register_patches = nullptr;", "null_table": "return nullptr;"}
    results = {}
    with tempfile.TemporaryDirectory(prefix="BearBirdPad ABI spaces ") as temporary:
        work = Path(temporary)
        (work / "main.cpp").write_text(MAIN)
        subprocess.run([*FLAGS, ROOT / "ios/module/game_module_loader.cpp", work / "main.cpp",
                        "-Wl,-export_dynamic", "-o", work / "loader"], check=True)
        for name, header, value in (("base", "recomp.h", 1), ("patch", "patch_attributes.h", 7)):
            path = work / (name + ".c")
            path.write_text(f'#include "{header}"\nRECOMP_FUNC void recomp_entrypoint(uint8_t* rdram, recomp_context* ctx) {{ rdram[0] = {value}; }}\n')
            subprocess.run(["xcrun", "clang", "-fvisibility=hidden", *["-I" + str(p) for p in INCLUDES],
                            "-c", path, "-o", work / (name + ".o")], check=True)
        for name, mutate in {**cases, "no_getter": "", "patch_first": ""}.items():
            path = work / (name + ".cpp")
            path.write_text(MODULE.replace("/*MUTATE*/", mutate) if name != "no_getter" else "int unused;\n")
            objects = [work / "base.o", work / "patch.o"]
            if name == "patch_first":
                objects.reverse()
            subprocess.run([*FLAGS, "-fvisibility=hidden", "-dynamiclib", "-Wl,-undefined,dynamic_lookup",
                            path, *objects, "-o", work / (name + ".dylib")], check=True)
        for name in [*cases, "no_getter", "patch_first", "missing"]:
            result = subprocess.run([work / "loader", work / (name + ".dylib")], capture_output=True, text=True)
            expected = 0 if name in ("good", "patch_first") else 2
            if result.returncode != expected:
                raise RuntimeError(f"{name}: {result.returncode}: {result.stdout} {result.stderr}")
            results[name] = result.returncode
        result = subprocess.run([work / "loader", work / "bad_identity.dylib", work / "good.dylib"], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError("Loading a correct module after rejection failed")
        results["retry_after_rejection"] = 0
        exports = subprocess.check_output(["xcrun", "nm", "-gU", work / "good.dylib"], text=True)
        if "_recomp_entrypoint" in exports or "_bearbirdpad_get_game_module" not in exports:
            raise RuntimeError("Private translated functions escaped hidden module visibility")
    evidence = ROOT / "work/module-evidence"
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"synthetic_native_mac_abi": results, "ios_loading": "not-tested", "gameplay": "not-tested"}
    (evidence / "loader-abi.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
