"""Levels, slope, direction and skew of a culvert, and the checks made before an export. Pure functions, metres.

What cannot be computed is left out and the reason goes to notes: nothing is estimated."""
from __future__ import annotations

import math
import re

_ST = re.compile(r"^\s*km\s*(\d+)\s*\+\s*(\d{1,4})(?:\s*[.,]\s*(\d+))?\s*$", re.I)


def station_value(s: str):
    m = _ST.match(s or "")
    return int(m.group(1)) * 1000 + float(f"{m.group(2)}.{m.group(3) or 0}") if m else None


def station_key(s: str) -> str:
    """'KM8+423,31' and 'Km8+423.310' are the same place."""
    v = station_value(s)
    return f"{v:.3f}" if v is not None else re.sub(r"\s+", "", s or "").lower()


def name_key(s: str) -> str:
    return re.sub(r"\s+", " ", s or "").strip().casefold()


def _dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def _main(n):
    """The longest extrusion of a recipe (the body of a segment)."""
    from .culvert import _exts
    ex = _exts(n)
    return max(ex, key=lambda e: abs(e["hi"] - e["lo"])) if ex else None


def _interval(n, e, c):
    """Range [lo, hi] of the solid on the axis line c + E*s (drawing units); None when it is not along that axis."""
    t = n.get("t")
    if t == "ext":
        if abs(_dot(n["E"], e["E"])) < 0.9999:
            return None
        sg = 1 if _dot(n["E"], e["E"]) > 0 else -1
        off = _dot([n["o"][i] - e["o"][i] for i in range(3)], e["E"])
        a, b = off + sg * n["lo"], off + sg * n["hi"]
        return min(a, b), max(a, b)
    if t == "bool":
        a = _interval(n["a"], e, c)
        if n.get("op") == "union":
            for x in n["b"]:
                b = _interval(x, e, c)
                if b:
                    a = (min(a[0], b[0]), max(a[1], b[1])) if a else b
        return a
    if t == "clip":
        a = _interval(n["n"], e, c)
        den = _dot(n["nrm"], e["E"])
        if not a or abs(den) < 1e-9:
            return a
        s = _dot([n["p"][i] - c[i] for i in range(3)], n["nrm"]) / den
        keep_low = (den > 0) == (n.get("keep") != "front")      # 'back' keeps the side opposite to the normal
        return (a[0], min(a[1], s)) if keep_low else (max(a[0], s), a[1])
    return None


def axis_of(geo, k):
    """One segment: unit axis E, a point on the axis, range, inverts at both ends (metres). None when it has no clear opening."""
    e = _main(geo)
    if not e or len(e["loops"]) < 2:
        return None
    inner = [p for lp in e["loops"][1:] for p in lp]
    xs, ys = [p[0] for p in inner], [p[1] for p in inner]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    c = [e["o"][i] + e["X"][i] * cx + e["Y"][i] * cy for i in range(3)]
    r = _interval(geo, e, c)
    if not r:
        return None
    low = min(e["o"][2] + e["X"][2] * p[0] + e["Y"][2] * p[1] for p in inner)
    z = lambda s: (low + e["E"][2] * s) * k
    ow = [p[0] for p in e["loops"][0]]
    return {"E": list(e["E"]), "c": [v * k for v in c], "lo": r[0] * k, "hi": r[1] * k, "z_lo": z(r[0]), "z_hi": z(r[1]),
            "width": (max(ow) - min(ow)) * k, "cells": len(e["loops"]) - 1}


