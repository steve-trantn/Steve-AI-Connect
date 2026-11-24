"""Site placement, automatic layers and IFC export (IFC4 / IFC4X3) with basic non-graphic data."""
from __future__ import annotations

import datetime
import math
import os
import re
import unicodedata
import uuid

from . import __version__, culvert, culvert_geo, meta
from .drawing import UserError, by_handle, ensure_layer, etype, g, iter_space, r3, vpt
from .tools import C, done, editing, selection_handles, tool

WORKSPACE = os.path.join(os.path.expanduser("~"), "Steve-CAD-AI")

# ---------------------------------------------------------------- helpers
_ACI_RGB = {1: (255, 0, 0), 2: (255, 255, 0), 3: (0, 255, 0), 4: (0, 255, 255), 5: (0, 0, 255), 6: (255, 0, 255),
            7: (230, 230, 230), 8: (128, 128, 128), 9: (192, 192, 192), 30: (255, 127, 0)}


def aci_rgb(aci):
    if aci in _ACI_RGB:
        return _ACI_RGB[aci]
    if isinstance(aci, int) and 10 <= aci <= 249:  # rough hue wheel of the ACI table
        h = ((aci - 10) // 10) * 15 / 360.0
        import colorsys
        r, gg, b = colorsys.hsv_to_rgb(h, 1.0 if aci % 2 == 0 else 0.5, 1.0 if (aci % 10) < 2 else 0.65)
        return int(r * 255), int(gg * 255), int(b * 255)
    return (200, 200, 200)


def ascii_name(s: str) -> str:
    s = s.replace("đ", "d").replace("Đ", "D")
    s = unicodedata.normalize("NFKD", s)
    return "".join(c for c in s if not unicodedata.combining(c))


def layer_safe(s: str) -> str:
    s = ascii_name(s).upper().strip()
    s = re.sub(r'[<>/\\":;?*|=`,]', "-", s)
    s = re.sub(r"\s+", "-", s)
    s = re.sub(r"-{2,}", "-", s).strip("-")
    return s[:120] or "0"


def part_short(part: str) -> str:
    """'Tường đầu hạ lưu BT M250 dày 40 cm' -> 'Tường đầu hạ lưu' (drop material and dimensions)."""
    p = re.split(r"\s(?:BTCT|BTXM|BT|bê tông|đá 2x4|vữa|dày|rộng|L=|\()", part, maxsplit=1, flags=re.I)[0]
    p = re.sub(r"\s(?:số\s)?\d{1,3}\b", "", p)  # 'Đốt cống 07' -> 'Đốt cống' (one layer for all segments)
    return p.strip(" ,-") or part


def _solids(d, handles, layer):
    if handles:
        return [by_handle(d, h) for h in handles]
    return [e for e in iter_space(d, ["3dSolid"], layer or None)]


# ---------------------------------------------------------------- tools
def _scope(d, handles, from_layer, selection_only):
    if not selection_only:
        return _solids(d, handles, from_layer)
    low = (from_layer or "").lower()
    return [e for e in selection_handles(d) if etype(e) == "3dSolid" and (not low or (g(e, "Layer") or "").lower() == low)]


@tool()
def solid_info(handles: list[str] | None = None, from_layer: str = "", selection_only: bool = False, limit: int = 500, units: str = "") -> dict:
    """Read the non-graphic data of 3D solids as export_ifc will write it: name, part, material, structure, station, type and
    extra fields, plus layer, volume (drawing units) and whether the geometry is only approximate. Edit with tag_solids(rows=...).
    units (m | mm | cm | ft | us-ft | inch): also the structure tree (segments, lengths, sizes, volumes in m3) as export_ifc writes it."""
    d = C.drawings.target()
    ents = _scope(d, handles, from_layer, selection_only)
    items, extra = [], []
    for e in ents[:limit]:
        rec = meta.read(e) or {}
        props = dict(rec.get("props") or {})
        row = {"handle": g(e, "Handle"), "layer": g(e, "Layer") or "", "name": rec.get("name") or "", "part": rec.get("part") or "",
               "material": rec.get("material") or "", "material_guess": meta.guess_material(rec.get("part") or ""),
               "structure": props.pop("structure", ""), "station": props.pop("station", ""), "type": props.pop("type", ""),
               "group": props.pop("group", ""), "group_guess": culvert.group_of({"part": rec.get("part") or ""}),
               "props": {str(k): v for k, v in props.items()}, "volume": g(e, "Volume") or 0.0,
               "approximate": not ("geo" in rec and meta.is_current(e, rec))}
        extra += [k for k in row["props"] if k not in extra]
        items.append(row)
    try:
        hint = unit_hint(ents, d.GetVariable("INSUNITS"))
    except Exception:
        hint = ""
    k = UNITS.get((hint or units).lower()) if units else None
    trees = culvert.build([_record(e, k) for e in ents], k) if k else []
    lost = [c for c in trees if not c["structure"] and not c["station"]]
    sug = culvert_geo.suggest([s for c in lost for s in c["solids"]], [c for c in trees if c not in lost], k) if lost else {}
    return {"total": len(ents), "suggestions": sug, "partial": len(ents) > len(items), "extra_fields": extra, "items": items, "unit_hint": hint,
            "structures": [culvert.slim(c) for c in trees]}


@tool("write")
def tag_solids(handles: list[str] | None = None, part: str = "", material: str = "", props: dict | None = None,
               rows: list[dict] | None = None) -> dict:
    """Set the non-graphic data kept on solids and exported to IFC: part name, material and extra fields
    (e.g. {"structure": "CH4X4", "station": "Km8+423.31", "type": "Cống hộp 4x4", "diameter": "D1000"}).
    Empty arguments keep the current values; props are merged.
    rows: different values per solid, one undo step: [{"handle": "2A1", "name": "Tường đầu 1", "part": ..., "material": ...,
    "props": {"structure": ..., "Mác": "M300"}}]. Only the keys given are changed, "" clears. name = IFC Name (default: from part)."""
    if not handles and not rows:
        raise UserError("Cần handles hoặc rows.")
    for r in rows or []:
        for k in (r.get("props") or {}):
            if not str(k).strip() or len(str(k)) > 60:
                raise UserError(f"Tên thông tin không hợp lệ: '{k}' (1 đến 60 ký tự).")
        if any(len(str(v)) > 500 for v in [r.get("name") or "", r.get("part") or "", r.get("material") or "", *(r.get("props") or {}).values()]):
            raise UserError("Mỗi giá trị tối đa 500 ký tự.")
    if rows:
        with editing() as d:
            ents = [(by_handle(d, r["handle"]), r) for r in rows]      # a wrong handle stops before anything is written
            for e, r in ents:
                if etype(e) != "3dSolid":
                    raise UserError(f"{r['handle']} không phải khối 3D.")
            n, failed = 0, []
            for e, r in ents:
                rec = meta.read(e) or {"v": 1, "part": "", "props": {}}
                for key in ("name", "part", "material"):
                    if key in r:
                        if str(r[key] or "").strip():
                            rec[key] = str(r[key]).strip()
                        else:
                            rec.pop(key, None)
                rec.setdefault("part", "")
                p = rec.setdefault("props", {})
                for key, v in (r.get("props") or {}).items():
                    key = str(key).strip()
                    if str(v if v is not None else "").strip():
                        p[key] = str(v).strip()
                    else:
                        p.pop(key, None)
                if "chk" not in rec:
                    rec["chk"] = meta.check_of(e)
                try:
                    meta.write(e, rec, d)
                    n += 1
                except Exception:      # e.g. more than the 16 KB a CAD object can carry
                    failed.append(r["handle"])
            return done(d, tagged=n, failed=failed)
    with editing() as d:
        n = 0
        for h in handles:
            e = by_handle(d, h)
            rec = meta.read(e) or {"v": 1, "part": "", "props": {}}
            if part:
                rec["part"] = part
            if material:
                rec["material"] = material
            if props:
                rec.setdefault("props", {}).update({k: v for k, v in props.items() if v not in (None, "")})
            if "chk" not in rec:
                rec["chk"] = meta.check_of(e)
            meta.write(e, rec, d)
            n += 1
        return done(d, tagged=n)


@tool("write")
def organize_layers(structure: str, station: str = "", handles: list[str] | None = None, from_layer: str = "",
                    pattern: str = "{structure}_{station}_{part}") -> dict:
    """Put each solid on a layer named after the structure, its station and its part, e.g.
    'CONG-HOP-4X4_KM8+423.31_TUONG-DAU-HA-LUU' (ASCII, valid layer names). structure = culvert name or size
    (e.g. 'Cống hộp 4x4', 'D1000'); station = lý trình. Also stores structure/station on the solids for IFC.
    Colors stay on the objects. Default: every 3D solid in the drawing (or those on from_layer)."""
    with editing() as d:
        ents = _solids(d, handles, from_layer)
        if not ents:
            raise UserError("Không có khối 3D nào để đặt layer.")
        made: dict[str, int] = {}
        for e in ents:
            rec = meta.read(e) or {"v": 1, "part": "", "props": {}}
            part = part_short(rec.get("part") or "") or "KHOI"
            name = layer_safe(pattern.format(structure=structure, station=station, part=part).replace("__", "_").strip("_"))
            ensure_layer(d, name)
            col = g(e, "Color")
            e.Layer = name
            if col is not None and col != 256:
                e.Color = col
            rec.setdefault("props", {}).update({"structure": structure, "station": station} if station else {"structure": structure})
            if "chk" not in rec:
                rec["chk"] = meta.check_of(e)
            meta.write(e, rec, d)
            made[name] = made.get(name, 0) + 1
        return done(d, layers=made)


@tool("write")
def place_on_site(local_point: list[float], site_point: list[float], azimuth_deg: float | None = None,
                  local_point2: list[float] | None = None, site_point2: list[float] | None = None,
                  handles: list[str] | None = None, from_layer: str = "") -> dict:
    """Move a model built in local coordinates to its real position (VN-2000 / project coordinates).
    local_point -> site_point (x, y, z: z sets the elevation shift). Rotation in plan either by azimuth_deg
    (counter-clockwise angle to turn the model, degrees) or by a second pair local_point2 -> site_point2
    (like ALIGN: the direction local_point->local_point2 is turned onto site_point->site_point2; no scaling).
    Default objects: every 3D solid (or those on from_layer). Recipes for IFC follow the move."""
    lp = (list(map(float, local_point)) + [0, 0])[:3]
    sp = (list(map(float, site_point)) + [0, 0])[:3]
    if local_point2 is not None and site_point2 is not None:
        a1 = math.atan2(local_point2[1] - lp[1], local_point2[0] - lp[0])
        a2 = math.atan2(site_point2[1] - sp[1], site_point2[0] - sp[0])
        ang = a2 - a1
    else:
        ang = math.radians(azimuth_deg or 0.0)
    with editing() as d:
        ents = [by_handle(d, h) for h in handles] if handles else _solids(d, None, from_layer)
        if not ents:
            raise UserError("Không có đối tượng nào để di chuyển.")
        A, t = meta.rot_z(lp, ang)
        A2, t2 = meta.translate([sp[i] - lp[i] for i in range(3)])
        for e in ents:
            if abs(ang) > 1e-12:
                e.Rotate(vpt(lp), ang)
            e.Move(vpt(lp), vpt(sp))
            rec = meta.read(e)
            if rec and "geo" in rec:
                rec["geo"] = meta.transform_node(meta.transform_node(rec["geo"], A, t), A2, t2)
                meta.stamp(e, rec, d)
        return done(d, moved=len(ents), rotation_deg=r3(math.degrees(ang), 6))


# ---------------------------------------------------------------- IFC writer
_B64 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_$"


def ifc_guid() -> str:
    n = uuid.uuid4().int
    out = [_B64[(n >> 126) & 0x3]]
    for i in range(21):
        out.append(_B64[(n >> (120 - 6 * i)) & 0x3F])
    return "".join(out)


def s_(text) -> str:
    if text is None:
        return "$"
    out = []
    for ch in str(text):
        if ch == "'":
            out.append("''")
        elif ch == "\\":
            out.append("\\\\")
        elif 32 <= ord(ch) < 127:
            out.append(ch)
        else:
            out.append("\\X2\\%04X\\X0\\" % ord(ch) if ord(ch) < 0x10000 else "?")
    return "'" + "".join(out) + "'"


def f_(v: float) -> str:
    v = 0.0 if abs(v) < 1e-12 else float(v)
    t = ("%.6f" % v).rstrip("0")
    return t if not t.endswith("-.") else "0."


class Step:
    def __init__(self):
        self.lines: list[str] = []

    def add(self, txt: str) -> str:
        self.lines.append(txt)
        return f"#{len(self.lines)}"

    def pt3(self, p, k=1.0):
        return self.add(f"IFCCARTESIANPOINT(({f_(p[0] * k)},{f_(p[1] * k)},{f_(p[2] * k)}));")

    def pt2(self, p, k=1.0):
        return self.add(f"IFCCARTESIANPOINT(({f_(p[0] * k)},{f_(p[1] * k)}));")

    def dir3(self, v):
        return self.add(f"IFCDIRECTION(({f_(v[0])},{f_(v[1])},{f_(v[2])}));")

    def a2p3(self, o, z, x, k=1.0):
        return self.add(f"IFCAXIS2PLACEMENT3D({self.pt3(o, k)},{self.dir3(z)},{self.dir3(x)});")


def _cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def _dot(a, b):
    return sum(a[i] * b[i] for i in range(3))


def _unit(v):
    n = math.sqrt(_dot(v, v)) or 1.0
    return [c / n for c in v]


def _perp(n):
    a = [1.0, 0.0, 0.0] if abs(n[0]) < 0.9 else [0.0, 1.0, 0.0]
    return _unit(_cross(n, a))


def _bbox(e):
    """GetBoundingBox, repaired: for coordinates over 1 000 000 ZWCAD 2026 answers exactly 1000000 as the minimum."""
    lo, hi = e.GetBoundingBox()
    lo, hi = list(lo), list(hi)
    cen = list(g(e, "Centroid") or [(a + b) / 2 for a, b in zip(lo, hi)])
    for i in range(3):
        if lo[i] == 1000000.0 and hi[i] > 1000000.0 and cen[i] - lo[i] > 4 * (hi[i] - cen[i]):
            lo[i] = 2 * cen[i] - hi[i]
    return lo, hi


def _record(e, k) -> dict:
    """What culvert.build and the IFC writer need to know about one solid (volume in m3)."""
    rec = meta.read(e) or {}
    props = dict(rec.get("props") or {})
    part = rec.get("part") or ""
    return {"handle": g(e, "Handle"), "layer": g(e, "Layer") or "", "name": rec.get("name") or "", "part": part,
            "material": rec.get("material") or meta.guess_material(part) or "", "structure": str(props.pop("structure", "") or ""),
            "station": str(props.pop("station", "") or ""), "type": str(props.pop("type", "") or ""), "group": str(props.pop("group", "") or ""),
            "extra": {str(a): v for a, v in props.items()}, "cen": [x * k for x in (g(e, "Centroid") or ())] or None, "vol": (g(e, "Volume") or 0.0) * k ** 3, "geo": rec.get("geo"),
            "near": not ("geo" in rec and meta.is_current(e, rec))}


def unit_hint(ents, ins) -> str:
    """'m' when the drawing says mm or cm but its solids are far too small for that (drawn in metres)."""
    if ins not in (4, 5) or not ents:
        return ""
    import statistics
    return "m" if statistics.median((g(e, "Volume") or 0.0) for e in ents) < 2000 else ""


UNITS = {"m": 1.0, "mm": 0.001, "cm": 0.01, "ft": 0.3048, "us-ft": 1200 / 3937, "inch": 0.0254}


def _box(st: Step, lo, hi, k) -> str:
    """The box around a solid as a real solid: many viewers do not draw IFCBOUNDINGBOX."""
    sx, sy, sz = (max((hi[i] - lo[i]) * k, 1e-4) for i in range(3))
    ax = st.add(f"IFCAXIS2PLACEMENT2D({st.pt2([0.0, 0.0])},$);")
    prof = st.add(f"IFCRECTANGLEPROFILEDEF(.AREA.,$,{ax},{f_(sx)},{f_(sy)});")
    pl = st.a2p3([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]], [0, 0, 1], [1, 0, 0], k)
    return st.add(f"IFCEXTRUDEDAREASOLID({prof},{pl},{st.dir3([0, 0, 1])},{f_(sz)});")


