import AppIntents
import SwiftUI
import WidgetKit

@main
struct PayWidgets: WidgetBundle {
    var body: some Widget {
        SpendWidget()
        VoiceWidget()
        MyQRWidget()
        if #available(iOS 18.0, *) {
            VoiceControl()
            ScanControl()
        }
    }
}

// MARK: Widget màn hình chính + màn hình khoá

struct SpendEntry: TimelineEntry {
    let date: Date
    let s: Summary
    var tone: WidgetTone = .green
}

/// Màu nền của widget, người dùng chọn khi nhấn giữ widget > Sửa tiện ích. Mỗi widget đặt màu riêng được.
enum WidgetTone: String, AppEnum {
    case green, black, white, orange, yellow, cream, mint, forest, pink

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Màu"
    static let caseDisplayRepresentations: [WidgetTone: DisplayRepresentation] = [
        .green: "Xanh lá", .black: "Đen", .white: "Trắng", .orange: "Cam", .yellow: "Vàng",
        .cream: "Kem", .mint: "Xanh nhạt", .forest: "Xanh lá đậm", .pink: "Hồng",
    ]

    private var hex: UInt32 {
        switch self {
        case .green: 0x61BE6E
        case .black: 0x141414
        case .white: 0xFFFFFF
        case .orange: 0xF5491C
        case .yellow: 0xEEAC27
        case .cream: 0xF4EDE1
        case .mint: 0xADD3D4
        case .forest: 0x134128
        case .pink: 0xFBC1A9
        }
    }
    /// Nền tối: chữ và nút chuyển sang trắng
    var dark: Bool { self == .black || self == .forest }
    var bg: Color { Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255) }
    /// Màu chữ, biểu tượng và nền nút chính
    var ink: Color { dark ? .white : Color(red: 0x0E / 255, green: 0x14 / 255, blue: 0x10 / 255) }
    /// Màu chữ đặt trên nút chính
    var onInk: Color { dark ? Color(red: 0x0E / 255, green: 0x14 / 255, blue: 0x10 / 255) : .white }
}

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
        var e = context.isPreview ? placeholder(in: context) : SpendEntry(date: Date(), s: Summary.load().at(Date()))
        e.tone = look.tone
        return e
    }

    /// App ghi số liệu mới là widget vẽ lại; thêm một mốc lúc nửa đêm để "hôm nay" tự về 0.
    func timeline(for look: WidgetLook, in context: Context) async -> Timeline<SpendEntry> {
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

/// Hai chi tiết của icon app: chấm tròn ở góc trái, sóng "chạm để trả" ở góc phải
private struct CardMarks: View {
    let ink: Color
    var body: some View {
        HStack {
            Circle().fill(ink).frame(width: 11, height: 11)
            Spacer()
            Image(systemName: "wave.3.right").font(.system(size: 15, weight: .bold)).foregroundStyle(ink)
        }
        .accessibilityHidden(true)
    }
}

struct SpendView: View {
    let e: SpendEntry
    @Environment(\.widgetFamily) private var family
    /// Màu theo lựa chọn của người dùng cho widget này (mặc định thẻ xanh lá như icon app)
    private var card: Color { e.tone.bg }
    private var ink: Color { e.tone.ink }
    private var soft: Color { e.tone.ink.opacity(0.62) }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if family == .systemSmall || family == .systemMedium { card } else { Color.clear }
            }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Circle().fill(ink).frame(width: 11, height: 11).accessibilityHidden(true)
                    Spacer(minLength: 6)
                    totals
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                VStack(spacing: 8) {
                    Link(destination: QuickKind.scan.url) {
                        Label(L("Quét QR"), systemImage: "qrcode.viewfinder")
                            .font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(e.tone.onInk)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    HStack(spacing: 8) {
                        iconAction("mic.fill", .voice, L("Nói để ghi"))
                        iconAction("plus", .add, L("Nhập"))
                    }
                }
                .frame(width: 118)
            }
        case .accessoryCircular:
            // Có ngân sách: vòng tròn đầy dần theo phần đã tiêu trong tháng, giữa là biểu tượng quét
            if let b = e.s.budgetStatus {
                Gauge(value: min(b.ratio, 1)) { Image(systemName: "qrcode.viewfinder").font(.system(size: 17, weight: .semibold)) }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .widgetURL(QuickKind.scan.url)
                    .accessibilityLabel(L("Quét QR"))
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "qrcode.viewfinder").font(.system(size: 24, weight: .semibold))
                }
                .widgetURL(QuickKind.scan.url)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Hôm nay đã chi")).font(.system(size: 12, weight: .medium)).opacity(0.75).lineLimit(1)
                Text(fmt(e.s.today)).font(.system(size: 24, weight: .bold)).kerning(-0.5).minimumScaleFactor(0.6).lineLimit(1)
                if let b = e.s.budgetStatus {
                    // Thanh ngân sách tháng: phần đã tiêu
                    Gauge(value: min(b.ratio, 1)) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                        .accessibilityLabel(b.label)
                } else {
                    Text(L("Tháng: %@đ", fmt(e.s.month))).font(.system(size: 12)).opacity(0.75).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(QuickKind.scan.url)
        case .accessoryInline:
            Label(L("Hôm nay %@đ", fmt(e.s.today)), systemImage: "creditcard.fill").widgetURL(QuickKind.scan.url)
        default:   // nhỏ: chạm vào là quét QR luôn
            VStack(alignment: .leading, spacing: 0) {
                CardMarks(ink: ink)
                Spacer(minLength: 6)
                totals
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(QuickKind.scan.url)
        }
    }

    /// Số đã chi hôm nay, dưới là ngân sách còn lại (kèm thanh) hoặc tổng tháng
    private var totals: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L("Hôm nay đã chi")).font(.system(size: 13, weight: .medium)).foregroundStyle(soft).lineLimit(1)
            Text(fmt(e.s.today)).font(.system(size: 32, weight: .bold)).kerning(-1).foregroundStyle(ink)
                .minimumScaleFactor(0.5).lineLimit(1)
            if let b = e.s.budgetStatus {
                Text(b.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
                    .minimumScaleFactor(0.7).lineLimit(1)
                // Trên nền màu: thanh màu mực thay cho xanh / cam / đỏ (chữ ở trên đã nói còn hay vượt)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(ink.opacity(0.16))
                        Capsule().fill(ink).frame(width: max(5, g.size.width * min(b.ratio, 1)))
                    }
                }
                .frame(height: 5).padding(.top, 3)
            } else {
                Text(L("Tháng %ld: %@đ", Calendar.current.component(.month, from: e.date), fmt(e.s.month)))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
        }
    }

    private func iconAction(_ icon: String, _ k: QuickKind, _ label: String) -> some View {
        Link(destination: k.url) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ink.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(ink)
        }
        .accessibilityLabel(label)
    }
}

