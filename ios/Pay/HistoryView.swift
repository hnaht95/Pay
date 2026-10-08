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
