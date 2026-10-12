import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    /// Chỉ xem một danh mục (mở từ ô danh mục ở màn hình chính); nil = toàn bộ lịch sử
    var category: String? = nil
    @State private var editing: EntryMode?
    @State private var menu: AppMenuSpec?
    /// Ô tìm: lọc theo ghi chú hoặc tên danh mục, không phân biệt dấu ("ca phe" ra "cà phê")
    @State private var query = ""
    @State private var titleEdge: CGFloat = 0
    @FocusState private var searching: Bool

    var body: some View {
        NavigationStack {
            let groups = grouped()
            List {
                // Đang tìm: một dòng tổng của các khoản tìm được
                if !query.isEmpty, !groups.isEmpty {
                    let found = groups.flatMap(\.1)
                    HStack {
                        Text(found.count == 1 ? L("1 khoản") : L("%ld khoản", found.count))
                        Spacer()
                        Text(fmt(found.reduce(0) { $0 + $1.a })).fontWeight(.semibold)
                    }
                    .font(.system(size: 16))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                if groups.isEmpty {
                    Text(query.isEmpty ? L("Chưa có khoản nào.") : L("Không tìm thấy khoản nào.")).font(.system(size: 17)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(40)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                ForEach(groups, id: \.0) { day, list in
                    Section {
                        // Tiêu đề ngày là một dòng thường, cuộn đi cùng danh sách (tiêu đề nhóm của List kiểu plain dính ở đầu
                        // màn khi cuộn, nền trong suốt nên chồng lên nhau và lên khoản đang cuộn qua)
                        HStack {
                            Text(title(day)); Spacer(); Text("\(fmt(list.reduce(0) { $0 + $1.a }))")
                        }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.top, 14).padding(.bottom, 2)
                        .titleEdgeBlur(titleEdge)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                        ForEach(list) { e in
                            // Chạm: mở xem; "Sửa khoản này" trong bảng nhấn giữ: vào thẳng trạng thái sửa
                            TapHold(tap: { editing = .edit(e) }, hold: { menu = expenseMenu(e, store: store) { editing = .editNow(e) } }) {
                                ExpenseRow(e: e, repeats: store.rule(for: e) != nil)
                            }
                            .titleEdgeBlur(titleEdge)
                            .expenseSwipe(delete: { withAnimation(.snappy(duration: 0.3)) { store.remove(id: e.id) } })
                        }
                    }
                    .listSectionSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .background(Palette.surface)
            // Tiêu đề và ô tìm tự vẽ, ghim trên vùng cuộn (thay thanh tiêu đề của hệ thống, cao thấp khác nhau theo bản iOS);
            // nội dung cuộn lên chui xuống dưới ô tìm, nhoè dần. Khoảng trên tiêu đề tới mép tấm bằng khoảng dưới tới ô tìm (~20 pt)
            .softTitleBar(plain: true) {
                VStack(spacing: 0) {
                    Text(category.map { Category.get($0).name } ?? L("Lịch sử chi tiêu")).font(.system(size: 21, weight: .bold)).lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Self.titleTop).padding(.bottom, 18)
                    // Ô tìm tự vẽ, cùng kiểu ô ghi chú ở màn nhập (nền nhạt bo 18, không viền, không bóng) thay cho thanh tìm của iOS
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary)
                        TextField(L("Tìm khoản chi"), text: $query)
                            .font(.system(size: 17))
                            .focused($searching)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                        if !query.isEmpty {
                            Button { query = "" } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    // Nền đục (màu nền tấm + lớp nhạt): nội dung cuộn chui xuống dưới không lộ qua ô
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { titleEdge = $0 }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $editing) { EntryView(mode: $0).id($0.id).environmentObject(store).sheetGrabber() }
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 24) }
        .appMenu($menu)
        .sheetGrabber()
    }

    private static let titleTop: CGFloat = 20

    private func grouped() -> [(Date, [Expense])] {
        let cal = Calendar.current
        // Lọc theo danh mục đang có (như Category.get), không theo mã thô: khoản của danh mục đã xoá hoặc chưa đồng bộ
        // về máy này được vẽ là "Khác" ở mọi nơi nên cũng phải nằm trong danh sách "Khác".
        // Tính sẵn tập mã một lần, khỏi dựng lại Category.all cho từng khoản của cả lịch sử
        let all = Category.all, known = Set(all.map(\.k)), other = all.last!.k
        let canon = { (k: String) in known.contains(k) ? k : other }
        let want = category.map(canon)
        let q = Store.noteKey(query)
        let hit = { (e: Expense) -> Bool in
            q.isEmpty || Store.noteKey(e.n ?? "").contains(q) || Store.noteKey(Category.get(e.c).name).contains(q)
        }
        let dict = Dictionary(grouping: store.items.filter { (want == nil || canon($0.c) == want) && hit($0) }) { cal.startOfDay(for: $0.date) }
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
