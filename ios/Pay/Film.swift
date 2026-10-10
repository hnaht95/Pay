import SwiftUI

/// Trạng thái của một khung hình phim giới thiệu. Bình thường là nil; khi dựng phim (bản Debug, xem FilmExport)
/// các màn hình đọc nó để tự vẽ ở đúng thời điểm: cuộn tới đâu, nút nào đang bị nhấn, thanh báo trượt tới đâu.
/// Phim vẽ bằng ImageRenderer ra PDF (chữ, hình là đường nét) nên không dùng được vùng cuộn, bảng trượt, kính
/// của hệ thống: ở chế độ này các màn hình thay chúng bằng bản tự vẽ trông giống.
struct FilmFrame {
    /// Đã cuộn xuống bao nhiêu pt
    var scroll: CGFloat = 0
    /// Mức đang nhấn của từng nút (0 = thả, 1 = nhấn hết), theo mã nút
    var pressed: [String: CGFloat] = [:]
    /// Thanh báo "Đã lưu": 0 = chưa hiện, 1 = hiện hẳn
    var toast: CGFloat = 0
    /// Các khoản "Chi lại" giữ nguyên thứ tự suốt phim
    var again: [Store.Frequent]? = nil
}

extension EnvironmentValues {
    @Entry var film: FilmFrame? = nil
}

extension View {
    /// Hiệu ứng nhấn như Pressable, theo mức `p` (0…1) do phim điều khiển
    func filmPressed(_ p: CGFloat) -> some View {
        let s: CGFloat = 1 - 0.06 * p, o: Double = 1 - 0.28 * Double(p)
        return scaleEffect(s).opacity(o)
    }
}

/// Vùng cuộn: ScrollView thật khi dùng app; khi dựng phim là nội dung dịch đi theo `film.scroll` và cắt theo khung.
struct FilmScroll<Content: View>: View {
    @Environment(\.film) private var film
    var axes: Axis.Set = .vertical
    @ViewBuilder let content: Content

    var body: some View {
        if let film {
            if axes == .horizontal {
                content.fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).clipped()   // minWidth 0: không thì khung nở theo nội dung
            } else {
                content.fixedSize(horizontal: false, vertical: true)
                    .offset(y: -film.scroll)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top).clipped()
            }
        } else {
            ScrollView(axes, showsIndicators: axes == .vertical) { content }
        }
    }
}

/// Màn hình iPhone của phim: nội dung nằm trong vùng an toàn như trên máy thật, có thanh trạng thái và Dynamic Island.
struct FilmScreen<Content: View>: View {
    static var size: CGSize { CGSize(width: 402, height: 874) }   // iPhone 17, tính bằng pt
    static var insets: EdgeInsets { EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0) }
    var dark = false
    /// Chấm chạm: vị trí và độ rõ (0…1)
    var touch: (at: CGPoint, alpha: CGFloat, scale: CGFloat)? = nil
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .top) {
            Palette.bg
            content
            statusBar
            if let touch {
                Circle().fill(.black.opacity(0.16))
                    .overlay { Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2) }
                    .frame(width: 46, height: 46)
                    .scaleEffect(touch.scale).opacity(touch.alpha)
                    .position(touch.at)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private var statusBar: some View {
        ZStack {
            Capsule().fill(.black).frame(width: 125, height: 36.5).position(x: 201, y: 32.2)
            Text("9:41").font(.system(size: 17, weight: .semibold)).position(x: 73, y: 33)
            HStack(spacing: 6) {
                Image(systemName: "cellularbars").font(.system(size: 16, weight: .semibold))
                Image(systemName: "wifi").font(.system(size: 15.5, weight: .semibold))
                Image(systemName: "battery.100percent").font(.system(size: 21, weight: .regular))
            }
            .position(x: 327, y: 33)
        }
        .foregroundStyle(.primary)
        .frame(width: Self.size.width, height: 62)
    }
}
