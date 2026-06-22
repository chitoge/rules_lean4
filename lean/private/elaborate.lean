/-
Exec-time elaborator + C codegen for Lean rules, written in Lean itself so the rules need NO
python / cc toolchain — it runs under the Lean toolchain's own `lean --run`.

Reading .lean source contents is only possible at exec time (Starlark can't at analysis time), so
the per-set dependency ordering lives here:
  0. merge every dependency olean tree (`--dep-root`) into one scratch search root,
  1. parse `import <Mod>` lines to build the intra-set DAG,
  2. topologically sort the modules,
  3. for each module in order:
       lean  <src> -o <olean-dir>/<Mod/Path>.olean -i ...ilean -c <scratch>/<Mod>.c
       leanc -c -o <obj-dir>/<Mod/Path>.o  <scratch>/<Mod>.c
     copying each fresh olean into the merged root so later modules import earlier ones.

The merged root (not the individual dep roots) is the LEAN_PATH search root because Lean binds a
top-level module namespace to a single root: a dependency and this set could otherwise not share a
top-level namespace across separate roots.

Usage: lean --run elaborate.lean -- --lean L --leanc C --src-root R --olean-dir O --obj-dir B \
                                     [--dep-root D ...] --srcs a.lean b.lean ...
The generated .c goes to a scratch dir (not obj-dir) so the objects tree holds only `.o`.
-/

structure Opts where
  lean : String := ""
  leanc : String := ""
  srcRoot : String := ""
  oleanDir : String := ""
  objDir : String := ""
  opts : Array String := #[]  -- lean options "key=value", passed as -Dkey=value
  depRoots : Array String := #[]  -- olean roots of dependencies, merged into one search root
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
  | "--dep-root" :: v :: rest => parseArgs rest { o with depRoots := o.depRoots.push v }
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

/-- Copy `src` to `dst`, creating parent directories. Lean ships no symlink-creation primitive and
    shelling out to `ln` would break hermeticity, so dependency oleans are copied. -/
def copyFile (src dst : String) : IO Unit := do
  if let some parent := (System.FilePath.mk dst).parent then
    IO.FS.createDirAll parent
  IO.FS.writeBinFile dst (← IO.FS.readBinFile src)

/-- Copy every regular file under `root` into `merged`, preserving relative paths. -/
partial def mergeRoot (root merged : String) : IO Unit := do
  for p in (← (System.FilePath.mk root).walkDir) do
    if (← p.metadata).type == .file then
      let ps := p.toString
      let rel := if ps.startsWith (root ++ "/") then (ps.drop (root.length + 1)).toString else ps
      copyFile ps s!"{merged}/{rel}"

/-- Top-level module-namespace component of a module name (`Foo.Bar` => `Foo`). -/
def firstComp (m : String) : String := (m.takeWhile (· != '.')).toString

/-- Top-level namespaces an olean root provides, from its first-level entries (`Mathlib/`, a loose
    `Foo.olean`, ...). A single import root can provide many (mathlib's holds Mathlib, Batteries, …). -/
def topNamespaces (root : String) : IO (List String) := do
  let entries ← (System.FilePath.mk root).readDir
  return entries.toList.map (fun e => firstComp e.fileName)

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
  -- Lean binds a top-level module namespace to a SINGLE LEAN_PATH root and does not fall through to
  -- later roots. So every namespace must live in exactly one root. A namespace provided by more than
  -- one root — this set's own oleans (`o.oleanDir`) counts as a root — is "contested": those roots
  -- are copied into one `merged` root. Roots whose namespaces are all unique (e.g. a mathlib import,
  -- disjoint from this set's code) stay on LEAN_PATH untouched — no multi-GB copy. This both fixes
  -- same-namespace splits (dep `Foo.Core` + own `Foo.App`) and keeps large foreign-namespace
  -- dependencies cheap.
  let ownTopNs := mods.map firstComp
  let mut depNs : List (String × List String) := []
  for dr in o.depRoots do
    depNs := depNs ++ [(dr, ← topNamespaces dr)]
  let contested := fun (n : String) =>
    let ownCount := if ownTopNs.contains n then 1 else 0
    ownCount + (depNs.filter (fun (_, ns) => ns.contains n)).length ≥ 2
  let ownMerged := ownTopNs.any contested

  let merged := s!"{scratch}/merged"
  IO.FS.createDirAll merged
  let mut pathRoots : List String := []  -- uncontested dep roots, used directly on LEAN_PATH
  for (dr, ns) in depNs do
    if ns.any contested then
      mergeRoot dr merged
    else
      pathRoots := pathRoots ++ [dr]
  let stdPath := (← IO.getEnv "LEAN_PATH").getD ""
  -- merged first; own oleanDir only if its namespaces are uncontested (else its modules are in
  -- merged and oleanDir on the path would re-shadow them).
  let roots := [merged] ++ pathRoots ++ (if ownMerged then [] else [o.oleanDir])
    ++ (if stdPath.isEmpty then [] else [stdPath])
  let leanPath := ":".intercalate roots
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
    -- When this set's own oleans are merged (a contested namespace), copy each module's *whole*
    -- artifact set into `merged` so later modules can import it. Not just the .olean: module-system
    -- modules also emit data files (.olean.private / .olean.server / .ir) imports need ("missing
    -- data file" otherwise). When uncontested, o.oleanDir is on LEAN_PATH and no copy is needed.
    if ownMerged then
      let relPath := System.FilePath.mk rel
      let base := relPath.fileName.getD rel
      let srcDir := (System.FilePath.mk olean).parent.getD (System.FilePath.mk ".")
      let dstDir := match relPath.parent with
        | some p => s!"{merged}/{p}"
        | none => merged
      for ent in (← srcDir.readDir) do
        if ent.fileName.startsWith (base ++ ".") then
          copyFile ent.path.toString s!"{dstDir}/{ent.fileName}"
    run o.leanc #["-c", "-o", obj, cfile] envOverride
