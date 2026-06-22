-- Forward FFI: Lean calls a C function implemented in add.c.

@[extern "rl4_add"]
opaque cAdd (a b : UInt32) : UInt32

def main : IO Unit := do
  let v := cAdd 20 22
  IO.println s!"cAdd 20 22 = {v}"
  if v != 42 then
    throw (IO.userError s!"expected 42, got {v}")
