// CPU-only microbenchmark: old linear lookup vs the current indexed lookup.
// This does not measure Direct3D rendering or in-game FPS.
#include "../src/Nameplate.cpp"
#include <initializer_list>

static int LinearLookup(const char* name) {
    const uint32_t hash = HashName(name);
    for (size_t i = 0; i < Whitelist.Count; i++) {
        if (Whitelist.Hashes[i] == hash && _strnicmp(name, Whitelist.Names[i], WHITELIST_NAME_SIZE) == 0) {
            return static_cast<int>(i);
        }
    }
    return -1;
}

static char Queries[128][WHITELIST_NAME_SIZE];
static volatile uint32_t Sink;

static double Measure(int (*find)(const char*), uint32_t iterations, uint32_t& checksum) {
    LARGE_INTEGER frequency, begin, end;
    QueryPerformanceFrequency(&frequency);
    QueryPerformanceCounter(&begin);
    uint32_t sum = 0;
    for (uint32_t i = 0; i < iterations; i++) {
        sum += static_cast<uint32_t>(find(Queries[i % 128]) + 1);
    }
    QueryPerformanceCounter(&end);
    Sink = sum;
    checksum = sum;
    return static_cast<double>(end.QuadPart - begin.QuadPart) * 1000.0 / frequency.QuadPart;
}

static int Benchmark(size_t count) {
    Whitelist.Count = 0;
    Whitelist.IndexDirty = true;
    for (size_t i = 0; i < count; i++) {
        char name[WHITELIST_NAME_SIZE];
        StringCbPrintfA(name, sizeof(name), "Player%03u", static_cast<unsigned>(i));
        AddWhitelisted(name);
    }
    for (size_t i = 0; i < 128; i++) {
        StringCbPrintfA(Queries[i], sizeof(Queries[i]), (i % 2) ? "Missing%03u" : "Player%03u",
            static_cast<unsigned>((i * 37) % count));
        if (LinearLookup(Queries[i]) != FindWhitelisted(Queries[i])) { return 1; }
    }
    const uint32_t iterations = 1000000;
    uint32_t linearSum, indexedSum;
    // Warm both paths before timing.
    Measure(LinearLookup, 10000, linearSum);
    Measure(FindWhitelisted, 10000, indexedSum);
    const double linear = Measure(LinearLookup, iterations, linearSum);
    const double indexed = Measure(FindWhitelisted, iterations, indexedSum);
    if (linearSum != indexedSum) { return 2; }
    printf("%u-entry whitelist, %u lookups, 50%% hits / 50%% misses\n", static_cast<unsigned>(count), iterations);
    printf("linear: %.3f ms; indexed: %.3f ms; ratio: %.2fx\n", linear, indexed, linear / indexed);
    return 0;
}

int main() {
    for (size_t count : { size_t(8), size_t(64), size_t(512) }) {
        const int result = Benchmark(count);
        if (result != 0) { return result; }
    }
    return 0;
}
