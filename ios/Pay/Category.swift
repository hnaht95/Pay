import SwiftUI
import UIKit

struct Category: Identifiable, Hashable {
    let k: String
    let icon: String
    /// Tên lưu trữ: tiếng Việt với danh mục có sẵn, hoặc đúng chữ người dùng đặt
    let rawName: String
    /// Tên để hiện: danh mục có sẵn ra tiếng Anh khi chọn English; tên người dùng tự đặt giữ nguyên (L trả lại chữ lạ)
    var name: String { L(rawName) }
    let color: Color
    /// Dùng hình vẽ phẳng trong Assets ("cat-<k>"); đổi sang emoji khác thì không
    var art = false
    let kw: [String]
    /// Màu biểu đồ của danh mục tự tạo (danh mục có sẵn dùng bảng màu cố định bên dưới)
    var customChart: Color? = nil
    /// Màu nền tối (xanh lá đậm, than): chữ trên ô dùng màu trắng
    var onDark = false
    /// Màu chữ trên nền màu của danh mục
    var ink: Color { onDark ? .white : Color(hex: 0x111114) }

    var id: String { k }

    init(k: String, icon: String, name: String, color: Color, art: Bool = false, kw: [String], customChart: Color? = nil, onDark: Bool = false) {
        self.k = k; self.icon = icon; self.rawName = name; self.color = color
        self.art = art; self.kw = kw; self.customChart = customChart; self.onDark = onDark
    }

    /// Danh mục tự tạo đang dùng, Store cập nhật mỗi khi đổi (cả khi máy khác thêm qua iCloud)
    nonisolated(unsafe) static var custom: [Category] = []
    /// Danh mục có sẵn sau khi người dùng đổi biểu tượng / màu / tên
    nonisolated(unsafe) static var edited: [String: Category] = [:]
    /// Danh mục tiền vào tự tạo (mã "in-u-…")
    nonisolated(unsafe) static var incomeCustom: [Category] = []

    /// Có sẵn (đã áp chỉnh sửa), rồi tự tạo, "Khác" luôn ở cuối
    static var all: [Category] {
        let base = builtin.map { edited[$0.k] ?? $0 }
        return Array(base.dropLast()) + custom + [base[base.count - 1]]
    }

    static let builtin: [Category] = [
        Category(k: "an", icon: "🍕", name: "Ăn uống", color: Color(hex: 0xF07B3F), kw: ["an", "com", "pho", "bun", "banh", "mi", "bia", "lau", "nuong", "kfc", "lotteria", "jollibee", "pizza", "grabfood", "shopeefood", "quan", "nha hang", "restaurant", "food", "bakery", "an sang", "an trua", "an toi", "chao", "xoi", "che", "kem", "tap hoa", "lunch", "dinner", "breakfast", "brunch", "meal", "rice", "noodle", "noodles", "beer", "snack", "snacks", "burger", "eat", "eating", "mcdonalds", "takeout"]),
        Category(k: "cafe", icon: "🥤", name: "Cafe", color: Color(hex: 0xFFD43B), kw: ["cafe", "ca phe", "coffee", "tra", "tra sua", "highlands", "starbucks", "phuc long", "katinat", "sinh to", "nuoc mia", "trung nguyen", "cong ca phe", "the coffee house", "tocotoco", "gong cha", "mixue", "phe la", "tea", "milk tea", "bubble tea", "boba", "latte", "cappuccino", "espresso", "smoothie", "juice"]),
        Category(k: "di", icon: "🚕", name: "Đi lại", color: Color(hex: 0xEA5455), kw: ["grab", "be", "xanh sm", "gojek", "xang", "taxi", "gui xe", "do xe", "parking", "ve xe", "ve tau", "may bay", "petrolimex", "rua xe", "sua xe", "vetc", "bot", "gas", "fuel", "petrol", "bus", "train", "flight", "plane", "uber", "toll", "metro", "car wash"], onDark: true),
        Category(k: "mua", icon: "🛒", name: "Mua sắm", color: Color(hex: 0xA2D5F2), kw: ["shopee", "lazada", "tiki", "tiktok", "sieu thi", "winmart", "bach hoa", "circle k", "gs25", "familymart", "7-eleven", "ministop", "quan ao", "ao", "quan", "giay", "dep", "my pham", "mart", "store", "shop", "uniqlo", "di cho", "shopping", "clothes", "shirt", "shoes", "market", "groceries", "grocery", "supermarket", "amazon", "cosmetics"]),
        Category(k: "hd", icon: "🧾", name: "Hoá đơn", color: Color(hex: 0xE2DBFF), kw: ["dien", "tien nuoc", "internet", "wifi", "mang", "4g", "5g", "dien thoai", "nap tien", "tien nha", "thue nha", "phong", "hoc phi", "evn", "viettel", "vnpt", "fpt", "mobifone", "vinaphone", "netflix", "spotify", "youtube", "icloud", "bao hiem", "chung cu", "phi dich vu", "rent", "electricity", "electric", "electric bill", "water bill", "phone bill", "mobile", "top up", "insurance", "tuition", "subscription", "utilities"]),
        Category(k: "khac", icon: "📌", name: "Khác", color: Color(hex: 0xCFEEDD), kw: []),
    ]

