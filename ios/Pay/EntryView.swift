import SwiftUI

/// Màn hình nhập số tiền với bàn phím số lớn (lưu mới / sau khi quét QR / sửa).
struct EntryView: View {
    let mode: EntryMode
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var digits = ""
    @State private var cat: String?
    @State private var catPicked = false
    /// Danh mục có sẵn trước khi gõ ghi chú (quét QR: đoán theo tên người nhận). Ghi chú không gợi ra danh mục nào thì về lại đây
    @State private var baseCat: String?
    /// Người dùng tự bấm đổi danh mục: lưu xong thì nhớ danh mục này cho ghi chú.
    /// Mở từ ô danh mục thì không tính (chọn trước khi gõ, chưa phải đổi so với app đoán)
    @State private var chosen = false
    @State private var note = ""
    @State private var addingCat = false
    @State private var ready = false
    /// Ngày giờ của khoản đang sửa
    @State private var when = Date()
    @State private var pickingDate = false
    /// Đang nhập / sửa. Mở một khoản đã ghi thì ban đầu chỉ xem (bàn phím mờ), bấm Sửa mới sửa
    @State private var editing = true
    @FocusState private var noteFocused: Bool

    private var amount: Int { Int(digits) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            Text(L("Số tiền")).font(.system(size: 15)).foregroundStyle(.secondary).padding(.top, 26)
            HStack(spacing: 4) {
                Text(amount > 0 ? fmt(amount) : "0")
                    .font(.system(size: 40, weight: .bold)).kerning(-1)
                    .foregroundStyle(amount > 0 ? .primary : .tertiary)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                // Đang nhập số tiền: vạch nhấp nháy sau số, như con trỏ của ô nhập
                if editing && !noteFocused {
                    TimelineView(.periodic(from: .now, by: 0.55)) { t in
                        let on = Int(t.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
                        Capsule().fill(Palette.goodInk).frame(width: 3, height: 36).opacity(on ? 1 : 0)
                            .animation(.easeInOut(duration: 0.18), value: on)
                    }
                    .accessibilityHidden(true)
                }
                Spacer(minLength: 8)
                if isEdit {
                    // Ngày giờ của khoản, cùng hàng với số tiền: chạm để đổi (mở bảng lịch tự vẽ)
                    Button { noteFocused = false; withAnimation(.snappy) { editing = true }; pickingDate = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar").font(.system(size: 13, weight: .semibold))
                            Text(stamp(when)).font(.system(size: 15, weight: .medium)).lineLimit(1)
                        }
                        .padding(.horizontal, 12).frame(height: 36)
                        .foregroundStyle(.primary)
                        .background(Palette.pill, in: Capsule())
                        .fixedSize()
                    }
                    .buttonStyle(Pressable())
                    .accessibilityLabel(L("Ngày giờ"))
                }
            }
            // Ô số tiền: không nền, không viền (số to nằm thẳng trên nền màn hình)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture { noteFocused = false; withAnimation(.snappy) { editing = true } }
            .padding(.top, 8)

            chips.padding(.top, 28)

            TextField(L("Ghi chú (không bắt buộc)"), text: $note)
                .font(.system(size: 18))
                .focused($noteFocused)
                .submitLabel(.done)
                .padding(.horizontal, 18).padding(.vertical, 15)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.top, 24)
                .onChange(of: note) { _, v in
                    guard !catPicked else { return }
                    // Đoán lại theo ghi chú đang có, không giữ kết quả của lúc gõ dở (gõ "anh Tuấn mượn" thì "an" từng giữ Ăn uống).
                    // Ghi chú không gợi ra danh mục nào thì về danh mục ban đầu; riêng "Khác" đã học cho ghi chú này
                    // (từ khoá đoán ra danh mục khác mà app vẫn trả "Khác") thì phải chọn đúng "Khác"
                    let g = store.guessCategory(v)
                    cat = g != "khac" || Category.guess(v) != "khac" ? g : baseCat
                }
                // Chạm vào ghi chú cũng là bắt đầu sửa
                .onChange(of: noteFocused) { _, on in if on { withAnimation(.snappy) { editing = true } } }

