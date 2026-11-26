"""Back end of the tables in the chat panel (no AI involved): runs a few whitelisted tools on the CAD that hosts the panel.
python panel.py --cad zwcad|autocad --pid <CAD process id>; one JSON request per stdin line, one JSON reply per stdout line."""
import argparse
import asyncio
import json
import math
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from stevecad import tools  # noqa: E402
from stevecad.com import EXECUTOR  # noqa: E402

READ = {"info", "audit", "find_duplicates", "quantities", "list_layers", "list_attributes", "zoom_to", "solid_info"}
KCS = {"kcs_check", "kcs_catalog", "kcs_mark", "kcs_unmark", "kcs_zoom", "kcs_table"}   # design checks (Kiểm tra KCS): a separate package, installed on its own in %LOCALAPPDATA%\SteveCADConnect\kcs


def kcs_api():
    home = os.path.join(os.environ.get("LOCALAPPDATA", ""), "SteveCADConnect", "kcs")
    if not os.path.isfile(os.path.join(home, "stevekcs", "api.py")):
        raise ValueError("Máy này chưa cài gói Kiểm tra KCS. Liên hệ Steve Tran, 0987 779 228.")
    if home not in sys.path:
        sys.path.insert(0, home)
    from stevekcs import api   # noqa: E402
    return api


def kcs_catalog():
    """Standards the package knows and the choices of each (class, speed...)."""
    return kcs_api().catalog()


def cad_to_dxf(dwg, folder):
    """DXF of a copy of the drawing, written by the CAD that hosts the panel: open the copy read-only, save it as DXF
    2018, close it, go back to the drawing the person was on. Their own drawing is never saved or changed."""
    copy = os.path.join(folder, "kcs-copy.dwg")
    shutil.copyfile(dwg, copy)
    out = os.path.join(folder, "kcs-copy.dxf")

    def go():
        app = tools.C.conn._app
        was = app.ActiveDocument
        d = app.Documents.Open(copy, True)
        try:
            d.SaveAs(out, 65)   # AutoCAD 2018 DXF (ac2018_dxf; ZWCAD uses the same value)
        finally:
            try:
                d.Close(False)
            finally:
                try:
                    was.Activate()
                except Exception:
                    pass
        return out
    EXECUTOR.submit(go).result()
    return out if os.path.exists(out) else None


def kcs_check(module="tuyen", standard="tcvn5729", v=80):
    """Checks the saved file of the drawing open in this CAD. The package does the work; this only finds it."""
    api = kcs_api()

    def where():
        d = tools.doc()
        return getattr(d, "FullName", "") or "", bool(getattr(d, "Saved", True)), tools.Drawings.name(d)
    path, saved, name = EXECUTOR.submit(where).result()
    if not path:
        raise ValueError("Bản vẽ chưa được lưu thành file. Lưu bản vẽ (SAVE) rồi kiểm tra lại.")
    r = api.check_file(path, v, os.path.join(os.path.expanduser("~"), "Steve-CAD-AI", "Excel"), module, standard, cad_to_dxf)
    r["unsaved"] = not saved
    r["_drawing"] = name
    return r


KCS_FN = {}


# marks of the checks: each one a block KCS-<n> on its own layer KCS-*, all in one undo step. kcs_unmark removes the
# block references on the KCS-* layers and the KCS-* block definitions, nothing else.
MARK_LAYERS = {"bad": ("KCS-KHONG-DAT", 1), "reason": ("KCS-CAN-GIAI-TRINH", 30), "advice": ("KCS-KHUYEN-NGHI", 2),
               "data": ("KCS-SO-LIEU", 6), "nodata": ("KCS-THIEU-DU-LIEU", 8), "table": ("KCS-BANG-KET-QUA", 7)}


