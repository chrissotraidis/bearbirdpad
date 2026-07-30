#pragma once

#ifdef __cplusplus
extern "C" {
#endif

int BearBirdPadTouch_Available(void);
int BearBirdPadTouch_Enabled(void);
int BearBirdPadTouch_HideWhenControllerConnected(void);
int BearBirdPadTouch_ShowDpad(void);
int BearBirdPadTouch_ShowL(void);
void BearBirdPadTouch_BeginLayoutEditing(void);
void BearBirdPadTouch_Install(void);
void BearBirdPadTouch_SetEnabled(int enabled);
void BearBirdPadTouch_SetHideWhenControllerConnected(int hidden);
void BearBirdPadTouch_SetShowDpad(int visible);
void BearBirdPadTouch_SetShowL(int visible);
void BearBirdPadTouch_SetMenuVisible(int visible);
void BearBirdPadTouch_SetControllerConnected(int connected);

#ifdef __cplusplus
}
#endif
