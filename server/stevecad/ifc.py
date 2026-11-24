"""Site placement, automatic layers and IFC export (IFC4 / IFC4X3) with basic non-graphic data."""
from __future__ import annotations

import datetime
import math
import os
import re
import unicodedata
import uuid

from . import __version__, meta
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
@tool("write")
def tag_solids(handles: list[str], part: str = "", material: str = "", props: dict | None = None) -> dict:
    """Set the non-graphic data kept on solids and exported to IFC: part name, material and extra fields
    (e.g. {"structure": "CH4X4", "station": "Km8+423.31", "type": "Cống hộp 4x4", "diameter": "D1000"}).
    Empty arguments keep the current values; props are merged."""
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
               selection_only: bool = False, preview: bool = False) -> dict:
    """Export 3D solids to an IFC file with basic non-graphic data.
    schema: IFC4 or IFC4X3 (IFC 4.3: elements placed in an IfcRoad under the site).
    Geometry is exact (extrusions, booleans, clipping) for solids built with the Steve CAD tools; solids edited
    by other means are exported as a box around them and listed in the result. Only 3D solids are exported.
    preview=True writes nothing: counts of exact / approximate solids, by layer. selection_only: the user's selection.
    Relative paths go to the Steve-CAD-AI folder.
    Each structure (props.structure + station) becomes an IfcElementAssembly; each solid an
    IfcBuildingElementProxy with: name = part, material, color, Pset_SteveCAD (Công trình, Lý trình, Loại, Bộ phận,
    Vật liệu, Layer, Màu ACI...) and Qto (NetVolume). units = drawing units: m | mm | cm | ft | us-ft | inch."""
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
    if selection_only:
        sel = list(selection_handles(d))
        ents = [e for e in sel if etype(e) == "3dSolid" and (not from_layer or (g(e, "Layer") or "").lower() == from_layer.lower())]
    else:
        ents = _solids(d, handles, from_layer)
    if not ents:
        raise UserError("Không có khối 3D (solid) nào để xuất" + (" trong vùng chọn." if selection_only else "."))
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

    groups: dict[str, list[str]] = {}
    mats: dict[str, list[str]] = {}
    styles: dict[int, str] = {}
    approx, n_ok = [], 0
    for e in ents:
        rec = meta.read(e) or {"part": "", "props": {}}
        props = rec.get("props") or {}
        part = rec.get("part") or etype(e)
        col = g(e, "Color")
        if col in (None, 256):
            try:
                col = d.Layers.Item(e.Layer).Color
            except Exception:
                col = 7
        vol = (g(e, "Volume") or 0.0) * k ** 3
        near = False
        if "geo" in rec and meta.is_current(e, rec):
            item, rtype = _geo(st, rec["geo"], k)
            n_ok += 1
        else:
            lo, hi = e.GetBoundingBox()
            item, rtype = _box(st, lo, hi, k), "SweptSolid"
            near = True
            approx.append(g(e, "Handle"))
        if col not in styles:
            r, gg, b = aci_rgb(col)
            rgb = st.add(f"IFCCOLOURRGB($,{f_(r / 255)},{f_(gg / 255)},{f_(b / 255)});")
            shade = st.add(f"IFCSURFACESTYLESHADING({rgb},0.);")
            styles[col] = st.add(f"IFCSURFACESTYLE($,.BOTH.,({shade}));")
        st.add(f"IFCSTYLEDITEM({item},({styles[col]}),$);")
        rep = st.add(f"IFCSHAPEREPRESENTATION({body},'Body',{s_(rtype)},({item}));")
        pds = st.add(f"IFCPRODUCTDEFINITIONSHAPE($,$,({rep}));")
        pl = st.add(f"IFCLOCALPLACEMENT({holder_pl},{st.a2p3([0, 0, 0], [0, 0, 1], [1, 0, 0])});")
        el = st.add(f"IFCBUILDINGELEMENTPROXY('{ifc_guid()}',$,{s_(part_short(part))},{s_(part)},{s_(part_short(part))},{pl},{pds},{s_(g(e, 'Handle'))},.USERDEFINED.);")
        material = rec.get("material") or meta.guess_material(part) or ""
        fields = [("Công trình", props.get("structure")), ("Lý trình", props.get("station")), ("Loại", props.get("type")),
                  ("Bộ phận", part), ("Vật liệu", material), ("Layer", g(e, "Layer")), ("Handle CAD", g(e, "Handle")),
                  ("Nguồn", dname)]
        fields += [(str(kk), vv) for kk, vv in props.items() if kk not in ("structure", "station", "type")]
        pv = [st.add(f"IFCPROPERTYSINGLEVALUE({s_(n)},$,IFCLABEL({s_(v)}),$);") for n, v in fields if v not in (None, "")]
        pv.append(st.add(f"IFCPROPERTYSINGLEVALUE({s_('Màu ACI')},$,IFCINTEGER({int(col)}),$);"))
        pv.append(st.add(f"IFCPROPERTYSINGLEVALUE({s_('Thể tích')},$,IFCVOLUMEMEASURE({f_(vol)}),$);"))
        pv.append(st.add(f"IFCPROPERTYSINGLEVALUE({s_('Hình học gần đúng')},$,IFCBOOLEAN({'.T.' if near else '.F.'}),$);"))
        ps = st.add(f"IFCPROPERTYSET('{ifc_guid()}',$,'Pset_SteveCAD',$,({','.join(pv)}));")
        st.add(f"IFCRELDEFINESBYPROPERTIES('{ifc_guid()}',$,$,$,({el}),{ps});")
        q = st.add(f"IFCQUANTITYVOLUME('NetVolume',$,$,{f_(vol)},$);")
        qs = st.add(f"IFCELEMENTQUANTITY('{ifc_guid()}',$,'Qto_SteveCAD',$,$,({q}));")
        st.add(f"IFCRELDEFINESBYPROPERTIES('{ifc_guid()}',$,$,$,({el}),{qs});")
        if material:
            mats.setdefault(material, []).append(el)
        key = " ".join(x for x in (props.get("structure"), props.get("station")) if x) or "Công trình"
        groups.setdefault(key, []).append(el)
    for mname, els in mats.items():
        m = st.add(f"IFCMATERIAL({s_(mname)},$,$);")
        st.add(f"IFCRELASSOCIATESMATERIAL('{ifc_guid()}',$,$,$,({','.join(els)}),{m});")
    assemblies = []
    for gname, els in groups.items():
        apl = st.add(f"IFCLOCALPLACEMENT({holder_pl},{st.a2p3([0, 0, 0], [0, 0, 1], [1, 0, 0])});")
        asm = st.add(f"IFCELEMENTASSEMBLY('{ifc_guid()}',$,{s_(gname)},$,$,{apl},$,$,.SITE.,.USERDEFINED.);")
        st.add(f"IFCRELAGGREGATES('{ifc_guid()}',$,$,$,{asm},({','.join(els)}));")
        assemblies.append(asm)
    st.add(f"IFCRELCONTAINEDINSPATIALSTRUCTURE('{ifc_guid()}',$,$,$,({','.join(assemblies)}),{holder});")

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
            "bounding_box_only": approx, "structures": {kk: len(v) for kk, v in groups.items()},
            "materials": list(mats), "size_kb": round(os.path.getsize(path) / 1024, 1)}
