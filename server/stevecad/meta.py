"""Non-graphic data + "build recipe" stored on each solid (XData, app STEVECAD).

The recipe describes how a solid was built (extrusion of profile loops, booleans, clipping) in world coordinates.
It travels with copies, is updated by our move/rotate/mirror/scale/place tools, and lets export_ifc write exact
parametric IFC geometry (IfcExtrudedAreaSolid, IfcBooleanResult, IfcHalfSpaceSolid). A check (volume + centroid)
detects solids edited outside our tools; those are exported as a bounding box and reported."""
from __future__ import annotations

import json
import math
import re

import pythoncom
import win32com.client

from .drawing import g

APP = "STEVECAD"


# ---------------------------------------------------------------- xdata
def _ensure_app(doc):
    try:
        doc.RegisteredApplications.Item(APP)
    except Exception:
        doc.RegisteredApplications.Add(APP)


def read(e) -> dict | None:
    try:
        _, vals = e.GetXData(APP)
    except Exception:
        return None
    if not vals or len(vals) < 2:
        return None
    try:
        return json.loads("".join(str(v) for v in vals[1:]))
    except Exception:
        return None


def write(e, rec: dict, doc=None):
    if doc is not None:
        _ensure_app(doc)
    txt = json.dumps(rec, ensure_ascii=False, separators=(",", ":"))
    chunks = [txt[i:i + 240] for i in range(0, len(txt), 240)]
    codes = (1001,) + (1000,) * len(chunks)
    vals = (APP,) + tuple(chunks)
    e.SetXData(win32com.client.VARIANT(pythoncom.VT_ARRAY | pythoncom.VT_I2, codes),
               win32com.client.VARIANT(pythoncom.VT_ARRAY | pythoncom.VT_VARIANT, vals))


def check_of(e) -> dict:
    return {"vol": g(e, "Volume"), "cen": list(g(e, "Centroid") or (0, 0, 0))}


def stamp(e, rec: dict, doc=None):
    """Store rec on e with a fresh volume/centroid check."""
    rec["chk"] = check_of(e)
    write(e, rec, doc)


def is_current(e, rec: dict) -> bool:
    c = rec.get("chk") or {}
    v0, v1 = c.get("vol"), g(e, "Volume")
    if v0 is None or v1 is None:
        return False
    if abs(v1 - v0) > 1e-4 * max(abs(v0), 1e-9):
        return False
    a, b = c.get("cen") or [0, 0, 0], list(g(e, "Centroid") or (0, 0, 0))
    size = max(abs(v0) ** (1 / 3), 1e-6)
    return math.dist(a, b) <= 1e-3 * size + 1e-9


# ---------------------------------------------------------------- material from the part name
_MAT = re.compile(r"(BTCT|BTXM|BT|bê tông|Bê tông|đá hộc xây|Đá hộc xây|đá 2x4|Đá 2x4|vữa|Vữa)[^,;()]*?(M\d{3})?(?=$|[,;()]| dày| rộng| L=| \()", re.I)


def guess_material(part: str) -> str:
    if not part:
        return ""
    m = re.search(r"((?:BTCT|BTXM|BT|bê tông|đá hộc xây vữa|đá hộc xây|đá 2x4|vữa xi măng|vữa)[^,;()]*?M\s?\d{3})", part, re.I)
    if m:
        return m.group(1).strip()
    m = re.search(r"(BTCT|BTXM|bê tông|đá hộc|đá dăm|cát)", part, re.I)
    return m.group(1) if m else ""


# ---------------------------------------------------------------- recipe transforms (affine: x' = A x + t)
def _mv(A, v):
    return [A[0][0] * v[0] + A[0][1] * v[1] + A[0][2] * v[2],
            A[1][0] * v[0] + A[1][1] * v[1] + A[1][2] * v[2],
            A[2][0] * v[0] + A[2][1] * v[1] + A[2][2] * v[2]]


def _unit(v):
    n = math.sqrt(sum(c * c for c in v)) or 1.0
    return [c / n for c in v]


def _det(A):
    return (A[0][0] * (A[1][1] * A[2][2] - A[1][2] * A[2][1]) - A[0][1] * (A[1][0] * A[2][2] - A[1][2] * A[2][0])
            + A[0][2] * (A[1][0] * A[2][1] - A[1][1] * A[2][0]))


def transform_node(n: dict, A, t) -> dict:
    s = abs(_det(A)) ** (1 / 3)
    k = n.get("t")
    if k == "ext":
        o = _mv(A, n["o"])
        return dict(n, o=[o[i] + t[i] for i in range(3)], X=_unit(_mv(A, n["X"])), Y=_unit(_mv(A, n["Y"])),
                    E=_unit(_mv(A, n["E"])), lo=n["lo"] * s, hi=n["hi"] * s,
                    loops=[[[p[0] * s, p[1] * s] for p in lp] for lp in n["loops"]])
    if k == "bool":
        return dict(n, a=transform_node(n["a"], A, t), b=[transform_node(x, A, t) for x in n["b"]])
    if k == "clip":
        p = _mv(A, n["p"])
        return dict(n, n=transform_node(n["n"], A, t), p=[p[i] + t[i] for i in range(3)], nrm=_unit(_mv(A, n["nrm"])))
    return n


def apply_affine(e, A, t, doc=None):
    """After a geometric edit done in the CAD, keep the stored recipe in step."""
    rec = read(e)
    if not rec or "geo" not in rec:
        return
    rec["geo"] = transform_node(rec["geo"], A, t)
    stamp(e, rec, doc)


def rot_z(base, ang_rad):
    c, s = math.cos(ang_rad), math.sin(ang_rad)
    A = [[c, -s, 0], [s, c, 0], [0, 0, 1]]
    b = base
    t = [b[0] - (c * b[0] - s * b[1]), b[1] - (s * b[0] + c * b[1]), 0.0]
    return A, t


def translate(d):
    return [[1, 0, 0], [0, 1, 0], [0, 0, 1]], [d[0], d[1], d[2] if len(d) > 2 else 0.0]


def uniform_scale(base, f):
    A = [[f, 0, 0], [0, f, 0], [0, 0, f]]
    return A, [base[i] - f * base[i] for i in range(3)]


def mirror_line(p1, p2):
    """Mirror across the vertical plane through the plan line p1-p2."""
    dx, dy = p2[0] - p1[0], p2[1] - p1[1]
    L = math.hypot(dx, dy) or 1.0
    ux, uy = dx / L, dy / L
    A = [[2 * ux * ux - 1, 2 * ux * uy, 0], [2 * ux * uy, 2 * uy * uy - 1, 0], [0, 0, 1]]
    m = _mv(A, [p1[0], p1[1], 0])
    return A, [p1[0] - m[0], p1[1] - m[1], 0.0]
