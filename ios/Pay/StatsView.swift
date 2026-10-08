import Charts
import SwiftUI

/// Thống kê theo tháng, kiểu bảng điều khiển: thẻ cam tổng chi, các ô số liệu, hạn mức, biểu đồ 6 tháng,
/// chi theo danh mục và các khoản gần đây.
struct StatsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var month = Date()
    /// Tháng cuối của khung 6 tháng đang hiện (thanh chọn tháng + biểu đồ 6 tháng)
    @State private var windowEnd = Date()

    private let cal = Calendar.current

    // Bảng màu của màn hình này
    static let page = Color(light: 0xEFEFEF, dark: 0x0D0D10)
    static let card = Color(light: 0xFFFFFF, dark: 0x1C1C1F)
    static let ink = Color(light: 0x1C1C1E, dark: 0xF2F2F2)          // cột "Hoá đơn", tab đang chọn
    static let inkText = Color(light: 0xFFFFFF, dark: 0x111114)
    static let orange = Color(light: 0xEE6A35, dark: 0xF07443)
    static let chip = Color(light: 0xF2F2F2, dark: 0x2A2A2E)

    var body: some View {
        let items = store.monthItems(month)
        let prev = comparable(store.monthItems(cal.date(byAdding: .month, value: -1, to: month)!))
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    monthTabs
                    hero(items, prev)
                    grid(items, prev)
                    limitCard(items)
                    trendCard
                    if !items.isEmpty {
                        categoryCard(items)
                        recentCard(items)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 32)
            }
            .background(Self.page.ignoresSafeArea())
            .navigationTitle("Thống kê")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } }
            }
        }
    }

    // MARK: Chọn tháng (dạng tab, tháng đang chọn là viên thuốc đậm)

    /// 6 tháng của khung đang xem, cũ trước mới sau.
    private var windowMonths: [Date] {
        (0..<6).reversed().map { cal.date(from: cal.dateComponents([.year, .month], from: cal.date(byAdding: .month, value: -$0, to: windowEnd)!))! }
    }

    private var atLatest: Bool { cal.isDate(windowEnd, equalTo: Date(), toGranularity: .month) }

    /// Lùi / tiến cả khung 6 tháng; tháng đang xem nhảy theo nếu rơi ra ngoài khung.
    private func page(_ n: Int) {
        var end = cal.date(byAdding: .month, value: 6 * n, to: windowEnd)!
        if end > Date() { end = Date() }
        windowEnd = end
        if !windowMonths.contains(where: { isSelected($0) }) { month = windowMonths.last! }
    }

    private var monthTabs: some View {
        // 6 tháng chia đều; ‹ › để lùi / tiến cả khung 6 tháng
        HStack(spacing: 2) {
            pageButton("chevron.left", label: "6 tháng trước") { page(-1) }
            ForEach(windowMonths, id: \.self) { m in
                let on = isSelected(m)
                let otherYear = cal.component(.year, from: m) != cal.component(.year, from: Date())
                Button { month = m } label: {
                    VStack(spacing: 0) {
                        Text(shortMonth(m)).font(.system(size: 15, weight: on ? .semibold : .regular))
                        if otherYear { Text(String(cal.component(.year, from: m))).font(.system(size: 10)).opacity(0.8) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundStyle(on ? Self.inkText : Color.secondary)
                    .background(on ? Self.ink : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            pageButton("chevron.right", label: "6 tháng sau") { page(1) }
                .disabled(atLatest)
                .opacity(atLatest ? 0.3 : 1)
        }
        .padding(4)
        .background(Self.card, in: Capsule())
    }

    private func pageButton(_ symbol: String, label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }

    // MARK: Thẻ cam: tổng chi tháng

    private func hero(_ items: [Expense], _ prev: [Expense]) -> some View {
        let total = sum(items)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Tổng chi \(monthName(month).lowercased())").font(.system(size: 16, weight: .medium))
                Spacer()
                iconChip("creditcard", fg: .white, bg: .white.opacity(0.2))
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(fmt(total)).font(.system(size: 40, weight: .bold)).kerning(-1).minimumScaleFactor(0.5).lineLimit(1)
                Text("đ").font(.system(size: 22, weight: .semibold)).opacity(0.8)
            }
            if let d = delta(total, sum(prev)) {
                HStack(spacing: 8) {
                    Label("\(abs(d))%", systemImage: d > 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.22), in: Capsule())
                    Text(isRunning ? "so với cùng kỳ" : "so với tháng trước")
                        .font(.system(size: 13)).opacity(0.85)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: 0xF6814E), Color(hex: 0xE9561F)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Ô số liệu 2×2

    private func grid(_ items: [Expense], _ prev: [Expense]) -> some View {
        let days = isRunning ? cal.component(.day, from: Date()) : cal.range(of: .day, in: .month, for: month)!.count
        let prevDays = isRunning ? days : cal.range(of: .day, in: .month, for: cal.date(byAdding: .month, value: -1, to: month)!)!.count
        let avg = sum(items) / max(days, 1), prevAvg = sum(prev) / max(prevDays, 1)
        let biggest = items.max { $0.a < $1.a }
        let today = store.total(on: Date()), yesterday = store.total(on: cal.date(byAdding: .day, value: -1, to: Date())!)
        // Grid: hai ô cùng hàng cao bằng nhau, chiều cao theo nội dung (không chừa chỗ trống)
        return Grid(horizontalSpacing: 14, verticalSpacing: 14) {
            GridRow {
            if isRunning {
                tile("Hôm nay", "sun.max", "\(fmt(today))đ", delta: delta(today, yesterday), note: "chưa có để so")
            } else {
                let active = Set(items.map { cal.component(.day, from: $0.date) }).count
                tile("Ngày có chi", "calendar", "\(active)/\(days)", delta: nil, note: "\(active * 100 / max(days, 1))% số ngày")
            }
            tile("TB mỗi ngày", "chart.line.flattrend.xyaxis", "\(fmt(avg / 1000 * 1000))đ", delta: delta(avg, prevAvg), note: "chưa có để so")
            }
            GridRow {
            tile("Lớn nhất", "arrow.up.forward.circle", biggest.map { "\(fmt($0.a))đ" } ?? "0đ", delta: nil,
                 note: biggest.map { $0.n?.isEmpty == false ? $0.n! : Category.get($0.c).name } ?? "chưa có")
            tile("Số khoản", "list.bullet", "\(items.count)", delta: delta(items.count, prev.count), note: "chưa có để so")
            }
        }
    }

    /// Ô số liệu tối giản: tên + biểu tượng, con số, và luôn một nhãn ở đáy: % nếu có so sánh, không thì nhãn xám ghi note.
    /// Nhờ vậy hai ô cùng hàng luôn cao bằng nhau mà không ô nào bị trống đáy.
    private func tile(_ title: String, _ icon: String, _ value: String, delta d: Int?, note: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Chữ tiêu đề nằm sát mép trên như lề trái/dưới; biểu tượng tròn lùi lên góc
            HStack(alignment: .top) {
                Text(title).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                iconChip(icon, fg: .primary, bg: Self.chip).padding(.top, 0.5).padding(.trailing, -1.5)   // cách mép trên và phải đều ~16,5pt (đã đo)
            }
            Text(value).font(.system(size: 22, weight: .bold)).minimumScaleFactor(0.5).lineLimit(1)
            if let d { deltaPill(d) } else { notePill(note) }
        }
        .padding(18)
        .padding(.top, 2.5)   // đỉnh chữ tiêu đề cách mép trên ~18,5pt, bằng lề trái/dưới (đã đo trên ảnh chụp)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Self.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Chi tăng là xấu: mũi tên lên nền đỏ nhạt, xuống nền xanh nhạt (có mũi tên, không chỉ dựa vào màu).
    private func deltaPill(_ d: Int) -> some View {
        let up = d > 0
        return Label("\(abs(d))%", systemImage: up ? "arrow.up" : "arrow.down")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(up ? Color(light: 0xB42318, dark: 0xFF8A80) : Color(light: 0x067647, dark: 0x6CE9A6))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background((up ? Color.red : Color.green).opacity(0.14), in: Capsule())
    }

    /// Nhãn xám cùng cỡ với nhãn %, cho ô không có gì để so.
    private func notePill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Self.chip, in: Capsule())
    }

    // MARK: Hạn mức tháng

    private func limitCard(_ items: [Expense]) -> some View {
        let spent = sum(items)
        return card {
            Text("Hạn mức chi tháng").font(.system(size: 17, weight: .semibold))
            if store.budget > 0 {
                let ratio = min(Double(spent) / Double(store.budget), 1)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Hatch.gray)
                        Capsule().fill(spent > store.budget ? Color(hex: 0xD92D20) : Self.orange)
                            .frame(width: max(12, g.size.width * ratio))
                    }
                }
                .frame(height: 12)
                .padding(.top, 8)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(fmt(spent))đ").font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text("/ \(fmt(store.budget))đ").font(.system(size: 14)).foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            } else {
                Text("Chưa đặt hạn mức. Vào Cài đặt › Ngân sách để đặt.").font(.system(size: 14)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Biểu đồ 6 tháng: Hoá đơn (đậm) + Chi tiêu khác (cam sọc)

    private struct MonthBar: Identifiable {
        let date: Date
        let bills: Int
        let other: Int
        var id: Date { date }
        var total: Int { bills + other }
    }

    private var trendCard: some View {
        // Cùng khung 6 tháng với thanh chọn tháng; tháng đang xem được tô đậm
        let bars: [MonthBar] = windowMonths.map { m in
            let items = store.monthItems(m)
            let bills = sum(items.filter { $0.c == "hd" })
            return MonthBar(date: m, bills: bills, other: sum(items) - bills)
        }
        let top = max(bars.map(\.total).max() ?? 0, 1)
        let gap = Double(top) * 0.02   // khe hở giữa hai đoạn của cùng một cột
        let used = bars.filter { $0.total > 0 }.map(\.total)
        return card {
            Text("Chi 6 tháng").font(.system(size: 17, weight: .semibold))
            HStack(spacing: 14) {
                legend(AnyShapeStyle(Self.ink), "Hoá đơn")
                legend(AnyShapeStyle(Hatch.orange), "Chi tiêu khác")
                Spacer()
            }
            .padding(.top, 4)
            Chart(bars) { b in
                if b.bills > 0 {
                    BarMark(x: .value("Tháng", b.date, unit: .month), yStart: .value("Từ", 0), yEnd: .value("Hoá đơn", b.bills), width: .ratio(0.55))
                        .foregroundStyle(Self.ink)
                        .cornerRadius(6)
                        .opacity(isSelected(b.date) ? 1 : 0.45)
                }
                if b.other > 0 {
                    let start = b.bills > 0 ? Double(b.bills) + gap : 0
                    BarMark(x: .value("Tháng", b.date, unit: .month), yStart: .value("Từ", start), yEnd: .value("Chi tiêu khác", start + Double(b.other)), width: .ratio(0.55))
                        .foregroundStyle(Hatch.orange)
                        .cornerRadius(6)
                        .opacity(isSelected(b.date) ? 1 : 0.45)
                }
            }
            // Giữ đủ 6 tháng trên trục kể cả tháng chưa có khoản chi nào
            .chartXScale(domain: bars.first!.date...cal.date(byAdding: .month, value: 1, to: bars.last!.date)!)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { v in
                    AxisValueLabel(centered: true) { if let d = v.as(Date.self) { Text(shortMonth(d)) } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Color.primary.opacity(0.1))
                    AxisValueLabel { if let n = v.as(Double.self) { Text(short(Int(n))) } }
                }
            }
            .chartOverlay { proxy in
                // Chạm cột để chuyển sang tháng đó (chỉ nhận chạm, vuốt vẫn cuộn trang)
                GeometryReader { g in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { p in
                            guard let plot = proxy.plotFrame, let d: Date = proxy.value(atX: p.x - g[plot].origin.x) else { return }
                            if let b = bars.first(where: { cal.isDate($0.date, equalTo: d, toGranularity: .month) }) { month = b.date }
                        }
                }
            }
            .frame(height: 220)
            .padding(.top, 12)

            // Trung bình / Thấp nhất / Cao nhất của các tháng có chi
            if !used.isEmpty {
                HStack(spacing: 0) {
                    stat("Trung bình", used.reduce(0, +) / used.count)
                    Divider().frame(height: 36)
                    stat("Thấp nhất", used.min()!)
                    Divider().frame(height: 36)
                    stat("Cao nhất", used.max()!)
                }
                .padding(.top, 16)
            }
        }
    }

    private func stat(_ title: String, _ v: Int) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(short(v)).font(.system(size: 20, weight: .bold))
        }
        .frame(maxWidth: .infinity)
    }

    private func isSelected(_ d: Date) -> Bool { cal.isDate(d, equalTo: month, toGranularity: .month) }

    private func legend(_ style: AnyShapeStyle, _ title: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(style).frame(width: 12, height: 12)
            Text(title).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    // MARK: Theo danh mục

    private func categoryCard(_ items: [Expense]) -> some View {
        let total = max(sum(items), 1)
        let byCat = Dictionary(grouping: items, by: \.c).mapValues(sum)
        let ranked = Category.all.filter { (byCat[$0.k] ?? 0) > 0 }.sorted { byCat[$0.k]! > byCat[$1.k]! }
        return card {
            Text("Theo danh mục").font(.system(size: 17, weight: .semibold))
            VStack(spacing: 22) {
                ForEach(ranked) { c in
                    let v = byCat[c.k]!
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            Text(c.icon).font(.system(size: 18)).frame(width: 38, height: 38).background(c.color, in: Circle())
                            Text(c.name).font(.system(size: 16, weight: .medium))
                            Text("\(Int((Double(v) / Double(total) * 100).rounded()))%")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Self.chip, in: Capsule())
                            Spacer()
                            Text("\(fmt(v))đ").font(.system(size: 16, weight: .semibold))
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Self.chip)
                                Capsule().fill(c.chart).frame(width: max(6, g.size.width * Double(v) / Double(total)))
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
            .padding(.top, 12)
        }
    }

    // MARK: Khoản chi gần đây

    private func recentCard(_ items: [Expense]) -> some View {
        let rows = Array(items.sorted { $0.t > $1.t }.prefix(6))
        return card {
            HStack {
                Text("Khoản chi gần đây").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("\(items.count) khoản").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(rows) { e in
                    let c = Category.get(e.c)
                    HStack(spacing: 12) {
                        Text(c.icon).font(.system(size: 16)).frame(width: 34, height: 34)
                            .background(c.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.n?.isEmpty == false ? e.n! : c.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                            Text(when(e.date)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text("\(fmt(e.a))đ").font(.system(size: 15, weight: .semibold))
                    }
                    .padding(.vertical, 14)
                    if e.id != rows.last?.id { Divider().padding(.leading, 50) }
                }
            }
        }
    }

    // MARK: Phụ

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Self.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func iconChip(_ symbol: String, fg: Color, bg: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
            .foregroundStyle(fg)
            .frame(width: 32, height: 32)
            .background(bg, in: Circle())
    }

    private var isRunning: Bool { cal.isDate(month, equalTo: Date(), toGranularity: .month) }

    /// Tháng đang chạy thì so với cùng kỳ tháng trước (ngày 1 đến hôm nay), không so với cả tháng trước.
    private func comparable(_ prev: [Expense]) -> [Expense] {
        guard isRunning else { return prev }
        let today = cal.component(.day, from: Date())
        return prev.filter { cal.component(.day, from: $0.date) <= today }
    }

    /// Phần trăm thay đổi, nil nếu không có gì để so.
    private func delta(_ now: Int, _ before: Int) -> Int? {
        guard before > 0 else { return nil }
        return Int((Double(now - before) / Double(before) * 100).rounded())
    }

    private func sum(_ items: [Expense]) -> Int { items.reduce(0) { $0 + $1.a } }

    private func monthName(_ d: Date) -> String {
        let c = cal.dateComponents([.month, .year], from: d)
        return c.year == cal.component(.year, from: Date()) ? "Tháng \(c.month!)" : "Tháng \(c.month!)/\(c.year!)"
    }

    private func shortMonth(_ d: Date) -> String { "T\(cal.component(.month, from: d))" }

    private func when(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM HH:mm"
        return f.string(from: d)
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

/// Nền sọc chéo (kiểu ảnh mẫu) cho cột "Chi tiêu khác" và phần còn trống của thanh hạn mức.
enum Hatch {
    static let orange = pattern(base: UIColor(red: 0.93, green: 0.42, blue: 0.21, alpha: 1), stripe: UIColor(red: 0.98, green: 0.62, blue: 0.45, alpha: 1))
    static let gray = pattern(base: UIColor(white: 0.5, alpha: 0.12), stripe: UIColor(white: 0.5, alpha: 0.28))

    private static func pattern(base: UIColor, stripe: UIColor) -> ImagePaint {
        let size: CGFloat = 8
        let img = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            base.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            stripe.setStroke()
            let p = UIBezierPath()
            p.lineWidth = 2
            // Ba đường chéo để mẫu nối liền khi lặp lại
            for o in [-size, 0, size] {
                p.move(to: CGPoint(x: o, y: size))
                p.addLine(to: CGPoint(x: o + size, y: 0))
            }
            p.stroke()
        }
        return ImagePaint(image: Image(uiImage: img), scale: 1)
    }
}
