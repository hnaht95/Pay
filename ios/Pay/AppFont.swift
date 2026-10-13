import SwiftUI
import UIKit

/// Phông chữ của app. Đang thử Space Mono (chỉ có hai nét: thường và đậm); tắt `spaceMono` để về phông hệ thống
enum AppFont {
    static let spaceMono = true

    /// Nét Space Mono gần nhất với độ đậm hệ thống: từ semibold trở lên là Bold
    static func name(_ weight: Font.Weight) -> String {
        [.semibold, .bold, .heavy, .black].contains(weight) ? "SpaceMono-Bold" : "SpaceMono-Regular"
    }

    static func ui(size: CGFloat, bold: Bool) -> UIFont {
        UIFont(name: bold ? "SpaceMono-Bold" : "SpaceMono-Regular", size: size) ?? .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
    }

    /// Thanh tiêu đề, nút chọn đoạn… của UIKit (SwiftUI không đặt phông cho các phần này)
    static func applyAppearance() {
        guard spaceMono else { return }
        let nav = UINavigationBar.appearance()
        nav.titleTextAttributes = [.font: ui(size: 17, bold: true)]
        nav.largeTitleTextAttributes = [.font: ui(size: 32, bold: true)]
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: ui(size: 17, bold: false)], for: .normal)
        let seg = UISegmentedControl.appearance()
        seg.setTitleTextAttributes([.font: ui(size: 13, bold: false)], for: .normal)
        seg.setTitleTextAttributes([.font: ui(size: 13, bold: true)], for: .selected)
    }
}

extension Font {
    /// Thay cho Font.system(size:weight:design:) ở mọi chỗ trong app
    static func app(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        guard AppFont.spaceMono else { return .system(size: size, weight: weight, design: design) }
        return .custom(AppFont.name(weight), fixedSize: size)
    }
}