            keypad.padding(.vertical, 8)
            // Hàng nút sát đáy, cách mép dưới 16 điểm bằng lề hai bên (như hai nút Nhập / Quét QR ở màn hình chính):
            // vùng an toàn dưới 34 điểm, lùi xuống 18
            actions.padding(.bottom, -18)
        }
        .padding(.horizontal, 16)
        // Bàn phím chữ (đang gõ ghi chú) phủ lên bàn phím số và các nút, bố cục đứng yên. Để iOS co vùng an toàn thì nội dung
        // không co nổi tới mức đó: phần đầu trượt lên dưới thanh trạng thái, nút Lưu vẫn chìm dưới bàn phím
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(Palette.surface.ignoresSafeArea())
        // Vuốt từ mép trái để quay lại, vuốt xuống để ẩn (màn hình này mở toàn màn hình nên iOS không có sẵn)
        .edgeBack(slides: { true }) { dismiss() }
        .swipeDownToClose { dismiss() }
        .onAppear(perform: setup)
        .sheet(isPresented: $pickingDate) {
            DateSheet(when: $when).presentationDetents([.height(560)]).sheetGrabber()
        }
        .sheet(isPresented: $addingCat) {
            // Tạo xong là đã đổi danh mục: vào trạng thái sửa như khi bấm một chip, để nút chính thành "Lưu thay đổi"
            CategoryEditor { k in cat = k; catPicked = true; chosen = true; withAnimation(.snappy) { editing = true } }
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
            // Khoản đã ghi: ngày giờ nằm trong ô số tiền (chạm để đổi), không lặp lại dưới tiêu đề
            if let sub, !isEdit { Text(sub).font(.system(size: 15)).foregroundStyle(.secondary).padding(.leading, 56).lineLimit(2) }
        }
        .padding(.top, 8)
    }

    private var isEdit: Bool {
        switch mode { case .edit, .editNow: return true; default: return false }
    }

    private var title: String {
        switch mode {
        case .new(let c): return c.map { "\(Category.get($0).icon) \(Category.get($0).name)" } ?? L("Lưu khoản chi")
        case .scan(let q): return L("Trả cho %@", q.name.isEmpty ? L("TK %@", q.acct ?? "") : q.name)
        case .raw: return L("Mã QR không phải VietQR")
        case .edit, .editNow: return L("Sửa khoản chi")
        }
    }

    private var sub: String? {
        switch mode {
        case .new: return nil
        case .scan(let q): return [q.bank, q.acct ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        case .raw(let s): return String(s.prefix(80))
        case .edit(let e), .editNow(let e): return stamp(e.date)
        }
    }

    private func stamp(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm, dd/MM"
        if Lang.isEnglish { f.locale = Lang.locale; f.dateFormat = "HH:mm, MMM d" }
        return f.string(from: d)
    }

    // MARK: Danh mục

    private var chips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Category.all) { c in
                        Button { cat = c.k; catPicked = true; chosen = true; withAnimation(.snappy) { editing = true } } label: {
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
            // Cuộn chip đang chọn vào giữa sau khi setup() gán xong `cat`. onAppear của hàng chip chạy trước
            // onAppear ngoài cùng (nơi gọi setup), lúc đó `cat` còn nil nên không cuộn được
            .onChange(of: ready) { _, _ in if let cat { proxy.scrollTo(cat, anchor: .center) } }
        }
    }

    // MARK: Bàn phím số

    private var keypad: some View {
        NumberPad(digits: $digits) { noteFocused = false }
        .frame(maxHeight: 320)
        .frame(maxHeight: .infinity)
        // Chưa bấm Sửa: bàn phím mờ và không nhận chạm
        .opacity(editing ? 1 : 0.25)
        .disabled(!editing)
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
            case .edit(var e), .editNow(var e):
                // Xoá và Sửa / Lưu thay đổi cùng một hàng, cùng kiểu hai nút Nhập / Quét QR ở màn hình chính
                GlassGroup {
                    HStack(spacing: 12) {
                        BigButton(title: L("Xoá"), icon: "", primary: false) {
                            // Đóng màn hình trước, xoá khi nó trượt đi gần hết: xoá ngay thì thanh "Đã xoá" bật lên sau màn hình
                            // đang trượt xuống, tới lúc thấy được thì nó đã đứng yên, như không có hiệu ứng
                            let id = e.id
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { store.remove(id: id) }
                        }
                        if editing {
                            BigButton(title: L("Lưu"), icon: "", primary: true) {
                                guard amount > 0 else { return }
                                e.a = amount; e.n = trimmed; e.c = finalCat
                                // Chỉ ghi lại thời điểm khi người dùng thật sự đổi (so theo phút), kẻo lệch mili giây làm xáo thứ tự
                                if abs(when.timeIntervalSince(e.date)) >= 60 { e.t = when.timeIntervalSince1970 * 1000 }
                                learn(); store.update(e); dismiss()
                            }
                            .opacity(amount == 0 ? 0.35 : 1)
                        } else {
                            BigButton(title: L("Sửa"), icon: "", primary: true) { withAnimation(.snappy) { editing = true } }
                        }
                    }
                }
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
            baseCat = cat
        case .edit(let e), .editNow(let e):
            digits = String(e.a); note = e.n ?? ""; cat = e.c; catPicked = true; when = e.date
            // Chạm vào một khoản thì ban đầu chỉ xem; đã bấm hẳn "Sửa" (thẻ nói, bảng nhấn giữ) thì vào sửa luôn
            if case .edit = mode { editing = false }
        }
    }
}

/// Bàn phím số của app (1–9, 000, 0, xoá): dùng ở màn nhập khoản chi và khoản chung thay cho bàn phím số của iOS.
struct NumberPad: View {
    @Binding var digits: String
    /// Gọi mỗi lần bấm phím (vd bỏ chọn ô ghi chú)
    var onPress: () -> Void = {}

    var body: some View {
        let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["000", "0", "del"]]
        VStack(spacing: 4) {
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
    }

