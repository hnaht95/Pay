import Charts
import SwiftUI

/// Thống kê theo tháng, phẳng và gọn nhưng có khung: các phần nằm trong thẻ phẳng bo 28 như ô ở trang chủ (không bóng, không
/// chuyển màu), nút có nền tròn, mỗi số liệu một biểu tượng nét mảnh, danh mục mang biểu tượng và màu của chính nó, tháng đang xem màu xanh lá của app.
struct StatsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var month = Date()
    /// Chỉ xem một danh mục (nil = tất cả)
    @State private var cat: String?
    /// Đang dựng phim giới thiệu (xem Film.swift)
    @Environment(\.film) private var film

    private let cal = Calendar.current

    static let page = Palette.bg
    /// Cột của các tháng không được chọn, vạch ngăn
    static let bar = Color(light: 0xD3D6DD, dark: 0x34343B)
    static let rule = Color.primary.opacity(0.1)
    /// Màu nhấn: xanh lá của biểu tượng app
    static let accent = Color(hex: 0x61BE6E)

    var body: some View {
        let items = only(store.monthItems(month))
        let prev = comparable(only(store.monthItems(cal.date(byAdding: .month, value: -1, to: month)!)))
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

    /// Các khoản của danh mục đang lọc (không lọc thì giữ nguyên)
    private func only(_ items: [Expense]) -> [Expense] { cat.map { c in items.filter { $0.c == c } } ?? items }

    private func content(_ items: [Expense], _ prev: [Expense]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            hero(items, prev).padding(.top, 6)
            chart
            figures(items, prev)
            let all = store.monthItems(month)
            if !all.isEmpty {
                heading(L("Danh mục"), L("Chạm để lọc"))
                categories(all)
            }
            if !items.isEmpty {
                heading(L("Gần đây"), items.count == 1 ? L("1 khoản") : L("%d khoản", items.count))
                recent(items)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 32)
    }

    /// Tiêu đề mục như ở màn hình chính: chữ đậm bên trái, viên thuốc xám bên phải
    private func heading(_ title: String, _ note: String) -> some View {
        HStack {
            Text(title).font(.system(size: 21, weight: .bold))
            Spacer()
            Text(note).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Palette.pill, in: Capsule())
        }
        .padding(.top, 14)
    }

    /// Thẻ phẳng: nền xám nhạt bo 28, không bóng
    private func panel<C: View>(_ pad: CGFloat = 20, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(pad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: Tổng chi của tháng (đổi tháng bằng hai mũi tên), so với trước, ngân sách

    private func step(_ by: Int) {
        guard let m = cal.date(byAdding: .month, value: by, to: month), m <= Date() || cal.isDate(m, equalTo: Date(), toGranularity: .month) else { return }
        withAnimation(.snappy) { month = m }
    }

    private func hero(_ items: [Expense], _ prev: [Expense]) -> some View {
        let total = sum(items)
        return panel { VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                arrow("chevron.left", L("Tháng trước")) { step(-1) }
                Text(monthName(month)).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                arrow("chevron.right", L("Tháng sau")) { step(1) }.opacity(isRunning ? 0.25 : 1).disabled(isRunning)
                Spacer()
                // Đang lọc một danh mục: tên danh mục, chạm để bỏ lọc
                if let cat {
                    Button { withAnimation(.snappy) { self.cat = nil } } label: {
                        HStack(spacing: 6) {
                            Circle().fill(Category.get(cat).chart).frame(width: 9, height: 9)
                            Text(Category.get(cat).name).font(.system(size: 15, weight: .semibold))
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(Pressable())
                }
            }
            Text(fmt(total)).font(.system(size: 46, weight: .bold)).kerning(-1.5).minimumScaleFactor(0.5).lineLimit(1)
                .contentTransition(.numericText())
                .padding(.top, 14)
            HStack(spacing: 6) {
                if let d = delta(total, sum(prev)) {
                    // Có mũi tên, không chỉ dựa vào màu
                    Label("\(abs(d))% " + (isRunning ? L("so với cùng kỳ") : L("so với tháng trước")), systemImage: d > 0 ? "arrow.up" : "arrow.down")
                } else {
                    Text(items.count == 1 ? L("1 khoản") : L("%d khoản", items.count))
                }
            }
            .font(.system(size: 15)).foregroundStyle(.secondary).padding(.top, 2)
            // Ngân sách của tháng đang xem (chỉ khi xem tất cả danh mục), cùng thanh với màn hình chính
            if cat == nil, let limit = store.budget(for: month) {
                let b = BudgetStatus(budget: limit, spent: total)
                VStack(alignment: .leading, spacing: 8) {
                    BudgetBar(s: b, height: 6, track: Self.bar)
                    HStack {
                        Text(b.remaining >= 0 ? L("Còn %@", fmt(b.remaining)) : L("Vượt %@", fmt(-b.remaining)))
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(b.level == .over ? Palette.danger : .primary)
                        Spacer()
                        Text(L("Ngân sách %@", fmt(b.budget))).font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 18)
            }
        } }
    }

    private func arrow(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(.primary)
                .frame(width: 36, height: 36).background(Palette.pill, in: Circle())
        }
        .buttonStyle(Pressable()).accessibilityLabel(label)
    }

    // MARK: Cột 6 tháng

    /// 6 tháng kết thúc ở tháng đang xem, cũ trước mới sau
    private var windowMonths: [Date] {
        (0..<6).reversed().map { cal.date(from: cal.dateComponents([.year, .month], from: cal.date(byAdding: .month, value: -$0, to: month)!))! }
    }

    /// Mỗi tháng một cột phẳng, số tiền ở đầu cột; tháng đang xem màu chữ chính, các tháng khác xám. Chạm cột để xem tháng đó
    private var chart: some View {
        let totals = windowMonths.map { sum(only(store.monthItems($0))) }
        let top = max(totals.max() ?? 0, 1)
        return panel(16) { HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(windowMonths.enumerated()), id: \.offset) { i, m in
                let on = isSelected(m), v = totals[i]
                Button { withAnimation(.snappy) { month = m } } label: {
                    VStack(spacing: 6) {
                        Text(v > 0 ? short(v) : "0").font(.system(size: 13, weight: on ? .bold : .regular))
                            .foregroundStyle(on ? Color.primary : Color.secondary).lineLimit(1).minimumScaleFactor(0.7)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(on ? Self.accent : Self.bar)
                            .frame(height: (4 + 120 * CGFloat(v) / CGFloat(top)).rounded())
                        Text(shortMonth(m)).font(.system(size: 14, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(monthName(m)): \(fmt(v))")
            }
        }
        .frame(height: 172, alignment: .bottom) }
    }

    private func isSelected(_ d: Date) -> Bool { cal.isDate(d, equalTo: month, toGranularity: .month) }

    // MARK: Bốn ô số liệu, mỗi ô một biểu tượng nét mảnh

    private func figures(_ items: [Expense], _ prev: [Expense]) -> some View {
        let total = sum(items)
        let days = isRunning ? cal.component(.day, from: Date()) : cal.range(of: .day, in: .month, for: month)!.count
        let biggest = items.max { $0.a < $1.a }
        let active = Set(items.map { cal.component(.day, from: $0.date) }).count
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                figure("calendar", L("TB mỗi ngày"), fmt(total / max(days, 1) / 1000 * 1000))
                figure("doc.text", L("TB mỗi khoản"), items.isEmpty ? "0" : fmt(total / items.count / 1000 * 1000))
            }
            GridRow {
                figure("arrow.up.right", L("Lớn nhất"), biggest.map { fmt($0.a) } ?? "0")
                figure("checkmark.circle", L("Ngày có chi"), "\(active)/\(days)")
            }
        }
    }

    private func figure(_ icon: String, _ title: String, _ value: String) -> some View {
        panel(16) {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: icon).font(.system(size: 16, weight: .medium))
                    .frame(width: 38, height: 38).background(Palette.pill, in: Circle())
                    .padding(.bottom, 12)
                Text(title).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
                Text(value).font(.system(size: 22, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }

    // MARK: Danh mục: biểu tượng trên nền màu của danh mục, tên, phần trăm, số tiền, thanh mảnh cùng màu.
    // Chạm để chỉ xem danh mục đó, chạm lần nữa để bỏ

    private func categories(_ all: [Expense]) -> some View {
        let total = max(sum(all), 1)
        let byCat = Dictionary(grouping: all, by: \.c).mapValues(sum)
        let ranked = Category.all.filter { (byCat[$0.k] ?? 0) > 0 }.sorted { byCat[$0.k]! > byCat[$1.k]! }
        return panel(8) {
            VStack(spacing: 0) {
                ForEach(ranked) { c in
                    let v = byCat[c.k]!, on = cat == c.k
                    Button { withAnimation(.snappy) { cat = on ? nil : c.k } } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(c: c, size: 22).frame(width: 42, height: 42).background(c.color, in: Circle())
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(c.name).font(.system(size: 17, weight: .semibold))
                                    Text("\(Int((Double(v) / Double(total) * 100).rounded()))%").font(.system(size: 14)).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(fmt(v)).font(.system(size: 17, weight: .semibold))
                                }
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Self.bar)
                                        Capsule().fill(c.chart).frame(width: max(5, g.size.width * CGFloat(v) / CGFloat(total)))
                                    }
                                }
                                .frame(height: 5)
                            }
                        }
                        .foregroundStyle(.primary)
                        .padding(12)
                        // Đang lọc danh mục này: dòng có nền; các dòng khác mờ đi
                        .background(on ? Palette.pill : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .contentShape(Rectangle())
                        .opacity(cat == nil || on ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                    .filmPressed(film?.pressed["stats-cat-" + c.k] ?? 0)
                }
            }
        }
    }

    // MARK: Khoản chi gần đây: cùng kiểu hàng với màn hình chính

    private func recent(_ items: [Expense]) -> some View {
        VStack(spacing: 10) {
            ForEach(items.sorted { $0.t > $1.t }.prefix(6)) { e in
                ExpenseRow(e: e, showDay: true, repeats: store.rule(for: e) != nil)
            }
        }
    }

    // MARK: Phụ

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
