"""Drawing helpers: target drawing (pinning), undo grouping, geometry variants, entity descriptions."""
from __future__ import annotations

import contextlib
import math
import os
import re

import pythoncom
import pywintypes
import win32com.client

from .com import busy_retry
from .vntext import decode

ACI_NAMES = {"byblock": 0, "red": 1, "yellow": 2, "green": 3, "cyan": 4, "blue": 5, "magenta": 6,
             "white": 7, "black": 7, "gray": 8, "grey": 8, "bylayer": 256,
             "do": 1, "vang": 2, "xanhla": 3, "xanhlam": 5, "trang": 7, "xam": 8}


class UserError(Exception):
    """Error whose message is shown to the AI as is (Vietnamese)."""


# ---------- variants ----------
def vpt(p) -> win32com.client.VARIANT:
    if p is None or len(p) < 2:
        raise UserError("Điểm phải có dạng [x, y] hoặc [x, y, z].")
    x, y, z = (list(map(float, p)) + [0.0])[:3]
    return win32com.client.VARIANT(pythoncom.VT_ARRAY | pythoncom.VT_R8, (x, y, z))


def vdoubles(xs) -> win32com.client.VARIANT:
    return win32com.client.VARIANT(pythoncom.VT_ARRAY | pythoncom.VT_R8, tuple(float(x) for x in xs))


def vobjects(objs) -> win32com.client.VARIANT:
    return win32com.client.VARIANT(pythoncom.VT_ARRAY | pythoncom.VT_DISPATCH, tuple(o._oleobj_ for o in objs))


def as_list(v):
    """COM returns a single object or a tuple of objects; normalise to a list of dispatch objects."""
    if v is None:
        return []
    if isinstance(v, (list, tuple)):
        return [win32com.client.dynamic.Dispatch(x) if not hasattr(x, "_oleobj_") else x for x in v]
    return [v]


def color_index(c) -> int | None:
    if c is None or c == "":
        return None
    if isinstance(c, int):
        if not 0 <= c <= 256:
            raise UserError("Màu ACI phải từ 0 đến 256 (256 = ByLayer).")
        return c
    s = str(c).strip().lower().replace(" ", "")
    if s.isdigit():
        return color_index(int(s))
    if s in ACI_NAMES:
        return ACI_NAMES[s]
    raise UserError(f"Không hiểu màu '{c}'. Dùng số ACI 0-256 hoặc red/yellow/green/cyan/blue/magenta/white/bylayer.")


def r3(v, nd=4):
    if v is None:
        return None
    if isinstance(v, (tuple, list)):
        return [round(float(x), nd) for x in v]
    return round(float(v), nd)


def g(o, name, default=None):
    try:
        return busy_retry(getattr, o, name)
    except Exception:
        return default


def etype(e) -> str:
    n = g(e, "ObjectName", "") or ""
    return re.sub(r"^(AcDb|ZcDb|Ac|Zc)", "", n) or "Unknown"


