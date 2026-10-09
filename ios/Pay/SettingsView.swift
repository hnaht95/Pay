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
            Text(v > 0 ? "Kéo để chỉnh, chạm để nhập số chính xác. Kéo hết sang trái là bỏ ngân sách."
                       : "Kéo sang phải để đặt ngân sách tháng, hoặc chạm để nhập số. Màn hình chính và widget sẽ hiện số còn lại và mức nên tiêu mỗi ngày.")
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

/// Thanh kéo kiểu app Peek / thanh âm lượng: khối sáng bo tròn có tay nắm ở đầu, chữ nằm trong khối, số tiền ở cuối thanh.
/// Kéo ngang ở đâu trên thanh cũng được, khối chạy theo ngón tay (không nhảy tới chỗ chạm). Chạm để nhập số chính xác.
struct BudgetSlider: View {
    /// Ngân sách đang đặt (đồng), 0 = chưa đặt
    let value: Int
    /// Số đang kéo, chỉ lưu khi buông tay
    @Binding var draft: Int?
    let commit: (Int) -> Void
    let tap: () -> Void

    /// Vị trí (0...1) lúc bắt đầu kéo
    @State private var start: Double?
    /// Kéo quá đầu / cuối thanh: thanh giãn ra một chút về phía đang kéo rồi bật lại khi buông
    @State private var stretch: CGFloat = 0
    @State private var width: CGFloat = 1
    @State private var labelWidth: CGFloat = 80
    @State private var valueWidth: CGFloat = 50

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

    /// Khối tô: đen trên nền trắng (giao diện sáng), trắng ngà trên nền tối như Peek
    private static let fillColor = Color(light: 0x111114, dark: 0xEBEBED)
    private static let fillInk = Color(light: 0xFFFFFF, dark: 0x2C2C2E)

    private var shown: Int { draft ?? value }
    /// Khối sáng ngắn nhất (mức 0): vừa chữ + tay nắm, như Peek
    private var minFill: CGFloat { 18 + labelWidth + 16 + 4 + 12 }
    /// Quãng đường khối sáng chạy được: ngón tay kéo bao nhiêu thì đầu khối đi bấy nhiêu
    private var travel: CGFloat { max(width - minFill, 1) }

    var body: some View {
        let fill = minFill + travel * Self.position(shown)
        // Số tiền nằm cuối thanh; khối sáng dài tới nơi thì số chui vào trong khối, ngay trước tay nắm
        let inside = fill > width - 20 - valueWidth - 12
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack(alignment: .leading) {
            shape.fill(Color(.secondarySystemGroupedBackground))
            HStack(spacing: 0) {
                Text("Mỗi tháng").fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = $0 }
                Spacer(minLength: 16)
                Capsule().frame(width: 4, height: 20).opacity(0.45)
            }
            .padding(.leading, 18).padding(.trailing, 12)
            .frame(width: fill)
            .frame(maxHeight: .infinity)
            .background(Self.fillColor, in: shape)
            .foregroundStyle(Self.fillInk)
            Text(shown > 0 ? Self.compact(shown) : "Chưa đặt").fixedSize()
                .monospacedDigit()
                .foregroundStyle(inside ? AnyShapeStyle(Self.fillInk) : shown > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { valueWidth = $0 }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, inside ? width - fill + 30 : 20)
        }
        .font(.system(size: 17, weight: .medium))
        .frame(height: 52)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 1) }
        .overlay { HorizontalPan(changed: drag, tapped: tap) }
        .scaleEffect(x: 1 + abs(stretch) / width, y: 1, anchor: stretch < 0 ? .trailing : .leading)
        .scaleEffect(start != nil ? 1.02 : 1)
        .animation(.spring(duration: 0.3), value: start != nil)
        .animation(.snappy(duration: 0.2), value: inside)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ngân sách tháng")
        .accessibilityValue(shown > 0 ? "\(fmt(shown)) đồng" : "Chưa đặt")
        .accessibilityAdjustableAction { dir in
            let i = Int((Self.position(value) * Self.last).rounded()) + (dir == .increment ? 1 : -1)
            commit(Self.levels[min(max(i, 0), Self.levels.count - 1)])
        }
        .accessibilityAction(named: "Nhập số chính xác", tap)
    }

    private func drag(_ dx: CGFloat, _ phase: HorizontalPan.Phase) {
        if phase == .began { start = Self.position(shown) }
        guard let start else { return }
        if phase == .ended {
            if let d = draft, d != value { commit(d) }
            draft = nil
            self.start = nil
            withAnimation(.spring(duration: 0.4, bounce: 0.45)) { stretch = 0 }
            return
        }
        let raw = start + Double(dx / travel)
        let v = Self.level(at: raw)
        if v != shown { tick(v) }
        draft = v
        // Quá đầu / cuối: giãn ra, càng kéo càng nặng tay
        let over = CGFloat(raw - min(max(raw, 0), 1)) * travel
        stretch = over == 0 ? 0 : (over < 0 ? -1 : 1) * 14 * (1 - exp(-abs(over) / 60))
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

/// Lớp trong suốt phủ lên thanh kéo: nhận kéo ngang và chạm; kéo dọc thì nhường để trang Cài đặt vẫn cuộn được.
struct HorizontalPan: UIViewRepresentable {
    enum Phase { case began, changed, ended }
    let changed: (CGFloat, Phase) -> Void
    let tapped: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.accessibilityElementsHidden = true   // VoiceOver dùng thanh kéo của SwiftUI (vuốt lên / xuống để chỉnh)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        v.addGestureRecognizer(pan)
        v.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap)))
        update(context.coordinator)
        return v
    }

    func updateUIView(_ v: UIView, context: Context) { update(context.coordinator) }

    private func update(_ c: Coordinator) {
        c.changed = changed
        c.tapped = tapped
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var changed: (CGFloat, Phase) -> Void = { _, _ in }
        var tapped: () -> Void = {}

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let dx = g.translation(in: g.view).x
            switch g.state {
            case .began: changed(dx, .began)
            case .changed: changed(dx, .changed)
            case .ended, .cancelled, .failed: changed(dx, .ended)
            default: break
            }
        }

        @objc func tap() { tapped() }

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
