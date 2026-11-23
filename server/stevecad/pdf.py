"""PDF input: look at a page (image for the AI) and import vector linework + text into the drawing."""
from __future__ import annotations

import io
import math
import os

from mcp.server.fastmcp import Image

from .drawing import UserError, ensure_layer, r3, vdoubles, vpt
from .tools import done, editing, tool
from .vntext import decode

PT_MM = 25.4 / 72.0  # one PDF point in millimetres on paper

_ACI_RGB = {1: (255, 0, 0), 2: (255, 255, 0), 3: (0, 255, 0), 4: (0, 255, 255), 5: (0, 0, 255), 6: (255, 0, 255),
            7: (0, 0, 0), 8: (128, 128, 128), 9: (192, 192, 192), 30: (255, 127, 0), 140: (0, 127, 255)}


def _check(path: str):
    if not os.path.isfile(path):
        raise UserError(f"Không có tệp '{path}'.")
    if not path.lower().endswith(".pdf"):
        raise UserError("Chỉ đọc tệp .pdf.")


def _rgb(col) -> tuple[int, int, int] | None:
    if col is None:
        return None
    if isinstance(col, (int, float)):
        col = (col,)
    col = tuple(float(c) for c in col) if isinstance(col, (list, tuple)) else None
    if not col:
        return None
    if len(col) == 1:
        v = int(col[0] * 255)
        return (v, v, v)
    if len(col) == 3:
        return tuple(int(c * 255) for c in col)
    if len(col) == 4:  # CMYK
        c, m, y, k = col
        return (int(255 * (1 - c) * (1 - k)), int(255 * (1 - m) * (1 - k)), int(255 * (1 - y) * (1 - k)))
    return None


def _aci(rgb) -> int:
    if rgb is None:
        return 7
    if max(rgb) < 60:  # black / near black -> white-or-black (7)
        return 7
    return min(_ACI_RGB, key=lambda k: sum((a - b) ** 2 for a, b in zip(_ACI_RGB[k], rgb)))


def _flatten(path_ops) -> list[list[tuple[float, float]]]:
    """pdfminer original_path -> list of sub-paths (point lists), Bezier curves flattened."""
    subs, cur = [], []
    last = None
    for op in path_ops:
        k = op[0]
        if k == "m":
            if len(cur) > 1:
                subs.append(cur)
            cur = [tuple(op[1])]
            last = tuple(op[1])
        elif k == "l":
            cur.append(tuple(op[1]))
            last = tuple(op[1])
        elif k in ("c", "v", "y") and last is not None:
            pts = [tuple(p) for p in op[1:]]
            if k == "v":
                pts = [last] + pts
            elif k == "y":
                pts = [pts[0], pts[1], pts[1]]
            p0, (p1, p2, p3) = last, pts[-3:]
            for i in range(1, 9):
                t = i / 8
                a, b, c, d = (1 - t) ** 3, 3 * t * (1 - t) ** 2, 3 * t * t * (1 - t), t ** 3
                cur.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
            last = p3
        elif k == "h" and cur:
            cur.append(cur[0])
    if len(cur) > 1:
        subs.append(cur)
    return subs


@tool()
def pdf_info(path: str, max_pages: int = 5) -> dict:
    """Pages of a PDF and, for the first pages, how much vector linework and text they contain
    (no vectors + no text = scanned drawing -> use pdf_page_image and read the numbers visually)."""
    _check(path)
    from pdfminer.high_level import extract_pages
    from pdfminer.layout import LTChar, LTCurve, LTTextContainer
    import pypdfium2 as pdfium
    pdf = pdfium.PdfDocument(path)
    n = len(pdf)
    pages = []
    for i, layout in enumerate(extract_pages(path, maxpages=max_pages)):
        paths = texts = 0
        sample = []
        for el in layout:
            if isinstance(el, LTCurve):
                paths += 1
            elif isinstance(el, LTTextContainer):
                texts += 1
                if len(sample) < 15:
                    sample.append(decode(el.get_text().strip())[:60])
        w, h = layout.width, layout.height
        pages.append({"page": i + 1, "size_mm": [round(w * PT_MM), round(h * PT_MM)], "vector_paths": paths,
                      "text_blocks": texts, "scanned": paths < 5 and texts == 0, "text_sample": sample})
    return {"pages": n, "detail": pages}


