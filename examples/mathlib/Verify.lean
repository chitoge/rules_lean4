/-
A nontrivial proof checked against mathlib. Building this library elaborates every declaration, so
a successful `bazel build`/`bazel test` *is* the proof check — if any proof were wrong, elaboration
(and the build) would fail.
-/
import Mathlib.Data.Nat.Prime.Basic
import Mathlib.Analysis.SpecialFunctions.Pow.Real
import Mathlib.Tactic

namespace Example

-- A real mathlib theorem used directly: there are infinitely many primes.
theorem infinitely_many_primes (n : ℕ) : ∃ p, n ≤ p ∧ p.Prime :=
  Nat.exists_infinite_primes n

-- Tactic proofs that exercise mathlib's algebra/order automation.
theorem binomial_square (a b : ℝ) : (a + b) ^ 2 = a ^ 2 + 2 * a * b + b ^ 2 := by
  ring

theorem sq_nonneg' (x : ℝ) : 0 ≤ x ^ 2 :=
  sq_nonneg x

theorem amgm_two (a b : ℝ) : 2 * a * b ≤ a ^ 2 + b ^ 2 := by
  nlinarith [sq_nonneg (a - b)]

end Example
