-- Diamond: Main imports Left and Right, both import Base. Exercises the exec-time topo-sort.
import Left
import Right

def main : IO Unit := do
  let v := left + right          -- (1+10) + (1+100) = 112
  IO.println s!"left + right = {v}"
  if v != 112 then
    throw (IO.userError s!"expected 112, got {v}")
