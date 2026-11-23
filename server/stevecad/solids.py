"""3D solid tools: put a 2D profile (from the drawing or from numbers) onto a 3D plane of a structure frame and
extrude it; booleans, slicing, boundaries, 3D view. Designed for culverts and other linear structures."""
from __future__ import annotations

import contextlib
import math
import time
from typing import Annotated

import pythoncom
import pywintypes
import win32com.client
from pydantic import Field

from .drawing import (UserError, as_list, bbox, by_handle, color_index, ensure_layer, etype, g, r3, run_cmd, vdoubles,
                      vobjects, vpt)
from . import meta
from .tools import C, Point, done, editing, need_active, tool

Vec = tuple[float, float, float]


# ---------------------------------------------------------------- vector helpers
def _cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a: Vec, b: Vec) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _unit(a: Vec) -> Vec:
    n = math.sqrt(_dot(a, a))
    return (a[0] / n, a[1] / n, a[2] / n)


def _add(a: Vec, b: Vec, k: float = 1.0) -> Vec:
    return (a[0] + k * b[0], a[1] + k * b[1], a[2] + k * b[2])


def frame(azimuth_deg: float, slope_pct: float) -> dict[str, Vec]:
    """Structure frame: u = along the axis (plan direction azimuth, rising slope_pct %), r = right of u (horizontal),
    w = 'up' (perpendicular to u and r)."""
    az = math.radians(azimuth_deg)
    th = math.atan(slope_pct / 100.0)
    u = (math.cos(az) * math.cos(th), math.sin(az) * math.cos(th), math.sin(th))
    r = (math.sin(az), -math.cos(az), 0.0)
    w = _unit(_cross(r, u))
    return {"u": u, "r": r, "w": w}


VIEWS = {
    # profile x -> , profile y -> , extrusion axis
    "section": ("r", "w", "u"),    # mặt cắt ngang / chính diện: nhìn xuôi theo tuyến (+u), bên phải là +x
    "elevation": ("u", "w", "r"),  # mặt cắt dọc / mặt đứng: trục cống sang phải là +x, đùn theo bề ngang
    "plan": ("u", "l", "w"),       # mặt bằng: trục cống sang phải (+x), bên trái tuyến là +y, đùn theo phương đứng
}


def _matrix(X: Vec, Y: Vec, N: Vec, origin: Vec, base: tuple[float, float], s: float):
    t = (origin[0] - s * (base[0] * X[0] + base[1] * Y[0]),
         origin[1] - s * (base[0] * X[1] + base[1] * Y[1]),
         origin[2] - s * (base[0] * X[2] + base[1] * Y[2]))
    rows = tuple((X[i] * s, Y[i] * s, N[i] * s, t[i]) for i in range(3)) + ((0.0, 0.0, 0.0, 1.0),)
    return win32com.client.VARIANT(pythoncom.VT_ARRAY | pythoncom.VT_R8, rows)


def _source_color(d, e):
    """Color of an object as it is displayed: ByLayer -> the layer's color, ByBlock -> 7. Returns (aci, truecolor)."""
    ci = g(e, "Color")
    if ci == 256:
        try:
            L = d.Layers.Item(e.Layer)
            return g(L, "Color", 7), g(L, "TrueColor")
        except pywintypes.com_error:
            return 7, None
    if ci == 0:
        return 7, None
    return ci, g(e, "TrueColor")


def _apply_color(sol, aci, tc):
    if tc is not None:
        try:
            sol.TrueColor = tc
            return
        except Exception:
            pass
    if aci is not None:
        sol.Color = int(aci)


def _inside(a, b) -> bool:
    """bbox a inside bbox b (2D/3D, tolerant)."""
    (alo, ahi), (blo, bhi) = a, b
    eps = 1e-9 + 1e-6 * max(abs(x) for x in list(bhi) + list(blo) + [1])
    return all(blo[i] - eps <= alo[i] and ahi[i] <= bhi[i] + eps for i in range(3))


