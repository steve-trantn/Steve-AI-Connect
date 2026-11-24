# Máy chủ đăng ký (Google Sheet + Apps Script)

Làm một lần, khoảng 5 phút. Nên dùng một tài khoản Google riêng cho việc này: email chứa mã xác nhận được gửi **từ tài khoản đó**.

1. Vào <https://sheets.new>, đặt tên, ví dụ *Steve AI Connect - Đăng ký*.
2. **Tiện ích mở rộng → Apps Script**. Xoá nội dung có sẵn, dán toàn bộ [Code.gs](Code.gs), bấm Lưu.
3. Chọn hàm `caiDat`, bấm **Chạy**, cấp quyền (Sheet, gửi mail và Google Drive để nhận gói skill).
4. **Triển khai → Tùy chọn triển khai mới → Ứng dụng web**: *Thực thi với tư cách* = **Tôi**, *Ai có quyền truy cập* = **Bất kỳ ai**. Bấm Triển khai.
5. Chép URL kết thúc bằng `/exec`, dán vào `$script:RegisterUrl` trong `app/core.ps1`.

**Cập nhật code không làm mất dữ liệu:** dữ liệu nằm trong Sheet, code chỉ thêm dòng hoặc cập nhật dòng có sẵn. Dán code mới xong chạy `caiDat`: hàm này sao lưu từng bảng sang sheet ẩn rồi mới định dạng. Đừng đổi tên sheet, đổi thứ tự hay chèn cột; muốn thêm cột riêng thì thêm ở bên phải cùng.

Sửa `Code.gs` về sau: **Triển khai → Quản lý các tùy chọn triển khai → Sửa → Phiên bản mới** (URL giữ nguyên).

- Không chia sẻ Google Sheet công khai: nó chứa thông tin cá nhân.
- Gmail thường gửi được khoảng 100 mail/ngày, Google Workspace nhiều hơn. Hết hạn mức thì người mới được dùng tạm 7 ngày.
- Gói skill nằm trong thư mục Drive *Steve AI Connect - Skill gop y* (riêng tư, đừng chia sẻ); sheet `SkillGoi` ghi mã biên nhận, link và SHA-256. Kiểm tra file tải về: `Get-FileHash <file>`. Đọc kỹ trước khi dùng, không chạy `.lsp` chưa đọc.
- Có người yêu cầu xoá thông tin: xoá dòng của họ trong sheet `DangKy`, `YeuCau`, `SkillGopY`, `SkillGoi` (và file trên Drive), và cả trong các sheet ẩn `..._SaoLuu_...`.
