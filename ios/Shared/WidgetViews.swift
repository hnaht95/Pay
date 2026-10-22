import AppIntents
import SwiftUI
import WidgetKit

// Hình của các widget. Nằm ở Shared để app cũng vẽ được (phim giới thiệu "Widget" trên web dựng từ chính các hình này);
// phần khai báo widget, nguồn dữ liệu thì ở PayWidget.

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

    /// Màu để lấy mực theo chỗ widget đang được vẽ. iOS gỡ nền widget (StandBy: còn nền đen) hoặc tô lại mọi màu
    /// (màn hình chính kiểu Tinted / Clear, StandBy ban đêm, `mode` khác fullColor) thì mực đen của nền sáng sẽ chìm:
    /// lấy mực trắng của nền tối. Nền thì vẫn đặt theo màu đã chọn, iOS tự bỏ khi cần.
    func inked(_ mode: WidgetRenderingMode, background: Bool) -> WidgetTone { background && mode == .fullColor ? self : .black }
    /// Nền và chữ của nút chính. `flat` (iOS tô lại mọi màu thành một màu, chỉ giữ độ trong): nền mực đặc với chữ onInk
    /// sẽ dính thành một khối, nên nền chuyển sang mực trong, chữ dùng mực
    func plate(_ flat: Bool) -> Color { flat ? ink.opacity(0.3) : ink }
    func onPlate(_ flat: Bool) -> Color { flat ? ink : onInk }
}

/// Hai chi tiết của icon app: chấm tròn ở góc trái, sóng "chạm để trả" ở góc phải
struct CardMarks: View {
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
    /// Cỡ widget. Trong widget thì lấy theo iOS; app dựng phim thì chỉ định
    var size: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { size ?? envFamily }
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.showsWidgetContainerBackground) private var showsBg
    /// Màu theo lựa chọn của người dùng cho widget này (mặc định thẻ xanh lá như icon app)
    private var card: Color { e.tone.bg }
    /// Mực theo chỗ đang vẽ (xem `WidgetTone.inked`); app dựng phim thì tự vẽ nền nên giữ đúng màu đã chọn
    private var tone: WidgetTone { size == nil ? e.tone.inked(mode, background: showsBg) : e.tone }
    private var ink: Color { tone.ink }
    private var soft: Color { tone.ink.opacity(0.62) }

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
                QuickButtons(tone: tone).frame(width: 118)
            }
        case .accessoryCircular:
            // Nút tròn có nền, giữa là biểu tượng mã QR như nút Quét QR trong app (không vòng tiến độ ngân sách), cùng kiểu nút micro
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "qrcode").font(.system(size: 22, weight: .semibold))
            }
            .widgetURL(QuickKind.scan.url)
            .accessibilityLabel(L("Quét QR"))
        case .accessoryRectangular:
            // Một khung gồm cả ba: số đã chi hôm nay bên trái (chạm là mở app), nút Quét QR và nút micro tròn bên phải (nút có tác
            // vụ riêng, iOS 17+). Số tiền vừa phải để còn chỗ cho hai nút; nền mờ cả khung cho chữ không chìm vào ảnh màn hình khoá
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("Hôm nay đã chi")).font(.system(size: 11, weight: .medium)).opacity(0.75).lineLimit(1).minimumScaleFactor(0.8)
                    Text(fmt(e.s.today)).font(.system(size: 18, weight: .bold)).kerning(-0.3).minimumScaleFactor(0.6).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(intent: ScanIntent()) { lockButton("qrcode", size: 15) }
                    .buttonStyle(.plain).accessibilityLabel(L("Quét QR"))
                Button(intent: VoiceIntent()) { lockButton("mic.fill", size: 14) }
                    .buttonStyle(.plain).accessibilityLabel(L("Nói để ghi"))
            }
            .padding(.leading, 10).padding(.trailing, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AccessoryWidgetBackground().clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)) }
            .widgetURL(URL(string: "sochipay://"))   // chạm ngoài hai nút: chỉ mở app
        case .accessoryInline:
            Label(L("Hôm nay %@", fmt(e.s.today)), systemImage: "creditcard.fill").widgetURL(URL(string: "sochipay://"))
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

    /// Nút tròn nhỏ trong khung màn hình khoá (đậm hơn nền khung một chút)
    private func lockButton(_ symbol: String, size: CGFloat) -> some View {
        Image(systemName: symbol).font(.system(size: size, weight: .semibold))
            .frame(width: 34, height: 34)
            .background(Circle().fill(.white.opacity(0.18)))
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
                Text(L("Tháng %ld: %@", Calendar.current.component(.month, from: e.date), fmt(e.s.month)))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
        }
    }
}

/// Thanh ngân sách trên nền màu: màu mực thay cho xanh / cam / đỏ (dòng chữ phía trên đã nói còn hay vượt)
struct InkBar: View {
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
struct QuickButtons: View {
    let tone: WidgetTone
    @Environment(\.widgetRenderingMode) private var mode
    /// iOS tô lại mọi màu thành một màu, chỉ giữ độ trong (màn hình chính kiểu Tinted / Clear, StandBy ban đêm)
    private var flat: Bool { mode != .fullColor }

