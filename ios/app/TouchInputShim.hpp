#pragma once

#include <cstdint>

namespace bearbirdpad::touch {

bool get_n64_input(int controller_num, uint16_t* buttons, float* x, float* y);
void merge_right_analog(float* x, float* y);

void set_button(uint16_t button, bool pressed);
void set_stick(float x, float y);
void set_camera(float x, float y);
void release_all();

} // namespace bearbirdpad::touch

extern "C" {

void BearBirdPadTouch_SetButton(uint16_t button, int pressed);
void BearBirdPadTouch_SetStick(float x, float y);
void BearBirdPadTouch_SetCamera(float x, float y);
void BearBirdPadTouch_ReleaseAll();

}