def _geo(st: Step, node, k) -> tuple[str, str]:
    """IFC item for a recipe node -> (#id, representation type)."""
    t = node.get("t")
    if t == "ext":
        X, Y, E = _unit(node["X"]), _unit(node["Y"]), _unit(node["E"])
        yi = _cross(E, X)
        flip = _dot(yi, Y) < 0
        curves = []
        for lp in node["loops"]:
            pts = [[p[0], -p[1] if flip else p[1]] for p in lp]
            ids = [st.pt2(p, k) for p in pts]
            curves.append(st.add(f"IFCPOLYLINE(({','.join(ids + [ids[0]])}));"))
        if len(curves) == 1:
            prof = st.add(f"IFCARBITRARYCLOSEDPROFILEDEF(.AREA.,$,{curves[0]});")
        else:
            prof = st.add(f"IFCARBITRARYPROFILEDEFWITHVOIDS(.AREA.,$,{curves[0]},({','.join(curves[1:])}));")
        o = [node["o"][i] + E[i] * node["lo"] for i in range(3)]
        pl = st.a2p3(o, E, X, k)
        return st.add(f"IFCEXTRUDEDAREASOLID({prof},{pl},{st.dir3([0, 0, 1])},{f_((node['hi'] - node['lo']) * k)});"), "SweptSolid"
    if t == "bool":
        a, _ = _geo(st, node["a"], k)
        op = {"union": ".UNION.", "intersect": ".INTERSECTION.", "subtract": ".DIFFERENCE."}[node["op"]]
        for b in node["b"]:
            bi, _ = _geo(st, b, k)
            a = st.add(f"IFCBOOLEANRESULT({op},{a},{bi});")
        return a, "CSG"
    if t == "clip":
        a, rt = _geo(st, node["n"], k)
        nrm = _unit(node["nrm"])
        plane = st.add(f"IFCPLANE({st.a2p3(node['p'], nrm, _perp(nrm), k)});")
        # keep 'back' (opposite the normal): remove the half space on the normal side -> material on that side
        flag = ".T." if node.get("keep") == "front" else ".F."
        hs = st.add(f"IFCHALFSPACESOLID({plane},{flag});")
        if rt == "SweptSolid" or rt == "Clipping":
            return st.add(f"IFCBOOLEANCLIPPINGRESULT(.DIFFERENCE.,{a},{hs});"), "Clipping"
        return st.add(f"IFCBOOLEANRESULT(.DIFFERENCE.,{a},{hs});"), "CSG"
    raise ValueError("unknown node")


