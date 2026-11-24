"""MCP tools of Steve CAD MCP. Every tool runs on the single CAD (STA) thread."""
from __future__ import annotations

import asyncio
import contextlib
import functools
import io
import math
import os
import traceback
from typing import Annotated

import pywintypes
from mcp.server.fastmcp import FastMCP, Image
from mcp.server.fastmcp.exceptions import ToolError
from mcp.types import ToolAnnotations
from pydantic import Field

from . import __version__
from .com import EXECUTOR, CadNotRunning, Connection, blocking_dialog, com_message
from .drawing import (Drawings, UserError, apply_common, area_of, as_list, by_handle, cmd_active, color_index,
                      count_matching, describe, ensure_layer, run_cmd, etype, g, geom_key, iter_space, length_of, new_selection_set,
                      poly_points, r3, select, selection_handles, undo_group, vdoubles, vobjects, vpt)

Point = Annotated[list[float], Field(min_length=2, max_length=3, description="[x, y] or [x, y, z]")]
Handles = Annotated[list[str], Field(description="Entity handles (from list_entities / get_selection)")]
Layer = Annotated[str, Field(description="Layer name; created if missing. Empty = current layer")]
Color = Annotated[int | str | None, Field(description="ACI 0-256 or red/yellow/green/cyan/blue/magenta/white/bylayer")]

INSTRUCTIONS = """Điều khiển {cad} đang mở trên máy người dùng (Steve CAD MCP).
- Luôn đọc dữ liệu thật bằng tool (info, list_layers, list_entities, get_selection) trước khi trả lời về bản vẽ.
- "Các đối tượng này/đang chọn" = get_selection. Góc tính bằng độ. Toạ độ theo đơn vị bản vẽ (xem info.units).
- Mỗi lần gọi tool sửa bản vẽ là MỘT bước UNDO. Sau khi sửa, nhắc người dùng có thể gõ UNDO.
- Xoá, lưu, mở bản vẽ: hỏi người dùng trước. Nhiều việc lặp lại: ưu tiên tool nhận nhiều handle một lần.
- Muốn xem kết quả: screenshot.
- Việc nhiều bước (ví dụ dựng cống 3D từ bản vẽ DWG/PDF): gọi list_skills rồi get_skill và làm theo."""


class Ctx:
    conn: Connection
    drawings: Drawings
    allow_script = False


C = Ctx()
mcp: FastMCP


def build(cad: str, progid: str | None, allow_script: bool) -> FastMCP:
    global mcp
    C.conn = Connection(cad, progid)
    C.drawings = Drawings(C.conn)
    C.allow_script = allow_script
    mcp = FastMCP(f"steve-cad-{cad}", instructions=INSTRUCTIONS.format(cad=C.conn.label))
    for fn, kind in _REGISTRY:
        if fn.__name__ == "run_script" and not allow_script:
            continue
        ann = {
            "read": ToolAnnotations(readOnlyHint=True, destructiveHint=False, idempotentHint=True, openWorldHint=False),
            "write": ToolAnnotations(readOnlyHint=False, destructiveHint=False, openWorldHint=False),
            "destructive": ToolAnnotations(readOnlyHint=False, destructiveHint=True, openWorldHint=False),
        }[kind]
        mcp.tool(annotations=ann)(fn)
    from .skills import register_prompts
    register_prompts(mcp)
    return mcp


# ---------------------------------------------------------------- plumbing
_REGISTRY: list = []


def _check_blocked():
    dlg = blocking_dialog(C.conn.app())
    if dlg:
        raise UserError(f"{C.conn.label} đang bị chặn bởi hộp thoại \"{dlg}\". Nhờ người dùng xử lý/đóng hộp thoại "
                        "đó rồi thử lại.")


def _run(fn, kw):
    try:
        _check_blocked()
        return fn(**kw)
    except ToolError:
        raise
    except (UserError, CadNotRunning) as e:
        raise ToolError(str(e)) from None
    except pywintypes.com_error as e:
        raise ToolError(f"{C.conn.label} từ chối: {com_message(e)}") from None
    except Exception as e:
        raise ToolError(f"{type(e).__name__}: {e}") from None


def tool(kind: str = "read"):
    def deco(fn):
        @functools.wraps(fn)
        async def w(**kw):
            loop = asyncio.get_running_loop()
            return await loop.run_in_executor(EXECUTOR, _run, fn, kw)
        _REGISTRY.append((w, kind))
        return w
    return deco


def doc():
    return C.drawings.target()


@contextlib.contextmanager
def editing():
    """Target drawing, with all changes grouped into one undo step."""
    d = doc()
    with undo_group(d):
        yield d


def need_active(d, what="lệnh này"):
    if not C.drawings.is_active(d):
        raise UserError(f"Bản vẽ làm việc '{Drawings.name(d)}' không phải tab đang mở trong {C.conn.label}, "
                        f"nên không chạy được {what}. Mở tab đó hoặc dùng use_drawing.")
    if cmd_active(d):
        raise UserError(f"Người dùng đang dở một lệnh trong {C.conn.label}. Đợi xong lệnh hoặc nhờ họ bấm Esc.")
    ensure_model(d)


