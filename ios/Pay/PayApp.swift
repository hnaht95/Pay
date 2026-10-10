import AppIntents
import SwiftUI
import WidgetKit

@main
struct PayApp: App {
    @StateObject private var store = Store.shared
    @StateObject private var quick = QuickAction.shared
    /// Nhận lời mời vào Nhà chung (iOS gọi qua scene delegate)
    @UIApplicationDelegateAdaptor(PayAppDelegate.self) private var appDelegate
    /// Đổi ngôn ngữ trong Cài đặt: dựng lại toàn bộ giao diện bằng ngôn ngữ mới, widget vẽ lại theo
    @State private var lang = Lang.current

    var body: some Scene {
        WindowGroup {
            HomeView()
                .id(lang)
                .environment(\.locale, Lang.locale)
                .onReceive(NotificationCenter.default.publisher(for: Lang.changed)) { _ in
                    lang = Lang.current
                    WidgetCenter.shared.reloadAllTimelines()
                }
                .environmentObject(store)
                .environmentObject(quick)
                // sochipay://scan, sochipay://add từ widget; sochipay:// trơn là quay về từ app ngân hàng, chỉ cần mở app
                .onOpenURL { url in if let k = QuickKind(url: url) { quick.pending = k } }
                .task {
                    #if DEBUG
                    FilmTouches.install()
                    await FilmExport.runIfAsked(store: store, quick: quick)
                    #endif
                    // Tải trước sổ Nhóm chung ngay khi mở app, để lúc bấm vào đã có sẵn (không hỏi quyền thông báo ở đây)
                    await House.shared.load(prompt: false)
                }
                #if DEBUG
                // "-filmVoiceOnWake YES": app được gọi lên lại (vd từ màn hình khoá) thì mở luôn "nói để ghi", như bấm nút Tác vụ —
                // để quay phim giới thiệu với hiệu ứng mở khoá thật của iOS
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    if UserDefaults.standard.bool(forKey: "filmVoiceOnWake") { quick.pending = .voice }
                }
                #endif
        }
    }
}

/// Hiện "Quét QR" và "Ghi khoản chi" trong app Phím tắt, Siri và phần chọn Phím tắt cho nút Tác vụ.
struct PayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: VoiceIntent(), phrases: ["Nói để ghi bằng \(.applicationName)", "\(.applicationName) nghe ghi chi"],
                    shortTitle: "Ghi bằng giọng nói", systemImageName: "mic.fill")
        AppShortcut(intent: LogExpenseIntent(), phrases: ["Ghi chi tiêu bằng \(.applicationName)", "\(.applicationName) ghi chi tiêu", "Ghi \(.applicationName)"],
                    shortTitle: "Ghi chi tiêu", systemImageName: "mic.fill")
        AppShortcut(intent: ScanIntent(), phrases: ["Quét QR bằng \(.applicationName)", "\(.applicationName) quét QR"],
                    shortTitle: "Quét QR", systemImageName: "qrcode.viewfinder")
        AppShortcut(intent: AddIntent(), phrases: ["Nhập chi tiêu bằng \(.applicationName)", "\(.applicationName) nhập khoản chi"],
                    shortTitle: "Nhập khoản chi", systemImageName: "plus")
    }
}

/// Nói một câu là ghi luôn, không mở app: "Ghi chi tiêu bằng Pay" -> Siri hỏi -> "35k cafe".
/// Gán vào nút Tác vụ: Cài đặt > Nút Tác vụ > Phím tắt > Pay > Ghi chi tiêu.
struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Ghi chi tiêu"
    static let description = IntentDescription("Ghi nhanh một khoản chi bằng giọng nói hoặc gõ, ví dụ \"35k cafe\", không cần mở app.")

    @Parameter(title: "Khoản chi", requestValueDialog: IntentDialog("Chi gì, bao nhiêu? Ví dụ: 35k cafe"))
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store.shared
        guard let e = store.quickAdd(text, spoken: true) else {
            throw $text.needsValueError(IntentDialog("Chưa nghe rõ số tiền. Nói lại, ví dụ: 35k cafe"))
        }
        var reply = "Đã ghi \(fmt(e.a))đ \(Category.get(e.c).name)."
        if let b = store.budgetStatus() { reply += " \(b.label) trong tháng." }
        else { reply += " Hôm nay đã chi \(fmt(store.total(on: Date())))đ." }
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}
