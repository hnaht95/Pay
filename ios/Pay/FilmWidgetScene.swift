#if DEBUG
import SwiftUI
import WidgetKit

/// Phim "Widget": màn hình chính của iPhone (dựng lại bằng hình vẽ, biểu tượng app chỉ là ô màu + ký hiệu chung),
/// nhấn giữ khoảng trống cho các biểu tượng rung, bấm Sửa > Thêm tiện ích, gõ "pay" để tìm, lướt qua một lượt
/// các widget của Pay rồi thêm widget cỡ vừa ra màn hình chính. Hình widget do chính code widget vẽ (Shared/WidgetViews.swift).
extension FilmExport {
    private static var en: Bool { Lang.isEnglish }
    private static let size = FilmScreen<EmptyView>.size

    private struct AppIcon { let symbol: String; let color: UInt32; let vi: String; let en: String }
    private static let apps: [AppIcon] = [
        AppIcon(symbol: "", color: 0xFFFFFF, vi: "Pay", en: "Pay"),
        AppIcon(symbol: "camera.fill", color: 0x8E8E93, vi: "Camera", en: "Camera"),
        AppIcon(symbol: "photo.fill", color: 0xFF9F0A, vi: "Ảnh", en: "Photos"),
        AppIcon(symbol: "map.fill", color: 0x30B0C7, vi: "Bản đồ", en: "Maps"),
        AppIcon(symbol: "calendar", color: 0xFF3B30, vi: "Lịch", en: "Calendar"),
        AppIcon(symbol: "clock.fill", color: 0x1C1C1E, vi: "Đồng hồ", en: "Clock"),
        AppIcon(symbol: "note.text", color: 0xFFCC00, vi: "Ghi chú", en: "Notes"),
        AppIcon(symbol: "cloud.sun.fill", color: 0x0A84FF, vi: "Thời tiết", en: "Weather"),
        AppIcon(symbol: "envelope.fill", color: 0x0A84FF, vi: "Mail", en: "Mail"),
        AppIcon(symbol: "heart.fill", color: 0xFF2D55, vi: "Sức khoẻ", en: "Health"),
        AppIcon(symbol: "gearshape.fill", color: 0x8E8E93, vi: "Cài đặt", en: "Settings"),
    ]
    private static let dock: [AppIcon] = [
        AppIcon(symbol: "phone.fill", color: 0x34C759, vi: "", en: ""), AppIcon(symbol: "safari.fill", color: 0x0A84FF, vi: "", en: ""),
        AppIcon(symbol: "message.fill", color: 0x34C759, vi: "", en: ""), AppIcon(symbol: "music.note", color: 0xFF2D55, vi: "", en: ""),
    ]