# ---------- target drawing ----------
class Drawings:
    """Which drawing the tools work on. Default: the active drawing. use_drawing() pins one, so switching tabs
    in the CAD never makes the AI draw into the wrong file. STEVECAD_PIN_FILE (written by the in-CAD chat) wins."""

    def __init__(self, conn):
        self.conn = conn
        self.pinned: str | None = None

    @staticmethod
    def name(d) -> str:
        return g(d, "FullName") or g(d, "Name") or "?"

    def all(self):
        docs = self.conn.app().Documents
        return [docs.Item(i) for i in range(docs.Count)]

    def _pin(self) -> str | None:
        f = os.environ.get("STEVECAD_PIN_FILE")
        if f:
            try:
                with open(f, encoding="utf-8-sig") as fh:
                    return fh.read().strip() or None
            except OSError:
                return None
        return self.pinned

    def find(self, key: str):
        docs = self.all()
        for d in docs:
            if self.name(d).lower() == key.lower():
                return d
        short = [d for d in docs if (g(d, "Name") or "").lower() == os.path.basename(key).lower()]
        if len(short) == 1:
            return short[0]
        if len(short) > 1:
            raise UserError(f"Có {len(short)} bản vẽ cùng tên '{key}'. Dùng đường dẫn đầy đủ (xem list_drawings).")
        return None

    def target(self):
        app = self.conn.app()
        pin = self._pin()
        if pin:
            d = self.find(pin)
            if d is None:
                raise UserError(f"Bản vẽ đang ghim '{pin}' đã đóng. Gọi use_drawing để chọn bản vẽ khác "
                                "(hoặc use_drawing(\"\") để dùng bản vẽ đang mở).")
            return d
        try:
            return app.ActiveDocument
        except pywintypes.com_error as e:
            raise UserError(f"{self.conn.label} chưa mở bản vẽ nào. Mở hoặc tạo một bản vẽ rồi thử lại.") from e

    def is_active(self, d) -> bool:
        try:
            return self.name(self.conn.app().ActiveDocument) == self.name(d)
        except pywintypes.com_error:
            return False


def cmd_active(doc) -> bool:
    try:
        return bool(doc.GetVariable("CMDACTIVE"))
    except pywintypes.com_error:
        return False


def run_cmd(doc, cmd: str, timeout: float = 20.0) -> bool:
    """Send a command line string and wait until the CAD is idle again (SendCommand returns early).
    Returns False if it is still running after timeout."""
    import time
    doc.SendCommand(cmd)
    t0 = time.monotonic()
    time.sleep(0.05)
    while time.monotonic() - t0 < timeout:
        if not cmd_active(doc):
            return True
        time.sleep(0.1)
    return False


@contextlib.contextmanager
def undo_group(doc):
    """Everything inside becomes ONE undo step. Skipped (tool still runs) when the user is mid-command,
    undo is off, or a group is already open."""
    opened = False
    try:
        ctl = int(doc.GetVariable("UNDOCTL"))
        if not cmd_active(doc) and (ctl & 1) and not (ctl & 8):
            doc.StartUndoMark()
            opened = True
    except pywintypes.com_error:
        opened = False
    try:
        yield
    finally:
        if opened:
            with contextlib.suppress(pywintypes.com_error):
                doc.EndUndoMark()


def by_handle(doc, h: str):
    try:
        return doc.HandleToObject(str(h).strip())
    except pywintypes.com_error:
        raise UserError(f"Không có đối tượng handle '{h}' trong bản vẽ {Drawings.name(doc)}.") from None


def ensure_layer(doc, name: str | None):
    if not name:
        return
    try:
        doc.Layers.Item(name)
    except pywintypes.com_error:
        doc.Layers.Add(name)


def apply_common(e, layer=None, color=None, doc=None):
    if layer:
        if doc is not None:
            ensure_layer(doc, layer)
        e.Layer = layer
    ci = color_index(color)
    if ci is not None:
        e.Color = ci


# ---------- geometry ----------
def length_of(e):
    t = etype(e)
    if t == "Arc":
        return g(e, "ArcLength")
    if t == "Circle":
        return g(e, "Circumference")
    if t in ("Line", "Polyline", "2dPolyline", "3dPolyline"):
        return g(e, "Length")
    return None


def area_of(e):
    t = etype(e)
    if t in ("Polyline", "2dPolyline") and not g(e, "Closed", False):
        return None
    if t in ("Polyline", "2dPolyline", "Circle", "Ellipse", "Hatch", "Region"):
        return g(e, "Area")
    return None


def poly_points(e) -> list[list[float]]:
    t = etype(e)
    c = list(g(e, "Coordinates", ()) or ())
    step = 2 if t == "Polyline" else 3
    return [[float(c[i]), float(c[i + 1])] + ([float(c[i + 2])] if step == 3 else []) for i in range(0, len(c) - step + 1, step)]


_font_cache: dict = {}


