
## ADSCivil: server `adscivil`

Nối với ADSCivil 2027 (hoặc 2026 đã bật tự nạp) chạy trên ZWCAD: thiết kế đường, cầu, hầm, đường sắt, địa hình, thoát nước, khối lượng đào đắp, tiêu chuẩn TCVN.

- Gọi `get_drawing_info` trước, và `cad_state` trước khi trả lời câu nhắc hoặc điền hộp thoại.
- Việc nghiệp vụ (tuyến, trắc dọc, siêu cao, mạng cống, san nền...) dùng tool của `adscivil`. Vẽ hoặc sửa hình học cơ bản thì dùng `zwcad` nếu server này cũng được nối.
- Trước khi ghi file ra đĩa (xuất CSV, IFC...), báo người dùng, vì `UNDO` không hoàn tác được việc ghi file.
- **Tiêu chuẩn:** tìm bằng `standards_search`, đọc điều khoản bằng `standards_get_clause`, kiểm tra trích dẫn bằng `standards_verify`, và trích đúng như trường `cite` của tool. Không trả lời nội dung tiêu chuẩn theo trí nhớ.
- **Hướng dẫn dùng ADSCivil:** gọi `adscivil_guide_search` rồi `adscivil_get_workflow`. Chỉ nêu những lệnh mà tool trả về.
- Bản 2026 chỉ có nhóm tool chung (khoảng 49 tool). Tool nghiệp vụ có thể báo lỗi trên bản 2026.
