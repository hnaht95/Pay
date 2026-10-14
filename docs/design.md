# Pay – quy chuẩn thiết kế

Mục tiêu: **iOS 18, iOS 26 và iOS 27 trông và dùng giống nhau.** Chỗ nào hệ thống vẽ khác nhau theo bản iOS (thanh tiêu đề, mép mờ khi cuộn, ô Form, vuốt xoá…) thì app tự vẽ.

- Mọi phần khung giao diện dùng chung nằm trong `ios/Pay/Chrome.swift`. Nhánh `#available` cho giao diện chỉ được đặt ở đó (và vài chỗ ghi rõ ở mục 11), không rải trong từng màn.
- Bản phát hành dựng bằng **Xcode 27** ở cả hai máy (SDK khác nhau thì iOS 27 vẽ khác).
- Sửa giao diện xong: chạy `ios/scripts/shots.sh` (mục 12), xem ảnh so sánh 3 bản iOS, sáng và tối, rồi mới báo xong.

---

## 1. Màu (`Palette`, `Category.swift`)

| Tên | Sáng | Tối | Dùng cho |
|---|---|---|---|
| `Palette.bg` | `F4F5F8` | `0D0D10` | nền trang chủ, nền trang |
| `Palette.surface` | `FFFFFF` | `17171B` | nền tấm (Lịch sử, màn sửa) |
| `Palette.card` | `EBEDF2` | `1D1D22` | thẻ, hàng khoản chi |
| `Palette.pill` | `E6E8EE` | `26262C` | viên nhỏ ("Xem tất cả", "Tháng 10") |
| `Palette.cta` / `ctaInk` | `111114` / `FFFFFF` | `FFFFFF` / `111114` | nút chính và chữ trên nó |
| `Palette.danger` | `D92D20` | `FF6B5E` | số tiền chi, xoá, vượt ngân sách |
| `Palette.goodInk` | `2F7A43` | `8FDCA3` | số tiền thu |
| Xanh lá của app | `61BE6E` | | sóng âm, chấm "có ảnh hoá đơn" |
| Nút Huỷ | `C2410C` | | `BigButton.cancelTint`, chữ trắng |

- Màu danh mục là `Category.color` (người dùng chọn được). Biểu đồ, thanh, ô lưới dùng **đúng màu này**.
- Thẻ "Hôm nay đã chi": nền trắng cả ở chế độ tối; đổi được màu nền và màu thanh ngân sách (nhấn giữ thẻ). Nền tối thì chữ trắng.
- Số tiền: chi màu `danger`, thu màu `goodInk` kèm mũi tên lên (`AmountArrow`, ~0,72 cỡ chữ), điều chỉnh số dư màu phụ.

## 2. Chữ

Chỉ dùng các cỡ dưới đây (thang chữ). Chọn theo **vai trò**, không theo cảm giác từng màn. Cần cỡ mới thì sửa bảng này trước.

| Cấp | Cỡ, độ đậm | Dùng cho |
|---|---|---|
| Số lớn | 40 bold | Số tiền chính của màn: thẻ Hôm nay đã chi, thẻ nói, màn Nhập, Thống kê, Nhóm chung, Khoản chung |
| Số nổi bật trong thẻ | 24 bold | Chi theo tháng, Số dư, ô màu Thống kê, giá gói Pro |
| Số đi kèm | 19 bold | Ô danh mục trang chủ, Trung bình / Thấp nhất / Cao nhất, Cần xác nhận, Được nhận / Còn phải trả |
| Tiêu đề | 21 bold | Tiêu đề màn / tấm, tiêu đề mục (Gần đây, Danh mục…), tiêu đề lớn trong trang (tên nhóm…), tiêu đề bảng nhấn giữ |
| Nút to | 21 semibold | `BigButton`, Lưu / Huỷ, nút chính cao 60 |
| Nhấn | 17 semibold / medium | Nút nhỏ, viên chọn danh mục, dòng của bảng nhấn giữ và Cài đặt, tên thành viên, ô nhập chữ |
| Tiêu đề thẻ | 16 semibold | Chi theo tháng, Theo danh mục, Số dư, Khoản thu, Khoản lớn nhất, Giữa những người khác, Lịch sử trả tiền |
| Nội dung | 15 regular / medium / semibold | Hàng danh sách (`Font.rowTitle`, `.rowAmount`), đoạn mô tả, chữ trống ("Chưa có khoản nào"), "Xem tất cả", công tắc 2 lựa chọn (Ngày / Tháng, Chi / Thu) |
| Phụ | 13 regular, màu phụ | Dòng phụ dưới tiêu đề, chú thích, nhãn ô số liệu |
| Nhỏ | 12 | Ngày giờ trong hàng (`Font.rowSub`), số trên ô lưới ảnh, % so với cùng kỳ, chấm đếm |