def need_active_doc(d):
    """Like need_active, for a document that was just activated (not the working drawing)."""
    if cmd_active(d):
        raise UserError(f"{C.conn.label} đang dở một lệnh. Nhờ người dùng bấm Esc rồi thử lại.")
    ensure_model(d)


def ensure_model(d):
    """Views, zoom and window selection work on model space: leave a Layout tab if the drawing opened on one."""
    try:
        if d.ActiveSpace != 1:  # acModelSpace
            d.ActiveSpace = 1
    except pywintypes.com_error:
        pass


def done(d, created=None, **extra):
    r = {"ok": True, "drawing": g(d, "Name")}
    if created is not None:
        r["handles"] = [g(e, "Handle") for e in created]
    r.update(extra)
    return r


def ms(d):
    return d.ModelSpace


def finish(d, e, layer="", color=None):
    apply_common(e, layer or None, color, d)
    return e


def entities(d, handles):
    if not handles:
        raise UserError("Chưa có handle nào. Dùng get_selection hoặc list_entities để lấy handle.")
    return [by_handle(d, h) for h in handles]


# ---------------------------------------------------------------- read
@tool()
def info() -> dict:
    """CAD product, working drawing, units, extents, current layer and object count. Call this first."""
    app = C.conn.app()
    d = doc()
    units = {0: "không đơn vị", 1: "inch", 2: "feet", 4: "mm", 5: "cm", 6: "m", 7: "km"}
    ins = d.GetVariable("INSUNITS")
    return {
        "cad": C.conn.label, "cad_version": g(app, "Version"), "server": f"steve-cad {__version__}",
        "drawing": Drawings.name(d), "pinned": bool(C.drawings._pin()), "active_tab": C.drawings.is_active(d),
        "saved": bool(g(d, "Saved", True)), "units": units.get(ins, f"INSUNITS={ins}"),
        "extents": {"min": r3(d.GetVariable("EXTMIN")), "max": r3(d.GetVariable("EXTMAX"))},
        "current_layer": g(g(d, "ActiveLayer"), "Name"), "modelspace_objects": d.ModelSpace.Count,
        "user_busy": cmd_active(d),
    }


@tool()
def use_cad(name: str = "") -> dict:
    """List the running CAD programs, or connect to one of them when several are open (e.g. AutoCAD 2024 and Civil 3D 2027).
    name: part of its name, version or window title, e.g. "2024" or "Civil 3D". Empty = only list."""
    cads = C.conn.running()
    if not cads:
        raise UserError(f"Không thấy {C.conn.label} đang mở.")
    if name:
        hit = [c for c in cads if name.lower() in f"{c['name']} {c['version']} {c['title']}".lower()]
        if len(hit) != 1:
            raise UserError(("Không có bản nào khớp" if not hit else "Nhiều bản cùng khớp") + f" '{name}'. Đang mở: " + "; ".join(c["title"] for c in cads))
        C.conn._app = hit[0]["app"]
        C.drawings.pinned = None
    cur = int(C.conn.app().HWND)
    return {"running": [{"name": c["name"], "version": c["version"], "title": c["title"], "connected": int(c["app"].HWND) == cur} for c in cads]}


@tool()
def list_drawings() -> list[dict]:
    """Open drawings, which one is the active tab and which one the tools work on."""
    t = Drawings.name(doc()) if C.conn.app().Documents.Count else None
    act = Drawings.name(C.conn.app().ActiveDocument) if t else None
    return [{"name": g(x, "Name"), "path": g(x, "FullName") or None, "active_tab": Drawings.name(x) == act,
             "working": Drawings.name(x) == t, "saved": bool(g(x, "Saved", True))} for x in C.drawings.all()]


@tool()
def use_drawing(name: str = "", activate: bool = False) -> dict:
    """Pin the drawing the tools work on (name or full path from list_drawings), so switching tabs is safe.
    activate=True also brings that tab to the front (needed for zoom, views, commands).
    Empty name = follow whichever tab is active."""
    if not name:
        C.drawings.pinned = None
        return {"ok": True, "working": "tab đang mở"}
    d = C.drawings.find(name)
    if d is None:
        raise UserError(f"Không có bản vẽ '{name}' đang mở.")
    C.drawings.pinned = Drawings.name(d)
    if activate:
        d.Activate()
    return {"ok": True, "working": C.drawings.pinned, "active_tab": C.drawings.is_active(d)}


@tool()
def list_layers(count_objects: bool = True) -> list[dict]:
    """Layers with color, on/off, frozen, locked, linetype and (optionally) number of model-space objects."""
    d = doc()
    cur = g(g(d, "ActiveLayer"), "Name")
    out = []
    for i in range(d.Layers.Count):
        L = d.Layers.Item(i)
        n = L.Name
        row = {"name": n, "color": g(L, "Color"), "on": bool(g(L, "LayerOn", True)), "frozen": bool(g(L, "Freeze", False)),
               "locked": bool(g(L, "Lock", False)), "linetype": g(L, "Linetype")}
        if n == cur:
            row["current"] = True
        if count_objects:
            row["objects"] = count_matching(d, None, n)
        out.append(row)
    return out


