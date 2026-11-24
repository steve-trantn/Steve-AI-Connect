---
name: cong-3d
title: Cống 3D
description: Dựng mô hình cống 3D (khối solid) từ bản vẽ cống DWG hoặc PDF (mặt bằng, cắt dọc, cắt ngang, chính diện), đúng hướng tuyến, góc chéo, cao độ, độ dốc; mỗi bộ phận một màu.
---

# Skill: Dựng cống 3D từ bản vẽ

Mục tiêu: từ bản vẽ thiết kế cống (cống hộp, cống tròn, cống bản), dựng các **khối solid 3D** cho từng bộ phận. Yêu cầu:

- đúng kích thước, đúng hướng tuyến và góc chéo, đúng cao độ và độ dốc;
- **mỗi bộ phận giữ màu của đối tượng gốc** (hoặc một màu riêng); để chung một layer cũng được.

Tool dùng: `info`, `list_entities` (lọc theo `window`), `get_entity`, `screenshot`, `pdf_info`, `pdf_page_image`, `import_pdf`, `boundary_at`, `solid_extrude`, `solid_boolean`, `solid_slice`, `solid_box_from_points`, `view_3d`.

## Bước 1. Nhận dạng các hình chiếu

**Nguồn DWG:**

1. Gọi `info`.
2. Gọi `list_entities(type="Text,MText")` để tìm tên các hình chiếu: MẶT BẰNG, CẮT DỌC (1/2 CẮT DỌC), MẶT CẮT NGANG, CHÍNH DIỆN (1/2 CHÍNH DIỆN), CHI TIẾT...
   - Chữ font TCVN3 hoặc VNI được server tự giải mã sang Unicode.
   - Ghi chú dạng "Kích thước mm, cao độ m" cho biết đơn vị.
3. Mỗi hình chiếu nằm quanh tên của nó. Dùng `list_entities(window=[x1,y1,x2,y2])` để đọc riêng từng hình chiếu: đường bao, kích thước (Dimension có `measurement`), cao độ (text dạng `3.31`, `+4.71`).
4. Muốn nhìn tận mắt: `zoom` vào cửa sổ đó rồi gọi `screenshot`.

**Nguồn PDF:**

1. Gọi `pdf_info(path)`.
2. Nếu PDF có nét vector: `import_pdf(path, page, insert_point, scale, crop)`.
   - `scale` là mẫu số tỉ lệ bản vẽ, ví dụ 1:50 → `scale=50`, để ra đúng mm thật.
   - Dùng `crop` để chỉ nhập hình chiếu cần dùng.
   - Sau khi nhập thì xử lý như DWG.
3. Nếu PDF là bản scan (không có vector): dùng `pdf_page_image(path, page, crop)` để đọc số liệu bằng mắt, rồi dựng bằng `loops` (toạ độ tự tính từ kích thước).

### Lập danh mục bộ phận: phải đủ, không chỉ thân cống

Đọc **hết** ghi chú, thuyết minh và chú thích vật liệu (Text/MText, đã giải mã) rồi liệt kê mọi bộ phận. Bộ hồ sơ cống thường có:

- **Đốt cống:** đúc sẵn hay đổ tại chỗ; chiều dài một đốt, ví dụ "L=1M" trong bảng thép; đốt hợp long; đoạn nối sát hố ga hoặc tường đầu.
- **Mối nối:** vữa xi măng, nút cao su, bao tải nhựa đường... Có chi tiết "MỐI NỐI" thì lấy kích thước vành vữa.
- **Móng và lót:** móng BTXM, bê tông lót, cấp phối đá dăm đệm, cát đệm (dày, rộng). **Gia cố nền** như cọc tre hoặc cừ thì hỏi người dùng có cần dựng không.
- **Hai đầu cống:** hố ga, giếng thu, tường đầu, tường cánh, sân cống, chân khay, gia cố mái, tấm đan hoặc nắp hố ga.
- **Ngoài phạm vi cống:** kết cấu áo đường, đất đắp, mương dẫn. Hỏi người dùng có cần dựng không.

**Bảng thống kê dạng OLE (bảng Excel nhúng)** không đọc được bằng `list_entities`: `zoom` vào bảng rồi `screenshot` để đọc. Bảng này dùng để so thể tích ở bước 6.

