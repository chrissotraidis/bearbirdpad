#include "TouchVisibility.hpp"

#include <cstdio>

namespace {

int failures = 0;

void expect(bool condition, const char* step) {
    if (!condition) {
        std::fprintf(stderr, "touch visibility FAIL: %s\n", step);
        ++failures;
    }
}

} // namespace

int main() {
    using bearbirdpad::touch::gameplay_visible;
    using bearbirdpad::touch::saved_auto_hide;

    const bool fresh = saved_auto_hide(false, false);
    expect(fresh, "absent preference defaults auto-hide on");
    expect(!saved_auto_hide(true, false), "saved auto-hide off is kept");
    expect(saved_auto_hide(true, true), "saved auto-hide on is kept");

    expect(gameplay_visible(true, fresh, false), "no controller keeps touch visible");
    expect(!gameplay_visible(true, fresh, true), "connecting a usable controller hides touch");
    expect(gameplay_visible(true, fresh, false), "disconnecting restores touch");
    expect(gameplay_visible(true, false, true), "turning auto-hide off while connected restores touch");
    expect(!gameplay_visible(true, true, true), "turning auto-hide on while connected hides touch");
    expect(gameplay_visible(true, saved_auto_hide(true, false), true),
           "a saved opt-out keeps touch visible with a controller");
    expect(!gameplay_visible(false, false, false), "Touch Controls off hides touch");

    // Show Touch Controls: enabled on, auto-hide off, controller still connected.
    expect(gameplay_visible(true, false, true), "Show restores touch with the controller connected");

    if (failures != 0) return 1;
    std::printf("Touch visibility tests passed.\n");
    return 0;
}