Ngoại lệ có chủ đích:
- Tiêu đề mục trong Form: 17 semibold màu phụ, viết thường.
- Hàng Đã chi / Số dư trên thẻ trang chủ: 17, tự hạ 15 → 13 khi số quá dài (hai bên luôn cùng cỡ).
- Chữ số trong ô lịch và viên ngày / tháng ở Thống kê: 18 semibold kiểu tròn.
- Màn chụp: chữ đơn cách trên khung xem (số tiêu cự 15–20). Cảnh phim quảng cáo theo kịch bản riêng.
- Biểu tượng emoji / SF Symbols chỉnh cỡ theo hình, không theo thang này (xem mục 6).

## 3. Khoảng cách, bo góc

- Lề trái phải của trang: **16**.
- Khe giữa các thẻ / ô: 10 (danh sách), 8 (lưới ảnh).
- Bo góc đồng tâm: bo thẻ = bo phần tử bên trong + khoảng cách tới mép. Ví dụ hàng khoản chi: ô 56 bo 13, cách mép 10 → thẻ bo 23.
- Bo: thẻ Hôm nay đã chi 32, thẻ danh mục 28, thẻ hàng khoản chi 23, ô lưới ảnh 18, khung xem camera 32, tấm 38.
- Phần tử nằm trong một viên / thẻ bo tròn (vd vòng tròn số đếm trong viên "Các lần điều chỉnh"): cách mép viên **đều** trên, dưới và phía sát mép (vd 5), để hai đường cong đồng tâm.
- Thẻ chỉ có chữ (không có ô biểu tượng): chữ cách đều hai bên 16.
- Ô danh mục trang chủ: nửa hàng cao 140, biểu tượng 52; **kéo dài cả hàng thì cao 180, biểu tượng 72**.

## 4. Thanh tiêu đề (`screenTitle`, `softTopEdge`, `softTitleBar`)

- App tự vẽ, ẩn thanh của hệ thống, để mọi bản iOS cao bằng nhau.
- Chữ 21 bold ở giữa, cách mép trên tấm 20 và cách vạch 20; vạch mảnh 1 pt (`primary` 10%), lùi vào 16 hai bên.
- Nền thanh là màu đặc của trang. Nội dung cuộn lên **cắt gọn ở vạch**, không nhoè.
- Trang con trong tấm: nút quay lại tròn 40 bên trái (chevron.left, nền `primary` 6%). **Không** có vuốt mép trái để quay lại.
- **Nút quay lại chỉ có khi trong cùng tấm có màn trước đó** để quay về (vd danh sách nhóm → một nhóm, Cài đặt → trang con). Màn đầu tiên của tấm không có nút quay lại; đóng tấm bằng vuốt xuống. Nhóm chung: luôn có màn danh sách nhóm (kể cả khi chỉ có một nhóm), vào một nhóm thì có nút quay lại danh sách.
- Không dùng ô chọn kiểu trang của iOS (`Picker` `.navigationLink`); dùng `PickLink` / `PickPage` của app.
- Lịch sử: tiêu đề và ô tìm ghim trên vùng cuộn, vạch ngăn dưới ô tìm; nút đổi kiểu xem nằm cạnh ô tìm.

## 5. Mép mờ khi cuộn

Hiệu ứng mép cuộn của hệ thống (iOS 26+) bị **tắt ở mọi nơi** (`noSystemEdge`), vì mỗi bản iOS và mỗi SDK vẽ một kiểu.

- **Trang chủ, dưới đồng hồ** (`statusBarEdge`): lớp nhoè tăng dần như mép cuộn mặc định của iOS 27, nhoè mạnh ở sát mép trên, hết trước chân thanh trạng thái. **Chỉ nhoè, không phủ màu** (`ClearBlur`: bộ lọc `variableBlur` gắn vào lớp nhoè của `UIVisualEffectView`, ẩn các lớp tô màu).
- **Sau hai nút đáy trang chủ / Nhóm chung** (`withDock`): cùng kiểu nhoè, từ mép dưới màn lên tới ngang giữa hai nút. Nửa trên nút trở lên để nguyên.
- **Không dùng `ultraThinMaterial` / kính mờ của iOS đè lên nội dung**: nó luôn kèm lớp phủ trắng / đen, trông đục như sữa.
- Thanh nút đáy của tấm (`bottomBar`, Huỷ / Lưu): dải màu nền nhạt dần (`EdgeFade`), nút nằm yên khi bàn phím hiện.
- Thẻ Nói để ghi: không phủ, không nhoè nền phía sau.

