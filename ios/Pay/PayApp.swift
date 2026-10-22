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
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Lệnh Chụp hoá đơn (nút Tác vụ, Phím tắt): bật camera ngay lúc lệnh tới, song song với lúc dựng giao diện
        QuickAction.onPhoto = { if Pro.shared.active { ReceiptCam.warmStart() } }
        // Khoá Face ID: mở app là khoá luôn (cửa sổ khoá dựng sau khi có màn hình)
        DispatchQueue.main.async { AppLock.shared.launch() }
    }

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
                .onOpenURL { url in
                    if let c = House.code(in: url.absoluteString) { quick.joinCode = c }   // camera iPhone quét mã nhóm
                    else if let k = QuickKind(url: url) { quick.pending = k }
                }
                // Quay lại app: đọc lại quyền Pro (gói năm hết hạn khi app nằm nền nhiều ngày không chắc có Transaction.updates)
                // Chỉ khi đang có Pro (để biết gói năm vừa hết hạn), mỗi giờ nhiều nhất một lần: đọc quyền mua mỗi lần quay lại app thì
                // trên TestFlight iOS hay hỏi mật khẩu Tài khoản Apple. Chưa có Pro thì không cần: mua xong Transaction.updates báo về
                .onChange(of: scenePhase) { _, p in AppLock.shared.phaseChanged(p) }
                .onChange(of: scenePhase) { _, p in
                    guard p == .active, Pro.shared.active else { return }
                    let last = UserDefaults.standard.double(forKey: "proChecked"), now = Date().timeIntervalSince1970
                    guard now - last > 3600 else { return }
                    UserDefaults.standard.set(now, forKey: "proChecked")
                    Task { await Pro.shared.refresh() }
                }
                .task {
                    Appearance.apply()
                    #if DEBUG
                    FilmTouches.install()
                    await FilmExport.runIfAsked(store: store, quick: quick)
                    SelfTest.runIfAsked(store: store)
                    // "-bankClaimTest <link dl.vietqr.io>": chạy trang trong khung web, in ra link app ngân hàng bắt được
                    if let t = UserDefaults.standard.string(forKey: "bankClaimTest"), let u = URL(string: t) {
                        try? await Task.sleep(for: .seconds(1))
                        let link = await BankWebClaim.run(u, timeout: 8)
                        print("BANKCLAIM", link?.absoluteString ?? "nil")
                        try? (link?.absoluteString ?? "nil").write(to: URL.documentsDirectory.appending(path: "bankclaim.txt"), atomically: true, encoding: .utf8)
                    }
                    #endif
                    // Kiểm tra quyền Pro và lắng nghe giao dịch (mua trên máy khác, gia hạn, hoàn tiền)
                    await Pro.shared.refresh()
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
        AppShortcut(intent: PhotoIntent(), phrases: ["Chụp hoá đơn bằng \(.applicationName)", "\(.applicationName) chụp hoá đơn"],
                    shortTitle: "Chụp hoá đơn", systemImageName: "camera.fill")
        AppShortcut(intent: CardPaymentIntent(), phrases: ["Ghi giao dịch thẻ bằng \(.applicationName)"],
                    shortTitle: "Ghi giao dịch thẻ", systemImageName: "creditcard")
        AppShortcut(intent: AddIntent(), phrases: ["Nhập chi tiêu bằng \(.applicationName)", "\(.applicationName) nhập khoản chi"],
                    shortTitle: "Nhập khoản chi", systemImageName: "plus")
    }
}

/// Tự ghi khi trả bằng Apple Pay: trong app Phím tắt > Tự động hoá > Giao dịch (Ví), chọn thẻ, thêm tác vụ "Ghi giao dịch thẻ"
/// của Pay rồi gán Số tiền và Người bán của giao dịch vào hai ô. Mỗi lần quẹt thẻ là có một khoản chi, không phải mở app.
/// Số tiền âm / có chữ hoàn tiền thì ghi khoản thu "Được chuyển". Tự động hoá chạy hai lần cho một giao dịch thì chỉ ghi một.
struct CardPaymentIntent: AppIntent {
    static let title: LocalizedStringResource = "Ghi giao dịch thẻ"
    static let description = IntentDescription("Ghi một khoản chi từ giao dịch thẻ trong Ví; số tiền âm hoặc hoàn tiền thì ghi khoản thu. Dùng trong Tự động hoá > Giao dịch: gán Số tiền và Người bán của giao dịch.")
    static let openAppWhenRun = false
    // Lưu ý: mô tả của App Intent không được chứa chữ "Apple" (App Store Connect trả về ITMS-90626)

