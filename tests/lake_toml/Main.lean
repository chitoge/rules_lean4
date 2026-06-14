-- Depends on Leancremental fetched via the `lake` extension (see MODULE.bazel), which parses the
-- package's lakefile.toml at v4.30.0/v0.4.1 and generates a lean_library for it. The package name
-- ("leancremental") differs from the library name ("Leancremental"); we depend on the library.
-- Body is Leancremental's README quick example, asserting 36.
import Leancremental

open Leancremental

def main : IO Unit := do
  let st ← State.create
  let x ← Var.create st 13
  let y ← Var.create st 17
  let z ← map2 (Var.watch x) (Var.watch y) (fun a b => a + b)
  let obs ← observe z
  State.stabilize st
  Var.set x 19
  State.stabilize st
  let v ← Observer.value! obs
  IO.println s!"lake-toml result = {v}"
  if v != 36 then
    throw (IO.userError s!"expected 36, got {v}")
