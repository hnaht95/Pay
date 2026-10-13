# Pay – quy định thiết kế

Mục tiêu: **iOS 18, iOS 26 và iOS 27 trông và dùng giống nhau.** Chỗ nào hệ thống vẽ khác nhau theo bản iOS (thanh tiêu đề, ô chọn, vuốt xoá, mép mờ…) thì app tự vẽ hoặc chỉnh lại cho khớp.

Mỗi lần sửa giao diện: build, cài và **kiểm tra trên cả 3 máy ảo** (iOS 18.2, iOS 26.2, iOS 27) trước khi báo xong.

---

## 1. Màu

| Tên | Sáng | Tối | Dùng cho |
|---|---|---|---|
| `Palette.bg` | `F4F5F8` | `0D0D10` | nền trang |
| `Palette.surface` | `FFFFFF` | `17171B` | nền tấm (Lịch sử, các màn sửa) |
| `Palette.card` | `EBEDF2` | `1D1D22` | thẻ, hàng khoản chi |
| `Palette.pill` | `E6E8EE` | `26262C` | viên nhỏ, vòng icon |
| `Palette.cta` | `111114` | `FFFFFF` | nút chính |
| `Palette.danger` | `D92D20` | `FF6B5E` | xoá, vượt ngân sách |
| Xanh lá của app | `61BE6E` | | icon app, điểm nhấn |
| Nút Huỷ | `C2410C` | | `BigButton.cancelTint`, chữ trắng |

- Màu danh mục là màu người dùng chọn (`Category.color`). Thanh và chấm ở Thống kê dùng **đúng màu này**, không dùng màu đậm riêng của biểu đồ.
- Thẻ "Hôm nay đã chi": nền mặc định trắng ở cả chế độ tối; đổi được màu nền và màu thanh ngân sách (nhấn giữ thẻ). Màu tối thì chữ trắng. Sắp vượt / vượt ngân sách thanh luôn cam / đỏ.

## 2. Chữ

| Chỗ | Cỡ | Độ đậm |
|---|---|---|
| Tiêu đề màn / tấm | 21 | bold |
| Tiêu đề mục (Gần đây, Danh mục…) | 21 | bold |
| Hàng khoản chi: tên, số tiền | 15 | medium |
| Hàng khoản chi: danh mục, ngày giờ | 12 | regular, màu phụ |
| Nút to (BigButton) | 21 | semibold |
| Tiêu đề mục trong Form | viết thường như iOS 26+ (iOS 18 không tự viết hoa) |

- Tiêu đề trong khung chụp, số tiêu cự: SF Mono, không nền.

## 3. Thanh tiêu đề

- Do app tự vẽ (`screenTitle`), ẩn thanh của hệ thống, để mọi bản iOS cao bằng nhau.
- Chữ 21 bold ở giữa, cách trên và dưới đều 20 pt; dưới là vạch mảnh 1 pt, lùi vào 16 pt hai bên.
- Nền thanh cùng màu nền trang.
- Trang con: nút quay lại tròn 40 pt bên trái (chevron.left trên nền `primary` 6%).
- Ô chọn kiểu trang của iOS (Picker navigationLink) không dùng; thay bằng trang chọn của app (`PickLink`).
- Lịch sử: tiêu đề và ô tìm ghim trên vùng cuộn, nền đặc, có vạch ngăn dưới ô tìm, nội dung cắt gọn ở vạch.

## 4. Mép mờ khi cuộn

- **Trang chủ, dưới đồng hồ:** iOS 27 (SDK 27) dùng mép mềm của hệ thống; bản khác app tự làm nhoè từng khối + dải màu nền nhạt.
- **Các màn có tiêu đề:** iOS 18 nhoè từng hàng dưới thanh tiêu đề (`navEdgeBlur`, `BlurForm`); iOS 26+ để hệ thống lo.
- **Không dùng lớp kính mờ của iOS đè lên nội dung**: nó luôn phủ màu sữa, nhìn đục.
- **Sau hai nút ở đáy (Nhập / Quét QR, Huỷ / Lưu):** dải màu nền nhẹ, cao ~120 pt, chỉ ló lên quá mép trên nút một chút. Không dùng dải đặc cao.
- Thẻ Nói để ghi: không phủ / nhoè nền phía sau.

