#if DEBUG
import CoreImage.CIFilterBuiltins
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
            let dot = pointer([hold, edit, add, field, row, plus, done], swipes, t)
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
                            Text("Pay").font(.app(size: 12.5, weight: .medium)).foregroundStyle(.white)
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

// MARK: - Phim "Quét QR, trả tiền"

#if DEBUG

/// Phim "Quét QR, trả tiền": bấm Quét QR, đưa mã của quán vào khung, lần đầu chọn app ngân hàng, gõ số tiền,
/// Lưu & mở Bank (app ngân hàng mở màn chuyển tiền đã điền sẵn), xác nhận, quay lại Pay: khoản đã ghi.
extension FilmExport {
    static func scan(_ store: Store) -> Film {
        let en = Lang.isEnglish
        // Quán trong phim là quán bịa; mã QR vẽ ra chỉ chứa một đường dẫn vô hại (quét thử không trả tiền cho ai)
        let qr = VietQR(raw: "", bin: "970436", acct: "0071000123456", amount: nil, name: "COM TAM BA NAM", purpose: "")
        let shop = en ? "Ba Nam Broken Rice" : "Cơm tấm Bà Năm"
        let scanTap = Tap(at: CGPoint(x: 290, y: 792), down: 1.0, up: 1.15)
        let found = 3.4
        let bankRow = Tap(at: SCAN.bankRow, down: 6.0, up: 6.2)
        let keys: [(String, Double)] = [("6", 7.3), ("5", 7.8), ("000", 8.4)]
        let keyTaps = keys.map { Tap(at: SCAN.key[$0.0]!, down: $0.1, up: $0.1 + 0.14) }
        let open = Tap(at: CGPoint(x: 262, y: 818), down: 9.8, up: 10.0)
        let confirm = Tap(at: CGPoint(x: 201, y: 790), down: 12.7, up: 12.9)
        let back = 14.6
        var saved = false
        return Film(length: 18.6) { t in
            if !saved, t >= open.up {
                saved = true
                store.appId = BankData.apps.first(where: \.fill)?.id ?? store.appId
                store.add(amount: 65_000, note: qr.name, cat: store.guessCategory("cơm tấm"), acct: qr.memoKey, toast: false)
            }
            // Màn hình chính: nút Quét QR nhấn; quay lại từ app ngân hàng thì thanh Đã lưu hiện một lúc
            var home = FilmFrame()
            home.time = t
            home.pressed["dock-scan"] = press(scanTap, t)
            home.toast = ease(t, back + 0.5, back + 0.85) * (1 - ease(t, back + 3.3, back + 3.7))
            // Máy quét trượt lên, quét được thì loé xanh rồi nhường chỗ cho màn trả tiền
            let scanner = ease(t, scanTap.up, scanTap.up + 0.42) * (1 - ease(t, found + 0.35, found + 0.6))
            let aim = ease(t, 1.8, found - 0.15)
            let flash = ease(t, found, found + 0.12) * (1 - ease(t, found + 0.25, found + 0.5))
            // Màn trả tiền: trượt lên sau khi quét, gõ số tiền, bấm Lưu & mở Bank thì lùi đi
            let entryUp = ease(t, found + 0.4, found + 0.85) * (1 - ease(t, open.up + 0.1, open.up + 0.4))
            var entry = FilmFrame()
            entry.time = t
            let typed = keys.filter { t >= $0.1 + 0.07 }.map(\.0).joined()
            entry.entry = .init(digits: typed, note: qr.name, cat: store.guessCategory("cơm tấm"),
                                key: keys.first(where: { t >= $0.1 && t < $0.1 + 0.16 })?.0)
            entry.pressed["bank"] = press(open, t)
            // Lần quét đầu: Pay hỏi dùng app ngân hàng nào
            let chooser = ease(t, found + 1.2, found + 1.6) * (1 - ease(t, bankRow.up + 0.1, bankRow.up + 0.5))
            // App ngân hàng: mở lên từ Pay, xác nhận, rồi quay về Pay
            let bank = ease(t, open.up + 0.3, open.up + 0.75) * (1 - ease(t, back, back + 0.45))
            let paid = ease(t, confirm.up + 0.1, confirm.up + 0.4)
            let size = FilmScreen<EmptyView>.size
            let dot = pointer([scanTap, bankRow] + keyTaps + [open, confirm], [], t)
            return AnyView(FilmScreen(lightStatus: scanner > 0.5 || bank > 0.5, touch: dot) {
                ZStack {
                    HomeView().environment(\.film, home)
                    if entryUp > 0 {
                        FilmSheet(shown: chooser) {
                            EntryView(mode: .scan(qr))
                                .padding(.top, FilmScreen<EmptyView>.insets.top).padding(.bottom, FilmScreen<EmptyView>.insets.bottom)
                                .background(Palette.surface)
                                .environment(\.film, entry)
                        } content: {
                            FilmBankChooser(pressed: press(bankRow, t))
                        }
                        .offset(y: ((1 - entryUp) * size.height).rounded())
                    }
                    if scanner > 0 {
                        FilmCamera(shop: shop, t: t, aim: aim, lock: ease(t, found - 0.55, found - 0.05), flash: flash)
                            .offset(y: ((1 - scanner) * size.height).rounded())
                    }
                    if bank > 0 {
                        FilmBankApp(name: qr.name, acct: qr.acct ?? "", bank: qr.bank, amount: 65_000, paid: paid,
                                    pressed: press(confirm, t))
                            .scaleEffect(0.9 + 0.1 * bank).opacity(Double(bank))
                    }
                }
                .frame(width: size.width, height: size.height)
            })
        }
    }