    /// Nhận dạng chữ để chịu được mọi kiểu Phím tắt đưa vào: "₫35.000", "35,000.00 VND", "35000", "-35.000", "(35.000 ₫)"
    @Parameter(title: "Số tiền")
    var amount: String

    @Parameter(title: "Người bán")
    var merchant: String?

    /// Mỗi tự động hoá Giao dịch gắn với một thẻ trong Ví: thẻ tín dụng thì bật để khoản tự ghi chưa trừ vào số dư
    @Parameter(title: "Thẻ tín dụng", default: false)
    var credit: Bool

    /// Không bắt buộc: gán tên / loại giao dịch nếu có, chứa "Refund" / "Hoàn tiền" thì ghi là hoàn tiền
    @Parameter(title: "Loại giao dịch")
    var kind: String?

    /// Mã khoản tự ghi bắt đầu bằng chữ này để nhận ra khi chống ghi trùng
    static let idPrefix = "wallet-"
    /// Tự động hoá chạy lại cho cùng giao dịch trong khoảng này (ms) thì bỏ qua
    static let dupWindow: Double = 3 * 60 * 1000
    /// Danh mục khoản thu cho tiền hoàn (từ khoá "hoan tien", "refund" nằm ở đây)
    static let refundCat = "in-nhan"

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Tính năng Pro (đọc cờ đã lưu: intent chạy nền, không chờ App Store)
        guard UserDefaults.standard.bool(forKey: "proActive") else {
            return .result(dialog: IntentDialog(stringLiteral: L("Tự ghi giao dịch thẻ cần Payso Pro. Mở Payso để nâng cấp.")))
        }
        guard let signed = Self.parse(amount), signed != 0 else {
            return .result(dialog: IntentDialog(stringLiteral: L("Không đọc được số tiền của giao dịch.")))
        }
        let a = abs(signed)
        let store = Store.shared
        let shop = (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let refund = signed < 0 || Self.isRefund(shop) || Self.isRefund(kind ?? "")
        let name = shop.isEmpty ? L("giao dịch thẻ") : shop
        // Hoàn tiền: khoản thu, ghi chú "Hoàn tiền · <người bán>"; tên người bán đã có chữ hoàn tiền thì giữ nguyên
        let note = refund ? (shop.isEmpty ? L("Hoàn tiền") : Self.isRefund(shop) ? shop : L("Hoàn tiền") + " · " + shop) : shop
        // Giao dịch thẻ thường luôn là khoản chi: không đoán theo từ khoá tiền vào (tên cửa hàng "Phở Lương Sơn", "Gift Shop" từng
        // thành khoản thu, số dư tăng thay vì giảm)
        let cat = refund ? Self.refundCat : store.guessCategory(shop)
        let now = Date().timeIntervalSince1970 * 1000
        let key = note.lowercased()
        if store.all.contains(where: { $0.id.hasPrefix(Self.idPrefix) && $0.a == a && $0.isIncome == refund
            && ($0.n ?? "").lowercased() == key && abs(now - $0.t) < Self.dupWindow }) {
            return .result(dialog: IntentDialog(stringLiteral: refund ? L("Đã ghi hoàn tiền %@ %@ rồi, không ghi lại.", fmt(a), name)
                                                                      : L("Đã ghi %@ %@ rồi, không ghi lại.", fmt(a), name)))
        }
        store.add(amount: a, note: note, cat: cat, credit: credit && !refund, toast: false, idPrefix: Self.idPrefix)
        return .result(dialog: IntentDialog(stringLiteral: refund ? L("Đã ghi hoàn tiền %@ từ %@.", fmt(a), name)
                                                                  : L("Đã ghi %@ %@.", fmt(a), name)))
    }

