#include <xxhash.h>

#include <algorithm>
#include <cinttypes>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <vector>

int main(int argc, char **argv) {
    if (argc != 2) {
        std::fprintf(stderr, "Usage: %s <retail-rom>\n", argv[0]);
        return 2;
    }

    std::ifstream input(argv[1], std::ios::binary);
    std::vector<std::uint8_t> rom{
        std::istreambuf_iterator<char>(input),
        std::istreambuf_iterator<char>()};

    if (!input.good() && !input.eof()) {
        std::fprintf(stderr, "Failed to read ROM\n");
        return 2;
    }
    if (rom.size() < 4) {
        std::fprintf(stderr, "ROM is too small\n");
        return 2;
    }

    const std::uint32_t magic =
        (static_cast<std::uint32_t>(rom[0]) << 24) |
        (static_cast<std::uint32_t>(rom[1]) << 16) |
        (static_cast<std::uint32_t>(rom[2]) << 8) |
        static_cast<std::uint32_t>(rom[3]);

    switch (magic) {
        case 0x80371240:
            break;
        case 0x37804012:
            for (std::size_t i = 0; i + 1 < rom.size(); i += 2) {
                std::swap(rom[i], rom[i + 1]);
            }
            break;
        case 0x40123780:
            for (std::size_t i = 0; i + 3 < rom.size(); i += 4) {
                std::reverse(rom.begin() + i, rom.begin() + i + 4);
            }
            break;
        default:
            std::fprintf(stderr, "Unrecognized N64 ROM byte order\n");
            return 2;
    }

    const std::uint64_t hash = XXH3_64bits(rom.data(), rom.size());
    std::printf("%016" PRIX64 "\n", hash);
    return 0;
}
