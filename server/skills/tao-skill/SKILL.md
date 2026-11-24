---
name: tao-skill
title: Tạo skill
description: Biến quy trình làm việc của bạn thành skill riêng để AI làm lại y hệt những lần sau.
---

# Skill: Tạo skill mới

Tool dùng: `list_skills`, `get_skill`, `save_skill`.

## Bước 1. Hiểu quy trình

Hỏi: việc gì, đầu vào (bản vẽ, file, số liệu), các bước đang làm tay, kết quả cần có, quy định riêng (layer, đơn vị, tên file), bước nào phải hỏi người dùng. Vừa cùng làm xong một việc thì rút quy trình từ chính việc đó. Gọi `list_skills` để tránh trùng.

## Bước 2. Soạn

Viết tiếng Việt, ngắn, cho một AI khác đọc là làm được:

- Mục tiêu và tool sẽ dùng (chỉ dùng tool có thật).
- Các bước đánh số: làm gì, gọi tool nào, kiểm tra gì trước khi sang bước sau.
- Chỗ phải hỏi: số liệu thiếu, trước khi xoá, lưu, ghi file.
- Cách kiểm tra kết quả và nội dung báo cáo cuối.

Không đưa vào skill: mật khẩu, thông tin cá nhân hay mật của dự án, số liệu chỉ đúng cho một bản vẽ, chỉ dẫn bỏ qua việc hỏi người dùng.

## Bước 3. Duyệt và lưu

Đưa toàn văn cho người dùng duyệt, đồng ý thì `save_skill`. Skill riêng nằm ở `Steve-CAD-AI\skills`, cập nhật công cụ không làm mất. Skill hiện trong nút **＋** của khung chat ở phiên mới.

## Bước 4. Thử

Chạy thử một lần trên bản vẽ nhỏ, sửa chỗ chưa rõ rồi lưu lại. Thấy hữu ích cho người khác thì gợi ý gửi Steve qua **Đề xuất tính năng**.
