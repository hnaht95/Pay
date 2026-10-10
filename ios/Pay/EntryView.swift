import SwiftUI

/// Màn hình nhập số tiền với bàn phím số lớn (lưu mới / sau khi quét QR / sửa).
struct EntryView: View {
    let mode: EntryMode
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var digits = ""
    @State private var cat: String?
    @State private var catPicked = false
    /// Người dùng tự bấm đổi danh mục: lưu xong thì nhớ danh mục này cho ghi chú.
    /// Mở từ ô danh mục thì không tính (chọn trước khi gõ, chưa phải đổi so với app đoán)
    @State private var chosen = false
    @State private var note = ""
    @State private var addingCat = false
    @State private var ready = false
    @FocusState private var noteFocused: Bool

    private var amount: Int { Int(digits) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            Text(L("Số tiền")).font(.system(size: 15)).foregroundStyle(.secondary).padding(.top, 16)
            HStack(alignment: .firstTextBaseline) {
                Text(amount > 0 ? fmt(amount) : "0")
                    .font(.system(size: 40, weight: .bold)).kerning(-1)
                    .foregroundStyle(amount > 0 ? .primary : .tertiary)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                Spacer()
                Text("đ").font(.system(size: 20, weight: .semibold)).foregroundStyle(.secondary)
            }
            // Ô số tiền đóng khung nền nhạt, cùng kiểu với ô ghi chú bên dưới
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.top, 8)

            chips.padding(.top, 14)

