# Touch controls

BanjoPad's full N64 overlay is available during gameplay on iPhone and iPad. It
supports simultaneous touches, so the stick, either Z trigger, and another
button can be held or tapped together for Banjo-Kazooie's compound moves.

## Customize the layout

Start the game, open the `•••` menu, then choose **Settings → Controls →
Customize Touch Layout**. The editor works directly on the live overlay:

- Tap a control to select it.
- Drag it to move it within the safe area.
- Use **Size** to scale it from 70% to 150%.
- Use **Hide** or **Show** for controls you do not need.
- Choose **Reset** to restore BanjoPad's default layout.
- Choose **Done** to save and return to gameplay.

The control stick is always available and cannot be hidden. The optional L
button and D-pad remain controlled by **Show L Button** and **Show D-pad** in
Settings; the editor keeps them visible but dimmed so they can still be
positioned and sized.

Layouts are saved automatically in separate phone and tablet profiles using
normalized positions, so they survive relaunches and adapt to different
landscape sizes. They remain app-private preferences and are not packaged into
the app. Do not copy a tablet profile over a phone profile: the control sizes
and safe-area geometry are deliberately independent.

The `•••` menu button is not part of the movable gameplay layout. It remains
available when touch controls are hidden and is clamped inside the active
window's safe area.

## Verification

The layout editor was exercised in iPhone Simulator for selection, movement,
both size limits, hide/show, Reset, save/relaunch restoration, and menu
recovery.

The current Release build was then installed and played on a 12.9-inch iPad
Pro (6th generation) and an iPhone 14. Physical testing confirmed that:

- gameplay touches reach the high-DPI Metal interface correctly;
- the `•••` button remains inside the top-right safe area;
- an iPad layout does not replace the iPhone layout;
- restoring the phone defaults removes the transferred tablet geometry; and
- save/config data survives an in-place app update.

Comfort, simultaneous-touch combinations, and optional controls should still
be rechecked whenever the default geometry changes.
