"""Build actions for the Lean rules: elaborate (+C codegen), compile bundled FFI, and link.

The elaborate/link orchestration runs as a Lean script via the toolchain's own `lean --run`. Every
action uses an explicit, hermetic env and declares the whole Lean toolchain as inputs. C/C++ FFI is
either compiled with the bundled clang (compile_ffi) or supplied as `cc_deps` (objects from a
cc_library); no Lean rule depends on a C++ toolchain.
"""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def lean_env(tc, dep_roots = []):
    """Hermetic env for a lean/leanc action; paths come from staged File paths."""
    return {
        "LEAN_PATH": ":".join([tc.std_olean_root] + dep_roots),
        "LEAN_SYSROOT": tc.sysroot,
        "LD_LIBRARY_PATH": ":".join(tc.lib_dirs.to_list()),
    }

def _run_lean_script(ctx, script, tc, dep_roots, tool_args, inputs, outputs, mnemonic, msg):
    # `lean --run <script> -- <tool flags>`. Pass the preamble and the tool-arg Args as separate
    # entries in `arguments` (Bazel concatenates them); never nest one Args inside another.
    preamble = ctx.actions.args()
    preamble.add("--run")
    preamble.add(script)
    preamble.add("--")
    ctx.actions.run(
        executable = tc.lean,
        arguments = [preamble, tool_args],
        inputs = depset([script], transitive = inputs + [tc.all_files]),
        outputs = outputs,
        env = lean_env(tc, dep_roots),
        mnemonic = mnemonic,
        progress_message = msg,
    )

def elaborate(ctx, name, srcs, src_root, dep, tc, opts = {}):
    """Elaborate `srcs` to oleans and C-codegen them to native objects.

    Returns (oleans_tree, objects_tree) TreeArtifacts. The generated `.c` is written to a scratch
    dir (never an output), so the objects tree holds only `.o`. `opts` are Lean options passed as
    -Dkey=value (e.g. {"experimental.module": "true"}).
    """
    oleans = ctx.actions.declare_directory(name + "/oleans")
    objects = ctx.actions.declare_directory(name + "/objects")

    tool_args = ctx.actions.args()
    tool_args.add("--lean", tc.lean.path)
    tool_args.add("--leanc", tc.leanc.path)
    tool_args.add("--src-root", src_root)
    tool_args.add("--olean-dir", oleans.path)
    tool_args.add("--obj-dir", objects.path)
    for k, v in opts.items():
        tool_args.add("--opt", "%s=%s" % (k, v))
    tool_args.add_all("--srcs", srcs)

    _run_lean_script(
        ctx,
        script = ctx.file._builder,
        tc = tc,
        dep_roots = dep.transitive_olean_roots.to_list(),
        tool_args = tool_args,
        inputs = [depset(srcs), dep.transitive_oleans],
        outputs = [oleans, objects],
        mnemonic = "LeanElab",
        msg = "Elaborating %s" % name,
    )
    return oleans, objects

def compile_ffi(ctx, srcs, hdrs, includes, copts, tc):
    """Compile C FFI sources with the Lean toolchain's bundled clang (via leanc); returns objects.

    Zero-config and hermetic — needs no separate C++ toolchain — but C only (the bundle has no C++
    stdlib headers; use `cc_deps` for C++). lean.h is on leanc's include path automatically.
    """
    objects = []
    inc_args = ctx.actions.args()
    for inc in includes:
        inc_args.add("-I", inc)
    inc_args.add_all(copts)
    hdr_inputs = depset(hdrs, transitive = [tc.all_files])
    for src in srcs:
        obj = ctx.actions.declare_file("%s._ffi/%s.o" % (ctx.label.name, src.basename))
        args = ctx.actions.args()
        args.add("-c").add("-o", obj).add(src.path)
        ctx.actions.run(
            executable = tc.leanc,
            arguments = [args, inc_args],
            inputs = depset([src], transitive = [hdr_inputs]),
            outputs = [obj],
            env = lean_env(tc),
            mnemonic = "LeanCC",
            progress_message = "Compiling FFI %s" % src.short_path,
        )
        objects.append(obj)
    return objects

def cc_deps_objects(cc_deps):
    """Linkable objects/archives from cc_library (CcInfo) deps, compiled by the user's cc toolchain."""
    objects = []
    for dep in cc_deps:
        for li in dep[CcInfo].linking_context.linker_inputs.to_list():
            for lib in li.libraries:
                if lib.objects:
                    objects += lib.objects
                elif lib.pic_objects:
                    objects += lib.pic_objects
                elif lib.static_library:
                    objects.append(lib.static_library)
                elif lib.pic_static_library:
                    objects.append(lib.pic_static_library)
    return objects

def link(ctx, out, objects, tc):
    """Link `objects` (TreeArtifacts and/or plain `.o`/`.a` Files) into a native executable via leanc."""
    tool_args = ctx.actions.args()
    tool_args.add("--leanc", tc.leanc.path)
    tool_args.add("--out", out.path)
    tool_args.add_all("--objects", objects, expand_directories = True)

    _run_lean_script(
        ctx,
        script = ctx.file._linker,
        tc = tc,
        dep_roots = [],
        tool_args = tool_args,
        inputs = [depset(objects)],
        outputs = [out],
        mnemonic = "LeanLink",
        msg = "Linking %s" % out.short_path,
    )