def _profile_curves(d, ms, handles, loops):
    """Temporary curve copies (in their drawing position) for the profile."""
    tmp = []
    if handles:
        for h in handles:
            e = by_handle(d, h)
            if etype(e) not in ("Line", "Arc", "Circle", "Ellipse", "Polyline", "2dPolyline", "Spline", "Region"):
                raise UserError(f"Đối tượng {h} ({etype(e)}) không dùng làm mặt cắt được: cần Line/Arc/Circle/Polyline/Spline.")
            tmp.append(e.Copy())
    for lp in loops or []:
        if "circle" in lp:
            cx, cy, rr = map(float, lp["circle"])
            tmp.append(ms.AddCircle(vpt([cx, cy]), rr))
        else:
            pts = lp.get("points") or []
            if len(pts) < 3:
                raise UserError("Mỗi vòng 'points' cần ít nhất 3 điểm.")
            p = ms.AddLightWeightPolyline(vdoubles([c for q in pts for c in (float(q[0]), float(q[1]))]))
            for i, b in enumerate(lp.get("bulges") or []):
                if b:
                    p.SetBulge(i, float(b))
            p.Closed = True
            tmp.append(p)
    if not tmp:
        raise UserError("Chưa có mặt cắt: truyền profile_handles (đối tượng trong bản vẽ) hoặc loops (toạ độ).")
    return tmp


def _arc_pts(p0, p1, bulge, n=12):
    """Points on a polyline arc segment (bulge = tan(angle/4)), excluding p0, including p1."""
    if abs(bulge) < 1e-12:
        return [p1]
    th = 4 * math.atan(bulge)
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    c = math.hypot(dx, dy)
    r = c / (2 * math.sin(th / 2))
    mx, my = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
    h = r * math.cos(th / 2)
    nx, ny = -dy / c, dx / c
    cx, cy = mx + nx * h, my + ny * h
    a0 = math.atan2(p0[1] - cy, p0[0] - cx)
    k = max(2, int(abs(th) / (math.pi / 2) * n))
    rr = math.hypot(p0[0] - cx, p0[1] - cy)
    return [[cx + rr * math.cos(a0 + th * i / k), cy + rr * math.sin(a0 + th * i / k)] for i in range(1, k + 1)]


def _poly_loop(pts, bulges):
    out = [list(pts[0])]
    n = len(pts)
    for i in range(n):
        b = bulges[i] if i < len(bulges) else 0.0
        out += _arc_pts(pts[i], pts[(i + 1) % n], b)
    return out[:-1] if math.dist(out[0], out[-1]) < 1e-9 else out


def _circle_loop(cx, cy, r, n=48):
    return [[cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)] for i in range(n)]


def _source_loops(d, handles, loops):
    """2D loops of the profile in its own coordinates (None if a curve type cannot be described)."""
    out = []
    for h in handles or []:
        e = by_handle(d, h)
        t = etype(e)
        if t == "Polyline":
            c = list(e.Coordinates)
            pts = [[c[i], c[i + 1]] for i in range(0, len(c), 2)]
            bul = []
            for i in range(len(pts)):
                try:
                    bul.append(float(e.GetBulge(i)))
                except Exception:
                    bul.append(0.0)
            out.append(_poly_loop(pts, bul))
        elif t == "Circle":
            cc = list(e.Center)
            out.append(_circle_loop(cc[0], cc[1], float(e.Radius)))
        else:
            return None
    for lp in loops or []:
        if "circle" in lp:
            cx, cy, rr = map(float, lp["circle"])
            out.append(_circle_loop(cx, cy, rr))
        else:
            pts = [[float(q[0]), float(q[1])] for q in lp.get("points") or []]
            out.append(_poly_loop(pts, [float(b) for b in (lp.get("bulges") or [])]))
    return out


def _area(lp):
    return abs(sum(lp[i][0] * lp[(i + 1) % len(lp)][1] - lp[(i + 1) % len(lp)][0] * lp[i][1] for i in range(len(lp)))) / 2