@tool()
def pdf_page_image(path: str, page: int = 1, crop: list[float] | None = None, max_px: int = 1600) -> Image:
    """Render a PDF page (or a part of it) as an image to read views, dimensions and notes.
    crop = [left, top, right, bottom] as fractions 0..1 of the page (e.g. [0.5, 0, 1, 0.5] = top-right quarter);
    zoom into a view with crop to read small dimension text."""
    _check(path)
    import pypdfium2 as pdfium
    pdf = pdfium.PdfDocument(path)
    if not 1 <= page <= len(pdf):
        raise UserError(f"PDF có {len(pdf)} trang.")
    pg = pdf[page - 1]
    w, h = pg.get_size()
    l, t, r, b = crop or [0, 0, 1, 1]
    if not (0 <= l < r <= 1 and 0 <= t < b <= 1):
        raise UserError("crop phải là [trái, trên, phải, dưới] trong khoảng 0..1.")
    cw, ch = (r - l) * w, (b - t) * h
    scale = min(max_px / max(cw, ch), 12.0)
    img = pg.render(scale=scale, crop=(l * w, (1 - b) * h, (1 - r) * w, t * h)).to_pil()
    buf = io.BytesIO()
    img.convert("RGB").save(buf, "JPEG", quality=85)
    return Image(data=buf.getvalue(), format="jpeg")


@tool("write")
def import_pdf(path: str, page: int = 1, insert_point: list[float] | None = None, scale: float = 1.0,
               crop: list[float] | None = None, include_text: bool = True, layer: str = "PDF-IMPORT",
               max_objects: int = 20000) -> dict:
    """Import the vector linework (and text) of a PDF page into the working drawing as polylines/text, so a PDF
    drawing can be measured and used like a DWG (e.g. as profiles for solid_extrude).
    Units: 1 = millimetres on paper; scale = drawing scale denominator to get real millimetres (1:50 -> 50).
    insert_point = where the page's bottom-left corner goes. crop = [left, top, right, bottom] fractions to import
    only one view. Colors follow the PDF (nearest ACI)."""
    _check(path)
    from pdfminer.high_level import extract_pages
    from pdfminer.layout import LTCurve, LTTextContainer, LTTextLine
    ip = [float(x) for x in ((insert_point or [0, 0]) + [0, 0])[:2]]
    k = PT_MM * float(scale)
    layouts = list(extract_pages(path, page_numbers=[page - 1]))
    if not layouts:
        raise UserError(f"Không đọc được trang {page}.")
    L = layouts[0]
    W, H = L.width, L.height
    cl, ct, cr, cb = crop or [0, 0, 1, 1]
    x0, x1, y0, y1 = cl * W, cr * W, (1 - cb) * H, (1 - ct) * H

    def inside(bb):
        return bb[0] >= x0 - 1 and bb[2] <= x1 + 1 and bb[1] >= y0 - 1 and bb[3] <= y1 + 1

    def P(p):
        return (ip[0] + (p[0] - x0) * k, ip[1] + (p[1] - y0) * k)

    curves, texts = [], []

    def walk(el):
        if isinstance(el, LTCurve):
            curves.append(el)
        elif isinstance(el, LTTextLine):
            texts.append(el)
        elif hasattr(el, "__iter__") and not isinstance(el, LTTextLine):
            for c in el:
                walk(c)
    for el in L:
        if isinstance(el, LTTextContainer) and include_text:
            for line in el:
                if isinstance(line, LTTextLine):
                    texts.append(line)
        elif isinstance(el, LTCurve):
            curves.append(el)
        elif hasattr(el, "__iter__"):
            walk(el)
    n_poly = n_text = 0
    with editing() as d:
        ensure_layer(d, layer)
        ms = d.ModelSpace
        for cv in curves:
            if n_poly + n_text >= max_objects:
                break
            if not inside(cv.bbox):
                continue
            ops = getattr(cv, "original_path", None)
            subs = _flatten(ops) if ops else [list(cv.pts)]
            col = _aci(_rgb(getattr(cv, "stroking_color", None)))
            for sp in subs:
                if len(sp) < 2:
                    continue
                pts = [P(p) for p in sp]
                closed = len(pts) > 2 and math.dist(pts[0], pts[-1]) < 1e-6 * max(1.0, k)
                if closed:
                    pts = pts[:-1]
                e = ms.AddLightWeightPolyline(vdoubles([c for p in pts for c in p]))
                if closed:
                    e.Closed = True
                e.Layer = layer
                if col != 7:
                    e.Color = col
                n_poly += 1
        if include_text:
            for tl in texts:
                if n_poly + n_text >= max_objects:
                    break
                if not inside(tl.bbox):
                    continue
                s = decode(tl.get_text().strip())
                if not s:
                    continue
                hgt = max((tl.bbox[3] - tl.bbox[1]) * 0.7 * k, 1e-6)
                e = ms.AddText(s, vpt(P((tl.bbox[0], tl.bbox[1]))), hgt)
                e.Layer = layer
                n_text += 1
        return done(d, None, polylines=n_poly, texts=n_text,
                    extent={"min": r3(P((x0, y0)), 2), "max": r3(P((x1, y1)), 2)},
                    units="mm thật nếu scale = mẫu số tỉ lệ bản vẽ" if scale != 1 else "mm trên giấy")
