# Máy chủ đăng ký (Google Sheet + Apps Script)

Làm một lần, khoảng 5 phút. Nên dùng một tài khoản Google riêng cho việc này: email chứa mã xác nhận được gửi **từ tài khoản đó**.

1. Vào <https://sheets.new>, đặt tên, ví dụ *Steve AI Connect - Đăng ký*.
2. **Tiện ích mở rộng → Apps Script**. Xoá nội dung có sẵn, dán toàn bộ [Code.gs](Code.gs), bấm Lưu.
3. Chọn hàm `caiDat`, bấm **Chạy**, cấp quyền (Sheet và gửi mail).
4. **Triển khai → Tùy chọn triển khai mới → Ứng dụng web**: *Thực thi với tư cách* = **Tôi**, *Ai có quyền truy cập* = **Bất kỳ ai**. Bấm Triển khai.
5. Chép URL kết thúc bằng `/exec`, dán vào `$script:RegisterUrl` trong `app/core.ps1`.

Sửa `Code.gs` về sau: **Triển khai → Quản lý các tùy chọn triển khai → Sửa → Phiên bản mới** (URL giữ nguyên).

- Không chia sẻ Google Sheet công khai: nó chứa thông tin cá nhân.
- Gmail thường gửi được khoảng 100 mail/ngày, Google Workspace nhiều hơn. Hết hạn mức thì người mới được dùng tạm 7 ngày.
- Có người yêu cầu xoá thông tin: xoá dòng của họ trong sheet `DangKy`.