    var body: some View {
        VStack(spacing: 8) {
            Link(destination: QuickKind.scan.url) {
                Label(L("Quét QR"), systemImage: "qrcode")
                    .font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(tone.onPlate(flat))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Nền nút chính nhận màu nhấn của kiểu Tinted; chữ ở nhóm thường nên vẫn tách khỏi nền
                    .background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tone.plate(flat)).widgetAccentable() }
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

struct VoiceView: View {
    let e: SpendEntry
    /// Cỡ widget. Trong widget thì lấy theo iOS; app dựng phim thì chỉ định
    var size: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { size ?? envFamily }
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.showsWidgetContainerBackground) private var showsBg
    /// Màu theo lựa chọn của người dùng cho widget này (mặc định thẻ xanh lá như icon app)
    private var card: Color { e.tone.bg }
    /// Mực theo chỗ đang vẽ (xem `WidgetTone.inked`); app dựng phim thì tự vẽ nền nên giữ đúng màu đã chọn
    private var tone: WidgetTone { size == nil ? e.tone.inked(mode, background: showsBg) : e.tone }
    private var ink: Color { tone.ink }
    private var soft: Color { tone.ink.opacity(0.62) }
    /// iOS tô lại mọi màu thành một màu, chỉ giữ độ trong (màn hình chính kiểu Tinted / Clear, StandBy ban đêm)
    private var flat: Bool { mode != .fullColor }

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
                // Micro đặc và cao hơn khung quét QR: nhỏ hơn vài điểm thì hai nút tròn nhìn bằng nhau
                Image(systemName: "mic.fill").font(.system(size: 20, weight: .semibold))
            }
            .accessibilityLabel(L("Nói để ghi"))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(tone.onPlate(flat))
                        .frame(width: 58, height: 58)
                        .background { Circle().fill(tone.plate(flat)).widgetAccentable() }
                    Spacer()
                    Image(systemName: "wave.3.right").font(.system(size: 15, weight: .bold)).foregroundStyle(ink)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 6)
                Text(L("Nói để ghi")).font(.system(size: 19, weight: .bold)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7)
                Text(L("Hôm nay %@", fmt(e.s.today)))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(soft)
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

struct MyQREntry: TimelineEntry {
    let date: Date
    let qr: MyQR
    var tone: WidgetTone = .green
    /// Số đã chi (cỡ vừa hiện cạnh mã QR)
    var s = Summary(today: 0, month: 0, count: 0, day: Date())
}

struct MyQRView: View {
    let e: MyQREntry
    /// Cỡ widget. Trong widget thì lấy theo iOS; app dựng phim thì chỉ định
    var size: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { size ?? envFamily }
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.showsWidgetContainerBackground) private var showsBg
    /// Cùng bộ màu với các widget khác của Pay (mặc định thẻ xanh lá, đổi được trong Sửa tiện ích)
    /// Mực theo chỗ đang vẽ (xem `WidgetTone.inked`); app dựng phim thì tự vẽ nền nên giữ đúng màu đã chọn
    private var tone: WidgetTone { size == nil ? e.tone.inked(mode, background: showsBg) : e.tone }
    private var ink: Color { tone.ink }
    private var soft: Color { tone.ink.opacity(0.62) }
    /// iOS tô lại mọi màu thành một màu, chỉ giữ độ trong (màn hình chính kiểu Tinted / Clear, StandBy ban đêm)
    private var flat: Bool { mode != .fullColor }

    var body: some View {
        content.containerBackground(for: .widget) { e.tone.bg }
    }

    /// Bốn số cuối của tài khoản, đủ để nhận ra mà không phơi cả số ra màn hình chính
    private var tail: String { e.qr.acct.count > 4 ? "••" + e.qr.acct.suffix(4) : e.qr.acct }

    /// Mã QR không nền, vẽ thẳng lên nền widget: ô màu đen trên nền sáng, màu trắng trên nền tối
    private var code: some View { MyQRCode(qr: e.qr, ink: tone.dark ? .white : .black) }

    private func quick(_ icon: String, _ k: QuickKind, _ label: String, primary: Bool = false) -> some View {
        Link(destination: k.url) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(primary ? tone.onPlate(flat) : ink)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(primary ? tone.plate(flat) : ink.opacity(0.14))
                        .widgetAccentable(primary)
                }
        }
        .accessibilityLabel(label)
    }

    @ViewBuilder private var content: some View {
        if !e.qr.ready {
            VStack(spacing: 8) {
                Image(systemName: "qrcode").font(.system(size: 34, weight: .semibold)).foregroundStyle(ink)
                Text(L("Mở Payso > Cài đặt để thêm tài khoản nhận tiền"))
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
                         ?? L("Tháng %ld: %@", Calendar.current.component(.month, from: e.date), fmt(e.s.month)))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(ink).minimumScaleFactor(0.7).lineLimit(1)
                    if let b = e.s.budgetStatus { InkBar(ratio: b.ratio, ink: ink).padding(.top, 3) }
                    Spacer(minLength: 6)
                    HStack(spacing: 6) {
                        quick("qrcode", .scan, L("Quét QR"), primary: true)
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
