# Quy ước mô hình cống và xuất IFC (từ v1.8.7)

Phần 2 là hành vi cũ của v1.8.6, giữ lại để biết vì sao có quy ước.

## 1. Quy ước khi dựng mô hình

### Bắt buộc

1. **Khối solid 3D**, không nằm trong block. Mỗi bộ phận một khối, **mỗi đốt một khối**, không gộp cả thân cống.
2. **Vẽ theo mét**, đặt `INSUNITS = 6` (Meters). Z là cao độ thật; toạ độ thật nếu có (`place_on_site`).
3. **Mỗi khối mang đủ 3 thông tin nhận dạng:**

   | Trường | Ghi là | Ví dụ |
   |---|---|---|
   | Công trình (`structure`) | Mã cống, **không trùng nhau** trong file | `C01`, `CH4X4-01` |
   | Lý trình (`station`) | `Km<số>+<3 chữ số mét>[.<lẻ>]`, dấu chấm thập phân | `Km8+423.31` |
   | Loại (`type`) | Loại + khẩu độ | `Cống hộp 4x4`, `Cống tròn D1000` |

4. **Tên bộ phận (`part`)** bắt đầu bằng từ khoá, có đầu cống nếu thuộc cửa:

   | Nhóm | Từ khoá đầu tên | Ví dụ |
   |---|---|---|
   | Thân cống | `Đốt cống <số>` | `Đốt cống 07 BTCT M300 L=2,0 m` |
   | Móng thân cống | `Móng cống`, `Lót móng cống`, `Đệm`, `Gối cống` | `Móng cống BT M200 dày 40 cm` |
   | Cửa thượng lưu / hạ lưu | tên bộ phận + `thượng lưu` / `hạ lưu` | `Tường đầu thượng lưu BT M250`, `Tường cánh hạ lưu (trái) BT M250` |

   Cửa cống luôn phải ghi **thượng lưu** hay **hạ lưu**. Vật liệu viết trong tên hoặc ở trường Vật liệu.

### Để tính đúng cao độ, độ dốc, góc chéo

5. **Đốt cống dựng bằng `solid_extrude` mặt cắt ngang** (bao ngoài + lòng cống) theo trục cống, dùng chung `origin`, `azimuth_deg`, `slope_pct` cho cả thân. `origin` đặt tại **tim đáy trong ở cửa thượng lưu**.
6. Đốt đánh số từ **thượng lưu về hạ lưu**. Đốt cùng chiều dài thì cùng bố trí mối nối.
7. Chỉ di chuyển, xoay, sao chép, cộng, trừ, cắt khối bằng **tool của Steve AI**. Sửa tay (grip, SLICE, UNION...) làm mất công thức dựng: khối xuất dạng hộp bao và không tính được số liệu.
8. **Góc chéo** là góc nhọn (0-90°) giữa trục cống và **tim đường**; 90° là cống vuông góc. Cần một trong hai: thông tin `road_azimuth` (phương vị tim đường tại cống), hoặc tường đầu dựng **song song tim đường** để công cụ suy ra. Hai nguồn lệch nhau thì báo, không tự chọn.

### Nhiều cống trong một file

9. Mỗi cống một **mã công trình riêng**, kể cả hai cống cùng khẩu độ hoặc cùng lý trình (trái/phải tuyến: `C05-T`, `C05-P`).
10. Sao chép cống sang vị trí khác thì **đổi ngay** Công trình và Lý trình cho cả bộ.
11. Layer (không bắt buộc, để dễ chọn): `<CÔNG TRÌNH>_<LÝ TRÌNH>_<BỘ PHẬN>`, tạo bằng `organize_layers`.

## 2. Trước đây (v1.8.6)

| Trường hợp | Kết quả |
|---|---|
| Hai cống, lý trình khác nhau | Tách đúng thành hai cống trong một file |
| Cùng cống, viết `Km8+423.31` và `KM8+423,31` | **Sai:** thành hai cống |
| Khối thiếu Công trình/Lý trình | Gom vào một cụm chung "Công trình" |
| Hai cống cùng tên, quên lý trình | **Sai:** nhập thành một cống, số đốt và chiều dài cộng dồn |
| Thứ tự trong file | Theo thứ tự khối, không theo lý trình |