def style_font(e) -> str:
    """Font file of the text style used by a Text/MText (cached) - tells TCVN3 / VNI apart."""
    st = g(e, "StyleName") or ""
    if st in _font_cache:
        return _font_cache[st]
    f = ""
    try:
        ts = e.Document.TextStyles.Item(st)
        f = (g(ts, "fontFile") or "") + " " + (g(ts, "BigFontFile") or "")
        try:
            face = ts.GetFont()
            f += " " + str(face[0])
        except Exception:
            pass
    except Exception:
        pass
    _font_cache[st] = f
    return f


def text_of(e) -> dict:
    raw = g(e, "TextString") or ""
    uni = decode(raw, style_font(e))
    return {"text": uni} if uni == raw else {"text": uni, "text_raw": raw}


def describe(e, detail: bool = False) -> dict:
    t = etype(e)
    d = {"handle": g(e, "Handle"), "type": t, "layer": g(e, "Layer")}
    col = g(e, "Color")
    if col not in (None, 256):
        d["color"] = col
    if t == "Line":
        d.update(start=r3(g(e, "StartPoint")), end=r3(g(e, "EndPoint")), length=r3(g(e, "Length")))
    elif t == "Circle":
        d.update(center=r3(g(e, "Center")), radius=r3(g(e, "Radius")))
    elif t == "Arc":
        d.update(center=r3(g(e, "Center")), radius=r3(g(e, "Radius")),
                 start_deg=r3(math.degrees(g(e, "StartAngle", 0))), end_deg=r3(math.degrees(g(e, "EndAngle", 0))))
    elif t in ("Polyline", "2dPolyline", "3dPolyline"):
        pts = poly_points(e)
        d.update(closed=bool(g(e, "Closed", False)), vertices=len(pts), length=r3(g(e, "Length")))
        a = area_of(e)
        if a is not None:
            d["area"] = r3(a)
        d["points"] = [r3(p, 3) for p in (pts if detail else pts[:20])]
        if not detail and len(pts) > 20:
            d["points_truncated"] = True
    elif t in ("Text", "MText"):
        d.update(text_of(e))
        d.update(position=r3(g(e, "InsertionPoint")), height=r3(g(e, "Height")))
    elif t == "BlockReference":
        d.update(name=g(e, "EffectiveName") or g(e, "Name"), position=r3(g(e, "InsertionPoint")),
                 rotation_deg=r3(math.degrees(g(e, "Rotation", 0))), scale=r3(g(e, "XScaleFactor")))
        if detail and g(e, "HasAttributes"):
            try:
                d["attributes"] = {a.TagString: a.TextString for a in as_list(e.GetAttributes())}
            except pywintypes.com_error:
                pass
    elif t == "Ellipse":
        d.update(center=r3(g(e, "Center")), major_radius=r3(g(e, "MajorRadius")), minor_radius=r3(g(e, "MinorRadius")))
    elif t == "Point":
        d.update(position=r3(g(e, "Coordinates")))
    elif t == "Hatch":
        d.update(pattern=g(e, "PatternName"), area=r3(g(e, "Area")))
    elif "Dimension" in t:
        d.update(measurement=r3(g(e, "Measurement")))
        ov = g(e, "TextOverride")
        if ov:
            d["text_override"] = decode(ov)
        tp = g(e, "TextPosition")
        if tp is not None:
            d["text_position"] = r3(tp, 1)
    elif t in ("3dSolid", "Region"):
        d.update(volume=r3(g(e, "Volume")) if t == "3dSolid" else None, area=r3(g(e, "Area")),
                 centroid=r3(g(e, "Centroid")))
        bb = bbox(e)
        if bb:
            d["bbox"] = bb
    if detail:
        for k, prop in (("linetype", "Linetype"), ("lineweight", "Lineweight")):
            v = g(e, prop)
            if v is not None:
                d[k] = v
    return d


