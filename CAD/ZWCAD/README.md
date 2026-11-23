# ZWCAD

- **MCP server:** Steve CAD MCP ([server/](../../server)), viết riêng cho công cụ này. Server điều khiển ZWCAD qua COM.
- **Tên server:** `zwcad`.
- **Cài vào:** `%LOCALAPPDATA%\SteveCADConnect\server`. Python dùng chung tại `%LOCALAPPDATA%\SteveCADConnect\venv`.
- **ProgID:** công cụ tự chọn bản ZWCAD mới nhất có trên máy (ví dụ `ZWCAD.Application.2026`) và truyền vào server bằng `--progid`.
- Server chỉ nối vào ZWCAD **đang mở**, không tự khởi động ZWCAD.
- **Đã thử:** ZWCAD 2026 Professional.

Lời dặn cho AI: [AGENTS.part.md](AGENTS.part.md). Danh sách tool: [server/README.md](../../server/README.md).
