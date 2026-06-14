-- Reverse FFI: export a Lean function so C/C++ can call it (see main.cpp).

@[export rl4_square]
def square (n : UInt32) : UInt32 := n * n
