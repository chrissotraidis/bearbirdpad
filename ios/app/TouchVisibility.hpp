#pragma once

namespace bearbirdpad::touch {

// Auto-hide starts on only for players who never chose; a saved
// hide_when_controller_connected value is kept.
inline bool saved_auto_hide(bool has_saved_choice, bool saved_choice) {
    return has_saved_choice ? saved_choice : true;
}

// Gameplay touch is live unless the player turned it off, or auto-hide is on
// and a usable controller drives Player 1. "Show Touch Controls" sets
// enabled = true and auto_hide = false, so it wins over controller suppression.
inline bool gameplay_visible(bool enabled, bool auto_hide, bool controller_ready) {
    return enabled && !(auto_hide && controller_ready);
}

} // namespace bearbirdpad::touch
