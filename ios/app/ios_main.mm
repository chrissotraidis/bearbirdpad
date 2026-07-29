#include <cstdio>

#include <SDL.h>

#include "IosLifecycle.h"
#include "TouchOverlay.h"

int banjo_recomp_main(int argc, char **argv);

extern "C" int SDL_main(int argc, char **argv) {
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
    SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "1");
    SDL_SetHint(SDL_HINT_ACCELEROMETER_AS_JOYSTICK, "0");
    BanjoPadLifecycle_Install();
    BanjoPadTouch_Install();
    std::puts("BANJOPAD_IOS launcher init");
    return banjo_recomp_main(argc, argv);
}
