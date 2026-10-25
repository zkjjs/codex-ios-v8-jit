#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <unistd.h>

// Linux's unpatched aria2 does not use the routing hooks. All traffic in this
// regression goes to a local closed port; no Google account or network is used.
const char* gdirect_ip = nullptr;
const char* gdirect_sni = nullptr;
using ProgressCallback = int (*)(int64_t, int64_t, int, int, void*);
extern "C" int gdirect_download_ex(const char*, const char*, const char*,
  const char*, const char*, const char*, const char*, int, ProgressCallback, void*, bool) noexcept;
int main() {
  char directory[] = "/tmp/gdirect-lifecycle-XXXXXX";
  if (!mkdtemp(directory)) return 1;
  for (int i = 0; i < 3; ++i) {
    std::fprintf(stderr, "Starting native session %d\n", i + 1);
    int result = gdirect_download_ex("http://127.0.0.1:1/test", directory,
      "test.bin", nullptr, nullptr, nullptr, nullptr, 1, nullptr, nullptr, false);
    if (result == 0) return 2; // A closed port must report an ordinary failure.
  }
  rmdir(directory);
  std::puts("PASS: repeated native sessions return errors without crashing");
}
