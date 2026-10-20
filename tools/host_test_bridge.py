#!/usr/bin/env python3
"""Host-side tests for pyforge.bridge.

These run the exact Python that ships in the APK against a mocked
Kotlin callback object, verifying the core interpreter-bridge logic on
your development machine:

    python3 tools/host_test_bridge.py

They cover: syntax checking, program runs with streaming output,
input() support, error payloads, cancellation (including a busy loop),
and the step-through debugger — including a genuine blocking check that
proves the tracer pauses until a command arrives.
"""
import json
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent /
                       "android" / "app" / "src" / "main" / "python"))

from pyforge import bridge  # noqa: E402

# bridge.py swaps the process-global sys.stdout while a run is active
# (so background-thread prints stream to the right run). Pin the real
# stdout here so test output is never swallowed during those windows.
_REAL_STDOUT = sys.stdout

PASS = 0
FAIL = 0


def check(name, condition, detail=""):
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"  ok    {name}", file=_REAL_STDOUT)
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}", file=_REAL_STDOUT)


class FakeBridge:
    """Mimics the Kotlin PyCallbacks object."""

    def __init__(self, cancel=False, command=2):
        self.cancel = cancel
        self.command = command
        self.pauses = []
        self.outputs = []
        self.paused_event = threading.Event()

    def isCancelled(self):
        return self.cancel

    def consumePauseRequest(self):
        return False

    def onOutput(self, run_id, stream, text):
        self.outputs.append((stream, text))

    def requestInput(self, run_id, prompt):
        return "Ada"

    def debugPause(self, run_id, line, locals_json):
        self.pauses.append((line, json.loads(locals_json)))
        self.paused_event.set()
        # Block like the real bridge until a command arrives.
        deadline = time.time() + 5
        while time.time() < deadline:
            if self._command_ready.is_set():
                break
            time.sleep(0.005)
        self._command_ready.clear()
        return self.command

    _command_ready = threading.Event()

    def release(self):
        self._command_ready.set()


def main():
    print("== check_syntax ==")
    r = json.loads(bridge.check_syntax("x = 1\nif x\n    pass\n"))
    check("detects error", r["ok"] is False and r["line"] == 2, str(r))
    r = json.loads(bridge.check_syntax("print('ok')"))
    check("accepts valid code", r["ok"] is True)

    print("== run_code ==")
    fb = FakeBridge()
    bridge.configure(fb)
    r = json.loads(bridge.run_code("r1", "/tmp/prog.py", "print('hello')\n"))
    check("runs ok", r["ok"] is True, str(r))
    # Output is coalesced into batches (one per print here), so check the
    # first batch contains the line instead of being exactly one write.
    check("streams output", fb.outputs and "hello" in fb.outputs[0][1],
          str(fb.outputs))

    print("== input() ==")
    r = json.loads(bridge.run_code("r2", "/tmp/prog.py",
                                   "name = input()\nprint('hi', name)\n"))
    check("input works", r["ok"] is True and any("Ada" in o[1] for o in fb.outputs),
          str(fb.outputs))

    print("== error payload ==")
    r = json.loads(bridge.run_code("r3", "/tmp/prog.py", "x = [1, 2]\nx[10]\n"))
    check("captures error", r["ok"] is False and r["error"]["type"] == "IndexError"
          and r["error"]["line"] == 2, str(r))

    print("== cancellation ==")
    fb = FakeBridge(cancel=True)
    bridge.configure(fb)
    r = json.loads(bridge.run_code("r4", "/tmp/prog.py",
                                   "total = 0\nwhile True:\n    total += 1\n"))
    check("busy loop is interruptible", r.get("cancelled") is True, str(r))

    print("== challenge_check ==")
    r = json.loads(bridge.challenge_check(
        "c1", "def add(a, b):\n    return a + b\n",
        "def test_add():\n    assert add(1, 2) == 3\n"
        "def test_neg():\n    assert add(-1, 1) == 0\n"))
    check("grades passing submission",
          r["ok"] is True and all(x["passed"] for x in r["results"]), str(r))
    r = json.loads(bridge.challenge_check(
        "c2", "def add(a, b):\n    return a - b\n",
        "def test_add():\n    assert add(1, 2) == 3\n"))
    check("grades failing submission",
          r["ok"] is True and not r["results"][0]["passed"], str(r))

    print("== debugger: breakpoints ==")
    fb = FakeBridge(command=2)  # Continue
    bridge.configure(fb)
    code = "total = 0\nfor i in range(3):\n    total += i\nprint('total', total)\n"
    r = json.loads(bridge.debug_run("d1", "/tmp/prog.py", code, "[3]"))
    pause_lines = [p[0] for p in fb.pauses]
    check("first pause at line 1", pause_lines[:1] == [1], str(pause_lines))
    check("breakpoint hit per iteration",
          pause_lines[1:] == [3, 3, 3], str(pause_lines))
    check("variable snapshot at breakpoint",
          any(p[1].get("i") == "1" for p in fb.pauses), str(fb.pauses))
    check("run completes", r["ok"] is True, str(r))

    print("== debugger: genuinely blocks ==")
    fb = FakeBridge(command=2)
    bridge.configure(fb)

    result_holder = {}

    def run_debug():
        result_holder["result"] = json.loads(
            bridge.debug_run("d2", "/tmp/prog.py", "a = 1\nb = 2\nc = a + b\n", "[]"))

    thread = threading.Thread(target=run_debug)
    thread.start()
    # The first pause (line 1) must arrive and block.
    blocked = fb.paused_event.wait(timeout=3)
    time.sleep(0.3)
    check("execution paused at line 1", blocked)
    check("thread still blocked (no premature completion)",
          thread.is_alive())
    check("no code after line 1 ran yet",
          len(fb.pauses) == 1, str(fb.pauses))
    fb.release()  # Continue: run to completion (no further breakpoints)
    thread.join(timeout=5)
    check("released run completes", not thread.is_alive())
    check("final state ok", result_holder.get("result", {}).get("ok") is True)

    print("== debugger: stop ==")
    fb = FakeBridge(command=3)  # Stop
    bridge.configure(fb)
    r = json.loads(bridge.debug_run("d3", "/tmp/prog.py",
                                    "a = 1\nb = 2\nprint(a + b)\n", "[]"))
    check("stop unwinds cleanly", r["ok"] is True and r.get("stoppedByUser") is True,
          str(r))

    print("== packages ==")
    r = json.loads(bridge.list_packages())
    check("lists packages", r["ok"] is True and len(r["packages"]) > 0)

    print("== git (graceful without dulwich) ==")
    r = json.loads(bridge.git_init("/tmp/pyforge-git-test"))
    check("reports missing dulwich gracefully",
          r["ok"] is False or r.get("initialized") is True, str(r))

    print()
    print(f"passed: {PASS}  failed: {FAIL}")
    sys.exit(0 if FAIL == 0 else 1)


if __name__ == "__main__":
    main()
