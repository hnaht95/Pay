import SwiftUI

extension View {
    /// Vuốt từ mép trái sang phải để quay lại / đóng màn hình (như cử chỉ quay lại của iOS, cho các màn hình mở dạng bảng).
    /// Dải nhận cử chỉ rộng 16pt sát mép trái, bằng lề của nội dung nên không che nút nào.
    func edgeBack(_ action: @escaping () -> Void) -> some View {
        overlay(alignment: .leading) {
            Color.clear.frame(width: 16).frame(maxHeight: .infinity).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 12).onEnded { v in
                    if v.translation.width > 60, abs(v.translation.height) < 90 { action() }
                })
                .ignoresSafeArea()
        }
    }

    /// Vuốt xuống để ẩn màn hình mở toàn màn hình (bảng thường đã có sẵn cử chỉ này của iOS).
    func swipeDownToClose(_ action: @escaping () -> Void) -> some View {
        simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.height > 110, abs(v.translation.width) < 80 { action() }
        })
    }

    /// Vạch ngang trên cùng của bảng, cho biết kéo xuống là đóng (thay nút Xong). Tự vẽ thay cho vạch của iOS
    /// vì vạch của iOS nằm sát mép trên, không dời xuống được.
    func sheetGrabber() -> some View {
        overlay(alignment: .top) {
            SheetGrabber().padding(.top, SheetGrabber.top).ignoresSafeArea().allowsHitTesting(false)
        }
    }
}

struct SheetGrabber: View {
    /// Khoảng cách từ mép trên của bảng tới vạch
    static let top: CGFloat = 11
    var body: some View {
        Capsule().fill(Color.primary.opacity(0.22)).frame(width: 36, height: 5)
    }
}
