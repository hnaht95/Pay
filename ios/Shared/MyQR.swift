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
    var image: CGImage? {
        guard let payload else { return nil }
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(payload.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        return CIContext().createCGImage(out, from: out.extent)
    }
}

/// Mã QR đen trên nền trắng, có lề trắng quanh mã để máy quét đọc được
struct MyQRCode: View {
    let qr: MyQR
    var body: some View {
        if let img = qr.image {
            Image(decorative: img, scale: 1).interpolation(.none).resizable().scaledToFit()
                .accessibilityLabel(L("Mã QR nhận tiền"))
        }
    }
}
