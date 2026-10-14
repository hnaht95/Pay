import Foundation

extension English {
    static let voice: [String: String] = [
        // Thẻ nói để ghi (VoiceEntryView)
        "iPhone chưa nhận được giọng tiếng Việt lúc này. Thử lại sau, hoặc quét QR.": "Speech recognition isn't available right now. Try again later, or scan a QR code.",
        "Không dùng được micro lúc này. Thử lại, hoặc quét QR.": "The microphone isn't available right now. Try again, or scan a QR code.",
        "Không bật được micro.": "Couldn't turn on the microphone.",
        "Không bật được micro (mã %@). Bấm Nói lại để thử lần nữa.": "Couldn't turn on the mic (code %@). Tap Try again.",
        "Đã ghi": "Logged",
        "Đang nghe": "Listening",
        "Đã hoàn tác, chưa ghi gì": "Undone. Nothing logged.",
        "Chưa nghe rõ số tiền": "Didn't catch the amount",
        "Đóng": "Close",
        "Hay là": "Or",
        "Bấm Nói lại để nói khoản khác.": "Tap Try Again to log something else.",
        "Vui lòng nói số tiền để ghi, ví dụ: \"ba lăm nghìn cà phê\"": "Please say an amount to log, e.g. \"35k coffee\"",
        "Đã nghe: \"%@\"": "Heard: \"%@\"",
        "Nói ví dụ: \"ba lăm nghìn cà phê\" hoặc \"nhận lương mười lăm triệu\"": "Say e.g. \"35k coffee\" or \"salary 15 million\"",
        "Vào Cài đặt › Pay để bật Micro và Nhận dạng giọng nói.": "Go to Settings › Pay and turn on Microphone and Speech Recognition.",
        "Cần quyền micro": "Microphone access needed",
        "Đang bật micro…": "Starting microphone…",
        "Hoàn tác": "Undo",
        "Sửa": "Edit",
        "Xong": "Done",
        "Quét QR": "Scan QR",
        "Mở Cài đặt": "Open Settings",
        "Nói lại": "Try Again",

        // Câu trả lời của lệnh "Ghi chi tiêu" trong Siri / Phím tắt (LogExpenseIntent)
        "Chưa nghe rõ số tiền. Nói lại, ví dụ: 35k cafe": "Didn't catch the amount. Try again, e.g. 35k coffee",
        "Đã ghi %@ %@.": "Logged %@ under %@.",
        "%@ trong tháng.": "%@ this month.",
        "Hôm nay đã chi %@.": "Spent %@ today.",

        // Widget và nút Trung tâm điều khiển (PayWidget)
        "Chi tiêu hôm nay": "Today's Spending",
        "Xem nhanh số đã chi, chạm để quét QR, nói hoặc nhập khoản mới.": "See today's spending at a glance. Tap to scan a QR code, speak, or add an expense.",
        "Nói để ghi": "Speak to Log",
        "Nhập": "Add",
        "Hôm nay": "Today",
        "Hôm nay %@": "Today %@",
        "Hôm nay đã chi": "Spent today",
        "Tháng: %@": "This month: %@",
        "Tháng %ld: %@": "Month %ld: %@",
        "Chạm là Pay nghe luôn, nói \"35k cafe\" là ghi.": "Tap and Pay starts listening. Say \"35k coffee\" to log it.",
        "Ghi bằng giọng nói": "Log by Voice",
        "Pay: Ghi bằng giọng nói": "Pay: Log by Voice",
        "Mở Pay và nghe luôn, nói \"35k cafe\" là ghi.": "Opens Pay and starts listening. Say \"35k coffee\" to log it.",
        "Pay: Quét QR": "Pay: Scan QR",
        "Mở Pay và quét mã QR thanh toán.": "Opens Pay to scan a payment QR code.",
    ]
}
