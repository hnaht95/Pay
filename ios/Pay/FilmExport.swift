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

    static let scenes: [String: (Store) -> Film] = ["again": again, "stats": stats, "voice": voice]

    // MARK: Công cụ

    /// 0 trước `a`, 1 sau `b`, trượt êm ở giữa
    static func ease(_ t: Double, _ a: Double, _ b: Double) -> CGFloat {
        let x = max(0, min(1, (t - a) / (b - a)))
        return CGFloat(x * x * (3 - 2 * x))
    }

    /// Như lò xo: từ 0 lúc `a` vọt quá 1 một chút rồi nảy về 1 (kiểu .snappy của SwiftUI), xong sau khoảng `dur` giây
    static func spring(_ t: Double, _ a: Double, _ dur: Double) -> CGFloat {
        let x = max(0, (t - a) / dur)
        return x >= 1.6 ? 1 : CGFloat(1 - exp(-5.5 * x) * cos(7.5 * x))
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

    /// Một lần kéo ngón tay từ `from` tới `to`
    struct Drag { var from: CGPoint; var to: CGPoint; var start: Double; var end: Double }

    /// Chấm chạm của một lần kéo
    static func touch(_ drags: [Drag], _ t: Double) -> (at: CGPoint, alpha: CGFloat, scale: CGFloat)? {
        for d in drags where t >= d.start - 0.1 && t <= d.end + 0.25 {
            let k = ease(t, d.start, d.end)
            let at = CGPoint(x: d.from.x + (d.to.x - d.from.x) * k, y: d.from.y + (d.to.y - d.from.y) * k)
            return (at, ease(t, d.start - 0.1, d.start) * (1 - ease(t, d.end, d.end + 0.25)), 1)
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

    // MARK: Phim "Thống kê"

    static func stats(_ store: Store) -> Film {
        let open = Tap(at: CGPoint(x: 321, y: 91), down: 0.8, up: 1.0)
        // Hai lần vuốt lên để xem hết trang
        let drags = [Drag(from: CGPoint(x: 200, y: 700), to: CGPoint(x: 200, y: 280), start: 2.6, end: 3.5),
                     Drag(from: CGPoint(x: 200, y: 700), to: CGPoint(x: 200, y: 280), start: 5.0, end: 5.9)]
        return Film(length: 8.0) { t in
            var home = FilmFrame(again: store.frequent())
            home.pressed["stats"] = press(open, t)
            var sheet = FilmFrame()
            // Trang trôi theo ngón tay rồi trượt thêm một đoạn theo đà
            sheet.scroll = drags.reduce(0) { $0 + 420 * ease(t, $1.start, $1.end) + 110 * ease(t, $1.end, $1.end + 0.7) }
            let dot = touch([open], t) ?? touch(drags, t)
            return AnyView(FilmScreen(touch: dot) {
                FilmSheet(shown: ease(t, open.up, open.up + 0.45)) {
                    HomeView().environment(\.film, home)
                } content: {
                    StatsView().environment(\.film, sheet)
                }
            })
        }
    }

    // MARK: Phim "Nói là ghi"

    /// Bắt đầu ở màn hình khoá (ảnh Documents/film-assets/lock.<ngôn ngữ>.jpg do web/film/vector/make.sh chép vào),
    /// nhấn giữ nút Tác vụ (vạch xanh cạnh máy do trang web vẽ, cùng mốc thời gian: xem VOICE_PRESS trong index.html),
    /// máy mở khoá vào thẳng thẻ ghi âm, nói một câu, app ghi, bấm Xong.
    static func voice(_ store: Store) -> Film {
        let said = (Lang.isEnglish ? "200k for gas" : "hai trăm nghìn đổ xăng").split(separator: " ").map(String.init)
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let lock = UIImage(contentsOfFile: dir.appendingPathComponent("film-assets/lock.\(Lang.current.rawValue).jpg").path)
        let unlock = 2.2, card = 2.6, first = 3.5, gap = 0.38
        let heardAll = first + gap * Double(said.count - 1)
        let save = heardAll + 1.1
        let done = Tap(at: CGPoint(x: 316, y: 785), down: save + 1.9, up: save + 2.1)
        let chips = store.frequent()
        var saved: Expense?
        return Film(length: done.up + 1.8) { t in
            if saved == nil, t >= save { saved = store.quickAdd(said.joined(separator: " "), spoken: true, toast: false) }
            var home = FilmFrame(again: chips)
            home.time = t
            var v = FilmFrame.Voice()
            v.shown = ease(t, card, card + 0.4) * (1 - ease(t, done.up, done.up + 0.28))
            let n = t < first ? 0 : min(said.count, Int((t - first) / gap) + 1)
            v.text = said.prefix(n).joined(separator: " ")
            // Số tiền đổi khi nghe thêm một tiếng: số cũ trôi lên, số mới trượt lên và nảy nhẹ
            func amount(_ k: Int) -> String { QuickParse.spoken(said.prefix(k).joined(separator: " ")).map { fmt($0.amount) } ?? "0" }
            if n > 0, amount(n) != amount(n - 1) {
                v.previous = amount(n - 1)
                v.elapsed = t - (first + gap * Double(n - 1))
            }
            // Giọng nói theo nhịp từng tiếng: mỗi tiếng bật lên nhanh rồi lắng xuống, tiếng nhấn mạnh to hơn,
            // giữa hai tiếng có quãng lặng ngắn; nói xong thì im (trước là một dải đều đều)
            var level: CGFloat = 0.06
            for (i, word) in said.enumerated() {
                // Chữ có số ("200k") đọc thành nhiều âm tiết
                let beats = word.contains(where: \.isNumber) ? 3 : 1
                for b in 0..<beats {
                    let at = first - 0.22 + gap * Double(i) + gap * Double(b) / Double(beats)
                    let loud = [0.78, 1.0, 0.62, 0.92, 0.7][(i + b) % 5] * (beats > 1 ? 0.85 : 1)
                    let len = beats > 1 ? 0.2 : 0.34
                    level += CGFloat(loud) * ease(t, at, at + 0.07) * (1 - ease(t, at + 0.1, at + len))
                }
            }
            v.level = min(1, level)
            v.saved = saved
            v.settle = ease(t, save, save + 0.38)
            var cardFrame = home
            cardFrame.voice = v
            cardFrame.pressed["voice-primary"] = press(done, t)
            let k = ease(t, unlock, unlock + 0.5)   // mở khoá: màn hình khoá trượt lên, app phía dưới thu về đúng cỡ
            let size = FilmScreen<EmptyView>.size
            return AnyView(FilmScreen(lightStatus: k < 0.45, touch: touch([done], t)) {
                ZStack {
                    HomeView().environment(\.film, home)
                        .scaleEffect(1.07 - 0.07 * k)
                    if t >= card - 0.05 && v.shown > 0 {
                        VoiceEntryView(onScan: {}).environment(\.film, cardFrame)
                    }
                    if k < 1 {
                        Color.black.opacity(0.4 * Double(1 - k))
                        if let lock {
                            Image(uiImage: lock).resizable().frame(width: size.width, height: size.height)
                                .offset(y: -size.height * k)
                        } else { Color.black.offset(y: -size.height * k) }
                    }
                }
                .frame(width: size.width, height: size.height)
            })
        }
    }
}
#endif
