"""Entry point: python run.py --cad zwcad|autocad [--progid ZWCAD.Application.2026] [--allow-script]"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from stevecad.tools import build  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description="Steve CAD MCP server")
    ap.add_argument("--cad", choices=["zwcad", "autocad"], required=True)
    ap.add_argument("--progid", default=None, help="ProgID override, e.g. ZWCAD.Application.2026")
    ap.add_argument("--allow-script", action="store_true", help="enable the run_script tool")
    a = ap.parse_args()
    allow = a.allow_script or os.environ.get("STEVECAD_ALLOW_SCRIPT") == "1"
    build(a.cad, a.progid, allow).run("stdio")


if __name__ == "__main__":
    main()
