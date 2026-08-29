#!/usr/bin/env python3
# run_lupa.py — runs dxui test scripts (pure Lua 5.1 compatible) in a lupa
# Lua runtime. Local machine has no standalone Lua interpreter; lupa ships
# its own. Usage:  python tests/run_lupa.py [test_file.lua ...]
# Cwd is set to the tests/ directory so the relative dofile("../client/...")
# paths inside the test scripts resolve the same way as in plain Lua.
import sys, os, lupa

ROOT = os.path.dirname(os.path.abspath(__file__))

def main():
    tests = sys.argv[1:]
    if not tests:
        tests = [f for f in ("test_kernel.lua", "test_render.lua", "test_input.lua", "test_layout.lua")
                 if os.path.exists(os.path.join(ROOT, f))]
    os.chdir(ROOT)  # relative dofile("../client/...") in tests needs this
    rc = 0
    for t in tests:
        path = t if os.path.isabs(t) else os.path.join(ROOT, t)
        if not os.path.exists(path):
            print(f"!! {t}: not found, skipped")
            continue
        with open(path, "r", encoding="utf-8") as f:
            code = f.read()
        runtime = lupa.LuaRuntime(unpack_returned_tuples=True)
        print(f"===== {os.path.basename(path)} =====")
        try:
            runtime.execute(code, path)
        except BaseException as e:
            # Lua scripts end with os.exit(1) on failure; lupa surfaces that
            # as an exception. Any exception here = the test run failed.
            print(f"!! {t}: FAILED ({type(e).__name__}): {e}")
            rc = 1
    sys.exit(rc)

if __name__ == "__main__":
    main()

