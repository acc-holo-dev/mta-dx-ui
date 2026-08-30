#!/usr/bin/env python3
# run_lupa.py — runs dxui test scripts under Lua 5.1 (matches MTA).
# Uses subprocess per test file to avoid os.exit killing the runner.
# Usage: python tests/run_lupa.py [--all] [test_file.lua ...]
#   --all  : run all 8 test files (default if no args)
# Cwd is set to tests/ so relative dofile("../client/...") paths resolve.

import sys, os, subprocess, importlib.util

ROOT = os.path.dirname(os.path.abspath(__file__))

ALL_TESTS = [
    "test_kernel.lua",
    "test_render.lua",
    "test_input.lua",
    "test_layout.lua",
    "test_m5.lua",
    "test_m6.lua",
    "test_m7.lua",
    "test_m8.lua",
    "test_m12.lua",
    "test_m13.lua",
    "test_m15.lua",
    "test_m16.lua",
    "test_m17.lua",
    "test_m18.lua",
    "test_m19.lua",
    "test_m20.lua",
]

def has_lua51():
    try:
        import lupa.lua51
        return True
    except ImportError:
        return False

def run_one(test_file):
    """Run a single test file in a subprocess with lua51 runtime."""
    env = os.environ.copy()
    env["PYTHONPATH"] = os.pathsep.join(sys.path)
    # Use lua51 if available, else default lupa
    lua_mod = "lupa.lua51" if has_lua51() else "lupa"
    cmd = [
        sys.executable, "-c",
        f"import os, sys; "
        f"os.chdir(r'{ROOT}'); "
        f"import {lua_mod} as L; "
        f"rt = L.LuaRuntime(unpack_returned_tuples=True); "
        f"rt.execute(open(r'{test_file}', encoding='utf-8').read(), r'{test_file}')"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, env=env)
    return result.returncode, result.stdout, result.stderr

def main():
    args = sys.argv[1:]
    run_all = False
    tests = []
    for a in args:
        if a == "--all":
            run_all = True
        else:
            tests.append(a)

    if not tests and not run_all:
        # default: run all
        tests = ALL_TESTS
    elif run_all:
        tests = ALL_TESTS

    # Filter to existing files
    tests = [t for t in tests if os.path.exists(os.path.join(ROOT, t))]
    if not tests:
        print("No test files to run")
        sys.exit(1)

    rc = 0
    for t in tests:
        print(f"===== {t} =====")
        code, stdout, stderr = run_one(t)
        if stdout:
            print(stdout, end="")
        if stderr:
            print(stderr, file=sys.stderr, end="")
        if code == 0:
            print(f"{t}: PASSED")
        else:
            print(f"!! {t}: FAILED (exit {code})")
            rc = 1
    sys.exit(rc)

if __name__ == "__main__":
    main()