    /// Chữ cho biết giao dịch là hoàn tiền: "Refund", "Hoàn tiền", "Hoàn trả", hoặc chỉ "Hoàn". "Hoàn Kiếm Coffee" không tính
    static func isRefund(_ s: String) -> Bool {
        let t = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi"))
            .replacingOccurrences(of: "đ", with: "d").trimmingCharacters(in: .whitespacesAndNewlines)
        if t == "hoan" || t == "refund" || t == "return" { return true }
        return ["refund", "hoan tien", "hoan tra", "tien hoan"].contains { t.contains($0) }
    }

    /// Số tiền có dấu (âm là tiền trả lại). Dấu "-" / "−" hoặc cặp ngoặc "(…)" là số âm. Bỏ ký hiệu tiền và chữ ("₫", "VND"),
    /// khoảng trắng; phần lẻ sau dấu thập phân (",00" / ".50" ở cuối) bỏ đi; còn lại ghép các chữ số (dấu nghìn . , đều bỏ)
    static func parse(_ s: String) -> Int? {
        let negative = s.contains("-") || s.contains("\u{2212}") || (s.contains("(") && s.contains(")"))
        var t = s.filter { $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }
        if let r = t.range(of: #"[.,]\d{1,2}$"#, options: .regularExpression) { t.removeSubrange(r) }
        let digits = t.filter(\.isNumber)
        guard !digits.isEmpty, digits.count <= 12, let v = Int(digits) else { return nil }
        return negative ? -v : v
    }
}

/// Nói một câu là ghi luôn, không mở app: "Ghi chi tiêu bằng Payso" -> Siri hỏi -> "35k cafe".
/// Gán vào nút Tác vụ: Cài đặt > Nút Tác vụ > Phím tắt > Pay > Ghi chi tiêu.
struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Ghi chi tiêu"
    static let description = IntentDescription("Ghi nhanh một khoản chi bằng giọng nói hoặc gõ, ví dụ \"35k cafe\", không cần mở app.")

    @Parameter(title: "Khoản chi", requestValueDialog: IntentDialog("Chi gì, bao nhiêu? Ví dụ: 35k cafe"))
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store.shared
        // Câu có nhắc tên nhóm ("ăn lẩu nhóm Tùng của 500k, Hạnh trả"): ghi vào Nhóm chung như ở thẻ nói để ghi
        let house = House.shared
        if let hit = house.groupMentioned(in: text) {
            let sale = House.speechDiscount(hit.rest)
            let roles = House.speechRoles(sale.rest, in: hit.group)
            if let q = QuickParse.spoken(roles.rest) ?? QuickParse.expense(roles.rest) {
                guard let msg = await house.voiceSpend(in: hit.group, amount: q.amount, note: q.note, payer: roles.payer, shares: roles.shares, discount: sale.discount) else {
                    return .result(dialog: IntentDialog(stringLiteral: L("Chưa ghi được vào %@. Mở Payso để thử lại.", hit.group.name)))
                }
                return .result(dialog: IntentDialog(stringLiteral: msg.text + "."))
            }
        }
        // Câu trả lời ghép lúc chạy nên đi qua L() được (tiêu đề và câu hỏi ở trên là chữ tĩnh của hệ thống, giữ tiếng Việt):
        // từng câu trọn vẹn một khoá, không ghép nửa Việt nửa Anh với tên danh mục / nhãn ngân sách đã dịch
        guard let e = store.quickAdd(text, spoken: true) else {
            throw $text.needsValueError(IntentDialog(stringLiteral: L("Chưa nghe rõ số tiền. Nói lại, ví dụ: 35k cafe")))
        }
        var reply = L("Đã ghi %@ %@.", fmt(e.a), Category.get(e.c).name)
        if let b = store.budgetStatus() { reply += " " + L("%@ trong tháng.", b.label) }
        else { reply += " " + L("Hôm nay đã chi %@.", fmt(store.total(on: Date()))) }
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}
