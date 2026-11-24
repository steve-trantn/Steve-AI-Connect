"""Tools behind the skills viet-lisp, kiem-tra-ban-ve, boc-khoi-luong and tao-skill."""
from __future__ import annotations

import os
import re
import tempfile
import time
import zipfile
from xml.sax.saxutils import escape

from . import tools
from .drawing import Drawings, UserError, area_of, bbox, count_matching, etype, g, iter_space, length_of, r3, run_cmd, text_of
from .tools import C, Handles, doc, done, entities, tool

WORKSPACE = os.path.join(os.path.expanduser("~"), "Steve-CAD-AI")
LISP_DIR = os.path.join(WORKSPACE, "Lisp")

# ---------------------------------------------------------------- AutoLISP
# Reaching outside the drawing: files, programs, registry, shell. Text matching is a safety net for honest mistakes,
# not a sandbox: the code must still be shown to the user before it runs.
DANGER = {
    "startapp": "chạy chương trình ngoài", "shell": "chạy lệnh Windows", "sh": "chạy lệnh Windows", "start": "chạy chương trình ngoài",
    "vl-file-delete": "xoá file", "vl-file-rename": "đổi tên file", "vl-file-copy": "chép file", "vl-mkdir": "tạo thư mục",
    "vl-registry-write": "ghi registry", "vl-registry-delete": "xoá registry", "setenv": "đổi biến môi trường của CAD",
    "setcfg": "ghi cấu hình CAD", "dos_command": "chạy lệnh DOS", "dos_delete": "xoá file", "arxload": "nạp chương trình ngoài",
    "vlax-create-object": "tạo đối tượng COM ngoài CAD", "vlax-get-or-create-object": "tạo đối tượng COM ngoài CAD",
    "vla-getinterfaceobject": "tạo đối tượng COM", "vlax-invoke-method": "gọi phương thức COM bất kỳ", "vlax-invoke": "gọi phương thức COM bất kỳ",
    "load": "nạp file lisp khác", "autoload": "nạp file lisp khác", "vl-load-all": "nạp vào mọi bản vẽ",
    "vl-vbaload": "chạy VBA", "vl-vbarun": "chạy VBA", "vlax-import-type-library": "nạp thư viện COM",
    "eval": "chạy mã được tạo lúc chạy", "read": "đọc mã từ chuỗi", "vla-sendcommand": "gửi lệnh bất kỳ", "vla-eval": "chạy VBA",
    "defun-q": "định nghĩa hàm dạng dữ liệu", "vl-cmdf-s": "gửi lệnh",
    "vla-save": "lưu bản vẽ", "vla-saveas": "lưu bản vẽ", "vla-close": "đóng bản vẽ", "vla-quit": "thoát CAD", "exit": None, "quit": None,
}
DANGER_CMD = re.compile(r"^[._'\-+]*(shell|sh|start|del|netload|arx|appload|vbarun|vbaload|script|scr|save|saveas|qsave|close|closeall|quit|exit|"
                        r"purge|erase|open|export|wblock|recover|plot|publish|-plot)$", re.I)


def _tokens(code: str):
    """AutoLISP tokens as (kind, text, line): kind in ( ) str sym. Raises UserError on unbalanced text."""
    out, i, line, n = [], 0, 1, len(code)
    while i < n:
        c = code[i]
        if c == "\n":
            line += 1
            i += 1
        elif c.isspace():
            i += 1
        elif c == ";":
            if code.startswith(";|", i):
                j = code.find("|;", i + 2)
                if j < 0:
                    raise UserError(f"Dòng {line}: ghi chú ;| chưa đóng bằng |;.")
                line += code.count("\n", i, j)
                i = j + 2
            else:
                j = code.find("\n", i)
                i = n if j < 0 else j
        elif c == '"':
            j, start = i + 1, line
            while j < n and code[j] != '"':
                if code[j] == "\\":
                    j += 1
                if j < n and code[j] == "\n":
                    line += 1
                j += 1
            if j >= n:
                raise UserError(f"Dòng {start}: chuỗi \" chưa đóng.")
            out.append(("str", code[i + 1:j], start))
            i = j + 1
        elif c in "()":
            out.append((c, c, line))
            i += 1
        elif c in "'`,":
            i += 1
        else:
            j = i
            while j < n and not code[j].isspace() and code[j] not in "()\";'`,":
                j += 1
            out.append(("sym", code[i:j], line))
            i = j
    return out


