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

    /// Như edgeBack, nhưng cả trang trượt theo ngón tay sang phải rồi mới đóng (như cử chỉ quay lại của iOS).
    /// Dời chính khung bảng của iOS (cả góc bo, bóng đổ), nên màn hình phía sau lộ ra dần.
    /// `slides` trả về false thì chỉ gọi `action` như edgeBack (vd đang ở trong một nhóm: lùi một bước, không đóng).
    func edgeBack(slides: @escaping () -> Bool, _ action: @escaping () -> Void) -> some View {
        modifier(SlideBack(slides: slides, action: action))
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

private struct SlideBack: ViewModifier {
    let slides: () -> Bool
    let action: () -> Void
    @State private var handle = SheetHandle.Ref()

    func body(content: Content) -> some View {
        content
            .background(SheetHandle(ref: handle).frame(width: 0, height: 0))
            .overlay(alignment: .leading) {
                Color.clear.frame(width: 16).frame(maxHeight: .infinity).contentShape(Rectangle())
                    // Toạ độ màn hình: trang trượt theo ngón tay nên toạ độ của chính nó không dùng được
                    .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .global)
                        .onChanged { v in if slides() { handle.move(max(0, v.translation.width)) } }
                        .onEnded { v in
                            guard slides() else {
                                if v.translation.width > 60, abs(v.translation.height) < 90 { action() }
                                return
                            }
                            let go = v.translation.width > 90 || v.predictedEndTranslation.width > 240
                            guard go else { handle.move(0, animated: true); return }
                            // Trượt hết sang phải rồi đóng ngay, không chạy thêm hiệu ứng thu xuống của iOS
                            handle.move(UIScreen.main.bounds.width, animated: true) {
                                var t = Transaction(animation: nil); t.disablesAnimations = true
                                withTransaction(t) { action() }
                            }
                        })
                    .ignoresSafeArea()
            }
    }
}

/// Nắm lấy khung của bảng / màn hình đang hiện (view do iOS dựng quanh nội dung SwiftUI) để dời nó sang ngang.
private struct SheetHandle: UIViewRepresentable {
    final class Ref {
        weak var view: UIView?

        /// Khung ngoài cùng của màn hình đang hiện: view của controller được present (kèm lớp bọc bo góc, đổ bóng nếu có)
        private var card: UIView? {
            var r: UIResponder? = view
            var top: UIViewController?
            while let n = r { if let vc = n as? UIViewController { top = vc }; r = n.next; if top?.presentingViewController != nil, top?.parent == nil { break } }
            guard let vc = top else { return nil }
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "slideDebug") {
                var v: UIView? = vc.view; var names: [String] = []
                while let x = v { names.append(String(describing: type(of: x))); v = x.superview }
                print("SLIDE", names.joined(separator: " < "), String(describing: type(of: vc.presentationController?.presentedView)))
            }
            #endif
            // Lớp bọc của bảng (bo góc, đổ bóng) nằm ngay dưới lớp chuyển cảnh; không có thì dời view của controller
            var v: UIView? = vc.view
            while let x = v, let up = x.superview, !String(describing: type(of: up)).contains("TransitionView"), !(up is UIWindow) { v = up }
            return v ?? vc.view
        }

        func move(_ x: CGFloat, animated: Bool = false, then: (() -> Void)? = nil) {
            guard let card else { then?(); return }
            let t = CGAffineTransform(translationX: x, y: 0)
            guard animated else { card.transform = t; return }
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) { card.transform = t } completion: { _ in then?() }
        }
    }

    let ref: Ref
    func makeUIView(context: Context) -> UIView { let v = UIView(); v.isUserInteractionEnabled = false; ref.view = v; return v }
    func updateUIView(_ v: UIView, context: Context) { ref.view = v }
}
