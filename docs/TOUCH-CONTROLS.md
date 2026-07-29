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
the app.

## Physical-device check

Simulator verification covers selection, movement, both size limits,
hide/show, Reset, save/relaunch restoration, and menu recovery. Before release,
repeat those actions on the target iPhone or iPad and check multi-finger comfort,
safe-area clearance, and the Z-plus-C compound moves with real touch input.