def _kcs_clear(d, table=False, marks=True):
    """Remove the marks and / or the table: objects on the KCS-* layers, then the KCS-* blocks nobody uses."""
    sp, found = tools.ms(d), []
    for i in range(sp.Count):   # collect first: deleting while walking the list skips objects
        try:
            e = sp.Item(i)
            lay = str(e.Layer).upper()
            if lay.startswith("KCS-") and ((lay == "KCS-BANG-KET-QUA") == table or (table and marks)):
                found.append(e)
        except Exception:
            pass
    n = 0
    for e in found:
        try:
            e.Delete()
            n += 1
        except Exception:
            pass
    names = []
    for i in range(d.Blocks.Count):
        try:
            nm = str(d.Blocks.Item(i).Name)
            if nm.upper().startswith("KCS-"):
                names.append(nm)
        except Exception:
            pass
    for nm in names:
        try:
            d.Blocks.Item(nm).Delete()   # refused while still inserted somewhere: then it stays
        except Exception:
            pass
    return n


def _kcs_setup(d):
    try:
        st = d.TextStyles.Item("KCS")
    except Exception:
        st = d.TextStyles.Add("KCS")
    try:
        st.SetFont("Arial", False, False, 0, 0)   # Vietnamese needs a TrueType font
    except Exception:
        pass
    for name, color in MARK_LAYERS.values():
        tools.ensure_layer(d, name)
        d.Layers.Item(name).Color = color


def _kcs_block(d, m, prefix):
    """One mark (or the table) as one block, inserted where it belongs: lines, filled arrowheads, notes."""
    layer = MARK_LAYERS.get(m.get("kind"), MARK_LAYERS["bad"])[0]
    bx, by = [float(v) for v in (m.get("base") or [0, 0])[:2]]
    k = 1
    while True:
        name = f"{prefix}{k}"
        try:
            d.Blocks.Item(name)
            k += 1
        except Exception:
            break
    blk = d.Blocks.Add(tools.vpt([bx, by, 0.0]), name)
    # the block's contents sit at their own coordinates; inserting the block at its base puts them back in place
    for pts in m.get("lines", []):
        if len(pts) >= 2:
            blk.AddLightWeightPolyline(tools.vdoubles([float(c) for p in pts for c in p[:2]]))
    for tri in m.get("arrows", []):
        a, b, c = [[float(v) for v in p[:2]] + [0.0] for p in tri[:3]]
        blk.AddSolid(tools.vpt(a), tools.vpt(b), tools.vpt(c), tools.vpt(c))
    for t in m.get("texts", []):
        at = tools.vpt([float(v) for v in t["pos"][:2]])
        e = blk.AddMText(at, 0.0, str(t["text"]))
        e.Height = float(t.get("h", 2.0))
        try:
            e.StyleName = "KCS"
        except Exception:
            pass
        try:
            e.AttachmentPoint = int(t.get("attach", 7))
            e.InsertionPoint = at
        except Exception:
            pass
        e.Rotation = math.radians(float(t.get("rot", 0)))
    for i in range(blk.Count):   # contents ByLayer / ByBlock: the block reference's layer decides the colour
        try:
            blk.Item(i).Layer = "0"
            blk.Item(i).Color = 0
        except Exception:
            pass
    ref = tools.ms(d).InsertBlock(tools.vpt([bx, by, 0.0]), name, 1.0, 1.0, 1.0, 0.0)
    ref.Layer = layer
    return ref


def kcs_mark(marks, _drawing=None):
    """marks (worked out by the KCS package), in drawing units, each one block:
    [{kind, base: [x, y], lines: [[[x, y], ...]], arrows: [[[x, y] * 3]], texts: [{pos, h, rot, text, attach}]}]
    Earlier marks are replaced (the table stays). One UNDO step."""
    def go():
        with tools.editing() as d:
            removed = _kcs_clear(d, table=False)
            _kcs_setup(d)
            for m in marks:
                _kcs_block(d, m, "KCS-DAU-")
            return dict(marked=len(marks), removed=removed)
    return EXECUTOR.submit(go).result()


