---
name: viet-lisp
description: Viết lệnh AutoLISP cho ZWCAD/AutoCAD theo yêu cầu, kiểm tra, chạy thử trên bản vẽ nháp rồi lưu kèm hướng dẫn dùng.
---

# Skill: Viết AutoLISP

Tool dùng: `info`, `get_selection`, `lisp_check`, `lisp_save`, `lisp_test`.

## Bước 1. Làm rõ yêu cầu

Hỏi gọn, chỉ hỏi phần còn thiếu: tên lệnh (không dấu), người dùng chọn gì, nhập gì, kết quả ra sao, đơn vị, layer. Yêu cầu đã rõ thì làm luôn. Nếu người dùng đang chọn đối tượng mẫu, đọc bằng `get_selection`.

## Bước 2. Viết mã

- Một lệnh `(defun c:TEN ( / biến-cục-bộ) ...)`; khai báo **mọi** biến cục bộ; hàm phụ có tiền tố riêng theo tên lệnh.
- Có `*error*` cục bộ: trả lại biến hệ thống đã đổi và kết thúc UNDO khi người dùng bấm Esc.
- Gom một bước UNDO: `(command "_.UNDO" "_Begin")` ... `(command "_.UNDO" "_End")`.
- Lệnh gọi dạng `"_.LINE"`. Tắt rồi trả lại OSMODE khi truyền toạ độ vào `command`. Ưu tiên `entmake` / `entmakex` khi vẽ nhiều.
- Kiểm tra `nil` sau `ssget`, `entsel`, `getpoint`, `getdist`.
- Câu nhắc viết **không dấu**. Ghi chú đầu file: tên lệnh, công dụng, cách dùng, ngày.
- Chỉ dùng hàm có ở cả ZWCAD và AutoCAD. Hàm `vl-`, `vla-` cần `(vl-load-com)`.

## Bước 3. Kiểm tra

1. `lisp_check(code=...)`, sửa hết lỗi ngoặc và cảnh báo.
2. Có mục `danger` thì tìm cách viết không cần tới nó. Bắt buộc phải dùng thì nói rõ dòng nào, làm gì.

## Bước 4. Cho xem và lưu

Đưa **toàn bộ mã** cho người dùng xem, nói ngắn gọn mã làm gì. Họ đồng ý thì `lisp_save`.

## Bước 5. Chạy thử trên bản vẽ nháp

1. `lisp_test(path)`: chỉ nạp. Lỗi thì sửa, lưu lại (`overwrite=True`, có bản `.bak`) và thử lại, tối đa 5 lần.
2. Phần tính toán tách thành hàm nhận tham số thì thử bằng `run="(ten-ham 10 20)"`. Không `run` lệnh chờ người dùng bấm điểm.
3. Lệnh cần tương tác: nhờ người dùng gõ thử **trong bản vẽ nháp** và cho biết kết quả.

**Không** nạp vào bản vẽ đang làm việc khi người dùng chưa đồng ý. Không dùng `allow_danger=True` nếu họ chưa đồng ý rõ ràng.

## Bước 6. Bàn giao

Nói: đường dẫn file, tên lệnh, cách nạp (`APPLOAD`, muốn tự nạp thì thêm vào Startup Suite), cách dùng, giới hạn, đã thử được gì và **chưa thử gì**. Nhắc đóng bản vẽ nháp không cần lưu.
