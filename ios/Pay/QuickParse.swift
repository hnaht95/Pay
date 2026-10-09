import Foundation

/// Đọc câu nhập nhanh kiểu bản web: "35k cafe" -> 35000 + "cafe".
enum QuickParse {
    /// "35k" -> 35000, "1tr2" -> 1200000, "1.5tr" -> 1500000, "35.000" -> 35000, "35000" -> 35000
    static func amount(_ raw: String) -> Int? {
        let s = strip(raw).replacingOccurrences(of: " ", with: "")
        if let m = s.wholeMatch(of: #/(\d+(?:[.,]\d+)?)(tr|trieu|m|cu)(\d+)?/#) {
            var v = Double(m.1.replacingOccurrences(of: ",", with: "."))!
            if let extra = m.3 { v += Double("0." + extra)! }
            return Int((v * 1e6).rounded())
        }
        if let m = s.wholeMatch(of: #/(\d+(?:[.,]\d+)?)(k|nghin|ngan|ng|n)/#) {
            return Int((Double(m.1.replacingOccurrences(of: ",", with: "."))! * 1e3).rounded())
        }
        if s.wholeMatch(of: #/\d{1,3}(?:[.,]\d{3})+/#) != nil {
            return Int(s.filter(\.isNumber))
        }
        if s.wholeMatch(of: #/\d+/#) != nil { return Int(s) }
        return nil
    }

    /// "35k cafe sáng" -> (35000, "cafe sáng"); bỏ chữ "đồng" Siri hay thêm vào. Không thấy số tiền thì nil.
    static func expense(_ text: String) -> (amount: Int, note: String)? {
        let re = #/(?i)(^|\s)(\d+(?:[.,]\d+)*)\s*(k|tr|triệu|trieu|củ|cu|m|nghìn|ngàn|nghin|ngan)?(\d+)?(?:\s*(?:đồng|dong|vnđ|vnd|đ))?(?![\p{L}\d])/#
        guard let m = text.firstMatch(of: re),
              let a = amount(String(m.2) + String(m.3 ?? "") + String(m.4 ?? "")), a > 0 else { return nil }
        let note = (text[..<m.range.lowerBound] + " " + text[m.range.upperBound...])
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (a, note)
    }

    // MARK: Giọng nói

    /// Câu nói (Siri / nhận dạng giọng nói) -> số tiền + ghi chú. Hiểu cả số bằng chữ và kiểu nói tắt:
    /// "ba mươi lăm nghìn cà phê", "ba lăm cafe", "hai trăm rưỡi", "một triệu hai", "nửa triệu", "3 củ".
    /// Không có đơn vị và số dưới 1.000 thì hiểu là nghìn ("35 cafe" = 35.000đ).
    static func spoken(_ text: String) -> (amount: Int, note: String)? {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        // Siri luôn viết có dấu, nên so khớp theo chữ có dấu để chữ thường không bị hiểu là số:
        // "tháng sau" ≠ sáu, "máy bay" ≠ bảy, "tôi/tối" ≠ tỷ, "làm" ≠ lăm. Câu gõ không dấu mới so theo chữ không dấu.
        let accented = text.lowercased() != strip(text)
        let toks = words.map { w in
            tok(w.lowercased().precomposedStringWithCanonicalMapping.trimmingCharacters(in: .punctuationCharacters), accented: accented)
        }

        // Tìm các cụm số liền nhau; chọn cụm "chắc chắn" nhất (có đơn vị / hàng chục trăm / số ≥ 10), rồi lớn nhất
        var best: (range: Range<Int>, value: Double, strong: Bool)?
        var i = 0
        while i < toks.count {
            guard let t = toks[i], t.canStart else { i += 1; continue }
            var j = i + 1
            while j < toks.count, let u = toks[j], !breaks(toks[j - 1]!, u) {
                j += 1
                if case .end = u { break }
            }
            let run = toks[i..<j].compactMap { $0 }
            let v = isLoneWord(run) ? 0 : value(run)
            let strong = run.contains { $0.isStrong }
            if v > 0, best == nil || (strong && !best!.strong) || (strong == best!.strong && v > best!.value) {
                best = (i..<j, v, strong)
            }
            i = j
        }
        guard let b = best else { return nil }
        var amount = Int(b.value.rounded())
        if amount < 1000 { amount *= 1000 }
        let note = words.enumerated().filter { !b.range.contains($0.offset) }.map(\.element).joined(separator: " ")
        return (amount, note)
    }

    private enum Tok {
        /// word: chữ số viết bằng chữ ("ba"); tail: lăm/nhăm/mốt/tư — chỉ đứng sau hàng chục ("ba lăm", "hai mốt")
        case num(Double, word: Bool, tail: Bool)
        /// lead: được đứng đầu cụm ("triệu hai"); tiếng lóng / viết tắt ("củ", "k") phải có số đứng trước
        case scale(Double, lead: Bool)
        case tens, hundreds, linh, half, halfPrefix, end, full(Double)

        var canStart: Bool {
            switch self {
            case .num, .full, .halfPrefix, .tens, .hundreds: true
            case .scale(_, let lead): lead
            default: false
            }
        }
        var isStrong: Bool {
            switch self {
            case .scale, .full, .hundreds, .tens: true
            case .num(let v, _, _): v >= 10
            default: false
            }
        }
    }

    /// Chữ số viết bằng chữ (có dấu) -> (giá trị, là dạng chỉ đứng sau hàng chục).
    private static let digitWords: [String: (Double, Bool)] = [
        "không": (0, false), "một": (1, false), "mốt": (1, true), "hai": (2, false), "ba": (3, false),
        "bốn": (4, false), "tư": (4, true), "năm": (5, false), "lăm": (5, true), "nhăm": (5, true),
        "sáu": (6, false), "bảy": (7, false), "bẩy": (7, false), "tám": (8, false), "chín": (9, false),
    ]
    private static let numberWords: [String: Tok] = [
        "mười": .tens, "mươi": .tens, "chục": .tens, "trăm": .hundreds, "linh": .linh, "lẻ": .linh,
        "nghìn": .scale(1e3, lead: true), "ngàn": .scale(1e3, lead: true), "k": .scale(1e3, lead: false),
        "triệu": .scale(1e6, lead: true), "tr": .scale(1e6, lead: false), "củ": .scale(1e6, lead: false),
        "tỷ": .scale(1e9, lead: true), "tỉ": .scale(1e9, lead: true),
        "rưỡi": .half, "nửa": .halfPrefix, "đồng": .end, "đ": .end, "₫": .end, "vnđ": .end, "vnd": .end,
    ]
    /// Câu gõ không dấu.
    private static let plainDigitWords: [String: (Double, Bool)] = [
        "khong": (0, false), "mot": (1, false), "hai": (2, false), "ba": (3, false), "bon": (4, false), "tu": (4, true),
        "nam": (5, false), "lam": (5, true), "sau": (6, false), "bay": (7, false), "tam": (8, false), "chin": (9, false),
    ]
    private static let plainNumberWords: [String: Tok] = [
        "muoi": .tens, "chuc": .tens, "tram": .hundreds, "linh": .linh, "le": .linh,
        "nghin": .scale(1e3, lead: true), "ngan": .scale(1e3, lead: true), "k": .scale(1e3, lead: false),
        "trieu": .scale(1e6, lead: true), "tr": .scale(1e6, lead: false), "cu": .scale(1e6, lead: false),
        "ty": .scale(1e9, lead: true), "ruoi": .half, "nua": .halfPrefix, "dong": .end, "d": .end, "vnd": .end,
    ]

    private static func tok(_ w: String, accented: Bool) -> Tok? {
        if let (v, tail) = (accented ? digitWords : plainDigitWords)[w] { return .num(v, word: true, tail: tail) }
        if let t = (accented ? numberWords : plainNumberWords)[w] { return t }
        // Số viết bằng chữ số, có thể dính ký hiệu tiền: "35.000", "35.000đ", "35.000₫", "1,5"
        let n = w.replacing(#/(đ|₫|vnđ|vnd)$/#, with: "")
        if n.wholeMatch(of: #/[0-9]{1,3}(?:[.,][0-9]{3})+/#) != nil {
            return .num(siriShorthand(Double(n.filter { $0.isASCII && $0.isNumber })!), word: false, tail: false)
        }
        if let m = n.wholeMatch(of: #/([0-9]+)(?:[.,]([0-9]+))?/#) {
            let v = Double(String(m.1) + (m.2.map { "." + $0 } ?? ""))!
            return .num(m.2 == nil ? siriShorthand(v) : v, word: false, tail: false)
        }
        if w.contains(where: \.isLetter), let a = amount(w) { return .full(Double(a)) }   // "35k", "1tr2"
        return nil
    }

    /// Hai từ liền nhau không thuộc cùng một số thì cụm số dừng trước từ sau:
    /// "tháng tư 500", "máy bay 2", "năm 2 triệu", "cho ba 200" là chữ thường đứng cạnh số tiền.
    private static func breaks(_ a: Tok, _ b: Tok) -> Bool {
        switch (a, b) {
        case let (.num(x, aWord, _), .num(y, _, bTail)):
            if aWord && x < 10 && bTail { return false }        // "ba lăm" = 35, "hai mốt" = 21, "bốn tư" = 44
            if !aWord && x >= 1000 && y < 10 && x.truncatingRemainder(dividingBy: impliedScale(x)) == 0 { return false }   // Siri: "1.000.000 2"
            return true
        case (.num, .full): return true                        // "ba 35k"
        default: return false
        }
    }

    /// Một chữ số đứng một mình ("ba", "năm", "tư", "nửa") gần như luôn là chữ thường, không phải số tiền.
    private static func isLoneWord(_ run: [Tok]) -> Bool {
        guard run.count == 1 else { return false }
        switch run[0] {
        case .num(_, true, _), .halfPrefix: return true
        default: return false
        }
    }

    /// Siri hiểu "mười triệu hai" theo nghĩa đen và viết "10.000.002". Số tròn triệu/nghìn cộng 1–9 đồng
    /// thì không ai nói thật, nên hiểu là nói tắt: 10.000.002 -> 10.200.000, 1.002 -> 1.200.
    private static func siriShorthand(_ x: Double) -> Double {
        for scale in [1e9, 1e6, 1e3] where x >= scale {
            let d = x.truncatingRemainder(dividingBy: scale)
            if d >= 1 && d <= 9 { return x - d + d * scale / 10 }
            return x
        }
        return x
    }

    /// Đơn vị khi đọc thành lời: từ 1 triệu trở lên là "triệu", còn lại là "nghìn".
    private static func impliedScale(_ x: Double) -> Double { x >= 1e6 ? 1e6 : 1e3 }

    /// Đọc một cụm số tiếng Việt thành giá trị.
    private static func value(_ toks: [Tok]) -> Double {
        enum Last { case none, num, tens, hundreds, linh, scale }
        var total = 0.0, group = 0.0, lastScale = 0.0
        var pending: Double?
        var pendingAfter = Last.none, last = Last.none

        // "hai trăm năm" = 250 (nói tắt), "hai trăm linh năm" = 205
        func flush() -> Double {
            guard let p = pending else { return group }
            return group + (pendingAfter == .hundreds && p < 10 ? p * 10 : p)
        }

        loop: for t in toks {
            switch t {
            case .num(let v, _, _):
                if let p = pending, last == .num, p < 10, v < 10, pendingAfter != .hundreds, pendingAfter != .linh {
                    group += p * 10 + v          // "ba lăm" = 35
                    pending = nil; last = .tens
                } else if let p = pending, last == .num, p >= 1000, v < 10, p.truncatingRemainder(dividingBy: impliedScale(p)) == 0 {
                    // Siri hay viết "1 triệu 2" thành "1.000.000 2": số tròn nghìn/triệu + một chữ số = nói tắt
                    // -> 1.200.000; "10.000 5" (mười nghìn năm) -> 10.500
                    total += group + p; group = 0
                    lastScale = impliedScale(p)
                    pending = v; pendingAfter = .scale; last = .num
                } else {
                    if pending != nil { group = flush() }
                    pending = v; pendingAfter = last; last = .num
                }
            case .tens:
                if let p = pending { group += p * 10; pending = nil } else { group += 10 }
                last = .tens
            case .hundreds:
                group += (pending ?? 1) * 100; pending = nil; last = .hundreds
            case .linh:
                last = .linh
            case .scale(let s, _):
                let g = flush()
                total += (g == 0 ? 1 : g) * s
                group = 0; pending = nil; last = .scale; lastScale = s
            case .half:
                // rưỡi = nửa đơn vị đứng ngay trước: triệu rưỡi, trăm rưỡi, chục rưỡi
                if last == .scale { total += lastScale / 2 }
                else if last == .hundreds { group += 50 }
                else if last == .tens { group += 5 }
                else if let p = pending { pending = p + 0.5 }
                last = .none
            case .halfPrefix:
                if pending != nil { group = flush() }
                pending = 0.5; pendingAfter = last; last = .num
            case .full(let v):
                total += v; group = 0; pending = nil; last = .scale; lastScale = v >= 1e6 ? 1e6 : 1e3
            case .end:
                break loop
            }
        }

        // Phần đuôi sau đơn vị, nói tắt: "một triệu hai" = 1,2 triệu, "một triệu hai trăm" = 1,2 triệu, "ba nghìn hai" = 3.200
        if lastScale > 0 {
            if let p = pending, pendingAfter == .scale, group == 0, p < 10 { return total + p * lastScale / 10 }
            let rem = flush()
            if rem > 0 && rem < 1000 { return total + rem * max(lastScale / 1000, 1) }
            return total + rem
        }
        return total + flush()
    }
}

