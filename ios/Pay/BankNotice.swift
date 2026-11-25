import AppIntents
import Foundation

/// Đọc thông báo biến động số dư của app ngân hàng / ví (VCB, Techcombank, MB, ACB, VPBank NEO, MoMo…): số tiền giao dịch,
/// tiền ra hay vào, nội dung chuyển khoản. Không đọc được số tiền giao dịch hoặc là tin OTP / khuyến mãi thì trả nil
enum BankNotice {
    struct Txn: Equatable { let amount: Int; let income: Bool; let note: String }

    static func parse(_ raw: String) -> Txn? {
        let text = raw.replacingOccurrences(of: "\u{2212}", with: "-")
        let fold = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi"))
            .replacingOccurrences(of: "đ", with: "d")
        // Tin mã xác thực, khuyến mãi: không phải giao dịch
        if fold.range(of: #"\botp\b|ma xac thuc|ma xac nhan"#, options: .regularExpression) != nil { return nil }

        // 1. Số tiền có dấu + / - đứng riêng (không dính chữ số trước, như ngày "18-11-2026"): "PS: -50,000 VND", "+1.000.000đ"
        let signed = #"(?<![\w.,])([+-])\s?(\d{1,3}(?:[.,]\d{3})+|\d{4,})(?:[.,]\d{1,2})?(?!\d)"#
        for m in matches(signed, in: text) where !afterBalance(m.range, in: fold) {
            guard let v = Int(m.groups[1].filter(\.isNumber)), v > 0 else { continue }
            let income = m.groups[0] == "+"
            return Txn(amount: v, income: income, note: note(text, fold, income: income))
        }
        // 2. Không có dấu: chữ cho biết hướng ("giảm", "thanh toán" / "tăng", "nhận") và số tiền đầu tiên không phải số dư
        let out = #"giam|bi tru|da tru|thanh toan|chi tieu|chuyen tien thanh cong|chuyen di|ghi no|debit|paid|payment"#
        let inn = #"tang|duoc cong|cong tien|cong vao|nhan|duoc chuyen|chuyen den|ghi co|credit|received"#
        let money = #"(?<![\w.,])(\d{1,3}(?:[.,]\d{3})+|\d{4,})(?:[.,]\d{1,2})?\s?(?:vnd|d\b|dong)"#
        guard let m = matches(money, in: fold).first(where: { !afterBalance($0.range, in: fold) }),
              let v = Int(m.groups[0].filter(\.isNumber)), v > 0 else { return nil }
        // Chữ chỉ hướng gần số tiền nhất (đứng trước nó) quyết định
        let head = String(fold[..<m.range.lowerBound])
        let lastOut = lastMatch(out, in: head), lastIn = lastMatch(inn, in: head)
        guard lastOut != nil || lastIn != nil else { return nil }
        let income = (lastIn ?? -1) > (lastOut ?? -1)
        return Txn(amount: v, income: income, note: note(text, fold, income: income))
    }

    /// Nội dung giao dịch: phần sau "ND:", "Nội dung:", "Description:", "GD:" (đến hết dòng / dấu "|"); ví điện tử không có
    /// nhãn thì "cho X" / "từ X" (X viết hoa); không có cả hai thì đoạn chữ cuối cùng không có số (VPBank NEO để nội dung trơn
    /// sau số dư). Bỏ mã tham chiếu đầu nội dung kiểu "MBVCB.1234567.", dấu cách thừa, rồi bỏ phần chữ mặc định của lệnh chuyển
    static func note(_ text: String, _ fold: String, income: Bool) -> String {
        var start: Int?
        // Bản bỏ dấu dài bằng văn bản gốc tính theo ký tự (bỏ dấu, đ → d không đổi số ký tự)
        // "GD:" có app dùng cho nội dung (ACB), có app dùng cho số tiền (MB "GD: -35,000VND"): xét sau cùng, bỏ khi theo sau là số
        if let r = fold.range(of: #"\b(?:nd|noi dung(?: gd| giao dich)?|description|desc|content)\s*:"#, options: .regularExpression)
            ?? fold.range(of: #"\bgd\s*:(?!\s*[+-]?\s*\d)"#, options: .regularExpression) {
            start = fold.distance(from: fold.startIndex, to: r.upperBound)
        } else if let r = text.range(of: #"\b(?:cho|tới|đến|từ)\s+(?=[\p{Lu}0-9])"#, options: .regularExpression) {
            start = text.distance(from: text.startIndex, to: r.upperBound)
        }
        var s: String
        if let start, start <= text.count {
            s = String(text[text.index(text.startIndex, offsetBy: start)...])
            if let cut = s.firstIndex(where: { "|\n".contains($0) }) { s = String(s[..<cut]) }
        } else {
            // Không nhãn: đoạn cuối (tách theo dòng, "|", ";", ". ") có chữ, không có số, không phải chữ mẫu của ngân hàng
            let parts = text.components(separatedBy: CharacterSet(charactersIn: "|\n;"))
                .flatMap { $0.components(separatedBy: ". ") }
            s = parts.last(where: { p in
                let f = strip(p)
                return p.contains(where: \.isLetter) && !p.contains(where: \.isNumber)
                    && f.range(of: #"so du|tai khoan|bien dong|giao dich|thong bao|\btk\b|\bvnd\b"#, options: .regularExpression) == nil
            }) ?? ""
        }
        if let r = s.range(of: #"^\s*[A-Z]{2,}[.\-]?\d{4,}[.\-]\d+[.\-]?"#, options: .regularExpression) { s.removeSubrange(r) }
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,;:-"))
        return String(plain(s, income: income).prefix(80))
    }

    /// Bỏ chữ mặc định ngân hàng điền khi chuyển khoản: "NGUYEN VAN THANH chuyen tien an sang" → "an sang". Tên viết hoa đứng
    /// trước "chuyen tien" / "chuyen khoan" / "CK" là người gửi: khoản chi thì đó là chính mình nên bỏ, khoản thu thì giữ tên người
    /// gửi ("NGUYEN VAN A chuyen tien" → "NGUYEN VAN A"). Tên viết hoa không kèm chữ chuyển tiền (cửa hàng "HIGHLANDS COFFEE") giữ
    static func plain(_ s: String, income: Bool) -> String {
        let boiler = #"(?i:chuyen tien|chuyen khoan|chuyển tiền|chuyển khoản|ck|ct|tra tien|trả tiền)\b"#
        var out = s
        // Tên viết hoa (phân biệt hoa thường, chữ cái lẻ "B" cũng tính) ngay trước chữ chuyển tiền
        if let r = out.range(of: #"^((?:[A-Z]+\s+){2,6}?)"# + boiler, options: .regularExpression),
           let name = out.range(of: #"^(?:[A-Z]+\s+){2,6}?(?="# + boiler + ")", options: .regularExpression) {
            let who = out[name].trimmingCharacters(in: .whitespaces)
            out = String(out[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " .,;:-"))
            if income { out = out.isEmpty ? who : who + " · " + out }
        } else if let r = out.range(of: "^" + boiler, options: .regularExpression) {
            out = String(out[r.upperBound...])
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:-"))
    }

    /// Số đứng ngay sau "Số dư:" / "SD:" / "Số dư khả dụng" (chỉ cách bởi dấu hai chấm, khoảng trắng, "VND"): là số dư, không
    /// phải tiền giao dịch
    private static func afterBalance(_ r: Range<String.Index>, in fold: String) -> Bool {
        let lo = fold.index(r.lowerBound, offsetBy: -min(30, fold.distance(from: fold.startIndex, to: r.lowerBound)))
        return fold[lo..<r.lowerBound].range(of: #"(?:so du(?: kha dung| cuoi(?: ky)?| tk)?|\bsd|balance|available)\s*[:=]?\s*(?:la\s*)?(?:vnd\s*)?$"#,
                                             options: .regularExpression) != nil
    }

    private static func lastMatch(_ p: String, in s: String) -> Int? {
        matches(#"\b(?:"# + p + #")\b"#, in: s).last.map { s.distance(from: s.startIndex, to: $0.range.lowerBound) }
    }

    private struct Hit { let range: Range<String.Index>; let groups: [String] }
    private static func matches(_ p: String, in s: String) -> [Hit] {
        guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
            guard let r = Range(m.range, in: s) else { return nil }
            let g = (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: s).map { String(s[$0]) } ?? "" }
            return Hit(range: r, groups: g)
        }
    }
}

/// Tự ghi từ thông báo ngân hàng: trong app Phím tắt > Tự động hoá > Thông báo, chọn các app ngân hàng / ví, thêm tác vụ
/// "Ghi từ thông báo ngân hàng" của Payso và gán Thông báo vào ô Nội dung. Mỗi thông báo biến động số dư là một khoản chi / thu.
/// Cùng giao dịch đã tự ghi (từ thông báo khác hoặc từ giao dịch thẻ trong Ví) trong 3 phút thì không ghi lại
struct BankNoticeIntent: AppIntent {
    static let title: LocalizedStringResource = "Ghi từ thông báo ngân hàng"
    static let description = IntentDescription("Đọc thông báo biến động số dư của app ngân hàng hoặc ví và ghi khoản chi / thu. Dùng trong Tự động hoá > Thông báo: gán Thông báo vào ô Nội dung.")
    static let openAppWhenRun = false

    @Parameter(title: "Nội dung")
    var text: String

    static let idPrefix = "bank-"

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard UserDefaults.standard.bool(forKey: "proActive") else {
            return .result(dialog: IntentDialog(stringLiteral: L("Tự ghi từ thông báo ngân hàng cần Payso Pro. Mở Payso để nâng cấp.")))
        }
        guard let t = BankNotice.parse(text) else {
            return .result(dialog: IntentDialog(stringLiteral: L("Không phải thông báo giao dịch, không ghi.")))
        }
        let store = Store.shared
        let now = Date().timeIntervalSince1970 * 1000
        let auto = [Self.idPrefix, CardPaymentIntent.idPrefix]
        if store.all.contains(where: { e in auto.contains(where: { e.id.hasPrefix($0) }) && e.a == t.amount
            && e.isIncome == t.income && abs(now - e.t) < CardPaymentIntent.dupWindow }) {
            return .result(dialog: IntentDialog(stringLiteral: L("Đã ghi %@ rồi, không ghi lại.", fmt(t.amount))))
        }
        // Ghi chú không đoán được thì dò từ khoá trên cả thông báo ("an sang" lọt ở chỗ ngân hàng không gắn nhãn)
        var cat = t.income ? store.guessIncome(t.note) : store.guessCategory(t.note)
        if !t.income, cat == "khac" { cat = Category.guess(text) }
        let note = t.note.isEmpty ? (t.income ? L("Được chuyển") : L("Chuyển khoản")) : t.note
        store.add(amount: t.amount, note: note, cat: cat, toast: false, idPrefix: Self.idPrefix)
        return .result(dialog: IntentDialog(stringLiteral: t.income ? L("Đã ghi khoản thu %@.", fmt(t.amount)) : L("Đã ghi %@ %@.", fmt(t.amount), note)))
    }
}