// MARK: Nút micro: chạm là mở Pay và nghe luôn (màn hình chính + màn hình khoá)

struct VoiceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "VoiceWidget", intent: WidgetLook.self, provider: SpendProvider()) { VoiceView(e: $0) }
            .configurationDisplayName(L("Nói để ghi"))
            .description(L("Chạm là Pay nghe luôn, nói \"35k cafe\" là ghi."))
            .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct VoiceView: View {
    let e: SpendEntry
    @Environment(\.widgetFamily) private var family
    /// Màu theo lựa chọn của người dùng cho widget này (mặc định thẻ xanh lá như icon app)
    private var card: Color { e.tone.bg }
    private var ink: Color { e.tone.ink }
    private var soft: Color { e.tone.ink.opacity(0.62) }

    var body: some View {
        content
            .widgetURL(QuickKind.voice.url)
            .containerBackground(for: .widget) {
                if family == .systemSmall { card } else { Color.clear }
            }
    }

    @ViewBuilder private var content: some View {
        if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill").font(.system(size: 24, weight: .semibold))
            }
            .accessibilityLabel(L("Nói để ghi"))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(e.tone.onInk)
                        .frame(width: 58, height: 58)
                        .background(ink, in: Circle())
                    Spacer()
                    Image(systemName: "wave.3.right").font(.system(size: 15, weight: .bold)).foregroundStyle(ink)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 6)
                Text(L("Nói để ghi")).font(.system(size: 19, weight: .bold)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7)
                Text(L("Hôm nay %@đ", fmt(e.s.today)))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(soft)
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: Mã QR nhận tiền của mình: người khác quét là chuyển khoản (tài khoản đặt trong Cài đặt của app)

