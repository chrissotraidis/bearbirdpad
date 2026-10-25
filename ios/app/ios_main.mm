#include <cstdio>

#include <SDL.h>

#include "IosLifecycle.h"
#include "TouchOverlay.h"
#if defined(BEARBIRDPAD_MODULE_SHELL)
#import <Foundation/Foundation.h>
#include "game_module.h"
#endif

int banjo_recomp_main(int argc, char **argv);

extern "C" int SDL_main(int argc, char **argv) {
#if defined(BEARBIRDPAD_MODULE_SHELL)
    NSString* modulePath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"BearBirdPadGame.dylib"];
    if (const char* error = bearbirdpad_load_game_module(modulePath.fileSystemRepresentation)) {
        std::fprintf(stderr, "%s\n", error);
        SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "Build BearBirdPad with PadMint", error, nullptr);
        return 1;
    }
#endif
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
    SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "1");
    SDL_SetHint(SDL_HINT_ACCELEROMETER_AS_JOYSTICK, "0");
    BearBirdPadLifecycle_Install();
    BearBirdPadTouch_Install();
    std::puts("BEARBIRDPAD_IOS launcher init");
    return banjo_recomp_main(argc, argv);
}
