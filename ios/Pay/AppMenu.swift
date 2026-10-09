import SwiftUI

/// Một lựa chọn trong bảng nhấn giữ.
struct AppMenuItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    var subtitle: String? = nil
    var danger = false
    let run: () -> Void
}

/// Nội dung bảng nhấn giữ: đầu bảng (biểu tượng, tên, dòng phụ) và các lựa chọn.
struct AppMenuSpec: Identifiable {
    let id = UUID()
    let icon: AnyView
    let title: String
    var subtitle: String? = nil
    let items: [AppMenuItem]
}

/// Bảng tuỳ chọn khi nhấn giữ, vẽ theo kiểu của app (thay menu mặc định của iOS):
/// thẻ trắng bo tròn giữa màn hình, nền phía sau tối đi, chạm ra ngoài là đóng.
struct AppMenu: View {
    let spec: AppMenuSpec
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture(perform: close)
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    spec.icon
                    VStack(alignment: .leading, spacing: 3) {
                        Text(spec.title).font(.system(size: 19, weight: .bold)).lineLimit(1)
                        if let s = spec.subtitle {
                            Text(s).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
                VStack(spacing: 4) {
                    ForEach(spec.items) { item in
                        Button { close(); item.run() } label: { row(item) }
                            .buttonStyle(Pressable())
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 10)
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
            .padding(.horizontal, 24)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    private func row(_ item: AppMenuItem) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.icon).font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(item.danger ? Palette.danger.opacity(0.12) : Palette.pill, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 17, weight: .medium)).lineLimit(1)
                if let s = item.subtitle {
                    Text(s).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(item.danger ? Palette.danger : .primary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

extension View {
    /// Hiện bảng nhấn giữ phủ toàn màn hình khi `spec` khác nil.
    func appMenu(_ spec: Binding<AppMenuSpec?>) -> some View {
        overlay {
            if let s = spec.wrappedValue {
                AppMenu(spec: s) { withAnimation(.easeOut(duration: 0.2)) { spec.wrappedValue = nil } }
                    .zIndex(2)
            }
        }
        .animation(.spring(duration: 0.32, bounce: 0.25), value: spec.wrappedValue?.id)
    }
}

/// Chạm và nhấn giữ trên cùng một ô: chạm chạy `tap`, giữ thì rung nhẹ rồi chạy `hold`; đang nhấn thì ô thu nhỏ một chút.
/// Dùng thay Button + contextMenu để mở bảng tự vẽ; vẫn cuộn được khi kéo bắt đầu trên ô.
struct TapHold<Content: View>: View {
    var tap: (() -> Void)? = nil
    let hold: () -> Void
    @ViewBuilder let content: Content
    /// Lúc vừa nhấn giữ: lần nhả tay ngay sau đó không tính là chạm
    @State private var heldAt = Date.distantPast

    var body: some View {
        // Dùng Button (không phải onTapGesture) để vuốt xoá trong danh sách vẫn chạy
        Button {
            guard Date().timeIntervalSince(heldAt) > 0.8 else { return }
            tap?()
        } label: { content.contentShape(Rectangle()) }
        .buttonStyle(Pressable())
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in
            heldAt = Date()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            hold()
        })
        .accessibilityAction(named: Text(L("Tuỳ chọn")), hold)
    }
}

/// Bảng nhấn giữ của một khoản chi: Sửa, Lặp hằng tháng / Bỏ lặp, Xoá.
@MainActor
func expenseMenu(_ e: Expense, store: Store, edit: @escaping () -> Void) -> AppMenuSpec {
    let c = Category.get(e.c)
    let f = DateFormatter(); f.dateFormat = "HH:mm, dd/MM"
    if Lang.isEnglish { f.locale = Lang.locale; f.dateFormat = "HH:mm, MMM d" }
    var items = [AppMenuItem(icon: "pencil", title: L("Sửa khoản này"), run: edit)]
    if let r = store.rule(for: e) {
        items.append(AppMenuItem(icon: "xmark.circle", title: L("Bỏ lặp hằng tháng"), subtitle: L("Đang tự ghi vào ngày %@ mỗi tháng", String(r.day))) { store.stopRepeating(r) })
    } else {
        items.append(AppMenuItem(icon: "repeat", title: L("Lặp hằng tháng"),
                                 subtitle: L("Tự ghi vào ngày %@ mỗi tháng", String(Calendar.current.component(.day, from: e.date)))) { store.repeatMonthly(e) })
    }
    items.append(AppMenuItem(icon: "trash.fill", title: L("Xoá"), danger: true) { store.remove(id: e.id) })
    return AppMenuSpec(icon: AnyView(CategoryIcon(c: c, size: 30).frame(width: 56, height: 56)
                        .background(c.color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))),
                       title: "\(e.n?.isEmpty == false ? e.n! : c.name) · \(fmt(e.a))",
                       subtitle: "\(c.name) · \(f.string(from: e.date))", items: items)
}

extension View {
    /// Nhấn giữ để mở bảng tự vẽ (không có hành động chạm)
    func onHold(_ action: @escaping () -> Void) -> some View { TapHold(hold: action) { self } }
}
