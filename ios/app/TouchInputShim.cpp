#include "TouchInputShim.hpp"

#include <algorithm>
#include <array>
#include <atomic>

namespace recompinput::profiles {
bool get_n64_input(int player_index, uint16_t* buttons_out, float* x_out, float* y_out);
}

namespace {

struct TouchState {
    std::atomic<uint16_t> buttons{0};
    std::atomic<uint16_t> last_polled_buttons{0};
    std::atomic<float> stick_x{0.0f};
    std::atomic<float> stick_y{0.0f};
    std::atomic<float> camera_x{0.0f};
    std::atomic<float> camera_y{0.0f};
};

TouchState touch_state;
std::array<std::atomic<uint8_t>, 16> button_press_counts{};

constexpr uint16_t ButtonZ = 0x2000;
constexpr uint16_t ButtonCUp = 0x0008;
constexpr uint16_t ButtonCDown = 0x0004;
constexpr uint16_t ButtonCLeft = 0x0002;
constexpr uint16_t ButtonCRight = 0x0001;
constexpr uint16_t CButtons = ButtonCUp | ButtonCDown | ButtonCLeft | ButtonCRight;

float clamp_axis(float value) {
    return std::clamp(value, -1.0f, 1.0f);
}

} // namespace

bool bearbirdpad::touch::get_n64_input(int controller_num, uint16_t* buttons, float* x, float* y) {
    bool got_input = recompinput::profiles::get_n64_input(controller_num, buttons, x, y);
    if (controller_num != 0) {
        return got_input;
    }

    if (!got_input) {
        *buttons = 0;
        *x = 0.0f;
        *y = 0.0f;
    }

    uint16_t touch_buttons = touch_state.buttons.load(std::memory_order_relaxed);
    uint16_t previous_touch_buttons =
        touch_state.last_polled_buttons.exchange(touch_buttons, std::memory_order_relaxed);

    // Give held touch Z one controller sample before each new touch C-button
    // edge. Otherwise the C-button edge can be consumed by the camera before
    // Banjo's crouch/modifier state processes it.
    uint16_t new_c_buttons = static_cast<uint16_t>(
        (touch_buttons & CButtons) & ~(previous_touch_buttons & CButtons));
    if ((touch_buttons & ButtonZ) != 0) {
        touch_buttons &= static_cast<uint16_t>(~new_c_buttons);
    }

    *buttons |= touch_buttons;
    *x = clamp_axis(*x + touch_state.stick_x.load(std::memory_order_relaxed));
    *y = clamp_axis(*y + touch_state.stick_y.load(std::memory_order_relaxed));
    return true;
}

void bearbirdpad::touch::merge_right_analog(float* x, float* y) {
    *x = clamp_axis(*x + touch_state.camera_x.load(std::memory_order_relaxed));
    *y = clamp_axis(*y + touch_state.camera_y.load(std::memory_order_relaxed));
}

void bearbirdpad::touch::set_button(uint16_t button, bool pressed) {
    for (size_t bit = 0; bit < button_press_counts.size(); ++bit) {
        uint16_t mask = static_cast<uint16_t>(1u << bit);
        if ((button & mask) == 0) {
            continue;
        }
        if (pressed) {
            button_press_counts[bit].fetch_add(1, std::memory_order_relaxed);
            touch_state.buttons.fetch_or(mask, std::memory_order_relaxed);
        } else {
            uint8_t count = button_press_counts[bit].load(std::memory_order_relaxed);
            while (count != 0 &&
                   !button_press_counts[bit].compare_exchange_weak(
                       count, static_cast<uint8_t>(count - 1), std::memory_order_relaxed)) {
            }
            if (count <= 1) {
                touch_state.buttons.fetch_and(static_cast<uint16_t>(~mask), std::memory_order_relaxed);
            }
        }
    }
}

void bearbirdpad::touch::set_stick(float x, float y) {
    touch_state.stick_x.store(clamp_axis(x), std::memory_order_relaxed);
    touch_state.stick_y.store(clamp_axis(y), std::memory_order_relaxed);
}

void bearbirdpad::touch::set_camera(float x, float y) {
    touch_state.camera_x.store(clamp_axis(x), std::memory_order_relaxed);
    touch_state.camera_y.store(clamp_axis(y), std::memory_order_relaxed);
}

void bearbirdpad::touch::release_all() {
    for (auto& count : button_press_counts) {
        count.store(0, std::memory_order_relaxed);
    }
    touch_state.buttons.store(0, std::memory_order_relaxed);
    touch_state.last_polled_buttons.store(0, std::memory_order_relaxed);
    set_stick(0.0f, 0.0f);
    set_camera(0.0f, 0.0f);
}

extern "C" void BearBirdPadTouch_SetButton(uint16_t button, int pressed) {
    bearbirdpad::touch::set_button(button, pressed != 0);
}

extern "C" void BearBirdPadTouch_SetStick(float x, float y) {
    bearbirdpad::touch::set_stick(x, y);
}

extern "C" void BearBirdPadTouch_SetCamera(float x, float y) {
    bearbirdpad::touch::set_camera(x, y);
}

extern "C" void BearBirdPadTouch_ReleaseAll() {
    bearbirdpad::touch::release_all();
}
