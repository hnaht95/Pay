import SwiftUI

/// Giao diện chọn trong Cài đặt: theo máy, luôn sáng, luôn tối
enum Appearance: String, CaseIterable {
    case system, light, dark
    static let key = "appearance"
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
