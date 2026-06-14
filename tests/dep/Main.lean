-- Depends on external Lake packages from lake-manifest.json: import-graph, which transitively
-- requires lean4-cli. rules_lean4 fetches both, builds them (Cli first, then importGraph which links
-- against Cli), and links them here. A successful import proves the transitive graph resolved.
import ImportGraph

def main : IO Unit :=
  IO.println "built against importGraph (which transitively depends on Cli)"
