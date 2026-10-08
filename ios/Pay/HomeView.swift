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
    @State private var entry: EntryMode?
    @State private var scanning = false
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var scanned: String?

    var body: some View {
        let now = Date()
        ZStack(alignment: .bottom) {
            Palette.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(now)
                    hero(now).padding(.top, 14)

                    sectionTitle("Danh mục") { Text("Tháng \(Calendar.current.component(.month, from: now))") }
                    tiles(now)

                    sectionTitle("Gần đây") {
                        Button("Xem tất cả") { showHistory = true }.foregroundStyle(.primary)
                    }
                    recent
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }

            dock
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
    }

    // MARK: Các phần

    private func header(_ now: Date) -> some View {
        HStack {
            Text("Pay").font(.system(size: 28, weight: .bold))
            Spacer()
            Text(dayLabel(now))
                .font(.system(size: 15)).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Palette.pill, in: Capsule())
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 18, weight: .medium))
                    .frame(width: 42, height: 42).background(Palette.pill, in: Circle())
            }
            .foregroundStyle(.primary)
            .accessibilityLabel("Cài đặt")
        }
        .padding(.top, 8)
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
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.goodInk)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Palette.good, in: Capsule())
                    .lineLimit(1)
                Spacer()
                if n > 0 { Text("\(n) khoản").font(.system(size: 15)).foregroundStyle(.secondary) }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.hero, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
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
                            Text(c.icon).font(.system(size: 26))
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
            Text("Chưa có khoản nào.\nBấm **Quét QR** khi trả tiền,\nhoặc **Lưu** / bấm một danh mục ở trên.")
                .font(.system(size: 17)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(24)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            VStack(spacing: 10) {
                ForEach(list) { e in
                    Button { entry = .edit(e) } label: { ExpenseRow(e: e, showDay: true) }.buttonStyle(Pressable())
                }
            }
        }
    }

    private var dock: some View {
        HStack(spacing: 12) {
            BigButton(title: "Lưu", icon: "plus", primary: false) { entry = .new(cat: nil) }
            BigButton(title: "Quét QR", icon: "qrcode.viewfinder", primary: true) { scanning = true }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
        .background(Palette.bg.ignoresSafeArea(edges: .bottom).overlay(alignment: .top) { Divider() })
    }

    private func dayLabel(_ d: Date) -> String {
        let dow = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"][Calendar.current.component(.weekday, from: d) - 1]
        let c = Calendar.current.dateComponents([.day, .month], from: d)
        return "\(dow), \(c.day!)/\(c.month!)"
    }
}

// MARK: Thành phần dùng chung

struct ExpenseRow: View {
    let e: Expense
    var showDay = false

    var body: some View {
        let c = Category.get(e.c)
        HStack(spacing: 14) {
            Text(c.icon).font(.system(size: 26))
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
    let title: String
    let icon: String
    let primary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 24, weight: .semibold))
                    .frame(width: 56, height: 56)
                    .background(primary ? Color.gray.opacity(0.3) : Palette.surface, in: Circle())
                Text(title).font(.system(size: 21, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 78)
            .foregroundStyle(primary ? Palette.ctaInk : .primary)
            .background(primary ? Palette.cta : Palette.card, in: Capsule())
        }
        .buttonStyle(Pressable())
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
