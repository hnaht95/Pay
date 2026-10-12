import PhotosUI
import SwiftUI
import WidgetKit

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var pro = Pro.shared
    @Environment(\.dismiss) private var dismiss
    /// Tài khoản nhận tiền của mình, cho widget mã QR
    @State private var myQR = MyQR.load()
    @State private var importing = false
    @State private var confirmErase = false
    @State private var syncing = false
    @State private var jsonURL: URL?
    @State private var csvURL: URL?
    /// Số đang kéo trên thanh ngân sách (chưa lưu), để dòng "Còn ..." bên dưới chạy theo
    @State private var budgetDraft: Int?
    @State private var typingBudget = false
    @State private var budgetText = ""
    /// Sửa / thêm danh mục tự tạo (nil k = thêm mới)
    /// Ngôn ngữ đang chọn trong Cài đặt
    @State private var lang = Lang.current
    @AppStorage(Appearance.key) private var appearanceRaw = Appearance.system.rawValue
    @AppStorage(Appearance.minimalKey) private var minimal = false
    private var appearance: Appearance {
        get { Appearance(rawValue: appearanceRaw) ?? .system }
        nonmutating set { appearanceRaw = newValue.rawValue }
    }
    @State private var remindOn = DailyReminder.isOn
    @State private var remindAt = Calendar.current.date(byAdding: .minute, value: DailyReminder.minute,
                                                        to: Calendar.current.startOfDay(for: Date()))!

    var body: some View {
        NavigationStack {
            BlurForm {
                Section { summary }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .cardless()

                proSection
                budgetSection
                recurringSection
                autoSection
                cloudSection
                bankSection
                myQRSection
                appearanceSection
                languageSection

                Section {
                    NavigationLink { QuickAccessHelp() } label: {
                        row(L("Widget, nút Tác vụ, Phím tắt"))
                    }
                } header: {
                    Text(L("Truy cập nhanh"))
                }

                dataSection

                Section {
                    LabeledContent { Text(version).foregroundStyle(.secondary) } label: {
                        row(L("Phiên bản"))
                    }
                } footer: {
                    Text(L("Pay — ghi chi tiêu tối giản: gõ 35k cafe hoặc quét VietQR."))
                }
            }
            .textCase(nil)   // tiêu đề mục viết thường ở mọi bản iOS (iOS 18 trở xuống tự viết hoa)
            .softTopEdge(fade: Color(.systemGroupedBackground), home: true)
            .screenTitle(L("Cài đặt"))
            .navigationBarTitleDisplayMode(.inline)
        }
        // Không có nút Xong: vạch ngang trên cùng cho biết kéo xuống là đóng
        .sheetGrabber()
        // File sao lưu có cả khoản định kỳ và danh mục đã học: đổi gì cũng làm lại
        .task(id: [store.items.hashValue, store.rules.hashValue, store.memo.hashValue]) { jsonURL = store.exportJSON(); csvURL = store.exportCSV() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { store.importBackup(from: url) }
        }
        .confirmationDialog(L("Xoá tất cả khoản chi?"), isPresented: $confirmErase, titleVisibility: .visible) {
            Button(L("Xoá tất cả"), role: .destructive) { store.eraseAll() }
        } message: {
            Text((store.cloudOn ? L("Các máy khác đang đồng bộ iCloud cũng sẽ bị xoá.") : L("Không hoàn tác được."))
                 + (store.rules.values.contains(where: \.on) ? " " + L("Khoản định kỳ cũng dừng tự ghi.") : "") + " " + L("Nên sao lưu trước."))
        }
        .alert(L("Ngân sách tháng"), isPresented: $typingBudget) {
            TextField(L("Ví dụ 8.000.000"), text: $budgetText).keyboardType(.numberPad)
            Button(L("Huỷ"), role: .cancel) {}
            Button(L("Lưu")) {
                let digits = budgetText.filter(\.isNumber)
                if digits.isEmpty { store.budget = 0 } else if let v = Int(digits.prefix(12)) { store.budget = v }
            }
        } message: {
            Text(L("Số tiền tiêu mỗi tháng. Để trống là bỏ ngân sách."))
        }
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 24) }
    }

    // MARK: Danh mục tự tạo

    // MARK: Tổng quan

    private var summary: some View {
        let now = Date()
        let month = store.monthItems(now)
        return HStack(spacing: 14) {
            Image("logo-pay").resizable().scaledToFit().frame(width: 60)   // chỉ thẻ xanh, không ô nền
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    Text(L("Tháng %@: %@ · %@ khoản", monthName(now), fmt(month.reduce(0) { $0 + $1.a }), String(month.count)))
                    Text(L("Tổng cộng %@ khoản đã ghi", String(store.items.count)))
                }
                .font(.system(size: 15)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        // Thẻ trắng như các ô khác (nền tím nhạt cũ tương phản kém)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Ngân sách

    private var budgetSection: some View {
        // Thanh kéo nằm ở chân mục chứ không làm một hàng: hàng của Form bị cắt theo góc bo lớn của ô,
        // làm góc thanh kéo méo thành góc vuông bo to. Chân mục không bị cắt.
        Section {
        } header: {
            Text(L("Ngân sách"))
        } footer: {
            VStack(alignment: .leading, spacing: 12) {
                BudgetSlider(value: store.budget, draft: $budgetDraft, commit: { store.budget = $0 }) {
                    budgetText = store.budget > 0 ? fmt(store.budget) : ""
                    typingBudget = true
                }
                .padding(.horizontal, -16)   // chân mục lùi vào 16 so với mép ô: thanh vẫn rộng bằng các ô khác
                budgetFooter
            }
            .textCase(nil)
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
                    Text(L("%@ · đã dùng %@%%", s.label, String(Int((s.ratio * 100).rounded()))))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(s.level == .over ? Palette.danger : .primary)
            }
            Text(v > 0 ? L("Kéo hoặc chạm vào thanh để chỉnh, giữ lâu để nhập số chính xác. Kéo hết sang trái là bỏ ngân sách.")
                       : L("Kéo hoặc chạm vào thanh để đặt ngân sách tháng, giữ lâu để nhập số. Màn hình chính và widget sẽ hiện số còn lại và mức nên tiêu mỗi ngày."))
        }
    }

    // MARK: Khoản định kỳ

    private var recurringSection: some View {
        let list = store.rules.values.filter(\.on).sorted { ($0.day, $0.minute, $0.id) < ($1.day, $1.minute, $1.id) }
        return Section {
            if list.isEmpty {
                // "Lặp hằng tháng" tô dạ quang xanh lá bằng nét bút của Shot
                HighlightedText(text: L("Nhấn giữ một khoản chi như tiền nhà, điện, internet rồi chọn **Lặp hằng tháng**, app sẽ tự ghi mỗi tháng."))
                    .font(.system(size: 15)).foregroundStyle(.secondary)
            }
            ForEach(list) { r in
                let c = Category.get(r.c)
                HStack(spacing: 12) {
                    CategoryBadge(c: c, side: 34, radius: 10, iconSize: 20, edge: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.n?.isEmpty == false ? r.n!.capFirst : c.name).lineLimit(1)
                        Text(L("Ngày %@ hằng tháng", String(r.day))).font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text("\(fmt(r.a))").fontWeight(.semibold).lineLimit(1)
                }
                .trashSwipe(L("Bỏ lặp")) { withAnimation(.snappy) { store.stopRepeating(r) } }
            }
        } header: {
            Text(L("Khoản định kỳ"))
        } footer: {
            if !list.isEmpty {
                Text(L("Tới ngày là app tự ghi (khi mở app). Tháng nào đã tự ghi tay khoản giống hệt thì bỏ qua. Vuốt sang trái để bỏ lặp."))
            }
        }
    }

    // MARK: Pro

    private var proSection: some View {
        Section {
            // Chỉ bản thử (TestFlight / Xcode): bật để dùng đủ tính năng Pro không cần mua, tắt để thử lại màn mua
            if pro.isTestBuild {
                Toggle(isOn: $pro.testerUnlock) {
                    Text(L("Bản thử: mở khoá Pro"))
                }
            }
            if pro.active {
                Label { Text(L("Đã có Pay Pro")) } icon: { Image(systemName: "checkmark.seal.fill").foregroundStyle(Color(hex: 0x61BE6E)) }
            } else {
                Button { ProPaywall.present() } label: {
                    HStack(spacing: 10) {
                        // "Nâng cấp" + chữ "Pro" viết tay xanh như màn mua Pro
                        Text(L("Nâng cấp")).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.primary)
                        ProBadge(height: 28)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                }
                Button(L("Khôi phục giao dịch")) { Task { await pro.restore() } }.foregroundStyle(Color.primary)
            }
        } footer: {
            if !pro.active { Text(L("Lịch sử đầy đủ, iCloud, khoản định kỳ, ảnh, danh mục không giới hạn, tự ghi Apple Pay, xuất CSV.")) }
        }
    }

    // MARK: iCloud

    private var cloudSection: some View {
        Section {
            // Pro: chưa mua thì công tắc hiện tắt, bật lên là mở màn mua Pro
            Toggle(isOn: Binding(get: { store.cloudOn && pro.active },
                                 set: { v in if !v || Pro.shared.allow(.cloud) { store.cloudOn = v } })) { proRow(L("Đồng bộ iCloud")) }
            if store.cloudOn && pro.active {
                HStack { Text(L("Trạng thái")); Spacer(); cloudStatus }
                if cloudReady {
                    Button {
                        syncing = true
                        Task { await store.syncNow(); syncing = false }
                    } label: {
                        HStack {
                            Text(L("Đồng bộ ngay"))
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
            Text(L("Đang tắt")).foregroundStyle(.secondary)
        case .connecting:
            Label(L("Đang kết nối…"), systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
        case .unavailable:
            Label(L("Không dùng được"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .on(let last):
            if let last {
                Label(L("Đã đồng bộ %@", time(last)), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Label(L("Đã bật"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }

    private var cloudFooter: String {
        switch store.cloudState {
        case .unavailable:
            return L("Máy này chưa đăng nhập iCloud hoặc đã tắt iCloud Drive (Cài đặt › Tên bạn › iCloud › iCloud Drive). Dữ liệu vẫn lưu trên máy.")
        case .off:
            return L("Dữ liệu chỉ lưu trên iPhone này. Bật để dùng chung với iPhone/iPad khác cùng Apple ID.")
        default:
            return L("Dữ liệu tự đồng bộ với iPhone/iPad khác cùng Apple ID. Không có mạng vẫn dùng được, có mạng sẽ tự cập nhật.")
        }
    }

    // MARK: Ngân hàng

    private var bankSection: some View {
        Section {
            Picker(selection: $store.appId) {
                Section(L("Mở sẵn người nhận + số tiền")) {
                    ForEach(BankData.apps.filter(\.fill)) { Text($0.name).tag($0.id) }
                }
                Section(L("Chỉ mở app (quét lại QR)")) {
                    ForEach(BankData.apps.filter { !$0.fill }) { Text($0.name).tag($0.id) }
                }
            } label: {
                row(L("App ngân hàng"))
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text(L("Thanh toán"))
        } footer: {
            Text(store.bankApp.fill ? L("Sau khi quét, Pay mở sẵn người nhận và số tiền trong app ngân hàng, không phải quét lại.") : L("App này chỉ mở được, bạn sẽ quét lại mã QR trong app ngân hàng."))
        }
    }

    // MARK: Tự động: nhắc ghi buổi tối, tự ghi khi trả Apple Pay

    private var autoSection: some View {
        Section {
            Toggle(isOn: Binding(get: { remindOn }, set: { v in
                remindOn = v
                Task { await DailyReminder.enable(v, store: store); remindOn = DailyReminder.isOn }
            })) { row(L("Nhắc ghi chi tiêu")) }
            if remindOn {
                DatePicker(selection: Binding(get: { remindAt }, set: { d in
                    remindAt = d
                    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                    DailyReminder.minute = (c.hour ?? 21) * 60 + (c.minute ?? 0)
                    DailyReminder.reschedule(loggedToday: store.count(on: Date()) > 0)
                }), displayedComponents: .hourAndMinute) { row(L("Giờ nhắc")) }
            }
            NavigationLink { ApplePayHelp() } label: { row(L("Tự ghi khi trả Apple Pay")) }
        } header: {
            Text(L("Tự động"))
        } footer: {
            Text(L("Tới giờ nhắc mà hôm ấy chưa ghi khoản nào, Pay báo một câu. Đã ghi rồi thì không báo."))
        }
    }

    // MARK: Mã QR nhận tiền của mình (cho widget)

    private static let banks = BankData.names.sorted { $0.value.lowercased() < $1.value.lowercased() }

    private var myQRSection: some View {
        Section {
            Picker(selection: $myQR.bin) {
                Text(L("Chưa chọn")).tag("")
                ForEach(Self.banks, id: \.key) { Text($0.value).tag($0.key) }
            } label: {
                row(L("Ngân hàng"))
            }
            .pickerStyle(.navigationLink)
            TextField(L("Số tài khoản"), text: $myQR.acct)
                .keyboardType(.asciiCapable).textInputAutocapitalization(.characters).autocorrectionDisabled()
            TextField(L("Tên chủ tài khoản (không bắt buộc)"), text: $myQR.name)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
            if myQR.ready {
                MyQRCode(qr: myQR)
                    .frame(width: 180, height: 180).padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
        } header: {
            Text(L("Mã QR nhận tiền"))
        } footer: {
            Text(L("Thêm widget \"Mã QR nhận tiền\" ra màn hình chính: người khác quét là chuyển khoản cho bạn, không phải mở app ngân hàng."))
        }
        .onChange(of: myQR) { _, typed in
            var q = typed
            // Chỉ giữ chữ và số ASCII (số dán từ app ngân hàng, tin nhắn hay có dấu cách, chấm, gạch ngang), tối đa 32 ký tự:
            // mã tính độ dài theo ký tự nên chữ có dấu làm lệch, và số dài quá 55 ký tự làm vỡ trường 38 (NAPAS chỉ cho 19)
            q.acct = String(q.acct.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(32))
            q.bank = BankData.names[q.bin] ?? ""
            // Ghi bản đã lọc ngược lại ô nhập trước khi lưu: mã xem trước ở trên vẽ từ đúng số mà widget sẽ dùng.
            // Gán xong onChange chạy lại với bản sạch rồi mới lưu.
            guard q == typed else { myQR = q; return }
            q.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: Ngôn ngữ

    private var appearanceSection: some View {
        Section {
            Picker(selection: Binding(get: { appearance }, set: { appearance = $0; Appearance.apply() })) {
                ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                row(L("Chế độ"))
            }
            .pickerStyle(.navigationLink)
            Toggle(isOn: $minimal) { row(L("Tối giản")) }
        } header: {
            Text(L("Giao diện"))
        } footer: {
            Text(L("Tối giản: danh mục không màu, chỉ biểu tượng giữ màu. Dùng được với cả Sáng và Tối."))
        }
    }

    private var languageSection: some View {
        Section {
            Picker(selection: Binding(get: { lang }, set: { lang = $0; Lang.set($0) })) {
                ForEach(Lang.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                row(L("Ngôn ngữ app"))
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text(L("Ngôn ngữ"))
        } footer: {
            Text(L("Đổi ngôn ngữ của app và widget."))
        }
    }

    // MARK: Dữ liệu

    private var dataSection: some View {
        Section {
            if let jsonURL {
                ShareLink(item: jsonURL) { row(L("Sao lưu ra file")) }
            }
            Button { importing = true } label: { row(L("Khôi phục từ file sao lưu")) }
            if pro.active, let csvURL {
                ShareLink(item: csvURL) { row(L("Xuất CSV cho Excel")) }
            } else if !pro.active {
                Button { Pro.shared.allow(.csv) } label: { proRow(L("Xuất CSV cho Excel")) }
            }
            Button(role: .destructive) { confirmErase = true } label: {
                row(L("Xoá tất cả khoản chi"), destructive: true)
            }
            .disabled(store.items.isEmpty)
        } header: {
            Text(L("Dữ liệu"))
        } footer: {
            Text(L("File sao lưu của bản web cũng khôi phục được ở đây. Khôi phục chỉ thêm khoản còn thiếu, không ghi đè."))
        }
    }

    // MARK: Phụ

    /// Một hàng chỉ có chữ (trước có ô biểu tượng màu ở đầu, đã bỏ cho gọn)
    private func row(_ title: String, destructive: Bool = false) -> some View {
        Text(title).foregroundStyle(destructive ? Color.red : Color.primary)
    }

    /// Hàng của tính năng Pro: chưa mua thì có nhãn "Pro" nhỏ bên cạnh
    private func proRow(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title).foregroundStyle(Color.primary)
            if !pro.active { ProBadge() }
        }
    }

    private var version: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "1.0") (\(i?["CFBundleVersion"] as? String ?? "1"))"
    }

    private func time(_ d: Date) -> String {
        let f = DateFormatter()
        let today = Calendar.current.isDateInToday(d)
        if Lang.isEnglish {
            f.locale = Lang.locale
            f.dateFormat = today ? "'at' h:mm a" : "MMM d 'at' h:mm a"
        } else {
            f.dateFormat = today ? "'lúc' HH:mm" : "dd/MM 'lúc' HH:mm"
        }
        return f.string(from: d)
    }

    /// Tên tháng trong dòng tổng quan: tiếng Việt là số ("Tháng 10"), tiếng Anh là tên tháng ("October")
    private func monthName(_ d: Date) -> String {
        guard Lang.isEnglish else { return String(Calendar.current.component(.month, from: d)) }
        let f = DateFormatter()
        f.locale = Lang.locale
        f.dateFormat = "LLLL"
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
    private static let handleActive = Color(hex: 0x111114)   // đang kéo: vạch đậm hẳn (trước là xanh nõn chuối, chìm trên nền xanh)
    private static let height: CGFloat = 48
    /// Bo nhẹ thôi, không phải viên thuốc: đúng tỉ lệ Peek (bo 11 trên cao 34)
    private static let radius: CGFloat = 14
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
    /// Mảng đã kéo: xanh lá của icon app
    private static let fill = Color(hex: 0x61BE6E)
    /// Chữ và vạch nằm trên mảng xanh: đen như các nét trên icon (trắng trên xanh này khó đọc)
    private static let ink = Color(hex: 0x111114)

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

    /// Số tiền trên thanh: ghi đủ số (8.000.000), không viết tắt kiểu "8tr" / "500k"
    static func compact(_ v: Int) -> String { fmt(v) }

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
            RoundedRectangle(cornerRadius: Self.radius, style: .circular).fill(Self.track)
            RoundedRectangle(cornerRadius: Self.radius, style: .circular).fill(Self.fill)
                .frame(width: filled)
                .overlay(alignment: .trailing) {
                    Capsule()
                        .fill(grab != nil ? Self.handleActive : Self.ink.opacity(0.55))
                        .frame(width: Self.barWidth, height: Self.height * 0.44)
                        .padding(.trailing, Self.barInset)
                        .animation(.easeOut(duration: 0.14), value: grab != nil)
                }
            Text(L("Mỗi tháng"))
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
        .accessibilityLabel(L("Ngân sách tháng"))
        .accessibilityValue(shown > 0 ? L("%@ đồng", fmt(shown)) : L("Chưa đặt"))
        .accessibilityAdjustableAction { dir in
            let i = Int((Self.position(value) * Self.last).rounded()) + (dir == .increment ? 1 : -1)
            commit(Self.levels[min(max(i, 0), Self.levels.count - 1)])
        }
        .accessibilityAction(named: Text(L("Nhập số chính xác")), typeExact)
    }

    private func valueLabel(size: CGFloat) -> some View {
        Text(shown > 0 ? Self.compact(shown) : L("Chưa đặt"))
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

struct CatEdit: Identifiable {
    let cat: CustomCat?
    var id: String { cat?.k ?? "new" }

    /// Sửa một danh mục bất kỳ (có sẵn hoặc tự tạo) theo mã
    @MainActor static func of(_ k: String, store: Store) -> CatEdit {
        if let c = store.cats[k], c.on { return CatEdit(cat: c) }
        let c = Category.get(k)
        return CatEdit(cat: CustomCat(k: k, name: c.rawName, icon: c.icon, tone: -1, on: true, u: 0))   // tên gốc tiếng Việt, không lưu bản dịch
    }
}

/// Thêm / sửa danh mục tự tạo: tên, biểu tượng, màu.
struct CategoryEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var editing: CustomCat? = nil
    /// Thêm xong: trả mã danh mục mới (để màn hình nhập chọn luôn)
    var onAdd: (String) -> Void = { _ in }

    @State private var name = ""
    @State private var icon = "🐶"
    @State private var tone = 0
    @FocusState private var nameFocused: Bool
    @State private var pickingEmoji = false
    /// Ảnh riêng của danh mục (thay cho biểu tượng); đổi / xoá rồi thì lưu lúc bấm Lưu
    @State private var photo: UIImage?
    @State private var photoChanged = false
    @State private var photoItem: PhotosPickerItem?
    /// Bảng chọn màu của iOS đang mở
    @State private var pickingColor = false
    /// Đang dựng phim giới thiệu (xem Film.swift): biểu tượng, màu đang chọn lấy từ phim
    @Environment(\.film) private var film
    private var fIcon: String { film?.edit?.icon ?? icon }
    private var fTone: Int { film?.edit?.tone ?? tone }
    private var shownName: String { film != nil ? L(editing?.name ?? "") : trimmed }

    static let emojis = ["🏠", "🐶", "👶", "🏋️", "🎮", "🎬", "📚", "🎓", "💊", "🏥", "💇", "🧴",
                         "🎁", "✈️", "🚗", "⛽️", "🍺", "🎵", "⚽️", "💡", "🛠️", "🌱", "❤️", "💼"]

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    /// Đang sửa danh mục có sẵn (Ăn uống, Cafe…): không xoá được, có "Về mặc định"
    private var builtin: Category? { editing.flatMap { e in Category.builtin.first { $0.k == e.k } } }
    private var previewColor: Color { fTone < 0 ? (builtin?.baseColor ?? CategoryTone.bg(0)) : CategoryTone.bg(fTone) }
    /// Trùng tên danh mục đang có (không tính chính nó)
    private var duplicate: Bool {
        let k = strip(trimmed)
        return !k.isEmpty && Category.all.contains { (strip($0.name) == k || strip($0.rawName) == k) && $0.k != editing?.k }
    }

    var body: some View {
        if let film { filmBody(film) } else { form }
    }

    private var previewCard: some View {
                    HStack(spacing: 14) {
                        Group {
                            if let photo { Image(uiImage: photo).resizable().scaledToFill() }
                            // Danh mục có sẵn chưa đổi biểu tượng: hiện đúng hình vẽ phẳng như ở màn hình chính
                            else if let b = builtin, fIcon == b.icon { CategoryIcon(c: b, size: 32) } else { Text(fIcon).font(.system(size: 28)) }
                        }
                            // Ô vuông nền trắng như ô danh mục ở màn hình chính
                            .frame(width: 56, height: 56).background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text(shownName.isEmpty ? L("Tên danh mục") : shownName)
                            .font(.system(size: 20, weight: .semibold)).lineLimit(1)
                            .opacity(shownName.isEmpty ? 0.4 : 1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(CategoryTone.dark(fTone) ? Color.white : Color(hex: 0x111114))
                    .padding(16)
                    .background(previewColor, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var emojiGrid: some View {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                        ForEach(Self.emojis, id: \.self) { e in
                            Button { if icon != e { Haptic.select() }; icon = e } label: {
                                Text(e).font(.system(size: 26))
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .background(fIcon == e ? previewColor : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(Pressable())
                            .filmPressed(film?.pressed["emoji-" + e] ?? 0)
                        }
                    }
                    .padding(.vertical, 4)
    }

    private var colorRows: some View { palettes }

    /// Bảng màu gợi ý — cùng cách bày thẻ bảng màu của app Shot (ColourSetCard): thẻ vuông 4 dải cao 41 / 26 / 18 / 15 %,
    /// bo 10, lưới 2 cột cách 16 (không ghi tên bảng). Chạm một dải để dùng màu ấy (lưu như màu tự chọn), dải đang dùng có dấu tích
    private var palettes: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
            ForEach(Self.palettes.indices, id: \.self) { p in paletteCard(Self.palettes[p]) }
        }
        .padding(.vertical, 8)
    }

    /// 4 dải cao bằng nhau
    private static let shares: [CGFloat] = [0.25, 0.25, 0.25, 0.25]

    private func paletteCard(_ p: (vi: String, en: String, colors: [UInt32])) -> some View {
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                VStack(spacing: 0) {
                    ForEach(p.colors.indices, id: \.self) { j in
                        let rgb = p.colors[j], t = CategoryTone.custom(rgb)
                        Button { if tone != t { Haptic.select() }; tone = t } label: {
                            Rectangle().fill(Color(hex: rgb))
                                .frame(height: g.size.height * Self.shares[j])
                                .overlay(alignment: .trailing) {
                                    if fTone == t {
                                        CircleCheck()
                                            .fill(CategoryTone.dark(t) ? .white : Color(hex: 0x1C1C1E), style: FillStyle(eoFill: true))
                                            .frame(width: 22, height: 22)
                                            .padding(.trailing, 10)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Màu %@", String(format: "#%06X", rgb)))
                    }
                }
            }
            // Thẻ dọc, cao hơn rộng
            .aspectRatio(0.72, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// 20 bảng màu được thích nhiều nhất trên Color Hunt, cùng bộ app Shot dùng (tên và 4 màu như Shot)
    private static let palettes: [(vi: String, en: String, colors: [UInt32])] = [
        ("Pastel", "Pastel", [0x95E1D3, 0xEAFFD0, 0xFCE38A, 0xF38181]),
        ("Neon", "Neon", [0xEAEAEA, 0xFF2E63, 0x252A34, 0x08D9D6]),
        ("Đầm phá", "Lagoon", [0x61C0BF, 0xBBDED6, 0xFAE3D9, 0xFFB6B9]),
        ("Mộng mơ", "Dream", [0xFFFFD2, 0xFCBAD3, 0xAA96DA, 0xA8D8EA]),
        ("Bến cảng", "Harbour", [0xFC5185, 0xF5F5F5, 0x3FC1C9, 0x364F6B]),
        ("Hoàng hôn", "Sunset", [0x355C7D, 0x6C5B7B, 0xC06C84, 0xF67280]),
        ("Than hồng", "Ember", [0xFFD460, 0xF07B3F, 0xEA5455, 0x2D4059]),
        ("Nhiệt đới", "Tropic", [0xFFDE7D, 0xF6416C, 0xF8F3D4, 0x00B8A9]),
        ("Rực rỡ", "Pop", [0xFF165D, 0xFF9A00, 0xF6F7D7, 0x3EC1D3]),
        ("Kem trái cây", "Sorbet", [0xFFAAA5, 0xFFD3B6, 0xDCEDC1, 0xA8E6CF]),
        ("Mạnh mẽ", "Bold", [0xF05454, 0x30475E, 0x222831, 0xDDDDDD]),
        ("Đêm", "Night", [0xEEEEEE, 0xFFD369, 0x393E46, 0x222831]),
        ("Gỉ sét", "Rust", [0xFF5722, 0xEEEEEE, 0x00ADB5, 0x303841]),
        ("Bờ biển", "Coast", [0xFF7E67, 0xFAFAFA, 0xA2D5F2, 0x07689F]),
        ("Cực quang", "Aurora", [0x521262, 0x6639A6, 0x3490DE, 0x6FE7DD]),
        ("Chạng vạng", "Dusk", [0x583D72, 0x9F5F80, 0xFF8474, 0xFFC996]),
        ("Kẹo ngọt", "Candy", [0xFF8AAE, 0xFFB2A6, 0xFFF89A, 0x9ADCFF]),
        ("Đất nung", "Earth", [0x9DAB86, 0xDED7B1, 0xE08F62, 0xCC7351]),
        ("Rừng", "Forest", [0xFBFADA, 0xADBC9F, 0x436850, 0x12372A]),
        ("Retro", "Retro", [0x00B7CD, 0xFFF1D1, 0xFF9100, 0xDF301C]),
    ]

    /// Phim: bản tự vẽ trông như Form (Form của hệ thống không vẽ ra PDF được): cùng các phần, cùng thứ tự
    private func filmBody(_ film: FilmFrame) -> some View {
        func head(_ t: String) -> some View {
            Text(t).font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 20).padding(.top, 26).padding(.bottom, 10)
        }
        func box<V: View>(@ViewBuilder _ v: () -> V) -> some View {
            VStack(alignment: .leading, spacing: 0) { v() }
                .padding(.horizontal, 20).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        return VStack(spacing: 0) {
            FilmNavBar(title: L("Sửa danh mục"), leading: L("Huỷ"), trailing: L("Lưu"), trailingPressed: film.pressed["save"] ?? 0)
            FilmScroll {
                VStack(alignment: .leading, spacing: 0) {
                    previewCard.padding(.top, 10)
                    head(L("Tên"))
                    box { Text(shownName).font(.system(size: 17)).frame(height: 44) }
                    head(L("Biểu tượng"))
                    box {
                        HStack(spacing: 12) {
                            Image(systemName: "face.smiling").font(.system(size: 18, weight: .semibold))
                                .frame(width: 34, height: 34).background(Palette.pill, in: Circle())
                            Text(L("Tất cả biểu tượng")).font(.system(size: 17))
                        }
                        .frame(height: 52)
                        Divider().padding(.leading, 46)
                        emojiGrid.padding(.vertical, 6)
                    }
                    Text(L("Chọn nhanh ở trên, hoặc mở bàn phím Emoji để chọn bất kỳ biểu tượng nào của iOS."))
                        .font(.system(size: 13)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 8)
                    head(L("Màu"))
                    box { VStack(spacing: 10) { colorRows }.font(.system(size: 17)).padding(.vertical, 8) }
                }
                .padding(.horizontal, 16).padding(.bottom, 60)
            }
        }
        .background(Color(hex: 0xF2F2F7))
        .environment(\.colorScheme, .light)
    }

    private var form: some View {
        NavigationStack {
            BlurForm {
                // Gắn ở cả mục (không ở hàng): BlurForm (iOS 18–25) dựng lại từng hàng, mất các tuỳ chỉnh gắn trên hàng
                Section { previewCard }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .cardless()

                Section {
                    TextField(L("Ví dụ: Thú cưng"), text: $name)
                        .focused($nameFocused)
                        .submitLabel(.done)
                } header: {
                    Text(L("Tên"))
                } footer: {
                    if duplicate { Text(L("Đã có danh mục tên này.")).foregroundStyle(.red) }
                }

                Section {
                    // Ảnh riêng: chọn từ thư viện ảnh, phủ kín ô vuông; có ảnh thì biểu tượng chỉ là phụ (dùng khi xoá ảnh)
                    // Ảnh danh mục là tính năng Pro: chưa mua thì lớp chạm phủ lên mở màn mua Pro
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack(spacing: 12) {
                            Image(systemName: "photo").font(.system(size: 17, weight: .semibold))
                                .frame(width: 34, height: 34).background(Palette.pill, in: Circle())
                            Text(photo == nil ? L("Chọn ảnh") : L("Đổi ảnh")).foregroundStyle(.primary)
                            if !Pro.shared.active { ProBadge() }
                            Spacer()
                            if let photo {
                                Image(uiImage: photo).resizable().scaledToFill().frame(width: 34, height: 34)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                    .tint(.primary)
                    .overlay { if !Pro.shared.active { Color.white.opacity(0.001).onTapGesture { Pro.shared.allow(.photos) } } }
                    if photo != nil {
                        Button { withAnimation(.snappy) { photo = nil; photoChanged = true } } label: {
                            Text(L("Xoá ảnh, dùng biểu tượng")).foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text(L("Ảnh"))
                }
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                            Haptic.tap()
                            withAnimation(.snappy) { photo = img; photoChanged = true }
                        }
                        photoItem = nil
                    }
                }

                Section {
                    // Mở bàn phím Emoji của iOS: chọn được mọi biểu tượng, có cả ô tìm kiếm
                    Button { pickingEmoji = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "face.smiling").font(.system(size: 18, weight: .semibold))
                                .frame(width: 34, height: 34).background(Palette.pill, in: Circle())
                            Text(L("Tất cả biểu tượng")).foregroundStyle(.primary)
                            Spacer()
                            if !Self.emojis.contains(icon) { Text(icon).font(.system(size: 24)) }
                        }
                    }
                    .tint(.primary)
                    .background(EmojiField(isOn: $pickingEmoji) { icon = $0 }.frame(width: 1, height: 1).opacity(0.01))
                    emojiGrid
                } header: {
                    Text(L("Biểu tượng"))
                } footer: {
                    Text(L("Chọn nhanh ở trên, hoặc mở bàn phím Emoji để chọn bất kỳ biểu tượng nào của iOS."))
                }

                Section(L("Màu")) {
                    colorRows
                }

            }
            .textCase(nil)   // tiêu đề mục viết thường ở mọi bản iOS (iOS 18 trở xuống tự viết hoa)
            .screenTitle(editing == nil ? L("Danh mục mới") : L("Sửa danh mục"))
            .navigationBarTitleDisplayMode(.inline)
            // Huỷ / Lưu ở đáy, cùng kiểu hai nút to như màn nhập khoản chi và chọn ngày; phía sau mờ dần như thanh tiêu đề
            .bottomBar {
                HStack(spacing: 12) {
                    BigButton(title: L("Huỷ"), icon: "", primary: false, tint: BigButton.cancelTint) { dismiss() }
                    if trimmed.isEmpty || duplicate {
                        // Chưa lưu được: nút xám đặc (không làm mờ cả nút: mờ thì thấy xuyên nội dung cuộn phía sau)
                        Text(L("Lưu")).font(.system(size: 21, weight: .semibold)).foregroundStyle(Palette.ctaInk.opacity(0.85))
                            .frame(maxWidth: .infinity).frame(height: 56 + BigButton.inset * 2)
                            // Chưa lưu được: cùng kiểu nút Lưu mờ ở màn nhập (nút đen mờ 55%), đậm hơn xám nhạt cũ
                            .background(Capsule().fill(Palette.cta.opacity(0.55)))
                    } else {
                        BigButton(title: L("Lưu"), icon: "", primary: true) { save() }
                    }
                }
                // Sát đáy như màn nhập: cách mép dưới 16 bằng lề hai bên (vùng an toàn 34, lùi xuống 18)
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, -18)
            }
            // Mép trên vùng cuộn mờ dần (không cắt ngang dưới tiêu đề)
            .softTopEdge(fade: Color(.systemGroupedBackground), home: true)
            // Bàn phím hiện lên thì Huỷ / Lưu nằm yên ở đáy, bị bàn phím che (không bị đẩy lên đè lên ô Ảnh)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onAppear {
                if let e = editing { name = L(e.name); icon = e.icon; tone = e.tone; photo = CategoryPhotos.image(e.k) }
                else { tone = CategoryTone.custom(0xCC7351); nameFocused = true }   // danh mục mới: màu đất nung + em chó
            }
        }
    }

    private func swatchRow(_ r: Range<Int>, custom: Bool = false) -> some View {
        HStack(spacing: 0) {
            ForEach(r, id: \.self) { i in
                Button { tone = i } label: { swatch(CategoryTone.bg(i), on: fTone == i).frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(Pressable())
                    .filmPressed(film?.pressed["tone-\(i)"] ?? 0)
                    .accessibilityLabel(L("Màu %@", String(i + 1)))
                    .accessibilityAddTraits(fTone == i ? .isSelected : [])
            }
            // Ô cuối hàng: tự chọn màu bằng bảng chọn màu của iOS (lưới, phổ màu, thanh trượt RGB, mã hex)
            if custom { customSwatch.frame(maxWidth: .infinity, minHeight: 44) }
        }
    }

    /// Ô tự chọn màu: vòng cầu vồng; đang dùng màu tự chọn thì hiện chính màu đó với vòng chọn
    private var customSwatch: some View {
        let on = CategoryTone.isCustom(fTone)
        return Button { pickingColor = true } label: { ZStack {
            if on { swatch(CategoryTone.bg(fTone), on: true) }
            else {
                Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                    .frame(width: 32, height: 32)
            }
        } }
        .buttonStyle(Pressable())
        .accessibilityLabel(L("Tự chọn màu"))
        .sheet(isPresented: $pickingColor) {
            SystemColorPicker(initial: UIColor(CategoryTone.bg(fTone))) { c in
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.getRed(&r, green: &g, blue: &b, alpha: &a)
                let byte = { (v: CGFloat) in UInt32(max(0, min(255, (v * 255).rounded()))) }
                tone = CategoryTone.custom(byte(r) << 16 | byte(g) << 8 | byte(b))
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func swatch(_ c: Color, on: Bool) -> some View {
        // Vòng đang chọn nằm ngoài ô màu, cách một khe 2pt: nó nổi trên nền hàng nên màu nào, nền sáng hay tối cũng thấy
        // (vẽ đè trong ô thì chìm trên than, xanh lá đậm ở nền sáng và trên các màu nhạt ở nền tối)
        Circle().fill(c)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .padding(on ? 4.5 : 0)
            .frame(width: 32, height: 32)
            .overlay { if on { Circle().strokeBorder(Color.primary.opacity(0.8), lineWidth: 2.5) } }
    }

    private func save() {
        if let e = editing {
            // không đổi tên (đang xem bản dịch của tên gốc): giữ tên gốc, khỏi lưu chữ tiếng Anh
            store.updateCategory(e.k, name: trimmed == L(e.name) ? e.name : trimmed, icon: icon, tone: tone)
            savePhoto(e.k)
        } else {
            let k = store.addCategory(name: trimmed, icon: icon, tone: tone)
            savePhoto(k)
            onAdd(k)
        }
        dismiss()
    }

    private func savePhoto(_ k: String) {
        guard photoChanged else { return }
        if let photo { CategoryPhotos.save(photo, k: k) } else { CategoryPhotos.remove(k) }
    }
}

/// Ô nhập ẩn chỉ để bật bàn phím Emoji của iOS; chọn một biểu tượng là trả về rồi đóng bàn phím.
struct EmojiField: UIViewRepresentable {
    @Binding var isOn: Bool
    let picked: (String) -> Void

    final class Field: UITextField {
        // Mở thẳng bàn phím Emoji thay vì bàn phím chữ
        override var textInputMode: UITextInputMode? {
            UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> Field {
        let f = Field()
        f.delegate = context.coordinator
        f.tintColor = .clear
        f.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return f
    }

    func updateUIView(_ f: Field, context: Context) {
        context.coordinator.parent = self
        if isOn && !f.isFirstResponder { DispatchQueue.main.async { f.becomeFirstResponder() } }
        if !isOn && f.isFirstResponder { DispatchQueue.main.async { f.resignFirstResponder() } }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiField
        init(_ p: EmojiField) { parent = p }

        @objc func changed(_ f: UITextField) {
            // Lấy biểu tượng vừa chọn (một ký tự hiển thị, kể cả emoji ghép nhiều mã)
            guard let last = f.text?.last, last.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0x238C }) else {
                f.text = ""; return
            }
            parent.picked(String(last))
            f.text = ""
            parent.isOn = false
        }

        func textFieldDidEndEditing(_ f: UITextField) { if parent.isOn { parent.isOn = false } }
    }
}

/// Hướng dẫn thêm widget, gán nút Tác vụ và dùng Phím tắt.
struct QuickAccessHelp: View {
    var body: some View {
        BlurForm {
            Section {
                step(1, "Ở màn hình chính, chạm và giữ vào chỗ trống đến khi biểu tượng rung.")
                step(2, "Bấm Sửa › Thêm tiện ích, tìm \"Pay\".")
                step(3, "Chọn \"Chi tiêu hôm nay\" (cỡ vừa có nút Quét QR, Nói, Nhập) hoặc \"Nói để ghi\" (chạm là nghe luôn).")
            } header: {
                Label(L("Widget màn hình chính"), systemImage: "square.grid.2x2.fill")
            }

            Section {
                step(1, "Chạm và giữ màn hình khoá, bấm Tuỳ chỉnh › Màn hình khoá.")
                step(2, "Bấm vùng widget dưới đồng hồ, chọn Pay › \"Nói để ghi\" (nút micro tròn).")
                step(3, "iOS 18 trở lên: bấm nút ở góc dưới (đèn pin, camera), đổi thành \"Pay: Ghi bằng giọng nói\".")
            } header: {
                Label(L("Màn hình khoá: nút micro"), systemImage: "lock.fill")
            } footer: {
                Text(L("Chạm nút micro, mở khoá xong là Pay nghe luôn. Màn hình khoá cũng có nút quét QR và số đã chi hôm nay."))
            }

            Section {
                step(1, "Mở Cài đặt › Nút Tác vụ, vuốt đến Điều khiển.")
                step(2, "Bấm Chọn điều khiển, tìm \"Pay: Ghi bằng giọng nói\".")
                step(3, "Nhấn giữ nút Tác vụ: Pay mở và nghe luôn. Nói \"35k cafe\", ngừng nói là tự ghi.")
            } header: {
                Label(L("Nút Tác vụ: ghi bằng giọng nói"), systemImage: "mic.fill")
            } footer: {
                Text(L("Cần iPhone 15 Pro trở lên, iOS 18 trở lên. Nói được nhiều kiểu: \"35 nghìn cà phê\", \"1tr2 tiền nhà\", \"grab 52k\". Danh mục tự đoán theo ghi chú."))
            }

            Section {
                step(1, "Mở Cài đặt › Nút Tác vụ, vuốt đến Điều khiển.")
                step(2, "Bấm Chọn điều khiển, tìm \"Pay: Quét QR\".")
                step(3, "Nhấn giữ nút Tác vụ là mở camera quét ngay.")
            } header: {
                Label(L("Nút Tác vụ: quét QR"), systemImage: "qrcode.viewfinder")
            } footer: {
                Text(L("Cần iOS 18 trở lên. Nút Tác vụ chỉ gán được một việc: chọn ghi bằng giọng nói hoặc quét QR. Nút \"Pay: Quét QR\" cũng thêm được vào Trung tâm điều khiển."))
            }

            Section {
                step(1, "Nói \"Ghi chi tiêu bằng Pay\" với Siri, rồi nói khoản chi. Hoặc \"Quét QR bằng Pay\".")
                step(2, "Hoặc mở app Phím tắt, hai lệnh này có sẵn trong mục Pay.")
            } header: {
                Label(L("Siri và Phím tắt"), systemImage: "wand.and.stars")
            }
        }
        .textCase(nil)   // tiêu đề mục viết thường ở mọi bản iOS (iOS 18 trở xuống tự viết hoa)
        .softTopEdge(fade: Color(.systemGroupedBackground), home: true)
        .screenTitle(L("Truy cập nhanh"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.08), in: Circle())
            Text(L(text))
        }
    }
}

/// Bảng chọn màu của iOS (lưới, phổ màu, thanh trượt RGB, mã hex), không chọn độ trong suốt.
struct SystemColorPicker: UIViewControllerRepresentable {
    let initial: UIColor
    let picked: (UIColor) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(picked) }

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let vc = UIColorPickerViewController()
        vc.supportsAlpha = false
        vc.selectedColor = initial
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIColorPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        let picked: (UIColor) -> Void
        init(_ picked: @escaping (UIColor) -> Void) { self.picked = picked }
        func colorPickerViewController(_ vc: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) { picked(color) }
    }
}

/// Cách cài tự động hoá Phím tắt để mỗi lần trả bằng Apple Pay là Pay tự ghi một khoản chi
struct ApplePayHelp: View {
    var body: some View {
        BlurForm {
            Section {
                step(1, L("Mở app Phím tắt, chọn thẻ Tự động hoá, bấm + rồi chọn Giao dịch."))
                step(2, L("Chọn thẻ trong Ví muốn theo dõi, đặt Chạy ngay (không cần xác nhận), bấm Tiếp."))
                step(3, L("Chọn Tác vụ mới, tìm Pay, chọn Ghi giao dịch thẻ."))
                step(4, L("Chạm ô Số tiền, chọn biến Giao dịch rồi chọn Số tiền. Chạm ô Người bán, chọn Giao dịch rồi chọn Người bán."))
                step(5, L("Bấm Xong. Từ giờ mỗi lần quẹt thẻ, Pay tự ghi khoản chi, danh mục đoán theo tên cửa hàng."))
            } footer: {
                Text(L("Phím tắt chỉ chạy được với thẻ đã thêm vào Ví trên iPhone này. Khoản tự ghi sửa hoặc xoá như khoản thường."))
            }
        }
        .softTopEdge(fade: Color(.systemGroupedBackground), home: true)
        .screenTitle(L("Tự ghi khi trả Apple Pay"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)").font(.system(size: 15, weight: .bold, design: .rounded))
                .frame(width: 24, height: 24).background(Palette.pill, in: Circle())
            Text(text).font(.system(size: 16))
        }
        .padding(.vertical, 4)
    }
}

/// Vòng tích đặc của app Shot (Tabler circle-check): hình tròn đặc, dấu tích khoét rỗng
struct CircleCheck: Shape {
    func path(in r: CGRect) -> Path {
        let k = min(r.width, r.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * k, y: r.minY + y * k) }
        let circle = Path(ellipseIn: CGRect(origin: p(2, 2), size: CGSize(width: 20 * k, height: 20 * k)))
        var tick = Path()
        tick.move(to: p(9, 12)); tick.addLine(to: p(11, 14)); tick.addLine(to: p(15, 10))
        return circle.subtracting(tick.strokedPath(StrokeStyle(lineWidth: 2 * k, lineCap: .round, lineJoin: .round)))
    }
}
