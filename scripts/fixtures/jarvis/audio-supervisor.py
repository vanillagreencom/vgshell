"""Observe the real supervisor's selector inside its disposable PID namespace."""
import json
import runpy
import selectors
import sys


class ObservedSelector(selectors.DefaultSelector):
    def select(self, timeout=None):
        print(json.dumps({"select": "enter", "timeout": timeout}), flush=True)
        ready = super().select(timeout)
        print(json.dumps({"select": "ready" if ready else "timeout"}), flush=True)
        return ready


target = sys.argv[1]
selectors.DefaultSelector = ObservedSelector
supervisor = runpy.run_path(target)
# The real exec bootstrap retains stdin; one byte lets this owned tool end.
sys.argv = [target, "init", "0", "python3", "-I", "-c",
            "import sys; sys.stdin.buffer.read(1); sys.exit(23)"]
try:
    sys.exit(supervisor["main"]())
except RuntimeError as error:
    print(json.dumps({"error": str(error)}), flush=True)
    sys.exit(70)
