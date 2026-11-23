# Steve CAD MCP

MCP server cho phép trợ lý AI (Claude, ChatGPT/Codex, Gemini...) điều khiển **ZWCAD** hoặc **AutoCAD đang mở** qua COM. Viết bằng Python, giao tiếp qua stdio.

```bat
python run.py --cad zwcad   [--progid ZWCAD.Application.2026] [--allow-script]
python run.py --cad autocad [--allow-script]
```

Thư viện cần: `requirements.txt` (mcp, pywin32, pillow, pdfminer.six, pypdfium2). Steve AI Connect tự cài và đăng ký server cho các trợ lý AI.

## Thiết kế

- **Một luồng COM riêng (STA):** mọi lệnh gọi CAD chạy trên một luồng. Nhờ vậy server không chặn kết nối MCP và không lẫn apartment.
- **CAD bận thì tự thử lại:** lệnh gọi COM bị CAD từ chối vì đang bận sẽ được thử lại trong 10 giây. Lệnh bị từ chối là lệnh chưa chạy, nên thử lại an toàn.
- **Phát hiện hộp thoại chặn:** nếu cửa sổ CAD đang bị một hộp thoại khóa, tool báo ngay tên hộp thoại thay vì treo.
- **Luôn gọi động (late binding):** không dùng bộ đệm makepy (gen_py). Phần mềm khác trên máy có tạo bộ đệm đó thì server vẫn chạy đúng.
- **Không bao giờ tự mở CAD ẩn:** chỉ nối vào CAD đang chạy.
- **Bản vẽ làm việc:** mặc định là tab đang mở. `use_drawing` ghim một bản vẽ, nên người dùng đổi tab giữa chừng cũng không làm AI vẽ nhầm. Bản vẽ đang ghim bị đóng thì tool dừng lại, không chuyển sang bản khác.
- **Một tool sửa bản vẽ = một bước UNDO.** Không gom khi người dùng đang dở lệnh hoặc UNDO đang tắt.
- **Lọc trong CAD:** lọc theo loại hoặc layer dùng selection set có bộ lọc DXF, nên CAD tự lọc và chỉ đối tượng khớp mới qua COM. Gọi COM sang ZWCAD tốn khoảng 4 ms mỗi lần, nên cách này nhanh hơn hàng chục lần so với duyệt từng đối tượng.
- **Gắn nhãn tool:** chỉ đọc (`readOnlyHint`) hoặc phá huỷ (`destructiveHint`), để trợ lý AI tự hỏi người dùng trước khi xoá hoặc lưu.
- **`run_script` mặc định tắt:** chỉ bật bằng `--allow-script` hoặc ô tích trong Steve AI Connect.
- Thông báo lỗi bằng tiếng Việt.
- **Chữ TCVN3/VNI:** chữ trong bản vẽ dùng font cũ (.VnTime, VNI-Times) được giải mã sang Unicode, để AI đọc được.
- **Ảnh chụp đúng kích thước** trên màn hình đặt tỉ lệ 125% hay 150% (server khai báo DPI-aware).

## Dựng 3D (`solid_extrude`)

Mặt cắt 2D có thể là polyline kín trong bản vẽ (vòng trong tự thành lỗ) hoặc toạ độ nhập tay. Mặt cắt được đặt vào hệ trục của công trình tuyến:

- **Hệ trục:** gốc `origin` (có cao độ thật), hướng `azimuth_deg`, độ dốc `slope_pct`.
- **Ba kiểu hình chiếu** (`view`):
  - `section` (mặt cắt ngang): đùn dọc trục;
  - `elevation` (mặt cắt dọc hoặc mặt đứng): đùn ngang;
  - `plan` (mặt bằng): đùn đứng.
- **Màu:** mặc định giữ màu hiển thị của đối tượng gốc, nên các bộ phận tự tách màu.
- **Hình phức tạp** như tường cánh có đỉnh dốc: giao (`intersect`) khối từ mặt bằng với khối từ mặt đứng.

