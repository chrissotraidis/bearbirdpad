#include <cstdio>

#include <SDL.h>

#include "IosLifecycle.h"
#include "TouchInputShim.hpp"
#include "ultramodern/ultramodern.hpp"

extern "C" int BanjoPadAudio_SetActive(int active);
extern "C" int BanjoPadFrontend_FlushConfigs(void);
extern "C" void plume_set_ios_swapchain_available(int available);

namespace {

bool installed = false;

void enter_background() {
    BanjoPadTouch_ReleaseAll();
    ultramodern::set_vi_scheduler_paused(true);
    plume_set_ios_swapchain_available(0);
    const bool audio_ok = BanjoPadAudio_SetActive(0) != 0;
    const bool config_ok = BanjoPadFrontend_FlushConfigs() != 0;
    const bool save_ok =
        !ultramodern::is_game_started() || ultramodern::flush_save_file();
    std::fprintf(
        stderr,
        "BANJOPAD_IOS lifecycle background: audio=%s config=%s save=%s\n",
        audio_ok ? "ok" : "failed",
        config_ok ? "ok" : "failed",
        save_ok ? "ok" : "failed");
}

void enter_foreground() {
    plume_set_ios_swapchain_available(1);
    const bool audio_ok = BanjoPadAudio_SetActive(1) != 0;
    ultramodern::set_vi_scheduler_paused(false);
    std::fprintf(
        stderr,
        "BANJOPAD_IOS lifecycle foreground: audio=%s\n",
        audio_ok ? "ok" : "failed");
}

int lifecycle_watch(void *, SDL_Event *event) {
    switch (event->type) {
    case SDL_APP_WILLENTERBACKGROUND:
    case SDL_APP_TERMINATING:
        enter_background();
        break;
    case SDL_APP_DIDENTERFOREGROUND:
        enter_foreground();
        break;
    default:
        break;
    }
    return 0;
}

} // namespace

extern "C" void BanjoPadLifecycle_Install(void) {
    if (installed) {
        return;
    }
    installed = true;
    SDL_AddEventWatch(lifecycle_watch, nullptr);
}
