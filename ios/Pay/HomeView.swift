import SwiftUI

/// Mở màn hình nhập số tiền theo từng tình huống
enum EntryMode: Identifiable {
    case new(cat: String?)
    case scan(VietQR)
    case raw(String)
    case edit(Expense)

    var id: String {
        switch self {
        case .new(let c): return "new-\(c ?? "")"
        case .scan(let q): return "scan-\(q.raw)"
        case .raw(let s): return "raw-\(s)"
        case .edit(let e): return "edit-\(e.id)"
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var quick: QuickAction
    @State private var entry: EntryMode?
    @State private var scanning = false
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showStats = false
    @State private var showHouse = false
    @State private var listening = false
    @State private var scanned: String?
    /// "Bây giờ" để tính hôm nay / tháng này; cập nhật khi app quay lại hoặc qua nửa đêm, nếu không màn hình
    /// mở lại sáng hôm sau vẫn hiện số của hôm qua
    @State private var now = Date()
    @State private var addingCat = false
    @State private var editingCat: CatEdit?
    /// Danh mục đang mở bảng tuỳ chọn (nhấn giữ) và danh mục đang bị nhấn
    @State private var menu: AppMenuSpec?
    /// Danh mục đang mở danh sách khoản chi (chạm vào ô danh mục)
    @State private var listing: Category?
    @Environment(\.scenePhase) private var scenePhase
    /// Đang dựng phim giới thiệu (xem Film.swift): vẽ theo trạng thái phim đưa vào
    @Environment(\.film) private var film

    var body: some View {
        let now = self.now
        ZStack(alignment: .bottom) {
            Palette.bg.ignoresSafeArea()

            FilmScroll {
                VStack(alignment: .leading, spacing: 0) {
                    header(now)
                    Button { showStats = true } label: { hero(now) }
                        .buttonStyle(Pressable())
                        .padding(.top, 14)

                    sectionTitle(L("Danh mục")) { Text(monthLabel(now)) }
                    tiles(now)

                    sectionTitle(L("Gần đây")) {
                        Button(L("Xem tất cả")) { showHistory = true }.buttonStyle(Pressable()).foregroundStyle(.primary)
                    }
                    recent
                }
                .padding(.horizontal, 16)
                .padding(.bottom, Self.nativeEdge && film == nil ? 16 : 120)
                .padding(.top, film == nil ? 0 : FilmScreen<EmptyView>.insets.top)
            }
            .withDock(dock: dock, fallbackBlur: bottomBlur, film: film != nil)

            ToastView()
                .padding(.bottom, 108 + (film == nil ? 0 : FilmScreen<EmptyView>.insets.bottom))
        }
        .appMenu($menu)
        .overlay {
            // Phim: bảng nhấn giữ theo trạng thái phim đưa vào
            if let m = film?.menu, m.shown > 0 {
                AppMenu(spec: categoryMenu(Category.get(m.key)), close: {}, shown: m.shown,
                        pressed: film?.pressed["menu-item"].map { (1, $0) })
            }
        }
        .fullScreenCover(item: $entry) { EntryView(mode: $0) }
        .fullScreenCover(isPresented: $scanning, onDismiss: {
            guard let s = scanned else { return }
            scanned = nil
            entry = VietQR.parse(s).flatMap { $0.acct != nil ? EntryMode.scan($0) : nil } ?? .raw(s)
        }) {
            ScannerView { code in scanned = code; scanning = false }
        }
        .sheet(isPresented: $showHistory) { HistoryView().environmentObject(store) }
        .sheet(item: $listing) { HistoryView(category: $0.k).environmentObject(store) }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
        .sheet(isPresented: $showStats) { StatsView().environmentObject(store) }
        .sheet(isPresented: $showHouse) { HouseView().environmentObject(store) }
        .onChange(of: quick.openHouse) { _, v in if v { quick.openHouse = false; showHouse = true } }
        .sheet(isPresented: $addingCat) { CategoryEditor().environmentObject(store) }
        .sheet(item: $editingCat) { CategoryEditor(editing: $0.cat).environmentObject(store) }
        .fullScreenCover(isPresented: $listening) {
            VoiceEntryView(onScan: {
                Task { try? await Task.sleep(for: .milliseconds(450)); scanning = true }
            }, onEdit: { e in
                Task { try? await Task.sleep(for: .milliseconds(450)); entry = .edit(e) }
            })
            .environmentObject(store)
        }
        .onChange(of: scenePhase) { _, p in if p == .active { wake() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in wake() }
        .onChange(of: quick.pending, initial: true) { _, k in
            guard let k else { return }
            quick.pending = nil
            Task { await run(k) }
        }
    }

    /// App quay lại / qua nửa đêm: cập nhật "hôm nay", ghi khoản định kỳ vừa tới hạn.
    private func wake() {
        now = Date()
        store.catchUpRecurring()
    }

    /// Mở thẳng màn hình quét / nhập. Đang mở màn hình khác thì đóng hết trước rồi mới mở.
    private func run(_ k: QuickKind) async {
        let busy = entry != nil || scanning || showHistory || showSettings || showStats || showHouse || listening || listing != nil
        if (k == .scan && scanning) || (k == .voice && listening) { return }
        entry = nil; scanning = false; showHistory = false; showSettings = false; showStats = false; showHouse = false; listening = false; listing = nil
        if busy { try? await Task.sleep(for: .milliseconds(450)) }
        switch k {
        case .scan: scanning = true
        case .add: entry = .new(cat: nil)
        case .voice: listening = true
        }
    }

    // MARK: Các phần

    private func header(_ now: Date) -> some View {
        HStack(spacing: 2) {
            // Logo app (thẻ xanh) thay chữ "Pay"
            Image("logo-pay").resizable().scaledToFit().frame(height: 30)
                .accessibilityLabel("Pay").accessibilityAddTraits(.isHeader)
            Spacer()
            headerButton("person.2.crop.square.stack.fill", L("Nhóm chung")) { showHouse = true }
            headerButton("icon-dashboard", L("Thống kê"), asset: true) { showStats = true }
            headerButton("icon-settings", L("Cài đặt"), asset: true) { showSettings = true }
        }
        .padding(.top, 8)
    }

    /// Cao của mọi thứ trên thanh đầu trang: nhãn ngày và các nút tròn.
    private static let headerSize: CGFloat = 42

    /// Nút tròn trên thanh đầu trang: biểu tượng tô đặc, cùng kích thước.
    /// asset: biểu tượng vẽ sẵn trong Assets (vd icon-dashboard của Tabler) thay vì SF Symbols
    private func headerButton(_ symbol: String, _ label: String, asset: Bool = false, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            (asset ? Image(symbol) : Image(systemName: symbol))
                .resizable().scaledToFit()
                .fontWeight(.semibold)
                // Cùng chiều cao hình: icon vẽ sẵn đã cắt sát biên; SF Symbols có lề trong nên phóng thêm cho bằng
                .frame(height: asset ? 20 : 21.5)
                .offset(y: asset ? 0 : 0.7)   // cùng đường đáy với hai icon kia
                .frame(width: Self.headerSize, height: Self.headerSize)   // không nền, nhưng vùng chạm vẫn 42×42
                .contentShape(Rectangle())
        }
        .buttonStyle(Pressable())
        .filmPressed(film?.pressed[symbol == "icon-dashboard" ? "stats" : symbol == "icon-settings" ? "settings" : "house"] ?? 0)
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }

    private func hero(_ now: Date) -> some View {
        let month = store.monthItems(now).reduce(0) { $0 + $1.a }
        let n = store.count(on: now)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("Hôm nay đã chi"))
                Spacer()
                Text(dayLabel(now))
            }
            .font(.system(size: 16)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(fmt(store.total(on: now)))
                    .font(.system(size: 46, weight: .bold)).kerning(-1.5)
                    .minimumScaleFactor(0.5).lineLimit(1)
            }
            .padding(.top, 8).padding(.bottom, 14)
            HStack {
                Text(L("%@: %@", monthLabel(now), fmt(month)))
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Palette.pill, in: Capsule())
                    .lineLimit(1)
                Spacer()
                if n > 0 { Text(n == 1 ? L("1 khoản") : L("%d khoản", n)).font(.system(size: 15)).foregroundStyle(.secondary) }
            }
            if let b = store.budgetStatus(now) { budget(b, now).padding(.top, 16) }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .environment(\.colorScheme, .light)   // thẻ luôn nền trắng chữ đen, kể cả chế độ tối (nổi trên nền đen)
    }

    /// Thanh ngân sách tháng: còn / vượt bao nhiêu, mỗi ngày còn tiêu được bao nhiêu.
    private func budget(_ b: BudgetStatus, _ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BudgetBar(s: b, height: 6, track: Palette.pill)
            HStack(spacing: 4) {
                // Chữ giữ màu chữ thường cho dễ đọc; chỉ khi vượt mới đỏ, kèm biểu tượng
                if b.level == .over { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(Palette.danger) }
                Text(b.remaining >= 0 ? L("Còn %@", fmt(b.remaining)) : L("Vượt %@", fmt(-b.remaining))).font(.system(size: 15, weight: .semibold)).foregroundStyle(b.level == .over ? Palette.danger : .primary)
                Spacer()
                Text(b.level == .over ? L("Ngân sách %@", fmt(b.budget)) : L("%@/ngày", fmt(b.perDay(at: now))))
                    .font(.system(size: 15)).foregroundStyle(.secondary)
            }
            .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private func sectionTitle<T: View>(_ title: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack {
            Text(title).font(.system(size: 21, weight: .bold))
            Spacer()
            trailing()
                .font(.system(size: 15)).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Palette.pill, in: Capsule())
        }
        .padding(.top, 26).padding(.bottom, 12)
    }

    private func tiles(_ now: Date) -> some View {
        var perCat: [String: Int] = [:]
        for e in store.monthItems(now) { perCat[e.c, default: 0] += e.a }
        // Mỗi danh mục dài cả hàng hoặc nửa hàng (đổi trong bảng nhấn giữ). Ô nửa hàng đứng lẻ ngay trước một ô dài
        // thì giãn ra cho kín hàng. Ô dấu + luôn ở cuối, nửa hàng.
        var rows: [[Category?]] = [], half: [Category?] = []   // nil = ô dấu +
        for c in Category.all {
            if store.isWide(c.k) {
                if !half.isEmpty { rows.append(half); half = [] }
                rows.append([c])
            } else {
                half.append(c)
                if half.count == 2 { rows.append(half); half = [] }
            }
        }
        half.append(nil); rows.append(half)
        return VStack(spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, c in
                        if let c {
                            // Chạm: xem các khoản của danh mục; nhấn giữ: bảng tuỳ chọn tự vẽ (có "Nhập khoản…")
                            TapHold(tap: { listing = c }, hold: { menu = categoryMenu(c) }) {
                                tile(c, total: perCat[c.k] ?? 0)
                            }
                            .filmPressed(film?.pressed["tile-" + c.k] ?? 0)
                            // Dấu + ở góc: nhập khoản mới cho danh mục này
                            .overlay(alignment: .topTrailing) {
                                Button { entry = .new(cat: c.k) } label: {
                                    Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                                        .frame(width: 30, height: 30).background(.white.opacity(0.6), in: Circle())
                                        .foregroundStyle(Color(hex: 0x111114))
                                        .padding(16).contentShape(Rectangle())
                                }
                                .buttonStyle(Pressable())
                                .accessibilityLabel(L("Nhập khoản %@", c.name))
                            }
                        } else {
                            addTile
                        }
                    }
                    // Ô dấu + đứng một mình vẫn chỉ rộng nửa hàng
                    if row.count == 1, row[0] == nil { Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
    }

    /// Ô cuối: tạo danh mục riêng. Chỉ dấu + ở giữa ô, không chữ
    private var addTile: some View {
        Button { addingCat = true } label: {
            Image(systemName: "plus").font(.system(size: 22, weight: .semibold))
                .frame(width: 52, height: 52).background(Palette.surface, in: Circle())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 140)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: Self.tileRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Self.tileRadius, style: .continuous))
        }
        .buttonStyle(Pressable())
        .accessibilityLabel(L("Thêm danh mục"))
    }

    private static let tileRadius: CGFloat = 28

    /// Ô danh mục: biểu tượng, tên, số tiền tháng này. Dấu + ở góc nhập khoản mới cho danh mục đó
    private func tile(_ c: Category, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CategoryIcon(c: c, size: 30)
                .frame(width: 52, height: 52).background(.white, in: Circle())
            Spacer(minLength: 14)
            Text(c.name).font(.system(size: 16, weight: .medium)).opacity(0.7)
            Text(fmt(total)).font(.system(size: 19, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(c.ink)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .background(c.color, in: RoundedRectangle(cornerRadius: Self.tileRadius, style: .continuous))
    }

    /// Bảng nhấn giữ của một danh mục
    private func categoryMenu(_ c: Category) -> AppMenuSpec {
        let month = store.monthItems(now).filter { $0.c == c.k }
        var items = [
            AppMenuItem(icon: "plus", title: L("Nhập khoản %@", c.name)) { entry = .new(cat: c.k) },
            AppMenuItem(icon: "paintpalette.fill", title: L("Đổi biểu tượng, màu, tên")) { editingCat = CatEdit.of(c.k, store: store) },
            store.isWide(c.k)
                ? AppMenuItem(icon: "rectangle.split.2x1", title: L("Thu ô về nửa hàng")) { withAnimation(.snappy) { store.setWide(c.k, false) } }
                : AppMenuItem(icon: "rectangle", title: L("Kéo ô dài cả hàng")) { withAnimation(.snappy) { store.setWide(c.k, true) } },
        ]
        if Category.isBuiltin(c.k) {
            if store.cats[c.k]?.on == true { items.append(AppMenuItem(icon: "arrow.uturn.backward", title: L("Về mặc định")) { store.resetCategory(c.k) }) }
        } else {
            items.append(AppMenuItem(icon: "trash.fill", title: L("Xoá danh mục"), danger: true) { store.removeCategory(c.k) })
        }
        return AppMenuSpec(icon: AnyView(CategoryIcon(c: c, size: 30).frame(width: 56, height: 56)
                            .background(c.color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))),
                           title: c.name,
                           subtitle: L("%@: %@", monthLabel(now), fmt(month.reduce(0) { $0 + $1.a })) + " · " + (month.count == 1 ? L("1 khoản") : L("%d khoản", month.count)),
                           items: items)
    }

    @ViewBuilder private var recent: some View {
        let list = Array(store.sorted.prefix(5))
        if list.isEmpty {
            // Chữ có **đậm** (Markdown): đưa qua LocalizedStringKey để Text vẽ đậm
            Text(LocalizedStringKey(L("Chưa có khoản nào.\nBấm **Quét QR** khi trả tiền,\nhoặc **Nhập** / bấm một danh mục ở trên.")))
                .font(.system(size: 17)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(24)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else if film != nil {
            VStack(spacing: 10) { ForEach(list) { ExpenseRow(e: $0, showDay: true, now: now, repeats: store.rule(for: $0) != nil) } }
        } else {
            // List để dùng thao tác vuốt có sẵn của iOS; không tự cuộn, cao vừa đủ số hàng
            List {
                ForEach(list) { e in
                    TapHold(tap: { entry = .edit(e) }, hold: { menu = expenseMenu(e, store: store) { entry = .edit(e) } }) {
                        ExpenseRow(e: e, showDay: true, now: now, repeats: store.rule(for: e) != nil)
                    }
                    .expenseSwipe(delete: { store.remove(id: e.id) })
                }
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .frame(height: CGFloat(list.count) * ExpenseRow.rowHeight)
        }
    }

    /// iOS 26: chừa chỗ cho thanh nút bằng safeAreaBar (không cần đệm 120pt ở cuối nội dung).
    static var nativeEdge: Bool { if #available(iOS 26.0, *) { true } else { false } }

    /// Lớp mờ dưới đáy (mọi phiên bản iOS): mờ đậm sát cạnh dưới, nhạt dần lên trên, để nút nổi dễ nhìn khi nội dung cuộn qua.
    private var bottomBlur: some View {
        // Chỉ chuyển dần sang màu nền, không dùng lớp kính mờ: kính mờ cộng lớp màu nền phủ lên trông đục như sữa.
        // Nhiều mốc theo đường cong êm để không thấy vạch ranh giới.
        LinearGradient(stops: [
            .init(color: Palette.bg, location: 0),
            .init(color: Palette.bg, location: 0.28),
            .init(color: Palette.bg.opacity(0.85), location: 0.45),
            .init(color: Palette.bg.opacity(0.55), location: 0.62),
            .init(color: Palette.bg.opacity(0.25), location: 0.8),
            .init(color: Palette.bg.opacity(0), location: 1),
        ], startPoint: .bottom, endPoint: .top)
        .frame(height: 170)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Hai nút nổi trên nội dung, nền kính (Liquid Glass trên iOS 26).
    private var dock: some View {
        GlassGroup {
            HStack(spacing: 12) {
                BigButton(title: L("Nhập"), icon: "plus", primary: false) { entry = .new(cat: nil) }
                BigButton(title: L("Quét QR"), icon: "qrcode.viewfinder", primary: true) { scanning = true }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    /// "Tháng 10" / "October"
    private func monthLabel(_ d: Date) -> String {
        if Lang.isEnglish {
            let f = DateFormatter(); f.locale = Lang.locale; f.dateFormat = "LLLL"
            return f.string(from: d)
        }
        return "Tháng \(Calendar.current.component(.month, from: d))"
    }

    /// "T7, 10/10" / "Sat, Oct 10"
    private func dayLabel(_ d: Date) -> String {
        if Lang.isEnglish {
            let f = DateFormatter(); f.locale = Lang.locale; f.dateFormat = "EEE, MMM d"
            return f.string(from: d)
        }
        let dow = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"][Calendar.current.component(.weekday, from: d) - 1]
        let c = Calendar.current.dateComponents([.day, .month], from: d)
        return "\(dow), \(c.day!)/\(c.month!)"
    }
}

// MARK: Thành phần dùng chung

extension View {
    /// Hàng khoản chi trong List: vuốt sang trái hiện nút Xoá (vuốt hết cỡ là xoá; chạm vào hàng để sửa), không kẻ dòng, nền trong suốt.
    func expenseSwipe(delete: @escaping () -> Void) -> some View {
        self
            .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                // Chỉ biểu tượng, không chữ; tên vẫn có cho VoiceOver
                Button(role: .destructive, action: delete) { Image(systemName: "trash.fill") }.accessibilityLabel(L("Xoá"))
            }
    }
}

struct ExpenseRow: View {
    /// Cao một hàng kể cả khoảng cách 10pt giữa các hàng (thẻ 86pt: vừa tên hai dòng + dòng phụ).
    static let rowHeight: CGFloat = 96
    let e: Expense
    var showDay = false
    var now = Date()
    /// Khoản định kỳ (app tự ghi hằng tháng): hiện biểu tượng lặp
    var repeats = false

    var body: some View {
        let c = Category.get(e.c)
        HStack(spacing: 14) {
            CategoryIcon(c: c, size: 30)
                .frame(width: 56, height: 56)
                .background(c.color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // Tên dài thì xuống dòng thứ hai thay vì bị cắt "…"
                    Text((e.n?.isEmpty == false ? e.n!.capFirst : c.name)).font(.system(size: 17, weight: .semibold))
                        .lineLimit(2).multilineTextAlignment(.leading).lineSpacing(-1)
                    if repeats {
                        Image(systemName: "repeat").font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary)
                            .accessibilityLabel(L("Hằng tháng"))
                    }
                }
                // Chỉ ngày giờ: danh mục đã có biểu tượng ở đầu hàng, khỏi nhắc lại bằng chữ
                Text(sub).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            // Số tiền luôn hiện đủ: phần tên nhường chỗ
            Text(fmt(e.a)).font(.system(size: 18, weight: .bold)).lineLimit(1).fixedSize().layoutPriority(1)
        }
        .foregroundStyle(.primary)
        .padding(.leading, 12).padding(.trailing, 16).padding(.vertical, 12)
        .frame(minHeight: Self.rowHeight - 10)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var sub: String {
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        var parts: [String] = []
        if showDay {
            let cal = Calendar.current
            if cal.isDate(e.date, inSameDayAs: now) { parts.append(L("Hôm nay")) }
            else if Lang.isEnglish { let df = DateFormatter(); df.locale = Lang.locale; df.dateFormat = "MMM d"; parts.append(df.string(from: e.date)) }
            else { let d = cal.dateComponents([.day, .month], from: e.date); parts.append("\(d.day!)/\(d.month!)") }
        }
        parts.append(tf.string(from: e.date))
        return parts.joined(separator: " · ")
    }
}

struct BigButton: View {
    static let inset: CGFloat = 11
    let title: String
    let icon: String
    let primary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Vòng icon cách đều mép nút ở trên, dưới và bên trái (cùng tâm với đầu nút bo tròn).
            // Nút phụ ôm vừa chữ; nút chính lấy phần còn lại, chữ nằm giữa khoảng trống sau icon.
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 24, weight: .semibold))
                    .frame(width: 56, height: 56)
                    .background(primary ? Palette.ctaInk.opacity(0.14) : Color.primary.opacity(0.08), in: Circle())   // theo màu chữ của nút: chế độ tối nút trắng thì vòng xám, không bị mất
                if primary { Spacer(minLength: 0) }
                Text(title).font(.system(size: 21, weight: .semibold)).lineLimit(1)
                    // Chữ được ưu tiên chỗ trước hai khoảng trống hai bên: không thì khi bật Chữ đậm (Trợ năng)
                    // chữ rộng ra mà vẫn bị cắt thành "Quét…" dù nút còn trống
                    .layoutPriority(1)
                    .minimumScaleFactor(0.7)
                if primary { Spacer(minLength: 0) }
            }
            .padding(BigButton.inset)
            .padding(.trailing, 14)
            .frame(maxWidth: primary ? .infinity : nil)
            .foregroundStyle(primary ? Palette.ctaInk : .primary)
            .contentShape(Capsule())
            .glassCapsule(tint: primary ? Palette.cta : nil)
        }
        .buttonStyle(Pressable())
    }
}

extension View {
    /// Gắn thanh nút ở đáy. iOS 26: safeAreaBar + mép cuộn mờ dần của hệ thống. iOS cũ: tự phủ lớp mờ.
    @ViewBuilder func withDock<D: View, B: View>(dock: D, fallbackBlur: B, film: Bool = false) -> some View {
        if film {
            overlay(alignment: .bottom) { ZStack(alignment: .bottom) { fallbackBlur; dock.padding(.bottom, FilmScreen<EmptyView>.insets.bottom) } }
        } else if #available(iOS 26.0, *) {
            // Mép mờ của hệ thống quá nhẹ trên máy thật, nên phủ thêm lớp mờ tự làm phía dưới thanh nút
            overlay(alignment: .bottom) { fallbackBlur }
                .safeAreaBar(edge: .bottom) { dock }
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            overlay(alignment: .bottom) { ZStack(alignment: .bottom) { fallbackBlur; dock } }
        }
    }
}

/// Gom các nút kính lại để iOS 26 vẽ chung một lớp kính (hai nút gần nhau trông liền mạch).
struct GlassGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 12) { content } } else { content }
    }
}

