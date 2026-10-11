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
                            // Chạm: mở xem; "Sửa khoản này" trong bảng nhấn giữ: vào thẳng trạng thái sửa
                            TapHold(tap: { editing = .edit(e) }, hold: { menu = expenseMenu(e, store: store) { editing = .editNow(e) } }) {
                                ExpenseRow(e: e, repeats: store.rule(for: e) != nil)
                            }
                            .expenseSwipe(delete: { withAnimation(.snappy(duration: 0.3)) { store.remove(id: e.id) } })
                        }
                    } header: {
                        HStack {
                            Text(title(day)); Spacer(); Text("\(fmt(list.reduce(0) { $0 + $1.a }))")
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
            .screenTitle(category.map { Category.get($0).name } ?? L("Lịch sử chi tiêu"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Đang xem một danh mục: nhập luôn khoản mới vào danh mục đó
                if let category {
                    // Nút tròn nền xám như các nút đầu trang khác của app, không dùng viên kính xanh mặc định của iOS
                    if #available(iOS 26.0, *) {
                        ToolbarItem(placement: .topBarTrailing) { addButton(category) }.sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .topBarTrailing) { addButton(category) }
                    }
                }
            }
        }
        .fullScreenCover(item: $editing) { EntryView(mode: $0).environmentObject(store) }
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 24) }
        .appMenu($menu)
        .sheetGrabber()
    }

    private func addButton(_ category: String) -> some View {
        Button { editing = .new(cat: category) } label: {
            // plus.circle.fill: vòng xanh lá của app (như sóng âm), dấu cộng trắng
            Image(systemName: "plus.circle.fill").font(.system(size: 26))
                .foregroundStyle(.white, Color(hex: 0x61BE6E))
                .frame(width: 40, height: 40).contentShape(Rectangle())
        }
        .buttonStyle(Pressable())
        .accessibilityLabel(L("Nhập khoản %@", Category.get(category).name))
    }

    private func grouped() -> [(Date, [Expense])] {
        let cal = Calendar.current
        // Lọc theo danh mục đang có (như Category.get), không theo mã thô: khoản của danh mục đã xoá hoặc chưa đồng bộ
        // về máy này được vẽ là "Khác" ở mọi nơi nên cũng phải nằm trong danh sách "Khác".
        // Tính sẵn tập mã một lần, khỏi dựng lại Category.all cho từng khoản của cả lịch sử
        let all = Category.all, known = Set(all.map(\.k)), other = all.last!.k
        let canon = { (k: String) in known.contains(k) ? k : other }
        let want = category.map(canon)
        let dict = Dictionary(grouping: store.items.filter { want == nil || canon($0.c) == want }) { cal.startOfDay(for: $0.date) }
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
