#if DEBUG
import SwiftUI

/// Chỉ bản Debug. Dựng phim giới thiệu dạng vector cho peakapp.vn: chạy app với "-filmExport <tên phim>"
/// (kèm -filmSeed YES, -filmLang vi|en), mỗi khung hình được chính các màn hình của app vẽ ra một trang PDF
/// trong Documents/film/<tên>.<ngôn ngữ>/ cùng meta.json. Sau đó web/film/vector/make.sh đổi thành phim cho web.
@MainActor
enum FilmExport {
    static let fps = 60.0

    static func runIfAsked(store: Store, quick: QuickAction) async {
        guard let name = UserDefaults.standard.string(forKey: "filmExport"), let scene = scenes[name] else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("film/\(name).\(Lang.current.rawValue)", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var film = scene(store)
        let count = Int((film.length * fps).rounded()) + 1
        var log: [[String: Any]] = []
        for i in 0..<count {
            let t = Double(i) / fps
            let view = film.frame(t)
                .environmentObject(store).environmentObject(quick)
                .environment(\.locale, Lang.locale)
            let r = ImageRenderer(content: view)
            r.proposedSize = ProposedViewSize(FilmScreen<EmptyView>.size)
            r.render { size, draw in
                var box = CGRect(origin: .zero, size: size)
                guard let ctx = CGContext(dir.appendingPathComponent(String(format: "p%05d.pdf", i)) as CFURL, mediaBox: &box, nil) else { return }
                ctx.beginPDFPage(nil); draw(ctx); ctx.endPDFPage(); ctx.closePDF()
            }
            log.append(["page": i, "camera": [1, 0, 0]])
            if i % 30 == 0 { await Task.yield() }
        }
        let meta: [String: Any] = ["fps": fps, "frames": log, "screen": [FilmScreen<EmptyView>.size.width, FilmScreen<EmptyView>.size.height]]
        try? JSONSerialization.data(withJSONObject: meta).write(to: dir.appendingPathComponent("meta.json"))
        try? Data("\(count)".utf8).write(to: dir.appendingPathComponent("done"))
        print("FilmExport: \(name) \(count) khung hình -> \(dir.path)")
    }

    /// Một phim: dài bao nhiêu giây và màn hình tại thời điểm t (gọi lần lượt t tăng dần; phim tự đổi dữ liệu khi tới lúc)
    struct Film {
        var length: Double
        var frame: (Double) -> AnyView
    }

    static let scenes: [String: (Store) -> Film] = ["again": again]

    // MARK: Công cụ

    /// 0 trước `a`, 1 sau `b`, trượt êm ở giữa
    static func ease(_ t: Double, _ a: Double, _ b: Double) -> CGFloat {
        let x = max(0, min(1, (t - a) / (b - a)))
        return CGFloat(x * x * (3 - 2 * x))
    }

    /// Một lần chạm tại `at`, ngón tay xuống lúc `down`, nhấc lúc `up`
    struct Tap { var at: CGPoint; var down: Double; var up: Double }

    /// Chấm chạm tại thời điểm t: hiện nhanh khi chạm, mờ dần và nở ra khi nhấc
    static func touch(_ taps: [Tap], _ t: Double) -> (at: CGPoint, alpha: CGFloat, scale: CGFloat)? {
        for tap in taps where t >= tap.down && t <= tap.up + 0.3 {
            let a = ease(t, tap.down, tap.down + 0.1), out = ease(t, tap.up, tap.up + 0.3)
            return (tap.at, a * (1 - out), 0.6 + 0.4 * a + 0.3 * out)
        }
        return nil
    }

    /// Mức nhấn của nút theo một lần chạm: xuống nhanh, nhả thì bật lại
    static func press(_ tap: Tap, _ t: Double) -> CGFloat {
        ease(t, tap.down, tap.down + 0.08) * (1 - ease(t, tap.up, tap.up + 0.25))
    }

    // MARK: Phim "Chi lại một chạm"

    static func again(_ store: Store) -> Film {
        let chips = store.frequent()
        let taps = [Tap(at: CGPoint(x: 225, y: 453), down: 1.0, up: 1.25), Tap(at: CGPoint(x: 83, y: 453), down: 4.0, up: 4.25)]
        let order = [1, 0]   // chạm "cà phê" rồi "ăn trưa"
        var done = 0
        var message: String?
        let hold = 2.0   // mỗi thanh báo hiện chừng này giây rồi tự đi, thanh sau không chồng lên thanh trước
        return Film(length: 7.3) { t in
            // Tới lúc nhấc tay: ghi khoản và hiện thanh báo như app thật
            while done < taps.count, t >= taps[done].up {
                let f = chips[order[done]]
                store.add(amount: f.amount, note: f.note, cat: f.cat, toast: false)
                message = L("Đã lưu %@đ", fmt(f.amount))
                store.toast = nil
                done += 1
            }
            // App thật đang chạy phía sau tự tắt thanh báo sau 5 giây: phim giữ thanh của mình tới khi nó trượt đi hẳn
            if let message, store.toast?.message != message { store.toast = Toast(message: message, undo: {}) }
            var frame = FilmFrame(again: chips)
            for (i, tap) in taps.enumerated() { frame.pressed["again-" + chips[order[i]].id] = press(tap, t) }
            frame.toast = taps.reduce(0) { $0 + ease(t, $1.up + 0.05, $1.up + 0.35) * (1 - ease(t, $1.up + hold, $1.up + hold + 0.3)) }
            return AnyView(FilmScreen(touch: touch(taps, t)) { HomeView() }.environment(\.film, frame))
        }
    }
}
#endif