def check_lisp(code: str) -> dict:
    tk = _tokens(code)
    stack = []
    for k, _, ln in tk:
        if k == "(":
            stack.append(ln)
        elif k == ")":
            if not stack:
                raise UserError(f"Dòng {ln}: thừa dấu ).")
            stack.pop()
    if stack:
        raise UserError(f"Thiếu {len(stack)} dấu ) - ngoặc mở ở dòng {stack[-1]} chưa đóng.")
    commands, danger, warn = [], [], []
    for a, (k, t, ln) in enumerate(tk):
        low = t.lower()
        if k == "sym":
            if low == "defun" and a + 1 < len(tk) and tk[a + 1][0] == "sym":
                nm = tk[a + 1][1]
                if nm.lower().startswith("c:"):
                    commands.append(nm[2:].upper())
                if nm.lower().startswith("s::") or nm.lower() in ("c:undo", "c:save", "c:qsave", "*error*") and nm.lower() != "*error*":
                    danger.append({"line": ln, "what": nm, "why": "ghi đè lệnh hoặc tự chạy khi mở bản vẽ"})
            # also when passed as a quoted symbol, e.g. (apply 'startapp ...)
            why = DANGER.get(low)
            if why:
                danger.append({"line": ln, "what": t, "why": why})
            if low == "open" and a + 1 < len(tk):
                mode = next((x[1] for x in tk[a + 1:a + 12] if x[0] == "str" and x[1].lower() in ("w", "a")), None)
                if mode:
                    danger.append({"line": ln, "what": f'open "{mode}"', "why": "ghi file ra đĩa"})
            if low.startswith(("vl-registry", "dos_", "acet-file", "acet-reg", "acet-sys")) and not why and not low.endswith("read"):
                danger.append({"line": ln, "what": t, "why": "truy cập file, registry hoặc hệ thống"})
        elif k == "str" and DANGER_CMD.match(t) and any(x[0] == "sym" and x[1].lower() in ("command", "command-s", "vl-cmdf") for x in tk[max(0, a - 40):a]):
            danger.append({"line": ln, "what": t, "why": "lệnh xoá, lưu, đóng, mở file hoặc chạy chương trình"})
    if not commands:
        warn.append("Không có lệnh nào dạng (defun c:TEN ...).")
    low = code.lower()
    if commands and "*error*" not in low:
        warn.append("Chưa có *error* để trả lại biến hệ thống khi người dùng bấm Esc.")
    if commands and "undo" not in low and "startundomark" not in low:
        warn.append("Chưa gom UNDO (command \"_.UNDO\" \"_Begin\" / \"_End\").")
    if any(ord(c) > 127 for c in code):
        warn.append("Có ký tự tiếng Việt có dấu: câu nhắc trong CAD có thể bị lỗi font. Nên viết không dấu.")
    return {"commands": commands, "danger": danger, "warnings": warn}


def _lisp_path(path: str) -> str:
    p = os.path.abspath(path if os.path.isabs(path) else os.path.join(LISP_DIR, path))
    if not p.lower().endswith(".lsp"):
        p += ".lsp"
    return p


@tool()
def lisp_check(code: str = "", path: str = "") -> dict:
    """Check AutoLISP source without running it: brackets, strings, command names, calls that reach outside the drawing
    (files, programs, registry, save, erase...) and missing good practice. Give code, or the path of a .lsp file."""
    if not code:
        p = _lisp_path(path)
        if not path or not os.path.isfile(p):
            raise UserError("Truyền code, hoặc path của một file .lsp có thật.")
        code = open(p, encoding="utf-8-sig", errors="replace").read()
    return check_lisp(code)


@tool("destructive")
def lisp_save(name: str, code: str, overwrite: bool = False) -> dict:
    """Save AutoLISP source to Steve-CAD-AI\\Lisp\\<name>.lsp (checked first). Show the code to the user and get their
    consent before saving. overwrite=True replaces an existing file (a .bak copy is kept)."""
    nm = re.sub(r"[^\w\-]", "", os.path.splitext(os.path.basename(name))[0], flags=re.ASCII)
    if not nm:
        raise UserError("Tên file chỉ gồm chữ không dấu, số, - và _.")
    rep = check_lisp(code)
    os.makedirs(LISP_DIR, exist_ok=True)
    p = os.path.join(LISP_DIR, nm + ".lsp")
    if os.path.exists(p):
        if not overwrite:
            raise UserError(f"Đã có {p}. Hỏi người dùng rồi dùng overwrite=True, hoặc đổi tên.")
        os.replace(p, p + ".bak")
    with open(p, "w", encoding="ascii" if code.isascii() else "utf-8-sig", newline="\r\n") as f:
        f.write(code.replace("\r\n", "\n"))
    return {"ok": True, "path": p, **rep}