struct MyQREntry: TimelineEntry {
    let date: Date
    let qr: MyQR
}

struct MyQRProvider: TimelineProvider {
    func placeholder(in context: Context) -> MyQREntry {
        MyQREntry(date: Date(), qr: MyQR(bin: "970416", bank: "ACB", acct: "123456789", name: "NGUYEN VAN A"))
    }
    func getSnapshot(in context: Context, completion: @escaping (MyQREntry) -> Void) {
        let q = MyQR.load()
        completion(context.isPreview && !q.ready ? placeholder(in: context) : MyQREntry(date: Date(), qr: q))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MyQREntry>) -> Void) {
        completion(Timeline(entries: [MyQREntry(date: Date(), qr: MyQR.load())], policy: .never))
    }
}

struct MyQRWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MyQRWidget", provider: MyQRProvider()) { MyQRView(e: $0) }
            .configurationDisplayName(L("Mã QR nhận tiền"))
            .description(L("Mã VietQR của bạn ngay trên màn hình chính, người khác quét là chuyển khoản."))
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct MyQRView: View {
    let e: MyQREntry
    @Environment(\.widgetFamily) private var family
    private let ink = Color(red: 0x0E / 255, green: 0x14 / 255, blue: 0x10 / 255)

    var body: some View {
        // Nền trắng ở cả nền sáng lẫn nền tối: mã QR cần nền trắng để máy quét đọc được
        content.containerBackground(for: .widget) { Color.white }
    }

    /// Bốn số cuối của tài khoản, đủ để nhận ra mà không phơi cả số ra màn hình chính
    private var tail: String { e.qr.acct.count > 4 ? "••" + e.qr.acct.suffix(4) : e.qr.acct }

    @ViewBuilder private var content: some View {
        if !e.qr.ready {
            VStack(spacing: 8) {
                Image(systemName: "qrcode").font(.system(size: 34, weight: .semibold)).foregroundStyle(ink)
                Text(L("Mở Pay > Cài đặt để thêm tài khoản nhận tiền"))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(ink.opacity(0.62))
                    .multilineTextAlignment(.center).minimumScaleFactor(0.8)
            }
        } else if family == .systemMedium {
            HStack(spacing: 16) {
                MyQRCode(qr: e.qr)
                VStack(alignment: .leading, spacing: 3) {
                    Circle().fill(ink).frame(width: 11, height: 11).accessibilityHidden(true)
                    Spacer(minLength: 4)
                    Text(L("Quét để chuyển cho")).font(.system(size: 13, weight: .medium)).foregroundStyle(ink.opacity(0.62)).lineLimit(1)
                    if !e.qr.name.isEmpty {
                        Text(e.qr.name).font(.system(size: 17, weight: .bold)).foregroundStyle(ink).lineLimit(2).minimumScaleFactor(0.7)
                    }
                    Text(e.qr.bank).font(.system(size: 14, weight: .semibold)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7)
                    Text(e.qr.acct).font(.system(size: 14, weight: .medium).monospacedDigit()).foregroundStyle(ink.opacity(0.62)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: family == .systemLarge ? 10 : 4) {
                MyQRCode(qr: e.qr)
                Text(e.qr.bank.isEmpty ? tail : e.qr.bank + " · " + tail)
                    .font(.system(size: family == .systemLarge ? 15 : 11, weight: .semibold)).foregroundStyle(ink.opacity(0.7))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
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
        .displayName("\(L("Pay: Ghi bằng giọng nói"))")
        .description("\(L("Mở Pay và nghe luôn, nói \"35k cafe\" là ghi."))")
    }
}

@available(iOS 18.0, *)
struct ScanControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ScanControl") {
            ControlWidgetButton(action: ScanIntent()) {
                Label(L("Quét QR"), systemImage: "qrcode.viewfinder")
            }
        }
        .displayName("\(L("Pay: Quét QR"))")
        .description("\(L("Mở Pay và quét mã QR thanh toán."))")
    }
}
