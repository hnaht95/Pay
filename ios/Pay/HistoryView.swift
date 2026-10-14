import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    /// Chỉ xem một danh mục (mở từ ô danh mục ở màn hình chính); nil = toàn bộ lịch sử
    var category: String? = nil
    @State private var editing: EntryMode?
    @State private var balanceOpen = false
    @State private var menu: AppMenuSpec?
    /// Ô tìm: lọc theo ghi chú hoặc tên danh mục, không phân biệt dấu ("ca phe" ra "cà phê")
    @State private var query = ""
    @FocusState private var searching: Bool
    /// Xem dạng lưới ảnh (chung một lựa chọn với mục Gần đây ở trang chủ)
    @AppStorage("recentGrid") private var grid = false

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
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 12))
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
                            Text(title(day)); Spacer(); Text("\(fmt(list.filter { !$0.isIncome && !$0.isAdjust }.reduce(0) { $0 + $1.a }))")
                        }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.top, 14).padding(.bottom, 2)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 12))
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                        if grid {
                            // Lưới ảnh 3 cột như mục Gần đây ở trang chủ: cả ngày là một hàng của List
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                                ForEach(list) { e in
                                    TapHold(tap: { if e.isAdjust { balanceOpen = true } else { editing = .edit(e) } }, hold: { menu = expenseMenu(e, store: store) { editing = .editNow(e) } }) {
                                        ExpenseTile(e: e)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 8))
                            .listRowBackground(Color.clear).listRowSeparator(.hidden)
                        } else {
                            ForEach(list) { e in
                                // Chạm: mở xem; "Sửa khoản này" trong bảng nhấn giữ: vào thẳng trạng thái sửa
                                TapHold(tap: { if e.isAdjust { balanceOpen = true } else { editing = .edit(e) } }, hold: { menu = expenseMenu(e, store: store) { editing = .editNow(e) } }) {
                                    ExpenseRow(e: e, repeats: store.rule(for: e) != nil)
                                }
                                .expenseSwipe(delete: { withAnimation(.snappy(duration: 0.3)) { store.remove(id: e.id) } })
                            }
                        }
                    }
                    .listSectionSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Nội dung cách mép phải màn 8, đúng như Gần đây ở trang chủ (xem expenseSwipe: nút xoá cách thẻ và mép màn bằng
            // nhau); bên trái hàng tự lùi 16. iOS 26+: lề nội dung (thanh cuộn vẫn sát mép màn); iOS cũ: lùi cả danh sách vì
            // lề nội dung làm iOS 18 đặt nút xoá khác, hàng trượt xa hơn
            .historyTrailingInset()
            .background(Palette.surface)
            // Tiêu đề và ô tìm tự vẽ, ghim trên vùng cuộn (thay thanh tiêu đề của hệ thống, cao thấp khác nhau theo bản iOS);
            // nội dung cuộn lên cắt gọn ở vạch dưới ô tìm. Khoảng trên tiêu đề tới mép tấm bằng khoảng dưới tới ô tìm (~20 pt)
            .softTitleBar {
                VStack(spacing: 0) {
                    Text(category.map { Category.get($0).name } ?? L("Lịch sử chi tiêu")).font(.system(size: 21, weight: .bold)).lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Self.titleTop).padding(.bottom, 18)
                    // Ô tìm tự vẽ, cùng kiểu ô ghi chú ở màn nhập (nền nhạt bo 18, không viền, không bóng) thay cho thanh tìm của iOS
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 19, weight: .medium)).foregroundStyle(.secondary)
                        TextField(L("Tìm khoản chi"), text: $query)
                            .font(.system(size: 18))
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
                    .padding(.horizontal, 18).padding(.vertical, 18)
                    // Nền đục (màu nền tấm + lớp nhạt): nội dung cuộn chui xuống dưới không lộ qua ô
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    // Cạnh ô tìm: đổi kiểu xem danh sách / lưới ảnh (cùng nút ở mục Gần đây)
                    .safeAreaInset(edge: .trailing, spacing: 10) {
                        Button { withAnimation(.snappy(duration: 0.3)) { grid.toggle() } } label: {
                            // Cùng cỡ chữ thì hình ba vạch nhỏ hơn hẳn hình hai tấm ảnh (đo: 85×81 so với 109×126): tăng cỡ ba vạch, giảm cỡ hai tấm
                            // cho hai biểu tượng trông to bằng nhau (~18×17 và ~17×20 điểm)
                            Image(systemName: grid ? "lineweight" : "rectangle.portrait.on.rectangle.portrait.angled.fill")
                                .font(.system(size: grid ? 21 : 16, weight: .semibold))
                                .frame(width: 58, height: 58)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(Pressable()).foregroundStyle(.primary)
                        .accessibilityLabel(grid ? L("Xem dạng danh sách") : L("Xem dạng lưới ảnh"))
                    }
                    .padding(.horizontal, 16).padding(.bottom, 16)
                    // Vạch ngăn mảnh, rộng bằng ô tìm: nội dung cuộn lên cắt gọn ngay dưới vạch
                    Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1).padding(.horizontal, 16)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $editing) { EntryView(mode: $0).id($0.id).environmentObject(store).sheetGrabber() }
        .sheet(isPresented: $balanceOpen) { BalanceSheet().environmentObject(store).sheetGrabber() }
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
        // Lịch sử chung có cả tiền vào; mở từ một danh mục chi thì chỉ khoản chi
        let dict = Dictionary(grouping: (category == nil ? store.all : store.items).filter { (want == nil || canon($0.c) == want) && hit($0) }) { cal.startOfDay(for: $0.date) }
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

private extension View {
    @ViewBuilder func historyTrailingInset() -> some View {
        if #available(iOS 26.0, *) { contentMargins(.trailing, 8, for: .scrollContent) } else { padding(.trailing, 8) }
    }
}
