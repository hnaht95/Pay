import AppIntents
import SwiftUI

@main
struct PayApp: App {
    @StateObject private var store = Store()
    @StateObject private var quick = QuickAction.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .environmentObject(quick)
                // sochipay://scan, sochipay://add từ widget; sochipay:// trơn là quay về từ app ngân hàng, chỉ cần mở app
                .onOpenURL { url in if let k = QuickKind(url: url) { quick.pending = k } }
        }
    }
}

/// Hiện "Quét QR" và "Ghi khoản chi" trong app Phím tắt, Siri và phần chọn Phím tắt cho nút Tác vụ.
struct PayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ScanIntent(), phrases: ["Quét QR bằng \(.applicationName)", "\(.applicationName) quét QR"],
                    shortTitle: "Quét QR", systemImageName: "qrcode.viewfinder")
        AppShortcut(intent: AddIntent(), phrases: ["Ghi chi tiêu bằng \(.applicationName)", "\(.applicationName) ghi khoản chi"],
                    shortTitle: "Ghi khoản chi", systemImageName: "plus")
    }
}