@tool()
def list_entities(type: str = "", layer: str = "", window: list[float] | None = None, crossing: bool = False,
                  limit: int = 200, offset: int = 0) -> dict:
    """Model-space objects with key geometry. Filter by type (Line, Circle, Arc, Polyline, Text, MText,
    BlockReference, Hatch, Dimension, 3dSolid...; comma-separated), layer, and/or window [x1, y1, x2, y2]
    (objects fully inside; crossing=True also takes objects touching it) - use window to read one view of a sheet.
    Text from legacy Vietnamese fonts (TCVN3 .VnTime, VNI) is returned decoded to Unicode. Use offset to page."""
    d = doc()
    types = [t.strip() for t in type.split(",") if t.strip()] or None
    ss = select(d, types, layer or None, window, crossing)
    try:
        total = ss.Count
        rows = [describe(ss.Item(i)) for i in range(max(0, offset), min(total, max(0, offset) + max(1, limit)))]
    finally:
        with contextlib.suppress(pywintypes.com_error):
            ss.Delete()
    return {"drawing": g(d, "Name"), "total": total, "returned": len(rows), "offset": offset,
            "more": offset + len(rows) < total, "entities": rows}


@tool()
def get_entity(handles: Handles) -> list[dict]:
    """Full properties of objects (all points, block attributes, linetype...)."""
    d = doc()
    return [describe(e, detail=True) for e in entities(d, handles)]


@tool()
def get_selection() -> dict:
    """Objects the user has currently selected (gripped) in the CAD."""
    d = doc()
    sel = selection_handles(d)
    return {"drawing": g(d, "Name"), "count": len(sel), "entities": [describe(e) for e in sel[:500]]}


@tool()
def list_blocks(include_anonymous: bool = False) -> list[dict]:
    """Block definitions in the drawing (excluding model/paper space) with number of references in model space."""
    d = doc()
    refs: dict[str, int] = {}
    for e in iter_space(d, ["BlockReference"]):
        k = g(e, "EffectiveName") or g(e, "Name")
        refs[k] = refs.get(k, 0) + 1
    out = []
    for i in range(d.Blocks.Count):
        b = d.Blocks.Item(i)
        n = b.Name
        if g(b, "IsLayout") or (n.startswith("*") and not include_anonymous):
            continue
        out.append({"name": n, "objects": g(b, "Count"), "references": refs.get(n, 0), "xref": bool(g(b, "IsXRef", False))})
    return out


@tool()
def measure(handles: list[str] | None = None) -> dict:
    """Length (lines, arcs, circles, polylines) and area (closed shapes, hatches) of objects, with totals.
    No handles = the user's current selection."""
    d = doc()
    ents = entities(d, handles) if handles else selection_handles(d)
    if not ents:
        raise UserError("Chưa chọn đối tượng nào: chọn trong CAD hoặc truyền handles.")
    rows, tl, ta = [], 0.0, 0.0
    for e in ents:
        L, A = length_of(e), area_of(e)
        tl += L or 0
        ta += A or 0
        rows.append({"handle": g(e, "Handle"), "type": etype(e), "length": r3(L), "area": r3(A)})
    return {"count": len(rows), "total_length": r3(tl), "total_area": r3(ta), "items": rows}


@tool()
def count_blocks(layer: str = "") -> dict:
    """How many times each block is inserted in model space (dynamic blocks counted by their real name)."""
    d = doc()
    c: dict[str, int] = {}
    for e in iter_space(d, ["BlockReference"], layer or None):
        k = g(e, "EffectiveName") or g(e, "Name")
        c[k] = c.get(k, 0) + 1
    return {"total": sum(c.values()), "blocks": dict(sorted(c.items(), key=lambda kv: -kv[1]))}


@tool("destructive")
def find_duplicates(layer: str = "", type: str = "", delete: bool = False, tolerance_decimals: int = 3,
                    max_objects: int = 3000) -> dict:
    """Find objects lying exactly on top of each other (same type, layer and geometry), optionally filtered by
    layer/type. Scanning is ~10 ms per object in ZWCAD, so filter big drawings. delete=True removes the extra
    copies, keeping one of each (ask the user first)."""
    d = doc()
    types = [t.strip() for t in type.split(",") if t.strip()] or None
    total = count_matching(d, types, layer or None)
    groups: dict = {}
    for e in iter_space(d, types, layer or None, limit=max_objects):
        k = geom_key(e, tolerance_decimals)
        if k is not None:
            groups.setdefault(k, []).append(e)
    def _h(x):
        try:
            return int(g(x, "Handle") or "0", 16)
        except ValueError:
            return 0
    dup = [sorted(v, key=_h) for v in groups.values() if len(v) > 1]  # keep the oldest object of each group
    res = {"scanned": min(total, max_objects), "total": total, "groups": len(dup), "extra_copies": sum(len(v) - 1 for v in dup),
           "examples": [{"type": etype(v[0]), "layer": g(v[0], "Layer"), "handles": [g(x, "Handle") for x in v]} for v in dup[:30]]}
    if delete and dup:
        with undo_group(d):
            for v in dup:
                for x in v[1:]:
                    x.Delete()
        res["deleted"] = res["extra_copies"]
    return res


