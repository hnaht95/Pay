import SwiftUI

/// Màn hình nhập số tiền với bàn phím số lớn (lưu mới / sau khi quét QR / sửa).
struct EntryView: View {
    let mode: EntryMode
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    /// Dựng phim: số đã gõ, ghi chú, danh mục lấy từ khung hình (xem FilmFrame.Entry), không từ trạng thái
    @Environment(\.film) private var film

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
    /// Lần quét QR đầu tiên (chưa từng chọn app ngân hàng): hỏi người dùng dùng app nào trước khi mở
    @State private var choosingBank = false
    @State private var ready = false
    /// Ngày giờ của khoản đang sửa
    @State private var when = Date()
    @State private var pickingDate = false
    /// Đang nhập / sửa. Mở một khoản đã ghi thì ban đầu chỉ xem (bàn phím mờ), bấm Sửa mới sửa
    @State private var editing = true
    @FocusState private var noteFocused: Bool
    @State private var scanningReceipt = false
    /// Nói để điền (nút micro cạnh ô ghi chú): "35k cafe" điền số tiền, ghi chú, danh mục
    @StateObject private var dictation = VoiceListener()
    @State private var dictating = false
    /// Ảnh hoá đơn đính kèm khoản (lưu trong Pay, xem ReceiptPhotos); đổi / xoá rồi thì lưu lại lúc bấm Lưu
    @State private var photo: UIImage?
    @State private var photoChanged = false
    @State private var viewingPhoto = false
    /// Đang ghi tiền vào (công tắc Chi / Vào): hàng chip là danh mục tiền vào
    @State private var income = false
    /// Khoản chi trả bằng thẻ tín dụng (xem Expense.cr): không trừ số dư ngay, cộng vào nợ thẻ
    @State private var credit = false

