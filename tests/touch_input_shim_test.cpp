#include <cassert>
#include <cmath>
#include <cstdint>

#include "TouchInputShim.hpp"

namespace {

constexpr uint16_t ButtonA = 0x8000;
constexpr uint16_t ButtonB = 0x4000;
constexpr uint16_t ButtonZ = 0x2000;
constexpr uint16_t ButtonCUp = 0x0008;
constexpr uint16_t ButtonCLeft = 0x0002;
bool stock_input_available = true;

bool nearly_equal(float a, float b) {
    return std::abs(a - b) < 0.0001f;
}

} // namespace

namespace recompinput::profiles {

bool get_n64_input(int player_index, uint16_t* buttons, float* x, float* y) {
    *buttons = 0;
    *x = 0.0f;
    *y = 0.0f;
    if (player_index != 0 || !stock_input_available) {
        return false;
    }

    *buttons = ButtonA;
    *x = 0.25f;
    *y = -0.25f;
    return true;
}

} // namespace recompinput::profiles

int main() {
    using namespace bearbirdpad::touch;

    release_all();
    set_stick(0.9f, 0.75f);
    set_button(ButtonZ, true);
    set_button(ButtonCUp, true);

    uint16_t buttons = 0;
    float x = 0.0f;
    float y = 0.0f;
    assert(get_n64_input(0, &buttons, &x, &y));
    assert(buttons == (ButtonA | ButtonZ));
    assert(nearly_equal(x, 1.0f));
    assert(nearly_equal(y, 0.5f));

    buttons = 0;
    x = 0.0f;
    y = 0.0f;
    assert(get_n64_input(0, &buttons, &x, &y));
    assert(buttons == (ButtonA | ButtonZ | ButtonCUp));
    assert(nearly_equal(x, 1.0f));
    assert(nearly_equal(y, 0.5f));

    // Talon Trot: C-Left is a momentary press while Z and analog remain held.
    set_button(ButtonCUp, false);
    set_button(ButtonCLeft, true);
    buttons = 0;
    x = 0.0f;
    y = 0.0f;
    assert(get_n64_input(0, &buttons, &x, &y));
    assert(buttons == (ButtonA | ButtonZ));

    buttons = 0;
    x = 0.0f;
    y = 0.0f;
    assert(get_n64_input(0, &buttons, &x, &y));
    assert(buttons == (ButtonA | ButtonZ | ButtonCLeft));
    assert(nearly_equal(x, 1.0f));
    assert(nearly_equal(y, 0.5f));

    set_button(ButtonCLeft, false);
    buttons = 0;
    x = 0.0f;
    y = 0.0f;
    assert(get_n64_input(0, &buttons, &x, &y));
    assert(buttons == (ButtonA | ButtonZ));
    assert(nearly_equal(x, 1.0f));
    assert(nearly_equal(y, 0.5f));

    // A second visible Z source keeps logical Z held when either source ends.
    set_button(ButtonZ, true);
    set_button(ButtonZ, false);
    buttons = 0;
    x = 0.0f;
    y = 0.0f;
    assert(get_n64_input(0, &buttons, &x, &y));
    assert((buttons & ButtonZ) != 0);

    set_button(ButtonZ, false);
    buttons = 0;
    x = 0.0f;
    y = 0.0f;
    assert(get_n64_input(0, &buttons, &x, &y));
    assert(buttons == ButtonA);

    set_camera(0.8f, -0.9f);
    x = 0.4f;
    y = -0.3f;
    merge_right_analog(&x, &y);
    assert(nearly_equal(x, 1.0f));
    assert(nearly_equal(y, -1.0f));

    release_all();
    buttons = 0;
    x = 0.0f;
    y = 0.0f;
    assert(get_n64_input(0, &buttons, &x, &y));
    assert(buttons == ButtonA);
    assert(nearly_equal(x, 0.25f));
    assert(nearly_equal(y, -0.25f));

    x = 0.4f;
    y = -0.3f;
    merge_right_analog(&x, &y);
    assert(nearly_equal(x, 0.4f));
    assert(nearly_equal(y, -0.3f));

    // A digital touch does not disturb an active analog touch.
    release_all();
    set_stick(-0.6f, 0.4f);
    set_button(ButtonB, true);
    buttons = 0;
    x = 0.0f;
    y = 0.0f;
    assert(get_n64_input(0, &buttons, &x, &y));
    assert(buttons == (ButtonA | ButtonB));
    assert(nearly_equal(x, -0.35f));
    assert(nearly_equal(y, 0.15f));
    set_button(ButtonB, false);

    release_all();
    stock_input_available = false;
    buttons = 123;
    x = 123.0f;
    y = 123.0f;
    assert(get_n64_input(0, &buttons, &x, &y));
    assert(buttons == 0);
    assert(nearly_equal(x, 0.0f));
    assert(nearly_equal(y, 0.0f));

    // A latched Z source remains held after the original finger lifts.
    set_button(ButtonZ, true);
    set_button(ButtonZ, true);
    set_button(ButtonZ, false);
    assert(get_n64_input(0, &buttons, &x, &y));
    assert(buttons == ButtonZ);
    set_button(ButtonZ, false);
    assert(get_n64_input(0, &buttons, &x, &y));
    assert(buttons == 0);

    // Working Z+A behavior is unchanged by the C-button timing correction.
    set_button(ButtonZ, true);
    set_button(ButtonA, true);
    assert(get_n64_input(0, &buttons, &x, &y));
    assert(buttons == (ButtonZ | ButtonA));
    release_all();

    buttons = 123;
    x = 123.0f;
    y = 123.0f;
    assert(!get_n64_input(1, &buttons, &x, &y));
    assert(buttons == 0);
    assert(nearly_equal(x, 0.0f));
    assert(nearly_equal(y, 0.0f));
}