def kcs_table(table, _drawing=None):
    """The table of results as one block (replaces an earlier one). One UNDO step."""
    def go():
        with tools.editing() as d:
            removed = _kcs_clear(d, table=True, marks=False)
            _kcs_setup(d)
            _kcs_block(d, dict(table, kind="table"), "KCS-BANG-")
            return dict(placed=True, removed=removed, at=table.get("base"))
    return EXECUTOR.submit(go).result()


def kcs_unmark(_drawing=None):
    """Remove every mark and the table."""
    def go():
        with tools.editing() as d:
            return dict(removed=_kcs_clear(d, table=True, marks=True))
    return EXECUTOR.submit(go).result()


def kcs_zoom(box, _drawing=None):
    def go():
        d = tools.doc()
        tools.need_active(d, "zoom")
        x0, y0, x1, y1 = [float(v) for v in box]
        m = max(x1 - x0, y1 - y0, 1.0) * 0.25
        tools.C.conn.app().ZoomWindow(tools.vpt([x0 - m, y0 - m]), tools.vpt([x1 + m, y1 + m]))
        return dict(ok=True)
    return EXECUTOR.submit(go).result()


WRITE = {"map_layers", "set_attributes", "set_props", "delete", "delete_duplicates", "export_xlsx", "export_ifc", "tag_solids"}


def pick(pid):
    """Connect to the CAD window of this process, never to another one that happens to be open."""
    import win32process
    for c in tools.C.conn.running():
        if win32process.GetWindowThreadProcessId(int(c["app"].HWND))[1] == pid:
            tools.C.conn._app = c["app"]
            return True
    return False


def kcs_feedback(item, verdict, comment="", standard="", option="", _drawing=None):
    """The engineer's verdict on one result (đúng / sai), kept on this PC in Steve-CAD-AI\\KCS\\phan-hoi.jsonl.
    Nothing is sent: the person sends the file to Steve when they choose to."""
    if verdict not in ("dung", "sai"):
        raise ValueError("Phản hồi không hợp lệ.")
    keep = {k: str(item.get(k, ""))[:300] for k in ("group", "route", "where", "criterion", "design", "required", "clause", "level", "status")}
    row = dict(time=__import__("time").strftime("%Y-%m-%d %H:%M:%S"), verdict=verdict, comment=str(comment)[:1000],
               standard=str(standard)[:60], option=str(option)[:60], drawing=os.path.basename(str(_drawing or "")), **keep)
    folder = os.path.join(os.path.expanduser("~"), "Steve-CAD-AI", "KCS")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, "phan-hoi.jsonl")
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(row, ensure_ascii=False) + "\n")
    return dict(saved=path)


KCS = KCS | {"kcs_feedback"}
KCS_FN.update(kcs_table=kcs_table, kcs_check=kcs_check, kcs_catalog=kcs_catalog, kcs_mark=kcs_mark, kcs_unmark=kcs_unmark, kcs_zoom=kcs_zoom, kcs_feedback=kcs_feedback)


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
            if name not in READ | WRITE | KCS:
                raise ValueError("Không hỗ trợ.")
            if not EXECUTOR.submit(pick, a.pid).result():
                raise ValueError("Không nối được với CAD. CAD đang bận, hoặc chưa mở bản vẽ nào.")
            if name in KCS:
                if name in ("kcs_mark", "kcs_unmark", "kcs_zoom", "kcs_table"):   # the boxes belong to the drawing that was checked
                    now = EXECUTOR.submit(lambda: tools.Drawings.name(tools.doc())).result()
                    if args.get("_drawing") != now:
                        raise ValueError("Bản vẽ đang mở đã đổi so với lúc kiểm tra. Kiểm tra lại rồi làm tiếp.")
                sys.stdout.write(json.dumps({"id": rid, "ok": True, "r": KCS_FN[name](**args)}, ensure_ascii=False, default=str) + "\n")
                sys.stdout.flush()
                continue
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
