"""Unexpected errors of the MCP server / panel back end, kept on this PC (errors.log). Sending them is up to the user: app/report.ps1."""
import json
import os
import time
import traceback


def record(src: str, exc: BaseException):
    try:
        home = os.path.join(os.environ.get("LOCALAPPDATA", ""), "SteveCADConnect")
        if not os.path.isdir(home):
            return
        f = os.path.join(home, "errors.log")
        if os.path.exists(f) and os.path.getsize(f) > 200_000:
            os.remove(f)
        ver = ""
        try:
            ver = open(os.path.join(home, "tool", "VERSION"), encoding="utf-8").readline().strip()
        except OSError:
            pass
        tb = traceback.extract_tb(exc.__traceback__)
        stack = " < ".join(f"{os.path.basename(x.filename)}:{x.lineno} {x.name}" for x in reversed(tb[-6:]))   # code places only, no values
        with open(f, "a", encoding="utf-8") as h:
            h.write(json.dumps({"t": time.strftime("%Y-%m-%d %H:%M:%S"), "src": src, "ver": ver, "msg": f"{type(exc).__name__}: {exc}"[:800], "stack": stack}, ensure_ascii=False) + "\n")
    except Exception:
        pass
