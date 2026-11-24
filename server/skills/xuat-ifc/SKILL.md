---
name: xuat-ifc
title: Export IFC
group: Mô hình 3D / BIM
description: Xuất khối 3D trong bản vẽ ra file IFC4 hoặc IFC4X3 (IFC 4.3), kèm vật liệu, màu, khối lượng và thông tin phi hình học.
---

# Skill: Xuất IFC

Tool dùng: `info`, `get_selection`, `solid_info`, `tag_solids`, `export_ifc`.

## Bước 1. Xem trước

Gọi `info` (đơn vị bản vẽ), rồi `export_ifc(path="IFC\\xem-truoc", preview=True, ...)`: chưa ghi file, chỉ trả số khối, số khối xuất chính xác, số khối chỉ xuất được dạng hộp bao, và theo layer.

- Chỉ xuất **khối solid 3D**. Corridor, surface, pipe network của Civil 3D và block chứa khối không được xuất: nói rõ nếu bản vẽ có.
- Khối không do tool Steve CAD dựng (hoặc đã bị sửa) chỉ xuất dạng **hộp bao**. Nêu số lượng trước khi xuất.

Cấu trúc file: công trình > nhóm (Thân cống, Móng thân cống, Cửa thượng lưu, Cửa hạ lưu) > bộ phận. `solid_info(units=...)` trả cây này kèm số đốt, chiều dài, khẩu độ hoặc đường kính, khối lượng: cho người dùng xem trước. `detail="part"` gộp bộ phận giống nhau thành một; `"solid"` tách từng khối. `unit_hint` khác đơn vị khai báo thì phải hỏi lại. Nhóm sai thì sửa bằng `props.group`.

Mỗi cống trong `structures` có `geo` (cao độ đáy, độ dốc, phương vị, góc chéo, chiều dài thật; không tính được thì bỏ trống, lý do ở `notes`), `issues` (lỗi, cảnh báo) và `handles`. Nêu các cống có lỗi trước khi xuất. Nhiều cống: `groups=[handles của từng cống]` để chọn cống, `split=True` để mỗi cống một file. Khối chưa rõ cống: xem `suggestions`, hỏi rồi mới `tag_solids`.

## Bước 2. Thông tin phi hình học

`solid_info` đọc tên, bộ phận, vật liệu, công trình, lý trình, loại và các thông tin thêm. Nêu ô còn trống; hỏi giá trị, không tự bịa. Cho xem bảng **cũ → mới**, đồng ý thì `tag_solids(rows=[...])` (một bước `UNDO`). `name` là Name trong IFC.

## Bước 3. Hỏi

Phạm vi (tất cả, đang chọn, một layer), IFC4 hay IFC4X3, **đơn vị bản vẽ** (m, mm, cm, ft, us-ft, inch; không đoán khi `info` không rõ), tên dự án. Hỏi lưu ở đâu.

## Bước 4. Xuất

Báo đường dẫn, được đồng ý mới gọi `export_ifc`. Ghi file không hoàn tác bằng `UNDO`. Báo cáo: đường dẫn, số khối, số khối gần đúng, dung lượng; nhắc mở thử bằng phần mềm xem IFC.