### Đọc bố trí đốt cống trên mặt cắt dọc

- `list_entities(window=<cắt dọc>, type="Line,Polyline")`: các vạch đứng có chiều cao bằng chiều cao ngoài của cống chính là ranh giới đốt. Từng cặp vạch sát nhau (cách 10–30 mm) là **khe mối nối**.
- Từ toạ độ x của các vạch, tính danh sách đoạn `[từ, đến]` dọc trục với s = 0 tại mặt ngoài hố ga (hoặc tường đầu) phía thượng lưu. Kiểm tra lại tổng chiều dài bằng Dimension tổng trên bản vẽ.
- Hố ga hoặc tường đầu: đọc kích thước lòng, chiều dày thành, cao độ đỉnh và đáy. Đáy hố ga thường thấp hơn đáy cống, ví dụ 300 mm để lắng.

### Bản vẽ cống ngang đường: những điểm hay gặp

- **Một tệp chứa nhiều cống:** mỗi cống một tờ, có tiêu đề kiểu "CẮT DỌC TIM CỐNG TẠI: KM...". Tìm theo tiêu đề rồi hỏi người dùng muốn dựng cống nào (lý trình, khẩu độ BxH, L).
- **Đốt cống vẽ bằng block:** trên cắt dọc, mỗi đốt thường là một block chèn nhiều lần (ví dụ `2X2XXX`, mỗi đốt 2 m).
  - Đếm số block, xem `GetBoundingBox` để biết vị trí và độ dốc.
  - Mở block định nghĩa ra đọc **ngàm** (âm dương, ví dụ 100–125 mm).
- **Đối chiếu ghi chú với hình vẽ:** có khi ghi chú (ví dụ "L=16m, 8x200") lệch với hình học (10 block = 20 m). Báo người dùng và dựng theo hình học, trừ khi người dùng bảo khác.
- **Giếng thu, hố thu hai đầu:** khoang dưới bọc chỗ giao với cống dọc, cổ giếng lên mặt vỉa hè, nắp lưới thu. Đọc kích thước từ Dimension; nhiều Dimension đo theo cm (DIMLFAC) trong khi hình học vẽ bằng mm.
- **Cao độ:** tờ cống thường không ghi cao độ tuyệt đối. Khi đó dựng theo **cao độ tương đối** (lấy y trên cắt dọc 1:1 làm z, mốc ±0.00 tại đáy cống), và báo người dùng lấy cao độ thiết kế từ trắc dọc để dịch mô hình.
- **Ngàm đốt cống:** mỗi đốt = vành ngàm âm (vòng đai ngoài) + thân + ngàm dương (tiết diện thu nhỏ), dựng bằng 3 lần `solid_extrude` rồi `solid_boolean(union)`. Đốt đầu và đốt cuối không có ngàm ở mặt tiếp giáp giếng.
- **Lỗ thông:** cổ giếng xuống khoang và cống ngang vào giếng đều phải khoét bằng `solid_boolean(subtract, keep_others=true)` khi dùng một dao cắt cho nhiều khối.

### Cống có tường đầu, tường cánh (không đổ vào ga)

- **Đọc theo hai hình chiếu:**
  - **cắt dọc** cho chiều dọc trục và cao độ: tường đầu hình thang, đỉnh tường cánh dốc, sân, chân khay, đá hộc;
  - **mặt bằng** (thường là block, ví dụ `CUAXA`) cho chiều ngang: bề rộng tường đầu, độ xòe và chiều dày tường cánh, bề rộng sân.
- **Mặt bằng và cắt dọc có thể khác tỉ lệ** (ví dụ 1:150 và 1:120): không lấy chiều dọc từ mặt bằng.
- **Tường cánh xòe có đỉnh dốc** = `intersect` của khối từ mặt bằng (dải xòe, đùn đứng) với khối từ cắt dọc (đỉnh dốc, đùn ngang).
- **Tường đầu:** đùn mặt cắt dọc qua hết bề rộng, rồi trừ khối bao ngoài cống để tạo lỗ.
- **Hai đầu đối xứng:** đổi `s` thành `L - s` cho cắt dọc và mặt bằng.
- **Cao độ:** block `COTE` (thuộc tính COTE) thường ghi cao độ đáy cống và mặt đường. Đọc bằng `list_entities(type="BlockReference")` hoặc `get_entity`.
- **Bản vẽ mở ra ở tab Layout:** các tool zoom, góc nhìn và chọn theo vùng tự chuyển về Model.

