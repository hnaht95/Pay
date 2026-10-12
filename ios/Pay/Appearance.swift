import SwiftUI

/// Giao diện chọn trong Cài đặt: theo máy, luôn sáng, luôn tối. Tối giản là công tắc riêng (danh mục không màu, biểu tượng
/// vẫn màu), đi được với cả sáng lẫn tối
enum Appearance: String, CaseIterable {
    case system, light, dark
    static let key = "appearance"
    static let minimalKey = "appearanceMinimal"

    static var minimalOn: Bool { UserDefaults.standard.bool(forKey: minimalKey) }

    static var current: Appearance { Appearance(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system }

    var title: String {
        switch self {
        case .system: L("Theo máy")
        case .light: L("Sáng")
        case .dark: L("Tối")
        }
    }

    /// Đặt thẳng lên cửa sổ (không dùng preferredColorScheme): cả các màn UIKit mở riêng (màn mua Pro, mời vào nhóm…) cũng theo
    @MainActor static func apply() {
        let style: UIUserInterfaceStyle = switch current { case .light: .light; case .dark: .dark; default: .unspecified }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for w in scene.windows { w.overrideUserInterfaceStyle = style }
        }
    }
}

extension View {
    /// Gốc app: bật / tắt Tối giản thì dựng lại toàn bộ (màu danh mục đọc thẳng cài đặt, không qua trạng thái SwiftUI)
    func appTone() -> some View { modifier(AppTone()) }
}

private struct AppTone: ViewModifier {
    @AppStorage(Appearance.minimalKey) private var minimal = false
    func body(content: Content) -> some View { content.id(minimal) }
}
