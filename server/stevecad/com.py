"""COM plumbing: one dedicated STA thread talks to the CAD; every COM call is retried while the CAD says 'busy'."""
from __future__ import annotations

import concurrent.futures
import time

import pythoncom
import pywintypes
import win32com.client
import win32com.client.dynamic
from win32com.client.dynamic import CDispatch

# CAD flavours: product label + the ProgID registered in the Running Object Table
CADS = {
    "zwcad": {"label": "ZWCAD", "progid": "ZWCAD.Application"},
    "autocad": {"label": "AutoCAD", "progid": "AutoCAD.Application"},
}

RPC_E_CALL_REJECTED = -2147418111          # 0x80010001
RPC_E_SERVERCALL_RETRYLATER = -2147417846  # 0x8001010A
BUSY_CODES = (RPC_E_CALL_REJECTED, RPC_E_SERVERCALL_RETRYLATER)
BUSY_WAIT_S = 10.0

EXECUTOR = concurrent.futures.ThreadPoolExecutor(max_workers=1, thread_name_prefix="cad-sta",
                                                 initializer=pythoncom.CoInitialize)


def busy_retry(fn, *a, **k):
    """A call the CAD rejected because it was busy was never executed, so retrying it is safe."""
    deadline = time.monotonic() + BUSY_WAIT_S
    delay = 0.05
    while True:
        try:
            return fn(*a, **k)
        except (pywintypes.com_error, AttributeError) as e:
            # late binding turns a rejected GetIDsOfNames into AttributeError; the COM error is in __context__
            ce = e if isinstance(e, pywintypes.com_error) else e.__context__
            busy = isinstance(ce, pywintypes.com_error) and ce.hresult in BUSY_CODES
            if busy and time.monotonic() < deadline:
                time.sleep(delay)
                delay = min(delay * 1.5, 0.5)
                continue
            if busy:
                raise ce from None
            raise


def _unwrap(v):
    if isinstance(v, Com):
        return object.__getattribute__(v, "_o")
    if isinstance(v, (list, tuple)):
        return type(v)(_unwrap(x) for x in v)
    return v


def late(o):
    """Always late-bound: a makepy (gen_py) cache left by other software changes property names and breaks
    entity-specific properties, so never use early-bound wrappers."""
    if isinstance(o, CDispatch) and type(o) is CDispatch:
        return o
    raw = getattr(o, "_oleobj_", o)
    return win32com.client.dynamic.Dispatch(raw.QueryInterface(pythoncom.IID_IDispatch))


def _is_com(x):
    return isinstance(x, CDispatch) or type(x).__name__ == "PyIDispatch" or (
        hasattr(type(x), "CLSID") and hasattr(x, "_oleobj_"))


def _wrap(v):
    if isinstance(v, Com):
        return v
    if _is_com(v):
        return Com(late(v))
    if isinstance(v, tuple) and v and any(_is_com(x) for x in v):
        return tuple(_wrap(x) for x in v)
    return v


class Com:
    """Thin proxy over a late-bound COM object: property reads, writes and method calls go through busy_retry,
    and COM objects coming back are proxied too."""
    __slots__ = ("_o",)

    def __init__(self, o):
        object.__setattr__(self, "_o", o)

    def __getattr__(self, name):
        o = object.__getattribute__(self, "_o")
        if name == "_oleobj_":
            return o._oleobj_
        v = busy_retry(getattr, o, name)
        if callable(v) and not isinstance(v, CDispatch):
            def call(*a, **k):
                return _wrap(busy_retry(v, *(_unwrap(x) for x in a), **{n: _unwrap(x) for n, x in k.items()}))
            return call
        return _wrap(v)

    def __setattr__(self, name, value):
        busy_retry(setattr, object.__getattribute__(self, "_o"), name, _unwrap(value))

    def __repr__(self):
        return f"<Com {object.__getattribute__(self, '_o')!r}>"


class CadNotRunning(Exception):
    pass


class Connection:
    """Holds the Application object of the running CAD. Never starts a hidden CAD instance."""

    def __init__(self, cad: str, progid: str | None = None):
        if cad not in CADS:
            raise ValueError(f"cad must be one of {list(CADS)}")
        self.cad = cad
        self.label = CADS[cad]["label"]
        self.progids = [p for p in (progid, CADS[cad]["progid"]) if p]
        self._app = None

    def running(self) -> list[dict]:
        """Every running CAD of this kind that can be reached, newest first (several AutoCAD / Civil 3D versions can be open)."""
        ids = [self.progids[-1]]
        if self.cad == "autocad":
            ids += [f"AutoCAD.Application.{v}" for v in ("26.1", "26", "25.1", "25", "24.3", "24.2", "24.1", "24")]
        out, seen = [], set()
        for pid in ids:
            try:
                a = Com(late(busy_retry(pythoncom.GetActiveObject, pywintypes.IID(pid))))
                hwnd = int(a.HWND)
                if hwnd in seen:
                    continue
                seen.add(hwnd)
                out.append({"name": a.Name, "version": a.Version, "title": a.Caption, "app": a})
            except Exception:   # not registered, not running, or still starting
                continue
        return out

    def app(self) -> Com:
        if self._app is not None:
            try:
                self._app.Name
                return self._app
            except pywintypes.com_error:
                self._app = None
        last = None
        for pid in self.progids:
            try:
                clsid = pywintypes.IID(pid)
                unk = busy_retry(pythoncom.GetActiveObject, clsid)
                self._app = Com(late(unk))
                return self._app
            except pywintypes.com_error as e:
                last = e
        raise CadNotRunning(
            f"Không thấy {self.label} đang mở. Hãy mở {self.label} và một bản vẽ rồi thử lại "
            f"(server không tự khởi động {self.label}).") from last


def blocking_dialog(app) -> str | None:
    """Title of a modal dialog that blocks the CAD (its main window is disabled), if any."""
    try:
        import win32gui
        import win32process
        main = win32gui.GetAncestor(int(object.__getattribute__(app, "_o").HWND), 2)
        if win32gui.IsWindowEnabled(main):
            return None
        pid = win32process.GetWindowThreadProcessId(main)[1]
        found = []

        def cb(h, _):
            if (h != main and win32gui.IsWindowVisible(h) and win32gui.IsWindowEnabled(h)
                    and win32process.GetWindowThreadProcessId(h)[1] == pid and win32gui.GetWindowText(h)):
                found.append(win32gui.GetWindowText(h))
        win32gui.EnumWindows(cb, None)
        return found[0] if found else "(hộp thoại không tên)"
    except Exception:
        return None


def com_message(e: Exception) -> str:
    """Readable text for a COM error, including the CAD's own description when there is one."""
    if isinstance(e, pywintypes.com_error):
        hr, msg, exc, _ = (list(e.args) + [None] * 4)[:4]
        if hr in BUSY_CODES:
            return "CAD đang bận (đang chạy lệnh hoặc mở hộp thoại). Bấm Esc trong CAD rồi thử lại."
        desc = str(exc[2]).strip() if exc and len(exc) > 2 and exc[2] else ""
        return desc or msg or f"COM error {hr}"
    return f"{type(e).__name__}: {e}"