@tool()
def screenshot(zoom_extents: bool = False) -> Image:
    """Picture of the CAD window, to check visually what was drawn (works even if the window is covered)."""
    import ctypes

    import win32gui
    import win32ui
    from PIL import Image as PILImage
    try:  # real pixel sizes on scaled displays (125%, 150%...), otherwise the capture is cropped
        ctypes.windll.user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
    except Exception:
        with contextlib.suppress(Exception):
            ctypes.windll.user32.SetProcessDPIAware()
    d = doc()
    app = C.conn.app()
    if zoom_extents and C.drawings.is_active(d):
        app.ZoomExtents()
    # let the CAD finish redrawing (GPU views) so the capture is not a stale frame
    import time
    with contextlib.suppress(Exception):
        app.Update()
    time.sleep(0.6)
    hwnd = win32gui.GetAncestor(int(app.HWND), 2)  # GA_ROOT: the main frame
    if win32gui.IsIconic(hwnd):
        raise UserError(f"Cửa sổ {C.conn.label} đang thu nhỏ (minimize) nên không chụp được. "
                        f"Nhờ người dùng mở lại cửa sổ {C.conn.label} rồi thử lại.")
    # measure in the CAD's own DPI context: PrintWindow draws at that size (a system-aware CAD on a monitor with another scale)
    u32 = ctypes.windll.user32
    old = None
    with contextlib.suppress(Exception):
        u32.GetWindowDpiAwarenessContext.restype = u32.SetThreadDpiAwarenessContext.restype = ctypes.c_void_p
        u32.GetWindowDpiAwarenessContext.argtypes = u32.SetThreadDpiAwarenessContext.argtypes = [ctypes.c_void_p]
        old = u32.SetThreadDpiAwarenessContext(u32.GetWindowDpiAwarenessContext(hwnd))
    l, t, r, b = win32gui.GetWindowRect(hwnd)
    w, h = r - l, b - t
    wdc = win32gui.GetWindowDC(hwnd)
    src = win32ui.CreateDCFromHandle(wdc)
    mem = src.CreateCompatibleDC()
    bmp = win32ui.CreateBitmap()
    bmp.CreateCompatibleBitmap(src, w, h)
    mem.SelectObject(bmp)
    try:
        ctypes.windll.user32.PrintWindow(hwnd, mem.GetSafeHdc(), 2)
        img = PILImage.frombuffer("RGB", (w, h), bmp.GetBitmapBits(True), "raw", "BGRX", 0, 1)
    finally:
        win32gui.DeleteObject(bmp.GetHandle())
        mem.DeleteDC()
        src.DeleteDC()
        win32gui.ReleaseDC(hwnd, wdc)
        if old:
            u32.SetThreadDpiAwarenessContext(old)
    img.thumbnail((1400, 1400))
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=80)
    return Image(data=buf.getvalue(), format="jpeg")


# ---------------------------------------------------------------- draw
@tool("write")
def line(points: list[Point], layer: Layer = "", color: Color = None) -> dict:
    """Separate line segments through consecutive points (2 points = 1 line)."""
    if len(points) < 2:
        raise UserError("Cần ít nhất 2 điểm.")
    with editing() as d:
        out = [finish(d, ms(d).AddLine(vpt(a), vpt(b)), layer, color) for a, b in zip(points, points[1:])]
        return done(d, out)


@tool("write")
def polyline(points: list[Point], closed: bool = False, layer: Layer = "", color: Color = None) -> dict:
    """One 2D polyline (LWPOLYLINE) through the points. closed=True for a closed outline."""
    if len(points) < 2:
        raise UserError("Cần ít nhất 2 điểm.")
    with editing() as d:
        flat = [c for p in points for c in (float(p[0]), float(p[1]))]
        e = ms(d).AddLightWeightPolyline(vdoubles(flat))
        if closed:
            e.Closed = True
        return done(d, [finish(d, e, layer, color)])


@tool("write")
def polyline3d(points: list[Point], closed: bool = False, layer: Layer = "", color: Color = None) -> dict:
    """3D polyline through [x, y, z] points (routes, profiles, terrain lines)."""
    if len(points) < 2:
        raise UserError("Cần ít nhất 2 điểm.")
    with editing() as d:
        flat = [c for p in points for c in (list(map(float, p)) + [0.0])[:3]]
        e = ms(d).Add3DPoly(vdoubles(flat))
        if closed:
            e.Closed = True
        return done(d, [finish(d, e, layer, color)])


@tool("write")
def rectangle(corner1: Point, corner2: Point, layer: Layer = "", color: Color = None) -> dict:
    """Closed rectangle polyline from two opposite corners."""
    (x1, y1), (x2, y2) = corner1[:2], corner2[:2]
    with editing() as d:
        e = ms(d).AddLightWeightPolyline(vdoubles([x1, y1, x2, y1, x2, y2, x1, y2]))
        e.Closed = True
        return done(d, [finish(d, e, layer, color)])


