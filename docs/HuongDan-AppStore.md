# Hướng dẫn đưa Pay lên App Store

Làm theo thứ tự. Nội dung để chép (mô tả, từ khoá…) nằm trong [AppStore.md](AppStore.md).
Tên menu dưới đây theo giao diện tiếng Anh của App Store Connect (appstoreconnect.apple.com); giao diện tiếng Việt có tên tương ứng.

---

## Bước 1 — Trang quyền riêng tư lên peakapp.vn

Chỉ cần trả lời Claude "đăng đi". Claude chạy `tools/deploy.sh --pay` trong thư mục Peakapp: thêm đúng file
`pay/privacy.html`, không đổi gì khác trên trang. Xong thì mở thử https://peakapp.vn/pay/privacy.html.

Phải xong bước này trước khi gửi duyệt: App Store bắt buộc có link quyền riêng tư, và màn mua Pro trong app cũng trỏ tới link này.

---

## Bước 2 — Thoả thuận, ngân hàng, thuế (để được bán)

Không có bước này thì gói Pro không bán được, TestFlight cũng không hiện giá.

1. App Store Connect → **Business** (biểu tượng ở trang đầu, hoặc menu trên cùng).
2. Mục **Agreements** → dòng **Paid Apps** → **View and Agree to Terms** → đọc, đồng ý.
3. Mục **Bank Accounts** → **Add Bank Account**:
   - Quốc gia: Vietnam; tiền nhận: VND (hoặc USD nếu tài khoản ngoại tệ).
   - Tên chủ tài khoản đúng như ở ngân hàng (không dấu), số tài khoản, mã SWIFT của ngân hàng (vd Vietcombank: BFTVVNVX, ACB: ASCBVNVX, Techcombank: VTCBVNVX — kiểm tra lại với ngân hàng của bạn).
4. Mục **Tax Forms** → **U.S. Form W-8BEN** (cá nhân ngoài nước Mỹ):
   - Điền tên, địa chỉ ở Việt Nam, quốc tịch.
   - Phần hiệp định thuế: Việt Nam và Mỹ hiện chưa có hiệp định thuế có hiệu lực (theo Claude biết — kiểm tra lại), nên để trống phần hưởng ưu đãi. Khi đó Apple chỉ khấu trừ thuế Mỹ trên phần bán cho người dùng ở Mỹ; bán ở Việt Nam không bị khấu trừ khoản này.
   - Ký điện tử, gửi.
5. Đợi trạng thái thoả thuận chuyển sang **Active** (vài giờ tới 1–2 ngày). Các bước sau vẫn làm được trong lúc chờ.

---

## Bước 3 — Tạo hai gói Pro

Vào **Apps** → chọn **Pay** → cột trái mục **Monetization**.

### 3a. Pro trọn đời (mua một lần)

1. **In-App Purchases** → nút **+**.
2. Type: **Non-Consumable**.
   - Reference Name: `Pay Pro Lifetime` (chỉ mình thấy).
   - Product ID: `com.hnaht95.sochipay.pro.lifetime` — **gõ đúng từng ký tự**, app tìm gói bằng mã này. Đặt rồi không đổi được.
3. Trong trang gói vừa tạo:
   - **Availability**: chọn tất cả quốc gia (hoặc chỉ Việt Nam).
   - **Price Schedule** → **Add Pricing**: nước gốc **Vietnam**, chọn **299.000 ₫**. Apple tự quy đổi cho các nước khác.
   - Giá ra mắt: trong Price Schedule → **Add Temporary Price** (hoặc "Schedule Price Change"): **149.000 ₫**, ngày bắt đầu = ngày app lên store, ngày kết thúc = 30 ngày sau. Hết hạn tự về 299.000 ₫.
     (Chưa biết ngày lên store thì để sau, khi app được duyệt mới thêm.)
   - **App Store Localization** → **+**:
     - Tiếng Việt: Display Name `Pay Pro trọn đời`, Description `Mở mọi tính năng Pro, trả một lần.`
     - English (U.S.): `Pay Pro Lifetime`, `Unlock every Pro feature with one payment.`
   - **Review Information**:
     - Screenshot: ảnh chụp màn mua Pro trong app (Claude chụp được, xem Bước 5).
     - Review Notes: `Mở Cài đặt › Nâng cấp Pro, hoặc chạm vào tính năng có chữ Pro.`
4. Bấm **Save**. Trạng thái phải là **Ready to Submit** (thiếu mục nào thì trang báo đỏ).

### 3b. Pro gói năm (tự gia hạn)

1. **Subscriptions** → **Create** (Subscription Group):
   - Reference Name: `Pay Pro`.
2. Trong nhóm vừa tạo → **+** (Create Subscription):
   - Reference Name: `Pay Pro Yearly`.
   - Product ID: `com.hnaht95.sochipay.pro.yearly` — gõ đúng.
3. Trong trang gói:
   - **Subscription Duration**: **1 Year**.
   - **Availability**: như gói trọn đời.
   - **Subscription Prices** → **Add Subscription Price**: Vietnam **79.000 ₫**.
   - **Localization**: Tiếng Việt `Pay Pro năm` / `Mở mọi tính năng Pro, gia hạn mỗi năm.`; English `Pay Pro Yearly` / `Unlock every Pro feature, renews yearly.`
   - **Review Information**: cùng ảnh và ghi chú như gói trọn đời.