            TextField(L("Ghi chú (không bắt buộc)"), text: $note)
                .font(.system(size: 18))
                .focused($noteFocused)
                .submitLabel(.done)
                .padding(.horizontal, 18).padding(.vertical, 15)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.top, 12)
                .onChange(of: note) { _, v in
                    guard !catPicked else { return }
                    let g = store.guessCategory(v)
                    if g != "khac" { cat = g }
                }

            keypad.padding(.vertical, 8)
            actions
        }
        .padding(.horizontal, 18).padding(.bottom, 8)
        .background(Palette.surface.ignoresSafeArea())
        // Vuốt từ mép trái để quay lại, vuốt xuống để ẩn (màn hình này mở toàn màn hình nên iOS không có sẵn)
        .edgeBack { dismiss() }
        .swipeDownToClose { dismiss() }
        .onAppear(perform: setup)
        .sheet(isPresented: $addingCat) {
            CategoryEditor { k in cat = k; catPicked = true; chosen = true }
                .environmentObject(store)
                .sheetGrabber()
        }
    }

    // MARK: Phần đầu

    private var head: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                        .frame(width: 46, height: 46).background(Palette.pill, in: Circle())
                }
                .buttonStyle(Pressable())
                .foregroundStyle(.primary)
                Text(title).font(.system(size: 21, weight: .bold)).lineLimit(1)
            }
            if let sub { Text(sub).font(.system(size: 15)).foregroundStyle(.secondary).padding(.leading, 56).lineLimit(2) }
        }
        .padding(.top, 8)
    }

    private var title: String {
        switch mode {
        case .new(let c): return c.map { "\(Category.get($0).icon) \(Category.get($0).name)" } ?? L("Lưu khoản chi")
        case .scan(let q): return L("Trả cho %@", q.name.isEmpty ? L("TK %@", q.acct ?? "") : q.name)
        case .raw: return L("Mã QR không phải VietQR")
        case .edit: return L("Sửa khoản chi")
        }
    }

    private var sub: String? {
        switch mode {
        case .new: return nil
        case .scan(let q): return [q.bank, q.acct ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        case .raw(let s): return String(s.prefix(80))
        case .edit(let e):
            let f = DateFormatter(); f.dateFormat = "HH:mm, dd/MM"
            if Lang.isEnglish { f.locale = Lang.locale; f.dateFormat = "HH:mm, MMM d" }
            return f.string(from: e.date)
        }
    }

    // MARK: Danh mục

    private var chips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Category.all) { c in
                        Button { cat = c.k; catPicked = true; chosen = true } label: {
                            let on = cat == c.k
                            // Đang chọn: nền màu danh mục (như ô ở màn hình chính); chưa chọn: nền xám rất nhạt
                            HStack(spacing: 8) {
                                CategoryIcon(c: c, size: 22).frame(width: 36, height: 36)
                                    .background(on ? Color.white.opacity(0.7) : c.color, in: Circle())
                                Text(c.name).font(.system(size: 17, weight: on ? .semibold : .medium))
                            }
                            .padding(.leading, 6).padding(.trailing, 16).padding(.vertical, 6)
                            .foregroundStyle(on ? c.ink : Color.primary)
                            .background(on ? c.color : Color.primary.opacity(0.05), in: Capsule())
                        }
                        .buttonStyle(Pressable())
                        .id(c.k)
                    }
                    // Tạo danh mục mới ngay tại đây, tạo xong chọn luôn
                    Button { addingCat = true } label: {
                        Label(L("Mới"), systemImage: "plus")
                            .font(.system(size: 17, weight: .medium))
                            .padding(.horizontal, 16).frame(height: 48)
                            .foregroundStyle(Color.primary)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                    }
                    .buttonStyle(Pressable())
                    .id("new")
                }
                .padding(.horizontal, 18)
            }
            .padding(.horizontal, -18)
            .onAppear { if let cat { proxy.scrollTo(cat, anchor: .center) } }
        }
    }

    // MARK: Bàn phím số

    private var keypad: some View {
        let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["000", "0", "del"]]
        return VStack(spacing: 4) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { k in
                        Button { press(k) } label: {
                            Group {
                                if k == "del" { Image(systemName: "delete.left").font(.system(size: 26)) }
                                else { Text(k).font(.system(size: k == "000" ? 26 : 32, weight: .medium)) }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(KeyStyle())
                        .accessibilityLabel(k == "del" ? L("Xoá") : k)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
        .frame(maxHeight: .infinity)
    }

    private func press(_ k: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        noteFocused = false
        withAnimation(.snappy(duration: 0.15)) {
            if k == "del" { digits = String(digits.dropLast()) }
            else if digits.isEmpty && (k == "0" || k == "000") { return }
            else if digits.count + k.count <= 12 { digits += k }
        }
    }

    // MARK: Nút

    @ViewBuilder private var actions: some View {
        VStack(spacing: 8) {
            switch mode {
            case .new, .raw:
                primary(L("Lưu")) { learn(); store.add(amount: amount, note: trimmed, cat: finalCat); dismiss() }
            case .scan(let q):
                let app = store.bankApp
                primary(L("Lưu & mở %@", app.name)) {
                    saveScan(q); dismiss()
                    let a = amount
                    Task { try? await Task.sleep(for: .milliseconds(350)); await BankLauncher.open(app, qr: q, amount: a) }
                }
                secondary(L("Chỉ lưu")) { saveScan(q); dismiss() }
                if !app.fill {
                    Text(L("Khi %@ mở ra, bạn quét lại mã QR. Chọn ACB One, MB, BIDV, VietinBank hoặc OCB trong Cài đặt để khỏi quét lại.", app.name))
                        .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            case .edit(var e):
                primary(L("Lưu thay đổi")) {
                    e.a = amount; e.n = trimmed; e.c = finalCat
                    learn(); store.update(e); dismiss()
                }
                Button(role: .destructive) { store.remove(id: e.id); dismiss() } label: {
                    Text(L("Xoá khoản này")).font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 46)
                }
                .foregroundStyle(Palette.danger)
            }
        }
    }

    private func primary(_ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(label).font(.system(size: 19, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 64)
                .foregroundStyle(Palette.ctaInk)
                .background(Palette.cta, in: Capsule())
        }
        .buttonStyle(Pressable())
        .disabled(amount == 0)
        .opacity(amount == 0 ? 0.35 : 1)
    }

    private func secondary(_ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(label).font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(.primary)
                .background(Palette.pill, in: Capsule())
        }
        .buttonStyle(Pressable())
        .disabled(amount == 0)
        .opacity(amount == 0 ? 0.35 : 1)
    }

    // MARK: Lưu

    private var trimmed: String { note.trimmingCharacters(in: .whitespaces) }
    private var finalCat: String { cat ?? store.guessCategory(trimmed) }

    /// Tự học: lần sau gõ / nói / quét đúng tên này thì app chọn sẵn danh mục người dùng đã chọn.
    private func learn() {
        if chosen { store.learnCategory(trimmed, finalCat) }
    }

    private func saveScan(_ q: VietQR) {
        learn()
        let key = q.memoKey
        let old = key.flatMap { store.memo[$0] }
        let name = !trimmed.isEmpty ? trimmed : (!q.name.isEmpty ? q.name : "\(q.bank) \(q.acct ?? "")")
        if let key { store.remember(key, Memo(c: finalCat, n: trimmed.isEmpty ? old?.n : trimmed)) }
        store.add(amount: amount, note: name, cat: finalCat, acct: key)
    }

    private func setup() {
        guard !ready else { return }
        ready = true
        switch mode {
        case .new(let c):
            cat = c; catPicked = c != nil
        case .raw:
            break
        case .scan(let q):
            let m = q.memoKey.flatMap { store.memo[$0] }
            note = m?.n ?? (!q.name.isEmpty ? q.name : q.purpose)
            if let a = q.amount, a > 0 { digits = String(a) }
            cat = m?.c ?? store.guessCategory(note)
            catPicked = m?.c != nil
        case .edit(let e):
            digits = String(e.a); note = e.n ?? ""; cat = e.c; catPicked = true
        }
    }
}

struct KeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(configuration.isPressed ? Palette.pill : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
