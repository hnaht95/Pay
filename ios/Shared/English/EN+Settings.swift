import Foundation

extension English {
    static let settings: [String: String] = [
        // Cài đặt
        "Cài đặt": "Settings",
        "Xong": "Done",
        "Huỷ": "Cancel",
        "Lưu": "Save",
        "Phiên bản": "Version",
        "Pay — ghi chi tiêu tối giản: gõ 35k cafe hoặc quét VietQR.": "Pay — minimal expense tracking: type 35k coffee or scan a VietQR code.",
        "Tháng %@: %@đ · %@ khoản": "%@: %@đ · %@ expenses",
        "Tổng cộng %@ khoản đã ghi": "%@ expenses logged in total",

        // Ngôn ngữ
        "Ngôn ngữ": "Language",
        "Ngôn ngữ app": "App language",
        "Đổi ngôn ngữ của app và widget.": "Changes the language of the app and widgets.",

        // Truy cập nhanh
        "Truy cập nhanh": "Quick access",
        "Widget, nút Tác vụ, Phím tắt": "Widgets, Action button, Shortcuts",

        // Xoá tất cả
        "Xoá tất cả khoản chi?": "Delete all expenses?",
        "Xoá tất cả": "Delete all",
        "Xoá tất cả khoản chi": "Delete all expenses",
        "Các máy khác đang đồng bộ iCloud cũng sẽ bị xoá.": "Other devices syncing with iCloud will be cleared too.",
        "Không hoàn tác được.": "This can't be undone.",
        "Khoản định kỳ cũng dừng tự ghi.": "Recurring expenses will stop being logged too.",
        "Nên sao lưu trước.": "Back up first.",

        // Ngân sách
        "Ngân sách": "Budget",
        "Ngân sách tháng": "Monthly budget",
        "Ví dụ 8.000.000": "e.g. 8,000,000",
        "Số tiền tiêu mỗi tháng. Để trống là bỏ ngân sách.": "How much to spend each month. Leave empty to remove the budget.",
        "%@ · đã dùng %@%%": "%@ · %@%% used",
        "Kéo hoặc chạm vào thanh để chỉnh, giữ lâu để nhập số chính xác. Kéo hết sang trái là bỏ ngân sách.": "Drag or tap the bar to adjust, or touch and hold to enter an exact amount. Drag all the way left to remove the budget.",
        "Kéo hoặc chạm vào thanh để đặt ngân sách tháng, giữ lâu để nhập số. Màn hình chính và widget sẽ hiện số còn lại và mức nên tiêu mỗi ngày.": "Drag or tap the bar to set a monthly budget, or touch and hold to enter an amount. The home screen and widgets will show what's left and how much to spend per day.",
        "Mỗi tháng": "Monthly",
        "%@ đồng": "%@ dong",
        "Chưa đặt": "Not set",
        "Nhập số chính xác": "Enter exact amount",

        // Danh mục
        "Danh mục": "Categories",
        "Thêm danh mục": "Add category",
        "Ngoài 6 danh mục có sẵn, bạn tạo thêm được danh mục riêng như Thú cưng, Con nhỏ, Gym.": "Besides the 6 built-in categories, you can create your own, like Pets, Kids or Gym.",
        "Chạm để sửa, vuốt sang trái để xoá. Khoản đã ghi của danh mục bị xoá sẽ hiện là Khác.": "Tap to edit, swipe left to delete. Expenses in a deleted category will show as Other.",
        "Muốn đổi biểu tượng, màu của danh mục có sẵn thì nhấn giữ ô danh mục ở màn hình chính.": "To change the icon or color of a built-in category, touch and hold it on the home screen.",
        "Tên danh mục": "Category name",
        "Ví dụ: Thú cưng": "e.g. Pets",
        "Tên": "Name",
        "Đã có danh mục tên này.": "A category with this name already exists.",
        "Tất cả biểu tượng": "All emoji",
        "Biểu tượng": "Icon",
        "Chọn nhanh ở trên, hoặc mở bàn phím Emoji để chọn bất kỳ biểu tượng nào của iOS.": "Pick one above, or open the emoji keyboard to choose any emoji.",
        "Màu": "Color",
        "Màu gốc": "Original color",
        "Màu %@": "Color %@",
        "Danh mục mới": "New category",
        "Sửa danh mục": "Edit category",
        "Về mặc định": "Reset to default",

        // Khoản định kỳ
        "Khoản định kỳ": "Recurring",
        "Nhấn giữ một khoản chi như tiền nhà, điện, internet rồi chọn **Lặp hằng tháng**, app sẽ tự ghi mỗi tháng.": "Touch and hold an expense like rent, electricity or internet, then choose **Repeat monthly** and the app will log it every month.",
        "Ngày %@ hằng tháng": "Day %@ every month",
        "Bỏ lặp": "Stop repeating",
        "Tới ngày là app tự ghi (khi mở app). Tháng nào đã tự ghi tay khoản giống hệt thì bỏ qua. Vuốt sang trái để bỏ lặp.": "On the day, the app logs it automatically (when opened). Skipped if you already logged an identical expense that month. Swipe left to stop repeating.",

        // iCloud
        "Đồng bộ iCloud": "iCloud sync",
        "Trạng thái": "Status",
        "Đồng bộ ngay": "Sync now",
        "Đang tắt": "Off",
        "Đang kết nối…": "Connecting…",
        "Không dùng được": "Unavailable",
        "Đã đồng bộ %@": "Synced %@",
        "Đã bật": "On",
        "Máy này chưa đăng nhập iCloud hoặc đã tắt iCloud Drive (Cài đặt › Tên bạn › iCloud › iCloud Drive). Dữ liệu vẫn lưu trên máy.": "This device isn't signed in to iCloud or iCloud Drive is off (Settings › Your Name › iCloud › iCloud Drive). Your data is still saved on this device.",
        "Dữ liệu chỉ lưu trên iPhone này. Bật để dùng chung với iPhone/iPad khác cùng Apple ID.": "Data is saved only on this iPhone. Turn on to share it with your other iPhone or iPad on the same Apple ID.",
        "Dữ liệu tự đồng bộ với iPhone/iPad khác cùng Apple ID. Không có mạng vẫn dùng được, có mạng sẽ tự cập nhật.": "Data syncs automatically with your other iPhone or iPad on the same Apple ID. Works offline and updates when you're back online.",

        // Thanh toán
        "Thanh toán": "Payments",
        "App ngân hàng": "Bank app",
        "Mở sẵn người nhận + số tiền": "Fills in recipient + amount",
        "Chỉ mở app (quét lại QR)": "Opens app only (scan QR again)",
        "Sau khi quét, Pay mở sẵn người nhận và số tiền trong app ngân hàng, không phải quét lại.": "After scanning, Pay fills in the recipient and amount in your bank app, so you don't have to scan again.",
        "App này chỉ mở được, bạn sẽ quét lại mã QR trong app ngân hàng.": "This app can only be opened; you'll scan the QR code again in the bank app.",

        // Dữ liệu
        "Dữ liệu": "Data",
        "Sao lưu ra file": "Back up to file",
        "Khôi phục từ file sao lưu": "Restore from backup",
        "Xuất CSV (Excel)": "Export CSV (Excel)",
        "File sao lưu của bản web cũng khôi phục được ở đây. Khôi phục chỉ thêm khoản còn thiếu, không ghi đè.": "Backups from the web version can be restored here too. Restoring only adds missing expenses and never overwrites.",

        // Hướng dẫn truy cập nhanh
        "Widget màn hình chính": "Home Screen widget",
        "Ở màn hình chính, chạm và giữ vào chỗ trống đến khi biểu tượng rung.": "On the Home Screen, touch and hold an empty area until the apps jiggle.",
        "Bấm Sửa › Thêm tiện ích, tìm \"Pay\".": "Tap Edit › Add Widget, then search for \"Pay\".",
        "Chọn \"Chi tiêu hôm nay\" (cỡ vừa có nút Quét QR, Nói, Nhập) hoặc \"Nói để ghi\" (chạm là nghe luôn).": "Choose \"Today's spending\" (the medium size has Scan QR, Speak and Type buttons) or \"Speak to log\" (tap and it starts listening).",
        "Màn hình khoá: nút micro": "Lock Screen: mic button",
        "Chạm và giữ màn hình khoá, bấm Tuỳ chỉnh › Màn hình khoá.": "Touch and hold the Lock Screen, then tap Customize › Lock Screen.",
        "Bấm vùng widget dưới đồng hồ, chọn Pay › \"Nói để ghi\" (nút micro tròn).": "Tap the widget area below the clock, then choose Pay › \"Speak to log\" (the round mic button).",
        "iOS 18 trở lên: bấm nút ở góc dưới (đèn pin, camera), đổi thành \"Pay: Ghi bằng giọng nói\".": "iOS 18 or later: tap a bottom corner button (flashlight, camera) and change it to \"Pay: Log by voice\".",
        "Chạm nút micro, mở khoá xong là Pay nghe luôn. Màn hình khoá cũng có nút quét QR và số đã chi hôm nay.": "Tap the mic button and Pay starts listening as soon as you unlock. The Lock Screen also has a Scan QR button and today's spending.",
        "Nút Tác vụ: ghi bằng giọng nói": "Action button: log by voice",
        "Mở Cài đặt › Nút Tác vụ, vuốt đến Điều khiển.": "Open Settings › Action Button and swipe to Controls.",
        "Bấm Chọn điều khiển, tìm \"Pay: Ghi bằng giọng nói\".": "Tap Choose a Control, then search for \"Pay: Log by voice\".",
        "Nhấn giữ nút Tác vụ: Pay mở và nghe luôn. Nói \"35k cafe\", ngừng nói là tự ghi.": "Press and hold the Action button: Pay opens and starts listening. Say \"35k coffee\" and it logs when you stop talking.",
        "Cần iPhone 15 Pro trở lên, iOS 18 trở lên. Nói được nhiều kiểu: \"35 nghìn cà phê\", \"1tr2 tiền nhà\", \"grab 52k\". Danh mục tự đoán theo ghi chú.": "Requires iPhone 15 Pro or later and iOS 18 or later. Say it in many ways: \"35 thousand coffee\", \"1.2 million rent\", \"grab 52k\". The category is guessed from the note.",
        "Nút Tác vụ: quét QR": "Action button: scan QR",
        "Bấm Chọn điều khiển, tìm \"Pay: Quét QR\".": "Tap Choose a Control, then search for \"Pay: Scan QR\".",
        "Nhấn giữ nút Tác vụ là mở camera quét ngay.": "Press and hold the Action button to open the scanner right away.",
        "Cần iOS 18 trở lên. Nút Tác vụ chỉ gán được một việc: chọn ghi bằng giọng nói hoặc quét QR. Nút \"Pay: Quét QR\" cũng thêm được vào Trung tâm điều khiển.": "Requires iOS 18 or later. The Action button can do only one thing: choose voice logging or QR scanning. The \"Pay: Scan QR\" control can also be added to Control Center.",
        "Siri và Phím tắt": "Siri and Shortcuts",
        "Nói \"Ghi chi tiêu bằng Pay\" với Siri, rồi nói khoản chi. Hoặc \"Quét QR bằng Pay\".": "Say \"Log expense with Pay\" to Siri, then say the expense. Or \"Scan QR with Pay\".",
        "Hoặc mở app Phím tắt, hai lệnh này có sẵn trong mục Pay.": "Or open the Shortcuts app; both actions are listed under Pay.",
    ]
}