_scratch = [None]   # name of the drawing opened for tests


@tool("destructive")
def lisp_test(path: str, run: str = "", allow_danger: bool = False) -> dict:
    """Load a .lsp in a new, unsaved SCRATCH drawing (never the user's drawing) and report load errors. `run` is an
    optional LISP expression to evaluate after loading, e.g. "(my-func 10 20)"; it must not wait for user input.
    Files with dangerous calls are refused unless the user agreed explicitly (allow_danger=True).
    The scratch drawing stays open so the user can try the command; the working drawing for the other tools is unchanged."""
    p = _lisp_path(path)
    if not os.path.isfile(p):
        raise UserError(f"Không có file {p}.")
    rep = check_lisp(open(p, encoding="utf-8-sig", errors="replace").read())
    bad = list(rep["danger"])
    if run:
        bad += check_lisp(run)["danger"]
    if bad and not allow_danger:
        raise UserError("Không chạy vì có lời gọi nguy hiểm: " + "; ".join(f"dòng {x['line']} {x['what']} ({x['why']})" for x in bad[:8]) +
                        ". Nói rõ với người dùng; chỉ dùng allow_danger=True khi họ đồng ý.")
    if C.drawings.pinned is None:   # keep the other tools on the user's drawing: a new tab becomes active below
        C.drawings.pinned = Drawings.name(doc())
    d = next((x for x in C.drawings.all() if _scratch[0] and Drawings.name(x) == _scratch[0] and not g(x, "FullName")), None)
    if d is None:
        d = C.conn.app().Documents.Add()
        _scratch[0] = Drawings.name(d)
    d.Activate()
    time.sleep(0.5)
    tools.need_active_doc(d)
    fd, out = tempfile.mkstemp(suffix=".txt", prefix="steveai-")
    os.close(fd)
    fwd = lambda s: s.replace("\\", "/").replace('"', "")   # noqa: E731
    expr = f"(setq steveai:r (vl-catch-all-apply '(lambda () (load \"{fwd(p)}\"){' ' + run if run else ''})))"
    cmd = (f"(progn (vl-load-com) {expr} (setq steveai:f (open \"{fwd(out)}\" \"w\")) "
           "(if (vl-catch-all-error-p steveai:r) (princ (strcat \"ERR \" (vl-catch-all-error-message steveai:r)) steveai:f) "
           "(progn (princ \"OK \" steveai:f) (prin1 steveai:r steveai:f))) (close steveai:f) (princ)) ")
    if "\n" in cmd:
        cmd = cmd.replace("\r", " ").replace("\n", " ")
    fin = run_cmd(d, cmd, timeout=30)
    res = ""
    for _ in range(50):   # SendCommand can return before the expression ran
        res = open(out, encoding="utf-8", errors="replace").read()
        if res:
            break
        time.sleep(0.1)
    try:
        os.remove(out)
    except OSError:
        pass
    ok = res.startswith("OK ")
    return {"ok": ok, "scratch_drawing": g(d, "Name"), "finished": fin, "result": res[3:] if ok else None,
            "error": None if ok else (res[4:] or "Không có kết quả: lisp đang chờ nhập liệu hoặc CAD bận. Nhờ người dùng bấm Esc."),
            "objects_in_scratch": d.ModelSpace.Count, "working_drawing": C.drawings.pinned, **rep}