    /// digits có thể là biểu thức (bàn phím có ÷ × − +, vd 120×3520): số tiền là kết quả
    private var amount: Int { Calc.value(film?.entry?.digits ?? digits) ?? 0 }
    /// Link mở app ngân hàng lấy sẵn qua VietQR (xem BankPrefetch)
    @ObservedObject private var prefetch = BankPrefetch.shared
    private var shownNote: String { film?.entry?.note ?? note }
    private var shownCat: String? { film?.entry.map { $0.cat } ?? cat }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            HStack {
                Text(L("Số tiền")).font(.system(size: 15)).foregroundStyle(.secondary)
                Spacer()
                if canIncome && film == nil {
                    if !income { creditToggle }
                    kindSwitch
                }
            }
            .frame(minHeight: 34)
            .padding(.top, 18)
            HStack(spacing: 4) {
                if income && amount > 0 { AmountArrow(up: true, size: 40).foregroundStyle(Palette.goodInk) }
                Text(amount > 0 ? fmt(amount) : "0")
                    .font(.system(size: 40, weight: .bold)).kerning(-1)
                    .foregroundStyle(amount > 0 ? (income ? AnyShapeStyle(Palette.goodInk) : AnyShapeStyle(.primary)) : AnyShapeStyle(.tertiary))
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                // Đang nhập số tiền: vạch nhấp nháy sau số, như con trỏ của ô nhập
                if editing && !noteFocused, let film {
                    // Phim: nhấp nháy theo thời điểm của khung hình
                    Capsule().fill(Palette.goodInk).frame(width: 3, height: 36).opacity(Int(film.time / 0.55) % 2 == 0 ? 1 : 0)
                } else if editing && !noteFocused {
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
            // Đang gõ phép tính (vd quy đổi ngoại tệ 120 × 3.520): hiện cả biểu thức, số to trong ô là kết quả (như màn khoản chung)
            if film == nil, Calc.isExpr(digits) {
                Text(Calc.pretty(digits) + " = " + fmt(amount))
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, -14)
            }

            Group { if film != nil { filmChips } else { chips } }.padding(.top, 28)

            // Ô ghi chú và bên phải là ô ảnh hoá đơn (cao bằng ô ghi chú)
            HStack(spacing: 10) {
            if film != nil {
                // Phim: ô nhập chữ của iOS không vẽ ra được, thay bằng chữ cùng kiểu
                Text(shownNote.isEmpty ? L("Ghi chú (không bắt buộc)") : shownNote)
                    .font(.system(size: 17)).foregroundStyle(shownNote.isEmpty ? .tertiary : .primary).lineLimit(1)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: Self.noteH, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
            TextField(L("Ghi chú (không bắt buộc)"), text: $note)
                .font(.system(size: 17))
                .focused($noteFocused)
                .submitLabel(.done)
                .padding(.horizontal, 18)
                .frame(minHeight: Self.noteH)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onChange(of: note) { _, v in
                    guard !catPicked else { return }
                    // Đoán lại theo ghi chú đang có, không giữ kết quả của lúc gõ dở (gõ "anh Tuấn mượn" thì "an" từng giữ Ăn uống).
                    // Ghi chú không gợi ra danh mục nào thì về danh mục ban đầu; riêng "Khác" đã học cho ghi chú này
                    // (từ khoá đoán ra danh mục khác mà app vẫn trả "Khác") thì phải chọn đúng "Khác"
                    if income { cat = store.guessIncome(v); return }
                    let g = store.guessCategory(v)
                    cat = g != "khac" || Category.guess(v) != "khac" ? g : baseCat
                }
                // Chạm vào ghi chú cũng là bắt đầu sửa
                .onChange(of: noteFocused) { _, on in if on { withAnimation(.snappy) { editing = true } } }
            }
            micTile
            photoTile
            }
            .padding(.top, 24)

            // Đang gõ ghi chú: ẩn bàn phím số (như màn khoản chung), chỉ còn bàn phím chữ của iOS; chạm ô số tiền thì hiện lại
            if noteFocused && film == nil {
                Spacer(minLength: 0)
            } else {
                keypad.padding(.vertical, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            // Hàng nút sát đáy, cách mép dưới 16 điểm bằng lề hai bên (như hai nút Nhập / Quét QR ở màn hình chính):
            // vùng an toàn dưới 34 điểm, lùi xuống 18
            actions.padding(.bottom, -18)
        }
        .padding(.horizontal, 16)
        // Bàn phím chữ (đang gõ ghi chú) phủ lên bàn phím số và các nút, bố cục đứng yên. Để iOS co vùng an toàn thì nội dung
        // không co nổi tới mức đó: phần đầu trượt lên dưới thanh trạng thái, nút Lưu vẫn chìm dưới bàn phím
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.snappy, value: noteFocused)
        .background(Palette.surface.ignoresSafeArea())
        .onAppear(perform: setup)
        .onAppear {
            if case .scan = mode, film == nil, UserDefaults.standard.string(forKey: "bankApp") == nil {
                Task { try? await Task.sleep(for: .milliseconds(400)); choosingBank = true }
            }
        }
        .sheet(isPresented: $choosingBank) {
            BankChooser { id in store.appId = id; choosingBank = false }
                .presentationDetents([.large])
                .sheetCorners()
        }
        .sheet(isPresented: $pickingDate) {
            DateSheet(when: $when).sheetGrabber()
        }
        .fullScreenCover(isPresented: $scanningReceipt) {
            ReceiptCamera { img in
                scanningReceipt = false
                guard let img else { return }
                Haptic.tap()
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
            CategoryEditor(income: income) { k in cat = k; catPicked = true; chosen = true; withAnimation(.snappy) { editing = true } }
                .environmentObject(store)
                .sheetGrabber()
        }
    }

    // MARK: Phần đầu

    private var head: some View {
        let showWeb = casso && prefetch.state == .loading
        return VStack(spacing: 2) {
            // Tiêu đề ở giữa. Màn mở dạng tấm (không phủ kín màn hình): đóng bằng vuốt xuống như các tấm khác,
            // không có mũi tên quay lại hay vuốt từ mép trái
            Text(title).font(.system(size: 21, weight: .bold)).lineLimit(1)
                .padding(.horizontal, 52)
                .frame(maxWidth: .infinity, minHeight: 46)
            // Khoản đã ghi: ngày giờ nằm trong ô số tiền (chạm để đổi), không lặp lại dưới tiêu đề
            if let sub, !isEdit { Text(sub).font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(1) }
        }
        .opacity(showWeb ? 0 : 1)
        // Khoản quét QR trả qua VietQR (vd ACB): phần đầu cao cố định, hai nội dung thay nhau. Lúc trang VietQR đang lấy
        // sẵn link mở app ngân hàng, trang đó (cả quảng cáo của VietQR) chiếm trọn phần đầu, không khung; xong thì trả lại
        // tiêu đề. Trang dựng to hơn rồi thu 55%: sơ đồ ở trên, quảng cáo (gắn đáy trang) ở dưới, không đè nhau
        .frame(maxWidth: .infinity)
        .frame(height: casso ? Self.cassoH : nil)
        .overlay {
            if showWeb {
                GeometryReader { g in
                    BankPrefetchWeb()
                        .frame(width: g.size.width / Self.cassoZoom, height: g.size.height / Self.cassoZoom)
                        .scaleEffect(Self.cassoZoom, anchor: .topLeading)
                }
                .background(Color.white)
                // Bo đồng tâm với góc tấm (cách mép tấm 16 cả trên lẫn hai bên): khung vuông góc trông như dán đè lên tấm
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: prefetch.state)
        .padding(.top, 8)
    }

    /// Cao phần đầu màn quét QR đi qua VietQR: trang VietQR dựng cao ~189px (sơ đồ + dòng trạng thái ~143px, phần dưới cho quảng
    /// cáo gắn đáy) rồi thu 55% còn 104. Cao hơn thì phía trên trống nhiều khi trang xong chỉ còn tiêu đề, bàn phím bên dưới chật
    private static let cassoH: CGFloat = 104
    private static let cassoZoom: CGFloat = 0.55

    /// Màn xác nhận khoản quét QR, app ngân hàng đi qua VietQR (lấy sẵn link được)
    private var casso: Bool {
        if case .scan = mode, film == nil, BankLauncher.viaCasso(store.bankApp), !UserDefaults.standard.bool(forKey: "acbScanMode") { return true }
        return false
    }

    /// Chiều cao ô ghi chú, cũng là cạnh ô ảnh hoá đơn bên cạnh
    private static let noteH: CGFloat = 54

    /// Ô ảnh hoá đơn cạnh ô ghi chú, vuông, cao bằng ô ghi chú: có ảnh thì hiện ảnh (chạm để xem to / chụp lại / xoá),
    /// chưa có thì icon camera (chạm để chụp hoặc chọn ảnh). Màn quét QR / mã lạ không có ô này
    @ViewBuilder private var photoTile: some View {
        if isNewEntry || isEdit || isScan {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            Button { if photo != nil { viewingPhoto = true } else if Pro.shared.allow(.photos) { scanningReceipt = true } } label: {
                Color.primary.opacity(0.05)
                    .overlay {
                        if let photo {
                            Image(uiImage: photo).resizable().scaledToFill()
                        } else {
                            Image(systemName: "camera.aperture").font(.system(size: 22, weight: .medium)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: Self.noteH, height: Self.noteH)   // ô vuông, hợp với icon chụp
                .clipShape(shape)
                .contentShape(shape)
            }
            .buttonStyle(Pressable())
            .accessibilityLabel(photo != nil ? L("Ảnh hoá đơn") : L("Chụp hoá đơn"))
        }
    }

    /// Nút micro cạnh ô ghi chú (cùng cỡ ô ảnh): chạm để nói "35k cafe", ngừng nói là điền số tiền, ghi chú, danh mục; chạm lần
    /// nữa khi đang nghe là dừng và điền phần đã nghe. Đang nghe: nền đỏ nhạt, chấm micro nhấp nháy, ô ghi chú hiện chữ đang nghe
    @ViewBuilder private var micTile: some View {
        if (isNewEntry || isEdit || isScan) && film == nil {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            Button { dictating ? dictation.finish() : startDictation() } label: {
                (dictating ? Palette.danger.opacity(0.15) : Color.primary.opacity(0.05))
                    .overlay {
                        Image(systemName: dictating ? "waveform" : "mic.fill").font(.system(size: 20, weight: .medium))
                            .foregroundStyle(dictating ? Palette.danger : .secondary)
                            .symbolEffect(.variableColor.iterative, isActive: dictating)
                    }
                    .frame(width: Self.noteH, height: Self.noteH)
                    .clipShape(shape)
                    .contentShape(shape)
            }
            .buttonStyle(Pressable())
            .accessibilityLabel(dictating ? L("Dừng nghe") : L("Nói để điền"))
            .onChange(of: dictation.text) { _, t in if dictating, !t.isEmpty { liveDictation(t) } }
            .onChange(of: dictation.phase) { _, p in
                if case .failed(let why) = p { dictating = false; store.showError(why) }
                if p == .denied { dictating = false; store.showError(L("Cần quyền micro")) }
            }
            .onDisappear { dictation.cancel() }
        }
    }

    private func startDictation() {
        noteFocused = false
        Haptic.tap()
        withAnimation(.snappy) { editing = true; dictating = true }
        dictation.onFinish = { said in applyDictation(said) }
        Task {
            await dictation.start()
            // Không bật được micro (thiếu quyền, lỗi): phase đã báo ở onChange; còn lại mà vẫn không nghe thì thôi
            if dictation.phase != .listening && dictating { if case .idle = dictation.phase { dictating = false } }
        }
    }

    /// Đang nói: đọc được số tiền thì số hiện ngay ở ô số tiền, ô ghi chú chỉ còn phần chữ ("35k cafe" → 35.000 · "cafe"),
    /// không để cả câu nằm ở ghi chú rồi mới nhảy lên khi nói xong. Chưa ra số tiền thì chưa đụng ô số tiền
    private func liveDictation(_ t: String) {
        if let q = QuickParse.spoken(t) ?? QuickParse.expense(t) {
            digits = String(q.amount)
            note = q.note
        } else {
            note = t
        }
    }

    /// Câu vừa nói: có số tiền thì điền số tiền + ghi chú (+ danh mục đoán theo ghi chú, tiền vào nếu có từ như "lương"); không
    /// đọc được số tiền thì cả câu vào ghi chú
    private func applyDictation(_ said: String) {
        withAnimation(.snappy) { dictating = false }
        let t = said.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        guard let q = QuickParse.spoken(t) ?? QuickParse.expense(t) else { note = t; return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.snappy) {
            digits = String(q.amount)
            if !catPicked && canIncome {
                let k = store.guessEntry(q.note)
                income = Category.isIncome(k)
                note = q.note
                cat = k
            } else {
                note = q.note
            }
        }
    }

    /// Ghi được tiền vào: nhập mới hoặc sửa (quét QR là trả tiền, luôn là khoản chi)
    private var canIncome: Bool { isNewEntry || isEdit }

    /// Công tắc Chi / Vào cạnh chữ "Số tiền". Đổi loại thì danh mục đoán lại theo ghi chú trong bộ danh mục của loại đó
    private var kindSwitch: some View {
        HStack(spacing: 2) {
            ForEach([false, true], id: \.self) { inc in
                let on = income == inc
                Button {
                    guard !on else { return }
                    Haptic.select()
                    withAnimation(.snappy(duration: 0.25)) {
                        income = inc
                        // Chưa có ghi chú: tiền vào chọn sẵn Lương (hay gặp nhất). Danh mục chọn sẵn đứng đầu hàng chip
                        cat = inc ? (trimmed.isEmpty ? Category.income[0].k : store.guessIncome(trimmed)) : store.guessCategory(trimmed)
                        catPicked = false; chosen = false; leadCat = cat
                        editing = true
                    }
                } label: {
                    Text(inc ? L("Thu") : L("Chi")).font(.system(size: 15, weight: .semibold))
                        .frame(width: 52, height: 30)
                        .foregroundStyle(on ? (inc ? Color.white : Palette.ctaInk) : Color.secondary)
                        .background { if on { Capsule().fill(inc ? Palette.goodInk : Palette.cta) } }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Palette.pill, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Loại khoản"))
    }

    /// Trả bằng thẻ tín dụng: viên bật / tắt cạnh công tắc Chi / Thu, cùng cao
    private var creditToggle: some View {
        Button {
            Haptic.select()
            withAnimation(.snappy(duration: 0.2)) { credit.toggle(); editing = true }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "creditcard.fill").font(.system(size: 13, weight: .semibold))
                Text(L("Thẻ tín dụng")).font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 12).frame(height: 34)
            .foregroundStyle(credit ? Palette.ctaInk : Color.secondary)
            .background(credit ? Palette.cta : Palette.pill, in: Capsule())
        }
        .buttonStyle(Pressable())
        .accessibilityLabel(L("Trả bằng thẻ tín dụng"))
        .accessibilityAddTraits(credit ? .isSelected : [])
    }

    /// Nhập mới (tay hoặc từ hoá đơn)
    private var isNewEntry: Bool {
        switch mode { case .new, .receipt: return true; default: return false }
    }

    /// Màn trả sau khi quét QR / dán STK: cũng có micro và ảnh hoá đơn cạnh ô ghi chú như màn nhập
    private var isScan: Bool {
        if case .scan = mode { return true }
        return false
    }

    private var isEdit: Bool {
        switch mode { case .edit, .editNow: return true; default: return false }
    }

    private var title: String {
        switch mode {
        case .new(let c) where c != nil && Category.isIncome(c) == income: return "\(Category.get(c).icon) \(Category.get(c).name)"
        case .new, .receipt: return income ? L("Lưu khoản thu") : L("Lưu khoản chi")
        case .scan(let q): return L("Trả cho %@", q.name.isEmpty ? L("TK %@", q.acct ?? "") : q.name)
        case .raw: return L("Mã QR không phải VietQR")
        case .edit, .editNow: return income ? L("Sửa khoản thu") : L("Sửa khoản chi")
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
                    let all = income ? Category.income : Category.all
                    let ordered = all.filter { $0.k == leadCat } + all.filter { $0.k != leadCat }
                    ForEach(ordered) { c in
                        Button { if cat != c.k { Haptic.select() }; cat = c.k; catPicked = true; chosen = true; withAnimation(.snappy) { editing = true } } label: {
                            let on = cat == c.k
                            // Đang chọn: nền màu danh mục (như ô ở màn hình chính); chưa chọn: nền xám rất nhạt
                            HStack(spacing: 8) {
                                CategoryBadge(c: c, side: 36, radius: 10, iconSize: 22)
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
                    Button { if (income ? Category.incomeCustom : Category.custom).count < Pro.freeCategories || Pro.shared.allow(.categories) { addingCat = true } } label: {
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
            .scrollClipDisabled()   // chip nhoè ở mép lan ra ngoài khung, không bị cắt vạch trên / dưới
            .padding(.horizontal, -18)
            // Hai mép mờ dần khi cuộn: chip đi ra mép thì tan vào nền thay vì bị cắt thẳng
            // Chỉ mờ phía còn chip bị che: đang ở đầu hàng thì mép trái không mờ, cuộn hết thì mép phải không mờ
            .modifier(ChipEdges(fade: $chipFade))

            // Sau khi setup() gán xong `cat` (onAppear của hàng chip chạy trước, lúc đó `cat` còn nil): đưa nó lên đầu hàng
            // (đứng đầu rồi nên hàng ở vị trí ban đầu là thấy, không cuộn: cuộn tới chip thì mất lề trái)
            .onChange(of: ready) { _, _ in leadCat = cat }
        }
    }

    /// Phim: hàng chip không cuộn (vùng cuộn và hiệu ứng nhoè mép không vẽ ra được), danh mục đang chọn đứng đầu
    private var filmChips: some View {
        let all = Category.all, lead = shownCat
        let ordered = all.filter { $0.k == lead } + all.filter { $0.k != lead }
        return HStack(spacing: 8) {
            ForEach(ordered) { c in
                let on = shownCat == c.k
                HStack(spacing: 8) {
                    CategoryBadge(c: c, side: 36, radius: 10, iconSize: 22)
                    Text(c.name).font(.system(size: 17, weight: on ? .semibold : .medium))
                }
                .padding(.leading, 6).padding(.trailing, 16).padding(.vertical, 6)
                .foregroundStyle(on ? c.ink : Color.primary)
                .background(on ? c.color : Color.primary.opacity(0.05), in: Capsule())
            }
        }
        // minWidth 0: hàng chip dài hơn màn hình không được kéo giãn cả màn (cắt ở mép phải như chip trôi ra ngoài)
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).clipped()
    }

    // MARK: Bàn phím số

    private var keypad: some View {
        NumberPad(digits: $digits, lit: film?.entry?.key, ops: true) { noteFocused = false }
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
                    BigButton(title: L("Huỷ"), icon: "", primary: false, tint: BigButton.cancelTint) { dismiss() }
                    BigButton(title: L("Lưu"), icon: "", primary: true) {
                        guard amount > 0 else { return }
                        learn(); store.add(amount: amount, note: trimmed, cat: finalCat, credit: credit && !income)
                        if let photo, let id = store.all.last?.id { ReceiptPhotos.save(photo, id: id) }
                        dismiss()
                    }
                    .opacity(amount == 0 ? 0.55 : 1)
                    .animation(.easeInOut(duration: 0.25), value: amount == 0)
                }
            case .scan(let q):
                let app = store.bankApp
                let prefetching = film == nil && BankLauncher.viaCasso(app) && amount > 0 && !UserDefaults.standard.bool(forKey: "acbScanMode")
                VStack(spacing: 10) {
                // Hai nút cùng một hàng, cùng cao: Lưu (chỉ ghi) bên trái, Lưu & mở app ngân hàng bên phải (rộng hơn)
                HStack(spacing: 12) {
                    Button { saveScan(q); dismiss() } label: {
                        Text(L("Lưu")).font(.system(size: 21, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 56 + BigButton.inset * 2)
                            .foregroundStyle(.primary)
                            .background(Palette.pill, in: Capsule())
                    }
                    .buttonStyle(Pressable())
                    .disabled(amount == 0)
                    .opacity(amount == 0 ? 0.55 : 1)
                    .frame(width: 104)
                    primary(L("Lưu & mở Bank")) {
                        saveScan(q); dismiss()
                        let a = amount
                        Task { try? await Task.sleep(for: .milliseconds(350)); await BankLauncher.open(app, qr: q, amount: a) }
                    }
                    .filmPressed(film?.pressed["bank"] ?? 0)
                }
                }
                // Lấy sẵn link có chữ ký khi số tiền đã đứng yên một nhịp (gõ tiếp thì lấy lại). Gắn ở khối luôn hiện: khung lấy sẵn
                // lúc chưa chạy là EmptyView, gắn vào đó thì việc này không bao giờ chạy
                .task(id: prefetching ? "\(app.id)|\(amount)" : "") {
                    guard prefetching else { return }
                    try? await Task.sleep(for: .milliseconds(700))
                    guard !Task.isCancelled else { return }
                    prefetch.start(app: app, qr: q, amount: amount)
                }
            case .edit(var e), .editNow(var e):
                // Huỷ và Sửa / Lưu thay đổi cùng một hàng. Xoá khoản: vuốt trái ở danh sách hoặc nhấn giữ
                GlassGroup {
                    HStack(spacing: 12) {
                        BigButton(title: L("Huỷ"), icon: "", primary: false, tint: BigButton.cancelTint) { dismiss() }
                        if editing {
                            BigButton(title: L("Lưu"), icon: "", primary: true) {
                                guard amount > 0 else { return }
                                e.a = amount; e.n = trimmed; e.c = finalCat; e.cr = credit && !income ? true : nil
                                // Chỉ ghi lại thời điểm khi người dùng thật sự đổi (so theo phút), kẻo lệch mili giây làm xáo thứ tự
                                if abs(when.timeIntervalSince(e.date)) >= 60 { e.t = when.timeIntervalSince1970 * 1000 }
                                learn(); store.update(e)
                                if photoChanged { if let photo { ReceiptPhotos.save(photo, id: e.id) } else { ReceiptPhotos.remove(e.id) } }
                                dismiss()
                            }
                            .opacity(amount == 0 ? 0.55 : 1)
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
            Text(label).font(.system(size: 21, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 16)   // tên ngân hàng dài (VietinBank iPay) không chạm mép nút
                .frame(maxWidth: .infinity, minHeight: 56 + BigButton.inset * 2)
                .foregroundStyle(Palette.ctaInk)
                .background(Palette.cta, in: Capsule())
        }
        .buttonStyle(Pressable())
        .disabled(amount == 0)
        .opacity(amount == 0 ? 0.55 : 1)
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
        .opacity(amount == 0 ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.25), value: amount == 0)   // sáng / mờ chuyển dần, không bật tắt
    }

    // MARK: Lưu

    private var trimmed: String { note.trimmingCharacters(in: .whitespaces) }
    private var finalCat: String { cat ?? (income ? store.guessIncome(trimmed) : store.guessCategory(trimmed)) }

    /// Tự học: lần sau gõ / nói / quét đúng tên này thì app chọn sẵn danh mục người dùng đã chọn.
    private func learn() {
        if chosen { store.learnCategory(trimmed, finalCat) }
    }

    private func saveScan(_ q: VietQR) {
        learn()
        let key = q.memoKey
        let old = key.flatMap { store.memo[$0] }
        let name = !trimmed.isEmpty ? trimmed : (!q.name.isEmpty ? q.name : "\(q.bank) \(q.acct ?? "")")
        // Tên nhớ cho tài khoản này: chỉ khi người dùng tự gõ. Nội dung chuyển khoản của mã QR ("DH 12345") là của riêng lần trả
        // này, nhớ thì lần sau quét cùng tài khoản lại hiện sẵn nội dung cũ
        let typed = !trimmed.isEmpty && trimmed != q.purpose.trimmingCharacters(in: .whitespaces)
        if let key { store.remember(key, Memo(c: finalCat, n: typed ? trimmed : old?.n)) }
        store.add(amount: amount, note: name, cat: finalCat, acct: key)
        if let photo, let id = store.all.last?.id { ReceiptPhotos.save(photo, id: id) }
    }

    private func setup() {
        guard !ready else { return }
        ready = true
        switch mode {
        case .new(let c):
            cat = c; catPicked = c != nil; income = Category.isIncome(c)
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
            digits = String(e.a); note = e.n ?? ""; cat = e.c; catPicked = true; when = e.date; income = e.isIncome; credit = e.isCredit
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
    /// Phim: phím đang được nhấn (sáng nền như khi bấm thật)
    var lit: String? = nil
    /// Có cột phép tính ÷ × − + (vd quy đổi ngoại tệ: 120 × 3520). digits khi đó là cả biểu thức, giá trị xem Calc.value
    var ops = false
    /// Gọi mỗi lần bấm phím (vd bỏ chọn ô ghi chú)
    var onPress: () -> Void = {}

    var body: some View {
        let rows = ops ? [["1", "2", "3", "÷"], ["4", "5", "6", "×"], ["7", "8", "9", "−"], ["000", "0", "del", "+"]]
                       : [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["000", "0", "del"]]
        VStack(spacing: 4) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { k in
                        Button { press(k) } label: {
                            Group {
                                if k == "del" { Image(systemName: "delete.left").font(.system(size: 26)) }
                                else if Calc.ops.contains(k) { Text(k).font(.system(size: 30, weight: .medium)).foregroundStyle(Palette.goodInk) }
                                else { Text(k).font(.system(size: k == "000" ? 26 : 32, weight: .medium)) }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .background(lit == k ? Palette.pill : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(KeyStyle())
                        // Nhấn giữ phím xoá: xoá hết số đang nhập. Chỉ gắn cử chỉ nhấn giữ cho phím xoá: phím số không có cử chỉ nào
                        // chen vào, gõ nhanh vẫn ăn từng phím
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in clearAll() }, including: k == "del" ? .all : .subviews)
                        .accessibilityLabel(k == "del" ? L("Xoá") : k)
                    }
                }
            }
        }
    }

    private func clearAll() {
        guard !digits.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onPress()
        withAnimation(.snappy(duration: 0.15)) { digits = "" }
    }

    private func press(_ k: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onPress()
        withAnimation(.snappy(duration: 0.15)) {
            if k == "del" { digits = String(digits.dropLast()); return }
            // Phép tính: chỉ sau một số; bấm phép khác ngay sau phép tính thì thay phép cũ
            if Calc.ops.contains(k) {
                guard let last = digits.last else { return }
                if Calc.ops.contains(String(last)) { digits = String(digits.dropLast()) + k }
                else if digits.count < 30 { digits += k }
                return
            }
            // Số mới (đầu chuỗi hoặc ngay sau phép tính) không bắt đầu bằng 0; mỗi số tối đa 12 chữ số
            let current = digits.split(omittingEmptySubsequences: false, whereSeparator: { Calc.ops.contains(String($0)) }).last ?? ""
            if current.isEmpty && (k == "0" || k == "000") { return }
            if current.count + k.count <= 12 && digits.count + k.count <= 30 { digits += k }
        }
    }
}

/// Biểu thức gõ trên bàn phím số có phép tính: "120×3520+15000". Nhân chia trước, cộng trừ sau; kết quả làm tròn tới đồng
enum Calc {
    static let ops: Set<String> = ["+", "−", "×", "÷"]

    /// Có phép tính trong chuỗi (để hiện dòng biểu thức nhỏ)
    static func isExpr(_ s: String) -> Bool { s.contains { ops.contains(String($0)) } }

    /// Giá trị của biểu thức, không âm; phép tính đang gõ dở ở cuối thì bỏ qua. Chuỗi rỗng / chia cho 0: nil
    static func value(_ s: String) -> Int? {
        var t = s
        while let l = t.last, ops.contains(String(l)) { t.removeLast() }
        guard !t.isEmpty else { return nil }
        var nums: [Double] = [], opsSeen: [Character] = [], cur = ""
        for ch in t {
            if ops.contains(String(ch)) { guard let v = Double(cur) else { return nil }; nums.append(v); opsSeen.append(ch); cur = "" }
            else if ch.isNumber { cur.append(ch) }
        }
        guard let v = Double(cur) else { return nil }
        nums.append(v)
        // Nhân chia trước
        var terms: [Double] = [nums[0]], signs: [Character] = []
        for (i, op) in opsSeen.enumerated() {
            let n = nums[i + 1]
            switch op {
            case "×": terms[terms.count - 1] *= n
            case "÷": guard n != 0 else { return nil }; terms[terms.count - 1] /= n
            default: terms.append(n); signs.append(op)
            }
        }
        var total = terms[0]
        for (i, op) in signs.enumerated() { total += op == "+" ? terms[i + 1] : -terms[i + 1] }
        guard total.isFinite, total < 1e15 else { return nil }
        return max(0, Int(total.rounded()))
    }

    /// Biểu thức để đọc: số có dấu chấm ngăn hàng nghìn, phép tính có cách hai bên ("120 × 3.520")
    static func pretty(_ s: String) -> String {
        var out = "", cur = ""
        func flush() { if let v = Int(cur) { out += fmt(v) } else { out += cur }; cur = "" }
        for ch in s {
            if ops.contains(String(ch)) { flush(); out += " \(ch) " } else { cur.append(ch) }
        }
        flush()
        return out
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
                let showsToday = !isThisWeek
                Button { jumpToToday() } label: {
                    Text(L("Hôm nay")).font(.system(size: 15, weight: .medium))
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
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.75), value: isThisWeek)
            // Dải ngày vuốt ngang liền một mạch như Thống kê (không mũi tên): từ ngày cũ nhất cần tới hôm nay, mở ra ở ngày
            // đang chọn; 7 viên vừa một màn, cuộn dừng đúng viên. Tiêu đề tháng theo ngày đang ở giữa dải
            // Danh sách ngày và tổng chi từng ngày tính một lần lúc mở (như Thống kê): tính lại mỗi lần cuộn thì vuốt bị giật
            // Giống dải ở Thống kê: dải tràn tới hai mép tấm, lề cuộn 20 (bằng lề tấm), đúng 7 cột vừa khít giữa hai lề,
            // thả tay luôn dừng cân hai bên; viên thừa trong lề nhoè rồi tan
            let w = max(0, (rowW - 40 - 6 * 6) / 7)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 6) {
                    ForEach(days, id: \.self) { d in
                        stripDay(d, spent: byDay[d] ?? 0, top: topSpent).frame(width: w).softScrollEdge(zone: 18, space: "dateStrip", width: rowW).id(d)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centerDay, anchor: .center)
            .defaultScrollAnchor(.trailing)
            .scrollClipDisabled()
            .frame(height: 84 + 22)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowW = $0 }
            .coordinateSpace(.named("dateStrip"))
            .modifier(SevenColumns(margin: 18))
            .padding(.horizontal, -20)
            .onChange(of: centerDay) { if let c = centerDay, !cal.isDate(c, equalTo: month, toGranularity: .month) { month = c } }
            // Giờ : phút, cùng khung xám bo góc với dải tuần; hai bánh xe cuộn dọc (phút nhảy 5), hàng giữa là giờ đang chọn
            HStack(spacing: 0) {
                // Đồng hồ báo thức (Tabler alarm-minus, bản đặc) trước nhãn
                HStack(spacing: 8) {
                    Image("icon-alarm").renderingMode(.template).resizable().frame(width: 22, height: 22)
                    Text(L("Thời gian chi")).font(.system(size: 17, weight: .medium))
                }
                .foregroundStyle(Color.primary.opacity(0.6))
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    PeekWheel(count: 24, value: Binding(get: { cal.component(.hour, from: when) }, set: { setTime(hour: $0) }),
                              pitch: 30, font: 20)
                        .frame(width: 40)
                    Text(":").font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.45))
                    PeekWheel(count: 12, step: 5, value: Binding(get: { cal.component(.minute, from: when) }, set: { setTime(minute: $0) }),
                              pitch: 30, font: 20)
                        .frame(width: 40)
                }
                .frame(width: 120, height: 96)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(light: 0xFFFFFF, dark: 0x2C2C2E)).frame(height: 34))
                .mask {
                    LinearGradient(stops: [.init(color: .black.opacity(0.08), location: 0), .init(color: .black, location: 0.35),
                                           .init(color: .black, location: 0.65), .init(color: .black.opacity(0.08), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .clipped()
            }
            .padding(.leading, 20).padding(.trailing, 12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            // Huỷ / Lưu ở đáy, to bằng hai nút Nhập / Quét QR của màn hình chính. Huỷ trả ngày giờ về như lúc mở
            HStack(spacing: 12) {
                BigButton(title: L("Huỷ"), icon: "", primary: false, tint: BigButton.cancelTint) { when = original ?? when; dismiss() }
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
        .onAppear {
            month = when; if original == nil { original = when }
            days = stripDays
            byDay = Store.shared.items.reduce(into: [:]) { m, e in m[cal.startOfDay(for: e.date), default: 0] += e.a }
            topSpent = max(byDay.values.max() ?? 1, 1)
            centerDay = cal.startOfDay(for: when)
        }
    }

    /// Ngày đang nằm giữa dải (cuộn tới đâu, tiêu đề tháng theo đó)
    @State private var centerDay: Date?
    @State private var days: [Date] = []
    @State private var byDay: [Date: Int] = [:]
    @State private var topSpent = 1
    /// Hôm nay đang nằm trong 7 viên đang thấy (viên giữa cách hôm nay không quá 3 ngày): khỏi hiện nút "Hôm nay"
    private var isThisWeek: Bool {
        let c = centerDay ?? cal.startOfDay(for: when)
        return (cal.dateComponents([.day], from: c, to: cal.startOfDay(for: Date())).day ?? 0) <= 3
    }

    /// Các ngày trên dải: từ khoản chi cũ nhất (ít nhất 120 ngày trước, và luôn có ngày đang chọn) tới hôm nay
    private var stripDays: [Date] {
        let today = cal.startOfDay(for: Date())
        let oldest = Store.shared.items.min(by: { $0.t < $1.t }).map { cal.startOfDay(for: $0.date) } ?? today
        let from = min(oldest, cal.startOfDay(for: when), cal.date(byAdding: .day, value: -120, to: today)!)
        let n = (cal.dateComponents([.day], from: from, to: today).day ?? 0) + 1
        return (0..<n).map { cal.date(byAdding: .day, value: $0, to: from)! }
    }


    /// Dải tuần cùng kiểu dải ngày ở Thống kê: chữ thứ nằm trên viên; trong viên số ngày ở trên, lớp xám dâng từ đáy
    /// theo mức chi của ngày (căn bậc hai, so với ngày chi nhiều nhất tuần). Ngày chọn viên đen, hôm nay số xanh lá
    private static let pillCard = Color(light: 0xF2F2F4, dark: 0x2C2C2E)
    private static let pillInk = Color(light: 0x1C1C1E, dark: 0xF2F2F2)
    private static let pillInkText = Color(light: 0xFFFFFF, dark: 0x111114)
    private static let todayTint = Color(light: 0x3FA65A, dark: 0x7FD08B)

    private func stripDay(_ d: Date, spent: Int, top: Int) -> some View {
        let on = cal.isDate(d, inSameDayAs: when), today = cal.isDateInToday(d), future = d > Date()
        let r = min(sqrt(Double(spent) / Double(top)), 1)
        let names = Lang.isEnglish ? ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"] : ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]
        return Button { pick(d) } label: {
            VStack(spacing: 6) {
                Text(names[(cal.component(.weekday, from: d) + 5) % 7])
                    .font(.system(size: 11, weight: on ? .bold : .medium))
                    .foregroundStyle(Color.primary.opacity(on ? 0.75 : 0.4))
                VStack(spacing: 0) {
                    Text("\(cal.component(.day, from: d))")
                        .font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(on ? Self.pillInkText : today ? Self.todayTint : Color.primary.opacity(0.8))
                        .frame(height: 24)
                        .padding(.top, 8)
                    GeometryReader { g in
                        // Ngày / tháng không chi vẫn có khối thấp nhất, rất mờ (không để trống viên)
                        Group {
                            // Thấp nhất 18: thấp hơn thì lớp chỉ còn một vệt mỏng cong theo đáy viên, nhìn như lỗi vẽ
                            let h = max(18, g.size.height * r)
                            UnevenRoundedRectangle(topLeadingRadius: min(8, h / 2), topTrailingRadius: min(8, h / 2), style: .continuous)
                                .fill(on ? Self.pillInkText.opacity(spent > 0 ? 0.22 : 0.08) : Color.primary.opacity(spent > 0 ? 0.09 : 0.035))
                                .frame(height: h)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                    }
                    .padding(4)
                }
                .frame(maxWidth: .infinity).frame(height: 84)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(on ? Self.pillInk : Self.pillCard))
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(Pressable())
        .opacity(future ? 0.3 : 1).disabled(future)
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
            Text(L("Bây giờ")).font(.system(size: 17, weight: .semibold))
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
        Haptic.select()
        withAnimation(.snappy) { centerDay = cal.startOfDay(for: Date()) }
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
extension View {
    /// Một phần tử trong dải cuộn ngang: phần nằm sát mép dải nhoè dần theo từng điểm ảnh như mép cuộn mềm của iOS
    /// (shader EdgeBlur.metal). Độ nhoè tính theo vị trí trên dải nên vùng nhoè liền mạch qua các cột kề nhau.
    /// (Không áp lên cả ScrollView được: hiệu ứng lớp không vẽ được vùng cuộn của UIKit)
    /// `space` + `width`: đo theo khung dải đặt tên (dải nằm trong tấm nổi, tấm lùi vào so với mép màn hình); bỏ trống thì
    /// đo theo mép màn hình
    func softScrollEdge(zone: CGFloat = 36, radius: CGFloat = 6, space: String? = nil, width: CGFloat? = nil) -> some View {
        let screenW = UIScreen.main.bounds.width
        return visualEffect { content, g in
            let x = space.map { g.frame(in: .named($0)).minX } ?? g.frame(in: .global).minX
            return content.layerEffect(ShaderLibrary.edgeBlur(.float(width ?? screenW), .float(zone), .float(radius), .float2(1, 1), .float(x)),
                                       maxSampleOffset: CGSize(width: radius * 1.5, height: radius * 1.5))
        }
    }
}

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
    /// Nấc vừa rung gần nhất
    @State private var tick = 0

    private var pos: CGFloat { CGFloat(base) - drag / pitch }
    private func wrap(_ i: Int) -> Int { ((i % count) + count) % count }

    var body: some View {
        let center = Int(pos.rounded())
        ZStack {
            ForEach(-4...4, id: \.self) { o in
                let i = center + o
                let d = CGFloat(i) - pos
                // Ghi rõ kiểu số (CGFloat cho hình, Double cho độ mờ): để trình biên dịch tự đoán thì Xcode 26.3 báo mơ hồ
                let a: CGFloat = min(abs(d), 1)
                let face: Font = Font.system(size: font, weight: abs(d) < 0.5 ? .semibold : .medium).monospacedDigit()
                let scale: CGFloat = (17 - 5 * a) / 17
                let fade: Double = 1 - 0.4 * Double(a)
                Text(String(format: "%02d", wrap(i) * step))
                    .font(face)
                    // Hàng đang chọn (giờ / phút hiện tại của khoản) màu xanh lá
                    .foregroundStyle(Color.primary)
                    .scaleEffect(scale)
                    .opacity(fade)
                    .offset(y: d * pitch)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { v in
                    drag = v.translation.height
                    // Rung từng nấc lúc kéo qua (như bánh xe giờ của iOS); sensoryFeedback theo `center` không chạy ổn trong cử chỉ
                    let c = Int((CGFloat(base) - drag / pitch).rounded())
                    if c != tick { tick = c; Haptic.select() }
                }
                .onEnded { v in
                    // Đà: lấy điểm dừng dự đoán của cú vuốt, rồi làm tròn về nấc
                    let target = Int((CGFloat(base) - v.predictedEndTranslation.height / pitch).rounded())
                    if target != tick { tick = target; Haptic.select() }   // vuốt có đà: thêm một nhịp khi dừng ở nấc mới
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { base = target; drag = 0 }
                    commit(target)
                }
        )
        .onAppear {
            guard !ready else { return }
            base = Int((Double(value) / Double(step)).rounded())
            tick = base
            ready = true
        }
    }

    private func commit(_ target: Int) {
        // Giờ lẻ (11:03) hiện ở nấc gần nhất (05) mà không bị đổi khi chỉ mở ra xem; chỉ đổi khi cuộn sang nấc khác
        if wrap(target) != wrap(Int((Double(value) / Double(step)).rounded())) { value = wrap(target) * step }
    }
}

/// Xem ảnh hoá đơn to, kèm Chụp lại / Xoá ảnh (khi đang sửa) và Đóng
struct PhotoViewer: View {
    let image: UIImage?
    let retake: () -> Void
    let remove: () -> Void
    let editable: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))   // bo góc như các thẻ trong app
                    .padding(.horizontal, 16)
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

/// Chọn app ngân hàng (lần quét QR đầu tiên): app mở sẵn người nhận + số tiền xếp trước, app chỉ mở được xếp sau.
/// Chọn xong là nhớ luôn, đổi lại trong Cài đặt › Thanh toán
struct BankChooser: View {
    let pick: (String) -> Void

    var body: some View {
        NavigationStack {
            BlurForm {
                Section {
                    ForEach(BankData.apps.filter(\.fill)) { row($0) }
                } header: {
                    header(L("Mở sẵn người nhận + số tiền"),
                           L("Quét xong, Payso mở thẳng màn chuyển tiền trong app ngân hàng, đã điền sẵn người nhận và số tiền. Bạn chỉ cần xác nhận."))
                }
                Section {
                    ForEach(BankData.apps.filter { !$0.fill }) { row($0) }
                } header: {
                    header(L("Chỉ mở app (quét lại QR)"),
                           L("Các ngân hàng này chưa cho app khác điền sẵn thông tin chuyển tiền. Payso ghi khoản chi rồi mở app ngân hàng, bạn quét lại mã QR trong đó để trả."))
                } footer: {
                    Text(L("Đổi lại bất cứ lúc nào trong Cài đặt › Thanh toán."))
                }
            }
            .softTopEdge(fade: Color(.systemGroupedBackground))
            .screenTitle(L("Bạn dùng app ngân hàng nào?"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Tên nhóm và lời giải thích ngay dưới, nằm trên danh sách ngân hàng của nhóm
    private func header(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.primary)
            Text(detail).font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
        }
        .textCase(nil)
        .padding(.bottom, 4)
    }

    private func row(_ a: BankApp) -> some View {
        Button { Haptic.select(); pick(a.id) } label: {
            Text(a.name).foregroundStyle(Color.primary).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
    }
}
