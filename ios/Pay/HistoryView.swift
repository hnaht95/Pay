import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    /// Chỉ xem một danh mục (mở từ ô danh mục ở màn hình chính); nil = toàn bộ lịch sử
    var category: String? = nil
    @State private var editing: EntryMode?
    @State private var menu: AppMenuSpec?

    var body: some View {
        NavigationStack {
            let groups = grouped()
            List {
                if groups.isEmpty {
                    Text(L("Chưa có khoản nào.")).font(.system(size: 17)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(40)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                ForEach(groups, id: \.0) { day, list in
                    Section {
                        ForEach(list) { e in
                            TapHold(tap: { editing = .edit(e) }, hold: { menu = expenseMenu(e, store: store) { editing = .edit(e) } }) {
                                ExpenseRow(e: e, repeats: store.rule(for: e) != nil, dot: category != nil)
                            }
                            .expenseSwipe(delete: { store.remove(id: e.id) })
                        }
                    } header: {
                        HStack {
                            Text(title(day)); Spacer(); Text("\(fmt(list.reduce(0) { $0 + $1.a }))đ")
                        }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                        .textCase(nil)
                    }
                    .listSectionSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .background(Palette.surface)
            .edgeBack { dismiss() }
            .navigationTitle(category.map { Category.get($0).name } ?? L("Lịch sử chi tiêu"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Đang xem một danh mục: nhập luôn khoản mới vào danh mục đó
                if let category {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { editing = .new(cat: category) } label: { Image(systemName: "plus") }
                            .accessibilityLabel(L("Nhập khoản %@", Category.get(category).name))
                    }
                }
            }
        }
        .fullScreenCover(item: $editing) { EntryView(mode: $0).environmentObject(store) }
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 24) }
        .appMenu($menu)
    }

    private func grouped() -> [(Date, [Expense])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: store.items.filter { category == nil || $0.c == category }) { cal.startOfDay(for: $0.date) }
        return dict.keys.sorted(by: >).map { ($0, dict[$0]!.sorted { $0.t > $1.t }) }
    }

    private func title(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return L("Hôm nay") }
        if cal.isDateInYesterday(d) { return L("Hôm qua") }
        if Lang.isEnglish {
            let f = DateFormatter(); f.locale = Lang.locale; f.dateFormat = "EEEE, MMM d"
            return f.string(from: d)
        }
        let dow = ["Chủ nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"][cal.component(.weekday, from: d) - 1]
        let c = cal.dateComponents([.day, .month], from: d)
        return "\(dow), \(c.day!)/\(c.month!)"
    }
}
