#include <cstdio>

#include <SDL.h>

int main(int, char **) {
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) != 0) {
        std::fprintf(stderr, "BANJOPAD_CI_STUB SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }

    SDL_Window *window = SDL_CreateWindow(
        "BanjoPad CI Stub",
        SDL_WINDOWPOS_UNDEFINED,
        SDL_WINDOWPOS_UNDEFINED,
        0,
        0,
        SDL_WINDOW_METAL | SDL_WINDOW_FULLSCREEN | SDL_WINDOW_ALLOW_HIGHDPI
    );
    if (window == nullptr) {
        std::fprintf(stderr, "BANJOPAD_CI_STUB window failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 2;
    }

    SDL_MetalView metal_view = SDL_Metal_CreateView(window);
    if (metal_view == nullptr) {
        std::fprintf(stderr, "BANJOPAD_CI_STUB Metal view failed: %s\n", SDL_GetError());
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 3;
    }

    std::puts("BANJOPAD_CI_STUB ready");
    SDL_Metal_DestroyView(metal_view);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