def lanes_of(axes):
    """Segments on the same straight line -> one lane: {E, o, lo, hi, z_lo, z_hi, width, n}."""
    lanes = []
    for a in axes:
        for ln in lanes:
            d = _dot(a["E"], ln["E"])
            if abs(d) < 0.9999:
                continue
            v = [a["c"][i] - ln["o"][i] for i in range(3)]
            t = _dot(v, ln["E"])
            if math.sqrt(max(0.0, _dot(v, v) - t * t)) > 0.05 + 2e-4 * abs(t):
                continue
            lo, hi, zl, zh = (t + a["lo"], t + a["hi"], a["z_lo"], a["z_hi"]) if d > 0 else (t - a["hi"], t - a["lo"], a["z_hi"], a["z_lo"])
            if lo < ln["lo"]:
                ln["lo"], ln["z_lo"] = lo, zl
            if hi > ln["hi"]:
                ln["hi"], ln["z_hi"] = hi, zh
            ln["n"] += 1
            break
        else:
            lanes.append({"E": a["E"], "o": a["c"], "lo": a["lo"], "hi": a["hi"], "z_lo": a["z_lo"], "z_hi": a["z_hi"], "width": a["width"], "n": 1, "cells": a["cells"]})
    return lanes


def _pt(ln, s):
    return [ln["o"][i] + ln["E"][i] * s for i in range(3)]


def _wall_dir(geo):
    """Plan direction of the long side of a head wall."""
    e = _main(geo)
    if not e:
        return None
    xs, ys = [p[0] for p in e["loops"][0]], [p[1] for p in e["loops"][0]]
    cand = [(abs(e["hi"] - e["lo"]), e["E"]), (max(xs) - min(xs), e["X"]), (max(ys) - min(ys), e["Y"])]
    flat = [(n, v) for n, v in cand if abs(v[2]) < 0.1]
    if len(flat) < 2:
        return None
    flat.sort(key=lambda x: -x[0])
    if flat[0][0] < 1.5 * flat[1][0]:
        return None      # not clearly longer one way
    return flat[0][1]


def _acute(a, b):
    n = math.hypot(a[0], a[1]) * math.hypot(b[0], b[1])
    return math.degrees(math.acos(min(1.0, abs(a[0] * b[0] + a[1] * b[1]) / n))) if n > 1e-9 else None


def _mean(pts):
    return [sum(p[i] for p in pts) / len(pts) for i in range(3)]


