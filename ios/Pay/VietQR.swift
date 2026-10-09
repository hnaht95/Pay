import Foundation
import UIKit

/// Nội dung một mã VietQR (chuẩn EMVCo).
struct VietQR: Hashable {
    var raw: String
    var bin: String?
    var acct: String?
    var amount: Int?
    var name: String
    var purpose: String

    var bank: String { bin.map { BankData.names[$0] ?? L("Ngân hàng %@", $0) } ?? "" }
    var memoKey: String? { bin.flatMap { b in acct.map { "\(b):\($0)" } } }

    /// Đọc chuỗi kiểu ID(2) + độ dài(2) + giá trị
    private static func tlv(_ s: String) -> [String: String] {
        let ch = Array(s)
        var out: [String: String] = [:], i = 0
        while i + 4 <= ch.count {
            let id = String(ch[i..<i + 2])
            guard let len = Int(String(ch[i + 2..<i + 4])), i + 4 + len <= ch.count else { break }
            out[id] = String(ch[i + 4..<i + 4 + len])
            i += 4 + len
        }
        return out
    }

    static func parse(_ text: String) -> VietQR? {
        guard text.hasPrefix("000201") else { return nil }
        let top = tlv(text)
        var q = VietQR(raw: text, amount: top["54"].flatMap { Double($0) }.map { Int($0.rounded()) },
                       name: (top["59"] ?? "").trimmingCharacters(in: .whitespaces), purpose: "")
        for id in ["38", "26", "27", "28"] {
            guard let v = top[id] else { continue }
            let sub = tlv(v)
            if sub["00"] == "A000000727", let b = sub["01"] {
                let ben = tlv(b)
                q.bin = ben["00"]; q.acct = ben["01"]
            }
        }
        if let add = top["62"] { q.purpose = (tlv(add)["08"] ?? "").trimmingCharacters(in: .whitespaces) }
        return q
    }
}

struct BankApp: Identifiable, Hashable {
    let id: String
    let name: String
    let scheme: String
    let fill: Bool
}

enum BankLauncher {
    /// Trang quay về sau khi chuyển khoản (VietQR chỉ nhận https). Trang này mở lại app bằng sochipay://
    static let returnURL = "https://hnaht95.github.io/Pay/back.html"
    private static let iPhoneUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// Mở app ngân hàng. App có fill: lấy deeplink có chữ ký từ dl.vietqr.io rồi mở thẳng (ACB One điền sẵn người nhận + số tiền).
    @MainActor
    static func open(_ app: BankApp, qr: VietQR?, amount: Int?) async {
        if app.fill, let qr, let acct = qr.acct, let bin = qr.bin, let code = BankData.codes[bin] {
            var url = "https://dl.vietqr.io/pay?app=\(app.id)&ba=\(enc(acct))@\(code)"
            if let amount, amount > 0 { url += "&am=\(amount)" }
            if !qr.purpose.isEmpty { url += "&tn=\(enc(qr.purpose))" }
            if !qr.name.isEmpty { url += "&bn=\(enc(qr.name))" }
            url += "&url=\(enc(returnURL))"
            if let deep = await signedDeeplink(url), let u = URL(string: deep), await UIApplication.shared.open(u) { return }
            if let u = URL(string: url) { await UIApplication.shared.open(u) }   // dự phòng: để Safari xử lý
            return
        }
        if let u = URL(string: app.scheme), await UIApplication.shared.open(u) { return }
        if let u = URL(string: "https://dl.vietqr.io/pay?app=\(app.id)") { await UIApplication.shared.open(u) }   // chưa cài app -> App Store
    }

    /// Trang dl.vietqr.io chứa `const DEEPLINK = 'acbone://...'` — lấy ra để mở thẳng app, khỏi qua Safari.
    private static func signedDeeplink(_ url: String) async -> String? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u, timeoutInterval: 8)
        req.setValue(iPhoneUA, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req), let html = String(data: data, encoding: .utf8),
              let r = html.range(of: #"const DEEPLINK = '([^']+)'"#, options: .regularExpression) else { return nil }
        let line = html[r]
        guard let start = line.firstIndex(of: "'") else { return nil }
        let link = String(line[line.index(after: start)..<line.index(before: line.endIndex)])
        return link.contains("://") ? link : nil
    }

    private static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? s
    }
}
