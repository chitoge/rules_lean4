def fib : Nat → Nat
  | 0 => 0
  | 1 => 1
  | n + 2 => fib n + fib (n + 1)

def main : IO Unit := do
  let v := fib 10
  IO.println s!"fib 10 = {v}"
  if v != 55 then
    throw (IO.userError s!"expected 55, got {v}")
