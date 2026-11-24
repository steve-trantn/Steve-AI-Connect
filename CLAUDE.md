# Steve AI Connect: quy tắc làm việc cho AI viết code

Trả lời tiếng Việt. Sản phẩm cho người dùng không rành kỹ thuật: mọi câu hiển thị phải rõ và có dấu.

## Quy trình (rút gọn từ 3 ý của obra/superpowers, giấy phép MIT; không cài cả bộ)

1. **Thử trước.** Sửa lỗi: viết bài thử tái hiện lỗi trong `tests/` rồi mới sửa. Tính năng mới: có bài thử kèm theo.
2. **Tìm nguyên nhân gốc.** Đọc lỗi, tái hiện, so với lần chạy được, rồi mới sửa một chỗ. Không vá theo phỏng đoán. Nghi "lỗi do bài thử" thì phải chứng minh.
3. **Kiểm chứng rồi mới báo xong.** Chạy lại lệnh thật và đọc kết quả; nói rõ cái gì chưa thử. Giao diện: chụp hình và nhìn (`STEVECAD_SNAPSHOT` + `STEVECAD_SNAPDIALOG`, hoặc `SteveAIChat.exe -skill ui-help -snapshot file.png`).

Việc nhỏ làm gọn, không lập kế hoạch dài, không dùng agent con khi không được yêu cầu.

## Lệnh

- Thử tất cả: `powershell -ExecutionPolicy Bypass -File tests\run.ps1` (khoảng 2-5 phút, phải ra `ALL PASSED`)
- Đóng gói: `build\build-exe.ps1` trên bản sạch (`git archive HEAD`), phải có đủ 3 file `SteveAIPanel.*.dll`
- Phát hành: chỉ khi người dùng bảo. Nâng số phiên bản ở `VERSION`, `CITATION.cff`, `README.md`; sau khi đẩy phải tải lại file và đối chiếu SHA-256.

## Không được

- Chạy `app\*.ps1` hay `SteveAIChat.exe` của repo để thử mà không đặt `STEVECAD_DRYRUN=1` (kể cả với thư mục tạm: registry và thư mục plugin vẫn là của máy thật).
- Để bài thử đụng vào registry, thư mục cài đặt hay CAD thật của máy.
- Nói "đã thử" khi chỉ mới thử với máy chủ giả lập. Bộ thử **không thay** việc bấm nút trong ZWCAD, AutoCAD và Civil 3D.
- Đổi thứ tự cột của các sheet trong `register/Code.gs`, hay xoá dữ liệu cũ.
- Hiện QR cà phê khi người dùng chưa bấm. Đưa thiết lập bảo mật hoặc gỡ cài đặt lên ribbon.
- Đưa dữ liệu của người dùng lên dòng lệnh (dùng stdin), hoặc gửi đi khi họ chưa thấy đúng nội dung sẽ gửi.