4. Quay lại trang **nhóm** "Pay Pro" → **App Store Localization** → **+** Tiếng Việt và English: Subscription Group Display Name `Pay Pro`. (Thiếu cái này gói năm không chuyển được sang Ready to Submit.)
5. **Save** → trạng thái **Ready to Submit**.

---

## Bước 4 — Thử mua Pro qua TestFlight

Làm được khi hai gói đã **Ready to Submit** (chưa cần duyệt). Mua trong TestFlight **không trừ tiền thật**.

1. Mở TestFlight trên iPhone → cài bản mới nhất (**202610120101** trở về sau).
2. Mở Pay → **Cài đặt › Nâng cấp Pro**.
   - Phải thấy hai gói với giá **299.000 ₫** và **79.000 ₫/năm**. Còn vòng xoay mãi: gói chưa Ready to Submit, hoặc Product ID gõ sai, hoặc thoả thuận Paid Apps chưa Active.
3. Chọn **Trọn đời** → **Mua** → hộp xác nhận của Apple (ghi là TestFlight / không tính phí) → xác nhận.
   - Sau khi mua: màn đóng lại, Cài đặt hiện **Đã có Pay Pro**, các nhãn Pro biến mất, dải Thống kê xem được tháng cũ, bật được đồng bộ iCloud.
4. Thử **Khôi phục giao dịch**: xoá app → cài lại từ TestFlight → Cài đặt › Khôi phục giao dịch → phải về lại trạng thái Pro.
5. Thử **gói năm** bằng một Apple ID khác (vì trọn đời đã mua rồi thì luôn là Pro): gói năm trên TestFlight gia hạn nhanh hơn nhiều so với thật, nên để một lúc sẽ thấy tự hết hạn / gia hạn.

Muốn thử lại từ đầu với cùng Apple ID: không xoá được giao dịch TestFlight, dùng một Apple ID khác. Hoặc thử trong Xcode (Run, cấu hình mua thử có sẵn; Debug › StoreKit › Manage Transactions để xoá giao dịch).

---

## Bước 5 — Ảnh chụp màn hình

- Bắt buộc: **iPhone 6,9"** (1320 × 2868 hoặc 2868 × 1320), **tối thiểu 3, tối đa 10** ảnh.
- Chỉ cần bộ 6,9": Apple tự thu nhỏ cho các máy nhỏ hơn.
- Nên có (theo thứ tự): Trang chủ · Quét QR → màn trả tiền · Nói để ghi · Thống kê · Nhóm chung · Màn mua Pro.

Claude chụp được trên máy ảo iPhone 17 Pro Max (đúng cỡ 6,9") với dữ liệu mẫu đẹp: chỉ cần nói "chụp ảnh App Store".
Ảnh màn mua Pro cho Bước 3 (Review Information) cũng lấy từ bộ này.

---

## Bước 6 — Điền thông tin app và gửi duyệt

Vào **Apps → Pay**.

### 6a. Trang phiên bản (cột trái, mục **iOS App → 1.0 Prepare for Submission**)

1. **Previews and Screenshots**: kéo thả ảnh 6,9" vào ô iPhone 6.9" Display.
2. **Promotional Text**, **Description**, **Keywords**, **Support URL** (`https://peakapp.vn`), **Marketing URL** (để trống được): chép từ [AppStore.md](AppStore.md).
3. **Build** → **+** → chọn **202610120101** (hoặc bản mới nhất). Nếu hỏi mã hoá: app đã khai sẵn "không dùng mã hoá riêng", thường không hỏi nữa.
4. **In-App Purchases and Subscriptions** → **+** → tích **cả hai gói Pro** (lần đầu bắt buộc gửi kèm bản app).
5. **App Review Information**:
   - Sign-in required: **tắt** (app không có đăng nhập).
   - Contact: tên, số điện thoại, email của bạn.
   - Notes: chép phần "Ghi chú cho người duyệt" trong AppStore.md.
6. **Version Release**: chọn **Manually release** nếu muốn tự bấm phát hành sau khi duyệt (để kịp đặt giá ra mắt 149.000 ₫ đúng ngày), hoặc **Automatically**.
7. **Save**.

### 6b. Trang thông tin chung (cột trái **General → App Information**)

- Name: `Pay – Ghi chi tiêu` (chưa ai dùng tên này mới được; trùng thì thêm chữ khác).
- Subtitle: `Quét QR, nói một câu là ghi`.
- Category: Primary **Finance**, Secondary **Productivity**.
- **Age Rating** → Edit → trả lời "None"/"No" hết → ra **4+**.
- **Content Rights**: "No, it does not contain third-party content" (emoji và chữ viết tay là của bạn / hệ thống).

### 6c. Giá và nơi bán (**Pricing and Availability**)

- Price: **Free** (USD 0).
- Availability: tất cả quốc gia, hoặc chỉ Việt Nam.

### 6d. Quyền riêng tư (**App Privacy**)

- Privacy Policy URL: `https://peakapp.vn/pay/privacy.html`.
- **Get Started** → "Do you or your third-party partners collect data from this app?" → **No, we do not collect data from this app** → **Publish**.

### 6e. Gửi duyệt

Quay lại trang phiên bản 1.0 → **Add for Review** → **Submit to App Review**.

- Thường duyệt trong 1–2 ngày. Bị từ chối thì Apple ghi lý do trong **Resolution Center**: chụp gửi Claude để sửa.
- Duyệt xong: nếu chọn Manually release thì bấm **Release This Version**, rồi vào gói Pro trọn đời thêm giá tạm 149.000 ₫ (Bước 3a).