@tool()
def export_ifc(path: str, schema: str = "IFC4", handles: list[str] | None = None, from_layer: str = "",
               units: str = "m", project: str = "", site: str = "", road: str = "", author: str = "",
               selection_only: bool = False, preview: bool = False, detail: str = "part",
               groups: list[list[str]] | None = None, split: bool = False) -> dict:
    """Export 3D solids to an IFC file with basic non-graphic data.
    schema: IFC4 or IFC4X3 (IFC 4.3: elements placed in an IfcRoad under the site).
    Geometry is exact (extrusions, booleans, clipping) for solids built with the Steve CAD tools; solids edited
    by other means are exported as a box around them and listed in the result. Only 3D solids are exported.
    preview=True writes nothing: counts of exact / approximate solids, by layer. selection_only: the user's selection.
    Relative paths go to the Steve-CAD-AI folder.
    One tree per structure (props.structure + station): structure (with segments, lengths, clear size or diameter, wall, volumes
    by material) > group (Thân cống, Móng thân cống, Cửa thượng lưu, Cửa hạ lưu; props.group overrides) > part.
    detail="part": equal parts are ONE element (e.g. 22 segments x 2 m); "solid": one element per solid. Elements are
    IfcPipeSegment(CULVERT), IfcWall, IfcSlab, IfcFooting or a proxy, with Pset_SteveCAD, Qto, material and colour.
    Levels, slope, azimuth and skew of each culvert are computed from its solids (left out when they cannot be).
    groups: export only these structures, each given by the handles of its solids (solid_info(...).structures[].handles).
    split=True: one file per structure, named <path>_<structure>_<station>.ifc; existing files are never replaced.
    units = drawing units: m | mm | cm | ft | us-ft | inch."""
    a = dict(schema=schema, units=units, project=project, site=site, road=road, author=author, detail=detail)
    if preview or (not groups and not split):
        return _export(path, handles=handles, from_layer=from_layer, selection_only=selection_only, preview=preview, **a)
    if not split:
        return _export(path, handles=[h for g_ in groups for h in g_], **a)
    k = UNITS.get(units.lower())
    if k is None:
        raise UserError("units phải là m, mm, cm, ft, us-ft hoặc inch.")
    d = C.drawings.target()
    ents = [by_handle(d, h) for g_ in groups for h in g_] if groups else _scope(d, handles, from_layer, selection_only)
    if not ents:
        raise UserError("Không có khối 3D (solid) nào để xuất.")
    full = os.path.abspath(path if os.path.isabs(path) else os.path.join(WORKSPACE, path))
    stem = full[:-4] if full.lower().endswith(".ifc") else full
    jobs, used = [], set()
    for c in culvert.build([_record(e, k) for e in ents], k):
        base = re.sub(r"[^A-Za-z0-9+._-]+", "-", ascii_name(c["key"])).strip("-.")[:80] or "cong"
        nm, n = base, 2
        while nm.lower() in used:
            nm, n = f"{base}-{n}", n + 1
        used.add(nm.lower())
        jobs.append((f"{stem}_{nm}.ifc", [s["handle"] for s in c["solids"]]))
    old = [os.path.basename(p) for p, _ in jobs if os.path.exists(p)]
    if old:
        raise UserError("Đã có file: " + ", ".join(old[:5]) + ". Chọn tên khác hoặc xoá file cũ.")
    rs = [_export(p, handles=hs, **a) for p, hs in jobs]
    return {"ok": True, "path": rs[0]["path"], "files": [r["path"] for r in rs], "schema": rs[0]["schema"], "elements": sum(r["elements"] for r in rs),
            "exact": sum(r["exact"] for r in rs), "bounding_box_only": [h for r in rs for h in r["bounding_box_only"]],
            "structures": {t: n for r in rs for t, n in r["structures"].items()}, "size_kb": round(sum(r["size_kb"] for r in rs), 1)}


