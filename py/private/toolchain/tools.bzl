"""Declaration of concrete toolchains for our Rust tools"""

load("//tools:integrity.bzl", "RELEASED_BINARY_INTEGRITY")
load("//tools:version.bzl", "VERSION")

# The expected config for each tool, whether it runs in an action or at runtime
RUST_BIN_CFG = {
    # unpack wheels happens inside an action
    "unpack": "exec",
    # creating the virtualenv happens when the binary is running
    "venv": "target",
}

TOOLCHAIN_PLATFORMS = {
    "darwin_amd64": struct(
        arch = "x86_64",
        vendor_os_abi = "apple-darwin",
        compatible_with = [
            "@platforms//os:macos",
            "@platforms//cpu:x86_64",
        ],
    ),
    "darwin_arm64": struct(
        arch = "aarch64",
        vendor_os_abi = "apple-darwin",
        compatible_with = [
            "@platforms//os:macos",
            "@platforms//cpu:aarch64",
        ],
    ),
    "linux_amd64": struct(
        arch = "x86_64",
        vendor_os_abi = "unknown-linux-gnu",
        compatible_with = [
            "@platforms//os:linux",
            "@platforms//cpu:x86_64",
        ],
    ),
    "linux_arm64": struct(
        arch = "aarch64",
        vendor_os_abi = "unknown-linux-gnu",
        compatible_with = [
            "@platforms//os:linux",
            "@platforms//cpu:aarch64",
        ],
    ),
}

def _toolchain_impl(ctx):
    binary = ctx.file.bin

    # Make a variable available in places like genrules.
    # See https://docs.bazel.build/versions/main/be/make-variables.html#custom_variables
    template_variables = platform_common.TemplateVariableInfo({
        ctx.attr.template_var: binary.path,
    })
    default_info = DefaultInfo(
        files = depset([binary]),
        runfiles = ctx.runfiles(files = [binary]),
    )

    # Export all the providers inside our ToolchainInfo
    # so the resolved_toolchain rule can grab and re-export them.
    toolchain_info = platform_common.ToolchainInfo(
        bin = binary,
        template_variables = template_variables,
        default_info = default_info,
    )

    return [toolchain_info, default_info, template_variables]

py_tool_toolchain = rule(
    implementation = _toolchain_impl,
    attrs = {
        "bin": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "template_var": attr.string(
            mandatory = True,
        ),
    },
)

def source_toolchain(name, toolchain_type, bin):
    """Makes vtool toolchain and repositories

    Args:
        name: Override the prefix for the generated toolchain repositories.
        toolchain_type: Toolchain type reference.
        bin: the rust_binary target
    """

    toolchain_rule = "{}_toolchain_source".format(name)
    py_tool_toolchain(
        name = toolchain_rule,
        bin = bin,
        template_var = "{}_BIN".format(name.upper()),
    )
    native.toolchain(
        name = "{}_source_toolchain".format(name),
        toolchain = toolchain_rule,
        toolchain_type = toolchain_type,
    )

def _prebuilt_tool_repo_impl(rctx):
    build_content = """\
# Generated by @aspect_rules_py//py/private/toolchain:tools.bzl
load("@aspect_rules_py//py/private/toolchain:tools.bzl", "py_tool_toolchain")

package(default_visibility = ["//visibility:public"])
"""

    # For manual testing, override these environment variables
    # TODO: use rctx.getenv when available, see https://github.com/bazelbuild/bazel/pull/20944
    release_fork = "aspect-build"
    release_version = VERSION
    if "RULES_PY_RELEASE_FORK" in rctx.os.environ:
        release_fork = rctx.os.environ["RULES_PY_RELEASE_FORK"]
    if "RULES_PY_RELEASE_VERSION" in rctx.os.environ:
        release_version = rctx.os.environ["RULES_PY_RELEASE_VERSION"]

    for tool, cfg in RUST_BIN_CFG.items():
        filename = "-".join([
            tool,
            TOOLCHAIN_PLATFORMS[rctx.attr.platform].arch,
            TOOLCHAIN_PLATFORMS[rctx.attr.platform].vendor_os_abi,
        ])
        url = "https://github.com/{}/rules_py/releases/download/v{}/{}".format(
            release_fork,
            release_version,
            filename,
        )
        rctx.download(
            url = url,
            sha256 = RELEASED_BINARY_INTEGRITY[filename],
            executable = True,
            output = tool,
        )
        build_content += """py_tool_toolchain(name = "{tool}_toolchain", bin = "{tool}", template_var = "{tool_upper}_BIN")\n""".format(
            tool = tool,
            tool_upper = tool.upper(),
        )

    rctx.file("BUILD.bazel", build_content)

prebuilt_tool_repo = repository_rule(
    doc = "Download pre-built binary tools and create concrete toolchains for them",
    implementation = _prebuilt_tool_repo_impl,
    attrs = {
        "platform": attr.string(mandatory = True, values = TOOLCHAIN_PLATFORMS.keys()),
    },
)