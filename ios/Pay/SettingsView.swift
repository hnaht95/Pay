import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var confirmErase = false
    @State private var syncing = false
    @State private var jsonURL: URL?
    @State private var csvURL: URL?
    /// Số đang kéo trên thanh ngân sách (chưa lưu), để dòng "Còn ..." bên dưới chạy theo
    @State private var budgetDraft: Int?
    @State private var typingBudget = false
    @State private var budgetText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section { summary }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                budgetSection
                recurringSection
                cloudSection
                bankSection

                Section {
                    NavigationLink { QuickAccessHelp() } label: {
                        row("Widget, nút Tác vụ, Phím tắt", "bolt.fill", .orange)
                    }
                } header: {
                    Text("Truy cập nhanh")
                }

                dataSection

                Section {
                    LabeledContent { Text(version).foregroundStyle(.secondary) } label: {
                        row("Phiên bản", "info.circle.fill", .gray)
                    }
                } footer: {
                    Text("Pay — ghi chi tiêu tối giản: gõ 35k cafe hoặc quét VietQR.")
                }
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } }
            }
        }
        // File sao lưu có cả khoản định kỳ và danh mục đã học: đổi gì cũng làm lại
        .task(id: [store.items.hashValue, store.rules.hashValue, store.memo.hashValue]) { jsonURL = store.exportJSON(); csvURL = store.exportCSV() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { store.importBackup(from: url) }
        }
        .confirmationDialog("Xoá tất cả khoản chi?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Xoá tất cả", role: .destructive) { store.eraseAll() }
        } message: {
            Text((store.cloudOn ? "Các máy khác đang đồng bộ iCloud cũng sẽ bị xoá." : "Không hoàn tác được.")
                 + (store.rules.values.contains(where: \.on) ? " Khoản định kỳ cũng dừng tự ghi." : "") + " Nên sao lưu trước.")
        }
        .alert("Ngân sách tháng", isPresented: $typingBudget) {
            TextField("Ví dụ 8.000.000", text: $budgetText).keyboardType(.numberPad)
            Button("Huỷ", role: .cancel) {}
            Button("Lưu") {
                let digits = budgetText.filter(\.isNumber)
                if digits.isEmpty { store.budget = 0 } else if let v = Int(digits.prefix(12)) { store.budget = v }
            }
        } message: {
            Text("Số tiền tiêu mỗi tháng. Để trống là bỏ ngân sách.")
        }
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 24) }
    }

    // MARK: Tổng quan

    private var summary: some View {
        let now = Date()
        let month = store.monthItems(now)
        return HStack(spacing: 14) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Palette.ctaInk)
                .frame(width: 60, height: 60)
                .background(Palette.cta, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("Pay").font(.system(size: 22, weight: .bold))
                Text("Tháng \(Calendar.current.component(.month, from: now)): \(fmt(month.reduce(0) { $0 + $1.a }))đ · \(month.count) khoản")
                    .font(.system(size: 15)).foregroundStyle(.secondary)
                Text("Tổng cộng \(store.items.count) khoản đã ghi")
                    .font(.system(size: 15)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Palette.hero, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Ngân sách

    private var budgetSection: some View {
        Section {
            BudgetSlider(value: store.budget, draft: $budgetDraft, commit: { store.budget = $0 }) {
                budgetText = store.budget > 0 ? fmt(store.budget) : ""
                typingBudget = true
            }
            // Chừa lề trên dưới: sát mép ô thì ô danh sách cắt mất góc bo phía dưới của thanh
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text("Ngân sách")
        } footer: {
            budgetFooter
        }
    }

    /// Còn / vượt bao nhiêu theo mức đang kéo, rồi cách dùng thanh kéo.
    private var budgetFooter: some View {
        let v = budgetDraft ?? store.budget
        let s = BudgetStatus(budget: v, spent: store.monthItems(Date()).reduce(0) { $0 + $1.a })
        return VStack(alignment: .leading, spacing: 6) {
            if v > 0 {
                // Chữ giữ màu chữ thường cho dễ đọc; chỉ khi vượt mới đỏ, kèm biểu tượng
                HStack(spacing: 4) {
                    if s.level == .over { Image(systemName: "exclamationmark.triangle.fill") }
                    Text("\(s.label) · đã dùng \(Int((s.ratio * 100).rounded()))%")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(s.level == .over ? Palette.danger : .primary)
            }
            Text(v > 0 ? "Kéo hoặc chạm vào thanh để chỉnh, giữ lâu để nhập số chính xác. Kéo hết sang trái là bỏ ngân sách."
                       : "Kéo hoặc chạm vào thanh để đặt ngân sách tháng, giữ lâu để nhập số. Màn hình chính và widget sẽ hiện số còn lại và mức nên tiêu mỗi ngày.")
        }
    }

    // MARK: Khoản định kỳ

    private var recurringSection: some View {
        let list = store.rules.values.filter(\.on).sorted { ($0.day, $0.minute, $0.id) < ($1.day, $1.minute, $1.id) }
        return Section {
            if list.isEmpty {
                Label {
                    Text("Nhấn giữ một khoản chi (tiền nhà, điện, internet…) và chọn **Lặp hằng tháng**, app sẽ tự ghi mỗi tháng.")
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                } icon: {
                    icon("repeat", .purple)
                }
            }
            ForEach(list) { r in
                let c = Category.get(r.c)
                HStack(spacing: 12) {
                    CategoryIcon(c: c, size: 20)
                        .frame(width: 34, height: 34)
                        .background(c.color, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.n?.isEmpty == false ? r.n! : c.name).lineLimit(1)
                        Text("Ngày \(r.day) hằng tháng").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text("\(fmt(r.a))đ").fontWeight(.semibold).lineLimit(1)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { store.stopRepeating(r) } label: { Text("Bỏ lặp") }
                }
            }
        } header: {
            Text("Khoản định kỳ")
        } footer: {
            if !list.isEmpty {
                Text("Tới ngày là app tự ghi (khi mở app). Tháng nào đã tự ghi tay khoản giống hệt thì bỏ qua. Vuốt sang trái để bỏ lặp.")
            }
        }
    }

    // MARK: iCloud

    private var cloudSection: some View {
        Section {
            Toggle(isOn: $store.cloudOn) { row("Đồng bộ iCloud", "icloud.fill", .blue) }
            if store.cloudOn {
                HStack { Text("Trạng thái"); Spacer(); cloudStatus }
                if cloudReady {
                    Button {
                        syncing = true
                        Task { await store.syncNow(); syncing = false }
                    } label: {
                        HStack {
                            Text("Đồng bộ ngay")
                            Spacer()
                            if syncing { ProgressView() }
                        }
                    }
                    .disabled(syncing)
                }
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text(cloudFooter)
        }
    }

    private var cloudReady: Bool {
        if case .on = store.cloudState { return true }
        return false
    }

    @ViewBuilder private var cloudStatus: some View {
        switch store.cloudState {
        case .off:
            Text("Đang tắt").foregroundStyle(.secondary)
        case .connecting:
            Label("Đang kết nối…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
        case .unavailable:
            Label("Không dùng được", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .on(let last):
            if let last {
                Label("Đã đồng bộ \(time(last))", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Label("Đã bật", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }

    private var cloudFooter: String {
        switch store.cloudState {
        case .unavailable:
            return "Máy này chưa đăng nhập iCloud hoặc đã tắt iCloud Drive (Cài đặt › Tên bạn › iCloud › iCloud Drive). Dữ liệu vẫn lưu trên máy."
        case .off:
            return "Dữ liệu chỉ lưu trên iPhone này. Bật để dùng chung với iPhone/iPad khác cùng Apple ID."
        default:
            return "Dữ liệu tự đồng bộ với iPhone/iPad khác cùng Apple ID. Không có mạng vẫn dùng được, có mạng sẽ tự cập nhật."
        }
    }

    // MARK: Ngân hàng

    private var bankSection: some View {
        Section {
            Picker(selection: $store.appId) {
                Section("Mở sẵn người nhận + số tiền") {
                    ForEach(BankData.apps.filter(\.fill)) { Text($0.name).tag($0.id) }
                }
                Section("Chỉ mở app (quét lại QR)") {
                    ForEach(BankData.apps.filter { !$0.fill }) { Text($0.name).tag($0.id) }
                }
            } label: {
                row("App ngân hàng", "building.columns.fill", .green)
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("Thanh toán")
        } footer: {
            Text(store.bankApp.fill ? "Sau khi quét, Pay mở sẵn người nhận và số tiền trong app ngân hàng, không phải quét lại." : "App này chỉ mở được, bạn sẽ quét lại mã QR trong app ngân hàng.")
        }
    }

    // MARK: Dữ liệu

    private var dataSection: some View {
        Section {
            if let jsonURL {
                ShareLink(item: jsonURL) { row("Sao lưu ra file", "square.and.arrow.up.fill", .indigo) }
            }
            Button { importing = true } label: { row("Khôi phục từ file sao lưu", "arrow.down.doc.fill", .teal) }
            if let csvURL {
                ShareLink(item: csvURL) { row("Xuất CSV (Excel)", "tablecells.fill", .green) }
            }
            Button(role: .destructive) { confirmErase = true } label: {
                row("Xoá tất cả khoản chi", "trash.fill", .red, destructive: true)
            }
            .disabled(store.items.isEmpty)
        } header: {
            Text("Dữ liệu")
        } footer: {
            Text("File sao lưu của bản web cũng khôi phục được ở đây. Khôi phục chỉ thêm khoản còn thiếu, không ghi đè.")
        }
    }

    // MARK: Phụ

    private func row(_ title: String, _ symbol: String, _ color: Color, destructive: Bool = false) -> some View {
        Label {
            Text(title).foregroundStyle(destructive ? Color.red : Color.primary)
        } icon: {
            icon(symbol, color)
        }
    }

    /// Ô vuông màu có biểu tượng trắng, kiểu Cài đặt của iPhone.
    private func icon(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var version: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "1.0") (\(i?["CFBundleVersion"] as? String ?? "1"))"
    }

    private func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(d) ? "'lúc' HH:mm" : "dd/MM 'lúc' HH:mm"
        return f.string(from: d)
    }
}

// MARK: Thanh kéo ngân sách

/// Thanh kéo ngân sách, lấy nguyên kiểu `LabeledSlider` của app Peek (thanh Âm lượng / Độ sáng): nhãn và số
/// nằm trong rãnh, phần đã đầy là mảng sáng bo nhẹ, đầu phải có vạch dọc làm tay nắm. Số đo của Peek
/// (cao 34, bo 11, chữ 12) phóng lên khoảng 1,4 lần cho vừa ngón tay.
///
/// Giống Peek: chạm chỗ nào trên thanh thì nhảy tới chỗ đó; nắm trúng vạch tay nắm thì vạch đi theo tay.
/// Khác Peek vì là màn hình cảm ứng nằm trong trang cuộn: kéo dọc nhường cho trang cuộn, chạm vào phần nhãn
/// không làm gì (tránh lỡ tay xoá ngân sách), giữ lâu để nhập số chính xác.
struct BudgetSlider: View {
    /// Ngân sách đang đặt (đồng), 0 = chưa đặt
    let value: Int
    /// Số đang kéo, chỉ lưu khi buông tay
    @Binding var draft: Int?
    let commit: (Int) -> Void
    /// Giữ lâu trên thanh: nhập số chính xác
    let typeExact: () -> Void

    /// Khoảng lệch từ chỗ nắm tới mép mảng sáng, giữ suốt một lượt kéo; khác nil là đang kéo
    @State private var grab: CGFloat?
    @State private var width: CGFloat = 1
    @State private var labelWidth: CGFloat = 80
    @State private var valueWidth: CGFloat = 40

    /// Vạch tay nắm lúc đang kéo: màu Peek dùng khi rê chuột lên thanh
    private static let handleActive = Color(.sRGB, red: 0.62, green: 0.85, blue: 0.10)
    private static let height: CGFloat = 48
    /// Bo nhẹ thôi, không phải viên thuốc: đúng tỉ lệ Peek (bo 11 trên cao 34)
    private static let radius: CGFloat = 18
    private static let leadingPad: CGFloat = 18
    private static let barWidth: CGFloat = 4
    private static let barInset: CGFloat = 13
    /// Chạm cách vạch tay nắm trong chừng này thì tính là nắm vạch (ngón tay to hơn con trỏ nên rộng hơn Peek)
    private static let grabReach: CGFloat = 22
    /// Mảng sáng còn cách số chừng này thì số chuyển vào trong mảng sáng
    private static let valueGap: CGFloat = 20
    /// Từ mép phải số tới vạch tay nắm, lúc số nằm trong mảng sáng
    private static let valueInset: CGFloat = 11
    // Giao diện tối đúng màu Peek (mảng trắng 0,92 trên rãnh trắng 0,10); giao diện sáng thì đảo lại
    private static let track = Color(light: 0xDCDCE2, dark: 0x2E2E31)
    private static let fill = Color.primary.opacity(0.92)
    /// Chữ và vạch nằm trên mảng sáng
    private static let ink = Color(light: 0xFFFFFF, dark: 0x000000)

    /// Các mức kéo được: 0 (chưa đặt), mỗi nấc 500 nghìn đến 10 triệu, rồi mỗi nấc 1 triệu đến 30 triệu.
    /// Nửa trái thanh dành cho 0–10 triệu cho dễ chỉnh mức hay dùng.
    static let levels: [Int] = Array(stride(from: 0, through: 10_000_000, by: 500_000))
        + Array(stride(from: 11_000_000, through: 30_000_000, by: 1_000_000))
    private static var last: Double { Double(levels.count - 1) }

    /// Vị trí (0...1) của một số tiền trên thanh; số lẻ (nhập tay) nằm giữa hai nấc.
    static func position(_ v: Int) -> Double {
        let i = v <= 10_000_000 ? Double(v) / 500_000 : 20 + Double(v - 10_000_000) / 1_000_000
        return min(max(i / last, 0), 1)
    }

    private static func level(at p: Double) -> Int { levels[Int((min(max(p, 0), 1) * last).rounded())] }

    /// 8.000.000 -> "8tr", 8.500.000 -> "8,5tr", 7.250.000 -> "7,25tr", 500.000 -> "500k"
    static func compact(_ v: Int) -> String {
        if v < 1_000_000 { return v % 1000 == 0 ? "\(v / 1000)k" : "\(fmt(v))đ" }
        var s = String(format: "%.2f", Double(v) / 1_000_000)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s.replacingOccurrences(of: ".", with: ",") + "tr"
    }

    private var shown: Int { draft ?? value }
    /// Mức 0 không phải bề rộng 0: mảng sáng phải bọc trọn nhãn chữ và vạch tay nắm
    private var floorWidth: CGFloat { min(Self.leadingPad + labelWidth + 14 + Self.barWidth + Self.barInset, width) }
    /// Quãng chạy thật của mép mảng sáng
    private var usable: CGFloat { max(1, width - floorWidth) }
    private var filled: CGFloat { floorWidth + usable * Self.position(shown) }

    var body: some View {
        let filled = self.filled
        // Hết chỗ thì số chuyển vào trong mảng sáng, sát bên trái vạch tay nắm và chạy theo nó
        let inside = width - Self.leadingPad - valueWidth - filled < Self.valueGap
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous).fill(Self.track)
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous).fill(Self.fill)
                .frame(width: filled)
                .overlay(alignment: .trailing) {
                    Capsule()
                        .fill(grab != nil ? Self.handleActive : Self.ink.opacity(0.55))
                        .frame(width: Self.barWidth, height: Self.height * 0.44)
                        .padding(.trailing, Self.barInset)
                        .animation(.easeOut(duration: 0.14), value: grab != nil)
                }
            Text("Mỗi tháng")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Self.ink.opacity(0.78))
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = $0 }
                .padding(.leading, Self.leadingPad)
            // Số không vẽ hai bản chồng nhau: ở ngoài thì nằm trên rãnh, ở trong thì nằm trên mảng sáng;
            // đổi chỗ thì mờ chéo chứ không trượt (đang kéo thì cú trượt bị cắt ngang thành cú nhảy)
            ZStack(alignment: .leading) {
                valueLabel(size: 17)
                    .foregroundStyle(shown > 0 ? AnyShapeStyle(Color.primary.opacity(0.85)) : AnyShapeStyle(.secondary))
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { valueWidth = $0 }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, Self.leadingPad)
                    .mask(alignment: .trailing) { Rectangle().frame(width: max(0, width - filled)) }
                    .opacity(inside ? 0 : 1)
                valueLabel(size: 16)
                    .foregroundStyle(Self.ink.opacity(0.78))
                    .frame(width: max(0, filled - Self.barInset - Self.barWidth - Self.valueInset), alignment: .trailing)
                    .opacity(inside ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.25), value: inside)
        }
        .frame(height: Self.height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 1) }
        .overlay { SliderGestures(pan: pan, tap: tap, hold: hold) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ngân sách tháng")
        .accessibilityValue(shown > 0 ? "\(fmt(shown)) đồng" : "Chưa đặt")
        .accessibilityAdjustableAction { dir in
            let i = Int((Self.position(value) * Self.last).rounded()) + (dir == .increment ? 1 : -1)
            commit(Self.levels[min(max(i, 0), Self.levels.count - 1)])
        }
        .accessibilityAction(named: "Nhập số chính xác", typeExact)
    }

    private func valueLabel(size: CGFloat) -> some View {
        Text(shown > 0 ? Self.compact(shown) : "Chưa đặt")
            .font(.system(size: size, weight: .medium, design: .rounded))
            .monospacedDigit()
            .fixedSize()
    }

    /// Mép vạch tay nắm hiện tại (giữa vạch)
    private var bar: CGFloat { filled - Self.barInset - Self.barWidth / 2 }

    private func pan(_ x: CGFloat, _ touchDown: CGFloat, _ phase: SliderGestures.Phase) {
        switch phase {
        case .began:
            // Nắm trúng vạch thì vạch đi theo tay (nhớ khoảng lệch); nắm chỗ khác thì mép mảng sáng nhảy tới tay
            grab = abs(touchDown - bar) <= Self.grabReach ? filled - touchDown : 0
            move(to: x)
        case .changed:
            move(to: x)
        case .ended:
            if let d = draft, d != value { commit(d) }
            draft = nil
            grab = nil
        }
    }

    private func move(to x: CGFloat) {
        let v = Self.level(at: Double((x + (grab ?? 0) - floorWidth) / usable))
        if v != shown { tick(v) }
        draft = v
    }

    /// Chạm: nhảy tới chỗ chạm. Chạm vào phần nhãn hay ngay vạch tay nắm thì thôi.
    private func tap(_ x: CGFloat) {
        guard x > floorWidth, abs(x - bar) > Self.grabReach else { return }
        let v = Self.level(at: Double((x - floorWidth) / usable))
        guard v != value else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.snappy(duration: 0.25)) { commit(v) }
    }

    private func hold() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        typeExact()
    }

    /// Rung nhẹ ở các mốc tròn (mỗi 1 triệu, trên 10 triệu thì mỗi 5 triệu), rung mạnh hơn khi chạm đầu / cuối thanh.
    private func tick(_ v: Int) {
        if v == 0 || v == Self.levels.last {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        } else if v % (v <= 10_000_000 ? 1_000_000 : 5_000_000) == 0 {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

/// Lớp trong suốt phủ lên thanh kéo: kéo ngang, chạm, giữ lâu. Kéo dọc thì nhường để trang Cài đặt vẫn cuộn được.
struct SliderGestures: UIViewRepresentable {
    enum Phase { case began, changed, ended }
    /// Kéo: chỗ ngón tay đang ở, và chỗ vừa chạm xuống (theo chiều ngang của thanh)
    let pan: (_ x: CGFloat, _ touchDown: CGFloat, _ phase: Phase) -> Void
    let tap: (_ x: CGFloat) -> Void
    let hold: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.accessibilityElementsHidden = true   // VoiceOver dùng thanh kéo của SwiftUI (vuốt lên / xuống để chỉnh)
        let c = context.coordinator
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:)))
        pan.delegate = c
        let hold = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.hold(_:)))
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: hold)
        [pan, hold, tap].forEach(v.addGestureRecognizer)
        update(c)
        return v
    }

    func updateUIView(_ v: UIView, context: Context) { update(context.coordinator) }

    private func update(_ c: Coordinator) {
        c.onPan = pan
        c.onTap = tap
        c.onHold = hold
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onPan: (CGFloat, CGFloat, Phase) -> Void = { _, _, _ in }
        var onTap: (CGFloat) -> Void = { _ in }
        var onHold: () -> Void = {}
        /// Chỗ ngón tay chạm xuống. Cử chỉ kéo chỉ bắt đầu sau khi ngón tay đi được một quãng,
        /// nên lấy từ lúc chạm chứ không suy ngược từ cử chỉ.
        private var touchDown: CGFloat = 0

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let x = g.location(in: g.view).x
            switch g.state {
            case .began: onPan(x, touchDown, .began)
            case .changed: onPan(x, touchDown, .changed)
            case .ended, .cancelled, .failed: onPan(x, touchDown, .ended)
            default: break
            }
        }

        @objc func tap(_ g: UITapGestureRecognizer) { onTap(g.location(in: g.view).x) }

        @objc func hold(_ g: UILongPressGestureRecognizer) { if g.state == .began { onHold() } }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if g is UIPanGestureRecognizer { touchDown = touch.location(in: g.view).x }
            return true
        }

        /// Chỉ nhận khi kéo ngang nhiều hơn dọc
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y)
        }

        /// Trang cuộn đợi thanh kéo quyết định trước: kéo ngang thì thanh nhận, kéo dọc thì trang cuộn
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            g is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}