@tool("write")
def circle(center: Point, radius: float, layer: Layer = "", color: Color = None) -> dict:
    """Circle."""
    with editing() as d:
        return done(d, [finish(d, ms(d).AddCircle(vpt(center), float(radius)), layer, color)])


@tool("write")
def arc(center: Point, radius: float, start_deg: float, end_deg: float, layer: Layer = "", color: Color = None) -> dict:
    """Arc, counter-clockwise from start_deg to end_deg."""
    with editing() as d:
        e = ms(d).AddArc(vpt(center), float(radius), math.radians(start_deg), math.radians(end_deg))
        return done(d, [finish(d, e, layer, color)])


@tool("write")
def ellipse(center: Point, major_radius: float, minor_radius: float, rotation_deg: float = 0,
            layer: Layer = "", color: Color = None) -> dict:
    """Ellipse; rotation_deg = direction of the major axis."""
    if minor_radius > major_radius:
        major_radius, minor_radius, rotation_deg = minor_radius, major_radius, rotation_deg + 90
    a = math.radians(rotation_deg)
    with editing() as d:
        e = ms(d).AddEllipse(vpt(center), vpt([major_radius * math.cos(a), major_radius * math.sin(a)]),
                             float(minor_radius) / float(major_radius))
        return done(d, [finish(d, e, layer, color)])


@tool("write")
def text(position: Point, value: str, height: float = 2.5, rotation_deg: float = 0,
         layer: Layer = "", color: Color = None) -> dict:
    """Single-line text."""
    with editing() as d:
        e = ms(d).AddText(value, vpt(position), float(height))
        if rotation_deg:
            e.Rotation = math.radians(rotation_deg)
        return done(d, [finish(d, e, layer, color)])


@tool("write")
def mtext(position: Point, value: str, width: float = 0, height: float = 2.5,
          layer: Layer = "", color: Color = None) -> dict:
    """Multi-line text (top-left at position). Use \\P for a new paragraph. width 0 = no wrapping."""
    with editing() as d:
        e = ms(d).AddMText(vpt(position), float(width), value)
        e.Height = float(height)
        return done(d, [finish(d, e, layer, color)])


@tool("write")
def hatch(boundary_handles: Handles, pattern: str = "ANSI31", scale: float = 1, angle_deg: float = 0,
          layer: Layer = "", color: Color = None) -> dict:
    """Hatch inside closed boundaries (closed polylines, circles...). pattern: ANSI31, SOLID, AR-CONC, EARTH..."""
    with editing() as d:
        loops = entities(d, boundary_handles)
        h = ms(d).AddHatch(0, pattern, True)
        h.AppendOuterLoop(vobjects(loops))
        if pattern.upper() != "SOLID":
            h.PatternScale = float(scale)
            h.PatternAngle = math.radians(angle_deg)
        h.Evaluate()
        return done(d, [finish(d, h, layer, color)])


@tool("write")
def insert_block(name: str, position: Point, scale: float = 1, rotation_deg: float = 0,
                 attributes: dict[str, str] | None = None, layer: Layer = "") -> dict:
    """Insert a block by name (or a .dwg file path). attributes = {TAG: value} fills block attributes."""
    with editing() as d:
        e = ms(d).InsertBlock(vpt(position), name, float(scale), float(scale), float(scale), math.radians(rotation_deg))
        if attributes and g(e, "HasAttributes"):
            want = {k.upper(): v for k, v in attributes.items()}
            for a in as_list(e.GetAttributes()):
                if a.TagString.upper() in want:
                    a.TextString = str(want[a.TagString.upper()])
        return done(d, [finish(d, e, layer)])


@tool("write")
def create_block(name: str, handles: Handles, base_point: Point, replace_with_reference: bool = True) -> dict:
    """Make a block definition from objects. replace_with_reference=True swaps the originals for one insert."""
    with editing() as d:
        try:
            d.Blocks.Item(name)
            raise UserError(f"Block '{name}' đã có. Chọn tên khác.")
        except pywintypes.com_error:
            pass
        src = entities(d, handles)
        blk = d.Blocks.Add(vpt(base_point), name)
        d.CopyObjects(vobjects(src), blk)
        created = []
        if replace_with_reference:
            for e in src:
                e.Delete()
            created.append(ms(d).InsertBlock(vpt(base_point), name, 1.0, 1.0, 1.0, 0.0))
        return done(d, created, block=name, objects=len(src))