# ---------------------------------------------------------------- audit / quantities
@tool()
def audit(max_objects: int = 2000) -> dict:
    """Read-only health check of the drawing: objects on layer 0 / Defpoints, forced colours, zero-length or tiny lines,
    dimensions with typed-over values, empty text, layers with objects that are off / frozen, unused layers, missing xrefs, duplicated
    layer names differing only by case/spaces. Use find_duplicates for overlapping objects. Nothing is changed."""
    d = doc()
    total = count_matching(d)
    by_layer, types, far = {}, {}, []
    forced, zero, dims, empty = [], [], [], []
    for e in iter_space(d, limit=max_objects):
        t, lay, h = etype(e), g(e, "Layer") or "", g(e, "Handle")
        by_layer[lay] = by_layer.get(lay, 0) + 1
        types[t] = types.get(t, 0) + 1
        if g(e, "Color", 256) not in (256, None):
            forced.append(h)
        if t in ("Line", "Polyline") and (length_of(e) or 0) < 1e-6:
            zero.append(h)
        elif "Dimension" in t and g(e, "TextOverride"):
            ov = str(g(e, "TextOverride"))
            if "<>" not in ov and ov.strip():
                dims.append({"handle": h, "shown": ov, "measured": r3(g(e, "Measurement"))})
        elif t in ("Text", "MText") and not str(text_of(e).get("text") or "").strip():
            empty.append(h)
    layers = []
    for i in range(d.Layers.Count):
        x = d.Layers.Item(i)
        layers.append((g(x, "Name"), bool(g(x, "LayerOn", True)), bool(g(x, "Freeze", False))))
    norm: dict = {}
    for n, _, _ in layers:
        norm.setdefault(re.sub(r"[\s_\-]+", "", n).lower(), []).append(n)
    xref = []
    for i in range(d.Blocks.Count):
        b = d.Blocks.Item(i)
        if g(b, "IsXRef"):
            pth = g(b, "Path") or ""
            base = g(d, "Path") or ""
            if pth and not os.path.exists(pth) and not os.path.exists(os.path.join(base, pth)):
                xref.append({"name": g(b, "Name"), "path": pth})
    cut = lambda a: {"count": len(a), "items": a[:40]}   # noqa: E731
    return {"drawing": g(d, "Name"), "objects": total, "scanned": min(total, max_objects), "partial": total > max_objects,
            "types": types, "on_layer_0": by_layer.get("0", 0), "on_defpoints": by_layer.get("Defpoints", 0) + by_layer.get("DEFPOINTS", 0),
            "forced_color": cut(forced), "zero_length": cut(zero), "dim_override": cut(dims), "empty_text": cut(empty),
            "hidden_layers_with_objects": [n for n, on, fr in layers if (not on or fr) and by_layer.get(n)],
            "layers_without_model_objects": [n for n, _, _ in layers if n not in by_layer and n not in ("0", "Defpoints")][:80] if total <= max_objects else None,
            "similar_layer_names": [v for v in norm.values() if len(v) > 1], "missing_xrefs": xref,
            "note": "layers_without_model_objects chỉ tính không gian mô hình; layer có thể đang dùng trong block hoặc layout."}


@tool()
def quantities(layer: str = "", window: list[float] | None = None, selection_only: bool = False, max_objects: int = 5000) -> dict:
    """Quantity take-off grouped by layer and type: count, total length, total area, and blocks by name. Filter by layer,
    by window [x1,y1,x2,y2], or selection_only=True for the user's current selection. Values are in drawing units.
    Overlapping objects are counted twice: run find_duplicates first."""
    d = doc()
    if selection_only:
        ents = list(tools.selection_handles(d))
        if not ents:
            raise UserError("Chưa chọn đối tượng nào trong CAD.")
        total = len(ents)
    else:
        total = count_matching(d, None, layer or None) if not window else None
        ents = iter_space(d, None, layer or None, limit=max_objects, window=window)
    rows, blocks, n, skipped = {}, {}, 0, {}
    for e in ents:
        n += 1
        t, lay = etype(e), g(e, "Layer") or ""
        if selection_only and layer and lay.lower() != layer.lower():
            continue
        if t == "BlockReference":
            k = (lay, g(e, "EffectiveName") or g(e, "Name"))
            blocks[k] = blocks.get(k, 0) + 1
            continue
        L, A = length_of(e), area_of(e)
        if L is None and A is None:
            skipped[t] = skipped.get(t, 0) + 1
            continue
        r = rows.setdefault((lay, t), {"layer": lay, "type": t, "count": 0, "length": 0.0, "area": 0.0, "sample_handles": []})
        r["count"] += 1
        r["length"] += L or 0
        r["area"] += A or 0
        if len(r["sample_handles"]) < 5:
            r["sample_handles"].append(g(e, "Handle"))
    for r in rows.values():
        r["length"], r["area"] = r3(r["length"]), r3(r["area"])
    return {"drawing": g(d, "Name"), "scanned": n, "total": total, "partial": bool(n >= max_objects and (total is None or total > n)),
            "rows": sorted(rows.values(), key=lambda r: (r["layer"], r["type"])),
            "blocks": [{"layer": k[0], "block": k[1], "count": v} for k, v in sorted(blocks.items())],
            "not_measured": skipped, "insunits": g(d, "Name") and d.GetVariable("INSUNITS")}


