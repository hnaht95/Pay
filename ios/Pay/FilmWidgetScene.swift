#if DEBUG
import SwiftUI

/// Phim "Widget": dựng từ ảnh chụp thật của máy ảo iOS (web/film/vector/assets/widget-NN.jpg, make.sh chép vào
/// Documents/film-assets): màn hình chính, nhấn giữ khoảng trống, Edit > Add Widget, tìm "pay", lướt qua các widget
/// của Pay rồi thêm widget cỡ vừa. Phim chỉ ghép các ảnh đó theo thời gian và vẽ chấm chạm.
extension FilmExport {
    private static let size = FilmScreen<EmptyView>.size

    private static func shot(_ n: Int) -> UIImage? {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return UIImage(contentsOfFile: dir.appendingPathComponent(String(format: "film-assets/widget-%02d.jpg", n)).path)
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

    static func widget(_ store: Store) -> Film {
        let img = (0...12).map { $0 == 0 ? nil : shot($0) }   // img[1]…img[12]
        let sheetTop: CGFloat = 122
        let hold = Tap(at: CGPoint(x: 200, y: 600), down: 0.9, up: 1.8)
        let jiggle = hold.down + 0.55
        let edit = Tap(at: CGPoint(x: 72, y: 33), down: 2.5, up: 2.7)
        let add = Tap(at: CGPoint(x: 140, y: 93), down: 3.5, up: 3.7)
        let field = Tap(at: CGPoint(x: 200, y: 176), down: 4.7, up: 4.9)
        let typed = field.up + 0.7
        let row = Tap(at: CGPoint(x: 100, y: 254), down: typed + 0.8, up: typed + 1.0)
        let swipes = (0..<4).map { i -> Drag in
            let at = row.up + 1.1 + Double(i) * 0.95
            return Drag(from: CGPoint(x: 320, y: 520), to: CGPoint(x: 80, y: 520), start: at, end: at + 0.35)
        }
        let plus = Tap(at: CGPoint(x: 200, y: 791), down: swipes[3].end + 1.3, up: swipes[3].end + 1.5)
        let done = Tap(at: CGPoint(x: 330, y: 33), down: plus.up + 1.9, up: plus.up + 2.1)
        // Dải ở giữa trang widget (chỗ widget lướt ngang); tên và mô tả phía trên thì đổi giữa chừng lần lướt
        let band = CGRect(x: 0, y: 330, width: size.width, height: 400)

        return Film(length: done.up + 1.6) { t in
            let dot = touch([hold, edit, add, field, row, plus, done], t) ?? touch(swipes, t)
            let up = ease(t, add.up, add.up + 0.45), down = ease(t, plus.up, plus.up + 0.4)
            // Đang ở trang widget thứ mấy (0…4) và đang lướt tới đâu
            var page = 0, k: CGFloat = 0
            for (i, s) in swipes.enumerated() where t >= s.start { page = i; k = ease(t, s.start, s.end + 0.15) }
            if k >= 1 { page += 1; k = 0 }
            return AnyView(FilmScreen(bare: true, touch: dot) {
                ZStack {
                    // Màn hình chính phía sau
                    if t >= done.up { full(img[12]) }
                    else if t >= plus.up { full(img[11]) }
                    else if t >= edit.up + 0.05, t < add.up + 0.1 { full(img[3]) }
                    else if t >= jiggle { full(img[2]) }
                    else { full(img[1]) }

                    // Bảng thêm tiện ích
                    if t >= add.up, down < 1 {
                        Color.black.opacity(0.55 * Double(up * (1 - down)))
                        let y = ((1 - up) * (size.height - sheetTop) + down * (size.height - sheetTop)).rounded()
                        if t < typed { sheet(img[4], top: sheetTop).offset(y: y) }
                        else if t < row.up + 0.05 { sheet(img[5], top: sheetTop).offset(y: y) }
                        else {
                            ZStack {
                                sheet(img[6 + (k > 0.5 ? page + 1 : page)], top: 112)
                                if k > 0 {
                                    ZStack {
                                        full(img[6 + page]).offset(x: (-size.width * k).rounded())
                                        full(img[7 + page]).offset(x: (size.width * (1 - k)).rounded())
                                    }
                                    .mask { Rectangle().frame(width: band.width, height: band.height).position(x: band.midX, y: band.midY) }
                                }
                            }
                            .offset(y: y)
                        }
                    }
                }
                .frame(width: size.width, height: size.height)
            })
        }
    }
}
#endif
