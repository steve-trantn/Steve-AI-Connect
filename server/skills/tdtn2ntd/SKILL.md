---
name: tdtn2ntd
title: TDT sang NTD
group: Chuyển đổi
description: Chuyển số liệu trắc ngang TDT (vnroad, file .tdtn) sang file NTD để nạp vào ADSCivil, giữ tên cọc, lý trình, cao độ, góc và mã địa vật từng điểm; một file hoặc cả thư mục.
---

# Skill: TDT (.tdtn) sang NTD cho ADSCivil

Bộ chuyển đi kèm Steve AI Connect, chạy bằng Python của chương trình (không cần cài thêm gì):

```
"%LOCALAPPDATA%\SteveCADConnect\venv\Scripts\python.exe" -I -X utf8 "%LOCALAPPDATA%\SteveCADConnect\tool\server\skills\tdtn2ntd\scripts\tdtn2ntd.py" <file.tdtn | thư mục> [-o THƯ_MỤC_RA] [--re-trai D2,D5] [--dao-ben] [--xem]
```

- Mỗi file ra `<tên>.ntd` và `<tên>_ma.csv`, mặc định trong thư mục `<tên>_NTD` cạnh file gốc. CSV giữ mã TDT gốc của từng điểm, nên mã không mất kể cả khi chưa có mã ADSCivil tương ứng.
- `--xem` chỉ in nội dung ra màn hình, không ghi gì.
- Bảng đổi mã: chương trình tự dùng `%USERPROFILE%\Steve-CAD-AI\ma_TDT_sang_ADS.json` nếu có, không thì bảng đi kèm. Người dùng muốn sửa bảng mã: chép bảng đi kèm (`...\skills\tdtn2ntd\ma_TDT_sang_ADS.json`) sang `Steve-CAD-AI` rồi sửa bản đó, vì bản cập nhật chương trình ghi đè thư mục cài đặt.
- Không gõ được biến `%...%` trong shell đang dùng thì đổi sang đường dẫn đầy đủ (`$env:LOCALAPPDATA` trong PowerShell).

## Quy trình

1. Hỏi đường dẫn file `.tdtn` (hoặc thư mục). Chạy `--xem` trước để thấy cọc, góc, mã. Báo `cau truc khong khop` nghĩa là file của phiên bản TDT khác: dừng lại, báo người dùng, không đoán.
2. Ghi file ra đĩa: nói trước sẽ ghi vào đâu và chờ người dùng đồng ý (UNDO không hoàn tác được việc ghi file).
3. Chuyển **một file** trước. Báo đường dẫn ra, số cọc và số điểm, mã đã đổi, mã chưa đổi được, các cọc có góc khác đi thẳng.
4. Người dùng nạp `.ntd` vào ADSCivil. Nếu có tool CAD, kiểm bình đồ (`zoom_to` tim tuyến, `screenshot`): tuyến không được gập ngược ở cọc đỉnh, chữ cọc không lộn ngược.
5. Đỉnh rẽ sai hướng: chạy lại với `--re-trai <tên cọc>`. Trắc ngang ngược trái/phải: `--dao-ben`.
6. Người dùng duyệt mẫu xong mới chạy cả thư mục.

## Cấu trúc .tdtn (little-endian)

- `int32` số cọc, rồi từng cọc:
  - `int32 len + tên`, `int32` (luôn 0)
  - `double` lý trình (cộng dồn), `double` cao độ tim
  - `int32 len + chuỗi góc` (`180` hoặc `D.MM.SSs`, ví dụ `9.27.137` = 9°27'13.7")
  - 48 byte 0
  - bên trái: `int32 n`, n × (`double` khoảng cách, `double` cao độ), n × `int32` mã; bên phải cùng cấu trúc
- Mã: 0 là không mã, số dương là mã địa vật, mã âm (`-1`, `-2`) là mã đặc biệt của TDT, chưa rõ nghĩa.

## Quy ước NTD

- `POLE tên lý_trình cao_độ 0.00000 0.000000 góc_rad`, π = đi thẳng.
- Góc TDT khác `180` là góc chuyển hướng: NTD = π − góc (rẽ phải, mặc định) hoặc π + góc (`--re-trai`). `359.59.600` coi như 0°, đi thẳng. Đổi thẳng độ sang radian sẽ làm tuyến gập ngược.
- `TARGETL` ghi khoảng cách âm, `TARGETR` dương. Cột thứ 3 là `<mã>*0*`, điểm không mã ghi `NOBLOCK*0*`.
- Mã Fcode ADSCivil là `1`…`130` (file `ADS Code for Cross Section.fcode` trong thư mục `Template\Fcode` của ADSCivil). Mã ngoài khoảng này hoặc không có trong bảng ghi `NOBLOCK`.

## Chưa chốt (nói rõ với người dùng)

- Chưa có bảng mã TDT (số → tên): đang giữ nguyên số (2→2, 3→3, 4→4, 12→12).
- Trên ADSCivil, mã có thể hiện thành **chữ** `12*0*` thay vì block. Nếu gặp: so với một file NTD có mã do ADSCivil tự xuất để tìm đúng cú pháp.
- Hướng rẽ ở cọc đỉnh là giả định (mặc định rẽ phải); luôn kiểm trên bình đồ.
