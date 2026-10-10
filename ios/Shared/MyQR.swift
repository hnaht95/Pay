import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Mã QR nhận tiền của chính người dùng (VietQR tĩnh, không kèm số tiền): đặt trong Cài đặt, widget "Mã QR nhận tiền" hiện ra
/// để người khác quét chuyển khoản. Lưu trong App Group vì widget chạy riêng, không đọc được dữ liệu của app.
struct MyQR: Equatable {
    var bin = ""        // mã ngân hàng (BIN) theo NAPAS
    var bank = ""       // tên ngân hàng để hiện (widget không có bảng tên ngân hàng)
    var acct = ""       // số tài khoản
    var name = ""       // tên chủ tài khoản, chỉ để hiện

    var ready: Bool { !bin.isEmpty && !acct.isEmpty }

    private static let store = UserDefaults(suiteName: Summary.group) ?? .standard

    static func load() -> MyQR {
        MyQR(bin: store.string(forKey: "myqr.bin") ?? "", bank: store.string(forKey: "myqr.bank") ?? "",
             acct: store.string(forKey: "myqr.acct") ?? "", name: store.string(forKey: "myqr.name") ?? "")
    }

    func save() {
        Self.store.set(bin, forKey: "myqr.bin"); Self.store.set(bank, forKey: "myqr.bank")
        Self.store.set(acct, forKey: "myqr.acct"); Self.store.set(name, forKey: "myqr.name")
    }

    /// Chuỗi VietQR (chuẩn EMVCo của NAPAS): chuyển nhanh tới tài khoản, người quét tự nhập số tiền
    /// Phim giới thiệu: mã hiện ra mang nội dung này thay cho tài khoản thật (một mã vô hại, quét ra trang của Pay)
    static var filmPayload: String?

    var payload: String? {
        guard ready else { return nil }
        if let demo = Self.filmPayload { return demo }
        func f(_ id: String, _ v: String) -> String { id + String(format: "%02d", v.count) + v }
        let account = f("00", "A000000727") + f("01", f("00", bin) + f("01", acct)) + f("02", "QRIBFTTA")
        let body = f("00", "01") + f("01", "11") + f("38", account) + f("53", "704") + f("58", "VN") + "6304"
        return body + String(format: "%04X", Self.crc16(body))
    }

    /// CRC-16/CCITT-FALSE (đa thức 0x1021, khởi đầu 0xFFFF), như chuẩn EMVCo yêu cầu
    static func crc16(_ s: String) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for b in s.utf8 {
            crc ^= UInt16(b) << 8
            for _ in 0..<8 { crc = crc & 0x8000 != 0 ? (crc << 1) ^ 0x1021 : crc << 1 }
        }
        return crc
    }

    /// Ảnh mã QR, mỗi ô một điểm ảnh (vẽ phóng to không làm mịn để ô vuông sắc nét)
    var image: CGImage? { image(clear: false) }

    /// clear = true: chỉ có các ô của mã, phần còn lại trong suốt (để tô mã bằng một màu, đặt thẳng lên nền có sẵn)
    func image(clear: Bool) -> CGImage? {
        guard let payload else { return nil }
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(payload.utf8)
        f.correctionLevel = "M"
        guard var out = f.outputImage else { return nil }
        if clear {
            let c = CIFilter.falseColor()
            c.inputImage = out
            c.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)   // ô đen của mã
            c.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)   // nền trắng -> trong suốt
            guard let t = c.outputImage else { return nil }
            out = t
        }
        return CIContext().createCGImage(out, from: out.extent)
    }
}

extension MyQR {
    /// Các ô của mã QR (true = ô tối), đã bỏ lề trắng quanh mã; hàng đầu là hàng trên cùng
    var modules: [[Bool]]? {
        guard let img = image else { return nil }
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 255, count: w * h)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let dark = (0..<h).map { y in (0..<w).map { x in px[y * w + x] < 128 } }
        let ys = dark.indices.filter { dark[$0].contains(true) }
        let xs = (0..<w).filter { x in dark.contains { $0[x] } }
        guard let y0 = ys.first, let y1 = ys.last, let x0 = xs.first, let x1 = xs.last else { return nil }
        return (y0...y1).map { y in Array(dark[y][x0...x1]) }
    }
}

/// Mã QR vẽ bằng hình (ô vuông, góc vuông) thay cho ảnh: phóng to bao nhiêu cũng nét. Dùng cho phim giới thiệu.
struct MyQRSquares: Shape {
    let m: [[Bool]]
    func path(in r: CGRect) -> Path {
        let n = m.count, u = min(r.width, r.height) / CGFloat(max(n, 1))
        let ox = r.midX - u * CGFloat(n) / 2, oy = r.midY - u * CGFloat(n) / 2
        var p = Path()
        for y in 0..<n {
            var x = 0
            while x < m[y].count {   // gộp các ô tối liền nhau trên một hàng thành một hình chữ nhật
                guard m[y][x] else { x += 1; continue }
                var e = x
                while e + 1 < m[y].count, m[y][e + 1] { e += 1 }
                p.addRect(CGRect(x: ox + CGFloat(x) * u, y: oy + CGFloat(y) * u, width: CGFloat(e - x + 1) * u + 0.3, height: u + 0.3))
                x = e + 1
            }
        }
        return p
    }
}

/// Mã QR: mặc định đen trên nền trắng; trong widget thì không nền, tô một màu theo nền widget
struct MyQRCode: View {
    let qr: MyQR
    /// Có màu: mã không nền, các ô tô bằng màu này (đặt thẳng lên nền của widget). nil: mã đen trên nền trắng
    var ink: Color? = nil

    /// Vẽ bằng hình thay cho ảnh (phim giới thiệu: nét ở mọi cỡ)
    static var vector = false

    var body: some View {
        if Self.vector, let m = qr.modules {
            MyQRSquares(m: m).fill(ink ?? .black).aspectRatio(1, contentMode: .fit)
        } else if let ink, let img = qr.image(clear: true) {
            Image(decorative: img, scale: 1).renderingMode(.template).interpolation(.none).resizable().scaledToFit()
                .foregroundStyle(ink)
                .accessibilityLabel(L("Mã QR nhận tiền"))
        } else if let img = qr.image {
            Image(decorative: img, scale: 1).interpolation(.none).resizable().scaledToFit()
                .accessibilityLabel(L("Mã QR nhận tiền"))
        }
    }
}