    /// Danh mục tiền vào có sẵn. Mã bắt đầu bằng "in-": khoản nào mang mã này là tiền vào (không tính vào chi tiêu, ngân sách)
    static let incomeBuiltin: [Category] = [
        Category(k: "in-luong", icon: "💼", name: "Lương", color: Color(hex: 0xC9F2D4), kw: ["luong", "tien luong", "nhan luong", "salary", "payroll", "wage", "wages", "paycheck"]),
        Category(k: "in-thuong", icon: "🎁", name: "Thưởng", color: Color(hex: 0xFFE7A8), kw: ["tien thuong", "thuong tet", "nhan thuong", "li xi", "lixi", "bonus", "award", "awards", "gift", "gifts"]),
        Category(k: "in-nhan", icon: "💸", name: "Được chuyển", color: Color(hex: 0xC8E6FF), kw: ["duoc chuyen", "nhan tien", "nhan chuyen khoan", "chuyen den", "chuyen vao", "chuyen khoan vao", "ck vao", "tien ve", "hoan tien", "refund", "cashback", "received", "collect interest", "interest"]),
        Category(k: "in-khac", icon: "💰", name: "Khác", color: Color(hex: 0xE4E4E8), kw: ["tien vao", "thu nhap", "income"]),
    ]

    /// Danh mục tiền vào: có sẵn (đã áp chỉnh sửa), rồi tự tạo, "Khác" luôn ở cuối
    static var income: [Category] {
        let base = incomeBuiltin.map { edited[$0.k] ?? $0 }
        return Array(base.dropLast()) + incomeCustom + [base[base.count - 1]]
    }

    /// Điều chỉnh số dư (không phải thu hay chi): "adj+" cộng vào số dư, "adj-" trừ đi. Khoản đầu tiên là số dư ban đầu
    static let adjust: [Category] = [
        Category(k: "adj+", icon: "⚖️", name: "Điều chỉnh số dư", color: Color(hex: 0xE4E4E8), kw: []),
        Category(k: "adj-", icon: "⚖️", name: "Điều chỉnh số dư", color: Color(hex: 0xE4E4E8), kw: []),
    ]

    /// Mã khoản điều chỉnh số dư
    static func isAdjust(_ k: String?) -> Bool { k?.hasPrefix("adj") == true }

    /// Danh mục theo mã. Mã lạ (danh mục đã xoá / chưa đồng bộ về) thì "Khác" cùng loại: tiền vào vẫn là tiền vào
    static func get(_ k: String?) -> Category {
        if let k, isAdjust(k) { return adjust.first { $0.k == k } ?? adjust[0] }
        if let k, isIncome(k) { return income.first { $0.k == k } ?? income.last! }
        return all.first { $0.k == k } ?? all.last!
    }

    static func isBuiltin(_ k: String) -> Bool { builtin.contains { $0.k == k } || incomeBuiltin.contains { $0.k == k } }

    /// Bản gốc của danh mục có sẵn (chi hoặc tiền vào)
    static func base(_ k: String) -> Category? { (builtin + incomeBuiltin).first { $0.k == k } }

    /// Mã danh mục tiền vào
    static func isIncome(_ k: String?) -> Bool { k?.hasPrefix("in-") == true }

    /// Đoán danh mục tiền vào theo ghi chú (từ khoá dài nhất); không khớp từ nào thì nil
    static func guessIncome(_ text: String?) -> String? {
        let s = " " + strip(text ?? "").map { $0.isLetter || $0.isNumber || $0 == " " ? String($0) : " " }.joined() + " "
        // Danh mục tự tạo ưu tiên trước, như guess()
        for list in [incomeCustom, income] {
            var best: String?, len = 0
            for c in list { for w in c.kw where s.contains(" \(w) ") && w.count > len { best = c.k; len = w.count } }
            if let best { return best }
        }
        return nil
    }