def measure(c: dict, k: float) -> dict:
    """c: one structure of culvert.build. -> {lanes, cells, length_true, length_plan, z_up, z_down, slope, azimuth, skew, guessed_ends, notes, split}"""
    from .culvert import BARREL, INLET, OUTLET, group_of
    out = {"notes": [], "split": False}
    br = [s for s in c["solids"] if group_of(s) == BARREL]
    if not br:
        out["notes"].append("không có đốt cống")
        return out
    axes = [axis_of(s["geo"], k) if s.get("geo") and not s.get("near") else None for s in br]
    if any(a is None for a in axes):
        out["notes"].append(f"{sum(a is None for a in axes)} đốt không còn công thức dựng hoặc không có lòng cống: không tính cao độ, độ dốc, góc")
        return out
    lanes = lanes_of(axes)
    out["cells"] = max(ln["cells"] for ln in lanes)
    main = max(lanes, key=lambda ln: ln["hi"] - ln["lo"])
    for ln in lanes:
        if ln is main:
            continue
        v = [ln["o"][i] - main["o"][i] for i in range(3)]
        t = _dot(v, main["E"])
        side = math.sqrt(max(0.0, _dot(v, v) - t * t))
        par = abs(_dot(ln["E"], main["E"])) > 0.9999
        sg = 1 if _dot(ln["E"], main["E"]) > 0 else -1
        a, b = sorted((t + sg * ln["lo"], t + sg * ln["hi"]))
        over = min(b, main["hi"]) - max(a, main["lo"])
        if not (par and side <= 3 * max(main["width"], ln["width"]) and over > 0.5 * (b - a)):
            out["split"] = True
    if out["split"]:
        out["notes"].append("các đốt không nằm trên một trục: có thể là hai cống dùng chung tên, hoặc thân gấp khúc; không tính cao độ, độ dốc, góc")
        return out
    out["lanes"] = len(lanes)
    E, L = main["E"], main["hi"] - main["lo"]
    flat = math.hypot(E[0], E[1])
    if flat < 0.5:
        out["notes"].append("trục cống gần thẳng đứng")
        return out
    out["length_true"], out["length_plan"] = L, L * flat
    A, B = _pt(main, main["lo"]), _pt(main, main["hi"])
    ends = {g: [s["cen"] for s in c["solids"] if group_of(s) == g and s.get("cen")] for g in (INLET, OUTLET)}
    up = None      # True: the 'lo' end is upstream
    if ends[INLET]:
        m = _mean(ends[INLET])
        up = math.dist(m, A) < math.dist(m, B)
    if ends[OUTLET]:
        m = _mean(ends[OUTLET])
        u2 = math.dist(m, B) < math.dist(m, A)
        if up is not None and up != u2:
            out["notes"].append("cửa thượng lưu và hạ lưu nằm cùng một đầu: kiểm tra lại tên bộ phận")
            return out
        up = u2 if up is None else up
    if up is None:
        if abs(main["z_lo"] - main["z_hi"]) < 1e-3:
            out["notes"].append("không có cửa cống và đáy bằng phẳng: không rõ đầu thượng lưu")
        else:
            up = main["z_lo"] > main["z_hi"]
            out["guessed_ends"] = True
            out["notes"].append("suy đoán đầu cao hơn là thượng lưu (không có cửa cống)")
    if up is not None:
        out["z_up"], out["z_down"] = (main["z_lo"], main["z_hi"]) if up else (main["z_hi"], main["z_lo"])
        out["slope"] = (out["z_up"] - out["z_down"]) / out["length_plan"] * 100
        d = E if up else [-x for x in E]
        out["azimuth"] = math.degrees(math.atan2(d[0], d[1])) % 360
    # skew: acute angle between the axis and the road centre line
    given = {str(s["extra"].get("road_azimuth")).strip() for s in c["solids"] if str(s["extra"].get("road_azimuth") or "").strip()}
    g_ang = None
    if len(given) > 1:
        out["notes"].append("road_azimuth của các khối không giống nhau")
    elif given:
        try:
            a = math.radians(float(given.pop().replace(",", ".")))
            g_ang = _acute(E, [math.sin(a), math.cos(a)])
        except ValueError:
            out["notes"].append("road_azimuth không phải số")
    walls = [_wall_dir(s["geo"]) for s in c["solids"] if "tường đầu" in (s.get("part") or "").lower() and s.get("geo") and not s.get("near")]
    ws = [x for x in (_acute(E, w) for w in walls if w) if x is not None]
    w_ang = sum(ws) / len(ws) if ws and max(ws) - min(ws) <= 1 else None
    if ws and w_ang is None:
        out["notes"].append("hai tường đầu không song song: không suy ra góc chéo")
    if len(given) <= 1:
        if g_ang is not None and w_ang is not None and abs(g_ang - w_ang) > 1:
            out["notes"].append(f"góc chéo theo road_azimuth ({g_ang:.1f}) và theo tường đầu ({w_ang:.1f}) lệch nhau: để trống")
        elif g_ang is not None or w_ang is not None:
            out["skew"] = g_ang if g_ang is not None else w_ang
            out["skew_from"] = "tim đường" if g_ang is not None else "tường đầu"
        elif not ws:
            out["notes"].append("chưa có phương vị tim đường hoặc tường đầu nên không có góc chéo")
    return out