def _col(n: int) -> str:
    s = ""
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(65 + r) + s
    return s


def write_xlsx(path: str, sheets: list[tuple[str, list[list]]]):
    """Minimal .xlsx writer: first row bold, numbers as numbers, everything else as plain text (never formulas)."""
    ct = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>']
    wb, rel, parts = [], [], []
    for i, (name, rows) in enumerate(sheets, 1):
        ct.append(f'<Override PartName="/xl/worksheets/sheet{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>')
        wb.append(f'<sheet name="{escape(name, {chr(34): "&quot;"})}" sheetId="{i}" r:id="rId{i}"/>')
        rel.append(f'<Relationship Id="rId{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet{i}.xml"/>')
        width: dict = {}
        body = []
        for r, row in enumerate(rows, 1):
            cells = []
            for c, v in enumerate(row, 1):
                st = ' s="1"' if r == 1 else ""
                if v is None or v == "":
                    continue
                if isinstance(v, (int, float)) and not isinstance(v, bool) and v == v and abs(v) != float("inf"):
                    cells.append(f'<c r="{_col(c)}{r}"{st}><v>{v!r}</v></c>')
                else:
                    t = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", str(v))[:32000]
                    cells.append(f'<c r="{_col(c)}{r}" t="inlineStr"{st}><is><t xml:space="preserve">{escape(t)}</t></is></c>')
                width[c] = min(60, max(width.get(c, 8), len(str(v)) + 2))
            body.append(f'<row r="{r}">{"".join(cells)}</row>')
        cols = "".join(f'<col min="{c}" max="{c}" width="{w}" customWidth="1"/>' for c, w in sorted(width.items()))
        parts.append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
                     '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
                     + (f"<cols>{cols}</cols>" if cols else "") + f'<sheetData>{"".join(body)}</sheetData></worksheet>')
    n = len(sheets) + 1
    rel.append(f'<Relationship Id="rId{n}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>')
    head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    with zipfile.ZipFile(path, "x", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", "".join(ct) + "</Types>")
        z.writestr("_rels/.rels", head + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" '
                   'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
        z.writestr("xl/workbook.xml", head + '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                   'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>' + "".join(wb) + "</sheets></workbook>")
        z.writestr("xl/_rels/workbook.xml.rels", head + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + "".join(rel) + "</Relationships>")
        z.writestr("xl/styles.xml", head + '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
                   '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
                   '<borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="2"><xf/><xf fontId="1" applyFont="1"/></cellXfs></styleSheet>')
        for i, x in enumerate(parts, 1):
            z.writestr(f"xl/worksheets/sheet{i}.xml", x)


@tool("destructive")
def export_xlsx(path: str, sheets: dict[str, list[list[str | float | int | None]]]) -> dict:
    """Write tables to a NEW Excel file (ask the user first; existing files are never overwritten). sheets = {"Sheet name":
    [[header...], [row...], ...]}. Relative paths go to the Steve-CAD-AI folder. Numbers stay numbers."""
    if not sheets:
        raise UserError("Chưa có bảng nào.")
    p = path if os.path.isabs(path) else os.path.join(WORKSPACE, path)
    if not p.lower().endswith(".xlsx"):
        p += ".xlsx"
    if os.path.exists(p):
        raise UserError(f"Đã có {p}. Chọn tên khác.")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    used, out = set(), []
    for name, rows in sheets.items():
        nm = re.sub(r"[\[\]:*?/\\']", " ", name).strip()[:31] or "Sheet"
        base, k = nm, 2
        while nm.lower() in used:
            nm = f"{base[:28]} {k}"
            k += 1
        used.add(nm.lower())
        out.append((nm, rows))
    write_xlsx(p, out)
    return {"ok": True, "path": p, "sheets": [{"name": n, "rows": len(r)} for n, r in out]}
