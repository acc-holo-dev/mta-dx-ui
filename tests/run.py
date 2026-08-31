#!/usr/bin/env python3
# run.py — runs DXUI V2 test scripts under Lua 5.1 (matches MTA).
# Usage: python tests/run.py [test_file.lua ...]
#   (no args = run all test_*.lua in this directory)

import sys, os, subprocess

ROOT = os.path.dirname(os.path.abspath(__file__))

def has_lua51():
    try:
        import lupa.lua51
        return True
    except ImportError:
        return False

def run_one(test_file):
    env = os.environ.copy()
    env["PYTHONPATH"] = os.pathsep.join(sys.path)
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
    tests = args if args else sorted(
        f for f in os.listdir(ROOT) if f.startswith("test_") and f.endswith(".lua")
    )
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
