import Charts
import SwiftUI

/// Thống kê theo tháng, kiểu "Analytics" nền sáng với màu nhấn vàng chanh: tên tháng có mũi tên lùi / tới, hàng lọc theo
/// danh mục, cột 6 tháng (tháng đang xem màu chanh, có số ở đầu cột), hàng ô số liệu lướt ngang, hạn mức, chi vào đâu,
/// các khoản gần đây.
struct StatsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var month = Date()
    /// Chỉ xem một danh mục (nil = tất cả)
    @State private var cat: String?
    /// Đang dựng phim giới thiệu (xem Film.swift)
    @Environment(\.film) private var film

    private let cal = Calendar.current

    // Bảng màu của màn hình này
    static let page = Color(light: 0xF2F2F2, dark: 0x0D0D10)
    static let card = Color(light: 0xFFFFFF, dark: 0x1C1C1F)
    static let lime = Color(hex: 0xC2F230)                         // màu nhấn; chữ trên nền này luôn màu mực
    static let limeInk = Color(hex: 0x111114)
    static let bar = Color(light: 0xC6C6C8, dark: 0x4A4A50)        // cột của các tháng khác
    static let chip = Color(light: 0xF2F2F2, dark: 0x2A2A2E)
    /// Màu của các danh mục trong "Chi vào đâu", theo thứ hạng
    static let slices: [Color] = [lime, Color(hex: 0x4FD1DB), Color(hex: 0xA78BFA), Color(hex: 0xFF9F43), Color(hex: 0xFF6B9D), Color(hex: 0x9AA0AB)]

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
        VStack(spacing: 12) {
            chartCard(items)
            figures(items, prev)
            if cat == nil { limitCard(items) }
            if !items.isEmpty {
                if cat == nil { categoryCard(items) }
                recentCard(items)
            }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 32)
    }

    // MARK: Thẻ chính: tên tháng, lọc danh mục, cột 6 tháng

    /// 6 tháng kết thúc ở tháng đang xem, cũ trước mới sau
    private var windowMonths: [Date] {
        (0..<6).reversed().map { cal.date(from: cal.dateComponents([.year, .month], from: cal.date(byAdding: .month, value: -$0, to: month)!))! }
    }

    private func step(_ by: Int) {
        guard let m = cal.date(byAdding: .month, value: by, to: month), m <= Date() || cal.isDate(m, equalTo: Date(), toGranularity: .month) else { return }
        withAnimation(.snappy) { month = m }
    }

    private func chartCard(_ items: [Expense]) -> some View {
        let totals = windowMonths.map { sum(only(store.monthItems($0))) }
        let top = max(totals.max() ?? 0, 1)
        // Danh mục có chi trong 6 tháng này (nhiều tiền trước), để lọc
        let spent = Dictionary(grouping: windowMonths.flatMap { store.monthItems($0) }, by: \.c).mapValues(sum)
        let cats = Category.all.filter { (spent[$0.k] ?? 0) > 0 }.sorted { spent[$0.k]! > spent[$1.k]! }
        return VStack(spacing: 14) {
            // Tên tháng, hai bên là lùi / tới một tháng
            HStack {
                arrow("chevron.left", L("Tháng trước")) { step(-1) }.filmPressed(film?.pressed["stats-prev"] ?? 0)
                Spacer()
                Text(monthName(month)).font(.system(size: 24, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                arrow("chevron.right", L("Tháng sau")) { step(1) }.opacity(isRunning ? 0.3 : 1).disabled(isRunning)
            }
            // Lọc: tất cả, hoặc một danh mục (đang chọn thì màu chanh, có dấu × để bỏ)
            FilmScroll(axes: .horizontal) {
                HStack(spacing: 8) {
                    Button { withAnimation(.snappy) { cat = nil } } label: {
                        Image(systemName: "square.grid.2x2").font(.system(size: 15, weight: .semibold))
                            .frame(width: 40, height: 38)
                            .foregroundStyle(cat == nil ? Self.limeInk : Color.secondary)
                            .background(cat == nil ? Self.lime : Self.chip, in: Capsule())
                    }
                    .buttonStyle(Pressable()).accessibilityLabel(L("Tất cả danh mục"))
                    ForEach(cats) { c in
                        let on = cat == c.k
                        Button { withAnimation(.snappy) { cat = on ? nil : c.k } } label: {
                            HStack(spacing: 6) {
                                Text(c.name).font(.system(size: 15, weight: on ? .semibold : .regular)).lineLimit(1)
                                if on { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                            }
                            .padding(.horizontal, 14).frame(height: 38)
                            .foregroundStyle(on ? Self.limeInk : Color.secondary)
                            .background(on ? Self.lime : Self.chip, in: Capsule())
                        }
                        .buttonStyle(Pressable())
                        .filmPressed(film?.pressed["stats-cat-" + c.k] ?? 0)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)

            // Cột 6 tháng: số tiền ở đầu cột, nối xuống bằng nét đứt; tháng đang xem màu chanh. Chạm cột để xem tháng đó
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(windowMonths.enumerated()), id: \.offset) { i, m in
                    let on = isSelected(m), v = totals[i]
                    Button { withAnimation(.snappy) { month = m } } label: {
                        VStack(spacing: 5) {
                            Text(v > 0 ? short(v) : "0").font(.system(size: on ? 13 : 12, weight: on ? .bold : .regular))
                                .foregroundStyle(on ? Color.primary : Color.secondary.opacity(0.7)).lineLimit(1).minimumScaleFactor(0.7)
                            DashedStem().stroke(on ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .frame(width: 1, height: 22)
                            UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 5, style: .continuous)
                                .fill(on ? Self.lime : Self.bar)
                                // Vạch ngang ở đỉnh cột, rộng hơn cột một chút
                                .overlay(alignment: .top) { Capsule().fill(on ? Self.lime : Self.bar).frame(height: 4).padding(.horizontal, -4).offset(y: -2) }
                                .frame(width: 30, height: (6 + 150 * CGFloat(v) / CGFloat(top)).rounded())
                            Text(shortMonth(m)).font(.system(size: 14, weight: on ? .semibold : .regular))
                                .foregroundStyle(on ? Color.primary : Color.secondary).padding(.top, 5)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(monthName(m)): \(fmt(v))")
                }
            }
            .frame(height: 235, alignment: .bottom)
        }
        .padding(16)
        .background(Self.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func arrow(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38).background(Self.chip, in: Circle()).foregroundStyle(.primary)
        }
        .buttonStyle(Pressable()).accessibilityLabel(label)
    }

    private struct DashedStem: Shape {
        func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); return p }
    }

    // MARK: Hàng ô số liệu, lướt ngang

    private func figures(_ items: [Expense], _ prev: [Expense]) -> some View {
        let total = sum(items)
        let days = isRunning ? cal.component(.day, from: Date()) : cal.range(of: .day, in: .month, for: month)!.count
        let biggest = items.max { $0.a < $1.a }
        let d = delta(total, sum(prev))
        return FilmScroll(axes: .horizontal) {
            HStack(spacing: 10) {
                figure("doc.text", items.isEmpty ? "0đ" : "\(short(total / items.count))", L("TB mỗi khoản"))
                if let d {
                    figure(d > 0 ? "arrow.up" : "arrow.down", (d > 0 ? L("Tăng %ld%%", d) : L("Giảm %ld%%", -d)), isRunning ? L("so với cùng kỳ") : L("so với tháng trước"))
                }
                figure("calendar", "\(short(total / max(days, 1) / 1000 * 1000))", L("TB mỗi ngày"))
                figure("arrow.up.forward", biggest.map { short($0.a) } ?? "0", L("Lớn nhất"))
                figure("list.bullet", "\(items.count)", L("Số khoản"))
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }

    private func figure(_ icon: String, _ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium))
                .frame(width: 38, height: 38).background(Self.chip, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .padding(.bottom, 10)
            Text(value).font(.system(size: 20, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
        .frame(width: 132, alignment: .leading)
        .background(Self.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: Hạn mức tháng

    /// Hạn mức của tháng đang xem (mức đặt cho tháng đó). Tháng cũ chưa từng đặt thì ẩn hẳn thẻ.
    @ViewBuilder private func limitCard(_ items: [Expense]) -> some View {
        let spent = sum(items)
        let limit = store.budget(for: month)
        if limit != nil || isRunning {
            card {
                Text(L("Hạn mức chi tháng")).font(.system(size: 17, weight: .semibold))
                if let limit {
                    let left = limit - spent
                    Text(left >= 0 ? L("Còn %@đ", fmt(left)) : L("Vượt %@đ", fmt(-left))).font(.system(size: 14)).foregroundStyle(.secondary)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Self.chip)
                            Capsule().fill(spent > limit ? Color(hex: 0xE5484D) : Self.lime)
                                .frame(width: max(20, g.size.width * min(Double(spent) / Double(max(limit, 1)), 1)))
                        }
                    }
                    .frame(height: 20).padding(.top, 10)
                    HStack {
                        Text("\(fmt(spent))đ"); Spacer(); Text("\(fmt(limit))đ")
                    }
                    .font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 4)
                } else {
                    Text(L("Chưa đặt hạn mức. Vào Cài đặt › Ngân sách để đặt.")).font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func isSelected(_ d: Date) -> Bool { cal.isDate(d, equalTo: month, toGranularity: .month) }

    // MARK: Chi vào đâu: một dải nhiều màu theo danh mục, dưới là danh sách (chạm một dòng để lọc theo danh mục đó)

    private func categoryCard(_ items: [Expense]) -> some View {
        let total = max(sum(items), 1)
        let byCat = Dictionary(grouping: items, by: \.c).mapValues(sum)
        let ranked = Category.all.filter { (byCat[$0.k] ?? 0) > 0 }.sorted { byCat[$0.k]! > byCat[$1.k]! }
        func color(_ i: Int) -> Color { Self.slices[min(i, Self.slices.count - 1)] }
        return card {
            Text(L("Chi vào đâu")).font(.system(size: 17, weight: .semibold))
            GeometryReader { g in
                // Mỗi danh mục một đoạn, rộng theo phần trăm (ít nhất 10pt để vẫn thấy), cách nhau 3pt
                let room = g.size.width - 3 * CGFloat(max(ranked.count - 1, 0))
                HStack(spacing: 3) {
                    ForEach(Array(ranked.enumerated()), id: \.offset) { i, c in
                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color(i))
                            .frame(width: max(10, room * CGFloat(byCat[c.k]!) / CGFloat(total)))
                    }
                }
                .frame(width: g.size.width, alignment: .leading).clipped()
            }
            .frame(height: 24).padding(.top, 8)
            VStack(spacing: 0) {
                ForEach(Array(ranked.enumerated()), id: \.offset) { i, c in
                    let v = byCat[c.k]!
                    Button { withAnimation(.snappy) { cat = c.k } } label: {
                        HStack(spacing: 10) {
                            Circle().fill(color(i)).frame(width: 9, height: 9)
                            Text(c.name).font(.system(size: 16))
                            Text("\(Int((Double(v) / Double(total) * 100).rounded()))%").font(.system(size: 13)).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(fmt(v))đ").font(.system(size: 15, weight: .semibold))
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 13).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < ranked.count - 1 { Divider() }
                }
            }
            .padding(.top, 6)
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
            .background(Self.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
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
