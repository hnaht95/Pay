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
    /// Danh mục đứng đầu hàng chip: danh mục của khoản lúc mở màn hình
    @State private var leadCat: String?
    /// Hàng chip còn chip bị che ở mép trái / phải (để làm mờ mép đó)
    @State private var chipFade = [false, true]
    @State private var addingCat = false
    @State private var ready = false
    /// Ngày giờ của khoản đang sửa
    @State private var when = Date()
    @State private var pickingDate = false
    /// Đang nhập / sửa. Mở một khoản đã ghi thì ban đầu chỉ xem (bàn phím mờ), bấm Sửa mới sửa
    @State private var editing = true
    @FocusState private var noteFocused: Bool
    @State private var scanningReceipt = false
    /// Ảnh hoá đơn đính kèm khoản (lưu trong Pay, xem ReceiptPhotos); đổi / xoá rồi thì lưu lại lúc bấm Lưu
    @State private var photo: UIImage?
    @State private var photoChanged = false
    @State private var viewingPhoto = false

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
            // Ô số tiền: khung viền mảnh, nhạt, không nền
            .padding(.horizontal, 18).padding(.vertical, 12)
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1) }
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
        .onAppear(perform: setup)
        .sheet(isPresented: $pickingDate) {
            DateSheet(when: $when).sheetGrabber()
        }
        .fullScreenCover(isPresented: $scanningReceipt) {
            ReceiptCamera { img in
                scanningReceipt = false
                guard let img else { return }
                withAnimation(.snappy) { photo = img; photoChanged = true; editing = true }
            }
        }
        .fullScreenCover(isPresented: $viewingPhoto) {
            PhotoViewer(image: photo, retake: {
                viewingPhoto = false
                Task { try? await Task.sleep(for: .milliseconds(350)); scanningReceipt = true }
            }, remove: {
                viewingPhoto = false
                withAnimation(.snappy) { photo = nil; photoChanged = true; editing = true }
            }, editable: editing)
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
        VStack(spacing: 2) {
            // Tiêu đề ở giữa. Màn mở dạng tấm (không phủ kín màn hình): đóng bằng vuốt xuống như các tấm khác,
            // không có mũi tên quay lại hay vuốt từ mép trái
            Text(title).font(.system(size: 21, weight: .bold)).lineLimit(1)
                .padding(.horizontal, 52)
                .frame(maxWidth: .infinity, minHeight: 46)
                .overlay(alignment: .trailing) {
                    // Ảnh hoá đơn: đã có thì hiện ảnh nhỏ (chạm để xem to / chụp lại / xoá); chưa có thì nút chụp
                    if let photo {
                        Button { viewingPhoto = true } label: {
                            Image(uiImage: photo).resizable().scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .frame(width: 46, height: 46).contentShape(Rectangle())
                        }
                        .buttonStyle(Pressable())
                        .accessibilityLabel(L("Ảnh hoá đơn"))
                    } else if isNewEntry || isEdit {
                        Button { scanningReceipt = true } label: {
                            Image(systemName: "camera.aperture").font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 46, height: 46).contentShape(Rectangle())
                        }
                        .buttonStyle(Pressable())
                        .accessibilityLabel(L("Chụp hoá đơn"))
                    }
                }
            // Khoản đã ghi: ngày giờ nằm trong ô số tiền (chạm để đổi), không lặp lại dưới tiêu đề
            if let sub, !isEdit { Text(sub).font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2) }
        }
        .padding(.top, 8)
    }

    /// Nhập mới (tay hoặc từ hoá đơn): có nút chụp hoá đơn ở góc trên
    private var isNewEntry: Bool {
        switch mode { case .new, .receipt: return true; default: return false }
    }

    private var isEdit: Bool {
        switch mode { case .edit, .editNow: return true; default: return false }
    }

    private var title: String {
        switch mode {
        case .new(let c): return c.map { "\(Category.get($0).icon) \(Category.get($0).name)" } ?? L("Lưu khoản chi")
        case .receipt: return L("Lưu khoản chi")
        case .scan(let q): return L("Trả cho %@", q.name.isEmpty ? L("TK %@", q.acct ?? "") : q.name)
        case .raw: return L("Mã QR không phải VietQR")
        case .edit, .editNow: return L("Sửa khoản chi")
        }
    }

    private var sub: String? {
        switch mode {
        case .new, .receipt: return nil
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
                    // Danh mục đã chọn khi mở màn hình đứng đầu hàng (không bị cắt hai bên); bấm chọn danh mục khác thì
                    // thứ tự giữ nguyên, khỏi nhảy chỗ dưới ngón tay
                    let all = Category.all
                    let ordered = all.filter { $0.k == leadCat } + all.filter { $0.k != leadCat }
                    ForEach(ordered) { c in
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
            // Hai mép mờ dần khi cuộn: chip đi ra mép thì tan vào nền thay vì bị cắt thẳng
            // Chỉ mờ phía còn chip bị che: đang ở đầu hàng thì mép trái không mờ, cuộn hết thì mép phải không mờ
            .modifier(ChipEdges(fade: $chipFade))
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [chipFade[0] ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing).frame(width: 24)
                    Color.black
                    LinearGradient(colors: [.black, chipFade[1] ? .clear : .black], startPoint: .leading, endPoint: .trailing).frame(width: 24)
                }
            }
            // Sau khi setup() gán xong `cat` (onAppear của hàng chip chạy trước, lúc đó `cat` còn nil): đưa nó lên đầu hàng
            // (đứng đầu rồi nên hàng ở vị trí ban đầu là thấy, không cuộn: cuộn tới chip thì mất lề trái)
            .onChange(of: ready) { _, _ in leadCat = cat }
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
            case .new, .raw, .receipt:
                // Huỷ và Lưu cùng một hàng, cùng kiểu hai nút Nhập / Quét QR ở màn hình chính
                HStack(spacing: 12) {
                    BigButton(title: L("Huỷ"), icon: "", primary: false) { dismiss() }
                    BigButton(title: L("Lưu"), icon: "", primary: true) {
                        guard amount > 0 else { return }
                        learn(); store.add(amount: amount, note: trimmed, cat: finalCat)
                        if let photo, let id = store.items.last?.id { ReceiptPhotos.save(photo, id: id) }
                        dismiss()
                    }
                    .opacity(amount == 0 ? 0.35 : 1)
                    .animation(.easeInOut(duration: 0.25), value: amount == 0)
                }
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
                // Huỷ và Sửa / Lưu thay đổi cùng một hàng. Xoá khoản: vuốt trái ở danh sách hoặc nhấn giữ
                GlassGroup {
                    HStack(spacing: 12) {
                        BigButton(title: L("Huỷ"), icon: "", primary: false) { dismiss() }
                        if editing {
                            BigButton(title: L("Lưu"), icon: "", primary: true) {
                                guard amount > 0 else { return }
                                e.a = amount; e.n = trimmed; e.c = finalCat
                                // Chỉ ghi lại thời điểm khi người dùng thật sự đổi (so theo phút), kẻo lệch mili giây làm xáo thứ tự
                                if abs(when.timeIntervalSince(e.date)) >= 60 { e.t = when.timeIntervalSince1970 * 1000 }
                                learn(); store.update(e)
                                if photoChanged { if let photo { ReceiptPhotos.save(photo, id: e.id) } else { ReceiptPhotos.remove(e.id) } }
                                dismiss()
                            }
                            .opacity(amount == 0 ? 0.35 : 1)
                            .animation(.easeInOut(duration: 0.25), value: amount == 0)
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
            // Cao và cỡ chữ bằng nút Xoá / Sửa (BigButton)
            Text(label).font(.system(size: 21, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 56 + BigButton.inset * 2)
                .foregroundStyle(Palette.ctaInk)
                .background(Palette.cta, in: Capsule())
        }
        .buttonStyle(Pressable())
        .disabled(amount == 0)
        .opacity(amount == 0 ? 0.35 : 1)
        .animation(.easeInOut(duration: 0.25), value: amount == 0)   // sáng / mờ chuyển dần, không bật tắt
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
        .animation(.easeInOut(duration: 0.25), value: amount == 0)   // sáng / mờ chuyển dần, không bật tắt
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
        case .receipt(let img):
            // Từ hoá đơn vừa chụp: ảnh đính kèm sẵn, số tiền và ghi chú nhập tay
            photo = img; photoChanged = true
        case .scan(let q):
            let m = q.memoKey.flatMap { store.memo[$0] }
            note = m?.n ?? (!q.name.isEmpty ? q.name : q.purpose)
            if let a = q.amount, a > 0 { digits = String(a) }
            cat = m?.c ?? store.guessCategory(note)
            catPicked = m?.c != nil
            baseCat = cat
        case .edit(let e), .editNow(let e):
            digits = String(e.a); note = e.n ?? ""; cat = e.c; catPicked = true; when = e.date
            let id = e.id
            Task { if let img = await ReceiptPhotos.load(id), !photoChanged { photo = img } }
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
    /// Lần đổi tháng gần nhất là tới tháng sau (lưới trượt lên) hay lùi tháng trước (trượt xuống)
    @State private var forward = true
    /// Ngày giờ lúc mở bảng, để Huỷ trả về
    @State private var original: Date?
    /// Bề ngang nút "Hôm nay" lúc bung (đo theo chữ), để co / nở được bằng một con số
    @State private var todayW: CGFloat = 90
    /// Bề ngang hàng lịch + giờ, để chia chỗ cho lưới và hai bánh xe
    @State private var rowW: CGFloat = 340
    /// Chiều cao nội dung tấm, để tấm cao vừa khít
    @State private var contentH: CGFloat = 330
    /// Nút Xong thò xuống dưới đáy nội dung chừng này: hết lề dưới 8 và vùng thanh home, chừa 20 pt tới đáy tấm
    private static var extendDown: CGFloat {
        let safe = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.safeAreaInsets.bottom ?? 34
        return max(0, 8 + safe - 18.5)   // đo trên máy: tấm (iOS 26) lùi vào ~1,5 pt so với lề phải, nên chừa 18,5 cho hai lề bằng nhau
    }

    private var cal: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    private var first: Date { cal.date(from: cal.dateComponents([.year, .month], from: month))! }
    private var isThisMonth: Bool { cal.isDate(month, equalTo: Date(), toGranularity: .month) }

    var body: some View {
        VStack(spacing: 14) {
            // Hàng tiêu đề như lịch của Peek (cỡ Peek × 1,5): "Tháng 10 năm 2026" chữ vừa mờ 55% (không hình tờ lịch);
            // nút "Hôm nay" luôn dựng sẵn, chỉ co bề ngang về 0 rồi mờ đi khi đang ở tháng này (bật ra thì nở từ 0, hai mũi tên
            // trượt theo); hai tam giác lên / xuống (lịch xếp tuần theo chiều dọc, lùi tháng là đi lên)
            HStack(spacing: 0) {
                Text(title).font(.system(size: 17, weight: .medium))
                    .contentTransition(.numericText())
                    .foregroundStyle(Color.primary.opacity(0.55))
                Spacer(minLength: 8)
                let showsToday = !isThisMonth
                Button { jumpToToday() } label: {
                    Text(L("Hôm nay")).font(.system(size: 15.75, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { todayW = ceil($0) + 24 }
                        .opacity(showsToday ? 1 : 0)
                        .frame(width: showsToday ? todayW : 0, height: 36)
                        .background(Capsule().fill(Color.primary.opacity(showsToday ? 0.08 : 0)))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(showsToday)
                .padding(.trailing, showsToday ? 4 : 0)
                arrow(angle: 0, L("Tháng trước")) { shift(-1) }
                arrow(angle: 180, L("Tháng sau")) { shift(1) }.opacity(isThisMonth ? 0.3 : 1).disabled(isThisMonth)
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.75), value: isThisMonth)
            // Lịch tháng bên trái, giờ : phút bên phải trên cùng một hàng (như Peek chia hai cột khi mở cả tháng);
            // hai bánh xe cao đúng bằng lưới
            // Lưới chiếm hết phần ngang còn lại (bánh xe giờ phút gọn 96 pt); chữ số giờ phút cùng cỡ chữ số ngày
            let wheelsW: CGFloat = 96
            let gw = max(0, rowW - wheelsW - 10)
            let k = gw / 7 / P.pitch
            let gh = k * P.height(rows: 6)
            HStack(alignment: .top, spacing: 10) {
                // Đổi tháng: lưới cũ trượt ra, lưới mới trượt vào theo chiều dọc (tháng sau từ dưới lên, tháng trước từ trên xuống)
                ZStack {
                    monthGrid
                        .id(first)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .bottom : .top).combined(with: .opacity),
                            removal: .move(edge: forward ? .top : .bottom).combined(with: .opacity)))
                }
                // Cắt rìa khi trượt, nhưng chừa 2 pt: nét khung 1,5 chạy đúng mép lưới, cắt sát thì nửa nét ở mép ngoài mất,
                // cạnh ngoài mỏng hơn cạnh trong
                .padding(2).clipped().padding(-2)
                .frame(width: gw, height: gh)
                // Khung giờ như Peek (nền tối bo góc, giờ : phút, phút nhảy từng 5, hai mép trên dưới mờ dần), cao đúng bằng
                // dải nền T7 / CN và nằm ngang hàng với dải ấy (không lên tới hàng chữ thứ)
                let colH = 6 * (P.row + P.rowGap) * k
                HStack(spacing: 4 * k) {
                    PeekWheel(count: 24, value: Binding(get: { cal.component(.hour, from: when) }, set: { setTime(hour: $0) }),
                              pitch: 18 * k, font: 17 * k)
                        .frame(width: 26 * k)
                    Text(":").font(.system(size: 17 * k, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.45))
                    PeekWheel(count: 12, step: 5, value: Binding(get: { cal.component(.minute, from: when) }, set: { setTime(minute: $0) }),
                              pitch: 18 * k, font: 17 * k)
                        .frame(width: 26 * k)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .mask {
                    LinearGradient(stops: [.init(color: .black.opacity(0.06), location: 0), .init(color: .black, location: 0.35),
                                           .init(color: .black, location: 0.65), .init(color: .black.opacity(0.06), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .frame(height: 5 * 18 * k)
                // Không nền, chỉ viền mảnh cùng màu khung tháng
                .overlay(RoundedRectangle(cornerRadius: P.frameR * k, style: .continuous)
                    .strokeBorder(Color(light: 0xD9D9DC, dark: 0x3A3A3E), lineWidth: 1.5))
                // Khung giờ gọn 5 hàng như Peek; phần còn lại của cột là nút "Bây giờ"
                .frame(maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .bottom) { dayBox(k: k).frame(height: colH - 5 * 18 * k - 8) }
                .frame(width: wheelsW, height: colH)
                .padding(.top, (P.band - P.rowGap / 2) * k)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowW = $0 }
            // Huỷ / Lưu ở đáy, to bằng hai nút Nhập / Quét QR của màn hình chính. Huỷ trả ngày giờ về như lúc mở
            HStack(spacing: 12) {
                BigButton(title: L("Huỷ"), icon: "", primary: false) { when = original ?? when; dismiss() }
                BigButton(title: L("Lưu"), icon: "", primary: true) { dismiss() }
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 8)
        // Cả cụm hạ xuống qua vùng thanh home: đáy lịch / nút Xong cách đáy tấm bằng lề phải, góc dưới phải nút Xong đồng tâm góc tấm.
        // (Bớt phần ấy khỏi chiều cao đo được: tấm thấp đi đúng chừng đó, nội dung tràn xuống vùng thanh home)
        .padding(.bottom, -Self.extendDown)
        // Tấm cao vừa khít nội dung (đo thật), không chừa khoảng trống dưới lịch
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentH = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.surface.ignoresSafeArea())
        .presentationDetents([.height(max(contentH, 200))])
        .onAppear { month = when; if original == nil { original = when } }
    }

    private var title: String {
        let c = cal.dateComponents([.month, .year], from: month)
        guard Lang.isEnglish else { return "Tháng \(c.month!) năm \(c.year!)" }
        let f = DateFormatter(); f.locale = Lang.locale; f.dateFormat = "LLLL yyyy"
        return f.string(from: month)
    }

    /// Ô dưới khung giờ: nút "Bây giờ" lấp cả ô, đưa về ngày giờ hiện tại (đang ở bây giờ thì mờ đi)
    private func dayBox(k: CGFloat) -> some View {
        let isNow = abs(when.timeIntervalSinceNow) < 60
        return Button {
            forward = Date() > first
            withAnimation(.spring(response: 0.42, dampingFraction: 0.75)) { when = Date(); month = Date() }
        } label: {
            Text(L("Bây giờ")).font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(Color.primary.opacity(isNow ? 0.35 : 0.85))
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: P.frameR * k, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: P.frameR * k, style: .continuous))
        }
        .buttonStyle(Pressable())
        .disabled(isNow)
        .animation(.easeInOut(duration: 0.2), value: isNow)
    }

    /// Tam giác bo góc của Peek (TriangleShape), mờ 45%, không nền
    private func arrow(angle: Double, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            // Cỡ Peek × 1,5: hình 7 trong khung 22, mỗi nút rộng 24 cách nhau 2
            TriangleShape().fill(Color.primary.opacity(0.45))
                .frame(width: 10.5, height: 10.5)
                .rotationEffect(.degrees(angle))
                .animation(.easeOut(duration: 0.2), value: angle)
                .frame(width: 36, height: 33).contentShape(Circle())
        }
        .buttonStyle(Pressable()).accessibilityLabel(label)
    }

    private func jumpToToday() {
        forward = Date() > first
        withAnimation(.spring(response: 0.42, dampingFraction: 0.75)) { month = Date() }
    }

    /// Bánh xe cuộn bằng ngón tay (bánh xe của iOS: kéo trong bảng không kéo theo cả bảng)
    // MARK: Lưới ngày — chép hình học lịch tháng của Peek (CalendarPanel / CalendarShapes, lúc mở cả tháng), phóng theo bề ngang
    //
    // Số gốc của Peek ở nhịp cột 28 pt: chữ số 11, chữ thứ 10, phần số mỗi hàng 23, hở hàng 2, hở cột 4, dải chữ thứ = 23 + 2,
    // viên nền cao 23 + 2 − 2×2 bo 0,31 chiều cao, khung tháng bo = bo viên + 2, nét 1,5 màu đặc nhạt, dải cuối tuần đậm 0,08,
    // ngày tháng khác mờ còn 0,42. Ở đây nhịp cột ≈ 49 pt nên mọi số nhân cùng hệ số k = nhịp / 28 (nét khung giữ 1,5).

    private enum P {
        static let pitch: CGFloat = 28, font: CGFloat = 11, symbolFont: CGFloat = 10
        static let row: CGFloat = 23, rowGap: CGFloat = 2, colGap: CGFloat = 4, frameGap: CGFloat = 2
        static var band: CGFloat { row + 2 }
        static var pillH: CGFloat { row + rowGap - frameGap * 2 }
        static var pillR: CGFloat { pillH * 0.31 }
        static var frameR: CGFloat { pillR + frameGap }
        static func height(rows: Int) -> CGFloat { band + CGFloat(rows) * (row + rowGap) - rowGap }
    }

    private var monthGrid: some View {
        let blanks = (cal.component(.weekday, from: first) + 5) % 7
        let days = cal.range(of: .day, in: .month, for: first)!.count
        // Luôn 6 hàng như Peek: tháng nào cũng cao bằng nhau, đổi tháng không nhảy chiều cao
        let rows = 6
        let names = Lang.isEnglish ? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] : ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]
        let todayCol = (cal.component(.weekday, from: Date()) + 5) % 7
        return GeometryReader { g in
            let k = g.size.width / 7 / P.pitch
            let rowH = P.row * k, gap = P.rowGap * k, band = P.band * k
            let grid = DayGrid(width: g.size.width - P.colGap * k, rowPitch: rowH + gap, columnGap: P.colGap * k, rowGap: gap)
            ZStack(alignment: .topLeading) {
                // Khung tháng: màu đặc (không trong suốt) để đoạn đi qua dải cuối tuần không sáng hơn đoạn khác
                MonthFrame(first: blanks, last: blanks + days - 1, grid: grid, radius: P.frameR * k)
                    .stroke(Color(light: 0xD9D9DC, dark: 0x3A3A3E), lineWidth: 1.5)
                    .offset(x: P.colGap * k / 2, y: band)
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(names.indices, id: \.self) { i in
                            Text(names[i]).font(.system(size: P.symbolFont * k, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(i == todayCol && isThisMonth ? 0.6 : 0.35))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: band)
                    VStack(spacing: gap) {
                        ForEach(0..<rows, id: \.self) { r in
                            HStack(spacing: 0) {
                                ForEach(0..<7, id: \.self) { c in
                                    dayCell(cal.date(byAdding: .day, value: r * 7 + c - blanks, to: first)!, k: k)
                                        .frame(maxWidth: .infinity).frame(height: rowH)
                                }
                            }
                        }
                    }
                }
            }
        }
        .aspectRatio(7 * P.pitch / P.height(rows: rows), contentMode: .fit)
    }

    private func dayCell(_ date: Date, k: CGFloat) -> some View {
        let inMonth = cal.isDate(date, equalTo: first, toGranularity: .month)
        let on = cal.isDate(date, inSameDayAs: when), today = cal.isDateInToday(date), future = date > Date()
        return Button { pick(date) } label: {
            Text("\(cal.component(.day, from: date))")
                .font(.system(size: P.font * k, weight: on || today ? .semibold : .medium, design: .rounded)).monospacedDigit()
                .foregroundStyle(on ? Palette.ctaInk : Color.primary.opacity(today ? 1 : 0.85))
                .frame(maxWidth: .infinity)
                .frame(height: P.pillH * k)
                // Viên nền lấp cả ô trừ hở 2 mỗi bên (cách nét khung đúng 2 ở mọi phía). Ngày đang chọn: nền đen chữ trắng như
                // nút chính (xám nhạt đứng trên dải cuối tuần cũng xám thì gần như không đọc ra); hôm nay: nền xanh lá nhạt
                .background(on ? Palette.cta : today ? Color.primary.opacity(0.1) : .clear,
                            in: RoundedRectangle(cornerRadius: P.pillR * k, style: .continuous))
                .padding(.horizontal, P.frameGap * k)
                .opacity(inMonth ? 1 : 0.42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(future)   // ngày chưa tới vẫn sáng như ngày thường, chỉ không chạm được; chỉ ngày khác tháng mới mờ
    }

    private func wheel(_ count: Int, _ value: Binding<Int>) -> some View {
        FlatWheel(count: count, value: value).frame(width: 76)
    }

    private func shift(_ by: Int) {
        guard let m = cal.date(byAdding: .month, value: by, to: first), m <= Date() else { return }
        forward = by > 0
        withAnimation(.spring(response: 0.42, dampingFraction: 0.75)) { month = m }
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

/// Theo dõi hàng chip đang cuộn tới đâu: còn chip bị che ở mép trái / phải không (iOS 17 không có, giữ mờ mép phải).
struct ChipEdges: ViewModifier {
    @Binding var fade: [Bool]

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: [Bool].self) { g in
                [g.contentOffset.x > 1, g.contentOffset.x < g.contentSize.width - g.containerSize.width - 1]
            } action: { _, v in withAnimation(.easeOut(duration: 0.15)) { fade = v } }
        } else {
            content
        }
    }
}

/// Bánh xe chọn số phẳng: cuộn dọc, dừng đúng từng hàng, số giữa đậm trên viên nền, các số kề mờ dần.
/// Không dùng Picker(.wheel) của iOS: bánh xe ấy cong như mặt trụ nên các số trên / dưới bị bóp dẹt chữ.
private struct FlatWheel: View {
    let count: Int
    @Binding var value: Int
    /// Cỡ chữ số và chiều cao một hàng (mặc định 22 / 36; đứng cạnh lịch thì nhỏ theo chữ số của lịch)
    var font: CGFloat = 22
    var row: CGFloat = 36
    @State private var pos: Int?

    var body: some View {
        GeometryReader { g in
            let pad = max(0, (g.size.height - row) / 2)
            ZStack {
                Capsule().fill(Palette.pill).frame(height: row)
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<count, id: \.self) { n in
                            let on = n == (pos ?? value)
                            Text(String(format: "%02d", n))
                                .font(.system(size: font, weight: .semibold).monospacedDigit())
                                .foregroundStyle(on ? Color.primary : Color.secondary)
                                .frame(maxWidth: .infinity, minHeight: row, maxHeight: row)
                                .contentShape(Rectangle())
                                .onTapGesture { withAnimation(.snappy) { pos = n } }
                                .id(n)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.vertical, pad, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $pos, anchor: .center)
                // Mờ dần lên trên / xuống dưới thay cho độ cong
                .mask {
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.35),
                                           .init(color: .black, location: 0.65), .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .onAppear { pos = value }
        .onChange(of: pos) { _, p in if let p, p != value { value = p } }
        .onChange(of: value) { _, v in if pos != v { pos = v } }
        .sensoryFeedback(.selection, trigger: pos)
    }
}

/// Lưới 7 cột của Peek (CalendarShapes.swift): mép ô nằm giữa khe, nên khung tháng và dải cuối tuần chạy đúng giữa hai ô
private struct DayGrid {
    var width: CGFloat, rowPitch: CGFloat, columnGap: CGFloat, rowGap: CGFloat
    var columnPitch: CGFloat { (width + columnGap) / 7 }
    func left(_ c: Int) -> CGFloat { CGFloat(c) * columnPitch - columnGap / 2 }
    func right(_ c: Int) -> CGFloat { CGFloat(c + 1) * columnPitch - columnGap / 2 }
    func top(_ r: Int) -> CGFloat { CGFloat(r) * rowPitch - rowGap / 2 }
    func bottom(_ r: Int) -> CGFloat { CGFloat(r + 1) * rowPitch - rowGap / 2 }
}

/// Khung bậc thang ôm trọn một tháng (chép MonthFrame của Peek): mọi góc bo bằng đường cong bậc hai, cắt ngắn lại nếu cạnh ngắn
private struct MonthFrame: Shape {
    let first: Int, last: Int
    let grid: DayGrid
    let radius: CGFloat

    func path(in _: CGRect) -> Path {
        let fr = first / 7, fc = first % 7, lr = last / 7, lc = last % 7
        guard lr > fr else {
            return Self.rounded([CGPoint(x: grid.left(fc), y: grid.top(fr)), CGPoint(x: grid.right(lc), y: grid.top(fr)),
                                 CGPoint(x: grid.right(lc), y: grid.bottom(lr)), CGPoint(x: grid.left(fc), y: grid.bottom(lr))], radius: radius)
        }
        return Self.rounded([CGPoint(x: grid.left(fc), y: grid.top(fr)), CGPoint(x: grid.right(6), y: grid.top(fr)),
                             CGPoint(x: grid.right(6), y: grid.top(lr)), CGPoint(x: grid.right(lc), y: grid.top(lr)),
                             CGPoint(x: grid.right(lc), y: grid.bottom(lr)), CGPoint(x: grid.left(0), y: grid.bottom(lr)),
                             CGPoint(x: grid.left(0), y: grid.bottom(fr)), CGPoint(x: grid.left(fc), y: grid.bottom(fr))], radius: radius)
    }

    private static func rounded(_ points: [CGPoint], radius: CGFloat) -> Path {
        var corners: [CGPoint] = []
        for (i, p) in points.enumerated() where p != points[(i + 1) % points.count] { corners.append(p) }
        var path = Path()
        let n = corners.count
        guard n > 2 else { return path }
        func cut(_ from: CGPoint, toward: CGPoint) -> CGPoint {
            let dx = toward.x - from.x, dy = toward.y - from.y
            let length = max(hypot(dx, dy), 0.0001)
            let k = min(radius, length / 2) / length
            return CGPoint(x: from.x + dx * k, y: from.y + dy * k)
        }
        for i in 0..<n {
            let c = corners[i]
            let start = cut(c, toward: corners[(i - 1 + n) % n]), end = cut(c, toward: corners[(i + 1) % n])
            if i == 0 { path.move(to: start) } else { path.addLine(to: start) }
            path.addQuadCurve(to: end, control: c)
        }
        path.closeSubpath()
        return path
    }
}

/// Dải nền hai cột T7 / CN, từ hàng ngày đầu tới hàng cuối (chép WeekendBand của Peek)
private struct WeekendBand: Shape {
    let rows: Int
    let grid: DayGrid
    let radius: CGFloat

    func path(in _: CGRect) -> Path {
        guard rows > 0 else { return Path() }
        let box = CGRect(x: grid.left(5), y: grid.top(0), width: grid.right(6) - grid.left(5), height: grid.bottom(rows - 1) - grid.top(0))
        return Path(roundedRect: box, cornerRadius: radius, style: .continuous)
    }
}

/// Một cột bánh xe giờ / phút kiểu Peek (NoteTimeWheel / WheelColumn): quay vòng (trên 00 là 55, 50…), hàng giữa chữ to đậm,
/// lệch một hàng thì chữ nhỏ lại (17 → 12) và mờ còn 60%. Kéo tay rồi buông thì bật về đúng nấc gần nhất (có đà theo tốc độ vuốt).
/// Tự vẽ bằng cử chỉ kéo, không dùng ScrollView: cần quay vòng và hàng giữa phải luôn đúng giá trị đang chọn.
/// `step` = bước nhảy (phút đi từng 5 như Peek)
private struct PeekWheel: View {
    let count: Int
    var step: Int = 1
    @Binding var value: Int
    let pitch: CGFloat
    let font: CGFloat
    /// Nấc đang đứng (đếm liên tục, không lấy dư — để lò xo chạy thẳng qua mốc 00 thay vì quay ngược cả vòng)
    @State private var base = 0
    @State private var drag: CGFloat = 0
    @State private var ready = false

    private var pos: CGFloat { CGFloat(base) - drag / pitch }
    private func wrap(_ i: Int) -> Int { ((i % count) + count) % count }

    var body: some View {
        let center = Int(pos.rounded())
        ZStack {
            ForEach(-4...4, id: \.self) { o in
                let i = center + o
                let d = CGFloat(i) - pos
                let a = min(abs(d), 1)
                Text(String(format: "%02d", wrap(i) * step))
                    .font(.system(size: font, weight: abs(d) < 0.5 ? .semibold : .medium).monospacedDigit())
                    // Hàng đang chọn (giờ / phút hiện tại của khoản) màu xanh lá
                    .foregroundStyle(Color.primary)
                    .scaleEffect((17 - 5 * a) / 17)
                    .opacity(1 - 0.4 * a)
                    .offset(y: d * pitch)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { v in drag = v.translation.height }
                .onEnded { v in
                    // Đà: lấy điểm dừng dự đoán của cú vuốt, rồi làm tròn về nấc
                    let target = Int((CGFloat(base) - v.predictedEndTranslation.height / pitch).rounded())
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { base = target; drag = 0 }
                    commit(target)
                }
        )
        .onAppear {
            guard !ready else { return }
            base = Int((Double(value) / Double(step)).rounded())
            ready = true
        }
        .sensoryFeedback(.selection, trigger: center)
    }

    private func commit(_ target: Int) {
        // Giờ lẻ (11:03) hiện ở nấc gần nhất (05) mà không bị đổi khi chỉ mở ra xem; chỉ đổi khi cuộn sang nấc khác
        if wrap(target) != wrap(Int((Double(value) / Double(step)).rounded())) { value = wrap(target) * step }
    }
}

/// Xem ảnh hoá đơn to, kèm Chụp lại / Xoá ảnh (khi đang sửa) và Đóng
private struct PhotoViewer: View {
    let image: UIImage?
    let retake: () -> Void
    let remove: () -> Void
    let editable: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image).resizable().scaledToFit().padding(.horizontal, 16)
            }
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    if editable {
                        pill(L("Xoá ảnh")) { remove() }
                        pill(L("Chụp lại")) { retake() }
                    }
                    pill(L("Đóng")) { dismiss() }
                }
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
    }

    private func pill(_ t: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(t).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(Pressable())
    }
}
