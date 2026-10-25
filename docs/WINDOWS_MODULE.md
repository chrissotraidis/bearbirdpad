# Private module development

This draft separates the iOS app from translated game code so a local Windows
build can use the same PadMint iOS module pipeline as the other N64 ports.
Public binaries remain paused by `AGENTS.md`; this work does not publish an app,
module, ROM, generated source, or private artifact. The default manual Mac
static build remains `fetch-sources.sh`, `build-host-tools.sh`,
`prepare-generated.sh`, `build-ios.sh --device --app`, then `package-ios.sh`.

## Boundary and pairing

The empty shell retains the renderer, frontend, and one N64ModernRuntime. The
private `BearBirdPadGame.dylib` owns the translated game functions, RSP audio,
overlay tables, translated patches, and patch bytes. Its only exported symbol
is `bearbirdpad_get_game_module`; translated definitions stay hidden. Strong
patch definitions override weak base functions inside that module.

The loader checks the table version, size, source identity, and every callback
before startup registers the game. Missing or mismatched modules produce a
build error and stop startup. The identity hashes the pinned source lock and
owned runtime/build inputs with normalized line endings; a host-specific path
is never part of the identity. An older public app cannot accept this module.

The shell excludes generated game/RSP/patch targets and local `.nrm` embeds.
Its Xcode link flags retain the runtime callbacks that generated code imports.
PadMint checks all module imports against the actual shell and its known
system-runtime baseline before inserting it at the app root.

## Source preparation

`sources.lock.json` records the complete upstream and submodule revisions.
The portable preparer rejects changed revisions and unrelated tracked source
edits, and replays only the maintained patch stack. It does not reset existing
work. Windows needs Visual Studio 2022 Build Tools with Desktop development
with C++ and a Windows SDK. ARM64 tools are preferred on ARM Windows; x64 tools
are a fallback there. PadMint supplies Python, Git, CMake, Ninja and the managed
LLVM tools.

The player's supported US 1.0 ROM is normalized privately without changing the
original. The Python raw-DEFLATE decoder follows the pinned Rust decoder's
32-block ordering and swaps, then checks the complete decompressed SHA-1.
Rust and Cargo are unnecessary for this route. MIPS patches use the separately
managed `mips-clang` tool on Windows; the ordinary iOS LLVM remains the linker
and module compiler. The pinned emitter uses canonical runtime callback names
and deterministic RSP output ordering.

Generation occurs in a temporary directory. Its ledger includes the ROM,
source contract, tools, and every generated output. Cached output must match
all those hashes. Replaced outputs are preserved under `generated.recovered-*`;
a failed generation cannot replace the last complete output. Module and host
CMake configuration starts fresh so a changed toolchain path cannot silently
reuse an old compiler or SDK.

Developers may pass `--source-dir PATH`, or set `BEARBIRDPAD_SOURCE_DIR`, to
reuse an already prepared public source cache. This is strictly read-only:
exact revisions and the complete applied patch set must verify first; no fetch,
checkout, patch repair, or normalization runs against that path. Git checks
suppress optional index writes. This option is useful for a read-only shared
source tree with local Windows build outputs. The normal player path prepares
its own pinned source checkout. Cache-override tests do not establish a clean
Windows player run.

## Local validation

Build a maintainer shell on macOS with Xcode and its Metal toolchain:

```sh
python3 scripts/build-module-shell.py --jobs 4
scripts/package-ios.sh \
  build-ios-module-shell-device/Release/BanjoRecompiled.app \
  work/BearBirdPad-module-shell.ipa
```

Build the matching private module through this branch's recipe using PadMint
and that local `--app`. The unpublished prerequisites are
[PadMint #177](https://github.com/chrissotraidis/padmint/pull/177) for portable
SDK headers and strict imports, and
[PadMint #180](https://github.com/chrissotraidis/padmint/pull/180) for the managed
Windows MIPS compiler. No shipped version number is claimed for these changes.
The recipe's future `published_app` is not available while publication is paused.

Public-only validation runs the Python behavior tests, builds pinned host
recompilers and a hand-written callback-name fixture, and exercises the native
Mac module loader with synthetic libraries. The CI workflow uploads no app or
game data. Native Windows public-generator CI and a private Windows backend
run are separate evidence: neither establishes iOS loading or gameplay.

Before any release, complete the repository's audit and publication gates,
validate the matched private build on a physical device, and run PadMint's
current-main `scripts/player-check.sh` with a clean checkout before tagging
and without that checkout after publication. Private gameplay acceptance and
the official player checks remain pending for this route.

## Evidence recorded locally (2026-10-26)

- Apple's Python 3.9: 27 repository and portable behavior tests passed.
- Native Mac synthetic loader: 15 cases passed, including both strong/weak
  object link orders, rejected identities, and retry after rejection.
- The player's normalized V64 decoded byte-for-byte equal to the pinned Rust
  output; the complete expected SHA-1 passed and the original stayed unchanged.
- Mac private generation and 177 module compile/link steps passed. The paired
  empty shell built, package audit passed, and PadMint accepted all imports:
  110 app callbacks and seven known runtime symbols. Only the getter is exported
  by the module, and the shell link inputs exclude private generated objects.
- The matched pair was inserted into a local private IPA. Its source identity
  is `1ccdbcdaa0bfc48d61db85dc0c5f118d0fcc4c31a32cb691dec6a125d23e086d`.
- Windows 11 ARM64: native MSVC compiled and linked a synthetic static library
  and executable with UNC source and local C: output. Exact process-local Git
  trust configuration allowed read-only verification of the public cache.
  Actual ARM64 private generation, module linking, import checks, identity
  validation and IPA insertion passed in 110 seconds with packaged PadMint
  from `ca6fb21`, using the verified read-only source cache and managed tools.
  All 433 checked source text files exactly matched the Mac LLVM 18 reference.
- The private x64 MSVC/LLVM build passed under Windows ARM64 emulation in
  131 seconds; compiler/linker/generator PE headers confirmed x64 code. Native
  ARM helper tools were reused. Its IPA SHA-256 exactly matched the ARM64
  toolchain output. This does not claim a private build on native x64 hardware.
- Native Windows ARM64 and x64 CI independently passed fresh public source
  preparation, generator compilation, and synthetic tests.

All private artifacts and complete receipts remain local. These checks do not
establish device loading, gameplay, clean Windows player setup, or release
readiness.
