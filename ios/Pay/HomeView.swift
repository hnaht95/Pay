import SwiftUI

/// Mở màn hình nhập số tiền theo từng tình huống
enum EntryMode: Identifiable {
    case new(cat: String?)
    case scan(VietQR)
    case raw(String)
    /// Nhập kèm ảnh hoá đơn vừa chụp (vuốt lên ở nút Nhập)
    case receipt(UIImage)
    case edit(Expense)
    /// Như .edit nhưng mở ra là sửa được ngay: người dùng vừa bấm hẳn "Sửa" (thẻ nói, bảng nhấn giữ), không qua bước chỉ xem
    case editNow(Expense)

    var id: String {
        switch self {
        case .new(let c): return "new-\(c ?? "")"
        case .scan(let q): return "scan-\(q.raw)"
        case .raw(let s): return "raw-\(s)"
        case .receipt(let img): return "receipt-\(ObjectIdentifier(img).hashValue)"
        case .edit(let e), .editNow(let e): return "edit-\(e.id)"
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var quick: QuickAction
    @State private var entry: EntryMode?
    @State private var scanning = false
    @State private var receiptScan = false
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showStats = false
    @State private var showHouse = false
    @State private var listening = false
    /// Lượt mở thẻ nói qua fullScreenCover, mỗi lần mở là một lượt mới (xem listen()). Thẻ chỉ tự đóng được khi còn
    /// đúng lượt của nó: lệnh đóng còn treo của thẻ cũ (tự đóng 5 giây sau "Đã ghi") không đóng nhầm thẻ vừa mở lại
    @State private var voiceRound = 0
    /// Thẻ nói để ghi mở bằng vuốt lên từ nút Quét QR: khung của nút, thẻ biến hình từ đó ra thay vì trượt lên từ đáy
    @State private var voiceFrom: CGRect?
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
            // Thanh "Đã xoá · Hoàn tác" nằm trên lớp mờ nhưng dưới hai nút: trồi lên từ sau dải nút, ẩn thì chui xuống lại sau
            // đó, không bao giờ đè lên nút. iOS 26 dải nút là safeAreaBar nên đáy lớp này đã nằm ngay trên dải nút
            .withDock(dock: dock, fallbackBlur: bottomBlur, film: film != nil) { ToastView() }
        }
        .appMenu($menu)
        .overlay {
            // Phim: bảng nhấn giữ theo trạng thái phim đưa vào
            if let m = film?.menu, m.shown > 0 {
                AppMenu(spec: categoryMenu(Category.get(m.key)), close: {}, shown: m.shown,
                        pressed: film?.pressed["menu-item"].map { (0, $0) })
            }
        }
        // Nhập / sửa khoản chi mở dạng tấm (sheet) như danh mục, thống kê, cài đặt — không phủ kín màn hình
        .sheet(item: $entry) { EntryView(mode: $0).id($0.id).sheetGrabber() }   // id: đổi khoản khi tấm còn mở thì dựng lại từ đầu, không mang trạng thái của khoản trước
        .fullScreenCover(isPresented: $receiptScan) {
            ReceiptCamera { img in
                receiptScan = false
                guard let img else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(350))   // đợi màn chụp đóng hẳn rồi mới mở màn nhập
                    entry = .receipt(img)
                }
            }
        }
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
        .sheet(isPresented: $addingCat) { CategoryEditor().environmentObject(store).sheetGrabber() }
        .sheet(item: $editingCat) { CategoryEditor(editing: $0.cat).environmentObject(store).sheetGrabber() }
        // Vuốt lên từ nút Quét QR: thẻ nói để ghi là một lớp ngay trên màn hình chính, biến hình từ nút ra.
        // (fullScreenCover của iOS luôn trượt cả lớp từ đáy lên, làm hỏng hiệu ứng biến hình.)
        .overlay {
            if let voiceFrom {
                VoiceEntryView(from: voiceFrom, face: AnyView(BigButton.face(title: L("Quét QR"), icon: "qrcode", primary: true)), onClose: { self.voiceFrom = nil }, onScan: {
                    Task { try? await Task.sleep(for: .milliseconds(450)); scanning = true }
                }, onEdit: { e in
                    Task { try? await Task.sleep(for: .milliseconds(450)); entry = .editNow(e) }
                })
                .environmentObject(store)
            }
        }
        .fullScreenCover(isPresented: $listening, onDismiss: {}) {
            // Thẻ đóng qua onClose kèm số lượt (xem voiceRound), không dùng dismiss của chính nó
            let round = voiceRound
            VoiceEntryView(onClose: { if round == voiceRound { listening = false } }, onScan: {
                Task { try? await Task.sleep(for: .milliseconds(450)); scanning = true }
            }, onEdit: { e in
                Task { try? await Task.sleep(for: .milliseconds(450)); entry = .editNow(e) }
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
        ReceiptPhotos.refreshCloudIndex()
    }

    /// Mở thẳng màn hình quét / nhập. Đang mở màn hình khác thì đóng hết trước rồi mới mở.
    private func run(_ k: QuickKind) async {
        let busy = entry != nil || scanning || showHistory || showSettings || showStats || showHouse || listening || listing != nil
            || addingCat || editingCat != nil
        // Thẻ nói còn mở thì không bỏ qua lệnh nói: thẻ có thể đã ngừng nghe từ lâu (đã ghi, chưa nghe rõ, thiếu quyền micro),
        // ở đây không biết được, nên đóng rồi mở lại để nghe ngay
        if k == .scan && scanning { return }
        entry = nil; scanning = false; showHistory = false; showSettings = false; showStats = false; showHouse = false; listening = false; listing = nil; voiceFrom = nil
        addingCat = false; editingCat = nil; menu = nil
        if busy { try? await Task.sleep(for: .milliseconds(450)) }
        switch k {
        case .scan: scanning = true
        case .add: entry = .new(cat: nil)
        case .voice: listen()
        }
    }

    /// Mở thẻ nói qua fullScreenCover; mỗi lần mở là một lượt mới (xem voiceRound).
    private func listen() {
        voiceRound += 1
        listening = true
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
        // Gom theo danh mục đang có: khoản của danh mục tự tạo đã xoá (hoặc chưa đồng bộ về máy này) tính vào Khác,
        // đúng như hàng của nó đang hiện, để tổng các ô vẫn bằng tổng tháng
        for e in store.monthItems(now) { perCat[Category.get(e.c).k, default: 0] += e.a }
        // Mỗi danh mục dài cả hàng hoặc nửa hàng (đổi trong bảng nhấn giữ). Ô nửa hàng đứng lẻ ngay trước một ô dài
        // thì giãn ra cho kín hàng. Nút thêm danh mục là một dòng thấp riêng ở cuối, dài cả hàng.
        var rows: [[Category?]] = [], half: [Category?] = []
        for c in Category.all {
            if store.isWide(c.k) {
                if !half.isEmpty { rows.append(half); half = [] }
                rows.append([c])
            } else {
                half.append(c)
                if half.count == 2 { rows.append(half); half = [] }
            }
        }
        if !half.isEmpty { rows.append(half) }
        return VStack(spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, c in
                        if let c {
                            // Chạm: xem các khoản của danh mục; nhấn giữ: bảng tuỳ chọn tự vẽ; dấu + ở góc: nhập khoản
                            TapHold(tap: { listing = c }, hold: { menu = categoryMenu(c) }) {
                                tile(c, total: perCat[c.k] ?? 0)
                            }
                            .filmPressed(film?.pressed["tile-" + c.k] ?? 0)
                            // Dấu + ở góc: nhập khoản mới cho danh mục này
                            .overlay(alignment: .topTrailing) {
                                Button { entry = .new(cat: c.k) } label: {
                                    Image(systemName: "plus").font(.system(size: 16, weight: .bold))
                                        .frame(width: 30, height: 30)
                                        .foregroundStyle(Color(hex: 0x111114))
                                        .padding(16).contentShape(Rectangle())
                                }
                                .buttonStyle(Pressable())
                                .accessibilityLabel(L("Nhập khoản %@", c.name))
                            }
                        }
                    }
                    // Ô nửa hàng đứng lẻ ở cuối vẫn chỉ rộng nửa hàng
                    if row.count == 1, let c = row[0], !store.isWide(c.k) { Color.clear.frame(maxWidth: .infinity) }
                }
            }
            addTile
        }
    }

    /// Dòng cuối: tạo danh mục riêng. Thấp, dài cả hàng, dấu + nhỏ và chữ ở giữa (giống nút Tạo nhóm mới)
    private var addTile: some View {
        Button { addingCat = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 16, weight: .bold))
                Text(L("Thêm danh mục")).font(.system(size: 17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 64)
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
        let month = store.monthItems(now).filter { Category.get($0.c).k == c.k }
        var items = [
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
                    TapHold(tap: { entry = .edit(e) }, hold: { menu = expenseMenu(e, store: store) { entry = .editNow(e) } }) {
                        ExpenseRow(e: e, showDay: true, now: now, repeats: store.rule(for: e) != nil)
                    }
                    .expenseSwipe(delete: { withAnimation(.snappy(duration: 0.3)) { store.remove(id: e.id) } })
                }
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            // Không cắt ở mép khung: lúc xoá, hàng mới trượt vào từ dưới bị xẻ ngang ở mép dưới danh sách
            .scrollClipDisabled()
            .frame(height: CGFloat(list.count) * ExpenseRow.rowHeight)
        }
    }

    /// iOS 26: chừa chỗ cho thanh nút bằng safeAreaBar (không cần đệm 120pt ở cuối nội dung).
    static var nativeEdge: Bool { if #available(iOS 26.0, *) { true } else { false } }

    /// Lớp mờ dưới đáy (mọi phiên bản iOS): mờ đậm sát cạnh dưới, nhạt dần lên trên, để nút nổi dễ nhìn khi nội dung cuộn qua.
    @ViewBuilder private var bottomBlur: some View {
        if film != nil {
            // Phim: cùng các mốc ấy, bằng dải màu đặc (xem FilmFade)
            FilmFade(color: Palette.bg, stops: [(0, 1), (0.28, 1), (0.45, 0.85), (0.62, 0.55), (0.8, 0.25), (1, 0)], height: 170)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        } else {
            bottomGradient
        }
    }

    private var bottomGradient: some View {
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
                // Chạm: nhập tay. Vuốt lên: chụp hoá đơn rồi mở màn nhập với ảnh hoá đơn đính kèm
                BigButton(title: L("Nhập"), icon: "plus", primary: false, swipeUp: { _ in receiptScan = true }) { entry = .new(cat: nil) }
                // Chạm: quét QR. Vuốt lên: thẻ nói để ghi phóng ra từ chính nút này
                // Đang là thẻ nói để ghi (biến hình từ nút này ra): nút thật không vẽ gì (ghost), chỉ còn khối biến hình
                BigButton(title: L("Quét QR"), icon: "qrcode", primary: true, ghost: voiceFrom != nil, swipeUp: { frame in
                    // VoiceOver: mở qua fullScreenCover, để thẻ là một màn hình riêng (tiêu điểm chuyển vào thẻ, phần phía sau
                    // không còn chọn được); lớp phủ biến hình chỉ là hiệu ứng để nhìn
                    if UIAccessibility.isVoiceOverRunning { listen(); return }
                    voiceFrom = frame
                    // Thẻ hiện ngay trên màn hình chính (xem lớp phủ bên dưới), không qua fullScreenCover
                }) { scanning = true }
            }
        }
        .padding(.horizontal, 16)
            // Sát vạch Home hơn (cách mép dưới 16 điểm, bằng lề hai bên): để nguyên vùng an toàn 34 điểm + 8 thì
            // dưới hai nút trống một khoảng lớn
            .padding(.bottom, HomeView.nativeEdge ? -18 : 8)
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
    /// Hàng khoản chi trong List: vuốt sang trái hiện nút Xoá (chạm vào hàng để sửa), không kẻ dòng, nền trong suốt.
    func expenseSwipe(delete: @escaping () -> Void) -> some View { modifier(ExpenseSwipe(delete: delete)) }
}

