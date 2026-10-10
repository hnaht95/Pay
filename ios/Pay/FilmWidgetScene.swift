#if DEBUG
import SwiftUI
import WidgetKit

/// Phim "Widget": màn hình chính thật của máy ảo iOS, tách thành từng mảnh (web/film/vector/widget-assets.py:
/// hình nền sạch, từng biểu tượng / widget nền trong suốt) để dựng lại có chuyển động: nhấn giữ khoảng trống cho các
/// biểu tượng rung, Edit > Add Widget, gõ "Pay", lướt qua các widget của Pay, thêm widget cỡ vừa (widget bật vào,
/// các biểu tượng lùi xuống), bấm Done. Toạ độ ghi theo ảnh chụp rộng 920px (`p` đổi sang điểm).
extension FilmExport {
    private static let size = FilmScreen<EmptyView>.size
    private static func p(_ v: CGFloat) -> CGFloat { v * 402 / 920 }

    private static func asset(_ name: String) -> UIImage? {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return UIImage(contentsOfFile: dir.appendingPathComponent("film-assets/" + name).path)
    }

    private static func full(_ img: UIImage?) -> some View {
        Group { if let img { Image(uiImage: img).resizable() } else { Color.black } }
            .frame(width: size.width, height: size.height)
    }

    /// Ảnh chỉ lấy phần từ `top` trở xuống (phần bảng trượt), bo hai góc trên
    private static func sheet(_ img: UIImage?, top: CGFloat) -> some View {
        full(img).mask(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 44, topTrailingRadius: 44, style: .continuous)
                .frame(height: size.height - top).offset(y: top)
        }
    }

    /// Một mảnh của màn hình chính (biểu tượng hoặc widget kèm tên): khung trên ảnh 920px, góc trên trái của thân để đặt dấu trừ
    private struct Piece { let image: UIImage?; let frame: CGRect; let body: CGPoint }

    private static func minus(_ scale: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(hex: 0x8C8494))
            Capsule().fill(Color(hex: 0x1C1C1E)).frame(width: 11, height: 2.2)
        }
        .frame(width: 25, height: 25).scaleEffect(scale)
    }

    static func widget(_ store: Store) -> Film {
        var pieces: [Piece] = []
        for (i, x) in [CGFloat(62), 486].enumerated() {
            pieces.append(Piece(image: asset("w-big\(i).png"), frame: CGRect(x: x - 12, y: 195, width: 398, height: 445), body: CGPoint(x: x, y: 207)))
        }
        for (r, y) in [CGFloat(665), 895].enumerated() {
            for (c, x) in [CGFloat(70), 282, 494, 706].enumerated() {
                pieces.append(Piece(image: asset("w-app\(r)\(c).png"), frame: CGRect(x: x - 24, y: y - 12, width: 193, height: 212), body: CGPoint(x: x, y: y)))
            }
        }
        let bg = asset("w-bg.jpg"), bgEdit = asset("w-bg-edit.jpg"), menuImg = asset("w-menu.png")
        let gallery = asset("w-sheet-gallery.jpg"), search = asset("w-sheet-search.jpg")
        let pages = (1...5).map { asset("w-sheet-\($0).jpg") }
        let qr = MyQR(bin: "970416", bank: "ACB", acct: "123456789", name: "NGUYEN VAN A")
        // Mã QR trong phim: một mã vô hại (quét ra trang của Pay), vẽ bằng hình cho nét
        MyQR.filmPayload = "https://peakapp.vn/pay"; MyQRCode.vector = true
        let now = Date()
        let sum = Summary(today: 35_000, month: store.monthItems(now).reduce(0) { $0 + $1.a } + 35_000, count: 1, day: now, budget: store.budget)

        let sheetTop = p(280)
        let hold = Tap(at: CGPoint(x: 200, y: 600), down: 0.9, up: 1.8)
        let jiggle = hold.down + 0.55
        let edit = Tap(at: CGPoint(x: 72, y: 33), down: 2.6, up: 2.8)
        let add = Tap(at: CGPoint(x: 140, y: 93), down: 3.6, up: 3.8)
        let field = Tap(at: CGPoint(x: 200, y: 176), down: 4.8, up: 5.0)
        let typed = [field.up + 0.45, field.up + 0.72, field.up + 0.99]   // P, a, y
        let row = Tap(at: CGPoint(x: 100, y: 254), down: typed[2] + 0.9, up: typed[2] + 1.1)
        let swipes = (0..<4).map { i -> Drag in
            let at = row.up + 1.1 + Double(i) * 0.95
            return Drag(from: CGPoint(x: 320, y: 520), to: CGPoint(x: 80, y: 520), start: at, end: at + 0.35)
        }
        let plus = Tap(at: CGPoint(x: 200, y: 791), down: swipes[3].end + 1.3, up: swipes[3].end + 1.5)
        let landed = plus.up + 0.1
        let done = Tap(at: CGPoint(x: 330, y: 33), down: landed + 2.0, up: landed + 2.2)
        let band = CGRect(x: 0, y: 330, width: size.width, height: 400)   // dải widget lướt ngang trong trang của Pay
        // Năm widget của trang đó, do chính code widget vẽ (nét, và không dính mép widget bên cạnh như trong ảnh chụp)
        let spend = SpendEntry(date: now, s: sum, tone: .green), mine = MyQREntry(date: now, qr: qr, tone: .green, s: sum)
        func tile<V: View>(_ w: CGFloat, @ViewBuilder _ v: () -> V) -> (CGFloat, AnyView) {
            (w, AnyView(ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WidgetTone.green.bg)
                v().padding(16)
            }.frame(width: w, height: 158)))
        }
        let tiles = [tile(158) { SpendView(e: spend, size: .systemSmall) }, tile(338) { SpendView(e: spend, size: .systemMedium) },
                     tile(158) { VoiceView(e: spend, size: .systemSmall) }, tile(158) { MyQRView(e: mine, size: .systemSmall) },
                     tile(338) { MyQRView(e: mine, size: .systemMedium) }]
        // Tâm của từng widget trên dải (cách nhau 34pt), widget đang xem nằm giữa màn hình
        var centers: [CGFloat] = [], x: CGFloat = 0
        for (i, tl) in tiles.enumerated() { if i > 0 { x += tiles[i - 1].0 / 2 + 34 + tl.0 / 2 }; centers.append(x) }
        let pageColor = Color(red: 41 / 255, green: 41 / 255, blue: 42 / 255)
        let fieldColor = Color(red: 29 / 255, green: 29 / 255, blue: 28 / 255), sheetColor = Color(red: 35 / 255, green: 34 / 255, blue: 34 / 255)

        return Film(length: done.up + 1.6) { t in
            let dot = touch([hold, edit, add, field, row, plus, done], t) ?? touch(swipes, t)
            let editing = ease(t, jiggle, jiggle + 0.22) * (1 - ease(t, done.up, done.up + 0.22))
            let menu = spring(t, edit.up, 0.32) * (1 - ease(t, add.up, add.up + 0.15))
            let up = ease(t, add.up + 0.05, add.up + 0.5), down = ease(t, landed, landed + 0.42)
            let shift = (p(459) * spring(t, landed + 0.05, 0.55)).rounded()   // các mảnh lùi xuống nhường chỗ cho widget mới
            let pop = spring(t, landed + 0.18, 0.5)
            let n = typed.filter { t >= $0 }.count
            var page = 0, k: CGFloat = 0
            for (i, s) in swipes.enumerated() where t >= s.start { page = i; k = ease(t, s.start, s.end + 0.15) }
            if k >= 1 { page += 1; k = 0 }

            return AnyView(FilmScreen(bare: true, touch: dot) {
                ZStack(alignment: .topLeading) {
                    full(bg)
                    if editing > 0 { full(bgEdit).opacity(Double(editing)) }

                    // Các biểu tượng và widget của màn hình chính: rung khi đang sửa, mỗi cái một nhịp
                    ForEach(Array(pieces.enumerated()), id: \.offset) { i, pc in
                        let big = i < 2
                        let angle = Double(editing) * (big ? 0.55 : 1.9) * sin(t * 27 + Double(i) * 2.1)
                        ZStack(alignment: .topLeading) {
                            if let img = pc.image { Image(uiImage: img).resizable().frame(width: p(pc.frame.width), height: p(pc.frame.height)) }
                            minus(editing).offset(x: p(pc.body.x - pc.frame.minX) - 11, y: p(pc.body.y - pc.frame.minY) - 11)
                        }
                        .frame(width: p(pc.frame.width), height: p(pc.frame.height), alignment: .topLeading)
                        .rotationEffect(.degrees(angle))
                        .offset(x: p(pc.frame.minX).rounded(), y: p(pc.frame.minY).rounded() + shift)
                    }

                    // Widget của Pay vừa thêm: hình do chính code widget vẽ, bật vào chỗ trên cùng
                    if t >= landed + 0.18 {
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 27, style: .continuous).fill(WidgetTone.green.bg)
                                MyQRView(e: MyQREntry(date: now, qr: qr, tone: .green, s: sum), size: .systemMedium).padding(16)
                            }
                            .frame(width: p(798), height: p(374))
                            .overlay(alignment: .topLeading) { minus(editing).offset(x: -8, y: -8) }
                            Text("Pay").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white)
                        }
                        .rotationEffect(.degrees(Double(editing) * 0.5 * sin(t * 27 + 1)))
                        .scaleEffect(0.6 + 0.4 * pop).opacity(Double(min(1, pop * 2)))
                        .offset(x: p(61), y: p(207))
                    }

                    // Bảng của nút Edit
                    if menu > 0.02, let menuImg {
                        Image(uiImage: menuImg).resizable().frame(width: p(570), height: p(429))
                            .scaleEffect(menu, anchor: .topLeading).opacity(Double(min(1, menu * 1.5)))
                            .offset(x: p(90), y: p(143))
                    }

                    // Bảng thêm tiện ích
                    if t >= add.up, down < 1 {
                        Color.black.opacity(0.55 * Double(up * (1 - down)))
                        let y = ((1 - up + down) * (size.height - sheetTop)).rounded()
                        ZStack(alignment: .topLeading) {
                            if t < field.up {
                                sheet(gallery, top: sheetTop)
                            } else if t < row.up + 0.05 {
                                sheet(search, top: sheetTop)
                                // Gõ từng chữ: che các chữ chưa gõ và dòng kết quả, vẽ con trỏ
                                let letters: [CGFloat] = [182, 208, 231, 256]
                                if n < 3 { fieldColor.frame(width: p(letters[3] - letters[n]) + 2, height: p(64)).offset(x: p(letters[n]), y: p(370)) }
                                if Int(t * 2) % 2 == 0 || n < 3 {
                                    Capsule().fill(Color(hex: 0x0A84FF)).frame(width: 2, height: 22).offset(x: p(letters[n]) + 1, y: p(379))
                                }
                                sheetColor.frame(width: size.width, height: p(170)).offset(y: p(500))
                                    .opacity(Double(1 - ease(t, typed[2] + 0.1, typed[2] + 0.35)))
                            } else {
                                // Trang widget của Pay: tên và mô tả mờ chuyển, dải widget lướt ngang
                                let inPage = ease(t, row.up + 0.05, row.up + 0.4)
                                sheet(search, top: sheetTop).opacity(Double(1 - inPage))
                                Group {
                                    sheet(pages[page], top: p(256))
                                    if k > 0 { sheet(pages[page + 1], top: p(256)).opacity(Double(k)) }
                                    // Dải widget: che phần ảnh chụp, vẽ lại các widget và cho lướt ngang
                                    pageColor.frame(width: band.width, height: band.height).offset(y: band.minY)
                                    let at = centers[page] + (centers[min(page + 1, 4)] - centers[page]) * k
                                    ForEach(Array(tiles.enumerated()), id: \.offset) { i, tl in
                                        tl.1.scaleEffect(0.94)
                                            .position(x: (size.width / 2 + centers[i] - at).rounded(), y: band.midY - 14)
                                    }
                                }
                                .frame(width: size.width, height: size.height, alignment: .topLeading)
                                .clipped()
                                .opacity(Double(inPage))
                                .offset(x: (40 * (1 - inPage)).rounded())
                            }
                        }
                        .frame(width: size.width, height: size.height, alignment: .topLeading)
                        .offset(y: y)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            })
        }
    }
}
#endif
