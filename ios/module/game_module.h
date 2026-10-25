#pragma once
#include <cstddef>
#include <cstdint>
#include "recomp.h"
#include "librecomp/rsp.hpp"

// The app owns the runtime, renderer and thread state. Only translated private
// code crosses this versioned function table; no C++ containers cross it.
struct BearBirdPadGameModule {
    uint32_t version;
    uint32_t size;
    const char* identity;
    gpr (*entrypoint_address)();
    void (*entrypoint)(uint8_t*, recomp_context*);
    RspUcodeFunc* audio;
    void (*register_overlays)();
    void (*register_patches)();
};
constexpr uint32_t bearbirdpad_game_module_version = 1;
using BearBirdPadGetModule = const BearBirdPadGameModule*();
extern "C" const char* bearbirdpad_load_game_module(const char* path);
extern "C" bool bearbirdpad_game_module_ready();
