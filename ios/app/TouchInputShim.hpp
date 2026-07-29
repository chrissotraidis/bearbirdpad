#pragma once

#include <cstdint>

namespace banjopad::touch {

bool get_n64_input(int controller_num, uint16_t* buttons, float* x, float* y);
void merge_right_analog(float* x, float* y);

void set_button(uint16_t button, bool pressed);
void set_stick(float x, float y);
void set_camera(float x, float y);
void release_all();

} // namespace banjopad::touch

extern "C" {

void BanjoPadTouch_SetButton(uint16_t button, int pressed);
void BanjoPadTouch_SetStick(float x, float y);
void BanjoPadTouch_SetCamera(float x, float y);
void BanjoPadTouch_ReleaseAll();

}