def check(c: dict) -> list[dict]:
    """[{level: 'err' | 'warn', text}] for one structure."""
    from .culvert import BARREL, OTHER, group_of
    out, ss = [], c["solids"]
    add = lambda lv, t: out.append({"level": lv, "text": t})
    if not c["structure"] and not c["station"]:
        add("err", "chưa có Công trình và Lý trình")
    elif not c["structure"]:
        add("warn", "chưa có Công trình")
    elif not c["station"]:
        add("warn", "chưa có Lý trình")
    if c["station"] and station_value(c["station"]) is None:
        add("warn", f"lý trình '{c['station']}' không đúng mẫu Km8+423.31")
    if len({s["station"] for s in ss if s["station"]}) > 1:
        add("warn", "lý trình viết nhiều kiểu: " + ", ".join(sorted({s["station"] for s in ss if s["station"]})))
    n = sum(not s["part"] for s in ss)
    if n:
        add("warn", f"{n} khối chưa có tên Bộ phận")
    other = sorted({s["part"] for s in ss if s["part"] and group_of(s) == OTHER})
    if other:
        add("warn", "không nhận ra nhóm: " + ", ".join(other[:4]) + ("…" if len(other) > 4 else ""))
    ends = sorted({s["part"] for s in ss if re.search(r"tường đầu|tường cánh|sân cống|chân khay", s["part"], re.I) and not re.search(r"thượng lưu|hạ lưu", s["part"], re.I) and not s["group"]})
    if ends:
        add("warn", "chưa ghi thượng lưu hay hạ lưu: " + ", ".join(ends[:4]))
    nums = [int(m.group(1)) for s in ss if group_of(s) == BARREL for m in [re.search(r"đốt(?: cống)?\s+(?:số\s+)?(\d{1,3})\b", s["part"], re.I)] if m]
    if nums:
        dup = sorted({x for x in nums if nums.count(x) > 1})
        miss = sorted(set(range(min(nums), max(nums) + 1)) - set(nums))
        if dup and c["geo"].get("lanes", 1) <= 1:
            add("warn", "đốt trùng số: " + ", ".join(map(str, dup[:6])))
        if miss:
            add("warn", "thiếu số đốt: " + ", ".join(map(str, miss[:6])))
    near = sum(bool(s["near"]) for s in ss)
    if near:
        add("warn", f"{near} khối chỉ xuất dạng hộp bao")
    seen, dup = set(), 0
    for s in ss:
        if s.get("cen"):
            key = (round(s["vol"], 5), *(round(x, 3) for x in s["cen"]))
            dup += key in seen
            seen.add(key)
    if dup:
        add("warn", f"{dup} khối trùng chỗ với khối khác")
    if c["geo"].get("split"):
        add("err", "có thể là hai cống dùng chung tên, hoặc thân gấp khúc")
    if c["geo"].get("slope", 0) < -1e-4:
        add("warn", f"độ dốc âm ({c['geo']['slope']:.2f}%): hạ lưu cao hơn thượng lưu")
    return out


def suggest(lost: list[dict], known: list[dict], k: float) -> dict:
    """For solids without structure and station: {handle: {structure, station, type, why}}. Only clear cases."""
    from .culvert import BARREL, group_of
    from .ifc import layer_safe
    out, lines = {}, []
    for c in known:
        for ln in lanes_of([a for a in (axis_of(s["geo"], k) if s.get("geo") and not s["near"] else None for s in c["solids"] if group_of(s) == BARREL) if a]):
            lines.append((c, _pt(ln, ln["lo"]), _pt(ln, ln["hi"])))
    pre = [(layer_safe(f"{c['structure']}_{c['station']}").upper() + "_", c) for c in known if c["structure"] and c["station"]]
    for s in lost:
        hit, why = [c for p, c in pre if s["layer"].upper().startswith(p)], "theo layer"
        if len(hit) != 1:
            hit, why = [], "theo vị trí"
            if s.get("cen") and lines:
                best: dict[int, tuple] = {}
                for c, a, b in lines:
                    ab = [b[i] - a[i] for i in range(3)]
                    t = max(0.0, min(1.0, _dot([s["cen"][i] - a[i] for i in range(3)], ab) / (_dot(ab, ab) or 1)))
                    d = math.dist(s["cen"], [a[i] + ab[i] * t for i in range(3)])
                    if id(c) not in best or d < best[id(c)][0]:
                        best[id(c)] = (d, c)
                ds = sorted(best.values(), key=lambda x: x[0])
                if ds[0][0] <= 10 and (len(ds) == 1 or ds[1][0] > 2 * max(ds[0][0], 1)):
                    hit = [ds[0][1]]
        if hit:
            out[s["handle"]] = {"structure": hit[0]["structure"], "station": hit[0]["station"], "type": hit[0]["type"], "why": why}
    return out
