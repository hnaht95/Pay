import SwiftUI

/// Dải bút dạ quang của Shot (HighlightNib.swift của Shot, như trên peakapp.vn): đầu bút dẹt hình viên thuốc
/// cao bằng dải, rộng 4 + 5% chiều cao, nghiêng 12,4°, quét thẳng từ đầu tới cuối chữ và hơi dốc lên về bên phải.
enum HighlightBand {
    /// Xanh lá của bút dạ quang Shot; tô ở độ đậm 0,45
    static let green = Color(hex: 0x5FB875)

    static func path(behind rect: CGRect) -> Path {
        let h = rect.height * 0.95, y = rect.midY + 1
        let from = CGPoint(x: rect.minX - 2 + h * 0.12, y: y + 1), to = CGPoint(x: rect.maxX + 2 - h * 0.12, y: y - 1)
        let nib = Self.nib(height: h)
        let pts = hull(nib.map { CGPoint(x: $0.x + from.x, y: $0.y + from.y) } + nib.map { CGPoint(x: $0.x + to.x, y: $0.y + to.y) })
        var p = Path()
        p.addLines(pts); p.closeSubpath()
        return p
    }

    private static func nib(height: CGFloat) -> [CGPoint] {
        let w = min(height, 4 + height * 0.05), r = w / 2, angle = -atan(0.22)
        let c = cos(angle), s = sin(angle)
        var pts: [CGPoint] = []
        for cap in 0...1 {
            let cy = cap == 0 ? -height / 2 + r : height / 2 - r
            for step in 0...12 {
                let a = CGFloat(step) * .pi / 12 + (cap == 0 ? .pi : 0), x = cos(a) * r, y = cy + sin(a) * r
                pts.append(CGPoint(x: x * c - y * s, y: x * s + y * c))
            }
        }
        return pts
    }

    /// Bao lồi (Andrew): hình đầu bút ở hai đầu nối lại thành một nét liền
    private static func hull(_ points: [CGPoint]) -> [CGPoint] {
        let pts = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for p in pts { while lower.count > 1, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }; lower.append(p) }
        for p in pts.reversed() { while upper.count > 1, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }; upper.append(p) }
        return Array(lower.dropLast()) + Array(upper.dropLast())
    }
}

/// Đánh dấu đoạn chữ cần tô dạ quang
struct HighlightMark: TextAttribute {}

/// Vẽ dải dạ quang phía sau các đoạn có HighlightMark, mỗi dòng một dải, rồi vẽ chữ lên trên
@available(iOS 18.0, *)
struct HighlightRenderer: TextRenderer {
    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            var band: CGRect?
            for run in line where run[HighlightMark.self] != nil {
                band = band.map { $0.union(run.typographicBounds.rect) } ?? run.typographicBounds.rect
            }
            if let band { ctx.fill(HighlightBand.path(behind: band), with: .color(HighlightBand.green.opacity(0.45))) }
        }
        for line in layout { ctx.draw(line) }
    }
}

/// Câu có một đoạn bọc trong **…**: đoạn đó được tô dạ quang (iOS 18 trở lên; iOS 17 thì in đậm như Markdown).
struct HighlightedText: View {
    let text: String

    var body: some View {
        if #available(iOS 18.0, *) {
            let parts = text.components(separatedBy: "**")
            parts.enumerated().reduce(Text("")) { out, part in
                out + (part.offset % 2 == 1 ? Text(part.element).customAttribute(HighlightMark()).foregroundStyle(.primary) : Text(part.element))
            }
            .textRenderer(HighlightRenderer())
        } else {
            Text(LocalizedStringKey(text))
        }
    }
}
