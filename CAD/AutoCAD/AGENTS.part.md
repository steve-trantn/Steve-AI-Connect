
## AutoCAD: server `autocad`

Điều khiển AutoCAD đang mở qua COM bằng Steve CAD MCP. Bộ tool giống hệt server `zwcad`:

- **Bắt đầu:** `info`. "Đối tượng này / đang chọn" → `get_selection`.
- **Đọc:** `list_drawings`, `list_layers`, `list_entities`, `get_entity`, `list_blocks`, `screenshot`
- **Tính toán:** `measure`, `count_blocks`, `find_duplicates`
- **Vẽ:** `line`, `polyline`, `polyline3d`, `rectangle`, `circle`, `arc`, `ellipse`, `text`, `mtext`, `hatch`, `insert_block`, `create_block`
- **Kích thước:** `dim_linear`, `dim_aligned`, `dim_radius`, `auto_dim`
- **Sửa:** `move`, `copy`, `rotate`, `scale`, `mirror`, `offset`, `array_rect`, `array_polar`, `set_props`, `delete`, `layer`
- **Bản vẽ:** `use_drawing`, `new_drawing`, `open_drawing`, `save`, `undo`, `redo`, `zoom`, `pick_points`, `pick_objects`, `command`
- **3D:** `solid_extrude` (đưa mặt cắt lên mặt phẳng 3D theo hướng tuyến, độ dốc, cao độ, rồi đùn thành khối), `solid_boolean`, `solid_slice`, `solid_box_from_points`, `boundary_at` (tạo đường bao kín từ một điểm), `view_3d`
- **Toạ độ, layer, IFC:** `place_on_site` (đưa mô hình về toạ độ thật: 1 điểm + góc, hoặc 2 cặp điểm như ALIGN), `organize_layers` (layer tự động theo tên cống/đường kính + lý trình + bộ phận), `tag_solids` (thông tin phi hình học), `export_ifc` (IFC4 hoặc IFC4X3, hình học chính xác, có Pset_SteveCAD, vật liệu, màu, khối lượng).
- **PDF:** `pdf_info`, `pdf_page_image` (xem trang hoặc một phần trang), `import_pdf` (nhập nét vẽ vector vào bản vẽ)
- **Skill:** `list_skills`, `get_skill`. Ví dụ `cong-3d`: dựng cống 3D từ bản vẽ DWG/PDF. Việc nhiều bước thì đọc skill rồi làm theo.
- Chữ font TCVN3/VNI trong bản vẽ được tự giải mã sang Unicode (`text`; bản gốc ở `text_raw`).
- Server không tự mở AutoCAD. AutoCAD chưa mở thì nhờ người dùng mở AutoCAD và một bản vẽ.
- Nếu tool báo AutoCAD bị một hộp thoại chặn (ví dụ hộp thoại bản quyền), nhờ người dùng đóng hộp thoại đó.
