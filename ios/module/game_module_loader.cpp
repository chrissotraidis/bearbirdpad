#include "game_module.h"
#include <cstdio>
#include <cstring>
#include <dlfcn.h>

namespace {
const BearBirdPadGameModule* module = nullptr;
void* library = nullptr;
}

extern "C" const char* bearbirdpad_load_game_module(const char* path) {
    if (module) return nullptr;
    if (!path || !*path) return "This copy needs its game module. Build it with PadMint using your supported ROM.";
    void* candidate = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!candidate) {
        std::fprintf(stderr, "[game module] %s\n", dlerror());
        return "The game module could not load. Build this copy with PadMint and install it again.";
    }
    auto getter = reinterpret_cast<BearBirdPadGetModule*>(dlsym(candidate, "bearbirdpad_get_game_module"));
    const auto* value = getter ? getter() : nullptr;
    if (!value || value->version != bearbirdpad_game_module_version || value->size != sizeof(BearBirdPadGameModule) ||
        !value->identity || std::strcmp(value->identity, BEARBIRDPAD_MODULE_ID) != 0 ||
        !value->entrypoint_address || !value->entrypoint || !value->audio ||
        !value->register_overlays || !value->register_patches) {
        dlclose(candidate);
        return "The game module belongs to a different app build. Build this copy with PadMint again.";
    }
    library = candidate; // Keep code and overlay pointers alive for every game thread.
    module = value;
    return nullptr;
}

extern "C" bool bearbirdpad_game_module_ready() { return module != nullptr; }
gpr get_entrypoint_address() { return module ? module->entrypoint_address() : 0; }
extern "C" void recomp_entrypoint(uint8_t* rdram, recomp_context* ctx) { module->entrypoint(rdram, ctx); }
RspExitReason n_aspMain(uint8_t* rdram, uint32_t address) { return module->audio(rdram, address); }
namespace banjo {
void register_bk_overlays() { module->register_overlays(); }
void register_bk_patches() { module->register_patches(); }
}
