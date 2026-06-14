"""Providers exposed by rules_lean4."""

LeanInfo = provider(
    doc = "Propagates a Lean target's compiled outputs to its reverse dependencies.",
    fields = {
        "transitive_oleans": "depset[File]: every .olean needed to import this target",
        "transitive_olean_roots": "depset[str]: directory prefixes to join into LEAN_PATH",
        "transitive_srcs": "depset[File]: .lean sources; a downstream-only export (e.g. for " +
                           "LEAN_SRC_PATH or tooling), not consumed by these rules",
        "transitive_objects": "depset[File]: .o objects for a downstream binary's link step",
    },
)

def merge_lean_info(deps):
    """Merge the LeanInfo of `deps` into transitive depsets (never list-concatenate)."""
    infos = [d[LeanInfo] for d in deps if LeanInfo in d]
    return struct(
        transitive_oleans = depset(transitive = [i.transitive_oleans for i in infos]),
        transitive_olean_roots = depset(transitive = [i.transitive_olean_roots for i in infos]),
        transitive_srcs = depset(transitive = [i.transitive_srcs for i in infos]),
        transitive_objects = depset(transitive = [i.transitive_objects for i in infos]),
    )