/// Hướng dẫn thêm widget, gán nút Tác vụ và dùng Phím tắt.
struct QuickAccessHelp: View {
    var body: some View {
        Form {
            Section {
                step(1, "Ở màn hình chính, chạm và giữ vào chỗ trống đến khi biểu tượng rung.")
                step(2, "Bấm Sửa › Thêm tiện ích, tìm \"Pay\".")
                step(3, "Chọn \"Chi tiêu hôm nay\" (cỡ vừa có nút Quét QR, Nói, Nhập) hoặc \"Nói để ghi\" (chạm là nghe luôn).")
            } header: {
                Label("Widget màn hình chính", systemImage: "square.grid.2x2.fill")
            }

            Section {
                step(1, "Chạm và giữ màn hình khoá, bấm Tuỳ chỉnh › Màn hình khoá.")
                step(2, "Bấm vùng widget dưới đồng hồ, chọn Pay › \"Nói để ghi\" (nút micro tròn).")
                step(3, "iOS 18 trở lên: bấm nút ở góc dưới (đèn pin, camera), đổi thành \"Pay: Ghi bằng giọng nói\".")
            } header: {
                Label("Màn hình khoá: nút micro", systemImage: "lock.fill")
            } footer: {
                Text("Chạm nút micro, mở khoá xong là Pay nghe luôn. Màn hình khoá cũng có nút quét QR và số đã chi hôm nay.")
            }

            Section {
                step(1, "Mở Cài đặt › Nút Tác vụ, vuốt đến Điều khiển.")
                step(2, "Bấm Chọn điều khiển, tìm \"Pay: Ghi bằng giọng nói\".")
                step(3, "Nhấn giữ nút Tác vụ: Pay mở và nghe luôn. Nói \"35k cafe\", ngừng nói là tự ghi.")
            } header: {
                Label("Nút Tác vụ: ghi bằng giọng nói", systemImage: "mic.fill")
            } footer: {
                Text("Cần iPhone 15 Pro trở lên, iOS 18 trở lên. Nói được nhiều kiểu: \"35 nghìn cà phê\", \"1tr2 tiền nhà\", \"grab 52k\". Danh mục tự đoán theo ghi chú.")
            }

            Section {
                step(1, "Mở Cài đặt › Nút Tác vụ, vuốt đến Điều khiển.")
                step(2, "Bấm Chọn điều khiển, tìm \"Pay: Quét QR\".")
                step(3, "Nhấn giữ nút Tác vụ là mở camera quét ngay.")
            } header: {
                Label("Nút Tác vụ: quét QR", systemImage: "qrcode.viewfinder")
            } footer: {
                Text("Cần iOS 18 trở lên. Nút Tác vụ chỉ gán được một việc: chọn ghi bằng giọng nói hoặc quét QR. Nút \"Pay: Quét QR\" cũng thêm được vào Trung tâm điều khiển.")
            }

            Section {
                step(1, "Nói \"Ghi chi tiêu bằng Pay\" với Siri, rồi nói khoản chi. Hoặc \"Quét QR bằng Pay\".")
                step(2, "Hoặc mở app Phím tắt, hai lệnh này có sẵn trong mục Pay.")
            } header: {
                Label("Siri và Phím tắt", systemImage: "wand.and.stars")
            }
        }
        .navigationTitle("Truy cập nhanh")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.08), in: Circle())
            Text(text)
        }
    }
}
