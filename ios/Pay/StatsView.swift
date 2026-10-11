import Charts
import SwiftUI

/// Thống kê theo tháng, kiểu bảng điều khiển: thẻ cam tổng chi, các ô số liệu, hạn mức, biểu đồ 6 tháng,
/// chi theo danh mục và các khoản gần đây.
struct StatsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var month = Date()
    /// Trang 6 tháng đang hiện trên thanh chọn tháng (0 = 6 tháng gần nhất, 1 = 6 tháng trước đó, ...)
    @State private var page: Int? = 0
    /// Xem theo tuần / tháng / năm
    /// Tuần đang xem (ngày đầu tuần, thứ Hai) và trang tuần trên thanh ngày (0 = tuần này)
    @State private var week = Self.wcal.dateInterval(of: .weekOfYear, for: Date())!.start
    /// Lịch tuần đang mở rộng ra cả tháng, và tháng đang hiện khi mở rộng
    /// Ngày đang nằm giữa dải ngày cuộn ngang (để biết đang xem tháng nào)
    @State private var centerDay: Date? = Calendar.current.startOfDay(for: Date())
    /// Mờ mép trái / phải của dải ngày (chỉ khi còn ngày khuất bên đó; mở ra ở hôm nay nên mép phải không mờ)
    @State private var stripFade = [true, false]
    /// Dải trên cùng đang xem theo ngày (false) hay theo tháng (true)
    @State private var byMonth = false
    /// Một ngày được chọn trong tuần (nil = cả tuần)
    @State private var day: Date?
    /// Đang dựng phim giới thiệu (xem Film.swift)
    @Environment(\.film) private var film

    private let cal = Calendar.current
    /// Lịch tuần bắt đầu từ thứ Hai
    static let wcal: Calendar = { var c = Calendar.current; c.firstWeekday = 2; return c }()

    enum Scope { case week, month }

    /// Thu gọn: xem theo tuần; mở rộng lịch ra cả tháng: xem theo tháng (phim giới thiệu luôn xem theo tháng)
    private var scope: Scope { .month }

    // Bảng màu của màn hình này
    static let page = Color(light: 0xEFEFEF, dark: 0x1C1C1E)   // tối: sáng hơn nền màn chính (0D0D10) để tấm sheet tách khỏi màn phía sau
    static let card = Color(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let ink = Color(light: 0x1C1C1E, dark: 0xF2F2F2)          // cột "Hoá đơn", tab đang chọn
    static let inkText = Color(light: 0xFFFFFF, dark: 0x111114)
    static let orange = Color(light: 0xEE6A35, dark: 0xF07443)
    static let chip = Color(light: 0xF2F2F2, dark: 0x3A3A3C)
    /// Khung Tổng chi kiểu bảng màu retro: nền pistachio, chữ xanh lá đậm, viên % / biểu tượng nền xanh chữ kem
    /// (giữ nguyên ở chế độ tối: nền sáng nổi trên trang tối vẫn đọc rõ)
    static let heroBg = Color(hex: 0xC9D9A4)
    static let heroInk = Color(hex: 0x1F6B47)
    static let heroPill = Color(hex: 0xE8F0D2)

    var body: some View {
        let items = spending(in: span)
        let prev = comparable(spending(in: prevSpan))
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
            .softTopEdge()
            .background(Self.page.ignoresSafeArea())
            .screenTitle(L("Thống kê"))

            .navigationBarTitleDisplayMode(.inline)
        }
        // Không có nút Xong: vạch ngang trên cùng cho biết kéo xuống là đóng
        .sheetGrabber()
        }
    }

    private func content(_ items: [Expense], _ prev: [Expense]) -> some View {
        VStack(spacing: 20) {
            if film != nil { monthTabs } else { periodHeader }
            hero(items, prev)
            grid(items, prev)
            if !items.isEmpty {
                categoryCard(items)
                recentCard(items)
            }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 32)
    }

    // MARK: Đầu trang: khoảng ngày + Hôm nay, chọn Tuần / Tháng / Năm, rồi thanh chọn ngày / tháng / năm

    private var periodHeader: some View { weekStrip }

    /// Ngày đầu tuần của trang tuần p (0 = tuần này, 1 = tuần trước, ...)
    private func weekStart(page p: Int) -> Date {
        let now = Self.wcal.dateInterval(of: .weekOfYear, for: Date())!.start
        return cal.date(byAdding: .day, value: -7 * p, to: now)!
    }

    // MARK: Dải ngày cuộn ngang
    //
    // Một dải liền mạch từ ngày có khoản chi đầu tiên tới hôm nay (mở ra ở hôm nay). Mỗi ngày một viên to, dễ chạm:
    // thứ, ngày, và một cột nhỏ cao theo số tiền đã chi. Cuộn sang tháng nào thì số liệu bên dưới tính theo tháng đó;
    // chạm một ngày để xem riêng ngày ấy, chạm lại để về cả tháng.

    private static let pillWidth: CGFloat = 50
    /// Viên ngày / tháng cao bằng nhau ở cả hai dải
    private static let pillHeight: CGFloat = 108

    private var weekStrip: some View {
        let today = cal.startOfDay(for: Date())
        let first = cal.startOfDay(for: store.items.min(by: { $0.t < $1.t })?.date ?? today)
        let from = min(first, cal.date(byAdding: .day, value: -60, to: today)!)
        let count = (cal.dateComponents([.day], from: from, to: today).day ?? 0) + 1
        let days = (0..<count).map { cal.date(byAdding: .day, value: $0, to: from)! }
        let byDay = store.items.reduce(into: [Date: Int]()) { m, e in m[cal.startOfDay(for: e.date), default: 0] += e.a }
        // Mốc 90%: một ngày trả tiền nhà không làm mọi cột khác lùn tịt (ngày vượt mốc thì cột đầy)
        let sorted = byDay.values.sorted()
        let top = max(sorted.isEmpty ? 1 : sorted[min(sorted.count - 1, sorted.count * 9 / 10)], 1)
        let shown = centerDay ?? today
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(byMonth ? String(cal.component(.year, from: month)) : monthYear(shown)).font(.system(size: 17, weight: .semibold))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: monthYear(shown))
                Spacer()
                if (!byMonth && (!cal.isDate(shown, equalTo: today, toGranularity: .month) || (day != nil && !cal.isDateInToday(day!))))
                    || (byMonth && !cal.isDate(month, equalTo: today, toGranularity: .month)) {
                    Button { withAnimation(.snappy) { goToday() } } label: {
                        Text(L("Hôm nay")).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12).frame(height: 30)
                            .background(Capsule().fill(Self.card))
                    }
                    .buttonStyle(Pressable())
                    .transition(.opacity)
                }
            }
            .frame(height: 30)
            .padding(.horizontal, 20)
            if byMonth { monthStrip } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 6) {
                    ForEach(days, id: \.self) { d in dayPill(d, spent: byDay[d] ?? 0, top: top).id(d) }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centerDay, anchor: .center)
            .defaultScrollAnchor(.trailing)
            .frame(height: Self.pillHeight + 20)
            .modifier(ChipEdges(fade: $stripFade))
            // Rung nhẹ mỗi khi một ngày lướt qua giữa dải, như bánh xe chọn giờ của iOS
            .sensoryFeedback(.selection, trigger: centerDay)
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [stripFade[0] ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing).frame(width: 32)
                    Color.black
                    LinearGradient(colors: [.black, stripFade[1] ? .clear : .black], startPoint: .leading, endPoint: .trailing).frame(width: 32)
                }
            }
            }
            // Công tắc Ngày / Tháng ngay dưới dải, giữa màn
            scopeToggle.frame(maxWidth: .infinity)
        }
        // Không nền thẻ, dải ngày tràn ra hai mép màn hình (bù lại lề 16 của trang); chữ tiêu đề vẫn thẳng lề
        .padding(.horizontal, -16)
        .onChange(of: centerDay) {
            // Cuộn sang tháng khác: số liệu theo tháng đó; ngày đang chọn ở tháng khác thì bỏ chọn
            guard let c = centerDay, !cal.isDate(c, equalTo: month, toGranularity: .month) else { return }
            showMonth(c)
            if let d = day, !cal.isDate(d, equalTo: c, toGranularity: .month) { day = nil }
        }
    }

    private static let todayTint = Color(light: 0x3FA65A, dark: 0x7FD08B)

    /// Viên ngày: thứ nhỏ, số ngày; lớp nền trong dâng cao theo mức chi.
    /// Đang chọn: nền đậm, chữ trắng; hôm nay: số xanh lá; ngày 1: ghi tháng thay cho thứ để thấy chỗ sang tháng.
    /// Nút chuyển dải trên cùng giữa Ngày và Tháng (hai chữ trong một viên, phần đang chọn nền đen)
    private var scopeToggle: some View {
        HStack(spacing: 2) {
            ForEach([false, true], id: \.self) { m in
                let on = byMonth == m
                Button {
                    withAnimation(.snappy) {
                        byMonth = m
                        day = nil
                    }
                } label: {
                    Text(m ? L("Tháng") : L("Ngày")).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? Self.inkText : Color.primary.opacity(0.6))
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Capsule().fill(on ? Self.ink : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Self.card))
        .sensoryFeedback(.selection, trigger: byMonth)
    }

    /// Dải theo tháng: mỗi tháng một viên như dải ngày (tên tháng trên, lớp xám dâng theo mức chi), chạm để xem tháng đó
    private var monthStrip: some View {
        let months = allMonths
        let totals = months.map { sum(spending(in: cal.dateInterval(of: .month, for: $0)!)) }
        let used = totals.filter { $0 > 0 }.sorted(by: >)
        let top = max(used.count > 1 && used[0] > used[1] * 2 ? used[1] : (used.first ?? 1), 1)
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 6) {
                    ForEach(Array(months.enumerated()), id: \.element) { i, m in monthPill(m, spent: totals[i], top: top).id(m) }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.trailing)
            .frame(height: Self.pillHeight + 20)
            .onChange(of: month) {
                withAnimation(.snappy) { proxy.scrollTo(cal.date(from: cal.dateComponents([.year, .month], from: month))!, anchor: .center) }
            }
        }
    }

    private func monthPill(_ m: Date, spent: Int, top: Int) -> some View {
        let on = isSelected(m)
        let now = cal.isDate(m, equalTo: Date(), toGranularity: .month)
        let r = min(sqrt(Double(spent) / Double(top)), 1)
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                day = nil
                showMonth(m)
                let last = cal.date(byAdding: .day, value: -1, to: cal.dateInterval(of: .month, for: m)!.end)!
                centerDay = cal.startOfDay(for: min(last, Date()))
            }
        } label: {
            VStack(spacing: 6) {
                // Hàng năm nằm ngoài viên, cùng kiểu hàng thứ của dải ngày
                Text(String(cal.component(.year, from: m)))
                    .font(.system(size: 11, weight: on ? .bold : .medium))
                    .foregroundStyle(Color.primary.opacity(on ? 0.75 : 0.4))
                VStack(spacing: 0) {
                    Text(shortMonth(m))
                        .font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(on ? Self.inkText : now ? Self.todayTint : Color.primary.opacity(0.8))
                        .frame(height: 24)
                        .padding(.top, 8)
                    GeometryReader { g in
                        if spent > 0 {
                            let h = max(8, g.size.height * r)
                            UnevenRoundedRectangle(topLeadingRadius: min(8, h / 2), topTrailingRadius: min(8, h / 2), style: .continuous)
                                .fill(on ? Self.inkText.opacity(0.22) : Color.primary.opacity(0.09))
                                .frame(height: h)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                    }
                    .padding(4)
                }
                .frame(width: Self.pillWidth, height: Self.pillHeight)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(on ? Self.ink : Self.card))
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(Pressable())
        .sensoryFeedback(.selection, trigger: on)
    }

    private func dayPill(_ d: Date, spent: Int, top: Int) -> some View {
        let on = day.map { cal.isDate($0, inSameDayAs: d) } ?? false
        let today = cal.isDateInToday(d)
        let r = min(sqrt(Double(spent) / Double(top)), 1)
        let firstOfMonth = cal.component(.day, from: d) == 1
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                if on { day = nil } else {
                    day = d
                    if !cal.isDate(d, equalTo: month, toGranularity: .month) { showMonth(d) }
                }
            }
        } label: {
            VStack(spacing: 6) {
                // Hàng thứ nằm ngoài viên
                Text(firstOfMonth ? shortMonth(d) : weekdayShort(d))
                    .font(.system(size: 11, weight: firstOfMonth || on ? .bold : .medium))
                    .foregroundStyle(Color.primary.opacity(firstOfMonth || on ? 0.75 : 0.4))
                // Viên: số ngày ở trên cùng; phần dưới số là chỗ lớp xanh dâng lên theo mức chi, không bao giờ trùm lên số
                VStack(spacing: 0) {
                    Text("\(cal.component(.day, from: d))")
                        .font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(on ? Self.inkText : today ? Self.todayTint : Color.primary.opacity(0.8))
                        .frame(height: 24)
                        .padding(.top, 8)
                    GeometryReader { g in
                        if spent > 0 {
                            // Cắt theo khung bo góc cao hết phần dưới số: lúc thấp, góc dưới vẫn khớp góc viên ngoài
                            // (tự bo theo chiều cao của lớp xanh thì lớp thấp thành viên thuốc, lệch góc)
                            let h = max(8, g.size.height * r)
                            UnevenRoundedRectangle(topLeadingRadius: min(8, h / 2), topTrailingRadius: min(8, h / 2), style: .continuous)
                                .fill(on ? Self.inkText.opacity(0.22) : Color.primary.opacity(0.09))
                                .frame(height: h)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                    }
                    .padding(4)
                }
                .frame(width: Self.pillWidth, height: Self.pillHeight)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(on ? Self.ink : Self.card))
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(Pressable())
    }

    /// "Tháng 10 năm 2026" (tiếng Anh: "October 2026")
    private func monthYear(_ d: Date) -> String {
        if Lang.isEnglish {
            let f = DateFormatter(); f.locale = Lang.locale; f.dateFormat = "LLLL yyyy"
            return f.string(from: d)
        }
        return "Tháng \(cal.component(.month, from: d)) năm \(cal.component(.year, from: d))"
    }

    private func goToday() {
        day = nil
        centerDay = cal.startOfDay(for: Date())
        showMonth(Date())
    }

    /// Tháng hiện trên lịch mở rộng cũng là tháng đang xem (và trang 6 tháng của biểu đồ chứa nó)
    private func showMonth(_ d: Date) {
        month = d
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        page = max(0, (cal.dateComponents([.month], from: cal.date(from: cal.dateComponents([.year, .month], from: d))!, to: start).month ?? 0) / 6)
    }

    /// "06.10 – 12.10.2026"; một ngày: "Thứ Hai, 13.10.2026"
    private var rangeLabel: String {
        let i = span
        let f = DateFormatter()
        f.locale = Lang.locale
        if unit == .day { f.dateFormat = "dd.MM.yyyy"; return "\(dayName(i.start, long: true)), \(f.string(from: i.start))" }
        let last = cal.date(byAdding: .day, value: -1, to: i.end)!
        f.dateFormat = "dd.MM"
        let a = f.string(from: i.start)
        f.dateFormat = "dd.MM.yyyy"
        return "\(a) – \(f.string(from: last))"
    }

    /// "T2".."CN" (tiếng Anh: "Mon")
    private func weekdayShort(_ d: Date) -> String {
        let w = cal.component(.weekday, from: d)
        guard Lang.isEnglish else { return w == 1 ? "CN" : "T\(w)" }
        let f = DateFormatter(); f.locale = Lang.locale; f.dateFormat = "EEE"
        return f.string(from: d)
    }

    /// long: "Thứ Hai" / short: "thứ Hai 13/10" (tiếng Anh: "Monday" / "Mon, Oct 13")
    private func dayName(_ d: Date, long: Bool) -> String {
        let w = cal.component(.weekday, from: d)
        if Lang.isEnglish {
            let f = DateFormatter(); f.locale = Lang.locale; f.dateFormat = long ? "EEEE" : "EEE, MMM d"
            return f.string(from: d)
        }
        let names = ["Chủ nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"]
        if long { return names[w - 1] }
        if cal.isDateInToday(d) { return "hôm nay" }
        return "\(names[w - 1].lowercased()) \(cal.component(.day, from: d))/\(cal.component(.month, from: d))"
    }

    // MARK: Chọn tháng (dạng tab, tháng đang chọn là viên thuốc đậm)

    /// 6 tháng của một trang, cũ trước mới sau.
    private func months(page p: Int) -> [Date] {
        // Lùi từ ngày 1 của tháng này, không lùi từ hôm nay: ngày 29–31 lùi 24 hay 30 tháng có khi rơi sang 1/3
        // thay vì cuối tháng 2 (lỗi của Foundation), làm cả trang lệch một tháng
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        return (0..<6).reversed().map { cal.date(byAdding: .month, value: -(6 * p + $0), to: start)! }
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
            HStack(spacing: 2) { ForEach(months(page: 0), id: \.self) { m in monthTab(m) } }
                .padding(4).background(Self.card, in: Capsule())
        } else { pagedMonthTabs }
    }

    private var pagedMonthTabs: some View {
        // Vuốt ngang để đổi trang 6 tháng; mỗi trang vừa khít chiều ngang nên không bị cắt chữ
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach((0..<pageCount).reversed(), id: \.self) { p in
                    HStack(spacing: 2) {
                        ForEach(months(page: p), id: \.self) { m in monthTab(m) }
                    }
                    .padding(4)
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
        .background(Self.card, in: Capsule())
        .clipShape(Capsule())
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
            .contentShape(Capsule())
        }
        .buttonStyle(Pressable())
    }

    // MARK: Thẻ cam: tổng chi tháng

    private func hero(_ items: [Expense], _ prev: [Expense]) -> some View {
        let total = sum(items)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(heroTitle).font(.system(size: 16, weight: .medium))
                Spacer()
                iconChip("creditcard", fg: Self.heroBg, bg: Self.heroInk)
            }
            Text(fmt(total)).font(.system(size: 40, weight: .bold)).kerning(-1).minimumScaleFactor(0.5).lineLimit(1)
            if let d = delta(total, sum(prev)) {
                HStack(spacing: 8) {
                    // 0% (kể cả do làm tròn) không phải tăng cũng không phải giảm: không vẽ mũi tên
                    Group {
                        if d == 0 { Text(verbatim: "0%") } else { Label("\(abs(d))%", systemImage: d > 0 ? "arrow.up" : "arrow.down") }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Self.heroPill)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Self.heroInk, in: Capsule())
                    Text(compareText)
                        .font(.system(size: 13))
                }
            }
            // Gộp từ thẻ "Chi theo tháng" cũ (trùng số tiền với khung này): vạch hạn mức (tháng này) và ngày không chi
            if scope == .month && day == nil {
                budgetLine(spent: total)
                noSpendLine
            }
        }
        .foregroundStyle(Self.heroInk)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.heroBg, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Ô số liệu 2×2

    private func grid(_ items: [Expense], _ prev: [Expense]) -> some View {
        let days = isRunning ? elapsedDays + 1 : dayCount(span)
        let prevDays = isRunning ? days : dayCount(prevSpan)
        let avg = sum(items) / max(days, 1), prevAvg = sum(prev) / max(prevDays, 1)
        let biggest = items.max { $0.a < $1.a }
        let today = store.total(on: Date()), yesterday = store.total(on: cal.date(byAdding: .day, value: -1, to: Date())!)
        // Grid: hai ô cùng hàng cao bằng nhau, chiều cao theo nội dung (không chừa chỗ trống)
        return Grid(horizontalSpacing: 14, verticalSpacing: 14) {
            // Xem một ngày: bỏ hàng "Hôm nay / TB mỗi ngày" (không có nghĩa với một ngày)
            if unit != .day {
            GridRow {
            if isRunning {
                tile(.tangerine, L("Hôm nay"), "sun.max", "\(fmt(today))", delta: delta(today, yesterday), note: L("chưa có để so"))
            } else {
                let active = Set(items.map { cal.startOfDay(for: $0.date) }).count
                tile(.tangerine, L("Ngày có chi"), "calendar", "\(active)/\(days)", delta: nil, note: L("%ld%% số ngày", active * 100 / max(days, 1)))
            }
            tile(.mustard, L("TB mỗi ngày"), "chart.line.flattrend.xyaxis", "\(fmt(avg / 1000 * 1000))", delta: delta(avg, prevAvg), note: L("chưa có để so"))
            }
            }
            GridRow {
            tile(.river, L("Lớn nhất"), "arrow.up.forward.circle", biggest.map { "\(fmt($0.a))" } ?? "0", delta: nil,
                 note: biggest.map { $0.n?.isEmpty == false ? $0.n! : Category.get($0.c).name } ?? L("chưa có"))
            tile(.tomato, L("Số khoản"), "list.bullet", "\(items.count)", delta: delta(items.count, prev.count), note: L("chưa có để so"))
            }
        }
    }

    /// Ô số liệu tối giản: tên + biểu tượng, con số, và luôn một nhãn ở đáy: % nếu có so sánh, không thì nhãn xám ghi note.
    /// Nhờ vậy hai ô cùng hàng luôn cao bằng nhau mà không ô nào bị trống đáy.
    /// Bộ ba màu kiểu bảng màu retro cho một ô: nền nhạt, chữ đậm cùng họ, và màu nhấn cho biểu tượng / nhãn %
    /// (giữ nguyên ở chế độ tối: nền sáng nổi trên trang tối vẫn đọc rõ)
    struct Tone {
        let bg: Color, ink: Color, accent: Color, onAccent: Color
        static let tangerine = Tone(bg: Color(hex: 0xF8D5B4), ink: Color(hex: 0x8A3A10), accent: Color(hex: 0xEC7A2B), onAccent: Color(hex: 0xFFF4E0))
        static let mustard = Tone(bg: Color(hex: 0xF7DF96), ink: Color(hex: 0x1F3F6E), accent: Color(hex: 0x1F3F6E), onAccent: Color(hex: 0xF7DF96))
        static let river = Tone(bg: Color(hex: 0xC8DBEF), ink: Color(hex: 0x1F4E8C), accent: Color(hex: 0x1F4E8C), onAccent: Color(hex: 0xDCE9F7))
        static let tomato = Tone(bg: Color(hex: 0xF6C8BC), ink: Color(hex: 0x8A2414), accent: Color(hex: 0xE2462E), onAccent: Color(hex: 0xFFE9DF))
    }

    private func tile(_ tone: Tone, _ title: String, _ icon: String, _ value: String, delta d: Int?, note: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Biểu tượng tròn căn giữa theo chiều dọc với chữ tiêu đề nhỏ bên trái
            HStack(alignment: .center) {
                Text(title).font(.system(size: 14)).foregroundStyle(tone.ink.opacity(0.8)).lineLimit(1)
                Spacer(minLength: 4)
                iconChip(icon, fg: tone.onAccent, bg: tone.accent)
            }
            Text(value).font(.system(size: 22, weight: .bold)).foregroundStyle(tone.ink).minimumScaleFactor(0.5).lineLimit(1)
            if let d { deltaPill(d, tone) } else { notePill(note, tone) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tone.bg, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Nhãn %: mũi tên lên = chi tăng, xuống = chi giảm.
    /// 0% (kể cả do làm tròn) không phải tăng cũng không phải giảm: nhãn xám, không mũi tên.
    @ViewBuilder private func deltaPill(_ d: Int, _ tone: Tone) -> some View {
        if d == 0 {
            notePill("0%", tone)
        } else {
            // Màu theo bảng màu của ô; tăng / giảm đọc qua mũi tên
            Label("\(abs(d))%", systemImage: d > 0 ? "arrow.up" : "arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tone.onAccent)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(tone.accent, in: Capsule())
        }
    }

    /// Nhãn xám cùng cỡ với nhãn %, cho ô không có gì để so.
    private func notePill(_ text: String, _ tone: Tone) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tone.ink)
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(tone.ink.opacity(0.1), in: Capsule())
    }

    // MARK: Biểu đồ 6 tháng: Hoá đơn (đậm) + Chi tiêu khác (cam sọc)

    private struct MonthBar: Identifiable {
        let date: Date
        let bills: Int
        let other: Int
        var id: Date { date }
        var total: Int { bills + other }
    }

    /// Biểu đồ theo kiểu xem: tuần -> 7 ngày, tháng -> 6 tháng của thanh chọn tháng, năm -> 12 tháng của năm
    @ViewBuilder private var trendCard: some View {
        switch scope {
        case .week:
            let start = Self.wcal.dateInterval(of: .weekOfYear, for: week)!.start
            trend(L("Chi trong tuần"), (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }, unit: .day, label: weekdayShort,
                  selected: { d in day.map { cal.isDate($0, inSameDayAs: d) } ?? true },
                  tap: { d in if d <= Date() { day = d } })
        case .month:
            monthTrend
        }
    }

    // MARK: Chi theo tháng — số lớn của tháng đang xem + dải cột tháng vuốt ngang (chạm cột để chọn tháng)

    private var monthTrend: some View {
        let months = allMonths
        let totals = months.map { sum(spending(in: cal.dateInterval(of: .month, for: $0)!)) }
        let used = totals.filter { $0 > 0 }
        let avg = used.isEmpty ? 0 : used.reduce(0, +) / used.count
        // Mốc chiều cao: tháng cao nhất, trừ khi nó vọt hẳn (gấp 2 tháng cao thứ hai) — khi đó cột ấy đầy khung,
        // các tháng khác vẫn so được với nhau
        let sorted = used.sorted(by: >)
        let top = max(sorted.count > 1 && sorted[0] > sorted[1] * 2 ? sorted[1] : (sorted.first ?? 1), 1)
        let current = sum(spending(in: cal.dateInterval(of: .month, for: month)!))
        let vsAvg = avg > 0 ? Int((Double(current - avg) / Double(avg) * 100).rounded()) : 0
        return card {
            Text(L("Chi theo tháng")).font(.system(size: 17, weight: .semibold))
            Group {
                if avg > 0 && current > 0 {
                    Text(monthName(month) + " · " + (vsAvg == 0 ? L("bằng mức trung bình")
                        : vsAvg > 0 ? L("cao hơn TB %ld%%", vsAvg) : L("thấp hơn TB %ld%%", -vsAvg)))
                } else {
                    Text(monthName(month))
                }
            }
            .font(.system(size: 13)).foregroundStyle(.secondary)
            .padding(.top, 2)
            Text(fmt(current))
                .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            budgetLine(spent: current)
            noSpendLine
        }
    }

    /// Ngày không chi tiêu của tháng đang xem: đếm các ngày đã qua (từ ngày bắt đầu dùng app) không có khoản nào,
    /// và ở tháng này thì thêm chuỗi ngày không chi liền nhau tính tới hôm qua. Hôm nay chưa hết nên không tính.
    @ViewBuilder private var noSpendLine: some View {
        let today = cal.startOfDay(for: Date())
        let mStart = cal.dateInterval(of: .month, for: month)!.start
        let mEnd = cal.dateInterval(of: .month, for: month)!.end
        let firstUse = store.items.min(by: { $0.t < $1.t }).map { cal.startOfDay(for: $0.date) } ?? today
        let from = max(mStart, firstUse)
        let to = min(mEnd, today)   // ngày cuối được tính là hôm qua (đang ở tháng này) hoặc ngày cuối tháng
        let spentDays = Set(spending(in: DateInterval(start: from, end: max(from, to))).map { cal.startOfDay(for: $0.date) })
        let total = max(0, cal.dateComponents([.day], from: from, to: to).day ?? 0)
        let free = max(0, total - spentDays.count)
        let streak: Int = {
            guard cal.isDate(month, equalTo: Date(), toGranularity: .month) else { return 0 }
            var n = 0, d = cal.date(byAdding: .day, value: -1, to: today)!
            while d >= firstUse, !spentDays.contains(d), d >= mStart { n += 1; d = cal.date(byAdding: .day, value: -1, to: d)! }
            return n
        }()
        if total > 0 {
            HStack(spacing: 6) {
                chipLabel(free == 0 ? L("Ngày nào cũng có chi") : L("%ld ngày không chi tiêu", free))
                if streak > 0 { chipLabel(L("Chuỗi %ld ngày", streak)) }
            }
            .padding(.top, 2)
        }
    }

    private func chipLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 13, weight: .medium)).foregroundStyle(Self.heroInk)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Self.heroInk.opacity(0.1), in: Capsule())
    }

    /// Hạn mức nằm ngay dưới số tiền: một vạch ngang mảnh đã dùng / hạn mức, kèm còn bao nhiêu và mức nên tiêu mỗi ngày.
    /// Chỉ ở tháng hiện tại và khi đã đặt ngân sách.
    @ViewBuilder private func budgetLine(spent: Int) -> some View {
        if cal.isDate(month, equalTo: Date(), toGranularity: .month), let limit = store.budget(for: month), limit > 0 {
            let over = spent > limit
            let pct = Int((Double(spent) / Double(limit) * 100).rounded())
            let monthDays = cal.range(of: .day, in: .month, for: Date())!.count
            let daysLeft = max(1, monthDays - cal.component(.day, from: Date()) + 1)
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Self.heroInk.opacity(0.15))
                        Capsule().fill(over ? Palette.danger : Self.heroInk)
                            .frame(width: max(6, g.size.width * min(Double(spent) / Double(limit), 1)))
                    }
                }
                .frame(height: 6)
                HStack {
                    Text(L("Đã dùng %ld%% của %@", pct, fmt(limit)))
                        .foregroundStyle(over ? Palette.danger : Self.heroInk.opacity(0.8))
                    Spacer()
                    Text(over ? L("Vượt %@", fmt(spent - limit)) : L("Còn %@/ngày", fmt((limit - spent) / daysLeft / 1000 * 1000)))
                        .foregroundStyle(over ? Palette.danger : Self.heroInk.opacity(0.8))
                }
                .font(.system(size: 13))
            }
            .padding(.top, 4)
        }
    }

    /// Một cột tháng: cột bo góc cao theo mức chi (xám nhạt; tháng đang xem đen), tên tháng ở dưới
    private func monthColumn(_ m: Date, total: Int, top: Int) -> some View {
        let on = isSelected(m)
        // Tháng chưa có dữ liệu: vạch mảnh 4 pt, màu nhạt nhất
        let h = total > 0 ? max(18, 88 * min(Double(total) / Double(top), 1)) : 4
        return Button {
            withAnimation(.snappy) {
                day = nil
                showMonth(m)
                // Dải ngày cuộn tới ngày cuối của tháng đó (tháng này thì tới hôm nay)
                let last = cal.date(byAdding: .day, value: -1, to: cal.dateInterval(of: .month, for: m)!.end)!
                centerDay = cal.startOfDay(for: min(last, Date()))
            }
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    // Ba mức màu: chưa có dữ liệu (nhạt nhất) < có chi < tháng đang xem (đen)
                    .fill(on ? Self.ink : Color.primary.opacity(total > 0 ? 0.1 : 0.04))
                    .frame(width: 40, height: h)
                    .frame(height: 88, alignment: .bottom)
                Text(shortMonth(m))
                    .font(.system(size: 12, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Color.primary : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(Pressable())
        .sensoryFeedback(.selection, trigger: on)
    }

    /// Mọi tháng từ tháng có khoản chi đầu tiên tới tháng này, ít nhất 12 tháng (dữ liệu ít vẫn vuốt được về năm trước)
    private var allMonths: [Date] {
        let now = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        let first = store.items.min(by: { $0.t < $1.t }).map { cal.date(from: cal.dateComponents([.year, .month], from: $0.date))! } ?? now
        let n = max(12, (cal.dateComponents([.month], from: first, to: now).month ?? 0) + 1)
        return (0..<n).reversed().map { cal.date(byAdding: .month, value: -$0, to: now)! }
    }

    private func trend(_ title: String, _ dates: [Date], unit: Calendar.Component, label: @escaping (Date) -> String,
                       selected: @escaping (Date) -> Bool, tap: @escaping (Date) -> Void) -> some View {
        let bars: [MonthBar] = dates.map { m in
            let items = spending(in: cal.dateInterval(of: unit, for: m)!)
            let bills = sum(items.filter { $0.c == "hd" })
            return MonthBar(date: m, bills: bills, other: sum(items) - bills)
        }
        let top = max(bars.map(\.total).max() ?? 0, 1)
        let gap = Double(top) * 0.02   // khe hở giữa hai đoạn của cùng một cột
        let used = bars.filter { $0.total > 0 }.map(\.total)
        return card {
            Text(title).font(.system(size: 17, weight: .semibold))
            HStack(spacing: 14) {
                legend(AnyShapeStyle(Self.ink), L("Hoá đơn"))
                legend(AnyShapeStyle(Self.orange), L("Chi tiêu khác"))
                Spacer()
            }
            .padding(.top, 4)
            Chart(bars) { b in
                if b.bills > 0 {
                    BarMark(x: .value("Tháng", b.date, unit: unit), yStart: .value("Từ", 0), yEnd: .value("Hoá đơn", b.bills), width: .ratio(0.55))
                        .foregroundStyle(Self.ink)
                        .cornerRadius(3)
                        .opacity(selected(b.date) ? 1 : 0.45)
                }
                if b.other > 0 {
                    let start = b.bills > 0 ? Double(b.bills) + gap : 0
                    BarMark(x: .value("Tháng", b.date, unit: unit), yStart: .value("Từ", start), yEnd: .value("Chi tiêu khác", start + Double(b.other)), width: .ratio(0.55))
                        .foregroundStyle(Self.orange)
                        .cornerRadius(3)
                        .opacity(selected(b.date) ? 1 : 0.45)
                }
            }
            // Giữ đủ 6 tháng trên trục kể cả tháng chưa có khoản chi nào
            .chartXScale(domain: bars.first!.date...cal.date(byAdding: unit, value: 1, to: bars.last!.date)!)
            // Nhiều hơn 6 tháng: vuốt ngang để xem các tháng trước, mỗi lần thấy 6 cột (trục số bên trái đứng yên)
            .chartXAxis {
                AxisMarks(values: .stride(by: unit)) { v in
                    AxisValueLabel(centered: true) { if let d = v.as(Date.self) { Text(label(d)) } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                    // Không kẻ vạch ở mốc 0 (đáy cột đã là đường đáy)
                    if (v.as(Double.self) ?? 0) > 0 {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Color.primary.opacity(0.1))
                    }
                    // Số căn trái theo mép thẻ
                    AxisValueLabel { if let n = v.as(Double.self) { Text(short(Int(n))).frame(width: 74, alignment: .leading) } }
                }
            }
            .chartGesture { proxy in
                // Chạm cột để chuyển sang tháng đó. Cử chỉ của chính biểu đồ: một lớp phủ nhận chạm sẽ chặn luôn cú vuốt cuộn ngang
                SpatialTapGesture().onEnded { e in
                    guard let d: Date = proxy.value(atX: e.location.x) else { return }
                    if let b = bars.first(where: { cal.isDate($0.date, equalTo: d, toGranularity: unit) }) { tap(b.date) }
                }
            }
            .frame(height: 220)
            .padding(.top, 12)

            // Trung bình / Thấp nhất / Cao nhất của các tháng có chi
            if !used.isEmpty {
                HStack(spacing: 8) {
                    stat(L("Trung bình"), used.reduce(0, +) / used.count)
                    stat(L("Thấp nhất"), used.min()!)
                    stat(L("Cao nhất"), used.max()!)
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
        .padding(.vertical, 12)
        .background(Self.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        // Nhóm theo danh mục đang có: khoản của danh mục đã xoá (hoặc chưa đồng bộ về máy này) tính vào "Khác",
        // như cách nó được vẽ ở mọi nơi, để các dòng cộng lại đúng bằng tổng chi
        let byCat = Dictionary(grouping: items, by: { Category.get($0.c).k }).mapValues(sum)
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
                            Text("\(fmt(v))").font(.system(size: 16, weight: .semibold))
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
                // "1 khoản" tách riêng để tiếng Anh có dạng số ít (như màn hình chính)
                Text(items.count == 1 ? L("1 khoản") : L("%ld khoản", items.count)).font(.system(size: 13)).foregroundStyle(.secondary)
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
                        Text("\(fmt(e.a))").font(.system(size: 15, weight: .semibold))
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

    // MARK: Khoảng thời gian đang xem

    /// Khoảng đang xem: một ngày (đã chọn trong tuần), cả tuần, cả tháng hoặc cả năm
    private var span: DateInterval {
        if let day { return cal.dateInterval(of: .day, for: day)! }
        switch scope {
        case .week: return Self.wcal.dateInterval(of: .weekOfYear, for: week)!
        case .month: return cal.dateInterval(of: .month, for: month)!
        }
    }

    private var unit: Calendar.Component {
        if day != nil { return .day }
        return scope == .week ? .weekOfYear : .month
    }

    /// Khoảng liền trước, cùng độ dài (hôm trước, tuần trước, tháng trước, năm trước)
    private var prevSpan: DateInterval {
        let c = unit == .weekOfYear ? Self.wcal : cal
        return c.dateInterval(of: unit, for: c.date(byAdding: unit, value: -1, to: span.start)!)!
    }

    private func spending(in i: DateInterval) -> [Expense] { store.items.filter { $0.date >= i.start && $0.date < i.end } }

    private func dayCount(_ i: DateInterval) -> Int { max(cal.dateComponents([.day], from: i.start, to: i.end).day ?? 1, 1) }

    /// Số ngày đã qua từ đầu khoảng đang xem tới hôm nay (hôm nay là ngày thứ elapsedDays + 1)
    private var elapsedDays: Int { cal.dateComponents([.day], from: span.start, to: cal.startOfDay(for: Date())).day ?? 0 }

    /// Tuần / tháng / năm đang chạy (một ngày lẻ thì so cả ngày trước, không tính là đang chạy)
    private var isRunning: Bool { unit != .day && span.contains(Date()) }

    /// Khoảng đang chạy thì so với cùng kỳ của khoảng trước (từ đầu đến cùng số ngày), không so với cả khoảng trước.
    private func comparable(_ prev: [Expense]) -> [Expense] {
        guard isRunning else { return prev }
        let start = prevSpan.start, n = elapsedDays
        return prev.filter { (cal.dateComponents([.day], from: start, to: $0.date).day ?? 0) <= n }
    }

    private var heroTitle: String {
        if let day { return L("Chi %@", dayName(day, long: false)) }
        switch scope {
        case .week:
            return isRunning ? L("Tổng chi tuần này") : L("Tổng chi tuần")
        case .month: return L("Tổng chi %@", Lang.isEnglish ? monthName(month) : monthName(month).lowercased())
        }
    }

    private var compareText: String {
        if isRunning { return L("so với cùng kỳ") }
        switch unit {
        case .day: return L("so với hôm trước")
        case .weekOfYear: return L("so với tuần trước")
        default: return L("so với tháng trước")
        }
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

    /// Số tiền ghi đủ (1.250.000), không viết tắt kiểu "1,3tr" / "45k"
    private func short(_ n: Int) -> String { fmt(n) }
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
