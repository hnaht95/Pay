import SwiftUI

/// Tờ lịch — chép nguyên từ Peek (CalendarShape.swift), hình lấy từ bộ Tabler Icons (bản đặc).
///
/// Cùng nút với hình hoa giấy: hoa giấy nghĩa là "mở khung sinh nhật", tờ lịch nghĩa là "về
/// lại lịch". Một nút đổi hình theo trạng thái chứ không phải hai nút cạnh nhau — hàng tiêu
/// đề chỉ cao 20 pt và đã có nhãn tuần cùng hai mũi tên chen chỗ.
///
/// Toạ độ giữ nguyên hệ 24×24 của tệp SVG gốc rồi nhân theo khung, cùng hệ với `ConfettiShape`
/// nên hai hình thay nhau mà không đổi cỡ. Cung tròn `a` trong SVG đã quy đổi sang Bézier bậc
/// ba theo thuật toán của W3C — `Path` không có lệnh vẽ cung theo kiểu ấy.
///
/// Ba đường con: khung lịch, lòng lịch (khoét ra), và số 1 nằm giữa. Dùng luật chẵn–lẻ cho
/// khớp các hình khác trong app.
struct CalendarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = rect.minX + (rect.width - 24 * s) / 2
        let dy = rect.minY + (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }
        var path = Path()

        // Khung lịch, kể cả hai cái ngạnh treo phía trên.
        path.move(to: p(16, 2))
        path.addCurve(to: p(16.99, 2.88), control1: p(16.51, 2), control2: p(16.93, 2.38))
        path.addLine(to: p(17, 3))
        path.addLine(to: p(17, 4))
        path.addLine(to: p(18, 4))
        path.addCurve(to: p(21, 6.82), control1: p(19.59, 4), control2: p(20.9, 5.24))
        path.addLine(to: p(21, 7))
        path.addLine(to: p(21, 19))
        path.addCurve(to: p(18.18, 22), control1: p(21, 20.59), control2: p(19.76, 21.9))
        path.addLine(to: p(18, 22))
        path.addLine(to: p(6, 22))
        path.addCurve(to: p(3.01, 19.18), control1: p(4.41, 22), control2: p(3.1, 20.76))
        path.addLine(to: p(3, 19))
        path.addLine(to: p(3, 7))
        path.addCurve(to: p(5.82, 4.01), control1: p(3, 5.41), control2: p(4.24, 4.1))
        path.addLine(to: p(6, 4))
        path.addLine(to: p(7, 4))
        path.addLine(to: p(7, 3))
        path.addCurve(to: p(7.94, 2), control1: p(7, 2.47), control2: p(7.41, 2.03))
        path.addCurve(to: p(8.99, 2.88), control1: p(8.47, 1.97), control2: p(8.93, 2.36))
        path.addLine(to: p(9, 3))
        path.addLine(to: p(9, 4))
        path.addLine(to: p(15, 4))
        path.addLine(to: p(15, 3))
        path.addCurve(to: p(16, 2), control1: p(15, 2.45), control2: p(15.45, 2))
        path.closeSubpath()

        // Lòng lịch, khoét ra để chỉ còn dải đầu là đặc.
        path.move(to: p(19, 9))
        path.addLine(to: p(5, 9))
        path.addLine(to: p(5, 18.62))
        path.addCurve(to: p(5.88, 19.99), control1: p(5, 19.33), control2: p(5.39, 19.91))
        path.addLine(to: p(6, 20))
        path.addLine(to: p(18, 20))
        path.addCurve(to: p(18.99, 18.79), control1: p(18.51, 20), control2: p(18.94, 19.47))
        path.addLine(to: p(19, 18.62))
        path.addLine(to: p(19, 9))
        path.closeSubpath()

        // Số 1 nằm giữa lòng lịch.
        path.move(to: p(12, 12))
        path.addCurve(to: p(12.99, 12.88), control1: p(12.51, 12), control2: p(12.93, 12.38))
        path.addLine(to: p(13, 13))
        path.addLine(to: p(13, 16))
        path.addCurve(to: p(12.06, 17), control1: p(13, 16.53), control2: p(12.59, 16.97))
        path.addCurve(to: p(11.01, 16.12), control1: p(11.53, 17.03), control2: p(11.07, 16.64))
        path.addLine(to: p(11, 16))
        path.addLine(to: p(11, 14))
        path.addCurve(to: p(10, 13.06), control1: p(10.47, 14), control2: p(10.03, 13.59))
        path.addCurve(to: p(10.88, 12.01), control1: p(9.97, 12.53), control2: p(10.36, 12.07))
        path.addLine(to: p(11, 12))
        path.addLine(to: p(12, 12))
        path.closeSubpath()

        return path
    }
}