# ---------------------------------------------------------------- dimensions
@tool("write")
def dim_linear(p1: Point, p2: Point, dim_line_point: Point, direction: str = "auto", layer: Layer = "") -> dict:
    """Horizontal/vertical dimension between p1 and p2; the dimension line passes through dim_line_point.
    direction: auto | horizontal | vertical."""
    dx, dy = abs(p2[0] - p1[0]), abs(p2[1] - p1[1])
    if direction == "auto":
        direction = "horizontal" if abs(dim_line_point[1] - (p1[1] + p2[1]) / 2) >= abs(dim_line_point[0] - (p1[0] + p2[0]) / 2) else "vertical"
        if dx < 1e-9:
            direction = "vertical"
        elif dy < 1e-9:
            direction = "horizontal"
    rot = 0.0 if direction == "horizontal" else math.pi / 2
    with editing() as d:
        return done(d, [finish(d, ms(d).AddDimRotated(vpt(p1), vpt(p2), vpt(dim_line_point), rot), layer)])


@tool("write")
def dim_aligned(p1: Point, p2: Point, offset: float = 10, layer: Layer = "") -> dict:
    """Aligned dimension along p1-p2, offset to the left of the direction p1->p2 (negative = right)."""
    L = math.hypot(p2[0] - p1[0], p2[1] - p1[1])
    if L < 1e-9:
        raise UserError("Hai điểm trùng nhau.")
    nx, ny = -(p2[1] - p1[1]) / L, (p2[0] - p1[0]) / L
    tp = [(p1[0] + p2[0]) / 2 + nx * offset, (p1[1] + p2[1]) / 2 + ny * offset]
    with editing() as d:
        return done(d, [finish(d, ms(d).AddDimAligned(vpt(p1), vpt(p2), vpt(tp)), layer)])


@tool("write")
def dim_radius(handle: str, diameter: bool = False, angle_deg: float = 45, layer: Layer = "") -> dict:
    """Radius (or diameter) dimension of a circle or arc, placed at angle_deg."""
    with editing() as d:
        e = by_handle(d, handle)
        if etype(e) not in ("Circle", "Arc"):
            raise UserError("Chỉ ghi bán kính cho Circle hoặc Arc.")
        c, r = list(e.Center), float(e.Radius)
        a = math.radians(angle_deg)
        p = [c[0] + r * math.cos(a), c[1] + r * math.sin(a)]
        if diameter:
            q = [c[0] - r * math.cos(a), c[1] - r * math.sin(a)]
            dim = ms(d).AddDimDiametric(vpt(p), vpt(q), r * 0.5)
        else:
            dim = ms(d).AddDimRadial(vpt(c), vpt(p), r * 0.5)
        return done(d, [finish(d, dim, layer)])


@tool("write")
def auto_dim(handles: list[str] | None = None, offset: float = 0, layer: Layer = "") -> dict:
    """Dimension every straight segment of lines/polylines, placed outside closed shapes.
    No handles = current selection. offset 0 = automatic (about 5% of the object size)."""
    with editing() as d:
        ents = entities(d, handles) if handles else selection_handles(d)
        if not ents:
            raise UserError("Chưa chọn đối tượng nào.")
        out = []
        for e in ents:
            t = etype(e)
            if t == "Line":
                pts, closed = [list(e.StartPoint)[:2], list(e.EndPoint)[:2]], False
            elif t in ("Polyline", "2dPolyline"):
                pts, closed = [p[:2] for p in poly_points(e)], bool(g(e, "Closed", False))
            else:
                continue
            if closed and pts[0] != pts[-1]:
                pts = pts + [pts[0]]
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            off = offset or 0.05 * max(max(xs) - min(xs), max(ys) - min(ys), 1e-6)
            area2 = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(pts, pts[1:]))
            side = -1 if (closed and area2 > 0) else 1  # CCW closed shape: outside is to the right
            for i, (a, b) in enumerate(zip(pts, pts[1:])):
                if t != "Line" and abs(g(e, "GetBulge") and e.GetBulge(i) or 0) > 1e-9:
                    continue  # arc segment
                L = math.hypot(b[0] - a[0], b[1] - a[1])
                if L < 1e-9:
                    continue
                nx, ny = -(b[1] - a[1]) / L, (b[0] - a[0]) / L
                tp = [(a[0] + b[0]) / 2 + nx * off * side, (a[1] + b[1]) / 2 + ny * off * side]
                out.append(finish(d, ms(d).AddDimAligned(vpt(a), vpt(b), vpt(tp)), layer))
        return done(d, out)


# ---------------------------------------------------------------- modify
@tool("write")
def move(handles: Handles, dx: float, dy: float, dz: float = 0) -> dict:
    """Move objects by a displacement."""
    with editing() as d:
        from . import meta
        for e in entities(d, handles):
            e.Move(vpt([0, 0, 0]), vpt([dx, dy, dz]))
            meta.apply_affine(e, *meta.translate([dx, dy, dz]), d)
        return done(d, moved=len(handles))


@tool("write")
def copy(handles: Handles, dx: float, dy: float, dz: float = 0, times: int = 1) -> dict:
    """Copy objects by a displacement; times>1 makes a row of copies (dx, 2dx, ...)."""
    with editing() as d:
        out = []
        for e in entities(d, handles):
            for k in range(1, max(1, times) + 1):
                c = e.Copy()
                c.Move(vpt([0, 0, 0]), vpt([dx * k, dy * k, dz * k]))
                from . import meta
                meta.apply_affine(c, *meta.translate([dx * k, dy * k, dz * k]), d)
                out.append(c)
        return done(d, out)


