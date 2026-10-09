import Foundation

/// Ngôn ngữ của app, chọn trong Cài đặt (mặc định tiếng Việt). Lưu trong App Group để widget cùng đổi theo.
/// Chữ trong code viết bằng tiếng Việt; bọc trong L("...") để ra tiếng Anh khi chọn English (bảng ở Shared/English/).
enum Lang: String, CaseIterable {
    case vi, en

    static let key = "appLanguage"
    private static let store = UserDefaults(suiteName: Summary.group) ?? .standard

    /// Đọc một lần rồi giữ; đổi qua `Lang.set` (app dựng lại giao diện theo thông báo `Lang.changed`)
    /// (Bản Debug chạy với "-filmLang en" thì dùng tiếng Anh mà không đổi lựa chọn đã lưu, để quay phim giới thiệu)
    private(set) static var current: Lang = {
        #if DEBUG
        if let l = UserDefaults.standard.string(forKey: "filmLang").flatMap(Lang.init(rawValue:)) { return l }
        #endif
        return Lang(rawValue: store.string(forKey: key) ?? "") ?? .vi
    }()

    static var isEnglish: Bool { current == .en }
    static var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "vi_VN") }
    static let changed = Notification.Name("PayLanguageChanged")

    static func set(_ l: Lang) {
        guard l != current else { return }
        current = l
        store.set(l.rawValue, forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// Tên hiện trong Cài đặt, luôn viết bằng chính ngôn ngữ đó
    var title: String { self == .vi ? "Tiếng Việt" : "English" }
}

/// Chữ tiếng Việt `vi` theo ngôn ngữ đang chọn. Chưa có trong bảng thì giữ nguyên tiếng Việt.
func L(_ vi: String) -> String {
    guard Lang.isEnglish else { return vi }
    return English.table[vi] ?? vi
}

/// Như L(_:), có tham số kiểu String(format:): L("Còn %@", money)
func L(_ vi: String, _ args: CVarArg...) -> String {
    String(format: L(vi), locale: Lang.locale, arguments: args)
}

/// Bảng Việt -> Anh, ghép từ các phần trong Shared/English/ (mỗi file giao diện một phần)
enum English {
    static let table: [String: String] = parts.reduce(into: [:]) { all, part in all.merge(part) { a, _ in a } }
}
