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
    /// Lượt thẻ nói hiện tại được dựng đè lên thẻ cũ còn đang hiện (xem run): thẻ mới hiện tại chỗ, không trượt lên
    @State private var voiceRenewed = false
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
    @AppStorage(HeroColor.key) private var heroTone = -1
    /// Mục Gần đây xem dạng lưới ảnh (3 cột, ảnh hoá đơn và số tiền) thay cho danh sách
    @AppStorage("recentGrid") private var recentGrid = false
    /// Kiểu đang vẽ ở mục Gần đây. Đổi theo recentGrid nhưng qua withAnimation: recentGrid là @AppStorage, thay đổi đến qua
    /// UserDefaults nên không mang hiệu ứng, kiểu cũ biến mất và kiểu mới hiện ra tức thì
    @State private var gridShown = UserDefaults.standard.bool(forKey: "recentGrid")
    /// Lưới so le: chiều cao từng cột khi chưa tính ô cuối (đo được), để ô cuối mỗi cột co giãn cho ba cột cùng một đáy
    @State private var gridCols: [Int: CGFloat] = [:]
    @AppStorage(HeroColor.barKey) private var heroBarTone = -1
    @State private var pickingHero = false
    /// Đang đặt / điều chỉnh số dư hiện có
    @State private var balanceOpen = false
    /// Bảng trả thẻ tín dụng (chạm dòng Nợ thẻ dưới số dư)
    @State private var cardOpen = false
    /// Số dư đang hiện (mặc định che bằng chấm); tự che lại sau ít giây hoặc khi rời app
    @State private var balanceShown = false
    @State private var hideBalance: Task<Void, Never>?
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
                    // Chạm: mở Thống kê; nhấn giữ: đổi màu thẻ
                    TapHold(tap: { showStats = true }, hold: {
                        // Đầu bảng như bảng nhấn giữ danh mục: ô bo góc màu thẻ, biểu tượng ở giữa
                        menu = AppMenuSpec(icon: AnyView(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(HeroColor.bg(heroTone))
                                                            .overlay(Text("💸").font(.system(size: 30)))
                                                            .frame(width: 56, height: 56)),
                                           title: L("Hôm nay đã chi"), subtitle: nil,
                                           items: [AppMenuItem(icon: "pencil.tip.crop.circle", title: L("Đổi màu thẻ"), plain: true) { pickingHero = true }])
                    }) { hero(now) }
                        .padding(.top, 14)

                    sectionTitle(L("Danh mục")) { Text(monthLabel(now)) }
                    tiles(now)

                    sectionTitle(L("Gần đây"), accessory: {
                        // Đổi kiểu xem: danh sách / lưới ảnh
                        if film == nil {
                            Button { recentGrid.toggle() } label: {
                                // Cùng cỡ chữ thì hình ba vạch nhỏ hơn hẳn hình hai tấm ảnh (đo: 85×81 so với 109×126): tăng cỡ ba vạch, giảm cỡ hai tấm
                                // cho hai biểu tượng trông to bằng nhau (~18×17 và ~17×20 điểm)
                                Image(systemName: gridShown ? "lineweight" : "rectangle.portrait.on.rectangle.portrait.angled.fill")
                                    .font(.system(size: gridShown ? 21 : 16, weight: .semibold))
                                    // Đổi biểu tượng kiểu thay hình của SF Symbols (hình cũ thu nhỏ biến đi, hình mới bật ra), nhanh gọn hơn mờ chéo
                                    .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                                    .frame(width: 37, height: 37)   // vùng chạm cao bằng viên "Xem tất cả" bên cạnh; không nền
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(Pressable()).foregroundStyle(.primary)
                            .accessibilityLabel(gridShown ? L("Xem dạng danh sách") : L("Xem dạng lưới ảnh"))
                        }
                    }) {
                        Button { showHistory = true } label: {
                            // To hơn nhãn "Tháng 10" ở mục Danh mục một chút: đây là nút bấm
                            Text(L("Xem tất cả")).font(.system(size: 15, weight: .medium))
                                .padding(.horizontal, 3).padding(.vertical, 3)
                        }
                        .buttonStyle(Pressable()).foregroundStyle(.primary)
                    }
                    recent
                }
                .padding(.horizontal, 16)
                // Cuộn hết: đáy nội dung cách mép trên hai nút đúng 16 (bằng lề hai bên). Nút cao 78, đáy nút cách mép màn 16, vùng
                // an toàn dưới 34: 16 + 78 + 16 − 34 = 76. Danh sách giữ 120 (hàng cuối đã có sẵn khoảng 10 dưới thẻ)
                .padding(.bottom, gridShown && film == nil && !store.activity.isEmpty ? 76 : 120)
                .padding(.top, film == nil ? 0 : FilmScreen<EmptyView>.insets.top)
            }
            .statusBarEdge(on: film == nil)
            // Thanh "Đã xoá · Hoàn tác" nằm trên lớp mờ nhưng dưới hai nút: trồi lên từ sau dải nút, ẩn thì chui xuống lại sau
            // đó, không bao giờ đè lên nút. iOS 26 dải nút là safeAreaBar nên đáy lớp này đã nằm ngay trên dải nút
            .withDock(dock: dock, fallbackBlur: bottomBlur, film: film != nil) { ToastView() }
        }
        .appMenu($menu)
        // Đổi kiểu xem: kiểu cũ mờ đi, kiểu mới mờ vào và nở nhẹ từ trên xuống (xem swapStyle)
        .onChange(of: recentGrid) { _, v in withAnimation(.snappy(duration: 0.35)) { gridShown = v } }
        .sheet(isPresented: $pickingHero) { HeroColorSheet() }
        .sheet(isPresented: $balanceOpen) { BalanceSheet().environmentObject(store).sheetGrabber() }
        .sheet(isPresented: $cardOpen) { CardPaySheet().environmentObject(store).sheetGrabber() }
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
            // Chụp xong: màn nhập kèm ảnh mở ngay trên màn chụp (không đóng màn chụp về trang chủ rồi mới mở). Lưu / huỷ ở màn
            // nhập thì cả màn chụp lẫn màn nhập cùng trượt xuống một lượt
            ReceiptFlow(store: store) { receiptScan = false }
        }
        .fullScreenCover(isPresented: $scanning, onDismiss: {
            guard let s = scanned else { return }
            scanned = nil
            entry = VietQR.parse(s).flatMap { $0.acct != nil ? EntryMode.scan($0) : nil } ?? .raw(s)
        }) {
            ScannerView { code in scanned = code; scanning = false }
        }
        .sheet(isPresented: $showHistory) { HistoryView().environmentObject(store).sheetCorners() }
        .sheet(item: $listing) { HistoryView(category: $0.k).environmentObject(store).sheetCorners() }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store).sheetCorners() }
        .sheet(isPresented: $showStats) { StatsView().environmentObject(store).sheetCorners() }
        .sheet(isPresented: $showHouse) { HouseView().environmentObject(store).sheetCorners() }
        // initial: mở app từ thông báo Nhóm chung khi app đang tắt, cờ đã bật trước khi màn này kịp theo dõi. Đang mở màn khác thì
        // đóng hết trước (tấm mới không hiện được đè lên tấm đang mở)
        .onChange(of: quick.openHouse, initial: true) { _, v in
            guard v else { return }
            quick.openHouse = false
            Task {
                let busy = entry != nil || scanning || receiptScan || showHistory || showSettings || showStats || listening || listing != nil
                    || addingCat || editingCat != nil || balanceOpen || cardOpen || pickingHero || voiceFrom != nil
                guard !showHouse else { return }
                entry = nil; scanning = false; receiptScan = false; showHistory = false; showSettings = false; showStats = false
                listening = false; listing = nil; voiceFrom = nil; addingCat = false; editingCat = nil; menu = nil
                balanceOpen = false; cardOpen = false; pickingHero = false
                if busy { try? await Task.sleep(for: .milliseconds(450)) }
                showHouse = true
            }
        }
        // Khởi động trước camera trong nền sau khi trang chủ hiện ra, để lần vuốt Nhập đầu tiên mở camera nhanh như các lần sau
        .task { try? await Task.sleep(for: .seconds(1)); ReceiptCam.prewarm() }
        #if DEBUG
        // Ảnh so sánh giữa các bản iOS (scripts/shots.sh): -shotOpen stats|settings|history|house|entry|voice|camera|balance|balancelog mở sẵn một màn
        .task {
            switch UserDefaults.standard.string(forKey: "shotOpen") {
            case "stats": showStats = true
            case "settings": showSettings = true
            case "history": showHistory = true
            case "house": showHouse = true
            case "entry": entry = .new(cat: nil)
            case "camera": receiptScan = true
            case "balance", "balancelog": balanceOpen = true
            case "card", "cardlog": cardOpen = true
            case "voice": voiceFrom = CGRect(x: 181, y: 780, width: 205, height: 78)   // khung nút Quét QR trên iPhone 16 Pro
            default: break
            }
            // -shotAdjust YES: đặt số dư rồi điều chỉnh một lần, để có các lần điều chỉnh
            if UserDefaults.standard.bool(forKey: "shotAdjust"), store.adjusts.isEmpty { store.setBalance(5_000_000); store.setBalance(4_820_000) }
            // -shotBudget N: đặt ngân sách tháng (0: bỏ ngân sách). -shotBalance N: đặt số dư
            let d = UserDefaults.standard
            if d.object(forKey: "shotBudget") != nil { store.budget = d.integer(forKey: "shotBudget") }
            if d.object(forKey: "shotBalance") != nil, store.adjusts.isEmpty { store.setBalance(d.integer(forKey: "shotBalance")) }
            // -shotCredit YES: số dư, ba khoản quẹt thẻ tín dụng, một lần trả thẻ; số dư hiện sẵn (không che)
            if UserDefaults.standard.bool(forKey: "shotCredit"), store.cardPays.isEmpty {
                if store.balance == nil { store.setBalance(12_500_000) }
                store.add(amount: 1_250_000, note: "Uniqlo", cat: "muasam", credit: true, toast: false)
                store.add(amount: 680_000, note: "Pizza 4P's", cat: "an", credit: true, toast: false)
                store.add(amount: 420_000, note: "Grab", cat: "dilai", credit: true, toast: false)
                store.payCard(500_000)
            }
            // -shotReveal YES / NO: số dư hiện sẵn / để che (mặc định: hiện khi có -shotCredit)
            if d.object(forKey: "shotReveal") != nil ? d.bool(forKey: "shotReveal") : d.bool(forKey: "shotCredit") { balanceShown = true }
            // Mở sẵn khoản quẹt thẻ mới nhất: -shotOpen creditedit (màn sửa) / creditmenu (bảng nhấn giữ)
            if let e = store.items.filter(\.isCredit).max(by: { $0.t < $1.t }) {
                switch UserDefaults.standard.string(forKey: "shotOpen") {
                case "creditedit": entry = .editNow(e)
                case "creditmenu": menu = expenseMenu(e, store: store) { entry = .editNow(e) }
                default: break
                }
            }
            // -shotWide an,cafe: kéo các ô danh mục đó dài cả hàng
            for k in (UserDefaults.standard.string(forKey: "shotWide") ?? "").split(separator: ",") { store.setWide(String(k), true) }
        }
        #endif
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
            VoiceEntryView(onClose: { if round == voiceRound { listening = false } }, instant: voiceRenewed, onScan: {
                Task { try? await Task.sleep(for: .milliseconds(450)); scanning = true }
            }, onEdit: { e in
                Task { try? await Task.sleep(for: .milliseconds(450)); entry = .editNow(e) }
            })
            .environmentObject(store)
            // Mỗi lượt một thẻ mới hẳn (micro, trạng thái nghe riêng), kể cả khi thẻ cũ còn đang hiện
            .id(voiceRound)
        }
        .onChange(of: scenePhase) { _, p in
            if p == .active { wake() } else { balanceShown = false }
            // Chuyển sang app khác: đóng luôn thẻ nói để ghi (tắt micro). Quay lại không còn thẻ cũ treo ở "Không bật được micro";
            // muốn nói thì bấm nút Tác vụ / vuốt lên từ Quét QR để mở thẻ mới
            if p == .background {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { voiceFrom = nil; listening = false }
            }
        }
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
        store.pruneReceiptPhotos()
    }

    /// Mở thẳng màn hình quét / nhập. Đang mở màn hình khác thì đóng hết trước rồi mới mở.
    private func run(_ k: QuickKind) async {
        // Thẻ nói đang mở mà lại gọi nói (bấm nút Tác vụ lần nữa): không đóng rồi mở lại thẻ, chỉ dựng thẻ mới tại chỗ (xem
        // voiceRound). Đóng rồi mở trong vài trăm mili giây thì iOS có khi giữ lại thẻ cũ, mà thẻ cũ đã tắt micro lúc bị đóng:
        // kẹt ở "Đang bật micro…"
        let renew = k == .voice && listening
        let busy = entry != nil || scanning || receiptScan || showHistory || showSettings || showStats || showHouse || (listening && !renew) || listing != nil
            || addingCat || editingCat != nil || balanceOpen || cardOpen || pickingHero
        // Thẻ nói còn mở thì không bỏ qua lệnh nói: thẻ có thể đã ngừng nghe từ lâu (đã ghi, chưa nghe rõ, thiếu quyền micro),
        // ở đây không biết được, nên đóng rồi mở lại để nghe ngay
        if k == .scan && scanning { return }
        if k == .photo && receiptScan { return }
        entry = nil; scanning = false; receiptScan = false; showHistory = false; showSettings = false; showStats = false; showHouse = false; listing = nil; voiceFrom = nil
        if !renew { listening = false }
        addingCat = false; editingCat = nil; menu = nil; balanceOpen = false; cardOpen = false; pickingHero = false
        if busy { try? await Task.sleep(for: .milliseconds(450)) }
        switch k {
        case .scan: scanning = true
        case .add: entry = .new(cat: nil)
        case .voice: listen()
        case .photo: if Pro.shared.allow(.photos) { receiptScan = true }
        }
    }

    /// Mở thẻ nói qua fullScreenCover; mỗi lần mở là một lượt mới (xem voiceRound).
    private func listen() {
        voiceRenewed = listening
        voiceRound += 1
        // Không dùng hiệu ứng trượt cả màn của fullScreenCover: thẻ tự trượt lên rồi, cộng thêm màn trượt nữa thì thẻ lên chậm
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { listening = true }
    }

    // MARK: Các phần

    private func header(_ now: Date) -> some View {
        HStack(spacing: 2) {
            // Logo app (thẻ xanh) thay chữ "Payso"
            Image("logo-pay").resizable().scaledToFit().frame(height: 30)
                .accessibilityLabel("Payso").accessibilityAddTraits(.isHeader)
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
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("Hôm nay đã chi"))
                Spacer()
                Text(dayLabel(now))
            }
            .font(.system(size: 15)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(fmt(store.total(on: now)))
                    .font(.system(size: 40, weight: .bold)).kerning(-1.5)
                    .minimumScaleFactor(0.5).lineLimit(1)
            }
            .padding(.top, 8)
            let bs = store.budgetStatus(now)
            if let bs {
                BudgetBar(s: bs, height: 6, track: heroTone < 0 ? Palette.pill : Color.primary.opacity(0.12), fill: HeroColor.bar(heroBarTone))
                    .padding(.top, 14)
            }
            // Hai cột cùng hàng: trái đã chi cả tháng / ngân sách (vượt thì số chi đỏ), phải số dư (chạm để đặt / chỉnh).
            // Hai bên luôn cùng một cỡ chữ: số dài quá thì cả hai cùng hạ một nấc, không bên nào co riêng, không xuống hàng
            ViewThatFits(in: .horizontal) {
                ForEach([17, 15, 13] as [CGFloat], id: \.self) { size in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L("Đã chi")).font(.system(size: 13)).foregroundStyle(.secondary)
                            (Text(fmt(month)).foregroundStyle(bs?.level == .over ? Palette.danger : Color.primary)
                             + Text(bs.map { "/" + fmt($0.budget) } ?? "").foregroundStyle(.secondary))
                                .font(.system(size: size, weight: .semibold))
                            // Cột Số dư có thêm dòng Nợ thẻ thì cột này cũng có dòng thứ ba cùng cỡ (còn / vượt ngân sách, chưa đặt
                            // ngân sách thì số khoản trong tháng), để hai cột cao bằng nhau, góc dưới trái không bị trống
                            if film == nil && store.cardDebt > 0 {
                                Group {
                                    if let bs {
                                        if bs.spent > bs.budget { Text(L("Vượt %@", fmt(bs.spent - bs.budget))).foregroundStyle(Palette.danger) }
                                        else { Text(L("Còn %@", fmt(bs.budget - bs.spent))).foregroundStyle(.secondary) }
                                    } else {
                                        Text(L("%d khoản", store.monthItems(now).count)).foregroundStyle(.secondary)
                                    }
                                }
                                .font(.system(size: 13))
                            }
                        }
                        .lineLimit(1).fixedSize()
                        Spacer(minLength: 0)
                        if film == nil { balanceColumn(size) }
                    }
                }
            }
            .padding(.top, 14)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeroColor.bg(heroTone), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        // Mặc định thẻ nền trắng chữ đen, kể cả chế độ tối (nổi trên nền đen); màu tối tự chọn thì chữ trắng
        .environment(\.colorScheme, HeroColor.scheme(heroTone))
    }

    /// Cột số dư hiện có: chưa đặt thì mời nhập; chạm để đặt / chỉnh
    /// Số dư che bằng chấm, chạm để hiện (8 giây rồi tự che lại); đang hiện thì chạm để đặt / chỉnh. Chưa đặt thì mời nhập
    private func balanceColumn(_ size: CGFloat) -> some View {
        let b = store.balance, debt = store.cardDebt
        return VStack(alignment: .trailing, spacing: 4) {
        Button {
            guard b != nil, !balanceShown else { balanceOpen = true; return }
            withAnimation(.snappy(duration: 0.2)) { balanceShown = true }
            hideBalance?.cancel()
            hideBalance = Task { try? await Task.sleep(for: .seconds(8)); if !Task.isCancelled { withAnimation(.snappy(duration: 0.2)) { balanceShown = false } } }
        } label: {
            VStack(alignment: .trailing, spacing: 3) {
                Text(L("Số dư")).font(.system(size: 13)).foregroundStyle(.secondary)
                if let b {
                    // Số và chấm chồng lên nhau, chỉ đổi độ mờ: khung luôn rộng bằng bên dài hơn nên hiện / che không làm cột đổi
                    // bề ngang. Đổi chữ thẳng thì bề ngang đổi theo, cả hàng (ViewThatFits) dàn lại giữa chừng hiệu ứng, số trượt từ
                    // mép ngoài thẻ vào / ra
                    ZStack(alignment: .trailing) {
                        Text(fmt(b)).foregroundStyle(b < 0 ? Palette.danger : Color.primary).opacity(balanceShown ? 1 : 0)
                        Text("••••••").foregroundStyle(Color.primary).opacity(balanceShown ? 0 : 1)
                    }
                    .font(.system(size: size, weight: .semibold))
                } else {
                    Text(L("Nhập số dư")).font(.system(size: size, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1).fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(Pressable())
        .accessibilityLabel(b == nil ? L("Nhập số dư") : balanceShown ? L("Số dư %@", fmt(b!)) : L("Số dư, chạm để hiện"))
            // Nợ thẻ tín dụng (khoản quẹt thẻ chưa trả): dòng nhỏ dưới số dư, che / hiện cùng số dư; chạm để trả thẻ.
            // Không nợ thì không có dòng này
            if debt > 0 {
                Button { cardOpen = true } label: {
                    // Cả dòng chồng lên nhau, căn phải: lúc che chữ "Chi tiêu thẻ" đứng sát dãy chấm (không cách một khoảng bằng số tiền)
                    ZStack(alignment: .trailing) {
                        Text(L("Chi tiêu thẻ") + " " + fmt(debt)).opacity(balanceShown ? 1 : 0)
                        Text(L("Chi tiêu thẻ") + " ••••").opacity(balanceShown ? 0 : 1)
                    }
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .lineLimit(1).fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(Pressable())
                .accessibilityLabel(balanceShown ? L("Chi tiêu thẻ %@, chạm để trả thẻ", fmt(debt)) : L("Chi tiêu thẻ, chạm để trả thẻ"))
            }
        }
    }

    /// Một ô của lưới so le ở mục Gần đây (height: ô cuối cột, cao theo đường đáy chung thay vì theo tỉ lệ ảnh)
    private func gridTile(_ e: Expense, height: CGFloat? = nil) -> some View {
        TapHold(tap: { if e.isAdjust { balanceOpen = true } else { entry = .edit(e) } },
                hold: { menu = expenseMenu(e, store: store) { entry = .editNow(e) } }) {
            ExpenseTile(e: e, free: true, height: height)
        }
    }

    /// accessory: nút tròn riêng đứng trước viên bên phải (vd đổi kiểu xem ở mục Gần đây)
    private func sectionTitle<T: View, A: View>(_ title: String, @ViewBuilder accessory: () -> A = { EmptyView() },
                                                @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 21, weight: .bold))
            Spacer()
            accessory()
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
                                        // Cùng màu tên và số tiền của ô: màu chữ của ô mờ 70% (nền tối thì trắng)
                                        .foregroundStyle(c.ink.opacity(0.7))
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
        Button { if Category.custom.count < Pro.freeCategories || Pro.shared.allow(.categories) { addingCat = true } } label: {
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

    /// Ô danh mục: biểu tượng, tên, số tiền tháng này. Dấu + ở góc nhập khoản mới cho danh mục đó.
    /// Ô dài cả hàng thì cao hơn và biểu tượng to hơn (180 / 72 thay vì 140 / 52), để không thành một dải dẹt
    private func tile(_ c: Category, total: Int) -> some View {
        let wide = store.isWide(c.k)
        return VStack(alignment: .leading, spacing: 0) {
            // Ô vuông nền trắng (bo đồng tâm với ô: 28 − 16), ảnh riêng hoặc biểu tượng
            CategoryBadge(c: c, side: wide ? 72 : 52, radius: wide ? 16 : 12, iconSize: wide ? 42 : 30)
            Spacer(minLength: 14)
            // Tên mờ 70% (pha màu nền); số tiền giữ đậm rõ cho dễ đọc
            Text(c.name).font(.system(size: 15, weight: .medium)).opacity(0.7)
            Text(fmt(total)).font(.system(size: 19, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(c.ink)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: wide ? 180 : 140, alignment: .leading)
        .background(c.color, in: RoundedRectangle(cornerRadius: Self.tileRadius, style: .continuous))
    }

    /// Bảng nhấn giữ của một danh mục
    private func categoryMenu(_ c: Category) -> AppMenuSpec {
        let month = store.monthItems(now).filter { Category.get($0.c).k == c.k }
        var items = [
            AppMenuItem(icon: "pencil.tip.crop.circle", title: L("Đổi biểu tượng, màu, tên"), plain: true) { editingCat = CatEdit.of(c.k, store: store) },
            store.isWide(c.k)
                ? AppMenuItem(icon: "arrow.down.right.and.arrow.up.left.circle", title: L("Thu ô về nửa hàng"), plain: true) { withAnimation(.snappy) { store.setWide(c.k, false) } }
                : AppMenuItem(icon: "arrow.down.left.and.arrow.up.right.circle", title: L("Kéo ô dài cả hàng"), plain: true) { withAnimation(.snappy) { store.setWide(c.k, true) } },
        ]
        if Category.isBuiltin(c.k) {
            if store.cats[c.k]?.on == true { items.append(AppMenuItem(icon: "arrow.uturn.backward.circle", title: L("Về mặc định"), plain: true) { store.resetCategory(c.k) }) }
        } else {
            items.append(AppMenuItem(icon: "trash.fill", title: L("Xoá danh mục"), danger: true) { store.removeCategory(c.k) })
        }
        return AppMenuSpec(icon: AnyView(CategoryBadge(c: c, side: 56, radius: 18, iconSize: 30)),
                           title: c.name,
                           subtitle: L("%@: %@", monthLabel(now), fmt(month.reduce(0) { $0 + $1.a })) + " · " + (month.count == 1 ? L("1 khoản") : L("%d khoản", month.count)),
                           items: items)
    }

    /// Hiệu ứng đổi giữa danh sách và lưới ảnh: hiện ra thì mờ vào và nở từ 96%, mất đi thì chỉ mờ đi
    static let swapStyle: AnyTransition = .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                                                      removal: .opacity)

    @ViewBuilder private var recent: some View {
        let list = Array(store.activity.prefix(5))
        if list.isEmpty {
            // Chữ có **đậm** (Markdown): đưa qua LocalizedStringKey để Text vẽ đậm
            Text(LocalizedStringKey(L("Chưa có khoản nào.\nBấm **Quét QR** khi trả tiền,\nhoặc **Nhập** / bấm một danh mục ở trên.")))
                .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(24)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else if film != nil {
            VStack(spacing: 10) { ForEach(list) { ExpenseRow(e: $0, showDay: true, now: now, repeats: store.rule(for: $0) != nil) } }
        } else if gridShown {
            // Lưới so le 3 cột (kiểu Pinterest): 12 khoản gần nhất xếp lần lượt từ trái sang phải; mỗi ô cao theo tỉ lệ ảnh hoá
            // đơn (không có ảnh thì màu và biểu tượng danh mục, cao thấp xen kẽ), số tiền ở góc
            // Ba cột dài ngắn khác nhau: ô cuối của mỗi cột co giãn chiều cao để cả ba cột cùng dừng ở một đường (không cột nào
            // hụt để lại khoảng trống lởm chởm, không ô nào bị cắt). Đường đáy: ngang đáy cột ngắn nhất, nhưng ô cuối của cột nào
            // cũng cao ít nhất 90
            let items = Array(store.activity.prefix(12))
            let cols = (0..<3).map { c in items.enumerated().filter { $0.offset % 3 == c }.map(\.element) }
            let line: CGFloat? = gridCols.count == 3 ? gridCols.values.max().map { $0 + 8 + 90 } : nil
            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<3, id: \.self) { col in
                    VStack(spacing: 8) {
                        // Các ô trừ ô cuối: cao theo tỉ lệ ảnh, đo tổng chiều cao
                        VStack(spacing: 8) {
                            ForEach(cols[col].dropLast()) { e in gridTile(e) }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { gridCols[col] = $0 }
                        if let last = cols[col].last {
                            gridTile(last, height: line.map { max(90, $0 - (gridCols[col] ?? 0) - (cols[col].count > 1 ? 8 : 0)) })
                        }
                    }
                }
            }
            .transition(Self.swapStyle)
        } else {
            // List để dùng thao tác vuốt có sẵn của iOS; không tự cuộn, cao vừa đủ số hàng
            List {
                ForEach(list) { e in
                    // Khoản điều chỉnh số dư: chạm mở bảng số dư (không sửa như khoản chi)
                    TapHold(tap: { if e.isAdjust { balanceOpen = true } else { entry = .edit(e) } },
                            hold: { menu = expenseMenu(e, store: store) { entry = .editNow(e) } }) {
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
            // Tràn ra mép trái màn (hàng tự lùi 16 trong expenseSwipe): vuốt xoá thì hàng trượt ra tận mép màn
            .padding(.leading, -16).padding(.trailing, -8)
            .transition(Self.swapStyle)
        }
    }

    /// Lớp mờ sau hai nút khi dựng phim: dải màu đặc (xem FilmFade). Ngoài phim withDock tự vẽ lớp nhoè (ClearBlur)
    private var bottomBlur: some View {
        FilmFade(color: Palette.bg, stops: [(0, 1), (0.28, 1), (0.45, 0.85), (0.62, 0.55), (0.8, 0.25), (1, 0)], height: 170)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    /// Hai nút nổi trên nội dung, nền kính (Liquid Glass trên iOS 26).
    private var dock: some View {
        GlassGroup {
            HStack(spacing: 12) {
                // Chạm: nhập tay. Vuốt lên: chụp hoá đơn rồi mở màn nhập với ảnh hoá đơn đính kèm
                BigButton(title: L("Nhập"), icon: "plus", primary: false, swipeUp: { _ in if Pro.shared.allow(.photos) { receiptScan = true } }) { entry = .new(cat: nil) }
                    .filmPressed(film?.pressed["dock-add"] ?? 0)
                // Chạm: quét QR. Vuốt lên: thẻ nói để ghi phóng ra từ chính nút này
                // Đang là thẻ nói để ghi (biến hình từ nút này ra): nút thật không vẽ gì (ghost), chỉ còn khối biến hình
                BigButton(title: L("Quét QR"), icon: "qrcode", primary: true, ghost: voiceFrom != nil, swipeUp: { frame in
                    // VoiceOver: mở qua fullScreenCover, để thẻ là một màn hình riêng (tiêu điểm chuyển vào thẻ, phần phía sau
                    // không còn chọn được); lớp phủ biến hình chỉ là hiệu ứng để nhìn
                    if UIAccessibility.isVoiceOverRunning { listen(); return }
                    voiceFrom = frame
                    // Thẻ hiện ngay trên màn hình chính (xem lớp phủ bên dưới), không qua fullScreenCover
                }) { scanning = true }
                .filmPressed(film?.pressed["dock-scan"] ?? 0)
            }
        }
        .padding(.horizontal, 16)
            // Sát vạch Home hơn (cách mép dưới 16 điểm, bằng lề hai bên): để nguyên vùng an toàn 34 điểm + 8 thì
            // dưới hai nút trống một khoảng lớn
            // (Cả iOS cũ: dải nút phủ lên nội dung vẫn tính vùng an toàn, nên cùng lùi 18 cho bằng vị trí trên iOS 26+)
            .padding(.bottom, -18)
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
    /// Nút xoá khi vuốt sang trái, dùng chung cho mọi hàng trong List / Form: chỉ thùng rác trên nền đỏ, không xoá khi vuốt hết,
    /// rung một nhịp. Hoàn tác do chỗ gọi lo (thanh "Đã xoá · Hoàn tác")
    func trashSwipe(_ label: String = L("Xoá"), delete: @escaping () -> Void) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { Haptic.tap(.medium); delete() } label: { Image(systemName: "trash.fill") }
                .tint(.red)
                .accessibilityLabel(label)
        }
    }

    /// Như trashSwipe cho thẻ nằm ngoài List (VStack trong ScrollView): kéo thẻ sang trái lộ nút thùng rác đỏ cùng bo góc
    func cardSwipe(radius: CGFloat = 24, _ label: String = L("Xoá"), delete: @escaping () -> Void) -> some View {
        modifier(CardSwipe(radius: radius, label: label, delete: delete))
    }

    /// Hàng khoản chi trong List: vuốt sang trái hiện nút Xoá (chạm vào hàng để sửa), không kẻ dòng, nền trong suốt.
    func expenseSwipe(delete: @escaping () -> Void) -> some View { modifier(ExpenseSwipe(delete: delete)) }
}

/// Kéo ngang theo tay (translation, và khi thả: translation + vận tốc ngang). iOS 18+: cử chỉ kéo của UIKit chỉ bắt đầu khi
/// kéo ngang; kéo dọc thì nó không nhận nên trang vẫn cuộn được dù đặt ngón tay lên thẻ (DragGesture của SwiftUI, kể cả
/// simultaneousGesture, giữ luôn ngón tay trên iOS 18+: đặt tay lên hàng rồi kéo dọc thì trang không cuộn)
extension View {
    @ViewBuilder func horizontalSwipe(changed: @escaping (CGFloat) -> Void, ended: @escaping (CGFloat, CGFloat) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            gesture(HorizontalPan(changed: changed, ended: ended))
        } else {
            simultaneousGesture(DragGesture(minimumDistance: 12)
                .onChanged { v in if abs(v.translation.width) > abs(v.translation.height) { changed(v.translation.width) } }
                .onEnded { v in ended(v.translation.width, v.velocity.width) })
        }
    }
}

@available(iOS 18.0, *)
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        g.delegate = context.coordinator
        return g
    }

    func handleUIGestureRecognizerAction(_ g: UIPanGestureRecognizer, context: Context) {
        let w = g.translation(in: g.view).x
        switch g.state {
        case .changed: changed(w)
        case .ended, .cancelled, .failed: ended(w, g.velocity(in: g.view).x)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Chỉ nhận khi hướng kéo lúc bắt đầu rõ là ngang (ngang gấp đôi dọc), kéo chéo thì để trang cuộn
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let p = g as? UIPanGestureRecognizer else { return false }
            let v = p.velocity(in: p.view)
            return abs(v.x) > abs(v.y) * 2
        }
    }
}

/// Vuốt xoá có sẵn của iOS (mượt như mọi danh sách của hệ thống). iOS 26+: nút xoá mặc định là thùng rác trắng trong vòng
/// tròn đỏ. iOS cũ hơn vẽ nút ô vuông đỏ cao hết hàng: thay bằng ảnh vòng tròn đỏ tự vẽ trên nền trong suốt cho giống iOS 26+.
/// Danh sách tràn ra mép trái màn (hàng lùi vào 16 bằng listRowInsets) để hàng vuốt đi trượt ra tận mép màn, không bị cắt
/// ở lề; mép phải danh sách cách mép màn 8 và hàng lùi thêm 8: nút xoá (hệ thống đặt sát mép phải danh sách) cách thẻ và cách
/// mép màn đều ~18pt (đo trên máy ảo iOS 18 và 27)
private struct ExpenseSwipe: ViewModifier {
    let delete: () -> Void
    /// Tâm hàng lúc đứng yên (xa bên phải nhất từng thấy) và đã rung cho lần vuốt này chưa
    @State private var restX: CGFloat?
    @State private var buzzed = false

    func body(content: Content) -> some View {
        content
            // Rung nhẹ khi vuốt đủ xa để lộ nút xoá (thao tác vuốt của hệ thống không báo lúc nút hiện ra): đo tâm hàng — màn
            // phía sau thu nhỏ khi mở tấm (iOS cũ) không làm tâm lệch, chỉ vuốt mới lệch
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: { x in
                if restX == nil || x > restX! { restX = x }
                let shift = (restX ?? x) - x
                if shift > 44, !buzzed { buzzed = true; Haptic.tap(.light) }
                if shift < 8 { buzzed = false }
            }
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 8))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    Haptic.tap(.medium)
                    delete()
                } label: {
                    if #available(iOS 26.0, *) { Image(systemName: "trash.fill") }
                    else { Image(uiImage: Self.roundTrash) }
                }
                .tint(Self.tint)
                .accessibilityLabel(L("Xoá"))
            }
    }

    private static var tint: Color { if #available(iOS 26.0, *) { .red } else { .clear } }

    /// Thùng rác trắng trong vòng tròn đỏ 50pt (như nút của iOS 26+), giữ nguyên màu (không bị tô trắng như ảnh mẫu). Hai bên
    /// chừa trống (trái 6, phải 8) để khoảng thẻ → nút và nút → mép màn bằng nhau, bằng iOS 26+ (~18pt, đo trên máy ảo)
    private static let roundTrash: UIImage = {
        let side: CGFloat = 50, pad: CGFloat = 6, padR: CGFloat = 8
        let img = UIGraphicsImageRenderer(size: CGSize(width: side + pad + padR, height: side)).image { _ in
            UIColor.systemRed.setFill()
            UIBezierPath(ovalIn: CGRect(x: pad, y: 0, width: side, height: side)).fill()
            let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            if let t = UIImage(systemName: "trash.fill", withConfiguration: cfg)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                t.draw(at: CGPoint(x: pad + (side - t.size.width) / 2, y: (side - t.size.height) / 2))
            }
        }
        return img.withRenderingMode(.alwaysOriginal)
    }()
}

/// Thẻ vuốt sang trái lộ nút thùng rác (ngoài List không có swipeActions): kéo quá nửa nút thì mở hẳn, thả sớm thì về;
/// chạm thùng rác: thẻ trượt đi rồi mới gọi xoá. Kéo dọc thì để vùng cuộn lo
private struct CardSwipe: ViewModifier {
    let radius: CGFloat
    let label: String
    let delete: () -> Void
    @State private var x: CGFloat = 0
    @State private var start: CGFloat = 0
    @State private var gone = false
    @State private var guardTap = SwipeGuard()
    private let button: CGFloat = 76

    func body(content: Content) -> some View {
        content
            .environment(\.swipeGuard, guardTap)
            // Đang mở: chạm vào thẻ thì đóng lại (không mở màn sửa). Phủ lên thẻ trước khi dịch để lớp này trượt theo thẻ,
            // không che nút thùng rác vừa lộ ra
            .overlay { if x < 0 && !gone { Color.white.opacity(0.001).onTapGesture { withAnimation(.snappy(duration: 0.25)) { x = 0; start = 0 } } } }
            .offset(x: gone ? -500 : x)
            .opacity(gone ? 0 : 1)
            .background(alignment: .trailing) {
                Button {
                    Haptic.tap(.medium)
                    withAnimation(.easeIn(duration: 0.22)) { gone = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { delete() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { gone = false; x = 0; start = 0 }
                } label: {
                    // Giống nút xoá của List trên iOS 26+: thùng rác trắng trong vòng tròn đỏ, giữa theo chiều cao thẻ
                    Image(systemName: "trash.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.red, in: Circle())
                        .frame(width: button)
                }
                .buttonStyle(Pressable())
                .opacity(gone ? 0 : min(1, -x / button))
                .accessibilityLabel(label)
            }
            .horizontalSwipe(changed: { w in
                guardTap.last = Date()
                let t = start + w
                x = t > 0 ? 0 : (t < -button ? -button + (t + button) * 0.3 : t)
            }, ended: { w, v in
                guardTap.last = Date()
                // Như vuốt của hệ thống: theo hướng tay lúc thả. Đang kéo ngược lại (sang phải) thì đóng, đang kéo sang trái thì mở;
                // gần như đứng yên mới xét vị trí (quá 60% nút thì mở). Trước: lướt nhẹ đã mở, kéo ngược tay lại vẫn mở
                let open = v > 150 ? false : (v < -250 ? x < -12 : x < -button * 0.6)
                // Lò xo nhận luôn vận tốc ngón tay lúc thả (như UIKit / vuốt của hệ thống): hàng đi tiếp đà tay rồi mới dừng, không
                // khựng lại một nhịp rồi mới chạy như lò xo bắt đầu từ vận tốc 0
                let target: CGFloat = open ? -button : 0
                let dist = target - x
                let rel = abs(dist) > 1 ? max(-12, min(12, v / dist)) : 0
                withAnimation(.interpolatingSpring(mass: 1, stiffness: 320, damping: 34, initialVelocity: rel)) { x = target }
                start = target
            })
    }
}

struct ExpenseRow: View {
    /// Cao một hàng kể cả khoảng cách 10pt giữa các hàng (thẻ 76pt: ô biểu tượng 56 cách trên dưới 10, vừa tên hai dòng + dòng phụ)
    static let rowHeight: CGFloat = 86
    /// Thẻ hàng khoản chi: ô biểu tượng cách mép thẻ 10 cả trên, dưới, trái; bo thẻ đồng tâm với ô (bo ô 13 + 10)
    static let rowRadius: CGFloat = 23, rowInset: CGFloat = 10
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
    @State private var thumb: UIImage?

    /// Dòng phụ thay cho tên danh mục (vd "Số dư sau: …" ở Các lần điều chỉnh)
    var sub: String? = nil

    init(e: Expense, showDay: Bool = false, now: Date = Date(), repeats: Bool = false, sub: String? = nil) {
        self.e = e; self.showDay = showDay; self.now = now; self.repeats = repeats; self.sub = sub
        c = Category.get(e.c)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Ô vuông nền trắng như ô danh mục; bo đồng tâm với thẻ (bo thẻ trừ khoảng cách tới mép)
            // Có ảnh hoá đơn đính kèm: ảnh đó làm ô biểu tượng (cùng khung bo góc)
            // Thẻ điều chỉnh số dư: không có ô biểu tượng (không phải khoản chi theo danh mục)
            if !e.isAdjust {
            Group {
                if let thumb {
                    Image(uiImage: thumb).resizable().scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: Self.rowRadius - Self.rowInset, style: .continuous))
                        .accessibilityLabel(L("Có ảnh hoá đơn"))
                } else {
                    CategoryBadge(c: c, side: 56, radius: Self.rowRadius - Self.rowInset)
                }
            }
            .task(id: "\(e.id)\(e.u ?? 0)") { thumb = await ReceiptPhotos.thumb(e.id) }
                // Có ảnh hoá đơn mà chưa tải được ảnh: chấm xanh lá (màu icon app) ở góc trên phải ô biểu tượng, viền màu thẻ cho tách nền
                .overlay(alignment: .topTrailing) {
                    if thumb == nil, ReceiptPhotos.has(e.id) {
                        // Vòng màu thẻ vẽ dưới, chấm xanh nhỏ hơn đè lên giữa: vẽ viền đè lên chấm xanh cùng cỡ thì mép xanh
                        // (khử răng cưa) lộ ra ngoài viền thành một vệt mảnh
                        Circle().fill(Palette.card).frame(width: 12, height: 12)
                            .overlay(Circle().fill(Color(hex: 0x61BE6E)).frame(width: 7, height: 7))
                            .offset(x: 3, y: -3)
                            .accessibilityLabel(L("Có ảnh hoá đơn"))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // Tên dài thì xuống dòng thứ hai thay vì bị cắt "…"
                    Text((e.n?.isEmpty == false ? e.n!.capFirst : c.name)).font(.rowTitle)
                        .lineLimit(2).multilineTextAlignment(.leading).lineSpacing(-1)
                    if repeats {
                        Image(systemName: "repeat").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            .accessibilityLabel(L("Hằng tháng"))
                    }
                    if e.isCredit {
                        Image(systemName: "creditcard.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            .accessibilityLabel(L("Thẻ tín dụng"))
                    }
                }
                // Tên danh mục dưới tên khoản, cỡ bằng ngày giờ bên phải (khoản không ghi chú thì tên đã là danh mục)
                if let sub {
                    Text(sub).font(.rowSub).foregroundStyle(.secondary).lineLimit(1)
                } else if e.n?.isEmpty == false {
                    Text(c.name).font(.rowSub).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            // Bên phải: số tiền, dưới là ngày | giờ (vạch dọc mảnh, mờ ngăn giữa). Luôn hiện đủ: phần tên nhường chỗ
            VStack(alignment: .trailing, spacing: 3) {
                // Khoản chi: chữ đỏ. Khoản thu: mũi tên lên, chữ xanh lá. Điều chỉnh số dư: mũi tên lên / xuống, chữ xám
                HStack(spacing: 3) {
                    if e.isIncome || e.isAdjust { AmountArrow(up: e.signed >= 0) }
                    Text(fmt(e.a)).font(.rowAmount).monospacedDigit()
                }
                .lineLimit(1)
                .foregroundStyle(e.isIncome ? AnyShapeStyle(Palette.goodInk) : e.isAdjust ? AnyShapeStyle(.secondary) : AnyShapeStyle(Palette.danger))
                HStack(spacing: 9) {
                    let parts = when
                    ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                        if i > 0 { Rectangle().fill(Color.primary.opacity(0.18)).frame(width: 1, height: 13) }
                        Text(p).font(.rowSub).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .fixedSize().layoutPriority(1)
        }
        .foregroundStyle(.primary)
        .padding(.leading, e.isAdjust ? 16 : Self.rowInset).padding(.trailing, e.isAdjust ? 16 : 14).padding(.vertical, Self.rowInset)   // thẻ không ô biểu tượng: chữ cách đều hai bên 16
        .frame(minHeight: Self.rowHeight - 10)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Self.rowRadius, style: .continuous))
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
    /// Màu nền riêng (chữ trắng), vd nút Huỷ cam đậm; nil: nền theo primary
    var tint: Color? = nil
    var swipeUp: ((CGRect) -> Void)? = nil
    /// Khung của nút trên màn hình, để thẻ nói để ghi biến hình từ đúng chỗ này ra
    @State private var frame: CGRect = .zero
    let action: () -> Void
    /// Nút có vuốt lên thì tự theo dõi ngón tay: đang nhấn, và lần nhấn này đã ra việc gì chưa
    @State private var down = false
    @State private var fired = false
    /// Ngón tay còn trên nút không; iOS tự đưa về false cả khi cử chỉ bị huỷ (vd màn hình khác vừa mở đè lên)
    @GestureState private var touching = false

    /// Mép trên của dải thanh Home (toạ độ toàn màn): vuốt lên bắt đầu dưới đường này là của iOS
    private static var homeZoneTop: CGFloat {
        let w = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first
        let h = w?.bounds.height ?? 874, bottom = w?.safeAreaInsets.bottom ?? 34
        return h - max(bottom, 20)
    }

    var body: some View {
        if let swipeUp {
            // Tự xử lý bằng một cử chỉ, mỗi lần nhấn chỉ ra đúng một việc: kéo lên quá 30pt là vuốt lên (làm ngay,
            // nhả tay không làm gì nữa), nhả tại chỗ là chạm, kéo đi hướng khác rồi nhả là bỏ.
            label
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
                .scaleEffect(down ? 0.94 : 1).opacity(down ? 0.72 : 1)
                .animation(down ? .easeOut(duration: 0.08) : .spring(duration: 0.3, bounce: 0.35), value: down)
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($touching) { _, on, _ in on = true }
                    .onChanged { v in
                        guard !fired else { return }
                        down = true
                        let up = -v.translation.height
                        // Vuốt bắt đầu trong dải thanh Home (vùng an toàn dưới đáy màn) là cử chỉ về màn hình chính của iOS, không
                        // phải vuốt lên từ nút: nút nằm sát đáy nên ngón tay vuốt từ mép dưới hay chạm vào phần dưới của nút
                        if up > 30, abs(v.translation.width) < 50, v.startLocation.y < Self.homeZoneTop {
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
            Self.face(title: title, icon: icon, primary: primary, ink: tint == nil ? nil : .white)
                .contentShape(Capsule())
                // Nút phụ có icon (Nhập ở màn hình chính): trắng đặc ở giao diện sáng, đen ở giao diện tối — không xám đục
                .glassCapsule(tint: tint ?? (primary ? Palette.cta : icon.isEmpty ? nil : Color(light: 0xFFFFFF, dark: 0x1C1C1F)))
        }
    }

    /// Mặt nút (vòng biểu tượng + chữ), chưa có nền. Vòng icon cách đều mép nút ở trên, dưới và bên trái (cùng tâm với
    /// đầu nút bo tròn). Nút phụ ôm vừa chữ; nút chính lấy phần còn lại, chữ nằm giữa khoảng trống sau icon.
    /// Thẻ nói để ghi cũng vẽ mặt này lên khối biến hình, để nút và thẻ là một khối liền.
    static func face(title: String, icon: String, primary: Bool, ink: Color? = nil) -> some View {
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
        .foregroundStyle(ink ?? (primary ? Palette.ctaInk : .primary))
    }

    /// Nền nút Huỷ: cam đậm, chữ trắng
    static let cancelTint = Color(hex: 0xC2410C)
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

/// Một dòng chọn trong Form: mở trang danh sách riêng (thay ô chọn kiểu trang của iOS, để trang ấy cũng có thanh tiêu đề của
/// app). Chọn xong tự quay lại
struct PickLink<T: Hashable, Label: View>: View {
    let title: String
    @Binding var selection: T
    /// Các nhóm lựa chọn: tên nhóm (nil = không có), rồi (giá trị, tên hiện)
    let sections: [(header: String?, items: [(T, String)])]
    @ViewBuilder var label: Label

    var body: some View {
        NavigationLink {
            PickPage(title: title, selection: $selection, sections: sections)
        } label: {
            LabeledContent {
                Text(sections.flatMap(\.items).first { $0.0 == selection }?.1 ?? "").foregroundStyle(.secondary).lineLimit(1)
            } label: { label }
        }
    }
}

private struct PickPage<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let sections: [(header: String?, items: [(T, String)])]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            ForEach(sections.indices, id: \.self) { i in
                Section {
                    ForEach(sections[i].items.indices, id: \.self) { j in
                        let item = sections[i].items[j]
                        Button {
                            Haptic.select()
                            selection = item.0
                            dismiss()
                        } label: {
                            HStack {
                                Text(item.1).foregroundStyle(Color.primary)
                                Spacer(minLength: 8)
                                if item.0 == selection { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.primary) }
                            }
                            .contentShape(Rectangle())
                        }
                    }
                } header: {
                    if let h = sections[i].header { Text(h) }
                }
            }
        }
        .textCase(nil)
        .softTopEdge(fade: Color(.systemGroupedBackground), back: true)
        .screenTitle(title)
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
                    // Hoàn tác có hiệu ứng: hàng vừa xoá trượt / hiện lại vào chỗ cũ, các hàng dưới dịch xuống nhường chỗ
                    Button { Haptic.tap(); withAnimation(.snappy(duration: 0.35)) { undo(); store.toast = nil } } label: {
                        Label(L("Hoàn tác"), systemImage: "arrow.uturn.backward")
                            .font(.system(size: 17, weight: .semibold))
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

/// Rung phản hồi dùng chung: chọn (nấc bánh xe, đổi lựa chọn) và chạm (hành động)
@MainActor
enum Haptic {
    private static let selection = UISelectionFeedbackGenerator()
    static func select() { selection.selectionChanged(); selection.prepare() }
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) { UIImpactFeedbackGenerator(style: style).impactOccurred() }
}

/// Cỡ chữ chung của mọi hàng danh sách trong app (Gần đây, Lịch sử, Thống kê, Nhóm chung): tên hàng, dòng phụ, số tiền.
/// Lấy theo hàng khoản chi (ExpenseRow); hàng ở màn nào cũng dùng bộ này để cỡ chữ không lệch nhau giữa các màn
extension Font {
    static let rowTitle = Font.system(size: 15, weight: .medium)
    static let rowSub = Font.system(size: 12)
    static let rowAmount = Font.system(size: 15, weight: .medium)
}


/// Màn chụp hoá đơn mở từ trang chủ (vuốt lên từ nút Nhập). Chụp xong, màn nhập kèm ảnh mở chồng ngay lên màn chụp. Lưu ở
/// màn nhập thì đóng luôn màn chụp, cả hai cùng trượt xuống về trang chủ; Huỷ (hoặc vuốt tấm xuống) thì quay lại màn chụp để
/// chụp lại. Về trang chủ bằng nút nhà cạnh nút chụp
private struct ReceiptFlow: View {
    let store: Store
    var close: () -> Void
    @State private var shot: EntryMode?
    /// Các khoản lúc mở màn nhập: lúc đóng có khoản mới (không phải khoản tự ghi hằng tháng) là đã lưu. Không so số lượng: khoản
    /// tự ghi khi quay lại app, giao dịch thẻ ghi nền, iCloud gộp về đều làm số lượng đổi
    @State private var idsAtShot = Set<String>()
    /// Đổi để màn chụp nhận chụp tiếp khi quay lại từ màn nhập (camera vẫn chạy suốt, không dựng lại: dựng lại thì khung xem đen
    /// một nhịp lúc bật lại camera)
    @State private var round = 0

    var body: some View {
        ReceiptCamera(resume: round, home: close) { img in
            guard let img else { close(); return }
            idsAtShot = Set(store.all.map(\.id))
            shot = .receipt(img)
        }
        .sheet(item: $shot, onDismiss: {
            if store.all.contains(where: { !idsAtShot.contains($0.id) && !$0.id.hasPrefix("r-") && !$0.isAdjust }) { close() } else { round += 1 }
        }) { EntryView(mode: $0).environmentObject(store).sheetGrabber() }
    }
}

/// Một ô của lưới ảnh ở mục Gần đây: ảnh hoá đơn phủ kín ô vuông bo góc; không có ảnh thì nền màu danh mục với biểu tượng ở
/// giữa. Số tiền trong viên tối mờ ở góc dưới trái (như ô ảnh của app Ảnh có nhãn)
struct ExpenseTile: View {
    let e: Expense
    /// Ô cao theo tỉ lệ ảnh (lưới so le ở trang chủ) thay vì ô vuông
    var free = false
    /// Cao cố định (ô cuối một cột của lưới so le): ảnh phủ kín, cắt bớt phần thừa
    var height: CGFloat? = nil
    private let c: Category
    @State private var photo: UIImage?

    init(e: Expense, free: Bool = false, height: CGFloat? = nil) { self.e = e; self.free = free; self.height = height; c = Category.get(e.c) }

    /// Rộng / cao của ô: ô vuông; lưới so le thì theo ảnh (giới hạn 0,6…1,3 cho ảnh quá dài / quá dẹt), chưa có ảnh thì một trong
    /// ba dáng cố định theo mã khoản để các ô cao thấp xen kẽ
    private var aspect: CGFloat {
        guard free else { return 1 }
        if let photo { return min(1.3, max(0.6, photo.size.width / max(1, photo.size.height))) }
        // Không dùng hashValue: Swift đổi giá trị mỗi lần mở app, ô sẽ đổi dáng
        return [0.75, 1, 0.8][e.id.utf8.reduce(0) { $0 &+ Int($1) } % 3]
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Group {
            if let height { Color.clear.frame(maxWidth: .infinity).frame(height: height) }
            else { Color.clear.aspectRatio(aspect, contentMode: .fit) }
        }
            .overlay {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    ZStack {
                        c.color
                        CategoryIcon(c: c, size: 40)
                    }
                }
            }
            .clipShape(shape)
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 2) {
                    if e.isIncome || e.isAdjust { AmountArrow(up: e.signed >= 0, size: 12) }
                    Text(fmt(e.a)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                }
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(6)
            }
            .contentShape(shape)
            .task(id: "\(e.id)\(e.u ?? 0)") { photo = await (free ? ReceiptPhotos.preview(e.id) : ReceiptPhotos.tile(e.id)) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(e.n?.isEmpty == false ? e.n! : c.name), \(fmt(e.a))")
    }
}
