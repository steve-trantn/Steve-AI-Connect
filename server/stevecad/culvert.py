"""Structure of a culvert from its solids: structure -> group (barrel, foundation, inlet, outlet) -> part, with counts, sizes and volumes.

Pure functions (no CAD): every solid is a dict {handle, part, material, structure, station, type, group, layer, vol (m3), geo, near}."""
from __future__ import annotations

import math
import re
import statistics

from . import culvert_geo as cg

BARREL, FOUND, INLET, OUTLET, OTHER = "Thân cống", "Móng thân cống", "Cửa thượng lưu", "Cửa hạ lưu", "Bộ phận khác"
ORDER = [BARREL, FOUND, INLET, OUTLET, OTHER]


def short(part: str) -> str:
    """'Đốt cống 07 BTCT M300 L=2,0 m' -> 'Đốt cống' (no material, size or running number)."""
    p = re.split(r"\s(?:BTCT|BTXM|BT|bê tông|đá 2x4|vữa|dày|rộng|L=|\()", part or "", maxsplit=1, flags=re.I)[0]
    end = re.search(r"(thượng lưu|hạ lưu)", part or "", re.I)
    p = re.sub(r"\s(?:số\s)?\d{1,3}\b", "", p).strip(" ,-") or (part or "")
    if end and end.group(1).lower() not in p.lower():
        p += " " + end.group(1).lower()
    return p


def group_of(s: dict) -> str:
    if (s.get("group") or "").strip():
        return s["group"].strip()
    p = (s.get("part") or "").lower()
    if "thượng lưu" in p:
        return INLET
    if "hạ lưu" in p:
        return OUTLET
    if re.search(r"móng|lót|đệm|gối cống", p):
        return FOUND
    if re.search(r"đốt|thân cống|ống cống|cống tròn|cống hộp", p):
        return BARREL
    return OTHER


def ifc_class(s: dict) -> tuple[str, str]:
    """(IFC entity, predefined type): all of them exist in IFC4 and IFC4X3 with the same nine attributes."""
    p = (s.get("part") or "").lower()
    if re.search(r"lót|móng|chân khay|gối cống", p):
        return "IFCFOOTING", "USERDEFINED"
    if group_of(s) == BARREL:
        return "IFCPIPESEGMENT", "CULVERT"
    if "tường" in p:
        return "IFCWALL", "USERDEFINED"
    if re.search(r"sân|bản", p):
        return "IFCSLAB", "USERDEFINED"
    return "IFCBUILDINGELEMENTPROXY", "USERDEFINED"


# ---------------------------------------------------------------- sizes from the recipe
def _exts(n):
    t = (n or {}).get("t")
    if t == "ext":
        return [n]
    if t == "bool":
        out = _exts(n["a"])
        return out + [x for b in n["b"] for x in _exts(b)] if n.get("op") == "union" else out
    if t == "clip":
        return _exts(n["n"])
    return []


def _size(loop):
    xs, ys = [p[0] for p in loop], [p[1] for p in loop]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    r = [math.hypot(p[0] - cx, p[1] - cy) for p in loop]
    round_ = len(loop) >= 12 and max(r) > 0 and (max(r) - min(r)) / max(r) < 0.02
    return w, h, round_


def dims(geo, k: float) -> dict:
    """Sizes in metres of the main extrusion: outer W x H, clear width x height or inner diameter, wall, length."""
    ex = _exts(geo)
    if not ex:
        return {}
    e = max(ex, key=lambda n: abs(n["hi"] - n["lo"]))
    w, h, rd = _size(e["loops"][0])
    d = {"length": abs(e["hi"] - e["lo"]) * k, "E": e["E"],
         "end": sum(e["o"][i] * e["E"][i] for i in range(3)) * k + max(e["hi"], e["lo"]) * k}
    if rd:
        d["outer_d"] = w * k
    else:
        d["outer_w"], d["outer_h"] = w * k, h * k
    if len(e["loops"]) >= 2:      # more than one opening: a multi-cell culvert, sizes of one cell
        iw, ih, ird = _size(e["loops"][1])
        d["cells"] = len(e["loops"]) - 1
        if ird:
            d["inner_d"] = iw * k
        else:
            d["clear_w"], d["clear_h"] = iw * k, ih * k
        d["wall"] = (min(p[0] for lp in e["loops"][1:] for p in lp) - min(p[0] for p in e["loops"][0])) * k
    return d