`variableBlur` là hàm nội bộ của Apple: được dùng cho TestFlight. Nếu App Store từ chối, đổi `ClearBlur` sang nhoè đều (chỉ một chỗ trong `Chrome.swift`).

## 6. Nút

- Nút to (`BigButton`): cao 78 (ô biểu tượng 56 + lề 11), bo tròn hai đầu. Nút chính màu `cta`; Huỷ cam đậm `C2410C`.
- Dải hai nút đáy trang chủ (Nhập / Quét QR): cách mép dưới màn 16, đè lên nội dung. Cuộn hết thì đáy nội dung cách mép trên nút đúng 16.
- Nút chưa bấm được: chữ mờ 0,55.
- Nhấn: thu nhỏ 0,94, mờ 0,72, bật lại bằng lò xo (`Pressable`). Mọi nút tự vẽ dùng kiểu này.
- Nút chỉ có biểu tượng (đổi kiểu xem, về trang chủ ở màn chụp): **không nền**, vùng chạm vẫn đủ to (≥ 37).
- Hai biểu tượng thay nhau ở một nút phải **trông to bằng nhau**: đo hình thật, chỉnh cỡ chữ từng biểu tượng (vd ba vạch `lineweight` 21, hai tấm ảnh 16). Đổi biểu tượng dùng `.contentTransition(.symbolEffect(.replace))`, không mờ chéo.

## 7. Danh sách khoản chi (`ExpenseRow`)

- Một hàng là một thẻ `Palette.card`, cao 76 + khe 10, bo 23.
- Trái: ô 56 bo 13, cách mép thẻ 10. **Ảnh hoá đơn nếu có**, không thì biểu tượng / ảnh danh mục trên nền trắng.
- Giữa: tên (tối đa 2 dòng), dưới là tên danh mục (hoặc dòng phụ riêng, vd "Số dư sau: …"). Phải: số tiền, dưới là ngày | giờ (vạch dọc mảnh ngăn giữa).
- **Vuốt xoá:** dùng vuốt có sẵn của iOS. iOS 26+ nút tròn đỏ của hệ thống; iOS 18 vẽ lại nút tròn đỏ 50 cho giống. Nút cách thẻ và cách mép màn bằng nhau (~18). Có rung khi lộ nút, xoá xong hiện "Đã xoá · Hoàn tác".
- Danh sách tràn ra mép trái màn để hàng vuốt đi không bị cắt. Thẻ đầu cách vạch dưới tiêu đề 16.
- **Điều chỉnh số dư không phải khoản chi:** không hiện ở Gần đây, Lịch sử, lưới ảnh. Chỉ xem ở bảng Số dư › Các lần điều chỉnh: thẻ không có ô biểu tượng, dòng phụ là số dư sau lần đó, vuốt để xoá.

## 8. Lưới ảnh (`ExpenseTile`)

Nút đổi kiểu ở mục Gần đây và ở Lịch sử, chung một lựa chọn (`recentGrid`), app nhớ cho lần sau.

- **Trang chủ › Gần đây:** lưới so le 3 cột kiểu Pinterest, 12 khoản gần nhất, xếp lần lượt từ trái sang phải. Ô cao theo tỉ lệ ảnh hoá đơn (giới hạn 0,6…1,3); chưa có ảnh thì xen kẽ ba dáng cố định theo mã khoản. **Ô cuối mỗi cột co giãn để ba cột cùng một đáy.**
- **Lịch sử:** lưới vuông 3 cột theo từng ngày.
- Ô: ảnh phủ kín, bo 18; không có ảnh thì nền màu danh mục, biểu tượng ở giữa. Số tiền góc dưới trái.
- Chạm ô: sửa khoản; nhấn giữ: bảng tuỳ chọn. Lưới không có vuốt xoá.

## 9. Tấm (sheet), bảng nhấn giữ