extension View {
    /// Nền kính hình viên thuốc: Liquid Glass trên iOS 26, kính mờ + bóng đổ trên iOS cũ hơn.
    func glassCapsule(tint: Color?) -> some View { modifier(GlassCapsule(tint: tint)) }
}

private struct GlassCapsule: ViewModifier {
    @Environment(\.film) private var film
    let tint: Color?

    func body(content: Content) -> some View { content.glass(tint: tint, drawn: film != nil) }
}

private extension View {
    /// drawn: tự vẽ nền giống kính (cho phim: kính của hệ thống không vẽ ra PDF được)
    @ViewBuilder func glass(tint: Color?, drawn: Bool) -> some View {
        if drawn {
            background {
                Capsule().fill(tint ?? Color.white.opacity(0.82))
                    .overlay { Capsule().strokeBorder(.white.opacity(tint == nil ? 0.9 : 0.12), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
            }
        } else if #available(iOS 26.0, *) {
            glassEffect(tint.map { Glass.regular.tint($0).interactive() } ?? .regular.interactive(), in: Capsule())
        } else {
            background {
                Capsule().fill(.ultraThinMaterial)
                    .overlay { if let tint { Capsule().fill(tint.opacity(0.92)) } }
                    .overlay { Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
            }
        }
    }
}

/// Hiệu ứng nhấn chung của các nút tự vẽ: thu nhỏ và mờ đi một chút khi đang nhấn, bật lại khi thả
/// (chỉ thu nhỏ 3% thì nút nhỏ gần như không thấy gì).
struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.08) : .spring(duration: 0.3, bounce: 0.35),
                       value: configuration.isPressed)
    }
}