def _named_length(part: str):
    m = re.search(r"\bL\s*=\s*(\d+(?:[.,]\d+)?)\s*m\b", part or "", re.I)
    return float(m.group(1).replace(",", ".")) if m else None


def segment_length(solids: list[dict], k: float):
    """Laying length of the segments: the distance between neighbours (joints overlap), else 'L=' in the name, else the extrusion."""
    ds = [dims(s.get("geo"), k) for s in solids]
    ends = sorted(d["end"] for d in ds if "end" in d)
    same = all("E" in d and sum(a * b for a, b in zip(d["E"], ds[0]["E"])) > 0.9999 for d in ds) if ds and "E" in ds[0] else False
    if same and len(ends) == len(solids) >= 2:
        gaps = [b - a for a, b in zip(ends, ends[1:])]
        m = statistics.median(gaps)
        if m > 1e-6 and max(abs(g - m) for g in gaps) <= 0.01 * m:
            return m
    named = {_named_length(s.get("part")) for s in solids}
    if len(named) == 1 and None not in named:
        return named.pop()
    ls = [d["length"] for d in ds if "length" in d]
    return statistics.median(ls) if ls and len(ls) == len(solids) and max(ls) - min(ls) <= 0.01 * max(ls) else None


def num(v: float, n: int = 3) -> str:
    return f"{round(v, n):g}".replace(".", ",")


def build(solids: list[dict], k: float) -> list[dict]:
    """[{key, title, type, station, count, volume, by_material, barrel{...}, groups: [{name, count, volume, parts: [...]}]}]"""
    out: dict[tuple, dict] = {}
    for s in solids:
        key = " ".join(x for x in (s.get("structure"), s.get("station")) if x) or "Chưa rõ công trình"
        c = out.setdefault((cg.name_key(s.get("structure")), cg.station_key(s.get("station"))), {"key": key, "structure": s.get("structure") or "", "type": "", "station": s.get("station") or "", "solids": []})
        c["type"] = c["type"] or s.get("type") or ""
        c["solids"].append(s)
    for c in out.values():
        groups: dict[str, dict] = {}
        for s in c["solids"]:
            g = groups.setdefault(group_of(s), {"parts": {}})
            nm = short(s.get("part")) or s.get("layer") or "Khối 3D"
            g["parts"].setdefault((nm, s.get("material") or ""), []).append(s)
        c["groups"] = []
        for gn in sorted(groups, key=lambda n: (ORDER.index(n) if n in ORDER else len(ORDER) - 1.5, n)):
            parts = []
            for (nm, mat), ss in groups[gn]["parts"].items():
                p = {"name": nm, "material": mat, "count": len(ss), "volume": sum(x["vol"] for x in ss), "solids": ss,
                     "approximate": sum(bool(x.get("near")) for x in ss)}
                if gn == BARREL:
                    d = [x for x in (dims(s.get("geo"), k) for s in ss) if x]
                    if d:
                        for f in ("clear_w", "clear_h", "inner_d", "outer_w", "outer_h", "outer_d", "wall"):
                            vals = [x[f] for x in d if f in x]
                            if len(vals) == len(ss) and max(vals) - min(vals) <= 0.005 * max(max(vals), 1e-9):
                                p[f] = vals[0]
                    p["segment_length"] = segment_length(ss, k)
                parts.append(p)
            c["groups"].append({"name": gn, "count": sum(p["count"] for p in parts), "volume": sum(p["volume"] for p in parts), "parts": parts})
        c["count"] = len(c["solids"])
        c["volume"] = sum(s["vol"] for s in c["solids"])
        c["by_material"] = {}
        for s in c["solids"]:
            m = s.get("material") or "Chưa có vật liệu"
            c["by_material"][m] = c["by_material"].get(m, 0.0) + s["vol"]
        br = [p for g in c["groups"] if g["name"] == BARREL for p in g["parts"]]
        c["barrel"] = {}
        if br:
            b = {"segments": sum(p["count"] for p in br)}
            if all(p.get("segment_length") for p in br):
                b["length"] = sum(p["count"] * p["segment_length"] for p in br)
                ls = {round(p["segment_length"], 4) for p in br}
                if len(ls) == 1:
                    b["segment_length"] = br[0]["segment_length"]
            main = max(br, key=lambda p: p["volume"])
            b.update({f: main[f] for f in ("clear_w", "clear_h", "inner_d", "outer_w", "outer_h", "outer_d", "wall") if f in main})
            b["volume"] = sum(p["volume"] for p in br)
            c["barrel"] = b
        c["geo"] = cg.measure(c, k)
        lanes = c["geo"].get("lanes", 1)
        if c["barrel"].get("length") and lanes > 1:      # pipes side by side: the length of one row
            c["barrel"]["length"] /= lanes
        c["barrel"].update({f: c["geo"][f] for f in ("cells",) if c["barrel"] and c["geo"].get(f, 1) > 1})
        if c["barrel"] and lanes > 1:
            c["barrel"]["lanes"] = lanes
        c["issues"] = cg.check(c)
        c["title"] = title(c)
    big = float("inf")
    return sorted(out.values(), key=lambda c: (not c["structure"] and not c["station"], cg.station_value(c["station"]) if cg.station_value(c["station"]) is not None else big, c["key"]))


