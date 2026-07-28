#include <cstdio>

#include <SDL.h>

int banjo_recomp_main(int argc, char **argv);

extern "C" int SDL_main(int argc, char **argv) {
    std::puts("BANJOPAD_IOS launcher init");
    return banjo_recomp_main(argc, argv);
}