struct ToastView: View {
    @EnvironmentObject var store: Store
    @Environment(\.film) private var film

    /// Mức hiện của thanh khi dựng phim (0…1); dùng app thì luôn 1, hiệu ứng do transition lo
    private var shown: Double { Double(film?.toast ?? 1) }

    var body: some View {
        if let t = store.toast {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 18))
                Text(t.message).font(.system(size: 17, weight: .medium)).lineLimit(1)
                if let undo = t.undo {
                    // Nút thật nằm trong thanh: nền tròn riêng, dễ nhấn (cao 48)
                    Button { undo(); store.toast = nil } label: {
                        Label(L("Hoàn tác"), systemImage: "arrow.uturn.backward")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.horizontal, 18).frame(height: 48)
                            .background(Palette.ctaInk.opacity(0.14), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(Pressable())
                }
            }
            .foregroundStyle(Palette.ctaInk)
            .padding(.leading, 20).padding(.trailing, t.undo == nil ? 22 : 7).padding(.vertical, t.undo == nil ? 15 : 7)
            // Phim: mờ từng phần (chữ, nền, bóng) thay vì mờ cả khối — khối có bóng mà mờ thì không vẽ ra PDF được
            .opacity(shown)
            .background(Palette.cta.opacity(shown), in: Capsule())
            .shadow(color: .black.opacity(0.18 * shown), radius: 16, y: 6)
            .offset(y: ((1 - shown) * 14).rounded())   // lùi xuống một chút rồi mờ đi, không chạm hai nút bên dưới
            .transition(.offset(y: 14).combined(with: .opacity))
            .task(id: t.id) {
                try? await Task.sleep(for: .seconds(5))
                if store.toast?.id == t.id { withAnimation { store.toast = nil } }
            }
        }
    }
}
