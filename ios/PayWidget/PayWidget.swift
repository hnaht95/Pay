import AppIntents
import SwiftUI
import WidgetKit

@main
struct PayWidgets: WidgetBundle {
    var body: some Widget {
        SpendWidget()
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
            .configurationDisplayName("Chi tiêu hôm nay")
            .description("Xem nhanh số đã chi, chạm để quét QR hoặc nhập khoản mới.")
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
                VStack(spacing: 10) {
                    action("Quét QR", "qrcode.viewfinder", .scan, primary: true)
                    action("Nhập", "plus", .add, primary: false)
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
                Label("Hôm nay", systemImage: "qrcode.viewfinder").font(.caption)
                Text("\(fmt(e.s.today))đ").font(.system(size: 22, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
                Text(e.s.budgetStatus.map(\.label) ?? "Tháng: \(fmt(e.s.month))đ").font(.caption2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(QuickKind.scan.url)
        case .accessoryInline:
            Text("Hôm nay \(fmt(e.s.today))đ").widgetURL(QuickKind.scan.url)
        default:   // nhỏ: chạm vào là quét QR luôn
            VStack(alignment: .leading, spacing: 0) {
                totals
                Spacer(minLength: 6)
                Label("Quét QR", systemImage: "qrcode.viewfinder")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.primary, in: Capsule())
                    .foregroundStyle(scheme == .dark ? .black : .white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(QuickKind.scan.url)
        }
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hôm nay đã chi").font(.system(size: 13)).foregroundStyle(.secondary)
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
                Text("Tháng \(Calendar.current.component(.month, from: e.date)): \(fmt(e.s.month))đ")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
        }
    }

    private func action(_ title: String, _ icon: String, _ k: QuickKind, primary: Bool) -> some View {
        Link(destination: k.url) {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(primary ? AnyShapeStyle(.primary) : AnyShapeStyle(.background.opacity(0.6)),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(primary ? (scheme == .dark ? Color.black : Color.white) : Color.primary)
        }
    }
}

// MARK: Nút trong Trung tâm điều khiển — gán được cho nút Tác vụ (iOS 18+)

@available(iOS 18.0, *)
struct VoiceControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "VoiceControl") {
            ControlWidgetButton(action: VoiceIntent()) {
                Label("Ghi bằng giọng nói", systemImage: "mic.fill")
            }
        }
        .displayName("Pay: Ghi bằng giọng nói")
        .description("Mở Pay và nghe luôn, nói \"35k cafe\" là ghi.")
    }
}

@available(iOS 18.0, *)
struct ScanControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ScanControl") {
            ControlWidgetButton(action: ScanIntent()) {
                Label("Quét QR", systemImage: "qrcode.viewfinder")
            }
        }
        .displayName("Pay: Quét QR")
        .description("Mở Pay và quét mã QR thanh toán.")
    }
}
