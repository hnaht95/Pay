#if DEBUG
import UIKit

/// Chỉ bản Debug, chạy với "-showTouches YES": vẽ chấm tròn chỗ ngón tay chạm, để quay phim giới thiệu trên máy ảo
/// (bản ghi màn hình của máy ảo không có dấu chạm).
enum FilmTouches {
    static func install() {
        guard UserDefaults.standard.bool(forKey: "showTouches") else { return }
        Task { @MainActor in
            for _ in 0..<20 {
                if let w = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                    .flatMap(\.windows).first(where: \.isKeyWindow) {
                    w.addGestureRecognizer(TouchDots())
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }
}

/// Không bao giờ nhận cử chỉ, chỉ nhìn các lần chạm đi qua cửa sổ và vẽ chấm theo.
private final class TouchDots: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var dots: [UITouch: UIView] = [:]

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let w = view else { return }
        for t in touches {
            let d = UIView(frame: CGRect(x: 0, y: 0, width: 46, height: 46))
            d.layer.cornerRadius = 23
            d.backgroundColor = UIColor.black.withAlphaComponent(0.16)
            d.layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
            d.layer.borderWidth = 2
            d.isUserInteractionEnabled = false
            d.center = t.location(in: w)
            d.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            w.addSubview(d)
            UIView.animate(withDuration: 0.12) { d.transform = .identity }
            dots[t] = d
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let w = view else { return }
        for t in touches { dots[t]?.center = t.location(in: w); if let d = dots[t] { w.bringSubviewToFront(d) } }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches) }

    private func lift(_ touches: Set<UITouch>) {
        for t in touches {
            guard let d = dots.removeValue(forKey: t) else { continue }
            UIView.animate(withDuration: 0.3, animations: { d.alpha = 0; d.transform = CGAffineTransform(scaleX: 1.3, y: 1.3) },
                           completion: { _ in d.removeFromSuperview() })
        }
        if dots.isEmpty { state = .failed }
    }

    override func reset() { super.reset() }
}
#endif
