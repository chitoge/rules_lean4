-- Entry point that imports two modules sharing the `Demo` prefix but living in different olean
-- trees: `Demo.Core` (from the `:core` dependency) and `Demo.Extra` (compiled in this same target).
-- This is the case the single-target `tests/multi` pattern can't express.
import Demo.Core
import Demo.Extra

open Demo

def main : IO Unit := do
  IO.println s!"answer = {answer}, extra = {extra}"
  if answer != 42 || extra != 43 then
    throw (IO.userError s!"expected 42/43, got {answer}/{extra}")
