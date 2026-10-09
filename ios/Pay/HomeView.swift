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
    @State private var listening = false
    @State private var scanned: String?

    var body: some View {
        let now = Date()
        ZStack(alignment: .bottom) {
            Palette.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(now)
                    Button { showStats = true } label: { hero(now) }
                        .buttonStyle(Pressable())
                        .padding(.top, 14)

                    sectionTitle("Danh mục") { Text("Tháng \(Calendar.current.component(.month, from: now))") }
                    tiles(now)

                    sectionTitle("Gần đây") {
                        Button("Xem tất cả") { showHistory = true }.foregroundStyle(.primary)
                    }
                    recent
                }
                .padding(.horizontal, 16)
                .padding(.bottom, Self.nativeEdge ? 16 : 120)
            }
            .withDock(dock: dock, fallbackBlur: bottomBlur)

            ToastView()
                .padding(.bottom, 108)
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
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
        .sheet(isPresented: $showStats) { StatsView().environmentObject(store) }
        .sheet(isPresented: $listening) {
            VoiceEntryView(onTypeInstead: {
                Task { try? await Task.sleep(for: .milliseconds(450)); entry = .new(cat: nil) }
            }, onEdit: { e in
                Task { try? await Task.sleep(for: .milliseconds(450)); entry = .edit(e) }
            })
            .environmentObject(store)
        }
        .onChange(of: quick.pending, initial: true) { _, k in
            guard let k else { return }
            quick.pending = nil
            Task { await run(k) }
        }
    }

    /// Mở thẳng màn hình quét / nhập. Đang mở màn hình khác thì đóng hết trước rồi mới mở.
    private func run(_ k: QuickKind) async {
        let busy = entry != nil || scanning || showHistory || showSettings || showStats || listening
        if (k == .scan && scanning) || (k == .voice && listening) { return }
        entry = nil; scanning = false; showHistory = false; showSettings = false; showStats = false; listening = false
        if busy { try? await Task.sleep(for: .milliseconds(450)) }
        switch k {
        case .scan: scanning = true
        case .add: entry = .new(cat: nil)
        case .voice: listening = true
        }
    }

    // MARK: Các phần

    private func header(_ now: Date) -> some View {
        HStack(spacing: 8) {
            Text("Pay").font(.system(size: 28, weight: .bold))
            Spacer()
            Text(dayLabel(now))
                .font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .frame(height: Self.headerSize)
                .background(Palette.pill, in: Capsule())
            headerButton("chart.bar.fill", "Thống kê") { showStats = true }
            headerButton("gearshape.fill", "Cài đặt") { showSettings = true }
        }
        .padding(.top, 8)
    }

    /// Cao của mọi thứ trên thanh đầu trang: nhãn ngày và các nút tròn.
    private static let headerSize: CGFloat = 42

    /// Nút tròn trên thanh đầu trang: biểu tượng tô đặc, cùng kích thước.
    private func headerButton(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
                .resizable().scaledToFit()
                .fontWeight(.semibold)
                .frame(width: 18, height: 18)   // mọi biểu tượng vừa trong cùng ô 18×18 nên to bằng nhau
                .frame(width: Self.headerSize, height: Self.headerSize)
                .background(Palette.pill, in: Circle())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }

    private func hero(_ now: Date) -> some View {
        let month = store.monthItems(now).reduce(0) { $0 + $1.a }
        let n = store.count(on: now)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Hôm nay đã chi").font(.system(size: 16)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(fmt(store.total(on: now)))
                    .font(.system(size: 60, weight: .bold)).kerning(-2)
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text("đ").font(.system(size: 30, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.top, 10).padding(.bottom, 14)
            HStack {
                Text("Tháng \(Calendar.current.component(.month, from: now)): \(fmt(month))đ")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Palette.pill, in: Capsule())
                    .lineLimit(1)
                Spacer()
                if n > 0 { Text("\(n) khoản").font(.system(size: 15)).foregroundStyle(.secondary) }
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
            BudgetBar(s: b, height: 10, track: Palette.pill)
            HStack(spacing: 4) {
                // Chữ giữ màu chữ thường cho dễ đọc; chỉ khi vượt mới đỏ, kèm biểu tượng
                if b.level == .over { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(Palette.danger) }
                Text(b.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(b.level == .over ? Palette.danger : .primary)
                Spacer()
                Text(b.level == .over ? "Ngân sách \(fmt(b.budget))đ" : "~\(fmt(b.perDay(at: now)))đ/ngày")
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
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(Category.all) { c in
                Button { entry = .new(cat: c.k) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top) {
                            CategoryIcon(c: c, size: 30)
                                .frame(width: 52, height: 52).background(.white, in: Circle())
                            Spacer()
                            Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                                .frame(width: 30, height: 30).background(.white.opacity(0.6), in: Circle())
                        }
                        Spacer(minLength: 14)
                        Text(c.name).font(.system(size: 17, weight: .medium)).opacity(0.7)
                        Text("\(fmt(perCat[c.k] ?? 0))đ").font(.system(size: 22, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(Color(hex: 0x111114))
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
                    .background(c.color, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .buttonStyle(Pressable())
            }
        }
    }

    @ViewBuilder private var recent: some View {
        let list = Array(store.sorted.prefix(5))
        if list.isEmpty {
            Text("Chưa có khoản nào.\nBấm **Quét QR** khi trả tiền,\nhoặc **Nhập** / bấm một danh mục ở trên.")
                .font(.system(size: 17)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(24)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            // List để dùng thao tác vuốt có sẵn của iOS; không tự cuộn, cao vừa đủ số hàng
            List {
                ForEach(list) { e in
                    Button { entry = .edit(e) } label: { ExpenseRow(e: e, showDay: true) }
                        .buttonStyle(Pressable())
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
        Color.clear
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Palette.bg.opacity(0.5))
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.4), .init(color: .clear, location: 1)],
                                         startPoint: .bottom, endPoint: .top))
                    .frame(height: 190)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    /// Hai nút nổi trên nội dung, nền kính (Liquid Glass trên iOS 26).
    private var dock: some View {
        GlassGroup {
            HStack(spacing: 12) {
                BigButton(title: "Nhập", icon: "plus", primary: false) { entry = .new(cat: nil) }
                BigButton(title: "Quét QR", icon: "qrcode.viewfinder", primary: true) { scanning = true }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private func dayLabel(_ d: Date) -> String {
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
                Button(role: .destructive, action: delete) { Image(systemName: "trash.fill") }.accessibilityLabel("Xoá")
            }
    }
}

struct ExpenseRow: View {
    /// Cao một hàng kể cả khoảng cách 10pt giữa các hàng (thẻ 80pt: biểu tượng 56 + lề 2×12).
    static let rowHeight: CGFloat = 90
    let e: Expense
    var showDay = false

    var body: some View {
        let c = Category.get(e.c)
        HStack(spacing: 14) {
            CategoryIcon(c: c, size: 30)
                .frame(width: 56, height: 56)
                .background(c.color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text((e.n?.isEmpty == false ? e.n! : c.name)).font(.system(size: 18, weight: .semibold)).lineLimit(1)
                Text(sub(c)).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(fmt(e.a))đ").font(.system(size: 18, weight: .bold)).lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.leading, 12).padding(.trailing, 16).padding(.vertical, 12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func sub(_ c: Category) -> String {
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        var parts: [String] = []
        if showDay {
            let cal = Calendar.current
            if cal.isDateInToday(e.date) { parts.append("Hôm nay") }
            else { let d = cal.dateComponents([.day, .month], from: e.date); parts.append("\(d.day!)/\(d.month!)") }
        }
        parts.append(tf.string(from: e.date))
        parts.append(c.name)
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
                    .background(primary ? Color.white.opacity(0.18) : Color.primary.opacity(0.08), in: Circle())
                if primary { Spacer(minLength: 0) }
                Text(title).font(.system(size: 21, weight: .semibold)).lineLimit(1)
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
    @ViewBuilder func withDock<D: View, B: View>(dock: D, fallbackBlur: B) -> some View {
        if #available(iOS 26.0, *) {
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
    @ViewBuilder func glassCapsule(tint: Color?) -> some View {
        if #available(iOS 26.0, *) {
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

struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ToastView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        if let t = store.toast {
            HStack(spacing: 18) {
                Text(t.message).font(.system(size: 17, weight: .medium))
                if let undo = t.undo {
                    Button { undo(); store.toast = nil } label: {
                        Text("Hoàn tác").font(.system(size: 17, weight: .bold)).underline()
                    }
                }
            }
            .foregroundStyle(Palette.ctaInk)
            .padding(.leading, 24).padding(.trailing, 18).padding(.vertical, 15)
            .background(Palette.cta, in: Capsule())
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: t.id) {
                try? await Task.sleep(for: .seconds(5))
                if store.toast?.id == t.id { withAnimation { store.toast = nil } }
            }
        }
    }
}
