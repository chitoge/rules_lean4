-- Proving in Lean: the file type-checks only if every proof is valid, so building this library
-- IS the test (see build_test in BUILD.bazel).

theorem add_comm' (a b : Nat) : a + b = b + a := Nat.add_comm a b

theorem zero_add' (n : Nat) : 0 + n = n := Nat.zero_add n

theorem append_assoc' (xs ys zs : List α) :
    (xs ++ ys) ++ zs = xs ++ (ys ++ zs) := by
  induction xs with
  | nil => rfl
  | cons _ _ ih => simp [List.cons_append, ih]

example : 2 + 2 = 4 := rfl