## Bước 2. Tỉ lệ và đơn vị

- **Kiểm tra tỉ lệ hình chiếu:** so `measurement` của một Dimension với khoảng cách hình học giữa hai điểm đo của nó. Nếu khác nhau thì hình chiếu vẽ theo tỉ lệ riêng: hệ số = measurement / khoảng cách vẽ.
- **Đơn vị mô hình:** nên dựng theo **mét** khi cao độ ghi bằng m. Khi đó `scale = 0.001` cho mặt cắt vẽ bằng mm (nhân thêm hệ số tỉ lệ của hình chiếu nếu có).
- **Đặt mô hình ở toạ độ thật** nếu biết toạ độ tim cống. Nếu không biết, đặt ở vùng trống, không đè lên khung tên hay hình chiếu.

## Bước 3. Lập bảng thông số, hỏi người dùng xác nhận

Trước khi dựng, trình bày một bảng ngắn:

- **Loại cống:** hộp, tròn hoặc bản; số khoang.
- **Kích thước:** khẩu độ B×H hoặc đường kính D; chiều dày nắp, thành, đáy; vát góc.
- **Chiều dài:** L thân cống.
- **Hướng và góc:** hướng tuyến cống `azimuth_deg`; góc chéo so với tim đường.
- **Cao độ:** đáy trong đầu vào và đầu ra. Từ đó suy ra `slope_pct = (z_ra - z_vào) / L × 100`.
- **Danh sách bộ phận và màu:** thân cống, tường đầu, tường cánh, sân cống, chân khay, móng hoặc đệm, gia cố.

Thiếu số liệu nào thì **hỏi**, không tự bịa. Số nào lấy từ giá trị điển hình thì ghi rõ "giả định".

## Bước 4. Lấy mặt cắt (profile)

- **Ưu tiên polyline kín có sẵn trong bản vẽ.** Tìm bằng `list_entities(window=..., type="Polyline,Circle")`, xem `closed` và `area`.
  - Bao ngoài và lòng cống truyền chung trong `profile_handles`. Vòng nằm trong vòng khác sẽ tự thành lỗ rỗng.
- **Mặt cắt vẽ bằng line rời:** gọi `boundary_at(point, only_layers=[layer nét bao bê tông])` với một điểm nằm trong phần bê tông, ví dụ giữa thành cống. Lệnh này tạo polyline kín, có cả lỗ.
  - `only_layers` tạm ẩn cốt thép, hatch và chữ, để các nét đó không chia nhỏ vùng.
  - Xem layer của nét bao bằng `list_entities(window=...)`.
- **PDF scan hoặc mặt cắt quá rối:** dùng `loops` theo toạ độ tính từ kích thước, với gốc toạ độ đặt tại tim đáy trong. Ví dụ cống hộp B×H, thành t, nắp tn, đáy td, vát c:
  - `{"points": [[-B/2-t, -td], [B/2+t, -td], [B/2+t, H+tn], [-B/2-t, H+tn]]}` (bao ngoài);
  - `{"points": [[-B/2, 0], [B/2, 0], [B/2, H-c], [B/2-c, H], [-B/2+c, H], [-B/2, H-c]]}` (lòng cống);
  - cống tròn: `{"circle": [0, R, R_ngoài]}` và `{"circle": [0, R, R_trong]}`.

## Bước 5. Dựng từng bộ phận bằng `solid_extrude`

Dùng chung một hệ trục cho cả cống:

- `origin`: tim đáy trong tại đầu vào, có cao độ z thật;
- `azimuth_deg`: hướng trục cống trong mặt bằng, đo ngược chiều kim đồng hồ từ trục +X;
- `slope_pct`: độ dốc thân cống. Các bộ phận đứng thẳng (tường đầu, tường cánh) dùng `slope_pct=0`.

