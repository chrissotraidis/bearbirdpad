#include <cassert>
#include <cmath>
#include <cstdint>

#include "TouchInputShim.hpp"

namespace {

constexpr uint16_t ButtonA = 0x8000;
constexpr uint16_t ButtonZ = 0x2000;
constexpr uint16_t ButtonCUp = 0x0008;
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
    using namespace banjopad::touch;

    release_all();
    set_stick(0.9f, 0.75f);
    set_button(ButtonZ, true);
    set_button(ButtonCUp, true);

    uint16_t buttons = 0;
    float x = 0.0f;
    float y = 0.0f;
    assert(get_n64_input(0, &buttons, &x, &y));
    assert(buttons == (ButtonA | ButtonZ | ButtonCUp));
    assert(nearly_equal(x, 1.0f));
    assert(nearly_equal(y, 0.5f));

    set_button(ButtonZ, true);
    set_button(ButtonZ, false);
    buttons = 0;
    x = 0.0f;
    y = 0.0f;
    assert(get_n64_input(0, &buttons, &x, &y));
    assert((buttons & ButtonZ) != 0);

    set_button(ButtonZ, false);
    set_button(ButtonCUp, false);
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

    stock_input_available = false;
    buttons = 123;
    x = 123.0f;
    y = 123.0f;
    assert(get_n64_input(0, &buttons, &x, &y));
    assert(buttons == 0);
    assert(nearly_equal(x, 0.0f));
    assert(nearly_equal(y, 0.0f));

    buttons = 123;
    x = 123.0f;
    y = 123.0f;
    assert(!get_n64_input(1, &buttons, &x, &y));
    assert(buttons == 0);
    assert(nearly_equal(x, 0.0f));
    assert(nearly_equal(y, 0.0f));
}
