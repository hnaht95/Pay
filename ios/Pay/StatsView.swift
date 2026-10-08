import Charts
import SwiftUI

/// Thống kê theo tháng: tổng, so với tháng trước, chi theo ngày, theo danh mục, nơi chi nhiều nhất.
struct StatsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var month = Date()
    @State private var pickedDay: Date?

    private let cal = Calendar.current
    private static let barColor = Color(light: 0x2A78D6, dark: 0x3987E5)

    var body: some View {
        let items = store.monthItems(month)
        let prev = comparable(store.monthItems(cal.date(byAdding: .month, value: -1, to: month)!))
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    monthPicker
                    summary(items, prev)
                    if items.isEmpty {
                        empty
                    } else {
                        tiles(items)
                        card("Chi theo ngày") { daily(items) }
                        card("Theo danh mục") { categories(items, prev) }
                        if !top(items).isEmpty { card("Chi nhiều nhất") { places(items) } }
                    }
                }
                .padding(16)
            }
            .background(Palette.bg)
            .navigationTitle("Thống kê")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } }
            }
        }
    }

    // MARK: Chọn tháng

    private var monthPicker: some View {
        let isNow = cal.isDate(month, equalTo: Date(), toGranularity: .month)
        return HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Tháng trước")
            Spacer()
            Text(monthTitle(month)).font(.system(size: 18, weight: .semibold))
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(isNow)
                .accessibilityLabel("Tháng sau")
        }
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.primary)
        .background(Palette.pill, in: Capsule())
    }

    private var isRunning: Bool { cal.isDate(month, equalTo: Date(), toGranularity: .month) }

    /// Tháng đang chạy thì so với cùng kỳ tháng trước (ngày 1 đến hôm nay), không so với cả tháng trước.
    private func comparable(_ prev: [Expense]) -> [Expense] {
        guard isRunning else { return prev }
        let today = cal.component(.day, from: Date())
        return prev.filter { cal.component(.day, from: $0.date) <= today }
    }

    private func shift(_ n: Int) {
        pickedDay = nil
        month = cal.date(byAdding: .month, value: n, to: month)!
    }

    // MARK: Tổng tháng

    private func summary(_ items: [Expense], _ prev: [Expense]) -> some View {
        let running = isRunning
        let total = sum(items)
        let before = sum(prev)
        let prevName = monthTitle(cal.date(byAdding: .month, value: -1, to: month)!).lowercased()
        return VStack(alignment: .leading, spacing: 8) {
            Text("Tổng chi").font(.system(size: 16)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(fmt(total)).font(.system(size: 44, weight: .bold)).kerning(-1).minimumScaleFactor(0.5).lineLimit(1)
                Text("đ").font(.system(size: 24, weight: .semibold)).foregroundStyle(.secondary)
            }
            if before > 0 {
                let pct = Int((Double(total - before) / Double(before) * 100).rounded())
                let less = total <= before
                // Chi ít hơn là tốt: mũi tên + chữ đi kèm màu, không dùng màu đơn độc
                Label("\(less ? "Ít" : "Nhiều") hơn \(abs(pct))% so với \(running ? "cùng kỳ " : "")\(prevName)",
                      systemImage: less ? "arrow.down.right" : "arrow.up.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(less ? Color(light: 0x006300, dark: 0x0CA30C) : Color(light: 0xD03B3B, dark: 0xE66767))
            } else if !prev.isEmpty || total > 0 {
                Text("Tháng trước chưa có dữ liệu để so sánh").font(.system(size: 15)).foregroundStyle(.secondary)
            }
            if let b = store.budgetStatus(month), cal.isDate(month, equalTo: Date(), toGranularity: .month) {
                BudgetBar(s: b, height: 8).padding(.top, 6)
                Text("\(b.label) · ngân sách \(fmt(b.budget))đ").font(.system(size: 14)).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.hero, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: Ô số liệu

    private func tiles(_ items: [Expense]) -> some View {
        let days = cal.isDate(month, equalTo: Date(), toGranularity: .month)
            ? cal.component(.day, from: Date())
            : cal.range(of: .day, in: .month, for: month)!.count
        let biggest = items.max { $0.a < $1.a }!
        return HStack(spacing: 10) {
            tile("TB mỗi ngày", "\(fmt(sum(items) / max(days, 1) / 1000 * 1000))đ")
            tile("Lớn nhất", "\(fmt(biggest.a))đ", sub: biggest.n?.isEmpty == false ? biggest.n : Category.get(biggest.c).name)
            tile("Số khoản", "\(items.count)")
        }
    }

    private func tile(_ title: String, _ value: String, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(size: 18, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
            if let sub { Text(sub).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: Chi theo ngày

    private func daily(_ items: [Expense]) -> some View {
        let byDay = Dictionary(grouping: items) { cal.startOfDay(for: $0.date) }.mapValues(sum)
        let first = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let count = cal.range(of: .day, in: .month, for: month)!.count
        let days = (0..<count).map { cal.date(byAdding: .day, value: $0, to: first)! }
        let perDay = store.budget > 0 ? store.budget / count : 0
        let picked = pickedDay.map { cal.startOfDay(for: $0) }

        return VStack(alignment: .leading, spacing: 8) {
            // Dòng chú thích thay đổi khi chạm vào cột: ngày + số tiền
            Group {
                if let picked {
                    Text("\(dayTitle(picked)): ") + Text("\(fmt(byDay[picked] ?? 0))đ").bold()
                } else {
                    Text("Chạm vào cột để xem từng ngày")
                }
            }
            .font(.system(size: 14)).foregroundStyle(.secondary)

            Chart {
                ForEach(days, id: \.self) { d in
                    BarMark(x: .value("Ngày", d, unit: .day), y: .value("Đã chi", byDay[d] ?? 0))
                        .foregroundStyle(Self.barColor.opacity(picked == nil || picked == d ? 1 : 0.35))
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
                }
                if perDay > 0 {
                    RuleMark(y: .value("Ngân sách/ngày", perDay))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Ngân sách/ngày").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                }
            }
            .chartOverlay { proxy in
                // Chạm để chọn ngày, chạm lại để bỏ chọn. Chỉ nhận chạm nên vuốt trên biểu đồ vẫn cuộn trang.
                GeometryReader { g in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { p in
                            guard let plot = proxy.plotFrame, let d: Date = proxy.value(atX: p.x - g[plot].origin.x) else { return }
                            let day = cal.startOfDay(for: d)
                            pickedDay = pickedDay == day ? nil : day
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel { if let n = v.as(Int.self) { Text(short(n)) } }
                }
            }
            .frame(height: 180)
        }
    }

    // MARK: Theo danh mục

    private func categories(_ items: [Expense], _ prev: [Expense]) -> some View {
        let total = max(sum(items), 1)
        let now = Dictionary(grouping: items, by: \.c).mapValues(sum)
        let before = Dictionary(grouping: prev, by: \.c).mapValues(sum)
        // Biểu đồ vẽ theo thứ tự danh mục cố định; danh sách bên dưới xếp theo số tiền
        let cats = Category.all.filter { (now[$0.k] ?? 0) > 0 }
        let ranked = cats.sorted { now[$0.k]! > now[$1.k]! }

        return VStack(spacing: 16) {
            Chart(cats) { c in
                SectorMark(angle: .value("Đã chi", now[c.k]!), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .cornerRadius(3)
                    .foregroundStyle(c.chart)
            }
            .chartLegend(.hidden)
            .frame(height: 190)
            .overlay {
                VStack(spacing: 2) {
                    Text("\(cats.count) danh mục").font(.system(size: 13)).foregroundStyle(.secondary)
                    Text(short(sum(items))).font(.system(size: 22, weight: .bold))
                }
            }

            // Bảng: tên, số tiền, phần trăm, so với tháng trước (đây cũng là chú thích của biểu đồ)
            VStack(spacing: 0) {
                ForEach(ranked) { c in
                    let v = now[c.k]!
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3).fill(c.chart).frame(width: 6, height: 30)
                        Text(c.icon).font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name).font(.system(size: 16, weight: .medium))
                            Text("\(Int((Double(v) / Double(total) * 100).rounded()))%").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(fmt(v))đ").font(.system(size: 16, weight: .semibold))
                            if let b = before[c.k], b > 0 {
                                let pct = Int((Double(v - b) / Double(b) * 100).rounded())
                                Text(pct == 0 ? "như \(isRunning ? "cùng kỳ " : "")tháng trước" : "\(pct > 0 ? "+" : "")\(pct)% \(isRunning ? "cùng kỳ " : "")tháng trước")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    if c.id != ranked.last?.id { Divider() }
                }
            }
        }
    }

    // MARK: Nơi chi nhiều nhất

    /// Gộp theo ghi chú / tên người nhận (không phân biệt hoa thường, dấu), lấy 5 nơi tốn nhất.
    private func top(_ items: [Expense]) -> [(name: String, total: Int, count: Int)] {
        let named = items.filter { !($0.n ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        return Dictionary(grouping: named) { strip($0.n!.trimmingCharacters(in: .whitespaces)) }
            .map { (name: $0.value.last!.n!.trimmingCharacters(in: .whitespaces), total: sum($0.value), count: $0.value.count) }
            .sorted { $0.total > $1.total }
            .prefix(5)
            .map { $0 }
    }

    private func places(_ items: [Expense]) -> some View {
        let rows = top(items)
        let maxTotal = rows.first?.total ?? 1
        return VStack(spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(r.name).font(.system(size: 16, weight: .medium)).lineLimit(1)
                        Text("· \(r.count) lần").font(.system(size: 13)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(fmt(r.total))đ").font(.system(size: 16, weight: .semibold))
                    }
                    GeometryReader { g in
                        Capsule().fill(Self.barColor)
                            .frame(width: max(6, g.size.width * Double(r.total) / Double(maxTotal)))
                    }
                    .frame(height: 6)
                }
            }
        }
    }

    // MARK: Phụ

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("Chưa có khoản chi nào trong \(monthTitle(month).lowercased())").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 19, weight: .bold))
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func sum(_ items: [Expense]) -> Int { items.reduce(0) { $0 + $1.a } }

    private func monthTitle(_ d: Date) -> String {
        let c = cal.dateComponents([.month, .year], from: d)
        return c.year == cal.component(.year, from: Date()) ? "Tháng \(c.month!)" : "Tháng \(c.month!)/\(c.year!)"
    }

    private func dayTitle(_ d: Date) -> String {
        let c = cal.dateComponents([.day, .month], from: d)
        return "Ngày \(c.day!)/\(c.month!)"
    }

    /// 1250000 -> "1,3tr", 45000 -> "45k"
    private func short(_ n: Int) -> String {
        if n >= 1_000_000 {
            let v = Double(n) / 1e6
            let t = v >= 10 ? String(Int(v.rounded())) : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
            return (t.hasSuffix(",0") ? String(t.dropLast(2)) : t) + "tr"
        }
        if n >= 1000 { return "\(n / 1000)k" }
        return "\(n)"
    }
}