@tool("write")
def rotate(handles: Handles, base: Point, angle_deg: float) -> dict:
    """Rotate objects about a base point (counter-clockwise)."""
    with editing() as d:
        from . import meta
        for e in entities(d, handles):
            e.Rotate(vpt(base), math.radians(angle_deg))
            meta.apply_affine(e, *meta.rot_z(list(base) + [0], math.radians(angle_deg)), d)
        return done(d, rotated=len(handles))


@tool("write")
def scale(handles: Handles, base: Point, factor: float) -> dict:
    """Scale objects about a base point."""
    if factor <= 0:
        raise UserError("Hệ số tỉ lệ phải > 0.")
    with editing() as d:
        from . import meta
        for e in entities(d, handles):
            e.ScaleEntity(vpt(base), float(factor))
            meta.apply_affine(e, *meta.uniform_scale((list(base) + [0, 0])[:3], float(factor)), d)
        return done(d, scaled=len(handles))


@tool("write")
def mirror(handles: Handles, p1: Point, p2: Point, keep_original: bool = True) -> dict:
    """Mirror objects across the line p1-p2."""
    with editing() as d:
        out = []
        from . import meta
        for e in entities(d, handles):
            m = e.Mirror(vpt(p1), vpt(p2))
            meta.apply_affine(m, *meta.mirror_line(p1, p2), d)
            out.append(m)
            if not keep_original:
                e.Delete()
        return done(d, out)


@tool("write")
def offset(handles: Handles, distance: float) -> dict:
    """Offset curves (lines, arcs, circles, polylines). Positive/negative picks the side."""
    with editing() as d:
        out = []
        for e in entities(d, handles):
            out += as_list(e.Offset(float(distance)))
        return done(d, out)


@tool("write")
def array_rect(handles: Handles, rows: int, columns: int, row_spacing: float, column_spacing: float) -> dict:
    """Rectangular array (copies) of objects."""
    with editing() as d:
        out = []
        for e in entities(d, handles):
            out += as_list(e.ArrayRectangular(int(rows), int(columns), 1, float(row_spacing), float(column_spacing), 0.0))
        return done(d, out)


@tool("write")
def array_polar(handles: Handles, count: int, center: Point, fill_angle_deg: float = 360) -> dict:
    """Polar array: count items (including the original) around center over fill_angle_deg."""
    with editing() as d:
        out = []
        for e in entities(d, handles):
            out += as_list(e.ArrayPolar(int(count), math.radians(fill_angle_deg), vpt(center)))
        return done(d, out)


@tool("write")
def set_props(handles: Handles, layer: str = "", color: Color = None, linetype: str = "",
              lineweight: int | None = None, text: str | None = None) -> dict:
    """Change layer, color, linetype, lineweight (1/100 mm, -1 = ByLayer) or text content of objects."""
    with editing() as d:
        ens = entities(d, handles)
        if layer:
            ensure_layer(d, layer)
        ci = color_index(color)
        for e in ens:
            if layer:
                e.Layer = layer
            if ci is not None:
                e.Color = ci
            if linetype:
                e.Linetype = linetype
            if lineweight is not None:
                e.Lineweight = int(lineweight)
            if text is not None and etype(e) in ("Text", "MText"):
                e.TextString = text
        return done(d, changed=len(ens))


@tool("destructive")
def delete(handles: Handles) -> dict:
    """Delete objects (ask the user first). Can be undone with UNDO."""
    with editing() as d:
        ens = entities(d, handles)
        for e in ens:
            e.Delete()
        return done(d, deleted=len(ens))


@tool("write")
def layer(name: str, color: Color = None, linetype: str = "", on: bool | None = None, frozen: bool | None = None,
          locked: bool | None = None, make_current: bool = False) -> dict:
    """Create a layer or change its color, linetype, on/off, frozen, locked; optionally make it current."""
    with editing() as d:
        ensure_layer(d, name)
        L = d.Layers.Item(name)
        ci = color_index(color)
        if ci is not None:
            L.Color = ci
        if linetype:
            L.Linetype = linetype
        if on is not None:
            L.LayerOn = bool(on)
        if frozen is not None:
            L.Freeze = bool(frozen)
        if locked is not None:
            L.Lock = bool(locked)
        if make_current:
            d.ActiveLayer = L
        return done(d, layer=name)


# ---------------------------------------------------------------- drawing / view
@tool("write")
def zoom(extents: bool = True, corner1: Point | None = None, corner2: Point | None = None) -> dict:
    """Zoom the active tab: extents (default) or the window corner1-corner2."""
    d = doc()
    need_active(d, "zoom")
    app = C.conn.app()
    if corner1 and corner2:
        app.ZoomWindow(vpt(corner1), vpt(corner2))
    else:
        app.ZoomExtents()
    return done(d)


@tool("write")
def undo(steps: int = 1) -> dict:
    """Undo the last steps in the working drawing (each modifying tool call = 1 step)."""
    d = doc()
    need_active(d, "UNDO")
    run_cmd(d, f"_.UNDO {max(1, int(steps))} ")
    return done(d, undone=steps)