def bbox(e):
    try:
        lo, hi = e.GetBoundingBox()
        return {"min": r3(lo), "max": r3(hi)}
    except Exception:
        return None


def geom_key(e, nd=3):
    """Signature used to find duplicates: same type, layer and geometry (rounded)."""
    t = etype(e)
    lay = g(e, "Layer")
    if t == "Line":
        a, b = tuple(r3(g(e, "StartPoint"), nd)), tuple(r3(g(e, "EndPoint"), nd))
        return (t, lay) + tuple(sorted([a, b]))
    if t in ("Circle",):
        return (t, lay, tuple(r3(g(e, "Center"), nd)), r3(g(e, "Radius"), nd))
    if t == "Arc":
        return (t, lay, tuple(r3(g(e, "Center"), nd)), r3(g(e, "Radius"), nd), r3(g(e, "StartAngle"), 4), r3(g(e, "EndAngle"), 4))
    if t in ("Polyline", "2dPolyline", "3dPolyline"):
        pts = tuple(tuple(r3(p, nd)) for p in poly_points(e))
        return (t, lay, bool(g(e, "Closed", False)), min(pts, pts[::-1]))
    if t in ("Text", "MText"):
        return (t, lay, g(e, "TextString"), tuple(r3(g(e, "InsertionPoint"), nd)))
    if t == "BlockReference":
        return (t, lay, g(e, "Name"), tuple(r3(g(e, "InsertionPoint"), nd)), r3(g(e, "Rotation"), 4))
    if t == "Point":
        return (t, lay, tuple(r3(g(e, "Coordinates"), nd)))
    return None


# ---------- iterating entities ----------
_ss_counter = [0]


DXF = {"line": "LINE", "circle": "CIRCLE", "arc": "ARC", "polyline": "LWPOLYLINE", "lwpolyline": "LWPOLYLINE",
       "2dpolyline": "POLYLINE", "3dpolyline": "POLYLINE", "text": "TEXT", "mtext": "MTEXT", "blockreference": "INSERT",
       "block": "INSERT", "insert": "INSERT", "hatch": "HATCH", "ellipse": "ELLIPSE", "point": "POINT", "spline": "SPLINE",
       "dimension": "DIMENSION", "leader": "LEADER", "mleader": "MULTILEADER", "solid": "SOLID", "region": "REGION",
       "3dsolid": "3DSOLID", "3dface": "3DFACE", "attributedefinition": "ATTDEF", "table": "ACAD_TABLE"}


def _wild_escape(s: str) -> str:
    return re.sub(r"([#@.*?~\[\]`,-])", r"`\1", s)