## Thông tin phi hình học và IFC

Mỗi khối do tool dựng mang **XData `STEVECAD`** gồm:

- tên bộ phận, vật liệu và các thuộc tính thêm (công trình, lý trình, loại...);
- **công thức dựng**: đùn mặt cắt, cộng/trừ/giao, cắt chéo, ở toạ độ thế giới.

Các tool `move`, `rotate`, `mirror`, `scale`, `copy`, `place_on_site` cập nhật công thức theo. Khối có kiểm tra thể tích và trọng tâm, nên nếu bị sửa bằng lệnh khác thì nhận ra được.

`export_ifc` dịch công thức sang hình học tham số của IFC, kích thước chính xác:

- khối đùn → `IfcExtrudedAreaSolid`;
- cộng/trừ/giao → `IfcBooleanResult`;
- cắt chéo → `IfcBooleanClippingResult` + `IfcHalfSpaceSolid`.

Khối không còn đúng công thức được xuất dạng hộp bao (`BoundingBox`) và liệt kê trong kết quả.

**Cấu trúc tệp IFC:**

- **Không gian:** Project → Site (IFC4.3 có thêm IfcRoad).
- **Theo công trình:** mỗi công trình (công trình + lý trình) là một `IfcElementAssembly`.
- **Theo khối:** mỗi khối là một `IfcBuildingElementProxy`, kèm theo:
  - `Pset_SteveCAD`: Công trình, Lý trình, Loại, Bộ phận, Vật liệu, Layer, Handle CAD, Màu ACI, Thể tích;
  - `Qto_SteveCAD` (NetVolume);
  - `IfcMaterial`;
  - màu bề mặt.

Đã kiểm tra bằng ifcopenshell: 0 lỗi schema, hình học dựng lại được và thể tích khớp.

## Skill

Mỗi skill là một tệp `skills/<tên>/SKILL.md`, viết quy trình nhiều bước cho AI. Server đưa skill ra dưới dạng MCP prompt và qua tool `get_skill`. Steve AI Connect còn chép skill vào `Steve-CAD-AI\.claude\skills` để Claude Code dùng như skill gốc. Thêm skill mới chỉ cần thêm một thư mục.

## Tool

| Nhóm | Tool |
|---|---|
| Bản vẽ | `info`, `list_drawings`, `use_drawing`, `new_drawing`, `open_drawing`, `save`, `undo`, `redo`, `zoom`, `command` |
| Đọc | `list_layers`, `list_entities`, `get_entity`, `get_selection`, `list_blocks`, `screenshot` |
| Tính toán | `measure`, `count_blocks`, `find_duplicates` |
| Vẽ | `line`, `polyline`, `polyline3d`, `rectangle`, `circle`, `arc`, `ellipse`, `text`, `mtext`, `hatch`, `insert_block`, `create_block` |
| Kích thước | `dim_linear`, `dim_aligned`, `dim_radius`, `auto_dim` |
| Sửa | `move`, `copy`, `rotate`, `scale`, `mirror`, `offset`, `array_rect`, `array_polar`, `set_props`, `delete`, `layer` |
| Tương tác | `pick_points`, `pick_objects` (nhờ người dùng bấm hoặc chọn trên màn hình) |
| 3D | `solid_extrude`, `solid_boolean`, `solid_slice`, `solid_box_from_points`, `boundary_at`, `view_3d` |
| PDF | `pdf_info`, `pdf_page_image`, `import_pdf` |
| Toạ độ, layer, IFC | `place_on_site`, `organize_layers`, `tag_solids`, `export_ifc` |
| Skill | `list_skills`, `get_skill` (đồng thời là MCP prompt, ví dụ `/cong_3d`) |
| Nâng cao | `run_script` (Python, chỉ khi được bật) |

Biến môi trường `STEVECAD_PIN_FILE`: đường dẫn tệp chứa tên bản vẽ làm việc, dành cho khung chat trong CAD (giai đoạn sau).

© Steve Tran · 0987 779 228
