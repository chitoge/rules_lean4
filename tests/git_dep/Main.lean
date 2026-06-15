-- Depends on the Leancremental library fetched straight from its git tag v0.4.2
-- (see the lean_git extension in MODULE.bazel). This is Leancremental's own README "Quick Example":
-- build a small incremental graph, set an input, restabilize, and read the observed result.
import Leancremental

open Leancremental

def main : IO Unit := do
  let state ← State.create

  let x ← Var.create state 13
  let y ← Var.create state 17
  let z ← map2 (Var.watch x) (Var.watch y) (fun a b => a + b)

  let observer ← observe z
  State.stabilize state

  Var.set x 19
  State.stabilize state

  let v ← Observer.value! observer
  IO.println s!"stabilized result = {v}"
  if v != 36 then
    throw (IO.userError s!"expected 36, got {v}")