@tool("write")
def redo() -> dict:
    """Redo the last undo."""
    d = doc()
    need_active(d, "REDO")
    run_cmd(d, "_.REDO ")
    return done(d)


@tool("destructive")
def command(cmd: str) -> dict:
    """Send a command line string to the active tab, e.g. "_.REGEN " or "_.PURGE _A * _N ".
    Prefer the dedicated tools; use this only for commands they do not cover. Ends with a space or newline."""
    d = doc()
    need_active(d, "lệnh dòng lệnh")
    if not cmd.endswith((" ", "\n")):
        cmd += " "
    finished = run_cmd(d, cmd)
    return done(d, sent=cmd, finished=finished)


@tool("write")
def new_drawing(template: str = "") -> dict:
    """Create a new drawing (optionally from a .dwt template) and make it the working drawing."""
    docs = C.conn.app().Documents
    d = docs.Add(template) if template else docs.Add()
    C.drawings.pinned = Drawings.name(d)
    return done(d)


@tool("write")
def open_drawing(path: str, read_only: bool = False) -> dict:
    """Open a .dwg file and make it the working drawing."""
    if not os.path.isfile(path):
        raise UserError(f"Không có tệp '{path}'.")
    d = C.conn.app().Documents.Open(path, bool(read_only))
    C.drawings.pinned = Drawings.name(d)
    return done(d)


@tool("destructive")
def save(path: str = "", overwrite: bool = False) -> dict:
    """Save the working drawing (ask the user first). path = Save As to a new .dwg; existing files need overwrite=True."""
    d = doc()
    if not path:
        if not g(d, "FullName"):
            raise UserError("Bản vẽ chưa có tên tệp: truyền path để Save As.")
        d.Save()
        return done(d, saved=Drawings.name(d))
    path = os.path.abspath(path)
    if not path.lower().endswith(".dwg"):
        path += ".dwg"
    if os.path.exists(path) and not overwrite:
        raise UserError(f"Tệp '{path}' đã có. Hỏi người dùng rồi gọi lại với overwrite=True.")
    d.SaveAs(path)
    if C.drawings.pinned:
        C.drawings.pinned = Drawings.name(d)
    return done(d, saved=path)


# ---------------------------------------------------------------- interactive
@tool("read")
def pick_points(prompt: str = "Chọn điểm", count: int = 1) -> dict:
    """Ask the user to click point(s) in the CAD window (waits for the user; Esc cancels)."""
    d = doc()
    need_active(d, "chọn điểm")
    pts = []
    try:
        for i in range(max(1, count)):
            msg = f"\n{prompt}" + (f" ({i + 1}/{count})" if count > 1 else "") + ": "
            pts.append(r3(d.Utility.GetPoint(pythoncom_empty(), msg)))
    except pywintypes.com_error:
        if not pts:
            raise UserError("Người dùng đã huỷ chọn điểm.") from None
    return {"points": pts}


@tool("read")
def pick_objects(prompt: str = "Chọn đối tượng rồi Enter") -> dict:
    """Ask the user to select objects in the CAD window (waits for Enter; Esc cancels)."""
    d = doc()
    need_active(d, "chọn đối tượng")
    with contextlib.suppress(pywintypes.com_error):
        d.Utility.Prompt(f"\n{prompt}\n")
    ss = new_selection_set(d)
    try:
        ss.SelectOnScreen()
        ents = [ss.Item(i) for i in range(ss.Count)]
        return {"count": len(ents), "entities": [describe(e) for e in ents[:500]]}
    finally:
        with contextlib.suppress(pywintypes.com_error):
            ss.Delete()


def pythoncom_empty():
    import pythoncom
    import win32com.client
    return win32com.client.VARIANT(pythoncom.VT_EMPTY, None)


# ---------------------------------------------------------------- script (off by default)
@tool("destructive")
def run_script(code: str) -> str:
    """Run Python for batch work or calculations. Names available: doc (working drawing), ms (ModelSpace),
    pt([x,y,z]) point variant, arr([...]) double array, math, describe(e), and every tool as a function.
    Assign `result` or print(). The whole script is one undo step."""
    d = doc()
    ns = {n: v for n, v in globals().items() if not n.startswith("_")}
    ns.update(doc=d, ms=d.ModelSpace, pt=vpt, arr=vdoubles, math=math, describe=describe)
    for fn, _ in _REGISTRY:  # tools callable directly (sync, already on the CAD thread)
        ns[fn.__name__] = fn.__wrapped__
    out = io.StringIO()
    with undo_group(d), contextlib.redirect_stdout(out):
        try:
            exec(compile(code, "<run_script>", "exec"), ns)
        except Exception:
            print(traceback.format_exc(limit=4))
    if "result" in ns:
        print(ns["result"], file=out)
    return out.getvalue() or "ok"


# extra tool modules (they register themselves with @tool)
from . import ifc, pdf, skills, solids, work  # noqa: E402,F401