def _export(path, schema="IFC4", handles=None, from_layer="", units="m", project="", site="", road="", author="",
            selection_only=False, preview=False, detail="part") -> dict:
    schema = schema.upper().replace(".", "").replace("_", "")
    sch = {"IFC4": "IFC4", "IFC43": "IFC4X3_ADD2", "IFC4X3": "IFC4X3_ADD2", "IFC4X3ADD2": "IFC4X3_ADD2"}.get(schema)
    if not sch:
        raise UserError("schema phải là IFC4 hoặc IFC4X3.")
    k = UNITS.get(units.lower())
    if k is None:
        raise UserError("units phải là m, mm, cm, ft, us-ft hoặc inch.")
    path = os.path.abspath(path if os.path.isabs(path) else os.path.join(WORKSPACE, path))
    if not path.lower().endswith(".ifc"):
        path += ".ifc"
    d = C.drawings.target()
    ents = _scope(d, handles, from_layer, selection_only)
    if not ents:
        raise UserError("Không có khối 3D (solid) nào để xuất" + (" trong vùng chọn." if selection_only else "."))
    if detail not in ("part", "solid"):
        raise UserError("detail phải là part hoặc solid.")
    if preview:
        by, exact = {}, 0
        for e in ents:
            rec = meta.read(e) or {}
            ok = "geo" in rec and meta.is_current(e, rec)
            exact += ok
            row = by.setdefault(g(e, "Layer") or "", [0, 0, 0.0])
            row[0] += 1
            row[1] += not ok
            row[2] += (g(e, "Volume") or 0.0) * k ** 3
        return {"preview": True, "elements": len(ents), "exact": exact, "approximate": len(ents) - exact,
                "layers": [{"layer": n, "solids": v[0], "approximate": v[1], "volume_m3": round(v[2], 3)} for n, v in sorted(by.items())]}
    st = Step()
    origin = st.a2p3([0, 0, 0], [0, 0, 1], [1, 0, 0])
    ctx = st.add(f"IFCGEOMETRICREPRESENTATIONCONTEXT($,'Model',3,1.E-05,{origin},$);")
    body = st.add(f"IFCGEOMETRICREPRESENTATIONSUBCONTEXT('Body','Model',*,*,*,*,{ctx},$,.MODEL_VIEW.,$);")
    u = [st.add("IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.);"), st.add("IFCSIUNIT(*,.AREAUNIT.,$,.SQUARE_METRE.);"),
         st.add("IFCSIUNIT(*,.VOLUMEUNIT.,$,.CUBIC_METRE.);"), st.add("IFCSIUNIT(*,.PLANEANGLEUNIT.,$,.RADIAN.);")]
    ua = st.add(f"IFCUNITASSIGNMENT(({','.join(u)}));")
    dname = g(d, "Name") or "model"
    proj = st.add(f"IFCPROJECT('{ifc_guid()}',$,{s_(project or os.path.splitext(dname)[0])},$,$,$,$,({ctx}),{ua});")
    site_pl = st.add(f"IFCLOCALPLACEMENT($,{origin});")
    site_id = st.add(f"IFCSITE('{ifc_guid()}',$,{s_(site or 'Site')},$,$,{site_pl},$,$,.ELEMENT.,$,$,$,$,$);")
    st.add(f"IFCRELAGGREGATES('{ifc_guid()}',$,$,$,{proj},({site_id}));")
    holder, holder_pl = site_id, site_pl
    if sch != "IFC4":
        holder_pl = st.add(f"IFCLOCALPLACEMENT({site_pl},{st.a2p3([0, 0, 0], [0, 0, 1], [1, 0, 0])});")
        holder = st.add(f"IFCROAD('{ifc_guid()}',$,{s_(road or 'Road')},$,$,{holder_pl},$,$,.ELEMENT.,.NOTDEFINED.);")
        st.add(f"IFCRELAGGREGATES('{ifc_guid()}',$,$,$,{site_id},({holder}));")

    mats: dict[str, list[str]] = {}
    styles: dict[int, str] = {}
    approx, n_ok, recs = [], 0, []
    for e in ents:
        q = _record(e, k)
        q["col"] = g(e, "Color")
        if q["col"] in (None, 256):
            try:
                q["col"] = d.Layers.Item(e.Layer).Color
            except Exception:
                q["col"] = 7
        if not q["near"]:
            q["item"], q["rtype"] = _geo(st, q["geo"], k)
            n_ok += 1
        else:
            lo, hi = _bbox(e)
            q["item"], q["rtype"] = _box(st, lo, hi, k), "SweptSolid"
            approx.append(q["handle"])
        col = q["col"]
        if col not in styles:
            r, gg, b = aci_rgb(col)
            rgb = st.add(f"IFCCOLOURRGB($,{f_(r / 255)},{f_(gg / 255)},{f_(b / 255)});")
            shade = st.add(f"IFCSURFACESTYLESHADING({rgb},0.);")
            styles[col] = st.add(f"IFCSURFACESTYLE($,.BOTH.,({shade}));")
        st.add(f"IFCSTYLEDITEM({q['item']},({styles[col]}),$);")
        recs.append(q)

    def place():
        return st.add(f"IFCLOCALPLACEMENT({holder_pl},{st.a2p3([0, 0, 0], [0, 0, 1], [1, 0, 0])});")

    def pset(el, name, fields):
        """fields: (name, value, kind) with kind text | len | vol | int | bool; empty text is left out"""
        pv = []
        for n, v, kind in fields:
            if v in (None, ""):
                continue
            t = {"text": lambda: f"IFCLABEL({s_(str(v)[:255])})", "len": lambda: f"IFCLENGTHMEASURE({f_(v)})", "vol": lambda: f"IFCVOLUMEMEASURE({f_(v)})",
                 "int": lambda: f"IFCINTEGER({int(v)})", "real": lambda: f"IFCREAL({f_(v)})", "bool": lambda: f"IFCBOOLEAN({'.T.' if v else '.F.'})"}[kind]()
            pv.append(st.add(f"IFCPROPERTYSINGLEVALUE({s_(n)},$,{t},$);"))
        if pv:
            ps = st.add(f"IFCPROPERTYSET('{ifc_guid()}',$,{s_(name)},$,({','.join(pv)}));")
            st.add(f"IFCRELDEFINESBYPROPERTIES('{ifc_guid()}',$,$,$,({el}),{ps});")

    def qto(el, vol, count=None, length=None):
        ql = [st.add(f"IFCQUANTITYVOLUME('NetVolume',$,$,{f_(vol)},$);")]
        if count:
            ql.append(st.add(f"IFCQUANTITYCOUNT('Count',$,$,{int(count)}{'.' if sch == 'IFC4' else ''},$);"))
        if length:
            ql.append(st.add(f"IFCQUANTITYLENGTH('Length',$,$,{f_(length)},$);"))
        qs = st.add(f"IFCELEMENTQUANTITY('{ifc_guid()}',$,'Qto_SteveCAD',$,$,({','.join(ql)}));")
        st.add(f"IFCRELDEFINESBYPROPERTIES('{ifc_guid()}',$,$,$,({el}),{qs});")

    def element(qs, name, desc, otype, tag):
        kinds = {q["rtype"] for q in qs}
        rep = st.add(f"IFCSHAPEREPRESENTATION({body},'Body',{s_(kinds.pop() if len(kinds) == 1 else 'SolidModel')},({','.join(q['item'] for q in qs)}));")
        pds = st.add(f"IFCPRODUCTDEFINITIONSHAPE($,$,({rep}));")
        cls, pre = culvert.ifc_class(qs[0])
        el = st.add(f"{cls}('{ifc_guid()}',$,{s_(name)},{s_(desc)},{s_(otype)},{place()},{pds},{s_(tag)},.{pre}.);")
        if qs[0]["material"]:
            mats.setdefault(qs[0]["material"], []).append(el)
        return el

    def solid_fields(q):
        base = [("Công trình", q["structure"], "text"), ("Lý trình", q["station"], "text"), ("Loại", q["type"], "text"), ("Nhóm", culvert.group_of(q), "text"),
                ("Tên", q["name"], "text"), ("Bộ phận", q["part"], "text"), ("Vật liệu", q["material"], "text"), ("Layer", q["layer"], "text"),
                ("Handle CAD", q["handle"], "text"), ("Nguồn", dname, "text")]
        base += [(kk, vv, "text") for kk, vv in q["extra"].items()]
        return base + [("Màu ACI", q["col"], "int"), ("Thể tích", q["vol"], "vol"), ("Hình học gần đúng", q["near"], "bool")]

    def assembly(name, desc, otype, kids):
        a = st.add(f"IFCELEMENTASSEMBLY('{ifc_guid()}',$,{s_(name)},{s_(desc) if desc else '$'},{s_(otype)},{place()},$,$,.SITE.,.USERDEFINED.);")
        st.add(f"IFCRELAGGREGATES('{ifc_guid()}',$,$,$,{a},({','.join(kids)}));")
        return a

    tops, trees = [], culvert.build(recs, k)
    for c in trees:
        gels = []
        for grp in c["groups"]:
            kids = []
            for p in grp["parts"]:
                ss, seg = p["solids"], p.get("segment_length")
                if detail == "solid":
                    for q in ss:
                        el = element([q], q["name"] or p["name"], q["part"] or p["name"], p["name"], q["handle"])
                        pset(el, "Pset_SteveCAD", solid_fields(q))
                        qto(el, q["vol"], None, seg)
                        kids.append(el)
                    continue
                label = p["name"] + (f" ({p['count']} {'đốt' if grp['name'] == culvert.BARREL else 'khối'}" + (f" x {culvert.num(seg)} m" if seg else "") + ")" if p["count"] > 1 else "")
                el = element(ss, ss[0]["name"] if p["count"] == 1 and ss[0]["name"] else label, ss[0]["part"] if p["count"] == 1 else label, p["name"], ",".join(q["handle"] for q in ss)[:250])
                common = {n: v for n, v in ss[0]["extra"].items() if all(q["extra"].get(n) == v for q in ss)}
                pset(el, "Pset_SteveCAD", [("Công trình", c["structure"], "text"), ("Lý trình", c["station"], "text"), ("Nhóm", grp["name"], "text"), ("Bộ phận", p["name"], "text"),
                     ("Vật liệu", p["material"], "text"), ("Số lượng", p["count"], "int"), ("Chiều dài một đốt", seg, "len"), ("Tổng chiều dài", seg * p["count"] if seg else None, "len"),
                     ("Khẩu độ rộng", p.get("clear_w"), "len"), ("Khẩu độ cao", p.get("clear_h"), "len"), ("Đường kính trong", p.get("inner_d"), "len"), ("Đường kính ngoài", p.get("outer_d"), "len"),
                     ("Chiều dày thành", p.get("wall"), "len"), ("Thể tích", p["volume"], "vol"), ("Số khối hình học gần đúng", p["approximate"], "int"), ("Hình học gần đúng", p["approximate"] > 0, "bool"), ("Nguồn", dname, "text")]
                     + [(n, v, "text") for n, v in common.items()])
                qto(el, p["volume"], p["count"], seg * p["count"] if seg else None)
                kids.append(el)
            a = assembly(grp["name"], "", "Nhóm bộ phận", kids)
            qto(a, grp["volume"], grp["count"])
            gels.append(a)
        b = c["barrel"]
        top = assembly(c["key"], c["title"], "CULVERT" if b else (c["type"] or "Công trình"), gels)
        pset(top, "Pset_SteveCAD_CongTrinh", [("Công trình", c["structure"], "text"), ("Loại", c["type"], "text"), ("Lý trình", c["station"], "text"), ("Số đốt", b.get("segments"), "int"),
             ("Chiều dài một đốt", b.get("segment_length"), "len"), ("Chiều dài thân cống", b.get("length"), "len"), ("Khẩu độ rộng", b.get("clear_w"), "len"), ("Khẩu độ cao", b.get("clear_h"), "len"),
             ("Đường kính trong", b.get("inner_d"), "len"), ("Đường kính ngoài", b.get("outer_d"), "len"), ("Chiều dày thành", b.get("wall"), "len"), ("Số khoang", c["geo"].get("cells"), "int"), ("Số hàng ống", c["geo"].get("lanes"), "int"),
             ("Chiều dài thật", c["geo"].get("length_true"), "len"), ("Chiều dài trên mặt bằng", c["geo"].get("length_plan"), "len"),
             ("Cao độ đáy trong thượng lưu", c["geo"].get("z_up"), "len"), ("Cao độ đáy trong hạ lưu", c["geo"].get("z_down"), "len"), ("Độ dốc (%)", c["geo"].get("slope"), "real"),
             ("Phương vị trục cống (độ)", c["geo"].get("azimuth"), "real"), ("Góc chéo (độ)", c["geo"].get("skew"), "real"), ("Góc chéo tính theo", c["geo"].get("skew_from"), "text"),
             ("Ghi chú tính toán", "; ".join(c["geo"]["notes"]), "text"), ("Tổng số khối", c["count"], "int"),
             ("Tổng thể tích", c["volume"], "vol")] + [("Thể tích " + m, v, "vol") for m, v in sorted(c["by_material"].items())])
        qto(top, c["volume"], None, b.get("length"))
        tops.append(top)
    for mname, els in mats.items():
        m = st.add(f"IFCMATERIAL({s_(mname)},$,$);")
        st.add(f"IFCRELASSOCIATESMATERIAL('{ifc_guid()}',$,$,$,({','.join(els)}),{m});")
    st.add(f"IFCRELCONTAINEDINSPATIALSTRUCTURE('{ifc_guid()}',$,$,$,({','.join(tops)}),{holder});")

    now = datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    head = ["ISO-10303-21;", "HEADER;",
            "FILE_DESCRIPTION(('ViewDefinition [DesignTransferView]'),'2;1');",
            f"FILE_NAME({s_(os.path.basename(path))},'{now}',({s_(author or 'Steve AI Connect')}),(''),"
            f"'Steve CAD MCP {__version__}','Steve CAD MCP {__version__}','');",
            f"FILE_SCHEMA(('{sch}'));", "ENDSEC;", "DATA;"]
    body_lines = [f"#{i + 1}= {ln}" for i, ln in enumerate(st.lines)]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(head + body_lines + ["ENDSEC;", "END-ISO-10303-21;", ""]))
    return {"ok": True, "path": path, "schema": sch, "elements": len(ents), "exact": n_ok,
            "bounding_box_only": approx, "structures": {c["title"]: c["count"] for c in trees},
            "materials": list(mats), "size_kb": round(os.path.getsize(path) / 1024, 1)}
