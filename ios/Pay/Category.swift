import SwiftUI

struct Category: Identifiable, Hashable {
    let k: String
    let icon: String
    let name: String
    let color: Color
    /// Dùng hình vẽ phẳng trong Assets ("cat-<k>"); đổi sang emoji khác thì không
    var art = false
    let kw: [String]
    /// Màu biểu đồ của danh mục tự tạo (danh mục có sẵn dùng bảng màu cố định bên dưới)
    var customChart: Color? = nil
    var id: String { k }

    /// Danh mục tự tạo đang dùng, Store cập nhật mỗi khi đổi (cả khi máy khác thêm qua iCloud)
    nonisolated(unsafe) static var custom: [Category] = []
    /// Danh mục có sẵn sau khi người dùng đổi biểu tượng / màu / tên
    nonisolated(unsafe) static var edited: [String: Category] = [:]

    /// Có sẵn (đã áp chỉnh sửa), rồi tự tạo, "Khác" luôn ở cuối
    static var all: [Category] {
        let base = builtin.map { edited[$0.k] ?? $0 }
        return Array(base.dropLast()) + custom + [base[base.count - 1]]
    }

    static let builtin: [Category] = [
        Category(k: "an", icon: "🍜", name: "Ăn uống", color: Color(hex: 0xFFC9C1), art: true, kw: ["an", "com", "pho", "bun", "banh", "mi", "bia", "lau", "nuong", "kfc", "lotteria", "jollibee", "pizza", "grabfood", "shopeefood", "quan", "nha hang", "restaurant", "food", "bakery", "an sang", "an trua", "an toi", "chao", "xoi", "che", "kem", "tap hoa"]),
        Category(k: "cafe", icon: "☕", name: "Cafe", color: Color(hex: 0xF1DCC0), art: true, kw: ["cafe", "ca phe", "coffee", "tra", "tra sua", "highlands", "starbucks", "phuc long", "katinat", "sinh to", "nuoc mia", "trung nguyen", "cong ca phe", "the coffee house", "tocotoco", "gong cha", "mixue", "phe la"]),
        Category(k: "di", icon: "🛵", name: "Đi lại", color: Color(hex: 0xC9E3FF), art: true, kw: ["grab", "be", "xanh sm", "gojek", "xang", "taxi", "gui xe", "do xe", "parking", "ve xe", "ve tau", "may bay", "petrolimex", "rua xe", "sua xe", "vetc", "bot"]),
        Category(k: "mua", icon: "🛍️", name: "Mua sắm", color: Color(hex: 0xFFD3E6), art: true, kw: ["shopee", "lazada", "tiki", "tiktok", "sieu thi", "winmart", "bach hoa", "circle k", "gs25", "familymart", "7-eleven", "ministop", "quan ao", "ao", "quan", "giay", "dep", "my pham", "mart", "store", "shop", "uniqlo", "cho"]),
        Category(k: "hd", icon: "🧾", name: "Hoá đơn", color: Color(hex: 0xE2DBFF), art: true, kw: ["dien", "tien nuoc", "internet", "wifi", "mang", "4g", "5g", "dien thoai", "nap tien", "tien nha", "thue nha", "phong", "hoc phi", "evn", "viettel", "vnpt", "fpt", "mobifone", "vinaphone", "netflix", "spotify", "youtube", "icloud", "bao hiem", "chung cu", "phi dich vu"]),
        Category(k: "khac", icon: "📌", name: "Khác", color: Color(hex: 0xCFEEDD), art: true, kw: []),
    ]

    static func get(_ k: String?) -> Category { all.first { $0.k == k } ?? all.last! }

    static func isBuiltin(_ k: String) -> Bool { builtin.contains { $0.k == k } }

    /// Màu đậm dùng cho biểu đồ (màu pastel ở trên quá nhạt để phân biệt). Cùng tông với màu pastel,
    /// cố định theo danh mục; đã kiểm tra phân biệt được cả khi mù màu, ở chế độ sáng lẫn tối.
    var chart: Color {
        if let customChart { return customChart }
        return switch k {
        case "an": Color(light: 0xE34948, dark: 0xE34948)
        case "cafe": Color(light: 0xEDA100, dark: 0xC98500)
        case "di": Color(light: 0x2A78D6, dark: 0x3987E5)
        case "mua": Color(light: 0xE87BA4, dark: 0xD55181)
        case "hd": Color(light: 0x4A3AA7, dark: 0x9085E9)
        default: Color(light: 0x1BAF7A, dark: 0x199E70)
        }
    }

    /// Đoán danh mục từ ghi chú / tên quán: lấy từ khoá khớp dài nhất.
    static func guess(_ text: String?) -> String {
        let s = " " + strip(text ?? "").map { $0.isLetter || $0.isNumber || $0 == " " ? String($0) : " " }.joined() + " "
        var best = "khac", len = 0
        for c in all {
            for w in c.kw where s.contains(" \(w) ") && w.count > len {
                best = c.k; len = w.count
            }
        }
        return best
    }
}

/// Hình minh hoạ phẳng của danh mục (Fluent Emoji Flat của Microsoft, giấy phép MIT), trong Assets "cat-<k>".
/// Danh mục chưa có hình thì hiện emoji.
struct CategoryIcon: View {
    let c: Category
    var size: CGFloat = 28

    var body: some View {
        if c.art, UIImage(named: "cat-\(c.k)") != nil {
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
    ]
    /// 8 màu đầu là nhạt, 8 màu sau là đậm
    static let light = 0..<8, strong = 8..<16
    static func bg(_ i: Int) -> Color { Color(hex: all[(i % all.count + all.count) % all.count].bg) }
    static func chart(_ i: Int) -> Color { Color(hex: all[(i % all.count + all.count) % all.count].chart) }
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
