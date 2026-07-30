#include "plume_render_interface.h"

#include <SDL.h>
#include <SDL_syswm.h>

#include <atomic>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <memory>
#include <vector>

namespace plume {
    std::unique_ptr<RenderInterface> CreateMetalInterface();
}

namespace {
    constexpr plume::RenderFormat SwapchainFormat = plume::RenderFormat::B8G8R8A8_UNORM;
    constexpr uint32_t SwapchainTextureCount = 3;

    std::atomic<bool> foreground{true};
    std::atomic<bool> resizeRequested{false};

    int lifecycleFilter(void *, SDL_Event *event) {
        switch (event->type) {
            case SDL_APP_WILLENTERBACKGROUND:
            case SDL_APP_DIDENTERBACKGROUND:
                foreground.store(false);
                std::puts("BEARBIRDPAD_SMOKE background: drawable acquisition disabled");
                break;
            case SDL_APP_WILLENTERFOREGROUND:
                foreground.store(false);
                break;
            case SDL_APP_DIDENTERFOREGROUND:
                resizeRequested.store(true);
                foreground.store(true);
                std::puts("BEARBIRDPAD_SMOKE foreground: drawable acquisition enabled");
                break;
            case SDL_APP_TERMINATING:
                foreground.store(false);
                break;
            default:
                break;
        }

        return 1;
    }

    struct SmokeContext {
        std::unique_ptr<plume::RenderInterface> interface;
        std::unique_ptr<plume::RenderDevice> device;
        std::unique_ptr<plume::RenderCommandQueue> queue;
        std::unique_ptr<plume::RenderCommandList> commandList;
        std::unique_ptr<plume::RenderCommandFence> fence;
        std::unique_ptr<plume::RenderCommandSemaphore> acquireSemaphore;
        std::unique_ptr<plume::RenderSwapChain> swapchain;
        std::vector<std::unique_ptr<plume::RenderCommandSemaphore>> releaseSemaphores;
        std::vector<std::unique_ptr<plume::RenderFramebuffer>> framebuffers;
    };

    void rebuildFramebuffers(SmokeContext &context) {
        context.swapchain->wait();
        context.framebuffers.clear();

        if (!context.swapchain->resize()) {
            std::fputs("BEARBIRDPAD_SMOKE ERROR: swapchain resize failed\n", stderr);
            return;
        }

        for (uint32_t index = 0; index < context.swapchain->getTextureCount(); index++) {
            const plume::RenderTexture *colorAttachment = context.swapchain->getTexture(index);
            plume::RenderFramebufferDesc descriptor(&colorAttachment, 1);
            context.framebuffers.emplace_back(context.device->createFramebuffer(descriptor));
        }

        while (context.releaseSemaphores.size() < context.swapchain->getTextureCount()) {
            context.releaseSemaphores.emplace_back(context.device->createCommandSemaphore());
        }

        std::printf(
            "BEARBIRDPAD_SMOKE resize: %ux%u textures=%u refresh=%u\n",
            context.swapchain->getWidth(),
            context.swapchain->getHeight(),
            context.swapchain->getTextureCount(),
            context.swapchain->getRefreshRate()
        );
    }

    bool renderFrame(SmokeContext &context, uint64_t frameNumber) {
        assert(foreground.load() && "nextDrawable must never be called while backgrounded");

        uint32_t imageIndex = 0;
        if (!context.swapchain->acquireTexture(context.acquireSemaphore.get(), &imageIndex)) {
            return false;
        }

        plume::RenderTexture *texture = context.swapchain->getTexture(imageIndex);
        context.commandList->begin();
        context.commandList->barriers(
            plume::RenderBarrierStage::GRAPHICS,
            plume::RenderTextureBarrier(texture, plume::RenderTextureLayout::COLOR_WRITE)
        );
        context.commandList->setFramebuffer(context.framebuffers.at(imageIndex).get());

        const float pulse = float(frameNumber % 240) / 239.0f;
        const plume::RenderColor color(0.08f, 0.22f + pulse * 0.18f, 0.32f + pulse * 0.30f, 1.0f);
        context.commandList->clearColor(0, color);
        context.commandList->barriers(
            plume::RenderBarrierStage::NONE,
            plume::RenderTextureBarrier(texture, plume::RenderTextureLayout::PRESENT)
        );
        context.commandList->end();

        const plume::RenderCommandList *commandList = context.commandList.get();
        plume::RenderCommandSemaphore *waitSemaphore = context.acquireSemaphore.get();
        plume::RenderCommandSemaphore *signalSemaphore = context.releaseSemaphores.at(imageIndex).get();
        context.queue->executeCommandLists(
            &commandList,
            1,
            &waitSemaphore,
            1,
            &signalSemaphore,
            1,
            context.fence.get()
        );

        if (!context.swapchain->present(imageIndex, &signalSemaphore, 1)) {
            return false;
        }

        context.queue->waitForCommandFence(context.fence.get());
        return true;
    }
}

