---
name: khung-ten
title: Khung tên
group: Bản vẽ
description: Đọc, so khớp và điền thuộc tính khung tên hàng loạt, lập danh mục bản vẽ ra Excel.
---

# Skill: Khung tên và danh mục bản vẽ

Tool dùng: `info`, `list_blocks`, `list_attributes`, `set_attributes`, `export_xlsx`.

## Bước 1. Tìm khung tên

`list_blocks`, rồi `list_attributes(block=...)` với block nghi là khung tên (đọc cả mô hình và layout). Khung tên không có attribute (chữ rời): nói rõ là skill này chưa điền tự động được.

## Bước 2. Đọc và soát

Lập bảng mỗi khung một dòng: layout, handle, các thuộc tính. Nêu số bản vẽ trùng, ô trống, tên dự án viết khác nhau, ngày hoặc tỷ lệ lệch. Chỉ nêu, không tự sửa.

## Bước 3. Điền

Hỏi ô nào đổi thành gì. Số bản vẽ tăng dần: hỏi thứ tự và tiền tố. Cho xem bảng **cũ → mới**, đồng ý thì `set_attributes`. Không tự điền tên người, chữ ký, ngày duyệt. Nhắc `UNDO`.

## Bước 4. Danh mục

`export_xlsx`: STT, số bản vẽ, tên bản vẽ, tỷ lệ, layout, ghi chú. Báo trước đường dẫn. Đọc lại bằng `list_attributes` để xác nhận đã điền đúng.