/// Bấm Xoá: hàng trượt sang trái và mờ đi (nút đỏ mờ theo khi thao tác vuốt đóng lại), xong mới xoá để các hàng dưới
/// trượt lên. Không dùng nút xoá kiểu destructive / vuốt hết cỡ của iOS: nó kéo nút đỏ dài hết hàng rồi cắt lẫn vào hàng dưới.
private struct ExpenseSwipe: ViewModifier {
    let delete: () -> Void
    @State private var gone = false

    func body(content: Content) -> some View {
        content
            .offset(x: gone ? -420 : 0)
            .opacity(gone ? 0 : 1)
            .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                // Chỉ biểu tượng, không chữ; tên vẫn có cho VoiceOver
                Button {
                    withAnimation(.easeIn(duration: 0.22)) { gone = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { delete() }
                    // Xoá xong (hàng đã rời danh sách) thì trả trạng thái về như cũ: bấm Hoàn tác, khoản quay lại đúng mã cũ và
                    // List dựng lại ô với trạng thái còn giữ — để "đã trượt đi" thì chỗ đó trắng trơn
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { gone = false }
                } label: { Image(systemName: "trash.fill") }
                .tint(.red)
                .accessibilityLabel(L("Xoá"))
            }
    }
}

struct ExpenseRow: View {
    /// Cao một hàng kể cả khoảng cách 10pt giữa các hàng (thẻ 86pt: vừa tên hai dòng + dòng phụ).
    static let rowHeight: CGFloat = 96
    /// Bo góc của thẻ (bằng ô danh mục) và khoảng cách từ ô biểu tượng tới mép thẻ: ô 56pt trong thẻ cao 86pt
    /// cách trên dưới 15pt, nên bên trái cũng 15pt
    static let radius: CGFloat = 28, inset: CGFloat = 15
    let e: Expense
    var showDay = false
    var now = Date()
    /// Khoản định kỳ (app tự ghi hằng tháng): hiện biểu tượng lặp
    var repeats = false
    /// Danh mục của khoản, lấy sẵn lúc dựng hàng chứ không đọc trong body: Category.custom / edited là biến static, SwiftUI
    /// không theo dõi, nên phải là một đầu vào thì sửa / xoá danh mục xong hàng mới vẽ lại
    private let c: Category
    /// Vị trí ngang bình thường của hàng và hàng đang bị vuốt sang trái (xem ô biểu tượng bên dưới)
    @State private var restX: CGFloat?
    @State private var swiped = false

