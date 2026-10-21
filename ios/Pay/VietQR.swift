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
            // Mã QR là dữ liệu từ ngoài: độ dài "-1" vẫn qua được Int() và phép so ở sau, rồi làm khoảng cắt bị ngược (dừng app)
            guard let len = Int(String(ch[i + 2..<i + 4])), len >= 0, i + 4 + len <= ch.count else { break }
            out[id] = String(ch[i + 4..<i + 4 + len])
            i += 4 + len
        }
        return out
    }

    static func parse(_ text: String) -> VietQR? {
        guard text.hasPrefix("000201") else { return nil }
        let top = tlv(text)
        // Số tiền: "nan", "inf", "1e30" hay 20 chữ số đều qua được Double() rồi làm Int() dừng app,
        // nên chỉ nhận số dương không quá 12 chữ số (bằng giới hạn của bàn phím số), còn lại coi như mã không ghi số tiền
        let amount = top["54"].flatMap { Double($0) }.map { $0.rounded() }.flatMap { $0 >= 1 && $0 < 1e12 ? Int($0) : nil }
        var q = VietQR(raw: text, amount: amount,
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
    /// Tên / tên viết tắt ngân hàng hay gặp trong tin nhắn ("MB 0123456789 200k") -> mã BIN. Ghép từ tên ngắn và mã của
    /// BankData, thêm vài cách gọi quen
    private static let bankWords: [String: String] = {
        var out: [String: String] = [:]
        for (bin, name) in BankData.names { out[fold(name)] = bin }
        for (bin, code) in BankData.codes { out[fold(code)] = bin }
        let extra: [String: String] = [
            "mb": "970422", "mbbank": "970422", "quandoi": "970422",
            "vcb": "970436", "vietcom": "970436", "ngoaithuong": "970436",
            "ctg": "970415", "vietin": "970415", "viettin": "970415", "congthuong": "970415",
            "tcb": "970407", "techcom": "970407", "agri": "970405", "agribank": "970405",
            "vpb": "970432", "tpb": "970423", "stb": "970403", "sacom": "970403", "hdb": "970437",
            "momo": "971025", "timo": "963388", "cake": "546034", "msb": "970426", "shb": "970443",
            "eximbank": "970431", "eib": "970431", "seabank": "970440", "lpbank": "970449", "lienviet": "970449",
        ]
        for (k, v) in extra where BankData.names[v] != nil { out[k] = v }
        return out
    }()

    /// Chữ thường, bỏ dấu, chỉ giữ chữ và số: "MB Bank" -> "mbbank", "Vietin" -> "vietin"
    private static func fold(_ s: String) -> String {
        s.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi"))
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Dòng bạn bè nhắn để chuyển tiền (dán ở màn quét): "MB 0123456789 200k", "STK 1903 4567 8901 Techcombank NGUYEN VAN A".
    /// Cần một số tài khoản (6–19 chữ số liền, cho phép cách nhau bởi dấu cách / chấm / gạch). Ngân hàng nhận theo tên hoặc tên
    /// viết tắt; không rõ thì bin = nil (màn hình hỏi chọn ngân hàng). Số tiền đọc như ô nhập nhanh, nếu có
    static func fromText(_ text: String) -> VietQR? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 300, !t.hasPrefix("000201") else { return nil }
        // Số tài khoản: một nhóm 6–19 chữ số ("0123456789", "107-8765-4321"), hoặc vài nhóm ngắn (≤ 5 chữ số) liền nhau cách bởi
        // dấu cách ("1903 4567 8901"). Không gộp số dài với số đứng sau: "0123456789 200k", "0987654321 1tr2" là STK + số tiền
        let tokens = t.split(whereSeparator: \.isWhitespace).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",:;()")) }
        func digitsOnly(_ w: String) -> String? {
            guard let f = w.first, f.isNumber, w.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "." }) else { return nil }
            // Kiểu tiền "1.500.000" không phải số tài khoản
            if w.wholeMatch(of: #/[0-9]{1,3}(?:\.[0-9]{3})+/#) != nil { return nil }
            return w.filter(\.isNumber)
        }
        var cands: [(acct: String, from: Int, to: Int)] = [], run = "", runStart = 0
        for (i, w) in tokens.enumerated() {
            let d = digitsOnly(w)
            if let d, d.count <= 5 {
                if run.isEmpty { runStart = i }
                run += d
                continue
            }
            if (6...19).contains(run.count) { cands.append((run, runStart, i - 1)) }
            run = ""
            if let d, (6...19).contains(d.count) { cands.append((d, i, i)) }
        }
        if (6...19).contains(run.count) { cands.append((run, runStart, tokens.count - 1)) }
        guard let pick = cands.max(by: { $0.acct.count < $1.acct.count }) else { return nil }
        let acct = pick.acct
        let rest = (tokens[..<pick.from] + tokens[(pick.to + 1)...]).joined(separator: " ")
        // Ngân hàng: từng chữ, rồi từng cặp chữ liền nhau ("MB Bank", "Viet in")
        let words = rest.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        var bin: String?
        for (i, w) in words.enumerated() {
            if let b = bankWords[fold(w)] { bin = b; break }
            if i + 1 < words.count, let b = bankWords[fold(w + words[i + 1])] { bin = b; break }
        }
        // Số tiền: bỏ tên ngân hàng và các chữ STK / số tài khoản rồi đọc như ô nhập nhanh
        let amount = QuickParse.expense(rest)?.amount
        let raw = "paste:\(bin ?? "?"):\(acct):\(amount ?? 0)"
        return VietQR(raw: raw, bin: bin, acct: acct, amount: amount, name: "", purpose: "")
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
            // dl.vietqr.io chỉ nhận tên người nhận gồm chữ không dấu, số và dấu cách: có dấu hay ký tự như - . & là báo
            // "invalid accountName" (đã thử 10/2026), cả lần chuyển hỏng. Bỏ dấu, bỏ ký tự lạ; không còn gì thì không gửi tên
            let bn = Self.plainName(qr.name)
            if !bn.isEmpty { url += "&bn=\(enc(bn))" }
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

    /// "Nguyễn Văn Á - CN.1" → "NGUYEN VAN A CN 1"
    static func plainName(_ s: String) -> String {
        let folded = s.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi")).uppercased()
        let kept = String(folded.unicodeScalars.map { CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").contains($0) ? Character($0) : " " })
        return kept.split(separator: " ").joined(separator: " ")
    }

    private static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? s
    }
}
