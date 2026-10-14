import SwiftUI

/// Màu thẻ "Hôm nay đã chi" ở trang chủ: -1 là mặc định (trắng), còn lại cùng cách lưu với màu danh mục (CategoryTone)
enum HeroColor {
    static let key = "heroTone"
    static let barKey = "heroBarTone"
    /// Màu thanh ngân sách: -1 là xanh lá mặc định
    static func bar(_ t: Int) -> Color? { t < 0 ? nil : CategoryTone.chart(t) }

    /// Mặc định: trắng (thẻ luôn vẽ ở giao diện sáng)
    static func bg(_ t: Int) -> Color { t < 0 ? .white : CategoryTone.bg(t) }
    /// Màu tối thì chữ trên thẻ trắng
    static func scheme(_ t: Int) -> ColorScheme { t >= 0 && CategoryTone.dark(t) ? .dark : .light }
}

/// Chọn màu thẻ "Hôm nay đã chi": mặc định, các màu có sẵn, hoặc tự chọn bằng bảng màu của iOS
struct HeroColorSheet: View {
    @AppStorage(HeroColor.key) private var tone = -1
    @AppStorage(HeroColor.barKey) private var barTone = -1
    @State private var editingBar = false
    @Environment(\.dismiss) private var dismiss
    @State private var custom = Color.white

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Xem trước
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Hôm nay đã chi")).font(.system(size: 15)).foregroundStyle(.secondary)
                        Text("125.000").font(.system(size: 40, weight: .bold))
                        Capsule().fill(Color.primary.opacity(0.12)).frame(height: 6)
                            .overlay(alignment: .leading) {
                                GeometryReader { g in
                                    Capsule().fill(HeroColor.bar(barTone) ?? Color(red: 0.18, green: 0.62, blue: 0.32))
                                        .frame(width: g.size.width * 0.6)
                                }
                            }
                            .frame(height: 6).padding(.top, 10)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HeroColor.bg(tone), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .environment(\.colorScheme, HeroColor.scheme(tone))

                    // Đổi màu nào: nền thẻ hay thanh ngân sách
                    // Tự vẽ (thanh phân đoạn của iOS thấp, không đổi được chiều cao): cao 48, bo tròn
                    HStack(spacing: 4) {
                        ForEach([false, true], id: \.self) { bar in
                            Button { if editingBar != bar { Haptic.select() }; withAnimation(.snappy(duration: 0.2)) { editingBar = bar } } label: {
                                Text(bar ? L("Thanh ngân sách") : L("Nền thẻ")).font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity).frame(height: 44)
                                    .background { if editingBar == bar { Capsule().fill(Color.primary.opacity(0.18)) } }
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(Palette.card, in: Capsule())
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                        swatch(-1, editingBar ? Color(red: 0.18, green: 0.62, blue: 0.32) : .white)
                        ForEach(CategoryTone.all.indices, id: \.self) { i in swatch(i, CategoryTone.bg(i)) }
                    }
                    ColorPicker(selection: Binding(get: { custom }, set: { c in
                        custom = c
                        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
                        let byte = { (v: CGFloat) in UInt32(max(0, min(255, (v * 255).rounded()))) }
                        let t = CategoryTone.custom(byte(r) << 16 | byte(g) << 8 | byte(b))
                        if editingBar { barTone = t } else { tone = t }
                    }), supportsOpacity: false) {
                        Text(L("Tự chọn màu")).font(.system(size: 17))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(16)
            }
            .background(Palette.bg.ignoresSafeArea())
            .screenTitle(L("Màu thẻ"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(650), .large])   // vừa đủ hết bảng màu và Tự chọn màu (nửa màn bị cắt)
        .sheetGrabber()
    }

    private func swatch(_ t: Int, _ c: Color) -> some View {
        let cur = editingBar ? barTone : tone
        return Button { if cur != t { Haptic.select() }; if editingBar { barTone = t } else { tone = t } } label: {
            Circle().fill(editingBar && t >= 0 ? CategoryTone.chart(t) : c)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                .padding(cur == t ? 4.5 : 0)
                .frame(width: 40, height: 40)
                .overlay { if cur == t { Circle().strokeBorder(Color.primary.opacity(0.8), lineWidth: 2.5) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t < 0 ? L("Mặc định") : L("Màu"))
    }
}