int main(int, char **) {
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
    SDL_SetEventFilter(lifecycleFilter, nullptr);

    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) != 0) {
        std::fprintf(stderr, "BEARBIRDPAD_SMOKE ERROR: SDL_Init: %s\n", SDL_GetError());
        return 1;
    }

    SDL_Window *window = SDL_CreateWindow(
        "BearBirdPad Metal Smoke",
        SDL_WINDOWPOS_UNDEFINED,
        SDL_WINDOWPOS_UNDEFINED,
        0,
        0,
        SDL_WINDOW_METAL | SDL_WINDOW_FULLSCREEN | SDL_WINDOW_ALLOW_HIGHDPI
    );
    if (window == nullptr) {
        std::fprintf(stderr, "BEARBIRDPAD_SMOKE ERROR: SDL_CreateWindow: %s\n", SDL_GetError());
        SDL_Quit();
        return 2;
    }

    SDL_MetalView metalView = SDL_Metal_CreateView(window);
    if (metalView == nullptr) {
        std::fprintf(stderr, "BEARBIRDPAD_SMOKE ERROR: SDL_Metal_CreateView: %s\n", SDL_GetError());
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 3;
    }

    SDL_SysWMinfo windowInfo{};
    SDL_VERSION(&windowInfo.version);
    if (SDL_GetWindowWMInfo(window, &windowInfo) != SDL_TRUE) {
        std::fprintf(stderr, "BEARBIRDPAD_SMOKE ERROR: SDL_GetWindowWMInfo: %s\n", SDL_GetError());
        SDL_Metal_DestroyView(metalView);
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 4;
    }

    SmokeContext context;
    context.interface = plume::CreateMetalInterface();
    context.device = context.interface->createDevice();
    context.queue = context.device->createCommandQueue(plume::RenderCommandListType::DIRECT);
    context.commandList = context.queue->createCommandList();
    context.fence = context.device->createCommandFence();
    context.acquireSemaphore = context.device->createCommandSemaphore();
    context.swapchain = context.queue->createSwapChain(
        plume::RenderSwapChainDesc(
            {
                windowInfo.info.uikit.window,
                SDL_Metal_GetLayer(metalView)
            },
            SwapchainFormat,
            SwapchainTextureCount
        )
    );
    rebuildFramebuffers(context);

    std::printf(
        "BEARBIRDPAD_SMOKE ready: device=%s\n",
        context.device->getDescription().name.c_str()
    );

    bool running = true;
    uint64_t frameNumber = 0;
    while (running) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT || event.type == SDL_APP_TERMINATING) {
                running = false;
            } else if (
                event.type == SDL_WINDOWEVENT &&
                (event.window.event == SDL_WINDOWEVENT_RESIZED ||
                 event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED)
            ) {
                resizeRequested.store(true);
            }
        }

        if (!foreground.load()) {
            SDL_Delay(16);
            continue;
        }

        if (resizeRequested.exchange(false) || context.swapchain->needsResize()) {
            rebuildFramebuffers(context);
        }

        if (renderFrame(context, frameNumber)) {
            frameNumber++;
            if ((frameNumber % 60) == 0) {
                std::printf("BEARBIRDPAD_SMOKE frames=%llu\n", static_cast<unsigned long long>(frameNumber));
            }
        } else {
            SDL_Delay(1);
        }
    }

    foreground.store(false);
    context.swapchain->wait();
    context = {};
    SDL_Metal_DestroyView(metalView);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
