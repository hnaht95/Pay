import SwiftUI

/// Một lựa chọn trong bảng nhấn giữ.
struct AppMenuItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    var subtitle: String? = nil
    var danger = false
    /// Biểu tượng đã có sẵn vòng tròn (vd pencil.tip.crop.circle): không vẽ nền tròn, vẽ to bằng ô nền
    var plain = false
    /// Màu riêng của biểu tượng (Tối giản: luôn đen / trắng theo chữ)
    var tint: Color? = nil
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
    /// Dựng phim: mức hiện của bảng (0…1) và lựa chọn đang bị nhấn
    var shown: CGFloat = 1
    var pressed: (index: Int, amount: CGFloat)? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.3 * Double(shown)).ignoresSafeArea().onTapGesture(perform: close)
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
                    ForEach(Array(spec.items.enumerated()), id: \.element.id) { i, item in
                        Button { close(); item.run() } label: { row(item) }
                            .buttonStyle(Pressable())
                            .filmPressed(pressed?.index == i ? pressed!.amount : 0)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 10)
            }
            // Mờ từng phần (nội dung, nền, bóng): khối có bóng mà mờ cả khối thì không vẽ ra PDF được (phim)
            .opacity(Double(shown))
            .background(Palette.surface.opacity(Double(shown)), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: .black.opacity(0.2 * Double(shown)), radius: 30, y: 10)
            .scaleEffect(0.9 + 0.1 * shown)
            .padding(.horizontal, 24)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        // VoiceOver: bảng chỉ là một lớp phủ trong cùng màn hình nên phải tự báo là modal (không thì vẫn vuốt tới được
        // các ô phía sau), và nhận cử chỉ thoát (vuốt hình chữ Z) để đóng
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
    }

    private func row(_ item: AppMenuItem) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.icon).font(.system(size: item.plain ? 26 : 16, weight: item.plain ? .regular : .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(Appearance.minimalOn ? AnyShapeStyle(.primary) : item.tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
                .background(item.plain ? Color.clear : item.danger ? Palette.danger.opacity(0.12) : Palette.pill, in: Circle())
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
/// Như Pressable (HomeView), thêm báo lúc ngón tay vừa đặt xuống
private struct PressableDown: ButtonStyle {
    let down: () -> Void
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.08) : .spring(duration: 0.3, bounce: 0.35),
                       value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, on in if on { down() } }
    }
}

struct TapHold<Content: View>: View {
    var tap: (() -> Void)? = nil
    let hold: () -> Void
    @ViewBuilder let content: Content
    /// Lần nhấn này đã thành nhấn giữ: lúc nhả tay không tính là chạm nữa, dù giữ bao lâu
    /// (trước đây chỉ bỏ qua lần nhả trong 0,8 giây, giữ lâu hơn rồi nhả là chạy cả hai việc)
    @State private var held = false
    @Environment(\.swipeGuard) private var swipeGuard

    var body: some View {
        // Dùng Button (không phải onTapGesture) để vuốt xoá trong danh sách vẫn chạy
        Button {
            if held { held = false; return }
            // Vừa vuốt ngang để xoá (Button trong List vẫn tính là chạm khi nhả tay): không mở màn sửa
            if let g = swipeGuard, Date().timeIntervalSince(g.last) < 0.4 { return }
            tap?()
        } label: { content.contentShape(Rectangle()) }
        // Ngón tay vừa đặt xuống là một lần nhấn mới: xoá cờ cũ, phòng lần trước giữ rồi kéo ra ngoài mới nhả (Button không
        // chạy nên cờ còn treo) làm mất lần chạm này. Biết qua trạng thái nhấn của Button, KHÔNG gắn onChanged vào
        // LongPressGesture: làm vậy cử chỉ giành luôn ngón tay, đặt tay lên ô rồi vuốt thì trang không cuộn được.
        .buttonStyle(PressableDown { held = false })
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.35)
            .onEnded { _ in
                held = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                hold()
            })
        .accessibilityAction(named: Text(L("Tuỳ chọn")), hold)
    }
}

/// Lần cuối thẻ bị kéo ngang (vuốt xoá tự vẽ), để TapHold bên trong bỏ qua lần "chạm" khi nhả tay sau khi vuốt
final class SwipeGuard { var last = Date.distantPast }

private struct SwipeGuardKey: EnvironmentKey { static let defaultValue: SwipeGuard? = nil }
extension EnvironmentValues {
    var swipeGuard: SwipeGuard? {
        get { self[SwipeGuardKey.self] }
        set { self[SwipeGuardKey.self] = newValue }
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
                                 subtitle: L("Tự ghi vào ngày %@ mỗi tháng", String(Calendar.current.component(.day, from: e.date)))) { if Pro.shared.allow(.recurring) { store.repeatMonthly(e) } })
    }
    items.append(AppMenuItem(icon: "trash.fill", title: L("Xoá"), danger: true) { store.remove(id: e.id) })
    return AppMenuSpec(icon: AnyView(CategoryBadge(c: c, side: 56, radius: 18, iconSize: 30)),
                       title: "\(e.n?.isEmpty == false ? e.n!.capFirst : c.name) · \(fmt(e.a))",
                       subtitle: "\(c.name) · \(f.string(from: e.date))", items: items)
}

extension View {
    /// Nhấn giữ để mở bảng tự vẽ (không có hành động chạm)
    func onHold(_ action: @escaping () -> Void) -> some View { TapHold(hold: action) { self } }
}
