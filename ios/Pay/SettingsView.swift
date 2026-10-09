import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var confirmErase = false
    @State private var syncing = false
    @State private var jsonURL: URL?
    @State private var csvURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section { summary }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                budgetSection
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
        .task(id: store.items) { jsonURL = store.exportJSON(); csvURL = store.exportCSV() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { store.importBackup(from: url) }
        }
        .confirmationDialog("Xoá tất cả khoản chi?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Xoá tất cả", role: .destructive) { store.eraseAll() }
        } message: {
            Text(store.cloudOn ? "Các máy khác đang đồng bộ iCloud cũng sẽ bị xoá. Nên sao lưu trước." : "Không hoàn tác được. Nên sao lưu trước.")
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
            HStack {
                icon("chart.pie.fill", .pink)
                Text("Ngân sách tháng").lineLimit(1).layoutPriority(1).padding(.leading, 8)
                Spacer(minLength: 8)
                TextField("Chưa đặt", value: budgetValue, format: .number.locale(Locale(identifier: "vi_VN")))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 60, maxWidth: 130)
                Text("đ").foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach([3, 5, 8, 10, 15], id: \.self) { tr in
                    Button("\(tr)tr") { store.budget = tr * 1_000_000 }
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(store.budget == tr * 1_000_000 ? Color.pink.opacity(0.2) : Color.primary.opacity(0.06), in: Capsule())
                        .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                if store.budget > 0 {
                    Button("Bỏ") { store.budget = 0 }.font(.system(size: 15)).foregroundStyle(.red).buttonStyle(.plain)
                }
            }
            if let b = store.budgetStatus() {
                VStack(alignment: .leading, spacing: 6) {
                    BudgetBar(s: b)
                    Text("\(b.label) · đã dùng \(Int((b.ratio * 100).rounded()))%").font(.system(size: 14)).foregroundStyle(b.color)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Ngân sách")
        } footer: {
            Text("Màn hình chính và widget hiện số còn lại và mức nên tiêu mỗi ngày. Dùng từ 80% thì chuyển màu cam, vượt thì màu đỏ.")
        }
    }

    /// 0 hiện là ô trống "Chưa đặt".
    private var budgetValue: Binding<Int?> {
        Binding(get: { store.budget > 0 ? store.budget : nil }, set: { store.budget = max($0 ?? 0, 0) })
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

/// Hướng dẫn thêm widget, gán nút Tác vụ và dùng Phím tắt.
struct QuickAccessHelp: View {
    var body: some View {
        Form {
            Section {
                step(1, "Ở màn hình chính, chạm và giữ vào chỗ trống đến khi biểu tượng rung.")
                step(2, "Bấm Sửa › Thêm tiện ích, tìm \"Pay\".")
                step(3, "Chọn cỡ nhỏ (chạm là quét QR) hoặc cỡ vừa (có nút Quét QR và Nhập).")
            } header: {
                Label("Widget màn hình chính", systemImage: "square.grid.2x2.fill")
            } footer: {
                Text("Màn hình khoá cũng có widget: số đã chi hôm nay, hoặc nút tròn quét QR.")
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