## 5. Nút

- Nút to (`BigButton`): cao 64, bo tròn hai đầu. Nút chính màu `cta`; Huỷ cam đậm `C2410C`.
- Màn sửa: Huỷ / Lưu cạnh nhau ở đáy (`bottomBar`), **nằm yên khi bàn phím hiện** (bàn phím che lên, không đẩy nút lên).
- Lưu chưa bấm được: mờ 0,55.
- Nhấn: thu nhỏ 0,94 và mờ đi (`Pressable`).

## 6. Danh sách khoản chi

- Một hàng là một thẻ `Palette.card`, bo 28, cao 86 + khe 10.
- Bên trái ô 56 pt bo 13: **ảnh hoá đơn nếu có**, không thì ảnh / biểu tượng danh mục.
- Tên + (dưới) tên danh mục; bên phải số tiền + (dưới) ngày | giờ.
- **Vuốt xoá:** dùng vuốt có sẵn của iOS (mượt như hệ thống). iOS 26+ nút tròn đỏ của hệ thống; iOS 18 vẽ lại nút cho giống (tròn đỏ 50 pt). Nút cách thẻ và cách mép màn bằng nhau (~18 pt). Có rung khi lộ nút, xoá có "Đã xoá · Hoàn tác".
- Danh sách tràn ra mép trái màn để hàng vuốt đi không bị cắt.

## 7. Tấm (sheet)

- Bo góc 38 ở mọi bản iOS (`sheetCorners`; iOS cũ mặc định chỉ ~10).
- Không có nút Xong; kéo xuống để đóng.
- Chiều cao tấm vừa đủ nội dung, không để cắt mất dòng cuối.

## 8. Bảng nhấn giữ (AppMenu)

- Đầu bảng: ô 56 bo 18 (biểu tượng / màu), tên, dòng phụ.
- Icon dòng chọn: icon vòng tròn của SF Symbols (`pencil.tip.crop.circle`, `arrow.down.left.and.arrow.up.right.circle`…), cỡ 26, **màu chữ** (trắng / đen theo giao diện), không nền.
- Dòng xoá: nền đỏ nhạt, chữ đỏ.

## 9. Chọn màu, chọn ảnh

- Chọn màu (danh mục, thẻ Hôm nay): lưới chấm tròn 40 pt, 6 cột; màu đang chọn có vòng viền ngoài; dưới là "Tự chọn màu" (bảng màu của iOS).
- Chọn ảnh (danh mục, nhóm, thành viên): luôn qua bước **căn khung** (kéo, chụm); khung vuông bo góc, ảnh đại diện thành viên khung tròn.

## 10. Màn chụp ảnh

- Khung xem bo 32, lưới 3×3 bật / tắt; thanh trên: quay lại, nhiệt độ màu, độ sáng, lưới.
- Trong khung chỉ có số tiêu cự (SF Mono, không nền); vuốt ngang hiện vòng tiêu cự.
- Hàng công cụ: tỉ lệ, hẹn giờ, đèn, đổi camera. Hàng dưới: ảnh mới nhất Pay đã chụp, nút chụp, bộ lọc.
- Ảnh chụp lưu vào app Ảnh (tắt được) và một bản riêng trong Pay (danh sách "Ảnh đã chụp").

## 11. Cách kiểm tra

| Máy ảo | ID |
|---|---|
| iOS 18.2 | `66881A12-3A9B-4078-B6AB-D418A9E9A7A6` |
| iOS 26.2 | `EE5BF48D-FFFF-45F6-8943-A64EF3EFF21D` |
| iOS 27 | `A9015D34-83B0-4A72-8649-330CE9E021D2` |

Mỗi thay đổi giao diện: chụp màn hình (hoặc quay, với hiệu ứng) cùng một chỗ trên cả 3 máy, so cạnh nhau.
