"""Back end of the tables in the chat panel (no AI involved): runs a few whitelisted tools on the CAD that hosts the panel.
python panel.py --cad zwcad|autocad --pid <CAD process id>; one JSON request per stdin line, one JSON reply per stdout line."""
import argparse
import asyncio
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from stevecad import tools  # noqa: E402
from stevecad.com import EXECUTOR  # noqa: E402

READ = {"info", "audit", "find_duplicates", "quantities", "list_layers", "list_attributes", "zoom_to"}
WRITE = {"map_layers", "set_attributes", "set_props", "delete", "delete_duplicates", "export_xlsx", "export_ifc"}


def pick(pid):
    """Connect to the CAD window of this process, never to another one that happens to be open."""
    import win32process
    for c in tools.C.conn.running():
        if win32process.GetWindowThreadProcessId(int(c["app"].HWND))[1] == pid:
            tools.C.conn._app = c["app"]
            return True
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cad", choices=["zwcad", "autocad"], required=True)
    ap.add_argument("--pid", type=int, required=True)
    a = ap.parse_args()
    for s in (sys.stdin, sys.stdout):
        s.reconfigure(encoding="utf-8")
    tools.build(a.cad, None, False)
    fn = {f.__name__: f for f, _ in tools._REGISTRY}
    for line in sys.stdin:
        rid = None
        try:
            q = json.loads(line)
            rid, name, args = q.get("id"), q.get("name"), dict(q.get("args") or {})
            if name not in READ | WRITE:
                raise ValueError("Không hỗ trợ.")
            if not EXECUTOR.submit(pick, a.pid).result():
                raise ValueError("Không nối được với CAD. CAD đang bận, hoặc chưa mở bản vẽ nào.")
            want = args.pop("_drawing", None)
            if name in WRITE or want:
                now = EXECUTOR.submit(lambda: tools.Drawings.name(tools.doc())).result()
                if not want or now != want:
                    raise ValueError("Bản vẽ đang mở đã đổi so với lúc quét. Quét lại rồi làm tiếp.")
            if name == "find_duplicates":
                args["delete"] = False
            if name == "delete_duplicates":
                name, args["delete"] = "find_duplicates", True
            r = asyncio.run(fn[name](**args))
            if isinstance(r, dict) and name not in ("export_xlsx",):
                r["_drawing"] = EXECUTOR.submit(lambda: tools.Drawings.name(tools.doc())).result()
            out = {"id": rid, "ok": True, "r": r}
        except Exception as e:
            out = {"id": rid, "ok": False, "error": str(e)}
        sys.stdout.write(json.dumps(out, ensure_ascii=False, default=str) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