    /// Ô biểu tượng app 64pt; `wiggle` là góc rung (độ) khi đang sửa màn hình chính, có dấu trừ ở góc
    private static func icon(_ a: AppIcon, wiggle: Double, edit: CGFloat, label: Bool = true) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color(hex: a.color))
                if a.symbol.isEmpty { Image("logo-pay").resizable().scaledToFit().padding(10) }
                else { Image(systemName: a.symbol).font(.system(size: 30, weight: .semibold)).foregroundStyle(.white) }
            }
            .frame(width: 64, height: 64)
            .overlay(alignment: .topLeading) {
                ZStack {
                    Circle().fill(Color(hex: 0xD9D9DE))
                    Capsule().fill(Color(hex: 0x1C1C1E)).frame(width: 10, height: 2.5)
                }
                .frame(width: 22, height: 22).scaleEffect(edit).offset(x: -7, y: -7)
            }
            if label { Text(en ? a.en : a.vi).font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(1) }
        }
        .frame(width: 80)
        .rotationEffect(.degrees(wiggle))
    }

    private static func pill(_ text: String) -> some View {
        Text(text).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).frame(height: 34)
            .background(.white.opacity(0.28), in: Capsule())
    }

    /// Một widget: nền bo góc màu xanh của Pay, nội dung lề 16pt
    private static func card<V: View>(_ w: CGFloat, _ h: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WidgetTone.green.bg)
            content().padding(16)
        }
        .frame(width: w, height: h)
    }

    private struct Page { let title: String; let text: String; let view: AnyView }

    static func widget(_ store: Store) -> Film {
        let now = Date()
        let s = Summary(today: 125_000, month: store.monthItems(now).reduce(0) { $0 + $1.a } + 125_000, count: 3, day: now, budget: store.budget)
        let qr = MyQR(bin: "970416", bank: "ACB", acct: "123456789", name: "NGUYEN VAN A")
        let spend = SpendEntry(date: now, s: s, tone: .green), mine = MyQREntry(date: now, qr: qr, tone: .green, s: s)
        let spendText = L("Xem nhanh số đã chi, chạm để quét QR, nói hoặc nhập khoản mới.")
        let qrText = L("Mã VietQR của bạn ngay trên màn hình chính, người khác quét là chuyển khoản.")
        let pages = [
            Page(title: L("Chi tiêu hôm nay"), text: spendText, view: AnyView(card(158, 158) { SpendView(e: spend, size: .systemSmall) })),
            Page(title: L("Nói để ghi"), text: L("Chạm là Pay nghe luôn, nói \"35k cafe\" là ghi."), view: AnyView(card(158, 158) { VoiceView(e: spend, size: .systemSmall) })),
            Page(title: L("Mã QR nhận tiền"), text: qrText, view: AnyView(card(158, 158) { MyQRView(e: mine, size: .systemSmall) })),
            Page(title: L("Mã QR nhận tiền"), text: qrText, view: AnyView(card(338, 158) { MyQRView(e: mine, size: .systemMedium) })),
            Page(title: L("Chi tiêu hôm nay"), text: spendText, view: AnyView(card(338, 158) { SpendView(e: spend, size: .systemMedium) })),
        ]

        // Mốc thời gian
        let hold = Tap(at: CGPoint(x: 200, y: 560), down: 0.9, up: 1.7)          // nhấn giữ khoảng trống
        let jiggle = hold.down + 0.5
        let edit = Tap(at: CGPoint(x: 58, y: 74), down: 2.3, up: 2.5)            // nút Sửa
        let add = Tap(at: CGPoint(x: 120, y: 122), down: 3.3, up: 3.5)           // Thêm tiện ích
        let sheetUp = add.up + 0.1
        let field = Tap(at: CGPoint(x: 200, y: 113), down: sheetUp + 0.8, up: sheetUp + 1.0)
        let typed = [field.up + 0.4, field.up + 0.68, field.up + 0.96]          // p, a, y
        let row = Tap(at: CGPoint(x: 160, y: 179), down: typed[2] + 0.7, up: typed[2] + 0.9)
        let pageIn = row.up + 0.05
        let swipes = (0..<4).map { i -> Drag in
            let at = pageIn + 1.0 + Double(i) * 0.95
            return Drag(from: CGPoint(x: 310, y: 400), to: CGPoint(x: 90, y: 400), start: at, end: at + 0.4)
        }
        let plus = Tap(at: CGPoint(x: 201, y: 797), down: swipes[3].end + 1.1, up: swipes[3].end + 1.3)
        let landed = plus.up + 0.15
        let done = Tap(at: CGPoint(x: 346, y: 74), down: landed + 1.5, up: landed + 1.7)
        let word = "pay"

        return Film(length: done.up + 1.5) { t in
            let editing = ease(t, jiggle, jiggle + 0.2) * (1 - ease(t, done.up, done.up + 0.2))
            let menu = spring(t, edit.up, 0.3) * (1 - ease(t, add.up, add.up + 0.15))
            let sheet = ease(t, sheetUp, sheetUp + 0.45) * (1 - ease(t, landed, landed + 0.4))
            let n = typed.filter { t >= $0 }.count
            let page = ease(t, pageIn, pageIn + 0.4)
            let shown = swipes.reduce(CGFloat(0)) { $0 + ease(t, $1.start, $1.end + 0.12) }   // đang ở trang thứ mấy của dải widget
            let current = min(pages.count - 1, Int(shown.rounded()))
            let placed = spring(t, landed + 0.15, 0.5)
            let shift = (204 * ease(t, landed, landed + 0.4)).rounded()   // các biểu tượng nhường hai hàng cho widget
            let dot = touch([hold, edit, add, field, row, plus, done], t) ?? touch(swipes, t)
            let top = FilmScreen<EmptyView>.insets.top

            return AnyView(FilmScreen(lightStatus: true, touch: dot) {
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [Color(hex: 0x1F2A5C), Color(hex: 0x5B3F8C), Color(hex: 0xD98BB4)], startPoint: .top, endPoint: .bottom)

                    // Lưới biểu tượng, 4 cột
                    ForEach(Array(apps.enumerated()), id: \.offset) { i, a in
                        icon(a, wiggle: Double(editing) * 1.7 * sin(t * 26 + Double(i) * 1.9), edit: editing)
                            .position(x: 59 + CGFloat(i % 4) * 94.7, y: 150 + CGFloat(i / 4) * 102 + shift)
                    }
                    // Widget vừa thêm
                    if t >= landed + 0.15 {
                        pages[4].view
                            .scaleEffect(0.7 + 0.3 * placed)
                            .rotationEffect(.degrees(Double(editing) * 0.5 * sin(t * 26)))
                            .position(x: size.width / 2, y: 104 + 79)
                    }
                    // Ô tìm kiếm và Dock
                    Label(en ? "Search" : "Tìm kiếm", systemImage: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 30).background(.white.opacity(0.22), in: Capsule())
                        .position(x: size.width / 2, y: 738)
                    RoundedRectangle(cornerRadius: 36, style: .continuous).fill(.white.opacity(0.22))
                        .frame(width: 370, height: 96).position(x: size.width / 2, y: size.height - 62)
                    ForEach(Array(dock.enumerated()), id: \.offset) { i, a in
                        icon(a, wiggle: Double(editing) * 1.7 * sin(t * 26 + Double(i) * 2.3 + 1), edit: editing, label: false)
                            .position(x: 59 + CGFloat(i) * 94.7, y: size.height - 62)
                    }

                    // Đang sửa màn hình chính: nút Sửa và Xong
                    if editing > 0 {
                        pill(en ? "Edit" : "Sửa").filmPressed(press(edit, t)).scaleEffect(editing).position(x: 58, y: 74)
                        pill(en ? "Done" : "Xong").filmPressed(press(done, t)).scaleEffect(editing).position(x: 346, y: 74)
                    }
                    // Bảng của nút Sửa
                    if menu > 0.02 {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array([("plus.square.on.square", en ? "Add Widget" : "Thêm tiện ích"),
                                           ("paintbrush", en ? "Customize" : "Tuỳ chỉnh"),
                                           ("rectangle.on.rectangle", en ? "Edit Pages" : "Sửa trang")].enumerated()), id: \.offset) { i, m in
                                HStack(spacing: 12) {
                                    Image(systemName: m.0).font(.system(size: 17, weight: .medium)).frame(width: 24)
                                    Text(m.1).font(.system(size: 17))
                                    Spacer()
                                }
                                .foregroundStyle(Color(hex: 0x111114))
                                .padding(.horizontal, 16).frame(height: 46)
                                .background(i == 0 ? Color.black.opacity(0.1 * Double(press(add, t))) : .clear)
                            }
                        }
                        .frame(width: 236)
                        .background(Color(hex: 0xF4F4F6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .scaleEffect(menu, anchor: .topLeading)
                        .offset(x: 22, y: 98)
                    }

                    // Bảng thêm tiện ích
                    if sheet > 0 {
                        Color.black.opacity(0.3 * Double(sheet))
                        ZStack(alignment: .topLeading) {
                            Color(hex: 0xF2F2F7)
                            // Trang tìm kiếm
                            VStack(alignment: .leading, spacing: 0) {
                                Capsule().fill(Color.black.opacity(0.2)).frame(width: 36, height: 5).frame(maxWidth: .infinity).padding(.top, 8)
                                HStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass").foregroundStyle(Color(hex: 0x8E8E93))
                                    if n == 0 { Text(en ? "Search Widgets" : "Tìm kiếm tiện ích").foregroundStyle(Color(hex: 0x8E8E93)) }
                                    else { Text(String(word.prefix(n))).foregroundStyle(Color(hex: 0x111114)) }
                                    // Con trỏ nhấp nháy khi đang gõ
                                    if t >= field.up, Int(t * 2) % 2 == 0 || n < 3 { Capsule().fill(Color(hex: 0x007AFF)).frame(width: 2, height: 20) }
                                    Spacer()
                                }
                                .font(.system(size: 17))
                                .padding(.horizontal, 12).frame(height: 40)
                                .background(Color.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .padding(.horizontal, 16).padding(.top, 18)
                                if n == 0 {
                                    // Gợi ý: vài ô xám giữ chỗ
                                    Text(en ? "Suggestions" : "Gợi ý").font(.system(size: 20, weight: .bold)).foregroundStyle(Color(hex: 0x111114))
                                        .padding(.horizontal, 20).padding(.top, 22)
                                    HStack(spacing: 16) {
                                        ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black.opacity(0.07)).frame(height: 170) }
                                    }
                                    .padding(.horizontal, 20).padding(.top, 12)
                                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black.opacity(0.07)).frame(height: 170)
                                        .padding(.horizontal, 20).padding(.top, 16)
                                } else {
                                    HStack(spacing: 14) {
                                        Image("logo-pay").resizable().scaledToFit().padding(6).frame(width: 40, height: 40)
                                            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        Text("Pay").font(.system(size: 18, weight: .medium)).foregroundStyle(Color(hex: 0x111114))
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0xB0B0B8))
                                    }
                                    .padding(.horizontal, 14).frame(height: 62)
                                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .filmPressed(press(row, t))
                                    .padding(.horizontal, 16).padding(.top, 16)
                                }
                                Spacer(minLength: 0)
                            }
                            // Trang các widget của Pay, trượt vào từ bên phải
                            if page > 0 {
                                ZStack(alignment: .top) {
                                    Color(hex: 0xF2F2F7)
                                    VStack(spacing: 0) {
                                        Capsule().fill(Color.black.opacity(0.2)).frame(width: 36, height: 5).padding(.top, 8)
                                        HStack {
                                            Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color(hex: 0x007AFF))
                                            Spacer()
                                            Image("logo-pay").resizable().scaledToFit().padding(4).frame(width: 28, height: 28)
                                                .background(.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                            Text("Pay").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(hex: 0x111114))
                                            Spacer()
                                            Color.clear.frame(width: 18, height: 18)
                                        }
                                        .padding(.horizontal, 20).padding(.top, 14)
                                        Text(pages[current].title).font(.system(size: 24, weight: .bold)).foregroundStyle(Color(hex: 0x111114))
                                            .padding(.top, 34)
                                        Text(pages[current].text).font(.system(size: 15)).foregroundStyle(Color(hex: 0x6B6B78))
                                            .multilineTextAlignment(.center).lineLimit(3).frame(height: 60, alignment: .top)
                                            .padding(.horizontal, 44).padding(.top, 8)
                                        // Dải widget: mỗi trang một widget, lướt ngang
                                        ZStack {
                                            ForEach(Array(pages.enumerated()), id: \.offset) { i, p in
                                                p.view.offset(x: ((CGFloat(i) - shown) * size.width).rounded())
                                            }
                                        }
                                        .frame(width: size.width, height: 200)
                                        .padding(.top, 26)
                                        HStack(spacing: 8) {
                                            ForEach(pages.indices, id: \.self) { i in
                                                Circle().fill(Color.black.opacity(i == current ? 0.75 : 0.2)).frame(width: 7, height: 7)
                                            }
                                        }
                                        .padding(.top, 22)
                                        Spacer(minLength: 0)
                                        Label(en ? "Add Widget" : "Thêm tiện ích", systemImage: "plus.circle.fill")
                                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                                            .frame(width: 320, height: 54)
                                            .background(Color(hex: 0x007AFF), in: Capsule())
                                            .filmPressed(press(plus, t))
                                            .padding(.bottom, 50)
                                    }
                                }
                                .offset(x: (size.width * (1 - page)).rounded())
                            }
                        }
                        .frame(width: size.width, height: size.height - top)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38, style: .continuous))
                        .offset(y: (top + (1 - sheet) * (size.height - top)).rounded())
                    }
                }
                .frame(width: size.width, height: size.height)
            })
        }
    }
}
#endif
