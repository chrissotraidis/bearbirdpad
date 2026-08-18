#pragma once

#include <algorithm>
#include <array>
#include <cstddef>
#include <functional>
#include <optional>
#include <span>
#include <vector>

namespace bearbirdpad::controller {

template <typename Identity, std::size_t SlotCount>
class Slots {
public:
    enum class ChangeKind {
        Release,
        Assign,
    };

    struct Change {
        ChangeKind kind;
        std::size_t slot;
        Identity identity;
    };

    using Connected = std::function<bool(Identity)>;

    std::vector<Change> reconcile(
        std::span<const Identity> current,
        const Connected &connected) {
        std::vector<Change> changes;

        for (std::size_t slot = 0; slot < slots_.size(); ++slot) {
            if (!slots_[slot].has_value()) {
                continue;
            }

            const Identity identity = *slots_[slot];
            const bool enumerated =
                std::find(current.begin(), current.end(), identity) != current.end();
            if (!enumerated || !connected(identity)) {
                changes.push_back({ChangeKind::Release, slot, identity});
                slots_[slot].reset();
            }
        }

        for (const Identity identity : current) {
            if (!connected(identity) || slot_for(identity).has_value()) {
                continue;
            }

            const auto free_slot = first_free_slot();
            if (!free_slot.has_value()) {
                break;
            }

            slots_[*free_slot] = identity;
            changes.push_back({ChangeKind::Assign, *free_slot, identity});
        }

        return changes;
    }

    bool release(Identity identity) {
        const auto slot = slot_for(identity);
        if (!slot.has_value()) {
            return false;
        }
        slots_[*slot].reset();
        return true;
    }

    std::optional<std::size_t> slot_for(Identity identity) const {
        for (std::size_t slot = 0; slot < slots_.size(); ++slot) {
            if (slots_[slot].has_value() && *slots_[slot] == identity) {
                return slot;
            }
        }
        return std::nullopt;
    }

    std::optional<Identity> identity_at(std::size_t slot) const {
        return slot < slots_.size() ? slots_[slot] : std::nullopt;
    }

    std::size_t connected_count() const {
        return static_cast<std::size_t>(std::count_if(
            slots_.begin(), slots_.end(), [](const auto &identity) {
                return identity.has_value();
            }));
    }

private:
    std::optional<std::size_t> first_free_slot() const {
        for (std::size_t slot = 0; slot < slots_.size(); ++slot) {
            if (!slots_[slot].has_value()) {
                return slot;
            }
        }
        return std::nullopt;
    }

    std::array<std::optional<Identity>, SlotCount> slots_{};
};

} // namespace bearbirdpad::controller