## 3. Cách làm từ v1.8.7

### 3.1 Số liệu tính từ khối, ghi ở cấp cống

| Số liệu | Cách tính |
|---|---|
| Cao độ đáy trong thượng lưu / hạ lưu | Điểm thấp nhất của lòng cống (vòng trong của mặt cắt) tại hai mặt ngoài cùng của thân |
| Đầu nào là thượng lưu | Đầu gần trọng tâm nhóm Cửa thượng lưu; không có cửa thì lấy đầu cao hơn và ghi "suy đoán" |
| Độ dốc (%) | (đáy TL - đáy HL) / chiều dài thân trên mặt bằng x 100. Âm thì cảnh báo |
| Phương vị trục cống | Hướng đùn của thân, trên mặt bằng, từ thượng lưu về hạ lưu |
| Góc chéo (độ) | Góc nhọn giữa trục cống và `road_azimuth`, hoặc phương dài của tường đầu |
| Chiều dài thân thật / danh nghĩa | Từ mặt đầu tới mặt cuối / số đốt x chiều dài đốt; ghi cả hai |

Không đủ dữ liệu (khối sửa tay, thân gấp khúc, các đốt không cùng trục) thì **để trống và nêu lý do**, không ước lượng.

### 3.2 Nhận cống

1. Chuẩn hoá lý trình trước khi gom (`KM8+423,31` = `Km8+423.31`), giữ nguyên cách viết gốc khi hiển thị.
2. Khối thiếu thông tin: **đề xuất** cống theo layer đúng mẫu, rồi theo khoảng cách tới thân cống gần nhất. Người dùng bấm nhận mới ghi.
3. Cùng mã nhưng có từ hai thân cống tách rời (khác trục, hoặc cách nhau quá 5 m): cảnh báo "có thể là hai cống", không gộp số liệu.

### 3.3 Xuất hàng loạt

- Bảng danh sách cống: ô chọn, mã, lý trình, loại, số đốt, L, i%, góc chéo, đáy TL/HL, khối lượng, **lỗi**. Sắp theo lý trình bằng số (Km9 trước Km10).
- Xuất **một file chung** (mặc định) hoặc **mỗi cống một file** vào thư mục đã chọn, tên `<mã>_<lý trình>.ifc`, không ghi đè khi chưa hỏi.
- Cống có lỗi nặng (trùng mã, thiếu nhận dạng) mặc định không được chọn.
- Cây IFC: Dự án > Công trường > (Tuyến, IFC4X3) > **Cống theo lý trình** > nhóm > bộ phận.
- Bảng tổng hợp Excel kèm theo: mỗi cống một dòng, thêm sheet khối lượng theo vật liệu.

### 3.4 Kiểm tra trước khi xuất

Thiếu Công trình/Lý trình/Tên bộ phận; mã trùng; lý trình sai mẫu; tên bộ phận không nhận ra nhóm; cửa cống không ghi đầu; số đốt đánh trùng hoặc nhảy số; khối hộp bao; đơn vị nghi sai; độ dốc âm; hai khối trùng nhau.

### 3.5 Bài thử phải có

Cống dốc và cống chéo với số liệu biết trước; hai cống cùng khẩu độ; lý trình viết khác kiểu; copy cống quên đổi mã; thiếu cửa thượng lưu; thân gấp khúc; khối sửa tay; 100 cống; IFC4 và IFC4X3 đều 0 lỗi ifcopenshell.

## 4. Đã chốt

1. Cống nhiều khoang: một cống, số khoang là thuộc tính. Nhiều hàng ống song song: một cống, có số hàng ống.
2. Cống dọc và hố ga: bảng riêng, làm sau.
3. Mặc định xuất một file chung.
