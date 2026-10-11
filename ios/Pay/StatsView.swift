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
    @State private var expanded = false
    @State private var calMonth = Date()
    /// Một ngày được chọn trong tuần (nil = cả tuần)
    @State private var day: Date?
    /// Đang dựng phim giới thiệu (xem Film.swift)
    @Environment(\.film) private var film

    private let cal = Calendar.current
    /// Lịch tuần bắt đầu từ thứ Hai
    static let wcal: Calendar = { var c = Calendar.current; c.firstWeekday = 2; return c }()

    enum Scope { case week, month }

    /// Thu gọn: xem theo tuần; mở rộng lịch ra cả tháng: xem theo tháng (phim giới thiệu luôn xem theo tháng)
    private var scope: Scope { film != nil || expanded ? .month : .week }

    // Bảng màu của màn hình này
    static let page = Color(light: 0xEFEFEF, dark: 0x0D0D10)
    static let card = Color(light: 0xFFFFFF, dark: 0x1C1C1F)
    static let ink = Color(light: 0x1C1C1E, dark: 0xF2F2F2)          // cột "Hoá đơn", tab đang chọn
    static let inkText = Color(light: 0xFFFFFF, dark: 0x111114)
    static let orange = Color(light: 0xEE6A35, dark: 0xF07443)
    static let chip = Color(light: 0xF2F2F2, dark: 0x2A2A2E)

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
            if scope == .month { limitCard(items) }
            trendCard
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

    // MARK: Lịch — chép từ CalendarPanel của Peek (hàng tiêu đề + dải bảy ngày), chỉ đổi màu cho nền sáng
    //
    // Peek vẽ chữ trắng trên nền đen của notch; ở đây là chữ `primary` trên thẻ trắng, cùng các mức độ mờ.
    // Tím của hôm nay -> xanh lá của app. Cỡ chữ / khung nhân 1,3 cho vừa màn hình điện thoại.

    private static let headerHeight: CGFloat = 30
    private static let stripHeight: CGFloat = 72
    private static let todayTint = Color(light: 0x3FA65A, dark: 0x7FD08B)

    private var weekStrip: some View {
        VStack(spacing: 10) {
            calendarHeader
            if expanded {
                monthGrid.transition(.opacity)
            } else {
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in dayColumn(cal.date(byAdding: .day, value: i, to: week)!, weekday: true) }
                }
                .frame(height: Self.stripHeight)
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(Self.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Hàng tiêu đề: nút gộp hình tờ lịch + nhãn tuần (chạm để mở cả tháng), "Hôm nay" khi đang ở tuần khác, hai mũi tên.
    private var calendarHeader: some View {
        let canNext = expanded
            ? cal.date(byAdding: .month, value: 1, to: cal.dateInterval(of: .month, for: calMonth)!.start)! <= Date()
            : cal.date(byAdding: .day, value: 7, to: week)! <= Date()
        let elsewhere = expanded ? !cal.isDate(calMonth, equalTo: Date(), toGranularity: .month) : week != weekStart(page: 0)
        return HStack(spacing: 6) {
            Button { withAnimation(.snappy) { toggleExpanded() } } label: {
                HStack(spacing: 8) {
                    CalendarShape().fill(style: FillStyle(eoFill: true))
                        .frame(width: 19, height: 19)
                        .foregroundStyle(Color.primary.opacity(0.5))
                    Text(calendarLabel)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.55))
                }
                .padding(.horizontal, 10)
                .frame(height: Self.headerHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(Pressable())
            Spacer(minLength: 8)
            // Chỉ hiện khi đang ở tuần / tháng khác — ở tuần này thì nút "Hôm nay" chẳng đưa đi đâu
            if elsewhere {
                Button { withAnimation(.snappy) { goToday() } } label: {
                    Text(L("Hôm nay"))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .padding(.horizontal, 10)
                        .frame(height: Self.headerHeight)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                        .contentShape(Capsule())
                }
                .buttonStyle(Pressable())
            }
            stepButton("chevron.left", L("Trước")) { step(-1) }
            stepButton("chevron.right", L("Sau")) { step(1) }.disabled(!canNext).opacity(canNext ? 1 : 0.3)
        }
        .frame(height: Self.headerHeight)
    }

    /// Nhãn: tuần này thì gọi tên, tuần khác thì ghi khoảng ngày "5.10 – 11.10"; đang chọn một ngày thì ghi ngày ấy;
    /// mở rộng thì ghi tháng.
    private var calendarLabel: String {
        if expanded { return monthYear(calMonth) }
        if let day { return dayName(day, long: true) + ", " + dotted(day) }
        if week == weekStart(page: 0) { return L("Tuần này") }
        return "\(dotted(week)) – \(dotted(cal.date(byAdding: .day, value: 6, to: week)!))"
    }

    /// "7.10" — ngày chấm tháng
    private func dotted(_ d: Date) -> String { "\(cal.component(.day, from: d)).\(cal.component(.month, from: d))" }

    private func stepButton(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { run() } } label: {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.45))
                .frame(width: 30, height: 28)
                .contentShape(Capsule())
        }
        .buttonStyle(Pressable())
        .accessibilityLabel(label)
    }

    /// Mở rộng: cả tháng, cùng kiểu cột như dải bảy ngày (hàng thứ ở trên, ô ngoài tháng để trống)
    private var monthGrid: some View {
        let start = Self.wcal.dateInterval(of: .weekOfYear, for: cal.dateInterval(of: .month, for: calMonth)!.start)!.start
        let end = cal.dateInterval(of: .month, for: calMonth)!.end
        let weeks = Int(ceil(Double(cal.dateComponents([.day], from: start, to: end).day!) / 7))
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekdayShort(cal.date(byAdding: .day, value: i, to: start)!))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)
            ForEach(0..<weeks, id: \.self) { w in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in
                        let d = cal.date(byAdding: .day, value: w * 7 + i, to: start)!
                        if cal.isDate(d, equalTo: calMonth, toGranularity: .month) {
                            dayColumn(d, weekday: false)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: 50)
            }
        }
    }

    private func toggleExpanded() {
        if !expanded { showMonth(day ?? cal.date(byAdding: .day, value: 3, to: week)!) }
        expanded.toggle()
    }

    /// ‹ ›: lùi / tới một tuần, hoặc một tháng khi đang mở rộng
    private func step(_ n: Int) {
        if expanded {
            showMonth(cal.date(byAdding: .month, value: n, to: calMonth)!)
        } else {
            week = cal.date(byAdding: .day, value: 7 * n, to: week)!
        }
        day = nil
    }

    /// Một cột ngày như Peek: chữ thứ nhỏ mờ, số tròn, hàng chấm (ở đây: chấm xanh = ngày có chi).
    /// Nền cột theo mức: đang chọn > hôm nay > không gì cả.
    private func dayColumn(_ d: Date, weekday: Bool) -> some View {
        let on = day.map { cal.isDate($0, inSameDayAs: d) } ?? false
        let future = d > Date()
        let today = cal.isDateInToday(d)
        let spent = !future && store.total(on: d) > 0
        return VStack(spacing: 6) {
            if weekday {
                Text(weekdayShort(d))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(today ? 0.6 : 0.35))
            }
            Text("\(cal.component(.day, from: d))")
                .font(.system(size: 20, weight: today ? .semibold : .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(today ? Self.todayTint : Color.primary.opacity(0.75))
            // Khung cao cố định để hàng số không nhấp nhô theo ngày có chấm hay không
            Circle().fill(Self.todayTint).frame(width: 4.5, height: 4.5).opacity(spent ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(future ? 0.35 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !future else { return }
            withAnimation(.snappy(duration: 0.2)) {
                if on { day = nil } else {
                    day = d
                    week = Self.wcal.dateInterval(of: .weekOfYear, for: d)!.start
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(on ? Color.primary.opacity(0.09) : today ? Color.primary.opacity(0.04) : .clear)
        )
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
        week = weekStart(page: 0)
        day = Date()
        showMonth(Date())
    }

    /// Tháng hiện trên lịch mở rộng cũng là tháng đang xem (và trang 6 tháng của biểu đồ chứa nó)
    private func showMonth(_ d: Date) {
        calMonth = d
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
                iconChip("creditcard", fg: .white, bg: .white.opacity(0.2))
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(fmt(total)).font(.system(size: 40, weight: .bold)).kerning(-1).minimumScaleFactor(0.5).lineLimit(1)
                Text("đ").font(.system(size: 22, weight: .semibold)).opacity(0.8)
            }
            if let d = delta(total, sum(prev)) {
                HStack(spacing: 8) {
                    // 0% (kể cả do làm tròn) không phải tăng cũng không phải giảm: không vẽ mũi tên
                    Group {
                        if d == 0 { Text(verbatim: "0%") } else { Label("\(abs(d))%", systemImage: d > 0 ? "arrow.up" : "arrow.down") }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(0.22), in: Capsule())
                    Text(compareText)
                        .font(.system(size: 13)).opacity(0.85)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { HeroGreen().clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)) }
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
                tile(L("Hôm nay"), "sun.max", "\(fmt(today))đ", delta: delta(today, yesterday), note: L("chưa có để so"))
            } else {
                let active = Set(items.map { cal.startOfDay(for: $0.date) }).count
                tile(L("Ngày có chi"), "calendar", "\(active)/\(days)", delta: nil, note: L("%ld%% số ngày", active * 100 / max(days, 1)))
            }
            tile(L("TB mỗi ngày"), "chart.line.flattrend.xyaxis", "\(fmt(avg / 1000 * 1000))đ", delta: delta(avg, prevAvg), note: L("chưa có để so"))
            }
            }
            GridRow {
            tile(L("Lớn nhất"), "arrow.up.forward.circle", biggest.map { "\(fmt($0.a))đ" } ?? "0đ", delta: nil,
                 note: biggest.map { $0.n?.isEmpty == false ? $0.n! : Category.get($0.c).name } ?? L("chưa có"))
            tile(L("Số khoản"), "list.bullet", "\(items.count)", delta: delta(items.count, prev.count), note: L("chưa có để so"))
            }
        }
    }

    /// Ô số liệu tối giản: tên + biểu tượng, con số, và luôn một nhãn ở đáy: % nếu có so sánh, không thì nhãn xám ghi note.
    /// Nhờ vậy hai ô cùng hàng luôn cao bằng nhau mà không ô nào bị trống đáy.
    private func tile(_ title: String, _ icon: String, _ value: String, delta d: Int?, note: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Biểu tượng tròn căn giữa theo chiều dọc với chữ tiêu đề nhỏ bên trái
            HStack(alignment: .center) {
                Text(title).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                iconChip(icon, fg: .primary, bg: Self.chip)
            }
            Text(value).font(.system(size: 22, weight: .bold)).minimumScaleFactor(0.5).lineLimit(1)
            if let d { deltaPill(d) } else { notePill(note) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Self.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Chi tăng là xấu: mũi tên lên nền đỏ nhạt, xuống nền xanh nhạt (có mũi tên, không chỉ dựa vào màu).
    /// 0% (kể cả do làm tròn) không phải tăng cũng không phải giảm: nhãn xám, không mũi tên.
    @ViewBuilder private func deltaPill(_ d: Int) -> some View {
        if d == 0 {
            notePill("0%")
        } else {
            let up = d > 0
            Label("\(abs(d))%", systemImage: up ? "arrow.up" : "arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(up ? Color(light: 0xB42318, dark: 0xFF8A80) : Color(light: 0x067647, dark: 0x6CE9A6))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background((up ? Color.red : Color.green).opacity(0.14), in: Capsule())
        }
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

    /// Hạn mức của tháng đang xem (mức đặt cho tháng đó). Tháng cũ chưa từng đặt thì ẩn hẳn thẻ.
    @ViewBuilder private func limitCard(_ items: [Expense]) -> some View {
        let spent = sum(items)
        let limit = store.budget(for: month)
        if limit != nil || isRunning {
        card {
            Text(L("Hạn mức chi tháng")).font(.system(size: 17, weight: .semibold))
            if let limit {
                let ratio = min(Double(spent) / Double(limit), 1)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Hatch.gray)
                        Capsule().fill(spent > limit ? Color(hex: 0xD92D20) : Self.orange)
                            .frame(width: max(12, g.size.width * ratio))
                    }
                }
                .frame(height: 12)
                .padding(.top, 8)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(fmt(spent))đ").font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text("/ \(fmt(limit))đ").font(.system(size: 14)).foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            } else {
                Text(L("Chưa đặt hạn mức. Vào Cài đặt › Ngân sách để đặt.")).font(.system(size: 14)).foregroundStyle(.secondary)
            }
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

    /// Biểu đồ theo kiểu xem: tuần -> 7 ngày, tháng -> 6 tháng của thanh chọn tháng, năm -> 12 tháng của năm
    @ViewBuilder private var trendCard: some View {
        switch scope {
        case .week:
            let start = Self.wcal.dateInterval(of: .weekOfYear, for: week)!.start
            trend(L("Chi trong tuần"), (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }, unit: .day, label: weekdayShort,
                  selected: { d in day.map { cal.isDate($0, inSameDayAs: d) } ?? true },
                  tap: { d in if d <= Date() { day = d } })
        case .month:
            trend(L("Chi 6 tháng"), windowMonths, unit: .month, label: shortMonth, selected: isSelected, tap: { d in day = nil; showMonth(d) })
        }
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
                legend(AnyShapeStyle(Hatch.orange), L("Chi tiêu khác"))
                Spacer()
            }
            .padding(.top, 4)
            Chart(bars) { b in
                if b.bills > 0 {
                    BarMark(x: .value("Tháng", b.date, unit: unit), yStart: .value("Từ", 0), yEnd: .value("Hoá đơn", b.bills), width: .ratio(0.55))
                        .foregroundStyle(Self.ink)
                        .cornerRadius(6)
                        .opacity(selected(b.date) ? 1 : 0.45)
                }
                if b.other > 0 {
                    let start = b.bills > 0 ? Double(b.bills) + gap : 0
                    BarMark(x: .value("Tháng", b.date, unit: unit), yStart: .value("Từ", start), yEnd: .value("Chi tiêu khác", start + Double(b.other)), width: .ratio(0.55))
                        .foregroundStyle(Hatch.orange)
                        .cornerRadius(6)
                        .opacity(selected(b.date) ? 1 : 0.45)
                }
            }
            // Giữ đủ 6 tháng trên trục kể cả tháng chưa có khoản chi nào
            .chartXScale(domain: bars.first!.date...cal.date(byAdding: unit, value: 1, to: bars.last!.date)!)
            .chartXAxis {
                AxisMarks(values: .stride(by: unit)) { v in
                    AxisValueLabel(centered: true) { if let d = v.as(Date.self) { Text(label(d)) } }
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
                            if let b = bars.first(where: { cal.isDate($0.date, equalTo: d, toGranularity: unit) }) { tap(b.date) }
                        }
                }
            }
            .frame(height: 220)
            .padding(.top, 12)

            // Trung bình / Thấp nhất / Cao nhất của các tháng có chi
            if !used.isEmpty {
                HStack(spacing: 0) {
                    stat(L("Trung bình"), used.reduce(0, +) / used.count)
                    Divider().frame(height: 36)
                    stat(L("Thấp nhất"), used.min()!)
                    Divider().frame(height: 36)
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

/// Nền khung Tổng chi: gradient loang chủ đạo xanh lá của app (#61BE6E) — đậm góc dưới trái, sáng dần lên góc trên phải,
/// điểm giữa lệch khỏi lưới cho mảng màu không đều — phủ một lớp hạt nhiễu mịn như ảnh in.
private struct HeroGreen: View {
    var body: some View {
        ZStack {
            if #available(iOS 18.0, *) {
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.58, 0.42], [1, 0.5],
                    [0, 1], [0.45, 1], [1, 1],
                ], colors: [
                    Color(hex: 0x45AE60), Color(hex: 0x7ACF86), Color(hex: 0xB4E6AE),
                    Color(hex: 0x2F9852), Color(hex: 0x61BE6E), Color(hex: 0x95DA98),
                    Color(hex: 0x1C7A3E), Color(hex: 0x2E9A55), Color(hex: 0x5CBB6C),
                ])
            } else {
                LinearGradient(colors: [Color(hex: 0x1C7A3E), Color(hex: 0x61BE6E), Color(hex: 0xB4E6AE)],
                               startPoint: .bottomLeading, endPoint: .topTrailing)
            }
            Image(uiImage: Self.grain).resizable(resizingMode: .tile)
                .blendMode(.overlay).opacity(0.25)
                .allowsHitTesting(false)
        }
    }

    /// Ô hạt nhiễu xám ngẫu nhiên 160×160 (dựng một lần), lát kín khung
    private static let grain: UIImage = {
        let n = 160
        var px = [UInt8](repeating: 0, count: n * n)
        for i in px.indices { px[i] = UInt8.random(in: 0...255) }
        let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        return UIImage(cgImage: ctx.makeImage()!, scale: 3, orientation: .up)
    }()
}
