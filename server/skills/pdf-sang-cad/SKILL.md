---
name: pdf-sang-cad
title: PDF sang CAD
description: Nhập bản vẽ PDF có nét vector vào CAD đúng tỷ lệ, kiểm tra bằng kích thước đã biết và tách layer.
---

# Skill: PDF sang CAD

Tool dùng: `pdf_info`, `pdf_page_image`, `new_drawing`, `import_pdf`, `measure`, `scale`, `list_entities`, `set_props`, `layer`, `screenshot`.

## Bước 1. Xem PDF

`pdf_info(path)`, rồi `pdf_page_image` trang cần dùng. PDF là ảnh scan (không có nét vector) thì nói rõ: không chuyển tự động được, chỉ vẽ lại theo kích thước đọc được.

## Bước 2. Hỏi

Trang nào, phần nào (crop), tỷ lệ ghi trên bản vẽ, đơn vị, nhập vào bản vẽ mới (khuyên dùng) hay bản đang mở.

## Bước 3. Nhập

`import_pdf(path, page, insert_point, scale, crop)`; `scale` là mẫu số tỷ lệ. Nhiều hình khác tỷ lệ trên một trang thì nhập từng hình với `crop` riêng.

## Bước 4. Kiểm tra tỷ lệ (bắt buộc)

Chọn ít nhất hai kích thước có ghi số, một ngang một đứng, đo bằng `measure`. Lệch quá 0,5% thì tính lại hệ số, cho người dùng xem rồi `scale`. Ngang và đứng lệch khác nhau: PDF bị co méo, dừng lại và báo.

## Bước 5. Dọn

Tách layer theo màu hoặc độ dày nét nếu người dùng cần. Chữ trong PDF có thể thành nét vẽ: báo, đừng tự gõ lại số liệu khi đọc không rõ. Chỉ xoá nét thừa khi được đồng ý.

## Bước 6. Báo cáo

Số đối tượng, hệ số tỷ lệ và sai lệch đo được, phần chưa chuyển được, nhắc kiểm tra lại trước khi dùng để thi công.
