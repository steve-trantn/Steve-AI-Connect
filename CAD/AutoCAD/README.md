# AutoCAD

- **MCP server:** Steve CAD MCP ([server/](../../server)), dùng chung với ZWCAD, cùng bộ tool. Server điều khiển AutoCAD qua COM.
- **Tên server:** `autocad`.
- **Cài vào:** `%LOCALAPPDATA%\SteveCADConnect\server`.
- Server nối vào AutoCAD **đang mở**. Nếu mở nhiều bản, server nối vào bản đăng ký COM trước. Server không tự khởi động AutoCAD.
- **Cần bản AutoCAD đầy đủ.** AutoCAD LT không có COM nên không dùng được.
- **Đã thử:** AutoCAD 2026, các tool vẽ chạy được. Khi AutoCAD đang mở một hộp thoại (ví dụ hộp thoại bản quyền "Desktop Licensing Service"), mọi lệnh COM bị chặn; server sẽ báo tên hộp thoại để người dùng đóng.

### Về "Autodesk AutoCAD MCP Server"

Autodesk có cài kèm một MCP server chính hãng (`AutoCAD-MCP-Server-2027.bundle`), nhưng nó chỉ chạy với **AutoCAD 2027** (R26) và chưa có tài liệu công khai. Khi Autodesk công bố cách dùng, công cụ sẽ bổ sung lựa chọn này.

Lời dặn cho AI: [AGENTS.part.md](AGENTS.part.md). Danh sách tool: [server/README.md](../../server/README.md).
