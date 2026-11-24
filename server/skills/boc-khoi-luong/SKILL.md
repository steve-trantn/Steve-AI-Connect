---
name: boc-khoi-luong
title: Bóc khối lượng
description: Bóc khối lượng từ bản vẽ (chiều dài, diện tích, đếm block theo layer), đổi đơn vị, ghi rõ nguồn từng số và xuất Excel.
---

# Skill: Bóc khối lượng

Tool dùng: `info`, `quantities`, `measure`, `count_blocks`, `find_duplicates`, `list_entities`, `pick_objects`, `screenshot`, `export_xlsx`.

## Bước 1. Xác nhận trước khi đo

- **Đơn vị bản vẽ** (`info`) và **tỷ lệ**: hình vẽ 1:1 hay thu nhỏ? Không chắc thì đo một kích thước đã biết rồi hỏi. Đây là chỗ sai nhiều nhất.
- **Phạm vi:** toàn bản vẽ, vùng `window`, layer, hay đối tượng đang chọn. Bản vẽ có nhiều hình chiếu của cùng một cấu kiện thì chỉ bóc **một** hình, tránh tính lặp.
- **Danh mục:** đầu việc nào ứng với layer / block nào, đơn vị tính (m, m², m³, cái), công thức nếu cần (chiều dài × rộng × dày).

## Bước 2. Làm sạch số liệu

`find_duplicates` trên các layer sẽ bóc. Có trùng thì nói số lượng và hỏi: loại ra khỏi phép tính hay xoá.

## Bước 3. Đo

`quantities(...)` cho từng phạm vi. Nếu `partial` là true thì số chưa đủ: chia nhỏ theo layer hoặc vùng. Xem `not_measured`: loại nào không đo được phải nêu ra. Đường hở nhưng cần diện tích thì không tự đóng, báo người dùng.

## Bước 4. Tính

Mỗi dòng ghi: đầu việc, layer/block, số lượng, chiều dài, diện tích, hệ số đổi đơn vị, công thức, kết quả. Số đo từ bản vẽ và số **người dùng cung cấp** (dày, cao, dung trọng) để ở hai cột khác nhau. Thiếu số thì hỏi, không tự giả định. Không cộng hao hụt nếu không được yêu cầu.

## Bước 5. Đối chiếu

Kiểm tay ít nhất 2 dòng lớn nhất: lấy `sample_handles`, gọi `measure`, hoặc so với bảng thống kê có sẵn trong bản vẽ. Nêu chênh lệch.

## Bước 6. Xuất

Cho xem bảng, đồng ý thì `export_xlsx` (báo trước đường dẫn; `UNDO` không xoá được file). Gồm sheet *Tong hop*, *Chi tiet* (layer, handle mẫu, phạm vi) và *Gia thiet* (đơn vị, tỷ lệ, số người dùng cung cấp, phần chưa bóc).
