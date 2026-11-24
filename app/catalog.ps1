# Steve CAD MCP - danh mục tool (ZWCAD và AutoCAD dùng chung), hiển thị ở trang "Công cụ & Skill".
# Mỗi dòng: tên tool | chức năng | ví dụ câu người dùng có thể gõ.
$script:ToolCatalog = [ordered]@{
  'Đọc bản vẽ' = @(
    @('info', 'Tên bản vẽ, đơn vị, phạm vi, layer hiện hành', 'Bản vẽ này đơn vị gì?'),
    @('list_drawings', 'Các bản vẽ đang mở', 'Đang mở những bản vẽ nào?'),
    @('use_drawing', 'Ghim bản vẽ làm việc', 'Làm việc trên bản vẽ MB-01'),
    @('get_selection', 'Đọc các đối tượng đang chọn', 'Đối tượng tôi đang chọn là gì?'),
    @('list_layers', 'Danh sách layer, màu, trạng thái', 'Liệt kê các layer'),
    @('list_entities', 'Liệt kê đối tượng theo loại, layer, vùng', 'Có bao nhiêu text trên layer GHICHU?'),
    @('get_entity', 'Chi tiết một đối tượng', 'Toạ độ các đỉnh của polyline này'),
    @('list_blocks', 'Danh sách block và số lần chèn', 'Bản vẽ có những block nào?'),
    @('screenshot', 'Chụp cửa sổ CAD để AI xem kết quả', 'Chụp lại màn hình cho tôi xem')
  )
  'Tính toán' = @(
    @('measure', 'Chiều dài, diện tích, kèm tổng', 'Tổng chiều dài các đường trên layer TIM'),
    @('count_blocks', 'Đếm block theo tên', 'Đếm số block cửa đi'),
    @('find_duplicates', 'Tìm đối tượng vẽ trùng', 'Tìm các đường bị vẽ chồng'),
    @('quantities', 'Khối lượng theo layer và loại', 'Bóc khối lượng layer TUONG'),
    @('audit', 'Soát lỗi bản vẽ (chỉ đọc)', 'Kiểm tra bản vẽ này có lỗi gì'),
    @('export_xlsx', 'Xuất bảng ra Excel (có hỏi trước)', 'Xuất bảng khối lượng ra Excel')
  )
  'Vẽ' = @(
    @('line', 'Đường thẳng', 'Vẽ đoạn thẳng từ 0,0 đến 5000,0'),
    @('polyline', 'Polyline 2D (kín hoặc hở)', 'Vẽ polyline qua các điểm ...'),
    @('polyline3d', 'Polyline 3D', 'Vẽ tuyến 3D theo các cao độ ...'),
    @('rectangle', 'Hình chữ nhật', 'Vẽ hình chữ nhật 6000x4000'),
    @('circle', 'Đường tròn', 'Vẽ đường tròn R500 tâm 1000,1000'),
    @('arc', 'Cung tròn', 'Vẽ cung tròn bán kính 2000'),
    @('ellipse', 'Ellipse', 'Vẽ ellipse trục 3000 x 1500'),
    @('text', 'Chữ một dòng', 'Ghi chữ "MẶT BẰNG" cao 350'),
    @('mtext', 'Chữ nhiều dòng', 'Thêm khung ghi chú 3 dòng'),
    @('hatch', 'Tô vật liệu (hatch)', 'Hatch bê tông cho vùng này'),
    @('insert_block', 'Chèn block, điền attribute', 'Chèn block TRUC tại các giao điểm'),
    @('create_block', 'Tạo block từ đối tượng', 'Gom các đối tượng đang chọn thành block')
  )
  'Kích thước' = @(
    @('dim_linear', 'Kích thước ngang / đứng', 'Ghi kích thước chiều dài phòng'),
    @('dim_aligned', 'Kích thước song song cạnh xiên', 'Ghi kích thước cạnh xiên'),
    @('dim_radius', 'Kích thước bán kính', 'Ghi bán kính đường tròn'),
    @('auto_dim', 'Tự ghi kích thước mọi cạnh, đặt ra ngoài', 'Ghi kích thước cho hình vừa vẽ')
  )
  'Sửa' = @(
    @('move', 'Di chuyển', 'Dời các đối tượng đang chọn sang phải 500'),
    @('copy', 'Sao chép', 'Copy cột này sang các trục còn lại'),
    @('rotate', 'Xoay', 'Xoay 90 độ quanh tâm'),
    @('scale', 'Co giãn tỉ lệ', 'Phóng to gấp 2'),
    @('mirror', 'Đối xứng', 'Lấy đối xứng qua trục giữa'),
    @('offset', 'Offset', 'Offset đường bao vào trong 200'),
    @('array_rect', 'Mảng chữ nhật', 'Rải cọc 5 hàng x 8 cột, bước 3000'),
    @('array_polar', 'Mảng tròn', 'Rải 12 lỗ bu lông quanh tâm'),
    @('set_props', 'Đổi layer, màu, kiểu đường...', 'Đổi các đối tượng đang chọn sang layer KICHTHUOC'),
    @('delete', 'Xoá (có hỏi trước)', 'Xoá các đường trùng'),
    @('layer', 'Tạo / sửa layer', 'Tạo layer TUONG màu đỏ')
  )
  'Bản vẽ' = @(
    @('new_drawing', 'Tạo bản vẽ mới', 'Mở bản vẽ mới'),
    @('open_drawing', 'Mở bản vẽ (có hỏi trước)', 'Mở file D:\DuAn\MB.dwg'),
    @('save', 'Lưu (có hỏi trước)', 'Lưu bản vẽ'),
    @('undo', 'Hoàn tác', 'Hoàn tác bước vừa rồi'),
    @('redo', 'Làm lại', 'Làm lại'),
    @('zoom', 'Zoom', 'Zoom toàn bộ bản vẽ'),
    @('command', 'Gửi lệnh CAD bất kỳ', 'Chạy lệnh REGEN')
  )
  'Hỏi người dùng' = @(
    @('pick_points', 'Nhờ bạn bấm điểm trên màn hình', 'Vẽ hình tròn tại điểm tôi chọn'),
    @('pick_objects', 'Nhờ bạn chọn đối tượng', 'Đo các đường tôi sẽ chọn')
  )
  '3D' = @(
    @('solid_extrude', 'Đùn mặt cắt thành khối, theo hướng tuyến, độ dốc, cao độ', 'Đùn mặt cắt cống dài 20 m, dốc 0.5%'),
    @('solid_boolean', 'Cộng / trừ / giao khối', 'Khoét lỗ cửa trên tường'),
    @('solid_slice', 'Cắt khối bằng mặt phẳng', 'Cắt khối theo mặt phẳng đứng'),
    @('solid_box_from_points', 'Khối hộp từ các điểm', 'Tạo khối móng từ 4 góc'),
    @('boundary_at', 'Tạo đường bao kín từ một điểm', 'Lấy đường bao vùng này'),
    @('view_3d', 'Xoay góc nhìn 3D', 'Xem mô hình hướng Đông Nam')
  )
  'Toạ độ, layer, IFC' = @(
    @('place_on_site', 'Đưa mô hình về toạ độ thật', 'Đặt cống về toạ độ VN-2000 tại Km0+568'),
    @('organize_layers', 'Layer tự động theo tên, lý trình, bộ phận', 'Sắp xếp layer cho mô hình cống'),
    @('tag_solids', 'Gắn thông tin phi hình học', 'Gắn vật liệu BTCT M300 cho thân cống'),
    @('export_ifc', 'Xuất IFC4 / IFC4X3 (có hỏi trước)', 'Xuất mô hình ra IFC')
  )
  'PDF' = @(
    @('pdf_info', 'Thông tin file PDF', 'File PDF này có mấy trang?'),
    @('pdf_page_image', 'Xem một trang hoặc một vùng', 'Xem trang 3 của bản vẽ PDF'),
    @('import_pdf', 'Nhập nét vẽ vector vào bản vẽ', 'Nhập trang 2 vào bản vẽ, tỉ lệ 1:100')
  )
  'Skill' = @(
    @('list_skills', 'Danh sách skill có sẵn', 'Có những skill nào?'),
    @('get_skill', 'Đọc hướng dẫn một skill', 'Đọc skill cong-3d'),
    @('save_skill', 'Lưu skill riêng của bạn', 'Lưu quy trình vừa làm thành skill')
  )
  'AutoLISP' = @(
    @('lisp_check', 'Kiểm tra mã LISP, không chạy', 'Kiểm tra file lisp này'),
    @('lisp_save', 'Lưu file .lsp (có hỏi trước)', 'Viết lisp đánh số thứ tự cọc'),
    @('lisp_test', 'Nạp thử trên bản vẽ nháp', 'Chạy thử lisp vừa viết')
  )
}
