"""D toolchain module unifying compilers e.g. DMD, LDC2. """

load(":dmd.bzl", "dmd_compile_attrs")
load(":ldc2.bzl", "ldc2_compile_attrs")

_DCompilerInfo = provider(fields = ["name"])

def _d_compiler_impl(ctx):
    return _DCompilerInfo(name = ctx.build_setting_value)

d_compiler = rule(
    _d_compiler_impl,
    build_setting = config.string(flag = True)
)

def d_toolchain(ctx):
    """Returns a struct containing info about the D toolchain.

    Args:
      ctx: The ctx object.

    Return:
      Struct containing D toolchain info:
    """
    name = ctx.attr.d_compiler[_DCompilerInfo].name
    # print("D compiler selected by --//rules:d_compiler is: " + name)
    if name == "dmd":
        flag_version = ctx.attr._dmd_flag_version
        compiler = ctx.file._dmd_compiler
        runtime_import_src = ctx.files._dmd_runtime_import_src
        stdlib = ctx.files._dmd_stdlib
        stdlib_src = ctx.files._dmd_stdlib_src
    elif name == "ldc2":
        flag_version = ctx.attr._ldc2_flag_version
        compiler = ctx.file._ldc2_compiler
        runtime_import_src = ctx.files._ldc2_runtime_import_src
        stdlib = ctx.files._ldc2_stdlib
        stdlib_src = ctx.files._ldc2_stdlib_src
    else:
        # TODO(klknn): Support GDC.
        fail("unknown compiler: " + name)

    return struct(
        flag_version = flag_version,
        compiler = compiler,
        runtime_import_src = runtime_import_src,
        stdlib = stdlib,
        stdlib_src = stdlib_src,
    )

d_toolchain_attrs = dict(
    {"d_compiler": attr.label(default = ":d_compiler")}.items() +
    dmd_compile_attrs.items() +
    ldc2_compile_attrs.items()
)
