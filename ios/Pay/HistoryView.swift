import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @EnvironmentObject var store: Store
    @State private var editing: EntryMode?

    var body: some View {
        NavigationStack {
            ScrollView {
                let groups = grouped()
                if groups.isEmpty {
                    Text("Chưa có khoản nào.").font(.system(size: 17)).foregroundStyle(.secondary).padding(40)
                }
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(groups, id: \.0) { day, list in
                        HStack {
                            Text(title(day)); Spacer(); Text("\(fmt(list.reduce(0) { $0 + $1.a }))đ")
                        }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 4).padding(.top, 12)
                        ForEach(list) { e in
                            Button { editing = .edit(e) } label: { ExpenseRow(e: e) }.buttonStyle(Pressable())
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(Palette.surface)
            .navigationTitle("Lịch sử chi tiêu")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fullScreenCover(item: $editing) { EntryView(mode: $0).environmentObject(store) }
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 24) }
    }

    private func grouped() -> [(Date, [Expense])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: store.sorted.prefix(500)) { cal.startOfDay(for: $0.date) }
        return dict.keys.sorted(by: >).map { ($0, dict[$0]!.sorted { $0.t > $1.t }) }
    }

    private func title(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Hôm nay" }
        if cal.isDateInYesterday(d) { return "Hôm qua" }
        let dow = ["Chủ nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"][cal.component(.weekday, from: d) - 1]
        let c = cal.dateComponents([.day, .month], from: d)
        return "\(dow), \(c.day!)/\(c.month!)"
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var importing = false
    @State private var jsonURL: URL?
    @State private var csvURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("App ngân hàng", selection: $store.appId) {
                        Section("Mở sẵn người nhận + số tiền") {
                            ForEach(BankData.apps.filter(\.fill)) { Text($0.name).tag($0.id) }
                        }
                        Section("Chỉ mở app (quét lại QR)") {
                            ForEach(BankData.apps.filter { !$0.fill }) { Text($0.name).tag($0.id) }
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text(store.bankApp.fill ? "Mở sẵn người nhận và số tiền, không phải quét lại." : "App này chỉ mở được, bạn sẽ quét lại mã QR trong app.")
                }

                Section {
                    if let jsonURL { ShareLink("Sao lưu", item: jsonURL) }
                    Button("Khôi phục từ file sao lưu") { importing = true }
                    if let csvURL { ShareLink("Xuất CSV (Excel)", item: csvURL) }
                } footer: {
                    Text("Dữ liệu chỉ lưu trên iPhone này. Nên sao lưu thỉnh thoảng. File sao lưu của bản web cũng khôi phục được ở đây.")
                }
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { jsonURL = store.exportJSON(); csvURL = store.exportCSV() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { store.importBackup(from: url) }
        }
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 24) }
    }
}
