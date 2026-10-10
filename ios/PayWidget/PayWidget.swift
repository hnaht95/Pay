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
    // Màu pastel, cùng bộ màu nhạt của danh mục trong app
    case pOrange, pGreen, pTeal, pBlue, pPurple, pRed, pYellow, pGray

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Màu"
    static let caseDisplayRepresentations: [WidgetTone: DisplayRepresentation] = [
        .green: "Xanh lá", .black: "Đen", .white: "Trắng", .orange: "Cam", .yellow: "Vàng",
        .cream: "Kem", .mint: "Xanh nhạt", .forest: "Xanh lá đậm", .pink: "Hồng",
        .pOrange: "Pastel cam", .pGreen: "Pastel xanh lá", .pTeal: "Pastel xanh ngọc", .pBlue: "Pastel xanh dương",
        .pPurple: "Pastel tím", .pRed: "Pastel hồng", .pYellow: "Pastel vàng", .pGray: "Pastel xám",
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
        case .pOrange: 0xFFE1B3
        case .pGreen: 0xD6F5C9
        case .pTeal: 0xC8F0F0
        case .pBlue: 0xD7E0FF
        case .pPurple: 0xF3D6FF
        case .pRed: 0xFFD6D6
        case .pYellow: 0xFFF2B8
        case .pGray: 0xE4E4E8
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
                QuickButtons(tone: e.tone).frame(width: 118)
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
                InkBar(ratio: b.ratio, ink: ink).padding(.top, 3)
            } else {
                Text(L("Tháng %ld: %@đ", Calendar.current.component(.month, from: e.date), fmt(e.s.month)))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
        }
    }
}

/// Thanh ngân sách trên nền màu: màu mực thay cho xanh / cam / đỏ (dòng chữ phía trên đã nói còn hay vượt)
private struct InkBar: View {
    let ratio: Double
    let ink: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(ink.opacity(0.16))
                Capsule().fill(ink).frame(width: max(5, g.size.width * min(ratio, 1)))
            }
        }
        .frame(height: 5)
    }
}

/// Ba nút vào nhanh của widget cỡ vừa: Quét QR (nút chính), dưới là Nói để ghi và Nhập
private struct QuickButtons: View {
    let tone: WidgetTone

    var body: some View {
        VStack(spacing: 8) {
            Link(destination: QuickKind.scan.url) {
                Label(L("Quét QR"), systemImage: "qrcode.viewfinder")
                    .font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(tone.onInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(tone.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            HStack(spacing: 8) {
                icon("mic.fill", .voice, L("Nói để ghi"))
                icon("plus", .add, L("Nhập"))
            }
        }
    }

    private func icon(_ name: String, _ k: QuickKind, _ label: String) -> some View {
        Link(destination: k.url) {
            Image(systemName: name)
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(tone.ink.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(tone.ink)
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
    var tone: WidgetTone = .green
    /// Số đã chi (cỡ vừa hiện cạnh mã QR)
    var s = Summary(today: 0, month: 0, count: 0, day: Date())
}

struct MyQRProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MyQREntry {
        MyQREntry(date: Date(), qr: MyQR(bin: "970416", bank: "ACB", acct: "123456789", name: "NGUYEN VAN A"),
                  s: Summary(today: 125_000, month: 3_450_000, count: 3, day: Date(), budget: 8_000_000))
    }
    func snapshot(for look: WidgetLook, in context: Context) async -> MyQREntry {
        let q = MyQR.load()
        var e = context.isPreview && !q.ready ? placeholder(in: context) : MyQREntry(date: Date(), qr: q, s: Summary.load().at(Date()))
        e.tone = look.tone
        return e
    }
    /// Như widget Chi tiêu hôm nay: app ghi số mới là vẽ lại, thêm một mốc lúc nửa đêm để "hôm nay" tự về 0
    func timeline(for look: WidgetLook, in context: Context) async -> Timeline<MyQREntry> {
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

struct MyQRView: View {
    let e: MyQREntry
    @Environment(\.widgetFamily) private var family
    /// Cùng bộ màu với các widget khác của Pay (mặc định thẻ xanh lá, đổi được trong Sửa tiện ích)
    private var ink: Color { e.tone.ink }
    private var soft: Color { e.tone.ink.opacity(0.62) }

    var body: some View {
        content.containerBackground(for: .widget) { e.tone.bg }
    }

    /// Bốn số cuối của tài khoản, đủ để nhận ra mà không phơi cả số ra màn hình chính
    private var tail: String { e.qr.acct.count > 4 ? "••" + e.qr.acct.suffix(4) : e.qr.acct }

    /// Mã QR không nền, vẽ thẳng lên nền widget: ô màu đen trên nền sáng, màu trắng trên nền tối
    private var code: some View { MyQRCode(qr: e.qr, ink: e.tone.dark ? .white : .black) }

    private func quick(_ icon: String, _ k: QuickKind, _ label: String, primary: Bool = false) -> some View {
        Link(destination: k.url) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(primary ? e.tone.onInk : ink)
                .background(primary ? ink : ink.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel(label)
    }

    @ViewBuilder private var content: some View {
        if !e.qr.ready {
            VStack(spacing: 8) {
                Image(systemName: "qrcode").font(.system(size: 34, weight: .semibold)).foregroundStyle(ink)
                Text(L("Mở Pay > Cài đặt để thêm tài khoản nhận tiền"))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(soft)
                    .multilineTextAlignment(.center).minimumScaleFactor(0.8)
            }
        } else if family == .systemMedium {
            // Cỡ vừa: mã QR nhận tiền bên trái; bên phải là số đã chi hôm nay, dưới là ba nút vào nhanh trên một hàng
            HStack(spacing: 14) {
                code
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Hôm nay đã chi")).font(.system(size: 13, weight: .medium)).foregroundStyle(soft).lineLimit(1)
                    Text(fmt(e.s.today)).font(.system(size: 28, weight: .bold)).kerning(-1).foregroundStyle(ink)
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text(e.s.budgetStatus.map(\.label)
                         ?? L("Tháng %ld: %@đ", Calendar.current.component(.month, from: e.date), fmt(e.s.month)))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(ink).minimumScaleFactor(0.7).lineLimit(1)
                    if let b = e.s.budgetStatus { InkBar(ratio: b.ratio, ink: ink).padding(.top, 3) }
                    Spacer(minLength: 6)
                    HStack(spacing: 6) {
                        quick("qrcode.viewfinder", .scan, L("Quét QR"), primary: true)
                        quick("mic.fill", .voice, L("Nói để ghi"))
                        quick("plus", .add, L("Nhập"))
                    }
                    .frame(height: 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: family == .systemLarge ? 10 : 5) {
                code
                Text(e.qr.bank.isEmpty ? tail : e.qr.bank + " · " + tail)
                    .font(.system(size: family == .systemLarge ? 15 : 11, weight: .semibold)).foregroundStyle(ink)
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
