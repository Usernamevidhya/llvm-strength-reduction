# -*- Python -*-
# lit configuration for the LLVM strength-reduction plugin.
import os
import shutil
import subprocess

import lit.formats

config.name = "StrengthReduction"
config.test_format = lit.formats.ShTest(execute_external=False)
config.suffixes = [".ll", ".test"]
config.excludes = ["lit.cfg.py", "lit.site.cfg.py", "lit.site.cfg.py.in"]
config.test_source_root = os.path.dirname(__file__)
config.test_exec_root = os.path.join(config.project_binary_dir, "test")

# ---- tool lookup ---------------------------------------------------------
tools_dir = config.llvm_tools_dir
path = os.pathsep.join([tools_dir, os.environ.get("PATH", "")])
config.environment["PATH"] = path


def find(tool):
    return shutil.which(tool, path=path)


for required in ("opt", "FileCheck", "not"):
    if not find(required):
        lit_config.fatal("required tool '%s' not found (looked in %s)" % (required, tools_dir))

# ---- substitutions -------------------------------------------------------
# %plugin: absolute path of the freshly built plugin.
config.substitutions.append(("%plugin", config.plugin_path))
# %sr_opt: opt with the plugin loaded.
config.substitutions.append(("%sr_opt", "opt -load-pass-plugin=%s" % config.plugin_path))
config.substitutions.append(("%samples", os.path.join(config.project_source_dir, "samples")))

# ---- optional features ---------------------------------------------------
if find("clang"):
    config.available_features.add("clang")

llc = find("llc")
if llc:
    try:
        out = subprocess.run([llc, "--version"], capture_output=True, text=True).stdout
        if "aarch64" in out.lower():
            config.available_features.add("aarch64-registered-target")
    except OSError:
        pass
