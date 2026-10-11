import SwiftUI

/// Tam giác đặc bo góc, hình lấy từ `triangle.fill` của bộ SF Symbols.
///
/// Vẽ tay chứ không gọi `Image(systemName:)`, vì hình này phải nằm **đúng giữa một vòng
/// tròn** và ký hiệu SF thì không chiều được chuyện đó: hộp chữ của nó không cân trong khung
/// nhận, mà lệch bao nhiêu lại đổi theo cỡ chữ. Đo trên ảnh dựng ra ở sáu cỡ từ 7 tới 11 thì
/// khoảng lệch nhảy từ 1,04 tới 1,96 pt, không theo quy luật nào — vì nó còn dính cả chuyện
/// làm tròn đường cơ sở khi rasterise. Vẽ tay thì toạ độ là của mình, hết sai số.
///
/// Toạ độ giữ nguyên hệ gốc của tệp SVG (viewBox 13,9941 × 12,2656) rồi nhân theo khung, để
/// đối chiếu lại với tệp gốc thế nào cũng được. Đường gốc chỉ có đoạn thẳng và Bézier bậc ba.
///
/// # Căn khung bao, không căn trọng tâm
///
/// Chỗ này đã thử cả hai đường, ghi lại kẻo lần sau lại đi vòng.
///
/// Tam giác dồn diện tích về phía đáy: trọng tâm của nó cách đỉnh 2/3 chiều cao, hình bo góc
/// này thì đo ra 0,609. Nên với **một** tam giác nằm trong **một** vòng tròn, căn theo trọng
/// tâm mới đúng — đó là lẽ nút phát nhạc của Apple bao giờ cũng nhích sang phải so với tâm
/// hình học.
///
/// Nhưng ở đây hai tam giác đứng cạnh nhau và **chỉ ngược chiều**, nên phần bù cũng đi ngược:
/// cái trỏ lên nhích lên, cái trỏ xuống nhích xuống, đo ra lệch nhau 1,58 pt. Mỗi cái nằm
/// đúng giữa vòng tròn của nó, mà cả cặp thì so le. Vòng tròn chỉ hiện lúc rê chuột, còn cặp
/// tam giác thì lúc nào cũng thấy — nên cái phải cân là cặp, không phải từng cái với cái nền
/// thỉnh thoảng mới có.
///
/// Giá phải trả: lúc vòng tròn hiện ra, tam giác thấp hơn tâm 0,79 pt. Nền ấy chỉ đậm 14%
/// trắng nên gần như không đọc ra được, mà hai cái so le thì đọc ra ngay.
struct TriangleShape: Shape {
    /// Bề ngang và chiều cao của đường gốc trong hệ toạ độ SVG.
    private static let box = CGSize(width: 13.4277, height: 12.2217)

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / Self.box.width, rect.height / Self.box.height)
        let w = Self.box.width * s, h = Self.box.height * s
        let dx = rect.midX - w / 2
        let dy = rect.midY - h / 2
        // Đường gốc bắt đầu từ y = 0,0439 chứ không phải 0, nên trừ đi cho khung bao khít.
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + (y - 0.0439453) * s)
        }
        var path = Path()
        path.move(to: p(1.83838, 12.2656))
        path.addLine(to: p(11.5894, 12.2656))
        path.addCurve(to: p(13.4277, 10.4321),
                      control1: p(12.7051, 12.2656), control2: p(13.4277, 11.4307))
        path.addCurve(to: p(13.1738, 9.48975),
                      control1: p(13.4277, 10.1147), control2: p(13.3447, 9.79004))
        path.addLine(to: p(8.2959, 0.964355))
        path.addCurve(to: p(6.71631, 0.0439453),
                      control1: p(7.94189, 0.34668), control2: p(7.33398, 0.0439453))
        path.addCurve(to: p(5.13428, 0.964355),
                      control1: p(6.09375, 0.0439453), control2: p(5.48096, 0.354004))
        path.addLine(to: p(0.256348, 9.49219))
        path.addCurve(to: p(0, 10.4321),
                      control1: p(0.0830078, 9.79492), control2: p(0, 10.1147))
        path.addCurve(to: p(1.83838, 12.2656),
                      control1: p(0, 11.4307), control2: p(0.722656, 12.2656))
        path.closeSubpath()
        return path
    }
}
