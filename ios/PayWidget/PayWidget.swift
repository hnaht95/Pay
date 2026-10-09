import AppIntents
import SwiftUI
import WidgetKit

@main
struct PayWidgets: WidgetBundle {
    var body: some Widget {
        SpendWidget()
        VoiceWidget()
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
}

struct SpendProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpendEntry {
        SpendEntry(date: Date(), s: Summary(today: 125_000, month: 3_450_000, count: 3, day: Date(), budget: 8_000_000))
    }

    func getSnapshot(in context: Context, completion: @escaping (SpendEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : SpendEntry(date: Date(), s: Summary.load().at(Date())))
    }

    /// App ghi số liệu mới là widget vẽ lại; thêm một mốc lúc nửa đêm để "hôm nay" tự về 0.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SpendEntry>) -> Void) {
        let now = Date()
        let s = Summary.load()
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        let entries = [SpendEntry(date: now, s: s.at(now)), SpendEntry(date: midnight, s: s.at(midnight))]
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

struct SpendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpendWidget", provider: SpendProvider()) { SpendView(e: $0) }
            .configurationDisplayName(L("Chi tiêu hôm nay"))
            .description(L("Xem nhanh số đã chi, chạm để quét QR, nói hoặc nhập khoản mới."))
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

private let hero = Color(red: 0xDF / 255, green: 0xE5 / 255, blue: 0xFF / 255)
private let heroDark = Color(red: 0x24 / 255, green: 0x2B / 255, blue: 0x4D / 255)

struct SpendView: View {
    let e: SpendEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if family == .systemSmall || family == .systemMedium { scheme == .dark ? heroDark : hero } else { Color.clear }
            }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 14) {
                totals.frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 8) {
                    action(L("Quét QR"), "qrcode.viewfinder", .scan, primary: true)
                    HStack(spacing: 8) {
                        iconAction("mic.fill", .voice, L("Nói để ghi"))
                        iconAction("plus", .add, L("Nhập"))
                    }
                }
                .frame(width: 118)
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "qrcode.viewfinder").font(.system(size: 24, weight: .semibold))
            }
            .widgetURL(QuickKind.scan.url)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(L("Hôm nay"), systemImage: "qrcode.viewfinder").font(.caption)
                Text("\(fmt(e.s.today))đ").font(.system(size: 22, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
                Text(e.s.budgetStatus.map(\.label) ?? L("Tháng: %@đ", fmt(e.s.month))).font(.caption2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(QuickKind.scan.url)
        case .accessoryInline:
            Text(L("Hôm nay %@đ", fmt(e.s.today))).widgetURL(QuickKind.scan.url)
        default:   // nhỏ: chạm vào là quét QR luôn
            VStack(alignment: .leading, spacing: 0) {
                totals
                Spacer(minLength: 6)
                // Màu chữ đặt trước nền: nền .primary lấy theo màu chữ bên ngoài nó
                Label(L("Quét QR"), systemImage: "qrcode.viewfinder")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(scheme == .dark ? .black : .white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.primary, in: Capsule())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(QuickKind.scan.url)
        }
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Hôm nay đã chi")).font(.system(size: 13)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(fmt(e.s.today)).font(.system(size: 30, weight: .bold)).kerning(-1)
                Text("đ").font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
            }
            .minimumScaleFactor(0.5).lineLimit(1)
            if let b = e.s.budgetStatus {
                Text(b.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(b.color)
                    .minimumScaleFactor(0.7).lineLimit(1)
                BudgetBar(s: b, height: 5)
            } else {
                Text(L("Tháng %ld: %@đ", Calendar.current.component(.month, from: e.date), fmt(e.s.month)))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
        }
    }

    private func iconAction(_ icon: String, _ k: QuickKind, _ label: String) -> some View {
        Link(destination: k.url) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.primary)
        }
        .accessibilityLabel(label)
    }

    private func action(_ title: String, _ icon: String, _ k: QuickKind, primary: Bool) -> some View {
        Link(destination: k.url) {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(primary ? (scheme == .dark ? Color.black : Color.white) : Color.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(primary ? AnyShapeStyle(.primary) : AnyShapeStyle(.background.opacity(0.6)),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: Nút micro: chạm là mở Pay và nghe luôn (màn hình chính + màn hình khoá)

struct VoiceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VoiceWidget", provider: SpendProvider()) { VoiceView(e: $0) }
            .configurationDisplayName(L("Nói để ghi"))
            .description(L("Chạm là Pay nghe luôn, nói \"35k cafe\" là ghi."))
            .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct VoiceView: View {
    let e: SpendEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .widgetURL(QuickKind.voice.url)
            .containerBackground(for: .widget) {
                if family == .systemSmall { scheme == .dark ? heroDark : hero } else { Color.clear }
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
                Image(systemName: "mic.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(scheme == .dark ? Color.black : Color.white)
                    .frame(width: 60, height: 60)
                    .background(.primary, in: Circle())
                Spacer(minLength: 6)
                Text(L("Nói để ghi")).font(.system(size: 18, weight: .bold))
                Text(L("Hôm nay %@đ", fmt(e.s.today)))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
