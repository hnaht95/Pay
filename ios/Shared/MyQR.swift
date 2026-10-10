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
    var payload: String? {
        guard ready else { return nil }
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

/// Mã QR: mặc định đen trên nền trắng; trong widget thì không nền, tô một màu theo nền widget
struct MyQRCode: View {
    let qr: MyQR
    /// Có màu: mã không nền, các ô tô bằng màu này (đặt thẳng lên nền của widget). nil: mã đen trên nền trắng
    var ink: Color? = nil

    var body: some View {
        if let ink, let img = qr.image(clear: true) {
            Image(decorative: img, scale: 1).renderingMode(.template).interpolation(.none).resizable().scaledToFit()
                .foregroundStyle(ink)
                .accessibilityLabel(L("Mã QR nhận tiền"))
        } else if let img = qr.image {
            Image(decorative: img, scale: 1).interpolation(.none).resizable().scaledToFit()
                .accessibilityLabel(L("Mã QR nhận tiền"))
        }
    }
}
