// Greet.Mod's part in C++: it needs the C++ runtime (operator new, the
// exception personality routine) and libnative.a's native_triple.
#include <stdint.h>
#include <string>
#include <vector>

extern "C" int native_triple(int x);

int32_t GreetCount(int32_t n) __asm__("Greet.-count");
int32_t GreetCount(int32_t n) {
  try {
    if (n < 0) throw n;
    std::vector<std::string> words(n, std::string("hello"));
    return native_triple(static_cast<int32_t>(words.size() * words[0].size()));
  } catch (int) {
    return -1;
  }
}
