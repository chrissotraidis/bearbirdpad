#include <cstdio>

#include <SDL.h>

int banjo_recomp_main(int argc, char **argv);

extern "C" int SDL_main(int argc, char **argv) {
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
    SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "1");
    std::puts("BANJOPAD_IOS launcher init");
    return banjo_recomp_main(argc, argv);
}
