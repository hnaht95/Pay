import Charts
import SwiftUI

/// Thống kê theo tháng, kiểu bảng điều khiển màu pastel: bảng xám xanh tổng chi với các cột danh mục có hoạ tiết,
/// dải vàng hạn mức, bốn ô số liệu, đường xu hướng 6 tháng, chi theo danh mục và các khoản gần đây.
struct StatsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var month = Date()
    /// Trang 6 tháng đang hiện trên thanh chọn tháng (0 = 6 tháng gần nhất, 1 = 6 tháng trước đó, ...)
    @State private var page: Int? = 0
    /// Đang dựng phim giới thiệu (xem Film.swift)
    @Environment(\.film) private var film

    private let cal = Calendar.current

    // Bảng màu của màn hình này
    static let page = Color(light: 0xF3F4F8, dark: 0x0D0D10)
    // Ba màu pastel của các bảng (giữ nguyên ở nền tối, chữ trên đó luôn màu mực)
    static let panel = Color(hex: 0xD6DEE8), yellow = Color(hex: 0xEEF0A0), mint = Color(hex: 0xD5E3D0)
    static let mark = Color(hex: 0x16161A)
    static let card = Color(light: 0xFFFFFF, dark: 0x1C1C1F)
    static let ink = Color(light: 0x1C1C1E, dark: 0xF2F2F2)          // cột "Hoá đơn", tab đang chọn
    static let inkText = Color(light: 0xFFFFFF, dark: 0x111114)
    static let orange = Color(light: 0xEE6A35, dark: 0xF07443)
    static let chip = Color(light: 0xF2F2F2, dark: 0x2A2A2E)

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
        } else {
        NavigationStack {
            ScrollView { content(items, prev) }
            .background(Self.page.ignoresSafeArea())
            .navigationTitle(L("Thống kê"))
            .navigationBarTitleDisplayMode(.inline)
        }
        // Không có nút Xong: vạch ngang trên cùng cho biết kéo xuống là đóng
        .sheetGrabber()
        }
    }

    private func content(_ items: [Expense], _ prev: [Expense]) -> some View {
        VStack(spacing: 20) {
            monthTabs
            hero(items, prev)
            limitBanner(items)
            grid(items, prev)
            trendCard
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
            .frame(maxWidth: .infinity, minHeight: 40)
            .foregroundStyle(on ? Self.inkText : Color.secondary)
            .background(on ? Self.ink : .clear, in: Capsule())
            // Tháng chưa chọn: viên thuốc chỉ có viền mảnh
            .overlay { if !on { Capsule().strokeBorder(Color.primary.opacity(0.22), lineWidth: 1) } }
            .contentShape(Capsule())
        }
        .buttonStyle(Pressable())
    }

    // MARK: Bảng xám xanh: tổng chi tháng + cột của các danh mục chi nhiều nhất

    private func hero(_ items: [Expense], _ prev: [Expense]) -> some View {
        let total = sum(items)
        let byCat = Dictionary(grouping: items, by: \.c).mapValues(sum)
        let top = Array(Category.all.filter { (byCat[$0.k] ?? 0) > 0 }.sorted { byCat[$0.k]! > byCat[$1.k]! }.prefix(4))
        let peak = max(top.first.map { byCat[$0.k]! } ?? 1, 1)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Tổng chi %@", Lang.isEnglish ? monthName(month) : monthName(month).lowercased()))
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(fmt(total)).font(.system(size: 36, weight: .bold)).kerning(-1).minimumScaleFactor(0.5).lineLimit(1)
                        Text("đ").font(.system(size: 20, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    if let d = delta(total, sum(prev)) {
                        Label("\(abs(d))% " + (isRunning ? L("so với cùng kỳ") : L("so với tháng trước")), systemImage: d > 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").font(.system(size: 20, weight: .semibold))
            }
            if !top.isEmpty {
                // Mỗi danh mục một cột, cao theo số tiền, mỗi cột một hoạ tiết: chuyển màu, sọc chéo, chấm bi, đen đặc
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(top.enumerated()), id: \.offset) { i, c in
                        let v = byCat[c.k]!
                        VStack(alignment: .leading, spacing: 2) {
                            Text(short(v)).font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                            Text(c.name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous)
                                .fill(Self.texture(i))
                                .frame(height: (34 + 86 * CGFloat(v) / CGFloat(peak)).rounded())
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.panel, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .environment(\.colorScheme, .light)
    }

    private static func texture(_ i: Int) -> AnyShapeStyle {
        switch i % 4 {
        case 0: AnyShapeStyle(LinearGradient(colors: [mark, mark.opacity(0.12)], startPoint: .top, endPoint: .bottom))
        case 1: AnyShapeStyle(Hatch.ink)
        case 2: AnyShapeStyle(Hatch.dots)
        default: AnyShapeStyle(mark)
        }
    }

    // MARK: Dải vàng: hạn mức tháng

    /// Hạn mức của tháng đang xem (mức đặt cho tháng đó). Tháng cũ chưa từng đặt thì ẩn hẳn dải.
    @ViewBuilder private func limitBanner(_ items: [Expense]) -> some View {
        let spent = sum(items)
        let limit = store.budget(for: month)
        if limit != nil || isRunning {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    if let limit {
                        let left = limit - spent
                        Text(left >= 0 ? L("Còn %@đ", fmt(left)) : L("Vượt %@đ", fmt(-left))).font(.system(size: 17, weight: .semibold))
                        Text(L("Đã dùng %ld%% hạn mức %@", spent * 100 / max(limit, 1), short(limit)))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Self.mark.opacity(0.12))
                                Capsule().fill(spent > limit ? Color(hex: 0xD92D20) : Self.mark)
                                    .frame(width: max(5, g.size.width * min(Double(spent) / Double(max(limit, 1)), 1)))
                            }
                        }
                        .frame(height: 5).padding(.top, 5)
                    } else {
                        Text(L("Hạn mức chi tháng")).font(.system(size: 17, weight: .semibold))
                        Text(L("Chưa đặt hạn mức. Vào Cài đặt › Ngân sách để đặt.")).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.right").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 48, height: 48).background(Self.mark, in: Circle())
            }
            .padding(.leading, 22).padding(.trailing, 10).padding(.vertical, 12)
            .background(Self.yellow, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .environment(\.colorScheme, .light)
        }
    }

    // MARK: Ô số liệu 2×2, mỗi ô một màu

    private func grid(_ items: [Expense], _ prev: [Expense]) -> some View {
        let days = isRunning ? cal.component(.day, from: Date()) : cal.range(of: .day, in: .month, for: month)!.count
        let prevDays = isRunning ? days : cal.range(of: .day, in: .month, for: cal.date(byAdding: .month, value: -1, to: month)!)!.count
        let avg = sum(items) / max(days, 1), prevAvg = sum(prev) / max(prevDays, 1)
        let biggest = items.max { $0.a < $1.a }
        let today = store.total(on: Date()), yesterday = store.total(on: cal.date(byAdding: .day, value: -1, to: Date())!)
        // Grid: hai ô cùng hàng cao bằng nhau, chiều cao theo nội dung (không chừa chỗ trống)
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
            if isRunning {
                tile(L("Hôm nay"), "\(fmt(today))đ", delta: delta(today, yesterday), note: L("chưa có để so"), bg: Self.panel)
            } else {
                let active = Set(items.map { cal.component(.day, from: $0.date) }).count
                tile(L("Ngày có chi"), "\(active)/\(days)", delta: nil, note: L("%ld%% số ngày", active * 100 / max(days, 1)), bg: Self.panel)
            }
            tile(L("TB mỗi ngày"), "\(fmt(avg / 1000 * 1000))đ", delta: delta(avg, prevAvg), note: L("chưa có để so"), bg: Self.mint)
            }
            GridRow {
            tile(L("Lớn nhất"), biggest.map { "\(fmt($0.a))đ" } ?? "0đ", delta: nil,
                 note: biggest.map { $0.n?.isEmpty == false ? $0.n!.capFirst : Category.get($0.c).name } ?? L("chưa có"), bg: nil)
            tile(L("Số khoản"), "\(items.count)", delta: delta(items.count, prev.count), note: L("chưa có để so"), bg: Self.yellow)
            }
        }
    }

    /// Ô số liệu: con số và mũi tên ở trên, tên bên dưới, dòng cuối là % thay đổi (hoặc ghi chú nếu không có gì để so).
    /// `bg` nil = ô trắng (theo nền sáng / tối); có màu pastel thì chữ luôn màu mực.
    private func tile(_ title: String, _ value: String, delta d: Int?, note: String, bg: Color?) -> some View {
        let body = VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(value).font(.system(size: 22, weight: .bold)).minimumScaleFactor(0.5).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .semibold)).padding(.top, 4)
            }
            Text(title).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
            Group {
                // Có mũi tên và dấu, không chỉ dựa vào màu
                if let d { Label("\(abs(d))%", systemImage: d > 0 ? "arrow.up" : "arrow.down") } else { Text(note) }
            }
            .font(.system(size: 13, weight: .medium)).foregroundStyle(.tertiary).lineLimit(1)
            .padding(.top, 10)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        return Group {
            if let bg { body.background(bg, in: RoundedRectangle(cornerRadius: 26, style: .continuous)).environment(\.colorScheme, .light) }
            else { body.background(Self.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous)) }
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
        struct Point: Identifiable { let id: String; let date: Date; let value: Int; let series: String }
        let points = bars.map { Point(id: "t\($0.date)", date: $0.date, value: $0.total, series: "total") }
            + bars.map { Point(id: "b\($0.date)", date: $0.date, value: $0.bills, series: "bills") }
        let picked = bars.first { isSelected($0.date) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(L("Chi 6 tháng")).font(.system(size: 17, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 17, weight: .semibold))
            }
            HStack(spacing: 14) {
                legend(AnyShapeStyle(Self.mark), L("Tổng chi"))
                legend(AnyShapeStyle(Self.mark.opacity(0.4)), L("Hoá đơn"))
                Spacer()
            }
            // Hai đường: tổng chi (liền, đậm) và hoá đơn (đứt, nhạt); tháng đang xem có chấm và nhãn vàng
            Chart {
                ForEach(points) { pt in
                    LineMark(x: .value("Tháng", pt.date, unit: .month), y: .value("Số tiền", pt.value), series: .value("Loại", pt.series))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(pt.series == "total" ? Self.mark : Self.mark.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: pt.series == "total" ? 2.5 : 2, lineCap: .round, dash: pt.series == "total" ? [] : [5, 5]))
                }
                if let picked, picked.total > 0 {
                    PointMark(x: .value("Tháng", picked.date, unit: .month), y: .value("Số tiền", picked.total))
                        .foregroundStyle(Self.mark).symbolSize(90)
                        .annotation(position: .top, spacing: 6) {
                            Text(short(picked.total)).font(.system(size: 13, weight: .bold))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Self.yellow, in: Capsule())
                        }
                }
            }
            .chartYScale(domain: 0...Double(top) * 1.25)
            // Giữ đủ 6 tháng trên trục kể cả tháng chưa có khoản chi nào
            .chartXScale(domain: bars.first!.date...cal.date(byAdding: .month, value: 1, to: bars.last!.date)!)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { v in
                    AxisValueLabel(centered: true) { if let d = v.as(Date.self) { Text(shortMonth(d)) } }
                }
            }
            .chartYAxis(.hidden)
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
            .padding(.top, 8)

            // Trung bình / Thấp nhất / Cao nhất của các tháng có chi
            if !used.isEmpty {
                HStack(spacing: 0) {
                    stat(L("Trung bình"), used.reduce(0, +) / used.count)
                    Divider().frame(height: 36)
                    stat(L("Thấp nhất"), used.min()!)
                    Divider().frame(height: 36)
                    stat(L("Cao nhất"), used.max()!)
                }
                .padding(.top, 12)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.panel, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .environment(\.colorScheme, .light)
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
            Circle().fill(style).frame(width: 10, height: 10)
            Text(title).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    // MARK: Theo danh mục

    private func categoryCard(_ items: [Expense]) -> some View {
        let total = max(sum(items), 1)
        let byCat = Dictionary(grouping: items, by: \.c).mapValues(sum)
        let ranked = Category.all.filter { (byCat[$0.k] ?? 0) > 0 }.sorted { byCat[$0.k]! > byCat[$1.k]! }
        return card {
            Text(L("Theo danh mục")).font(.system(size: 17, weight: .semibold))
            VStack(spacing: 22) {
                ForEach(ranked) { c in
                    let v = byCat[c.k]!
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            CategoryIcon(c: c, size: 22).frame(width: 38, height: 38).background(c.color, in: Circle())
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
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Self.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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