def select(doc, types: list[str] | None = None, layer: str | None = None, window=None, crossing: bool = False):
    """Model-space objects matching type/layer (and optionally lying in window [x1,y1,x2,y2]), filtered INSIDE
    the CAD (one call) - returns a selection set. Caller must .Delete() it."""
    codes, vals = [67], [0]
    if types:
        names = []
        for t in types:
            k = t.strip().lower().replace("acdb", "")
            names.append(DXF.get(k, t.strip().upper()))
        codes.append(0)
        vals.append(",".join(sorted(set(names))))
    if layer:
        codes.append(8)
        vals.append(_wild_escape(layer))
    ss = new_selection_set(doc)
    ft = win32com.client.VARIANT(pythoncom.VT_ARRAY | pythoncom.VT_I2, tuple(codes))
    fd = win32com.client.VARIANT(pythoncom.VT_ARRAY | pythoncom.VT_VARIANT, tuple(vals))
    empty = win32com.client.VARIANT(pythoncom.VT_EMPTY, None)  # ZWCAD ignores the filter with pythoncom.Missing
    if not window:
        ss.Select(5, empty, empty, ft, fd)
        return ss
    x1, y1, x2, y2 = map(float, window)
    lo, hi = (min(x1, x2), min(y1, y2)), (max(x1, x2), max(y1, y2))
    try:
        active = doc.Application.ActiveDocument.FullName == doc.FullName and doc.Name == doc.Application.ActiveDocument.Name
    except pywintypes.com_error:
        active = False
    if active and not cmd_active(doc):
        # window selection only sees what is on screen: look at the window from the top, select, restore the view
        with contextlib.suppress(pywintypes.com_error):
            if doc.ActiveSpace != 1:  # on a Layout tab -> model space
                doc.ActiveSpace = 1
        vp = doc.ActiveViewport
        saved = {k: g(vp, k) for k in ("Direction", "Target", "Center", "Height")}
        aspect = (g(vp, "Width") or 1.0) / (saved["Height"] or 1.0)
        try:
            vp.Direction = vpt([0, 0, 1])
            vp.Target = vpt([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, 0])
            vp.Center = win32com.client.VARIANT(pythoncom.VT_ARRAY | pythoncom.VT_R8, (0.0, 0.0))
            vp.Height = max(hi[1] - lo[1], (hi[0] - lo[0]) / max(aspect, 1e-6)) * 1.05
            doc.ActiveViewport = vp
            ss.Select(1 if crossing else 0, vpt([lo[0], lo[1], 0]), vpt([hi[0], hi[1], 0]), ft, fd)
        finally:
            with contextlib.suppress(Exception):
                for k, v in saved.items():
                    if v is not None:
                        setattr(vp, k, vpt(v) if k in ("Direction", "Target") else (
                            win32com.client.VARIANT(pythoncom.VT_ARRAY | pythoncom.VT_R8, tuple(v)[:2]) if k == "Center" else v))
                doc.ActiveViewport = vp
        return ss
    # drawing not on screen: filter in the CAD by type/layer, then by bounding box here (slower)
    ss.Select(5, empty, empty, ft, fd)
    keep = []
    for i in range(ss.Count):
        e = ss.Item(i)
        try:
            a, b = e.GetBoundingBox()
        except pywintypes.com_error:
            continue
        inside = a[0] >= lo[0] and a[1] >= lo[1] and b[0] <= hi[0] and b[1] <= hi[1]
        touch = not (b[0] < lo[0] or a[0] > hi[0] or b[1] < lo[1] or a[1] > hi[1])
        if inside or (crossing and touch):
            keep.append(e)
    with contextlib.suppress(pywintypes.com_error):
        ss.Delete()
    return _ListSet(keep)


class _ListSet:
    """Selection-set look-alike over a Python list."""

    def __init__(self, items):
        self._items = items
        self.Count = len(items)

    def Item(self, i):
        return self._items[i]

    def Delete(self):
        self._items = []


def count_matching(doc, types=None, layer=None) -> int:
    ss = select(doc, types, layer)
    try:
        return ss.Count
    finally:
        with contextlib.suppress(pywintypes.com_error):
            ss.Delete()


def iter_space(doc, types: list[str] | None = None, layer: str | None = None, limit: int | None = None, window=None):
    """Yield model-space entities filtered by type (Line, Circle, Polyline, BlockReference...) and layer.
    The CAD does the filtering; only matching objects cross the (slow) COM boundary."""
    ss = select(doc, types, layer, window)
    try:
        n = ss.Count if not limit else min(ss.Count, limit)
        for i in range(n):
            yield ss.Item(i)
    finally:
        with contextlib.suppress(pywintypes.com_error):
            ss.Delete()


def selection_handles(doc) -> list:
    """Objects the user has selected (gripped) in the CAD right now."""
    try:
        ss = doc.PickfirstSelectionSet
        return [ss.Item(i) for i in range(ss.Count)]
    except pywintypes.com_error:
        return []


def new_selection_set(doc):
    _ss_counter[0] += 1
    name = f"STEVEAI_{os.getpid()}_{_ss_counter[0]}"
    sets = doc.SelectionSets
    with contextlib.suppress(pywintypes.com_error):
        sets.Item(name).Delete()
    return sets.Add(name)