    init(e: Expense, showDay: Bool = false, now: Date = Date(), repeats: Bool = false) {
        self.e = e; self.showDay = showDay; self.now = now; self.repeats = repeats
        c = Category.get(e.c)
    }

    var body: some View {
        HStack(spacing: 14) {
            CategoryIcon(c: c, size: 30)
                .frame(width: 56, height: 56)
                // Bo đồng tâm với thẻ: bo của thẻ trừ đi khoảng cách tới mép
                .background(c.color, in: RoundedRectangle(cornerRadius: Self.radius - Self.inset, style: .continuous))
                // Có ảnh hoá đơn đính kèm: chấm xanh lá (màu icon app) ở góc trên phải ô biểu tượng, viền màu thẻ cho tách nền
                .overlay(alignment: .topTrailing) {
                    if ReceiptPhotos.has(e.id) {
                        // Vòng màu thẻ vẽ dưới, chấm xanh nhỏ hơn đè lên giữa: vẽ viền đè lên chấm xanh cùng cỡ thì mép xanh
                        // (khử răng cưa) lộ ra ngoài viền thành một vệt mảnh
                        Circle().fill(Palette.card).frame(width: 12, height: 12)
                            .overlay(Circle().fill(Color(hex: 0x61BE6E)).frame(width: 7, height: 7))
                            .offset(x: 3, y: -3)
                            .accessibilityLabel(L("Có ảnh hoá đơn"))
                    }
                }
                // Vuốt để xoá: danh sách cắt hàng ở mép trái, ô biểu tượng trượt gần hết ra ngoài nhưng còn lộ một vệt nền màu.
                // Hàng lệch khỏi chỗ cũ thì ô biểu tượng mờ đi
                .opacity(swiped ? 0 : 1)
                .animation(.easeOut(duration: 0.15), value: swiped)
            HStack(spacing: 6) {
                // Tên dài thì xuống dòng thứ hai thay vì bị cắt "…"
                Text((e.n?.isEmpty == false ? e.n!.capFirst : c.name)).font(.system(size: 17, weight: .semibold))
                    .lineLimit(2).multilineTextAlignment(.leading).lineSpacing(-1)
                if repeats {
                    Image(systemName: "repeat").font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary)
                        .accessibilityLabel(L("Hằng tháng"))
                }
            }
            Spacer(minLength: 8)
            // Bên phải: số tiền, dưới là ngày | giờ (vạch dọc mảnh, mờ ngăn giữa). Luôn hiện đủ: phần tên nhường chỗ
            VStack(alignment: .trailing, spacing: 3) {
                Text(fmt(e.a)).font(.system(size: 18, weight: .bold)).lineLimit(1)
                HStack(spacing: 9) {
                    let parts = when
                    ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                        if i > 0 { Rectangle().fill(Color.primary.opacity(0.18)).frame(width: 1, height: 13) }
                        Text(p).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .fixedSize().layoutPriority(1)
        }
        .foregroundStyle(.primary)
        .padding(.leading, Self.inset).padding(.trailing, 16).padding(.vertical, 12)
        .frame(minHeight: Self.rowHeight - 10)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { x in
            // Chỗ đứng yên là chỗ xa bên phải nhất từng thấy (lúc mới hiện có thể đang trượt vào)
            if restX == nil || x > restX! { restX = x }
            swiped = x < (restX ?? x) - 12
        }
    }

    /// Ngày (nếu cần) và giờ của khoản chi
    private var when: [String] {
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        var parts: [String] = []
        if showDay {
            let cal = Calendar.current
            if cal.isDate(e.date, inSameDayAs: now) { parts.append(L("Hôm nay")) }
            else if Lang.isEnglish { let df = DateFormatter(); df.locale = Lang.locale; df.dateFormat = "MMM d"; parts.append(df.string(from: e.date)) }
            else { let d = cal.dateComponents([.day, .month], from: e.date); parts.append("\(d.day!)/\(d.month!)") }
        }
        parts.append(tf.string(from: e.date))
        return parts
    }
}

struct BigButton: View {
    static let inset: CGFloat = 11
    let title: String
    let icon: String
    let primary: Bool
    /// Việc làm khi vuốt lên từ nút (nếu có)
    /// Giữ chỗ nhưng không vẽ gì, kể cả nền kính (opacity không ẩn được nền kính của iOS 26)
    var ghost = false
    var swipeUp: ((CGRect) -> Void)? = nil
    /// Khung của nút trên màn hình, để thẻ nói để ghi biến hình từ đúng chỗ này ra
    @State private var frame: CGRect = .zero
    let action: () -> Void
    /// Nút có vuốt lên thì tự theo dõi ngón tay: đang nhấn, và lần nhấn này đã ra việc gì chưa
    @State private var down = false
    @State private var fired = false
    /// Ngón tay còn trên nút không; iOS tự đưa về false cả khi cử chỉ bị huỷ (vd màn hình khác vừa mở đè lên)
    @GestureState private var touching = false

