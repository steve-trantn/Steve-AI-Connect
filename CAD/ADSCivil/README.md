# ADSCivil

- **MCP server:** `AdsMcpServer.exe`, có sẵn trong **ADSCivil NW 2027 For ZWCAD 2026**. Server nối với ADSCivil đang mở qua named pipe `\\.\pipe\adscivil-mcp-<PID của ZWCAD>`. Công cụ không chép file này đi đâu mà dùng ngay tại thư mục cài.
- **Tên server:** `adscivil`.
- **Tool:** khoảng 290 tool khi nối với ADSCivil 2027 (tuyến, trắc dọc, siêu cao, mạng cống, san nền, kiểm tra thiết kế, tra tiêu chuẩn TCVN, hướng dẫn sử dụng...). Khi ADSCivil chưa mở chỉ còn khoảng 25 tool tra cứu.
- Chọn được phiên ADSCivil khi mở nhiều ZWCAD: đặt biến môi trường `ADSCIVIL_MCP_PIPE=\\.\pipe\adscivil-mcp-<PID>`.

## ADSCivil NW 2026

Module AI của bản 2027 (`Ads.System.AI.Assistant.zrx`) chỉ phụ thuộc ZWCAD, nên chạy được trong ADSCivil 2026. Khi tích **"ADSCivil 2026: tự nạp trợ lý ADSAI"**, công cụ chạy [install-2026-autoload.ps1](install-2026-autoload.ps1):

1. chép `Ads.System.AI.Assistant.zrx`, `AdsMcpServer.exe` và `AdsAI\` từ thư mục 2027 sang thư mục 2026;
2. thêm [ads-ai-autoload.lsp](ads-ai-autoload.lsp) vào cuối `ZWCAD.lsp` của bản 2026 (sao lưu trước, chỉ thêm một lần).

Khởi động ADSCivil 2026: dòng lệnh hiện `ADSCivil AI: da nap. Go ADSAI de mo tro ly AI.`

Giới hạn:

- Bản 2026 chỉ có nhóm tool chung (khoảng 49 tool). Tool nghiệp vụ chỉ có trên bản 2027.
- Cài lại ADSCivil 2026 sẽ ghi đè `ZWCAD.lsp`. Khi đó bấm Connect lại.
- Disconnect (khi có tích ô 2026) hoặc Uninstall sẽ gỡ đoạn tự nạp, trả `ZWCAD.lsp` về như cũ.

Lời dặn cho AI: [AGENTS.part.md](AGENTS.part.md).