    /// Chỗ chạm trong phim quét QR (đo trên khung hình đã vẽ)
    enum SCAN {
        static let bankRow = CGPoint(x: 140, y: 222)
        static let key: [String: CGPoint] = ["6": CGPoint(x: 325, y: 556), "5": CGPoint(x: 201, y: 556), "000": CGPoint(x: 75, y: 718)]
    }
}

/// Máy quét trong phim, như nhìn qua camera thật: tấm biển mã QR bằng mica trên mặt bàn gỗ của quán, ly trà đá bên cạnh,
/// tường phía sau tối dần, góc ảnh tối như ống kính. Máy cầm tay: khung hình rung nhẹ và tiến lại gần (`aim` 0…1),
/// càng gần càng đứng yên; khi mã vào khung thì góc ngắm vàng bám theo mã (`lock` 0…1), bắt được thì xanh và loé (`flash`).
private struct FilmCamera: View {
    let shop: String
    let t: Double
    let aim: CGFloat
    let lock: CGFloat
    let flash: CGFloat

    var body: some View {
        let size = FilmScreen<EmptyView>.size, side = size.width * 0.68
        let center = CGPoint(x: size.width / 2, y: size.height * 0.45)
        // Tay cầm máy: lắc theo vài nhịp chồng lên nhau, nhỏ dần khi đã ngắm trúng
        let shake = 1 - 0.85 * aim
        let jx = (sin(t * 5.3) * 6 + sin(t * 11.7) * 2.5) * shake, jy = (cos(t * 4.1) * 5 + sin(t * 9.3) * 2) * shake
        let tilt = (sin(t * 3.2) * 1.4) * Double(shake)
        // Tiến lại gần: cả cảnh to dần, tấm biển từ lệch dưới phải vào giữa khung
        let zoom = 0.8 + 0.27 * aim
        let standeeAt = CGPoint(x: center.x + 64 * (1 - aim), y: center.y + 96 * (1 - aim))
        // Chỗ mã QR trên màn hình: theo tấm biển (mã nằm giữa biển, lệch lên một chút) và độ to của cả cảnh
        let qrSide = Self.qrSide * zoom
        let qrCenter = CGPoint(x: (standeeAt.x - center.x) * zoom + center.x + jx,
                               y: (standeeAt.y - center.y) * zoom + center.y + jy + Self.qrOffsetY * zoom)
        ZStack {
            Color(hex: 0x241A14)
            scene(size: size, standeeAt: standeeAt)
                .scaleEffect(zoom, anchor: UnitPoint(x: center.x / size.width, y: center.y / size.height))
                .rotationEffect(.degrees(tilt))
                .offset(x: jx, y: jy)
            vignette(size)
            // Khung ngắm của Pay: ngoài khung phủ tối (tô chẵn lẻ, PDF vẽ được), viền trắng, bắt được mã thì xanh
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                p.addRoundedRect(in: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side),
                                 cornerSize: CGSize(width: 36, height: 36), style: .continuous)
            }
            .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(flash > 0 ? Palette.goodInk : .white.opacity(0.9), lineWidth: 3 + 2 * flash)
                .frame(width: side, height: side).position(center)
            // Góc ngắm bám theo mã: hiện dần, co về đúng mép mã, bắt được thì đổi xanh
            if lock > 0 {
                let pad = 18 * (1 - lock) + 6
                brackets(side: qrSide + pad * 2, color: flash > 0 ? Palette.goodInk : Color(hex: 0xFFD60A))
                    .position(qrCenter).opacity(Double(min(1, lock * 2)))
            }
            Color.white.opacity(0.3 * Double(flash))
            VStack {
                Text(L("Đưa mã QR của quán vào khung"))
                    .font(.app(size: 18, weight: .medium)).foregroundStyle(.white)
                    .padding(.top, 20 + FilmScreen<EmptyView>.insets.top)
                Spacer()
                HStack(spacing: 12) { pill(L("Chọn ảnh QR")); pill(L("Đóng")) }
                    .padding(.horizontal, 16).padding(.bottom, 12 + FilmScreen<EmptyView>.insets.bottom)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    // MARK: Cảnh trong quán

    /// Cảnh vẽ rộng hơn màn hình (máy lắc, nghiêng, thu nhỏ vẫn phủ kín): toạ độ trên màn hình cộng thêm (dx, dy)
    private func scene(size screen: CGSize, standeeAt s: CGPoint) -> some View {
        let size = CGSize(width: screen.width * 1.7, height: screen.height * 1.5)
        let dx = (size.width - screen.width) / 2, dy = (size.height - screen.height) / 2
        let standeeAt = CGPoint(x: s.x + dx, y: s.y + dy)
        let tableTop = screen.height * 0.56 + dy
        return ZStack(alignment: .topLeading) {
            // Tường quán: ấm, tối dần lên trên; vài mảng đèn mờ phía xa
            LinearGradient(colors: [Color(hex: 0x241A14), Color(hex: 0x5B4433), Color(hex: 0x6E5440)], startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(hex: 0xF3C98B)).frame(width: 150).position(x: 70 + dx, y: 150 + dy).opacity(0.18)
            Circle().fill(Color(hex: 0xF3C98B)).frame(width: 90).position(x: 330 + dx, y: 110 + dy).opacity(0.14)
            Circle().fill(Color(hex: 0xF3C98B)).frame(width: 60).position(x: 250 + dx, y: 230 + dy).opacity(0.1)
            // Mặt bàn gỗ: các tấm ván, vân gỗ mảnh, mép bàn sáng
            table(size: size, top: tableTop)
            // Ly trà đá bên trái, sau tấm biển
            iceTea.position(x: standeeAt.x - 128, y: standeeAt.y + 70)
            // Bóng tấm biển trên mặt bàn, rồi tấm biển
            Ellipse().fill(Color.black.opacity(0.35)).frame(width: 230, height: 34).position(x: standeeAt.x + 14, y: standeeAt.y + 168)
            standee.position(standeeAt)
        }
        .frame(width: size.width, height: size.height)
        .position(x: screen.width / 2, y: screen.height / 2)
        .frame(width: screen.width, height: screen.height)
    }

    private func table(size: CGSize, top: CGFloat) -> some View {
        let planks = 7
        return ZStack(alignment: .topLeading) {
            ForEach(0..<planks, id: \.self) { i in
                let h = (size.height - top) / CGFloat(planks)
                let tone = [0xA0714A, 0x96683F, 0xA87850, 0x8F6239, 0x9C6D45, 0xA4744C, 0x93653C][i]
                Rectangle().fill(Color(hex: UInt32(tone))).frame(width: size.width, height: h + 1).offset(y: top + CGFloat(i) * h)
                // Vân gỗ: vài đường cong mảnh trên mỗi tấm
                Path { p in
                    for k in 0..<3 {
                        let y = top + CGFloat(i) * h + h * (0.25 + 0.25 * CGFloat(k))
                        p.move(to: CGPoint(x: -10, y: y))
                        p.addCurve(to: CGPoint(x: size.width + 10, y: y + CGFloat((i + k) % 3 - 1) * 4),
                                   control1: CGPoint(x: size.width * 0.3, y: y - 5), control2: CGPoint(x: size.width * 0.7, y: y + 6))
                    }
                }
                .stroke(Color.black.opacity(0.09), lineWidth: 1)
                Rectangle().fill(Color.black.opacity(0.18)).frame(width: size.width, height: 1).offset(y: top + CGFloat(i + 1) * h)
            }
            Rectangle().fill(Color(hex: 0xC9976A)).frame(width: size.width, height: 3).offset(y: top)
        }
    }

    private var iceTea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: 0xC27A2C).opacity(0.85)).frame(width: 74, height: 120)
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.22)).frame(width: 74, height: 30).offset(y: -45)
            ForEach(0..<4, id: \.self) { k in
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.35)).frame(width: 18, height: 16)
                    .offset(x: CGFloat([-16, 12, -6, 16][k]), y: CGFloat([-36, -30, -18, -6][k])).rotationEffect(.degrees(Double(k * 17)))
            }
            Rectangle().fill(Color.white.opacity(0.3)).frame(width: 6, height: 108).offset(x: -26)
            RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.45), lineWidth: 2).frame(width: 74, height: 120)
        }
    }

    /// Tấm biển mica: khung trong dày, tấm in trắng bên trong, chân đế tối
    private var standee: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(shop).font(.app(size: 19, weight: .heavy)).foregroundStyle(Color(hex: 0xB0302A))
                Text(Lang.isEnglish ? "Scan to pay" : "Quét mã để thanh toán").font(.app(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x3A3A3C))
                if let img = Self.code { Image(uiImage: img).interpolation(.none).resizable().frame(width: Self.qrSide, height: Self.qrSide) }
                Text("COM TAM BA NAM").font(.app(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0x1D1D1F))
                Text("0071 000 123 456").font(.app(size: 12, weight: .medium)).foregroundStyle(Color(hex: 0x6E6E73))
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(9)
            .background(Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.6), lineWidth: 1.5))
            // Chân đế
            UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 4, style: .continuous)
                .fill(Color(hex: 0x2C2C2E)).frame(width: 214, height: 18)
        }
    }

    private func vignette(_ size: CGSize) -> some View {
        // Góc tối như ống kính: các vòng đồng tâm, ngoài đậm trong nhạt
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                let r = size.height * (0.62 + 0.08 * CGFloat(i))
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: size))
                    p.addEllipse(in: CGRect(x: size.width / 2 - r * 0.62, y: size.height * 0.45 - r * 0.55, width: r * 1.24, height: r * 1.1))
                }
                .fill(Color.black.opacity(0.07), style: FillStyle(eoFill: true))
            }
        }
    }

    private func brackets(side: CGFloat, color: Color) -> some View {
        let arm = side * 0.22
        return Path { p in
            let h = side / 2
            for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] {
                let c = CGPoint(x: h + CGFloat(sx) * h, y: h + CGFloat(sy) * h)
                p.move(to: CGPoint(x: c.x, y: c.y - CGFloat(sy) * arm))
                p.addLine(to: c)
                p.addLine(to: CGPoint(x: c.x - CGFloat(sx) * arm, y: c.y))
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        .frame(width: side, height: side)
    }

    private func pill(_ s: String) -> some View {
        Text(s).font(.app(size: 18, weight: .semibold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(.white.opacity(0.18), in: Capsule())
    }

    /// Cạnh mã QR trên biển, và mã lệch lên khỏi tâm biển bao nhiêu (theo bố cục của `standee`)
    static let qrSide: CGFloat = 150
    static let qrOffsetY: CGFloat = -8

    /// Mã QR vẽ trên biển: chỉ chứa đường dẫn tới trang của Pay, không phải mã chuyển tiền thật
    static let code: UIImage? = {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data("https://peakapp.vn/pay".utf8)
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }()
}

/// Bảng "Bạn dùng app ngân hàng nào?" của lần quét đầu, vẽ lại cho phim (danh sách của iOS không vẽ ra được)
private struct FilmBankChooser: View {
    var pressed: CGFloat

    var body: some View {
        let fill = BankData.apps.filter(\.fill), rest = BankData.apps.filter { !$0.fill }
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Bạn dùng app ngân hàng nào?")).font(.app(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: 56)
            VStack(alignment: .leading, spacing: 8) {
                header(L("Mở sẵn người nhận + số tiền"),
                       L("Quét xong, Pay mở thẳng màn chuyển tiền trong app ngân hàng, đã điền sẵn người nhận và số tiền. Bạn chỉ cần xác nhận."))
                group(fill, first: true)
                header(L("Chỉ mở app (quét lại QR)"),
                       L("Các ngân hàng này chưa cho app khác điền sẵn thông tin chuyển tiền. Pay ghi khoản chi rồi mở app ngân hàng, bạn quét lại mã QR trong đó để trả."))
                    .padding(.top, 14)
                group(Array(rest.prefix(6)), first: false)
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 0)
        }
        .background(Palette.bg)
    }

    private func header(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.app(size: 15, weight: .semibold))
            Text(detail).font(.app(size: 14)).foregroundStyle(Color.primary.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private func group(_ apps: [BankApp], first: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(apps.enumerated()), id: \.offset) { i, a in
                Text(a.name).font(.app(size: 17)).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).frame(height: 46)
                    .background(first && i == 0 ? Color.primary.opacity(0.08 * Double(pressed)) : .clear)
                if i < apps.count - 1 { Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 0.5).padding(.leading, 16) }
            }
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// App ngân hàng trong phim: một màn chuyển tiền chung chung (không phải app của ngân hàng nào), Pay đã điền sẵn
/// người nhận và số tiền; xác nhận thì hiện đã chuyển.
private struct FilmBankApp: View {
    let name: String
    let acct: String
    let bank: String
    let amount: Int
    var paid: CGFloat
    var pressed: CGFloat

    var body: some View {
        let en = Lang.isEnglish
        let size = FilmScreen<EmptyView>.size
        ZStack {
            Color(hex: 0x14365C)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "building.columns.fill").font(.app(size: 20))
                    Text(en ? "Your bank app" : "App ngân hàng của bạn").font(.app(size: 17, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, FilmScreen<EmptyView>.insets.top + 14)
                Text(en ? "Transfer" : "Chuyển tiền").font(.app(size: 30, weight: .bold)).foregroundStyle(.white).padding(.top, 18)
                VStack(alignment: .leading, spacing: 16) {
                    field(en ? "To" : "Người nhận", name)
                    field(en ? "Account" : "Số tài khoản", "\(acct) · \(bank)")
                    field(en ? "Amount" : "Số tiền", fmt(amount), big: true)
                    field(en ? "Note" : "Nội dung", en ? "Paid via Pay" : "Thanh toán qua Pay")
                }
                .padding(20)
                .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.top, 20)
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Color(hex: 0x7BE495))
                    Text(en ? "Filled in by Pay" : "Pay đã điền sẵn").foregroundStyle(.white.opacity(0.85))
                }
                .font(.app(size: 15, weight: .medium)).padding(.top, 14)
                Spacer()
                Text(en ? "Confirm" : "Xác nhận").font(.app(size: 21, weight: .semibold)).foregroundStyle(Color(hex: 0x14365C))
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(.white, in: Capsule())
                    .filmPressed(pressed)
                    .padding(.bottom, FilmScreen<EmptyView>.insets.bottom + 6)
            }
            .padding(.horizontal, 20)
            if paid > 0 {
                Color(hex: 0x14365C).opacity(0.94 * Double(paid))
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill").font(.app(size: 76)).foregroundStyle(Color(hex: 0x7BE495))
                    Text(en ? "Sent" : "Đã chuyển").font(.app(size: 28, weight: .bold)).foregroundStyle(.white)
                    Text(fmt(amount)).font(.app(size: 22, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                }
                .scaleEffect(0.85 + 0.15 * paid).opacity(Double(paid))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func field(_ label: String, _ value: String, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.app(size: 14)).foregroundStyle(Color(hex: 0x6E6E73))
            Text(value).font(.app(size: big ? 28 : 18, weight: big ? .bold : .semibold)).foregroundStyle(Color(hex: 0x1D1D1F)).lineLimit(1)
        }
    }
}
#endif
