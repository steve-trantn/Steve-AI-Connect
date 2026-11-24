---
name: xuat-ifc
title: Export IFC
group: Mô hình 3D / BIM
description: Xuất khối 3D trong bản vẽ ra file IFC4 hoặc IFC4X3 (IFC 4.3), kèm vật liệu, màu, khối lượng và thông tin phi hình học.
---

# Skill: Xuất IFC

Tool dùng: `info`, `list_entities`, `get_selection`, `tag_solids`, `export_ifc`.

## Bước 1. Xem trước

Gọi `info` (đơn vị bản vẽ), rồi `export_ifc(path="IFC\\xem-truoc", preview=True, ...)`: chưa ghi file, chỉ trả số khối, số khối xuất chính xác, số khối chỉ xuất được dạng hộp bao, và theo layer.

- Chỉ xuất **khối solid 3D**. Corridor, surface, pipe network của Civil 3D và block chứa khối không được xuất: nói rõ nếu bản vẽ có.
- Khối không do tool Steve CAD dựng (hoặc đã bị sửa) chỉ xuất dạng **hộp bao**. Nêu số lượng trước khi xuất.

## Bước 2. Hỏi

Phạm vi (tất cả, đang chọn, một layer), IFC4 hay IFC4X3, **đơn vị bản vẽ** (m, mm, cm, ft, us-ft, inch; không đoán khi `info` không rõ), tên dự án. Thiếu tên bộ phận, vật liệu thì đề nghị `tag_solids`.

## Bước 3. Xuất

Báo đường dẫn, được đồng ý mới gọi `export_ifc`. Ghi file không hoàn tác bằng `UNDO`. Báo cáo: đường dẫn, số khối, số khối gần đúng, dung lượng; nhắc mở thử bằng phần mềm xem IFC.
