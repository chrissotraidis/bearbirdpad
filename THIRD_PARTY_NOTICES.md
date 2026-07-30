# Third-party licenses

BanjoPad applies patches to pinned upstream source trees. The BanjoPad license
does not replace any upstream license. This table records the direct build
inputs and patched components at the revisions selected by
[`scripts/fetch-sources.sh`](scripts/fetch-sources.sh).

| Component | Pinned version | License status |
|---|---|---|
| [BanjoRecomp](https://github.com/BanjoRecomp/BanjoRecomp) | `c20314cd1bcaefff7bdbce257a25ebcc30cc1cdc` | GPL-3.0-or-later (`COPYING`; project metadata declares `GPL-3.0+`) |
| [N64ModernRuntime](https://github.com/N64Recomp/N64ModernRuntime) | `ca568b6ad79b9029d14077f0c3ffa757727c5559` | GNU GPL version 3 text in `COPYING` |
| [N64Recomp](https://github.com/N64Recomp/N64Recomp) | `2b6f05688de2abc7d86da5b4a89b84c2c6acbabe` | MIT |
| [RT64](https://github.com/rt64/rt64) | `6f1c2d99a4ea571c139f449c326fd176ba8f3496` | MIT |
| [Plume](https://github.com/rt64/rt64/tree/6f1c2d99a4ea571c139f449c326fd176ba8f3496/src/contrib/plume) | `d890ac899e505fb30040e037a4037cdeca68f033` | MIT |
| [RecompFrontend](https://github.com/N64Recomp/RecompFrontend) | `d0d90ba49f46f4896aaeda362056c21b1e342561` | **Unresolved:** no project-level license is present at this revision. The nested GamepadMotionHelpers license covers only that component. |
| [bk-decomp](https://gitlab.com/banjo.decomp/banjo-kazooie) | `351ca1580c10e550160ac11c77824fa9a498015e` | CC0-1.0 |
| [BanjoRecompSyms](https://github.com/BanjoRecomp/BanjoRecompSyms) | `6820055ca076e94e30e53d917bd9e5f71c28ca20` | CC0-1.0 |
| [hlslpp](https://github.com/redorav/hlslpp) | `6f5274c66132e8f951c400103d897582b8f21491` | MIT |
| [sljit](https://github.com/zherczeg/sljit) | `f6326087b3404efb07c6d3deed97b3c3b8098c0c` | BSD-style two-clause license |
| [nativefiledialog-extended](https://github.com/btzy/nativefiledialog-extended) | `17b6e8ce219c0677f94b63636abb9296b28841ca` | zlib |
| bcdec | Added by the maintained RT64 patch | MIT or Unlicense |
| [SDL 2](https://github.com/libsdl-org/SDL) | `2.32.10` | zlib |
| [FreeType](https://freetype.org) | `2.13.3` | FreeType License or GPL-2.0-or-later; the chosen terms and required notices must be preserved |

Each upstream checkout contains its applicable license texts and additional
transitive notices. A binary distributor must preserve those notices and
audit the exact fetched source and package, not rely on this summary alone.

## Current distribution hold

Do not publish an IPA or a third-party source bundle until RecompFrontend's
project license has been confirmed by its copyright holders or an
authoritative upstream license notice. A public BanjoPad source release should
also include the exact pinned revisions and this notice.

This file is a repository audit record, not legal advice.
