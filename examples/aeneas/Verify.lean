/-
Smoke test of the Aeneas verification stack: importing `Aeneas` pulls in the Aeneas support library
(built from source here) and, transitively, mathlib — all as prebuilt oleans. If this elaborates,
the whole stack is wired and Aeneas-generated `.lean` files can be checked the same way.

(Aeneas-generated code begins with `import Aeneas`; drop such a file in here and add it to `srcs` to
machine-check a real Rust-to-Lean translation.)
-/
import Aeneas

example : 1 + 1 = 2 := rfl
