#include "game_module.h"

extern "C" void recomp_entrypoint(uint8_t*, recomp_context*);
gpr get_entrypoint_address();
extern RspUcodeFunc n_aspMain;
namespace banjo { void register_bk_overlays(); void register_bk_patches(); }

extern "C" __attribute__((visibility("default")))
const BearBirdPadGameModule* bearbirdpad_get_game_module() {
    static const BearBirdPadGameModule module{
        bearbirdpad_game_module_version, sizeof(BearBirdPadGameModule), BEARBIRDPAD_MODULE_ID,
        get_entrypoint_address, recomp_entrypoint, n_aspMain,
        banjo::register_bk_overlays, banjo::register_bk_patches
    };
    return &module;
}
