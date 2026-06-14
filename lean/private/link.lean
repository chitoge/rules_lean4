/-
Exec-time linker for `lean_binary`, in Lean (no python/cc dep — runs under `lean --run`).

We let `leanc` own the (version-specific) runtime link line — we only hand it the objects and the
output path.

Usage: lean --run link.lean -- --leanc C --out EXE --objects a.o b.o ...
-/

structure Opts where
  leanc : String := ""
  out : String := ""
  objects : Array String := #[]

partial def parseArgs (as : List String) (o : Opts) : Opts :=
  match as with
  | [] => o
  | "--leanc" :: v :: rest => parseArgs rest { o with leanc := v }
  | "--out" :: v :: rest => parseArgs rest { o with out := v }
  | "--objects" :: rest => { o with objects := rest.toArray }  -- consumes the remainder
  | _ :: rest => parseArgs rest o

def main (argv : List String) : IO Unit := do
  let o := parseArgs argv {}
  let out ← IO.Process.output {
    cmd := o.leanc, args := #["-o", o.out] ++ o.objects
  }
  if out.exitCode != 0 then
    IO.eprintln out.stderr
    IO.Process.exit out.exitCode.toUInt8
