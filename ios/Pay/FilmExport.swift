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

        await House.shared.load()   // dữ liệu mẫu của Nhóm chung (chạy kèm -houseDemo YES)
        House.shared.open(nil)
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

    static let scenes: [String: (Store) -> Film] = ["stats": stats, "voice": voice, "group": group, "category": category, "widget": widget]

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

    // MARK: Phim "Thống kê"

    static func stats(_ store: Store) -> Film {
        let open = Tap(at: CGPoint(x: 321, y: 91), down: 0.8, up: 1.0)
        // Hai lần vuốt lên để xem hết trang
        let drags = [Drag(from: CGPoint(x: 200, y: 700), to: CGPoint(x: 200, y: 280), start: 2.6, end: 3.5),
                     Drag(from: CGPoint(x: 200, y: 700), to: CGPoint(x: 200, y: 280), start: 5.0, end: 5.9)]
        return Film(length: 8.0) { t in
            var home = FilmFrame()
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
        var saved: Expense?
        return Film(length: done.up + 1.8) { t in
            if saved == nil, t >= save { saved = store.quickAdd(said.joined(separator: " "), spoken: true, toast: false) }
            var home = FilmFrame()
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

    // MARK: Phim "Widget"

    /// Màn hình chính của iPhone với ba widget của Pay (hình do chính code widget vẽ, xem Shared/WidgetViews.swift):
    /// bấm micro trên widget, Pay mở ra nghe luôn, nói một câu, ghi xong quay về thì số trên widget đã đổi;
    /// cuối phim các widget lần lượt đổi màu (chọn trong Sửa tiện ích).
    static func widget(_ store: Store) -> Film {
        let said = (Lang.isEnglish ? "35k coffee" : "ba mươi lăm nghìn cà phê").split(separator: " ").map(String.init)
        let size = FilmScreen<EmptyView>.size
        let mic = Tap(at: WIDGETS.mic, down: 1.1, up: 1.3)
        let open = mic.up, card = open + 0.45, first = card + 0.8, gap = 0.36
        let heardAll = first + gap * Double(said.count - 1)
        let save = heardAll + 0.9
        let done = Tap(at: CGPoint(x: 316, y: 785), down: save + 1.5, up: save + 1.7)
        let close = done.up + 0.45
        let recolor = [close + 1.5, close + 2.7, close + 3.9]
        let qr = MyQR(bin: "970416", bank: "ACB", acct: "123456789", name: "NGUYEN VAN A")
        var saved: Expense?
        func summary() -> Summary {
            let now = Date()
            return Summary(today: store.total(on: now), month: store.monthItems(now).reduce(0) { $0 + $1.a },
                           count: store.count(on: now), day: now, budget: store.budget)
        }
        return Film(length: recolor[2] + 1.8) { t in
            if saved == nil, t >= save { saved = store.quickAdd(said.joined(separator: " "), spoken: true, toast: false) }
            // Thẻ ghi âm, như phim "Nói là ghi" nhưng gọn hơn
            var v = FilmFrame.Voice()
            v.shown = ease(t, card, card + 0.4) * (1 - ease(t, done.up, done.up + 0.28))
            let n = t < first ? 0 : min(said.count, Int((t - first) / gap) + 1)
            v.text = said.prefix(n).joined(separator: " ")
            func amount(_ k: Int) -> String { QuickParse.spoken(said.prefix(k).joined(separator: " ")).map { fmt($0.amount) } ?? "0" }
            if n > 0, amount(n) != amount(n - 1) { v.previous = amount(n - 1); v.elapsed = t - (first + gap * Double(n - 1)) }
            var level: CGFloat = 0.06
            for i in said.indices {
                let at = first - 0.22 + gap * Double(i)
                level += CGFloat([0.78, 1.0, 0.62, 0.92, 0.7][i % 5]) * ease(t, at, at + 0.07) * (1 - ease(t, at + 0.1, at + 0.34))
            }
            v.level = min(1, level); v.saved = saved; v.settle = ease(t, save, save + 0.38)
            var home = FilmFrame(); home.time = t
            var cardFrame = home
            cardFrame.voice = v
            cardFrame.pressed["voice-primary"] = press(done, t)
            // App phóng ra từ chỗ chạm trên widget rồi thu về lại đó
            let k = ease(t, open, open + 0.42) * (1 - ease(t, close, close + 0.42))
            // Màu của từng widget theo thời gian: (màu trước, màu sau, mức chuyển)
            @MainActor func tone(_ seq: [WidgetTone], _ delay: Double) -> (WidgetTone, WidgetTone, CGFloat) {
                var i = 0
                for (j, at) in recolor.enumerated() where t >= at + delay { i = j + 1 }
                guard i > 0 else { return (seq[0], seq[0], 1) }
                return (seq[i - 1], seq[i], ease(t, recolor[i - 1] + delay, recolor[i - 1] + delay + 0.35))
            }
            let s = summary()
            return AnyView(FilmScreen(lightStatus: k < 0.5, touch: touch([mic, done], t)) {
                ZStack(alignment: .topLeading) {
                    // Hình nền màn hình chính
                    LinearGradient(colors: [Color(hex: 0x2A1B4D), Color(hex: 0x6B3F8C), Color(hex: 0xD98BB4)], startPoint: .top, endPoint: .bottom)
                    widgetCard(WIDGETS.spend, tone([.green, .black, .pPurple, .green], 0)) { SpendView(e: SpendEntry(date: Date(), s: s, tone: $0), size: .systemMedium) }
                        .scaleEffect(1 - 0.03 * press(mic, t))
                    widgetCard(WIDGETS.qr, tone([.green, .pYellow, .white, .green], 0.12)) { MyQRView(e: MyQREntry(date: Date(), qr: qr, tone: $0, s: s), size: .systemMedium) }
                    widgetCard(WIDGETS.voice, tone([.green, .pBlue, .orange, .green], 0.24)) { VoiceView(e: SpendEntry(date: Date(), s: s, tone: $0), size: .systemSmall) }
                    widgetCard(WIDGETS.small, tone([.green, .cream, .forest, .green], 0.36)) { SpendView(e: SpendEntry(date: Date(), s: s, tone: $0), size: .systemSmall) }
                    // Thanh Dock
                    RoundedRectangle(cornerRadius: 34, style: .continuous).fill(.white.opacity(0.22))
                        .frame(width: 350, height: 92).position(x: size.width / 2, y: size.height - 66)
                    HStack(spacing: 24) {
                        Image("logo-pay").resizable().scaledToFit().padding(9).frame(width: 60, height: 60)
                            .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        ForEach([0x34C759, 0x0A84FF, 0xFF9F0A], id: \.self) { c in
                            RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color(hex: UInt32(c))).frame(width: 60, height: 60)
                        }
                    }
                    .position(x: size.width / 2, y: size.height - 66)
                    if k > 0 {
                        ZStack {
                            HomeView().environment(\.film, home)
                            if v.shown > 0 { VoiceEntryView(onScan: {}).environment(\.film, cardFrame) }
                        }
                        .frame(width: size.width, height: size.height)
                        .background(Palette.bg)
                        .clipShape(RoundedRectangle(cornerRadius: (56 * (1 - k)).rounded(), style: .continuous))
                        .scaleEffect(0.12 + 0.88 * k, anchor: UnitPoint(x: mic.at.x / size.width, y: mic.at.y / size.height))
                    }
                }
                .frame(width: size.width, height: size.height)
            })
        }
    }

    /// Chỗ đặt các widget trên màn hình chính của phim (cỡ vừa 338x158, cỡ nhỏ 158x158) và nút micro của widget đầu
    private enum WIDGETS {
        static let spend = CGRect(x: 32, y: 84, width: 338, height: 158)
        static let qr = CGRect(x: 32, y: 264, width: 338, height: 158)
        static let voice = CGRect(x: 32, y: 444, width: 158, height: 158)
        static let small = CGRect(x: 212, y: 444, width: 158, height: 158)
        static let mic = CGPoint(x: 264, y: 196)
    }

    /// Một widget trên màn hình chính: nền bo góc màu của widget (đang đổi màu thì màu mới phủ dần lên), nội dung lề 16pt
    private static func widgetCard<V: View>(_ r: CGRect, _ tone: (WidgetTone, WidgetTone, CGFloat), @ViewBuilder _ content: (WidgetTone) -> V) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return ZStack {
            shape.fill(tone.0.bg)
            shape.fill(tone.1.bg.opacity(Double(tone.2)))
            content(tone.2 > 0.5 ? tone.1 : tone.0).padding(16)
        }
        .frame(width: r.width, height: r.height)
        .offset(x: r.minX, y: r.minY)
    }

    // MARK: Phim "Nhóm chung"

    /// Mở Nhóm chung, vào nhóm đầu, bấm "Đã nhận" cho khoản người khác báo đã chuyển, rồi kéo xem ai chuyển cho ai
    static func group(_ store: Store) -> Film {
        let house = House.shared
        let open = Tap(at: CGPoint(x: 277, y: 91), down: 0.8, up: 1.0)
        let pick = Tap(at: CGPoint(x: 150, y: 196), down: 2.5, up: 2.7)
        let got = Tap(at: CGPoint(x: 290, y: 568), down: 4.7, up: 4.9)
        let drag = Drag(from: CGPoint(x: 200, y: 660), to: CGPoint(x: 200, y: 330), start: 6.4, end: 7.3)
        let first = house.groups.first
        var picked = false, answered = false
        return Film(length: 9.6) { t in
            if !picked, t >= pick.up, let first { house.open(first.id); picked = true }
            if !answered, t >= got.up, let s = house.current?.pending.first(where: { $0.to == house.me }) {
                answered = true
                Task { await house.respond(s.id, received: true) }
            }
            var home = FilmFrame()
            home.pressed["house"] = press(open, t)
            var sheet = FilmFrame()
            if let first { sheet.pressed["group-" + first.id] = press(pick, t) }
            sheet.pressed["received"] = press(got, t)
            sheet.scroll = 330 * ease(t, drag.start, drag.end) + 90 * ease(t, drag.end, drag.end + 0.7)
            let dot = touch([open, pick, got], t) ?? touch([drag], t)
            return AnyView(FilmScreen(touch: dot) {
                FilmSheet(shown: ease(t, open.up, open.up + 0.45)) {
                    HomeView().environment(\.film, home)
                } content: {
                    HouseView().environment(\.film, sheet)
                }
            })
        }
    }

    // MARK: Phim "Danh mục của bạn"

    /// Nhấn giữ ô Cafe, chọn "Đổi biểu tượng, màu, tên", chọn cốc bia và màu vàng, Lưu: ô ở màn hình chính đổi theo
    static func category(_ store: Store) -> Film {
        let key = "cafe", beer = "🍺", yellow = 14
        let hold = Tap(at: CGPoint(x: 290, y: 509), down: 0.8, up: 1.7)
        let item = Tap(at: CGPoint(x: 190, y: 450), down: 2.8, up: 3.0)
        let emoji = Tap(at: POINTS.emoji, down: 4.6, up: 4.8)
        let drag = Drag(from: CGPoint(x: 200, y: 700), to: CGPoint(x: 200, y: 480), start: 5.6, end: 6.3)
        let color = Tap(at: POINTS.color, down: 7.3, up: 7.5)
        let save = Tap(at: CGPoint(x: 352, y: 100), down: 8.6, up: 8.8)
        let original = Category.get(key)
        var saved = false
        return Film(length: 11.0) { t in
            if !saved, t >= save.up {
                saved = true
                store.updateCategory(key, name: original.rawName, icon: beer, tone: yellow)
            }
            var home = FilmFrame()
            home.pressed["tile-" + key] = press(Tap(at: hold.at, down: hold.down, up: hold.down + 0.45), t)
            // Giữ 0,35 giây thì bảng bật ra; chọn xong thì bảng đóng
            let menu = ease(t, hold.down + 0.35, hold.down + 0.6) * (1 - ease(t, item.up, item.up + 0.2))
            home.menu = (key, menu)
            home.pressed["menu-item"] = press(item, t)
            var sheet = FilmFrame()
            sheet.edit = .init(icon: t >= emoji.up ? beer : original.icon, tone: t >= color.up ? yellow : -1)
            sheet.pressed["emoji-" + beer] = press(emoji, t)
            sheet.pressed["tone-\(yellow)"] = press(color, t)
            sheet.pressed["save"] = press(save, t)
            sheet.scroll = 220 * ease(t, drag.start, drag.end) + 40 * ease(t, drag.end, drag.end + 0.6)
            let shown = ease(t, item.up + 0.15, item.up + 0.6) * (1 - ease(t, save.up, save.up + 0.4))
            let dot = touch([hold, item, emoji, color, save], t) ?? touch([drag], t)
            return AnyView(FilmScreen(touch: dot) {
                FilmSheet(shown: shown) {
                    HomeView().environment(\.film, home)
                } content: {
                    CategoryEditor(editing: CustomCat(k: key, name: original.rawName, icon: original.icon, tone: -1, on: true, u: 0))
                        .environment(\.film, sheet)
                }
            })
        }
    }

    /// Chỗ chạm trong màn sửa danh mục (đo trên khung hình đã vẽ)
    private enum POINTS {
        static let emoji = CGPoint(x: 282, y: 601)
        static let color = CGPoint(x: 302, y: 662)
    }
}
#endif
