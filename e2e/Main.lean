-- Consumes @leancremental (added from a git tag) and runs its README quick example, asserting 36.
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
  IO.println s!"e2e consumer result = {v}"
  if v != 36 then
    throw (IO.userError s!"expected 36, got {v}")