- Tấm bo 38 ở mọi bản iOS (`sheetCorners`). Không có nút Xong, kéo xuống để đóng.
- Bảng nhấn giữ (`AppMenu`): đầu bảng là ô 56 (biểu tượng / màu), tên, dòng phụ. Biểu tượng dòng chọn là icon vòng tròn của SF Symbols, màu chữ, không nền. Dòng xoá chữ đỏ.

## 10. Màn chụp hoá đơn (`ReceiptScan.swift`)

- Khung xem 3:4 cố định, bo 32, có lưới chia ba (vạch trắng mờ, không có trong ảnh). Thu phóng theo mặc định của app Camera: mở ở 1× (24mm), số hiện dạng × (chữ đơn cách, không nền), chạm đổi nấc 1× · 2× · 0,5×; vuốt ngang hiện vòng tiêu cự, giữa vòng có thêm số mm. Đổi camera: camera trước 1×, quay lại camera sau giữ tiêu cự đang dùng.
- Thanh trên chỉ có nút quay lại. Nút đổi camera trước / sau nằm ngang hàng số thu phóng, sát mép phải khung xem, biểu tượng trắng cùng cỡ với số, trên nền tròn kính mờ 40. Chạm: rung ngay, khung xem lật quanh trục dọc dưới lớp kính mờ, đổi camera chạy song song.
- Camera dùng **ống vật lý** (camera trước, ống chính, ống góc siêu rộng), không dùng camera ghép nhiều ống của iOS (chậm khi đổi trước ↔ sau). Dưới 1× tự đổi sang ống góc siêu rộng. Ảnh camera trước lật gương giống khung xem.
- Hàng dưới, cao hơn vạch Home 28: ô ảnh bên trái, nút chụp ở giữa, nút nhà bên phải. Ô ảnh và nút nhà đứng **giữa khoảng từ mép màn tới mép nút chụp**.
  - Ô ảnh: hai ảnh mới nhất trong app Ảnh, khung 3:4 bo 6, xếp chồng lệch nhau, viền trắng mảnh.
  - Nút nhà: SF Symbols `house`, nét đậm, không nền. Chỉ có khi mở từ trang chủ.
- Chụp: chỉ khung xem tối sầm thoáng qua (không loé cả màn), ảnh cắt đúng 3:4 rồi dùng luôn, không qua bước sửa. Ảnh chọn từ thư viện căn vào khung 3:4.
- Chụp xong: màn nhập mở ngay **trên** màn chụp, camera vẫn chạy phía dưới. Lưu: cả hai trượt xuống về trang chủ. Huỷ: quay lại màn chụp, chụp tiếp ngay (không bật lại camera, không nháy đen).

## 11. Chỗ vẫn để hệ thống vẽ

- Công tắc (Toggle), chọn ngày giờ, bàn phím, hộp thoại xác nhận, bảng chia sẻ, thanh trạng thái.
- Cách mở tấm: iOS 18 trang phía sau thu nhỏ lùi vào, iOS 26+ tấm nổi bo lớn. Không tự vẽ lại (mất cử chỉ quen thuộc).
- Nhánh `#available` còn lại ngoài `Chrome.swift`: nút xoá khi vuốt (iOS 18 tự vẽ), bo tấm (`sheetCorners`), `BlurForm` (iOS 17 dùng Form thường).

## 12. Kiểm tra trước khi tải lên

```bash
cd ios
scripts/shots.sh                 # dựng app rồi chụp mọi màn
scripts/shots.sh -n home stats   # không dựng lại, chỉ chụp các màn cho trước
```

- Tự tạo máy ảo "Pay iOS 18 / 26 / 27" (iPhone 16 Pro), chụp sáng và tối, ghép mỗi màn một ảnh 6 cột vào `ios/build/shots/<màn>.png`.
- Màn có sẵn: `home`, `home-mid`, `home-end`, `stats`, `settings`, `history`, `house`, `entry`.
- Cờ chỉ có ở bản thử (DEBUG): `-shotOpen stats|settings|history|house|entry|voice|camera|balance|balancelog`, `-shotWide an,cafe` (ô danh mục dài cả hàng), `-shotAdjust YES` (tạo hai lần điều chỉnh số dư), `-shotScroll 0…1`, `-shotSystemEdge YES` (để mép cuộn của hệ thống, làm mẫu so sánh), `-shotPhotos YES` (hai ảnh mẫu cho ô ảnh ở màn chụp), `-recentGrid YES|NO`.
- Máy ảo không có camera, không cấp được quyền thư viện ảnh và không bấm được nút; những phần đó phải thử trên máy thật.