    /// Màu đậm dùng cho biểu đồ (màu pastel ở trên quá nhạt để phân biệt). Cùng tông với màu pastel,
    /// cố định theo danh mục; đã kiểm tra phân biệt được cả khi mù màu, ở chế độ sáng lẫn tối.
    var chart: Color {
        if let customChart { return customChart }
        return switch k {
        case "an": Color(light: 0xE8692A, dark: 0xF07B3F)
        case "cafe": Color(light: 0xA88400, dark: 0xE5B000)
        case "di": Color(light: 0xD93A3C, dark: 0xEA5455)
        case "mua": Color(light: 0x3E9BD6, dark: 0x5AAFE3)
        case "hd": Color(light: 0x4A3AA7, dark: 0x9085E9)
        case "in-luong": Color(light: 0x2E9E55, dark: 0x45C06E)
        case "in-thuong": Color(light: 0xB58A00, dark: 0xE5B000)
        case "in-nhan": Color(light: 0x2F7FC9, dark: 0x5AAFE3)
        case "in-khac": Color(light: 0x6B6B78, dark: 0x9A9AA6)
        default: Color(light: 0x1BAF7A, dark: 0x199E70)
        }
    }

    /// Đoán danh mục từ ghi chú / tên quán: lấy từ khoá khớp dài nhất.
    static func guess(_ text: String?) -> String {
        let s = " " + strip(text ?? "").map { $0.isLetter || $0.isNumber || $0 == " " ? String($0) : " " }.joined() + " "
        // Danh mục tự tạo ưu tiên trước: người dùng đặt tên "Mèo" thì "mua cát cho mèo" phải vào Mèo,
        // không bị từ khoá có sẵn (mua, chợ…) giành mất
        var best = "khac", len = 0
        for c in custom {
            for w in c.kw where s.contains(" \(w) ") && w.count > len { best = c.k; len = w.count }
        }
        if best != "khac" { return best }
        for c in all {
            for w in c.kw where s.contains(" \(w) ") && w.count > len {
                best = c.k; len = w.count
            }
        }
        return best
    }

    /// Mọi danh mục có từ khoá xuất hiện trong ghi chú (danh mục tự tạo trước), để người dùng đổi nhanh khi câu nhắc tới nhiều thứ.
    static func matches(_ text: String?) -> [String] {
        let s = " " + strip(text ?? "").map { $0.isLetter || $0.isNumber || $0 == " " ? String($0) : " " }.joined() + " "
        return (custom + all.filter { c in !custom.contains { $0.k == c.k } })
            .filter { c in c.kw.contains { s.contains(" \($0) ") } }
            .map(\.k)
    }
}

/// Hình minh hoạ phẳng của danh mục (Fluent Emoji Flat của Microsoft, giấy phép MIT), trong Assets "cat-<k>".
/// Danh mục chưa có hình thì hiện emoji.
struct CategoryIcon: View {
    let c: Category
    var size: CGFloat = 28

    var body: some View {
        if let img = CategoryPhotos.image(c.k) {
            // Danh mục có ảnh riêng: ảnh vuông bo góc thay cho biểu tượng
            Image(uiImage: img).resizable().scaledToFill().frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        } else if c.art, UIImage(named: "cat-\(c.k)") != nil {
            Image("cat-\(c.k)").resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Text(c.icon).font(.system(size: size * 0.85))
        }
    }
}

