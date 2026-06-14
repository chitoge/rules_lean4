/-
Exec-time elaborator + C codegen for Lean rules, written in Lean itself so the rules need NO
python / cc toolchain — it runs under the Lean toolchain's own `lean --run`.

Reading .lean source contents is only possible at exec time (Starlark can't at analysis time), so
the per-set dependency ordering lives here:
  1. parse `import <Mod>` lines to build the intra-set DAG,
  2. topologically sort the modules,
  3. for each module in order:
       lean  <src> -o <olean-dir>/<Mod/Path>.olean -i ...ilean -c <scratch>/<Mod>.c
       leanc -c -o <obj-dir>/<Mod/Path>.o  <scratch>/<Mod>.c
     with this olean-dir prepended to LEAN_PATH so later modules import earlier ones.

Usage: lean --run elaborate.lean -- --lean L --leanc C --src-root R --olean-dir O --obj-dir B \
                                     --srcs a.lean b.lean ...
The generated .c goes to a scratch dir (not obj-dir) so the objects tree holds only `.o`.
-/

structure Opts where
  lean : String := ""
  leanc : String := ""
  srcRoot : String := ""
  oleanDir : String := ""
  objDir : String := ""
  opts : Array String := #[]  -- lean options "key=value", passed as -Dkey=value
  srcs : Array String := #[]

partial def parseArgs (as : List String) (o : Opts) : Opts :=
  match as with
  | [] => o
  | "--lean" :: v :: rest => parseArgs rest { o with lean := v }
  | "--leanc" :: v :: rest => parseArgs rest { o with leanc := v }
  | "--src-root" :: v :: rest => parseArgs rest { o with srcRoot := v }
  | "--olean-dir" :: v :: rest => parseArgs rest { o with oleanDir := v }
  | "--obj-dir" :: v :: rest => parseArgs rest { o with objDir := v }
  | "--opt" :: v :: rest => parseArgs rest { o with opts := o.opts.push v }
  | "--srcs" :: rest => { o with srcs := rest.toArray }  -- consumes the remainder
  | _ :: rest => parseArgs rest o

/-- `Foo/Bar.lean` under `src_root` => module name `Foo.Bar`. -/
def moduleName (src srcRoot : String) : String :=
  let rel := if srcRoot.isEmpty || srcRoot == "." then src
             else if src.startsWith (srcRoot ++ "/") then (src.drop (srcRoot.length + 1)).toString
             else src
  let noExt := if rel.endsWith ".lean" then (rel.dropEnd 5).toString else rel
  noExt.replace "/" "."

/-- Strip leading module-system import qualifiers (`public`, `private`, `meta`, in any combination). -/
partial def stripImportKeywords (s : String) : String :=
  if s.startsWith "public " then stripImportKeywords (s.drop 7).toString.trimAsciiStart.toString
  else if s.startsWith "private " then stripImportKeywords (s.drop 8).toString.trimAsciiStart.toString
  else if s.startsWith "meta " then stripImportKeywords (s.drop 5).toString.trimAsciiStart.toString
  else s

/-- Parse top-level `import M` lines; keep only imports that are also in this set. Handles the
    module-system forms `public`/`private`/`meta import M` and `import all M`. -/
def importsOf (content : String) (inSet : String → Bool) : List String :=
  content.splitOn "\n" |>.filterMap (fun line =>
    let t := stripImportKeywords line.trimAsciiStart.toString
    if t.startsWith "import " then
      let rest0 := (t.drop 7).toString.trimAsciiStart.toString
      let rest := if rest0.startsWith "all " then (rest0.drop 4).toString.trimAsciiStart.toString else rest0
      let modName := (rest.takeWhile (fun c => !c.isWhitespace)).toString
      if inSet modName then some modName else none
    else none)

/-- Depth-first visit accumulating (seen, reverse-order). -/
partial def visit (depsOf : String → List String) (m : String)
    (acc : List String × List String) : List String × List String :=
  let (seen, order) := acc
  if seen.contains m then (seen, order)
  else
    let seen := m :: seen
    let (seen, order) := (depsOf m).foldl (fun a d => visit depsOf d a) (seen, order)
    (seen, m :: order)

/-- Topological sort over the intra-set import graph. -/
def topoSort (mods : List String) (depsOf : String → List String) : List String :=
  let (_, order) := mods.foldl (fun a m => visit depsOf m a) ([], [])
  order.reverse

def run (cmd : String) (args : Array String) (env : Array (String × Option String)) : IO Unit := do
  let out ← IO.Process.output { cmd := cmd, args := args, env := env }
  if out.exitCode != 0 then
    let argStr := String.intercalate " " args.toList
    IO.eprintln s!"command failed ({out.exitCode}): {cmd} {argStr}"
    -- lean writes diagnostics to stdout; leanc to stderr — surface both.
    unless out.stdout.isEmpty do IO.eprintln out.stdout
    unless out.stderr.isEmpty do IO.eprintln out.stderr
    IO.Process.exit out.exitCode.toUInt8

def main (argv : List String) : IO Unit := do
  let o := parseArgs argv {}
  let pairs := o.srcs.toList.map (fun s => (moduleName s o.srcRoot, s))
  let byMod := fun (m : String) => (pairs.find? (·.1 == m)).map (·.2)
  let inSet := fun (m : String) => (byMod m).isSome
  let mods := pairs.map (·.1)

  -- precompute intra-set deps per module
  let mut depMap : List (String × List String) := []
  for (m, s) in pairs do
    let content ← IO.FS.readFile s
    depMap := (m, importsOf content inSet) :: depMap
  let depsOf := fun (m : String) => ((depMap.find? (·.1 == m)).map (·.2)).getD []

  let scratch ← IO.FS.createTempDir
  -- prepend our olean-dir to LEAN_PATH so later modules import earlier ones in this set.
  let basePath := (← IO.getEnv "LEAN_PATH").getD ""
  let leanPath := o.oleanDir ++ (if basePath.isEmpty then "" else ":" ++ basePath)
  let envOverride : Array (String × Option String) := #[("LEAN_PATH", some leanPath)]

  for m in topoSort mods depsOf do
    let some src := byMod m | throw (IO.userError s!"no source for {m}")
    let rel := m.replace "." "/"
    let olean := s!"{o.oleanDir}/{rel}.olean"
    let ilean := s!"{o.oleanDir}/{rel}.ilean"
    let cfile := s!"{scratch}/{rel}.c"
    let obj := s!"{o.objDir}/{rel}.o"
    for p in [olean, cfile, obj] do
      if let some parent := (System.FilePath.mk p).parent then
        IO.FS.createDirAll parent
    -- A --setup file only sets the module name (so `initialize_<Module>` symbols match), which —
    -- unlike `-R` — needs no path-containment check and so works when Bazel stages sources as
    -- symlinks (sandbox / remote execution). Imports are left to LEAN_PATH (which finds each
    -- module's full artifact set — .olean, .ir for meta imports, etc.); populating importArts here
    -- would list only the .olean and break `meta import`.
    let setup := "{\"name\": \"" ++ m ++ "\", \"options\": {}, \"plugins\": [], \"dynlibs\": [], "
      ++ "\"importArts\": {}, \"isModule\": false}"
    let setupPath := s!"{scratch}/{m}.setup.json"
    IO.FS.writeFile setupPath setup
    let optArgs := o.opts.map (fun kv => "-D" ++ kv)
    run o.lean (#[src, "--setup", setupPath] ++ optArgs ++ #["-o", olean, "-i", ilean, "-c", cfile]) envOverride
    run o.leanc #["-c", "-o", obj, cfile] envOverride
