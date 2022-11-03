# Copyright 2022 klknn.
# Copyright 2015 The Bazel Authors. All rights reserved
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""D rules for Bazel."""
load(":d_toolchain.bzl", "d_toolchain", "d_toolchain_attrs")

COMPILATION_MODE_FLAGS_POSIX = {
    "fastbuild": ["-g"],
    "dbg": ["-debug", "-g"],
    "opt": ["-checkaction=halt", "-boundscheck=safeonly", "-O"],
}

COMPILATION_MODE_FLAGS_WINDOWS = {
    "fastbuild": ["-g", "-m64", "-mscrtlib=msvcrt"],
    "dbg": ["-debug", "-g", "-m64", "-mscrtlib=msvcrtd"],
    "opt": ["-checkaction=halt", "-boundscheck=safeonly", "-O",
        "-m64", "-mscrtlib=msvcrt"],
}

def _is_windows(ctx):
    return ctx.configuration.host_path_separator == ";"

def _compilation_mode_flags(ctx):
    """Returns a list of flags based on the compilation_mode."""
    if _is_windows(ctx):
        return COMPILATION_MODE_FLAGS_WINDOWS[ctx.var["COMPILATION_MODE"]]
    else:
        return COMPILATION_MODE_FLAGS_POSIX[ctx.var["COMPILATION_MODE"]]

def _format_version(name):
    """Formats the string name to be used in a --version flag."""
    return name.replace("-", "_")

def _build_import(label, im):
    """Builds the import path under a specific label"""
    import_path = ""
    if label.workspace_root:
        import_path += label.workspace_root + "/"
    if label.package:
        import_path += label.package + "/"
    import_path += im
    return import_path

def _files_directory(files):
    """Returns the shortest parent directory of a list of files."""
    dir = files[0].dirname
    for f in files:
        if len(dir) > len(f.dirname):
            dir = f.dirname
    return dir

def _build_compile_arglist(ctx, out, depinfo, imports, string_imports, extra_flags = []):
    """Returns a list of strings constituting the D compile command arguments."""
    toolchain = d_toolchain(ctx)
    return (
        _compilation_mode_flags(ctx) +
        extra_flags + [
            "-of" + out.path,
            "-I.",
            "-w",
        ] +
        ["-I%s" % _build_import(ctx.label, im) for im in ctx.attr.imports] +
        ["-I%s" % im for im in imports] +
        ["-I" + _files_directory(toolchain.stdlib_src),
         "-I" + _files_directory(toolchain.runtime_import_src)] +
        ["%s=Have_%s" % (toolchain.flag_version, _format_version(ctx.label.name))] +
        ["%s=%s" % (toolchain.flag_version, v) for v in ctx.attr.versions] +
        ["%s=%s" % (toolchain.flag_version, v) for v in depinfo.versions] +
        ["-J=" + f.dirname for f in string_imports]
    )

def _build_link_arglist(ctx, objs, out, depinfo):
    """Returns a list of strings constituting the D link command arguments."""
    toolchain = d_toolchain(ctx)
    return (
        _compilation_mode_flags(ctx) +
        ["-of" + out.path] +
        [("-L/LIBPATH:" if _is_windows(ctx) else "-L-L") + toolchain.stdlib[0].dirname] +
        [f.path for f in depinfo.libs.to_list() + depinfo.transitive_libs.to_list()] +
        depinfo.link_flags +
        objs
    )

def _a_filetype(ctx, files):
    lib_suffix = ".lib" if _is_windows(ctx) else ".a"
    return [f for f in files if f.basename.endswith(lib_suffix)]

def _setup_deps(ctx, deps, name, working_dir):
    """Sets up dependencies.

    Walks through dependencies and constructs the commands and flags needed
    for linking the necessary dependencies.

    Args:
      deps: List of deps labels from ctx.attr.deps.
      name: Name of the current target.
      working_dir: The output directory of the current target's output.

    Returns:
      Returns a struct containing the following fields:
        libs: List of Files containing the target's direct library dependencies.
        transitive_libs: List of Files containing all of the target's
            transitive libraries.
        d_srcs: List of Files representing D source files of dependencies that
            will be used as inputs for this target.
        versions: List of D versions to be used for compiling the target.
        imports: List of Strings containing input paths that will be passed
            to the D compiler via -I flags.
        link_flags: List of linker flags.
    """
    libs = []
    transitive_libs = []
    d_srcs = []
    transitive_d_srcs = []
    versions = []
    imports = []
    link_flags = []
    for dep in deps:
        if hasattr(dep, "d_lib"):
            # The dependency is a d_library.
            libs.append(dep.d_lib)
            transitive_libs.append(dep.transitive_libs)
            d_srcs += dep.d_srcs
            transitive_d_srcs.append(dep.transitive_d_srcs)
            versions += dep.versions + ["Have_%s" % _format_version(dep.label.name)]
            link_flags.extend(dep.link_flags)
            imports += [_build_import(dep.label, im) for im in dep.imports]

        elif hasattr(dep, "d_srcs"):
            # The dependency is a d_source_library.
            d_srcs += dep.d_srcs
            transitive_d_srcs.append(dep.transitive_d_srcs)
            transitive_libs.append(dep.transitive_libs)
            link_flags += ["-L%s" % linkopt for linkopt in dep.linkopts]
            imports += [_build_import(dep.label, im) for im in dep.imports]
            versions += dep.versions

        elif CcInfo in dep:
            # The dependency is a cc_library
            native_libs = _a_filetype(ctx, _get_libs_for_static_executable(dep))
            libs.extend(native_libs)
            transitive_libs.append(depset(native_libs))

        else:
            fail("D targets can only depend on d_library, d_source_library, or " +
                 "cc_library targets.", "deps")

    return struct(
        libs = depset(libs),
        transitive_libs = depset(transitive = transitive_libs),
        d_srcs = depset(d_srcs).to_list(),
        transitive_d_srcs = depset(transitive = transitive_d_srcs),
        versions = versions,
        imports = depset(imports).to_list(),
        link_flags = depset(link_flags).to_list(),
    )

def _d_library_impl(ctx):
    """Implementation of the d_library rule."""
    d_lib = ctx.actions.declare_file((ctx.label.name + ".lib") if _is_windows(ctx) else ("lib" + ctx.label.name + ".a"))

    # Dependencies
    depinfo = _setup_deps(ctx, ctx.attr.deps, ctx.label.name, d_lib.dirname)

    # TODO(klknn): Combine these transitive fields into struct.
    trans_imports = depset(depinfo.imports, transitive = [d.trans_imports for d in ctx.attr.deps])
    trans_d_srcs = depset(depinfo.d_srcs, transitive = [d.trans_d_srcs for d in ctx.attr.deps])
    trans_string_imports = depset(ctx.files.string_imports, transitive = [d.trans_string_imports for d in ctx.attr.deps])

    # Build compile command.
    compile_args = _build_compile_arglist(
        ctx = ctx,
        out = d_lib,
        depinfo = depinfo,
        imports = trans_imports.to_list(),
        string_imports = trans_string_imports.to_list(),
        extra_flags = ["-lib"],
    )

    # Convert sources to args
    # This is done to support receiving a File that is a directory, as
    # args will auto-expand this to the contained files
    args = ctx.actions.args()
    args.add_all(compile_args)
    args.add_all(ctx.files.srcs)

    toolchain = d_toolchain(ctx)
    compile_inputs = depset(
        ctx.files.srcs +
        trans_string_imports.to_list() +
        depinfo.d_srcs +
        toolchain.stdlib +
        toolchain.stdlib_src +
        trans_d_srcs.to_list() +
        toolchain.runtime_import_src,
        transitive = [
            depinfo.transitive_d_srcs,
            depinfo.libs,
            depinfo.transitive_libs,
        ],
    )

    ctx.actions.run(
        inputs = compile_inputs,
        tools = [toolchain.compiler],
        outputs = [d_lib],
        mnemonic = "Dcompile",
        executable = toolchain.compiler.path,
        arguments = [args],
        use_default_shell_env = True,
        progress_message = "Compiling D library " + ctx.label.name,
    )

    return struct(
        files = depset([d_lib]),
        d_srcs = ctx.files.srcs,
        transitive_d_srcs = depset(depinfo.d_srcs),
        trans_d_srcs = trans_d_srcs,
        transitive_libs = depset(transitive = [depinfo.libs, depinfo.transitive_libs]),
        link_flags = depinfo.link_flags,
        versions = ctx.attr.versions,
        imports = ctx.attr.imports,
        trans_imports = trans_imports,
        trans_string_imports = trans_string_imports,
        d_lib = d_lib,
        deps = ctx.attr.deps,
    )

def _d_binary_impl_common(ctx, extra_flags = []):
    """Common implementation for rules that build a D binary."""
    d_bin = ctx.actions.declare_file(ctx.label.name + ".exe" if _is_windows(ctx) else ctx.label.name)
    d_obj = ctx.actions.declare_file(ctx.label.name + (".obj" if _is_windows(ctx) else ".o"))
    depinfo = _setup_deps(ctx, ctx.attr.deps, ctx.label.name, d_bin.dirname)
    trans_imports = depset(depinfo.imports, transitive = [d.trans_imports for d in ctx.attr.deps])
    trans_d_srcs = depset(depinfo.d_srcs, transitive = [d.trans_d_srcs for d in ctx.attr.deps])
    trans_string_imports = depset(ctx.files.string_imports, transitive = [d.trans_string_imports for d in ctx.attr.deps])

    # Build compile command
    compile_args = _build_compile_arglist(
        ctx = ctx,
        depinfo = depinfo,
        out = d_obj,
        imports = trans_imports.to_list(),
        string_imports = trans_string_imports.to_list(),
        extra_flags = ["-c"] + extra_flags,
    )

    # Convert sources to args
    # This is done to support receiving a File that is a directory, as
    # args will auto-expand this to the contained files
    args = ctx.actions.args()
    args.add_all(compile_args)
    args.add_all(ctx.files.srcs)

    toolchain = d_toolchain(ctx)
    toolchain_files = (
        toolchain.stdlib +
        toolchain.stdlib_src +
        toolchain.runtime_import_src
    )

    compile_inputs = depset(
        ctx.files.srcs +
        trans_d_srcs.to_list() +
        trans_string_imports.to_list() +
        depinfo.d_srcs +
        toolchain_files,
        transitive = [depinfo.transitive_d_srcs],
    )
    ctx.actions.run(
        inputs = compile_inputs,
        tools = [toolchain.compiler],
        outputs = [d_obj],
        mnemonic = "Dcompile",
        executable = toolchain.compiler.path,
        arguments = [args],
        use_default_shell_env = True,
        progress_message = "Compiling D binary " + ctx.label.name,
    )

    # Build link command
    link_args = _build_link_arglist(
        ctx = ctx,
        objs = [d_obj.path],
        depinfo = depinfo,
        out = d_bin,
    )

    link_inputs = depset(
        [d_obj] + toolchain_files,
        transitive = [depinfo.libs, depinfo.transitive_libs],
    )

    ctx.actions.run(
        inputs = link_inputs,
        tools = [toolchain.compiler],
        outputs = [d_bin],
        mnemonic = "Dlink",
        executable = toolchain.compiler.path,
        arguments = link_args,
        use_default_shell_env = True,
        progress_message = "Linking D binary " + ctx.label.name,
    )

    return struct(
        d_srcs = ctx.files.srcs,
        transitive_d_srcs = depset(depinfo.d_srcs),
        imports = ctx.attr.imports,
        executable = d_bin,
        trans_imports = trans_imports,
        trans_d_srcs = trans_d_srcs,
        trans_string_imports = trans_string_imports,
    )

def _d_binary_impl(ctx):
    """Implementation of the d_binary rule."""
    return _d_binary_impl_common(ctx)

def _d_test_impl(ctx):
    """Implementation of the d_test rule."""
    # TODO(klknn): Find cov files.
    return _d_binary_impl_common(ctx, extra_flags = ["-unittest", "-cov", "-main"])

def _get_libs_for_static_executable(dep):
    """
    Finds the libraries used for linking an executable statically.
    This replaces the old API dep.cc.libs
    Args:
      dep: Target
    Returns:
      A list of File instances, these are the libraries used for linking.
    """
    libs = []
    for li in dep[CcInfo].linking_context.linker_inputs.to_list():
        for library_to_link in li.libraries:
            if library_to_link.static_library != None:
                libs.append(library_to_link.static_library)
            elif library_to_link.pic_static_library != None:
                libs.append(library_to_link.pic_static_library)
            elif library_to_link.interface_library != None:
                libs.append(library_to_link.interface_library)
            elif library_to_link.dynamic_library != None:
                libs.append(library_to_link.dynamic_library)
    return libs

def _d_source_library_impl(ctx):
    """Implementation of the d_source_library rule."""
    transitive_d_srcs = []
    transitive_libs = []
    transitive_transitive_libs = []
    transitive_imports = depset()
    transitive_linkopts = depset()
    transitive_versions = depset()
    for dep in ctx.attr.deps:
        if hasattr(dep, "d_srcs"):
            # Dependency is another d_source_library target.
            transitive_d_srcs.append(dep.d_srcs)
            transitive_imports = depset(dep.imports, transitive = [transitive_imports])
            transitive_linkopts = depset(dep.linkopts, transitive = [transitive_linkopts])
            transitive_versions = depset(dep.versions, transitive = [transitive_versions])
            transitive_transitive_libs.append(dep.transitive_libs)

        elif CcInfo in dep:
            # Dependency is a cc_library target.
            native_libs = _a_filetype(ctx, _get_libs_for_static_executable(dep))
            transitive_libs.extend(native_libs)

        else:
            fail("d_source_library can only depend on other " +
                 "d_source_library or cc_library targets.", "deps")

    return struct(
        d_srcs = ctx.files.srcs,
        transitive_d_srcs = depset(transitive = transitive_d_srcs, order = "postorder"),
        transitive_libs = depset(transitive_libs, transitive = transitive_transitive_libs),
        imports = ctx.attr.imports + transitive_imports.to_list(),
        linkopts = ctx.attr.linkopts + transitive_linkopts.to_list(),
        versions = ctx.attr.versions + transitive_versions.to_list(),
    )

_d_public_attrs = {
    "srcs": attr.label_list(allow_files = [".d", ".di"]),
    "imports": attr.string_list(),
    "string_imports": attr.label_list(),
    "linkopts": attr.string_list(),
    "versions": attr.string_list(),
    "deps": attr.label_list(),
}

_d_common_attrs = dict(_d_public_attrs.items() + d_toolchain_attrs.items())

d_library = rule(
    _d_library_impl,
    attrs = _d_common_attrs,
)

d_source_library = rule(
    _d_source_library_impl,
    attrs = _d_common_attrs,
)

d_binary = rule(
    _d_binary_impl,
    attrs = _d_common_attrs,
    executable = True,
)

d_test = rule(
    _d_test_impl,
    attrs = _d_common_attrs,
    executable = True,
    test = True,
)

def d_library_with_test(name, size = "small", timeout = "short", **kwargs):
    d_library(name = name, **kwargs)
    d_test(name = name + "_test", size = size, timeout = timeout, **kwargs)