def title(c: dict) -> str:
    """'Cống hộp 4x4 Km8+423.31: 22 đốt x 2 m = 44 m, khẩu độ 4x4 m, thành 0,4 m'"""
    b, t = c["barrel"], []
    if b:
        x = f"{b['segments']} đốt" + (f" ({b['lanes']} hàng)" if b.get("lanes") else "")
        if b.get("lanes") and b.get("length"):
            t.append(f"{x}, mỗi hàng {num(b['length'])} m")
            x = ""
        if x and b.get("segment_length"):
            x += f" x {num(b['segment_length'])} m"
        if x and b.get("length"):
            x += f" = {num(b['length'])} m"
        if x:
            t.append(x)
        if "inner_d" in b:
            t.append(f"đường kính trong D{num(b['inner_d'])} m")
        elif "clear_w" in b:
            t.append(f"khẩu độ {str(b['cells']) + ' khoang ' if b.get('cells') else ''}{num(b['clear_w'])}x{num(b['clear_h'])} m")
        if "wall" in b:
            t.append(f"thành {num(b['wall'])} m")
    return c["key"] + (": " + ", ".join(t) if t else "")


def slim(c: dict) -> dict:
    """For the table in the panel: the same tree with handles instead of solids."""
    return {"title": c["title"], "key": c["key"], "structure": c["structure"], "geo": {f: round(v, 4) if isinstance(v, float) else v for f, v in c["geo"].items()}, "issues": c["issues"],
            "handles": [s["handle"] for s in c["solids"]], "type": c["type"], "station": c["station"], "count": c["count"], "volume": round(c["volume"], 3),
            "by_material": {m: round(v, 3) for m, v in c["by_material"].items()}, "barrel": {f: round(v, 4) for f, v in c["barrel"].items()},
            "groups": [{"name": g["name"], "count": g["count"], "volume": round(g["volume"], 3),
                        "parts": [{"name": p["name"], "material": p["material"], "count": p["count"], "volume": round(p["volume"], 3),
                                   "segment_length": p.get("segment_length"), "approximate": p["approximate"], "handles": [s["handle"] for s in p["solids"]]}
                                  for p in g["parts"]]} for g in c["groups"]]}
