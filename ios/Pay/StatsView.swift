import Charts
import SwiftUI

/// Thống kê theo tháng, kiểu bảng điều khiển tài chính nền tối (luôn tối, kể cả khi máy đang ở nền sáng): thẻ than viền mảnh,
/// màu nhấn vàng chanh và xanh ngọc. Tổng chi + cột 6 tháng + bốn số liệu, hạn mức, chi vào đâu, các khoản gần đây.
struct StatsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var month = Date()
    /// Trang 6 tháng đang hiện trên thanh chọn tháng (0 = 6 tháng gần nhất, 1 = 6 tháng trước đó, ...)
    @State private var page: Int? = 0
    /// Đang dựng phim giới thiệu (xem Film.swift)
    @Environment(\.film) private var film

    private let cal = Calendar.current

    // Bảng màu của màn hình này (một bộ duy nhất: màn này luôn tối)
    static let page = Color(hex: 0x0B0C0F)
    static let card = Color(hex: 0x14161B)
    static let line = Color.white.opacity(0.09)          // viền thẻ, vạch ngăn
    static let lime = Color(hex: 0xD7F93B), cyan = Color(hex: 0x4FE0E6)
    static let ink = Color(hex: 0xD7F93B)                // tab đang chọn
    static let inkText = Color(hex: 0x0B0C0F)
    static let chip = Color.white.opacity(0.07)
    static let bad = Color(hex: 0xFF6B81)                // chi tăng
    /// Màu của các danh mục trong "Chi vào đâu", theo thứ hạng
    static let slices: [Color] = [lime, cyan, Color(hex: 0xA78BFA), Color(hex: 0xFF9F43), Color(hex: 0xFF6B9D), Color(hex: 0x8A8F9C)]

    var body: some View {
        let items = store.monthItems(month)
        let prev = comparable(store.monthItems(cal.date(byAdding: .month, value: -1, to: month)!))
        if film != nil {
            // Phim: thanh tiêu đề và vùng cuộn tự vẽ (xem Film.swift)
            VStack(spacing: 0) {
                FilmNavBar(title: L("Thống kê"), grabber: true)
                FilmScroll { content(items, prev) }
            }
            .background(Self.page)
            .environment(\.colorScheme, .dark)
        } else {
        NavigationStack {
            ScrollView { content(items, prev) }
            .background(Self.page.ignoresSafeArea())
            .navigationTitle(L("Thống kê"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        // Không có nút Xong: vạch ngang trên cùng cho biết kéo xuống là đóng
        .sheetGrabber()
        .environment(\.colorScheme, .dark)
        }
    }

    private func content(_ items: [Expense], _ prev: [Expense]) -> some View {
        VStack(spacing: 14) {
            monthTabs
            hero(items, prev)
            limitCard(items)
            if !items.isEmpty {
                categoryCard(items)
                recentCard(items)
            }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 32)
    }

    // MARK: Chọn tháng (dạng tab, tháng đang chọn là viên thuốc đậm)

    /// Tháng cuối của trang đang xem.
    private var windowEnd: Date { cal.date(byAdding: .month, value: -6 * (page ?? 0), to: Date())! }

    /// 6 tháng của một trang, cũ trước mới sau.
    private func months(page p: Int) -> [Date] {
        let end = cal.date(byAdding: .month, value: -6 * p, to: Date())!
        return (0..<6).reversed().map { cal.date(from: cal.dateComponents([.year, .month], from: cal.date(byAdding: .month, value: -$0, to: end)!))! }
    }

    private var windowMonths: [Date] { months(page: page ?? 0) }

    /// Số trang: lùi đến tháng có khoản chi đầu tiên, ít nhất 2 trang (12 tháng).
    private var pageCount: Int {
        guard let first = store.items.min(by: { $0.t < $1.t })?.date else { return 2 }
        let back = cal.dateComponents([.month], from: cal.date(from: cal.dateComponents([.year, .month], from: first))!,
                                      to: cal.date(from: cal.dateComponents([.year, .month], from: Date()))!).month ?? 0
        return max(2, back / 6 + 1)
    }

    @ViewBuilder private var monthTabs: some View {
        if film != nil {
            HStack(spacing: 6) { ForEach(months(page: 0), id: \.self) { m in monthTab(m) } }
        } else { pagedMonthTabs }
    }

    private var pagedMonthTabs: some View {
        // Vuốt ngang để đổi trang 6 tháng; mỗi trang vừa khít chiều ngang nên không bị cắt chữ
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach((0..<pageCount).reversed(), id: \.self) { p in
                    HStack(spacing: 6) {
                        ForEach(months(page: p), id: \.self) { m in monthTab(m) }
                    }
                    .padding(.horizontal, 1)
                    .containerRelativeFrame(.horizontal)
                    .id(p)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .defaultScrollAnchor(.trailing)
        .onChange(of: page) {
            // Vuốt sang trang khác: tháng đang xem nhảy về tháng mới nhất của trang đó
            if !windowMonths.contains(where: { isSelected($0) }) { month = windowMonths.last! }
        }
    }

    private func monthTab(_ m: Date) -> some View {
        let on = isSelected(m)
        let otherYear = cal.component(.year, from: m) != cal.component(.year, from: Date())
        return Button { month = m } label: {
            VStack(spacing: 0) {
                Text(shortMonth(m)).font(.system(size: 15, weight: on ? .semibold : .regular))
                if otherYear { Text(String(cal.component(.year, from: m))).font(.system(size: 10)).opacity(0.8) }
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .foregroundStyle(on ? Self.inkText : Color.secondary)
            .background(on ? Self.ink : .clear, in: Capsule())
            // Tháng chưa chọn: ô than viền mảnh
            .background(on ? Color.clear : Self.card, in: Capsule())
            .overlay { if !on { Capsule().strokeBorder(Self.line, lineWidth: 1) } }
            .contentShape(Capsule())
        }
        .buttonStyle(Pressable())
    }

    // MARK: Thẻ chính: tổng chi tháng, cột 6 tháng, bốn số liệu

    private struct MonthBar: Identifiable {
        let date: Date
        let bills: Int
        let other: Int
        var id: Date { date }
        var total: Int { bills + other }
    }

    private func hero(_ items: [Expense], _ prev: [Expense]) -> some View {
        let total = sum(items)
        // Cùng khung 6 tháng với thanh chọn tháng; tháng đang xem được tô rõ
        let bars: [MonthBar] = windowMonths.map { m in
            let its = store.monthItems(m)
            let bills = sum(its.filter { $0.c == "hd" })
            return MonthBar(date: m, bills: bills, other: sum(its) - bills)
        }
        let top = max(bars.map(\.total).max() ?? 0, 1)
        let gap = Double(top) * 0.025   // khe hở giữa hai đoạn của cùng một cột
        let days = isRunning ? cal.component(.day, from: Date()) : cal.range(of: .day, in: .month, for: month)!.count
        let prevDays = isRunning ? days : cal.range(of: .day, in: .month, for: cal.date(byAdding: .month, value: -1, to: month)!)!.count
        let avg = total / max(days, 1), prevAvg = sum(prev) / max(prevDays, 1)
        let biggest = items.max { $0.a < $1.a }
        let today = store.total(on: Date()), yesterday = store.total(on: cal.date(byAdding: .day, value: -1, to: Date())!)
        return card {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(fmt(total)).font(.system(size: 34, weight: .bold)).kerning(-0.8).minimumScaleFactor(0.5).lineLimit(1)
                Text("đ").font(.system(size: 18, weight: .semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let d = delta(total, sum(prev)) { change(d, isRunning ? L("so với cùng kỳ") : L("so với tháng trước")) }
            }
            Text(L("Tổng chi %@", Lang.isEnglish ? monthName(month) : monthName(month).lowercased()))
                .font(.system(size: 13)).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Spacer()
                legend(AnyShapeStyle(Self.cyan), L("Chi tiêu khác"))
                legend(AnyShapeStyle(Self.lime), L("Hoá đơn"))
            }
            .padding(.top, 6)
            Chart(bars) { b in
                if b.bills > 0 {
                    BarMark(x: .value("Tháng", b.date, unit: .month), yStart: .value("Từ", 0), yEnd: .value("Hoá đơn", b.bills), width: .ratio(0.42))
                        .foregroundStyle(Self.lime)
                        .cornerRadius(5)
                        .opacity(isSelected(b.date) ? 1 : 0.4)
                }
                if b.other > 0 {
                    let start = b.bills > 0 ? Double(b.bills) + gap : 0
                    BarMark(x: .value("Tháng", b.date, unit: .month), yStart: .value("Từ", start), yEnd: .value("Chi tiêu khác", start + Double(b.other)), width: .ratio(0.42))
                        .foregroundStyle(Hatch.cyan)
                        .cornerRadius(5)
                        .opacity(isSelected(b.date) ? 1 : 0.4)
                }
            }
            // Giữ đủ 6 tháng trên trục kể cả tháng chưa có khoản chi nào
            .chartXScale(domain: bars.first!.date...cal.date(byAdding: .month, value: 1, to: bars.last!.date)!)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { v in
                    AxisValueLabel(centered: true) { if let d = v.as(Date.self) { Text(shortMonth(d)).foregroundStyle(Color.white.opacity(0.45)) } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel { if let n = v.as(Double.self) { Text(short(Int(n))).foregroundStyle(Color.white.opacity(0.45)) } }
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
            .frame(height: 190)
            .padding(.top, 4)

            Rectangle().fill(Self.line).frame(height: 1).padding(.top, 10)
            // Bốn số liệu, hai hàng hai cột, ngăn bằng vạch mảnh
            Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    if isRunning {
                        figure(L("Hôm nay"), "\(fmt(today))đ", delta: delta(today, yesterday), note: L("chưa có để so"))
                    } else {
                        let active = Set(items.map { cal.component(.day, from: $0.date) }).count
                        figure(L("Ngày có chi"), "\(active)/\(days)", delta: nil, note: L("%ld%% số ngày", active * 100 / max(days, 1)))
                    }
                    figure(L("TB mỗi ngày"), "\(fmt(avg / 1000 * 1000))đ", delta: delta(avg, prevAvg), note: L("chưa có để so"))
                }
                GridRow {
                    figure(L("Lớn nhất"), biggest.map { "\(fmt($0.a))đ" } ?? "0đ", delta: nil,
                           note: biggest.map { $0.n?.isEmpty == false ? $0.n!.capFirst : Category.get($0.c).name } ?? L("chưa có"))
                    figure(L("Số khoản"), "\(items.count)", delta: delta(items.count, prev.count), note: L("chưa có để so"))
                }
            }
            .padding(.top, 6)
        }
    }

    /// Một số liệu: tên nhỏ, con số, dòng thay đổi (hoặc ghi chú nếu không có gì để so)
    private func figure(_ title: String, _ value: String, delta d: Int?, note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(size: 20, weight: .bold)).minimumScaleFactor(0.5).lineLimit(1)
            if let d { change(d, nil) } else { Text(note).font(.system(size: 12)).foregroundStyle(.tertiary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Phần trăm thay đổi. Chi tăng là xấu: mũi tên lên màu hồng đỏ, giảm thì vàng chanh (có mũi tên, không chỉ dựa vào màu).
    private func change(_ d: Int, _ suffix: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: d > 0 ? "arrow.up.right" : "arrow.down.right").font(.system(size: 10, weight: .bold))
            Text("\(abs(d))%").font(.system(size: 12, weight: .semibold))
            if let suffix { Text(suffix).font(.system(size: 12)).foregroundStyle(.secondary) }
        }
        .foregroundStyle(d > 0 ? Self.bad : Self.lime)
        .lineLimit(1)
    }

    // MARK: Hạn mức tháng

    /// Hạn mức của tháng đang xem (mức đặt cho tháng đó). Tháng cũ chưa từng đặt thì ẩn hẳn thẻ.
    @ViewBuilder private func limitCard(_ items: [Expense]) -> some View {
        let spent = sum(items)
        let limit = store.budget(for: month)
        if limit != nil || isRunning {
            card {
                Text(L("Hạn mức chi tháng")).font(.system(size: 16, weight: .semibold))
                if let limit {
                    let left = limit - spent
                    Text(left >= 0 ? L("Còn %@đ", fmt(left)) : L("Vượt %@đ", fmt(-left))).font(.system(size: 13)).foregroundStyle(.secondary)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(spent > limit ? AnyShapeStyle(Self.bad)
                                                         : AnyShapeStyle(LinearGradient(colors: [Self.cyan, Self.lime], startPoint: .leading, endPoint: .trailing)))
                                .frame(width: max(10, g.size.width * min(Double(spent) / Double(max(limit, 1)), 1)))
                        }
                    }
                    .frame(height: 10).padding(.top, 8)
                    HStack {
                        Text("\(fmt(spent))đ"); Spacer(); Text("\(fmt(limit))đ")
                    }
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 2)
                } else {
                    Text(L("Chưa đặt hạn mức. Vào Cài đặt › Ngân sách để đặt.")).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func isSelected(_ d: Date) -> Bool { cal.isDate(d, equalTo: month, toGranularity: .month) }

    private func legend(_ style: AnyShapeStyle, _ title: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(style).frame(width: 8, height: 8)
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    // MARK: Chi vào đâu: một dải nhiều màu theo danh mục, dưới là danh sách kèm phần trăm

    private func categoryCard(_ items: [Expense]) -> some View {
        let total = max(sum(items), 1)
        let byCat = Dictionary(grouping: items, by: \.c).mapValues(sum)
        let ranked = Category.all.filter { (byCat[$0.k] ?? 0) > 0 }.sorted { byCat[$0.k]! > byCat[$1.k]! }
        func color(_ i: Int) -> Color { Self.slices[min(i, Self.slices.count - 1)] }
        return card {
            Text(L("Chi vào đâu")).font(.system(size: 16, weight: .semibold))
            Text(L("Theo danh mục")).font(.system(size: 13)).foregroundStyle(.secondary)
            GeometryReader { g in
                // Mỗi danh mục một đoạn, rộng theo phần trăm (ít nhất 6pt để vẫn thấy), cách nhau 3pt
                let room = g.size.width - 3 * CGFloat(max(ranked.count - 1, 0))
                HStack(spacing: 3) {
                    ForEach(Array(ranked.enumerated()), id: \.offset) { i, c in
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color(i))
                            .frame(width: max(6, room * CGFloat(byCat[c.k]!) / CGFloat(total)))
                    }
                }
                .frame(width: g.size.width, alignment: .leading).clipped()
            }
            .frame(height: 12).padding(.top, 8)
            VStack(spacing: 12) {
                ForEach(Array(ranked.enumerated()), id: \.offset) { i, c in
                    let v = byCat[c.k]!
                    HStack(spacing: 10) {
                        Circle().fill(color(i)).frame(width: 8, height: 8)
                        Text(c.name).font(.system(size: 15))
                        Spacer()
                        Text("\(fmt(v))đ").font(.system(size: 14)).foregroundStyle(.secondary)
                        Text("\(Int((Double(v) / Double(total) * 100).rounded()))%").font(.system(size: 15, weight: .semibold))
                            .frame(width: 44, alignment: .trailing)
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
                Text(L("Khoản chi gần đây")).font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(L("%ld khoản", items.count)).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(rows) { e in
                    let c = Category.get(e.c)
                    HStack(spacing: 12) {
                        CategoryIcon(c: c, size: 20).frame(width: 34, height: 34)
                            .background(c.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.n?.isEmpty == false ? e.n!.capFirst : c.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
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
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Self.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Self.line, lineWidth: 1) }
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
        if Lang.isEnglish {
            let f = DateFormatter()
            f.locale = Lang.locale
            f.dateFormat = c.year == cal.component(.year, from: Date()) ? "LLLL" : "LLLL yyyy"
            return f.string(from: d)
        }
        return c.year == cal.component(.year, from: Date()) ? "Tháng \(c.month!)" : "Tháng \(c.month!)/\(c.year!)"
    }

    private func shortMonth(_ d: Date) -> String {
        guard Lang.isEnglish else { return "T\(cal.component(.month, from: d))" }
        let f = DateFormatter()
        f.locale = Lang.locale
        f.dateFormat = "LLL"   // "Oct"
        return f.string(from: d)
    }

    private func when(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Lang.locale
        f.dateFormat = Lang.isEnglish ? "MMM d, HH:mm" : "dd/MM HH:mm"
        return f.string(from: d)
    }

    /// 1250000 -> "1,3tr", 45000 -> "45k" (tiếng Anh: "1.3M", "45k")
    private func short(_ n: Int) -> String {
        if n >= 1_000_000 {
            let v = Double(n) / 1e6
            if Lang.isEnglish {
                let t = v >= 10 ? String(Int(v.rounded())) : String(format: "%.1f", v)
                return (t.hasSuffix(".0") ? String(t.dropLast(2)) : t) + "M"
            }
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
    /// Sọc chéo mực trên nền trong, và chấm bi mực: hoạ tiết của các cột danh mục ở Thống kê
    static let ink = pattern(base: UIColor(white: 0.09, alpha: 0.1), stripe: UIColor(white: 0.09, alpha: 0.55))
    /// Sọc chéo xanh ngọc: phần "Chi tiêu khác" của cột tháng ở Thống kê
    static let cyan = pattern(base: UIColor(red: 0.31, green: 0.88, blue: 0.90, alpha: 0.55), stripe: UIColor(red: 0.31, green: 0.88, blue: 0.90, alpha: 1))
    static let dots: ImagePaint = {
        let size: CGFloat = 7, f = UIGraphicsImageRendererFormat(); f.scale = 3
        let img = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: f).image { ctx in
            UIColor(white: 0.09, alpha: 0.08).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            UIColor(white: 0.09, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 2.2, y: 2.2, width: 2.6, height: 2.6)).fill()
        }
        return ImagePaint(image: Image(uiImage: img), scale: 1)
    }()

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