/// Màu cho danh mục tự tạo: nền pastel (ô, chip) và màu đậm cùng tông cho biểu đồ.
enum CategoryTone {
    static let all: [(bg: UInt32, chart: UInt32)] = [
        (0xFFE1B3, 0xE08A00),   // cam
        (0xD6F5C9, 0x3E9B2F),   // lá
        (0xC8F0F0, 0x1C9A9A),   // ngọc
        (0xD7E0FF, 0x4560D8),   // xanh dương
        (0xF3D6FF, 0xA33FCC),   // tím
        (0xFFD6D6, 0xD23C3C),   // đỏ
        (0xFFF2B8, 0xB59200),   // vàng
        (0xE4E4E8, 0x6B6B78),   // xám
        // Đậm: vẫn đủ sáng để chữ đen trên ô đọc rõ
        (0xFFA94D, 0xC96A00),   // cam
        (0x7ED957, 0x2E8B1F),   // lá
        (0x4FD1C5, 0x158A80),   // ngọc
        (0x7F9CFF, 0x2F4FD0),   // xanh dương
        (0xB993FF, 0x7A3FD6),   // tím
        (0xFF7A7A, 0xC42F2F),   // đỏ
        (0xFFD43B, 0xA88400),   // vàng
        (0xFF8CC6, 0xC2387E),   // hồng
        // Bộ màu phẳng, đậm (đo từ ảnh mẫu người dùng gửi 10/10/2026): hai màu tối dùng chữ trắng, xem `dark`
        (0xF5491C, 0xD93A10),   // cam đỏ
        (0xF4EDE1, 0xB59A6E),   // kem
        (0xEEAC27, 0xB57C00),   // vàng nghệ
        (0xADD3D4, 0x3E8E91),   // xanh ngọc nhạt
        (0x134128, 0x1F6B42),   // xanh lá đậm
        (0x141414, 0x55555C),   // than
        (0xFBC1A9, 0xD9703F),   // đào
    ]
    /// 8 màu đầu là nhạt, 8 màu sau là đậm, 7 màu cuối là bộ màu phẳng
    static let light = 0..<8, strong = 8..<16, flat = 16..<23
    /// Màu người dùng tự chọn (bảng chọn màu của iOS): lưu chung số `tone` với chỉ số bảng màu, bằng `customBase + 0xRRGGBB`
    static let customBase = 0x1_000_000
    static func isCustom(_ i: Int) -> Bool { i >= customBase }
    static func custom(_ rgb: UInt32) -> Int { customBase + Int(rgb & 0xFFFFFF) }
    static func rgb(_ i: Int) -> UInt32 { UInt32((i - customBase) & 0xFFFFFF) }

    /// Màu tối: chữ và biểu tượng trên ô phải trắng
    static func dark(_ i: Int) -> Bool {
        guard isCustom(i) else { return i == 20 || i == 21 }
        let c = rgb(i)
        let r = Double((c >> 16) & 0xFF), g = Double((c >> 8) & 0xFF), b = Double(c & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255 < 0.55
    }
    static func bg(_ i: Int) -> Color {
        isCustom(i) ? Color(hex: rgb(i)) : Color(hex: all[(i % all.count + all.count) % all.count].bg)
    }
    /// Màu biểu đồ: màu tự chọn thì lấy chính nó đậm thêm (sáng quá thì khó thấy trên biểu đồ)
    static func chart(_ i: Int) -> Color {
        guard isCustom(i) else { return Color(hex: all[(i % all.count + all.count) % all.count].chart) }
        let c = rgb(i)
        let k = dark(i) ? 1.0 : 0.62
        func ch(_ v: UInt32) -> UInt32 { UInt32(Double(v & 0xFF) * k) }
        return Color(hex: ch(c >> 16) << 16 | ch(c >> 8) << 8 | ch(c))
    }
}

/// Mũi tên trước số tiền thay cho dấu + / −: lên là tiền vào (số dư tăng), xuống là tiền ra. Nhỏ hơn chữ số (~0,72 cỡ chữ)
struct AmountArrow: View {
    let up: Bool
    var size: CGFloat = 15

    var body: some View {
        Image(systemName: up ? "arrow.up" : "arrow.down").font(.system(size: (size * 0.72).rounded(), weight: .bold))
    }
}

/// Bỏ dấu tiếng Việt, chữ thường: "Phở Bò" -> "pho bo"
func strip(_ s: String) -> String {
    s.lowercased().replacingOccurrences(of: "đ", with: "d").folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN"))
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// Màu đổi theo sáng / tối
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    }
}

/// Bảng màu phẳng, giống bản web
enum Palette {
    static let bg = Color(light: 0xF4F5F8, dark: 0x0D0D10)
    static let surface = Color(light: 0xFFFFFF, dark: 0x17171B)
    static let card = Color(light: 0xEBEDF2, dark: 0x1D1D22)
    static let pill = Color(light: 0xE6E8EE, dark: 0x26262C)
    static let hero = Color(light: 0xDFE5FF, dark: 0x242B4D)
    static let good = Color(light: 0xDFF3E3, dark: 0x1F3A27)
    static let goodInk = Color(light: 0x2F7A43, dark: 0x8FDCA3)
    static let cta = Color(light: 0x111114, dark: 0xFFFFFF)
    static let ctaInk = Color(light: 0xFFFFFF, dark: 0x111114)
    static let danger = Color(light: 0xD92D20, dark: 0xFF6B5E)
}