def _group_loops(lps):
    """Same outer/hole grouping as _regions: [[outer, hole, ...], ...] sorted by outer area (largest first)."""
    info = sorted(((lp, _area(lp), (min(p[0] for p in lp), min(p[1] for p in lp), max(p[0] for p in lp), max(p[1] for p in lp))) for lp in lps),
                  key=lambda x: -x[1])
    groups = []
    for lp, _, bb in info:
        host = next((gp for gp in groups if gp[1][0] - 1e-9 <= bb[0] and gp[1][1] - 1e-9 <= bb[1] and bb[2] <= gp[1][2] + 1e-9 and bb[3] <= gp[1][3] + 1e-9), None)
        if host is None:
            groups.append([[lp], bb])
        else:
            host[0].append(lp)
    return [gp[0] for gp in groups]


def _regions(ms, curves):
    """Closed loops -> regions with holes subtracted (a loop inside another loop is a hole)."""
    try:
        regs = as_list(ms.AddRegion(vobjects(curves)))
    except pywintypes.com_error as e:
        raise UserError("Không tạo được vùng kín từ mặt cắt (các đường chưa khép kín hoặc tự cắt nhau). "
                        "Dùng boundary_at để tạo đường bao kín rồi thử lại.") from e
    if not regs:
        raise UserError("Mặt cắt không có vòng kín nào.")
    info = []
    for rg in regs:
        lo, hi = rg.GetBoundingBox()
        info.append([rg, abs(rg.Area), (tuple(lo), tuple(hi))])
    info.sort(key=lambda x: -x[1])
    outers = []
    for rg, area, bb in info:
        host = next((o for o in outers if _inside(bb, o[2])), None)
        if host is None:
            outers.append([rg, area, bb, 0])
        else:
            host[0].Boolean(2, rg)  # subtract hole (rg is consumed)
            host[3] += 1
    return [(o[0], o[3]) for o in outers]


# ---------------------------------------------------------------- tools
Loops = Annotated[list[dict] | None, Field(description='Profile from numbers: [{"points": [[x,y],...], "bulges": [...]?}, {"circle": [cx,cy,r]}]. A loop inside another is a hole.')]