    private func press(_ k: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onPress()
        withAnimation(.snappy(duration: 0.15)) {
            if k == "del" { digits = String(digits.dropLast()) }
            else if digits.isEmpty && (k == "0" || k == "000") { return }
            else if digits.count + k.count <= 12 { digits += k }
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

/// Bảng chọn ngày giờ tự vẽ (không dùng DatePicker của iOS): lịch tháng bắt đầu từ thứ Hai, hai ô chỉnh giờ / phút, nút Xong.
/// Không chọn được thời điểm trong tương lai.
struct DateSheet: View {
    @Binding var when: Date
    @Environment(\.dismiss) private var dismiss
    /// Tháng đang xem
    @State private var month = Date()

    private var cal: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    private var first: Date { cal.date(from: cal.dateComponents([.year, .month], from: month))! }
    private var isThisMonth: Bool { cal.isDate(month, equalTo: Date(), toGranularity: .month) }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(title).font(.system(size: 21, weight: .bold))
                Spacer()
                arrow("chevron.left", L("Tháng trước")) { shift(-1) }
                arrow("chevron.right", L("Tháng sau")) { shift(1) }.opacity(isThisMonth ? 0.3 : 1).disabled(isThisMonth)
            }
            let names = Lang.isEnglish ? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] : ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]
            HStack(spacing: 0) {
                ForEach(names, id: \.self) { Text($0).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
            }
            // Ô trống đầu tháng cho ngày 1 rơi đúng cột thứ của nó
            let blanks = (cal.component(.weekday, from: first) + 5) % 7
            let days = cal.range(of: .day, in: .month, for: first)!.count
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                // Mã âm cho ô trống, kẻo trùng mã với ngày 1, 2… (trùng thì các ngày đó không được vẽ)
                ForEach((0..<blanks).map { -1 - $0 }, id: \.self) { _ in Color.clear.frame(height: 42) }
                ForEach(1...days, id: \.self) { d in
                    let date = cal.date(byAdding: .day, value: d - 1, to: first)!
                    let on = cal.isDate(date, inSameDayAs: when), today = cal.isDateInToday(date), future = date > Date()
                    Button { pick(date) } label: {
                        Text("\(d)").font(.system(size: 17, weight: on || today ? .bold : .regular))
                            .foregroundStyle(on ? Palette.ctaInk : .primary)
                            .frame(width: 42, height: 42)
                            .background(on ? Palette.cta : .clear, in: Circle())
                            .overlay { if today && !on { Circle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1.5) } }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(future ? 0.25 : 1).disabled(future)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text(L("Giờ")).font(.system(size: 17, weight: .semibold))
                Spacer()
                wheel(24, Binding(get: { cal.component(.hour, from: when) }, set: { setTime(hour: $0) }))
                Text(":").font(.system(size: 22, weight: .bold)).foregroundStyle(.secondary)
                wheel(60, Binding(get: { cal.component(.minute, from: when) }, set: { setTime(minute: $0) }))
            }
            .frame(height: 120)
            Button { dismiss() } label: {
                Text(L("Xong")).font(.system(size: 19, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .foregroundStyle(Palette.ctaInk).background(Palette.cta, in: Capsule())
            }
            .buttonStyle(Pressable())
        }
        .padding(.horizontal, 20).padding(.top, 34).padding(.bottom, 12)
        .background(Palette.surface.ignoresSafeArea())
        .onAppear { month = when }
    }

    private var title: String {
        let c = cal.dateComponents([.month, .year], from: month)
        guard Lang.isEnglish else { return "Tháng \(c.month!), \(c.year!)" }
        let f = DateFormatter(); f.locale = Lang.locale; f.dateFormat = "LLLL yyyy"
        return f.string(from: month)
    }

    private func arrow(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(.primary)
                .frame(width: 38, height: 38).background(Palette.pill, in: Circle())
        }
        .buttonStyle(Pressable()).accessibilityLabel(label)
    }

    /// Bánh xe cuộn bằng ngón tay (bánh xe của iOS: kéo trong bảng không kéo theo cả bảng)
    private func wheel(_ count: Int, _ value: Binding<Int>) -> some View {
        Picker("", selection: value) {
            ForEach(0..<count, id: \.self) { n in
                Text(String(format: "%02d", n)).font(.system(size: 22, weight: .semibold).monospacedDigit()).tag(n)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(width: 76)
        .clipped()
    }

    private func shift(_ by: Int) {
        guard let m = cal.date(byAdding: .month, value: by, to: first), m <= Date() else { return }
        withAnimation(.snappy) { month = m }
    }

    /// Đổi ngày, giữ nguyên giờ phút
    private func pick(_ day: Date) {
        let t = cal.dateComponents([.hour, .minute], from: when)
        UISelectionFeedbackGenerator().selectionChanged()
        set(cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: day) ?? day)
    }

    /// Đổi giờ hoặc phút, giữ nguyên ngày
    private func setTime(hour: Int? = nil, minute: Int? = nil) {
        var c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: when)
        if let hour { c.hour = hour }
        if let minute { c.minute = minute }
        if let d = cal.date(from: c) { set(d) }
    }

    private func set(_ d: Date) { withAnimation(.snappy(duration: 0.2)) { when = min(d, Date()) } }
}
