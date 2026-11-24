---
name: chuan-layer
title: Chuẩn layer
group: Bản vẽ
description: Đổi layer, màu, kiểu nét theo bảng layer chuẩn của công ty; cho xem bảng ánh xạ trước khi đổi.
---

# Skill: Chuẩn hoá layer

Tool dùng: `info`, `list_layers`, `list_entities`, `audit`, `layer`, `set_props`, `export_xlsx`.

## Bước 1. Lấy bảng chuẩn

Xin bảng layer chuẩn (tên, màu, kiểu nét, dùng cho gì): dán vào chat, file, hoặc một bản vẽ mẫu đang mở. Không có bảng thì không tự đặt ra tên layer.

## Bước 2. Lập bảng ánh xạ

`list_layers` rồi lập bảng: layer hiện có, số đối tượng, layer chuẩn đề xuất, độ chắc (chắc / cần hỏi). Chỉ ghi "chắc" khi tên gần như trùng. Layer 0, Defpoints và layer của xref (có dấu `|`) giữ nguyên. Đối tượng gán màu tay: hỏi có đổi về ByLayer không.

## Bước 3. Xin duyệt

Cho xem cả bảng, hỏi các dòng chưa chắc. Cần lưu hồ sơ thì `export_xlsx` (báo trước đường dẫn).

## Bước 4. Đổi

1. Tạo hoặc sửa layer chuẩn bằng `layer`.
2. Từng layer cũ: `list_entities(layer=...)` lấy handle (đi hết các trang), rồi `set_props(layer=...)`. Mỗi lần gọi là một bước UNDO.
3. Không xoá layer cũ khi chưa được đồng ý riêng.

## Bước 5. Đối chiếu

`list_layers` lại: tổng số đối tượng trước và sau phải bằng nhau. Nêu phần chưa đổi: đối tượng trong block, trong layout, layer khoá. Nhắc `UNDO`.
