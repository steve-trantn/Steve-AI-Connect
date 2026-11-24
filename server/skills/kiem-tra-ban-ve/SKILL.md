---
name: kiem-tra-ban-ve
title: Kiểm tra bản vẽ
description: Soát lỗi bản vẽ (trùng đối tượng, sai layer, màu gán tay, kích thước sửa tay, text rỗng, xref mất) rồi báo cáo; chỉ sửa khi được đồng ý.
---

# Skill: Kiểm tra bản vẽ

Tool dùng: `info`, `audit`, `find_duplicates`, `list_layers`, `list_entities`, `get_entity`, `zoom`, `screenshot`, `set_props`, `delete`.

## Bước 1. Phạm vi

`info` để biết bản vẽ, đơn vị, số đối tượng. Bản vẽ lớn thì hỏi muốn soát toàn bộ hay một vài layer. Công ty có bảng layer chuẩn thì xin bảng đó.

## Bước 2. Quét (chỉ đọc)

1. `audit`. Nếu `partial` là true, nói rõ mới quét bao nhiêu / tổng số; tăng `max_objects` khi người dùng đồng ý chờ.
2. `find_duplicates(delete=False)` theo từng layer có nhiều đường.
3. Có bảng layer chuẩn: so với `list_layers`, nêu layer thừa, thiếu, sai màu.
4. Kích thước sửa tay (`dim_override`): so `shown` với `measured`. Chênh lệch do làm tròn hay do tỷ lệ là chuyện khác nhau, đừng kết luận là sai khi chưa xét.

## Bước 3. Báo cáo

Bảng: mức (Cần sửa / Nên xem / Ghi nhận), lỗi, số lượng, layer hoặc handle ví dụ, đề xuất. Không suy diễn: điều chưa kiểm tra (block lồng, layout, đúng sai thiết kế) ghi là **chưa kiểm tra**.

## Bước 4. Sửa khi được đồng ý

Hỏi sửa mục nào. Làm từng nhóm, mỗi nhóm một bước UNDO, xong báo số đối tượng đã đổi và nhắc `UNDO`. Xoá đối tượng trùng phải được đồng ý riêng. Không tự sửa số kích thước. Sửa xong chạy lại `audit` để so trước / sau.
