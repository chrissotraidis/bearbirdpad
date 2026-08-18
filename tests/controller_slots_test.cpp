#include <array>
#include <cassert>
#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

#include "ControllerSlots.hpp"

namespace {

struct FakeController {
    bool connected = true;
    bool button = false;
    float axis = 0.0f;
};

class Harness {
public:
    using Slots = bearbirdpad::controller::Slots<int, 4>;

    void reconcile(const char *reason, const std::vector<int> &current) {
        last_reason = reason;
        const auto changes = slots.reconcile(current, [&](int identity) {
            const auto found = controllers.find(identity);
            return found != controllers.end() && found->second.connected;
        });

        for (const auto &change : changes) {
            if (change.kind == Slots::ChangeKind::Release) {
                controllers.erase(change.identity);
            }
        }
    }

    bool button(std::size_t slot) const {
        const auto identity = slots.identity_at(slot);
        if (!identity.has_value()) {
            return false;
        }
        const auto found = controllers.find(*identity);
        return found != controllers.end() && found->second.connected &&
               found->second.button;
    }

    float axis(std::size_t slot) const {
        const auto identity = slots.identity_at(slot);
        if (!identity.has_value()) {
            return 0.0f;
        }
        const auto found = controllers.find(*identity);
        return found != controllers.end() && found->second.connected
                   ? found->second.axis
                   : 0.0f;
    }

    Slots slots;
    std::unordered_map<int, FakeController> controllers;
    std::string last_reason;
};

void missed_removal_releases_held_input_and_return_reclaims_player_one() {
    Harness harness;
    harness.controllers[10] = {.connected = true, .button = true, .axis = 0.75f};
    harness.reconcile("startup", {10});
    assert(harness.slots.slot_for(10) == 0);
    assert(harness.button(0));
    assert(harness.axis(0) == 0.75f);

    // No remove event arrives. Enumeration and the backend connection check
    // are the only evidence that the sleeping controller is gone.
    harness.controllers[10].connected = false;
    harness.reconcile("active-check", {10});
    assert(!harness.slots.slot_for(10).has_value());
    assert(!harness.button(0));
    assert(harness.axis(0) == 0.0f);

    harness.controllers[11] = {.connected = true};
    harness.reconcile("device-added", {11});
    assert(harness.slots.slot_for(11) == 0);
}

void additional_controller_uses_player_two_without_moving_player_one() {
    Harness harness;
    harness.controllers[20] = {.connected = true};
    harness.reconcile("startup", {20});
    harness.controllers[21] = {.connected = true};
    harness.reconcile("device-added", {20, 21});

    assert(harness.slots.slot_for(20) == 0);
    assert(harness.slots.slot_for(21) == 1);
}

void changing_one_controller_preserves_the_other_owner() {
    Harness harness;
    harness.controllers[30] = {.connected = true};
    harness.controllers[31] = {.connected = true};
    harness.reconcile("startup", {30, 31});

    harness.controllers[31].connected = false;
    harness.controllers[32] = {.connected = true};
    harness.reconcile("device-changed", {30, 32});

    assert(harness.slots.slot_for(30) == 0);
    assert(harness.slots.slot_for(32) == 1);
    assert(!harness.slots.slot_for(31).has_value());
}

void foreground_reconciliation_repairs_missed_changes() {
    Harness harness;
    harness.controllers[40] = {.connected = true};
    harness.controllers[41] = {.connected = true};
    harness.reconcile("startup", {40, 41});

    harness.controllers[40].connected = false;
    harness.reconcile("foreground", {41});

    assert(harness.last_reason == "foreground");
    assert(harness.slots.slot_for(41) == 1);
    assert(!harness.slots.identity_at(0).has_value());

    harness.controllers[42] = {.connected = true};
    harness.reconcile("device-added", {41, 42});
    assert(harness.slots.slot_for(42) == 0);
    assert(harness.slots.slot_for(41) == 1);
}

} // namespace

int main() {
    missed_removal_releases_held_input_and_return_reclaims_player_one();
    additional_controller_uses_player_two_without_moving_player_one();
    changing_one_controller_preserves_the_other_owner();
    foreground_reconciliation_repairs_missed_changes();
    return 0;
}
