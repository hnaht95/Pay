import Foundation

/// Đọc câu nhập nhanh kiểu bản web: "35k cafe" -> 35000 + "cafe".
enum QuickParse {
    /// "35k" -> 35000, "1tr2" -> 1200000, "1.5tr" -> 1500000, "35.000" -> 35000, "35000" -> 35000
    /// Chỉ nhận chữ số 0-9: \d của Swift khớp cả chữ số Unicode ("３５", "٣٥") mà Double() không đọc được.
    static func amount(_ raw: String) -> Int? {
        let s = strip(raw).replacingOccurrences(of: " ", with: "")
        if let m = s.wholeMatch(of: #/([0-9]+(?:[.,][0-9]+)?)(tr|trieu|m|cu)([0-9]+)?/#) {
            guard var v = Double(m.1.replacingOccurrences(of: ",", with: ".")) else { return nil }
            if let extra = m.3 { v += Double("0." + extra) ?? 0 }
            return whole(v * 1e6)
        }
        if let m = s.wholeMatch(of: #/([0-9]+(?:[.,][0-9]+)?)(k|nghin|ngan|ng|n)/#) {
            return Double(m.1.replacingOccurrences(of: ",", with: ".")).flatMap { whole($0 * 1e3) }
        }
        if s.wholeMatch(of: #/[0-9]{1,3}(?:[.,][0-9]{3})+/#) != nil {
            return Double(s.filter(\.isNumber)).flatMap(whole)
        }
        if s.wholeMatch(of: #/[0-9]+/#) != nil { return Double(s).flatMap(whole) }
        return nil
    }

    /// Số tiền lớn nhất còn nhận: 12 chữ số, bằng bàn phím ở màn hình nhập. Dãy số dài hơn lẫn trong câu là mã giao dịch /
    /// số tài khoản chứ không phải tiền, và Double vượt Int.max mà ép sang Int thì app văng.
    private static let maxAmount = 999_999_999_999.0

    /// Làm tròn thành số đồng; ngoài khoảng 0…maxAmount (kể cả vô cực / không phải số) thì nil.
    private static func whole(_ v: Double) -> Int? {
        let r = v.rounded()
        return r >= 0 && r <= maxAmount ? Int(r) : nil
    }

    /// "35k cafe sáng" -> (35000, "cafe sáng"); bỏ chữ "đồng" Siri hay thêm vào. Không thấy số tiền thì nil.
    static func expense(_ text: String) -> (amount: Int, note: String)? {
        let re = #/(?i)(^|\s)([0-9]+(?:[.,][0-9]+)*)\s*(k|tr|triệu|trieu|củ|cu|m|nghìn|ngàn|nghin|ngan)?([0-9]+)?(?:\s*(?:đồng|dong|vnđ|vnd|đ))?(?![\p{L}\d])/#
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
    /// Hiểu cả tiếng Anh ("200k for gas", "forty five thousand coffee"): dùng trước khi app đang ở tiếng Anh
    /// hoặc câu có chữ tiếng Anh rõ ràng; ngược lại chỉ dùng khi đọc kiểu tiếng Việt không ra số.
    /// Câu có đơn vị tiền tiếng Việt thì luôn đọc kiểu tiếng Việt trước (xem `hasVietnameseUnit`).
    static func spoken(_ text: String) -> (amount: Int, note: String)? {
        if !hasVietnameseUnit(text), (Lang.isEnglish && !looksVietnamese(text)) || looksEnglish(text) { return english(text) ?? vietnamese(text) }
        return vietnamese(text) ?? english(text)
    }

    private static func vietnamese(_ text: String) -> (amount: Int, note: String)? {
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
            if v > 0, v <= maxAmount, best == nil || (strong && !best!.strong) || (strong == best!.strong && v > best!.value) {
                best = (i..<j, v, strong)
            }
            i = j
        }
        // Dưới 1.000 là nghìn; nhân trước rồi mới làm tròn, để "35 rưỡi" / "35,5" ra 35.500 chứ không phải 36.000
        guard let b = best, let amount = whole(b.value < 1000 ? b.value * 1000 : b.value) else { return nil }
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
        let n = w.replacing(#/(đ|₫|vnđ|vnd)$/#, with: "").replacing(#/^(₫|vnđ|vnd)(?=[0-9])/#, with: "")   // cả "₫35.000"
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
        case (.full, .num): return true                        // "50k 2 ly cafe": số lượng sau số tiền không cộng vào số tiền
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
                    pending = nil; last = .none  // không phải .tens: "ba lăm rưỡi" là 35,5 chứ không phải "chục rưỡi" (+5)
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
                else if let p = pending {
                    // Sau một số trơn. Siri viết "hai trăm rưỡi" thành "200 rưỡi", "một triệu rưỡi" thành "1.000.000 rưỡi":
                    // số tròn trăm / nghìn / triệu thì rưỡi là nửa hàng đó; số không tròn từ 1.000 trở lên thì bỏ qua
                    if p >= 1000 {
                        if p.truncatingRemainder(dividingBy: impliedScale(p)) == 0 { pending = p + impliedScale(p) / 2 }
                    } else if p >= 100, p.truncatingRemainder(dividingBy: 100) == 0 { pending = p + 50 }
                    else { pending = p + 0.5 }                // "35 rưỡi", "bảy rưỡi" = 35,5 / 7,5 (nghìn)
                }
                else if group > 0 { group += 0.5 }            // "ba lăm rưỡi" = 35,5
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
            // "ba trăm nghìn hai chục": phần chục tròn sau "nghìn" là hai chục nghìn (320.000), không phải 20 đồng
            if lastScale == 1e3, rem >= 10, rem < 100, rem.truncatingRemainder(dividingBy: 10) == 0 { return total + rem * 1e3 }
            if rem > 0 && rem < 1000 { return total + rem * max(lastScale / 1000, 1) }
            return total + rem
        }
        return total + flush()
    }

    // MARK: Giọng nói tiếng Anh

    /// Chữ chỉ có trong câu tiếng Anh (không trùng chữ tiếng Việt gõ không dấu như "on" = ôn, "ten" = tên, "a" = à)
    private static let englishMarkers: Set<String> = [
        "thousand", "thousands", "million", "millions", "billion", "hundred", "grand", "for", "and", "half",
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "eleven", "twelve", "fifteen", "twenty",
        "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "bucks", "spent", "paid", "mil",
    ]

    /// Câu tiếng Việt (có dấu, hoặc có đơn vị gõ không dấu) thì đọc kiểu tiếng Việt trước, kể cả khi app ở tiếng Anh
    private static func looksVietnamese(_ text: String) -> Bool {
        if text.lowercased() != strip(text) { return true }
        let units: Set<String> = ["nghin", "ngan", "trieu", "tr", "cu", "ty", "muoi", "tram", "ruoi", "nua"]
        return text.split(whereSeparator: \.isWhitespace).contains {
            units.contains($0.lowercased().trimmingCharacters(in: .punctuationCharacters))
        }
    }

    private static func looksEnglish(_ text: String) -> Bool {
        text.split(whereSeparator: \.isWhitespace).contains {
            englishMarkers.contains($0.lowercased().trimmingCharacters(in: .punctuationCharacters))
        }
    }

    /// Câu có đơn vị tiền tiếng Việt thì số tiền được nói kiểu Việt, dù lẫn chữ tiếng Anh (tên hàng, thương hiệu:
    /// "mua Number One 2 triệu", "seven eleven 9 nghìn"). Bộ đọc tiếng Anh không hiểu các đơn vị này: nó đọc "2 triệu" thành 2.000đ
    /// và để lại chữ "triệu" trong ghi chú. (Không có "tram" gõ không dấu: trùng chữ tiếng Anh.)
    /// Trừ khi câu có luôn đơn vị tiếng Anh: lúc đó số tiền nói kiểu Anh, chữ Việt kia là chữ thường ("mười cái bánh 45 thousand").
    private static func hasVietnameseUnit(_ text: String) -> Bool {
        let units: Set<String> = ["nghìn", "ngàn", "triệu", "tỷ", "tỉ", "trăm", "mươi", "mười", "chục", "rưỡi", "củ",
                                  "nghin", "ngan", "trieu", "muoi", "chuc", "ruoi"]
        let english: Set<String> = ["thousand", "thousands", "million", "millions", "billion", "hundred"]
        let words = text.split(whereSeparator: \.isWhitespace).map {
            $0.lowercased().precomposedStringWithCanonicalMapping.trimmingCharacters(in: .punctuationCharacters)
        }
        return words.contains(where: units.contains) && !words.contains(where: english.contains)
    }

    /// Chữ thừa ở đầu / cuối ghi chú: "200k for gas" -> "gas", "lunch for 45k" -> "lunch"
    private static let englishFillers: Set<String> = [
        "for", "on", "at", "of", "and", "spent", "paid", "dong", "dongs", "vnd", "vnđ", "đ", "₫",
    ]

    private enum ETok {
        /// word: số viết bằng chữ ("five"); số bằng chữ số thì word = false
        case num(Double, word: Bool)
        case tens(Double), hundred, scale(Double), article, and, half, full(Double), end

        var isStrong: Bool {
            switch self {
            case .scale, .full, .hundred, .tens: true
            case .num(let v, _): v >= 10
            default: false
            }
        }
    }

    private static let englishWords: [String: ETok] = [
        "zero": .num(0, word: true), "one": .num(1, word: true), "two": .num(2, word: true), "three": .num(3, word: true),
        "four": .num(4, word: true), "five": .num(5, word: true), "six": .num(6, word: true), "seven": .num(7, word: true),
        "eight": .num(8, word: true), "nine": .num(9, word: true), "ten": .num(10, word: true), "eleven": .num(11, word: true),
        "twelve": .num(12, word: true), "thirteen": .num(13, word: true), "fourteen": .num(14, word: true),
        "fifteen": .num(15, word: true), "sixteen": .num(16, word: true), "seventeen": .num(17, word: true),
        "eighteen": .num(18, word: true), "nineteen": .num(19, word: true),
        "twenty": .tens(20), "thirty": .tens(30), "forty": .tens(40), "fourty": .tens(40), "fifty": .tens(50),
        "sixty": .tens(60), "seventy": .tens(70), "eighty": .tens(80), "ninety": .tens(90),
        "hundred": .hundred,
        "thousand": .scale(1e3), "thousands": .scale(1e3), "grand": .scale(1e3), "k": .scale(1e3),
        "million": .scale(1e6), "millions": .scale(1e6), "mil": .scale(1e6), "m": .scale(1e6),
        "billion": .scale(1e9), "bn": .scale(1e9),
        "a": .article, "an": .article, "and": .and, "half": .half,
        "dong": .end, "dongs": .end, "vnd": .end, "vnđ": .end, "đ": .end, "₫": .end,
    ]

    private static func etok(_ raw: String) -> ETok? {
        var w = raw.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if w.hasPrefix("$") { w.removeFirst() }
        if let t = englishWords[w] { return t }
        let n = w.replacing(#/(đ|₫|vnđ|vnd)$/#, with: "")
        if n.wholeMatch(of: #/[0-9]{1,3}(?:,[0-9]{3})+/#) != nil || n.wholeMatch(of: #/[0-9]{1,3}(?:\.[0-9]{3})+/#) != nil {
            return .num(Double(n.filter { $0.isASCII && $0.isNumber })!, word: false)   // "45,000", "35.000"
        }
        if let m = n.wholeMatch(of: #/([0-9]+)(?:[.,]([0-9]+))?/#) {
            return .num(Double(String(m.1) + (m.2.map { "." + $0 } ?? ""))!, word: false)   // "45", "1.2"
        }
        if n.contains(where: \.isLetter), let a = amount(n) { return .full(Double(a)) }   // "200k", "1.2m"
        return nil
    }

    /// Từ sau có nối tiếp được cụm số đang đọc không ("forty" + "five" được, "two" + "five" thì không).
    private static func continues(_ a: ETok, _ b: ETok) -> Bool {
        switch (a, b) {
        case (.full, .end), (.num, .end), (.tens, .end), (.hundred, .end), (.scale, .end): return true
        case (_, .full), (.full, _), (.end, _): return false
        case let (.tens, .num(v, word)): return word && v >= 1 && v <= 9    // "forty five"
        case (.num, .num), (.num, .tens), (.tens, .tens): return false
        case (.hundred, .num), (.hundred, .tens), (.scale, .num), (.scale, .tens), (.and, .num), (.and, .tens): return true
        case (_, .num), (_, .tens): return false
        case (.num, .hundred), (.tens, .hundred), (.article, .hundred): return true
        case (_, .hundred): return false
        case (.num, .scale), (.tens, .scale), (.hundred, .scale), (.article, .scale), (.half, .scale): return true
        case (_, .scale): return false
        case (.num, .and), (.tens, .and), (.hundred, .and), (.scale, .and): return true
        case (_, .and): return false
        case (.and, .article), (.half, .article): return true                // "and a half", "half a million"
        case (_, .article): return false
        case (.article, .half), (.and, .half): return true
        default: return false
        }
    }

    private static func english(_ text: String) -> (amount: Int, note: String)? {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let toks = words.map(etok)
        var best: (range: Range<Int>, value: Double, strong: Bool)?
        var i = 0
        while i < toks.count {
            guard let t = toks[i] else { i += 1; continue }
            switch t {
            case .scale, .and, .end: i += 1; continue    // "k", "thousand" phải có số đứng trước
            default: break
            }
            var j = i + 1
            while j < toks.count, let u = toks[j], continues(toks[j - 1]!, u) {
                j += 1
                if case .end = u { break }
            }
            // Không để "and" / "a" thừa ở cuối cụm ("35k and a coffee")
            while j > i + 1, let last = toks[j - 1] {
                if case .and = last { j -= 1 } else if case .article = last { j -= 1 } else { break }
            }
            let run = Array(toks[i..<j].compactMap { $0 })
            let v = isLoneEnglish(run) ? 0 : englishValue(run)
            let strong = run.contains { $0.isStrong }
            if v > 0, v <= maxAmount, best == nil || (strong && !best!.strong) || (strong == best!.strong && v > best!.value) {
                best = (i..<j, v, strong)
            }
            i = j
        }
        guard let b = best, let amount = whole(b.value < 1000 ? b.value * 1000 : b.value) else { return nil }   // như bản tiếng Việt
        var note = words.enumerated().filter { !b.range.contains($0.offset) }.map(\.element)
        let isFiller = { (w: String) in englishFillers.contains(w.lowercased().trimmingCharacters(in: .punctuationCharacters)) }
        while let f = note.first, isFiller(f) { note.removeFirst() }
        while let l = note.last, isFiller(l) { note.removeLast() }
        return (amount, note.joined(separator: " "))
    }

    /// "one", "a", "half" đứng một mình là chữ thường ("one coffee"), không phải số tiền.
    private static func isLoneEnglish(_ run: [ETok]) -> Bool {
        guard run.count == 1 else { return false }
        switch run[0] {
        case .num(let v, true): return v < 10
        case .article, .half: return true
        default: return false
        }
    }

    /// Đọc một cụm số tiếng Anh. Phần lẻ sau đơn vị hiểu theo kiểu nói tắt như tiếng Việt:
    /// "a million two" = 1,2 triệu, "one million two hundred" = 1,2 triệu (không ai trả 200đ lẻ).
    private static func englishValue(_ toks: [ETok]) -> Double {
        enum Last { case none, num, tens, hundred, scale }
        var total = 0.0, group = 0.0, lastScale = 0.0
        var halfNext = false, last = Last.none
        /// Một chữ số đứng ngay sau đơn vị ("a million two")
        var digitAfterScale = false

        loop: for (k, t) in toks.enumerated() {
            switch t {
            case .num(let v, _):
                digitAfterScale = last == .scale && v < 10
                if last == .scale { group = v } else { group += v }
                last = .num
            case .tens(let v):
                digitAfterScale = false
                group += v; last = .tens
            case .hundred:
                digitAfterScale = false
                group = (group == 0 ? 1 : group) * 100; last = .hundred
            case .scale(let s):
                var g = group == 0 ? 1 : group
                if halfNext { g *= 0.5; halfNext = false }
                total += g * s
                group = 0; lastScale = s; last = .scale; digitAfterScale = false
            case .and:
                continue
            case .article:
                if k + 1 < toks.count, case .half = toks[k + 1] { continue }   // "and a half"
                group += 1; last = .num
            case .half:
                if last == .scale && group == 0 { total += lastScale / 2 }       // "a million and a half"
                else if group > 0 { group += 0.5 }                              // "two and a half million"
                else { halfNext = true }                                         // "half a million"
            case .full(let v):
                total += v; group = 0; last = .scale; lastScale = v >= 1e6 ? 1e6 : 1e3
            case .end:
                break loop
            }
        }
        if lastScale > 0 && group > 0 {
            if digitAfterScale { return total + group * lastScale / 10 }
            if group < 1000 { return total + group * max(lastScale / 1000, 1) }
        }
        return total + group
    }
}

// MARK: Ngày và quẹt thẻ

extension QuickParse {
    /// Ngày nói trong câu ("hôm qua", "tối qua", "thứ hai", "ngày 12") và "quẹt thẻ": bỏ các chữ đó ra khỏi câu, phần còn lại
    /// mới đưa cho `spoken` / `expense` đọc số tiền, để "thứ hai" / "ngày 12" không thành số tiền hay nằm lại trong ghi chú.
    /// date: nil = bây giờ. Không bao giờ ra giờ ở tương lai ("tối nay" lúc 10 giờ sáng = bây giờ).
    static func when(_ text: String, now: Date = Date(), calendar cal: Calendar = .current) -> (rest: String, date: Date?, credit: Bool) {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let n = words.map { $0.lowercased().precomposedStringWithCanonicalMapping.trimmingCharacters(in: .punctuationCharacters) }
        let accented = text.lowercased() != strip(text)
        var drop = Set<Int>()

        /// Câu gõ không dấu cũng nhận ("hom qua"); chữ có dấu thì phải đúng dấu ("tôi qua" không phải "tối qua")
        func eq(_ i: Int, _ w: String) -> Bool {
            n.indices.contains(i) && !drop.contains(i) && (n[i] == w || (!accented && n[i] == strip(w)))
        }
        /// Chữ ngay sau còn nối được vào số đứng trước ("thứ hai trăm", "ngày 5 nghìn") thì đó là số tiền, không phải ngày
        func continuesNumber(_ i: Int, _ v: Double, word: Bool) -> Bool {
            guard n.indices.contains(i), let t = tok(n[i], accented: accented) else { return false }
            return !breaks(.num(v, word: word, tail: false), t)
        }
        func ago(_ k: Int, hour: Int? = nil) -> Date? {
            guard let d = cal.date(byAdding: .day, value: -k, to: now) else { return nil }
            return hour.flatMap { cal.date(bySettingHour: $0, minute: 0, second: 0, of: d) } ?? d
        }
        func today(hour: Int?) -> Date? {
            guard let h = hour, let d = cal.date(bySettingHour: h, minute: 0, second: 0, of: now), d < now else { return nil }
            return d
        }
        /// "thứ hai tuần trước" / "thứ hai tuần rồi"
        func lastWeek(_ i: Int) -> Bool { eq(i, "tuần") && (eq(i + 1, "trước") || eq(i + 1, "rồi")) }
        /// Thứ gần nhất đã qua (hôm nay đúng thứ đó thì là hôm nay), lùi thêm một tuần nếu sau đó nói "tuần trước".
        /// wd theo Calendar: 1 = chủ nhật … 7 = thứ bảy
        func weekday(_ wd: Int, after i: Int) -> Date? {
            let k = (cal.component(.weekday, from: now) - wd + 7) % 7 + (lastWeek(i) ? 7 : 0)
            return k == 0 ? nil : ago(k)
        }
        /// Ngày d của tháng này; d còn ở phía trước thì là tháng trước (tháng ngắn hơn thì lấy ngày cuối tháng)
        func day(_ d: Int) -> Date? {
            let cur = cal.component(.day, from: now)
            if d == cur { return nil }
            guard let base = d > cur ? cal.date(byAdding: .month, value: -1, to: now) : now,
                  let days = cal.range(of: .day, in: .month, for: base) else { return nil }
            return cal.date(byAdding: .day, value: min(d, days.count) - cal.component(.day, from: base), to: base)
        }
        func dayNumber(_ i: Int) -> Int? {
            guard n.indices.contains(i), !drop.contains(i), n[i].allSatisfy({ $0.isASCII && $0.isNumber }), let d = Int(n[i]),
                  (1...31).contains(d), !continuesNumber(i + 1, Double(d), word: false) else { return nil }
            return d
        }

        // Quẹt thẻ: "quẹt thẻ", "bằng thẻ", "thẻ tín dụng", "trả bằng thẻ tín dụng"
        var credit = false
        for i in n.indices where !credit {
            var lo = i, hi = i
            if eq(i, "thẻ") {
                let tinDung = eq(i + 1, "tín") && eq(i + 2, "dụng")
                guard eq(i - 1, "quẹt") || eq(i - 1, "bằng") || tinDung else { continue }
                if tinDung { hi = i + 2 }
                while ["quẹt", "bằng", "dùng"].contains(where: { eq(lo - 1, $0) }) { lo -= 1 }
                if eq(lo - 1, "trả") { lo -= 1 } else if eq(lo - 1, "toán") && eq(lo - 2, "thanh") { lo -= 2 }
            } else if Lang.isEnglish, n[i] == "card" {
                guard i > 0, ["credit", "by", "with", "on", "my"].contains(n[i - 1]) else { continue }
                while lo > 0, ["credit", "my", "a", "the"].contains(n[lo - 1]) { lo -= 1 }
                while lo > 0, ["by", "with", "on", "using", "paid"].contains(n[lo - 1]) { lo -= 1 }
            } else { continue }
            credit = true
            drop.formUnion(lo...hi)
        }

        // Ngày: lấy cụm đầu tiên tìm thấy
        let parts: [String: Int] = ["sáng": 8, "trưa": 12, "chiều": 16, "tối": 20, "đêm": 22]
        let weekdays: [String: Int] = ["hai": 2, "ba": 3, "tư": 4, "năm": 5, "sáu": 6, "bảy": 7, "bẩy": 7]
        let ordinals = ["lần", "người", "đứa", "con", "cái", "ly", "phần", "hạng", "tập", "đợt", "kỳ", "kì", "giải"]
        var found: (lo: Int, hi: Int, date: Date?)?
        for i in n.indices where found == nil && !drop.contains(i) {
            // Buổi + qua / nay chỉ nhận khi có dấu: "toi qua", "sang qua" không dấu có thể là "tôi qua", "sang qua"
            if accented, let h = parts[n[i]] {
                if eq(i + 1, "hôm") && eq(i + 2, "qua") { found = (i, i + 2, ago(1, hour: h)) }
                else if eq(i + 1, "qua") { found = (i, i + 1, ago(1, hour: h)) }
                else if eq(i + 1, "hôm") && eq(i + 2, "kia") { found = (i, i + 2, ago(2, hour: h)) }
                else if eq(i + 1, "nay") { found = (i, i + 1, today(hour: h)) }
                else if eq(i + 1, "hôm") && eq(i + 2, "nay") { found = (i, i + 2, today(hour: h)) }
            } else if eq(i, "hôm") {
                if eq(i + 1, "qua") { found = (i, i + 1, ago(1)) }
                else if eq(i + 1, "kia") { found = (i, i + 1, ago(2)) }
                else if eq(i + 1, "nay") { found = (i, i + 1, nil) }
                else if let d = dayNumber(i + 1) { found = (i, i + 1, day(d)) }
            } else if eq(i, "ngày"), let d = dayNumber(i + 1) {
                found = (i, i + 1, day(d))
            } else if eq(i, "thứ"), n.indices.contains(i + 1), !drop.contains(i + 1), !ordinals.contains(where: { eq(i - 1, $0) }) {
                // "thứ hai" chỉ khi có dấu ("thu hai trieu" là thu hai triệu); "thứ 2" / "thu 2" thì nhận cả
                let w = n[i + 1]
                if accented, let wd = weekdays[w], !continuesNumber(i + 2, Double(wd), word: true) {
                    found = (i, i + 1, weekday(wd, after: i + 2))
                } else if w.count == 1, let wd = Int(w), (2...7).contains(wd), !continuesNumber(i + 2, Double(wd), word: false) {
                    found = (i, i + 1, weekday(wd, after: i + 2))
                }
            } else if eq(i, "chủ") && eq(i + 1, "nhật") {
                found = (i, i + 1, weekday(1, after: i + 2))
            } else if Lang.isEnglish {
                let days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
                let times = ["morning": 8, "afternoon": 16, "evening": 20]
                let next = i + 1 < n.count ? n[i + 1] : ""
                switch n[i] {
                case "yesterday": found = (i, i, ago(1))
                case "today": found = (i, i, nil)
                case "tonight": found = (i, i, today(hour: 20))
                case "last" where next == "night": found = (i, i + 1, ago(1, hour: 20))
                case "this" where times[next] != nil: found = (i, i + 1, today(hour: times[next]))
                default:
                    // "on monday", "last monday" = thứ hai vừa qua
                    if let k = days.firstIndex(of: n[i]) {
                        found = (i > 0 && ["on", "last"].contains(n[i - 1]) ? i - 1 : i, i, weekday(k + 1, after: n.count))
                    }
                }
            }
        }

        var date: Date?
        if var f = found {
            if n[f.lo] != "hôm" && eq(f.lo - 1, "hôm") { f.lo -= 1 }   // "hôm thứ hai"
            if eq(f.lo - 1, "vào") { f.lo -= 1 }                       // "vào tối qua", "vào hôm thứ hai"
            if lastWeek(f.hi + 1) { f.hi += 2 }
            drop.formUnion(f.lo...f.hi)
            date = f.date
        }
        let rest = words.enumerated().filter { !drop.contains($0.offset) }.map(\.element).joined(separator: " ")
        return (rest, date, credit)
    }
}
