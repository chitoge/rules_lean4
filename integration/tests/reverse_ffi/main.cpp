// Reverse FFI: a C++ program initializes the Lean runtime and calls an @[export]ed Lean function.
#include <lean/lean.h>
#include <cstdio>

extern "C" void lean_initialize_runtime_module();
extern "C" lean_object *initialize_Square(uint8_t builtin, lean_object *world);
extern "C" uint32_t rl4_square(uint32_t n);

int main() {
  lean_initialize_runtime_module();
  lean_object *res = initialize_Square(/*builtin=*/1, lean_io_mk_world());
  if (!lean_io_result_is_ok(res)) {
    lean_io_result_show_error(res);
    return 1;
  }
  lean_dec_ref(res);
  lean_io_mark_end_initialization();

  uint32_t s = rl4_square(7);
  printf("square(7) = %u\n", s);
  return s == 49 ? 0 : 2;
}
