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
    /// Thời điểm của phim (giây), cho những thứ tự chuyển động: sóng âm, chấm đỏ nhấp nháy
    var time: Double = 0
    /// Thẻ ghi bằng giọng nói đang hiện (nil = không)
    var voice: Voice? = nil

    struct Voice {
        /// Thẻ trượt lên tới đâu (0…1)
        var shown: CGFloat = 1
        /// Câu đã nghe tới lúc này
        var text = ""
        /// Độ to giọng nói (0…1)
        var level: CGFloat = 0
        /// Khoản đã ghi xong (nil = còn đang nghe)
        var saved: Expense? = nil
        /// Số tiền vừa đổi: số cũ và mức chuyển sang số mới (0…1) — số cũ trôi lên mờ đi, số mới trồi lên
        var previous: String? = nil
        var shift: CGFloat = 1
        /// Ghi xong: thẻ thu gọn lại (sóng âm xẹp dần), 0…1
        var settle: CGFloat = 0
    }
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
                    .offset(y: -film.scroll.rounded())   // điểm nguyên: chữ và hình cùng bước, không lệch nhau
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
    /// Thanh trạng thái của màn hình khoá: biểu tượng trắng trên nền tối, không có giờ ở góc trái
    var lightStatus = false
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
            // Màn hình khoá không hiện giờ ở góc (đã có đồng hồ lớn): giờ chỉ có khi đã vào app
            if !lightStatus { Text("9:41").font(.system(size: 17, weight: .semibold)).position(x: 73, y: 33) }
            HStack(spacing: 6) {
                Image(systemName: "cellularbars").font(.system(size: 16, weight: .semibold))
                Image(systemName: "wifi").font(.system(size: 15.5, weight: .semibold))
                Image(systemName: "battery.100percent").font(.system(size: 21, weight: .regular))
            }
            .position(x: 327, y: 33)
        }
        .foregroundStyle(lightStatus ? Color.white : Color.primary)
        .frame(width: Self.size.width, height: 62)
    }
}

/// Thanh tiêu đề của một bảng trượt lên (thay thanh điều hướng của hệ thống khi dựng phim):
/// tiêu đề ở giữa, nút viên thuốc hai bên như iOS 26.
struct FilmNavBar: View {
    let title: String
    var leading: String? = nil
    var trailing: String? = nil
    /// Mức nhấn của nút bên phải (0…1)
    var trailingPressed: CGFloat = 0

    var body: some View {
        ZStack {
            Text(title).font(.system(size: 17, weight: .semibold))
            HStack {
                if let leading { pill(leading, weight: .regular) }
                Spacer()
                if let trailing { pill(trailing, weight: .semibold).filmPressed(trailingPressed) }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 76)
    }

    private func pill(_ text: String, weight: Font.Weight) -> some View {
        Text(text).font(.system(size: 17, weight: weight))
            .padding(.horizontal, 17).frame(height: 44)
            .background {
                Capsule().fill(Color.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
            }
            .foregroundStyle(Color(hex: 0x111114))
    }
}

/// Một bảng trượt lên phủ gần hết màn hình (sheet), theo mức `shown` 0…1: phía sau tối dần, bảng trượt từ đáy lên.
struct FilmSheet<Back: View, Content: View>: View {
    var shown: CGFloat
    @ViewBuilder let back: Back
    @ViewBuilder let content: Content

    var body: some View {
        let size = FilmScreen<EmptyView>.size, top = FilmScreen<EmptyView>.insets.top
        ZStack(alignment: .top) {
            back
            Color.black.opacity(0.3 * Double(shown))
            content
                .frame(width: size.width, height: size.height - top)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38, style: .continuous))
                .offset(y: (top + (1 - shown) * (size.height - top)).rounded())
        }
        .frame(width: size.width, height: size.height)
    }
}