@tool("write")
def solid_extrude(view: str, origin: Point, extrude_from: float | None = None, extrude_to: float | None = None,
                  pieces: list[list[float]] | None = None, segment_length: float | None = None,
                  joint_gap: float = 0.0, profile_handles: list[str] | None = None, loops: Loops = None,
                  base_point: list[float] | None = None, scale: float = 1.0, mirror_x: bool = False,
                  azimuth_deg: float = 0.0, slope_pct: float = 0.0,
                  layer: str = "", color: int | str | None = None, name: str = "", material: str = "",
                  props: dict | None = None) -> dict:
    """Build a 3D solid from a 2D profile placed in the frame of a linear structure (culvert, wall, beam...).

    Frame: origin (model point, e.g. invert/đáy trong at the inlet, with its real elevation z), azimuth_deg (plan
    direction of the structure axis, CCW from +X), slope_pct (dốc dọc, + = rising along the axis).
    view = which drawing view the profile comes from:
      - "section"   (mặt cắt ngang / chính diện): profile x -> right of the axis, y -> up; extruded ALONG the axis.
      - "elevation" (mặt cắt dọc / mặt đứng): profile x -> along the axis, y -> up; extruded ACROSS (to the right).
      - "plan"      (mặt bằng): profile x -> along the axis, y -> left of the axis; extruded UP.
    extrude_from/extrude_to: range along the extrusion direction, in model units (e.g. 0 to L along the axis;
    -B/2 to B/2 across; z offsets up).
    Segments (đốt cống, mối nối): pieces = [[from, to], ...] makes one solid per range (exact layout read from the
    drawing: end pieces, closure segment...); or segment_length + joint_gap splits extrude_from..extrude_to into
    equal segments (the last one shorter if it does not divide). Joint collars: same tool with short pieces
    centred on each joint. base_point: profile point (in the profile's own coordinates) that lands on
    origin. scale: profile units -> model units (0.001 when the profile is in mm and the model in m).
    mirror_x: flip the profile left/right (view drawn from the other side).
    Profile: profile_handles (closed curves already in the drawing - holes = inner loops) or loops (numbers).
    Color: default = the source object's displayed color (ByLayer resolved), so parts stay color-separated.
    Non-graphic data (kept on the solid, exported to IFC): name = part name (e.g. "Tường đầu hạ lưu BT M250"),
    material (guessed from the name if empty), props = extra fields such as {"structure": "CH4X4",
    "station": "Km8+423.31", "type": "Cống hộp 4x4"}."""
    view = view.lower().strip()
    if view not in VIEWS:
        raise UserError("view phải là section, elevation hoặc plan.")
    if pieces:
        ranges = [sorted((float(a), float(b))) for a, b in pieces]
    else:
        if extrude_from is None or extrude_to is None:
            raise UserError("Cần extrude_from và extrude_to (hoặc pieces).")
        a0, b0 = sorted((float(extrude_from), float(extrude_to)))
        if segment_length:
            ranges, t = [], a0
            while t < b0 - 1e-9:
                ranges.append([t, min(t + float(segment_length), b0)])
                t += float(segment_length) + float(joint_gap)
        else:
            ranges = [[a0, b0]]
    ranges = [r for r in ranges if r[1] - r[0] > 1e-9]
    if not ranges:
        raise UserError("Khoảng đùn rỗng: from và to phải khác nhau.")
    if len(ranges) > 2000:
        raise UserError("Quá nhiều đoạn (>2000).")
    F = frame(azimuth_deg, slope_pct)
    F["l"] = (-F["r"][0], -F["r"][1], -F["r"][2])
    xk, yk, ek = VIEWS[view]
    X, Y, E = F[xk], F[yk], F[ek]
    if mirror_x:
        X = (-X[0], -X[1], -X[2])
    N = _unit(_cross(X, Y))
    o = tuple(map(float, (list(origin) + [0, 0, 0])[:3]))
    o3 = o
    with editing() as d:
        ms = d.ModelSpace
        src = by_handle(d, profile_handles[0]) if profile_handles else None
        if base_point is None:
            if src is None:
                base_point = [0.0, 0.0]
            else:
                raise UserError("Cần base_point: điểm trên mặt cắt (toạ độ trong bản vẽ) ứng với origin, "
                                "ví dụ tim đáy trong của cống.")
        src_loops = _source_loops(d, profile_handles, loops)
        curves = _profile_curves(d, ms, profile_handles, loops)
        regs = []
        try:
            M = _matrix(X, Y, N, o3, (float(base_point[0]), float(base_point[1])), float(scale))
            for c in curves:
                c.TransformBy(M)
            regs = _regions(ms, curves)
            out = []
            for rg, holes in regs:
                # the CAD picks the region normal itself: if it points against the wanted direction, start from `hi`
                along = _dot(tuple(rg.Normal), E) >= 0
                for lo, hi in ranges:
                    r2 = rg.Copy()
                    k = lo if along else hi
                    r2.Move(vpt([0, 0, 0]), vpt([E[0] * k, E[1] * k, E[2] * k]))
                    try:
                        out.append((ms.AddExtrudedSolid(r2, hi - lo, 0.0), holes, (lo, hi)))
                    finally:
                        with contextlib.suppress(Exception):
                            r2.Delete()
        finally:
            for c in curves:
                with contextlib.suppress(Exception):
                    c.Delete()
            for rg, _ in regs:
                with contextlib.suppress(Exception):
                    rg.Delete()
        aci, tc = (color_index(color), None) if color not in (None, "", "source") else (
            _source_color(d, src) if src is not None else (None, None))
        if layer:
            ensure_layer(d, layer)
        groups = None
        if src_loops:
            bx, by, sc = float(base_point[0]), float(base_point[1]), float(scale)
            loc = [[[(p[0] - bx) * sc, (p[1] - by) * sc] for p in lp] for lp in src_loops]
            groups = _group_loops(loc)
        n_out = max(1, len(out) // max(1, len(ranges)))
        mat = material or meta.guess_material(name)
        res = []
        total = 0.0
        for idx, (sol, holes, (lo, hi)) in enumerate(out):
            gi = idx // max(1, len(ranges))
            rec = {"v": 1, "part": name or "", "material": mat, "props": props or {}}
            if groups and len(groups) == n_out:
                rec["geo"] = {"t": "ext", "o": list(o3), "X": list(X), "Y": list(Y), "E": list(E), "lo": lo, "hi": hi,
                              "loops": groups[gi]}
            meta.stamp(sol, rec, d)
            if layer:
                sol.Layer = layer
            _apply_color(sol, aci, tc)
            v = g(sol, "Volume") or 0.0
            total += v
            row = {"handle": g(sol, "Handle"), "volume": r3(v), "range": [r3(lo), r3(hi)]}
            if len(out) <= 3:
                row.update(holes=holes, bbox=bbox(sol))
            res.append(row)
        return done(d, None, count=len(res), total_volume=r3(total), solids=res, name=name or None)


@tool("write")
def solid_boolean(operation: str, target: str, others: list[str], keep_others: bool = False) -> dict:
    """Combine solids: operation = union | subtract | intersect. target is kept (changed); others are consumed
    unless keep_others=True. Use intersect of a plan extrusion and an elevation extrusion to get exact shapes
    (e.g. wing walls / tường cánh with a sloping top)."""
    op = {"union": 0, "intersect": 1, "subtract": 2}.get(operation.lower().strip())
    if op is None:
        raise UserError("operation phải là union, subtract hoặc intersect.")
    with editing() as d:
        t = by_handle(d, target)
        keep_color = (g(t, "Color"), g(t, "TrueColor"))  # ZWCAD resets the color to ByLayer after Boolean
        rec_t = meta.read(t) or {"v": 1, "part": "", "props": {}}
        geo_ok = "geo" in rec_t and meta.is_current(t, rec_t)
        geos = []
        for h in others:
            o = by_handle(d, h)
            ro = meta.read(o)
            if ro and "geo" in ro and meta.is_current(o, ro):
                geos.append(ro["geo"])
            else:
                geo_ok = False
            if keep_others:
                o = o.Copy()
            t.Boolean(op, o)
            # AutoCAD erases the consumed solid; ZWCAD leaves an empty one behind -> remove it
            with contextlib.suppress(Exception):
                if (g(o, "Volume") or 0.0) <= 1e-12:
                    o.Delete()
        if keep_color[0] is not None and g(t, "Color") != keep_color[0]:
            _apply_color(t, keep_color[0], keep_color[1])
        if geo_ok:
            rec_t["geo"] = {"t": "bool", "op": operation.lower().strip(), "a": rec_t["geo"], "b": geos}
        else:
            rec_t.pop("geo", None)
        meta.stamp(t, rec_t, d)
        vol = g(t, "Volume")
        if vol is not None and vol <= 1e-12:
            raise UserError("Kết quả rỗng (hai khối không giao nhau?). Gõ UNDO để quay lại.")
        return done(d, None, handle=g(t, "Handle"), volume=r3(vol), bbox=bbox(t))


@tool("write")
def solid_slice(handles: list[str], point: Point, normal: Point, keep: str = "back") -> dict:
    """Cut solids with a plane through point with the given normal [nx, ny, nz].
    keep = "back" (side opposite to the normal), "front" (side the normal points to) or "both".
    Typical use: skewed culvert ends (đầu cống chéo) - a vertical plane at the skew angle."""
    n = _unit(tuple(map(float, (list(normal) + [0, 0, 0])[:3])))
    p = tuple(map(float, (list(point) + [0, 0, 0])[:3]))
    a = _unit(_cross(n, (0, 0, 1)) if abs(n[2]) < 0.9 else _cross(n, (1, 0, 0)))
    b = _cross(n, a)
    with editing() as d:
        kept = []
        for h in handles:
            s1 = by_handle(d, h)
            rec0 = meta.read(s1)
            if rec0 and not meta.is_current(s1, rec0):
                rec0.pop("geo", None)
            s2 = s1.SliceSolid(vpt(p), vpt(_add(p, a)), vpt(_add(p, b)), True)
            parts = [x for x in [s1] + as_list(s2) if x is not None]
            for part in parts:
                c = g(part, "Centroid")
                side = _dot((c[0] - p[0], c[1] - p[1], c[2] - p[2]), n) if c is not None else 0
                want = keep == "both" or (keep == "front" and side > 0) or (keep == "back" and side <= 0)
                if want:
                    kept.append(part)
                    if rec0 is not None:
                        rec = dict(rec0)
                        if "geo" in rec0:
                            rec["geo"] = {"t": "clip", "n": rec0["geo"], "p": list(p), "nrm": list(n),
                                          "keep": "front" if side > 0 else "back"}
                        meta.stamp(part, rec, d)
                else:
                    part.Delete()
        return done(d, kept)


@tool("write")
def solid_box_from_points(p1: Point, p2: Point, layer: str = "", color: int | str | None = None) -> dict:
    """Axis-aligned box between two opposite 3D corners (quick blocks: đệm móng, chân khay...)."""
    a = [float(x) for x in (list(p1) + [0])[:3]]
    b = [float(x) for x in (list(p2) + [0])[:3]]
    L, W, H = abs(b[0] - a[0]), abs(b[1] - a[1]), abs(b[2] - a[2])
    if min(L, W, H) <= 0:
        raise UserError("Hộp phải có kích thước > 0 theo cả 3 phương.")
    with editing() as d:
        c = [(a[i] + b[i]) / 2 for i in range(3)]
        s = d.ModelSpace.AddBox(vpt(c), L, W, H)
        if layer:
            ensure_layer(d, layer)
            s.Layer = layer
        ci = color_index(color)
        if ci is not None:
            s.Color = ci
        meta.stamp(s, {"v": 1, "part": "", "props": {}, "geo": {
            "t": "ext", "o": [0.0, 0.0, 0.0], "X": [1.0, 0.0, 0.0], "Y": [0.0, 1.0, 0.0], "E": [0.0, 0.0, 1.0],
            "lo": min(a[2], b[2]), "hi": max(a[2], b[2]),
            "loops": [[[min(a[0], b[0]), min(a[1], b[1])], [max(a[0], b[0]), min(a[1], b[1])],
                       [max(a[0], b[0]), max(a[1], b[1])], [min(a[0], b[0]), max(a[1], b[1])]]]}}, d)
        return done(d, [s], volume=r3(g(s, "Volume")))


@tool("write")
def boundary_at(point: Point, only_layers: list[str] | None = None, zoom_first: bool = True, layer: str = "") -> dict:
    """Make a closed polyline around the area that contains `point` (like BOUNDARY / BPOLY), from lines, arcs,
    polylines nearby; islands inside become extra loops (holes). Use it when a section view is drawn with loose
    lines. only_layers = consider only these layers (others are hidden for the moment) - e.g. the concrete outline
    layer, so rebar, hatch and text lines do not split the area. The view zooms to the point first."""
    d = C.drawings.target()
    need_active(d, "BOUNDARY")
    app = C.conn.app()
    x, y = float(point[0]), float(point[1])
    hidden = []
    if only_layers:
        keep = {n.lower() for n in only_layers}
        if not layer:  # the current layer cannot be hidden: work on a kept layer
            layer = only_layers[0]
        for i in range(d.Layers.Count):
            L = d.Layers.Item(i)
            if L.Name.lower() not in keep and g(L, "LayerOn", True) and L.Name != g(d.ActiveLayer, "Name"):
                L.LayerOn = False
                hidden.append(L)
    try:
        return _boundary(d, app, x, y, zoom_first, layer)
    finally:
        for L in hidden:
            with contextlib.suppress(Exception):
                L.LayerOn = True


def _boundary(d, app, x, y, zoom_first, layer):
    if zoom_first:
        # zoom so the closed area around the point is fully visible
        ext = 5000.0
        try:
            lo = d.GetVariable("EXTMIN")
            hi = d.GetVariable("EXTMAX")
            ext = max(hi[0] - lo[0], hi[1] - lo[1]) / 20 or ext
        except Exception:
            pass
        app.ZoomWindow(vpt([x - ext, y - ext]), vpt([x + ext, y + ext]))
    ms = d.ModelSpace
    before = ms.Count
    if layer:
        ensure_layer(d, layer)
        old = d.ActiveLayer
        d.ActiveLayer = d.Layers.Item(layer)
    try:
        d.SendCommand(f"_.-BOUNDARY {x},{y}\n\n")
        t0 = time.monotonic()
        while time.monotonic() - t0 < 15:
            if not d.GetVariable("CMDACTIVE"):
                break
            time.sleep(0.1)
        else:
            with contextlib.suppress(Exception):
                d.SendCommand("\x03\x03")
            raise UserError("BOUNDARY không kết thúc (điểm nằm ngoài vùng kín?).")
    finally:
        if layer:
            d.ActiveLayer = old
    new = [ms.Item(i) for i in range(before, ms.Count)]
    if not new:
        raise UserError("Không tìm được vùng kín quanh điểm này. Phóng to để thấy hết vùng, hoặc vẽ thêm đường để khép kín.")
    return done(d, new, area=[r3(g(e, "Area")) for e in new])


@tool("write")
def view_3d(direction: str = "SE", style: str = "conceptual", zoom_to: list[str] | None = None,
            zoom_extents: bool = True) -> dict:
    """3D view of the active tab: direction SE | SW | NE | NW | top | front | left | right | back | bottom;
    style conceptual | realistic | shaded | hidden | wireframe | 2d. zoom_to = handles to fit on screen
    (e.g. the solids just built); otherwise zoom extents."""
    d = C.drawings.target()
    need_active(d, "đổi góc nhìn")
    views = {"se": (1, -1, 1), "sw": (-1, -1, 1), "ne": (1, 1, 1), "nw": (-1, 1, 1), "top": (0, 0, 1),
             "bottom": (0, 0, -1), "front": (0, -1, 0), "back": (0, 1, 0), "left": (-1, 0, 0), "right": (1, 0, 0)}
    styles = {"conceptual": "_C", "realistic": "_R", "shaded": "_S", "hidden": "_H", "wireframe": "_W", "2d": "_2"}
    v = views.get(direction.lower().strip())
    st = styles.get(style.lower().strip())
    if not v or not st:
        raise UserError("direction/style không hợp lệ.")
    vp = d.ActiveViewport
    vp.Direction = vpt(v)
    if not zoom_to and zoom_extents:
        # fit the whole model through the viewport (ZoomExtents right after a view change can show nothing)
        with contextlib.suppress(Exception):
            run_cmd(d, "_.REGEN ")
        try:
            lo, hi = list(d.GetVariable("EXTMIN")), list(d.GetVariable("EXTMAX"))
            if all(abs(v) < 1e19 for v in lo + hi):
                zoom_to = ["__extents__"]
        except Exception:
            pass
    if zoom_to:
        if zoom_to != ["__extents__"]:
            los, his = [], []
            for h in zoom_to:
                a, b = by_handle(d, h).GetBoundingBox()
                los.append(a)
                his.append(b)
            lo = [min(p[i] for p in los) for i in range(3)]
            hi = [max(p[i] for p in his) for i in range(3)]
        c = [(lo[i] + hi[i]) / 2 for i in range(3)]
        diag = math.sqrt(sum((hi[i] - lo[i]) ** 2 for i in range(3))) or 1.0
        vp.Target = vpt(c)                                     # look at the objects
        vp.Center = win32com.client.VARIANT(pythoncom.VT_ARRAY | pythoncom.VT_R8, (0.0, 0.0))
        vp.Height = diag * 0.8
    d.ActiveViewport = vp
    run_cmd(d, f"_.VSCURRENT {st} ")
    if not zoom_to and zoom_extents:
        C.conn.app().ZoomExtents()
    return done(d)
