import AppIntents
import SwiftUI
import WidgetKit

@main
struct PayWidgets: WidgetBundle {
    var body: some Widget {
        SpendWidget()
        VoiceWidget()
        QuickLockWidget()
        MyQRWidget()
        if #available(iOS 18.0, *) {
            VoiceControl()
            ScanControl()
            PhotoControl()
        }
    }
}

// MARK: Widget màn hình chính + màn hình khoá

struct WidgetLook: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Màu widget"
    static let description = IntentDescription("Chọn màu nền cho widget này.")

    @Parameter(title: "Màu", default: .green) var tone: WidgetTone
}

struct SpendProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SpendEntry {
        SpendEntry(date: Date(), s: Summary(today: 125_000, month: 3_450_000, count: 3, day: Date(), budget: 8_000_000))
    }

    func snapshot(for look: WidgetLook, in context: Context) async -> SpendEntry {
        // Tiến trình widget sống qua nhiều lần vẽ lại: đọc lại ngôn ngữ vừa đổi trong app trước khi dựng hình
        Lang.reload()
        var e = context.isPreview ? placeholder(in: context) : SpendEntry(date: Date(), s: Summary.load().at(Date()))
        e.tone = look.tone
        return e
    }

    /// App ghi số liệu mới là widget vẽ lại; thêm một mốc lúc nửa đêm để "hôm nay" tự về 0.
    func timeline(for look: WidgetLook, in context: Context) async -> Timeline<SpendEntry> {
        Lang.reload()
        let now = Date()
        let s = Summary.load()
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        let entries = [SpendEntry(date: now, s: s.at(now), tone: look.tone), SpendEntry(date: midnight, s: s.at(midnight), tone: look.tone)]
        return Timeline(entries: entries, policy: .after(midnight))
    }
}

struct SpendWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SpendWidget", intent: WidgetLook.self, provider: SpendProvider()) { SpendView(e: $0) }
            .configurationDisplayName(L("Chi tiêu hôm nay"))
            .description(L("Xem nhanh số đã chi, chạm để quét QR, nói hoặc nhập khoản mới."))
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: Nút micro: chạm là mở Pay và nghe luôn (màn hình chính + màn hình khoá)

struct VoiceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "VoiceWidget", intent: WidgetLook.self, provider: SpendProvider()) { VoiceView(e: $0) }
            .configurationDisplayName(L("Nói để ghi"))
            .description(L("Chạm là Payso nghe luôn, nói \"35k cafe\" là ghi."))
            .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

// MARK: Nút nhanh màn hình khoá: Quét QR, nói, chụp hoá đơn trong một khung chữ nhật

struct QuickLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickLockWidget", provider: QuickLockProvider()) { _ in QuickLockView() }
            .configurationDisplayName(L("Nút nhanh"))
            .description(L("Quét QR, nói để ghi, chụp hoá đơn ngay từ màn hình khoá."))
            .supportedFamilies([.accessoryRectangular])
    }
}

struct QuickLockProvider: TimelineProvider {
    struct Entry: TimelineEntry { let date: Date }
    func placeholder(in context: Context) -> Entry { Entry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: Date())], policy: .never))
    }
}

// MARK: Mã QR nhận tiền của mình: người khác quét là chuyển khoản (tài khoản đặt trong Cài đặt của app)

struct MyQRProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MyQREntry {
        MyQREntry(date: Date(), qr: MyQR(bin: "970416", bank: "ACB", acct: "123456789", name: "NGUYEN VAN A"),
                  s: Summary(today: 125_000, month: 3_450_000, count: 3, day: Date(), budget: 8_000_000))
    }
    func snapshot(for look: WidgetLook, in context: Context) async -> MyQREntry {
        Lang.reload()
        let q = MyQR.load()
        var e = context.isPreview && !q.ready ? placeholder(in: context) : MyQREntry(date: Date(), qr: q, s: Summary.load().at(Date()))
        e.tone = look.tone
        return e
    }
    /// Như widget Chi tiêu hôm nay: app ghi số mới là vẽ lại, thêm một mốc lúc nửa đêm để "hôm nay" tự về 0
    func timeline(for look: WidgetLook, in context: Context) async -> Timeline<MyQREntry> {
        Lang.reload()
        let now = Date(), q = MyQR.load(), s = Summary.load()
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        return Timeline(entries: [MyQREntry(date: now, qr: q, tone: look.tone, s: s.at(now)),
                                  MyQREntry(date: midnight, qr: q, tone: look.tone, s: s.at(midnight))], policy: .after(midnight))
    }
}

struct MyQRWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MyQRWidget", intent: WidgetLook.self, provider: MyQRProvider()) { MyQRView(e: $0) }
            .configurationDisplayName(L("Mã QR nhận tiền"))
            .description(L("Mã VietQR của bạn ngay trên màn hình chính, người khác quét là chuyển khoản."))
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: Nút trong Trung tâm điều khiển — gán được cho nút Tác vụ (iOS 18+)

@available(iOS 18.0, *)
struct VoiceControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "VoiceControl") {
            ControlWidgetButton(action: VoiceIntent()) {
                Label(L("Ghi bằng giọng nói"), systemImage: "mic.fill")
            }
        }
        .displayName("\(L("Payso: Ghi bằng giọng nói"))")
        .description("\(L("Mở Payso và nghe luôn, nói \"35k cafe\" là ghi."))")
    }
}

@available(iOS 18.0, *)
struct PhotoControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "PhotoControl") {
            ControlWidgetButton(action: PhotoIntent()) {
                Label(L("Chụp hoá đơn"), systemImage: "camera.fill")
            }
        }
        .displayName("\(L("Payso: Chụp hoá đơn"))")
        .description("\(L("Mở Payso và chụp ngay ảnh hoá đơn."))")
    }
}

@available(iOS 18.0, *)
struct ScanControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ScanControl") {
            ControlWidgetButton(action: ScanIntent()) {
                Label(L("Quét QR"), systemImage: "qrcode")
            }
        }
        .displayName("\(L("Payso: Quét QR"))")
        .description("\(L("Mở Payso và quét mã QR thanh toán."))")
    }
}