| Bộ phận | view | Mặt cắt lấy từ | Khoảng đùn |
|---|---|---|---|
| Thân cống, chia đốt | `section` | mặt cắt ngang | `pieces=[[s1,s2],...]` đúng bố trí đốt; hoặc `segment_length` + `joint_gap` |
| Vành vữa mối nối | `section` | chi tiết mối nối (vành chữ U bọc nắp và thành) | `pieces` ngắn, tâm tại từng mối nối |
| Hố ga: thành, gờ, đáy, đệm, tấm đan | `plan` | mặt bằng, cắt 1-1 | z đáy → z đỉnh (cao độ tuyệt đối) |
| Lỗ cửa cống xuyên thành hố ga | `section` | lòng cống | đùn xuyên chiều dày thành, rồi `solid_boolean(subtract)` |
| Móng, đệm dưới thân | `section` | mặt cắt ngang | `-a` → `L+a` |
| Tường đầu | `section` | chính diện (bao ngoài + lỗ cửa cống) | `-t` → `0` ở đầu vào; `L` → `L+t` ở đầu ra |
| Tường cánh | `plan` và `elevation`, rồi `solid_boolean(intersect)` | mặt bằng (hình dạng, chiều dày) và mặt đứng (đỉnh dốc) | plan: z đáy → z đỉnh; elevation: hết bề ngang |
| Sân cống, chân khay | `elevation` | cắt dọc | ngang theo bề rộng sân: `-B_sân/2` → `B_sân/2` |
| Gia cố, tấm lát | `plan` | mặt bằng | chiều dày lớp |

Lưu ý khi dựng:

- **`base_point`:** điểm trên mặt cắt (toạ độ trong bản vẽ) tương ứng với `origin`. Thường là tim đáy trong của cống.
- **`mirror_x=true`:** dùng khi hình chiếu vẽ nhìn từ phía ngược lại.
- **Nửa hình chiếu (1/2 chính diện, 1/2 cắt dọc):** dựng nửa có trong bản vẽ, rồi dựng nửa còn lại với `mirror_x=true`, cuối cùng `solid_boolean(union)`.
- **Cống chéo:** dựng thân dài dư ở hai đầu, rồi `solid_slice` bằng mặt phẳng đứng song song tim đường. Pháp tuyến mặt cắt là vector nằm ngang, vuông góc với tim đường. Giữ phần phía trong.
- **Tách màu:** mặc định mỗi solid lấy màu hiển thị của đối tượng mặt cắt gốc. Có thể truyền `color` riêng cho từng bộ phận để dễ phân biệt. `layer` có thể chung, ví dụ `3D-CONG`.
- **Một lần gọi tool = một bước UNDO.** Dựng sai thì gọi `undo`.

## Bước 6. Kiểm tra và báo cáo

1. `list_entities(type="3dSolid")` để lấy thể tích từng khối. `solid_extrude` trả `count` và `total_volume` cho mỗi nhóm.
   - Thể tích **một đốt** đem so với bảng thống kê vật tư của đốt cống, ví dụ "thể tích bê tông 0.58 m³".
   - Chênh dưới 5% thì chấp nhận được. Ghi rõ nguyên nhân, ví dụ ngàm mối nối hay móc cẩu chưa dựng. Nếu bản vẽ có bảng **thống kê vật tư hoặc khối lượng bê tông**, so sánh và báo chênh lệch (%).
2. `view_3d(direction="SE", style="conceptual", zoom_to=[các handle solid])`, rồi `screenshot` để tự kiểm tra hình dạng: lỗ cống, vát góc, góc chéo, cao độ.
3. **Hoàn thiện:**
   - Truyền `name` (bộ phận, kèm vật liệu) và `props` (`structure`, `station`, `type`) cho mọi lần `solid_extrude`.
   - Xong thì gọi `organize_layers(structure, station)` để có layer kiểu `CONG-HOP-4X4_KM8+423.31_TUONG-DAU-HA-LUU`.
   - Có toạ độ thật thì gọi `place_on_site` (1 điểm + góc phương vị, hoặc 2 cặp điểm).
   - Người dùng cần BIM thì gọi `export_ifc(path, schema="IFC4" hoặc "IFC4X3")`.
4. Báo người dùng một bảng gồm bộ phận, số lượng, màu, thể tích (m³) và giả định đã dùng. Liệt kê rõ **những gì chưa dựng và lý do** (thiếu số liệu, ngoài phạm vi, chờ người dùng xác nhận). Nhắc người dùng có thể `UNDO` hoặc lưu bản vẽ.