    var body: some View {
        if let swipeUp {
            // Tự xử lý bằng một cử chỉ, mỗi lần nhấn chỉ ra đúng một việc: kéo lên quá 30pt là vuốt lên (làm ngay,
            // nhả tay không làm gì nữa), nhả tại chỗ là chạm, kéo đi hướng khác rồi nhả là bỏ.
            label
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
                .scaleEffect(down ? 0.94 : 1).opacity(down ? 0.72 : 1)
                .animation(down ? .easeOut(duration: 0.08) : .spring(duration: 0.3, bounce: 0.35), value: down)
                .gesture(DragGesture(minimumDistance: 0)
                    .updating($touching) { _, on, _ in on = true }
                    .onChanged { v in
                        guard !fired else { return }
                        down = true
                        let up = -v.translation.height
                        if up > 30, abs(v.translation.width) < 50 {
                            fired = true; down = false
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            swipeUp(frame)
                        }
                    }
                    .onEnded { v in
                        let tapped = !fired && abs(v.translation.width) < 24 && abs(v.translation.height) < 24
                        down = false
                        if tapped { action() }
                    })
                // Ngón tay rời nút (nhả hoặc bị huỷ): dọn trạng thái để lần nhấn sau bắt đầu lại từ đầu
                .onChange(of: touching) { _, on in
                    guard !on else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { if !touching { fired = false; down = false } }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { action() }
                .accessibilityAction(named: Text(L("Nói để ghi"))) { swipeUp(frame) }
                // Đang ẩn (đã thành thẻ nói): mặt nút không vẽ nhưng phần tử trợ năng bọc ngoài vẫn còn, phải ẩn theo
                .accessibilityHidden(ghost)
        } else {
            Button(action: action) { label }.buttonStyle(Pressable())
        }
    }

    @ViewBuilder private var label: some View {
        if ghost {
            Self.face(title: title, icon: icon, primary: primary).hidden()
        } else {
            Self.face(title: title, icon: icon, primary: primary)
                .contentShape(Capsule())
                .glassCapsule(tint: primary ? Palette.cta : nil)
        }
    }

    /// Mặt nút (vòng biểu tượng + chữ), chưa có nền. Vòng icon cách đều mép nút ở trên, dưới và bên trái (cùng tâm với
    /// đầu nút bo tròn). Nút phụ ôm vừa chữ; nút chính lấy phần còn lại, chữ nằm giữa khoảng trống sau icon.
    /// Thẻ nói để ghi cũng vẽ mặt này lên khối biến hình, để nút và thẻ là một khối liền.
    static func face(title: String, icon: String, primary: Bool) -> some View {
        // icon rỗng: nút chỉ có chữ ở giữa, cao bằng nút có icon (vd Xoá / Sửa ở màn sửa khoản chi). Không đặt một khung trống
        // vào hàng: khung rộng 0 vẫn ăn một khoảng cách 10 pt, đẩy chữ lệch sang phải 5 pt so với giữa nút
        HStack(spacing: icon.isEmpty ? 0 : 10) {
            if icon.isEmpty {
                Color.clear.frame(width: 0, height: 56)
            } else {
                Image(systemName: icon).font(.system(size: 24, weight: .semibold))
                    .frame(width: 56, height: 56)
                    .background(primary ? Palette.ctaInk.opacity(0.14) : Color.primary.opacity(0.08), in: Circle())   // theo màu chữ của nút: chế độ tối nút trắng thì vòng xám, không bị mất
            }
            if primary || icon.isEmpty { Spacer(minLength: 0) }
            Text(title).font(.system(size: 21, weight: .semibold)).lineLimit(1)
                // Chữ được ưu tiên chỗ trước hai khoảng trống hai bên: không thì khi bật Chữ đậm (Trợ năng)
                // chữ rộng ra mà vẫn bị cắt thành "Quét…" dù nút còn trống
                .layoutPriority(1)
                .minimumScaleFactor(0.7)
            if primary || icon.isEmpty { Spacer(minLength: 0) }
        }
        .padding(BigButton.inset)
        .padding(.trailing, icon.isEmpty ? 0 : 14)
        .frame(maxWidth: primary || icon.isEmpty ? .infinity : nil)
        .foregroundStyle(primary ? Palette.ctaInk : .primary)
    }
}

extension View {
    /// Gắn thanh nút ở đáy. iOS 26: safeAreaBar + mép cuộn mờ dần của hệ thống. iOS cũ: tự phủ lớp mờ.
    /// above: lớp nằm trên lớp mờ, dưới hai nút, sát mép trên dải nút (vd thanh "Đã xoá · Hoàn tác"). iOS 26: là lớp phủ riêng
    /// của màn hình (safeAreaBar đẩy đáy vùng an toàn lên tới mép trên dải nút), không gắn vào dải nút: gắn vào dải thì lớp mờ
    /// cạnh cuộn của hệ thống tính theo cả nó, thanh biến mất là lớp mờ đổi theo
    @ViewBuilder func withDock<D: View, B: View, A: View>(dock: D, fallbackBlur: B, film: Bool = false,
                                                          @ViewBuilder above: () -> A = { EmptyView() }) -> some View {
        let attached = dock.background(alignment: .top) { above().alignmentGuide(.top) { $0[.bottom] + 8 } }
        if film {
            overlay(alignment: .bottom) { ZStack(alignment: .bottom) { fallbackBlur; attached.padding(.bottom, FilmScreen<EmptyView>.insets.bottom) } }
        } else if #available(iOS 26.0, *) {
            // Mép mờ của hệ thống quá nhẹ trên máy thật, nên phủ thêm lớp mờ tự làm phía dưới thanh nút
            overlay(alignment: .bottom) { fallbackBlur }
                .overlay(alignment: .bottom) { above().padding(.bottom, 8) }
                .safeAreaBar(edge: .bottom) { dock }
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            overlay(alignment: .bottom) { ZStack(alignment: .bottom) { fallbackBlur; attached } }
        }
    }
}

/// Trước đây gom nút kính của iOS 26; giờ nút vẽ phẳng nên chỉ trả lại nội dung.
struct GlassGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { content }
}

