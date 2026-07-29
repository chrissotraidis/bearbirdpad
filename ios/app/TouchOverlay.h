#pragma once

#ifdef __cplusplus
extern "C" {
#endif

int BanjoPadTouch_Available(void);
int BanjoPadTouch_Enabled(void);
void BanjoPadTouch_Install(void);
void BanjoPadTouch_SetEnabled(int enabled);
void BanjoPadTouch_SetMenuVisible(int visible);
void BanjoPadTouch_SetControllerConnected(int connected);

#ifdef __cplusplus
}
#endif
