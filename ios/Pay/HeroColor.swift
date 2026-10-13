import SwiftUI

/// Màu thẻ "Hôm nay đã chi" ở trang chủ: -1 là mặc định (trắng), còn lại cùng cách lưu với màu danh mục (CategoryTone)
enum HeroColor {
    static let key = "heroTone"

    /// Mặc định: trắng (thẻ luôn vẽ ở giao diện sáng)
    static func bg(_ t: Int) -> Color { t < 0 ? .white : CategoryTone.bg(t) }
    /// Màu tối thì chữ trên thẻ trắng
    static func scheme(_ t: Int) -> ColorScheme { t >= 0 && CategoryTone.dark(t) ? .dark : .light }
}

/// Chọn màu thẻ "Hôm nay đã chi": mặc định, các màu có sẵn, hoặc tự chọn bằng bảng màu của iOS
struct HeroColorSheet: View {
    @AppStorage(HeroColor.key) private var tone = -1
    @Environment(\.dismiss) private var dismiss
    @State private var custom = Color.white

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Xem trước
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Hôm nay đã chi")).font(.system(size: 15)).foregroundStyle(.secondary)
                        Text("125.000").font(.system(size: 34, weight: .bold))
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HeroColor.bg(tone), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .environment(\.colorScheme, HeroColor.scheme(tone))

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                        swatch(-1, .white)
                        ForEach(CategoryTone.all.indices, id: \.self) { i in swatch(i, CategoryTone.bg(i)) }
                    }
                    ColorPicker(selection: Binding(get: { custom }, set: { c in
                        custom = c
                        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
                        let byte = { (v: CGFloat) in UInt32(max(0, min(255, (v * 255).rounded()))) }
                        tone = CategoryTone.custom(byte(r) << 16 | byte(g) << 8 | byte(b))
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
        .presentationDetents([.height(570), .large])   // vừa đủ hết bảng màu và Tự chọn màu (nửa màn bị cắt)
        .sheetGrabber()
    }

    private func swatch(_ t: Int, _ c: Color) -> some View {
        Button { if tone != t { Haptic.select() }; tone = t } label: {
            Circle().fill(c)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                .padding(tone == t ? 4.5 : 0)
                .frame(width: 40, height: 40)
                .overlay { if tone == t { Circle().strokeBorder(Color.primary.opacity(0.8), lineWidth: 2.5) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t < 0 ? L("Mặc định") : L("Màu"))
    }
}