extension View {
    /// Nền phẳng hình viên thuốc (kiểu Peek): nút chính màu đặc, nút phụ xám nhạt; không kính, không viền, không bóng.
    func glassCapsule(tint: Color?) -> some View {
        background { Capsule().fill(tint ?? Palette.pill) }
    }
}

extension View {
    /// Mép trên vùng cuộn mờ dần dưới thanh tiêu đề (kiểu mềm của iOS 26), như màn nhóm chung — không phải vạch cắt ngang
    @ViewBuilder func softTopEdge() -> some View {
        if #available(iOS 26.0, *) { scrollEdgeEffectStyle(.soft, for: .top) } else { self }
    }

    /// Tiêu đề màn hình: cỡ 21 đậm, bằng "Sửa / Lưu khoản chi" (tiêu đề mặc định của iOS nhỏ quá)
    func screenTitle(_ title: String) -> some View {
        navigationTitle(title).toolbar {
            ToolbarItem(placement: .principal) { Text(title).font(.system(size: 21, weight: .bold)).lineLimit(1) }
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

    /// Hiện / ẩn / đổi thông báo luôn có hiệu ứng (trượt lên + hiện dần) dù chỗ gọi có bọc withAnimation hay không:
    /// trước đây chỉ lúc tự ẩn sau 5 giây là mượt, còn lúc hiện ("Đã xoá") và lúc bấm Hoàn tác thì bật / tắt phụt.
    var body: some View {
        ZStack(alignment: .bottom) { bar }
            // Hiện: lò xo nảy rõ. Ẩn: trượt êm không nảy (dùng chung lò xo nảy thì lúc ẩn thanh giật lên rồi mới rơi, trông gắt)
            .animation(film == nil ? (store.toast == nil ? .easeInOut(duration: 0.38) : .spring(response: 0.38, dampingFraction: 0.6)) : nil,
                       value: store.toast?.id)
    }

    @ViewBuilder private var bar: some View {
        if let t = store.toast {
            HStack(spacing: 14) {
                // Báo lỗi (vd lưu khoản chung thất bại) thì không vẽ dấu tích thành công
                Image(systemName: t.error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill").font(.system(size: 18))
                // Câu dài (vd "Sẽ tự ghi ngày 28 hằng tháng, lần tới 28/11", câu báo lỗi) xuống dòng thứ hai thay vì bị cắt "…"
                Text(t.message).font(.system(size: 17, weight: .medium))
                    .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                if let undo = t.undo {
                    // Nút thật nằm trong thanh: nền tròn riêng, dễ nhấn (cao 48)
                    Button { undo(); store.toast = nil } label: {
                        Label(L("Hoàn tác"), systemImage: "arrow.uturn.backward")
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1).fixedSize()   // không xuống dòng "Hoàn / tác" khi câu thông báo dài
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
            .padding(.horizontal, 16)   // thanh dài hết cỡ vẫn cách hai mép màn hình, bằng lề của nội dung
            .offset(y: ((1 - shown) * 14).rounded())   // lùi xuống một chút rồi mờ đi, không chạm hai nút bên dưới
            // Trồi lên từ sau dải nút, ẩn thì trượt xuống chui lại sau đó (thanh nằm dưới lớp dải nút, xem HomeView)
            // Chỉ lùi xuống 22 điểm (chạm nhẹ mép trên hai nút): lùi sâu thì thanh đậm lộ ra ở khe giữa hai nút. Hiện dần từ trong
            // suốt nên không thấy một khối đậm bật ra
            .transition(.asymmetric(
                insertion: .offset(y: 22).combined(with: .opacity.animation(.easeOut(duration: 0.3))),
                removal: .offset(y: 16).combined(with: .scale(scale: 0.96, anchor: .bottom)).combined(with: .opacity.animation(.easeOut(duration: 0.32)))))
            .task(id: t.id) {
                // 3 giây: đủ để kịp bấm Hoàn tác, không nằm lâu che màn hình. Bị huỷ giữa chừng (thanh được dựng lại, vd lúc màn
                // hình Sửa vừa đóng) thì thôi, task mới sẽ đếm lại: không kiểm tra thì thanh vừa hiện đã tắt ngay
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                if store.toast?.id == t.id { store.toast = nil }
            }
        }
    }
}
