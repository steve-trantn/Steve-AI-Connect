
## ZWCAD: server `zwcad`

Điều khiển ZWCAD đang mở qua COM bằng Steve CAD MCP.

- **Bắt đầu:** `info` (bản vẽ, đơn vị, phạm vi bản vẽ, layer hiện hành). "Đối tượng này / đang chọn" → `get_selection`.
- **Đọc:** `list_drawings`, `list_layers`, `list_entities` (lọc theo loại, layer hoặc cửa sổ `window`, có phân trang), `get_entity`, `list_blocks`, `screenshot`
- **Tính toán:** `measure` (chiều dài, diện tích, kèm tổng), `count_blocks`, `find_duplicates`
- **Vẽ:** `line`, `polyline`, `polyline3d`, `rectangle`, `circle`, `arc`, `ellipse`, `text`, `mtext`, `hatch`, `insert_block` (điền được attribute), `create_block`
- **Kích thước:** `dim_linear`, `dim_aligned`, `dim_radius`, `auto_dim` (ghi kích thước mọi cạnh, tự đặt ra phía ngoài)
- **Sửa:** `move`, `copy`, `rotate`, `scale`, `mirror`, `offset`, `array_rect`, `array_polar`, `set_props`, `delete`, `layer`. Mỗi tool nhận nhiều handle một lần.
- **Bản vẽ:** `use_drawing` (ghim bản vẽ làm việc), `new_drawing`, `open_drawing`, `save`, `undo`, `redo`, `zoom`
- **Hỏi người dùng trên màn hình:** `pick_points` (nhờ bấm điểm), `pick_objects` (nhờ chọn đối tượng)
- **3D:** `solid_extrude` (đưa mặt cắt lên mặt phẳng 3D theo hướng tuyến, độ dốc, cao độ, rồi đùn thành khối), `solid_boolean`, `solid_slice`, `solid_box_from_points`, `boundary_at` (tạo đường bao kín từ một điểm), `view_3d`
- **Toạ độ, layer, IFC:** `place_on_site` (đưa mô hình về toạ độ thật: 1 điểm + góc, hoặc 2 cặp điểm như ALIGN), `organize_layers` (layer tự động theo tên cống/đường kính + lý trình + bộ phận), `solid_info` (đọc thông tin phi hình học của khối), `tag_solids` (thông tin phi hình học), `export_ifc` (IFC4 hoặc IFC4X3, hình học chính xác, có Pset_SteveCAD, vật liệu, màu, khối lượng).
- **PDF:** `pdf_info`, `pdf_page_image` (xem trang hoặc một phần trang), `import_pdf` (nhập nét vẽ vector vào bản vẽ)
- **LISP, khối lượng, Excel:** `lisp_check`, `lisp_save`, `lisp_test` (chạy thử trên bản vẽ nháp), `quantities`, `audit` (soát lỗi, chỉ đọc), `export_xlsx`. Cho người dùng xem mã LISP trước khi lưu hoặc chạy.
- **Skill:** `list_skills`, `get_skill`. Ví dụ `cong-3d`: dựng cống 3D từ bản vẽ DWG/PDF. Việc nhiều bước thì đọc skill rồi làm theo.
- Chữ font TCVN3/VNI trong bản vẽ được tự giải mã sang Unicode (`text`; bản gốc ở `text_raw`).
- Lệnh không có tool riêng: `command` (ví dụ `"_.REGEN "`). Tránh lệnh mở hộp thoại, vì hộp thoại sẽ chặn ZWCAD.
- Mỗi lần gọi tool sửa bản vẽ là **một** bước UNDO.
